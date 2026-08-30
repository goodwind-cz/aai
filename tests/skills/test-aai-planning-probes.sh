#!/usr/bin/env bash
#
# Test: planning behavioral probes — the two Planning boundaries that live in
# NO artifact the other suites read (CHANGE-0113 D2, disposition rows R04/R09
# in docs/analysis/altitude-disposition-PLANNING.md).
#
#   R04  "No code implementation in planning."  A Planning run's diff must
#        touch only docs/specs/**, docs/ai/** and docs/INDEX.md.
#   R09  "Do not create a git worktree during Planning."
#
# WHY A PROBE SUITE AND NOT A PROMPT LINE
#   Both rules were prose in .aai/PLANNING.prompt.md and nothing at runtime
#   inspected what a Planning run actually DID. The enforcement now lives in
#   .aai/scripts/check-role-output.mjs behind two OPTIONAL flags
#   (--base-ref, --worktree-baseline / --worktree-guard). The flags are opt-in
#   because the orchestrator's merge-protocol step 1 invocation
#   (.aai/SUBAGENT_PROTOCOL.md) passes only `--file`, and ORCHESTRATION.prompt.md
#   sits at its hard 40-line cap — buying live wiring would cost prompt bytes
#   the diet ledger would have to fund. So the HONEST scope is:
#     - the CHECK is real, deterministic and shipped;
#     - this suite is what proves it catches each violation, by running a
#       scripted fake-Planning run that commits the violation on purpose;
#     - a live ride only gets the check when the operator (or a future
#       orchestrator change) passes the flags. That gap is stated in
#       .aai/SUBAGENT_PROTOCOL.md and in the CHANGE-0113 adoption intake
#       rather than papered over.
#
# Bash-3.2 safe (no associative arrays, no `mapfile`) — macOS default shell.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -uo pipefail

TEST_NAME="aai-planning-probes"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Pipe-free payload assertions (spec-assertions-must-not-die-on-their-own-payload).
# shellcheck source=lib/assert-payload.sh
. "$SCRIPT_DIR/lib/assert-payload.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHECKER="$PROJECT_ROOT/.aai/scripts/check-role-output.mjs"
PROTOCOL_DOC="$PROJECT_ROOT/.aai/SUBAGENT_PROTOCOL.md"

FAILED=0
TMP_ROOT=""
REPO=""

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then
    echo "INFO: keeping fixtures under $TMP_ROOT"
    return 0
  fi
  [[ -n "${TMP_ROOT:-}" && -d "$TMP_ROOT" ]] && rm -rf "$TMP_ROOT"
  return 0
}
trap cleanup EXIT

log_pass() { echo "PASS $*"; }
log_fail() { echo "FAIL $*" >&2; FAILED=1; }
log_skip() { echo "SKIP $*"; exit 42; }
log_info() { echo "  $*"; }

check_deps() {
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  [[ -f "$CHECKER" ]] || log_info "NOTE: $CHECKER missing (expected only on the pre-change RED tree)"
  TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aai-planning-probes.XXXXXX")"
}

expect_exit() {
  local want="$1" got="$2" label="$3"
  if [[ "$got" -ne "$want" ]]; then
    log_info "$label: exit $got (want $want)"
    return 1
  fi
  return 0
}

# new_repo — scratch git repo with one baseline commit on `main`. $REPO set.
new_repo() {
  REPO="$(mktemp -d "$TMP_ROOT/repo.XXXXXX")"
  mkdir -p "$REPO/docs/specs" "$REPO/docs/ai" "$REPO/src"
  (
    cd "$REPO" || exit 1
    git -c init.defaultBranch=main init -q .
    git config user.email "fixture@example.com"
    git config user.name "fixture"
    echo "baseline" > src/app.mjs
    echo "# Index" > docs/INDEX.md
    git add -A && git commit -qm baseline
  ) || return 1
}

