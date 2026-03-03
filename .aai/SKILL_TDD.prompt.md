# TDD Skill - Test-Driven Development Cycle

## Goal
Enforce systematic RED-GREEN-REFACTOR test-driven development with verifiable evidence at each phase.

Inspired by Superpowers framework's mandatory TDD cycles.

## Instructions

### Prerequisites Check

Before starting TDD cycle:
1. Check `docs/ai/STATE.yaml` for a `current_focus` entry and at least one `active_work_items` entry
2. Verify the current work item's type allows TDD (implementation, feature, bugfix)
3. If there is no `current_focus` or no `active_work_items`, suggest running `/aai-intake` first

### Phase 1: RED (Write Failing Test)

**Objective:** Create a test that describes expected behavior and FAILS.

1. **Identify Test Scope**
   - Read requirements from `docs/requirements/` or `docs/specs/`
   - Determine what behavior to test
   - Choose appropriate test type (unit/integration/e2e)

2. **Write Failing Test**
   ```bash
   # Create test file (if doesn't exist)
   # Write test that describes expected behavior
   # DO NOT implement the feature yet
   ```

3. **Run Test and Verify RED**
   ```bash
   # Run test suite
   npm test [test-file]  # or appropriate command
   # or: pytest [test-file]
   # or: cargo test [test-name]
   ```

4. **Capture RED Evidence**
   - Save test output to `docs/ai/tdd/red-[timestamp].log`
   - Verify test FAILS with expected error message
   - If test passes, it's not testing new behavior - STOP and revise

5. **Update STATE.yaml**
   ```yaml
   tdd_cycle:
     status: RED
     test_path: [path-to-test-file]
     evidence:
       red: docs/ai/tdd/red-[timestamp].log
       green: null
       refactor: null
   ```

**RED Phase Checklist:**
- [ ] Test file created/updated
- [ ] Test describes expected behavior clearly
- [ ] Test FAILS when run (verified)
- [ ] Failure is for the right reason (not syntax error)
- [ ] Evidence saved to docs/ai/tdd/
- [ ] STATE.yaml updated

**BLOCK:** Cannot proceed to GREEN until RED evidence exists.

### Phase 2: GREEN (Minimal Implementation)

**Objective:** Write ONLY enough code to make the test pass.

1. **Implement Minimal Solution**
   - Write the simplest code that makes the test pass
   - Avoid over-engineering
   - Resist adding "nice-to-have" features
   - Focus on making the test GREEN

2. **Run Test and Verify GREEN**
   ```bash
   # Run the same test again
   npm test [test-file]
   ```

3. **Capture GREEN Evidence**
   - Save test output to `docs/ai/tdd/green-[timestamp].log`
   - Verify test PASSES
   - Verify ALL previously passing tests still pass

4. **Update STATE.yaml**
   ```yaml
   tdd_cycle:
     status: GREEN
     test_path: [path-to-test-file]
     evidence:
       red: docs/ai/tdd/red-[timestamp].log
       green: docs/ai/tdd/green-[timestamp].log
       refactor: null
   ```

**GREEN Phase Checklist:**
- [ ] Implementation added to source code
- [ ] New test PASSES (verified)
- [ ] All existing tests still PASS
- [ ] No over-engineering (minimal code)
- [ ] Evidence saved to docs/ai/tdd/
- [ ] STATE.yaml updated

**BLOCK:** Cannot proceed to REFACTOR until GREEN evidence exists.

### Phase 3: REFACTOR (Improve Code Quality)

**Objective:** Improve code quality without changing behavior.

1. **Identify Refactoring Opportunities**
   - Code duplication
   - Complex conditionals
   - Poor naming
   - Violation of SOLID principles
   - Performance improvements

2. **Refactor Code**
   - Extract functions/classes
   - Rename variables for clarity
   - Simplify logic
   - Add comments where necessary
   - Improve structure

3. **Run Tests and Verify Still GREEN**
   ```bash
   # Run full test suite
   npm test
   ```

4. **Capture REFACTOR Evidence**
   - Save test output to `docs/ai/tdd/refactor-[timestamp].log`
   - Verify ALL tests still PASS
   - Document refactoring decisions

5. **Update STATE.yaml**
   ```yaml
   tdd_cycle:
     status: REFACTOR_COMPLETE
     test_path: [path-to-test-file]
     evidence:
       red: docs/ai/tdd/red-[timestamp].log
       green: docs/ai/tdd/green-[timestamp].log
       refactor: docs/ai/tdd/refactor-[timestamp].log
     refactoring_summary: |
       - Extracted login validation to separate function
       - Renamed variables for clarity
       - Simplified error handling
   ```

6. **Record Decision**
   - Create decision log in `docs/decisions/`
   - Document what was refactored and why
   - Link to TDD evidence

