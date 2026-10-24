#!/usr/bin/env bash
# AAI L1 Triage launcher; the logic lives in triage.mjs (RFC-0017 phase 3).
# Usage: ./.aai/scripts/triage.sh [--check]
MODULE="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/triage.mjs"
if command -v node >/dev/null 2>&1 && [[ -f "$MODULE" ]]; then
  exec node "$MODULE" "$@"
fi
echo "### Triage verdict: UNKNOWN (node or triage.mjs unavailable)"
exit 0
