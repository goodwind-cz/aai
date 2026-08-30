#!/usr/bin/env bash
#
# Test: RFC-0012 Phase 1 — local shadow-mode friction capture WIRING
# (docs/specs/SPEC-0079-spec-friction-shadow-capture-wiring.md, TEST-001..007).
#
# Phase 0 shipped the protocol + offline CLI. Phase 1 wires them into the skill
# surface as ONE canonical seam, inherited by every universal skill via the
# shared guide, enforced here with a negative control.
#
#   .aai/system/FRICTION_PROTOCOL.md  — gains a "## Skill wiring (shadow capture)"
#                                       section naming the record command + the
#                                       shadow best-effort/never-mask contract.
#   .aai/AGENTS.md                    — gains ONE thin inheriting pointer.
#   .aai/scripts/aai-friction.mjs     — the Phase-0 CLI the seam invokes.
#
# Test map:
#   TEST-001 (Spec-AC-01) protocol has the "Skill wiring" seam naming the exact
#                         record command, exactly once.
#   TEST-002 (Spec-AC-02) AGENTS.md carries a thin pointer to the seam (shadow
#                         capture + FRICTION_PROTOCOL.md), not a duplicated body.
#   TEST-003 (Spec-AC-03) negative control: deleting the seam section OR the
#                         AGENTS pointer makes the guard FAIL (has teeth).
#   TEST-004 (Spec-AC-04) seam states the shadow contract: best-effort, never
#                         masks the skill result, capture failure swallowed.
#   TEST-005 (Spec-AC-05) the seam introduces NO Phase-2 surface (no triage,
#                         feedback.yaml, upsert, review/auto mode).
#   TEST-006 (Spec-AC-06) companion: prompt-diet + layer-profiles suites green.
#   TEST-007 (Spec-AC-01) integration: the documented record command runs
#                         end-to-end -> exactly one spool line, exit 0.
#
# docs/specs/SPEC-0088-spec-friction-capture-default-on.md (friction-capture-
# default-on) appends suite-local TEST-008..016 below (existing TEST-001..007
# above are NOT renumbered — they cover the Phase 1 wiring spec). Each new
# case is annotated with the spec's own TEST-NNN id it satisfies:
#   TEST-008 (spec TEST-001) protocol seam enumerates the three deterministic
#                            hooks (validation FAIL, remediation dispatch,
#                            canon-file gate/lint/CI failure).
#   TEST-009 (spec TEST-002) VALIDATION + REMEDIATION each carry a grep-
#                            verifiable best-effort FRICTION HOOK pointer.
#   TEST-010 (spec TEST-003) SKILL_PR carries the CI-failure hook pointer;
#                            existing seam heading/record-command pins still
#                            pass.
#   TEST-011 (spec TEST-004) negative control: stripping the hook enumeration
#                            or any wired pointer fails the guard (teeth).
#   TEST-012 (spec TEST-005) SEAM A: documented record command with a v2
#                            AAI-owned fixture -> exactly one v2 spool line,
#                            exit 0.
#   TEST-013 (spec TEST-006) a fixture whose failure_class is outside the
#                            closed taxonomy is rejected non-zero, no line.
#   TEST-014 (spec TEST-007) SEAM B: a non-empty fixture spool run through the
#                            offline triage engine yields >=1 cluster.
#   TEST-015 (spec TEST-008) SKILL_WRAP_UP step 6 names the triage invocation
#                            + proposed-intake surfacing, keeps the empty-spool
#                            silence contract.
#   TEST-016 (spec TEST-009) negative control: a hook capture into an
#                            unwritable spool preserves the primary step's own
#                            exit code.

set -u

TEST_NAME="test-aai-friction-wiring"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Pipe-free payload assertions (spec-assertions-must-not-die-on-their-own-payload).
# shellcheck source=lib/assert-payload.sh
. "$SCRIPT_DIR/lib/assert-payload.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

SCRIPT="$PROJECT_ROOT/.aai/scripts/aai-friction.mjs"
PROTOCOL="$PROJECT_ROOT/.aai/system/FRICTION_PROTOCOL.md"
AGENTS="$PROJECT_ROOT/.aai/AGENTS.md"
PROMPT_DIET_TEST="$SCRIPT_DIR/test-aai-prompt-diet.sh"
LAYER_PROFILES_TEST="$SCRIPT_DIR/test-aai-layer-profiles.sh"

