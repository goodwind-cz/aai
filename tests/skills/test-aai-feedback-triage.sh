#!/usr/bin/env bash
#
# Test: RFC-0012 Phase 2 / RFC-0013 Slice B — offline triage engine
# (.aai/scripts/aai-feedback-triage.mjs), TEST-001..014.
#
# Offline triage: read the friction spool, hard-gate, score from v2 signals with a
# v1 recurrence fallback, cluster by fingerprint, write a LOCAL report. No network.

set -u
TEST_NAME="test-aai-feedback-triage"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Pipe-free payload assertions (spec-assertions-must-not-die-on-their-own-payload).
# shellcheck source=lib/assert-payload.sh
. "$SCRIPT_DIR/lib/assert-payload.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"
PROFILES="$PROJECT_ROOT/.aai/system/PROFILES.yaml"
SCRIPT="$PROJECT_ROOT/.aai/scripts/aai-feedback-triage.mjs"

cleanup() {
  if [ -n "${KEEP_TEST_DIR:-}" ]; then echo "INFO: keeping $TEST_DIR"
  elif [ -n "${TEST_DIR:-}" ] && [ -d "$TEST_DIR" ]; then rm -rf "$TEST_DIR"; fi
}
trap cleanup EXIT
log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_info() { echo "INFO: $*"; }
log_skip() { echo "SKIP: $*"; exit 42; }

command -v node >/dev/null 2>&1 || log_skip "node not found"

setup() { TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-triage-test.XXXXXX")"; }

# obs <fingerprint> <failure_class> [extra json members, comma-prefixed]
obs() {
  local fp="$1" fc="$2" extra="${3:-}"
  printf '{"schema_version":2,"os_family":"macos","aai_pin":"unknown","node_major":22,"skill_id":"SKILL_TDD","skill_phase":"impl","failure_class":"%s","fingerprint":"%s"%s}\n' "$fc" "$fp" "$extra"
}
# report field readers (node stdlib)
rp() { node -e 'const r=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));const p=process.argv[2].split(".");let v=r;for(const k of p)v=v?.[k];process.stdout.write(v===undefined?"__UNDEF__":(typeof v==="object"?JSON.stringify(v):String(v)))' "$1" "$2"; }
# cluster field by fingerprint: clu <report> <fp> <field>
clu() { node -e 'const r=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));const c=r.clusters.find(x=>x.fingerprint===process.argv[2]);process.stdout.write(c?String(c[process.argv[3]]):"__NOCLUSTER__")' "$1" "$2" "$3"; }
run() { node "$SCRIPT" --spool "$1" --config "${2:-/nonexistent}" --out "$3" > "$TEST_DIR/out" 2> "$TEST_DIR/err"; echo $?; }

# --- TEST-001: hard gates drop with a named reason --------------------------
test_001_gates() {
  log_info "Test: each hard gate drops with a named reason (TEST-001)..."
  local sp="$TEST_DIR/s1"; local rep="$TEST_DIR/r1"
  { obs "v1:ok" "contract_violation"
    printf '{"schema_version":3,"failure_class":"contract_violation","fingerprint":"v1:badver"}\n'
    obs "v1:badclass" "NOT_A_CLASS"
    obs "v1:dirty" "contract_violation" ',"hostname":"leaked.example.com"'
  } > "$sp"
  [ "$(run "$sp" "" "$rep")" = "0" ] || log_fail "TEST-001: engine must exit 0"
  local reasons; reasons="$(rp "$rep" dropped)"
  assert_payload_contains "$reasons" "bad_schema_version" "TEST-001: must drop bad schema_version ($reasons)"
  assert_payload_contains "$reasons" "non_taxonomy_failure_class" "TEST-001: must drop non-taxonomy class ($reasons)"
  assert_payload_contains "$reasons" "unsanitized_key" "TEST-001: must drop an unsanitized key ($reasons)"
  [ "$(rp "$rep" kept)" = "1" ] || log_fail "TEST-001: exactly the one valid obs kept (got $(rp "$rep" kept))"
  log_pass "hard gates drop bad schema / non-taxonomy class / unsanitized key with reasons (TEST-001)"
}

