#!/bin/sh
# AAI layer updater launcher; argument, source, sync and report policy live in aai-update.mjs (RFC-0017 phase 5).
# Usage: ./.aai/scripts/aai-update.sh [--repo <slug|url|path>] [--ref <ref>] [--dry-run] [--keep-temp] [--force] [-h]
MODULE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/aai-update.mjs"
if command -v node >/dev/null 2>&1 && [ -f "$MODULE" ]; then
  AAI_UPDATE_SYNC_RUNNER=bash
  export AAI_UPDATE_SYNC_RUNNER
  exec node "$MODULE" "$@"
fi
echo "aai-update: refused - node not found in PATH or aai-update.mjs missing; nothing was changed. Install Node.js 22 or later (https://nodejs.org/) and re-run." >&2
exit 1
