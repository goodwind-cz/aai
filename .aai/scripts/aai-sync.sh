#!/bin/sh
# AAI layer sync launcher; argument, profile, copy, prune and gitignore rules live in aai-sync.mjs (RFC-0017 phase 5).
# Usage: bash .aai/scripts/aai-sync.sh <path-to-target-project> [--profile core|extended] [-h]
MODULE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/aai-sync.mjs"
if command -v node >/dev/null 2>&1 && [ -f "$MODULE" ]; then
  exec node "$MODULE" "$@"
fi
echo "aai-sync: refused - node not found in PATH or aai-sync.mjs missing; nothing was changed. Install Node.js 22 or later (https://nodejs.org/) and re-run." >&2
exit 1
