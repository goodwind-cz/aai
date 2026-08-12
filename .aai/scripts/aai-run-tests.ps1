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
# Exit-code contract (CHANGE-0133 / SPEC-DRAFT-spec-ps1-wrapper-path-dup):
#   0/N   - the wrapped command RAN and this is its own real exit code.
#   2     - usage error (no command given); never confused with the codes below.
#   78    - no usable POSIX interpreter (sysexits EX_CONFIG); AAI-ENV-ERROR on
#           stderr; no test run attempted (see Resolution order above).
#   124   - a process that RAN and was killed at AAI_TEST_TIMEOUT (GNU-timeout
#           convention). NEVER produced for a command that never started.
#   125   - the dispatcher itself could not START the command — a spawn/
#           infrastructure failure (e.g. a duplicate-casing Path/PATH
#           dictionary collision reaching Start-Process) — one AAI-SPAWN-ERROR
#           line on stderr names the real exception and the branch (WSL or
#           Git Bash). The wait logic is never reached with a null process.
#
# Environment canonicalization (Spec-AC-01/Spec-AC-02): before ANY spawn — the
# WSL probe (Test-WslUsable itself calls Start-Process) included —
# Set-CanonicalProcessEnvironment collapses every OrdinalIgnoreCase-duplicate
# environment key (the field defect: a process environment carrying both
# `Path` and `PATH`, invisible through the case-insensitive $env: drive but
# fatal to the OrdinalIgnoreCase dictionary .NET builds for a child process)
# down to one canonical key per collision group, via
# [Environment]::SetEnvironmentVariable — never the $env: drive.
#
# Git-Bash run contract (Spec-AC-03, narrower guarantee stated verbatim): on
# the Git-Bash path this dispatcher launches `.aai/scripts/aai-run-tests.sh
# <cmd...>` under the resolved bash.exe, passes AAI_TEST_TIMEOUT through,
# propagates the child's REAL exit code, and on timeout kills the LAUNCHED
# PROCESS TREE via Windows `taskkill /T /F` and exits 124. This covers the
# launched tree only — a detached/reparented descendant is NOT guaranteed
# reaped, because Windows has no POSIX process-group/session semantics. That
# is explicitly WEAKER than the SPEC-0009 macOS/Linux contract; never assume
# it is equivalent. A failure to SPAWN at all (Start-Process throws or
# returns no process object) never reaches this contract: it exits 125 with
# an AAI-SPAWN-ERROR line instead (Spec-AC-03/Spec-AC-04).
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

function Get-ProcessEnvironmentSnapshot {
  # Thin, mockable wrapper around the REAL process environment. MUST read
  # [Environment]::GetEnvironmentVariables() — NEVER the $env: drive, which is
  # exactly the case-insensitive view that HIDES a Path/PATH duplicate (the
  # field defect this canonicalizer closes).
  [CmdletBinding()] param()
  return [Environment]::GetEnvironmentVariables()
}

function Set-EnvironmentVariableRaw {
  # Thin, mockable wrapper around the single native primitive that mutates the
  # CURRENT process's environment block (never Start-Process -Environment —
  # that overload is 7.4+ only and out of bounds under the Windows PowerShell
  # 5.1 compatibility gate, Article 3). $Value = $null removes the variable.
  #
  # Cross-runtime defense-in-depth: on at least one real .NET/Unix combination
  # observed in this repo's own CI-equivalent host, [Environment]::
  # SetEnvironmentVariable(name, $null) leaves the key present with an empty
  # value instead of truly removing it, which still collides in a later
  # OrdinalIgnoreCase dictionary build. When the primary call demonstrably did
  # not remove the EXACT key, fall back to the env-provider remove targeted at
  # that literal, already-known name — proven exact on THIS proof's own
  # runtime (Unix pwsh / .NET 10: removing 'PATH' leaves a co-existing 'Path'
  # survivor untouched, verified empirically), but Windows exactness is NOT
  # established by that proof — both the Win32 and Env: providers there match
  # names case-insensitively, which is the same defect CR-1 closes via the
  # removal-then-re-read-then-write ordering in Set-CanonicalProcessEnvironment
  # rather than via this primitive's precision — never a case-insensitive scan
  # standing in for detection.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Name,
    [AllowNull()][string]$Value
  )
  [Environment]::SetEnvironmentVariable($Name, $Value)
  # NB: PowerShell coerces an explicit $null argument into "" for a [string]-
  # typed parameter (a well-known binding quirk) — [string]::IsNullOrEmpty
  # is the delete-intent test that survives that coercion, matching .NET's
  # own documented deletion semantics (null/empty/whitespace-only deletes).
  if ([string]::IsNullOrEmpty($Value) -and (Get-ProcessEnvironmentSnapshot).ContainsKey($Name)) {
    Remove-Item -LiteralPath "Env:\$Name" -ErrorAction SilentlyContinue
  }
}

