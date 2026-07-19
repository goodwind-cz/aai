---
id: spec-prompt-diet-floor-credit-drift
type: spec
number: 60
status: done
ceremony_level: 1
links:
  requirement: prompt-diet-floor-credit-drift
  rfc: null
  pr:
    - 115
  commits:
    - 6130cef4fb51c96a2d2470f307a4111f6ddfff4a
---

# Spec: prompt-diet byte-floor credit drift — single sourceable ledger both suites read

SPEC-FROZEN: true

Reserved display number (RFC-0007): NONE minted in-branch. This file stays
`SPEC-0060-spec-prompt-diet-floor-credit-drift.md` with `number: null`; the
sequential integer is minted/reserved at merge by
`.aai/scripts/allocate-doc-number.mjs`. The slug id is `spec-`-prefixed
(`spec-prompt-diet-floor-credit-drift`) per spec-lint's `spec-id-shape` rule so it
can NEVER collide with the intake's id (`prompt-diet-floor-credit-drift`).

Ceremony justification: test-infrastructure-only change across a single logical
surface (the prompt-diet byte-floor test fixtures). It extracts three already-
existing inline constants + the `JUSTIFIED_ADDITIONS` ledger + two pure helpers
into one sourceable file `tests/skills/lib/prompt-diet-ledger.sh` that both suites
read, and gives `test-aai-verify-gate.sh` TEST-006 the same credited formula.
No production/runtime/agent-facing behavior changes; the ledger sum stays 9239
verbatim. The three touched paths (`tests/skills/lib/prompt-diet-ledger.sh`,
`tests/skills/test-aai-prompt-diet.sh`, `tests/skills/test-aai-verify-gate.sh`)
are verified NOT in `protected_paths_l3` (docs/ai/docs-audit.yaml — state engine,
allocator, guards, WORKFLOW.md, CONSTITUTION.md); no workflow canon touched.
Behavior-preserving, single surface, reversible, low-risk → L1 lean lane.

## Links
- Requirement: docs/issues/ISSUE-0017-prompt-diet-floor-credit-drift.md
- Sibling spec (ledger origin): docs/specs/SPEC-0059-spec-prompt-diet-itemized-growth-ledger.md
- Prior true-up history: docs/specs/SPEC-0048-prompt-diet-byte-budget-true-up.md; docs/issues/DEBT-0002-prompt-diet-byte-budget-true-up.md
- Technology contract: docs/TECHNOLOGY.md
- Learned rules: docs/knowledge/LEARNED.md (DEBT-0002 / "two copies of one gate" drift pattern)

## Problem (WHAT/WHY lives in the intake; this is the HOW anchor)
Two suites hardcode `BASELINE_PROMPT_BYTES=357457` and
`REQUIRED_REDUCTION_BYTES=28672`. `test-aai-prompt-diet.sh` TEST-010 credits the
justified-growth ledger (`+ JUSTIFIED_GROWTH_BYTES`, =9239) and PASSES;
`test-aai-verify-gate.sh` TEST-006 omits the credit and FAILS on the default
branch (`reduction = 20455 < 28672`; observed exit 1, after=328748, extra=8254).
The two floors have drifted because the credit mechanism lives in only one copy.
Structural fix: one sourceable ledger both suites read, so a single definition
of each constant makes divergence impossible.

## Implementation strategy
- Strategy: tdd
- Rationale: This is a bug fix that requires a durable regression proof, and the
  gating RED already exists naturally (`./tests/skills/test-aai-verify-gate.sh`
  exits 1 on TEST-006 today — observed 2026-07-19). RED → GREEN → REFACTOR maps
  cleanly: (RED) the credited-floor assertion and the single-source wiring
  assertion both fail before the change; (GREEN) create the shared ledger, source
  it in both suites, add the credit term to TEST-006; (REFACTOR) delete the now-
  duplicated inline constant/ledger/helper definitions from the prompt-diet suite
  so only one definition survives. Locking the anti-drift guarantee GREEN is the
  whole point, so a test-first discipline is appropriate despite the mechanical
  extraction.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: Small, low-risk, single-surface, reversible test-infra
  change on three files; no protected paths, no runtime surface, no migration.
  Work already proceeds on branch `feat/prompt-diet-shared-ledger`.
