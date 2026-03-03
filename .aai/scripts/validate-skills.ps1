param(
  [string]$TargetRoot = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path $TargetRoot).Path

function Require-File {
  param([string]$Path)
  if (!(Test-Path $Path)) {
    throw "Missing required file: $Path"
  }
}

Write-Host "Validating skills in: $root"

$requiredPrompts = @(
  ".aai/SKILL_CHECK_STATE.prompt.md",
  ".aai/SKILL_INTAKE.prompt.md",
  ".aai/SKILL_LOOP.prompt.md",
  ".aai/SKILL_HITL.prompt.md",
  ".aai/SKILL_BOOTSTRAP.prompt.md",
  ".aai/SKILL_VALIDATE_REPORT.prompt.md",
  ".aai/SKILL_CANONICALIZE.prompt.md",
  ".aai/SKILL_TDD.prompt.md",
  ".aai/SKILL_WORKTREE.prompt.md",
  ".aai/SKILL_SHARE.prompt.md"
)

foreach ($p in $requiredPrompts) {
  Require-File -Path (Join-Path $root $p)
}

$skillsMarker = Join-Path $root ".claude/skills/AAI_DYNAMIC_SKILLS.md"
if (Test-Path $skillsMarker) {
  Write-Host "OK: dynamic skills bootstrap marker exists (.claude/skills/AAI_DYNAMIC_SKILLS.md)"
} else {
  Write-Warning "Missing .claude/skills/AAI_DYNAMIC_SKILLS.md (bootstrap may not have run yet)."
}

$tickLog = Join-Path $root "docs/ai/LOOP_TICKS.jsonl"
if (Test-Path $tickLog) {
  $hasSkillTicks = Select-String -Path $tickLog -Pattern '"mode":"skill"' -SimpleMatch -ErrorAction SilentlyContinue
  if ($hasSkillTicks) {
    Write-Host "OK: LOOP_TICKS.jsonl contains skill-mode evidence."
  } else {
    Write-Warning "LOOP_TICKS.jsonl has no skill-mode entries yet."
  }
} else {
  Write-Warning "Missing docs/ai/LOOP_TICKS.jsonl (no runtime evidence yet)."
}

Write-Host "Skill validation completed."
