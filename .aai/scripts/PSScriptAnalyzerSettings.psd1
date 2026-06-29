@{
    # PSScriptAnalyzer settings for the AAI vendored .ps1 scripts.
    #
    # These are CLI entrypoints (not modules), so a few default rules are noise:
    # - PSAvoidUsingWriteHost: Write-Host IS the intended user-facing output here.
    # - PSUseApprovedVerbs / PSUseSingularNouns: internal helper functions in
    #   standalone scripts; the "unapproved verb" warning only matters on module
    #   import, which never happens for these.
    # - PSUseShouldProcessForStateChangingFunctions: these scripts are themselves
    #   the state-changing command; -WhatIf is provided at the script level
    #   (e.g. aai-update's -DryRun), not per internal function.
    #
    # The test gate (tests/skills/test-ps1-quality.sh) runs this at Error severity
    # so it fails CI/pre-commit only on real defects, while `--warn` surfaces the
    # rest for cleanup. Cross-version (Windows PowerShell 5.1) syntax is checked
    # separately via PSUseCompatibleSyntax in the same gate.
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSUseApprovedVerbs',
        'PSUseSingularNouns',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSAvoidUsingEmptyCatchBlock'
    )
    Rules = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            # Windows PowerShell 5.1 is the field environment that broke; 7.0 is
            # the documented pwsh floor. The gate fails if either can't parse.
            TargetVersions = @('5.1', '7.0')
        }
    }
}
