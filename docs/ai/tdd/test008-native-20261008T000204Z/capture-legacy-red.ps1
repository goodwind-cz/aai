$ErrorActionPreference = 'Stop'
$PSNativeCommandArgumentPassing = 'Legacy'
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
$result = Invoke-PreflightNode -NodeArgs @('-e', 'console.log(JSON.stringify({clone_diagnostic:"full-boundary"}));console.error("genuine-native-failure");process.exit(7)')
Write-Host ('CAPTURE_LEGACY ' + (@{ Output=($result.Output -join "`n"); ExitCode=$result.ExitCode; Preference=$ErrorActionPreference; ArgumentMode=$PSNativeCommandArgumentPassing } | ConvertTo-Json -Compress))
if ($result.ExitCode -ne 7) { throw ('assertion: expected exit7, observed' + $result.ExitCode) }
