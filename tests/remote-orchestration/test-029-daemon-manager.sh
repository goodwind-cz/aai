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

mkdir -p "$tmp/bin" "$tmp/home/claude" "$tmp/home/codex"

cat > "$tmp/project.yaml" <<'EOF'
project_id: fixture-daemon-029
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

cat > "$tmp/bin/claude.js" <<'EOF'
const [command, subcommand, format] = process.argv.slice(2);
if (command === "auth" && subcommand === "status" && format === "--json") {
  console.log(JSON.stringify({
    loggedIn: true,
    email: "daemon@example.test",
    subscriptionType: "max"
  }));
  process.exit(0);
}
console.error("unsupported");
process.exit(1);
EOF

cat > "$tmp/bin/codex.js" <<'EOF'
console.log("codex ok");
EOF

cat > "$tmp/updates.json" <<'EOF'
[]
EOF

touch "$tmp/telegram.log"
port=18779
"$NODE_BIN" tests/remote-orchestration/fixtures/fake-telegram-api.js "$tmp/updates.json" "$tmp/telegram.log" "$port" > "$tmp/server.out" 2>&1 &
server_pid="$!"
sleep 1

run_cli init --db "$tmp/control-plane.db" > /dev/null
run_cli project register \
  --db "$tmp/control-plane.db" \
  --project-config "$tmp/project.yaml" \
  --repo-path "$PWD" > /dev/null
run_cli auth probe \
  --db "$tmp/control-plane.db" \
  --provider claude \
  --cli-path "$tmp/bin/claude.js" \
  --session-home "$tmp/home/claude" > /dev/null
run_cli auth probe \
  --db "$tmp/control-plane.db" \
  --provider codex \
  --cli-path "$tmp/bin/codex.js" \
  --session-home "$tmp/home/codex" \
  --probe-args --help > /dev/null

cat > "$tmp/control-plane.env" <<EOF
AAI_TELEGRAM_BOT_TOKEN=test-token
AAI_CONTROL_PLANE_DB=$tmp/control-plane.db
AAI_APPROVAL_CONFIG=$tmp/approval-gates.json
AAI_CONTROL_PLANE_LOG=$tmp/control-plane.log
AAI_CONTROL_PLANE_CONSOLE_LOG=$tmp/control-plane.console.log
AAI_CONTROL_PLANE_PID_FILE=$tmp/control-plane.pid
AAI_PROJECT_ID=fixture-daemon-029
AAI_PROJECT_CONFIG_PATH=$tmp/project.yaml
AAI_MANAGED_REPO_PATH=$PWD
AAI_CLAUDE_CLI_PATH=$tmp/bin/claude.js
AAI_CODEX_CLI_PATH=$tmp/bin/codex.js
AAI_CLAUDE_SESSION_HOME=$tmp/home/claude
AAI_CODEX_SESSION_HOME=$tmp/home/codex
AAI_TELEGRAM_API_BASE=http://127.0.0.1:$port
NODE_NO_WARNINGS=1
EOF

bash apps/control-plane/scripts/control-plane-daemon.sh --env "$tmp/control-plane.env" start > "$tmp/start.out"
assert_contains "$tmp/start.out" "Started control-plane daemon in background."
assert_file "$tmp/control-plane.pid"

bash apps/control-plane/scripts/control-plane-daemon.sh --env "$tmp/control-plane.env" status > "$tmp/status.out"
assert_contains "$tmp/status.out" "Daemon: running"
assert_contains "$tmp/status.out" "fixture-daemon-029"
assert_contains "$tmp/status.out" "- claude: ok"
assert_contains "$tmp/status.out" "- codex: ok"

bash apps/control-plane/scripts/control-plane-daemon.sh --env "$tmp/control-plane.env" probe > "$tmp/probe.out"
assert_contains "$tmp/probe.out" "Provider probe results"
assert_contains "$tmp/probe.out" "- claude: ok"
assert_contains "$tmp/probe.out" "- codex: ok"

bash apps/control-plane/scripts/control-plane-daemon.sh --env "$tmp/control-plane.env" stop > "$tmp/stop.out"
assert_contains "$tmp/stop.out" "Stopped control-plane daemon."

bash apps/control-plane/scripts/control-plane-daemon.sh --env "$tmp/control-plane.env" status > "$tmp/status-stopped.out"
assert_contains "$tmp/status-stopped.out" "Daemon: stopped"

echo "PASS"
