#!/usr/bin/env pwsh
# AAI release-cut engine - PowerShell parity twin of aai-release.sh for /aai-release.
#
# Rolls the repo root's CHANGELOG.md `[unreleased]` blocks into a versioned
# section, commits in an isolated temporary worktree, pushes a release branch,
# and finishes a bound release PR — behind an operator gate with a safe default
# (plan-only) mode. On merge to main, CI creates the annotated tag and
# publishes the GitHub release.
#
# Usage (run from anywhere inside the target repo):
#   ./.aai/scripts/aai-release.ps1                          # plan-only (default-safe), no writes
#   ./.aai/scripts/aai-release.ps1 -DryRun                  # same as bare invocation, explicit
#   ./.aai/scripts/aai-release.ps1 -Version v1.2.3          # verbatim version (any scheme)
#   ./.aai/scripts/aai-release.ps1 -Confirm                 # CUT: merge, verify, clean up
#   ./.aai/scripts/aai-release.ps1 -Confirm -NoRemote       # CUT, skip push + gh pr create
#   $env:AAI_RELEASE_DATE="2026-07-20"; ./.aai/scripts/aai-release.ps1 -DryRun
#   $env:AAI_RELEASE_NO_REMOTE="1"; ./.aai/scripts/aai-release.ps1 -Confirm
#
# Exit codes: 0 success (plan or cut) | 1 bad argument | 10 not a git repo |
#   11 no CHANGELOG.md | 12 malformed [unreleased] region | 13 no rollable
#   [unreleased] entries (absent/empty) | 15 tag already exists (cut path) |
#   16 gh absent/unauthenticated (when remote PR creation is attempted).
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
  return $out
}



function Select-CapturedValue {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object]$Captured,
    [Parameter(Mandatory)][string]$Pattern,
    [string]$Name = 'required-native-output'
  )
  foreach ($line in @($Captured)) {
    $text = "$line".Trim()
    if ($text -match $Pattern) { return $text }
  }
  throw "REFUSED: empty-native-output - $Name did not return a validated value"
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

if ($DryRun) { $Confirm = $false }

