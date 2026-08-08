#!/usr/bin/env pwsh
<#
.SYNOPSIS
  live-spool.ps1 - statusline/hook tap writer (SPEC-DRAFT-spec-live-status-dashboard).
  Windows twin of live-spool.sh.

.DESCRIPTION
  Reads ONE JSON payload from stdin, projects a WHITELIST of fields, appends
  one line to docs/ai/live/<kind>.jsonl, caps the file by line count, and
  ALWAYS exits 0 - a statusline or hook writer must never disturb the
  harness it is tapping. The repo root is resolved from this script's own
  location. AAI_LIVE_SPOOL_DIR overrides the spool directory.
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [string]$Kind = 'statusline'
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $ScriptDir '..\..')
$SpoolDir = if ($env:AAI_LIVE_SPOOL_DIR) { $env:AAI_LIVE_SPOOL_DIR } else { Join-Path $RepoRoot 'docs/ai/live' }
$MaxLines = 500

try {
  $Payload = [Console]::In.ReadToEnd()
  if (-not [string]::IsNullOrWhiteSpace($Payload)) {
    $Obj = $null
    try { $Obj = $Payload | ConvertFrom-Json -ErrorAction Stop } catch { $Obj = $null }

    if ($Obj) {
      $Common = @('session_id', 'cwd', 'model')
      $StatuslineFields = @('rate_limits', 'cost')
      $HookFields = @('hook_event_name')
      $Allow = if ($Kind -eq 'hooks') { $Common + $HookFields } else { $Common + $StatuslineFields }

      $Out = [ordered]@{ ts = (Get-Date).ToUniversalTime().ToString('o') }
      foreach ($key in $Allow) {
        if ($Obj.PSObject.Properties.Name -contains $key) {
          $Out[$key] = $Obj.$key
        }
      }

      New-Item -ItemType Directory -Force -Path $SpoolDir -ErrorAction SilentlyContinue | Out-Null
      $File = Join-Path $SpoolDir "$Kind.jsonl"
      $Line = $Out | ConvertTo-Json -Compress -Depth 10
      Add-Content -Path $File -Value $Line -ErrorAction SilentlyContinue

      if (Test-Path $File) {
        $Lines = @(Get-Content $File -ErrorAction SilentlyContinue)
        if ($Lines.Count -gt $MaxLines) {
          $Start = $Lines.Count - $MaxLines
          $Lines[$Start..($Lines.Count - 1)] | Set-Content $File -ErrorAction SilentlyContinue
        }
      }
    }
  }

  if ($Kind -eq 'statusline') {
    # Minimal stdout passthrough so a statusLine command never renders blank.
    Write-Output '(aai-live tap active)'
  }
} catch {
  # ALWAYS exit 0 - a statusline/hook writer must never disturb the harness.
}

exit 0
