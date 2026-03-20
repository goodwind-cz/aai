#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

tmp="$(mktemp -d .tmp-control-plane-build-XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

pushd apps/control-plane >/dev/null
run_npm_cmd install --no-fund --no-audit >/dev/null
run_npm_cmd run build >/dev/null
"$NODE_BIN" dist/cli.js help > "../../$tmp/help.txt"
"$NODE_BIN" dist/cli.js init --db "../../$tmp/control-plane.db" > "../../$tmp/init.json"
"$NODE_BIN" dist/cli.js auth validate --mode cli-subscription > "../../$tmp/auth.json"
popd >/dev/null

grep -q "telegram serve" "$tmp/help.txt" || { echo "missing telegram serve in built help"; exit 1; }
grep -q "run launch" "$tmp/help.txt" || { echo "missing run launch in built help"; exit 1; }
grep -q "\"ok\": true" "$tmp/init.json" || { echo "built init failed"; exit 1; }
grep -q "\"mode\": \"cli-subscription\"" "$tmp/auth.json" || { echo "built auth validation failed"; exit 1; }
echo "PASS"
