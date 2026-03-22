#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ENV_FILE=""
RENDER_NODE=""

usage() {
  cat <<'EOF'
Usage:
  bash apps/control-plane/scripts/control-plane-daemon.sh [--env <path>] [start|run|status|stop|restart|logs|probe|usage|auth <setup|status>]

Commands:
  start     Start the Telegram daemon in background and return immediately.
  run       Run the Telegram daemon in foreground.
  status    Show current daemon/process/auth status.
  stop      Stop the background daemon.
  restart   Restart the background daemon.
  logs      Tail the structured runtime log.
  probe     Re-probe Claude and Codex session state and print the result.
  usage     Show provider usage telemetry and routing capacity summary.
  auth      Run 'auth setup' or 'auth status' for provider readiness.
EOF
}

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

detect_default_env_file() {
  printf '%s\n' "$HOST_ROOT/.runtime/control-plane.env"
}

detect_render_node() {
  if command -v node >/dev/null 2>&1; then
    printf '%s\n' "node"
    return
  fi
  if command -v node.exe >/dev/null 2>&1; then
    printf '%s\n' "node.exe"
    return
  fi
  printf '\n'
}

run_provider_login_command() {
  local cli_path="$1"
  shift
  if [[ "$cli_path" =~ \.(cjs|mjs|js|ts)$ ]]; then
    "${RENDER_NODE:-node}" --no-warnings "$cli_path" "$@"
    return
  fi
  "$cli_path" "$@"
}

print_shell_command() {
  printf '  '
  printf '%q ' "$@"
  printf '\n'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      ENV_FILE="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

ENV_FILE="${ENV_FILE:-$(detect_default_env_file)}"
[[ -f "$ENV_FILE" ]] || fail "Missing env file: $ENV_FILE"
source "$ENV_FILE"
RENDER_NODE="$(detect_render_node)"

ACTION="${1:-start}"
ARG2="${2:-}"
ARG3="${3:-}"
RUNTIME_DIR="$(cd "$(dirname "$ENV_FILE")" && pwd)"
PID_FILE="${AAI_CONTROL_PLANE_PID_FILE:-$RUNTIME_DIR/control-plane.pid}"
CONSOLE_LOG="${AAI_CONTROL_PLANE_CONSOLE_LOG:-$RUNTIME_DIR/control-plane.console.log}"
STRUCTURED_LOG="${AAI_CONTROL_PLANE_LOG:-$RUNTIME_DIR/control-plane.log}"

mkdir -p "$RUNTIME_DIR"

daemon_command() {
  local cmd=(
    bash apps/control-plane/scripts/run-cli.sh telegram serve
    --db "$AAI_CONTROL_PLANE_DB"
    --token "$AAI_TELEGRAM_BOT_TOKEN"
    --approval-config "$AAI_APPROVAL_CONFIG"
    --max-idle-cycles 0
  )
  if [[ -n "${AAI_TELEGRAM_API_BASE:-}" ]]; then
    cmd+=(--api-base "$AAI_TELEGRAM_API_BASE")
  fi
  if [[ -n "${AAI_TELEGRAM_POLL_INTERVAL_MS:-}" ]]; then
    cmd+=(--poll-interval-ms "$AAI_TELEGRAM_POLL_INTERVAL_MS")
  fi
  printf '%q ' "${cmd[@]}"
  printf '\n'
}

is_running() {
  if [[ ! -f "$PID_FILE" ]]; then
    return 1
  fi
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -z "$pid" ]]; then
    return 1
  fi
  kill -0 "$pid" 2>/dev/null
}

