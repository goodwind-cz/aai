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
