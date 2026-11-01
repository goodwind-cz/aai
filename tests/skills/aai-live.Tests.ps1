# aai-live launcher cases (spec-node-first-small-pairs, TEST-3210).
# Each case launches .aai/scripts/aai-live.ps1 with the engine running the test
# ((Get-Process -Id $PID).Path), so the Windows PowerShell 5.1 step tests 5.1 and
# the pwsh 7 steps test pwsh 7, in a scratch root that holds the launcher, the
# module and a generator stub. The opener is a stub in a directory whose name
# holds a space: a .cmd on Windows, a shell script elsewhere. No case may skip.
Describe 'aai-live launcher' {
  BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:Launcher = Join-Path $Root '.aai/scripts/aai-live.ps1'
    $script:Module = Join-Path $Root '.aai/scripts/aai-live.mjs'
    $script:Engine = (Get-Process -Id $PID).Path
    $script:IsWin = [IO.Path]::DirectorySeparatorChar -eq '\'
    $script:Scratch = Join-Path ([IO.Path]::GetTempPath()) ('aai live ' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $script:Scratch | Out-Null
    $script:Utf8 = New-Object System.Text.UTF8Encoding $false
    $script:Counter = 0
    $script:Refused = 'aai-live: refused - node not found in PATH or aai-live.mjs missing'
    # The generator stub writes the file named by --output (default docs/ai/live-status.html) and exits with STUB_RC.
    $script:GenSource = @'
import fs from 'node:fs';
import path from 'node:path';
const a = process.argv.slice(2);
const i = a.lastIndexOf('--output');
const out = i >= 0 ? a[i + 1] : 'docs/ai/live-status.html';
if (!a.includes('--data-only')) {
  fs.mkdirSync(path.dirname(path.resolve(out)), { recursive: true });
  fs.writeFileSync(path.resolve(out), '<html></html>');
}
process.exit(Number(process.env.STUB_RC || 0));
'@

    function Invoke-Proc {
      param([string]$File, [string]$ArgLine, [string]$WorkDir, [hashtable]$Env = @{})
      $psi = New-Object System.Diagnostics.ProcessStartInfo
      $psi.FileName = $File
      $psi.Arguments = $ArgLine
      $psi.WorkingDirectory = $WorkDir
      $psi.UseShellExecute = $false
      $psi.RedirectStandardOutput = $true
      $psi.RedirectStandardError = $true
      $psi.StandardOutputEncoding = $script:Utf8
      foreach ($k in $Env.Keys) { $psi.EnvironmentVariables[$k] = $Env[$k] }
      $p = [System.Diagnostics.Process]::Start($psi)
      $out = $p.StandardOutput.ReadToEnd()
      $err = $p.StandardError.ReadToEnd()
      $p.WaitForExit()
      return [pscustomobject]@{ ExitCode = $p.ExitCode; Stdout = $out; Stderr = $err }
    }
    function New-Root {
      param([switch]$NoModule)
      $script:Counter++
      $dir = Join-Path $script:Scratch ('root ' + $script:Counter)
      $scripts = Join-Path $dir '.aai/scripts'
      New-Item -ItemType Directory -Force -Path $scripts | Out-Null
      Copy-Item -LiteralPath $script:Launcher -Destination $scripts
      if (-not $NoModule) { Copy-Item -LiteralPath $script:Module -Destination $scripts }
      [IO.File]::WriteAllText((Join-Path $scripts 'generate-live-status.mjs'), $script:GenSource, $script:Utf8)
      return $dir
    }
    function New-Opener {
      # A stub that appends ARG=<first argument> and ARG2=<second argument> to its log; returns @{ Path; Log }.
      $script:Counter++
      $dir = Join-Path $script:Scratch ('opener dir ' + $script:Counter)
      New-Item -ItemType Directory -Force -Path $dir | Out-Null
      $log = Join-Path $dir 'opener.log'
      if ($script:IsWin) {
        $path = Join-Path $dir 'opener.cmd'
        $text = "@echo off`r`necho ARG=%~1>>`"$log`"`r`necho ARG2=%~2>>`"$log`"`r`n"
      } else {
        $path = Join-Path $dir 'opener.sh'
        $text = "#!/bin/sh`necho `"ARG=`$1`" >> `"$log`"`necho `"ARG2=`$2`" >> `"$log`"`n"
      }
      [IO.File]::WriteAllText($path, $text, $script:Utf8)
      if (-not $script:IsWin) { & chmod +x $path }
      return @{ Path = $path; Log = $log }
    }
    function Invoke-Launcher {
      param([string]$Dir, [string]$ArgText, [hashtable]$Env = @{})
      $argLine = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $Dir '.aai/scripts/aai-live.ps1') + '"'
      if ($ArgText) { $argLine = $argLine + ' ' + $ArgText }
      return (Invoke-Proc -File $script:Engine -ArgLine $argLine -WorkDir $Dir -Env $Env)
    }
    function Get-Lines {
      param([string]$Text)
      return @(($Text -split "`r?`n") | Where-Object { $_ -ne '' })
    }
  }

  AfterAll {
    if ($script:Scratch -and (Test-Path -LiteralPath $script:Scratch)) {
      Remove-Item -LiteralPath $script:Scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  It 'parses with zero errors' {
    $errs = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($script:Launcher, [ref]$null, [ref]$errs)
    $errs.Count | Should -Be 0
  }

  It 'a one-shot --output run hands the opener exactly one argument, the absolute page path' {
    $dir = New-Root
    $op = New-Opener
    $r = Invoke-Launcher -Dir $dir -ArgText '--output custom/page.html' -Env @{ AAI_LIVE_OPENER = $op.Path }
    $r.ExitCode | Should -Be 0
    $page = Join-Path $dir 'custom/page.html'
    Test-Path -LiteralPath $page | Should -BeTrue
    $lines = Get-Lines ([IO.File]::ReadAllText($op.Log))
    $lines.Count | Should -Be 2
    $lines[0] | Should -BeLike 'ARG=*'
    $arg = $lines[0].Substring(4)
    [IO.Path]::IsPathRooted($arg) | Should -BeTrue
    $arg | Should -Match 'custom[\\/]page\.html$'
    (Get-Item -LiteralPath $arg).FullName | Should -Be (Get-Item -LiteralPath $page).FullName
    $lines[1] | Should -BeExactly 'ARG2='
  }

  It '--data-only opens nothing' {
    $dir = New-Root
    $op = New-Opener
    $r = Invoke-Launcher -Dir $dir -ArgText '--data-only' -Env @{ AAI_LIVE_OPENER = $op.Path }
    $r.ExitCode | Should -Be 0
    Test-Path -LiteralPath $op.Log | Should -BeFalse
  }

  It 'the generator exit code is forwarded and nothing is opened after a failure' {
    $dir = New-Root
    $op = New-Opener
    $r = Invoke-Launcher -Dir $dir -ArgText '--output custom/page.html' -Env @{ AAI_LIVE_OPENER = $op.Path; STUB_RC = '3' }
    $r.ExitCode | Should -Be 3
    Test-Path -LiteralPath $op.Log | Should -BeFalse
  }

  It 'prints exactly the refusal line and exits 1 when aai-live.mjs is absent' {
    $dir = New-Root -NoModule
    $r = Invoke-Launcher -Dir $dir -ArgText '--data-only'
    $r.ExitCode | Should -Be 1
    $r.Stderr.TrimEnd("`r", "`n") | Should -BeExactly $script:Refused
    $r.Stdout | Should -BeExactly ''
  }

  It 'runs on Node 22 or newer' {
    $v = (& node --version) | Select-Object -First 1
    Write-Host "node --version: $v"
    $v | Should -Match '^v\d+\.'
    [int]($v.TrimStart('v').Split('.')[0]) | Should -BeGreaterOrEqual 22
  }
}
