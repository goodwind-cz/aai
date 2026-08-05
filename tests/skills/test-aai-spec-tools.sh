#!/usr/bin/env bash
#
# Test: aai-spec-tools — the two deterministic frozen-spec editors
# (CHANGE-0120 cheap-ticks, AC-002 + AC-003).
#
#   .aai/scripts/spec-scope-edit.mjs — orchestrator-level include/exclude of a
#     path in the frozen spec's review-scope list. REFUSES any path the ride's
#     own diff touched (that is a content decision -> Planning). Replaces a
#     full re-Planning dispatch for user side-change exclusions.
#   .aai/scripts/spec-freeze.mjs — ATOMIC freeze: frontmatter
#     `status: implementing` and the `SPEC-FROZEN: true` body marker are
#     written together or not at all, so the half-frozen paperwork state that
#     bounced a live ride back to Planning cannot be produced.
#
# Every arm runs in a mktemp scratch GIT repo; the real repo is only READ (the
# two scripts under test). bash 3.2 compatible.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -uo pipefail

TEST_NAME="aai-spec-tools"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCOPE_EDIT="$PROJECT_ROOT/.aai/scripts/spec-scope-edit.mjs"
FREEZE="$PROJECT_ROOT/.aai/scripts/spec-freeze.mjs"

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
  [[ -f "$SCOPE_EDIT" ]] || log_info "NOTE: $SCOPE_EDIT missing (expected only on the pre-change RED tree)"
  [[ -f "$FREEZE" ]] || log_info "NOTE: $FREEZE missing (expected only on the pre-change RED tree)"
  TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aai-spec-tools-test.XXXXXX")"
}

expect_exit() {
  local want="$1" got="$2" label="$3"
  if [[ "$got" -ne "$want" ]]; then
    log_info "$label: exit $got (want $want)"
    return 1
  fi
  return 0
}

# spec_body <frontmatter-status> <marker true|false> <scope-line>
spec_body() {
  local status="$1" marker="$2" scope="$3"
  cat <<EOF
---
id: spec-fixture-tools
type: spec
number: 1
status: $status
links:
  pr: []
---

# Implementation Spec — fixture
EOF
  [[ "$marker" == "true" ]] && printf '\nSPEC-FROZEN: true\n'
  cat <<EOF

## Implementation strategy
- Strategy: direct
- Rationale: fixture

## Isolation and review
- Worktree recommendation: optional
- User decision: inline
- Base ref: main
- Inline review scope: $scope

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence   | Review-By | Notes |
|------------|-------------|--------|------------|-----------|-------|
| Spec-AC-01 | first       | done   | tests/a.sh | —         | —     |
EOF
}

# new_repo — a scratch git repo with ONE committed baseline, a `main` base ref,
# and a ride commit touching src/touched.mjs. $REPO / $SPEC are exported.
# The frozen spec's review scope lists BOTH the ride-touched file and an
# untouched user side-change (requirements.txt), the live incident's shape.
new_repo() {
  REPO="$(mktemp -d "$TMP_ROOT/repo.XXXXXX")"
  mkdir -p "$REPO/docs/specs" "$REPO/docs/ai" "$REPO/src"
  (
    cd "$REPO" || exit 1
    git init -q -b main .
    git config user.email "fixture@example.com"
    git config user.name "fixture"
    echo "baseline" > src/touched.mjs
    echo "requests" > requirements.txt
    echo "* text=auto" > .gitattributes
    git add -A && git commit -qm baseline
    # The ride lives on its OWN branch off `main`, so `main...HEAD` is a real
    # non-empty diff (a ride committed onto the base ref itself would make the
    # three-dot range empty and silently disarm the refusal this suite asserts).
    git checkout -q -b ride
    # the ride's own commit: ONLY src/touched.mjs changes
    echo "ride edit" >> src/touched.mjs
    git add -A && git commit -qm ride
  ) || return 1
  SPEC="$REPO/docs/specs/SPEC-0001-fx.md"
  spec_body implementing true \
    "src/touched.mjs, requirements.txt, tests/skills/test-x.sh" > "$SPEC"
}

runscope() { (cd "$REPO" && node "$SCOPE_EDIT" "$@"); }
runfreeze() { (cd "$REPO" && node "$FREEZE" "$@"); }

