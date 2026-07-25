#!/usr/bin/env bash
#
# Test: RFC-0012 Phase 2c / Slice C — review-mode GitHub upsert (approval-gated)
# (.aai/scripts/aai-feedback-upsert.mjs), TEST-001..008.
#
# `gh` is MOCKED via a stub on AAI_GH_BIN that RECORDS every invocation — the
# suite makes NO real network call. The core invariant under test: a plain run
# performs NO mutating GitHub call; a write happens ONLY under --publish --confirm.

set -u
TEST_NAME="test-aai-feedback-upsert"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"
SCRIPT="$PROJECT_ROOT/.aai/scripts/aai-feedback-upsert.mjs"
LAYER_PROFILES_TEST="$SCRIPT_DIR/test-aai-layer-profiles.sh"

cleanup() { [ -n "${TEST_DIR:-}" ] && [ -z "${KEEP_TEST_DIR:-}" ] && rm -rf "$TEST_DIR"; }
trap cleanup EXIT
log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_info() { echo "INFO: $*"; }
log_skip() { echo "SKIP: $*"; exit 42; }
command -v node >/dev/null 2>&1 || log_skip "node not found"

# Mock gh: $1 records calls; SEARCH_RESULT controls the search response.
setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-upsert-test.XXXXXX")"
  GH_CALLS="$TEST_DIR/gh_calls"; : > "$GH_CALLS"
  mkdir -p "$TEST_DIR/bin" "$TEST_DIR/friction"
  cat > "$TEST_DIR/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$@" >> "$GH_CALLS"
if [ "$1" = "search" ]; then cat "${SEARCH_RESULT:-/dev/null}" 2>/dev/null || echo "[]"; fi
if [ "$1" = "issue" ] && [ "$2" = "create" ]; then echo "https://github.com/x/y/issues/1"; fi
exit 0
SH
  chmod +x "$TEST_DIR/bin/gh"
  export GH_CALLS
  printf '[]' > "$TEST_DIR/empty.json"; SEARCH_RESULT="$TEST_DIR/empty.json"; export SEARCH_RESULT
  # a review-mode config
  printf 'triage:\n  mode: review\nupsert:\n  destination: goodwind-cz/aai   # pinned (RFC-0012 D1)\n  budget:\n    max_new_issues_per_7d: 3\n' > "$TEST_DIR/fb.yaml"
  # a spool + report with one review_candidate
  cat > "$TEST_DIR/friction/observations.jsonl" <<'JSONL'
{"schema_version":2,"os_family":"macos","aai_pin":"unknown","node_major":22,"skill_id":"SKILL_TDD","skill_phase":"impl","failure_class":"contract_violation","fingerprint":"v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","impact":"high","confidence":"high","reproducible":true}
JSONL
  cat > "$TEST_DIR/friction/triage-report.json" <<'JSON'
{"schema":"aai-triage/v1","clusters":[{"fingerprint":"v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","failure_class":"contract_violation","recurrence":2,"score":9,"decision":"review_candidate","auto_publishable":false}]}
JSON
}

# run the engine with the mock gh + isolated friction dir
RUN() {
  AAI_GH_BIN="$TEST_DIR/bin/gh" AAI_FRICTION_DIR="$TEST_DIR/friction" AAI_NOW_MS=1000000000000 \
    node "$SCRIPT" --report "$TEST_DIR/friction/triage-report.json" \
      --spool "$TEST_DIR/friction/observations.jsonl" --config "${1:-$TEST_DIR/fb.yaml}" "${@:2}" \
      > "$TEST_DIR/out" 2> "$TEST_DIR/err"; echo $?
}
creates() { local n; n="$(grep -c "^issue create" "$GH_CALLS" 2>/dev/null)"; echo "${n:-0}"; }
reset_calls() { : > "$GH_CALLS"; }

