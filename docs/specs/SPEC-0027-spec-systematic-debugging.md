---
id: spec-systematic-debugging
type: spec
number: 27
status: draft
links:
  change: systematic-debugging
  research: RES-0001
  pr: []
  commits: []
---

# SPEC — Systematic-Debugging Gate Skill for Remediation

SPEC-FROZEN: true

## Links
- Change: systematic-debugging
  (docs/issues/CHANGE-0018-systematic-debugging.md, AC-001..AC-003)
- Research: RES-0001 P2 recommendation 7b — Superpowers systematic-debugging
  pattern (4-phase root-cause-first protocol, NO FIXES WITHOUT ROOT CAUSE) —
  docs/specs/RES-0001-aai-competitive-gap-and-model-efficiency.md
- Sibling gate: docs/specs/SPEC-0025-spec-verification-before-completion.md
  (.aai/SKILL_VERIFY.prompt.md owns the completion side; this spec owns the
  debugging side and cross-links it)
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (SPEC-FROZEN: true)
- implementing: work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Implementation strategy
- Strategy: loop
- Rationale: prompt-text and wrapper work with deterministic grep-based
  verification, same class as SPEC-0025. Every gating test is a grep/wc
  stanza trivially RED-provable by one pre-change run of the new suite (the
  target file does not exist yet, wiring markers absent). RED-GREEN-REFACTOR
  per test adds no signal over one focused pass plus a recorded RED run.
- RED-proof obligation: before any edit, run
  `bash tests/skills/test-aai-debug-gate.sh` on the pre-change tree and save
  the failing output to `docs/ai/tdd/debug-gate-red.log` (expected:
  TEST-001..TEST-006 FAIL; TEST-007 and TEST-008 pass pre-change by
  construction — they guard invariants that must SURVIVE the change, and are
  non-vacuous because TEST-007 re-runs the prompt-diet suite after the corpus
  grows and TEST-008 re-audits the repo after new docs land).

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: additive new prompt + wrappers + one new suite; the only
  edit to an existing protected prompt is a 2-line additive insertion in
  REMEDIATION. Isolation is useful, not safety-critical.
- User decision: worktree (already executing in
  /Users/ales/Projects/aai-feat-sysdebug, branch feat/systematic-debugging)
- Base ref: main (merge-base 19508a5 at freeze time)
- Inline review scope (explicit paths):
  - .aai/SKILL_DEBUG.prompt.md (new)
  - .aai/REMEDIATION.prompt.md (2-line additive wiring)
  - .claude/skills/aai-debug/SKILL.md (new)
  - .codex/skills/aai-debug/SKILL.md (new)
  - .gemini/skills/aai-debug/SKILL.md (new)
  - tests/skills/test-aai-debug-gate.sh (new)
  - SKILLS.md, .aai/AGENTS.md (one catalog row/line each)
  - docs/INDEX.md (regenerated)

## Design decisions

### D1 — New gate prompt `.aai/SKILL_DEBUG.prompt.md` (≤120 lines)
Compact, self-contained; matches SKILL_VERIFY's tone/structure. Required:
1. Iron Law: NO FIXES WITHOUT ROOT CAUSE.
2. Protocol, exactly this chain and order:
   READ → REPRODUCE → ISOLATE → FIX-AT-CAUSE
   - READ the full error output (no tail-only reading).
   - REPRODUCE minimally, before any edit.
   - ISOLATE via recent changes (git log/diff), component-boundary
     instrumentation, and backward data-flow tracing.
   - FIX-AT-CAUSE, never at the symptom; the fix must make the phase-2
     reproduction pass.