render_provider_sessions() {
  local payload="$1"
  if [[ -z "$RENDER_NODE" ]]; then
    printf '%s\n' "$payload"
    return
  fi
  "$RENDER_NODE" --no-warnings - "$payload" <<'EOF'
const [raw] = process.argv.slice(2);
const payload = JSON.parse(raw);
const sessions = Array.isArray(payload.sessions) ? payload.sessions : [];
if (sessions.length === 0) {
  console.log("No provider sessions recorded yet.");
  process.exit(0);
}
for (const session of sessions) {
  const account = session.account_label || "unknown";
  const verified = session.last_verified_at_utc || "never";
  const usage = session.last_usage_sync_at_utc || "never";
  const error = session.last_error || "none";
  console.log(`- ${session.provider}: ${session.status}`);
  console.log(`  account: ${account}`);
  console.log(`  cli: ${session.cli_path}`);
  console.log(`  session home: ${session.session_home}`);
  console.log(`  last verified: ${verified}`);
  console.log(`  last usage sync: ${usage}`);
  console.log(`  error: ${error}`);
}
EOF
}

render_project_summary() {
  local payload="$1"
  if [[ -z "$RENDER_NODE" ]]; then
    printf '%s\n' "$payload"
    return
  fi
  "$RENDER_NODE" --no-warnings - "$payload" <<'EOF'
const [raw] = process.argv.slice(2);
const payload = JSON.parse(raw);
if (payload.project) {
  const project = payload.project;
  console.log(`- project id: ${project.project_id}`);
  console.log(`  repo path: ${project.local_repo_path}`);
  console.log(`  config: ${project.project_config_path}`);
  console.log(`  default branch: ${project.default_branch}`);
  console.log(`  provider policy: ${project.default_provider_policy}`);
  console.log(`  allowed chats: ${(project.allowed_telegram_chat_ids || []).join(",") || "none"}`);
  console.log(`  allowed users: ${(project.allowed_telegram_user_ids || []).join(",") || "none"}`);
  process.exit(0);
}
const projects = Array.isArray(payload.projects) ? payload.projects : [];
if (projects.length === 0) {
  console.log("No registered projects.");
  process.exit(0);
}
for (const project of projects) {
  console.log(`- ${project.project_id} (${project.default_branch})`);
}
EOF
}

auth_doctor() {
  bash apps/control-plane/scripts/run-cli.sh auth doctor \
    --db "$AAI_CONTROL_PLANE_DB" \
    --claude-cli-path "${AAI_CLAUDE_CLI_PATH:-$(command -v claude 2>/dev/null || true)}" \
    --claude-session-home "${AAI_CLAUDE_SESSION_HOME:-$HOME/.claude}" \
    --codex-cli-path "${AAI_CODEX_CLI_PATH:-$(command -v codex 2>/dev/null || true)}" \
    --codex-session-home "${AAI_CODEX_SESSION_HOME:-$HOME/.codex}"
}

render_auth_doctor() {
  local payload="$1"
  if [[ -z "$RENDER_NODE" ]]; then
    printf '%s\n' "$payload"
    return
  fi
  "$RENDER_NODE" --no-warnings - "$payload" <<'EOF'
const [raw] = process.argv.slice(2);
const payload = JSON.parse(raw);
const sessions = Array.isArray(payload.sessions) ? payload.sessions : [];
const capacities = Array.isArray(payload.capacities) ? payload.capacities : [];
if (sessions.length === 0) {
  console.log("No provider sessions recorded yet.");
  process.exit(0);
}
for (const session of sessions) {
  const capacity = capacities.find((entry) => entry.provider === session.provider) || null;
  console.log(`- ${session.provider}: ${session.status}`);
  console.log(`  account: ${session.account_label || "unknown"}`);
  console.log(`  cli: ${session.cli_path}`);
  console.log(`  session home: ${session.session_home}`);
  console.log(`  last verified: ${session.last_verified_at_utc || "never"}`);
  console.log(`  last usage sync: ${session.last_usage_sync_at_utc || "never"}`);
  console.log(`  error: ${session.last_error || "none"}`);
  if (capacity) {
    console.log(`  dispatch: ${capacity.dispatch_state}`);
    console.log(`  recommended parallel runs: ${capacity.recommended_parallel_runs}`);
    console.log(`  capacity reason: ${capacity.reason}`);
  }
}
EOF
}

