#!/usr/bin/env bash
#
# Test: aai-docs-lock primitive (RFC-0004 / SPEC-0004)
# Verifies the atomic scope-lock CLI (.aai/scripts/docs-lock.mjs) and the
# single-writer protocol/orchestrator/.gitignore wiring against isolated
# fixtures. Implements TEST-001..010 from the frozen spec.
#
# The lock directory is overridable via AAI_LOCK_DIR so the suite never touches
# the real docs/ai/locks/. The script under test is overridable via
# DOCS_LOCK_SCRIPT so the concurrency test can be RED-proofed against a naive
# (non-O_EXCL) stub that double-claims.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-docs-lock"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOCK_SCRIPT="${DOCS_LOCK_SCRIPT:-$PROJECT_ROOT/.aai/scripts/docs-lock.mjs}"
PROTOCOL_DOC="$PROJECT_ROOT/.aai/SUBAGENT_PROTOCOL.md"
ORCH_DOC="$PROJECT_ROOT/.aai/ORCHESTRATION_PARALLEL.prompt.md"
LOCKS_VIEW_DOC="$PROJECT_ROOT/.aai/system/LOCKS.md"

TMP_ROOT=""
LOCKDIR=""

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

# Run the lock CLI against the current isolated LOCKDIR. Never aborts the suite
# on non-zero exit (callers inspect $? deliberately).
runlock() {
  AAI_LOCK_DIR="$LOCKDIR" node "$LOCK_SCRIPT" "$@"
}

# Allocate a fresh, empty lock directory for the next test (per-test isolation).
fresh_lockdir() {
  LOCKDIR="$(mktemp -d "$TMP_ROOT/locks.XXXXXX")"
}

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  [[ -f "$LOCK_SCRIPT" ]] || log_fail "Lock script not found: $LOCK_SCRIPT"
  TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aai-docs-lock-test.XXXXXX")"
  log_pass "Dependencies checked"
}

# --- TEST-001 — CLI surface + usage/exit-2 contract (Spec-AC-01) --------------
test_cli_surface() {
  log_info "TEST-001: no-arg and bogus subcommand exit 2; 4 subcommands recognized..."
  fresh_lockdir
  local rc
  set +e
  runlock >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "no-arg invocation must exit 2 (got $rc)"
  runlock bogus-subcommand >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "bogus subcommand must exit 2 (got $rc)"
  # all four subcommands must be recognized (not exit 2 "unknown subcommand").
  # list/reap take no positional args; acquire/release missing-args is its own
  # usage-2, but the subcommand itself must be known — assert via list/reap=0
  # and that acquire/release usage error names the subcommand, not "unknown".
  runlock list >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "list must be a recognized subcommand (exit 0, got $rc)"
  runlock reap >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "reap must be a recognized subcommand (exit 0, got $rc)"
  local out
  out="$(runlock acquire 2>&1)"; rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "acquire with no args must exit 2 (got $rc)"
  echo "$out" | grep -qiF "unknown subcommand" \
    && log_fail "acquire must be recognized, not reported as unknown subcommand"
  out="$(runlock release 2>&1)"; rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "release with no args must exit 2 (got $rc)"
  echo "$out" | grep -qiF "unknown subcommand" \
    && log_fail "release must be recognized, not reported as unknown subcommand"
  set -e
  log_pass "CLI surface + usage/exit-2 contract correct"
}

