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

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | unit | tests/a.sh           | first       | green  |
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
    git -c init.defaultBranch=main init -q .
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

# --- AC-003 TEST-009 — freeze a spec with NO H1 ------------------------------
# The real corpus shape (SPEC-0100/0101/0102 and every doc-generator spec carry
# frontmatter and go straight to `## Links` — no `# ` title). The marker then
# goes after the frontmatter, and its offset MUST be re-derived from the
# already-status-rewritten document: reusing the pre-rewrite match index splices
# the marker INSIDE the frontmatter and pushes the bytes it overran out behind
# it. The signature of that bug is `status: implement` + `SPEC-FROZEN: trueing`.
test_freeze_004_no_h1() {
  local out rc ok=1 spec
  new_repo || { log_fail "TEST-009(freeze) fixture setup failed"; return; }
  spec="$REPO/docs/specs/SPEC-0100-noh1.md"

  # (a) the corpus shape: a long frontmatter whose LAST value is the byte range
  # a stale offset would truncate.
  cat > "$spec" <<'EOF'
---
id: spec-no-h1
type: spec
number: 100
status: draft
links:
  pr:
    - 178
  commits:
    - 8e167599068a3ce15c02cae2bd7d3175200b754e
---

## Links
- Requirement: docs/issues/CHANGE-0079-fx.md

## Implementation strategy
- Strategy: direct
- Rationale: fixture

## Isolation and review
- Inline review scope: src/touched.mjs
EOF
  cp "$spec" "$spec.orig"
  out="$(runfreeze --path docs/specs/SPEC-0100-noh1.md --no-event 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-009(freeze) no-H1 freeze" || ok=0

  # The commit SHA is the canary: a stale-offset splice truncates it.
  grep -q '^    - 8e167599068a3ce15c02cae2bd7d3175200b754e$' "$spec" \
    || { log_info "TEST-009(freeze): frontmatter content was TRUNCATED: $(sed -n '1,16p' "$spec")"; ok=0; }
  # The two corruption signatures must not exist anywhere in the result.
  grep -q 'SPEC-FROZEN: trueing' "$spec" \
    && { log_info "TEST-009(freeze): the marker was spliced INSIDE the frontmatter"; ok=0; }
  grep -q '^status: implement$' "$spec" \
    && { log_info "TEST-009(freeze): the status line was truncated to 'implement'"; ok=0; }
  grep -q '^status: implementing$' "$spec" \
    || { log_info "TEST-009(freeze): status not flipped: $(sed -n '1,12p' "$spec")"; ok=0; }
  # The marker lives in the BODY, after the closing `---`.
  node -e '
    const fs = require("fs");
    const c = fs.readFileSync(process.argv[1], "utf8");
    const fm = c.match(/^---\n([\s\S]*?)\n---/);
    if (!fm) throw new Error("frontmatter no longer parses");
    if (/^SPEC-FROZEN:/m.test(fm[1])) throw new Error("marker INSIDE frontmatter");
    const body = c.slice(fm.index + fm[0].length);
    const n = (body.match(/^SPEC-FROZEN:[ \t]*\S*[ \t]*$/gm) || []);
    if (n.length !== 1) throw new Error("body markers: " + n.length);
    if (n[0].trim() !== "SPEC-FROZEN: true") throw new Error("marker value: " + n[0]);
  ' "$spec" 2>&1 | grep -q . \
    && { log_info "TEST-009(freeze): post-freeze shape wrong: $(node -e 'const fs=require("fs");process.stdout.write(fs.readFileSync(process.argv[1],"utf8").slice(0,400))' "$spec")"; ok=0; }
  # BYTE-CORRECT: exactly two changes vs the original — the status line and the
  # inserted marker (plus its blank line). Nothing else moved.
  local dl
  dl="$(diff "$spec.orig" "$spec" | grep -c '^[<>]' || true)"
  [[ "$dl" == 4 ]] \
    || { log_info "TEST-009(freeze): expected exactly 4 diff lines (status flip + marker + blank), got $dl: $(diff "$spec.orig" "$spec")"; ok=0; }

  # (b) the MINIMAL shape that produced `status: implement` + `trueing`.
  printf -- '---\nid: x\ntype: spec\nstatus: draft\n---\n\n## Summary\nbody text\n\n## Implementation strategy\n- Strategy: direct\n' \
    > "$REPO/docs/specs/SPEC-0101-min.md"
  out="$(runfreeze --path docs/specs/SPEC-0101-min.md --no-event 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-009(freeze) minimal no-H1" || ok=0
  local want
  want="$(printf -- '---\nid: x\ntype: spec\nstatus: implementing\n---\n\nSPEC-FROZEN: true\n\n## Summary\nbody text\n\n## Implementation strategy\n- Strategy: direct\n')"
  [[ "$(cat "$REPO/docs/specs/SPEC-0101-min.md")" == "$want" ]] \
    || { log_info "TEST-009(freeze): minimal output not byte-correct: $(cat "$REPO/docs/specs/SPEC-0101-min.md")"; ok=0; }
  # idempotent on the no-H1 shape too
  local before
  before="$(cksum "$REPO/docs/specs/SPEC-0101-min.md")"
  runfreeze --path docs/specs/SPEC-0101-min.md --no-event >/dev/null 2>&1; rc=$?
  expect_exit 0 "$rc" "TEST-009(freeze) no-H1 re-freeze" || ok=0
  [[ "$before" == "$(cksum "$REPO/docs/specs/SPEC-0101-min.md")" ]] \
    || { log_info "TEST-009(freeze): a no-H1 re-freeze rewrote the file"; ok=0; }

  # (c) POST-TRANSFORM ASSERTION: a doc the transform cannot leave in a provably
  # frozen shape (two SPEC-FROZEN lines) exits 1 with NOTHING written.
  printf -- '---\nid: y\ntype: spec\nstatus: draft\n---\n\n# T\n\nSPEC-FROZEN: false\n\n## X\nSPEC-FROZEN: false\n' \
    > "$REPO/docs/specs/SPEC-0102-dual.md"
  before="$(cksum "$REPO/docs/specs/SPEC-0102-dual.md")"
  out="$(runfreeze --path docs/specs/SPEC-0102-dual.md --no-event 2>&1)"; rc=$?
  expect_exit 1 "$rc" "TEST-009(freeze) post-transform assertion" || ok=0
  echo "$out" | grep -qi "post-transform assertion" \
    || { log_info "TEST-009(freeze): the assertion did not name itself: $out"; ok=0; }
  [[ "$before" == "$(cksum "$REPO/docs/specs/SPEC-0102-dual.md")" ]] \
    || { log_info "TEST-009(freeze): a failed assertion still wrote the file"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-009(freeze) no-H1 specs freeze byte-correctly (no truncation, marker outside frontmatter); a failed post-transform assertion exits 1 writing nothing" \
    || log_fail "TEST-009(freeze) no-H1 freeze"
}

# --- AC-002 TEST-010 — path SPELLING cannot launder a ride-touched path -------
# The diff refusal compared raw strings, so './committed.js' was a different
# path from 'committed.js' and walked straight past the gate.
test_scope_006_path_normalization() {
  local out rc ok=1 spelling
  new_repo || { log_fail "TEST-010(scope) fixture setup failed"; return; }

  # src/touched.mjs IS in the ride diff. Every spelling of it must be refused.
  for spelling in './src/touched.mjs' 'src/../src/touched.mjs' './/src/touched.mjs' 'src/./touched.mjs'; do
    out="$(runscope --spec docs/specs/SPEC-0001-fx.md --exclude "$spelling" --base-ref main 2>&1)"; rc=$?
    expect_exit 3 "$rc" "TEST-010(scope) exclude $spelling" || ok=0
  done
  # ABSOLUTE spelling of the same file
  out="$(runscope --spec docs/specs/SPEC-0001-fx.md --exclude "$REPO/src/touched.mjs" --base-ref main 2>&1)"; rc=$?
  expect_exit 3 "$rc" "TEST-010(scope) exclude absolute" || ok=0

  # --include is the sharper hole: it WROTE the laundered spelling into the
  # review scope while the plain spelling was refused.
  local before
  before="$(cksum "$SPEC")"
  out="$(runscope --spec docs/specs/SPEC-0001-fx.md --include './src/touched.mjs' --base-ref main 2>&1)"; rc=$?
  expect_exit 3 "$rc" "TEST-010(scope) include laundered spelling" || ok=0
  [[ "$before" == "$(cksum "$SPEC")" ]] \
    || { log_info "TEST-010(scope): a laundered --include still wrote the spec"; ok=0; }

  # CONTROL: an UNTOUCHED path still applies, and a laundered spelling of it
  # resolves to the same entry (no duplicate, no './' prefix in the file).
  out="$(runscope --spec docs/specs/SPEC-0001-fx.md --exclude './requirements.txt' --base-ref main 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-010(scope) untouched laundered spelling applies" || ok=0
  scope_list | grep -q "requirements.txt" \
    && { log_info "TEST-010(scope): './requirements.txt' did not match 'requirements.txt': $(scope_list)"; ok=0; }
  grep -q '\./' "$SPEC" \
    && { log_info "TEST-010(scope): a laundered spelling leaked into the spec: $(scope_list)"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-010(scope) './x', 'a/../x', './/x' and absolute spellings all resolve to one path — none launders a ride-touched file past the refusal" \
    || log_fail "TEST-010(scope) path normalization"
}

# --- AC-002 TEST-011 — the NESTED and BACKTICKED corpus shapes ----------------
# 30 corpus specs write the scope as an indented child list and 24 backtick
# their entries. Both parsed as EMPTY: --exclude exited 0 "already out of scope"
# without editing or auditing, and --include wrote onto the LABEL line and left
# the child list dangling. Fixtures mirror SPEC-0026 (nested) and SPEC-0074
# (backticked).
test_scope_007_nested_and_backticked() {
  local out rc ok=1 nested btick
  new_repo || { log_fail "TEST-011(scope) fixture setup failed"; return; }
  nested="$REPO/docs/specs/SPEC-0026-nested.md"
  btick="$REPO/docs/specs/SPEC-0074-btick.md"

  write_nested() {
    cat > "$nested" <<'EOF'
---
id: spec-nested
type: spec
status: implementing
---

# Nested fixture

SPEC-FROZEN: true

## Isolation and review
- Worktree recommendation: optional
- User decision: inline
- Base ref: main
- Inline review scope (explicit paths):
  - .aai/templates/BRIEF_TEMPLATE.md (new)
  - .aai/PLANNING.prompt.md
  - requirements.txt
  - tests/skills/test-aai-hygiene-pack.sh

## Design decisions
EOF
  }
  write_nested
  cat > "$btick" <<'EOF'
---
id: spec-btick
type: spec
status: implementing
---

# Backticked fixture

SPEC-FROZEN: true

## Isolation and review
- Inline review scope: `requirements.txt`,
  `tests/skills/test-aai-branch-guard.sh`

## Companion obligations
EOF

  # (a) NESTED --exclude actually edits, and is AUDITED.
  out="$(runscope --spec docs/specs/SPEC-0026-nested.md --exclude requirements.txt --base-ref main 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-011(scope) nested exclude" || ok=0
  grep -q '^  - requirements.txt$' "$nested" \
    && { log_info "TEST-011(scope): nested exclude did not remove the child: $(sed -n '15,21p' "$nested")"; ok=0; }
  grep -q '^  - .aai/PLANNING.prompt.md$' "$nested" \
    || { log_info "TEST-011(scope): nested exclude dropped a sibling: $(sed -n '15,21p' "$nested")"; ok=0; }
  # the trailing `(new)` annotation survives
  grep -q '^  - .aai/templates/BRIEF_TEMPLATE.md (new)$' "$nested" \
    || { log_info "TEST-011(scope): the entry annotation was lost: $(sed -n '15,21p' "$nested")"; ok=0; }
  # the LABEL line is untouched — never written onto
  grep -q '^- Inline review scope (explicit paths):$' "$nested" \
    || { log_info "TEST-011(scope): the label line was corrupted: $(sed -n '15,16p' "$nested")"; ok=0; }
  grep -q '"event":"spec_scope_edited"' "$REPO/docs/ai/EVENTS.jsonl" 2>/dev/null \
    || { log_info "TEST-011(scope): a nested edit was not audited"; ok=0; }

  # (b) BACKTICKED --exclude matches the bare path and PRESERVES the spelling of
  # the entries it keeps.
  out="$(runscope --spec docs/specs/SPEC-0074-btick.md --exclude requirements.txt --base-ref main 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-011(scope) backticked exclude" || ok=0
  grep -q 'requirements.txt' "$btick" \
    && { log_info "TEST-011(scope): backticked exclude did not remove the entry: $(grep -A2 'review scope' "$btick")"; ok=0; }
  grep -q '`tests/skills/test-aai-branch-guard.sh`' "$btick" \
    || { log_info "TEST-011(scope): the surviving entry lost its backticks: $(grep -A2 'review scope' "$btick")"; ok=0; }

  # (c) NESTED --include appends a CHILD, never text on the label line.
  write_nested
  out="$(runscope --spec docs/specs/SPEC-0026-nested.md --include .gitattributes --base-ref main 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-011(scope) nested include" || ok=0
  grep -q '^- Inline review scope (explicit paths):$' "$nested" \
    || { log_info "TEST-011(scope): include wrote onto the label line: $(sed -n '15,22p' "$nested")"; ok=0; }
  grep -q '^  - .gitattributes$' "$nested" \
    || { log_info "TEST-011(scope): include did not append a child bullet: $(sed -n '15,22p' "$nested")"; ok=0; }
  grep -q '^  - requirements.txt$' "$nested" \
    || { log_info "TEST-011(scope): include dropped an existing child: $(sed -n '15,22p' "$nested")"; ok=0; }
  grep -q '^## Design decisions$' "$nested" \
    || { log_info "TEST-011(scope): include ate the following section"; ok=0; }

  # (d) a bullet that yields NO parsable entry is REFUSED (exit 4), never
  # reported as a no-op success.
  printf -- '---\nid: z\ntype: spec\nstatus: implementing\n---\n\n# Z\n\n## Isolation and review\n- Inline review scope: <paths>\n\n## Next\n' \
    > "$REPO/docs/specs/SPEC-0008-zero.md"
  local before
  before="$(cksum "$REPO/docs/specs/SPEC-0008-zero.md")"
  out="$(runscope --spec docs/specs/SPEC-0008-zero.md --exclude requirements.txt --base-ref main 2>&1)"; rc=$?
  expect_exit 4 "$rc" "TEST-011(scope) zero parsable entries" || ok=0
  echo "$out" | grep -qi "no parsable path entries" \
    || { log_info "TEST-011(scope): the refusal did not explain itself: $out"; ok=0; }
  [[ "$before" == "$(cksum "$REPO/docs/specs/SPEC-0008-zero.md")" ]] \
    || { log_info "TEST-011(scope): a refused zero-parsable edit still wrote"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-011(scope) nested child lists and backticked entries are first-class (edited, audited, spelling preserved, label line intact); an unparsable list refuses exit 4" \
    || log_fail "TEST-011(scope) nested/backticked shapes"
}

test_012_scope_nonascii_refusal() {
  # re-validation R1: git C-quoting must not launder a non-ASCII ride-touched path
  log_info "TEST-012(scope): non-ASCII ride-touched path refused (quotePath laundering)..."
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/st12.XXXXXX")"
  ( cd "$d" && git -c init.defaultBranch=main init -q .     && printf -- '---\nid: s\n---\n# S\n\n- Inline review scope (explicit paths): p\xc5\x99\xc3\xadloha.js, other.txt\n' > SPEC-0001-spec-s.md     && printf x > "příloha.js" && printf y > other.txt     && git add -A && git -c user.email=t@t -c user.name=t commit -qm base     && printf xx > "příloha.js" && git add "příloha.js"     && git -c user.email=t@t -c user.name=t commit -qm touch )
  local out rc=0
  out="$(cd "$d" && node "$SCOPE_EDIT" --spec SPEC-0001-spec-s.md --exclude 'příloha.js' --base-ref HEAD~1 2>&1)" || rc=$?
  [[ "$rc" -eq 3 ]] || log_fail "TEST-012(scope): non-ASCII touched path must exit 3 (got $rc): $out"
  grep -qF 'příloha.js, other.txt' "$d/SPEC-0001-spec-s.md"     || log_fail "TEST-012(scope): spec must be unmodified after the refusal"
  rm -rf "$d"
  log_pass "TEST-012(scope): quotePath laundering closed (exit 3, spec untouched)"
}

test_013_scope_backtick_annotation_key() {
  # review BLOCKING 1: `` `p` (new) `` must key as p — one-pass stripping left
  # a stray backtick and reopened the silent-no-op class on 13 corpus specs.
  log_info "TEST-013(scope): backticked entry WITH trailing annotation is matchable..."
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/st13.XXXXXX")"
  ( cd "$d" && git -c init.defaultBranch=main init -q .     && printf -- '---\nid: s\n---\n# S\n\n- Inline review scope (explicit paths): `src/lib.mjs` (new), `other.sh`\n' > SPEC-0001-spec-s.md     && printf x > other.sh && mkdir -p src && printf y > src/lib.mjs     && git add -A && git -c user.email=t@t -c user.name=t commit -qm base )
  local out rc=0
  out="$(cd "$d" && node "$SCOPE_EDIT" --spec SPEC-0001-spec-s.md --exclude src/lib.mjs --base-ref HEAD 2>&1)" || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-013(scope): exclude of a backtick+annotation entry must succeed (got $rc): $out"
  grep -qF 'src/lib.mjs' "$d/SPEC-0001-spec-s.md" && log_fail "TEST-013(scope): entry must be REMOVED from the scope"
  grep -qF '`other.sh`' "$d/SPEC-0001-spec-s.md" || log_fail "TEST-013(scope): sibling entry must survive with backticks"
  [[ -f "$d/docs/ai/EVENTS.jsonl" ]] || log_fail "TEST-013(scope): the edit must be audited"
  # include must NOT duplicate an entry present under a decorated spelling
  out="$(cd "$d" && node "$SCOPE_EDIT" --spec SPEC-0001-spec-s.md --include other.sh --base-ref HEAD 2>&1)" || rc=$?
  n="$(grep -o 'other.sh' "$d/SPEC-0001-spec-s.md" | wc -l | tr -d ' ')"
  [[ "$n" == 1 ]] || log_fail "TEST-013(scope): include must not duplicate a decorated entry (count $n)"
  rm -rf "$d"
  log_pass "TEST-013(scope): decorated entries matchable; no silent no-op, no duplicate"
}

# === R31 (CHANGE-0113 D2 probe) — FREEZE PRECONDITIONS ========================
# Before CHANGE-0113 spec-freeze.mjs checked frontmatter parse + status
# transition only: a spec whose ACs had no tests, or whose strategy was still
# `undecided`, froze happily. The Planning prompt said not to; nothing enforced
# it. These arms are the enforcement.
#
# NOTE on the split: MEASURABILITY of an AC stays Planning's judgment (no
# script can decide it); the two arms a parser CAN decide are gated here.

# freeze_fixture <status> <extra-body-flag> — a freezable spec at $SPEC.
# Args: 1 status, 2 "notest" to drop the Test Plan, "undecided"/"nostrategy"
# to break the strategy line.
freeze_fixture() {
  local status="$1" variant="${2:-}"
  spec_body "$status" false "src/touched.mjs" > "$SPEC"
  case "$variant" in
    notest) grep -v '^| TEST-001 ' "$SPEC" > "$SPEC.tmp" && mv "$SPEC.tmp" "$SPEC" ;;
    undecided) sed 's/^- Strategy: direct$/- Strategy: undecided/' "$SPEC" > "$SPEC.tmp" && mv "$SPEC.tmp" "$SPEC" ;;
    nostrategy) sed '/^- Strategy: direct$/d' "$SPEC" > "$SPEC.tmp" && mv "$SPEC.tmp" "$SPEC" ;;
  esac
}

