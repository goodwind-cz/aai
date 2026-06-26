#!/usr/bin/env bash
#
# Test: aai-orchestration-mode selector (RFC-0005 / SPEC-0005)
# Verifies the deterministic, fail-closed parallel-mode selector
# (.aai/scripts/orchestration-mode.mjs) and the SKILL_LOOP / orchestrator /
# STATE-schema / USER_GUIDE / CHANGELOG wiring. Implements TEST-001..017 from
# the frozen spec.
#
# The script under test is overridable via DOCS_SELECTOR_SCRIPT so the SAFETY
# test (TEST-003: overlapping scopes must NEVER be co-scheduled) can be
# RED-proofed against a deliberately overlap-BLIND stub (one that parallelizes
# any >=2 scopes, ignoring path overlap — the rejected Option C), analogous to
# SPEC-0004 TEST-003's non-O_EXCL stub.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-orchestration-mode"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SELECTOR="${DOCS_SELECTOR_SCRIPT:-$PROJECT_ROOT/.aai/scripts/orchestration-mode.mjs}"

SKILL_LOOP_DOC="$PROJECT_ROOT/.aai/SKILL_LOOP.prompt.md"
ORCH_DOC="$PROJECT_ROOT/.aai/ORCHESTRATION.prompt.md"
ORCH_PAR_DOC="$PROJECT_ROOT/.aai/ORCHESTRATION_PARALLEL.prompt.md"
STATE_DOC="$PROJECT_ROOT/docs/ai/STATE.yaml"
USER_GUIDE_DOC="$PROJECT_ROOT/docs/USER_GUIDE.md"
CHANGELOG_DOC="$PROJECT_ROOT/CHANGELOG.md"

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

# Run the selector with JSON ($1) on stdin; echoes stdout.
sel() { printf '%s' "$1" | node "$SELECTOR"; }

# ok <output-json> <single-line-js-boolean-expr> <failure-message>
# `o` is the parsed output object. The expr MUST NOT contain single quotes.
ok() {
  local out="$1" expr="$2" msg="$3"
  if ! printf '%s' "$out" | node -e 'const o=JSON.parse(require("fs").readFileSync(0,"utf8"));process.exit(('"$expr"')?0:1);' 2>/dev/null; then
    log_fail "$msg (output: $out)"
  fi
}

# JS helper expressions reused across tests:
#   PAR = the parallel group (or undefined)
#   inPar(id) = id is in the parallel group
# Provided inline per-test as needed.

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  [[ -f "$SELECTOR" ]] || log_fail "Selector script not found: $SELECTOR"
  log_pass "Dependencies checked"
}

# --- TEST-001 — CLI contract: bad input/flag -> exit 2; valid -> exit 0 + keys -
test_cli_contract() {
  log_info "TEST-001: no/empty input, malformed JSON, unknown flag -> exit 2; valid -> exit 0 + {mode,k,groups,reasons}..."
  local rc out
  set +e
  printf '' | node "$SELECTOR" >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "empty stdin must exit 2 (got $rc)"
  printf '   ' | node "$SELECTOR" >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "whitespace-only stdin must exit 2 (got $rc)"
  printf '%s' 'not json {' | node "$SELECTOR" >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "malformed JSON must exit 2 (got $rc)"
  printf '%s' '{"scopes":[]}' | node "$SELECTOR" --bogus-flag >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "unknown flag must exit 2 (got $rc)"
  printf '%s' '[1,2,3]' | node "$SELECTOR" >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "non-object JSON must exit 2 (got $rc)"
  out="$(printf '%s' '{"orchestration_mode":"auto","scopes":[{"id":"A","role_kind":"read","review_scope_paths":["a/"]}]}' | node "$SELECTOR")"; rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "valid input must exit 0 (got $rc)"
  set -e
  ok "$out" '"mode" in o && "k" in o && "groups" in o && "reasons" in o' "valid output must carry keys mode,k,groups,reasons"
  ok "$out" 'Array.isArray(o.groups) && typeof o.reasons==="object"' "groups must be an array; reasons an object"
  # --input <file> path also works
  local tmp; tmp="$(mktemp)"
  printf '%s' '{"scopes":[{"id":"A","role_kind":"read","review_scope_paths":["a/"]}]}' > "$tmp"
  out="$(node "$SELECTOR" --input "$tmp")"; rc=$?
  rm -f "$tmp"
  [[ "$rc" -eq 0 ]] || log_fail "--input <file> must exit 0 (got $rc)"
  ok "$out" 'o.mode==="single"' "--input file path must be parsed and decided"
  log_pass "CLI contract: bad input/flag exit 2; valid input exits 0 with the D3 keys"
}

