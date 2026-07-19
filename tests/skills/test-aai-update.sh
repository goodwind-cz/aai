#!/usr/bin/env bash
#
# Test: aai-update.sh temp-dir TOCTOU fix (ISSUE-0012 / SPEC-0052, TEST-001..005).
#
# Covers the security-correctness fix to .aai/scripts/aai-update.sh: the
# securely-owned `mktemp -d` parent ($TMP) must be retained for the whole run
# and NEVER `rm -rf`'d-and-recreated mid-run; every clone/retry attempt must
# target a fresh SUBDIRECTORY of it ($TMP/src, i.e. $SRCDIR); only that
# subdirectory is wiped between attempts; the executed sync script resolves
# from inside the retained parent.
#
#   - TEST-001 (Spec-AC-01): static — clone-target argument in all three
#     clone attempts (gh / plain git / anonymous git) is "$SRCDIR" (=
#     "$TMP/src"), never bare "$TMP". RED on the current (unfixed) script.
#   - TEST-002 (Spec-AC-01): static — no mid-run `rm -rf "$TMP"` in the clone
#     cascade; only the exit-trap `cleanup()` removes $TMP; each per-attempt
#     wipe targets $SRCDIR. RED on the current (unfixed) script.
#   - TEST-003 (Spec-AC-01): `bash -n aai-update.sh` parses clean (exit 0).
#   - TEST-004 (Spec-AC-03): happy-path dry-run — `--force --dry-run` exits 0
#     and prints the "Would run" line; no $TMP is ever created (negative
#     control: dry-run never touches the filesystem).
#   - TEST-005 (Spec-AC-03, SEAM-1): integration — a real clone from a local
#     `file://` fixture repo with `--keep-temp`: the repo materializes at
#     $TMP/src, the parent $TMP is retained and owned by the invoker, and the
#     cloned `aai-sync.sh` actually executes against TARGET. A second arm
#     forces every clone attempt to fail (mid-operation failure) and asserts
#     a clean exit 3 with no stray $SRCDIR left behind. Skips cleanly if git
#     is unavailable.
#
# Fixture diversity checklist (SPEC-0013 H7), mapped:
#   - degenerate/empty       -> TEST-004: dry-run creates $TMP for zero runs
#   - zero-remainder          -> TEST-005a: single successful clone attempt,
#                                 nothing left to retry
#   - multi-source/multi-writer -> TEST-002 (static): three distinct clone
#                                 mechanisms (gh / git / anonymous git) all
#                                 target the SAME $SRCDIR output across
#                                 attempts — the multi-writer shape lives in
#                                 the retry cascade itself
#   - mid-operation failure   -> TEST-005b: an invalid source forces every
#                                 attempt to fail; $SRCDIR is wiped before
#                                 each retry and no partial clone survives
#   - negative control        -> TEST-004: dry-run must NOT create any
#                                 aai-src.* temp dir at all
#
# bash 3.2 compatible (no ${var^^}, no declare -A, no mapfile). Run via
# .aai/scripts/aai-run-tests.sh per the LEARNED wrapper rule.
#
# Usage:
#   bash tests/skills/test-aai-update.sh            # run all tests
#   bash tests/skills/test-aai-update.sh test_001_clone_target_is_srcdir
#                                                     # run one test
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-update"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

UPDATE_SH="$PROJECT_ROOT/.aai/scripts/aai-update.sh"

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; }
log_info() { echo "INFO: $*"; }

check_deps() {
  log_info "Checking dependencies..."
  [[ -f "$UPDATE_SH" ]] || log_fail "aai-update.sh not found: $UPDATE_SH"
  command -v bash >/dev/null 2>&1 || log_fail "bash not found"
  log_pass "Dependencies checked"
}

# --- TEST-001 (Spec-AC-01): clone target is $SRCDIR, never bare $TMP -------

