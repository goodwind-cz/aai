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
      param([string]$Payload, [string]$Kind, [string]$SpoolDir, [string]$LauncherPath)
      $psi = New-Object System.Diagnostics.ProcessStartInfo
      $psi.FileName = $script:Engine
      if (-not $LauncherPath) { $LauncherPath = $script:Launcher }
      $kindArg = ''
      if ($Kind) { $kindArg = ' ' + $Kind }
      $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $LauncherPath + '"' + $kindArg
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
      $err = $p.StandardError.ReadToEnd()
      $p.WaitForExit()
      return [pscustomobject]@{ ExitCode = $p.ExitCode; Stdout = $out; Stderr = $err }
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
    $r.Stderr | Should -BeExactly ''
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
    $r.Stderr | Should -BeExactly ''
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
    $r.Stderr | Should -BeExactly ''
    @(Get-Content -LiteralPath (Join-Path $dir 'hooks.jsonl')).Count | Should -Be 1
  }

  It 'writes exactly one line for a 1 MB object payload and keeps stderr empty' {
    $dir = New-SpoolDir
    $pad = 'a' * 1048576
    $r = Invoke-Launcher -Payload ('{"session_id":"s1","cwd":"/x","pad":"' + $pad + '"}') -Kind 'statusline' -SpoolDir $dir
    $r.ExitCode | Should -Be 0
    $r.Stderr | Should -BeExactly ''
    @(Get-Content -LiteralPath (Join-Path $dir 'statusline.jsonl')).Count | Should -Be 1
  }

  It 'prints exactly the passthrough line when no argument is given' {
    $dir = New-SpoolDir
    $r = Invoke-Launcher -Payload '' -Kind '' -SpoolDir $dir
    $r.ExitCode | Should -Be 0
    $r.Stdout.TrimEnd("`r", "`n") | Should -BeExactly '(aai-live tap active)'
  }

  It 'prints the passthrough and writes nothing when the module is absent' {
    $dir = New-SpoolDir
    $copyDir = Join-Path $script:Scratch 'nomodule'
    New-Item -ItemType Directory -Force -Path $copyDir | Out-Null
    $copy = Join-Path $copyDir 'live-spool.ps1'
    Copy-Item -LiteralPath $script:Launcher -Destination $copy
    $r = Invoke-Launcher -Payload '{"cwd":"/x"}' -Kind 'statusline' -SpoolDir $dir -LauncherPath $copy
    $r.ExitCode | Should -Be 0
    $r.Stdout.TrimEnd("`r", "`n") | Should -BeExactly '(aai-live tap active)'
    Test-Path -LiteralPath $dir | Should -BeFalse
  }

  It 'DIAGNOSTIC (temporary, PR #495): reports how stdin reaches the launcher and node' {
    function Invoke-Raw {
      param([string]$File, [string]$Arguments, [string]$Payload, [string]$SpoolDir)
      $psi = New-Object System.Diagnostics.ProcessStartInfo
      $psi.FileName = $File
      $psi.Arguments = $Arguments
      $psi.UseShellExecute = $false
      $psi.RedirectStandardInput = $true
      $psi.RedirectStandardOutput = $true
      $psi.RedirectStandardError = $true
      if ($SpoolDir) { $psi.EnvironmentVariables['AAI_LIVE_SPOOL_DIR'] = $SpoolDir }
      $p = [System.Diagnostics.Process]::Start($psi)
      $bytes = $script:Utf8.GetBytes($Payload)
      $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
      $p.StandardInput.BaseStream.Flush()
      $p.StandardInput.Close()
      $out = $p.StandardOutput.ReadToEnd()
      $err = $p.StandardError.ReadToEnd()
      $p.WaitForExit()
      return "rc=$($p.ExitCode) out=[$($out.Trim())] err=[$($err.Trim())]"
    }
    $payload = '{"session_id":"s1","cwd":"/x"}'
    $d = Join-Path $script:Scratch 'diag'
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    $nodePath = (Get-Command node -CommandType Application | Select-Object -First 1).Source
    $module = Join-Path $script:Root '.aai/scripts/live-spool.mjs'
    Set-Content -LiteralPath (Join-Path $d 'p1.ps1') -Value 'Write-Output ("redir=" + [Console]::IsInputRedirected + " inenc=" + [Console]::InputEncoding.WebName)'
    Set-Content -LiteralPath (Join-Path $d 'p2.ps1') -Value '$ms = New-Object System.IO.MemoryStream; [Console]::OpenStandardInput().CopyTo($ms); Write-Output ("openstdin_bytes=" + $ms.Length)'
    Set-Content -LiteralPath (Join-Path $d 'p3.ps1') -Value '$a = @($input); Write-Output ("input_count=" + $a.Count + " first=" + ($a | Select-Object -First 1))'
    Set-Content -LiteralPath (Join-Path $d 'p4.ps1') -Value '& node -e "let n=0;try{n=require(''fs'').readFileSync(0).length}catch(e){console.log(''node_err=''+e.code)};console.log(''node_inherited_bytes=''+n)"'
    $js = Join-Path $d 'p5.mjs'
    Set-Content -LiteralPath $js -Value ("import { pathToFileURL } from 'node:url'; const m = await import(pathToFileURL(process.argv[2]).href); const t = m.readStdin(); console.log('readStdin_len=' + t.length); const l = m.projectPayload(t, 'statusline'); console.log('line=' + l); try { m.appendCapped(process.argv[3] + '/x.jsonl', l || '{}'); console.log('append=ok') } catch (e) { console.log('append_err=' + e.stack) }")
    foreach ($n in 'p1','p2','p3','p4') {
      $r = Invoke-Raw -File $script:Engine -Arguments ('-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $d ($n + '.ps1')) + '"') -Payload $payload
      Write-Host "AAI-DIAG $n $r"
    }
    Write-Host ("AAI-DIAG node-direct-module " + (Invoke-Raw -File $nodePath -Arguments ('"' + $module + '" statusline') -Payload $payload -SpoolDir (Join-Path $d 'sp1')))
    Write-Host ("AAI-DIAG node-direct-module spool exists=" + (Test-Path -LiteralPath (Join-Path $d 'sp1\statusline.jsonl')))
    Write-Host ("AAI-DIAG node-p5 " + (Invoke-Raw -File $nodePath -Arguments ('"' + $js + '" "' + $module + '" "' + $d + '"') -Payload $payload))
    $r6 = Invoke-Raw -File $script:Engine -Arguments ('-NoProfile -ExecutionPolicy Bypass -File "' + $script:Launcher + '" statusline') -Payload $payload -SpoolDir (Join-Path $d 'sp2')
    Write-Host ("AAI-DIAG launcher " + $r6 + " spool exists=" + (Test-Path -LiteralPath (Join-Path $d 'sp2\statusline.jsonl')))
    $true | Should -BeTrue
  }

  It 'runs on Node 22 or newer' {
    $v = (& node --version) | Select-Object -First 1
    Write-Host "node --version: $v"
    $v | Should -Match '^v\d+\.'
    [int]($v.TrimStart('v').Split('.')[0]) | Should -BeGreaterOrEqual 22
  }
}
