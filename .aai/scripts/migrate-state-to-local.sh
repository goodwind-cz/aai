#!/bin/sh
# Launcher: the migration logic lives in migrate-state-to-local.mjs (RFC-0017 phase 5).
# Usage: sh .aai/scripts/migrate-state-to-local.sh [path-to-target-project] [--dry-run]
MODULE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/migrate-state-to-local.mjs"
if command -v node >/dev/null 2>&1 && [ -f "$MODULE" ]; then
  exec node "$MODULE" "$@"
fi
echo "migrate-state-to-local: refused - node not found in PATH or migrate-state-to-local.mjs missing; nothing was changed. Install Node.js 22 or later (https://nodejs.org/) and re-run." >&2
exit 1
