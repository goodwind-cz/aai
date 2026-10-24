#!/usr/bin/env bash
# Expert fetch launcher; the logic lives in expert-fetch.mjs (RFC-0017 phase 3).
# Usage: bash .aai/scripts/expert-fetch.sh <key> [--force] | --detect <tok>... | --body <key> | --list | --check <key> <phase>
MODULE="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/expert-fetch.mjs"
if command -v node >/dev/null 2>&1 && [[ -f "$MODULE" ]]; then
  exec node "$MODULE" "$@"
fi
echo "ERROR: expert-fetch needs node (expert-fetch.mjs unavailable)" >&2
exit 1
