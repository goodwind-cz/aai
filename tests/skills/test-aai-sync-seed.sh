#!/usr/bin/env bash
#
# Test: aai-sync seeds project-owned docs/ai/*.yaml config when missing
# (CHANGE seed-update-config; CHANGE-0121 downstream-lane-seed).
#
# Verifies the seed-when-missing behavior mirroring the TECHNOLOGY.md seed:
#   - a FRESH target (no docs/ai/update-config.yaml) is SEEDED from
#     .aai/templates/update-config.template.yaml with the documented default
#     policy (mode: notify + throttle_hours: 24 + the key comments).
#   - an EXISTING target docs/ai/update-config.yaml is PRESERVED byte-for-byte
#     across a re-sync (project-owned policy is never clobbered).
#   - the same discipline for docs/ai/docs-audit.yaml (CHANGE-0121): absent
#     downstream, it made lane-gate fail closed on `protected_config_missing`
#     — no downstream project could EVER ride the fast lane. TEST-004..006.
#
# The seed source is the vendored template (always synced), NOT the repo's own
# docs/ai/update-config.yaml — so a project that adopts the file keeps its edits.
#
# NO NETWORK: runs the REAL aai-sync.sh from this repo into a local temp target.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-sync-seed"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SYNC_SH="$PROJECT_ROOT/.aai/scripts/aai-sync.sh"
SYNC_PS1="$PROJECT_ROOT/.aai/scripts/aai-sync.ps1"
TEMPLATE="$PROJECT_ROOT/.aai/templates/update-config.template.yaml"
AUDIT_TEMPLATE="$PROJECT_ROOT/.aai/templates/docs-audit.template.yaml"
LIVE_AUDIT_CONFIG="$PROJECT_ROOT/docs/ai/docs-audit.yaml"
LANE_GATE="$PROJECT_ROOT/.aai/scripts/lane-gate.mjs"

TMP_ROOT=""

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

check_deps() {
  log_info "Checking dependencies..."
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  [[ -f "$SYNC_SH" ]] || log_fail "aai-sync.sh not found: $SYNC_SH"
  TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aai-sync-seed-test.XXXXXX")"
  log_pass "Dependencies checked"
}

# --- TEST-001 — fresh target: docs/ai/update-config.yaml is SEEDED -------------
# AC-001: a fresh sync (no config) seeds mode: notify + throttle_hours: 24 + comments.
test_seed_fresh() {
  log_info "TEST-001: fresh target sync seeds docs/ai/update-config.yaml from the template..."
  local dst="$TMP_ROOT/fresh" cfg
  mkdir -p "$dst"
  git -C "$dst" init -q -b main
  cfg="$dst/docs/ai/update-config.yaml"
  [[ ! -f "$cfg" ]] || log_fail "config unexpectedly present before sync (bad fixture)"

  bash "$SYNC_SH" "$dst" >/dev/null 2>&1 || log_fail "fresh sync failed"

  [[ -f "$cfg" ]] || log_fail "fresh sync did NOT seed docs/ai/update-config.yaml"
  grep -q '^mode: notify$' "$cfg" || log_fail "seeded config missing 'mode: notify', got: $(cat "$cfg")"
  grep -q '^throttle_hours: 24$' "$cfg" || log_fail "seeded config missing 'throttle_hours: 24', got: $(cat "$cfg")"
  # documented-default key comments come along with the template (discoverability).
  grep -q 'ABSENT FILE' "$cfg" || log_fail "seeded config missing the documented key comments (template body), got: $(cat "$cfg")"
  # the seed must equal the vendored template byte-for-byte.
  cmp -s "$TEMPLATE" "$cfg" || log_fail "seeded config differs from the template (should be an exact copy)"
  log_pass "TEST-001 fresh target seeds update-config.yaml from the template (notify/24 + comments)"
}

