#!/usr/bin/env bash
set -euo pipefail

STATE_PATH="docs/ai/STATE.yaml"
TICK_LOG="docs/ai/LOOP_TICKS.jsonl"
TICK_COMMAND=""
MODE="skill"
AGENT_COMMAND=""
MAX_ITERATIONS=20
MAX_RUN_SECONDS=0
STAGNATION_LIMIT=3
RECOVERY_ENABLED=1
PROPOSE_ONLY=0
PROPOSE_BRANCH=""
SLEEP_SECONDS=1
AUTO_INIT_STATE=0
SKIP_BOOTSTRAP_CHECK=0
DRY_RUN=0
SKILL_FLOW="none"
BOOTSTRAP_READY="unknown"

usage() {
  cat <<'EOF'
Usage:
  ./.aai/scripts/autonomous-loop.sh [options]

Options:
  --mode skill|legacy         skill (default) runs SKILL_CHECK_STATE -> SKILL_INTAKE -> SKILL_LOOP
  --agent-command "<command>" Agent binary used in skill mode (example: codex)
  --tick-command "<command>"  Explicit command that performs one autonomous tick
  --max-iterations N          Maximum loop iterations (default: 20)
  --max-run-seconds N         Cumulative wall-clock budget across ticks; escalate to HITL when exceeded (default: 0 = unlimited)
  --stagnation-limit N        Consecutive no-progress ticks before HITL escalation (default: 3)
  --no-recovery               Skip the fresh-context recovery attempt; escalate to HITL immediately on stagnation
  --propose-only              Unattended-safe: isolate work on a fresh branch, hard-block any push during the
                              run, and print a review summary at the end. Recommended for scheduled/overnight runs.
  --propose-branch NAME       Branch name to use for --propose-only (default: aai/loop-<UTC timestamp>); implies --propose-only
  --sleep-seconds N           Sleep between iterations (default: 1)
  --auto-init-state           Create docs/ai/STATE.yaml if missing
  --skip-bootstrap-check      Skip check for .claude/skills/AAI_DYNAMIC_SKILLS.md
  --dry-run                   Do not execute tick command
EOF
}

build_skill_tick_command() {
  local cmd="$1"
  printf "%s --prompt-file .aai/SKILL_CHECK_STATE.prompt.md; %s --prompt-file .aai/SKILL_INTAKE.prompt.md; %s --prompt-file .aai/SKILL_LOOP.prompt.md" \
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
    --max-run-seconds)
      MAX_RUN_SECONDS="${2:-0}"
      shift 2
      ;;
    --stagnation-limit)
      STAGNATION_LIMIT="${2:-3}"
      shift 2
      ;;
    --no-recovery)
      RECOVERY_ENABLED=0
      shift
      ;;
    --propose-only)
      PROPOSE_ONLY=1
      shift
      ;;
    --propose-branch)
      PROPOSE_BRANCH="${2:-}"
      PROPOSE_ONLY=1
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
  for p in .aai/SKILL_CHECK_STATE.prompt.md .aai/SKILL_INTAKE.prompt.md .aai/SKILL_LOOP.prompt.md .aai/SKILL_BOOTSTRAP.prompt.md; do
    if [[ ! -f "$p" ]]; then
      echo "ERROR: missing required skill prompt: $p" >&2
      exit 1
    fi
  done

  if [[ "$SKIP_BOOTSTRAP_CHECK" == "0" ]]; then
    if [[ ! -f ".claude/skills/AAI_DYNAMIC_SKILLS.md" ]]; then
      BOOTSTRAP_READY="false"
      echo "ERROR: Missing .claude/skills/AAI_DYNAMIC_SKILLS.md. Run bootstrap first: follow .aai/SKILL_BOOTSTRAP.prompt.md" >&2
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

# Capture harness/runtime version ONCE so a behavior regression can be correlated
# with a runtime upgrade (version drift). Prefer the Claude CLI; fall back to the
# configured agent command identifier, then "unknown". Sanitize for JSON.
harness_version="$(claude --version 2>/dev/null | head -n1 || true)"
[[ -z "$harness_version" ]] && harness_version="${AGENT_COMMAND:-}"
[[ -z "$harness_version" ]] && harness_version="unknown"
harness_version="${harness_version//\"/}"
harness_version="${harness_version//$'\n'/ }"

