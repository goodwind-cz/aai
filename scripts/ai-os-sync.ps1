param(
  [Parameter(Mandatory=$true)]
  [string]$TargetRoot
)

$ErrorActionPreference = "Stop"

# Push AI-OS layer FROM this repository INTO a target project.
#
# Usage (run from anywhere, script finds its own repo root):
#   .\scripts\ai-os-sync.ps1 -TargetRoot ..\maty-ai
#
# Example:
#   .\scripts\ai-os-sync.ps1 -TargetRoot z:\AI\maty-ai

function Copy-Replace {
  param(
    [Parameter(Mandatory=$true)][string]$Src,
    [Parameter(Mandatory=$true)][string]$Dst
  )
  # Git is the backup — no .bak files needed.
  if (Test-Path $Dst) { Remove-Item $Dst -Recurse -Force }
  Copy-Item $Src $Dst -Recurse -Force
}

# Resolve source = this repository's root (parent of the scripts/ folder)
$SrcRoot = Split-Path -Parent $PSScriptRoot

if (!(Test-Path (Join-Path $SrcRoot "ai"))) {
  throw "Source missing ai/ directory: $SrcRoot"
}

if (!(Test-Path $TargetRoot)) {
  throw "Target directory does not exist: $TargetRoot"
}

$TargetRoot = (Resolve-Path $TargetRoot).Path

Write-Host "Syncing AI-OS from: $SrcRoot"
Write-Host "Target project:     $TargetRoot"

# Target directories (AI-OS layer only)
foreach ($d in @("ai",".claude/skills",".github","docs/workflow","docs/roles","docs/templates","docs/knowledge","docs/ai","scripts")) {
  New-Item -ItemType Directory -Force -Path (Join-Path $TargetRoot $d) | Out-Null
}

# Copy AI-OS canonical layer
Copy-Replace (Join-Path $SrcRoot "ai") (Join-Path $TargetRoot "ai")

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

$wf = Join-Path $SrcRoot "docs/workflow"
if (Test-Path $wf) { Copy-Replace $wf (Join-Path $TargetRoot "docs/workflow") }

$roles = Join-Path $SrcRoot "docs/roles"
if (Test-Path $roles) { Copy-Replace $roles (Join-Path $TargetRoot "docs/roles") }

$tpl = Join-Path $SrcRoot "docs/templates"
if (Test-Path $tpl) { Copy-Replace $tpl (Join-Path $TargetRoot "docs/templates") }

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

$aiDocs = Join-Path $SrcRoot "docs/ai"
if (Test-Path $aiDocs) {
  # Preserve runtime files if they already exist in target docs/ai
  $runtimeFiles = @("STATE.yaml", "METRICS.yaml", "LOOP_TICKS.yaml")
  $tmpRuntimeBackup = Join-Path ([System.IO.Path]::GetTempPath()) ("ai-os-sync-runtime-" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $tmpRuntimeBackup | Out-Null
  foreach ($runtimeFile in $runtimeFiles) {
    $runtimeDst = Join-Path $TargetRoot ("docs/ai/" + $runtimeFile)
    if (Test-Path $runtimeDst) {
      Copy-Item $runtimeDst (Join-Path $tmpRuntimeBackup $runtimeFile) -Force
    }
  }

  Copy-Replace $aiDocs (Join-Path $TargetRoot "docs/ai")

  foreach ($runtimeFile in $runtimeFiles) {
    $runtimeBackup = Join-Path $tmpRuntimeBackup $runtimeFile
    if (Test-Path $runtimeBackup) {
      Copy-Item $runtimeBackup (Join-Path $TargetRoot ("docs/ai/" + $runtimeFile)) -Force
      Write-Host "  PRESERVE runtime file: $(Join-Path $TargetRoot ("docs/ai/" + $runtimeFile))"
    }
  }
  Remove-Item $tmpRuntimeBackup -Recurse -Force
}

# Root canonical shims/files
foreach ($f in @("AGENTS.md","PLAYBOOK.md","CLAUDE.md","README.md")) {
  $srcFile = Join-Path $SrcRoot $f
  if (Test-Path $srcFile) {
    Copy-Replace $srcFile (Join-Path $TargetRoot $f)
  }
}

# Canonical helper scripts
foreach ($f in @(
  "scripts/ai-os-sync.ps1",
  "scripts/ai-os-sync.sh",
  "scripts/autonomous-loop.ps1",
  "scripts/autonomous-loop.sh"
)) {
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

# IMPORTANT: Do NOT sync project-specific docs:
# - docs/requirements/**, docs/specs/**, docs/decisions/**, docs/releases/**, docs/issues/**
# These are owned by the target project.

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

$pinPath = Join-Path $TargetRoot "docs/ai/AI_OS_PIN.md"
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
