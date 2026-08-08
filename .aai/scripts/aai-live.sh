#!/usr/bin/env bash
#
# aai-live.sh — generate the live-status dashboard, then open it
# (SPEC-DRAFT-spec-live-status-dashboard). No server, no port: the page is a
# plain static file opened directly via the platform opener; `--watch` keeps
# it current through its own meta-refresh (see generate-live-status.mjs).
#
# Usage: bash .aai/scripts/aai-live.sh [--watch] [--interval <s>] [--data-only] [...]
# All args are passed through to generate-live-status.mjs.
#
# Exit codes: 0 ok | 1 node/generator/opener missing.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GEN="$SCRIPT_DIR/generate-live-status.mjs"

command -v node >/dev/null 2>&1 || { echo "aai-live: refused — node not found in PATH" >&2; exit 1; }
[[ -f "$GEN" ]] || { echo "aai-live: refused — generator not found: $GEN" >&2; exit 1; }

OPENER=""
if [[ -n "${AAI_LIVE_OPENER:-}" ]]; then
  OPENER="$AAI_LIVE_OPENER"
elif command -v open >/dev/null 2>&1; then
  OPENER="open"
elif command -v xdg-open >/dev/null 2>&1; then
  OPENER="xdg-open"
else
  echo "aai-live: refused — no browser opener found on PATH (expected 'open' on macOS or 'xdg-open' on Linux; on Windows use aai-live.ps1; set AAI_LIVE_OPENER to override)" >&2
  exit 1
fi

is_data_only() {
  local a
  for a in "$@"; do [[ "$a" == "--data-only" ]] && return 0; done
  return 1
}
is_watch() {
  local a
  for a in "$@"; do [[ "$a" == "--watch" ]] && return 0; done
  return 1
}

cd "$REPO_ROOT"

if is_watch "$@"; then
  # Warm one-shot FULL generate (HTML + JSON, no --data-only) first so there
  # is actually something to open immediately, THEN open, THEN hand off to
  # the (blocking, self-refreshing) watch loop. --data-only here used to
  # suppress the HTML write while the opener unconditionally opened the HTML
  # path anyway (BLOCKING-2, code review CHANGE-0127): every fresh checkout
  # (outputs are gitignored) opened a file that did not exist yet.
  node "$GEN" >/dev/null 2>&1 || true
  if ! is_data_only "$@"; then
    "$OPENER" "$REPO_ROOT/docs/ai/live-status.html" >/dev/null 2>&1 || true
  fi
  exec node "$GEN" "$@"
fi

node "$GEN" "$@"
rc=$?
if [[ "$rc" -eq 0 ]] && ! is_data_only "$@"; then
  "$OPENER" "$REPO_ROOT/docs/ai/live-status.html" >/dev/null 2>&1 || true
fi
exit "$rc"
