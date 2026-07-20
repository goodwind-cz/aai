---
id: reaper-deterministic-age-guard
number: 18
type: issue
status: done
links:
  pr:
    - 120
  commits:
    - b6df8347937b45e053653175e0a3f0ae8e918618
---

# Reaper age guard is a wall-clock race: make the fresh-sibling decision deterministic

## Summary
- `.aai/scripts/aai-reap-tests.sh` decides whether a matching process is a
  "fresh in-flight sibling" (spare) or an "old leaked survivor" (reap) by
  comparing its `ps` elapsed-time (`etime`) against a FIXED constant threshold
  `AAI_REAP_MIN_AGE_SECS` (Guard 3, lines 157-159). Because the threshold is a
  fixed constant rather than relative to when the step began, and `etime` has
  whole-second granularity, a genuinely fresh sibling can be sampled as "old
  enough" once the reaper's own overhead (two `ps axo` snapshots + a PPID-subtree
  walk) plus a loaded runner push the elapsed time past the constant. This makes
  `tests/skills/test-aai-run-tests.sh` TEST-006/TEST-015 intermittently red on
  Linux CI. Widening the margin (done in CHANGE-0043: 2s→5s) reduced but did not
  eliminate the flake — it has since blocked merges TWICE (PR #118 window, PR #119).

## Type
- bug

## Impact
- `aai-run-tests` is a REQUIRED CI check (branch protection on main). A flaky
  required check intermittently BLOCKS legitimate merges (worked around by
  re-running / owner override). Severity: medium — no product/runtime impact, but
  it erodes trust in the enforced gate and costs a ~6-min re-run each time.

## Current Behavior
- Guard 3: `age = etime_to_secs(etime); [ "$age" -ge "$MIN_AGE" ] || continue`.
  `MIN_AGE` is a fixed constant (default 0; the test sets 5). A fresh sibling
  spawned right before the reap has real age ~0s, but the reaper samples its
  `etime` AFTER its own variable overhead; on a slow runner `etime` can round up
  to ≥ MIN_AGE, so the fresh sibling is wrongly reaped ("reaper over-reached:
  killed a FRESH sibling younger than the step-start threshold").

## Expected Behavior
- The spare/reap decision is DETERMINISTIC: a process spawned at/after the step
  began is ALWAYS spared, and one that pre-existed the step is ALWAYS reaped,
  regardless of how long the reaper takes to run or how loaded the host is.

## Steps to Reproduce (if applicable)
1) Under load (or on a throttled CI runner), run
   `bash tests/skills/test-aai-run-tests.sh` TEST-006 repeatedly.
2) Intermittently: `FAIL ... reaper over-reached: killed a FRESH sibling <pid>
   younger than the step-start threshold`.

## Verification
- `tests/skills/test-aai-run-tests.sh` (TEST-006, TEST-015) passes DETERMINISTICALLY
  — including under artificially injected reaper delay / high load — with a small,
  bounded margin, not a widened-timeout hope.
- The reaper still correctly REAPS a genuine pre-step survivor and SPARES a genuine
  post-step sibling (both directions preserved — no assertion weakened).
- `./tests/skills/test-aai-run-tests.sh` exits 0 on macOS; the `skill-suite` CI job
  is green on Ubuntu across repeated runs (spot-check by re-running the CI job 2-3×).

## Constraints / Risks
- Candidate deterministic design (Planning to finalize): replace the FIXED
  `MIN_AGE` constant with a STEP-START EPOCH. Capture `date +%s` once when the
  step begins (passed to the reaper, e.g. `AAI_REAP_STEP_START_EPOCH`, with the
  `aai-run-tests.sh` wrapper capturing it at its own start). In the reaper,
  capture `SNAP_NOW` at the single `ps` snapshot instant; per process compute
  `start_epoch = SNAP_NOW - etime` and SPARE when
  `start_epoch >= STEP_START_EPOCH - GRACE` (small fixed GRACE, e.g. 1-2s, to
  absorb `etime`'s whole-second rounding). This is deterministic — `start_epoch`
  and `STEP_START_EPOCH` are both fixed, independent of reaper overhead — and
  avoids parsing `ps -o lstart=` into an epoch (locale/BSD-vs-GNU `date` minefield).
- SAFETY-CRITICAL: the reaper kills processes. The fix must NOT widen what gets
  killed (never reap a genuine fresh sibling; still reap genuine survivors).
  Fail-safe: if `STEP_START_EPOCH` is unset/invalid, fall back to the current
  `MIN_AGE` behavior (back-compat), never to "reap everything".
- Portability (per LEARNED 2026-07-19): BSD + GNU `ps etime` + `date +%s` only;
  no `ps -o lstart` epoch parsing, no `stat -f`-first, no `mktemp -t <bare>`.
  Keep bash + the PowerShell twin (`aai-reap-tests.ps1`) in parity if the .ps1
  has the same guard.
- The test itself must become deterministic: rather than spawning a "fresh" proc
  and hoping the sampled age stays under a constant, it should exercise the
  step-start-epoch contract directly (e.g. set `AAI_REAP_STEP_START_EPOCH` to a
  known value and assert spare/reap by construction, optionally injecting a
  reaper delay to prove overhead no longer flips the decision).
- No secret referenced — SECRETS PREFLIGHT skipped.

## Notes
- This is the residual risk RR (reaper timing-margin, mitigated not eliminated)
  recorded in SPEC-0062/SPEC-0063 validation and flagged in LEARNED 2026-07-19.
- Verification is CI-authoritative: the flake reproduces under Linux CI load; the
  macOS host rarely triggers it. Weave a CI re-run spot-check into validation.
