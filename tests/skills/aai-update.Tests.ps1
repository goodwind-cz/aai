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
# ISSUE-0012 / SPEC-0052 additions (temp-dir TOCTOU fix — ps1 parity):
#   - TEST-006 (Spec-AC-02): static — clone-target in all three attempts is
#     $SrcDir (=$Tmp/src), never bare $Tmp; $Tmp created once as a directory.
#     RED on the current (unfixed) script.
#   - TEST-007 (Spec-AC-02): static — no `Remove-Item ... $Tmp` in the attempt
#     cascade; per-attempt wipe targets $SrcDir; only the `finally` block
#     removes $Tmp. RED on the current (unfixed) script.
#   - TEST-008 (Spec-AC-02): `[Parser]::ParseFile` clean — covered by the
#     pre-existing "parses with no syntax errors" test below.
#   - TEST-009 (Spec-AC-03, SEAM-1 parity): integration — a real clone from a
#     local file:// fixture repo with -KeepTemp: the repo materializes at
#     $Tmp/src and $Tmp is retained. Skips cleanly if git/pwsh unavailable.
#   - TEST-010 (Spec-AC-03): the four pre-existing Describe blocks below
#     (parses / canonical-repo guard / dry-run / bash long-flag / robustness)
#     are the regression guards proving behavior is unchanged.
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
        It 'warns but does not crash on an unrecognized argument' {
            $r = Invoke-Update -ScriptArgs @('--force', '--dry-run', '--bogus', 'xyz')
            $r.Code | Should -Be 0
            $r.Err  | Should -Match "ignoring unrecognized argument '--bogus'"
        }
    }

    Context 'temp-dir lifecycle (ISSUE-0012 / SPEC-0052 — retain $Tmp, clone into $SrcDir)' {
        BeforeAll {
            $script:UpdateContent = Get-Content -Raw $script:Update
        }

        It 'TEST-006: clone target is $SrcDir (=$Tmp/src) in all three attempts, never bare $Tmp; $Tmp created once as a directory' {
            ([regex]::Matches($script:UpdateContent, [regex]::Escape('gh repo clone $Repo $SrcDir'))).Count | Should -Be 1
            ([regex]::Matches($script:UpdateContent, [regex]::Escape('$CloneUrl $SrcDir'))).Count | Should -Be 2
            ([regex]::Matches($script:UpdateContent, [regex]::Escape('gh repo clone $Repo $Tmp'))).Count | Should -Be 0
            ([regex]::Matches($script:UpdateContent, [regex]::Escape('$CloneUrl $Tmp'))).Count | Should -Be 0
            ([regex]::Matches($script:UpdateContent, [regex]::Escape('New-Item -ItemType Directory -Path $Tmp -Force'))).Count | Should -Be 1
            ([regex]::Matches($script:UpdateContent, [regex]::Escape('$SrcDir = Join-Path $Tmp ''src'''))).Count | Should -Be 1
            ([regex]::Matches($script:UpdateContent, [regex]::Escape('$Src = $SrcDir'))).Count | Should -Be 1
        }

        It 'TEST-007: no Remove-Item ... $Tmp in the attempt cascade; per-attempt wipe targets $SrcDir; only finally removes $Tmp' {
            ([regex]::Matches($script:UpdateContent, [regex]::Escape('Remove-Item -Recurse -Force $SrcDir -ErrorAction SilentlyContinue'))).Count | Should -Be 3
            ([regex]::Matches($script:UpdateContent, [regex]::Escape('Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue'))).Count | Should -Be 1
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

                $foundTmp = Get-ChildItem -Path $fixtureTmpBase -Directory -Filter 'aai-src-*' -ErrorAction SilentlyContinue | Select-Object -First 1
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

        It 'TEST-3584: no line combines a git or gh call with a redirect; the helper carries both tags; the file is ASCII-only' {
            $lines = @(Get-Content -LiteralPath $script:Update)
            $raw = @($lines | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '\b(git|gh)\b' -and $_ -match '\*>|2>' })
            $raw | Should -BeNullOrEmpty
            @($lines | Where-Object { $_ -match "ErrorActionPreference = 'Continue'.*# AAI-BEST-EFFORT-EAP\s*$" }).Count | Should -Be 1
            @($lines | Where-Object { $_ -match '# AAI-BEST-EFFORT-RC\s*$' }).Count | Should -Be 1
            @($lines | Where-Object { $_ -match 'PSNativeCommandUseErrorActionPreference = \$false' }).Count | Should -Be 1
            $bytes = [System.IO.File]::ReadAllBytes($script:Update)
            @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
        }
    }
}
