#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

tmp="$(make_tmpdir)"
server_pid=""
cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

cat > "$tmp/project.yaml" <<'EOF'
project_id: fixture-project
default_branch: main
allowed_docker_profile: worker-default
default_provider_policy: auto
phase_provider_preferences:
  planning: claude
EOF

cat > "$tmp/approval-gates.json" <<'EOF'
{
  "approve_implementation_requires": ["prd_ref"],
  "approve_validation_requires": ["implementation_summary"]
}
EOF

mkdir -p "$tmp/bin" "$tmp/home"
cat > "$tmp/bin/claude.js" <<'EOF'
const [command, subcommand, format] = process.argv.slice(2);
if (command === "auth" && subcommand === "status" && format === "--json") {
  console.log(JSON.stringify({
    loggedIn: true,
    email: "fixture@example.test",
    subscriptionType: "max"
  }));
  process.exit(0);
}
console.error("unsupported");
process.exit(1);
EOF

cat > "$tmp/updates.json" <<'EOF'
[
  {
    "update_id": 101,
    "message": {
      "message_id": 1,
      "text": "/intake fixture-project PRD-LIVE-021 Start live polling test",
      "chat": { "id": 9001 },
      "from": { "id": 42 }
    }
  },
  {
    "update_id": 102,
    "message": {
      "message_id": 2,
      "text": "/usage",
      "chat": { "id": 9001 },
      "from": { "id": 42 }
    }
  },
  {
    "update_id": 103,
    "message": {
      "message_id": 3,
      "text": "/status fixture-project PRD-LIVE-021",
      "chat": { "id": 9001 },
      "from": { "id": 42 }
    }
  },
  {
    "update_id": 104,
    "callback_query": {
      "id": "cb-1",
      "data": "stop:run:PRD-LIVE-021",
      "message": {
        "message_id": 4,
        "chat": { "id": 9001 }
      },
      "from": { "id": 42 }
    }
  }
]
EOF

touch "$tmp/telegram.log"

port=18777
"$NODE_BIN" tests/remote-orchestration/fixtures/fake-telegram-api.js "$tmp/updates.json" "$tmp/telegram.log" "$port" > "$tmp/server.out" 2>&1 &
server_pid="$!"
sleep 1

run_cli init --db "$tmp/control-plane.db" >/dev/null
run_cli project register \
  --db "$tmp/control-plane.db" \
  --project-config "$tmp/project.yaml" \
  --repo-path "$PWD" >/dev/null

run_cli auth probe \
  --db "$tmp/control-plane.db" \
  --provider claude \
  --cli-path "$tmp/bin/claude.js" \
  --session-home "$tmp/home" >/dev/null

run_cli telegram serve \
  --db "$tmp/control-plane.db" \
  --token test-token \
  --approval-config "$tmp/approval-gates.json" \
  --api-base "http://127.0.0.1:$port" \
  --once > "$tmp/serve.json"

json_assert_file "$tmp/serve.json" "data.processed_updates === 4"

run_cli queue status --db "$tmp/control-plane.db" --project-id fixture-project --ref-id PRD-LIVE-021 > "$tmp/status.json"
json_assert_file "$tmp/status.json" "data.work_item.status === 'stopped' && data.work_item.phase === 'planning'"

assert_contains "$tmp/telegram.log" "\"method\":\"sendMessage\""
assert_contains "$tmp/telegram.log" "Queued PRD-LIVE-021 for fixture-project"
assert_contains "$tmp/telegram.log" "Usage telemetry unavailable."
assert_contains "$tmp/telegram.log" "claude: status=ok, account=fixture@example.test (max)"
assert_contains "$tmp/telegram.log" "\"method\":\"answerCallbackQuery\""

echo "PASS"
