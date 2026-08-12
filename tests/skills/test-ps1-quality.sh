#!/usr/bin/env bash
#
# Test: PowerShell script quality gate
# Guards the vendored .aai/scripts/*.ps1 against the class of failure that broke
# /aai-update in the field (a PowerShell PARSE error before any work), plus
# cross-version (Windows PowerShell 5.1) syntax incompatibilities and real
# PSScriptAnalyzer defects. Also runs the aai-update.ps1 Pester smoke tests.
#
# Three layers:
#   1. Parse-check EVERY .ps1 (catches the exact "'<' operator reserved /
#      missing terminator" class). Pure pwsh, no extra modules.
#   2. PSScriptAnalyzer at Error severity using .aai/scripts/PSScriptAnalyzerSettings.psd1
#      (includes PSUseCompatibleSyntax targeting 5.1 + 7.0). Skipped-with-note if
#      the module is absent.
#   3. Pester smoke tests: aai-update.Tests.ps1 (aai-update.ps1) AND
#      aai-win-dispatch.Tests.ps1 (SPEC-0046 Windows test-wrapper dispatchers,
#      Spec-AC-09). Skipped-with-note if Pester absent.
#
# Exit codes:
#   0  - All checks passed
#   1  - A check failed
#   42 - Skipped (pwsh not installed — these scripts only run under PowerShell)

set -euo pipefail

TEST_NAME="ps1-quality"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PS_DIR="$PROJECT_ROOT/.aai/scripts"
SETTINGS="$PS_DIR/PSScriptAnalyzerSettings.psd1"
# VF-6: directory discovery (matching the windows-5_1 job's own
# `$cfg.Run.Path = 'tests/skills'`), not a hardcoded two-file list -- a future
# tests/skills/*.Tests.ps1 file is now picked up on BOTH sides identically, so
# it cannot land on Windows CI while staying invisible to this POSIX
# SkippedCount=0 guard (CHANGE-0134 SEAM-4's stated intent, now true on both).
PESTER_TESTS_DIR="$SCRIPT_DIR"

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

command -v pwsh >/dev/null 2>&1 || log_skip "pwsh not installed — install with 'brew install powershell' (macOS) to run this gate"

# --- 1. Parse-check every .ps1 ------------------------------------------------
log_info "Parse-checking every .aai/scripts/*.ps1 ..."
parse_out="$(PS_DIR="$PS_DIR" pwsh -NoProfile -Command '
  $bad = 0
  Get-ChildItem -Path (Join-Path $env:PS_DIR "*.ps1") | Sort-Object Name | ForEach-Object {
    $errs = $null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$errs) | Out-Null
    if ($errs -and $errs.Count) {
      $bad++
      Write-Output ("PARSEFAIL " + $_.Name)
      $errs | ForEach-Object { Write-Output ("  " + $_.Message) }
    }
  }
  Write-Output ("PARSEBAD=" + $bad)
' 2>&1)"
echo "$parse_out" | grep -v '^PARSEBAD=' || true
if ! echo "$parse_out" | grep -q '^PARSEBAD=0$'; then
  log_fail "one or more .ps1 scripts have parse errors (see above)"
fi
log_pass "all .ps1 scripts parse cleanly"

