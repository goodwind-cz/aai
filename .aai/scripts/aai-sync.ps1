param(
  [Parameter(Mandatory=$true)]
  [string]$TargetRoot
)

$ErrorActionPreference = "Stop"

# Push AI-OS layer FROM this repository INTO a target project.
#
# Usage (run from anywhere, script finds its own repo root):
#   .\.aai\scripts\ai-os-sync.ps1 -TargetRoot ..\maty-ai
#
# Example:
#   .\.aai\scripts\ai-os-sync.ps1 -TargetRoot z:\AI\maty-ai

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

Write-Host "Syncing AI-OS from: $SrcRoot"
Write-Host "Target project:     $TargetRoot"

# Target directories (AI-OS layer only)
foreach ($d in @(".aai/workflow",".aai/roles",".aai/templates",".aai/scripts",".aai/system",".aai/knowledge",".claude/skills",".codex/skills",".codex/skills.local",".gemini/skills",".gemini/skills.local",".github","docs/knowledge","docs/ai")) {
  New-Item -ItemType Directory -Force -Path (Join-Path $TargetRoot $d) | Out-Null
}

# Copy AI-OS canonical layer (.aai/ is the single source of truth)
Copy-Replace (Join-Path $SrcRoot ".aai") (Join-Path $TargetRoot ".aai")

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
# AI-OS-TEMPLATE sentinel (meaning the target project has filled them with real content).
$know = Join-Path $SrcRoot "docs/knowledge"
if (Test-Path $know) {
  New-Item -ItemType Directory -Force -Path (Join-Path $TargetRoot "docs/knowledge") | Out-Null
  Get-ChildItem -Path $know -File | ForEach-Object {
    $srcFile = $_.FullName
    $dstFile = Join-Path $TargetRoot "docs/knowledge" $_.Name
    $isTemplate = $true
    if (Test-Path $dstFile) {
      $content = Get-Content $dstFile -Raw -ErrorAction SilentlyContinue
      $isTemplate = $content -match "AI-OS-TEMPLATE"
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
foreach ($f in @("CLAUDE.md","CODEX.md","GEMINI.md","README.md")) {
  $srcFile = Join-Path $SrcRoot $f
  if (Test-Path $srcFile) {
    Copy-Replace $srcFile (Join-Path $TargetRoot $f)
  }
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
  Add-Content -Path $gitignorePath -Value "`n# AI-OS infrastructure (vendored, not committed)`n.aai/"
  Write-Host "  Added .aai/ to $gitignorePath"
}

# Pin info
$templateSha = "UNKNOWN"
try { $templateSha = (git -C $SrcRoot rev-parse HEAD) 2>$null } catch {}

$templateVersion = "UNKNOWN"
$versionFile = Join-Path $SrcRoot "docs/ai/AI_OS_VERSION.md"
if (Test-Path $versionFile) {
  try {
    $line = Select-String -Path $versionFile -Pattern '^\s*-?\s*Version:' | Select-Object -First 1
    if ($line) {
      $templateVersion = ($line.Line -replace '.*Version:\s*','').Trim()
      if ([string]::IsNullOrWhiteSpace($templateVersion)) { $templateVersion = "UNKNOWN" }
    }
  } catch {}
}

$pinPath = Join-Path $TargetRoot ".aai/system/AI_OS_PIN.md"
@"
# AI-OS Pin

- Source path: $SrcRoot
- Template version: $templateVersion
- Template commit: $templateSha
- Synced at (UTC): $((Get-Date).ToUniversalTime().ToString("o"))

Notes:
- This project intentionally vendors the AI-OS files (self-contained).
- Project-specific docs (requirements/specs/decisions/releases/issues) are not synced by this script.
"@ | Set-Content -Path $pinPath -Encoding utf8

Write-Host "Sync complete. Review changes in $TargetRoot :"
Write-Host "  cd $TargetRoot; git status; git diff"