function Get-CanonicalEnvironmentMap {
  # Pure, side-effect-free (Spec-AC-01). Groups keys by OrdinalIgnoreCase;
  # within a group members are ordered by [StringComparer]::Ordinal. The PATH
  # group survives under the literal key 'Path' with the ordinal-ordered
  # union of the group's values (split on [IO.Path]::PathSeparator, empty
  # segments dropped, duplicate directory entries dropped preserving first
  # occurrence). Every other collision group survives under its ordinal-first
  # member's key AND that key's value, unchanged — concatenating unrelated
  # values would corrupt them. A collision-free map is returned unchanged, and
  # the output never contains a residual collision, so normalizing twice is
  # identical to normalizing once.
  [CmdletBinding()]
  param([Parameter(Mandatory)][System.Collections.IDictionary]$Environment)

  $groupOrder = [System.Collections.Generic.List[string]]::new()
  $groups = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new(
    [StringComparer]::OrdinalIgnoreCase)
  foreach ($key in $Environment.Keys) {
    $k = [string]$key
    if (-not $groups.ContainsKey($k)) {
      $groups[$k] = [System.Collections.Generic.List[string]]::new()
      $groupOrder.Add($k)
    }
    $groups[$k].Add($k)
  }

  $result = [ordered]@{}
  foreach ($groupKey in $groupOrder) {
    $members = $groups[$groupKey].ToArray()
    [Array]::Sort($members, [StringComparer]::Ordinal)
    # The PATH-merge rule applies only to a GENUINE collision (more than one
    # casing actually present) — a lone 'PATH' (the ordinary POSIX spelling,
    # never colliding with anything) must survive completely unchanged, same
    # as any other single-member group, or the "already-clean environment is
    # a NO-OP" edge case would regress on every normal POSIX host.
    $isPathGroup = $false
    if ($members.Count -gt 1) {
      foreach ($m in $members) {
        if ([string]::Equals($m, 'Path', [System.StringComparison]::OrdinalIgnoreCase)) { $isPathGroup = $true; break }
      }
    }
    if ($isPathGroup) {
      $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
      $union = [System.Collections.Generic.List[string]]::new()
      foreach ($m in $members) {
        $val = [string]$Environment[$m]
        if ([string]::IsNullOrEmpty($val)) { continue }
        foreach ($seg in $val.Split([IO.Path]::PathSeparator)) {
          if ([string]::IsNullOrEmpty($seg)) { continue }
          if ($seen.Add($seg)) { $union.Add($seg) }
        }
      }
      $result['Path'] = [string]::Join([IO.Path]::PathSeparator, $union)
    } else {
      $first = $members[0]
      $result[$first] = $Environment[$first]
    }
  }
  return $result
}

function Set-CanonicalProcessEnvironment {
  # Applies Get-CanonicalEnvironmentMap to the REAL current-process
  # environment (Spec-AC-02): discards every casing that did not survive via
  # Set-EnvironmentVariableRaw($name, $null), then sets each survivor whose
  # value actually changed. Returns the list of DISCARDED (collapsed) names.
  # On an already-clean environment (no collision groups, no value drift)
  # this makes ZERO Set-EnvironmentVariableRaw calls — the common path never
  # regresses.
  [CmdletBinding()] param()
  $current = Get-ProcessEnvironmentSnapshot
  $canonical = Get-CanonicalEnvironmentMap -Environment $current
  $survivors = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($k in $canonical.Keys) { [void]$survivors.Add([string]$k) }

  $collapsed = [System.Collections.Generic.List[string]]::new()
  foreach ($existingKey in @($current.Keys)) {
    $ek = [string]$existingKey
    if (-not $survivors.Contains($ek)) {
      Set-EnvironmentVariableRaw -Name $ek -Value $null
      $collapsed.Add($ek)
    }
  }
  # CR-1 (review 20260812T133652Z): a case-insensitive removal primitive — the
  # only kind available on Windows — can take a SURVIVOR's own entry when the
  # survivor shares a name-insensitive casing with a just-discarded key (e.g.
  # removing 'Temp' can also erase 'TEMP'). Deciding the write below against
  # the PRE-removal $current then wrongly no-ops whenever the canonical value
  # equals the survivor's pre-removal value — exactly every non-PATH group,
  # and any PATH group whose other casings add no new segments. Re-read the
  # REAL post-removal state before comparing, but ONLY when a removal
  # actually happened: on an already-clean environment $collapsed is empty,
  # so this branch is skipped and the zero-Set-EnvironmentVariableRaw-calls
  # no-op contract stays byte-identical (RAW_SET_CALLS=0).
  if ($collapsed.Count -gt 0) {
    $current = Get-ProcessEnvironmentSnapshot
  }
  foreach ($k in $canonical.Keys) {
    $kk = [string]$k
    $newVal = [string]$canonical[$k]
    $oldVal = if ($current.ContainsKey($kk)) { [string]$current[$kk] } else { $null }
    if ($oldVal -ne $newVal) {
      Set-EnvironmentVariableRaw -Name $kk -Value $newVal
    }
  }
  return $collapsed
}

