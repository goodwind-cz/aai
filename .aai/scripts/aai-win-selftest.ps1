#!/usr/bin/env pwsh
#
# aai-win-selftest.ps1 — Windows self-test + environment probe consumed by
# `.aai/scripts/aai-doctor.mjs` CAT-14 (Windows Self-Test) and CAT-15
# (Windows Environment) (CHANGE-0135 / spec-doctor-win-selftest).
#
# D1 (frozen design decision, do not re-derive): this file DOT-SOURCES
# `.aai/scripts/aai-run-tests.ps1` for its probe functions instead of
# duplicating them. That header explicitly blesses this: "Dot-sourcing this
# file (`. $path`) defines the functions WITHOUT running Main". This script
# therefore CALLS Test-WslPresent, Test-WslUsable, Get-GitBashCandidates,
# Find-GitBash, Get-ProcessEnvironmentSnapshot, Get-CanonicalEnvironmentMap
# and Wait-ProcessWithTimeout, and defines none of them. The production
# dispatcher is not edited by this scope, and this file mutates nothing: the
# canonicalizer that WRITES the real process environment is never called and
# never named here — diagnosis only (D2).
#
# D3 (frozen): arm 3 (spawn-failure induction) doctors a CHILD process's
# environment only — ProgramFiles/ProgramFiles(x86) point at a temp root
# holding a non-executable `bash.exe` decoy under a `Git\bin` directory, and
# PATH is reduced so neither a real bash.exe nor wsl.exe resolves there. That
# doctoring happens INSIDE the spawned engine's own -Command text (never via
# $env: on this process), so the caller's real environment and the host's
# real Git installation are never touched, moved, renamed or deleted.
#
# Every arm spawns a FRESH engine process (pwsh, else powershell.exe) with
# both standard streams redirected to per-arm temp files (OS-handle capture)
# and `.Handle` touched on the very next statement after the Start-Process
# assignment — the same 5.1 ExitCode-null footgun workaround
# `aai-run-tests.ps1` itself documents and uses.
#
# Output: direct invocation runs the whole probe and prints ONE JSON object
# on stdout, then exits 0 (this script's own success — arm/category failures
# are reported INSIDE the JSON, never via a non-zero process exit, so the
# consumer's own timeout/parse-failure handling is the only degrade path).
# Dot-sourcing defines the functions only, mirroring the wrapper's
# `$MyInvocation.InvocationName -ne '.'` guard below.
#
# Usage:
#   pwsh -File .aai/scripts/aai-win-selftest.ps1

. (Join-Path $PSScriptRoot 'aai-run-tests.ps1')

# ---- CAT-15 pure derivations ------------------------------------------------

function Get-EnvironmentCollisionReport {
  # Pure (D2): derives WHICH original snapshot keys collapsed into which
  # survivor purely from the wrapper's own Get-CanonicalEnvironmentMap, never
  # re-deriving the collision rule. A group of size 1 (no real collision) is
  # never reported.
  [CmdletBinding()]
  param([Parameter(Mandatory)][System.Collections.IDictionary]$Environment)

  $canonical = Get-CanonicalEnvironmentMap -Environment $Environment
  $groups = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new(
    [StringComparer]::OrdinalIgnoreCase)
  foreach ($key in $Environment.Keys) {
    $k = [string]$key
    if (-not $groups.ContainsKey($k)) { $groups[$k] = [System.Collections.Generic.List[string]]::new() }
    $groups[$k].Add($k)
  }

  $report = @()
  foreach ($survivorKey in $canonical.Keys) {
    $sk = [string]$survivorKey
    if (-not $groups.ContainsKey($sk)) { continue }
    # -cne (case-SENSITIVE): PowerShell's default -ne is case-INsensitive, so
    # a bare -ne here would treat 'PATH' as equal to survivor 'Path' and
    # silently drop it from its own collision report.
    $collapsed = @($groups[$sk] | Where-Object { $_ -cne $sk } | Sort-Object)
    if ($collapsed.Count -gt 0) {
      $report += [ordered]@{ survivor = $sk; collapsed = $collapsed }
    }
  }
  # Write-Output -NoEnumerate: sends $report as ONE pipeline object rather
  # than enumerating its elements onto the pipeline. Plain `return $report`
  # (or even the unary-comma `,$report` idiom) both unwrap/rewrap based on
  # element COUNT -- a 0-element array comes back double-wrapped (an outer
  # 1-element array containing the empty array) and a 1-element array comes
  # back unwrapped to a bare hashtable, either of which makes a caller's
  # `.Count` read wrong. -NoEnumerate is the one primitive whose behavior
  # does not depend on how many elements $report happens to hold.
  Write-Output -NoEnumerate $report
}

