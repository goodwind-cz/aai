#!/usr/bin/env bash
#
# Test: atomic doc-number reservation in origin (CHANGE-0035 / SPEC-0047)
#
# Verifies the D2 create-only atomic-ref reservation protocol layered on top
# of the SPEC-0015 allocator: reservation-before-rename, the D3 candidate
# union scan (local + origin/* + reservation refs), the D4 offline/no-
# permission provisional-marker fallback + --reserve completion, the D5
# merge-guard predicates (cross-branch collision + unreserved marker), the D6
# spec-lint --slug-handles advisory, and the D7 coupled-families union
# counter with one atomic multi-ref push.
#
# D10: every fixture uses a LOCAL bare repo (`git init --bare`) as origin —
# zero network. A race is simulated by pushing a reservation ref directly to
# the bare repo "from another clone" before invoking the code under test.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-doc-number-reservation"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ALLOC_SCRIPT="$PROJECT_ROOT/.aai/scripts/allocate-doc-number.mjs"

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
assert_contains() { grep -qF "$2" "$1" || log_fail "Expected '$2' in $1"; }
assert_not_contains() {
  if grep -qF "$2" "$1"; then log_fail "Did not expect '$2' in $1"; fi
}

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  [[ -f "$ALLOC_SCRIPT" ]] || log_fail "Allocator script not found: $ALLOC_SCRIPT"
  log_pass "Dependencies checked"
}

PROJECT_FILES=(
  .aai/scripts/allocate-doc-number.mjs
  .aai/scripts/generate-docs-index.mjs
  .aai/scripts/docs-audit.mjs
  .aai/scripts/append-event.mjs
  .aai/scripts/spec-lint.mjs
  .aai/scripts/pre-commit-checks.sh
)