3. Rationalization table with ≥5 data rows ("just add a null check", "the
   test is flaky", "works on my run", ...), including the motivating
   example: the fieldSpan finding (ISSUE-0007/SPEC-0022) where the surface
   append-indent fix nearly masked the deeper span bug.
4. Cross-link to `.aai/SKILL_VERIFY.prompt.md` for the completion side (the
   fixed state still needs the IDENTIFY→RUN→READ→VERIFY→CLAIM gate).

### D2 — REMEDIATION wiring (≤2 lines, placed BEFORE the fix step)
Two additive lines at the end of PROCESS step 2 (categorize), physically
before step 3 "Apply fixes in order". Purely additive — no existing line is
changed or removed, so no obligation is lost (verified by TEST-005 asserting
the surviving step-3/4/6 markers). "≤2 lines" is measured as: number of
lines containing the literal `SKILL_DEBUG` in REMEDIATION is ≥1 and ≤2.
Byte budget: prompt-diet floor is net reduction ≥28,672 bytes vs baseline
357,457; pre-change measured reduction is 47,668 → headroom 18,996 bytes.
SKILL_DEBUG at ≤120 lines is ≤~5 KB; the floor holds with ≥13 KB margin
(TEST-007 re-asserts via the prompt-diet suite itself).

### D3 — Wrappers in the three agent trees
New `aai-debug` wrapper SKILL.md in `.claude/skills/`, `.codex/skills/`,
`.gemini/skills/`, mirroring the aai-verify wrapper style (frontmatter
`name` + `description`; body: read `.aai/SKILL_DEBUG.prompt.md` and follow
exactly; not-found fallback line). No `model:` pin. Catalog wiring: one row
in SKILLS.md Quick Reference; one `Follow .aai/SKILL_DEBUG.prompt.md` line
in .aai/AGENTS.md (neither counts toward the prompt-diet corpus).

### D4 — Grep test suite `tests/skills/test-aai-debug-gate.sh`
New bash-3.2-compatible suite (exit 0/1/42), same shape as
tests/skills/test-aai-verify-gate.sh. Shared-baseline caveat: the prompt-diet
byte-floor constants live in tests/skills/test-aai-prompt-diet.sh (TEST-010)
and are NOT duplicated here — this suite asserts the floor by running that
suite (TEST-007) and keeps its own stanzas to existence/content greps.

## Acceptance Criteria Mapping
- Maps to: CHANGE AC-001
  - Spec-AC-01: `.aai/SKILL_DEBUG.prompt.md` exists, ≤120 lines, contains the
    literal ordered chain `READ → REPRODUCE → ISOLATE → FIX-AT-CAUSE`, a
    rationalization table with ≥5 data rows, and a cross-link to
    `.aai/SKILL_VERIFY.prompt.md`.
  - Verification: TEST-001..TEST-004 stanzas in
    tests/skills/test-aai-debug-gate.sh; expected exit 0 with PASS lines.
- Maps to: CHANGE AC-002
  - Spec-AC-02: REMEDIATION references `SKILL_DEBUG` on ≥1 and ≤2 lines,
    positioned before its "Apply fixes in order" step; existing obligations
    survive (fix-order list, reset-block rules, no-loop stop rule).
  - Verification: TEST-005 stanza.
- Maps to: CHANGE AC-003
  - Spec-AC-03: `aai-debug/SKILL.md` exists in all three agent trees with
    `name: aai-debug` + pointer to `.aai/SKILL_DEBUG.prompt.md`; prompt-diet
    suite green (floor holds); repo-wide strict docs audit exits 0; full
    tests/skills sweep green (validation-owned).
  - Verification: TEST-006..TEST-008 stanzas; full suite run at validation.

## Acceptance Criteria Status

| Spec-AC    | Description                                           | Status  | Evidence | Review-By | Notes |
|------------|-------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Gate prompt ≤120 lines with chain + table + verify link | done | TEST-001..004 green; docs/ai/tdd/debug-gate-green.log | — | .aai/SKILL_DEBUG.prompt.md, 68 lines, 6 table rows |
| Spec-AC-02 | ≤2-line REMEDIATION wiring before fix step, no loss   | done | TEST-005 green; docs/ai/tdd/debug-gate-green.log | — | 2 additive lines at end of PROCESS step 2 (1 line contains SKILL_DEBUG); fix-order, reset-block x2, no-loop markers asserted intact |
| Spec-AC-03 | Wrappers x3; diet floor holds; strict audit CLEAN     | done | TEST-006..008 green; docs/ai/tdd/debug-gate-green.log; docs-audit --check --strict --no-event exit 0 (62 docs, CLEAN); 8-suite sweep green (hygiene, prompt-diet, verify-gate, state, dispatch, metrics, docs-audit, doc-numbering) | — | wrappers in .claude/.codex/.gemini/skills/aai-debug/SKILL.md |

## Implementation plan
- Components affected: prompt layer (.aai/SKILL_DEBUG.prompt.md new,
  .aai/REMEDIATION.prompt.md +2 lines), wrapper trees (x3, one new dir each),
  test layer (one new suite), catalogs (SKILLS.md, .aai/AGENTS.md),
  docs/INDEX.md regeneration.
- Order: (1) RED run of the new suite on the pre-change tree → save log;
  (2) write SKILL_DEBUG; (3) wire REMEDIATION; (4) wrappers + catalogs;
  (5) suite green; (6) sweep (hygiene, prompt-diet, verify-gate, state,
  dispatch, metrics, docs-audit, doc-numbering); (7) strict audit; (8) index
  regen (idempotent); (9) AC table reconciliation.
- Edge cases: SKILL_DEBUG writes no STATE, so it needs no state.mjs fallback
  text (keeps prompt-diet TEST-007 trivially safe); REMEDIATION wiring is
  additive-only to avoid renumbering its PROCESS steps (step numbers are
  referenced internally: "recorded in step 1").
- Seam analysis:
  - Seam S1 — the `.aai/*.prompt.md` byte corpus is shared with prompt-diet
    TEST-010. Crossing test: TEST-007 runs the real prompt-diet suite
    post-change (no constant duplication).
  - Seam S2 — wrapper trees are consumed wholesale by aai-sync/aai-update
    (directory copy, shape-agnostic). No crossing test needed; residual risk
    none.
  - Seam S3 — REMEDIATION's fix flow is consumed by every remediation run;
    the wiring must add the gate without deleting an obligation. Crossing
    test: TEST-005 asserts the new pointer AND survival of the step-3
    fix-order marker, both reset-block markers, and the step-6 no-loop rule.
  - Seam S4 — docs/INDEX.md and strict audit consume the new spec/change
    docs. Crossing test: TEST-008 (repo-wide strict audit) + index regen.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                 | Description                                                                  | Status  |
|----------|------------|-------------|--------------------------------------|------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-debug-gate.sh | SKILL_DEBUG.prompt.md exists and `wc -l` ≤ 120                                | green |
| TEST-002 | Spec-AC-01 | unit        | tests/skills/test-aai-debug-gate.sh | Protocol chain literal `READ → REPRODUCE → ISOLATE → FIX-AT-CAUSE` present    | green |
| TEST-003 | Spec-AC-01 | unit        | tests/skills/test-aai-debug-gate.sh | Rationalization table has ≥5 data rows (pipe-rows minus header/separator)     | green |
| TEST-004 | Spec-AC-01 | unit        | tests/skills/test-aai-debug-gate.sh | Cross-link to .aai/SKILL_VERIFY.prompt.md present                             | green |
| TEST-005 | Spec-AC-02 | integration | tests/skills/test-aai-debug-gate.sh | REMEDIATION has 1-2 `SKILL_DEBUG` lines, before "Apply fixes in order"; obligation markers survive (S3) | green |
| TEST-006 | Spec-AC-03 | unit        | tests/skills/test-aai-debug-gate.sh | `aai-debug/SKILL.md` in .claude/.codex/.gemini trees, each with `name: aai-debug` + pointer | green |
| TEST-007 | Spec-AC-03 | integration | tests/skills/test-aai-debug-gate.sh | Prompt-diet floor holds post-change: `bash tests/skills/test-aai-prompt-diet.sh` exits 0 (S1) | green |
| TEST-008 | Spec-AC-03 | integration | tests/skills/test-aai-debug-gate.sh | `node .aai/scripts/docs-audit.mjs --check --strict --no-event` exits 0 (S4)   | green |

Notes:
- "Suites green" (CHANGE AC-003) is owned by the Validation full tests/skills
  run. Known environmental exceptions per LEARNED 2026-07-15:
  tests/skills/test-aai-worktree.sh fails deterministically on this machine
  pre-existing on clean main — verify via main comparison, do not chase.
- RED-proof: TEST-001..006 must be observed FAILING on the pre-change tree
  (log: docs/ai/tdd/debug-gate-red.log). TEST-007/008 are survival-invariant
  tests (see Implementation strategy).

## Verification
- `bash tests/skills/test-aai-debug-gate.sh` → exit 0, all 8 stanzas PASS.
- `bash tests/skills/test-aai-verify-gate.sh` → exit 0 (sibling gate intact).
- Full suite via `.aai/scripts/aai-run-tests.sh` over tests/skills (runner
  conventions) → green modulo the recorded environmental failures.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` → exit 0.
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal with evidence.

## Evidence contract
For each implementation, validation, and code review artifact, record:
- ref_id: systematic-debugging
- Spec-AC and TEST-xxx links where applicable
- command or review scope, exit code or review verdict
- evidence path (docs/ai/tdd/debug-gate-red.log for RED; suite output logs)
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow.
