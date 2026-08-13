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
  git -C "$dir" config user.email "test@example.invalid"
  git -C "$dir" config user.name "AAI Test"
  pin="$dir/.aai/system/AAI_PIN.md"
  cfg="$dir/docs/ai/update-config.yaml"
  write_pin "$pin" "${CANON_SHAS[0]}" "$CANON"
  write_config "$cfg" notify
  echo "keep-me" > "$dir/sentinel.txt"
  # Finding 4: commit a CLEAN baseline AND gitignore the only permitted write
  # (.aai/cache/), so porcelain is EMPTY at rest and any UNEXPECTED mutation (a
  # write OUTSIDE .aai/cache/) shows up. The old uncommitted fixture collapsed
  # every write under one untracked '?? .aai/' porcelain line, so a stray write
  # under .aai/ would not have changed the output — a weak no-mutation check.
  printf '.aai/cache/\n' > "$dir/.gitignore"
  git -C "$dir" add -A
  git -C "$dir" commit -qm "clean baseline"
  local before after
  before="$(cd "$dir" && git status --porcelain)"
  [[ -z "$before" ]] || log_fail "baseline not clean (bad fixture): [$before]"
  set +e
  out="$(cd "$dir" && runcheck --pin "$pin" --config "$cfg" --remote "$CANON" --force 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "notify+behind must exit 0 (got $rc): $out"
  echo "$out" | grep -qi "newer AAI release" || log_fail "expected 'newer AAI release' line, got: $out"
  after="$(cd "$dir" && git status --porcelain)"
  [[ -z "$after" ]] || log_fail "notify mode mutated repo files (porcelain not empty): [$after]"
  [[ "$(cat "$dir/sentinel.txt")" == "keep-me" ]] || log_fail "notify mode altered a repo file"
  log_pass "TEST-001 notify surfaces newer-release line, mutates nothing (clean-baseline porcelain)"
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

