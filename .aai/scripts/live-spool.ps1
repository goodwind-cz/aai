#!/usr/bin/env pwsh
# live-spool.ps1 - launcher for live-spool.mjs, the statusline/hook tap writer
# (SPEC-0114). All logic lives in the Node module. Always exits 0. Stdin is read
# as raw bytes and handed to Node untouched (Windows PowerShell 5.1 does not
# forward its stdin to `& node`). Without Node or the module it prints the
# passthrough for statusline only.
param([Parameter(Position = 0)][string]$Kind = 'statusline')
$Module = Join-Path $PSScriptRoot 'live-spool.mjs'
$Payload = New-Object System.IO.MemoryStream
if ([Console]::IsInputRedirected) { [Console]::OpenStandardInput().CopyTo($Payload) }
$Ran = $false
$Node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($Node) {
  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo $Node.Source, ('"' + $Module + '" "' + $Kind + '"')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $null = $p.StandardError.ReadToEndAsync()
    $Payload.WriteTo($p.StandardInput.BaseStream)
    $p.StandardInput.Close()
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    if ($p.ExitCode -eq 0) { $Ran = $true; [Console]::Out.Write($out) }
  } catch { $Ran = $false }
}
if (-not $Ran -and $Kind -eq 'statusline') { Write-Output '(aai-live tap active)' }
exit 0