test_001_clone_target_is_srcdir() {
  log_info "Test: clone-target argument in all three attempts is \"\$SRCDIR\" (=\"\$TMP/src\"), never bare \"\$TMP\" (TEST-001)..."

  local n
  n=$(grep -cF 'gh repo clone "$REPO" "$SRCDIR"' "$UPDATE_SH" || true)
  [[ "$n" == "1" ]] \
    || log_fail "TEST-001: expected exactly 1 'gh repo clone \"\$REPO\" \"\$SRCDIR\"' line, got $n"

  n=$(grep -cF '"$CLONE_URL" "$SRCDIR"' "$UPDATE_SH" || true)
  [[ "$n" == "2" ]] \
    || log_fail "TEST-001: expected exactly 2 '\"\$CLONE_URL\" \"\$SRCDIR\"' lines (plain git + anonymous git), got $n"

  n=$(grep -cF 'gh repo clone "$REPO" "$TMP"' "$UPDATE_SH" || true)
  [[ "$n" == "0" ]] \
    || log_fail "TEST-001: 'gh repo clone \"\$REPO\" \"\$TMP\"' (bare TMP target) must be ABSENT, found $n"

  n=$(grep -cF '"$CLONE_URL" "$TMP"' "$UPDATE_SH" || true)
  [[ "$n" == "0" ]] \
    || log_fail "TEST-001: '\"\$CLONE_URL\" \"\$TMP\"' (bare TMP target) must be ABSENT, found $n"

  n=$(grep -cF 'SRCDIR="$TMP/src"' "$UPDATE_SH" || true)
  [[ "$n" == "1" ]] \
    || log_fail "TEST-001: expected exactly 1 'SRCDIR=\"\$TMP/src\"' declaration, got $n"

  n=$(grep -cF 'SRC="$SRCDIR"' "$UPDATE_SH" || true)
  [[ "$n" == "1" ]] \
    || log_fail "TEST-001: expected exactly 1 'SRC=\"\$SRCDIR\"' assignment (sync must resolve inside the retained parent), got $n"

  log_pass "Clone target is \$SRCDIR in all three attempts; never bare \$TMP (TEST-001)"
}

# --- TEST-002 (Spec-AC-01): no mid-run rm -rf "$TMP" in the clone cascade --

test_002_no_midrun_rm_tmp() {
  log_info "Test: no mid-run 'rm -rf \"\$TMP\"' in the clone cascade; only the exit-trap removes \$TMP; per-attempt wipe targets \$SRCDIR (TEST-002)..."

  local n
  n=$(grep -cF 'rm -rf "$SRCDIR"' "$UPDATE_SH" || true)
  [[ "$n" == "3" ]] \
    || log_fail "TEST-002: expected exactly 3 'rm -rf \"\$SRCDIR\"' per-attempt wipes, got $n"

  n=$(grep -cF 'rm -rf "$TMP"' "$UPDATE_SH" || true)
  [[ "$n" == "1" ]] \
    || log_fail "TEST-002: expected exactly 1 'rm -rf \"\$TMP\"' in the WHOLE file (the exit-trap only), got $n"

  # That single remaining occurrence must be the cleanup() exit-trap line, not
  # a clone-cascade wipe.
  grep -qF -- '-d "$TMP" ]] && rm -rf "$TMP"' "$UPDATE_SH" \
    || log_fail "TEST-002: the sole 'rm -rf \"\$TMP\"' must be the cleanup() exit-trap guard line"

  log_pass "No mid-run 'rm -rf \"\$TMP\"' in the clone cascade; only cleanup() removes \$TMP (TEST-002)"
}

# --- TEST-003 (Spec-AC-01): bash -n parses clean ----------------------------

test_003_bash_syntax_check() {
  log_info "Test: bash -n aai-update.sh exits 0 (TEST-003)..."
  bash -n "$UPDATE_SH" || log_fail "TEST-003: bash -n aai-update.sh failed to parse"
  log_pass "bash -n aai-update.sh parses clean (TEST-003)"
}

# --- TEST-004 (Spec-AC-03): happy-path dry-run + negative control ----------