# result_block <file> <role> — a minimal VALID subagent_result for that role.
result_block() {
  local out="$1" role="$2"
  {
    echo "Role run complete."
    echo ""
    echo '```yaml'
    echo 'subagent_result:'
    echo '  scope: CHANGE-0113'
    echo "  role: $role"
    echo '  status: PASS'
    echo '  started_utc: 2026-01-07T00:00:00Z'
    echo '  ended_utc: 2026-01-07T00:05:00Z'
    echo '  duration_seconds: 300'
    echo '  evidence:'
    echo '    - command: node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-DRAFT-x.md'
    echo '      exit_code: 0'
    echo '  files_changed: []'
    echo '  blockers: []'
    echo '```'
  } > "$out"
}

runcheck() { (cd "$REPO" && node "$CHECKER" "$@"); }

# --- PROBE-001 (R04) — a Planning run that writes CODE is caught --------------
test_001_r04_code_write_caught() {
  local out rc ok=1
  new_repo || { log_fail "PROBE-001 fixture setup failed"; return; }

  # SCRIPTED FAKE-PLANNING RUN — it does the legitimate half (a spec + a STATE
  # write) AND the violation (edits a source file, adds a test file). This is
  # the tempting shortcut the prose rule was written against: "the fix is two
  # lines, I'll just do it while I'm here".
  (
    cd "$REPO" || exit 1
    printf -- '---\nid: spec-x\ntype: spec\nstatus: draft\n---\n\n# Spec\n' > docs/specs/SPEC-DRAFT-x.md
    printf 'current_focus: CHANGE-0113\n' > docs/ai/STATE.yaml
    echo "planning could not resist" >> src/app.mjs
    printf 'echo new test\n' > tests-new.sh
  )
  result_block "$TMP_ROOT/msg.md" "Planning"

  out="$(runcheck --file "$TMP_ROOT/msg.md" --now 2026-06-01T00:00:00Z --base-ref main)"; rc=$?
  expect_exit 1 "$rc" "PROBE-001 code write" || ok=0
  assert_payload_contains "$out" "ROLE-OUTPUT-VIOLATION: E-PLANNING-WROTE-CODE" "PROBE-001: no E-PLANNING-WROTE-CODE line: $out" || ok=0
  assert_payload_contains "$out" "src/app.mjs" "PROBE-001: the modified source file was not named: $out" || ok=0
  assert_payload_contains "$out" "tests-new.sh" "PROBE-001: the NEW untracked file was not named (untracked writes must count): $out" || ok=0
  assert_payload_not_contains "$out" "docs/specs/SPEC-DRAFT-x.md" "PROBE-001: an ALLOWED path was reported as a violation: $out" || ok=0
  [[ $ok -eq 1 ]] && log_pass "PROBE-001 (R04) a Planning run that writes code/tests is caught, tracked AND untracked" \
    || log_fail "PROBE-001 (R04) code write"
}

