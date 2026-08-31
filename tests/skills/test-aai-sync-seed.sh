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
RUNTIME_LIST="$PROJECT_ROOT/.aai/system/RUNTIME_IGNORE.list"
GITIGNORE_LIB="$PROJECT_ROOT/.aai/scripts/lib/gitignore-block.sh"
BOOTSTRAP_SH="$PROJECT_ROOT/.aai/scripts/aai-bootstrap.sh"

TMP_ROOT=""

# Set by any pwsh-dependent arm that could not run (pwsh absent). Checked at
# the end of main(): a suite that never exercised a single PowerShell
# assertion must not report the same "all tests passed" exit 0 as a full run
# — it reports the suite's own documented skip status (exit 42) instead, so a
# runner without pwsh cannot silently certify the PowerShell half of this
# scope's root-cause fix.
PWSH_ARM_SKIPPED=0

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

# ── spec-aai-update-gitignore-drift-reconcile — TEST-007..TEST-018 ────────────
# The PowerShell sync path had NO runtime-sidecar reconcile at all (the root
# cause of the reported drift), and the bash side FORKED the same reconcile
# into two copies with different marker text (measured: two marker lines
# after a bootstrap-then-sync target). These tests pin: PS1 now reaches parity
# with bash (TEST-007..009), no engine ever writes a second marker
# (TEST-010), the bash fork is collapsed into one sourced library
# (TEST-011), the library is PROFILES-classified and survives a core-profile
# sync (TEST-012, TEST-013), a missing list/library degrades instead of
# failing (TEST-014), git status sees no runtime-sidecar path once the AAI
# runtime files exist (TEST-015), and the list's own header names its real
# consumers (TEST-016). TEST-017 lives in test-aai-bootstrap.sh. TEST-018
# pins the POSIX path that already worked, against the extraction.

# --- TEST-007 — ps1 seeds every runtime-sidecar pattern (Spec-AC-01) ----------
test_ps1_seeds_all_patterns() {
  log_info "TEST-007: real aai-sync.ps1 into a temp target seeds every runtime-sidecar pattern (0 missing)..."
  if ! command -v pwsh >/dev/null 2>&1; then
    PWSH_ARM_SKIPPED=1
    log_info "TEST-007 note: pwsh absent — SKIPPED"
    return 0
  fi
  local dst="$TMP_ROOT/ps1-seed-all"
  mkdir -p "$dst"
  printf 'node_modules/\n' > "$dst/.gitignore"
  pwsh -NoProfile -File "$SYNC_PS1" -TargetRoot "$dst" >/dev/null 2>&1 \
    || log_fail "TEST-007: aai-sync.ps1 run failed"
  local missing
  missing="$(comm -23 <(grep -v '^#' "$RUNTIME_LIST" | grep -v '^$' | sort) <(sort "$dst/.gitignore") | wc -l | tr -d ' ')"
  [[ "$missing" -eq 0 ]] || log_fail "TEST-007: $missing runtime-sidecar pattern(s) still missing after aai-sync.ps1"
  log_pass "TEST-007 aai-sync.ps1 seeds every runtime-sidecar pattern (0 missing)"
}