# Vendor the doc-numbering toolchain into an isolated git repo. Echoes the
# repo path. When want_origin != "no", also `git init --bare` a companion
# origin at $TEST_DIR/origin-<label>.git and `git remote add origin <bare>`
# (D10). NOTE: this path is deterministic by design — mk_repo is always
# invoked via command substitution `d="$(mk_repo label)"`, which runs the
# function body in a SUBSHELL, so any plain variable it sets (e.g. a would-be
# ORIGIN_BARE global) never propagates to the caller. Callers recompute the
# bare path as "$TEST_DIR/origin-<label>.git" instead of reading a global.
mk_repo() {
  local label="$1" want_origin="${2:-yes}"
  local d="$TEST_DIR/iso-$label"
  local bare="$TEST_DIR/origin-$label.git"
  rm -rf "$d" "$bare"
  mkdir -p "$d/.aai/scripts/lib" \
           "$d/docs/rfc" "$d/docs/specs" "$d/docs/issues" \
           "$d/docs/requirements" "$d/docs/releases" "$d/docs/ai" \
           "$d/docs/ai/reviews" "$d/docs/ai/reports" "$d/docs/ai/briefs" \
           "$d/docs/product" "$d/docs/project-sessions" "$d/docs/knowledge" \
           "$d/docs/archive" \
           "$d/tests"
  local f
  for f in "${PROJECT_FILES[@]}"; do
    cp "$PROJECT_ROOT/$f" "$d/$f" 2>/dev/null || true
  done
  cp "$PROJECT_ROOT"/.aai/scripts/lib/*.mjs "$d/.aai/scripts/lib/"
  (cd "$d" && git init -q -b main \
     && git config user.email test@example.com \
     && git config user.name "AAI Test")
  printf 'docs/INDEX.audit.md\n' > "$d/.gitignore"
  (cd "$d" && git add .aai .gitignore && git commit -qm "chore: vendor scripts")
  if [[ "$want_origin" != "no" ]]; then
    git init -q --bare "$bare"
    (cd "$d" && git remote add origin "$bare")
  fi
  printf '%s' "$d"
}

write_draft() {
  # write_draft <repo> <dir> <PREFIX> <slug>
  local d="$1" dir="$2" prefix="$3" slug="$4"
  cat > "$d/docs/$dir/$prefix-DRAFT-$slug.md" <<MD
---
id: $slug
type: rfc
number: null
status: draft
links:
  pr: []
---
# Draft: $slug
MD
}

# seed_numbered <repo> <dir> <PREFIX> <top> [type]  — RFC-0001..RFC-000N style.
seed_numbered() {
  local d="$1" dir="$2" prefix="$3" top="$4" type="${5:-rfc}" i n
  for i in $(seq 1 "$top"); do
    n="$(printf '%04d' "$i")"
    cat > "$d/docs/$dir/$prefix-$n-seed-$i.md" <<MD
---
id: seed-$prefix-$i
type: $type
number: $i
status: done
links:
  pr: []
---
# Seed $prefix $i
MD
  done
  (cd "$d" && git add "docs/$dir" && git commit -qm "docs: seed $prefix up to $top")
}

# push_raw_ref <bare> <refname> <marker> — a throwaway commit from "another
# clone", pushed directly to <bare> at <refname>. Simulates a pre-existing
# reservation / branch WITHOUT going through the code under test (D10).
push_raw_ref() {
  local bare="$1" ref="$2" marker="$3"
  local scratch="$TEST_DIR/scratch-$RANDOM-$RANDOM"
  rm -rf "$scratch"; mkdir -p "$scratch"
  (cd "$scratch" && git init -q && git config user.email r@r.example && git config user.name racer \
     && echo "$marker" > marker.txt && git add marker.txt && git commit -qm "raw: $marker" \
     && git push -q "$bare" "HEAD:$ref")
  rm -rf "$scratch"
}

ref_exists() {  # ref_exists <bare> <refname>
  [[ -n "$(git ls-remote "$1" "$2" 2>/dev/null)" ]]
}

# =============================================================================
# TEST-001 (Spec-AC-01): reservation-before-rename with a reachable origin.
test_001_reservation_before_rename() {
  log_info "TEST-001: allocation creates refs/aai/docnums/<ID> in bare origin AND renames the file..."
  local d; d="$(mk_repo t001)"
  local bare="$TEST_DIR/origin-t001.git"
  (cd "$d" && git checkout -q -b feature/one)
  write_draft "$d" rfc RFC topic-one
  (cd "$d" && git add docs/rfc && git commit -qm "docs: draft one" >/dev/null)
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs \
      --path docs/rfc/RFC-DRAFT-topic-one.md --base-ref main > alloc.log 2>&1) \
    || log_fail "allocation must exit 0: $(cat "$d/alloc.log")"
  assert_file "$d/docs/rfc/RFC-0001-topic-one.md"
  [[ ! -f "$d/docs/rfc/RFC-DRAFT-topic-one.md" ]] || log_fail "DRAFT must be renamed away"
  ref_exists "$bare" "refs/aai/docnums/RFC-0001" \
    || log_fail "refs/aai/docnums/RFC-0001 must exist in the bare origin after allocation"
  assert_not_contains "$d/alloc.log" "number_reserved"
  rm -rf "$d"
  log_pass "TEST-001 reservation ref created in origin, file renamed, no provisional marker"
}

# =============================================================================
# TEST-002 (Spec-AC-03): ref-exists rejection retries next free (direct unit
# test of the reserveAtomic primitive — see Seam S4 residual-risk note in the
# spec: a genuine in-flight push race cannot be forced deterministically in a
# local fixture, so this test exercises the REJECTION-DRIVEN RETRY logic
# against a real pre-existing ref, which is the observable outcome).
test_002_retry_on_rejection() {
  log_info "TEST-002: pre-existing reservation ref -> create-only push rejected -> retries to next free..."
  local d; d="$(mk_repo t002)"
  local bare="$TEST_DIR/origin-t002.git"
  push_raw_ref "$bare" "refs/aai/docnums/CHANGE-0005" "racer-owns-5"
  cat > "$d/probe.mjs" <<'EOF'
import { reserveAtomic } from './.aai/scripts/allocate-doc-number.mjs';
import assert from 'node:assert';
const r = reserveAtomic(process.cwd(), 'origin', [{ prefix: 'CHANGE', width: 4 }], 5, 50);
assert.strictEqual(r.ok, true, 'reservation must eventually succeed: ' + JSON.stringify(r));
assert.strictEqual(r.number, 6, 'must retry past the pre-existing 5 and land on 6: ' + JSON.stringify(r));
console.log('ok');
EOF
  (cd "$d" && node probe.mjs) > "$d/probe.log" 2>&1 \
    || log_fail "TEST-002 retry-on-rejection incorrect: $(cat "$d/probe.log")"
  assert_contains "$d/probe.log" "ok"
  ref_exists "$bare" "refs/aai/docnums/CHANGE-0005" || log_fail "the racer's ref (5) must still exist"
  ref_exists "$bare" "refs/aai/docnums/CHANGE-0006" || log_fail "the retried ref (6) must now exist"
  rm -rf "$d"
  log_pass "TEST-002 rejection on pre-existing ref retries and lands next free; both refs exist"
}

# =============================================================================
# TEST-003 (Spec-AC-02): a number taken only on an unmerged origin side branch
# is skipped (the exact SPEC-0042-incident regression this spec exists to fix).
test_003_origin_side_branch_scanned() {
  log_info "TEST-003: number taken on an unmerged origin branch (never locally fetched before) is skipped..."
  local d; d="$(mk_repo t003)"
  local bare="$TEST_DIR/origin-t003.git"
  # "another contributor" pushes a branch straight to origin with a numbered
  # doc our clone has never seen (not on local main, not previously fetched).
  local other="$TEST_DIR/other-t003"
  rm -rf "$other"; mkdir -p "$other/docs/rfc"
  (cd "$other" && git init -q && git config user.email o@o.example && git config user.name other)
  cat > "$other/docs/rfc/RFC-0005-side-topic.md" <<'MD'
---
id: side-topic
type: rfc
number: 5
status: draft
links:
  pr: []
---
# Side
MD
  (cd "$other" && git add docs/rfc && git commit -qm "docs: side branch RFC-0005" \
     && git push -q "$bare" "HEAD:refs/heads/unmerged/side")
  rm -rf "$other"

  (cd "$d" && git checkout -q -b feature/three)
  write_draft "$d" rfc RFC main-topic
  (cd "$d" && git add docs/rfc && git commit -qm "docs: draft" >/dev/null)
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs \
      --path docs/rfc/RFC-DRAFT-main-topic.md --base-ref main > alloc.log 2>&1) \
    || log_fail "allocation must exit 0: $(cat "$d/alloc.log")"
  assert_file "$d/docs/rfc/RFC-0006-main-topic.md"
  [[ ! -f "$d/docs/rfc/RFC-0005-main-topic.md" ]] \
    || log_fail "must NOT re-mint RFC-0005 (taken on the unmerged origin side branch)"
  rm -rf "$d"
  log_pass "TEST-003 origin side-branch number scanned and skipped (union candidate scan)"
}

# =============================================================================
# TEST-004 (Spec-AC-02): a naked reservation ref (no doc anywhere) is taken.
test_004_naked_reservation_ref_taken() {
  log_info "TEST-004: a naked reservation ref with no doc anywhere is treated as taken..."
  local d; d="$(mk_repo t004)"
  local bare="$TEST_DIR/origin-t004.git"
  push_raw_ref "$bare" "refs/aai/docnums/RFC-0005" "naked-reservation"
  (cd "$d" && git checkout -q -b feature/four)
  write_draft "$d" rfc RFC four-topic
  (cd "$d" && git add docs/rfc && git commit -qm "docs: draft" >/dev/null)
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs \
      --path docs/rfc/RFC-DRAFT-four-topic.md --base-ref main > alloc.log 2>&1) \
    || log_fail "allocation must exit 0: $(cat "$d/alloc.log")"
  assert_file "$d/docs/rfc/RFC-0006-four-topic.md"
  [[ ! -f "$d/docs/rfc/RFC-0005-four-topic.md" ]] \
    || log_fail "must NOT re-mint RFC-0005 (a naked reservation ref already claims it)"
  rm -rf "$d"
  log_pass "TEST-004 naked reservation ref treated as taken"
}

# =============================================================================
# TEST-005 (Spec-AC-04): unreachable push target -> provisional marker + warn + exit 0.
test_005_offline_fallback_marker() {
  log_info "TEST-005: unreachable origin -> allocation proceeds, marks number_reserved: false, warns, exit 0..."
  local d; d="$(mk_repo t005 no)"
  (cd "$d" && git remote add origin "$TEST_DIR/does-not-exist-t005.git")
  (cd "$d" && git checkout -q -b feature/five)
  write_draft "$d" rfc RFC unreachable-topic
  (cd "$d" && git add docs/rfc && git commit -qm "docs: draft" >/dev/null)
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs \
      --path docs/rfc/RFC-DRAFT-unreachable-topic.md --base-ref main > alloc.log 2>&1) \
    || log_fail "allocation must still exit 0 (fail-open with a visible tax): $(cat "$d/alloc.log")"
  local out="$d/docs/rfc/RFC-0001-unreachable-topic.md"
  assert_file "$out"
  grep -qE '^number_reserved:[[:space:]]*false[[:space:]]*$' "$out" \
    || log_fail "must stamp number_reserved: false when reservation push fails"
  assert_contains "$d/alloc.log" "WARNING"
  rm -rf "$d"
  log_pass "TEST-005 offline/no-permission fallback: provisional marker + WARNING + exit 0"
}

# =============================================================================
# TEST-006 (Spec-AC-05a): guard exit 4 on cross-branch collision (staged
# TYPE-NNNN exists on the base ref under a different slug id).
test_006_guard_cross_branch_collision() {
  log_info "TEST-006: --guard exit 4 when staged TYPE-NNNN exists on base ref under a different id..."
  local d; d="$(mk_repo t006)"
  local bare="$TEST_DIR/origin-t006.git"
  cat > "$d/docs/issues/CHANGE-0005-alpha.md" <<'MD'
---
id: alpha
type: change
number: 5
status: done
links:
  pr: []
---
# Alpha
MD
  (cd "$d" && git add docs/issues && git commit -qm "docs: alpha on main" \
     && git push -q origin HEAD:refs/heads/main)
  # a DIFFERENT clone stages CHANGE-0005 under a different id "beta".
  local d2; d2="$TEST_DIR/iso-t006b"
  rm -rf "$d2"; cp -R "$d" "$d2"
  rm -f "$d2/docs/issues/CHANGE-0005-alpha.md"
  cat > "$d2/docs/issues/CHANGE-0005-beta.md" <<'MD'
---
id: beta
type: change
number: 5
status: done
links:
  pr: []
---
# Beta
MD
  (cd "$d2" && git add docs/issues)
  set +e
  (cd "$d2" && node .aai/scripts/allocate-doc-number.mjs --guard --base-ref origin/main > guard.log 2>&1)
  local rc=$?
  set -e
  [[ "$rc" -eq 4 ]] || log_fail "cross-branch collision must exit 4 (got $rc): $(cat "$d2/guard.log")"
  assert_contains "$d2/guard.log" "beta"
  assert_contains "$d2/guard.log" "alpha"
  # negative control: the SAME id on both sides must NOT trip the predicate.
  local d3; d3="$TEST_DIR/iso-t006c"
  rm -rf "$d3"; cp -R "$d" "$d3"
  (cd "$d3" && git add docs/issues)
  (cd "$d3" && node .aai/scripts/allocate-doc-number.mjs --guard --base-ref origin/main > guard-clean.log 2>&1) \
    || log_fail "matching id on both sides must NOT trip the cross-branch predicate: $(cat "$d3/guard-clean.log")"
  rm -rf "$d" "$d2" "$d3"
  log_pass "TEST-006 guard cross-branch collision exit 4 naming both ids; matching id is a negative control"
}

# =============================================================================
# TEST-007 (Spec-AC-04, Spec-AC-05b): guard blocks number_reserved: false;
# --reserve completes it (marker removed, guard clean) or exits 4 when the
# ref already exists at completion time.
test_007_guard_marker_and_reserve_completion() {
  log_info "TEST-007: --guard blocks number_reserved: false; --reserve completes or exits 4 on collision..."
  local d; d="$(mk_repo t007)"
  local bare="$TEST_DIR/origin-t007.git"
  cat > "$d/docs/issues/CHANGE-0005-gamma.md" <<'MD'
---
id: gamma
type: change
number: 5
status: draft
number_reserved: false
links:
  pr: []
---
# Gamma
MD
  (cd "$d" && git add docs/issues/CHANGE-0005-gamma.md)
  set +e
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs --guard > guard-blocked.log 2>&1)
  local rc=$?
  set -e
  [[ "$rc" -eq 4 ]] || log_fail "unreserved marker must exit 4 (got $rc): $(cat "$d/guard-blocked.log")"
  assert_contains "$d/guard-blocked.log" "CHANGE-0005-gamma.md"

  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs --reserve \
      --path docs/issues/CHANGE-0005-gamma.md > reserve.log 2>&1) \
    || log_fail "--reserve completion must exit 0: $(cat "$d/reserve.log")"
  assert_not_contains "$d/docs/issues/CHANGE-0005-gamma.md" "number_reserved"
  ref_exists "$bare" "refs/aai/docnums/CHANGE-0005" || log_fail "completion must create the reservation ref"
  (cd "$d" && git add docs/issues/CHANGE-0005-gamma.md)
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs --guard > guard-clean.log 2>&1) \
    || log_fail "guard must be clean after completion: $(cat "$d/guard-clean.log")"

  # ref-exists-at-completion case -> exit 4, naming the collision.
  cat > "$d/docs/issues/CHANGE-0006-delta.md" <<'MD'
---
id: delta
type: change
number: 6
status: draft
number_reserved: false
links:
  pr: []
---
# Delta
MD
  push_raw_ref "$bare" "refs/aai/docnums/CHANGE-0006" "collides-with-delta"
  set +e
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs --reserve \
      --path docs/issues/CHANGE-0006-delta.md > reserve2.log 2>&1)
  rc=$?
  set -e
  [[ "$rc" -eq 4 ]] || log_fail "--reserve on an already-taken ref must exit 4 (got $rc): $(cat "$d/reserve2.log")"
  assert_contains "$d/reserve2.log" "CHANGE-0006"
  grep -qE '^number_reserved:[[:space:]]*false[[:space:]]*$' "$d/docs/issues/CHANGE-0006-delta.md" \
    || log_fail "the marker must remain on an exit-4 completion (never silently cleared)"
  rm -rf "$d"
  log_pass "TEST-007 guard blocks unreserved marker; --reserve completes clean or exits 4 on collision"
}

# =============================================================================
# TEST-008 (Spec-AC-06): spec-lint --slug-handles.
test_008_slug_handles_lint() {
  log_info "TEST-008: spec-lint --slug-handles flags an artifact filename with no merged doc; clean once merged..."
  local d; d="$(mk_repo t008 no)"
  cat > "$d/docs/ai/reviews/review-CHANGE-036.md" <<'MD'
# Review
Notes about CHANGE-036.
MD
  set +e
  (cd "$d" && node .aai/scripts/spec-lint.mjs --slug-handles > lint.log 2>&1)
  local rc=$?
  set -e
  [[ "$rc" -eq 1 ]] || log_fail "must exit 1 (findings) when CHANGE-036 has no merged doc (got $rc): $(cat "$d/lint.log")"
  assert_contains "$d/lint.log" "CHANGE-036"
  assert_contains "$d/lint.log" "review-CHANGE-036.md"
  mkdir -p "$d/docs/issues"
  cat > "$d/docs/issues/CHANGE-0036-real-doc.md" <<'MD'
---
id: real-doc
type: change
number: 36
status: done
links:
  pr: []
---
# Real
MD
  (cd "$d" && node .aai/scripts/spec-lint.mjs --slug-handles > lint-clean.log 2>&1) \
    || log_fail "must be clean once CHANGE-0036 exists as a doc: $(cat "$d/lint-clean.log")"
  rm -rf "$d"
  log_pass "TEST-008 slug-handles lint warns on unconfirmed handle, clean once the doc exists"
}

# =============================================================================
# TEST-009 (Spec-AC-07): coupled families union counter + one atomic push.
test_009_coupled_families_union() {
  log_info "TEST-009: coupled_families union (max 5, max 3 -> 6 for both); one atomic push creates both refs..."
  local d; d="$(mk_repo t009)"
  local bare="$TEST_DIR/origin-t009.git"
  printf 'coupled_families:\n  - FAMA+FAMB\n' > "$d/docs/ai/docs-audit.yaml"
  seed_numbered "$d" issues FAMA 5 change
  seed_numbered "$d" issues FAMB 3 change
  (cd "$d" && git add docs/ai/docs-audit.yaml && git commit -qm "docs: coupled_families config" >/dev/null)
  (cd "$d" && git checkout -q -b feature/nine)
  write_draft "$d" issues FAMA paired-topic
  (cd "$d" && git add docs/issues && git commit -qm "docs: draft" >/dev/null)
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs \
      --path docs/issues/FAMA-DRAFT-paired-topic.md --base-ref main > alloc.log 2>&1) \
    || log_fail "coupled allocation must exit 0: $(cat "$d/alloc.log")"
  assert_file "$d/docs/issues/FAMA-0006-paired-topic.md"
  ref_exists "$bare" "refs/aai/docnums/FAMA-0006" || log_fail "FAMA-0006 reservation ref must exist"
  ref_exists "$bare" "refs/aai/docnums/FAMB-0006" \
    || log_fail "FAMB-0006 reservation ref must ALSO exist (coupled union, one atomic push)"
  rm -rf "$d"
  log_pass "TEST-009 coupled union counter (6 for both); one atomic push created both refs"
}

# =============================================================================
# TEST-010 (Spec-AC-07): atomic all-or-nothing (direct unit test of the
# reserveAtomic primitive with two coupled members — see TEST-002 note on why
# this is a direct primitive test rather than a full-CLI race).
test_010_coupled_atomic_all_or_nothing() {
  log_info "TEST-010: one member ref pre-exists -> neither ref created at that number; pair retries together..."
  local d; d="$(mk_repo t010)"
  local bare="$TEST_DIR/origin-t010.git"
  push_raw_ref "$bare" "refs/aai/docnums/FAMB-0006" "racer-owns-famb-6"
  cat > "$d/probe.mjs" <<'EOF'
import { reserveAtomic } from './.aai/scripts/allocate-doc-number.mjs';
import assert from 'node:assert';
const r = reserveAtomic(process.cwd(), 'origin',
  [{ prefix: 'FAMA', width: 4 }, { prefix: 'FAMB', width: 4 }], 6, 50);
assert.strictEqual(r.ok, true, JSON.stringify(r));
assert.strictEqual(r.number, 7, 'must retry PAST 6 (one member taken) and land the PAIR on 7: ' + JSON.stringify(r));
console.log('ok');
EOF
  (cd "$d" && node probe.mjs) > "$d/probe.log" 2>&1 \
    || log_fail "TEST-010 atomic all-or-nothing incorrect: $(cat "$d/probe.log")"
  assert_contains "$d/probe.log" "ok"
  if ref_exists "$bare" "refs/aai/docnums/FAMA-0006"; then
    log_fail "FAMA-0006 must NEVER have been created (atomic all-or-nothing: FAMB-0006 was taken)"
  fi
  ref_exists "$bare" "refs/aai/docnums/FAMA-0007" || log_fail "FAMA-0007 must exist (the retried pair)"
  ref_exists "$bare" "refs/aai/docnums/FAMB-0007" || log_fail "FAMB-0007 must exist (the retried pair)"
  rm -rf "$d"
  log_pass "TEST-010 atomic all-or-nothing: neither ref at the colliding number, pair retried together"
}

# =============================================================================
# TEST-011 (Spec-AC-08): back-compat invariant — the existing SPEC-0015 suite
# stays green (D9). By design this test CANNOT be observed RED: it passes
# today and its evidentiary value is that it keeps passing after the change
# (regression guard, not new-behavior proof — see spec Test Plan RED-proof
# exception).
test_011_backcompat_suite() {
  log_info "TEST-011: existing tests/skills/test-aai-doc-numbering.sh suite stays green (D9 back-compat)..."
  (cd "$PROJECT_ROOT" && AAI_TEST_TIMEOUT=600 \
      bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-doc-numbering.sh \
      > "$TEST_DIR/backcompat.log" 2>&1)
  local rc=$?
  [[ "$rc" -eq 0 ]] \
    || log_fail "existing doc-numbering suite must stay green (D9): rc=$rc: $(tail -40 "$TEST_DIR/backcompat.log")"
  assert_contains "$TEST_DIR/backcompat.log" "All doc-numbering tests passed."
  log_pass "TEST-011 existing doc-numbering suite green (back-compat invariant, D9)"
}

# =============================================================================
# TEST-012 (Spec-AC-09): CI workflow wiring — deterministic grep assertions.
test_012_ci_wiring() {
  log_info "TEST-012: workflow passes PR base as --base-ref, has slug-handles lint step, enforce gate unchanged..."
  local wf="$PROJECT_ROOT/.github/workflows/docs-numbering.yml"
  assert_file "$wf"
  grep -qE '\-\-guard.*--base-ref|--base-ref.*--guard|base-ref.*allocate-doc-number' "$wf" \
    || log_fail "CI workflow must pass --base-ref to the allocator guard"
  grep -qF "github.base_ref" "$wf" \
    || log_fail "CI workflow must derive --base-ref from the PR target branch (github.base_ref)"
  grep -qF "spec-lint.mjs --slug-handles" "$wf" \
    || log_fail "CI workflow must run spec-lint --slug-handles"
  grep -qF "doc_number_guard" "$wf" \
    || log_fail "CI workflow enforce gate must still key off doc_number_guard"
  log_pass "TEST-012 CI wiring: --base-ref from PR target, slug-handles lint step, enforce gate intact"
}

# =============================================================================
# TEST-013 (Spec-AC-10): docs rows in TECHNOLOGY.md + USER_GUIDE.md.
test_013_docs_rows() {
  log_info "TEST-013: TECHNOLOGY.md + USER_GUIDE.md document reservation/marker/coupled_families/guard..."
  local tech="$PROJECT_ROOT/docs/TECHNOLOGY.md"
  local guide="$PROJECT_ROOT/docs/USER_GUIDE.md"
  assert_file "$tech"; assert_file "$guide"
  grep -qF "refs/aai/docnums" "$tech" || log_fail "TECHNOLOGY.md must document the reservation ref namespace"
  grep -qF "number_reserved" "$tech" || log_fail "TECHNOLOGY.md must document the number_reserved marker"
  grep -qF "coupled_families" "$tech" || log_fail "TECHNOLOGY.md must document coupled_families"
  grep -qF "refs/aai/docnums" "$guide" || log_fail "USER_GUIDE.md must document the reservation ref namespace"
  grep -qF "number_reserved" "$guide" || log_fail "USER_GUIDE.md must document the number_reserved marker"
  grep -qF "coupled_families" "$guide" || log_fail "USER_GUIDE.md must document coupled_families"
  grep -qiE "slug-handles" "$guide" || log_fail "USER_GUIDE.md must document the --slug-handles lint mode"
  log_pass "TEST-013 TECHNOLOGY.md + USER_GUIDE.md document the reservation protocol"
}

# =============================================================================
# TEST-014 (Seam S1): pre-commit host surfaces a NEW-predicate-only failure
# under doc_number_guard: enforce (the guards ride one wiring point).
test_014_seam_precommit_host() {
  log_info "TEST-014: pre-commit host blocks on the NEW predicate alone under doc_number_guard: enforce..."
  local d; d="$(mk_repo t014)"
  seed_numbered "$d" rfc RFC 4
  printf 'doc_number_guard: enforce\n' > "$d/docs/ai/docs-audit.yaml"
  cat > "$d/docs/issues/CHANGE-0005-epsilon.md" <<'MD'
---
id: epsilon
type: change
number: 5
status: draft
number_reserved: false
links:
  pr: []
---
# Epsilon (fully numbered, no DRAFT, no duplicate — ONLY the new predicate fires)
MD
  (cd "$d" && git add docs/issues/CHANGE-0005-epsilon.md docs/ai/docs-audit.yaml)
  set +e
  (cd "$d" && bash .aai/scripts/pre-commit-checks.sh > pc.log 2>&1)
  local rc=$?
  set -e
  [[ "$rc" -ne 0 ]] || log_fail "host must block on the unreserved-marker predicate under enforce"
  assert_contains "$d/pc.log" "CHANGE-0005-epsilon.md"
  assert_contains "$d/pc.log" "doc_number_guard: enforce"
  rm -rf "$d"
  log_pass "TEST-014 seam S1: pre-commit host surfaces the new-predicate-only failure under enforce"
}

# =============================================================================
# TEST-015 (Seam S3): docs-audit --check --strict raises no frontmatter
# finding for number_reserved: false.
test_015_seam_docs_audit_marker() {
  log_info "TEST-015: docs-audit --check --strict raises no finding for number_reserved: false..."
  local d; d="$(mk_repo t015 no)"
  cat > "$d/docs/issues/CHANGE-0005-provisional.md" <<'MD'
---
id: provisional
type: change
number: 5
status: draft
number_reserved: false
links:
  pr: []
---
# Provisional
MD
  set +e
  (cd "$d" && node .aai/scripts/docs-audit.mjs --check --strict --no-event \
      --path docs/issues/CHANGE-0005-provisional.md > audit.log 2>&1)
  local rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "docs-audit must not fail on number_reserved: false: rc=$rc: $(cat "$d/audit.log")"
  if grep -qi "number_reserved" "$d/audit.log"; then
    log_fail "docs-audit must raise no finding mentioning number_reserved: $(cat "$d/audit.log")"
  fi
  rm -rf "$d"
  log_pass "TEST-015 seam S3: docs-audit raises no frontmatter finding for number_reserved: false"
}

# =============================================================================
# TEST-016 (validation F1, post-implementation defect): two reservation
# attempts from the SAME HEAD (no intervening commit — the common case of two
# clones sharing an unmodified base tip) must NOT both "win" the same number.
# Pre-fix, `pushReservation` pushed `HEAD:<ref>`; when the ref already exists
# at that exact sha, git reports "Everything up-to-date" (exit 0) WITHOUT ever
# evaluating the create-only `--force-with-lease=<ref>:` — a silent false
# success (Validator attack 2a).
test_016_same_sha_retries_not_false_success() {
  log_info "TEST-016 (F1): second same-HEAD reservation attempt must retry, not silently re-win the number..."
  local d; d="$(mk_repo t016)"
  local bare="$TEST_DIR/origin-t016.git"
  cat > "$d/probe.mjs" <<'EOF'
import { reserveAtomic } from './.aai/scripts/allocate-doc-number.mjs';
import assert from 'node:assert';
const r1 = reserveAtomic(process.cwd(), 'origin', [{ prefix: 'CHANGE', width: 4 }], 50, 50);
assert.strictEqual(r1.ok, true, 'first reservation must succeed: ' + JSON.stringify(r1));
assert.strictEqual(r1.number, 50, 'first reservation must land on 50: ' + JSON.stringify(r1));
// Second allocator, SAME repo/HEAD (no intervening commit) — the ref from r1
// now pre-exists at the identical sha a naive re-push would send.
const r2 = reserveAtomic(process.cwd(), 'origin', [{ prefix: 'CHANGE', width: 4 }], 50, 50);
assert.strictEqual(r2.ok, true, 'second reservation must eventually succeed: ' + JSON.stringify(r2));
assert.strictEqual(r2.number, 51,
  'second reservation must be REJECTED on the same-sha collision and retry to 51, not silently re-report 50 (F1): '
  + JSON.stringify(r2));
console.log('ok');
EOF
  (cd "$d" && node probe.mjs) > "$d/probe.log" 2>&1 \
    || log_fail "TEST-016 same-sha false-success (F1): $(cat "$d/probe.log")"
  assert_contains "$d/probe.log" "ok"
  ref_exists "$bare" "refs/aai/docnums/CHANGE-0050" || log_fail "CHANGE-0050 (first reservation) must exist"
  ref_exists "$bare" "refs/aai/docnums/CHANGE-0051" || log_fail "CHANGE-0051 (retried second reservation) must exist"
  rm -rf "$d"
  log_pass "TEST-016 same-sha reservation attempt correctly rejected and retried (F1 fixed)"
}

# =============================================================================
# TEST-017 (validation F1 coupled variant): same-HEAD retry with a coupled
# family — pre-fix, one member's same-sha no-op let the WHOLE atomic push
# report success, landing both refs a second time at the same number
# (Validator attack 2e).
test_017_coupled_same_sha_neither_lands() {
  log_info "TEST-017 (F1 coupled): second same-HEAD coupled reservation must retry the PAIR, not false-succeed..."
  local d; d="$(mk_repo t017)"
  local bare="$TEST_DIR/origin-t017.git"
  cat > "$d/probe.mjs" <<'EOF'
import { reserveAtomic } from './.aai/scripts/allocate-doc-number.mjs';
import assert from 'node:assert';
const members = [{ prefix: 'FAMA', width: 4 }, { prefix: 'FAMB', width: 4 }];
const r1 = reserveAtomic(process.cwd(), 'origin', members, 50, 50);
assert.strictEqual(r1.ok, true, JSON.stringify(r1));
assert.strictEqual(r1.number, 50, JSON.stringify(r1));
const r2 = reserveAtomic(process.cwd(), 'origin', members, 50, 50);
assert.strictEqual(r2.ok, true, JSON.stringify(r2));
assert.strictEqual(r2.number, 51,
  'coupled retry must land the PAIR on 51, not silently re-win 50 for either member (F1): ' + JSON.stringify(r2));
console.log('ok');
EOF
  (cd "$d" && node probe.mjs) > "$d/probe.log" 2>&1 \
    || log_fail "TEST-017 coupled same-sha false-success (F1): $(cat "$d/probe.log")"
  assert_contains "$d/probe.log" "ok"
  ref_exists "$bare" "refs/aai/docnums/FAMA-0051" || log_fail "FAMA-0051 (retried pair) must exist"
  ref_exists "$bare" "refs/aai/docnums/FAMB-0051" || log_fail "FAMB-0051 (retried pair) must exist"
  rm -rf "$d"
  log_pass "TEST-017 coupled same-sha reservation correctly retried as a pair (F1 fixed)"
}

# =============================================================================
# TEST-018 (validation F2): a permission-denied / unpacker-error push failure
# (read-only bare origin — NOT an unreachable path, which TEST-005 already
# covers) must fall through to the D4 provisional path (number_reserved:
# false + WARNING + exit 0), never the 50-attempt retry storm ending in
# die(4) (Validator attack 2c permission variant).
test_018_readonly_origin_provisional_no_retry_storm() {
  log_info "TEST-018 (F2): permission-denied origin -> provisional marker + exit 0, no retry storm..."
  local d; d="$(mk_repo t018 no)"
  local bare="$TEST_DIR/origin-t018-ro.git"
  git init -q --bare "$bare"
  chmod -R a-w "$bare"
  (cd "$d" && git remote add origin "$bare")
  (cd "$d" && git checkout -q -b feature/eighteen)
  write_draft "$d" rfc RFC readonly-topic
  (cd "$d" && git add docs/rfc && git commit -qm "docs: draft" >/dev/null)
  local start_ts end_ts elapsed rc
  start_ts=$(date +%s)
  set +e
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs \
      --path docs/rfc/RFC-DRAFT-readonly-topic.md --base-ref main > alloc.log 2>&1)
  rc=$?
  set -e
  end_ts=$(date +%s)
  chmod -R u+w "$bare"
  [[ "$rc" -eq 0 ]] \
    || log_fail "read-only-origin push failure must still exit 0 (F2 fail-open, got $rc): $(cat "$d/alloc.log")"
  local out="$d/docs/rfc/RFC-0001-readonly-topic.md"
  assert_file "$out"
  grep -qE '^number_reserved:[[:space:]]*false[[:space:]]*$' "$out" \
    || log_fail "permission-denied push must stamp number_reserved: false (F2), not silently drop the marker"
  assert_contains "$d/alloc.log" "WARNING"
  elapsed=$(( end_ts - start_ts ))
  [[ "$elapsed" -le 20 ]] \
    || log_fail "must not retry-storm on a non-collision failure (F2): took ${elapsed}s (50 futile retries pre-fix)"
  rm -rf "$d" "$bare"
  log_pass "TEST-018 permission-denied origin: provisional marker + WARNING + exit 0, no retry storm (F2 fixed)"
}

# =============================================================================
# TEST-101 (Spec-AC-01): full-CLI allocation rewrites the DRAFT ref to the
# numbered basename across every newly-scanned committed-class tree (product,
# reviews, sessions, knowledge, root README/CHANGELOG). Also exercises the
# degenerate/empty-collection shape (a same-tree file with NO draft reference
# must stay untouched — the unchanged-guard path) as a negative control.
test_101_widen_rewrite_scan() {
  log_info "TEST-101: full-CLI allocation rewrites refs in product, reviews, sessions, knowledge, root README/CHANGELOG..."
  local d; d="$(mk_repo t101)"
  (cd "$d" && git checkout -q -b feature/101)
  write_draft "$d" rfc RFC widen-topic
  local old="RFC-DRAFT-widen-topic" new="RFC-0001-widen-topic"
  printf '# Product doc\nSee %s for details.\n' "$old" > "$d/docs/product/uses-draft.md"
  printf '# Review\nRefs %s.\n' "$old" > "$d/docs/ai/reviews/review-widen.md"
  printf '# Session\nDiscussed %s.\n' "$old" > "$d/docs/project-sessions/2026-07-27-widen.md"
  printf '# Knowledge\nLink to %s.\n' "$old" > "$d/docs/knowledge/widen-notes.md"
  printf '# README\nSee %s.\n' "$old" > "$d/README.md"
  printf '# Changelog\n- Added %s.\n' "$old" > "$d/CHANGELOG.md"
  # negative control / degenerate case: a product doc with NO draft reference.
  printf '# Unrelated\nNothing to see here.\n' > "$d/docs/product/unrelated.md"
  local unrelated_before
  unrelated_before="$(shasum -a 256 "$d/docs/product/unrelated.md" | awk '{print $1}')"
  (cd "$d" && git add -A && git commit -qm "docs: draft + references" >/dev/null)
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs \
      --path docs/rfc/RFC-DRAFT-widen-topic.md --base-ref main > alloc.log 2>&1) \
    || log_fail "allocation must exit 0: $(cat "$d/alloc.log")"
  assert_file "$d/docs/rfc/RFC-0001-widen-topic.md"
  for f in docs/product/uses-draft.md docs/ai/reviews/review-widen.md \
           docs/project-sessions/2026-07-27-widen.md docs/knowledge/widen-notes.md \
           README.md CHANGELOG.md; do
    assert_contains "$d/$f" "$new"
    assert_not_contains "$d/$f" "$old"
  done
  local unrelated_after
  unrelated_after="$(shasum -a 256 "$d/docs/product/unrelated.md" | awk '{print $1}')"
  [[ "$unrelated_before" == "$unrelated_after" ]] \
    || log_fail "a same-tree file with no draft reference must stay byte-identical (unchanged guard)"
  rm -rf "$d"
  log_pass "TEST-101 widened rewrite scan: all six newly-scanned trees rewritten; unrelated file untouched"
}

# =============================================================================
# TEST-102 (Spec-AC-01, seam S2): self-reference in the renamed draft body is
# rewritten after the rename (the just-renamed file lives in a scanned dir).
test_102_self_reference_seam_s2() {
  log_info "TEST-102: self-reference in the renamed draft body is rewritten (seam S2)..."
  local d; d="$(mk_repo t102)"
  (cd "$d" && git checkout -q -b feature/102)
  local slug="self-ref-topic"
  cat > "$d/docs/rfc/RFC-DRAFT-$slug.md" <<MD
---
id: $slug
type: rfc
number: null
status: draft
links:
  pr: []
---
# Draft: $slug
See also RFC-DRAFT-$slug.md for the canonical link.
MD
  (cd "$d" && git add docs/rfc && git commit -qm "docs: self-referencing draft" >/dev/null)
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs \
      --path "docs/rfc/RFC-DRAFT-$slug.md" --base-ref main > alloc.log 2>&1) \
    || log_fail "allocation must exit 0: $(cat "$d/alloc.log")"
  local out="$d/docs/rfc/RFC-0001-$slug.md"
  assert_file "$out"
  assert_contains "$out" "RFC-0001-$slug.md"
  assert_not_contains "$out" "RFC-DRAFT-$slug.md"
  rm -rf "$d"
  log_pass "TEST-102 seam S2: self-reference in the renamed draft body rewritten"
}

# =============================================================================
# TEST-103 (Spec-AC-02): excluded fixture files (docs/archive, and
# docs/ai/reports nested BESIDE the scanned docs/ai/reviews) stay byte-
# identical, even though they carry the exact DRAFT token (negative control:
# the token must NOT trigger a rewrite in an excluded tree).
test_103_excluded_trees_byte_identical() {
  log_info "TEST-103: excluded fixture files (docs/archive, docs/ai/reports beside docs/ai/reviews) byte-identical..."
  local d; d="$(mk_repo t103)"
  (cd "$d" && git checkout -q -b feature/103)
  write_draft "$d" rfc RFC excl-topic
  local old="RFC-DRAFT-excl-topic"
  printf '# Archived\nStale ref %s.\n' "$old" > "$d/docs/archive/stale.md"
  printf '# Report spool\nStale ref %s.\n' "$old" > "$d/docs/ai/reports/spool.md"
  (cd "$d" && git add -A && git commit -qm "docs: draft + excluded fixtures" >/dev/null)
  local before_archive before_reports
  before_archive="$(shasum -a 256 "$d/docs/archive/stale.md" | awk '{print $1}')"
  before_reports="$(shasum -a 256 "$d/docs/ai/reports/spool.md" | awk '{print $1}')"
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs \
      --path docs/rfc/RFC-DRAFT-excl-topic.md --base-ref main > alloc.log 2>&1) \
    || log_fail "allocation must exit 0: $(cat "$d/alloc.log")"
  local after_archive after_reports
  after_archive="$(shasum -a 256 "$d/docs/archive/stale.md" | awk '{print $1}')"
  after_reports="$(shasum -a 256 "$d/docs/ai/reports/spool.md" | awk '{print $1}')"
  [[ "$before_archive" == "$after_archive" ]] || log_fail "docs/archive fixture must be byte-identical after allocation"
  [[ "$before_reports" == "$after_reports" ]] \
    || log_fail "docs/ai/reports fixture (nested beside scanned docs/ai/reviews) must be byte-identical after allocation"
  assert_contains "$d/docs/archive/stale.md" "$old"
  assert_contains "$d/docs/ai/reports/spool.md" "$old"
  rm -rf "$d"
  log_pass "TEST-103 excluded trees byte-identical; nested docs/ai/reports beside scanned docs/ai/reviews untouched"
}

# =============================================================================
# TEST-104 (Spec-AC-03): a second allocation run is a clean no-op (no DRAFT
# remains); every rewrite-tree file is sha-unchanged between run1-after and
# run2-after (fully-covered / zero-remainder shape).
test_104_idempotent_second_run() {
  log_info "TEST-104: second allocation run is a no-op; rewrite-tree files sha-unchanged run1-after vs run2-after..."
  local d; d="$(mk_repo t104)"
  (cd "$d" && git checkout -q -b feature/104)
  write_draft "$d" rfc RFC idem-topic
  local old="RFC-DRAFT-idem-topic"
  printf '# Product\nSee %s.\n' "$old" > "$d/docs/product/idem.md"
  (cd "$d" && git add -A && git commit -qm "docs: draft + ref" >/dev/null)
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs \
      --path docs/rfc/RFC-DRAFT-idem-topic.md --base-ref main > alloc1.log 2>&1) \
    || log_fail "first allocation must exit 0: $(cat "$d/alloc1.log")"
  local sha_after1
  sha_after1="$(shasum -a 256 "$d/docs/product/idem.md" | awk '{print $1}')"
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs --all --base-ref main > alloc2.log 2>&1) \
    || log_fail "second allocation must exit 0: $(cat "$d/alloc2.log")"
  assert_contains "$d/alloc2.log" "nothing to do"
  local sha_after2
  sha_after2="$(shasum -a 256 "$d/docs/product/idem.md" | awk '{print $1}')"
  [[ "$sha_after1" == "$sha_after2" ]] \
    || log_fail "docs/product fixture must be sha-unchanged between run1-after and run2-after"
  rm -rf "$d"
  log_pass "TEST-104 idempotent second run: no-op, rewrite-tree file sha-unchanged"
}

# =============================================================================
# TEST-105 (Spec-AC-04): --dry-run reports the planned per-tree rewrite set
# and writes nothing; every fixture file (draft and reference) stays byte-
# identical to its pre-run state; the DRAFT file is still present.
test_105_dry_run_reports_and_no_write() {
  log_info "TEST-105: dry-run reports planned per-tree rewrites and writes nothing; DRAFT still present..."
  local d; d="$(mk_repo t105)"
  (cd "$d" && git checkout -q -b feature/105)
  write_draft "$d" rfc RFC dryrun-topic
  local old="RFC-DRAFT-dryrun-topic"
  printf '# Product\nSee %s.\n' "$old" > "$d/docs/product/dry.md"
  (cd "$d" && git add -A && git commit -qm "docs: draft + ref" >/dev/null)
  local before_product before_draft
  before_product="$(shasum -a 256 "$d/docs/product/dry.md" | awk '{print $1}')"
  before_draft="$(shasum -a 256 "$d/docs/rfc/RFC-DRAFT-dryrun-topic.md" | awk '{print $1}')"
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs \
      --path docs/rfc/RFC-DRAFT-dryrun-topic.md --base-ref main --dry-run > dry.log 2>&1) \
    || log_fail "dry-run must exit 0: $(cat "$d/dry.log")"
  assert_contains "$d/dry.log" "docs/product"
  assert_contains "$d/dry.log" "dry.md"
  assert_file "$d/docs/rfc/RFC-DRAFT-dryrun-topic.md"
  [[ ! -f "$d/docs/rfc/RFC-0001-dryrun-topic.md" ]] || log_fail "dry-run must not rename the draft"
  local after_product after_draft
  after_product="$(shasum -a 256 "$d/docs/product/dry.md" | awk '{print $1}')"
  after_draft="$(shasum -a 256 "$d/docs/rfc/RFC-DRAFT-dryrun-topic.md" | awk '{print $1}')"
  [[ "$before_product" == "$after_product" ]] || log_fail "dry-run must not write the docs/product fixture"
  [[ "$before_draft" == "$after_draft" ]] || log_fail "dry-run must not touch the DRAFT file"
  rm -rf "$d"
  log_pass "TEST-105 dry-run reports planned per-tree rewrites; writes nothing; DRAFT still present"
}

# =============================================================================
# TEST-106 (Spec-AC-05): a probe imports REWRITE_TREES and EXCLUDED_TREES and
# asserts membership (structural teeth — a single exported constant, not a
# second matcher).
test_106_rewrite_trees_constants_probe() {
  log_info "TEST-106: probe imports REWRITE_TREES/EXCLUDED_TREES and asserts membership..."
  local d; d="$(mk_repo t106 no)"
  cat > "$d/probe.mjs" <<'EOF'
// Namespace import (not a named import) so a not-yet-exported constant
// surfaces as the probe's OWN assert.ok failure (RED_CLASS: product_red)
// rather than an ESM SyntaxError at module-load time (which would die before
// any assertion ran and classify as infra_fail).
import * as mod from './.aai/scripts/allocate-doc-number.mjs';
import assert from 'node:assert';
assert.ok(Array.isArray(mod.REWRITE_TREES),
  'REWRITE_TREES must be an exported array (got: ' + typeof mod.REWRITE_TREES + ')');
assert.ok(Array.isArray(mod.EXCLUDED_TREES),
  'EXCLUDED_TREES must be an exported array (got: ' + typeof mod.EXCLUDED_TREES + ')');
assert.ok(mod.REWRITE_TREES.includes('docs/product'), 'REWRITE_TREES must include docs/product');
assert.ok(mod.EXCLUDED_TREES.includes('docs/archive'), 'EXCLUDED_TREES must include docs/archive');
assert.ok(mod.EXCLUDED_TREES.includes('docs/ai/reports'), 'EXCLUDED_TREES must include docs/ai/reports');
console.log('ok');
EOF
  (cd "$d" && node probe.mjs) > "$d/probe.log" 2>&1 \
    || log_fail "TEST-106 constants probe failed: $(cat "$d/probe.log")"
  assert_contains "$d/probe.log" "ok"
  rm -rf "$d"
  log_pass "TEST-106 REWRITE_TREES/EXCLUDED_TREES exported and carry the expected membership"
}

# =============================================================================
# TEST-107 (Spec-AC-06): existing allocation/collision/guard suites pass
# unchanged (regression guard). Exempt from RED-proof by design (spec Test
# Plan): it passes today and its evidentiary value is staying green.
test_107_regression_doc_numbering_suite() {
  log_info "TEST-107: existing allocation/collision/guard suites pass unchanged (regression)..."
  (cd "$PROJECT_ROOT" && AAI_TEST_TIMEOUT=600 \
      bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-doc-numbering.sh \
      > "$TEST_DIR/regression-107.log" 2>&1)
  local rc=$?
  [[ "$rc" -eq 0 ]] \
    || log_fail "doc-numbering suite must stay green (Spec-AC-06): rc=$rc: $(tail -40 "$TEST_DIR/regression-107.log")"
  assert_contains "$TEST_DIR/regression-107.log" "All doc-numbering tests passed."
  log_pass "TEST-107 existing doc-numbering suite green (regression guard)"
}

# =============================================================================
# TEST-108 (Spec-AC-07): targeted allocator suites are green locally; PR CI
# full framework is the authoritative gate. Like TEST-107, this is a
# suite-level meta-assertion (not new allocator behavior), so it is treated
# as regression-shaped and exempt from a standalone RED-proof: its real
# evidence is the exit code of THIS suite's own run (TEST-101..107 above),
# which the outer test harness (aai-run-tests.sh) observes. This function
# adds a deterministic, non-recursive wiring check (both targeted suite files
# present, syntactically valid, and executable) rather than re-invoking this
# same suite file from within itself, which would recurse without bound.
test_108_targeted_suites_wiring() {
  log_info "TEST-108: targeted allocator suites are present and syntactically valid (Spec-AC-07)..."
  local this_suite="$PROJECT_ROOT/tests/skills/test-aai-doc-number-reservation.sh"
  local sibling_suite="$PROJECT_ROOT/tests/skills/test-aai-doc-numbering.sh"
  assert_file "$this_suite"
  assert_file "$sibling_suite"
  # Both suites are invoked as `bash <path>` (see TEST-107 / aai-run-tests.sh),
  # not executed directly, so only readability + syntax validity are asserted
  # — no execute-bit requirement (test-aai-doc-numbering.sh legitimately ships
  # without one).
  [[ -r "$this_suite" ]] || log_fail "this suite must be readable"
  [[ -r "$sibling_suite" ]] || log_fail "the sibling doc-numbering suite must be readable"
  bash -n "$this_suite" || log_fail "this suite must be syntactically valid bash"
  bash -n "$sibling_suite" || log_fail "the sibling doc-numbering suite must be syntactically valid bash"
  log_pass "TEST-108 targeted allocator suites present and syntactically valid; PR CI full framework remains authoritative"
}


# TEST-109 (review NB-1, PR allocator-rewrite-all-trees): the isExcludedTree
# separator guard is load-bearing in COMMITTED coverage — no excluded tree is
# nested under a scanned root in the real repo, so TEST-103 alone would pass
# even with a no-op guard. Probe the exported predicate directly: exact tree,
# nested file, separator guard (reports vs reports-extra), non-excluded root.
test_109_excluded_guard_unit_probe() {
  log_info "TEST-109: isExcludedTree unit probe (nested, separator guard, negatives)..."
  local out
  out="$(node --input-type=module -e "
    import { isExcludedTree } from '$PROJECT_ROOT/.aai/scripts/allocate-doc-number.mjs';
    const cases = [
      ['docs/ai/reports/spool.md', true],
      ['docs/ai/reports', true],
      ['docs/ai/reports-extra/file.md', false],
      ['docs/archive/deep/nested/old.md', true],
      ['docs/knowledge/FACTS.md', false],
      ['docs/product/x.md', false],
    ];
    let bad = 0;
    for (const [rel, want] of cases) {
      const got = isExcludedTree(rel);
      if (got !== want) { console.log('MISMATCH ' + rel + ' got=' + got + ' want=' + want); bad++; }
    }
    console.log(bad === 0 ? 'PROBE_OK' : 'PROBE_FAIL');
  " 2>&1)" || log_fail "TEST-109: probe execution failed: $out"
  [[ "$out" == *PROBE_OK* ]] || log_fail "TEST-109: guard probe mismatches: $out"
  log_pass "TEST-109 isExcludedTree guard probe (nested + separator + negatives)"
}

main() {
  echo ""
  echo "AAI Doc-Number Reservation Test Suite (CHANGE-0035 / SPEC-0047)"
  echo "================================================================="
  echo ""
  check_deps
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-doc-number-reservation-test.XXXXXX")"

  test_001_reservation_before_rename
  test_002_retry_on_rejection
  test_003_origin_side_branch_scanned
  test_004_naked_reservation_ref_taken
  test_005_offline_fallback_marker
  test_006_guard_cross_branch_collision
  test_007_guard_marker_and_reserve_completion
  test_008_slug_handles_lint
  test_009_coupled_families_union
  test_010_coupled_atomic_all_or_nothing
  test_011_backcompat_suite
  test_012_ci_wiring
  test_013_docs_rows
  test_014_seam_precommit_host
  test_015_seam_docs_audit_marker
  test_016_same_sha_retries_not_false_success
  test_017_coupled_same_sha_neither_lands
  test_018_readonly_origin_provisional_no_retry_storm
  test_101_widen_rewrite_scan
  test_102_self_reference_seam_s2
  test_103_excluded_trees_byte_identical
  test_109_excluded_guard_unit_probe
  test_104_idempotent_second_run
  test_105_dry_run_reports_and_no_write
  test_106_rewrite_trees_constants_probe
  test_107_regression_doc_numbering_suite
  test_108_targeted_suites_wiring

  echo ""
  echo "All doc-number-reservation tests passed."
}

# Only auto-run when EXECUTED directly (bash test-aai-doc-number-reservation.sh).
# Sourcing this file (e.g. `source ... ; test_101_widen_rewrite_scan`) lets a
# single TEST-xxx run in isolation for RED/GREEN evidence capture without
# tripping the earlier tests' `set -e`-fatal `log_fail`.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