render_usage_summary() {
  local payload="$1"
  if [[ -z "$RENDER_NODE" ]]; then
    printf '%s\n' "$payload"
    return
  fi
  "$RENDER_NODE" --no-warnings - "$payload" <<'EOF'
const [raw] = process.argv.slice(2);
const payload = JSON.parse(raw);
const windows = Array.isArray(payload.windows) ? payload.windows : [];
const capacities = Array.isArray(payload.capacities) ? payload.capacities : [];
const sessions = Array.isArray(payload.sessions) ? payload.sessions : [];
if (windows.length === 0) {
  console.log("Usage telemetry unavailable.");
  for (const capacity of capacities) {
    const session = sessions.find((entry) => entry.provider === capacity.provider) || null;
    console.log(`- ${capacity.provider}: dispatch=${capacity.dispatch_state}, recommended_parallel_runs=${capacity.recommended_parallel_runs}, reason=${capacity.reason}, account=${session?.account_label || "unknown"}`);
  }
  process.exit(0);
}
for (const window of windows) {
  console.log(`- ${window.provider}: ${window.used_percentage}% used, resets ${window.reset_at_utc}`);
}
for (const capacity of capacities) {
  console.log(`  ${capacity.provider}: dispatch=${capacity.dispatch_state}, recommended_parallel_runs=${capacity.recommended_parallel_runs}, reason=${capacity.reason}`);
}
EOF
}

auth_status_flow() {
  local payload=""
  payload="$(auth_doctor)"
  printf 'Provider auth status\n'
  render_auth_doctor "$payload"
}

usage_status_flow() {
  local payload=""
  payload="$(bash apps/control-plane/scripts/run-cli.sh usage show --db "$AAI_CONTROL_PLANE_DB")"
  printf 'Provider usage and routing capacity\n'
  render_usage_summary "$payload"
}

probe_and_render_provider() {
  local provider="$1"
  local payload=""
  if ! payload="$(probe_provider "$provider" 2>/dev/null)"; then
    printf -- '- %s: probe failed\n' "$provider"
    return 1
  fi
  if [[ -z "$RENDER_NODE" ]]; then
    printf '%s\n' "$payload"
    return 0
  fi
  "$RENDER_NODE" --no-warnings - "$payload" <<'EOF'
const [raw] = process.argv.slice(2);
const payload = JSON.parse(raw);
const session = payload.session;
const windows = Array.isArray(payload.usage_windows) ? payload.usage_windows : [];
if (!session) {
  console.log("- probe returned no session payload");
  process.exit(0);
}
console.log(`- ${session.provider}: ${session.status}`);
console.log(`  account: ${session.account_label || "unknown"}`);
console.log(`  cli: ${session.cli_path}`);
console.log(`  session home: ${session.session_home}`);
console.log(`  last verified: ${session.last_verified_at_utc || "never"}`);
console.log(`  last usage sync: ${session.last_usage_sync_at_utc || "never"}`);
console.log(`  error: ${session.last_error || "none"}`);
if (windows.length === 0) {
  console.log("  usage telemetry: unavailable");
} else {
  for (const window of windows) {
    console.log(`  usage ${window.window_label}: ${window.used_percentage}% used, resets ${window.reset_at_utc}`);
  }
}
EOF
}

