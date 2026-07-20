#!/usr/bin/env pwsh
#
# aai-reap-tests.ps1 — Windows entry point mirroring aai-reap-tests.sh
# (SPEC-0046 / ISSUE-0009, Spec-AC-04). Defence-in-depth sweep for leaked
# `vitest`/`esbuild` process trees after a test-running tick.
#
# SAFETY INVARIANT (load-bearing, mirrors the .sh reaper — never global): this
# reaper kills ONLY processes whose command line contains a `vitest`/`esbuild`
# token AND the workspace path (AAI_REAP_WORKSPACE, default $PWD, matched as a
# proper path-separator-anchored segment, never a bare substring) AND that are
# NOT this step's own in-flight work. It never issues a global kill. It prints
# `reaped: N` like the .sh reaper.
#
# StepStart (SPEC "reaper-deterministic-age-guard", Spec-AC-05, CONTRACT PARITY
# ONLY — not a bug fix): Get-ReapCandidates already uses each process's real
# per-process CreationDate (not a truncated `ps etime` string), so it never had
# the whole-second-rounding flake the .sh reaper's epoch mode exists to fix.
# An optional -StepStart [datetime] (sourced from AAI_REAP_STEP_START_EPOCH by
# the dispatcher) spares CreationDate >= StepStart - GraceSeconds and reaps
# older matches, so a Windows step owner passing the SAME env var the .sh
# reaper consumes gets consistent cross-platform semantics. Absent -StepStart
# is byte-identical to today's -MinAgeSeconds path (additive, back-compat).
#
# Resolution (mirrors aai-run-tests.ps1, Spec-AC-01): when WSL is usable, a
# WSL-launched test run's processes live INSIDE WSL and are invisible to the
# Windows process table — this delegates that half of the sweep to the
# existing `.aai/scripts/aai-reap-tests.sh` running inside WSL. The NATIVE
# path below (real Windows process inspection, Spec-AC-04's actual contract)
# ALWAYS also runs, because a Git-Bash-launched run's processes (bash.exe,
# node.exe, ...) ARE ordinary Windows processes regardless of which
# interpreter launched them.
#
# Platform matrix: see aai-run-tests.ps1 header / docs/TECHNOLOGY.md
# (Spec-AC-07 — the 5-row matrix is kept identical across all three).
#
# Dot-sourcing this file (`. $path`) defines the functions WITHOUT running
# Main (see the `$MyInvocation.InvocationName -ne '.'` guard at the bottom) —
# tests/skills/aai-win-dispatch.Tests.ps1 relies on this to mock the process
# snapshot and kill primitives.
#
# Usage:
#   pwsh -File .aai/scripts/aai-reap-tests.ps1
#
# Environment:
#   AAI_REAP_WORKSPACE        workspace path to scope by (default: current directory)
#   AAI_REAP_MIN_AGE_SECS     minimum process age in seconds to be eligible (default 0);
#                             used only when AAI_REAP_STEP_START_EPOCH is absent/invalid
#   AAI_REAP_STEP_START_EPOCH optional step-start Unix epoch seconds (mirrors the .sh
#                             reaper's contract). When a valid positive integer, activates
#                             the StepStart path: spares a process whose CreationDate is
#                             >= (StepStart - AAI_REAP_GRACE_SECS), reaps older matches.
#                             Absent/invalid falls back to AAI_REAP_MIN_AGE_SECS unchanged.
#   AAI_REAP_GRACE_SECS       StepStart grace window in seconds (default 2). Ignored
#                             unless AAI_REAP_STEP_START_EPOCH is active.
#
# CANNOT VERIFY ON THIS HOST: real Windows process enumeration/kill semantics.
# Covered by the Manual verification protocol (SPEC-0046 MV-2), not by CI.

# ---- Probes (shared shape with aai-run-tests.ps1; kept independent on purpose
#      so each dispatcher parses/tests standalone — see that file's header for
#      the rationale behind NOT sharing a module). --------------------------

function Test-WslPresent {
  [CmdletBinding()] param()
  return [bool](Get-Command wsl.exe -ErrorAction SilentlyContinue)
}

