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

function Test-FileContentDifferent {
  param(
    [Parameter(Mandatory=$true)][string]$Src,
    [Parameter(Mandatory=$true)][string]$Dst
  )
  if (!(Test-Path $Src) -or !(Test-Path $Dst)) { return $true }
  $srcItem = Get-Item $Src -Force
  $dstItem = Get-Item $Dst -Force
  if ($srcItem.PSIsContainer -or $dstItem.PSIsContainer) { return $true }
  try {
    $srcHash = (Get-FileHash -Algorithm SHA256 -Path $Src).Hash
    $dstHash = (Get-FileHash -Algorithm SHA256 -Path $Dst).Hash
    return $srcHash -ne $dstHash
  } catch {
    return $true
  }
}

function Test-DirectoryContentDifferent {
  param(
    [Parameter(Mandatory=$true)][string]$Src,
    [Parameter(Mandatory=$true)][string]$Dst
  )
  if (!(Test-Path $Src) -or !(Test-Path $Dst)) { return $true }
  $srcFiles = Get-ChildItem -Path $Src -Recurse -File -Force -ErrorAction SilentlyContinue
  $dstFiles = Get-ChildItem -Path $Dst -Recurse -File -Force -ErrorAction SilentlyContinue

  $srcRel = @{}
  foreach ($f in $srcFiles) {
    $rel = $f.FullName.Substring($Src.Length).TrimStart('\','/')
    $srcRel[$rel] = $f.FullName
  }
  $dstRel = @{}
  foreach ($f in $dstFiles) {
    $rel = $f.FullName.Substring($Dst.Length).TrimStart('\','/')
    $dstRel[$rel] = $f.FullName
  }

  if ($srcRel.Count -ne $dstRel.Count) { return $true }
  foreach ($rel in $srcRel.Keys) {
    if (!$dstRel.ContainsKey($rel)) { return $true }
    if (Test-FileContentDifferent -Src $srcRel[$rel] -Dst $dstRel[$rel]) { return $true }
  }
  return $false
}

function Get-CopilotProjectOverridesContent {
  param(
    [Parameter(Mandatory=$true)][string]$Content
  )
  $startMarker = "<!-- AAI-PROJECT-OVERRIDES:START -->"
  $endMarker = "<!-- AAI-PROJECT-OVERRIDES:END -->"
  $startIndex = $Content.IndexOf($startMarker)
  $endIndex = $Content.IndexOf($endMarker)
  if (($startIndex -ge 0) -and ($endIndex -gt $startIndex)) {
    $startPos = $startIndex + $startMarker.Length
    return $Content.Substring($startPos, $endIndex - $startPos).Trim()
  }
  return $Content.Trim()
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
foreach ($d in @(".aai/workflow",".aai/roles",".aai/templates",".aai/scripts",".aai/system",".aai/knowledge",".claude/skills",".claude-plugin",".codex/skills",".codex/skills.local",".cursor/rules",".gemini/skills",".gemini/skills.local",".github","docs/knowledge","docs/ai","hooks")) {
  New-Item -ItemType Directory -Force -Path (Join-Path $TargetRoot $d) | Out-Null
}

$overwriteConflicts = @()

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
  $targetAaiPath = Join-Path $TargetRoot ".aai"
  Copy-Replace $_.FullName (Join-Path $targetAaiPath $_.Name)
}

# Clean stale top-level items in target .aai/ that no longer exist in source (except scripts/, cache/)
Get-ChildItem -Path (Join-Path $TargetRoot ".aai") -Force | Where-Object { $_.Name -notin @("scripts","cache") } | ForEach-Object {
  $srcAaiPath = Join-Path $SrcRoot ".aai"
  if (!(Test-Path (Join-Path $srcAaiPath $_.Name))) {
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
    $srcSkillMd = Join-Path $_.FullName "SKILL.md"
    $dstSkillMd = Join-Path $dstEntry "SKILL.md"
    if (Test-Path $dstEntry) {
      if ((Test-Path $srcSkillMd) -and (Test-Path $dstSkillMd)) {
        if (Test-FileContentDifferent -Src $srcSkillMd -Dst $dstSkillMd) {
          $overwriteConflicts += [pscustomobject]@{
            Path = ".claude/skills/$($_.Name)/SKILL.md"
            Recommendation = "Template skill differs in target. Use AI agent to merge intentional project guidance into a project-owned skill (for example .claude/skills/aai-project-<topic>/SKILL.md) and keep synced template skills unchanged."
          }
        }
      } elseif (Test-DirectoryContentDifferent -Src $_.FullName -Dst $dstEntry) {
        $overwriteConflicts += [pscustomobject]@{
          Path = ".claude/skills/$($_.Name)"
          Recommendation = "Directory differs in target. Use AI agent to extract project-specific content into project-owned skills and keep sync-managed entries as template-only."
        }
      }
    }
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
    $dstKnowledge = Join-Path $TargetRoot "docs/knowledge"
    $dstFile = Join-Path $dstKnowledge $_.Name
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
  $dstFile = Join-Path $TargetRoot $f
  if ((Test-Path $srcFile) -and (Test-Path $dstFile) -and (Test-FileContentDifferent -Src $srcFile -Dst $dstFile)) {
    $overwriteConflicts += [pscustomobject]@{
      Path = $f
      Recommendation = "Target file contains local changes. Use AI agent to merge project-specific instructions into docs/ai/project-overrides/$f and keep synced shim concise."
    }
  }
  if (Test-Path $srcFile) {
    Copy-Replace $srcFile $dstFile
  }
}
$srcReadme = Join-Path $SrcRoot "README.md"
$dstReadmeAai = Join-Path $TargetRoot "README_AAI.md"
if ((Test-Path $srcReadme) -and (Test-Path $dstReadmeAai) -and (Test-FileContentDifferent -Src $srcReadme -Dst $dstReadmeAai)) {
  $overwriteConflicts += [pscustomobject]@{
    Path = "README_AAI.md"
    Recommendation = "Target README_AAI.md differs from source README.md. Use AI agent to move project notes into README.md or docs/, and keep README_AAI.md sync-managed."
  }
}
if (Test-Path $srcReadme) {
  Copy-Replace $srcReadme $dstReadmeAai
}

# Copilot shim
$copilot = Join-Path $SrcRoot ".github/copilot-instructions.md"
$dstCopilot = Join-Path $TargetRoot ".github/copilot-instructions.md"
if (Test-Path $copilot) {
  $overrideDir = Join-Path $TargetRoot "docs/ai/project-overrides"
  $overrideFile = Join-Path $overrideDir "copilot-instructions.project.md"
  if ((Test-Path $dstCopilot) -and (Test-FileContentDifferent -Src $copilot -Dst $dstCopilot)) {
    New-Item -ItemType Directory -Force -Path $overrideDir | Out-Null
    $dstContent = Get-Content $dstCopilot -Raw -ErrorAction SilentlyContinue
    $projectOverrides = Get-CopilotProjectOverridesContent -Content $dstContent
    if ([string]::IsNullOrWhiteSpace($projectOverrides) -and (Test-Path $overrideFile)) {
      $projectOverrides = (Get-Content $overrideFile -Raw -ErrorAction SilentlyContinue).Trim()
    }
    if (![string]::IsNullOrWhiteSpace($projectOverrides)) {
      Set-Content -Path $overrideFile -Value $projectOverrides -Encoding utf8
    }

    $baseContent = Get-Content $copilot -Raw -ErrorAction SilentlyContinue
    $merged = @(
      $baseContent.TrimEnd()
      ""
      "---"
      "## Project Overrides (auto-merged)"
      ""
      "<!-- AAI-PROJECT-OVERRIDES:START -->"
      $projectOverrides
      "<!-- AAI-PROJECT-OVERRIDES:END -->"
      ""
    ) -join "`n"
    Set-Content -Path $dstCopilot -Value $merged -Encoding utf8
    Write-Host "  MERGE preserved project overrides in: $overrideFile"
  } else {
    Copy-Replace $copilot $dstCopilot
  }
}

# Codex skill index
$codexSkills = Join-Path $SrcRoot ".codex/skills"
$dstCodexSkills = Join-Path $TargetRoot ".codex/skills"
if ((Test-Path $codexSkills) -and (Test-Path $dstCodexSkills) -and (Test-DirectoryContentDifferent -Src $codexSkills -Dst $dstCodexSkills)) {
  $overwriteConflicts += [pscustomobject]@{
    Path = ".codex/skills/"
    Recommendation = "Target Codex skills differ from sync source. Use AI agent to migrate project-specific content into project-owned docs and keep sync-managed indexes untouched."
  }
}
if (Test-Path $codexSkills) {
  Copy-Replace $codexSkills $dstCodexSkills
}
if (Test-Path (Join-Path $TargetRoot ".codex/skills.local")) {
  Write-Host "  PRESERVE local Codex dynamic index: $(Join-Path $TargetRoot ".codex/skills.local")"
}

# Gemini skill index
$geminiSkills = Join-Path $SrcRoot ".gemini/skills"
$dstGeminiSkills = Join-Path $TargetRoot ".gemini/skills"
if ((Test-Path $geminiSkills) -and (Test-Path $dstGeminiSkills) -and (Test-DirectoryContentDifferent -Src $geminiSkills -Dst $dstGeminiSkills)) {
  $overwriteConflicts += [pscustomobject]@{
    Path = ".gemini/skills/"
    Recommendation = "Target Gemini skills differ from sync source. Use AI agent to migrate project-specific content into project-owned docs and keep sync-managed indexes untouched."
  }
}
if (Test-Path $geminiSkills) {
  Copy-Replace $geminiSkills $dstGeminiSkills
}
if (Test-Path (Join-Path $TargetRoot ".gemini/skills.local")) {
  Write-Host "  PRESERVE local Gemini dynamic index: $(Join-Path $TargetRoot ".gemini/skills.local")"
}

# Claude Code plugin manifest
$pluginJson = Join-Path $SrcRoot ".claude-plugin/plugin.json"
if (Test-Path $pluginJson) {
  Copy-Replace $pluginJson (Join-Path $TargetRoot ".claude-plugin/plugin.json")
  Write-Host "  SYNC .claude-plugin/plugin.json"
}

# Session hooks (cross-platform: Claude Code, Cursor, Gemini, Codex)
$hooksDir = Join-Path $SrcRoot "hooks"
if (Test-Path $hooksDir) {
  Copy-Replace $hooksDir (Join-Path $TargetRoot "hooks")
  Write-Host "  SYNC hooks/"
}

# Cursor rules
$cursorRule = Join-Path $SrcRoot ".cursor/rules/aai.mdc"
if (Test-Path $cursorRule) {
  Copy-Replace $cursorRule (Join-Path $TargetRoot ".cursor/rules/aai.mdc")
  Write-Host "  SYNC .cursor/rules/aai.mdc"
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
    "docs/ai/reports/sync-conflicts-*.md"
  ) -join "`n"
  Add-Content -Path $gitignorePath -Value $reportBlock
  Write-Host "  Added validation report patterns to $gitignorePath"
}

# Ensure synced agent skill indexes are gitignored (sync-managed artifacts)
$giContent = if (Test-Path $gitignorePath) { Get-Content $gitignorePath -Raw -ErrorAction SilentlyContinue } else { "" }
$agentSkillEntries = @(
  ".claude/skills/"
  ".codex/skills/"
  ".codex/skills.local/"
  ".gemini/skills/"
  ".gemini/skills.local/"
)
$missingAgentSkillEntries = @()
foreach ($entry in $agentSkillEntries) {
  if ($giContent -notmatch ("(?m)^" + [regex]::Escape($entry) + "$")) {
    $missingAgentSkillEntries += $entry
  }
}
if ($missingAgentSkillEntries.Count -gt 0) {
  $agentSkillBlock = @(
    ""
    "# AAI agent skill sync artifacts (managed by sync)"
  ) + $missingAgentSkillEntries
  Add-Content -Path $gitignorePath -Value ($agentSkillBlock -join "`n")
  Write-Host "  Added agent skill sync patterns to $gitignorePath"
}

# Create conflict advisory report for files that were overwritten with differences.
if ($overwriteConflicts.Count -gt 0) {
  $reportDir = Join-Path $TargetRoot "docs/ai/reports"
  New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
  $reportName = "sync-conflicts-$((Get-Date).ToString('yyyyMMdd-HHmmss')).md"
  $reportPath = Join-Path $reportDir $reportName
  $reportLines = @(
    "# Sync Conflict Advisory"
    ""
    "- Generated at (UTC): $((Get-Date).ToUniversalTime().ToString('o'))"
    "- Source: $SrcRoot"
    ""
    "The following target files/directories had local content that differed from sync source and were overwritten."
    "Use an AI agent to decide merge strategy per item."
    ""
    "## Recommended AI workflow"
    "1. Inspect each item with `git diff -- <path>` in the target project."
    "2. Ask AI to extract project-specific guidance and place it into project-owned docs (for example `docs/ai/project-overrides/`)."
    "3. Keep sync-managed files as baseline templates to reduce future conflicts."
    ""
    "## Overwritten items"
  )
  foreach ($conflict in $overwriteConflicts) {
    $reportLines += ""
    $reportLines += "- Path: $($conflict.Path)"
    $reportLines += "- Recommendation: $($conflict.Recommendation)"
  }
  Set-Content -Path $reportPath -Value ($reportLines -join "`n") -Encoding utf8
  Write-Host "  Advisory report: $reportPath"
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
