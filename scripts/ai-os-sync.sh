#!/usr/bin/env bash
set -euo pipefail

# Push AI-OS layer FROM this repository INTO a target project.
#
# Usage (run from anywhere, script finds its own repo root):
#   ./scripts/ai-os-sync.sh <path-to-target-project>
#
# Example:
#   ./scripts/ai-os-sync.sh ../maty-ai

DST_ROOT="${1:-}"
if [[ -z "$DST_ROOT" ]]; then
  echo "Usage: $0 <path-to-target-project>"
  exit 1
fi

if [[ ! -d "$DST_ROOT" ]]; then
  echo "ERROR: Target directory does not exist: $DST_ROOT"
  exit 1
fi

# Resolve source = this repository's root (two levels up from this script)
SRC_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ ! -d "$SRC_ROOT/ai" ]]; then
  echo "ERROR: Source missing ai/ directory: $SRC_ROOT"
  exit 1
fi

echo "Syncing AI-OS from: $SRC_ROOT"
echo "Target project:     $DST_ROOT"

# Target directories (AI-OS layer only)
mkdir -p \
  "$DST_ROOT/ai" \
  "$DST_ROOT/.claude/skills" \
  "$DST_ROOT/.codex/skills" \
  "$DST_ROOT/.codex/skills.local" \
  "$DST_ROOT/.gemini/skills" \
  "$DST_ROOT/.gemini/skills.local" \
  "$DST_ROOT/.github" \
  "$DST_ROOT/docs/workflow" \
  "$DST_ROOT/docs/roles" \
  "$DST_ROOT/docs/templates" \
  "$DST_ROOT/docs/knowledge" \
  "$DST_ROOT/docs/ai" \
  "$DST_ROOT/scripts"

copy_replace() {
  local src="$1"
  local dst="$2"
  # Git is the backup — no .bak files needed.
  rm -rf "$dst" 2>/dev/null || true
  cp -a "$src" "$dst"
}

# Copy AI-OS canonical layer
copy_replace "$SRC_ROOT/ai" "$DST_ROOT/ai"

# Claude Code skills (session helpers):
# copy template skills file-by-file and preserve target-only local skills.
if [[ -d "$SRC_ROOT/.claude/skills" ]]; then
  mkdir -p "$DST_ROOT/.claude/skills"
  for src_entry in "$SRC_ROOT/.claude/skills/"*; do
    [[ -e "$src_entry" ]] || continue
    entry_name="$(basename "$src_entry")"
    dst_entry="$DST_ROOT/.claude/skills/$entry_name"
    copy_replace "$src_entry" "$dst_entry"
  done
  echo "  PRESERVE target-only skills under: $DST_ROOT/.claude/skills"
fi

if [[ -d "$SRC_ROOT/docs/workflow" ]]; then copy_replace "$SRC_ROOT/docs/workflow" "$DST_ROOT/docs/workflow"; fi
if [[ -d "$SRC_ROOT/docs/roles" ]]; then copy_replace "$SRC_ROOT/docs/roles" "$DST_ROOT/docs/roles"; fi
if [[ -d "$SRC_ROOT/docs/templates" ]]; then copy_replace "$SRC_ROOT/docs/templates" "$DST_ROOT/docs/templates"; fi

# docs/knowledge: file-by-file copy; skip files that no longer contain the
# AI-OS-TEMPLATE sentinel (meaning the target project has filled them with real content).
if [[ -d "$SRC_ROOT/docs/knowledge" ]]; then
  mkdir -p "$DST_ROOT/docs/knowledge"
  for src_file in "$SRC_ROOT/docs/knowledge/"*; do
    [[ -f "$src_file" ]] || continue
    filename="$(basename "$src_file")"
    dst_file="$DST_ROOT/docs/knowledge/$filename"
    if [[ ! -f "$dst_file" ]] || grep -q "AI-OS-TEMPLATE" "$dst_file" 2>/dev/null; then
      cp -a "$src_file" "$dst_file"
    else
      echo "  SKIP (project-owned, sentinel removed): $dst_file"
    fi
  done
fi