# --- TEST-002: deterministic report -----------------------------------------
test_002_deterministic() {
  log_info "Test: same spool -> byte-identical report (TEST-002)..."
  local sp="$TEST_DIR/s2"
  { obs "v1:b" "deterministic_script_failure" ',"impact":"low"'
    obs "v1:a" "contract_violation" ',"impact":"high","confidence":"high","reproducible":true'
    obs "v1:a" "contract_violation" ',"impact":"medium"'
  } > "$sp"
  run "$sp" "" "$TEST_DIR/ra" >/dev/null; run "$sp" "" "$TEST_DIR/rb" >/dev/null
  diff "$TEST_DIR/ra" "$TEST_DIR/rb" >/dev/null || log_fail "TEST-002: report must be byte-identical across runs"
  log_pass "report is deterministic (byte-identical across runs) (TEST-002)"
}

# --- TEST-004/005: v2-signal scoring + v1 fallback --------------------------
test_004_v2_scoring() {
  log_info "Test: impact high scores strictly higher than low; v1 falls back to recurrence (TEST-004/005)..."
  local sp="$TEST_DIR/s4"; local rep="$TEST_DIR/r4"
  { obs "v1:hi" "contract_violation" ',"impact":"high"'
    obs "v1:lo" "contract_violation" ',"impact":"low"'
    printf '{"schema_version":1,"os_family":"macos","aai_pin":"unknown","node_major":22,"skill_id":"x","skill_phase":"y","failure_class":"contract_violation","fingerprint":"v1:v1r"}\n'
  } > "$sp"
  run "$sp" "" "$rep" >/dev/null
  local hi lo v1; hi="$(clu "$rep" v1:hi score)"; lo="$(clu "$rep" v1:lo score)"; v1="$(clu "$rep" v1:v1r score)"
  [ "$hi" -gt "$lo" ] || log_fail "TEST-004: impact high ($hi) must score > low ($lo)"
  [ "$v1" = "0" ] || log_fail "TEST-005: a v1 record (single, no v2 fields) scores 0 via recurrence fallback (got $v1)"
  log_pass "v2 impact scoring ordered (high>low); v1 recurrence fallback works (TEST-004/005)"
}

# --- TEST-006: fingerprint clustering ---------------------------------------
test_006_clustering() {
  log_info "Test: two same-fingerprint rows -> one cluster, recurrence 2 (TEST-006)..."
  local sp="$TEST_DIR/s6"; local rep="$TEST_DIR/r6"
  { obs "v1:dup" "contract_violation"; obs "v1:dup" "contract_violation"; } > "$sp"
  run "$sp" "" "$rep" >/dev/null
  [ "$(rp "$rep" clusters)" != "__UNDEF__" ] || log_fail "TEST-006: clusters missing"
  [ "$(clu "$rep" v1:dup recurrence)" = "2" ] || log_fail "TEST-006: recurrence must be 2 (got $(clu "$rep" v1:dup recurrence))"
  local n; n="$(node -e 'const r=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(String(r.clusters.length))' "$rep")"
  [ "$n" = "1" ] || log_fail "TEST-006: two same-fp rows -> exactly one cluster (got $n)"
  log_pass "clustering groups by fingerprint; recurrence counted (TEST-006)"
}

# --- TEST-007: threshold decision; nothing auto_publishable -----------------
test_007_decision_no_auto() {
  log_info "Test: decision honors threshold; NO cluster is auto_publishable (TEST-007)..."
  local sp="$TEST_DIR/s7"; local rep="$TEST_DIR/r7"
  { obs "v1:strong" "contract_violation" ',"impact":"high","confidence":"high","reproducible":true'
    obs "v1:weak" "contract_violation" ',"impact":"low"'
  } > "$sp"
  run "$sp" "" "$rep" >/dev/null
  [ "$(clu "$rep" v1:strong decision)" = "review_candidate" ] || log_fail "TEST-007: strong cluster -> review_candidate"
  [ "$(clu "$rep" v1:weak decision)" = "retain" ] || log_fail "TEST-007: weak cluster -> retain"
  if node -e 'const r=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.exit(r.clusters.some(c=>c.auto_publishable===true)?0:1)' "$rep"; then
    log_fail "TEST-007: NO cluster may be auto_publishable in this slice"
  fi
  log_pass "threshold decision correct; no cluster auto_publishable (TEST-007)"
}

