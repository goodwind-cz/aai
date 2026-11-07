# RETIRED (RFC-0017 phase 5, pre-commit-checks-ps1-retire): a deprecation launcher for one release; the next release deletes it.
[Console]::Error.WriteLine('pre-commit-checks.ps1: retired - the PowerShell pre-commit checks are retired (RFC-0017 phase 5) and will be deleted in the next release; replacement: bash .aai/scripts/pre-commit-checks.sh (the installed hooks already run it); nothing was checked')
exit 1
