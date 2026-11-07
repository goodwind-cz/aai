# pre-commit-checks launcher cases (spec-pre-commit-checks-ps1-retire, TEST-3449).
# Each case launches pre-commit-checks.ps1 with the engine running the test ((Get-Process -Id $PID).Path),
# so the Windows PowerShell 5.1 step tests 5.1 and the pwsh 7 steps test pwsh 7. Fixtures are git
# repositories in TestDrive with a local identity; nothing touches the repository checkout. No case
# may skip.
Describe 'retired PowerShell pre-commit checks launcher' {
  BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:Launcher = Join-Path $Root '.aai/scripts/pre-commit-checks.ps1'
    $script:Engine = (Get-Process -Id $PID).Path
    $script:Retired = 'pre-commit-checks.ps1: retired - the PowerShell pre-commit checks are retired (RFC-0017 phase 5) and will be deleted in the next release; replacement: bash .aai/scripts/pre-commit-checks.sh (the installed hooks already run it); nothing was checked'

    function Invoke-Git {
      param([string]$Dir, [string[]]$GitArgs)
      $ErrorActionPreference = 'Continue'
      $o = & git -C $Dir @GitArgs 2>&1
      return ($o | ForEach-Object { "$_" }) -join "`n"
    }
    function New-Fixture {
      param([string]$Name, [bool]$StageSecret = $false)
      $d = Join-Path $TestDrive $Name
      New-Item -ItemType Directory -Force -Path $d | Out-Null
      [IO.File]::WriteAllText((Join-Path $d 'README.txt'), "fixture`n")
      [void](Invoke-Git $d @('init', '-q'))
      [void](Invoke-Git $d @('config', 'user.email', 'fixture@example.invalid'))
      [void](Invoke-Git $d @('config', 'user.name', 'fixture'))
      [void](Invoke-Git $d @('config', 'core.autocrlf', 'false'))
      [void](Invoke-Git $d @('config', 'commit.gpgsign', 'false'))
      [void](Invoke-Git $d @('add', '-A'))
      [void](Invoke-Git $d @('commit', '-q', '-m', 'fixture'))
      if ($StageSecret) {
        [IO.File]::WriteAllText((Join-Path $d 'config.txt'), ("api" + "_key = 'abcdefgh1234'`n"))
        [void](Invoke-Git $d @('add', 'config.txt'))
      }
      return $d
    }
    function Invoke-Launcher {
      param([string]$WorkDir, [string]$ExtraArgs = '')
      $psi = New-Object System.Diagnostics.ProcessStartInfo
      $psi.FileName = $script:Engine
      $psi.Arguments = ('-NoProfile -File "' + $script:Launcher + '" ' + $ExtraArgs).Trim()
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
      return (Invoke-Git $Dir @('status', '--porcelain')) + '|' + (Invoke-Git $Dir @('diff', '--cached', '--name-only'))
    }
    function Assert-Retired {
      param([string]$Dir, $Result, [string]$Before)
      $Result.ExitCode | Should -Be 1
      $Result.Stdout | Should -Be ''
      $Result.Stderr.Trim() | Should -Be $script:Retired
      Get-Snapshot $Dir | Should -Be $Before
    }
  }

  It 'with no argument prints its retirement line, exits 1 and changes nothing' {
    $d = New-Fixture 'fx-none'
    $before = Get-Snapshot $d
    $r = Invoke-Launcher $d
    Assert-Retired $d $r $before
  }

  It 'with -Strict prints its retirement line, exits 1 and changes nothing' {
    $d = New-Fixture 'fx-strict'
    $before = Get-Snapshot $d
    $r = Invoke-Launcher $d '-Strict'
    Assert-Retired $d $r $before
  }

  It 'with a staged secret-shaped file and extra arguments still refuses by name and leaves the index alone' {
    $d = New-Fixture 'fx-secret' $true
    $before = Get-Snapshot $d
    $before | Should -Match 'config.txt'
    $r = Invoke-Launcher $d '-Strict extra'
    Assert-Retired $d $r $before
  }
}
