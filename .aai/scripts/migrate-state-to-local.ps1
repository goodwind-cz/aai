<#
.SYNOPSIS
  Migrate AAI per-dev runtime state to local-only (RFC-0001).

.DESCRIPTION
  Untracks docs/ai/STATE.yaml and docs/ai/LOOP_TICKS.jsonl from git so
  each developer keeps their own loop state without merge conflicts.
  Cross-developer visibility lives in docs/ai/EVENTS.jsonl (append-only,
  committed).

  Idempotent: re-runs are no-ops when state is already migrated.
  Does NOT auto-commit. Prints the next commands for the user to run.

.PARAMETER TargetRoot
  Path to the target AAI project. Defaults to current directory.

.PARAMETER DryRun
  Preview changes without writing to disk.

.EXAMPLE
  .\.aai\scripts\migrate-state-to-local.ps1

.EXAMPLE
  .\.aai\scripts\migrate-state-to-local.ps1 -TargetRoot C:\path\to\project -DryRun
#>

[CmdletBinding()]
param(
  [string]$TargetRoot = (Get-Location).Path,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$TargetRoot = (Resolve-Path -LiteralPath $TargetRoot).Path

if (-not (Test-Path (Join-Path $TargetRoot "docs/ai"))) {
  Write-Error "$TargetRoot/docs/ai not found. Is this an AAI project?"
  exit 1
}

Push-Location $TargetRoot
try {
  & git rev-parse --git-dir *> $null
  if ($LASTEXITCODE -ne 0) {
    Write-Error "$TargetRoot is not inside a git repository."
    exit 1
  }

  $dirty = & git status --porcelain
  if ($dirty) {
    Write-Error "Working tree has uncommitted changes. Commit or stash them first, then re-run."
    exit 1
  }

  $gitignorePath = Join-Path $TargetRoot ".gitignore"
  $stateFile     = "docs/ai/STATE.yaml"
  $ticksFile     = "docs/ai/LOOP_TICKS.jsonl"
  $eventsFile    = "docs/ai/EVENTS.jsonl"

  $untrackedCount  = 0
  $gitignoreAdded  = 0
  $eventsCreated   = 0

  Write-Host "AAI per-dev runtime state migration (RFC-0001)"
  Write-Host "Target: $TargetRoot"
  if ($DryRun) { Write-Host "Mode:   dry-run (no changes will be written)" }
  Write-Host ""

  # 1. Untrack STATE.yaml and LOOP_TICKS.jsonl if tracked.
  foreach ($f in @($stateFile, $ticksFile)) {
    & git ls-files --error-unmatch $f *> $null
    if ($LASTEXITCODE -eq 0) {
      Write-Host "UNTRACK $f (file remains on disk)"
      if (-not $DryRun) {
        & git rm --cached $f | Out-Null
      } else {
        Write-Host "  [dry-run] git rm --cached $f"
      }
      $untrackedCount++
    } else {
      Write-Host "SKIP    $f (already untracked or absent)"
    }
  }

  # 1b. Untrack runtime evidence dirs (per-dev; .gitkeep placeholders stay).
  $tddTracked = & git ls-files "docs/ai/tdd" "docs/ai/loop" 2>$null
  foreach ($f in @($tddTracked)) {
    if (-not $f -or $f -like "*/.gitkeep") { continue }
    Write-Host "UNTRACK $f (runtime evidence; file remains on disk)"
    if (-not $DryRun) {
      & git rm --cached $f | Out-Null
    } else {
      Write-Host "  [dry-run] git rm --cached $f"
    }
    $untrackedCount++
  }

  # 2. Add gitignore entries if missing.
  $giContent = ""
  if (Test-Path $gitignorePath) {
    $giContent = Get-Content -LiteralPath $gitignorePath -Raw -ErrorAction SilentlyContinue
  }

  $headerWritten = $false
  foreach ($pattern in @($stateFile, $ticksFile, 'docs/ai/tdd/**', '!docs/ai/tdd/', '!docs/ai/tdd/.gitkeep', 'docs/ai/loop/')) {
    # \r? before $: CRLF gitignores leave \r on the line in multiline mode
    $exists = $giContent -match ("(?m)^" + [regex]::Escape($pattern) + "\r?$")
    if (-not $exists) {
      if (-not $headerWritten) {
        Write-Host "GITIGNORE add header + entries to $gitignorePath"
        if (-not $DryRun) {
          Add-Content -Path $gitignorePath -Value "`n# AAI per-dev runtime state (RFC-0001: never committed)"
        }
        $headerWritten = $true
      }
      Write-Host "GITIGNORE add: $pattern"
      if (-not $DryRun) {
        Add-Content -Path $gitignorePath -Value $pattern
      }
      $gitignoreAdded++
    } else {
      Write-Host "SKIP    .gitignore already contains $pattern"
    }
  }

  # 3. Create EVENTS.jsonl placeholder if absent.
  $eventsAbs = Join-Path $TargetRoot $eventsFile
  if (-not (Test-Path $eventsAbs)) {
    Write-Host "CREATE  $eventsFile (empty, append-only audit log)"
    if (-not $DryRun) {
      $eventsDir = Join-Path $TargetRoot "docs/ai"
      New-Item -ItemType Directory -Force -Path $eventsDir | Out-Null
      New-Item -ItemType File -Force -Path $eventsAbs | Out-Null
    }
    $eventsCreated = 1
  } else {
    Write-Host "SKIP    $eventsFile already exists"
  }

  Write-Host ""
  Write-Host "Summary:"
  Write-Host "  Files untracked:        $untrackedCount"
  Write-Host "  .gitignore entries added: $gitignoreAdded"
  Write-Host "  EVENTS.jsonl created:   $eventsCreated"

  if ($DryRun) {
    Write-Host ""
    Write-Host "Dry-run only. Re-run without -DryRun to apply."
    exit 0
  }

  if ($untrackedCount -gt 0 -or $gitignoreAdded -gt 0 -or $eventsCreated -gt 0) {
    Write-Host ""
    Write-Host "Next steps (run manually):"
    Write-Host "  git -C `"$TargetRoot`" add .gitignore $eventsFile"
    Write-Host "  git -C `"$TargetRoot`" commit -m `"Migrate AAI STATE to per-dev local runtime (RFC-0001)`""
    Write-Host ""
    Write-Host "After commit, other developers will see STATE.yaml and LOOP_TICKS.jsonl"
    Write-Host "vanish from the tree on next pull. Their local copies remain on disk."
  } else {
    Write-Host ""
    Write-Host "Nothing to do - already migrated."
  }
}
finally {
  Pop-Location
}
