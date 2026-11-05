# Launcher: the migration logic lives in migrate-state-to-local.mjs (RFC-0017 phase 5).
# Usage: powershell -NoProfile -File .aai/scripts/migrate-state-to-local.ps1 [-TargetRoot <path>] [-DryRun]
param([string]$TargetRoot = (Get-Location).Path, [switch]$DryRun)
$Module = Join-Path $PSScriptRoot 'migrate-state-to-local.mjs'
if ((Get-Command node -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $Module)) {
  $nodeArgs = @($Module, $TargetRoot)
  if ($DryRun) { $nodeArgs += '--dry-run' }
  & node @nodeArgs
  exit $LASTEXITCODE
}
[Console]::Error.WriteLine('migrate-state-to-local: refused - node not found in PATH or migrate-state-to-local.mjs missing; nothing was changed. Install Node.js 22 or later (https://nodejs.org/) and re-run.')
exit 1
