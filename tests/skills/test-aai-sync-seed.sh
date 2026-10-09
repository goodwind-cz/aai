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
. "$SCRIPT_DIR/lib/pipe-safe.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# Companion suites are declared in suite-map.yaml, not run nested
# (nested-suite-reruns-duplicate-sweep-time).
# shellcheck source=lib/companion-assert.sh
. "$SCRIPT_DIR/lib/companion-assert.sh"
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
# Canonical fixture source (built once per run, lazily; see _sync_fixture_canon).
SYNC_FIXTURE_CANON=""
# Golden directory of the key the last _sync_cached call served (read by test_794/795).
SYNC_LAST_GOLDEN=""

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
    # The sync goldens are read-only on purpose (_sync_cached); give the
    # owner write back so rm can remove them.
    if [[ -d "$TMP_ROOT/golden" ]]; then chmod -R u+w "$TMP_ROOT/golden" 2>/dev/null || true; fi
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
  SYNC_FIXTURE_CANON="$TMP_ROOT/fixture-canon"
  log_pass "Dependencies checked"
}

# --- sync cache (hot-spots D3) -------------------------------------------------
# Most tests start with a FIRST sync into a fresh target whose output they
# discard, then assert on a later step. _sync_cached runs that first sync for
# real ONCE per key into a read-only golden and hands every later request a
# writable copy. A key is engine (sh|ps1) + source kind (real = $PROJECT_ROOT,
# fixture = $SYNC_FIXTURE_CANON) + target kind (empty | git).
# It may replace ONLY a first sync into a fresh target whose output the test
# discards. A re-sync, a pre-seeded target, a captured stdout, an engine-parity
# comparison and TEST-778's old-vs-new comparison always call the engine
# directly. State lives on disk (a .done marker next to the golden), not in a
# variable, so a call made inside a command substitution (TEST-630 replays a
# test that way) still sees the golden an earlier call made.
# The premise (path-dependent output is only the pin and advisory header lines;
# an existing pin is read for Profile only) is pinned by test_795.
_hooks_run_engine() {
  local engine="$1" src="$2" dst="$3"
  [[ -n "$dst" && "$dst" == /* ]] || log_fail "bad fixture path: [$dst]"
  if [[ "$engine" == "ps1" ]]; then
    pwsh -NoProfile -File "$src/.aai/scripts/aai-sync.ps1" -TargetRoot "$dst"
  else
    bash "$src/.aai/scripts/aai-sync.sh" "$dst"
  fi
}

_sync_fixture_canon() {
  if [[ ! -f "$TMP_ROOT/fixture-canon.done" ]]; then
    rm -rf "$SYNC_FIXTURE_CANON"
    _778_build_fixture_source "$SYNC_FIXTURE_CANON"
    : > "$TMP_ROOT/fixture-canon.done"
  fi
}

# Copy the canonical fixture source to its own path; the caller edits the copy.
_fixture_source_copy() {
  local dir="$1"
  [[ -n "$dir" && "$dir" == /* ]] || log_fail "_fixture_source_copy: destination is empty or relative: [$dir]"
  _sync_fixture_canon
  mkdir -p "$dir"
  cp -R "$SYNC_FIXTURE_CANON/." "$dir/" || log_fail "_fixture_source_copy: copy into $dir failed"
}

# _sync_cached <engine> <source-root> <dst> [git]
_sync_cached() {
  local engine="$1" src="$2" dst="$3" tkind="${4:-empty}" skind key golden
  [[ -n "$dst" && "$dst" == /* ]] || log_fail "_sync_cached: destination is empty or relative: [$dst]"
  case "$engine" in sh|ps1) : ;; *) log_fail "_sync_cached: unknown engine [$engine]" ;; esac
  case "$tkind" in git|empty) : ;; *) log_fail "_sync_cached: unknown target kind [$tkind]" ;; esac
  if [[ "$src" == "$PROJECT_ROOT" ]]; then
    skind=real
  elif [[ "$src" == "$SYNC_FIXTURE_CANON" ]]; then
    skind=fixture
    _sync_fixture_canon
  else
    log_fail "_sync_cached: source [$src] is neither the real source nor the canonical fixture source"
  fi
  key="$engine-$skind-$tkind"
  golden="$TMP_ROOT/golden/$key"
  if [[ ! -f "$golden.done" ]]; then
    if [[ -d "$golden" ]]; then chmod -R u+w "$golden"; rm -rf "$golden"; fi
    mkdir -p "$golden"
    if [[ "$tkind" == "git" ]]; then git -C "$golden" init -q -b main; fi
    _hooks_run_engine "$engine" "$src" "$golden" >/dev/null 2>&1 \
      || log_fail "_sync_cached: the real $engine sync into golden $key failed"
    chmod -R a-w "$golden"
    : > "$golden.done"
  fi
  SYNC_LAST_GOLDEN="$golden"
  mkdir -p "$dst"
  cp -Rp "$golden/." "$dst/" || log_fail "_sync_cached: copy of golden $key into $dst failed"
  chmod -R u+w "$dst"
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
  _sync_cached sh "$PROJECT_ROOT" "$dst" git
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
  _sync_cached sh "$PROJECT_ROOT" "$dst_sh" git
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
    _sync_cached ps1 "$PROJECT_ROOT" "$dst_ps" git
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


# --- TEST-022 — .agents/skills mirror is synced + gitignored (parity fix) -----
# Root cause (real downstream incident): .agents/skills is the mirror modern
# Gemini CLI and Cursor read as their PRIMARY discovery path, but aai-sync used
# to sync only .claude/.codex/.gemini skills. A target that ever acquired a
# .agents/skills tree kept a STALE, sync-unmanaged copy that SHADOWED the fresh
# per-harness copies (old skills win, new skills like aai-pr never surface).
# This pins: aai-sync now propagates .agents/skills, gitignores it once,
# refreshes a stale copy on re-sync, and the .ps1 engine does the same.
test_agents_skills_mirror_synced() {
  log_info "TEST-022: aai-sync propagates + gitignores .agents/skills (primary Gemini/Cursor discovery path)..."
  # A fresh, unique dir per call (not a fixed name): TEST-630 replays this
  # exact function a second time in the same process/$TMP_ROOT (mutation
  # proof, D8) — a fixed path would reuse the FIRST call's already-mutated
  # fixture (its own target-only-skill and stale-entry arms leave the tree
  # non-pristine) and the second call's freshness assumptions would break for
  # a reason that has nothing to do with the mutation under test.
  local dst
  dst="$(mktemp -d "${TMP_ROOT}/agents-skills-mirror.XXXXXX")"
  _sync_cached sh "$PROJECT_ROOT" "$dst" git

  # (a) the mirror lands with real skills, not just an empty directory.
  [[ -f "$dst/.agents/skills/aai-pr/SKILL.md" ]] \
    || log_fail "TEST-022: .agents/skills/aai-pr/SKILL.md missing after sync (mirror not propagated)"

  # (b) skill-set parity with .gemini/skills. README.md is a .gemini-only
  #     regenerated index (HARNESS_SKILLS.yaml: .gemini/skills|drop|yes vs
  #     .agents/skills|carry|no), so compare skill DIRECTORIES only.
  local agents_dirs gemini_dirs
  agents_dirs="$(find "$dst/.agents/skills" -mindepth 1 -maxdepth 1 -type d | sed 's#.*/##' | LC_ALL=C sort)"
  gemini_dirs="$(find "$dst/.gemini/skills" -mindepth 1 -maxdepth 1 -type d | sed 's#.*/##' | LC_ALL=C sort)"
  [[ "$agents_dirs" == "$gemini_dirs" ]] \
    || log_fail "TEST-022: .agents/skills skill set differs from .gemini/skills"

  # (c) gitignored exactly once (sync-managed, like the other mirrors).
  local count
  count="$(grep -cxF ".agents/skills/" "$dst/.gitignore")"
  [[ "$count" -eq 1 ]] || log_fail "TEST-022: .agents/skills/ occurs $count time(s) in .gitignore, expected 1"

  # (d) canonical entries are REFRESHED on re-sync (the shadow the fix kills)
  #     AND a target-only project skill is PRESERVED — the entry-by-entry sync
  #     must never wholesale-delete a downstream's own .agents/skills entry.
  rm -rf "$dst/.agents/skills/aai-pr"
  printf 'STALE\n' > "$dst/.agents/skills/aai-loop/SKILL.md"
  mkdir -p "$dst/.agents/skills/aai-project-acme"
  printf 'project-owned\n' > "$dst/.agents/skills/aai-project-acme/SKILL.md"
  bash "$SYNC_SH" "$dst" >/dev/null 2>&1 || log_fail "TEST-022: re-sync failed"
  [[ -f "$dst/.agents/skills/aai-pr/SKILL.md" ]] \
    || log_fail "TEST-022: re-sync did not restore a removed .agents/skills entry (stale shadow would persist)"
  if grep -q STALE "$dst/.agents/skills/aai-loop/SKILL.md"; then
    log_fail "TEST-022: re-sync left a tampered .agents/skills entry stale (would shadow fresh skills)"
  fi
  { [[ -f "$dst/.agents/skills/aai-project-acme/SKILL.md" ]] \
      && grep -q 'project-owned' "$dst/.agents/skills/aai-project-acme/SKILL.md"; } \
    || log_fail "TEST-022: re-sync DELETED a target-only project skill under .agents/skills (data loss)"

  # (e) the gitignore entry stays de-duplicated across re-sync.
  count="$(grep -cxF ".agents/skills/" "$dst/.gitignore")"
  [[ "$count" -eq 1 ]] || log_fail "TEST-022: .agents/skills/ duplicated to $count after re-sync (not idempotent)"

  # (f) ps1 parity — actually RUN the PowerShell engine (when pwsh is present)
  #     and assert it propagates the mirror and gitignores it, not merely that
  #     the path string appears somewhere in the script.
  if command -v pwsh >/dev/null 2>&1; then
    local pdst
    pdst="$(mktemp -d "${TMP_ROOT}/agents-skills-ps1.XXXXXX")"
    _sync_cached ps1 "$PROJECT_ROOT" "$pdst" git
    [[ -f "$pdst/.agents/skills/aai-pr/SKILL.md" ]] \
      || log_fail "TEST-022: aai-sync.ps1 did not propagate .agents/skills (ps1 parity broken)"
    [[ "$(grep -cxF ".agents/skills/" "$pdst/.gitignore")" -eq 1 ]] \
      || log_fail "TEST-022: aai-sync.ps1 did not gitignore .agents/skills/ exactly once"
  else
    PWSH_ARM_SKIPPED=1
    log_info "TEST-022 note: pwsh absent — ps1 parity arm SKIPPED (bash assertions above still ran)"
  fi

  log_pass "TEST-022 .agents/skills synced entry-by-entry (target-only preserved), gitignored once, refreshed on re-sync, ps1 parity exercised"
}

# --- TEST-628 (Spec-AC-11, spec-update-installs-ref-guard-undisclosed) --------
# file_content_different (fu-sync-hash-compare-fails-open) already fails
# closed when `cmp` cannot complete the comparison (exit 2), but no test
# drove that path directly -- the only existing pin (test-aai-layer-profiles.sh
# TEST-004) asserts a downstream symptom a working `cmp` never produces. This
# calls the function directly (extracted from aai-sync.sh via the same
# awk-body-extraction shape test-aai-doctor.sh and test-aai-git-ref-guard.sh
# already use for a sourceable-function unit check -- aai-sync.sh itself is
# not safely sourceable, it runs its whole sync top-to-bottom), driven by an
# UNREADABLE path so `cmp` itself exits 2. The .ps1 twin's catch arm is
# checked statically (residual-risk note: the Windows CI leg is the only
# real runtime check on the twin).
test_628_compare_fails_closed() {
  log_info "TEST-628: file_content_different reports NOT different when cmp cannot complete the comparison (exit 2, driven with an unreadable path); the .ps1 twin's catch arm returns false..."
  local fn readable unreadable out rc=0
  fn="$(awk '/^file_content_different\(\) \{/{f=1} f{print; if ($0 ~ /^}/) exit}' "$SYNC_SH")"
  [[ -n "$fn" ]] || log_fail "TEST-628: could not extract file_content_different() from $SYNC_SH"

  readable="$TMP_ROOT/t628-readable.txt"
  unreadable="$TMP_ROOT/t628-unreadable.txt"
  printf 'a\n' > "$readable"
  printf 'b\n' > "$unreadable"
  chmod 000 "$unreadable"
  if [[ ! -r "$unreadable" ]]; then
    out="$(
      bash -c "
        set -euo pipefail
        $fn
        if file_content_different \"\$1\" \"\$2\"; then echo DIFFERENT; else echo NOT_DIFFERENT; fi
      " _ "$readable" "$unreadable"
    )" || rc=$?
    chmod 644 "$unreadable"
    [[ "$rc" -eq 0 ]] || log_fail "TEST-628: calling file_content_different against an unreadable path errored (rc=$rc): $out"
    [[ "$out" == "NOT_DIFFERENT" ]] \
      || log_fail "TEST-628: file_content_different treated an unreadable-path cmp failure (exit 2) as DIFFERENT, expected NOT_DIFFERENT (fail-closed): $out"
  else
    chmod 644 "$unreadable"
    log_info "TEST-628 note: chmod 000 did not make the file unreadable in this environment (root?) — bash arm SKIPPED, ps1 static arm still runs"
  fi

  # ps1 twin (static): the catch arm of Test-FileContentDifferent must
  # `return $false` (fail closed), never $true.
  local body
  body="$(awk '/^function Test-FileContentDifferent \{$/{f=1} f{print; if ($0 ~ /^}$/) exit}' "$SYNC_PS1")"
  [[ -n "$body" ]] || log_fail "TEST-628: could not extract Test-FileContentDifferent from $SYNC_PS1"
  local catch_body
  catch_body="$(printf '%s\n' "$body" | awk '/} catch \{/{f=1;next} f{print}')"
  [[ -n "$catch_body" ]] || log_fail "TEST-628: Test-FileContentDifferent has no catch block: $body"
  printf '%s\n' "$catch_body" | qgrep -qF 'return $false' \
    || log_fail "TEST-628: Test-FileContentDifferent's catch arm does not return \$false (fail-closed): $catch_body"
  printf '%s\n' "$catch_body" | qgrep -qF 'return $true' \
    && log_fail "TEST-628: Test-FileContentDifferent's catch arm returns \$true somewhere (fail-open): $catch_body"

  log_pass "TEST-628 file_content_different reports NOT_DIFFERENT when cmp cannot complete (exit 2, unreadable path); ps1 catch arm returns \$false"
}

# --- TEST-629/630 (Spec-AC-11, D8): two already-fixed registry items close on
# a mutation that reddens their EXISTING pin, never on a reading of the
# source. These wrap the existing pins (test_bash_seed_crlf_safe / TEST-021,
# test_agents_skills_mirror_synced / TEST-022) rather than duplicate their
# fixtures — running the real pin IS the proof; nothing here re-implements
# it. The inner call runs inside a command substitution (a real subshell) so
# its own log_fail (which calls `exit 1`) only ends that subshell; this
# wrapper then re-raises with a message carrying its OWN TEST-62{9,0} id,
# because mutation-run.mjs attributes a redden by finding that literal id in
# a FAIL line, and the wrapped pin's failure message only ever says
# TEST-021/TEST-022.

test_629_crlf_pin_still_bites() {
  log_info "TEST-629: replaying the existing CRLF pin (test_bash_seed_crlf_safe / TEST-021) under mutation -- fu-gitignore-crlf-exact-line closes on this proof, not a reading..."
  local out rc=0
  out="$(test_bash_seed_crlf_safe 2>&1)" || rc=$?
  [[ "$rc" -eq 0 ]] \
    || log_fail "TEST-629: the existing CRLF pin (test_bash_seed_crlf_safe) failed under mutation:"$'\n'"$out"
  log_pass "TEST-629 the existing CRLF pin still bites under mutation; fu-gitignore-crlf-exact-line closes on this proof"
}

test_630_agents_tree_pin_still_bites() {
  log_info "TEST-630: replaying the existing .agents/skills propagation pin (test_agents_skills_mirror_synced / TEST-022) under mutation -- fu-agents-tree-not-synced closes on this proof, not a reading..."
  local out rc=0
  out="$(test_agents_skills_mirror_synced 2>&1)" || rc=$?
  [[ "$rc" -eq 0 ]] \
    || log_fail "TEST-630: the existing .agents/skills propagation pin (test_agents_skills_mirror_synced) failed under mutation:"$'\n'"$out"
  log_pass "TEST-630 the existing .agents/skills propagation pin still bites under mutation; fu-agents-tree-not-synced closes on this proof"
}

# ── spec-sync-deletes-target-only-hooks — TEST-773..792 ────────────────────
# goodwind-cz/aai#414: aai-sync used to sync hooks/ with copy_replace
# (rm -rf then cp -a), which destroyed any target-only file under hooks/ --
# most damagingly a downstream project's own hooks/merge-guard.{sh,ps1,py}
# safety control -- on every sync, with no advisory of any kind (a purely
# destructive run wrote no report at all). These pin: hooks/ is now a
# file-by-file merge (TEST-773, TEST-774), source-owned hook files still
# overwrite and keep their executable bit (TEST-775), a diverging
# source-owned hook registration JSON is flagged in the advisory rather than
# silently overwritten (TEST-776), the advisory is written on a
# deletion-only run (TEST-777) and stays byte-identical to the pre-change
# engine for a quiet run (TEST-778), the PowerShell engine mirrors all four
# behaviours (TEST-779), a source-retired hook survives disarmed rather than
# deleted (TEST-780), and the four named regression suites stay green
# (TEST-781). TEST-782/783 pin the refusal and node-absent degrade paths;
# TEST-784..788 (owner-directed extension, 2026-09-30) pin update-in-place
# vs. left-as-is -- see the block header above test_784.

# --- TEST-773 (Spec-AC-01) — target-only hook survives a real sync ------------
test_773_hook_target_only_survives_bytes() {
  log_info "TEST-773: a target-only hooks/merge-guard.sh survives a real sync byte-identical..."
  local dst="$TMP_ROOT/hooks-773" recorded="$TMP_ROOT/hooks-773-recorded.sh"
  _sync_cached sh "$PROJECT_ROOT" "$dst" git
  printf '#!/bin/sh\necho guard\n' > "$dst/hooks/merge-guard.sh"
  cp "$dst/hooks/merge-guard.sh" "$recorded"
  bash "$SYNC_SH" "$dst" >/dev/null 2>&1 || log_fail "TEST-773: re-sync failed"
  [[ -f "$dst/hooks/merge-guard.sh" ]] \
    || log_fail "TEST-773: target-only hooks/merge-guard.sh was deleted by the sync"
  cmp -s "$recorded" "$dst/hooks/merge-guard.sh" \
    || log_fail "TEST-773: target-only hooks/merge-guard.sh changed bytes across the sync"
  log_pass "TEST-773 a target-only hooks/merge-guard.sh survives a real sync byte-identical"
}

# --- TEST-774 (Spec-AC-02) — preserved hook is named on stdout ----------------
test_774_hook_target_only_named_on_stdout() {
  log_info "TEST-774: sync stdout carries PRESERVE target-only hook naming hooks/merge-guard.sh..."
  local dst="$TMP_ROOT/hooks-774" log="$TMP_ROOT/hooks-774.log"
  _sync_cached sh "$PROJECT_ROOT" "$dst" git
  printf '#!/bin/sh\necho guard\n' > "$dst/hooks/merge-guard.sh"
  bash "$SYNC_SH" "$dst" >"$log" 2>&1 || log_fail "TEST-774: re-sync failed: $(cat "$log")"
  grep -qF -- 'PRESERVE target-only hook: hooks/merge-guard.sh' "$log" \
    || log_fail "TEST-774: sync stdout did not name the preserved hook: $(cat "$log")"
  log_pass "TEST-774 sync stdout names the preserved target-only hook by path"
}

# --- TEST-775 (Spec-AC-03) — source-owned hook overwritten, stays executable --
test_775_hook_source_owned_overwritten_stays_executable() {
  log_info "TEST-775: a differing hooks/session-start.sh is replaced by source bytes and stays executable..."
  local dst="$TMP_ROOT/hooks-775" src_session="$PROJECT_ROOT/hooks/session-start.sh"
  _sync_cached sh "$PROJECT_ROOT" "$dst" git
  printf '#!/bin/sh\necho tampered\n' > "$dst/hooks/session-start.sh"
  chmod -x "$dst/hooks/session-start.sh"
  bash "$SYNC_SH" "$dst" >/dev/null 2>&1 || log_fail "TEST-775: re-sync failed"
  cmp -s "$src_session" "$dst/hooks/session-start.sh" \
    || log_fail "TEST-775: hooks/session-start.sh was not replaced with source bytes"
  [[ -x "$dst/hooks/session-start.sh" ]] \
    || log_fail "TEST-775: hooks/session-start.sh is not executable after the sync"
  log_pass "TEST-775 a differing source-owned hooks/session-start.sh is overwritten and stays executable"
}

# --- TEST-776 (Spec-AC-04, REVISED by owner amendment 2026-09-30) -------------
# A target-added registration entry inside hooks/hooks.json (e.g. the
# reporter's own PreToolUse -> merge-guard.sh hook) is now ADDITIVELY MERGED,
# not overwritten: it must survive the sync, and the sync SHALL print a
# `MERGE hooks/hooks.json: ...` line. No advisory entry is written for an
# ordinary successful merge -- see TEST-782 for the refusal case.
test_776_hook_json_target_added_entry_survives_merge() {
  log_info "TEST-776: a target-added hooks/hooks.json registration (PreToolUse -> merge-guard.sh) survives an additive-merge sync..."
  local dst="$TMP_ROOT/hooks-776" log="$TMP_ROOT/hooks-776.log"
  _sync_cached sh "$PROJECT_ROOT" "$dst" git
  cat > "$dst/hooks/hooks.json" <<'HOOKSJSON'
{
  "hooks": {
    "SessionStart": [
      { "matcher": "startup|resume|clear|compact", "hooks": [ { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh\"", "async": false } ] }
    ],
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/merge-guard.sh\"", "async": false } ] }
    ]
  }
}
HOOKSJSON
  bash "$SYNC_SH" "$dst" >"$log" 2>&1 || log_fail "TEST-776: re-sync failed: $(cat "$log")"
  grep -qF -- 'MERGE hooks/hooks.json:' "$log" \
    || log_fail "TEST-776: sync stdout did not print a MERGE hooks/hooks.json line: $(cat "$log")"
  grep -qF -- 'merge-guard.sh' "$dst/hooks/hooks.json" \
    || log_fail "TEST-776: the target-added PreToolUse -> merge-guard.sh registration was lost: $(cat "$dst/hooks/hooks.json")"
  grep -qF -- 'SessionStart' "$dst/hooks/hooks.json" \
    || log_fail "TEST-776: the source-owned SessionStart registration is missing after merge: $(cat "$dst/hooks/hooks.json")"
  log_pass "TEST-776 a target-added hooks/hooks.json registration survives an additive-merge sync"
}

