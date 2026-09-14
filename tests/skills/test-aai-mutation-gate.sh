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

# mg_tree_hash <dir> — the SAME tree hash mutation-run.mjs's own D7 tripwire
# computes (.aai/scripts/lib/tree-hash.mjs), computed from OUTSIDE the tool
# so this assertion can never inherit a bug in the tool's own self-check.
mg_tree_hash() {
  node --input-type=module -e "
import { computeTreeHash } from '$PROJECT_ROOT/.aai/scripts/lib/tree-hash.mjs';
process.stdout.write(computeTreeHash(process.argv[1]));
" "$1"
}

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

  local status_before status_after hash_before hash_after
  status_before="$(cd "$fx" && git status --porcelain)"
  hash_before="$(mg_tree_hash "$fx")"

  local out rc
  out="$(cd "$fx" && node "$MUTATION_RUN" --spec docs/specs/fixture-spec.md --test-id TEST-9001 \
    --suite tests/skills/fixture-suite.sh --selector test_9001_greet_and_marker \
    --target lib/greeting.mjs --sed 's/hello/goodbye/' 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-471: mutation-run.mjs exited $rc on a normal RED run (dirty tree + untracked file): $out"

  status_after="$(cd "$fx" && git status --porcelain)"
  hash_after="$(mg_tree_hash "$fx")"
  [[ "$status_before" == "$status_after" ]] \
    || log_fail "TEST-471: the fixture's git status changed across the run (before=[$status_before] after=[$status_after]) — the runner must write to docs/ai/tdd/ only"
  # D7: git status ALONE is blind to a content change in an already-dirty
  # TRACKED file (" M path" prints identically either way) — a tree hash
  # excluding docs/ai/tdd/ over path+content is the other half of the
  # tripwire, and it is what actually catches a runner that writes into the
  # shipping tree.
  [[ "$hash_before" == "$hash_after" ]] \
    || log_fail "TEST-471: the fixture's tree hash (excluding docs/ai/tdd) changed across the run (before=$hash_before after=$hash_after) — the runner must write to docs/ai/tdd/ only"

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

  # A PRIVATE $TMPDIR for this test's own node invocations (NB4): counting
  # aai-mutation-* dirs under the SHARED system tmp would be racy against any
  # OTHER concurrent mutation-run.mjs (this ride's own workflow encourages
  # exactly that concurrency) — a private os.tmpdir() makes the leftover-
  # clone count observe only what THIS test's own runs produced.
  local priv_tmp; priv_tmp="$(mktemp -d "${TMPDIR:-/tmp}/aai-mg-472-priv.XXXXXX")"
  MG_FIXTURE_DIRS="$MG_FIXTURE_DIRS $priv_tmp"

  local tmp_before tmp_after
  tmp_before="$(find "$priv_tmp" -maxdepth 1 -name 'aai-mutation-*' 2>/dev/null | wc -l | tr -d ' ')"

  local out rc
  out="$(cd "$fx" && TMPDIR="$priv_tmp" node "$MUTATION_RUN" --spec docs/specs/fixture-spec.md --test-id TEST-9001 \
    --suite tests/skills/fixture-suite.sh --selector test_9001_does_not_exist \
    --target lib/greeting.mjs --sed 's/hello/goodbye/' 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "TEST-472: unknown selector must exit 2, got $rc: $out"
  assert_payload_contains "$out" "fixture-suite.sh" \
    "TEST-472: unknown-selector refusal must name the suite"
  [[ -e "$(mg_record_path "$fx" fixture-spec-472 TEST-9001)" ]] \
    && log_fail "TEST-472: unknown-selector refusal must write no record"

  out="$(cd "$fx" && TMPDIR="$priv_tmp" node "$MUTATION_RUN" --spec docs/specs/fixture-spec.md --test-id TEST-9001 \
    --suite tests/skills/fixture-suite.sh --selector test_9001_greet_and_marker \
    --target lib/greeting.mjs --sed 's/no_such_pattern_xyz/replacement/' 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "TEST-472: a no-op mutation must exit 2, got $rc: $out"
  assert_payload_contains "$out" "no_such_pattern_xyz" \
    "TEST-472: no-op-mutation refusal must name the expression"
  assert_payload_contains "$out" "lib/greeting.mjs" \
    "TEST-472: no-op-mutation refusal must name the target path"
  [[ -e "$(mg_record_path "$fx" fixture-spec-472 TEST-9001)" ]] \
    && log_fail "TEST-472: no-op-mutation refusal must write no record"

  tmp_after="$(find "$priv_tmp" -maxdepth 1 -name 'aai-mutation-*' 2>/dev/null | wc -l | tr -d ' ')"
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

  # Arm 4 (B3 / D14): a record whose --patch mutation cannot be APPLIED at
  # replay time (a stale/off-repo path — the exact shape of the pre-fix
  # mutation-TEST-487.txt/mutation-TEST-488.txt defect) must never crash
  # --replay with an uncaught stack trace, and must exit with a code
  # DISTINCT from "a record replayed cleanly but no longer reddens" (arm 2's
  # exit 1) — conflating the two is exactly the bug this arm closes.
  local fx4; fx4="$(mg_new_fixture)"
  mg_seed_repo "$fx4"
  mg_write_fixture_suite "$fx4"
  mg_write_spec "$fx4" "fixture-spec-481-arm4"
  printf "console.log('hello');\n" > "$fx4/lib/greeting.mjs"
  ( cd "$fx4" && git add -A && git commit -q -m base )
  local head4; head4="$(cd "$fx4" && git rev-parse HEAD)"
  mkdir -p "$fx4/docs/ai/tdd/fixture-spec-481-arm4"
  cat > "$fx4/docs/ai/tdd/fixture-spec-481-arm4/mutation-TEST-9003.txt" <<EOF
