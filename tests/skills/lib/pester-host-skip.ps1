# pester-host-skip.ps1 — shared discovery-time Windows-skip predicate
# (CHANGE-0134 Spec-AC-02).
#
# MUST be dot-sourced at FILE/DISCOVERY scope in every *.Tests.ps1 that uses
# it — i.e. as plain top-level script code, OUTSIDE any BeforeAll block.
# Pester evaluates a `-Skip:` expression at DISCOVERY time, before ANY
# BeforeAll (even a top-of-file one) ever runs; a BeforeAll-scoped variable
# reads back $null there, and $null is falsy, so the test would silently NOT
# skip on the very host this predicate exists to guard.
#
# $IsWindows is a PowerShell Core (6.0+)-only automatic variable — reading it under Windows
# PowerShell 5.1 returns $null (undefined, not $false), which is also falsy
# and would silently un-skip a Windows-fragile test on exactly the engine
# this scope adds coverage for. $PSVersionTable.PSEdition is 'Desktop' on
# Windows PowerShell 5.1 (no non-Windows Desktop edition exists, so 'Desktop'
# alone is a sufficient and correct Windows signal there) and 'Core' on pwsh
# 6/7 (cross-platform, where the explicit $IsWindows flag is authoritative).
#
# Usage (each .Tests.ps1 file, at the very top, outside BeforeAll):
#   . (Join-Path $PSScriptRoot 'lib/pester-host-skip.ps1')
#   $script:SkipOnWindows = Test-IsWindowsHostFor -Edition $PSVersionTable.PSEdition -IsWindowsFlag $IsWindows
#   ... It '... (PosixOnly: <reason>)' -Skip:$script:SkipOnWindows { ... }
#
# Adding a PosixOnly skip requires bumping AAI_EXPECTED_WIN_SKIP_COUNT in
# .github/workflows/ps1-quality.yml (one place, job-level env) -- test_017 in
# tests/skills/test-aai-win-fallback.sh pins the two to stay equal, so a skip
# added without the bump fails fast, locally, instead of ~10+ minutes into
# the real Windows job.

function Test-IsWindowsHostFor {
  [CmdletBinding()]
  param(
    [string]$Edition,
    [object]$IsWindowsFlag
  )
  if ($Edition -eq 'Desktop') { return $true }
  return ($IsWindowsFlag -eq $true)
}