# --- TEST-002 — disjoint paths -> parallel, both co-scheduled (Spec-AC-02) -----
test_disjoint_parallel() {
  log_info "TEST-002: two scopes with DISJOINT paths -> mode=parallel, k=2, one group with BOTH..."
  local json out
  json='{"orchestration_mode":"auto","k_max":2,"locks_available":true,"scopes":[{"id":"A","role_kind":"write","review_scope_paths":["apps/web/dashboard/"],"isolation":"inline"},{"id":"B","role_kind":"write","review_scope_paths":["apps/api/export/"],"isolation":"inline"}]}'
  out="$(sel "$json")"
  ok "$out" 'o.mode==="parallel"' "disjoint scopes must yield mode=parallel"
  ok "$out" 'o.k===2' "disjoint scopes must yield k=2"
  ok "$out" 'o.groups.some(g=>g.kind==="parallel"&&g.scopes.includes("A")&&g.scopes.includes("B")&&g.scopes.length===2)' "both A and B must share ONE parallel group"
  log_pass "disjoint declared paths are co-scheduled (parallel, k=2)"
}

# --- TEST-003 — SAFETY: overlapping paths NEVER co-scheduled (Spec-AC-02) ------
# RED-proofed against an overlap-BLIND stub via DOCS_SELECTOR_SCRIPT: the blind
# stub parallelizes any >=2 scopes, co-schedules the overlapping pair, and fails
# the "not co-scheduled" assertion. The real selector turns it GREEN.
test_overlap_safety() {
  log_info "TEST-003: two OVERLAPPING scopes (apps/api/ vs apps/api/export/) -> NOT co-scheduled + conflict reason..."
  local json out
  json='{"orchestration_mode":"auto","k_max":2,"locks_available":true,"scopes":[{"id":"A","role_kind":"write","review_scope_paths":["apps/api/"],"isolation":"inline"},{"id":"B","role_kind":"write","review_scope_paths":["apps/api/export/"],"isolation":"inline"}]}'
  out="$(sel "$json")"
  ok "$out" '!o.groups.some(g=>g.kind==="parallel"&&g.scopes.includes("A")&&g.scopes.includes("B"))' "overlapping scopes must NEVER share a parallel group"
  ok "$out" 'o.mode==="single"' "an overlapping pair (no other independent scope) must yield mode=single"
  ok "$out" '!!o.reasons.B' "a conflict reason must be recorded for the deferred overlapping scope"
  log_pass "overlapping declared paths are never co-scheduled (fail-closed)"
}

# --- TEST-004 — missing/empty path is uncertain -> sequential (Spec-AC-03) -----
test_missing_path_uncertain() {
  log_info "TEST-004: a scope with MISSING/empty review_scope_paths is uncertain -> never parallel..."
  local json out
  json='{"orchestration_mode":"auto","k_max":2,"locks_available":true,"scopes":[{"id":"A","role_kind":"write","review_scope_paths":[],"isolation":"inline"},{"id":"B","role_kind":"read","review_scope_paths":["apps/api/"]}]}'
  out="$(sel "$json")"
  ok "$out" '!o.groups.some(g=>g.kind==="parallel"&&g.scopes.includes("A"))' "an uncertain (no-path) scope must never be in the parallel group"
  ok "$out" 'o.mode==="single"' "uncertain + one disjoint scope cannot form a parallel group -> single"
  ok "$out" '!!o.reasons.A' "the uncertain scope must carry a reason"
  log_pass "missing/empty review-scope path is fail-closed to sequential"
}

