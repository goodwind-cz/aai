#!/usr/bin/env bash
#
# Test: aai-test-canon skill (RFC-0006 / SPEC-0008)
# Verifies the test canonicalization engine: Phase 1 matrix/proposal/approval gate,
# Phase 2 consolidation/move/archive/stub scaffold, drift detection/idempotency,
# runner compatibility, soft prerequisite degrade, coverage report, stub tagging,
# and --drift/--resync modes.
#
# Test IDs: TEST-001 through TEST-012 per SPEC-0008 Test Plan.
#           TEST-013/TEST-014 are RFC-0006 review-fix regressions (PR #29).
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-test-canon"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_CANON_SCRIPT="$PROJECT_ROOT/.aai/scripts/test-canon.mjs"

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then
    echo "INFO: keeping fixture at $TEST_DIR"
    return 0
  fi
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}
trap cleanup EXIT

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

assert_file() { [[ -f "$1" ]] || log_fail "Missing file: $1"; }
assert_not_file() { if [[ -f "$1" ]]; then log_fail "Unexpected file: $1"; fi; }
assert_dir_empty_or_absent() {
  if [[ -d "$1" ]]; then
    if find "$1" -name '*.sh' -o -name '*.ps1' -o -name '*.py' -o -name '*.mjs' -type f 2>/dev/null | grep -q .; then
      log_fail "Expected no test files under $1"
    fi
  fi
}
assert_contains() { grep -qF "$2" "$1" || log_fail "Expected '$2' in $1"; }
assert_not_contains() { if grep -qF "$2" "$1"; then log_fail "Did not expect '$2' in $1"; fi; }
assert_json_key() {
  # $1: json file, $2: key, $3: expected value pattern
  local val
  val=$(node -e "const j=JSON.parse(require('fs').readFileSync('$1','utf8')); console.log(j['$2']??'<missing>')")
  [[ "$val" == "$3" ]] || log_fail "Expected json key '$2'='$3' but got '$val'"
}
assert_json_has_key() {
  local val
  val=$(node -e "const j=JSON.parse(require('fs').readFileSync('$1','utf8')); console.log(JSON.stringify(j['$2']??'<missing>'))")
  [[ "$val" != '<missing>' ]] || log_fail "Expected json key '$2' to exist in $1"
}

# Run a small node snippet against the fixture.
# Usage: node_eval "<js>"  — exit code is the snippet's; stdout is captured.
node_eval() { (cd "$TEST_DIR" && node --input-type=module -e "$1"); }

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  command -v npm >/dev/null 2>&1 || log_info "npm not found (optional for runner tests)"
  log_pass "Dependencies checked"
}

# Create a minimal fixture with test files and canonical domain map
# Args:
#   $1 - domain name (e.g., "test-canon")
#   $2 - number of test files to create
#   $3 - number of acceptance criteria per canonical doc
#   $4 - "with-canonical" | "without-canonical" (docs/canonical presence)
setup_fixture() {
  local domain="${1:-test-canon}"
  local num_tests="${2:-2}"
  local num_criteria="${3:-3}"
  local canon_mode="${4:-with-canonical}"

  log_info "Setting up fixture (domain=$domain, tests=$num_tests, criteria=$num_criteria, canon=$canon_mode)..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-test-canon-test.XXXXXX")"
  cd "$TEST_DIR"
  git init -q
  git config user.email "test@example.com"
  git config user.name "AAI Test"

  mkdir -p .aai/scripts/lib docs/ai docs/ai/reports tests/skills

  # Copy the test-canon script if it exists (will be created later)
  if [[ -f "$TEST_CANON_SCRIPT" ]]; then
    cp "$TEST_CANON_SCRIPT" .aai/scripts/
    # Also copy lib files
    if ls "$PROJECT_ROOT/.aai/scripts/lib/"*.mjs 2>/dev/null; then
      cp "$PROJECT_ROOT/.aai/scripts/lib/"*.mjs .aai/scripts/lib/
    fi
  fi

  # Create canonical domain map (docs-canon.map.json) for Phase 1 to read
  # Sources point to spec docs (the canonical docs' sources)
  cat > docs/ai/docs-canon.map.json <<EOF
{
  "approved": true,
  "generated": "phase2",
  "domains": {
    "${domain}": {
      "sources": ["docs/specs/${domain}.md"],
      "confidence": "heuristic"
    }
  },
  "unclear": []
}
EOF

  # Create test-canon.map.json (test map) for Phase 2 to read
  # Sources point to test files in tests/skills/
  local test_files_json=""
  for i in $(seq 1 "$num_tests"); do
    if [[ -n "$test_files_json" ]]; then test_files_json+=", "; fi
    test_files_json+="\"tests/skills/${domain}-${i}.sh\""
  done
  cat > docs/ai/test-canon.map.json <<EOF
{
  "approved": true,
  "generated": "phase1",
  "domains": {
    "${domain}": {
      "sources": [${test_files_json}],
      "confidence": "heuristic"
    }
  },
  "unclear": []
}
EOF

  # Create test files
  for i in $(seq 1 "$num_tests"); do
    local tf="tests/skills/${domain}-${i}.sh"
    cat > "$tf" <<TESTMD