# --- TEST-018 — source agreement: sync source derived from the drift verdict ----
test_source_agreement() {
  log_info "TEST-018: auto mode + pin naming an ALTERNATE canonical source -> aai-update invoked with that SAME --source (detection and sync agree)..."
  local dir="$TMP_ROOT/t018" pin cfg outcome recorded out rc
  mkdir -p "$dir/.aai/scripts" "$dir/.aai/system" "$dir/docs/ai"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email "test@example.invalid"
  git -C "$dir" config user.name "AAI Test"
  git -C "$dir" remote add origin "https://example.invalid/some-owner/target.git"
  # REAL update-check + layer-drift copied in so the detached child's SELF_DIR
  # resolves to a RECORDING stub aai-update.sh sitting beside them.
  cp "$CHECK_SCRIPT" "$dir/.aai/scripts/update-check.mjs"
  cp "$DRIFT_SCRIPT" "$dir/.aai/scripts/layer-drift.mjs"
  recorded="$dir/.aai/recorded-source.txt"
  cat > "$dir/.aai/scripts/aai-update.sh" <<STUB
#!/usr/bin/env bash
# recording stub: capture the --repo (sync source) it was invoked with.
repo=""
while [[ \$# -gt 0 ]]; do case "\$1" in --repo) repo="\$2"; shift 2;; *) shift;; esac; done
printf '%s\n' "\$repo" > "$recorded"
echo "stub sync applied"
exit 0
STUB
  chmod +x "$dir/.aai/scripts/aai-update.sh"
  pin="$dir/.aai/system/AAI_PIN.md"
  cfg="$dir/docs/ai/update-config.yaml"
  outcome="$dir/.aai/cache/update-sync-outcome.json"
  # Pin names the ALTERNATE canonical ($CANON, a local git dir) and is behind it.
  # NO --source, NO --remote: the source must be DERIVED from the pin/verdict,
  # NOT default to goodwind-cz/aai (which would overwrite from an unrelated repo).
  write_pin "$pin" "${CANON_SHAS[0]}" "$CANON"
  write_config "$cfg" auto
  set +e
  out="$(cd "$dir" && node "$dir/.aai/scripts/update-check.mjs" --pin "$pin" --config "$cfg" --outcome "$outcome" --force 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "source-agreement run must exit 0 (got $rc): $out"
  wait_for_grep "$recorded" "." 20 || log_fail "aai-update stub was never invoked: outcome=$(cat "$outcome" 2>/dev/null)"
  grep -qF "$CANON" "$recorded" || log_fail "aai-update must sync from the pin-named source '$CANON', got: [$(cat "$recorded")]"
  log_pass "TEST-018 auto derives the sync --source from the drift verdict (source agreement)"
}

# --- TEST-019 — detached --run-sync child has NO bounded watchdog ---------------
test_detached_no_watchdog() {
  log_info "TEST-019: the detached --run-sync sync runs aai-update with NO bounded watchdog (runs to completion)..."
  local out rc
  set +e
  out="$(node --input-type=module -e "
import { buildSyncSpawnOptions } from '$CHECK_SCRIPT';
const detached = buildSyncSpawnOptions(null, '/tmp/x');
if ('timeout' in detached && detached.timeout !== undefined) { console.error('FAIL: detached sync must be unbounded (no watchdog), got timeout=' + detached.timeout); process.exit(1); }
const bounded = buildSyncSpawnOptions(5000, '/tmp/x');
if (bounded.timeout == null) { console.error('FAIL: a bounded call must still set a timeout'); process.exit(1); }
console.log('ok');
" 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "detached-no-watchdog assertion failed: $out"
  log_pass "TEST-019 detached --run-sync sync has no bounded watchdog (runs to completion)"
}

# --- TEST-020 — future-dated running marker frees the concurrent guard ----------
test_future_dated_running_marker() {
  log_info "TEST-020: a running marker with a FUTURE started_utc is NOT treated as in-flight -> a new sync may launch..."
  local dir="$TMP_ROOT/t020" src="$TMP_ROOT/t020-src" pin cfg outcome out rc
  build_sync_source "$src"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email "test@example.invalid"
  git -C "$dir" config user.name "AAI Test"
  git -C "$dir" remote add origin "https://example.invalid/some-owner/target.git"
  mkdir -p "$dir/.aai/system" "$dir/.aai/cache"
  pin="$dir/.aai/system/AAI_PIN.md"
  cfg="$dir/docs/ai/update-config.yaml"
  outcome="$dir/.aai/cache/update-sync-outcome.json"
  write_pin "$pin" "${CANON_SHAS[0]}" "$CANON"
  write_config "$cfg" auto
  # A running marker dated in the FUTURE: naive (now-started)<=STALE is negative
  # and wedges the guard forever; it must be treated as never-in-flight (free).
  printf '{"started_utc":"2099-01-01T00:00:00Z","finished_utc":null,"target_version":null,"result":"running","detail":null,"reported":false}\n' > "$outcome"
  set +e
  out="$(cd "$dir" && runcheck --pin "$pin" --config "$cfg" --remote "$CANON" --source "$src" --outcome "$outcome" --now "2026-07-20T11:00:00Z" --force 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "future-dated running marker run must exit 0 (got $rc): $out"
  echo "$out" | grep -qi "in progress" && log_fail "future-dated running marker must NOT be treated as in-flight, got: $out"
  echo "$out" | grep -qi "background" || log_fail "a new detached sync must be launched (background), got: $out"
  wait_for_grep "$outcome" '"result":"applied"' 20 || log_fail "the freshly launched sync outcome not applied: $(cat "$outcome" 2>/dev/null)"
  log_pass "TEST-020 future-dated running marker frees the concurrent guard (self-heals)"
}

# --- TEST-021 — throttle_hours strict digits-only validation -------------------
test_throttle_hours_strict() {
  log_info "TEST-021: throttle_hours with a non-digit token (24h, 0x10) is rejected -> stderr warning + default 24..."
  local dir="$TMP_ROOT/t021" pin cfg cache errf out rc bad
  mkdir -p "$dir/.aai/system" "$dir/.aai/cache"
  pin="$dir/.aai/system/AAI_PIN.md"
  cache="$dir/.aai/cache/update-check.json"
  write_pin "$pin" "${CANON_SHAS[0]}" "$CANON"
  errf="$TMP_ROOT/t021.err"
  # Cache 1h before the injected clock: within the DEFAULT 24h window. A run that
  # correctly rejects the bad token and defaults to 24 STAYS THROTTLED (silent);
  # a buggy coercion of "0x10" -> 0 would disable throttling and notify.
  for bad in "24h" "0x10"; do
    cfg="$dir/config-$bad.yaml"
    write_config "$cfg" notify "$bad"
    printf '{"last_check_utc":"2026-07-20T10:00:00Z"}' > "$cache"
    set +e
    out="$(cd "$dir" && runcheck --pin "$pin" --config "$cfg" --remote "$CANON" --cache "$cache" --now "2026-07-20T11:00:00Z" 2>"$errf")"; rc=$?
    set -e
    [[ "$rc" -eq 0 ]] || log_fail "throttle_hours '$bad' run must exit 0 (got $rc): $out"
    grep -qi "throttle_hours" "$errf" || log_fail "throttle_hours '$bad' must warn on stderr, got: [$(cat "$errf")]"
    grep -qi "not a non-negative integer" "$errf" || log_fail "throttle_hours '$bad' warning must name the contract, got: [$(cat "$errf")]"
    echo "$out" | grep -qi "newer AAI release" && log_fail "throttle_hours '$bad' must default to 24 (stay throttled within 24h), but it probed/notified: $out"
  done
  log_pass "TEST-021 throttle_hours non-digit token rejected -> stderr warning + default 24"
}

# --- TEST-022 — failed outcome message makes no false cleanliness claim --------
test_failed_outcome_message() {
  log_info "TEST-022: a failed detached-sync outcome advises git status/diff + rerun and makes NO false 'no changes forced' claim..."
  local dir="$TMP_ROOT/t022" pin cfg outcome out rc
  mkdir -p "$dir/.aai/system" "$dir/.aai/cache"
  pin="$dir/.aai/system/AAI_PIN.md"
  cfg="$dir/update-config.yaml"
  outcome="$dir/.aai/cache/update-sync-outcome.json"
  write_pin "$pin" "${CANON_SHAS[2]}" "$CANON"   # pin EQUAL -> no new sync; only surfacing
  write_config "$cfg" notify
  printf '{"started_utc":"2026-07-20T09:00:00Z","finished_utc":"2026-07-20T09:00:30Z","target_version":"abc1234","result":"failed","detail":"clone failed","reported":false}\n' > "$outcome"
  set +e
  out="$(cd "$dir" && runcheck --pin "$pin" --config "$cfg" --remote "$CANON" --outcome "$outcome" --force 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "failed-outcome surfacing run must exit 0 (got $rc): $out"
  echo "$out" | grep -qi "auto-update failed" || log_fail "a failed outcome must be surfaced, got: $out"
  echo "$out" | grep -qiE "git status|git diff" || log_fail "failed message must point at git status/diff, got: $out"
  echo "$out" | grep -qi "No changes were forced" && log_fail "failed message must NOT falsely claim cleanliness, got: $out"
  log_pass "TEST-022 failed outcome message advises git status/diff, no false cleanliness claim"
}

# --- TEST-023 — PowerShell host selection (pwsh, else powershell.exe) ----------
test_resolve_pwsh() {
  log_info "TEST-023: resolvePwsh selects pwsh when available, else falls back to powershell.exe (Windows PS 5.1)..."
  local out rc
  set +e
  out="$(node --input-type=module -e "
import { resolvePwsh } from '$CHECK_SCRIPT';
if (resolvePwsh(() => true) !== 'pwsh') { console.error('FAIL: available -> pwsh'); process.exit(1); }
if (resolvePwsh(() => false) !== 'powershell.exe') { console.error('FAIL: unavailable -> powershell.exe'); process.exit(1); }
if (resolvePwsh((e) => e === 'powershell.exe') !== 'powershell.exe') { console.error('FAIL: only 5.1 present -> powershell.exe'); process.exit(1); }
console.log('ok');
" 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "resolvePwsh selection assertion failed: $out"
  log_pass "TEST-023 resolvePwsh: pwsh if available else powershell.exe"
}

# --- TEST-024 — atomic O_EXCL claim: N true-parallel runs -> exactly ONE sync --
# (RR-1) The `running`-marker guard is a cross-process TOCTOU: N truly-
# simultaneous same-repo starts each read "no sync in flight", each decide to
# spawn, each write the marker, each launch a detached aai-update (probe: 5->5).
# The atomic O_EXCL claim on .aai/cache/update-sync.lock makes exactly one win.
test_atomic_claim_single_invocation() {
  log_info "TEST-024: 5 TRUE-parallel auto+behind runs -> EXACTLY ONE detached sync invocation (atomic O_EXCL claim; the rest back off 'in progress')..."
  local dir="$TMP_ROOT/t024" src="$TMP_ROOT/t024-src" pin cfg outcome n bg inflight i
  build_slow_sync_source "$src" 3
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
  # Launch 5 full update-check parents as close to simultaneously as possible;
  # pre-fix each independently spawns a detached sync (TOCTOU), so the invocation
  # counter would read 5. Post-fix exactly one wins the atomic claim.
  for i in 1 2 3 4 5; do
    ( cd "$dir" && node "$CHECK_SCRIPT" --pin "$pin" --config "$cfg" --remote "$CANON" --source "$src" --outcome "$outcome" --force >"$dir/run-$i.out" 2>&1 ) &
  done
  wait
  # NB: "detached" uniquely marks the SPAWNER line; the back-off line ("a
  # background sync is already in progress") also contains "background", so a
  # "background" grep would match every run — discriminate on "detached".
  bg="$({ grep -l -i "detached" "$dir"/run-*.out 2>/dev/null || true; } | wc -l | tr -d ' ')"
  inflight="$({ grep -l -i "in progress" "$dir"/run-*.out 2>/dev/null || true; } | wc -l | tr -d ' ')"
  [[ "$bg" == "1" ]] || log_fail "expected exactly 1 run to spawn the sync (background), got $bg (outputs: $(cat "$dir"/run-*.out))"
  [[ "$inflight" == "4" ]] || log_fail "expected 4 runs to back off 'in progress', got $inflight (outputs: $(cat "$dir"/run-*.out))"
  wait_for_grep "$outcome" '"result":"applied"' 25 || log_fail "detached sync outcome not applied within timeout: $(cat "$outcome" 2>/dev/null)"
  n="$(wc -l < "$dir/.aai/sync-invocations" 2>/dev/null | tr -d ' ')"
  [[ "$n" == "1" ]] || log_fail "atomic claim failed: expected exactly 1 sync invocation across 5 TRUE-parallel runs, got $n"
  log_pass "TEST-024 atomic O_EXCL claim -> exactly one sync across 5 true-parallel runs"
}

# --- TEST-025 — lock lifecycle: fresh blocks, stale + future reclaim (no wedge) -
# (RR-1 safety valve) A FRESH lock backs a racer off (in progress, no duplicate
# spawn). A STALE (>30min) or FUTURE-dated lock is a crashed/abandoned sync and
# is reclaimed so auto mode NEVER wedges. Reuses the SYNC_STALE_MS window.
test_lock_reclaim_and_block() {
  log_info "TEST-025: a FRESH lock blocks a duplicate spawn (in progress); a STALE or FUTURE lock is reclaimed (fresh sync spawns) -> never wedges..."
  # (a) FRESH lock -> back off, NO spawn, NO invocation.
  local dir="$TMP_ROOT/t025a" src="$TMP_ROOT/t025a-src" pin cfg outcome lock out rc
  build_sync_source "$src"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email "test@example.invalid"; git -C "$dir" config user.name "AAI Test"
  git -C "$dir" remote add origin "https://example.invalid/some-owner/target.git"
  mkdir -p "$dir/.aai/system" "$dir/.aai/cache"
  pin="$dir/.aai/system/AAI_PIN.md"; cfg="$dir/docs/ai/update-config.yaml"
  outcome="$dir/.aai/cache/update-sync-outcome.json"; lock="$dir/.aai/cache/update-sync.lock"
  write_pin "$pin" "${CANON_SHAS[0]}" "$CANON"; write_config "$cfg" auto
  printf '{"pid":424242,"started_utc":"2026-07-20T10:59:00Z"}\n' > "$lock"   # 1 min old -> fresh
  set +e
  out="$(cd "$dir" && runcheck --pin "$pin" --config "$cfg" --remote "$CANON" --source "$src" --outcome "$outcome" --now "2026-07-20T11:00:00Z" --force 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "fresh-lock run must exit 0 (got $rc): $out"
  echo "$out" | grep -qi "in progress" || log_fail "a FRESH lock must make the run back off 'in progress', got: $out"
  echo "$out" | grep -qi "detached" && log_fail "a FRESH lock must NOT spawn a duplicate sync (detached), got: $out"
  sleep 1
  [[ ! -f "$dir/.aai/sync-invocations" ]] || log_fail "a FRESH lock must prevent any sync invocation, got: $(cat "$dir/.aai/sync-invocations")"

  # (b) STALE lock (2h old, > 30min window) -> reclaimed, a fresh sync spawns.
  local d2="$TMP_ROOT/t025b" s2="$TMP_ROOT/t025b-src" p2 c2 o2 l2
  build_sync_source "$s2"
  mkdir -p "$d2"
  git -C "$d2" init -q -b main
  git -C "$d2" config user.email "test@example.invalid"; git -C "$d2" config user.name "AAI Test"
  git -C "$d2" remote add origin "https://example.invalid/some-owner/target.git"
  mkdir -p "$d2/.aai/system" "$d2/.aai/cache"
  p2="$d2/.aai/system/AAI_PIN.md"; c2="$d2/docs/ai/update-config.yaml"
  o2="$d2/.aai/cache/update-sync-outcome.json"; l2="$d2/.aai/cache/update-sync.lock"
  write_pin "$p2" "${CANON_SHAS[0]}" "$CANON"; write_config "$c2" auto
  printf '{"pid":424242,"started_utc":"2026-07-20T09:00:00Z"}\n' > "$l2"   # 2h old -> stale
  set +e
  out="$(cd "$d2" && runcheck --pin "$p2" --config "$c2" --remote "$CANON" --source "$s2" --outcome "$o2" --now "2026-07-20T11:00:00Z" --force 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "stale-lock run must exit 0 (got $rc): $out"
  echo "$out" | grep -qi "detached" || log_fail "a STALE lock must be reclaimed and a fresh sync spawned (detached), got: $out"
  wait_for_grep "$o2" '"result":"applied"' 20 || log_fail "reclaimed stale-lock sync outcome not applied: $(cat "$o2" 2>/dev/null)"

  # (c) FUTURE-dated lock -> reclaimed (mirror the future-date guards).
  local d3="$TMP_ROOT/t025c" s3="$TMP_ROOT/t025c-src" p3 c3 o3 l3
  build_sync_source "$s3"
  mkdir -p "$d3"
  git -C "$d3" init -q -b main
  git -C "$d3" config user.email "test@example.invalid"; git -C "$d3" config user.name "AAI Test"
  git -C "$d3" remote add origin "https://example.invalid/some-owner/target.git"
  mkdir -p "$d3/.aai/system" "$d3/.aai/cache"
  p3="$d3/.aai/system/AAI_PIN.md"; c3="$d3/docs/ai/update-config.yaml"
  o3="$d3/.aai/cache/update-sync-outcome.json"; l3="$d3/.aai/cache/update-sync.lock"
  write_pin "$p3" "${CANON_SHAS[0]}" "$CANON"; write_config "$c3" auto
  printf '{"pid":424242,"started_utc":"2099-01-01T00:00:00Z"}\n' > "$l3"   # future -> reclaimable
  set +e
  out="$(cd "$d3" && runcheck --pin "$p3" --config "$c3" --remote "$CANON" --source "$s3" --outcome "$o3" --now "2026-07-20T11:00:00Z" --force 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "future-lock run must exit 0 (got $rc): $out"
  echo "$out" | grep -qi "detached" || log_fail "a FUTURE-dated lock must be reclaimed (detached), got: $out"
  wait_for_grep "$o3" '"result":"applied"' 20 || log_fail "reclaimed future-lock sync outcome not applied: $(cat "$o3" 2>/dev/null)"
  log_pass "TEST-025 fresh lock blocks; stale + future locks reclaimed (never wedges)"
}

# --- TEST-026 — concurrent surfacing: a finished outcome surfaces at most once --
# (RR-2) once-only surfacing is a read->print->flip-reported TOCTOU: N
# simultaneous runs can each print the "applied" line. An atomic surfacing claim
# makes exactly one print. Sequential surfacing (TEST-015) stays unchanged.
test_concurrent_surface_once() {
  log_info "TEST-026: 8 TRUE-parallel runs surface a completed outcome AT MOST ONCE (atomic surfacing claim)..."
  local dir="$TMP_ROOT/t026" pin cfg outcome i printed
  mkdir -p "$dir/.aai/system" "$dir/.aai/cache"
  pin="$dir/.aai/system/AAI_PIN.md"; cfg="$dir/update-config.yaml"
  outcome="$dir/.aai/cache/update-sync-outcome.json"
  write_pin "$pin" "${CANON_SHAS[2]}" "$CANON"   # pin EQUAL -> up-to-date, no new sync
  write_config "$cfg" notify
  printf '{"started_utc":"2026-07-20T09:00:00Z","finished_utc":"2026-07-20T09:00:30Z","target_version":"abc1234","result":"applied","detail":"synced","reported":false}\n' > "$outcome"
  # Launch 8 runs simultaneously; pre-fix each reads reported:false and prints.
  for i in 1 2 3 4 5 6 7 8; do
    ( cd "$dir" && node "$CHECK_SCRIPT" --pin "$pin" --config "$cfg" --remote "$CANON" --outcome "$outcome" --force >"$dir/surf-$i.out" 2>&1 ) &
  done
  wait
  printed="$({ grep -l -i "auto-update applied" "$dir"/surf-*.out 2>/dev/null || true; } | wc -l | tr -d ' ')"
  [[ "$printed" == "1" ]] || log_fail "a completed outcome must surface AT MOST ONCE under concurrency, but $printed runs printed it (outputs: $(cat "$dir"/surf-*.out))"
  grep -q '"reported":true' "$outcome" || log_fail "surfaced outcome must end marked reported, cache: $(cat "$outcome")"
  log_pass "TEST-026 concurrent surfacing prints the applied line exactly once"
}

# --- TEST-027 — CONCURRENT stale-lock RECLAIM is atomic: exactly ONE sync -------
# (RR-1 full closure) TEST-024 covers a COLD start (no lock) and TEST-025 covers
# a SEQUENTIAL reclaim (one run vs a stale lock). Neither covers N racers
# reclaiming the SAME pre-existing stale lock at once. The pre-remediation
# read->rm->create reclaim was NOT atomic: two racers could both pass the
# staleness read, then the loser's rmSync would delete the WINNER's FRESH lock
# and its create would succeed -> TWO detached spawns for one stale lock. The
# atomic reclaim makes EXACTLY ONE racer win per stale lock. Amplified over
# several rounds so the pre-fix race reproduces near-certainly, while the fixed
# code is deterministic (exactly one spawn per round -> total == rounds).
test_concurrent_stale_reclaim() {
  log_info "TEST-027: N TRUE-parallel runs reclaiming a PRE-EXISTING stale lock -> EXACTLY ONE detached sync per round (atomic reclaim; amplified)..."
  local base="$TMP_ROOT/t027" src="$TMP_ROOT/t027-src" rounds=10 par=8 r i s
  local total_spawns=0 last_dir="" pin cfg outcome lock now="2026-07-20T11:00:00Z"
  build_slow_sync_source "$src" 3
  for r in $(seq 1 "$rounds"); do
    local dir="$base/r$r"
    mkdir -p "$dir/.aai/system" "$dir/.aai/cache" "$dir/docs/ai"
    git -C "$dir" init -q -b main
    git -C "$dir" config user.email "test@example.invalid"; git -C "$dir" config user.name "AAI Test"
    git -C "$dir" remote add origin "https://example.invalid/some-owner/target.git"
    pin="$dir/.aai/system/AAI_PIN.md"; cfg="$dir/docs/ai/update-config.yaml"
    outcome="$dir/.aai/cache/update-sync-outcome.json"; lock="$dir/.aai/cache/update-sync.lock"
    write_pin "$pin" "${CANON_SHAS[0]}" "$CANON"; write_config "$cfg" auto
    # A PRE-EXISTING 2h-old stale lock (> SYNC_STALE_MS) all racers must reclaim.
    printf '{"pid":424242,"started_utc":"2026-07-20T09:00:00Z"}\n' > "$lock"
    for i in $(seq 1 "$par"); do
      ( cd "$dir" && node "$CHECK_SCRIPT" --pin "$pin" --config "$cfg" --remote "$CANON" \
          --source "$src" --outcome "$outcome" --now "$now" --force >"$dir/run-$i.out" 2>&1 ) &
    done
    wait
    # "detached" uniquely marks the SPAWNER line (the back-off line says "in
    # progress"), so it counts reclaim winners for this round.
    s="$({ grep -l -i "detached" "$dir"/run-*.out 2>/dev/null || true; } | wc -l | tr -d ' ')"
    total_spawns=$((total_spawns + s))
    last_dir="$dir"
  done
  # Deterministic post-fix: exactly one reclaim winner per round. Pre-fix the
  # non-atomic reclaim double-spawns in one or more rounds -> total > rounds.
  [[ "$total_spawns" == "$rounds" ]] \
    || log_fail "concurrent reclaim not atomic: expected exactly $rounds detached spawns ($par parallel x $rounds rounds, one winner each), got $total_spawns"
  # Harm fidelity: the last round's SINGLE winner produced exactly ONE real sync
  # invocation (not merely one 'detached' line).
  wait_for_grep "$last_dir/.aai/cache/update-sync-outcome.json" '"result":"applied"' 25 \
    || log_fail "reclaimed-lock sync outcome not applied: $(cat "$last_dir/.aai/cache/update-sync-outcome.json" 2>/dev/null)"
  local n
  n="$(wc -l < "$last_dir/.aai/sync-invocations" 2>/dev/null | tr -d ' ')"
  [[ "$n" == "1" ]] || log_fail "atomic reclaim failed: expected exactly 1 sync invocation in the last round, got $n"
  log_pass "TEST-027 concurrent stale-lock reclaim is atomic (exactly one spawn/invocation per round across $rounds rounds x $par parallel)"
}

# --- TEST-028 — surfaceOutcome restores the outcome on a post-claim read fail ---
# (Defect 2) After the atomic claim rename (outcome -> .surfacing) succeeds, a
# torn/failed read of the .surfacing file must NOT orphan the outcome there with
# the real path gone (it would then never surface). The fix renames .surfacing
# back to the outcome path (best-effort) and surfaces nothing; a later run then
# surfaces it exactly once. Verified via an injected read fault (targeted unit
# check) since a torn read after a same-process rename is not otherwise
# deterministically reproducible in a black-box run.
test_surface_restore_on_read_failure() {
  log_info "TEST-028: surfaceOutcome restores the outcome (no .surfacing orphan) when the post-claim read throws, and a later run surfaces it once..."
  local out rc
  set +e
  out="$(node --input-type=module -e "
import { surfaceOutcome } from '$CHECK_SCRIPT';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'surf-restore-'));
const oc = path.join(dir, 'update-sync-outcome.json');
fs.writeFileSync(oc, JSON.stringify({started_utc:'2026-07-20T09:00:00Z',finished_utc:'2026-07-20T09:00:30Z',target_version:'abc1234',result:'applied',detail:'synced',reported:false}) + '\n');
const emit = []; const result = { reported_outcome: null };
// Injected fault: the read AFTER the claim rename throws (torn write observed).
surfaceOutcome(oc, emit, result, () => { throw new Error('torn read after claim'); });
// The claim path is PER-PID (\${oc}.surfacing.<pid>.<seq>); assert on the glob so
// a per-pid orphan regression is actually caught (the old shared '.surfacing'
// path could never match the real code).
const orphans = fs.readdirSync(dir).filter((n) => n.startsWith(path.basename(oc) + '.surfacing.'));
if (orphans.length) { console.error('FAIL: outcome orphaned at ' + orphans.join(',')); process.exit(1); }
if (!fs.existsSync(oc)) { console.error('FAIL: outcome lost (not restored to the outcome path)'); process.exit(1); }
if (emit.length) { console.error('FAIL: nothing must surface on a torn read, got: ' + emit.join(' | ')); process.exit(1); }
if (JSON.parse(fs.readFileSync(oc, 'utf8')).reported) { console.error('FAIL: restored outcome must stay unreported (surface next run)'); process.exit(1); }
// A subsequent NORMAL run (default reader) surfaces the recovered outcome ONCE.
surfaceOutcome(oc, emit, result);
if (!emit.some((l) => /auto-update applied/i.test(l))) { console.error('FAIL: recovered outcome must surface once on the next run'); process.exit(1); }
if (!JSON.parse(fs.readFileSync(oc, 'utf8')).reported) { console.error('FAIL: surfaced outcome must be marked reported'); process.exit(1); }
console.log('ok');
" 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "surface-restore-on-read-failure assertion failed: $out"
  log_pass "TEST-028 surfaceOutcome restores the outcome on a post-claim read failure (no orphan; surfaces once later)"
}

