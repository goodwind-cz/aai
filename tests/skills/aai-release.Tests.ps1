# Pester v5 unit tests for .aai/scripts/aai-release.ps1's protected-branch
# classifier (release-protected-branch-fallback / TEST-033, Spec-AC-07).
#
# WHY A UNIT TEST AND NOT ONLY THE INTEGRATION ARM: the bash suite's
# test_033_ps1_fallback_parity drives the whole ps1 engine through a protected
# `file://` fixture, but it can only run where `pwsh` exists AND a scratch git
# remote can be pushed to. The classifier is the one piece whose behavior must
# be pinned on EVERY engine the ps1 gate runs (pwsh 7 on POSIX, pwsh 7 on
# Windows, Windows PowerShell 5.1), because a `.Contains`/`ToLowerInvariant`
# difference there silently turns the fallback off and hands the operator back
# the exact half-cut release this scope exists to prevent.
#
# The dot-source below is the seam under test as much as the function is:
# Test-ProtectedBranchRejection is defined ABOVE aai-release.ps1's
# `if ($MyInvocation.InvocationName -ne '.')` guard on purpose, so dot-sourcing
# the engine defines the classifier WITHOUT parsing arguments or cutting a
# release (the same contract Invoke-NativeChecked has carried since
# ps1-native-stderr-guard / SPEC-0067 Spec-AC-03). If the function is ever
# moved below the guard, every It below fails with "not recognized".
#
# Run via: pwsh -NoProfile -Command "Invoke-Pester tests/skills/aai-release.Tests.ps1"
# (the bash gate tests/skills/test-ps1-quality.sh discovers this directory and
#  skips cleanly if pwsh or Pester is unavailable).

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:Release  = Join-Path $script:RepoRoot '.aai/scripts/aai-release.ps1'

    # Dot-sourced HERE (inside BeforeAll) rather than at top-of-file/discovery
    # scope: a top-level dot-source's function definitions do not carry into
    # Pester's Run-phase block scopes (proven in aai-update.Tests.ps1 against
    # real Windows PowerShell 5.1).
    . $script:Release
}

Describe 'aai-release.ps1 exports and direct-push classifier elimination' {

    It 'parses with no syntax errors' {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script:Release, [ref]$null, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It 'Test-ProtectedBranchRejection and Get-DfConflictRef are eliminated' {
        (Get-Command Test-ProtectedBranchRejection -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
        (Get-Command Get-DfConflictRef -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
    }

    It 'Select-CapturedValue extracts matching values' {
        $sample = @('first line', 'https://github.com/goodwind-cz/aai/pull/462', 'third line')
        $val = Select-CapturedValue -Captured $sample -Pattern '^https?://'
        $val | Should -Be 'https://github.com/goodwind-cz/aai/pull/462'
    }

    It 'Select-CapturedValue refuses empty-native-output when no line matches' {
        $sample = @('first line', 'second line')
        { Select-CapturedValue -Captured $sample -Pattern '^https?://' } | Should -Throw '*REFUSED: empty-native-output*'
    }
}
