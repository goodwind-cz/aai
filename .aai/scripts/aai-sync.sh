#!/usr/bin/env bash
set -euo pipefail

# Push AAI layer FROM this repository INTO a target project.
#
# Usage (run from anywhere, script finds its own repo root):
#   ./.aai/scripts/aai-sync.sh <path-to-target-project>
#
# Example:
#   ./.aai/scripts/aai-sync.sh ../maty-ai

DST_ROOT="${1:-}"
if [[ -z "$DST_ROOT" ]]; then
  echo "Usage: $0 <path-to-target-project>"
  exit 1
fi

if [[ ! -d "$DST_ROOT" ]]; then
  echo "ERROR: Target directory does not exist: $DST_ROOT"
  exit 1
fi

# Resolve source = this repository's root (three levels up from this script: .aai/scripts/X.sh)
SRC_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if [[ ! -d "$SRC_ROOT/.aai" ]]; then
  echo "ERROR: Source missing .aai/ directory: $SRC_ROOT"
  exit 1
fi

echo "Syncing AAI from: $SRC_ROOT"
echo "Target project:     $DST_ROOT"

# Target directories (AAI layer only)
mkdir -p \
  "$DST_ROOT/.aai/workflow" \
  "$DST_ROOT/.aai/roles" \
  "$DST_ROOT/.aai/templates" \
  "$DST_ROOT/.aai/scripts" \
  "$DST_ROOT/.aai/system" \
  "$DST_ROOT/.aai/knowledge" \
  "$DST_ROOT/.claude/skills" \
  "$DST_ROOT/.codex/skills" \
  "$DST_ROOT/.codex/skills.local" \
  "$DST_ROOT/.gemini/skills" \
  "$DST_ROOT/.gemini/skills.local" \
  "$DST_ROOT/.github" \
  "$DST_ROOT/docs/knowledge" \
  "$DST_ROOT/docs/ai"

copy_replace() {
  local src="$1"
  local dst="$2"
  # Git is the backup — no .bak files needed.
  rm -rf "$dst" 2>/dev/null || true
  cp -a "$src" "$dst"
}

# ── Legacy cleanup: remove old-layout paths that moved into .aai/ ──────────
LEGACY_CLEANED=0

# Old prompt / subagent directory (was ai/)
if [[ -d "$DST_ROOT/ai" ]]; then
  rm -rf "$DST_ROOT/ai"
  echo "  MIGRATE removed legacy: ai/"
  LEGACY_CLEANED=1
fi

# Old scripts directory (was scripts/) — only remove AAI-owned scripts, keep project scripts
if [[ -d "$DST_ROOT/scripts" ]]; then
  # Remove scripts that now live in .aai/scripts/ (current names)
  for src_script in "$SRC_ROOT/.aai/scripts/"*; do
    [[ -e "$src_script" ]] || continue
    fname="$(basename "$src_script")"
    if [[ -f "$DST_ROOT/scripts/$fname" ]]; then
      rm -f "$DST_ROOT/scripts/$fname"
      echo "  MIGRATE removed legacy: scripts/$fname -> now in .aai/scripts/"
      LEGACY_CLEANED=1
    fi
  done
  # Remove old ai-os-* named scripts (renamed to aai-*)
  for f in "$DST_ROOT/scripts/"ai-os-*; do
    [[ -e "$f" ]] || continue
    fname="$(basename "$f")"
    rm -f "$f"
    echo "  MIGRATE removed legacy: scripts/$fname (old ai-os-* name)"
    LEGACY_CLEANED=1
  done
  # Remove the directory only if it's now empty
  if [[ -z "$(ls -A "$DST_ROOT/scripts" 2>/dev/null)" ]]; then
    rmdir "$DST_ROOT/scripts"
    echo "  MIGRATE removed empty: scripts/"
  fi
fi

# Root files that moved into .aai/
for f in AGENTS.md PLAYBOOK.md; do
  if [[ -f "$DST_ROOT/$f" ]]; then
    rm -f "$DST_ROOT/$f"
    echo "  MIGRATE removed legacy root: $f"
    LEGACY_CLEANED=1
  fi
done