# --- TEST-002 — acquire writes a well-formed lock file (Spec-AC-02) -----------
test_acquire_writes_lock() {
  log_info "TEST-002: acquire of a free scope exits 0 and writes a valid lock payload..."
  fresh_lockdir
  local rc
  set +e
  runlock acquire SPEC-0004 orch-A >/dev/null 2>&1; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "acquire of a free scope must exit 0 (got $rc)"
  local lf="$LOCKDIR/SPEC-0004.lock"
  [[ -f "$lf" ]] || log_fail "lock file not created: $lf"
  # validate JSON keys/values with node (no jq dependency)
  node -e '
    const fs = require("fs");
    const l = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const need = ["scope","owner","acquired_utc","ttl_seconds","pid"];
    for (const k of need) if (!(k in l)) { console.error("missing key "+k); process.exit(1); }
    if (l.scope !== "SPEC-0004") { console.error("scope mismatch"); process.exit(1); }
    if (l.owner !== "orch-A") { console.error("owner mismatch"); process.exit(1); }
    if (l.ttl_seconds !== 1800) { console.error("default ttl must be 1800, got "+l.ttl_seconds); process.exit(1); }
    if (typeof l.pid !== "number") { console.error("pid must be a number"); process.exit(1); }
    if (Number.isNaN(Date.parse(l.acquired_utc))) { console.error("acquired_utc not a date"); process.exit(1); }
  ' "$lf" || log_fail "lock payload schema/values incorrect"
  # honour --ttl override
  fresh_lockdir
  set +e
  runlock acquire JOB-1 owner-x --ttl 60 >/dev/null 2>&1
  set -e
  node -e '
    const fs = require("fs");
    const l = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    if (l.ttl_seconds !== 60) { console.error("--ttl override ignored, got "+l.ttl_seconds); process.exit(1); }
  ' "$LOCKDIR/JOB-1.lock" || log_fail "--ttl override not honoured"
  log_pass "acquire writes a well-formed lock with default + override ttl"
}

# --- TEST-003 — CONCURRENCY: exactly one of N acquires wins (Spec-AC-03) ------
# RED-proofed: against a naive non-O_EXCL stub (read-existence-then-create) this
# reliably lets >=2 acquirers succeed, failing the "exactly one exit 0" assert.
test_concurrency_single_winner() {
  log_info "TEST-003: N=20 concurrent acquires of ONE scope -> exactly one exit 0..."
  fresh_lockdir
  local n=20
  local rcdir
  rcdir="$(mktemp -d "$TMP_ROOT/rc.XXXXXX")"
  local i
  for ((i = 0; i < n; i++)); do
    (
      # Disable set -e inside the subshell: a contended acquire exits 3, which
      # would otherwise abort the subshell before its exit code is recorded.
      set +e
      AAI_LOCK_DIR="$LOCKDIR" node "$LOCK_SCRIPT" acquire CONTESTED "owner-$i" >/dev/null 2>&1
      echo "$?" > "$rcdir/$i"
    ) &
  done
  wait
  local zeros threes total
  set +e
  zeros="$(grep -lx 0 "$rcdir"/* 2>/dev/null | wc -l | tr -d ' ')"
  threes="$(grep -lx 3 "$rcdir"/* 2>/dev/null | wc -l | tr -d ' ')"
  total="$(ls -1 "$rcdir" | wc -l | tr -d ' ')"
  set -e
  log_info "  results: $zeros winner(s), $threes contended, $total total"
  [[ "$total" -eq "$n" ]] || log_fail "expected $n results, got $total"
  [[ "$zeros" -eq 1 ]] || log_fail "exactly ONE acquire must exit 0 (got $zeros) — double-claim race"
  [[ "$threes" -eq $((n - 1)) ]] || log_fail "the other $((n - 1)) acquires must exit 3 (got $threes)"
  # exactly one lock file, naming exactly one owner
  local nlocks
  nlocks="$(ls -1 "$LOCKDIR"/*.lock 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$nlocks" -eq 1 ]] || log_fail "exactly one lock file must remain (got $nlocks)"
  node -e '
    const fs = require("fs");
    const l = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    if (typeof l.owner !== "string" || !l.owner.startsWith("owner-")) {
      console.error("lock owner malformed: "+l.owner); process.exit(1);
    }
  ' "$LOCKDIR/CONTESTED.lock" || log_fail "remaining lock must name exactly one valid owner"
  log_pass "exactly one concurrent acquire wins; the rest are contended"
}

# --- TEST-004 — release frees the scope (Spec-AC-04) --------------------------
test_release_frees_scope() {
  log_info "TEST-004: acquire(A)=0; competing acquire(B)=3; release(A)=0; re-acquire(B)=0..."
  fresh_lockdir
  local rc
  set +e
  runlock acquire SCOPE-1 ownerA >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "first acquire must exit 0 (got $rc)"
  runlock acquire SCOPE-1 ownerB >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 3 ]] || log_fail "competing acquire must exit 3 (got $rc)"
  runlock release SCOPE-1 ownerA >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "release by owner must exit 0 (got $rc)"
  runlock acquire SCOPE-1 ownerB >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "re-acquire after release must exit 0 (got $rc)"
  set -e
  log_pass "release frees the scope for a new owner"
}

