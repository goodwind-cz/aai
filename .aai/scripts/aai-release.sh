#!/usr/bin/env bash
# AAI release-cut engine — one deterministic command for /aai-release.
#
# Rolls the repo root's CHANGELOG.md `[unreleased]` blocks into a versioned
# section, commits in an isolated temporary worktree, pushes a release branch,
# and finishes a bound release PR — behind an operator gate with a safe default
# (plan-only) mode. On merge to main, CI creates the annotated tag and
# publishes the GitHub release.
#
# Usage (run from anywhere inside the target repo):
#   ./.aai/scripts/aai-release.sh                       # plan-only (default-safe), no writes
#   ./.aai/scripts/aai-release.sh --dry-run             # same as bare invocation, explicit
#   ./.aai/scripts/aai-release.sh --version v1.2.3      # verbatim version (any scheme)
#   ./.aai/scripts/aai-release.sh --confirm             # CUT: merge, verify, clean up
#   ./.aai/scripts/aai-release.sh --confirm --no-remote # CUT, skip push + gh pr create
#   AAI_RELEASE_DATE=2026-07-20 ./.aai/scripts/aai-release.sh --dry-run
#                                                        # pin the CalVer date (tests)
#   AAI_RELEASE_NO_REMOTE=1 ./.aai/scripts/aai-release.sh --confirm
#                                                        # env twin of --no-remote
#
# Default version (no --version): CalVer `vYYYY.MM.DD`, from AAI_RELEASE_DATE
# (expected YYYY-MM-DD) if set/non-empty, else the real UTC clock.
#
# Exit codes: 0 success (plan or cut) | 1 bad argument | 10 not a git repo |
#   11 no CHANGELOG.md | 12 malformed [unreleased] region | 13 no rollable
#   [unreleased] entries (absent/empty) | 15 tag already exists (cut path) |
#   16 gh absent/unauthenticated (when remote PR creation is attempted) |
#   8 finish pending in a merge queue (resume) | 20 finish refused.
set -euo pipefail

VERSION=""
DRY_RUN=0
CONFIRM=0
NO_REMOTE=0
[[ "${AAI_RELEASE_NO_REMOTE:-0}" == "1" ]] && NO_REMOTE=1

usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)        VERSION="${2:?--version needs a value}"; shift 2 ;;
    --dry-run)         DRY_RUN=1; shift ;;
    --confirm|--yes)   CONFIRM=1; shift ;;
    --no-remote)        NO_REMOTE=1; shift ;;
    -h|--help)          usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ "$DRY_RUN" == "1" ]]; then
  CONFIRM=0
fi

OUT=""
NOTES=""
PUSH_LOG=""
PR_OUT=""
WT_DIR=""
cleanup() {
  [[ -n "$OUT" && -f "$OUT" ]] && rm -f "$OUT"
  [[ -n "$NOTES" && -f "$NOTES" ]] && rm -f "$NOTES"
  [[ -n "$PUSH_LOG" && -f "$PUSH_LOG" ]] && rm -f "$PUSH_LOG"
  [[ -n "$PR_OUT" && -f "$PR_OUT" ]] && rm -f "$PR_OUT"
  if [[ -n "$WT_DIR" && -d "$WT_DIR" ]]; then
    git -C "$ROOT" worktree remove --force "$WT_DIR" >/dev/null 2>&1 || rm -rf "$WT_DIR"
  fi
  true
}
trap cleanup EXIT

# --- unlogged-PR precondition
unlogged_prs() {
  local online=""
  [[ "${GH_BLOCK:-1}" == "0" && "$NO_REMOTE" != "1" ]] && git -C "$ROOT" remote get-url origin >/dev/null 2>&1 && online="--online"
  node "$(dirname "$0")/release-finish.mjs" --root "$ROOT" --audit "$1" $online
}

# --- ALWAYS-checked preconditions: not a git repo / no CHANGELOG --
if ! ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  echo "REFUSED: not a git repository (cwd=$(pwd))." >&2
  exit 10
fi
CHANGELOG="$ROOT/CHANGELOG.md"
if [[ ! -f "$CHANGELOG" ]]; then
  echo "REFUSED: no CHANGELOG.md at repo root: $CHANGELOG" >&2
  exit 11
fi

DIRTY=0
[[ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]] && DIRTY=1

