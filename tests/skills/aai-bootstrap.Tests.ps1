# aai-bootstrap launcher cases (spec-bootstrap-on-node, D-PESTER, TEST-3955).
# Each case launches aai-bootstrap.ps1 with the engine running the test ((Get-Process -Id $PID).Path), so the
# Windows PowerShell 5.1 step tests 5.1 and the pwsh 7 steps test pwsh 7. Every fixture lives in TestDrive and
# nothing touches the checkout. No case may skip.
Describe 'aai-bootstrap launcher' {
  BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:Launcher = Join-Path $Root '.aai/scripts/aai-bootstrap.ps1'
    $script:Engine = (Get-Process -Id $PID).Path
    $script:Refused = 'aai-bootstrap: refused - node not found in PATH or aai-bootstrap.mjs missing; nothing was written. Install Node.js 22 or later (https://nodejs.org/) and re-run.'

    function New-Dir {
      param([string]$Name)
      $d = Join-Path $TestDrive $Name
      New-Item -ItemType Directory -Force -Path $d | Out-Null
      return $d
    }
    function Invoke-Launcher {
      param([string]$LauncherPath, [string]$WorkDir, [string]$LauncherArgs, [string]$Path)
      $psi = New-Object System.Diagnostics.ProcessStartInfo
      $psi.FileName = $script:Engine
      $psi.Arguments = ('-NoProfile -NonInteractive -File "' + $LauncherPath + '" ' + $LauncherArgs).Trim()
      $psi.WorkingDirectory = $WorkDir
      $psi.UseShellExecute = $false
      $psi.RedirectStandardOutput = $true
      $psi.RedirectStandardError = $true
      $psi.EnvironmentVariables['PATH'] = $Path
      $psi.EnvironmentVariables['PWD'] = $WorkDir
      $p = [System.Diagnostics.Process]::Start($psi)
      $out = $p.StandardOutput.ReadToEnd()
      $err = $p.StandardError.ReadToEnd()
      $p.WaitForExit()
      return [pscustomobject]@{ ExitCode = $p.ExitCode; Stdout = $out; Stderr = $err }
    }
  }

  It 'passes every argument through in order and keeps the module exit code' {
    $d = New-Dir 'pass'
    Copy-Item -LiteralPath $script:Launcher -Destination (Join-Path $d 'aai-bootstrap.ps1')
    $stub = "import { writeFileSync } from 'node:fs';`nimport { dirname, join } from 'node:path';`nimport { fileURLToPath } from 'node:url';`n" +
      "writeFileSync(join(dirname(fileURLToPath(import.meta.url)), 'argv.json'), JSON.stringify(process.argv.slice(2)));`nprocess.exit(7);`n"
    [IO.File]::WriteAllText((Join-Path $d 'aai-bootstrap.mjs'), $stub)
    $r = Invoke-Launcher (Join-Path $d 'aai-bootstrap.ps1') $d '"dir with space" --dry-run --force --with-claude-hooks -h' $env:PATH
    $r.ExitCode | Should -Be 7
    $got = (Get-Content -LiteralPath (Join-Path $d 'argv.json') -Raw) | ConvertFrom-Json
    @($got) | Should -Be @('dir with space', '--dry-run', '--force', '--with-claude-hooks', '-h')
  }

  It 'refuses with the one line, writes nothing and exits 1 when node is not on PATH' {
    $d = New-Dir 'nonode'
    $target = New-Dir 'nonode-target'
    $emptyPath = New-Dir 'empty-path'
    $r = Invoke-Launcher $script:Launcher $d ('"' + $target + '"') $emptyPath
    $r.ExitCode | Should -Be 1
    $r.Stdout | Should -Be ''
    $r.Stderr.Trim() | Should -Be $script:Refused
    @(Get-ChildItem -LiteralPath $target -Force).Count | Should -Be 0
  }

  It 'refuses the same way when the module is missing next to the launcher' {
    $d = New-Dir 'nomodule'
    $target = New-Dir 'nomodule-target'
    Copy-Item -LiteralPath $script:Launcher -Destination (Join-Path $d 'aai-bootstrap.ps1')
    $r = Invoke-Launcher (Join-Path $d 'aai-bootstrap.ps1') $d ('"' + $target + '"') $env:PATH
    $r.ExitCode | Should -Be 1
    $r.Stdout | Should -Be ''
    $r.Stderr.Trim() | Should -Be $script:Refused
    @(Get-ChildItem -LiteralPath $target -Force).Count | Should -Be 0
  }

  It 'bootstraps a project whose path holds a space and records its native full path' {
    $d = New-Dir 'real target'
    [IO.File]::WriteAllText((Join-Path $d 'package.json'), '{"name":"fixture","scripts":{"test":"echo ok"}}')
    $r = Invoke-Launcher $script:Launcher $d ('"' + $d + '"') $env:PATH
    $r.ExitCode | Should -Be 0
    Test-Path -LiteralPath (Join-Path $d '.claude/skills/aai-test-unit/SKILL.md') | Should -BeTrue
    $marker = Get-Content -LiteralPath (Join-Path $d '.claude/skills/AAI_DYNAMIC_SKILLS.md')
    @($marker | Where-Object { $_ -ceq ('- Target root: ' + $d) }).Count | Should -Be 1
  }
}
