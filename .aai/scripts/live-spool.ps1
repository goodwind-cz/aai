#!/usr/bin/env pwsh
# live-spool.ps1 - launcher for live-spool.mjs, the statusline/hook tap writer
# (SPEC-0114). All logic lives in the Node module; Node inherits stdin, so
# nothing is decoded here. Always exits 0. Without Node nothing can read the
# spool, so it only prints the passthrough.
param([Parameter(Position = 0)][string]$Kind = 'statusline')
$Module = Join-Path $PSScriptRoot 'live-spool.mjs'
if (Get-Command node -ErrorAction SilentlyContinue) {
  & node $Module $Kind 2>$null
} elseif ($Kind -eq 'statusline') {
  Write-Output '(aai-live tap active)'
}
exit 0
