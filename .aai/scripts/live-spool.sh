#!/usr/bin/env bash
# live-spool.sh - launcher for live-spool.mjs, the statusline/hook tap writer
# (SPEC-0114). All logic lives in the Node module; kind is the first argument
# (statusline|hooks, default statusline); AAI_LIVE_SPOOL_DIR overrides the
# spool directory. Always exits 0: a tap must never disturb the harness.
# When Node is absent or cannot run the module, it drains stdin and prints
# the passthrough for statusline only.
MODULE="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/live-spool.mjs"
rc=1
if command -v node >/dev/null 2>&1; then
  node "$MODULE" "$@" 2>/dev/null && rc=0
fi
if [[ $rc -ne 0 ]]; then
  [[ -t 0 ]] || cat >/dev/null 2>&1
  [[ "${1:-statusline}" == "statusline" ]] && echo "(aai-live tap active)"
fi
exit 0
