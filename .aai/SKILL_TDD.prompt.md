# TDD Skill - Test-Driven Development Cycle

## Goal
Enforce systematic RED-GREEN-REFACTOR test-driven development with verifiable evidence at each phase.

Inspired by Superpowers framework's mandatory TDD cycles.

## Instructions

### Prerequisites Check

Before starting TDD cycle:
1. **Capture `started_utc`** from system clock (`date -u +%Y-%m-%dT%H:%M:%SZ` or platform equivalent). Store it for metrics.
2. Check `docs/ai/STATE.yaml` for a `current_focus` entry and at least one `active_work_items` entry
3. Verify the current work item's type allows TDD (implementation, feature, bugfix)
4. If there is no `current_focus` or no `active_work_items`, suggest running `/aai-intake` first
5. **Locate the frozen spec** (`docs/specs/SPEC-<id>.md`) for the current scope
6. **Read the `## Test Plan` table** from the spec — this is the source of truth for which tests to write
7. If the spec has no `## Test Plan` section, STOP and suggest re-running Planning to generate it

### Phase 1: RED (Write Failing Test)

**Objective:** Pick the next `pending` TEST-xxx from the spec's Test Plan and write it so it FAILS.

1. **Select Next Test**
   - Read `## Test Plan` from the frozen spec
   - Pick the first TEST-xxx with status `pending`
   - If all TEST-xxx are `green`, the TDD cycle is complete — skip to Phase 4
   - Note the test type, expected file path, and description

2. **Write Failing Test**
   ```bash
   # Create test file at the path suggested in Test Plan (adjust if needed)
   # Write test that matches the TEST-xxx description
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

5. **Update Spec Test Plan**
   - Set the TEST-xxx status to `red` in the spec's `## Test Plan` table

6. **Update STATE.yaml**
   ```yaml
   tdd_cycle:
     status: RED
     test_id: TEST-xxx
     spec_path: docs/specs/SPEC-<id>.md
     test_path: [path-to-test-file]
     evidence:
       red: docs/ai/tdd/red-[timestamp].log
       green: null
       refactor: null
   ```

**RED Phase Checklist:**
- [ ] TEST-xxx selected from spec Test Plan
- [ ] Test file created/updated at expected path
- [ ] Test matches TEST-xxx description from spec
- [ ] Test FAILS when run (verified)
- [ ] Failure is for the right reason (not syntax error)
- [ ] Evidence saved to docs/ai/tdd/
- [ ] Spec Test Plan status updated to `red`
- [ ] STATE.yaml updated

**BLOCK:** Cannot proceed to GREEN until RED evidence exists.

### Phase 2: GREEN (Minimal Implementation)

**Objective:** Write ONLY enough code to make the test pass.

0. **Expert Resolution (optional)** — do NOT read the registry file.
   ```bash
   bash .aai/scripts/expert-fetch.sh --detect ts react  # from scope file extensions
   bash .aai/scripts/expert-fetch.sh --check typescript tdd-green
   bash .aai/scripts/expert-fetch.sh typescript
   EXPERT_BODY=$(bash .aai/scripts/expert-fetch.sh --body typescript)
   ```
   - Delegate GREEN implementation to a subagent using the expert body
     wrapped in AAI constraints (see `.aai/EXPERT_RESOLVE.prompt.md` Step 5)
   - The expert receives: failing test names, expected behavior, TECHNOLOGY.md constraints
   - The expert MUST return a result block per `.aai/SUBAGENT_PROTOCOL.md`
   - If fetch fails or no match, implement without expert (graceful degradation)

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

4. **Update Spec Test Plan**
   - Set the TEST-xxx status to `green` in the spec's `## Test Plan` table

