#!/usr/bin/env bash
#
# Test: mutation-run.mjs, the runner half of SPEC-DRAFT
# spec-mutation-gate-for-tests (D1-D7, D14). TEST-471, TEST-472, TEST-474,
# TEST-481. Every test drives the REAL .aai/scripts/mutation-run.mjs (never a
# reimplementation) against a throwaway fixture git repository, so a
# regression in the shipped tool is what turns this suite red — never a
# fixture standing in for behaviour the tool does not actually have.
#
# TEST-473 (the selector-fails-closed corpus guard) lives in
# tests/skills/test-aai-hygiene-pack.sh, per the spec's own File-path
# assignment — not duplicated here.
#
# Usage:
#   bash tests/skills/test-aai-mutation-gate.sh              # run all
#   bash tests/skills/test-aai-mutation-gate.sh test_471_runner_isolation
#
# Exit codes: 0 all selected tests passed / 1 a test failed / 2 unknown
# selector / 42 missing dependencies.

set -uo pipefail

TEST_NAME="aai-mutation-gate"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MUTATION_RUN="${AAI_MUTATION_RUN:-$PROJECT_ROOT/.aai/scripts/mutation-run.mjs}"
# Pipe-free payload assertions (spec-assertions-must-not-die-on-their-own-payload).
# shellcheck source=lib/assert-payload.sh
. "$SCRIPT_DIR/lib/assert-payload.sh"

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_info() { echo "INFO: $*"; }
log_skip() { echo "SKIP: $*"; exit 42; }

MG_FIXTURE_DIRS=""
cleanup() {
  local d
  for d in $MG_FIXTURE_DIRS; do
    [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
  done
}
trap cleanup EXIT

check_deps() {
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  [[ -f "$MUTATION_RUN" ]] || log_fail "mutation-run.mjs not found at $MUTATION_RUN"
}

# --- fixture helpers --------------------------------------------------------

# mg_new_fixture -> prints the path to a fresh empty tmpdir; registered for
# cleanup on exit.
mg_new_fixture() {
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/aai-mg-fixture.XXXXXX")"
  MG_FIXTURE_DIRS="$MG_FIXTURE_DIRS $d"
  printf '%s\n' "$d"
}

# mg_seed_repo <dir> — the ONE thing mutation-run.mjs needs from a repo it is
# pointed at: its own aai-run-tests.sh wrapper at the standard path, so
# `bash .aai/scripts/aai-run-tests.sh` inside a clone of the fixture
# resolves exactly as it would in a real AAI checkout.
mg_seed_repo() {
  local d="$1"
  mkdir -p "$d/.aai/scripts" "$d/tests/skills" "$d/lib" "$d/docs/specs"
  cp "$PROJECT_ROOT/.aai/scripts/aai-run-tests.sh" "$d/.aai/scripts/aai-run-tests.sh"
  # Mirror the real repo's .gitignore rule for evidence: the runner's own
  # output directory must never show up as fixture drift.
  printf 'docs/ai/tdd/\n' > "$d/.gitignore"
  ( cd "$d" && git init -q -b main && git config user.email t@example.com && git config user.name fixture )
}

# mg_write_fixture_suite <dir> — a small suite with two test_* functions the
# Test Plan rows below drive. Every FAIL line the fixture itself can print
# names TEST-9001 (a fixture-internal id, unrelated to the real Test Plan
# band) so mutation-run.mjs's own FAIL-line grammar has something to match.
mg_write_fixture_suite() {
  local d="$1"
  cat > "$d/tests/skills/fixture-suite.sh" <<'EOS'
#!/usr/bin/env bash
set -uo pipefail
TEST_NAME="fixture-suite"
FSCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FROOT="$(cd "$FSCRIPT_DIR/../.." && pwd)"
log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }

test_9001_greet_and_marker() {
  local outfile rc out
  outfile="$(mktemp)"
  node "$FROOT/lib/greeting.mjs" >"$outfile" 2>&1
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    # The target crashed before any assertion ran (a broken-syntax mutation):
    # no "FAIL TEST-9001" line here on purpose — this IS the shape the
    # mutation gate's INCONCLUSIVE verdict exists to catch.
    cat "$outfile" >&2
    rm -f "$outfile"
    exit "$rc"
  fi
  out="$(cat "$outfile")"; rm -f "$outfile"
  [[ "$out" == "hello" ]] || log_fail "TEST-9001 greeting mismatch: got '$out' want 'hello'"
  [[ -f "$FROOT/lib/extra.txt" ]] || log_fail "TEST-9001 untracked marker file missing: lib/extra.txt"
  local body; body="$(cat "$FROOT/lib/extra.txt")"
  [[ "$body" == "marker-present" ]] || log_fail "TEST-9001 untracked marker content wrong: got '$body'"
  log_pass "TEST-9001 greeting + untracked marker both correct"
}

main() {
  if [[ -n "${1:-}" ]]; then
    declare -F "$1" >/dev/null || { echo "Unknown test: $1" >&2; exit 2; }
    "$1"
    return
  fi
  test_9001_greet_and_marker
}
main "$@"
EOS
}