mutation_record: v1
spec_id: fixture-spec-481-arm4
test_id: TEST-9003
suite: tests/skills/fixture-suite.sh
selector: test_9001_greet_and_marker
target: lib/greeting.mjs
mutation: patch:does-not-exist-on-this-machine.patch
base_commit: ${head4}
tree_hash: $(printf '0%.0s' $(seq 1 64))
run_at_utc: 2026-01-01T00:00:00Z
rc: 1
verdict: RED
first_fail: FAIL fixture TEST-9003
---
fixture tail
EOF

  out="$(cd "$fx4" && node "$MUTATION_RUN" --replay --spec docs/specs/fixture-spec.md 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 4 ]] || log_fail "TEST-481 arm4: --replay of an unreplayable (missing patch) record must exit 4 (distinct from a genuine regression's exit 1), got $rc: $out"
  assert_payload_line_matches "$out" 'INCONCLUSIVE TEST-9003:.*could not apply the recorded mutation' \
    "TEST-481 arm4: replay must report TEST-9003 INCONCLUSIVE naming the apply failure: $out"
  assert_payload_not_contains "$out" "at applyMutation" \
    "TEST-481 arm4: replay must never leak a raw stack trace for an unreplayable record: $out"

  # Arm 5 (NB2-r2): a CONCURRENT EDITOR of the source tree — a separate
  # writer touching a tracked file while --replay is running its own slow
  # suite — must be reported as inconclusive (exit 4), never as a genuine
  # regression (exit 1); the message must name the changed path rather than
  # asserting a cause the D7 tripwire cannot actually tell apart.
  local fx5; fx5="$(mg_new_fixture)"
  mg_seed_repo "$fx5"
  mg_write_spec "$fx5" "fixture-spec-481-arm5"
  printf "console.log('hello');\n" > "$fx5/lib/greeting.mjs"
  printf 'marker\n' > "$fx5/CONCURRENT_MARKER.txt"
  ( cd "$fx5" && git add -A && git commit -q -m base )

  # A selector slow enough to give a background writer a real window against
  # the SOURCE tree while the suite runs inside the clone.
  cat > "$fx5/tests/skills/fixture-suite.sh" <<'EOS'
#!/usr/bin/env bash
set -uo pipefail
FSCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FROOT="$(cd "$FSCRIPT_DIR/../.." && pwd)"
log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
test_9001_slow_greet() {
  sleep 3
  local out; out="$(node "$FROOT/lib/greeting.mjs" 2>&1)"
  [[ "$out" == "hello" ]] || log_fail "TEST-9001 greeting mismatch: got '$out'"
  log_pass "TEST-9001 greeting ok"
}
main() {
  if [[ -n "${1:-}" ]]; then
    declare -F "$1" >/dev/null || { echo "Unknown test: $1" >&2; exit 2; }
    "$1"; return
  fi
  test_9001_slow_greet
}
main "$@"
EOS
  ( cd "$fx5" && git add -A && git commit -q -m 'slow selector' )

  out="$(cd "$fx5" && node "$MUTATION_RUN" --spec docs/specs/fixture-spec.md --test-id TEST-9001 \
    --suite tests/skills/fixture-suite.sh --selector test_9001_slow_greet \
    --target lib/greeting.mjs --sed 's/hello/goodbye/' 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-481 arm5 setup: expected a RED record, got exit $rc: $out"

  ( sleep 1; printf 'edited-by-concurrent-writer\n' >> "$fx5/CONCURRENT_MARKER.txt" ) &
  local bgpid=$!
  out="$(cd "$fx5" && node "$MUTATION_RUN" --replay --spec docs/specs/fixture-spec.md 2>&1)" && rc=0 || rc=$?
  wait "$bgpid" 2>/dev/null || true
  [[ "$rc" -eq 4 ]] || log_fail "TEST-481 arm5: --replay must exit 4 (inconclusive) when the source tree changes concurrently during the run, never exit 1 (a genuine regression), got $rc: $out"
  assert_payload_line_matches "$out" 'INCONCLUSIVE TEST-9001:.*CONCURRENT_MARKER\.txt' \
    "TEST-481 arm5: replay must name the changed path CONCURRENT_MARKER.txt: $out"
  assert_payload_contains "$out" "this run, or another writer" \
    "TEST-481 arm5: replay's D7 message must own that it cannot tell a concurrent writer from its own run: $out"

  log_pass "TEST-481 replay exits 0 when every live record still reddens, names a record that no longer reddens once the code changes (exit 1), reports INCONCLUSIVE for a record whose target vanished, reports INCONCLUSIVE at a DISTINCT exit code (4) for a record whose mutation cannot be applied at all, and reports a concurrent editor's write during the run as inconclusive (exit 4, path named) rather than a genuine regression"
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

  # Arms B/C — the live shipping evidence tree (self-scaling; when absent —
  # always true inside a mutation-run.mjs clone, in CI and in the sweep's
  # isolated clones — they degrade BY NAME below and arm A carries the proof;
  # meaningful in a normal, non-clone run).
  local real_spec="$PROJECT_ROOT/docs/specs/SPEC-DRAFT-spec-mutation-gate-for-tests.md"
  local real_evidence_dir="$PROJECT_ROOT/docs/ai/tdd/spec-mutation-gate-for-tests"
  # Arms B/C read the LIVE evidence tree (gitignored). In CI and in every
  # isolated clone it is absent BY DESIGN; arm A above already proved the
  # ancestry property on tool-produced records, so the absence is a named
  # degrade, never a log_skip — `log_skip` is exit 42 and VOIDS THE WHOLE
  # SUITE (the same lesson test-aai-follow-ups.sh TEST-443 recorded).
  if [[ ! -f "$real_spec" ]]; then
    log_info "TEST-486 arms B/C DEGRADED (named): this ride's own spec is not present in this checkout"
    log_pass "TEST-486: ancestry check proved on tool-produced records (arm A); live-tree arms degraded by name"
    return 0
  fi
  if [[ ! -d "$real_evidence_dir" ]]; then
    log_info "TEST-486 arms B/C DEGRADED (named): evidence tree absent in this checkout (gitignored; expected in CI and isolated clones)"
    log_pass "TEST-486: ancestry check proved on tool-produced records (arm A); live-tree arms degraded by name"
    return 0
  fi

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
  if [[ "${#live_ids[@]}" -lt 1 ]]; then
    log_info "TEST-486 arms B/C DEGRADED (named): no live (non-rotated) mutation records under $real_evidence_dir"
    log_pass "TEST-486: ancestry check proved on tool-produced records (arm A); live-tree arms degraded by name"
    return 0
  fi

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

# --- NB1 — a dangling untracked symlink must never crash the clone builder
# or leak a clone -----------------------------------------------------------
test_nb1_dangling_symlink_no_leak() {
  log_info "Test: a dangling untracked symlink in the working tree is reproduced AS a symlink (never followed), and the run completes with no leaked \$TMPDIR clone (NB1)..."
  local fx; fx="$(mg_new_fixture)"
  mg_seed_repo "$fx"
  mg_write_fixture_suite "$fx"
  mg_write_spec "$fx" "fixture-spec-nb1"
  printf "console.log('hello');\n" > "$fx/lib/greeting.mjs"
  ( cd "$fx" && git add -A && git commit -q -m base )
  printf 'marker-present' > "$fx/lib/extra.txt"
  # A DANGLING untracked symlink: readable by lstat, unreadable by anything
  # that follows it (fs.copyFileSync would throw ENOENT).
  ( cd "$fx" && ln -s /nonexistent/nowhere dangling-link.md )

  local priv_tmp; priv_tmp="$(mktemp -d "${TMPDIR:-/tmp}/aai-mg-nb1-priv.XXXXXX")"
  MG_FIXTURE_DIRS="$MG_FIXTURE_DIRS $priv_tmp"

  local out rc
  out="$(cd "$fx" && TMPDIR="$priv_tmp" node "$MUTATION_RUN" --spec docs/specs/fixture-spec.md --test-id TEST-9001 \
    --suite tests/skills/fixture-suite.sh --selector test_9001_greet_and_marker \
    --target lib/greeting.mjs --sed 's/hello/goodbye/' 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "NB1: a dangling untracked symlink must not crash a normal RED run, got $rc: $out"
  assert_payload_not_contains "$out" "ENOENT" \
    "NB1: the run must never surface a raw ENOENT from copying the dangling symlink: $out"

  [[ -L "$fx/dangling-link.md" ]] \
    || log_fail "NB1: the dangling symlink must still be present, untouched, in the source tree"

  local leftover; leftover="$(find "$priv_tmp" -maxdepth 1 -name 'aai-mutation-*' 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$leftover" -eq 0 ]] \
    || log_fail "NB1: a run with a dangling symlink in the tree must leave no clone directory behind, found $leftover under $priv_tmp"

  log_pass "NB1 a dangling untracked symlink is reproduced as a symlink (never followed/read), the run completes normally, and no clone is leaked"
}

