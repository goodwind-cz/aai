---
id: win-fallback-test028-red-on-bash-3
type: issue
number: 96
status: draft
links:
  pr: []
  commits: []
---

# aai-win-fallback TEST-028 is red on a host whose bash is older than 4

## Summary
- `tests/skills/test-aai-win-fallback.sh` TEST-028 fails on macOS with `FAIL python path: got []` and `wrapper exit 1`, on a clean `origin/main` too, so a local full sweep on macOS can never be all green.
- Root cause: the test's execution arm runs a suite that calls a Windows-style path (`C:\proj\.venv\Scripts\python.exe`), which only resolves through `command_not_found_handle` in `.aai/scripts/lib/git-bash-path.sh`. Bash supports that hook from 4.0 on. macOS ships `/bin/bash` 3.2.57, so the hook never fires there and the call fails as "command not found".
- The product is not affected: Git Bash on Windows is bash 5, and CI (Linux, bash 5) runs the arm green.

## Type
- bug

## Impact
- Every local full sweep on a macOS host with the system bash: one red suite (`aai-win-fallback`), which every ride has to explain away as "pre-existing, host-only" (rides for DEBT-0010 and DEBT-0011 both did).
- Severity: low (test-only). Priority: medium, because a permanently red suite trains the operator to ignore red.
- Tracked as follow-up `fu-win-fallback-test028-local-macos`.

## Current Behavior
- On bash 3.2, TEST-028's in-process path-translation asserts pass, then the execution arm runs the sentinel suite through the wrapper. The Windows path is not found (no `command_not_found_handle` support), the suite prints `FAIL python path: got []`, the wrapper exits 1, and TEST-028 fails the whole suite.

## Expected Behavior
- On a bash older than 4, TEST-028 still runs its in-process path-translation asserts, and reports the execution arm as a NAMED skip that states the reason (bash < 4 has no `command_not_found_handle`; Git Bash and CI are bash 5). This is the same pattern the suite already uses for its pwsh-absent named skips.
- On bash 4 or newer (CI, Git Bash, Homebrew bash), the execution arm runs exactly as today.
- The bash version is read from the interpreter that runs the sentinel suite (the one the wrapper invokes), not assumed from the test process.

## Steps to Reproduce (if applicable)
1) On macOS with only the system bash (3.2.57) on `PATH`, check out `origin/main`.
2) `env -u AAI_ROLE bash tests/skills/test-aai-win-fallback.sh`
3) Observe `FAIL: TEST-028: wrapper exit 1 (want 0, not 127)` and `FAIL python path: got []`.

## Verification
- `env -u AAI_ROLE bash tests/skills/test-aai-win-fallback.sh` on macOS bash 3.2 exits 0, and its output names the TEST-028 execution-arm skip with the bash version.
- The same suite under bash 4+ (for example `PATH=/opt/homebrew/bin:$PATH` when Homebrew bash is present, or CI) still runs the execution arm and prints `TEST-028 Windows Python path translated in-process and executed under Git Bash`.
- A mutation that removes the version guard turns the suite red again on bash 3.2. A mutation that skips the arm unconditionally is caught on bash 4+ because the pass line no longer appears.

## Constraints / Risks
- The skip must stay narrow: only the execution arm, only when the invoked bash is older than 4. The translation asserts must keep running everywhere, and a bash 4+ host must never skip.
- No product code change: `git-bash-path.sh` and the wrappers stay as they are.
- No secret referenced; secrets preflight skipped.

## Notes
- Found while closing DEBT-0011 (slowest-suite-hot-spots) on 2026-10-09: the failure reproduced on a clean `origin/main` worktree.
- Implementation mode: left to Planning (autopilot default, /aai-ship).
