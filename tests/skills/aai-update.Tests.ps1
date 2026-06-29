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
}
