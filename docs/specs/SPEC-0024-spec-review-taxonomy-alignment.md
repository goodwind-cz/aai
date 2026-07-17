---
id: spec-review-taxonomy-alignment
type: spec
number: 24
status: done
links:
  change: review-taxonomy-alignment
  requirement: null
  rfc: null
  pr:
    - 66
  commits:
    - 0cadd9f
---

# SPEC — Align Orchestration-Facing Surfaces With the Dual-Verdict Review Taxonomy (CHANGE-0014)

SPEC-FROZEN: true

## Links
- Change (WHAT/WHY): docs/issues/CHANGE-0014-review-taxonomy-alignment.md
- Upstream taxonomy owner: docs/specs/SPEC-0021-spec-single-dual-verdict-review.md
  (dual-verdict report schema lives in .aai/SKILL_CODE_REVIEW.prompt.md)
- Originating finding: docs/ai/reviews/review-dual-verdict-20260715T234706Z.md
  (code_quality NB-1)
- Test suite extended: tests/skills/test-aai-hygiene-pack.sh
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec being written / frozen for implementation
- implementing: spec frozen, work delivered in the worktree, awaiting
  independent validation + merge (this doc)
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Problem

SPEC-0021 replaced the two-stage (Stage 1 spec compliance / Stage 2 code
quality) + ERROR/WARNING review taxonomy with a single dual-verdict pass:
`spec_compliance` (AC-walk), `code_quality` (BLOCKING/NON-BLOCKING findings
with file:line + failure_scenario), and a mandatory `cannot_verify` list.
Orchestration-facing surfaces still speak the old taxonomy, so a review FAIL
dispatches Remediation with failure buckets that can never match a new-format
report (mis-bucketing / spurious HITL risk). Routing survives (dispatch keys
on `code_review.status`), so this is alignment, not breakage.

## Occurrence inventory (ground truth, verified by grep on worktree @ 833ef7c)

Patterns swept: `Stage 1`, `Stage 2`, `stage-1`, `stage-2`, `two-stage`
(case-insensitive), `ERROR finding`, `WARNING finding`, `ERROR/WARNING`,
`ERROR blocks`, `WARNING requires` — repo-wide, then filtered to
orchestration-facing surfaces (immutable history under docs/specs, docs/ai,
docs/issues, docs/_archive and CHANGELOG.md excluded by policy).

| # | File:line | Old-taxonomy text |
|---|-----------|-------------------|
| 1 | .aai/REMEDIATION.prompt.md:31 | `Code Review Stage 1 spec non-compliance` |
| 2 | .aai/REMEDIATION.prompt.md:32 | `Code Review Stage 2 ERROR findings` |
| 3 | .aai/REMEDIATION.prompt.md:37 | `Code quality/security fixes from Code Review ERROR findings` |
| 4 | .aai/SKILL_TDD.prompt.md:325 | `ERROR findings block merge/PR readiness.` |
| 5 | .aai/SKILL_TDD.prompt.md:326 | `WARNING findings require a recorded decision or follow-up task.` |
| 6 | .aai/workflow/WORKFLOW.md:63 | stop condition `Code Review ERROR findings` |
| 7 | .aai/ORCHESTRATION_HITL.prompt.md:22 | trigger 9 `Code Review ERROR findings need a fix/waiver decision` |
| 8 | .aai/scripts/orchestration-dispatch.mjs:166 | `stop_condition: 'review verdict recorded (ERROR findings block readiness)'` |
| 9 | .aai/system/AUTONOMOUS_LOOP.md:22 | `two-stage review (spec compliance, then code quality)` |
| 10 | .aai/system/SUPERPOWERS_INTEGRATION.md:64 | heading `### 4. Two-Stage Code Review` |
| 11 | .aai/system/SUPERPOWERS_INTEGRATION.md:67-68 | `Stage 1: Spec compliance (blocking)` / `Stage 2: Code quality (non-blocking warnings)` |
| 12 | .aai/system/SUPERPOWERS_INTEGRATION.md:71 | `/aai-code-review with two mandatory stages` |
| 13 | .aai/system/SUPERPOWERS_INTEGRATION.md:73-74 | `ERROR findings block merge/PR readiness` / `WARNING findings require a recorded decision, remediation, or follow-up item` |
| 14 | .aai/system/SUPERPOWERS_INTEGRATION.md:124-125 | `→ Stage 1: Spec compliance` / `→ Stage 2: Code quality` |
| 15 | .aai/system/SUPERPOWERS_INTEGRATION.md:242-243 | `ERROR blocks merge/PR readiness, WARNING requires a recorded decision/remediation/follow-up` |

Deltas vs the dogfood NB-1 list (review-dual-verdict-20260715T234706Z.md):
- EXTRA #10 (SUPERPOWERS heading `Two-Stage Code Review`, line 64) and
  EXTRA #12 (`two mandatory stages`, line 71) — found by the repo-wide sweep.
