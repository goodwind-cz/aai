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
$TickLogPath = "docs/ai/LOOP_TICKS.jsonl"

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
      focus_type = $null
      focus_ref_id = $null
    }
  }

  $raw = Get-Content -Path $StatePath -Raw
  $projectStatus = [regex]::Match($raw, '(?m)^\s*project_status:\s*([A-Za-z_]+)\s*$').Groups[1].Value
  $humanRequired = [regex]::Match($raw, '(?m)^\s*required:\s*(true|false)\s*$').Groups[1].Value
  $validationStatus = [regex]::Match($raw, '(?m)^\s*status:\s*(pass|fail|not_run)\s*$').Groups[1].Value
  $focusType = [regex]::Match($raw, '(?ms)^\s*current_focus:\s*\r?\n\s*type:\s*([A-Za-z0-9_]+)\s*$').Groups[1].Value
  $focusRefId = [regex]::Match($raw, '(?ms)^\s*current_focus:\s*\r?\n\s*type:\s*[A-Za-z0-9_]+\s*\r?\n\s*ref_id:\s*([^\r\n]+)\s*$').Groups[1].Value

  return @{
    project_status = $projectStatus
    human_required = $humanRequired
    validation_status = $validationStatus
    focus_type = $focusType
    focus_ref_id = $focusRefId
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
  New-Item -ItemType File -Path $TickLogPath | Out-Null
}

# Detect if previous loop run ended with human_input pause — record resume
$loopStartUtc = (Get-Date).ToUniversalTime()
$loopStartEpoch = [int][double]::Parse((Get-Date -UFormat %s -Date $loopStartUtc))
$tickLogLines = Get-Content $TickLogPath -ErrorAction SilentlyContinue
$lastPauseEpoch = 0
$lastResumeEpoch = 0
foreach ($line in $tickLogLines) {
  if ($line -match '"type":"human_pause"' -and $line -match '"paused_epoch":(\d+)') {
    $lastPauseEpoch = [int]$Matches[1]
  }
  if ($line -match '"type":"human_resume"' -and $line -match '"resumed_epoch":(\d+)') {
    $lastResumeEpoch = [int]$Matches[1]
  }
}
if ($lastPauseEpoch -gt 0 -and $lastPauseEpoch -gt $lastResumeEpoch) {
  $reviewDuration = $loopStartEpoch - $lastPauseEpoch
  $resumeEntry = "{`"type`":`"human_resume`",`"resumed_utc`":`"$($loopStartUtc.ToString('o'))`",`"resumed_epoch`":$loopStartEpoch,`"review_duration_seconds`":$reviewDuration}"
  Add-Content -Path $TickLogPath -Value $resumeEntry -Encoding utf8
  Write-Host "Detected human resume after ${reviewDuration}s review pause."
}

for ($i = 1; $i -le $MaxIterations; $i++) {
  $stateBefore = Read-State
  $preStop = Stop-Reason -state $stateBefore
  if ($preStop) {
    Write-Host "Stop before iteration $($i): $preStop"
    break
  }

  Write-Host "Iteration $i/$MaxIterations"
  $stateSnapshotBefore = Read-State
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
  $stateSnapshotAfter = Read-State
  $tickEntry = "{`"type`":`"tick`",`"tick`":$i,`"started_utc`":`"$tickStartUtc`",`"ended_utc`":`"$tickEndUtc`",`"duration_seconds`":$tickDuration,`"exit_code`":$tickExit,`"focus_type_before`":`"$($stateSnapshotBefore.focus_type)`",`"focus_ref_id_before`":`"$($stateSnapshotBefore.focus_ref_id)`",`"focus_type_after`":`"$($stateSnapshotAfter.focus_type)`",`"focus_ref_id_after`":`"$($stateSnapshotAfter.focus_ref_id)`",`"validation_status_before`":`"$($stateSnapshotBefore.validation_status)`",`"validation_status_after`":`"$($stateSnapshotAfter.validation_status)`"}"
  Add-Content -Path $TickLogPath -Value $tickEntry -Encoding utf8

  Start-Sleep -Seconds $SleepSeconds
  $stateAfter = Read-State
  $postStop = Stop-Reason -state $stateAfter
  if ($postStop) {
    Write-Host "Stop after iteration $($i): $postStop"
    # Record human_input pause so next loop run can calculate review duration
    if ($postStop -eq "human_input.required=true") {
      $pauseNow = (Get-Date).ToUniversalTime()
      $pauseEpoch = [int][double]::Parse((Get-Date -UFormat %s -Date $pauseNow))
      $pauseEntry = "{`"type`":`"human_pause`",`"paused_utc`":`"$($pauseNow.ToString('o'))`",`"paused_epoch`":$pauseEpoch,`"stop_reason`":`"$postStop`"}"
      Add-Content -Path $TickLogPath -Value $pauseEntry -Encoding utf8
    }
    break
  }

  if ($i -eq $MaxIterations) {
    Write-Host "Reached max iterations ($MaxIterations) without stop condition."
  }
}

Write-Host "Autonomous loop finished."
