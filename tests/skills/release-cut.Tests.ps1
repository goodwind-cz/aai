# aai-release.ps1 launcher cases for aai-release.mjs and release-cut.mjs (spec-release-on-node TEST-3472;
# spec-release-publish-on-node TEST-3529, DB-10 and DB-19).
# Each case launches aai-release.ps1 with the engine running the test ((Get-Process -Id $PID).Path), so the
# Windows PowerShell 5.1 step tests 5.1 and the pwsh 7 steps test pwsh 7. Fixtures are git repositories in
# TestDrive written as bytes with [System.IO.File]::WriteAllBytes (the bytes do not depend on the engine), with
# a local identity; every run is local (-NoRemote or -DryRun), no case calls gh, pushes, tags or publishes, and
# nothing touches the checkout's own CHANGELOG.md. No case may skip.
Describe 'aai-release.ps1 via aai-release.mjs' {
  BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:Script = Join-Path $Root '.aai/scripts/aai-release.ps1'
    $script:Engine = (Get-Process -Id $PID).Path
    $script:IsWin = [IO.Path]::DirectorySeparatorChar -eq '\'
    $script:Dash = [string][char]0x2014
    $script:Utf8 = New-Object System.Text.UTF8Encoding($false)

    function Invoke-Git {
      param([string]$Dir, [string[]]$GitArgs)
      $ErrorActionPreference = 'Continue'
      $o = & git -C $Dir @GitArgs 2>&1
      return ($o | ForEach-Object { "$_" }) -join "`n"
    }
    function New-Project {
      param([string]$Name, [string]$Changelog)
      $d = Join-Path $TestDrive $Name
      New-Item -ItemType Directory -Force -Path $d | Out-Null
      [IO.File]::WriteAllBytes((Join-Path $d 'CHANGELOG.md'), $script:Utf8.GetBytes($Changelog))
      [void](Invoke-Git $d @('init', '-q', '-b', 'main'))
      [void](Invoke-Git $d @('config', 'user.email', 'fixture@example.invalid'))
      [void](Invoke-Git $d @('config', 'user.name', 'fixture'))
      [void](Invoke-Git $d @('config', 'core.autocrlf', 'false'))
      [void](Invoke-Git $d @('config', 'commit.gpgsign', 'false'))
      [void](Invoke-Git $d @('add', '-A'))
      [void](Invoke-Git $d @('commit', '-q', '-m', 'chore: base'))
      return $d
    }
    function Invoke-Script {
      param([string]$WorkDir, [string]$ScriptArgs, [string]$Path)
      $psi = New-Object System.Diagnostics.ProcessStartInfo
      $psi.FileName = $script:Engine
      $psi.Arguments = ('-NoProfile -NonInteractive -File "' + $script:Script + '" ' + $ScriptArgs).Trim()
      $psi.WorkingDirectory = $WorkDir
      $psi.UseShellExecute = $false
      $psi.RedirectStandardOutput = $true
      $psi.RedirectStandardError = $true
      $psi.StandardOutputEncoding = $script:Utf8
      $psi.StandardErrorEncoding = $script:Utf8
      if ($Path) { $psi.EnvironmentVariables['PATH'] = $Path }
      $p = [System.Diagnostics.Process]::Start($psi)
      $so = $p.StandardOutput.ReadToEndAsync()
      $se = $p.StandardError.ReadToEndAsync()
      $p.WaitForExit()
      return [pscustomobject]@{ Code = $p.ExitCode; Out = $so.Result; Err = $se.Result }
    }
    function Invoke-Engine {
      param([string]$WorkDir, [string]$Arguments)
      $psi = New-Object System.Diagnostics.ProcessStartInfo
      $psi.FileName = $script:Engine
      $psi.Arguments = $Arguments
      $psi.WorkingDirectory = $WorkDir
      $psi.UseShellExecute = $false
      $psi.RedirectStandardOutput = $true
      $psi.RedirectStandardError = $true
      $psi.StandardOutputEncoding = $script:Utf8
      $psi.StandardErrorEncoding = $script:Utf8
      $p = [System.Diagnostics.Process]::Start($psi)
      $so = $p.StandardOutput.ReadToEndAsync()
      $se = $p.StandardError.ReadToEndAsync()
      $p.WaitForExit()
      return [pscustomobject]@{ Code = $p.ExitCode; Out = $so.Result; Err = $se.Result }
    }
    function Get-BlobText {
      param([string]$Dir, [string]$Spec)
      $psi = New-Object System.Diagnostics.ProcessStartInfo
      $psi.FileName = 'git'
      $psi.Arguments = '-C "' + $Dir + '" show ' + $Spec
      $psi.UseShellExecute = $false
      $psi.RedirectStandardOutput = $true
      $p = [System.Diagnostics.Process]::Start($psi)
      $ms = New-Object System.IO.MemoryStream
      $p.StandardOutput.BaseStream.CopyTo($ms)
      $p.WaitForExit()
      return $script:Utf8.GetString($ms.ToArray())
    }
    function New-GitOnlyBin {
      param([string]$Name)
      $b = Join-Path $TestDrive $Name
      New-Item -ItemType Directory -Force -Path $b | Out-Null
      $git = (Get-Command git).Source
      if ($script:IsWin) {
        [IO.File]::WriteAllText((Join-Path $b 'git.cmd'), "@echo off`r`n`"$git`" %*`r`n")
      } else {
        $p = Join-Path $b 'git'
        [IO.File]::WriteAllText($p, "#!/bin/sh`nexec `"$git`" `"`$@`"`n")
        & chmod +x $p
      }
      return $b
    }
    $script:Good = "# Changelog`n`n## [unreleased]`n`n## [unreleased] $script:Dash a`n`nBody`n"
  }

  It 'prints the plan of a UTF-8 em dash CHANGELOG written as bytes with -DryRun and exits 0' {
    $d = New-Project 'plan' $script:Good
    $r = Invoke-Script $d '-DryRun -NoRemote -Version v9'
    $r.Code | Should -Be 0 -Because ("stdout=[" + $r.Out + "] stderr=[" + $r.Err + "]")
    $lines = $r.Out -split "\r?\n"
    $lines[0] | Should -Be ('## aai-release (plan) ' + $script:Dash + ' no files changed')
    $lines | Should -Contain ('  5:## [v9] ' + $script:Dash + ' a')
    $lines | Should -Contain ('- none ' + $script:Dash + ' ready to cut with -Confirm')
    (Invoke-Git $d @('status', '--porcelain')) | Should -Be ''
  }

  It 'refuses a malformed [unreleased] heading with exit 12 and the REFUSED line only' {
    $d = New-Project 'bad' "# Changelog`n`n## [unreleased] foo`n`nx`n"
    $r = Invoke-Script $d '-DryRun -NoRemote -Version v9'
    $r.Code | Should -Be 12 -Because ("stdout=[" + $r.Out + "] stderr=[" + $r.Err + "]")
    $r.Err.Trim() | Should -Be ("REFUSED: malformed [unreleased] heading in CHANGELOG.md (a '## [unreleased]' line has unexpected trailing text or a stray heading-only body) $script:Dash never silently dropping entries.")
    $r.Out | Should -Be ''
  }

  It 'cuts the local release branch whose CHANGELOG equals the expected bytes with -Confirm -NoRemote' {
    $d = New-Project 'cut' $script:Good
    $r = Invoke-Script $d '-Confirm -NoRemote -Version v9'
    $r.Code | Should -Be 0 -Because ("stdout=[" + $r.Out + "] stderr=[" + $r.Err + "]")
    $want = "# Changelog`n`n## [unreleased]`n`n## [v9] $script:Dash a`n`nBody`n"
    (Get-BlobText $d 'chore/release-v9:CHANGELOG.md') | Should -BeExactly $want
  }

  It 'refuses missing release notes on one line followed by the Resume line' {
    $d = New-Project 'notes' $script:Good
    [void](Invoke-Git $d @('tag', 'v0'))
    New-Item -ItemType Directory -Force -Path (Join-Path $d '.aai') | Out-Null
    [IO.File]::WriteAllText((Join-Path $d '.aai/f13.txt'), "13`n")
    [void](Invoke-Git $d @('add', '-A'))
    [void](Invoke-Git $d @('commit', '-q', '-m', 'fix: other (#13)'))
    [IO.File]::WriteAllText((Join-Path $d '.aai/f14.txt'), "14`n")
    [void](Invoke-Git $d @('add', '-A'))
    [void](Invoke-Git $d @('commit', '-q', '-m', 'fix: another (#14)'))
    $r = Invoke-Script $d '-Confirm -NoRemote -Version v9'
    $r.Code | Should -Be 20 -Because ("stdout=[" + $r.Out + "] stderr=[" + $r.Err + "]")
    $err = @($r.Err -split "\r?\n" | Where-Object { $_ -ne '' })
    $err.Count | Should -Be 2
    $err[0] | Should -Be ('REFUSED: missing-notes ' + $script:Dash + ' #14 fix: another; #13 fix: other')
    $err[1] | Should -BeLike 'Resume: pwsh -NoProfile -File "*aai-release.ps1" -Version v9 -Confirm -NoRemote'
    (Invoke-Git $d @('branch', '--list', 'chore/release-v9')) | Should -Be ''
  }

  It 'names a missing node with exit 20 when PATH holds no node' {
    $d = New-Project 'nonode' $script:Good
    $bin = New-GitOnlyBin 'gitonly'
    $r = Invoke-Script $d '-DryRun -Version v9' $bin
    $r.Code | Should -Be 20 -Because ("stdout=[" + $r.Out + "] stderr=[" + $r.Err + "]")
    $r.Err.Trim() | Should -Be ('REFUSED: missing-node ' + $script:Dash + ' Node.js 22 or later is required for /aai-release (https://nodejs.org/); nothing was changed.')
    $r.Out | Should -Be ''
  }

  It 'refuses an existing tag with exit 15 before the audit' {
    $d = New-Project 'tagged' $script:Good
    [void](Invoke-Git $d @('tag', 'v9'))
    $r = Invoke-Script $d '-Confirm -NoRemote -Version v9'
    $r.Code | Should -Be 15 -Because ("stdout=[" + $r.Out + "] stderr=[" + $r.Err + "]")
    $r.Err.Trim() | Should -Be 'REFUSED: tag v9 already exists.'
  }

  It 'DB-10 relays the cut report on the success stream of the caller' {
    $d = New-Project 'db10' $script:Good
    $cmd = "`$o = @(& '" + $script:Script + "' -Confirm -NoRemote -Version v9); [Console]::Out.Write('CAPTURED=' + `$o.Count + '|' + `$o[0])"
    $r = Invoke-Engine $d ('-NoProfile -NonInteractive -Command "' + ($cmd -replace '"', '\"') + '"')
    $r.Code | Should -Be 0 -Because ("stdout=[" + $r.Out + "] stderr=[" + $r.Err + "]")
    $m = [regex]::Match($r.Out, '^CAPTURED=(\d+)\|(.*)$', 'Singleline')
    $m.Success | Should -BeTrue -Because $r.Out
    [int]$m.Groups[1].Value | Should -Be 5
    $m.Groups[2].Value.Trim() | Should -Be ('## aai-release ' + $script:Dash + ' cut complete')
  }

  It 'DB-19 dot-sourcing the launcher defines nothing and runs nothing' {
    $d = Join-Path $TestDrive 'dot'
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    $cmd = ". '" + $script:Script + "'; if (Get-Command Invoke-NativeChecked, Invoke-Quiet, Select-CapturedValue -ErrorAction SilentlyContinue) { 'DEFINED' } else { 'CLEAN' }"
    $r = Invoke-Engine $d ('-NoProfile -NonInteractive -Command "' + ($cmd -replace '"', '\"') + '"')
    $r.Code | Should -Be 0 -Because ("stdout=[" + $r.Out + "] stderr=[" + $r.Err + "]")
    $r.Out.Trim() | Should -Be 'CLEAN'
    $r.Err | Should -Be ''
  }

  It 'DB-21 -Version with no value gets the PowerShell binder error, exit 1, and nothing runs' {
    $d = New-Project 'db21' $script:Good
    $head = Invoke-Git $d @('rev-parse', 'HEAD')
    $r = Invoke-Script $d '-NoRemote -Version'
    $r.Code | Should -Be 1 -Because ("stdout=[" + $r.Out + "] stderr=[" + $r.Err + "]")
    $r.Out | Should -Be ''
    $r.Err | Should -Match 'Version'
    (Invoke-Git $d @('rev-parse', 'HEAD')) | Should -Be $head
    (Invoke-Git $d @('branch', '--list', 'chore/release-*')) | Should -Be ''
  }

  It 'prints the usage in the ps1 spelling with -h and exits 0' {
    $d = New-Project 'help' $script:Good
    $r = Invoke-Script $d '-h'
    $r.Code | Should -Be 0 -Because ("stdout=[" + $r.Out + "] stderr=[" + $r.Err + "]")
    ($r.Out -split "\r?\n")[0] | Should -Be 'usage: aai-release.ps1 [-Version <v>] [-DryRun] [-Confirm] [-NoRemote]'
    $r.Err | Should -Be ''
  }

  It 'accepts --version=v9 as an extra argument and refuses an unknown argument on two stderr lines' {
    $d = New-Project 'extra' $script:Good
    $ok = Invoke-Script $d '-DryRun -NoRemote --version=v9'
    $ok.Code | Should -Be 0 -Because ("stdout=[" + $ok.Out + "] stderr=[" + $ok.Err + "]")
    ($ok.Out -split "\r?\n") | Should -Contain '- Resolved version: v9'
    $bad = Invoke-Script $d '-DryRun --bogus'
    $bad.Code | Should -Be 1
    @($bad.Err -split "\r?\n" | Where-Object { $_ -ne '' }) | Should -Be @('Unknown argument: --bogus', 'Run with --help for usage.')
    $bad.Out | Should -Be ''
  }

  It 'keeps exit 12 for a malformed CHANGELOG when a caller under ErrorActionPreference Stop captures stderr' {
    $d = New-Project 'captured' "# Changelog`n`n## [unreleased] foo`n`nx`n"
    $cmd = "`$ErrorActionPreference = 'Stop'; & '" + $script:Script + "' -DryRun -NoRemote -Version v9; exit `$LASTEXITCODE"
    $r = Invoke-Engine $d ('-NoProfile -NonInteractive -Command "' + ($cmd -replace '"', '\"') + '"')
    $r.Code | Should -Be 12 -Because ("stdout=[" + $r.Out + "] stderr=[" + $r.Err + "]")
    $r.Err | Should -BeLike 'REFUSED: malformed [[]unreleased] heading*'
  }
}
