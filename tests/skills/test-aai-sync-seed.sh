#!/usr/bin/env bash
#
# Test: aai-sync seeds docs/ai/update-config.yaml when missing
# (CHANGE seed-update-config).
#
# Verifies the seed-when-missing behavior mirroring the TECHNOLOGY.md seed:
#   - a FRESH target (no docs/ai/update-config.yaml) is SEEDED from
#     .aai/templates/update-config.template.yaml with the documented default
#     policy (mode: notify + throttle_hours: 24 + the key comments).
#   - an EXISTING target docs/ai/update-config.yaml is PRESERVED byte-for-byte
#     across a re-sync (project-owned policy is never clobbered).
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
  before="$(sha256sum "$cfg" | awk '{print $1}')"

  bash "$SYNC_SH" "$dst" >/dev/null 2>&1 || log_fail "re-sync failed"

  [[ -f "$cfg" ]] || log_fail "re-sync removed the existing config"
  after="$(sha256sum "$cfg" | awk '{print $1}')"
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
  fi
  log_pass "TEST-003 template classified in core + both scripts seed it (parity)"
}

main() {
  echo "=== Test Suite: $TEST_NAME ==="
  check_deps
  test_seed_fresh
  test_preserve_existing
  test_template_and_parity
  echo "=== All $TEST_NAME tests passed ==="
}

main "$@"