# --- PROBE-002 (R04) — the allowed surface is clean ---------------------------
test_002_r04_allowed_surface_clean() {
  local out rc ok=1
  new_repo || { log_fail "PROBE-002 fixture setup failed"; return; }
  (
    cd "$REPO" || exit 1
    printf -- '---\nid: spec-x\ntype: spec\nstatus: draft\n---\n\n# Spec\n' > docs/specs/SPEC-DRAFT-x.md
    printf 'current_focus: CHANGE-0113\n' > docs/ai/STATE.yaml
    mkdir -p docs/ai/briefs && printf '# brief\n' > docs/ai/briefs/CHANGE-0113.md
    printf '# Index\n- SPEC-DRAFT-x\n' > docs/INDEX.md
  )
  result_block "$TMP_ROOT/msg.md" "Planning"
  out="$(runcheck --file "$TMP_ROOT/msg.md" --now 2026-06-01T00:00:00Z --base-ref main)"; rc=$?
  expect_exit 0 "$rc" "PROBE-002 allowed surface" || ok=0
  [[ -z "$out" ]] || { log_info "PROBE-002: a clean Planning diff produced output: $out"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "PROBE-002 (R04) docs/specs + docs/ai + docs/INDEX.md is the allowed Planning surface" \
    || log_fail "PROBE-002 (R04) allowed surface"
}

# --- PROBE-003 (R09) — a worktree created during the run is caught ------------
test_003_r09_new_worktree_caught() {
  local out rc ok=1
  new_repo || { log_fail "PROBE-003 fixture setup failed"; return; }
  # BEFORE the run: capture the worktree baseline (this is what a wired
  # orchestrator would do; here the probe harness does it).
  (cd "$REPO" && git worktree list --porcelain) > "$TMP_ROOT/wt-baseline.txt"

  # SCRIPTED FAKE-PLANNING RUN — it creates the worktree the rule forbids.
  (cd "$REPO" && git worktree add -q -b feature/CHANGE-0113 "$TMP_ROOT/wt-CHANGE-0113" >/dev/null 2>&1)
  result_block "$TMP_ROOT/msg.md" "Planning"

  out="$(runcheck --file "$TMP_ROOT/msg.md" --now 2026-06-01T00:00:00Z --worktree-baseline "$TMP_ROOT/wt-baseline.txt")"; rc=$?
  expect_exit 1 "$rc" "PROBE-003 new worktree" || ok=0
  assert_payload_contains "$out" "ROLE-OUTPUT-VIOLATION: E-PLANNING-WORKTREE" "PROBE-003: no E-PLANNING-WORKTREE line: $out" || ok=0
  assert_payload_contains "$out" "wt-CHANGE-0113" "PROBE-003: the new worktree was not named: $out" || ok=0

  # CONTROL: the same baseline against an UNCHANGED worktree list is clean.
  new_repo || { log_fail "PROBE-003 control setup failed"; return; }
  (cd "$REPO" && git worktree list --porcelain) > "$TMP_ROOT/wt-baseline2.txt"
  result_block "$TMP_ROOT/msg.md" "Planning"
  out="$(runcheck --file "$TMP_ROOT/msg.md" --now 2026-06-01T00:00:00Z --worktree-baseline "$TMP_ROOT/wt-baseline2.txt")"; rc=$?
  expect_exit 0 "$rc" "PROBE-003 unchanged control" || ok=0
  [[ $ok -eq 1 ]] && log_pass "PROBE-003 (R09) a worktree created during the run is caught against a baseline; an unchanged list is clean" \
    || log_fail "PROBE-003 (R09) new worktree"
}

# --- PROBE-004 (R09) — the baseline-free guard catches a scope-named tree -----
# A wired orchestrator has no before-capture today, so --worktree-guard answers
# the weaker but still useful question: is there a worktree belonging to THIS
# scope? That is the realistic violation shape (Planning creating the ride's
# own isolation tree). Its limits are asserted here, not hidden.
test_004_r09_scope_guard() {
  local out rc ok=1
  new_repo || { log_fail "PROBE-004 fixture setup failed"; return; }
  (cd "$REPO" && git worktree add -q -b feature/CHANGE-0113 "$TMP_ROOT/guard-CHANGE-0113" >/dev/null 2>&1)
  result_block "$TMP_ROOT/msg.md" "Planning"
  out="$(runcheck --file "$TMP_ROOT/msg.md" --now 2026-06-01T00:00:00Z --worktree-guard)"; rc=$?
  expect_exit 1 "$rc" "PROBE-004 scope-named worktree" || ok=0
  assert_payload_contains "$out" "E-PLANNING-WORKTREE" "PROBE-004: scope-named worktree not caught: $out" || ok=0

  # CONTROL: an unrelated worktree is NOT this scope's and does not fire.
  new_repo || { log_fail "PROBE-004 control setup failed"; return; }
  (cd "$REPO" && git worktree add -q -b other/thing "$TMP_ROOT/guard-unrelated" >/dev/null 2>&1)
  result_block "$TMP_ROOT/msg.md" "Planning"
  out="$(runcheck --file "$TMP_ROOT/msg.md" --now 2026-06-01T00:00:00Z --worktree-guard)"; rc=$?
  expect_exit 0 "$rc" "PROBE-004 unrelated worktree control" || ok=0
  [[ $ok -eq 1 ]] && log_pass "PROBE-004 (R09) --worktree-guard catches a scope-named tree; an unrelated tree is not this scope's business" \
    || log_fail "PROBE-004 (R09) scope guard"
}

# --- PROBE-005 — both gates are PLANNING-scoped -------------------------------
# Implementation legitimately writes code and legitimately works in a worktree.
# A gate that fired on it would be worse than no gate.
test_005_role_scoping() {
  local out rc ok=1
  new_repo || { log_fail "PROBE-005 fixture setup failed"; return; }
  (cd "$REPO" && git worktree list --porcelain) > "$TMP_ROOT/wt-baseline3.txt"
  (
    cd "$REPO" || exit 1
    echo "implementation edit" >> src/app.mjs
    git worktree add -q -b impl/CHANGE-0113 "$TMP_ROOT/wt-impl-CHANGE-0113" >/dev/null 2>&1
  )
  result_block "$TMP_ROOT/msg.md" "Implementation"
  out="$(runcheck --file "$TMP_ROOT/msg.md" --now 2026-06-01T00:00:00Z --base-ref main --worktree-guard --worktree-baseline "$TMP_ROOT/wt-baseline3.txt")"; rc=$?
  expect_exit 0 "$rc" "PROBE-005 implementation unaffected" || ok=0
  [[ -z "$out" ]] || { log_info "PROBE-005: an Implementation run was gated: $out"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "PROBE-005 both gates are Planning-scoped; Implementation writes code and worktrees freely" \
    || log_fail "PROBE-005 role scoping"
}

# --- PROBE-006 — the flags exist, self-document, and fail LOUD ----------------
test_006_flag_contract() {
  local out rc ok=1
  new_repo || { log_fail "PROBE-006 fixture setup failed"; return; }
  result_block "$TMP_ROOT/msg.md" "Planning"

  # (a) a bad --base-ref must be a loud usage error, never a silent pass.
  out="$(runcheck --file "$TMP_ROOT/msg.md" --now 2026-06-01T00:00:00Z --base-ref no-such-ref 2>&1)"; rc=$?
  expect_exit 1 "$rc" "PROBE-006 bad base-ref" || ok=0
  echo "$out" | grep -qi "base-ref" \
    || { log_info "PROBE-006: a bad --base-ref did not explain itself: $out"; ok=0; }

  # (b) an unreadable --worktree-baseline is a loud usage error too.
  out="$(runcheck --file "$TMP_ROOT/msg.md" --now 2026-06-01T00:00:00Z --worktree-baseline /nonexistent/baseline.txt 2>&1)"; rc=$?
  expect_exit 1 "$rc" "PROBE-006 bad baseline path" || ok=0

  # (c) the usage text names both optional flags.
  out="$(node "$CHECKER" --bogus-flag 2>&1)"; rc=$?
  assert_payload_contains "$out" "--base-ref" "PROBE-006: usage does not name --base-ref: $out" || ok=0
  assert_payload_contains "$out" "--worktree-guard" "PROBE-006: usage does not name --worktree-guard: $out" || ok=0

  # (d) the WIRING TRUTH is written down where an operator will find it: the
  # merge protocol says the flags exist and that step 1 does not pass them.
  grep -qF -- "--base-ref" "$PROTOCOL_DOC" \
    || { log_info "PROBE-006: SUBAGENT_PROTOCOL.md does not document the optional Planning flags"; ok=0; }
  grep -qiE "opt-?in|optional" "$PROTOCOL_DOC" \
    || { log_info "PROBE-006: SUBAGENT_PROTOCOL.md must state the flags are opt-in (honest wiring scope)"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "PROBE-006 flags self-document, fail loud on bad input, and their opt-in wiring is written down" \
    || log_fail "PROBE-006 flag contract"
}

main() {
  echo "=== $TEST_NAME ==="
  check_deps
  test_001_r04_code_write_caught
  test_002_r04_allowed_surface_clean
  test_003_r09_new_worktree_caught
  test_004_r09_scope_guard
  test_005_role_scoping
  test_006_flag_contract

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