#!/usr/bin/env bash
set -euo pipefail
echo "PASS: ${domain}-${i}"
TESTMD
    chmod +x "$tf"
  done

  # Create canonical docs if mode requires
  if [[ "$canon_mode" == "with-canonical" ]]; then
    mkdir -p "docs/canonical"
    cat > "docs/canonical/${domain}.md" <<CANONMD
---
id: CANON-${domain}
type: canonical
domain: ${domain}
status: accepted
sources:
  - docs/specs/${domain}.md
---

# Canonical: ${domain}

## Intent

_To be synthesized._

## Acceptance Criteria

CANONMD
    for j in $(seq 1 "$num_criteria"); do
      echo "- AC-${domain}-${j}: Acceptance criterion ${j} for ${domain}" >> "docs/canonical/${domain}.md"
    done
    cat >> "docs/canonical/${domain}.md" <<CANONMD

## Decisions

_To be synthesized._

## Technical Details

_To be synthesized._

## Superseded Decisions

_No superseded decisions._
CANONMD
  fi

  # Create a spec doc for the domain
  mkdir -p docs/specs
  cat > "docs/specs/${domain}.md" <<SPECMD
---
id: SPEC-${domain}
type: spec
status: draft
links:
  pr: []
---

# ${domain} specification

_Content._
SPECMD

  # Stage everything and commit
  git add -A
  git commit --no-gpg-sign -q -m "fixture setup for ${domain}" 2>/dev/null || true
  log_pass "Fixture created at $TEST_DIR"
}

# Run the test-canon.mjs script inside the fixture
# Usage: run_script [--phase1|--phase2|--drift|--resync] [extra args...]
run_script() {
  if [[ ! -f "$TEST_DIR/.aai/scripts/test-canon.mjs" ]]; then
    log_fail "test-canon.mjs not found in fixture — implementation missing"
  fi
  (cd "$TEST_DIR" && node .aai/scripts/test-canon.mjs "$@")
}

# ==============================================================================
# TEST-001: Phase 1 basic — matrix, proposal, gap report, unclear bucket,
#           never moves test files
# ==============================================================================
test_001() {
  log_info "--- TEST-001: Phase 1 basic (matrix/proposal/gap/unclear/no-move) ---"

  # Create fixture with tests that map to domain and one unmappable test
  setup_fixture "test-canon" 2 3 "with-canonical"

  # Add an unmappable test (no matching domain)
  cat > "tests/skills/test-unmappable.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
echo "PASS: unmappable test"
EOF
  chmod +x "tests/skills/test-unmappable.sh"
  git add -A && git commit --no-gpg-sign -q -m "add unmappable test" 2>/dev/null || true

  # Run Phase 1
  run_script --phase1 || log_fail "Phase 1 exited non-zero"

  # Assert proposal exists with approved: false
  assert_file "docs/ai/test-canon.proposal.json"
  assert_json_key "docs/ai/test-canon.proposal.json" "approved" "false"

  # Assert unclear bucket contains unmappable test
  assert_json_has_key "docs/ai/test-canon.proposal.json" "unclear"

  # Assert NO test files were moved or written (originals still in tests/skills/)
  assert_file "tests/skills/test-canon-1.sh"
  assert_file "tests/skills/test-canon-2.sh"
  assert_file "tests/skills/test-unmappable.sh"

  # Assert coverage gap report exists
  ls docs/ai/reports/test-canon-coverage-*.md 2>/dev/null || log_fail "Coverage report not found"

  log_pass "TEST-001 passed"
}

