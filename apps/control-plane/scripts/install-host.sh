#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
APP_DIR="$HOST_ROOT/apps/control-plane"
NPM_BIN="npm"

MANAGED_REPO_PATH="$HOST_ROOT"
PROJECT_CONFIG_PATH=""
DB_PATH="$HOST_ROOT/.runtime/control-plane.db"
PROJECT_ID=""
DEFAULT_BRANCH=""
DOCKER_PROFILE="worker-default"
DEFAULT_PROVIDER_POLICY="auto"
PLANNING_PROVIDER="claude"
IMPLEMENTATION_PROVIDER="codex"
VALIDATION_PROVIDER="codex"
CHAT_IDS=""
USER_IDS=""
TELEGRAM_BOT_TOKEN=""
WIZARD_MODE=0
SKIP_DEPS=0
SKIP_BUILD=0
SKIP_PROVIDER_PROBES=0
CLAUDE_CLI_PATH=""
CODEX_CLI_PATH=""
CLAUDE_SESSION_HOME="${HOME}/.claude"
CODEX_SESSION_HOME="${HOME}/.codex"
SUMMARY_PATH=""
RUNTIME_ENV_PATH=""
RUN_SCRIPT_PATH=""
EXISTING_STATE_POLICY=""
ORIGINAL_ARGC=$#
MANAGED_REPO_PATH_SET=0
PROJECT_ID_SET=0
PROJECT_CONFIG_PATH_SET=0
DEFAULT_BRANCH_SET=0
CHAT_IDS_SET=0
USER_IDS_SET=0
TELEGRAM_BOT_TOKEN_SET=0
CLAUDE_CLI_PATH_SET=0
CODEX_CLI_PATH_SET=0
CLAUDE_SESSION_HOME_SET=0
CODEX_SESSION_HOME_SET=0
SUMMARY_PATH_SET=0
DOCKER_PROFILE_SET=0
DEFAULT_PROVIDER_POLICY_SET=0
PLANNING_PROVIDER_SET=0
IMPLEMENTATION_PROVIDER_SET=0
VALIDATION_PROVIDER_SET=0

usage() {
  cat <<'EOF'
Usage:
  bash apps/control-plane/scripts/install-host.sh [options]

Options:
  --repo-path <path>                 Managed project repository to register. Default: current host repo.
  --project-id <id>                  Logical project id. Default: basename of managed repo.
  --project-config-path <path>       Portable project config path. Default: <repo>/docs/ai/project-overrides/remote-control.yaml
  --db-path <path>                   Host runtime DB path. Default: .runtime/control-plane.db under host repo.
  --default-branch <branch>          Default branch for the project. Auto-detected if omitted.
  --docker-profile <name>            Default docker profile. Default: worker-default
  --default-provider-policy <name>   Default provider policy. Default: auto
  --planning-provider <name>         Default planning provider. Default: claude
  --implementation-provider <name>   Default implementation provider. Default: codex
  --validation-provider <name>       Default validation provider. Default: codex
  --chat-ids <csv>                   Allowed Telegram chat ids.
  --user-ids <csv>                   Allowed Telegram user ids.
  --telegram-bot-token <token>       Telegram bot token stored into local runtime env file.
  --claude-cli-path <path>           Override Claude CLI path.
  --codex-cli-path <path>            Override Codex CLI path.
  --claude-session-home <path>       Override Claude session home. Default: ~/.claude
  --codex-session-home <path>        Override Codex session home. Default: ~/.codex
  --summary-path <path>              Install summary JSON path. Default: .runtime/install-summary.<project>.json
  --runtime-env-path <path>          Runtime env file path. Default: .runtime/control-plane.env under host repo.
  --run-script-path <path>           Generated launch script path. Default: .runtime/run-control-plane.sh under host repo.
  --preserve-existing                Keep existing config/runtime files and do not reinitialize the DB.
  --overwrite-existing               Replace existing config/runtime files and reinitialize the DB.
  --skip-deps                        Skip npm install.
  --skip-build                       Skip npm build.
  --skip-provider-probes             Skip provider binary/session probes.
  --wizard                           Prompt for missing values interactively.
  --help                             Show this help.
EOF
}

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

is_tty() {
  [[ -t 0 && -t 1 ]]
}

prompt_with_default() {
  local prompt_text="$1"
  local default_value="$2"
  local answer=""
  if [[ -n "$default_value" ]]; then
    printf '%s [%s]: ' "$prompt_text" "$default_value" >&2
  else
    printf '%s: ' "$prompt_text" >&2
  fi
  IFS= read -r answer || true
  if [[ -z "$answer" ]]; then
    printf '%s\n' "$default_value"
    return
  fi
  printf '%s\n' "$answer"
}

prompt_secret() {
  local prompt_text="$1"
  local answer=""
  printf '%s: ' "$prompt_text" >&2
  IFS= read -r answer || true
  printf '%s\n' "$answer"
}

mask_value() {
  local value="$1"
  local length="${#value}"
  if [[ "$length" -le 8 ]]; then
    printf '********\n'
    return
  fi
  printf '%s...%s\n' "${value:0:4}" "${value: -4}"
}

