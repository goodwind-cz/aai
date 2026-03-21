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
ORIGINAL_ARGC=$#

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

write_project_config() {
  local config_path="$1"
  mkdir -p "$(dirname "$config_path")"
  if [[ -f "$config_path" ]]; then
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
  mkdir -p "$(dirname "$env_path")"
  {
    printf 'AAI_TELEGRAM_BOT_TOKEN=%s\n' "$TELEGRAM_BOT_TOKEN"
    printf 'AAI_CONTROL_PLANE_DB=%s\n' "$DB_PATH"
    printf 'AAI_APPROVAL_CONFIG=%s\n' "$HOST_ROOT/apps/control-plane/config/approval-gates.json"
    printf 'AAI_CONTROL_PLANE_LOG=%s\n' "$HOST_ROOT/.runtime/control-plane.log"
    printf 'NODE_NO_WARNINGS=1\n'
  } > "$env_path"
}

write_run_script() {
  local script_path="$1"
  local env_path="$2"
  mkdir -p "$(dirname "$script_path")"
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
bash apps/control-plane/scripts/run-cli.sh telegram serve \\
  --db "\$AAI_CONTROL_PLANE_DB" \\
  --token "\$AAI_TELEGRAM_BOT_TOKEN" \\
  --approval-config "\$AAI_APPROVAL_CONFIG"
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

write_summary() {
  local created_config="$1"
  local claude_detected="$2"
  local codex_detected="$3"
  local claude_recommended="$4"
  local codex_recommended="$5"
  local claude_status="$6"
  local codex_status="$7"

  mkdir -p "$(dirname "$SUMMARY_PATH")"
  "$NODE_BIN" --no-warnings - "$(to_native_path "$SUMMARY_PATH")" "$(to_native_path "$HOST_ROOT")" "$(to_native_path "$MANAGED_REPO_PATH")" "$(to_native_path "$DB_PATH")" "$(to_native_path "$PROJECT_CONFIG_PATH")" "$PROJECT_ID" "$DEFAULT_BRANCH" "$created_config" "$(to_native_path "$claude_detected")" "$(to_native_path "$CLAUDE_SESSION_HOME")" "$claude_recommended" "$claude_status" "$(to_native_path "$codex_detected")" "$(to_native_path "$CODEX_SESSION_HOME")" "$codex_recommended" "$codex_status" <<'EOF'
const fs = require("node:fs");
const [
  summaryPath,
  hostRoot,
  managedRepoPath,
  dbPath,
  projectConfigPath,
  projectId,
  defaultBranch,
  createdConfig,
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
  config_created: createdConfig === "true",
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-path)
      MANAGED_REPO_PATH="$2"
      shift 2
      ;;
    --project-id)
      PROJECT_ID="$2"
      shift 2
      ;;
    --project-config-path)
      PROJECT_CONFIG_PATH="$2"
      shift 2
      ;;
    --db-path)
      DB_PATH="$2"
      shift 2
      ;;
    --default-branch)
      DEFAULT_BRANCH="$2"
      shift 2
      ;;
    --docker-profile)
      DOCKER_PROFILE="$2"
      shift 2
      ;;
    --default-provider-policy)
      DEFAULT_PROVIDER_POLICY="$2"
      shift 2
      ;;
    --planning-provider)
      PLANNING_PROVIDER="$2"
      shift 2
      ;;
    --implementation-provider)
      IMPLEMENTATION_PROVIDER="$2"
      shift 2
      ;;
    --validation-provider)
      VALIDATION_PROVIDER="$2"
      shift 2
      ;;
    --chat-ids)
      CHAT_IDS="$2"
      shift 2
      ;;
    --user-ids)
      USER_IDS="$2"
      shift 2
      ;;
    --telegram-bot-token)
      TELEGRAM_BOT_TOKEN="$2"
      shift 2
      ;;
    --claude-cli-path)
      CLAUDE_CLI_PATH="$2"
      shift 2
      ;;
    --codex-cli-path)
      CODEX_CLI_PATH="$2"
      shift 2
      ;;
    --claude-session-home)
      CLAUDE_SESSION_HOME="$2"
      shift 2
      ;;
    --codex-session-home)
      CODEX_SESSION_HOME="$2"
      shift 2
      ;;
    --summary-path)
      SUMMARY_PATH="$2"
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

