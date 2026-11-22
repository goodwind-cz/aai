#!/bin/sh
# AAI git hook installer launcher; mode, policy, slot and write rules live in install-pre-commit-hook.mjs (RFC-0017 phase 5).
# Usage: bash .aai/scripts/install-pre-commit-hook.sh [--force] [--uninstall] [--print [kind]] [--hooks <csv>] [--decline-ref-guard] [--arm-ref-guard] [-h]
MODULE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/install-pre-commit-hook.mjs"
if command -v node >/dev/null 2>&1 && [ -f "$MODULE" ]; then
  exec node "$MODULE" "$@"
fi
echo "install-pre-commit-hook: refused - node not found in PATH or install-pre-commit-hook.mjs missing; nothing was changed. Install Node.js 22 or later (https://nodejs.org/) and re-run." >&2
exit 1