**REFACTOR Phase Checklist:**
- [ ] Refactoring completed
- [ ] All tests still PASS (verified)
- [ ] No behavior changes
- [ ] Code quality improved
- [ ] Evidence saved to docs/ai/tdd/
- [ ] Decision documented
- [ ] STATE.yaml updated

### Phase 4: Documentation & Commit

1. **Update Documentation**
   - Add/update code comments
   - Update `docs/knowledge/FACTS.md` with learnings
   - Update `docs/knowledge/PATTERNS.md` if new pattern emerged

2. **Prepare Commit**
   ```bash
   git add [test-file] [implementation-files] docs/ai/tdd/
   git commit -m "$(cat <<'EOF'
   feat: [feature description]

   TDD cycle completed:
   - RED: [timestamp] - Test failed as expected
   - GREEN: [timestamp] - Minimal implementation passed
   - REFACTOR: [timestamp] - Code quality improved

   Evidence: docs/ai/tdd/

   Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
   EOF
   )"
   ```

3. **Clean TDD Cycle State**
   ```yaml
   tdd_cycle:
     status: IDLE
     test_path: null
     evidence:
       red: null
       green: null
       refactor: null
   ```

## Token Optimization

### Efficiency Strategies

1. **Incremental Testing**
   ```bash
   # Run only the test you're working on
   npm test -- --testNamePattern="login validation"

   # Run only changed files
   npm test -- --onlyChanged
   ```

2. **Cached Results**
   - Reuse evidence files for similar tasks
   - Reference previous TDD cycles in FACTS.md

3. **Parallel TDD**
   - Multiple features can have independent TDD cycles
   - Use git worktrees for parallel development

## Integration with AI-OS Workflow

### When to Use /aai-tdd

**During IMPLEMENTATION phase:**
```
/aai-intake (creates requirement)
  ↓
/aai-planning (breaks down into tasks)
  ↓
/aai-tdd (for each implementation task)
  ↓
/aai-validate-report (verify completion)
```

**TDD-First Development:**
```
User: "Add user login feature"
  ↓
/aai-intake → creates docs/requirements/REQ-001-user-login.md
  ↓
/aai-planning → breaks into 2-5 min tasks
  ↓
/aai-tdd → RED: write failing login test
  ↓
/aai-tdd → GREEN: implement minimal login
  ↓
/aai-tdd → REFACTOR: improve code quality
  ↓
/aai-validate-report → generate evidence report
```

## Safety & Enforcement

### Hard Blocks

1. **Cannot skip RED phase**
   - If test passes immediately, it's not testing new behavior
   - Must revise test to ensure it fails first

2. **Cannot skip GREEN phase**
   - Cannot refactor without passing tests
   - Must achieve GREEN before REFACTOR

3. **Cannot commit without evidence**
   - All three phases must have evidence files
   - STATE.yaml must show complete cycle

### Warnings

1. **Test coverage regression**
   - Warn if new code reduces overall coverage
   - Suggest adding more tests

2. **Over-engineering in GREEN phase**
   - Detect if implementation is more complex than needed
   - Suggest simplification

## Example Complete Cycle

```
User: "Add password strength validation"

1. RED Phase:
   - Created: tests/auth/password-strength.spec.ts
   - Test: "should reject weak passwords"
   - Run: npm test password-strength
   - Result: FAIL (expected - function doesn't exist)
   - Evidence: docs/ai/tdd/red-20260302T084900Z.log

2. GREEN Phase:
   - Created: src/auth/password-validator.ts
   - Implementation: basic regex check for 8+ chars, 1 number, 1 special
   - Run: npm test password-strength
   - Result: PASS
   - Evidence: docs/ai/tdd/green-20260302T085200Z.log

3. REFACTOR Phase:
   - Extracted regex to constant
   - Added descriptive variable names
   - Added JSDoc comments
   - Run: npm test
   - Result: ALL PASS
   - Evidence: docs/ai/tdd/refactor-20260302T085500Z.log
   - Decision: docs/decisions/DEC-003-password-validation.md

4. Commit:
   git commit -m "feat: add password strength validation

   TDD cycle: RED → GREEN → REFACTOR
   Evidence: docs/ai/tdd/
   "
```

## Troubleshooting

### Test never fails (can't get RED)
- Test may be too simple or already implemented
- Verify test is actually calling new functionality
- Check test assertions are meaningful

### Can't get GREEN
- Implementation may be incomplete
- Check test expectations are realistic
- Review error messages for hints

### Tests break during REFACTOR
- Behavior was changed (not just structure)
- Revert refactoring and try smaller changes
- Ensure tests are testing behavior, not implementation details

## Metrics

Track TDD effectiveness in `docs/ai/METRICS.jsonl`:
```jsonl
{"timestamp":"2026-03-02T08:55:00Z","type":"tdd_cycle","task":"password-validation","duration_seconds":360,"phases":{"red":60,"green":180,"refactor":120},"tests_added":3,"coverage_delta":"+5%"}
```