prompt_secret_with_default() {
  local prompt_text="$1"
  local default_value="$2"
  local answer=""
  if [[ -n "$default_value" ]]; then
    printf '%s [Enter to keep %s]: ' "$prompt_text" "$(mask_value "$default_value")" >&2
  else
    printf '%s: ' "$prompt_text" >&2
  fi
  IFS= read -r answer || true
  if [[ -z "$answer" ]]; then
    printf '%s\n' "$default_value"
    return
  fi
  printf '%s\n' "$answer"
}

prompt_existing_state_policy() {
  local answer=""
  printf '%s\n' "Existing control-plane state detected." >&2
  printf '%s\n' "Choose what to do with the existing config/runtime files: preserve or overwrite." >&2
  printf '%s' "Action [preserve]: " >&2
  IFS= read -r answer || true
  if [[ -z "$answer" ]]; then
    answer="preserve"
  fi
  printf '%s\n' "$answer"
}

prompt_yes_no_default() {
  local prompt_text="$1"
  local default_answer="$2"
  local answer=""
  printf '%s [%s]: ' "$prompt_text" "$default_answer" >&2
  IFS= read -r answer || true
  if [[ -z "$answer" ]]; then
    answer="$default_answer"
  fi
  printf '%s\n' "$answer"
}

detect_project_id() {
  basename "$MANAGED_REPO_PATH" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-'
}

detect_default_branch() {
  local repo_path="$1"
  local branch=""

  if branch="$(git -C "$repo_path" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"; then
    printf '%s\n' "${branch#origin/}"
    return
  fi

  if branch="$(git -C "$repo_path" branch --show-current 2>/dev/null)" && [[ -n "$branch" ]]; then
    printf '%s\n' "$branch"
    return
  fi

  printf 'main\n'
}

version_major() {
  local executable="$1"
  "$executable" -p "process.versions.node.split('.')[0]" 2>/dev/null || return 1
}

