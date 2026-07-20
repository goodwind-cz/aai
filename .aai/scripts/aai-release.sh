#!/usr/bin/env bash
# AAI release-cut engine — one deterministic command for /aai-release.
#
# Rolls the repo root's CHANGELOG.md `[unreleased]` blocks into a versioned
# section, commits, creates an annotated tag, publishes a GitHub release with
# notes derived from that section, and pushes — behind an operator gate with
# a safe default (plan-only) mode. Works identically releasing AAI itself or
# a downstream project that has the AAI layer deployed: its only inputs are
# the repo root, its CHANGELOG.md, and its git/gh remote.
#
# Usage (run from anywhere inside the target repo):
#   ./.aai/scripts/aai-release.sh                       # plan-only (default-safe), no writes
#   ./.aai/scripts/aai-release.sh --dry-run             # same as bare invocation, explicit
#   ./.aai/scripts/aai-release.sh --version v1.2.3      # verbatim version (any scheme)
#   ./.aai/scripts/aai-release.sh --confirm             # CUT: roll+commit+tag(+push+publish)
#   ./.aai/scripts/aai-release.sh --confirm --no-remote # CUT, skip push + gh release create
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
#   [unreleased] entries (absent/empty) | 14 dirty working tree (cut path) |
#   15 tag already exists (cut path) | 16 gh absent/unauthenticated (publish
#   path only; dry-run works offline).
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

# D4: --dry-run always wins over --confirm (safe by construction).
if [[ "$DRY_RUN" == "1" ]]; then
  CONFIRM=0
fi

OUT=""
NOTES=""
cleanup() {
  # A trap handler's own final exit status would otherwise silently replace
  # the script's real exit code (bash trap semantics) — every path ends in
  # `|| true` so the caller always sees the code the script exited with.
  [[ -n "$OUT" && -f "$OUT" ]] && rm -f "$OUT"
  [[ -n "$NOTES" && -f "$NOTES" ]] && rm -f "$NOTES"
  true
}
trap cleanup EXIT

# --- D6 ALWAYS-checked preconditions (a)/(b): not a git repo / no CHANGELOG --
if ! ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  echo "REFUSED: not a git repository (cwd=$(pwd))." >&2
  exit 10
fi
CHANGELOG="$ROOT/CHANGELOG.md"
if [[ ! -f "$CHANGELOG" ]]; then
  echo "REFUSED: no CHANGELOG.md at repo root: $CHANGELOG" >&2
  exit 11
fi

# Snapshot the dirty-tree state NOW, before this script creates its own temp
# file inside $ROOT below — a later check would see our own scratch file and
# falsely report a clean tree as dirty.
DIRTY=0
[[ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]] && DIRTY=1

# --- D3: version resolution (verbatim else CalVer, clock-controllable) ------
if [[ -z "$VERSION" ]]; then
  if [[ -n "${AAI_RELEASE_DATE:-}" ]]; then
    VERSION="v${AAI_RELEASE_DATE//-/.}"
  else
    VERSION="$(date -u +v%Y.%m.%d)"
  fi
fi

# --- D1: CHANGELOG rollup transform (line-surgical, byte-preserved) --------
# Full-template mktemp (no `-t <bare>`): the CHANGELOG's own temp is created
# IN ITS OWN DIRECTORY so the final `mv` below is an atomic same-filesystem
# rename. The notes temp lives under TMPDIR (consumed only by `gh`, no
# atomicity requirement).
OUT="$(mktemp "$ROOT/.aai-release-changelog.XXXXXX")"
NOTES="$(mktemp "${TMPDIR:-/tmp}/aai-release-notes.XXXXXX")"

rollup_rc=0
awk -v version="$VERSION" -v outfile="$OUT" -v notesfile="$NOTES" -f - "$CHANGELOG" <<'AWKPROG' || rollup_rc=$?
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

