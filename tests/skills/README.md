# AAI Skills Test Framework

Comprehensive testing framework for AAI (Autonomous AI) skills.

## Overview

This framework provides automated testing for all AAI skills, including:
- **aai-share** - Cloudflare Pages publishing
- **aai-tdd** - Test-driven development workflow
- **aai-worktree** - Git worktree management
- **aai-bootstrap** - Architecture detection and dynamic skill generation
- **aai-intake** - Intake routing and artifact generation

## Quick Start

```bash
# Run all tests
bash tests/skills/test-framework.sh

# Run a specific skill test
bash tests/skills/test-framework.sh --skill aai-share

# Run with verbose output
bash tests/skills/test-framework.sh --verbose

# Show help
bash tests/skills/test-framework.sh --help
```

## Test Structure

### Test Framework (`test-framework.sh`)

Main test runner that:
- Discovers all skill test files
- Checks system dependencies
- Runs tests in isolated environments
- Collects and reports results
- Generates summary reports

**Exit codes:**
- `0` - All tests passed
- `1` - Some tests failed
- `2` - Framework error (setup failed, invalid arguments)

### Individual Skill Tests

Each skill has its own test file:

#### `test-aai-share.sh`
Tests Cloudflare Pages publishing functionality:
- Document validation
- Markdown to HTML conversion
- Branch name derivation
- Mock/real deployment
- Publication history recording
- Cleanup

#### `test-aai-tdd.sh`
Tests TDD workflow:
- STATE.yaml prerequisites verification
- Spec Test Plan validation
- RED phase (failing test)
- GREEN phase (minimal implementation)
- REFACTOR phase (code quality improvements)
- Evidence capture
- State transitions

#### `test-aai-worktree.sh`
Tests git worktree management:
- Worktree creation
- AAI state initialization
- Worktree listing
- Context switching
- Branch isolation
- Registry updates
- Cleanup and archival

#### `test-aai-bootstrap.sh`
Tests architecture detection:
- Package manager detection (npm, python, cargo, go)
- Test framework discovery (jest, playwright, pytest)
- Build tool detection (vite, webpack, typescript)
- Dynamic skill generation
- Cross-agent discovery indexes
- .gitignore hygiene

#### `test-aai-intake.sh`
Tests intake routing:
- Type detection (prd, change, issue, hotfix, techdebt, research, rfc, release)
- Artifact generation
- STATE.yaml updates
- Artifact structure validation
- Routing logic verification
- Language policy (input: any, output: English)

## Test Design Principles

### 1. Isolation
- Each test runs in a temporary directory
- No side effects on main repository
- Automatic cleanup on success and failure

### 2. Speed
- All tests complete in < 30 seconds
- Fast feedback loop
- Suitable for CI/CD integration

### 3. Determinism
- Same inputs produce same outputs
- No flaky tests
- Reproducible results

### 4. Self-Cleaning
- Cleanup via `trap` ensures temporary files are removed
- Works even on test failure or interruption

### 5. Dependency Handling
- Tests check for required dependencies
- Skip gracefully if dependencies missing (exit code 42)
- Clear error messages for missing tools

## Test Results

Results are saved to `tests/skills/results/test-YYYYMMDD-HHMMSS/`:

```
results/test-20260307-082203/
├── summary.txt              # Human-readable summary
├── metrics.jsonl            # Machine-readable metrics
├── aai-share.log            # Individual test logs
├── aai-share.result         # PASS/FAIL/SKIP status
├── aai-tdd.log
├── aai-tdd.result
└── ...
```

### Summary Report

```
AAI Skills Test Summary
=======================

Run ID: test-20260307-082203
Date: 2026-03-07T08:22:03Z
Environment: Linux 6.6.87.2-microsoft-standard-WSL2

Results:
--------
Total:   5
Passed:  5 (100%)
Failed:  0 (0%)
Skipped: 0 (0%)

Failed Tests:
  (none)
```

### Metrics (JSONL)

```jsonl
{"skill":"aai-bootstrap","status":"PASS","duration_seconds":0,"exit_code":0}
{"skill":"aai-intake","status":"PASS","duration_seconds":0,"exit_code":0}
{"skill":"aai-share","status":"PASS","duration_seconds":0,"exit_code":0}
{"skill":"aai-tdd","status":"PASS","duration_seconds":0,"exit_code":0}
{"skill":"aai-worktree","status":"PASS","duration_seconds":1,"exit_code":0}
```

