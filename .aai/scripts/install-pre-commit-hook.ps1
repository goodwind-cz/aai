# AAI git hook installer launcher; mode, policy, slot and write rules live in install-pre-commit-hook.mjs (RFC-0017 phase 5).
# Usage: powershell -NoProfile -File .aai/scripts/install-pre-commit-hook.ps1 [-Force] [-Uninstall] [-Print [kind]] [-Hooks <csv>] [-DeclineRefGuard] [-ArmRefGuard] [-h] (the --long flags work too)
$ErrorActionPreference = 'Continue'
$PSNativeCommandUseErrorActionPreference = $false
$Module = Join-Path $PSScriptRoot 'install-pre-commit-hook.mjs'
if ((Get-Command node -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $Module)) {
  $argv = New-Object System.Collections.Generic.List[string]
  foreach ($a in $args) {
    if ($a -is [bool]) { if (-not $a -and $argv.Count -gt 0) { $argv.RemoveAt($argv.Count - 1) }; continue }
    $s = if ($a -is [array]) { $a -join ',' } else { [string]$a }
    if ($s -match '^-[A-Za-z][A-Za-z0-9-]*:$') { $s = $s.Substring(0, $s.Length - 1) }
    $argv.Add($s)
  }
  & node $Module @argv
  exit $LASTEXITCODE
}
[Console]::Error.WriteLine('install-pre-commit-hook: refused - node not found in PATH or install-pre-commit-hook.mjs missing; nothing was changed. Install Node.js 22 or later (https://nodejs.org/) and re-run.')
exit 1
