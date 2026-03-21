#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CLI_PATH="$APP_DIR/dist/cli.js"
REPO_ROOT="$(cd "$APP_DIR/../.." && pwd)"
NODE_BIN=""

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
      return
    fi
  fi

  if command -v node.exe >/dev/null 2>&1; then
    local major
    major="$(version_major node.exe || true)"
    if [[ -n "$major" && "$major" -ge 24 ]]; then
      NODE_BIN="node.exe"
      return
    fi
  fi

  printf '%s\n' "Node.js >=20 is required. Preferred in WSL: a native Linux Node from ~/.nvm, otherwise node.exe >=24." >&2
  exit 1
}

to_native_path() {
  local raw_path="$1"
  if [[ -z "$raw_path" ]]; then
    printf '\n'
    return
  fi

  if [[ "$raw_path" =~ ^[a-zA-Z]:[\\/].*$ ]]; then
    printf '%s\n' "$raw_path"
    return
  fi

  if [[ "$raw_path" != /* ]]; then
    raw_path="$REPO_ROOT/$raw_path"
  fi

  if [[ "$NODE_BIN" != "node.exe" ]]; then
    printf '%s\n' "$raw_path"
    return
  fi

  if [[ "$raw_path" =~ ^/mnt/([a-zA-Z])/(.*)$ ]]; then
    local drive="${BASH_REMATCH[1]}"
    local tail="${BASH_REMATCH[2]}"
    tail="${tail//\//\\}"
    printf '%s\n' "${drive^}:\\${tail}"
    return
  fi

  if [[ "$raw_path" == /* ]]; then
    printf '%s\n' "$raw_path"
    return
  fi
  printf '%s\n' "$raw_path"
}

convert_mount_csv() {
  local raw="$1"
  if [[ -z "$raw" ]]; then
    printf '\n'
    return
  fi

  local IFS=','
  local converted=()
  local entry
  for entry in $raw; do
    local source
    local target
    local mode=""
    IFS='|' read -r source target mode <<<"$entry"
    source="$(to_native_path "$source")"
    if [[ -n "$mode" ]]; then
      converted+=("${source}|${target}|${mode}")
    else
      converted+=("${source}|${target}")
    fi
  done

  local joined=""
  local item
  for item in "${converted[@]}"; do
    if [[ -n "$joined" ]]; then
      joined+=","
    fi
    joined+="$item"
  done
  printf '%s\n' "$joined"
}

resolve_node_bin
export NODE_NO_WARNINGS=1

if [[ ! -f "$CLI_PATH" ]]; then
  printf '%s\n' "Missing built CLI at $CLI_PATH. Run npm --prefix apps/control-plane run build first." >&2
  exit 1
fi

translated_args=()
expect_path_flag=""
expect_mount_flag=""

for arg in "$@"; do
  if [[ -n "$expect_path_flag" ]]; then
    translated_args+=("$(to_native_path "$arg")")
    expect_path_flag=""
    continue
  fi

  if [[ -n "$expect_mount_flag" ]]; then
    translated_args+=("$(convert_mount_csv "$arg")")
    expect_mount_flag=""
    continue
  fi

  case "$arg" in
    --db|--project-config|--repo-path|--cli-path|--session-home|--usage-file|--artifact-path|--manifest|--worker-command|--docker-bin|--config|--allowlist|--approval-config|--worktrees-root|--manifest-path|--mount-allowlist)
      translated_args+=("$arg")
      expect_path_flag="$arg"
      ;;
    --mounts|--read-only-mounts|--extra-mounts)
      translated_args+=("$arg")
      expect_mount_flag="$arg"
      ;;
    *)
      translated_args+=("$arg")
      ;;
  esac
done

exec "$NODE_BIN" --no-warnings "$(to_native_path "$CLI_PATH")" "${translated_args[@]}"
