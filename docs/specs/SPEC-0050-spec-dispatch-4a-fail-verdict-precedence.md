---
id: spec-dispatch-4a-fail-verdict-precedence
type: spec
number: 50
status: implementing
ceremony_level: 2
links:
  change: dispatch-4a-fail-verdict-precedence
  rfc: null
  pr: []
  commits: []
---

# SPEC — Rule 4a Must Not Retarget Away From an Unaddressed FAIL Verdict

SPEC-FROZEN: true

## Links
- Change: dispatch-4a-fail-verdict-precedence
  (docs/issues/CHANGE-0036-dispatch-4a-fail-verdict-precedence.md)
- Reconciles (does NOT reopen): spec-dispatch-new-intake-after-completed-scope
  (docs/specs/SPEC-0042-spec-dispatch-new-intake-after-completed-scope.md,
  done — D1 defines rule 4a; D5 says fail verdicts fire regardless of item
  status; this change makes D5 hold for the done+flushed corner D1 created).
- Origin: docs/ai/reviews/review-20260717T125756Z.md NB-1; decisions.jsonl
  disposition (CHANGE-0031, 2026-07-17).
- Technology contract: docs/TECHNOLOGY.md

## Number allocation
- File created as `docs/specs/SPEC-0050-spec-dispatch-4a-fail-verdict-precedence.md`
  with `number: null` (RFC-0007 / SPEC-0015 parallel-safe doc numbering). The
  sequential number is allocated at PR/merge by
  `.aai/scripts/allocate-doc-number.mjs` (+ SPEC-0047 origin reservation).
- Expected display id: **SPEC-0050**. Cross-branch collision check performed at
  planning (2026-07-17): highest SPEC number is SPEC-0049 in the local tree, in
  every `origin/*` branch tree, AND in the `refs/aai/docnums/SPEC-*` reservation
  refs (0048, 0049). No `SPEC-0050` exists anywhere. Next-free = 50.

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (SPEC-FROZEN: true)
- implementing: work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Ceremony level
`ceremony_level: 2` — full pipeline. Honest L1-vs-L2 reasoning (the intake
declared L3-scope in its filename slug but that is factually stale — see below):
- The diff is nominally single-surface and single-predicate: one added guard
  clause on the rule-4a arm of `decide()` plus additive tests. That is what
  makes L1 superficially plausible.
- But this scope changes dispatch BEHAVIOR (which role fires) on the
  deterministic dispatch core the loop itself executes. A wrong dispatch is
  self-amplifying. This is EXACTLY the reasoning the direct parent SPEC-0042
  recorded when it reclassified its own L1 intent up to L2 for the same file;
  consistency plus the behavior-change argument keep this change at L2.
- LEARNED 2026-07-16/17 ("two independent gates are not redundant"): this
  change EXISTS because an independent code review (NB-1) caught what the
  dispatch's own passing test suite missed. Keeping full ceremony preserves the
  second gate (full independent validation + code review) at full depth — the
  gate that surfaces exactly this class of defect.
- L3 is NOT mandatory and NOT forced: verified against `protected_paths_l3`
  in docs/ai/docs-audit.yaml (2026-07-17) — `.aai/scripts/orchestration-dispatch.mjs`
  is NOT listed (the list is state engine / allocator / guards / workflow
  canon). The intake's `l3-scope` filename note is factually stale, same as
  SPEC-0041/SPEC-0042 recorded for this file.

## Implementation strategy
- Strategy: tdd
- Rationale: the entire scope is deterministic-orchestration core logic,
  provable by table-driven fixtures — pure `decide()` variants and CLI exit
  codes / JSON payloads. It is a data-integrity guard on a governance-critical
  surface where a silent regression corrupts dispatch routing. There is no
  prompt-text or glue component that would justify a loop/hybrid split.
  RED-GREEN-REFACTOR per TEST-xxx with evidence in docs/ai/tdd/.
- RED-proof obligation: before any product edit, run the new suite functions
  against the pre-change tree and save the failing output to
  `docs/ai/tdd/dispatch-4a-fail-precedence-red.log`. Expected pre-change
  failures: TEST-001/TEST-002 (a done+flushed focus carrying a fail verdict +
  one open intake currently emits a rule-`4a` retarget, not rule 10/12
  Remediation), TEST-005 (the fail-closed invariant is violated — a 4a
  retarget is emitted for a fail-verdict shape), TEST-006 (the rule-4a `when`
  doc string does not yet mention the guard). TEST-003 (CLI) also REDs
  pre-change (exit-0 rule 4a instead of exit-0 rule 10/12). TEST-004 is a
  survival invariant — green pre-change by construction, non-vacuous because it
  re-runs the real legacy suite over the changed tree post-change.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: edits the deterministic dispatcher the loop executes
  (isolation is useful), but the change is a single additive predicate clause
  plus additive tests — materially smaller than SPEC-0042's new-arm + new-probe
  scope. Not required for safety.
