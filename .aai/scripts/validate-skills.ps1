#!/usr/bin/env pwsh
# Skill validation launcher; the logic lives in validate-skills.mjs (RFC-0017 small-pairs slice).
# Usage: validate-skills.ps1 [-TargetRoot] <dir>
param([string]$TargetRoot = (Get-Location).Path)
$Module = Join-Path $PSScriptRoot 'validate-skills.mjs'
if ((Get-Command node -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $Module)) {
  & node $Module $TargetRoot
  exit $LASTEXITCODE
}
[Console]::Error.WriteLine('ERROR: validate-skills needs node (validate-skills.mjs unavailable)')
exit 1
