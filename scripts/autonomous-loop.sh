#!/usr/bin/env bash
set -euo pipefail

STATE_PATH="docs/ai/STATE.yaml"
TICK_LOG="docs/ai/LOOP_TICKS.jsonl"
TICK_COMMAND=""
MODE="skill"
AGENT_COMMAND=""
MAX_ITERATIONS=20
SLEEP_SECONDS=1
AUTO_INIT_STATE=0
SKIP_BOOTSTRAP_CHECK=0
DRY_RUN=0
SKILL_FLOW="none"
BOOTSTRAP_READY="unknown"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/autonomous-loop.sh [options]

Options:
  --mode skill|legacy         skill (default) runs SKILL_CHECK_STATE -> SKILL_INTAKE -> SKILL_LOOP
  --agent-command "<command>" Agent binary used in skill mode (example: codex)
  --tick-command "<command>"  Explicit command that performs one autonomous tick
  --max-iterations N          Maximum loop iterations (default: 20)
  --sleep-seconds N           Sleep between iterations (default: 1)
  --auto-init-state           Create docs/ai/STATE.yaml if missing
  --skip-bootstrap-check      Skip check for .claude/skills.local/README.md
  --dry-run                   Do not execute tick command
EOF
}

build_skill_tick_command() {
  local cmd="$1"
  printf "%s --prompt-file ai/SKILL_CHECK_STATE.prompt.md; %s --prompt-file ai/SKILL_INTAKE.prompt.md; %s --prompt-file ai/SKILL_LOOP.prompt.md" \
    "$cmd" "$cmd" "$cmd"
}

create_state_file() {
  mkdir -p docs/ai
  cat > "$STATE_PATH" <<EOF
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

updated_at_utc: "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
EOF
}

read_project_status() {
  grep -E '^[[:space:]]*project_status:[[:space:]]*' "$STATE_PATH" | head -n1 | sed -E 's/^[^:]+:[[:space:]]*//'
}

read_human_required() {
  awk '
    /^[[:space:]]*human_input:/ {in_human=1; next}
    in_human && /^[[:space:]]*[A-Za-z0-9_]+:/ && $1 !~ /^required:/ {in_human=0}
    in_human && /^[[:space:]]*required:[[:space:]]*/ {
      sub(/^[[:space:]]*required:[[:space:]]*/, "", $0)
      print $0
      exit
    }
  ' "$STATE_PATH"
}

read_validation_status() {
  awk '
    /^[[:space:]]*last_validation:/ {in_val=1; next}
    in_val && /^[[:space:]]*[A-Za-z0-9_]+:/ && $1 !~ /^status:/ {in_val=0}
    in_val && /^[[:space:]]*status:[[:space:]]*/ {
      sub(/^[[:space:]]*status:[[:space:]]*/, "", $0)
      print $0
      exit
    }
  ' "$STATE_PATH"
}

read_focus_type() {
  awk '
    /^[[:space:]]*current_focus:/ {in_focus=1; next}
    in_focus && /^[[:space:]]*[A-Za-z0-9_]+:/ && $1 !~ /^type:/ {in_focus=0}
    in_focus && /^[[:space:]]*type:[[:space:]]*/ {
      sub(/^[[:space:]]*type:[[:space:]]*/, "", $0)
      print $0
      exit
    }
  ' "$STATE_PATH"
}

read_focus_ref_id() {
  awk '
    /^[[:space:]]*current_focus:/ {in_focus=1; next}
    in_focus && /^[[:space:]]*[A-Za-z0-9_]+:/ && $1 !~ /^ref_id:/ {in_focus=0}
    in_focus && /^[[:space:]]*ref_id:[[:space:]]*/ {
      sub(/^[[:space:]]*ref_id:[[:space:]]*/, "", $0)
      print $0
      exit
    }
  ' "$STATE_PATH"
}

stop_reason() {
  local project_status human_required validation_status
  project_status="$(read_project_status || true)"
  human_required="$(read_human_required || true)"
  validation_status="$(read_validation_status || true)"

  if [[ "$project_status" == "paused" ]]; then
    echo "project_status=paused"
    return 0
  fi
  if [[ "$human_required" == "true" ]]; then
    echo "human_input.required=true"
    return 0
  fi
  if [[ "$validation_status" == "pass" ]]; then
    echo "last_validation.status=pass"
    return 0
  fi
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tick-command)
      TICK_COMMAND="${2:-}"
      shift 2
      ;;
    --mode)
      MODE="${2:-skill}"
      shift 2
      ;;
    --agent-command)
      AGENT_COMMAND="${2:-}"
      shift 2
      ;;
    --max-iterations)
      MAX_ITERATIONS="${2:-20}"
      shift 2
      ;;
    --sleep-seconds)
      SLEEP_SECONDS="${2:-1}"
      shift 2
      ;;
    --auto-init-state)
      AUTO_INIT_STATE=1
      shift
      ;;
    --skip-bootstrap-check)
      SKIP_BOOTSTRAP_CHECK=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "$MODE" != "skill" && "$MODE" != "legacy" ]]; then
  echo "ERROR: --mode must be 'skill' or 'legacy'." >&2
  usage
  exit 1
fi

if [[ ! -f "$STATE_PATH" ]]; then
  if [[ "$AUTO_INIT_STATE" == "1" ]]; then
    create_state_file
    echo "Initialized $STATE_PATH"
  else
    echo "ERROR: Missing $STATE_PATH. Re-run with --auto-init-state." >&2
    exit 1
  fi
fi