# The canonical seam markers Phase 1 introduces.
SEAM_HEADING="## Skill wiring (shadow capture)"
RECORD_CMD="node .aai/scripts/aai-friction.mjs record --input"

cleanup() {
  if [ -n "${KEEP_TEST_DIR:-}" ]; then
    echo "INFO: keeping fixture at $TEST_DIR"
  elif [ -n "${TEST_DIR:-}" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
}
trap cleanup EXIT

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git  >/dev/null 2>&1 || log_skip "git not found"
  [ -f "$PROMPT_DIET_TEST" ]    || log_fail "test-aai-prompt-diet.sh not found"
  [ -f "$LAYER_PROFILES_TEST" ] || log_fail "test-aai-layer-profiles.sh not found"
  # PROTOCOL / AGENTS / SCRIPT are intentionally NOT required here so the RED
  # phase fails on each TEST-xxx's own assertion (product_red), not a skip.
  log_pass "Dependencies checked"
}

setup_fixture() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-friction-wiring-test.XXXXXX")"
}

# Extract the "Skill wiring" seam section body (heading -> next "## " heading)
# from a protocol file. Prints nothing if the heading is absent.
extract_seam() {
  local file="$1"
  awk -v h="$SEAM_HEADING" '
    $0 == h { cap = 1; print; next }
    cap && /^## / { cap = 0 }
    cap { print }
  ' "$file"
}

# The guard predicate under test: exit 0 iff the seam is fully wired across the
# protocol file ($1) and the shared guide ($2). Used both on the live tree and,
# by TEST-003, on mutated copies to prove the guard has teeth.
seam_wired() {
  local protocol="$1" agents="$2"
  [ -f "$protocol" ] || return 1
  [ -f "$agents" ]   || return 1
  grep -qF "$SEAM_HEADING" "$protocol" || return 1
  grep -qF "$RECORD_CMD"   "$protocol" || return 1
  # AGENTS thin pointer: names the protocol seam + the shadow-capture concept.
  grep -qF "FRICTION_PROTOCOL.md" "$agents" || return 1
  grep -qi "shadow" "$agents"              || return 1
  grep -qi "friction" "$agents"            || return 1
  return 0
}

# --- TEST-001 (Spec-AC-01): protocol seam names the record command ----------

test_001_protocol_seam() {
  log_info "Test: FRICTION_PROTOCOL.md has the Skill wiring seam naming the record command (TEST-001)..."
  [ -f "$PROTOCOL" ] || log_fail "TEST-001: protocol file missing: $PROTOCOL"
  local n; n="$(grep -cF "$SEAM_HEADING" "$PROTOCOL" || true)"
  [ "$n" = "1" ] || log_fail "TEST-001: seam heading '$SEAM_HEADING' must appear exactly once (got $n)"
  grep -qF "$RECORD_CMD" "$PROTOCOL" \
    || log_fail "TEST-001: seam must name the exact record command '$RECORD_CMD'"
  log_pass "Protocol seam present and names the record command (TEST-001)"
}

# --- TEST-002 (Spec-AC-02): AGENTS.md thin inheriting pointer ---------------

test_002_agents_pointer() {
  log_info "Test: AGENTS.md carries a thin pointer to the shadow-capture seam (TEST-002)..."
  [ -f "$AGENTS" ] || log_fail "TEST-002: AGENTS.md missing: $AGENTS"
  grep -qF "FRICTION_PROTOCOL.md" "$AGENTS" \
    || log_fail "TEST-002: AGENTS.md must reference FRICTION_PROTOCOL.md"
  grep -qi "shadow" "$AGENTS" \
    || log_fail "TEST-002: AGENTS.md pointer must mention shadow capture"
  grep -qi "friction" "$AGENTS" \
    || log_fail "TEST-002: AGENTS.md pointer must mention friction"
  # DRY: the pointer must NOT duplicate the protocol body. The taxonomy table
  # header lives only in the protocol; assert it is absent from AGENTS.md.
  if grep -qF "failure_class" "$AGENTS"; then
    log_fail "TEST-002: AGENTS.md must POINT at the seam, not duplicate the protocol body (found 'failure_class')"
  fi
  log_pass "AGENTS.md thin inheriting pointer present, body not duplicated (TEST-002)"
}

# --- TEST-003 (Spec-AC-03): negative control (guard has teeth) --------------

