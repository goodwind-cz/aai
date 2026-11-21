# Pester v5 smoke tests for .aai/scripts/aai-update.ps1
#
# Guards the two bugs fixed in PR #16 and the general "does it even parse/run"
# contract, so the PowerShell entrypoint can never silently regress:
#   1. The script PARSES (the field failure was a parse error before any work).
#   2. -DryRun reaches and prints the (previously fragile) "Would run" line.
#   3. The bash long-flags forwarded verbatim by the /aai-update skill
#      (--dry-run, --repo, --ref, --force) are accepted, not just -DryRun/-Repo.
#   4. The canonical-repo guard still refuses (exit 2) without -Force.
#
# update-on-node (SPEC-DRAFT-update-on-node, D-REHOME / D-PESTER): aai-update.ps1 is now a thin launcher of
# .aai/scripts/aai-update.mjs. The source-shape cases of the old PowerShell twin (TEST-006, TEST-007, TEST-3587,
# TEST-3588, TEST-3589) are retired; their properties are proven on the module by the node tests of
# the aai-update-node suite (TEST-3964, TEST-3965). TEST-009 keeps its real clone through the launcher
# (temp directory prefix aai-src.), and the launcher context below runs the launcher itself with the running engine.
#   - TEST-009 (Spec-AC-03, SEAM-1 parity): integration -- a real clone from a local file:// fixture repo with
#     -KeepTemp: the repo materializes at $Tmp/src and $Tmp is retained.
#   - TEST-010 (Spec-AC-03): the Describe blocks below (parses / canonical-repo guard / dry-run / bash long-flag /
#     robustness) are the regression guards proving behavior is unchanged.
#
# Run via: pwsh -NoProfile -Command "Invoke-Pester tests/skills/aai-update.Tests.ps1"
# (the bash gate tests/skills/test-ps1-quality.sh wraps this and skips if pwsh
#  or Pester is unavailable).
#
# CHANGE-0134 Spec-AC-02: dot-sourced at FILE/DISCOVERY scope (plain top-level
# script code, NOT inside BeforeAll) -- see tests/skills/lib/pester-host-skip.ps1
# for why a BeforeAll-scoped variable would silently fail to skip here.
. (Join-Path $PSScriptRoot 'lib/pester-host-skip.ps1')
$script:SkipOnWindows = Test-IsWindowsHostFor -Edition $PSVersionTable.PSEdition -IsWindowsFlag $IsWindows

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:Update   = Join-Path $RepoRoot '.aai/scripts/aai-update.ps1'
    # CHANGE-0134 remediation (real Windows PowerShell 5.1 fix): dot-sourced
    # HERE (inside BeforeAll) rather than at top-of-file/discovery scope -- a
    # top-level dot-source's function definitions do not carry into Pester's
    # Run-phase block scopes (proven while building this fix: a top-level `.`
    # left `Invoke-NativeCaptured` unresolved inside this very BeforeAll).
    . (Join-Path $PSScriptRoot 'lib/pester-native-capture.ps1')

    # D-SAFETY: every update run here is network-free. Only file:// URLs and local directories are used as sources;
    # GIT_ALLOW_PROTOCOL=file and an empty GH_CONFIG_DIR keep git and gh off the network, the token variables are
    # removed, and on POSIX a gh stub that fails sits first on PATH (restored in AfterAll).
    $script:SavedEnv = @{}
    foreach ($n in 'GIT_ALLOW_PROTOCOL', 'GH_CONFIG_DIR', 'GH_TOKEN', 'GITHUB_TOKEN', 'GH_ENTERPRISE_TOKEN', 'GITHUB_ENTERPRISE_TOKEN', 'PATH') {
        $script:SavedEnv[$n] = [Environment]::GetEnvironmentVariable($n)
    }
    $ghConfig = Join-Path $TestDrive 'gh-config'
    New-Item -ItemType Directory -Path $ghConfig -Force | Out-Null
    $env:GIT_ALLOW_PROTOCOL = 'file'
    $env:GH_CONFIG_DIR = $ghConfig
    foreach ($n in 'GH_TOKEN', 'GITHUB_TOKEN', 'GH_ENTERPRISE_TOKEN', 'GITHUB_ENTERPRISE_TOKEN') { Remove-Item "Env:\$n" -ErrorAction SilentlyContinue }
    if ([System.IO.Path]::DirectorySeparatorChar -eq '/') {
        $stubDir = Join-Path $TestDrive 'gh-stub'
        New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $stubDir 'gh'), "#!/bin/sh`nexit 1`n")
        & chmod +x (Join-Path $stubDir 'gh')
        $env:PATH = $stubDir + [System.IO.Path]::PathSeparator + $env:PATH
    }

    # Invoke the updater in a fresh pwsh and capture stdout/stderr/exit code.
    # NB: the parameter must NOT be named $Args (that is an automatic variable in
    # PowerShell functions; splatting it would forward nothing). Returns
    # @{ Out; Err; Code }.
    #
    # CHANGE-0134 remediation (real Windows PowerShell 5.1 fix): routed through the
    # shared Invoke-NativeCaptured (lib/pester-native-capture.ps1) instead of
    # an in-process `2>$errFile` — see that file's header for why the naive
    # form throws a caught "RemoteException" under real 5.1 whenever this
    # harness runs with $ErrorActionPreference = 'Stop' (ps1-quality.yml's
    # Pester step sets exactly that).
    function Invoke-Update {
        param([string[]]$ScriptArgs)
        $r = Invoke-NativeCaptured -Exe 'pwsh' -Arguments (@('-NoProfile', '-File', $script:Update) + $ScriptArgs)
        return @{ Out = $r.Out; Err = $r.Err; Code = $r.Code }
    }
}

