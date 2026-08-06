#!/usr/bin/env bash
#
# Test: spec-lint — deterministic structural validation of spec documents
# (CHANGE spec-lint / SPEC spec-spec-lint)
#
# Verifies .aai/scripts/spec-lint.mjs (intra-spec structure lint: AC ids
# unique/sequential, status enum, done-needs-evidence, Test Plan to Spec-AC
# mapping, SPEC-FROZEN consistency, ceremony_level enum, parser-invisible AC
# rows), the PLANNING/VALIDATION advisory wiring, and seam survival.
# Implements TEST-001..TEST-011 from the frozen spec.
#
# Fixture arms run in a mktemp scratch root (own docs/specs tree); the real
# repo is only READ (TEST-009 real-corpus arm, TEST-010 greps, TEST-011 seams).
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -uo pipefail

TEST_NAME="aai-spec-lint"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LINT="$PROJECT_ROOT/.aai/scripts/spec-lint.mjs"

FAILED=0
TMP_ROOT=""

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then
    echo "INFO: keeping fixtures under $TMP_ROOT"
    return 0
  fi
  [[ -n "${TMP_ROOT:-}" && -d "$TMP_ROOT" ]] && rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

log_pass() { echo "PASS $*"; }
log_fail() { echo "FAIL $*" >&2; FAILED=1; }
log_skip() { echo "SKIP $*"; exit 42; }
log_info() { echo "  $*"; }

check_deps() {
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  [[ -f "$LINT" ]] || log_info "NOTE: $LINT missing (expected only on the pre-change RED tree)"
  TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aai-spec-lint-test.XXXXXX")"
}

# Make a fresh fixture root with docs/specs and return its path via $FIX.
new_fixture_root() {
  FIX="$(mktemp -d "$TMP_ROOT/fix.XXXXXX")"
  mkdir -p "$FIX/docs/specs"
}

# Write a fixture spec. Args: <path> ; body on stdin.
write_spec() {
  cat > "$1"
}

# Run the lint CLI from a given root. Args: <root> [cli args...]
runlint() {
  local root="$1"; shift
  (cd "$root" && node "$LINT" "$@")
}

# Canonical clean spec body (frozen, strategy, 2 ACs, mapped Test Plan).
clean_spec_body() {
  cat <<'EOF'
---
id: spec-fixture-clean
type: spec
number: null
status: implementing
links:
  pr: []
---

# Fixture — clean

SPEC-FROZEN: true

## Implementation strategy
- Strategy: loop
- Rationale: fixture

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | run-1    | —         | —     |
| Spec-AC-02 | second      | planned | —       | —         | —     |

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | unit | tests/x.sh           | a           | green  |
| TEST-002 | Spec-AC-02 | unit | tests/x.sh           | b           | pending |
EOF
}

# Assert the last runlint produced exit code $1 (actual in $2), label $3.
expect_exit() {
  local want="$1" got="$2" label="$3"
  if [[ "$got" -ne "$want" ]]; then
    log_info "$label: exit $got (want $want)"
    return 1
  fi
  return 0
}