# --- TEST-491 — Spec-AC-03 (NB3-r2/NB4-r2): heredoc-aware selector extraction
test_491_heredoc_selector_extraction() {
  log_info "Test: heredoc-only names never leak into unknown-selector suggestions (NB3-r2), and an UNTERMINATED heredoc never swallows a real trailing selector (NB4-r2) (TEST-491)..."
  local fx; fx="$(mg_new_fixture)"
  mg_seed_repo "$fx"
  mg_write_spec "$fx" "fixture-spec-491"
  printf "console.log('hello');\n" > "$fx/lib/greeting.mjs"

  # Arm A (NB3-r2): a heredoc BODY that happens to contain another suite's
  # function-definition TEXT must never leak into THIS suite's own selector
  # grammar — a suite does not define a test merely by printing one.
  cat > "$fx/tests/skills/fixture-suite.sh" <<'FIXTURE_EOS_A'
#!/usr/bin/env bash
set -uo pipefail
log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
write_other_suite() {
  cat <<'INNER'
test_9002_farewell() {
  :
}
INNER
}
main() { "$1"; }
main "$@"
FIXTURE_EOS_A
  ( cd "$fx" && git add -A && git commit -q -m 'heredoc-body fixture' )

  local out rc
  out="$(cd "$fx" && node "$MUTATION_RUN" --spec docs/specs/fixture-spec.md --test-id TEST-9001 \
    --suite tests/skills/fixture-suite.sh --selector test_nonexistent_selector_xyz \
    --target lib/greeting.mjs --sed 's/hello/goodbye/' 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "TEST-491 arm A: unknown selector must exit 2, got $rc: $out"
  assert_payload_not_contains "$out" "test_9002_farewell" \
    "TEST-491 arm A: a heredoc-only name must never appear in the unknown-selector suggestions: $out"

  # Arm B (NB4-r2): an UNTERMINATED heredoc must not swallow the rest of the
  # file — a REAL selector defined after it must still be found.
  cat > "$fx/tests/skills/fixture-suite.sh" <<'FIXTURE_EOS_B'
#!/usr/bin/env bash
set -uo pipefail
log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
test_aaa() {
  cat <<'EOS2'
this heredoc is never terminated in this fixture file on purpose
test_bbb() { :; }
test_ccc() { :; }
FIXTURE_EOS_B
  ( cd "$fx" && git add -A && git commit -q -m 'unterminated heredoc fixture' )

  out="$(cd "$fx" && node "$MUTATION_RUN" --spec docs/specs/fixture-spec.md --test-id TEST-9001 \
    --suite tests/skills/fixture-suite.sh --selector test_nonexistent_selector_xyz \
    --target lib/greeting.mjs --sed 's/hello/goodbye/' 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "TEST-491 arm B: unknown selector must exit 2, got $rc: $out"
  assert_payload_contains "$out" "test_aaa" \
    "TEST-491 arm B: the heredoc's OWN opener function must still be found (it is a real, if oddly-shaped, selector): $out"
  assert_payload_contains "$out" "test_bbb" \
    "TEST-491 arm B: a real selector defined AFTER an unterminated heredoc must still be found, never silently swallowed: $out"
  assert_payload_contains "$out" "test_ccc" \
    "TEST-491 arm B: a real selector defined AFTER an unterminated heredoc must still be found, never silently swallowed: $out"

  log_pass "TEST-491 heredoc-only names never leak into selector suggestions, and an unterminated heredoc never swallows a real trailing selector"
}

# --- TEST-492 — Spec-AC-11/D14 (NB7-r2): rotated record's patch pointer ----
test_492_rotated_patch_pointer() {
  log_info "Test: a rotated record's mutation: field follows its own rotated patch copy, not the live name whose bytes belong to the next run (NB7-r2) (TEST-492)..."
  local fx; fx="$(mg_new_fixture)"
  mg_seed_repo "$fx"
  mg_write_fixture_suite "$fx"
  mg_write_spec "$fx" "fixture-spec-492"
  printf "console.log('hello');\n" > "$fx/lib/greeting.mjs"
  ( cd "$fx" && git add -A && git commit -q -m base )
  printf 'marker-present' > "$fx/lib/extra.txt"

  local patch1; patch1="$(mg_new_fixture)/first.patch"
  cat > "$patch1" <<'EOF'
--- a/lib/greeting.mjs
+++ b/lib/greeting.mjs
@@ -1 +1 @@
-console.log('hello');
+console.log('goodbye');
EOF
  local out rc
  out="$(cd "$fx" && node "$MUTATION_RUN" --spec docs/specs/fixture-spec.md --test-id TEST-9001 \
    --suite tests/skills/fixture-suite.sh --selector test_9001_greet_and_marker \
    --target lib/greeting.mjs --patch "$patch1" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-492 setup 1: expected a RED record, got exit $rc: $out"

  local rec; rec="$(mg_record_path "$fx" fixture-spec-492 TEST-9001)"
  local run_at1; run_at1="$(grep '^run_at_utc: ' "$rec" | sed 's/^run_at_utc: //')"
  local first_patch_bytes; first_patch_bytes="$(cat "$(dirname "$rec")/mutation-TEST-9001.patch")"

  local patch2; patch2="$(mg_new_fixture)/second.patch"
  cat > "$patch2" <<'EOF'
--- a/lib/greeting.mjs
+++ b/lib/greeting.mjs
@@ -1 +1 @@
-console.log('hello');
+console.log('farewell');
EOF
  out="$(cd "$fx" && node "$MUTATION_RUN" --spec docs/specs/fixture-spec.md --test-id TEST-9001 \
    --suite tests/skills/fixture-suite.sh --selector test_9001_greet_and_marker \
    --target lib/greeting.mjs --patch "$patch2" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-492 setup 2: expected a second RED record (rotating the first), got exit $rc: $out"

  local rotated_txt; rotated_txt="$(dirname "$rec")/mutation-TEST-9001.${run_at1}.txt"
  [[ -f "$rotated_txt" ]] || log_fail "TEST-492: rotated record not found at $rotated_txt"
  local rotated_patch_rel; rotated_patch_rel="$(grep '^mutation: patch:' "$rotated_txt" | sed 's/^mutation: patch://')"
  [[ -n "$rotated_patch_rel" ]] || log_fail "TEST-492: rotated record's mutation field is not a patch: pointer: $(cat "$rotated_txt")"
  local rotated_patch_abs="$fx/$rotated_patch_rel"
  [[ -f "$rotated_patch_abs" ]] || log_fail "TEST-492: rotated record's mutation field names a file that does not exist: $rotated_patch_rel"
  local rotated_patch_bytes; rotated_patch_bytes="$(cat "$rotated_patch_abs")"
  [[ "$rotated_patch_bytes" == "$first_patch_bytes" ]] \
    || log_fail "TEST-492: the rotated record's mutation: field does not resolve to the FIRST patch's content"
  [[ "$rotated_patch_rel" != "docs/ai/tdd/fixture-spec-492/mutation-TEST-9001.patch" ]] \
    || log_fail "TEST-492: rotated record still points at the LIVE patch name, whose bytes now belong to the NEXT run"

  # NB-3 (remediation round 4, fault-injection-free): the pair's FINAL
  # on-disk state, checked by the NAMING CONVENTION alone (never trusting the
  # rotated record's own mutation: pointer, which is what the assertions
  # above already do) — the rotated .patch sibling
  # (mutation-TEST-9001.<stamp>.patch) exists whenever the rotated .txt does.
  # rotateExisting now moves the patch to its rotated location BEFORE the
  # record is rotated and the live record removed (was: record rotated, live
  # record removed, patch renamed LAST — a process death between the last
  # two steps could leave a rotated record with no rotated patch yet). This
  # is a documented invariant checked via final state, not process-kill
  # timing injection (too flake-prone to simulate reliably, per this ride's
  # own NB7-r3 disposition for a sibling ordering claim).
  local rotated_patch_by_name; rotated_patch_by_name="$(dirname "$rec")/mutation-TEST-9001.${run_at1}.patch"
  [[ -f "$rotated_patch_by_name" ]] \
    || log_fail "TEST-492 (NB-3): the rotated .patch sibling (by naming convention, $(basename "$rotated_patch_by_name")) must exist whenever the rotated .txt does — a rotated record must never be able to name a patch that was not yet moved"

  log_pass "TEST-492 a rotated record's mutation: field follows its own rotated patch copy, byte-identical to the first patch, never the live name, and the rotated patch sibling exists (by naming convention) whenever the rotated record does"
}

# --- TEST-493 — Spec-AC-03 (NB6-r2): selector_honoured field --------------
test_493_selector_honoured_field() {
  log_info "Test: a record for a suite that ignores \$1 and runs every test carries selector_honoured: no, and one that dispatches carries yes (NB6-r2) (TEST-493)..."
  local fx; fx="$(mg_new_fixture)"
  mg_seed_repo "$fx"
  mg_write_spec "$fx" "fixture-spec-493"
  printf "console.log('hello');\n" > "$fx/lib/greeting.mjs"

  # A suite whose main() runs EVERYTHING regardless of $1 — no positional
  # dispatch idiom at all (the live spec-lint/spec-tools/prompt-diet/heartbeat
  # shape NB6-r2 names).
  cat > "$fx/tests/skills/fixture-suite.sh" <<'EOS'
#!/usr/bin/env bash
set -uo pipefail
FSCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FROOT="$(cd "$FSCRIPT_DIR/../.." && pwd)"
log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
test_9001_greet() {
  local out; out="$(node "$FROOT/lib/greeting.mjs" 2>&1)"
  [[ "$out" == "hello" ]] || log_fail "TEST-9001 greeting mismatch: got '$out'"
  log_pass "TEST-9001 greeting ok"
}
main() {
  test_9001_greet
}
main "$@"
EOS
  ( cd "$fx" && git add -A && git commit -q -m base )

  local out rc
  out="$(cd "$fx" && node "$MUTATION_RUN" --spec docs/specs/fixture-spec.md --test-id TEST-9001 \
    --suite tests/skills/fixture-suite.sh --selector test_9001_greet \
    --target lib/greeting.mjs --sed 's/hello/goodbye/' 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-493: expected a RED record, got exit $rc: $out"
  assert_payload_contains "$out" "NOTE:" "TEST-493: a non-dispatching suite must print a NOTE: $out"

  local rec; rec="$(mg_record_path "$fx" fixture-spec-493 TEST-9001)"
  grep -qF 'selector_honoured: no (suite runs every test)' "$rec" \
    || log_fail "TEST-493: record must carry selector_honoured: no (suite runs every test): $(cat "$rec")"

  # A fixture suite that DOES dispatch on $1 (declare -F "$1") must carry yes.
  local fx2; fx2="$(mg_new_fixture)"
  mg_seed_repo "$fx2"
  mg_write_fixture_suite "$fx2"
  mg_write_spec "$fx2" "fixture-spec-493-honoured"
  printf "console.log('hello');\n" > "$fx2/lib/greeting.mjs"
  printf 'marker-present' > "$fx2/lib/extra.txt"
  ( cd "$fx2" && git add -A && git commit -q -m base )
  out="$(cd "$fx2" && node "$MUTATION_RUN" --spec docs/specs/fixture-spec.md --test-id TEST-9001 \
    --suite tests/skills/fixture-suite.sh --selector test_9001_greet_and_marker \
    --target lib/greeting.mjs --sed 's/hello/goodbye/' 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-493 (honoured arm): expected a RED record, got exit $rc: $out"
  local rec2; rec2="$(mg_record_path "$fx2" fixture-spec-493-honoured TEST-9001)"
  grep -qF 'selector_honoured: yes' "$rec2" \
    || log_fail "TEST-493: a dispatching suite's record must carry selector_honoured: yes: $(cat "$rec2")"

  log_pass "TEST-493 mutation-run.mjs records whether the row's own suite actually honours the positional selector, both directions, and NOTEs the non-dispatching case"
}

# --- TEST-496 — Spec-AC-11/D14 (NB-3, remediation round 3): a
# buildIsolatedClone() failure during --replay is INCONCLUSIVE, never a
# genuine regression -----------------------------------------------------
test_496_replay_clone_build_failure_inconclusive() {
  log_info "Test: --replay classifies a buildIsolatedClone() failure as INCONCLUSIVE (exit 4), never failures (exit 1) (TEST-496, closes NB-3)..."
  if [[ "$(id -u)" == "0" ]]; then
    log_info "TEST-496: running as root ignores file permission bits — the chmod 000 probe below cannot force a deterministic clone-build failure this way; this arm is inapplicable on this host"
    return
  fi
  local fx; fx="$(mg_new_fixture)"
  mg_seed_repo "$fx"
  mg_write_fixture_suite "$fx"
  mg_write_spec "$fx" "fixture-spec-496"
  printf "console.log('hello');\n" > "$fx/lib/greeting.mjs"
  ( cd "$fx" && git add -A && git commit -q -m base )
  printf 'marker-present' > "$fx/lib/extra.txt"

  local out rc
  out="$(cd "$fx" && node "$MUTATION_RUN" --spec docs/specs/fixture-spec.md --test-id TEST-9001 \
    --suite tests/skills/fixture-suite.sh --selector test_9001_greet_and_marker \
    --target lib/greeting.mjs --sed 's/hello/goodbye/' 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-496 setup: expected a RED record, got exit $rc: $out"

  # Force EVERY future buildIsolatedClone() call to fail deterministically:
  # `git -C ROOT rev-parse HEAD` is its very first command, so an unreadable
  # .git directory refuses immediately and reliably — no timing race needed
  # (unlike arm5's concurrent-editor race, this is the OTHER buildIsolatedClone
  # failure shape: not a tree mismatch, just "could not build a clone at all").
  chmod 000 "$fx/.git"
  out="$(cd "$fx" && node "$MUTATION_RUN" --replay --spec docs/specs/fixture-spec.md 2>&1)" && rc=0 || rc=$?
  chmod 755 "$fx/.git"
  [[ "$rc" -eq 4 ]] || log_fail "TEST-496: --replay must exit 4 (inconclusive) when buildIsolatedClone() itself fails, never exit 1 (a genuine regression), got $rc: $out"
  assert_payload_line_matches "$out" 'INCONCLUSIVE TEST-9001:.*could not build an isolated clone' \
    "TEST-496: replay must report TEST-9001 INCONCLUSIVE naming the clone-build failure: $out"
  assert_payload_not_contains "$out" "FAIL TEST-9001" \
    "TEST-496: a clone-build failure must never be reported as FAIL (a regression signal): $out"

  log_pass "TEST-496 --replay classifies a buildIsolatedClone() failure (this ride's own documented concurrent-operating-mode shape) as inconclusive, exit 4, never a genuine regression"
}

# --- TEST-497 — Spec-AC-01/D7 (NB-1, remediation round 4; supersedes the
# round-3 NB-5 shape): a concurrent write to a RUNTIME_ALLOWLIST path during
# the run must NOT downgrade a genuine verdict --------------------------
test_497_d7_ignores_runtime_allowlist_concurrent_write() {
  log_info "Test: a concurrent write to docs/ai/STATE.yaml or docs/ai/LOOP_TICKS.jsonl (gitignored, RUNTIME_ALLOWLIST) during the run is reproduced into the clone (D4) but excluded from the D7 before/after comparison, so the run's own RED verdict survives instead of being downgraded (TEST-497, closes NB-1)..."
  local fx; fx="$(mg_new_fixture)"
  mg_seed_repo "$fx"
  mg_write_spec "$fx" "fixture-spec-497"
  printf 'docs/ai/tdd/\ndocs/ai/STATE.yaml\ndocs/ai/LOOP_TICKS.jsonl\n' > "$fx/.gitignore"
  printf "console.log('hello');\n" > "$fx/lib/greeting.mjs"

  # A slow selector, so a background writer has a real window against the
  # SOURCE tree while the clone's suite runs (the same shape TEST-481 arm 5
  # uses for a TRACKED file — here the write lands on an UNTRACKED, ignored
  # runtime path instead, which is now REPRODUCED but not TRIPWIRED).
  cat > "$fx/tests/skills/fixture-suite.sh" <<'EOS'
#!/usr/bin/env bash
set -uo pipefail
FSCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FROOT="$(cd "$FSCRIPT_DIR/../.." && pwd)"
log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
test_9001_slow_greet() {
  sleep 3
  local out; out="$(node "$FROOT/lib/greeting.mjs" 2>&1)"
  [[ "$out" == "hello" ]] || log_fail "TEST-9001 greeting mismatch: got '$out'"
  log_pass "TEST-9001 greeting ok"
}
test_9002_slow_greet() {
  sleep 3
  local out; out="$(node "$FROOT/lib/greeting.mjs" 2>&1)"
  [[ "$out" == "hello" ]] || log_fail "TEST-9002 greeting mismatch: got '$out'"
  log_pass "TEST-9002 greeting ok"
}
test_9003_slow_greet() {
  sleep 3
  local out; out="$(node "$FROOT/lib/greeting.mjs" 2>&1)"
  [[ "$out" == "hello" ]] || log_fail "TEST-9003 greeting mismatch: got '$out'"
  log_pass "TEST-9003 greeting ok"
}
main() {
  if [[ -n "${1:-}" ]]; then
    declare -F "$1" >/dev/null || { echo "Unknown test: $1" >&2; exit 2; }
    "$1"; return
  fi
  test_9001_slow_greet
}
main "$@"
EOS
  ( cd "$fx" && git add -A && git commit -q -m base )

  # Arm 1 (TEST-9001): a concurrent write to docs/ai/STATE.yaml during the
  # run must leave the verdict RED (exit 0), never downgraded to
  # INCONCLUSIVE — the exact opposite of this test's pre-round-4 shape.
  ( sleep 1; mkdir -p "$fx/docs/ai" && printf 'current_focus: intruder\n' >> "$fx/docs/ai/STATE.yaml" ) &
  local bgpid=$!
  local out rc
  out="$(cd "$fx" && node "$MUTATION_RUN" --spec docs/specs/fixture-spec.md --test-id TEST-9001 \
    --suite tests/skills/fixture-suite.sh --selector test_9001_slow_greet \
    --target lib/greeting.mjs --sed 's/hello/goodbye/' 2>&1)" && rc=0 || rc=$?
  wait "$bgpid" 2>/dev/null || true
  [[ "$rc" -eq 0 ]] || log_fail "TEST-497 arm1: a concurrent write to docs/ai/STATE.yaml (RUNTIME_ALLOWLIST) must NOT downgrade the verdict (want exit 0 RED), got $rc: $out"
  assert_payload_not_contains "$out" "D7 tripwire" \
    "TEST-497 arm1: the allowlist write must never trip the D7 message: $out"
  local rec1; rec1="$(mg_record_path "$fx" fixture-spec-497 TEST-9001)"
  grep -qF 'verdict: RED' "$rec1" || log_fail "TEST-497 arm1: record's verdict is not RED: $(cat "$rec1")"

  # Arm 2 (TEST-9002): the same property for docs/ai/LOOP_TICKS.jsonl (a
  # log-tick-shaped append, the OTHER RUNTIME_ALLOWLIST path) — a distinct
  # test id AND its own selector (its FAIL line must name TEST-9002 for
  # classifyVerdict to read it as RED, not INCONCLUSIVE) so arm 1's record
  # is not rotated out from under this assertion either.
  ( sleep 1; mkdir -p "$fx/docs/ai" && printf '{"v":1,"ts":"2026-01-01T00:00:00Z","role":"orchestrator","event":"tick"}\n' >> "$fx/docs/ai/LOOP_TICKS.jsonl" ) &
  bgpid=$!
  out="$(cd "$fx" && node "$MUTATION_RUN" --spec docs/specs/fixture-spec.md --test-id TEST-9002 \
    --suite tests/skills/fixture-suite.sh --selector test_9002_slow_greet \
    --target lib/greeting.mjs --sed 's/hello/goodbye/' 2>&1)" && rc=0 || rc=$?
  wait "$bgpid" 2>/dev/null || true
  [[ "$rc" -eq 0 ]] || log_fail "TEST-497 arm2: a concurrent log-tick-shaped append to docs/ai/LOOP_TICKS.jsonl (RUNTIME_ALLOWLIST) must NOT downgrade the verdict (want exit 0 RED), got $rc: $out"
  assert_payload_not_contains "$out" "D7 tripwire" \
    "TEST-497 arm2: the allowlist write must never trip the D7 message: $out"
  local rec2; rec2="$(mg_record_path "$fx" fixture-spec-497 TEST-9002)"
  grep -qF 'verdict: RED' "$rec2" || log_fail "TEST-497 arm2: record's verdict is not RED: $(cat "$rec2")"

  # Arm 3 (TEST-9003, remediation round 5, NB1-r6, closes the round-4
  # mutation-free survivor): a RAPID appender (~50ms interval) writes to the
  # SOURCE docs/ai/STATE.yaml for the WHOLE run — clone build through suite
  # exit, not one well-timed write — proving buildIsolatedClone's D4 second
  # window (hashing the bytes it ACTUALLY copies into the clone, rather than
  # trusting the earlier computeTreeFileHashes(ROOT) snapshot) genuinely
  # closes under load. Started BEFORE the run and killed only after it
  # returns, so it is live across clone-build AND the (slow) suite run.
  local appender_stop; appender_stop="$fx/.appender-stop"
  rm -f "$appender_stop"
  ( while [[ ! -e "$appender_stop" ]]; do
      mkdir -p "$fx/docs/ai" 2>/dev/null
      printf 'current_focus: intruder\n' >> "$fx/docs/ai/STATE.yaml" 2>/dev/null
      sleep 0.05
    done ) &
  local apid=$!
  out="$(cd "$fx" && node "$MUTATION_RUN" --spec docs/specs/fixture-spec.md --test-id TEST-9003 \
    --suite tests/skills/fixture-suite.sh --selector test_9003_slow_greet \
    --target lib/greeting.mjs --sed 's/hello/goodbye/' 2>&1)" && rc=0 || rc=$?
  touch "$appender_stop"
  wait "$apid" 2>/dev/null || true
  [[ "$rc" -eq 0 ]] || log_fail "TEST-497 arm3 (NB1-r6): a RAPID (~50ms) whole-run concurrent appender to docs/ai/STATE.yaml (RUNTIME_ALLOWLIST) must NOT downgrade the verdict (want exit 0 RED), got $rc: $out"
  assert_payload_not_contains "$out" "D7 tripwire" \
    "TEST-497 arm3: the allowlist write must never trip the D7 message: $out"
  local rec3; rec3="$(mg_record_path "$fx" fixture-spec-497 TEST-9003)"
  grep -qF 'verdict: RED' "$rec3" || log_fail "TEST-497 arm3: record's verdict is not RED: $(cat "$rec3")"

  log_pass "TEST-497 the D7 tripwire reproduces RUNTIME_ALLOWLIST paths into the clone (D4) but excludes them from its own before/after comparison, so a canon-permitted concurrent ceremony write to docs/ai/STATE.yaml or docs/ai/LOOP_TICKS.jsonl never downgrades a genuine RED verdict, even under a rapid whole-run writer (NB1-r6)"
}

# --- TEST-498 — Spec-AC-05/D8 (NB-7, remediation round 3): a terminal-not-
# green Status cell exempts a row from the RED-record requirement -----------
test_498_gate_status_exemption() {
  log_info "Test: mutation-gate.mjs exempts a Test Plan row whose Status cell is deferred/dropped/rejected, naming it EXEMPT rather than demanding a RED record (TEST-498, closes NB-7)..."
  local suite="tests/skills/fixture-suite.sh"

  # (A) a single deferred row with NO record at all, and an empty Mutation
  # cell — the exact shape that used to be unsatisfiable without fabricating
  # a record or deleting the row.
  local id_a; id_a="$(mg_gate_id exempt-deferred)"
  local spec_a; spec_a="$(mg_new_fixture)/spec.md"
  mg_write_gate_spec "$spec_a" "$id_a" tdd "mutation_gate: v1" <<EOF
| TEST-9001 | Spec-AC-01 | unit | ${suite} | a |  | deferred |
EOF
  mkdir -p "$(mg_gate_evidence_dir "$id_a")"
  local out rc
  out="$(mg_gate "$spec_a" 2>&1)"; rc=$?
  # Remediation round 4 (NB-2): a Test Plan whose ONLY row is exempt is the
  # vacuous-pass shape — zero rows ever judged against the RED-record
  # requirement — so it is now its own named DEGRADE class, never printed as
  # an ordinary "GATE PASS: 0 row(s) satisfied" line an operator would read
  # as nothing-to-see-here.
  [[ "$rc" -eq 0 ]] || log_fail "TEST-498(A) deferred: want exit 0, got $rc: $out"
  assert_payload_line_matches "$out" 'EXEMPT TEST-9001: status deferred' \
    "TEST-498(A): deferred row not named EXEMPT: $out"
  assert_payload_contains "$out" 'DEGRADED: every row exempt (1)' \
    "TEST-498(A): the all-exempt vacuous pass must be a named DEGRADE class: $out"
  assert_payload_contains "$out" 'degraded=1' "TEST-498(A): degrade count wrong: $out"

  # (B) dropped and rejected, same shape, both exempt in one spec, alongside
  # ONE genuinely satisfied row — proves exemption is per-row, not
  # all-or-nothing, and the satisfied count excludes the exempt rows.
  local head_commit; head_commit="$(cd "$PROJECT_ROOT" && git rev-parse HEAD)"
  local id_b; id_b="$(mg_gate_id exempt-mixed)"
  local spec_b; spec_b="$(mg_new_fixture)/spec.md"
  mg_write_gate_spec "$spec_b" "$id_b" tdd "mutation_gate: v1" <<EOF
| TEST-9001 | Spec-AC-01 | unit | ${suite} | a |  | dropped |
| TEST-9002 | Spec-AC-01 | unit | ${suite} | b |  | rejected |
| TEST-9003 | Spec-AC-01 | unit | ${suite} | c | sed:s/OLD/NEW/ | pending |
EOF
  mg_write_gate_record "$(mg_gate_evidence_dir "$id_b")" TEST-9003 TEST-9003 "$suite" RED "$head_commit"
  out="$(mg_gate "$spec_b" 2>&1)"; rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-498(B) mixed: want exit 0, got $rc: $out"
  assert_payload_line_matches "$out" 'EXEMPT TEST-9001: status dropped' "TEST-498(B): TEST-9001 not EXEMPT: $out"
  assert_payload_line_matches "$out" 'EXEMPT TEST-9002: status rejected' "TEST-498(B): TEST-9002 not EXEMPT: $out"
  assert_payload_contains "$out" '1 row(s) satisfied' "TEST-498(B): satisfied count must exclude the two exempt rows: $out"

  # (C) a deferred row whose Status the gate reads case-insensitively / with
  # surrounding whitespace, still exempt.
  local id_c; id_c="$(mg_gate_id exempt-case)"
  local spec_c; spec_c="$(mg_new_fixture)/spec.md"
  mg_write_gate_spec "$spec_c" "$id_c" tdd "mutation_gate: v1" <<EOF
| TEST-9001 | Spec-AC-01 | unit | ${suite} | a |  | Deferred |
EOF
  mkdir -p "$(mg_gate_evidence_dir "$id_c")"
  out="$(mg_gate "$spec_c" 2>&1)"; rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-498(C) case-insensitive deferred: want exit 0, got $rc: $out"
  assert_payload_line_matches "$out" 'EXEMPT TEST-9001: status deferred' "TEST-498(C): mixed-case Deferred not exempted: $out"

  # (D) Remediation round 4 (NB-2): MULTIPLE exempt rows, none satisfied — the
  # DEGRADE class' count must reflect the real row count, not a hardcoded 1
  # (arm A only ever proved n=1); EXEMPT lines still print per row.
  local id_d; id_d="$(mg_gate_id exempt-all-multi)"
  local spec_d; spec_d="$(mg_new_fixture)/spec.md"
  mg_write_gate_spec "$spec_d" "$id_d" tdd "mutation_gate: v1" <<EOF
| TEST-9001 | Spec-AC-01 | unit | ${suite} | a |  | deferred |
| TEST-9002 | Spec-AC-01 | unit | ${suite} | b |  | dropped |
| TEST-9003 | Spec-AC-01 | unit | ${suite} | c |  | rejected |
EOF
  mkdir -p "$(mg_gate_evidence_dir "$id_d")"
  out="$(mg_gate "$spec_d" 2>&1)"; rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-498(D) all-exempt (n=3): want exit 0, got $rc: $out"
  assert_payload_contains "$out" 'DEGRADED: every row exempt (3)' \
    "TEST-498(D): the all-exempt count must reflect all 3 rows, not a hardcoded 1: $out"
  assert_payload_contains "$out" 'degraded=3' "TEST-498(D): degrade count wrong: $out"
  assert_payload_line_matches "$out" 'EXEMPT TEST-9001: status deferred' "TEST-498(D): TEST-9001 not EXEMPT: $out"
  assert_payload_line_matches "$out" 'EXEMPT TEST-9002: status dropped' "TEST-498(D): TEST-9002 not EXEMPT: $out"
  assert_payload_line_matches "$out" 'EXEMPT TEST-9003: status rejected' "TEST-498(D): TEST-9003 not EXEMPT: $out"

  log_pass "TEST-498 mutation-gate.mjs exempts a Test Plan row whose Status is deferred/dropped/rejected, naming it EXEMPT, excludes exempt rows from the satisfied count, and names an all-exempt Test Plan as its own DEGRADE class rather than a vacuous PASS"
}

# --- TEST-499 — Spec-AC-01/D7 (NB1-r3, remediation round 3): the NORMAL-run
# D7 self-check also names the changed path, not only --replay's -----------
test_499_d7_normal_run_names_path() {
  log_info "Test: a concurrent editor of a TRACKED file during a normal (non-replay) run is caught by the D7 tripwire and the message names the changed path, exactly like --replay's own message (TEST-499, closes the NB1-r3 mutation-free survivor)..."
  local fx; fx="$(mg_new_fixture)"
  mg_seed_repo "$fx"
  mg_write_spec "$fx" "fixture-spec-499"
  printf "console.log('hello');\n" > "$fx/lib/greeting.mjs"
  printf 'marker\n' > "$fx/CONCURRENT_MARKER.txt"
  ( cd "$fx" && git add -A && git commit -q -m base )

  cat > "$fx/tests/skills/fixture-suite.sh" <<'EOS'
#!/usr/bin/env bash
set -uo pipefail
FSCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FROOT="$(cd "$FSCRIPT_DIR/../.." && pwd)"
log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
test_9001_slow_greet() {
  sleep 3
  local out; out="$(node "$FROOT/lib/greeting.mjs" 2>&1)"
  [[ "$out" == "hello" ]] || log_fail "TEST-9001 greeting mismatch: got '$out'"
  log_pass "TEST-9001 greeting ok"
}
main() {
  if [[ -n "${1:-}" ]]; then
    declare -F "$1" >/dev/null || { echo "Unknown test: $1" >&2; exit 2; }
    "$1"; return
  fi
  test_9001_slow_greet
}
main "$@"
EOS
  ( cd "$fx" && git add -A && git commit -q -m 'slow selector' )

  ( sleep 1; printf 'edited-by-concurrent-writer\n' >> "$fx/CONCURRENT_MARKER.txt" ) &
  local bgpid=$!
  local out rc
  out="$(cd "$fx" && node "$MUTATION_RUN" --spec docs/specs/fixture-spec.md --test-id TEST-9001 \
    --suite tests/skills/fixture-suite.sh --selector test_9001_slow_greet \
    --target lib/greeting.mjs --sed 's/hello/goodbye/' 2>&1)" && rc=0 || rc=$?
  wait "$bgpid" 2>/dev/null || true
  [[ "$rc" -eq 6 ]] || log_fail "TEST-499: a normal run must exit 6 (INCONCLUSIVE) when the source tree changes concurrently, got $rc: $out"
  assert_payload_line_matches "$out" 'INCONCLUSIVE:.*CONCURRENT_MARKER\.txt' \
    "TEST-499: the normal-run D7 message must name the changed path CONCURRENT_MARKER.txt: $out"
  assert_payload_contains "$out" "this run, or another writer" \
    "TEST-499: the normal-run D7 message must own that it cannot tell a concurrent writer from its own run: $out"

  local rec; rec="$(mg_record_path "$fx" fixture-spec-499 TEST-9001)"
  grep -qF 'verdict: INCONCLUSIVE' "$rec" || log_fail "TEST-499: record's verdict is not INCONCLUSIVE: $(cat "$rec")"
  grep -qF 'CONCURRENT_MARKER.txt' "$rec" || log_fail "TEST-499: record's first_fail does not name the changed path: $(cat "$rec")"

  log_pass "TEST-499 the normal-run D7 self-check names the changed path exactly like --replay's own message, closing the NB1-r3 mutation-free survivor"
}

# --- TEST-500 — D2 (NB2-r3, remediation round 3): a rotated-name collision
# gets a monotonic suffix, never a silent overwrite --------------------------
test_500_rotation_same_second_suffix() {
  log_info "Test: a rotated record name collision (two rotations sharing one run_at_utc stamp) gets a monotonic .1/.2 suffix rather than silently overwriting the earlier archive (TEST-500, closes NB2-r3)..."
  local fx; fx="$(mg_new_fixture)"
  mg_seed_repo "$fx"
  mg_write_fixture_suite "$fx"
  mg_write_spec "$fx" "fixture-spec-500"
  printf "console.log('hello');\n" > "$fx/lib/greeting.mjs"
  ( cd "$fx" && git add -A && git commit -q -m base )
  printf 'marker-present' > "$fx/lib/extra.txt"

  # The first run is a --patch mutation, so a LIVE .patch sibling exists and
  # rotation has two files to move in lockstep (NB5-r4: the collision probe
  # must consider the patch name too, not only the record name).
  local patch1; patch1="$(mg_new_fixture)/first.patch"
  cat > "$patch1" <<'EOF'
--- a/lib/greeting.mjs
+++ b/lib/greeting.mjs
@@ -1 +1 @@
-console.log('hello');
+console.log('goodbye');
EOF
  local out rc
  out="$(cd "$fx" && node "$MUTATION_RUN" --spec docs/specs/fixture-spec.md --test-id TEST-9001 \
    --suite tests/skills/fixture-suite.sh --selector test_9001_greet_and_marker \
    --target lib/greeting.mjs --patch "$patch1" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-500 setup: expected a RED record, got exit $rc: $out"

  local rec; rec="$(mg_record_path "$fx" fixture-spec-500 TEST-9001)"
  local stamp; stamp="$(grep '^run_at_utc: ' "$rec" | sed 's/^run_at_utc: //')"
  local dir; dir="$(dirname "$rec")"

  # Pre-occupy the bare rotated name the NEXT run would try first, with a
  # marker the real tool must never touch — this deterministically forces the
  # same-second collision D2's rotation naming did not itself cover, without
  # relying on two real runs landing in the same wall-clock second.
  printf 'PRE-EXISTING ARCHIVE — must never be overwritten\n' > "$dir/mutation-TEST-9001.${stamp}.txt"
  # NB5-r4 arm: ALSO plant a decoy at the bare rotated PATCH name for the NEXT
  # stamp-free slot the record would otherwise take (.1) — a rotated .patch
  # sitting alone (its .txt gone, or planted by hand) must never be clobbered,
  # so both files must skip to .2 together.
  printf 'DECOY-ARCHIVE-DO-NOT-OVERWRITE\n' > "$dir/mutation-TEST-9001.${stamp}.1.patch"

  out="$(cd "$fx" && node "$MUTATION_RUN" --spec docs/specs/fixture-spec.md --test-id TEST-9001 \
    --suite tests/skills/fixture-suite.sh --selector test_9001_greet_and_marker \
    --target lib/greeting.mjs --sed "s/'\\);/')/" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 5 ]] || log_fail "TEST-500: second run (STAYED GREEN) exit wrong, got $rc: $out"

  [[ "$(cat "$dir/mutation-TEST-9001.${stamp}.txt")" == 'PRE-EXISTING ARCHIVE — must never be overwritten' ]] \
    || log_fail "TEST-500: the pre-existing archive at the bare stamp name was overwritten"

  [[ "$(cat "$dir/mutation-TEST-9001.${stamp}.1.patch")" == 'DECOY-ARCHIVE-DO-NOT-OVERWRITE' ]] \
    || log_fail "TEST-500 (NB5-r4): the decoy at the .1 rotated PATCH name was overwritten — the collision probe ignored the patch sibling"
  [[ ! -f "$dir/mutation-TEST-9001.${stamp}.1.txt" ]] \
    || log_fail "TEST-500 (NB5-r4): the record took the .1 slot while its patch sibling's .1 name was taken — the pair split"
  [[ -f "$dir/mutation-TEST-9001.${stamp}.2.txt" && -f "$dir/mutation-TEST-9001.${stamp}.2.patch" ]] \
    || log_fail "TEST-500: the real first record and its patch must be archived together at the .2 suffix once bare and .1 are taken, found: $(ls "$dir")"
  grep -qF 'test_id: TEST-9001' "$dir/mutation-TEST-9001.${stamp}.2.txt" \
    || log_fail "TEST-500: the .2-suffixed archive does not carry the rotated record's own content: $(cat "$dir/mutation-TEST-9001.${stamp}.2.txt")"
  grep -qF "mutation: patch:" "$dir/mutation-TEST-9001.${stamp}.2.txt" \
    || log_fail "TEST-500: the rotated record must still name a patch: $(grep '^mutation:' "$dir/mutation-TEST-9001.${stamp}.2.txt")"
  grep -F "${stamp}.2.patch" "$dir/mutation-TEST-9001.${stamp}.2.txt" >/dev/null \
    || log_fail "TEST-500: the rotated record's mutation: must point at its own .2 patch sibling: $(grep '^mutation:' "$dir/mutation-TEST-9001.${stamp}.2.txt")"

  log_pass "TEST-500 a rotated-name collision (same run_at_utc second) is resolved with a monotonic suffix shared by the record and its patch sibling — the pre-existing archive survives untouched, and the real record still gets archived"
}

