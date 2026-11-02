#!/bin/sh
# Test-process reaper launcher; the logic and the safety contract live in aai-reap-tests.mjs (RFC-0017 phase 5).
# Usage: sh .aai/scripts/aai-reap-tests.sh
MODULE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/aai-reap-tests.mjs"
if command -v node >/dev/null 2>&1 && [ -f "$MODULE" ]; then
  export AAI_REAP_WORKSPACE="${AAI_REAP_WORKSPACE:-$PWD}"
  exec node "$MODULE" "$@"
fi
echo "aai-reap-tests: refused - node not found in PATH or aai-reap-tests.mjs missing; nothing was reaped" >&2
exit 1