function Test-WslUsable {
  [CmdletBinding()] param()
  if (-not (Test-WslPresent)) { return $false }
  try {
    $proc = Start-Process -FilePath 'wsl.exe' -ArgumentList @('-e', 'true') -NoNewWindow -PassThru
    $completed = $proc.WaitForExit(5000)
    if (-not $completed) {
      try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
      return $false
    }
    return ($proc.ExitCode -eq 0)
  } catch {
    return $false
  }
}

function Get-GitBashCandidates {
  [CmdletBinding()] param()
  $candidates = @()
  if ($env:ProgramFiles) { $candidates += (Join-Path $env:ProgramFiles 'Git\bin\bash.exe') }
  $pf86 = ${env:ProgramFiles(x86)}
  if ($pf86) { $candidates += (Join-Path $pf86 'Git\bin\bash.exe') }
  $gitCmd = Get-Command git.exe -ErrorAction SilentlyContinue
  if ($gitCmd) {
    try {
      $execPath = & git.exe --exec-path 2>$null
      if ($execPath) {
        $gitRoot = Split-Path (Split-Path (Split-Path $execPath -Parent) -Parent) -Parent
        if ($gitRoot) { $candidates += (Join-Path $gitRoot 'bin\bash.exe') }
      }
    } catch {}
  }
  $pathBash = Get-Command bash.exe -ErrorAction SilentlyContinue -All
  if ($pathBash) {
    foreach ($b in $pathBash) { $candidates += $b.Source }
  }
  return $candidates
}

function Test-IsWslBashShim {
  [CmdletBinding()] param([string]$Path)
  return ($Path -match '(?i)\\System32\\bash\.exe$')
}

function Find-GitBash {
  [CmdletBinding()] param()
  foreach ($c in (Get-GitBashCandidates)) {
    if (-not $c) { continue }
    if (Test-IsWslBashShim -Path $c) { continue }
    if (Test-Path -LiteralPath $c -PathType Leaf) { return $c }
  }
  return $null
}

function Resolve-Interpreter {
  [CmdletBinding()] param()
  if (Test-WslUsable) {
    return @{ Mode = 'wsl' }
  }
  $bash = Find-GitBash
  if ($bash) {
    return @{ Mode = 'gitbash'; BashPath = $bash }
  }
  return @{ Mode = 'error' }
}

# ---- Native reap (Spec-AC-04) -------------------------------------------------

function Get-ProcessSnapshot {
  # Real Windows process table: pid, full command line, creation time. Kept as
  # its own function ONLY so tests can inject a fixture snapshot.
  [CmdletBinding()] param()
  Get-CimInstance Win32_Process |
    Select-Object -Property @{Name = 'ProcessId'; Expression = { $_.ProcessId } },
                             @{Name = 'CommandLine'; Expression = { $_.CommandLine } },
                             @{Name = 'CreationDate'; Expression = { $_.CreationDate } }
}

function Get-ReapCandidates {
  # Guard 1: vitest/esbuild token. Guard 2: workspace path as a proper
  # path-separator-anchored segment (never a bare substring — a workspace at
  # C:\ws\myproject must NOT match a sibling at C:\ws\myproject-fork). Guard 3
  # (age): two modes —
  #   - StepStart mode (optional -StepStart supplied): spare CreationDate >=
  #     (StepStart - GraceSeconds); reap older. Contract parity with the .sh
  #     reaper's epoch mode (see file header) — CreationDate is a REAL
  #     per-process timestamp here, not a truncated `ps etime` string, so this
  #     mode never had the whole-second rounding flake to begin with.
  #   - Legacy mode (no -StepStart, the default): age >= MinAgeSeconds, exactly
  #     today's behavior — spares a concurrent sibling's just-started run.
  [CmdletBinding()]
  param(
    [AllowEmptyCollection()]
    [Parameter(Mandatory)][object[]]$Snapshot,
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][int]$MinAgeSeconds,
    [Parameter(Mandatory)][datetime]$Now,
    [datetime]$StepStart,
    [int]$GraceSeconds = 2
  )
  $ws = $Workspace.TrimEnd('\', '/')
  $wsPattern = [regex]::Escape($ws) + '[\\/]'
  $useStepStart = $PSBoundParameters.ContainsKey('StepStart')
  $threshold = $null
  if ($useStepStart) { $threshold = $StepStart.AddSeconds(-$GraceSeconds) }
  $out = @()
  foreach ($p in $Snapshot) {
    if (-not $p.CommandLine) { continue }
    if ($p.CommandLine -notmatch '(?i)(vitest|esbuild)') { continue }
    if ($p.CommandLine -notmatch $wsPattern) { continue }
    if ($useStepStart) {
      if ($p.CreationDate -ge $threshold) { continue }
    } else {
      $age = ($Now - $p.CreationDate).TotalSeconds
      if ($age -lt $MinAgeSeconds) { continue }
    }
    $out += $p
  }
  return $out
}