# --- TEST-002 — existing target: config PRESERVED byte-for-byte ----------------
# AC-002: an existing docs/ai/update-config.yaml is never overwritten by a re-sync.
test_preserve_existing() {
  log_info "TEST-002: existing docs/ai/update-config.yaml is PRESERVED byte-for-byte across a re-sync..."
  local dst="$TMP_ROOT/existing" cfg custom before after
  mkdir -p "$dst/docs/ai"
  git -C "$dst" init -q -b main
  cfg="$dst/docs/ai/update-config.yaml"
  # An operator-owned policy that OPTED IN to auto — must survive the sync intact.
  custom="$dst/custom-expected.yaml"
  cat > "$custom" <<'CFG'
# operator-owned policy (edited): opted into auto-update
mode: auto
throttle_hours: 6
CFG
  cp "$custom" "$cfg"
  before="$({ sha256sum "$cfg" 2>/dev/null || shasum -a 256 "$cfg"; } | awk '{print $1}')"

  bash "$SYNC_SH" "$dst" >/dev/null 2>&1 || log_fail "re-sync failed"

  [[ -f "$cfg" ]] || log_fail "re-sync removed the existing config"
  after="$({ sha256sum "$cfg" 2>/dev/null || shasum -a 256 "$cfg"; } | awk '{print $1}')"
  [[ "$before" == "$after" ]] || log_fail "re-sync OVERWROTE the operator's config (hash changed): $(cat "$cfg")"
  cmp -s "$custom" "$cfg" || log_fail "re-sync did not preserve the operator's config byte-for-byte"
  grep -q '^mode: auto$' "$cfg" || log_fail "operator's 'mode: auto' was lost, got: $(cat "$cfg")"
  log_pass "TEST-002 existing config preserved byte-for-byte (never clobbered)"
}

# --- TEST-003 — template exists + classified; ps1 parity (static) --------------
# AC-003: the template file exists and both sync scripts seed it with parity.
test_template_and_parity() {
  log_info "TEST-003: template file exists, is in PROFILES core, and both sync scripts seed it..."
  [[ -f "$TEMPLATE" ]] || log_fail "seed template missing: $TEMPLATE"
  # PROFILES core union must carry the new template (layer-profiles invariant).
  local profiles="$PROJECT_ROOT/.aai/system/PROFILES.yaml" in_core
  in_core="$(awk '
    $0 == "core:" { f = 1; next }
    /^[^ ]/       { f = 0 }
    f && sub(/^  - /, "") { sub(/[ \t\r]+$/, ""); print }
  ' "$profiles" | grep -Fx ".aai/templates/update-config.template.yaml" || true)"
  [[ -n "$in_core" ]] || log_fail ".aai/templates/update-config.template.yaml is NOT in the PROFILES.yaml core list"
  # both engines seed docs/ai/update-config.yaml from the template (parity).
  grep -qF "update-config.template.yaml" "$SYNC_SH" || log_fail "aai-sync.sh does not seed from the template"
  grep -qF "docs/ai/update-config.yaml" "$SYNC_SH" || log_fail "aai-sync.sh does not reference the seed target"
  if [[ -f "$SYNC_PS1" ]]; then
    grep -qF "update-config.template.yaml" "$SYNC_PS1" || log_fail "aai-sync.ps1 does not seed from the template (parity)"
    grep -qF "docs/ai/update-config.yaml" "$SYNC_PS1" || log_fail "aai-sync.ps1 does not reference the seed target (parity)"
  fi
  log_pass "TEST-003 template classified in core + both scripts seed it (parity)"
}

# ── CHANGE-0121 — docs/ai/docs-audit.yaml seed (fast lane reachable downstream) ─

