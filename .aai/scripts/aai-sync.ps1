param(
  [Parameter(Mandatory=$true)]
  [string]$TargetRoot
)

$ErrorActionPreference = "Stop"

# Push AAI layer FROM this repository INTO a target project.
#
# Usage (run from anywhere, script finds its own repo root):
#   .\.aai\scripts\aai-sync.ps1 -TargetRoot ..\maty-ai
#
# Example:
#   .\.aai\scripts\aai-sync.ps1 -TargetRoot z:\AI\maty-ai

function Copy-Replace {
  param(
    [Parameter(Mandatory=$true)][string]$Src,
    [Parameter(Mandatory=$true)][string]$Dst
  )
  # Git is the backup — no .bak files needed.
  if (Test-Path $Dst) { Remove-Item $Dst -Recurse -Force }
  Copy-Item $Src $Dst -Recurse -Force
}

# Resolve source = this repository's root (grandparent of the .aai/scripts/ folder)
$SrcRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

if (!(Test-Path (Join-Path $SrcRoot ".aai"))) {
  throw "Source missing .aai/ directory: $SrcRoot"
}

if (!(Test-Path $TargetRoot)) {
  throw "Target directory does not exist: $TargetRoot"
}

$TargetRoot = (Resolve-Path $TargetRoot).Path

Write-Host "Syncing AAI from: $SrcRoot"
Write-Host "Target project:     $TargetRoot"

# Target directories (AAI layer only)
foreach ($d in @(".aai/workflow",".aai/roles",".aai/templates",".aai/scripts",".aai/system",".aai/knowledge",".claude/skills",".codex/skills",".codex/skills.local",".gemini/skills",".gemini/skills.local",".github","docs/knowledge","docs/ai")) {
  New-Item -ItemType Directory -Force -Path (Join-Path $TargetRoot $d) | Out-Null
}

# -- Legacy cleanup: remove old-layout paths that moved into .aai/ -----------
$legacyCleaned = $false

# Old prompt / subagent directory (was ai/)
$oldAi = Join-Path $TargetRoot "ai"
if (Test-Path $oldAi) {
  Remove-Item $oldAi -Recurse -Force
  Write-Host "  MIGRATE removed legacy: ai/"
  $legacyCleaned = $true
}

# Old scripts directory (was scripts/) — only remove AAI-owned scripts, keep project scripts
$oldScripts = Join-Path $TargetRoot "scripts"
if (Test-Path $oldScripts) {
  # Remove scripts that now live in .aai/scripts/ (current names)
  Get-ChildItem -Path (Join-Path $SrcRoot ".aai/scripts") -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $oldFile = Join-Path $oldScripts $_.Name
    if (Test-Path $oldFile) {
      Remove-Item $oldFile -Force
      Write-Host "  MIGRATE removed legacy: scripts/$($_.Name) -> now in .aai/scripts/"
      $legacyCleaned = $true
    }
  }
  # Remove old ai-os-* named scripts (renamed to aai-*)
  Get-ChildItem -Path $oldScripts -File -Filter "ai-os-*" -Force -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-Item $_.FullName -Force
    Write-Host "  MIGRATE removed legacy: scripts/$($_.Name) (old ai-os-* name)"
    $legacyCleaned = $true
  }
  # Remove the directory only if it's now empty
  if ((Get-ChildItem -Path $oldScripts -Force -ErrorAction SilentlyContinue).Count -eq 0) {
    Remove-Item $oldScripts -Force
    Write-Host "  MIGRATE removed empty: scripts/"
  }
}

# Root files that moved into .aai/
foreach ($f in @("AGENTS.md","PLAYBOOK.md")) {
  $oldFile = Join-Path $TargetRoot $f
  if (Test-Path $oldFile) {
    Remove-Item $oldFile -Force
    Write-Host "  MIGRATE removed legacy root: $f"
    $legacyCleaned = $true
  }
}