# --- TEST-029 — linkSync-unsupported claim falls back to wx; genuine error is loud
# (Finding A) claimLockFile hard-links a per-pid temp into place; on a filesystem
# that disallows hard links (EPERM/ENOSYS/EOPNOTSUPP/EMLINK) it must FALL BACK to
# an atomic openSync(..,'wx') create so the claim still succeeds and auto-update
# actually runs. A GENUINE claim error (e.g. EACCES) must NOT masquerade as "a
# sync is already in progress" (silent no-op); it must be a loud, non-fatal skip.
# Injected via a NODE_OPTIONS preload that forces fs.linkSync to throw.
test_linksync_fallback_and_error() {
  log_info "TEST-029: linkSync-unsupported -> wx fallback (sync spawns); genuine error -> loud warning, not a silent 'in progress'..."
  local dir="$TMP_ROOT/t029" src="$TMP_ROOT/t029-src" pin cfg outcome preload out err rc
  build_sync_source "$src"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email "test@example.invalid"; git -C "$dir" config user.name "AAI Test"
  git -C "$dir" remote add origin "https://example.invalid/some-owner/target.git"
  mkdir -p "$dir/.aai/system"
  pin="$dir/.aai/system/AAI_PIN.md"; cfg="$dir/docs/ai/update-config.yaml"
  outcome="$dir/.aai/cache/update-sync-outcome.json"
  write_pin "$pin" "${CANON_SHAS[0]}" "$CANON"; write_config "$cfg" auto
  # Preload that forces fs.linkSync to throw a code chosen by an env var. Shared
  # fs default object -> update-check's linkSync is overridden in-process.
  preload="$TMP_ROOT/t029-linkfail.mjs"
  cat > "$preload" <<'PRE'
import fs from 'node:fs';
const code = process.env.AAI_TEST_LINK_FAIL || 'ENOSYS';
fs.linkSync = () => { const e = new Error('injected link failure'); e.code = code; throw e; };
PRE
  # (a) ENOSYS (hard links unsupported) -> wx fallback -> the claim succeeds and
  # the detached sync spawns + eventually applies.
  set +e
  out="$(cd "$dir" && AAI_TEST_LINK_FAIL=ENOSYS NODE_OPTIONS="--import file://$preload" \
    node "$CHECK_SCRIPT" --pin "$pin" --config "$cfg" --remote "$CANON" --source "$src" --outcome "$outcome" --force 2>/dev/null)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "linkSync-ENOSYS run must exit 0 (got $rc): $out"
  echo "$out" | grep -qi "detached" || log_fail "linkSync-unsupported must fall back to wx and SPAWN the sync (detached), got: $out"
  echo "$out" | grep -qi "in progress" && log_fail "linkSync-unsupported must NOT report a bogus in-progress sync, got: $out"
  wait_for_grep "$outcome" '"result":"applied"' 20 || log_fail "wx-fallback sync outcome not applied: $(cat "$outcome" 2>/dev/null)"
  [[ -f "$dir/.aai/system-marker.txt" ]] || log_fail "wx-fallback sync did not materialize the synced marker"

  # (b) EACCES (genuine claim error) -> loud stderr WARNING, NO spawn, and NOT the
  # silent "in progress" no-op that pre-fix masqueraded a genuine failure as.
  local d2="$TMP_ROOT/t029b" s2="$TMP_ROOT/t029b-src" p2 c2 o2
  build_sync_source "$s2"
  mkdir -p "$d2"
  git -C "$d2" init -q -b main
  git -C "$d2" config user.email "test@example.invalid"; git -C "$d2" config user.name "AAI Test"
  git -C "$d2" remote add origin "https://example.invalid/some-owner/target.git"
  mkdir -p "$d2/.aai/system"
  p2="$d2/.aai/system/AAI_PIN.md"; c2="$d2/docs/ai/update-config.yaml"
  o2="$d2/.aai/cache/update-sync-outcome.json"
  write_pin "$p2" "${CANON_SHAS[0]}" "$CANON"; write_config "$c2" auto
  err="$TMP_ROOT/t029b.err"
  set +e
  out="$(cd "$d2" && AAI_TEST_LINK_FAIL=EACCES NODE_OPTIONS="--import file://$preload" \
    node "$CHECK_SCRIPT" --pin "$p2" --config "$c2" --remote "$CANON" --source "$s2" --outcome "$o2" --force 2>"$err")"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "genuine-error run must still exit 0 non-fatally (got $rc): $out / $(cat "$err")"
  grep -qi "WARNING" "$err" || log_fail "a genuine claim error must emit a loud stderr WARNING, got stderr: [$(cat "$err")]"
  grep -qi "lock" "$err" || log_fail "the genuine-error warning must name the lock, got stderr: [$(cat "$err")]"
  echo "$out" | grep -qi "in progress" && log_fail "a genuine claim error must NOT masquerade as 'in progress', got: $out"
  sleep 1
  [[ ! -f "$d2/.aai/system-marker.txt" ]] || log_fail "a genuine claim error must NOT spawn a sync"
  log_pass "TEST-029 linkSync-unsupported falls back to wx (sync spawns); genuine error is a loud non-silent skip"
}