# --- Version resolution
if [[ -z "$VERSION" ]]; then
  if [[ -n "${AAI_RELEASE_DATE:-}" ]]; then
    VERSION="v${AAI_RELEASE_DATE//-/.}"
  else
    VERSION="$(date -u +v%Y.%m.%d)"
  fi
fi

# Remote confirm uses the shared durable finish sequence before parsing caller notes.
if [[ "$CONFIRM" == "1" && "$NO_REMOTE" != "1" ]]; then
  if ! command -v node >/dev/null 2>&1; then
    echo "REFUSED: missing-node — Node.js is required for release finish" >&2
    echo "Resume: bash \"$0\" --version $VERSION --confirm" >&2
    exit 20
  fi
  exec node "$(dirname "$0")/release-finish.mjs" --root "$ROOT" --version "$VERSION" --confirm
fi

# --- CHANGELOG rollup transform
OUT="$(mktemp "$ROOT/.aai-release-changelog.XXXXXX")"
NOTES="$(mktemp "${TMPDIR:-/tmp}/aai-release-notes.XXXXXX")"

perform_rollup() {
  local in_file="$1" out_file="$2" notes_file="$3"
  local rc=0
  awk -v version="$VERSION" -v outfile="$out_file" -v notesfile="$notes_file" -f - "$in_file" <<'AWKPROG' || rc=$?
{ L[NR] = $0 }
END {
  n = NR
  first_heading = 0
  for (i = 1; i <= n; i++) {
    if (L[i] ~ /^## \[/) { first_heading = i; break }
  }
  if (first_heading == 0) { print "ABSENT" > "/dev/stderr"; exit 5 }

  m = 0
  for (i = first_heading; i <= n; i++) {
    if (L[i] ~ /^## /) { m++; head_idx[m] = i }
  }
  head_idx[m + 1] = n + 1

  malformed = 0
  entry_count = 0
  for (k = 1; k <= m; k++) {
    hi = head_idx[k]
    hline = L[hi]
    body_start = hi + 1
    body_end = head_idx[k + 1] - 1
    if (hline ~ /^## \[unreleased\] — /) {
      type[k] = "ENTRY"
      entry_count++
    } else if (hline ~ /^## \[unreleased\]/) {
      if (hline ~ /^## \[unreleased\][ \t]*$/) {
        allblank = 1
        for (b = body_start; b <= body_end; b++) {
          if (L[b] !~ /^[ \t]*$/) { allblank = 0; break }
        }
        if (allblank) { type[k] = "SCAFFOLD" } else { type[k] = "MALFORMED"; malformed = 1 }
      } else {
        type[k] = "MALFORMED"; malformed = 1
      }
    } else {
      type[k] = "OTHER"
    }
  }

  if (malformed) { print "MALFORMED" > "/dev/stderr"; exit 4 }
  if (entry_count == 0) { print "EMPTY" > "/dev/stderr"; exit 5 }

  first_entry_hi = 0
  for (k = 1; k <= m; k++) { if (type[k] == "ENTRY") { first_entry_hi = head_idx[k]; break } }

  for (i = 1; i < first_heading; i++) print L[i] > outfile

  nc = 0
  for (k = 1; k <= m; k++) {
    hi = head_idx[k]
    body_end = head_idx[k + 1] - 1
    if (hi == first_entry_hi) {
      print "## [unreleased]" > outfile
      print "" > outfile
    }
    if (type[k] == "ENTRY") {
      line = L[hi]
      pos = index(line, "[unreleased]")
      newline = substr(line, 1, pos - 1) "[" version "]" substr(line, pos + length("[unreleased]"))
      print newline > outfile
      nc++; NL[nc] = newline
    } else if (type[k] == "SCAFFOLD") {
      continue
    } else {
      print L[hi] > outfile
    }
    for (b = hi + 1; b <= body_end; b++) {
      print L[b] > outfile
      if (type[k] == "ENTRY") { nc++; NL[nc] = L[b] }
    }
  }

  s = 1; e = nc
  while (s <= e && NL[s] ~ /^[ \t]*$/) s++
  while (e >= s && NL[e] ~ /^[ \t]*$/) e--
  for (i = s; i <= e; i++) print NL[i] > notesfile
}
AWKPROG
  return $rc
}

rollup_rc=0
perform_rollup "$CHANGELOG" "$OUT" "$NOTES" || rollup_rc=$?

case "$rollup_rc" in
  0) : ;;
  4) echo "REFUSED: malformed [unreleased] heading in CHANGELOG.md (a '## [unreleased]' line has unexpected trailing text or a stray heading-only body) — never silently dropping entries." >&2
     exit 12 ;;
  5) echo "REFUSED: no rollable [unreleased] entries in CHANGELOG.md (absent or empty) — nothing to release." >&2
     exit 13 ;;
  *) echo "REFUSED: could not parse CHANGELOG.md (rc=$rollup_rc)." >&2
     exit 12 ;;
