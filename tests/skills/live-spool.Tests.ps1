# live-spool launcher parity (spec-node-first-sync-hook-slice, TEST-2412).
# Each case launches .aai/scripts/live-spool.ps1 with the engine running the
# test ((Get-Process -Id $PID).Path), so the Windows PowerShell 5.1 step tests
# 5.1 and the pwsh 7 steps test pwsh 7. The payload bytes are written to the
# launcher's standard input as UTF-8 by this test. No case may skip.
Describe 'live-spool launcher' {
  BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:Launcher = Join-Path $Root '.aai/scripts/live-spool.ps1'
    $script:Engine = (Get-Process -Id $PID).Path
    $script:Scratch = Join-Path ([IO.Path]::GetTempPath()) ('aai live spool ' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $Scratch | Out-Null
    $script:Utf8 = New-Object System.Text.UTF8Encoding $false
    $script:Counter = 0

    function Invoke-Launcher {
      param([string]$Payload, [string]$Kind, [string]$SpoolDir)
      $psi = New-Object System.Diagnostics.ProcessStartInfo
      $psi.FileName = $script:Engine
      $kindArg = ''
      if ($Kind) { $kindArg = ' ' + $Kind }
      $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $script:Launcher + '"' + $kindArg
      $psi.UseShellExecute = $false
      $psi.RedirectStandardInput = $true
      $psi.RedirectStandardOutput = $true
      $psi.RedirectStandardError = $true
      $psi.StandardOutputEncoding = $script:Utf8
      $psi.EnvironmentVariables['AAI_LIVE_SPOOL_DIR'] = $SpoolDir
      $p = [System.Diagnostics.Process]::Start($psi)
      $bytes = $script:Utf8.GetBytes($Payload)
      $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
      $p.StandardInput.BaseStream.Flush()
      $p.StandardInput.Close()
      $out = $p.StandardOutput.ReadToEnd()
      $null = $p.StandardError.ReadToEnd()
      $p.WaitForExit()
      return [pscustomobject]@{ ExitCode = $p.ExitCode; Stdout = $out }
    }
    function New-SpoolDir {
      $script:Counter++
      return (Join-Path $script:Scratch ('spool' + $script:Counter))
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

  It 'writes one whitelisted line with a 3-digit ts for an object payload' {
    $dir = New-SpoolDir
    $r = Invoke-Launcher -Payload '{"session_id":"s1","cwd":"/x","model":"m","rate_limits":{"five_hour":{"used_percent":33}},"transcript_path":"/t"}' -Kind 'statusline' -SpoolDir $dir
    $r.ExitCode | Should -Be 0
    $lines = @(Get-Content -LiteralPath (Join-Path $dir 'statusline.jsonl'))
    $lines.Count | Should -Be 1
    $lines[0] | Should -Match '^\{"ts":"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z","session_id":"s1","cwd":"/x","model":"m","rate_limits":\{"five_hour":\{"used_percent":33\}\}\}$'
    $lines[0] | Should -Not -Match 'transcript_path'
  }

  It 'round-trips a non-ASCII payload as UTF-8 without BOM and with LF only' {
    $dir = New-SpoolDir
    $text = 'Opus ' + [char]0x2713 + ' ' + [char]0x010D + [char]0x0159
    $r = Invoke-Launcher -Payload ('{"model":{"display_name":"' + $text + '"}}') -Kind 'statusline' -SpoolDir $dir
    $r.ExitCode | Should -Be 0
    $bytes = [IO.File]::ReadAllBytes((Join-Path $dir 'statusline.jsonl'))
    ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
    ($bytes -contains 13) | Should -BeFalse
    $decoded = $script:Utf8.GetString($bytes)
    $decoded.Contains($text) | Should -BeTrue
    $decoded.EndsWith("`n") | Should -BeTrue
  }

  It 'creates no spool file for an array payload' {
    $dir = New-SpoolDir
    $r = Invoke-Launcher -Payload '[1,2,3]' -Kind 'statusline' -SpoolDir $dir
    $r.ExitCode | Should -Be 0
    Test-Path -LiteralPath (Join-Path $dir 'statusline.jsonl') | Should -BeFalse
  }

  It 'prints nothing and exits 0 for the hooks kind' {
    $dir = New-SpoolDir
    $r = Invoke-Launcher -Payload '{"hook_event_name":"Stop"}' -Kind 'hooks' -SpoolDir $dir
    $r.ExitCode | Should -Be 0
    $r.Stdout | Should -BeExactly ''
    @(Get-Content -LiteralPath (Join-Path $dir 'hooks.jsonl')).Count | Should -Be 1
  }

  It 'prints exactly the passthrough line when no argument is given' {
    $dir = New-SpoolDir
    $r = Invoke-Launcher -Payload '' -Kind '' -SpoolDir $dir
    $r.ExitCode | Should -Be 0
    $r.Stdout.TrimEnd("`r", "`n") | Should -BeExactly '(aai-live tap active)'
  }

  It 'runs on Node 22 or newer' {
    $v = (& node --version) | Select-Object -First 1
    Write-Host "node --version: $v"
    $v | Should -Match '^v\d+\.'
    [int]($v.TrimStart('v').Split('.')[0]) | Should -BeGreaterOrEqual 22
  }
}