# --- TEST-005 — ownership guard + idempotent release (Spec-AC-04) -------------
test_release_ownership_guard() {
  log_info "TEST-005: non-owner release exits 4 + lock intact; unheld release idempotent 0..."
  fresh_lockdir
  local rc
  set +e
  runlock acquire SCOPE-2 ownerA >/dev/null 2>&1
  runlock release SCOPE-2 ownerB >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 4 ]] || log_fail "release by a non-owner must exit 4 (got $rc)"
  [[ -f "$LOCKDIR/SCOPE-2.lock" ]] || log_fail "non-owner release must leave the lock intact"
  node -e '
    const fs = require("fs");
    const l = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    if (l.owner !== "ownerA") { console.error("owner changed: "+l.owner); process.exit(1); }
  ' "$LOCKDIR/SCOPE-2.lock" || log_fail "lock owner must stay ownerA after a rejected release"
  # idempotent release of an unheld scope
  runlock release NEVER-HELD ownerA >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "release of an unheld scope must exit 0 (got $rc)"
  set -e
  log_pass "ownership guard rejects non-owners; unheld release is idempotent"
}

# --- TEST-006 — reap reclaims an expired lock (Spec-AC-05) --------------------
test_reap_reclaims_expired() {
  log_info "TEST-006: acquire --ttl 1, sleep 2, reap deletes expired; fresh acquire then 0..."
  fresh_lockdir
  local rc out
  set +e
  runlock acquire EXPIRES soonGone --ttl 1 >/dev/null 2>&1
  sleep 2
  out="$(runlock reap 2>&1)"; rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "reap must exit 0 (got $rc)"
  echo "$out" | grep -qiF "EXPIRES" || log_fail "reap must report the reclaimed scope EXPIRES"
  [[ -f "$LOCKDIR/EXPIRES.lock" ]] && log_fail "reap must delete the expired lock file"
  runlock acquire EXPIRES newOwner >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "acquire after reap must exit 0 (got $rc)"
  set -e
  log_pass "reap reclaims an expired lock; scope re-acquirable"
}

# --- TEST-007 — acquire self-heal AND fresh-not-reaped (Spec-AC-05) -----------
test_selfheal_and_fresh_not_reaped() {
  log_info "TEST-007: (a) expired -> acquire self-heals; (b) fresh -> never reaped, still contended..."
  # (a) self-heal: acquire --ttl 1, sleep 2, acquire SAME scope other owner -> 0
  fresh_lockdir
  local rc
  set +e
  runlock acquire HEAL-ME ownerA --ttl 1 >/dev/null 2>&1
  sleep 2
  runlock acquire HEAL-ME ownerB >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "acquire of an EXPIRED scope must self-heal and exit 0 (got $rc)"
  node -e '
    const fs = require("fs");
    const l = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    if (l.owner !== "ownerB") { console.error("self-heal must reassign owner, got "+l.owner); process.exit(1); }
  ' "$LOCKDIR/HEAL-ME.lock" || log_fail "self-heal must hand the scope to the new owner"
  # (b) fresh-not-reaped: long ttl, reap leaves it, competing acquire still 3
  fresh_lockdir
  runlock acquire FRESH ownerA --ttl 1800 >/dev/null 2>&1
  runlock reap >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "reap must exit 0 even with only fresh locks (got $rc)"
  [[ -f "$LOCKDIR/FRESH.lock" ]] || log_fail "reap must NOT delete a fresh (non-expired) lock"
  runlock acquire FRESH ownerB >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 3 ]] || log_fail "a fresh lock must still contend a competing acquire (got $rc)"
  set -e
  log_pass "expired locks self-heal on acquire; fresh locks are never reaped"
}