# --- TEST-777 (Spec-AC-05) — deletion-only run still writes an advisory -------
test_777_deletion_only_advisory_has_deleted_items() {
  log_info "TEST-777: a deletion-only re-sync writes an advisory with a Deleted items section naming the path..."
  local dst="$TMP_ROOT/hooks-777" newest
  _sync_cached sh "$PROJECT_ROOT" "$dst" git
  mkdir -p "$dst/.aai/zz-target-only"
  printf 'x\n' > "$dst/.aai/zz-target-only/x.txt"
  bash "$SYNC_SH" "$dst" >/dev/null 2>&1 || log_fail "TEST-777: re-sync failed"
  newest="$(find "$dst/docs/ai/reports" -name 'sync-conflicts-*.md' -type f | LC_ALL=C sort | tail -n1)"
  [[ -n "$newest" ]] \
    || log_fail "TEST-777: no advisory was written for a deletion-only run (pre-change baseline: none at all)"
  grep -qF -- '## Deleted items' "$newest" \
    || log_fail "TEST-777: advisory missing the '## Deleted items' heading: $(cat "$newest")"
  grep -qF -- '- Path: .aai/zz-target-only' "$newest" \
    || log_fail "TEST-777: advisory does not name the deleted path: $(cat "$newest")"
  log_pass "TEST-777 a deletion-only re-sync writes an advisory with a Deleted items section naming the path"
}