mg_write_spec() {
  local d="$1" spec_id="$2"
  cat > "$d/docs/specs/fixture-spec.md" <<EOF
---
id: ${spec_id}
type: spec
status: implementing
---

# Fixture spec (test-only, never read by any real gate)
EOF
}

# mg_record_path <dir> <spec_id> <test_id>
mg_record_path() {
  printf '%s\n' "$1/docs/ai/tdd/$2/mutation-$3.txt"
}

# --- TEST-471 — Spec-AC-01: runner isolation and record shape --------------
test_471_runner_isolation() {
  log_info "Test: mutation-run.mjs builds an isolated clone whose tree hash matches a DIRTY working tree (tracked mod + untracked file) and writes a correct v1 record (TEST-471)..."
  local fx; fx="$(mg_new_fixture)"
  mg_seed_repo "$fx"
  mg_write_fixture_suite "$fx"
  mg_write_spec "$fx" "fixture-spec-471"
  printf "console.log('base');\n" > "$fx/lib/greeting.mjs"
  ( cd "$fx" && git add -A && git commit -q -m base )
  # DIRTY tracked modification (uncommitted) + an untracked file: the clone
  # must reproduce BOTH, or the fixture's own test cannot possibly see them.
  printf "console.log('hello');\n" > "$fx/lib/greeting.mjs"
  printf 'marker-present' > "$fx/lib/extra.txt"

  local status_before status_after
  status_before="$(cd "$fx" && git status --porcelain)"

  local out rc
  out="$(cd "$fx" && node "$MUTATION_RUN" --spec docs/specs/fixture-spec.md --test-id TEST-9001 \
    --suite tests/skills/fixture-suite.sh --selector test_9001_greet_and_marker \
    --target lib/greeting.mjs --sed 's/hello/goodbye/' 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-471: mutation-run.mjs exited $rc on a normal RED run (dirty tree + untracked file): $out"

  status_after="$(cd "$fx" && git status --porcelain)"
  [[ "$status_before" == "$status_after" ]] \
    || log_fail "TEST-471: the fixture's git status changed across the run (before=[$status_before] after=[$status_after]) — the runner must write to docs/ai/tdd/ only"

  local rec; rec="$(mg_record_path "$fx" fixture-spec-471 TEST-9001)"
  [[ -f "$rec" ]] || log_fail "TEST-471: no record written at $rec"

  local content; content="$(cat "$rec")"
  local field
  for field in 'mutation_record: v1' 'spec_id: fixture-spec-471' 'test_id: TEST-9001' \
    'suite: tests/skills/fixture-suite.sh' 'selector: test_9001_greet_and_marker' \
    'target: lib/greeting.mjs' 'verdict: RED'; do
    assert_payload_contains "$content" "$field" "TEST-471: record missing/wrong field '$field'"
  done
  assert_payload_line_matches "$content" '^mutation: sed:s/hello/goodbye/$' \
    "TEST-471: record's mutation field wrong"
  assert_payload_line_matches "$content" '^base_commit: [0-9a-f]{40}$' \
    "TEST-471: record's base_commit is not 40 hex"
  assert_payload_line_matches "$content" '^tree_hash: [0-9a-f]{64}$' \
    "TEST-471: record's tree_hash is not 64 hex"
  assert_payload_line_matches "$content" '^run_at_utc: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' \
    "TEST-471: record's run_at_utc is not ISO 8601 seconds"
  assert_payload_line_matches "$content" '^rc: [0-9]+$' \
    "TEST-471: record's rc is not numeric"
  assert_payload_contains "$content" 'TEST-9001 greeting mismatch' \
    "TEST-471: record's first_fail does not name the fixture's own FAIL line"

  log_pass "TEST-471 clone reproduces a dirty tracked file + an untracked file, the v1 record carries every header field, and the fixture's git status is byte-identical before/after"
}

