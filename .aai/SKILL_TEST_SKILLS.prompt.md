# Test Skills — AAI Skill Testing Framework

## Goal
Discover all installed AAI skills, check dependencies, run comprehensive test suites, and generate detailed test reports. Supports testing individual skills or all skills at once.

## Usage

```bash
# Test all skills
/aai-test-skills

# Test a specific skill
/aai-test-skills --skill aai-share

# Test with auto-fix for common issues
/aai-test-skills --fix

# Verbose output
/aai-test-skills --verbose
```

## Instructions

### 1. Discover Installed Skills

Scan for all AAI skills in the project:

```bash
# Find all skill prompts
find .aai -name "SKILL_*.prompt.md" -type f | sort
```

Extract skill names from filenames:
- `.aai/SKILL_SHARE.prompt.md` → `aai-share`
- `.aai/SKILL_TDD.prompt.md` → `aai-tdd`
- `.aai/SKILL_WORKTREE.prompt.md` → `aai-worktree`
- etc.

### 2. Check System Dependencies

Before running tests, verify all required dependencies are available:

```bash
# Core dependencies
git --version
npm --version

# Optional dependencies (skill-specific)
which wrangler    # for aai-share
which pandoc      # for documentation generation
which pytest      # for Python projects
which cargo       # for Rust projects
```

Create dependency report:
```
System Dependencies:
✓ git         2.43.0
✓ npm         10.2.4
✗ wrangler    not found (needed for aai-share)
✓ pandoc      3.1.2
```

### 3. Run Test Suite

Execute the test framework:

```bash
# Run all tests
bash tests/skills/test-framework.sh

# Run specific skill test
bash tests/skills/test-aai-share.sh

# With auto-fix
bash tests/skills/test-framework.sh --fix

# Verbose mode
bash tests/skills/test-framework.sh --verbose
```

The test framework will:
1. Set up isolated test environments
2. Run each skill's test suite
3. Collect results (PASS/FAIL/SKIP)
4. Clean up test artifacts
5. Generate summary report

### 4. Generate Test Report

After tests complete, generate a comprehensive report:

```markdown
# AAI Skills Test Report

**Generated:** 2026-03-07T14:30:00Z
**Test Run ID:** test-20260307-143000
**Environment:** Linux 6.6.87.2 (WSL2)

## Summary

- Total Skills: 11
- Tests Passed: 8
- Tests Failed: 2
- Tests Skipped: 1
- Success Rate: 80%

## Detailed Results

### aai-share ✓ PASS
- Duration: 12.3s
- Tests: 5/5 passed
- Dependencies: wrangler ✓
- Notes: All publishing workflows succeeded

### aai-tdd ✗ FAIL
- Duration: 8.7s
- Tests: 3/4 passed
- Failed: RED phase - test did not fail as expected
- Error: Test passed on first run (should fail initially)

### aai-worktree ✓ PASS
- Duration: 15.2s
- Tests: 6/6 passed
- Dependencies: git ✓
- Notes: All worktree operations verified

### aai-bootstrap ⊘ SKIP
- Reason: No test fixtures available
- Dependencies: Missing test project templates

### aai-intake ✓ PASS
- Duration: 6.1s
- Tests: 8/8 passed
- Notes: All intake types routed correctly

## Dependency Analysis

| Dependency | Required By | Status |
|------------|-------------|--------|
| git        | aai-worktree, all | ✓ Installed |
| npm        | aai-bootstrap, aai-build | ✓ Installed |
| wrangler   | aai-share | ✓ Installed |
| pandoc     | aai-share (optional) | ✓ Installed |
| pytest     | aai-test-unit (Python) | ✗ Not found |

## Recommendations

1. Fix failing tests in aai-tdd (RED phase validation)
2. Add test fixtures for aai-bootstrap
3. Install pytest for Python project testing
4. Consider adding integration tests for aai-loop

## Test Evidence

All test logs saved to: `tests/skills/results/test-20260307-143000/`
```

### 5. Handle Test Failures

If tests fail:

1. **Capture Error Details**
   ```bash
   # Errors are logged to tests/skills/results/[timestamp]/[skill].log
   cat tests/skills/results/test-20260307-143000/aai-tdd.log
   ```

2. **Provide Fix Suggestions**
   - Common issues and solutions
   - Links to documentation
   - Commands to repair broken state

3. **Auto-Fix (if --fix flag used)**
   ```bash
   # Example fixes:
   # - Reset broken STATE.yaml
   # - Clean stale worktrees
   # - Repair git configuration
   # - Re-authenticate with Wrangler
   ```

### 6. Update Test Status

Record test run in metrics:

```bash
mkdir -p docs/ai/tests
echo '{"timestamp":"2026-03-07T14:30:00Z","type":"skill_test","run_id":"test-20260307-143000","total":11,"passed":8,"failed":2,"skipped":1}' >> docs/ai/tests/test-runs.jsonl
```

