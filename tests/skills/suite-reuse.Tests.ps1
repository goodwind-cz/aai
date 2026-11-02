# suite-reuse helper parity (spec-precise-suite-evidence-reuse, Spec-AC-10 / TEST-3184;
# trace identity: spec-reuse-for-docs-reading-suites D10).
# The reuse logic is one Node module on every platform; these cases run its CLI
# against a throwaway fixture repository under $TestDrive so the Windows hosts
# (Windows PowerShell 5.1 and pwsh 7, native and WSL) prove the same behavior as
# POSIX: a pass recorded with a trace file is REUSE, an edited traced input is
# RUN with reason=inputs, an added untracked file is RUN with reason=paths, and
# the store keeps its input paths with '/' separators. The trace file is
# written synthetically (the access-time canary decides on a real host). No case
# may skip.
Describe 'suite-reuse helper' {
  BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:Helper = Join-Path $Root '.aai/scripts/suite-reuse.mjs'
    $script:Utf8 = New-Object System.Text.UTF8Encoding $false
    $script:Counter = 0
    # CI and GITHUB_ACTIONS switch reuse off by design (D6); the cases need it on.
    $script:Saved = @{}
    foreach ($n in @('CI', 'GITHUB_ACTIONS', 'AAI_SUITE_REUSE')) {
      $script:Saved[$n] = [Environment]::GetEnvironmentVariable($n)
      [Environment]::SetEnvironmentVariable($n, $null)
    }

    function Write-Text {
      param([string]$Path, [string]$Text)
      $dir = Split-Path -Parent $Path
      if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
      [IO.File]::WriteAllText($Path, $Text, $script:Utf8)
    }
    function New-Fixture {
      $script:Counter++
      $repo = Join-Path $TestDrive ('repo' + $script:Counter)
      New-Item -ItemType Directory -Force -Path $repo | Out-Null
      $null = & git -C $repo init -q
      Write-Text (Join-Path $repo '.gitignore') "tests/skills/results/`n"
      Write-Text (Join-Path $repo 'tests/skills/suite-map.yaml') "core:`n  - fx`nfull_run_triggers:`n  shared_lib_globs:`n    - .aai/scripts/lib/**`nsuites:`n  fx:`n    globs:`n      - tests/skills/data/*.txt`n"
      Write-Text (Join-Path $repo 'tests/skills/suite-reuse.json') '{"version":1,"suites":{"fx":{"inputs":[],"live":false,"note":"fixture suite reads only its data files"}}}'
      Write-Text (Join-Path $repo 'tests/skills/test-fx.sh') "#!/usr/bin/env bash`necho fixture`n"
      Write-Text (Join-Path $repo 'tests/skills/data/a.txt') "a`n"
      return $repo
    }
    function Invoke-Helper {
      param([string[]]$Arguments)
      $out = & node $script:Helper @Arguments 2>&1
      return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = (($out | ForEach-Object { "$_" }) -join "`n") }
    }
    function Invoke-Check {
      param([string]$Repo, [string]$Run)
      Invoke-Helper @('check', '--root', $Repo, '--run-dir', (Join-Path $Repo "tests/skills/results/$Run"), '--mode', 'selected', '--isolation', 'on', '--suite', 'fx')
    }
    # A passing, attested, isolated run recorded for fx.
    function Add-Record {
      param([string]$Repo, [string]$Run)
      $dir = Join-Path $Repo "tests/skills/results/$Run"
      $null = Invoke-Check $Repo $Run
      Write-Text (Join-Path $dir 'fx.log') "PASS fx`n"
      $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Repo 'tests/skills/data/a.txt')).Hash.ToLower()
      # an input's identity is its sha256 plus its executable bit (checkout-trace.mjs contentHash); NTFS has none
      $exec = '-'
      if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) {
        $m = [int][System.IO.File]::GetUnixFileMode((Join-Path $Repo 'tests/skills/data/a.txt'))
        if ($m -band 0x49) { $exec = 'x' }
      }
      $hash = $hash + ':' + $exec
      $listed = @(& git -C $Repo ls-files --others --exclude-standard | ForEach-Object { "$_" })
      $trace = [ordered]@{
        suite = 'fx'; run_id = $Run; canary = $true; git_read = $false; index_read = $false
        inputs = [ordered]@{ 'tests/skills/data/a.txt' = $hash }; paths = $listed; env_names = @()
      }
      Write-Text (Join-Path $dir 'fx.reuse-trace.json') (ConvertTo-Json -InputObject $trace -Depth 5)
      Write-Text (Join-Path $dir 'metrics.jsonl') ('{"skill":"fx","status":"PASS","exit_code":0,"duration_seconds":1,"tripwire_attested":true,"tripwire_hasher_degraded":false}' + "`n")
      Invoke-Helper @('record', '--root', $Repo, '--run-dir', $dir, '--suite', 'fx', '--isolation', 'isolated', '--seeding', 'seeded')
    }
  }

  AfterAll {
    foreach ($n in $script:Saved.Keys) { [Environment]::SetEnvironmentVariable($n, $script:Saved[$n]) }
  }

  It 'reuses a recorded pass whose identity is unchanged' {
    $repo = New-Fixture
    (Add-Record $repo 'run1').Text | Should -Match 'RECORDED fx'
    $r = Invoke-Check $repo 'run2'
    $r.ExitCode | Should -Be 0
    $r.Text | Should -Match '^REUSE fx run=run1 at=\S+ log=tests/skills/results/run1/fx\.log'
  }

  It 'runs again with reason=inputs when a traced input is edited' {
    $repo = New-Fixture
    $null = Add-Record $repo 'run1'
    Write-Text (Join-Path $repo 'tests/skills/data/a.txt') "a edited`n"
    (Invoke-Check $repo 'run2').Text | Should -Match 'RUN fx reason=inputs changed tests/skills/data/a\.txt'
  }

  It 'runs again with reason=paths when an untracked file appears' {
    $repo = New-Fixture
    $null = Add-Record $repo 'run1'
    Write-Text (Join-Path $repo 'tests/skills/data/b.txt') "b`n"
    (Invoke-Check $repo 'run2').Text | Should -Match 'RUN fx reason=paths added tests/skills/data/b\.txt'
  }

  It 'stores input paths with slash separators' {
    $repo = New-Fixture
    $null = Add-Record $repo 'run1'
    $store = Join-Path $repo 'tests/skills/results/reuse/fx.json'
    Test-Path -LiteralPath $store | Should -BeTrue
    $rec = [IO.File]::ReadAllText($store) | ConvertFrom-Json
    $paths = @($rec.inputs_map.PSObject.Properties.Name)
    $paths.Count | Should -BeGreaterThan 0
    ($paths -contains 'tests/skills/data/a.txt') | Should -BeTrue
    @($paths | Where-Object { $_ -match '\\' }).Count | Should -Be 0
    $rec.log | Should -Be 'tests/skills/results/run1/fx.log'
  }
}
