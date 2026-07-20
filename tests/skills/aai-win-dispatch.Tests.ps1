# Pester v5 tests for the Windows fallback dispatchers (SPEC-0046 / ISSUE-0009,
# TEST-001..006).
#
# Testability constraint: this host is macOS — there is no real WSL, no real
# Windows Git Bash, no real `taskkill`. Every probe/launch/kill primitive in
# both .ps1 files is a small, independently-named function so it can be
# overridden with `Mock` — the resolution/selection LOGIC (Spec-AC-01,
# Spec-AC-02, Spec-AC-04) and the argv/parameter shapes handed to the launch
# primitives (Spec-AC-03) are genuinely exercised here; the real-Windows
# process semantics of those primitives are explicitly OUT of scope for this
# suite (covered by the Manual verification protocol MV-1..MV-3 in the spec).
#
# Both dispatchers are written so that DOT-SOURCING them (`. $path`) defines
# all functions WITHOUT executing Main — `$MyInvocation.InvocationName -ne '.'`
# guards the bottom-of-file entry point. That is what lets this suite mock
# individual functions and call the rest directly.
#
# Run via: pwsh -NoProfile -Command "Invoke-Pester tests/skills/aai-win-dispatch.Tests.ps1 -Output Detailed"
# (tests/skills/test-ps1-quality.sh wraps this and skips if pwsh/Pester absent.)

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:RunDispatcher = Join-Path $RepoRoot '.aai/scripts/aai-run-tests.ps1'
    $script:ReapDispatcher = Join-Path $RepoRoot '.aai/scripts/aai-reap-tests.ps1'
}