test_004_dry_run_happy_path() {
  log_info "Test: happy-path dry-run exits 0 with 'Would run' line; no \$TMP ever created (TEST-004)..."

  local fixture_tmpdir target_dir out err code
  fixture_tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/aai-update-test-dryrun-tmpbase.XXXXXX")"
  target_dir="$(mktemp -d "${TMPDIR:-/tmp}/aai-update-test-dryrun-target.XXXXXX")"

  out="$fixture_tmpdir/out.log"; err="$fixture_tmpdir/err.log"
  code=0
  ( cd "$target_dir" && TMPDIR="$fixture_tmpdir" bash "$UPDATE_SH" --force --dry-run ) \
    > "$out" 2> "$err" || code=$?

  [[ "$code" == "0" ]] \
    || log_fail "TEST-004: --force --dry-run expected exit 0, got $code (stderr: $(cat "$err"))"
  grep -qE 'Would run:.*aai-sync\.sh' "$out" \
    || log_fail "TEST-004: dry-run stdout missing 'Would run: ...aai-sync.sh' line (got: $(cat "$out"))"

  # negative control: dry-run must never create an aai-src.* temp dir
  local stray
  stray="$(find "$fixture_tmpdir" -maxdepth 1 -name 'aai-src.*' 2>/dev/null | head -1 || true)"
  [[ -z "$stray" ]] \
    || log_fail "TEST-004: dry-run must not create any \$TMP (found stray: $stray)"

  rm -rf "$fixture_tmpdir" "$target_dir"
  log_pass "Dry-run: exit 0, 'Would run' line present, no \$TMP created (TEST-004)"
}

# --- TEST-005 (Spec-AC-03, SEAM-1): integration file:// fixture clone ------

# Builds a minimal local git repo at $1 that stands in for the canonical AAI
# repo: it has a fake .aai/scripts/aai-sync.sh which, when executed, proves
# (a) it actually ran and (b) what argv/cwd it saw, by writing a marker file
# into the given TARGET.
build_fixture_source_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir/.aai/scripts"
  cat > "$repo_dir/.aai/scripts/aai-sync.sh" <<'FIXTURE'
#!/usr/bin/env bash
set -euo pipefail
target="${1:?target required}"
mkdir -p "$target"
printf 'FIXTURE_SYNC_RAN target=%s\n' "$target" > "$target/FIXTURE_SYNC_MARKER"
FIXTURE
  chmod +x "$repo_dir/.aai/scripts/aai-sync.sh"
  git -C "$repo_dir" init -q -b main
  git -C "$repo_dir" -c user.email="test@example.com" -c user.name="test" \
    add -A
  git -C "$repo_dir" -c user.email="test@example.com" -c user.name="test" \
    commit -q -m "fixture"
}

