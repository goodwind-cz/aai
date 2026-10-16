# Code Review r3 — git-platform-detected-at-bootstrap

- Ref: git-platform-detected-at-bootstrap
- Round: 3 (proportionate delta review)
- Delta: `git diff 2d4b2e03..HEAD` = b0d32033 only (7 files, +10/-8)
- Prior round: docs/ai/reviews/review-20261016T180456Z-git-platform-detected-at-bootstrap-r2.md (PASS; r2-NB-1 to remediate, r2-NB-2 accepted residual)
- Validation: docs/ai/reports/VALIDATION-20261016T181112Z-git-platform-detected-at-bootstrap-r3.md (PASS)

## Verdicts

- spec_compliance: **PASS**
- code_quality: **PASS**

## r2-NB-1 closure

CLOSED. `.aai/SKILL_MERGE.prompt.md:16` now reads "Exit 4 (completion_pending) stops: re-run `/aai-merge <n>`." The re-run goes back through preflight, so a completed PR lands in `already_merged` and then step 2, and a still-active PR goes back through every gate. The old wording could be read as "re-run the platform.mjs line", which refuses `not_open` on a completed PR. `tests/skills/test-aai-platform-adapter.sh:776` pins the exact sentence. Validation r3 showed RED-first on that sentence (rc=1 against the 2d4b2e03 prompt, rc=0 at HEAD).

## Delta walk

| Change | Check | Result |
|---|---|---|
| SKILL_MERGE:16 wording | `wc -c` 4377 -> 4391 (+14) | consistent |
| prompt-diet-ledger.sh:255 entry 882 -> 896 | 442 + 454 = 896, at most 900 cap; byte counts match `wc -c` (BOOTSTRAP 5724, MERGE 4391) | consistent |
| test-aai-prompt-diet.sh want_growth 56826 -> 56840 | 55944 + 896; selector `test_012_growth_sum_matches_ledger` re-run: PASS 56840 | consistent |
| test-aai-pr-preflight.sh test_008 sum +882 -> +896 | same credit, mirrored | consistent |
| test-aai-platform-adapter.sh:776 new assertion | selector TEST-076 re-run rc=0 | consistent |
| Spec TEST-076 description cell + frozen_sha256 | only the description cell changes (+14 chars); decisions.jsonl has a measurement-class `spec_amendment` at 18:09:52Z naming that cell; `spec-amend list --strict` lists it | consistent |

The delta adds no new behaviour, surface or risk. The r2 whole-ride verdict (Spec-AC-01..14) still stands, and validation r3 re-ran the affected suites and the mutation replay (15/15 redden, GATE PASS).

## Findings

### BLOCKING
None.

### NON-BLOCKING
None new. r2-NB-2 is still an accepted residual and has not changed.

## cannot_verify

- I did not re-run the full sweep, the Pester twins or the mutation replay in this round. For those I rely on validation r3 (selected suites + CORE) and on r2's full sweep (109/109).
- The Azure DevOps exit 4 path has not run against a live Azure DevOps org. The wording is checked against the platform.mjs and merge-cleanup code paths cited in validation r3, not against a live run.
- The `test-aai-prompt-diet.sh` selector here is the function name. `TEST-012` as a selector returns "Unknown test". This is not a defect of the delta. TEST-076 itself calls it in its own selector form, and that passed.
