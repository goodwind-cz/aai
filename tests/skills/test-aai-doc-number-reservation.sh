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
# Companion suites are declared in suite-map.yaml, not run nested
# (nested-suite-reruns-duplicate-sweep-time).
# shellcheck source=lib/companion-assert.sh
. "$SCRIPT_DIR/lib/companion-assert.sh"
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
  assert_companions aai-doc-number-reservation aai-doc-numbering \
    || log_fail "TEST-011 (plan row TEST-024): aai-doc-numbering must be selected with aai-doc-number-reservation"
  log_pass "TEST-011 existing doc-numbering suite is selected with this suite (back-compat invariant, D9)"
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
  assert_companions aai-doc-number-reservation aai-doc-numbering \
    || log_fail "TEST-107 (plan row TEST-024): aai-doc-numbering must be selected with aai-doc-number-reservation"
  log_pass "TEST-107 existing doc-numbering suite is selected with this suite (regression guard)"
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


# RFC-0016 B transport seam. Every probe uses real objects and bare refs;
# only the named transport call is recorded/stalled/refused by the shim.
transport_probe() {
  local scenario="$1" d real_git
  d="$(mk_repo "transport-$scenario")"
  real_git="$(command -v git)"
  TRANSPORT_SCENARIO="$scenario" TRANSPORT_REAL_GIT="$real_git" \
    TRANSPORT_ROOT="$PROJECT_ROOT" node --input-type=module - "$d" <<'JS'
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync, spawn } from 'node:child_process';
import { pathToFileURL } from 'node:url';
const d = process.argv[2], scenario = process.env.TRANSPORT_SCENARIO;
const real = process.env.TRANSPORT_REAL_GIT;
const bare = path.join(path.dirname(d), `origin-transport-${scenario}.git`);
const git = (...args) => execFileSync(real, args, {cwd:d, encoding:'utf8', stdio:['ignore','pipe','pipe']}).trim();
const refs = () => git('ls-remote', 'origin', 'refs/aai/docnums/*').split('\n').filter(Boolean);
const ref = (prefix,n) => `refs/aai/docnums/${prefix}-${String(n).padStart(4,'0')}`;
const shaAt = name => git('ls-remote','origin',name).split(/\s/)[0];
const members = [{prefix:'RFC',width:4}];
const pair = [{prefix:'FAMA',width:4},{prefix:'FAMB',width:4}];
const head = git('rev-parse','HEAD');
git('push','origin','HEAD:refs/heads/main');
fs.mkdirSync(path.join(d,'bin'));
const log = path.join(d,'argv.jsonl');
fs.writeFileSync(path.join(d,'bin/git'), `#!${process.execPath}\n` + String.raw`
const fs = require('node:fs'), cp = require('node:child_process');
const args = process.argv.slice(2), env = process.env;
if (['push','fetch','ls-remote'].includes(args[0])) fs.appendFileSync(env.TRANSPORT_LOG, JSON.stringify(args)+'\n');
const match = args[0] === env.TRANSPORT_MATCH && (!env.TRANSPORT_FETCH_KIND || (env.TRANSPORT_FETCH_KIND === 'base' ? args.length === 3 : args.length === 2));
if (match && env.TRANSPORT_MODE === 'stall') {
  fs.writeFileSync(env.TRANSPORT_TIMING,JSON.stringify({pid:process.pid,started:Date.now()}));
  process.stderr.write(env.TRANSPORT_STALE === 'yes' ? '! [rejected] candidate (stale info)\n' : 'transport stalled\n');
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,3500);
  process.exit(1);
}
if (match && env.TRANSPORT_MODE === 'fail') { process.stderr.write(env.TRANSPORT_ERROR); process.exit(1); }
const r = cp.spawnSync(env.TRANSPORT_REAL_GIT,args,{stdio:'inherit'});
process.exit(r.status ?? 1);
`);
fs.chmodSync(path.join(d,'bin/git'),0o755);
const originalPath = process.env.PATH;
Object.assign(process.env, {PATH:path.join(d,'bin')+path.delimiter+originalPath,
  TRANSPORT_LOG:log, TRANSPORT_TIMING:path.join(d,'timing.json'), AAI_DOCNUM_NETWORK_TIMEOUT_MS:'1000'});
