# Shared Node matrix: POSIX executable stubs and native Windows provider shims.
# Windows proof requires both Windows PowerShell 5.1 and pwsh 7.
Describe 'PR readiness process boundary' {
    BeforeAll {
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
        $script:Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $script:Native = $env:OS -eq 'Windows_NT'
        $script:OldScratch = $env:AAI_PREFLIGHT_SCRATCH
        $script:Scratch = Join-Path ([IO.Path]::GetTempPath()) ('aai-pr-preflight-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:Scratch | Out-Null
        $source = [IO.File]::ReadAllText((Join-Path $script:Root 'tests/skills/test-aai-pr-preflight.sh'))
        $matrix = [regex]::Match($source, "(?s)AAI_PREFLIGHT_MATRIX'\r?\n(.*?)\r?\nAAI_PREFLIGHT_MATRIX").Groups[1].Value
        $script:Matrix = Join-Path $script:Scratch 'matrix.cjs'
        [IO.File]::WriteAllText($script:Matrix, $matrix, (New-Object Text.UTF8Encoding($false)))
        $env:AAI_PREFLIGHT_SCRATCH = $script:Scratch
        if ($script:Native) {
            $script:Shim = Join-Path $script:Scratch 'client.exe'
            $compiler = Join-Path $script:Scratch 'compile.ps1'
            # Build with .NET Framework even when the caller is pwsh 7.
            $compile = @'
$code = @"
using System;
using System.IO;
using System.Diagnostics;
class Client {
 static string Quote(string s) {
  return "\"" + s.Replace("\"", "\\\"") + "\"";
 }
 static int Main(string[] args) {
  var name = Path.GetFileNameWithoutExtension(Process.GetCurrentProcess().MainModule.FileName);
  if (name == "python") {
   if (args.Length < 2 || args[0] != "-IBm" || args[1] != "azure.cli") return 96;
   name = "az"; var forwarded = new string[args.Length - 2]; Array.Copy(args, 2, forwarded, 0, forwarded.Length); args = forwarded;
  }
  var start = new ProcessStartInfo(Environment.GetEnvironmentVariable("AAI_NATIVE_NODE"));
  start.UseShellExecute = false;
  start.RedirectStandardInput = true;
  start.Arguments = Quote(Environment.GetEnvironmentVariable("AAI_NATIVE_STUB")) + " " + Quote(name);
  foreach (var arg in args) start.Arguments += " " + Quote(arg);
  using (var child = Process.Start(start)) {
   child.StandardInput.Close(); child.WaitForExit(); return child.ExitCode;
  }
 }
}
"@
Add-Type -TypeDefinition $code -OutputAssembly $args[0] -OutputType ConsoleApplication
'@
            [IO.File]::WriteAllText($compiler,$compile,(New-Object Text.UTF8Encoding($false)))
            & powershell -NoProfile -File $compiler $script:Shim
            if ($LASTEXITCODE -ne 0) { throw 'native shim compilation failed' }
            $script:OldShim = $env:AAI_PREFLIGHT_NATIVE_SHIM
            $env:AAI_PREFLIGHT_NATIVE_SHIM = $script:Shim
        }
    }
    It 'prints captured JSON and preserves nonzero native status under Stop' {
        $oldPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Stop'
            $result = Invoke-PreflightNode -NodeArgs @('-e', 'console.log(JSON.stringify({clone_diagnostic:"full-boundary"}));console.error("genuine-native-failure");process.exit(7)')
            $result.ExitCode | Should -Be 7
            ($result.Output -join "`n") | Should -Match '"clone_diagnostic":"full-boundary"'
            ($result.Output -join "`n") | Should -Match 'genuine-native-failure'
            $ErrorActionPreference | Should -Be 'Stop'
            Write-Host 'INFO: TEST008_NATIVE_CAPTURE diagnostic_visible=true nonzero_preserved=true preference_restored=true'
        } finally {
            $ErrorActionPreference = $oldPreference
        }
    }
    It 'runs the eight provider/identity/refusal/timeout matrix arms' {
        foreach ($id in @('001','002','003','004','005','006','007','008')) {
            $result = Invoke-PreflightNode -NodeArgs @($script:Matrix, $script:Root, $id)
            $output = $result.Output
            $rc = $result.ExitCode
            Write-Host ($output -join "`n")
            $rc | Should -Be 0
            ($output -join "`n") | Should -Match ('PASS: TEST-' + $id)
        }
        if (-not $script:Native) {
            # CI's Linux Pester job must also execute the canonical Bash entry
            # without its own scratch override masking the portable default.
            $oldScratch = $env:AAI_PREFLIGHT_SCRATCH
            $env:AAI_PREFLIGHT_SCRATCH = $null
            Push-Location -LiteralPath $script:Root
            try {
                $output = & bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-preflight.sh 2>&1
                $rc = $LASTEXITCODE
                Write-Host ($output -join "`n")
                $rc | Should -Be 0
                ($output -join "`n") | Should -Match 'scratch_override=unset platform=(linux|darwin)'
                foreach ($id in @('001','002','003','004','005','006','007','008')) {
                    ($output -join "`n") | Should -Match ('PASS: TEST-' + $id)
                }
            } finally {
                Pop-Location
                $env:AAI_PREFLIGHT_SCRATCH = $oldScratch
            }
        }
    }
    AfterAll {
        if ($script:Native) {
            $env:AAI_PREFLIGHT_NATIVE_SHIM = $script:OldShim
        }
        $env:AAI_PREFLIGHT_SCRATCH = $script:OldScratch
        Remove-Item -LiteralPath $script:Scratch -Recurse -Force
    }
}