## Running Individual Tests

You can run individual test files directly:

```bash
# Run specific skill test
bash tests/skills/test-aai-share.sh
bash tests/skills/test-aai-tdd.sh
bash tests/skills/test-aai-worktree.sh
bash tests/skills/test-aai-bootstrap.sh
bash tests/skills/test-aai-intake.sh
```

Each test outputs:
- ✓ for passing steps
- ✗ for failing steps
- ⊘ for skipped tests

## Dependencies

### Required
- `bash` - Shell interpreter
- `git` - Version control

### Optional (skill-specific)
- `wrangler` - For aai-share (Cloudflare Pages deployment)
- `npm` - For Node.js project detection in aai-bootstrap
- `pandoc` - For document conversion (optional in aai-share)

## Integration with CI/CD

### GitHub Actions Example

```yaml
name: Test AAI Skills
on: [push, pull_request]

jobs:
  test-skills:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup dependencies
        run: |
          npm install -g wrangler
          sudo apt-get install -y pandoc

      - name: Run skill tests
        run: bash tests/skills/test-framework.sh

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: test-results
          path: tests/skills/results/
```

## Troubleshooting

### Permission Denied

```bash
# Make test scripts executable
chmod +x tests/skills/*.sh
```

### Missing Dependencies

```bash
# Install wrangler for aai-share tests
npm install -g wrangler

# Install pandoc (macOS)
brew install pandoc

# Install pandoc (Linux)
sudo apt-get install pandoc
```

### Tests Hang or Timeout

```bash
# Kill hung processes
pkill -f "test-framework.sh"

# Clean up temp directories
rm -rf /tmp/aai-test-*
```

## Adding New Tests

To add a test for a new skill:

1. Create `tests/skills/test-aai-<skill-name>.sh`
2. Follow the template structure:

```bash
#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="aai-<skill-name>"
TEST_DIR=""

cleanup() {
  if [[ -n "${TEST_DIR:-}" ]] && [[ -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}
trap cleanup EXIT

log_pass() { echo "✓ $*"; }
log_fail() { echo "✗ $*" >&2; return 1; }
log_skip() { echo "⊘ $*"; exit 42; }
log_info() { echo "  $*"; }

check_deps() {
  # Check required dependencies
  # Exit 42 (skip) if missing
}

setup_test_env() {
  # Create isolated test environment
}

test_<feature_1>() {
  # Test specific feature
}

test_<feature_2>() {
  # Test another feature
}

main() {
  echo "Testing: $TEST_NAME"
  echo "===================="

  check_deps
  setup_test_env

  test_<feature_1>
  test_<feature_2>
  # ... more tests

  echo ""
  echo "All tests passed!"
  exit 0
}

main "$@"
```

3. Make it executable: `chmod +x tests/skills/test-aai-<skill-name>.sh`
4. Run to verify: `bash tests/skills/test-aai-<skill-name>.sh`
5. Add to framework: It will be auto-discovered by `test-framework.sh`

## Test Coverage

Current coverage:

| Skill | Tests | Coverage |
|-------|-------|----------|
| aai-share | 6 | Document validation, conversion, deployment, recording, cleanup |
| aai-tdd | 7 | RED-GREEN-REFACTOR cycle, evidence capture, state management |
| aai-worktree | 8 | Creation, isolation, switching, cleanup, archival |
| aai-bootstrap | 8 | Detection (pkg mgr, test frameworks, build tools), skill generation |
| aai-intake | 11 | Type detection, artifact generation, routing, validation |

## Metrics Tracking

Test runs are recorded in `docs/ai/tests/test-runs.jsonl`:

```jsonl
{"timestamp":"2026-03-07T08:22:03Z","type":"skill_test","run_id":"test-20260307-082203","total":5,"passed":5,"failed":0,"skipped":0}
```

This allows tracking test health over time.

## Future Enhancements

- [ ] Parallel test execution
- [ ] Code coverage reporting
- [ ] Performance benchmarking
- [ ] Regression testing
- [ ] Test result visualization
- [ ] Integration tests (cross-skill scenarios)
- [ ] Mutation testing
- [ ] Property-based testing

## License

Same as AAI project.

## Contributing

When adding new skills or modifying existing ones:
1. Update or create corresponding test file
2. Ensure tests are isolated and fast (< 30s)
3. Add clear pass/fail indicators
4. Document expected behavior
5. Run `bash tests/skills/test-framework.sh` before committing