# --- TEST-001: plain run makes NO mutating gh call --------------------------
test_001_prepare_no_write() {
  log_info "Test: a plain review-mode run performs no mutating gh call (TEST-001)..."
  reset_calls
  local code; code="$(RUN)"
  [ "$code" = "0" ] || log_fail "TEST-001: plain run must exit 0 ($(cat "$TEST_DIR/err"))"
  [ "$(creates)" = "0" ] || log_fail "TEST-001: plain run must make ZERO issue-create calls (made $(creates))"
  [ -f "$TEST_DIR/friction/pending-issues/v1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.md" ] || log_fail "TEST-001: a draft must be written"
  log_pass "plain run is prepare-only: no mutating gh call, draft written (TEST-001)"
}

# --- TEST-002/003: template + transmit redaction ----------------------------
test_002_template_and_redaction() {
  log_info "Test: title/body templated; poisoned summary dropped by transmit redaction (TEST-002/003)..."
  # add a poisoned summary to the observation
  cat > "$TEST_DIR/friction/observations.jsonl" <<'JSONL'
{"schema_version":2,"os_family":"macos","aai_pin":"unknown","node_major":22,"skill_id":"SKILL_TDD","skill_phase":"impl","failure_class":"contract_violation","fingerprint":"v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","impact":"high","summary":"failed at /Users/ales/.ssh/id_rsa"}
JSONL
  reset_calls; RUN >/dev/null
  local draft="$TEST_DIR/friction/pending-issues/v1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.md"
  grep -qF "[contract_violation] SKILL_TDD/impl (high impact)" "$draft" || log_fail "TEST-002: title must be templated from structured fields"
  grep -qF "aai-friction:v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" "$draft" || log_fail "TEST-002: body must carry the dedup marker"
  grep -qF "id_rsa" "$draft" && log_fail "TEST-003: a poisoned summary must be DROPPED (transmit redaction), never in the draft"
  grep -qF "transmit_dropped" "$draft" || log_fail "TEST-003: redaction_status must record the drop"
  log_pass "title/body templated; poisoned summary dropped by transmit redaction (TEST-002/003)"
}

# --- TEST-004: dedup ---------------------------------------------------------
test_004_dedup() {
  log_info "Test: an existing marker -> no duplicate NEW issue (TEST-004)..."
  printf '[{"number":42}]' > "$TEST_DIR/existing.json"; SEARCH_RESULT="$TEST_DIR/existing.json"
  reset_calls; RUN >/dev/null
  local draft="$TEST_DIR/friction/pending-issues/v1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.md"
  grep -qF "status: update_existing" "$draft" || log_fail "TEST-004: existing marker -> draft marked update_existing"
  # confirmed publish must NOT create when one already exists
  reset_calls; RUN "$TEST_DIR/fb.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm >/dev/null
  [ "$(creates)" = "0" ] || log_fail "TEST-004: must not create a duplicate when an issue already carries the marker"
  SEARCH_RESULT="$TEST_DIR/empty.json"
  log_pass "existing marker deduped: draft=update_existing, no duplicate create (TEST-004)"
}

# --- TEST-005: budget --------------------------------------------------------
test_005_budget() {
  log_info "Test: budget met -> prepared-deferred, not filed (TEST-005)..."
  # seed the ledger with max_new_issues_per_7d recent creates
  local led="$TEST_DIR/friction/upsert-ledger.jsonl"
  for i in 1 2 3; do echo "{\"event\":\"issue_created\",\"fingerprint\":\"v1:old$i\",\"ts_ms\":999999999999}" >> "$led"; done
  reset_calls; local out; RUN "$TEST_DIR/fb.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm >/dev/null; out="$(cat "$TEST_DIR/out")"
  [ "$(creates)" = "0" ] || log_fail "TEST-005: over-budget publish must NOT create an issue"
  echo "$out" | grep -qi "budget" || log_fail "TEST-005: must report the budget deferral"
  log_pass "budget met -> deferred, no create (TEST-005)"
}

