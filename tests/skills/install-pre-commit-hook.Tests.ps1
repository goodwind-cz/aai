# install-pre-commit-hook.ps1 cases (spec-git-hook-bodies-single-source, TEST-3435).
# Each case launches the ps1 installer with the engine running the test ((Get-Process -Id $PID).Path),
# so the Windows PowerShell 5.1 step tests 5.1 and the pwsh 7 steps test pwsh 7. Fixtures are fresh git
# repositories in TestDrive with a local identity and core.autocrlf false; the installer and the hook
# templates are vendored into the fixture, so nothing touches the checkout's own hooks. No case may skip.
Describe 'install-pre-commit-hook.ps1' {
  BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:Engine = (Get-Process -Id $PID).Path
    $script:IsWin = [IO.Path]::DirectorySeparatorChar -eq '\'
    $script:Slots = @('pre-commit', 'reference-transaction', 'pre-push')
    $script:Tpl = Join-Path (Join-Path (Join-Path $script:Root '.aai') 'templates') 'git-hooks'

    function Invoke-Git {
      param([string]$Dir, [string[]]$GitArgs)
      $ErrorActionPreference = 'Continue'
      $o = & git -C $Dir @GitArgs 2>&1
      return ($o | ForEach-Object { "$_" }) -join "`n"
    }
    function New-Repo {
      param([string]$Name)
      $d = Join-Path $TestDrive $Name
      New-Item -ItemType Directory -Force -Path $d | Out-Null
      [void](Invoke-Git $d @('init', '-q'))
      [void](Invoke-Git $d @('config', 'user.email', 'fixture@example.invalid'))
      [void](Invoke-Git $d @('config', 'user.name', 'fixture'))
      [void](Invoke-Git $d @('config', 'core.autocrlf', 'false'))
      [void](Invoke-Git $d @('config', 'commit.gpgsign', 'false'))
      return $d
    }
    # Copy-Installers: vendor both installers and the whole templates directory into <repo>/.aai/.
    function Copy-Installers {
      param([string]$Repo)
      $s = Join-Path (Join-Path $Repo '.aai') 'scripts'
      $t = Join-Path (Join-Path $Repo '.aai') 'templates'
      New-Item -ItemType Directory -Force -Path $s, $t | Out-Null
      Copy-Item -LiteralPath (Join-Path (Join-Path (Join-Path $script:Root '.aai') 'scripts') 'install-pre-commit-hook.ps1') -Destination $s
      Copy-Item -LiteralPath (Join-Path (Join-Path (Join-Path $script:Root '.aai') 'scripts') 'install-pre-commit-hook.sh') -Destination $s
      Copy-Item -LiteralPath $script:Tpl -Destination $t -Recurse
    }
    function Start-Proc {
      param([string]$File, [string]$ArgLine, [string]$WorkDir)
      $psi = New-Object System.Diagnostics.ProcessStartInfo
      $psi.FileName = $File
      $psi.Arguments = $ArgLine
      $psi.WorkingDirectory = $WorkDir
      $psi.UseShellExecute = $false
      $psi.RedirectStandardOutput = $true
      $psi.RedirectStandardError = $true
      $p = [System.Diagnostics.Process]::Start($psi)
      $out = $p.StandardOutput.ReadToEnd()
      $err = $p.StandardError.ReadToEnd()
      $p.WaitForExit()
      return [pscustomobject]@{ ExitCode = $p.ExitCode; Stdout = $out; Stderr = $err }
    }
    function Invoke-Ps1 {
      param([string]$Repo, [string]$Extra = '')
      $ps1 = Join-Path (Join-Path (Join-Path $Repo '.aai') 'scripts') 'install-pre-commit-hook.ps1'
      return (Start-Proc $script:Engine (('-NoProfile -NonInteractive -File "' + $ps1 + '" ' + $Extra).Trim()) $Repo)
    }
    function Get-GitBash {
      if ($script:IsWin) {
        $git = (Get-Command git -ErrorAction Stop).Source
        $gitRoot = Split-Path -Parent (Split-Path -Parent $git)
        foreach ($c in @('bin\bash.exe', 'usr\bin\bash.exe')) {
          $p = Join-Path $gitRoot $c
          if (Test-Path -LiteralPath $p) { return $p }
        }
      }
      return (Get-Command bash -ErrorAction Stop).Source
    }
    function Invoke-Sh {
      param([string]$Repo)
      $sh = (Join-Path (Join-Path (Join-Path $Repo '.aai') 'scripts') 'install-pre-commit-hook.sh') -replace '\\', '/'
      return (Start-Proc (Get-GitBash) ('"' + $sh + '"') $Repo)
    }
    function Get-Bytes {
      param([string]$Path)
      $b = [IO.File]::ReadAllBytes($Path)
      return ,[byte[]]$b
    }
    # Get-TemplateBytes: a template's bytes with every CR removed (what the installers write).
    function Get-TemplateBytes {
      param([string]$Dir, [string]$Name)
      $b = [IO.File]::ReadAllBytes((Join-Path $Dir $Name))
      $b = $b -ne 13
      return ,[byte[]]$b
    }
    # Get-Composed: the D-COMPOSE pre-commit bytes (line 1 of the index template, the guard block, the rest).
    function Get-Composed {
      param([string]$Dir)
      $i = Get-TemplateBytes $Dir 'pre-commit-index.sh'
      $g = Get-TemplateBytes $Dir 'pre-commit-guard-checks.sh'
      $nl = [Array]::IndexOf($i, [byte]10)
      return ,[byte[]]($i[0..$nl] + $g + $i[($nl + 1)..($i.Length - 1)])
    }
    function Get-Wanted {
      param([string]$Dir, [string]$Slot)
      if ($Slot -eq 'pre-commit') { return ,(Get-Composed $Dir) }
      if ($Slot -eq 'reference-transaction') { return ,(Get-TemplateBytes $Dir 'reference-transaction.sh') }
      return ,(Get-TemplateBytes $Dir 'pre-push.sh')
    }
    function Test-SameBytes {
      param([byte[]]$A, [byte[]]$B)
      return ([Convert]::ToBase64String($A) -eq [Convert]::ToBase64String($B))
    }
    function Get-HookPath {
      param([string]$Repo, [string]$Slot)
      return (Join-Path (Join-Path (Join-Path $Repo '.git') 'hooks') $Slot)
    }
  }

  It 'writes the three hooks equal to the template bytes, LF-only with a final newline' {
    $d = New-Repo 'fresh'
    Copy-Installers $d
    $r = Invoke-Ps1 $d
    $r.ExitCode | Should -Be 0
    foreach ($slot in $script:Slots) {
      $got = Get-Bytes (Get-HookPath $d $slot)
      (Test-SameBytes $got (Get-Wanted $script:Tpl $slot)) | Should -BeTrue
      ($got -contains 13) | Should -BeFalse
      $got[$got.Length - 1] | Should -Be 10
    }
  }

  It 'writes hooks byte-identical to those the sh installer writes into a twin repository under bash' {
    $a = New-Repo 'twin-ps1'
    $b = New-Repo 'twin-sh'
    Copy-Installers $a
    Copy-Installers $b
    (Invoke-Ps1 $a).ExitCode | Should -Be 0
    (Invoke-Sh $b).ExitCode | Should -Be 0
    foreach ($slot in $script:Slots) {
      (Test-SameBytes (Get-Bytes (Get-HookPath $a $slot)) (Get-Bytes (Get-HookPath $b $slot))) | Should -BeTrue
    }
  }

  It 'refuses by name when a template is missing and writes no hook' {
    $d = New-Repo 'missing'
    Copy-Installers $d
    $gone = Join-Path (Join-Path (Join-Path (Join-Path $d '.aai') 'templates') 'git-hooks') 'pre-push.sh'
    Remove-Item -LiteralPath $gone
    $r = Invoke-Ps1 $d
    $r.ExitCode | Should -Be 1
    $r.Stderr | Should -BeLike ('*ERROR: AAI hook template missing: ' + $gone + '*')
    foreach ($slot in $script:Slots) {
      Test-Path -LiteralPath (Get-HookPath $d $slot) | Should -BeFalse
    }
  }

  It 'writes CR-free hooks equal to the LF result when the templates hold CRLF' {
    $d = New-Repo 'crlf'
    Copy-Installers $d
    $tdir = Join-Path (Join-Path (Join-Path $d '.aai') 'templates') 'git-hooks'
    foreach ($f in (Get-ChildItem -LiteralPath $tdir -File)) {
      $lf = Get-TemplateBytes $tdir $f.Name
      $text = [Text.Encoding]::ASCII.GetString($lf).Replace("`n", "`r`n")
      [IO.File]::WriteAllBytes($f.FullName, [Text.Encoding]::ASCII.GetBytes($text))
    }
    $r = Invoke-Ps1 $d
    $r.ExitCode | Should -Be 0
    foreach ($slot in $script:Slots) {
      $got = Get-Bytes (Get-HookPath $d $slot)
      ($got -contains 13) | Should -BeFalse
      (Test-SameBytes $got (Get-Wanted $script:Tpl $slot)) | Should -BeTrue
    }
  }

  It 'inserts the guard block into a pre-guard AAI pre-commit hook and keeps every other byte' {
    $d = New-Repo 'upgrade'
    Copy-Installers $d
    $idx = Get-TemplateBytes $script:Tpl 'pre-commit-index.sh'
    $nl = [Array]::IndexOf($idx, [byte]10)
    $old = [byte[]]($idx[0..$nl] + $idx[($nl + 1)..($idx.Length - 1)])
    New-Item -ItemType Directory -Force -Path (Join-Path (Join-Path $d '.git') 'hooks') | Out-Null
    [IO.File]::WriteAllBytes((Get-HookPath $d 'pre-commit'), $old)
    $r = Invoke-Ps1 $d '-Hooks index'
    $r.ExitCode | Should -Be 0
    $r.Stdout | Should -BeLike '*Upgraded AAI pre-commit hook*'
    (Test-SameBytes (Get-Bytes (Get-HookPath $d 'pre-commit')) (Get-Composed $script:Tpl)) | Should -BeTrue
  }

  It 'changes no byte on a plain re-run and says every hook is already installed' {
    $d = New-Repo 'rerun'
    Copy-Installers $d
    (Invoke-Ps1 $d).ExitCode | Should -Be 0
    $before = @{}
    foreach ($slot in $script:Slots) { $before[$slot] = Get-Bytes (Get-HookPath $d $slot) }
    $r = Invoke-Ps1 $d
    $r.ExitCode | Should -Be 0
    foreach ($slot in $script:Slots) {
      (Test-SameBytes (Get-Bytes (Get-HookPath $d $slot)) $before[$slot]) | Should -BeTrue
    }
    $r.Stdout | Should -BeLike '*AAI pre-commit hook already installed*'
    $r.Stdout | Should -BeLike '*AAI reference-transaction hook already installed*'
    $r.Stdout | Should -BeLike '*AAI pre-push hook already installed*'
  }

  It 'still uninstalls its hooks when the templates are gone' {
    $d = New-Repo 'uninstall'
    Copy-Installers $d
    (Invoke-Ps1 $d).ExitCode | Should -Be 0
    Remove-Item -LiteralPath (Join-Path (Join-Path (Join-Path $d '.aai') 'templates') 'git-hooks') -Recurse -Force
    $r = Invoke-Ps1 $d '-Uninstall'
    $r.ExitCode | Should -Be 0
    foreach ($slot in $script:Slots) {
      Test-Path -LiteralPath (Get-HookPath $d $slot) | Should -BeFalse
    }
  }
}