test_003_negative_control() {
  log_info "Test: negative control — removing the seam or the pointer fails the guard (TEST-003)..."
  # Positive: the live tree is wired.
  seam_wired "$PROTOCOL" "$AGENTS" \
    || log_fail "TEST-003: live tree must be wired (positive control failed)"

  local p_mut="$TEST_DIR/protocol-no-seam.md"
  local a_mut="$TEST_DIR/agents-no-pointer.md"

  # Mutation 1: protocol with the whole seam section stripped.
  awk -v h="$SEAM_HEADING" '
    $0 == h { drop = 1; next }
    drop && /^## / { drop = 0 }
    drop { next }
    { print }
  ' "$PROTOCOL" > "$p_mut"
  if seam_wired "$p_mut" "$AGENTS"; then
    log_fail "TEST-003: guard passed with the protocol seam removed (no teeth)"
  fi

  # Mutation 2: AGENTS.md with every FRICTION_PROTOCOL.md reference removed.
  grep -v "FRICTION_PROTOCOL.md" "$AGENTS" > "$a_mut"
  if seam_wired "$PROTOCOL" "$a_mut"; then
    log_fail "TEST-003: guard passed with the AGENTS pointer removed (no teeth)"
  fi

  log_pass "Negative control: guard fails when either side of the seam is removed (TEST-003)"
}

# --- TEST-004 (Spec-AC-04): shadow best-effort / never-mask contract --------

test_004_shadow_contract() {
  log_info "Test: seam documents the shadow best-effort / never-mask / swallow contract (TEST-004)..."
  local seam; seam="$(extract_seam "$PROTOCOL")"
  [ -n "$seam" ] || log_fail "TEST-004: seam section is empty or missing"
  printf '%s' "$seam" | grep -qi "best-effort" \
    || log_fail "TEST-004: seam must state capture is best-effort"
  printf '%s' "$seam" | grep -qiE "never (mask|change)|must not (mask|change|replace)" \
    || log_fail "TEST-004: seam must state capture never masks/changes the skill result"
  printf '%s' "$seam" | grep -qi "swallow" \
    || log_fail "TEST-004: seam must state a capture failure is swallowed"
  log_pass "Seam documents the shadow best-effort / never-mask / swallow contract (TEST-004)"
}

# --- TEST-005 (Spec-AC-05): no Phase-2 surface introduced -------------------

test_005_no_phase2_surface() {
  log_info "Test: seam introduces no Phase-2 (triage/upsert/config) surface (TEST-005)..."
  local seam; seam="$(extract_seam "$PROTOCOL")"
  [ -n "$seam" ] || log_fail "TEST-005: seam section is empty or missing"
  local forbidden="aai-feedback-triage feedback.yaml upsert"
  local tok
  for tok in $forbidden; do
    if printf '%s' "$seam" | grep -qiF "$tok"; then
      log_fail "TEST-005: seam must not introduce Phase-2 surface token '$tok'"
    fi
  done
  # No GitHub/network invocation wired into the seam.
  if printf '%s' "$seam" | grep -qE '(^|[^a-zA-Z])gh (issue|pr|api)'; then
    log_fail "TEST-005: seam must not wire a gh network call"
  fi
  log_pass "Seam introduces no Phase-2 surface (TEST-005)"
}

# --- TEST-006 (Spec-AC-06): companion suites green --------------------------

test_006_companion_suites() {
  log_info "Test: companion prompt-diet + layer-profiles suites green (TEST-006)..."
  local out code
  out="$(bash "$PROMPT_DIET_TEST" 2>&1)"; code=$?
  [ "$code" = "0" ] || log_fail "TEST-006: test-aai-prompt-diet.sh must pass (exit $code): $(printf '%s' "$out" | tail -3)"
  out="$(bash "$LAYER_PROFILES_TEST" 2>&1)"; code=$?
  [ "$code" = "0" ] || log_fail "TEST-006: test-aai-layer-profiles.sh must pass (exit $code): $(printf '%s' "$out" | tail -3)"
  log_pass "Companion prompt-diet + layer-profiles suites green (TEST-006)"
}

# --- TEST-007 (Spec-AC-01, integration): documented command runs e2e --------