- Dogfood cited SUPERPOWERS_INTEGRATION.md:238; actual occurrence sits at
  242-243 (drift). All other dogfood entries confirmed at the cited files.
- Deliberately NOT in scope: .aai/SKILL_CODE_REVIEW.prompt.md:4,8
  ("replaces the former two-stage flow" / "two-stage history") — the review
  prompt's own historical note; CHANGE-0014 scopes the review prompt out.
  .aai/workflow/WORKFLOW.md:64-65 "free-text WARNINGs" refers to the H6
  disposition vocabulary (NON-BLOCKING findings are "the WARNINGs of the H6
  policy" per the schema) and is not a review-report taxonomy reference.

## Implementation strategy
- Strategy: loop
- Rationale: pure wording alignment across prompts/docs plus one display
  string in a script; behavior unchanged. Evidence is grep-RED -> GREEN via a
  new hygiene stanza (the SPEC-0013 grep-wiring pattern), not unit TDD.

## Isolation and review
- Worktree recommendation: recommended
- User decision: worktree (provisioned by the operator)
- Base ref: main @ 833ef7c
- Worktree branch/path: feat/change-0014-taxonomy at
  /Users/ales/Projects/aai-feat-taxonomy
- Inline review scope: n/a (worktree chosen)

## Design decisions (resolved — do not reopen during implementation)

### D1 — Remediation buckets mirror the report schema field names
REMEDIATION.prompt.md step-2 categories name the dual-verdict report fields
exactly as .aai/SKILL_CODE_REVIEW.prompt.md's YAML schema emits them:
`spec_compliance` verdict fail (non-compliant `ac_walk` rows, each with a
per-AC citation), `code_quality` verdict fail (`findings` ranked
BLOCKING/NON-BLOCKING, each with file:line + `failure_scenario`), and
`cannot_verify` named as an evidence-gap list that is NOT a failure bucket.
Step-3(d) fixes key on BLOCKING findings; NON-BLOCKING carries the H6
disposition duty.

### D2 — orchestration-dispatch.mjs:166 is display text, not logic
The `stop_condition` string is part of the Code Review role template handed
to the dispatched agent; no code branches on its content (the dispatch suite
asserts only that `stop_condition` is a non-empty string; routing keys on
`code_review.status`). Treatment: reword the string in place — no behavior
change, dispatch suite must stay green unmodified.

### D3 — Superpowers-concept lines are reworded, not deleted
SUPERPOWERS_INTEGRATION.md contrasts an external tool's concept with AAI's
implementation. The concept prose keeps its meaning ("separate compliance and
quality passes with severity levels") but stops using the retired AAI labels,
so a repo-wide negative grep stays clean without whitelisting a live doc.

### D4 — Negative-grep hygiene stanza (test_043), whitelist = history + self
New test_043 in tests/skills/test-aai-hygiene-pack.sh sweeps .aai, .claude,
.codex, .gemini for the old-taxonomy patterns and fails on ANY hit, excluding
only .aai/SKILL_CODE_REVIEW.prompt.md (historical self-reference, out of
scope per CHANGE-0014). docs/** (immutable history incl. this spec's
inventory table) and tests/** (the patterns live in the test itself) are
outside the swept trees by construction. Positive anchors assert the new
vocabulary landed (non-vacuous): REMEDIATION carries the schema field names;
dispatch/WORKFLOW/HITL/SKILL_TDD say BLOCKING; AUTONOMOUS_LOOP and
SUPERPOWERS say dual-verdict.

## Acceptance Criteria Mapping
- Maps to: CHANGE-0014 AC-001
  - Spec-AC-01: repo-wide grep for the old taxonomy (patterns above) over
    .aai/.claude/.codex/.gemini returns zero hits outside the whitelisted
    historical self-reference; all 15 inventory occurrences reworded to
    spec_compliance/code_quality + BLOCKING/NON-BLOCKING (+ cannot_verify).
  - Verification: tests/skills/test-aai-hygiene-pack.sh test_043 (grep-RED
    before rewording, GREEN after).
- Maps to: CHANGE-0014 AC-002
  - Spec-AC-02: REMEDIATION.prompt.md finding-intake wording names the
    dual-verdict report schema fields (spec_compliance, code_quality,
    ac_walk, BLOCKING/NON-BLOCKING findings, failure_scenario,
    cannot_verify) so a review-FAIL dispatch buckets correctly (D1).
  - Verification: test_043 positive anchors on REMEDIATION.prompt.md.
- Maps to: CHANGE-0014 AC-003
  - Spec-AC-03: existing suites green — hygiene pack (incl. new stanza),
    orchestration-dispatch (its file is touched, D2), state, metrics,
    docs-audit, doc-numbering, prompt-diet; repo audit strict CLEAN; index
    idempotent; check-state OK.
  - Verification: full sweep logs (docs/ai/tdd/, this worktree).

## Acceptance Criteria Status

| Spec-AC    | Description                                          | Status | Evidence | Review-By | Notes |
|------------|------------------------------------------------------|--------|----------|-----------|-------|
| Spec-AC-01 | old taxonomy absent from orchestration-facing trees  | done   | docs/ai/tdd/red-change-0014-taxonomy.log -> docs/ai/tdd/green-change-0014-taxonomy.log | — | RED: test_043 fails naming all inventory hits; GREEN: zero hits + anchors present |
| Spec-AC-02 | REMEDIATION buckets match report schema field names  | done   | docs/ai/tdd/red-change-0014-taxonomy.log -> docs/ai/tdd/green-change-0014-taxonomy.log | — | RED: schema anchors absent; GREEN: spec_compliance/code_quality/ac_walk/BLOCKING/cannot_verify present |
| Spec-AC-03 | full suite sweep green, strict audit CLEAN           | done   | docs/ai/tdd/sweep-change-0014-taxonomy.log | — | 7 suites exit 0; audit CLEAN; index idempotent; check-state OK |

Status values: planned | implementing | done | deferred | blocked | rejected
- planned: AC defined, no implementation started
- implementing: work in flight; not allowed at PASS claim time
- done: implementation complete; requires non-empty Evidence (commit SHA or RUN_ID)
- deferred: explicitly postponed; requires Review-By (minimum +14 days) + Notes
- blocked: cannot proceed; requires Review-By + Notes naming blocker
- rejected: will not be implemented; requires Notes with rationale (terminal)

Gate behavior (enforced by .aai/VALIDATION.prompt.md when this column is present):
- Any planned/implementing AC blocks PASS
- Any done AC with empty Evidence blocks PASS
- Any deferred/blocked AC with Review-By in the past blocks any PASS until re-decided
- Review-By must be at least 14 days in the future when set

## Implementation plan
- .aai/REMEDIATION.prompt.md — step-2 failure buckets + step-3(d) reworded to
  the report schema field names (D1).
- .aai/SKILL_TDD.prompt.md — code-review-gate bullets: BLOCKING blocks
  readiness (code_quality verdict fail); NON-BLOCKING carries H6 disposition.
- .aai/workflow/WORKFLOW.md — stop condition reworded to BLOCKING findings.
- .aai/ORCHESTRATION_HITL.prompt.md — trigger 9 reworded to BLOCKING findings.
- .aai/scripts/orchestration-dispatch.mjs — stop_condition display string
  reworded (D2); no logic change.
- .aai/system/AUTONOMOUS_LOOP.md — Code reviewer bullet: dual-verdict pass.
- .aai/system/SUPERPOWERS_INTEGRATION.md — section 4 heading + bullets,
  workflow example step 6, "Current behavior" line (D3).
- tests/skills/test-aai-hygiene-pack.sh — new test_043 registered in main()
  (D4), grep-RED first.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected)                                | Description                                                        | Status |
|----------|------------|------|-----------------------------------------------------|--------------------------------------------------------------------|--------|
| TEST-001 | Spec-AC-01 | unit | tests/skills/test-aai-hygiene-pack.sh (test_043)    | negative grep: old taxonomy absent from .aai/.claude/.codex/.gemini (whitelist: SKILL_CODE_REVIEW historical note) | green |
| TEST-002 | Spec-AC-02 | unit | tests/skills/test-aai-hygiene-pack.sh (test_043)    | positive anchors: REMEDIATION carries spec_compliance/code_quality/ac_walk/BLOCKING/NON-BLOCKING/failure_scenario/cannot_verify | green |
| TEST-003 | Spec-AC-03 | int  | full sweep (hygiene, dispatch, state, metrics, docs-audit, doc-numbering, prompt-diet) | all suites exit 0; strict audit CLEAN; index idempotent; check-state OK | green |

Test status values: pending -> red -> green.

## Verification
- bash tests/skills/test-aai-hygiene-pack.sh — exit 0 (incl. test_043)
- bash tests/skills/test-aai-orchestration-dispatch.sh — exit 0 (touched file)
- bash tests/skills/test-aai-state.sh, test-aai-metrics.sh,
  test-aai-docs-audit.sh, test-aai-doc-numbering.sh, test-aai-prompt-diet.sh
  — exit 0
- node .aai/scripts/docs-audit.mjs --check --strict --no-event — Verdict: CLEAN
- node .aai/scripts/generate-docs-index.mjs — idempotent (byte-identical
  modulo the Generated stamp)
- node .aai/scripts/check-state.mjs — OK
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal.

## Evidence contract
Per artifact record: ref_id (CHANGE-0014), Spec-AC/TEST links, command, exit
code, evidence path (docs/ai/tdd/*-change-0014-taxonomy.log), commit SHA or
diff range when available.

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow.