# Propose-only (unattended-safe): isolate all work on a dedicated branch and
# HARD-block any push for the duration of the run, so an overnight loop can never
# ship unreviewed changes. The runner itself never pushes/merges; the pre-push
# hook additionally stops the agent from doing so. A review summary is printed at
# the end. The hook is restored on exit (success, error, or Ctrl-C).
ORIG_BRANCH=""
HOOK_PATH=""
HOOK_BAK=""
cleanup_propose() {
  [[ -z "$HOOK_PATH" ]] && return 0
  rm -f "$HOOK_PATH"
  [[ -n "$HOOK_BAK" && -f "$HOOK_BAK" ]] && mv "$HOOK_BAK" "$HOOK_PATH"
}
if [[ "$PROPOSE_ONLY" == "1" ]]; then
  if ! command -v git >/dev/null 2>&1 || ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: --propose-only requires a git work tree." >&2
    exit 1
  fi
  ORIG_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo detached)"
  [[ -z "$PROPOSE_BRANCH" ]] && PROPOSE_BRANCH="aai/loop-$(date -u +%Y%m%d-%H%M%SZ)"
  if git checkout -b "$PROPOSE_BRANCH" >/dev/null 2>&1 || git checkout "$PROPOSE_BRANCH" >/dev/null 2>&1; then
    echo "Propose-only: working on branch '$PROPOSE_BRANCH' (base: $ORIG_BRANCH). Runner will not push or merge."
  else
    echo "ERROR: --propose-only could not create/checkout branch '$PROPOSE_BRANCH'." >&2
    exit 1
  fi
  HOOK_PATH="$(git rev-parse --git-path hooks/pre-push)"
  if [[ -f "$HOOK_PATH" ]]; then HOOK_BAK="$HOOK_PATH.aai-bak"; mv "$HOOK_PATH" "$HOOK_BAK"; fi
  mkdir -p "$(dirname "$HOOK_PATH")"
  cat > "$HOOK_PATH" <<'HOOK'
#!/bin/sh
echo "AAI propose-only: push blocked during the autonomous loop. Review the branch, then push/merge manually." >&2
exit 1
HOOK
  chmod +x "$HOOK_PATH"
  trap cleanup_propose EXIT
fi

echo "Autonomous loop start"
echo "Mode: $MODE"
echo "Tick command: $TICK_COMMAND"
echo "Max iterations: $MAX_ITERATIONS"
[[ "$MAX_RUN_SECONDS" -gt 0 ]] && echo "Max run seconds: $MAX_RUN_SECONDS"
echo "Stagnation limit: $STAGNATION_LIMIT"
echo "Harness version: $harness_version"
[[ "$PROPOSE_ONLY" == "1" ]] && echo "Propose-only: ON (branch=$PROPOSE_BRANCH)"

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

