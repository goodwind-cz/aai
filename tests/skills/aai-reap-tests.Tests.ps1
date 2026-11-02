# aai-reap-tests launcher cases (spec-node-first-reap-tests, TEST-3239).
# Each case launches .aai/scripts/aai-reap-tests.ps1 with the engine running the test
# ((Get-Process -Id $PID).Path), so the Windows PowerShell 5.1 step tests 5.1 and the
# pwsh 7 steps test pwsh 7. Fixtures are Node sleepers that exit by themselves after
# 90 s, started in a fresh scratch workspace; every started process is stopped by id
# in AfterEach, nothing is ever killed by name, and a final scan fails the file if a
# command line still holds the scratch root. No case may skip.
Describe 'aai-reap-tests launcher' {
  BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:Launcher = Join-Path $Root '.aai/scripts/aai-reap-tests.ps1'
    $script:Module = Join-Path $Root '.aai/scripts/aai-reap-tests.mjs'
    $script:Engine = (Get-Process -Id $PID).Path
    $script:Node = (Get-Command node -ErrorAction Stop).Source
    $script:IsWin = [IO.Path]::DirectorySeparatorChar -eq '\'
    $script:Scratch = Join-Path ([IO.Path]::GetTempPath()) ('aai-reap-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $script:Scratch | Out-Null
    # A POSIX process reports its physical working directory (/var is /private/var on macOS), so the scratch root is
    # the physical path there; on Windows the path stays as given, which is what the engine passes on.
    if (-not $script:IsWin) { $script:Scratch = (& node -e 'process.stdout.write(require("fs").realpathSync(process.argv[1]))' $script:Scratch) }
    $script:Started = New-Object System.Collections.ArrayList
    $script:Refused = 'aai-reap-tests: refused - node not found in PATH or aai-reap-tests.mjs missing; nothing was reaped'

    function Start-Sleeper {
      param([string]$Dir)
      $psi = New-Object System.Diagnostics.ProcessStartInfo
      $psi.FileName = $script:Node
      $psi.Arguments = '-e "setTimeout(function(){},90000)" vitest "' + (Join-Path $Dir 'worker') + '"'
      $psi.UseShellExecute = $false
      $psi.CreateNoWindow = $true
      $p = [System.Diagnostics.Process]::Start($psi)
      [void]$script:Started.Add($p)
      return $p
    }
    function New-Workspace {
      param([string]$Name)
      $dir = Join-Path $script:Scratch $Name
      New-Item -ItemType Directory -Force -Path $dir | Out-Null
      return $dir
    }
    function Invoke-Launcher {
      param([string]$LauncherPath, [string]$WorkDir, [hashtable]$Env = @{})
      $psi = New-Object System.Diagnostics.ProcessStartInfo
      $psi.FileName = $script:Engine
      $psi.Arguments = '-NoProfile -File "' + $LauncherPath + '"'
      $psi.WorkingDirectory = $WorkDir
      $psi.UseShellExecute = $false
      $psi.RedirectStandardOutput = $true
      $psi.RedirectStandardError = $true
      foreach ($k in @('AAI_REAP_WORKSPACE', 'AAI_REAP_MIN_AGE_SECS', 'AAI_REAP_STEP_START_EPOCH', 'AAI_REAP_GRACE_SECS')) {
        [void]$psi.EnvironmentVariables.Remove($k)
      }
      foreach ($k in $Env.Keys) { $psi.EnvironmentVariables[$k] = $Env[$k] }
      $p = [System.Diagnostics.Process]::Start($psi)
      $out = $p.StandardOutput.ReadToEnd()
      $err = $p.StandardError.ReadToEnd()
      $p.WaitForExit()
      return [pscustomobject]@{ ExitCode = $p.ExitCode; Stdout = $out; Stderr = $err }
    }
    function Wait-Exit {
      param($Process, [int]$Millis = 5000)
      return $Process.WaitForExit($Millis)
    }
    function Get-CommandLines {
      if ($script:IsWin) { return @(Get-CimInstance Win32_Process | ForEach-Object { [string]$_.CommandLine }) }
      return @((& ps axo 'args=') | ForEach-Object { [string]$_ })
    }
    function Get-Epoch { return [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
  }

  AfterEach {
    foreach ($p in @($script:Started)) {
      if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    }
    foreach ($p in @($script:Started)) { [void]$p.WaitForExit(3000) }
    $script:Started.Clear()
  }

  AfterAll {
    $leftover = @(Get-CommandLines | Where-Object { $_ -and $_.Contains($script:Scratch) })
    Remove-Item -LiteralPath $script:Scratch -Recurse -Force -ErrorAction SilentlyContinue
    if ($leftover.Count -gt 0) { throw ('processes still hold the scratch root: ' + ($leftover -join ' | ')) }
  }

  It 'kills a pre-step in-workspace match and spares a sibling workspace and a post-step match' {
    $ws = New-Workspace 'ws'
    $other = New-Workspace 'other'
    $old = Start-Sleeper $ws
    $sibling = Start-Sleeper $other
    Start-Sleep -Seconds 4
    $step = Get-Epoch
    Start-Sleep -Milliseconds 1100
    $post = Start-Sleeper $ws
    $r = Invoke-Launcher -LauncherPath $script:Launcher -WorkDir $script:Root -Env @{
      AAI_REAP_WORKSPACE = $ws; AAI_REAP_STEP_START_EPOCH = [string]$step; AAI_REAP_GRACE_SECS = '0' }
    $r.ExitCode | Should -Be 0
    (Wait-Exit $old) | Should -BeTrue
    $sibling.HasExited | Should -BeFalse
    $post.HasExited | Should -BeFalse
    $r.Stdout | Should -Match 'reaped: 1'
    $r.Stdout | Should -Match ('reaped pids: ' + $old.Id)
  }

  It 'reaps the in-workspace match when run from a pushed location without AAI_REAP_WORKSPACE' {
    $ws = New-Workspace 'pushed'
    $old = Start-Sleeper $ws
    Start-Sleep -Seconds 2
    $saved = @{}
    foreach ($k in @('AAI_REAP_WORKSPACE', 'AAI_REAP_MIN_AGE_SECS', 'AAI_REAP_STEP_START_EPOCH', 'AAI_REAP_GRACE_SECS')) {
      $saved[$k] = [Environment]::GetEnvironmentVariable($k)
      [Environment]::SetEnvironmentVariable($k, $null)
    }
    [Environment]::SetEnvironmentVariable('AAI_REAP_MIN_AGE_SECS', '1')
    Push-Location -LiteralPath $ws
    try { $out = (& $script:Engine -NoProfile -File $script:Launcher 2>&1) -join "`n"; $code = $LASTEXITCODE }
    finally {
      Pop-Location
      foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    }
    $code | Should -Be 0
    (Wait-Exit $old) | Should -BeTrue
    $out | Should -Match 'reaped: 1'
  }

  It 'matches a workspace whose name holds a non-ASCII letter' {
    $ws = New-Workspace ('w' + [char]0x00E9 + 's')
    $old = Start-Sleeper $ws
    Start-Sleep -Seconds 2
    $r = Invoke-Launcher -LauncherPath $script:Launcher -WorkDir $script:Root -Env @{
      AAI_REAP_WORKSPACE = $ws; AAI_REAP_MIN_AGE_SECS = '1' }
    $r.ExitCode | Should -Be 0
    (Wait-Exit $old) | Should -BeTrue
    $r.Stdout | Should -Match 'reaped: 1'
  }

  It 'prints the refusal line and exits 1 for a launcher copy without the module' {
    $dir = New-Workspace 'nomodule'
    $copy = Join-Path $dir 'aai-reap-tests.ps1'
    Copy-Item -LiteralPath $script:Launcher -Destination $copy
    $r = Invoke-Launcher -LauncherPath $copy -WorkDir $dir
    $r.ExitCode | Should -Be 1
    $r.Stdout | Should -BeNullOrEmpty
    $r.Stderr.TrimEnd() | Should -Be $script:Refused
  }
}