test_007_documented_command_runs() {
  log_info "Test: the documented record command runs end-to-end -> one spool line, exit 0 (TEST-007)..."
  [ -f "$SCRIPT" ] || log_fail "TEST-007: capture CLI missing: $SCRIPT"
  local sp="$TEST_DIR/sp007"; mkdir -p "$sp"
  local spool="$sp/observations.jsonl"
  local input="$TEST_DIR/wf007.json"
  cat > "$input" <<'JSON'
{
  "schema_version": 1,
  "skill_id": "SKILL_TDD",
  "skill_phase": "implementation",
  "failure_class": "deterministic_script_failure",
  "expected_behavior": "the documented seam command records one observation",
  "observed_behavior": "verifying the prose->CLI seam end-to-end"
}
JSON
  # Invoke exactly the command form the seam documents.
  local code=0
  AAI_FRICTION_SPOOL_DIR="$sp" node "$SCRIPT" record --input "$input" \
    > "$TEST_DIR/o007" 2> "$TEST_DIR/e007" || code=$?
  [ "$code" = "0" ] || log_fail "TEST-007: documented command must exit 0 (got $code): $(cat "$TEST_DIR/e007")"
  local n; n="$(grep -c . "$spool" 2>/dev/null || echo 0)"
  [ "$n" = "1" ] || log_fail "TEST-007: expected exactly 1 spool line (got $n)"
  log_pass "Documented record command runs end-to-end: one spool line, exit 0 (TEST-007)"
}

# =============================================================================
# friction-capture-default-on: TEST-008..016 (suite-local; spec ids annotated)
# =============================================================================

FEEDBACK_TRIAGE_SCRIPT="$PROJECT_ROOT/.aai/scripts/aai-feedback-triage.mjs"
VALIDATION_PROMPT="$PROJECT_ROOT/.aai/VALIDATION.prompt.md"
REMEDIATION_PROMPT="$PROJECT_ROOT/.aai/REMEDIATION.prompt.md"
SKILL_PR_PROMPT="$PROJECT_ROOT/.aai/SKILL_PR.prompt.md"
SKILL_WRAP_UP_PROMPT="$PROJECT_ROOT/.aai/SKILL_WRAP_UP.prompt.md"

DETERMINISTIC_HEADING="### Deterministic hook points"
HOOK_MARKER="FRICTION HOOK"

# The guard predicate under test: exit 0 iff every deterministic hook is
# enumerated in the protocol AND every owning prompt carries a wired pointer.
# Used both on the live tree (positive control) and on mutated copies (TEST-011
# negative control) to prove the guard has teeth.
hooks_wired() {
  local protocol="$1" validation="$2" remediation="$3" skillpr="$4" implementation="${5:-}"
  [ -f "$protocol" ] || return 1
  grep -qF "$DETERMINISTIC_HEADING" "$protocol" || return 1
  grep -qi "validation FAIL" "$protocol"        || return 1
  grep -qi "remediation dispatch" "$protocol"   || return 1
  grep -qi "canon-file gate/lint/CI failure" "$protocol" || return 1
  grep -qi "canon-surface check failure" "$protocol"      || return 1
  local f
  for f in "$validation" "$remediation" "$skillpr"; do
    [ -f "$f" ] || return 1
    grep -qF "$HOOK_MARKER" "$f"           || return 1
    grep -qF "FRICTION_PROTOCOL.md" "$f"   || return 1
  done
  # 5th hook (validation residual-risk R2 remediation, 2026-07-26): the
  # IMPLEMENTATION canon-surface check-failure hook covers the headroom-cap
  # trap class. Optional param keeps existing 4-way mutation calls valid.
  if [ -n "$implementation" ]; then
    [ -f "$implementation" ] || return 1
    grep -qF "$HOOK_MARKER" "$implementation"         || return 1
    grep -qF "FRICTION_PROTOCOL.md" "$implementation" || return 1
    grep -qi "canon-surface check failure" "$implementation" || return 1
  fi
  return 0
}

# --- TEST-008 (spec TEST-001): protocol enumerates the three hooks ----------

