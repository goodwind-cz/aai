# legacy-migrations launcher cases (spec-retire-legacy-migrations, TEST-3388).
# Each case launches a .ps1 launcher with the engine running the test ((Get-Process -Id $PID).Path),
# so the Windows PowerShell 5.1 step tests 5.1 and the pwsh 7 steps test pwsh 7. Fixtures are git
# repositories in TestDrive with a local identity; nothing touches the repository checkout. No case
# may skip.
Describe 'legacy migration launchers' {
  BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:Scripts = Join-Path $Root '.aai/scripts'
    $script:Launcher = Join-Path $Scripts 'migrate-state-to-local.ps1'
    $script:Engine = (Get-Process -Id $PID).Path
    $script:Refused = 'migrate-state-to-local: refused - node not found in PATH or migrate-state-to-local.mjs missing; nothing was changed. Install Node.js 22 or later (https://nodejs.org/) and re-run.'
    $script:Retired = @{
      'aai-canonicalize' = 'aai-canonicalize: retired - the aai-canonicalize script and the /aai-canonicalize skill are retired (RFC-0017 phase 5) and will be deleted in the next release; replacement: none; nothing was changed'
      'migrate-yaml-to-jsonl' = 'migrate-yaml-to-jsonl: retired - the migrate-yaml-to-jsonl script is retired (RFC-0017 phase 5) and will be deleted in the next release; replacement: none; nothing was changed'
    }

    function Invoke-Git {
      param([string]$Dir, [string[]]$GitArgs)
      $ErrorActionPreference = 'Continue'
      $o = & git -C $Dir @GitArgs 2>&1
      return ($o | ForEach-Object { "$_" }) -join "`n"
    }
    function New-Legacy {
      param([string]$Name)
      $d = Join-Path $TestDrive $Name
      foreach ($sub in @('docs/ai/tdd/x', 'docs/ai/loop')) { New-Item -ItemType Directory -Force -Path (Join-Path $d $sub) | Out-Null }
      [IO.File]::WriteAllText((Join-Path $d '.gitignore'), "node_modules`r`n")
      foreach ($f in @('docs/ai/STATE.yaml', 'docs/ai/LOOP_TICKS.jsonl', 'docs/ai/tdd/.gitkeep', 'docs/ai/tdd/x/red.log', 'docs/ai/loop/a.txt')) {
        [IO.File]::WriteAllText((Join-Path $d $f), "x`n")
      }
      [void](Invoke-Git $d @('init', '-q'))
      [void](Invoke-Git $d @('config', 'user.email', 'fixture@example.invalid'))
      [void](Invoke-Git $d @('config', 'user.name', 'fixture'))
      [void](Invoke-Git $d @('config', 'core.autocrlf', 'false'))
      [void](Invoke-Git $d @('config', 'commit.gpgsign', 'false'))
      [void](Invoke-Git $d @('add', '-A'))
      [void](Invoke-Git $d @('commit', '-q', '-m', 'legacy'))
      return $d
    }
    function Invoke-Launcher {
      param([string]$LauncherPath, [string]$WorkDir, [string]$ExtraArgs = '')
      $psi = New-Object System.Diagnostics.ProcessStartInfo
      $psi.FileName = $script:Engine
      $psi.Arguments = ('-NoProfile -File "' + $LauncherPath + '" ' + $ExtraArgs).Trim()
      $psi.WorkingDirectory = $WorkDir
      $psi.UseShellExecute = $false
      $psi.RedirectStandardOutput = $true
      $psi.RedirectStandardError = $true
      $p = [System.Diagnostics.Process]::Start($psi)
      $out = $p.StandardOutput.ReadToEnd()
      $err = $p.StandardError.ReadToEnd()
      $p.WaitForExit()
      return [pscustomobject]@{ ExitCode = $p.ExitCode; Stdout = $out; Stderr = $err }
    }
    function Get-Snapshot {
      param([string]$Dir)
      $files = Get-ChildItem -LiteralPath $Dir -Recurse -File -Force | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } | Sort-Object FullName
      return (($files | ForEach-Object { $_.FullName.Substring($Dir.Length) + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join "`n")
    }
    function Assert-Migrated {
      param([string]$Dir)
      (Invoke-Git $Dir @('ls-files')) | Should -Be ".gitignore`ndocs/ai/tdd/.gitkeep"
      $text = [IO.File]::ReadAllText((Join-Path $Dir '.gitignore'))
      $text | Should -BeLike '*# AAI per-dev runtime state (RFC-0001: never committed)*'
      $text | Should -BeLike '*docs/INDEX.audit.md*'
      (Get-Item -LiteralPath (Join-Path $Dir 'docs/ai/EVENTS.jsonl')).Length | Should -Be 0
      Test-Path -LiteralPath (Join-Path $Dir 'docs/ai/STATE.yaml') | Should -BeTrue
    }
  }

  It 'migrate-state-to-local.ps1 with -TargetRoot produces the Spec-AC-02 effects' {
    $d = New-Legacy 'fx-target'
    $r = Invoke-Launcher $script:Launcher $TestDrive ('-TargetRoot "' + $d + '"')
    $r.ExitCode | Should -Be 0
    $r.Stdout | Should -BeLike '*Files untracked:        4*'
    Assert-Migrated $d
  }

  It 'migrate-state-to-local.ps1 with -DryRun changes nothing' {
    $d = New-Legacy 'fx-dry'
    $before = Get-Snapshot $d
    $index = Invoke-Git $d @('ls-files', '-s')
    $r = Invoke-Launcher $script:Launcher $TestDrive ('-TargetRoot "' + $d + '" -DryRun')
    $r.ExitCode | Should -Be 0
    $r.Stdout | Should -BeLike '*Dry-run only. Re-run without the dry-run flag to apply.*'
    Get-Snapshot $d | Should -Be $before
    Invoke-Git $d @('ls-files', '-s') | Should -Be $index
  }

  It 'migrate-state-to-local.ps1 with a mistyped switch (-DyRun) is refused and changes nothing' {
    $d = New-Legacy 'fx-typo'
    $before = Get-Snapshot $d
    $index = Invoke-Git $d @('ls-files', '-s')
    $r = Invoke-Launcher $script:Launcher $TestDrive ('-TargetRoot "' + $d + '" -DyRun')
    $r.ExitCode | Should -Not -Be 0
    $r.Stdout | Should -Be ''
    Get-Snapshot $d | Should -Be $before
    Invoke-Git $d @('ls-files', '-s') | Should -Be $index
  }

  It 'migrate-state-to-local.ps1 from Push-Location with no -TargetRoot migrates the location' {
    $d = New-Legacy 'fx-cwd'
    Push-Location -LiteralPath $d
    try {
      $null = & $script:Launcher
      $code = $LASTEXITCODE
    } finally { Pop-Location }
    $code | Should -Be 0
    Assert-Migrated $d
  }

  It 'a launcher copy without the module refuses with exit 1 and changes nothing' {
    $d = New-Legacy 'fx-nomodule'
    $copy = Join-Path $TestDrive 'copy-nomodule'
    New-Item -ItemType Directory -Force -Path $copy | Out-Null
    Copy-Item -LiteralPath $script:Launcher -Destination $copy
    $before = Get-Snapshot $d
    $r = Invoke-Launcher (Join-Path $copy 'migrate-state-to-local.ps1') $d ('-TargetRoot "' + $d + '"')
    $r.ExitCode | Should -Be 1
    $r.Stdout | Should -Be ''
    $r.Stderr.Trim() | Should -Be $script:Refused
    Get-Snapshot $d | Should -Be $before
    Invoke-Git $d @('status', '--porcelain') | Should -Be ''
  }

  It 'aai-canonicalize.ps1 prints its retirement line, exits 1 and changes nothing' {
    $d = New-Legacy 'fx-canon'
    $before = Get-Snapshot $d
    $r = Invoke-Launcher (Join-Path $script:Scripts 'aai-canonicalize.ps1') $d '-TargetRoot . -DryRun'
    $r.ExitCode | Should -Be 1
    $r.Stdout | Should -Be ''
    $r.Stderr.Trim() | Should -Be $script:Retired['aai-canonicalize']
    Get-Snapshot $d | Should -Be $before
    Invoke-Git $d @('status', '--porcelain') | Should -Be ''
  }

  It 'migrate-yaml-to-jsonl.ps1 prints its retirement line, exits 1 and changes nothing' {
    $d = New-Legacy 'fx-yaml'
    $before = Get-Snapshot $d
    $r = Invoke-Launcher (Join-Path $script:Scripts 'migrate-yaml-to-jsonl.ps1') $d '-TargetRoot . -DryRun'
    $r.ExitCode | Should -Be 1
    $r.Stdout | Should -Be ''
    $r.Stderr.Trim() | Should -Be $script:Retired['migrate-yaml-to-jsonl']
    Get-Snapshot $d | Should -Be $before
    Invoke-Git $d @('status', '--porcelain') | Should -Be ''
  }
}
