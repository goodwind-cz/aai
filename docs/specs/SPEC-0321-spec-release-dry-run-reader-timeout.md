---
id: spec-release-dry-run-reader-timeout
type: spec
number: 321
status: done
frozen_sha256: e45b7c3ca014842221bba8fa8b26a7abf3473c73156cd610df4880a9d9c721c7
ceremony_level: 1
links:
  requirement: release-dry-run-reader-timeout
  rfc: null
  pr: []
  commits: []
---

# Release dry-run: a per-reader timeout with measured headroom

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0272-release-dry-run-reader-timeout.md
- Technology contract: docs/TECHNOLOGY.md
- Registry items closed by this scope: none. `fu-dry-run-budget-from-weights` is touched but stays open: this ride raises the per-reader bound and refreshes one weight; it does not derive the budget from the weights. The delivery appends a note to it.

Ceremony justification: one executor default pair in `.aai/scripts/release-dry-run.mjs`, its pinned tests, one prose comment, one weight row and the weight audit test that names its source runs; no state engine, allocator, guard, hook or workflow file is touched and no protected_paths_l3 surface is involved; fully reversible by restoring two constants. Independent validation and one code review remain required.

## Implementation strategy
- Strategy: loop
- Rationale: the change is two constants, one weight row and the tests that pin them. Each changed assertion is observed failing against the pre-change tree (TEST-007 pins 900 and 1800 while the code still says 540 and 1080; TEST-006 fails under a scratch default of 901; TEST-4037 fails on the re-measured weight file before it admits the re-measure set), then green.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: autopilot default; the owner directed a dedicated worktree because the main checkout is shared and carries unrelated changes.
- User decision: worktree
- Base ref: origin/main (3a81b019)
- Worktree branch/path: fix/release-dry-run-reader-timeout at /Users/ales/Projects/aai-worktrees/release-dry-run-timeout
- Inline review scope: .aai/scripts/release-dry-run.mjs, tests/skills/lib/release-first.test.mjs, tests/skills/test-aai-sync-node.sh, tests/skills/suite-weights.tsv, tests/skills/test-aai-suite-select.sh, docs/issues/CHANGE-0272-release-dry-run-reader-timeout.md, docs/specs/SPEC-0321-spec-release-dry-run-reader-timeout.md
- Code review required: true.