# scope_list — echo the current review-scope line(s), whitespace-collapsed.
scope_list() {
  node -e '
    const fs = require("fs");
    const c = fs.readFileSync(process.argv[1], "utf8").replace(/\r\n?/g, "\n");
    const m = c.match(/^-\s*Inline review scope[^\n:]*:([\s\S]*?)(?=\n-\s|\n\n|\n##\s)/m);
    process.stdout.write(m ? m[1].replace(/\s+/g, " ").trim() : "(none)");
  ' "$SPEC"
}

# --- AC-002 TEST-001 — excludes an UNTOUCHED path -----------------------------
test_scope_001_exclude_untouched() {
  local out rc ok=1
  new_repo || { log_fail "TEST-001(scope) fixture setup failed"; return; }
  out="$(runscope --spec docs/specs/SPEC-0001-fx.md --exclude requirements.txt --base-ref main 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-001(scope) exclude untouched" || ok=0
  local list
  list="$(scope_list)"
  echo "$list" | grep -q "requirements.txt" \
    && { log_info "TEST-001(scope): requirements.txt still in scope: $list"; ok=0; }
  echo "$list" | grep -q "src/touched.mjs" \
    || { log_info "TEST-001(scope): the edit dropped an unrelated entry: $list"; ok=0; }
  echo "$list" | grep -q "tests/skills/test-x.sh" \
    || { log_info "TEST-001(scope): the edit dropped an unrelated entry: $list"; ok=0; }
  # ONLY the review-scope section may change: the AC table is byte-identical.
  grep -q "^| Spec-AC-01 | first       | done   | tests/a.sh | —         | —     |$" "$SPEC" \
    || { log_info "TEST-001(scope): the AC table was modified"; ok=0; }
  grep -q "^SPEC-FROZEN: true$" "$SPEC" \
    || { log_info "TEST-001(scope): the freeze marker was modified"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-001(scope) excludes an untouched path, edits ONLY the review-scope list" \
    || log_fail "TEST-001(scope) exclude untouched"
}

# --- AC-002 TEST-002 — REFUSES a path the ride's diff touched -----------------
test_scope_002_refuse_diff_path() {
  local out rc ok=1 before
  new_repo || { log_fail "TEST-002(scope) fixture setup failed"; return; }
  before="$(cksum "$SPEC")"
  out="$(runscope --spec docs/specs/SPEC-0001-fx.md --exclude src/touched.mjs --base-ref main 2>&1)"; rc=$?
  expect_exit 3 "$rc" "TEST-002(scope) refuse diff path" || ok=0
  echo "$out" | grep -qi "refus" \
    || { log_info "TEST-002(scope): refusal not named in the output: $out"; ok=0; }
  [[ "$before" == "$(cksum "$SPEC")" ]] \
    || { log_info "TEST-002(scope): a REFUSED edit still wrote the spec"; ok=0; }
  [[ -f "$REPO/docs/ai/EVENTS.jsonl" ]] \
    && { log_info "TEST-002(scope): a REFUSED edit still emitted an audit event"; ok=0; }

  # --include is refused by the SAME rule: this tool only ever moves paths the
  # ride did not touch. A ride-touched path is a content decision -> Planning.
  out="$(runscope --spec docs/specs/SPEC-0001-fx.md --include src/touched.mjs --base-ref main 2>&1)"; rc=$?
  expect_exit 3 "$rc" "TEST-002(scope) refuse include of a diff path" || ok=0

  # UNCOMMITTED work counts as the ride's diff too (fail-closed).
  echo "dirty" >> "$REPO/requirements.txt"
  out="$(runscope --spec docs/specs/SPEC-0001-fx.md --exclude requirements.txt --base-ref main 2>&1)"; rc=$?
  expect_exit 3 "$rc" "TEST-002(scope) refuse uncommitted path" || ok=0
  [[ $ok -eq 1 ]] && log_pass "TEST-002(scope) refuses any path in the ride diff (committed or uncommitted), writes nothing" \
    || log_fail "TEST-002(scope) refuse diff path"
}

# --- AC-002 TEST-003 — audited via an EVENTS line -----------------------------
test_scope_003_events_audit() {
  local rc ok=1
  new_repo || { log_fail "TEST-003(scope) fixture setup failed"; return; }
  runscope --spec docs/specs/SPEC-0001-fx.md --exclude requirements.txt --base-ref main >/dev/null 2>&1; rc=$?
  expect_exit 0 "$rc" "TEST-003(scope) applied" || ok=0
  [[ -f "$REPO/docs/ai/EVENTS.jsonl" ]] \
    || { log_info "TEST-003(scope): no EVENTS.jsonl written"; ok=0; }
  node -e '
    const fs = require("fs");
    const e = JSON.parse(fs.readFileSync(process.argv[1], "utf8").trim().split("\n").pop());
    if (e.event !== "spec_scope_edited") throw new Error("event type: " + e.event);
    if (e.payload.op !== "exclude") throw new Error("op: " + JSON.stringify(e.payload));
    if (e.payload.target !== "requirements.txt") throw new Error("target: " + JSON.stringify(e.payload));
    if (e.v !== 1 || !e.ts || !e.actor || !e.ref) throw new Error("schema fields missing: " + JSON.stringify(e));
  ' "$REPO/docs/ai/EVENTS.jsonl" 2>/dev/null || { log_info "TEST-003(scope): audit line shape wrong: $(cat "$REPO/docs/ai/EVENTS.jsonl" 2>/dev/null)"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-003(scope) an applied edit appends a spec_scope_edited audit line" \
    || log_fail "TEST-003(scope) EVENTS audit"
}

# --- AC-002 TEST-004 — idempotent + include round-trip ------------------------
test_scope_004_idempotent() {
  local rc ok=1 after1 after2 n
  new_repo || { log_fail "TEST-004(scope) fixture setup failed"; return; }
  runscope --spec docs/specs/SPEC-0001-fx.md --exclude requirements.txt --base-ref main >/dev/null 2>&1
  after1="$(cksum "$SPEC")"
  runscope --spec docs/specs/SPEC-0001-fx.md --exclude requirements.txt --base-ref main >/dev/null 2>&1; rc=$?
  after2="$(cksum "$SPEC")"
  expect_exit 0 "$rc" "TEST-004(scope) re-exclude is a no-op success" || ok=0
  [[ "$after1" == "$after2" ]] \
    || { log_info "TEST-004(scope): a second identical exclude changed the file"; ok=0; }
  n="$(grep -c '"event":"spec_scope_edited"' "$REPO/docs/ai/EVENTS.jsonl" 2>/dev/null || true)"
  [[ "$n" == 1 ]] \
    || { log_info "TEST-004(scope): a no-op re-run appended another audit line (got $n)"; ok=0; }

  # include round-trip: re-adding the untouched path restores it.
  runscope --spec docs/specs/SPEC-0001-fx.md --include requirements.txt --base-ref main >/dev/null 2>&1; rc=$?
  expect_exit 0 "$rc" "TEST-004(scope) include" || ok=0
  scope_list | grep -q "requirements.txt" \
    || { log_info "TEST-004(scope): include did not restore the path: $(scope_list)"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-004(scope) idempotent (byte-identical, no duplicate audit line); include round-trips" \
    || log_fail "TEST-004(scope) idempotence"
}

# --- AC-002 TEST-005 — fail-closed structure + usage contract -----------------
test_scope_005_fail_closed() {
  local out rc ok=1
  new_repo || { log_fail "TEST-005(scope) fixture setup failed"; return; }
  # no review-scope section at all -> structural refusal, no write
  printf -- '---\nid: x\ntype: spec\nstatus: implementing\n---\n\n# no scope section\n' \
    > "$REPO/docs/specs/SPEC-0002-noscope.md"
  out="$(runscope --spec docs/specs/SPEC-0002-noscope.md --exclude requirements.txt --base-ref main 2>&1)"; rc=$?
  expect_exit 4 "$rc" "TEST-005(scope) missing review-scope section" || ok=0

  # unreadable spec -> structural refusal
  out="$(runscope --spec docs/specs/NOPE.md --exclude requirements.txt --base-ref main 2>&1)"; rc=$?
  expect_exit 4 "$rc" "TEST-005(scope) unreadable spec" || ok=0

  # a bad base ref makes the diff probe fail -> REFUSE, never fall open
  out="$(runscope --spec docs/specs/SPEC-0001-fx.md --exclude requirements.txt --base-ref no-such-ref 2>&1)"; rc=$?
  expect_exit 4 "$rc" "TEST-005(scope) unusable base ref" || ok=0

  # usage errors
  out="$(runscope --spec docs/specs/SPEC-0001-fx.md 2>&1)"; rc=$?
  expect_exit 2 "$rc" "TEST-005(scope) neither --include nor --exclude" || ok=0
  out="$(runscope --spec docs/specs/SPEC-0001-fx.md --include a --exclude b 2>&1)"; rc=$?
  expect_exit 2 "$rc" "TEST-005(scope) both --include and --exclude" || ok=0
  out="$(runscope --bogus 2>&1)"; rc=$?
  expect_exit 2 "$rc" "TEST-005(scope) unknown flag" || ok=0

  # the exit contract is DOCUMENTED in --help
  out="$(runscope --help 2>&1)"; rc=$?
  for code in 0 2 3 4; do
    echo "$out" | grep -qE "^\s*$code " || { log_info "TEST-005(scope): --help does not document exit $code: $out"; ok=0; }
  done
  [[ $ok -eq 1 ]] && log_pass "TEST-005(scope) fail-closed on structure/probe failure; usage contract + documented exit codes" \
    || log_fail "TEST-005(scope) fail-closed"
}

# --- AC-003 TEST-006 — atomic freeze ------------------------------------------
test_freeze_001_atomic() {
  local out rc ok=1
  new_repo || { log_fail "TEST-006(freeze) fixture setup failed"; return; }
  # start from the DRAFT, unfrozen state
  spec_body draft false "src/touched.mjs" > "$SPEC"
  out="$(runfreeze --path docs/specs/SPEC-0001-fx.md 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-006(freeze) freeze" || ok=0
  grep -q "^status: implementing$" "$SPEC" \
    || { log_info "TEST-006(freeze): frontmatter status not flipped: $(head -8 "$SPEC")"; ok=0; }
  grep -q "^SPEC-FROZEN: true$" "$SPEC" \
    || { log_info "TEST-006(freeze): marker not written: $(head -14 "$SPEC")"; ok=0; }
  # the freeze is a doc_lifecycle transition on the ledger
  node -e '
    const fs = require("fs");
    const e = JSON.parse(fs.readFileSync(process.argv[1], "utf8").trim().split("\n").pop());
    if (e.event !== "doc_lifecycle") throw new Error("event: " + e.event);
    if (e.payload.from !== "draft" || e.payload.to !== "implementing") throw new Error("payload: " + JSON.stringify(e.payload));
  ' "$REPO/docs/ai/EVENTS.jsonl" 2>/dev/null \
    || { log_info "TEST-006(freeze): no draft->implementing doc_lifecycle event"; ok=0; }

  # idempotent: a second freeze is a no-op success, byte-identical, no event
  local before n
  before="$(cksum "$SPEC")"
  out="$(runfreeze --path docs/specs/SPEC-0001-fx.md 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-006(freeze) idempotent re-freeze" || ok=0
  [[ "$before" == "$(cksum "$SPEC")" ]] \
    || { log_info "TEST-006(freeze): a re-freeze rewrote the file"; ok=0; }
  n="$(grep -c '"event":"doc_lifecycle"' "$REPO/docs/ai/EVENTS.jsonl" || true)"
  [[ "$n" == 1 ]] || { log_info "TEST-006(freeze): a no-op re-freeze appended another event (got $n)"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-006(freeze) status + marker written together; idempotent; audited" \
    || log_fail "TEST-006(freeze) atomic freeze"
}

# --- AC-003 TEST-007 — the freeze tool cannot PRODUCE a half-state ------------
test_freeze_002_half_state_refusal() {
  local out rc ok=1 before
  new_repo || { log_fail "TEST-007(freeze) fixture setup failed"; return; }

  # (a) no frontmatter at all -> refuse, write nothing (a marker-only write
  # would BE the half-state).
  printf '# no frontmatter\n\n## Isolation and review\n' > "$REPO/docs/specs/SPEC-0003-nofm.md"
  before="$(cksum "$REPO/docs/specs/SPEC-0003-nofm.md")"
  out="$(runfreeze --path docs/specs/SPEC-0003-nofm.md 2>&1)"; rc=$?
  expect_exit 3 "$rc" "TEST-007(freeze) no frontmatter" || ok=0
  [[ "$before" == "$(cksum "$REPO/docs/specs/SPEC-0003-nofm.md")" ]] \
    || { log_info "TEST-007(freeze): refused doc was still written"; ok=0; }

  # (b) frontmatter without a `status:` key -> refuse (cannot set both halves).
  printf -- '---\nid: x\ntype: spec\n---\n\n# no status key\n' > "$REPO/docs/specs/SPEC-0004-nostatus.md"
  out="$(runfreeze --path docs/specs/SPEC-0004-nostatus.md 2>&1)"; rc=$?
  expect_exit 3 "$rc" "TEST-007(freeze) no status key" || ok=0

  # (c) a TERMINAL status is never re-frozen.
  spec_body done true "src/touched.mjs" > "$REPO/docs/specs/SPEC-0005-done.md"
  before="$(cksum "$REPO/docs/specs/SPEC-0005-done.md")"
  out="$(runfreeze --path docs/specs/SPEC-0005-done.md 2>&1)"; rc=$?
  expect_exit 3 "$rc" "TEST-007(freeze) terminal status" || ok=0
  [[ "$before" == "$(cksum "$REPO/docs/specs/SPEC-0005-done.md")" ]] \
    || { log_info "TEST-007(freeze): a done spec was rewritten"; ok=0; }

  # (d) usage + documented exit contract
  out="$(runfreeze 2>&1)"; rc=$?
  expect_exit 2 "$rc" "TEST-007(freeze) missing --path" || ok=0
  out="$(runfreeze --help 2>&1)"; rc=$?
  for code in 0 2 3; do
    echo "$out" | grep -qE "^\s*$code " || { log_info "TEST-007(freeze): --help does not document exit $code: $out"; ok=0; }
  done
  [[ $ok -eq 1 ]] && log_pass "TEST-007(freeze) refuses every half-state it cannot write atomically; documented exits" \
    || log_fail "TEST-007(freeze) half-state refusal"
}

# --- AC-003 TEST-008 — freeze REPAIRS an existing half-frozen doc -------------
# The half-frozen state spec-lint flags is exactly what this tool resolves: a
# marker-without-status doc becomes fully frozen in ONE write, and spec-lint
# goes from finding to clean.
test_freeze_003_repairs_half_frozen() {
  local out rc ok=1
  new_repo || { log_fail "TEST-008(freeze) fixture setup failed"; return; }
  spec_body draft true "src/touched.mjs" > "$SPEC"
  out="$(cd "$REPO" && node "$PROJECT_ROOT/.aai/scripts/spec-lint.mjs" --path docs/specs/SPEC-0001-fx.md 2>&1)"; rc=$?
  expect_exit 1 "$rc" "TEST-008(freeze) half-frozen lints dirty first" || ok=0
  echo "$out" | grep -q "half-frozen" \
    || { log_info "TEST-008(freeze): the half-frozen fixture was not flagged: $out"; ok=0; }

  out="$(runfreeze --path docs/specs/SPEC-0001-fx.md 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-008(freeze) repair" || ok=0
  out="$(cd "$REPO" && node "$PROJECT_ROOT/.aai/scripts/spec-lint.mjs" --path docs/specs/SPEC-0001-fx.md 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-008(freeze) clean after repair" || ok=0
  echo "$out" | grep -q "half-frozen" \
    && { log_info "TEST-008(freeze): still half-frozen after the repair: $out"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-008(freeze) repairs a half-frozen doc in one write; spec-lint goes finding -> clean" \
    || log_fail "TEST-008(freeze) half-frozen repair"
}

main() {
  echo "=== $TEST_NAME ==="
  check_deps
  test_scope_001_exclude_untouched
  test_scope_002_refuse_diff_path
  test_scope_003_events_audit
  test_scope_004_idempotent
  test_scope_005_fail_closed
  test_freeze_001_atomic
  test_freeze_002_half_state_refusal
  test_freeze_003_repairs_half_frozen

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
