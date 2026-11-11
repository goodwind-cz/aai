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
    # Driver notes (for example the Windows PowerShell 5.1 GIT_REDIRECT_STDERR NOTE) belong in every run log, green or not.
    @($rep.notes) | Where-Object { $_ } | ForEach-Object { Write-Host $_ }
    $rep.verdict | Should -Be 'PASS'
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
