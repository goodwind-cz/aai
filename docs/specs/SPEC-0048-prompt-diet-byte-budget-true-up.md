---
id: prompt-diet-byte-budget-true-up
type: spec
number: 48
status: done
ceremony_level: 1
links:
  requirement: DEBT-0002
  rfc: null
  pr:
    - 100
  commits:
    - e3a1b08
---

# Spec — prompt-diet byte-budget & thin-wrapper ceiling true-up (DEBT-0002)

Ceremony justification: L1 single-surface test-threshold fix. The change re-baselines
the prompt-corpus measurement constants in ONE producer test
(`tests/skills/test-aai-prompt-diet.sh` TEST-010/TEST-011) and removes ONE now-dead
tolerance in its ONE consumer (`test-aai-ceremony-levels.sh` test_017), plus LEARNED/DEBT
docs. No engine, product, or protected-path (`protected_paths_l3`) code is touched; no
prompt CONTENT is edited (re-dieting is explicitly out of scope). Evidence bar is unchanged
(both suites must exit 0). Review may re-classify upward.

## Links
- Requirement: docs/issues/DEBT-0002-prompt-diet-byte-budget-true-up.md
- Technology contract: docs/TECHNOLOGY.md
- Prior art / discipline: SPEC-0017 (prompt-diet corpus + byte floor), LEARNED.md 2026-07-17

## Problem (measured, clean main this session)
- TEST-010 byte floor: `after`=325653 B, `extra`(INTAKE_COMMON+STATE_FALLBACK)=8254 B,
  `BASELINE_PROMPT_BYTES`=357457 → net reduction = **23550 B** vs
  `REQUIRED_REDUCTION_BYTES`=**28672 B**. Deficit = **5122 B**. Only TEST-010's byte half
  is RED; its repo-wide strict-audit half is green.
- TEST-011 thin-wrapper ceiling: `.aai/ORCHESTRATION.prompt.md` = **40/40 lines** (zero
  headroom — a 1-line canon growth broke it live 2026-07-17). Other wrappers:
  METRICS_FLUSH 31, METRICS_REPORT 15.
- Consumer seam: `test-aai-ceremony-levels.sh` runs prompt-diet in TWO places —
  `test_010_seam_survival` (asserts exit 0; currently FAILS the whole suite) and `test_017`
  (carries an identity-based tolerance for the same pre-existing shortfall).

## Re-baseline mechanism (decisions)
1. **Byte floor — justified-additions ledger, NOT a blank raise.** Keep
   `BASELINE_PROMPT_BYTES` and `REQUIRED_REDUCTION_BYTES` UNCHANGED (they are the historical
   SPEC-0017 diet contract; rewriting them erases history and IS the blank-raise anti-pattern).
   Add a new constant `JUSTIFIED_GROWTH_BYTES` credited into the reduction:
   `adjusted_reduction = BASELINE - after - extra + JUSTIFIED_GROWTH_BYTES`, still gated by
   `>= REQUIRED_REDUCTION_BYTES`. `JUSTIFIED_GROWTH_BYTES` carries an inline ledger comment
   enumerating the canon-mandated additions since the SPEC-0017 diet (dual-verdict review
   taxonomy, VALIDATION 8a exception, CEREMONY LANE block, RED_CLASS discipline, SECRETS
   PREFLIGHT block, doc-number reservation docs, ceremony-lane surfaces) and recording the
   measured deficit (5122 B) + chosen credit + resulting headroom.
2. **Floor still bites — bounded headroom cap.** TEST-010 additionally asserts
   `0 <= headroom <= HEADROOM_CAP` where `headroom = adjusted_reduction - REQUIRED_REDUCTION_BYTES`
   and `HEADROOM_CAP` is small (≈2048 B). This mechanically prevents padding
   `JUSTIFIED_GROWTH_BYTES` arbitrarily and forces future prompt growth beyond the cap to FAIL
   (add a justified ledger line or shrink) — satisfying the SPEC-0017 "no silent absorption"
   constraint by construction, not convention. Recommended: `JUSTIFIED_GROWTH_BYTES ≈ 6144 B`
   → headroom ≈ 1022 B, inside a 2048 B cap. (Implementation confirms exact values from the
   clean-tree measurement.)
3. **Line ceiling — documented headroom.** Raise the TEST-011 thin-wrapper ceiling from 40 to
   45 with an inline rationale comment. 40/40 ORCHESTRATION passes with 5-line headroom; a
   wrapper exceeding 45 (no longer "thin") still fails. Other two wrappers stay well under.
4. **Consumer tolerance removal (fold-in).** Once the floor is green, `test_017`'s S3
   pre-existing-shortfall tolerance branch collapses to a plain prompt-diet exit-0 assertion;
   its explanatory comments are updated to cite DEBT-0002 as resolved. `test_010_seam_survival`
   and every `test_001..010` SPEC-0030 stanza are NOT edited (D5 additive-only) — they already
   assert exit 0 and pass once the floor holds.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC    | Description                                                                                                                    | Status  | Evidence | Review-By | Notes |