test_008_hooks_enumerated() {
  log_info "Test: protocol seam enumerates the three deterministic hooks (TEST-008 / spec TEST-001)..."
  local seam; seam="$(extract_seam "$PROTOCOL")"
  [ -n "$seam" ] || log_fail "TEST-008: seam section is empty or missing"
  assert_payload_contains "$seam" "$DETERMINISTIC_HEADING" "TEST-008: seam must carry the '$DETERMINISTIC_HEADING' subsection"
  printf '%s' "$seam" | grep -qi "validation FAIL" \
    || log_fail "TEST-008: seam must name the validation-FAIL hook"
  printf '%s' "$seam" | grep -qi "remediation dispatch" \
    || log_fail "TEST-008: seam must name the remediation-dispatch hook"
  printf '%s' "$seam" | grep -qi "canon-file gate/lint/CI failure" \
    || log_fail "TEST-008: seam must name the canon-file gate/lint/CI failure hook"
  log_pass "Protocol seam enumerates all three deterministic hooks (TEST-008 / spec TEST-001)"
}

# --- TEST-009 (spec TEST-002): VALIDATION + REMEDIATION pointers ------------

test_009_validation_remediation_pointers() {
  log_info "Test: VALIDATION and REMEDIATION each carry a wired FRICTION HOOK pointer (TEST-009 / spec TEST-002)..."
  [ -f "$VALIDATION_PROMPT" ] || log_fail "TEST-009: $VALIDATION_PROMPT missing"
  [ -f "$REMEDIATION_PROMPT" ] || log_fail "TEST-009: $REMEDIATION_PROMPT missing"
  grep -qF "$HOOK_MARKER" "$VALIDATION_PROMPT" \
    || log_fail "TEST-009: VALIDATION.prompt.md must carry a '$HOOK_MARKER' pointer"
  grep -qF "FRICTION_PROTOCOL.md" "$VALIDATION_PROMPT" \
    || log_fail "TEST-009: VALIDATION.prompt.md pointer must name FRICTION_PROTOCOL.md"
  grep -qi "best-effort" "$VALIDATION_PROMPT" \
    || log_fail "TEST-009: VALIDATION.prompt.md pointer must state best-effort"
  grep -qF "$HOOK_MARKER" "$REMEDIATION_PROMPT" \
    || log_fail "TEST-009: REMEDIATION.prompt.md must carry a '$HOOK_MARKER' pointer"
  grep -qF "FRICTION_PROTOCOL.md" "$REMEDIATION_PROMPT" \
    || log_fail "TEST-009: REMEDIATION.prompt.md pointer must name FRICTION_PROTOCOL.md"
  grep -qi "best-effort" "$REMEDIATION_PROMPT" \
    || log_fail "TEST-009: REMEDIATION.prompt.md pointer must state best-effort"
  log_pass "VALIDATION + REMEDIATION carry wired best-effort FRICTION HOOK pointers (TEST-009 / spec TEST-002)"
}

# --- TEST-010 (spec TEST-003): SKILL_PR pointer + existing pins still pass --

test_010_skill_pr_pointer_and_pins() {
  log_info "Test: SKILL_PR carries the CI-failure hook pointer; existing seam pins still pass (TEST-010 / spec TEST-003)..."
  [ -f "$SKILL_PR_PROMPT" ] || log_fail "TEST-010: $SKILL_PR_PROMPT missing"
  grep -qF "$HOOK_MARKER" "$SKILL_PR_PROMPT" \
    || log_fail "TEST-010: SKILL_PR.prompt.md must carry a '$HOOK_MARKER' pointer"
  grep -qF "FRICTION_PROTOCOL.md" "$SKILL_PR_PROMPT" \
    || log_fail "TEST-010: SKILL_PR.prompt.md pointer must name FRICTION_PROTOCOL.md"
  grep -qi "best-effort" "$SKILL_PR_PROMPT" \
    || log_fail "TEST-010: SKILL_PR.prompt.md pointer must state best-effort"
  # Existing TEST-001 pins (seam heading exactly once + exact record command)
  # must be unregressed by the new subsection.
  local n; n="$(grep -cF "$SEAM_HEADING" "$PROTOCOL" || true)"
  [ "$n" = "1" ] || log_fail "TEST-010: seam heading must still appear exactly once (got $n)"
  grep -qF "$RECORD_CMD" "$PROTOCOL" \
    || log_fail "TEST-010: seam must still name the exact record command"
  log_pass "SKILL_PR carries the CI-failure hook pointer; TEST-001 pins unregressed (TEST-010 / spec TEST-003)"
}

# --- TEST-011 (spec TEST-004): negative control on the hook guard -----------