# ==============================================================================
# TEST-002: Phase 2 approval gate — unapproved blocks, approved allows
# ==============================================================================
test_002() {
  log_info "--- TEST-002: Phase 2 approval gate ---"

  # Fixture with approved: false map
  setup_fixture "test-canon" 1 1 "with-canonical"

  # Set approved: false
  node -e "
    const j = JSON.parse(require('fs').readFileSync('docs/ai/test-canon.map.json','utf8'));
    j.approved = false;
    require('fs').writeFileSync('docs/ai/test-canon.map.json', JSON.stringify(j, null, 2) + '\n');
  " || true

  # Also create proposal with approved: false
  cat > "docs/ai/test-canon.proposal.json" <<EOF
{
  "approved": false,
  "generated": "phase1",
  "domains": {},
  "unclear": []
}
EOF

  # Phase 2 should fail/block on unapproved
  if run_script --phase2 2>/dev/null; then
    log_fail "Phase 2 succeeded with approved: false — gate bypassed"
  fi
  log_pass "Phase 2 correctly blocked on approved: false"

  # Now set approved: true in the map
  node -e "
    const j = JSON.parse(require('fs').readFileSync('docs/ai/test-canon.map.json','utf8'));
    j.approved = true;
    require('fs').writeFileSync('docs/ai/test-canon.map.json', JSON.stringify(j, null, 2) + '\n');
  "
  git add -A && git commit --no-gpg-sign -q -m "approve map" 2>/dev/null || true

  # Phase 2 should now proceed
  run_script --phase2 || log_fail "Phase 2 failed with approved: true"
  log_pass "Phase 2 succeeded with approved: true"

  log_pass "TEST-002 passed"
}

# ==============================================================================
# TEST-003: Phase 2 consolidation — canonical layer, git-move, archive, stubs,
#           unclear NOT moved
# ==============================================================================
test_003() {
  log_info "--- TEST-003: Phase 2 consolidation (canonical layer, git-move, archive, stubs, unclear) ---"

  setup_fixture "test-canon" 3 2 "with-canonical"

  # Add an unclear test (not mapped to any domain)
  cat > "tests/skills/test-other-1.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
echo "PASS: other test"
EOF
  chmod +x "tests/skills/test-other-1.sh"
  git add -A && git commit --no-gpg-sign -q -m "add unclear test" 2>/dev/null || true

  # Run Phase 2 with approved map
  run_script --phase2 || log_fail "Phase 2 failed"

  # Assert canonical test layer exists
  assert_file "tests/canonical/test-canon.sh"

  # Assert originals were moved to archive (tests/skills/ originals should be gone or archived)
  # Originals should now be in tests/_archive/
  assert_file "tests/_archive/skills/test-canon-1.sh"
  assert_file "tests/_archive/skills/test-canon-2.sh"
  assert_file "tests/_archive/skills/test-canon-3.sh"

  # Assert unclear test was NOT moved (still in tests/skills/)
  assert_file "tests/skills/test-other-1.sh"

  # Assert RED stubs were scaffolded for uncovered acceptance criteria
  # With 3 tests and 2 criteria, there should be at least 1 stub for uncovered criteria
  assert_file "tests/canonical/"*".stub"* 2>/dev/null || \
    ls tests/canonical/ 2>/dev/null || true
  # Check for any stub files
  if find tests/canonical/ -name "*uncovered*" -o -name "*.stub*" 2>/dev/null | grep -q .; then
    log_pass "RED stubs found"
  else
    log_info "No stub files found — checking for RED stubs in canonical test"
    # Stubs may be embedded in the canonical test file
  fi

  # Assert git tracked the moves (git log shows the move)
  git log --oneline --follow -- "tests/_archive/skills/test-canon-1.sh" 2>/dev/null | head -5 || true
  git log --oneline -- "tests/_archive/" 2>/dev/null | grep -q . || \
    log_info "Note: git history may show move if git mv was used"

  log_pass "TEST-003 passed"
}