stagnation_count=0
recovery_attempted=0
for ((i=1; i<=MAX_ITERATIONS; i++)); do
  if reason="$(stop_reason)"; then
    echo "Stop before iteration $i: $reason"
    break
  fi

  # Run budget (wall-clock): a loop that runs N times costs N prompts that each
  # keep getting bigger. Bound the run so an unattended loop can't burn unbounded
  # cost — escalate to HITL instead of starting another (more expensive) tick.
  if [[ "$MAX_RUN_SECONDS" -gt 0 ]]; then
    elapsed=$(( $(date -u +%s) - loop_start_epoch ))
    if [[ "$elapsed" -ge "$MAX_RUN_SECONDS" ]]; then
      echo "Stop before iteration $i: run budget exhausted (${elapsed}s >= ${MAX_RUN_SECONDS}s wall-clock)" >&2
      echo "  Human decision required: raise --max-run-seconds or narrow scope, then re-run." >&2
      bud_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      bud_epoch="$(date -u +%s)"
      printf '{"type":"human_pause","paused_utc":"%s","paused_epoch":%s,"stop_reason":"run budget exhausted: %ss wall-clock >= %ss"}\n' \
        "$bud_utc" "$bud_epoch" "$elapsed" "$MAX_RUN_SECONDS" >> "$TICK_LOG"
      break
    fi
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

  # No-progress guard: a tick made no forward progress if both focus and
  # validation status are unchanged. Reset the counter as soon as either moves.
  if [[ "$focus_ref_after" == "$focus_ref_before" && "$validation_status_after" == "$validation_status_before" ]]; then
    stagnation_count=$(( stagnation_count + 1 ))
  else
    stagnation_count=0
  fi

  # Append external tick timing (model-agnostic). harness_version enables
  # version-drift correlation; stagnation_count makes the no-progress run visible.
  printf '{"type":"tick","tick":%s,"started_utc":"%s","ended_utc":"%s","duration_seconds":%s,"exit_code":%s,"mode":"%s","skill_flow":"%s","bootstrap_ready":"%s","harness_version":"%s","focus_type_before":"%s","focus_ref_id_before":"%s","focus_type_after":"%s","focus_ref_id_after":"%s","validation_status_before":"%s","validation_status_after":"%s","stagnation_count":%s}\n' \
    "$i" "$tick_start_utc" "$tick_end_utc" "$tick_duration" "$tick_exit" "$MODE" "$SKILL_FLOW" "$BOOTSTRAP_READY" "$harness_version" "$focus_type_before" "$focus_ref_before" "$focus_type_after" "$focus_ref_after" "$validation_status_before" "$validation_status_after" "$stagnation_count" >> "$TICK_LOG"

  if [[ "$tick_exit" -ne 0 ]]; then
    echo "Tick command exited with code $tick_exit" >&2
  fi

  # Stagnation handling. A stuck scope is most often context rot, not a genuinely
  # impossible task — so before escalating to a human, try ONE fresh-context
  # recovery tick: a brand-new agent process (cold context) re-derives state from
  # the filesystem (STATE.yaml + canonical prompts) and is told via AAI_RECOVERY=1
  # that the loop is stuck, so it should re-read and change approach. Only if that
  # also makes no progress do we escalate to HITL — never burn the remaining budget.
  if [[ "$stagnation_count" -ge "$STAGNATION_LIMIT" ]]; then
    if [[ "$RECOVERY_ENABLED" == "1" && "$recovery_attempted" -eq 0 ]]; then
      recovery_attempted=1
      echo "Stagnation at limit — attempting one fresh-context recovery tick (AAI_RECOVERY=1) before HITL." >&2
      rec_focus_before="$focus_ref_after"
      rec_val_before="$validation_status_after"
      rec_start_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      rec_exit=0
      if [[ "$DRY_RUN" == "1" ]]; then
        echo "[dry-run] Would execute recovery tick."
      else
        AAI_RECOVERY=1 bash -lc "$TICK_COMMAND" || rec_exit=$?
      fi
      rec_end_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      rec_focus_after="$(read_focus_ref_id || true)"
      rec_val_after="$(read_validation_status || true)"
      printf '{"type":"recovery","tick":%s,"started_utc":"%s","ended_utc":"%s","exit_code":%s,"focus_ref_id_before":"%s","focus_ref_id_after":"%s","validation_status_before":"%s","validation_status_after":"%s"}\n' \
        "$i" "$rec_start_utc" "$rec_end_utc" "$rec_exit" "$rec_focus_before" "$rec_focus_after" "$rec_val_before" "$rec_val_after" >> "$TICK_LOG"
      if [[ "$rec_focus_after" != "$rec_focus_before" || "$rec_val_after" != "$rec_val_before" ]]; then
        echo "Recovery made progress — resetting stagnation counter and continuing." >&2
        stagnation_count=0
        recovery_attempted=0
        sleep "$SLEEP_SECONDS"
        continue
      fi
      echo "Recovery made no progress — escalating to HITL." >&2
    fi
    # Escalate: a stuck scope needs a changed prompt/scope from a human, not more
    # spins. Stop instead of burning the remaining iteration budget.
    echo "Stop after iteration $i: stagnation ($stagnation_count consecutive no-progress ticks >= limit $STAGNATION_LIMIT)" >&2
    echo "  Human decision required: change the prompt or scope, then re-run. Loop will not spin further." >&2
    stag_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    stag_epoch="$(date -u +%s)"
    printf '{"type":"human_pause","paused_utc":"%s","paused_epoch":%s,"stop_reason":"stagnation: %s consecutive no-progress ticks (recovery_attempted=%s)"}\n' \
      "$stag_utc" "$stag_epoch" "$stagnation_count" "$recovery_attempted" >> "$TICK_LOG"
    break
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

if [[ "$PROPOSE_ONLY" == "1" ]]; then
  commits="$(git rev-list --count "$ORIG_BRANCH..$PROPOSE_BRANCH" 2>/dev/null || echo '?')"
  echo "--- Propose-only review summary ---"
  echo "  Branch: $PROPOSE_BRANCH (base: $ORIG_BRANCH)"
  echo "  Commits ahead of base: $commits"
  git --no-pager diff --stat "$ORIG_BRANCH..$PROPOSE_BRANCH" 2>/dev/null | sed 's/^/  /' || true
  echo "  Nothing was pushed or merged. Review the branch, then merge/push when ready."
fi

# Wake-up digest: one human-readable summary of this run (best-effort).
if command -v node >/dev/null 2>&1 && [ -f .aai/scripts/loop-digest.mjs ]; then
  echo
  node .aai/scripts/loop-digest.mjs --write 2>/dev/null || true
fi

echo "Autonomous loop finished."
