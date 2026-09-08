#!/usr/bin/env bash
#
# Cloud Agent install for the AAI repository.
#
# AAI is dependency-free by design: all tooling runs on the Node standard
# library (.mjs), POSIX bash (3.2-compatible test suites), and PowerShell 7
# mirrors. There is no package manifest or lockfile to restore, so this script
# only ensures the toolchain the workflow and its test matrix need is present.
#
# The default Cloud Agent image already ships node, git and gh. This adds
# PowerShell 7 plus PSScriptAnalyzer and Pester so the FULL cross-platform test
# matrix runs on the Linux VM — both the POSIX bash suites and the .ps1 quality
# gate (tests/skills/test-ps1-quality.sh), matching the CI "gate" job.
#
# Idempotent and non-interactive: every step is guarded so re-running (or
# running against a snapshot that already has the toolchain) is a no-op.
set -euo pipefail

log() { printf '\033[0;34m[install]\033[0m %s\n' "$*"; }

# --- 1. PowerShell 7 (pwsh) via the Microsoft apt repository ----------------
if command -v pwsh >/dev/null 2>&1; then
  log "pwsh already present: $(pwsh --version)"
else
  log "installing PowerShell 7 ..."
  sudo apt-get update -qq
  sudo apt-get install -y -qq wget apt-transport-https software-properties-common
  # shellcheck disable=SC1091
  . /etc/os-release
  tmpdeb="$(mktemp --suffix=.deb)"
  wget -q "https://packages.microsoft.com/config/ubuntu/${VERSION_ID}/packages-microsoft-prod.deb" -O "$tmpdeb"
  sudo dpkg -i "$tmpdeb"
  rm -f "$tmpdeb"
  sudo apt-get update -qq
  sudo apt-get install -y -qq powershell
  log "installed $(pwsh --version)"
fi

# --- 2. PSScriptAnalyzer + Pester (CurrentUser scope) -----------------------
# CI accepts any Pester with major version >= 5; the same guard is used here so
# an already-satisfied module set is left untouched.
log "ensuring PSScriptAnalyzer + Pester (CurrentUser) ..."
pwsh -NoProfile -Command '
  $ErrorActionPreference = "Stop"
  Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
  if (-not (Get-Module PSScriptAnalyzer -ListAvailable)) {
    Install-Module PSScriptAnalyzer -Scope CurrentUser -Force -Repository PSGallery
  }
  if (-not (Get-Module Pester -ListAvailable | Where-Object { $_.Version.Major -ge 5 })) {
    Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck -Repository PSGallery
  }
  $pssa = (Get-Module PSScriptAnalyzer -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version
  $pester = (Get-Module Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version
  Write-Host "PSScriptAnalyzer $pssa; Pester $pester"
'

# --- 3. Toolchain sanity report ---------------------------------------------
log "toolchain:"
log "  node    $(node --version 2>/dev/null || echo MISSING)"
log "  bash    $(bash --version 2>/dev/null | head -1 || echo MISSING)"
log "  git     $(git --version 2>/dev/null || echo MISSING)"
if command -v gh >/dev/null 2>&1; then
  log "  gh      $(gh --version 2>/dev/null | head -1)"
else
  log "  gh      not present (optional; only needed for the /aai-pr ceremony)"
fi
log "  pwsh    $(pwsh --version 2>/dev/null || echo MISSING)"
if command -v python3 >/dev/null 2>&1; then
  log "  python3 $(python3 --version 2>/dev/null) (PyYAML round-trip checks in the state suite)"
fi

log "AAI Cloud Agent environment ready."
