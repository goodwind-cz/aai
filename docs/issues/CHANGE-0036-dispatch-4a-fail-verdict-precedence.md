---
id: dispatch-4a-fail-verdict-precedence
type: change
number: 36
status: draft
links:
  pr: []
  commits: []
---

# Change — Rule 4a must not retarget away from an unaddressed FAIL verdict

## Summary
- Guard the deterministic dispatcher's rule 4a (new-intake retarget) so it does
  NOT fire when the completed focus still carries a recorded FAIL verdict
  (`last_validation.status == fail` or `code_review.status == fail`). Such a
  focus must fall through to rules 10/12 (Remediation) first — a buried failure
  is worse than a delayed retarget.

## Motivation / Business Value
- CHANGE-0031/SPEC-0042 review (review-20260717T125756Z, NB-1) found: rule 4a is
  evaluated before rules 10/12, and fires on `(work_item done/absent) AND
  flushed` with no verdict check. A done+flushed focus that still records a
  `fail` verdict is therefore RETARGETED to a new intake, silently burying the
  unremediated failure. This contradicts SPEC-0042 D5's stated intent that fail
  verdicts fire regardless of item status. Low reachability today (flush H5
  reset usually clears verdicts), but the precedence inversion is a real
  correctness gap in the governance dispatch core.

## Scope
- In scope: the rule-4a guard in `.aai/scripts/lib/` decide() /
  `.aai/scripts/orchestration-dispatch.mjs` (~line 314); its test suite
  `tests/skills/test-aai-orchestration-dispatch.sh`; the rule-4a `when` doc
  string; SPEC-0042 D1/D5 reconciliation note (via this change's spec).
- Out of scope: any other rule ordering; the retarget payload shape; the
  open-intake scan.

## Affected Area
- Deterministic orchestration dispatch (`decide()`), rule 4a arm.

## Desired Behavior (To-Be)
- Rule 4a's firing condition gains a clause: it fires only when neither
  `last_validation.status` nor `code_review.status` is `fail`. When a fail
  verdict is present on the completed+flushed focus, decide() falls through so
  rule 10 (validation fail → Remediation) or rule 12 (code_review fail →
  Remediation) dispatches, exactly as it would for a non-terminal item.
- All existing rule-4a behavior (retarget on single open intake, no_action on
  zero, needs_llm on 2+/unmappable/scan-failure) is unchanged when no fail
  verdict is present.

## Acceptance Criteria
- AC-001: a done+flushed focus with `last_validation.status == fail` (one open
  intake present) dispatches Remediation (rule 10), NOT a 4a retarget.
- AC-002: a done+flushed focus with `code_review.status == fail` dispatches
  Remediation (rule 12), NOT a 4a retarget.
- AC-003: a done+flushed focus with NO fail verdict retains today's exact 4a
  behavior for all candidate counts (retarget / no_action / needs_llm) — the
  existing dispatch suite stays green with zero assertion edits.
- AC-004: decide() stays pure (no clock/fs/mutation); the rule-4a `when` doc
  string documents the new guard.

## Verification
- New stanzas in `tests/skills/test-aai-orchestration-dispatch.sh`: the two
  fail-verdict fixtures (validation, review) each assert Remediation not 4a; a
  negative control (no fail → 4a unchanged). Full dispatch suite + ceremony
  suite exit 0.

## Constraints / Risks
- Deterministic core — the guard must be fail-closed and add no rule reordering
  (only tighten 4a's predicate). Verify rules 10/12 genuinely fire for a
  done-status item once 4a abstains (they read verdict status, not work-item
  status, so they should).

## Notes
- Source: docs/ai/reviews/review-20260717T125756Z.md NB-1; decisions.jsonl
  disposition (CHANGE-0031, 2026-07-17). Reconciles SPEC-0042 D1 (4a) with D5
  (fail verdicts fire regardless of status).