# --- TEST-778 (Spec-AC-06) — quiet run stays byte-identical to pre-change -----
# "Pre-change" is the exact aai-sync.sh at the commit this scope's own spec
# measured against (goodwind-cz/aai#414, pin v2026.09.30) -- an immutable,
# already-merged point in this repo's history, not the moving HEAD, so this
# pin stays meaningful after the fix itself is committed and merged.
#
# aai-sync.sh resolves its OWN source root two directories above its own
# path ($0/../..), so a bare extracted copy run from $TMP_ROOT cannot find
# .aai/. This builds one real fixture SOURCE tree (the subset of this repo
# aai-sync.sh actually reads from $SRC_ROOT) and swaps only
# .aai/scripts/aai-sync.sh between the two runs, exactly as the spec's own
# verification prescribes.
_778_build_fixture_source() {
  local dir="$1" item
  mkdir -p "$dir"
  for item in .aai hooks .claude .codex .gemini .agents .cursor .claude-plugin docs/knowledge; do
    [[ -e "$PROJECT_ROOT/$item" ]] || continue
    mkdir -p "$dir/$(dirname "$item")"
    cp -R "$PROJECT_ROOT/$item" "$dir/$item"
  done
  if [[ -f "$PROJECT_ROOT/README.md" ]]; then
    cp "$PROJECT_ROOT/README.md" "$dir/README.md"
  fi
  if [[ -f "$PROJECT_ROOT/.github/copilot-instructions.md" ]]; then
    mkdir -p "$dir/.github"
    cp "$PROJECT_ROOT/.github/copilot-instructions.md" "$dir/.github/copilot-instructions.md"
  fi
  if [[ -f "$PROJECT_ROOT/docs/ai/AAI_VERSION.md" ]]; then
    mkdir -p "$dir/docs/ai"
    cp "$PROJECT_ROOT/docs/ai/AAI_VERSION.md" "$dir/docs/ai/AAI_VERSION.md"
  fi
}

test_778_quiet_run_advisory_byte_identical_old_vs_new() {
  log_info "TEST-778: old-engine and new-engine advisories match for a quiet run (no deletion, no hook-JSON divergence), generated-at line excluded..."
  local pre_change_rev="beb6a248"
  git -C "$PROJECT_ROOT" cat-file -e "${pre_change_rev}:.aai/scripts/aai-sync.sh" 2>/dev/null \
    || log_fail "TEST-778: pre-change revision $pre_change_rev is not reachable in this checkout's history (needs full history, e.g. fetch-depth: 0)"

  local fixture_src="$TMP_ROOT/quiet-fixture-src"
  _fixture_source_copy "$fixture_src"

  local dst_old="$TMP_ROOT/quiet-old" dst_new="$TMP_ROOT/quiet-new" old_report new_report
  mkdir -p "$dst_old" "$dst_new"
  git -C "$dst_old" init -q -b main
  git -C "$dst_new" init -q -b main

  # OLD engine run: swap in the pre-change script, sync, then restore.
  git -C "$PROJECT_ROOT" show "${pre_change_rev}:.aai/scripts/aai-sync.sh" > "$fixture_src/.aai/scripts/aai-sync.sh" 2>/dev/null \
    || log_fail "TEST-778: could not extract aai-sync.sh from $pre_change_rev"
  grep -qF -- 'DELETIONS' "$fixture_src/.aai/scripts/aai-sync.sh" \
    && log_fail "TEST-778: the extracted 'old' engine already carries the DELETIONS change -- $pre_change_rev is not a pre-change revision"
  bash "$fixture_src/.aai/scripts/aai-sync.sh" "$dst_old" >/dev/null 2>&1 \
    || log_fail "TEST-778: old-engine sync failed"

  # NEW engine run: the current (changed) script, same fixture source tree.
  cp "$SYNC_SH" "$fixture_src/.aai/scripts/aai-sync.sh"
  bash "$fixture_src/.aai/scripts/aai-sync.sh" "$dst_new" >/dev/null 2>&1 \
    || log_fail "TEST-778: new-engine sync failed"

  old_report="$(find "$dst_old/docs/ai/reports" -name 'sync-conflicts-*.md' -type f | LC_ALL=C sort | tail -n1)"
  new_report="$(find "$dst_new/docs/ai/reports" -name 'sync-conflicts-*.md' -type f | LC_ALL=C sort | tail -n1)"
  [[ -n "$old_report" ]] || log_fail "TEST-778: old engine did not write an advisory (bad fixture -- expected a non-empty overwrite list on a fresh target)"
  [[ -n "$new_report" ]] || log_fail "TEST-778: new engine did not write an advisory (bad fixture)"
  grep -qF -- '## Deleted items' "$new_report" \
    && log_fail "TEST-778: new engine's quiet-run advisory unexpectedly contains a Deleted items heading: $(cat "$new_report")"
  diff <(grep -v -- '^- Generated at (UTC):' "$old_report") <(grep -v -- '^- Generated at (UTC):' "$new_report") \
    || log_fail "TEST-778: quiet-run advisories differ between the old and new engine (beyond the generated-at line)"
  log_pass "TEST-778 old-engine and new-engine advisories match for a quiet run, generated-at line excluded"
}

# --- TEST-779 (Spec-AC-07) — ps1 engine mirrors AC-01,02,04,05 ----------------
# REVISED by owner amendment 2026-09-30: AC-04's ps1 mirror is now the
# additive-merge survival property (TEST-776's ps1 twin), not the old
# "flag the divergence" behavior.
test_779_ps1_engine_hooks_parity() {
  log_info "TEST-779: aai-sync.ps1 preserves+names a target-only hook, additively merges a target-added hooks.json registration, and reports a deletion-only advisory..."
  if ! command -v pwsh >/dev/null 2>&1; then
    PWSH_ARM_SKIPPED=1
    log_info "TEST-779 note: pwsh absent — SKIPPED"
    return 0
  fi
  local dst="$TMP_ROOT/hooks-779-ps1" log="$TMP_ROOT/hooks-779-ps1.log"
  local recorded="$TMP_ROOT/hooks-779-recorded.sh" newest
  _sync_cached ps1 "$PROJECT_ROOT" "$dst" git

  # AC-01 / AC-02: target-only hook survives byte-identical and is named.
  printf '#!/bin/sh\necho guard\n' > "$dst/hooks/merge-guard.sh"
  cp "$dst/hooks/merge-guard.sh" "$recorded"
  # AC-04 (revised): a target-added hooks.json registration survives an
  # additive merge, and the sync prints a MERGE hooks/hooks.json line.
  cat > "$dst/hooks/hooks.json" <<'HOOKSJSON'
{
  "hooks": {
    "SessionStart": [
      { "matcher": "startup|resume|clear|compact", "hooks": [ { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh\"", "async": false } ] }
    ],
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/merge-guard.ps1\"", "async": false } ] }
    ]
  }
}
HOOKSJSON
  pwsh -NoProfile -File "$SYNC_PS1" -TargetRoot "$dst" >"$log" 2>&1 \
    || log_fail "TEST-779: re-sync failed: $(cat "$log")"
  [[ -f "$dst/hooks/merge-guard.sh" ]] \
    || log_fail "TEST-779: target-only hooks/merge-guard.sh was deleted by aai-sync.ps1"
  cmp -s "$recorded" "$dst/hooks/merge-guard.sh" \
    || log_fail "TEST-779: target-only hook changed bytes across the ps1 sync"
  grep -qF -- 'PRESERVE target-only hook: hooks/merge-guard.sh' "$log" \
    || log_fail "TEST-779: ps1 stdout did not name the preserved hook: $(cat "$log")"
  grep -qF -- 'MERGE hooks/hooks.json:' "$log" \
    || log_fail "TEST-779: ps1 stdout did not print a MERGE hooks/hooks.json line: $(cat "$log")"
  grep -qF -- 'merge-guard.ps1' "$dst/hooks/hooks.json" \
    || log_fail "TEST-779: the target-added PreToolUse -> merge-guard.ps1 registration was lost: $(cat "$dst/hooks/hooks.json")"

  # AC-05: a deletion-only re-sync still writes an advisory with Deleted items.
  mkdir -p "$dst/.aai/zz-target-only"
  printf 'x\n' > "$dst/.aai/zz-target-only/x.txt"
  pwsh -NoProfile -File "$SYNC_PS1" -TargetRoot "$dst" >/dev/null 2>&1 \
    || log_fail "TEST-779: deletion-only ps1 re-sync failed"
  newest="$(find "$dst/docs/ai/reports" -name 'sync-conflicts-*.md' -type f | LC_ALL=C sort | tail -n1)"
  grep -qF -- '## Deleted items' "$newest" \
    || log_fail "TEST-779: ps1 advisory missing the Deleted items heading: $(cat "$newest")"
  grep -qF -- '- Path: .aai/zz-target-only' "$newest" \
    || log_fail "TEST-779: ps1 advisory does not name the deleted path: $(cat "$newest")"

  log_pass "TEST-779 aai-sync.ps1 preserves+names a target-only hook, additively merges a target-added hooks.json registration, and reports a deletion-only advisory"
}

# --- TEST-780 (Spec-AC-08, REVISED by owner amendment 2026-09-30) ------------
# The frozen spec's original claim -- a retired hook is DISARMED because
# hooks.json is wholly overwritten and the source's registration vanishes --
# is now FALSE: additive merge never removes an existing target entry. The
# owner-directed property is the opposite: a target's EXISTING registration
# for a hook the source no longer ships SHALL survive (same as any other
# target-added entry), and so SHALL the hook's own file. Retirement (making a
# stale registration disappear) is explicitly OUT OF SCOPE under additive
# merge -- residual risk, not silently dropped (see spec Scope decision).
test_780_retired_hook_registration_and_file_both_survive() {
  log_info "TEST-780: a target's existing hooks.json registration for a source-retired hook survives, and so does the hook's file..."
  local dst="$TMP_ROOT/hooks-780"
  _sync_cached sh "$PROJECT_ROOT" "$dst" git
  printf '#!/bin/sh\necho retired\n' > "$dst/hooks/retired-hook.sh"
  cat > "$dst/hooks/hooks.json" <<'HOOKSJSON'
{
  "hooks": {
    "SessionStart": [
      { "matcher": "startup|resume|clear|compact", "hooks": [ { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh\"", "async": false } ] }
    ],
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/retired-hook.sh\"", "async": false } ] }
    ]
  }
}
HOOKSJSON
  bash "$SYNC_SH" "$dst" >/dev/null 2>&1 || log_fail "TEST-780: re-sync failed"
  [[ -f "$dst/hooks/retired-hook.sh" ]] \
    || log_fail "TEST-780: the retired hook's file was deleted (expected: survives, additive merge never removes)"
  grep -qF -- 'retired-hook.sh' "$dst/hooks/hooks.json" \
    || log_fail "TEST-780: the retired hook's EXISTING registration was removed by the sync (additive merge must never remove a target entry): $(cat "$dst/hooks/hooks.json")"
  grep -qF -- 'SessionStart' "$dst/hooks/hooks.json" \
    || log_fail "TEST-780: the source-owned SessionStart registration is missing after merge: $(cat "$dst/hooks/hooks.json")"
  log_pass "TEST-780 a target's existing registration for a source-retired hook survives the merge, and so does the hook's file"
}

