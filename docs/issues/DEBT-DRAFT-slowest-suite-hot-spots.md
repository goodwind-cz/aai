---
id: slowest-suite-hot-spots
type: techdebt
number: null
status: draft
links:
  pr: []
  commits: []
---

# Tech Debt: four hot spots make the always-run and slowest suites expensive

## Debt Summary
Apart from nested suite runs (separate intake), a few single tests dominate
the cost of the slowest suites. `aai-hygiene-pack` (282 s) is in the core set
that runs on every PR, so its cost is paid even in selected mode.

1. hygiene-pack test_094 takes 136 s: it runs 67 suites with an unknown test
   name to prove each rejects it.
2. hygiene-pack TEST-562 takes 92 s: the no-NUL check spawns one `node` and
   one `git check-attr` per tracked file (1,598 files). The shipped check has
   the same per-file shape.
3. `aai-sync-seed` (336 s on CI) calls the real `aai-sync` about 77 times at
   about 2.2 s each.
4. `aai-run-tests` (133 s) sleeps through its reaper and timeout scenarios.

## Root Cause
- Each test was written for correctness on a small tree; the per-file and
  per-call costs grew with the repository and were never measured.

## Current Cost / Risk
- About 230 s on every PR (hygiene-pack) and about 400 s more of full-sweep
  CPU in sync-seed and run-tests.
- The per-file no-NUL check also slows the shipped pre-commit path on large
  downstream repositories.

## Target State
- The no-NUL check runs as one process over all files, in the test and in the
  shipped check.
- test_094 proves the unknown-test-name contract statically for all suites and
  executes only a small sample.
- sync-seed builds one `aai-sync` result once and copies it per test.
- run-tests uses the shortest sleeps that still prove the reaper and timeout
  behavior.

## Scope
- In scope: the four hot spots above and re-seeding suite weights.
- Out of scope: nested suite runs (nested-suite-reruns-duplicate-sweep-time)
  and Windows CI (ci-windows-leg-waits-and-ps1-path-filter).

## Plan / Migration
1. No-NUL check: single-process implementation, behavior-equivalent output,
   pinned by the existing tests.
2. test_094: static detection of the dispatch shape plus a sampled execution.
3. sync-seed: shared cached sync fixture with per-test copies.
4. run-tests: shorten sleeps, keep the reaper assertions.
5. Re-seed `tests/skills/suite-weights.tsv`; then consider more shards.
- Rollback: per item.

## Verification
- hygiene-pack under about 60 s on CI; sync-seed and run-tests each roughly
  halved; measured on CI and with the local 8×4 sweep.
- The slowest full-mode CI leg is at most 1.25 times the mean leg, measured on
  a full-mode CI run after re-seeding suite weights. This bound moved here from
  nested-suite-reruns-duplicate-sweep-time (Spec-AC-12) by owner amendment on
  2026-10-09: CI run 37934068219 showed aai-hygiene-pack alone (308 s) flooring
  the slowest leg (shard walls 309, 210, 132, 133 s).
- The no-NUL check output is identical before and after on the live tree and
  on fixtures with a NUL byte.
- Every behavior the four tests proved is still proved (mutation of the
  contract still reddens the test).

## Constraints / Risks
- The cached sync fixture must not leak state between tests.
- Shorter sleeps must not make the reaper tests flaky under CI load.

## Notes
- Source: CI and test efficiency analysis 2026-10-09. Option B of the C, A, B
  sequence the owner approved: "Udělej jak doporučuješ". Ride after
  nested-suite-reruns-duplicate-sweep-time.
- Implementation mode (user choice): direct — owner accepted the
  recommendation (performance rework of existing tests, behavior pinned by the
  tests that already exist plus targeted regressions).
- Side finding: delta-stage3 writes logs to fixed `/tmp/aai-delta-stage3-*.log`
  paths that can collide across concurrent runs; fold in if cheap.