print_status() {
  if is_running; then
    printf 'Daemon: running\n'
    printf 'PID: %s\n' "$(cat "$PID_FILE")"
  else
    printf 'Daemon: stopped\n'
  fi
  printf 'Project: %s\n' "${AAI_PROJECT_ID:-unknown}"
  printf 'DB: %s\n' "$AAI_CONTROL_PLANE_DB"
  printf 'Structured log: %s\n' "$STRUCTURED_LOG"
  printf 'Console log: %s\n' "$CONSOLE_LOG"
  printf 'Telegram token: %s\n' "$(if [[ -n "${AAI_TELEGRAM_BOT_TOKEN:-}" ]]; then printf configured; else printf missing; fi)"
  printf '\nProvider sessions\n'
  local auth_payload=""
  if auth_payload="$(auth_doctor 2>/dev/null)"; then
    render_provider_sessions "$auth_payload"
  else
    printf 'Unable to load provider session status.\n'
  fi
  printf '\nUsage and routing\n'
  local usage_payload=""
  if usage_payload="$(bash apps/control-plane/scripts/run-cli.sh usage show --db "$AAI_CONTROL_PLANE_DB" 2>/dev/null)"; then
    render_usage_summary "$usage_payload"
  else
    printf 'Unable to load provider usage summary.\n'
  fi
  printf '\nProjects\n'
  local project_payload=""
  if [[ -n "${AAI_PROJECT_ID:-}" ]]; then
    project_payload="$(bash apps/control-plane/scripts/run-cli.sh project show --db "$AAI_CONTROL_PLANE_DB" --project-id "$AAI_PROJECT_ID" 2>/dev/null || true)"
  else
    project_payload="$(bash apps/control-plane/scripts/run-cli.sh project list --db "$AAI_CONTROL_PLANE_DB" 2>/dev/null || true)"
  fi
  if [[ -n "$project_payload" ]]; then
    render_project_summary "$project_payload"
  else
    printf 'Unable to load project status.\n'
  fi
}

probe_provider() {
  local provider="$1"
  local cli_path=""
  local session_home=""
  case "$provider" in
    claude)
      cli_path="${AAI_CLAUDE_CLI_PATH:-$(command -v claude 2>/dev/null || true)}"
      session_home="${AAI_CLAUDE_SESSION_HOME:-$HOME/.claude}"
      ;;
    codex)
      cli_path="${AAI_CODEX_CLI_PATH:-$(command -v codex 2>/dev/null || true)}"
      session_home="${AAI_CODEX_SESSION_HOME:-$HOME/.codex}"
      ;;
    *)
      fail "Unsupported provider: $provider"
      ;;
  esac

  if [[ -z "$cli_path" ]]; then
    bash apps/control-plane/scripts/run-cli.sh auth mark-missing \
      --db "$AAI_CONTROL_PLANE_DB" \
      --provider "$provider" \
      --session-home "$session_home" \
      --message "$provider CLI is not installed on this host." || return 1
    return 0
  fi

  bash apps/control-plane/scripts/run-cli.sh auth probe \
    --db "$AAI_CONTROL_PLANE_DB" \
    --provider "$provider" \
    --cli-path "$cli_path" \
    --session-home "$session_home"
}

doctor_has_ready_provider() {
  local payload="$1"
  if [[ -z "$RENDER_NODE" ]]; then
    grep -q '"status": "ok"' <<<"$payload"
    return
  fi
  "$RENDER_NODE" --no-warnings - "$payload" <<'EOF'
const [raw] = process.argv.slice(2);
const payload = JSON.parse(raw);
const sessions = Array.isArray(payload.sessions) ? payload.sessions : [];
process.exit(sessions.some((entry) => entry.status === "ok") ? 0 : 1);
EOF
}

print_native_login_command() {
  local provider="$1"
  local cli_path="$2"
  local session_home="$3"
  case "$provider" in
    claude)
      print_shell_command env "HOME=$session_home" "AAI_PROVIDER_SESSION_HOME=$session_home" "$cli_path" auth login
      ;;
    codex)
      print_shell_command env "HOME=$session_home" "AAI_PROVIDER_SESSION_HOME=$session_home" "$cli_path" login
      ;;
  esac
}

auth_setup_for_provider() {
  local provider="$1"
  local payload="$2"
  local cli_path="$3"
  local session_home="$4"
  local current_status=""
  local account_label=""
  local last_error=""

  current_status="$("$RENDER_NODE" --no-warnings - "$payload" "$provider" <<'EOF'
const [raw, provider] = process.argv.slice(2);
const payload = JSON.parse(raw);
const sessions = Array.isArray(payload.sessions) ? payload.sessions : [];
const session = sessions.find((entry) => entry.provider === provider);
process.stdout.write(session?.status || "unknown");
EOF
)"
  account_label="$("$RENDER_NODE" --no-warnings - "$payload" "$provider" <<'EOF'