# --- TEST-005 — unparseable glob is uncertain -> sequential (Spec-AC-03) -------
test_unparseable_glob() {
  log_info "TEST-005: a scope whose only path is a bare glob (** / *) reduces to empty -> uncertain..."
  local out
  for g in '**' '*' '*.md'; do
    local json
    json='{"orchestration_mode":"auto","k_max":2,"locks_available":true,"scopes":[{"id":"A","role_kind":"write","review_scope_paths":["'"$g"'"],"isolation":"inline"},{"id":"B","role_kind":"read","review_scope_paths":["apps/api/"]}]}'
    out="$(sel "$json")"
    ok "$out" '!o.groups.some(g=>g.kind==="parallel"&&g.scopes.includes("A"))' "bare-glob scope ($g) must never be parallel"
    ok "$out" '!!o.reasons.A' "bare-glob scope ($g) must carry an uncertain reason"
  done
  log_pass "bare/leading-glob paths reduce to empty prefix -> uncertain -> sequential"
}

# --- TEST-018 — canonicalization safety (Spec-AC-02/03) ------------------------
# Post-review E1: normalizePath must canonicalize before overlap so that NON-
# literal spellings of an overlapping/whole-repo path are NEVER co-scheduled.
# Each pair below genuinely shares files; the selector must yield mode=single
# (never a parallel group with both). RED-proofed: pre-fix normalizePath skips
# canonicalization and co-schedules these as parallel.
test_canonicalization_safety() {
  log_info "TEST-018: '.', './', '//', '..', and case variants must NOT defeat overlap (fail-closed)..."
  local out a
  # pairs of paths that overlap once canonicalized; B is always apps/api/
  for a in '.' './apps/api/' 'apps//api/' 'apps/web/../api/' 'Apps/Api/'; do
    local json
    json='{"orchestration_mode":"auto","k_max":2,"locks_available":true,"scopes":[{"id":"A","role_kind":"write","review_scope_paths":["'"$a"'"],"isolation":"inline"},{"id":"B","role_kind":"write","review_scope_paths":["apps/api/"],"isolation":"inline"}]}'
    out="$(sel "$json")"
    ok "$out" '!o.groups.some(g=>g.kind==="parallel"&&g.scopes.includes("A")&&g.scopes.includes("B"))' "A=[$a] vs apps/api/ must NEVER be co-scheduled parallel"
    ok "$out" 'o.mode==="single"' "A=[$a] overlapping apps/api/ must yield mode=single"
  done
  # whole-repo override=parallel must NOT force a co-schedule either
  out="$(sel '{"orchestration_mode":"parallel","k_max":2,"locks_available":true,"scopes":[{"id":"A","role_kind":"write","review_scope_paths":["."],"isolation":"inline"},{"id":"B","role_kind":"write","review_scope_paths":["apps/api/"],"isolation":"inline"}]}')"
  ok "$out" '!o.groups.some(g=>g.kind==="parallel"&&g.scopes.includes("A")&&g.scopes.includes("B"))' "override=parallel must still never co-schedule a whole-repo '.' scope"
  log_pass "non-literal/whole-repo/case path spellings are canonicalized and fail-closed"
}

# --- TEST-006 — single scope -> single/k=1, no overhead (Spec-AC-04) -----------
test_single_scope() {
  log_info "TEST-006: one actionable scope -> mode=single, k=1, no parallel group..."
  local out
  out="$(sel '{"orchestration_mode":"auto","k_max":2,"scopes":[{"id":"A","role_kind":"write","review_scope_paths":["src/a/"],"isolation":"inline"}]}')"
  ok "$out" 'o.mode==="single"' "single scope must be mode=single"
  ok "$out" 'o.k===1' "single scope must be k=1"
  ok "$out" '!o.groups.some(g=>g.kind==="parallel")' "single scope must have NO parallel group"
  log_pass "single actionable scope -> single/k=1 (zero overhead)"
}

