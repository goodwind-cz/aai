#!/usr/bin/env bash
#
# Test: config-driven new-release notify + opt-in auto-sync
# (CHANGE auto-update-config / SPEC spec-auto-update-config)
#
# Verifies .aai/scripts/update-check.mjs (config resolution, drift detection via
# the REUSED layer-drift.mjs, notify/auto branches reusing aai-update.{sh,ps1}
# with its canonical guard, offline degrade, throttle cache) and the SessionStart
# hook wiring (best-effort, provably NON-BLOCKING). Implements TEST-001..TEST-013
# from the frozen spec.
#
# ZERO REAL NETWORK: the fake canonical repo is a local `git init` fixture; the
# offline tier is a file:// URL to a nonexistent path (mirrors
# tests/skills/test-aai-layer-drift.sh:80-97). Auto-sync tests use a LOCAL
# fixture source (real local sync, no network). The clock is injected via --now.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-update-check"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHECK_SCRIPT="$PROJECT_ROOT/.aai/scripts/update-check.mjs"
DRIFT_SCRIPT="$PROJECT_ROOT/.aai/scripts/layer-drift.mjs"
UPDATE_SH="$PROJECT_ROOT/.aai/scripts/aai-update.sh"
SYNC_SH="$PROJECT_ROOT/.aai/scripts/aai-sync.sh"
PROFILES="$PROJECT_ROOT/.aai/system/PROFILES.yaml"
HOOK_SH="$PROJECT_ROOT/hooks/session-start.sh"
HOOK_PS1="$PROJECT_ROOT/hooks/session-start.ps1"
HOOKS_JSON="$PROJECT_ROOT/hooks/hooks.json"

TMP_ROOT=""
CANON=""          # fixture canonical repo (git dir)
CANON_SHAS=()     # commit shas oldest..newest

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