# --- TEST-008: no network (static) ------------------------------------------
test_008_no_network_static() {
  log_info "Test: static — no network/gh/token in the engine source (TEST-008)..."
  [ -f "$SCRIPT" ] || log_fail "TEST-008: engine missing"
  local broad; broad="$(grep -inE 'require\(|http|https|fetch|net\.|dns|child_process|socket|gh |token' "$SCRIPT" | grep -vE 'no network|no token|GitHub token' || true)"
  [ -z "$broad" ] || log_fail "TEST-008: engine must have no network/token surface:
$broad"
  log_pass "engine is offline: no network/token surface (TEST-008)"
}

# --- TEST-009: offline runtime ----------------------------------------------
test_009_offline_runtime() {
  log_info "Test: runtime under an unroutable proxy -> exit 0, report written (TEST-009)..."
  local sp="$TEST_DIR/s9"; local rep="$TEST_DIR/r9"
  obs "v1:z" "contract_violation" > "$sp"
  local code=0
  HTTP_PROXY="http://10.255.255.1:9" HTTPS_PROXY="http://10.255.255.1:9" \
    http_proxy="http://10.255.255.1:9" https_proxy="http://10.255.255.1:9" \
    node "$SCRIPT" --spool "$sp" --out "$rep" >/dev/null 2>&1 || code=$?
  [ "$code" = "0" ] || log_fail "TEST-009: engine must run offline under a blocked proxy (exit $code)"
  [ -f "$rep" ] || log_fail "TEST-009: report must be written"
  log_pass "engine runs offline under an unroutable proxy (TEST-009)"
}

# --- TEST-010: local-only, no sendable payload / send path ------------------
test_010_local_only() {
  log_info "Test: local mode writes report only; no send/payload path (TEST-010)..."
  local sp="$TEST_DIR/s10"; local rep="$TEST_DIR/r10"
  obs "v1:l" "contract_violation" > "$sp"
  run "$sp" "" "$rep" >/dev/null
  [ "$(rp "$rep" mode)" = "local" ] || log_fail "TEST-010: default mode must be local"
  # No payload file is emitted beyond the report; and no send/publish code path.
  grep -qiE 'issue_payload|createIssue|POST|upsert|publish\(' "$SCRIPT" \
    && log_fail "TEST-010: no issue-send/upsert path may exist in this slice" || true
  log_pass "local mode summarizes only; no send/upsert path (TEST-010)"
}

# --- TEST-011: capture->triage seam (real records) --------------------------
test_011_capture_seam() {
  log_info "Test: real aai-friction v2+v1 records -> triage gates/scores/clusters (TEST-011)..."
  local friction="$PROJECT_ROOT/.aai/scripts/aai-friction.mjs"
  [ -f "$friction" ] || log_skip "aai-friction.mjs not present"
  local sd="$TEST_DIR/spooldir"; mkdir -p "$sd"
  local v2="$TEST_DIR/in2.json" v1="$TEST_DIR/in1.json"
  cat > "$v2" <<'JSON'
{"schema_version":2,"skill_id":"SKILL_TDD","skill_phase":"impl","failure_class":"contract_violation","expected_behavior":"x","observed_behavior":"y","impact":"high","confidence":"high","reproducible":true}
JSON
  cat > "$v1" <<'JSON'
{"schema_version":1,"skill_id":"SKILL_PR","skill_phase":"review","failure_class":"deterministic_script_failure","expected_behavior":"a","observed_behavior":"b"}
JSON
  AAI_FRICTION_SPOOL_DIR="$sd" node "$friction" record --input "$v2" >/dev/null 2>&1 || log_fail "TEST-011: v2 record failed"
  AAI_FRICTION_SPOOL_DIR="$sd" node "$friction" record --input "$v1" >/dev/null 2>&1 || log_fail "TEST-011: v1 record failed"
  local rep="$TEST_DIR/r11"
  [ "$(run "$sd/observations.jsonl" "" "$rep")" = "0" ] || log_fail "TEST-011: triage over the real spool must exit 0"
  [ "$(rp "$rep" kept)" = "2" ] || log_fail "TEST-011: both real records must pass the gates (kept=$(rp "$rep" kept))"
  local n; n="$(node -e 'const r=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(String(r.clusters.length))' "$rep")"
  [ "$n" = "2" ] || log_fail "TEST-011: two distinct fingerprints -> two clusters (got $n)"
  log_pass "capture->triage seam: real v2+v1 records gated/scored/clustered end-to-end (TEST-011)"
}

