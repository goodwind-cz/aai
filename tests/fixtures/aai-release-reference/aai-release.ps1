#!/usr/bin/env pwsh
# AAI release-cut launcher for /aai-release (PowerShell); the whole command lives in aai-release.mjs (RFC-0017 phase 5).
# Usage (run from anywhere inside the target repo):
#   ./.aai/scripts/aai-release.ps1 [-Version <v>] [-DryRun] [-Confirm] [-NoRemote] [-h]
# Flags, environment variables and exit codes: see .aai/SKILL_RELEASE.prompt.md (run with -h for the usage).
# No ErrorActionPreference Stop and no stderr redirect here: a refusal of the module keeps its exit code under Windows PowerShell 5.1.
param(
  [string]$Version = "",
  [switch]$DryRun,
  [switch]$Confirm,
  [switch]$Yes,
  [switch]$NoRemote,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$ExtraArgs
)

if ($MyInvocation.InvocationName -ne '.') {
  $module = Join-Path $PSScriptRoot 'aai-release.mjs'
  if (-not (Get-Command node -ErrorAction SilentlyContinue) -or -not (Test-Path -LiteralPath $module)) {
    [Console]::Error.WriteLine("REFUSED: missing-node " + [char]0x2014 + " Node.js 22 or later is required for /aai-release (https://nodejs.org/); nothing was changed.")
    exit 20
  }
  $nodeArgs = @($module, '--launcher', 'ps1', '--launcher-path', $PSCommandPath)
  if ($Version) { $nodeArgs += '--version', $Version }
  if ($DryRun) { $nodeArgs += '--dry-run' }
  if ($Confirm) { $nodeArgs += '--confirm' }
  if ($Yes) { $nodeArgs += '--yes' }
  if ($NoRemote) { $nodeArgs += '--no-remote' }
  if ($ExtraArgs) { $nodeArgs += $ExtraArgs }
  & node @nodeArgs
  exit $LASTEXITCODE
}