5. **Update STATE.yaml**
   ```yaml
   tdd_cycle:
     status: GREEN
     test_id: TEST-xxx
     spec_path: docs/specs/SPEC-<id>.md
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
- [ ] Spec Test Plan status updated to `green`
- [ ] STATE.yaml updated

**BLOCK:** Cannot proceed to REFACTOR until GREEN evidence exists.

### Phase 3: REFACTOR (Improve Code Quality)

**Objective:** Improve code quality without changing behavior.

0. **Expert Resolution (optional)** — do NOT read the registry file.
   Reuse the expert from GREEN if cached, or detect a refactoring-specific expert:
   ```bash
   bash .aai/scripts/expert-fetch.sh --check performance tdd-refactor
   bash .aai/scripts/expert-fetch.sh --check security tdd-refactor
   bash .aai/scripts/expert-fetch.sh performance  # only if eligible
   EXPERT_BODY=$(bash .aai/scripts/expert-fetch.sh --body performance)
   ```
   Delegate refactoring to expert subagent with: current implementation, passing tests, goals.
   Graceful degradation: if no match or fetch fails, refactor without expert.

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

### Cycle Continuation

After completing REFACTOR for one TEST-xxx:
- Check the spec's `## Test Plan` for remaining `pending` tests
- If more `pending` TEST-xxx exist → return to Phase 1 (RED) with the next one
- If all TEST-xxx are `green` → proceed to Phase 4

### Phase 4: Documentation & Commit

1. **Update Documentation**
   - Add/update code comments
   - Update `docs/knowledge/FACTS.md` with learnings
   - Update `docs/knowledge/PATTERNS.md` if new pattern emerged

2. **Prepare Commit**
   ```bash
   git add [test-files] [implementation-files] docs/ai/tdd/ docs/specs/SPEC-*.md
   git commit -m "$(cat <<'EOF'
   feat: [feature description]

   TDD cycles completed (TEST-001..TEST-NNN):
   - All tests from spec Test Plan implemented via RED→GREEN→REFACTOR
   - Evidence: docs/ai/tdd/

   Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
   EOF
   )"
   ```

3. **Capture `ended_utc`** from system clock. Record agent_runs entry in STATE.yaml (see Metrics section below).

4. **Clean TDD Cycle State**
   ```yaml
   tdd_cycle:
     status: IDLE
     test_id: null
     spec_path: null
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

## Integration with AAI Workflow

### Unified Flow (same spec, two strategies)

```
/aai-intake → requirement with AC
  ↓
Planning (via /aai-loop or manual) → spec + Test Plan (TEST-001..N)
  ↓
┌─────────────────────────────────────────────────────┐
│  Choose implementation strategy:                     │
│                                                      │
│  /aai-loop  → Implementation agent covers all        │
│               TEST-xxx from Test Plan (free-form)    │
│                                                      │
│  /aai-tdd   → RED-GREEN-REFACTOR per TEST-xxx        │
│               (disciplined TDD cycle)                │
└─────────────────────────────────────────────────────┘
  ↓
Validation (via /aai-loop or manual) → all TEST-xxx green = PASS
```

Both strategies consume the same `## Test Plan` from the frozen spec.
Both produce the same evidence artifacts.
The difference is discipline: TDD enforces RED→GREEN→REFACTOR per test.

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

### agent_runs (record in docs/ai/STATE.yaml)

Capture real wall-clock timestamps:
- started_utc: immediately before Phase 1 (RED) begins
- ended_utc: immediately after the last phase completes (REFACTOR or Phase 4 commit)
After completing, append under
metrics.work_items[ref_id].agent_runs in docs/ai/STATE.yaml:
  role:             TDD
  model_id:         <your model identifier, e.g. claude-opus-4-6, claude-sonnet-4-5>
  started_utc:      <ISO 8601 UTC, real measured start>
  ended_utc:        <ISO 8601 UTC, real measured end>
  duration_seconds: <integer, ended_utc - started_utc>
  tokens_in:        <integer if your platform exposes it, otherwise null>
  tokens_out:       <integer if your platform exposes it, otherwise null>
  cost_usd:         null
  tdd_tests:        <count of TEST-xxx completed in this run>
Do NOT estimate any timing or token values. Only record measured/platform values.
