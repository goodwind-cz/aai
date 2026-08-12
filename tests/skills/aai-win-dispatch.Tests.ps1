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
#
# CHANGE-0134 Spec-AC-02: dot-sourced at FILE/DISCOVERY scope (plain top-level
# script code, NOT inside BeforeAll) so the handful of genuinely
# Windows-fragile `It`s below can reference $script:SkipOnWindows in their own
# `-Skip:` parameter — see tests/skills/lib/pester-host-skip.ps1 for why a
# BeforeAll-scoped variable would silently fail to skip here.
. (Join-Path $PSScriptRoot 'lib/pester-host-skip.ps1')
$script:SkipOnWindows = Test-IsWindowsHostFor -Edition $PSVersionTable.PSEdition -IsWindowsFlag $IsWindows

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:RunDispatcher = Join-Path $RepoRoot '.aai/scripts/aai-run-tests.ps1'
    $script:ReapDispatcher = Join-Path $RepoRoot '.aai/scripts/aai-reap-tests.ps1'
    $script:ReleaseScript = Join-Path $RepoRoot '.aai/scripts/aai-release.ps1'
    $script:SkipHelperPath = Join-Path $PSScriptRoot 'lib/pester-host-skip.ps1'
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

    Context 'CHANGE-0134 TEST-003 (Spec-AC-02): Test-IsWindowsHostFor never silently fails to skip on Windows PowerShell 5.1, never over-skips on POSIX' {
        # Real child-process invocations (not a direct in-process call): Pester
        # v5 only runs top-level (non-block) script code during DISCOVERY, so
        # the file-scope dot-source above (needed there so $script:SkipOnWindows
        # is correct for -Skip: evaluation) does not carry the function forward
        # into Run phase. Spawning a fresh pwsh per case keeps the helper
        # dot-sourced in EXACTLY one place in this file (file/discovery scope,
        # never inside a BeforeAll) -- the shape TEST-004 below pins.
        It 'edition <_.Edition>, IsWindowsFlag <_.FlagLiteral> -> <_.Expected>' -ForEach @(
            @{ Edition = 'Desktop'; FlagLiteral = '$null'; Expected = $true }
            @{ Edition = 'Core'; FlagLiteral = '$true'; Expected = $true }
            @{ Edition = 'Core'; FlagLiteral = '$false'; Expected = $false }
            @{ Edition = 'Desktop'; FlagLiteral = '$false'; Expected = $true }
        ) {
            $cmd = ". '$script:SkipHelperPath'; Test-IsWindowsHostFor -Edition '$Edition' -IsWindowsFlag $FlagLiteral"
            $out = (& pwsh -NoProfile -Command $cmd | Select-Object -Last 1).Trim()
            $out | Should -Be ([string]$Expected)
        }
    }

    Context 'TEST-001 (Spec-AC-01): usable WSL -> WSL branch selected, delegation argv correct' {
        It 'Resolve-Interpreter returns wsl when the WSL probe succeeds' {
            Mock Test-WslUsable { $true }
            $r = Resolve-Interpreter
            $r.Mode | Should -Be 'wsl'
        }

        It 'builds the correct wsl.exe delegation argv (env passthrough + script + command)' {
            $argv = Get-WslDelegationArgs -Command @('sh', '-c', 'exit 0') `
                -ShScriptPath 'C:\repo\.aai\scripts\aai-run-tests.sh' -Timeout 300 `
                -WslPathResolver { param($p) '/mnt/c/repo/.aai/scripts/aai-run-tests.sh' }
            $argv | Should -Be @('-e', 'env', 'AAI_TEST_TIMEOUT=300', '/mnt/c/repo/.aai/scripts/aai-run-tests.sh', 'sh', '-c', 'exit 0')
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

    Context 'TEST-010 (field fix, PR #247 run 31603532721): Test-WslUsable is a REAL functional probe, not a bare present-check' {
        It 'wsl.exe present, ZERO installed distributions (stub prints the message and exits 0) -> NOT usable' {
            # The exact field defect: windows-latest wsl.exe with no installed
            # distro prints "Windows Subsystem for Linux has no installed
            # distributions." and exits 0 -- indistinguishable from success
            # under a bare ExitCode -eq 0 check.
            Mock Test-WslPresent { $true }
            Mock Start-WslProbeProcess { [PSCustomObject]@{ Id = 8001; ExitCode = 0 } }
            Mock Wait-ProcessWithTimeout { $true }
            Test-WslUsable | Should -Be $false
        }

        It 'wsl.exe present, real distro answers the sentinel exit code -> usable' {
            Mock Test-WslPresent { $true }
            Mock Start-WslProbeProcess { [PSCustomObject]@{ Id = 8002; ExitCode = 42 } }
            Mock Wait-ProcessWithTimeout { $true }
            Test-WslUsable | Should -Be $true
        }

        It 'wsl.exe present, distro answers a NON-sentinel exit code -> NOT usable' {
            Mock Test-WslPresent { $true }
            Mock Start-WslProbeProcess { [PSCustomObject]@{ Id = 8003; ExitCode = 1 } }
            Mock Wait-ProcessWithTimeout { $true }
            Test-WslUsable | Should -Be $false
        }

        It 'wsl.exe absent -> NOT usable, probe process never spawned' {
            Mock Test-WslPresent { $false }
            Mock Start-WslProbeProcess { [PSCustomObject]@{ Id = 8004; ExitCode = 42 } }
            Test-WslUsable | Should -Be $false
            Should -Invoke Start-WslProbeProcess -Times 0 -Exactly
        }

        It 'probe hangs past the watchdog -> NOT usable, hung probe process killed (never stalls the caller)' {
            Mock Test-WslPresent { $true }
            Mock Start-WslProbeProcess { [PSCustomObject]@{ Id = 8005; ExitCode = $null } }
            Mock Wait-ProcessWithTimeout { $false }
            Mock Stop-Process { }
            Test-WslUsable | Should -Be $false
            Should -Invoke Stop-Process -Times 1 -Exactly -ParameterFilter { $Id -eq 8005 }
        }

        It 'probe runs the sentinel command THROUGH a distro (-e sh -c), never a bare presence check' {
            Mock Test-WslPresent { $true }
            $script:capturedProbeArgs = $null
            Mock Start-WslProbeProcess {
                $script:capturedProbeArgs = $ArgumentList
                [PSCustomObject]@{ Id = 8006; ExitCode = 42 }
            }
            Mock Wait-ProcessWithTimeout { $true }
            Test-WslUsable | Should -Be $true
            $script:capturedProbeArgs | Should -Be @('-e', 'sh', '-c', 'exit 42')
        }

        It 'H1 (field defect, PR #247 run 31606986703): Start-WslProbeProcess redirects BOTH stdout and stderr, never inherits the caller''s streams' {
            # The zero-distro windows-latest field defect: wsl.exe prints its
            # UTF-16LE "no installed distributions" message and exits 0. With
            # -NoNewWindow and NO redirection, that message inherits whatever
            # the CALLER's own stdout/stderr are pointed at (a harness
            # capturing this wrapper's own stdout to a file, in the real
            # smoke) -- a UTF-16LE BOM at the start of that captured stream
            # flips Get-Content's encoding auto-detection for the WHOLE file,
            # corrupting every ASCII/UTF-8 byte after it, including a real
            # success marker written later by the Git-Bash branch. This is a
            # static source-contract check (real wsl.exe is not available on
            # any CI host this suite runs on) pinning that the fix -- both
            # streams redirected to real files, never $null/NUL -- stays in
            # place.
            $content = Get-Content -Raw $script:RunDispatcher
            if ($content -match '(?s)function Start-WslProbeProcess\s*\{(.*?)\n\}') {
                $body = $Matches[1]
            } else {
                $body = ''
            }
            $body | Should -Match '-RedirectStandardOutput\s+\$outFile'
            $body | Should -Match '-RedirectStandardError\s+\$errFile'
            $body | Should -Not -Match "-RedirectStandardOutput\s+(\`$null|'NUL'|""NUL"")"
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
        It 'exits 78 with exactly one stderr line matching ^AAI-ENV-ERROR: naming both probed options (PosixOnly: windows-latest always has a real Git Bash, so the dispatcher resolves it and runs the command instead of erroring)' -Skip:$script:SkipOnWindows {
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

    # ---- CHANGE-0133 / SPEC-0120-spec-ps1-wrapper-path-dup (TEST-001..009) ----
    # Environment canonicalization before every spawn, explicit 125 infra exit
    # code, no fake 124. NOTE: the "TEST-NNN" labels below are this spec's OWN
    # Test Plan ids, scoped to SPEC-0120-spec-ps1-wrapper-path-dup — they are
    # independent of (and numerically overlap) the SPEC-0046 TEST-001..006
    # labels used above in this same Describe block for a different spec.

    Context 'CHANGE-0133 TEST-001 (Spec-AC-01): PATH collision group collapses to one literal Path key, ordinal-ordered union, dedup' {
        It 'Path + PATH + path -> exactly one key "Path", ordinal-key-ordered union with duplicate segments dropped; OrdinalIgnoreCase dictionary build does not throw' {
            # CHANGE-0134 Spec-AC-02: made PORTABLE, not skipped -- this is the
            # one arm of this suite where the logic under test (path-segment
            # splitting/joining) is genuinely engine-relevant, so skipping it
            # on Windows would forfeit real Windows coverage of the exact
            # defect class this scope exists to catch. The pre-existing
            # fixture hardcoded ':' as the segment separator while the
            # assertion joined with [IO.Path]::PathSeparator -- correct only
            # on POSIX (':'), silently wrong under Windows (';'). Both the
            # fixture values and the expected value are now built with the
            # SAME [IO.Path]::PathSeparator, so the test asserts identically
            # on every platform.
            $sep = [IO.Path]::PathSeparator
            $envd = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
            $envd.Add('Path', "/usr/bin${sep}/shared")
            $envd.Add('PATH', "/bin${sep}/shared")
            $envd.Add('path', '/opt/bin')
            $map = Get-CanonicalEnvironmentMap -Environment $envd
            @($map.Keys) | Should -Be @('Path')
            # Ordinal member order: 'PATH' < 'Path' < 'path' (uppercase sorts
            # before lowercase) -> PATH's segments first, then Path's ('/shared'
            # already seen, dropped), then path's.
            $expected = @('/bin', '/shared', '/usr/bin', '/opt/bin') -join $sep
            $map['Path'] | Should -Be $expected
            {
                $d = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
                foreach ($k in $map.Keys) { $d.Add([string]$k, [string]$map[$k]) }
            } | Should -Not -Throw
        }
    }

    Context 'CHANGE-0133 TEST-002 (Spec-AC-01): non-PATH group -> ordinal-first key+value only, no-op on clean input, idempotent' {
        It 'Temp/TEMP collapses to the ordinal-first key with that key''s value only (no concatenation)' {
            $envd = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
            $envd.Add('TEMP', '/private/tmp')
            $envd.Add('Temp', '/other/tmp')
            $map = Get-CanonicalEnvironmentMap -Environment $envd
            @($map.Keys) | Should -Be @('TEMP')
            $map['TEMP'] | Should -Be '/private/tmp'
        }

        It 'identical-value duplicate casings collapse to a single entry' {
            $envd = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
            $envd.Add('FOO', 'same-value')
            $envd.Add('foo', 'same-value')
            $map = Get-CanonicalEnvironmentMap -Environment $envd
            @($map.Keys).Count | Should -Be 1
            $map['FOO'] | Should -Be 'same-value'
        }

        It 'a collision-free map is returned unchanged' {
            $envd = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
            $envd.Add('ALPHA', '1')
            $envd.Add('BETA', '2')
            $map = Get-CanonicalEnvironmentMap -Environment $envd
            @($map.Keys) | Should -Be @('ALPHA', 'BETA')
            $map['ALPHA'] | Should -Be '1'
            $map['BETA'] | Should -Be '2'
        }

        It 'normalizing the output a second time yields an identical map (idempotent)' {
            $envd = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
            $envd.Add('Path', '/a:/b')
            $envd.Add('PATH', '/b:/c')
            $envd.Add('Temp', '/t1')
            $envd.Add('TEMP', '/t2')
            $once = Get-CanonicalEnvironmentMap -Environment $envd
            $twice = Get-CanonicalEnvironmentMap -Environment $once
            @($twice.Keys) | Should -Be @($once.Keys)
            foreach ($k in $once.Keys) { $twice[$k] | Should -Be $once[$k] }
        }
    }

    Context 'CHANGE-0133 TEST-003 (Spec-AC-02, SEAM-1): real dual-casing environment -- CONTROL throws, TREATMENT does not, one Path survives with both directories' {
        It 'child pwsh: CONTROL arm (OrdinalIgnoreCase dictionary over the live dup env) THROWS; TREATMENT arm (after Set-CanonicalProcessEnvironment) does NOT throw, exactly one PATH casing remains, value holds both original directories (PosixOnly: the Win32 environment block is case-insensitive, so the CONTROL arm cannot be constructed in-process on Windows -- SPEC-0120 RR-1)' -Skip:$script:SkipOnWindows {
            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('aai-run-tests-dupenv-' + [System.IO.Path]::GetRandomFileName())
            New-Item -ItemType Directory -Path $tmp | Out-Null
            try {
                $probeFile = Join-Path $tmp 'probe.ps1'
                $probeBody = @'
. "__DISPATCHER__"
[Environment]::SetEnvironmentVariable('PATH', '/dir-one')
[Environment]::SetEnvironmentVariable('Path', '/dir-two')

$controlThrew = $false
try {
    $d = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    $snap = [Environment]::GetEnvironmentVariables()
    foreach ($k in $snap.Keys) { $d.Add([string]$k, [string]$snap[$k]) }
} catch { $controlThrew = $true }
Write-Output "CONTROL_THREW=$controlThrew"

Set-CanonicalProcessEnvironment | Out-Null

$treatmentThrew = $false
try {
    $d2 = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    $snap2 = [Environment]::GetEnvironmentVariables()
    foreach ($k in $snap2.Keys) { $d2.Add([string]$k, [string]$snap2[$k]) }
} catch { $treatmentThrew = $true }
Write-Output "TREATMENT_THREW=$treatmentThrew"

$finalSnap = [Environment]::GetEnvironmentVariables()
$pathCasings = @($finalSnap.Keys | Where-Object { $_ -match '(?i)^path$' })
Write-Output "PATH_CASING_COUNT=$($pathCasings.Count)"
Write-Output "FINAL_PATH=$($finalSnap['Path'])"
'@
                $probeBody = $probeBody.Replace('__DISPATCHER__', $script:RunDispatcher)
                Set-Content -LiteralPath $probeFile -Value $probeBody
                $out = & pwsh -NoProfile -File $probeFile 2>&1
                $joined = $out -join "`n"
                $joined | Should -Match 'CONTROL_THREW=True'
                $joined | Should -Match 'TREATMENT_THREW=False'
                $joined | Should -Match 'PATH_CASING_COUNT=1'
                $joined | Should -Match 'FINAL_PATH=.*dir-one'
                $joined | Should -Match 'FINAL_PATH=.*dir-two'
            } finally {
                Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'CHANGE-0133 TEST-004 (Spec-AC-02, SEAM-3): canonicalizer runs exactly once, before every probe/launch primitive on both branches; clean env -> zero raw Set calls' {
        It 'gitbash branch: canonicalizer invoked exactly once, BEFORE Test-WslUsable and BEFORE Start-GitBashProcess' {
            $script:order = [System.Collections.Generic.List[string]]::new()
            Mock Set-CanonicalProcessEnvironment { $script:order.Add('canonicalize') }
            Mock Test-WslUsable { $script:order.Add('Test-WslUsable'); $false }
            Mock Find-GitBash { 'C:\Program Files\Git\bin\bash.exe' }
            Mock Start-GitBashProcess { $script:order.Add('Start-GitBashProcess'); [PSCustomObject]@{ Id = 7001; ExitCode = 0 } }
            Mock Wait-ProcessWithTimeout { $true }
            $rc = Invoke-Dispatch -Command @('sh', '-c', 'exit 0')
            $rc | Should -Be 0
            Should -Invoke Set-CanonicalProcessEnvironment -Times 1 -Exactly
            @($script:order) | Should -Be @('canonicalize', 'Test-WslUsable', 'Start-GitBashProcess')
        }

        It 'wsl branch: canonicalizer invoked exactly once, BEFORE Test-WslUsable and BEFORE Invoke-WslProcess' {
            $script:order2 = [System.Collections.Generic.List[string]]::new()
            Mock Set-CanonicalProcessEnvironment { $script:order2.Add('canonicalize') }
            Mock Test-WslUsable { $script:order2.Add('Test-WslUsable'); $true }
            Mock ConvertTo-WslPath { '/mnt/c/repo/.aai/scripts/aai-run-tests.sh' }
            Mock Invoke-WslProcess { $script:order2.Add('Invoke-WslProcess'); 0 }
            $rc = Invoke-Dispatch -Command @('sh', '-c', 'exit 0')
            $rc | Should -Be 0
            Should -Invoke Set-CanonicalProcessEnvironment -Times 1 -Exactly
            @($script:order2) | Should -Be @('canonicalize', 'Test-WslUsable', 'Invoke-WslProcess')
        }

        It 'on an already-clean environment the applier performs ZERO Set-EnvironmentVariableRaw calls' {
            Mock Get-ProcessEnvironmentSnapshot {
                $d = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
                $d.Add('FOO', 'bar')
                $d.Add('PATH', '/a:/b')
                return $d
            }
            Mock Set-EnvironmentVariableRaw { }
            Set-CanonicalProcessEnvironment | Out-Null
            Should -Invoke Set-EnvironmentVariableRaw -Times 0 -Exactly
        }
    }

    Context 'CHANGE-0133 TEST-005 (Spec-AC-03): spawn failure (throw or null) -> 125, wait logic never reached, never 124' {
        It 'Start-GitBashProcess THROW -> Invoke-ViaGitBash returns 125, Wait-ProcessWithTimeout never invoked' {
            Mock Start-GitBashProcess { throw 'AAI-TEST-005-THROW' }
            Mock Wait-ProcessWithTimeout { $true }
            Mock Stop-ProcessTree { }
            $rc = Invoke-ViaGitBash -BashPath 'C:\Git\bin\bash.exe' -Command @('sh', '-c', 'exit 0') `
                -ShScriptPath 'C:\repo\.aai\scripts\aai-run-tests.sh' -Timeout 300
            $rc | Should -Be 125
            $rc | Should -Not -Be 124
            Should -Invoke Wait-ProcessWithTimeout -Times 0 -Exactly
        }

        It 'Start-GitBashProcess returns $null -> Invoke-ViaGitBash returns 125, Wait-ProcessWithTimeout never invoked' {
            Mock Start-GitBashProcess { $null }
            Mock Wait-ProcessWithTimeout { $true }
            Mock Stop-ProcessTree { }
            $rc = Invoke-ViaGitBash -BashPath 'C:\Git\bin\bash.exe' -Command @('sh', '-c', 'exit 0') `
                -ShScriptPath 'C:\repo\.aai\scripts\aai-run-tests.sh' -Timeout 300
            $rc | Should -Be 125
            $rc | Should -Not -Be 124
            Should -Invoke Wait-ProcessWithTimeout -Times 0 -Exactly
        }
    }

    Context 'CHANGE-0133 TEST-006 (Spec-AC-03): real child pwsh spawn-failure -> exactly one AAI-SPAWN-ERROR line naming Git Bash + exit 125' {
        It 'stderr holds exactly one AAI-SPAWN-ERROR line containing the exception text and the literal token "Git Bash"; exit code is 125' {
            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('aai-run-tests-spawnfail-' + [System.IO.Path]::GetRandomFileName())
            New-Item -ItemType Directory -Path $tmp | Out-Null
            try {
                $probeFile = Join-Path $tmp 'probe.ps1'
                $probeBody = @'
. "__DISPATCHER__"
function Start-GitBashProcess { param($BashPath, $ScriptArgs, $Timeout) throw 'AAI-TEST-006-UNIQUE-SPAWN-FAILURE' }
$rc = Invoke-ViaGitBash -BashPath 'C:\Git\bin\bash.exe' -Command @('sh', '-c', 'exit 0') -ShScriptPath 'C:\repo\.aai\scripts\aai-run-tests.sh' -Timeout 300
exit $rc
'@
                $probeBody = $probeBody.Replace('__DISPATCHER__', $script:RunDispatcher)
                Set-Content -LiteralPath $probeFile -Value $probeBody
                $errFile = Join-Path $tmp 'err.txt'
                & pwsh -NoProfile -File $probeFile 2>$errFile 1>$null
                $code = $LASTEXITCODE
                $errLines = @(Get-Content $errFile -ErrorAction SilentlyContinue | Where-Object { $_ -match '^AAI-SPAWN-ERROR:' })
                $code | Should -Be 125
                $errLines.Count | Should -Be 1
                $errLines[0] | Should -Match 'AAI-TEST-006-UNIQUE-SPAWN-FAILURE'
                $errLines[0] | Should -Match 'Git Bash'
            } finally {
                Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'CHANGE-0133 TEST-007 (Spec-AC-03): regression pins -- 124 keeps its meaning, no spawn-error noise' {
        It 'live process + timeout still yields 124, tree-kill once, NO AAI-SPAWN-ERROR written' {
            Mock Start-GitBashProcess { [PSCustomObject]@{ Id = 5150; ExitCode = $null } }
            Mock Wait-ProcessWithTimeout { $false }
            Mock Stop-ProcessTree { }
            $origErr = [Console]::Error
            $sw = [System.IO.StringWriter]::new()
            [Console]::SetError($sw)
            try {
                $rc = Invoke-ViaGitBash -BashPath 'C:\Git\bin\bash.exe' -Command @('sh', '-c', 'sleep 300') `
                    -ShScriptPath 'C:\repo\.aai\scripts\aai-run-tests.sh' -Timeout 2
            } finally {
                [Console]::SetError($origErr)
            }
            $rc | Should -Be 124
            Should -Invoke Stop-ProcessTree -Times 1 -Exactly -ParameterFilter { $ProcessId -eq 5150 }
            $sw.ToString() | Should -Not -Match 'AAI-SPAWN-ERROR'
        }

        It 'a normally completed process still propagates its own exit code 7' {
            Mock Start-GitBashProcess { [PSCustomObject]@{ Id = 5151; ExitCode = 7 } }
            Mock Wait-ProcessWithTimeout { $true }
            $rc = Invoke-ViaGitBash -BashPath 'C:\Git\bin\bash.exe' -Command @('sh', '-c', 'exit 7') `
                -ShScriptPath 'C:\repo\.aai\scripts\aai-run-tests.sh' -Timeout 300
            $rc | Should -Be 7
        }
    }

    Context 'CHANGE-0133 TEST-008 (Spec-AC-04): cleanup covers the spawn-failed branch, never a null pid' {
        It 'a throw AFTER a live process object exists tree-kills exactly that pid once and returns 125' {
            Mock Start-GitBashProcess { [PSCustomObject]@{ Id = 6001; ExitCode = $null } }
            Mock Wait-ProcessWithTimeout { throw 'AAI-TEST-008-POST-SPAWN-FAILURE' }
            Mock Stop-ProcessTree { }
            $rc = Invoke-ViaGitBash -BashPath 'C:\Git\bin\bash.exe' -Command @('sh', '-c', 'exit 0') `
                -ShScriptPath 'C:\repo\.aai\scripts\aai-run-tests.sh' -Timeout 300
            $rc | Should -Be 125
            Should -Invoke Stop-ProcessTree -Times 1 -Exactly -ParameterFilter { $ProcessId -eq 6001 }
        }

        It 'a spawn that produced no object invokes Stop-ProcessTree zero times (never a null/empty pid to taskkill)' {
            Mock Start-GitBashProcess { $null }
            Mock Stop-ProcessTree { }
            $rc = Invoke-ViaGitBash -BashPath 'C:\Git\bin\bash.exe' -Command @('sh', '-c', 'exit 0') `
                -ShScriptPath 'C:\repo\.aai\scripts\aai-run-tests.sh' -Timeout 300
            $rc | Should -Be 125
            Should -Invoke Stop-ProcessTree -Times 0 -Exactly
        }
    }

    Context 'CHANGE-0133 TEST-009 (Spec-AC-04): WSL branch parity -- throw -> 125 named WSL, surfaced unchanged through Invoke-Dispatch; a real non-zero delegation passes through' {
        It 'Invoke-WslProcess THROW -> Invoke-ViaWsl returns 125 with a diagnostic naming the literal token WSL' {
            Mock Invoke-WslProcess { throw 'AAI-TEST-009-WSL-SPAWN-FAILURE' }
            Mock ConvertTo-WslPath { '/mnt/c/repo/.aai/scripts/aai-run-tests.sh' }
            $origErr = [Console]::Error
            $sw = [System.IO.StringWriter]::new()
            [Console]::SetError($sw)
            try {
                $rc = Invoke-ViaWsl -Command @('sh', '-c', 'exit 0') -ShScriptPath 'C:\repo\.aai\scripts\aai-run-tests.sh' -Timeout 300
            } finally {
                [Console]::SetError($origErr)
            }
            $rc | Should -Be 125
            $sw.ToString() | Should -Match 'AAI-SPAWN-ERROR'
            $sw.ToString() | Should -Match 'WSL'
            $sw.ToString() | Should -Match 'AAI-TEST-009-WSL-SPAWN-FAILURE'
        }

        It 'Invoke-Dispatch surfaces that 125 unchanged on the wsl branch' {
            Mock Test-WslUsable { $true }
            Mock ConvertTo-WslPath { '/mnt/c/repo/.aai/scripts/aai-run-tests.sh' }
            Mock Invoke-WslProcess { throw 'AAI-TEST-009-DISPATCH-SPAWN-FAILURE' }
            $rc = Invoke-Dispatch -Command @('sh', '-c', 'exit 0')
            $rc | Should -Be 125
        }

        It 'a delegation that RAN and returned non-zero is passed through as its own code' {
            Mock Invoke-WslProcess { 3 }
            Mock ConvertTo-WslPath { '/mnt/c/repo/.aai/scripts/aai-run-tests.sh' }
            $rc = Invoke-ViaWsl -Command @('sh', '-c', 'exit 3') -ShScriptPath 'C:\repo\.aai\scripts\aai-run-tests.sh' -Timeout 300
            $rc | Should -Be 3
        }
    }

    # ---- review-20260812T133652Z-CHANGE-0133-ps1-wrapper-path-dup, CR-1 -------
    # (NON-BLOCKING finding, remediated in-tree). Ports the review's own
    # worst-case emulation of a case-insensitive removal primitive (the kind
    # available on Windows, unavailable on this macOS host) into a Pester arm
    # so the defect the review found -- and its fix -- have a permanent home.
    Context 'CR-1 (review 20260812T133652Z): survivor re-write must be decided against POST-removal state, not the pre-removal snapshot' {
        It 'a case-insensitive removal primitive that erases the survivor''s own entry still gets the merged value written back' {
            # Emulates the Windows Env:-provider / Win32 removal semantics this
            # host cannot exercise directly: Set-EnvironmentVariableRaw(name,
            # $null) here deletes EVERY casing of that name from a mutable
            # store, exactly the review's worst-case primitive. TEMP/Temp is a
            # non-PATH group, which the review identifies as the class that
            # ALWAYS trips the bug (the survivor's canonical value never
            # differs from its own pre-removal value, so the stale-snapshot
            # comparison always skips the write).
            $script:crOneStore = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
            $script:crOneStore['TEMP'] = '/original-temp'
            $script:crOneStore['Temp'] = '/other-temp'
            Mock Get-ProcessEnvironmentSnapshot {
                $d = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
                foreach ($k in $script:crOneStore.Keys) { $d[$k] = $script:crOneStore[$k] }
                return $d
            }
            Mock Set-EnvironmentVariableRaw {
                param($Name, $Value)
                if ([string]::IsNullOrEmpty($Value)) {
                    foreach ($k in @($script:crOneStore.Keys)) {
                        if ([string]::Equals($k, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                            $script:crOneStore.Remove($k) | Out-Null
                        }
                    }
                } else {
                    $script:crOneStore[$Name] = $Value
                }
            }
            Set-CanonicalProcessEnvironment | Out-Null
            # The survivor casing 'TEMP' carrying its canonical value must be
            # present afterwards -- a case-insensitive removal of the discarded
            # 'Temp' casing must never be allowed to silently delete it without
            # a re-write.
            $script:crOneStore.ContainsKey('TEMP') | Should -Be $true
            $script:crOneStore['TEMP'] | Should -Be '/original-temp'
        }

        It 'H3 (PR #247 run 31606986703 investigation): an unrelated process-scope var (AAI_TEST_TIMEOUT) survives canonicalization of a REAL Path/PATH collision AND is visible to a spawned grandchild process — RED/GREEN probe for the smoke''s "default 300s watchdog used instead of AAI_TEST_TIMEOUT=2" symptom (PosixOnly: same Win32 case-insensitive-environment limitation as CHANGE-0133 TEST-003, PLUS the fixture overwrites PATH with a nonexistent directory, which on Windows breaks the Start-Process -FilePath ''pwsh'' resolution this assertion depends on)' -Skip:$script:SkipOnWindows {
            # Field evidence: arm2 of the Windows smoke set AAI_TEST_TIMEOUT=2
            # then invoked aai-run-tests.ps1, which ran to the DEFAULT 300s
            # watchdog instead — i.e. Get-EffectiveTimeout resolved 300, not 2,
            # sometime after Set-CanonicalProcessEnvironment ran (Invoke-
            # Dispatch calls canonicalize THEN reads AAI_TEST_TIMEOUT). This is
            # a REAL, unmocked child-process probe (mirrors CHANGE-0133
            # TEST-003's pattern) exercising the dispatcher's actual removal/
            # rewrite primitives against a genuine dual-casing PATH collision
            # -- the one scenario CR-1 proved DOES trigger collateral damage
            # for a group member. AAI_TEST_TIMEOUT is a single-casing,
            # non-colliding key: if it survives here, Set-
            # CanonicalProcessEnvironment is CLEARED as the root cause and the
            # loss must be happening upstream of this process (fix-at-cause
            # belongs in whatever spawns THIS process, not here).
            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('aai-run-tests-h3-' + [System.IO.Path]::GetRandomFileName())
            New-Item -ItemType Directory -Path $tmp | Out-Null
            try {
                $probeFile = Join-Path $tmp 'probe.ps1'
                $probeBody = @'
. "__DISPATCHER__"
[Environment]::SetEnvironmentVariable('PATH', '/dir-one')
[Environment]::SetEnvironmentVariable('Path', '/dir-two')
[Environment]::SetEnvironmentVariable('AAI_TEST_TIMEOUT', '137')

Set-CanonicalProcessEnvironment | Out-Null

Write-Output "AFTER_ENV_DRIVE=$($env:AAI_TEST_TIMEOUT)"
Write-Output "AFTER_ENV_CLASS=$([Environment]::GetEnvironmentVariable('AAI_TEST_TIMEOUT'))"
Write-Output "EFFECTIVE_TIMEOUT=$(Get-EffectiveTimeout -Raw $env:AAI_TEST_TIMEOUT)"

$outFile = [System.IO.Path]::GetTempFileName()
try {
    Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-Command', '$env:AAI_TEST_TIMEOUT') `
        -NoNewWindow -Wait -RedirectStandardOutput $outFile | Out-Null
    $childSaw = (Get-Content -LiteralPath $outFile -Raw).Trim()
} finally {
    Remove-Item -LiteralPath $outFile -ErrorAction SilentlyContinue
}
Write-Output "GRANDCHILD_SAW=$childSaw"
'@
                $probeBody = $probeBody.Replace('__DISPATCHER__', $script:RunDispatcher)
                Set-Content -LiteralPath $probeFile -Value $probeBody
                $out = & pwsh -NoProfile -File $probeFile 2>&1
                $joined = $out -join "`n"
                $joined | Should -Match 'AFTER_ENV_DRIVE=137'
                $joined | Should -Match 'AFTER_ENV_CLASS=137'
                $joined | Should -Match 'EFFECTIVE_TIMEOUT=137'
                $joined | Should -Match 'GRANDCHILD_SAW=137'
            } finally {
                Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
            }
        }

        It 'an already-clean environment still makes ZERO Set-EnvironmentVariableRaw calls (no re-read on the no-op path)' {
            # Guards the RAW_SET_CALLS=0 no-op contract the review's 59-key
            # real-environment probe asserts: the CR-1 re-read must only fire
            # when $collapsed.Count -gt 0, never unconditionally.
            Mock Get-ProcessEnvironmentSnapshot {
                $d = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
                $d.Add('FOO', 'bar')
                $d.Add('PATH', '/a:/b')
                return $d
            }
            Mock Set-EnvironmentVariableRaw { }
            Set-CanonicalProcessEnvironment | Out-Null
            Should -Invoke Set-EnvironmentVariableRaw -Times 0 -Exactly
            Should -Invoke Get-ProcessEnvironmentSnapshot -Times 1 -Exactly
        }
    }

    # ---- PR #247 iter-4 (owner-directed remediation) ---------------------------
    Context 'TEST-011 (5.1 ExitCode-null footgun): every Start-Process -PassThru launch helper touches .Handle immediately' {
        # Structural/source pin, not a behavioral one: the null-ExitCode-after-
        # exit quirk is Windows PowerShell 5.1-only (.NET Framework Process
        # class), so it cannot be reproduced on this (macOS pwsh 7) host. What
        # CAN be pinned here is the SHAPE of the fix — that the very next
        # statement after each `$proc = Start-Process ... -PassThru` assigns
        # `.Handle` to $null-discard, BEFORE any Remove-Item/wait/return —
        # so a future edit that reorders or drops that line regresses loudly.
        It 'Start-WslProbeProcess touches $proc.Handle on the line immediately after the Start-Process assignment' {
            $content = Get-Content -Raw $script:RunDispatcher
            if ($content -match '(?s)function Start-WslProbeProcess\s*\{(.*?)\n\}') {
                $body = $Matches[1]
            } else {
                $body = ''
            }
            $body | Should -Match '(?s)\$proc\s*=\s*Start-Process\s+-FilePath\s+''wsl\.exe''.*?\n\s*(#.*\n\s*)*\$null\s*=\s*\$proc\.Handle'
        }

        It 'Start-GitBashProcess touches $proc.Handle on the line immediately after the Start-Process assignment, and returns $proc (not the raw Start-Process pipeline output)' {
            $content = Get-Content -Raw $script:RunDispatcher
            if ($content -match '(?s)function Start-GitBashProcess\s*\{(.*?)\n\}') {
                $body = $Matches[1]
            } else {
                $body = ''
            }
            $body | Should -Match '(?s)\$proc\s*=\s*Start-Process\s+-FilePath\s+\$BashPath.*?\n\s*(#.*\n\s*)*\$null\s*=\s*\$proc\.Handle'
            $body | Should -Match 'return\s+\$proc\s*$'
            $body | Should -Not -Match 'return\s+Start-Process'
        }
    }

    Context 'TEST-012 (TIMEOUT VISIBILITY): Get-EffectiveTimeoutSource labels env vs default in parity with Get-EffectiveTimeout''s own coercion rule' {
        It 'Get-EffectiveTimeoutSource: <_.Raw> -> <_.Expected>' -ForEach @(
            @{ Raw = 'bogus'; Expected = 'default' }
            @{ Raw = '0'; Expected = 'default' }
            @{ Raw = '-5'; Expected = 'default' }
            @{ Raw = ''; Expected = 'default' }
            @{ Raw = $null; Expected = 'default' }
            @{ Raw = '45'; Expected = 'env' }
            @{ Raw = '99999999999'; Expected = 'default' }
        ) {
            Get-EffectiveTimeoutSource -Raw $Raw | Should -Be $Expected
        }

        It 'never disagrees with Get-EffectiveTimeout on whether a given Raw value is env-sourced' -ForEach @(
            'bogus', '0', '-5', '', $null, '45', '300', '99999999999'
        ) {
            $raw = $_
            $value = Get-EffectiveTimeout -Raw $raw
            $source = Get-EffectiveTimeoutSource -Raw $raw
            if ($source -eq 'default') { $value | Should -Be 300 }
        }
    }

    Context 'TEST-013 (branch diagnostic, always-on): AAI-BRANCH line names the chosen branch and effective timeout on every non-error run' {
        It 'Write-BranchDiag writes exactly one AAI-BRANCH line with branch, timeout, and source' {
            $origErr = [Console]::Error
            $sw = [System.IO.StringWriter]::new()
            [Console]::SetError($sw)
            try {
                Write-BranchDiag -Branch 'Git Bash' -Timeout 2 -TimeoutSource 'env'
            } finally {
                [Console]::SetError($origErr)
            }
            $lines = @($sw.ToString() -split "`r?`n" | Where-Object { $_ -match '^AAI-BRANCH:' })
            $lines.Count | Should -Be 1
            $lines[0] | Should -Match '^AAI-BRANCH: Git Bash \| AAI-TIMEOUT: 2s \(source=env\)$'
        }

        It 'Invoke-Dispatch prints AAI-BRANCH naming WSL, with the default-sourced timeout, on the wsl branch' {
            Mock Test-WslUsable { $true }
            Mock ConvertTo-WslPath { '/mnt/c/repo/.aai/scripts/aai-run-tests.sh' }
            Mock Invoke-WslProcess { 0 }
            $origErr = [Console]::Error
            $sw = [System.IO.StringWriter]::new()
            [Console]::SetError($sw)
            try {
                $rc = Invoke-Dispatch -Command @('sh', '-c', 'exit 0')
            } finally {
                [Console]::SetError($origErr)
            }
            $rc | Should -Be 0
            $sw.ToString() | Should -Match '^AAI-BRANCH: WSL \| AAI-TIMEOUT: 300s \(source=default\)'
        }

        It 'Invoke-Dispatch prints AAI-BRANCH naming Git Bash, with the env-sourced timeout, on the gitbash branch' {
            Mock Test-WslUsable { $false }
            Mock Find-GitBash { 'C:\Program Files\Git\bin\bash.exe' }
            Mock Start-GitBashProcess { [PSCustomObject]@{ Id = 9001; ExitCode = 3 } }
            Mock Wait-ProcessWithTimeout { $true }
            $origErr = [Console]::Error
            $sw = [System.IO.StringWriter]::new()
            [Console]::SetError($sw)
            $prevTimeout = $env:AAI_TEST_TIMEOUT
            $env:AAI_TEST_TIMEOUT = '2'
            try {
                $rc = Invoke-Dispatch -Command @('sh', '-c', 'exit 3')
            } finally {
                [Console]::SetError($origErr)
                $env:AAI_TEST_TIMEOUT = $prevTimeout
            }
            $rc | Should -Be 3
            $sw.ToString() | Should -Match '^AAI-BRANCH: Git Bash \| AAI-TIMEOUT: 2s \(source=env\)'
        }

        It 'Invoke-Dispatch never prints AAI-BRANCH on the error branch (Write-EnvError keeps its exactly-one-line contract)' {
            Mock Test-WslUsable { $false }
            Mock Find-GitBash { $null }
            $origErr = [Console]::Error
            $sw = [System.IO.StringWriter]::new()
            [Console]::SetError($sw)
            try {
                $rc = Invoke-Dispatch -Command @('sh', '-c', 'exit 0')
            } finally {
                [Console]::SetError($origErr)
            }
            $rc | Should -Be 78
            $sw.ToString() | Should -Not -Match 'AAI-BRANCH:'
            $errLines = @($sw.ToString() -split "`r?`n" | Where-Object { $_ -match '^AAI-ENV-ERROR:' })
            $errLines.Count | Should -Be 1
        }
    }
}

Describe 'aai-release.ps1' {
    # ps1-native-stderr-guard (SPEC-0067-spec-ps1-native-stderr-guard,
    # TEST-001..004, 006, 007). Dot-sourcing aai-release.ps1 defines
    # Invoke-NativeChecked WITHOUT performing a release — the
    # `$MyInvocation.InvocationName -ne '.'` guard around the executable body
    # (arg-parse through the closing finally) is what makes that safe. The
    # TEST-006/TEST-007 checks below spawn a CHILD pwsh process rather than
    # dot-sourcing in-process, because pre-fix (and on any regression) the
    # unguarded body calls `exit N` on its own preconditions, which would
    # otherwise kill this entire Pester run rather than just the probe.

    BeforeEach {
        # Re-dot-source before every test so this suite's own $LASTEXITCODE /
        # function state never leaks between tests (mirrors the pattern above).
        . $script:ReleaseScript
    }

    It 'parses with no syntax errors' {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script:ReleaseScript, [ref]$null, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    Context 'TEST-001 (Spec-AC-01): static contract — helper defined with a local EAP override' {
        It 'defines function Invoke-NativeChecked' {
            $content = Get-Content -Raw $script:ReleaseScript
            $content | Should -Match 'function\s+Invoke-NativeChecked'
        }

        It 'sets a local $ErrorActionPreference = ''Continue'' inside the helper' {
            $content = Get-Content -Raw $script:ReleaseScript
            $content | Should -Match "\`$ErrorActionPreference\s*=\s*'Continue'"
        }
    }

    Context 'TEST-002/TEST-003 (Spec-AC-01): Invoke-NativeChecked behavioral contract' {
        It 'TEST-002: stub writes stderr AND exits 0 -> returns without throwing' {
            # NB: assignment must happen OUTSIDE a `{ } | Should -Not -Throw`
            # scriptblock — that scriptblock is a child scope, so an
            # assignment inside it never leaks to an outer $result. try/catch
            # does not introduce a new variable scope, so it does.
            $result = $null
            $threw = $false
            try {
                $result = Invoke-NativeChecked -Exe 'pwsh' -Arguments @(
                    '-NoProfile', '-Command',
                    '[Console]::Error.WriteLine("benign progress text"); exit 0'
                )
            } catch {
                $threw = $true
            }
            $threw | Should -Be $false
            ($result -join "`n") | Should -Match 'benign progress text'
        }

        It 'TEST-003: stub writes stderr AND exits non-zero -> throws and the message CONTAINS the stderr text' {
            {
                Invoke-NativeChecked -Exe 'pwsh' -Arguments @(
                    '-NoProfile', '-Command',
                    '[Console]::Error.WriteLine("real failure diagnostic"); exit 1'
                )
            } | Should -Throw '*real failure diagnostic*'
        }
    }

    Context 'TEST-004 (Spec-AC-02): every cut-path native call is routed through the helper; probes untouched' {
        It 'no bare git -C $Root push/add/commit/tag statement remains' {
            $content = Get-Content -Raw $script:ReleaseScript
            $content | Should -Not -Match '(?m)^\s*git\s+-C\s+\$Root\s+(push|add|commit|tag)\b'
        }

        It 'no bare gh release create statement remains' {
            # Unanchored on purpose: a bare call reads as contiguous source text
            # "gh release create" even mid-line (e.g. inside a try{}); after the
            # fix the exe/verb/noun become separate quoted Invoke-NativeChecked
            # array elements, so this contiguous substring no longer appears in
            # CODE. Write-Host display strings and header comments (e.g. "-
            # Published: gh release create $Version", "# ... skip push + gh
            # release create") legitimately still contain that phrase as text,
            # so those lines are excluded from this check.
            $offending = Get-Content $script:ReleaseScript | Where-Object {
                $trimmed = $_.TrimStart()
                $_ -notmatch 'Write-Host' -and -not $trimmed.StartsWith('#') -and $_ -match 'gh\s+release\s+create'
            }
            $offending | Should -BeNullOrEmpty
        }

        It 'git add/commit/tag are invoked through Invoke-NativeChecked' {
            $content = Get-Content -Raw $script:ReleaseScript
            $content | Should -Match "Invoke-NativeChecked\s+-Exe\s+'git'\s+-Arguments\s+@\('-C',\s*\`$Root,\s*'add'"
            $content | Should -Match "Invoke-NativeChecked\s+-Exe\s+'git'\s+-Arguments\s+@\('-C',\s*\`$Root,\s*'commit'"
            $content | Should -Match "Invoke-NativeChecked\s+-Exe\s+'git'\s+-Arguments\s+@\('-C',\s*\`$Root,\s*'tag'"
        }

        It 'the display git rev-parse --short HEAD is invoked through Invoke-NativeChecked' {
            $content = Get-Content -Raw $script:ReleaseScript
            $content | Should -Match "Invoke-NativeChecked\s+-Exe\s+'git'\s+-Arguments\s+@\('-C',\s*\`$Root,\s*'rev-parse',\s*'--short',\s*'HEAD'"
        }

        It 'both git push calls are invoked through Invoke-NativeChecked' {
            $content = Get-Content -Raw $script:ReleaseScript
            $content | Should -Match "Invoke-NativeChecked\s+-Exe\s+'git'\s+-Arguments\s+@\('-C',\s*\`$Root,\s*'push',\s*'origin',\s*\`$branch\)"
            $content | Should -Match "Invoke-NativeChecked\s+-Exe\s+'git'\s+-Arguments\s+@\('-C',\s*\`$Root,\s*'push',\s*'origin',\s*""refs/tags"
        }

        It 'gh release create is invoked through Invoke-NativeChecked' {
            $content = Get-Content -Raw $script:ReleaseScript
            $content | Should -Match "Invoke-NativeChecked\s+-Exe\s+'gh'\s+-Arguments\s+@\('release',\s*'create'"
        }

        It 'the tolerant probes (rev-parse -q --verify, gh auth status) keep their existing *> $null handling' {
            $content = Get-Content -Raw $script:ReleaseScript
            $content | Should -Match 'rev-parse\s+-q\s+--verify\s+"refs/tags/\$Version"\s+\*>\s+\$null'
            $content | Should -Match 'gh\s+auth\s+status\s+\*>\s+\$null'
        }
    }

    Context 'TEST-006 (Spec-AC-03): dot-source guard — defines the helper WITHOUT running a release' {
        It 'dot-sourcing in a child process defines Invoke-NativeChecked and does not exit early on release preconditions' {
            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('aai-release-dotsource-' + [System.IO.Path]::GetRandomFileName())
            New-Item -ItemType Directory -Path $tmp | Out-Null
            try {
                $probeFile = Join-Path $tmp 'probe.ps1'
                $probeBody = @"
Set-Location -LiteralPath '$tmp'
. '$($script:ReleaseScript)'
if (Get-Command Invoke-NativeChecked -ErrorAction SilentlyContinue) { Write-Output 'HELPER_DEFINED' } else { Write-Output 'HELPER_MISSING' }
Write-Output 'DOTSOURCE_COMPLETED'
"@
                Set-Content -LiteralPath $probeFile -Value $probeBody
                $out = & pwsh -NoProfile -File $probeFile 2>&1
                $exitCode = $LASTEXITCODE
                ($out -join "`n") | Should -Match 'HELPER_DEFINED'
                ($out -join "`n") | Should -Match 'DOTSOURCE_COMPLETED'
                $exitCode | Should -Be 0
            } finally {
                Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'TEST-007 (Spec-AC-03): -File -DryRun regression — the guard does not change normal execution' {
        It 'pwsh -File aai-release.ps1 -DryRun in a throwaway git fixture exits 0 and prints the plan header' {
            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('aai-release-dryrun-' + [System.IO.Path]::GetRandomFileName())
            New-Item -ItemType Directory -Path $tmp | Out-Null
            try {
                Push-Location $tmp
                try {
                    & git init -q .
                    & git config user.email 'aai-test@example.com'
                    & git config user.name 'AAI Test'
                    $changelog = @"
# Changelog

## [unreleased] — Added
- placeholder entry for TEST-007
"@
                    Set-Content -LiteralPath (Join-Path $tmp 'CHANGELOG.md') -Value $changelog
                    & git add -- CHANGELOG.md
                    & git commit -q -m 'init'
                    $out = & pwsh -NoProfile -File $script:ReleaseScript -DryRun 2>&1
                    $exitCode = $LASTEXITCODE
                } finally {
                    Pop-Location
                }
                $exitCode | Should -Be 0
                ($out -join "`n") | Should -Match 'aai-release \(plan\)'
            } finally {
                Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
            }
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

    # ---- CHANGE-0134 TEST-007 (Spec-AC-03): reaper Test-WslUsable gains the
    # SAME functional-probe fix aai-run-tests.ps1 already carries (CHANGE-0133
    # follow-up) -- the pre-change reaper accepts any `wsl.exe -e true` exit 0
    # as usable, which a distro-less windows-latest satisfies vacuously. RED on
    # the pre-change tree: the reaper has neither Start-WslProbeProcess nor
    # Wait-ProcessWithTimeout, so Test-WslUsable never calls the mocked probe
    # at all and these expectations fail.
    Context 'CHANGE-0134 TEST-007 (Spec-AC-03): reaper Test-WslUsable is a REAL functional probe, not a bare present-check' {
        It 'wsl.exe present, ZERO installed distributions (probe exits 0 without the sentinel) -> NOT usable' {
            Mock Test-WslPresent { $true }
            Mock Start-WslProbeProcess { [PSCustomObject]@{ Id = 9101; ExitCode = 0 } }
            Mock Wait-ProcessWithTimeout { $true }
            Test-WslUsable | Should -Be $false
        }

        It 'wsl.exe present, real distro answers the exact sentinel exit code -> usable' {
            Mock Test-WslPresent { $true }
            Mock Start-WslProbeProcess { [PSCustomObject]@{ Id = 9102; ExitCode = 42 } }
            Mock Wait-ProcessWithTimeout { $true }
            Test-WslUsable | Should -Be $true
        }

        It 'wsl.exe present, distro answers a NON-sentinel exit code -> NOT usable' {
            Mock Test-WslPresent { $true }
            Mock Start-WslProbeProcess { [PSCustomObject]@{ Id = 9103; ExitCode = 1 } }
            Mock Wait-ProcessWithTimeout { $true }
            Test-WslUsable | Should -Be $false
        }

        It 'probe never completes within the watchdog -> NOT usable, probe process stopped exactly once' {
            Mock Test-WslPresent { $true }
            Mock Start-WslProbeProcess { [PSCustomObject]@{ Id = 9104; ExitCode = $null } }
            Mock Wait-ProcessWithTimeout { $false }
            Mock Stop-Process { }
            Test-WslUsable | Should -Be $false
            Should -Invoke Stop-Process -Times 1 -Exactly -ParameterFilter { $Id -eq 9104 }
        }
    }

    # ---- CHANGE-0134 TEST-008 (Spec-AC-03): structural pin over the reaper's
    # own Start-WslProbeProcess, mirroring the pin that already guards
    # aai-run-tests.ps1's copy (TEST-011 in the Describe above). RED on the
    # pre-change tree: the function does not exist yet.
    Context 'CHANGE-0134 TEST-008 (Spec-AC-03): structural pin -- reaper Start-WslProbeProcess redirects both streams and touches .Handle immediately' {
        It 'Start-WslProbeProcess exists, redirects stdout+stderr to per-call temp files, and touches $proc.Handle on the very next statement' {
            $content = Get-Content -Raw $script:ReapDispatcher
            if ($content -match '(?s)function Start-WslProbeProcess\s*\{(.*?)\n\}') {
                $body = $Matches[1]
            } else {
                $body = ''
            }
            $body | Should -Not -BeNullOrEmpty
            $body | Should -Match '-RedirectStandardOutput\s+\$outFile'
            $body | Should -Match '-RedirectStandardError\s+\$errFile'
            $body | Should -Not -Match "-RedirectStandardOutput\s+(\`$null|'NUL'|""NUL"")"
            $body | Should -Match '(?s)\$proc\s*=\s*Start-Process\s+-FilePath\s+''wsl\.exe''.*?\n\s*(#.*\n\s*)*\$null\s*=\s*\$proc\.Handle'
        }
    }

    # ---- CHANGE-0134 TEST-009 (Spec-AC-03, SEAM-3): cross-file sentinel/argv
    # parity -- the two dispatchers deliberately share no module (see both
    # headers), so nothing but a test enforces they still agree. RED on the
    # pre-change tree: the reaper's probe argv is the bare `-e true` command,
    # not the sentinel `-e sh -c "exit <N>"` shape aai-run-tests.ps1 uses.
    Context 'CHANGE-0134 TEST-009 (Spec-AC-03, SEAM-3): reaper and run-tests dispatchers agree on the sentinel value and probe argv' {
        It 'both dispatchers'' Test-WslUsable declare the identical sentinel integer literal' {
            $runContent = Get-Content -Raw $script:RunDispatcher
            $reapContent = Get-Content -Raw $script:ReapDispatcher
            $runSentinel = if ($runContent -match '\$sentinel\s*=\s*(\d+)') { $Matches[1] } else { $null }
            $reapSentinel = if ($reapContent -match '\$sentinel\s*=\s*(\d+)') { $Matches[1] } else { $null }
            $runSentinel | Should -Not -BeNullOrEmpty
            $reapSentinel | Should -Not -BeNullOrEmpty
            $reapSentinel | Should -Be $runSentinel
        }

        It 'both dispatchers'' Test-WslUsable pass the identical probe argument list shape (-e sh -c "exit $sentinel") to Start-WslProbeProcess' {
            $runContent = Get-Content -Raw $script:RunDispatcher
            $reapContent = Get-Content -Raw $script:ReapDispatcher
            $pattern = "Start-WslProbeProcess\s+-ArgumentList\s+@\('-e',\s*'sh',\s*'-c',\s*""exit \`$sentinel""\)"
            $runContent | Should -Match $pattern
            $reapContent | Should -Match $pattern
        }

        It 'reaper Resolve-Interpreter falls through to gitbash when the probe does not return the sentinel-clean result' {
            Mock Test-WslPresent { $true }
            Mock Start-WslProbeProcess { [PSCustomObject]@{ Id = 9105; ExitCode = 0 } }
            Mock Wait-ProcessWithTimeout { $true }
            Mock Find-GitBash { 'C:\Program Files\Git\bin\bash.exe' }
            $r = Resolve-Interpreter
            $r.Mode | Should -Be 'gitbash'
            $r.BashPath | Should -Be 'C:\Program Files\Git\bin\bash.exe'
        }
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
