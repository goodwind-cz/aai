---
id: prompts-invoke-wsl-bash-on-windows
type: issue
number: null
status: draft
links:
  pr: []
  commits: []
---

# Issue — Skill prompts tell Windows agents to invoke bash, which hits a blocked WSL shim

## Summary
- `SKILL_TDD.prompt.md`, `SKILL_VERIFY.prompt.md`, and sibling skill prompts recommend running tests as `bash .aai/scripts/aai-run-tests.sh <command>`.
- On Windows that `bash` often resolves to the WSL shim. When WSL is installed but CreateInstance is denied by policy, the command dies before any test runs (`Access is denied` / `Bash/Service/CreateInstance/E_ACCESSDENIED`), sometimes with NUL bytes in the error text.
- The working entry is the PowerShell wrapper `.aai/scripts/aai-run-tests.ps1`, which already degrades to Git Bash. AGENTS.md already states both platform literals; the skill prompts do not.

## Type
- bug

## Impact
- Who/what is affected: Windows contributors and agents following skill prompts (TDD, Verify, Loop, Validation, and related skills) on a machine where WSL exists but cannot start.
- Severity/priority: high for Windows downstream projects — false infrastructure failure is indistinguishable from a test failure, and the agent then debugs application code that never ran.

## Current Behavior
- Skill prompts instruct `bash .aai/scripts/aai-run-tests.sh <cmd>`.
- CHANGE-0139 / `tests/skills/test-aai-win-fallback.sh` TEST-024 pins that POSIX shape in six prompts plus `DYNAMIC_SKILLS.md` and forbids a bare `.aai/scripts/aai-run-tests.sh` mention after stripping the bash-prefixed literal.
- `SKILL_TDD.prompt.md` is not in that TEST-024 pin list and still recommends the bash form.
- Observed on Windows (PowerShell, Git Bash present, WSL present but blocked, `core.autocrlf=true`):
  - Direct `bash .aai/scripts/aai-run-tests.sh ...` -> WSL `E_ACCESSDENIED` before tests start.
  - `& '.aai/scripts/aai-run-tests.ps1' 'venv/Scripts/python.exe' '-m' 'pytest' ...` -> `AAI-BRANCH: Git Bash`, tests pass.

## Expected Behavior
- On Windows, skill prompts never recommend invoking `bash`, `bash.exe`, `sh`, or `wsl` for test runs.
- Agents are pointed at the AGENTS.md canonical pair: Windows `powershell -NoProfile -File .aai/scripts/aai-run-tests.ps1 <command...>`, POSIX `bash .aai/scripts/aai-run-tests.sh <command...>`.
- A WSL-present-but-`E_ACCESSDENIED` machine with Git Bash available is a supported, tested path (the `.ps1` wrapper already takes it).
- WSL error text is readable UTF-8 without embedded NUL bytes.

## Steps to Reproduce (if applicable)
1. On Windows, with WSL installed but `wsl` / `bash` CreateInstance denied by policy, and Git Bash available.
2. Follow `SKILL_TDD.prompt.md` or `SKILL_VERIFY.prompt.md` and run `bash .aai/scripts/aai-run-tests.sh <any test command>`.
3. Observe `Access is denied` / `E_ACCESSDENIED` and no test result.
4. Run the same command through `.aai/scripts/aai-run-tests.ps1` and observe Git Bash degradation and a real test result.

## Verification
- Prompt corpus (at least TDD, Verify, Loop, Validation, Test-Skills, Bootstrap, Deslop) names the Windows `.ps1` literal or defers to the AGENTS.md pair; it does not tell a Windows agent to start with `bash`.
- A regression test covers: WSL present, `E_ACCESSDENIED` on CreateInstance, Git Bash available -> wrapper uses Git Bash and returns the wrapped command's exit code.
- `tests/skills/test-aai-win-fallback.sh` stays green after the prompt-contract update (TEST-024 and related pins must be revised with the contract, not silently broken).
- WSL denial output captured by the wrapper is NUL-free UTF-8.

## Constraints / Risks
- Known risks or constraints: CHANGE-0139 TEST-024 currently requires the bash-prefixed POSIX literal in the prompt corpus and treats a surviving bare `.aai/scripts/aai-run-tests.sh` as a failure. Fixing Windows guidance without updating that pin will redden the fallback suite. ISSUE-0009 and CHANGE-0133 already shipped the wrapper fallback itself; this issue is the remaining prompt-layer drift, not a re-implementation of the wrapper. AGENTS.md already carries both literals and the prohibition "Never invoke bash.exe, sh, or wsl directly for test runs".
- Secrets preflight results (if any secret referenced): none — no local secret is referenced.

## Notes
- Source: local Windows usage report 2026-09-24 (`internal/windows-usage-report.md` in the project store). Not previously filed upstream.
- Related done work that does **not** close this: ISSUE-0009 (`test-wrapper-windows-fallback`), CHANGE-0133 (`ps1-wrapper-path-dup`), CHANGE-0139 canonical invocation contract.
- Assumption: Git Bash is the supported Windows fallback when WSL cannot start; native cmd.exe-only environments remain out of scope unless Planning finds otherwise.
