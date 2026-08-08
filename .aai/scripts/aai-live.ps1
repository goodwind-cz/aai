#!/usr/bin/env pwsh
<#
.SYNOPSIS
  aai-live.ps1 - generate the live-status dashboard, then open it
  (SPEC-0114-spec-live-status-dashboard). Windows twin of aai-live.sh.

.DESCRIPTION
  No server, no port: opens the static HTML file directly via Start-Process
  (the Windows platform opener). All arguments pass through to
  generate-live-status.mjs.
#>
[CmdletBinding()]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$RestArgs
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $ScriptDir '..\..')
$Gen = Join-Path $ScriptDir 'generate-live-status.mjs'

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Write-Error 'aai-live: refused - node not found in PATH'
  exit 1
}
if (-not (Test-Path $Gen)) {
  Write-Error "aai-live: refused - generator not found: $Gen"
  exit 1
}

if ($null -eq $RestArgs) { $RestArgs = @() }
$DataOnly = $RestArgs -contains '--data-only'
$Watch = $RestArgs -contains '--watch'
$OutputHtml = Join-Path $RepoRoot 'docs/ai/live-status.html'

Set-Location $RepoRoot

if ($Watch) {
  # Warm one-shot generate so there is actually something to open
  # immediately (BLOCKING-2, code review CHANGE-0127).
  #
  # The warm-up forwards the invocation's OWN args (minus -watch itself, so
  # it stays one-shot) instead of running the generator bare. Two
  # regressions this closes (NNB-1/NNB-2, code review 102429Z, introduced by
  # the prior BLOCKING-2 remediation): a bare warm-up always wrote the HTML
  # even when -data-only asked to suppress it, and it ignored -output (plus
  # -home/-interval/-cache/-spool-dir), so under
  # `-watch -output custom/page.html` Start-Process opened a frozen
  # snapshot at the DEFAULT path while the watch loop rewrote
  # custom/page.html — a page that looks live and is permanently stale.
  $WarmupArgs = @($RestArgs | Where-Object { $_ -ne '--watch' })
  & node $Gen @WarmupArgs | Out-Null
  if (-not $DataOnly) {
    $OpenTarget = $OutputHtml
    for ($i = 0; $i -lt $RestArgs.Count; $i++) {
      if ($RestArgs[$i] -eq '--output' -and ($i + 1) -lt $RestArgs.Count) {
        $OpenTarget = $RestArgs[$i + 1]
        if (-not [System.IO.Path]::IsPathRooted($OpenTarget)) {
          $OpenTarget = Join-Path $RepoRoot $OpenTarget
        }
      }
    }
    Start-Process $OpenTarget -ErrorAction SilentlyContinue
  }
  & node $Gen @RestArgs
  exit $LASTEXITCODE
}

& node $Gen @RestArgs
$rc = $LASTEXITCODE
if ($rc -eq 0 -and -not $DataOnly) {
  Start-Process $OutputHtml -ErrorAction SilentlyContinue
}
exit $rc