# --- TEST-007 — two independent (defaults) -> parallel k=2 (Spec-AC-04) --------
test_two_independent_defaults() {
  log_info "TEST-007: two mutually independent scopes, default orchestration_mode/k_max -> parallel k=2..."
  local out
  out="$(sel '{"scopes":[{"id":"A","role_kind":"read","review_scope_paths":["src/a/"]},{"id":"B","role_kind":"read","review_scope_paths":["src/b/"]}]}')"
  ok "$out" 'o.mode==="parallel"' "two independent scopes (defaults) must be parallel"
  ok "$out" 'o.k===2' "k must be min(k_max=2,count=2)=2"
  log_pass "two independent scopes under defaults -> parallel, k=2"
}

# --- TEST-008 — >k_max independent -> k=k_max, remainder sequential (Spec-AC-05)
test_kmax_cap() {
  log_info "TEST-008: three independent scopes, k_max=2 -> k=2, parallel has exactly 2, third sequential (k_cap)..."
  local out
  out="$(sel '{"orchestration_mode":"auto","k_max":2,"scopes":[{"id":"A","role_kind":"read","review_scope_paths":["src/a/"]},{"id":"B","role_kind":"read","review_scope_paths":["src/b/"]},{"id":"C","role_kind":"read","review_scope_paths":["src/c/"]}]}')"
  ok "$out" 'o.mode==="parallel"&&o.k===2' "k must equal k_max=2"
  ok "$out" 'o.groups.filter(g=>g.kind==="parallel")[0].scopes.length===2' "the parallel group must hold exactly 2"
  ok "$out" 'o.groups.some(g=>g.kind==="sequential"&&g.scopes.length===1&&g.scopes.includes("C"))' "the third scope must be a sequential singleton"
  ok "$out" '/k_cap/i.test(o.reasons.C||"")' "the deferred third scope must carry a k_cap reason"
  log_pass ">k_max independent scopes capped at k_max; remainder deferred"
}

# --- TEST-009 — read-only disjoint -> parallel, no worktree (Spec-AC-06) -------
test_readonly_disjoint() {
  log_info "TEST-009: two read-only scopes on disjoint paths -> parallel k=2 (no worktree needed)..."
  local out
  out="$(sel '{"orchestration_mode":"auto","k_max":2,"scopes":[{"id":"A","role_kind":"read","review_scope_paths":["docs/a/"],"isolation":"inline"},{"id":"B","role_kind":"read","review_scope_paths":["docs/b/"],"isolation":"inline"}]}')"
  ok "$out" 'o.mode==="parallel"&&o.k===2' "read-only disjoint scopes must parallelize without a worktree"
  ok "$out" 'o.groups.some(g=>g.kind==="parallel"&&g.scopes.includes("A")&&g.scopes.includes("B"))' "both read scopes must co-schedule"
  log_pass "read-only roles across disjoint paths parallelize (no worktree)"
}

# --- TEST-010 — write isolation requirement (Spec-AC-06) ----------------------
test_write_isolation() {
  log_info "TEST-010: write inline w/ unprovable paths -> sequential; write worktree -> independent..."
  # (a) inline write with NO paths is uncertain -> sequential
  local out
  out="$(sel '{"orchestration_mode":"auto","k_max":2,"scopes":[{"id":"A","role_kind":"write","review_scope_paths":[],"isolation":"inline"},{"id":"B","role_kind":"write","review_scope_paths":["y/"],"isolation":"inline"}]}')"
  ok "$out" '!o.groups.some(g=>g.kind==="parallel"&&g.scopes.includes("A"))' "an inline write with no provable paths must be sequential"
  ok "$out" '!!o.reasons.A' "the unprovable inline write must carry a reason"
  # (b) worktree write (no paths) is treated independent -> can join the parallel group
  out="$(sel '{"orchestration_mode":"auto","k_max":2,"scopes":[{"id":"A","role_kind":"write","review_scope_paths":[],"isolation":"worktree"},{"id":"B","role_kind":"write","review_scope_paths":["y/"],"isolation":"inline"}]}')"
  ok "$out" 'o.mode==="parallel"&&o.k===2' "a worktree write must be treated as independent"
  ok "$out" 'o.groups.some(g=>g.kind==="parallel"&&g.scopes.includes("A")&&g.scopes.includes("B"))' "the worktree write may join the parallel group"
  log_pass "write parallelizes only when inline-disjoint or worktree-isolated"
}