Describe 'aai-run-tests.ps1' {

    BeforeEach {
        # Re-dot-source before every test so Mocks never leak between tests.
        . $script:RunDispatcher
    }

    It 'parses with no syntax errors' {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script:RunDispatcher, [ref]$null, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    Context 'TEST-001 (Spec-AC-01): usable WSL -> WSL branch selected, delegation argv correct' {
        It 'Resolve-Interpreter returns wsl when the WSL probe succeeds' {
            Mock Test-WslUsable { $true }
            $r = Resolve-Interpreter
            $r.Mode | Should -Be 'wsl'
        }

        It 'builds the correct wsl.exe delegation argv (env passthrough + script + command)' {
            $args = Get-WslDelegationArgs -Command @('sh', '-c', 'exit 0') `
                -ShScriptPath 'C:\repo\.aai\scripts\aai-run-tests.sh' -Timeout 300 `
                -WslPathResolver { param($p) '/mnt/c/repo/.aai/scripts/aai-run-tests.sh' }
            $args | Should -Be @('-e', 'env', 'AAI_TEST_TIMEOUT=300', '/mnt/c/repo/.aai/scripts/aai-run-tests.sh', 'sh', '-c', 'exit 0')
        }

        It 'Invoke-Dispatch calls the WSL launch path with the resolved argv when WSL is usable' {
            Mock Test-WslUsable { $true }
            Mock ConvertTo-WslPath { '/mnt/c/repo/.aai/scripts/aai-run-tests.sh' }
            $script:capturedArgs = $null
            Mock Invoke-WslProcess { $script:capturedArgs = $Arguments; return 0 }
            Mock Start-GitBashProcess { $null }
            $rc = Invoke-Dispatch -Command @('sh', '-c', 'exit 0')
            $rc | Should -Be 0
            $script:capturedArgs | Should -Be @('-e', 'env', 'AAI_TEST_TIMEOUT=300', '/mnt/c/repo/.aai/scripts/aai-run-tests.sh', 'sh', '-c', 'exit 0')
            Should -Invoke Invoke-WslProcess -Times 1 -Exactly
            Should -Invoke Start-GitBashProcess -Times 0 -Exactly
        }
    }

    Context 'TEST-002 (Spec-AC-01): WSL absent/unusable + Git Bash candidates -> first-hit-wins, shim excluded' {
        It 'Find-GitBash skips a WSL System32 shim and a non-existent candidate, returning the first REAL hit' {
            Mock Get-GitBashCandidates {
                @(
                    'C:\Windows\System32\bash.exe',
                    'C:\nonexistent\bash.exe',
                    'C:\Program Files\Git\bin\bash.exe',
                    'C:\second\bash.exe'
                )
            }
            Mock Test-Path {
                param($LiteralPath)
                # Simulate: the System32 shim "exists" (it really does on a WSL-enabled
                # Windows box) but must never be picked; the first non-shim REAL path wins.
                $LiteralPath -in @('C:\Windows\System32\bash.exe', 'C:\Program Files\Git\bin\bash.exe', 'C:\second\bash.exe')
            }
            $found = Find-GitBash
            $found | Should -Be 'C:\Program Files\Git\bin\bash.exe'
        }

        It 'Resolve-Interpreter falls through to gitbash when WSL is unusable' {
            Mock Test-WslUsable { $false }
            Mock Find-GitBash { 'C:\Program Files\Git\bin\bash.exe' }
            $r = Resolve-Interpreter
            $r.Mode | Should -Be 'gitbash'
            $r.BashPath | Should -Be 'C:\Program Files\Git\bin\bash.exe'
        }

        It 'wsl.exe present but no usable distro falls through to Git Bash, never hangs/errors raw' {
            Mock Test-WslPresent { $true }
            Mock Test-WslUsable { $false }   # present-but-unusable is the contract this probe encodes
            Mock Find-GitBash { 'C:\Program Files\Git\bin\bash.exe' }
            $r = Resolve-Interpreter
            $r.Mode | Should -Be 'gitbash'
        }
    }

    Context 'TEST-003 (Spec-AC-01): all probes negative -> error branch, never a partial launch' {
        It 'Resolve-Interpreter returns error when neither WSL nor Git Bash is usable' {
            Mock Test-WslUsable { $false }
            Mock Find-GitBash { $null }
            $r = Resolve-Interpreter
            $r.Mode | Should -Be 'error'
        }

        It 'Invoke-Dispatch never invokes a launch primitive on the error path' {
            Mock Test-WslUsable { $false }
            Mock Find-GitBash { $null }
            Mock Invoke-WslProcess { 0 }
            Mock Start-GitBashProcess { $null }
            Mock Write-EnvError { }
            $rc = Invoke-Dispatch -Command @('sh', '-c', 'exit 0')
            $rc | Should -Be 78
            Should -Invoke Invoke-WslProcess -Times 0 -Exactly
            Should -Invoke Start-GitBashProcess -Times 0 -Exactly
        }
    }

    Context 'TEST-004 (Spec-AC-02): real invocation on THIS host (no WSL, no Windows Git Bash) -> exit 78 + exactly one AAI-ENV-ERROR line' {
        It 'exits 78 with exactly one stderr line matching ^AAI-ENV-ERROR: naming both probed options' {
            $errFile = [System.IO.Path]::GetTempFileName()
            try {
                & pwsh -NoProfile -File $script:RunDispatcher sh -c 'exit 0' 2>$errFile 1>$null
                $code = $LASTEXITCODE
                $errLines = @(Get-Content $errFile -ErrorAction SilentlyContinue | Where-Object { $_ -match '^AAI-ENV-ERROR:' })
                $code | Should -Be 78
                $errLines.Count | Should -Be 1
                $errLines[0] | Should -Match 'AAI-ENV-ERROR: no usable POSIX interpreter'
                $errLines[0] | Should -Match 'WSL'
                $errLines[0] | Should -Match 'Git'
            } finally {
                Remove-Item $errFile -ErrorAction SilentlyContinue
            }
        }

        It 'usage error (no command given) is distinct from the env error and never exit 78' {
            & pwsh -NoProfile -File $script:RunDispatcher 2>$null 1>$null
            $LASTEXITCODE | Should -Not -Be 78
        }
    }

    Context 'TEST-005 (Spec-AC-03): Git-Bash run contract — passthrough, exit fidelity, timeout->124 + tree-kill' {
        # NB: this coercion check runs FIRST in the Context, before any
        # Start-GitBashProcess/Wait-ProcessWithTimeout/Stop-ProcessTree Mocks
        # are installed below — running it last (after three Mock/Should
        # -Invoke cycles against the same functions) trips a Pester v5 mock-
        # table caching quirk unrelated to this repo's code (reproduced in
        # isolation outside this file). Ordering first sidesteps it cleanly.
        It 'AAI_TEST_TIMEOUT coercion parity (matches the .sh default): <_.Raw> -> <_.Expected>' -ForEach @(
            @{ Raw = 'bogus'; Expected = 300 }
            @{ Raw = '0'; Expected = 300 }
            @{ Raw = '-5'; Expected = 300 }
            @{ Raw = ''; Expected = 300 }
            @{ Raw = $null; Expected = 300 }
            @{ Raw = '45'; Expected = 45 }
            @{ Raw = '99999999999'; Expected = 300 }
        ) {
            Get-EffectiveTimeout -Raw $Raw | Should -Be $Expected
        }

        It 'passes the wrapper script path, command args, and AAI_TEST_TIMEOUT to the launched process' {
            $script:startArgs = $null
            Mock Start-GitBashProcess {
                $script:startArgs = @{ BashPath = $BashPath; ScriptArgs = $ScriptArgs; Timeout = $Timeout }
                [PSCustomObject]@{ Id = 4242; ExitCode = 0 }
            }
            Mock Wait-ProcessWithTimeout { $true }
            $rc = Invoke-ViaGitBash -BashPath 'C:\Git\bin\bash.exe' -Command @('sh', '-c', 'exit 0') `
                -ShScriptPath 'C:\repo\.aai\scripts\aai-run-tests.sh' -Timeout 45
            $rc | Should -Be 0
            $script:startArgs.BashPath | Should -Be 'C:\Git\bin\bash.exe'
            $script:startArgs.ScriptArgs | Should -Be @('C:\repo\.aai\scripts\aai-run-tests.sh', 'sh', '-c', 'exit 0')
            $script:startArgs.Timeout | Should -Be 45
        }

        It 'NB-A: outer Git-Bash watchdog deadline = AAI_TEST_TIMEOUT + grace (never races the inner .sh reap-grace sleep)' {
            $script:outerTimeoutSeconds = $null
            Mock Start-GitBashProcess { [PSCustomObject]@{ Id = 4242; ExitCode = 0 } }
            Mock Wait-ProcessWithTimeout {
                $script:outerTimeoutSeconds = $TimeoutSeconds
                $true
            }
            $rc = Invoke-ViaGitBash -BashPath 'C:\Git\bin\bash.exe' -Command @('sh', '-c', 'exit 0') `
                -ShScriptPath 'C:\repo\.aai\scripts\aai-run-tests.sh' -Timeout 45
            $rc | Should -Be 0
            $script:outerTimeoutSeconds | Should -Be (45 + (Get-OuterWatchdogGraceSeconds))
        }

        It 'propagates the real (non-zero) child exit code on normal completion' {
            Mock Start-GitBashProcess { [PSCustomObject]@{ Id = 4242; ExitCode = 7 } }
            Mock Wait-ProcessWithTimeout { $true }
            $rc = Invoke-ViaGitBash -BashPath 'C:\Git\bin\bash.exe' -Command @('sh', '-c', 'exit 7') `
                -ShScriptPath 'C:\repo\.aai\scripts\aai-run-tests.sh' -Timeout 300
            $rc | Should -Be 7
        }

        It 'on timeout, kills the launched process TREE (taskkill /T /F semantics) and exits 124' {
            Mock Start-GitBashProcess { [PSCustomObject]@{ Id = 4242; ExitCode = $null } }
            Mock Wait-ProcessWithTimeout { $false }
            Mock Stop-ProcessTree { }
            $rc = Invoke-ViaGitBash -BashPath 'C:\Git\bin\bash.exe' -Command @('sh', '-c', 'sleep 300') `
                -ShScriptPath 'C:\repo\.aai\scripts\aai-run-tests.sh' -Timeout 2
            $rc | Should -Be 124
            Should -Invoke Stop-ProcessTree -Times 1 -Exactly -ParameterFilter { $ProcessId -eq 4242 }
        }
    }
}

Describe 'aai-reap-tests.ps1' {

    BeforeEach {
        . $script:ReapDispatcher
    }

    It 'parses with no syntax errors' {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script:ReapDispatcher, [ref]$null, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    Context 'TEST-006 (Spec-AC-04): mocked snapshot — other-workspace spared, young spared, old match killed as tree; prints reaped: N' {
        BeforeEach {
            $script:now = Get-Date '2026-07-17T12:00:00'
            $script:snapshot = @(
                # Old match: same workspace, vitest token, aged well past the threshold -> REAP.
                [PSCustomObject]@{ ProcessId = 100; CommandLine = 'node vitest run C:\ws\myproject\worker.js'; CreationDate = $script:now.AddSeconds(-120) }
                # Young match: same workspace, vitest token, younger than the threshold -> SPARE.
                [PSCustomObject]@{ ProcessId = 101; CommandLine = 'node vitest run C:\ws\myproject\worker.js'; CreationDate = $script:now.AddSeconds(-2) }
                # Other workspace: vitest token but a DIFFERENT workspace path -> SPARE.
                [PSCustomObject]@{ ProcessId = 102; CommandLine = 'node vitest run C:\ws\other-project\worker.js'; CreationDate = $script:now.AddSeconds(-120) }
                # No token at all -> SPARE (must never be a bare global kill).
                [PSCustomObject]@{ ProcessId = 103; CommandLine = 'C:\Windows\explorer.exe'; CreationDate = $script:now.AddSeconds(-120) }
            )
        }

        It 'Get-ReapCandidates keeps only the aged in-workspace match' {
            $candidates = Get-ReapCandidates -Snapshot $script:snapshot -Workspace 'C:\ws\myproject' `
                -MinAgeSeconds 30 -Now $script:now
            $candidates.Count | Should -Be 1
            $candidates[0].ProcessId | Should -Be 100
        }

        It 'Invoke-ReapNative kills only the aged in-workspace match and prints reaped: N' {
            Mock Get-ProcessSnapshot { $script:snapshot }
            Mock Get-Date { $script:now }
            Mock Stop-ProcessTree { }
            $out = Invoke-ReapNative -Workspace 'C:\ws\myproject' -MinAgeSeconds 30
            Should -Invoke Stop-ProcessTree -Times 1 -Exactly -ParameterFilter { $ProcessId -eq 100 }
            ($out -join "`n") | Should -Match 'reaped: 1'
        }

        It 'never issues a global kill: an unmatched sibling and a fresh sibling both survive untouched' {
            Mock Get-ProcessSnapshot { $script:snapshot }
            Mock Get-Date { $script:now }
            Mock Stop-ProcessTree { }
            Invoke-ReapNative -Workspace 'C:\ws\myproject' -MinAgeSeconds 30 | Out-Null
            Should -Invoke Stop-ProcessTree -Times 0 -Exactly -ParameterFilter { $ProcessId -eq 101 }
            Should -Invoke Stop-ProcessTree -Times 0 -Exactly -ParameterFilter { $ProcessId -eq 102 }
            Should -Invoke Stop-ProcessTree -Times 0 -Exactly -ParameterFilter { $ProcessId -eq 103 }
        }

        It 'prints reaped: 0 and kills nothing when no candidate matches' {
            Mock Get-ProcessSnapshot { @() }
            Mock Stop-ProcessTree { }
            $out = Invoke-ReapNative -Workspace 'C:\ws\myproject' -MinAgeSeconds 0
            ($out -join "`n") | Should -Match 'reaped: 0'
            Should -Invoke Stop-ProcessTree -Times 0 -Exactly
        }
    }

    Context 'StepStart (reaper-deterministic-age-guard, Spec-AC-05): contract parity with the .sh reaper''s epoch mode' {
        BeforeEach {
            $script:now = Get-Date '2026-07-17T12:00:00'
            $script:stepStart = $script:now.AddSeconds(-10)
            $script:snapshot = @(
                # Pre-step survivor: CreationDate well before (StepStart - Grace) -> REAP.
                [PSCustomObject]@{ ProcessId = 200; CommandLine = 'node vitest run C:\ws\myproject\worker.js'; CreationDate = $script:now.AddSeconds(-120) }
                # Post-step sibling: CreationDate at/after StepStart -> SPARE, even though its
                # age (2s) would exceed a legacy MinAgeSeconds of 0 — StepStart takes over.
                [PSCustomObject]@{ ProcessId = 201; CommandLine = 'node vitest run C:\ws\myproject\worker.js'; CreationDate = $script:now.AddSeconds(-2) }
                # Right at the boundary: CreationDate == StepStart - Grace -> SPARE (>= is spare,
                # mirrors the .sh reaper's strict `<` for reap).
                [PSCustomObject]@{ ProcessId = 202; CommandLine = 'node vitest run C:\ws\myproject\worker.js'; CreationDate = $script:stepStart.AddSeconds(-2) }
            )
        }

        It 'Get-ReapCandidates -StepStart spares CreationDate >= StepStart-Grace and reaps older, ignoring MinAgeSeconds' {
            $candidates = Get-ReapCandidates -Snapshot $script:snapshot -Workspace 'C:\ws\myproject' `
                -MinAgeSeconds 999 -Now $script:now -StepStart $script:stepStart -GraceSeconds 2
            $candidates.Count | Should -Be 1
            $candidates[0].ProcessId | Should -Be 200
        }

        It 'Get-ReapCandidates without -StepStart stays byte-identical to the legacy MinAgeSeconds path' {
            $legacy = Get-ReapCandidates -Snapshot $script:snapshot -Workspace 'C:\ws\myproject' -MinAgeSeconds 30 -Now $script:now
            # Legacy mode: age >= 30 -> only the ~120s-old process (200) qualifies; the ~2s
            # (201) and ~12s (202) siblings are both younger than 30s -> spared.
            $legacy.Count | Should -Be 1
            $legacy[0].ProcessId | Should -Be 200
        }

        It 'Invoke-ReapNative -StepStart reaps only the pre-step survivor' {
            Mock Get-ProcessSnapshot { $script:snapshot }
            Mock Get-Date { $script:now }
            Mock Stop-ProcessTree { }
            $out = Invoke-ReapNative -Workspace 'C:\ws\myproject' -MinAgeSeconds 999 -StepStart $script:stepStart -GraceSeconds 2
            Should -Invoke Stop-ProcessTree -Times 1 -Exactly -ParameterFilter { $ProcessId -eq 200 }
            Should -Invoke Stop-ProcessTree -Times 0 -Exactly -ParameterFilter { $ProcessId -eq 201 }
            Should -Invoke Stop-ProcessTree -Times 0 -Exactly -ParameterFilter { $ProcessId -eq 202 }
            ($out -join "`n") | Should -Match 'reaped: 1'
        }

        It 'Get-StepStartFromEpoch: valid positive integer <= now returns the local DateTime' {
            $nowEpoch = [DateTimeOffset]$script:now
            $raw = [string]([DateTimeOffset]$script:stepStart).ToUnixTimeSeconds()
            $result = Get-StepStartFromEpoch -Raw $raw -Now $script:now
            $result | Should -Not -BeNullOrEmpty
            [Math]::Abs(($result - $script:stepStart).TotalSeconds) | Should -BeLessThan 1
        }

        It 'Get-StepStartFromEpoch: unset/empty/non-integer/negative/zero/future all fail safe to $null (never global)' {
            $future = ([DateTimeOffset]$script:now).ToUnixTimeSeconds() + 100000
            @($null, '', 'abc', '-5', '0', $future) | ForEach-Object {
                Get-StepStartFromEpoch -Raw $_ -Now $script:now | Should -BeNullOrEmpty
            }
        }

        It 'Invoke-ReapDispatch fail-safe: an invalid AAI_REAP_STEP_START_EPOCH falls back to legacy AAI_REAP_MIN_AGE_SECS (never a global kill)' {
            Mock Get-ProcessSnapshot { $script:snapshot }
            Mock Get-Date { $script:now }
            Mock Stop-ProcessTree { }
            Mock Resolve-Interpreter { @{ Mode = 'error' } }
            $env:AAI_REAP_WORKSPACE = 'C:\ws\myproject'
            $env:AAI_REAP_MIN_AGE_SECS = '30'
            $env:AAI_REAP_STEP_START_EPOCH = 'not-an-epoch'
            try {
                Invoke-ReapDispatch | Out-Null
            } finally {
                Remove-Item Env:\AAI_REAP_WORKSPACE -ErrorAction SilentlyContinue
                Remove-Item Env:\AAI_REAP_MIN_AGE_SECS -ErrorAction SilentlyContinue
                Remove-Item Env:\AAI_REAP_STEP_START_EPOCH -ErrorAction SilentlyContinue
            }
            # Legacy MinAgeSeconds=30 path: only the ~120s-old process (200) qualifies.
            Should -Invoke Stop-ProcessTree -Times 1 -Exactly -ParameterFilter { $ProcessId -eq 200 }
            Should -Invoke Stop-ProcessTree -Times 0 -Exactly -ParameterFilter { $ProcessId -eq 201 }
            Should -Invoke Stop-ProcessTree -Times 0 -Exactly -ParameterFilter { $ProcessId -eq 202 }
        }

        It 'Get-ReapWslDelegationArgs forwards AAI_REAP_STEP_START_EPOCH/AAI_REAP_GRACE_SECS only when StepStartEpoch is supplied' {
            $withStepStart = Get-ReapWslDelegationArgs -ShScriptPath 'C:\repo\.aai\scripts\aai-reap-tests.sh' `
                -Workspace 'C:\ws\myproject' -MinAgeSeconds 0 -StepStartEpoch '1750000000' -GraceSeconds '2' `
                -WslPathResolver { param($p) '/mnt/c/repo/.aai/scripts/aai-reap-tests.sh' }
            $withStepStart | Should -Be @('-e', 'env', 'AAI_REAP_WORKSPACE=C:\ws\myproject', 'AAI_REAP_MIN_AGE_SECS=0', `
                'AAI_REAP_STEP_START_EPOCH=1750000000', 'AAI_REAP_GRACE_SECS=2', '/mnt/c/repo/.aai/scripts/aai-reap-tests.sh')

            $withoutStepStart = Get-ReapWslDelegationArgs -ShScriptPath 'C:\repo\.aai\scripts\aai-reap-tests.sh' `
                -Workspace 'C:\ws\myproject' -MinAgeSeconds 0 `
                -WslPathResolver { param($p) '/mnt/c/repo/.aai/scripts/aai-reap-tests.sh' }
            $withoutStepStart | Should -Be @('-e', 'env', 'AAI_REAP_WORKSPACE=C:\ws\myproject', 'AAI_REAP_MIN_AGE_SECS=0', '/mnt/c/repo/.aai/scripts/aai-reap-tests.sh')
        }
    }

    Context 'NB-C: WSL-delegated reap forwards AAI_REAP_WORKSPACE/AAI_REAP_MIN_AGE_SECS and prints a single summary line' {
        It 'Get-ReapWslDelegationArgs builds the correct wsl.exe delegation argv (env passthrough for BOTH overrides + script)' {
            $wslArgs = Get-ReapWslDelegationArgs -ShScriptPath 'C:\repo\.aai\scripts\aai-reap-tests.sh' `
                -Workspace 'C:\ws\myproject' -MinAgeSeconds 30 `
                -WslPathResolver { param($p) '/mnt/c/repo/.aai/scripts/aai-reap-tests.sh' }
            $wslArgs | Should -Be @('-e', 'env', 'AAI_REAP_WORKSPACE=C:\ws\myproject', 'AAI_REAP_MIN_AGE_SECS=30', '/mnt/c/repo/.aai/scripts/aai-reap-tests.sh')
        }

        It 'Invoke-ReapDispatch forwards the resolved workspace and min-age into the WSL delegation call' {
            Mock Test-WslUsable { $true }
            $script:capturedWorkspace = $null
            $script:capturedMinAge = $null
            Mock Invoke-ReapViaWsl {
                $script:capturedWorkspace = $Workspace
                $script:capturedMinAge = $MinAgeSeconds
                'reaped: 2'
            }
            Mock Invoke-ReapNative { 0 }
            $env:AAI_REAP_WORKSPACE = 'C:\ws\myproject'
            $env:AAI_REAP_MIN_AGE_SECS = '30'
            try {
                Invoke-ReapDispatch | Out-Null
            } finally {
                Remove-Item Env:\AAI_REAP_WORKSPACE -ErrorAction SilentlyContinue
                Remove-Item Env:\AAI_REAP_MIN_AGE_SECS -ErrorAction SilentlyContinue
            }
            $script:capturedWorkspace | Should -Be 'C:\ws\myproject'
            $script:capturedMinAge | Should -Be 30
        }

        It 'in WSL mode, the delegate summary is authoritative: the native pass never prints its own reaped: N line' {
            Mock Test-WslUsable { $true }
            Mock Invoke-ReapViaWsl { 'reaped: 2' }
            $script:nativeCalled = $false
            Mock Invoke-ReapNative { $script:nativeCalled = $true; 'reaped: 5' }
            $out = Invoke-ReapDispatch *>&1 | Out-String
            $script:nativeCalled | Should -Be $true
            ([regex]::Matches($out, 'reaped: \d+')).Count | Should -Be 1
            $out | Should -Match 'reaped: 2'
        }

        It 'in native-only mode (WSL unusable), the native pass IS the summary of record and prints exactly one line' {
            Mock Test-WslUsable { $false }
            Mock Find-GitBash { 'C:\Program Files\Git\bin\bash.exe' }
            Mock Invoke-ReapViaWsl { 'reaped: 99' }
            Mock Invoke-ReapNative { 'reaped: 5'; return 5 }
            $out = Invoke-ReapDispatch *>&1 | Out-String
            Should -Invoke Invoke-ReapViaWsl -Times 0 -Exactly
            ([regex]::Matches($out, 'reaped: \d+')).Count | Should -Be 1
            $out | Should -Match 'reaped: 5'
        }
    }
}