# --- TEST-501 — D2/D14 (NB3-r3, remediation round 3): rotateExisting's
# pointer rewrite is not corrupted by $-patterns in the rotated path --------
test_501_rotation_dollar_pattern_safe() {
  log_info "Test: a rotated record's mutation: pointer rewrite survives a spec id containing \$-patterns (\$& etc.) without duplicating or truncating the record (TEST-501, closes NB3-r3)..."
  local fx; fx="$(mg_new_fixture)"
  mg_seed_repo "$fx"
  mg_write_fixture_suite "$fx"
  # A spec id containing a literal '$&' — the exact String.replace trap this
  # repo's own LEARNED rule names (js-replace-dollar-quote-corrupts):
  # rotatedPatchRel is built from this id, unvalidated (readSpecId), and
  # reaches rotateExisting's pointer rewrite.
  mg_write_spec "$fx" 'fixture-spec-501-a$&b'
  printf "console.log('hello');\n" > "$fx/lib/greeting.mjs"
  ( cd "$fx" && git add -A && git commit -q -m base )
  printf 'marker-present' > "$fx/lib/extra.txt"

  local patch1; patch1="$(mg_new_fixture)/first.patch"
  cat > "$patch1" <<'EOF'
--- a/lib/greeting.mjs
+++ b/lib/greeting.mjs
@@ -1 +1 @@
-console.log('hello');
+console.log('goodbye');
EOF
  local out rc
  out="$(cd "$fx" && node "$MUTATION_RUN" --spec docs/specs/fixture-spec.md --test-id TEST-9001 \
    --suite tests/skills/fixture-suite.sh --selector test_9001_greet_and_marker \
    --target lib/greeting.mjs --patch "$patch1" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-501 setup 1: expected a RED record, got exit $rc: $out"

  local rec; rec="$(mg_record_path "$fx" 'fixture-spec-501-a$&b' TEST-9001)"
  local run_at1; run_at1="$(grep '^run_at_utc: ' "$rec" | sed 's/^run_at_utc: //')"

  local patch2; patch2="$(mg_new_fixture)/second.patch"
  cat > "$patch2" <<'EOF'
--- a/lib/greeting.mjs
+++ b/lib/greeting.mjs
@@ -1 +1 @@
-console.log('hello');
+console.log('farewell');
EOF
  out="$(cd "$fx" && node "$MUTATION_RUN" --spec docs/specs/fixture-spec.md --test-id TEST-9001 \
    --suite tests/skills/fixture-suite.sh --selector test_9001_greet_and_marker \
    --target lib/greeting.mjs --patch "$patch2" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-501 setup 2: expected a second RED record (rotating the first), got exit $rc: $out"

  local rotated_txt; rotated_txt="$(dirname "$rec")/mutation-TEST-9001.${run_at1}.txt"
  [[ -f "$rotated_txt" ]] || log_fail "TEST-501: rotated record not found at $rotated_txt"

  # The parser is the authority on whether the record is intact — a
  # corrupted rewrite duplicates the tail or truncates the mutation: line,
  # and either shape breaks parseRecord (never re-implemented here).
  local parse_out
  parse_out="$(node --input-type=module -e "
import { parseRecord } from '$PROJECT_ROOT/.aai/scripts/lib/mutation-record.mjs';
import fs from 'node:fs';
const text = fs.readFileSync(process.argv[1], 'utf8');
const parsed = parseRecord(text);
if (!parsed.ok) { console.log('PARSE_FAIL: ' + parsed.error); process.exit(0); }
console.log('PARSE_OK mutation=' + parsed.fields.mutation);
" "$rotated_txt")"
  assert_payload_contains "$parse_out" "PARSE_OK" \
    "TEST-501: the rotated record must still parse as a valid v1 record after the pointer rewrite: $parse_out"
  assert_payload_contains "$parse_out" 'mutation=patch:docs/ai/tdd/fixture-spec-501-a$&b/mutation-TEST-9001' \
    "TEST-501: the rotated record's mutation: field must resolve to its OWN rotated patch path, literally (no \$-pattern reinterpretation): $parse_out"

  log_pass "TEST-501 rotateExisting's pointer rewrite passes a function (never a string) to String.replace, so a \$-bearing spec id in the rotated path is inserted literally rather than corrupting the record"
}

