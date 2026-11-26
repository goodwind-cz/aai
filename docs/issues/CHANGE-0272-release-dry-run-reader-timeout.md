---
id: release-dry-run-reader-timeout
type: change
number: 272
status: done
capability: release-dry-run-reader-timeout
user_visible: false
links:
  pr: []
  commits: []
---

# Release dry-run: a per-reader timeout with measured headroom

## Summary
- The `release-dry-run` CI job (`.github/workflows/skill-suite.yml`, step
  "Rehearse production rollup with every discovered reader") times out the
  reader `tests/skills/test-aai-release-cut.sh` on the rolled payload at the
  540 s per-reader default (`DEFAULT_READER_TIMEOUT_SECONDS` in
  `.aai/scripts/release-dry-run.mjs`). It blocks PRs and the v2026.11.26
  release PR #599.
- Raise the per-reader default to 900 s, keep the 1800 s executor budget the
  workflow passes and the 35-minute job deadline, keep the invariant
  "two complete reader arms fit the executor allowance" (1800 >= 2 x 900),
  and refresh the stale `aai-release-cut` scheduling weight.

## Motivation / Business Value
- Every PR run and the release PR fail on a reader that is healthy: the same
  suite passes alone in 350-370 s. The failure is deterministic under the
  current bound, not a flake.

## Measurement (CI, 2026-11-24 to 2026-11-26)
- Dry-run reports (`release-dry-run.json` artifacts, latest attempt of 19 PR
  runs): `test-aai-release-cut.sh` rolled arm PASS in 346-517 s (median about
  465 s); timeouts at 540 s in runs 45642970445, 45813029163 (#596),
  45855312625 (#597) and 45877369789 (#599); one budget-exhausted at 530 s
  (45532832909). The ordinary diagnostic arm, which runs alone after the
  rolled arm, passed in 350-370 s every time.
- Main-push skill-suite runs (full framework legs): the suite took 99-142 s
  up to 2026-11-23 (the five D-WEIGHTS runs, weight 116), 279 s at #582
  (1aec7030), and 359-601 s from #586 on (last five: 371, 601, 363, 597,
  408 s).
- Cause: the suite itself grew. #582 added the pwsh launcher and Pester cases
  TEST-4026 to TEST-4028, #586 added TEST-4041 (another TEST-4027 run under a
  broken pwsh cache). Under the dry-run's four concurrent readers (with
  test-aai-release.sh, pre-commit-checks and merge-cleanup at 400-480 s each)
  it runs about 1.25 times slower than alone. The 540 s bound was set from one
  464 s measurement taken alone (1.16 times), so ordinary runner variance
  crosses it.
- Not the cause: #597's private `XDG_CACHE_HOME` per suite. Dry-run PASS
  times before it (median about 465 s) and after it (448, 450 s) are the
  same, and the main-push times straddle it unchanged (363-601 s before,
  371 s after). The cache is per suite, so only the first pwsh start of a
  suite is cold.
- Contributing, small: the CHANGELOG reader count grew from 46 to 49, which
  adds contention to the same four job slots.
- The stale weight (116) schedules the suite twelfth of 49, into the slot
  band shared with the other heavy readers.

## Scope
- In scope:
  - `.aai/scripts/release-dry-run.mjs`: `DEFAULT_READER_TIMEOUT_SECONDS` 540
    to 900, `DEFAULT_BUDGET_SECONDS` 1080 to 1800 (the workflow value, so the
    default also satisfies the two-arm invariant), comment updated.
  - `tests/skills/lib/release-first.test.mjs`: the TEST-006 invariant reads
    the exported default instead of a literal, and the TEST-007 pins follow
    the new defaults.
  - `tests/skills/test-aai-sync-node.sh`: the TEST-4019 prose names the new
    bound.
  - `tests/skills/suite-weights.tsv`: `aai-release-cut` re-measured from the
    five latest successful main-push runs, in the file's sample-comment
    convention, with their source run lines.
  - `tests/skills/test-aai-suite-select.sh` TEST-4037: admits that one named
    re-measure set for `aai-release-cut` only (additive amendment of
    SPEC-0313 Spec-AC-01, disclosed).
- Out of scope:
  - Making `test-aai-release-cut.sh` faster (follow-up).
  - Deriving the budget from the weights (`fu-dry-run-budget-from-weights`
    stays open, with a note).
  - The workflow file (no L3 surface is touched).

## Affected Area
- Release dry-run executor defaults, its pinned tests, and the suite weights.

## Desired Behavior (To-Be)
- A healthy release-cut reader finishes inside the per-reader bound on CI
  with headroom (900 s against a 601 s worst observed run anywhere), while a
  hung reader is still killed and reported as a timeout.

## Acceptance Criteria
- AC-001: `DEFAULT_READER_TIMEOUT_SECONDS` is 900 and
  `DEFAULT_BUDGET_SECONDS` is 1800; the workflow budget stays 1800 and the
  job deadline 35 minutes.
- AC-002: TEST-006 asserts budget >= 2 x the exported reader default and
  fails when the default exceeds half the budget.
- AC-003: `auditWeights` passes, and the `aai-release-cut` weight equals the
  median of its five named re-measure runs.
- AC-004: the release dry-run job passes on this PR's own CI run.

## Verification
- `node --test tests/skills/lib/release-first.test.mjs`
- `env -u AAI_ROLE bash tests/skills/test-aai-suite-select.sh test_4037_weights_measured`
- `env -u AAI_ROLE bash tests/skills/test-framework.sh --skill aai-release-first`
- The PR's `release dry-run` check.

## Constraints / Risks
- A higher bound lets a truly hung reader hold a slot 360 s longer; the 1800 s
  budget and the 35-minute deadline still bound the job.
- Changing the weight changes the CI shard plan; the plan is recomputed per
  run and only balance changes.
- No secret is referenced.

## Notes
- Implementation mode: autopilot, Planning decides.
- Use plain Markdown headings and body text.