# --- TEST-030 — releaseSyncLock only deletes the lock THIS sync owns ------------
# (Finding B) If a sync outlives the 30min stale window, a second run reclaims
# (installs a NEW lock with a new owner token). The first sync's release must NOT
# delete the reclaimer's lock (deleting by path would let a THIRD sync start).
# Release only when the recorded owner token matches.
test_owner_scoped_release() {
  log_info "TEST-030: releaseSyncLock leaves a lock owned by a DIFFERENT token; deletes only the owner's own lock..."
  local out rc
  set +e
  out="$(node --input-type=module -e "
import { releaseSyncLock } from '$CHECK_SCRIPT';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'owner-rel-'));
const lock = path.join(dir, 'update-sync.lock');
fs.writeFileSync(lock, JSON.stringify({pid:111, started_utc:'2026-07-20T09:00:00Z', token:'OWNER-A'}) + '\n');
// A DIFFERENT owner token (a reclaimer's lock) must NOT be deleted.
releaseSyncLock(lock, 'OWNER-B');
if (!fs.existsSync(lock)) { console.error('FAIL: released a lock owned by a different token'); process.exit(1); }
// The owner's OWN token deletes it.
releaseSyncLock(lock, 'OWNER-A');
if (fs.existsSync(lock)) { console.error('FAIL: owner did not delete its own lock'); process.exit(1); }
console.log('ok');
" 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "owner-scoped-release assertion failed: $out"
  log_pass "TEST-030 releaseSyncLock is owner-scoped (mismatched token kept, own token deleted)"
}