# --- TEST-472 — Spec-AC-02: runner refusals ---------------------------------
test_472_runner_refusals() {
  log_info "Test: mutation-run.mjs refuses an unknown selector and a no-op mutation, writing no record and leaving no clone (TEST-472)..."
  local fx; fx="$(mg_new_fixture)"
  mg_seed_repo "$fx"
  mg_write_fixture_suite "$fx"
  mg_write_spec "$fx" "fixture-spec-472"
  printf "console.log('hello');\n" > "$fx/lib/greeting.mjs"
  ( cd "$fx" && git add -A && git commit -q -m base )

  local tmp_before tmp_after
  tmp_before="$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'aai-mutation-*' 2>/dev/null | wc -l | tr -d ' ')"

  local out rc
  out="$(cd "$fx" && node "$MUTATION_RUN" --spec docs/specs/fixture-spec.md --test-id TEST-9001 \
    --suite tests/skills/fixture-suite.sh --selector test_9001_does_not_exist \
    --target lib/greeting.mjs --sed 's/hello/goodbye/' 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "TEST-472: unknown selector must exit 2, got $rc: $out"
  assert_payload_contains "$out" "fixture-suite.sh" \
    "TEST-472: unknown-selector refusal must name the suite"
  [[ -e "$(mg_record_path "$fx" fixture-spec-472 TEST-9001)" ]] \
    && log_fail "TEST-472: unknown-selector refusal must write no record"

  out="$(cd "$fx" && node "$MUTATION_RUN" --spec docs/specs/fixture-spec.md --test-id TEST-9001 \
    --suite tests/skills/fixture-suite.sh --selector test_9001_greet_and_marker \
    --target lib/greeting.mjs --sed 's/no_such_pattern_xyz/replacement/' 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "TEST-472: a no-op mutation must exit 2, got $rc: $out"
  assert_payload_contains "$out" "no_such_pattern_xyz" \
    "TEST-472: no-op-mutation refusal must name the expression"
  assert_payload_contains "$out" "lib/greeting.mjs" \
    "TEST-472: no-op-mutation refusal must name the target path"
  [[ -e "$(mg_record_path "$fx" fixture-spec-472 TEST-9001)" ]] \
    && log_fail "TEST-472: no-op-mutation refusal must write no record"

  tmp_after="$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'aai-mutation-*' 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$tmp_before" == "$tmp_after" ]] \
    || log_fail "TEST-472: a refusal must leave no clone directory behind (before=$tmp_before after=$tmp_after)"

  log_pass "TEST-472 both refusals (unknown selector, no-op mutation) exit 2, name the cause, write no record, and leave no clone behind"
}