test_005_integration_file_fixture_clone() {
  log_info "Test: SEAM-1 — real clone from local file:// fixture with --keep-temp lands at \$TMP/src, parent retained+owned, sync executes (TEST-005)..."

  if ! command -v git >/dev/null 2>&1; then
    log_skip "TEST-005: git not available — skipping cleanly"
    return 0
  fi

  local work_dir fixture_src target_dir fixture_tmpdir out err code
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/aai-update-test-e2e.XXXXXX")"
  # Canonicalize (mktemp can inherit a double slash from a trailing-slash
  # TMPDIR): the script's own `pwd` always normalizes, so comparisons below
  # must compare against the same normalized form.
  work_dir="$(cd "$work_dir" && pwd)"

  fixture_src="$work_dir/fixture-src-repo"
  mkdir -p "$fixture_src"
  build_fixture_source_repo "$fixture_src"

  # --- (a) happy path: single successful attempt (zero-remainder fixture) ---
  target_dir="$work_dir/target-a"
  mkdir -p "$target_dir"
  fixture_tmpdir="$work_dir/tmpbase-a"
  mkdir -p "$fixture_tmpdir"

  out="$work_dir/a.out"; err="$work_dir/a.err"
  code=0
  ( cd "$target_dir" && TMPDIR="$fixture_tmpdir" bash "$UPDATE_SH" \
      --repo "file://$fixture_src" --force --keep-temp ) \
    > "$out" 2> "$err" || code=$?
  [[ "$code" == "0" ]] \
    || log_fail "TEST-005a: expected exit 0, got $code (stderr: $(cat "$err"))"

  local found_tmp
  found_tmp="$(find "$fixture_tmpdir" -maxdepth 1 -name 'aai-src.*' -type d 2>/dev/null | head -1 || true)"
  [[ -n "$found_tmp" && -d "$found_tmp" ]] \
    || log_fail "TEST-005a: expected a retained aai-src.* \$TMP dir under $fixture_tmpdir, found none"
  [[ -d "$found_tmp/src/.git" ]] \
    || log_fail "TEST-005a: clone must materialize at \$TMP/src (missing $found_tmp/src/.git)"
  [[ -f "$found_tmp/src/.aai/scripts/aai-sync.sh" ]] \
    || log_fail "TEST-005a: cloned aai-sync.sh missing at \$TMP/src/.aai/scripts/aai-sync.sh"
  [[ -f "$target_dir/FIXTURE_SYNC_MARKER" ]] \
    || log_fail "TEST-005a: cloned aai-sync.sh did not execute against TARGET (no marker file)"
  grep -qF "target=$target_dir" "$target_dir/FIXTURE_SYNC_MARKER" \
    || log_fail "TEST-005a: sync marker does not reference the correct TARGET"
  # parent $TMP retained (not the exit-trap's job here since --keep-temp) and
  # owned by the invoking user
  local owner_uid invoker_uid
  # GNU `stat -f` means `--file-system` (succeeds, wrong data) so it must NOT
  # be tried first on Linux; try GNU `stat -c` first, then BSD `stat -f`.
  owner_uid="$(stat -c '%u' "$found_tmp" 2>/dev/null || stat -f '%u' "$found_tmp" 2>/dev/null || true)"
  invoker_uid="$(id -u)"
  [[ -z "$owner_uid" || "$owner_uid" == "$invoker_uid" ]] \
    || log_fail "TEST-005a: retained \$TMP is not owned by the invoking user (owner=$owner_uid, invoker=$invoker_uid)"

  # --- (b) mid-operation failure: an invalid source forces every clone
  #     attempt to fail; assert clean exit 3 and no stray $SRCDIR survives
  #     (per-attempt wipe leaves no partial clone behind). ---
  target_dir="$work_dir/target-b"
  mkdir -p "$target_dir"
  fixture_tmpdir="$work_dir/tmpbase-b"
  mkdir -p "$fixture_tmpdir"

  out="$work_dir/b.out"; err="$work_dir/b.err"
  code=0
  ( cd "$target_dir" && TMPDIR="$fixture_tmpdir" bash "$UPDATE_SH" \
      --repo "file://$work_dir/does-not-exist-fixture" --force --keep-temp ) \
    > "$out" 2> "$err" || code=$?
  [[ "$code" == "3" ]] \
    || log_fail "TEST-005b: expected exit 3 (fetch failure) for an invalid source, got $code (stderr: $(cat "$err"))"

  found_tmp="$(find "$fixture_tmpdir" -maxdepth 1 -name 'aai-src.*' -type d 2>/dev/null | head -1 || true)"
  [[ -n "$found_tmp" && -d "$found_tmp" ]] \
    || log_fail "TEST-005b: retained \$TMP parent should still exist (--keep-temp) after a failed run"
  [[ ! -e "$found_tmp/src" || -z "$(find "$found_tmp/src" -mindepth 1 2>/dev/null)" ]] \
    || log_fail "TEST-005b: \$SRCDIR must be empty/absent after every attempt fails (no stray partial clone)"
  [[ ! -f "$target_dir/FIXTURE_SYNC_MARKER" ]] \
    || log_fail "TEST-005b: sync must NOT have executed on a failed clone"

  rm -rf "$work_dir"
  log_pass "SEAM-1: real clone lands at \$TMP/src, parent retained+owned, sync executes; failed cascade leaves no stray \$SRCDIR (TEST-005)"
}

main() {
  echo "=== $TEST_NAME ==="
  check_deps

  if [[ $# -gt 0 ]]; then
    "$1"
    echo "=== $TEST_NAME: SELECTED TEST PASSED ($1) ==="
    return
  fi

  test_001_clone_target_is_srcdir
  test_002_no_midrun_rm_tmp
  test_003_bash_syntax_check
  test_004_dry_run_happy_path
  test_005_integration_file_fixture_clone

  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}

main "$@"