# --- TEST-781 (Spec-AC-09) — the named regression suites stay green ----------
# test-aai-hooks-overlay.sh added to the set by the owner amendment
# (2026-09-30): install_claude_hooks in aai-bootstrap.sh now calls the SAME
# shared .aai/scripts/lib/merge-hooks-json.mjs this scope introduces, so that
# suite is a regression guard for THIS change too, not just a bystander.
test_781_regression_suites_exit_zero() {
  log_info "TEST-781: the sync-engine regression suites are declared companions of this suite..."
  assert_companions aai-sync-seed aai-bootstrap aai-hooks-overlay aai-layer-drift aai-layer-profiles \
    || log_fail "TEST-781 (plan row TEST-011): bootstrap, hooks-overlay, layer-drift and layer-profiles must be selected with aai-sync-seed"
  log_pass "TEST-781 test-aai-layer-drift.sh, test-aai-layer-profiles.sh, test-aai-bootstrap.sh and test-aai-hooks-overlay.sh are selected with this suite (each exits 0 in its own run)"
}

# --- TEST-782 (Spec-AC-10, NEW) — malformed target hooks.json: merge refused,
# file untouched, advisory names it. Pre-amendment behavior (both the
# original beb6a248 engine AND this scope's own first pass) silently
# overwrote a malformed target file with source bytes; the owner amendment
# requires the SAME refuse-loud discipline install_claude_hooks already has.
test_782_hook_json_malformed_merge_refused() {
  log_info "TEST-782: a malformed target hooks/hooks.json refuses the merge, stays byte-untouched, and is named in the advisory..."
  local dst="$TMP_ROOT/hooks-782" before after newest rec_file="$TMP_ROOT/hooks-782-rec.txt"
  _sync_cached sh "$PROJECT_ROOT" "$dst" git
  printf 'NOT JSON {' > "$dst/hooks/hooks.json"
  before="$(cat "$dst/hooks/hooks.json")"
  bash "$SYNC_SH" "$dst" >/dev/null 2>&1 || log_fail "TEST-782: re-sync failed"
  after="$(cat "$dst/hooks/hooks.json")"
  [[ "$before" == "$after" ]] \
    || log_fail "TEST-782: malformed hooks/hooks.json was modified by the sync (want byte-untouched); before=[$before] after=[$after]"
  newest="$(find "$dst/docs/ai/reports" -name 'sync-conflicts-*.md' -type f | LC_ALL=C sort | tail -n1)"
  [[ -n "$newest" ]] || log_fail "TEST-782: no advisory report was written"
  grep -qF -- '- Path: hooks/hooks.json' "$newest" \
    || log_fail "TEST-782: advisory does not name hooks/hooks.json: $(cat "$newest")"
  awk '/^- Path: hooks\/hooks\.json$/{getline; print; exit}' "$newest" > "$rec_file"
  grep -q 'refused' "$rec_file" \
    || log_fail "TEST-782: hooks/hooks.json recommendation does not say the merge was refused: $(cat "$newest")"
  log_pass "TEST-782 a malformed target hooks/hooks.json refuses the merge, stays byte-untouched, and is named in the advisory"
}

# --- TEST-783 (Spec-AC-11, NEW) — node unavailable: hooks.json left
# untouched (never created), advisory names it. Mirrors aai-bootstrap.sh's
# own "node unavailable -> WARN + skip" precedent (never proceed
# destructively when the interpreter the merge needs is absent).
test_783_hook_json_no_node_leaves_untouched() {
  log_info "TEST-783: with node unavailable, hooks/hooks.json is left untouched (not created) and named in the advisory..."
  if ! command -v node >/dev/null 2>&1; then
    log_info "TEST-783 note: node already absent from this runner's PATH -- degrading to a direct assertion against the real environment"
  fi
  local dst="$TMP_ROOT/hooks-783" log="$TMP_ROOT/hooks-783.log" errlog="$TMP_ROOT/hooks-783.err" no_node_path
  mkdir -p "$dst"
  git -C "$dst" init -q -b main
  # A PATH carrying only the directories bash/git themselves need, with every
  # directory that could contain a `node` binary excluded -- proves the
  # DEGRADE path, not just that this one PATH lacks a node symlink.
  no_node_path="$(dirname "$(command -v bash)"):$(dirname "$(command -v git)")"
  # stdout and stderr captured SEPARATELY: Spec-AC-11 says the WARN is on
  # stdout (as it is in the .ps1 engine); a `2>&1` log could not tell a
  # stderr WARN from a stdout one (Validation NB-2, 2026-09-30).
  env PATH="$no_node_path" bash "$SYNC_SH" "$dst" >"$log" 2>"$errlog" \
    || log_fail "TEST-783: sync failed under a node-less PATH (should degrade, not fail): $(cat "$log" "$errlog")"
  if env PATH="$no_node_path" bash -c 'command -v node' >/dev/null 2>&1; then
    log_fail "TEST-783: bad fixture -- node is still resolvable on the stripped PATH"
  fi
  [[ -f "$dst/hooks/hooks.json" ]] \
    && log_fail "TEST-783: hooks/hooks.json was created without node (expected: left untouched/absent)"
  grep -qF -- 'WARN node unavailable' "$log" \
    || log_fail "TEST-783: sync STDOUT did not warn about the missing node interpreter (stderr was: $(cat "$errlog")); stdout: $(cat "$log")"
  local newest
  newest="$(find "$dst/docs/ai/reports" -name 'sync-conflicts-*.md' -type f | LC_ALL=C sort | tail -n1)"
  [[ -n "$newest" ]] || log_fail "TEST-783: no advisory report was written"
  grep -qF -- '- Path: hooks/hooks.json' "$newest" \
    || log_fail "TEST-783: advisory does not name hooks/hooks.json: $(cat "$newest")"
  log_pass "TEST-783 with node unavailable, hooks/hooks.json is left untouched and named in the advisory"
}

# ── owner-directed scope extension (2026-09-30) — TEST-784..788 ─────────────
# Validation measured a second consequence of additive-only merge: a source
# that CHANGES an already-registered hook's command shipped the new command
# as an addition and left the old one registered -- two SessionStart entries
# after a v2 sync, one pointing at a file the source no longer ships, one
# stale entry per release edit in every downstream target. The owner's
# decision: match on the script PATH inside the command and UPDATE the
# source-owned entry in place -- but never rewrite an entry the engine cannot
# prove it authored (the standing priority: a user-modified hook is never
# overwritten). The proof is the `--shipped` snapshot the engine records under
# <target>/.aai/cache/hooks-shipped/: an entry byte-equal to what the engine
# last shipped is provably unmodified engine output (TEST-784, updated); any
# other same-path entry is LEFT AS-IS, not added beside, and named in the
# advisory (TEST-785). A target-added entry whose path the source does not
# ship is untouched in every case (asserted inside both). A fresh target's
# hooks.json is the source's bytes, not a re-serialisation (TEST-786,
# Validation NB-4). An explicit --with-claude-hooks with the merge library
# missing FAILS instead of warn-and-succeeding (TEST-787, Validation NB-3).
# The .ps1 engine mirrors update + left-as-is (TEST-788).
#
# These need a SOURCE whose hooks/hooks.json can be edited between syncs, so
# they build a fixture source tree (same builder as TEST-778) and run the
# engine copy inside it -- never the live repo's hooks.json.

# Count of command entries under one event of a hooks JSON; the merge-guard
# command must also still be present verbatim (the ride's core property).
_hooks_event_count() {
  node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    let n = 0; for (const g of (j.hooks[process.argv[2]] || [])) n += (g.hooks || []).length;
    console.log(n);' "$1" "$2"
}

# Seed the target's hooks/hooks.json with a target-added PreToolUse ->
# merge-guard registration ON TOP of whatever the sync wrote (never a
# hand-written file: the SessionStart entry must be exactly what the engine
# shipped, so the update arm is testing provenance, not a lucky string match).
_hooks_add_merge_guard() {
  node -e '
    const fs = require("fs"); const p = process.argv[1]; const cmd = process.argv[2];
    const j = JSON.parse(fs.readFileSync(p, "utf8"));
    j.hooks.PreToolUse = [{ matcher: "Bash", hooks: [{ type: "command", command: cmd, async: false }] }];
    fs.writeFileSync(p, JSON.stringify(j, null, 2) + "\n");' "$1" "$2"
}

# Edit the fixture SOURCE's SessionStart command: same script path, new flag
# (an ordinary release edit; the path key stays, the command string changes).
_hooks_source_edit_flag() {
  node -e '
    const fs = require("fs"); const p = process.argv[1]; const flag = process.argv[2];
    const j = JSON.parse(fs.readFileSync(p, "utf8"));
    const h = j.hooks.SessionStart[0].hooks[0];
    h.command = h.command.replace(/( --v\d+)?$/, " " + flag);
    fs.writeFileSync(p, JSON.stringify(j, null, 2) + "\n");' "$1" "$2"
}

# --- TEST-784 (Spec-AC-12, NEW) — provably-unmodified source-owned entry is
# UPDATED in place; the target-added entry is untouched; no stale duplicate.
test_784_hook_json_source_edit_updates_in_place() {
  log_info "TEST-784: a source-changed command for a source-owned script path is UPDATED in place (target entry equals what the engine last shipped); the target-added merge-guard entry is untouched..."
  local fixture_src="$TMP_ROOT/upd-784-src" dst="$TMP_ROOT/upd-784" log="$TMP_ROOT/upd-784.log"
  local guard_cmd='"${CLAUDE_PLUGIN_ROOT}/hooks/merge-guard.sh"' guard_needle='hooks/merge-guard.sh\"' n
  _fixture_source_copy "$fixture_src"
  _sync_cached sh "$SYNC_FIXTURE_CANON" "$dst" git
  [[ -f "$dst/.aai/cache/hooks-shipped/hooks.json" ]] \
    || log_fail "TEST-784: the engine did not record what it shipped (.aai/cache/hooks-shipped/hooks.json missing)"
  cmp -s "$fixture_src/hooks/hooks.json" "$dst/.aai/cache/hooks-shipped/hooks.json" \
    || log_fail "TEST-784: the shipped snapshot is not a verbatim copy of the source hooks.json"
  _hooks_add_merge_guard "$dst/hooks/hooks.json" "$guard_cmd"
  _hooks_source_edit_flag "$fixture_src/hooks/hooks.json" "--v2"
  bash "$fixture_src/.aai/scripts/aai-sync.sh" "$dst" >"$log" 2>&1 || log_fail "TEST-784: v2 sync failed: $(cat "$log")"
  grep -qF -- 'MERGE hooks/hooks.json: 0 hook(s) added, 1 updated' "$log" \
    || log_fail "TEST-784: sync stdout did not report exactly one in-place update: $(grep -F 'MERGE hooks/hooks.json' "$log" || cat "$log")"
  n="$(_hooks_event_count "$dst/hooks/hooks.json" SessionStart)"
  [[ "$n" == "1" ]] \
    || log_fail "TEST-784: expected exactly 1 SessionStart command after the v2 sync (updated in place), got $n -- the stale v1 entry accumulated: $(cat "$dst/hooks/hooks.json")"
  grep -qF -- 'session-start.sh\" --v2' "$dst/hooks/hooks.json" \
    || log_fail "TEST-784: the SessionStart entry was not updated to the v2 command: $(cat "$dst/hooks/hooks.json")"
  grep -qF -- "$guard_needle" "$dst/hooks/hooks.json" \
    || log_fail "TEST-784: the target-added PreToolUse -> merge-guard.sh registration was lost by the update: $(cat "$dst/hooks/hooks.json")"
  n="$(_hooks_event_count "$dst/hooks/hooks.json" PreToolUse)"
  [[ "$n" == "1" ]] || log_fail "TEST-784: the target-added PreToolUse entry count changed ($n)"
  # Idempotent: a third run of the same v2 source changes nothing.
  bash "$fixture_src/.aai/scripts/aai-sync.sh" "$dst" >"$log" 2>&1 || log_fail "TEST-784: v2 re-sync failed"
  grep -qF -- 'MERGE hooks/hooks.json: 0 hook(s) added, 0 updated, 1 already present' "$log" \
    || log_fail "TEST-784: a repeated v2 sync was not a no-op: $(grep -F 'MERGE hooks/hooks.json' "$log")"
  log_pass "TEST-784 a source-changed command is updated in place (1 SessionStart entry, no stale duplicate); the target-added merge-guard entry is untouched"
}