# --- TEST-502 — D2 (NB5-r3, remediation round 3): parseRecord tolerates an
# unrecognized header key -- this IS the v1 back-compat contract ------------
test_502_parse_record_tolerates_extra_field() {
  log_info "Test: a mutation record carrying an extra, unrecognized header key still parses as v1 and still satisfies the gate -- the exact tolerance the selector_honoured field (NB6-r2) depends on (TEST-502, closes NB5-r3)..."
  local suite="tests/skills/fixture-suite.sh"
  local head_commit; head_commit="$(cd "$PROJECT_ROOT" && git rev-parse HEAD)"

  local id; id="$(mg_gate_id extra-field-tolerance)"
  local spec; spec="$(mg_new_fixture)/spec.md"
  mg_write_gate_spec "$spec" "$id" tdd "mutation_gate: v1" <<EOF
| TEST-9001 | Spec-AC-01 | unit | ${suite} | a | sed:s/OLD/NEW/ | pending |
EOF
  local dir; dir="$(mg_gate_evidence_dir "$id")"
  mkdir -p "$dir"
  cat > "$dir/mutation-TEST-9001.txt" <<EOF
mutation_record: v1
spec_id: fixture
test_id: TEST-9001
suite: ${suite}
selector: test_fixture
target: lib/fixture.mjs
mutation: sed:s/OLD/NEW/
base_commit: ${head_commit}
tree_hash: $(printf '0%.0s' $(seq 1 64))
run_at_utc: 2026-01-01T00:00:00Z
rc: 1
verdict: RED
first_fail: FAIL fixture TEST-9001
some_future_field_nobody_has_written_yet: whatever
---
fixture tail
EOF

  local out rc
  out="$(mg_gate "$spec" 2>&1)"; rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-502: a record with an unrecognized extra header key must still satisfy the gate, got $rc: $out"
  assert_payload_contains "$out" 'GATE PASS' "TEST-502: expected GATE PASS: $out"
  assert_payload_contains "$out" 'satisfied degraded=0' "TEST-502: expected a clean satisfied summary: $out"

  log_pass "TEST-502 parseRecord's tolerance of an unrecognized header key is proved by a test, not merely asserted in prose -- the gate still passes a record carrying one"
}