esac

if [[ -s "$CHANGELOG" ]]; then
  last_byte="$(tail -c1 "$CHANGELOG" | od -An -tx1 2>/dev/null | tr -d ' \n')"
  if [[ "$last_byte" != "0a" ]]; then
    printf '%s' "$(cat "$OUT")" > "$OUT"
  fi
fi

TAG_EXISTS=0
git -C "$ROOT" rev-parse -q --verify "refs/tags/$VERSION" >/dev/null 2>&1 && TAG_EXISTS=1

GH_BLOCK=0
GH_REASON=""
if [[ "$NO_REMOTE" != "1" ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    GH_BLOCK=1; GH_REASON="gh CLI not found on PATH"
  elif ! gh auth status >/dev/null 2>&1; then
    GH_BLOCK=1; GH_REASON="gh CLI not authenticated (gh auth status failed)"
  fi
fi

TARGET_BRANCH="$(git -C "$ROOT" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || true)"
if [[ -z "$TARGET_BRANCH" ]]; then
  if git -C "$ROOT" rev-parse -q --verify refs/remotes/origin/main >/dev/null 2>&1 || git -C "$ROOT" rev-parse -q --verify refs/heads/main >/dev/null 2>&1; then
    TARGET_BRANCH="main"
  else
    TARGET_BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")"
    [[ "$TARGET_BRANCH" != "HEAD" ]] || TARGET_BRANCH="main"
  fi
fi

if [[ "$CONFIRM" != "1" ]]; then
  # --- PLAN-ONLY (bare invocation or --dry-run): print the plan, write nothing.
  echo "## aai-release (plan) — no files changed"
  echo "- Resolved version: $VERSION"
  echo "- Tag to create:    $VERSION (annotated)"
  echo "- Commit message:   chore(release): $VERSION"
  echo
  echo "## CHANGELOG rollup (would write)"
  grep -n -F "## [$VERSION] — " "$OUT" | sed 's/^/  /' || true
  echo "  ## [unreleased]   <- fresh scaffold inserted above the rolled section"
  echo
  echo "## Release notes preview (title=$VERSION)"
  sed 's/^/  /' "$NOTES"
  echo
  echo "## Preconditions"
  blocked=0
  [[ "$TAG_EXISTS" == "1" ]] && { echo "- would block: tag $VERSION already exists"; blocked=1; }
  [[ "$GH_BLOCK" == "1" ]] && { echo "- would block (publish path): $GH_REASON"; blocked=1; }
  UNLOGGED="$(unlogged_prs "$NOTES")"
  if [[ -n "$UNLOGGED" ]]; then
    echo "- NAMED (not blocking): $(printf '%s\n' "$UNLOGGED" | wc -l | tr -d ' ') PR(s) merged since the previous tag have no matching section in these notes:"
    printf '%s\n' "$UNLOGGED" | sed 's/^/    - /'
    echo "    Add a '## [unreleased] — <title>' section for each, or confirm they are covered under another title."
  fi
  if [[ "$blocked" == "0" && -z "$UNLOGGED" ]]; then
    echo "- none — ready to cut with --confirm"
  elif [[ "$blocked" == "0" ]]; then
    echo "- confirm will refuse until the NAMED missing release notes are resolved"
  fi
  echo
  echo "## Remote"
  if [[ "$NO_REMOTE" == "1" ]]; then
    echo "- --no-remote / AAI_RELEASE_NO_REMOTE=1: push + gh pr create would be SKIPPED"
  else
    echo "- push (branch chore/release-$VERSION) and 'gh pr create' (base $TARGET_BRANCH) WOULD run against this repo's remote; CI will tag and publish upon merge"
  fi
  exit 0
fi

# --- CONFIRM (the cut): fail-closed
if [[ "$TAG_EXISTS" == "1" ]]; then
  echo "REFUSED: tag $VERSION already exists." >&2
  exit 15
fi
if [[ "$GH_BLOCK" == "1" ]]; then
  echo "REFUSED: $GH_REASON (publish path) — dry-run works offline; pass --no-remote/AAI_RELEASE_NO_REMOTE=1 to skip publish, or fix gh auth." >&2
  exit 16
fi

UNLOGGED_CUT="$(unlogged_prs "$NOTES")"
if [[ -n "$UNLOGGED_CUT" ]]; then
  echo "REFUSED: missing-notes — $UNLOGGED_CUT" >&2
  echo "Resume: bash \"$0\" --version $VERSION --confirm --no-remote" >&2
  exit 20
fi

# --- CUT IN TEMPORARY WORKTREE
RELEASE_BRANCH="chore/release-$VERSION"

BASE_REF=""
if git -C "$ROOT" rev-parse -q --verify "refs/remotes/origin/$TARGET_BRANCH" >/dev/null 2>&1; then
  BASE_REF="origin/$TARGET_BRANCH"
elif git -C "$ROOT" rev-parse -q --verify "refs/heads/$TARGET_BRANCH" >/dev/null 2>&1; then
  BASE_REF="$TARGET_BRANCH"
else
  BASE_REF="HEAD"
fi

if git -C "$ROOT" rev-parse -q --verify "refs/heads/$RELEASE_BRANCH" >/dev/null 2>&1; then
  EXISTING_SUBJECT="$(git -C "$ROOT" log -1 --format=%s "refs/heads/$RELEASE_BRANCH" 2>/dev/null || true)"
  if [[ "$EXISTING_SUBJECT" == "chore(release): $VERSION"* ]] || git -C "$ROOT" merge-base --is-ancestor "$RELEASE_BRANCH" "$BASE_REF" 2>/dev/null; then
    git -C "$ROOT" branch -D "$RELEASE_BRANCH" >/dev/null 2>&1 || true
  else
    echo "REFUSED: branch $RELEASE_BRANCH already exists with unmerged commits ($EXISTING_SUBJECT)." >&2
    exit 12
  fi
fi

WT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-release-wt.XXXXXX")"
git -C "$ROOT" worktree add -q -b "$RELEASE_BRANCH" "$WT_DIR" "$BASE_REF"

WT_OUT="$(mktemp "${TMPDIR:-/tmp}/aai-release-wt-out.XXXXXX")"
WT_NOTES="$(mktemp "${TMPDIR:-/tmp}/aai-release-wt-notes.XXXXXX")"
wt_rc=0
perform_rollup "$WT_DIR/CHANGELOG.md" "$WT_OUT" "$WT_NOTES" || wt_rc=$?
if [[ "$wt_rc" != "0" ]]; then
  rm -f "$WT_OUT" "$WT_NOTES"
  git -C "$ROOT" worktree remove --force "$WT_DIR" >/dev/null 2>&1 || rm -rf "$WT_DIR"
  echo "REFUSED: base branch has no rollable entries in CHANGELOG.md (rc=$wt_rc)." >&2
  exit 13
fi
mv -f "$WT_OUT" "$WT_DIR/CHANGELOG.md"
cp -f "$WT_NOTES" "$NOTES"
rm -f "$WT_NOTES"
mkdir -p "$WT_DIR/docs/ai"
{
  echo "# AAI Version"
  echo
  echo "- Version: $VERSION"
  echo
  echo "Notes:"
  echo "- Written by the release engines (aai-release.sh / aai-release.ps1) at each cut;"
  echo "  consumed by \`.aai/scripts/aai-sync.*\` to stamp \`Template version:\` into the"
  echo "  target project's \`.aai/system/AAI_PIN.md\`. Do not edit by hand."
} > "$WT_DIR/docs/ai/AAI_VERSION.md"

git -C "$WT_DIR" add -- CHANGELOG.md docs/ai/AAI_VERSION.md
git -C "$WT_DIR" commit -q -m "chore(release): $VERSION"
RELEASE_SHA="$(git -C "$WT_DIR" rev-parse HEAD)"

# Remove worktree immediately
git -C "$ROOT" worktree remove --force "$WT_DIR" >/dev/null 2>&1 || rm -rf "$WT_DIR"
WT_DIR=""

echo "## aai-release — cut complete"
echo "- Version: $VERSION"
echo "- Commit:  $(git -C "$ROOT" rev-parse --short "$RELEASE_SHA")"
echo "- Release branch: $RELEASE_BRANCH ($RELEASE_SHA)"

echo "- Remote:  SKIPPED (--no-remote/AAI_RELEASE_NO_REMOTE=1) — release branch $RELEASE_BRANCH created locally at $RELEASE_SHA"

exit 0