# --- TEST-474 — Spec-AC-04: three verdicts and rotation ---------------------
test_474_three_verdicts_and_rotation() {
  log_info "Test: STAYED GREEN, INCONCLUSIVE, and record rotation instead of deletion (TEST-474)..."
  local fx; fx="$(mg_new_fixture)"
  mg_seed_repo "$fx"
  mg_write_fixture_suite "$fx"
  mg_write_spec "$fx" "fixture-spec-474"
  printf "console.log('hello');\n" > "$fx/lib/greeting.mjs"
  ( cd "$fx" && git add -A && git commit -q -m base )

  local common=(--spec docs/specs/fixture-spec.md --test-id TEST-9001 \
    --suite tests/skills/fixture-suite.sh --selector test_9001_greet_and_marker --target lib/greeting.mjs)

  # A mutation the test cannot see (drops the trailing semicolon; behavior
  # unchanged) -> STAYED GREEN, exit 5.
  printf 'marker-present' > "$fx/lib/extra.txt"
  local out rc
  out="$(cd "$fx" && node "$MUTATION_RUN" "${common[@]}" --sed "s/'\\);/')/" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 5 ]] || log_fail "TEST-474: an invisible mutation must exit 5 (STAYED GREEN), got $rc: $out"
  local rec1; rec1="$(mg_record_path "$fx" fixture-spec-474 TEST-9001)"
  [[ -f "$rec1" ]] || log_fail "TEST-474: STAYED GREEN must still write a record"
  grep -qF 'verdict: STAYED GREEN' "$rec1" || log_fail "TEST-474: record's verdict is not STAYED GREEN: $(cat "$rec1")"
  local rec1_run_at; rec1_run_at="$(grep '^run_at_utc: ' "$rec1")"
  local rec1_bytes; rec1_bytes="$(cat "$rec1")"

  # A mutation that breaks the target's syntax (unterminated string) -> the
  # fixture's own node invocation crashes before any FAIL line names
  # TEST-9001 -> INCONCLUSIVE, exit 6. Also proves rotation: the STAYED GREEN
  # record from above must survive, byte-identical, under its run-stamped name.
  out="$(cd "$fx" && node "$MUTATION_RUN" "${common[@]}" --sed "s/'hello'/'hello/" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 6 ]] || log_fail "TEST-474: a syntax-breaking mutation must exit 6 (INCONCLUSIVE), got $rc: $out"
  local rec2; rec2="$(mg_record_path "$fx" fixture-spec-474 TEST-9001)"
  [[ -f "$rec2" ]] || log_fail "TEST-474: INCONCLUSIVE must still write a record"
  grep -qF 'verdict: INCONCLUSIVE' "$rec2" || log_fail "TEST-474: record's verdict is not INCONCLUSIVE: $(cat "$rec2")"
  grep -qF 'first_fail: (no FAIL line naming TEST-9001' "$rec2" \
    || log_fail "TEST-474: an INCONCLUSIVE record's first_fail must say no FAIL line named the test (the suite died for another reason): $(cat "$rec2")"

  local rotated; rotated="$(dirname "$rec2")/mutation-TEST-9001.${rec1_run_at#run_at_utc: }.txt"
  [[ -f "$rotated" ]] || log_fail "TEST-474: rotation did not preserve the prior STAYED GREEN record at $rotated"
  [[ "$(cat "$rotated")" == "$rec1_bytes" ]] \
    || log_fail "TEST-474: the rotated record's bytes changed — rotation must never rewrite the old file"

  log_pass "TEST-474 STAYED GREEN (5) and INCONCLUSIVE (6) both record and exit correctly, and the second run rotates the first record aside byte-identical rather than deleting it"
}