# --- TEST-012: fail-closed config -------------------------------------------
test_012_failclosed_config() {
  log_info "Test: malformed feedback.yaml -> local mode (TEST-012)..."
  local sp="$TEST_DIR/s12"; local rep="$TEST_DIR/r12"; local cfg="$TEST_DIR/bad.yaml"
  obs "v1:c" "contract_violation" > "$sp"
  printf 'triage:\n  mode: {this is: not valid\n' > "$cfg"
  [ "$(run "$sp" "$cfg" "$rep")" = "0" ] || log_fail "TEST-012: malformed config must not error"
  [ "$(rp "$rep" mode)" = "local" ] || log_fail "TEST-012: malformed config must fail closed to local (got $(rp "$rep" mode))"
  # a stray mode:auto outside triage: must not take effect
  printf 'other:\n  mode: auto\ntriage:\n  mode: local\n' > "$cfg"
  run "$sp" "$cfg" "$rep" >/dev/null
  [ "$(rp "$rep" mode)" = "local" ] || log_fail "TEST-012: mode must be read only under triage:"
  # PR review: mode nested DEEPER than a direct child (under thresholds) must NOT count
  printf 'triage:\n  thresholds:\n    mode: auto\n' > "$cfg"
  run "$sp" "$cfg" "$rep" >/dev/null
  [ "$(rp "$rep" mode)" = "local" ] || log_fail "TEST-012: a non-direct-child mode must be ignored (nesting scope)"
  # PR review: a malformed / unknown-key triage block forces local even with a valid mode present
  printf 'triage:\n  mode: auto\n  broken: [\n' > "$cfg"
  run "$sp" "$cfg" "$rep" >/dev/null
  [ "$(rp "$rep" mode)" = "local" ] || log_fail "TEST-012: a malformed triage block must fail closed to local"
  printf 'triage:\n  mode: auto\n  evil: yes\n' > "$cfg"
  run "$sp" "$cfg" "$rep" >/dev/null
  [ "$(rp "$rep" mode)" = "local" ] || log_fail "TEST-012: an unknown direct-child key must fail closed to local"
  # a syntactically valid, in-scope non-local mode IS adopted (parsed, no net effect here)
  printf 'triage:\n  mode: review\n' > "$cfg"
  run "$sp" "$cfg" "$rep" >/dev/null
  [ "$(rp "$rep" mode)" = "review" ] || log_fail "TEST-012: a valid in-scope mode:review must be adopted"
  log_pass "fail-closed config: nesting-scoped, malformed/unknown-key -> local; valid mode adopted (TEST-012)"
}