function Get-WslTriState {
  # absent | present-no-distro | functional, driven entirely by the wrapper's
  # own two probes so a Pester mock of either is deterministic on every host.
  [CmdletBinding()] param()
  if (-not (Test-WslPresent)) { return 'absent' }
  if (Test-WslUsable) { return 'functional' }
  return 'present-no-distro'
}

function Get-AvailableEngines {
  [CmdletBinding()] param()
  $result = @()
  if (Get-Command pwsh -ErrorAction SilentlyContinue) {
    $ver = (& pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>$null)
    $result += [ordered]@{ name = 'pwsh'; version = [string]$ver }
  }
  if (Get-Command powershell -ErrorAction SilentlyContinue) {
    $ver2 = (& powershell -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>$null)
    $result += [ordered]@{ name = 'powershell'; version = [string]$ver2 }
  }
  # See Get-EnvironmentCollisionReport above for why -NoEnumerate, not a
  # bare return or the unary-comma idiom.
  Write-Output -NoEnumerate $result
}

# ---- CAT-14 pure report builder ---------------------------------------------

function Build-SelfTestReport {
  # Pure: turns an array of already-computed arm results (each carrying Name/
  # Status/ExitCode/Diag) into the documented report shape, verbatim — no
  # process spawning here, so this is unit-testable with synthetic input.
  [CmdletBinding()]
  param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Arms)

  $failed = $false
  $entries = @()
  foreach ($arm in $Arms) {
    $entries += [ordered]@{
      name     = $arm.Name
      status   = $arm.Status
      exitCode = $arm.ExitCode
      diag     = $arm.Diag
    }
    if ($arm.Status -ne 'PASS') { $failed = $true }
  }
  # Edge case (spec, recorded): a real Windows host with NEITHER WSL nor Git
  # Bash cannot pass the success/timeout arms at all -- the wrapper's own
  # documented contract there is exit 78 (AAI-ENV-ERROR), never a fabricated
  # arm result. Name that precondition explicitly instead of a bare
  # "N/3 arms passed" when it is what actually happened, so the doctor's WARN
  # reason is diagnostic, not just a count.
  $successArm = $entries | Where-Object { $_.name -eq 'success' } | Select-Object -First 1
  $timeoutArm = $entries | Where-Object { $_.name -eq 'timeout' } | Select-Object -First 1
  $reason = $null
  if ($successArm -and $timeoutArm -and $successArm.exitCode -eq 78 -and $timeoutArm.exitCode -eq 78) {
    $reason = 'host has no usable POSIX interpreter (WSL or Git Bash) -- the wrapper reported AAI-ENV-ERROR (exit 78) on every arm needing one'
  }
  return [ordered]@{ spawned = $true; arms = $entries; failed = $failed; reason = $reason }
}

# ---- CAT-14 arm execution ----------------------------------------------------