# --- TEST-481 — Spec-AC-11: replay ------------------------------------------
test_481_replay() {
  log_info "Test: mutation-run.mjs --replay re-applies every live record and exits non-zero naming a record that no longer reddens or whose target vanished (TEST-481)..."
  local fx; fx="$(mg_new_fixture)"
  mg_seed_repo "$fx"
  mg_write_fixture_suite "$fx"
  mg_write_spec "$fx" "fixture-spec-481"
  printf "console.log('hello');\n" > "$fx/lib/greeting.mjs"
  ( cd "$fx" && git add -A && git commit -q -m base )
  printf 'marker-present' > "$fx/lib/extra.txt"

  local out rc
  out="$(cd "$fx" && node "$MUTATION_RUN" --spec docs/specs/fixture-spec.md --test-id TEST-9001 \
    --suite tests/skills/fixture-suite.sh --selector test_9001_greet_and_marker \
    --target lib/greeting.mjs --sed 's/hello/goodbye/' 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-481 setup: expected a RED record for TEST-9001, got exit $rc: $out"

  printf "console.log('world');\n" > "$fx/lib/farewell.mjs"
  ( cd "$fx" && git add -A && git commit -q -m farewell )
  cat > "$fx/tests/skills/fixture-suite.sh" <<'EOS'
#!/usr/bin/env bash
set -uo pipefail
FSCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FROOT="$(cd "$FSCRIPT_DIR/../.." && pwd)"
log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
test_9001_greet_and_marker() {
  local out; out="$(node "$FROOT/lib/greeting.mjs" 2>&1)"
  [[ "$out" == "hello" ]] || log_fail "TEST-9001 greeting mismatch: got '$out'"
  log_pass "TEST-9001 greeting ok"
}
test_9002_farewell() {
  local out; out="$(node "$FROOT/lib/farewell.mjs" 2>&1)"
  [[ "$out" == "world" ]] || log_fail "TEST-9002 farewell mismatch: got '$out'"
  log_pass "TEST-9002 farewell ok"
}
main() {
  if [[ -n "${1:-}" ]]; then
    declare -F "$1" >/dev/null || { echo "Unknown test: $1" >&2; exit 2; }
    "$1"; return
  fi
  test_9001_greet_and_marker
  test_9002_farewell
}
main "$@"
EOS
  ( cd "$fx" && git add -A && git commit -q -m 'fixture-suite gains test_9002' )

  out="$(cd "$fx" && node "$MUTATION_RUN" --spec docs/specs/fixture-spec.md --test-id TEST-9002 \
    --suite tests/skills/fixture-suite.sh --selector test_9002_farewell \
    --target lib/farewell.mjs --sed 's/world/planet/' 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-481 setup: expected a RED record for TEST-9002, got exit $rc: $out"

  # Arm 1: two live RED records, both still redden -> exit 0.
  out="$(cd "$fx" && node "$MUTATION_RUN" --replay --spec docs/specs/fixture-spec.md 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-481 arm1: --replay of two still-reddening records must exit 0, got $rc: $out"
  assert_payload_contains "$out" "RED TEST-9001" "TEST-481 arm1: replay did not confirm TEST-9001 still reddens"
  assert_payload_contains "$out" "RED TEST-9002" "TEST-481 arm1: replay did not confirm TEST-9002 still reddens"

  # Arm 2: weaken the fixture's own assertion for TEST-9001 so the recorded
  # mutation no longer reddens it (the code under test "fixed") -> exit
  # non-zero, naming TEST-9001; TEST-9002 is untouched and still reddens.
  cat > "$fx/tests/skills/fixture-suite.sh" <<'EOS'
#!/usr/bin/env bash
set -uo pipefail
FSCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FROOT="$(cd "$FSCRIPT_DIR/../.." && pwd)"
log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
test_9001_greet_and_marker() {
  log_pass "TEST-9001 no longer asserts anything about the greeting"
}
test_9002_farewell() {
  local out; out="$(node "$FROOT/lib/farewell.mjs" 2>&1)"
  [[ "$out" == "world" ]] || log_fail "TEST-9002 farewell mismatch: got '$out'"
  log_pass "TEST-9002 farewell ok"
}
main() {
  if [[ -n "${1:-}" ]]; then
    declare -F "$1" >/dev/null || { echo "Unknown test: $1" >&2; exit 2; }
    "$1"; return
  fi
  test_9001_greet_and_marker
  test_9002_farewell
}
main "$@"
EOS
  ( cd "$fx" && git add -A && git commit -q -m 'weaken TEST-9001 assertion' )

  out="$(cd "$fx" && node "$MUTATION_RUN" --replay --spec docs/specs/fixture-spec.md 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -ne 0 ]] || log_fail "TEST-481 arm2: --replay must exit non-zero once one record no longer reddens: $out"
  assert_payload_contains "$out" "TEST-9001" "TEST-481 arm2: replay output must name TEST-9001"
  assert_payload_contains "$out" "RED TEST-9002" "TEST-481 arm2: TEST-9002 must still be reported as reddening"

  # Arm 3: delete TEST-9002's recorded target file entirely -> INCONCLUSIVE
  # for it, exit non-zero, naming it and that its target is gone.
  rm -f "$fx/lib/farewell.mjs"
  ( cd "$fx" && git add -A && git commit -q -m 'delete farewell target' )
  out="$(cd "$fx" && node "$MUTATION_RUN" --replay --spec docs/specs/fixture-spec.md 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -ne 0 ]] || log_fail "TEST-481 arm3: --replay must exit non-zero when a record's target no longer exists: $out"
  assert_payload_line_matches "$out" 'INCONCLUSIVE TEST-9002:.*target no longer exists' \
    "TEST-481 arm3: replay must report TEST-9002 INCONCLUSIVE naming the missing target"

  log_pass "TEST-481 replay exits 0 when every live record still reddens, names a record that no longer reddens once the code changes, and reports INCONCLUSIVE for a record whose target vanished"
}

main() {
  echo "=== AAI Skill Test: $TEST_NAME ==="
  check_deps
  test_471_runner_isolation
  test_472_runner_refusals
  test_474_three_verdicts_and_rotation
  test_481_replay
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ "$#" -eq 0 ]]; then
    main
  else
    check_deps
    declare -F "$1" >/dev/null || { echo "Unknown test: $1" >&2; exit 2; }
    "$1"
    echo "=== $TEST_NAME: SELECTED PASSED ($1) ==="
  fi
fi