# --- 2. PSScriptAnalyzer -------------------------------------------------------
has_pssa="$(pwsh -NoProfile -Command 'if (Get-Module PSScriptAnalyzer -ListAvailable) { "yes" } else { "no" }' 2>/dev/null || echo no)"
if [[ "$has_pssa" == "yes" ]]; then
  # 2a. BLOCKING: cross-version syntax (Windows PowerShell 5.1 + pwsh 7.0) and
  #     true parse Errors. PSUseCompatibleSyntax reports any construct that one of
  #     the target versions cannot parse — the exact cross-version class the field
  #     failure belongs to. Any finding here fails the gate.
  log_info "Running PSScriptAnalyzer cross-version syntax check (5.1 + 7.0) ..."
  compat_out="$(PS_DIR="$PS_DIR" pwsh -NoProfile -Command '
    $s = @{ Rules = @{ PSUseCompatibleSyntax = @{ Enable = $true; TargetVersions = @("5.1","7.0") } } }
    $compat = Invoke-ScriptAnalyzer -Path $env:PS_DIR -Recurse -IncludeRule PSUseCompatibleSyntax -Settings $s
    # -Severity Error is unreliable across PSScriptAnalyzer versions; filter explicitly.
    $errs = Invoke-ScriptAnalyzer -Path $env:PS_DIR -Recurse | Where-Object { $_.Severity -eq "Error" }
    $all = @($compat) + @($errs)
    if ($all -and $all.Count) {
      $all | ForEach-Object { Write-Output ("{0}:{1}  {2}  {3}" -f (Split-Path $_.ScriptName -Leaf), $_.Line, $_.RuleName, $_.Message) }
    }
    Write-Output ("COMPATBAD=" + $all.Count)
  ' 2>&1)"
  echo "$compat_out" | grep -v '^COMPATBAD=' || true
  if ! echo "$compat_out" | grep -q '^COMPATBAD=0$'; then
    log_fail "PSScriptAnalyzer found cross-version syntax incompatibilities or parse Errors (see above)"
  fi
  log_pass "PSScriptAnalyzer: scripts are 5.1 + 7.0 syntax compatible, 0 parse Errors"

  # 2b. INFORMATIONAL: quality warnings (non-blocking; CLI scripts intentionally
  #     use Write-Host etc., excluded via PSScriptAnalyzerSettings.psd1).
  log_info "PSScriptAnalyzer quality warnings (informational, non-blocking):"
  SETTINGS="$SETTINGS" PS_DIR="$PS_DIR" pwsh -NoProfile -Command '
    $r = Invoke-ScriptAnalyzer -Path $env:PS_DIR -Recurse -Settings $env:SETTINGS -Severity Warning
    if ($r) {
      $r | ForEach-Object { Write-Output ("  {0}:{1}  {2}" -f (Split-Path $_.ScriptName -Leaf), $_.Line, $_.RuleName) }
    } else { Write-Output "  (none)" }
  ' 2>&1 || true
else
  log_info "SKIP PSScriptAnalyzer (module absent; install: pwsh -c \"Install-Module PSScriptAnalyzer -Scope CurrentUser\")"
fi

# --- 3. Pester smoke tests: aai-update.ps1 + the Windows dispatchers ---------
has_pester="$(pwsh -NoProfile -Command 'if (Get-Module Pester -ListAvailable | Where-Object { $_.Version.Major -ge 5 }) { "yes" } else { "no" }' 2>/dev/null || echo no)"
if [[ "$has_pester" == "yes" ]]; then
  log_info "Running Pester smoke tests (aai-update.Tests.ps1, aai-win-dispatch.Tests.ps1) ..."
  # CHANGE-0134 Spec-AC-02 (POSIX half of SEAM-1): PassThru captures the
  # result object so SkippedCount can be asserted directly, rather than
  # letting Pester's own Run.Exit decide pass/fail from FailedCount alone.
  # This IS the guard that a Windows-only skip predicate (CHANGE-0134's
  # $script:SkipOnWindows) can never leak into the Linux/macOS gate and turn
  # it vacuously green: on a POSIX host SkippedCount must be exactly zero.
  if PESTER_TESTS_DIR="$PESTER_TESTS_DIR" pwsh -NoProfile -Command '
      $cfg = New-PesterConfiguration
      $cfg.Run.Path = $env:PESTER_TESTS_DIR
      $cfg.Run.PassThru = $true
      $cfg.Output.Verbosity = "Detailed"
      $result = Invoke-Pester -Configuration $cfg
      Write-Host "AAI-POSIX-PESTER: Total=$($result.TotalCount) Passed=$($result.PassedCount) Failed=$($result.FailedCount) Skipped=$($result.SkippedCount)"
      $fail = 0
      if ($result.FailedCount -gt 0) { $fail++ }
      if ($result.SkippedCount -ne 0) {
        Write-Host "FAIL: SkippedCount=$($result.SkippedCount) on a POSIX host (must be 0 -- a Windows-only skip predicate leaked through)"
        $fail++
      }
      # VF-5: TEST-005 declares a TotalCount floor of 111; previously only
      # printed, never asserted, so a discovery that silently matched no
      # files (e.g. a bad Run.Path) would report Total=0 and still exit green.
      if ($result.TotalCount -lt 111) {
        Write-Host "FAIL: TotalCount=$($result.TotalCount) is below the declared floor of 111 (TEST-005)"
        $fail++
      }
      if ($fail -gt 0) { exit 1 }
      exit 0
    '; then
    log_pass "Pester smoke tests passed (SkippedCount 0 on this POSIX host)"
  else
    log_fail "Pester smoke tests failed (aai-update.ps1 and/or aai-win-dispatch.Tests.ps1 failed, or a non-zero SkippedCount leaked on POSIX)"
  fi
else
  log_info "SKIP Pester (Pester v5 absent; install: pwsh -c \"Install-Module Pester -Scope CurrentUser\")"
fi

echo ""
log_pass "All $TEST_NAME checks passed"