function Stop-ProcessTree {
  [CmdletBinding()] param([Parameter(Mandatory)][int]$ProcessId)
  & taskkill.exe /PID $ProcessId /T /F 2>$null | Out-Null
}

function Invoke-ReapNative {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][int]$MinAgeSeconds,
    [Nullable[datetime]]$StepStart = $null,
    [int]$GraceSeconds = 2
  )
  $snapshot = @(Get-ProcessSnapshot)
  $now = Get-Date
  $candidateArgs = @{
    Snapshot      = $snapshot
    Workspace     = $Workspace
    MinAgeSeconds = $MinAgeSeconds
    Now           = $now
  }
  if ($null -ne $StepStart) {
    $candidateArgs.StepStart = $StepStart
    $candidateArgs.GraceSeconds = $GraceSeconds
  }
  $candidates = Get-ReapCandidates @candidateArgs
  foreach ($c in $candidates) {
    Stop-ProcessTree -ProcessId $c.ProcessId
  }
  Write-Output "reaped: $($candidates.Count)"
  return $candidates.Count
}

# ---- WSL-delegated reap (the WSL-side process table is invisible to Windows) --

function Get-ReapWslDelegationArgs {
  # NB-C remediation: mirrors aai-run-tests.ps1's Get-WslDelegationArgs — pass
  # the SAME AAI_REAP_WORKSPACE / AAI_REAP_MIN_AGE_SECS overrides this
  # dispatcher resolved into the WSL-side reaper via `env`, exactly like the
  # run dispatcher passes AAI_TEST_TIMEOUT. Without this the WSL half of the
  # sweep silently runs with its own defaults (PWD, MIN_AGE=0) instead of the
  # operator's overrides — e.g. an operator-set AAI_REAP_MIN_AGE_SECS meant to
  # spare a concurrent sibling's just-started run would be dropped, and the
  # WSL-delegated half could reap that sibling's fresh processes.
  #
  # StepStart parity: forward AAI_REAP_STEP_START_EPOCH / AAI_REAP_GRACE_SECS
  # RAW (as this dispatcher received them, unvalidated) so the WSL-side
  # aai-reap-tests.sh applies its OWN validation (SPEC-AC-03 fail-safe) —
  # never re-derived/re-formatted here. Omitted entirely when
  # StepStartEpoch is absent/empty, so a step owner not opting in keeps the
  # WSL delegate on its existing AAI_REAP_MIN_AGE_SECS path byte-for-byte.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$ShScriptPath,
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][int]$MinAgeSeconds,
    [string]$StepStartEpoch,
    [string]$GraceSeconds,
    [scriptblock]$WslPathResolver
  )
  if ($WslPathResolver) {
    $wslScript = & $WslPathResolver $ShScriptPath
  } else {
    $result = & wsl.exe wslpath -a $ShScriptPath 2>$null
    $wslScript = if ($LASTEXITCODE -eq 0 -and $result) { $result | Select-Object -First 1 } else { $ShScriptPath }
  }
  $envArgs = @("AAI_REAP_WORKSPACE=$Workspace", "AAI_REAP_MIN_AGE_SECS=$MinAgeSeconds")
  if ($StepStartEpoch) {
    $envArgs += "AAI_REAP_STEP_START_EPOCH=$StepStartEpoch"
    if ($GraceSeconds) { $envArgs += "AAI_REAP_GRACE_SECS=$GraceSeconds" }
  }
  return (@('-e', 'env') + $envArgs + @($wslScript))
}

function Invoke-ReapWslProcess {
  [CmdletBinding()] param([Parameter(Mandatory)][string[]]$Arguments)
  & wsl.exe @Arguments
}

