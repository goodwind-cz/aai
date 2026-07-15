#!/usr/bin/env bash
#
# Test: vendored-layer drift check (CHANGE doctor-vendored-layer-drift /
# SPEC spec-doctor-vendored-layer-drift)
#
# Verifies .aai/scripts/layer-drift.mjs (pin vs canonical comparison with
# honest distance tiers and strict degrade-and-report), the AAI_PIN contract
# extension ("Canonical repo:" stamped by aai-sync), and the SKILL_DOCTOR
# CAT-13 wiring. Implements TEST-001..TEST-011 from the frozen spec.
#
# ZERO REAL NETWORK: the fake canonical repo is a local `git init` fixture;
# the ls-remote tier is exercised through file:// URLs; the offline tier
# through a file:// URL to a nonexistent path. (Spec-AC-04)
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-layer-drift"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DRIFT_SCRIPT="$PROJECT_ROOT/.aai/scripts/layer-drift.mjs"
SYNC_SH="$PROJECT_ROOT/.aai/scripts/aai-sync.sh"
SYNC_PS1="$PROJECT_ROOT/.aai/scripts/aai-sync.ps1"
UPDATE_SH="$PROJECT_ROOT/.aai/scripts/aai-update.sh"
DOCTOR_PROMPT="$PROJECT_ROOT/.aai/SKILL_DOCTOR.prompt.md"

TMP_ROOT=""
CANON=""        # fixture canonical repo (git dir)
CANON_SHAS=()   # commit shas oldest..newest

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

# Run the drift CLI; never aborts the suite on non-zero exit (callers inspect $?).
rundrift() {
  node "$DRIFT_SCRIPT" "$@"
}

# Write a pin file. Args: <path> <commit> [canonical_repo] [source_path]
write_pin() {
  local pin_path="$1" commit="$2" repo="${3:-}" src="${4:-}"
  mkdir -p "$(dirname "$pin_path")"
  {
    echo "# AAI Pin"
    echo ""
    [[ -n "$src" ]] && echo "- Source path: $src"
    echo "- Template version: v-test"
    echo "- Template commit: $commit"
    [[ -n "$repo" ]] && echo "- Canonical repo: $repo"
    echo "- Synced at (UTC): 2026-07-16T00:00:00Z"
  } > "$pin_path"
}

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aai-layer-drift-test.XXXXXX")"
  log_pass "Dependencies checked"
}