$OutFile = $null
$NotesFile = $null
$wtDir = $null
try {
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

  $dirtyOut = (git -C $Root status --porcelain 2>$null)
  $Dirty = [bool]($dirtyOut -and $dirtyOut.Trim().Length -gt 0)

  if (-not $Version) {
    $releaseDate = $env:AAI_RELEASE_DATE
    if ($releaseDate) {
      $Version = "v" + ($releaseDate -replace '-', '.')
    } else {
      $Version = "v" + ((Get-Date).ToUniversalTime().ToString("yyyy.MM.dd"))
    }
  }

  if ($Confirm -and -not $NoRemote) {
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
      [Console]::Error.WriteLine("REFUSED: missing-node - Node.js is required for release finish")
      [Console]::Error.WriteLine("Resume: pwsh -NoProfile -File `"$PSCommandPath`" -Version $Version -Confirm")
      exit 20
    }
    & node (Join-Path $PSScriptRoot 'release-finish.mjs') --root $Root --version $Version --confirm
    exit $LASTEXITCODE
  }

  function Invoke-ChangelogRollup {
    [CmdletBinding()]
    param(
      [Parameter(Mandatory)][string]$Path,
      [Parameter(Mandatory)][string]$VersionString
    )
    $lines = Get-Content -LiteralPath $Path
    $n = $lines.Count
    $firstHeading = -1
    for ($i = 0; $i -lt $n; $i++) {
      if ($lines[$i] -match '^## \[') { $firstHeading = $i; break }
    }
    if ($firstHeading -eq -1) {
      return @{ Success = $false; ExitCode = 13; Error = "REFUSED: no rollable [unreleased] entries in CHANGELOG.md (absent or empty) - nothing to release." }
    }

    $headIdx = New-Object System.Collections.Generic.List[int]
    for ($i = $firstHeading; $i -lt $n; $i++) {
      if ($lines[$i] -match '^## ') { $headIdx.Add($i) }
    }
    $headIdx.Add($n)

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
      return @{ Success = $false; ExitCode = 12; Error = "REFUSED: malformed [unreleased] heading in CHANGELOG.md (a '## [unreleased]' line has unexpected trailing text or a stray heading-only body) - never silently dropping entries." }
    }
    if ($entryCount -eq 0) {
      return @{ Success = $false; ExitCode = 13; Error = "REFUSED: no rollable [unreleased] entries in CHANGELOG.md (absent or empty) - nothing to release." }
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
        $newline = $line.Substring(0, $pos) + "[" + $VersionString + "]" + $line.Substring($pos + "[unreleased]".Length)
        $newLines.Add($newline)
        $notesLines.Add($newline)
      } elseif ($type[$k] -eq "SCAFFOLD") {
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

    $origBytes = [System.IO.File]::ReadAllText($Path)
    $hadTrailingNewline = $origBytes.EndsWith("`n")
    $newContent = ($newLines -join "`n")
    if ($hadTrailingNewline) { $newContent += "`n" }

    return @{
      Success = $true
      ExitCode = 0
      NewContent = $newContent
      Notes = ($trimmedNotes -join "`n")
    }
  }

  $initialRollup = Invoke-ChangelogRollup -Path $Changelog -VersionString $Version
  if (-not $initialRollup.Success) {
    [Console]::Error.WriteLine($initialRollup.Error)
    exit $initialRollup.ExitCode
  }

  $OutFile = Join-Path $Root (".aai-release-changelog." + [System.IO.Path]::GetRandomFileName())
  $NotesFile = Join-Path ([System.IO.Path]::GetTempPath()) ("aai-release-notes." + [System.IO.Path]::GetRandomFileName())
  [System.IO.File]::WriteAllText($OutFile, $initialRollup.NewContent)
  [System.IO.File]::WriteAllText($NotesFile, $initialRollup.Notes)

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

  $branch = (git -C $Root symbolic-ref refs/remotes/origin/HEAD 2>$null)
  if ($branch) { $branch = $branch -replace '^refs/remotes/origin/', '' }
  if (-not $branch) {
    git -C $Root rev-parse -q --verify refs/remotes/origin/main *> $null
    if ($LASTEXITCODE -eq 0) {
      $branch = 'main'
    } else {
      git -C $Root rev-parse -q --verify refs/heads/main *> $null
      if ($LASTEXITCODE -eq 0) {
        $branch = 'main'
      } else {
        $branch = (git -C $Root rev-parse --abbrev-ref HEAD 2>$null)
        if (-not $branch -or $branch -eq "HEAD") { $branch = "main" }
      }
    }
  }

  $auditArgs = @((Join-Path $PSScriptRoot 'release-finish.mjs'), '--root', $Root, '--audit', $NotesFile)
  if (-not $ghBlock -and -not $NoRemote) { $auditArgs += '--online' }
  $unlogged = @(& node @auditArgs)
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

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
    if ($unlogged.Count -gt 0) { Write-Host "- NAMED (not blocking): missing notes"; $unlogged | ForEach-Object { Write-Host "    - $_" } }
    if ($tagExists) { Write-Host "- would block: tag $Version already exists"; $blocked = $true }
    if ($ghBlock) { Write-Host "- would block (publish path): $ghReason"; $blocked = $true }
    if (-not $blocked -and $unlogged.Count -eq 0) { Write-Host "- none - ready to cut with -Confirm" }
    elseif ($unlogged.Count -gt 0) { Write-Host "- confirm will refuse until missing release notes are resolved" }
    Write-Host ""
    Write-Host "## Remote"
    if ($NoRemote) {
      Write-Host "- -NoRemote / AAI_RELEASE_NO_REMOTE=1: push + gh pr create would be SKIPPED"
    } else {
      Write-Host "- push (branch chore/release-$Version) and 'gh pr create' (base $branch) WOULD run against this repo's remote; CI will tag and publish upon merge"
    }
    exit 0
  }

  if ($tagExists) {
    [Console]::Error.WriteLine("REFUSED: tag $Version already exists.")
    exit 15
  }
  if ($ghBlock) {
    [Console]::Error.WriteLine("REFUSED: $ghReason (publish path) - dry-run works offline; pass -NoRemote/AAI_RELEASE_NO_REMOTE=1 to skip publish, or fix gh auth.")
    exit 16
  }

  if ($unlogged.Count -gt 0) {
    [Console]::Error.WriteLine("REFUSED: missing-notes - $($unlogged -join '; ')")
    [Console]::Error.WriteLine("Resume: pwsh -NoProfile -File `"$PSCommandPath`" -Version $Version -Confirm -NoRemote")
    exit 20
  }

  $releaseBranch = "chore/release-$Version"

  $baseRef = ""
  git -C $Root rev-parse -q --verify "refs/remotes/origin/$branch" *> $null
  if ($LASTEXITCODE -eq 0) {
    $baseRef = "origin/$branch"
  } else {
    git -C $Root rev-parse -q --verify "refs/heads/$branch" *> $null
    if ($LASTEXITCODE -eq 0) {
      $baseRef = $branch
    } else {
      $baseRef = "HEAD"
    }
  }

  git -C $Root rev-parse -q --verify "refs/heads/$releaseBranch" *> $null
  if ($LASTEXITCODE -eq 0) {
    $existingSubject = (git -C $Root log -1 --format=%s "refs/heads/$releaseBranch" 2>$null)
    $isAncestor = $false
    git -C $Root merge-base --is-ancestor $releaseBranch $baseRef *> $null
    if ($LASTEXITCODE -eq 0) { $isAncestor = $true }
    if (($existingSubject -like "chore(release): $Version*") -or $isAncestor) {
      git -C $Root branch -D $releaseBranch *> $null
    } else {
      [Console]::Error.WriteLine("REFUSED: branch $releaseBranch already exists with unmerged commits ($existingSubject).")
      exit 12
    }
  }

  $wtDir = Join-Path ([System.IO.Path]::GetTempPath()) ("aai-release-wt-" + [System.IO.Path]::GetRandomFileName())
  Invoke-NativeChecked -Exe 'git' -Arguments @('-C', $Root, 'worktree', 'add', '-q', '-b', $releaseBranch, $wtDir, $baseRef) | Out-Null
  try {
    $wtChangelog = Join-Path $wtDir 'CHANGELOG.md'
    $wtRollup = Invoke-ChangelogRollup -Path $wtChangelog -VersionString $Version
    if (-not $wtRollup.Success) {
      [Console]::Error.WriteLine($wtRollup.Error)
      exit $wtRollup.ExitCode
    }
    [System.IO.File]::WriteAllText($wtChangelog, $wtRollup.NewContent)
    $wtAiDir = Join-Path $wtDir 'docs/ai'
    New-Item -ItemType Directory -Force -Path $wtAiDir | Out-Null
    $versionDoc = @(
      '# AAI Version', '',
      "- Version: $Version", '',
      'Notes:',
      '- Written by the release engines (aai-release.sh / aai-release.ps1) at each cut;',
      '  consumed by `.aai/scripts/aai-sync.*` to stamp `Template version:` into the',
      '  target project''s `.aai/system/AAI_PIN.md`. Do not edit by hand.'
    )
    Set-Content -LiteralPath (Join-Path $wtAiDir 'AAI_VERSION.md') -Value ($versionDoc -join "`n") -NoNewline:$false
    Invoke-NativeChecked -Exe 'git' -Arguments @('-C', $wtDir, 'add', '--', 'CHANGELOG.md', 'docs/ai/AAI_VERSION.md') | Out-Null
    Invoke-NativeChecked -Exe 'git' -Arguments @('-C', $wtDir, 'commit', '-q', '-m', "chore(release): $Version") | Out-Null
    $releaseSha = Select-CapturedValue -Captured (Invoke-NativeChecked -Exe 'git' -Arguments @('-C', $wtDir, 'rev-parse', 'HEAD')) -Pattern '^(?:[0-9a-f]{40}|[0-9a-f]{64})$' -Name 'release-sha'
  } finally {
    git -C $Root worktree remove --force $wtDir *> $null
    if (Test-Path $wtDir) { Remove-Item -Recurse -Force $wtDir -ErrorAction SilentlyContinue }
    $wtDir = $null
  }

  $shortSha = Select-CapturedValue -Captured (Invoke-NativeChecked -Exe 'git' -Arguments @('-C', $Root, 'rev-parse', '--short', $releaseSha)) -Pattern '^[0-9a-f]{7,64}$' -Name 'short-sha'
  Write-Host "## aai-release - cut complete"
  Write-Host "- Version: $Version"
  Write-Host "- Commit:  $shortSha"
  Write-Host "- Release branch: $releaseBranch ($releaseSha)"

  Write-Host "- Remote:  SKIPPED (-NoRemote/AAI_RELEASE_NO_REMOTE=1) - release branch $releaseBranch created locally"
  exit 0
} finally {
  if ($OutFile -and (Test-Path $OutFile)) { Remove-Item -Force $OutFile -ErrorAction SilentlyContinue }
  if ($NotesFile -and (Test-Path $NotesFile)) { Remove-Item -Force $NotesFile -ErrorAction SilentlyContinue }
  if ($wtDir -and (Test-Path $wtDir)) {
    git -C $Root worktree remove --force $wtDir *> $null
    Remove-Item -Recurse -Force $wtDir -ErrorAction SilentlyContinue
  }
}

}
