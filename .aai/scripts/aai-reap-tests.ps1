# Test-process reaper launcher; the logic and the safety contract live in aai-reap-tests.mjs (RFC-0017 phase 5).
# Usage: powershell -NoProfile -File .aai/scripts/aai-reap-tests.ps1
$Module = Join-Path $PSScriptRoot 'aai-reap-tests.mjs'
if ((Get-Command node -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $Module)) {
  & node $Module
  exit $LASTEXITCODE
}
[Console]::Error.WriteLine('aai-reap-tests: refused - node not found in PATH or aai-reap-tests.mjs missing; nothing was reaped')
exit 1
