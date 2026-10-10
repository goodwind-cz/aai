# /aai-merge PowerShell parity (spec-directed-merge-and-post-merge-cleanup, TEST-016).
# Runs the prompt's own AAI_MERGE_PS block against a real downstream-shaped
# fixture on a spaced path; runs under Windows PowerShell 5.1 and pwsh 7.
# gh is a deny-by-default node stub reached through AAI_MERGE_CLEANUP_GH_NODE
# (a native Windows runner cannot spawn a .cmd/.sh stub without a shell).
Describe 'merge cleanup PowerShell parity' {
  BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:Scratch = Join-Path ([IO.Path]::GetTempPath()) ('aai merge ps ' + [guid]::NewGuid().ToString('N'))
    $script:Utf8 = New-Object System.Text.UTF8Encoding $false
    $script:Pr = 433
    $script:Branch = 'ride/foo'
    $script:Saved = @{}
    foreach ($name in 'GIT_AUTHOR_NAME', 'GIT_AUTHOR_EMAIL', 'GIT_COMMITTER_NAME', 'GIT_COMMITTER_EMAIL', 'AAI_MERGE_CLEANUP_GH_NODE', 'GH_STUB_DIR', 'AAI_PR', 'AAI_GIT_WRITE') {
      $script:Saved[$name] = [Environment]::GetEnvironmentVariable($name)
    }
    $env:GIT_AUTHOR_NAME = 'AAI Fixture'; $env:GIT_COMMITTER_NAME = 'AAI Fixture'
    $env:GIT_AUTHOR_EMAIL = 'fixture@example.invalid'; $env:GIT_COMMITTER_EMAIL = 'fixture@example.invalid'

    function Assert-Native { param([string]$Exe, [string[]]$NativeArgs)
      & $Exe @NativeArgs
      if ($LASTEXITCODE -ne 0) { throw "$Exe failed ($LASTEXITCODE): $($NativeArgs -join ' ')" }
    }
    function Write-Text { param([string]$Path, [string]$Text)
      $dir = Split-Path -Parent $Path
      if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
      [IO.File]::WriteAllText($Path, $Text, $script:Utf8)
    }
    function Set-RepoIdentity { param([string]$Dir)
      Assert-Native git @('-C', $Dir, 'config', 'user.name', 'AAI Fixture')
      Assert-Native git @('-C', $Dir, 'config', 'user.email', 'fixture@example.invalid')
      Assert-Native git @('-C', $Dir, 'config', 'core.autocrlf', 'false')
    }

    $script:Bare = Join-Path $Scratch 'origin.git'
    $script:Origin = Join-Path $Scratch 'installed origin'
    $script:Ride = Join-Path $Scratch 'linked ride'
    $script:Ghd = Join-Path $Scratch 'gh stub'
    New-Item -ItemType Directory -Force -Path $Ghd | Out-Null
    $script:Engine = Join-Path $Origin '.aai/scripts/merge-cleanup.mjs'

    $issueDraft = "---`nid: foo`ntype: issue`nnumber: null`nstatus: draft`nlinks:`n  pr: []`n  commits: []`n---`n`n# Issue foo`n`nDraft body.`n"
    $specDraft = "---`nid: spec-foo`ntype: spec`nnumber: null`nstatus: implementing`nlinks:`n  requirement: foo`n  pr: []`n  commits: []`n---`n`n# Spec foo`n`nDraft spec body.`n"
    $issueNum = "---`nid: foo`ntype: issue`nnumber: 1`nstatus: done`nlinks:`n  pr:`n    - $Pr`n  commits: []`n---`n`n# Issue foo`n`nDraft body.`n`nDelivered.`n"
    $specNum = "---`nid: spec-foo`ntype: spec`nnumber: 1`nstatus: done`nlinks:`n  requirement: foo`n  pr:`n    - $Pr`n  commits: []`n---`n`n# Spec foo`n`nDraft spec body.`n`nDelivered.`n`n## Acceptance Criteria Status`n`n| Spec-AC | Description | Status | Evidence | Review-By | Notes |`n|---|---|---|---|---|---|`n| Spec-AC-01 | The fixture spec is delivered. | done | docs/ai/tdd/foo-green.log | tdd | fixture |`n"

    Assert-Native git @('init', '-q', '--bare', '-b', 'main', $Bare)
    Assert-Native git @('-C', $Bare, 'symbolic-ref', 'HEAD', 'refs/heads/main')
    Assert-Native git @('init', '-q', '-b', 'main', $Origin)
    Set-RepoIdentity $Origin
    Assert-Native git @('-C', $Origin, 'remote', 'add', 'origin', $Bare)
    Write-Text (Join-Path $Origin 'README.md') "fixture`n"
    Write-Text (Join-Path $Origin '.gitignore') "docs/ai/archive/**`ndocs/ai/reports/**`ndocs/ai/tdd/**`ndocs/ai/validation/**`ndocs/ai/reviews/**`ndocs/ai/evidence/**`ndocs/ai/STATE.yaml`n"
    Write-Text (Join-Path $Origin 'docs/ai/EVENTS.jsonl') "{`"v`":1,`"ts`":`"2026-10-09T00:00:00Z`",`"actor`":`"fixture`",`"event`":`"seed`",`"ref`":`"seed`",`"payload`":{}}`n"
    Write-Text (Join-Path $Origin 'docs/INDEX.md') "# Docs Index $([char]0x2014) auto-generated, DO NOT EDIT`n"
    & (Join-Path $Root '.aai/scripts/aai-sync.ps1') -TargetRoot $Origin -Profile core *> $null
    Assert-Native git @('-C', $Origin, 'add', '-A')
    Assert-Native git @('-C', $Origin, 'commit', '-qm', 'baseline and installed layer')
    Assert-Native git @('-C', $Origin, 'push', '-q', 'origin', 'main')
    Assert-Native git @('-C', $Origin, 'fetch', '-q', 'origin')
    Write-Text (Join-Path $Origin 'docs/issues/ISSUE-DRAFT-foo.md') $issueDraft
    Write-Text (Join-Path $Origin 'docs/specs/SPEC-DRAFT-spec-foo.md') $specDraft

    Assert-Native git @('-C', $Origin, 'worktree', 'add', '-q', '-b', $Branch, $Ride, 'main')
    Set-RepoIdentity $Ride
    Assert-Native node @((Join-Path $Origin '.aai/scripts/worktree-seed.mjs'), '--source', $Origin, '--target', $Ride)
    Write-Text (Join-Path $Ride 'docs/issues/ISSUE-DRAFT-foo.md') $issueDraft
    Write-Text (Join-Path $Ride 'docs/specs/SPEC-DRAFT-spec-foo.md') $specDraft
    Assert-Native git @('-C', $Ride, 'add', 'docs/issues/ISSUE-DRAFT-foo.md', 'docs/specs/SPEC-DRAFT-spec-foo.md')
    Assert-Native git @('-C', $Ride, 'commit', '-qm', 'docs: drafts')
    Assert-Native git @('-C', $Ride, 'mv', 'docs/issues/ISSUE-DRAFT-foo.md', 'docs/issues/ISSUE-0001-foo.md')
    Assert-Native git @('-C', $Ride, 'mv', 'docs/specs/SPEC-DRAFT-spec-foo.md', 'docs/specs/SPEC-0001-spec-foo.md')
    Write-Text (Join-Path $Ride 'docs/issues/ISSUE-0001-foo.md') $issueNum
    Write-Text (Join-Path $Ride 'docs/specs/SPEC-0001-spec-foo.md') $specNum
    $events = [IO.File]::ReadAllText((Join-Path $Ride 'docs/ai/EVENTS.jsonl'))
    foreach ($ref in 'foo', 'spec-foo') {
      $events += "{`"v`":1,`"ts`":`"2026-10-10T00:00:00Z`",`"actor`":`"fixture`",`"event`":`"work_item_closed`",`"ref`":`"$ref`",`"payload`":{`"validation`":`"pass`",`"code_review`":`"pass`"}}`n"
    }
    Write-Text (Join-Path $Ride 'docs/ai/EVENTS.jsonl') $events
    Write-Text (Join-Path $Ride 'README.md') "fixture`ndelivered by the ride`n"
    Assert-Native git @('-C', $Ride, 'add', 'docs/issues/ISSUE-0001-foo.md', 'docs/specs/SPEC-0001-spec-foo.md', 'docs/ai/EVENTS.jsonl', 'README.md')
    Assert-Native git @('-C', $Ride, 'commit', '-qm', 'docs: number and close')
    Assert-Native git @('-C', $Ride, 'push', '-q', 'origin', $Branch)
    Assert-Native git @('-C', $Ride, 'push', '-q', 'origin', "HEAD:refs/pull/$Pr/head")
    $script:HeadOid = (& git -C $Ride rev-parse HEAD).Trim()
    $tree = (& git -C $Ride rev-parse 'HEAD^{tree}').Trim()
    $main0 = (& git -C $Bare rev-parse refs/heads/main).Trim()
    $script:Mc = (& git -C $Bare commit-tree $tree -p $main0 -m "foo (#$Pr)").Trim()
    Assert-Native git @('-C', $Bare, 'update-ref', 'refs/heads/main', $Mc)

    $prJson = "{`"number`":$Pr,`"state`":`"MERGED`",`"isDraft`":false,`"headRefOid`":`"$HeadOid`",`"headRefName`":`"$Branch`",`"baseRefName`":`"main`",`"mergeStateStatus`":`"UNKNOWN`",`"statusCheckRollup`":[],`"mergeCommit`":{`"oid`":`"$Mc`"},`"url`":`"https://github.com/example/repo/pull/$Pr`"}`n"
    Write-Text (Join-Path $Ghd "pr-$Pr.json") $prJson
    $script:GhStub = Join-Path $Ghd 'gh-stub.js'
    Write-Text $GhStub @'