# docs/ subdirs whose content moved into .aai/
for d in docs/workflow docs/roles docs/templates; do
  if [[ -d "$DST_ROOT/$d" ]] && [[ "$(ls -A "$DST_ROOT/$d" 2>/dev/null | grep -v '\.gitkeep')" ]]; then
    rm -rf "$DST_ROOT/$d"
    mkdir -p "$DST_ROOT/$d"
    touch "$DST_ROOT/$d/.gitkeep"
    echo "  MIGRATE cleaned legacy dir: $d/ (kept .gitkeep)"
    LEGACY_CLEANED=1
  fi
done

# System docs that moved from docs/ai/ to .aai/system/
for f in AUTONOMOUS_LOOP.md SUPERPOWERS_INTEGRATION.md DYNAMIC_SKILLS.md PRICING.yaml AAI_PIN.md LOCKS.md; do
  if [[ -f "$DST_ROOT/docs/ai/$f" ]]; then
    rm -f "$DST_ROOT/docs/ai/$f"
    echo "  MIGRATE removed legacy: docs/ai/$f -> now in .aai/system/"
    LEGACY_CLEANED=1
  fi
done

# PATTERNS_UNIVERSAL moved from docs/knowledge/ to .aai/knowledge/
if [[ -f "$DST_ROOT/docs/knowledge/PATTERNS_UNIVERSAL.md" ]]; then
  rm -f "$DST_ROOT/docs/knowledge/PATTERNS_UNIVERSAL.md"
  echo "  MIGRATE removed legacy: docs/knowledge/PATTERNS_UNIVERSAL.md -> now in .aai/knowledge/"
  LEGACY_CLEANED=1
fi

if [[ "$LEGACY_CLEANED" -eq 1 ]]; then
  echo "  Legacy paths migrated to .aai/ structure."
fi

# ── Copy AAI canonical layer (.aai/ is the single source of truth) ──────
# Entry-by-entry so we can merge scripts/ and preserve target-only scripts.
mkdir -p "$DST_ROOT/.aai"

# Top-level files and non-scripts directories: overwrite from source
# Skip scripts/ (merged separately) and cache/ (runtime artifact, not synced)
for item in "$SRC_ROOT/.aai/"*; do
  [[ -e "$item" ]] || continue
  name="$(basename "$item")"
  [[ "$name" == "scripts" || "$name" == "cache" ]] && continue
  copy_replace "$item" "$DST_ROOT/.aai/$name"
done

# Clean stale top-level items in target .aai/ that no longer exist in source (except scripts/, cache/)
for item in "$DST_ROOT/.aai/"*; do
  [[ -e "$item" ]] || continue
  name="$(basename "$item")"
  [[ "$name" == "scripts" || "$name" == "cache" ]] && continue
  if [[ ! -e "$SRC_ROOT/.aai/$name" ]]; then
    rm -rf "$item"
    echo "  CLEAN removed stale: .aai/$name"
  fi
done

# scripts/: file-by-file merge — overwrite source scripts, preserve target-only
mkdir -p "$DST_ROOT/.aai/scripts"
for src_script in "$SRC_ROOT/.aai/scripts/"*; do
  [[ -e "$src_script" ]] || continue
  fname="$(basename "$src_script")"
  copy_replace "$src_script" "$DST_ROOT/.aai/scripts/$fname"
done
for dst_script in "$DST_ROOT/.aai/scripts/"*; do
  [[ -e "$dst_script" ]] || continue
  fname="$(basename "$dst_script")"
  if [[ ! -e "$SRC_ROOT/.aai/scripts/$fname" ]]; then
    echo "  PRESERVE target-only script: .aai/scripts/$fname"
  fi
done

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

# docs/knowledge: file-by-file copy; skip files that no longer contain the
# AAI-TEMPLATE sentinel (meaning the target project has filled them with real content).
if [[ -d "$SRC_ROOT/docs/knowledge" ]]; then
  mkdir -p "$DST_ROOT/docs/knowledge"
  for src_file in "$SRC_ROOT/docs/knowledge/"*; do
    [[ -f "$src_file" ]] || continue
    filename="$(basename "$src_file")"
    dst_file="$DST_ROOT/docs/knowledge/$filename"
    if [[ ! -f "$dst_file" ]] || grep -q "AAI-TEMPLATE" "$dst_file" 2>/dev/null; then
      cp -a "$src_file" "$dst_file"
    else
      echo "  SKIP (project-owned, sentinel removed): $dst_file"
    fi
  done
