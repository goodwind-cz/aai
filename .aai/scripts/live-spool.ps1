#!/usr/bin/env pwsh
# live-spool.ps1 - launcher for live-spool.mjs, the statusline/hook tap writer
# (SPEC-0114). All logic lives in the Node module; Node inherits stdin, so
# nothing is decoded here. Always exits 0. When Node is absent or cannot run
# the module, it drains stdin and prints the passthrough for statusline only.
param([Parameter(Position = 0)][string]$Kind = 'statusline')
$Module = Join-Path $PSScriptRoot 'live-spool.mjs'
$Ran = $false
if (Get-Command node -ErrorAction SilentlyContinue) {
  & node $Module $Kind 2>$null
  $Ran = ($LASTEXITCODE -eq 0)
}
if (-not $Ran) {
  if ([Console]::IsInputRedirected) { $null = [Console]::In.ReadToEnd() }
  if ($Kind -eq 'statusline') { Write-Output '(aai-live tap active)' }
}
exit 0
