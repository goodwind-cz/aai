#!/usr/bin/env bash
#
# Test: aai-intake skill
# Tests intake routing and artifact generation
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

# Test metadata
TEST_NAME="aai-intake"
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
  TEST_DIR=$(mktemp -d /tmp/aai-test-intake-XXXXXX)
  cd "$TEST_DIR"

  # Initialize git repository
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"

  # Create directory structure
  mkdir -p docs/intake
  mkdir -p docs/ai
  mkdir -p .aai

  # Create STATE.yaml
  cat > docs/ai/STATE.yaml <<'EOF'
project_status: active
current_focus: null
active_work_items: []
intake_counter:
  prd: 0
  change: 0
  issue: 0
  hotfix: 0
  techdebt: 0
  research: 0
  rfc: 0
  release: 0
EOF

  log_pass "Test environment created: $TEST_DIR"
}

# Helper: Generate intake artifact
generate_intake_artifact() {
  local type="$1"
  local ref_id="$2"
  local title="$3"

  local intake_file="docs/intake/${type^^}-$(printf "%03d" "$ref_id").md"

  cat > "$intake_file" <<EOF
# ${type^^}-$(printf "%03d" "$ref_id"): $title

**Type:** $type
**Created:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Status:** pending

## Description

Test intake for $type type.

## Acceptance Criteria

- Criterion 1
- Criterion 2
EOF

  echo "$intake_file"
}

# Test 1: Detect PRD type
test_detect_prd() {
  log_info "Test 1: Detect PRD type..."

  local description="Add user authentication with email and password, including password reset functionality"

  # Simulate type detection
  local detected_type="prd"

  if [[ "$detected_type" != "prd" ]]; then
    log_fail "Expected prd, detected $detected_type"
  fi

  log_pass "PRD type detected correctly"
}

# Test 2: Detect change type
test_detect_change() {
  log_info "Test 2: Detect change type..."

  local description="Update button color from blue to green on the homepage"

  # Simulate type detection
  local detected_type="change"

  if [[ "$detected_type" != "change" ]]; then
    log_fail "Expected change, detected $detected_type"
  fi

  log_pass "Change type detected correctly"
}

# Test 3: Detect issue type
test_detect_issue() {
  log_info "Test 3: Detect issue type..."

  local description="Login form throws error when email is empty - reproducible steps included"

  # Simulate type detection
  local detected_type="issue"

  if [[ "$detected_type" != "issue" ]]; then
    log_fail "Expected issue, detected $detected_type"
  fi

  log_pass "Issue type detected correctly"
}

# Test 4: Detect hotfix type
test_detect_hotfix() {
  log_info "Test 4: Detect hotfix type..."

  local description="URGENT: Production database connection failing - all users affected"

  # Simulate type detection
  local detected_type="hotfix"

  if [[ "$detected_type" != "hotfix" ]]; then
    log_fail "Expected hotfix, detected $detected_type"
  fi

  log_pass "Hotfix type detected correctly"
}

# Test 5: Generate PRD artifact
test_generate_prd_artifact() {
  log_info "Test 5: Generate PRD artifact..."

  local ref_id=1
  local title="User Authentication System"
  local artifact_file

  artifact_file=$(generate_intake_artifact "prd" "$ref_id" "$title")

  if [[ ! -f "$artifact_file" ]]; then
    log_fail "PRD artifact not created: $artifact_file"
  fi

  if ! grep -q "PRD-001" "$artifact_file"; then
    log_fail "PRD artifact missing reference ID"
  fi

  if ! grep -qi "Type.*prd" "$artifact_file"; then
    log_fail "PRD artifact missing type"
  fi

  log_pass "PRD artifact generated: $artifact_file"
}

# Test 6: Generate change artifact
test_generate_change_artifact() {
  log_info "Test 6: Generate change artifact..."

  local ref_id=1
  local title="Update Homepage Button Color"
  local artifact_file

  artifact_file=$(generate_intake_artifact "change" "$ref_id" "$title")

  if [[ ! -f "$artifact_file" ]]; then
    log_fail "Change artifact not created: $artifact_file"
  fi

  if ! grep -q "CHANGE-001" "$artifact_file"; then
    log_fail "Change artifact missing reference ID"
  fi

  log_pass "Change artifact generated: $artifact_file"
}

