# Launcher: the publish logic lives in cloudflare-share.mjs (RFC-0017 phase 5).
# Usage: powershell -NoProfile -File .aai/scripts/cloudflare-share.ps1 <document.md>
[CmdletBinding()] param([Parameter(Position = 0)][string]$DocumentPath)
$Module = Join-Path $PSScriptRoot 'cloudflare-share.mjs'
if ((Get-Command node -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $Module)) {
  $nodeArgs = @($Module); if ($DocumentPath) { $nodeArgs += $DocumentPath }
  & node @nodeArgs
  exit $LASTEXITCODE
}
[Console]::Error.WriteLine('cloudflare-share: refused - node not found in PATH or cloudflare-share.mjs missing; nothing was published. Install Node.js 22 or later (https://nodejs.org/) and re-run.')
exit 1