const calls = () => fs.existsSync(log) ? fs.readFileSync(log,'utf8').trim().split('\n').filter(Boolean).map(JSON.parse) : [];
const clear = () => { fs.writeFileSync(log,''); for (const k of ['TRANSPORT_MODE','TRANSPORT_MATCH','TRANSPORT_ERROR','TRANSPORT_FETCH_KIND','TRANSPORT_STALE']) delete process.env[k]; fs.rmSync(process.env.TRANSPORT_TIMING,{force:true}); };
const {reserveAtomic, reservationRef} = await import(pathToFileURL(path.join(d,'.aai/scripts/allocate-doc-number.mjs')));
const reserve = (ms=members,n=1,cap=3) => reserveAtomic(d,'origin',ms,n,cap);
const cli = (args,extra={}) => spawnSync(process.execPath,['.aai/scripts/allocate-doc-number.mjs',...args],
  {cwd:d,encoding:'utf8',env:{...process.env,...extra},timeout:15000});
const output = r => (r.stdout??'')+(r.stderr??'');
// Measure the stalled subprocess itself: allocation also performs local scans
// and regeneration, which are intentionally outside the network deadline.
const cliStall = args => new Promise(resolve => {
  let stdout='', stderr='', elapsed;
  const child=spawn(process.execPath,['.aai/scripts/allocate-doc-number.mjs',...args],{cwd:d,env:process.env});
  child.stdout.on('data',v=>{stdout+=v;}); child.stderr.on('data',v=>{stderr+=v;});
  const timer=setInterval(()=>{
    if(elapsed!==undefined || !fs.existsSync(process.env.TRANSPORT_TIMING)) return;
    const t=JSON.parse(fs.readFileSync(process.env.TRANSPORT_TIMING,'utf8'));
    try {process.kill(t.pid,0);} catch {elapsed=Date.now()-t.started;}
  },10);
  child.on('close',status=>{clearInterval(timer);resolve({status,stdout,stderr,elapsed});});
});
const draft = slug => { const rel=path.posix.join('docs','rfc',`RFC-DRAFT-${slug}.md`); fs.writeFileSync(path.join(d,rel),`---\nid: ${slug}\ntype: rfc\nnumber: null\nstatus: draft\n---\n# ${slug}\n`); return rel; };
const provisional = (slug,n) => { const rel=path.posix.join('docs','rfc',`RFC-${String(n).padStart(4,'0')}-${slug}.md`); fs.writeFileSync(path.join(d,rel),`---\nid: ${slug}\ntype: rfc\nnumber: ${n}\nnumber_reserved: false\nstatus: draft\n---\n# ${slug}\n`); return rel; };
const check = (v,message) => assert.ok(v,`TEST-${scenario}: ${message}`);
console.log(`TEST-${scenario} before=${JSON.stringify(refs())} node=${process.version} platform=${process.platform}`);
if (scenario === '201') {
  git('--git-dir='+bare,'config','receive.advertiseAtomic','false');
  let r=reserve(); check(r.ok,'singleton must reserve on real non-atomic server');
  const first=shaAt(ref('RFC',1)); check(first && first!==head,'reservation must use unique object, not HEAD');
  r=reserve(members,1); check(r.ok && r.number===2,'existing singleton must retry next number');
  check(shaAt(ref('RFC',2))!==first,'each attempt needs a new object');
  const pushes=calls().filter(a=>a[0]==='push'); check(pushes.length===3,'one success and collision then success');
  for (const a of pushes) {check(!a.includes('--atomic'),'singleton argv omits --atomic'); check(a.some(v=>/^--force-with-lease=refs\/aai\/docnums\/RFC-\d+:$/.test(v)),'empty expected-value lease');}
} else if (scenario === '202') {
  let r=reserve(pair,1); check(r.ok,'coupled supported success'); check(refs().length===2,'both coupled refs exist');
  git('push','origin',`HEAD:${ref('FAMA',2)}`); clear();
  r=reserve(pair,2); check(r.ok && r.number===3,'pair retries collision together');
  check(!shaAt(ref('FAMB',2)),'unclaimed peer absent at collided number');
  check(shaAt(ref('FAMA',3)) && shaAt(ref('FAMB',3)),'retried pair exists');
  const pushes=calls().filter(a=>a[0]==='push'); check(pushes.length===2,'two coupled attempts');
  check(pushes.every(a=>a.includes('--atomic')),'coupled argv always requires --atomic');
} else if (scenario === '203') {
  git('--git-dir='+bare,'config','receive.advertiseAtomic','false');
  const r=reserve(pair); check(!r.ok && !r.collision,'unsupported coupled push refuses as non-collision');
  check(refs().length===0,'unsupported coupled writes zero refs');
  check(calls().filter(a=>a[0]==='push').length===1,'no split fallback or retries');
  check(/unsupported.atomic/i.test(r.error) && /server|support/i.test(r.error),'unsupported category with server remedy');
} else if (scenario === '204') {
  const failures=[];
  for (const [operation,kind] of [['push',''],['ls-remote',''],['fetch','base'],['fetch','candidate']]) {
    clear(); Object.assign(process.env,{TRANSPORT_MODE:'stall',TRANSPORT_MATCH:operation,TRANSPORT_FETCH_KIND:kind,AAI_DOCNUM_NETWORK_TIMEOUT_MS:'500'});
    const begin=Date.now(); let text, elapsed;
    if(operation==='push') {const r=reserve(); text=r.error??''; elapsed=Date.now()-begin; check(!r.ok && !r.collision,'timeout is non-collision');}
    else {const rel=draft('stall-'+(kind||operation)); const r=await cliStall(['--path',rel,'--base-ref',kind==='base'?'origin/main':'main']); check(r.status===0,'scan/fetch failure keeps fallback contract'); text=output(r); elapsed=r.elapsed;}
    const total=Date.now()-begin, attempted=calls().filter(a=>a[0]===operation && (!kind || (kind==='base'?a.length===3:a.length===2))).length;
    console.log(`TEST-204 operation=${operation} kind=${kind} deadline_ms=500 elapsed_ms=${elapsed} total_cli_ms=${total} attempts=${attempted} diagnostic=${text}`);
    if(elapsed===undefined || elapsed>2500 || !text.includes(operation) || !/timeout/i.test(text) || !text.includes('500')) failures.push(`${operation}/${kind}: bounded operation-specific timeout missing (${elapsed} ms)`);
    check(attempted===1,'stalled operation attempted once');
  }
  clear(); process.env.AAI_DOCNUM_NETWORK_TIMEOUT_MS='1000'; const quick=Date.now(); check(reserve(members,50).ok,'quick negative control succeeds'); check(Date.now()-quick<2500,'quick operation is bounded');
  for(const value of ['0','-1','NaN','Infinity','300001','1.5','']) {
    const rel=provisional('bad-'+(value||'empty'),60); const r=cli(['--reserve','--path',rel],{AAI_DOCNUM_NETWORK_TIMEOUT_MS:value});
    check(/invalid.*AAI_DOCNUM_NETWORK_TIMEOUT_MS.*30000/i.test(output(r)),'invalid override visibly retains finite default: '+value);
  }
  check(failures.length===0,failures.join('; '));
} else if (scenario === '205') {
  const errors=[['unknown','fatal: requested URL returned HTTP 303','inspect'],
    ['permission','fatal: requested URL returned HTTP 401','access'],
    ['permission','fatal: requested URL returned HTTP 403','access'],
    ['permission','remote: permission denied\n! [remote rejected] x (unpacker error)','access'],
    ['connectivity','fatal: Could not resolve host: example.invalid','connect'],
    ['unsupported-atomic','fatal: the receiving end does not support --atomic push','server'],
    ['unknown','remote: hook declined\n! [remote rejected] x (unpacker error)','inspect']];
  for(const [category,message,remedy] of errors) {
    clear(); Object.assign(process.env,{TRANSPORT_MODE:'fail',TRANSPORT_MATCH:'push',TRANSPORT_ERROR:message});
    const r=reserve(); console.log(`TEST-205 category=${category} result=${JSON.stringify(r)} attempts=${calls().filter(a=>a[0]==='push').length}`);
    check(!r.ok && !r.collision,'non-collision rejection must not retry');
    check(calls().filter(a=>a[0]==='push').length===1,'non-collision attempts exactly once');
    check(r.error.includes(category) && r.error.toLowerCase().includes(remedy),'category and concrete remedy: '+category);
  }
  clear(); Object.assign(process.env,{TRANSPORT_MODE:'stall',TRANSPORT_MATCH:'push',TRANSPORT_STALE:'yes',AAI_DOCNUM_NETWORK_TIMEOUT_MS:'500'});
  const r=reserve(); check(!r.ok && !r.collision && /timeout/i.test(r.error),'timeout outranks partial stale info');
  check(/unknown|uncertain/i.test(r.error) && /inspect/i.test(r.error),'timeout warns remote outcome uncertain and inspection');
  check(calls().filter(a=>a[0]==='push').length===1,'timeout attempts exactly once');
  clear(); process.env.AAI_DOCNUM_NETWORK_TIMEOUT_MS='1000'; git('push','origin',`HEAD:${ref('RFC',1)}`); clear();
  const collided=reserve(); check(collided.ok && collided.number===2,'real lease rejection alone retries');
  check(calls().filter(a=>a[0]==='push').length===2,'real stale info has two attempts');
} else if (scenario === '206') {
  git('--git-dir='+bare,'config','receive.advertiseAtomic','false');
  const rel=draft('portable'); let r=cli(['--path',rel,'--base-ref','main']); check(r.status===0,'full allocation succeeds');
  const numbered=path.join(d,'docs','rfc','RFC-0001-portable.md'); check(fs.existsSync(numbered),'allocation renames draft');
  check(!fs.readFileSync(numbered,'utf8').includes('number_reserved:'),'confirmed allocation has no marker');
  const completion=provisional('completion',2); r=cli(['--reserve','--path',completion]); check(r.status===0,'completion succeeds');
  check(!fs.readFileSync(path.join(d,completion),'utf8').includes('number_reserved:'),'completion clears marker');
  const collision=provisional('collision',2), before=fs.readFileSync(path.join(d,collision),'utf8');
  r=cli(['--reserve','--path',collision]); check(r.status===4 && /renumber/.test(output(r)),'existing reservation exits 4 and names renumbering');
  check(fs.readFileSync(path.join(d,collision),'utf8')===before,'collision leaves file byte-identical');
  const failure=provisional('failure',3); clear(); Object.assign(process.env,{TRANSPORT_MODE:'fail',TRANSPORT_MATCH:'push',TRANSPORT_ERROR:'permission denied'});
  r=cli(['--reserve','--path',failure]); check(r.status===0 && /WARNING.*permission/s.test(output(r)),'non-collision completion warns, exits 0');
  check(fs.readFileSync(path.join(d,failure),'utf8').includes('number_reserved: false'),'failed completion retains marker');
  clear(); git('push','origin',`HEAD:${ref('RFC',4)}`); const same=provisional('same-head',4);
  r=cli(['--reserve','--path',same]); check(r.status===4,'same-HEAD singleton cannot be falsely confirmed');
  git('push','origin',`HEAD:${ref('FAMA',5)}`); clear();
  const coupled=reserve(pair,5); check(!coupled.ok && !coupled.collision,'unsupported coupled remains refused');
  check(!shaAt(ref('FAMB',5)),'coupled unsupported has no partial peer');
  fs.writeFileSync(path.join(d,'docs','ai','docs-audit.yaml'),'coupled_families:\n  - RFC+SPEC-RFC\n');
  const coupledDoc=provisional('coupled-unsupported',6); clear();
  r=cli(['--reserve','--path',coupledDoc]);
  check(r.status===0 && /unsupported-atomic/.test(output(r)),'public coupled completion degrades visibly');
  check(fs.readFileSync(path.join(d,coupledDoc),'utf8').includes('number_reserved: false'),'coupled refusal keeps provisional marker');
  check(!shaAt(ref('RFC',6)) && !shaAt(ref('SPEC-RFC',6)),'public coupled refusal leaves both refs absent');
  check(calls().filter(a=>a[0]==='push').length===1,'public coupled refusal has no split fallback');
} else if (scenario === '207') {
  check(reservationRef('RFC-0001')==='refs/aai/docnums/RFC-0001','public ref namespace remains compatible');
  const root=process.env.TRANSPORT_ROOT;
  const {extractDocPathReferences}=await import(pathToFileURL(path.join(root,'.aai/scripts/lib/docs-model.mjs')));
  const source=fs.readFileSync(path.join(root,'tests/skills/test-aai-doc-number-reservation.sh'),'utf8');
  const references=extractDocPathReferences(source);
  check(references.includes(path.posix.join('docs','rfc','RFC-0016-downstream-pr-ceremony-reliability.md')),'source-ref scanner positive control sees real RFC');
  check(!references.includes(path.posix.join('docs','rfc','RFC-0001-portable.md')),'disposable portable path must not become a broken index link');
} else if (scenario === '208') {
  const root=process.env.TRANSPORT_ROOT;
  for(const name of ['docs/TECHNOLOGY.md','docs/USER_GUIDE.md']) {
    const text=fs.readFileSync(path.join(root,name),'utf8');
    for(const term of ['unique reservation commit','singleton','--atomic','30000 ms','AAI_DOCNUM_NETWORK_TIMEOUT_MS','300000','remote outcome']) check(text.includes(term),name+' documents '+term);
    check(!text.includes('origin HEAD:<ref>') && !text.includes('    HEAD:<ref>'),'stale HEAD protocol removed from '+name);
  }
  const rfc=fs.readFileSync(path.join(root,'docs/rfc/RFC-0016-downstream-pr-ceremony-reliability.md'),'utf8');
  check(/^status: draft$/m.test(rfc),'umbrella RFC stays draft');
  check(/\| B \|[^\n]*\| (?:in progress|done) \|[^\n]*singleton-reservation-portability/.test(rfc),'RFC B in progress/done cites change');
  for(const phase of ['A','C','D','E']) check(new RegExp('\\| '+phase+' \\|[^\\n]*\\| not started \\|').test(rfc),'other RFC phase '+phase+' unchanged');
}
console.log(`TEST-${scenario} after=${JSON.stringify(refs())} pushes=${JSON.stringify(calls().filter(a=>a[0]==='push'))}`);
console.log(`PASS: TEST-${scenario} transport assertions`);
JS
}

