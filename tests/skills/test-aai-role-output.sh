#!/usr/bin/env bash
#
# Test: role-output-contracts — deterministic EXPECT validation of dispatched-
# role result blocks (docs/specs/SPEC-0094-spec-role-output-contracts.md).
#
# Verifies .aai/scripts/check-role-output.mjs (LAST subagent_result fence
# extraction, six EXPECT postconditions, machine-parseable
# ROLE-OUTPUT-VIOLATION lines, exit 0 clean / 1 on any violation),
# determinism + zero-dep (Spec-AC-02), the duration/timestamp/future-started
# timing rules (Spec-AC-03), and the CONTRACT/PROTOCOL canon wiring
# (Spec-AC-04). Implements TEST-001..010, TEST-013, TEST-014 from the frozen
# spec (TEST-011/012/015 are covered by other suites/CI, see spec Test Plan).
#
# Bash-3.2 safe (no associative arrays, no `mapfile`) — macOS default shell.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-role-output"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHECKER="$PROJECT_ROOT/.aai/scripts/check-role-output.mjs"
FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures/role-outputs"
CONTRACT_DOC="$PROJECT_ROOT/.aai/SUBAGENT_CONTRACT.md"
PROTOCOL_DOC="$PROJECT_ROOT/.aai/SUBAGENT_PROTOCOL.md"

TMP_ROOT=""

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then
    echo "INFO: keeping fixtures under $TMP_ROOT"
    return 0
  fi
  if [[ -n "${TMP_ROOT:-}" && -d "$TMP_ROOT" ]]; then
    rm -rf "$TMP_ROOT"
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
  [[ -f "$CHECKER" ]] || log_fail "checker script not found: $CHECKER"
  [[ -d "$FIXTURES_DIR" ]] || log_fail "fixtures dir not found: $FIXTURES_DIR"
  TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aai-role-output-test.XXXXXX")"
  log_pass "Dependencies checked"
}

# Run the checker; never aborts the suite on non-zero exit (callers inspect
# $? and $out deliberately).
runcheck() {
  node "$CHECKER" "$@"
}

