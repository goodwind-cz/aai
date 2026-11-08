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
# Remote -Confirm re-cuts a moved base under the same version (release-finish.mjs).
# Every release-head push first runs the release-preflight (tracked CHANGELOG node tests).
#
# Exit codes: 0 success (plan or cut) | 1 bad argument | 10 not a git repo |
#   11 no CHANGELOG.md | 12 malformed [unreleased] region | 13 no rollable
#   [unreleased] entries (absent/empty) | 15 tag already exists (cut path) |
#   16 gh absent/unauthenticated (when remote PR creation is attempted) |
#   8 finish pending in a merge queue (resume) | 20 finish refused.
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



# Probe a native command whose stderr is expected noise (non-zero is an answer, not a fault). Windows PowerShell 5.1
# turns any native stderr line into a terminating error under $ErrorActionPreference='Stop', even with 2>$null or *> $null,
# so the probe runs under 'Continue' and the caller reads $LASTEXITCODE.
function Invoke-Quiet {
  param([Parameter(Mandatory)][string]$Exe, [string[]]$Arguments)
  $ErrorActionPreference = 'Continue'
  & $Exe @Arguments 2>&1 | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }
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

$wtDir = $null
try {
  $Root = (Invoke-Quiet git @('rev-parse', '--show-toplevel'))
  if (-not $Root -or $LASTEXITCODE -ne 0) {
    [Console]::Error.WriteLine("REFUSED: not a git repository (cwd=$(Get-Location)).")
    exit 10
  }
  $Changelog = Join-Path $Root "CHANGELOG.md"
  if (-not (Test-Path $Changelog)) {
    [Console]::Error.WriteLine("REFUSED: no CHANGELOG.md at repo root: $Changelog")
    exit 11
  }

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

  if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    [Console]::Error.WriteLine("REFUSED: missing-node " + [char]0x2014 + " Node.js 22 or later is required for /aai-release (https://nodejs.org/); nothing was changed.")
    exit 20
  }
  $cut = Join-Path $PSScriptRoot 'release-cut.mjs'

  $branch = (Invoke-Quiet git @('-C', $Root, 'symbolic-ref', 'refs/remotes/origin/HEAD'))
  if ($LASTEXITCODE -ne 0) { $branch = $null }
  if ($branch) { $branch = $branch -replace '^refs/remotes/origin/', '' }
  if (-not $branch) {
    $null = Invoke-Quiet git @('-C', $Root, 'rev-parse', '-q', '--verify', 'refs/remotes/origin/main')
    if ($LASTEXITCODE -eq 0) {
      $branch = 'main'
    } else {
      $null = Invoke-Quiet git @('-C', $Root, 'rev-parse', '-q', '--verify', 'refs/heads/main')
      if ($LASTEXITCODE -eq 0) {
        $branch = 'main'
      } else {
        $branch = (Invoke-Quiet git @('-C', $Root, 'rev-parse', '--abbrev-ref', 'HEAD'))
        if (-not $branch -or $branch -eq "HEAD") { $branch = "main" }
      }
    }
  }

  if (-not $Confirm) {
    # PLAN-ONLY (bare invocation or -DryRun): release-cut.mjs prints the plan, which reaches the success stream; nothing is written.
    $planArgs = @($cut, 'plan', '--root', $Root, '--version', $Version, '--target-branch', $branch, '--launcher', 'ps1')
    if ($NoRemote) {
      $planArgs += '--no-remote'
    } elseif (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
      $planArgs += '--gh-block', 'gh CLI not found on PATH'
    } else {
      $null = Invoke-Quiet gh @('auth', 'status')
      if ($LASTEXITCODE -ne 0) { $planArgs += '--gh-block', 'gh CLI not authenticated (gh auth status failed)' }
    }
    & node @planArgs
    exit $LASTEXITCODE
  }

  # CONFIRM (the local cut, -NoRemote): rollup, tag and notes checks first; fail-closed
  & node $cut check --root $Root --version $Version --launcher ps1 --launcher-path $PSCommandPath
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  $releaseBranch = "chore/release-$Version"

  $baseRef = ""
  $null = Invoke-Quiet git @('-C', $Root, 'rev-parse', '-q', '--verify', "refs/remotes/origin/$branch")
  if ($LASTEXITCODE -eq 0) {
    $baseRef = "origin/$branch"
  } else {
    $null = Invoke-Quiet git @('-C', $Root, 'rev-parse', '-q', '--verify', "refs/heads/$branch")
    if ($LASTEXITCODE -eq 0) {
      $baseRef = $branch
    } else {
      $baseRef = "HEAD"
    }
  }

  $null = Invoke-Quiet git @('-C', $Root, 'rev-parse', '-q', '--verify', "refs/heads/$releaseBranch")
  if ($LASTEXITCODE -eq 0) {
    $existingSubject = (Invoke-Quiet git @('-C', $Root, 'log', '-1', '--format=%s', "refs/heads/$releaseBranch"))
    $isAncestor = $false
    $null = Invoke-Quiet git @('-C', $Root, 'merge-base', '--is-ancestor', $releaseBranch, $baseRef)
    if ($LASTEXITCODE -eq 0) { $isAncestor = $true }
    if (($existingSubject -like "chore(release): $Version*") -or $isAncestor) {
      $null = Invoke-Quiet git @('-C', $Root, 'branch', '-D', $releaseBranch)
    } else {
      [Console]::Error.WriteLine("REFUSED: branch $releaseBranch already exists with unmerged commits ($existingSubject).")
      exit 12
    }
  }

  $wtDir = Join-Path ([System.IO.Path]::GetTempPath()) ("aai-release-wt-" + [System.IO.Path]::GetRandomFileName())
  Invoke-NativeChecked -Exe 'git' -Arguments @('-C', $Root, 'worktree', 'add', '-q', '-b', $releaseBranch, $wtDir, $baseRef) | Out-Null
  try {
    # A refusal on the base branch's CHANGELOG.md exits with its code; the finally block removes the worktree.
    & node $cut roll --file (Join-Path $wtDir 'CHANGELOG.md') --version $Version
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
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
    $null = Invoke-Quiet git @('-C', $Root, 'worktree', 'remove', '--force', $wtDir)
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
  if ($wtDir -and (Test-Path $wtDir)) {
    $null = Invoke-Quiet git @('-C', $Root, 'worktree', 'remove', '--force', $wtDir)
    Remove-Item -Recurse -Force $wtDir -ErrorAction SilentlyContinue
  }
}

}
