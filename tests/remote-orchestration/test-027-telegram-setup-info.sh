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

cat > "$tmp/updates.json" <<'EOF'
[
  {
    "update_id": 201,
    "message": {
      "message_id": 1,
      "text": "/projects",
      "chat": { "id": 9001 },
      "from": { "id": 42 }
    }
  },
  {
    "update_id": 202,
    "callback_query": {
      "id": "cb-setup",
      "data": "project:fixture-project:session",
      "message": {
        "message_id": 2,
        "chat": { "id": 9002 }
      },
      "from": { "id": 84 }
    }
  }
]
EOF

touch "$tmp/telegram.log"

port=18778
"$NODE_BIN" tests/remote-orchestration/fixtures/fake-telegram-api.js "$tmp/updates.json" "$tmp/telegram.log" "$port" > "$tmp/server.out" 2>&1 &
server_pid="$!"
sleep 1

npm --silent --prefix apps/control-plane run telegram:get-me -- \
  --token test-token \
  --api-base "http://127.0.0.1:$port" > "$tmp/get-me.json"

npm --silent --prefix apps/control-plane run telegram:setup-info -- \
  --token test-token \
  --api-base "http://127.0.0.1:$port" \
  --limit 10 > "$tmp/setup-info.json"

json_assert_file "$tmp/get-me.json" "data.username === 'aai_test_bot' && data.is_bot === true"
json_assert_file "$tmp/setup-info.json" "data.bot.username === 'aai_test_bot'"
json_assert_file "$tmp/setup-info.json" "data.chat_ids.length === 2 && data.chat_ids.some((entry) => entry.chat_id === '9001') && data.chat_ids.some((entry) => entry.chat_id === '9002')"
json_assert_file "$tmp/setup-info.json" "data.user_ids.length === 2 && data.user_ids.some((entry) => entry.user_id === '42') && data.user_ids.some((entry) => entry.user_id === '84')"
json_assert_file "$tmp/setup-info.json" "data.recent_updates.length === 2 && data.recent_updates[0].type === 'message' && data.recent_updates[1].type === 'callback_query'"

assert_contains "$tmp/telegram.log" "\"method\":\"getMe\""
assert_contains "$tmp/telegram.log" "\"method\":\"getUpdates\""

echo "PASS"