# --- TEST-020(freeze) — an untested Spec-AC REFUSES the freeze ----------------
test_freeze_020_precondition_ac_without_test() {
  local out rc ok=1 before
  new_repo || { log_fail "TEST-020(freeze) fixture setup failed"; return; }
  freeze_fixture draft notest
  before="$(cksum "$SPEC")"
  out="$(runfreeze --path docs/specs/SPEC-0001-fx.md --no-event 2>&1)"; rc=$?
  expect_exit 3 "$rc" "TEST-020(freeze) untested AC" || ok=0
  echo "$out" | grep -qi "refus" \
    || { log_info "TEST-020(freeze): refusal not named: $out"; ok=0; }
  echo "$out" | grep -qF "ac-without-test" \
    || { log_info "TEST-020(freeze): the refusal must name its reason (ac-without-test): $out"; ok=0; }
  echo "$out" | grep -qF "Spec-AC-01" \
    || { log_info "TEST-020(freeze): the refusal must name the offending AC: $out"; ok=0; }
  [[ "$before" == "$(cksum "$SPEC")" ]] \
    || { log_info "TEST-020(freeze): a refused freeze still wrote the spec"; ok=0; }
  grep -q "^SPEC-FROZEN: true$" "$SPEC" \
    && { log_info "TEST-020(freeze): the marker was written despite the refusal"; ok=0; }
  grep -q "^status: implementing$" "$SPEC" \
    && { log_info "TEST-020(freeze): the status was flipped despite the refusal"; ok=0; }

  # --dry-run is a WOULD-BE freeze: it must refuse identically, not report ok.
  out="$(runfreeze --path docs/specs/SPEC-0001-fx.md --dry-run --no-event 2>&1)"; rc=$?
  expect_exit 3 "$rc" "TEST-020(freeze) dry-run refuses too" || ok=0

  # --json must carry a machine-readable refusal (the orchestrator's path).
  out="$(runfreeze --path docs/specs/SPEC-0001-fx.md --json --no-event 2>&1)"; rc=$?
  expect_exit 3 "$rc" "TEST-020(freeze) json refusal" || ok=0
  echo "$out" | grep -qF '"refused": true' \
    || { log_info "TEST-020(freeze): --json refusal shape wrong: $out"; ok=0; }
  echo "$out" | grep -qF 'ac-without-test' \
    || { log_info "TEST-020(freeze): --json refusal must name the reason: $out"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-020(freeze) an untested Spec-AC refuses the freeze (exit 3, named reason, nothing written)" \
    || log_fail "TEST-020(freeze) ac-without-test precondition"
}

# --- TEST-021(freeze) — an undecided/absent strategy REFUSES the freeze -------
test_freeze_021_precondition_strategy() {
  local out rc ok=1 before variant
  for variant in undecided nostrategy; do
    new_repo || { log_fail "TEST-021(freeze) fixture setup failed"; return; }
    freeze_fixture draft "$variant"
    before="$(cksum "$SPEC")"
    out="$(runfreeze --path docs/specs/SPEC-0001-fx.md --no-event 2>&1)"; rc=$?
    expect_exit 3 "$rc" "TEST-021(freeze) strategy $variant" || ok=0
    echo "$out" | grep -qF "frozen-without-strategy" \
      || { log_info "TEST-021(freeze) $variant: the refusal must name its reason: $out"; ok=0; }
    [[ "$before" == "$(cksum "$SPEC")" ]] \
      || { log_info "TEST-021(freeze) $variant: a refused freeze still wrote the spec"; ok=0; }
  done
  [[ $ok -eq 1 ]] && log_pass "TEST-021(freeze) an undecided/absent strategy refuses the freeze (both arms, nothing written)" \
    || log_fail "TEST-021(freeze) strategy precondition"
}

# --- TEST-022(freeze) — negative controls: what must STILL freeze -------------
test_freeze_022_precondition_controls() {
  local out rc ok=1
  # (a) the full fixture (covered AC + decided strategy) still freezes
  new_repo || { log_fail "TEST-022(freeze) fixture setup failed"; return; }
  freeze_fixture draft
  out="$(runfreeze --path docs/specs/SPEC-0001-fx.md --no-event 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-022(freeze) compliant spec freezes" || ok=0
  grep -q "^SPEC-FROZEN: true$" "$SPEC" \
    || { log_info "TEST-022(freeze): compliant spec did not get the marker"; ok=0; }

  # (b) an L1 lean spec is strategy-EXEMPT (RFC-0009), exactly as spec-lint is,
  # but its ACs still need tests — the two arms are independent.
  new_repo || { log_fail "TEST-022(freeze) fixture setup failed"; return; }
  cat > "$REPO/docs/specs/SPEC-0200-lean.md" <<'EOF'
---
id: spec-fixture-lean-freeze
type: spec
number: 200
status: draft
ceremony_level: 1
links:
  pr: []
---

# Fixture — lean L1

Ceremony justification: single-surface fixture fix.

## Acceptance Criteria

| Spec-AC    | Description | Status  |
|------------|-------------|---------|
| Spec-AC-01 | only        | planned |

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | unit | tests/x.sh           | a           | pending |
EOF
  out="$(runfreeze --path docs/specs/SPEC-0200-lean.md --no-event 2>&1)"; rc=$?
  expect_exit 0 "$rc" "TEST-022(freeze) lean L1 strategy exemption" || ok=0

  # (c) the OTHER refusal classes still take precedence and still name
  # themselves (a precondition must not swallow a terminal-status refusal).
  printf -- '---\nid: d\ntype: spec\nstatus: done\n---\n\n# D\n' \
    > "$REPO/docs/specs/SPEC-0201-done.md"
  out="$(runfreeze --path docs/specs/SPEC-0201-done.md --no-event 2>&1)"; rc=$?
  expect_exit 3 "$rc" "TEST-022(freeze) terminal status still refuses" || ok=0
  echo "$out" | grep -qi "only draft" \
    || { log_info "TEST-022(freeze): terminal-status refusal changed wording: $out"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-022(freeze) compliant + lean-L1 specs still freeze; other refusals unchanged" \
    || log_fail "TEST-022(freeze) precondition negative controls"
}

# --- TEST-023(freeze) — the gate is documented in --help ----------------------
test_freeze_023_help_documents_preconditions() {
  local out rc ok=1
  new_repo || { log_fail "TEST-023(freeze) fixture setup failed"; return; }
  out="$(runfreeze --help 2>&1)"; rc=$?
  echo "$out" | grep -qF "ac-without-test" \
    || { log_info "TEST-023(freeze): --help does not name the ac-without-test precondition: $out"; ok=0; }
  echo "$out" | grep -qi "strategy" \
    || { log_info "TEST-023(freeze): --help does not name the strategy precondition: $out"; ok=0; }
  # measurability is NOT claimed by the tool — the honest split
  grep -qi "measurab" "$FREEZE" \
    || { log_info "TEST-023(freeze): the script must document that measurability stays prompt judgment"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-023(freeze) --help documents both precondition arms; measurability split documented" \
    || log_fail "TEST-023(freeze) precondition documentation"
}

test_024_freeze_unparsed_ac_row() {
  # bot P2 (#232): an AC-looking row the parser drops must refuse the freeze
  log_info "TEST-024(freeze): parser-dropped AC row refuses (ac-row-unparsed)..."
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/sf24.XXXXXX")"
  cat > "$d/SPEC-0001-spec-x.md" <<'SPEC'
---
id: spec-x
type: spec
number: 1
status: draft
---
# S

- Strategy: direct

## Acceptance Criteria Status

| Spec-AC | Description | Status | Test | Evidence | Review-By |
|---|---|---|---|---|---|
| Spec-AC-01 | a | planned | tests/a.sh | — | — |
| Spec-AC-02 broken row no pipes

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Status |
|---|---|---|---|---|---|
| TEST-001 | Spec-AC-01 | unit | tests/a.sh | a | pending |
SPEC
  local before after rc=0 out
  before="$(cksum "$d/SPEC-0001-spec-x.md")"
  out="$(node "$FREEZE" --path "$d/SPEC-0001-spec-x.md" --no-event 2>&1)" || rc=$?
  [[ "$rc" -eq 3 ]] || log_fail "TEST-024(freeze): must refuse exit 3 (got $rc): $out"
  printf '%s' "$out" | grep -q 'ac-row-unparsed' || log_fail "TEST-024(freeze): reason must name ac-row-unparsed: $out"
  after="$(cksum "$d/SPEC-0001-spec-x.md")"
  [[ "$before" == "$after" ]] || log_fail "TEST-024(freeze): refusal must write nothing"
  rm -rf "$d"
  log_pass "TEST-024(freeze): unparsed AC row refuses, nothing written"
}

main() {
  echo "=== $TEST_NAME ==="
  check_deps
  test_scope_001_exclude_untouched
  test_scope_002_refuse_diff_path
  test_scope_003_events_audit
  test_scope_004_idempotent
  test_scope_005_fail_closed
  test_scope_006_path_normalization
  test_scope_007_nested_and_backticked
  test_012_scope_nonascii_refusal
  test_013_scope_backtick_annotation_key
  test_freeze_001_atomic
  test_freeze_002_half_state_refusal
  test_freeze_003_repairs_half_frozen
  test_freeze_004_no_h1
  test_freeze_020_precondition_ac_without_test
  test_freeze_021_precondition_strategy
  test_freeze_022_precondition_controls
  test_freeze_023_help_documents_preconditions
  test_024_freeze_unparsed_ac_row

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