- User decision: undecided
- Base ref: feat/prompt-diet-shared-ledger
- Worktree branch/path: n/a
- Inline review scope: tests/skills/lib/prompt-diet-ledger.sh,
  tests/skills/test-aai-prompt-diet.sh, tests/skills/test-aai-verify-gate.sh

## Acceptance Criteria Mapping

Maps the single intake requirement (Verification section of
ISSUE-0017-prompt-diet-floor-credit-drift.md) to implementation-oriented,
individually verifiable Spec-ACs.

- Maps to: intake Verification bullet 3 ("Both suites read the shared ledger from
  a single source; changing the ledger in one place is reflected in both")
  - Spec-AC-01: A single sourceable file `tests/skills/lib/prompt-diet-ledger.sh`
    exists and, when sourced into a bash shell, defines in the sourcing shell's
    GLOBAL scope: `BASELINE_PROMPT_BYTES=357457`, `REQUIRED_REDUCTION_BYTES=28672`,
    `HEADROOM_CAP=2048`, the `JUSTIFIED_ADDITIONS` array with its 3 entries
    verbatim, `JUSTIFIED_GROWTH_BYTES` computed by the portable
    `${_entry%% *}` + `$(( ))` summation equal to `9239`, and the two pure
    helpers `compute_reduction_headroom` and `justified_growth_breach_suggestion`.
    Uses no `bc`, no `mapfile`, no `declare -A` (bash-3.2 / Windows-Git-Bash safe).
    - Verification: `bash -c 'set -e; source tests/skills/lib/prompt-diet-ledger.sh;
      [ "$BASELINE_PROMPT_BYTES" -eq 357457 ]; [ "$REQUIRED_REDUCTION_BYTES" -eq 28672 ];
      [ "$HEADROOM_CAP" -eq 2048 ]; [ "$JUSTIFIED_GROWTH_BYTES" -eq 9239 ];
      declare -p JUSTIFIED_ADDITIONS; declare -f compute_reduction_headroom;
      declare -f justified_growth_breach_suggestion'` exits 0.

- Maps to: intake Verification bullet 3 (drift structurally impossible)
  - Spec-AC-02: BOTH suites source the shared ledger via a CWD-independent path
    (`"$SCRIPT_DIR/lib/prompt-diet-ledger.sh"`, resolved from `BASH_SOURCE`
    before/independent of the `cd "$PROJECT_ROOT"`), and NEITHER suite re-defines
    `BASELINE_PROMPT_BYTES`, `REQUIRED_REDUCTION_BYTES`, `HEADROOM_CAP`, or the
    `JUSTIFIED_ADDITIONS` array inline. Exactly one definition of each survives.
    - Verification: `grep -lF 'lib/prompt-diet-ledger.sh' tests/skills/test-aai-prompt-diet.sh
      tests/skills/test-aai-verify-gate.sh` lists both files; AND
      `grep -REc '^[[:space:]]*(BASELINE_PROMPT_BYTES|REQUIRED_REDUCTION_BYTES|HEADROOM_CAP)='
      tests/skills/test-aai-prompt-diet.sh tests/skills/test-aai-verify-gate.sh`
      reports 0 inline assignments in each suite; AND
      `grep -Ec '^JUSTIFIED_ADDITIONS=\(' tests/skills/test-aai-*.sh` reports 0.

- Maps to: intake Verification bullet 1 (`test-aai-verify-gate.sh` exits 0 /
  TEST-006 PASS)
  - Spec-AC-03: `test-aai-verify-gate.sh` TEST-006 applies the identical credited
    formula `reduction = BASELINE - after - extra + JUSTIFIED_GROWTH_BYTES` (sourced,
    not re-typed) and PASSES; the whole suite exits 0.
    - Verification: `./tests/skills/test-aai-verify-gate.sh; echo "exit=$?"` →
      `exit=0` and a `PASS TEST-006` line in stdout.

- Maps to: intake Verification bullet 2 (`test-aai-prompt-diet.sh` still exits 0;
  ledger integrity unchanged — array still sums to 9239 via `declare -p`)
  - Spec-AC-04: `test-aai-prompt-diet.sh` still exits 0 after the extraction, with
    TEST-010 (credited reduction within `[0, HEADROOM_CAP]`), TEST-012
    (`JUSTIFIED_GROWTH_BYTES == 9239 == independent re-sum`) and TEST-013 (array
    `declare -p`-visible, ≥3 numeric-leading entries) all PASS. Confirms the
    sourced array remains visible to `declare -p` in the test functions.
    - Verification: `./tests/skills/test-aai-prompt-diet.sh; echo "exit=$?"` →
      `exit=0` with `PASS TEST-010`, `PASS TEST-012`, `PASS TEST-013` lines.

## Seam analysis (rule 6a)
- Seam S1 — the byte-floor CONTRACT shared by two independent suites: both
  `test-aai-prompt-diet.sh` (TEST-010) and `test-aai-verify-gate.sh` (TEST-006)
  read the same baseline/floor/credit. This shared record is exactly what drifted.
  - Crossing test: TEST-004 (Spec-AC-02) proves the seam structurally — after the
    change there is exactly ONE definition of each constant (in the lib), so the
    two consumers can no longer diverge. TEST-005 + TEST-006 (below) additionally
    exercise both consumers end-to-end (both suites exit 0) reading through the
    single source.
  - Residual risk: there is no runtime "mutate-and-observe-both" test. This is
    accepted and is STRONGER than a mutation test: single-sourcing removes the
    second definition entirely, so divergence is impossible by construction rather
    than merely detected after the fact. Recorded, not mitigated further.

## Constitution deviations

None.

- Art. 1 (Evidence before claims): every Spec-AC names an executable command with
  an expected exit code; freeze claims no PASS. Compliant.
- Art. 2 (Simplicity): removes a duplicated definition; adds one small sourceable
  file — net simplification, nothing speculative. Compliant.
- Art. 3 (Portability): plain bash, git-diffable; no `bc`/`mapfile`/`declare -A`;
  CWD-independent source path keeps tri-platform + bash-3.2 behavior. Compliant.
- Art. 4 (Degrade and report): breach helper still emits the paste-ready ledger
  suggestion; a missing lib surfaces as a hard sourcing error (fail-fast). Compliant.
- Art. 5 (Additive first): the `JUSTIFIED_ADDITIONS` array name, its 3 entries, and
  the 9239 sum are preserved verbatim; TEST-006 gains a term (additive) — no public
  contract broken. Compliant.
- Art. 6 (Single-writer state): no STATE.yaml write in this scope. Compliant.
- Art. 7 (Operator-only merge): planning only; no merge. Compliant.

## Acceptance Criteria Status

| Spec-AC    | Description                                                        | Status | Evidence                                                              | Review-By | Notes                                                        |
|------------|-------------------------------------------------------------------|--------|----------------------------------------------------------------------|-----------|--------------------------------------------------------------|
| Spec-AC-01 | Shared ledger file defines constants + array + helpers (sum 9239) | done   | docs/ai/tdd/green-20260719T084714Z-prompt-diet-floor-credit-drift.log | —         | tests/skills/lib/prompt-diet-ledger.sh present; TEST-001/002 green |
| Spec-AC-02 | Both suites source it; no inline redefinition (single-source)     | done   | docs/ai/tdd/green-20260719T084714Z-prompt-diet-floor-credit-drift.log | —         | 0 inline BASELINE/REQUIRED/HEADROOM/array defs in either suite; TEST-003/004 green |
| Spec-AC-03 | verify-gate TEST-006 credited formula PASSES; suite exits 0       | done   | docs/ai/tdd/green-20260719T084714Z-prompt-diet-floor-credit-drift.log | —         | RED docs/ai/tdd/red-20260719T084434Z-...log → GREEN exit 0; TEST-005 green |
| Spec-AC-04 | prompt-diet suite still exits 0 (TEST-010/012/013 PASS)           | done   | docs/ai/tdd/green-20260719T084714Z-prompt-diet-floor-credit-drift.log | —         | declare -p ledger integrity preserved (sum 9239); TEST-006 green |

## Implementation plan
- Components/modules affected:
  - NEW `tests/skills/lib/prompt-diet-ledger.sh` — the single source. Contains,
    lifted verbatim from the current prompt-diet suite (lines ~31-79):
    `BASELINE_PROMPT_BYTES`, `REQUIRED_REDUCTION_BYTES`, the `JUSTIFIED_ADDITIONS`
    array (3 entries), the `JUSTIFIED_GROWTH_BYTES` summation loop, `HEADROOM_CAP`,
    and the `compute_reduction_headroom` / `justified_growth_breach_suggestion`
    helpers. Keep every explanatory comment (DEBT-0002/SPEC-0048/SPEC-0059 history)
    so provenance is not lost. The file must NOT `set -u`/`cd`/run tests — it is a
    pure library; guard against nothing (it is only sourced, never executed).
  - `tests/skills/test-aai-prompt-diet.sh` — replace the inline definitions
    (lines ~31-79) with `source "$SCRIPT_DIR/lib/prompt-diet-ledger.sh"` placed at
    top level (NOT inside a function) so the array stays a global visible to
    `declare -p` in TEST-012/013. Keep the source AFTER `SCRIPT_DIR`/`PROJECT_ROOT`
    are computed; the absolute `$SCRIPT_DIR` path resolves regardless of the
    subsequent `cd "$PROJECT_ROOT"`.
  - `tests/skills/test-aai-verify-gate.sh` — replace the inline
    `BASELINE_PROMPT_BYTES`/`REQUIRED_REDUCTION_BYTES` block (lines ~26-29) with the
    same top-level `source "$SCRIPT_DIR/lib/prompt-diet-ledger.sh"`, and change
    TEST-006 (`test_006_prompt_diet_floor`, lines ~130-142) so `reduction` includes
    `+ JUSTIFIED_GROWTH_BYTES` (equivalently call `compute_reduction_headroom` and
    test the returned headroom `>= 0`). Update the stale comment that claims "same
    formula, re-measured here" to reflect the now genuinely-shared source.
- Data flows: `SCRIPT_DIR` (from `BASH_SOURCE`) → source lib → globals available to
  every test function in the same shell process (`main` calls functions directly,
  no subshell — so `declare -p` sees them).
- Edge cases:
  - `declare -p` visibility: sourcing at top level = global scope; equivalent to
    today's top-level assignment. TEST-012/013 must still pass (Spec-AC-04 guards).
  - CWD independence: both suites are runnable from repo root; the source path is
    `$SCRIPT_DIR/lib/...` (absolute), immune to the later `cd`.
  - Third consumer: `tests/skills/test-aai-ceremony-levels.sh` does NOT copy the
    constants — it re-invokes `test-aai-prompt-diet.sh` as a subprocess and asserts
    exit 0. It needs NO change and stays green once the prompt-diet suite exits 0.
  - verify-gate TEST-006 stays a LOWER-bound floor check only. The upper `HEADROOM_CAP`
    anti-bloat guard remains prompt-diet TEST-010's sole responsibility — do NOT add
    a second cap gate to verify-gate (that would re-introduce the very "two copies of
    one gate" drift this change eliminates).

## Test Plan
For each Spec-AC, concrete tests. Every row names a directly executable command
(L1 lightweight-lane requirement). "Suite TEST-nnn" refers to the internal test id
inside the named `.sh` file.

| Test ID  | Spec-AC    | Type        | File path (expected)                          | Description / executable command | Status |
|----------|------------|-------------|-----------------------------------------------|----------------------------------|--------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/lib/prompt-diet-ledger.sh        | `bash -c 'set -e; source tests/skills/lib/prompt-diet-ledger.sh; [ "$BASELINE_PROMPT_BYTES" -eq 357457 ]; [ "$REQUIRED_REDUCTION_BYTES" -eq 28672 ]; [ "$HEADROOM_CAP" -eq 2048 ]; [ "$JUSTIFIED_GROWTH_BYTES" -eq 9239 ]; declare -p JUSTIFIED_ADDITIONS'` exits 0 | green |
| TEST-002 | Spec-AC-01 | unit        | tests/skills/lib/prompt-diet-ledger.sh        | `bash -c 'set -e; source tests/skills/lib/prompt-diet-ledger.sh; declare -f compute_reduction_headroom; declare -f justified_growth_breach_suggestion; read -r r h <<<"$(compute_reduction_headroom 357457 328748 8254 9239 28672)"; [ "$r" -eq 29694 ]; [ "$h" -eq 1022 ]'` exits 0 (helpers behave identically to inline) | green |
| TEST-003 | Spec-AC-02 | integration | tests/skills/test-aai-*.sh                     | `test $(grep -lF 'lib/prompt-diet-ledger.sh' tests/skills/test-aai-prompt-diet.sh tests/skills/test-aai-verify-gate.sh | wc -l | tr -d ' ') -eq 2` (both suites source the shared file) | green |
| TEST-004 | Spec-AC-02 | integration | tests/skills/test-aai-*.sh                     | Seam S1 anti-drift: `! grep -REq '^[[:space:]]*(BASELINE_PROMPT_BYTES|REQUIRED_REDUCTION_BYTES|HEADROOM_CAP)=' tests/skills/test-aai-prompt-diet.sh tests/skills/test-aai-verify-gate.sh` AND `! grep -Eq '^JUSTIFIED_ADDITIONS=\(' tests/skills/test-aai-prompt-diet.sh tests/skills/test-aai-verify-gate.sh` (exactly one definition survives — in the lib) | green |
| TEST-005 | Spec-AC-03 | integration | tests/skills/test-aai-verify-gate.sh          | `./tests/skills/test-aai-verify-gate.sh; echo "exit=$?"` → `exit=0` with a `PASS TEST-006` line (RED captured: docs/ai/tdd/red-20260719T084434Z-...log, exit 1, `FAIL TEST-006`) | green |
| TEST-006 | Spec-AC-04 | integration | tests/skills/test-aai-prompt-diet.sh          | `./tests/skills/test-aai-prompt-diet.sh; echo "exit=$?"` → `exit=0` with `PASS TEST-010`, `PASS TEST-012`, `PASS TEST-013` (declare -p ledger integrity preserved, sum 9239) | green |

RED-proof obligation: TEST-005 was RED on `feat/prompt-diet-shared-ledger` before
the change (evidence docs/ai/tdd/red-20260719T084434Z-prompt-diet-floor-credit-drift.log:
`RED_CLASS: product_red`; exit 1, `FAIL TEST-006 prompt-diet floor broken (net
reduction 20455 bytes < 28672)`). TEST-003/TEST-004/TEST-001/TEST-002 were RED
before the change because `tests/skills/lib/prompt-diet-ledger.sh` did not exist
and the suites did not source it. GREEN evidence:
docs/ai/tdd/green-20260719T084714Z-prompt-diet-floor-credit-drift.log (all suites
exit 0).

Notes:
- Every Spec-AC has ≥1 TEST-xxx entry. Test IDs are stable.
- Suite-internal TEST-006 (verify-gate) and TEST-010/012/013 (prompt-diet) are the
  concrete assertions the spec's TEST-005/006 rows execute end-to-end.

## Verification
- Commands to run (full gate):
  - `bash -c 'set -e; source tests/skills/lib/prompt-diet-ledger.sh; [ "$JUSTIFIED_GROWTH_BYTES" -eq 9239 ]; declare -p JUSTIFIED_ADDITIONS'`
  - `grep -lF 'lib/prompt-diet-ledger.sh' tests/skills/test-aai-prompt-diet.sh tests/skills/test-aai-verify-gate.sh`
  - `./tests/skills/test-aai-verify-gate.sh`  (expect exit 0, PASS TEST-006)
  - `./tests/skills/test-aai-prompt-diet.sh`  (expect exit 0, PASS TEST-010/012/013)
  - `./tests/skills/test-aai-ceremony-levels.sh`  (expect exit 0 — subprocess re-run of prompt-diet stays green; regression guard for the third consumer)
- Evidence artifacts: docs/ai/tdd/red-20260719T084434Z-prompt-diet-floor-credit-drift.log (RED),
  docs/ai/tdd/green-20260719T084714Z-prompt-diet-floor-credit-drift.log (GREEN, all suites exit 0).
- PASS criteria: all TEST-xxx in status green AND all Spec-AC in a terminal status
  (done) with non-empty evidence. — MET.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: prompt-diet-floor-credit-drift
- Spec-AC and TEST-xxx links where applicable
- command or review scope (from the Test Plan / Verification above)
- exit code or review verdict
- evidence path (log capture)
- commit SHA or diff range when available
