# retired-loop-runner launcher cases (spec-retire-shell-loop-runner, TEST-3405).
# Each case launches autonomous-loop.ps1 with the engine running the test ((Get-Process -Id $PID).Path),
# so the Windows PowerShell 5.1 step tests 5.1 and the pwsh 7 steps test pwsh 7. Fixtures are git
# repositories in TestDrive with a local identity; nothing touches the repository checkout. No case
# may skip.
Describe 'retired shell loop runner launcher' {
  BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:Launcher = Join-Path $Root '.aai/scripts/autonomous-loop.ps1'
    $script:Engine = (Get-Process -Id $PID).Path
    $script:Retired = 'autonomous-loop: retired - the autonomous-loop shell runner is retired (RFC-0017 phase 5) and will be deleted in the next release; replacement: /aai-loop; nothing was changed'

    function Invoke-Git {
      param([string]$Dir, [string[]]$GitArgs)
      $ErrorActionPreference = 'Continue'
      $o = & git -C $Dir @GitArgs 2>&1
      return ($o | ForEach-Object { "$_" }) -join "`n"
    }
    function New-Fixture {
      param([string]$Name)
      $d = Join-Path $TestDrive $Name
      New-Item -ItemType Directory -Force -Path (Join-Path $d 'docs/ai') | Out-Null
      [IO.File]::WriteAllText((Join-Path $d 'docs/ai/.gitkeep'), '')
      [void](Invoke-Git $d @('init', '-q'))
      [void](Invoke-Git $d @('config', 'user.email', 'fixture@example.invalid'))
      [void](Invoke-Git $d @('config', 'user.name', 'fixture'))
      [void](Invoke-Git $d @('config', 'core.autocrlf', 'false'))
      [void](Invoke-Git $d @('config', 'commit.gpgsign', 'false'))
      [void](Invoke-Git $d @('add', '-A'))
      [void](Invoke-Git $d @('commit', '-q', '-m', 'fixture'))
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
    function Assert-Retired {
      param([string]$Dir, $Result)
      $Result.ExitCode | Should -Be 1
      $Result.Stdout | Should -Be ''
      $Result.Stderr.Trim() | Should -Be $script:Retired
      Test-Path -LiteralPath (Join-Path $Dir 'docs/ai/STATE.yaml') | Should -BeFalse
      Test-Path -LiteralPath (Join-Path $Dir 'docs/ai/LOOP_TICKS.jsonl') | Should -BeFalse
      Invoke-Git $Dir @('status', '--porcelain') | Should -Be ''
    }
  }

  It 'with skill-mode switches prints its retirement line, exits 1 and changes nothing' {
    $d = New-Fixture 'fx-skill'
    $r = Invoke-Launcher $d '-Mode skill -AgentCommand codex -MaxIterations 1 -AutoInitState'
    Assert-Retired $d $r
  }

  It 'with no argument prints its retirement line, exits 1 and changes nothing' {
    $d = New-Fixture 'fx-none'
    $r = Invoke-Launcher $d
    Assert-Retired $d $r
  }

  It 'with -DryRun prints its retirement line, exits 1 and changes nothing' {
    $d = New-Fixture 'fx-dry'
    $r = Invoke-Launcher $d '-DryRun'
    Assert-Retired $d $r
  }

  It 'with an unknown switch still prints its retirement line and exits 1' {
    $d = New-Fixture 'fx-unknown'
    $r = Invoke-Launcher $d '-NoSuchSwitch value'
    Assert-Retired $d $r
  }
}
