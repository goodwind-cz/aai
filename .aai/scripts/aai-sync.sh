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
  "$DST_ROOT/.claude-plugin" \
  "$DST_ROOT/.codex/skills" \
  "$DST_ROOT/.codex/skills.local" \
  "$DST_ROOT/.cursor/rules" \
  "$DST_ROOT/.gemini/skills" \
  "$DST_ROOT/.gemini/skills.local" \
  "$DST_ROOT/.github" \
  "$DST_ROOT/docs/knowledge" \
  "$DST_ROOT/docs/ai" \
  "$DST_ROOT/hooks"

OVERWRITE_CONFLICTS=()

copy_replace() {
  local src="$1"
  local dst="$2"
  # Git is the backup — no .bak files needed.
  rm -rf "$dst" 2>/dev/null || true
  cp -a "$src" "$dst"
}

file_content_different() {
  local src="$1"
  local dst="$2"
  [[ -f "$src" && -f "$dst" ]] || return 0
  local src_hash dst_hash
  src_hash="$(sha256sum "$src" 2>/dev/null | awk '{print $1}')" || return 0
  dst_hash="$(sha256sum "$dst" 2>/dev/null | awk '{print $1}')" || return 0
  [[ "$src_hash" != "$dst_hash" ]]
}

directory_content_different() {
  local src="$1"
  local dst="$2"
  [[ -d "$src" && -d "$dst" ]] || return 0
  local src_manifest dst_manifest
  src_manifest="$(mktemp)"
  dst_manifest="$(mktemp)"
  (
    cd "$src"
    find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum 2>/dev/null
  ) > "$src_manifest" || true
  (
    cd "$dst"
    find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum 2>/dev/null
  ) > "$dst_manifest" || true
  if ! cmp -s "$src_manifest" "$dst_manifest"; then
    rm -f "$src_manifest" "$dst_manifest"
    return 0
  fi
  rm -f "$src_manifest" "$dst_manifest"
  return 1
}