test_011_hooks_negative_control() {
  log_info "Test: negative control — stripping the hook enumeration or any pointer fails hooks_wired (TEST-011 / spec TEST-004)..."
  hooks_wired "$PROTOCOL" "$VALIDATION_PROMPT" "$REMEDIATION_PROMPT" "$SKILL_PR_PROMPT" "$PROJECT_ROOT/.aai/IMPLEMENTATION.prompt.md" \
    || log_fail "TEST-011: live tree must be wired (positive control failed)"

  local p_mut="$TEST_DIR/protocol-no-hooks.md"
  # Mutation: protocol with the deterministic-hooks subsection stripped
  # (it is the last subsection in the file -> strip from its heading to EOF).
  awk -v h="$DETERMINISTIC_HEADING" '
    index($0, h) == 1 { drop = 1 }
    !drop { print }
  ' "$PROTOCOL" > "$p_mut"
  if hooks_wired "$p_mut" "$VALIDATION_PROMPT" "$REMEDIATION_PROMPT" "$SKILL_PR_PROMPT"; then
    log_fail "TEST-011: guard passed with the hook enumeration removed (no teeth)"
  fi

  local v_mut="$TEST_DIR/validation-no-pointer.md"
  grep -v "$HOOK_MARKER" "$VALIDATION_PROMPT" > "$v_mut"
  if hooks_wired "$PROTOCOL" "$v_mut" "$REMEDIATION_PROMPT" "$SKILL_PR_PROMPT"; then
    log_fail "TEST-011: guard passed with the VALIDATION pointer removed (no teeth)"
  fi

  local r_mut="$TEST_DIR/remediation-no-pointer.md"
  grep -v "$HOOK_MARKER" "$REMEDIATION_PROMPT" > "$r_mut"
  if hooks_wired "$PROTOCOL" "$VALIDATION_PROMPT" "$r_mut" "$SKILL_PR_PROMPT"; then
    log_fail "TEST-011: guard passed with the REMEDIATION pointer removed (no teeth)"
  fi

  local s_mut="$TEST_DIR/skillpr-no-pointer.md"
  grep -v "$HOOK_MARKER" "$SKILL_PR_PROMPT" > "$s_mut"
  if hooks_wired "$PROTOCOL" "$VALIDATION_PROMPT" "$REMEDIATION_PROMPT" "$s_mut"; then
    log_fail "TEST-011: guard passed with the SKILL_PR pointer removed (no teeth)"
  fi

  log_pass "Negative control: guard fails when the hook enumeration or any pointer is removed (TEST-011 / spec TEST-004)"
}

# --- TEST-012 (spec TEST-005): SEAM A — v2 record end-to-end ----------------

test_012_v2_record_end_to_end() {
  log_info "Test: SEAM A — documented record command with a v2 fixture appends one v2 spool line, exit 0 (TEST-012 / spec TEST-005)..."
  [ -f "$SCRIPT" ] || log_fail "TEST-012: capture CLI missing: $SCRIPT"
  local sp="$TEST_DIR/sp012"; mkdir -p "$sp"
  local spool="$sp/observations.jsonl"
  local input="$TEST_DIR/hook012.json"
  cat > "$input" <<'JSON'
{
  "schema_version": 2,
  "skill_id": "SKILL_VALIDATION",
  "skill_phase": "validation",
  "failure_class": "deterministic_script_failure",
  "expected_behavior": "the hook records one v2 observation",
  "observed_behavior": "verifying the default-on hook end-to-end",
  "impact": "medium",
  "confidence": "high",
  "reproducible": true
}
JSON
  local code=0
  AAI_FRICTION_SPOOL_DIR="$sp" node "$SCRIPT" record --input "$input" \
    > "$TEST_DIR/o012" 2> "$TEST_DIR/e012" || code=$?
  [ "$code" = "0" ] || log_fail "TEST-012: documented command must exit 0 (got $code): $(cat "$TEST_DIR/e012")"
  local n; n="$(grep -c . "$spool" 2>/dev/null || echo 0)"
  [ "$n" = "1" ] || log_fail "TEST-012: expected exactly 1 spool line (got $n)"
  local keys
  keys="$(node -e 'const l=require("fs").readFileSync(process.argv[1],"utf8").trim();process.stdout.write(Object.keys(JSON.parse(l)).sort().join(","))' "$spool")"
  case ",$keys," in
    *",impact,"*) : ;;
    *) log_fail "TEST-012: v2 spool line must carry structured-signal key 'impact' (got: $keys)" ;;
  esac
  case ",$keys," in
    *",confidence,"*) : ;;
    *) log_fail "TEST-012: v2 spool line must carry structured-signal key 'confidence' (got: $keys)" ;;
  esac
  case ",$keys," in
    *",reproducible,"*) : ;;
    *) log_fail "TEST-012: v2 spool line must carry structured-signal key 'reproducible' (got: $keys)" ;;
  esac
  log_pass "SEAM A: documented record command, v2 fixture -> one v2 spool line, exit 0 (TEST-012 / spec TEST-005)"
}

