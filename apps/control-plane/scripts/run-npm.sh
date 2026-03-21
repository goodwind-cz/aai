#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NODE_BIN=""
NPM_BIN="npm"
NPM_MODE="native"

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
    return 0
  fi

  return 1
}

if select_best_nvm_node; then
  :
elif command -v node >/dev/null 2>&1 && [[ "$(version_major node || true)" -ge 20 ]]; then
  NODE_BIN="node"
  NPM_BIN="npm"
elif command -v node.exe >/dev/null 2>&1; then
  NODE_BIN="node.exe"
  NPM_BIN="npm.cmd"
  NPM_MODE="cmd"
else
  printf '%s\n' "Node.js >=20 is required." >&2
  exit 1
fi

cd "$APP_DIR"

if [[ "$NPM_MODE" == "native" ]]; then
  PATH="$(dirname "$NPM_BIN"):$PATH" "$NPM_BIN" "$@"
  exit $?
fi

if ! command -v cmd.exe >/dev/null 2>&1; then
  printf '%s\n' "cmd.exe is required for npm.cmd fallback." >&2
  exit 1
fi

cmd.exe /c "$NPM_BIN" "$@"