extract_copilot_project_overrides() {
  local file="$1"
  local start='<!-- AAI-PROJECT-OVERRIDES:START -->'
  local end='<!-- AAI-PROJECT-OVERRIDES:END -->'
  if grep -qF "$start" "$file" 2>/dev/null && grep -qF "$end" "$file" 2>/dev/null; then
    awk -v start="$start" -v end="$end" '
      $0==start {in_block=1; next}
      $0==end {in_block=0; exit}
      in_block {print}
    ' "$file"
  else
    cat "$file"
  fi
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

TECHNOLOGY_TEMPLATE_PATH="$SRC_ROOT/.aai/templates/TECHNOLOGY_TEMPLATE.md"
TARGET_TECHNOLOGY_PATH="$DST_ROOT/docs/TECHNOLOGY.md"

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
    src_skill_md="$src_entry/SKILL.md"
    dst_skill_md="$dst_entry/SKILL.md"
    if [[ -e "$dst_entry" ]]; then
      if [[ -f "$src_skill_md" && -f "$dst_skill_md" ]] && file_content_different "$src_skill_md" "$dst_skill_md"; then
        OVERWRITE_CONFLICTS+=(".claude/skills/$entry_name/SKILL.md|Template skill differs in target. Use AI agent to merge intentional project guidance into a project-owned skill (for example .claude/skills/aai-project-<topic>/SKILL.md) and keep synced template skills unchanged.")
      elif directory_content_different "$src_entry" "$dst_entry"; then
        OVERWRITE_CONFLICTS+=(".claude/skills/$entry_name|Directory differs in target. Use AI agent to extract project-specific content into project-owned skills and keep sync-managed entries as template-only.")
      fi
    fi
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

# docs/TECHNOLOGY.md: seed from template only when missing.
if [[ -f "$TECHNOLOGY_TEMPLATE_PATH" && ! -f "$TARGET_TECHNOLOGY_PATH" ]]; then
  cp -a "$TECHNOLOGY_TEMPLATE_PATH" "$TARGET_TECHNOLOGY_PATH"
  echo "  SEED docs/TECHNOLOGY.md from .aai/templates/TECHNOLOGY_TEMPLATE.md"
fi

# docs/ai: preserve existing runtime data, but sync template files.
# System docs (AUTONOMOUS_LOOP.md, LOCKS.md, etc.) are now in .aai/system/.
if [[ -d "$DST_ROOT/docs/ai" ]]; then
  echo "  PRESERVE docs/ai/ runtime data (STATE.yaml, *.jsonl, decisions.jsonl, reports/)"
fi


# Root canonical shims (AGENTS.md and PLAYBOOK.md are now inside .aai/)
# README.md is synced as README_AAI.md to avoid overwriting the target project's own README.
for f in CLAUDE.md CODEX.md GEMINI.md SKILLS.md; do
  if [[ -f "$SRC_ROOT/$f" && -f "$DST_ROOT/$f" ]] && file_content_different "$SRC_ROOT/$f" "$DST_ROOT/$f"; then
    OVERWRITE_CONFLICTS+=("$f|Target file contains local changes. Use AI agent to merge project-specific instructions into docs/ai/project-overrides/$f and keep synced shim concise.")
  fi
  if [[ -f "$SRC_ROOT/$f" ]]; then
    copy_replace "$SRC_ROOT/$f" "$DST_ROOT/$f"
  fi
done
if [[ -f "$SRC_ROOT/README.md" && -f "$DST_ROOT/README_AAI.md" ]] && file_content_different "$SRC_ROOT/README.md" "$DST_ROOT/README_AAI.md"; then
  OVERWRITE_CONFLICTS+=("README_AAI.md|Target README_AAI.md differs from source README.md. Use AI agent to move project notes into README.md or docs/, and keep README_AAI.md sync-managed.")
fi
if [[ -f "$SRC_ROOT/README.md" ]]; then
  copy_replace "$SRC_ROOT/README.md" "$DST_ROOT/README_AAI.md"
fi

# Copilot shim
mkdir -p "$DST_ROOT/.github"
if [[ -f "$SRC_ROOT/.github/copilot-instructions.md" ]]; then
  dst_copilot="$DST_ROOT/.github/copilot-instructions.md"
  override_dir="$DST_ROOT/docs/ai/project-overrides"
  override_file="$override_dir/copilot-instructions.project.md"
  if [[ -f "$dst_copilot" ]] && file_content_different "$SRC_ROOT/.github/copilot-instructions.md" "$dst_copilot"; then
    mkdir -p "$override_dir"
    project_overrides="$(extract_copilot_project_overrides "$dst_copilot" 2>/dev/null || true)"
    if [[ -z "$project_overrides" && -f "$override_file" ]]; then
      project_overrides="$(cat "$override_file")"
    fi
    printf "%s\n" "$project_overrides" > "$override_file"
    {
      cat "$SRC_ROOT/.github/copilot-instructions.md"
      echo
      echo "---"
      echo "## Project Overrides (auto-merged)"
      echo
      echo "<!-- AAI-PROJECT-OVERRIDES:START -->"
      printf "%s\n" "$project_overrides"
      echo "<!-- AAI-PROJECT-OVERRIDES:END -->"
    } > "$dst_copilot"
    echo "  MERGE preserved project overrides in: $override_file"
  else
    copy_replace "$SRC_ROOT/.github/copilot-instructions.md" "$dst_copilot"
  fi
fi

# Codex skill index
if [[ -d "$SRC_ROOT/.codex/skills" && -d "$DST_ROOT/.codex/skills" ]] && directory_content_different "$SRC_ROOT/.codex/skills" "$DST_ROOT/.codex/skills"; then
  OVERWRITE_CONFLICTS+=(".codex/skills/|Target Codex skills differ from sync source. Use AI agent to migrate project-specific content into project-owned docs and keep sync-managed indexes untouched.")
fi
if [[ -d "$SRC_ROOT/.codex/skills" ]]; then
  copy_replace "$SRC_ROOT/.codex/skills" "$DST_ROOT/.codex/skills"
fi
if [[ -d "$DST_ROOT/.codex/skills.local" ]]; then
  echo "  PRESERVE local Codex dynamic index: $DST_ROOT/.codex/skills.local"
fi

# Gemini skill index
if [[ -d "$SRC_ROOT/.gemini/skills" && -d "$DST_ROOT/.gemini/skills" ]] && directory_content_different "$SRC_ROOT/.gemini/skills" "$DST_ROOT/.gemini/skills"; then
  OVERWRITE_CONFLICTS+=(".gemini/skills/|Target Gemini skills differ from sync source. Use AI agent to migrate project-specific content into project-owned docs and keep sync-managed indexes untouched.")
fi
if [[ -d "$SRC_ROOT/.gemini/skills" ]]; then
  copy_replace "$SRC_ROOT/.gemini/skills" "$DST_ROOT/.gemini/skills"
fi
if [[ -d "$DST_ROOT/.gemini/skills.local" ]]; then
  echo "  PRESERVE local Gemini dynamic index: $DST_ROOT/.gemini/skills.local"
fi

# Claude Code plugin manifest
if [[ -f "$SRC_ROOT/.claude-plugin/plugin.json" ]]; then
  copy_replace "$SRC_ROOT/.claude-plugin/plugin.json" "$DST_ROOT/.claude-plugin/plugin.json"
  echo "  SYNC .claude-plugin/plugin.json"
fi

# Session hooks (cross-platform: Claude Code, Cursor, Gemini, Codex)
if [[ -d "$SRC_ROOT/hooks" ]]; then
  copy_replace "$SRC_ROOT/hooks" "$DST_ROOT/hooks"
  chmod +x "$DST_ROOT/hooks/session-start.sh" 2>/dev/null || true
  echo "  SYNC hooks/"
fi

# Cursor rules
if [[ -f "$SRC_ROOT/.cursor/rules/aai.mdc" ]]; then
  copy_replace "$SRC_ROOT/.cursor/rules/aai.mdc" "$DST_ROOT/.cursor/rules/aai.mdc"
  echo "  SYNC .cursor/rules/aai.mdc"
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

# Ensure docs/ai/reports is fully treated as ephemeral runtime evidence
REPORT_PATTERNS=(
  'docs/ai/reports/**'
  '!docs/ai/reports/'
  '!docs/ai/reports/.gitkeep'
)
REPORT_HEADER='# AAI runtime reports (ephemeral; not project-owned docs)'
if ! grep -qF 'docs/ai/reports/**' "$DST_ROOT/.gitignore" 2>/dev/null; then
  echo -e "\n$REPORT_HEADER" >> "$DST_ROOT/.gitignore"
  for pattern in "${REPORT_PATTERNS[@]}"; do
    echo "$pattern" >> "$DST_ROOT/.gitignore"
  done
  echo "  Added docs/ai/reports runtime ignore rules to $DST_ROOT/.gitignore"
fi

# Ensure synced agent skill indexes are gitignored (sync-managed artifacts)
AGENT_SKILL_PATTERNS=(
  '.claude/skills/'
  '.codex/skills/'
  '.codex/skills.local/'
  '.gemini/skills/'
  '.gemini/skills.local/'
)
missing_agent_skill_patterns=()
for pattern in "${AGENT_SKILL_PATTERNS[@]}"; do
  if ! grep -qxF "$pattern" "$DST_ROOT/.gitignore" 2>/dev/null; then
    missing_agent_skill_patterns+=("$pattern")
  fi
done
if [[ ${#missing_agent_skill_patterns[@]} -gt 0 ]]; then
  echo -e "\n# AAI agent skill sync artifacts (managed by sync)" >> "$DST_ROOT/.gitignore"
  for pattern in "${missing_agent_skill_patterns[@]}"; do
    echo "$pattern" >> "$DST_ROOT/.gitignore"
  done
  echo "  Added agent skill sync patterns to $DST_ROOT/.gitignore"
fi

# Create conflict advisory report for files that were overwritten with differences.
if [[ ${#OVERWRITE_CONFLICTS[@]} -gt 0 ]]; then
  mkdir -p "$DST_ROOT/docs/ai/reports"
  report_path="$DST_ROOT/docs/ai/reports/sync-conflicts-$(date -u +%Y%m%d-%H%M%S).md"
  {
    echo "# Sync Conflict Advisory"
    echo
    echo "- Generated at (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "- Source: $SRC_ROOT"
    echo
    echo "The following target files/directories had local content that differed from sync source and were overwritten."
    echo "Use an AI agent to decide merge strategy per item."
    echo
    echo "## Recommended AI workflow"
    echo "1. Inspect each item with \`git diff -- <path>\` in the target project."
    echo "2. Ask AI to extract project-specific guidance and place it into project-owned docs (for example \`docs/ai/project-overrides/\`)."
    echo "3. Keep sync-managed files as baseline templates to reduce future conflicts."
    echo
    echo "## Overwritten items"
    for conflict in "${OVERWRITE_CONFLICTS[@]}"; do
      path_part="${conflict%%|*}"
      rec_part="${conflict#*|}"
      echo
      echo "- Path: $path_part"
      echo "- Recommendation: $rec_part"
    done
  } > "$report_path"
  echo "  Advisory report: $report_path"
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
- docs/TECHNOLOGY.md is seeded from template only when missing and becomes project-owned after generation.
EOPIN

echo "Sync complete. Review changes in $DST_ROOT:"
echo "  cd $DST_ROOT && git status && git diff"