# extract_l3 <yaml> — the protected_paths_l3 block items, one per line, in
# order. Termination matches the PRODUCTION readers (select-suites.mjs et al —
# bot review): the block ends at the FIRST line that is neither a list item
# nor blank/comment, not merely at the next column-0 key — so the drift guard
# (TEST-006) reads the file the same way production does.
extract_l3() {
  awk '
    /^protected_paths_l3:[[:space:]]*$/ { f = 1; next }
    f && !/^[[:space:]]*-[[:space:]]/ && !/^[[:space:]]*(#|$)/ { f = 0 }
    f && /^[[:space:]]*-[[:space:]]/    { sub(/^[[:space:]]*-[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print }
  ' "$1"
}

# lane_fixture <dir> — the non-config half of a lane-gate fixture (suite map,
# L1 spec, direct STATE). The docs-audit.yaml is deliberately NOT written: the
# whole point of TEST-004 is that the SEED supplies it.
lane_fixture() {
  local dir="$1"
  mkdir -p "$dir/tests/skills" "$dir/docs/specs" "$dir/docs/ai"
  cat > "$dir/tests/skills/suite-map.yaml" <<'YAML'
core:
  - aai-core-a

full_run_triggers:
  shared_lib_globs:
    - .aai/scripts/lib/**

suites:
  aai-core-a:
    globs:
      - docs/**
YAML
  printf -- '---\nid: fx\nstatus: implementing\nceremony_level: 1\n---\n\nbody\n' \
    > "$dir/docs/specs/SPEC-DRAFT-fx.md"
  printf 'implementation_strategy:\n  selected: direct\n  source: intake\n' \
    > "$dir/docs/ai/STATE.yaml"
}

# --- TEST-004 — fresh target: docs/ai/docs-audit.yaml is SEEDED ---------------
# CHANGE-0121 AC-001 (seed arm) + AC-002 (lane-gate resolves protected_config).
test_seed_audit_fresh() {
  log_info "TEST-004: fresh target sync seeds docs/ai/docs-audit.yaml; lane-gate sees protected_config=present..."
  local dst="$TMP_ROOT/audit-fresh" cfg dial out
  mkdir -p "$dst"
  git -C "$dst" init -q -b main
  cfg="$dst/docs/ai/docs-audit.yaml"
  [[ ! -f "$cfg" ]] || log_fail "TEST-004: config unexpectedly present before sync (bad fixture)"

  bash "$SYNC_SH" "$dst" >"$TMP_ROOT/audit-fresh.log" 2>&1 \
    || log_fail "TEST-004: fresh sync failed: $(cat "$TMP_ROOT/audit-fresh.log")"

  [[ -f "$cfg" ]] || log_fail "TEST-004: fresh sync did NOT seed docs/ai/docs-audit.yaml"
  # the seed is the vendored template verbatim (no per-target rendering).
  cmp -s "$AUDIT_TEMPLATE" "$cfg" \
    || log_fail "TEST-004: seeded config differs from the template (should be an exact copy)"
  # the sync announces the seed on one line (operator discoverability).
  grep -qF "SEED docs/ai/docs-audit.yaml" "$TMP_ROOT/audit-fresh.log" \
    || log_fail "TEST-004: sync did not print the one-line SEED note: $(cat "$TMP_ROOT/audit-fresh.log")"
  # dials seeded REPORT-ONLY — adopting the file must not silently start
  # blocking a downstream project's commits/closes.
  for dial in close_gate doc_number_guard product_doc_gate usage_capture_gate; do
    grep -qE "^${dial}: report-only$" "$cfg" \
      || log_fail "TEST-004: seeded dial '$dial' is not report-only: $(cat "$cfg")"
  done
  grep -qE '^docs_ai_canon_extra: \[\]$' "$cfg" \
    || log_fail "TEST-004: seeded config must carry an empty docs_ai_canon_extra"
  grep -qE '^protected_paths_l3:[[:space:]]*$' "$cfg" \
    || log_fail "TEST-004: seeded config must carry a protected_paths_l3 block"
  [[ -n "$(extract_l3 "$cfg")" ]] || log_fail "TEST-004: seeded protected_paths_l3 block is empty"

  # AC-002 — the lane gate in the seeded target now resolves the predicate.
  if command -v node >/dev/null 2>&1 && [[ -f "$LANE_GATE" ]]; then
    lane_fixture "$dst"
    printf 'docs/x.md\n' > "$dst/files.txt"
    out="$(node "$LANE_GATE" --repo-root "$dst" --spec "$dst/docs/specs/SPEC-DRAFT-fx.md" \
      --state "$dst/docs/ai/STATE.yaml" --files-from "$dst/files.txt" --max-files 5 2>&1)"
    grep -qF 'protected_config=present ok' <<< "$out" \
      || log_fail "TEST-004: seeded target still fails the protected_config predicate: $out"
    grep -qE '^LANE fast$' <<< "$out" \
      || log_fail "TEST-004: seeded target does not reach the fast lane: $out"
    # negative control — remove the seed and the gate fails closed again.
    rm -f "$cfg"
    out="$(node "$LANE_GATE" --repo-root "$dst" --spec "$dst/docs/specs/SPEC-DRAFT-fx.md" \
      --state "$dst/docs/ai/STATE.yaml" --files-from "$dst/files.txt" --max-files 5 2>&1)"
    grep -qE '^LANE heavy reason=protected_config_missing' <<< "$out" \
      || log_fail "TEST-004: fail-closed semantics changed (control): $out"
  else
    log_info "TEST-004: node absent — lane-gate arm skipped (seed arm still asserted)"
  fi
  log_pass "TEST-004 fresh target seeds docs-audit.yaml (report-only dials) and the fast lane becomes reachable"
}

# --- TEST-005 — existing docs-audit.yaml PRESERVED byte-for-byte --------------
# CHANGE-0121 AC-001 (never-overwrite arm).
test_preserve_existing_audit() {
  log_info "TEST-005: existing docs/ai/docs-audit.yaml is PRESERVED byte-for-byte across a re-sync..."
  local dst="$TMP_ROOT/audit-existing" cfg custom before after
  mkdir -p "$dst/docs/ai"
  git -C "$dst" init -q -b main
  cfg="$dst/docs/ai/docs-audit.yaml"
  # an operator-owned policy that ENFORCED its dials and extended the
  # protected set — must survive the sync intact.
  custom="$dst/custom-expected.yaml"
  cat > "$custom" <<'CFG'
# project-owned guard policy (edited)
close_gate: enforce
doc_number_guard: enforce
protected_paths_l3:
  - src/payments/ledger.ts
docs_ai_canon_extra:
  - vendor-reports
CFG
  cp "$custom" "$cfg"
  before="$({ sha256sum "$cfg" 2>/dev/null || shasum -a 256 "$cfg"; } | awk '{print $1}')"

  bash "$SYNC_SH" "$dst" >/dev/null 2>&1 || log_fail "TEST-005: re-sync failed"

  [[ -f "$cfg" ]] || log_fail "TEST-005: re-sync removed the existing config"
  after="$({ sha256sum "$cfg" 2>/dev/null || shasum -a 256 "$cfg"; } | awk '{print $1}')"
  [[ "$before" == "$after" ]] || log_fail "TEST-005: re-sync OVERWROTE the operator's config: $(cat "$cfg")"
  cmp -s "$custom" "$cfg" || log_fail "TEST-005: re-sync did not preserve the config byte-for-byte"
  grep -qE '^close_gate: enforce$' "$cfg" || log_fail "TEST-005: operator's enforced dial was lost"
  log_pass "TEST-005 existing docs-audit.yaml preserved byte-for-byte (never clobbered)"
}

# --- TEST-006 — single-source: template mirrors the live protected set --------
# CHANGE-0121 AC-003 + the "no hand copy that drifts" constraint. The seeded
# protected_paths_l3 is the CANONICAL vendored set (this repo's own
# docs/ai/docs-audit.yaml, itself pinned to the WORKFLOW.md ceremony table) —
# editing one without the other turns this suite RED.
test_audit_template_single_source() {
  log_info "TEST-006: docs-audit template is PROFILES-classified, seeded by both engines, and mirrors the live protected set..."
  [[ -f "$AUDIT_TEMPLATE" ]] || log_fail "TEST-006: seed template missing: $AUDIT_TEMPLATE"
  local profiles="$PROJECT_ROOT/.aai/system/PROFILES.yaml" in_core live_l3 tpl_l3
  in_core="$(awk '
    $0 == "core:" { f = 1; next }
    /^[^ ]/       { f = 0 }
    f && sub(/^  - /, "") { sub(/[ \t\r]+$/, ""); print }
  ' "$profiles" | grep -Fx ".aai/templates/docs-audit.template.yaml" || true)"
  [[ -n "$in_core" ]] || log_fail "TEST-006: .aai/templates/docs-audit.template.yaml is NOT in the PROFILES.yaml core list"

  grep -qF "docs-audit.template.yaml" "$SYNC_SH" || log_fail "TEST-006: aai-sync.sh does not seed from the template"
  if [[ -f "$SYNC_PS1" ]]; then
    grep -qF "docs-audit.template.yaml" "$SYNC_PS1" \
      || log_fail "TEST-006: aai-sync.ps1 does not seed from the template (parity)"
  fi

  # DRIFT GUARD (single source): template list == this repo's live list.
  live_l3="$(extract_l3 "$LIVE_AUDIT_CONFIG")"
  tpl_l3="$(extract_l3 "$AUDIT_TEMPLATE")"
  [[ -n "$live_l3" ]] || log_fail "TEST-006: no protected_paths_l3 extracted from $LIVE_AUDIT_CONFIG"
  if [[ "$live_l3" != "$tpl_l3" ]]; then
    log_fail "TEST-006: seeded protected_paths_l3 DRIFTED from the canonical set."$'\n'"live:"$'\n'"$live_l3"$'\n'"template:"$'\n'"$tpl_l3"
  fi
  log_pass "TEST-006 template classified in core, seeded by both engines, protected set single-sourced"
}

main() {
  echo "=== Test Suite: $TEST_NAME ==="
  check_deps
  test_seed_fresh
  test_preserve_existing
  test_template_and_parity
  test_seed_audit_fresh
  test_preserve_existing_audit
  test_audit_template_single_source
  echo "=== All $TEST_NAME tests passed ==="
}

main "$@"
