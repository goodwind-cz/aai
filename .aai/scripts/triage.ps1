#!/usr/bin/env pwsh
# AAI L1 Triage launcher; the logic lives in triage.mjs (RFC-0017 phase 3).
# Usage: ./.aai/scripts/triage.ps1 [-Check]
param([switch]$Check)
$Module = Join-Path $PSScriptRoot 'triage.mjs'
$NodeArgs = @()
if ($Check -or ($args -contains '--check')) { $NodeArgs += '--check' }
if ((Get-Command node -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $Module)) {
  & node $Module @NodeArgs
  exit $LASTEXITCODE
}
Write-Output '### Triage verdict: UNKNOWN (node or triage.mjs unavailable)'
exit 0
