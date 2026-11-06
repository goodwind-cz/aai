#!/bin/sh
# Launcher: the publish logic lives in cloudflare-share.mjs (RFC-0017 phase 5).
# Usage: sh .aai/scripts/cloudflare-share.sh <document.md>
MODULE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/cloudflare-share.mjs"
if command -v node >/dev/null 2>&1 && [ -f "$MODULE" ]; then
  exec node "$MODULE" "$@"
fi
echo "cloudflare-share: refused - node not found in PATH or cloudflare-share.mjs missing; nothing was published. Install Node.js 22 or later (https://nodejs.org/) and re-run." >&2
exit 1
