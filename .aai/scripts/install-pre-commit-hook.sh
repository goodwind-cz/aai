#!/usr/bin/env bash
set -euo pipefail

# Install an opt-in .git/hooks/pre-commit that auto-regenerates docs/INDEX.md
# whenever the commit touches docs/. RFC-0001 layer 4 convenience.
#
# Usage:
#   ./.aai/scripts/install-pre-commit-hook.sh           # install if absent
#   ./.aai/scripts/install-pre-commit-hook.sh --force   # overwrite existing
#   ./.aai/scripts/install-pre-commit-hook.sh --uninstall
#
# Idempotent. Refuses to overwrite a non-AAI hook unless --force is given.

FORCE=0
UNINSTALL=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "ERROR: unexpected argument: $arg" >&2
      exit 2
      ;;
  esac
done

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "ERROR: not inside a git repository." >&2
  exit 1
}
HOOK_PATH="$REPO_ROOT/.git/hooks/pre-commit"
MARKER="# AAI:INDEX-AUTOGEN"

if [[ "$UNINSTALL" == 1 ]]; then
  if [[ -f "$HOOK_PATH" ]] && grep -qF "$MARKER" "$HOOK_PATH"; then
    rm "$HOOK_PATH"
    echo "Uninstalled AAI pre-commit hook from $HOOK_PATH"
  else
    echo "No AAI pre-commit hook found (or hook is not AAI-managed). No action taken."
  fi
  exit 0
fi

if [[ -f "$HOOK_PATH" && "$FORCE" != 1 ]]; then
  if grep -qF "$MARKER" "$HOOK_PATH"; then
    echo "AAI pre-commit hook already installed at $HOOK_PATH. No action taken."
    exit 0
  fi
  echo "ERROR: $HOOK_PATH already exists and is not AAI-managed." >&2
  echo "       Pass --force to overwrite, or merge the snippet manually:" >&2
  echo "       $REPO_ROOT/.aai/scripts/install-pre-commit-hook.sh --print" >&2
  exit 1
fi

mkdir -p "$REPO_ROOT/.git/hooks"
cat > "$HOOK_PATH" <<'HOOK'
#!/usr/bin/env bash
# AAI:INDEX-AUTOGEN — auto-regenerate docs/INDEX.md on docs/ changes.
# Installed by .aai/scripts/install-pre-commit-hook.sh
set -euo pipefail

if ! command -v node >/dev/null 2>&1; then
  exit 0
fi

if ! git diff --cached --name-only | grep -qE '^docs/'; then
  exit 0
fi

GEN=".aai/scripts/generate-docs-index.mjs"
if [[ ! -f "$GEN" ]]; then
  exit 0
fi

if ! node "$GEN"; then
  echo "AAI:INDEX-AUTOGEN: generator failed; commit aborted." >&2
  exit 1
fi

git add docs/INDEX.md
# Companion violations report is created when docs are malformed, removed when clean.
if [[ -f docs/INDEX.violations.md ]]; then
  git add docs/INDEX.violations.md
else
  git rm --cached --quiet --ignore-unmatch docs/INDEX.violations.md
fi
# SPEC-0010 / ISSUE-0003: docs/INDEX.audit.md carries git-history-dependent
# Orphans + Drift sections; it is git-ignored and must NEVER be staged (staging it
# would reintroduce the committed-index non-idempotence). Belt-and-suspenders un-stage.
git rm --cached --quiet --ignore-unmatch docs/INDEX.audit.md
echo "AAI:INDEX-AUTOGEN: regenerated and staged docs/INDEX.md"
HOOK
chmod +x "$HOOK_PATH"
echo "Installed AAI pre-commit hook at $HOOK_PATH"
echo "Effect: on every commit that touches docs/, regenerate docs/INDEX.md and stage it."
echo "Uninstall with: bash .aai/scripts/install-pre-commit-hook.sh --uninstall"
