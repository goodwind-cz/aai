#!/bin/sh
# AAI release-cut launcher for /aai-release; the whole command lives in aai-release.mjs (RFC-0017 phase 5).
# Usage (run from anywhere inside the target repo):
#   ./.aai/scripts/aai-release.sh [--version <v>] [--dry-run] [--confirm] [--no-remote] [-h]
# Flags, environment variables and exit codes: see .aai/SKILL_RELEASE.prompt.md (run with --help for the usage).
case "$0" in */*) DIR="${0%/*}" ;; *) DIR=. ;; esac
MODULE="$DIR/aai-release.mjs"
if command -v node >/dev/null 2>&1 && [ -f "$MODULE" ]; then
  exec node "$MODULE" --launcher sh --launcher-path "$0" "$@"
fi
echo "REFUSED: missing-node — Node.js 22 or later is required for /aai-release (https://nodejs.org/); nothing was changed." >&2
exit 20
