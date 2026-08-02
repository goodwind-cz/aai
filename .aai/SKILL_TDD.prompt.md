# TDD Skill - Test-Driven Development Cycle

## Goal
Enforce systematic RED-GREEN-REFACTOR test-driven development with verifiable evidence at each phase.
When invoked before the repository is ready for implementation, run the same
orchestration preflight used by the autonomous loop until a frozen spec with a
Test Plan is available or a human decision is required.

## Instructions

### Phase 0: Orchestration Preflight

**Objective:** Reach a TDD-ready scope without manual STATE.yaml edits.

Do not re-derive a setup loop here — drive the real one. Capture `started_utc`
from the system clock for metrics, then repeat `.aai/ORCHESTRATION.prompt.md`
(which runs `.aai/scripts/orchestration-dispatch.mjs`, the authority on what to
dispatch next) until the scope has a frozen spec with a `## Test Plan` and a
TDD-capable strategy. Bail out of the repeat when it stops converging and
report the last dispatch and blocker. Three stop rules bind this phase:

- If `docs/ai/STATE.yaml` is missing or unhealthy per
  `.aai/SKILL_CHECK_STATE.prompt.md`, let orchestration repair it; if state is
  BROKEN and cannot be safely repaired, STOP with the health report.
- If `human_input.required == true`, STOP and output the same HITL block as
  `.aai/SKILL_LOOP.prompt.md`.
- Execute ONLY setup dispatches (technology extraction, bootstrap, intake,
  planning, worktree decision). Never run regular Implementation, TDD
  Implementation, Validation, Code Review, Remediation, or Metrics Flush inside
  this phase. When no scope exists and the caller gave no work description, ask
  one concise question for it and STOP until answered.

Two gates below are TDD's own — the dispatcher does not enforce them.

5. **Verify implementation strategy**
   - TDD may proceed when `implementation_strategy.selected` is `tdd`.
   - TDD may proceed for the TDD-marked portion of a `hybrid` strategy.
   - If strategy is `loop`, STOP and ask whether to return to Planning to switch
     strategy to TDD or to continue with regular loop implementation.
   - If strategy is `direct` or `untested` (spec-implementation-mode-choice), the
     user chose a non-TDD lane at intake: do NOT start RED. Hand off to
     `.aai/IMPLEMENTATION.prompt.md` (direct = implement then targeted tests;
     untested = implement only, no tests).
   - If strategy is `undecided`, return to Planning. Do not start RED.

6. **Resolve worktree decision gate** — see .aai/ROLE_COMMON.md WORKTREE GATE.
   - If user selected `inline`, confirm `worktree.inline_review_scope` is explicit.
     If it is missing or ambiguous, STOP and ask for exact paths or diff range.
   - If user selected `worktree`, continue only inside the recorded worktree path.

7. **Replay relevant learnings** — `.aai/SKILL_REPLAY.prompt.md` semantics for
   the current scope.

### Prerequisites Check

Before starting TDD cycle:
1. Check `docs/ai/STATE.yaml` for a `current_focus` entry and at least one `active_work_items` entry
2. Verify the current work item's type allows TDD (implementation, feature, bugfix)
3. **Locate the frozen spec** (`docs/specs/SPEC-<id>.md`) for the current scope
4. Confirm the frozen spec has `SPEC-FROZEN: true`
5. Confirm implementation strategy allows TDD (`tdd` or applicable `hybrid`)
6. Confirm required/recommended worktree decision has been recorded
7. **Read the `## Test Plan` table** from the spec — this is the source of truth for which tests to write
8. If the spec has no `## Test Plan` section, STOP and run or dispatch Planning to generate it

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
   - **Classify it** (SPEC-0044): prepend one header line —
     `RED_CLASS: product_red` if the test's own assertion output reached,
     else `RED_CLASS: infra_fail` — then run
     `node .aai/scripts/tdd-evidence-check.mjs --red <log>` (see script
     header for the full rule); non-zero blocks GREEN until
     product_red-classified

5. **Update Spec Test Plan**
   - Set the TEST-xxx status to `red` in the spec's `## Test Plan` table

