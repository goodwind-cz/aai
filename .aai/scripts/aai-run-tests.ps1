#!/usr/bin/env pwsh
#
# aai-run-tests.ps1 — Windows entry point for aai-run-tests.sh (SPEC-0046 /
# ISSUE-0009). Deterministically resolves a POSIX interpreter and delegates to
# the existing .sh wrapper (SPEC-0009's killable process-group contract), so
# the loop/skills invoke ONE command regardless of host OS.
#
# Resolution order (Spec-AC-01), fixed and deterministic for identical probe
# results — never a hang, never a raw wsl.exe error surfacing to the caller:
#   1. Usable WSL       — wsl.exe present AND a probe command succeeds in the
#                          default distro. wsl.exe present but NO usable distro
#                          counts as WSL-absent and falls through to (2).
#   2. Native Git Bash   — fixed candidate list, first hit wins:
#                            $env:ProgramFiles\Git\bin\bash.exe
#                            ${env:ProgramFiles(x86)}\Git\bin\bash.exe
#                            bash.exe derived from `git.exe --exec-path`
#                            PATH bash.exe that is NOT the WSL System32 shim
#   3. Named failure      — AAI-ENV-ERROR (Spec-AC-02), exit 78.
#
# Platform matrix (Spec-AC-07 — kept identical across this header,
# aai-reap-tests.ps1, and docs/TECHNOLOGY.md):
#   macOS                              - full SPEC-0009 contract (unaffected by this file)
#   Linux                              - full SPEC-0009 contract (unaffected by this file)
#   Windows + WSL                      - full contract via WSL delegation (this dispatcher)
#   Windows + Git-Bash-only (no WSL)   - DEGRADED: launched-tree taskkill /T only; detached/
#                                         reparented descendants NOT guaranteed reaped (no
#                                         POSIX sessions on Windows) — weaker than SPEC-0009
#   Windows, neither WSL nor Git Bash  - AAI-ENV-ERROR: ..., exit 78; no test run attempted
#
# Git-Bash run contract (Spec-AC-03, narrower guarantee stated verbatim): on
# the Git-Bash path this dispatcher launches `.aai/scripts/aai-run-tests.sh
# <cmd...>` under the resolved bash.exe, passes AAI_TEST_TIMEOUT through,
# propagates the child's REAL exit code, and on timeout kills the LAUNCHED
# PROCESS TREE via Windows `taskkill /T /F` and exits 124. This covers the
# launched tree only — a detached/reparented descendant is NOT guaranteed
# reaped, because Windows has no POSIX process-group/session semantics. That
# is explicitly WEAKER than the SPEC-0009 macOS/Linux contract; never assume
# it is equivalent.
#
# Every probe/launch/kill primitive below is its own small function so Pester
# (tests/skills/aai-win-dispatch.Tests.ps1) can override each branch. Dot-
# sourcing this file (`. $path`) defines the functions WITHOUT running Main —
# only a direct invocation (`pwsh -File ...`) runs Main, via the
# `$MyInvocation.InvocationName -ne '.'` guard at the bottom.
#
# Usage:
#   pwsh -File .aai/scripts/aai-run-tests.ps1 <command> [args...]
#
# Environment:
#   AAI_TEST_TIMEOUT  timeout in seconds (default 300; non-integer or <=0 -> 300;
#                      same coercion as the .sh wrapper)
#
# CANNOT VERIFY ON THIS HOST: real WSL delegation, real Git-Bash/MSYS process
# semantics, real `taskkill /T` tree-kill completeness. Covered by the Manual
# verification protocol (SPEC-0046 MV-1..MV-3), not by this repo's CI.
#
# Deliberately NO param() block: a declared -Command parameter would collide
# with PowerShell's own -c/-Command prefix-abbreviation on the CLI (e.g. a
# caller passing `sh -c "..."` would have `-c` mis-bound as this script's
# parameter). Plain `$args` sidesteps that entirely.

# ---- Probes (WSL) ------------------------------------------------------------

function Test-WslPresent {
  [CmdletBinding()] param()
  return [bool](Get-Command wsl.exe -ErrorAction SilentlyContinue)
}

