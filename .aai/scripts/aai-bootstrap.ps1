# Project bootstrap launcher; detection, rendering and write policy live in aai-bootstrap.mjs (RFC-0017 phase 5).
# Usage: powershell -NoProfile -File .aai/scripts/aai-bootstrap.ps1 [target-root] [--dry-run] [--force] [--with-claude-hooks]
$Module = Join-Path $PSScriptRoot 'aai-bootstrap.mjs'
if ((Get-Command node -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $Module)) {
  & node $Module @args
  exit $LASTEXITCODE
}
[Console]::Error.WriteLine('aai-bootstrap: refused - node not found in PATH or aai-bootstrap.mjs missing; nothing was written. Install Node.js 22 or later (https://nodejs.org/) and re-run.')
exit 1
