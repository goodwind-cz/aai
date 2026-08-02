#!/usr/bin/env bash
# AAI session-start hook — injects meta-skill context at session start.
# Compatible with: Claude Code, Cursor, Gemini CLI, Codex, GitHub Copilot.
# Pattern adapted from https://github.com/obra/superpowers

set -euo pipefail

# Locate project root (where AGENTS.md lives)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
META_SKILL="$PROJECT_ROOT/.aai/SKILL_META.prompt.md"

if [[ ! -f "$META_SKILL" ]]; then
  # No meta-skill file — nothing to inject
  exit 0
fi

CONTENT="$(cat "$META_SKILL")"

# Best-effort new-release check (spec-auto-update-config). Runs update-check.mjs
# and appends its notify/degrade/sync line onto CONTENT so it rides the existing
# emit path. This is RUNTIME-CRITICAL: a check failure, timeout, or slow network
# must NEVER break, block, or delay session start — every path below is guarded
# and the whole thing is bounded by a self-contained watchdog (no dependency on
# a `timeout` binary, which macOS lacks). Errors are swallowed; on any problem
# CONTENT is emitted unchanged, exactly as before this hook existed.
UPDATE_CHECK="$PROJECT_ROOT/.aai/scripts/update-check.mjs"
if [[ -f "$UPDATE_CHECK" ]] && command -v node >/dev/null 2>&1; then
  _uc_timeout="${AAI_UPDATE_CHECK_TIMEOUT_S:-15}"
  [[ "$_uc_timeout" =~ ^[0-9]+$ ]] || _uc_timeout=15
  _uc_out="$(mktemp "${TMPDIR:-/tmp}/aai-update-check.XXXXXX" 2>/dev/null || true)"
  if [[ -n "$_uc_out" ]]; then
    # exec replaces the backgrounded subshell with node, so $! is node's own PID
    # and the watchdog's kill actually reaches it.
    { cd "$PROJECT_ROOT" && exec node "$UPDATE_CHECK"; } >"$_uc_out" 2>/dev/null &
    _uc_pid=$!
    { sleep "$_uc_timeout"; kill -9 "$_uc_pid"; } >/dev/null 2>&1 &
    _uc_watch=$!
    wait "$_uc_pid" 2>/dev/null || true
    kill "$_uc_watch" 2>/dev/null || true
    wait "$_uc_watch" 2>/dev/null || true
    _uc_note="$(cat "$_uc_out" 2>/dev/null || true)"
    rm -f "$_uc_out" 2>/dev/null || true
    if [[ -n "$_uc_note" ]]; then
      CONTENT="$CONTENT

$_uc_note"
    fi
  fi
fi

# Best-effort orphaned-runaway sweep (CHANGE orphan-sweep-session-hook). Kills
# launchd-adopted agent-shell wrappers that have burned >=20% CPU for >=2h —
# the 2026-07-29 busy-loop leak class (37 procs, ~15 cores, 4 days). Same
# never-block contract as update-check above: bounded by a watchdog, all
# errors swallowed, CONTENT emitted unchanged on any problem. Its one-line
# kill report (silent when nothing found) rides the same emit path so the
# session SEES what was reaped. macOS/Linux only by construction (the script
# no-ops without `ps`).
ORPHAN_SWEEP="$PROJECT_ROOT/.aai/scripts/orphan-sweep.mjs"
if [[ -f "$ORPHAN_SWEEP" ]] && command -v node >/dev/null 2>&1; then
  _os_timeout="${AAI_ORPHAN_SWEEP_TIMEOUT_S:-10}"
  [[ "$_os_timeout" =~ ^[0-9]+$ ]] || _os_timeout=10
  _os_out="$(mktemp "${TMPDIR:-/tmp}/aai-orphan-sweep.XXXXXX" 2>/dev/null || true)"
  if [[ -n "$_os_out" ]]; then
    { cd "$PROJECT_ROOT" && exec node "$ORPHAN_SWEEP"; } >"$_os_out" 2>/dev/null &
    _os_pid=$!
    { sleep "$_os_timeout"; kill -9 "$_os_pid"; } >/dev/null 2>&1 &
    _os_watch=$!
    wait "$_os_pid" 2>/dev/null || true
    kill "$_os_watch" 2>/dev/null || true
    wait "$_os_watch" 2>/dev/null || true
    _os_note="$(cat "$_os_out" 2>/dev/null || true)"
    rm -f "$_os_out" 2>/dev/null || true
    if [[ -n "$_os_note" ]]; then
      CONTENT="$CONTENT

$_os_note"
    fi
  fi
fi

ESCAPED="$(printf '%s' "$CONTENT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"

# Detect platform and emit in the correct format
if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
  # Claude Code plugin hook format
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","output":%s}}' "$ESCAPED"

elif [[ -n "${CURSOR_WORKSPACE_PATH:-}" || -n "${CURSOR_RULES_PATH:-}" ]]; then
  # Cursor
  printf '{"additional_context":%s}' "$ESCAPED"

elif [[ -n "${GEMINI_PROJECT_ROOT:-}" || -n "${GEMINI_CLI:-}" ]]; then
  # Gemini CLI
  printf '%s' "$CONTENT"

else
  # Codex / fallback — print as plain text to stdout (picked up as system context)
  printf '%s' "$CONTENT"
fi