# --- TEST-011 — docs-lock absent -> single/k=1 degrade (Spec-AC-07) ------------
test_locks_unavailable_degrade() {
  log_info "TEST-011: locks_available=false with two independent scopes -> mode=single, k=1, locks reason..."
  local out
  out="$(sel '{"orchestration_mode":"auto","k_max":2,"locks_available":false,"scopes":[{"id":"A","role_kind":"read","review_scope_paths":["src/a/"]},{"id":"B","role_kind":"read","review_scope_paths":["src/b/"]}]}')"
  ok "$out" 'o.mode==="single"&&o.k===1' "no locks must degrade to single/k=1 even with independent scopes"
  ok "$out" '/lock/i.test(o.reasons.B||"")' "the deferred scope must carry a locks_unavailable reason"
  log_pass "locks_available=false degrades to single/k=1 (never parallel without locks)"
}

# --- TEST-012 — max_k_budget caps K (Spec-AC-08) ------------------------------
test_budget_cap() {
  log_info "TEST-012: max_k_budget=1 with 3 indep -> single; =2 with 3 indep & k_max=3 -> k=2..."
  local out
  out="$(sel '{"orchestration_mode":"auto","k_max":3,"max_k_budget":1,"scopes":[{"id":"A","role_kind":"read","review_scope_paths":["src/a/"]},{"id":"B","role_kind":"read","review_scope_paths":["src/b/"]},{"id":"C","role_kind":"read","review_scope_paths":["src/c/"]}]}')"
  ok "$out" 'o.mode==="single"&&o.k===1' "max_k_budget=1 must force single"
  out="$(sel '{"orchestration_mode":"auto","k_max":3,"max_k_budget":2,"scopes":[{"id":"A","role_kind":"read","review_scope_paths":["src/a/"]},{"id":"B","role_kind":"read","review_scope_paths":["src/b/"]},{"id":"C","role_kind":"read","review_scope_paths":["src/c/"]}]}')"
  ok "$out" 'o.mode==="parallel"&&o.k===2' "max_k_budget=2 with k_max=3 and 3 indep must yield k=2"
  log_pass "max_k_budget caps fan-out (=1 single; =2 -> k=2)"
}

# --- TEST-013 — override single forces single (Spec-AC-09) --------------------
test_override_single() {
  log_info "TEST-013: orchestration_mode=single with two independent scopes -> single, k=1..."
  local out
  out="$(sel '{"orchestration_mode":"single","k_max":2,"scopes":[{"id":"A","role_kind":"read","review_scope_paths":["src/a/"]},{"id":"B","role_kind":"read","review_scope_paths":["src/b/"]}]}')"
  ok "$out" 'o.mode==="single"&&o.k===1' "override single must force single/k=1 even with independent scopes"
  ok "$out" '!o.groups.some(g=>g.kind==="parallel")' "override single must produce no parallel group"
  log_pass "override orchestration_mode=single forces single"
}

# --- TEST-014 — override parallel respects independence both ways (Spec-AC-09) -
test_override_parallel_respects_safety() {
  log_info "TEST-014: orchestration_mode=parallel: disjoint -> parallel; overlapping -> single (opt-in, not a safety override)..."
  local out
  out="$(sel '{"orchestration_mode":"parallel","k_max":2,"scopes":[{"id":"A","role_kind":"write","review_scope_paths":["apps/web/"],"isolation":"inline"},{"id":"B","role_kind":"write","review_scope_paths":["apps/api/"],"isolation":"inline"}]}')"
  ok "$out" 'o.mode==="parallel"&&o.k===2' "override parallel + disjoint -> parallel"
  out="$(sel '{"orchestration_mode":"parallel","k_max":2,"scopes":[{"id":"A","role_kind":"write","review_scope_paths":["apps/api/"],"isolation":"inline"},{"id":"B","role_kind":"write","review_scope_paths":["apps/api/export/"],"isolation":"inline"}]}')"
  ok "$out" 'o.mode==="single"' "override parallel + OVERLAPPING -> single (never bypass overlap test)"
  ok "$out" '!o.groups.some(g=>g.kind==="parallel"&&g.scopes.includes("A")&&g.scopes.includes("B"))' "override parallel must not co-schedule overlapping scopes"
  log_pass "override parallel is an opt-in that respects independence (never unsafe)"
}