# --- TEST-013: profiles classification --------------------------------------
test_013_profiles() {
  log_info "Test: feedback-triage prompt + engine classified once under extended (TEST-013)..."
  [ -f "$PROFILES" ] || log_fail "TEST-013: PROFILES.yaml not found: $PROFILES"
  local extended_block n
  extended_block="$(awk '/^extended:/{cap=1; next} cap' "$PROFILES")"
  assert_payload_contains "$extended_block" ".aai/SKILL_FEEDBACK_TRIAGE.prompt.md" \
    "TEST-013: feedback-triage prompt must be classified under 'extended:' in PROFILES.yaml"
  assert_payload_contains "$extended_block" ".aai/scripts/aai-feedback-triage.mjs" \
    "TEST-013: feedback-triage engine must be classified under 'extended:' in PROFILES.yaml"
  n="$(grep -cF '  - .aai/SKILL_FEEDBACK_TRIAGE.prompt.md' "$PROFILES" || true)"
  [ "$n" = "1" ] || log_fail "TEST-013: feedback-triage prompt must be classified exactly once (got $n)"
  n="$(grep -cF '  - .aai/scripts/aai-feedback-triage.mjs' "$PROFILES" || true)"
  [ "$n" = "1" ] || log_fail "TEST-013: feedback-triage engine must be classified exactly once (got $n)"
  log_pass "feedback-triage prompt + engine classified once under extended (TEST-013)"
}

# --- TEST-014: harness key survives triage; out-of-set value normalizes -----
test_014_harness_key() {
  log_info "Test: harness key is allowed through the gate and closed-set normalized (TEST-014)..."
  local sp="$TEST_DIR/s14"; local rep="$TEST_DIR/r14"
  { obs "v1:harness-ok" "contract_violation" ',"harness":"codex"'
    obs "v1:harness-bogus" "contract_violation" ',"harness":"not-a-real-harness"'
  } > "$sp"
  [ "$(run "$sp" "" "$rep")" = "0" ] || log_fail "TEST-014: triage must exit 0"
  [ "$(rp "$rep" kept)" = "2" ] || log_fail "TEST-014: harness key must not be gated as unsanitized (kept=$(rp "$rep" kept))"
  [ "$(clu "$rep" v1:harness-ok harness)" = "codex" ] || \
    log_fail "TEST-014: an in-set harness value must pass through (got $(clu "$rep" v1:harness-ok harness))"
  [ "$(clu "$rep" v1:harness-bogus harness)" = "unknown" ] || \
    log_fail "TEST-014: an out-of-set harness value must normalize to unknown, not be rejected (got $(clu "$rep" v1:harness-bogus harness))"
  log_pass "harness key allowed through the gate; closed-set normalized, never rejected whole (TEST-014)"
}

# --- TEST-649 (Spec-AC-01): recurrence only promotes a cluster that already
# carries signal; a signal-free or confidence-only cluster stays retain no
# matter how large -----------------------------------------------------------
test_649_recurrence_only_promotes() {
  log_info "Test: recurrence bonus is gated on SIGNAL_FLOOR -- zero-signal and confidence-only clusters never become candidates by recurrence alone; a low/low cluster at recurrence 3 and a lone high/high observation both do (TEST-649)..."
  local sp="$TEST_DIR/s649"; local rep="$TEST_DIR/r649"
  local i
  {
    for i in $(seq 1 6); do obs "v1:zero" "contract_violation"; done
    for i in $(seq 1 20); do obs "v1:confonly" "contract_violation" ',"confidence":"low"'; done
    for i in $(seq 1 3); do obs "v1:lowlow" "contract_violation" ',"impact":"low","confidence":"low"'; done
    obs "v1:hihi" "contract_violation" ',"impact":"high","confidence":"high"'
  } > "$sp"
  [ "$(run "$sp" "" "$rep")" = "0" ] || log_fail "TEST-649: triage must exit 0"
  [ "$(clu "$rep" v1:zero decision)" = "retain" ] || \
    log_fail "TEST-649: six zero-signal observations of one fingerprint must NOT become a review candidate (got $(clu "$rep" v1:zero decision), score $(clu "$rep" v1:zero score))"
  [ "$(clu "$rep" v1:confonly decision)" = "retain" ] || \
    log_fail "TEST-649: twenty confidence-only observations of one fingerprint must NOT become a review candidate at any recurrence (got $(clu "$rep" v1:confonly decision), score $(clu "$rep" v1:confonly score))"
  [ "$(clu "$rep" v1:lowlow decision)" = "review_candidate" ] || \
    log_fail "TEST-649: three low/low observations of one fingerprint (recurrence 3, signal 2) must be a review candidate (got $(clu "$rep" v1:lowlow decision), score $(clu "$rep" v1:lowlow score))"
  [ "$(clu "$rep" v1:hihi decision)" = "review_candidate" ] || \
    log_fail "TEST-649: a single high/high observation must be a review candidate on signal alone (got $(clu "$rep" v1:hihi decision), score $(clu "$rep" v1:hihi score))"
  log_pass "recurrence promotes only a cluster whose own max signal already clears the floor (TEST-649)"
}

