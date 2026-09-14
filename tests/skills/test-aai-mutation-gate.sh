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
MUTATION_GATE="${AAI_MUTATION_GATE:-$PROJECT_ROOT/.aai/scripts/mutation-gate.mjs}"
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
  [[ -f "$MUTATION_GATE" ]] || log_fail "mutation-gate.mjs not found at $MUTATION_GATE"
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

# === mutation-gate.mjs fixture helpers (D8, D9; TEST-475, TEST-476, TEST-486) ==
# mutation-gate.mjs resolves BOTH the --spec file and the evidence directory
# against `process.cwd()` (never a repo it is pointed at some other way), so
# every gate fixture below runs with cwd=$PROJECT_ROOT (the real repo, so
# `git merge-base --is-ancestor` has real history to judge) and writes its
# throwaway evidence under $PROJECT_ROOT/docs/ai/tdd/<fixture-id>/ — gitignored
# runtime space (measurement 4), registered in MG_FIXTURE_DIRS for cleanup.

# mg_gate_id <label> -> a unique fixture spec id (never collides with a real
# spec, never reused across two arms of the same test).
MG_GATE_ID_SEQ=0
mg_gate_id() {
  MG_GATE_ID_SEQ=$((MG_GATE_ID_SEQ + 1))
  printf 'mg-test-fixture-%s-%s-%s\n' "$1" "$$" "$MG_GATE_ID_SEQ"
}

# mg_gate_evidence_dir <spec_id> -> the real repo's throwaway evidence dir for
# that fixture id; registers it for cleanup.
mg_gate_evidence_dir() {
  local d="$PROJECT_ROOT/docs/ai/tdd/$1"
  MG_FIXTURE_DIRS="$MG_FIXTURE_DIRS $d"
  printf '%s\n' "$d"
}

# mg_write_gate_spec <path> <spec_id> <strategy> <mutation_gate_line> — writes
# frontmatter + a `## Test Plan` header; the caller appends data rows via
# stdin. `mutation_gate_line` is either "mutation_gate: v1" or "" (an
# in-flight, not-yet-frozen spec: D9 reads applicability off strategy alone).
mg_write_gate_spec() {
  local path="$1" spec_id="$2" strategy="$3" marker="$4"
  {
    printf -- '---\nid: %s\ntype: spec\nstatus: implementing\n' "$spec_id"
    [[ -n "$marker" ]] && printf '%s\n' "$marker"
    printf -- '---\n\n# Fixture — mutation gate (%s)\n\n## Implementation strategy\n- Strategy: %s\n\n## Test Plan\n\n| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |\n|---------|---------|------|-----------------------|--------------|----------|--------|\n' "$spec_id" "$strategy"
    cat
  } > "$path"
}

# mg_write_gate_record <evidence_dir> <file_test_id> <record_test_id> <suite>
# <verdict> <base_commit> — writes a hand-built v1 record at
# mutation-<file_test_id>.txt whose OWN test_id field is <record_test_id>
# (deliberately different for the "record names another row" fixture).
mg_write_gate_record() {
  local dir="$1" file_test_id="$2" record_test_id="$3" suite="$4" verdict="$5" base_commit="$6"
  mkdir -p "$dir"
  cat > "$dir/mutation-${file_test_id}.txt" <<EOF
mutation_record: v1
spec_id: fixture
test_id: ${record_test_id}
suite: ${suite}
selector: test_fixture
target: lib/fixture.mjs
mutation: sed:s/OLD/NEW/
base_commit: ${base_commit}
tree_hash: $(printf '0%.0s' $(seq 1 64))
run_at_utc: 2026-01-01T00:00:00Z
rc: 1
verdict: ${verdict}
first_fail: FAIL fixture TEST-9001
---
fixture tail
EOF
}