fi

# docs/ai: only sync runtime TEMPLATE files — preserve existing runtime data.
# System docs (AUTONOMOUS_LOOP.md, LOCKS.md, etc.) are now in .aai/system/.
if [[ -d "$DST_ROOT/docs/ai" ]]; then
  echo "  PRESERVE docs/ai/ runtime data (STATE.yaml, *.jsonl, decisions.jsonl, reports/)"
fi

# Root canonical shims (AGENTS.md and PLAYBOOK.md are now inside .aai/)
for f in CLAUDE.md CODEX.md GEMINI.md README.md SKILLS.md; do
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

# Ensure .aai/ is gitignored in target (it's vendored, not committed)
if ! grep -q '^\.aai/' "$DST_ROOT/.gitignore" 2>/dev/null; then
  echo -e "\n# AAI infrastructure (vendored, not committed)\n.aai/" >> "$DST_ROOT/.gitignore"
  echo "  Added .aai/ to $DST_ROOT/.gitignore"
fi

# Ensure .cloudflare-publish* and .wrangler/ are gitignored (aai-share temp dirs)
for pattern in '.cloudflare-publish*' '.wrangler/'; do
  if ! grep -qF "$pattern" "$DST_ROOT/.gitignore" 2>/dev/null; then
    echo -e "\n$pattern" >> "$DST_ROOT/.gitignore"
    echo "  Added $pattern to $DST_ROOT/.gitignore"
  fi
done

# Ensure expert subagent cache is gitignored (runtime artifact, not committed)
if ! grep -qF '.aai/cache/' "$DST_ROOT/.gitignore" 2>/dev/null; then
  echo -e "\n# Expert subagent cache (fetched on-demand from VoltAgent registry)\n.aai/cache/" >> "$DST_ROOT/.gitignore"
  echo "  Added .aai/cache/ to $DST_ROOT/.gitignore"
fi

# Ensure ephemeral validation reports/screenshots are gitignored
REPORT_PATTERNS=(
  'docs/ai/reports/validation-*.md'
  'docs/ai/reports/LATEST.md'
  'docs/ai/reports/screenshots/'
  'docs/ai/reports/MIGRATION_REPORT_*.md'
)
REPORT_HEADER='# Ephemeral validation reports (reproducible via /aai-validate-report)'
if ! grep -qF 'docs/ai/reports/validation-' "$DST_ROOT/.gitignore" 2>/dev/null; then
  echo -e "\n$REPORT_HEADER" >> "$DST_ROOT/.gitignore"
  for pattern in "${REPORT_PATTERNS[@]}"; do
    echo "$pattern" >> "$DST_ROOT/.gitignore"
  done
  echo "  Added validation report patterns to $DST_ROOT/.gitignore"
fi

# Pin info
TEMPLATE_SHA="UNKNOWN"
TEMPLATE_VERSION="UNKNOWN"
if command -v git >/dev/null 2>&1; then
  TEMPLATE_SHA="$(git -C "$SRC_ROOT" rev-parse HEAD 2>/dev/null || echo UNKNOWN)"
fi
if [[ -f "$SRC_ROOT/docs/ai/AAI_VERSION.md" ]]; then
  TEMPLATE_VERSION="$(grep -E '^-? *Version:' "$SRC_ROOT/docs/ai/AAI_VERSION.md" 2>/dev/null | head -n1 | sed -E 's/.*Version:\s*//')"
  [[ -z "$TEMPLATE_VERSION" ]] && TEMPLATE_VERSION="UNKNOWN"
fi

cat > "$DST_ROOT/.aai/system/AAI_PIN.md" <<EOPIN
# AAI Pin

- Source path: $SRC_ROOT
- Template version: $TEMPLATE_VERSION
- Template commit: $TEMPLATE_SHA
- Synced at (UTC): $(date -u +"%Y-%m-%dT%H:%M:%SZ")

Notes:
- This project intentionally vendors the AAI files (self-contained).
- Project-specific docs (requirements/specs/decisions/releases/issues) are not synced by this script.
EOPIN

echo "Sync complete. Review changes in $DST_ROOT:"
echo "  cd $DST_ROOT && git status && git diff"
