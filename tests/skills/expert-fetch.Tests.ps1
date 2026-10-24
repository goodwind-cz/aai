# expert-fetch launcher parity (spec-node-first-third-slice, TEST-2617).
# Each case launches .aai/scripts/expert-fetch.ps1 with the engine running the
# test ((Get-Process -Id $PID).Path), so the Windows PowerShell 5.1 step tests 5.1
# and the pwsh 7 steps test pwsh 7, in a scratch root that holds the launcher, the
# module and a fixture registry. Assertions read ASCII lines only. No case may skip.
Describe 'expert-fetch launcher' {
  BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:Launcher = Join-Path $Root '.aai/scripts/expert-fetch.ps1'
    $script:Module = Join-Path $Root '.aai/scripts/expert-fetch.mjs'
    $script:Engine = (Get-Process -Id $PID).Path
    $script:Scratch = Join-Path ([IO.Path]::GetTempPath()) ('aai expert ' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $script:Scratch | Out-Null
    $script:Utf8 = New-Object System.Text.UTF8Encoding $false
    $script:Utf8Bom = New-Object System.Text.UTF8Encoding $true
    $script:Counter = 0
    $script:Unavailable = 'ERROR: expert-fetch needs node (expert-fetch.mjs unavailable)'
    $real = [IO.File]::ReadAllText((Join-Path $script:Root '.aai/system/EXPERT_REGISTRY.yaml'), $script:Utf8)
    $extra = "  zblocked:`n    path: 09-meta-orchestration/orchestrator.md`n    use_in: [implementation]`n" +
      "  znouse:`n    path: 02-language-specialists/znouse.md`n  zafter:`n    path: 02-language-specialists/zafter.md`n    use_in: [tdd-green]`n"
    $script:Registry = $real.TrimEnd("`r", "`n") + "`n" + $extra
    $script:Sha = [regex]::Match($script:Registry, 'pinned_sha:\s*"([^"]+)"').Groups[1].Value

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
    function New-Fixture {
      param([switch]$NoModule)
      $script:Counter++
      $dir = Join-Path $script:Scratch ('fx' + $script:Counter)
      $scripts = Join-Path $dir '.aai/scripts'
      New-Item -ItemType Directory -Force -Path $scripts | Out-Null
      New-Item -ItemType Directory -Force -Path (Join-Path $dir '.aai/system') | Out-Null
      Copy-Item -LiteralPath $script:Launcher -Destination $scripts
      if (-not $NoModule) { Copy-Item -LiteralPath $script:Module -Destination $scripts }
      [IO.File]::WriteAllText((Join-Path $dir '.aai/system/EXPERT_REGISTRY.yaml'), $script:Registry, $script:Utf8)
      return $dir
    }
    function Invoke-Launcher {
      param([string]$Dir, [string]$Args1, [hashtable]$Env = @{})
      $argLine = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $Dir '.aai/scripts/expert-fetch.ps1') + '"'
      if ($Args1) { $argLine = $argLine + ' ' + $Args1 }
      return (Invoke-Proc -File $script:Engine -ArgLine $argLine -WorkDir $Dir -Env $Env)
    }
    function Get-Lines {
      param([string]$Text)
      return @(($Text -split "`r?`n") | Where-Object { $_ -ne '' })
    }
    function Write-Cache {
      param([string]$Dir, [string]$Key, [string]$Prompt, [string]$ShaText)
      $cache = Join-Path $Dir '.aai/cache/experts'
      New-Item -ItemType Directory -Force -Path $cache | Out-Null
      [IO.File]::WriteAllText((Join-Path $cache ($Key + '.md')), $Prompt, $script:Utf8Bom)
      [IO.File]::WriteAllText((Join-Path $cache ('.sha_' + $Key)), $ShaText, $script:Utf8Bom)
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

  It '-List prints as many keys as the registry holds' {
    $dir = New-Fixture
    $want = [regex]::Matches($script:Registry, '(?m)^  [a-z][a-z0-9_-]*:[ \t\r]*$').Count
    $r = Invoke-Launcher -Dir $dir -Args1 '-List'
    $r.ExitCode | Should -Be 0
    (Get-Lines $r.Stdout).Count | Should -Be $want
    (Get-Lines $r.Stdout) | Should -Contain 'typescript'
  }

  It '-Detect forwards every token: .TSX py docker prints docker and python' {
    $dir = New-Fixture
    $r = Invoke-Launcher -Dir $dir -Args1 '-Detect .TSX py docker'
    $r.ExitCode | Should -Be 0
    (Get-Lines $r.Stdout) | Should -Be @('docker', 'python')
  }

  It '-Check typescript -Phase implementation prints eligible and exits 0' {
    $dir = New-Fixture
    $r = Invoke-Launcher -Dir $dir -Args1 '-Check typescript -Phase implementation'
    $r.ExitCode | Should -Be 0
    (Get-Lines $r.Stdout) | Should -Be @('eligible')
  }

  It '-Check znouse -Phase tdd-green prints not-found and exits 2' {
    $dir = New-Fixture
    $r = Invoke-Launcher -Dir $dir -Args1 '-Check znouse -Phase tdd-green'
    $r.ExitCode | Should -Be 2
    (Get-Lines $r.Stdout) | Should -Be @('not-found')
  }

  It 'a fetch of an unknown key exits 2' {
    $dir = New-Fixture
    $r = Invoke-Launcher -Dir $dir -Args1 '-ExpertKey nosuch'
    $r.ExitCode | Should -Be 2
    (Get-Lines $r.Stderr) | Should -Contain "ERROR: Expert 'nosuch' not found in registry"
  }

  It 'a fetch of an expert in a blocked category exits 1 without a gh call' {
    $dir = New-Fixture
    $r = Invoke-Launcher -Dir $dir -Args1 '-ExpertKey zblocked' -Env @{ AAI_GH_BIN = (Join-Path $dir 'no-such-gh') }
    $r.ExitCode | Should -Be 1
    (Get-Lines $r.Stderr) | Should -Contain "ERROR: Category '09-meta-orchestration' is blocked in registry"
  }

  It '-Body prints the body of a cache file written with a UTF-8 BOM' {
    $dir = New-Fixture
    Write-Cache -Dir $dir -Key 'typescript' -Prompt "---`nname: ts`n---`n# Title`nbody line`n" -ShaText $script:Sha
    $r = Invoke-Launcher -Dir $dir -Args1 '-Body typescript'
    $r.ExitCode | Should -Be 0
    (Get-Lines $r.Stdout) | Should -Be @('# Title', 'body line')
  }

  It 'a cache hit with BOM files prints the cache path without any gh call' {
    $dir = New-Fixture
    Write-Cache -Dir $dir -Key 'typescript' -Prompt "---`nname: ts`n---`nbody`n" -ShaText ($script:Sha + "`r`n")
    $r = Invoke-Launcher -Dir $dir -Args1 '-ExpertKey typescript' -Env @{ AAI_GH_BIN = (Join-Path $dir 'no-such-gh') }
    $r.ExitCode | Should -Be 0
    $lines = @(Get-Lines $r.Stdout)
    $lines.Count | Should -Be 1
    $line = $lines[0]
    $line | Should -Match 'typescript\.md$'
    Test-Path -LiteralPath $line | Should -BeTrue
  }

  It 'a fetch without a cache and without a usable gh exits 1 and creates no cache file' {
    $dir = New-Fixture
    $r = Invoke-Launcher -Dir $dir -Args1 '-ExpertKey typescript' -Env @{ AAI_GH_BIN = (Join-Path $dir 'no-such-gh') }
    $r.ExitCode | Should -Be 1
    $r.Stderr | Should -Match 'ERROR: Failed to fetch'
    Test-Path -LiteralPath (Join-Path $dir '.aai/cache/experts/typescript.md') | Should -BeFalse
  }

  It 'prints exactly the node-unavailable line and exits 1 when expert-fetch.mjs is absent' {
    $dir = New-Fixture -NoModule
    $r = Invoke-Launcher -Dir $dir -Args1 '-List'
    $r.ExitCode | Should -Be 1
    $r.Stderr.TrimEnd("`r", "`n") | Should -BeExactly $script:Unavailable
    $r.Stdout | Should -BeExactly ''
  }

  It 'runs on Node 22 or newer' {
    $v = (& node --version) | Select-Object -First 1
    Write-Host "node --version: $v"
    $v | Should -Match '^v\d+\.'
    [int]($v.TrimStart('v').Split('.')[0]) | Should -BeGreaterOrEqual 22
  }
}
