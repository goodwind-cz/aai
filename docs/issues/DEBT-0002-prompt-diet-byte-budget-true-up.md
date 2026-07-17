---
id: prompt-diet-byte-budget-true-up
type: techdebt
number: 2
status: done
links:
  pr: []
  commits: []
---

# Tech Debt: prompt-diet TEST-010 byte-budget floor breached on clean main

## Debt Summary
- `tests/skills/test-aai-prompt-diet.sh` TEST-010 (prompt-corpus byte-budget
  floor, net reduction >= 28672 B) fails on clean main: measured 28187 B at
  merge commit c144736 (~485 B short), independent of any in-flight change.
  SPEC-0041's required lane prompt text widened the shortfall to ~1770 B.

## Root Cause
- The budget floor was calibrated for the SPEC-0017 prompt-diet corpus and
  never re-baselined as later canon-mandated prompt additions (dual-verdict
  review taxonomy, VALIDATION 8a exception, CEREMONY LANE block) legitimately
  grew the corpus. Each addition was individually justified; the fixed floor
  does not model justified growth.

## Current Cost / Risk
- Every suite whose seam re-runs prompt-diet (e.g. test-aai-ceremony-levels.sh
  test_010) exits 1 on a clean tree — masking real regressions and forcing
  identity-based tolerances (ceremony suite test_017) that are fragile.

## Target State
- TEST-010 green on clean main with a re-baselined budget (or a
  growth-aware model, e.g. per-file ceilings with a justified-additions
  ledger); identity-based tolerance in test_017 removed.

## Scope
- In scope: tests/skills/test-aai-prompt-diet.sh TEST-010 baseline,
  ceremony suite test_017 tolerance removal, LEARNED.md entry update.
- Out of scope: any prompt-content edits (no re-dieting in this item).

## Plan / Migration
- Measure current corpus, set the new floor with headroom rationale recorded
  in the test file comment; drop test_017's tolerance; run both suites.

## Verification
- `bash tests/skills/test-aai-prompt-diet.sh` -> exit 0 on clean tree.
- `bash tests/skills/test-aai-ceremony-levels.sh` -> exit 0 with the
  tolerance removed.

## Constraints / Risks
- Do not silently absorb future unjustified prompt growth: the re-baseline
  must document what grew and why (SPEC-0017 discipline).

## Notes (W2 fold-in, review-20260717T134629Z)
- Also true up the TEST-011 40-line ceiling headroom for deterministic-tick
  wrapper prompts: .aai/ORCHESTRATION.prompt.md sits at exactly 40/40 lines
  (zero headroom; a one-line growth broke it live on 2026-07-17 — validation
  FAIL 133218Z). Re-baseline alongside the byte floor.

## Notes
- Found during CHANGE-0030/SPEC-0041 TDD (2026-07-17); verified pre-existing
  via clean-main worktree A/B by both Validation and Code Review. See
  LEARNED.md 2026-07-17 entry and review-20260717T121031Z.md NB-2.

## Resolution (2026-07-17, DEBT-0002/SPEC-0048)
- `tests/skills/test-aai-prompt-diet.sh` TEST-010 re-baselined via a
  `JUSTIFIED_GROWTH_BYTES=6144` ledger credit (inline itemized comment;
  `BASELINE_PROMPT_BYTES`/`REQUIRED_REDUCTION_BYTES` unchanged) plus a new
  `HEADROOM_CAP=2048` anti-bloat guard asserting `0 <= headroom <=
  HEADROOM_CAP` (measured: reduction 29694 B, headroom 1022 B) — proven to
  bite RED with a deliberately padded credit before going GREEN.
- TEST-011 thin-wrapper line ceiling raised 40 -> 45 with rationale comment;
  a synthetic 46-line fixture proof confirms the ceiling still rejects
  over-limit wrappers.
- `test-aai-ceremony-levels.sh` `test_017`'s pre-existing-shortfall tolerance
  removed -> plain exit-0 assertion; full suite green.
- Evidence: docs/ai/tdd/red-20260717T185005Z-test010-011.log,
  docs/ai/tdd/red-20260717T185240Z-test002-headroomcap.log,
  docs/ai/tdd/green-20260717T185321Z-test001-002-003.log,
  docs/ai/tdd/green-20260717T185451Z-test004-ceremony.log.
- See docs/specs/SPEC-0048-prompt-diet-byte-budget-true-up.md and
  docs/knowledge/LEARNED.md 2026-07-17 entry.
