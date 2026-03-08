#!/usr/bin/env bash
# Pre-compact context save script
# Saves critical AAI state before Claude Code compresses context messages.
# Source: Inspired by pro-workflow pre-compact hook (https://github.com/rohitg00/pro-workflow)
#
# Usage: Called automatically via Claude Code PreCompact hook
# Configure in .claude/settings.local.json:
#   "hooks": { "PreCompact": [{ "command": "bash .aai/scripts/pre-compact-save.sh" }] }

set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
STATE_FILE="$PROJECT_ROOT/docs/ai/STATE.yaml"
DECISIONS_FILE="$PROJECT_ROOT/docs/ai/decisions.jsonl"
METRICS_FILE="$PROJECT_ROOT/docs/ai/METRICS.jsonl"
OUTPUT_FILE="$PROJECT_ROOT/docs/ai/.session-context.md"
BACKUP_FILE="$PROJECT_ROOT/docs/ai/.pre-compact-state-backup.yaml"

TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Backup STATE.yaml
if [ -f "$STATE_FILE" ]; then
  cp "$STATE_FILE" "$BACKUP_FILE"
fi

# Build context snapshot
{
  echo "# Pre-Compact Context Snapshot"
  echo "# Auto-generated at $TIMESTAMP"
  echo "# Read this file after context compression to restore awareness."
  echo ""

  echo "## Current State"
  if [ -f "$STATE_FILE" ]; then
    echo '```yaml'
    cat "$STATE_FILE"
    echo '```'
  else
    echo "STATE.yaml not found."
  fi
  echo ""

  echo "## Recent Decisions (last 5)"
  if [ -f "$DECISIONS_FILE" ]; then
    echo '```json'
    tail -5 "$DECISIONS_FILE"
    echo '```'
  else
    echo "No decisions log found."
  fi
  echo ""

  echo "## Recent Metrics (last 3)"
  if [ -f "$METRICS_FILE" ]; then
    echo '```json'
    tail -3 "$METRICS_FILE"
    echo '```'
  else
    echo "No metrics log found."
  fi
  echo ""

  echo "## Git Status"
  echo '```'
  git -C "$PROJECT_ROOT" status --short 2>/dev/null || echo "Not a git repository"
  echo '```'
  echo ""

  echo "## Current Branch"
  git -C "$PROJECT_ROOT" branch --show-current 2>/dev/null || echo "Unknown"

} > "$OUTPUT_FILE"

echo "Pre-compact context saved to $OUTPUT_FILE"