### 7. Exit Codes

The test framework uses standard exit codes:

- `0` - All tests passed
- `1` - Some tests failed
- `2` - Test framework error (setup failed, invalid arguments, etc.)

## Individual Skill Tests

Each skill has its own test file in `tests/skills/`:

### test-aai-share.sh
Tests Cloudflare Pages publishing:
- Markdown to HTML conversion
- Image asset copying
- Wrangler deployment
- URL generation
- History recording

### test-aai-tdd.sh
Tests TDD workflow:
- RED phase (failing test)
- GREEN phase (minimal implementation)
- REFACTOR phase (code quality)
- Evidence capture
- State transitions

### test-aai-worktree.sh
Tests git worktree management:
- Worktree creation
- Branch isolation
- Switching between worktrees
- Cleanup and archival
- Registry updates

### test-aai-bootstrap.sh
Tests architecture detection:
- Package manager detection
- Test framework discovery
- Dynamic skill generation
- Cross-agent index creation

### test-aai-intake.sh
Tests intake routing:
- Type detection (prd, change, issue, etc.)
- Artifact generation
- Validation
- State updates

## Test Isolation

All tests use isolated environments:

```bash
# Create temporary test directory
TEST_DIR=$(mktemp -d /tmp/aai-test-XXXXXX)

# Set up test fixtures
cp -r tests/fixtures/sample-project "$TEST_DIR/"

# Run test in isolation
cd "$TEST_DIR/sample-project"
# ... run test commands ...

# Cleanup (always runs via trap)
trap "rm -rf '$TEST_DIR'" EXIT
```

## Test Best Practices

1. **Fast Execution** - Each test completes in < 30 seconds
2. **Isolated** - No side effects on main repository
3. **Deterministic** - Same inputs produce same outputs
4. **Self-Cleaning** - Cleanup on success and failure
5. **Documented** - Clear pass/fail criteria
6. **Skippable** - Skip if dependencies missing

## Continuous Integration

Add to GitHub Actions workflow:

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

### Test Framework Not Found

```bash
# Ensure tests directory exists
mkdir -p tests/skills

# Verify test framework exists
ls -la tests/skills/test-framework.sh
```

### Permission Denied

```bash
# Make test scripts executable
chmod +x tests/skills/*.sh
```

### Tests Hang or Timeout

```bash
# Kill hung processes
pkill -f "test-framework.sh"

# Clean up temp directories
rm -rf /tmp/aai-test-*
```

### Missing Dependencies

```bash
# Install common dependencies
npm install -g wrangler    # for aai-share
brew install pandoc        # for docs (macOS)
sudo apt-get install pandoc  # for docs (Linux)
```

## Metrics

Track test metrics over time:

```jsonl
{"timestamp":"2026-03-07T14:30:00Z","type":"skill_test","total":11,"passed":8,"failed":2,"skipped":1,"duration_seconds":127}
{"timestamp":"2026-03-08T09:15:00Z","type":"skill_test","total":11,"passed":10,"failed":0,"skipped":1,"duration_seconds":118}
{"timestamp":"2026-03-08T16:45:00Z","type":"skill_test","total":11,"passed":11,"failed":0,"skipped":0,"duration_seconds":142}
```

## Example Output

```
AAI Skills Test Framework
==========================

Discovering skills...
✓ Found 11 skills

Checking dependencies...
✓ git 2.43.0
✓ npm 10.2.4
✓ wrangler 3.48.0
✓ pandoc 3.1.2

Running tests...
[1/11] aai-share .......... PASS (12.3s)
[2/11] aai-tdd ............ FAIL (8.7s)
[3/11] aai-worktree ...... PASS (15.2s)
[4/11] aai-bootstrap ..... SKIP (no fixtures)
[5/11] aai-intake ........ PASS (6.1s)
[6/11] aai-loop .......... PASS (18.4s)
[7/11] aai-hitl .......... PASS (4.2s)
[8/11] aai-check-state ... PASS (2.1s)
[9/11] aai-validate-report  PASS (9.8s)
[10/11] aai-flush ........ PASS (3.3s)
[11/11] aai-canonicalize . PASS (5.5s)

Summary:
--------
Total:   11
Passed:   9 (82%)
Failed:   1 (9%)
Skipped:  1 (9%)
Duration: 127 seconds

Results saved to: tests/skills/results/test-20260307-143000/

Exit code: 1 (some tests failed)
```

## Safety

- All tests run in isolated temporary directories
- No modifications to main repository state
- Automatic cleanup on success and failure
- No network calls to production services
- Mock/stub external dependencies when possible

## Future Enhancements

- Parallel test execution
- Coverage reporting
- Performance benchmarking
- Regression testing
- Integration with CI/CD
- Test result visualization
