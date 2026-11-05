---
id: spec-admit-tests-other-suites
type: spec
number: null
status: implementing
mutation_gate: v1
mutation_uncomparable: 6
frozen_sha256: 8f6be663332cb6620bc42c7f7b92bdcbc6adeeed311fc10862a876a2e688f112
ceremony_level: 1
links:
  requirement: admit-tests-other-suites
  rfc: null
  pr: []
  commits: []
---

# Admission tests judge only their own suites; the sources-escape lint rule is covered

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/ISSUE-DRAFT-admit-tests-other-suites.md
- Technology contract: docs/TECHNOLOGY.md
- Follow-ups closed at delivery: `fu-admit-tests-red-on-other-suites` and `fu-sources-lint-escape-untested` (the delivery commit or the close ceremony appends their `follow_up_status` done lines, resolved by this ref).

Ceremony justification: test-only change inside one internal suite (tests/skills/test-aai-suite-reuse.sh, not shipped downstream); no script, state engine, allocator, guard or workflow canon file is touched and no protected_paths_l3 surface is involved; fully reversible. Independent Validation and code review remain required.

## Implementation strategy
- Strategy: tdd
- Rationale: both defects are observable as a red or a missing red. Item 1 is reproduced on a branch that changes only another manifest suite; item 2 is proven by a scratch copy of `suite-reuse.mjs` with the `..` check removed, against which the old TEST-3341 stays green and the extended one goes red.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: autopilot default; the main checkout is shared and carries an unrelated uncommitted change.
- User decision: worktree
- Base ref: main (f8297dbc)
- Worktree branch/path: fix/admit-tests-other-suites at /Users/ales/Projects/aai-worktrees/admit-tests-other-suites
- Inline review scope: tests/skills/test-aai-suite-reuse.sh, docs/issues/ISSUE-DRAFT-admit-tests-other-suites.md, docs/specs/SPEC-DRAFT-admit-tests-other-suites.md, docs/ai/decisions.jsonl
- Code review required: true.

## Scope
In scope, all in `tests/skills/test-aai-suite-reuse.sh`:
- `test_3307_live_appended_probes` and `test_3337_split_admission` keep the ADMIT-OFF and ADMIT-NONE exits, the ADMIT-FAIL rejection and the per-suite probe checks for an admitted suite, but when none of their own suites is in the admission output they pass with a "not admitted on this branch" line instead of failing. Standalone mode (empty `LIVE_ADMIT_OUT`) is unchanged.
- `test_3341_sources_lint` gains two cases: a `../`-escaping sources path and one that normalizes outside the root (`tests/../../x`), both failing lint with exit 1 and `no-source-file`. Its comment becomes true.
- Three new tests, TEST-3370 to TEST-3372, drive the two live-admission tests against a synthetic admission output.

Finding (no product change): `.aai/scripts/suite-reuse.mjs` line 362 rejects any `sources` path that is absolute or has a `..` segment, so both escape forms are rejected today; the product code is not changed.

Out of scope: the admission itself, the manifest, every other suite.

## Acceptance Criteria Mapping