if [[ "$WIZARD_MODE" -eq 1 ]]; then
  printf '\nAAI Remote Orchestration Setup\n' >&2
  printf 'This wizard will prepare the host runtime, register one project, and generate the run command.\n\n' >&2
  MANAGED_REPO_PATH="$(prompt_with_default "Managed project repository path" "$MANAGED_REPO_PATH")"
  if [[ ! -d "$MANAGED_REPO_PATH" ]]; then
    fail "Repository path does not exist: $MANAGED_REPO_PATH"
  fi
  MANAGED_REPO_PATH="$(cd "$MANAGED_REPO_PATH" && pwd)"
  PROJECT_ID="$(prompt_with_default "Project id" "$PROJECT_ID")"
  DEFAULT_BRANCH="$(prompt_with_default "Default branch" "$DEFAULT_BRANCH")"
  CHAT_IDS="$(prompt_with_default "Allowed Telegram chat ids (csv, optional)" "$CHAT_IDS")"
  USER_IDS="$(prompt_with_default "Allowed Telegram user ids (csv, optional)" "$USER_IDS")"
  TELEGRAM_BOT_TOKEN="$(prompt_secret "Telegram bot token (leave blank to add later)")"
  PROJECT_CONFIG_PATH="${PROJECT_CONFIG_PATH:-$MANAGED_REPO_PATH/docs/ai/project-overrides/remote-control.yaml}"
  SUMMARY_PATH="${SUMMARY_PATH:-$HOST_ROOT/.runtime/install-summary.${PROJECT_ID}.json}"
fi

resolve_node_bin

command -v git >/dev/null 2>&1 || fail "git is required."
command -v bash >/dev/null 2>&1 || fail "bash is required."

if [[ "$SKIP_DEPS" -eq 0 ]]; then
  (cd "$APP_DIR" && run_npm install --no-fund --no-audit)
fi

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  (cd "$APP_DIR" && run_npm run build)
fi

[[ -f "$APP_DIR/dist/cli.js" ]] || fail "Built CLI missing at $APP_DIR/dist/cli.js"

"$NODE_BIN" --no-warnings "$(to_native_path "$APP_DIR/dist/cli.js")" init --db "$(to_native_path "$DB_PATH")" >/dev/null

created_config="false"
if [[ ! -f "$PROJECT_CONFIG_PATH" ]]; then
  write_project_config "$PROJECT_CONFIG_PATH"
  created_config="true"
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
fi

if [[ "$claude_status" != "ok" ]]; then
  claude_recommended="Install Claude Code CLI manually, run 'claude auth login', verify with 'claude auth status --json', and rerun bash apps/control-plane/scripts/install-host.sh or npm --prefix apps/control-plane run auth:probe -- ..."
fi

if [[ "$codex_status" != "ok" ]]; then
  codex_recommended="Install or reinstall Codex CLI with 'npm install -g @openai/codex@latest', run 'codex' and choose 'Sign in with ChatGPT', then rerun bash apps/control-plane/scripts/install-host.sh or npm --prefix apps/control-plane run auth:probe -- ..."
fi

write_summary "$created_config" "$claude_detected" "$codex_detected" "$claude_recommended" "$codex_recommended" "$claude_status" "$codex_status"

if [[ -n "$TELEGRAM_BOT_TOKEN" ]]; then
  write_runtime_env "$RUNTIME_ENV_PATH"
  write_run_script "$RUN_SCRIPT_PATH" "$RUNTIME_ENV_PATH"
fi

printf 'Install complete.\n'
printf 'Host DB: %s\n' "$DB_PATH"
printf 'Project config: %s\n' "$PROJECT_CONFIG_PATH"
printf 'Install summary: %s\n' "$SUMMARY_PATH"
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
  printf 'Run command: bash %s\n' "$RUN_SCRIPT_PATH"
else
  printf 'Telegram token not provided. Add it later with AAI_TELEGRAM_BOT_TOKEN in %s and run:\n' "$RUNTIME_ENV_PATH"
  printf '  npm --prefix apps/control-plane run telegram:serve -- --db %s --token "$AAI_TELEGRAM_BOT_TOKEN" --approval-config apps/control-plane/config/approval-gates.json\n' "$DB_PATH"
fi
