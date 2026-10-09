---
id: ci-windows-leg-waits-and-ps1-path-filter
type: techdebt
number: 9
status: done
links:
  pr:
    - TBD
  commits:
    - e4bbe1861e7ce8310b8fad273ef3c8958f3d1530
---

# Tech Debt: the Windows ps1 leg waits 10 minutes on a 2-second timeout and runs for bash-only ledger edits

## Debt Summary
The `windows-5_1` job of `.github/workflows/ps1-quality.yml` finishes last on
86 of 166 PR pushes. Measured over 600 Actions runs (2026-09-28 to 2026-10-08),
all-checks wall per PR push is p50 12.9 min against 7.5 min for the required
checks. Two causes:

1. The two "Real-wrapper smoke" steps take 307 s and 306 s. That is 10 of the
   job's 12.4 min. A scenario that runs `aai-run-tests.ps1` with
   `AAI_TEST_TIMEOUT=2` around a `sleep 300` child still waits the full 300 s
   (one run: 23:55:49 to 00:00:51). This points to a real Windows defect: the
   wrapper's timeout may not kill or detach the child tree, so the timeout does
   not bound the run. The job also has no `timeout-minutes`.
2. The ps1-quality path filter includes `tests/skills/lib/**`. 65 of 117 PR
   runs (56%, about 1,014 Windows runner-minutes in 10 days) were triggered only
   by bash-only ledgers that PowerShell never reads: `prompt-diet-ledger.sh`
   (changed in 34 of 94 commits) and `cd-subshell-leak-baseline.tsv` (23 of 94).

## Root Cause
- The wrapper timeout test asserts the exit code, not the elapsed time, so a
  timeout that only fires after the child exits on its own stays green.
- The path filter was widened to the whole `tests/skills/lib/` directory when
  the first PowerShell-consumed helper landed there, and never narrowed as
  bash-only ledgers accumulated in the same directory.

## Current Cost / Risk
- About 5 min of extra waiting on most PR pushes (all-checks p50 12.9 min vs
  about 7.5 min without the leg on the critical path).
- About 16 Windows runner-minutes per push.
- Possible real defect: on native Windows the test wrapper may not enforce
  `AAI_TEST_TIMEOUT`, so a hung suite can run until the job limit, and the job
  has none.

## Target State
- A wrapper timeout on Windows ends the run within a bounded margin of
  `AAI_TEST_TIMEOUT` and reaps the child tree. The smoke steps take seconds.
- ps1-quality runs only when a file PowerShell actually reads changes.
- `windows-5_1` has an explicit `timeout-minutes`.

## Scope
- In scope: `.aai/scripts/aai-run-tests.ps1` timeout and child-tree reaping on
  native Windows (5.1 and pwsh 7), the ps1-quality smoke scenarios that cover
  it, the ps1-quality `paths:` filter, and `timeout-minutes` on `windows-5_1`.
- Out of scope: the bash wrapper, the skill-suite workflow, suite-level
  optimizations (separate intakes nested-suite-reruns-duplicate-sweep-time and
  slowest-suite-hot-spots).

## Plan / Migration
1. Reproduce on the Windows runner: time the timeout scenario and list the
   surviving processes after the wrapper returns.
2. If the wrapper does not enforce the timeout, fix it (kill the tree, return
   the timeout exit code) and assert elapsed time in the smoke scenario.
3. Narrow `paths:` from `tests/skills/lib/**` to the files PowerShell reads,
   for example `tests/skills/lib/*.ps1`, `tests/skills/lib/assert-payload.sh`
   and `tests/skills/lib/pipe-safe.sh`. Derive the exact list from the
   PowerShell sources, not from memory.
4. Add `timeout-minutes` to `windows-5_1`.
- Rollback: revert the filter change (a missed trigger only means a PowerShell
  regression is caught by the weekly canary or the next ps1 edit).

## Verification
- A Windows CI run of the timeout scenario finishes within `AAI_TEST_TIMEOUT`
  plus a small margin, and no child of the scenario survives the wrapper.
- `windows-5_1` loses its two 300 s smoke waits (each smoke step finishes in
  seconds) and its p50 stays at or below 10 min. Owner decision 2026-10-09
  re-baselined the earlier 2–3 min estimate: the Pester steps grew to about
  8 min independently of this scope and are addressed by
  slowest-suite-hot-spots.
- A PR that changes only `tests/skills/lib/prompt-diet-ledger.sh` does not
  trigger ps1-quality; a PR that changes a `.ps1` under `tests/skills/lib/` or
  a listed shared helper does.
- All-checks wall per PR push p50 falls toward about 7.5 min.

## Constraints / Risks
- The fix must keep PowerShell 5.1 and pwsh 7 parity and the existing
  degraded-mode contract on Git-Bash/MSYS.
- Narrowing the filter must not drop a file a PowerShell script or Pester test
  actually reads; derive the list from the sources and pin it with a test.
- No secrets are involved.

## Notes
- Source: CI and test efficiency analysis 2026-10-09 (600 runs, run ids and
  step timings in the analysis data). Option C of the C, A, B sequence the
  owner approved: "Udělej jak doporučuješ".
- Implementation mode (user choice): tdd — owner accepted the recommendation
  (behavioral fix in the test wrapper on two PowerShell engines plus CI wiring).
