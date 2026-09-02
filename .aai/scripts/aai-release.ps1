#!/usr/bin/env pwsh
# AAI release-cut engine - PowerShell parity twin of aai-release.sh for /aai-release.
#
# Rolls the repo root's CHANGELOG.md `[unreleased]` blocks into a versioned
# section, commits, creates an annotated tag, publishes a GitHub release with
# notes derived from that section, and pushes - behind an operator gate with
# a safe default (plan-only) mode. Same flags/behavior/exit codes as the bash
# twin; its only inputs are the repo root, its CHANGELOG.md, and its git/gh
# remote, so it runs identically in any deployed target project.
#
# Usage (run from anywhere inside the target repo):
#   ./.aai/scripts/aai-release.ps1                          # plan-only (default-safe), no writes
#   ./.aai/scripts/aai-release.ps1 -DryRun                  # same as bare invocation, explicit
#   ./.aai/scripts/aai-release.ps1 -Version v1.2.3          # verbatim version (any scheme)
#   ./.aai/scripts/aai-release.ps1 -Confirm                 # CUT: roll+commit+tag(+push+publish)
#   ./.aai/scripts/aai-release.ps1 -Confirm -NoRemote        # CUT, skip push + gh release create
#   $env:AAI_RELEASE_DATE="2026-07-20"; ./.aai/scripts/aai-release.ps1 -DryRun
#   $env:AAI_RELEASE_NO_REMOTE="1"; ./.aai/scripts/aai-release.ps1 -Confirm
#
# The /aai-release skill forwards the user's flags verbatim in bash long-flag
# form (--dry-run, --version, --confirm/--yes, --no-remote); those are also
# accepted here via -ExtraArgs so this entrypoint behaves like the bash twin.
#
# Exit codes: 0 success (plan or cut) | 1 bad argument | 10 not a git repo |
#   11 no CHANGELOG.md | 12 malformed [unreleased] region | 13 no rollable
#   [unreleased] entries (absent/empty) | 14 dirty working tree (cut path) |
#   15 tag already exists (cut path) | 16 gh absent/unauthenticated (publish
#   path only; dry-run works offline) | 17 target branch is protected: fell
#   back to a release branch + PR, release NOT published | 18 protected-branch
#   fallback engaged but INCOMPLETE (see the report's manual commands).
param(
  [string]$Version = "",
  [switch]$DryRun,
  [switch]$Confirm,
  [switch]$Yes,
  [switch]$NoRemote,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$ExtraArgs
)

