# Pre-compact context save script (PowerShell)
# Saves critical AAI state before Claude Code compresses context messages.
# Source: Inspired by pro-workflow pre-compact hook (https://github.com/rohitg00/pro-workflow)
#
# Usage: Called automatically via Claude Code PreCompact hook
# Configure in .claude/settings.local.json:
#   "hooks": { "PreCompact": [{ "command": "powershell -File .aai/scripts/pre-compact-save.ps1" }] }

$ErrorActionPreference = "Stop"

$ProjectRoot = git rev-parse --show-toplevel 2>$null
if (-not $ProjectRoot) { $ProjectRoot = Get-Location }

$StateFile = Join-Path $ProjectRoot "docs/ai/STATE.yaml"
$DecisionsFile = Join-Path $ProjectRoot "docs/ai/decisions.jsonl"
$MetricsFile = Join-Path $ProjectRoot "docs/ai/METRICS.jsonl"
$OutputFile = Join-Path $ProjectRoot "docs/ai/.session-context.md"
$BackupFile = Join-Path $ProjectRoot "docs/ai/.pre-compact-state-backup.yaml"

$Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# Backup STATE.yaml
if (Test-Path $StateFile) {
    Copy-Item $StateFile $BackupFile -Force
}

# Build context snapshot
$output = @()
$output += "# Pre-Compact Context Snapshot"
$output += "# Auto-generated at $Timestamp"
$output += "# Read this file after context compression to restore awareness."
$output += ""

$output += "## Current State"
if (Test-Path $StateFile) {
    $output += '```yaml'
    $output += Get-Content $StateFile -Raw
    $output += '```'
} else {
    $output += "STATE.yaml not found."
}
$output += ""

$output += "## Recent Decisions (last 5)"
if (Test-Path $DecisionsFile) {
    $output += '```json'
    $output += Get-Content $DecisionsFile -Tail 5
    $output += '```'
} else {
    $output += "No decisions log found."
}
$output += ""

$output += "## Recent Metrics (last 3)"
if (Test-Path $MetricsFile) {
    $output += '```json'
    $output += Get-Content $MetricsFile -Tail 3
    $output += '```'
} else {
    $output += "No metrics log found."
}
$output += ""

$output += "## Git Status"
$output += '```'
try {
    $output += (git -C $ProjectRoot status --short 2>$null)
} catch {
    $output += "Not a git repository"
}
$output += '```'
$output += ""

$output += "## Current Branch"
try {
    $output += (git -C $ProjectRoot branch --show-current 2>$null)
} catch {
    $output += "Unknown"
}

$output -join "`n" | Set-Content $OutputFile -Encoding UTF8

Write-Host "Pre-compact context saved to $OutputFile"