test_201_singleton_non_atomic() { transport_probe 201 || log_fail "TEST-001 (TEST-201) singleton transport probe"; }
test_202_coupled_success_collision() { transport_probe 202 || log_fail "TEST-002 (TEST-202) coupled success/collision probe"; }
test_203_coupled_unsupported() { transport_probe 203 || log_fail "TEST-003 (TEST-203) unsupported coupled probe"; }
test_204_network_deadlines() { transport_probe 204 || log_fail "TEST-004 (TEST-204) network deadlines probe"; }
test_205_failure_categories() { transport_probe 205 || log_fail "TEST-005 (TEST-205) diagnostic/retry probe"; }
test_206_cli_transport_contract() { transport_probe 206 || log_fail "TEST-006 (TEST-206) CLI transport probe"; }
test_207_regression_transport_wiring() {
  transport_probe 207 || log_fail "TEST-007 (TEST-207) namespace probe"
  assert_companions aai-doc-number-reservation aai-doc-numbering || log_fail "TEST-007 (TEST-207) allocator companions must be selected together"
  test_108_targeted_suites_wiring
}
test_208_transport_documentation() { transport_probe 208 || log_fail "TEST-008 (TEST-208) contract documentation probe"; }


# PR535 close correction preserves audit history and the narrow owner waiver.
test_209_close_telemetry_waiver_correction() {
  node --input-type=module - "$PROJECT_ROOT" <<'JS' || log_fail "TEST-009 (TEST-209) waiver telemetry correction"
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
const root=process.argv[2];
const rows=fs.readFileSync(path.join(root,'docs','ai','EVENTS.jsonl'),'utf8').split('\n').filter(l=>l.trim() && !l.startsWith('#')).map(JSON.parse);
const decision=path.posix.join('docs','decisions','DECISION-singleton-reservation-portability.md');
assert.ok(fs.readFileSync(path.join(root,decision),'utf8').includes('TEST-829/830'),'TEST-209 owner decision preserves narrow exception');
for(const ref of ['singleton-reservation-portability','spec-singleton-reservation-portability']) {
  const closes=rows.filter(r=>r.event==='work_item_closed' && r.ref===ref);
  const latest=closes.at(-1);
  console.log(`TEST-209 ref=${ref} latest=${JSON.stringify(latest)}`);
  assert.equal(latest?.payload?.validation,'not_run','TEST-209 latest close must not invent a validation PASS');
  assert.equal(latest?.payload?.code_review,'pass','TEST-209 correction retains the actual close-time review');
  for(const term of ['correction','FAIL','waiver',decision]) assert.ok(latest.payload.notes.includes(term),'TEST-209 correction notes include '+term);
  assert.ok(closes.some(r=>r.payload.validation==='pass'),'TEST-209 preserves prior ledger entries for audit');
}
console.log('PASS: TEST-209 delivery correction preserves FAIL plus narrow owner waiver');
JS
}

main() {
  echo ""
  echo "AAI Doc-Number Reservation Test Suite (CHANGE-0035 / SPEC-0047)"
  echo "================================================================="
  echo ""
  check_deps
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-doc-number-reservation-test.XXXXXX")"

  if [[ $# -ge 1 ]]; then
    [[ "$(type -t "$1" 2>/dev/null || true)" == "function" ]] \
      || { echo "unknown test: $1" >&2; exit 2; }
    "$1"
    return 0
  fi

  test_209_close_telemetry_waiver_correction
  test_201_singleton_non_atomic
  test_202_coupled_success_collision
  test_203_coupled_unsupported
  test_204_network_deadlines
  test_205_failure_categories
  test_206_cli_transport_contract
  test_207_regression_transport_wiring
  test_208_transport_documentation
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
