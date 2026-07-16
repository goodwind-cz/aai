#!/usr/bin/env pwsh
# AAI layer updater - one deterministic command for /aai-update.
#
# Materializes the canonical AAI repo's `main`, runs aai-sync into THIS project,
# and prints concise post-sync evidence. Replaces the old 7-step agent-narrated
# procedure: the agent now runs this once and relays the final report.
#
# Usage (run from the TARGET project root):
#   ./.aai/scripts/aai-update.ps1                       # sync from goodwind-cz/aai@main
#   ./.aai/scripts/aai-update.ps1 -DryRun              # print the plan, change nothing
#   ./.aai/scripts/aai-update.ps1 -Repo OWNER/NAME     # alternate upstream slug
#   ./.aai/scripts/aai-update.ps1 -Repo ../aai         # alternate upstream: local checkout
#   ./.aai/scripts/aai-update.ps1 -Ref some-branch     # non-default ref
#   ./.aai/scripts/aai-update.ps1 -KeepTemp            # keep the temp clone for inspection
#   ./.aai/scripts/aai-update.ps1 -Force               # allow running inside the canonical repo
#
# PowerShell parses the whole script before running, so (unlike the bash twin) it
# needs no self-relocation: the sync overwriting this file mid-run is harmless.
param(
  [string]$Repo = "goodwind-cz/aai",
  [string]$Ref = "main",
  [switch]$DryRun,
  [switch]$KeepTemp,
  [switch]$Force,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$ExtraArgs
)

# The /aai-update skill forwards the user's flags verbatim in bash long-flag form
# (--dry-run, --repo, --ref, --keep-temp, --force). Accept those in addition to
# the native -DryRun/-Repo/... so this entrypoint behaves like the bash twin.
$extra = @(); if ($ExtraArgs) { $extra = @($ExtraArgs) }
for ($i = 0; $i -lt $extra.Count; $i++) {
  switch -Regex ($extra[$i]) {
    '^--dry-run$'    { $DryRun = $true }
    '^--keep-temp$'  { $KeepTemp = $true }
    '^--force$'      { $Force = $true }
    '^--repo=(.+)$'  { $Repo = $Matches[1] }
    '^--ref=(.+)$'   { $Ref = $Matches[1] }
    '^--repo$'       { $i++; if ($i -lt $extra.Count) { $Repo = $extra[$i] } }
    '^--ref$'        { $i++; if ($i -lt $extra.Count) { $Ref = $extra[$i] } }
    default { [Console]::Error.WriteLine("WARN: ignoring unrecognized argument '$($extra[$i])'") }
  }
}

$ErrorActionPreference = "Stop"
$Target = (Get-Location).Path

function Get-NormSlug([string]$s) {
  if (-not $s) { return "" }
  $s = $s -replace '\.git$', ''
  if ($s -match 'github\.com[:/](.+)$') { $s = $Matches[1] }
  if ($s -match '^[^/]+/[^/]+$') { return $s.ToLower() }
  return ""
}

# Canonical-repo guard: refuse to sync the AAI repo into itself.
$targetOrigin = (git -C $Target config --get remote.origin.url 2>$null)
if ((Get-NormSlug $Repo) -and ((Get-NormSlug $targetOrigin) -eq (Get-NormSlug $Repo)) -and (-not $Force)) {
  [Console]::Error.WriteLine("REFUSED: this project ($targetOrigin) looks like the canonical AAI repo.")
  [Console]::Error.WriteLine("  /aai-update syncs AAI INTO a target project; update the canonical repo with normal git.")
  [Console]::Error.WriteLine("  Pass -Force to override.")
  exit 2
}