# --- TEST-785 (Spec-AC-13, NEW) — an entry the engine cannot prove it
# authored is LEFT AS-IS, the new command is NOT added beside it, and the
# advisory names it. Two arms: (a) edited locally after the engine shipped it;
# (b) no shipped record at all (a target synced by a pre-#414 engine, or a
# fresh clone whose gitignored .aai/cache/ is empty) -- indistinguishable
# from a user edit by the files alone, so the owner's priority wins.
test_785_hook_json_unprovable_entry_left_as_is() {
  log_info "TEST-785: a same-path entry the engine cannot prove it shipped is left as-is, not duplicated, and named in the advisory (edited-locally arm + no-record arm)..."
  local fixture_src="$TMP_ROOT/left-785-src" dst="$TMP_ROOT/left-785" log="$TMP_ROOT/left-785.log"
  local guard_cmd='"${CLAUDE_PLUGIN_ROOT}/hooks/merge-guard.sh"' guard_needle='hooks/merge-guard.sh\"' n newest rec_file="$TMP_ROOT/left-785-rec.txt"
  _fixture_source_copy "$fixture_src"
  _sync_cached sh "$SYNC_FIXTURE_CANON" "$dst" git
  _hooks_add_merge_guard "$dst/hooks/hooks.json" "$guard_cmd"
  # (a) the user edits the source-owned SessionStart command locally.
  _hooks_source_edit_flag "$dst/hooks/hooks.json" "--mine"
  _hooks_source_edit_flag "$fixture_src/hooks/hooks.json" "--v2"
  bash "$fixture_src/.aai/scripts/aai-sync.sh" "$dst" >"$log" 2>&1 || log_fail "TEST-785: v2 sync failed: $(cat "$log")"
  grep -qF -- 'MERGE hooks/hooks.json: 0 hook(s) added, 0 updated, 0 already present, 1 left as-is' "$log" \
    || log_fail "TEST-785(a): sync stdout did not report exactly one left-as-is entry: $(grep -F 'MERGE hooks/hooks.json' "$log" || cat "$log")"
  n="$(_hooks_event_count "$dst/hooks/hooks.json" SessionStart)"
  [[ "$n" == "1" ]] \
    || log_fail "TEST-785(a): expected the user's single SessionStart entry to stand alone, got $n entries (the source's version was added beside it): $(cat "$dst/hooks/hooks.json")"
  grep -qF -- 'session-start.sh\" --mine' "$dst/hooks/hooks.json" \
    || log_fail "TEST-785(a): the user-modified SessionStart entry was rewritten: $(cat "$dst/hooks/hooks.json")"
  grep -qF -- "$guard_needle" "$dst/hooks/hooks.json" \
    || log_fail "TEST-785(a): the target-added merge-guard registration was lost: $(cat "$dst/hooks/hooks.json")"
  newest="$(find "$dst/docs/ai/reports" -name 'sync-conflicts-*.md' -type f | LC_ALL=C sort | tail -n1)"
  [[ -n "$newest" ]] || log_fail "TEST-785(a): no advisory was written for a left-as-is registration"
  awk '/^- Path: hooks\/hooks\.json$/{getline; print; exit}' "$newest" > "$rec_file"
  grep -qF -- 'left as-is' "$rec_file" \
    || log_fail "TEST-785(a): the advisory's hooks/hooks.json recommendation does not say the entry was left as-is: $(cat "$newest")"
  grep -qF -- '--mine' "$rec_file" \
    || log_fail "TEST-785(a): the advisory does not quote the target's own (kept) command: $(cat "$rec_file")"
  grep -qF -- "$TMP_ROOT" "$rec_file" \
    && log_fail "TEST-785(a): the advisory recommendation embeds an absolute filesystem path (Validation NB-5): $(cat "$rec_file")"
  # (b) no shipped record: the target carries the UNMODIFIED v2 entry but the
  # engine has no proof it wrote it; the source moves on to v3.
  local dst_b="$TMP_ROOT/left-785b" log_b="$TMP_ROOT/left-785b.log"
  mkdir -p "$dst_b"
  git -C "$dst_b" init -q -b main
  bash "$fixture_src/.aai/scripts/aai-sync.sh" "$dst_b" >/dev/null 2>&1 || log_fail "TEST-785(b): v2 sync failed"
  rm -rf "$dst_b/.aai/cache/hooks-shipped"
  _hooks_source_edit_flag "$fixture_src/hooks/hooks.json" "--v3"
  bash "$fixture_src/.aai/scripts/aai-sync.sh" "$dst_b" >"$log_b" 2>&1 || log_fail "TEST-785(b): v3 sync failed: $(cat "$log_b")"
  grep -qF -- 'MERGE hooks/hooks.json: 0 hook(s) added, 0 updated, 0 already present, 1 left as-is' "$log_b" \
    || log_fail "TEST-785(b): without a shipped record the engine must not update (cannot tell a user edit from an older source): $(grep -F 'MERGE hooks/hooks.json' "$log_b" || cat "$log_b")"
  grep -qF -- 'session-start.sh\" --v2' "$dst_b/hooks/hooks.json" \
    || log_fail "TEST-785(b): the unprovable v2 entry was rewritten without a shipped record: $(cat "$dst_b/hooks/hooks.json")"
  n="$(_hooks_event_count "$dst_b/hooks/hooks.json" SessionStart)"
  [[ "$n" == "1" ]] || log_fail "TEST-785(b): the v3 command was added beside the unprovable entry ($n SessionStart entries)"
  [[ -f "$dst_b/.aai/cache/hooks-shipped/hooks.json" ]] \
    || log_fail "TEST-785(b): the engine did not (re)record what it shipped, so the next sync could never update either"
  log_pass "TEST-785 a same-path entry the engine cannot prove it shipped is left as-is (edited-locally + no-record arms), never duplicated, and named in the advisory"
}

# --- TEST-786 (Spec-AC-14, NEW — Validation NB-4) — a fresh target's
# hooks/hooks.json is the SOURCE'S BYTES, not a JSON.stringify
# re-serialisation. Regression PIN of a pre-change property: the beb6a248
# engine copied the file verbatim (copy_replace) and this ride's first pass
# (ac042706) regenerated it -- byte-identical only because the repo's own file
# happens to be in stringify shape. A reformatted source proves the difference.
test_786_fresh_target_hooks_json_is_source_bytes() {
  log_info "TEST-786: a fresh target's hooks/hooks.json is byte-identical to a source hooks.json that is NOT in JSON.stringify shape..."
  local fixture_src="$TMP_ROOT/fresh-786-src" dst="$TMP_ROOT/fresh-786"
  _fixture_source_copy "$fixture_src"
  # Same document, 4-space indent + a trailing comment-shaped key: valid JSON
  # that JSON.stringify(x, null, 2) cannot reproduce.
  node -e '
    const fs = require("fs"); const p = process.argv[1];
    const j = JSON.parse(fs.readFileSync(p, "utf8"));
    j._comment = "reformatted by TEST-786";
    fs.writeFileSync(p, JSON.stringify(j, null, 4) + "\n");' "$fixture_src/hooks/hooks.json"
  mkdir -p "$dst"
  git -C "$dst" init -q -b main
  bash "$fixture_src/.aai/scripts/aai-sync.sh" "$dst" >/dev/null 2>&1 || log_fail "TEST-786: fresh sync failed"
  cmp -s "$fixture_src/hooks/hooks.json" "$dst/hooks/hooks.json" \
    || log_fail "TEST-786: fresh target hooks/hooks.json is not the source's bytes:"$'\n'"$(diff "$fixture_src/hooks/hooks.json" "$dst/hooks/hooks.json" || true)"
  log_pass "TEST-786 a fresh target's hooks/hooks.json is the source's bytes verbatim, not a re-serialisation"
}

