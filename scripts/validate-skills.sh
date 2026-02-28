#!/usr/bin/env bash
set -euo pipefail

TARGET="$(cd "${1:-$(pwd)}" && pwd)"
echo "Validating skills in: $TARGET"

require_file() {
  local p="$1"
  if [[ ! -f "$p" ]]; then
    echo "ERROR: Missing required file: $p" >&2
    exit 1
  fi
}

for p in \
  "$TARGET/ai/SKILL_CHECK_STATE.prompt.md" \
  "$TARGET/ai/SKILL_INTAKE.prompt.md" \
  "$TARGET/ai/SKILL_LOOP.prompt.md" \
  "$TARGET/ai/SKILL_HITL.prompt.md" \
  "$TARGET/ai/SKILL_BOOTSTRAP.prompt.md" \
  "$TARGET/ai/SKILL_VALIDATE_REPORT.prompt.md"; do
  require_file "$p"
done

if [[ -f "$TARGET/.claude/skills/AAI_DYNAMIC_SKILLS.md" ]]; then
  echo "OK: dynamic skills bootstrap marker exists (.claude/skills/AAI_DYNAMIC_SKILLS.md)"
else
  echo "WARN: Missing .claude/skills/AAI_DYNAMIC_SKILLS.md (bootstrap may not have run yet)."
fi

if [[ -f "$TARGET/docs/ai/LOOP_TICKS.jsonl" ]]; then
  if grep -q '"mode":"skill"' "$TARGET/docs/ai/LOOP_TICKS.jsonl"; then
    echo "OK: LOOP_TICKS.jsonl contains skill-mode evidence."
  else
    echo "WARN: LOOP_TICKS.jsonl has no skill-mode entries yet."
  fi
else
  echo "WARN: Missing docs/ai/LOOP_TICKS.jsonl (no runtime evidence yet)."
fi

echo "Skill validation completed."