- User decision: inline — already operator-approved and RECORDED in STATE
  ("operator-approved wave: inline on fix/dispatch-4a-fail-verdict-precedence").
  No new operator decision required; rule 8 does not gate (user_decision is not
  `undecided`).
- Base ref: main
- Inline review scope (explicit paths):
  - .aai/scripts/orchestration-dispatch.mjs (rule-4a arm: the added
    fail-verdict guard clause + its inline comment; the RULES table `4a`
    `when` doc string)
  - tests/skills/test-aai-orchestration-dispatch.sh (new stanzas
    test_013..test_018; reserved for this dispatch scope by SPEC-0041 D5)
  - docs/specs/SPEC-0050-spec-dispatch-4a-fail-verdict-precedence.md (this
    spec; renamed to SPEC-0050 at merge)
  - docs/issues/CHANGE-0036-dispatch-4a-fail-verdict-precedence.md (status
    lifecycle only)
  - docs/INDEX.md (regenerated)

## Design decisions

### D1 — The guard is a single added conjunct on the rule-4a predicate
Rule 4a currently fires on (orchestration-dispatch.mjs:314):
```js
if ((s.work_item == null || s.work_item.status === 'done') && s.flushed === true) {
```
Add ONE conjunct so the arm ABSTAINS whenever the completed focus carries a
recorded fail verdict. Exact frozen change (no rule reordering, no new rule,
purity preserved):
```js
// A recorded FAIL verdict (validation OR code review) on the completed focus
// is NOT retargetable: 4a must abstain so decide() falls through to rules
// 10/12 (Remediation) — a buried failure is worse than a delayed retarget
// (CHANGE-0036 / reconciles SPEC-0042 D5 for the done+flushed corner).
const focusHasFailVerdict = (s.validation && s.validation.status === 'fail')
  || (s.review && s.review.status === 'fail');
if ((s.work_item == null || s.work_item.status === 'done')
    && s.flushed === true
    && !focusHasFailVerdict) {
```

### D2 — Confirmed snapshot field names (NOT the STATE block names)
The intake and dispatch note referenced `last_validation.status` /
`code_review.status` — those are the STATE.yaml BLOCK names. In the `decide()`
snapshot shape (buildSnapshot, orchestration-dispatch.mjs:597-604) they are
projected as:
- `s.validation.status`  (from the `last_validation` block; enum pass|fail|not_run)
- `s.review.status`      (from the `code_review` block; enum not_run|pass|fail|waived)
The guard reads EXACTLY these two, matching how rule 10 (`vstatus === 'fail'`,
line 376) and rule 12 (`s.review.status === 'fail'`, line 394) already read
them. The `s.validation && ` / `s.review && ` null-guards mirror the existing
defensive reads and keep `decide()` total on hand-built snapshots.

### D3 — Confirmed: rules 10/12 fire for a done-status item once 4a abstains
Rules 10 and 12 are verdict-status-based and carry NO work-item-status guard:
- Rule 10 (line 376): `if (vstatus === 'fail')` → `dispatchFor('Remediation','10')`.
- Rule 12 (line 394): `if (s.review && s.review.status === 'fail')` →
  `dispatchFor('Remediation','12')`.
So a `status: done` work item with a fail verdict reaches Remediation PROVIDED
the earlier rules do not preempt. The traversal after 4a abstains passes:
rule 5 (spec present), rule 6 (frozen + frontmatter status draft/implementing),
rule 7 (strategy selected), rule 8 (user_decision not undecided), the
line-364 work-item presence check, and rule 9 (fires only when
`phase === 'planning' && status === 'done'` OR `phase === 'preparation'`).
Therefore the Remediation routing holds for the natural fail shape:
spec status `implementing`, an eligible phase (`validation` / `code_review` /
`remediation` / `implementation`), strategy set, worktree decided, and
`last_run_role !== 'Remediation'` (else rule 10/12 degrade to the existing
`possible_missing_remediation_reset` needs_llm — still fail-closed, still NOT a
retarget). The fixtures in TEST-001/TEST-002/TEST-003 are built to that shape.

### D4 — Fail-closed completeness (the invariant, broader than rule 10/12)
The guard's core guarantee is: **4a NEVER emits a retarget when a fail verdict
is present**, for every work-item / spec shape. Where decide() lands after
abstaining depends on the rest of the snapshot; every landing surfaces the
failure rather than burying it:
- `work_item.status === 'done'` + fail + eligible phase/spec → rule 10/12
  Remediation (the primary path, AC-001/AC-002).