# docs/ subdirs whose content moved into .aai/
foreach ($d in @("docs/workflow","docs/roles","docs/templates")) {
  $dirPath = Join-Path $TargetRoot $d
  if (Test-Path $dirPath) {
    $entries = Get-ChildItem -Path $dirPath -Force | Where-Object { $_.Name -ne ".gitkeep" }
    if ($entries.Count -gt 0) {
      Remove-Item $dirPath -Recurse -Force
      New-Item -ItemType Directory -Force -Path $dirPath | Out-Null
      New-Item -ItemType File -Force -Path (Join-Path $dirPath ".gitkeep") | Out-Null
      Write-Host "  MIGRATE cleaned legacy dir: $d/ (kept .gitkeep)"
      $legacyCleaned = $true
    }
  }
}

# System docs that moved from docs/ai/ to .aai/system/
foreach ($f in @("AUTONOMOUS_LOOP.md","SUPERPOWERS_INTEGRATION.md","DYNAMIC_SKILLS.md","PRICING.yaml","AAI_PIN.md","LOCKS.md")) {
  $oldFile = Join-Path $TargetRoot "docs/ai/$f"
  if (Test-Path $oldFile) {
    Remove-Item $oldFile -Force
    Write-Host "  MIGRATE removed legacy: docs/ai/$f -> now in .aai/system/"
    $legacyCleaned = $true
  }
}

# PATTERNS_UNIVERSAL moved from docs/knowledge/ to .aai/knowledge/
$oldPU = Join-Path $TargetRoot "docs/knowledge/PATTERNS_UNIVERSAL.md"
if (Test-Path $oldPU) {
  Remove-Item $oldPU -Force
  Write-Host "  MIGRATE removed legacy: docs/knowledge/PATTERNS_UNIVERSAL.md -> now in .aai/knowledge/"
  $legacyCleaned = $true
}

if ($legacyCleaned) {
  Write-Host "  Legacy paths migrated to .aai/ structure."
}

# -- Copy AAI canonical layer (.aai/ is the single source of truth) -------
# Entry-by-entry so we can merge scripts/ and preserve target-only scripts.
New-Item -ItemType Directory -Force -Path (Join-Path $TargetRoot ".aai") | Out-Null

# Top-level files and non-scripts directories: overwrite from source
# Skip scripts/ (merged separately) and cache/ (runtime artifact, not synced)
Get-ChildItem -Path (Join-Path $SrcRoot ".aai") -Force | Where-Object { $_.Name -notin @("scripts","cache") } | ForEach-Object {
  Copy-Replace $_.FullName (Join-Path $TargetRoot ".aai" $_.Name)
}

# Clean stale top-level items in target .aai/ that no longer exist in source (except scripts/, cache/)
Get-ChildItem -Path (Join-Path $TargetRoot ".aai") -Force | Where-Object { $_.Name -notin @("scripts","cache") } | ForEach-Object {
  if (!(Test-Path (Join-Path $SrcRoot ".aai" $_.Name))) {
    Remove-Item $_.FullName -Recurse -Force
    Write-Host "  CLEAN removed stale: .aai/$($_.Name)"
  }
}

# scripts/: file-by-file merge — overwrite source scripts, preserve target-only
$srcScripts = Join-Path $SrcRoot ".aai/scripts"
$dstScripts = Join-Path $TargetRoot ".aai/scripts"
New-Item -ItemType Directory -Force -Path $dstScripts | Out-Null
Get-ChildItem -Path $srcScripts -Force | ForEach-Object {
  Copy-Replace $_.FullName (Join-Path $dstScripts $_.Name)
}
Get-ChildItem -Path $dstScripts -Force | ForEach-Object {
  if (!(Test-Path (Join-Path $srcScripts $_.Name))) {
    Write-Host "  PRESERVE target-only script: .aai/scripts/$($_.Name)"
  }
}