case "$rollup_rc" in
  0) : ;;
  4) echo "REFUSED: malformed [unreleased] heading in CHANGELOG.md (a '## [unreleased]' line has unexpected trailing text or a stray heading-only body) — never silently dropping entries." >&2
     exit 12 ;;
  5) echo "REFUSED: no rollable [unreleased] entries in CHANGELOG.md (absent or empty) — nothing to release." >&2
     exit 13 ;;
  *) echo "REFUSED: could not parse CHANGELOG.md (rc=$rollup_rc)." >&2
     exit 12 ;;
esac

# Preserve the original file's final-newline state (byte fidelity, D1 step 5):
# command substitution strips ALL trailing newlines, reproducing "no trailing
# newline" exactly when the source had none.
if [[ -s "$CHANGELOG" ]]; then
  last_byte="$(tail -c1 "$CHANGELOG" | od -An -tx1 2>/dev/null | tr -d ' \n')"
  if [[ "$last_byte" != "0a" ]]; then
    printf '%s' "$(cat "$OUT")" > "$OUT"
  fi
fi

# --- D6 CUT-path gates (d)/(e)/(f): dirty tree (snapshotted above) / existing tag / gh auth ----
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

BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"

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
  [[ "$DIRTY" == "1" ]] && { echo "- would block: working tree is dirty"; blocked=1; }
  [[ "$TAG_EXISTS" == "1" ]] && { echo "- would block: tag $VERSION already exists"; blocked=1; }
  [[ "$GH_BLOCK" == "1" ]] && { echo "- would block (publish path): $GH_REASON"; blocked=1; }
  [[ "$blocked" == "0" ]] && echo "- none — ready to cut with --confirm"
  echo
  echo "## Remote"
  if [[ "$NO_REMOTE" == "1" ]]; then
    echo "- --no-remote / AAI_RELEASE_NO_REMOTE=1: push + gh release create would be SKIPPED"
  else
    echo "- push ($BRANCH + tag $VERSION) and 'gh release create' WOULD run against this repo's remote"
  fi
  exit 0
fi

# --- CONFIRM (the cut): fail-closed, zero writes on any refusal below ------
if [[ "$DIRTY" == "1" ]]; then
  echo "REFUSED: working tree is dirty — commit or stash before cutting a release." >&2
  exit 14
fi
if [[ "$TAG_EXISTS" == "1" ]]; then
  echo "REFUSED: tag $VERSION already exists." >&2
  exit 15
fi
if [[ "$GH_BLOCK" == "1" ]]; then
  echo "REFUSED: $GH_REASON (publish path) — dry-run works offline; pass --no-remote/AAI_RELEASE_NO_REMOTE=1 to skip publish, or fix gh auth." >&2
  exit 16
fi

# --- D7 cut sequence: rewrite -> add -> commit -> tag -> (push + publish) --
mv -f "$OUT" "$CHANGELOG"
OUT=""

git -C "$ROOT" add -- CHANGELOG.md
git -C "$ROOT" commit -q -m "chore(release): $VERSION"
git -C "$ROOT" tag -a "$VERSION" -m "$VERSION"

echo "## aai-release — cut complete"
echo "- Version: $VERSION"
echo "- Commit:  $(git -C "$ROOT" rev-parse --short HEAD)"
echo "- Tag:     $VERSION (annotated)"

if [[ "$NO_REMOTE" != "1" ]]; then
  git -C "$ROOT" push origin "$BRANCH"
  git -C "$ROOT" push origin "refs/tags/$VERSION"
  ( cd "$ROOT" && gh release create "$VERSION" --title "$VERSION" --notes-file "$NOTES" )
  echo "- Pushed:  $BRANCH + tag $VERSION"
  echo "- Published: gh release create $VERSION"
else
  echo "- Remote:  SKIPPED (--no-remote/AAI_RELEASE_NO_REMOTE=1) — would push $BRANCH + tag $VERSION, then 'gh release create $VERSION'"
fi
