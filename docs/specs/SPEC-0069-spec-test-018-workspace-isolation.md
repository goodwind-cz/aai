---
id: spec-test-018-workspace-isolation
type: spec
number: 69
status: done
ceremony_level: 1
links:
  requirement: docs/issues/ISSUE-0023-test-018-workspace-isolation.md
  rfc: null
  pr:
    - 128
  commits:
    - 1f725c291cc3bc5e9f211b00bf4212eee237910e
---

# Spec: TEST-018 fresh per-case workspace + guaranteed teardown (removes cross-iteration proc pollution)

SPEC-FROZEN: true

Ceremony justification: single test function (`test_018()` in
`tests/skills/test-aai-run-tests.sh`) changed, test-only — no production code
(`.aai/scripts/aai-reap-tests.sh` is explicitly out of scope and unmodified).
`tests/skills/test-aai-run-tests.sh` is verified NOT in `protected_paths_l3`
(docs/ai/docs-audit.yaml: state engine, allocator, guards, `WORKFLOW.md`,
`CONSTITUTION.md`). Mechanical, reversible, single-surface fix -> L1 lean lane.

## Links
- Requirement: docs/issues/ISSUE-0023-test-018-workspace-isolation.md
- Technology contract: docs/TECHNOLOGY.md
- Learned rules: docs/knowledge/LEARNED.md (Session 2026-07-19 — Linux
  portability, CI-authoritative-when-only-CI-reproduces)