# --- TEST-031 — surfaceOutcome recovers a STALE orphaned .surfacing.* claim -----
# (Finding C) If a reporter is killed after the atomic claim rename (outcome ->
# .surfacing.PID.SEQ) but before restore/recreate, the sole outcome copy is
# orphaned at the per-pid claim path with the real outcome gone -> it never
# surfaces. A later run must recover the newest mtime-STALE orphan (never a fresh
# one from a live reporter) and surface it exactly once.
test_surface_orphan_recovery() {
  log_info "TEST-031: a STALE orphaned .surfacing.* with no outcome file is recovered and surfaced once; a FRESH orphan is left untouched..."
  local out rc
  set +e
  out="$(node --input-type=module -e "
import { surfaceOutcome } from '$CHECK_SCRIPT';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'surf-orphan-'));
const oc = path.join(dir, 'update-sync-outcome.json');
const body = JSON.stringify({started_utc:'2026-07-20T09:00:00Z',finished_utc:'2026-07-20T09:00:30Z',target_version:'abc1234',result:'applied',detail:'synced',reported:false}) + '\n';
// (a) FRESH orphan (mtime now), no outcome -> NOT resurrected (a live reporter).
const fresh = oc + '.surfacing.4242.0';
fs.writeFileSync(fresh, body);
let emit = []; const result = { reported_outcome: null };
surfaceOutcome(oc, emit, result);
if (emit.length) { console.error('FAIL: a FRESH orphan must NOT be recovered mid-flight, got: ' + emit.join(' | ')); process.exit(1); }
if (!fs.existsSync(fresh)) { console.error('FAIL: a fresh orphan (live reporter) must be left in place'); process.exit(1); }
fs.rmSync(fresh, { force: true });
// (b) STALE orphan (mtime > 30min old), no outcome -> recovered + surfaced once.
const stale = oc + '.surfacing.99999.0';
fs.writeFileSync(stale, body);
const old = (Date.now() - 40 * 60 * 1000) / 1000;
fs.utimesSync(stale, old, old);
emit = [];
surfaceOutcome(oc, emit, result);
if (!emit.some((l) => /auto-update applied/i.test(l))) { console.error('FAIL: a stale orphan must be recovered and surfaced'); process.exit(1); }
if (fs.existsSync(stale)) { console.error('FAIL: recovered orphan claim not consumed'); process.exit(1); }
if (!fs.existsSync(oc)) { console.error('FAIL: recovered outcome not written back to the outcome path'); process.exit(1); }
if (!JSON.parse(fs.readFileSync(oc, 'utf8')).reported) { console.error('FAIL: recovered+surfaced outcome must be marked reported'); process.exit(1); }
// (c) a subsequent run does NOT surface it again (once-only preserved).
const emit2 = [];
surfaceOutcome(oc, emit2, result);
if (emit2.length) { console.error('FAIL: a recovered outcome must surface only once, got: ' + emit2.join(' | ')); process.exit(1); }
console.log('ok');
" 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "surface-orphan-recovery assertion failed: $out"
  log_pass "TEST-031 surfaceOutcome recovers a stale orphaned claim once; leaves a fresh (live) orphan untouched"
}

