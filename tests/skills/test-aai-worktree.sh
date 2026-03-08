#!/usr/bin/env bash
#
# Test: aai-worktree skill
# Tests git worktree management functionality
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

# Test metadata
TEST_NAME="aai-worktree"
TEST_DIR=""
WORKTREE_DIR=""

# Cleanup function
cleanup() {
  # Clean up worktrees first
  if [[ -n "${TEST_DIR:-}" ]] && [[ -d "$TEST_DIR" ]]; then
    cd "$TEST_DIR" 2>/dev/null || true

    # Remove any worktrees
    git worktree list --porcelain 2>/dev/null | grep '^worktree ' | cut -d' ' -f2 | while read -r wt; do
      if [[ "$wt" != "$TEST_DIR" ]]; then
        git worktree remove "$wt" --force 2>/dev/null || true
      fi
    done
  fi

  # Clean up directories
  if [[ -n "${WORKTREE_DIR:-}" ]] && [[ -d "$WORKTREE_DIR" ]]; then
    rm -rf "$WORKTREE_DIR"
  fi

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

  # Check git version supports worktrees (2.5+)
  local git_version
  git_version=$(git --version | grep -oE '[0-9]+\.[0-9]+' | head -n1)
  local major minor
  major=$(echo "$git_version" | cut -d. -f1)
  minor=$(echo "$git_version" | cut -d. -f2)

  if [[ $major -lt 2 ]] || { [[ $major -eq 2 ]] && [[ $minor -lt 5 ]]; }; then
    log_skip "git version too old (need 2.5+, have $git_version)"
  fi

  log_pass "Dependencies checked"
}

# Setup test environment
setup_test_env() {
  log_info "Setting up test environment..."

  # Create temporary directory for main repo
  TEST_DIR=$(mktemp -d /tmp/aai-test-worktree-XXXXXX)
  cd "$TEST_DIR"

  # Initialize git repository
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"

  # Create initial commit
  echo "# Test Project" > README.md
  git add README.md
  git commit -q -m "Initial commit"

  # Create main branch (ensure it exists)
  git branch -M main

  # Create docs/ai directory structure
  mkdir -p docs/ai
  cat > docs/ai/STATE.yaml <<'EOF'
project_status: active
current_focus: null
active_work_items: []
EOF
  git add docs/ai/STATE.yaml
  git commit -q -m "Add STATE.yaml"

  log_pass "Test environment created: $TEST_DIR"
}

# Test 1: Create worktree
test_create_worktree() {
  log_info "Test 1: Create worktree..."

  local task_name="feature-login"
  local branch_name="feature/login"
  local repo_name
  repo_name=$(basename "$TEST_DIR")
  WORKTREE_DIR="$TEST_DIR/../${repo_name}-${task_name}"

  # Create worktree
  git worktree add "$WORKTREE_DIR" -b "$branch_name" main

  # Verify worktree was created
  if [[ ! -d "$WORKTREE_DIR" ]]; then
    log_fail "Worktree directory not created: $WORKTREE_DIR"
  fi

  # Verify branch was created
  if ! git branch | grep -q "$branch_name"; then
    log_fail "Branch not created: $branch_name"
  fi

  # Verify worktree is listed (use realpath to handle symlinks/relative paths)
  local worktree_realpath
  worktree_realpath=$(realpath "$WORKTREE_DIR" 2>/dev/null || readlink -f "$WORKTREE_DIR")
  if ! git worktree list | grep -qF "$worktree_realpath"; then
    # Fallback: check if branch is in list
    if ! git worktree list | grep -q "$branch_name"; then
      log_fail "Worktree not listed"
    fi
  fi

  log_pass "Worktree created successfully"
}

# Test 2: Initialize AAI state in worktree
test_initialize_state() {
  log_info "Test 2: Initialize AAI state in worktree..."

  cd "$WORKTREE_DIR"

  # Initialize STATE.yaml for this worktree
  local task_name="feature-login"
  local branch_name="feature/login"

  cat > docs/ai/STATE.yaml <<EOF
task: $task_name
status: in_progress
branch: $branch_name
worktree_path: $WORKTREE_DIR
created_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
parent_worktree: $TEST_DIR
EOF

  if [[ ! -f docs/ai/STATE.yaml ]]; then
    log_fail "STATE.yaml not created in worktree"
  fi

  if ! grep -q "task: $task_name" docs/ai/STATE.yaml; then
    log_fail "STATE.yaml missing task name"
  fi

  log_pass "AAI state initialized in worktree"
}

# Test 3: List worktrees
test_list_worktrees() {
  log_info "Test 3: List worktrees..."

  cd "$TEST_DIR"

  # List worktrees
  local worktree_list
  worktree_list=$(git worktree list --porcelain)

  # Should have 2 worktrees: main and feature
  local worktree_count
  worktree_count=$(echo "$worktree_list" | grep -c '^worktree ' || true)

  if [[ $worktree_count -ne 2 ]]; then
    log_fail "Expected 2 worktrees, found $worktree_count"
  fi

  # Check if our worktree is listed (check for branch name as it's more reliable)
  if ! echo "$worktree_list" | grep -q "feature/login"; then
    log_fail "Feature worktree not in list"
  fi

  log_pass "Worktree list verified"
}