## Problem
`tests/skills/test-aai-run-tests.sh::test_018()` proves the reaper's LEGACY
fixed-threshold fail-safe (invoked when `AAI_REAP_STEP_START_EPOCH` is
unset/empty/non-integer/negative/zero/future). All 6 invalid-epoch cases
(`UNSET EMPTY abc -5 0 $future`) and both directions (`reap-old` MIN_AGE=1,
`spare-fresh` MIN_AGE=60) currently share ONE workspace — a single
`ws="$(mktemp -d "$TMP_ROOT/ws18.XXXXXX")"` above the `for invalid` loop
(current line ~568). The reaper (`.aai/scripts/aai-reap-tests.sh`) matches
candidate processes by workspace PATH PREFIX (`AAI_REAP_WORKSPACE`), so a
marker process that outlives its intended per-iteration reap (or a slow kill
under CI host load) stays matchable by ANY later case's reaper invocation —
the exact residual flake ("fail-safe broken (case='-5'): … must still spare
the fresh match (reaper output: reaped: 1)", observed on PR #122 and #127).
The prior fix (SPEC-0064, PR #123) corrected the per-direction MIN_AGE margins
but left this shared-workspace vector open. Per the issue's constraint, the
correct fix is STATE ISOLATION (fresh workspace + guaranteed teardown), not a
further margin widening.

## Scope
- In scope: `tests/skills/test-aai-run-tests.sh`, function `test_018()` only —
  (a) replace the single shared `$ws` with a fresh `mktemp -d` workspace per
  case (each of the 6 invalid-epoch cases gets its own workspace; a workspace
  reused across both directions of the SAME case is acceptable since both
  markers in one case are torn down before the case ends), and (b)
  unconditionally tear down BOTH `old_pid` and `fresh_pid` each iteration
  (today only `fresh_pid` has an unconditional `kill -9`; `old_pid` is killed
  only on the failure branch, i.e. never on the pass path).
- Out of scope: `.aai/scripts/aai-reap-tests.sh` (the reaper) — untouched;
  its epoch guard and workspace-prefix matching are correct and independently
  proven by TEST-006/016/017/019. Any other `test_0NN()` function in the same
  file. The split-direction MIN_AGE margins themselves (1 / 60) — preserved
  unchanged, not widened.
- Protected paths touched: none (`tests/skills/test-aai-run-tests.sh` verified
  absent from `protected_paths_l3`).

## Implementation strategy
- Strategy: loop
- Rationale: mechanical test-isolation fix confined to one existing function —
  swap a shared `mktemp -d` for a per-case one and add an unconditional
  teardown line per direction. No new production behavior, no design decision
  in flight; RED-GREEN-REFACTOR discipline adds no signal beyond RED-proofing
  the new structural assertions (still required below, per the RED-proof
  obligation applying regardless of strategy).

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: single test file, single function, no protected path, no
  migration, fully reversible (`git diff` of one function). Isolation adds
  process overhead without a corresponding safety benefit at this scope.
- User decision: undecided
- Base ref: main (current branch: fix/test-018-workspace-isolation)
- Worktree branch/path: n/a (not_needed)
- Inline review scope: `tests/skills/test-aai-run-tests.sh` (diff range: this
  branch vs `main`, `test_018()` only)

## Acceptance Criteria Mapping

- Maps to: ISSUE-0023-test-018-workspace-isolation Verification bullet 1
  (fresh workspace per case/direction)
- Spec-AC-01: Each of the 6 invalid-epoch cases in `test_018()` uses a FRESH
  `mktemp -d` workspace — no single workspace variable is assigned once above
  the `for invalid` loop and reused by all 6 cases.
  - Verification: TEST-001 (no `mktemp -d` before the loop starts) and
    TEST-002 (the per-case `mktemp -d` workspace lives INSIDE the `for invalid`
    loop body, so it runs fresh each iteration; discriminates old vs new: 0 vs 1
    occurrence within the loop body) both pass.

- Maps to: ISSUE-0023-test-018-workspace-isolation Verification bullet 2
  (guaranteed teardown of both processes every iteration)
- Spec-AC-02: Every process spawned in a `test_018()` iteration — BOTH
  `old_pid` (reap-old direction) and `fresh_pid` (spare-fresh direction) — is
  unconditionally killed before the next case begins; today only `fresh_pid`
  has an unconditional `kill -9`, while `old_pid` is killed only inside the
  failure (`log_fail`) branch, i.e. never on the pass path — the exact leak
  vector.
  - Verification: TEST-003 (an unconditional `kill -9 "$old_pid"` exists
    outside the failure branch, in addition to the pre-existing one inside it)
    passes.

- Maps to: ISSUE-0023-test-018-workspace-isolation Constraints/Risks (do not
  widen margins)
- Spec-AC-03: The split-direction load-immune margins are PRESERVED unchanged
  — `reap-old` still runs at MIN_AGE=1, `spare-fresh` still runs at
  MIN_AGE=60 — so both directions keep proving the LEGACY path was taken.
  - Verification: TEST-004 (both `reap_run "$invalid" 1` and
    `reap_run "$invalid" 60` call sites are still present, unchanged; verified
    2026-07-22 at `grep -cE 'reap_run "\$invalid" (1|60)\)"'
    tests/skills/test-aai-run-tests.sh` -> `2` against the current file)
    passes.

- Maps to: ISSUE-0023-test-018-workspace-isolation Verification bullet 3
  (suite exits 0; CI green)
- Spec-AC-04: `bash tests/skills/test-aai-run-tests.sh` exits 0 on macOS,
  including a passing TEST-018.
  - Verification: TEST-005 passes.
- Spec-AC-05: The CI `skill-suite` job is green on Ubuntu across a repeated
  run at the same commit (the flake is load-related and reproduces only under
  Linux CI — CI is the authoritative environment for this claim; the fix
  removes the MECHANISM structurally per Spec-AC-01/02 rather than relying on
  a lucky run).
  - Verification: TEST-006 passes.

## Constitution deviations

None.

<!-- Art.1 evidence-before-claims: measurable AC + TEST-xxx below; RED-proof
  required for the new structural assertions (TEST-001/002/003); no PASS
  claimed in planning. Art.2 KISS/YAGNI: minimal per-case mktemp + one
  additional unconditional kill line; no new helper abstraction, no change to
  sibling tests. Art.3 portability: plain POSIX `mktemp -d` (already used
  elsewhere in this file), no new platform surface. Art.4 degrade-and-report:
  n/a (test fixture only, no runtime degrade path). Art.5 additive: the 6-case
  loop, both directions, and the two MIN_AGE margins are unchanged; only
  workspace scoping and teardown timing change. Art.6 single-writer: no
  docs/ai/STATE.yaml write in this change. Art.7 operator-only merge: planning
  does not merge. -->

## Seam analysis
- Shared consumer: `.aai/scripts/aai-reap-tests.sh` is read by every
  `test_0NN()` in this file (TEST-006/016/017/018/019), not owned by this
  change. It is unmodified here and independently proven correct by
  TEST-006/016/017/019 (epoch mode) and by TEST-018 itself (legacy fail-safe)
  — no new seam is introduced by isolating TEST-018's own fixture state.
- Intra-suite collision: sibling tests already mint their own `mktemp -d`
  workspace (`ws16.XXXXXX`, `ws17.XXXXXX`, …) under the same `$TMP_ROOT`; this
  change follows the identical pattern for TEST-018's per-case workspaces
  (`ws18*.XXXXXX`), and `mktemp`'s guaranteed-unique random suffix rules out
  collision between cases or with sibling tests. No integration test is added
  for this — it is the same pattern already exercised successfully by
  TEST-006/016/017, so no residual risk is recorded.
- No cross-feature seam: this is a test-only isolation fix with no production
  code path, no shared DB/state table, and no field consumed by another
  screen or feature.

## Acceptance Criteria Status

| Spec-AC    | Description                                                          | Status  | Evidence | Review-By | Notes |
|------------|-----------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Each of the 6 cases uses a fresh `mktemp -d` workspace (no shared `$ws`) | done | TEST-001 → 0 (no mktemp before loop); TEST-002 → 1 inside loop body, discriminates old=0/new=1 | — | — |
| Spec-AC-02 | Both `old_pid` and `fresh_pid` unconditionally torn down each iteration | done | TEST-003 → 2 (`kill -9 "$old_pid" "$fresh_pid"` per iteration) | — | — |
| Spec-AC-03 | Split-direction margins (MIN_AGE=1 / 60) preserved unchanged           | done | TEST-004 → 2 margin call sites unchanged; `git diff main...HEAD -- .aai/scripts/aai-reap-tests.sh` empty (reaper untouched) | — | — |
| Spec-AC-04 | `bash tests/skills/test-aai-run-tests.sh` exits 0 on macOS             | done | TEST-005 → full suite exit 0, TEST-018 PASS (validation 2026-07-22) | — | — |
| Spec-AC-05 | CI `skill-suite` green on Ubuntu across a repeated run at the same commit | done | skill-suite run 29953801471 @ HEAD 1f725c2 — attempt 1 + attempt 2 both `success` | — | — |

## Implementation plan
- Components/modules affected: `tests/skills/test-aai-run-tests.sh`,
  `test_018()` only (approx. current lines 566-610).
- Data flow: none beyond the existing fixture — spawn marked `sleep`
  processes, invoke the reaper with `AAI_REAP_WORKSPACE` scoped to a fresh
  per-case `mktemp -d`, assert liveness, tear down.
- Edge cases:
  - A case that itself fails calls `log_fail`, which `exit 1`s immediately —
    the script-level `trap cleanup EXIT` (via the `SPAWNED_PIDS_FILE`
    tracked-pid sweep) already reaps every spawned pid on that path. The
    residual leak this spec fixes is specifically the PASSING-case path,
    where the loop continues to the next iteration without an intervening
    exit, and only `fresh_pid` (not `old_pid`) is guaranteed dead.
  - `future` (the far-future epoch string case) still exercises the same
    fresh-workspace-per-case pattern as the other 5 invalid values — no
    special-casing needed.
  - A workspace may be shared by the two directions WITHIN one case (they
    still execute sequentially and both are torn down before the case ends);
    only cross-CASE and cross-iteration sharing is the isolation target.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)               | Description                                                                                                                    | Status  |
|----------|------------|-------------|-------------------------------------|----------------------------------------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit (structural) | tests/skills/test-aai-run-tests.sh | `awk '/^test_018\(\)/,/for invalid/{print}' tests/skills/test-aai-run-tests.sh \| grep -c 'mktemp -d'` -> `0` (no workspace mktemp executes before the per-case loop begins). RED-proof: verified 2026-07-22 against the current file -> `1` (the shared `$ws` sits in this slice). | pending |
| TEST-002 | Spec-AC-01 | unit (structural) | tests/skills/test-aai-run-tests.sh | `sed -n '/for invalid in/,/^  done$/p' tests/skills/test-aai-run-tests.sh \| grep -c 'mktemp -d'` -> `1` (the per-case workspace mktemp lives INSIDE the loop body, so it runs fresh each iteration). RED-proof: verified 2026-07-22 against the pre-fix file -> `0` (the shared `$ws` mktemp sat BEFORE the loop). A raw occurrence count is not used — one line executed 6x is one textual occurrence; the discriminating signal is the mktemp being inside vs. before the loop. | pending |
| TEST-003 | Spec-AC-02 | unit (structural) | tests/skills/test-aai-run-tests.sh | `awk '/^test_018\(\)/,/^}/{print}' tests/skills/test-aai-run-tests.sh \| grep -c 'kill -9 "\$old_pid"'` -> `>= 2` (the pre-existing failure-branch kill plus a new unconditional per-iteration kill). RED-proof: verified 2026-07-22 against the current file -> `1`. | pending |
| TEST-004 | Spec-AC-03 | unit (structural) | tests/skills/test-aai-run-tests.sh | `grep -cE 'reap_run "\$invalid" (1\|60)\)"' tests/skills/test-aai-run-tests.sh` -> `2` (both direction call sites present, thresholds unchanged). Non-regression guard — verified 2026-07-22 already `2` pre-change; gates against accidental margin widening during the isolation edit, not a new-behavior RED-proof. | pending |
| TEST-005 | Spec-AC-04 | e2e         | tests/skills/test-aai-run-tests.sh | `bash tests/skills/test-aai-run-tests.sh` -> exit 0, output includes a PASS line for TEST-018 (local macOS sanity run; not expected to reproduce the load-only flake). | pending |
| TEST-006 | Spec-AC-05 | e2e (CI)    | .github/workflows/skill-suite.yml   | After push, `gh run list --workflow=skill-suite.yml --branch fix/test-018-workspace-isolation --json headSha,conclusion --limit 5 -q '.[] \| select(.headSha=="'"$(git rev-parse HEAD)"'") \| .conclusion'` shows `success` for >=2 runs at the same HEAD (the pushed run plus one `gh run rerun`) — CI is authoritative per the issue's honest-verification note. | pending |

Notes:
- Every Spec-AC has >=1 TEST-xxx.
- RED-proof obligation: TEST-001/002/003 gate NEW structural assertions and
  MUST be observed FAILING against the current (pre-change) file before their
  PASS counts as evidence — regardless of `loop` strategy (a test never seen
  failing may be tautological). TEST-004 is a non-regression guard (already
  green pre-change; it protects against the isolation edit accidentally
  touching the margins, the same class as SPEC-0058's TEST-002). TEST-005/006
  are end-to-end confirmations, not independently RED-proofable (the flake
  they guard against is load/CI-only, not reproducible on demand).
- Test IDs are stable — do not renumber after freeze.
- At ceremony level 1 this Test Plan IS the declared validation scope: every
  row above names a directly executable command.

## Verification
- `bash tests/skills/test-aai-run-tests.sh` -> exit 0 (TEST-005; includes
  TEST-018 passing on this machine).
- The four structural greps in TEST-001..004, run directly against
  `tests/skills/test-aai-run-tests.sh`, each match their stated expectation.
- `gh run list --workflow=skill-suite.yml ...` (TEST-006) shows `success` for
  >=2 runs at the same HEAD on Ubuntu.
- PASS criteria: all TEST-001..006 green; all Spec-AC-01..05 in a terminal
  status with non-empty Evidence; RED log/output captured for TEST-001/002/003
  before the fix is applied.

## Evidence contract
For each implementation, validation, and code review artifact, record:
- ref_id: test-018-workspace-isolation
- Spec-AC and TEST-xxx links: Spec-AC-01/TEST-001+002, Spec-AC-02/TEST-003,
  Spec-AC-03/TEST-004, Spec-AC-04/TEST-005, Spec-AC-05/TEST-006
- command or review scope: the six commands in the Test Plan above; review
  scope is `tests/skills/test-aai-run-tests.sh` (diff vs `main`)
- exit code or review verdict
- evidence path (RED/GREEN capture under docs/ai/tdd/ or inline in the
  implementation return record; review under docs/ai/reviews/)
- commit SHA or diff range when available