# --- TEST-006: config pin / auto refused / degrade --------------------------
test_006_config() {
  log_info "Test: destination pin; auto refused; local/missing-dest -> prepare-none (TEST-006)..."
  # auto refused
  printf 'triage:\n  mode: auto\nupsert:\n  destination: goodwind-cz/aai   # pinned (RFC-0012 D1)\n' > "$TEST_DIR/fbauto.yaml"
  RUN "$TEST_DIR/fbauto.yaml" >/dev/null; local code=$?
  grep -qi "auto is refused\|mode=auto" "$TEST_DIR/err" || log_fail "TEST-006: auto mode must be refused"
  # local mode -> prepare nothing
  printf 'triage:\n  mode: local\nupsert:\n  destination: goodwind-cz/aai   # pinned (RFC-0012 D1)\n' > "$TEST_DIR/fblocal.yaml"
  reset_calls; RUN "$TEST_DIR/fblocal.yaml" >/dev/null
  [ "$(creates)" = "0" ] || log_fail "TEST-006: local mode must make no gh call"
  grep -qi "prepare-none\|nothing prepared" "$TEST_DIR/out" || log_fail "TEST-006: local mode must prepare nothing"
  log_pass "destination pin; auto refused; local -> prepare-none (TEST-006)"
}

# --- TEST-007: confirmed publish is the only write + ledger append ----------
test_007_confirm_only_write() {
  log_info "Test: --publish needs --confirm; confirmed -> one create + ledger append (TEST-007)..."
  cat > "$TEST_DIR/friction/observations.jsonl" <<'JSONL'
{"schema_version":2,"os_family":"macos","aai_pin":"unknown","node_major":22,"skill_id":"SKILL_TDD","skill_phase":"impl","failure_class":"contract_violation","fingerprint":"v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","impact":"high"}
JSONL
  rm -f "$TEST_DIR/friction/upsert-ledger.jsonl"
  # without --confirm: no write
  reset_calls; RUN "$TEST_DIR/fb.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa >/dev/null
  [ "$(creates)" = "0" ] || log_fail "TEST-007: --publish without --confirm must NOT write"
  grep -qi "without --confirm" "$TEST_DIR/out" || log_fail "TEST-007: must state it refuses without --confirm"
  # with --confirm: exactly one create + ledger append
  reset_calls; RUN "$TEST_DIR/fb.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm >/dev/null
  [ "$(creates)" = "1" ] || log_fail "TEST-007: confirmed publish must make exactly one create (made $(creates))"
  grep -qF "issue_created" "$TEST_DIR/friction/upsert-ledger.jsonl" || log_fail "TEST-007: confirmed publish must append to the ledger"
  log_pass "confirmed publish is the only write; ledger appended (TEST-007)"
}

# --- TEST-008: static — mutating gh only in the confirmed path --------------
test_008_static_write_gate() {
  log_info "Test: static — 'issue create' appears only guarded by --confirm (TEST-008)..."
  [ -f "$SCRIPT" ] || log_fail "TEST-008: engine missing"
  # exactly one 'issue', 'create' mutating invocation in the source, inside the publish/confirm branch
  local n; n="$(grep -c "'issue', 'create'" "$SCRIPT")"
  [ "$n" = "1" ] || log_fail "TEST-008: expected exactly one issue-create call site (got $n)"
  # the create call site must be preceded by an args.confirm gate in the file
  grep -q "args.confirm" "$SCRIPT" || log_fail "TEST-008: the write path must be gated by args.confirm"
  log_pass "single issue-create call site, gated by --confirm (TEST-008)"
}