# --- TEST-013 (spec TEST-006): excluded failure_class rejected --------------

test_013_excluded_class_rejected() {
  log_info "Test: a fixture with a non-taxonomy failure_class is rejected non-zero, no spool line (TEST-013 / spec TEST-006)..."
  local sp="$TEST_DIR/sp013"; mkdir -p "$sp"
  local spool="$sp/observations.jsonl"
  local input="$TEST_DIR/excl013.json"
  cat > "$input" <<'JSON'
{
  "schema_version": 2,
  "skill_id": "SKILL_VALIDATION",
  "skill_phase": "validation",
  "failure_class": "transient_provider_failure",
  "expected_behavior": "the hook only records AAI-owned classes",
  "observed_behavior": "an excluded, non-AAI class was offered to the hook"
}
JSON
  local code=0
  AAI_FRICTION_SPOOL_DIR="$sp" node "$SCRIPT" record --input "$input" \
    > "$TEST_DIR/o013" 2> "$TEST_DIR/e013" || code=$?
  [ "$code" != "0" ] || log_fail "TEST-013: excluded failure_class must be rejected (got exit 0)"
  local n; n="$(grep -c . "$spool" 2>/dev/null || echo 0)"
  [ "$n" = "0" ] || log_fail "TEST-013: excluded failure_class must not write a spool line (got $n)"
  log_pass "Excluded (non-taxonomy) failure_class rejected non-zero, no spool line (TEST-013 / spec TEST-006)"
}

# --- TEST-014 (spec TEST-007): SEAM B — spool through triage ----------------

test_014_wrapup_triage_seam_b() {
  log_info "Test: SEAM B — a non-empty fixture spool run through the triage engine yields >=1 cluster (TEST-014 / spec TEST-007)..."
  [ -f "$FEEDBACK_TRIAGE_SCRIPT" ] || log_fail "TEST-014: triage engine missing: $FEEDBACK_TRIAGE_SCRIPT"
  local sp="$TEST_DIR/spool014.jsonl"
  local report="$TEST_DIR/report014.json"
  cat > "$sp" <<'JSONL'
{"schema_version":2,"os_family":"macos","aai_pin":"unknown","node_major":22,"skill_id":"SKILL_VALIDATION","skill_phase":"validation","failure_class":"deterministic_script_failure","fingerprint":"v1:hook014test","impact":"high","confidence":"high","reproducible":true}
JSONL
  local code=0
  node "$FEEDBACK_TRIAGE_SCRIPT" --spool "$sp" --config "/nonexistent" --out "$report" \
    > "$TEST_DIR/o014" 2> "$TEST_DIR/e014" || code=$?
  [ "$code" = "0" ] || log_fail "TEST-014: triage engine must exit 0 (got $code): $(cat "$TEST_DIR/e014")"
  [ -f "$report" ] || log_fail "TEST-014: triage engine must write a report to $report"
  local n; n="$(node -e 'const r=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(String(r.clusters.length))' "$report")"
  [ "$n" -ge 1 ] || log_fail "TEST-014: report must contain at least one cluster from the non-empty fixture spool (got $n)"
  log_pass "SEAM B: non-empty fixture spool -> triage report with >=1 cluster (TEST-014 / spec TEST-007)"
}

# --- TEST-015 (spec TEST-008): SKILL_WRAP_UP step 6 wiring ------------------

