#!/usr/bin/env bash
#
# AAI Skills Test Framework
# Runs comprehensive tests for all AAI skills
#
# Usage:
#   bash tests/skills/test-framework.sh [OPTIONS]
#
# Options:
#   --skill SKILL    Test specific skill only (e.g., aai-share)
#   --fix            Auto-fix common issues
#   --verbose        Show detailed output
#   --help           Show this help message
#
# Exit codes:
#   0 - All tests passed
#   1 - Some tests failed
#   2 - Framework error (setup failed, invalid arguments)

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
RESULTS_DIR="$SCRIPT_DIR/results"
RUN_ID="test-$(date -u +%Y%m%d-%H%M%S)"
RUN_DIR="$RESULTS_DIR/$RUN_ID"
VERBOSE=false
AUTO_FIX=false
SPECIFIC_SKILL=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --skill)
      SPECIFIC_SKILL="$2"
      shift 2
      ;;
    --fix)
      AUTO_FIX=true
      shift
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    --help)
      grep '^#' "$0" | grep -v '#!/usr/bin/env' | sed 's/^# //'
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 2
      ;;
  esac
done

# Logging functions
log() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
  echo -e "${GREEN}[PASS]${NC} $*"
}

log_fail() {
  echo -e "${RED}[FAIL]${NC} $*"
}

log_skip() {
  echo -e "${YELLOW}[SKIP]${NC} $*"
}

log_verbose() {
  if [[ "$VERBOSE" == "true" ]]; then
    echo -e "${BLUE}[DEBUG]${NC} $*"
  fi
}

# Setup results directory
setup_results_dir() {
  log "Setting up results directory: $RUN_DIR"
  mkdir -p "$RUN_DIR"
  echo "Test run started at $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$RUN_DIR/summary.txt"
}

# Discover all skill test files
discover_tests() {
  if [[ -n "$SPECIFIC_SKILL" ]]; then
    # Test specific skill
    local test_file="$SCRIPT_DIR/test-${SPECIFIC_SKILL}.sh"
    if [[ -f "$test_file" ]]; then
      echo "$test_file"
    else
      log_fail "Test file not found: $test_file"
      exit 2
    fi
  else
    # Find all test files
    find "$SCRIPT_DIR" -name "test-aai-*.sh" -type f | sort
  fi
}

# Check system dependencies
check_dependencies() {
  log "Checking system dependencies..."

  local deps_ok=true

  # Core dependencies
  for cmd in git bash; do
    if command -v "$cmd" &> /dev/null; then
      local version
      version=$("$cmd" --version 2>&1 | head -n1 || echo "unknown")
      log_verbose "$cmd: $version"
    else
      log_fail "Required dependency not found: $cmd"
      deps_ok=false
    fi
  done

  # Optional dependencies (check but don't fail)
  for cmd in npm wrangler pandoc pytest cargo; do
    if command -v "$cmd" &> /dev/null; then
      local version
      version=$("$cmd" --version 2>&1 | head -n1 || echo "unknown")
      log_verbose "$cmd: $version"
    else
      log_verbose "$cmd: not found (optional)"
    fi
  done

  if [[ "$deps_ok" == "false" ]]; then
    log_fail "Missing required dependencies"
    exit 2
  fi

  log_success "Dependencies checked"
}

# Run a single test file
run_test() {
  local test_file="$1"
  local test_name
  test_name=$(basename "$test_file" .sh)
  local skill_name="${test_name#test-}"

  TOTAL_TESTS=$((TOTAL_TESTS + 1))

  # Create log file
  local log_file="$RUN_DIR/${skill_name}.log"

  # Progress indicator
  printf "[%2d/%2d] %-20s " "$TOTAL_TESTS" "${#test_files[@]}" "$skill_name"

  # Run test and capture output
  local start_time
  start_time=$(date +%s)
  local exit_code=0

  if [[ "$VERBOSE" == "true" ]]; then
    bash "$test_file" 2>&1 | tee "$log_file" || exit_code=$?
  else
    bash "$test_file" &> "$log_file" || exit_code=$?
  fi

  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - start_time))

  # Check result
  case $exit_code in
    0)
      printf "${GREEN}PASS${NC} (%.1fs)\n" "$duration"
      PASSED_TESTS=$((PASSED_TESTS + 1))
      echo "PASS" > "$RUN_DIR/${skill_name}.result"
      ;;
    42)
      printf "${YELLOW}SKIP${NC} (%.1fs)\n" "$duration"
      SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
      echo "SKIP" > "$RUN_DIR/${skill_name}.result"
      ;;
    *)
      printf "${RED}FAIL${NC} (%.1fs)\n" "$duration"
      FAILED_TESTS=$((FAILED_TESTS + 1))
      echo "FAIL" > "$RUN_DIR/${skill_name}.result"

      # Show failure details in verbose mode
      if [[ "$VERBOSE" == "true" ]]; then
        echo "--- Error Details ---"
        tail -n 20 "$log_file"
        echo "---"
      fi
      ;;
  esac

  # Record metrics
  echo "{\"skill\":\"$skill_name\",\"status\":\"$(cat "$RUN_DIR/${skill_name}.result")\",\"duration_seconds\":$duration,\"exit_code\":$exit_code}" >> "$RUN_DIR/metrics.jsonl"
}