# --- TEST-011 — CONCURRENCY on the EXPIRED-RECLAIM path (Spec-AC-03) ----------
# Code-review E1 regression guard: TEST-003 only stresses a FREE scope and never
# enters the self-heal/reclaim branch. Here we pre-seed an EXPIRED lock so every
# concurrent acquirer takes the reclaim path; a blind unconditional unlink-by-path
# lets two winners through (one clobbers the other's fresh lock). The atomic
# rename-steal must still yield exactly ONE winner.
test_concurrency_expired_reclaim_single_winner() {
  log_info "TEST-011: N concurrent acquires over a PRE-EXPIRED lock -> exactly one exit 0..."
  fresh_lockdir
  # Seed an already-expired lock directly (acquired in the past, tiny ttl).
  node -e '
    const fs = require("fs");
    const p = process.argv[1];
    fs.writeFileSync(p, JSON.stringify({
      scope: "RECLAIM",
      owner: "dead-owner",
      acquired_utc: new Date(Date.now() - 3600 * 1000).toISOString(),
      ttl_seconds: 1,
      pid: 999999,
    }));
  ' "$LOCKDIR/RECLAIM.lock"
  local n=30 rcdir i
  rcdir="$(mktemp -d "$TMP_ROOT/rc-reclaim.XXXXXX")"
  for ((i = 0; i < n; i++)); do
    (
      set +e
      AAI_LOCK_DIR="$LOCKDIR" node "$LOCK_SCRIPT" acquire RECLAIM "owner-$i" >/dev/null 2>&1
      echo "$?" > "$rcdir/$i"
    ) &
  done
  wait
  local zeros total
  set +e
  zeros="$(grep -lx 0 "$rcdir"/* 2>/dev/null | wc -l | tr -d ' ')"
  total="$(ls -1 "$rcdir" | wc -l | tr -d ' ')"
  set -e
  log_info "  results: $zeros winner(s) over the reclaim path, $total total"
  [[ "$total" -eq "$n" ]] || log_fail "expected $n results, got $total"
  [[ "$zeros" -eq 1 ]] || log_fail "exactly ONE acquire must win the expired-reclaim race (got $zeros) — double-claim via unconditional unlink"
  local nlocks
  nlocks="$(ls -1 "$LOCKDIR"/*.lock 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$nlocks" -eq 1 ]] || log_fail "exactly one lock file must remain after the reclaim race (got $nlocks)"
  log_pass "expired-reclaim path yields exactly one winner under concurrency"
}

# --- TEST-008 — list view (Spec-AC-06) ---------------------------------------
test_list_view() {
  log_info "TEST-008: list on empty dir prints no-locks marker; after acquires shows both..."
  fresh_lockdir
  local rc out
  set +e
  out="$(runlock list 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "list on empty dir must exit 0 (got $rc)"
  echo "$out" | grep -qiF "no locks" || log_fail "empty list must print a no-locks marker"
  set +e
  runlock acquire ALPHA owner-1 >/dev/null 2>&1
  runlock acquire BETA owner-2 >/dev/null 2>&1
  out="$(runlock list 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "list must exit 0 (got $rc)"
  echo "$out" | grep -qF "ALPHA" || log_fail "list must show scope ALPHA"
  echo "$out" | grep -qF "BETA" || log_fail "list must show scope BETA"
  echo "$out" | grep -qF "owner-1" || log_fail "list must show owner-1"
  echo "$out" | grep -qF "owner-2" || log_fail "list must show owner-2"
  log_pass "list reports held locks and a no-locks marker when empty"
}

