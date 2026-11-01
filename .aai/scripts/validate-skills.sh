#!/usr/bin/env bash
# Skill validation launcher; the logic lives in validate-skills.mjs (RFC-0017 small-pairs slice).
# Usage: bash .aai/scripts/validate-skills.sh [target-dir]
MODULE="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/validate-skills.mjs"
if command -v node >/dev/null 2>&1 && [[ -f "$MODULE" ]]; then
  exec node "$MODULE" "$@"
fi
echo "ERROR: validate-skills needs node (validate-skills.mjs unavailable)" >&2
exit 1