- `work_item == null` (flush removed it) + fail → the line-364 guard returns
  `needs_llm ['focus_ref_not_in_active_work_items']` (surfaced, fail-closed;
  rules 10/12 are unreachable because they read `s.work_item`, but the fail is
  flagged, never silently retargeted).
- `work_item.status === 'done'` + fail + terminal (`done`) spec frontmatter →
  rule 6 `dispatch Planning` on the closed scope (re-plan, not a silent 4a
  retarget of the failure onto a different intake).
All three are "fall through, do not bury" — consistent with the change's core
intent. AC-005 asserts the invariant across these shapes; only the eligible
shape asserts rule 10/12 specifically.

### D5 — Additivity: existing suite stays byte-green, zero assertion edits
Every existing fixture (test_001..test_012) uses `validation` pass/not_run with
`review` pass/not_run, so `focusHasFailVerdict` is `false` and the 4a arm
evaluates exactly as today. No existing test asserts a 4a dispatch on a
fail-verdict shape. The change is strictly additive: new suite functions
test_013..test_018 only; no edit to any test_001..test_012 assertion, no rule
renumber, no output-field change (`retarget` stays as-is on every verdict).

## Acceptance Criteria Mapping
- Maps to: CHANGE-0036 AC-001 (validation fail → Remediation, not 4a)
  - Spec-AC-01; verification via TEST-001 (decide) + TEST-003 (CLI).
- Maps to: CHANGE-0036 AC-002 (code_review fail → Remediation, not 4a)
  - Spec-AC-02; verification via TEST-002 (decide) + TEST-003 (CLI).
- Maps to: CHANGE-0036 AC-003 (no fail verdict → 4a unchanged; suite green)
  - Spec-AC-03; verification via TEST-004.
- Maps to: CHANGE-0036 AC-004 (decide() pure; `when` doc string documents guard)
  - Spec-AC-04; verification via TEST-006.
- Maps to: CHANGE-0036 Constraints (fail-closed) + review NB-1 null-item shape
  - Spec-AC-05; verification via TEST-005.

Spec-AC list (each measurable):
- Spec-AC-01: Given a snapshot with `work_item.status === 'done'`,
  `flushed === true`, `validation.status === 'fail'`, spec present+frozen with
  frontmatter status `implementing`, an eligible phase (`validation`), strategy
  selected, `worktree.user_decision !== 'undecided'`, `last_run_role !==
  'Remediation'`, and exactly one open mappable intake in `open_intakes`,
  `decide()` returns `verdict === 'dispatch'`, `rule === '10'`, `role ===
  'Remediation'`, and `retarget === null`. It is NOT `rule === '4a'`.
- Spec-AC-02: The same shape with `validation.status === 'not_run'` and
  `review.status === 'fail'` and phase `code_review` returns `verdict ===
  'dispatch'`, `rule === '12'`, `role === 'Remediation'`, `retarget === null`;
  NOT `rule === '4a'`.
- Spec-AC-03: With NO fail verdict (`validation.status` in {pass, not_run} AND
  `review.status` in {pass, not_run, waived}), a done+flushed focus retains
  today's EXACT rule-4a behavior for all candidate counts — one mappable intake
  → `dispatch` rule `4a` retarget; zero → `no_action`
  `scope_complete_no_open_intake`; 2+/unmappable/scan-fail → `needs_llm` named
  reasons. `bash tests/skills/test-aai-orchestration-dispatch.sh` exits 0 with
  the pre-existing stanzas (test_001..test_012) unchanged (zero assertion
  edits).
- Spec-AC-04: `decide()` stays pure on a fail-verdict retarget-guard snapshot
  (same input → same output; input object unmutated), and the rule-`4a` `when`
  doc string in the RULES table documents the fail-verdict abstention guard
  (greppable for `fail`/`Remediation`/`10`).
- Spec-AC-05 (fail-closed invariant): For EVERY shape carrying a fail verdict
  (`validation.status === 'fail'` OR `review.status === 'fail'`) on a
  done/absent + flushed focus, `decide()` NEVER returns a `rule === '4a'`
  dispatch with a non-null `retarget`. Specifically: `work_item == null` + fail
  → `needs_llm` reason `focus_ref_not_in_active_work_items` with `retarget ===
  null`; both verdicts fail → still abstains (no 4a retarget).
- Spec-AC-06 (hygiene): `node .aai/scripts/docs-audit.mjs --check --strict
  --no-event` exit 0; `node .aai/scripts/check-state.mjs` OK; the full dispatch
  suite exits 0.

