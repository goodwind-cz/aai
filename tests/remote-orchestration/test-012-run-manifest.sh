#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

tmp="$(make_tmpdir)"
trap 'rm -rf "$tmp"' EXIT
db="$tmp/runtime/control-plane.db"
usage="$tmp/usage.json"

write_usage_fixture "$usage"
run_cli init --db "$db" > /dev/null
run_cli run prepare \
  --db "$db" \
  --project-id aai-canonical \
  --ref-id PRD-AAI-REMOTE-ORCHESTRATION-01 \
  --repo-path "$PWD" \
  --project-config docs/ai/project-overrides/remote-control.yaml \
  --usage-file "$usage" \
  --worktrees-root "$tmp/worktrees" \
  --container-image ghcr.io/example/aai-worker:preview \
  --provider auto > "$tmp/manifest-output.json"

manifest_path="$(NODE_NO_WARNINGS=1 "$NODE_BIN" -e "const fs=require('fs');const data=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));process.stdout.write(data.manifest_path);" "$tmp/manifest-output.json")"
run_cli run validate --manifest "$manifest_path" > "$tmp/validate.json"
json_assert_file "$tmp/validate.json" "data.valid === true"
echo "PASS"