const fs = require('fs'), path = require('path');
const dir = process.env.GH_STUB_DIR;
if (!dir) { console.error('STUB-DENY: GH_STUB_DIR unset'); process.exit(1); }
const a = process.argv.slice(2);
fs.appendFileSync(path.join(dir, 'gh-argv.log'), a.join(' ') + '\n');
const fields = 'number,state,isDraft,headRefOid,headRefName,baseRefName,mergeStateStatus,statusCheckRollup,mergeCommit,url';
if (a.length === 5 && a[0] === 'pr' && a[1] === 'view' && /^[0-9]+$/.test(a[2]) && a[3] === '--json' && a[4] === fields) {
  const p = path.join(dir, 'pr-' + a[2] + '.json');
  if (fs.existsSync(p)) { process.stdout.write(fs.readFileSync(p)); process.exit(0); }
}
console.error('STUB-DENY: unexpected argv: ' + a.join(' '));
process.exit(1);
'@
    $env:AAI_MERGE_CLEANUP_GH_NODE = $GhStub
    $env:GH_STUB_DIR = $Ghd
    $env:AAI_PR = "$Pr"

    $prompt = [IO.File]::ReadAllText((Join-Path $Root '.aai/SKILL_MERGE.prompt.md'))
    $match = [regex]::Match($prompt, '(?s)# AAI_MERGE_PS_BEGIN\r?\n(.*?)\s*# AAI_MERGE_PS_END')
    if (-not $match.Success) { throw 'PowerShell merge block missing from prompt' }
    $script:Block = [scriptblock]::Create($match.Groups[1].Value)
  }
  AfterAll {
    foreach ($name in $script:Saved.Keys) { [Environment]::SetEnvironmentVariable($name, $script:Saved[$name]) }
    if (Test-Path -LiteralPath $Ride) { & git -C $Origin worktree remove --force $Ride | Out-Null }
    if (Test-Path -LiteralPath $Scratch) { Remove-Item -LiteralPath $Scratch -Recurse -Force }
  }

  It 'TEST-016 refuses a dirty worktree and removes nothing' {
    [IO.File]::AppendAllText((Join-Path $Ride 'README.md'), "edit`n", $Utf8)
    Push-Location -LiteralPath $Ride
    $lines = New-Object System.Collections.ArrayList
    $failure = ''
    try {
      try { & $Block | ForEach-Object { [void]$lines.Add("$_") } } catch { $failure = $_.Exception.Message }
    } finally { Pop-Location }
    $failure | Should -BeLike '*exited 3*'
    ($lines -join "`n") | Should -BeLike '*REFUSE worktree_dirty*'
    (Test-Path -LiteralPath $Ride) | Should -BeTrue
    (& git -C $Origin show-ref --verify "refs/heads/$Branch") | Should -Not -BeNullOrEmpty
    (Test-Path -LiteralPath (Join-Path $Origin 'docs/issues/ISSUE-DRAFT-foo.md')) | Should -BeTrue
  }

  It 'TEST-016 cleans up the merged ride from inside the worktree on a spaced path' {
    $committed = (& git -C $Ride show 'HEAD:README.md')
    [IO.File]::WriteAllText((Join-Path $Ride 'README.md'), (($committed -join "`n") + "`n"), $Utf8)
    Push-Location -LiteralPath $Ride
    $lines = New-Object System.Collections.ArrayList
    try {
      try { & $Block | ForEach-Object { [void]$lines.Add("$_") } } catch { throw "$($_.Exception.Message)`n$($lines -join "`n")" }
    } finally { Pop-Location }
    (Test-Path -LiteralPath $Ride) | Should -BeFalse
    & git -C $Origin show-ref --verify -q "refs/heads/$Branch" 2>$null
    $LASTEXITCODE | Should -Not -Be 0
    (Test-Path -LiteralPath (Join-Path $Origin 'docs/issues/ISSUE-0001-foo.md')) | Should -BeTrue
    (Test-Path -LiteralPath (Join-Path $Origin 'docs/specs/SPEC-0001-spec-foo.md')) | Should -BeTrue
    (Test-Path -LiteralPath (Join-Path $Origin 'docs/issues/ISSUE-DRAFT-foo.md')) | Should -BeFalse
    (Test-Path -LiteralPath (Join-Path $Origin 'docs/specs/SPEC-DRAFT-spec-foo.md')) | Should -BeFalse
    (Get-Content -LiteralPath (Join-Path $Origin "docs/ai/archive/merge-cleanup/pr-$Pr/manifest.jsonl")).Count | Should -Be 2
    (& git -C $Origin rev-parse HEAD).Trim() | Should -Be $Mc
    $log = [IO.File]::ReadAllText((Join-Path $Ghd 'gh-argv.log'))
    $log | Should -Match "pr view $Pr --json"
    $log | Should -Not -Match 'pr merge'
  }
}