select_best_nvm_node() {
  local candidate=""
  local candidate_major=0
  local path

  shopt -s nullglob
  for path in "$HOME"/.nvm/versions/node/*/bin/node; do
    local major
    major="$(version_major "$path" || true)"
    if [[ -n "$major" && "$major" -ge 20 && "$major" -gt "$candidate_major" ]]; then
      candidate="$path"
      candidate_major="$major"
    fi
  done
  shopt -u nullglob

  if [[ -n "$candidate" ]]; then
    NODE_BIN="$candidate"
    NPM_BIN="$(dirname "$candidate")/npm"
    NPM_MODE="native"
    return 0
  fi

  return 1
}

resolve_node_bin() {
  if select_best_nvm_node; then
    return
  fi

  if command -v node >/dev/null 2>&1; then
    local major
    major="$(version_major node || true)"
    if [[ -n "$major" && "$major" -ge 20 ]]; then
      NODE_BIN="node"
      NPM_BIN="npm"
      NPM_MODE="native"
      return
    fi
  fi

  if command -v node.exe >/dev/null 2>&1; then
    local major
    major="$(version_major node.exe || true)"
    if [[ -n "$major" && "$major" -ge 24 ]]; then
      NODE_BIN="node.exe"
      NPM_MODE="cmd"
      return
    fi
  fi

  fail "Node.js >=20 is required. Preferred in WSL: a native Linux Node from ~/.nvm, otherwise node.exe >=24."
}

run_npm() {
  if [[ "$NPM_MODE" == "native" ]]; then
    PATH="$(dirname "$NPM_BIN"):$PATH" "$NPM_BIN" "$@"
    return
  fi

  if ! command -v cmd.exe >/dev/null 2>&1; then
    fail "cmd.exe is required to run npm.cmd when using node.exe fallback."
  fi

  cmd.exe /c npm.cmd "$@"
}

to_native_path() {
  local raw_path="$1"
  if [[ -z "$raw_path" ]]; then
    printf '\n'
    return
  fi

  if [[ "$NODE_BIN" == "node.exe" ]]; then
    if [[ "$raw_path" =~ ^/mnt/([a-zA-Z])/(.*)$ ]]; then
      local drive="${BASH_REMATCH[1]}"
      local tail="${BASH_REMATCH[2]}"
      tail="${tail//\//\\}"
      printf '%s\n' "${drive^}:\\${tail}"
      return
    fi

    if [[ "$raw_path" =~ ^[a-zA-Z]:[\\/].*$ ]]; then
      printf '%s\n' "$raw_path"
      return
    fi

    if command -v pwd >/dev/null 2>&1 && [[ "$raw_path" != /* ]]; then
      raw_path="$(pwd)/$raw_path"
      if [[ "$raw_path" =~ ^/mnt/([a-zA-Z])/(.*)$ ]]; then
        local drive="${BASH_REMATCH[1]}"
        local tail="${BASH_REMATCH[2]}"
        tail="${tail//\//\\}"
        printf '%s\n' "${drive^}:\\${tail}"
        return
      fi
    fi

    printf '%s\n' "$raw_path"
    return
  fi

  printf '%s\n' "$raw_path"
}

resolve_cli_path() {
  local provider="$1"
  local explicit_path="$2"
  if [[ -n "$explicit_path" ]]; then
    printf '%s\n' "$explicit_path"
    return
  fi

  if command -v "$provider" >/dev/null 2>&1; then
    command -v "$provider"
    return
  fi

  printf '\n'
}

read_env_value() {
  local env_path="$1"
  local key="$2"
  if [[ ! -f "$env_path" ]]; then
    return
  fi
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]+=/, "", $0); print; exit }' "$env_path"
}

read_yaml_scalar() {
  local yaml_path="$1"
  local key="$2"
  if [[ ! -f "$yaml_path" ]]; then
    return
  fi
  awk -v key="$key" '
    $0 ~ ("^" key ":[[:space:]]*") {
      sub("^[^:]+:[[:space:]]*", "", $0)
      print
      exit
    }
  ' "$yaml_path"
}

read_yaml_phase_preference() {
  local yaml_path="$1"
  local phase="$2"
  if [[ ! -f "$yaml_path" ]]; then
    return
  fi
  awk -v phase="$phase" '
    /^phase_provider_preferences:[[:space:]]*$/ { in_block=1; next }
    in_block && /^[^[:space:]]/ { in_block=0 }
    in_block && $0 ~ ("^[[:space:]]+" phase ":[[:space:]]*") {
      sub("^[[:space:]]*" phase ":[[:space:]]*", "", $0)
      print
      exit
    }
  ' "$yaml_path"
}

read_summary_value() {
  local summary_path="$1"
  local expression="$2"
  if [[ ! -f "$summary_path" ]]; then
    return
  fi
  "$NODE_BIN" --no-warnings - "$summary_path" "$expression" <<'EOF'
const fs = require("node:fs");
const [summaryPath, expression] = process.argv.slice(2);
const payload = JSON.parse(fs.readFileSync(summaryPath, "utf8"));
const value = Function("data", `return (${expression});`)(payload);
if (value === undefined || value === null) {
  process.exit(0);
}
if (Array.isArray(value)) {
  process.stdout.write(value.join(","));
  process.exit(0);
}
process.stdout.write(String(value));
EOF
}

load_defaults_from_existing_state() {
  local existing_token=""
  local existing_project_id=""
  local existing_default_branch=""
  local existing_chat_ids=""
  local existing_user_ids=""
  local existing_claude_cli=""
  local existing_codex_cli=""
  local existing_claude_home=""
  local existing_codex_home=""
  local existing_docker_profile=""
  local existing_provider_policy=""
  local existing_planning_provider=""
  local existing_implementation_provider=""
  local existing_validation_provider=""

  existing_project_id="$(read_yaml_scalar "$PROJECT_CONFIG_PATH" "project_id" || true)"
  existing_default_branch="$(read_yaml_scalar "$PROJECT_CONFIG_PATH" "default_branch" || true)"
  existing_docker_profile="$(read_yaml_scalar "$PROJECT_CONFIG_PATH" "allowed_docker_profile" || true)"
  existing_provider_policy="$(read_yaml_scalar "$PROJECT_CONFIG_PATH" "default_provider_policy" || true)"
  existing_planning_provider="$(read_yaml_phase_preference "$PROJECT_CONFIG_PATH" "planning" || true)"
  existing_implementation_provider="$(read_yaml_phase_preference "$PROJECT_CONFIG_PATH" "implementation" || true)"
  existing_validation_provider="$(read_yaml_phase_preference "$PROJECT_CONFIG_PATH" "validation" || true)"
  existing_token="$(read_env_value "$RUNTIME_ENV_PATH" "AAI_TELEGRAM_BOT_TOKEN" || true)"
  existing_claude_cli="$(read_env_value "$RUNTIME_ENV_PATH" "AAI_CLAUDE_CLI_PATH" || true)"
  existing_codex_cli="$(read_env_value "$RUNTIME_ENV_PATH" "AAI_CODEX_CLI_PATH" || true)"
  existing_claude_home="$(read_env_value "$RUNTIME_ENV_PATH" "AAI_CLAUDE_SESSION_HOME" || true)"
  existing_codex_home="$(read_env_value "$RUNTIME_ENV_PATH" "AAI_CODEX_SESSION_HOME" || true)"

  if [[ -f "$SUMMARY_PATH" ]]; then
    existing_chat_ids="$(read_summary_value "$SUMMARY_PATH" "data.host_binding?.allowed_telegram_chat_ids || []" || true)"
    existing_user_ids="$(read_summary_value "$SUMMARY_PATH" "data.host_binding?.allowed_telegram_user_ids || []" || true)"
    existing_claude_cli="$(read_summary_value "$SUMMARY_PATH" "data.providers?.claude?.cli_path || ''" || true)"
    existing_codex_cli="$(read_summary_value "$SUMMARY_PATH" "data.providers?.codex?.cli_path || ''" || true)"
    existing_claude_home="$(read_summary_value "$SUMMARY_PATH" "data.providers?.claude?.session_home || ''" || true)"
    existing_codex_home="$(read_summary_value "$SUMMARY_PATH" "data.providers?.codex?.session_home || ''" || true)"
  fi

  if [[ -f "$DB_PATH" && -f "$APP_DIR/dist/cli.js" && -n "$existing_project_id" ]]; then
    local project_json=""
    project_json="$("$NODE_BIN" --no-warnings "$(to_native_path "$APP_DIR/dist/cli.js")" project show \
      --db "$(to_native_path "$DB_PATH")" \
      --project-id "$existing_project_id" 2>/dev/null || true)"
    if [[ -n "$project_json" ]]; then
      existing_chat_ids="$("$NODE_BIN" --no-warnings - "$project_json" <<'EOF'
const [raw] = process.argv.slice(2);
const payload = JSON.parse(raw);
const values = payload.project?.allowed_telegram_chat_ids || [];
process.stdout.write(values.join(","));
EOF
)"
      existing_user_ids="$("$NODE_BIN" --no-warnings - "$project_json" <<'EOF'
const [raw] = process.argv.slice(2);
const payload = JSON.parse(raw);
const values = payload.project?.allowed_telegram_user_ids || [];
process.stdout.write(values.join(","));
EOF
)"
    fi
  fi

  if [[ "$PROJECT_ID_SET" -eq 0 && -n "$existing_project_id" ]]; then
    PROJECT_ID="$existing_project_id"
  fi
  if [[ "$DEFAULT_BRANCH_SET" -eq 0 && -n "$existing_default_branch" ]]; then
    DEFAULT_BRANCH="$existing_default_branch"
  fi
  if [[ "$CHAT_IDS_SET" -eq 0 && -n "$existing_chat_ids" ]]; then
    CHAT_IDS="$existing_chat_ids"
  fi
  if [[ "$USER_IDS_SET" -eq 0 && -n "$existing_user_ids" ]]; then
    USER_IDS="$existing_user_ids"
  fi
  if [[ "$TELEGRAM_BOT_TOKEN_SET" -eq 0 && -n "$existing_token" ]]; then
    TELEGRAM_BOT_TOKEN="$existing_token"
  fi
  if [[ "$DOCKER_PROFILE_SET" -eq 0 && -n "$existing_docker_profile" ]]; then
    DOCKER_PROFILE="$existing_docker_profile"
  fi
  if [[ "$DEFAULT_PROVIDER_POLICY_SET" -eq 0 && -n "$existing_provider_policy" ]]; then
    DEFAULT_PROVIDER_POLICY="$existing_provider_policy"
  fi
  if [[ "$PLANNING_PROVIDER_SET" -eq 0 && -n "$existing_planning_provider" ]]; then
    PLANNING_PROVIDER="$existing_planning_provider"
  fi
  if [[ "$IMPLEMENTATION_PROVIDER_SET" -eq 0 && -n "$existing_implementation_provider" ]]; then
    IMPLEMENTATION_PROVIDER="$existing_implementation_provider"
  fi
  if [[ "$VALIDATION_PROVIDER_SET" -eq 0 && -n "$existing_validation_provider" ]]; then
    VALIDATION_PROVIDER="$existing_validation_provider"
  fi
  if [[ "$CLAUDE_CLI_PATH_SET" -eq 0 && -n "$existing_claude_cli" ]]; then
    CLAUDE_CLI_PATH="$existing_claude_cli"
  fi
  if [[ "$CODEX_CLI_PATH_SET" -eq 0 && -n "$existing_codex_cli" ]]; then
    CODEX_CLI_PATH="$existing_codex_cli"
  fi
  if [[ "$CLAUDE_SESSION_HOME_SET" -eq 0 && -n "$existing_claude_home" ]]; then
    CLAUDE_SESSION_HOME="$existing_claude_home"
  fi
  if [[ "$CODEX_SESSION_HOME_SET" -eq 0 && -n "$existing_codex_home" ]]; then
    CODEX_SESSION_HOME="$existing_codex_home"
  fi
}

write_project_config() {
  local config_path="$1"
  mkdir -p "$(dirname "$config_path")"
  if [[ -f "$config_path" && "$EXISTING_STATE_POLICY" != "overwrite" ]]; then
    return
  fi

  cat > "$config_path" <<EOF
project_id: $PROJECT_ID
default_branch: $DEFAULT_BRANCH
allowed_docker_profile: $DOCKER_PROFILE
default_provider_policy: $DEFAULT_PROVIDER_POLICY
phase_provider_preferences:
  planning: $PLANNING_PROVIDER
  implementation: $IMPLEMENTATION_PROVIDER
  validation: $VALIDATION_PROVIDER
EOF
}

write_runtime_env() {
  local env_path="$1"
  local claude_cli="$2"
  local codex_cli="$3"
  local runtime_dir
  runtime_dir="$(dirname "$env_path")"
  mkdir -p "$runtime_dir"
  if [[ -f "$env_path" && "$EXISTING_STATE_POLICY" != "overwrite" ]]; then
    return
  fi
  {
    printf 'AAI_TELEGRAM_BOT_TOKEN=%s\n' "$TELEGRAM_BOT_TOKEN"
    printf 'AAI_CONTROL_PLANE_DB=%s\n' "$DB_PATH"
    printf 'AAI_APPROVAL_CONFIG=%s\n' "$HOST_ROOT/apps/control-plane/config/approval-gates.json"
    printf 'AAI_CONTROL_PLANE_LOG=%s\n' "$runtime_dir/control-plane.log"
    printf 'AAI_CONTROL_PLANE_CONSOLE_LOG=%s\n' "$runtime_dir/control-plane.console.log"
    printf 'AAI_CONTROL_PLANE_PID_FILE=%s\n' "$runtime_dir/control-plane.pid"
    printf 'AAI_PROJECT_ID=%s\n' "$PROJECT_ID"
    printf 'AAI_PROJECT_CONFIG_PATH=%s\n' "$PROJECT_CONFIG_PATH"
    printf 'AAI_MANAGED_REPO_PATH=%s\n' "$MANAGED_REPO_PATH"
    printf 'AAI_CLAUDE_CLI_PATH=%s\n' "$claude_cli"
    printf 'AAI_CODEX_CLI_PATH=%s\n' "$codex_cli"
    printf 'AAI_CLAUDE_SESSION_HOME=%s\n' "$CLAUDE_SESSION_HOME"
    printf 'AAI_CODEX_SESSION_HOME=%s\n' "$CODEX_SESSION_HOME"
    printf 'NODE_NO_WARNINGS=1\n'
  } > "$env_path"
}

write_run_script() {
  local script_path="$1"
  local env_path="$2"
  mkdir -p "$(dirname "$script_path")"
  if [[ -f "$script_path" && "$EXISTING_STATE_POLICY" != "overwrite" ]]; then
    return
  fi
  cat > "$script_path" <<EOF
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$env_path"
if [[ ! -f "\$ENV_FILE" ]]; then
  ENV_FILE="\$SCRIPT_DIR/$(basename "$env_path")"
fi
source "\$ENV_FILE"
cd "$HOST_ROOT"
bash apps/control-plane/scripts/control-plane-daemon.sh --env "\$ENV_FILE" "\${1:-start}" "\${@:2}"
EOF
  chmod +x "$script_path"
}

probe_provider() {
  local provider="$1"
  local cli_path="$2"
  local session_home="$3"
  if [[ -z "$cli_path" ]]; then
    "$NODE_BIN" --no-warnings "$(to_native_path "$APP_DIR/dist/cli.js")" auth mark-missing \
      --db "$(to_native_path "$DB_PATH")" \
      --provider "$provider" \
      --session-home "$(to_native_path "$session_home")" \
      --message "$provider CLI is not installed on this host. Install it manually, then rerun install-host.sh or auth probe." >/dev/null
    printf 'missing\n'
    return
  fi

  local probe_args=()
  case "$provider" in
    claude)
      probe_args=(--probe-args "auth,status,--json")
      ;;
    codex)
      probe_args=(--probe-args "--help")
      ;;
  esac

  local result
  result="$("$NODE_BIN" --no-warnings "$(to_native_path "$APP_DIR/dist/cli.js")" auth probe \
    --db "$(to_native_path "$DB_PATH")" \
    --provider "$provider" \
    --cli-path "$(to_native_path "$cli_path")" \
    --session-home "$(to_native_path "$session_home")" \
    "${probe_args[@]}")"

  if printf '%s' "$result" | grep -q '"status": "ok"'; then
    printf 'ok\n'
    return
  fi
  if printf '%s' "$result" | grep -q '"status": "missing"'; then
    printf 'missing\n'
    return
  fi
  printf 'error\n'
}

run_interactive_provider_login() {
  local provider="$1"
  local cli_path="$2"
  if [[ -z "$cli_path" || ! -x "$cli_path" && ! -f "$cli_path" ]]; then
    case "$provider" in
      claude)
        printf '%s\n' "Claude CLI is not installed. Install it first, then run 'claude auth login'." >&2
        ;;
      codex)
        printf '%s\n' "Codex CLI is not installed or broken. Reinstall with 'npm install -g @openai/codex@latest', then run 'codex' and choose 'Sign in with ChatGPT'." >&2
        ;;
    esac
    return
  fi

  case "$provider" in
    claude)
      printf '%s\n' "Opening Claude interactive login..." >&2
      "$cli_path" auth login || true
      ;;
    codex)
      printf '%s\n' "Opening Codex interactive login. Choose 'Sign in with ChatGPT', finish login, then exit Codex." >&2
      "$cli_path" || true
      ;;
  esac
}

maybe_offer_provider_login() {
  local provider="$1"
  local current_status="$2"
  local cli_path="$3"
  local session_home="$4"
  if [[ "$WIZARD_MODE" -ne 1 || ! -t 0 || ! -t 1 || "$current_status" == "ok" ]]; then
    return
  fi

  local answer=""
  answer="$(prompt_yes_no_default "Provider '$provider' is $current_status. Open interactive login now?" "y")"
  case "${answer,,}" in
    y|yes)
      run_interactive_provider_login "$provider" "$cli_path"
      ;;
    *)
      return
      ;;
  esac
}

write_summary() {
  local config_action="$1"
  local claude_detected="$2"
  local codex_detected="$3"
  local claude_recommended="$4"
  local codex_recommended="$5"
  local claude_status="$6"
  local codex_status="$7"

  mkdir -p "$(dirname "$SUMMARY_PATH")"
  if [[ -f "$SUMMARY_PATH" && "$EXISTING_STATE_POLICY" != "overwrite" ]]; then
    return
  fi
  "$NODE_BIN" --no-warnings - "$(to_native_path "$SUMMARY_PATH")" "$(to_native_path "$HOST_ROOT")" "$(to_native_path "$MANAGED_REPO_PATH")" "$(to_native_path "$DB_PATH")" "$(to_native_path "$PROJECT_CONFIG_PATH")" "$PROJECT_ID" "$DEFAULT_BRANCH" "$config_action" "$EXISTING_STATE_POLICY" "$CHAT_IDS" "$USER_IDS" "$(to_native_path "$claude_detected")" "$(to_native_path "$CLAUDE_SESSION_HOME")" "$claude_recommended" "$claude_status" "$(to_native_path "$codex_detected")" "$(to_native_path "$CODEX_SESSION_HOME")" "$codex_recommended" "$codex_status" <<'EOF'
const fs = require("node:fs");
const [
  summaryPath,
  hostRoot,
  managedRepoPath,
  dbPath,
  projectConfigPath,
  projectId,
  defaultBranch,
  configAction,
  existingStatePolicy,
  allowedChatIdsRaw,
  allowedUserIdsRaw,
  claudeCliPath,
  claudeSessionHome,
  claudeRecommended,
  claudeStatus,
  codexCliPath,
  codexSessionHome,
  codexRecommended,
  codexStatus
] = process.argv.slice(2);

const payload = {
  installed_at_utc: new Date().toISOString(),
  host_root: hostRoot,
  managed_repo_path: managedRepoPath,
  db_path: dbPath,
  project_config_path: projectConfigPath,
  project_id: projectId,
  default_branch: defaultBranch,
  existing_state_policy: existingStatePolicy,
  project_config_action: configAction,
  host_binding: {
    allowed_telegram_chat_ids: allowedChatIdsRaw ? allowedChatIdsRaw.split(",").filter(Boolean) : [],
    allowed_telegram_user_ids: allowedUserIdsRaw ? allowedUserIdsRaw.split(",").filter(Boolean) : []
  },
  providers: {
    claude: {
      cli_path: claudeCliPath || null,
      session_home: claudeSessionHome,
      installed: claudeStatus === "ok",
      status: claudeStatus || "unknown",
      recommended_action: claudeRecommended || null
    },
    codex: {
      cli_path: codexCliPath || null,
      session_home: codexSessionHome,
      installed: codexStatus === "ok",
      status: codexStatus || "unknown",
      recommended_action: codexRecommended || null
    }
  }
};

fs.writeFileSync(summaryPath, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
EOF
}

collect_existing_state_paths() {
  local path
  local paths=()
  for path in "$PROJECT_CONFIG_PATH" "$DB_PATH" "$SUMMARY_PATH" "$RUNTIME_ENV_PATH" "$RUN_SCRIPT_PATH"; do
    if [[ -e "$path" ]]; then
      paths+=("$path")
    fi
  done
  if [[ "${#paths[@]}" -eq 0 ]]; then
    return
  fi
  printf '%s\n' "${paths[@]}"
}

resolve_existing_state_policy() {
  mapfile -t existing_paths < <(collect_existing_state_paths)
  if [[ "${#existing_paths[@]}" -eq 0 ]]; then
    EXISTING_STATE_POLICY="preserve"
    return
  fi

  if [[ -n "$EXISTING_STATE_POLICY" ]]; then
    return
  fi

  if [[ "$WIZARD_MODE" -eq 1 || -t 0 ]]; then
    printf '%s\n' "Existing files:" >&2
    local path
    for path in "${existing_paths[@]}"; do
      printf '  - %s\n' "$path" >&2
    done
    EXISTING_STATE_POLICY="$(prompt_existing_state_policy)"
  else
    fail "Existing control-plane state detected. Re-run with --preserve-existing or --overwrite-existing."
  fi

  case "$EXISTING_STATE_POLICY" in
    preserve|overwrite)
      ;;
    *)
      fail "Invalid existing state policy: $EXISTING_STATE_POLICY. Use preserve or overwrite."
      ;;
  esac
}

wipe_database_files() {
  rm -f "$DB_PATH" "$DB_PATH-wal" "$DB_PATH-shm"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-path)
      MANAGED_REPO_PATH="$2"
      MANAGED_REPO_PATH_SET=1
      shift 2
      ;;
    --project-id)
      PROJECT_ID="$2"
      PROJECT_ID_SET=1
      shift 2
      ;;
    --project-config-path)
      PROJECT_CONFIG_PATH="$2"
      PROJECT_CONFIG_PATH_SET=1
      shift 2
      ;;
    --db-path)
      DB_PATH="$2"
      shift 2
      ;;
    --default-branch)
      DEFAULT_BRANCH="$2"
      DEFAULT_BRANCH_SET=1
      shift 2
      ;;
    --docker-profile)
      DOCKER_PROFILE="$2"
      DOCKER_PROFILE_SET=1
      shift 2
      ;;
    --default-provider-policy)
      DEFAULT_PROVIDER_POLICY="$2"
      DEFAULT_PROVIDER_POLICY_SET=1
      shift 2
      ;;
    --planning-provider)
      PLANNING_PROVIDER="$2"
      PLANNING_PROVIDER_SET=1
      shift 2
      ;;
    --implementation-provider)
      IMPLEMENTATION_PROVIDER="$2"
      IMPLEMENTATION_PROVIDER_SET=1
      shift 2
      ;;
    --validation-provider)
      VALIDATION_PROVIDER="$2"
      VALIDATION_PROVIDER_SET=1
      shift 2
      ;;
    --chat-ids)
      CHAT_IDS="$2"
      CHAT_IDS_SET=1
      shift 2
      ;;
    --user-ids)
      USER_IDS="$2"
      USER_IDS_SET=1
      shift 2
      ;;
    --telegram-bot-token)
      TELEGRAM_BOT_TOKEN="$2"
      TELEGRAM_BOT_TOKEN_SET=1
      shift 2
      ;;
    --claude-cli-path)
      CLAUDE_CLI_PATH="$2"
      CLAUDE_CLI_PATH_SET=1
      shift 2
      ;;
    --codex-cli-path)
      CODEX_CLI_PATH="$2"
      CODEX_CLI_PATH_SET=1
      shift 2
      ;;
    --claude-session-home)
      CLAUDE_SESSION_HOME="$2"
      CLAUDE_SESSION_HOME_SET=1
      shift 2
      ;;
    --codex-session-home)
      CODEX_SESSION_HOME="$2"
      CODEX_SESSION_HOME_SET=1
      shift 2
      ;;
    --summary-path)
      SUMMARY_PATH="$2"
      SUMMARY_PATH_SET=1
      shift 2
      ;;
    --runtime-env-path)
      RUNTIME_ENV_PATH="$2"
      shift 2
      ;;
    --run-script-path)
      RUN_SCRIPT_PATH="$2"
      shift 2
      ;;
    --preserve-existing)
      EXISTING_STATE_POLICY="preserve"
      shift
      ;;
    --overwrite-existing)
      EXISTING_STATE_POLICY="overwrite"
      shift
      ;;
    --skip-deps)
      SKIP_DEPS=1
      shift
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --skip-provider-probes)
      SKIP_PROVIDER_PROBES=1
      shift
      ;;
    --wizard)
      WIZARD_MODE=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

if [[ "$ORIGINAL_ARGC" -eq 0 ]] && is_tty; then
  WIZARD_MODE=1
fi

MANAGED_REPO_PATH="$(cd "$MANAGED_REPO_PATH" && pwd)"
PROJECT_ID="${PROJECT_ID:-$(detect_project_id)}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-$(detect_default_branch "$MANAGED_REPO_PATH")}"
PROJECT_CONFIG_PATH="${PROJECT_CONFIG_PATH:-$MANAGED_REPO_PATH/docs/ai/project-overrides/remote-control.yaml}"
SUMMARY_PATH="${SUMMARY_PATH:-$HOST_ROOT/.runtime/install-summary.${PROJECT_ID}.json}"
RUNTIME_ENV_PATH="${RUNTIME_ENV_PATH:-$HOST_ROOT/.runtime/control-plane.env}"
RUN_SCRIPT_PATH="${RUN_SCRIPT_PATH:-$HOST_ROOT/.runtime/run-control-plane.sh}"

resolve_node_bin
load_defaults_from_existing_state

if [[ "$WIZARD_MODE" -eq 1 ]]; then
  printf '\nAAI Remote Orchestration Setup\n' >&2
  printf 'This wizard will prepare the host runtime, help with Claude/Codex login, register one project, and generate simple start/status/stop commands.\n\n' >&2
  MANAGED_REPO_PATH="$(prompt_with_default "Managed project repository path" "$MANAGED_REPO_PATH")"
  if [[ ! -d "$MANAGED_REPO_PATH" ]]; then
    fail "Repository path does not exist: $MANAGED_REPO_PATH"
  fi
  MANAGED_REPO_PATH="$(cd "$MANAGED_REPO_PATH" && pwd)"
  if [[ "$PROJECT_CONFIG_PATH_SET" -eq 0 ]]; then
    PROJECT_CONFIG_PATH="$MANAGED_REPO_PATH/docs/ai/project-overrides/remote-control.yaml"
  fi
  if [[ "$PROJECT_ID_SET" -eq 0 ]]; then
    PROJECT_ID="$(detect_project_id)"
  fi
  if [[ "$DEFAULT_BRANCH_SET" -eq 0 ]]; then
    DEFAULT_BRANCH="$(detect_default_branch "$MANAGED_REPO_PATH")"
  fi
  load_defaults_from_existing_state
  PROJECT_ID="$(prompt_with_default "Project id" "$PROJECT_ID")"
  if [[ "$SUMMARY_PATH_SET" -eq 0 ]]; then
    SUMMARY_PATH="$HOST_ROOT/.runtime/install-summary.${PROJECT_ID}.json"
  fi
  load_defaults_from_existing_state
  DEFAULT_BRANCH="$(prompt_with_default "Default branch" "$DEFAULT_BRANCH")"
  CHAT_IDS="$(prompt_with_default "Allowed Telegram chat ids (csv, optional)" "$CHAT_IDS")"
  USER_IDS="$(prompt_with_default "Allowed Telegram user ids (csv, optional)" "$USER_IDS")"
  TELEGRAM_BOT_TOKEN="$(prompt_secret_with_default "Telegram bot token (leave blank to add later)" "$TELEGRAM_BOT_TOKEN")"
fi

resolve_existing_state_policy

command -v git >/dev/null 2>&1 || fail "git is required."
command -v bash >/dev/null 2>&1 || fail "bash is required."

if [[ "$SKIP_DEPS" -eq 0 ]]; then
  (cd "$APP_DIR" && run_npm install --no-fund --no-audit)
fi

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  (cd "$APP_DIR" && run_npm run build)
fi

[[ -f "$APP_DIR/dist/cli.js" ]] || fail "Built CLI missing at $APP_DIR/dist/cli.js"

if [[ "$EXISTING_STATE_POLICY" == "overwrite" ]]; then
  wipe_database_files
fi

"$NODE_BIN" --no-warnings "$(to_native_path "$APP_DIR/dist/cli.js")" init --db "$(to_native_path "$DB_PATH")" >/dev/null

config_action="preserved"
if [[ ! -f "$PROJECT_CONFIG_PATH" ]]; then
  write_project_config "$PROJECT_CONFIG_PATH"
  config_action="created"
elif [[ "$EXISTING_STATE_POLICY" == "overwrite" ]]; then
  write_project_config "$PROJECT_CONFIG_PATH"
  config_action="overwritten"
fi

register_args=(
  "$NODE_BIN" --no-warnings "$(to_native_path "$APP_DIR/dist/cli.js")" project register
  --db "$(to_native_path "$DB_PATH")"
  --project-config "$(to_native_path "$PROJECT_CONFIG_PATH")"
  --repo-path "$(to_native_path "$MANAGED_REPO_PATH")"
)

if [[ -n "$CHAT_IDS" ]]; then
  register_args+=(--chat-ids "$CHAT_IDS")
fi

if [[ -n "$USER_IDS" ]]; then
  register_args+=(--user-ids "$USER_IDS")
fi

"${register_args[@]}" >/dev/null

claude_detected="$(resolve_cli_path claude "$CLAUDE_CLI_PATH")"
codex_detected="$(resolve_cli_path codex "$CODEX_CLI_PATH")"
claude_recommended=""
codex_recommended=""
claude_status="unknown"
codex_status="unknown"

if [[ "$SKIP_PROVIDER_PROBES" -eq 0 ]]; then
  claude_status="$(probe_provider claude "$claude_detected" "$CLAUDE_SESSION_HOME")"
  codex_status="$(probe_provider codex "$codex_detected" "$CODEX_SESSION_HOME")"
  maybe_offer_provider_login claude "$claude_status" "$claude_detected" "$CLAUDE_SESSION_HOME"
  maybe_offer_provider_login codex "$codex_status" "$codex_detected" "$CODEX_SESSION_HOME"
  claude_status="$(probe_provider claude "$claude_detected" "$CLAUDE_SESSION_HOME")"
  codex_status="$(probe_provider codex "$codex_detected" "$CODEX_SESSION_HOME")"
fi

if [[ "$claude_status" != "ok" ]]; then
  claude_recommended="Install Claude Code CLI manually, run 'claude auth login', verify with 'claude auth status --json', and rerun bash apps/control-plane/scripts/install-host.sh or npm --prefix apps/control-plane run auth:probe -- ..."
fi

if [[ "$codex_status" != "ok" ]]; then
  codex_recommended="Install or reinstall Codex CLI with 'npm install -g @openai/codex@latest', run 'codex' and choose 'Sign in with ChatGPT', then rerun bash apps/control-plane/scripts/install-host.sh or npm --prefix apps/control-plane run auth:probe -- ..."
fi

write_summary "$config_action" "$claude_detected" "$codex_detected" "$claude_recommended" "$codex_recommended" "$claude_status" "$codex_status"

if [[ -n "$TELEGRAM_BOT_TOKEN" ]]; then
  write_runtime_env "$RUNTIME_ENV_PATH" "$claude_detected" "$codex_detected"
  write_run_script "$RUN_SCRIPT_PATH" "$RUNTIME_ENV_PATH"
fi

printf 'Install complete.\n'
printf 'Existing state policy: %s\n' "$EXISTING_STATE_POLICY"
printf 'Host DB: %s\n' "$DB_PATH"
printf 'Project config: %s\n' "$PROJECT_CONFIG_PATH"
printf 'Install summary: %s\n' "$SUMMARY_PATH"
printf 'Provider status:\n'
printf '  Claude: %s\n' "$claude_status"
printf '  Codex: %s\n' "$codex_status"
if [[ -n "$claude_detected" ]]; then
  printf 'Claude CLI: %s\n' "$claude_detected"
fi
if [[ -n "$codex_detected" ]]; then
  printf 'Codex CLI: %s\n' "$codex_detected"
fi
if [[ "$claude_status" != "ok" ]]; then
  printf 'Claude CLI not found. Install it manually, or the router will not use Claude.\n'
fi
if [[ "$codex_status" != "ok" ]]; then
  printf 'Codex CLI not found. Install it manually, or the router will not use Codex.\n'
fi
if [[ -n "$TELEGRAM_BOT_TOKEN" ]]; then
  printf 'Quick start:\n'
  printf '  Start in background: bash %s start\n' "$RUN_SCRIPT_PATH"
  printf '  Check status:       bash %s status\n' "$RUN_SCRIPT_PATH"
  printf '  Stop:               bash %s stop\n' "$RUN_SCRIPT_PATH"
  printf '  Restart:            bash %s restart\n' "$RUN_SCRIPT_PATH"
  printf '  Show logs:          bash %s logs\n' "$RUN_SCRIPT_PATH"
  printf '  Re-probe auth:      bash %s probe\n' "$RUN_SCRIPT_PATH"
  printf '  Claude login:       bash %s login claude\n' "$RUN_SCRIPT_PATH"
  printf '  Codex login:        bash %s login codex\n' "$RUN_SCRIPT_PATH"
else
  printf 'Telegram token not provided. Add it later with AAI_TELEGRAM_BOT_TOKEN in %s and run:\n' "$RUNTIME_ENV_PATH"
  printf '  npm --prefix apps/control-plane run install:wizard\n'
fi