const [raw, provider] = process.argv.slice(2);
const payload = JSON.parse(raw);
const sessions = Array.isArray(payload.sessions) ? payload.sessions : [];
const session = sessions.find((entry) => entry.provider === provider);
process.stdout.write(session?.account_label || "");
EOF
)"
  last_error="$("$RENDER_NODE" --no-warnings - "$payload" "$provider" <<'EOF'
const [raw, provider] = process.argv.slice(2);
const payload = JSON.parse(raw);
const sessions = Array.isArray(payload.sessions) ? payload.sessions : [];
const session = sessions.find((entry) => entry.provider === provider);
process.stdout.write(session?.last_error || "");
EOF
)"

  if [[ -z "$cli_path" ]]; then
    case "$provider" in
      claude)
        printf "Claude CLI is not installed. Install Claude Code CLI first, then rerun 'bash %s auth setup'.\n" "$0"
        ;;
      codex)
        printf "Codex CLI is not installed. Install it with 'npm install -g @openai/codex@latest', then rerun 'bash %s auth setup'.\n" "$0"
        ;;
    esac
    return
  fi

  if [[ "$current_status" == "ok" ]]; then
    printf "%s already looks ready" "$provider"
    if [[ -n "$account_label" ]]; then
      printf " as %s" "$account_label"
    fi
    printf ". Using the existing native CLI login.\n"
    return
  fi

  printf "%s is not ready yet" "$provider"
  if [[ -n "$last_error" ]]; then
    printf " (%s)" "$last_error"
  fi
  printf ".\n"
  printf "Run this native provider login in a separate direct WSL/Linux terminal:\n"
  print_native_login_command "$provider" "$cli_path" "$session_home"
  if [[ "$provider" == "claude" ]]; then
    printf "When Claude opens the browser and shows an authentication code, paste that code back into that native terminal and press Enter there.\n"
  else
    printf "When Codex opens its login flow, complete it there and then exit that native terminal session.\n"
  fi
  printf "After native login succeeds, rerun:\n"
  printf "  bash %s auth status\n" "$0"
}

auth_setup_flow() {
  local payload=""
  printf 'Auth setup\n'
  printf 'SuperTurtle-style rule: init/install only prepares config and runtime. Provider login stays in the native Claude/Codex CLI, and start only runs after auth is already ready.\n\n'
  payload="$(auth_doctor)"
  render_auth_doctor "$payload"
  printf '\n'
  auth_setup_for_provider "claude" "$payload" "${AAI_CLAUDE_CLI_PATH:-$(command -v claude 2>/dev/null || true)}" "${AAI_CLAUDE_SESSION_HOME:-$HOME/.claude}"
  printf '\n'
  auth_setup_for_provider "codex" "$payload" "${AAI_CODEX_CLI_PATH:-$(command -v codex 2>/dev/null || true)}" "${AAI_CODEX_SESSION_HOME:-$HOME/.codex}"
  printf '\nNext step\n'
  printf '  1. Finish native provider login in a normal WSL/Linux terminal if needed.\n'
  printf '  2. Run: bash %s auth status\n' "$0"
  printf '  3. Then run: bash %s start\n' "$0"
}

login_provider() {
  local provider="$1"
  local cli_path=""
  local session_home=""
  case "$provider" in
    claude)
      cli_path="${AAI_CLAUDE_CLI_PATH:-$(command -v claude 2>/dev/null || true)}"
      session_home="${AAI_CLAUDE_SESSION_HOME:-$HOME/.claude}"
      ;;
    codex)
      cli_path="${AAI_CODEX_CLI_PATH:-$(command -v codex 2>/dev/null || true)}"
      session_home="${AAI_CODEX_SESSION_HOME:-$HOME/.codex}"
      ;;
    *)
      fail "Unsupported provider: $provider"
      ;;
  esac
  local payload=""
  payload="$(auth_doctor)"
  auth_setup_for_provider "$provider" "$payload" "$cli_path" "$session_home"
}