# Claude Code skills (session helpers):
# copy template skills entry-by-entry and preserve target-only local skills.
$claudeSkills = Join-Path $SrcRoot ".claude/skills"
if (Test-Path $claudeSkills) {
  $targetClaudeSkills = Join-Path $TargetRoot ".claude/skills"
  New-Item -ItemType Directory -Force -Path $targetClaudeSkills | Out-Null
  Get-ChildItem -Path $claudeSkills -Force | ForEach-Object {
    $dstEntry = Join-Path $targetClaudeSkills $_.Name
    Copy-Replace $_.FullName $dstEntry
  }
  Write-Host "  PRESERVE target-only skills under: $targetClaudeSkills"
}

# docs/knowledge: file-by-file copy; skip files that no longer contain the
# AAI-TEMPLATE sentinel (meaning the target project has filled them with real content).
$know = Join-Path $SrcRoot "docs/knowledge"
if (Test-Path $know) {
  New-Item -ItemType Directory -Force -Path (Join-Path $TargetRoot "docs/knowledge") | Out-Null
  Get-ChildItem -Path $know -File | ForEach-Object {
    $srcFile = $_.FullName
    $dstFile = Join-Path $TargetRoot "docs/knowledge" $_.Name
    $isTemplate = $true
    if (Test-Path $dstFile) {
      $content = Get-Content $dstFile -Raw -ErrorAction SilentlyContinue
      $isTemplate = $content -match "AAI-TEMPLATE"
    }
    if ($isTemplate) {
      Copy-Item $srcFile $dstFile -Force
    } else {
      Write-Host "  SKIP (project-owned, sentinel removed): $dstFile"
    }
  }
}

# docs/ai: preserve existing runtime data — system docs are now in .aai/system/
if (Test-Path (Join-Path $TargetRoot "docs/ai")) {
  Write-Host "  PRESERVE docs/ai/ runtime data (STATE.yaml, *.jsonl, decisions.jsonl, reports/)"
}

# Root canonical shims (AGENTS.md and PLAYBOOK.md are now inside .aai/)
# README.md is synced as README_AAI.md to avoid overwriting the target project's own README.
foreach ($f in @("CLAUDE.md","CODEX.md","GEMINI.md","SKILLS.md")) {
  $srcFile = Join-Path $SrcRoot $f
  if (Test-Path $srcFile) {
    Copy-Replace $srcFile (Join-Path $TargetRoot $f)
  }
}
$srcReadme = Join-Path $SrcRoot "README.md"
if (Test-Path $srcReadme) {
  Copy-Replace $srcReadme (Join-Path $TargetRoot "README_AAI.md")
}

# Copilot shim
$copilot = Join-Path $SrcRoot ".github/copilot-instructions.md"
if (Test-Path $copilot) {
  Copy-Replace $copilot (Join-Path $TargetRoot ".github/copilot-instructions.md")
}

# Codex skill index
$codexSkills = Join-Path $SrcRoot ".codex/skills"
if (Test-Path $codexSkills) {
  Copy-Replace $codexSkills (Join-Path $TargetRoot ".codex/skills")
}
if (Test-Path (Join-Path $TargetRoot ".codex/skills.local")) {
  Write-Host "  PRESERVE local Codex dynamic index: $(Join-Path $TargetRoot ".codex/skills.local")"
}

# Gemini skill index
$geminiSkills = Join-Path $SrcRoot ".gemini/skills"
if (Test-Path $geminiSkills) {
  Copy-Replace $geminiSkills (Join-Path $TargetRoot ".gemini/skills")
}
if (Test-Path (Join-Path $TargetRoot ".gemini/skills.local")) {
  Write-Host "  PRESERVE local Gemini dynamic index: $(Join-Path $TargetRoot ".gemini/skills.local")"
}

# IMPORTANT: Do NOT sync project-specific docs:
# - docs/requirements/**, docs/specs/**, docs/decisions/**, docs/releases/**, docs/issues/**
# These are owned by the target project.

