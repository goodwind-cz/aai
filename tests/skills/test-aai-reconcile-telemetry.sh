#!/usr/bin/env bash
#
# Test: worktree-stranded committed telemetry reconciliation
# (CHANGE-0039 / docs/specs/SPEC-0055-spec-worktree-telemetry-reconciliation.md,
# TEST-001..008).
#
# Covers .aai/scripts/reconcile-telemetry.mjs — the deterministic PR-time
# helper that carries a scope's uncommitted-added METRICS.jsonl/EVENTS.jsonl
# lines from a sibling (main) checkout onto the current scope tree (a linked
# git worktree), append-only union deduped, staged, then scrubs the exact
# carried lines from the source (carry-before-clean) — plus its wiring into
# .aai/SKILL_PR.prompt.md.
#
#   - TEST-001 (Spec-AC-01): two-checkout fixture; a stranded scope-ref METRICS
#     record uncommitted-added in main; reconcile from the linked worktree;
#     assert the record lands in the worktree's METRICS.jsonl (created fresh —
#     it did not exist there) AND is staged.
#   - TEST-002 (Spec-AC-02): same fixture; a stranded scope-ref EVENTS.jsonl
#     line in main; reconcile; assert carried (union) + staged in the worktree.
#   - TEST-003 (Spec-AC-03): single-checkout (no `git worktree add` at all)
#     fixture; reconcile; assert exit 0, zero writes, nothing staged, and a
#     "nothing to carry" report line.
#   - TEST-004 (Spec-AC-04): run reconcile twice; assert the 2nd run makes
#     zero writes (byte-identical destination, same staged set) and the
#     source no longer strands the carried lines after the 1st run.
#   - TEST-005 (Spec-AC-05): main strands lines for scopeA + scopeB + one
#     unparseable garbage line; `--ref scopeA` carries ONLY scopeA's lines;
#     scopeB + the garbage line are untouched in BOTH trees; the run stages
#     EXACTLY the files it modified (nothing else).
#   - TEST-006 (Spec-AC-06, SEAM-1): strand a scope-ref `ac_evidence` EVENTS
#     line in main; reconcile; run the REAL docs-audit.mjs on the worktree
#     scope tree and assert it parses the carried line with no new violation;
#     also assert default cleanup leaves main's `git diff` free of the
#     carried line, while `--no-source-cleanup` leaves it in place.
#   - TEST-007 (Spec-AC-04): the worktree destination already carries an
#     identical committed line; reconcile does not duplicate it (full-line
#     dedupe). Plus `--dry-run` writes nothing and prints the plan JSON.
#   - TEST-008 (Spec-AC-06, SEAM-2): grep-guard — SKILL_PR.prompt.md wires
#     reconcile-telemetry.mjs as a PR-ceremony step AND lists
#     METRICS.jsonl/EVENTS.jsonl as expected companions in the staged-vs-scope
#     audit.
#
# Bonus (not a Spec-AC-gating test; fixture-diversity "mid-operation failure"
# item): a destination path that cannot be written (a directory in place of
# the file) makes the write step fail closed — exit 1, source untouched.
#
# Fixture diversity checklist (SPEC-0013 H7), mapped:
#   - degenerate/empty            -> TEST-001: destination METRICS.jsonl absent
#                                      entirely before the carry (created fresh)
#   - zero-remainder                -> TEST-004: 2nd run, zero writes
#   - multi-source/multi-writer      -> TEST-005: two refs' lines stranded in the
#                                      SAME source file by two different writers
#   - mid-operation failure           -> bonus test: write-time failure fails
#                                      closed, source untouched
#   - negative control                 -> TEST-005: unparseable garbage line
#                                      never carried nor removed
#
# ALL fixtures are throwaway git repos (a "main" checkout + a REAL linked
# `git worktree add` scope tree) under a mktemp dir, cleaned on EXIT — the
# pattern proven in tests/skills/test-aai-worktree.sh. The real repo's
# docs/ai/METRICS.jsonl and docs/ai/EVENTS.jsonl are NEVER touched — the
# script under test always runs with cwd = a fixture tree.
#
# bash 3.2 compatible (no ${var^^}, no declare -A). Run via
# .aai/scripts/aai-run-tests.sh per the LEARNED wrapper rule.
#
# Usage:
#   bash tests/skills/test-aai-reconcile-telemetry.sh
#   bash tests/skills/test-aai-reconcile-telemetry.sh test_002_events_carry_union_staged
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-reconcile-telemetry"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

