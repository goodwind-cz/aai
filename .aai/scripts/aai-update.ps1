# AAI layer updater launcher; argument, source, sync and report policy live in aai-update.mjs (RFC-0017 phase 5).
# Usage: powershell -NoProfile -File .aai/scripts/aai-update.ps1 [-Repo X] [-Ref Y] [-DryRun] [-KeepTemp] [-Force] (the --long flags work too)
$ErrorActionPreference = 'Continue'; $PSNativeCommandUseErrorActionPreference = $false
$Module = Join-Path $PSScriptRoot 'aai-update.mjs'
if ((Get-Command node -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $Module)) {
  $prev = $env:AAI_UPDATE_SYNC_RUNNER; $env:AAI_UPDATE_SYNC_RUNNER = (Get-Process -Id $PID).Path
  $argv = New-Object System.Collections.Generic.List[string]
  foreach ($a in $args) {
    if ($a -is [bool]) { if (-not $a -and $argv.Count -gt 0) { $argv.RemoveAt($argv.Count - 1) }; continue }
    $s = if ($a -is [array]) { $a -join ',' } else { [string]$a }
    if ($s -match '^-[A-Za-z][A-Za-z0-9-]*:$') { $s = $s.Substring(0, $s.Length - 1) }
    if ($s -match '\s' -and $s.EndsWith('\') -and $PSVersionTable.PSVersion.Major -lt 6) { $s += '\' }
    $argv.Add($s)
  }
  try { & node $Module @argv } finally { $env:AAI_UPDATE_SYNC_RUNNER = $prev }
  exit $LASTEXITCODE
}
[Console]::Error.WriteLine('aai-update: refused - node not found in PATH or aai-update.mjs missing; nothing was changed. Install Node.js 22 or later (https://nodejs.org/) and re-run.')
exit 1
