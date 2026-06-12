#!/usr/bin/env bash
#
# Test: aai-bootstrap skill
# Verifies the real bootstrap generator against an isolated project fixture.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-bootstrap"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOOTSTRAP_SCRIPT="$PROJECT_ROOT/.aai/scripts/aai-bootstrap.sh"

cleanup() {
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}
trap cleanup EXIT

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

assert_file() {
  local path="$1"
  [[ -f "$path" ]] || log_fail "Missing file: $path"
}

assert_not_file() {
  local path="$1"
  [[ ! -f "$path" ]] || log_fail "Unexpected file exists: $path"
}

assert_contains() {
  local path="$1"
  local text="$2"
  grep -qF "$text" "$path" || log_fail "Expected '$text' in $path"
}

assert_not_contains() {
  local path="$1"
  local text="$2"
  if grep -qF "$text" "$path"; then
    log_fail "Did not expect '$text' in $path"
  fi
}

check_deps() {
  log_info "Checking dependencies..."
  command -v bash >/dev/null 2>&1 || log_skip "bash not found"
  [[ -f "$BOOTSTRAP_SCRIPT" ]] || log_fail "Bootstrap script not found: $BOOTSTRAP_SCRIPT"
  bash -n "$BOOTSTRAP_SCRIPT" || log_fail "Bootstrap script has syntax errors"
  log_pass "Dependencies checked"
}

setup_fixture() {
  log_info "Setting up isolated fixture..."
  TEST_DIR="$(mktemp -d /tmp/aai-test-bootstrap-XXXXXX)"
  cd "$TEST_DIR"

  cat > package.json <<'JSON'
{
  "name": "bootstrap-fixture",
  "version": "1.0.0",
  "scripts": {
    "test": "jest",
    "test:e2e": "playwright test",
    "build": "vite build",
    "lint": "eslint ."
  },
  "devDependencies": {
    "@playwright/test": "^1.40.0",
    "eslint": "^8.0.0",
    "jest": "^29.0.0",
    "vite": "^5.0.0"
  }
}
JSON

  cat > jest.config.js <<'JS'
module.exports = {
  testEnvironment: "node"
};
JS

  cat > playwright.config.js <<'JS'
module.exports = {
  testDir: "./e2e",
  use: { baseURL: "http://localhost:3000" }
};
JS

  cat > vite.config.js <<'JS'
export default {};
JS

  cat > eslint.config.js <<'JS'
export default [];
JS

  cat > pyproject.toml <<'TOML'
[project]
name = "bootstrap-fixture"
version = "1.0.0"

[project.optional-dependencies]
dev = [
  "pydantic-monty",
  "ruff"
]

[tool.ruff]
line-length = 100
TOML

  mkdir -p app e2e docs/knowledge
  cat > app/login.ts <<'TS'
export function requireAuth() {
  return true;
}
TS

  cat > .env.e2e <<'ENV'
E2E_EMAIL=user@example.test
E2E_PASSWORD=not-real
ENV

  log_pass "Fixture created: $TEST_DIR"
}

test_dry_run_has_no_writes() {
  log_info "Test: dry-run previews without writing..."
  bash "$BOOTSTRAP_SCRIPT" "$TEST_DIR" --dry-run > "$TEST_DIR/dry-run.log"

  assert_contains "$TEST_DIR/dry-run.log" "Mode: dry-run"
  assert_contains "$TEST_DIR/dry-run.log" "/aai-test-unit -> npm test"
  assert_contains "$TEST_DIR/dry-run.log" "/aai-test-e2e -> npm run test:e2e"
  assert_contains "$TEST_DIR/dry-run.log" "/aai-python-monty ->"
  assert_contains "$TEST_DIR/dry-run.log" "Authentication detected"
  assert_not_file "$TEST_DIR/.claude/skills/aai-test-unit/SKILL.md"

  log_pass "Dry-run did not write files"
}