# --- TEST-015 — SKILL_LOOP + orchestrator wiring (Spec-AC-10) ------------------
test_wiring_skill_loop() {
  log_info "TEST-015: SKILL_LOOP RUN ORCHESTRATION is mode-aware; both orchestrators cross-reference the selector..."
  [[ -f "$SKILL_LOOP_DOC" ]] || log_fail "missing $SKILL_LOOP_DOC"
  [[ -f "$ORCH_DOC" ]] || log_fail "missing $ORCH_DOC"
  [[ -f "$ORCH_PAR_DOC" ]] || log_fail "missing $ORCH_PAR_DOC"
  grep -qF "orchestration-mode.mjs" "$SKILL_LOOP_DOC" || log_fail "SKILL_LOOP must reference the selector orchestration-mode.mjs"
  grep -qF "ORCHESTRATION.prompt.md" "$SKILL_LOOP_DOC" || log_fail "SKILL_LOOP must dispatch ORCHESTRATION.prompt.md (single)"
  grep -qF "ORCHESTRATION_PARALLEL.prompt.md" "$SKILL_LOOP_DOC" || log_fail "SKILL_LOOP must dispatch ORCHESTRATION_PARALLEL.prompt.md (parallel)"
  grep -qF "orchestration.mode" "$SKILL_LOOP_DOC" || log_fail "SKILL_LOOP must record orchestration.mode"
  grep -qF "orchestration.k" "$SKILL_LOOP_DOC" || log_fail "SKILL_LOOP must record orchestration.k"
  grep -qF "orchestration.groups" "$SKILL_LOOP_DOC" || log_fail "SKILL_LOOP must record orchestration.groups"
  grep -qF "orchestration-mode.mjs" "$ORCH_PAR_DOC" || log_fail "ORCHESTRATION_PARALLEL must cross-reference the selector"
  grep -qF "orchestration-mode.mjs" "$ORCH_DOC" || log_fail "ORCHESTRATION must cross-reference the selector"
  log_pass "SKILL_LOOP is mode-aware and both orchestrators cross-reference the selector"
}

# --- TEST-016 — STATE.yaml schema header (Spec-AC-11) -------------------------
test_wiring_state_schema() {
  log_info "TEST-016: STATE.yaml schema header documents orchestration.mode/k/groups + absent==auto..."
  [[ -f "$STATE_DOC" ]] || log_fail "missing $STATE_DOC"
  grep -qiE "orchestration\.mode:.*auto.*single.*parallel" "$STATE_DOC" || log_fail "STATE header must document orchestration.mode (auto|single|parallel)"
  grep -qiE "orchestration\.k" "$STATE_DOC" || log_fail "STATE header must document orchestration.k"
  grep -qiE "orchestration\.groups" "$STATE_DOC" || log_fail "STATE header must document orchestration.groups"
  grep -qiE "absent.*auto" "$STATE_DOC" || log_fail "STATE header must note an absent block == auto (back-compat)"
  log_pass "STATE.yaml schema header documents the optional orchestration block"
}

# --- TEST-017 — USER_GUIDE + CHANGELOG (Spec-AC-12) ---------------------------
test_wiring_docs() {
  log_info "TEST-017: USER_GUIDE has a Parallel multi-agent orchestration section; CHANGELOG has RFC-0005 + docs-lock..."
  [[ -f "$USER_GUIDE_DOC" ]] || log_fail "missing $USER_GUIDE_DOC"
  [[ -f "$CHANGELOG_DOC" ]] || log_fail "missing $CHANGELOG_DOC"
  grep -qiF "Parallel multi-agent orchestration" "$USER_GUIDE_DOC" || log_fail "USER_GUIDE must have a 'Parallel multi-agent orchestration' section"
  grep -qF "k_max" "$USER_GUIDE_DOC" || log_fail "USER_GUIDE must document the k_max default"
  grep -qiF "docs-lock" "$USER_GUIDE_DOC" || log_fail "USER_GUIDE must document the docs-lock degrade-to-single behavior"
  grep -qiE "auto.*single.*parallel|single.*parallel" "$USER_GUIDE_DOC" || log_fail "USER_GUIDE must document auto/single/parallel modes"
  grep -qiF "override" "$USER_GUIDE_DOC" || log_fail "USER_GUIDE must document how to override the mode"
  grep -qF "RFC-0005" "$CHANGELOG_DOC" || log_fail "CHANGELOG must have an RFC-0005 entry"
  grep -qiF "docs-lock" "$CHANGELOG_DOC" || log_fail "CHANGELOG must (retroactively) reference the docs-lock primitive"
  log_pass "USER_GUIDE parallel-orchestration section + CHANGELOG RFC-0005/docs-lock entry present"
}