# --- TEST-787 (Spec-AC-15, NEW — Validation NB-3) — an EXPLICIT
# --with-claude-hooks whose merge library is missing FAILS (exit 3, nothing
# written), the same Review-NB-1 rule the refusal branch already follows: a
# requested capability that delivers nothing must fail, not warn-and-succeed.
# Fixture: a target vendored from THIS source, then the library removed (the
# shape of a target synced from a pre-#414 source), bootstrap run from the
# target's own copy.
test_787_bootstrap_missing_merge_library_fails_explicit_opt_in() {
  log_info "TEST-787: aai-bootstrap.sh --with-claude-hooks exits 3 and writes nothing when the shared merge library is missing..."
  local dst="$TMP_ROOT/lib-absent-hooks-787" log="$TMP_ROOT/lib-absent-hooks-787.log" rc
  _sync_cached sh "$PROJECT_ROOT" "$dst" git
  [[ -f "$dst/.aai/scripts/lib/merge-hooks-json.mjs" ]] \
    || log_fail "TEST-787: bad fixture -- sync did not vendor .aai/scripts/lib/merge-hooks-json.mjs"
  [[ -f "$dst/.aai/templates/hooks/settings-hooks.json" ]] \
    || log_fail "TEST-787: bad fixture -- sync did not vendor the hooks overlay template"
  rm -f "$dst/.aai/scripts/lib/merge-hooks-json.mjs"
  [[ -n "$dst" && "$dst" == /* ]] || log_fail "TEST-787: fixture path is empty or relative (HAZ-CD)"
  rc=0
  ( cd "$dst" && bash .aai/scripts/aai-bootstrap.sh --with-claude-hooks ) >"$log" 2>&1 || rc=$?
  [[ "$rc" -eq 3 ]] \
    || log_fail "TEST-787: expected exit 3 (explicit --with-claude-hooks delivered nothing), got $rc: $(cat "$log")"
  [[ -f "$dst/.claude/settings.json" ]] \
    && log_fail "TEST-787: .claude/settings.json was written although the merge library was missing"
  grep -qF -- 'merge-hooks-json.mjs' "$log" \
    || log_fail "TEST-787: the failure does not name the missing library: $(cat "$log")"
  grep -qF -- 'ERROR' "$log" \
    || log_fail "TEST-787: the failure is not reported as an ERROR (warn-and-succeed shape): $(cat "$log")"
  log_pass "TEST-787 an explicit --with-claude-hooks with the merge library missing exits 3, writes nothing, and names the library"
}

# --- TEST-788 (Spec-AC-07, extended) — the .ps1 engine mirrors TEST-784
# (update in place) and TEST-785(a) (left as-is + advisory).
test_788_ps1_engine_update_and_left_as_is_parity() {
  log_info "TEST-788: aai-sync.ps1 updates a provably-unmodified source-owned entry in place and leaves an unprovable one as-is (advisory named)..."
  if ! command -v pwsh >/dev/null 2>&1; then
    PWSH_ARM_SKIPPED=1
    log_info "TEST-788 note: pwsh absent — SKIPPED"
    return 0
  fi
  local fixture_src="$TMP_ROOT/upd-788-src" dst="$TMP_ROOT/upd-788-ps1" log="$TMP_ROOT/upd-788-ps1.log"
  local guard_cmd='"${CLAUDE_PLUGIN_ROOT}/hooks/merge-guard.ps1"' guard_needle='hooks/merge-guard.ps1\"' n newest rec_file="$TMP_ROOT/upd-788-rec.txt"
  _fixture_source_copy "$fixture_src"
  _sync_cached ps1 "$SYNC_FIXTURE_CANON" "$dst" git
  [[ -f "$dst/.aai/cache/hooks-shipped/hooks.json" ]] \
    || log_fail "TEST-788: the ps1 engine did not record what it shipped"
  _hooks_add_merge_guard "$dst/hooks/hooks.json" "$guard_cmd"
  _hooks_source_edit_flag "$fixture_src/hooks/hooks.json" "--v2"
  pwsh -NoProfile -File "$fixture_src/.aai/scripts/aai-sync.ps1" -TargetRoot "$dst" >"$log" 2>&1 \
    || log_fail "TEST-788: v2 ps1 sync failed: $(cat "$log")"
  grep -qF -- 'MERGE hooks/hooks.json: 0 hook(s) added, 1 updated' "$log" \
    || log_fail "TEST-788: ps1 stdout did not report one in-place update: $(grep -F 'MERGE hooks/hooks.json' "$log" || cat "$log")"
  n="$(_hooks_event_count "$dst/hooks/hooks.json" SessionStart)"
  [[ "$n" == "1" ]] || log_fail "TEST-788: expected 1 SessionStart entry after the ps1 v2 sync, got $n: $(cat "$dst/hooks/hooks.json")"
  grep -qF -- 'session-start.sh\" --v2' "$dst/hooks/hooks.json" \
    || log_fail "TEST-788: ps1 did not update the SessionStart entry to v2: $(cat "$dst/hooks/hooks.json")"
  grep -qF -- "$guard_needle" "$dst/hooks/hooks.json" \
    || log_fail "TEST-788: the target-added merge-guard.ps1 registration was lost: $(cat "$dst/hooks/hooks.json")"
  # left-as-is arm: local edit, then a v3 source.
  _hooks_source_edit_flag "$dst/hooks/hooks.json" "--mine"
  _hooks_source_edit_flag "$fixture_src/hooks/hooks.json" "--v3"
  pwsh -NoProfile -File "$fixture_src/.aai/scripts/aai-sync.ps1" -TargetRoot "$dst" >"$log" 2>&1 \
    || log_fail "TEST-788: v3 ps1 sync failed: $(cat "$log")"
  grep -qF -- 'MERGE hooks/hooks.json: 0 hook(s) added, 0 updated, 0 already present, 1 left as-is' "$log" \
    || log_fail "TEST-788: ps1 did not leave the user-modified entry as-is: $(grep -F 'MERGE hooks/hooks.json' "$log" || cat "$log")"
  grep -qF -- 'session-start.sh\" --mine' "$dst/hooks/hooks.json" \
    || log_fail "TEST-788: ps1 rewrote the user-modified entry: $(cat "$dst/hooks/hooks.json")"
  n="$(_hooks_event_count "$dst/hooks/hooks.json" SessionStart)"
  [[ "$n" == "1" ]] || log_fail "TEST-788: ps1 added the v3 command beside the user's entry ($n SessionStart entries)"
  newest="$(find "$dst/docs/ai/reports" -name 'sync-conflicts-*.md' -type f | LC_ALL=C sort | tail -n1)"
  [[ -n "$newest" ]] || log_fail "TEST-788: ps1 wrote no advisory for a left-as-is registration"
  awk '/^- Path: hooks\/hooks\.json$/{getline; print; exit}' "$newest" > "$rec_file"
  grep -qF -- 'left as-is' "$rec_file" \
    || log_fail "TEST-788: ps1 advisory does not say the entry was left as-is: $(cat "$newest")"
  grep -qF -- "$TMP_ROOT" "$rec_file" \
    && log_fail "TEST-788: ps1 advisory recommendation embeds an absolute filesystem path (Validation NB-5): $(cat "$rec_file")"
  log_pass "TEST-788 aai-sync.ps1 updates a provably-unmodified entry in place and leaves an unprovable one as-is with an advisory entry"
}

# ── Remediation round 2 (2026-09-30) — TEST-789..792 ────────────────────────
# Validation round 2 (BLOCKING-3) measured that proving the COMMAND alone and
# then replacing the whole hook object silently dropped a user-edited matcher
# and a user-added timeout/async -- exactly the loss Amendment 2's rule 3
# promised could not happen. The proof now covers the WHOLE registration:
# the hook object in every field (canonical JSON) and its enclosing matcher
# (TEST-789 bash, TEST-790 ps1). Two non-blocking findings fixed in the same
# round: bash dropped dotfiles under hooks/ where cp -a and the ps1 engine
# did not (NB-B, TEST-791); and a snapshot the engine could not WRITE after
# a merge that did happen was reported as "refused (target left untouched)"
# -- a control stating the opposite of what happened (NB-A, TEST-792).

# Set the SessionStart[0] matcher of a hooks JSON (a user narrowing the
# shipped hook to one event, the likeliest edit on the shipped file).
_hooks_edit_matcher() {
  node -e '
    const fs = require("fs"); const p = process.argv[1];
    const j = JSON.parse(fs.readFileSync(p, "utf8"));
    j.hooks.SessionStart[0].matcher = process.argv[2];
    fs.writeFileSync(p, JSON.stringify(j, null, 2) + "\n");' "$1" "$2"
}

# Add timeout: 120 and flip async: true on SessionStart[0].hooks[0] -- the
# command string stays byte-identical to what the engine shipped.
_hooks_add_fields() {
  node -e '
    const fs = require("fs"); const p = process.argv[1];
    const j = JSON.parse(fs.readFileSync(p, "utf8"));
    const h = j.hooks.SessionStart[0].hooks[0];
    h.async = true; h.timeout = 120;
    fs.writeFileSync(p, JSON.stringify(j, null, 2) + "\n");' "$1"
}

# Add a NEW event (Stop) to the fixture SOURCE so the next merge must WRITE
# the destination (an add), independent of the SessionStart provenance path.
_hooks_source_add_stop_event() {
  node -e '
    const fs = require("fs"); const p = process.argv[1];
    const j = JSON.parse(fs.readFileSync(p, "utf8"));
    j.hooks.Stop = [{ hooks: [{ type: "command", command: "\"${CLAUDE_PLUGIN_ROOT}/hooks/stop.sh\"", async: false }] }];
    fs.writeFileSync(p, JSON.stringify(j, null, 2) + "\n");' "$1"
}

# Canonical JSON of one event's groups, for byte-level "unchanged" assertions.
_hooks_event_json() {
  node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    console.log(JSON.stringify(j.hooks[process.argv[2]] || []));' "$1" "$2"
}

# One provenance arm shared by TEST-789 (bash) and TEST-790 (ps1): sync v1,
# apply the user edit (matcher | fields), ship v2, sync, and assert the
# user's registration survived byte-for-byte, nothing was added beside it,
# stdout reported 1 left as-is, and the advisory names the edit.
# $1 engine (sh|ps1)  $2 arm (matcher|fields)  $3 test id  $4 fixture tag
_hooks_user_edit_preserved_arm() {
  local engine="$1" arm="$2" tid="$3" tag="$4"
  local fixture_src="$TMP_ROOT/$tag-src" dst="$TMP_ROOT/$tag" log="$TMP_ROOT/$tag.log" rec_file="$TMP_ROOT/$tag-rec.txt"
  local before after n newest
  _fixture_source_copy "$fixture_src"
  _sync_cached "$engine" "$SYNC_FIXTURE_CANON" "$dst" git
  [[ -f "$dst/.aai/cache/hooks-shipped/hooks.json" ]] || log_fail "$tid($arm): the engine did not record what it shipped"
  case "$arm" in
    matcher) _hooks_edit_matcher "$dst/hooks/hooks.json" "startup" ;;
    fields)  _hooks_add_fields "$dst/hooks/hooks.json" ;;
    *) log_fail "$tid: unknown arm $arm" ;;
  esac
  before="$(_hooks_event_json "$dst/hooks/hooks.json" SessionStart)"
  _hooks_source_edit_flag "$fixture_src/hooks/hooks.json" "--v2"
  _hooks_run_engine "$engine" "$fixture_src" "$dst" >"$log" 2>&1 || log_fail "$tid($arm): v2 $engine sync failed: $(cat "$log")"
  after="$(_hooks_event_json "$dst/hooks/hooks.json" SessionStart)"
  [[ "$before" == "$after" ]] \
    || log_fail "$tid($arm): the user-modified SessionStart registration was rewritten (command was untouched, so the old command-only proof let it through):"$'\n'"  before: $before"$'\n'"  after:  $after"
  grep -qF -- 'MERGE hooks/hooks.json: 0 hook(s) added, 0 updated, 0 already present, 1 left as-is' "$log" \
    || log_fail "$tid($arm): stdout did not report the entry as left as-is: $(grep -F 'MERGE hooks/hooks.json' "$log" || cat "$log")"
  n="$(_hooks_event_count "$dst/hooks/hooks.json" SessionStart)"
  [[ "$n" == "1" ]] || log_fail "$tid($arm): the v2 command was added beside the user's entry ($n SessionStart entries)"
  newest="$(find "$dst/docs/ai/reports" -name 'sync-conflicts-*.md' -type f | LC_ALL=C sort | tail -n1)"
  [[ -n "$newest" ]] || log_fail "$tid($arm): no advisory was written for the preserved user edit"
  awk '/^- Path: hooks\/hooks\.json$/{getline; print; exit}' "$newest" > "$rec_file"
  grep -qF -- 'left as-is' "$rec_file" \
    || log_fail "$tid($arm): the advisory's hooks/hooks.json entry does not say left as-is: $(cat "$newest")"
  case "$arm" in
    matcher) grep -qF -- 'matcher "startup"' "$rec_file" \
      || log_fail "$tid(matcher): the advisory does not name the user's matcher: $(cat "$rec_file")" ;;
    fields)  grep -qF -- 'timeout' "$rec_file" \
      || log_fail "$tid(fields): the advisory does not name the user-added field: $(cat "$rec_file")" ;;
  esac
  grep -qF -- "$TMP_ROOT" "$rec_file" \
    && log_fail "$tid($arm): the advisory embeds an absolute filesystem path (Validation NB-5): $(cat "$rec_file")"
  return 0
}

# --- TEST-789 (Spec-AC-13, arms c+d) — a user-edited MATCHER and a
# user-added timeout/async on the shipped hook (command untouched) are
# both preserved byte-for-byte and named in the advisory. RED at 1936b504:
# both were reported "1 updated" and silently rewritten.
test_789_hook_json_user_edited_matcher_and_fields_preserved() {
  log_info "TEST-789: a shipped hook whose matcher or non-command fields the user edited is left as-is (whole-object provenance), not rewritten, and named in the advisory..."
  _hooks_user_edit_preserved_arm sh matcher TEST-789 prov-789m
  _hooks_user_edit_preserved_arm sh fields TEST-789 prov-789f
  log_pass "TEST-789 a user-edited matcher and user-added timeout/async both survive a source command change, 1 left as-is, advisory names the edit"
}

# --- TEST-790 (Spec-AC-07 / Spec-AC-13) — the same two arms on the ps1
# engine (same shared library; Validation round 2 probe 4 P3 reproduced the
# loss there too). Absent pwsh exits 42.
test_790_ps1_user_edited_matcher_and_fields_preserved() {
  log_info "TEST-790: aai-sync.ps1 leaves a user-edited matcher / user-added timeout on the shipped hook as-is and names it..."
  if ! command -v pwsh >/dev/null 2>&1; then
    PWSH_ARM_SKIPPED=1
    log_info "TEST-790 note: pwsh absent — SKIPPED"
    return 0
  fi
  _hooks_user_edit_preserved_arm ps1 matcher TEST-790 prov-790m
  _hooks_user_edit_preserved_arm ps1 fields TEST-790 prov-790f
  log_pass "TEST-790 aai-sync.ps1 preserves a user-edited matcher and user-added fields (1 left as-is, advisory named)"
}

# --- TEST-791 (Spec-AC-16) — dotfiles under hooks/ are hooks too: a source
# hooks/.hidden-hook.sh is synced and a target-only hooks/.local-only.sh is
# preserved AND named, by the bash engine exactly as by the ps1 engine and
# the pre-#414 cp -a. RED at 1936b504 (bash globbed without dotglob).
test_791_hooks_dotfiles_synced_and_preserved_cross_engine() {
  log_info "TEST-791: a source dotfile under hooks/ is synced and a target-only dotfile is preserved and named (bash; ps1 parity arm when pwsh is present)..."
  local fixture_src="$TMP_ROOT/dot-791-src" dst="$TMP_ROOT/dot-791" log="$TMP_ROOT/dot-791.log"
  _fixture_source_copy "$fixture_src"
  printf '#!/bin/sh\necho hidden\n' > "$fixture_src/hooks/.hidden-hook.sh"
  mkdir -p "$dst/hooks"
  printf 'mine\n' > "$dst/hooks/.local-only.sh"
  git -C "$dst" init -q -b main
  bash "$fixture_src/.aai/scripts/aai-sync.sh" "$dst" >"$log" 2>&1 || log_fail "TEST-791: bash sync failed: $(cat "$log")"
  cmp -s "$fixture_src/hooks/.hidden-hook.sh" "$dst/hooks/.hidden-hook.sh" \
    || log_fail "TEST-791: the bash engine did not sync the source dotfile hooks/.hidden-hook.sh (cp -a and the ps1 engine do)"
  [[ "$(cat "$dst/hooks/.local-only.sh")" == "mine" ]] \
    || log_fail "TEST-791: the target-only dotfile hooks/.local-only.sh was lost or changed"
  grep -qF -- 'PRESERVE target-only hook: hooks/.local-only.sh' "$log" \
    || log_fail "TEST-791: bash stdout did not name the preserved target-only dotfile: $(cat "$log")"
  if command -v pwsh >/dev/null 2>&1; then
    local dst_ps="$TMP_ROOT/dot-791-ps1" log_ps="$TMP_ROOT/dot-791-ps1.log"
    mkdir -p "$dst_ps/hooks"
    printf 'mine\n' > "$dst_ps/hooks/.local-only.sh"
    git -C "$dst_ps" init -q -b main
    pwsh -NoProfile -File "$fixture_src/.aai/scripts/aai-sync.ps1" -TargetRoot "$dst_ps" >"$log_ps" 2>&1 \
      || log_fail "TEST-791: ps1 sync failed: $(cat "$log_ps")"
    cmp -s "$fixture_src/hooks/.hidden-hook.sh" "$dst_ps/hooks/.hidden-hook.sh" \
      || log_fail "TEST-791: the ps1 engine did not sync the source dotfile"
    grep -qF -- 'PRESERVE target-only hook: hooks/.local-only.sh' "$log_ps" \
      || log_fail "TEST-791: ps1 stdout did not name the preserved target-only dotfile: $(cat "$log_ps")"
  else
    PWSH_ARM_SKIPPED=1
    log_info "TEST-791 note: pwsh absent — ps1 parity arm SKIPPED"
  fi
  log_pass "TEST-791 dotfiles under hooks/ are synced (source) and preserved + named (target-only) by the bash engine, matching ps1"
}

# --- TEST-792 (Spec-AC-17, Spec-AC-07) — when the shipped snapshot cannot
# be written (its path is a directory) after a merge that DID write the
# target, the run reports the merge (MERGE line, target written) plus a
# WARN naming the unrecorded snapshot, and the advisory entry says the merge
# was applied -- never "refused (target left untouched)". RED at 1936b504:
# no MERGE line, "refused (target left untouched)" for a written file.
_hooks_snapshot_unwritable_arm() {
  local engine="$1" tid="$2" tag="$3"
  local fixture_src="$TMP_ROOT/$tag-src" dst="$TMP_ROOT/$tag" log="$TMP_ROOT/$tag.log" rec_file="$TMP_ROOT/$tag-rec.txt" newest
  _fixture_source_copy "$fixture_src"
  _sync_cached "$engine" "$SYNC_FIXTURE_CANON" "$dst" git
  rm -rf "$dst/.aai/cache/hooks-shipped/hooks.json"
  mkdir -p "$dst/.aai/cache/hooks-shipped/hooks.json"
  _hooks_source_add_stop_event "$fixture_src/hooks/hooks.json"
  _hooks_run_engine "$engine" "$fixture_src" "$dst" >"$log" 2>&1 || log_fail "$tid: v2 $engine sync failed (a snapshot write failure must degrade, not fail): $(cat "$log")"
  grep -qF -- 'MERGE hooks/hooks.json: 1 hook(s) added' "$log" \
    || log_fail "$tid: the merge that happened was not reported as a merge: $(grep -E 'MERGE|WARN' "$log" || cat "$log")"
  grep -qF -- 'stop.sh' "$dst/hooks/hooks.json" \
    || log_fail "$tid: bad fixture -- the Stop hook was not merged into the target: $(cat "$dst/hooks/hooks.json")"
  grep -qF -- 'shipped snapshot could not be recorded' "$log" \
    || log_fail "$tid: stdout did not WARN that the snapshot was not recorded: $(cat "$log")"
  grep -qF -- 'target left untouched' "$log" \
    && log_fail "$tid: stdout claims the target was left untouched although it was written: $(cat "$log")"
  newest="$(find "$dst/docs/ai/reports" -name 'sync-conflicts-*.md' -type f | LC_ALL=C sort | tail -n1)"
  [[ -n "$newest" ]] || log_fail "$tid: no advisory was written for the unrecorded snapshot"
  awk '/^- Path: hooks\/hooks\.json$/{getline; print; exit}' "$newest" > "$rec_file"
  grep -qF -- 'could not record what it shipped' "$rec_file" \
    || log_fail "$tid: the advisory does not say the snapshot was not recorded: $(cat "$newest")"
  grep -qF -- 'left untouched' "$rec_file" \
    && log_fail "$tid: the advisory claims the target was left untouched although it was written: $(cat "$rec_file")"
  grep -qF -- "$TMP_ROOT" "$rec_file" \
    && log_fail "$tid: the advisory embeds an absolute filesystem path (Validation NB-5): $(cat "$rec_file")"
  return 0
}

test_792_snapshot_unwritable_reports_true_state() {
  log_info "TEST-792: a merge whose shipped snapshot cannot be written is reported as applied + snapshot not recorded, never as refused/untouched (bash; ps1 arm when pwsh is present)..."
  _hooks_snapshot_unwritable_arm sh TEST-792 snap-792
  if command -v pwsh >/dev/null 2>&1; then
    _hooks_snapshot_unwritable_arm ps1 TEST-792 snap-792-ps1
  else
    PWSH_ARM_SKIPPED=1
    log_info "TEST-792 note: pwsh absent — ps1 arm SKIPPED"
  fi
  log_pass "TEST-792 a snapshot write failure after a real merge is reported truthfully (merge applied, snapshot not recorded) on both engines"
}


# -- TEST-793 (Codex P1 / P2 on PR #415) -------------------------------------
# The pre-change copy_replace UNLINKED the destination, so a committed
# hooks.json symlink was replaced. A merge writes THROUGH the link, so a link
# aimed outside the target would have this engine rewrite a file the sync was
# never asked to touch. Also asserts the atomic write leaves no temp residue.
test_793_symlink_destination_refused_and_write_is_atomic() {
  log_info "TEST-793: a symlinked hooks.json is refused, the file it points at is untouched, and a merge leaves no temp residue..."
  local root outside victim before after out plain residue
  root="$(mktemp -d "${TMPDIR:-/tmp}/sync-793.XXXXXX")"
  outside="$(mktemp -d "${TMPDIR:-/tmp}/sync-793-out.XXXXXX")"
  victim="$outside/victim.json"
  printf '%s\n' '{"hooks":{"Stop":[{"matcher":"x","hooks":[{"type":"command","command":"outside.sh"}]}]}}' > "$victim"
  before="$(shasum -a 256 "$victim" | awk '{print $1}')"

  mkdir -p "$root/hooks"
  ln -s "$victim" "$root/hooks/hooks.json"

  set +e
  out="$(node "$PROJECT_ROOT/.aai/scripts/lib/merge-hooks-json.mjs" "$PROJECT_ROOT/hooks/hooks.json" "$root/hooks/hooks.json" 2>&1)"
  set -e

  case "$out" in
    *"is a symbolic link"*) : ;;
    *) log_fail "TEST-793: the refusal must name the symlink as the reason; got: $out" ;;
  esac

  after="$(shasum -a 256 "$victim" | awk '{print $1}')"
  [[ "$before" == "$after" ]] \
    || log_fail "TEST-793: the file OUTSIDE the target was modified through the symlink"
  [[ -L "$root/hooks/hooks.json" ]] \
    || log_fail "TEST-793: the symlink was replaced instead of refused"

  plain="$(mktemp -d "${TMPDIR:-/tmp}/sync-793-plain.XXXXXX")"
  mkdir -p "$plain/hooks"
  printf '%s\n' '{"hooks":{}}' > "$plain/hooks/hooks.json"
  node "$PROJECT_ROOT/.aai/scripts/lib/merge-hooks-json.mjs" "$PROJECT_ROOT/hooks/hooks.json" "$plain/hooks/hooks.json" >/dev/null 2>&1
  residue="$(find "$plain/hooks" -name '.*.tmp' | wc -l | tr -d ' ')"
  [[ "$residue" == "0" ]] \
    || log_fail "TEST-793: the atomic write left $residue temp file(s) behind in hooks/"
  node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$plain/hooks/hooks.json" \
    || log_fail "TEST-793: the merged hooks.json is not valid JSON after an atomic write"

  rm -rf "$root" "$outside" "$plain"
  log_pass "TEST-793 a symlinked destination is refused without following or replacing it, and the merged write leaves no temp residue"
}

# --- sync cache, hot-spots D3 (plan rows TEST-006, TEST-007, TEST-008) ---------
# test_794..796 pin the _sync_cached helper itself: the golden is read-only and
# every request gets an independent writable copy (794); a cached copy equals a
# fresh real sync from a differently located identical source, and the engines
# read nothing of an existing pin but its Profile (795); and the cache is adopted
# widely without ever replacing a re-sync or a sync whose output is asserted (796).

# Files under $1 that carry an owner executable bit, relative to $1, sorted.
_794_exec_list() {
  local root="$1"
  find "$root" -type f -perm -u+x -print | sed "s|^$root||" | LC_ALL=C sort
}

test_794_sync_cache_golden_isolation() {
  log_info "TEST-794: a sync golden is read-only, every copy is writable and equals it (contents + executable bits), two keys give two goldens..."
  local d1="$TMP_ROOT/cache-794-a" d2="$TMP_ROOT/cache-794-b" d3="$TMP_ROOT/cache-794-c"
  local golden golden2 diffs
  _sync_cached sh "$PROJECT_ROOT" "$d1" git
  golden="$SYNC_LAST_GOLDEN"
  _sync_cached sh "$PROJECT_ROOT" "$d2" git
  [[ "$SYNC_LAST_GOLDEN" == "$golden" ]] \
    || log_fail "TEST-794 (plan row TEST-006): two requests for one key were served by two goldens ($golden vs $SYNC_LAST_GOLDEN)"

  # Both copies equal the golden in contents and in executable bits.
  diffs="$(diff -rq "$golden" "$d1" 2>&1 || true)"
  [[ -z "$diffs" ]] || log_fail "TEST-794 (plan row TEST-006): copy A differs from its golden: $diffs"
  diffs="$(diff -rq "$golden" "$d2" 2>&1 || true)"
  [[ -z "$diffs" ]] || log_fail "TEST-794 (plan row TEST-006): copy B differs from its golden: $diffs"
  [[ -n "$(_794_exec_list "$golden")" ]] \
    || log_fail "TEST-794 (plan row TEST-006): bad fixture -- the golden holds no executable file to compare"
  [[ "$(_794_exec_list "$golden")" == "$(_794_exec_list "$d1")" ]] \
    || log_fail "TEST-794 (plan row TEST-006): copy A lost or gained executable bits relative to the golden"
  [[ "$(_794_exec_list "$golden")" == "$(_794_exec_list "$d2")" ]] \
    || log_fail "TEST-794 (plan row TEST-006): copy B lost or gained executable bits relative to the golden"

  # A copy is writable (the directory and a file inside it).
  { : > "$d1/zz-writable"; } 2>/dev/null \
    || log_fail "TEST-794 (plan row TEST-006): a copy is not writable"
  { printf 'x\n' >> "$d1/.aai/system/AAI_PIN.md"; } 2>/dev/null \
    || log_fail "TEST-794 (plan row TEST-006): a file inside a copy is not writable"

  # No state leaks between copies or back into the golden.
  diffs="$(diff -rq "$golden" "$d2" 2>&1 || true)"
  [[ -z "$diffs" ]] || log_fail "TEST-794 (plan row TEST-006): a write into copy A showed up in copy B: $diffs"
  [[ ! -e "$golden/zz-writable" ]] \
    || log_fail "TEST-794 (plan row TEST-006): a write into copy A reached the golden"

  # A write into the golden fails (root ignores file modes, so skip the arm there).
  if [[ "$(id -u)" != "0" ]]; then
    if { : > "$golden/zz-golden-write"; } 2>/dev/null; then
      rm -f "$golden/zz-golden-write"
      log_fail "TEST-794 (plan row TEST-006): a write into the golden succeeded; the golden is not read-only"
    fi
    if { printf 'x\n' >> "$golden/.aai/system/AAI_PIN.md"; } 2>/dev/null; then
      log_fail "TEST-794 (plan row TEST-006): a file inside the golden is writable"
    fi
  else
    log_info "TEST-794 note: running as root -- the golden write-refusal arm is skipped"
  fi

  # A second key gets its own golden.
  _sync_cached sh "$SYNC_FIXTURE_CANON" "$d3" git
  golden2="$SYNC_LAST_GOLDEN"
  [[ "$golden2" != "$golden" ]] \
    || log_fail "TEST-794 (plan row TEST-006): a second key reused the first key's golden"
  diffs="$(diff -rq "$golden" "$golden2" 2>&1 || true)"
  [[ -n "$diffs" ]] \
    || log_fail "TEST-794 (plan row TEST-006): the real-source and fixture-source goldens are identical, so the key does not discriminate"
  log_pass "TEST-794 a golden is read-only; each copy is writable, equals it in contents and executable bits, and leaks nothing to another copy; two keys give two goldens"
}

# One golden against one fresh real sync from a differently located identical
# source. The fresh syncs of all keys are independent (own source copy, own
# target), so they run concurrently: _795_start launches one, _795_check compares.
# $1 engine  $2 source kind (real|fixture)  $3 ordinal
_795_PIDS=""
_795_start() {
  local engine="$1" skind="$2" n="$3" src second fresh f
  if [[ "$skind" == "real" ]]; then src="$PROJECT_ROOT"; else src="$SYNC_FIXTURE_CANON"; fi
  _sync_cached "$engine" "$src" "$TMP_ROOT/eq-795-$n-copy" git
  # The "identical source": the engine-visible subset (the fixture builder) in
  # another place; for the real key plus the four root files the engine copies.
  second="$TMP_ROOT/eq-795-$n-src"
  _fixture_source_copy "$second"
  if [[ "$skind" == "real" ]]; then
    for f in CLAUDE.md CODEX.md GEMINI.md SKILLS.md; do
      if [[ -f "$PROJECT_ROOT/$f" ]]; then cp "$PROJECT_ROOT/$f" "$second/$f"; fi
    done
  fi
  fresh="$TMP_ROOT/eq-795-$n-fresh"
  mkdir -p "$fresh"
  git -C "$fresh" init -q -b main
  ( _hooks_run_engine "$engine" "$second" "$fresh" >/dev/null 2>&1 ) &
  _795_PIDS="$_795_PIDS $!:$n:$engine/$skind"
}

_795_check() {
  local engine="$1" skind="$2" n="$3" golden fresh diffs rest a b
  golden="$TMP_ROOT/golden/$engine-$skind-git"
  fresh="$TMP_ROOT/eq-795-$n-fresh"
  # Tree: the only differing paths are the pin and the advisory file name.
  diffs="$(diff -rq "$golden" "$fresh" 2>&1 || true)"
  rest="$(printf '%s\n' "$diffs" | grep -vE '/\.aai/system/AAI_PIN\.md and .* differ$|^Only in .*/docs/ai/reports: sync-conflicts-[0-9-]+\.md$' || true)"
  [[ -z "$rest" ]] \
    || log_fail "TEST-795 (plan row TEST-007): a cached $engine/$skind golden differs from a fresh sync beyond the pin and the advisory name:"$'\n'"$rest"
  # Pin: equal apart from the four path- or time-dependent lines.
  a="$(grep -vE '^- (Source path|Template commit|Canonical repo|Synced at \(UTC\)):' "$golden/.aai/system/AAI_PIN.md" || true)"
  b="$(grep -vE '^- (Source path|Template commit|Canonical repo|Synced at \(UTC\)):' "$fresh/.aai/system/AAI_PIN.md" || true)"
  [[ -n "$a" && "$a" == "$b" ]] \
    || log_fail "TEST-795 (plan row TEST-007): the $engine/$skind pins differ beyond Source path, Template commit, Canonical repo and Synced at:"$'\n'"$(diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") || true)"
  # Advisory: one file each, equal apart from its Generated at and Source header lines.
  a="$(find "$golden/docs/ai/reports" -name 'sync-conflicts-*.md' -type f | wc -l | tr -d ' ')"
  b="$(find "$fresh/docs/ai/reports" -name 'sync-conflicts-*.md' -type f | wc -l | tr -d ' ')"
  [[ "$a" == "1" && "$b" == "1" ]] \
    || log_fail "TEST-795 (plan row TEST-007): expected one advisory per sync ($engine/$skind), got golden=$a fresh=$b"
  a="$(grep -vE '^- (Generated at \(UTC\)|Source):' "$golden"/docs/ai/reports/sync-conflicts-*.md || true)"
  b="$(grep -vE '^- (Generated at \(UTC\)|Source):' "$fresh"/docs/ai/reports/sync-conflicts-*.md || true)"
  [[ -n "$a" && "$a" == "$b" ]] \
    || log_fail "TEST-795 (plan row TEST-007): the $engine/$skind advisories differ beyond their Generated at and Source header lines:"$'\n'"$(diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") || true)"
}

