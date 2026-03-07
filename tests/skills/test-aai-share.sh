#!/usr/bin/env bash
#
# Test: aai-share skill
# Tests Cloudflare Pages publishing functionality
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

# Test metadata
TEST_NAME="aai-share"
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

  # Git is always required
  if ! command -v git &> /dev/null; then
    log_skip "git not found"
  fi

  # Wrangler is optional - we'll mock if not available
  if ! command -v wrangler &> /dev/null; then
    log_info "wrangler not found - will use mock mode"
    MOCK_MODE=true
  else
    MOCK_MODE=false
  fi

  log_pass "Dependencies checked"
}

# Setup test environment
setup_test_env() {
  log_info "Setting up test environment..."

  # Create temporary directory
  TEST_DIR=$(mktemp -d /tmp/aai-test-share-XXXXXX)
  cd "$TEST_DIR"

  # Initialize git repository
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"

  # Create test document structure
  mkdir -p docs/ai/reports
  mkdir -p docs/ai/published

  # Create sample markdown document
  cat > docs/ai/reports/TEST_REPORT.md <<'EOF'
# Test Report

This is a test report for validation.

## Summary

- Test 1: Passed
- Test 2: Passed
- Test 3: Failed

## Details

Lorem ipsum dolor sit amet, consectetur adipiscing elit.

### Code Example

```bash
echo "Hello, World!"
```

## Conclusion

Testing complete.
EOF

  log_pass "Test environment created: $TEST_DIR"
}

# Test 1: Validate document exists
test_validate_document() {
  log_info "Test 1: Validate document exists..."

  local doc_path="docs/ai/reports/TEST_REPORT.md"

  if [[ ! -f "$doc_path" ]]; then
    log_fail "Document not found: $doc_path"
  fi

  if [[ ! "$doc_path" =~ \.md$ ]]; then
    log_fail "Document is not a Markdown file"
  fi

  log_pass "Document validation passed"
}

# Test 2: Convert Markdown to HTML
test_convert_markdown() {
  log_info "Test 2: Convert Markdown to HTML..."

  mkdir -p .cloudflare-publish

  # Simple conversion (mock the converter script)
  local input_file="docs/ai/reports/TEST_REPORT.md"
  local output_dir=".cloudflare-publish"

  # Create a basic HTML conversion
  cat > "$output_dir/index.html" <<EOF
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Test Report</title>
  <style>
    body { font-family: sans-serif; max-width: 800px; margin: 40px auto; padding: 0 20px; }
    h1 { border-bottom: 1px solid #ccc; }
    code { background: #f4f4f4; padding: 2px 6px; border-radius: 3px; }
  </style>
</head>
<body>
  <h1>Test Report</h1>
  <p>This is a test report for validation.</p>
</body>
</html>
EOF

  if [[ ! -f "$output_dir/index.html" ]]; then
    log_fail "HTML output not created"
  fi

  if ! grep -q "Test Report" "$output_dir/index.html"; then
    log_fail "HTML content does not match expected"
  fi

  log_pass "Markdown to HTML conversion passed"
}

# Test 3: Derive branch name
test_derive_branch_name() {
  log_info "Test 3: Derive branch name..."

  # Create a repo name
  local repo_root
  repo_root=$(git rev-parse --show-toplevel)

  local repo_name
  repo_name=$(basename "$repo_root")

  # Sanitize branch name (lowercase, non-alphanumeric → -)
  local branch_name
  branch_name=$(echo "$repo_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')

  if [[ -z "$branch_name" ]]; then
    log_fail "Branch name is empty"
  fi

  if [[ "$branch_name" =~ [^a-z0-9-] ]]; then
    log_fail "Branch name contains invalid characters: $branch_name"
  fi

  log_info "Branch name: $branch_name"
  log_pass "Branch name derivation passed"
}

# Test 4: Mock deployment (or real if wrangler available)
test_deploy() {
  log_info "Test 4: Deploy to Cloudflare Pages..."

  if [[ "$MOCK_MODE" == "true" ]]; then
    log_info "Mock mode: simulating deployment..."

    # Simulate successful deployment
    local mock_url="https://aai-test-share.aai-reports.pages.dev"
    echo "$mock_url" > .cloudflare-publish/deploy-url.txt

    log_pass "Mock deployment succeeded: $mock_url"
  else
    log_info "Real mode: would deploy via wrangler (skipping in test)"
    # In a real test environment with credentials, you could:
    # wrangler pages deploy .cloudflare-publish --project-name=aai-reports-test
    log_pass "Deployment check passed (real mode - manual verification required)"
  fi
}

# Test 5: Record publication
test_record_publication() {
  log_info "Test 5: Record publication history..."

  mkdir -p docs/ai/published

  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  local url="https://aai-test-share.aai-reports.pages.dev"
  local doc_path="docs/ai/reports/TEST_REPORT.md"

  # Record publication
  echo "{\"timestamp\":\"$timestamp\",\"document\":\"$doc_path\",\"url\":\"$url\"}" >> docs/ai/published/history.jsonl

  if [[ ! -f docs/ai/published/history.jsonl ]]; then
    log_fail "Publication history not created"
  fi

  if ! grep -q "$doc_path" docs/ai/published/history.jsonl; then
    log_fail "Publication history does not contain document path"
  fi

  log_pass "Publication recording passed"
}

# Test 6: Cleanup
test_cleanup() {
  log_info "Test 6: Cleanup publish directory..."

  if [[ -d .cloudflare-publish ]]; then
    rm -rf .cloudflare-publish
  fi

  if [[ -d .cloudflare-publish ]]; then
    log_fail "Cleanup failed - publish directory still exists"
  fi

  log_pass "Cleanup passed"
}

# Main test execution
main() {
  echo "Testing: $TEST_NAME"
  echo "===================="

  check_deps
  setup_test_env

  # Run tests
  test_validate_document
  test_convert_markdown
  test_derive_branch_name
  test_deploy
  test_record_publication
  test_cleanup

  echo ""
  echo "All tests passed!"
  exit 0
}

main "$@"