6. **Update STATE.yaml** — PRIMARY PATH (transactional CLI, SPEC-0012):
   ```bash
   node .aai/scripts/state.mjs set-tdd-cycle --status RED --test-id TEST-xxx \
     --spec-path docs/specs/SPEC-<id>.md --test-path [path-to-test-file] \
     --red docs/ai/tdd/red-[timestamp].log
   ```
   FALLBACK — if .aai/scripts/state.mjs is absent: read .aai/STATE_FALLBACK.md
   and follow its TDD-cycle hand-edit rule (status RED + red evidence path).

**Fixture diversity checklist (MANDATORY when authoring fixtures)** (SPEC-0013 H7):
- [ ] degenerate/empty collection (zero items, empty file, empty map)
- [ ] fully-covered / zero-remainder case (nothing left to do — the branch test-canon missed)
- [ ] multi-source / multi-writer case (more than one contributor to the same output)
- [ ] mid-operation failure (abort between steps; partial state observed)
- [ ] negative control (input that must NOT trigger the behavior)

RED-proof rule extension: ask "would this suite stay green if the happy path were the only path implemented?" — if yes, the suite is not evidence; add the missing shapes.

**BLOCK:** Cannot proceed to GREEN until RED evidence exists and is
product_red-classified.

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
   - The expert MUST return a result block per `.aai/SUBAGENT_CONTRACT.md`
   - If fetch fails or no match, implement without expert (graceful degradation)

0b. **Python Monty Scratchpad (optional)** — see .aai/ROLE_COMMON.md PYTHON
   MONTY SCRATCHPAD. A Monty pass never replaces RED/GREEN evidence — the
   selected failing test must still be made GREEN through the repository's
   normal test command.

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

5. **Update STATE.yaml** — PRIMARY PATH (transactional CLI, SPEC-0012):
   ```bash
   node .aai/scripts/state.mjs set-tdd-cycle --status GREEN --test-id TEST-xxx \
     --spec-path docs/specs/SPEC-<id>.md --test-path [path-to-test-file] \
     --green docs/ai/tdd/green-[timestamp].log
   ```
   FALLBACK — if .aai/scripts/state.mjs is absent: read .aai/STATE_FALLBACK.md
   and follow its TDD-cycle hand-edit rule (status GREEN + green evidence path).

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

5. **Update STATE.yaml** — PRIMARY PATH (transactional CLI, SPEC-0012):
   ```bash
   node .aai/scripts/state.mjs set-tdd-cycle --status REFACTOR_COMPLETE \
     --test-path [path-to-test-file] --refactor docs/ai/tdd/refactor-[timestamp].log
   ```
   Record the refactoring summary in docs/ai/decisions.jsonl (step 6 below).
   FALLBACK — if .aai/scripts/state.mjs is absent: read .aai/STATE_FALLBACK.md
   and follow its TDD-cycle hand-edit rule (status REFACTOR_COMPLETE + refactor evidence path).

6. **Record Decision**
   - Append decision entries to `docs/ai/decisions.jsonl`
   - Document what was refactored and why
   - Link to TDD evidence

### Cycle Continuation

After completing REFACTOR for one TEST-xxx:
- Check the spec's `## Test Plan` for remaining `pending` tests
- If more `pending` TEST-xxx exist → return to Phase 1 (RED) with the next one
- If all TEST-xxx are `green` → proceed to Phase 4

### Phase 4: Documentation, Validation & Review Gate

No completion claim in this phase without the `.aai/SKILL_VERIFY.prompt.md` gate.

1. **Update Documentation**
   - Add/update code comments
   - Update `docs/knowledge/FACTS.md` with learnings
   - Update `docs/knowledge/PATTERNS.md` if new pattern emerged