AfterAll {
    foreach ($n in $script:SavedEnv.Keys) { [Environment]::SetEnvironmentVariable($n, $script:SavedEnv[$n]) }
}

Describe 'aai-update.ps1' {

    It 'parses with no syntax errors' {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script:Update, [ref]$null, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    Context 'canonical-repo guard' {
        # release-corpus-hermetic Spec-AC-04 (TEST-005/TEST-006): the guard compares the
        # TARGET project's remote.origin.url with -Repo. The old case ran the updater with
        # cwd = the checkout under test, so it passed only where that checkout's origin was
        # the canonical URL and failed in an isolation clone (origin = a local path). Each
        # case now builds its own disposable git target with an explicit origin and invokes
        # the real updater from it; no mock, and the updater is unchanged.
        BeforeAll {
            function New-UpdateTarget {
                param([string]$Name, [string]$OriginUrl)
                $dir = Join-Path $TestDrive $Name
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                git -C $dir init -q
                git -C $dir remote add origin $OriginUrl   # AAI-HERMETIC-ORIGIN
                return $dir
            }
        }

        It 'refuses (exit 2) when the target project origin is the canonical AAI repo, without -Force' {
            $target = New-UpdateTarget -Name 'canonical-target' -OriginUrl 'https://github.com/goodwind-cz/aai.git'
            Push-Location $target
            try {
                $r = Invoke-Update -ScriptArgs @('-DryRun')
            } finally {
                Pop-Location
            }
            $r.Code | Should -Be 2
            $r.Err  | Should -Match 'REFUSED'
        }

        It 'does not refuse a non-canonical target, and leaves the caller location and the real remote untouched' {
            $callerLocation = (Get-Location).Path
            $realOriginBefore = (git -C $script:RepoRoot config --get remote.origin.url 2>$null)
            $target = New-UpdateTarget -Name 'other-target' -OriginUrl 'https://github.com/acme/foo.git'
            Push-Location $target
            try {
                $r = Invoke-Update -ScriptArgs @('-DryRun')
            } finally {
                Pop-Location  # AAI-HERMETIC-POP
            }
            $r.Code | Should -Be 0
            $r.Err  | Should -Not -Match 'REFUSED'
            $r.Out  | Should -Match 'dry-run'
            (Get-Location).Path | Should -Be $callerLocation
            (git -C $script:RepoRoot config --get remote.origin.url 2>$null) | Should -Be $realOriginBefore
        }
    }

    Context 'dry-run output (the previously fragile "Would run" line)' {
        It 'native -Force -DryRun prints the Would-run line and exits 0' {
            $r = Invoke-Update -ScriptArgs @('-Force', '-DryRun')
            $r.Code | Should -Be 0
            $r.Out  | Should -Match 'Would run:.*aai-sync\.ps1 -TargetRoot "'
            $r.Out  | Should -Match 'dry-run'
        }

        It 'bash-style --force --dry-run works identically (flag parity)' {
            $r = Invoke-Update -ScriptArgs @('--force', '--dry-run')
            $r.Code | Should -Be 0
            $r.Out  | Should -Match 'Would run:.*-TargetRoot "'
        }
    }

    Context 'bash long-flag values' {
        It 'accepts --repo=OWNER/NAME and --ref BRANCH (= and space forms)' {
            $r = Invoke-Update -ScriptArgs @('--force', '--dry-run', '--repo=acme/foo', '--ref', 'dev')
            $r.Code | Should -Be 0
            $r.Out  | Should -Match 'acme/foo'
            $r.Out  | Should -Match 'dev'
        }
    }

    Context 'robustness' {
        It 'refuses an unrecognized argument with the Unknown argument line and exit 1 (DR-2)' {
            $r = Invoke-Update -ScriptArgs @('--force', '--dry-run', '--bogus', 'xyz')
            $r.Code | Should -Be 1
            $r.Err  | Should -Match 'Unknown argument: --bogus'
        }
    }

    Context 'SEAM-1 integration (ISSUE-0012 / SPEC-0052 — real clone parity)' {
        It 'TEST-009: file:// fixture clone with -KeepTemp lands at $Tmp/src; $Tmp retained (skips if git unavailable) (PosixOnly: redirects the temp base through $env:TMPDIR, which [System.IO.Path]::GetTempPath() ignores on Windows, and builds a file://C:\...  URL from a backslash path)' -Skip:$script:SkipOnWindows {
            if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
                Set-ItResult -Skipped -Because 'git not installed'
                return
            }

            $workDir = Join-Path ([System.IO.Path]::GetTempPath()) ("aai-update-ps1-e2e-" + [System.IO.Path]::GetRandomFileName())
            New-Item -ItemType Directory -Path $workDir -Force | Out-Null
            try {
                # Build a minimal fixture "canonical repo" with a fake aai-sync.ps1
                # that proves it ran (and against which TARGET) without needing the
                # real sync logic.
                $fixtureSrc = Join-Path $workDir 'fixture-src-repo'
                New-Item -ItemType Directory -Path (Join-Path $fixtureSrc '.aai/scripts') -Force | Out-Null
                $fixtureSyncPath = Join-Path $fixtureSrc '.aai/scripts/aai-sync.ps1'
                @'
param([string]$TargetRoot)
New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null
"FIXTURE_SYNC_RAN target=$TargetRoot" | Set-Content -Path (Join-Path $TargetRoot 'FIXTURE_SYNC_MARKER')
'@ | Set-Content -Path $fixtureSyncPath
                git -C $fixtureSrc init -q -b main
                git -C $fixtureSrc -c user.email=test@example.com -c user.name=test add -A
                git -C $fixtureSrc -c user.email=test@example.com -c user.name=test commit -q -m fixture

                $targetDir = Join-Path $workDir 'target'
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                $fixtureTmpBase = Join-Path $workDir 'tmpbase'
                New-Item -ItemType Directory -Path $fixtureTmpBase -Force | Out-Null

                $errFile = [System.IO.Path]::GetTempFileName()
                Push-Location $targetDir
                try {
                    $env:TMPDIR = $fixtureTmpBase
                    $out = & pwsh -NoProfile -File $script:Update -Repo "file://$fixtureSrc" -Force -KeepTemp 2>$errFile
                    $code = $LASTEXITCODE
                } finally {
                    Pop-Location
                    Remove-Item Env:\TMPDIR -ErrorAction SilentlyContinue
                }
                $errText = Get-Content $errFile -Raw -ErrorAction SilentlyContinue
                Remove-Item $errFile -ErrorAction SilentlyContinue

                $code | Should -Be 0 -Because "stderr: $errText"

                $foundTmp = Get-ChildItem -Path $fixtureTmpBase -Directory -Filter 'aai-src.*' -ErrorAction SilentlyContinue | Select-Object -First 1
                $foundTmp | Should -Not -BeNullOrEmpty
                (Test-Path (Join-Path $foundTmp.FullName 'src/.git')) | Should -BeTrue
                (Test-Path (Join-Path $foundTmp.FullName 'src/.aai/scripts/aai-sync.ps1')) | Should -BeTrue
                (Test-Path (Join-Path $targetDir 'FIXTURE_SYNC_MARKER')) | Should -BeTrue
            } finally {
                Remove-Item -Recurse -Force $workDir -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'best-effort native calls (update-ps1-git-stderr)' {
        # Spec-AC-01..04: the updater runs every redirected git/gh call through one
        # best-effort helper, so a git stderr line or a nonzero exit never ends it.
        # The updater runs under the HOSTING engine (powershell.exe on the 5.1 leg,
        # pwsh on the 7 leg) behind a wrapper that turns on the native-command error
        # preference on 7.3+ (the regression trigger on pwsh).
        BeforeAll {
            $script:HostExe = (Get-Process -Id $PID).Path
            $script:BeWrapper = Join-Path $TestDrive 'be-wrapper.ps1'
            @'
param([string]$UpdatePath, [string]$RepoArg)
if ($PSVersionTable.PSVersion -ge [version]'7.3') { $PSNativeCommandUseErrorActionPreference = $true }
& $UpdatePath -Repo $RepoArg -Ref main
exit $LASTEXITCODE
'@ | Set-Content -LiteralPath $script:BeWrapper

            function New-BeSource {
                param([string]$Name)
                $src = Join-Path $TestDrive $Name
                New-Item -ItemType Directory -Path (Join-Path $src '.aai/scripts') -Force | Out-Null
                @'
param([string]$TargetRoot)
New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null
"BE_SYNC_RAN" | Set-Content -Path (Join-Path $TargetRoot 'BE_SYNC_MARKER')
'@ | Set-Content -LiteralPath (Join-Path $src '.aai/scripts/aai-sync.ps1')
                git -C $src init -q -b main
                git -C $src -c user.email=test@example.com -c user.name=test add -A
                git -C $src -c user.email=test@example.com -c user.name=test commit -q -m fixture
                return $src
            }

            function Invoke-BeUpdate {
                param([string]$Target, [string]$RepoArg)
                Push-Location $Target
                try {
                    $r = Invoke-NativeCaptured -Exe $script:HostExe -Arguments @('-NoProfile', '-File', $script:BeWrapper, '-UpdatePath', $script:Update, '-RepoArg', $RepoArg)
                } finally {
                    Pop-Location
                }
                return $r
            }

            function New-BeGitTarget {
                param([string]$Name)
                $dir = Join-Path $TestDrive $Name
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                git -C $dir init -q
                git -C $dir remote add origin 'https://github.com/acme/foo.git'
                return $dir
            }
        }

        It 'TEST-3580: a local -Repo checkout without origin (fetch and pull fail) still syncs and exits 0' {
            $src = New-BeSource -Name 'be-src-1'
            $target = New-BeGitTarget -Name 'be-target-1'
            $r = Invoke-BeUpdate -Target $target -RepoArg $src
            $r.Code | Should -Be 0 -Because "stderr: $($r.Err)"
            (Test-Path (Join-Path $target 'BE_SYNC_MARKER')) | Should -BeTrue
            $r.Err | Should -Not -Match 'NativeCommandError'
            $r.Err | Should -Not -Match 'non-zero exit code'
        }

        It 'TEST-3581: a nonexistent file:// source tries every clone attempt and exits 3, never 1' {
            $target = New-BeGitTarget -Name 'be-target-2'
            $missing = [System.Uri]::new((Join-Path $TestDrive 'be-no-such-repo')).AbsoluteUri
            $r = Invoke-BeUpdate -Target $target -RepoArg $missing
            $r.Code | Should -Be 3 -Because "stderr: $($r.Err)"
            $r.Err | Should -Match 'ERROR: could not fetch'
        }

        It 'TEST-3582: a real file:// fixture repository clones through the cascade and its sync runs' {
            $src = New-BeSource -Name 'be-src-3'
            $target = New-BeGitTarget -Name 'be-target-3'
            $url = [System.Uri]::new($src).AbsoluteUri
            $r = Invoke-BeUpdate -Target $target -RepoArg $url
            $r.Code | Should -Be 0 -Because "stderr: $($r.Err)"
            (Test-Path (Join-Path $target 'BE_SYNC_MARKER')) | Should -BeTrue
        }

        It 'TEST-3583: a target that is not a git repository passes the guard, syncs, and reports no changes' {
            $src = New-BeSource -Name 'be-src-4'
            $target = Join-Path $TestDrive 'be-target-4'
            New-Item -ItemType Directory -Path $target -Force | Out-Null
            $r = Invoke-BeUpdate -Target $target -RepoArg $src
            $r.Code | Should -Be 0 -Because "stderr: $($r.Err)"
            $r.Err | Should -Not -Match 'REFUSED'
            (Test-Path (Join-Path $target 'BE_SYNC_MARKER')) | Should -BeTrue
            $r.Out | Should -Match 'Changed files: none \(already up to date\)'
        }

        It 'TEST-3584: the launcher holds no git or gh token and is ASCII only (the native-call class is gone from the update path)' {
            $lines = @(Get-Content -LiteralPath $script:Update)
            @($lines | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '\b(git|gh)\b' }).Count | Should -Be 0
            $bytes = [System.IO.File]::ReadAllBytes($script:Update)
            @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
        }
    }

    Context 'launcher (update-on-node)' {
        # D-PESTER: the launcher runs under the engine running this test ((Get-Process -Id $PID).Path), through
        # ProcessStartInfo with an explicit PATH; every fixture lives in $TestDrive.
        BeforeAll {
            $script:Engine = (Get-Process -Id $PID).Path
            $script:Refused = 'aai-update: refused - node not found in PATH or aai-update.mjs missing; nothing was changed. Install Node.js 22 or later (https://nodejs.org/) and re-run.'

            function New-LaunchDir {
                param([string]$Name)
                $d = Join-Path $TestDrive $Name
                New-Item -ItemType Directory -Force -Path $d | Out-Null
                return $d
            }
            function Invoke-Engine {
                param([string]$EngineArgs, [string]$WorkDir, [string]$Path)
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = $script:Engine
                $psi.Arguments = $EngineArgs
                $psi.WorkingDirectory = $WorkDir
                $psi.UseShellExecute = $false
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError = $true
                $psi.EnvironmentVariables['PATH'] = $Path
                $psi.EnvironmentVariables['PWD'] = $WorkDir
                $p = [System.Diagnostics.Process]::Start($psi)
                $out = $p.StandardOutput.ReadToEnd()
                $err = $p.StandardError.ReadToEnd()
                $p.WaitForExit()
                return [pscustomobject]@{ ExitCode = $p.ExitCode; Stdout = $out; Stderr = $err }
            }
            function Invoke-Launcher {
                param([string]$LauncherPath, [string]$WorkDir, [string]$LauncherArgs, [string]$Path)
                return (Invoke-Engine -EngineArgs (('-NoProfile -NonInteractive -File "' + $LauncherPath + '" ' + $LauncherArgs).Trim()) -WorkDir $WorkDir -Path $Path)
            }
            function Write-StubModule {
                param([string]$Dir, [string]$Body)
                [System.IO.File]::WriteAllText((Join-Path $Dir 'aai-update.mjs'), $Body)
            }
        }

        It 'passes every argument through in order, hands the module the engine path and keeps its exit code' {
            $d = New-LaunchDir 'launch-pass'
            Copy-Item -LiteralPath $script:Update -Destination (Join-Path $d 'aai-update.ps1')
            Write-StubModule $d "console.log(JSON.stringify({ argv: process.argv.slice(2), runner: process.env.AAI_UPDATE_SYNC_RUNNER }));`nprocess.exit(7);`n"
            $r = Invoke-Launcher (Join-Path $d 'aai-update.ps1') $d '-Repo "dir with space" --ref dev -DryRun --keep-temp -Force -h' $env:PATH
            $r.ExitCode | Should -Be 7 -Because "stderr: $($r.Stderr)"
            $got = $r.Stdout | ConvertFrom-Json
            @($got.argv) | Should -Be @('-Repo', 'dir with space', '--ref', 'dev', '-DryRun', '--keep-temp', '-Force', '-h')
            $got.runner | Should -Be $script:Engine
        }

        It 'restores the caller value of AAI_UPDATE_SYNC_RUNNER afterwards, and leaves it unset when it was unset' {
            $d = New-LaunchDir 'launch-scope'
            Copy-Item -LiteralPath $script:Update -Destination (Join-Path $d 'aai-update.ps1')
            Write-StubModule $d "process.exit(0);`n"
            $launcher = Join-Path $d 'aai-update.ps1'
            $preset = Invoke-Engine -EngineArgs ('-NoProfile -NonInteractive -Command "$env:AAI_UPDATE_SYNC_RUNNER = ''preset''; & ''' + $launcher + '''; $env:AAI_UPDATE_SYNC_RUNNER"') -WorkDir $d -Path $env:PATH
            $preset.Stdout.Trim() | Should -Be 'preset' -Because "stderr: $($preset.Stderr)"
            $unset = Invoke-Engine -EngineArgs ('-NoProfile -NonInteractive -Command "& ''' + $launcher + '''; $env:AAI_UPDATE_SYNC_RUNNER"') -WorkDir $d -Path $env:PATH
            $unset.Stdout.Trim() | Should -Be '' -Because "stderr: $($unset.Stderr)"
        }

        It 'refuses with the one line, prints nothing on stdout and changes nothing when node is not on PATH' {
            $d = New-LaunchDir 'launch-nonode'
            $target = New-LaunchDir 'launch-nonode-target'
            $emptyPath = New-LaunchDir 'launch-empty-path'
            Copy-Item -LiteralPath $script:Update -Destination (Join-Path $d 'aai-update.ps1')
            Write-StubModule $d "process.exit(0);`n"
            $r = Invoke-Launcher (Join-Path $d 'aai-update.ps1') $target '--dry-run' $emptyPath
            $r.ExitCode | Should -Be 1
            $r.Stdout | Should -Be ''
            $r.Stderr.Trim() | Should -Be $script:Refused
            @(Get-ChildItem -LiteralPath $target -Force).Count | Should -Be 0
        }

        It 'refuses the same way when the module is missing next to the launcher' {
            $d = New-LaunchDir 'launch-nomodule'
            $target = New-LaunchDir 'launch-nomodule-target'
            Copy-Item -LiteralPath $script:Update -Destination (Join-Path $d 'aai-update.ps1')
            $r = Invoke-Launcher (Join-Path $d 'aai-update.ps1') $target '--dry-run' $env:PATH
            $r.ExitCode | Should -Be 1
            $r.Stdout | Should -Be ''
            $r.Stderr.Trim() | Should -Be $script:Refused
            @(Get-ChildItem -LiteralPath $target -Force).Count | Should -Be 0
        }

        It 'runs the real module: the sync of the source runs under the same engine and the evidence prints' {
            $src = New-LaunchDir 'launch-src'
            New-Item -ItemType Directory -Path (Join-Path $src '.aai/scripts') -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $src '.aai/scripts/aai-sync.ps1'), "param([string]`$TargetRoot)`nNew-Item -ItemType Directory -Path `$TargetRoot -Force | Out-Null`n(Get-Process -Id `$PID).Path | Set-Content -Path (Join-Path `$TargetRoot 'SYNC_ENGINE')`n")
            git -C $src init -q -b main
            git -C $src -c user.email=test@example.com -c user.name=test add -A
            git -C $src -c user.email=test@example.com -c user.name=test commit -q -m fixture
            $target = New-LaunchDir 'launch-real-target'
            git -C $target init -q
            git -C $target remote add origin 'https://github.com/acme/foo.git'
            $r = Invoke-Launcher $script:Update $target ('-Repo "' + $src + '" -Force') $env:PATH
            $r.ExitCode | Should -Be 0 -Because "stderr: $($r.Stderr)"
            (Get-Content -LiteralPath (Join-Path $target 'SYNC_ENGINE') -Raw).Trim() | Should -Be $script:Engine
            $r.Stdout | Should -Match '## Post-sync evidence'
            $r.Stdout | Should -Match '## Next'
        }
    }
}
