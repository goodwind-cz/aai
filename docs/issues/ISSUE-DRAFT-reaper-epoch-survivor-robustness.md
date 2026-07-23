---
id: reaper-epoch-survivor-robustness
number: null
type: issue
status: draft
links:
  pr: []
  commits: []
---

# TEST-017 asserts an epoch-mode reap AT the reaper's documented ambiguity boundary, so it flakes under CI load

## Summary
- `tests/skills/test-aai-run-tests.sh` TEST-017 ("epoch mode reaps a genuine
  pre-step survivor regardless of MIN_AGE") intermittently fails on CI with
  `epoch mode failed to reap a genuine pre-step survivor <pid> (reaper output:
  reaped: 0)`. Observed on PR #129 (a diff that does not touch the reaper at all);
  the full local suite is 42/42 green on macOS, so it is CI-load-only.
- ROOT CAUSE — the test asserts INSIDE the reaper's documented resolution limit,
  not a reaper defect:
  - `.aai/scripts/aai-reap-tests.sh` reaps iff
    `start_epoch < STEP_START - GRACE`, with `GRACE=2` documented as
    "1s etime truncation + 1s snapshot sampling skew".
  - `start_epoch = SNAP_NOW - age`, where `age = etime_to_secs(etime)` is
    FLOOR-truncated to whole seconds — so the computed `start_epoch` can be up to
    ~1s LATER than the process's true start.
  - TEST-017 spawns the survivor, `sleep 3`, then captures `step_start`. A nominal
    3s gap must survive 1s of `start_epoch` truncation slop AND 1s of `date +%s`
    quantization on `STEP_START`, against a threshold that already subtracts
    GRACE=2. The inequality therefore lands EXACTLY on the boundary
    (`start_epoch < STEP_START - 2` with a 3s nominal gap), and whether it reaps
    depends on sub-second phase alignment. CI load shifts the phase → intermittent
    spare instead of reap.

## Type
- bug

## Impact
- `aai-run-tests` is a REQUIRED CI check (branch protection), so this
  intermittently BLOCKS merges on unrelated PRs, each costing a ~8-min re-run
  (hit on #129 this session). It also erodes trust in the epoch guard: the failure
  message reads like the "deterministic" epoch mode is broken, when in fact the
  test is sampling inside the contract's ambiguity band. Severity: medium — no
  product impact; wasted cycles + a misleading signal.

## Current Behavior
- TEST-017 gives the survivor a nominal 3-second head start over `STEP_START`,
  which equals `GRACE (2) + 1s truncation` — the minimum theoretically-reapable
  gap, with ZERO margin. Under load the observed outcome flips between reap and
  spare.

## Expected Behavior
- TEST-017 proves the epoch-mode property it is meant to prove (a genuine
  pre-step survivor is reaped regardless of a high legacy `MIN_AGE`) from a gap
  that is UNAMBIGUOUSLY outside the documented resolution limit, so the assertion
  is deterministic on any load. The property under test is unchanged; only the
  fixture's margin moves out of the boundary band.

## Steps to Reproduce (if applicable)
1) Under CI load (Ubuntu runner, full 42-suite run) execute
   `tests/skills/test-aai-run-tests.sh`; TEST-017 intermittently reports
   `reaped: 0` and fails. 2) Locally on an idle macOS host it passes consistently
   (42/42), which is why it presents as a phantom regression on unrelated PRs.

## Verification
- TEST-017's pre-step gap is widened to sit clearly outside `GRACE + truncation`
  (e.g. the survivor predates `STEP_START` by comfortably more than 3s), with an
  inline comment naming the arithmetic so the margin is not "tuned" away later.
- The test still proves the ORIGINAL property: `AAI_REAP_MIN_AGE_SECS=999`
  (legacy threshold that would SPARE) must not prevent the epoch-mode reap, and
  the reaper must report a non-zero reaped count.
- `bash tests/skills/test-aai-run-tests.sh` exits 0 on macOS, and the CI
  `skill-suite` job is green on Ubuntu across repeated runs (CI is the
  authoritative environment for this load-dependent flake).
- The PRODUCTION reaper `.aai/scripts/aai-reap-tests.sh` is UNCHANGED — including
  `GRACE=2`; this is a test-fixture margin fix, not a contract change.

## Constraints / Risks
- Do NOT "fix" this by raising `GRACE` or otherwise loosening the production
  reaper: GRACE is the documented truncation/skew budget, and widening it would
  make the reaper spare genuinely-leaked processes. The test must respect the
  contract's resolution limit, not the contract bend to the test.
- Do NOT simply retry/loop the assertion until it passes — that hides the boundary
  problem instead of removing it (same anti-pattern as widening a margin, which is
  what made the earlier TEST-018 fix incomplete).
- Keep the added wait SMALL — the suite already runs ~8 min on CI; buy margin with
  a few seconds, not tens.
- Linux-portable (LEARNED 2026-07-19): full `mktemp` templates, POSIX-safe, honor
  shebangs; the reaper is invoked via `sh` in adjacent tests.
- Companion obligations check (PLANNING step 3a): scope touches NO prompt-corpus
  file and adds NO new `.aai/**` file → no prompt-diet ledger true-up and no
  PROFILES.yaml classification required.
- No secret referenced — SECRETS PREFLIGHT skipped.

## Notes
- Third correction in this family; the pattern across all of them is the same:
  the reaper's real guarantees are quantized to whole seconds, so any test that
  asserts within ±1s of a threshold is flaky by construction. TEST-016 (spare a
  fresh sibling) is safe because it asserts far from the boundary; TEST-017 is the
  remaining one that asserts ON it.
