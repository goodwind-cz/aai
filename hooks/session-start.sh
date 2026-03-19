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