function Write-SpawnError {
  # Spec-AC-03/Spec-AC-04: EXACTLY ONE stderr line, naming the failing branch
  # (literal token WSL or Git Bash) and the real exception message. Mirrors
  # the single-line discipline of Write-EnvError.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Branch,
    [Parameter(Mandatory)][string]$Message
  )
  [Console]::Error.WriteLine("AAI-SPAWN-ERROR: [$Branch] $Message")
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
  try {
    # Invoke-WslProcess is synchronous (`& wsl.exe @Arguments`) — there is no
    # separate process object to reap on failure, so Stop-ProcessTree is never
    # invoked on this branch (Spec-AC-04): a delegation that RAN returns its
    # own $LASTEXITCODE unchanged; a throw here means the delegation never ran.
    return Invoke-WslProcess -Arguments $wslArgs
  } catch {
    Write-SpawnError -Branch 'WSL' -Message $_.Exception.Message
    return 125
  }
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
  # -ErrorAction Stop (Spec-AC-03): a non-terminating Start-Process error
  # (e.g. the OrdinalIgnoreCase Path/PATH dictionary collision this scope
  # fixes) becomes a catchable exception instead of silently returning $null.
  return Start-Process -FilePath $BashPath -ArgumentList $ScriptArgs -NoNewWindow -PassThru -ErrorAction Stop
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
  # Spec-AC-03/Spec-AC-04: a throw OR a $null/pid-less return from the spawn
  # primitive writes the spawn error and returns 125 WITHOUT ever calling
  # Wait-ProcessWithTimeout (the wait logic must never see $null); a throw
  # raised AFTER a live process object exists is reaped in `finally` (guarded
  # on a non-null pid, so a spawn that produced no object never reaches
  # Stop-ProcessTree at all); the timeout path below is byte-equivalent to
  # before this change.
  # CR-5 (review 20260812T133652Z): this same catch also fires for a throw
  # raised by Wait-ProcessWithTimeout or by reading $proc.ExitCode AFTER the
  # command genuinely started — those cases still print AAI-SPAWN-ERROR even
  # though the command DID start, so the message names the failing branch and
  # exception, not "never started"; the process is still reaped above, so
  # this is a diagnostic-wording caveat only, never a functional gap.
  $bashArgs = @($ShScriptPath) + $Command
  $proc = $null
  $spawnFailed = $false
  try {
    $proc = Start-GitBashProcess -BashPath $BashPath -ScriptArgs $bashArgs -Timeout $Timeout
    if (-not $proc -or -not $proc.Id) {
      Write-SpawnError -Branch 'Git Bash' -Message 'spawn primitive returned no process object'
      $spawnFailed = $true
      return 125
    }
    $outerTimeout = $Timeout + (Get-OuterWatchdogGraceSeconds)
    $completed = Wait-ProcessWithTimeout -Process $proc -TimeoutSeconds $outerTimeout
    if (-not $completed) {
      Stop-ProcessTree -ProcessId $proc.Id
      return 124
    }
    return $proc.ExitCode
  } catch {
    Write-SpawnError -Branch 'Git Bash' -Message $_.Exception.Message
    $spawnFailed = $true
    return 125
  } finally {
    if ($spawnFailed -and $proc -and $proc.Id) {
      Stop-ProcessTree -ProcessId $proc.Id
    }
  }
}

# ---- Dispatch -------------------------------------------------------------------

function Invoke-Dispatch {
  [CmdletBinding()] param([string[]]$Command)
  if (-not $Command -or $Command.Count -eq 0) {
    [Console]::Error.WriteLine('usage: aai-run-tests.ps1 <command> [args...]')
    return 2
  }
  # SEAM-3: canonicalize BEFORE Resolve-Interpreter, not merely before the
  # chosen launch primitive — Test-WslUsable (inside Resolve-Interpreter)
  # itself calls Start-Process, so it is a spawn site too and would otherwise
  # remain on the broken duplicate-cased environment.
  Set-CanonicalProcessEnvironment | Out-Null
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