if [[ "$MODE" == "skill" ]]; then
  SKILL_FLOW="check_state>intake>loop"
  for p in ai/SKILL_CHECK_STATE.prompt.md ai/SKILL_INTAKE.prompt.md ai/SKILL_LOOP.prompt.md ai/SKILL_BOOTSTRAP.prompt.md; do
    if [[ ! -f "$p" ]]; then
      echo "ERROR: missing required skill prompt: $p" >&2
      exit 1
    fi
  done

  if [[ "$SKIP_BOOTSTRAP_CHECK" == "0" ]]; then
    if [[ ! -f ".claude/skills.local/README.md" ]]; then
      BOOTSTRAP_READY="false"
      echo "ERROR: Missing .claude/skills.local/README.md. Run bootstrap first: follow ai/SKILL_BOOTSTRAP.prompt.md" >&2
      exit 1
    fi
    BOOTSTRAP_READY="true"
  else
    BOOTSTRAP_READY="skipped"
  fi

  if [[ -z "$TICK_COMMAND" ]]; then
    if [[ -z "$AGENT_COMMAND" ]]; then
      echo "ERROR: in --mode skill provide either --tick-command or --agent-command." >&2
      usage
      exit 1
    fi
    TICK_COMMAND="$(build_skill_tick_command "$AGENT_COMMAND")"
  fi
else
  if [[ -z "$TICK_COMMAND" ]]; then
    echo "ERROR: --tick-command is required in --mode legacy." >&2
    usage
    exit 1
  fi
fi

echo "Autonomous loop start"
echo "Mode: $MODE"
echo "Tick command: $TICK_COMMAND"
echo "Max iterations: $MAX_ITERATIONS"

# Initialize tick log if missing
if [[ ! -f "$TICK_LOG" ]]; then
  mkdir -p "$(dirname "$TICK_LOG")"
  touch "$TICK_LOG"
fi

# Detect if previous loop run ended with human_input pause — record resume
loop_start_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
loop_start_epoch="$(date -u +%s)"
if grep -q '"type":"human_pause"' "$TICK_LOG" 2>/dev/null; then
  # Find last pause that has no matching resume
  last_pause_epoch="$(grep '"type":"human_pause"' "$TICK_LOG" | sed 's/.*"paused_epoch":\([0-9]*\).*/\1/' | tail -n1)"
  last_resume_epoch="$(grep '"type":"human_resume"' "$TICK_LOG" | sed 's/.*"resumed_epoch":\([0-9]*\).*/\1/' | tail -n1)"
  if [[ -n "$last_pause_epoch" && ( -z "$last_resume_epoch" || "$last_pause_epoch" -gt "$last_resume_epoch" ) ]]; then
    review_duration=$(( loop_start_epoch - last_pause_epoch ))
    printf '{"type":"human_resume","resumed_utc":"%s","resumed_epoch":%s,"review_duration_seconds":%s}\n' \
      "$loop_start_utc" "$loop_start_epoch" "$review_duration" >> "$TICK_LOG"
    echo "Detected human resume after ${review_duration}s review pause."
  fi
fi

for ((i=1; i<=MAX_ITERATIONS; i++)); do
  if reason="$(stop_reason)"; then
    echo "Stop before iteration $i: $reason"
    break
  fi

  echo "Iteration $i/$MAX_ITERATIONS"
  focus_type_before="$(read_focus_type || true)"
  focus_ref_before="$(read_focus_ref_id || true)"
  validation_status_before="$(read_validation_status || true)"
  tick_start_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  tick_start_epoch="$(date -u +%s)"
  tick_exit=0

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[dry-run] Would execute tick command."
  else
    bash -lc "$TICK_COMMAND" || tick_exit=$?
  fi

  tick_end_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  tick_end_epoch="$(date -u +%s)"
  tick_duration=$(( tick_end_epoch - tick_start_epoch ))
  focus_type_after="$(read_focus_type || true)"
  focus_ref_after="$(read_focus_ref_id || true)"
  validation_status_after="$(read_validation_status || true)"

  # Append external tick timing (model-agnostic)
  printf '{"type":"tick","tick":%s,"started_utc":"%s","ended_utc":"%s","duration_seconds":%s,"exit_code":%s,"mode":"%s","skill_flow":"%s","bootstrap_ready":"%s","focus_type_before":"%s","focus_ref_id_before":"%s","focus_type_after":"%s","focus_ref_id_after":"%s","validation_status_before":"%s","validation_status_after":"%s"}\n' \
    "$i" "$tick_start_utc" "$tick_end_utc" "$tick_duration" "$tick_exit" "$MODE" "$SKILL_FLOW" "$BOOTSTRAP_READY" "$focus_type_before" "$focus_ref_before" "$focus_type_after" "$focus_ref_after" "$validation_status_before" "$validation_status_after" >> "$TICK_LOG"

  if [[ "$tick_exit" -ne 0 ]]; then
    echo "Tick command exited with code $tick_exit" >&2
  fi

  sleep "$SLEEP_SECONDS"

  if reason="$(stop_reason)"; then
    echo "Stop after iteration $i: $reason"
    # Record human_input pause so next loop run can calculate review duration
    if [[ "$reason" == "human_input.required=true" ]]; then
      pause_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      pause_epoch="$(date -u +%s)"
      printf '{"type":"human_pause","paused_utc":"%s","paused_epoch":%s,"stop_reason":"%s"}\n' \
        "$pause_utc" "$pause_epoch" "$reason" >> "$TICK_LOG"
    fi
    break
  fi

  if [[ "$i" -eq "$MAX_ITERATIONS" ]]; then
    echo "Reached max iterations ($MAX_ITERATIONS) without stop condition."
  fi
done

echo "Autonomous loop finished."
