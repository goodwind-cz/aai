#!/usr/bin/env pwsh
# Expert fetch launcher; the logic lives in expert-fetch.mjs (RFC-0017 phase 3).
# Usage: see expert-fetch.mjs (--list, --detect, --check, --body, <key> [--force]).
[CmdletBinding(PositionalBinding = $false)]
param([string]$ExpertKey, [switch]$Force, [string[]]$Detect, [string]$Body, [switch]$List, [string]$Check, [string]$Phase,
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
$Module = Join-Path $PSScriptRoot 'expert-fetch.mjs'
$Rest = @($Rest | Where-Object { $_ })
if ($List) { $NodeArgs = @('--list') }
elseif ($Detect) { $NodeArgs = @('--detect') + $Detect + $Rest }
elseif ($Check) { $NodeArgs = @('--check', $Check) + @($Phase | Where-Object { $_ }) + $Rest }
elseif ($Body) { $NodeArgs = @('--body', $Body) }
else { $NodeArgs = @($ExpertKey | Where-Object { $_ }) + $Rest; if ($Force) { $NodeArgs += '--force' } }
if ((Get-Command node -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $Module)) {
  & node $Module @NodeArgs
  exit $LASTEXITCODE
}
[Console]::Error.WriteLine('ERROR: expert-fetch needs node (expert-fetch.mjs unavailable)')
exit 1