function New-SelfTestTempRoot {
  [CmdletBinding()] param()
  $root = Join-Path ([System.IO.Path]::GetTempPath()) ('aai-win-selftest-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $root -Force | Out-Null
  return $root
}

function Resolve-SelfTestEngine {
  [CmdletBinding()] param()
  if (Get-Command pwsh -ErrorAction SilentlyContinue) { return 'pwsh' }
  if (Get-Command powershell -ErrorAction SilentlyContinue) { return 'powershell' }
  return $null
}

function Get-QuotedArgumentString {
  # ArgumentList must reach Start-Process as ONE pre-quoted string, never the
  # raw array: Start-Process space-joins array elements WITHOUT quoting ones
  # that contain embedded spaces (identical footgun to
  # aai-run-tests.ps1's own Start-WslProbeProcess, whose header names it and
  # whose exact fix this mirrors).
  [CmdletBinding()]
  param([Parameter(Mandatory)][string[]]$ArgumentList)
  return ($ArgumentList | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' '
}

function Invoke-SelfTestChildEngine {
  # Spawns a FRESH engine process to run a small inner SCRIPT FILE (never an
  # inline -Command string carrying embedded quotes — the ArgumentList
  # footgun above makes that unreliable). Both standard streams redirect to
  # per-arm temp files (OS-handle capture, TEST-003); `.Handle` is touched on
  # the statement immediately after the Start-Process assignment, before any
  # wait — the 5.1 ExitCode-null footgun workaround. Every environment
  # variable an arm needs is set INSIDE the inner script's own text, never
  # via $env: on THIS (calling) process.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Engine,
    [Parameter(Mandatory)][string]$InnerScriptContent,
    [Parameter(Mandatory)][string]$ArmTempDir,
    [int]$WaitSeconds = 30
  )
  New-Item -ItemType Directory -Path $ArmTempDir -Force | Out-Null
  $innerScriptPath = Join-Path $ArmTempDir 'inner.ps1'
  Set-Content -LiteralPath $innerScriptPath -Value $InnerScriptContent
  $outFile = Join-Path $ArmTempDir 'stdout.txt'
  $errFile = Join-Path $ArmTempDir 'stderr.txt'
  $argString = Get-QuotedArgumentString -ArgumentList @('-NoProfile', '-File', $innerScriptPath)
  $proc = Start-Process -FilePath $Engine -ArgumentList $argString `
    -NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
  $null = $proc.Handle
  $completed = Wait-ProcessWithTimeout -Process $proc -TimeoutSeconds $WaitSeconds
  if (-not $completed) {
    try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
  }
  $stdOut = if (Test-Path -LiteralPath $outFile) { Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue } else { '' }
  $stdErr = if (Test-Path -LiteralPath $errFile) { Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue } else { '' }
  return [ordered]@{
    ExitCode = if ($completed) { $proc.ExitCode } else { $null }
    TimedOut = -not $completed
    StdOut   = [string]$stdOut
    StdErr   = [string]$stdErr
  }
}

function Get-LastDiagLine {
  [CmdletBinding()]
  param([string]$Text, [string]$Pattern)
  if ([string]::IsNullOrEmpty($Text)) { return '' }
  $found = [regex]::Matches($Text, $Pattern)
  if ($found.Count -eq 0) { return '' }
  return $found[$found.Count - 1].Value.Trim()
}

function Invoke-SelfTestArmSuccess {
  # success: exit 3 plus a marker FILE whose content matches, no
  # AAI-SPAWN-ERROR line. A marker FILE (not a stdout regex) sidesteps the
  # UTF-16LE stream-corruption edge case the spec records.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Engine,
    [Parameter(Mandatory)][string]$RunDispatcherPath,
    [Parameter(Mandatory)][string]$ArmTempDir
  )
  $marker = Join-Path $ArmTempDir 'marker.txt'
  $markerPosix = $marker -replace '\\', '/'
  $inner = @"
`$env:AAI_TEST_TIMEOUT = '60'
& '$RunDispatcherPath' sh -c "echo AAI-SELFTEST-OK > '$markerPosix'; exit 3"
exit `$LASTEXITCODE
"@
  $result = Invoke-SelfTestChildEngine -Engine $Engine -InnerScriptContent $inner -ArmTempDir $ArmTempDir -WaitSeconds 90
  $markerOk = (Test-Path -LiteralPath $marker) -and ((Get-Content -LiteralPath $marker -Raw -ErrorAction SilentlyContinue) -match 'AAI-SELFTEST-OK')
  $spawnError = $result.StdErr -match 'AAI-SPAWN-ERROR'
  $diag = Get-LastDiagLine -Text $result.StdErr -Pattern 'AAI-BRANCH:.*'
  $status = if ($result.ExitCode -eq 3 -and $markerOk -and -not $spawnError) { 'PASS' } else { 'FAIL' }
  return [ordered]@{ Name = 'success'; Status = $status; ExitCode = $result.ExitCode; Diag = $diag }
}

function Invoke-SelfTestArmTimeout {
  # timeout: exit 124 under AAI_TEST_TIMEOUT of 2, no AAI-SPAWN-ERROR line.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Engine,
    [Parameter(Mandatory)][string]$RunDispatcherPath,
    [Parameter(Mandatory)][string]$ArmTempDir
  )
  $inner = @"
`$env:AAI_TEST_TIMEOUT = '2'
& '$RunDispatcherPath' sh -c 'sleep 30'
exit `$LASTEXITCODE
"@
  $result = Invoke-SelfTestChildEngine -Engine $Engine -InnerScriptContent $inner -ArmTempDir $ArmTempDir -WaitSeconds 30
  $spawnError = $result.StdErr -match 'AAI-SPAWN-ERROR'
  $diag = Get-LastDiagLine -Text $result.StdErr -Pattern 'AAI-BRANCH:.*'
  $status = if ($result.ExitCode -eq 124 -and -not $spawnError) { 'PASS' } else { 'FAIL' }
  return [ordered]@{ Name = 'timeout'; Status = $status; ExitCode = $result.ExitCode; Diag = $diag }
}

function Invoke-SelfTestArmSpawnFail {
  # spawnfail (D3): exit 125 with exactly one AAI-SPAWN-ERROR line and no
  # marker file. The doctored ProgramFiles/PATH exist ONLY inside the spawned
  # engine's own -Command text; the decoy lives entirely under this arm's own
  # temp directory and is created with New-Item/Set-Content — the real,
  # already-resolved bash executable on the host is never touched, relocated
  # or deleted by this function or by any other in this file.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Engine,
    [Parameter(Mandatory)][string]$RunDispatcherPath,
    [Parameter(Mandatory)][string]$ArmTempDir
  )
  New-Item -ItemType Directory -Path $ArmTempDir -Force | Out-Null
  $decoyRoot = Join-Path $ArmTempDir 'decoy'
  $decoyGitBin = Join-Path $decoyRoot 'Git\bin'
  New-Item -ItemType Directory -Path $decoyGitBin -Force | Out-Null
  $decoyBash = Join-Path $decoyGitBin 'bash.exe'
  Set-Content -LiteralPath $decoyBash -Value 'AAI self-test decoy: not a real executable' -NoNewline
  $marker = Join-Path $ArmTempDir 'marker.txt'
  $markerPosix = $marker -replace '\\', '/'
  $reducedPath = if ($env:SystemRoot) { Join-Path $env:SystemRoot 'System32' } else { '/usr/bin' }
  $inner = @"
`$env:ProgramFiles = '$decoyRoot'
`${env:ProgramFiles(x86)} = '$decoyRoot'
`$env:PATH = '$reducedPath'
`$env:Path = '$reducedPath'
`$env:AAI_TEST_TIMEOUT = '30'
& '$RunDispatcherPath' sh -c "echo should-not-run > '$markerPosix'; exit 0"
exit `$LASTEXITCODE
"@
  $result = Invoke-SelfTestChildEngine -Engine $Engine -InnerScriptContent $inner -ArmTempDir $ArmTempDir -WaitSeconds 30
  $spawnErrorMatches = [regex]::Matches($result.StdErr, 'AAI-SPAWN-ERROR:.*')
  $markerAbsent = -not (Test-Path -LiteralPath $marker)
  $status = if ($result.ExitCode -eq 125 -and $spawnErrorMatches.Count -eq 1 -and $markerAbsent) { 'PASS' } else { 'FAIL' }
  $diag = if ($spawnErrorMatches.Count -gt 0) { $spawnErrorMatches[$spawnErrorMatches.Count - 1].Value.Trim() } else { '' }
  return [ordered]@{ Name = 'spawnfail'; Status = $status; ExitCode = $result.ExitCode; Diag = $diag }
}

function Invoke-SelfTest {
  # Orchestrates the three arms for real. Degrades to a named, non-spawning
  # SKIP-shaped result when no engine resolves (the doctor's own platform +
  # engine gate means this only happens if this script is invoked directly
  # outside that gate, e.g. by a human or this repo's own test suite).
  [CmdletBinding()] param()
  $engine = Resolve-SelfTestEngine
  if (-not $engine) {
    return [ordered]@{ spawned = $false; reason = 'no PowerShell engine (pwsh or powershell.exe) resolved on PATH'; arms = @(); failed = $true }
  }
  $runDispatcherPath = Join-Path $PSScriptRoot 'aai-run-tests.ps1'
  $root = New-SelfTestTempRoot
  try {
    $armSuccess = Invoke-SelfTestArmSuccess -Engine $engine -RunDispatcherPath $runDispatcherPath -ArmTempDir (Join-Path $root 'arm-success')
    $armTimeout = Invoke-SelfTestArmTimeout -Engine $engine -RunDispatcherPath $runDispatcherPath -ArmTempDir (Join-Path $root 'arm-timeout')
    $armSpawnFail = Invoke-SelfTestArmSpawnFail -Engine $engine -RunDispatcherPath $runDispatcherPath -ArmTempDir (Join-Path $root 'arm-spawnfail')
    return Build-SelfTestReport -Arms @($armSuccess, $armTimeout, $armSpawnFail)
  } finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
  }
}

# ---- Report assembly (SEAM-1) ------------------------------------------------

function Get-SelfTestReport {
  [CmdletBinding()] param()
  $snapshot = Get-ProcessEnvironmentSnapshot
  return [ordered]@{
    selftest    = Invoke-SelfTest
    environment = [ordered]@{
      # Get-EnvironmentCollisionReport/Get-AvailableEngines already guarantee
      # a real array via -NoEnumerate (see their own headers) -- wrapping
      # THOSE two in @() again would re-introduce the exact double-wrap bug
      # that primitive avoids. Get-GitBashCandidates is the WRAPPER's own
      # function (plain `return`, ordinary pipeline unwrap semantics), so it
      # still needs the defensive @() wrap here.
      collisions = Get-EnvironmentCollisionReport -Environment $snapshot
      engines    = Get-AvailableEngines
      gitBash    = [ordered]@{ candidates = @(Get-GitBashCandidates); selected = (Find-GitBash) }
      wsl        = Get-WslTriState
    }
  }
}

if ($MyInvocation.InvocationName -ne '.') {
  $report = Get-SelfTestReport
  $report | ConvertTo-Json -Depth 8 -Compress
  exit 0
}