## Constitution deviations

None.

Honest per-article check at freeze (docs/CONSTITUTION.md):
- Art. 1 (evidence before claims): the guard tightens on executable verdict
  status; no verdict semantics weakened; RED-proof required. No deviation.
- Art. 2 (simplicity/YAGNI): one conjunct on one predicate; no new rule, probe,
  or field. No deviation.
- Art. 3 (portability): plain Node stdlib mjs + bash-3.2 tests. No deviation.
- Art. 4 (degrade and report): every fail shape surfaces a named outcome
  (Remediation dispatch, or a machine-greppable needs_llm reason); nothing
  silent. No deviation.
- Art. 5 (additive first): guard is a strict conjunct tightening; existing
  fixtures byte-identical; `retarget` field unchanged. No deviation.
- Art. 6 (single-writer STATE): dispatcher stays read-only. No deviation.
- Art. 7 (operator-only merge): untouched. No deviation.

## Acceptance Criteria Status

Tracks per-Spec-AC delivery state.

| Spec-AC    | Description                                                        | Status  | Evidence | Review-By | Notes |
|------------|--------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | validation fail on done+flushed focus → rule 10 Remediation, not 4a | done | TEST-013/TEST-015(a); docs/ai/tdd/dispatch-4a-fail-precedence-red.log, docs/ai/tdd/dispatch-4a-fail-precedence-green.log | — | — |
| Spec-AC-02 | code_review fail on done+flushed focus → rule 12 Remediation, not 4a | done | TEST-014/TEST-015(b); docs/ai/tdd/dispatch-4a-fail-precedence-red.log, docs/ai/tdd/dispatch-4a-fail-precedence-green.log | — | — |
| Spec-AC-03 | no fail verdict → 4a behavior unchanged; suite green, zero edits    | done | TEST-016; test_001..012 zero assertion edits (git diff --stat: 315 insertions/1 non-assertion deletion in main() header only); docs/ai/tdd/dispatch-4a-fail-precedence-green.log | — | — |
| Spec-AC-04 | decide() pure on fail snapshot; 4a `when` doc string documents guard | done | TEST-018; docs/ai/tdd/dispatch-4a-fail-precedence-red.log (doc-string half RED pre-change), docs/ai/tdd/dispatch-4a-fail-precedence-green.log | — | — |
| Spec-AC-05 | fail-closed invariant: no 4a retarget for any fail shape (incl. null item) | done | TEST-017; docs/ai/tdd/dispatch-4a-fail-precedence-red.log, docs/ai/tdd/dispatch-4a-fail-precedence-green.log | — | — |
| Spec-AC-06 | hygiene: docs-audit strict + check-state OK + full dispatch suite exit 0 | done | docs-audit --check --strict --no-event → CLEAN/exit 0; check-state.mjs → OK; full dispatch suite exit 0 (docs/ai/tdd/dispatch-4a-fail-precedence-green.log) | — | — |

## Implementation plan
- Components affected: orchestration core
  (.aai/scripts/orchestration-dispatch.mjs: the rule-4a arm's predicate gains
  one `&& !focusHasFailVerdict` conjunct + its inline comment; the RULES table
  `4a` `when` doc string gains the abstention clause), test layer
  (tests/skills/test-aai-orchestration-dispatch.sh: new functions
  test_013..test_018 mapped to TEST-001..TEST-006, registered in `main()`),
  docs/INDEX.md (regenerated).
- Order: (1) write new suite functions test_013..test_018; (2) RED run on the
  pre-change tree → docs/ai/tdd/dispatch-4a-fail-precedence-red.log
  (expected failures per the RED-proof note); (3) add the guard clause +
  inline comment + `when` doc-string edit (TEST-001, TEST-002, TEST-005,
  TEST-006 GREEN); (4) CLI fixtures GREEN (TEST-003); (5) survival re-run of
  the full legacy suite (TEST-004) → docs/ai/tdd/dispatch-4a-fail-precedence-green.log;
  (6) index regen + check-state; (7) AC table reconciliation; (8) STATE via CLI.
- Edge cases (from D3/D4): done + fail + terminal spec status → rule 6 Planning
  (not a 4a retarget); work_item == null + fail → needs_llm
  focus_ref_not_in_active_work_items; done + fail + last_run_role Remediation →
  needs_llm possible_missing_remediation_reset (rule 10/12 forensic, unchanged);
  no fail → 4a exactly as today; `retarget` is null on every non-4a verdict as
  before.

