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
#   3. Pester smoke tests: every tests/skills/*.Tests.ps1 (directory discovery,
#      matching the windows-5_1 job's own Run.Path — SPEC-0046 Windows
#      test-wrapper dispatchers, Spec-AC-09). Skipped-with-note if Pester absent.
#
# Exit codes:
#   0  - All checks passed
#   1  - A check failed
#   42 - Skipped (pwsh not installed — these scripts only run under PowerShell)

set -euo pipefail

TEST_NAME="ps1-quality"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/pipe-safe.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/assert-payload.sh
. "$SCRIPT_DIR/lib/assert-payload.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PS_DIR="$PROJECT_ROOT/.aai/scripts"
SETTINGS="$PS_DIR/PSScriptAnalyzerSettings.psd1"
# VF-4: CHANGE-0134 puts tests/skills/*.Tests.ps1 + tests/skills/lib/*.ps1 on
# Windows PowerShell 5.1 for the first time (the windows-5_1 job's full-suite
# discovery step); the cross-version compat gate below must cover them too,
# not just .aai/scripts, or a 5.1-incompatible construct there ships clean
# through this gate and is discovered only in the real Windows job.
TESTS_PS_DIR="$PROJECT_ROOT/tests/skills"
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

# --- 0. Timeout default parity (Spec-AC-08, validation round 1 BLOCKING-22) --
# Grep-based, not pwsh-based, so it runs on every host regardless of whether
# PowerShell is installed — unlike the Pester leg below (step 3), which is
# CI-only on the Windows-5.1 dimension specifically; pwsh 7 + Pester 5 (when
# present, e.g. via 'brew install powershell') DO exercise it locally too
# (review NB-16 / validator R3-NB-6: this comment used to claim the leg
# "cannot be exercised on this machine at all", which is false wherever pwsh
# is installed).
# Get-EffectiveTimeout's fallback must match aai-run-tests.sh's own
# `${AAI_TEST_TIMEOUT:-3000}` default; the two drifted once already
# (BLOCKING-22: the .ps1 stayed at 300 after the .sh wrapper's raise to
# 3000, silently overriding it back down on every Windows run).
RUN_PS1="$PROJECT_ROOT/.aai/scripts/aai-run-tests.ps1"
RUN_SH="$PROJECT_ROOT/.aai/scripts/aai-run-tests.sh"
log_info "Checking aai-run-tests.ps1's Get-EffectiveTimeout default against the .sh wrapper..."
sh_default="$(grep -oE 'AAI_TEST_TIMEOUT:-[0-9]+' "$RUN_SH" | qhead -1 | grep -oE '[0-9]+$')"
[[ -n "$sh_default" ]] || log_fail "could not find the .sh wrapper's AAI_TEST_TIMEOUT default (aai-run-tests.sh)"
ps1_default="$(awk '/^function Get-EffectiveTimeout {/,/^}/' "$RUN_PS1" | grep -oE 'return [0-9]+' | tail -1 | grep -oE '[0-9]+')"
[[ -n "$ps1_default" ]] || log_fail "could not find Get-EffectiveTimeout's fallback return value in $RUN_PS1"
[[ "$ps1_default" == "$sh_default" ]] \
  || log_fail "aai-run-tests.ps1's Get-EffectiveTimeout falls back to ${ps1_default}s but aai-run-tests.sh defaults to ${sh_default}s — Windows would silently run at a different timeout than every other platform"
log_pass "aai-run-tests.ps1 Get-EffectiveTimeout defaults to ${ps1_default}s, matching the .sh wrapper's ${sh_default}s"

command -v pwsh >/dev/null 2>&1 || log_skip "pwsh not installed — install with 'brew install powershell' (macOS) to run this gate; the parity check above already ran without it, but PARSE-checking, PSScriptAnalyzer and the Pester leg below (Windows-PowerShell-5.1-only, CI-only) cannot run on this machine"

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
assert_payload_has_line "$parse_out" "PARSEBAD=0" "one or more .ps1 scripts have parse errors (see above)"
log_pass "all .ps1 scripts parse cleanly"

# --- 2. PSScriptAnalyzer -------------------------------------------------------
has_pssa="$(pwsh -NoProfile -Command 'if (Get-Module PSScriptAnalyzer -ListAvailable) { "yes" } else { "no" }' 2>/dev/null || echo no)"
if [[ "$has_pssa" == "yes" ]]; then
  # 2a. BLOCKING: cross-version syntax (Windows PowerShell 5.1 + pwsh 7.0) and
  #     true parse Errors. PSUseCompatibleSyntax reports any construct that one of
  #     the target versions cannot parse — the exact cross-version class the field
  #     failure belongs to. Any finding here fails the gate.
  log_info "Running PSScriptAnalyzer cross-version syntax check (5.1 + 7.0) over .aai/scripts + tests/skills (.Tests.ps1 + lib/*.ps1) ..."
  compat_out="$(PS_DIR="$PS_DIR" TESTS_PS_DIR="$TESTS_PS_DIR" pwsh -NoProfile -Command '
    $s = @{ Rules = @{ PSUseCompatibleSyntax = @{ Enable = $true; TargetVersions = @("5.1","7.0") } } }
    $paths = @($env:PS_DIR, $env:TESTS_PS_DIR)
    # Invoke-ScriptAnalyzer -Path does not accept an array on this PSSA
    # version (throws "Cannot convert System.Object[] to String"), so each
    # directory is scanned in its own call and the results merged.
    $compat = @($paths | ForEach-Object { Invoke-ScriptAnalyzer -Path $_ -Recurse -IncludeRule PSUseCompatibleSyntax -Settings $s })
    # -Severity Error is unreliable across PSScriptAnalyzer versions; filter explicitly.
    $errs = @($paths | ForEach-Object { Invoke-ScriptAnalyzer -Path $_ -Recurse } | Where-Object { $_.Severity -eq "Error" })
    $all = @($compat) + @($errs)
    if ($all -and $all.Count) {
      $all | ForEach-Object { Write-Output ("{0}:{1}  {2}  {3}" -f (Split-Path $_.ScriptName -Leaf), $_.Line, $_.RuleName, $_.Message) }
    }
    Write-Output ("COMPATBAD=" + $all.Count)
  ' 2>&1)"
  echo "$compat_out" | grep -v '^COMPATBAD=' || true
  assert_payload_has_line "$compat_out" "COMPATBAD=0" "PSScriptAnalyzer found cross-version syntax incompatibilities or parse Errors (see above)"
  log_pass "PSScriptAnalyzer: .aai/scripts + tests/skills are 5.1 + 7.0 syntax compatible, 0 parse Errors"

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

# --- 3. Pester smoke tests: tests/skills/*.Tests.ps1 (directory discovery) ---
has_pester="$(pwsh -NoProfile -Command 'if (Get-Module Pester -ListAvailable | Where-Object { $_.Version.Major -ge 5 }) { "yes" } else { "no" }' 2>/dev/null || echo no)"
if [[ "$has_pester" == "yes" ]]; then
  log_info "Running Pester smoke tests (tests/skills/*.Tests.ps1, directory discovery) ..."
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
    log_fail "Pester smoke tests failed (one or more tests/skills/*.Tests.ps1 failed, or a non-zero SkippedCount leaked on POSIX)"
  fi
else
  log_info "SKIP Pester (Pester v5 absent; install: pwsh -c \"Install-Module Pester -Scope CurrentUser\")"
fi

echo ""
log_pass "All $TEST_NAME checks passed"
