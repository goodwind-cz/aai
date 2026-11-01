# validate-skills launcher parity (spec-node-first-small-pairs, TEST-3205).
# Each case launches .aai/scripts/validate-skills.ps1 with the engine running the
# test ((Get-Process -Id $PID).Path), so the Windows PowerShell 5.1 step tests 5.1
# and the pwsh 7 steps test pwsh 7, in a scratch root that holds the launcher and
# the module. Assertions read ASCII lines only. No case may skip.
Describe 'validate-skills launcher' {
  BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:Launcher = Join-Path $Root '.aai/scripts/validate-skills.ps1'
    $script:Module = Join-Path $Root '.aai/scripts/validate-skills.mjs'
    $script:Engine = (Get-Process -Id $PID).Path
    $script:Scratch = Join-Path ([IO.Path]::GetTempPath()) ('aai skills ' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $script:Scratch | Out-Null
    $script:Utf8 = New-Object System.Text.UTF8Encoding $false
    $script:Counter = 0
    $script:Unavailable = 'ERROR: validate-skills needs node (validate-skills.mjs unavailable)'
    $script:Required = @(
      '.aai/SKILL_CHECK_STATE.prompt.md', '.aai/SKILL_INTAKE.prompt.md', '.aai/SKILL_LOOP.prompt.md',
      '.aai/SKILL_HITL.prompt.md', '.aai/SKILL_BOOTSTRAP.prompt.md', '.aai/SKILL_VALIDATE_REPORT.prompt.md',
      '.aai/SKILL_CANONICALIZE.prompt.md', '.aai/SKILL_TDD.prompt.md', '.aai/SKILL_WORKTREE.prompt.md',
      '.aai/SKILL_CODE_REVIEW.prompt.md', '.aai/SKILL_SHARE.prompt.md', '.aai/scripts/aai-bootstrap.sh')

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
    function New-Target {
      param([string]$Skip = '')
      $script:Counter++
      $dir = Join-Path $script:Scratch ('target ' + $script:Counter)
      foreach ($rel in $script:Required) {
        if ($rel -eq $Skip) { continue }
        $path = Join-Path $dir $rel
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
        [IO.File]::WriteAllText($path, '', $script:Utf8)
      }
      $marker = Join-Path $dir '.claude/skills/AAI_DYNAMIC_SKILLS.md'
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $marker) | Out-Null
      [IO.File]::WriteAllText($marker, '', $script:Utf8)
      $ticks = Join-Path $dir 'docs/ai/LOOP_TICKS.jsonl'
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ticks) | Out-Null
      [IO.File]::WriteAllText($ticks, '{"mode":"skill"}' + "`n", $script:Utf8)
      return $dir
    }
    function New-LauncherDir {
      param([switch]$NoModule)
      $script:Counter++
      $dir = Join-Path $script:Scratch ('launcher ' + $script:Counter)
      New-Item -ItemType Directory -Force -Path $dir | Out-Null
      Copy-Item -LiteralPath $script:Launcher -Destination $dir
      if (-not $NoModule) { Copy-Item -LiteralPath $script:Module -Destination $dir }
      return $dir
    }
    function Invoke-Launcher {
      param([string]$LauncherDir, [string]$ArgText)
      $argLine = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $LauncherDir 'validate-skills.ps1') + '"'
      if ($ArgText) { $argLine = $argLine + ' ' + $ArgText }
      return (Invoke-Proc -File $script:Engine -ArgLine $argLine -WorkDir $script:Scratch)
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

  It 'a full fixture passed as -TargetRoot exits 0 and prints the four lines' {
    $target = New-Target
    $r = Invoke-Launcher -LauncherDir (New-LauncherDir) -ArgText ('-TargetRoot "' + $target + '"')
    $r.ExitCode | Should -Be 0
    $lines = @(Get-Lines $r.Stdout)
    $lines.Count | Should -Be 4
    $lines[0] | Should -Match '^Validating skills in: '
    $lines[1] | Should -BeExactly 'OK: dynamic skills bootstrap marker exists (.claude/skills/AAI_DYNAMIC_SKILLS.md)'
    $lines[2] | Should -BeExactly 'OK: LOOP_TICKS.jsonl contains skill-mode evidence.'
    $lines[3] | Should -BeExactly 'Skill validation completed.'
    $r.Stderr | Should -BeExactly ''
  }

  It 'a missing required file prints the ERROR line on stderr and exits 1' {
    $target = New-Target -Skip '.aai/SKILL_TDD.prompt.md'
    $r = Invoke-Launcher -LauncherDir (New-LauncherDir) -ArgText ('-TargetRoot "' + $target + '"')
    $r.ExitCode | Should -Be 1
    $errLines = @(Get-Lines $r.Stderr)
    $errLines.Count | Should -Be 1
    $errLines[0] | Should -Match '^ERROR: Missing required file: .*SKILL_TDD\.prompt\.md$'
  }

  It 'a positional target works like -TargetRoot' {
    $target = New-Target
    $r = Invoke-Launcher -LauncherDir (New-LauncherDir) -ArgText ('"' + $target + '"')
    $r.ExitCode | Should -Be 0
    (Get-Lines $r.Stdout)[-1] | Should -BeExactly 'Skill validation completed.'
  }

  It 'a missing target prints the Target-not-found line and exits 1' {
    $nope = Join-Path $script:Scratch 'no such target'
    $r = Invoke-Launcher -LauncherDir (New-LauncherDir) -ArgText ('-TargetRoot "' + $nope + '"')
    $r.ExitCode | Should -Be 1
    (Get-Lines $r.Stderr) | Should -Be @('ERROR: Target not found: ' + $nope)
  }

  It 'prints exactly the node-unavailable line and exits 1 when validate-skills.mjs is absent' {
    $target = New-Target
    $r = Invoke-Launcher -LauncherDir (New-LauncherDir -NoModule) -ArgText ('-TargetRoot "' + $target + '"')
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