| Requirement | Spec-AC | Verification | Observable and evidence |
|-------------|---------|--------------|-------------------------|
| Expected: TEST-3307 judges only the five index-reading suites | Spec-AC-01 | `env -u AAI_ROLE bash tests/skills/test-aai-suite-reuse.sh test_3370_probe_test_other_suites_only` | exit 0; a synthetic admission holding only `aai-pricing` passes TEST-3307 with a not-admitted line |
| Expected: TEST-3337 judges only the four split suites | Spec-AC-02 | `env -u AAI_ROLE bash tests/skills/test-aai-suite-reuse.sh test_3371_split_test_other_suites_only` | exit 0; the same input passes TEST-3337 with a not-admitted line |
| Expected: an admitted own suite is still judged | Spec-AC-03 | `env -u AAI_ROLE bash tests/skills/test-aai-suite-reuse.sh test_3372_own_suite_still_judged` | exit 0; an ADMIT-FAIL of an own suite, an admitted own suite or corpus half without its probe, and an admission output with no ADMIT-PASS or ADMIT-FAIL line (a crash, a lint refusal) still fail both tests; ADMIT-OFF still passes |
| Expected: lint covers the escaping sources path | Spec-AC-04 | `env -u AAI_ROLE bash tests/skills/test-aai-suite-reuse.sh test_3341_sources_lint` | exit 0; `../x` and `tests/../../x` fail lint with exit 1 |

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN the admission output holds only suites other than the five index-reading ones, THEN TEST-3307 SHALL pass with a not-admitted line. | implementing | docs/ai/tdd/admit-tests-other-suites/red-item1.log; docs/ai/tdd/admit-tests-other-suites/green.log | — | TEST-3370 |
| Spec-AC-02 | WHEN the admission output holds only suites other than the four split ones, THEN TEST-3337 SHALL pass with a not-admitted line. | implementing | docs/ai/tdd/admit-tests-other-suites/red-item1.log; docs/ai/tdd/admit-tests-other-suites/green.log | — | TEST-3371 |
| Spec-AC-03 | WHEN an own suite is in the admission output as ADMIT-FAIL, or as ADMIT-PASS without its probe or with poisoned zero, THEN TEST-3307 and TEST-3337 SHALL still fail. | implementing | docs/ai/tdd/admit-tests-other-suites/red-f1.log; docs/ai/tdd/admit-tests-other-suites/green.log | — | TEST-3372 |
| Spec-AC-04 | WHEN a sources path escapes the repo root (`../x`, `tests/../../x`), THEN lint SHALL fail with exit 1 and name `no-source-file`. | implementing | docs/ai/tdd/admit-tests-other-suites/red-item2.log; docs/ai/tdd/admit-tests-other-suites/green.log | — | TEST-3341 |

## Implementation plan
Write TEST-3370..3372 and the TEST-3341 extension, observe RED (item 1 on a branch that changes only another manifest suite; item 2 against a scratch `suite-reuse.mjs` without the `..` check), apply the two test-body edits, observe GREEN, run the full suite and `bash -n`.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---------|---------|------|----------------------|-------------|----------|--------|
| TEST-3370 | Spec-AC-01 | unit | tests/skills/test-aai-suite-reuse.sh | `env -u AAI_ROLE bash tests/skills/test-aai-suite-reuse.sh test_3370_probe_test_other_suites_only` | none | green |
| TEST-3371 | Spec-AC-02 | unit | tests/skills/test-aai-suite-reuse.sh | `env -u AAI_ROLE bash tests/skills/test-aai-suite-reuse.sh test_3371_split_test_other_suites_only` | none | green |
| TEST-3372 | Spec-AC-03 | unit | tests/skills/test-aai-suite-reuse.sh | `env -u AAI_ROLE bash tests/skills/test-aai-suite-reuse.sh test_3372_own_suite_still_judged` | none | green |
| TEST-3341 | Spec-AC-04 | unit | tests/skills/test-aai-suite-reuse.sh | modified row: `env -u AAI_ROLE bash tests/skills/test-aai-suite-reuse.sh test_3341_sources_lint` | none | green |
| TEST-3307 | Spec-AC-01 | regression | tests/skills/test-aai-suite-reuse.sh | modified row: `env -u AAI_ROLE bash tests/skills/test-aai-suite-reuse.sh test_3307_live_appended_probes` | none | green |
| TEST-3337 | Spec-AC-02 | regression | tests/skills/test-aai-suite-reuse.sh | modified row: `env -u AAI_ROLE bash tests/skills/test-aai-suite-reuse.sh test_3337_split_admission` | none | green |

## Verification
Focused commands above, full `env -u AAI_ROLE bash tests/skills/test-aai-suite-reuse.sh` exit 0, `bash -n`. No full sweep.

## Evidence contract
Record ref_id admit-tests-other-suites, Spec-AC and TEST ids, commands, exit codes and evidence paths under docs/ai/tdd/admit-tests-other-suites/. Review scope is the inline review scope with base main.

### Evidence by strategy
tdd: stored RED (red-item1.log, red-item2.log) and GREEN (green.log) under docs/ai/tdd/admit-tests-other-suites/.
