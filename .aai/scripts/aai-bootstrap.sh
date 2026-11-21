#!/bin/sh
# Project bootstrap launcher; detection, rendering and write policy live in aai-bootstrap.mjs (RFC-0017 phase 5).
# Usage: ./.aai/scripts/aai-bootstrap.sh [target-root] [--dry-run] [--force] [--with-claude-hooks]
MODULE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/aai-bootstrap.mjs"
if command -v node >/dev/null 2>&1 && [ -f "$MODULE" ]; then
  exec node "$MODULE" "$@"
fi
echo "aai-bootstrap: refused - node not found in PATH or aai-bootstrap.mjs missing; nothing was written. Install Node.js 22 or later (https://nodejs.org/) and re-run." >&2
exit 1