# mg_gate <spec_path> [extra args...] — runs the real CLI from $PROJECT_ROOT
# (so git ancestry is real) against an absolute --spec path.
mg_gate() {
  local spec_path="$1"; shift
  ( cd "$PROJECT_ROOT" && node "$MUTATION_GATE" --spec "$spec_path" "$@" )
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

# --- TEST-480 — Spec-AC-10: canon carries the rule --------------------------
# .aai/SKILL_TDD.prompt.md GREEN, .aai/VALIDATION.prompt.md step 5g and
# .aai/ROLE_COMMON.md each name the mutation obligation AND a runnable
# mutation-run.mjs command line -- asserted by actually feeding the EXTRACTED
# command line's flags to the REAL delivered CLI (never a re-implementation
# of its arg grammar), so a prompt that names a flag the tool does not accept
# fails this test rather than merely "looking right" to a human reader.
test_480_canon_prose_carries_rule() {
  log_info "Test: canon prose (SKILL_TDD GREEN, VALIDATION 5g, ROLE_COMMON) names the mutation obligation with a command line that parses against the real mutation-run.mjs CLI (TEST-480)..."
  local skill_tdd="$PROJECT_ROOT/.aai/SKILL_TDD.prompt.md"
  local validation="$PROJECT_ROOT/.aai/VALIDATION.prompt.md"
  local role_common="$PROJECT_ROOT/.aai/ROLE_COMMON.md"
  local f
  for f in "$skill_tdd" "$validation" "$role_common"; do
    [[ -f "$f" ]] || log_fail "TEST-480: $f not found"
    grep -qi 'mutation' "$f" || log_fail "TEST-480: $f never mentions mutation at all"
    grep -qF 'mutation-run.mjs' "$f" || log_fail "TEST-480: $f never names mutation-run.mjs"
  done

  local fx; fx="$(mg_new_fixture)"
  cat > "$fx/t480_check.mjs" <<'NODE'
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';

const [, , mutationRun, ...files] = process.argv;

// The CLI's OWN recognized flag set (mirrors mutation-run.mjs parseArgs --
// this list is never itself trusted as proof; every span below is also
// actually RUN against the real CLI below, which is the load-bearing check).
const RECOGNIZED = new Set([
  '--spec', '--test-id', '--suite', '--selector', '--target',
  '--sed', '--patch', '--replay', '--help', '-h',
]);

const SUBS = {
  '<spec-path>': 'docs/specs/mg-t480-does-not-exist.md',
  '<path>': 'docs/specs/mg-t480-does-not-exist.md',
  'TEST-xxx': 'TEST-9001',
  '<suite>': 'tests/skills/mg-t480-does-not-exist.sh',
  '<test_fn>': 'test_dummy',
  "'<expr>'": "s/a/b/",
};

const failures = [];
for (const file of files) {
  const content = fs.readFileSync(file, 'utf8');
  // Only a backtick span that is itself a RUNNABLE invocation (starts with
  // "node") counts as "the runnable command line" — a bare `mutation-run.mjs`
  // filename mention elsewhere in the same file is real prose but not a
  // command, so it must never be silently swept into the same span by a
  // later, unrelated pair of backticks.
  const spans = [...content.matchAll(/`(node[^`]*mutation-run\.mjs[^`]*)`/gs)].map((m) => m[1]);
  if (spans.length === 0) {
    failures.push(`${file}: no backtick-quoted "node .../mutation-run.mjs ..." command line found`);
    continue;
  }
  for (const raw of spans) {
    const normalized = raw.replace(/\s+/g, ' ').trim();
    const tokens = normalized.split(' ');
    const idx = tokens.findIndex((t) => t.endsWith('mutation-run.mjs'));
    if (idx === -1) {
      failures.push(`${file}: span "${normalized}" has no mutation-run.mjs token`);
      continue;
    }
    const args = tokens.slice(idx + 1).map((t) => (t in SUBS ? SUBS[t] : t));
    for (const t of args) {
      if (t.startsWith('--') && !RECOGNIZED.has(t)) {
        failures.push(`${file}: span "${normalized}" uses an unrecognized flag ${t}`);
      }
    }
    let out = '';
    try {
      out = execFileSync(process.execPath, [mutationRun, ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    } catch (err) {
      out = `${err.stdout ?? ''}${err.stderr ?? ''}`;
    }
    if (/unrecognized argument/.test(out)) {
      failures.push(`${file}: span "${normalized}" was refused by the REAL CLI's own arg parser: ${out.trim()}`);
    }
  }
}
if (failures.length) {
  console.error(failures.join('\n'));
  process.exit(1);
}
console.log('ok');
NODE

  local out
  out="$(cd "$PROJECT_ROOT" && node "$fx/t480_check.mjs" "$MUTATION_RUN" "$skill_tdd" "$validation" "$role_common" 2>&1)" \
    || log_fail "TEST-480: canon command-line parse check failed against the real CLI: $out"
  assert_payload_contains "$out" 'ok' "TEST-480: parse-check script did not report ok: $out"

  log_pass "TEST-480 SKILL_TDD GREEN, VALIDATION step 5g and ROLE_COMMON each name the mutation obligation with a command line that parses cleanly against the real mutation-run.mjs CLI"
}

# --- TEST-475 — Spec-AC-05: gate refusals, every offending row named -------
test_475_gate_refusals() {
  log_info "Test: mutation-gate.mjs collects EVERY offending Test Plan row, never just the first (TEST-475)..."
  local head_commit; head_commit="$(cd "$PROJECT_ROOT" && git rev-parse HEAD)"
  local orphan_commit; orphan_commit="$(printf 'f%.0s' $(seq 1 40))"
  local suite="tests/skills/fixture-suite.sh"

  # (A) empty Mutation cell — no record needed, but the evidence DIRECTORY
  # must still exist (an absent directory degrades the WHOLE spec per D9,
  # which is a different arm — TEST-476(C) — from a per-row defect).
  local id_a; id_a="$(mg_gate_id empty-cell)"
  local spec_a; spec_a="$(mg_new_fixture)/spec.md"
  mg_write_gate_spec "$spec_a" "$id_a" tdd "mutation_gate: v1" <<EOF
| TEST-9001 | Spec-AC-01 | unit | ${suite} | a |  | pending |
EOF
  mkdir -p "$(mg_gate_evidence_dir "$id_a")"
  local out rc
  out="$(mg_gate "$spec_a" 2>&1)"; rc=$?
  [[ "$rc" -eq 5 ]] || log_fail "TEST-475(A) empty cell: want exit 5, got $rc: $out"
  assert_payload_line_matches "$out" 'OFFENDING TEST-9001:.*empty' "TEST-475(A): empty-cell row not named: $out"

  # (B) valid Mutation cell, evidence directory exists, but no record file.
  local id_b; id_b="$(mg_gate_id absent-record)"
  local spec_b; spec_b="$(mg_new_fixture)/spec.md"
  mg_write_gate_spec "$spec_b" "$id_b" tdd "mutation_gate: v1" <<EOF
| TEST-9001 | Spec-AC-01 | unit | ${suite} | a | sed:s/OLD/NEW/ | pending |
EOF
  mkdir -p "$(mg_gate_evidence_dir "$id_b")"
  out="$(mg_gate "$spec_b" 2>&1)"; rc=$?
  [[ "$rc" -eq 5 ]] || log_fail "TEST-475(B) absent record: want exit 5, got $rc: $out"
  assert_payload_line_matches "$out" 'OFFENDING TEST-9001:.*missing record' "TEST-475(B): absent-record row not named: $out"

  # (C) record exists, verdict STAYED GREEN.
  local id_c; id_c="$(mg_gate_id stayed-green)"
  local spec_c; spec_c="$(mg_new_fixture)/spec.md"
  mg_write_gate_spec "$spec_c" "$id_c" tdd "mutation_gate: v1" <<EOF
| TEST-9001 | Spec-AC-01 | unit | ${suite} | a | sed:s/OLD/NEW/ | pending |
EOF
  mg_write_gate_record "$(mg_gate_evidence_dir "$id_c")" TEST-9001 TEST-9001 "$suite" "STAYED GREEN" "$head_commit"
  out="$(mg_gate "$spec_c" 2>&1)"; rc=$?
  [[ "$rc" -eq 5 ]] || log_fail "TEST-475(C) STAYED GREEN: want exit 5, got $rc: $out"
  assert_payload_line_matches "$out" 'OFFENDING TEST-9001:.*not RED' "TEST-475(C): STAYED GREEN row not named: $out"

  # (D) record exists, verdict RED, but its own test_id names ANOTHER row.
  local id_d; id_d="$(mg_gate_id wrong-testid)"
  local spec_d; spec_d="$(mg_new_fixture)/spec.md"
  mg_write_gate_spec "$spec_d" "$id_d" tdd "mutation_gate: v1" <<EOF
| TEST-9001 | Spec-AC-01 | unit | ${suite} | a | sed:s/OLD/NEW/ | pending |
EOF
  mg_write_gate_record "$(mg_gate_evidence_dir "$id_d")" TEST-9001 TEST-9099 "$suite" RED "$head_commit"
  out="$(mg_gate "$spec_d" 2>&1)"; rc=$?
  [[ "$rc" -eq 5 ]] || log_fail "TEST-475(D) test_id mismatch: want exit 5, got $rc: $out"
  assert_payload_line_matches "$out" 'OFFENDING TEST-9001:.*test_id.*does not match' "TEST-475(D): test_id-mismatch row not named: $out"

  # (E) record exists, verdict RED, test_id/suite correct, base_commit is an
  # orphan (not an ancestor of HEAD).
  local id_e; id_e="$(mg_gate_id orphan-commit)"
  local spec_e; spec_e="$(mg_new_fixture)/spec.md"
  mg_write_gate_spec "$spec_e" "$id_e" tdd "mutation_gate: v1" <<EOF
| TEST-9001 | Spec-AC-01 | unit | ${suite} | a | sed:s/OLD/NEW/ | pending |
EOF
  mg_write_gate_record "$(mg_gate_evidence_dir "$id_e")" TEST-9001 TEST-9001 "$suite" RED "$orphan_commit"
  out="$(mg_gate "$spec_e" 2>&1)"; rc=$?
  [[ "$rc" -eq 5 ]] || log_fail "TEST-475(E) orphan base_commit: want exit 5, got $rc: $out"
  assert_payload_line_matches "$out" 'OFFENDING TEST-9001:.*not an ancestor' "TEST-475(E): orphan-commit row not named: $out"

  # (F) TWO defective rows in ONE spec — BOTH must be named (proves the gate
  # collects every offending row rather than returning after the first).
  local id_f; id_f="$(mg_gate_id two-defects)"
  local spec_f; spec_f="$(mg_new_fixture)/spec.md"
  mg_write_gate_spec "$spec_f" "$id_f" tdd "mutation_gate: v1" <<EOF
| TEST-9001 | Spec-AC-01 | unit | ${suite} | a |  | pending |
| TEST-9002 | Spec-AC-01 | unit | ${suite} | b | sed:s/OLD/NEW/ | pending |
EOF
  mg_write_gate_record "$(mg_gate_evidence_dir "$id_f")" TEST-9002 TEST-9002 "$suite" RED "$orphan_commit"
  out="$(mg_gate "$spec_f" 2>&1)"; rc=$?
  [[ "$rc" -eq 5 ]] || log_fail "TEST-475(F) two defects: want exit 5, got $rc: $out"
  assert_payload_line_matches "$out" 'OFFENDING TEST-9001:' "TEST-475(F): first defective row (TEST-9001) not named: $out"
  assert_payload_line_matches "$out" 'OFFENDING TEST-9002:' "TEST-475(F): second defective row (TEST-9002) not named: $out"

  # (G) all-satisfied — exit 0. base_commit is real HEAD (an ancestor of
  # itself).
  local id_g; id_g="$(mg_gate_id all-satisfied)"
  local spec_g; spec_g="$(mg_new_fixture)/spec.md"
  mg_write_gate_spec "$spec_g" "$id_g" tdd "mutation_gate: v1" <<EOF
| TEST-9001 | Spec-AC-01 | unit | ${suite} | a | sed:s/OLD/NEW/ | pending |
EOF
  mg_write_gate_record "$(mg_gate_evidence_dir "$id_g")" TEST-9001 TEST-9001 "$suite" RED "$head_commit"
  out="$(mg_gate "$spec_g" 2>&1)"; rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-475(G) all-satisfied: want exit 0, got $rc: $out"
  assert_payload_contains "$out" 'degraded=0' "TEST-475(G): all-satisfied summary did not carry degraded=0: $out"

  log_pass "TEST-475 the gate refuses each of five single-defect fixtures naming that row, both rows of a two-defect fixture, and passes an all-satisfied fixture at exit 0"
}

# --- TEST-476 — Spec-AC-06: degrade, always named, never a silent 0 --------
test_476_gate_degrade() {
  log_info "Test: mutation-gate.mjs degrades BY NAME for a pre-change spec and an absent evidence tree, and refuses at exit 3 when it cannot run (TEST-476)..."
  local suite="tests/skills/fixture-suite.sh"

  # (A) no mutation_gate marker at all — a pre-change/unmarked spec.
  local id_a; id_a="$(mg_gate_id no-marker)"
  local spec_a; spec_a="$(mg_new_fixture)/spec.md"
  mg_write_gate_spec "$spec_a" "$id_a" tdd "" <<EOF
| TEST-9001 | Spec-AC-01 | unit | ${suite} | a | sed:s/OLD/NEW/ | pending |
EOF
  local out rc
  out="$(mg_gate "$spec_a" 2>&1)"; rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-476(A) no marker: want exit 0, got $rc: $out"
  assert_payload_contains "$out" 'DEGRADED: pre-change spec' "TEST-476(A): no-marker degrade not named: $out"
  assert_payload_contains "$out" 'degraded=1' "TEST-476(A): degrade count wrong: $out"

  # (B) strategy is direct (not tdd/hybrid), even with the marker present.
  local id_b; id_b="$(mg_gate_id direct-strategy)"
  local spec_b; spec_b="$(mg_new_fixture)/spec.md"
  mg_write_gate_spec "$spec_b" "$id_b" direct "mutation_gate: v1" <<EOF
| TEST-9001 | Spec-AC-01 | unit | ${suite} | a | sed:s/OLD/NEW/ | pending |
EOF
  out="$(mg_gate "$spec_b" 2>&1)"; rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-476(B) direct strategy: want exit 0, got $rc: $out"
  assert_payload_contains "$out" 'DEGRADED: pre-change spec' "TEST-476(B): direct-strategy degrade not named: $out"

  # (C) applicable (marker + tdd) but the evidence DIRECTORY does not exist —
  # the exact silent-pass shape this ride exists to refuse: must still name
  # the class and carry degraded=<n>, never a bare 0 with no explanation.
  local id_c; id_c="$(mg_gate_id no-evidence-dir)"
  local spec_c; spec_c="$(mg_new_fixture)/spec.md"
  mg_write_gate_spec "$spec_c" "$id_c" tdd "mutation_gate: v1" <<EOF
| TEST-9001 | Spec-AC-01 | unit | ${suite} | a | sed:s/OLD/NEW/ | pending |
| TEST-9002 | Spec-AC-01 | unit | ${suite} | b | sed:s/A/B/       | pending |
EOF
  [[ ! -e "$(mg_gate_evidence_dir "$id_c")" ]] || log_fail "TEST-476(C) setup: evidence dir must not pre-exist"
  out="$(mg_gate "$spec_c" 2>&1)"; rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-476(C) no evidence dir: want exit 0, got $rc: $out"
  assert_payload_contains "$out" 'DEGRADED: evidence tree absent' "TEST-476(C): absent-evidence-dir degrade not named: $out"
  assert_payload_contains "$out" 'degraded=2' "TEST-476(C): degrade count wrong (want 2 rows): $out"
  local list_out; list_out="$(mg_gate "$spec_c" --list-degraded 2>&1)"
  assert_payload_line_matches "$list_out" 'DEGRADED TEST-9001:' "TEST-476(C): --list-degraded did not name TEST-9001: $list_out"
  assert_payload_line_matches "$list_out" 'DEGRADED TEST-9002:' "TEST-476(C): --list-degraded did not name TEST-9002: $list_out"
  assert_payload_not_contains "$out" 'DEGRADED TEST-' "TEST-476(C): the DEFAULT run (no --list-degraded) printed per-row detail: $out"

  # (D) the gate itself cannot run: an unreadable --spec path -> exit 3.
  out="$(mg_gate "$(mg_new_fixture)/does-not-exist.md" 2>&1)"; rc=$?
  [[ "$rc" -eq 3 ]] || log_fail "TEST-476(D) unreadable spec: want exit 3, got $rc: $out"

  # (E) a tree with no git: exit 3, never 0 and never 5. mutation-gate.mjs
  # resolves ROOT from process.cwd(), so cwd is pointed at a non-repo dir with
  # its OWN copy of an applicable spec (git -C <non-repo> rev-parse HEAD
  # fails cleanly there without touching the real repo).
  local nogit; nogit="$(mg_new_fixture)"
  mkdir -p "$nogit/docs/specs"
  local spec_e="$nogit/docs/specs/spec.md"
  mg_write_gate_spec "$spec_e" "$(mg_gate_id no-git)" tdd "mutation_gate: v1" <<EOF
| TEST-9001 | Spec-AC-01 | unit | ${suite} | a | sed:s/OLD/NEW/ | pending |
EOF
  out="$(cd "$nogit" && node "$MUTATION_GATE" --spec "$spec_e" 2>&1)"; rc=$?
  [[ "$rc" -eq 3 ]] || log_fail "TEST-476(E) no-git tree: want exit 3, got $rc: $out"

  log_pass "TEST-476 a pre-change (no-marker) spec and a non-tdd/hybrid spec both degrade named 'pre-change spec'; an absent evidence directory degrades named 'evidence tree absent' with the row count, --list-degraded prints per-row detail the default run withholds; an unreadable spec and a git-less tree both refuse at exit 3"
}

# --- TEST-486 — Spec-AC-16: the gate reads THIS ride's own real records ----
test_486_gate_reads_this_ride() {
  log_info "Test: mutation-gate.mjs against a fixture copy of THIS spec, gated with the REAL records this ride has produced so far, exits 0 degraded=0; removing one record exits 5 naming it (TEST-486)..."

  # Arm A — self-contained and clone-safe (runs correctly even INSIDE a
  # mutation-run.mjs isolated clone, where $PROJECT_ROOT/docs/ai/tdd/** is
  # unconditionally excluded from cloning by D4/D7 — so arms B/C below,
  # which read that live directory, always SKIP there). A genuinely
  # tool-produced record — the REAL mutation-run.mjs, run here, not a
  # hand-written stand-in (Seam S1: "not only a synthetic fixture") — is
  # gated alongside a hand-planted record on an ORPHAN base_commit, so the
  # ancestry rule (D8) is exercised by an ACTUAL mutation-run.mjs output
  # sitting next to the defective row, not only by TEST-475(E)'s fully
  # synthetic fixture.
  local fx; fx="$(mg_new_fixture)"
  mg_seed_repo "$fx"
  mg_write_fixture_suite "$fx"
  local gate_id; gate_id="$(mg_gate_id this-ride-real)"
  local gate_spec="$fx/docs/specs/fixture-spec.md"
  mg_write_gate_spec "$gate_spec" "$gate_id" tdd "mutation_gate: v1" <<EOF
| TEST-9001 | Spec-AC-01 | unit | tests/skills/fixture-suite.sh | a | sed:s/hello/goodbye/ | pending |
| TEST-9002 | Spec-AC-01 | unit | tests/skills/fixture-suite.sh | b | sed:s/A/B/           | pending |
EOF
  printf "console.log('base');\n" > "$fx/lib/greeting.mjs"
  ( cd "$fx" && git add -A && git commit -q -m base )
  printf "console.log('hello');\n" > "$fx/lib/greeting.mjs"
  printf 'marker-present' > "$fx/lib/extra.txt"

  local run_out run_rc
  run_out="$(cd "$fx" && node "$MUTATION_RUN" --spec docs/specs/fixture-spec.md --test-id TEST-9001 \
    --suite tests/skills/fixture-suite.sh --selector test_9001_greet_and_marker \
    --target lib/greeting.mjs --sed 's/hello/goodbye/' 2>&1)" && run_rc=0 || run_rc=$?
  [[ "$run_rc" -eq 0 ]] || log_fail "TEST-486 arm A setup: mutation-run.mjs must produce a RED record for TEST-9001, got exit $run_rc: $run_out"

  local head_commit; head_commit="$(cd "$fx" && git rev-parse HEAD)"
  local orphan_commit; orphan_commit="$(printf 'e%.0s' $(seq 1 40))"
  mg_write_gate_record "$fx/docs/ai/tdd/$gate_id" TEST-9002 TEST-9002 "tests/skills/fixture-suite.sh" RED "$orphan_commit"

  local out rc
  out="$(cd "$fx" && node "$MUTATION_GATE" --spec docs/specs/fixture-spec.md 2>&1)"; rc=$?
  [[ "$rc" -eq 5 ]] || log_fail "TEST-486 arm A: gate over a real record + an orphan-commit record must exit 5, got $rc: $out"
  assert_payload_not_contains "$out" 'OFFENDING TEST-9001' "TEST-486 arm A: the GENUINE mutation-run.mjs record (TEST-9001) was wrongly flagged: $out"
  assert_payload_line_matches "$out" 'OFFENDING TEST-9002:.*not an ancestor' "TEST-486 arm A: the orphan-base_commit record (TEST-9002) was not named: $out"
  log_info "TEST-486 arm A: base_commit sanity — $head_commit is HEAD, $orphan_commit is the planted orphan"

  # Arms B/C — the live shipping evidence tree (self-scaling, degrades to
  # SKIP rather than a false pass/fail when absent — always true inside a
  # mutation-run.mjs clone, per the comment above; meaningful in a normal,
  # non-clone run).
  local real_spec="$PROJECT_ROOT/docs/specs/SPEC-DRAFT-spec-mutation-gate-for-tests.md"
  local real_evidence_dir="$PROJECT_ROOT/docs/ai/tdd/spec-mutation-gate-for-tests"
  [[ -f "$real_spec" ]] || log_skip "TEST-486: this ride's own spec is not present in this checkout"
  [[ -d "$real_evidence_dir" ]] || log_skip "TEST-486: no real evidence directory yet — nothing this ride has produced to gate"

  # Enumerate the LIVE (non-rotated) real records this ride has produced SO
  # FAR — self-scaling across runs: whichever Test Plan rows already carry a
  # real RED record are the ones this test proves the gate reads correctly,
  # never a fixed/hand-maintained list.
  local live_ids=() f base
  for f in "$real_evidence_dir"/mutation-TEST-*.txt; do
    [[ -e "$f" ]] || continue
    base="$(basename "$f")"
    [[ "$base" =~ ^mutation-(TEST-[0-9]+)\.txt$ ]] || continue
    live_ids+=("${BASH_REMATCH[1]}")
  done
  [[ "${#live_ids[@]}" -ge 1 ]] || log_skip "TEST-486: no live (non-rotated) real mutation records found under $real_evidence_dir"

  local id; id="$(mg_gate_id this-ride)"
  local spec_path; spec_path="$(mg_new_fixture)/spec.md"
  local evidence_dir; evidence_dir="$(mg_gate_evidence_dir "$id")"
  mkdir -p "$evidence_dir"

  # Build the fixture spec: same applicability shape (marker + tdd) as the
  # real spec, its Test Plan trimmed to exactly the rows with a live record —
  # the File path cell for each row is read from that row's OWN real record's
  # `suite:` field, so it matches by construction (mutation-gate.mjs checks
  # record.suite === row.fileCell).
  {
    printf -- '---\nid: %s\ntype: spec\nstatus: implementing\nmutation_gate: v1\n---\n\n' "$id"
    printf '# Fixture — this ride'"'"'s own records (TEST-486)\n\n## Implementation strategy\n- Strategy: tdd\n\n## Test Plan\n\n'
    printf '| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |\n|---------|---------|------|-----------------------|--------------|----------|--------|\n'
    local tid suite_lines suite_field
    for tid in "${live_ids[@]}"; do
      cp "$real_evidence_dir/mutation-${tid}.txt" "$evidence_dir/mutation-${tid}.txt"
      # No pipe into head/grep -q (hygiene-pack test_102 pipe-safe ratchet):
      # capture every matching line from the FILE directly, then take the
      # first via parameter expansion.
      suite_lines="$(grep '^suite: ' "$evidence_dir/mutation-${tid}.txt")"
      suite_field="${suite_lines%%$'\n'*}"
      suite_field="${suite_field#suite: }"
      printf '| %s | Spec-AC-01 | integration | %s | real record | see mutation-gate evidence | pending |\n' "$tid" "$suite_field"
    done
  } > "$spec_path"

  local out rc
  out="$(mg_gate "$spec_path" 2>&1)"; rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-486 arm1: gate over this ride's own real records must exit 0, got $rc: $out"
  assert_payload_contains "$out" 'degraded=0' "TEST-486 arm1: summary did not carry degraded=0: $out"

  # Remove ONE record from the fixture copy (never from the real evidence
  # tree) -> exit 5, naming exactly that row.
  local removed="${live_ids[0]}"
  rm -f "$evidence_dir/mutation-${removed}.txt"
  out="$(mg_gate "$spec_path" 2>&1)"; rc=$?
  [[ "$rc" -eq 5 ]] || log_fail "TEST-486 arm2: gate after removing $removed's record must exit 5, got $rc: $out"
  assert_payload_line_matches "$out" "OFFENDING ${removed}:" "TEST-486 arm2: removed record's row ($removed) not named: $out"

  log_pass "TEST-486 a genuine mutation-run.mjs record passes while a hand-planted orphan-commit record is refused naming it (arm A); the live shipping evidence tree, when present, gates identically end to end (arms B/C)"
}

main() {
  echo "=== AAI Skill Test: $TEST_NAME ==="
  check_deps
  test_471_runner_isolation
  test_472_runner_refusals
  test_474_three_verdicts_and_rotation
  test_481_replay
  test_480_canon_prose_carries_rule
  test_475_gate_refusals
  test_476_gate_degrade
  test_486_gate_reads_this_ride
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
