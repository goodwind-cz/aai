# triage launcher parity (spec-node-first-second-slice, TEST-2513).
# Each case launches .aai/scripts/triage.ps1 from a scratch git repository with
# the engine running the test ((Get-Process -Id $PID).Path), so the Windows
# PowerShell 5.1 step tests 5.1 and the pwsh 7 steps test pwsh 7. Assertions read
# ASCII lines only. No case may skip.
Describe 'triage launcher' {
  BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:Launcher = Join-Path $Root '.aai/scripts/triage.ps1'
    $script:Module = Join-Path $Root '.aai/scripts/triage.mjs'
    $script:Engine = (Get-Process -Id $PID).Path
    $script:Scratch = Join-Path ([IO.Path]::GetTempPath()) ('aai triage ' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $Scratch | Out-Null
    $script:Utf8 = New-Object System.Text.UTF8Encoding $false
    $script:Counter = 0
    $script:Unknown = '### Triage verdict: UNKNOWN (node or triage.mjs unavailable)'

    function Invoke-Proc {
      param([string]$File, [string]$ArgLine, [string]$WorkDir)
      $psi = New-Object System.Diagnostics.ProcessStartInfo
      $psi.FileName = $File
      $psi.Arguments = $ArgLine
      $psi.WorkingDirectory = $WorkDir
      $psi.UseShellExecute = $false
      $psi.RedirectStandardOutput = $true
      $psi.RedirectStandardError = $true
      $psi.StandardOutputEncoding = $script:Utf8
      $p = [System.Diagnostics.Process]::Start($psi)
      $out = $p.StandardOutput.ReadToEnd()
      $err = $p.StandardError.ReadToEnd()
      $p.WaitForExit()
      return [pscustomobject]@{ ExitCode = $p.ExitCode; Stdout = $out; Stderr = $err }
    }
    function New-Fixture {
      param([string]$AuditJs, [switch]$NoModule)
      $script:Counter++
      $dir = Join-Path $script:Scratch ('fx' + $script:Counter)
      $scripts = Join-Path $dir '.aai/scripts'
      New-Item -ItemType Directory -Force -Path $scripts | Out-Null
      Copy-Item -LiteralPath $script:Launcher -Destination $scripts
      if (-not $NoModule) { Copy-Item -LiteralPath $script:Module -Destination $scripts }
      if ($AuditJs) { [IO.File]::WriteAllText((Join-Path $scripts 'docs-audit.mjs'), $AuditJs, $script:Utf8) }
      $null = Invoke-Proc -File 'git' -ArgLine 'init -q -b main' -WorkDir $dir
      $null = Invoke-Proc -File 'git' -ArgLine 'add -A' -WorkDir $dir
      $null = Invoke-Proc -File 'git' -ArgLine '-c user.email=t@example.invalid -c user.name=T commit -q -m init' -WorkDir $dir
      return $dir
    }
    function Invoke-Launcher {
      param([string]$Dir, [string]$Flag)
      $argLine = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $Dir '.aai/scripts/triage.ps1') + '"'
      if ($Flag) { $argLine = $argLine + ' ' + $Flag }
      return (Invoke-Proc -File $script:Engine -ArgLine $argLine -WorkDir $Dir)
    }
    function Get-Lines {
      param($Result)
      return @($Result.Stdout -split "`r?`n")
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

  It 'prints the header, state, tree and tick lines and a CLEAN verdict for a clean fixture' {
    $dir = New-Fixture
    $r = Invoke-Launcher -Dir $dir
    $r.ExitCode | Should -Be 0
    $lines = Get-Lines $r
    $lines[0] | Should -Match '^## AAI L1 Triage - \d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$'
    $lines | Should -Contain '- State: not present yet (docs/ai/STATE.yaml) - orchestrator will init, or run /aai-check-state'
    $lines | Should -Contain '- Working tree: clean'
    $lines | Should -Contain '- Last tick: none recorded'
    $lines | Should -Contain '### Triage verdict: CLEAN'
  }

  It 'reads project_status from a STATE.yaml written with a UTF-8 BOM' {
    $dir = New-Fixture
    New-Item -ItemType Directory -Force -Path (Join-Path $dir 'docs/ai') | Out-Null
    $bytes = [byte[]](0xEF, 0xBB, 0xBF) + $script:Utf8.GetBytes("project_status: active`n")
    [IO.File]::WriteAllBytes((Join-Path $dir 'docs/ai/STATE.yaml'), $bytes)
    $r = Invoke-Launcher -Dir $dir
    $r.ExitCode | Should -Be 0
    (Get-Lines $r) | Should -Contain '- State: present (project_status=active)'
  }

  It 'exits 1 under -Check and 0 without it when the audit prints NEEDS-TRIAGE' {
    $dir = New-Fixture -AuditJs 'process.stdout.write("- Mode: quick\n### Verdict: NEEDS-TRIAGE\n");'
    $checked = Invoke-Launcher -Dir $dir -Flag '-Check'
    $checked.ExitCode | Should -Be 1
    (Get-Lines $checked) | Should -Contain '### Triage verdict: NEEDS-ATTENTION (1 area(s))'
    $plain = Invoke-Launcher -Dir $dir
    $plain.ExitCode | Should -Be 0
  }

  It 'exits 1 under a literal --check when the audit prints NEEDS-TRIAGE' {
    $dir = New-Fixture -AuditJs 'process.stdout.write("- Mode: quick\n### Verdict: NEEDS-TRIAGE\n");'
    $r = Invoke-Launcher -Dir $dir -Flag '--check'
    $r.ExitCode | Should -Be 1
  }

  It 'treats a lower-case needs-triage as CLEAN and exits 0 under -Check' {
    $dir = New-Fixture -AuditJs 'process.stdout.write("- mode: quick\n### verdict: needs-triage\n");'
    $r = Invoke-Launcher -Dir $dir -Flag '-Check'
    $r.ExitCode | Should -Be 0
    $lines = Get-Lines $r
    $lines | Should -Contain '### Triage verdict: CLEAN'
    $lines | Should -Contain '- Docs audit: (no output)'
  }

  It 'prints exactly the UNKNOWN line and exits 0 when triage.mjs is absent' {
    $dir = New-Fixture -NoModule
    foreach ($flag in @('', '-Check')) {
      $r = Invoke-Launcher -Dir $dir -Flag $flag
      $r.ExitCode | Should -Be 0
      $r.Stdout.TrimEnd("`r", "`n") | Should -BeExactly $script:Unknown
      $r.Stderr | Should -BeExactly ''
    }
  }

  It 'runs on Node 22 or newer' {
    $v = (& node --version) | Select-Object -First 1
    Write-Host "node --version: $v"
    $v | Should -Match '^v\d+\.'
    [int]($v.TrimStart('v').Split('.')[0]) | Should -BeGreaterOrEqual 22
  }
}