# --- TEST-650 (Spec-AC-01): RECURRENCE_CAP is pinned at 3, not the member
# count -----------------------------------------------------------------------
test_650_recurrence_cap_pinned() {
  log_info "Test: RECURRENCE_CAP is declared as 3 in the source, and a twelve-member low/low cluster scores exactly 5 -- the cap binds at 3, not at the twelve observations present (TEST-650)..."
  grep -qE '^const RECURRENCE_CAP = 3;' "$SCRIPT" || \
    log_fail "TEST-650: the source must declare RECURRENCE_CAP as 3 (static)"
  local sp="$TEST_DIR/s650"; local rep="$TEST_DIR/r650"
  local i
  { for i in $(seq 1 12); do obs "v1:dozen" "contract_violation" ',"impact":"low","confidence":"low"'; done
  } > "$sp"
  [ "$(run "$sp" "" "$rep")" = "0" ] || log_fail "TEST-650: triage must exit 0"
  [ "$(clu "$rep" v1:dozen score)" = "5" ] || \
    log_fail "TEST-650: a twelve-member low/low cluster must score exactly 5 (signal 2 + cap 3), not the member count (got $(clu "$rep" v1:dozen score))"
  log_pass "RECURRENCE_CAP pinned at 3; a twelve-member cluster scores 5, not the member count (TEST-650)"
}

# --- TEST-651 (Spec-AC-01): the delivered harness rendering in triage closes
# on its existing pin (TEST-014), proven to redden under mutation, never on a
# reading of the source. Wraps test_014_harness_key rather than duplicating
# its fixture -- running the real pin IS the proof. The inner call runs in a
# command substitution (a real subshell), so its own log_fail (which calls
# exit 1) only ends that subshell; this wrapper re-raises with its OWN
# TEST-651 id, because mutation-run.mjs attributes a redden by finding that
# literal id in a FAIL line, and the wrapped pin's failure only ever says
# TEST-014. --------------------------------------------------------------
test_651_harness_pin_still_bites() {
  log_info "TEST-651: replaying the existing harness pin (test_014_harness_key / TEST-014) under mutation -- the delivered harness rendering in triage closes on this proof, not a reading..."
  local out rc=0
  out="$(test_014_harness_key 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] || \
    log_fail "TEST-651: the existing harness pin (test_014_harness_key) failed under mutation:"$'\n'"$out"
  log_pass "TEST-651 the existing harness pin still bites under mutation"
}

main() {
  echo "=== $TEST_NAME ==="
  setup
  [ -f "$SCRIPT" ] || log_fail "engine missing: $SCRIPT"
  if [ $# -gt 0 ]; then
    declare -F "$1" >/dev/null || { echo "Unknown test: $1" >&2; exit 2; }
    "$1"; echo "=== $TEST_NAME: SELECTED PASSED ($1) ==="; return
  fi
  test_001_gates
  test_002_deterministic
  test_004_v2_scoring
  test_006_clustering
  test_007_decision_no_auto
  test_008_no_network_static
  test_009_offline_runtime
  test_010_local_only
  test_011_capture_seam
  test_012_failclosed_config
  test_013_profiles
  test_014_harness_key
  test_649_recurrence_only_promotes
  test_650_recurrence_cap_pinned
  test_651_harness_pin_still_bites
  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}
main "$@"