$Tmp = $null
try {
  # Resolve SOURCE: an existing local checkout, or a fresh shallow clone.
  if (Test-Path -PathType Container $Repo) {
    $Src = (Resolve-Path $Repo).Path
    git -C $Src fetch --depth 1 origin $Ref *> $null
    git -C $Src checkout $Ref *> $null
    git -C $Src pull --ff-only origin $Ref *> $null
    $SrcDesc = "local checkout $Src"
  } else {
    if ($Repo -match '://' -or $Repo -match '@.+:') { $CloneUrl = $Repo } else { $CloneUrl = "https://github.com/$Repo.git" }
    $SrcDesc = "$CloneUrl@$Ref"
    if (-not $DryRun) {
      $Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("aai-src-" + [System.IO.Path]::GetRandomFileName())
      $cloned = $false
      # git refuses to clone into a non-empty dir, and a failed attempt leaves a
      # partial one behind - so wipe $Tmp before every attempt.
      if (Get-Command gh -ErrorAction SilentlyContinue) {
        if (Test-Path $Tmp) { Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue }
        gh repo clone $Repo $Tmp -- --branch $Ref --depth 1 *> $null
        if ($LASTEXITCODE -eq 0) { $cloned = $true }
      }
      if (-not $cloned) {
        if (Test-Path $Tmp) { Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue }
        git clone --branch $Ref --depth 1 $CloneUrl $Tmp *> $null
        if ($LASTEXITCODE -eq 0) { $cloned = $true }
      }
      if (-not $cloned) {
        # Last resort: a truly anonymous clone. On a machine where `gh auth setup-git`
        # wired gh in as git's credential helper, a broken/expired token gets injected
        # even into the plain `git clone` above - 401-ing a PUBLIC repo that needs no
        # auth at all. Emptying the credential helper + any injected auth header forces
        # git to fetch anonymously, so the public canonical repo clones with no creds.
        if (Test-Path $Tmp) { Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue }
        $env:GIT_TERMINAL_PROMPT = '0'  # PR#67 review NB-1: never prompt
        git -c credential.helper= -c http.https://github.com/.extraheader= clone --branch $Ref --depth 1 $CloneUrl $Tmp *> $null
        if ($LASTEXITCODE -eq 0) { $cloned = $true }
      }
      if (-not $cloned) {
        [Console]::Error.WriteLine("ERROR: could not fetch $Repo@$Ref (auth or network?). Treat as an access issue, not a missing repo.")
        exit 3
      }
    }
    $Src = $Tmp
  }

  if ($DryRun) {
    Write-Host "## aai-update (dry-run) - no files changed"
    Write-Host "- Target:   $Target"
    Write-Host "- Upstream: $SrcDesc"
    Write-Host ('- Would run: SOURCE/.aai/scripts/aai-sync.ps1 -TargetRoot "{0}"' -f $Target)
    Write-Host "- Then check: git status --short, .aai/system/AAI_PIN.md, docs/ai/reports/sync-conflicts-*.md"
    Write-Host "- Next: /aai-doctor (and /aai-bootstrap if skills changed)"
    exit 0
  }

  $Sync = Join-Path $Src ".aai/scripts/aai-sync.ps1"
  if (-not (Test-Path $Sync)) { [Console]::Error.WriteLine("ERROR: sync script missing in source: $Sync"); exit 4 }

  Write-Host "## aai-update - syncing $SrcDesc into $Target"
  & $Sync -TargetRoot $Target

  Write-Host ""
  Write-Host "## Post-sync evidence"
  $changed = @(git -C $Target status --short 2>$null | Where-Object { $_ })
  if ($changed.Count -gt 0) {
    Write-Host "- Changed files ($($changed.Count)):"
    $changed | ForEach-Object { Write-Host "  $_" }
  } else {
    Write-Host "- Changed files: none (already up to date)"
  }

  $pin = Join-Path $Target ".aai/system/AAI_PIN.md"
  if (Test-Path $pin) {
    Write-Host "- AAI_PIN:"
    Select-String -Path $pin -Pattern 'source|version|commit|ref|canonical' | ForEach-Object { Write-Host "  $($_.Line)" }
  }

  $reports = Join-Path $Target "docs/ai/reports"
  if (Test-Path $reports) {
    $conf = Get-ChildItem $reports -Filter "sync-conflicts-*.md" -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($conf) { Write-Host "- ! Conflict advisory: $($conf.Name) - review before committing." }
  }

  Write-Host ""
  Write-Host "## Next"
  Write-Host "- Review the diff (git diff), then commit manually (this tool never auto-commits)."
  Write-Host "- Recommended: /aai-doctor (and /aai-bootstrap if skills/indexes changed)"
} finally {
  if ((-not $KeepTemp) -and $Tmp -and (Test-Path $Tmp)) {
    Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
  }
}