test_generate_dynamic_skills() {
  log_info "Test: generates dynamic skills from real detection..."
  bash "$BOOTSTRAP_SCRIPT" "$TEST_DIR" > "$TEST_DIR/apply.log"

  local unit="$TEST_DIR/.claude/skills/aai-test-unit/SKILL.md"
  local e2e="$TEST_DIR/.claude/skills/aai-test-e2e/SKILL.md"
  local build="$TEST_DIR/.claude/skills/aai-build/SKILL.md"
  local lint="$TEST_DIR/.claude/skills/aai-lint/SKILL.md"
  local monty="$TEST_DIR/.claude/skills/aai-python-monty/SKILL.md"
  local marker="$TEST_DIR/.claude/skills/AAI_DYNAMIC_SKILLS.md"
  local codex="$TEST_DIR/.codex/skills.local/README.md"
  local gemini="$TEST_DIR/.gemini/skills.local/README.md"

  for path in "$unit" "$e2e" "$build" "$lint" "$monty" "$marker" "$codex" "$gemini"; do
    assert_file "$path"
  done

  assert_contains "$unit" "AAI-DYNAMIC-SKILL:START"
  assert_contains "$unit" "npm test"
  assert_contains "$e2e" "npm run test:e2e"
  assert_contains "$e2e" "Authentication detected"
  assert_contains "$e2e" "E2E_EMAIL"
  assert_contains "$e2e" "E2E_PASSWORD"
  assert_not_contains "$e2e" "user@example.test"
  assert_not_contains "$e2e" "not-real"
  assert_contains "$build" "npm run build"
  assert_contains "$lint" "npm run lint"
  assert_contains "$monty" "pydantic-monty available"
  assert_contains "$monty" "Monty Scratchpad Workflow"
  assert_contains "$monty" "final validation evidence"
  assert_contains "$monty" "Never expose shell execution"
  assert_contains "$marker" "Python"
  assert_contains "$marker" "aai-python-monty"
  assert_contains "$marker" "Playwright"
  assert_contains "$marker" "Jest"
  assert_contains "$marker" "Vite"
  assert_contains "$codex" ".claude/skills/aai-test-unit/SKILL.md"
  assert_contains "$codex" ".claude/skills/aai-python-monty/SKILL.md"
  assert_contains "$gemini" ".claude/skills/aai-build/SKILL.md"
  assert_contains "$TEST_DIR/.gitignore" ".claude/skills/.cache"
  assert_contains "$TEST_DIR/.gitignore" ".codex/skills.local/.cache"
  assert_contains "$TEST_DIR/.gitignore" ".gemini/skills.local/.cache"

  log_pass "Dynamic skills generated from fixture"
}

test_managed_skill_is_stable() {
  log_info "Test: managed skill can be regenerated without content churn..."
  local unit="$TEST_DIR/.claude/skills/aai-test-unit/SKILL.md"
  local monty="$TEST_DIR/.claude/skills/aai-python-monty/SKILL.md"
  local before_unit before_monty
  before_unit="$(cksum "$unit")"
  before_monty="$(cksum "$monty")"

  bash "$BOOTSTRAP_SCRIPT" "$TEST_DIR" > "$TEST_DIR/reapply.log"

  local after_unit after_monty
  after_unit="$(cksum "$unit")"
  after_monty="$(cksum "$monty")"
  [[ "$before_unit" == "$after_unit" ]] || log_fail "Managed unit skill changed unexpectedly on re-run"
  [[ "$before_monty" == "$after_monty" ]] || log_fail "Managed Monty skill changed unexpectedly on re-run"
  assert_contains "$TEST_DIR/reapply.log" "Unchanged files:"

  log_pass "Managed skill stayed stable"
}

test_no_overwrite_without_force() {
  log_info "Test: unmarked skill is protected from overwrite..."
  local unit="$TEST_DIR/.claude/skills/aai-test-unit/SKILL.md"
  cat > "$unit" <<'MD'
# custom unit skill

CUSTOM CONTENT - DO NOT OVERWRITE
MD

  if bash "$BOOTSTRAP_SCRIPT" "$TEST_DIR" > "$TEST_DIR/conflict.out" 2> "$TEST_DIR/conflict.err"; then
    log_fail "Bootstrap unexpectedly overwrote an unmarked skill"
  fi

  assert_contains "$TEST_DIR/conflict.err" "would overwrite unmarked files"
  assert_contains "$unit" "CUSTOM CONTENT - DO NOT OVERWRITE"

  log_pass "Unmarked skill was preserved"
}

test_force_is_explicit_overwrite() {
  log_info "Test: --force explicitly replaces an unmarked dynamic path..."
  local unit="$TEST_DIR/.claude/skills/aai-test-unit/SKILL.md"

  bash "$BOOTSTRAP_SCRIPT" "$TEST_DIR" --force > "$TEST_DIR/force.log"

  assert_contains "$TEST_DIR/force.log" "Force: true"
  assert_contains "$unit" "AAI-DYNAMIC-SKILL:START"
  assert_contains "$unit" "npm test"
  assert_not_contains "$unit" "CUSTOM CONTENT - DO NOT OVERWRITE"

  log_pass "--force replaced the unmarked skill"
}

main() {
  echo "Testing: $TEST_NAME"
  echo "===================="

  check_deps
  setup_fixture
  test_dry_run_has_no_writes
  test_generate_dynamic_skills
  test_managed_skill_is_stable
  test_no_overwrite_without_force
  test_force_is_explicit_overwrite

  echo
  echo "All tests passed!"
}

main "$@"