# --- 0138-TEST-005 (CHANGE-0138 Spec-AC-04, behavioral half, update-check side)
# A UTF-8 BOM immediately followed by a first-line column-0 `mode: auto` key
# must be honored by resolveConfig: on the throttled fast path (fresh cache +
# injected --now, zero network) --json resolves effective_mode auto with
# throttled true. The twin structural pin lives in test-aai-update.sh.
test_bom_first_line_key() {
  log_info "0138-TEST-005: BOM + first-line 'mode: auto' -> effective_mode auto on the throttled fast path (zero network)..."
  local dir="$TMP_ROOT/t0138-bom" cfg cache out rc
  mkdir -p "$dir/.aai/cache"
  cfg="$dir/update-config.yaml"
  cache="$dir/.aai/cache/update-check.json"
  # EF BB BF then the column-0 key on LINE ONE (the exact NB-2 shape).
  printf '\357\273\277mode: auto\n' > "$cfg"
  # Fresh cache within the default 24h window -> throttle fast path, no probe.
  printf '{"last_check_utc":"2026-07-20T10:00:00Z"}' > "$cache"
  set +e
  out="$(cd "$dir" && runcheck --config "$cfg" --cache "$cache" --now "2026-07-20T11:00:00Z" --json 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "0138-TEST-005: throttled BOM run must exit 0 (got $rc): $out"
  grep -qF '"effective_mode":"auto"' <<<"$out" \
    || log_fail "0138-TEST-005: BOM must not hide the first-line mode key (want auto): $out"
  grep -qF '"throttled":true' <<<"$out" \
    || log_fail "0138-TEST-005: expected the throttled fast path (zero network): $out"
  log_pass "0138-TEST-005 BOM-prefixed first-line mode: auto honored on the throttled fast path"
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
  test_source_agreement
  test_detached_no_watchdog
  test_future_dated_running_marker
  test_throttle_hours_strict
  test_failed_outcome_message
  test_resolve_pwsh
  test_atomic_claim_single_invocation
  test_lock_reclaim_and_block
  test_concurrent_surface_once
  test_concurrent_stale_reclaim
  test_surface_restore_on_read_failure
  test_linksync_fallback_and_error
  test_owner_scoped_release
  test_surface_orphan_recovery
  test_bom_first_line_key
  echo "=== ALL TESTS PASSED: $TEST_NAME ==="
}

main "$@"