start_daemon() {
  [[ -n "${AAI_TELEGRAM_BOT_TOKEN:-}" ]] || fail "AAI_TELEGRAM_BOT_TOKEN is missing in $ENV_FILE"
  local doctor_payload=""
  doctor_payload="$(auth_doctor)"
  if ! doctor_has_ready_provider "$doctor_payload"; then
    printf 'No ready Claude/Codex CLI session is available yet.\n' >&2
    printf 'Run this first:\n' >&2
    printf '  bash %s auth setup\n' "$0" >&2
    printf '\nCurrent provider state:\n' >&2
    render_auth_doctor "$doctor_payload" >&2
    exit 1
  fi
  if is_running; then
    printf 'Control-plane daemon is already running with PID %s.\n' "$(cat "$PID_FILE")"
    return
  fi

  : > "$CONSOLE_LOG"
  nohup bash -lc "cd \"$HOST_ROOT\" && $(daemon_command)" >>"$CONSOLE_LOG" 2>&1 &
  local pid=$!
  printf '%s\n' "$pid" > "$PID_FILE"
  sleep 1
  if is_running; then
    printf 'Started control-plane daemon in background.\n'
    printf 'PID: %s\n' "$pid"
    printf 'Next: use the same launcher with status, stop, logs, or probe.\n'
    return
  fi
  printf 'Failed to start control-plane daemon. Last console log lines:\n' >&2
  tail -n 20 "$CONSOLE_LOG" >&2 || true
  exit 1
}

run_daemon_foreground() {
  [[ -n "${AAI_TELEGRAM_BOT_TOKEN:-}" ]] || fail "AAI_TELEGRAM_BOT_TOKEN is missing in $ENV_FILE"
  cd "$HOST_ROOT"
  local cmd=(
    bash apps/control-plane/scripts/run-cli.sh telegram serve
    --db "$AAI_CONTROL_PLANE_DB"
    --token "$AAI_TELEGRAM_BOT_TOKEN"
    --approval-config "$AAI_APPROVAL_CONFIG"
    --max-idle-cycles 0
  )
  if [[ -n "${AAI_TELEGRAM_API_BASE:-}" ]]; then
    cmd+=(--api-base "$AAI_TELEGRAM_API_BASE")
  fi
  if [[ -n "${AAI_TELEGRAM_POLL_INTERVAL_MS:-}" ]]; then
    cmd+=(--poll-interval-ms "$AAI_TELEGRAM_POLL_INTERVAL_MS")
  fi
  exec "${cmd[@]}"
}

stop_daemon() {
  if ! is_running; then
    if [[ -f "$PID_FILE" ]]; then
      rm -f "$PID_FILE"
      printf 'Stopped control-plane daemon.\n'
      return
    fi
    rm -f "$PID_FILE"
    printf 'Control-plane daemon is not running.\n'
    return
  fi
  local pid
  pid="$(cat "$PID_FILE")"
  kill "$pid" 2>/dev/null || true
  for _ in 1 2 3 4 5; do
    if ! kill -0 "$pid" 2>/dev/null; then
      break
    fi
    sleep 1
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
  printf 'Stopped control-plane daemon.\n'
}

restart_daemon() {
  stop_daemon
  start_daemon
}

case "$ACTION" in
  start)
    start_daemon
    ;;
  run|foreground)
    run_daemon_foreground
    ;;
  status)
    print_status
    ;;
  stop)
    stop_daemon
    ;;
  restart)
    restart_daemon
    ;;
  logs)
    touch "$STRUCTURED_LOG"
    exec tail -f "$STRUCTURED_LOG"
    ;;
  probe)
    auth_status_flow
    ;;
  usage)
    usage_status_flow
    ;;
  auth)
    case "${ARG2:-setup}" in
      setup)
        auth_setup_flow
        ;;
      status)
        auth_status_flow
        ;;
      *)
        fail "Usage: ... auth <setup|status>"
        ;;
    esac
    ;;
  login)
    [[ -n "$ARG2" ]] || fail "Usage: ... login <claude|codex>"
    login_provider "$ARG2"
    ;;
  *)
    usage
    exit 1
    ;;
esac
