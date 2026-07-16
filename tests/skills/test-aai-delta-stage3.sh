#!/usr/bin/env bash
#
# Test: RFC-0011 (delta-spec lifecycle) — close-time delta merge + PR-ceremony
# wiring (spec-delta-stage-3). Verifies the deterministic, line-surgical
# delta-merge engine (.aai/scripts/delta-merge.mjs) on ISOLATED fixture repos
# (a synthesized canonical doc + a spec with deltas — never this repo's absent
# canonical tree), the SKILL_PR ceremony step + taxonomy-guard cleanliness, and
# seam survival (the sibling suites + the strict repo audit stay green).
#
# Single shell file per repo convention; stanzas map to the spec-delta-stage-3
# Test Plan IDs (TEST-001, TEST-002, TEST-003, TEST-006, TEST-007). The
# provenance-drift stanzas (TEST-004/TEST-005) live in test-aai-docs-audit.sh.
#
# Per-stanza runs (TDD RED/GREEN evidence): ONLY=TEST-00N bash <this file>
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-delta-stage3"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MERGE="$PROJECT_ROOT/.aai/scripts/delta-merge.mjs"
SKILL_PR="$PROJECT_ROOT/.aai/SKILL_PR.prompt.md"
DASH="—"  # em dash (delta + REQ headings)

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then
    [[ -n "${TEST_DIR:-}" ]] && echo "INFO: keeping fixture at $TEST_DIR"
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
assert_contains() { grep -qF -- "$2" "$1" || log_fail "Expected '$2' in $1"; }
assert_not_contains() { if grep -qF -- "$2" "$1"; then log_fail "Did not expect '$2' in $1"; fi; }

sha() { shasum -a 256 "$1" | awk '{print $1}'; }
# sha of the file region from the first line matching $2 (fixed) to EOF.
sha_tail_from() { awk -v p="$2" 'index($0,p){f=1} f{print}' "$1" | shasum -a 256 | awk '{print $1}'; }
# Print the block from the first line containing $2 up to (not incl.) the next
# `### ` / `## ` heading — used for a BOUNDED byte-identity check of one block.
extract_block() {
  awk -v h="$2" '
    index($0,h) && !cap { cap=1; print; next }
    cap && /^(###|## |<!--)/ { exit }
    cap { print }
  ' "$1"
}

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  [[ -f "$MERGE" ]] || log_fail "delta-merge.mjs not found: $MERGE"
  log_pass "Dependencies checked"
}

