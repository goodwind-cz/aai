#!/usr/bin/env pwsh
<#
.SYNOPSIS
  aai-live.ps1 - generate the live-status dashboard, then open it
  (SPEC-DRAFT-spec-live-status-dashboard). Windows twin of aai-live.sh.

.DESCRIPTION
  No server, no port: opens the static HTML file directly via Start-Process
  (the Windows platform opener). All arguments pass through to
  generate-live-status.mjs.
#>
[CmdletBinding()]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$RestArgs
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $ScriptDir '..\..')
$Gen = Join-Path $ScriptDir 'generate-live-status.mjs'

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Write-Error 'aai-live: refused - node not found in PATH'
  exit 1
}
if (-not (Test-Path $Gen)) {
  Write-Error "aai-live: refused - generator not found: $Gen"
  exit 1
}

if ($null -eq $RestArgs) { $RestArgs = @() }
$DataOnly = $RestArgs -contains '--data-only'
$Watch = $RestArgs -contains '--watch'
$OutputHtml = Join-Path $RepoRoot 'docs/ai/live-status.html'

Set-Location $RepoRoot

if ($Watch) {
  & node $Gen --data-only | Out-Null
  if (-not $DataOnly) {
    Start-Process $OutputHtml -ErrorAction SilentlyContinue
  }
  & node $Gen @RestArgs
  exit $LASTEXITCODE
}

& node $Gen @RestArgs
$rc = $LASTEXITCODE
if ($rc -eq 0 -and -not $DataOnly) {
  Start-Process $OutputHtml -ErrorAction SilentlyContinue
}
exit $rc
