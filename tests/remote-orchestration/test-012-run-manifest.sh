#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

tmp="$(make_tmpdir)"
trap 'rm -rf "$tmp"' EXIT
db="$tmp/runtime/control-plane.db"
usage="$tmp/usage.json"
mkdir -p "$tmp/home/claude"

write_usage_fixture "$usage"
run_cli init --db "$db" > /dev/null
cat > "$tmp/claude.js" <<'EOF'
const [command, subcommand, format] = process.argv.slice(2);
if (command === "auth" && subcommand === "status" && format === "--json") {
  console.log(JSON.stringify({ loggedIn: true, email: "manifest@example.test", subscriptionType: "max" }));
  process.exit(0);
}
process.exit(1);
EOF
run_cli auth probe \
  --db "$db" \
  --provider claude \
  --cli-path "$tmp/claude.js" \
  --session-home "$tmp/home/claude" \
  --probe-args auth,status,--json > /dev/null
run_cli run prepare \
  --db "$db" \
  --project-id aai-canonical \
  --ref-id PRD-AAI-REMOTE-ORCHESTRATION-01 \
  --repo-path "$PWD" \
  --project-config docs/ai/project-overrides/remote-control.yaml \
  --usage-file "$usage" \
  --worktrees-root "$tmp/worktrees" \
  --container-image ghcr.io/example/aai-worker:preview \
  --requirement-refs docs/requirements/PRD-AAI-REMOTE-ORCHESTRATION-01.md \
  --spec-refs docs/specs/SPEC-PRD-AAI-REMOTE-ORCHESTRATION-01.md \
  --provider auto > "$tmp/manifest-output.json"

manifest_path="$(NODE_NO_WARNINGS=1 "$NODE_BIN" -e "const fs=require('fs');const data=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));process.stdout.write(data.manifest_path);" "$tmp/manifest-output.json")"
run_cli run validate --manifest "$manifest_path" > "$tmp/validate.json"
json_assert_file "$tmp/validate.json" "data.valid === true"
json_assert_file "$manifest_path" "data.handoff_packet_path.endsWith('.aai-handoff.json') && data.memory_contract.hidden_shared_memory_required === false"
json_assert_file "$manifest_path" "data.provider_session && data.provider_session.provider === 'claude' && data.mounts.some((entry) => entry.target === '/var/run/aai/provider-session/claude' && entry.read_only === true)"
echo "PASS"