# Build an isolated repo with the vendored engine + libs and a synthesized
# canonical doc for domain oauth2-login carrying three requirements.
setup_iso() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-delta-stage3-test.XXXXXX")"
  mkdir -p "$TEST_DIR/.aai/scripts/lib" "$TEST_DIR/docs/canonical" "$TEST_DIR/docs/specs"
  cp "$MERGE" "$TEST_DIR/.aai/scripts/"
  cp "$PROJECT_ROOT"/.aai/scripts/lib/*.mjs "$TEST_DIR/.aai/scripts/lib/"
  cat > "$TEST_DIR/docs/canonical/oauth2-login.md" <<MD
---
id: CANON-oauth2-login
type: canonical
domain: oauth2-login
status: accepted
sources:
  - docs/_archive/specs/SPEC-old.md
---

# Canonical: oauth2-login

## Overview / Intent

The current-state requirement set for the oauth2-login domain.

## Requirements

### REQ-OAUTH2_LOGIN-001 ${DASH} Session expiry
The system SHALL expire an idle session after 30 minutes.

- Scenario: WHEN a session is idle for 30 minutes THEN the next request is rejected with 401.

Provenance: SPEC-0001

### REQ-OAUTH2_LOGIN-002 ${DASH} Lockout
The system SHALL lock the account after 5 failed logins.

Provenance: SPEC-0001

### REQ-OAUTH2_LOGIN-003 ${DASH} Legacy grant
The system SHALL accept the legacy password grant.

Provenance: SPEC-0001

## UI

Login form prose (untouched).

## Processes / Behavior

Behavior prose (untouched).

## Data model

Data prose (untouched).

## Superseded decisions

None.
MD
}

# Write the primary merging spec (numbered SPEC-0007) with one ADDED, one
# MODIFIED, one REMOVED against oauth2-login.
write_primary_spec() {
  cat > "$TEST_DIR/docs/specs/SPEC-0007-oauth2-hardening.md" <<MD
---
id: oauth2-hardening
type: spec
number: 7
status: frozen
links:
  pr: []
---

# Spec: OAuth2 hardening

SPEC-FROZEN: true

## Deltas

### ADDED REQ-OAUTH2_LOGIN ${DASH} Token rotation
The system SHALL rotate refresh tokens on every use.

- Scenario: WHEN a refresh token is used THEN a new refresh token is issued and the old one is revoked.

### MODIFIED REQ-OAUTH2_LOGIN-001 ${DASH} Session expiry tightened
The system SHALL expire an idle session after 15 minutes.

- Scenario: WHEN a session is idle for 15 minutes THEN the next request is rejected with 401.

### REMOVED REQ-OAUTH2_LOGIN-003

## Verification
x
MD
}

run_merge() { (cd "$TEST_DIR" && node .aai/scripts/delta-merge.mjs "$@"); }

# ---------------------------------------------------------------------------
# TEST-001 (Spec-AC-01) — apply ADDED/MODIFIED/REMOVED, untouched lines identical
# ---------------------------------------------------------------------------
test_001_apply() {
  log_info "TEST-001: delta-merge applies ADDED/MODIFIED/REMOVED; untouched lines byte-identical (int)..."
  setup_iso
  write_primary_spec
  local canon="$TEST_DIR/docs/canonical/oauth2-login.md"
  local tail_before; tail_before="$(sha_tail_from "$canon" '## UI')"
  extract_block "$canon" '### REQ-OAUTH2_LOGIN-002' > "$TEST_DIR/req2-before.txt"

  run_merge --spec docs/specs/SPEC-0007-oauth2-hardening.md > "$TEST_DIR/merge.log" \
    || log_fail "TEST-001: merge must succeed (exit 0): $(cat "$TEST_DIR/merge.log")"

  # MODIFIED 001 + ADDED 004 + REMOVED 003 tombstone all applied, parse clean.
  (cd "$TEST_DIR" && node --input-type=module -e '
    import fs from "node:fs";
    import { parseRequirementsSection } from "./.aai/scripts/lib/docs-model.mjs";
    const c = fs.readFileSync("docs/canonical/oauth2-login.md", "utf8");
    const r = parseRequirementsSection(c, { domain: "oauth2-login" });
    if (!r.present || r.violations.length) { console.error("parse violations", r.violations); process.exit(1); }
    const ids = r.requirements.map(q => q.id);
    const want = ["REQ-OAUTH2_LOGIN-001","REQ-OAUTH2_LOGIN-002","REQ-OAUTH2_LOGIN-004"];
    if (JSON.stringify(ids) !== JSON.stringify(want)) { console.error("ids wrong", ids); process.exit(1); }
    const by = Object.fromEntries(r.requirements.map(q => [q.id, q]));
    const m = by["REQ-OAUTH2_LOGIN-001"];
    if (m.title !== "Session expiry tightened" || m.provenance !== "SPEC-0007" || m.shallCount !== 1) { console.error("MODIFIED wrong", m); process.exit(1); }
    if (!m.scenarios[0].includes("15 minutes")) { console.error("MODIFIED scenario not replaced", m); process.exit(1); }
    if (!c.includes("expire an idle session after 15 minutes")) { console.error("MODIFIED SHALL not replaced"); process.exit(1); }
    const a = by["REQ-OAUTH2_LOGIN-004"];
    if (a.title !== "Token rotation" || a.provenance !== "SPEC-0007" || a.shallCount !== 1) { console.error("ADDED wrong", a); process.exit(1); }
    const u = by["REQ-OAUTH2_LOGIN-002"];
    if (u.provenance !== "SPEC-0001") { console.error("untouched 002 provenance changed", u); process.exit(1); }
  ') || log_fail "TEST-001: merged canonical parse assertions failed"

  # REMOVED 003 retired via tombstone (id gone, retirement recorded, NNN not reused).
  assert_contains "$canon" "<!-- RETIRED REQ-OAUTH2_LOGIN-003 by SPEC-0007 -->"
  assert_not_contains "$canon" "### REQ-OAUTH2_LOGIN-003"
  assert_not_contains "$canon" "SHALL accept the legacy password grant"

  # Line-surgical: the ## UI..EOF tail and the untouched REQ-002 block are byte-identical.
  [[ "$(sha_tail_from "$canon" '## UI')" == "$tail_before" ]] \
    || log_fail "TEST-001: the ## UI..EOF region must be byte-identical after merge"
  extract_block "$canon" '### REQ-OAUTH2_LOGIN-002' > "$TEST_DIR/req2-after.txt"
  diff -u "$TEST_DIR/req2-before.txt" "$TEST_DIR/req2-after.txt" >/dev/null \
    || log_fail "TEST-001: the untouched REQ-002 block must be byte-identical after merge"

  log_pass "TEST-001: ADDED->004 (retired 003 not reused), MODIFIED body+title+Provenance, REMOVED tombstone; untouched lines byte-identical"
}

# ---------------------------------------------------------------------------
# TEST-002 (Spec-AC-01) — fail-closed preconditions; canonical byte-UNCHANGED
# ---------------------------------------------------------------------------
test_002_fail_closed() {
  log_info "TEST-002: fail-closed on violation / missing doc / absent id / title collision; ZERO writes (int)..."
  setup_iso
  local canon="$TEST_DIR/docs/canonical/oauth2-login.md"

  fail_case() { # $1 label, $2 spec-body-file, $3 expected-reason-substring
    local before after
    before="$(sha "$canon")"
    if run_merge --spec "$1" > "$TEST_DIR/fc.log" 2>&1; then
      log_fail "TEST-002: expected non-zero exit for case: $1"
    fi
    after="$(sha "$canon")"
    [[ "$before" == "$after" ]] || log_fail "TEST-002: canonical MUST be byte-unchanged on fail-close ($1)"
    assert_contains "$TEST_DIR/fc.log" "$2"
  }

  # (a) delta violation (ADDED carrying two SHALL lines -> delta-shall-count)
  cat > "$TEST_DIR/docs/specs/SPEC-bad-violation.md" <<MD
---
id: bad-violation
type: spec
status: frozen
---
# Spec
## Deltas
### ADDED REQ-OAUTH2_LOGIN ${DASH} Two shalls
The system SHALL a.
The system SHALL b.
## Verification
x
MD
  fail_case "docs/specs/SPEC-bad-violation.md" "invalid"

  # (b) missing canonical doc (targets a domain with no docs/canonical/<slug>.md)
  cat > "$TEST_DIR/docs/specs/SPEC-missing-doc.md" <<MD
---
id: missing-doc
type: spec
status: frozen
---
# Spec
## Deltas
### ADDED REQ-BILLING ${DASH} Invoice
The system SHALL issue an invoice per settled order.
## Verification
x
MD
  fail_case "docs/specs/SPEC-missing-doc.md" "canonical doc not found"

  # (c) absent MODIFIED/REMOVED id
  cat > "$TEST_DIR/docs/specs/SPEC-absent-id.md" <<MD
---
id: absent-id
type: spec
status: frozen
---
# Spec
## Deltas
### MODIFIED REQ-OAUTH2_LOGIN-099 ${DASH} Nope
The system SHALL do something to a requirement that does not exist.
## Verification
x
MD
  fail_case "docs/specs/SPEC-absent-id.md" "absent"

  # (d) ADDED title collision with an existing requirement in the domain
  cat > "$TEST_DIR/docs/specs/SPEC-collision.md" <<MD
---
id: collision
type: spec
status: frozen
---
# Spec
## Deltas
### ADDED REQ-OAUTH2_LOGIN ${DASH} Lockout
The system SHALL lock the account after 3 failed logins.
## Verification
x
MD
  fail_case "docs/specs/SPEC-collision.md" "collides"

  log_pass "TEST-002: all four fail-closed preconditions exit non-zero, name the reason, leave the canonical byte-unchanged"
}

# ---------------------------------------------------------------------------
# TEST-003 (Spec-AC-01) — byte-idempotence on a second run
# ---------------------------------------------------------------------------
test_003_idempotent() {
  log_info "TEST-003: a second delta-merge for the same spec is byte-identical (int)..."
  setup_iso
  write_primary_spec
  local canon="$TEST_DIR/docs/canonical/oauth2-login.md"
  run_merge --spec docs/specs/SPEC-0007-oauth2-hardening.md > /dev/null \
    || log_fail "TEST-003: first merge must succeed"
  local after1; after1="$(sha "$canon")"
  run_merge --spec docs/specs/SPEC-0007-oauth2-hardening.md > "$TEST_DIR/rerun.log" \
    || log_fail "TEST-003: second merge must succeed (REMOVED-already-gone is a no-op, not an error): $(cat "$TEST_DIR/rerun.log")"
  local after2; after2="$(sha "$canon")"
  [[ "$after1" == "$after2" ]] || log_fail "TEST-003: canonical changed on the idempotent second run"
  # ADDED not duplicated; tombstone present exactly once.
  [[ "$(grep -c 'REQ-OAUTH2_LOGIN-004' "$canon")" -eq 1 ]] || log_fail "TEST-003: ADDED requirement duplicated on re-run"
  [[ "$(grep -c 'RETIRED REQ-OAUTH2_LOGIN-003' "$canon")" -eq 1 ]] || log_fail "TEST-003: tombstone duplicated on re-run"
  log_pass "TEST-003: second run byte-identical; ADDED not re-appended; REMOVED-already-gone a clean no-op"
}

# Build an isolated repo with a canonical "sprockets" doc carrying two ADJACENT
# requirements (001, 002) — no untouched block between them, so a MODIFIED-001 +
# REMOVED-002 leaves the tombstone IMMEDIATELY after the modified block (the
# tombstone-absorption regression shape).
setup_sprockets() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-delta-stage3-sprockets.XXXXXX")"
  mkdir -p "$TEST_DIR/.aai/scripts/lib" "$TEST_DIR/docs/canonical" "$TEST_DIR/docs/specs"
  cp "$MERGE" "$TEST_DIR/.aai/scripts/"
  cp "$PROJECT_ROOT"/.aai/scripts/lib/*.mjs "$TEST_DIR/.aai/scripts/lib/"
  cat > "$TEST_DIR/docs/canonical/sprockets.md" <<MD
---
id: CANON-sprockets
type: canonical
domain: sprockets
status: accepted
sources:
  - docs/_archive/specs/SPEC-old.md
---

# Canonical: sprockets

## Overview / Intent

Intent.

## Requirements

### REQ-SPROCKETS-001 ${DASH} Foo
The system SHALL foo.

Provenance: SPEC-0001

### REQ-SPROCKETS-002 ${DASH} Bar
The system SHALL bar.

Provenance: SPEC-0001

## UI

UI.
MD
}

# ---------------------------------------------------------------------------
# TEST-008 (Spec-AC-01) — tombstone survives when the MODIFIED target is
# IMMEDIATELY adjacent to the REMOVED id (regression: tombstone was absorbed
# into the preceding modified block's slice and discarded on re-render).
# ---------------------------------------------------------------------------
test_008_adjacent_tombstone_idempotent() {
  log_info "TEST-008: MODIFIED adjacent to REMOVED — tombstone survives a byte-idempotent re-run (int)..."
  setup_sprockets
  local canon="$TEST_DIR/docs/canonical/sprockets.md"
  cat > "$TEST_DIR/docs/specs/SPEC-0200-tighten.md" <<MD
---
id: tighten
type: spec
number: 200
status: frozen
---
# Spec
## Deltas
### MODIFIED REQ-SPROCKETS-001 ${DASH} Foo tightened
The system SHALL foo strictly.
### REMOVED REQ-SPROCKETS-002
## Verification
x
MD
  run_merge --spec docs/specs/SPEC-0200-tighten.md > "$TEST_DIR/r1.log" \
    || log_fail "TEST-008: first merge must succeed"
  assert_contains "$canon" "<!-- RETIRED REQ-SPROCKETS-002 by SPEC-0200 -->"
  local after1; after1="$(sha "$canon")"
  run_merge --spec docs/specs/SPEC-0200-tighten.md > "$TEST_DIR/r2.log" \
    || log_fail "TEST-008: second merge must succeed"
  [[ "$(grep -c 'RETIRED REQ-SPROCKETS-002' "$canon")" -eq 1 ]] \
    || log_fail "TEST-008: the tombstone must NOT be dropped on the second run (regression)"
  [[ "$(sha "$canon")" == "$after1" ]] \
    || log_fail "TEST-008: canonical changed on the idempotent second run (tombstone absorbed/discarded)"
  grep -qiE 'already merged|byte-idempotent' "$TEST_DIR/r2.log" \
    || log_fail "TEST-008: the second run must report a no-op, not 'applied'"
  log_pass "TEST-008: tombstone adjacent to a modified block survives; second run byte-identical"
}

# ---------------------------------------------------------------------------
# TEST-009 (Spec-AC-01) — a retired NNN is NEVER reused across specs, even when
# the tombstone sits adjacent to a modified block and the removing spec re-runs.
# ---------------------------------------------------------------------------
test_009_nnn_never_reused() {
  log_info "TEST-009: retired NNN not reused by a later ADDED across specs (int)..."
  setup_sprockets
  local canon="$TEST_DIR/docs/canonical/sprockets.md"
  cat > "$TEST_DIR/docs/specs/SPEC-0200-tighten.md" <<MD
---
id: tighten
type: spec
number: 200
status: frozen
---
# Spec
## Deltas
### MODIFIED REQ-SPROCKETS-001 ${DASH} Foo tightened
The system SHALL foo strictly.
### REMOVED REQ-SPROCKETS-002
## Verification
x
MD
  # Run the removing spec TWICE (the second run is where the regression dropped
  # the tombstone, freeing 002 for reuse).
  run_merge --spec docs/specs/SPEC-0200-tighten.md > /dev/null || log_fail "TEST-009: merge-A run1 failed"
  run_merge --spec docs/specs/SPEC-0200-tighten.md > /dev/null || log_fail "TEST-009: merge-A run2 failed"
  cat > "$TEST_DIR/docs/specs/SPEC-0201-add.md" <<MD
---
id: add
type: spec
number: 201
status: frozen
---
# Spec
## Deltas
### ADDED REQ-SPROCKETS ${DASH} Baz
The system SHALL baz.
## Verification
x
MD
  run_merge --spec docs/specs/SPEC-0201-add.md > /dev/null || log_fail "TEST-009: merge-B (ADDED) failed"
  assert_contains "$canon" "### REQ-SPROCKETS-003 ${DASH} Baz"
  assert_not_contains "$canon" "### REQ-SPROCKETS-002 ${DASH} Baz"
  # the retirement record for 002 must persist (guards the NNN)
  assert_contains "$canon" "<!-- RETIRED REQ-SPROCKETS-002 by SPEC-0200 -->"
  log_pass "TEST-009: ADDED took REQ-SPROCKETS-003; retired 002 never reused"
}

# ---------------------------------------------------------------------------
# TEST-010 (Spec-AC-01) — a DIFFERENT spec that MODIFIES the block immediately
# preceding an earlier spec's tombstone must not destroy that retirement record.
# ---------------------------------------------------------------------------
test_010_cross_spec_tombstone_survives() {
  log_info "TEST-010: cross-spec — modifying the block before a tombstone preserves it (int)..."
  setup_sprockets
  local canon="$TEST_DIR/docs/canonical/sprockets.md"
  # SPEC-A retires 002 only (001 left untouched, so 001 directly precedes the tombstone).
  cat > "$TEST_DIR/docs/specs/SPEC-0202-retire.md" <<MD
---
id: retire
type: spec
number: 202
status: frozen
---
# Spec
## Deltas
### REMOVED REQ-SPROCKETS-002
## Verification
x
MD
  run_merge --spec docs/specs/SPEC-0202-retire.md > /dev/null || log_fail "TEST-010: SPEC-A retire failed"
  assert_contains "$canon" "<!-- RETIRED REQ-SPROCKETS-002 by SPEC-0202 -->"
  # SPEC-B modifies 001 — the block immediately preceding SPEC-A's tombstone.
  cat > "$TEST_DIR/docs/specs/SPEC-0203-modify.md" <<MD
---
id: modify
type: spec
number: 203
status: frozen
---
# Spec
## Deltas
### MODIFIED REQ-SPROCKETS-001 ${DASH} Foo revised
The system SHALL foo differently.
## Verification
x
MD
  run_merge --spec docs/specs/SPEC-0203-modify.md > /dev/null || log_fail "TEST-010: SPEC-B modify failed"
  assert_contains "$canon" "<!-- RETIRED REQ-SPROCKETS-002 by SPEC-0202 -->"
  assert_contains "$canon" "### REQ-SPROCKETS-001 ${DASH} Foo revised"
  log_pass "TEST-010: SPEC-A's tombstone survives a later SPEC-B modification of the preceding block"
}

# ---------------------------------------------------------------------------
# TEST-006 (Spec-AC-03) — SKILL_PR ceremony step + taxonomy-guard clean
# ---------------------------------------------------------------------------
test_006_skill_pr() {
  log_info "TEST-006: SKILL_PR documents the delta-merge ceremony step; no stage-N token on edited .aai surfaces (unit)..."
  assert_file "$SKILL_PR"
  assert_contains "$SKILL_PR" 'delta-merge.mjs'
  assert_contains "$SKILL_PR" 'RFC-0011'
  grep -qiE 'after number allocation|after allocation|AFTER number allocation' "$SKILL_PR" \
    || log_fail "TEST-006: SKILL_PR must place the merge AFTER number allocation"
  grep -qiE 'fail-closed|non-zero' "$SKILL_PR" \
    || log_fail "TEST-006: SKILL_PR must state the step is fail-closed (STOP on non-zero exit)"
  grep -qiF 'STOP' "$SKILL_PR" || log_fail "TEST-006: SKILL_PR must STOP the ceremony on a non-zero delta-merge exit"
  grep -qiE 'no-op' "$SKILL_PR" \
    || log_fail "TEST-006: SKILL_PR must document the no-op when no Deltas / no canonical"
  grep -qiF 'never merge' "$SKILL_PR" || log_fail "TEST-006: SKILL_PR must keep the operator-only merge boundary"

  # Taxonomy guard: NO stage-N token on any edited .aai surface (hygiene-pack
  # review-taxonomy guard bans stage 1/stage-1/stage 2/... on .aai surfaces).
  local edited=(
    "$PROJECT_ROOT/.aai/scripts/delta-merge.mjs"
    "$PROJECT_ROOT/.aai/scripts/lib/docs-audit-core.mjs"
    "$SKILL_PR"
  )
  if grep -rnE 'stage[ -][123]' "${edited[@]}"; then
    log_fail "TEST-006: a stage-N taxonomy token leaked onto an edited .aai surface"
  fi
  log_pass "TEST-006: SKILL_PR carries the post-allocation, fail-closed, no-op-documented merge step; taxonomy clean"
}

# ---------------------------------------------------------------------------
# TEST-007 (Spec-AC-03) — seam survival: sibling suites + strict repo audit
# ---------------------------------------------------------------------------
test_007_seam_survival() {
  log_info "TEST-007: delta-stage1 + delta-stage2 + spec-lint + docs-audit suites pass; strict repo audit CLEAN (int)..."
  local s
  for s in test-aai-delta-stage1.sh test-aai-delta-stage2.sh test-aai-spec-lint.sh test-aai-docs-audit.sh; do
    bash "$SCRIPT_DIR/$s" > "/tmp/aai-delta-stage3-$s.log" 2>&1 \
      || { tail -25 "/tmp/aai-delta-stage3-$s.log" >&2; log_fail "TEST-007: sibling suite failed: $s"; }
  done
  (cd "$PROJECT_ROOT" && node .aai/scripts/docs-audit.mjs --check --strict --no-event >/dev/null 2>&1) \
    || log_fail "TEST-007: repo-wide strict audit must stay CLEAN (empty canonical -> no false positive)"
  log_pass "TEST-007: sibling suites green; strict audit CLEAN over the real (empty-canonical) repo"
}

# ---------------------------------------------------------------------------

main() {
  echo "=== Test: $TEST_NAME (spec-delta-stage-3 / RFC-0011 delta-spec lifecycle) ==="
  check_deps
  local only="${ONLY:-}"
  run_stanza() {
    local id="$1"; shift
    if [[ -z "$only" || "$only" == "$id" ]]; then "$@"; fi
  }
  run_stanza TEST-001 test_001_apply
  run_stanza TEST-002 test_002_fail_closed
  run_stanza TEST-003 test_003_idempotent
  run_stanza TEST-008 test_008_adjacent_tombstone_idempotent
  run_stanza TEST-009 test_009_nnn_never_reused
  run_stanza TEST-010 test_010_cross_spec_tombstone_survives
  run_stanza TEST-006 test_006_skill_pr
  run_stanza TEST-007 test_007_seam_survival
  echo "=== All $TEST_NAME tests passed ==="
}

main "$@"
