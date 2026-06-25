#!/usr/bin/env pwsh
# AAI L1 Triage - read-only health snapshot. Writes nothing; safe to schedule.
#
# Surfaces docs drift, runtime-state presence, and working-tree cleanliness so an
# operator (or an L1 scheduled run) sees problems BEFORE launching a full,
# write-capable loop. This is the cheapest rung of autonomy: read and report only.
#
# Usage:
#   ./.aai/scripts/triage.ps1            # print report, always exit 0
#   ./.aai/scripts/triage.ps1 -Check     # exit 1 if anything needs triage (CI gate)
param([switch]$Check)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '../..')
Set-Location $root

$state = 'docs/ai/STATE.yaml'
$ticks = 'docs/ai/LOOP_TICKS.jsonl'
$issues = 0

Write-Output "## AAI L1 Triage - $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))"
Write-Output ''

# 1) Runtime state presence
if ((Test-Path $state) -and (Select-String -Path $state -Pattern '^project_status:' -Quiet)) {
  $ps = ((Select-String -Path $state -Pattern '^project_status:' | Select-Object -First 1).Line -split '\s+')[1]
  Write-Output "- State: present (project_status=$ps)"
} else {
  # Benign before the first run - the orchestrator auto-creates state. Informational only.
  Write-Output "- State: not present yet ($state) - orchestrator will init, or run /aai-check-state"
}

# 2) Working tree
$porcelain = git status --porcelain 2>$null
if ($porcelain) {
  $n = ($porcelain | Measure-Object -Line).Lines
  Write-Output "- Working tree: $n uncommitted change(s)"
} else {
  Write-Output "- Working tree: clean"
}

# 3) Last recorded tick
if ((Test-Path $ticks) -and (Get-Item $ticks).Length -gt 0) {
  Write-Output "- Last tick: $(Get-Content $ticks -Tail 1)"
} else {
  Write-Output "- Last tick: none recorded"
}

# 4) Docs audit (quick is read-only: --quick skips the EVENTS append)
Write-Output ''
if ((Get-Command node -ErrorAction SilentlyContinue) -and (Test-Path '.aai/scripts/docs-audit.mjs')) {
  $audit = node .aai/scripts/docs-audit.mjs --quick 2>$null
  $shown = $audit | Select-String -Pattern '^- (Mode|Scanned|Tracked):|^### Verdict:'
  if ($shown) { $shown.Line | ForEach-Object { Write-Output $_ } } else { Write-Output "- Docs audit: (no output)" }
  if ($audit | Select-String -Pattern 'NEEDS-TRIAGE' -Quiet) { $issues++ }
} else {
  Write-Output "- Docs audit: skipped (node or docs-audit.mjs unavailable)"
}

Write-Output ''
if ($issues -eq 0) {
  Write-Output "### Triage verdict: CLEAN"
} else {
  Write-Output "### Triage verdict: NEEDS-ATTENTION ($issues area(s))"
  if ($Check) { exit 1 }
}
exit 0
