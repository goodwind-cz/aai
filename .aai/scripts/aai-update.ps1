# AAI layer updater launcher; argument, source, sync and report policy live in aai-update.mjs (RFC-0017 phase 5).
# Usage: powershell -NoProfile -File .aai/scripts/aai-update.ps1 [-Repo X] [-Ref Y] [-DryRun] [-KeepTemp] [-Force] (the --long flags work too)
$ErrorActionPreference = 'Continue'
$PSNativeCommandUseErrorActionPreference = $false
$Module = Join-Path $PSScriptRoot 'aai-update.mjs'
if ((Get-Command node -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $Module)) {
  $prev = $env:AAI_UPDATE_SYNC_RUNNER
  $env:AAI_UPDATE_SYNC_RUNNER = (Get-Process -Id $PID).Path
  try { & node $Module @args } finally { $env:AAI_UPDATE_SYNC_RUNNER = $prev }
  exit $LASTEXITCODE
}
[Console]::Error.WriteLine('aai-update: refused - node not found in PATH or aai-update.mjs missing; nothing was changed. Install Node.js 22 or later (https://nodejs.org/) and re-run.')
exit 1
