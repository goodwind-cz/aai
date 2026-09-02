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
#   path only; dry-run works offline) | 17 target branch is protected: fell
#   back to a release branch + PR, release NOT published | 18 protected-branch
#   fallback engaged but INCOMPLETE (see the report's manual commands).
set -euo pipefail

VERSION=""
DRY_RUN=0
CONFIRM=0
NO_REMOTE=0
[[ "${AAI_RELEASE_NO_REMOTE:-0}" == "1" ]] && NO_REMOTE=1

usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; }

# D1 classifier: is this captured push output a protected-branch/required-
# status-checks rejection? GitHub's own token `GH006`, or the host-agnostic
# wording pair, both case-insensitively. Deliberately narrow: every OTHER
# failure class (auth, network, non-fast-forward) must keep today's raw
# behavior, so a miss degrades to "re-emit and exit with git's code", never to
# a wrong recovery (Constitution article 4; SEAM-5 residual risk).
is_protected_branch_rejection() {
  local text
  text="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  case "$text" in
    *gh006*) return 0 ;;
  esac
  case "$text" in
    *"protected branch"*)
      case "$text" in
        *"status check"*) return 0 ;;
      esac
      ;;
  esac
  return 1
}

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
PUSH_LOG=""
PR_OUT=""
cleanup() {
  # A trap handler's own final exit status would otherwise silently replace
  # the script's real exit code (bash trap semantics) — every path ends in
  # `|| true` so the caller always sees the code the script exited with.
  [[ -n "$OUT" && -f "$OUT" ]] && rm -f "$OUT"
  [[ -n "$NOTES" && -f "$NOTES" ]] && rm -f "$NOTES"
  [[ -n "$PUSH_LOG" && -f "$PUSH_LOG" ]] && rm -f "$PUSH_LOG"
  [[ -n "$PR_OUT" && -f "$PR_OUT" ]] && rm -f "$PR_OUT"
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
    } else if (type[k] == "SCAFFOLD") {
      # Pre-existing bare scaffolds are CONSUMED, not copied: the roll inserts
      # exactly one fresh scaffold above the rolled section, and copying the
      # old one through produced a duplicate bare heading INSIDE the versioned
      # region on every cut (the recurring class TEST-022 pins at PR time —
      # but this engine writes directly to main, so it must not plant it).
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
# D3 step 2: the target branch's pre-cut position, captured BEFORE the release
# commit exists. The protected-branch fallback resets the target branch back to
# exactly this SHA, so the cut leaves the branch as it found it.
PRE_CUT_SHA="$(git -C "$ROOT" rev-parse HEAD)"

mv -f "$OUT" "$CHANGELOG"
OUT=""

# AAI_VERSION.md: the version stamp aai-sync reads to fill `Template version:`
# in a target project's AAI_PIN.md. Without it every downstream pin said
# UNKNOWN (operator-found after the v2026.08.03 deployment check).
mkdir -p "$ROOT/docs/ai"
{
  echo "# AAI Version"
  echo
  echo "- Version: $VERSION"
  echo
  echo "Notes:"
  echo "- Written by the release engines (aai-release.sh / aai-release.ps1) at each cut;"
  echo "  consumed by \`.aai/scripts/aai-sync.*\` to stamp \`Template version:\` into the"
  echo "  target project's \`.aai/system/AAI_PIN.md\`. Do not edit by hand."
} > "$ROOT/docs/ai/AAI_VERSION.md"
git -C "$ROOT" add -- CHANGELOG.md docs/ai/AAI_VERSION.md
git -C "$ROOT" commit -q -m "chore(release): $VERSION"
git -C "$ROOT" tag -a "$VERSION" -m "$VERSION"

echo "## aai-release — cut complete"
echo "- Version: $VERSION"
echo "- Commit:  $(git -C "$ROOT" rev-parse --short HEAD)"
echo "- Tag:     $VERSION (annotated)"

if [[ "$NO_REMOTE" != "1" ]]; then
  # D2 --no-follow-tags: with `push.followTags=true` in the repo or the
  # operator's GLOBAL git config, this branch push would carry
  # refs/tags/$VERSION along with it — and GitHub's branch protection is
  # per-ref and NON-atomic, so a GH006-rejected branch push still publishes
  # the tag. That is precisely how v2026.09.01 (PR #329) left an orphaned tag
  # pointing at a commit `main` never received. The tag push below stays
  # strictly AFTER a successful branch push, and never runs on the fallback.
  PUSH_LOG="$(mktemp "${TMPDIR:-/tmp}/aai-release-push.XXXXXX")"
  push_rc=0
  git -C "$ROOT" push --no-follow-tags origin "$BRANCH" >"$PUSH_LOG" 2>&1 || push_rc=$?
  # D1: always re-emit git's own output, whatever happens next — no diagnostic
  # is ever swallowed by the capture.
  cat "$PUSH_LOG" >&2
  push_text="$(cat "$PUSH_LOG")"
  rm -f "$PUSH_LOG"; PUSH_LOG=""

  if [[ "$push_rc" != "0" ]]; then
    if ! is_protected_branch_rejection "$push_text"; then
      # Every other failure class keeps today's behavior exactly: git's raw
      # output (already on stderr above) and git's own exit code.
      exit "$push_rc"
    fi

    # --- D3 protected-branch fallback: release branch + PR, then STOP -------
    RELEASE_BRANCH="chore/release-$VERSION"
    echo "## aai-release — target branch '$BRANCH' is PROTECTED (push rejected)" >&2

    fallback_incomplete() {
      # D5 exit 18: the fallback engaged but could not finish. Name the exact
      # manual commands rather than leaving a half-cut release to reconstruct.
      echo "## aai-release — PROTECTED-BRANCH FALLBACK INCOMPLETE"
      echo "- Reason:  $1"
      echo "- Version: $VERSION (release commit exists LOCALLY, tag is LOCAL ONLY)"
      echo "- Finish by hand:"
      echo "    git branch $RELEASE_BRANCH $RELEASE_SHA     # if that ref does not exist yet"
      echo "    git reset --hard $PRE_CUT_SHA               # on $BRANCH"
      echo "    git push --no-follow-tags origin $RELEASE_BRANCH"
      echo "    gh pr create --base $BRANCH --head $RELEASE_BRANCH --title 'chore(release): $VERSION'"
      echo "- The release is NOT published and no tag was pushed."
      exit 18
    }

    RELEASE_SHA="$(git -C "$ROOT" rev-parse HEAD)"

    if [[ "$BRANCH" == "HEAD" ]]; then
      fallback_incomplete "detached HEAD — there is no target branch for 'gh pr create --base', so the fallback refuses rather than opening a PR against a bogus base"
    fi
    if git -C "$ROOT" rev-parse -q --verify "refs/heads/$RELEASE_BRANCH" >/dev/null 2>&1; then
      fallback_incomplete "branch $RELEASE_BRANCH already exists — never clobbering an existing ref"
    fi

    git -C "$ROOT" branch "$RELEASE_BRANCH" "$RELEASE_SHA"
    git -C "$ROOT" reset -q --hard "$PRE_CUT_SHA"

    PUSH_LOG="$(mktemp "${TMPDIR:-/tmp}/aai-release-push.XXXXXX")"
    branch_push_rc=0
    git -C "$ROOT" push --no-follow-tags origin "$RELEASE_BRANCH" >"$PUSH_LOG" 2>&1 || branch_push_rc=$?
    cat "$PUSH_LOG" >&2
    rm -f "$PUSH_LOG"; PUSH_LOG=""
    if [[ "$branch_push_rc" != "0" ]]; then
      fallback_incomplete "pushing $RELEASE_BRANCH to origin failed (git exit $branch_push_rc; its output is on stderr above)"
    fi

    PR_BODY="Automated release cut for $VERSION.

The target branch \`$BRANCH\` is protected, so \`aai-release\` did not push to it
directly. This PR carries the release commit; \`$BRANCH\` was reset to
$PRE_CUT_SHA and is unchanged.

The release is NOT published and the annotated tag \`$VERSION\` exists only in
the cutting operator's local clone. After this PR merges, re-point and publish
the tag against the merge commit (a squash merge produces a new SHA).

Opened by .aai/scripts/aai-release.sh — it never merges this PR."
    pr_rc=0
    # gh's stdout goes to a temp file, its stderr passes straight through:
    # the URL is captured, the diagnostics are never swallowed (Constitution
    # article 4). The `cd` stays inside a plain SUBSHELL rather than a command
    # substitution — a `cd` inside `$( )` is the leak shape
    # .aai/scripts/check-cd-subshell-leak.mjs refuses.
    PR_OUT="$(mktemp "${TMPDIR:-/tmp}/aai-release-pr.XXXXXX")"
    ( cd "$ROOT" && gh pr create --base "$BRANCH" --head "$RELEASE_BRANCH" \
        --title "chore(release): $VERSION" --body "$PR_BODY" ) >"$PR_OUT" || pr_rc=$?
    PR_URL="$(cat "$PR_OUT")"
    rm -f "$PR_OUT"; PR_OUT=""
    if [[ "$pr_rc" != "0" ]]; then
      fallback_incomplete "gh pr create failed (exit $pr_rc; its output is on stderr above) — the release branch IS pushed, only the PR is missing"
    fi

    # D8 report. D4: no `gh release create`, no `gh pr merge` — ever, on this
    # path (Constitution article 7). Pinned by TEST-028/TEST-033.
    echo "## aai-release — PROTECTED BRANCH: fell back to a release PR"
    echo "- PR:              $PR_URL"
    echo "- Release branch:  $RELEASE_BRANCH (pushed, carries the release commit $RELEASE_SHA)"
    echo "- Target branch:   $BRANCH — reset to its pre-cut SHA $PRE_CUT_SHA (left clean)"
    echo "- Release:         NOT PUBLISHED — CI must pass and the PR must be merged first."
    echo "- Tag:             $VERSION is annotated LOCALLY ONLY and was NOT pushed."
    echo "- After the PR merges, re-point the tag at the merge commit and publish:"
    echo "    git checkout $BRANCH && git pull"
    echo "    git tag -d $VERSION"
    echo "    git tag -a $VERSION -m $VERSION"
    echo "    git push origin refs/tags/$VERSION"
    echo "    gh release create $VERSION --title $VERSION --notes-file <the [$VERSION] CHANGELOG section>"
    exit 17
  fi

  git -C "$ROOT" push origin "refs/tags/$VERSION"
  ( cd "$ROOT" && gh release create "$VERSION" --title "$VERSION" --notes-file "$NOTES" )
  echo "- Pushed:  $BRANCH + tag $VERSION"
  echo "- Published: gh release create $VERSION"
else
  echo "- Remote:  SKIPPED (--no-remote/AAI_RELEASE_NO_REMOTE=1) — would push $BRANCH + tag $VERSION, then 'gh release create $VERSION'"
fi