function Invoke-NativeChecked {
  # Diagnostics-preserving checked-invoke (ps1-native-stderr-guard /
  # SPEC-0067-spec-ps1-native-stderr-guard, Spec-AC-01). A native command's
  # SUCCESS-stderr (e.g. `git push`'s "To <remote>..." progress line) must
  # NEVER be promoted to a terminating error under this script's outer
  # `$ErrorActionPreference = 'Stop'` (that promotion is Windows PowerShell
  # 5.1 behavior; see the issue). Gates SOLELY on the child's real exit code:
  # zero -> return the captured output, never throw, regardless of stderr
  # content; non-zero -> throw a terminating error whose message INCLUDES the
  # captured text, so a real failure (rejected push, auth, network) still
  # fails loudly with git/gh's own diagnostic - never a blanket `*> $null`
  # that would hide it.
  #
  # CHANGE-0134 remediation (RR-1 realized -- first real Windows PowerShell 5.1 run,
  # PR #248 run 31638479811, TEST-002): a LOCAL `$ErrorActionPreference =
  # 'Continue'` reassignment around an in-process `2>&1` merge does NOT
  # reliably suppress the 5.1 stderr-promotion described above -- proven
  # false on real hardware, exactly the residual risk SPEC-0067 recorded as
  # unverified (pwsh 7 does not reproduce the promotion at all, so this was
  # never provable off-host). Capturing at the OS-handle level via
  # Start-Process -RedirectStandardOutput/-RedirectStandardError sidesteps
  # PowerShell's error-stream/EAP machinery entirely -- the same technique
  # aai-run-tests.ps1's Start-WslProbeProcess/Start-GitBashProcess already
  # use for the sibling 5.1 ExitCode-null footgun. Arguments are individually
  # quoted into ONE -ArgumentList string first: Start-Process -ArgumentList
  # silently mis-splits an ARRAY whose elements contain embedded spaces (each
  # element is naively space-joined, not quoted) -- proven while building
  # this fix, and would otherwise tear a commit message or `-m` value into
  # multiple argv entries.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Exe,
    [Parameter(Mandatory)][string[]]$Arguments
  )
  $outFile = [System.IO.Path]::GetTempFileName()
  $errFile = [System.IO.Path]::GetTempFileName()
  try {
    $argString = ($Arguments | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' '
    $proc = Start-Process -FilePath $Exe -ArgumentList $argString -NoNewWindow -PassThru -Wait `
      -RedirectStandardOutput $outFile -RedirectStandardError $errFile -ErrorAction Stop
    # 5.1 ExitCode-null footgun: touch .Handle so a real exit code is
    # readable on every PowerShell version, even though -Wait already
    # blocked until the process exited.
    $null = $proc.Handle
    $exitCode = $proc.ExitCode
    $stdout = @(Get-Content -LiteralPath $outFile -ErrorAction SilentlyContinue)
    $stderr = @(Get-Content -LiteralPath $errFile -ErrorAction SilentlyContinue)
    $out = @($stdout + $stderr) | Where-Object { $null -ne $_ }
  } finally {
    Remove-Item -LiteralPath $outFile, $errFile -ErrorAction SilentlyContinue
  }
  if ($exitCode -ne 0) {
    $joined = ($out | ForEach-Object { "$_" }) -join [Environment]::NewLine
    throw "$Exe $($Arguments -join ' ') failed (exit ${exitCode}): $joined"
  }
  return ,$out
}

function Test-ProtectedBranchRejection {
  # D1 classifier, parity twin of aai-release.sh's is_protected_branch_rejection:
  # is this captured `git push` output a protected-branch / required-status-
  # checks rejection? GitHub's own `GH006` token, or the host-agnostic wording
  # pair, both case-insensitively. Deliberately narrow -- every OTHER failure
  # class (auth, network, non-fast-forward) must keep today's raw behavior, so
  # a miss degrades to "re-emit and exit with git's code", never to a wrong
  # recovery (Constitution article 4).
  #
  # Defined ABOVE the dot-source guard on purpose: dot-sourcing this file must
  # define the classifier WITHOUT parsing args or cutting a release, so
  # tests/skills/aai-release.Tests.ps1 can unit-test it (same seam as
  # Invoke-NativeChecked, ps1-native-stderr-guard Spec-AC-03).
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][AllowEmptyString()][string]$Text
  )
  if ([string]::IsNullOrEmpty($Text)) { return $false }
  $t = $Text.ToLowerInvariant()
  if ($t.Contains('gh006')) { return $true }
  if ($t.Contains('protected branch') -and $t.Contains('status check')) { return $true }
  return $false
}

if ($MyInvocation.InvocationName -ne '.') {

$extra = @(); if ($ExtraArgs) { $extra = @($ExtraArgs) }
for ($i = 0; $i -lt $extra.Count; $i++) {
  switch -Regex ($extra[$i]) {
    '^--dry-run$'     { $DryRun = $true }
    '^--confirm$'     { $Confirm = $true }
    '^--yes$'         { $Yes = $true }
    '^--no-remote$'   { $NoRemote = $true }
    '^--version=(.+)$' { $Version = $Matches[1] }
    '^--version$'     { $i++; if ($i -lt $extra.Count) { $Version = $extra[$i] } }
    default { [Console]::Error.WriteLine("Unknown argument: $($extra[$i])"); exit 1 }
  }
}
if ($Yes) { $Confirm = $true }
if ($env:AAI_RELEASE_NO_REMOTE -eq "1") { $NoRemote = $true }

$ErrorActionPreference = "Stop"

# D4: -DryRun always wins over -Confirm (safe by construction).
if ($DryRun) { $Confirm = $false }

$OutFile = $null
$NotesFile = $null
try {
  # --- D6 ALWAYS-checked preconditions (a)/(b): not a git repo / no CHANGELOG
  $Root = (git rev-parse --show-toplevel 2>$null)
  if (-not $Root -or $LASTEXITCODE -ne 0) {
    [Console]::Error.WriteLine("REFUSED: not a git repository (cwd=$(Get-Location)).")
    exit 10
  }
  $Changelog = Join-Path $Root "CHANGELOG.md"
  if (-not (Test-Path $Changelog)) {
    [Console]::Error.WriteLine("REFUSED: no CHANGELOG.md at repo root: $Changelog")
    exit 11
  }

  # Snapshot the dirty-tree state NOW, before any temp file is created under
  # $Root below (a later check would see our own scratch file as "dirty").
  $dirtyOut = (git -C $Root status --porcelain 2>$null)
  $Dirty = [bool]($dirtyOut -and $dirtyOut.Trim().Length -gt 0)

  # --- D3: version resolution (verbatim else CalVer, clock-controllable) ---
  if (-not $Version) {
    $releaseDate = $env:AAI_RELEASE_DATE
    if ($releaseDate) {
      $Version = "v" + ($releaseDate -replace '-', '.')
    } else {
      $Version = "v" + (Get-Date -AsUTC -Format "yyyy.MM.dd")
    }
  }

  # --- D1: CHANGELOG rollup transform (line-surgical, byte-preserved) -----
  $lines = Get-Content -LiteralPath $Changelog
  $n = $lines.Count
  $firstHeading = -1
  for ($i = 0; $i -lt $n; $i++) {
    if ($lines[$i] -match '^## \[') { $firstHeading = $i; break }
  }
  if ($firstHeading -eq -1) {
    [Console]::Error.WriteLine("REFUSED: no rollable [unreleased] entries in CHANGELOG.md (absent or empty) - nothing to release.")
    exit 13
  }

  $headIdx = New-Object System.Collections.Generic.List[int]
  for ($i = $firstHeading; $i -lt $n; $i++) {
    if ($lines[$i] -match '^## ') { $headIdx.Add($i) }
  }
  $headIdx.Add($n)  # sentinel end

  $m = $headIdx.Count - 1
  $type = New-Object string[] $m
  $malformed = $false
  $entryCount = 0
  for ($k = 0; $k -lt $m; $k++) {
    $hi = $headIdx[$k]
    $hline = $lines[$hi]
    $bodyStart = $hi + 1
    $bodyEnd = $headIdx[$k + 1] - 1
    if ($hline -match ('^## \[unreleased\] ' + [char]0x2014 + ' ')) {
      $type[$k] = "ENTRY"; $entryCount++
    } elseif ($hline -match '^## \[unreleased\]') {
      if ($hline -match '^## \[unreleased\][ \t]*$') {
        $allBlank = $true
        for ($b = $bodyStart; $b -le $bodyEnd; $b++) {
          if ($lines[$b] -notmatch '^[ \t]*$') { $allBlank = $false; break }
        }
        if ($allBlank) { $type[$k] = "SCAFFOLD" } else { $type[$k] = "MALFORMED"; $malformed = $true }
      } else {
        $type[$k] = "MALFORMED"; $malformed = $true
      }
    } else {
      $type[$k] = "OTHER"
    }
  }

  if ($malformed) {
    [Console]::Error.WriteLine("REFUSED: malformed [unreleased] heading in CHANGELOG.md (a '## [unreleased]' line has unexpected trailing text or a stray heading-only body) - never silently dropping entries.")
    exit 12
  }
  if ($entryCount -eq 0) {
    [Console]::Error.WriteLine("REFUSED: no rollable [unreleased] entries in CHANGELOG.md (absent or empty) - nothing to release.")
    exit 13
  }

  $firstEntryHi = -1
  for ($k = 0; $k -lt $m; $k++) { if ($type[$k] -eq "ENTRY") { $firstEntryHi = $headIdx[$k]; break } }

  $newLines = New-Object System.Collections.Generic.List[string]
  for ($i = 0; $i -lt $firstHeading; $i++) { $newLines.Add($lines[$i]) }

  $notesLines = New-Object System.Collections.Generic.List[string]
  for ($k = 0; $k -lt $m; $k++) {
    $hi = $headIdx[$k]
    $bodyEnd = $headIdx[$k + 1] - 1
    if ($hi -eq $firstEntryHi) {
      $newLines.Add("## [unreleased]")
      $newLines.Add("")
    }
    if ($type[$k] -eq "ENTRY") {
      $line = $lines[$hi]
      $pos = $line.IndexOf("[unreleased]")
      $newline = $line.Substring(0, $pos) + "[" + $Version + "]" + $line.Substring($pos + "[unreleased]".Length)
      $newLines.Add($newline)
      $notesLines.Add($newline)
    } elseif ($type[$k] -eq "SCAFFOLD") {
      # Pre-existing bare scaffolds are CONSUMED, not copied (parity with the
      # bash engine): copying them through duplicated the bare heading inside
      # the versioned region on every cut.
      continue
    } else {
      $newLines.Add($lines[$hi])
    }
    for ($b = $hi + 1; $b -le $bodyEnd; $b++) {
      $newLines.Add($lines[$b])
      if ($type[$k] -eq "ENTRY") { $notesLines.Add($lines[$b]) }
    }
  }

  $s = 0; $e = $notesLines.Count - 1
  while ($s -le $e -and $notesLines[$s] -match '^[ \t]*$') { $s++ }
  while ($e -ge $s -and $notesLines[$e] -match '^[ \t]*$') { $e-- }
  $trimmedNotes = @()
  for ($i = $s; $i -le $e; $i++) { $trimmedNotes += $notesLines[$i] }

  $OutFile = Join-Path $Root (".aai-release-changelog." + [System.IO.Path]::GetRandomFileName())
  $NotesFile = Join-Path ([System.IO.Path]::GetTempPath()) ("aai-release-notes." + [System.IO.Path]::GetRandomFileName())
  # Preserve the original file's final-newline state (byte fidelity, D1 step 5).
  $origBytes = [System.IO.File]::ReadAllText($Changelog)
  $hadTrailingNewline = $origBytes.EndsWith("`n")
  $newContent = ($newLines -join "`n")
  if ($hadTrailingNewline) { $newContent += "`n" }
  [System.IO.File]::WriteAllText($OutFile, $newContent)
  [System.IO.File]::WriteAllText($NotesFile, ($trimmedNotes -join "`n"))

  # --- D6 CUT-path gates (d)/(e)/(f): dirty tree (snapshotted above) / existing tag / gh auth
  $tagExists = $false
  git -C $Root rev-parse -q --verify "refs/tags/$Version" *> $null
  if ($LASTEXITCODE -eq 0) { $tagExists = $true }

  $ghBlock = $false
  $ghReason = ""
  if (-not $NoRemote) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
      $ghBlock = $true; $ghReason = "gh CLI not found on PATH"
    } else {
      gh auth status *> $null
      if ($LASTEXITCODE -ne 0) { $ghBlock = $true; $ghReason = "gh CLI not authenticated (gh auth status failed)" }
    }
  }

  $branch = (git -C $Root rev-parse --abbrev-ref HEAD 2>$null)
  if (-not $branch) { $branch = "HEAD" }

  if (-not $Confirm) {
    Write-Host "## aai-release (plan) - no files changed"
    Write-Host "- Resolved version: $Version"
    Write-Host "- Tag to create:    $Version (annotated)"
    Write-Host "- Commit message:   chore(release): $Version"
    Write-Host ""
    Write-Host "## CHANGELOG rollup (would write)"
    Select-String -Path $OutFile -Pattern ("^## \[" + [regex]::Escape($Version) + "\] " + [char]0x2014 + " ") | ForEach-Object { Write-Host "  $($_.LineNumber):$($_.Line)" }
    Write-Host "  ## [unreleased]   <- fresh scaffold inserted above the rolled section"
    Write-Host ""
    Write-Host "## Release notes preview (title=$Version)"
    Get-Content $NotesFile | ForEach-Object { Write-Host "  $_" }
    Write-Host ""
    Write-Host "## Preconditions"
    $blocked = $false
    if ($Dirty) { Write-Host "- would block: working tree is dirty"; $blocked = $true }
    if ($tagExists) { Write-Host "- would block: tag $Version already exists"; $blocked = $true }
    if ($ghBlock) { Write-Host "- would block (publish path): $ghReason"; $blocked = $true }
    if (-not $blocked) { Write-Host "- none - ready to cut with -Confirm" }
    Write-Host ""
    Write-Host "## Remote"
    if ($NoRemote) {
      Write-Host "- -NoRemote / AAI_RELEASE_NO_REMOTE=1: push + gh release create would be SKIPPED"
    } else {
      Write-Host "- push ($branch + tag $Version) and 'gh release create' WOULD run against this repo's remote"
    }
    exit 0
  }

  # --- CONFIRM (the cut): fail-closed, zero writes on any refusal below ---
  if ($Dirty) {
    [Console]::Error.WriteLine("REFUSED: working tree is dirty - commit or stash before cutting a release.")
    exit 14
  }
  if ($tagExists) {
    [Console]::Error.WriteLine("REFUSED: tag $Version already exists.")
    exit 15
  }
  if ($ghBlock) {
    [Console]::Error.WriteLine("REFUSED: $ghReason (publish path) - dry-run works offline; pass -NoRemote/AAI_RELEASE_NO_REMOTE=1 to skip publish, or fix gh auth.")
    exit 16
  }

  # --- D7 cut sequence: rewrite -> add -> commit -> tag -> (push + publish)
  # D3 step 2 (bash parity): the target branch's pre-cut position, captured
  # BEFORE the release commit exists. The protected-branch fallback resets the
  # target branch back to exactly this SHA.
  $preCutSha = (Invoke-NativeChecked -Exe 'git' -Arguments @('-C', $Root, 'rev-parse', 'HEAD') | Select-Object -Last 1)

  Move-Item -Force -LiteralPath $OutFile -Destination $Changelog
  $OutFile = $null

  # AAI_VERSION.md parity with the bash engine: the version stamp aai-sync
  # reads to fill `Template version:` in a target's AAI_PIN.md.
  $versionDoc = @(
    '# AAI Version', '',
    "- Version: $Version", '',
    'Notes:',
    '- Written by the release engines (aai-release.sh / aai-release.ps1) at each cut;',
    '  consumed by `.aai/scripts/aai-sync.*` to stamp `Template version:` into the',
    '  target project''s `.aai/system/AAI_PIN.md`. Do not edit by hand.'
  )
  New-Item -ItemType Directory -Force -Path (Join-Path $Root 'docs/ai') | Out-Null
  Set-Content -LiteralPath (Join-Path $Root 'docs/ai/AAI_VERSION.md') -Value ($versionDoc -join "`n") -NoNewline:$false
  Invoke-NativeChecked -Exe 'git' -Arguments @('-C', $Root, 'add', '--', 'CHANGELOG.md', 'docs/ai/AAI_VERSION.md') | Out-Null
  Invoke-NativeChecked -Exe 'git' -Arguments @('-C', $Root, 'commit', '-q', '-m', "chore(release): $Version") | Out-Null
  Invoke-NativeChecked -Exe 'git' -Arguments @('-C', $Root, 'tag', '-a', $Version, '-m', $Version) | Out-Null

  $shortSha = (Invoke-NativeChecked -Exe 'git' -Arguments @('-C', $Root, 'rev-parse', '--short', 'HEAD') | Select-Object -Last 1)
  Write-Host "## aai-release - cut complete"
  Write-Host "- Version: $Version"
  Write-Host "- Commit:  $shortSha"
  Write-Host "- Tag:     $Version (annotated)"

  if (-not $NoRemote) {
    # D2 --no-follow-tags (bash parity): with `push.followTags=true` in the
    # repo or the operator's GLOBAL git config this branch push would carry
    # refs/tags/$Version with it, and GitHub's branch protection is per-ref and
    # NON-atomic -- so a GH006-rejected branch push still publishes the tag.
    # That is how v2026.09.01 (PR #329) left an orphaned tag behind. The tag
    # push stays strictly AFTER a successful branch push and never runs on the
    # fallback path.
    $pushError = ''
    try {
      Invoke-NativeChecked -Exe 'git' -Arguments @('-C', $Root, 'push', '--no-follow-tags', 'origin', $branch) | Out-Null
    } catch {
      # Invoke-NativeChecked folds the child's captured stdout+stderr into the
      # thrown message, so no diagnostic is lost by catching here.
      $pushError = "$($_.Exception.Message)"
    }

    if ($pushError) {
      [Console]::Error.WriteLine($pushError)
      if (-not (Test-ProtectedBranchRejection -Text $pushError)) {
        # Every other failure class keeps today's behavior: git's raw output
        # (already on stderr above) and git's own exit code.
        $rawExit = 1
        if ($pushError -match 'failed \(exit (\d+)\)') { $rawExit = [int]$Matches[1] }
        exit $rawExit
      }

      # --- D3 protected-branch fallback: release branch + PR, then STOP -----
      $releaseBranch = "chore/release-$Version"
      [Console]::Error.WriteLine("## aai-release - target branch '$branch' is PROTECTED (push rejected)")
      $releaseSha = (Invoke-NativeChecked -Exe 'git' -Arguments @('-C', $Root, 'rev-parse', 'HEAD') | Select-Object -Last 1)

      # D5 exit 18: the fallback engaged but could not finish -- name the exact
      # manual commands rather than leaving a half-cut release to reconstruct.
      $fallbackIncomplete = {
        param([string]$Reason)
        Write-Host "## aai-release - PROTECTED-BRANCH FALLBACK INCOMPLETE"
        Write-Host "- Reason:  $Reason"
        Write-Host "- Version: $Version (release commit exists LOCALLY, tag is LOCAL ONLY)"
        Write-Host "- Finish by hand:"
        Write-Host "    git branch $releaseBranch $releaseSha     # if that ref does not exist yet"
        Write-Host "    git reset --hard $preCutSha               # on $branch"
        Write-Host "    git push --no-follow-tags origin $releaseBranch"
        Write-Host "    gh pr create --base $branch --head $releaseBranch --title 'chore(release): $Version'"
        Write-Host "- The release is NOT published and no tag was pushed."
        exit 18
      }

      if ($branch -eq 'HEAD') {
        & $fallbackIncomplete "detached HEAD - there is no target branch for 'gh pr create --base', so the fallback refuses rather than opening a PR against a bogus base"
      }
      git -C $Root rev-parse -q --verify "refs/heads/$releaseBranch" *> $null
      if ($LASTEXITCODE -eq 0) {
        & $fallbackIncomplete "branch $releaseBranch already exists - never clobbering an existing ref"
      }

      Invoke-NativeChecked -Exe 'git' -Arguments @('-C', $Root, 'branch', $releaseBranch, $releaseSha) | Out-Null
      Invoke-NativeChecked -Exe 'git' -Arguments @('-C', $Root, 'reset', '-q', '--hard', $preCutSha) | Out-Null

      $branchPushError = ''
      try {
        Invoke-NativeChecked -Exe 'git' -Arguments @('-C', $Root, 'push', '--no-follow-tags', 'origin', $releaseBranch) | Out-Null
      } catch {
        $branchPushError = "$($_.Exception.Message)"
      }
      if ($branchPushError) {
        [Console]::Error.WriteLine($branchPushError)
        & $fallbackIncomplete "pushing $releaseBranch to origin failed (its output is on stderr above)"
      }

      $prBody = @(
        "Automated release cut for $Version.",
        '',
        "The target branch ``$branch`` is protected, so ``aai-release`` did not push to it",
        "directly. This PR carries the release commit; ``$branch`` was reset to",
        "$preCutSha and is unchanged.",
        '',
        "The release is NOT published and the annotated tag ``$Version`` exists only in",
        'the cutting operator''s local clone. After this PR merges, re-point and publish',
        'the tag against the merge commit (a squash merge produces a new SHA).',
        '',
        'Opened by .aai/scripts/aai-release.ps1 - it never merges this PR.'
      ) -join [Environment]::NewLine

      $prUrl = ''
      $prError = ''
      Push-Location $Root
      try {
        $prUrl = (Invoke-NativeChecked -Exe 'gh' -Arguments @('pr', 'create', '--base', $branch, '--head', $releaseBranch, '--title', "chore(release): $Version", '--body', $prBody) | Select-Object -Last 1)
      } catch {
        $prError = "$($_.Exception.Message)"
      } finally { Pop-Location }
      if ($prError) {
        [Console]::Error.WriteLine($prError)
        & $fallbackIncomplete "gh pr create failed (its output is on stderr above) - the release branch IS pushed, only the PR is missing"
      }

      # D8 report. D4: no `gh release create`, no `gh pr merge` - ever, on this
      # path (Constitution article 7). Pinned by TEST-033.
      Write-Host "## aai-release - PROTECTED BRANCH: fell back to a release PR"
      Write-Host "- PR:              $prUrl"
      Write-Host "- Release branch:  $releaseBranch (pushed, carries the release commit $releaseSha)"
      Write-Host "- Target branch:   $branch - reset to its pre-cut SHA $preCutSha (left clean)"
      Write-Host "- Release:         NOT PUBLISHED - CI must pass and the PR must be merged first."
      Write-Host "- Tag:             $Version is annotated LOCALLY ONLY and was NOT pushed."
      Write-Host "- After the PR merges, re-point the tag at the merge commit and publish:"
      Write-Host "    git checkout $branch && git pull"
      Write-Host "    git tag -d $Version"
      Write-Host "    git tag -a $Version -m $Version"
      Write-Host "    git push origin refs/tags/$Version"
      Write-Host "    gh release create $Version --title $Version --notes-file <the [$Version] CHANGELOG section>"
      exit 17
    }

    Invoke-NativeChecked -Exe 'git' -Arguments @('-C', $Root, 'push', 'origin', "refs/tags/$Version") | Out-Null
    Push-Location $Root
    try { Invoke-NativeChecked -Exe 'gh' -Arguments @('release', 'create', $Version, '--title', $Version, '--notes-file', $NotesFile) | Out-Null } finally { Pop-Location }
    Write-Host "- Pushed:  $branch + tag $Version"
    Write-Host "- Published: gh release create $Version"
  } else {
    Write-Host "- Remote:  SKIPPED (-NoRemote/AAI_RELEASE_NO_REMOTE=1) - would push $branch + tag $Version, then 'gh release create $Version'"
  }
} finally {
  if ($OutFile -and (Test-Path $OutFile)) { Remove-Item -Force $OutFile -ErrorAction SilentlyContinue }
  if ($NotesFile -and (Test-Path $NotesFile)) { Remove-Item -Force $NotesFile -ErrorAction SilentlyContinue }
}

}  # end: if ($MyInvocation.InvocationName -ne '.') - dot-sourcing defines
   # Invoke-NativeChecked (and any other functions above this guard) without
   # performing arg-parse or a release (ps1-native-stderr-guard, Spec-AC-03).