function Invoke-ReapViaWsl {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$ShScriptPath,
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][int]$MinAgeSeconds,
    [string]$StepStartEpoch,
    [string]$GraceSeconds
  )
  try {
    $wslArgs = Get-ReapWslDelegationArgs -ShScriptPath $ShScriptPath -Workspace $Workspace -MinAgeSeconds $MinAgeSeconds `
      -StepStartEpoch $StepStartEpoch -GraceSeconds $GraceSeconds
    Invoke-ReapWslProcess -Arguments $wslArgs
  } catch {
    Write-Output 'reaped: 0'
  }
}

# ---- Dispatch -------------------------------------------------------------------

function Get-EffectiveMinAge {
  [CmdletBinding()] param([string]$Raw)
  if ($Raw -and ($Raw -match '^[0-9]+$')) { return [int]$Raw }
  return 0
}

function Get-EffectiveGraceSeconds {
  [CmdletBinding()] param([string]$Raw)
  if ($Raw -and ($Raw -match '^[0-9]+$')) { return [int]$Raw }
  return 2
}

function Get-StepStartFromEpoch {
  # Mirrors the .sh reaper's EPOCH MODE validity rule (Spec-AC-03 fail-safe):
  # valid iff all-digits, > 0, and NOT in the future relative to $Now. Any
  # other shape (absent, empty, non-integer, negative, zero, future/clock
  # skew) returns $null so callers fall back to the legacy MinAgeSeconds path
  # — never a global kill.
  [CmdletBinding()]
  param([string]$Raw, [Parameter(Mandatory)][datetime]$Now)
  if (-not $Raw) { return $null }
  if ($Raw -notmatch '^[0-9]+$') { return $null }
  $epochSeconds = [int64]0
  if (-not [int64]::TryParse($Raw, [ref]$epochSeconds)) { return $null }
  if ($epochSeconds -le 0) { return $null }
  $candidate = [DateTimeOffset]::FromUnixTimeSeconds($epochSeconds).LocalDateTime
  if ($candidate -gt $Now) { return $null }
  return $candidate
}

function Invoke-ReapDispatch {
  [CmdletBinding()] param()
  $workspace = if ($env:AAI_REAP_WORKSPACE) { $env:AAI_REAP_WORKSPACE } else { (Get-Location).Path }
  $minAge = Get-EffectiveMinAge -Raw $env:AAI_REAP_MIN_AGE_SECS
  $graceSeconds = Get-EffectiveGraceSeconds -Raw $env:AAI_REAP_GRACE_SECS
  $stepStart = Get-StepStartFromEpoch -Raw $env:AAI_REAP_STEP_START_EPOCH -Now (Get-Date)
  $resolution = Resolve-Interpreter
  if ($resolution.Mode -eq 'wsl') {
    # NB-C remediation: the WSL delegate prints its own authoritative
    # "reaped: N" line (env-scoped per Get-ReapWslDelegationArgs above). The
    # native pass below still ALWAYS runs too — a Git-Bash-launched run's
    # processes are ordinary Windows processes regardless of interpreter
    # choice — but its own summary line is suppressed here so the operator
    # sees exactly ONE "reaped: N" line per invocation, matching the .sh
    # reaper's single-line output shape (the delegate's output is
    # authoritative). Write-Host so the line reaches the console even though
    # it's nested inside the `exit (Invoke-ReapDispatch)` expression below.
    Invoke-ReapViaWsl -ShScriptPath (Join-Path $PSScriptRoot 'aai-reap-tests.sh') -Workspace $workspace -MinAgeSeconds $minAge `
      -StepStartEpoch $env:AAI_REAP_STEP_START_EPOCH -GraceSeconds $env:AAI_REAP_GRACE_SECS | Write-Host
    Invoke-ReapNative -Workspace $workspace -MinAgeSeconds $minAge -StepStart $stepStart -GraceSeconds $graceSeconds | Out-Null
  } else {
    # No WSL delegate ran: the native pass IS the summary of record — let its
    # "reaped: N" line (and only that line, filtering out the trailing raw
    # count Invoke-ReapNative's `return` also emits) reach the operator.
    Invoke-ReapNative -Workspace $workspace -MinAgeSeconds $minAge -StepStart $stepStart -GraceSeconds $graceSeconds |
      Where-Object { $_ -is [string] } | Write-Host
  }
  return 0
}

if ($MyInvocation.InvocationName -ne '.') {
  exit (Invoke-ReapDispatch)
}