function Test-WslUsable {
  # wsl.exe present AND a probe command succeeds in the default distro. A
  # present-but-no-distro wsl.exe answers quickly with a non-zero exit; the
  # 5s watchdog guards against any prompt/hang so this NEVER blocks the caller.
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

# ---- Probes (native Git Bash) -------------------------------------------------

function Get-GitBashCandidates {
  # Fixed, ordered, UNFILTERED candidate list (Spec-AC-01). Filtering out the
  # WSL System32 shim happens in Find-GitBash, not here, so each concern stays
  # independently testable.
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
        # .../Git/mingw64/libexec/git-core -> .../Git/bin/bash.exe
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
  # Windows ships a `bash.exe` shim under System32 that launches WSL — never
  # treat it as a native Git Bash candidate (Spec-AC-01).
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

# ---- Resolution ---------------------------------------------------------------

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

function Write-EnvError {
  # Spec-AC-02: EXACTLY ONE stderr line, naming both probed options plus a
  # remediation hint.
  [CmdletBinding()] param()
  [Console]::Error.WriteLine(
    'AAI-ENV-ERROR: no usable POSIX interpreter found (probed: WSL, Git for Windows). ' +
    'Install WSL (wsl --install) or Git for Windows (https://git-scm.com/download/win), ' +
    'or run this from inside an existing WSL/Git Bash shell.'
  )
}

# ---- Timeout coercion (parity with the .sh wrapper) ---------------------------

function Get-EffectiveTimeout {
  # NB-B remediation: '^[0-9]+$' alone admits digit strings arbitrarily beyond
  # Int32 range (e.g. AAI_TEST_TIMEOUT=99999999999, a fat-fingered paste); a
  # bare [int]$Raw cast on those throws an overflow conversion error instead
  # of coercing to the safe 300s default, unlike the .sh wrapper's coercion.
  # Parse into Int64 first (TryParse never throws) and only accept the value
  # if it also fits Int32 — everything downstream (Wait-ProcessWithTimeout's
  # WaitForExit(ms), Start-GitBashProcess's env var) is Int32-typed, so a
  # value that doesn't fit is exactly as unusable as a non-integer one and
  # falls back to 300 the same way.
  [CmdletBinding()] param([string]$Raw)
  if ($Raw -and ($Raw -match '^[0-9]+$')) {
    $parsed = [long]0
    if ([long]::TryParse($Raw, [ref]$parsed) -and $parsed -gt 0 -and $parsed -le [int]::MaxValue) {
      return [int]$parsed
    }
  }
  return 300
}

# ---- WSL launch path ------------------------------------------------------------

function ConvertTo-WslPath {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$WindowsPath)
  try {
    $result = & wsl.exe wslpath -a $WindowsPath 2>$null
    if ($LASTEXITCODE -eq 0 -and $result) { return ($result | Select-Object -First 1) }
  } catch {}
  return $WindowsPath
}

function Get-WslDelegationArgs {
  # Returns the argv array for wsl.exe. `-e` executes argv directly (no shell
  # interpretation), so command arguments pass through verbatim with zero
  # quoting/injection surface; `env VAR=val cmd...` sets AAI_TEST_TIMEOUT for
  # the delegated .sh without needing a login shell.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string[]]$Command,
    [Parameter(Mandatory)][string]$ShScriptPath,
    [Parameter(Mandatory)][int]$Timeout,
    [scriptblock]$WslPathResolver
  )
  if ($WslPathResolver) {
    $wslScript = & $WslPathResolver $ShScriptPath
  } else {
    $wslScript = ConvertTo-WslPath -WindowsPath $ShScriptPath
  }
  return @('-e', 'env', "AAI_TEST_TIMEOUT=$Timeout", $wslScript) + $Command
}

function Invoke-WslProcess {
  [CmdletBinding()] param([Parameter(Mandatory)][string[]]$Arguments)
  & wsl.exe @Arguments
  return $LASTEXITCODE
}