# docs/ai: preserve runtime files if they already exist in target
if [[ -d "$SRC_ROOT/docs/ai" ]]; then
  tmp_runtime_backup="$(mktemp -d)"
  for runtime_file in STATE.yaml METRICS.jsonl LOOP_TICKS.jsonl decisions.jsonl; do
    if [[ -f "$DST_ROOT/docs/ai/$runtime_file" ]]; then
      cp -a "$DST_ROOT/docs/ai/$runtime_file" "$tmp_runtime_backup/$runtime_file"
    fi
  done

  copy_replace "$SRC_ROOT/docs/ai" "$DST_ROOT/docs/ai"

  for runtime_file in STATE.yaml METRICS.jsonl LOOP_TICKS.jsonl decisions.jsonl; do
    if [[ -f "$tmp_runtime_backup/$runtime_file" ]]; then
      cp -a "$tmp_runtime_backup/$runtime_file" "$DST_ROOT/docs/ai/$runtime_file"
      echo "  PRESERVE runtime file: $DST_ROOT/docs/ai/$runtime_file"
    fi
  done
  rm -rf "$tmp_runtime_backup"
fi

# Root canonical shims/files
for f in AGENTS.md PLAYBOOK.md CLAUDE.md CODEX.md GEMINI.md README.md; do
  if [[ -f "$SRC_ROOT/$f" ]]; then
    copy_replace "$SRC_ROOT/$f" "$DST_ROOT/$f"
  fi
done

# Canonical helper scripts
for f in \
  scripts/ai-os-sync.ps1 \
  scripts/ai-os-sync.sh \
  scripts/autonomous-loop.ps1 \
  scripts/autonomous-loop.sh
do
  if [[ -f "$SRC_ROOT/$f" ]]; then
    copy_replace "$SRC_ROOT/$f" "$DST_ROOT/$f"
  fi
done

# Copilot shim
mkdir -p "$DST_ROOT/.github"
if [[ -f "$SRC_ROOT/.github/copilot-instructions.md" ]]; then
  copy_replace "$SRC_ROOT/.github/copilot-instructions.md" "$DST_ROOT/.github/copilot-instructions.md"
fi

# Codex skill index
if [[ -d "$SRC_ROOT/.codex/skills" ]]; then
  copy_replace "$SRC_ROOT/.codex/skills" "$DST_ROOT/.codex/skills"
fi
if [[ -d "$DST_ROOT/.codex/skills.local" ]]; then
  echo "  PRESERVE local Codex dynamic index: $DST_ROOT/.codex/skills.local"
fi

# Gemini skill index
if [[ -d "$SRC_ROOT/.gemini/skills" ]]; then
  copy_replace "$SRC_ROOT/.gemini/skills" "$DST_ROOT/.gemini/skills"
fi
if [[ -d "$DST_ROOT/.gemini/skills.local" ]]; then
  echo "  PRESERVE local Gemini dynamic index: $DST_ROOT/.gemini/skills.local"
fi

# IMPORTANT: Do NOT sync project-specific docs:
# - docs/requirements/**, docs/specs/**, docs/decisions/**, docs/releases/**, docs/issues/**
# These are owned by the target project.

# Pin info
TEMPLATE_SHA="UNKNOWN"
TEMPLATE_VERSION="UNKNOWN"
if command -v git >/dev/null 2>&1; then
  TEMPLATE_SHA="$(git -C "$SRC_ROOT" rev-parse HEAD 2>/dev/null || echo UNKNOWN)"
fi
if [[ -f "$SRC_ROOT/docs/ai/AI_OS_VERSION.md" ]]; then
  TEMPLATE_VERSION="$(grep -E '^-? *Version:' "$SRC_ROOT/docs/ai/AI_OS_VERSION.md" 2>/dev/null | head -n1 | sed -E 's/.*Version:\s*//')"
  [[ -z "$TEMPLATE_VERSION" ]] && TEMPLATE_VERSION="UNKNOWN"
fi

cat > "$DST_ROOT/docs/ai/AI_OS_PIN.md" <<EOPIN
# AI-OS Pin

- Source path: $SRC_ROOT
- Template version: $TEMPLATE_VERSION
- Template commit: $TEMPLATE_SHA
- Synced at (UTC): $(date -u +"%Y-%m-%dT%H:%M:%SZ")

Notes:
- This project intentionally vendors the AI-OS files (self-contained).
- Project-specific docs (requirements/specs/decisions/releases/issues) are not synced by this script.
EOPIN

echo "Sync complete. Review changes in $DST_ROOT:"
echo "  cd $DST_ROOT && git status && git diff"
