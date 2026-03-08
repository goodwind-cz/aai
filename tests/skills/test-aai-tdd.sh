#!/usr/bin/env bash
#
# Test: aai-tdd skill
# Tests TDD workflow (RED-GREEN-REFACTOR)
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

# Test metadata
TEST_NAME="aai-tdd"
TEST_DIR=""

# Cleanup function
cleanup() {
  if [[ -n "${TEST_DIR:-}" ]] && [[ -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}
trap cleanup EXIT

# Logging
log_pass() { echo "✓ $*"; }
log_fail() { echo "✗ $*" >&2; return 1; }
log_skip() { echo "⊘ $*"; exit 42; }
log_info() { echo "  $*"; }

# Portable in-place replacement helper (GNU/BSD sed compatible)
replace_in_file() {
  local search="$1"
  local replace="$2"
  local file="$3"
  local tmp
  tmp="$(mktemp "$(dirname "$file")/.tmp.XXXXXX")"
  sed "s|$search|$replace|" "$file" > "$tmp"
  mv "$tmp" "$file"
}

# Check dependencies
check_deps() {
  log_info "Checking dependencies..."

  if ! command -v git &> /dev/null; then
    log_skip "git not found"
  fi

  log_pass "Dependencies checked"
}

# Setup test environment
setup_test_env() {
  log_info "Setting up test environment..."

  # Create temporary directory
  TEST_DIR=$(mktemp -d /tmp/aai-test-tdd-XXXXXX)
  cd "$TEST_DIR"

  # Initialize git repository
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"

  # Create project structure
  mkdir -p docs/ai/tdd
  mkdir -p docs/specs
  mkdir -p src
  mkdir -p tests

  # Create STATE.yaml
  cat > docs/ai/STATE.yaml <<'EOF'
project_status: active
current_focus: TEST-001
active_work_items:
  - ref_id: CHANGE-001
    type: change
    title: Add calculator function
    status: in_progress

tdd_cycle:
  status: IDLE
  test_id: null
  spec_path: null
  test_path: null
  evidence:
    red: null
    green: null
    refactor: null
EOF

  # Create frozen spec with Test Plan
  cat > docs/specs/SPEC-CHANGE-001.md <<'EOF'
# SPEC-CHANGE-001: Add Calculator Function

## Test Plan

| ID | Type | Description | File | Status |
|----|------|-------------|------|--------|
| TEST-001 | unit | Calculator should add two numbers | tests/calculator.test.js | pending |
| TEST-002 | unit | Calculator should handle negative numbers | tests/calculator.test.js | pending |
EOF

  # Create a simple test runner script
  cat > run-tests.sh <<'EOF'
#!/usr/bin/env bash
# Simple test runner that checks if tests pass

if [[ ! -f tests/calculator.test.js ]]; then
  echo "Error: Test file not found"
  exit 1
fi

# Check if implementation exists
if [[ ! -f src/calculator.js ]]; then
  echo "FAIL: Implementation not found"
  exit 1
fi

# Simple validation - check if function is exported
if grep -q "function add" src/calculator.js && grep -q "module.exports" src/calculator.js; then
  echo "PASS: All tests passed"
  exit 0
else
  echo "FAIL: Implementation incomplete"
  exit 1
fi
EOF
  chmod +x run-tests.sh

  log_pass "Test environment created: $TEST_DIR"
}

# Test 1: Verify STATE.yaml prerequisites
test_verify_state() {
  log_info "Test 1: Verify STATE.yaml prerequisites..."

  if [[ ! -f docs/ai/STATE.yaml ]]; then
    log_fail "STATE.yaml not found"
  fi

  # Check for current_focus
  if ! grep -q "current_focus:" docs/ai/STATE.yaml; then
    log_fail "STATE.yaml missing current_focus"
  fi

  # Check for active_work_items
  if ! grep -q "active_work_items:" docs/ai/STATE.yaml; then
    log_fail "STATE.yaml missing active_work_items"
  fi

  log_pass "STATE.yaml prerequisites verified"
}

# Test 2: Verify spec has Test Plan
test_verify_spec() {
  log_info "Test 2: Verify spec has Test Plan..."

  local spec_file="docs/specs/SPEC-CHANGE-001.md"

  if [[ ! -f "$spec_file" ]]; then
    log_fail "Spec file not found: $spec_file"
  fi

  if ! grep -q "## Test Plan" "$spec_file"; then
    log_fail "Spec missing Test Plan section"
  fi

  if ! grep -q "TEST-001" "$spec_file"; then
    log_fail "Spec Test Plan missing TEST-001"
  fi

  log_pass "Spec Test Plan verified"
}

# Test 3: RED phase - Write failing test
test_red_phase() {
  log_info "Test 3: RED phase - Write failing test..."

  # Create failing test
  cat > tests/calculator.test.js <<'EOF'
// Test for calculator add function
const calculator = require('../src/calculator');

// TEST-001: Calculator should add two numbers
if (typeof calculator === 'undefined' || typeof calculator.add !== 'function') {
  console.log('FAIL: calculator.add function not found');
  process.exit(1);
}

const result = calculator.add(2, 3);
if (result !== 5) {
  console.log('FAIL: Expected 5, got ' + result);
  process.exit(1);
}

console.log('PASS: calculator.add works correctly');
process.exit(0);
EOF

  # Test should fail because implementation doesn't exist
  if ./run-tests.sh &> docs/ai/tdd/red-test.log; then
    log_fail "Test should have failed in RED phase but passed"
  fi

  # Verify RED evidence was captured
  if [[ ! -f docs/ai/tdd/red-test.log ]]; then
    log_fail "RED evidence not captured"
  fi

  # Update STATE.yaml
  replace_in_file "status: IDLE" "status: RED" docs/ai/STATE.yaml
  replace_in_file "test_id: null" "test_id: TEST-001" docs/ai/STATE.yaml

  log_pass "RED phase completed - test fails as expected"
}

# Test 4: GREEN phase - Minimal implementation
test_green_phase() {
  log_info "Test 4: GREEN phase - Minimal implementation..."

  # Create minimal implementation
  mkdir -p src
  cat > src/calculator.js <<'EOF'
// Minimal implementation for TEST-001
function add(a, b) {
  return a + b;
}

module.exports = { add };
EOF

  # Test should now pass
  if ! ./run-tests.sh &> docs/ai/tdd/green-test.log; then
    log_fail "Test should have passed in GREEN phase"
  fi

  # Verify GREEN evidence was captured
  if [[ ! -f docs/ai/tdd/green-test.log ]]; then
    log_fail "GREEN evidence not captured"
  fi

  # Update STATE.yaml
  replace_in_file "status: RED" "status: GREEN" docs/ai/STATE.yaml

  log_pass "GREEN phase completed - test passes with minimal implementation"
}

# Test 5: REFACTOR phase - Improve code quality
test_refactor_phase() {
  log_info "Test 5: REFACTOR phase - Improve code quality..."

  # Refactor with better documentation and validation
  cat > src/calculator.js <<'EOF'
/**
 * Calculator module
 * Provides basic arithmetic operations
 */

/**
 * Adds two numbers together
 * @param {number} a - First number
 * @param {number} b - Second number
 * @returns {number} Sum of a and b
 */
function add(a, b) {
  // Validate inputs
  if (typeof a !== 'number' || typeof b !== 'number') {
    throw new TypeError('Arguments must be numbers');
  }

  return a + b;
}

module.exports = { add };
EOF

  # Test should still pass after refactoring
  if ! ./run-tests.sh &> docs/ai/tdd/refactor-test.log; then
    log_fail "Test should still pass after REFACTOR"
  fi

  # Verify REFACTOR evidence was captured
  if [[ ! -f docs/ai/tdd/refactor-test.log ]]; then
    log_fail "REFACTOR evidence not captured"
  fi

  # Update STATE.yaml
  replace_in_file "status: GREEN" "status: REFACTOR_COMPLETE" docs/ai/STATE.yaml

  log_pass "REFACTOR phase completed - tests still pass with improved code"
}

# Test 6: Verify all evidence files exist
test_verify_evidence() {
  log_info "Test 6: Verify all evidence files exist..."

  local required_evidence=(
    "docs/ai/tdd/red-test.log"
    "docs/ai/tdd/green-test.log"
    "docs/ai/tdd/refactor-test.log"
  )

  for evidence_file in "${required_evidence[@]}"; do
    if [[ ! -f "$evidence_file" ]]; then
      log_fail "Missing evidence file: $evidence_file"
    fi
  done

  log_pass "All evidence files verified"
}

# Test 7: Verify STATE.yaml updated correctly
test_verify_state_updates() {
  log_info "Test 7: Verify STATE.yaml updated correctly..."

  if ! grep -q "status: REFACTOR_COMPLETE" docs/ai/STATE.yaml; then
    log_fail "STATE.yaml not updated to REFACTOR_COMPLETE"
  fi

  if ! grep -q "test_id: TEST-001" docs/ai/STATE.yaml; then
    log_fail "STATE.yaml missing test_id"
  fi

  log_pass "STATE.yaml updated correctly"
}

# Main test execution
main() {
  echo "Testing: $TEST_NAME"
  echo "===================="

  check_deps
  setup_test_env

  # Run tests
  test_verify_state
  test_verify_spec
  test_red_phase
  test_green_phase
  test_refactor_phase
  test_verify_evidence
  test_verify_state_updates

  echo ""
  echo "All tests passed!"
  exit 0
}

main "$@"