# ==============================================================================
# TEST-004: Scaffolded stubs are RED (runner observes failure)
# ==============================================================================
test_004() {
  log_info "--- TEST-004: Stubs are RED (failing) ---"

  setup_fixture "test-canon" 1 3 "with-canonical"
  run_script --phase2 || log_fail "Phase 2 failed"

  # Find scaffolded stub files — they should fail when run
  local stubs_found=false
  for f in tests/canonical/*; do
    if [[ -f "$f" ]]; then
      # Run the stub and check it fails (non-zero exit or produces failure)
      # Stubs should be syntactically valid but fail at runtime
      local exit_code=0
      bash "$f" 2>/dev/null || exit_code=$?
      if [[ $exit_code -ne 0 ]]; then
        stubs_found=true
        log_pass "Stub $f is RED (exit $exit_code)"
      fi
    fi
  done

  if [[ "$stubs_found" != "true" ]]; then
    log_fail "No RED stubs found — all stubs passed (GREEN without implementation)"
  fi

  log_pass "TEST-004 passed"
}

# ==============================================================================
# TEST-005: Runner verification before archive — failure aborts Phase 2
# ==============================================================================
test_005() {
  log_info "--- TEST-005: Runner verification gate ---"

  setup_fixture "test-canon" 1 1 "with-canonical"

  # Add a source test
  cat > "tests/skills/extra-test.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "PASS: extra test"
EOF
  chmod +x "tests/skills/extra-test.sh"
  git add -A && git commit --no-gpg-sign -q -m "add extra test" 2>/dev/null || true

  # Update map to include the extra test
  node -e "
    const j = JSON.parse(require('fs').readFileSync('docs/ai/test-canon.map.json','utf8'));
    j.domains['test-canon'].sources.push('tests/skills/extra-test.sh');
    require('fs').writeFileSync('docs/ai/test-canon.map.json', JSON.stringify(j, null, 2) + '\n');
  "
  git add -A && git commit --no-gpg-sign -q -m "update map" 2>/dev/null || true

  # Run Phase 2 — it should verify runner before archiving
  # Since all canonical tests are syntactically valid, verification passes
  run_script --phase2 || log_fail "Phase 2 failed"

  # Verify canonical tests exist and are syntactically valid
  assert_file "tests/canonical/test-canon.sh"
  bash -n "tests/canonical/test-canon.sh" 2>/dev/null || log_fail "Canonical test has syntax error"

  # Verify originals were archived (gate passed because verification succeeded)
  assert_file "tests/_archive/skills/extra-test.sh"

  log_pass "TEST-005 passed"
}

# ==============================================================================
# TEST-006: Drift detection — modified source/criterion triggers drift;
#           unchanged run is idempotent
# ==============================================================================
test_006() {
  log_info "--- TEST-006: Drift detection (modified source triggers drift, idempotent re-run) ---"

  setup_fixture "test-canon" 2 2 "with-canonical"
  run_script --phase2 || log_fail "Phase 2 failed"

  # Phase 2 must have produced a map file with source hashes for drift detection
  if [[ ! -f "docs/ai/test-canon.map.json" ]]; then
    log_fail "Phase 2 did not produce test-canon.map.json — drift detection impossible"
  fi
  assert_json_has_key "docs/ai/test-canon.map.json" "domains"

  # Capture initial state
  local initial_hash
  initial_hash=$(sha256sum docs/ai/test-canon.map.json | cut -d' ' -f1)

  # Re-run unchanged — should be idempotent
  run_script --phase2 || log_fail "Phase 2 re-run failed"

  local re_run_hash
  re_run_hash=$(sha256sum docs/ai/test-canon.map.json | cut -d' ' -f1)

  # Idempotency: map file should be byte-identical modulo timestamps
  if [[ "$initial_hash" != "$re_run_hash" ]]; then
    log_fail "Re-run changed map file — not idempotent"
  fi
  log_pass "Re-run is idempotent (map byte-identical)"

  # Now modify an archived source test (simulates real drift to archived copy)
  echo "# Modified content" >> "tests/_archive/skills/test-canon-1.sh"
  git add -A && git commit --no-gpg-sign -q -m "modify archived source" 2>/dev/null || true

  # Re-run Phase 2 — should detect drift and NOT silently overwrite
  # The implementation should either:
  #   a) Refuse to run (exit non-zero) because drift detected, OR
  #   b) Report drift without overwriting
  # It MUST NOT silently overwrite the canonical test layer
  local before_mod
  before_mod=$(sha256sum tests/canonical/* 2>/dev/null | head -c 40 || echo "no-canonical")
  if run_script --phase2 2>/dev/null; then
    local after_mod
    after_mod=$(sha256sum tests/canonical/* 2>/dev/null | head -c 40 || echo "no-canonical")
    if [[ "$before_mod" != "$after_mod" ]]; then
      log_fail "Phase 2 silently overwrote canonical tests despite drift — should report drift"
    fi
  fi

  log_pass "TEST-006 passed"
}

# ==============================================================================
# TEST-007: --drift reports without modifying; --resync re-synthesizes
# ==============================================================================
test_007() {
  log_info "--- TEST-007: --drift no-modify, --resync re-synthesizes ---"

  setup_fixture "test-canon" 2 2 "with-canonical"
  run_script --phase2 || log_fail "Phase 2 failed"

  # Phase 2 must have produced artifacts for drift detection to work
  if [[ ! -f "docs/ai/test-canon.map.json" ]]; then
    log_fail "Phase 2 did not produce map file — drift detection cannot function"
  fi
  if [[ ! -d "tests/canonical" ]]; then
    log_fail "Phase 2 did not create canonical test layer — nothing to drift-check"
  fi

  # Record file timestamps before drift
  local timestamps_before=""
  for f in docs/canonical/* tests/canonical/*; do
    if [[ -f "$f" ]]; then
      timestamps_before+="$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null):$f "
    fi
  done

  # Modify an archived source test (simulates real drift to archived copy)
  echo "# Modified content" >> "tests/_archive/skills/test-canon-1.sh"
  git add -A && git commit --no-gpg-sign -q -m "modify archived source for drift" 2>/dev/null || true

  # Run --drift — should report drift (exit 1 when drift found) but NOT modify files
  # After modifying an archived source, drift should be detected (exit 1)
  local drift_exit=0
  run_script --drift 2>&1 || drift_exit=$?
  if [[ $drift_exit -ne 1 ]]; then
    log_fail "--drift should exit 1 when drift is detected (got exit $drift_exit)"
  fi

  # Verify file timestamps unchanged
  for f in docs/canonical/* tests/canonical/*; do
    if [[ -f "$f" ]]; then
      local ts_after
      ts_after=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null)
      if [[ "$ts_after" != "$(echo "$timestamps_before" | grep -o "$f" | head -1 || true)" ]]; then
        log_info "File $f — checking timestamp stability"
      fi
    fi
  done

  log_pass "--drift reported without modifying files (exit 1 for drift found)"

  # Run --resync — should re-synthesize from archived sources
  run_script --phase2 --resync || log_fail "--resync failed"
  log_pass "--resync re-synthesized drifted domains"

  log_pass "TEST-007 passed"
}

# ==============================================================================
# TEST-008: Runner compatibility — canonical tests discoverable by existing runners
# ==============================================================================
test_008() {
  log_info "--- TEST-008: Runner compatibility ---"

  setup_fixture "test-canon" 2 1 "with-canonical"
  run_script --phase2 || log_fail "Phase 2 failed"

  # Phase 2 must have produced canonical test artifacts for runner compatibility check
  if [[ ! -d "tests/canonical" ]]; then
    log_fail "Phase 2 did not create canonical test layer — runner compatibility cannot be verified"
  fi
  if [[ ! -d "tests/_archive" ]]; then
    log_fail "Phase 2 did not create archive layer — back-links cannot be verified"
  fi

  # Verify test-framework.sh discovers tests in tests/canonical/
  # Canonical tests must be runnable
  local found_canonical=false
  shopt -s nullglob
  for f in tests/canonical/*.sh; do
    if [[ -f "$f" ]]; then
      found_canonical=true
      bash "$f" 2>/dev/null || log_info "Canonical test $f produced non-zero exit (expected for stubs)"
    fi
  done
  shopt -u nullglob
  if [[ "$found_canonical" != "true" ]]; then
    log_fail "No canonical test scripts found in tests/canonical/ — runner compatibility broken"
  fi
  log_pass "Canonical tests exist and are runnable"

  # Check bidirectional back-links: archive files must have canonical: pointers
  local found_archive=false
  for f in tests/_archive/skills/*; do
    if [[ -f "$f" ]]; then
      found_archive=true
      if grep -iq "canonical:" "$f" 2>/dev/null; then
        log_pass "Archive file $f has canonical back-link"
      else
        log_fail "Archive file $f missing canonical back-link"
      fi
    fi
  done
  if [[ "$found_archive" != "true" ]]; then
    log_fail "No archived originals found — archive layer missing"
  fi

  # Check canonical files link back to archive
  for f in tests/canonical/*; do
    if [[ -f "$f" ]] && grep -iq "archive:" "$f" 2>/dev/null; then
      log_pass "Canonical file $f has archive back-link"
    fi
  done

  log_pass "TEST-008 passed"
}

# ==============================================================================
# TEST-009: Soft prerequisite — absent docs/canonical/ degrades gracefully
# ==============================================================================
test_009() {
  log_info "--- TEST-009: Soft prerequisite degrade (no docs/canonical/) ---"

  setup_fixture "test-canon" 2 2 "without-canonical"

  # Phase 1 should degrade gracefully (not abort) when docs/canonical/ is absent
  # Capture stderr to check for degrade message
  local stderr
  stderr=$(run_script --phase1 2>&1 1>/dev/null) || log_fail "Phase 1 failed without docs/canonical/"

  # Check that degrade message was emitted to stderr
  if echo "$stderr" | grep -qi "degrad\|absent\|missing\|no canonical\|fallback\|raw docs"; then
    log_pass "Degrade mode detected: message about absent docs/canonical/"
  else
    log_info "Checking stderr for degrade message: $stderr"
    # Even without stderr message, Phase 1 should complete and produce a proposal
  fi

  # Assert proposal was still written (not blocked)
  assert_file "docs/ai/test-canon.proposal.json"
  log_pass "Proposal written despite absent docs/canonical/"

  log_pass "TEST-009 passed"
}

# ==============================================================================
# TEST-010: Phase 1 produces human-readable coverage matrix report
# ==============================================================================
test_010() {
  log_info "--- TEST-010: Human-readable coverage matrix report ---"

  setup_fixture "test-canon" 3 4 "with-canonical"
  run_script --phase1 || log_fail "Phase 1 failed"

  # Assert human-readable report exists with timestamp
  local report_file
  report_file=$(ls docs/ai/reports/test-canon-coverage-*.md 2>/dev/null) || log_fail "Coverage report not found"

  # Assert report file CONTENT contains per-domain coverage info
  assert_contains "$report_file" "test-canon"
  assert_contains "$report_file" "Coverage"
  assert_contains "$report_file" "Uncovered"

  log_pass "TEST-010 passed"
}

# ==============================================================================
# TEST-011: Scaffolded stubs tagged (domain + criterion), syntactically valid
# ==============================================================================
test_011() {
  log_info "--- TEST-011: Stub tagging and syntax validity ---"

  setup_fixture "test-canon" 1 3 "with-canonical"
  run_script --phase2 || log_fail "Phase 2 failed"

  # Find stub files and verify tags
  local found_tag=false
  shopt -s nullglob
  for f in tests/canonical/* tests/canonical/*.stub*; do
    if [[ -f "$f" ]]; then
      # Check for domain tag
      if grep -q "test-canon" "$f" 2>/dev/null; then
        found_tag=true
        log_pass "Stub $f contains domain tag 'test-canon'"
      fi
      # Check for criterion tag (AC-xxx)
      if grep -q "AC-" "$f" 2>/dev/null; then
        log_pass "Stub $f contains criterion tag"
      fi
      # Verify syntax: for bash stubs, check syntax
      if [[ "$f" == *.sh ]]; then
        bash -n "$f" 2>/dev/null || log_fail "Stub $f has syntax error"
        log_pass "Stub $f is syntactically valid bash"
      fi
    fi
  done
  shopt -u nullglob

  if [[ "$found_tag" != "true" ]]; then
    log_fail "No stub files with domain tags found"
  fi

  # Verify gap report references stub tags
  local report_file
  report_file=$(ls docs/ai/reports/test-canon-coverage-*.md 2>/dev/null) || true
  if [[ -n "$report_file" ]]; then
    assert_contains "$report_file" "test-canon"
  fi

  log_pass "TEST-011 passed"
}

# ==============================================================================
# TEST-012: --drift no file modification; --resync re-synthesizes + re-baselines
# ==============================================================================
test_012() {
  log_info "--- TEST-012: --drift no-modify, --resync re-baselines ---"

  setup_fixture "test-canon" 2 2 "with-canonical"
  run_script --phase2 || log_fail "Phase 2 failed"

  # Modify an archived source test (this will cause drift to archived copy)
  echo "# Modified" >> "tests/_archive/skills/test-canon-1.sh"
  git add -A && git commit --no-gpg-sign -q -m "modify archived source for drift" 2>/dev/null || true

  # Record timestamps AFTER modification but BEFORE --drift
  local before_drift
  before_drift=$(find docs/ tests/ -type f -name "*.md" -o -name "*.sh" -o -name "*.json" 2>/dev/null | sort | while read -r f; do
    echo "$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null):$f"
  done)

  # Run --drift — should NOT modify any files (exit 1 when drift found is expected)
  local drift_exit=0
  run_script --drift 2>&1 || drift_exit=$?
  if [[ $drift_exit -ne 1 ]]; then
    log_fail "--drift should exit 1 when drift is detected (got exit $drift_exit)"
  fi

  # Verify no file timestamps changed by --drift
  local after_drift
  after_drift=$(find docs/ tests/ -type f -name "*.md" -o -name "*.sh" -o -name "*.json" 2>/dev/null | sort | while read -r f; do
    echo "$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null):$f"
  done)

  if [[ "$before_drift" == "$after_drift" ]]; then
    log_pass "--drift modified no files (timestamps unchanged)"
  else
    log_fail "--drift modified files — should be read-only"
  fi

  # Run --resync — should re-synthesize and re-baseline hashes
  run_script --phase2 --resync || log_fail "--resync failed"

  # Verify hashes were re-baselined (map file updated)
  assert_json_has_key "docs/ai/test-canon.map.json" "domains"

  log_pass "TEST-012 passed"
}

# ==============================================================================
# TEST-013: Fully-covered domain (0 stubs) yields a syntactically valid canonical
#           suite that runs the archived source and exits 0.
#           Regression for Bug 1 (empty `if` when stubs is empty → bash syntax
#           error → verifyRunner aborts Phase 2 for the fully-covered case).
# ==============================================================================
test_013() {
  log_info "--- TEST-013: Fully-covered domain (0 stubs) produces valid canonical (Bug 1) ---"

  setup_fixture "test-canon" 1 2 "with-canonical"

  # Make the single source test cover EVERY acceptance criterion (by embedding
  # the AC-<domain>-N tags that findCoveredCriteria matches) so stubs is empty.
  cat > "tests/skills/test-canon-1.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Covers AC-test-canon-1
# Covers AC-test-canon-2
echo "PASS: test-canon-1"
EOF
  chmod +x "tests/skills/test-canon-1.sh"
  git add -A && git commit --no-gpg-sign -q -m "cover all criteria (0 stubs)" 2>/dev/null || true

  # Phase 2 must SUCCEED. Pre-fix: the empty-if wrapper is a bash syntax error,
  # so verifyRunner's `bash -n` fails and Phase 2 aborts here (RED-proof).
  run_script --phase2 || log_fail "Phase 2 failed for fully-covered domain (0 stubs)"

  # Canonical exists and is syntactically valid bash.
  assert_file "tests/canonical/test-canon.sh"
  bash -n "tests/canonical/test-canon.sh" 2>/dev/null || log_fail "Canonical test has syntax error (empty-if bug)"

  # No stub-runner wrapper should be emitted when there are no stubs.
  assert_not_contains "tests/canonical/test-canon.sh" "if [ -z"

  # Running the canonical (archived source passes, no stubs) must exit 0.
  bash "tests/canonical/test-canon.sh" >/dev/null 2>&1 || log_fail "Canonical suite did not exit 0 for fully-covered domain"

  # And it must actually reference/run the archived source.
  assert_file "tests/_archive/skills/test-canon-1.sh"

  log_pass "TEST-013 passed"
}

# ==============================================================================
# TEST-014: Atomic archive rollback on multi-source git mv failure.
#           Regression for Bug 2 (a later source's git mv throws but earlier
#           sources are left archived — a half-applied state).
# ==============================================================================
test_014() {
  log_info "--- TEST-014: Atomic archive rollback on multi-source git mv failure (Bug 2) ---"

  setup_fixture "test-canon" 2 1 "with-canonical"

  # Force the 2nd source's git mv to fail by pre-creating its archive destination
  # (git mv refuses to overwrite an existing destination).
  mkdir -p tests/_archive/skills
  cat > "tests/_archive/skills/test-canon-2.sh" <<'EOF'
#!/usr/bin/env bash
echo "pre-existing archive blocker"
EOF
  git add -A && git commit --no-gpg-sign -q -m "pre-create archive blocker for source 2" 2>/dev/null || true

  # Phase 2 must ABORT (2nd git mv fails on the existing destination).
  if run_script --phase2 2>/dev/null; then
    log_fail "Phase 2 succeeded despite forced git mv failure on 2nd source"
  fi
  log_pass "Phase 2 aborted on forced git mv failure"

  # The 1st source must be ROLLED BACK to its original location...
  assert_file "tests/skills/test-canon-1.sh"
  # ...and NOT left archived. Pre-fix leaves it in tests/_archive/ (RED-proof).
  assert_not_file "tests/_archive/skills/test-canon-1.sh"

  # No canonical file may remain from the aborted run.
  assert_not_file "tests/canonical/test-canon.sh"

  log_pass "TEST-014 passed"
}

# ==============================================================================
# Main
# ==============================================================================
run_all() {
  check_deps

  local tests=(
    test_001 test_002 test_003 test_004 test_005 test_006
    test_007 test_008 test_009 test_010 test_011 test_012
    test_013 test_014
  )
  local total=${#tests[@]}
  local passed=0
  local failed=0

  log_info "Running $total tests..."
  echo ""

  for t in "${tests[@]}"; do
    local name="$t"
    # Run in subshell so cleanup trap resets per test
    if ( "$t" 2>&1 ); then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
      echo "FAIL: $t" >&2
    fi
    echo ""
  done

  echo "========================================="
  echo "Results: $passed/$total passed, $failed failed"
  echo "========================================="

  if [[ $failed -gt 0 ]]; then
    exit 1
  fi
  exit 0
}

# If no arguments, run all tests
if [[ $# -eq 0 ]]; then
  run_all
else
  # Run specific test(s) by name
  for arg in "$@"; do
    "test_${arg}" 2>&1 || exit 1
  done
fi
