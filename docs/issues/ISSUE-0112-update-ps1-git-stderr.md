---
id: update-ps1-git-stderr
type: issue
number: 112
status: done
links:
  pr: []
  commits: []
---

# aai-update.ps1 dies on git stderr under Windows PowerShell 5.1

## Summary
`.aai/scripts/aai-update.ps1` runs git with its output discarded (`git -C $Src fetch --depth 1 origin $Ref *> $null`, then checkout and pull) while `$ErrorActionPreference = "Stop"` is set at the top of the script. Under Windows PowerShell 5.1, redirecting a native command's stderr turns every stderr line into an ErrorRecord, and under `Stop` the first one ends the script. With a local `-Repo` checkout the update exits 1 and syncs nothing. The bash twin (`aai-update.sh:78-80`) runs the same three commands best-effort (`>/dev/null 2>&1 || true`), exits 0 and syncs. Closes follow-up `fu-parity-win-update-5-1-stderr` (P2, ref install-path-parity-harness).

## Type
bug

## Impact
- Consumer-visible: a Windows PowerShell 5.1 user who runs `/aai-update` (the updater picks `pwsh` when present, else `powershell.exe`) against a local checkout gets no update at all. git fetch, checkout and pull write to stderr even when they succeed, so no source checkout avoids it.
- The same pattern is used by the default path's clone attempts (`gh repo clone ... *> $null`, `git clone ... *> $null`; git clone always writes "Cloning into" to stderr) and the post-sync `git -C $Target status --short 2>$null`. These are the same class in the same file. They were not observed failing in CI, because the Windows clone test (TEST-009 in `tests/skills/aai-update.Tests.ps1`) is skipped on Windows and the parity harness only runs the local `-Repo` path.
- Severity/priority: P2 (as filed).

## Current Behavior
CI run 42972323735 (Windows PowerShell 5.1), parity scenario UP-01: `.aai/scripts/aai-update.ps1:72`, exit sh 0 / ps1 1, stderr `git : fatal: origin does not appear to be a git repository ... NativeCommandError`. The parity harness (`tests/skills/lib/install-parity.mjs`) works around it by running the ps1 update twin with `GIT_REDIRECT_STDERR=2>&1` on a PowerShell below 6 host and prints a NOTE saying so.

## Expected Behavior
- The ps1 twin behaves like the sh twin: the best-effort git calls never end the script because git wrote to stderr or exited nonzero, on Windows PowerShell 5.1 and on pwsh 7 (including with `$PSNativeCommandUseErrorActionPreference = $true` inherited from the caller). The clone cascade still decides success from the exit code.
- The harness workaround (env override, its NOTE and the node test that scopes it) is removed, so the `windows-parity` CI job proves the fix on 5.1.

## Steps to Reproduce
1. On Windows PowerShell 5.1, make a target directory and a local source checkout whose `origin` remote is missing (or any checkout: git fetch prints progress to stderr).
2. From the target, run `powershell -NoProfile -File <src>/.aai/scripts/aai-update.ps1 -Repo <src> -Ref main`.
3. Observe exit 1 and a NativeCommandError from the fetch line; nothing is synced.
4. Under pwsh 7.3+, the same exit 1 reproduces when the caller sets `$PSNativeCommandUseErrorActionPreference = $true` before invoking the script, since git exits nonzero.

## Verification
- New Pester regression in `tests/skills/aai-update.Tests.ps1` runs the updater under the engine hosting the test (powershell.exe on the 5.1 leg, pwsh on 7) against a local `-Repo` fixture whose git calls fail and write to stderr, and asserts exit 0 plus the sync marker. Under pwsh 7 it also forces `$PSNativeCommandUseErrorActionPreference = $true` so it is RED locally before the fix.
- `node --test tests/skills/lib/install-parity.test.mjs` passes with the workaround removed; `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-install-parity.sh` and the `aai-update` suite pass.
- CI: `ps1-quality.yml` `windows-parity` (5.1 and pwsh 7 legs) green with no `GIT_REDIRECT_STDERR` NOTE; `windows-5_1` full Pester suite green.

## Constraints / Risks
- `tests/skills/aai-update.Tests.ps1` TEST-006/TEST-007 pin literal clone/cleanup text in the script (`gh repo clone $Repo $SrcDir`, `$CloneUrl $SrcDir` twice, three `Remove-Item -Recurse -Force $SrcDir -ErrorAction SilentlyContinue`); the fix must keep those strings.
- The sync itself (`& $Sync -TargetRoot $Target`) runs in-process with its own `Stop`; native calls inside `aai-sync.ps1` are out of scope and are only recorded as follow-ups.
- SPEC-0284 (done, frozen) describes the workaround in its D-text; it stays as the historical record and is not edited.
- Secrets preflight: no secret referenced.

## Notes
- Implementation mode: autopilot (/aai-ship); Planning decides. human_time_minutes: null (autopilot default).
- Assumption: the ps1 twin keeps its current exit codes (2 refused, 3 fetch failure, 4 missing sync script); only the best-effort calls change.