# --- TEST-009 — lock dir is gitignored (Spec-AC-07) --------------------------
# This test uses the DEFAULT lock path (docs/ai/locks/) inside an isolated git
# fixture whose .gitignore is copied from the project, to prove the real rule.
test_gitignore() {
  log_info "TEST-009: docs/ai/locks/ is gitignored; lock files never show in porcelain..."
  local gitdir
  gitdir="$(mktemp -d "$TMP_ROOT/git.XXXXXX")"
  (
    cd "$gitdir"
    git init -q
    git config user.email "test@example.com"
    git config user.name "AAI Test"
    mkdir -p docs/ai
    cp "$PROJECT_ROOT/.gitignore" .gitignore
    git add .gitignore && git commit -qm "chore: vendor gitignore" >/dev/null 2>&1
  )
  local rc
  set +e
  # default lock dir (no AAI_LOCK_DIR) => docs/ai/locks under cwd
  ( cd "$gitdir" && node "$LOCK_SCRIPT" acquire DEMO-1 orch-A >/dev/null 2>&1 ); rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "acquire must exit 0 in the git fixture (got $rc)"
  [[ -f "$gitdir/docs/ai/locks/DEMO-1.lock" ]] || log_fail "lock file must be created at the default path"
  ( cd "$gitdir" && git check-ignore docs/ai/locks/DEMO-1.lock >/dev/null 2>&1 ); rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "git check-ignore must match docs/ai/locks/DEMO-1.lock (got $rc)"
  local porcelain
  porcelain="$(cd "$gitdir" && git status --porcelain)"
  set -e
  echo "$porcelain" | grep -qF "docs/ai/locks" \
    && log_fail "lock files must never appear in git status --porcelain"
  log_pass "docs/ai/locks/ is gitignored; lock files invisible to git"
}

# --- TEST-010 — protocol/orchestrator/LOCKS.md wiring (Spec-AC-08) ------------
test_wiring_and_protocol() {
  log_info "TEST-010: single-writer rule + orchestrator wiring + LOCKS.md demotion present..."
  [[ -f "$PROTOCOL_DOC" ]] || log_fail "missing $PROTOCOL_DOC"
  [[ -f "$ORCH_DOC" ]] || log_fail "missing $ORCH_DOC"
  [[ -f "$LOCKS_VIEW_DOC" ]] || log_fail "missing $LOCKS_VIEW_DOC"

  # SUBAGENT_PROTOCOL: hard rule "MUST NOT write ... STATE.yaml" + sole writer
  grep -qiE "MUST NOT (write|modify).*STATE\.yaml" "$PROTOCOL_DOC" \
    || log_fail "SUBAGENT_PROTOCOL must carry the hard 'MUST NOT write ... STATE.yaml' rule"
  grep -qiE "sole.*(STATE )?writer|only .*STATE.* writer|sole writer" "$PROTOCOL_DOC" \
    || log_fail "SUBAGENT_PROTOCOL must name the orchestrator as the sole STATE writer"
  # rationalization-table row referencing the no-STATE-write rule
  grep -qiF "STATE.yaml" "$PROTOCOL_DOC" \
    || log_fail "SUBAGENT_PROTOCOL must reference STATE.yaml in its rule/table"

  # ORCHESTRATION_PARALLEL: docs-lock acquire/release wiring + degrade fallback
  grep -qF "docs-lock" "$ORCH_DOC" \
    || log_fail "ORCHESTRATION_PARALLEL must reference docs-lock"
  grep -qiF "acquire" "$ORCH_DOC" \
    || log_fail "ORCHESTRATION_PARALLEL must reference acquire-before-dispatch"
  grep -qiF "release" "$ORCH_DOC" \
    || log_fail "ORCHESTRATION_PARALLEL must reference release-after-merge"
  grep -qiE "K=1|K = 1" "$ORCH_DOC" \
    || log_fail "ORCHESTRATION_PARALLEL must state the degrade fallback to K=1"

  # LOCKS.md demoted to a human-readable view
  grep -qiE "human-readable view|not the authoritative|view, not" "$LOCKS_VIEW_DOC" \
    || log_fail "LOCKS.md must state it is a human-readable view, not authoritative"
  grep -qF "docs-lock" "$LOCKS_VIEW_DOC" \
    || log_fail "LOCKS.md must point at docs-lock as the authoritative mechanism"

  log_pass "single-writer rule, orchestrator wiring, and LOCKS.md demotion all present"
}

main() {
  echo "Testing $TEST_NAME (atomic scope-lock CLI + single-writer wiring)"
  check_deps
  test_cli_surface
  test_acquire_writes_lock
  test_concurrency_single_winner
  test_release_frees_scope
  test_release_ownership_guard
  test_reap_reclaims_expired
  test_selfheal_and_fresh_not_reaped
  test_concurrency_expired_reclaim_single_winner
  test_list_view
  test_gitignore
  test_wiring_and_protocol
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

# Allow sourcing for isolated per-test execution (TDD RED/GREEN evidence);
# run the full suite only when invoked directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