## Seam analysis
- Seam S1 — the rule-4a predicate is shared with SPEC-0042's 4a arm and its
  test suite (test_006..test_012) and with SPEC-0041's lane logic / ceremony
  suite. Crossing test: TEST-004 re-runs the FULL legacy dispatch suite
  (test_001..test_012, which internally re-runs the real ceremony-suite lane
  stanzas via test_011) post-change and asserts exit 0 with zero assertion
  edits — proving the new conjunct did not perturb any existing arm.
- Seam S2 — the guard reads the SAME `s.validation.status` / `s.review.status`
  snapshot fields that rules 10/11/12/13/14 read. Crossing test: TEST-003
  drives the real CLI end-to-end (buildSnapshot → decide) on fixture repos with
  a real `last_validation`/`code_review` STATE block and asserts the Remediation
  routing, proving the guard and the downstream rules agree on the field values.
- No new seam is introduced (no new probe, no new output field, no STATE
  write). Residual risk: none beyond SPEC-0042's already-recorded residuals.

## Test Plan

All rows live in tests/skills/test-aai-orchestration-dispatch.sh (reserved for
this dispatch scope by SPEC-0041 D5); bash-3.2 compatible; scratch temp-dir
fixture repos only. New functions test_013..test_018; test_001..test_012 are
never edited.

| Test ID  | Spec-AC    | Type        | File path (expected)                            | Description                                                                                     | Status  |
|----------|------------|-------------|--------------------------------------------------|--------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-orchestration-dispatch.sh | decide(): done+flushed + validation fail + one open intake + eligible shape (spec implementing, phase validation) → verdict dispatch, rule 10, role Remediation, retarget null; asserts rule !== '4a' | green |
| TEST-002 | Spec-AC-02 | unit        | tests/skills/test-aai-orchestration-dispatch.sh | decide(): done+flushed + validation not_run + code_review fail + phase code_review → verdict dispatch, rule 12, role Remediation, retarget null; asserts rule !== '4a' | green |
| TEST-003 | Spec-AC-01, Spec-AC-02 | integration | tests/skills/test-aai-orchestration-dispatch.sh | CLI end-to-end on real fixture repos (STATE + frozen implementing spec + flushed METRICS ref + one open intake doc): validation-fail fixture → exit 0 rule 10; review-fail fixture → exit 0 rule 12; retarget null in both | green |
| TEST-004 | Spec-AC-03 | integration | tests/skills/test-aai-orchestration-dispatch.sh | Survival + negative control: no-fail done+flushed+one intake → 4a retarget unchanged; the full legacy suite test_001..test_012 runs to exit 0 with zero assertion edits | green |
| TEST-005 | Spec-AC-05 | unit        | tests/skills/test-aai-orchestration-dispatch.sh | Fail-closed invariant (parametric): done+validation fail, done+review fail, work_item null + fail, both verdicts fail — NONE yields a rule-4a dispatch/non-null retarget; null+fail → needs_llm focus_ref_not_in_active_work_items | green |
| TEST-006 | Spec-AC-04 | unit        | tests/skills/test-aai-orchestration-dispatch.sh | decide() purity on a fail-verdict snapshot (double-decide + input-freeze) + grep the RULES 4a `when` doc string documents the abstention guard (mentions fail + Remediation) | green |

Notes:
- RED-proof: TEST-001/TEST-002/TEST-003/TEST-005 and TEST-006's doc-string half
  must be observed FAILING on the pre-change tree
  (docs/ai/tdd/dispatch-4a-fail-precedence-red.log). TEST-004 is a survival
  invariant (green pre-change by construction; non-vacuous — it re-runs the
  real legacy suite over the changed tree post-change).
- Known environmental exceptions (verify via stash/main comparison before
  chasing): tests/skills/test-aai-worktree.sh (LEARNED 2026-07-15) and the
  prompt-diet byte-budget stanza (DEBT-0002 / SPEC-0048 lineage) are pre-existing
  and unrelated to this scope.

## Verification
- `bash tests/skills/test-aai-orchestration-dispatch.sh` → exit 0, including
  the new TEST-001..TEST-006 stanzas (test_013..test_018) AND the pre-existing
  test_001..test_012 unchanged (intake AC-001..AC-004).
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` → exit 0.
- `node .aai/scripts/check-state.mjs` → OK.
- `node .aai/scripts/generate-docs-index.mjs && git diff --exit-code -I '^Generated:' -- docs/INDEX.md`
  → exit 0 (idempotent).
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: dispatch-4a-fail-verdict-precedence
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path (docs/ai/tdd/dispatch-4a-fail-precedence-red.log,
  docs/ai/tdd/dispatch-4a-fail-precedence-green.log)
- commit SHA or diff range when available