# --- TEST-503 — Spec-AC-03 (NB6-r3, remediation round 3): a heredoc opener
# inside a COMMENT line must never open a real heredoc -----------------------
test_503_heredoc_in_comment_ignored() {
  log_info "Test: a heredoc marker mentioned inside a full-line comment does not consume a LATER, legitimate heredoc sharing the same marker -- a real selector between them is not swallowed (TEST-503, closes NB6-r3)..."
  local fx; fx="$(mg_new_fixture)"
  mg_seed_repo "$fx"
  mg_write_spec "$fx" "fixture-spec-503"
  printf "console.log('hello');\n" > "$fx/lib/greeting.mjs"

  cat > "$fx/tests/skills/fixture-suite.sh" <<'FIXTURE_EOS'
#!/usr/bin/env bash
set -uo pipefail
log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
# example: cat <<EOS
test_swallowed() {
  :
}
write_stuff() {
  cat <<EOS
some real heredoc body sharing the SAME marker as the comment above
EOS
}
test_after() {
  :
}
main() { "$1"; }
main "$@"
FIXTURE_EOS
  ( cd "$fx" && git add -A && git commit -q -m 'commented heredoc marker fixture' )

  local out rc
  out="$(cd "$fx" && node "$MUTATION_RUN" --spec docs/specs/fixture-spec.md --test-id TEST-9001 \
    --suite tests/skills/fixture-suite.sh --selector test_nonexistent_selector_xyz \
    --target lib/greeting.mjs --sed 's/hello/goodbye/' 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "TEST-503: unknown selector must exit 2, got $rc: $out"
  assert_payload_contains "$out" "test_swallowed" \
    "TEST-503: a real selector defined right after a COMMENTED heredoc opener must still be found, never swallowed up to the next real heredoc's terminator: $out"
  assert_payload_contains "$out" "test_after" \
    "TEST-503: a real selector defined after the legitimate heredoc must still be found: $out"

  log_pass "TEST-503 a heredoc marker mentioned inside a comment line never opens a real heredoc, so it cannot consume a later, legitimate heredoc's body and swallow the selectors in between"
}

