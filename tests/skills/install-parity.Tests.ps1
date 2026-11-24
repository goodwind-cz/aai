# install-parity driver on the smoke matrix (spec-install-path-parity-harness, TEST-3568, D-PESTER).
# The driver (tests/skills/lib/install-parity.mjs) runs the bash and the PowerShell twin of aai-sync, aai-update
# and the hook installer into scratch targets and diffs what they leave behind. This file is its front end on every
# host: the PowerShell twin runs under the engine that runs this file ((Get-Process -Id $PID).Path), so the Windows
# PowerShell 5.1 step tests 5.1 and the pwsh 7 steps test pwsh 7. The bash twin runs under Git for Windows' bash on
# Windows (never the WSL shim) and the bash on PATH elsewhere. Every native call goes through Invoke-NativeCaptured.
# No case may skip: a missing node or bash is a failure that names the tool.
Describe 'install-parity driver, smoke matrix' {
  BeforeAll {
    # Dot-sourced inside BeforeAll: a top-level dot-source does not reach Pester's run-phase scopes.
    . (Join-Path $PSScriptRoot 'lib/pester-native-capture.ps1')
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:Driver = Join-Path (Join-Path (Join-Path $script:Root 'tests') 'skills') 'lib/install-parity.mjs'
    $script:Engine = (Get-Process -Id $PID).Path
    $script:IsWin = [IO.Path]::DirectorySeparatorChar -eq '\'
    $script:Allowlist = Join-Path $PSScriptRoot 'lib/install-parity-allowlist.tsv'
    $script:Report = Join-Path $TestDrive 'parity-report.json'
    # AAI_PARITY_PESTER_SCENARIOS (comma list of smoke scenario ids) narrows the run to those scenarios. The bash suite sets it
    # so its POSIX case stays cheap (the full smoke matrix already ran there); unset, this file runs the whole smoke matrix,
    # which is what the Windows parity job and the Linux ps1 gate do.
    $script:Only = @(($env:AAI_PARITY_PESTER_SCENARIOS -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $script:ScenarioArgs = @(); foreach ($id in $script:Only) { $script:ScenarioArgs += @('--scenario', $id) }

    # Git for Windows' bash: the first existing of the four candidates; the WSL shim under System32 is never used.
    function Get-BashCandidates {
      $c = @()
      if ($env:ProgramFiles) { $c += (Join-Path $env:ProgramFiles 'Git\bin\bash.exe') }
      $pf86 = ${env:ProgramFiles(x86)}
      if ($pf86) { $c += (Join-Path $pf86 'Git\bin\bash.exe') }
      $g = Invoke-NativeCaptured -Exe 'git' -Arguments @('--exec-path')
      if ($g.Code -eq 0 -and $g.Out.Trim()) {
        # .../Git/mingw64/libexec/git-core -> .../Git/bin/bash.exe
        $gitRoot = Split-Path (Split-Path (Split-Path $g.Out.Trim() -Parent) -Parent) -Parent
        if ($gitRoot) { $c += (Join-Path $gitRoot 'bin\bash.exe') }
      }
      $onPath = Get-Command bash.exe -All -ErrorAction SilentlyContinue
      foreach ($b in $onPath) {
        if ($b.Source -notmatch '(?i)[\\/]System32[\\/]') { $c += $b.Source }
      }
      return $c
    }
    function Get-BashPath {
      if ($script:IsWin) {
        foreach ($c in (Get-BashCandidates)) {
          if ($c -and ($c -notmatch '(?i)[\\/]System32[\\/]') -and (Test-Path -LiteralPath $c -PathType Leaf)) { return $c }
        }
        return $null
      }
      $b = Get-Command bash -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($b) { return $b.Source }
      return $null
    }

    # D-HOSTCHECK (node-first-phase5-closeout): the named host checks the driver puts in its report (host_checks). On win32 every required
    # entry must be present, pass and have checked something (a missing entry, one that checked zero lines or a duplicate is a failure,
    # never a pass); on POSIX the two Windows entries must read not-applicable. Both are asserted for the scenarios the report holds.
    # BEGIN Get-ParityHostCheckProblems
    function Select-ParityHostCheck {
      param($Checks, [string]$Id, [string]$Scenario, [string]$Twin)
      return @($Checks | Where-Object { $_.id -eq $Id -and $_.scenario -eq $Scenario -and $_.twin -eq $Twin })
    }
    function Get-ParityHostCheckProblems {
      param($Report, [bool]$IsWin)
      $problems = @()
      $checks = @()
      if ($Report.PSObject.Properties.Name -contains 'host_checks') { $checks = @($Report.host_checks | ForEach-Object { $_ }) }
      $ran = @($Report.scenarios | ForEach-Object { $_.id })
      foreach ($e in $checks) { if ($e.status -eq 'fail') { $problems += ('host check ' + $e.id + ' ' + $e.scenario + ' ' + $e.twin + ' failed: ' + $e.detail) } }
      if ($IsWin) {
        foreach ($sc in @('SY-01', 'UP-01')) { if ($ran -notcontains $sc) { $problems += ('win32 run did not run ' + $sc + ', so its host checks are missing') } }
        foreach ($tw in @('launcher', 'node')) {
          $m = @(Select-ParityHostCheck -Checks $checks -Id 'source-path-windows' -Scenario 'SY-01' -Twin $tw)
          if ($m.Count -ne 1) { $problems += ('expected exactly one source-path-windows SY-01 ' + $tw + ' entry, found ' + $m.Count); continue }
          if ($m[0].status -ne 'pass') { $problems += ('source-path-windows SY-01 ' + $tw + ' is ' + $m[0].status + ', not pass') }
          if ([int]$m[0].checked -lt 2) { $problems += ('source-path-windows SY-01 ' + $tw + ' checked ' + $m[0].checked + ' lines, at least 2 are required') }
        }
        $c = @(Select-ParityHostCheck -Checks $checks -Id 'source-path-windows-control' -Scenario 'SY-01' -Twin 'sh')
        if ($c.Count -ne 1) { $problems += ('expected exactly one source-path-windows-control SY-01 sh entry, found ' + $c.Count) }
        elseif ($c[0].status -ne 'bites') { $problems += ('source-path-windows-control is ' + $c[0].status + ', not bites') }
        $o = @(Select-ParityHostCheck -Checks $checks -Id 'no-odd-root' -Scenario 'UP-01' -Twin 'launcher')
        if ($o.Count -ne 1) { $problems += ('expected exactly one no-odd-root UP-01 launcher entry, found ' + $o.Count) }
        else {
          if ($o[0].status -ne 'pass') { $problems += ('no-odd-root UP-01 launcher is ' + $o[0].status + ', not pass') }
          if ([int]$o[0].checked -lt 1) { $problems += ('no-odd-root UP-01 launcher checked ' + $o[0].checked + ' root entries, at least 1 is required') }
        }
      } else {
        if ($ran -contains 'SY-01') {
          foreach ($tw in @('launcher', 'node')) {
            $m = @(Select-ParityHostCheck -Checks $checks -Id 'source-path-windows' -Scenario 'SY-01' -Twin $tw)
            if ($m.Count -ne 1 -or $m[0].status -ne 'not-applicable') { $problems += ('source-path-windows SY-01 ' + $tw + ' must read not-applicable on a POSIX host') }
          }
          $c = @(Select-ParityHostCheck -Checks $checks -Id 'source-path-windows-control' -Scenario 'SY-01' -Twin 'sh')
          if ($c.Count -ne 1 -or $c[0].status -ne 'not-applicable') { $problems += 'source-path-windows-control must read not-applicable on a POSIX host' }
        }
        if ($ran -contains 'UP-01') {
          $o = @(Select-ParityHostCheck -Checks $checks -Id 'no-odd-root' -Scenario 'UP-01' -Twin 'launcher')
          if ($o.Count -ne 1 -or $o[0].status -ne 'pass' -or [int]$o[0].checked -lt 1) { $problems += 'no-odd-root UP-01 launcher must read pass with at least 1 root entry checked' }
        }
      }
      return $problems
    }
    # END Get-ParityHostCheckProblems

    $script:Bash = Get-BashPath
    $node = Invoke-NativeCaptured -Exe 'node' -Arguments @('--version')
    $script:NodeCode = $node.Code
  }

  It 'runs the smoke matrix with both twins and every divergence on the allowlist' {
    if ($script:NodeCode -ne 0) { throw 'node is required for the install-parity driver and was not found or did not run' }
    if (-not (Test-Path -LiteralPath $script:Allowlist)) { throw 'the committed allowlist lib/install-parity-allowlist.tsv is missing' }
    if (-not $script:Bash) { throw 'bash is required for the install-parity driver: no Git for Windows bash was found (the WSL shim in System32 is not used)' }
    # The driver defaults to every registered twin (a twin added to its registry runs here with no edit). The scratch base
    # is this run's own directory, removed in the finally, so an interrupted run leaves nothing under the temp dir.
    $scratch = Join-Path ([IO.Path]::GetTempPath()) ('aai-parity-pester-' + [guid]::NewGuid().ToString('N').Substring(0, 12))
    $null = New-Item -ItemType Directory -Path $scratch -Force
    $prevScratch = $env:AAI_PARITY_SCRATCH
    try {
      $env:AAI_PARITY_SCRATCH = $scratch
      $r = Invoke-NativeCaptured -Exe 'node' -Arguments (@($script:Driver, 'run', '--matrix', 'smoke', '--bash', $script:Bash, '--ps', $script:Engine, '--json', $script:Report) + $script:ScenarioArgs)
    } finally {
      if ($null -eq $prevScratch) { Remove-Item Env:\AAI_PARITY_SCRATCH -ErrorAction SilentlyContinue } else { $env:AAI_PARITY_SCRATCH = $prevScratch }
      Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($r.Code -ne 0) {
      Write-Host "install-parity driver exit $($r.Code)"
      Write-Host $r.Out
      Write-Host $r.Err
    }
    $r.Code | Should -Be 0
    $rep = Get-Content -LiteralPath $script:Report -Raw | ConvertFrom-Json
    # Driver notes belong in every run log, green or not; the AAI-HOST-CHECK and AAI-ODD-DIAG lines are the ones the hosted run is read for.
    @($rep.notes) | Where-Object { $_ } | ForEach-Object { Write-Host $_ }
    $rep.verdict | Should -Be 'PASS'
  }

  It 'holds the named host checks the platform requires' {
    $rep = Get-Content -LiteralPath $script:Report -Raw | ConvertFrom-Json
    $hostLines = @($rep.notes | Where-Object { $_ -like 'AAI-HOST-CHECK *' })
    Write-Host ('AAI-HOST-CHECK lines in this run: ' + $hostLines.Count)
    $problems = @(Get-ParityHostCheckProblems -Report $rep -IsWin $script:IsWin)
    foreach ($p in $problems) { Write-Host ('HOST-CHECK PROBLEM: ' + $p) }
    ($problems -join "`n") | Should -Be ''
  }

  It 'compares exactly the scenarios the smoke tier lists' {
    $l = Invoke-NativeCaptured -Exe 'node' -Arguments @($script:Driver, 'list', '--matrix', 'smoke', '--json')
    $l.Code | Should -Be 0
    # Windows PowerShell 5.1 sends a top-level JSON array down the pipeline as ONE object: flatten it through ForEach-Object.
    $want = @(($l.Out | ConvertFrom-Json) | ForEach-Object { $_ })
    if ($script:Only.Count -gt 0) { $want = @($want | Where-Object { $script:Only -contains $_ }) }
    $rep = Get-Content -LiteralPath $script:Report -Raw | ConvertFrom-Json
    $got = @($rep.scenarios | ForEach-Object { $_.id })
    $want.Count | Should -BeGreaterThan 0
    ($got -join ',') | Should -Be ($want -join ',')
  }
}