RECONCILE="$PROJECT_ROOT/.aai/scripts/reconcile-telemetry.mjs"
DOCS_AUDIT="$PROJECT_ROOT/.aai/scripts/docs-audit.mjs"
SKILL_PR="$PROJECT_ROOT/.aai/SKILL_PR.prompt.md"

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then
    echo "INFO: keeping fixture at $TEST_DIR"
    return
  fi
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
    for m in "$TEST_DIR"/*-main "$TEST_DIR"/*-main2; do
      [[ -d "$m/.git" ]] || continue
      git -C "$m" worktree list --porcelain 2>/dev/null | grep '^worktree ' | cut -d' ' -f2- | while read -r wt; do
        [[ "$wt" != "$m" ]] && git -C "$m" worktree remove --force "$wt" 2>/dev/null || true
      done
    done
    rm -rf "$TEST_DIR"
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
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  [[ -f "$DOCS_AUDIT" ]] || log_fail "docs-audit.mjs not found: $DOCS_AUDIT"
  [[ -f "$SKILL_PR" ]] || log_fail "SKILL_PR.prompt.md not found: $SKILL_PR"
  # NOTE: RECONCILE is intentionally NOT required here — TEST-001..007 (and
  # the bonus test) RED naturally (node fails to load the absent module)
  # while the script does not yet exist, per the spec's RED-proof note.
  log_pass "Dependencies checked"
}

setup_fixture() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-reconcile-telemetry-test.XXXXXX")"
}

# --- fixture repo builders ---------------------------------------------------

metrics_header() {
  cat <<'EOF'
# AAI Metrics Ledger — append-only, one JSON object per line (JSONL format)
#
# Each line represents one completed work item flushed from STATE.yaml.
EOF
}

# new_main_repo <name> -> prints the fixture main checkout's absolute path.
new_main_repo() {
  local name="$1"
  local dir="$TEST_DIR/$name"
  mkdir -p "$dir/docs/ai"
  metrics_header > "$dir/docs/ai/METRICS.jsonl"
  : > "$dir/docs/ai/EVENTS.jsonl"
  git init -q "$dir"
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name test
  git -C "$dir" add -A
  git -C "$dir" commit -q -m init
  git -C "$dir" branch -M main
  echo "$dir"
}

# add_worktree <main_dir> <name> <branch> -> prints the linked worktree's path.
add_worktree() {
  local main_dir="$1" name="$2" branch="$3"
  local wt_dir="$TEST_DIR/$name"
  git -C "$main_dir" worktree add -q "$wt_dir" -b "$branch" main
  echo "$wt_dir"
}

# strand_line <dir> <relfile> <content> — append an UNCOMMITTED line to an
# already-tracked file (simulates flush/an agent writing in main and never
# committing it).
strand_line() {
  local dir="$1" relfile="$2" content="$3"
  printf '%s\n' "$content" >> "$dir/$relfile"
}

metrics_line() {
  local ref="$1" tag="${2:-x}"
  printf '{"date_utc":"2026-07-18","ref_id":"%s","title":"fixture %s","human_time_minutes":{"intake":null,"reviews":null},"agent_runs":[],"totals":{"human_time_minutes":0,"agent_duration_seconds":0,"total_cost_usd":null},"strategy":"tdd","reliability":{"validation_fails":0,"review_fails":0,"remediation_runs":0,"first_pass_clean":true},"verdict":"PASS"}' "$ref" "$tag"
}

events_line() {
  local ref="$1" event="${2:-ac_status}" tag="${3:-t}"
  printf '{"v":1,"ts":"2026-07-18T10:00:00.%s00Z","actor":"test","event":"%s","ref":"%s","payload":{"from":"implementing","to":"done"}}' "$tag" "$event" "$ref"
}

# --- invocation + assertion helpers ------------------------------------------

# run_reconcile <dir> <outfile> <errfile> <args...> — echoes the exit code.
run_reconcile() {
  local dir="$1" outfile="$2" errfile="$3"
  shift 3
  local code=0
  ( cd "$dir" && node "$RECONCILE" "$@" > "$outfile" 2> "$errfile" ) || code=$?
  echo "$code"
}

assert_exit() {
  local desc="$1" expected="$2" actual="$3"
  [[ "$actual" == "$expected" ]] \
    || log_fail "$desc: expected exit $expected, got $actual"
}

file_size() { wc -c < "$1" 2>/dev/null | tr -d ' '; }

staged_names() {
  git -C "$1" diff --cached --name-only
}

# --- TEST-001 -----------------------------------------------------------------

test_001_metrics_carry_created_fresh() {
  log_info "TEST-001: stranded METRICS record carried onto scope tree + staged (destination absent -> created fresh)"
  local main; main=$(new_main_repo t001-main)
  local wt; wt=$(add_worktree "$main" t001-wt scope-t001)

  # Destination starts with NO METRICS.jsonl at all (degenerate/empty case).
  git -C "$wt" rm -q docs/ai/METRICS.jsonl
  git -C "$wt" commit -q -m "remove metrics for fixture"
  [[ ! -f "$wt/docs/ai/METRICS.jsonl" ]] || log_fail "t001 setup: destination METRICS.jsonl should be absent"

  local line; line=$(metrics_line "scope-t001" "m1")
  strand_line "$main" docs/ai/METRICS.jsonl "$line"

  local out="$TEST_DIR/t001.out" err="$TEST_DIR/t001.err" code
  code=$(run_reconcile "$wt" "$out" "$err" --ref scope-t001)
  assert_exit "t001 reconcile" 0 "$code"

  [[ -f "$wt/docs/ai/METRICS.jsonl" ]] || log_fail "t001: destination METRICS.jsonl not created"
  grep -qF "$line" "$wt/docs/ai/METRICS.jsonl" \
    || log_fail "t001: carried record not present in destination METRICS.jsonl"
  staged_names "$wt" | grep -qF "docs/ai/METRICS.jsonl" \
    || log_fail "t001: docs/ai/METRICS.jsonl not staged"

  log_pass "Stranded METRICS record carried onto fresh destination + staged (TEST-001)"
}

# --- TEST-002 -----------------------------------------------------------------

test_002_events_carry_union_staged() {
  log_info "TEST-002: stranded scope-ref EVENTS line carried (union) + staged"
  local main; main=$(new_main_repo t002-main)
  local wt; wt=$(add_worktree "$main" t002-wt scope-t002)

  local eline; eline=$(events_line "scope-t002" "ac_status" "a")
  strand_line "$main" docs/ai/EVENTS.jsonl "$eline"

  local out="$TEST_DIR/t002.out" err="$TEST_DIR/t002.err" code
  code=$(run_reconcile "$wt" "$out" "$err" --ref scope-t002)
  assert_exit "t002 reconcile" 0 "$code"

  grep -qF "$eline" "$wt/docs/ai/EVENTS.jsonl" \
    || log_fail "t002: carried EVENTS line not present in destination"
  staged_names "$wt" | grep -qF "docs/ai/EVENTS.jsonl" \
    || log_fail "t002: docs/ai/EVENTS.jsonl not staged"

  log_pass "Stranded EVENTS line carried (union) + staged (TEST-002)"
}

# --- TEST-003 -----------------------------------------------------------------

test_003_inline_verified_noop() {
  log_info "TEST-003: single-checkout (no sibling worktree) -> verified no-op"
  local main; main=$(new_main_repo t003-main)

  local before before_e
  before=$(file_size "$main/docs/ai/METRICS.jsonl")
  before_e=$(file_size "$main/docs/ai/EVENTS.jsonl")

  local out="$TEST_DIR/t003.out" err="$TEST_DIR/t003.err" code
  code=$(run_reconcile "$main" "$out" "$err" --ref anything)
  assert_exit "t003 reconcile" 0 "$code"

  [[ "$(file_size "$main/docs/ai/METRICS.jsonl")" == "$before" ]] \
    || log_fail "t003: METRICS.jsonl changed on inline no-op"
  [[ "$(file_size "$main/docs/ai/EVENTS.jsonl")" == "$before_e" ]] \
    || log_fail "t003: EVENTS.jsonl changed on inline no-op"
  [[ -z "$(staged_names "$main")" ]] \
    || log_fail "t003: something got staged on inline no-op"
  grep -qi "nothing to carry" "$out" \
    || log_fail "t003: expected a 'nothing to carry' report line, got: $(cat "$out")"

  log_pass "Inline single-checkout scope is a verified no-op (TEST-003)"
}

# --- TEST-004 -----------------------------------------------------------------

test_004_idempotent_rerun() {
  log_info "TEST-004: re-running carries nothing new; byte-identical destination; source no longer strands"
  local main; main=$(new_main_repo t004-main)
  local wt; wt=$(add_worktree "$main" t004-wt scope-t004)

  local line eline
  line=$(metrics_line "scope-t004" "m1")
  strand_line "$main" docs/ai/METRICS.jsonl "$line"
  eline=$(events_line "scope-t004" "ac_status" "a")
  strand_line "$main" docs/ai/EVENTS.jsonl "$eline"

  local out1="$TEST_DIR/t004-1.out" err1="$TEST_DIR/t004-1.err" code1
  code1=$(run_reconcile "$wt" "$out1" "$err1" --ref scope-t004)
  assert_exit "t004 first run" 0 "$code1"

  local m_after1 e_after1 staged_before
  m_after1=$(cat "$wt/docs/ai/METRICS.jsonl")
  e_after1=$(cat "$wt/docs/ai/EVENTS.jsonl")
  staged_before=$(staged_names "$wt")

  # Source no longer strands the carried lines after the first (default) run.
  if git -C "$main" diff -- docs/ai/METRICS.jsonl | grep -qF "$line"; then
    log_fail "t004: source still strands the METRICS line after default cleanup"
  fi
  if git -C "$main" diff -- docs/ai/EVENTS.jsonl | grep -qF "$eline"; then
    log_fail "t004: source still strands the EVENTS line after default cleanup"
  fi

  local out2="$TEST_DIR/t004-2.out" err2="$TEST_DIR/t004-2.err" code2
  code2=$(run_reconcile "$wt" "$out2" "$err2" --ref scope-t004)
  assert_exit "t004 second run" 0 "$code2"

  [[ "$(cat "$wt/docs/ai/METRICS.jsonl")" == "$m_after1" ]] \
    || log_fail "t004: METRICS.jsonl not byte-identical after 2nd run"
  [[ "$(cat "$wt/docs/ai/EVENTS.jsonl")" == "$e_after1" ]] \
    || log_fail "t004: EVENTS.jsonl not byte-identical after 2nd run"
  [[ "$(staged_names "$wt")" == "$staged_before" ]] \
    || log_fail "t004: 2nd run changed the staged file set (should be zero writes)"
  grep -qi "nothing to carry" "$out2" \
    || log_fail "t004: 2nd run expected a 'nothing to carry' report line, got: $(cat "$out2")"

  log_pass "Idempotent re-run: zero writes, source stays clean (TEST-004)"
}

# --- TEST-005 -----------------------------------------------------------------

test_005_ref_isolation_and_garbage_skip() {
  log_info "TEST-005: --ref filters to scopeA only; scopeB + garbage line untouched; exact staged set"
  local main; main=$(new_main_repo t005-main)
  local wt; wt=$(add_worktree "$main" t005-wt scope-t005a)

  local lineA lineB elineA elineB
  lineA=$(metrics_line "scope-t005a" "a")
  lineB=$(metrics_line "scope-t005b" "b")
  strand_line "$main" docs/ai/METRICS.jsonl "$lineA"
  strand_line "$main" docs/ai/METRICS.jsonl "$lineB"
  strand_line "$main" docs/ai/METRICS.jsonl '{not valid json'
  elineA=$(events_line "scope-t005a" "ac_status" "a")
  elineB=$(events_line "scope-t005b" "ac_status" "b")
  strand_line "$main" docs/ai/EVENTS.jsonl "$elineA"
  strand_line "$main" docs/ai/EVENTS.jsonl "$elineB"

  local out="$TEST_DIR/t005.out" err="$TEST_DIR/t005.err" code
  code=$(run_reconcile "$wt" "$out" "$err" --ref scope-t005a)
  assert_exit "t005 reconcile" 0 "$code"

  grep -qF "$lineA" "$wt/docs/ai/METRICS.jsonl" || log_fail "t005: scopeA METRICS line not carried"
  if grep -qF "$lineB" "$wt/docs/ai/METRICS.jsonl"; then
    log_fail "t005: scopeB METRICS line WAS carried (ref isolation violated)"
  fi
  grep -qF "$elineA" "$wt/docs/ai/EVENTS.jsonl" || log_fail "t005: scopeA EVENTS line not carried"
  if grep -qF "$elineB" "$wt/docs/ai/EVENTS.jsonl"; then
    log_fail "t005: scopeB EVENTS line WAS carried (ref isolation violated)"
  fi

  # scopeB + garbage line are still present, untouched, in the source.
  grep -qF "$lineB" "$main/docs/ai/METRICS.jsonl" \
    || log_fail "t005: scopeB METRICS line removed from source (must stay untouched)"
  grep -qF '{not valid json' "$main/docs/ai/METRICS.jsonl" \
    || log_fail "t005: garbage line removed from source (must never be touched)"
  grep -qF "$elineB" "$main/docs/ai/EVENTS.jsonl" \
    || log_fail "t005: scopeB EVENTS line removed from source (must stay untouched)"

  # scopeA lines are gone from source (default cleanup).
  if git -C "$main" diff -- docs/ai/METRICS.jsonl | grep -qF "$lineA"; then
    log_fail "t005: scopeA METRICS line still stranded in source after cleanup"
  fi

  # Exactly the touched files are staged — nothing else.
  local staged expected
  staged=$(staged_names "$wt" | sort)
  expected=$(printf 'docs/ai/EVENTS.jsonl\ndocs/ai/METRICS.jsonl')
  [[ "$staged" == "$expected" ]] \
    || log_fail "t005: staged set mismatch — expected exactly METRICS.jsonl+EVENTS.jsonl, got: $staged"

  log_pass "Ref isolation + garbage-line skip + exact staged set (TEST-005)"
}

# --- TEST-006 -----------------------------------------------------------------

test_006_seam1_real_audit_and_cleanup_toggle() {
  log_info "TEST-006: SEAM-1 real docs-audit on carried EVENTS line; cleanup on/off"
  local main; main=$(new_main_repo t006-main)
  local wt; wt=$(add_worktree "$main" t006-wt scope-t006)

  local eline; eline=$(events_line "scope-t006" "ac_evidence" "a")
  strand_line "$main" docs/ai/EVENTS.jsonl "$eline"

  local out="$TEST_DIR/t006.out" err="$TEST_DIR/t006.err" code
  code=$(run_reconcile "$wt" "$out" "$err" --ref scope-t006)
  assert_exit "t006 reconcile" 0 "$code"
  grep -qF "$eline" "$wt/docs/ai/EVENTS.jsonl" || log_fail "t006: carried ac_evidence line missing from destination"

  # Default cleanup: source no longer strands it.
  if git -C "$main" diff -- docs/ai/EVENTS.jsonl | grep -qF "$eline"; then
    log_fail "t006: source still strands the carried line after default cleanup"
  fi

  # SEAM-1: the REAL docs-audit.mjs runs on the scope tree and parses/attributes
  # the carried line with no new finding (no crash, clean exit).
  local aout="$TEST_DIR/t006-audit.out" aerr="$TEST_DIR/t006-audit.err" acode=0
  ( cd "$wt" && node "$DOCS_AUDIT" --check --no-event > "$aout" 2> "$aerr" ) || acode=$?
  [[ "$acode" == "0" ]] || log_fail "t006: real docs-audit.mjs did not exit 0 on the carried line: $(cat "$aerr")"
  if grep -qi "schema violation" "$aout"; then
    log_fail "t006: docs-audit reported a schema violation for the carried line"
  fi

  # --no-source-cleanup leaves the source edit in place.
  local main2; main2=$(new_main_repo t006b-main)
  local wt2; wt2=$(add_worktree "$main2" t006b-wt scope-t006b)
  local eline2; eline2=$(events_line "scope-t006b" "ac_evidence" "b")
  strand_line "$main2" docs/ai/EVENTS.jsonl "$eline2"
  local out2="$TEST_DIR/t006b.out" err2="$TEST_DIR/t006b.err" code2
  code2=$(run_reconcile "$wt2" "$out2" "$err2" --ref scope-t006b --no-source-cleanup)
  assert_exit "t006b reconcile --no-source-cleanup" 0 "$code2"
  grep -qF "$eline2" "$wt2/docs/ai/EVENTS.jsonl" || log_fail "t006b: line not carried with --no-source-cleanup"
  git -C "$main2" diff -- docs/ai/EVENTS.jsonl | grep -qF "$eline2" \
    || log_fail "t006b: --no-source-cleanup should leave the source edit in place"

  log_pass "SEAM-1 real docs-audit clean + carry-before-clean toggle verified (TEST-006)"
}

# --- TEST-007 -----------------------------------------------------------------

test_007_dedupe_and_dry_run() {
  log_info "TEST-007: destination already has an identical line -> no duplicate; --dry-run writes nothing"
  local main; main=$(new_main_repo t007-main)
  local wt; wt=$(add_worktree "$main" t007-wt scope-t007)

  local line; line=$(metrics_line "scope-t007" "m1")
  # Pre-seed the destination with the identical line, committed.
  strand_line "$wt" docs/ai/METRICS.jsonl "$line"
  git -C "$wt" add docs/ai/METRICS.jsonl
  git -C "$wt" commit -q -m "pre-existing identical metrics line"

  strand_line "$main" docs/ai/METRICS.jsonl "$line"

  local out="$TEST_DIR/t007.out" err="$TEST_DIR/t007.err" code
  code=$(run_reconcile "$wt" "$out" "$err" --ref scope-t007)
  assert_exit "t007 reconcile" 0 "$code"

  local count
  count=$(grep -cF "$line" "$wt/docs/ai/METRICS.jsonl")
  [[ "$count" == "1" ]] || log_fail "t007: expected exactly 1 occurrence of the line (dedup), got $count"

  # --dry-run on a fresh pair: writes nothing, prints plan JSON.
  local main2; main2=$(new_main_repo t007b-main)
  local wt2; wt2=$(add_worktree "$main2" t007b-wt scope-t007b)
  local line2; line2=$(metrics_line "scope-t007b" "m2")
  strand_line "$main2" docs/ai/METRICS.jsonl "$line2"
  local before; before=$(cat "$wt2/docs/ai/METRICS.jsonl")

  local out2="$TEST_DIR/t007b.out" err2="$TEST_DIR/t007b.err" code2
  code2=$(run_reconcile "$wt2" "$out2" "$err2" --ref scope-t007b --dry-run)
  assert_exit "t007b dry-run" 0 "$code2"
  [[ "$(cat "$wt2/docs/ai/METRICS.jsonl")" == "$before" ]] \
    || log_fail "t007b: --dry-run wrote to the destination"
  [[ -z "$(staged_names "$wt2")" ]] \
    || log_fail "t007b: --dry-run staged something"
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'))" "$out2" \
    || log_fail "t007b: --dry-run stdout is not valid JSON"
  grep -qF "scope-t007b" "$out2" || log_fail "t007b: dry-run plan JSON does not mention the ref"

  log_pass "Full-line dedupe + --dry-run writes nothing (TEST-007)"
}

# --- TEST-008 -----------------------------------------------------------------

test_008_skill_pr_grep_guard() {
  log_info "TEST-008: SKILL_PR.prompt.md wires the reconcile step + lists METRICS/EVENTS as expected companions"
  grep -q "reconcile-telemetry.mjs" "$SKILL_PR" \
    || log_fail "t008: SKILL_PR.prompt.md does not mention reconcile-telemetry.mjs"
  grep -qi "RECONCILE" "$SKILL_PR" \
    || log_fail "t008: SKILL_PR.prompt.md has no RECONCILE-named step"
  grep -q "docs/ai/METRICS.jsonl" "$SKILL_PR" \
    || log_fail "t008: SKILL_PR.prompt.md does not list docs/ai/METRICS.jsonl as an expected companion"
  grep -q "docs/ai/EVENTS.jsonl" "$SKILL_PR" \
    || log_fail "t008: SKILL_PR.prompt.md does not list docs/ai/EVENTS.jsonl as an expected companion"
  log_pass "SKILL_PR.prompt.md reconcile wiring + expected-companions grep-guard (TEST-008)"
}

# --- BONUS ---------------------------------------------------------------------

test_009_bonus_write_failure_fails_closed() {
  log_info "BONUS: destination write failure (mid-operation) fails closed, source untouched"
  local main; main=$(new_main_repo t009-main)
  local wt; wt=$(add_worktree "$main" t009-wt scope-t009)

  local line; line=$(metrics_line "scope-t009" "m1")
  strand_line "$main" docs/ai/METRICS.jsonl "$line"

  # Rig the destination: replace the tracked file with a directory so the
  # write step fails (EISDIR) instead of succeeding.
  rm -f "$wt/docs/ai/METRICS.jsonl"
  mkdir -p "$wt/docs/ai/METRICS.jsonl"

  local out="$TEST_DIR/t009.out" err="$TEST_DIR/t009.err" code
  code=$(run_reconcile "$wt" "$out" "$err" --ref scope-t009)
  assert_exit "t009 write failure fails closed" 1 "$code"
  # Must be OUR diagnosed failure (the script ran, attempted the write, and
  # reported cleanly) — not a Node module-resolution crash, which would also
  # exit 1 but prove nothing about fail-closed behavior.
  grep -q "reconcile-telemetry:" "$err" \
    || log_fail "t009: expected a reconcile-telemetry diagnostic on stderr, got: $(cat "$err")"
  if grep -qi "Cannot find module\|MODULE_NOT_FOUND" "$err"; then
    log_fail "t009: failure is a module-resolution crash, not a diagnosed write failure: $(cat "$err")"
  fi

  git -C "$main" diff -- docs/ai/METRICS.jsonl | grep -qF "$line" \
    || log_fail "t009: source line was removed despite the destination write failure (must fail closed)"

  log_pass "Mid-operation write failure fails closed; source untouched (BONUS)"
}

main() {
  echo "=== $TEST_NAME ==="
  check_deps
  setup_fixture

  if [[ $# -gt 0 ]]; then
    "$1"
    echo "=== $TEST_NAME: SELECTED TEST PASSED ($1) ==="
    return
  fi

  test_001_metrics_carry_created_fresh
  test_002_events_carry_union_staged
  test_003_inline_verified_noop
  test_004_idempotent_rerun
  test_005_ref_isolation_and_garbage_skip
  test_006_seam1_real_audit_and_cleanup_toggle
  test_007_dedupe_and_dry_run
  test_008_skill_pr_grep_guard
  test_009_bonus_write_failure_fails_closed

  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}

main "$@"