# --- TEST-506 — D8 amendment (remediation round 5, BLOCKING-1, validation
# round 6): a record's own target_sha256 lets the gate see a STALE row —----
test_506_gate_detects_stale_target() {
  log_info "Test: a record whose target_sha256 no longer matches the LIVE target's bytes is OFFENDING (STALE), naming the row and the target; regenerating target_sha256 restores GATE PASS; a legacy record with no target_sha256 at all is counted unstamped= rather than treated as stale (TEST-506, closes BLOCKING-1)..."

  local id; id="$(mg_gate_id stale-target)"
  local spec; spec="$(mg_new_fixture)/spec.md"
  local dir; dir="$(mg_gate_evidence_dir "$id")"
  mkdir -p "$dir"
  local target_rel="docs/ai/tdd/$id/fixture-target.mjs"
  printf "console.log('v1');\n" > "$PROJECT_ROOT/$target_rel"

  local head_commit; head_commit="$(cd "$PROJECT_ROOT" && git rev-parse HEAD)"
  local sha1; sha1="$(cd "$PROJECT_ROOT" && shasum -a 256 "$target_rel" | awk '{print $1}')"

  mg_write_gate_spec "$spec" "$id" tdd "mutation_gate: v1" <<EOF
| TEST-9001 | Spec-AC-01 | unit | tests/skills/fixture-suite.sh | a | sed:s/OLD/NEW/ | pending |
EOF
  cat > "$dir/mutation-TEST-9001.txt" <<EOF
mutation_record: v1
spec_id: fixture
test_id: TEST-9001
suite: tests/skills/fixture-suite.sh
selector: test_fixture
target: ${target_rel}
mutation: sed:s/OLD/NEW/
base_commit: ${head_commit}
tree_hash: $(printf '0%.0s' $(seq 1 64))
run_at_utc: 2026-01-01T00:00:00Z
rc: 1
verdict: RED
first_fail: FAIL fixture TEST-9001
target_sha256: ${sha1}
---
fixture tail
EOF

  local out rc
  out="$(mg_gate "$spec" 2>&1)"; rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-506 setup: an unchanged target's record must satisfy the gate, got $rc: $out"
  assert_payload_contains "$out" 'unstamped=0' "TEST-506 setup: a stamped, unchanged record must not count as unstamped: $out"

  # The target changes AFTER the record was produced -- the record is now
  # STALE, even though it still parses, still names verdict RED, and its
  # base_commit is still an ancestor of HEAD.
  printf "console.log('v2');\n" > "$PROJECT_ROOT/$target_rel"
  out="$(mg_gate "$spec" 2>&1)"; rc=$?
  [[ "$rc" -eq 5 ]] || log_fail "TEST-506: a changed target must turn the row OFFENDING, got $rc: $out"
  assert_payload_contains "$out" "STALE TEST-9001" "TEST-506: the offending reason must name the STALE class: $out"
  assert_payload_contains "$out" "${target_rel} changed since the record" "TEST-506: the offending reason must name the changed target: $out"
  assert_payload_contains "$out" "re-run mutation-run.mjs" "TEST-506: the offending reason must name the remedy: $out"

  # Regenerating the record's target_sha256 (mutation-run.mjs's own job,
  # simulated here by hand for a hand-built fixture record) restores PASS.
  local sha2; sha2="$(cd "$PROJECT_ROOT" && shasum -a 256 "$target_rel" | awk '{print $1}')"
  local tmp_rec; tmp_rec="$(mktemp "${TMPDIR:-/tmp}/aai-mg-t506.XXXXXX")"
  sed "s/^target_sha256: .*/target_sha256: ${sha2}/" "$dir/mutation-TEST-9001.txt" > "$tmp_rec"
  mv "$tmp_rec" "$dir/mutation-TEST-9001.txt"
  out="$(mg_gate "$spec" 2>&1)"; rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-506: regenerating target_sha256 must restore GATE PASS, got $rc: $out"
  assert_payload_contains "$out" 'unstamped=0' "TEST-506: a freshly re-stamped record must not count as unstamped: $out"
  rm -f "$PROJECT_ROOT/$target_rel"

  # A LEGACY record with no target_sha256 field at all (mg_write_gate_record
  # never writes one) predates the D8 amendment -- it must NOT be treated as
  # stale (nothing to compare against), only counted in a named unstamped=
  # degrade, and the gate stays exit 0.
  local id2; id2="$(mg_gate_id stale-target-legacy)"
  local spec2; spec2="$(mg_new_fixture)/spec.md"
  mg_write_gate_spec "$spec2" "$id2" tdd "mutation_gate: v1" <<EOF
| TEST-9002 | Spec-AC-01 | unit | tests/skills/fixture-suite.sh | a | sed:s/OLD/NEW/ | pending |
EOF
  local dir2; dir2="$(mg_gate_evidence_dir "$id2")"
  mg_write_gate_record "$dir2" TEST-9002 TEST-9002 "tests/skills/fixture-suite.sh" RED "$head_commit"
  out="$(mg_gate "$spec2" 2>&1)"; rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-506: a legacy record with no target_sha256 must still satisfy the gate, got $rc: $out"
  assert_payload_contains "$out" 'unstamped=1' "TEST-506: a legacy record with no target_sha256 must be counted unstamped, got: $out"

  log_pass "TEST-506 a record's target_sha256 lets the gate catch a STALE row (target changed since the record) as OFFENDING, re-stamping restores PASS, and a legacy record with no target_sha256 is a named unstamped degrade, never mistaken for stale (closes BLOCKING-1)"
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
  test_nb1_dangling_symlink_no_leak
  test_491_heredoc_selector_extraction
  test_492_rotated_patch_pointer
  test_493_selector_honoured_field
  test_496_replay_clone_build_failure_inconclusive
  test_497_d7_ignores_runtime_allowlist_concurrent_write
  test_498_gate_status_exemption
  test_499_d7_normal_run_names_path
  test_500_rotation_same_second_suffix
  test_501_rotation_dollar_pattern_safe
  test_502_parse_record_tolerates_extra_field
  test_503_heredoc_in_comment_ignored
  test_506_gate_detects_stale_target
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