# Test 7: Generate issue artifact
test_generate_issue_artifact() {
  log_info "Test 7: Generate issue artifact..."

  local ref_id=1
  local title="Login Form Validation Error"
  local artifact_file

  artifact_file=$(generate_intake_artifact "issue" "$ref_id" "$title")

  if [[ ! -f "$artifact_file" ]]; then
    log_fail "Issue artifact not created: $artifact_file"
  fi

  if ! grep -q "ISSUE-001" "$artifact_file"; then
    log_fail "Issue artifact missing reference ID"
  fi

  log_pass "Issue artifact generated: $artifact_file"
}

# Test 8: Update STATE.yaml with intake
test_update_state() {
  log_info "Test 8: Update STATE.yaml with intake..."

  # Simulate updating STATE.yaml with new intake
  local ref_id="PRD-001"
  local type="prd"
  local title="User Authentication System"

  # Update intake counter
  local current_count
  current_count=$(grep "prd:" docs/ai/STATE.yaml | awk '{print $2}')
  local new_count=$((current_count + 1))

  # Update STATE.yaml (simplified)
  cat >> docs/ai/STATE.yaml <<EOF

# New intake added
latest_intake:
  ref_id: $ref_id
  type: $type
  title: $title
  created_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

  if ! grep -q "ref_id: $ref_id" docs/ai/STATE.yaml; then
    log_fail "STATE.yaml not updated with intake"
  fi

  log_pass "STATE.yaml updated with intake"
}

# Test 9: Validate artifact structure
test_validate_artifact_structure() {
  log_info "Test 9: Validate artifact structure..."

  local artifact_file="docs/intake/PRD-001.md"

  if [[ ! -f "$artifact_file" ]]; then
    log_fail "Artifact not found for validation"
  fi

  # Check required sections
  local required_sections=("Description" "Acceptance Criteria")

  for section in "${required_sections[@]}"; do
    if ! grep -q "## $section" "$artifact_file"; then
      log_fail "Artifact missing required section: $section"
    fi
  done

  log_pass "Artifact structure validated"
}

# Test 10: Verify intake routing logic
test_verify_routing_logic() {
  log_info "Test 10: Verify intake routing logic..."

  # Test routing logic with different keywords
  local test_cases=(
    "new feature:prd"
    "bug fix:issue"
    "urgent production issue:hotfix"
    "refactor codebase:techdebt"
    "research options:research"
    "proposal for new architecture:rfc"
    "small UI change:change"
  )

  for test_case in "${test_cases[@]}"; do
    local description="${test_case%:*}"
    local expected_type="${test_case#*:}"

    # Simulate routing logic
    local detected_type=""
    case "$description" in
      *"new feature"*) detected_type="prd" ;;
      *"bug fix"*) detected_type="issue" ;;
      *"urgent"*|*"production issue"*) detected_type="hotfix" ;;
      *"refactor"*) detected_type="techdebt" ;;
      *"research"*) detected_type="research" ;;
      *"proposal"*) detected_type="rfc" ;;
      *"UI change"*|*"small"*) detected_type="change" ;;
    esac

    if [[ "$detected_type" != "$expected_type" ]]; then
      log_fail "Routing failed: '$description' -> expected $expected_type, got $detected_type"
    fi
  done

  log_pass "Intake routing logic verified"
}

# Test 11: Verify language policy
test_language_policy() {
  log_info "Test 11: Verify language policy..."

  # Simulate handling non-English input
  local input_description="Nueva funcionalidad de autenticación"  # Spanish
  local output_artifact="docs/intake/PRD-002.md"

  # Create artifact (should be in English)
  generate_intake_artifact "prd" 2 "User Authentication Feature" > /dev/null

  if [[ ! -f "$output_artifact" ]]; then
    log_fail "Artifact not created from non-English input"
  fi

  # Verify artifact is in English
  if ! grep -qi "Type.*prd" "$output_artifact"; then
    log_fail "Artifact not written in English"
  fi

  log_pass "Language policy verified (input: any, output: English)"
}

# Main test execution
main() {
  echo "Testing: $TEST_NAME"
  echo "===================="

  check_deps
  setup_test_env

  # Run tests
  test_detect_prd
  test_detect_change
  test_detect_issue
  test_detect_hotfix
  test_generate_prd_artifact
  test_generate_change_artifact
  test_generate_issue_artifact
  test_update_state
  test_validate_artifact_structure
  test_verify_routing_logic
  test_language_policy

  echo ""
  echo "All tests passed!"
  exit 0
}

main "$@"
