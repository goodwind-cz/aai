param(
  [Parameter(Mandatory=$true)]
  [string]$TickCommand,
  [int]$MaxIterations = 20,
  [int]$SleepSeconds = 1,
  [switch]$AutoInitState,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$StatePath = "docs/ai/STATE.yaml"
$TickLogPath = "docs/ai/LOOP_TICKS.yaml"

function New-StateFile {
  $utc = (Get-Date).ToUniversalTime().ToString("o")
  @"
project_status: active

current_focus:
  type: none
  ref_id: null
  primary_path: null

locks:
  implementation: true
  implementation_reason: "Implementation is forbidden until scope is explicitly unlocked in state."
  protected_paths:
    - docs/workflow/
    - docs/roles/
    - ai/
  protected_paths_edit_allowed: false
  protected_paths_reason: "Edits are allowed only with explicit scope/HITL approval."

active_work_items:
  []

last_validation:
  status: not_run
  run_at_utc: null
  validator_ref: ai/VALIDATION.prompt.md
  evidence_paths: []
  notes: "No validation run yet."

human_input:
  required: false
  question_ref: null
  blocking_reason: null

ai_os:
  pin_path: docs/ai/AI_OS_PIN.md
  pin_version: null
  pin_commit: null

updated_at_utc: "$utc"
"@ | Set-Content -Path $StatePath -Encoding utf8
}

function Read-State {
  if (!(Test-Path $StatePath)) {
    return @{
      project_status = $null
      human_required = $null
      validation_status = $null
    }
  }

  $raw = Get-Content -Path $StatePath -Raw
  $projectStatus = [regex]::Match($raw, '(?m)^\s*project_status:\s*([A-Za-z_]+)\s*$').Groups[1].Value
  $humanRequired = [regex]::Match($raw, '(?m)^\s*required:\s*(true|false)\s*$').Groups[1].Value
  $validationStatus = [regex]::Match($raw, '(?m)^\s*status:\s*(pass|fail|not_run)\s*$').Groups[1].Value

  return @{
    project_status = $projectStatus
    human_required = $humanRequired
    validation_status = $validationStatus
  }
}

function Stop-Reason {
  param([hashtable]$state)

  if ($state.project_status -eq "paused") { return "project_status=paused" }
  if ($state.human_required -eq "true") { return "human_input.required=true" }
  if ($state.validation_status -eq "pass") { return "last_validation.status=pass" }
  return $null
}

if (!(Test-Path $StatePath)) {
  if ($AutoInitState) {
    New-Item -ItemType Directory -Force -Path "docs/ai" | Out-Null
    New-StateFile
    Write-Host "Initialized $StatePath"
  } else {
    throw "Missing $StatePath. Re-run with -AutoInitState to create it."
  }
}

Write-Host "Autonomous loop start"
Write-Host "Tick command: $TickCommand"
Write-Host "Max iterations: $MaxIterations"

# Initialize tick log if missing
if (!(Test-Path $TickLogPath)) {
  New-Item -ItemType Directory -Force -Path (Split-Path $TickLogPath) | Out-Null
  Set-Content -Path $TickLogPath -Value "# Loop Tick Log (append-only, external timing)`n# Used by ai/METRICS_FLUSH.prompt.md`nticks:" -Encoding utf8
}

for ($i = 1; $i -le $MaxIterations; $i++) {
  $stateBefore = Read-State
  $preStop = Stop-Reason -state $stateBefore
  if ($preStop) {
    Write-Host "Stop before iteration $($i): $preStop"
    break
  }

  Write-Host "Iteration $i/$MaxIterations"
  $tickStart = (Get-Date).ToUniversalTime()
  $tickStartUtc = $tickStart.ToString("o")
  $tickExit = 0

  if ($DryRun) {
    Write-Host "[dry-run] Would execute tick command."
  } else {
    try {
      Invoke-Expression $TickCommand
      $tickExit = if ($LASTEXITCODE -ne $null) { $LASTEXITCODE } else { 0 }
    } catch {
      $tickExit = 1
      Write-Host "Tick command error: $_"
    }
  }

  $tickEnd = (Get-Date).ToUniversalTime()
  $tickEndUtc = $tickEnd.ToString("o")
  $tickDuration = [int]($tickEnd - $tickStart).TotalSeconds

  # Append external tick timing (model-agnostic)
  $tickEntry = "  - tick: $i`n    started_utc: `"$tickStartUtc`"`n    ended_utc: `"$tickEndUtc`"`n    duration_seconds: $tickDuration`n    exit_code: $tickExit"
  Add-Content -Path $TickLogPath -Value $tickEntry -Encoding utf8

  Start-Sleep -Seconds $SleepSeconds
  $stateAfter = Read-State
  $postStop = Stop-Reason -state $stateAfter
  if ($postStop) {
    Write-Host "Stop after iteration $($i): $postStop"
    break
  }

  if ($i -eq $MaxIterations) {
    Write-Host "Reached max iterations ($MaxIterations) without stop condition."
  }
}

Write-Host "Autonomous loop finished."
