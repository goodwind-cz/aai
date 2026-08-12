# pester-native-capture.ps1 — shared OS-handle-level native-process capture
# (CHANGE-0134 remediation, first real-Windows-PowerShell-5.1 Pester run: PR #248 run
# 31638479811, 5 of the 10 failures this run surfaced).
#
# WHY THIS EXISTS: an in-process `& pwsh ... 2>$file` (or `2>$null`) redirect
# on a native/child pwsh call wraps every line the child writes to stderr as
# an ErrorRecord (`RemoteException: <text>`). Under Windows PowerShell 5.1,
# with the CALLING scope's $ErrorActionPreference at 'Stop' — exactly what
# ps1-quality.yml's "Full Pester suite discovery" step sets before
# Invoke-Pester — that ErrorRecord is promoted to a TERMINATING error the
# instant the child writes ANY stderr, even on a clean exit 0. The test then
# fails as a caught exception ("RemoteException: <child's stderr text>")
# instead of exercising its actual assertion. This is the same class of
# defect `.aai/scripts/aai-release.ps1`'s Invoke-NativeChecked exists to
# guard against in PRODUCTION code (SPEC-0067) — this file is the TEST-HARNESS
# equivalent, needed because these tests deliberately spawn a real child pwsh
# and must read its real stdout/stderr/exit code without going through
# PowerShell's error-stream/EAP machinery at all.
#
# Capturing at the OS-handle level via Start-Process
# -RedirectStandardOutput/-RedirectStandardError sidesteps that machinery
# entirely — the same technique aai-run-tests.ps1's Start-WslProbeProcess /
# Start-GitBashProcess already use for the sibling 5.1 ExitCode-null footgun,
# and ps1-quality.yml's own Invoke-WrapperSmokeArm uses for this exact
# reason (see that file's step header comment).
#
# Arguments are individually quoted into ONE -ArgumentList string before the
# call: Start-Process -ArgumentList silently mis-splits an ARRAY whose
# elements contain embedded spaces (each element is naively space-joined,
# not quoted) — proven while building this fix: a `-Command` script body or
# any argument containing a space arrives at the child as several separate,
# wrongly-split words. Passing one pre-quoted string sidesteps that too.
#
# Usage (each *.Tests.ps1 file, dot-sourced once, anywhere a BeforeAll can
# reach it — this helper has no discovery-time skip dependency, unlike
# pester-host-skip.ps1):
#   . (Join-Path $PSScriptRoot 'lib/pester-native-capture.ps1')
#   $r = Invoke-NativeCaptured -Exe 'pwsh' -Arguments @('-NoProfile', '-File', $path, '-Force')
#   $r.Code / $r.Out / $r.Err

function Invoke-NativeCaptured {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Exe,
    [Parameter(Mandatory)][string[]]$Arguments
  )
  $outFile = [System.IO.Path]::GetTempFileName()
  $errFile = [System.IO.Path]::GetTempFileName()
  try {
    $argString = ($Arguments | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' '
    $proc = Start-Process -FilePath $Exe -ArgumentList $argString -NoNewWindow -PassThru -Wait `
      -RedirectStandardOutput $outFile -RedirectStandardError $errFile -ErrorAction Stop
    # 5.1 ExitCode-null footgun (same cause documented in
    # aai-run-tests.ps1's Start-WslProbeProcess/Start-GitBashProcess): touch
    # .Handle so a real exit code is readable on every PowerShell version,
    # even though -Wait already blocked until the process exited.
    $null = $proc.Handle
    [pscustomobject]@{
      Out  = "$(Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue)"
      Err  = "$(Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue)"
      Code = $proc.ExitCode
    }
  } finally {
    Remove-Item -LiteralPath $outFile, $errFile -ErrorAction SilentlyContinue
  }
}