test_015_wrapup_step6_wired() {
  log_info "Test: SKILL_WRAP_UP step 6 names the triage invocation + proposed-intake surfacing, empty stays silent (TEST-015 / spec TEST-008)..."
  [ -f "$SKILL_WRAP_UP_PROMPT" ] || log_fail "TEST-015: $SKILL_WRAP_UP_PROMPT missing"
  # Extract step 6's body (heading "6." to the next top-level numbered step).
  local step6
  step6="$(awk '
    /^6\. FRICTION FEEDBACK NUDGE/ { cap = 1; print; next }
    cap && /^6b\./ { cap = 0 }
    cap { print }
  ' "$SKILL_WRAP_UP_PROMPT")"
  [ -n "$step6" ] || log_fail "TEST-015: step 6 (FRICTION FEEDBACK NUDGE) section not found"
  assert_payload_contains "$step6" "aai-feedback-triage.mjs" "TEST-015: step 6 must name the triage engine aai-feedback-triage.mjs"
  printf '%s' "$step6" | grep -qi "proposed-intake" \
    || log_fail "TEST-015: step 6 must surface proposed-intake one-liners"
  printf '%s' "$step6" | grep -qi "review_candidate" \
    || log_fail "TEST-015: step 6 must name the review_candidate decision it lists"
  printf '%s' "$step6" | grep -qi "SILENT" \
    || log_fail "TEST-015: step 6 must keep the empty-spool SILENT contract documented"
  log_pass "SKILL_WRAP_UP step 6 names the triage invocation + proposed-intake, silence preserved (TEST-015 / spec TEST-008)"
}

# --- TEST-016 (spec TEST-009): negative control — unwritable spool ----------

test_016_unwritable_spool_negative_control() {
  log_info "Test: a hook capture into an unwritable spool preserves the primary step's own exit code (TEST-016 / spec TEST-009)..."
  local sp="$TEST_DIR/ro016"; mkdir -p "$sp"
  local input="$TEST_DIR/hook016.json"
  cat > "$input" <<'JSON'
{
  "schema_version": 2,
  "skill_id": "SKILL_VALIDATION",
  "skill_phase": "validation",
  "failure_class": "deterministic_script_failure",
  "expected_behavior": "the hook records one observation",
  "observed_behavior": "the spool directory is unwritable"
}
JSON
  # Root-safe blocked spool (PR #162 Codex P2): chmod a-w does not stop UID 0,
  # so nest the spool path under a regular FILE — writes fail with ENOTDIR
  # for every UID, root included.
  local blocked="$sp/blocker-file/spool"
  : > "$sp/blocker-file"
  # Setup sanity: the capture call itself must actually fail against the
  # blocked spool path, else this negative control would be vacuous.
  local cap_code=0
  AAI_FRICTION_SPOOL_DIR="$blocked" node "$SCRIPT" record --input "$input" \
    > "$TEST_DIR/cap016.out" 2> "$TEST_DIR/cap016.err" || cap_code=$?
  [ "$cap_code" != "0" ] \
    || log_fail "TEST-016: setup invalid — capture must actually fail against an unwritable spool dir"

  # Simulate the seam's documented best-effort hook pattern: a primary step
  # that already produced its own result (exit 4, e.g. a validation FAIL),
  # followed by a best-effort hook capture whose failure must be swallowed.
  simulate_hook_wrapped_step() {
    ( exit 4 )
    local primary_rc=$?
    AAI_FRICTION_SPOOL_DIR="$blocked" node "$SCRIPT" record --input "$input" >/dev/null 2>&1 || true
    return "$primary_rc"
  }
  local final_rc=0
  simulate_hook_wrapped_step || final_rc=$?
  [ "$final_rc" = "4" ] \
    || log_fail "TEST-016: capture failure at the hook must not change the primary step's exit code (got $final_rc, want 4)"
  log_pass "Capture failure into an unwritable spool preserves the primary step's own exit code (TEST-016 / spec TEST-009)"
}

main() {
  echo "=== $TEST_NAME ==="
  check_deps
  setup_fixture

  if [ $# -gt 0 ]; then
    "$1"
    echo "=== $TEST_NAME: SELECTED TEST PASSED ($1) ==="
    return
  fi

  test_001_protocol_seam
  test_002_agents_pointer
  test_003_negative_control
  test_004_shadow_contract
  test_005_no_phase2_surface
  test_006_companion_suites
  test_007_documented_command_runs

  test_008_hooks_enumerated
  test_009_validation_remediation_pointers
  test_010_skill_pr_pointer_and_pins
  test_011_hooks_negative_control
  test_012_v2_record_end_to_end
  test_013_excluded_class_rejected
  test_014_wrapup_triage_seam_b
  test_015_wrapup_step6_wired
  test_016_unwritable_spool_negative_control

  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}

main "$@"