# --- TEST-008 — ps1 second run is byte-identical, no duplicate patterns (Spec-AC-02) ---
test_ps1_second_run_idempotent() {
  log_info "TEST-008: second aai-sync.ps1 run leaves .gitignore byte-identical, each pattern occurs exactly once..."
  if ! command -v pwsh >/dev/null 2>&1; then
    PWSH_ARM_SKIPPED=1
    log_info "TEST-008 note: pwsh absent — SKIPPED"
    return 0
  fi
  local dst="$TMP_ROOT/ps1-idempotent" before after
  mkdir -p "$dst"
  printf 'node_modules/\n' > "$dst/.gitignore"
  pwsh -NoProfile -File "$SYNC_PS1" -TargetRoot "$dst" >/dev/null 2>&1 || log_fail "TEST-008: first run failed"
  before="$({ sha256sum "$dst/.gitignore" 2>/dev/null || shasum -a 256 "$dst/.gitignore"; } | awk '{print $1}')"
  pwsh -NoProfile -File "$SYNC_PS1" -TargetRoot "$dst" >/dev/null 2>&1 || log_fail "TEST-008: second run failed"
  after="$({ sha256sum "$dst/.gitignore" 2>/dev/null || shasum -a 256 "$dst/.gitignore"; } | awk '{print $1}')"
  [[ "$before" == "$after" ]] || log_fail "TEST-008: .gitignore changed on second run (before=$before after=$after)"
  local pattern count
  while IFS= read -r pattern; do
    [[ -z "$pattern" || "$pattern" == \#* ]] && continue
    count="$(grep -cxF -- "$pattern" "$dst/.gitignore")"
    [[ "$count" -eq 1 ]] || log_fail "TEST-008: pattern '$pattern' occurs $count time(s), expected 1"
  done < "$RUNTIME_LIST"
  log_pass "TEST-008 second aai-sync.ps1 run is byte-identical, every pattern occurs exactly once"
}

# --- TEST-009 — ps1 preserves user lines/order; comment mention does not suppress seed (Spec-AC-03, Spec-AC-01) ---
test_ps1_preserves_user_lines_and_seeds_commented_pattern() {
  log_info "TEST-009: aai-sync.ps1 preserves user .gitignore lines verbatim/in-order and still seeds a pattern only mentioned in a comment..."
  if ! command -v pwsh >/dev/null 2>&1; then
    PWSH_ARM_SKIPPED=1
    log_info "TEST-009 note: pwsh absent — SKIPPED"
    return 0
  fi
  local dst="$TMP_ROOT/ps1-user-lines" head4 expected
  mkdir -p "$dst"
  printf 'node_modules/\n*.local\n# see docs/ai/briefs/** for handoffs\n.env\n' > "$dst/.gitignore"
  pwsh -NoProfile -File "$SYNC_PS1" -TargetRoot "$dst" >/dev/null 2>&1 \
    || log_fail "TEST-009: aai-sync.ps1 run failed"
  head4="$(head -n 4 "$dst/.gitignore")"
  expected="$(printf 'node_modules/\n*.local\n# see docs/ai/briefs/** for handoffs\n.env')"
  [[ "$head4" == "$expected" ]] \
    || log_fail "TEST-009: user lines not preserved verbatim/in-order, got:"$'\n'"$head4"
  grep -qxF 'docs/ai/briefs/**' "$dst/.gitignore" \
    || log_fail "TEST-009: a comment mentioning the pattern suppressed the real seed"
  log_pass "TEST-009 user lines preserved verbatim/in-order; comment mention does not suppress the real seed"
}

# --- TEST-010 — legacy bootstrap marker: no second marker on either engine (Spec-AC-05) ---
test_legacy_marker_no_duplicate_across_engines() {
  log_info "TEST-010: target pre-seeded with the legacy bootstrap marker synced by each engine yields exactly one marker-prefix line and no duplicated pattern..."
  local legacy_marker='# AAI runtime sidecars (seeded by aai-bootstrap; per-dev, never commit)'

  local dst_sh="$TMP_ROOT/legacy-marker-sh" n_marker_sh n_state_sh
  mkdir -p "$dst_sh"
  git -C "$dst_sh" init -q -b main
  printf 'node_modules/\n%s\ndocs/ai/STATE.yaml\n' "$legacy_marker" > "$dst_sh/.gitignore"
  bash "$SYNC_SH" "$dst_sh" >/dev/null 2>&1 || log_fail "TEST-010: bash sync failed"
  n_marker_sh="$(grep -c '^# AAI runtime sidecars' "$dst_sh/.gitignore")"
  n_state_sh="$(grep -cxF 'docs/ai/STATE.yaml' "$dst_sh/.gitignore")"
  [[ "$n_marker_sh" -eq 1 ]] || log_fail "TEST-010: bash engine produced $n_marker_sh marker-prefix line(s), expected 1"
  [[ "$n_state_sh" -eq 1 ]] || log_fail "TEST-010: bash engine duplicated docs/ai/STATE.yaml ($n_state_sh occurrences)"

  if command -v pwsh >/dev/null 2>&1; then
    local dst_ps="$TMP_ROOT/legacy-marker-ps" n_marker_ps n_state_ps
    mkdir -p "$dst_ps"
    printf 'node_modules/\n%s\ndocs/ai/STATE.yaml\n' "$legacy_marker" > "$dst_ps/.gitignore"
    pwsh -NoProfile -File "$SYNC_PS1" -TargetRoot "$dst_ps" >/dev/null 2>&1 || log_fail "TEST-010: ps1 sync failed"
    n_marker_ps="$(grep -c '^# AAI runtime sidecars' "$dst_ps/.gitignore")"
    n_state_ps="$(grep -cxF 'docs/ai/STATE.yaml' "$dst_ps/.gitignore")"
    [[ "$n_marker_ps" -eq 1 ]] || log_fail "TEST-010: ps1 engine produced $n_marker_ps marker-prefix line(s), expected 1"
    [[ "$n_state_ps" -eq 1 ]] || log_fail "TEST-010: ps1 engine duplicated docs/ai/STATE.yaml ($n_state_ps occurrences)"
  else
    PWSH_ARM_SKIPPED=1
    log_info "TEST-010 note: pwsh absent — ps1 engine arm skipped"
  fi
  log_pass "TEST-010 legacy bootstrap marker yields exactly one marker-prefix line and no duplicated pattern on both engines"
}

# --- TEST-020 — marker PREFIX pinned identically across all 5 call sites (Spec-AC-05 guard hardening) ---
test_marker_prefix_pinned_across_call_sites() {
  log_info "TEST-020: the marker PREFIX is byte-identical across the bash constant, the PowerShell detection regex, and all three caller marker texts..."
  # The prefix cannot be a single literal SHARED across bash and PowerShell
  # (no shell library spans both languages), so it exists as 5 call-site
  # copies: this pins them all to the bash constant as the one canonical
  # source, so a future copy-edit to any single copy is caught here instead
  # of silently reproducing the two-marker Spec-AC-05 regression this scope
  # fixed (drift is invisible to TEST-010, which only counts lines matching
  # the CURRENT prefix, whatever that happens to be).
  local canonical
  canonical="$(grep -oE '^AAI_GITIGNORE_MARKER_PREFIX="[^"]*"' "$GITIGNORE_LIB" | sed -E 's/^AAI_GITIGNORE_MARKER_PREFIX="(.*)"$/\1/')"
  [[ -n "$canonical" ]] || log_fail "TEST-020: could not extract AAI_GITIGNORE_MARKER_PREFIX from $GITIGNORE_LIB"

  # 1. the bash constant (extracted above) is the canonical copy.
  # 2. the PowerShell detection regex.
  grep -qF "(?m)^${canonical}" "$SYNC_PS1" \
    || log_fail "TEST-020: aai-sync.ps1's detection regex does not start with the canonical prefix '$canonical'"
  # 3-5. the three caller marker TEXTS actually written to .gitignore.
  grep -qF "\"${canonical} (seeded by aai-bootstrap;" "$BOOTSTRAP_SH" \
    || log_fail "TEST-020: aai-bootstrap.sh's marker text does not start with the canonical prefix '$canonical'"
  grep -qF "\"${canonical} (seeded from" "$SYNC_SH" \
    || log_fail "TEST-020: aai-sync.sh's marker text does not start with the canonical prefix '$canonical'"
  grep -qF "\"${canonical} (seeded by aai-sync.ps1;" "$SYNC_PS1" \
    || log_fail "TEST-020: aai-sync.ps1's written marker text does not start with the canonical prefix '$canonical'"
  log_pass "TEST-020 marker prefix '$canonical' pinned identically across the bash constant, the ps1 regex, and all 3 caller marker texts"
}

# --- TEST-011 — one bash reader, sourced (not reimplemented) by both callers (Spec-AC-04) ---
test_single_bash_reader_and_sourcing() {
  log_info "TEST-011: exactly one bash reader loops over the runtime list; aai-bootstrap.sh and aai-sync.sh each source it, not reimplement it..."
  [[ -f "$GITIGNORE_LIB" ]] || log_fail "TEST-011: shared library missing: $GITIGNORE_LIB"

  # Semantic population Spec-AC-04 bounds: every .sh file under .aai/scripts
  # that references RUNTIME_IGNORE at all -- not a stylistic loop-syntax
  # fingerprint (a prior version of this assertion counted files containing
  # the literal string 'while IFS= read -r line', which is blind to a
  # reimplementation using a different loop-variable name and brittle to any
  # unrelated read-loop being renamed to 'line').
  local referencers n_referencers
  referencers="$(find "$PROJECT_ROOT/.aai/scripts" -name '*.sh' -print0 \
    | xargs -0 grep -lF 'RUNTIME_IGNORE' 2>/dev/null | sort || true)"
  n_referencers="$(grep -c . <<< "$referencers" || true)"
  [[ "$n_referencers" -eq 3 ]] \
    || log_fail "TEST-011: expected exactly 3 .aai/scripts/**.sh files to reference RUNTIME_IGNORE (bootstrap, sync, library), found $n_referencers: $referencers"

  # Of that set, exactly one file -- the shared library -- may loop-and-append
  # over the list: a `while ... read ...; done < "$<var named after the
  # runtime list>"` construct, tied to the LIST VARIABLE itself (any
  # read-loop element-variable name), never the generic `while IFS= read -r
  # line` idiom that 7 unrelated .aai/scripts/**.sh files already share.
  local loop_regex='done[[:space:]]*<[[:space:]]*"\$[A-Za-z_]*[Rr]untime_?[Ll]ist'
  local f loopers=0
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    grep -qE "$loop_regex" "$f" && loopers=$((loopers + 1))
  done <<< "$referencers"
  [[ "$loopers" -eq 1 ]] \
    || log_fail "TEST-011: expected exactly one RUNTIME_IGNORE-referencing file to loop-and-append over the list (the shared library), found $loopers"
  grep -qE "$loop_regex" "$GITIGNORE_LIB" \
    || log_fail "TEST-011: the shared library itself does not contain the runtime-list read-loop"
  grep -qE "$loop_regex" "$BOOTSTRAP_SH" \
    && log_fail "TEST-011: aai-bootstrap.sh reimplements a read-loop over the runtime list instead of sourcing the shared library"
  grep -qE "$loop_regex" "$SYNC_SH" \
    && log_fail "TEST-011: aai-sync.sh reimplements a read-loop over the runtime list instead of sourcing the shared library"

  grep -qE 'source[[:space:]]+"\$GITIGNORE_BLOCK_LIB"' "$BOOTSTRAP_SH" \
    || log_fail "TEST-011: aai-bootstrap.sh does not source the shared library"
  grep -qE 'source[[:space:]]+"\$GITIGNORE_BLOCK_LIB"' "$SYNC_SH" \
    || log_fail "TEST-011: aai-sync.sh does not source the shared library"
  log_pass "TEST-011 one bash reader of the runtime list (the shared library), sourced by both bash callers, structurally verified"
}

# --- TEST-012 — shared library classified in PROFILES.yaml core (Spec-AC-06) ---
test_library_in_profiles_core() {
  log_info "TEST-012: PROFILES.yaml core list contains the shared gitignore library path..."
  local profiles="$PROJECT_ROOT/.aai/system/PROFILES.yaml" in_core
  in_core="$(awk '
    $0 == "core:" { f = 1; next }
    /^[^ ]/       { f = 0 }
    f && sub(/^  - /, "") { sub(/[ \t\r]+$/, ""); print }
  ' "$profiles" | grep -Fx ".aai/scripts/lib/gitignore-block.sh" || true)"
  [[ -n "$in_core" ]] || log_fail "TEST-012: .aai/scripts/lib/gitignore-block.sh is NOT in the PROFILES.yaml core list"
  log_pass "TEST-012 shared gitignore library classified in PROFILES.yaml core"
}

# --- TEST-013 — core-profile sync keeps the library; bootstrap still works (Spec-AC-06) ---
test_core_profile_keeps_library_and_bootstrap_works() {
  log_info "TEST-013: aai-sync.sh --profile core leaves the shared library present; bootstrap still exits 0 on that target..."
  local dst="$TMP_ROOT/core-profile-lib"
  mkdir -p "$dst"
  git -C "$dst" init -q -b main
  bash "$SYNC_SH" "$dst" --profile core >/dev/null 2>&1 || log_fail "TEST-013: core-profile sync failed"
  [[ -f "$dst/.aai/scripts/lib/gitignore-block.sh" ]] \
    || log_fail "TEST-013: core-profile sync pruned the shared gitignore library"
  bash "$dst/.aai/scripts/aai-bootstrap.sh" "$dst" >/dev/null 2>&1 \
    || log_fail "TEST-013: bootstrap failed on a core-profile target"
  log_pass "TEST-013 core-profile target keeps the library present; bootstrap still exits 0"
}

# --- TEST-014 — missing list path degrades with a named note, exit 0 (Spec-AC-07) ---
test_library_missing_list_skips_with_note() {
  log_info "TEST-014: calling the library with a nonexistent runtime-list path prints a named note and returns 0..."
  local out rc=0 missing_list="$TMP_ROOT/does-not-exist-$$.list" gi="$TMP_ROOT/nonexistent-gi-target/.gitignore"
  mkdir -p "$(dirname "$gi")"
  # `|| rc=$?` (not a bare `rc=$?` after the fact) is load-bearing under this
  # suite's `set -euo pipefail`: a bare assignment on the next line never
  # runs when the command substitution itself fails set -e, so `$?` would
  # always read 0 and the "returns exit status 0" assertion below would be a
  # tautology that could never catch a future nonzero return.
  out="$(
    # shellcheck source=/dev/null
    source "$GITIGNORE_LIB"
    aai_gitignore_seed_runtime "$gi" "$missing_list" "# marker"
  )" || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-014: library returned $rc for a missing list path, expected 0"
  grep -qF "$missing_list" <<< "$out" || log_fail "TEST-014: skip note does not name the missing path: $out"
  grep -qF "missing" <<< "$out" || log_fail "TEST-014: skip note does not read as a skip: $out"
  log_pass "TEST-014 missing list path -> named skip note, exit 0"
}

# --- TEST-019 — library-absent branch degrades with a named note, exit 0 (Spec-AC-07 second half) ---
test_bootstrap_survives_missing_library() {
  log_info "TEST-019: aai-bootstrap.sh degrades with a named skip note (not a crash) when the shared gitignore library itself is absent..."
  # Simulates a project vendored before this scope: aai-bootstrap.sh is
  # present but .aai/scripts/lib/gitignore-block.sh is not (e.g. a stale
  # vendored copy, or a hand-pruned target). Realized by syncing a full
  # target then deleting only the library -- the exact shape of that legacy
  # case -- and running bootstrap from the target's own copy (never the real
  # repo's library, which is left untouched).
  local dst="$TMP_ROOT/lib-absent-bootstrap" out
  mkdir -p "$dst"
  git -C "$dst" init -q -b main
  bash "$SYNC_SH" "$dst" >/dev/null 2>&1 || log_fail "TEST-019: sync failed"
  [[ -f "$dst/.aai/scripts/lib/gitignore-block.sh" ]] \
    || log_fail "TEST-019: bad fixture -- sync did not vendor the shared library into $dst"
  rm -f "$dst/.aai/scripts/lib/gitignore-block.sh"
  out="$(bash "$dst/.aai/scripts/aai-bootstrap.sh" "$dst" 2>&1)" \
    || log_fail "TEST-019: aai-bootstrap.sh exited nonzero with the shared library missing:"$'\n'"$out"
  grep -qF "skipped runtime-sidecar gitignore seed" <<< "$out" \
    || log_fail "TEST-019: bootstrap did not print the named skip note for the missing library:"$'\n'"$out"
  grep -qF "gitignore-block.sh" <<< "$out" \
    || log_fail "TEST-019: bootstrap's skip note does not name the missing library path:"$'\n'"$out"
  log_pass "TEST-019 aai-bootstrap.sh degrades with a named skip note (exit 0) when the shared library is absent"
}

# --- TEST-015 — git status sees zero runtime-sidecar paths on both engines (Spec-AC-08) ---
test_git_status_clean_after_spool_creation() {
  log_info "TEST-015: git status --porcelain reports zero runtime-sidecar paths once spool files exist, on both engines..."
  local dst_sh="$TMP_ROOT/gitstatus-sh" leaked_sh
  mkdir -p "$dst_sh"
  git -C "$dst_sh" init -q -b main
  bash "$SYNC_SH" "$dst_sh" >/dev/null 2>&1 || log_fail "TEST-015: bash sync failed"
  mkdir -p "$dst_sh/docs/ai/briefs" "$dst_sh/docs/ai/tdd"
  : > "$dst_sh/docs/ai/STATE.yaml"
  : > "$dst_sh/docs/ai/LOOP_TICKS.jsonl"
  : > "$dst_sh/docs/ai/briefs/handoff.md"
  : > "$dst_sh/docs/ai/tdd/cycle.log"
  leaked_sh="$(cd "$dst_sh" && git status --porcelain | grep -E 'STATE\.yaml|LOOP_TICKS\.jsonl|docs/ai/briefs/|docs/ai/tdd/' || true)"
  [[ -z "$leaked_sh" ]] \
    || log_fail "TEST-015: bash engine leaves runtime-sidecar paths visible to git status:"$'\n'"$leaked_sh"

  if command -v pwsh >/dev/null 2>&1; then
    local dst_ps="$TMP_ROOT/gitstatus-ps" leaked_ps
    mkdir -p "$dst_ps"
    git -C "$dst_ps" init -q -b main
    pwsh -NoProfile -File "$SYNC_PS1" -TargetRoot "$dst_ps" >/dev/null 2>&1 || log_fail "TEST-015: ps1 sync failed"
    mkdir -p "$dst_ps/docs/ai/briefs" "$dst_ps/docs/ai/tdd"
    : > "$dst_ps/docs/ai/STATE.yaml"
    : > "$dst_ps/docs/ai/LOOP_TICKS.jsonl"
    : > "$dst_ps/docs/ai/briefs/handoff.md"
    : > "$dst_ps/docs/ai/tdd/cycle.log"
    leaked_ps="$(cd "$dst_ps" && git status --porcelain | grep -E 'STATE\.yaml|LOOP_TICKS\.jsonl|docs/ai/briefs/|docs/ai/tdd/' || true)"
    [[ -z "$leaked_ps" ]] \
      || log_fail "TEST-015: ps1 engine leaves runtime-sidecar paths visible to git status:"$'\n'"$leaked_ps"
  else
    PWSH_ARM_SKIPPED=1
    log_info "TEST-015 note: pwsh absent — ps1 engine arm skipped"
  fi
  log_pass "TEST-015 git status --porcelain shows zero runtime-sidecar paths after spool creation, on both engines"
}

# --- TEST-016 — RUNTIME_IGNORE.list header names exactly its real consumers (Spec-AC-09) ---
test_runtime_ignore_header_consumer_accuracy() {
  log_info "TEST-016: every script named in RUNTIME_IGNORE.list's header references the list; every referencing script is named there..."
  local header named=(
    ".aai/scripts/aai-bootstrap.sh"
    ".aai/scripts/aai-sync.sh"
    ".aai/scripts/aai-sync.ps1"
    ".aai/scripts/lib/gitignore-block.sh"
  )
  header="$(sed -n '1,8p' "$RUNTIME_LIST")"
  local n
  for n in "${named[@]}"; do
    grep -qF "$(basename "$n")" <<< "$header" \
      || log_fail "TEST-016: header does not name $n"
    grep -qF "RUNTIME_IGNORE" "$PROJECT_ROOT/$n" \
      || log_fail "TEST-016: $n is named in the header but does not reference RUNTIME_IGNORE.list"
  done

  local actual_readers f base found
  actual_readers="$(find "$PROJECT_ROOT/.aai" -type f \( -name '*.sh' -o -name '*.ps1' -o -name '*.mjs' \) -print0 \
    | xargs -0 grep -l 'RUNTIME_IGNORE' 2>/dev/null || true)"
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    base="${f#"$PROJECT_ROOT"/}"
    found=0
    for n in "${named[@]}"; do
      [[ "$base" == "$n" ]] && found=1 && break
    done
    [[ "$found" -eq 1 ]] || log_fail "TEST-016: $base references RUNTIME_IGNORE.list but is not named in the header"
  done <<< "$actual_readers"

  grep -qF "migrate-state-to-local.ps1" "$RUNTIME_LIST" \
    && log_fail "TEST-016: header still falsely claims migrate-state-to-local.ps1 as a consumer"
  log_pass "TEST-016 RUNTIME_IGNORE.list header names exactly its real consumers"
}

# --- TEST-018 — bash sync regression pin, same fixtures as TEST-007/008 (Spec-AC-01, 02, 03) ---
test_bash_sync_regression_pin() {
  log_info "TEST-018: bash aai-sync.sh regression pin — the POSIX path that already worked stays correct after the extraction..."
  local dst="$TMP_ROOT/bash-regression-pin" before after
  mkdir -p "$dst"
  git -C "$dst" init -q -b main
  printf 'node_modules/\n' > "$dst/.gitignore"
  bash "$SYNC_SH" "$dst" >/dev/null 2>&1 || log_fail "TEST-018: first bash sync run failed"
  local missing
  missing="$(comm -23 <(grep -v '^#' "$RUNTIME_LIST" | grep -v '^$' | sort) <(sort "$dst/.gitignore") | wc -l | tr -d ' ')"
  [[ "$missing" -eq 0 ]] || log_fail "TEST-018: $missing runtime-sidecar pattern(s) missing after bash sync"
  before="$({ sha256sum "$dst/.gitignore" 2>/dev/null || shasum -a 256 "$dst/.gitignore"; } | awk '{print $1}')"
  bash "$SYNC_SH" "$dst" >/dev/null 2>&1 || log_fail "TEST-018: second bash sync run failed"
  after="$({ sha256sum "$dst/.gitignore" 2>/dev/null || shasum -a 256 "$dst/.gitignore"; } | awk '{print $1}')"
  [[ "$before" == "$after" ]] || log_fail "TEST-018: bash sync is not idempotent after the extraction (before=$before after=$after)"
  local pattern count
  while IFS= read -r pattern; do
    [[ -z "$pattern" || "$pattern" == \#* ]] && continue
    count="$(grep -cxF -- "$pattern" "$dst/.gitignore")"
    [[ "$count" -eq 1 ]] || log_fail "TEST-018: pattern '$pattern' occurs $count time(s), expected 1"
  done < "$RUNTIME_LIST"
  log_pass "TEST-018 bash aai-sync.sh regression pin: 0 missing, byte-identical re-run, every pattern occurs exactly once"
}


# --- TEST-021 -- CRLF-terminated .gitignore does not get duplicate patterns ---
# (Copilot review, PR #326): grep -qxF against a CRLF file's on-disk lines
# (each carrying a trailing CR that plain grep never strips) used to treat an
# already-present LF pattern as missing and duplicate it. Calls
# aai_gitignore_seed_runtime DIRECTLY (source the library, not the full
# aai-sync.sh pipeline) -- aai-sync.sh runs its own separate stale-line
# de-duplication pass afterward that would silently absorb this exact
# defect, so exercising the full script would prove nothing about the
# library function's OWN contract (idempotent, exact-match, no duplication).
test_bash_seed_crlf_safe() {
  log_info "TEST-021: a CRLF-terminated .gitignore does not get its already-present patterns duplicated..."
  local dst="$TMP_ROOT/bash-crlf-safe"
  mkdir -p "$dst"
  local pattern
  {
    while IFS= read -r pattern; do
      [[ -z "$pattern" || "$pattern" == \#* ]] && continue
      printf '%s\r\n' "$pattern"
    done < "$RUNTIME_LIST"
  } > "$dst/.gitignore"
  (
    source "$GITIGNORE_LIB"
    aai_gitignore_seed_runtime "$dst/.gitignore" "$RUNTIME_LIST" "# AAI runtime sidecars"
  ) >/dev/null 2>&1 || log_fail "TEST-021: aai_gitignore_seed_runtime failed"
  local dup=0 count
  while IFS= read -r pattern; do
    [[ -z "$pattern" || "$pattern" == \#* ]] && continue
    count="$(tr -d '\r' < "$dst/.gitignore" | grep -cxF -- "$pattern")"
    if [[ "$count" -ne 1 ]]; then
      log_fail "TEST-021: pattern '$pattern' occurs $count time(s) in a CRLF .gitignore, expected 1 (duplicated by a CR-blind exact match)"
      dup=1
    fi
  done < "$RUNTIME_LIST"
  [[ "$dup" -eq 0 ]] && log_pass "TEST-021 every runtime-sidecar pattern occurs exactly once against a pre-existing CRLF .gitignore (no CR-blind duplication)"
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
  test_ps1_seeds_all_patterns
  test_ps1_second_run_idempotent
  test_ps1_preserves_user_lines_and_seeds_commented_pattern
  test_legacy_marker_no_duplicate_across_engines
  test_marker_prefix_pinned_across_call_sites
  test_single_bash_reader_and_sourcing
  test_library_in_profiles_core
  test_core_profile_keeps_library_and_bootstrap_works
  test_library_missing_list_skips_with_note
  test_bootstrap_survives_missing_library
  test_git_status_clean_after_spool_creation
  test_runtime_ignore_header_consumer_accuracy
  test_bash_sync_regression_pin
  test_bash_seed_crlf_safe
  if [[ "$PWSH_ARM_SKIPPED" -eq 1 ]]; then
    log_skip "pwsh absent — one or more PowerShell assertions were not exercised (all bash-only assertions above passed)"
  fi
  echo "=== All $TEST_NAME tests passed ==="
}

main "$@"
