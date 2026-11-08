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
# Remote --confirm re-cuts a moved base under the same version (release-finish.mjs).
# Every release-head push first runs the release-preflight (tracked CHANGELOG node tests).
#
# Exit codes: 0 success (plan or cut) | 1 bad argument | 10 not a git repo |
#   11 no CHANGELOG.md | 12 malformed [unreleased] region | 13 no rollable
#   [unreleased] entries (absent/empty) | 15 tag already exists (cut path) |
#   16 gh absent/unauthenticated (when remote PR creation is attempted) |
#   8 finish pending in a merge queue (resume) | 20 finish refused.
set -euo pipefail
# The CHANGELOG rollup, the tag check, the unlogged-PR audit call and the plan are done by release-cut.mjs
# (next to this script), which rolls through lib/release-rollup.mjs like the remote finish does.

VERSION=""
DRY_RUN=0
CONFIRM=0
NO_REMOTE=0
[[ "${AAI_RELEASE_NO_REMOTE:-0}" == "1" ]] && NO_REMOTE=1

usage() { sed -n '2,${/^#/!q;s/^# \{0,1\}//;p;}' "$0"; }

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

WT_DIR=""
cleanup() {
  if [[ -n "$WT_DIR" && -d "$WT_DIR" ]]; then
    git -C "$ROOT" worktree remove --force "$WT_DIR" >/dev/null 2>&1 || rm -rf "$WT_DIR"
  fi
  true
}
trap cleanup EXIT

# --- ALWAYS-checked preconditions: not a git repo / no CHANGELOG --
if ! ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  echo "REFUSED: not a git repository (cwd=$(pwd))." >&2
  exit 10
fi
if [[ ! -f "$ROOT/CHANGELOG.md" ]]; then
  echo "REFUSED: no CHANGELOG.md at repo root: $ROOT/CHANGELOG.md" >&2
  exit 11
fi

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

if ! command -v node >/dev/null 2>&1; then
  echo "REFUSED: missing-node — Node.js 22 or later is required for /aai-release (https://nodejs.org/); nothing was changed." >&2
  exit 20
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
  # --- PLAN-ONLY (bare invocation or --dry-run): release-cut.mjs prints the plan, nothing is written.
  PLAN_ARGS=(--root "$ROOT" --version "$VERSION" --target-branch "$TARGET_BRANCH" --launcher sh)
  if [[ "$NO_REMOTE" == "1" ]]; then
    PLAN_ARGS+=(--no-remote)
  elif ! command -v gh >/dev/null 2>&1; then
    PLAN_ARGS+=(--gh-block "gh CLI not found on PATH")
  elif ! gh auth status >/dev/null 2>&1; then
    PLAN_ARGS+=(--gh-block "gh CLI not authenticated (gh auth status failed)")
  fi
  exec node "$(dirname "$0")/release-cut.mjs" plan "${PLAN_ARGS[@]}"
fi

# --- CONFIRM (the local cut, --no-remote): rollup, tag and notes checks first; fail-closed
node "$(dirname "$0")/release-cut.mjs" check --root "$ROOT" --version "$VERSION" --launcher sh --launcher-path "$0"

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

# A refusal on the base branch's CHANGELOG.md exits with its code; the exit trap removes the worktree.
node "$(dirname "$0")/release-cut.mjs" roll --file "$WT_DIR/CHANGELOG.md" --version "$VERSION"
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
