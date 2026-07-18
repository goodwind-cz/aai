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

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:Update   = Join-Path $RepoRoot '.aai/scripts/aai-update.ps1'

    # Invoke the updater in a fresh pwsh and capture stdout/stderr/exit code.
    # NB: the parameter must NOT be named $Args (that is an automatic variable in
    # PowerShell functions; splatting it would forward nothing). Returns
    # @{ Out; Err; Code }.
    function Invoke-Update {
        param([string[]]$ScriptArgs)
        $errFile = [System.IO.Path]::GetTempFileName()
        $out = & pwsh -NoProfile -File $script:Update @ScriptArgs 2>$errFile
        $code = $LASTEXITCODE
        $err = Get-Content $errFile -Raw -ErrorAction SilentlyContinue
        Remove-Item $errFile -ErrorAction SilentlyContinue
        return @{ Out = ($out -join "`n"); Err = "$err"; Code = $code }
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
        It 'refuses (exit 2) when run inside the canonical AAI repo without -Force' {
            $r = Invoke-Update -ScriptArgs @('-DryRun')   # cwd = canonical repo
            $r.Code | Should -Be 2
            $r.Err  | Should -Match 'REFUSED'
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
        It 'TEST-009: file:// fixture clone with -KeepTemp lands at $Tmp/src; $Tmp retained (skips if git unavailable)' {
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
}