# --- TEST-019 — parent/child link fail-closed even on DISJOINT paths (D4) ------
# The selector's conflict() treats a declared parent/child link as a conflict
# (isLinkedParentChild), so a declared dependency forces sequential even when the
# two scopes touch DISJOINT files. Positive control: the SAME two scopes with the
# link removed DO parallelize -> the link (not the paths) is what defers them, so
# the assertion is non-tautological.
test_parent_child_link_fail_closed() {
  log_info "TEST-019: two DISJOINT-path scopes with a parent/child link -> NOT co-scheduled (mode=single + reason); unlinked control -> parallel..."
  local json out
  # (a) B declares parent=A; paths are disjoint (src/a/ vs src/b/) -> conflict via link
  json='{"orchestration_mode":"auto","k_max":2,"locks_available":true,"scopes":[{"id":"A","role_kind":"write","review_scope_paths":["src/a/"],"isolation":"inline","children":["B"]},{"id":"B","role_kind":"write","review_scope_paths":["src/b/"],"isolation":"inline","parent":"A"}]}'
  out="$(sel "$json")"
  ok "$out" '!o.groups.some(g=>g.kind==="parallel"&&g.scopes.includes("A")&&g.scopes.includes("B"))' "a parent/child link must NEVER co-schedule the pair, even on disjoint paths"
  ok "$out" 'o.mode==="single"' "a linked pair with no other independent scope must yield mode=single"
  ok "$out" '!!o.reasons.B' "the deferred linked scope must carry a reason"
  ok "$out" '/conflicts-with A/.test(o.reasons.B||"")' "the deferred linked scope must record a conflicts-with reason naming the parent"
  # (b) POSITIVE CONTROL: identical scopes/paths but WITHOUT the link -> parallel
  json='{"orchestration_mode":"auto","k_max":2,"locks_available":true,"scopes":[{"id":"A","role_kind":"write","review_scope_paths":["src/a/"],"isolation":"inline"},{"id":"B","role_kind":"write","review_scope_paths":["src/b/"],"isolation":"inline"}]}'
  out="$(sel "$json")"
  ok "$out" 'o.mode==="parallel"&&o.k===2' "control: the SAME disjoint scopes WITHOUT a link must parallelize (k=2)"
  ok "$out" 'o.groups.some(g=>g.kind==="parallel"&&g.scopes.includes("A")&&g.scopes.includes("B"))' "control: unlinked disjoint scopes must share one parallel group"
  log_pass "a declared parent/child link forces sequential even on disjoint paths (fail-closed); unlinked control parallelizes"
}

main() {
  echo "Testing $TEST_NAME (deterministic fail-closed parallel-mode selector + wiring)"
  check_deps
  test_cli_contract
  test_disjoint_parallel
  test_overlap_safety
  test_missing_path_uncertain
  test_unparseable_glob
  test_canonicalization_safety
  test_single_scope
  test_two_independent_defaults
  test_kmax_cap
  test_readonly_disjoint
  test_write_isolation
  test_locks_unavailable_degrade
  test_budget_cap
  test_override_single
  test_override_parallel_respects_safety
  test_wiring_skill_loop
  test_wiring_state_schema
  test_wiring_docs
  test_parent_child_link_fail_closed
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

# Allow sourcing for isolated per-test execution (TDD RED/GREEN evidence);
# run the full suite only when invoked directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