test_795_sync_cache_equivalence() {
  log_info "TEST-795: per golden key a fresh sync from a differently located identical source equals the golden apart from the pin and advisory path lines; the engines read only Profile from an existing pin..."
  local n=0 engine skind fields entry arms="" arm
  _795_PIDS=""
  for engine in sh ps1; do
    if [[ "$engine" == "ps1" ]] && ! command -v pwsh >/dev/null 2>&1; then
      PWSH_ARM_SKIPPED=1
      log_info "TEST-795 note: pwsh absent -- ps1 keys SKIPPED"
      continue
    fi
    for skind in real fixture; do
      n=$((n + 1))
      _795_start "$engine" "$skind" "$n"
      arms="$arms $engine:$skind:$n"
    done
  done
  for entry in $_795_PIDS; do
    wait "${entry%%:*}" \
      || log_fail "TEST-795 (plan row TEST-007): the real sync from the second source failed (${entry##*:})"
  done
  for arm in $arms; do
    _795_check "${arm%%:*}" "$(echo "$arm" | cut -d: -f2)" "${arm##*:}"
  done

  # Static: the only field either engine reads from an existing pin is Profile.
  fields="$(grep -oE "s/\^- [A-Za-z ()]+: //p" "$SYNC_SH" | LC_ALL=C sort -u || true)"
  [[ "$fields" == "s/^- Profile: //p" ]] \
    || log_fail "TEST-795 (plan row TEST-007): aai-sync.sh reads a pin field other than Profile (or none): [$fields]"
  fields="$(grep -oE "Pattern '\^- [A-Za-z ()]+:" "$SYNC_PS1" | LC_ALL=C sort -u || true)"
  [[ "$fields" == "Pattern '^- Profile:" ]] \
    || log_fail "TEST-795 (plan row TEST-007): aai-sync.ps1 reads a pin field other than Profile (or none): [$fields]"
  fields="$(grep -nE '\^- (Source path|Template version|Template commit|Canonical repo|Synced at)' "$SYNC_SH" "$SYNC_PS1" || true)"
  [[ -z "$fields" ]] \
    || log_fail "TEST-795 (plan row TEST-007): an engine matches a pin field other than Profile: $fields"
  log_pass "TEST-795 a cached golden equals a fresh sync from a differently located identical source (pin and advisory path lines aside); both engines read only Profile from an existing pin"
}