# Build the fake canonical repo: 3 commits on main, origin remote configured.
build_canonical_fixture() {
  log_info "Building fake canonical repo fixture (3 commits, no network)..."
  CANON="$TMP_ROOT/canonical"
  mkdir -p "$CANON"
  git -C "$CANON" init -q -b main
  git -C "$CANON" config user.email "test@example.invalid"
  git -C "$CANON" config user.name "AAI Test"
  git -C "$CANON" remote add origin "https://example.invalid/goodwind-cz/aai.git"
  for i in 1 2 3; do
    echo "content $i" > "$CANON/file.txt"
    git -C "$CANON" add file.txt
    git -C "$CANON" commit -qm "commit $i"
    CANON_SHAS+=("$(git -C "$CANON" rev-parse HEAD)")
  done
  [[ ${#CANON_SHAS[@]} -eq 3 ]] || log_fail "fixture build produced ${#CANON_SHAS[@]} commits"
  log_pass "Canonical fixture at $CANON (HEAD ${CANON_SHAS[2]:0:7})"
}

# --- TEST-001 — usage errors exit 2 (Spec-AC-03 hard edges) -------------------
test_usage_errors() {
  log_info "TEST-001: unknown flag and missing flag value exit 2..."
  [[ -f "$DRIFT_SCRIPT" ]] || log_fail "drift script not found: $DRIFT_SCRIPT"
  local rc
  set +e
  rundrift --bogus-flag >/dev/null 2>&1; rc=$?
  set -e
  [[ "$rc" -eq 2 ]] || log_fail "unknown flag must exit 2 (got $rc)"
  set +e
  rundrift --pin >/dev/null 2>&1; rc=$?
  set -e
  [[ "$rc" -eq 2 ]] || log_fail "--pin without value must exit 2 (got $rc)"
  log_pass "TEST-001 usage/exit-2 contract"
}

# --- TEST-002 — equal pin, local tier -> up-to-date, exit 0 (Spec-AC-01) ------
test_equal_local() {
  log_info "TEST-002: pin == canonical HEAD (local tier) -> up-to-date, exit 0..."
  local pin="$TMP_ROOT/t002/AAI_PIN.md" out rc
  write_pin "$pin" "${CANON_SHAS[2]}" "$CANON"
  set +e
  out="$(rundrift --pin "$pin" 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "equal pin must exit 0 (got $rc): $out"
  echo "$out" | grep -qi "up-to-date" || log_fail "expected up-to-date line, got: $out"
  log_pass "TEST-002 up-to-date (local tier)"
}

# --- TEST-003 — pin 2 behind, local tier -> BEHIND by 2 + remedy (Spec-AC-02) -
test_behind_local() {
  log_info "TEST-003: pin 2 behind canonical (local tier) -> BEHIND by 2 + /aai-update, exit 3..."
  local pin="$TMP_ROOT/t003/AAI_PIN.md" out rc
  write_pin "$pin" "${CANON_SHAS[0]}" "$CANON"
  set +e
  out="$(rundrift --pin "$pin" 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 3 ]] || log_fail "behind pin must exit 3 (got $rc): $out"
  echo "$out" | grep -q "BEHIND" || log_fail "expected BEHIND line, got: $out"
  echo "$out" | grep -q "2 commit" || log_fail "expected distance '2 commit(s)', got: $out"
  echo "$out" | grep -q "/aai-update" || log_fail "expected /aai-update remedy, got: $out"
  log_pass "TEST-003 BEHIND by N with remedy (local tier)"
}

# --- TEST-004a/b — file:// ls-remote tier (Spec-AC-01/02) ---------------------
test_lsremote_tier() {
  log_info "TEST-004a: file:// remote, equal -> up-to-date, exit 0 (ls-remote tier)..."
  local pin="$TMP_ROOT/t004a/AAI_PIN.md" out rc
  write_pin "$pin" "${CANON_SHAS[2]}" "file://$CANON"
  set +e
  out="$(rundrift --pin "$pin" 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "equal pin via file:// must exit 0 (got $rc): $out"
  echo "$out" | grep -qi "up-to-date" || log_fail "expected up-to-date line, got: $out"
  log_pass "TEST-004a up-to-date (ls-remote tier)"

  log_info "TEST-004b: file:// remote, pin differs -> unknown distance + remedy, exit 3..."
  local pin2="$TMP_ROOT/t004b/AAI_PIN.md" out2 rc2
  write_pin "$pin2" "${CANON_SHAS[0]}" "file://$CANON"
  set +e
  out2="$(rundrift --pin "$pin2" 2>&1)"; rc2=$?
  set -e
  [[ "$rc2" -eq 3 ]] || log_fail "differing pin via file:// must exit 3 (got $rc2): $out2"
  echo "$out2" | grep -qi "unknown distance" || log_fail "expected 'unknown distance', got: $out2"
  echo "$out2" | grep -q "/aai-update" || log_fail "expected /aai-update remedy, got: $out2"
  log_pass "TEST-004b drift with unknown distance (ls-remote tier)"
}

# --- TEST-005 — unreachable remote -> unverifiable, exit 4 (Spec-AC-03) -------
test_offline() {
  log_info "TEST-005: file:// remote to nonexistent path -> unverifiable, exit 4..."
  local pin="$TMP_ROOT/t005/AAI_PIN.md" out rc
  write_pin "$pin" "${CANON_SHAS[2]}" "file://$TMP_ROOT/does-not-exist-anywhere"
  set +e
  out="$(rundrift --pin "$pin" 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 4 ]] || log_fail "unreachable remote must exit 4 (got $rc): $out"
  echo "$out" | grep -qi "unverifiable" || log_fail "expected unverifiable line, got: $out"
  log_pass "TEST-005 unverifiable when canonical unreachable"
}

# --- TEST-006 — missing pin -> unverifiable, exit 4 (Spec-AC-03) --------------
test_missing_pin() {
  log_info "TEST-006: missing pin file -> unverifiable, exit 4..."
  local out rc
  set +e
  out="$(rundrift --pin "$TMP_ROOT/nope/AAI_PIN.md" 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 4 ]] || log_fail "missing pin must exit 4 (got $rc): $out"
  echo "$out" | grep -qi "unverifiable" || log_fail "expected unverifiable line, got: $out"
  log_pass "TEST-006 unverifiable when pin missing"
}

# --- TEST-007 — placeholder pin -> unverifiable "not stamped" (Spec-AC-03) ----
test_placeholder_pin() {
  log_info "TEST-007: placeholder (template) pin -> unverifiable, exit 4..."
  local pin="$TMP_ROOT/t007/AAI_PIN.md" out rc
  mkdir -p "$TMP_ROOT/t007"
  cat > "$pin" <<'EOF'
# AAI Pin

- Source path: <set by sync script>
- Template version: <set by sync script>
- Template commit: <set by sync script>
- Synced at (UTC): <set by sync script>
EOF
  set +e
  out="$(rundrift --pin "$pin" 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 4 ]] || log_fail "placeholder pin must exit 4 (got $rc): $out"
  echo "$out" | grep -qi "unverifiable" || log_fail "expected unverifiable line, got: $out"
  echo "$out" | grep -qi "not stamped\|never synced\|template" || log_fail "expected not-stamped reason, got: $out"
  log_pass "TEST-007 unverifiable on placeholder pin"
}

# --- TEST-008 — D2 fallback: Source path used when Canonical repo absent ------
test_source_path_fallback() {
  log_info "TEST-008: pre-contract pin (no Canonical repo, reachable Source path) -> local tier..."
  local pin="$TMP_ROOT/t008/AAI_PIN.md" out rc
  write_pin "$pin" "${CANON_SHAS[0]}" "" "$CANON"
  set +e
  out="$(rundrift --pin "$pin" 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 3 ]] || log_fail "source-path fallback must compute drift, exit 3 (got $rc): $out"
  echo "$out" | grep -q "2 commit" || log_fail "source-path fallback must compute real distance, got: $out"
  log_pass "TEST-008 Source path fallback (backward-tolerant pin)"
}

# --- TEST-009 — --json contract across tiers (Spec-AC-01..03) -----------------
test_json_contract() {
  log_info "TEST-009: --json emits parseable objects with status/relation/distance/source..."
  local pin="$TMP_ROOT/t009/AAI_PIN.md" out
  # behind, local tier
  write_pin "$pin" "${CANON_SHAS[0]}" "$CANON"
  set +e
  out="$(rundrift --pin "$pin" --json 2>&1)"
  set -e
  echo "$out" | node -e '
    let d = "";
    process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => {
      const j = JSON.parse(d);
      const die = (m) => { console.error(m); process.exit(1); };
      if (j.status !== "behind") die("status: " + j.status);
      if (j.relation !== "behind") die("relation: " + j.relation);
      if (j.distance !== 2) die("distance: " + j.distance);
      if (j.source !== "pin_canonical_repo") die("source: " + j.source);
      if (!j.pin_commit || !j.canonical_head) die("missing shas");
    });
  ' || log_fail "behind/local --json contract violated: $out"
  # unverifiable (missing pin)
  set +e
  out="$(rundrift --pin "$TMP_ROOT/nope2/AAI_PIN.md" --json 2>&1)"
  set -e
  echo "$out" | node -e '
    let d = "";
    process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => {
      const j = JSON.parse(d);
      if (j.status !== "unverifiable") { console.error("status: " + j.status); process.exit(1); }
      if (j.source !== "none") { console.error("source: " + j.source); process.exit(1); }
    });
  ' || log_fail "unverifiable --json contract violated: $out"
  log_pass "TEST-009 --json contract"
}

# --- TEST-010 — real aai-sync.sh stamps Canonical repo (Spec-AC-05, seam) -----
test_sync_stamps_pin() {
  log_info "TEST-010: aai-sync.sh run from fixture source stamps '- Canonical repo:'..."
  [[ -f "$SYNC_SH" ]] || log_fail "aai-sync.sh not found: $SYNC_SH"
  local src="$TMP_ROOT/sync-src" dst="$TMP_ROOT/sync-dst"
  mkdir -p "$src/.aai/scripts" "$dst"
  cp "$SYNC_SH" "$src/.aai/scripts/aai-sync.sh"
  echo "marker" > "$src/.aai/AGENTS.md"
  git -C "$src" init -q -b main
  git -C "$src" config user.email "test@example.invalid"
  git -C "$src" config user.name "AAI Test"
  git -C "$src" remote add origin "https://example.invalid/goodwind-cz/aai.git"
  git -C "$src" add -A
  git -C "$src" commit -qm "fixture source"
  git -C "$dst" init -q -b main
  bash "$src/.aai/scripts/aai-sync.sh" "$dst" >/dev/null 2>&1 \
    || log_fail "fixture aai-sync.sh run failed"
  local pin="$dst/.aai/system/AAI_PIN.md"
  [[ -f "$pin" ]] || log_fail "sync did not write pin: $pin"
  grep -q "^- Canonical repo: https://example.invalid/goodwind-cz/aai.git$" "$pin" \
    || log_fail "pin lacks stamped Canonical repo line: $(cat "$pin")"
  grep -q "^- Template commit: $(git -C "$src" rev-parse HEAD)$" "$pin" \
    || log_fail "pin lacks template commit: $(cat "$pin")"
  # Seam crossing: the drift script must consume THIS synced pin end-to-end.
  local out rc
  set +e
  out="$(rundrift --pin "$pin" --remote "$src" 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "freshly synced pin must verify up-to-date (got $rc): $out"
  log_pass "TEST-010 sync stamps pin; drift script verifies the synced pin"
}

# --- TEST-010b — ps1 parity (Spec-AC-05) --------------------------------------
test_ps1_parity() {
  log_info "TEST-010b: aai-sync.ps1 stamps Canonical repo (static parity)..."
  [[ -f "$SYNC_PS1" ]] || log_fail "aai-sync.ps1 not found: $SYNC_PS1"
  grep -q "Canonical repo: " "$SYNC_PS1" \
    || log_fail "aai-sync.ps1 does not stamp '- Canonical repo:'"
  grep -q "canonical" "$UPDATE_SH" \
    || log_fail "aai-update.sh post-sync evidence grep does not surface the Canonical repo line"
  log_pass "TEST-010b ps1 stamp + update evidence parity"
}

# --- TEST-011 — SKILL_DOCTOR CAT-13 wiring (Spec-AC-06) -----------------------
test_doctor_wiring() {
  log_info "TEST-011: SKILL_DOCTOR.prompt.md wires CAT-13 vendored layer drift..."
  [[ -f "$DOCTOR_PROMPT" ]] || log_fail "doctor prompt not found: $DOCTOR_PROMPT"
  grep -q "\[CAT-13\]" "$DOCTOR_PROMPT" || log_fail "no [CAT-13] section in doctor prompt"
  grep -q "layer-drift.mjs" "$DOCTOR_PROMPT" || log_fail "CAT-13 does not invoke layer-drift.mjs"
  grep -q "/aai-update" "$DOCTOR_PROMPT" || log_fail "CAT-13 lacks the /aai-update remedy"
  # informational, never BROKEN (degrade-and-report)
  awk '/\[CAT-13\]/{f=1} f' "$DOCTOR_PROMPT" | grep -qi "informational" \
    || log_fail "CAT-13 must be documented informational (never BROKEN)"
  # OUTPUT FORMAT block must include the category line
  awk '/^OUTPUT FORMAT/{f=1} f' "$DOCTOR_PROMPT" | grep -q "CAT-13" \
    || log_fail "OUTPUT FORMAT block lacks the CAT-13 line"
  log_pass "TEST-011 doctor CAT-13 wiring"
}

# --- Spec-AC-04 self-check — no real network schemes in this suite ------------
test_no_real_network() {
  log_info "Self-check: suite uses no real-network URL schemes..."
  # Allowed: file:// URLs and the non-routable example.invalid remote string
  # (never contacted — it is only stamped into pins/fixture git config).
  if grep -nE "https?://" "${BASH_SOURCE[0]}" | grep -v "example.invalid" | grep -qv "^ *#"; then
    log_fail "suite references a routable http(s) URL"
  fi
  log_pass "Self-check: fixtures only (file:// + non-routable placeholders)"
}

test_space_in_path() {  # Review B1 regression
  log_info "TEST-014: CLI executes from a path containing a space (main-guard URL-decode bug)..."
  local d="$TMP_ROOT/space dir/.aai/scripts"
  mkdir -p "$d"
  cp "$PROJECT_ROOT/.aai/scripts/layer-drift.mjs" "$d/"
  local out rc
  set +e
  out="$(node "$TMP_ROOT/space dir/.aai/scripts/layer-drift.mjs" --pin "$TMP_ROOT/nope/AAI_PIN.md" 2>&1)"; rc=$?
  set -e
  # Pre-fix: percent-encoded pathname never matched argv -> main() skipped,
  # EMPTY output, exit 0 — doctor would read that as "up-to-date".
  [[ -n "$out" ]] || log_fail "CLI from a space-containing path must produce output (main-guard must fire)"
  [[ "$rc" -eq 4 ]] || log_fail "expected unverifiable exit 4 from space path (got $rc): $out"
  echo "$out" | grep -qi "unverifiable" || log_fail "expected unverifiable line, got: $out"
  log_pass "TEST-014 main-guard fires from a space-containing path (B1)"
}

main() {
  echo "=== AAI Skill Test: $TEST_NAME ==="
  check_deps
  build_canonical_fixture
  test_usage_errors
  test_equal_local
  test_behind_local
  test_lsremote_tier
  test_offline
  test_missing_pin
  test_placeholder_pin
  test_source_path_fallback
  test_json_contract
  test_sync_stamps_pin
  test_ps1_parity
  test_doctor_wiring
  test_no_real_network
  test_space_in_path
  echo "=== ALL TESTS PASSED: $TEST_NAME ==="
}

main "$@"
