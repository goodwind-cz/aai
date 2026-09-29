#!/usr/bin/env bash
# Antigravity CLI loads project skills from .agents/skills/{skill}/SKILL.md.
# Home trees (~/.gemini/antigravity-cli/skills and ~/.gemini/skills) are lookup
# locations, not install targets. This suite locks that decision.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_NAME="aai-antigravity-project-skills"

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }

test_001_project_mirror_is_agents_skills() {
  local sync="$PROJECT_ROOT/.aai/scripts/sync-harness-skills.mjs"
  local out rc=0 sample rel mirror
  [[ -f "$sync" ]] || log_fail "TEST-001: missing $sync"
  set +e
  out="$(node "$sync" --check 2>&1)"
  rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "TEST-001: sync-harness-skills --check exited $rc ($out)"

  sample=""
  for sample in "$PROJECT_ROOT"/.claude/skills/*/SKILL.md; do
    [[ -f "$sample" ]] || log_fail "TEST-001: no source SKILL.md under .claude/skills"
    break
  done
  rel="${sample#"$PROJECT_ROOT/.claude/skills/"}"
  mirror="$PROJECT_ROOT/.agents/skills/$rel"
  [[ -f "$mirror" ]] || log_fail "TEST-001: missing project mirror $mirror"
  cmp -s "$sample" "$mirror" \
    || log_fail "TEST-001: .agents/skills/$rel is not byte-identical to the source"
  log_pass "TEST-001: .agents/skills matches .claude/skills and sync --check exits 0"
}

test_002_does_not_publish_into_home() {
  local publisher="$PROJECT_ROOT/.aai/scripts/publish-home-skills.mjs"
  local profiles="$PROJECT_ROOT/.aai/system/PROFILES.yaml"
  [[ ! -e "$publisher" ]] \
    || log_fail "TEST-002: $publisher must not exist"
  if grep -qF 'publish-home-skills.mjs' "$profiles"; then
    log_fail "TEST-002: PROFILES.yaml still lists publish-home-skills.mjs"
  fi
  if grep -R -q -F --include='*.mjs' 'antigravity-cli' "$PROJECT_ROOT/.aai/scripts"; then
    log_fail "TEST-002: a script under .aai/scripts still names antigravity-cli"
  fi
  log_pass "TEST-002: no home publisher and no antigravity-cli install path in .aai/scripts"
}

main() {
  echo "=== AAI Skill Test: $TEST_NAME ==="
  if [[ $# -gt 0 ]]; then
    declare -F "$1" >/dev/null || { echo "Unknown test: $1" >&2; exit 2; }
    "$1"
    echo "=== $TEST_NAME: SELECTED PASSED ($1) ==="
    return
  fi
  test_001_project_mirror_is_agents_skills
  test_002_does_not_publish_into_home
  echo "=== $TEST_NAME: ALL PASSED ==="
}

main "$@"