|------------|------------------------------------------------------------------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | prompt-diet TEST-010 byte floor re-baselined via `JUSTIFIED_GROWTH_BYTES` ledger (BASELINE/REQUIRED unchanged); suite exit 0 | done | docs/ai/tdd/red-20260717T185005Z-test010-011.log; docs/ai/tdd/green-20260717T185321Z-test001-002-003.log (reduction 29694 B) | — | — |
| Spec-AC-02 | TEST-010 headroom-cap assertion proves `0 <= headroom <= HEADROOM_CAP` — floor still bites, credit cannot be padded          | done | docs/ai/tdd/red-20260717T185240Z-test002-headroomcap.log (padded credit 99999 -> headroom 94877 FAIL); docs/ai/tdd/green-20260717T185321Z-test001-002-003.log (headroom 1022/2048) | — | — |
| Spec-AC-03 | TEST-011 wrapper ceiling raised 40→45 with rationale comment; ORCHESTRATION passes with headroom; >45 still fails            | done | docs/ai/tdd/green-20260717T185321Z-test001-002-003.log (TEST-011 pass, synthetic 46-line fixture proof) | — | — |
| Spec-AC-04 | ceremony-levels test_017 tolerance removed → plain exit-0 assertion; full suite exit 0 (D5: test_001..010 untouched)         | done | docs/ai/tdd/green-20260717T185451Z-test004-ceremony.log (full suite PASS); git diff confirms test_010_seam_survival/test_001..010 untouched | — | — |
| Spec-AC-05 | LEARNED.md 2026-07-17 entry records the resolution; DEBT-0002 doc status → done with links                                    | done | docs/knowledge/LEARNED.md 2026-07-17 "RESOLVED" entry; docs/issues/DEBT-0002-prompt-diet-byte-budget-true-up.md status: done + Resolution section | — | — |

Status values: planned | implementing | done | deferred | blocked | rejected

## Seam analysis
- SEAM (producer→consumer): `test-aai-prompt-diet.sh` TEST-010 is consumed by
  `test-aai-ceremony-levels.sh` in TWO code paths (`test_010_seam_survival`, `test_017`).
  Covered end-to-end by TEST-004 (run the FULL ceremony suite, assert exit 0 — the consumer
  observes the producer's real green, not a mocked tolerance).
- SEAM (repo-wide audit): TEST-010 also runs `docs-audit --check --strict`. Threshold-only
  edits do not touch docs bodies; that half stays green (already exit 0 this session) — TEST-001
  re-asserts it.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                          | Description                                                                                  | Status  |
|----------|------------|-------------|-----------------------------------------------|----------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-prompt-diet.sh          | `bash …/test-aai-prompt-diet.sh` exits 0 on clean tree (byte half green via ledger credit)   | green   |
| TEST-002 | Spec-AC-02 | unit        | tests/skills/test-aai-prompt-diet.sh          | headroom in [0, HEADROOM_CAP]; a synthetic over-credit / +N>cap prompt growth makes TEST-010 FAIL | green   |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-prompt-diet.sh          | TEST-011 ceiling=45: ORCHESTRATION (40) passes; a synthetic 46-line wrapper fixture fails     | green   |
| TEST-004 | Spec-AC-04 | integration | tests/skills/test-aai-ceremony-levels.sh      | full ceremony suite exits 0 (seam: tolerance removed, consumer sees producer green)          | green   |
| TEST-005 | Spec-AC-05 | integration | docs/knowledge/LEARNED.md, docs/issues/DEBT-0002-*.md | grep the resolution markers in LEARNED + DEBT status `done` with links                | green   |

Test status values: pending → red → green

RED-proof obligation: prompt-diet TEST-010 and the ceremony suite are observably RED on clean
main NOW (23550 < 28672; suite aborts at `test_010_seam_survival`). The NEW anti-bloat guard
(TEST-002) must be seen RED with a deliberately-wrong credit before it counts as GREEN.

## Implementation strategy
- Strategy: hybrid
- Rationale: TDD the new `JUSTIFIED_GROWTH_BYTES` + headroom-cap guard (TEST-002) — it is the
  load-bearing anti-bloat logic that MUST actually bite, so observe it RED (wrong credit) then
  GREEN. Loop the mechanical edits (constant/comment re-baseline, ceiling 40→45, tolerance
  removal, LEARNED/DEBT docs — TEST-001/003/004/005), each RED-proven by the current failing
  state before the edit.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: test-threshold + docs only, single scope, no engine/protected-path code;
  fully reversible.
- User decision: inline
- Base ref: fix/prompt-diet-budget-true-up
- Inline review scope: tests/skills/test-aai-prompt-diet.sh, tests/skills/test-aai-ceremony-levels.sh, docs/knowledge/LEARNED.md, docs/issues/DEBT-0002-prompt-diet-byte-budget-true-up.md, docs/specs/SPEC-0048-prompt-diet-byte-budget-true-up.md
- Code review required: true (test change per PLANNING step 9)

## Verification
- `bash tests/skills/test-aai-prompt-diet.sh` → exit 0 (TEST-001/002/003).
- `bash tests/skills/test-aai-ceremony-levels.sh` → exit 0 (TEST-004).
- `grep` resolution markers in docs/knowledge/LEARNED.md and DEBT-0002 status `done` (TEST-005).
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal (done with non-empty Evidence).

## Evidence contract
Per implementation/TDD/validation/review artifact record: ref_id, Spec-AC + TEST-xxx links,
command or review scope, exit code or verdict, evidence path, and commit SHA / diff range.

SPEC-FROZEN: true
