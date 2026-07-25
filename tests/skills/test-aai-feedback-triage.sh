#!/usr/bin/env bash
#
# Test: RFC-0012 Phase 2 / RFC-0013 Slice B — offline triage engine
# (.aai/scripts/aai-feedback-triage.mjs), TEST-001..012.
#
# Offline triage: read the friction spool, hard-gate, score from v2 signals with a
# v1 recurrence fallback, cluster by fingerprint, write a LOCAL report. No network.

set -u
TEST_NAME="test-aai-feedback-triage"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"
SCRIPT="$PROJECT_ROOT/.aai/scripts/aai-feedback-triage.mjs"
LAYER_PROFILES_TEST="$SCRIPT_DIR/test-aai-layer-profiles.sh"

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
[ -f "$LAYER_PROFILES_TEST" ] || log_fail "test-aai-layer-profiles.sh not found"

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
  echo "$reasons" | grep -q "bad_schema_version" || log_fail "TEST-001: must drop bad schema_version ($reasons)"
  echo "$reasons" | grep -q "non_taxonomy_failure_class" || log_fail "TEST-001: must drop non-taxonomy class ($reasons)"
  echo "$reasons" | grep -q "unsanitized_key" || log_fail "TEST-001: must drop an unsanitized key ($reasons)"
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
  log_pass "fail-closed config: malformed / out-of-scope mode -> local (TEST-012)"
}

# --- TEST-013: profiles classification --------------------------------------
test_013_profiles() {
  log_info "Test: new .aai files classified; layer-profiles green (TEST-013)..."
  local out code; out="$(bash "$LAYER_PROFILES_TEST" 2>&1)"; code=$?
  [ "$code" = "0" ] || log_fail "TEST-013: test-aai-layer-profiles.sh must pass: $(printf '%s' "$out" | tail -3)"
  log_pass "new .aai files classified; layer-profiles green (TEST-013)"
}

main() {
  echo "=== $TEST_NAME ==="
  setup
  [ -f "$SCRIPT" ] || log_fail "engine missing: $SCRIPT"
  if [ $# -gt 0 ]; then "$1"; echo "=== $TEST_NAME: SELECTED PASSED ($1) ==="; return; fi
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
  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}
main "$@"