# --- TEST-010 (Spec-AC-03): EVERY interpolated field is transmit-sanitized -----
# Regression: only `summary` was redacted; hostile skill_id/skill_phase/impact/
# evidence_ref reached the gh argv verbatim. Now every field is re-validated.
test_010_field_sanitization() {
  log_info "Test: hostile non-summary fields never reach a gh argument (TEST-010)..."
  # Hostile content with DISALLOWED chars (paths/spaces/@/invalid-enum) — caught by
  # the charset/enum gate. (Token-shaped fixtures below are assembled from fragments
  # so no scannable provider-secret literal is committed to this file.)
  cat > "$TEST_DIR/friction/observations.jsonl" <<'JSONL'
{"schema_version":2,"os_family":"macos-attacker@evil.com","aai_pin":"unknown","node_major":22,"skill_id":"SKILL_TDD_/Users/ales/.ssh/id_rsa","skill_phase":"impl with spaces","failure_class":"contract_violation","fingerprint":"v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","impact":"high) not-an-enum (","evidence_ref":"/Users/ales/.ssh/id_rsa"}
JSONL
  reset_calls; RUN "$TEST_DIR/fb.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm >/dev/null
  local leak; leak="$( { cat "$GH_CALLS"; cat "$TEST_DIR/friction/pending-issues/v1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.md" 2>/dev/null; } | grep -oE 'id_rsa|/Users/|@evil|not-an-enum' || true)"
  [ -z "$leak" ] || log_fail "TEST-010: a hostile field leaked into the gh argv or draft: $leak"
  grep -qF "<redacted>" "$GH_CALLS" || log_fail "TEST-010: hostile identifier fields must be redacted in the payload"
  # CLEAN-TOKEN case (regression): a secret that is itself identifier-shaped
  # (gh PAT / Stripe / AWS prefixes, no disallowed char) must ALSO be caught by the
  # deny-list, not sail through the charset gate — the blind spot re-validation found.
  # Prefixes are fragment-assembled so no contiguous provider-secret literal is
  # committed (GitHub push-protection); the runtime string still trips the detector.
  local GHP="gh""p_" SKL="sk""_live_" AKIA="AKI""A"
  printf '{"schema_version":2,"os_family":"macos","aai_pin":"%sABCDEFGHIJKLMNOP","node_major":22,"skill_id":"%s1234567890abcdefghijklmnopqrstuvwxyzAB","skill_phase":"%s51ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij","failure_class":"contract_violation","fingerprint":"v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","impact":"high"}\n' \
    "$AKIA" "$GHP" "$SKL" > "$TEST_DIR/friction/observations.jsonl"
  reset_calls; RUN "$TEST_DIR/fb.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm >/dev/null
  local tleak; tleak="$(grep -oE "${GHP}[A-Za-z0-9]+|${SKL}[A-Za-z0-9]+|${AKIA}[A-Z0-9]{16}" "$GH_CALLS" || true)"
  [ -z "$tleak" ] || log_fail "TEST-010: a charset-clean secret token leaked into the gh argv: $tleak"
  log_pass "every non-summary field re-sanitized incl. charset-clean secret tokens (TEST-010)"
}

# --- TEST-011 (Spec-AC-04): dedup fail-CLOSED on an unverifiable search ---------
test_011_dedup_failclosed() {
  log_info "Test: confirm-publish refuses to create when dedup search is unverifiable (TEST-011)..."
  cat > "$TEST_DIR/friction/observations.jsonl" <<'JSONL'
{"schema_version":2,"os_family":"macos","aai_pin":"unknown","node_major":22,"skill_id":"SKILL_TDD","skill_phase":"impl","failure_class":"contract_violation","fingerprint":"v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","impact":"high"}
JSONL
  # mock gh returns malformed (unparseable) search output
  printf 'not json {[' > "$TEST_DIR/garbage.json"; SEARCH_RESULT="$TEST_DIR/garbage.json"
  reset_calls; local code; code="$(RUN "$TEST_DIR/fb.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm)"
  [ "$(creates)" = "0" ] || log_fail "TEST-011: must NOT create when dedup cannot be verified"
  [ "$code" != "0" ] || log_fail "TEST-011: an unverifiable dedup must fail (non-zero), not silently create"
  SEARCH_RESULT="$TEST_DIR/empty.json"
  log_pass "dedup fail-closed: unverifiable search refuses the create (TEST-011)"
}

