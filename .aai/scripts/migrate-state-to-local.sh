#!/usr/bin/env bash
set -euo pipefail

# Migrate AAI per-dev runtime state to local-only (RFC-0001).
#
# Untracks docs/ai/STATE.yaml and docs/ai/LOOP_TICKS.jsonl from git so
# each developer keeps their own loop state without merge conflicts.
# Cross-developer visibility lives in docs/ai/EVENTS.jsonl (append-only,
# committed).
#
# Usage:
#   ./.aai/scripts/migrate-state-to-local.sh [path-to-target-project] [--dry-run]
#   (target defaults to current directory)
#
# Idempotent: re-runs are no-ops when state is already migrated.
# Does NOT auto-commit. Prints the next commands for the user to run.

DRY_RUN=0
TARGET=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      if [[ -z "$TARGET" ]]; then
        TARGET="$arg"
      else
        echo "ERROR: unexpected argument: $arg" >&2
        exit 2
      fi
      ;;
  esac
done

TARGET="$(cd "${TARGET:-$(pwd)}" && pwd)"
cd "$TARGET"

if [[ ! -d "$TARGET/docs/ai" ]]; then
  echo "ERROR: $TARGET/docs/ai not found. Is this an AAI project?" >&2
  exit 1
fi

if ! git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1; then
  echo "ERROR: $TARGET is not inside a git repository." >&2
  exit 1
fi

# Refuse to run on a dirty working tree (avoids mixing this migration with
# unrelated staged changes).
if [[ -n "$(git -C "$TARGET" status --porcelain)" ]]; then
  echo "ERROR: working tree has uncommitted changes." >&2
  echo "       Commit or stash them first, then re-run this script." >&2
  exit 1
fi

run() {
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "  [dry-run] $*"
  else
    eval "$@"
  fi
}

GITIGNORE="$TARGET/.gitignore"
STATE_FILE="docs/ai/STATE.yaml"
TICKS_FILE="docs/ai/LOOP_TICKS.jsonl"
EVENTS_FILE="docs/ai/EVENTS.jsonl"

untracked_count=0
gitignore_added=0
events_created=0

echo "AAI per-dev runtime state migration (RFC-0001)"
echo "Target: $TARGET"
[[ "$DRY_RUN" == 1 ]] && echo "Mode:   dry-run (no changes will be written)"
echo

# 1. Untrack STATE.yaml and LOOP_TICKS.jsonl if tracked.
for f in "$STATE_FILE" "$TICKS_FILE"; do
  if git -C "$TARGET" ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    echo "UNTRACK $f (file remains on disk)"
    run "git -C \"$TARGET\" rm --cached \"$f\""
    untracked_count=$((untracked_count + 1))
  else
    echo "SKIP    $f (already untracked or absent)"
  fi
done

# 1b. Untrack TDD evidence logs (per-dev runtime evidence; .gitkeep stays).
while IFS= read -r f; do
  [[ -z "$f" || "$f" == *"/.gitkeep" ]] && continue
  echo "UNTRACK $f (TDD evidence log; file remains on disk)"
  run "git -C \"$TARGET\" rm --cached \"$f\""
  untracked_count=$((untracked_count + 1))
done < <(git -C "$TARGET" ls-files "docs/ai/tdd" 2>/dev/null)

# 2. Add gitignore entries if missing.
for pattern in "$STATE_FILE" "$TICKS_FILE" "docs/ai/tdd/**" '!docs/ai/tdd/' '!docs/ai/tdd/.gitkeep'; do
  if ! grep -qxF "$pattern" "$GITIGNORE" 2>/dev/null; then
    if [[ "$gitignore_added" -eq 0 ]]; then
      echo "GITIGNORE add header + entries to $GITIGNORE"
      if [[ "$DRY_RUN" == 0 ]]; then
        {
          echo
          echo "# AAI per-dev runtime state (RFC-0001: never committed)"
        } >> "$GITIGNORE"
      fi
    fi
    echo "GITIGNORE add: $pattern"
    if [[ "$DRY_RUN" == 0 ]]; then
      echo "$pattern" >> "$GITIGNORE"
    fi
    gitignore_added=$((gitignore_added + 1))
  else
    echo "SKIP    .gitignore already contains $pattern"
  fi
done

# 3. Create EVENTS.jsonl placeholder if absent.
if [[ ! -e "$TARGET/$EVENTS_FILE" ]]; then
  echo "CREATE  $EVENTS_FILE (empty, append-only audit log)"
  if [[ "$DRY_RUN" == 0 ]]; then
    mkdir -p "$TARGET/docs/ai"
    : > "$TARGET/$EVENTS_FILE"
  fi
  events_created=1
else
  echo "SKIP    $EVENTS_FILE already exists"
fi

echo
echo "Summary:"
echo "  Files untracked:        $untracked_count"
echo "  .gitignore entries added: $gitignore_added"
echo "  EVENTS.jsonl created:   $events_created"

if [[ "$DRY_RUN" == 1 ]]; then
  echo
  echo "Dry-run only. Re-run without --dry-run to apply."
  exit 0
fi

if [[ "$untracked_count" -gt 0 || "$gitignore_added" -gt 0 || "$events_created" -gt 0 ]]; then
  echo
  echo "Next steps (run manually):"
  echo "  git -C \"$TARGET\" add .gitignore $EVENTS_FILE"
  echo "  git -C \"$TARGET\" commit -m \"Migrate AAI STATE to per-dev local runtime (RFC-0001)\""
  echo
  echo "After commit, other developers will see STATE.yaml and LOOP_TICKS.jsonl"
  echo "vanish from the tree on next pull. Their local copies remain on disk."
else
  echo
  echo "Nothing to do — already migrated."
fi
