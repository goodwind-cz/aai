#!/usr/bin/env bash
# Live-status launcher; the logic lives in aai-live.mjs (RFC-0017 small-pairs slice).
# Usage: bash .aai/scripts/aai-live.sh [--watch] [--interval <s>] [--data-only] [...]
MODULE="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/aai-live.mjs"
if command -v node >/dev/null 2>&1 && [[ -f "$MODULE" ]]; then
  exec node "$MODULE" "$@"
fi
echo "aai-live: refused - node not found in PATH or aai-live.mjs missing" >&2
exit 1
