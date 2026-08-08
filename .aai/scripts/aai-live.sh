#!/usr/bin/env bash
#
# aai-live.sh — generate the live-status dashboard, then open it
# (SPEC-0114-spec-live-status-dashboard). No server, no port: the page is a
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

# resolve_output_path <args...> -> the value of the invocation's own
# --output flag, or the generator's own default when absent. Used so the
# opener (below) always targets the SAME file the watch loop is about to
# keep rewriting, never the hardcoded default path.
resolve_output_path() {
  local out="docs/ai/live-status.html"
  local prev=""
  local a
  for a in "$@"; do
    [[ "$prev" == "--output" ]] && out="$a"
    prev="$a"
  done
  printf '%s' "$out"
}

cd "$REPO_ROOT"

if is_watch "$@"; then
  # Warm one-shot generate first so there is actually something to open
  # immediately, THEN open, THEN hand off to the (blocking, self-refreshing)
  # watch loop.
  #
  # The warm-up forwards the invocation's OWN args (minus --watch itself, so
  # the warm-up is one-shot and does not block) instead of running the
  # generator bare. Two regressions this closes (NNB-1/NNB-2, code review
  # 102429Z, introduced by the prior remediation of BLOCKING-2):
  #   - a bare `node "$GEN"` always wrote the HTML, even when the invocation
  #     passed --data-only to suppress it — the flag was silently ignored
  #     for exactly the warm-up write.
  #   - a bare `node "$GEN"` also ignored --output/--home/--interval/--cache/
  #     --spool-dir, so under e.g. `--watch --output custom/page.html` the
  #     opener (hardcoded to docs/ai/live-status.html) opened a frozen
  #     snapshot at the DEFAULT path while the watch loop kept rewriting
  #     custom/page.html — a page that looks live and is permanently stale.
  # Passing the same args through makes the warm-up honor --data-only (no
  # HTML written, matching the flag's own promise) and write to the same
  # --output the opener below now resolves from those same args.
  WARMUP_ARGS=()
  for ARG in "$@"; do
    [[ "$ARG" == "--watch" ]] && continue
    WARMUP_ARGS+=("$ARG")
  done
  # BLOCKING-I (re-review 105110Z): bare `"${WARMUP_ARGS[@]}"` is fatal under
  # this file's own `set -u` on bash < 4.4 — including bash 3.2.57, the ONLY
  # bash on stock macOS — when WARMUP_ARGS is empty, which is exactly the
  # documented bare `--watch` invocation (no other flags). Plain
  # `"${WARMUP_ARGS[@]:-}"` is not safe either: on an empty array it still
  # passes ONE empty-string argument through to the generator rather than
  # zero arguments. `${WARMUP_ARGS[@]+"${WARMUP_ARGS[@]}"}` is the idiom that
  # is provably correct in both cases — parameter-expansion existence test
  # (`+`) short-circuits to nothing when the array has zero elements, and
  # expands each element quoted (no word-splitting) when it does not.
  node "$GEN" ${WARMUP_ARGS[@]+"${WARMUP_ARGS[@]}"} >/dev/null 2>&1 || true
  if ! is_data_only "$@"; then
    OPEN_TARGET="$(resolve_output_path "$@")"
    case "$OPEN_TARGET" in
      /*) : ;;
      *) OPEN_TARGET="$REPO_ROOT/$OPEN_TARGET" ;;
    esac
    "$OPENER" "$OPEN_TARGET" >/dev/null 2>&1 || true
  fi
  exec node "$GEN" "$@"
fi

node "$GEN" "$@"
rc=$?
if [[ "$rc" -eq 0 ]] && ! is_data_only "$@"; then
  "$OPENER" "$REPO_ROOT/docs/ai/live-status.html" >/dev/null 2>&1 || true
fi
exit "$rc"
