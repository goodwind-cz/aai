#!/usr/bin/env pwsh
# AAI release-cut launcher for /aai-release (PowerShell); the whole command, the flag grammar included, lives in aai-release.mjs (RFC-0017 phase 5).
# Usage (run from anywhere inside the target repo): ./.aai/scripts/aai-release.ps1 [-Version <v>] [-DryRun] [-Confirm] [-NoRemote] [-h] (the --long flags work too)
# Flags, environment variables and exit codes: see .aai/SKILL_RELEASE.prompt.md (run with -h for the usage).
# No ErrorActionPreference and no stderr redirect here: a refusal of the module keeps its exit code under Windows PowerShell 5.1.
if ($MyInvocation.InvocationName -eq '.') { return }
$Module = Join-Path $PSScriptRoot 'aai-release.mjs'
if (-not (Get-Command node -ErrorAction SilentlyContinue) -or -not (Test-Path -LiteralPath $Module)) {
  [Console]::Error.WriteLine('REFUSED: missing-node ' + [char]0x2014 + ' Node.js 22 or later is required for /aai-release (https://nodejs.org/); nothing was changed.')
  exit 20
}
$argv = New-Object System.Collections.Generic.List[string]
foreach ($a in $args) {
  if ($a -is [bool]) { if (-not $a -and $argv.Count -gt 0) { $argv.RemoveAt($argv.Count - 1) }; continue }
  $s = if ($a -is [array]) { $a -join ',' } else { [string]$a }
  if ($s -match '^-[A-Za-z][A-Za-z0-9-]*:$') { $s = $s.Substring(0, $s.Length - 1) }
  $argv.Add($s)
}
& node $Module --launcher ps1 --launcher-path $PSCommandPath @argv
exit $LASTEXITCODE
