# cloudflare-share launcher cases (spec-cloudflare-share-on-node, TEST-3425).
# Each case launches cloudflare-share.ps1 with the engine running the test ((Get-Process -Id $PID).Path),
# so the Windows PowerShell 5.1 step tests 5.1 and the pwsh 7 steps test pwsh 7. Fixtures are git
# repositories in TestDrive with a local identity and a stub wrangler first on PATH (wrangler.cmd on
# Windows, an executable script elsewhere); nothing reaches the network or touches the checkout. No case may skip.
Describe 'cloudflare-share launcher' {
  BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:Launcher = Join-Path $Root '.aai/scripts/cloudflare-share.ps1'
    $script:Engine = (Get-Process -Id $PID).Path
    $script:IsWin = [IO.Path]::DirectorySeparatorChar -eq '\'
    $script:Url = 'https://abc123.my-repo.aai-reports.pages.dev'
    $script:Usage = 'Usage: cloudflare-share <document.md>'
    $script:Refused = 'cloudflare-share: refused - node not found in PATH or cloudflare-share.mjs missing; nothing was published. Install Node.js 22 or later (https://nodejs.org/) and re-run.'

    function Invoke-Git {
      param([string]$Dir, [string[]]$GitArgs)
      $ErrorActionPreference = 'Continue'
      $o = & git -C $Dir @GitArgs 2>&1
      return ($o | ForEach-Object { "$_" }) -join "`n"
    }
    function New-Project {
      param([string]$Name)
      $d = Join-Path $TestDrive $Name
      New-Item -ItemType Directory -Force -Path $d | Out-Null
      [IO.File]::WriteAllText((Join-Path $d 'my doc.md'), "# Title`n`nbody`n")
      [void](Invoke-Git $d @('init', '-q'))
      [void](Invoke-Git $d @('config', 'user.email', 'fixture@example.invalid'))
      [void](Invoke-Git $d @('config', 'user.name', 'fixture'))
      [void](Invoke-Git $d @('config', 'core.autocrlf', 'false'))
      [void](Invoke-Git $d @('config', 'commit.gpgsign', 'false'))
      [void](Invoke-Git $d @('add', '-A'))
      [void](Invoke-Git $d @('commit', '-q', '-m', 'fixture'))
      return $d
    }
    function New-Stub {
      param([string]$Name, [bool]$Fails = $false)
      $b = Join-Path $TestDrive $Name
      New-Item -ItemType Directory -Force -Path $b | Out-Null
      if ($script:IsWin) {
        $text = if ($Fails) { "@echo off`r`necho deploy failed`r`nexit /b 1`r`n" } else { "@echo off`r`necho $script:Url`r`n" }
        [IO.File]::WriteAllText((Join-Path $b 'wrangler.cmd'), $text)
      } else {
        $text = if ($Fails) { "#!/bin/sh`necho deploy failed`nexit 1`n" } else { "#!/bin/sh`necho $script:Url`n" }
        $p = Join-Path $b 'wrangler'
        [IO.File]::WriteAllText($p, $text)
        & chmod +x $p
      }
      return $b
    }
    function Invoke-Launcher {
      param([string]$WorkDir, [string]$LauncherArgs, [string]$Path)
      $psi = New-Object System.Diagnostics.ProcessStartInfo
      $psi.FileName = $script:Engine
      $psi.Arguments = ('-NoProfile -NonInteractive -File "' + $script:Launcher + '" ' + $LauncherArgs).Trim()
      $psi.WorkingDirectory = $WorkDir
      $psi.UseShellExecute = $false
      $psi.RedirectStandardOutput = $true
      $psi.RedirectStandardError = $true
      $psi.EnvironmentVariables['PATH'] = $Path
      $p = [System.Diagnostics.Process]::Start($psi)
      $out = $p.StandardOutput.ReadToEnd()
      $err = $p.StandardError.ReadToEnd()
      $p.WaitForExit()
      return [pscustomobject]@{ ExitCode = $p.ExitCode; Stdout = $out; Stderr = $err }
    }
    function Get-StubPath {
      param([string]$Bin)
      return $Bin + [IO.Path]::PathSeparator + $env:PATH
    }
    function Get-Records {
      param([string]$Dir)
      $h = Join-Path $Dir 'docs/ai/published/history.jsonl'
      if (-not (Test-Path -LiteralPath $h)) { return ,@() }
      return ,@(Get-Content -LiteralPath $h | Where-Object { $_ })
    }
  }

  It 'publishes a document whose path holds a space and records one line' {
    $d = New-Project 'My Repo'
    $r = Invoke-Launcher $d '"my doc.md"' (Get-StubPath (New-Stub 'bin-ok'))
    $r.ExitCode | Should -Be 0
    $r.Stderr | Should -Be ''
    $r.Stdout | Should -BeLike '*Document published successfully!*'
    $r.Stdout | Should -BeLike '*Document: my doc*'
    $r.Stdout | Should -BeLike "*URL: $script:Url*"
    $r.Stdout | Should -BeLike '*branch: my-repo*'
    Test-Path -LiteralPath (Join-Path $d '.cloudflare-publish') | Should -BeFalse
    $recs = Get-Records $d
    $recs.Count | Should -Be 1
    $rec = $recs[0] | ConvertFrom-Json
    $rec.document | Should -Be 'my doc.md'
    $rec.url | Should -Be $script:Url
  }

  It 'accepts the document by the parameter name -DocumentPath' {
    $d = New-Project 'By Name'
    $r = Invoke-Launcher $d '-DocumentPath "my doc.md"' (Get-StubPath (New-Stub 'bin-name'))
    $r.ExitCode | Should -Be 0
    $r.Stdout | Should -BeLike "*URL: $script:Url*"
    (Get-Records $d).Count | Should -Be 1
  }

  It 'prints the usage line on stderr and exits 1 with no argument and no prompt' {
    $d = New-Project 'No Arg'
    $r = Invoke-Launcher $d '' (Get-StubPath (New-Stub 'bin-noarg'))
    $r.ExitCode | Should -Be 1
    $r.Stdout | Should -Be ''
    $r.Stderr.Trim() | Should -Be $script:Usage
    Test-Path -LiteralPath (Join-Path $d '.cloudflare-publish') | Should -BeFalse
    (Get-Records $d).Count | Should -Be 0
  }

  It 'reports a missing document on stderr and exits 1' {
    $d = New-Project 'Missing'
    $r = Invoke-Launcher $d 'nope.md' (Get-StubPath (New-Stub 'bin-missing'))
    $r.ExitCode | Should -Be 1
    $r.Stdout | Should -Be ''
    $r.Stderr.Trim() | Should -Be 'ERROR: Document not found: nope.md'
    Test-Path -LiteralPath (Join-Path $d '.cloudflare-publish') | Should -BeFalse
  }

  It 'fails with exit 1 and no record when wrangler fails' {
    $d = New-Project 'Failing'
    $r = Invoke-Launcher $d '"my doc.md"' (Get-StubPath (New-Stub 'bin-fail' $true))
    $r.ExitCode | Should -Be 1
    $r.Stderr | Should -BeLike '*ERROR: Deployment failed or URL not found*'
    Test-Path -LiteralPath (Join-Path $d '.cloudflare-publish') | Should -BeFalse
    (Get-Records $d).Count | Should -Be 0
  }

  It 'prints the refusal line when node is not on PATH (DR-20)' {
    $d = New-Project 'No Node'
    $empty = Join-Path $TestDrive 'bin-empty'
    New-Item -ItemType Directory -Force -Path $empty | Out-Null
    $r = Invoke-Launcher $d '"my doc.md"' $empty
    $r.ExitCode | Should -Be 1
    $r.Stdout | Should -Be ''
    $r.Stderr.Trim() | Should -Be $script:Refused
    Test-Path -LiteralPath (Join-Path $d '.cloudflare-publish') | Should -BeFalse
    (Get-Records $d).Count | Should -Be 0
  }
}