# Run update-check; never aborts the suite on non-zero exit (callers inspect $?).
runcheck() {
  node "$CHECK_SCRIPT" "$@"
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

# Write an update-config.yaml. Args: <path> [mode] [throttle_hours]
write_config() {
  local cfg_path="$1" mode="${2:-}" throttle="${3:-}"
  mkdir -p "$(dirname "$cfg_path")"
  {
    [[ -n "$mode" ]] && echo "mode: $mode"
    [[ -n "$throttle" ]] && echo "throttle_hours: $throttle"
    echo "# comment line ignored"
  } > "$cfg_path"
}

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  [[ -f "$CHECK_SCRIPT" ]] || log_fail "update-check script not found: $CHECK_SCRIPT"
  TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aai-update-check-test.XXXXXX")"
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

# Build a LOCAL fixture SOURCE that aai-update can sync from (no network): a git
# repo carrying a real aai-sync.sh plus a distinctive marker file under .aai.
# Args: <dir> [origin_url]
build_sync_source() {
  local src="$1" origin="${2:-https://example.invalid/goodwind-cz/aai.git}"
  mkdir -p "$src/.aai/scripts"
  cp "$SYNC_SH" "$src/.aai/scripts/aai-sync.sh"
  echo "marker-from-source" > "$src/.aai/AGENTS.md"
  echo "SYNCED_MARKER_$(date +%s)" > "$src/.aai/system-marker.txt"
  git -C "$src" init -q -b main
  git -C "$src" config user.email "test@example.invalid"
  git -C "$src" config user.name "AAI Test"
  git -C "$src" remote add origin "$origin"
  git -C "$src" add -A
  git -C "$src" commit -qm "fixture sync source"
}

# Build a LOCAL fixture SOURCE whose aai-sync.sh is a SLOW STUB: it records each
# invocation, sleeps, then materializes the marker. Used to prove the detached
# model (hook returns before the sync finishes) and the concurrent-sync guard.
# Args: <dir> [sleep_seconds] [origin_url]
build_slow_sync_source() {
  local src="$1" sleep_s="${2:-4}" origin="${3:-https://example.invalid/goodwind-cz/aai.git}"
  mkdir -p "$src/.aai/scripts"
  cat > "$src/.aai/scripts/aai-sync.sh" <<STUB
#!/usr/bin/env bash
# slow stub sync: record invocation, sleep, then materialize the marker.
target="\$1"
mkdir -p "\$target/.aai/system"
printf 'invoked\n' >> "\$target/.aai/sync-invocations"
sleep $sleep_s
printf 'SYNCED_STUB\n' > "\$target/.aai/system-marker.txt"
echo "stub sync applied"
STUB
  chmod +x "$src/.aai/scripts/aai-sync.sh"
  git -C "$src" init -q -b main
  git -C "$src" config user.email "test@example.invalid"
  git -C "$src" config user.name "AAI Test"
  git -C "$src" remote add origin "$origin"
  git -C "$src" add -A
  git -C "$src" commit -qm "slow stub sync source"
}

# Poll until <file> contains <pattern> (grep -q) or timeout (default 20s). The
# detached-sync model means outcomes land asynchronously; tests must wait, never
# assume synchronous completion.
wait_for_grep() {
  local f="$1" pat="$2" timeout="${3:-20}" i=0
  while [[ $i -lt $((timeout * 2)) ]]; do
    [[ -f "$f" ]] && grep -q "$pat" "$f" && return 0
    sleep 0.5; i=$((i + 1))
  done
  return 1
}

# --- TEST-001 — notify + pin behind THEN newer-release line, no repo mutation --
test_notify_behind() {
  log_info "TEST-001: notify mode + pin behind local canonical -> newer-release line, no repo mutation..."
  local dir="$TMP_ROOT/t001" pin cfg out rc
  mkdir -p "$dir/.aai/system" "$dir/docs/ai"
  git -C "$dir" init -q -b main
  pin="$dir/.aai/system/AAI_PIN.md"
  cfg="$dir/docs/ai/update-config.yaml"
  write_pin "$pin" "${CANON_SHAS[0]}" "$CANON"
  write_config "$cfg" notify
  echo "keep-me" > "$dir/sentinel.txt"
  local before after
  before="$(cd "$dir" && git status --porcelain 2>/dev/null; ls -1 "$dir")"
  set +e
  out="$(cd "$dir" && runcheck --pin "$pin" --config "$cfg" --remote "$CANON" --force 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "notify+behind must exit 0 (got $rc): $out"
  echo "$out" | grep -qi "newer AAI release" || log_fail "expected 'newer AAI release' line, got: $out"
  after="$(cd "$dir" && git status --porcelain 2>/dev/null; ls -1 "$dir")"
  [[ "$before" == "$after" ]] || log_fail "notify mode mutated repo files:"$'\n'"before=[$before]"$'\n'"after=[$after]"
  [[ "$(cat "$dir/sentinel.txt")" == "keep-me" ]] || log_fail "notify mode altered a repo file"
  log_pass "TEST-001 notify surfaces newer-release line, mutates nothing"
}

# --- TEST-002 — notify + pin equal THEN quiet, no notify, exit 0 --------------
test_notify_equal() {
  log_info "TEST-002: notify mode + pin equal canonical -> quiet, no notify line, exit 0..."
  local dir="$TMP_ROOT/t002" pin cfg out rc
  mkdir -p "$dir/.aai/system"
  pin="$dir/.aai/system/AAI_PIN.md"
  cfg="$dir/update-config.yaml"
  write_pin "$pin" "${CANON_SHAS[2]}" "$CANON"
  write_config "$cfg" notify
  set +e
  out="$(cd "$dir" && runcheck --pin "$pin" --config "$cfg" --remote "$CANON" --force 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "notify+equal must exit 0 (got $rc): $out"
  echo "$out" | grep -qi "newer AAI release" && log_fail "up-to-date must NOT print a notify line, got: $out"
  log_pass "TEST-002 up-to-date is quiet"
}

# --- TEST-003 — auto + pin behind THEN aai-update sync invoked DETACHED --------
test_auto_sync() {
  log_info "TEST-003: auto mode + pin behind local source -> aai-update sync invoked DETACHED (outcome eventually applied), exit 0..."
  local dir="$TMP_ROOT/t003" src="$TMP_ROOT/t003-src" pin cfg outcome out rc
  build_sync_source "$src"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email "test@example.invalid"
  git -C "$dir" config user.name "AAI Test"
  # NON-canonical origin so the aai-update guard does NOT refuse (want a sync).
  git -C "$dir" remote add origin "https://example.invalid/some-owner/target.git"
  mkdir -p "$dir/.aai/system"
  pin="$dir/.aai/system/AAI_PIN.md"
  cfg="$dir/docs/ai/update-config.yaml"
  outcome="$dir/.aai/cache/update-sync-outcome.json"
  write_pin "$pin" "${CANON_SHAS[0]}" "$CANON"
  write_config "$cfg" auto
  [[ -f "$dir/.aai/system-marker.txt" ]] && log_fail "marker present before sync (bad fixture)"
  set +e
  out="$(cd "$dir" && runcheck --pin "$pin" --config "$cfg" --remote "$CANON" --source "$src" --outcome "$outcome" --force 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "auto+behind must exit 0 (got $rc): $out"
  # DETACHED model: the run returns without blocking; the sync completes in the
  # background and its outcome lands in the persistent outcome log.
  echo "$out" | grep -qi "background" || log_fail "auto+behind must report a detached/background sync, got: $out"
  wait_for_grep "$outcome" '"result":"applied"' 20 || log_fail "detached sync outcome not applied within timeout: $(cat "$outcome" 2>/dev/null)"
  [[ -f "$dir/.aai/system-marker.txt" ]] || log_fail "detached sync did not materialize the synced marker: $(cat "$outcome" 2>/dev/null)"
  log_pass "TEST-003 auto invokes aai-update sync DETACHED (outcome eventually applied)"
}

# --- TEST-004 — auto + canonical repo THEN aai-update refuses (detached) -------
test_auto_canonical_refuse() {
  log_info "TEST-004: auto mode + project origin == source slug -> aai-update refuses (detached), refused outcome, surfaced next run, no mutation..."
  local dir="$TMP_ROOT/t004" pin cfg outcome out rc
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email "test@example.invalid"
  git -C "$dir" config user.name "AAI Test"
  # Origin equals the update source SLUG -> canonical-repo guard must refuse.
  git -C "$dir" remote add origin "https://github.com/goodwind-cz/aai.git"
  mkdir -p "$dir/.aai/system"
  pin="$dir/.aai/system/AAI_PIN.md"
  cfg="$dir/update-config.yaml"
  outcome="$dir/.aai/cache/update-sync-outcome.json"
  write_pin "$pin" "${CANON_SHAS[0]}" "$CANON"
  write_config "$cfg" auto
  set +e
  out="$(cd "$dir" && runcheck --pin "$pin" --config "$cfg" --remote "$CANON" --source "goodwind-cz/aai" --outcome "$outcome" --force 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "auto+canonical must still exit 0 (got $rc): $out"
  # The detached sync reuses the aai-update origin-slug guard -> records refused.
  wait_for_grep "$outcome" '"result":"refused"' 20 || log_fail "canonical guard must record a refused outcome: $(cat "$outcome" 2>/dev/null)"
  [[ ! -f "$dir/.aai/system-marker.txt" ]] || log_fail "canonical repo was mutated (sync should have refused)"
  # report-next-session: a subsequent run surfaces the refused note.
  set +e
  out="$(cd "$dir" && runcheck --pin "$pin" --config "$cfg" --remote "$CANON" --source "goodwind-cz/aai" --outcome "$outcome" --force 2>&1)"; rc=$?
  set -e
  echo "$out" | grep -qi "refused" || log_fail "refused outcome must surface on the next run, got: $out"
  log_pass "TEST-004 auto refuses on canonical repo (detached), refused outcome surfaced, no mutation"
}

# --- TEST-005 — notify + unreachable source THEN could-not-check, exit 0 -------
test_notify_unverifiable() {
  log_info "TEST-005: notify mode + unreachable source -> could-not-check note, exit 0, no sync..."
  local dir="$TMP_ROOT/t005" pin cfg out rc
  mkdir -p "$dir/.aai/system"
  pin="$dir/.aai/system/AAI_PIN.md"
  cfg="$dir/update-config.yaml"
  write_pin "$pin" "${CANON_SHAS[2]}" "file://$TMP_ROOT/does-not-exist-anywhere"
  write_config "$cfg" notify
  set +e
  out="$(cd "$dir" && runcheck --pin "$pin" --config "$cfg" --remote "file://$TMP_ROOT/does-not-exist-anywhere" --force 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "notify+unverifiable must exit 0 (got $rc): $out"
  echo "$out" | grep -qi "could not check" || log_fail "expected 'could not check' note, got: $out"
  echo "$out" | grep -qi "newer AAI release" && log_fail "unverifiable must NOT claim a newer release, got: $out"
  log_pass "TEST-005 unverifiable degrades to could-not-check (notify)"
}

# --- TEST-006 — auto + unreachable source THEN no aai-update invoked, exit 0 ---
test_auto_unverifiable_no_sync() {
  log_info "TEST-006: auto mode + unreachable source -> could-not-check note, NO aai-update invoked, exit 0..."
  local dir="$TMP_ROOT/t006" src="$TMP_ROOT/t006-src" pin cfg out rc
  build_sync_source "$src"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email "test@example.invalid"
  git -C "$dir" config user.name "AAI Test"
  git -C "$dir" remote add origin "https://example.invalid/some-owner/target.git"
  mkdir -p "$dir/.aai/system"
  pin="$dir/.aai/system/AAI_PIN.md"
  cfg="$dir/update-config.yaml"
  write_pin "$pin" "${CANON_SHAS[2]}" "file://$TMP_ROOT/does-not-exist-anywhere"
  write_config "$cfg" auto
  set +e
  out="$(cd "$dir" && runcheck --pin "$pin" --config "$cfg" --remote "file://$TMP_ROOT/does-not-exist-anywhere" --source "$src" --force 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "auto+unverifiable must exit 0 (got $rc): $out"
  echo "$out" | grep -qi "could not check" || log_fail "expected 'could not check' note, got: $out"
  [[ ! -f "$dir/.aai/system-marker.txt" ]] || log_fail "auto synced despite unverifiable verdict (must never sync unless behind)"
  log_pass "TEST-006 auto never syncs on unverifiable"
}

# --- TEST-007 — config absent THEN notify default (line, no sync) -------------
test_config_absent_default_notify() {
  log_info "TEST-007: config file absent + pin behind -> behaves as notify default (line printed, no sync)..."
  local dir="$TMP_ROOT/t007" pin out rc
  mkdir -p "$dir/.aai/system"
  git -C "$dir" init -q -b main
  git -C "$dir" remote add origin "https://example.invalid/some-owner/target.git"
  pin="$dir/.aai/system/AAI_PIN.md"
  write_pin "$pin" "${CANON_SHAS[0]}" "$CANON"
  local cfg="$dir/docs/ai/update-config.yaml"
  [[ ! -f "$cfg" ]] || log_fail "config unexpectedly present (bad fixture)"
  set +e
  out="$(cd "$dir" && runcheck --pin "$pin" --config "$cfg" --remote "$CANON" --force 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "absent config must exit 0 (got $rc): $out"
  echo "$out" | grep -qi "newer AAI release" || log_fail "absent config must default to notify line, got: $out"
  [[ ! -f "$dir/.aai/system-marker.txt" ]] || log_fail "absent config must NOT auto-sync"
  log_pass "TEST-007 absent config == notify default"
}

# --- TEST-008 — unknown mode THEN stderr error, notify fallback, NO auto-sync --
test_unknown_mode_fallback() {
  log_info "TEST-008: mode unknown value + pin behind -> stderr error, notify fallback, NO auto-sync..."
  local dir="$TMP_ROOT/t008" src="$TMP_ROOT/t008-src" pin cfg outerr rc
  build_sync_source "$src"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" remote add origin "https://example.invalid/some-owner/target.git"
  mkdir -p "$dir/.aai/system"
  pin="$dir/.aai/system/AAI_PIN.md"
  cfg="$dir/update-config.yaml"
  write_pin "$pin" "${CANON_SHAS[0]}" "$CANON"
  write_config "$cfg" "autoo"   # typo of "auto"
  local err
  set +e
  err="$(cd "$dir" && runcheck --pin "$pin" --config "$cfg" --remote "$CANON" --source "$src" --force 2>"$TMP_ROOT/t008.err")"; rc=$?
  set -e
  err="$(cat "$TMP_ROOT/t008.err")"
  [[ "$rc" -eq 0 ]] || log_fail "unknown mode must still exit 0 (got $rc)"
  echo "$err" | grep -qi "mode" || log_fail "unknown mode must emit a clear stderr error naming 'mode', got stderr: $err"
  [[ ! -f "$dir/.aai/system-marker.txt" ]] || log_fail "unknown mode auto-synced (must fall back to notify, never auto)"
  # fell back to notify -> the behind line still surfaces on stdout
  local out
  set +e
  out="$(cd "$dir" && runcheck --pin "$pin" --config "$cfg" --remote "$CANON" --source "$src" --force 2>/dev/null)"
  set -e
  echo "$out" | grep -qi "newer AAI release" || log_fail "unknown mode must fall back to a notify line, got: $out"
  log_pass "TEST-008 unknown mode -> stderr error + notify fallback (never auto)"
}

# --- TEST-009 — throttle within window THEN probe skipped, no notify ----------
test_throttle_skip() {
  log_info "TEST-009: cache timestamp within window -> probe skipped, no notify, exit 0 (no drift call)..."
  local dir="$TMP_ROOT/t009" pin cfg cache out rc
  mkdir -p "$dir/.aai/system" "$dir/.aai/cache"
  pin="$dir/.aai/system/AAI_PIN.md"
  cfg="$dir/update-config.yaml"
  cache="$dir/.aai/cache/update-check.json"
  write_pin "$pin" "${CANON_SHAS[0]}" "$CANON"   # behind: would notify if probed
  write_config "$cfg" notify 24
  # Last check 1 hour before the injected clock -> inside the 24h window.
  printf '{"last_check_utc":"2026-07-20T10:00:00Z"}' > "$cache"
  set +e
  out="$(cd "$dir" && runcheck --pin "$pin" --config "$cfg" --remote "$CANON" --cache "$cache" --now "2026-07-20T11:00:00Z" 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "throttled run must exit 0 (got $rc): $out"
  echo "$out" | grep -qi "newer AAI release" && log_fail "throttled run must NOT probe/notify, got: $out"
  [[ -z "$(echo "$out" | tr -d '[:space:]')" ]] || log_fail "throttled run must be silent (fast path), got: $out"
  log_pass "TEST-009 throttle skips probe within window"
}

# --- TEST-010 — outside window OR --force THEN probe runs, notify produced -----
test_throttle_probe() {
  log_info "TEST-010: cache outside window OR --force -> probe runs, notify decision produced..."
  local dir="$TMP_ROOT/t010" pin cfg cache out rc
  mkdir -p "$dir/.aai/system" "$dir/.aai/cache"
  pin="$dir/.aai/system/AAI_PIN.md"
  cfg="$dir/update-config.yaml"
  cache="$dir/.aai/cache/update-check.json"
  write_pin "$pin" "${CANON_SHAS[0]}" "$CANON"
  write_config "$cfg" notify 24
  # (a) OUTSIDE the window: last check 48h before the injected clock.
  printf '{"last_check_utc":"2026-07-18T11:00:00Z"}' > "$cache"
  set +e
  out="$(cd "$dir" && runcheck --pin "$pin" --config "$cfg" --remote "$CANON" --cache "$cache" --now "2026-07-20T11:00:00Z" 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "outside-window run must exit 0 (got $rc): $out"
  echo "$out" | grep -qi "newer AAI release" || log_fail "outside-window run must probe and notify, got: $out"
  # cache refreshed to the injected clock after a probe.
  grep -q "2026-07-20T11:00:00Z" "$cache" || log_fail "successful probe must refresh the throttle cache, cache: $(cat "$cache")"
  # (b) INSIDE the window but --force overrides the throttle.
  printf '{"last_check_utc":"2026-07-20T10:30:00Z"}' > "$cache"
  set +e
  out="$(cd "$dir" && runcheck --pin "$pin" --config "$cfg" --remote "$CANON" --cache "$cache" --now "2026-07-20T11:00:00Z" --force 2>&1)"; rc=$?
  set -e
  echo "$out" | grep -qi "newer AAI release" || log_fail "--force must probe despite a fresh cache, got: $out"
  log_pass "TEST-010 probe runs outside window and on --force; cache refreshed"
}

# --- TEST-011 — SessionStart hook stays NON-BLOCKING when the check fails/hangs -
test_hook_non_blocking() {
  log_info "TEST-011: hooks/session-start.sh with update-check forced to FAIL/HANG -> hook exits 0 and still emits meta content..."
  [[ -f "$HOOK_SH" ]] || log_fail "hook not found: $HOOK_SH"
  local fx="$TMP_ROOT/t011"
  mkdir -p "$fx/hooks" "$fx/.aai/scripts"
  cp "$HOOK_SH" "$fx/hooks/session-start.sh"
  printf 'META_SKILL_SENTINEL_CONTENT\n' > "$fx/.aai/SKILL_META.prompt.md"
  local marker="$fx/.aai/scripts/invoked.marker"

  # (a) FAIL: the check WRITES A MARKER (proving the hook actually invoked it),
  # then exits non-zero and prints garbage to stderr. The marker assertion is
  # what makes this a real RED: a hook that never calls update-check would
  # trivially exit 0 + emit meta, so without the marker the test would pass
  # against an UNWIRED hook (all-happy-path trap, SPEC-0013 H7).
  cat > "$fx/.aai/scripts/update-check.mjs" <<STUB
import fs from 'node:fs';
fs.writeFileSync('$marker', 'x');
console.error("update-check: simulated failure");
process.exit(1);
STUB
  rm -f "$marker"
  local out rc
  set +e
  out="$(bash "$fx/hooks/session-start.sh" 2>/dev/null)"; rc=$?
  set -e
  [[ -f "$marker" ]] || log_fail "hook did NOT invoke update-check.mjs (marker absent -> not wired)"
  [[ "$rc" -eq 0 ]] || log_fail "hook must exit 0 when the check FAILS (got $rc)"
  echo "$out" | grep -qF "META_SKILL_SENTINEL_CONTENT" \
    || log_fail "hook must still emit meta-skill content when the check fails, got: $out"

  # (b) HANG: the check writes the marker, then never exits — the hook's own
  # watchdog must bound it, still exit 0, and still emit meta.
  cat > "$fx/.aai/scripts/update-check.mjs" <<STUB
import fs from 'node:fs';
fs.writeFileSync('$marker', 'x');
setInterval(() => {}, 1000);  // hang forever
STUB
  rm -f "$marker"
  local start end elapsed
  start="$(date +%s)"
  set +e
  out="$(AAI_UPDATE_CHECK_TIMEOUT_S=2 bash "$fx/hooks/session-start.sh" 2>/dev/null)"; rc=$?
  set -e
  end="$(date +%s)"
  elapsed=$((end - start))
  [[ -f "$marker" ]] || log_fail "hook did NOT invoke update-check.mjs in the hang case (marker absent)"
  [[ "$rc" -eq 0 ]] || log_fail "hook must exit 0 when the check HANGS (got $rc)"
  echo "$out" | grep -qF "META_SKILL_SENTINEL_CONTENT" \
    || log_fail "hook must still emit meta-skill content when the check hangs, got: $out"
  [[ "$elapsed" -lt 20 ]] || log_fail "hook watchdog did not bound a hanging check (took ${elapsed}s)"
  log_pass "TEST-011 SessionStart hook is provably non-blocking (fail + hang, both exit 0 + emit, invocation proven)"
}

# --- TEST-012 — static parity: hooks wire SessionStart + invoke update-check ---
test_hook_wiring_parity() {
  log_info "TEST-012: hooks.json wires SessionStart AND both session-start.{sh,ps1} invoke update-check.mjs guarded..."
  [[ -f "$HOOKS_JSON" ]] || log_fail "hooks.json not found: $HOOKS_JSON"
  [[ -f "$HOOK_SH" ]] || log_fail "session-start.sh not found"
  [[ -f "$HOOK_PS1" ]] || log_fail "session-start.ps1 not found"
  grep -qF "SessionStart" "$HOOKS_JSON" || log_fail "hooks.json must wire SessionStart"
  grep -qF "update-check.mjs" "$HOOK_SH" || log_fail "session-start.sh must invoke update-check.mjs"
  grep -qF "update-check.mjs" "$HOOK_PS1" || log_fail "session-start.ps1 must invoke update-check.mjs"
  # Guarded / non-blocking markers (swallow errors; still emit meta).
  grep -qF "SKILL_META" "$HOOK_SH" || log_fail "session-start.sh must still emit SKILL_META"
  grep -qF "SKILL_META" "$HOOK_PS1" || log_fail "session-start.ps1 must still emit SKILL_META"
  grep -qE "2>/dev/null|\|\| true" "$HOOK_SH" || log_fail "session-start.sh update-check must be error-guarded"
  grep -qE "try|WaitForExit|SilentlyContinue" "$HOOK_PS1" || log_fail "session-start.ps1 update-check must be error/timeout-guarded"
  log_pass "TEST-012 hooks wire SessionStart + invoke update-check guarded (sh + ps1)"
}

# --- TEST-013 — update-check.mjs classified in PROFILES core -------------------
test_profiles_classification() {
  log_info "TEST-013: .aai/scripts/update-check.mjs is listed in PROFILES.yaml core list..."
  [[ -f "$PROFILES" ]] || log_fail "PROFILES.yaml not found: $PROFILES"
  # column-0 'core:' block, 2-space list items (same discipline as the sync parser).
  local in_core
  in_core="$(awk '
    $0 == "core:" { f = 1; next }
    /^[^ ]/       { f = 0 }
    f && sub(/^  - /, "") { sub(/[ \t\r]+$/, ""); print }
  ' "$PROFILES" | grep -Fx ".aai/scripts/update-check.mjs" || true)"
  [[ -n "$in_core" ]] || log_fail ".aai/scripts/update-check.mjs is NOT in the PROFILES.yaml core list"
  log_pass "TEST-013 update-check.mjs classified as core"
}

# --- TEST-014 — REAL hook launches auto-sync DETACHED (fast exit, non-blocking) -
test_hook_detached_auto_sync() {
  log_info "TEST-014: REAL session-start.sh, auto mode + behind -> hook exits 0 FAST (well under the sync), sync launched DETACHED, outcome eventually written..."
  [[ -f "$HOOK_SH" ]] || log_fail "hook not found: $HOOK_SH"
  local fx="$TMP_ROOT/t014"
  mkdir -p "$fx/hooks" "$fx/.aai/scripts" "$fx/.aai/system" "$fx/docs/ai"
  cp "$HOOK_SH" "$fx/hooks/session-start.sh"
  cp "$CHECK_SCRIPT" "$fx/.aai/scripts/update-check.mjs"   # REAL update-check
  cp "$DRIFT_SCRIPT" "$fx/.aai/scripts/layer-drift.mjs"    # REAL detection
  printf 'META_SKILL_SENTINEL_CONTENT\n' > "$fx/.aai/SKILL_META.prompt.md"
  # SLOW STUB aai-update: proves the hook returns BEFORE the sync completes.
  cat > "$fx/.aai/scripts/aai-update.sh" <<'STUB'
#!/usr/bin/env bash
sleep 4
mkdir -p "$(pwd)/.aai/system"
printf 'STUB_SYNCED\n' > "$(pwd)/.aai/system-marker.txt"
echo "stub sync applied"
exit 0
STUB
  chmod +x "$fx/.aai/scripts/aai-update.sh"
  write_pin "$fx/.aai/system/AAI_PIN.md" "${CANON_SHAS[0]}" "$CANON"   # behind
  write_config "$fx/docs/ai/update-config.yaml" auto
  local marker="$fx/.aai/system-marker.txt"
  local outcome="$fx/.aai/cache/update-sync-outcome.json"
  local start end elapsed out rc
  start="$(date +%s)"
  set +e
  out="$(bash "$fx/hooks/session-start.sh" 2>/dev/null)"; rc=$?
  set -e
  end="$(date +%s)"; elapsed=$((end - start))
  [[ "$rc" -eq 0 ]] || log_fail "hook must exit 0 on the auto path (got $rc)"
  echo "$out" | grep -qF "META_SKILL_SENTINEL_CONTENT" \
    || log_fail "hook must still emit meta-skill content on the auto path, got: $out"
  [[ "$elapsed" -lt 4 ]] || log_fail "hook must return BEFORE the 4s sync completes (took ${elapsed}s) -> not detached/non-blocking"
  [[ ! -f "$marker" ]] || log_fail "sync marker present immediately after the hook -> sync ran synchronously, not detached"
  wait_for_grep "$outcome" '"result":"applied"' 20 || log_fail "detached sync outcome not written within timeout: $(cat "$outcome" 2>/dev/null)"
  [[ -f "$marker" ]] || log_fail "detached sync did not eventually materialize the marker"
  log_pass "TEST-014 SessionStart hook launches auto-sync DETACHED (fast exit, outcome eventually written)"
}

# --- TEST-015 — report-next-session: completed outcome surfaced ONCE ------------
test_report_next_session() {
  log_info "TEST-015: a completed-but-unreported sync outcome is surfaced ONCE on a subsequent run, then marked reported..."
  local dir="$TMP_ROOT/t015" pin cfg outcome out rc
  mkdir -p "$dir/.aai/system" "$dir/.aai/cache"
  pin="$dir/.aai/system/AAI_PIN.md"
  cfg="$dir/update-config.yaml"
  outcome="$dir/.aai/cache/update-sync-outcome.json"
  write_pin "$pin" "${CANON_SHAS[2]}" "$CANON"   # pin EQUAL -> up-to-date, no new sync
  write_config "$cfg" notify
  printf '{"started_utc":"2026-07-20T09:00:00Z","finished_utc":"2026-07-20T09:00:30Z","target_version":"abc1234","result":"applied","detail":"synced","reported":false}\n' > "$outcome"
  set +e
  out="$(cd "$dir" && runcheck --pin "$pin" --config "$cfg" --remote "$CANON" --outcome "$outcome" --force 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "surfacing run must exit 0 (got $rc): $out"
  echo "$out" | grep -qi "auto-update applied" || log_fail "a completed outcome must be surfaced, got: $out"
  echo "$out" | grep -qi "review the diff" || log_fail "an applied outcome must advise reviewing the diff, got: $out"
  grep -q '"reported":true' "$outcome" || log_fail "surfaced outcome must be marked reported, cache: $(cat "$outcome")"
  # second run: outcome already reported -> not surfaced again (shows once).
  set +e
  out="$(cd "$dir" && runcheck --pin "$pin" --config "$cfg" --remote "$CANON" --outcome "$outcome" --force 2>&1)"; rc=$?
  set -e
  echo "$out" | grep -qi "auto-update applied" && log_fail "a reported outcome must NOT surface again, got: $out"
  log_pass "TEST-015 completed detached outcome surfaced once, then marked reported"
}

# --- TEST-016 — concurrent-sync guard: no duplicate while a sync is in-flight ---
test_concurrent_sync_guard() {
  log_info "TEST-016: a second run while a detached sync is in-flight does NOT launch a duplicate sync..."
  local dir="$TMP_ROOT/t016" src="$TMP_ROOT/t016-src" pin cfg outcome out rc n
  build_slow_sync_source "$src" 4
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email "test@example.invalid"
  git -C "$dir" config user.name "AAI Test"
  git -C "$dir" remote add origin "https://example.invalid/some-owner/target.git"
  mkdir -p "$dir/.aai/system"
  pin="$dir/.aai/system/AAI_PIN.md"
  cfg="$dir/docs/ai/update-config.yaml"
  outcome="$dir/.aai/cache/update-sync-outcome.json"
  write_pin "$pin" "${CANON_SHAS[0]}" "$CANON"
  write_config "$cfg" auto
  # Run 1: launches the (slow) detached sync.
  set +e
  out="$(cd "$dir" && runcheck --pin "$pin" --config "$cfg" --remote "$CANON" --source "$src" --outcome "$outcome" --force 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "run1 must exit 0 (got $rc): $out"
  # Run 2 (immediately, sync still in-flight): must NOT spawn a duplicate.
  set +e
  out="$(cd "$dir" && runcheck --pin "$pin" --config "$cfg" --remote "$CANON" --source "$src" --outcome "$outcome" --force 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "run2 must exit 0 (got $rc): $out"
  echo "$out" | grep -qi "in progress" || log_fail "run2 must report an in-flight sync (concurrent guard), got: $out"
  # wait for the single sync to finish, then assert EXACTLY ONE invocation.
  wait_for_grep "$outcome" '"result":"applied"' 20 || log_fail "detached sync outcome not applied: $(cat "$outcome" 2>/dev/null)"
  n="$(wc -l < "$dir/.aai/sync-invocations" 2>/dev/null | tr -d ' ')"
  [[ "$n" == "1" ]] || log_fail "concurrent guard failed: expected 1 sync invocation, got $n"
  log_pass "TEST-016 concurrent-sync guard prevents a duplicate in-flight sync"
}

# --- TEST-017 — future-dated throttle cache forces a probe (self-heals) --------
test_future_dated_cache_probes() {
  log_info "TEST-017: a future-dated throttle cache is treated as never-checked -> probe RUNS (self-heals, never throttled forever)..."
  local dir="$TMP_ROOT/t017" pin cfg cache out rc j
  mkdir -p "$dir/.aai/system" "$dir/.aai/cache"
  pin="$dir/.aai/system/AAI_PIN.md"
  cfg="$dir/update-config.yaml"
  cache="$dir/.aai/cache/update-check.json"
  write_pin "$pin" "${CANON_SHAS[0]}" "$CANON"   # behind -> would notify if probed
  write_config "$cfg" notify 24
  # Future-dated cache + a clock in the PAST: naive (now-last)<window throttles forever.
  printf '{"last_check_utc":"2099-01-01T00:00:00Z"}' > "$cache"
  set +e
  out="$(cd "$dir" && runcheck --pin "$pin" --config "$cfg" --remote "$CANON" --cache "$cache" --now "2026-07-20T11:00:00Z" 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "future-dated cache run must exit 0 (got $rc): $out"
  echo "$out" | grep -qi "newer AAI release" \
    || log_fail "future-dated cache must force a probe (not throttle forever), got: $out"
  # confirm via --json that throttled:false (empirical repro of the review finding).
  printf '{"last_check_utc":"2099-01-01T00:00:00Z"}' > "$cache"
  set +e
  j="$(cd "$dir" && runcheck --pin "$pin" --config "$cfg" --remote "$CANON" --cache "$cache" --now "2026-07-20T11:00:00Z" --json 2>/dev/null)"; rc=$?
  set -e
  echo "$j" | grep -q '"throttled":false' || log_fail "future-dated cache must yield throttled:false, got: $j"
  log_pass "TEST-017 future-dated throttle cache forces a probe (self-heals)"
}

main() {
  echo "=== AAI Skill Test: $TEST_NAME ==="
  check_deps
  build_canonical_fixture
  test_notify_behind
  test_notify_equal
  test_auto_sync
  test_auto_canonical_refuse
  test_notify_unverifiable
  test_auto_unverifiable_no_sync
  test_config_absent_default_notify
  test_unknown_mode_fallback
  test_throttle_skip
  test_throttle_probe
  test_hook_non_blocking
  test_hook_wiring_parity
  test_profiles_classification
  test_hook_detached_auto_sync
  test_report_next_session
  test_concurrent_sync_guard
  test_future_dated_cache_probes
  echo "=== ALL TESTS PASSED: $TEST_NAME ==="
}

main "$@"