# Ensure .aai/ is gitignored in target (it's vendored, not committed)
$gitignorePath = Join-Path $TargetRoot ".gitignore"
$needsGitignore = $true
if (Test-Path $gitignorePath) {
  $content = Get-Content $gitignorePath -Raw -ErrorAction SilentlyContinue
  if ($content -match '(?m)^\.aai/') { $needsGitignore = $false }
}
if ($needsGitignore) {
  Add-Content -Path $gitignorePath -Value "`n# AAI infrastructure (vendored, not committed)`n.aai/"
  Write-Host "  Added .aai/ to $gitignorePath"
}

# Ensure .cloudflare-publish* and .wrangler/ are gitignored (aai-share temp dirs)
$giContent = if (Test-Path $gitignorePath) { Get-Content $gitignorePath -Raw -ErrorAction SilentlyContinue } else { "" }
foreach ($pattern in @('.cloudflare-publish*', '.wrangler/')) {
  if ($giContent -notmatch [regex]::Escape($pattern)) {
    Add-Content -Path $gitignorePath -Value "`n$pattern"
    Write-Host "  Added $pattern to $gitignorePath"
  }
}

# Ensure expert subagent cache is gitignored (runtime artifact, not committed)
$giContent = if (Test-Path $gitignorePath) { Get-Content $gitignorePath -Raw -ErrorAction SilentlyContinue } else { "" }
if ($giContent -notmatch [regex]::Escape('.aai/cache/')) {
  Add-Content -Path $gitignorePath -Value "`n# Expert subagent cache (fetched on-demand from VoltAgent registry)`n.aai/cache/"
  Write-Host "  Added .aai/cache/ to $gitignorePath"
}

# Ensure ephemeral validation reports/screenshots are gitignored
$giContent = if (Test-Path $gitignorePath) { Get-Content $gitignorePath -Raw -ErrorAction SilentlyContinue } else { "" }
if ($giContent -notmatch [regex]::Escape('docs/ai/reports/validation-')) {
  $reportBlock = @(
    ""
    "# Ephemeral validation reports (reproducible via /aai-validate-report)"
    "docs/ai/reports/validation-*.md"
    "docs/ai/reports/LATEST.md"
    "docs/ai/reports/screenshots/"
    "docs/ai/reports/MIGRATION_REPORT_*.md"
  ) -join "`n"
  Add-Content -Path $gitignorePath -Value $reportBlock
  Write-Host "  Added validation report patterns to $gitignorePath"
}

# Pin info
$templateSha = "UNKNOWN"
try { $templateSha = (git -C $SrcRoot rev-parse HEAD) 2>$null } catch {}

$templateVersion = "UNKNOWN"
$versionFile = Join-Path $SrcRoot "docs/ai/AAI_VERSION.md"
if (Test-Path $versionFile) {
  try {
    $line = Select-String -Path $versionFile -Pattern '^\s*-?\s*Version:' | Select-Object -First 1
    if ($line) {
      $templateVersion = ($line.Line -replace '.*Version:\s*','').Trim()
      if ([string]::IsNullOrWhiteSpace($templateVersion)) { $templateVersion = "UNKNOWN" }
    }
  } catch {}
}

$pinPath = Join-Path $TargetRoot ".aai/system/AAI_PIN.md"
@"
# AAI Pin

- Source path: $SrcRoot
- Template version: $templateVersion
- Template commit: $templateSha
- Synced at (UTC): $((Get-Date).ToUniversalTime().ToString("o"))

Notes:
- This project intentionally vendors the AAI files (self-contained).
- Project-specific docs (requirements/specs/decisions/releases/issues) are not synced by this script.
"@ | Set-Content -Path $pinPath -Encoding utf8

Write-Host "Sync complete. Review changes in $TargetRoot :"
Write-Host "  cd $TargetRoot; git status; git diff"
