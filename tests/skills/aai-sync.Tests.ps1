# aai-sync.ps1 launcher cases (spec-sync-on-node, D-PESTER, TEST-4016).
# The .ps1 is a thin launcher of the Node module aai-sync.mjs. Each case launches it with the engine running the test
# ((Get-Process -Id $PID).Path), so the Windows PowerShell 5.1 step tests 5.1 and the pwsh 7 steps test pwsh 7, through
# ProcessStartInfo with an explicit PATH. Every directory lives in $TestDrive, and git runs with no system config and an
# empty global config. No case may skip.
Describe 'aai-sync.ps1' {
  Context 'launcher (sync-on-node)' {
    BeforeAll {
      $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
      $script:Engine = (Get-Process -Id $PID).Path
      $script:ScriptsDir = Join-Path (Join-Path $script:Root '.aai') 'scripts'
      $script:Launcher = Join-Path $script:ScriptsDir 'aai-sync.ps1'
      $script:Refused = 'aai-sync: refused - node not found in PATH or aai-sync.mjs missing; nothing was changed. Install Node.js 22 or later (https://nodejs.org/) and re-run.'
      $script:GitGlobal = Join-Path $TestDrive 'empty-gitconfig'
      [IO.File]::WriteAllText($script:GitGlobal, '')

      function New-LaunchDir {
        param([string]$Name)
        $d = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Force -Path $d | Out-Null
        return $d
      }
      function Invoke-Engine {
        param([string]$EngineArgs, [string]$WorkDir, [string]$Path, [string]$EnginePath = $script:Engine)
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $EnginePath
        $psi.Arguments = $EngineArgs
        $psi.WorkingDirectory = $WorkDir
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.EnvironmentVariables['PATH'] = $Path
        foreach ($k in @($psi.EnvironmentVariables.Keys)) { if ("$k" -like 'GIT_*') { $psi.EnvironmentVariables.Remove("$k") } }
        $psi.EnvironmentVariables['GIT_CONFIG_NOSYSTEM'] = '1'
        $psi.EnvironmentVariables['GIT_CONFIG_GLOBAL'] = $script:GitGlobal
        $p = [System.Diagnostics.Process]::Start($psi)
        $out = $p.StandardOutput.ReadToEnd()
        $err = $p.StandardError.ReadToEnd()
        $p.WaitForExit()
        return [pscustomobject]@{ ExitCode = $p.ExitCode; Stdout = $out; Stderr = $err }
      }
      function Invoke-LauncherFile {
        param([string]$Launcher, [string]$WorkDir, [string]$LauncherArgs, [string]$Path)
        return (Invoke-Engine -EngineArgs (('-NoProfile -NonInteractive -File "' + $Launcher + '" ' + $LauncherArgs).Trim()) -WorkDir $WorkDir -Path $Path)
      }
      # in session: one child engine runs the launcher as a command, so the arguments are parsed as PowerShell code and the
      # launcher's exit code is handed on explicitly (-Command otherwise reports only success or failure)
      function Invoke-LauncherSession {
        param([string]$Launcher, [string]$WorkDir, [string]$LauncherArgs, [string]$Path)
        return (Invoke-Engine -EngineArgs ('-NoProfile -NonInteractive -Command "& ''' + $Launcher + ''' ' + $LauncherArgs + '; exit $LASTEXITCODE"') -WorkDir $WorkDir -Path $Path)
      }
      function Write-StubModule {
        param([string]$Dir)
        [IO.File]::WriteAllText((Join-Path $Dir 'aai-sync.mjs'), "console.log(JSON.stringify({ argv: process.argv.slice(2) }));`nprocess.exit(7);`n")
      }
      function New-TargetRepo {
        param([string]$Name)
        $d = New-LaunchDir $Name
        $ErrorActionPreference = 'Continue'
        [void](& git -C $d init -q 2>&1)
        return $d
      }
      function Get-Names {
        param([string]$Dir)
        return @(Get-ChildItem -LiteralPath $Dir -Recurse -Force | Where-Object { $_.FullName -notmatch '[\\/]\.git([\\/]|$)' } | ForEach-Object { $_.FullName })
      }
    }

    It 'passes every argument through under -File in order and keeps the module exit code' {
      $d = New-LaunchDir 'launch-pass'
      Copy-Item -LiteralPath $script:Launcher -Destination (Join-Path $d 'aai-sync.ps1')
      Write-StubModule $d
      $r = Invoke-LauncherFile (Join-Path $d 'aai-sync.ps1') $d '-TargetRoot "C D" -Profile core -- x' $env:PATH
      $r.ExitCode | Should -Be 7 -Because "stderr: $($r.Stderr)"
      $got = $r.Stdout | ConvertFrom-Json
      @($got.argv) | Should -Be @('-TargetRoot', 'C D', '-Profile', 'core', '--', 'x')
    }

    It 'marshals in-session arguments: -TargetRoot:value is a flag and a value, a comma array is one value, -Flag:$false drops the token before it' {
      $d = New-LaunchDir 'launch-session'
      Copy-Item -LiteralPath $script:Launcher -Destination (Join-Path $d 'aai-sync.ps1')
      Write-StubModule $d
      $t = Join-Path $TestDrive 'session-target'
      $r = Invoke-LauncherSession (Join-Path $d 'aai-sync.ps1') $d ('-TargetRoot:' + $t + ' -Profile core') $env:PATH
      $r.ExitCode | Should -Be 7 -Because "stderr: $($r.Stderr)"
      $got = $r.Stdout | ConvertFrom-Json
      @($got.argv) | Should -Be @('-TargetRoot', $t, '-Profile', 'core')
      $r2 = Invoke-LauncherSession (Join-Path $d 'aai-sync.ps1') $d '-Profile core,extended -Profile:$false' $env:PATH
      $r2.ExitCode | Should -Be 7 -Because "stderr: $($r2.Stderr)"
      $got2 = $r2.Stdout | ConvertFrom-Json
      @($got2.argv) | Should -Be @('-Profile', 'core,extended')
    }

    It 'hands a -TargetRoot that holds a space and ends in a backslash to the module unchanged (D-PS51), through powershell.exe on Windows and pwsh elsewhere' {
      $d = New-LaunchDir 'launch-backslash'
      Copy-Item -LiteralPath $script:Launcher -Destination (Join-Path $d 'aai-sync.ps1')
      Write-StubModule $d
      $isWin = ($env:OS -eq 'Windows_NT')
      $enginePath = if ($isWin) { Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' } else { $script:Engine }
      # the child engine reads this command line with the usual Windows rules, so the trailing backslash is doubled before the closing quote
      $r = Invoke-Engine ('-NoProfile -NonInteractive -File "' + (Join-Path $d 'aai-sync.ps1') + '" -TargetRoot "C:\My Projects\app\\"') $d $env:PATH $enginePath
      $r.ExitCode | Should -Be 7 -Because "stderr: $($r.Stderr)"
      $got = $r.Stdout | ConvertFrom-Json
      @($got.argv) | Should -Be @('-TargetRoot', 'C:\My Projects\app\')
    }

    It 'refuses with the one line, prints nothing on stdout and changes nothing when node is not on PATH' {
      $d = New-LaunchDir 'launch-nonode'
      $target = New-TargetRepo 'launch-nonode-target'
      $emptyPath = New-LaunchDir 'launch-empty-path'
      Copy-Item -LiteralPath $script:Launcher -Destination (Join-Path $d 'aai-sync.ps1')
      Write-StubModule $d
      $before = Get-Names $target
      $r = Invoke-LauncherFile (Join-Path $d 'aai-sync.ps1') $target ('-TargetRoot "' + $target + '" -Profile core') $emptyPath
      $r.ExitCode | Should -Be 1
      $r.Stdout | Should -Be ''
      $r.Stderr.Trim() | Should -Be $script:Refused
      @(Get-Names $target).Count | Should -Be @($before).Count
    }

    It 'refuses the same way when the module is missing next to the launcher' {
      $d = New-LaunchDir 'launch-nomodule'
      $target = New-TargetRepo 'launch-nomodule-target'
      Copy-Item -LiteralPath $script:Launcher -Destination (Join-Path $d 'aai-sync.ps1')
      $before = Get-Names $target
      $r = Invoke-LauncherFile (Join-Path $d 'aai-sync.ps1') $target ('-TargetRoot "' + $target + '"') $env:PATH
      $r.ExitCode | Should -Be 1
      $r.Stdout | Should -Be ''
      $r.Stderr.Trim() | Should -Be $script:Refused
      @(Get-Names $target).Count | Should -Be @($before).Count
    }

    It 'runs the real module in session: -TargetRoot -Profile core exits 0 and pins the core profile, and -Profile bogus exits 2' {
      $src = New-LaunchDir 'launch-real-src'
      $sd = Join-Path (Join-Path $src '.aai') 'scripts'
      $sl = Join-Path $sd 'lib'
      $sys = Join-Path (Join-Path $src '.aai') 'system'
      New-Item -ItemType Directory -Force -Path $sd, $sl, $sys | Out-Null
      foreach ($f in @('aai-sync.mjs', 'aai-sync.ps1', 'aai-sync.sh')) { Copy-Item -LiteralPath (Join-Path $script:ScriptsDir $f) -Destination $sd }
      foreach ($f in @('resolve-base.mjs', 'gitignore-block.mjs', 'merge-hooks-json.mjs')) { Copy-Item -LiteralPath (Join-Path (Join-Path $script:ScriptsDir 'lib') $f) -Destination $sl }
      [IO.File]::WriteAllText((Join-Path (Join-Path $src '.aai') 'AGENTS.md'), "fixture agents`n")
      [IO.File]::WriteAllText((Join-Path $sys 'PROFILES.yaml'), "core:`n  - .aai/AGENTS.md`n  - .aai/scripts/aai-sync.mjs`nextended:`n  - .aai/other.md`n")
      $target = New-TargetRepo 'launch-real-target'
      $launcher = Join-Path $sd 'aai-sync.ps1'
      $r = Invoke-LauncherSession $launcher $target ('-TargetRoot "' + $target + '" -Profile core') $env:PATH
      $r.ExitCode | Should -Be 0 -Because "stderr: $($r.Stderr)"
      $pin = Get-Content -LiteralPath (Join-Path (Join-Path (Join-Path $target '.aai') 'system') 'AAI_PIN.md') -Raw
      $pin | Should -Match '(?m)^- Profile: core\r?$'
      Test-Path -LiteralPath (Join-Path (Join-Path $target '.aai') 'AGENTS.md') | Should -BeTrue
      $bad = New-TargetRepo 'launch-real-bogus'
      $before = Get-Names $bad
      $r2 = Invoke-LauncherSession $launcher $bad ('-TargetRoot "' + $bad + '" -Profile bogus') $env:PATH
      $r2.ExitCode | Should -Be 2
      @(Get-Names $bad).Count | Should -Be @($before).Count
    }
  }
}