# Generate summary report
generate_summary() {
  log ""
  log "========================================="
  log "Test Summary"
  log "========================================="
  log "Total:   $TOTAL_TESTS"
  log_success "Passed:  $PASSED_TESTS ($(( TOTAL_TESTS > 0 ? PASSED_TESTS * 100 / TOTAL_TESTS : 0 ))%)"

  if [[ $FAILED_TESTS -gt 0 ]]; then
    log_fail "Failed:  $FAILED_TESTS ($(( TOTAL_TESTS > 0 ? FAILED_TESTS * 100 / TOTAL_TESTS : 0 ))%)"
  fi

  if [[ $SKIPPED_TESTS -gt 0 ]]; then
    log_skip "Skipped: $SKIPPED_TESTS ($(( TOTAL_TESTS > 0 ? SKIPPED_TESTS * 100 / TOTAL_TESTS : 0 ))%)"
  fi

  log ""
  log "Results saved to: $RUN_DIR"

  # Write summary file
  cat > "$RUN_DIR/summary.txt" <<EOF
AAI Skills Test Summary
=======================

Run ID: $RUN_ID
Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Environment: $(uname -s) $(uname -r)

Results:
--------
Total:   $TOTAL_TESTS
Passed:  $PASSED_TESTS ($(( TOTAL_TESTS > 0 ? PASSED_TESTS * 100 / TOTAL_TESTS : 0 ))%)
Failed:  $FAILED_TESTS ($(( TOTAL_TESTS > 0 ? FAILED_TESTS * 100 / TOTAL_TESTS : 0 ))%)
Skipped: $SKIPPED_TESTS ($(( TOTAL_TESTS > 0 ? SKIPPED_TESTS * 100 / TOTAL_TESTS : 0 ))%)

Failed Tests:
EOF

  # List failed tests
  if [[ $FAILED_TESTS -gt 0 ]]; then
    for result_file in "$RUN_DIR"/*.result; do
      if grep -q "FAIL" "$result_file"; then
        local skill_name
        skill_name=$(basename "$result_file" .result)
        echo "  - $skill_name" >> "$RUN_DIR/summary.txt"
      fi
    done
  else
    echo "  (none)" >> "$RUN_DIR/summary.txt"
  fi

  # Record in project metrics
  if [[ -d "$PROJECT_ROOT/docs/ai/tests" ]] || mkdir -p "$PROJECT_ROOT/docs/ai/tests" 2>/dev/null; then
    echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"type\":\"skill_test\",\"run_id\":\"$RUN_ID\",\"total\":$TOTAL_TESTS,\"passed\":$PASSED_TESTS,\"failed\":$FAILED_TESTS,\"skipped\":$SKIPPED_TESTS}" >> "$PROJECT_ROOT/docs/ai/tests/test-runs.jsonl"
  fi
}

# Main execution
main() {
  echo ""
  echo "AAI Skills Test Framework"
  echo "========================="
  echo ""

  # Setup
  setup_results_dir
  check_dependencies

  # Discover tests
  log "Discovering skill tests..."
  local test_files=()
  while IFS= read -r test_file; do
    test_files+=("$test_file")
  done < <(discover_tests)

  if [[ ${#test_files[@]} -eq 0 ]]; then
    log_fail "No tests to run"
    exit 2
  fi

  log "Found ${#test_files[@]} test(s)"

  # Run tests
  log ""
  log "Running tests..."
  log ""

  for test_file in "${test_files[@]}"; do
    run_test "$test_file"
  done

  # Generate summary
  log ""
  generate_summary

  # Determine exit code
  if [[ $FAILED_TESTS -gt 0 ]]; then
    exit 1
  else
    exit 0
  fi
}

# Run main
main "$@"
