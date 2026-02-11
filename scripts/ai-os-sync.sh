#!/usr/bin/env bash
set -euo pipefail

# Sync AI-OS layer from a template checkout/worktree into this project.
#
# Usage:
#   ./scripts/ai-os-sync.sh <path-to-ai-os-template-worktree>
#
# Example:
#   ./scripts/ai-os-sync.sh ../ai-os-v1.3.0

SRC_ROOT="${1:-}"
if [[ -z "$SRC_ROOT" ]]; then
  echo "Usage: $0 <path-to-ai-os-template-worktree>"
  exit 1
fi

if [[ ! -d "$SRC_ROOT/ai" ]]; then
  echo "ERROR: Source missing ai/ directory: $SRC_ROOT"
  exit 1
fi

echo "Syncing AI-OS from: $SRC_ROOT"
echo "Target project: $(pwd)"

# Target directories (AI-OS layer only)
mkdir -p ai .github docs/workflow docs/roles docs/templates docs/knowledge docs/ai

copy_with_bak() {
  local src="$1"
  local dst="$2"

  if [[ -e "$dst" ]]; then
    # backup (best-effort)
    rm -rf "${dst}.bak" 2>/dev/null || true
    cp -a "$dst" "${dst}.bak" 2>/dev/null || true
    rm -rf "$dst"
  fi

  # copy
  cp -a "$src" "$dst"
}

# Copy trees (AI-OS canonical layer)
copy_with_bak "$SRC_ROOT/ai" "ai"

if [[ -d "$SRC_ROOT/docs/workflow" ]]; then copy_with_bak "$SRC_ROOT/docs/workflow" "docs/workflow"; fi
if [[ -d "$SRC_ROOT/docs/roles" ]]; then copy_with_bak "$SRC_ROOT/docs/roles" "docs/roles"; fi
if [[ -d "$SRC_ROOT/docs/templates" ]]; then copy_with_bak "$SRC_ROOT/docs/templates" "docs/templates"; fi
if [[ -d "$SRC_ROOT/docs/knowledge" ]]; then copy_with_bak "$SRC_ROOT/docs/knowledge" "docs/knowledge"; fi
if [[ -d "$SRC_ROOT/docs/ai" ]]; then copy_with_bak "$SRC_ROOT/docs/ai" "docs/ai"; fi

# Root canonical shims/files (only if present in template)
for f in AGENTS.md PLAYBOOK.md CLAUDE.md README.md; do
  if [[ -f "$SRC_ROOT/$f" ]]; then
    copy_with_bak "$SRC_ROOT/$f" "$f"
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
    copy_with_bak "$SRC_ROOT/$f" "$f"
  fi
done

# Copilot shim
mkdir -p .github
if [[ -f "$SRC_ROOT/.github/copilot-instructions.md" ]]; then
  copy_with_bak "$SRC_ROOT/.github/copilot-instructions.md" ".github/copilot-instructions.md"
fi

# IMPORTANT: Do NOT sync project-specific docs by default:
# - docs/requirements/**, docs/specs/**, docs/decisions/**, docs/releases/**, docs/issues/**
# These are owned by the target project.

# Pin info
TEMPLATE_SHA="UNKNOWN"
TEMPLATE_VERSION="UNKNOWN"
if command -v git >/dev/null 2>&1; then
  TEMPLATE_SHA="$(git -C "$SRC_ROOT" rev-parse HEAD 2>/dev/null || echo UNKNOWN)"
fi
if [[ -f "$SRC_ROOT/docs/ai/AI_OS_VERSION.md" ]]; then
  # best-effort: extract first "Version:" line
  TEMPLATE_VERSION="$(grep -E '^-? *Version:' "$SRC_ROOT/docs/ai/AI_OS_VERSION.md" 2>/dev/null | head -n1 | sed -E 's/.*Version:\s*//')"
  [[ -z "$TEMPLATE_VERSION" ]] && TEMPLATE_VERSION="UNKNOWN"
fi

cat > docs/ai/AI_OS_PIN.md <<EOPIN
# AI-OS Pin

- Source path: $SRC_ROOT
- Template version: $TEMPLATE_VERSION
- Template commit: $TEMPLATE_SHA
- Synced at (UTC): $(date -u +"%Y-%m-%dT%H:%M:%SZ")

Notes:
- This project intentionally vendors the AI-OS files (self-contained).
- Project-specific docs (requirements/specs/decisions/releases/issues) are not synced by this script.
EOPIN

echo "Sync complete."
echo "Review changes:"
echo "  git status"
echo "  git diff"
