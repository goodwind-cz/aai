param(
  [Parameter(Mandatory=$true)]
  [string]$SourceRoot
)

$ErrorActionPreference = "Stop"

function Copy-WithBak {
  param(
    [Parameter(Mandatory=$true)][string]$Src,
    [Parameter(Mandatory=$true)][string]$Dst
  )

  if (Test-Path $Dst) {
    try {
      if (Test-Path "$Dst.bak") { Remove-Item "$Dst.bak" -Recurse -Force -ErrorAction SilentlyContinue }
      Copy-Item $Dst "$Dst.bak" -Recurse -Force -ErrorAction SilentlyContinue
    } catch {}
    Remove-Item $Dst -Recurse -Force
  }
  Copy-Item $Src $Dst -Recurse -Force
}

if (!(Test-Path (Join-Path $SourceRoot "ai"))) {
  throw "Source missing ai/ directory: $SourceRoot"
}

Write-Host "Syncing AI-OS from: $SourceRoot"
Write-Host "Target project: $(Get-Location)"

New-Item -ItemType Directory -Force -Path "scripts","ai",".github","docs/workflow","docs/roles","docs/templates","docs/knowledge","docs/ai" | Out-Null

# Copy AI-OS canonical layer
Copy-WithBak (Join-Path $SourceRoot "ai") "ai"

$wf = Join-Path $SourceRoot "docs/workflow"
if (Test-Path $wf) { Copy-WithBak $wf "docs/workflow" }

$roles = Join-Path $SourceRoot "docs/roles"
if (Test-Path $roles) { Copy-WithBak $roles "docs/roles" }

$tpl = Join-Path $SourceRoot "docs/templates"
if (Test-Path $tpl) { Copy-WithBak $tpl "docs/templates" }

$know = Join-Path $SourceRoot "docs/knowledge"
if (Test-Path $know) { Copy-WithBak $know "docs/knowledge" }

$aiDocs = Join-Path $SourceRoot "docs/ai"
if (Test-Path $aiDocs) { Copy-WithBak $aiDocs "docs/ai" }

# Root canonical shims/files (only if present in template)
foreach ($f in @("AGENTS.md","PLAYBOOK.md","CLAUDE.md","README.md")) {
  $srcFile = Join-Path $SourceRoot $f
  if (Test-Path $srcFile) {
    Copy-WithBak $srcFile $f
  }
}

# Canonical helper scripts
foreach ($f in @(
  "scripts/ai-os-sync.ps1",
  "scripts/ai-os-sync.sh",
  "scripts/autonomous-loop.ps1",
  "scripts/autonomous-loop.sh"
)) {
  $srcFile = Join-Path $SourceRoot $f
  if (Test-Path $srcFile) {
    Copy-WithBak $srcFile $f
  }
}

# Copilot shim
$copilot = Join-Path $SourceRoot ".github/copilot-instructions.md"
if (Test-Path $copilot) {
  Copy-WithBak $copilot ".github/copilot-instructions.md"
}

# IMPORTANT: Do NOT sync project-specific docs by default:
# - docs/requirements/**, docs/specs/**, docs/decisions/**, docs/releases/**, docs/issues/**

# Pin info
$templateSha = "UNKNOWN"
try { $templateSha = (git -C $SourceRoot rev-parse HEAD) 2>$null } catch {}

$templateVersion = "UNKNOWN"
$versionFile = Join-Path $SourceRoot "docs/ai/AI_OS_VERSION.md"
if (Test-Path $versionFile) {
  try {
    $line = Select-String -Path $versionFile -Pattern '^\s*-?\s*Version:' | Select-Object -First 1
    if ($line) {
      $templateVersion = ($line.Line -replace '.*Version:\s*','').Trim()
      if ([string]::IsNullOrWhiteSpace($templateVersion)) { $templateVersion = "UNKNOWN" }
    }
  } catch {}
}

@"
# AI-OS Pin

- Source path: $SourceRoot
- Template version: $templateVersion
- Template commit: $templateSha
- Synced at (UTC): $((Get-Date).ToUniversalTime().ToString("o"))

Notes:
- This project intentionally vendors the AI-OS files (self-contained).
- Project-specific docs (requirements/specs/decisions/releases/issues) are not synced by this script.
"@ | Set-Content -Path "docs/ai/AI_OS_PIN.md" -Encoding utf8

Write-Host "Sync complete."
Write-Host "Review changes:"
Write-Host "  git status"
Write-Host "  git diff"
