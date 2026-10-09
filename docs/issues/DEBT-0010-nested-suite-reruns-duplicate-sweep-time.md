---
id: nested-suite-reruns-duplicate-sweep-time
type: techdebt
number: 10
status: done
links:
  pr:
    - 443
  commits:
    - e2e11cf0757c476aa0e85ff4156e30bb2f618cf9
---

# Tech Debt: suites re-run other suites, so a third of the sweep is duplicate work

## Debt Summary
28 suites (54 test functions) run other whole suites to prove a "companion
suite stays green". This costs about 1,350–1,600 s, or 32–38% of the
4,156 s full-sweep CPU. In full mode every companion also runs on its own, so
the nested run is pure duplication.

The worst case sets the critical path of every full-mode CI run.
`aai-learned-append` takes 397 s on CI. Measured locally, its TEST-015/016/017
take 403 of 398 s re-running `layer-profiles`, `prompt-diet`,
`friction-wiring` and `hygiene-pack`; its own 15 tests take under 1 s.
Further cases: `delta-stage3` TEST-007 (about 223 s re-running stage1, stage2,
spec-lint and docs-audit), `repo-tripwire` (133 of 146 s, including a nested
run of itself), `ceremony-levels` (63 of 66 s), `sync-seed` TEST-781 (100 s),
`doctor` TEST-031 (69 s). The full `layer-profiles` suite is re-run inside
8 other suites.

## Root Cause
- When a change touched a file another suite pins, the cheapest way to keep
  that suite green in selected mode was to call it from the changed suite.
  Selected mode had no other way to say "when X changes, also run Y".

## Current Cost / Risk
- About a third of sweep CPU and the full-mode critical path (the leg holding
  `aai-learned-append` takes p50 7.1 min against 3.7–5.5 min for the others).
- Local sweeps are slower by the same share.
- Nested runs multiply flake exposure: one flaky companion fails several
  suites at once.

## Target State
- `tests/skills/suite-map.yaml` declares companion suites (for example a
  `companions:` list per row) and `select-suites.mjs` selects them together
  with the suite that names them, so selected-mode coverage is kept without
  nesting.
- No suite runs another whole suite. A hygiene check refuses a new nested
  suite run.

## Scope
- In scope: the companion declaration and its selection, removal of the
  nested runs in all 28 suites, the hygiene ratchet, re-seeding
  `tests/skills/suite-weights.tsv`, and the frozen-spec amendments for the
  Test Plan rows these functions back.
- Out of scope: Windows CI (ci-windows-leg-waits-and-ps1-path-filter) and
  single-suite hot spots (slowest-suite-hot-spots).

## Plan / Migration
1. Add the companion field and selection, with a test that a change mapped to
   a suite also selects its companions.
2. Remove the nested runs, worst first: learned-append TEST-015/016/017,
   delta-stage3 TEST-007, repo-tripwire, sync-seed TEST-781, doctor TEST-031,
   ceremony-levels, then the rest. Each removed nested run becomes a
   companion entry.
3. Add the hygiene ratchet, re-seed suite weights, re-check shard balance.
- Rollback: per suite; restoring one nested call is local.

## Verification
- `aai-learned-append` runs in under 10 s; no full-mode leg is held by it.
- Full-sweep CPU drops by about a third (measured with the same local 8×4
  sweep and on CI).
- For every removed nested run, a change to the companion's mapped paths
  selects both suites in selected mode (test pinned).
- The hygiene ratchet fails on a newly added nested suite run.

## Constraints / Risks
- Many of these functions back Test Plan rows in frozen specs; removing them
  needs batched measurement or contract amendments and possibly owner
  sign-off.
- Mutation records that point at the removed functions must be re-pointed or
  retired honestly.
- Selected-mode coverage must not shrink: the companion selection is the
  compensating control.

## Notes
- Source: CI and test efficiency analysis 2026-10-09. Option A of the C, A, B
  sequence the owner approved: "Udělej jak doporučuješ". Ride after
  ci-windows-leg-waits-and-ps1-path-filter.
- Implementation mode (user choice): tdd — owner accepted the recommendation
  (selector behavior change plus a cross-suite refactor).