# --- TEST-001 — duplicate Spec-AC id ------------------------------------------
test_001_duplicate_id() {
  new_fixture_root
  # duplicate the id; keep the Test Plan resolvable (TEST-002 maps to Spec-AC-01)
  clean_spec_body | sed 's/| Spec-AC-02 | second/| Spec-AC-01 | second/; s/| TEST-002 | Spec-AC-02 |/| TEST-002 | Spec-AC-01 |/' \
    > "$FIX/docs/specs/SPEC-DRAFT-dup.md"
  local out rc ok=1
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 1 "$rc" "TEST-001" || ok=0
  echo "$out" | grep -q "ac-id-duplicate" || { log_info "TEST-001: no ac-id-duplicate in output"; ok=0; }
  echo "$out" | grep -q "Spec-AC-01" || { log_info "TEST-001: duplicate id not named"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-001 duplicate Spec-AC id" || log_fail "TEST-001 duplicate Spec-AC id"
}

# --- TEST-002 — id gap + malformed id ------------------------------------------
test_002_gap_and_malformed() {
  new_fixture_root
  clean_spec_body | sed 's/Spec-AC-02/Spec-AC-03/g' > "$FIX/docs/specs/SPEC-DRAFT-gap.md"
  local out rc ok=1
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 1 "$rc" "TEST-002 gap" || ok=0
  echo "$out" | grep -q "ac-id-gap" || { log_info "TEST-002: no ac-id-gap"; ok=0; }
  echo "$out" | grep -q "Spec-AC-02" || { log_info "TEST-002: missing id not named"; ok=0; }

  new_fixture_root
  clean_spec_body | sed 's/| Spec-AC-02 |/| Spec-AC-2 |/; s/| TEST-002 | Spec-AC-02 |/| TEST-002 | Spec-AC-01 |/' \
    > "$FIX/docs/specs/SPEC-DRAFT-malformed.md"
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 1 "$rc" "TEST-002 malformed" || ok=0
  echo "$out" | grep -q "ac-id-malformed" || { log_info "TEST-002: no ac-id-malformed"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-002 id gap + malformed id" || log_fail "TEST-002 id gap + malformed id"
}

# --- TEST-003 — done without evidence + qualified-status control ----------------
test_003_done_without_evidence() {
  new_fixture_root
  clean_spec_body | sed 's/| Spec-AC-01 | first       | done   | run-1    |/| Spec-AC-01 | first       | done   | — |/' \
    > "$FIX/docs/specs/SPEC-DRAFT-noev.md"
  local out rc ok=1
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 1 "$rc" "TEST-003" || ok=0
  echo "$out" | grep -q "done-without-evidence" || { log_info "TEST-003: no done-without-evidence"; ok=0; }

  # control: qualified canonical status WITH evidence is clean
  new_fixture_root
  clean_spec_body | sed 's/| Spec-AC-01 | first       | done   |/| Spec-AC-01 | first       | done (pre-existing) |/' \
    > "$FIX/docs/specs/SPEC-DRAFT-qualified.md"
  runlint "$FIX" >/dev/null 2>&1; rc=$?
  expect_exit 0 "$rc" "TEST-003 qualified control" || ok=0
  [[ $ok -eq 1 ]] && log_pass "TEST-003 done-without-evidence (+qualified control)" || log_fail "TEST-003 done-without-evidence"
}

# --- TEST-004 — Test Plan mapping: unknown, range/list controls, malformed ------
test_004_test_plan_mapping() {
  new_fixture_root
  clean_spec_body | sed 's/| TEST-002 | Spec-AC-02 |/| TEST-002 | Spec-AC-09 |/' \
    > "$FIX/docs/specs/SPEC-DRAFT-unknown.md"
  local out rc ok=1
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 1 "$rc" "TEST-004 unknown" || ok=0
  echo "$out" | grep -q "test-ac-unknown" || { log_info "TEST-004: no test-ac-unknown"; ok=0; }
  echo "$out" | grep -q "Spec-AC-09" || { log_info "TEST-004: unknown id not named"; ok=0; }

  # control: comma list + NN..MM range both resolve
  new_fixture_root
  clean_spec_body | sed 's/| TEST-001 | Spec-AC-01 |/| TEST-001 | Spec-AC-01, Spec-AC-02 |/; s/| TEST-002 | Spec-AC-02 |/| TEST-002 | Spec-AC-01..02 |/' \
    > "$FIX/docs/specs/SPEC-DRAFT-listrange.md"
  runlint "$FIX" >/dev/null 2>&1; rc=$?
  expect_exit 0 "$rc" "TEST-004 list/range control" || ok=0

  # malformed: dash cell
  new_fixture_root
  clean_spec_body | sed 's/| TEST-002 | Spec-AC-02 |/| TEST-002 | — |/' \
    > "$FIX/docs/specs/SPEC-DRAFT-dashcell.md"
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 1 "$rc" "TEST-004 malformed" || ok=0
  echo "$out" | grep -q "test-ac-malformed" || { log_info "TEST-004: no test-ac-malformed"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-004 Test Plan mapping" || log_fail "TEST-004 Test Plan mapping"
}

# --- TEST-005 — SPEC-FROZEN consistency + lean L1 exemption ----------------------
test_005_frozen_consistency() {
  local out rc ok=1
  # frozen + undecided strategy
  new_fixture_root
  clean_spec_body | sed 's/- Strategy: loop/- Strategy: undecided/' \
    > "$FIX/docs/specs/SPEC-DRAFT-undecided.md"
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 1 "$rc" "TEST-005 undecided" || ok=0
  echo "$out" | grep -q "frozen-without-strategy" || { log_info "TEST-005: no frozen-without-strategy"; ok=0; }

  # frozen + no AC table
  new_fixture_root
  clean_spec_body | awk '/## Acceptance Criteria Status/{skip=1} /## Test Plan/{skip=0} !skip' \
    > "$FIX/docs/specs/SPEC-DRAFT-notable.md"
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 1 "$rc" "TEST-005 no table" || ok=0
  echo "$out" | grep -q "frozen-without-ac-table" || { log_info "TEST-005: no frozen-without-ac-table"; ok=0; }

  # lean L1 control: ceremony_level 1 + justification, AC table only, no strategy
  new_fixture_root
  write_spec "$FIX/docs/specs/SPEC-DRAFT-lean.md" <<'EOF'
---
id: spec-fixture-lean
type: spec
number: null
status: implementing
ceremony_level: 1
links:
  pr: []
---

# Fixture — lean L1

SPEC-FROZEN: true

Ceremony justification: single-surface fixture fix.

## Acceptance Criteria Status

| Spec-AC    | Description | Status  | Evidence | Review-By | Notes |
|------------|-------------|---------|----------|-----------|-------|
| Spec-AC-01 | only        | planned | —        | —         | —     |

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | unit | tests/x.sh           | a           | pending |
EOF
  runlint "$FIX" >/dev/null 2>&1; rc=$?
  expect_exit 0 "$rc" "TEST-005 lean L1 control" || ok=0
  [[ $ok -eq 1 ]] && log_pass "TEST-005 SPEC-FROZEN consistency (+lean L1 exemption)" || log_fail "TEST-005 SPEC-FROZEN consistency"
}

# --- TEST-006 — ceremony enum + invalid AC status --------------------------------
test_006_ceremony_and_status() {
  local out rc ok=1
  for bad in banana 7; do
    new_fixture_root
    clean_spec_body | awk -v b="$bad" '{print} /^status: implementing/{print "ceremony_level: " b}' \
      > "$FIX/docs/specs/SPEC-DRAFT-cl.md"
    out="$(runlint "$FIX" 2>&1)"; rc=$?
    expect_exit 1 "$rc" "TEST-006 cl=$bad" || ok=0
    echo "$out" | grep -q "ceremony-level-invalid" || { log_info "TEST-006: no ceremony-level-invalid for $bad"; ok=0; }
  done

  # null / absent are clean
  new_fixture_root
  clean_spec_body | awk '{print} /^status: implementing/{print "ceremony_level: null"}' \
    > "$FIX/docs/specs/SPEC-DRAFT-clnull.md"
  runlint "$FIX" >/dev/null 2>&1; rc=$?
  expect_exit 0 "$rc" "TEST-006 null control" || ok=0

  # invalid AC status token
  new_fixture_root
  clean_spec_body | sed 's/| Spec-AC-02 | second      | planned |/| Spec-AC-02 | second      | finished |/' \
    > "$FIX/docs/specs/SPEC-DRAFT-badstatus.md"
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 1 "$rc" "TEST-006 bad status" || ok=0
  echo "$out" | grep -q "ac-status-invalid" || { log_info "TEST-006: no ac-status-invalid"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-006 ceremony enum + status enum" || log_fail "TEST-006 ceremony enum + status enum"
}

# --- TEST-007 — parser-invisible AC row (escaped pipes, pre-fix SPEC-0012 shape) --
test_007_unparseable_row() {
  new_fixture_root
  # The Evidence cell carries markdown-escaped pipes, so the raw split yields
  # more cells than the header and the shared parser DROPS the row.
  write_spec "$FIX/docs/specs/SPEC-DRAFT-escpipe.md" <<'EOF'
---
id: spec-fixture-escpipe
type: spec
number: null
status: implementing
links:
  pr: []
---

# Fixture — escaped pipes

SPEC-FROZEN: true

## Implementation strategy
- Strategy: loop
- Rationale: fixture

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | run-1    | —         | —     |
| Spec-AC-02 | second      | done   | notes preserved (`\|-`/`>+`/`\|`) run-2 | — | — |

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | unit | tests/x.sh           | a           | green  |
| TEST-002 | Spec-AC-02 | unit | tests/x.sh           | b           | green  |
EOF
  local out rc ok=1
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 1 "$rc" "TEST-007" || ok=0
  echo "$out" | grep -q "ac-row-unparseable" || { log_info "TEST-007: no ac-row-unparseable"; ok=0; }
  echo "$out" | grep -q "Spec-AC-02" || { log_info "TEST-007: dropped row id not named"; ok=0; }

  # Review F1 negative control: a COMPACT (unpadded) but valid row must NOT
  # fire ac-row-unparseable — the old \S* capture swallowed pipes and mangled
  # the id into the whole pipe-run.
  new_fixture_root
  write_spec "$FIX/docs/specs/SPEC-DRAFT-compact.md" <<'EOF'
---
id: spec-fixture-compact
type: spec
number: null
status: implementing
links:
  pr: []
---

# Fixture — compact rows

SPEC-FROZEN: true

## Implementation strategy
- Strategy: loop
- Rationale: fixture

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---------|-------------|--------|----------|-----------|-------|
|Spec-AC-01|compact|done|run-1|—|—|

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | unit | tests/x.sh           | a           | green  |
EOF
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-007b" || ok=0
  echo "$out" | grep -q "ac-row-unparseable" && { log_info "TEST-007b: compact valid row falsely flagged (F1)"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-007 parser-invisible AC row (+compact negative control)" || log_fail "TEST-007 parser-invisible AC row"
}

# --- TEST-008 — default scan, research skip, usage errors, --json shape ----------
test_008_cli_contract() {
  local out rc ok=1
  new_fixture_root
  clean_spec_body > "$FIX/docs/specs/SPEC-DRAFT-a.md"
  clean_spec_body | sed 's/id: spec-fixture-clean/id: spec-fixture-b/' > "$FIX/docs/specs/SPEC-DRAFT-b.md"
  # research doc with a broken table must be SKIPPED by the default scan
  clean_spec_body | sed 's/^type: spec/type: research/; s/| Spec-AC-02 | second/| Spec-AC-01 | second/' \
    > "$FIX/docs/specs/RES-0001-fixture.md"
  out="$(runlint "$FIX" --json 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-008 clean scan" || ok=0
  echo "$out" | node -e '
    let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
      const j=JSON.parse(s);
      if (j.scanned !== 2 || j.skipped !== 1 || j.clean !== true || !Array.isArray(j.findings) || j.findings.length !== 0) {
        console.error("bad json: " + s); process.exit(1);
      }
    });' || { log_info "TEST-008: --json shape wrong"; ok=0; }

  runlint "$FIX" --bogus >/dev/null 2>&1; rc=$?
  expect_exit 2 "$rc" "TEST-008 unknown flag" || ok=0
  runlint "$FIX" --path docs/specs/NOPE.md >/dev/null 2>&1; rc=$?
  expect_exit 2 "$rc" "TEST-008 unreadable path" || ok=0
  [[ $ok -eq 1 ]] && log_pass "TEST-008 CLI contract (scan/skip/json/usage)" || log_fail "TEST-008 CLI contract"
}

# --- TEST-009 — REAL corpus lints clean ------------------------------------------
test_009_real_corpus() {
  local out rc
  out="$(runlint "$PROJECT_ROOT" 2>&1)"; rc=$?
  if [[ $rc -eq 0 ]]; then
    log_pass "TEST-009 real corpus clean (exit 0)"
  else
    log_info "TEST-009 output: $out"
    log_fail "TEST-009 real corpus clean (exit $rc)"
  fi
}

# --- TEST-010 — advisory wiring (PLANNING post-freeze, VALIDATION step 1) --------
test_010_advisory_wiring() {
  local ok=1 f n
  for f in .aai/PLANNING.prompt.md .aai/VALIDATION.prompt.md; do
    n=$(grep -c "spec-lint.mjs" "$PROJECT_ROOT/$f" || true)
    if [[ "$n" -lt 1 ]]; then
      log_info "TEST-010: $f has no spec-lint.mjs advisory"; ok=0
    fi
    if [[ "$n" -gt 2 ]]; then
      log_info "TEST-010: $f mentions spec-lint.mjs on $n lines (max 2)"; ok=0
    fi
    # the advisory block (lines mentioning spec-lint or its degrade) must be <= 2 lines
    n=$(grep -c "spec-lint" "$PROJECT_ROOT/$f" || true)
    if [[ "$n" -gt 2 ]]; then
      log_info "TEST-010: $f carries $n spec-lint lines (max 2)"; ok=0
    fi
    grep -q "spec-lint" "$PROJECT_ROOT/$f" && \
      grep -A1 -B1 "spec-lint" "$PROJECT_ROOT/$f" | grep -qi "absent" \
      || { log_info "TEST-010: $f advisory lacks a degrade clause"; ok=0; }
    grep -A1 -B1 "spec-lint" "$PROJECT_ROOT/$f" | grep -qi "advisor" \
      || { log_info "TEST-010: $f advisory not marked advisory/report-only"; ok=0; }
  done
  # no step renumbering: PLANNING steps 11/12 and VALIDATION step 2 intact
  grep -q "^11) Emit the work-item brief" "$PROJECT_ROOT/.aai/PLANNING.prompt.md" \
    || { log_info "TEST-010: PLANNING step 11 heading changed"; ok=0; }
  grep -q "^12) Update docs/ai/STATE.yaml" "$PROJECT_ROOT/.aai/PLANNING.prompt.md" \
    || { log_info "TEST-010: PLANNING step 12 heading changed"; ok=0; }
  grep -q "^2) Inventory all requirements" "$PROJECT_ROOT/.aai/VALIDATION.prompt.md" \
    || { log_info "TEST-010: VALIDATION step 2 heading changed"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-010 advisory wiring (<=2 lines, degrade, no renumber)" || log_fail "TEST-010 advisory wiring"
}

# --- TEST-011 — seam survival: strict audit, prompt-diet floor, index stability --
test_011_seam_survival() {
  local ok=1
  if ! node "$PROJECT_ROOT/.aai/scripts/docs-audit.mjs" --check --strict --no-event >/dev/null 2>&1; then
    log_info "TEST-011: repo-wide strict audit failed"; ok=0
  fi
  if ! (cd "$PROJECT_ROOT" && bash tests/skills/test-aai-prompt-diet.sh >/dev/null 2>&1); then
    log_info "TEST-011: prompt-diet suite failed"; ok=0
  fi
  # index double-regeneration stability, modulo the Generated stamp
  local snap1 snap2
  (cd "$PROJECT_ROOT" && node .aai/scripts/generate-docs-index.mjs >/dev/null 2>&1)
  snap1="$(grep -v '^Generated:' "$PROJECT_ROOT/docs/INDEX.md" | shasum | cut -d' ' -f1)"
  (cd "$PROJECT_ROOT" && node .aai/scripts/generate-docs-index.mjs >/dev/null 2>&1)
  snap2="$(grep -v '^Generated:' "$PROJECT_ROOT/docs/INDEX.md" | shasum | cut -d' ' -f1)"
  if [[ "$snap1" != "$snap2" ]]; then
    log_info "TEST-011: index regeneration not stable ($snap1 vs $snap2)"; ok=0
  fi
  [[ $ok -eq 1 ]] && log_pass "TEST-011 seam survival (audit/diet/index)" || log_fail "TEST-011 seam survival"
}

# Build a spec = clean body + a `## Deltas` section (block content on stdin).
# The delta-stage-2 fixtures reuse the clean spec so the ONLY findings under
# test are the new delta-* codes (RFC-0011 delta-spec lifecycle).
with_deltas() {
  clean_spec_body
  printf '\n## Deltas\n\n'
  cat
  printf '\n'
}

# --- TEST-003 (delta-stage-2) — spec-lint validates the `## Deltas` shape ------
# A well-formed section yields ZERO delta findings; each malformed variant emits
# exactly its D2 code. (spec-delta-stage-2 Test Plan TEST-003.)
test_delta_003_shape() {
  local out rc ok=1

  # well-formed: one ADDED (no NNN), one MODIFIED, one REMOVED -> clean
  new_fixture_root
  with_deltas > "$FIX/docs/specs/SPEC-DRAFT-deltas-clean.md" <<'EOF'
### ADDED REQ-OAUTH2_LOGIN — Password grant retired
The system SHALL reject the OAuth2 password grant on the login endpoint.

- Scenario: WHEN a password-grant token request arrives THEN it is refused with 400.

### MODIFIED REQ-AUTH-001 — Session expiry tightened
The system SHALL expire an idle session after 15 minutes.

### REMOVED REQ-AUTH-009
EOF
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-003 clean deltas" || ok=0
  echo "$out" | grep -q "delta-" && { log_info "TEST-003: well-formed Deltas produced a delta finding: $out"; ok=0; }

  # malformed variants -> one code each (fixture path names the expected code)
  local block code
  delta_case() {
    code="$1"; shift
    new_fixture_root
    with_deltas > "$FIX/docs/specs/SPEC-DRAFT-$code.md"
    out="$(runlint "$FIX" 2>&1)"; rc=$?
    expect_exit 1 "$rc" "TEST-003 $code exit" || ok=0
    # Assert on the bracketed RULE token, not a bare substring — the fixture
    # filename (SPEC-DRAFT-$code.md) also contains $code, so a substring grep
    # would match the path regardless of which rule actually fired (review F3).
    echo "$out" | grep -qF "[$code]" || { log_info "TEST-003: no [$code] rule emitted; got: $out"; ok=0; }
  }

  delta_case delta-op-invalid <<'EOF'
### RENAMED REQ-AUTH-001 — bad op
The system SHALL x.
EOF
  delta_case delta-added-numbered <<'EOF'
### ADDED REQ-AUTH-001 — numbered add
The system SHALL x.
EOF
  delta_case delta-id-malformed <<'EOF'
### MODIFIED REQ-auth-1 — lowercase kebab unpadded id
The system SHALL x.
EOF
  delta_case delta-domain-underivable <<'EOF'
### ADDED REQ-Auth — mixed-case domain
The system SHALL x.
EOF
  delta_case delta-shall-count <<'EOF'
### MODIFIED REQ-AUTH-002 — two shalls
The system SHALL a.
The system SHALL b.
EOF
  delta_case delta-scenario-malformed <<'EOF'
### ADDED REQ-AUTH — bad scenario
The system SHALL x.

- Scenario: missing the keywords entirely.
EOF
  delta_case delta-duplicate <<'EOF'
### MODIFIED REQ-AUTH-004 — first
The system SHALL a.

### REMOVED REQ-AUTH-004
EOF

  [[ $ok -eq 1 ]] && log_pass "TEST-003 (delta-stage-2) Deltas shape validation" || log_fail "TEST-003 (delta-stage-2) Deltas shape validation"
}

# --- TEST-004 (delta-stage-2) — legacy control: no `## Deltas` = zero new findings
# A spec with NO Deltas section produces zero delta findings (byte-identical
# finding set to pre-change); the whole real corpus stays LINT PASS.
# (spec-delta-stage-2 Test Plan TEST-004.)
test_delta_004_legacy_control() {
  local out rc ok=1

  # a plain clean spec (no `## Deltas`) lints clean, emits no delta-* finding
  new_fixture_root
  clean_spec_body > "$FIX/docs/specs/SPEC-DRAFT-legacy.md"
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-004 legacy clean" || ok=0
  echo "$out" | grep -q "delta-" && { log_info "TEST-004: legacy spec produced a delta finding"; ok=0; }

  # a present-but-empty `## Deltas` section is a valid state -> no finding
  new_fixture_root
  with_deltas > "$FIX/docs/specs/SPEC-DRAFT-emptydeltas.md" <<'EOF'
EOF
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-004 empty deltas" || ok=0
  echo "$out" | grep -q "delta-" && { log_info "TEST-004: empty Deltas section produced a finding"; ok=0; }

  # the REAL corpus (no `## Deltas` sections today) stays LINT PASS with no delta-*
  out="$(runlint "$PROJECT_ROOT" 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-004 real corpus" || ok=0
  echo "$out" | grep -q "delta-" && { log_info "TEST-004: real corpus produced a delta finding"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-004 (delta-stage-2) legacy/empty Deltas unaffected; corpus LINT PASS" || log_fail "TEST-004 (delta-stage-2) legacy control"
}

# --- SPEC-0051 TEST-001 — dropped-duplicate reconciliation (Spec-AC-01/02) ------
# A duplicate Spec-AC-02 whose second copy is dropped by an escaped-pipe
# cell-count break: the surviving copy seeds knownIds (silencing
# ac-row-unparseable) and only the surviving copy reaches ac.rows (silencing
# ac-id-duplicate) — the raw-vs-parsed reconciliation is the ONLY thing that
# can still catch it.
test_dupac_001_dropped_duplicate() {
  new_fixture_root
  write_spec "$FIX/docs/specs/SPEC-DRAFT-dupac-dropped.md" <<'EOF'
---
id: spec-fixture-dupac-dropped
type: spec
number: null
status: implementing
links:
  pr: []
---

# Fixture — duplicate id, one copy dropped by escaped pipe

SPEC-FROZEN: true

## Implementation strategy
- Strategy: loop
- Rationale: fixture

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | run-1    | —         | —     |
| Spec-AC-02 | second      | done   | run-2    | —         | —     |
| Spec-AC-02 | second-dup  | done   | notes preserved (`\|-`/`>+`/`\|`) run-3 | — | — |

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|-----------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | unit | tests/x.sh            | a           | green  |
| TEST-002 | Spec-AC-02 | unit | tests/x.sh            | b           | green  |
EOF
  local out rc ok=1
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 1 "$rc" "TEST-001(dupac)" || ok=0
  echo "$out" | grep -q "duplicate-ac-id" || { log_info "TEST-001(dupac): no duplicate-ac-id finding"; ok=0; }
  echo "$out" | grep -q "Spec-AC-02" || { log_info "TEST-001(dupac): repeated id not named"; ok=0; }
  # Spec-AC-02: detail reports the raw-vs-parsed delta (2 raw rows, 1 survived).
  echo "$out" | grep -qE "Spec-AC-02 appears in 2 raw AC-table rows but only 1 survived" \
    || { log_info "TEST-001(dupac): raw-vs-parsed delta (2 raw / 1 parsed) not reported: $out"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-001(dupac) dropped-duplicate names id + raw-vs-parsed delta" || log_fail "TEST-001(dupac) dropped-duplicate reconciliation"
}

# --- SPEC-0051 TEST-002 — both copies parse: existing rule only (Spec-AC-03) ----
# A duplicate id whose BOTH copies parse is already caught by ac-id-duplicate;
# the new rule must NOT also fire (rawCount == parsedCount == 2, so rc > pc is
# false).
test_dupac_002_both_parse_no_double_report() {
  new_fixture_root
  clean_spec_body | sed 's/| Spec-AC-02 | second/| Spec-AC-01 | second/; s/| TEST-002 | Spec-AC-02 |/| TEST-002 | Spec-AC-01 |/' \
    > "$FIX/docs/specs/SPEC-DRAFT-dupac-bothparse.md"
  local out rc ok=1
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 1 "$rc" "TEST-002(dupac)" || ok=0
  echo "$out" | grep -q "ac-id-duplicate" || { log_info "TEST-002(dupac): no ac-id-duplicate"; ok=0; }
  echo "$out" | grep -q "duplicate-ac-id" && { log_info "TEST-002(dupac): both-parse dup falsely ALSO fired duplicate-ac-id: $out"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-002(dupac) both-parse duplicate -> ac-id-duplicate only" || log_fail "TEST-002(dupac) both-parse no double-report"
}

# --- SPEC-0051 TEST-003 — fully-vanished row: existing rule only (Spec-AC-03) ---
# A single (non-duplicated) row dropped by the shared parser is already caught
# by ac-row-unparseable; the new rule must NOT also fire (parsedCount == 0, so
# the pc >= 1 guard excludes it).
test_dupac_003_vanished_no_double_report() {
  new_fixture_root
  write_spec "$FIX/docs/specs/SPEC-DRAFT-dupac-vanished.md" <<'EOF'
---
id: spec-fixture-dupac-vanished
type: spec
number: null
status: implementing
links:
  pr: []
---

# Fixture — single row fully dropped, no surviving copy

SPEC-FROZEN: true

## Implementation strategy
- Strategy: loop
- Rationale: fixture

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | first       | done   | run-1    | —         | —     |
| Spec-AC-02 | second      | done   | notes preserved (`\|-`/`>+`/`\|`) run-2 | — | — |

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|-----------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | unit | tests/x.sh            | a           | green  |
EOF
  local out rc ok=1
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 1 "$rc" "TEST-003(dupac)" || ok=0
  echo "$out" | grep -q "ac-row-unparseable" || { log_info "TEST-003(dupac): no ac-row-unparseable"; ok=0; }
  echo "$out" | grep -q "duplicate-ac-id" && { log_info "TEST-003(dupac): fully-vanished row falsely ALSO fired duplicate-ac-id: $out"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-003(dupac) fully-vanished row -> ac-row-unparseable only" || log_fail "TEST-003(dupac) vanished-row no double-report"
}

# --- SPEC-0051 TEST-004 — no false positives on legitimate shapes (Spec-AC-04) --
# A clean gate table with a compact row plus a Test-Plan Spec-AC-NN..MM range,
# and a genuine lean L1 AC table (no Review-By column, !ac.hasGate), must each
# emit zero duplicate-ac-id findings.
test_dupac_004_no_false_positives() {
  local out rc ok=1

  # clean gate table: compact rows (rc == pc) + a Test-Plan range reference
  # (range rows never enter rawCount — the (?=\s|\|) lookahead excludes them).
  new_fixture_root
  write_spec "$FIX/docs/specs/SPEC-DRAFT-dupac-compact-range.md" <<'EOF'
---
id: spec-fixture-dupac-compact-range
type: spec
number: null
status: implementing
links:
  pr: []
---

# Fixture — compact rows + Test-Plan range, no duplicates

SPEC-FROZEN: true

## Implementation strategy
- Strategy: loop
- Rationale: fixture

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---------|-------------|--------|----------|-----------|-------|
|Spec-AC-01|first|done|run-1|—|—|
|Spec-AC-02|second|done|run-2|—|—|

## Test Plan

| Test ID  | Spec-AC        | Type | File path (expected) | Description | Status |
|----------|----------------|------|-----------------------|-------------|--------|
| TEST-001 | Spec-AC-01..02 | unit | tests/x.sh            | a           | green  |
EOF
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-004(dupac) compact+range" || ok=0
  echo "$out" | grep -q "duplicate-ac-id" && { log_info "TEST-004(dupac): compact+range fixture falsely fired duplicate-ac-id: $out"; ok=0; }

  # genuine lean L1 table (no Review-By column -> !ac.hasGate): the new rule
  # lives INSIDE the if (ac.hasGate) branch, so it can never run here.
  new_fixture_root
  write_spec "$FIX/docs/specs/SPEC-DRAFT-dupac-lean.md" <<'EOF'
---
id: spec-fixture-dupac-lean
type: spec
number: null
status: implementing
ceremony_level: 1
links:
  pr: []
---

# Fixture — lean L1, no canonical gate table

SPEC-FROZEN: true

Ceremony justification: single-surface fixture fix.

## Acceptance Criteria Status

| Spec-AC    | Status  |
|------------|---------|
| Spec-AC-01 | planned |

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | unit | tests/x.sh           | a           | pending |
EOF
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-004(dupac) lean L1" || ok=0
  echo "$out" | grep -q "duplicate-ac-id" && { log_info "TEST-004(dupac): lean L1 fixture falsely fired duplicate-ac-id: $out"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-004(dupac) no false positives (compact/range/lean)" || log_fail "TEST-004(dupac) no false positives"
}

# --- SPEC-0051 TEST-005 — real corpus + full suite stay clean (Spec-AC-05) ------
# The real repo corpus lints with zero duplicate-ac-id findings; "existing
# suite stays green with zero assertion edits" is proven by this same suite
# run (test_001..test_011, test_delta_003/004 above) staying green end to end.
test_dupac_005_real_corpus() {
  local out rc ok=1
  out="$(runlint "$PROJECT_ROOT" 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-005(dupac) real corpus" || ok=0
  echo "$out" | grep -q "duplicate-ac-id" && { log_info "TEST-005(dupac): real corpus produced a duplicate-ac-id finding: $out"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-005(dupac) real corpus zero duplicate-ac-id findings" || log_fail "TEST-005(dupac) real corpus"
}

# --- SPEC-0058 TEST-001 — bare-slug spec id flagged (Spec-AC-01) ----------------
# A type: spec fixture whose id is a bare slug (neither numbered SPEC-NNNN nor
# spec--prefixed) — otherwise clean — must yield exactly one spec-id-shape
# finding naming the id and the spec-<change-slug> guidance; exit 1.
test_specidshape_001_bareslug_flagged() {
  new_fixture_root
  clean_spec_body | sed 's/^id: spec-fixture-clean/id: secrets-preflight-env-multiline/' \
    > "$FIX/docs/specs/SPEC-DRAFT-bareslug.md"
  local out rc ok=1 n
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 1 "$rc" "TEST-001(specidshape)" || ok=0
  n=$(echo "$out" | grep -c "\[spec-id-shape\]")
  [[ "$n" -eq 1 ]] || { log_info "TEST-001(specidshape): expected exactly 1 spec-id-shape finding, got $n: $out"; ok=0; }
  echo "$out" | grep -q 'secrets-preflight-env-multiline' || { log_info "TEST-001(specidshape): id not named in finding"; ok=0; }
  echo "$out" | grep -q 'spec-<change-slug>' || { log_info "TEST-001(specidshape): spec-<change-slug> guidance missing"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-001(specidshape) bare-slug spec id flagged" || log_fail "TEST-001(specidshape) bare-slug spec id flagged"
}

# --- SPEC-0058 TEST-002 — negative controls: prefixed / numbered ids clean (Spec-AC-02) --
# A spec--prefixed id and a legacy numbered SPEC-NNNN id each lint CLEAN.
test_specidshape_002_negative_controls() {
  local out rc ok=1

  # spec--prefixed control (clean_spec_body's id is already spec-fixture-clean)
  new_fixture_root
  clean_spec_body > "$FIX/docs/specs/SPEC-DRAFT-prefixed.md"
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-002(specidshape) prefixed" || ok=0
  echo "$out" | grep -q "spec-id-shape" && { log_info "TEST-002(specidshape): spec--prefixed id falsely flagged: $out"; ok=0; }

  # legacy numbered SPEC-NNNN control
  new_fixture_root
  clean_spec_body | sed 's/^id: spec-fixture-clean/id: SPEC-0099/' \
    > "$FIX/docs/specs/SPEC-DRAFT-numbered.md"
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-002(specidshape) numbered" || ok=0
  echo "$out" | grep -q "spec-id-shape" && { log_info "TEST-002(specidshape): numbered SPEC-NNNN id falsely flagged: $out"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-002(specidshape) prefixed + numbered ids lint clean" || log_fail "TEST-002(specidshape) negative controls"
}

# --- SPEC-0058 TEST-003 — type guard: non-spec doc via --path not flagged (Spec-AC-02) --
# The check runs ONLY for type: spec docs. A type: research doc with a
# bare-slug id, linted via --path (any-type entry point), is NOT flagged.
test_specidshape_003_type_guard() {
  new_fixture_root
  clean_spec_body | sed 's/^id: spec-fixture-clean/id: bare-research-slug/; s/^type: spec/type: research/' \
    > "$FIX/docs/specs/SPEC-DRAFT-research.md"
  local out rc ok=1
  out="$(runlint "$FIX" --path docs/specs/SPEC-DRAFT-research.md 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-003(specidshape)" || ok=0
  echo "$out" | grep -q "spec-id-shape" && { log_info "TEST-003(specidshape): non-spec --path doc falsely flagged: $out"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-003(specidshape) type guard: non-spec --path doc not flagged" || log_fail "TEST-003(specidshape) type guard"
}

# --- SPEC-0058 TEST-004 — real-corpus loop: zero spec-id-shape findings (Spec-AC-03) --
# An explicit loop over every real docs/specs/SPEC-*.md (read-only, not a mock)
# asserts zero spec-id-shape findings — the corpus is clean post-remediation.
test_specidshape_004_real_corpus_loop() {
  local ok=1 f rel out rc
  for f in "$PROJECT_ROOT"/docs/specs/SPEC-*.md; do
    [[ -f "$f" ]] || continue
    rel="docs/specs/$(basename "$f")"
    out="$(cd "$PROJECT_ROOT" && node "$LINT" --path "$rel" 2>&1)"; rc=$?
    if echo "$out" | grep -q "spec-id-shape"; then
      log_info "TEST-004(specidshape): $rel produced a spec-id-shape finding: $out"; ok=0
    fi
    if [[ $rc -eq 2 ]]; then
      log_info "TEST-004(specidshape): $rel unreadable (exit 2): $out"; ok=0
    fi
  done
  [[ $ok -eq 1 ]] && log_pass "TEST-004(specidshape) real-corpus loop: zero spec-id-shape findings" || log_fail "TEST-004(specidshape) real-corpus loop"
}

# --- SPEC-0058 TEST-005 — fixture-id alignment regression guard (Spec-AC-03) ----
# Every existing type: spec fixture id in THIS file was mechanically spec--
# prefixed so the new rule doesn't break prior expect-clean stanzas. Guard
# against a future fixture being added without the prefix (which would flip an
# expect-clean stanza to a false positive under the new rule).
test_specidshape_005_fixture_alignment_regression() {
  local hits
  hits="$(grep -n '^id: fixture-' "$PROJECT_ROOT/tests/skills/test-aai-spec-lint.sh" || true)"
  if [[ -n "$hits" ]]; then
    log_info "TEST-005(specidshape): unprefixed type:spec fixture id(s) found (would trip spec-id-shape): $hits"
    log_fail "TEST-005(specidshape) fixture-id alignment regression guard"
  else
    log_pass "TEST-005(specidshape) fixture-id alignment regression guard (no unprefixed fixture ids)"
  fi
}

# --- CHANGE-0122 strategy-scaled evidence (TEST-001..TEST-007) -----------------
# Evidence requirements scale with the RECORDED implementation strategy: a spec
# whose strategy is direct/untested but whose evidence-bearing sections demand a
# STORED RED artifact / TDD-cycle evidence is a mismatch the planner must fix at
# freeze (the ride that motivated CHANGE-0122 paid two extra agent runs for
# evidence its own strategy never promised).

# Spec body = clean body + a `## Verification` section DEMANDING a stored RED
# artifact. Args: <strategy> — the literal `none` omits the `- Strategy:` line
# and declares ceremony_level 1 (strategy is exempt there, so the fixture stays
# otherwise clean and proves the fail-open path).
red_demanding_body() {
  local strategy="$1"
  if [[ "$strategy" == "none" ]]; then
    clean_spec_body \
      | grep -v '^- Strategy: ' \
      | awk '{print} /^status: implementing/{print "ceremony_level: 1"}' \
      | awk '{print} /^SPEC-FROZEN: true/{print ""; print "Ceremony justification: single-surface fixture fix."}'
  else
    clean_spec_body | sed "s/^- Strategy: loop/- Strategy: $strategy/"
  fi
  cat <<'EOF'

## Verification
- Commands to run: bash tests/skills/test-x.sh
- Evidence artifacts: a stored RED log under docs/ai/tdd/ is required for every
  AC-gating test before its green run may count.
EOF
}

# --- CHANGE-0122 TEST-001 — direct strategy + RED demand is a finding -----------
test_stratev_001_direct_demanding_red() {
  new_fixture_root
  red_demanding_body direct > "$FIX/docs/specs/SPEC-DRAFT-direct-red.md"
  local out rc ok=1 n
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 1 "$rc" "TEST-001(stratev)" || ok=0
  n=$(echo "$out" | grep -c "\[strategy-evidence-mismatch\]")
  [[ "$n" -ge 1 ]] || { log_info "TEST-001(stratev): no strategy-evidence-mismatch finding: $out"; ok=0; }
  echo "$out" | grep -q "direct" || { log_info "TEST-001(stratev): recorded strategy not named"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-001(stratev) direct-strategy spec demanding a stored RED artifact is flagged" \
    || log_fail "TEST-001(stratev) direct-strategy RED demand"
}

# --- CHANGE-0122 TEST-002 — the SAME text under tdd/hybrid is clean -------------
test_stratev_002_tdd_hybrid_unchanged() {
  local out rc ok=1 s
  for s in tdd hybrid; do
    new_fixture_root
    red_demanding_body "$s" > "$FIX/docs/specs/SPEC-DRAFT-$s-red.md"
    out="$(runlint "$FIX" 2>&1)"; rc=$?
    expect_exit 0 "$rc" "TEST-002(stratev) $s" || ok=0
    echo "$out" | grep -q "strategy-evidence-mismatch" \
      && { log_info "TEST-002(stratev): $s strategy falsely flagged: $out"; ok=0; }
  done
  [[ $ok -eq 1 ]] && log_pass "TEST-002(stratev) identical RED demand under tdd/hybrid stays clean" \
    || log_fail "TEST-002(stratev) tdd/hybrid non-regression"
}

# --- CHANGE-0122 TEST-003 — untested fires; unknown strategy fails OPEN ---------
test_stratev_003_untested_and_unknown() {
  local out rc ok=1
  new_fixture_root
  red_demanding_body untested > "$FIX/docs/specs/SPEC-DRAFT-untested-red.md"
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 1 "$rc" "TEST-003(stratev) untested" || ok=0
  echo "$out" | grep -q "strategy-evidence-mismatch" \
    || { log_info "TEST-003(stratev): untested not flagged: $out"; ok=0; }

  # unknown strategy (no recorded value anywhere) -> NO finding, exit 0
  new_fixture_root
  red_demanding_body none > "$FIX/docs/specs/SPEC-DRAFT-nostrategy-red.md"
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-003(stratev) unknown" || ok=0
  echo "$out" | grep -q "strategy-evidence-mismatch" \
    && { log_info "TEST-003(stratev): unknown strategy produced a finding (must fail open): $out"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-003(stratev) untested flagged; unknown strategy fails open" \
    || log_fail "TEST-003(stratev) untested + fail-open"
}

# --- CHANGE-0122 TEST-004 — negative controls (no false findings) ---------------
# (a) a direct spec that EXPLICITLY waives the stored RED artifact;
# (b) a direct spec whose Implementation-strategy RATIONALE discusses RED-first
#     TDD (the real SPEC-0110 shape — rationale prose is not a demand).
test_stratev_004_negative_controls() {
  local out rc ok=1
  new_fixture_root
  clean_spec_body | sed 's/^- Strategy: loop/- Strategy: direct/' \
    > "$FIX/docs/specs/SPEC-DRAFT-direct-waived.md"
  cat >> "$FIX/docs/specs/SPEC-DRAFT-direct-waived.md" <<'EOF'

## Verification
- Commands to run: bash tests/skills/test-x.sh
- Evidence artifacts: targeted regression tests green plus the scoped diff. No
  stored RED log is required on this direct ride.
EOF
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-004(stratev) waiver" || ok=0
  echo "$out" | grep -q "strategy-evidence-mismatch" \
    && { log_info "TEST-004(stratev): explicit waiver falsely flagged: $out"; ok=0; }

  new_fixture_root
  clean_spec_body \
    | sed 's/^- Strategy: loop/- Strategy: direct/' \
    | sed 's/^- Rationale: fixture/- Rationale: RED-first TDD ceremony would outweigh a one-line fix; a stored RED log proves nothing here./' \
    > "$FIX/docs/specs/SPEC-DRAFT-direct-rationale.md"
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-004(stratev) rationale" || ok=0
  echo "$out" | grep -q "strategy-evidence-mismatch" \
    && { log_info "TEST-004(stratev): strategy-rationale prose falsely flagged: $out"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-004(stratev) negative controls (explicit waiver, rationale prose)" \
    || log_fail "TEST-004(stratev) negative controls"
}

# --- CHANGE-0122 TEST-005 — --strategy supplies the value the spec omits --------
# Orchestration/dispatch knows STATE's recorded strategy even when a lean spec
# records none; the flag makes that value explicit and wins over the spec line.
test_stratev_005_strategy_flag() {
  local out rc ok=1
  new_fixture_root
  red_demanding_body none > "$FIX/docs/specs/SPEC-DRAFT-flag.md"
  local p=docs/specs/SPEC-DRAFT-flag.md
  out="$(runlint "$FIX" --path "$p" --strategy direct 2>&1)"; rc=$?
  expect_exit 1 "$rc" "TEST-005(stratev) flag direct" || ok=0
  echo "$out" | grep -q "strategy-evidence-mismatch" \
    || { log_info "TEST-005(stratev): --strategy direct did not supply the strategy: $out"; ok=0; }

  out="$(runlint "$FIX" --path "$p" --strategy tdd 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-005(stratev) flag tdd" || ok=0
  echo "$out" | grep -q "strategy-evidence-mismatch" \
    && { log_info "TEST-005(stratev): --strategy tdd still flagged: $out"; ok=0; }

  # the flag OUTRANKS the spec's own record (STATE is the authority the caller has)
  new_fixture_root
  red_demanding_body direct > "$FIX/docs/specs/SPEC-DRAFT-override.md"
  out="$(runlint "$FIX" --path docs/specs/SPEC-DRAFT-override.md --strategy tdd 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-005(stratev) flag outranks body" || ok=0

  runlint "$FIX" --path "$p" --strategy >/dev/null 2>&1; rc=$?
  expect_exit 2 "$rc" "TEST-005(stratev) flag needs a value" || ok=0
  runlint "$FIX" --path "$p" --strategy banana >/dev/null 2>&1; rc=$?
  expect_exit 2 "$rc" "TEST-005(stratev) flag enum" || ok=0
  # a corpus-wide scan must NOT accept a single ride's strategy
  runlint "$FIX" --strategy direct >/dev/null 2>&1; rc=$?
  expect_exit 2 "$rc" "TEST-005(stratev) flag requires --path" || ok=0
  [[ $ok -eq 1 ]] && log_pass "TEST-005(stratev) --strategy override (supplies value, outranks body, enum-guarded, --path-scoped)" \
    || log_fail "TEST-005(stratev) --strategy override"
}

# --- CHANGE-0122 TEST-006 — template + PLANNING carry the evidence contract -----
test_stratev_006_template_and_prompt() {
  local ok=1 tpl="$PROJECT_ROOT/.aai/templates/SPEC_TEMPLATE.md"
  local plan="$PROJECT_ROOT/.aai/PLANNING.prompt.md"
  grep -qi "Evidence by strategy" "$tpl" \
    || { log_info "TEST-006(stratev): SPEC_TEMPLATE has no per-strategy evidence table heading"; ok=0; }
  local s
  for s in "tdd / hybrid" "direct" "untested"; do
    grep -q "^| $s " "$tpl" \
      || { log_info "TEST-006(stratev): SPEC_TEMPLATE evidence table has no '$s' row"; ok=0; }
  done
  grep -qi "^| direct .*no stored RED" "$tpl" \
    || { log_info "TEST-006(stratev): direct row does not state NO stored RED artifact"; ok=0; }
  grep -q "^| tdd / hybrid .*RED artifact" "$tpl" \
    || { log_info "TEST-006(stratev): tdd/hybrid row does not keep the RED artifact requirement"; ok=0; }
  grep -qi "evidence.*strategy\|strategy.*evidence" "$plan" \
    || { log_info "TEST-006(stratev): PLANNING has no strategy-scaled evidence pointer"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-006(stratev) SPEC_TEMPLATE evidence table + PLANNING pointer" \
    || log_fail "TEST-006(stratev) template + prompt wiring"
}

# --- CHANGE-0122 TEST-007 — real corpus: zero strategy-evidence-mismatch --------
test_stratev_007_real_corpus() {
  local out rc ok=1
  out="$(runlint "$PROJECT_ROOT" 2>&1)"; rc=$?
  [[ $rc -eq 2 ]] && { log_info "TEST-007(stratev): real-corpus scan errored: $out"; ok=0; }
  echo "$out" | grep -q "strategy-evidence-mismatch" \
    && { log_info "TEST-007(stratev): real corpus produced a strategy-evidence-mismatch: $out"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-007(stratev) real corpus: zero strategy-evidence-mismatch findings" \
    || log_fail "TEST-007(stratev) real corpus"
}

test_stratev_template_no_selfflag() {
  # bot P2 (#228): a direct spec derived from SPEC_TEMPLATE must NOT self-flag
  # on the template's own "### Evidence by strategy" guidance or on sentences
  # documenting the rule itself.
  log_info "TEST-008(stratev): template-derived direct spec lints clean..."
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/sl-t8.XXXXXX")"
  cp "$PROJECT_ROOT/.aai/templates/SPEC_TEMPLATE.md" "$d/SPEC-0001-spec-t8.md"
  perl -0pi -e 's/^- Strategy: .*/- Strategy: direct/m' "$d/SPEC-0001-spec-t8.md" 2>/dev/null     || sed -i.bak -E 's/^- Strategy: .*/- Strategy: direct/' "$d/SPEC-0001-spec-t8.md"
  # CHANGE-0120: was "$SPEC_LINT" — an undefined name, so under this suite's
  # `set -u` the lint NEVER ran and the assertion below was vacuously true.
  # The suite's script variable is $LINT.
  local out; out="$(node "$LINT" --path "$d/SPEC-0001-spec-t8.md" 2>&1)" || true
  if printf '%s' "$out" | grep -q 'strategy-evidence-mismatch'; then
    log_fail "TEST-008(stratev): template guidance self-flagged: $out"
  fi
  rm -rf "$d"
  log_pass "TEST-008(stratev): template-derived direct spec clean"
}

# --- CHANGE-0120 half-frozen -------------------------------------------------
#
# Freeze is a TWO-PART state: the `SPEC-FROZEN: true` body marker AND
# frontmatter `status: implementing`. Writing one without the other is the
# paperwork half-state that bounced a live ride back to Planning. spec-lint
# flags it at WRITE time so the mismatch cannot survive to dispatch;
# spec-freeze.mjs is the tool that cannot produce it.

# half_frozen_body <frontmatter-status> <marker true|false>
half_frozen_body() {
  local status="$1" marker="$2"
  clean_spec_body \
    | sed "s/^status: implementing$/status: $status/" \
    | { if [[ "$marker" == "true" ]]; then cat; else grep -v '^SPEC-FROZEN: true$'; fi; }
}

test_halffrozen_001_marker_without_status() {
  local out rc ok=1 s
  # draft / proposed / accepted + marker == half-frozen (the live incident).
  for s in draft proposed accepted; do
    new_fixture_root
    half_frozen_body "$s" true > "$FIX/docs/specs/SPEC-DRAFT-hf-$s.md"
    out="$(runlint "$FIX" 2>&1)"; rc=$?
    expect_exit 1 "$rc" "TEST-001(halffrozen) $s" || ok=0
    echo "$out" | grep -q "half-frozen" \
      || { log_info "TEST-001(halffrozen): marker + status $s not flagged: $out"; ok=0; }
  done
  [[ $ok -eq 1 ]] && log_pass "TEST-001(halffrozen) SPEC-FROZEN marker without status implementing is a finding" \
    || log_fail "TEST-001(halffrozen) marker-without-status"
}

test_halffrozen_002_status_without_marker() {
  local out rc ok=1
  new_fixture_root
  half_frozen_body implementing false > "$FIX/docs/specs/SPEC-DRAFT-hf-nomarker.md"
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 1 "$rc" "TEST-002(halffrozen)" || ok=0
  echo "$out" | grep -q "half-frozen" \
    || { log_info "TEST-002(halffrozen): status implementing without the marker not flagged: $out"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-002(halffrozen) status implementing without the SPEC-FROZEN marker is a finding" \
    || log_fail "TEST-002(halffrozen) status-without-marker"
}

test_halffrozen_003_negative_controls() {
  local out rc ok=1
  # (a) the canonical BOTH-halves state is clean.
  new_fixture_root
  half_frozen_body implementing true > "$FIX/docs/specs/SPEC-DRAFT-hf-ok.md"
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-003(halffrozen) both halves" || ok=0
  echo "$out" | grep -q "half-frozen" \
    && { log_info "TEST-003(halffrozen): a correctly frozen spec was flagged: $out"; ok=0; }

  # (b) NEITHER half (an unfrozen draft) is clean — this rule is about the
  # MIXED state only, never about un-frozen planning drafts.
  new_fixture_root
  half_frozen_body draft false > "$FIX/docs/specs/SPEC-DRAFT-hf-neither.md"
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-003(halffrozen) neither half" || ok=0
  echo "$out" | grep -q "half-frozen" \
    && { log_info "TEST-003(halffrozen): an unfrozen draft was flagged: $out"; ok=0; }

  # (c) a `done` spec with no marker is HISTORY, not a half-freeze: the rule's
  # status arm is scoped to `implementing` so the legacy corpus stays clean.
  new_fixture_root
  half_frozen_body done false > "$FIX/docs/specs/SPEC-DRAFT-hf-done.md"
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-003(halffrozen) done without marker" || ok=0
  echo "$out" | grep -q "half-frozen" \
    && { log_info "TEST-003(halffrozen): a done spec without the marker was flagged: $out"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-003(halffrozen) negative controls: both halves / neither half / legacy done stay clean" \
    || log_fail "TEST-003(halffrozen) negative controls"
}

test_halffrozen_004_real_corpus() {
  local out rc ok=1
  out="$(cd "$PROJECT_ROOT" && node "$LINT" 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-004(halffrozen) real corpus" || ok=0
  echo "$out" | grep -q "half-frozen" \
    && { log_info "TEST-004(halffrozen): real corpus produced a half-frozen finding: $out"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-004(halffrozen) real corpus zero half-frozen findings" \
    || log_fail "TEST-004(halffrozen) real corpus"
}

# === R21 (CHANGE-0113 D2 probe) — AC -> TEST reverse coverage =================
# spec-lint has always checked TEST->AC (`test-ac-unknown`); the REVERSE
# direction — a Spec-AC no Test Plan row claims — had NO detector, and the
# altitude replay (docs/analysis/altitude-replay.md, task T3) showed it is
# exactly the shape a shorter Planning prompt regresses to.

# --- TEST-001(actest) — a freezable spec with an untested AC is flagged --------
test_actest_001_untested_ac() {
  new_fixture_root
  # Drop the Test Plan row that covers Spec-AC-02: the AC survives, its test
  # does not. `test-ac-unknown` cannot see this — the reverse rule must.
  clean_spec_body | grep -v '^| TEST-002 ' > "$FIX/docs/specs/SPEC-DRAFT-untested.md"
  local out rc ok=1
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 1 "$rc" "TEST-001(actest)" || ok=0
  echo "$out" | grep -q "ac-without-test" || { log_info "TEST-001(actest): no ac-without-test finding: $out"; ok=0; }
  echo "$out" | grep -q "Spec-AC-02" || { log_info "TEST-001(actest): untested id not named: $out"; ok=0; }
  echo "$out" | grep -q "ac-without-test.*Spec-AC-01" \
    && { log_info "TEST-001(actest): the COVERED AC was flagged too: $out"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-001(actest) untested Spec-AC flagged, covered one is not" \
    || log_fail "TEST-001(actest) untested Spec-AC"
}

# --- TEST-002(actest) — negative controls: covered ACs, ranges, lists ----------
test_actest_002_negative_controls() {
  local rc ok=1
  # a) the canonical clean fixture (1 row per AC) stays clean
  new_fixture_root
  clean_spec_body > "$FIX/docs/specs/SPEC-DRAFT-clean.md"
  runlint "$FIX" >/dev/null 2>&1; rc=$?
  expect_exit 0 "$rc" "TEST-002(actest) clean control" || ok=0

  # b) ONE row covering BOTH ACs via a comma list is full coverage
  new_fixture_root
  clean_spec_body | grep -v '^| TEST-002 ' \
    | sed 's/| TEST-001 | Spec-AC-01 |/| TEST-001 | Spec-AC-01, Spec-AC-02 |/' \
    > "$FIX/docs/specs/SPEC-DRAFT-listcover.md"
  runlint "$FIX" >/dev/null 2>&1; rc=$?
  expect_exit 0 "$rc" "TEST-002(actest) comma-list coverage control" || ok=0

  # c) the NN..MM range form is coverage too
  new_fixture_root
  clean_spec_body | grep -v '^| TEST-002 ' \
    | sed 's/| TEST-001 | Spec-AC-01 |/| TEST-001 | Spec-AC-01..02 |/' \
    > "$FIX/docs/specs/SPEC-DRAFT-rangecover.md"
  runlint "$FIX" >/dev/null 2>&1; rc=$?
  expect_exit 0 "$rc" "TEST-002(actest) range coverage control" || ok=0
  [[ $ok -eq 1 ]] && log_pass "TEST-002(actest) covered ACs (row / list / range) produce no finding" \
    || log_fail "TEST-002(actest) coverage negative controls"
}

# --- TEST-003(actest) — lean L0/L1 tables use the SAME reverse rule ------------
test_actest_003_lean_table() {
  local out rc ok=1
  new_fixture_root
  write_spec "$FIX/docs/specs/SPEC-DRAFT-leanuntested.md" <<'EOF'
---
id: spec-fixture-lean-untested
type: spec
number: null
status: accepted
ceremony_level: 1
links:
  pr: []
---

# Fixture — lean L1, one AC untested

Ceremony justification: single-surface fixture fix.

## Acceptance Criteria

| Spec-AC    | Description | Status  |
|------------|-------------|---------|
| Spec-AC-01 | covered     | planned |
| Spec-AC-02 | untested    | planned |

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | unit | tests/x.sh           | a           | pending |
EOF
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 1 "$rc" "TEST-003(actest) lean untested" || ok=0
  echo "$out" | grep -q "ac-without-test" || { log_info "TEST-003(actest): lean table AC not checked: $out"; ok=0; }
  echo "$out" | grep -q "Spec-AC-02" || { log_info "TEST-003(actest): lean untested id not named: $out"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-003(actest) lean L1 AC table gets the same reverse check" \
    || log_fail "TEST-003(actest) lean table reverse check"
}

# --- TEST-004(actest) — a TERMINAL spec is history, not a finding --------------
# The rule is a freeze-boundary obligation. A `done` spec's Test Plan is
# history (suites get renamed, folded, archived); re-litigating it produces
# noise, not action — and the 12 real corpus specs in that shape are exactly
# why the scope is the FREEZABLE statuses.
test_actest_004_terminal_scope() {
  local out rc ok=1
  new_fixture_root
  clean_spec_body | grep -v '^| TEST-002 ' | sed 's/^status: implementing$/status: done/' \
    > "$FIX/docs/specs/SPEC-DRAFT-doneuntested.md"
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  echo "$out" | grep -q "ac-without-test" \
    && { log_info "TEST-004(actest): a done spec was flagged: $out"; ok=0; }

  # and the mirror: the SAME body at an in-flight status IS flagged
  new_fixture_root
  clean_spec_body | grep -v '^| TEST-002 ' | sed 's/^status: implementing$/status: draft/' \
    | sed '/^SPEC-FROZEN: true$/d' > "$FIX/docs/specs/SPEC-DRAFT-draftuntested.md"
  out="$(runlint "$FIX" 2>&1)"; rc=$?
  expect_exit 1 "$rc" "TEST-004(actest) draft arm" || ok=0
  echo "$out" | grep -q "ac-without-test" \
    || { log_info "TEST-004(actest): a draft spec was NOT flagged: $out"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-004(actest) terminal specs exempt, in-flight specs checked" \
    || log_fail "TEST-004(actest) terminal-status scope"
}

# --- TEST-005(actest) — the real corpus stays CLEAN ----------------------------
test_actest_005_real_corpus() {
  local out rc ok=1
  out="$(cd "$PROJECT_ROOT" && node "$LINT" 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-005(actest) real corpus" || ok=0
  echo "$out" | grep -q "ac-without-test" \
    && { log_info "TEST-005(actest): real corpus produced an ac-without-test finding: $out"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-005(actest) real corpus zero ac-without-test findings" \
    || log_fail "TEST-005(actest) real corpus"
}

main() {
  echo "=== $TEST_NAME ==="
  check_deps
  test_001_duplicate_id
  test_002_gap_and_malformed
  test_003_done_without_evidence
  test_004_test_plan_mapping
  test_005_frozen_consistency
  test_006_ceremony_and_status
  test_007_unparseable_row
  test_008_cli_contract
  test_009_real_corpus
  test_010_advisory_wiring
  test_011_seam_survival
  test_delta_003_shape
  test_delta_004_legacy_control
  test_dupac_001_dropped_duplicate
  test_dupac_002_both_parse_no_double_report
  test_dupac_003_vanished_no_double_report
  test_dupac_004_no_false_positives
  test_dupac_005_real_corpus
  test_specidshape_001_bareslug_flagged
  test_specidshape_002_negative_controls
  test_specidshape_003_type_guard
  test_specidshape_004_real_corpus_loop
  test_specidshape_005_fixture_alignment_regression
  test_stratev_001_direct_demanding_red
  test_stratev_002_tdd_hybrid_unchanged
  test_stratev_003_untested_and_unknown
  test_stratev_004_negative_controls
  test_stratev_005_strategy_flag
  test_stratev_006_template_and_prompt
  test_stratev_007_real_corpus
  test_stratev_template_no_selfflag
  test_halffrozen_001_marker_without_status
  test_halffrozen_002_status_without_marker
  test_halffrozen_003_negative_controls
  test_halffrozen_004_real_corpus
  test_actest_001_untested_ac
  test_actest_002_negative_controls
  test_actest_003_lean_table
  test_actest_004_terminal_scope
  test_actest_005_real_corpus

  echo ""
  if [[ $FAILED -eq 0 ]]; then
    echo "All tests passed!"
    exit 0
  else
    echo "Some tests FAILED."
    exit 1
  fi
}

# Sourcing-compatible: run main only when executed directly (per-test TDD evidence).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