1b. **Pre-Handoff AC-Table Reconciliation** — see .aai/ROLE_COMMON.md
   PRE-HANDOFF AC-TABLE RECONCILIATION: reconcile the spec's
   `## Acceptance Criteria Status` table, then run
   `node .aai/scripts/docs-audit.mjs --gate <SPEC-ID>` and fix until
   exit 0 before reporting complete. "Covered by" here
   means every Spec-AC covered by the completed TDD cycles; Evidence may be a
   commit SHA, RUN_ID, or the docs/ai/tdd/*.log paths from those cycles.

2. **Run Standard Validation**
   - Execute `.aai/VALIDATION.prompt.md` or dispatch Validation through
     `.aai/ORCHESTRATION.prompt.md`.
   - Validation must record executable evidence in `docs/ai/STATE.yaml`.
   - If validation FAILs, return to Remediation. Do not claim completion.

3. **Run Code Review Gate**
   - If `code_review.required == true`, execute `.aai/SKILL_CODE_REVIEW.prompt.md`
     after validation evidence exists.
   - Code review may use a worktree diff, branch diff, staged diff, or explicit
     inline path scope. It does not require a worktree.
   - BLOCKING findings fail the code_quality verdict and block merge/PR
     readiness.
   - NON-BLOCKING findings require a recorded decision or follow-up task
     (H6 disposition duty).
   - PASS or explicit human waiver must be recorded before merge/PR-ready output.

4. **Capture `ended_utc`**
   - Capture from system clock immediately after the last TDD-owned state write.
   - Record agent_runs entry in STATE.yaml (see Metrics section below).

5. **Clean TDD Cycle State** — PRIMARY PATH (transactional CLI, SPEC-0012):
   ```bash
   node .aai/scripts/state.mjs set-tdd-cycle --status IDLE
   ```
   (`--status IDLE` nulls test_id/spec_path/test_path and all evidence fields.)
   FALLBACK — if .aai/scripts/state.mjs is absent: read .aai/STATE_FALLBACK.md
   and follow its TDD-cycle hand-edit rule (status IDLE, all other fields null).

6. **Prepare Commit Only With Explicit Approval**
   - Do not commit automatically.
   - Commit is allowed only after:
     - all selected TEST-xxx entries are green
     - Validation PASS exists with evidence
     - Code Review PASS exists or the user explicitly waived review
     - the user explicitly confirms committing
   - If approval is missing, report candidate files and a suggested commit message
     without running `git commit`.

## Integration with AAI Workflow

### Unified Flow (same spec, selectable strategy)

```
/aai-intake -> requirement with AC
  -> Planning -> frozen spec + Test Plan + implementation_strategy
  -> Worktree decision gate if recommended/required
  -> Implementation strategy:
       loop   = Implementation agent covers TEST-xxx entries in one pass
       tdd    = RED-GREEN-REFACTOR per TEST-xxx
       hybrid = TDD for risky behavior, loop implementation for simple glue
  -> Validation -> executable evidence
  -> Code Review -> spec compliance, then code quality
  -> Metrics flush / PR / commit only after required gates pass
```

Both strategies consume the same `## Test Plan` from the frozen spec.
Both produce compatible evidence artifacts.
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

4. **Cannot start implementation with an unresolved worktree decision**
   - `recommended` and `required` recommendations require a user decision
   - Inline override is allowed only with explicit review scope

5. **Cannot claim merge/PR readiness without review**
   - Code Review PASS or explicit human waiver is required when
     `code_review.required == true`

6. **Cannot count an all-happy-path suite as evidence** (SPEC-0013 H7)
   - The Phase 1 fixture diversity checklist is mandatory when authoring fixtures
   - If the suite would stay green with only the happy path implemented,
     it is not evidence — add the missing fixture shapes before claiming RED/GREEN

### Warnings

1. **Test coverage regression**
   - Warn if new code reduces overall coverage
   - Suggest adding more tests

2. **Over-engineering in GREEN phase**
   - Detect if implementation is more complex than needed
   - Suggest simplification

## Troubleshooting
See `.aai/SKILL_DEBUG.prompt.md` for the systematic-debugging root-cause gate
(READ → REPRODUCE → ISOLATE → FIX-AT-CAUSE) when RED/GREEN/REFACTOR stalls.

## Metrics

### agent_runs (record in docs/ai/STATE.yaml)

See .aai/ROLE_COMMON.md (role: "TDD Implementation") for the append-run metrics
procedure. Capture `started_utc` immediately before Phase 1 (RED) begins.
Additionally pass `--tdd-tests <count of TEST-xxx completed>` on the
append-run call (this role's residue); the FALLBACK covers it too
(incl. tdd_tests).
