# Real linked-worktree fixture; runs under Windows PowerShell 5.1 and pwsh 7.
Describe 'worktree seed PowerShell parity' {
  BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:Scratch = Join-Path ([IO.Path]::GetTempPath()) ('aai seed ps ' + [guid]::NewGuid().ToString('N'))
    $script:Source = Join-Path $Scratch 'installed source'
    $script:Target = Join-Path $Scratch 'linked target'
    $script:Unavailable = Join-Path $Scratch 'temporarily unavailable'
    $script:UnavailableMoved = Join-Path $Scratch 'temporarily unavailable.moved'
    $script:Seeder = Join-Path $Root '.aai/scripts/worktree-seed.mjs'
    New-Item -ItemType Directory -Force -Path $Source | Out-Null
    function Assert-Native { param([string]$Exe, [string[]]$NativeArgs)
      & $Exe @NativeArgs
      if ($LASTEXITCODE -ne 0) { throw "$Exe failed ($LASTEXITCODE): $($NativeArgs -join ' ')" }
    }
    Assert-Native git @('-C', $Source, 'init', '-q', '-b', 'main')
    Assert-Native git @('-C', $Source, 'config', 'user.name', 'AAI Fixture')
    Assert-Native git @('-C', $Source, 'config', 'user.email', 'fixture@example.invalid')
    [IO.File]::WriteAllText((Join-Path $Source 'README.md'), 'seed fixture')
    & (Join-Path $Root '.aai/scripts/aai-sync.ps1') -TargetRoot $Source -Profile core
    Assert-Native git @('-C', $Source, 'add', 'README.md', '.gitignore')
    Assert-Native git @('-C', $Source, 'commit', '-qm', 'project baseline')
    Assert-Native git @('-C', $Source, 'worktree', 'add', '-q', '-b', 'feature', $Target, 'main')
    $prompt = [IO.File]::ReadAllText((Join-Path $Root '.aai/SKILL_WORKTREE.prompt.md'))
    $match = [regex]::Match($prompt, '(?s)# AAI_WORKTREE_PS_SEED_GATE_BEGIN\r?\n(.*?)\s*# AAI_WORKTREE_PS_SEED_GATE_END')
    if (-not $match.Success) { throw 'PowerShell setup gate missing from prompt' }
    $script:Gate = [scriptblock]::Create($match.Groups[1].Value + "`nNew-Item -ItemType File -Path (Join-Path `$AaiTargetRoot 'setup-success') | Out-Null")
  }
  AfterAll {
    if (Test-Path -LiteralPath $UnavailableMoved) { Move-Item -LiteralPath $UnavailableMoved -Destination $Unavailable }
    if (Test-Path -LiteralPath $Unavailable) { & git -C $Source worktree remove --force $Unavailable | Out-Null }
    if (Test-Path -LiteralPath $Target) { & git -C $Source worktree remove --force $Target | Out-Null }
    if (Test-Path -LiteralPath $Scratch) { Remove-Item -LiteralPath $Scratch -Recurse -Force }
  }

  It 'TEST-008 stops before initialization or success after seed refusal' {
    New-Item -ItemType Directory -Force -Path (Join-Path $Target '.aai/AGENTS.md') | Out-Null
    $AaiSourceRoot = $Source
    $AaiTargetRoot = $Target
    try {
      { & $Gate } | Should -Throw '*installed AAI seed failed*'
      (Test-Path -LiteralPath (Join-Path $Target 'docs/ai/STATE.yaml')) | Should -BeFalse
      (Test-Path -LiteralPath (Join-Path $Target 'setup-success')) | Should -BeFalse
    } finally { Remove-Item -LiteralPath (Join-Path $Target '.aai') -Recurse -Force }
  }

  It 'TEST-008 seeds spaced paths, runs initializer, and creates no links' {
    (Test-Path -LiteralPath (Join-Path $Target '.aai/scripts/check-state.mjs')) | Should -BeFalse
    $skillRoots = @('.agents/skills', '.claude/skills', '.codex/skills', '.gemini/skills')
    for ($index = 0; $index -lt $skillRoots.Count; $index++) {
      $skill = Join-Path $Source ($skillRoots[$index] + '/metadata-' + ($index + 1))
      New-Item -ItemType Directory -Force -Path $skill | Out-Null
      [IO.File]::WriteAllText((Join-Path $skill 'SKILL.md'), "ordinary skill payload $($index + 1)")
      if ($index % 2 -eq 0) {
        New-Item -ItemType Directory -Force -Path (Join-Path $skill '.git') | Out-Null
        [IO.File]::WriteAllText((Join-Path $skill '.git/config'), 'nested git metadata')
      } else {
        [IO.File]::WriteAllText((Join-Path $skill '.git'), "gitdir: $Source/.git/worktrees/foreign-$index")
      }
    }
    Assert-Native git @('-C', $Source, 'worktree', 'add', '-q', '-b', 'unavailable-sibling', $Unavailable, 'main')
    Move-Item -LiteralPath $Unavailable -Destination $UnavailableMoved
    $AaiSourceRoot = $Source
    $AaiTargetRoot = $Target
    Push-Location -LiteralPath $Source
    try { & $Gate } finally {
      Pop-Location
      Move-Item -LiteralPath $UnavailableMoved -Destination $Unavailable
    }
    (Test-Path -LiteralPath (Join-Path $Target 'setup-success')) | Should -BeTrue
    for ($index = 0; $index -lt $skillRoots.Count; $index++) {
      $targetSkill = Join-Path $Target ($skillRoots[$index] + '/metadata-' + ($index + 1))
      (Test-Path -LiteralPath (Join-Path $targetSkill 'SKILL.md')) | Should -BeTrue
      (Test-Path -LiteralPath (Join-Path $targetSkill '.git')) | Should -BeFalse
    }
    $sourcePin = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Source '.aai/system/AAI_PIN.md')).Hash
    $targetPin = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Target '.aai/system/AAI_PIN.md')).Hash
    $targetPin | Should -Be $sourcePin
    Push-Location -LiteralPath $Target
    try {
      & node '.aai/scripts/check-state.mjs' --repair
      $LASTEXITCODE | Should -Be 0
      & node '.aai/scripts/check-state.mjs'
      $LASTEXITCODE | Should -Be 0
    } finally { Pop-Location }
    $links = @(Get-ChildItem -LiteralPath (Join-Path $Target '.aai') -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
    $links.Count | Should -Be 0
  }

  It 'TEST-008 refuses a conflict and does not alter existing installed bytes' {
    $pin = Join-Path $Target '.aai/system/AAI_PIN.md'
    $before = (Get-FileHash -Algorithm SHA256 -LiteralPath $pin).Hash
    Add-Content -LiteralPath (Join-Path $Source '.aai/system/AAI_PIN.md') -Value 'origin update'
    & node $Seeder --source $Source --target $Target
    $LASTEXITCODE | Should -Not -Be 0
    (Get-FileHash -Algorithm SHA256 -LiteralPath $pin).Hash | Should -Be $before
  }
}