# Test 4: Switch to worktree (simulate cd)
test_switch_worktree() {
  log_info "Test 4: Switch to worktree..."

  # Switch to worktree
  cd "$WORKTREE_DIR"

  # Verify we're on the correct branch
  local current_branch
  current_branch=$(git branch --show-current)

  if [[ "$current_branch" != "feature/login" ]]; then
    log_fail "Not on expected branch: $current_branch"
  fi

  # Verify STATE.yaml is different from main
  if ! grep -q "task: feature-login" docs/ai/STATE.yaml; then
    log_fail "STATE.yaml not specific to this worktree"
  fi

  log_pass "Successfully switched to worktree"
}

# Test 5: Make changes in worktree
test_worktree_isolation() {
  log_info "Test 5: Test worktree isolation..."

  cd "$WORKTREE_DIR"

  # Make changes in worktree
  echo "Login feature" > login.js
  git add login.js
  git commit -q -m "Add login feature"

  # Verify commit is in feature branch
  if ! git log --oneline | grep -q "Add login feature"; then
    log_fail "Commit not found in feature branch"
  fi

  # Switch back to main worktree
  cd "$TEST_DIR"

  # Verify file doesn't exist in main
  if [[ -f login.js ]]; then
    log_fail "File from feature branch leaked to main"
  fi

  # Verify commit is not in main
  if git log --oneline | grep -q "Add login feature"; then
    log_fail "Commit from feature branch leaked to main"
  fi

  log_pass "Worktree isolation verified"
}

# Test 6: Update worktree registry
test_registry_update() {
  log_info "Test 6: Update worktree registry..."

  cd "$TEST_DIR"

  # Create registry file
  mkdir -p .git
  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  echo "{\"timestamp\":\"$timestamp\",\"action\":\"create\",\"task\":\"feature/login\",\"path\":\"$WORKTREE_DIR\",\"branch\":\"feature/login\"}" >> .git/worktrees-registry.jsonl

  if [[ ! -f .git/worktrees-registry.jsonl ]]; then
    log_fail "Registry file not created"
  fi

  if ! grep -q "feature/login" .git/worktrees-registry.jsonl; then
    log_fail "Registry missing worktree entry"
  fi

  log_pass "Worktree registry updated"
}

# Test 7: Cleanup worktree
test_cleanup_worktree() {
  log_info "Test 7: Cleanup worktree..."

  cd "$TEST_DIR"

  # Commit any uncommitted changes in worktree first
  cd "$WORKTREE_DIR"
  if [[ -n "$(git status --porcelain)" ]]; then
    git add -A
    git commit -q -m "Final changes before cleanup" || true
  fi
  cd "$TEST_DIR"

  # Archive STATE.yaml before cleanup
  mkdir -p docs/ai/archive/worktrees
  local archive_name="STATE-feature-login-$(date +%Y%m%d).yaml"
  cp "$WORKTREE_DIR/docs/ai/STATE.yaml" \
     "docs/ai/archive/worktrees/$archive_name"

  if [[ ! -f "docs/ai/archive/worktrees/$archive_name" ]]; then
    log_fail "STATE.yaml not archived"
  fi

  # Remove worktree
  git worktree remove "$WORKTREE_DIR"

  # Verify worktree was removed
  if [[ -d "$WORKTREE_DIR" ]]; then
    log_fail "Worktree directory still exists after removal"
  fi

  # Verify worktree is not listed (check by branch name)
  if git worktree list | grep -q "feature/login"; then
    log_fail "Worktree still listed after removal"
  fi

  # Update registry
  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "{\"timestamp\":\"$timestamp\",\"action\":\"cleanup\",\"task\":\"feature/login\",\"path\":\"$WORKTREE_DIR\",\"merged\":false}" >> .git/worktrees-registry.jsonl

  log_pass "Worktree cleanup successful"
}

# Test 8: Verify cleanup
test_verify_cleanup() {
  log_info "Test 8: Verify cleanup..."

  cd "$TEST_DIR"

  # Should only have main worktree now
  local worktree_count
  worktree_count=$(git worktree list --porcelain | grep -c '^worktree ' || true)

  if [[ $worktree_count -ne 1 ]]; then
    log_fail "Expected 1 worktree after cleanup, found $worktree_count"
  fi

  # Verify archived STATE.yaml exists
  if ! compgen -G "docs/ai/archive/worktrees/STATE-feature-login-*.yaml" > /dev/null; then
    log_fail "Archived STATE.yaml not found"
  fi

  log_pass "Cleanup verified"
}

# Main test execution
main() {
  echo "Testing: $TEST_NAME"
  echo "===================="

  check_deps
  setup_test_env

  # Run tests
  test_create_worktree
  test_initialize_state
  test_list_worktrees
  test_switch_worktree
  test_worktree_isolation
  test_registry_update
  test_cleanup_worktree
  test_verify_cleanup

  echo ""
  echo "All tests passed!"
  exit 0
}

main "$@"