# --- TEST-001 — every VALID fixture -> exit 0, zero violation lines ----------
test_001_valid_fixtures() {
  log_info "TEST-001: every VALID fixture (4 role classes) -> exit 0, no violation lines..."
  local f out rc
  for f in "$FIXTURES_DIR"/*-valid.md; do
    set +e
    out="$(runcheck --file "$f" --now 2026-06-01T00:00:00Z)"; rc=$?
    set -e
    [[ "$rc" -eq 0 ]] || log_fail "$(basename "$f") expected exit 0, got $rc; output: $out"
    [[ -z "$out" ]] || log_fail "$(basename "$f") expected zero output on a clean run, got: $out"
  done
  log_pass "TEST-001 all valid fixtures accepted"
}

# --- TEST-002 — every VIOLATING fixture -> exit 1 with its expected code -----
test_002_violating_fixtures() {
  log_info "TEST-002: every VIOLATING fixture -> exit 1 with the expected ROLE-OUTPUT-VIOLATION code..."
  local out rc
  set +e
  out="$(runcheck --file "$FIXTURES_DIR/implementation-violating.md" --now 2026-06-01T00:00:00Z)"; rc=$?
  set -e
  [[ "$rc" -eq 1 ]] || log_fail "implementation-violating.md expected exit 1, got $rc"
  echo "$out" | grep -qF "ROLE-OUTPUT-VIOLATION: E-MISSING-FIELD" \
    || log_fail "implementation-violating.md expected E-MISSING-FIELD, got: $out"

  set +e
  out="$(runcheck --file "$FIXTURES_DIR/validation-violating.md" --now 2026-06-01T00:00:00Z)"; rc=$?
  set -e
  [[ "$rc" -eq 1 ]] || log_fail "validation-violating.md expected exit 1, got $rc"
  echo "$out" | grep -qF "ROLE-OUTPUT-VIOLATION: E-BAD-STATUS" \
    || log_fail "validation-violating.md expected E-BAD-STATUS, got: $out"

  set +e
  out="$(runcheck --file "$FIXTURES_DIR/review-violating.md" --now 2026-06-01T00:00:00Z)"; rc=$?
  set -e
  [[ "$rc" -eq 1 ]] || log_fail "review-violating.md expected exit 1, got $rc"
  echo "$out" | grep -qF "ROLE-OUTPUT-VIOLATION: E-NO-EVIDENCE" \
    || log_fail "review-violating.md expected E-NO-EVIDENCE, got: $out"

  set +e
  out="$(runcheck --file "$FIXTURES_DIR/planning-violating.md" --now 2026-06-01T00:00:00Z)"; rc=$?
  set -e
  [[ "$rc" -eq 1 ]] || log_fail "planning-violating.md expected exit 1, got $rc"
  echo "$out" | grep -qF "ROLE-OUTPUT-VIOLATION: E-BAD-TIMESTAMP" \
    || log_fail "planning-violating.md expected E-BAD-TIMESTAMP, got: $out"

  log_pass "TEST-002 all violating fixtures rejected with their expected code"
}

# --- TEST-003 — valid block + EXTRA unknown fields still passes (core-only) --
test_003_extra_fields_ignored() {
  log_info "TEST-003: a valid block carrying EXTRA unknown fields still passes..."
  local msg="$TMP_ROOT/extra-fields.md"
  cat > "$msg" <<'EOF'
Done.

```yaml
subagent_result:
  scope: role-output-contracts
  role: Implementation
  status: PASS
  started_utc: 2026-01-05T00:00:00Z
  ended_utc: 2026-01-05T00:01:00Z
  duration_seconds: 60
  retry_count: 2
  model_id: claude-opus-4-8
  evidence:
    - command: echo ok
      exit_code: 0
      output_snippet: "ok"
      latency_ms: 12
  files_changed: []
  blockers: []
  notes: >-
    a multi-line extension field the checker must never choke on
```
EOF
  local out rc
  set +e
  out="$(runcheck --file "$msg" --now 2026-06-01T00:00:00Z)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "extra-field block expected exit 0, got $rc; output: $out"
  [[ -z "$out" ]] || log_fail "extra-field block expected zero output, got: $out"
  log_pass "TEST-003 extra extension fields ignored (required core validated only)"
}

# --- TEST-004 — two fences: only the LAST is validated -----------------------
test_004_last_fence_wins() {
  log_info "TEST-004: two subagent_result fences present -> only the LAST is validated..."
  local bad_then_good="$TMP_ROOT/last-valid.md"
  cat > "$bad_then_good" <<'EOF'
Template skeleton echoed earlier in the message (invalid, missing fields):

```yaml
subagent_result:
  role: Implementation
  status: PASS
```

Actual result block:

```yaml
subagent_result:
  scope: role-output-contracts
  role: Implementation
  status: PASS
  started_utc: 2026-01-06T00:00:00Z
  ended_utc: 2026-01-06T00:01:00Z
  duration_seconds: 60
  evidence:
    - command: echo ok
      exit_code: 0
      output_snippet: "ok"
  files_changed: []
  blockers: []
```
EOF
  local out rc
  set +e
  out="$(runcheck --file "$bad_then_good" --now 2026-06-01T00:00:00Z)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "last-valid case expected exit 0 (last fence wins), got $rc; output: $out"

  local good_then_bad="$TMP_ROOT/last-invalid.md"
  cat > "$good_then_bad" <<'EOF'
Draft (valid, discarded):

```yaml
subagent_result:
  scope: role-output-contracts
  role: Implementation
  status: PASS
  started_utc: 2026-01-06T00:00:00Z
  ended_utc: 2026-01-06T00:01:00Z
  duration_seconds: 60
  evidence:
    - command: echo ok
      exit_code: 0
      output_snippet: "ok"
  files_changed: []
  blockers: []
```

Final (invalid, bad status):

```yaml
subagent_result:
  scope: role-output-contracts
  role: Implementation
  status: DONE
  started_utc: 2026-01-06T00:00:00Z
  ended_utc: 2026-01-06T00:01:00Z
  duration_seconds: 60
  evidence:
    - command: echo ok
      exit_code: 0
      output_snippet: "ok"
  files_changed: []
  blockers: []
```
EOF
  set +e
  out="$(runcheck --file "$good_then_bad" --now 2026-06-01T00:00:00Z)"; rc=$?
  set -e
  [[ "$rc" -eq 1 ]] || log_fail "last-invalid case expected exit 1 (last fence wins), got $rc"
  echo "$out" | grep -qF "E-BAD-STATUS" || log_fail "last-invalid case expected E-BAD-STATUS, got: $out"
  log_pass "TEST-004 LAST fence wins in both directions"
}

# --- TEST-005 — two consecutive runs -> byte-identical stdout + exit ---------
test_005_determinism() {
  log_info "TEST-005: two consecutive runs on the same input -> byte-identical stdout + exit code..."
  local f="$FIXTURES_DIR/implementation-valid.md"
  local out1 out2 rc1 rc2
  set +e
  out1="$(runcheck --file "$f" --now 2026-06-01T00:00:00Z)"; rc1=$?
  out2="$(runcheck --file "$f" --now 2026-06-01T00:00:00Z)"; rc2=$?
  set -e
  [[ "$rc1" -eq "$rc2" ]] || log_fail "exit codes differ across runs: $rc1 vs $rc2"
  [[ "$out1" == "$out2" ]] || log_fail "stdout differs across runs"

  # Same probe against a violating fixture (non-empty output path).
  f="$FIXTURES_DIR/validation-violating.md"
  set +e
  out1="$(runcheck --file "$f" --now 2026-06-01T00:00:00Z)"; rc1=$?
  out2="$(runcheck --file "$f" --now 2026-06-01T00:00:00Z)"; rc2=$?
  set -e
  [[ "$rc1" -eq "$rc2" ]] || log_fail "violating-fixture exit codes differ across runs: $rc1 vs $rc2"
  [[ "$out1" == "$out2" ]] || log_fail "violating-fixture stdout differs across runs"
  log_pass "TEST-005 byte-identical stdout + exit code across two runs"
}

# --- TEST-006 — no network/model import; no package.json; plain node --------
test_006_zero_dep() {
  log_info "TEST-006: no network/model import in checker; no package.json added; runs on plain node..."
  if grep -nE "require\(['\"](https?|http|net|dgram|tls)['\"]\)|from ['\"](https?|http|net|dgram|tls)['\"]|fetch\(|XMLHttpRequest|anthropic|openai" "$CHECKER" >/dev/null 2>&1; then
    log_fail "checker references a network/model API"
  fi
  local import_lines non_stdlib
  import_lines="$(grep -E "^import .* from ['\"]" "$CHECKER" || true)"
  [[ -n "$import_lines" ]] || log_fail "checker has no import statements to verify (unexpected)"
  non_stdlib="$(echo "$import_lines" | grep -vE "from ['\"]node:" || true)"
  [[ -z "$non_stdlib" ]] || log_fail "checker imports a non-stdlib module: $non_stdlib"
  [[ ! -f "$PROJECT_ROOT/.aai/scripts/package.json" ]] \
    || log_fail "no package.json/manifest may be added for the checker"
  [[ ! -f "$PROJECT_ROOT/package.json" ]] \
    || log_fail "repo root package.json unexpectedly present"
  # Plain node invocation (no env, no flags beyond the CLI's own args) works.
  local out rc
  set +e
  out="$(env -i PATH="$PATH" node "$CHECKER" --file "$FIXTURES_DIR/implementation-valid.md" --now 2026-06-01T00:00:00Z 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "plain env-stripped node run failed: $out"
  log_pass "TEST-006 zero-dep, LLM-free, plain-node confirmed"
}

# --- TEST-007 — duration tolerance accepted / rejected -----------------------
test_007_duration_tolerance() {
  log_info "TEST-007: duration within +/-1s accepted; beyond tolerance -> E-BAD-DURATION..."
  local within="$TMP_ROOT/duration-within.md" beyond="$TMP_ROOT/duration-beyond.md"
  cat > "$within" <<'EOF'
```yaml
subagent_result:
  scope: role-output-contracts
  role: Implementation
  status: PASS
  started_utc: 2026-01-07T00:00:00Z
  ended_utc: 2026-01-07T00:01:00Z
  duration_seconds: 61
  evidence:
    - command: echo ok
      exit_code: 0
      output_snippet: "ok"
  files_changed: []
  blockers: []
```
EOF
  cat > "$beyond" <<'EOF'
```yaml
subagent_result:
  scope: role-output-contracts
  role: Implementation
  status: PASS
  started_utc: 2026-01-07T00:00:00Z
  ended_utc: 2026-01-07T00:01:00Z
  duration_seconds: 65
  evidence:
    - command: echo ok
      exit_code: 0
      output_snippet: "ok"
  files_changed: []
  blockers: []
```
EOF
  local out rc
  set +e
  out="$(runcheck --file "$within" --now 2026-06-01T00:00:00Z)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "duration off by exactly 1s must be accepted, got rc=$rc output: $out"

  set +e
  out="$(runcheck --file "$beyond" --now 2026-06-01T00:00:00Z)"; rc=$?
  set -e
  [[ "$rc" -eq 1 ]] || log_fail "duration off by 5s must be rejected, got rc=$rc"
  echo "$out" | grep -qF "ROLE-OUTPUT-VIOLATION: E-BAD-DURATION" \
    || log_fail "expected E-BAD-DURATION, got: $out"
  log_pass "TEST-007 duration +/-1s tolerance enforced"
}

# --- TEST-008 — malformed (non-ISO-8601) timestamp -> E-BAD-TIMESTAMP --------
test_008_bad_timestamp() {
  log_info "TEST-008: malformed timestamp -> E-BAD-TIMESTAMP..."
  local out rc
  set +e
  out="$(runcheck --file "$FIXTURES_DIR/planning-violating.md" --now 2026-06-01T00:00:00Z)"; rc=$?
  set -e
  [[ "$rc" -eq 1 ]] || log_fail "expected exit 1, got $rc"
  echo "$out" | grep -qF "ROLE-OUTPUT-VIOLATION: E-BAD-TIMESTAMP" \
    || log_fail "expected E-BAD-TIMESTAMP, got: $out"

  # A non-UTC offset (missing explicit Z/+00:00) must also be rejected.
  local offset="$TMP_ROOT/offset-timestamp.md"
  cat > "$offset" <<'EOF'
```yaml
subagent_result:
  scope: role-output-contracts
  role: Implementation
  status: PASS
  started_utc: 2026-01-07T02:00:00+02:00
  ended_utc: 2026-01-07T00:01:00Z
  duration_seconds: 60
  evidence:
    - command: echo ok
      exit_code: 0
      output_snippet: "ok"
  files_changed: []
  blockers: []
```
EOF
  set +e
  out="$(runcheck --file "$offset" --now 2026-06-01T00:00:00Z)"; rc=$?
  set -e
  [[ "$rc" -eq 1 ]] || log_fail "non-UTC offset timestamp must be rejected, got rc=$rc"
  echo "$out" | grep -qF "ROLE-OUTPUT-VIOLATION: E-BAD-TIMESTAMP" \
    || log_fail "expected E-BAD-TIMESTAMP for non-UTC offset, got: $out"
  log_pass "TEST-008 malformed / non-UTC timestamps rejected"
}

# --- TEST-009 — missing field / bad status / no-integer-evidence bundle -----
test_009_field_bundle() {
  log_info "TEST-009: missing field -> E-MISSING-FIELD; bad status -> E-BAD-STATUS; no integer exit_code -> E-NO-EVIDENCE..."
  local out rc

  set +e
  out="$(runcheck --file "$FIXTURES_DIR/implementation-violating.md" --now 2026-06-01T00:00:00Z)"; rc=$?
  set -e
  [[ "$rc" -eq 1 ]] || log_fail "missing-field fixture expected exit 1, got $rc"
  echo "$out" | grep -qF "ROLE-OUTPUT-VIOLATION: E-MISSING-FIELD" \
    || log_fail "expected E-MISSING-FIELD, got: $out"

  set +e
  out="$(runcheck --file "$FIXTURES_DIR/validation-violating.md" --now 2026-06-01T00:00:00Z)"; rc=$?
  set -e
  [[ "$rc" -eq 1 ]] || log_fail "bad-status fixture expected exit 1, got $rc"
  echo "$out" | grep -qF "ROLE-OUTPUT-VIOLATION: E-BAD-STATUS" \
    || log_fail "expected E-BAD-STATUS, got: $out"

  # Empty evidence list (no entries at all) -> E-NO-EVIDENCE.
  local empty_ev="$TMP_ROOT/empty-evidence.md"
  cat > "$empty_ev" <<'EOF'
```yaml
subagent_result:
  scope: role-output-contracts
  role: Implementation
  status: PASS
  started_utc: 2026-01-08T00:00:00Z
  ended_utc: 2026-01-08T00:01:00Z
  duration_seconds: 60
  evidence: []
  files_changed: []
  blockers: []
```
EOF
  set +e
  out="$(runcheck --file "$empty_ev" --now 2026-06-01T00:00:00Z)"; rc=$?
  set -e
  [[ "$rc" -eq 1 ]] || log_fail "empty-evidence fixture expected exit 1, got $rc"
  echo "$out" | grep -qF "ROLE-OUTPUT-VIOLATION: E-NO-EVIDENCE" \
    || log_fail "expected E-NO-EVIDENCE for empty evidence list, got: $out"

  log_pass "TEST-009 missing-field / bad-status / no-evidence bundle"
}

# --- TEST-010 — CONTRACT EXPECT pointer (<=60 lines); PROTOCOL step 1 --------
test_010_canon_wiring() {
  log_info "TEST-010: CONTRACT <=60 lines + EXPECT pointer; PROTOCOL step 1 names the mandatory checker invocation + reject-and-re-prompt-once..."
  [[ -f "$CONTRACT_DOC" ]] || log_fail "missing .aai/SUBAGENT_CONTRACT.md"
  [[ -f "$PROTOCOL_DOC" ]] || log_fail "missing .aai/SUBAGENT_PROTOCOL.md"

  local n
  n="$(wc -l < "$CONTRACT_DOC" | tr -d ' ')"
  [[ "$n" -le 60 ]] || log_fail "SUBAGENT_CONTRACT.md must stay <=60 lines (got $n)"
  grep -qF "check-role-output.mjs" "$CONTRACT_DOC" \
    || log_fail "SUBAGENT_CONTRACT.md must name check-role-output.mjs"
  grep -qiF "EXPECT" "$CONTRACT_DOC" \
    || log_fail "SUBAGENT_CONTRACT.md must carry a grep-able EXPECT pointer"

  grep -qF "check-role-output.mjs" "$PROTOCOL_DOC" \
    || log_fail "SUBAGENT_PROTOCOL.md must name check-role-output.mjs"
  grep -qiE "reject.and.re.prompt" "$PROTOCOL_DOC" \
    || log_fail "SUBAGENT_PROTOCOL.md must document the reject-and-re-prompt-once rule"
  local step1
  step1="$(awk '/^## Merge protocol/{f=1} f && /^2\. Evaluate overall status/{exit} f' "$PROTOCOL_DOC")"
  echo "$step1" | grep -qF "check-role-output.mjs" \
    || log_fail "the mandatory checker invocation must live in merge-protocol STEP 1 (before step 2), got step-1 text:"$'\n'"$step1"
  grep -qF "300 seconds in the future" "$PROTOCOL_DOC" \
    || log_fail "SEAM-2: PROTOCOL must still document the 300s future-timestamp rule"
  log_pass "TEST-010 canon wiring: CONTRACT $n lines + EXPECT pointer; PROTOCOL step 1 mandatory invocation"
}

# --- TEST-020 — CONTRACT headroom guard (<=54 lines, >=6 below the 60 cap) ----
# Guards against the zero-headroom trap where the CONTRACT sits exactly at the
# SPEC-0094 hard <=60-line cap and the next clause addition silently breaches
# it. This is a stricter sibling of TEST-010's <=60 cap (which stays intact).
test_020_contract_headroom() {
  log_info "TEST-020: CONTRACT <=54 lines (>=6-line headroom below the 60 cap)..."
  [[ -f "$CONTRACT_DOC" ]] || log_fail "missing .aai/SUBAGENT_CONTRACT.md"
  local n
  n="$(wc -l < "$CONTRACT_DOC" | tr -d ' ')"
  [[ "$n" -le 54 ]] \
    || log_fail "SUBAGENT_CONTRACT.md must stay <=54 lines for >=6-line headroom below the 60 cap (got $n)"
  log_pass "TEST-020 CONTRACT headroom: $n lines (<=54, >=6 below the 60 cap)"
}

# --- TEST-013 — started_utc >300s ahead of --now -> E-FUTURE-STARTED ---------
test_013_future_started() {
  log_info "TEST-013: started_utc >300s ahead of --now -> E-FUTURE-STARTED; PROTOCOL still documents 300s (SEAM-2)..."
  local future="$TMP_ROOT/future-started.md"
  cat > "$future" <<'EOF'
```yaml
subagent_result:
  scope: role-output-contracts
  role: Implementation
  status: PASS
  started_utc: 2026-06-01T00:10:01Z
  ended_utc: 2026-06-01T00:15:01Z
  duration_seconds: 300
  evidence:
    - command: echo ok
      exit_code: 0
      output_snippet: "ok"
  files_changed: []
  blockers: []
```
EOF
  local out rc
  set +e
  out="$(runcheck --file "$future" --now 2026-06-01T00:00:00Z)"; rc=$?
  set -e
  [[ "$rc" -eq 1 ]] || log_fail "started_utc 601s ahead of --now must be rejected, got rc=$rc"
  echo "$out" | grep -qF "ROLE-OUTPUT-VIOLATION: E-FUTURE-STARTED" \
    || log_fail "expected E-FUTURE-STARTED, got: $out"

  # Exactly at the 300s boundary must still be accepted (>300s rejects, not >=).
  local boundary="$TMP_ROOT/boundary-started.md"
  cat > "$boundary" <<'EOF'
```yaml
subagent_result:
  scope: role-output-contracts
  role: Implementation
  status: PASS
  started_utc: 2026-06-01T00:05:00Z
  ended_utc: 2026-06-01T00:10:00Z
  duration_seconds: 300
  evidence:
    - command: echo ok
      exit_code: 0
      output_snippet: "ok"
  files_changed: []
  blockers: []
```
EOF
  set +e
  out="$(runcheck --file "$boundary" --now 2026-06-01T00:00:00Z)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "started_utc exactly 300s ahead must be accepted (boundary), got rc=$rc output: $out"

  grep -qF "300 seconds in the future" "$PROTOCOL_DOC" \
    || log_fail "SEAM-2: PROTOCOL must document the SAME 300s future-timestamp threshold"
  log_pass "TEST-013 future-started rejection at >300s; SEAM-2 threshold match confirmed"
}

# --- TEST-014 — SEAM-1: canonical CONTRACT skeleton, filled, passes ----------
test_014_seam1_contract_skeleton() {
  log_info "TEST-014: SEAM-1 — canonical subagent_result skeleton from SUBAGENT_CONTRACT.md, filled with valid values, passes the checker..."
  local body="$TMP_ROOT/seam1-body.yaml"
  awk '/^```yaml$/{f=1;next} /^```$/{if(f){exit}} f' "$CONTRACT_DOC" > "$body"
  [[ -s "$body" ]] || log_fail "could not extract the fenced yaml block from SUBAGENT_CONTRACT.md"
  grep -qF "subagent_result:" "$body" || log_fail "extracted CONTRACT skeleton does not start with subagent_result:"

  # Anchored on the KEY prefix (not the placeholder text) so the two
  # identically-worded started_utc/ended_utc placeholders resolve to distinct
  # values instead of colliding — plain text substitution would give both
  # fields the same timestamp and manufacture a spurious E-BAD-DURATION.
  sed -i.bak \
    -e 's/^  scope: .*/  scope: seam1-test/' \
    -e 's/^  role: .*/  role: Implementation/' \
    -e 's/^  status: .*/  status: PASS/' \
    -e 's/^  started_utc: .*/  started_utc: 2026-01-09T00:00:00Z/' \
    -e 's/^  ended_utc: .*/  ended_utc: 2026-01-09T00:01:00Z/' \
    -e 's/^  duration_seconds: .*/  duration_seconds: 60/' \
    -e 's/^    - command: .*/    - command: echo ok/' \
    -e 's/^      exit_code: .*/      exit_code: 0/' \
    -e 's/^      output_snippet: .*/      output_snippet: ok/' \
    -e 's/^    - <relative path>/    - some\/file.txt/' \
    -e 's/^    - <description of any blocker.*/    - none/' \
    "$body"
  rm -f "$body.bak"

  local msg="$TMP_ROOT/seam1-msg.md"
  {
    echo "SEAM-1 probe: canonical CONTRACT skeleton filled with valid sample values."
    echo ""
    echo '```yaml'
    cat "$body"
    echo '```'
  } > "$msg"

  local out rc
  set +e
  out="$(runcheck --file "$msg" --now 2026-06-01T00:00:00Z)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "SEAM-1 filled CONTRACT skeleton expected exit 0, got $rc; output: $out; body:"$'\n'"$(cat "$body")"
  log_pass "TEST-014 SEAM-1: filled CONTRACT skeleton passes the checker"
}

main() {
  echo "=== AAI Skill Test: $TEST_NAME ==="
  check_deps
  test_001_valid_fixtures
  test_002_violating_fixtures
  test_003_extra_fields_ignored
  test_004_last_fence_wins
  test_005_determinism
  test_006_zero_dep
  test_007_duration_tolerance
  test_008_bad_timestamp
  test_009_field_bundle
  test_010_canon_wiring
  test_020_contract_headroom
  test_013_future_started
  test_014_seam1_contract_skeleton
  echo "=== ALL TESTS PASSED: $TEST_NAME ==="
}

# Allow sourcing for isolated per-test execution (TDD RED/GREEN evidence);
# run the full suite only when invoked directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