test_796_sync_cache_adoption() {
  log_info "TEST-796: the suite routes at least 15 first syncs through _sync_cached, never one that captures output, and keeps its direct engine calls..."
  local self="${BASH_SOURCE[0]}" calls bad direct
  # Count only the conversions in the suite proper (the lines before this block's
  # own pin tests, which call _sync_cached to test it).
  calls="$(awk '/^# --- sync cache, hot-spots D3 \(plan rows/{exit} /^[[:space:]]*_sync_cached[[:space:]]/{n++} END{print n+0}' "$self")"
  [[ "$calls" -ge 15 ]] \
    || log_fail "TEST-796 (plan row TEST-008): only $calls _sync_cached call site(s) in this suite, expected at least 15"
  bad="$(grep -nE '^[[:space:]]*_sync_cached[[:space:]].*(>|\$\(|\|)' "$self" || true)"
  [[ -z "$bad" ]] \
    || log_fail "TEST-796 (plan row TEST-008): a _sync_cached call captures or pipes output (a first sync whose output is asserted must stay a real engine call): $bad"
  # Every re-sync and every asserted sync is a direct engine call; a floor keeps
  # them from being converted wholesale.
  direct="$(grep -cE '^[[:space:]]*(env PATH="[^"]*" )?(bash "\$(SYNC_SH|fixture_src/\.aai/scripts/aai-sync\.sh)"|pwsh -NoProfile -File "\$(SYNC_PS1|fixture_src/\.aai/scripts/aai-sync\.ps1)"|_hooks_run_engine "\$engine")' "$self" || true)"
  [[ "$direct" -ge 30 ]] \
    || log_fail "TEST-796 (plan row TEST-008): only $direct direct engine call line(s) remain, expected at least 30 (every re-sync and asserted first sync stays real)"
  log_pass "TEST-796 $calls first syncs go through _sync_cached, none captures output, $direct direct engine calls remain"
}

main() {
  echo "=== Test Suite: $TEST_NAME ==="
  check_deps

  # Single-test dispatch (mutation-run.mjs D3 --selector; same shape as
  # test-aai-release.sh's main()): a mutation isolated to a widely-used
  # shared helper (e.g. gitignore-block.sh) can break an EARLIER test in the
  # full-suite run below, which would make the suite exit before ever
  # reaching the row's own FAIL line -- INCONCLUSIVE rather than RED, even
  # when the row's own assertion is the one that actually catches the
  # mutation. Positional dispatch lets the mutation gate run exactly the
  # test a row names.
  if [[ $# -gt 0 ]]; then
    "$1"
    echo "=== $TEST_NAME: SELECTED TEST PASSED ($1) ==="
    return
  fi

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
  test_agents_skills_mirror_synced
  test_628_compare_fails_closed
  test_629_crlf_pin_still_bites
  test_630_agents_tree_pin_still_bites
  test_773_hook_target_only_survives_bytes
  test_774_hook_target_only_named_on_stdout
  test_775_hook_source_owned_overwritten_stays_executable
  test_776_hook_json_target_added_entry_survives_merge
  test_777_deletion_only_advisory_has_deleted_items
  test_778_quiet_run_advisory_byte_identical_old_vs_new
  test_779_ps1_engine_hooks_parity
  test_780_retired_hook_registration_and_file_both_survive
  test_781_regression_suites_exit_zero
  test_782_hook_json_malformed_merge_refused
  test_783_hook_json_no_node_leaves_untouched
  test_784_hook_json_source_edit_updates_in_place
  test_785_hook_json_unprovable_entry_left_as_is
  test_786_fresh_target_hooks_json_is_source_bytes
  test_787_bootstrap_missing_merge_library_fails_explicit_opt_in
  test_788_ps1_engine_update_and_left_as_is_parity
  test_789_hook_json_user_edited_matcher_and_fields_preserved
  test_790_ps1_user_edited_matcher_and_fields_preserved
  test_791_hooks_dotfiles_synced_and_preserved_cross_engine
  test_792_snapshot_unwritable_reports_true_state
  test_793_symlink_destination_refused_and_write_is_atomic
  test_794_sync_cache_golden_isolation
  test_795_sync_cache_equivalence
  test_796_sync_cache_adoption
  if [[ "$PWSH_ARM_SKIPPED" -eq 1 ]]; then
    log_skip "pwsh absent — one or more PowerShell assertions were not exercised (all bash-only assertions above passed)"
  fi
  echo "=== All $TEST_NAME tests passed ==="
}

main "$@"