function Invoke-ViaWsl {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string[]]$Command,
    [Parameter(Mandatory)][string]$ShScriptPath,
    [Parameter(Mandatory)][int]$Timeout
  )
  $wslArgs = Get-WslDelegationArgs -Command $Command -ShScriptPath $ShScriptPath -Timeout $Timeout
  return Invoke-WslProcess -Arguments $wslArgs
}

# ---- Git-Bash launch path -------------------------------------------------------

function Start-GitBashProcess {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$BashPath,
    [Parameter(Mandatory)][string[]]$ScriptArgs,
    [Parameter(Mandatory)][int]$Timeout
  )
  $env:AAI_TEST_TIMEOUT = "$Timeout"
  return Start-Process -FilePath $BashPath -ArgumentList $ScriptArgs -NoNewWindow -PassThru
}

function Wait-ProcessWithTimeout {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$Process,
    [Parameter(Mandatory)][int]$TimeoutSeconds
  )
  return $Process.WaitForExit($TimeoutSeconds * 1000)
}

function Get-OuterWatchdogGraceSeconds {
  # NB-A remediation: the inner aai-run-tests.sh watchdog polls the command
  # once per second (up to 1s slack) and, on EVERY exit path, ALWAYS re-reaps
  # the process group afterwards with a further TERM-then-sleep-1-then-KILL
  # grace (see aai-run-tests.sh's "poll ... sleep 1" watchdog loop and its
  # "ALWAYS reap the whole group on every exit path" block, each `sleep 1`).
  # So a command that finishes right at the AAI_TEST_TIMEOUT boundary can
  # legitimately still be inside that reap-grace sleep up to ~1-2s later
  # before bash.exe itself exits. The OUTER Wait-ProcessWithTimeout below must
  # never race that: it waits AAI_TEST_TIMEOUT + this fixed grace, so a
  # PASSING run near the boundary is never force-killed and misreported as
  # 124. This grace applies ONLY to the outer deadline — the env var handed
  # to the inner .sh (AAI_TEST_TIMEOUT itself) is untouched.
  [CmdletBinding()] param()
  return 5
}

function Stop-ProcessTree {
  # Windows taskkill /T /F semantics — the launched-tree-only guarantee
  # (Spec-AC-03); reparented/detached descendants are NOT covered.
  [CmdletBinding()] param([Parameter(Mandatory)][int]$ProcessId)
  & taskkill.exe /PID $ProcessId /T /F 2>$null | Out-Null
}

function Invoke-ViaGitBash {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$BashPath,
    [Parameter(Mandatory)][string[]]$Command,
    [Parameter(Mandatory)][string]$ShScriptPath,
    [Parameter(Mandatory)][int]$Timeout
  )
  $bashArgs = @($ShScriptPath) + $Command
  $proc = Start-GitBashProcess -BashPath $BashPath -ScriptArgs $bashArgs -Timeout $Timeout
  $outerTimeout = $Timeout + (Get-OuterWatchdogGraceSeconds)
  $completed = Wait-ProcessWithTimeout -Process $proc -TimeoutSeconds $outerTimeout
  if (-not $completed) {
    Stop-ProcessTree -ProcessId $proc.Id
    return 124
  }
  return $proc.ExitCode
}

# ---- Dispatch -------------------------------------------------------------------

function Invoke-Dispatch {
  [CmdletBinding()] param([string[]]$Command)
  if (-not $Command -or $Command.Count -eq 0) {
    [Console]::Error.WriteLine('usage: aai-run-tests.ps1 <command> [args...]')
    return 2
  }
  $shScriptPath = Join-Path $PSScriptRoot 'aai-run-tests.sh'
  $timeout = Get-EffectiveTimeout -Raw $env:AAI_TEST_TIMEOUT
  $resolution = Resolve-Interpreter
  switch ($resolution.Mode) {
    'wsl' { return Invoke-ViaWsl -Command $Command -ShScriptPath $shScriptPath -Timeout $timeout }
    'gitbash' { return Invoke-ViaGitBash -BashPath $resolution.BashPath -Command $Command -ShScriptPath $shScriptPath -Timeout $timeout }
    default {
      Write-EnvError
      return 78
    }
  }
}

if ($MyInvocation.InvocationName -ne '.') {
  exit (Invoke-Dispatch -Command $args)
}
