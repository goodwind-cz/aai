$ErrorActionPreference='Stop'
$PSNativeCommandArgumentPassing='Legacy'
        function Invoke-PreflightNode {
            param([string[]]$NodeArgs)
            # PS5.1 Stop must not hide captured JSON before the exit assertion.
            $oldPreference = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Continue'
                $output = & node @NodeArgs 2>&1
                $rc = $LASTEXITCODE
            } finally {
                $ErrorActionPreference = $oldPreference
            }
            return @{ Output = @($output); ExitCode = $rc }
        }
$result=Invoke-PreflightNode -NodeArgs @('/private/tmp/aai-pr434-remediation-scratch/capture-control.cjs')
Write-Host ('CAPTURE_LEGACY ' + (@{Output=($result.Output -join "`n");ExitCode=$result.ExitCode;Preference=[string]$ErrorActionPreference;ArgumentMode=[string]$PSNativeCommandArgumentPassing} | ConvertTo-Json -Compress))
if($result.ExitCode -ne 7 -or ($result.Output -join "`n") -notmatch '"clone_diagnostic":"full-boundary"' -or ($result.Output -join "`n") -notmatch 'genuine-native-failure' -or $ErrorActionPreference -ne 'Stop'){throw 'capture contract failed'}