## Measured cause
- The CI dry-run reports of 19 PR runs (2026-11-24 to 2026-11-26) show `tests/skills/test-aai-release-cut.sh` on the rolled arm passing in 346 to 517 s, median about 465 s, and timing out at the 540 s bound in runs 45642970445, 45813029163, 45855312625 and 45877369789 (two attempts on #599). Its ordinary diagnostic arm, which runs alone after the rolled arm, passed in 350 to 370 s every time.
- The suite grew. On main-push runs it took 99 to 142 s up to 2026-11-23 (the five D-WEIGHTS runs, weight 116), 279 s at #582, and 359 to 601 s from #586 on. #582 added the pwsh launcher and Pester cases TEST-4026 to TEST-4028; #586 added TEST-4041.
- Inside the dry-run it shares four job slots with the other heavy readers (test-aai-release.sh, test-aai-pre-commit-checks.sh, test-aai-merge-cleanup.sh at 400 to 480 s) and runs about 1.25 times slower than alone. The 540 s bound came from one 464 s measurement taken alone (1.16 times), so ordinary variance crosses it.
- #597's private `XDG_CACHE_HOME` per suite does not contribute measurably: dry-run passes before it (median about 465 s) and after it (448 and 450 s) match, and the main-push times on both sides overlap (363 to 601 s before, 371 s after). The cache is per suite, so only the first pwsh start of a suite is cold.
- The CHANGELOG reader count grew from 46 to 49 over the same window, adding contention to the same four slots. It is a small contributor.
- The stale weight 116 schedules the suite twelfth of 49 readers, into the band where the heavy readers already hold the slots.

## Scope
In scope:
- `.aai/scripts/release-dry-run.mjs`: `DEFAULT_READER_TIMEOUT_SECONDS` 540 to 900 and `DEFAULT_BUDGET_SECONDS` 1080 to 1800, so the defaults equal the workflow and satisfy 1800 >= 2 x 900; the comment above them states the measurement.
- `tests/skills/lib/release-first.test.mjs`: TEST-006 imports the exported reader default and asserts budget >= 2 x that default; TEST-007 pins 900 and 1800.
- `tests/skills/test-aai-sync-node.sh`: the TEST-4019 comment names the 900 s bound and the 30-minute budget.
- `tests/skills/suite-weights.tsv`: the `aai-release-cut` row is re-measured from the five latest successful main-push runs (45875856570, 45867692451, 45820326840, 45816645699, 45808578900; 371, 601, 363, 597, 408 s; median 408), with five `# source run` lines and a header line.
- `tests/skills/test-aai-suite-select.sh` TEST-4037: the source run lines are the five D-WEIGHTS runs plus that named re-measure set; only `aai-release-cut` may name the re-measure runs, and it must name only them.

Out of scope: the workflow (budget 1800 and `timeout-minutes: 35` stay), making the suite faster, deriving the budget from the weights.

## Acceptance Criteria Mapping

| Requirement | Spec-AC | Verification | Observable and evidence |
|-------------|---------|--------------|-------------------------|
| AC-001 | Spec-AC-01 | `env -u AAI_ROLE bash tests/skills/test-aai-release-first.sh test_007` | exit 0; the production-default run reports readerTimeoutSeconds 900 and budgetSeconds 1800 |
| AC-002 | Spec-AC-02 | `env -u AAI_ROLE bash tests/skills/test-aai-release-first.sh test_006` | exit 0 on the change; the same test fails with a scratch default of 901 |
| AC-003 | Spec-AC-03 | `env -u AAI_ROLE bash tests/skills/test-aai-suite-select.sh test_4037_weights_measured` | exit 0; auditWeights passes and the aai-release-cut row is 408 |
| AC-001 | Spec-AC-04 | `env -u AAI_ROLE bash tests/skills/test-aai-sync-node.sh test_4019_wiring` | exit 0; the prose names 900 and the suite still holds |
| AC-004 | Spec-AC-05 | `gh pr checks <pr>` for the release dry-run check | the check is pass on the PR head; observed after the PR opens |

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN release-dry-run.mjs runs without --timeout-seconds or --budget-seconds THEN its report SHALL record readerTimeoutSeconds 900 and budgetSeconds 1800. | done | docs/ai/tdd/release-dry-run-reader-timeout/red-test_007.log; docs/ai/tdd/release-dry-run-reader-timeout/green-test_007.log; docs/ai/reports/VALIDATION-release-dry-run-reader-timeout.md | — | TEST-007 |
| Spec-AC-02 | WHEN the workflow budget is read THEN TEST-006 SHALL assert it is at least twice the exported DEFAULT_READER_TIMEOUT_SECONDS AND fail when that default exceeds half the budget. | done | docs/ai/tdd/release-dry-run-reader-timeout/red-test_006-901.log; docs/ai/tdd/release-dry-run-reader-timeout/green-test_006.log; docs/ai/reports/VALIDATION-release-dry-run-reader-timeout.md | — | TEST-006 |
| Spec-AC-03 | WHEN auditWeights reads suite-weights.tsv THEN it SHALL pass, the source run lines SHALL be the five D-WEIGHTS runs plus the five named re-measure runs, only aai-release-cut SHALL name the re-measure runs, AND its weight SHALL be 408. | done | docs/ai/tdd/release-dry-run-reader-timeout/red-test_4037.log; docs/ai/tdd/release-dry-run-reader-timeout/green-test_4037.log; docs/ai/tdd/release-dry-run-reader-timeout/p4-subset.log; docs/ai/reports/VALIDATION-release-dry-run-reader-timeout.md | — | TEST-4037 |
| Spec-AC-04 | WHEN test-aai-sync-node.sh describes the release rehearsal THEN its comment SHALL name the 900 second bound and the suite SHALL pass. | done | docs/ai/tdd/release-dry-run-reader-timeout/green-test_4019.log; docs/ai/reports/VALIDATION-release-dry-run-reader-timeout.md | — | TEST-4019 |
| Spec-AC-05 | WHEN this PR's CI runs THEN the release dry-run check SHALL pass on the PR head. | deferred (observed on this PR CI after open) | — | validation:2026-11-27 | TEST-5001 |

## Implementation plan
Edit the two constants and comment; update TEST-006 and TEST-007; observe each failing against the old constants or a scratch 901 default; update the weight row, its sample line, the source lines and header; extend TEST-4037 and observe it failing before its extension; update the TEST-4019 comment; run the focused commands and the release-first and suite-select selectors.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---------|---------|------|----------------------|-------------|----------|--------|
| TEST-007 | Spec-AC-01 | integration | tests/skills/lib/release-first.test.mjs | modified row: `env -u AAI_ROLE bash tests/skills/test-aai-release-first.sh test_007` | `sed:s/DEFAULT_READER_TIMEOUT_SECONDS=900/DEFAULT_READER_TIMEOUT_SECONDS=540/` on .aai/scripts/release-dry-run.mjs | green |
| TEST-006 | Spec-AC-02 | inspection | tests/skills/lib/release-first.test.mjs | modified row: `env -u AAI_ROLE bash tests/skills/test-aai-release-first.sh test_006` | `sed:s/DEFAULT_READER_TIMEOUT_SECONDS=900/DEFAULT_READER_TIMEOUT_SECONDS=901/` on .aai/scripts/release-dry-run.mjs | green |
| TEST-4037 | Spec-AC-03 | inspection | tests/skills/test-aai-suite-select.sh | modified row: `env -u AAI_ROLE bash tests/skills/test-aai-suite-select.sh test_4037_weights_measured` | `sed:s/\naai-release-cut\t408\n/\naai-release-cut\t116\n/` on tests/skills/suite-weights.tsv | green |
| TEST-4019 | Spec-AC-04 | inspection | tests/skills/test-aai-sync-node.sh | modified row: `env -u AAI_ROLE bash tests/skills/test-aai-sync-node.sh test_4019_wiring` | none | green |
| TEST-5001 | Spec-AC-05 | e2e | .github/workflows/skill-suite.yml | `gh pr checks <pr>`: the release dry-run job of this PR's own run passes | none | pending |

## Verification
The focused commands above, then `node --test tests/skills/lib/release-first.test.mjs` exit 0. No full sweep: the change touches no other suite's input except the weight file, whose readers are TEST-4037, TEST-3475 and the dry-run schedule.

## Evidence contract
Record ref_id release-dry-run-reader-timeout, Spec-AC and TEST ids, commands, exit codes and evidence paths under docs/ai/tdd/release-dry-run-reader-timeout/. Review scope is the inline review scope with base origin/main.

### Evidence by strategy
loop: per-TEST green runs with their exit codes; the RED observations are recorded in the validation report, storage optional.

## Residual risks
- The weight change rebalances the CI shard plan; the plan is recomputed per run and no test pins a leg assignment.
- A hung reader now holds a slot up to 900 s; the 1800 s budget and the 35-minute deadline still bound the job.
- Spec-AC-03 amends SPEC-0313 Spec-AC-01 (exactly the five D-WEIGHTS runs) additively: one suite may name one named re-measure set. Recorded with spec-amend, signoff none.
