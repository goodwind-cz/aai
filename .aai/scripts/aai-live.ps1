#!/usr/bin/env pwsh
# Live-status launcher; the logic lives in aai-live.mjs (RFC-0017 small-pairs slice).
# Usage: aai-live.ps1 [--watch] [--interval <s>] [--data-only] [...]
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$RestArgs)
$Module = Join-Path $PSScriptRoot 'aai-live.mjs'
if ((Get-Command node -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $Module)) {
  & node $Module @RestArgs
  exit $LASTEXITCODE
}
[Console]::Error.WriteLine('aai-live: refused - node not found in PATH or aai-live.mjs missing')
exit 1
