param(
  [string]$TickCommand,
  [ValidateSet("skill","legacy")]
  [string]$Mode = "skill",
  [string]$AgentCommand,
  [int]$MaxIterations = 20,
  [int]$SleepSeconds = 1,
  [switch]$AutoInitState,
  [switch]$NoAutoInstallPyYaml,
  [switch]$SkipBootstrapCheck,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$StatePath = "docs/ai/STATE.yaml"
$TickLogPath = "docs/ai/LOOP_TICKS.jsonl"
$Py = $null
$StateReaderPy = $null
$SkillFlow = "none"
$BootstrapReady = "unknown"

function Test-RequiredFiles {
  param([string[]]$Paths)
  $missing = @()
  foreach ($p in $Paths) {
    if (!(Test-Path $p)) { $missing += $p }
  }
  return $missing
}

function Build-SkillTickCommand {
  param([string]$Cmd)
  $steps = @(
    ".aai/SKILL_CHECK_STATE.prompt.md",
    ".aai/SKILL_INTAKE.prompt.md",
    ".aai/SKILL_LOOP.prompt.md"
  )
  $parts = @()
  foreach ($s in $steps) {
    $parts += "$Cmd --prompt-file $s"
  }
  return ($parts -join "; ")
}

function Ensure-PyYaml {
  param([switch]$NoAutoInstall)

  foreach ($cmd in @("python3", "python", "py")) {
    try {
      $out = & $cmd -c "import yaml; print('ok')" 2>$null
      if ($out -eq "ok") { return $cmd }
    } catch {}
  }

  if ($NoAutoInstall) {
    throw "python + PyYAML required. Install with: pip install pyyaml"
  }

  foreach ($cmd in @("python3", "python", "py")) {
    try {
      $out = & $cmd -c "print('ok')" 2>$null
      if ($out -eq "ok") {
        Write-Host "PyYAML not found. Installing via $cmd -m pip install pyyaml..."
        & $cmd -m pip install pyyaml | Out-Host
        $verify = & $cmd -c "import yaml; print('ok')" 2>$null
        if ($verify -eq "ok") { return $cmd }
      }
    } catch {}
  }

  throw "python + PyYAML required. Install with: pip install pyyaml"
}

function Initialize-StateReader {
  param([string]$PyCmd)

  $pyScript = @"
import yaml, json, sys

path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}

def get(d, *keys):
    for k in keys:
        if not isinstance(d, dict) or k not in d:
            return None
        d = d[k]
    return d

out = {
    "project_status": data.get("project_status"),
    "human_required": get(data, "human_input", "required"),
    "validation_status": get(data, "last_validation", "status"),
    "focus_type": get(data, "current_focus", "type"),
    "focus_ref_id": get(data, "current_focus", "ref_id"),
}

print(json.dumps(out, separators=(",", ":"), ensure_ascii=False))
"@

  $tmp = [System.IO.Path]::GetTempFileName() + ".py"
  Set-Content -Path $tmp -Value $pyScript -Encoding utf8
  return $tmp
}

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
    - .aai/workflow/
    - .aai/roles/
    - .aai/
  protected_paths_edit_allowed: false
  protected_paths_reason: "Edits are allowed only with explicit scope/HITL approval."

active_work_items:
  []

last_validation:
  status: not_run
  run_at_utc: null
  validator_ref: .aai/VALIDATION.prompt.md
  evidence_paths: []
  notes: "No validation run yet."

human_input:
  required: false
  question_ref: null
  blocking_reason: null

ai_os:
  pin_path: .aai/system/AAI_PIN.md
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

  $json = & $Py $StateReaderPy $StatePath
  if ([string]::IsNullOrWhiteSpace($json)) {
    return @{
      project_status = $null
      human_required = $null
      validation_status = $null
      focus_type = $null
      focus_ref_id = $null
    }
  }

  $parsed = $json | ConvertFrom-Json
  $projectStatus = [string]$parsed.project_status
  $humanRequired = [string]$parsed.human_required
  $validationStatus = [string]$parsed.validation_status
  $focusType = [string]$parsed.focus_type
  $focusRefId = [string]$parsed.focus_ref_id

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

if ($Mode -eq "skill") {
  $SkillFlow = "check_state>intake>loop"
  $requiredSkillPrompts = @(
    ".aai/SKILL_CHECK_STATE.prompt.md",
    ".aai/SKILL_INTAKE.prompt.md",
    ".aai/SKILL_LOOP.prompt.md",
    ".aai/SKILL_BOOTSTRAP.prompt.md"
  )
  $missingPrompts = Test-RequiredFiles -Paths $requiredSkillPrompts
  if ($missingPrompts.Count -gt 0) {
    throw "Missing required skill prompts: $($missingPrompts -join ', ')"
  }

  if (!$SkipBootstrapCheck) {
    if (!(Test-Path ".claude/skills/AAI_DYNAMIC_SKILLS.md")) {
      $BootstrapReady = "false"
      throw "Missing .claude/skills/AAI_DYNAMIC_SKILLS.md. Run bootstrap first: follow .aai/SKILL_BOOTSTRAP.prompt.md"
    }
    $BootstrapReady = "true"
  } else {
    $BootstrapReady = "skipped"
  }

  if ([string]::IsNullOrWhiteSpace($TickCommand)) {
    if ([string]::IsNullOrWhiteSpace($AgentCommand)) {
      throw "In Mode=skill provide either -TickCommand or -AgentCommand (example: -AgentCommand 'codex')."
    }
    $TickCommand = Build-SkillTickCommand -Cmd $AgentCommand
  }
} else {
  if ([string]::IsNullOrWhiteSpace($TickCommand)) {
    throw "In Mode=legacy, -TickCommand is required."
  }
}

try {
  $Py = Ensure-PyYaml -NoAutoInstall:$NoAutoInstallPyYaml
  $StateReaderPy = Initialize-StateReader -PyCmd $Py

Write-Host "Autonomous loop start"
Write-Host "Mode: $Mode"
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
  $tickEntry = "{`"type`":`"tick`",`"tick`":$i,`"started_utc`":`"$tickStartUtc`",`"ended_utc`":`"$tickEndUtc`",`"duration_seconds`":$tickDuration,`"exit_code`":$tickExit,`"mode`":`"$Mode`",`"skill_flow`":`"$SkillFlow`",`"bootstrap_ready`":`"$BootstrapReady`",`"focus_type_before`":`"$($stateSnapshotBefore.focus_type)`",`"focus_ref_id_before`":`"$($stateSnapshotBefore.focus_ref_id)`",`"focus_type_after`":`"$($stateSnapshotAfter.focus_type)`",`"focus_ref_id_after`":`"$($stateSnapshotAfter.focus_ref_id)`",`"validation_status_before`":`"$($stateSnapshotBefore.validation_status)`",`"validation_status_after`":`"$($stateSnapshotAfter.validation_status)`"}"
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

} finally {
  if ($StateReaderPy -and (Test-Path $StateReaderPy)) {
    Remove-Item $StateReaderPy -Force -ErrorAction SilentlyContinue
  }
}
Write-Host "Autonomous loop finished."