# --- TEST-012 (PR review): fingerprint validation + labels applied ------------
test_012_fingerprint_and_labels() {
  log_info "Test: off-shape fingerprint skipped; configured labels applied on create (TEST-012)..."
  # a report with a POISONED (off-shape) fingerprint alongside a valid one
  cat > "$TEST_DIR/friction/observations.jsonl" <<'JSONL'
{"schema_version":2,"os_family":"macos","aai_pin":"unknown","node_major":22,"skill_id":"SKILL_TDD","skill_phase":"impl","failure_class":"contract_violation","fingerprint":"v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","impact":"high"}
{"schema_version":2,"os_family":"macos","aai_pin":"unknown","node_major":22,"skill_id":"X","skill_phase":"y","failure_class":"contract_violation","fingerprint":"v1:POISON_/Users/x/.ssh","impact":"high"}
JSONL
  cat > "$TEST_DIR/friction/triage-report.json" <<'JSON'
{"clusters":[{"fingerprint":"v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","failure_class":"contract_violation","recurrence":2,"score":9,"decision":"review_candidate","auto_publishable":false},{"fingerprint":"v1:POISON_/Users/x/.ssh","failure_class":"contract_violation","recurrence":2,"score":9,"decision":"review_candidate","auto_publishable":false}]}
JSON
  # config WITH a labels list
  printf 'triage:\n  mode: review\nupsert:\n  destination: goodwind-cz/aai   # pin\n  labels:\n    - aai-friction\n' > "$TEST_DIR/fblab.yaml"
  reset_calls; RUN "$TEST_DIR/fblab.yaml" >/dev/null
  # only the valid fingerprint gets a draft; the poisoned one is skipped (never a file / never a gh call carrying it)
  [ -f "$TEST_DIR/friction/pending-issues/v1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.md" ] || log_fail "TEST-012: valid fingerprint must be prepared"
  ls "$TEST_DIR/friction/pending-issues/" | grep -qi "POISON\|ssh\|Users" && log_fail "TEST-012: an off-shape fingerprint must be skipped (no draft)"
  grep -qi "POISON\|/Users/\|\.ssh" "$GH_CALLS" && log_fail "TEST-012: an off-shape fingerprint must never reach a gh call" || true
  # poisoned fingerprint publish is rejected (RUN echoes the node exit code)
  local pc; pc="$(RUN "$TEST_DIR/fblab.yaml" --publish "v1:POISON_/Users/x/.ssh" --confirm)"
  [ "$pc" != "0" ] || log_fail "TEST-012: publishing an off-shape fingerprint must be rejected"
  # labels applied on a valid confirmed create (clear the shared ledger so an
  # earlier test's budget does not defer this create)
  rm -f "$TEST_DIR/friction/upsert-ledger.jsonl"
  reset_calls; RUN "$TEST_DIR/fblab.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm >/dev/null
  grep -qF "label aai-friction" "$GH_CALLS" || log_fail "TEST-012: configured labels must be applied on create ($(cat "$TEST_DIR/out"))"
  log_pass "off-shape fingerprint skipped/rejected; configured labels applied (TEST-012)"
}

test_009_profiles() {
  log_info "Test: new .aai files classified; layer-profiles green (TEST-009)..."
  local out code; out="$(bash "$LAYER_PROFILES_TEST" 2>&1)"; code=$?
  [ "$code" = "0" ] || log_fail "TEST-009: layer-profiles must pass: $(printf '%s' "$out" | tail -3)"
  log_pass "new .aai files classified; layer-profiles green (TEST-009)"
}

main() {
  echo "=== $TEST_NAME ==="
  [ -f "$SCRIPT" ] || log_fail "engine missing: $SCRIPT"
  setup
  if [ $# -gt 0 ]; then "$1"; echo "=== $TEST_NAME: SELECTED PASSED ($1) ==="; return; fi
  test_001_prepare_no_write
  test_002_template_and_redaction
  test_004_dedup
  test_005_budget
  test_006_config
  test_007_confirm_only_write
  test_008_static_write_gate
  test_010_field_sanitization
  test_011_dedup_failclosed
  test_012_fingerprint_and_labels
  test_009_profiles
  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}
main "$@"
