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
# CHANGE-0137 (spec-update-doctor-field-report) adds test_006..test_017 —
# the post-update doctor field report: .aai/scripts/update-doctor-report.mjs
# (config-gated doctor spawn + provenance-stamped report + retention) plus the
# thin guarded postambles in both update entrypoints. Those functions carry
# their OWN TEST-xxx ids from that spec's Test Plan, labelled 0137-TEST-001..
# 0137-TEST-012 in log lines to avoid colliding with the SPEC-0052 ids above.
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
UPDATE_PS1="$PROJECT_ROOT/.aai/scripts/aai-update.ps1"
HELPER_MJS="$PROJECT_ROOT/.aai/scripts/update-doctor-report.mjs"
DOCTOR_MJS="$PROJECT_ROOT/.aai/scripts/aai-doctor.mjs"

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

# ===========================================================================
# CHANGE-0137 — post-update doctor field report (spec-update-doctor-field-report)
# ===========================================================================

# Minimal helper-target fixture root: docs/ai only (reports dir is the
# helper's own mkdir -p job — spec edge case).
make_helper_root() {
  mkdir -p "$1/docs/ai"
}

# Stub doctors — tiny node scripts the fixtures write (spec Implementation
# plan). Written as .js (CJS default) so `node <stub> --root .. --json` runs
# them regardless of module type.
write_stub_doctor() {
  local path="$1" kind="$2"
  mkdir -p "$(dirname "$path")"
  case "$kind" in
    clean)
      cat > "$path" <<'STUB'
console.log(JSON.stringify({
  root: "stub", generatedAt: "2026-01-01T00:00:00.000Z",
  categories: [{ id: "CAT-01", name: "Core Files", status: "PASS", reason: "stub" }],
  verdict: "CLEAN", issues: 0, exit: 0,
}, null, 2));
STUB
      ;;
    issues)
      cat > "$path" <<'STUB'
console.log(JSON.stringify({
  root: "stub", generatedAt: "2026-01-01T00:00:00.000Z",
  categories: [
    { id: "CAT-01", name: "Core Files", status: "FAIL", reason: "stub fail" },
    { id: "CAT-05", name: "Knowledge Files", status: "WARN", reason: "stub warn" },
  ],
  verdict: "ISSUES", issues: 2, exit: 1,
}, null, 2));
process.exit(1);
STUB
      ;;
    exit2)
      printf 'console.error("stub: usage error");\nprocess.exit(2);\n' > "$path"
      ;;
    garbage)
      printf 'console.log("this is not json at all");\n' > "$path"
      ;;
    sleep)
      printf 'setTimeout(function () {}, 30000);\n' > "$path"
      ;;
  esac
}

# Runs the helper with rc capture. Args: <workdir> <outfile> <errfile> then
# helper argv. Sets HELPER_RC.
run_helper() {
  local workdir="$1" out="$2" err="$3"
  shift 3
  HELPER_RC=0
  ( cd "$workdir" && node "$HELPER_MJS" "$@" ) > "$out" 2> "$err" || HELPER_RC=$?
}

count_doctor_reports() {
  find "$1/docs/ai/reports" -maxdepth 1 -name 'doctor-*.md' 2>/dev/null | wc -l | tr -d ' '
}

# Fixture source repo for the INTEGRATION arms: its aai-sync.sh installs a
# stub doctor (env-switchable: clean / issues / crash) plus a helper into the
# target — the REAL update-doctor-report.mjs by default, or a broken one when
# $3 == broken (0137-TEST-003 SEAM-2 arm).
build_fixture_doctor_source_repo() {
  local repo_dir="$1" helper_kind="${2:-real}"
  mkdir -p "$repo_dir/.aai/scripts"
  cat > "$repo_dir/.aai/scripts/aai-doctor.mjs" <<'STUB'
const mode = process.env.AAI_FIXTURE_DOCTOR_MODE || 'clean';
if (mode === 'crash') { throw new Error('fixture doctor crash'); }
if (mode === 'issues') {
  console.log(JSON.stringify({
    root: 'stub', generatedAt: '2026-01-01T00:00:00.000Z',
    categories: [
      { id: 'CAT-01', name: 'Core Files', status: 'FAIL', reason: 'stub fail' },
      { id: 'CAT-05', name: 'Knowledge Files', status: 'WARN', reason: 'stub warn' },
    ],
    verdict: 'ISSUES', issues: 2, exit: 1,
  }, null, 2));
  process.exit(1);
}
console.log(JSON.stringify({
  root: 'stub', generatedAt: '2026-01-01T00:00:00.000Z',
  categories: [{ id: 'CAT-01', name: 'Core Files', status: 'PASS', reason: 'stub' }],
  verdict: 'CLEAN', issues: 0, exit: 0,
}, null, 2));
STUB
  if [[ "$helper_kind" == "broken" ]]; then
    printf 'throw new Error("broken fixture helper");\n' \
      > "$repo_dir/.aai/scripts/update-doctor-report.mjs"
  else
    cp "$HELPER_MJS" "$repo_dir/.aai/scripts/update-doctor-report.mjs"
  fi
  cat > "$repo_dir/.aai/scripts/aai-sync.sh" <<'FIXTURE'
#!/usr/bin/env bash
set -euo pipefail
target="${1:?target required}"
src="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p "$target/.aai/scripts" "$target/docs/ai"
cp "$src/.aai/scripts/aai-doctor.mjs" "$target/.aai/scripts/aai-doctor.mjs"
cp "$src/.aai/scripts/update-doctor-report.mjs" "$target/.aai/scripts/update-doctor-report.mjs"
printf 'FIXTURE_SYNC_RAN target=%s\n' "$target" > "$target/FIXTURE_SYNC_MARKER"
FIXTURE
  chmod +x "$repo_dir/.aai/scripts/aai-sync.sh"
  git -C "$repo_dir" init -q -b main
  git -C "$repo_dir" -c user.email="test@example.com" -c user.name="test" add -A
  git -C "$repo_dir" -c user.email="test@example.com" -c user.name="test" \
    commit -q -m "fixture"
}

# Git-initialized fixture TARGET with the vendored .gitignore (SEAM-4).
build_fixture_target() {
  local target_dir="$1"
  mkdir -p "$target_dir/docs/ai/reports"
  cp "$PROJECT_ROOT/.gitignore" "$target_dir/.gitignore"
  touch "$target_dir/docs/ai/reports/.gitkeep"
  git -C "$target_dir" init -q -b main
  git -C "$target_dir" -c user.email="test@example.com" -c user.name="test" add -A
  git -C "$target_dir" -c user.email="test@example.com" -c user.name="test" \
    commit -q -m "target baseline"
}

# Runs a full fixture update. Args: <target> <tmpbase> <out> <err> <repo> [env k=v].
# Sets UPDATE_RC.
run_fixture_update() {
  local target="$1" tmpbase="$2" out="$3" err="$4" repo="$5"
  shift 5
  UPDATE_RC=0
  ( cd "$target" && env "$@" TMPDIR="$tmpbase" bash "$UPDATE_SH" \
      --repo "file://$repo" --force ) > "$out" 2> "$err" || UPDATE_RC=$?
}

# --- 0137-TEST-001 (Spec-AC-01, SEAM-4): full fixture update run ------------

test_006_0137_update_writes_field_report() {
  log_info "Test: full fixture update writes the doctor field report; dry-run never does (0137-TEST-001)..."
  command -v git >/dev/null 2>&1 || { log_skip "0137-TEST-001: git not available"; return 0; }
  command -v node >/dev/null 2>&1 || { log_skip "0137-TEST-001: node not available"; return 0; }

  local work fixture_src target tmpbase out err n report
  work="$(mktemp -d "${TMPDIR:-/tmp}/aai-0137-t001.XXXXXX")"; work="$(cd "$work" && pwd)"
  fixture_src="$work/src-repo"; mkdir -p "$fixture_src"
  build_fixture_doctor_source_repo "$fixture_src" real
  target="$work/target"; mkdir -p "$target"; build_fixture_target "$target"
  tmpbase="$work/tmpbase"; mkdir -p "$tmpbase"
  out="$work/out.log"; err="$work/err.log"

  run_fixture_update "$target" "$tmpbase" "$out" "$err" "$fixture_src"
  [[ "$UPDATE_RC" == "0" ]] \
    || log_fail "0137-TEST-001: update expected exit 0, got $UPDATE_RC (stderr: $(cat "$err"))"
  grep -qF '## Doctor field report' "$out" \
    || log_fail "0137-TEST-001: update output missing the '## Doctor field report' section"
  n=$(grep -c '^DOCTOR CLEAN - full report: docs/ai/reports/doctor-' "$out" || true)
  [[ "$n" == "1" ]] \
    || log_fail "0137-TEST-001: expected exactly 1 DOCTOR CLEAN line naming the report path, got $n (out: $(cat "$out"))"
  report="$(find "$target/docs/ai/reports" -maxdepth 1 -name 'doctor-*.md' | head -1 || true)"
  [[ -n "$report" ]] || log_fail "0137-TEST-001: no report file written under docs/ai/reports"
  basename "$report" | grep -qE '^doctor-[0-9]{8}T[0-9]{6}Z-[a-z0-9-]+\.md$' \
    || log_fail "0137-TEST-001: report name '$(basename "$report")' does not match doctor-UTCSTAMP-tag.md"
  # SEAM-4: the vendored .gitignore keeps the report out of git status.
  local porcelain="$work/porcelain.txt"
  git -C "$target" status --porcelain > "$porcelain" 2>/dev/null || true
  if grep -q 'docs/ai/reports/doctor-' "$porcelain"; then
    log_fail "0137-TEST-001: report appears in git status --porcelain (SEAM-4 violated): $(cat "$porcelain")"
  fi

  # Dry-run arm: never invokes the helper, never creates a report.
  local target2="$work/target2" out2="$work/out2.log"
  mkdir -p "$target2"; build_fixture_target "$target2"
  local rc2=0
  ( cd "$target2" && TMPDIR="$tmpbase" bash "$UPDATE_SH" \
      --repo "file://$fixture_src" --force --dry-run ) > "$out2" 2>&1 || rc2=$?
  [[ "$rc2" == "0" ]] || log_fail "0137-TEST-001: dry-run expected exit 0, got $rc2"
  [[ "$(count_doctor_reports "$target2")" == "0" ]] \
    || log_fail "0137-TEST-001: dry-run must not create a report"
  if grep -qF '## Doctor field report' "$out2"; then
    log_fail "0137-TEST-001: dry-run must not print the Doctor field report section"
  fi

  rm -rf "$work"
  log_pass "Full fixture update writes the report, one DOCTOR CLEAN line, gitignored; dry-run abstains (0137-TEST-001)"
}

# --- 0137-TEST-002 (Spec-AC-01): direct helper failure matrix ---------------

test_007_0137_helper_failure_matrix() {
  log_info "Test: helper failure matrix — missing doctor / exit 2 / non-JSON each yield ONE named SKIP, no report, exit 0 (0137-TEST-002)..."
  command -v node >/dev/null 2>&1 || { log_skip "0137-TEST-002: node not available"; return 0; }
  [[ -f "$HELPER_MJS" ]] || log_fail "0137-TEST-002: helper missing: $HELPER_MJS"

  local work root out err lines
  work="$(mktemp -d "${TMPDIR:-/tmp}/aai-0137-t002.XXXXXX")"; work="$(cd "$work" && pwd)"
  out="$work/out.log"; err="$work/err.log"

  # Arm 1: --doctor points at a missing path.
  root="$work/root1"; make_helper_root "$root"
  run_helper "$work" "$out" "$err" --root "$root" --doctor "$root/does-not-exist.mjs"
  [[ "$HELPER_RC" == "0" ]] || log_fail "0137-TEST-002: missing-doctor arm expected exit 0, got $HELPER_RC"
  lines=$(wc -l < "$out" | tr -d ' ')
  [[ "$lines" == "1" ]] || log_fail "0137-TEST-002: missing-doctor arm expected exactly 1 stdout line, got $lines: $(cat "$out")"
  grep -qF 'DOCTOR-REPORT SKIP doctor script missing - update unaffected' "$out" \
    || log_fail "0137-TEST-002: missing-doctor arm line wrong: $(cat "$out")"
  [[ "$(count_doctor_reports "$root")" == "0" ]] || log_fail "0137-TEST-002: missing-doctor arm wrote a report"

  # Arm 2: doctor exits 2 (usage error).
  root="$work/root2"; make_helper_root "$root"
  write_stub_doctor "$work/stub-exit2.js" exit2
  run_helper "$work" "$out" "$err" --root "$root" --doctor "$work/stub-exit2.js"
  [[ "$HELPER_RC" == "0" ]] || log_fail "0137-TEST-002: exit-2 arm expected exit 0, got $HELPER_RC"
  lines=$(wc -l < "$out" | tr -d ' ')
  [[ "$lines" == "1" ]] || log_fail "0137-TEST-002: exit-2 arm expected exactly 1 stdout line, got $lines: $(cat "$out")"
  grep -qF 'DOCTOR-REPORT SKIP doctor usage error (exit 2) - update unaffected' "$out" \
    || log_fail "0137-TEST-002: exit-2 arm line wrong: $(cat "$out")"
  [[ "$(count_doctor_reports "$root")" == "0" ]] || log_fail "0137-TEST-002: exit-2 arm wrote a report"

  # Arm 3: doctor prints non-JSON.
  root="$work/root3"; make_helper_root "$root"
  write_stub_doctor "$work/stub-garbage.js" garbage
  run_helper "$work" "$out" "$err" --root "$root" --doctor "$work/stub-garbage.js"
  [[ "$HELPER_RC" == "0" ]] || log_fail "0137-TEST-002: garbage arm expected exit 0, got $HELPER_RC"
  lines=$(wc -l < "$out" | tr -d ' ')
  [[ "$lines" == "1" ]] || log_fail "0137-TEST-002: garbage arm expected exactly 1 stdout line, got $lines: $(cat "$out")"
  grep -qF 'DOCTOR-REPORT SKIP doctor output unparseable - update unaffected' "$out" \
    || log_fail "0137-TEST-002: garbage arm line wrong: $(cat "$out")"
  [[ "$(count_doctor_reports "$root")" == "0" ]] || log_fail "0137-TEST-002: garbage arm wrote a report"

  rm -rf "$work"
  log_pass "Helper failure matrix: one named SKIP per arm, no report, exit 0 (0137-TEST-002)"
}

# --- 0137-TEST-003 (Spec-AC-01, SEAM-2): induced-failure update runs --------

test_008_0137_induced_failure_update_runs() {
  log_info "Test: doctor exit 1 still reports ISSUES; crashing doctor and broken helper degrade to ONE SKIP line; update exit unchanged (0137-TEST-003)..."
  command -v git >/dev/null 2>&1 || { log_skip "0137-TEST-003: git not available"; return 0; }
  command -v node >/dev/null 2>&1 || { log_skip "0137-TEST-003: node not available"; return 0; }

  local work fixture_src broken_src target tmpbase out err n
  work="$(mktemp -d "${TMPDIR:-/tmp}/aai-0137-t003.XXXXXX")"; work="$(cd "$work" && pwd)"
  fixture_src="$work/src-repo"; mkdir -p "$fixture_src"
  build_fixture_doctor_source_repo "$fixture_src" real
  tmpbase="$work/tmpbase"; mkdir -p "$tmpbase"

  # Arm 1: doctor exits 1 with ISSUES JSON — report still written, never a SKIP.
  target="$work/target-issues"; mkdir -p "$target"; build_fixture_target "$target"
  out="$work/issues.out"; err="$work/issues.err"
  run_fixture_update "$target" "$tmpbase" "$out" "$err" "$fixture_src" AAI_FIXTURE_DOCTOR_MODE=issues
  [[ "$UPDATE_RC" == "0" ]] \
    || log_fail "0137-TEST-003: issues arm expected update exit 0, got $UPDATE_RC (stderr: $(cat "$err"))"
  n=$(grep -c '^DOCTOR ISSUES(2) - full report: docs/ai/reports/doctor-' "$out" || true)
  [[ "$n" == "1" ]] || log_fail "0137-TEST-003: issues arm expected 1 DOCTOR ISSUES(2) line, got $n: $(cat "$out")"
  if grep -q 'DOCTOR-REPORT SKIP' "$out"; then
    log_fail "0137-TEST-003: issues arm must never print a SKIP line"
  fi
  [[ "$(count_doctor_reports "$target")" == "1" ]] \
    || log_fail "0137-TEST-003: issues arm must still write the report (doctor exit 1 is not a failure of this step)"

  # Arm 2: crashing doctor — one named SKIP, update still exits 0.
  target="$work/target-crash"; mkdir -p "$target"; build_fixture_target "$target"
  out="$work/crash.out"; err="$work/crash.err"
  run_fixture_update "$target" "$tmpbase" "$out" "$err" "$fixture_src" AAI_FIXTURE_DOCTOR_MODE=crash
  [[ "$UPDATE_RC" == "0" ]] \
    || log_fail "0137-TEST-003: crash arm expected update exit 0, got $UPDATE_RC (stderr: $(cat "$err"))"
  n=$(grep -c '^DOCTOR-REPORT SKIP doctor output unparseable - update unaffected$' "$out" || true)
  [[ "$n" == "1" ]] || log_fail "0137-TEST-003: crash arm expected exactly 1 named SKIP line, got $n: $(cat "$out")"
  [[ "$(count_doctor_reports "$target")" == "0" ]] || log_fail "0137-TEST-003: crash arm must not write a report"

  # Arm 3 (SEAM-2): helper file replaced by one that throws — the WRAPPER's own
  # guard prints the SKIP; the update's exit code is byte-identical to arm 1's.
  broken_src="$work/src-repo-broken"; mkdir -p "$broken_src"
  build_fixture_doctor_source_repo "$broken_src" broken
  target="$work/target-broken"; mkdir -p "$target"; build_fixture_target "$target"
  out="$work/broken.out"; err="$work/broken.err"
  run_fixture_update "$target" "$tmpbase" "$out" "$err" "$broken_src"
  [[ "$UPDATE_RC" == "0" ]] \
    || log_fail "0137-TEST-003: broken-helper arm expected update exit 0, got $UPDATE_RC (stderr: $(cat "$err"))"
  n=$(grep -c '^DOCTOR-REPORT SKIP helper crashed - update unaffected$' "$out" || true)
  [[ "$n" == "1" ]] || log_fail "0137-TEST-003: broken-helper arm expected exactly 1 wrapper SKIP line, got $n: $(cat "$out")"
  [[ "$(count_doctor_reports "$target")" == "0" ]] || log_fail "0137-TEST-003: broken-helper arm must not write a report"

  rm -rf "$work"
  log_pass "Induced failures: ISSUES report on exit 1, one named SKIP on crash/broken helper, update exit unchanged (0137-TEST-003)"
}

# --- 0137-TEST-004 (Spec-AC-02, SEAM-3): config matrix ----------------------

test_009_0137_config_matrix() {
  log_info "Test: post_update_doctor config matrix — absent==on, off named, unknown warns+on, column-0 discipline, update-check seam (0137-TEST-004)..."
  command -v node >/dev/null 2>&1 || { log_skip "0137-TEST-004: node not available"; return 0; }
  [[ -f "$HELPER_MJS" ]] || log_fail "0137-TEST-004: helper missing: $HELPER_MJS"

  local work root out err stub cfg
  work="$(mktemp -d "${TMPDIR:-/tmp}/aai-0137-t004.XXXXXX")"; work="$(cd "$work" && pwd)"
  out="$work/out.log"; err="$work/err.log"
  stub="$work/stub-clean.js"; write_stub_doctor "$stub" clean

  # Arm 1: absent config — default on, doctor runs, report written.
  root="$work/root-absent"; make_helper_root "$root"
  run_helper "$work" "$out" "$err" --root "$root" --doctor "$stub"
  [[ "$HELPER_RC" == "0" ]] || log_fail "0137-TEST-004: absent-config arm expected exit 0, got $HELPER_RC"
  grep -q '^DOCTOR CLEAN - full report: ' "$out" || log_fail "0137-TEST-004: absent-config arm must run the doctor: $(cat "$out")"
  [[ "$(count_doctor_reports "$root")" == "1" ]] || log_fail "0137-TEST-004: absent-config arm must write the report"

  # Arm 2: off — the named disabled line, no report.
  root="$work/root-off"; make_helper_root "$root"
  cfg="$root/docs/ai/update-config.yaml"
  printf 'post_update_doctor: off\n' > "$cfg"
  run_helper "$work" "$out" "$err" --root "$root" --doctor "$stub"
  [[ "$HELPER_RC" == "0" ]] || log_fail "0137-TEST-004: off arm expected exit 0, got $HELPER_RC"
  [[ "$(cat "$out")" == "DOCTOR-REPORT SKIP disabled by config (post_update_doctor: off)" ]] \
    || log_fail "0137-TEST-004: off arm line wrong: $(cat "$out")"
  [[ "$(count_doctor_reports "$root")" == "0" ]] || log_fail "0137-TEST-004: off arm must not write a report"

  # Arm 3: unknown value — stderr warning names it, behaves as on.
  root="$work/root-unknown"; make_helper_root "$root"
  printf 'post_update_doctor: maybe\n' > "$root/docs/ai/update-config.yaml"
  run_helper "$work" "$out" "$err" --root "$root" --doctor "$stub"
  [[ "$HELPER_RC" == "0" ]] || log_fail "0137-TEST-004: unknown arm expected exit 0, got $HELPER_RC"
  grep -q 'maybe' "$err" || log_fail "0137-TEST-004: unknown arm must warn on stderr naming the bad value: $(cat "$err")"
  [[ "$(count_doctor_reports "$root")" == "1" ]] || log_fail "0137-TEST-004: unknown arm must behave as on (report written)"

  # Arm 4: indented and commented keys are never a dial (column-0 discipline).
  root="$work/root-col0"; make_helper_root "$root"
  printf '  post_update_doctor: off\n# post_update_doctor: off\n' > "$root/docs/ai/update-config.yaml"
  run_helper "$work" "$out" "$err" --root "$root" --doctor "$stub"
  [[ "$HELPER_RC" == "0" ]] || log_fail "0137-TEST-004: column-0 arm expected exit 0, got $HELPER_RC"
  [[ "$(count_doctor_reports "$root")" == "1" ]] \
    || log_fail "0137-TEST-004: indented/commented key must be ignored (doctor must run)"

  # Arm 5 (SEAM-3): a combined file still resolves mode/throttle through the
  # UNCHANGED update-check parser. Throttle fast path (fresh cache + --now)
  # keeps this arm zero-network and proves throttle_hours parsed unchanged.
  local combined="$work/combined.yaml" cache="$work/cache.json" json
  printf 'mode: notify\nthrottle_hours: 24\npost_update_doctor: off\n' > "$combined"
  printf '{"last_check_utc":"2026-07-20T10:00:00Z"}' > "$cache"
  local rc=0
  json="$( cd "$work" && node "$PROJECT_ROOT/.aai/scripts/update-check.mjs" \
      --config "$combined" --cache "$cache" --now "2026-07-20T11:00:00Z" --json 2>"$err" )" || rc=$?
  [[ "$rc" == "0" ]] || log_fail "0137-TEST-004: update-check over the combined file expected exit 0, got $rc ($(cat "$err"))"
  grep -qF '"effective_mode":"notify"' <<<"$json" \
    || log_fail "0137-TEST-004: update-check must still resolve mode notify over the combined file: $json"
  grep -qF '"throttled":true' <<<"$json" \
    || log_fail "0137-TEST-004: update-check must still resolve throttle_hours (throttled fast path): $json"
  # And the helper honors the same combined file's off dial via --config.
  root="$work/root-combined"; make_helper_root "$root"
  run_helper "$work" "$out" "$err" --root "$root" --config "$combined" --doctor "$stub"
  [[ "$(cat "$out")" == "DOCTOR-REPORT SKIP disabled by config (post_update_doctor: off)" ]] \
    || log_fail "0137-TEST-004: helper over the combined file must honor off: $(cat "$out")"

  rm -rf "$work"
  log_pass "Config matrix: absent==on, off named, unknown warns+runs, column-0 only, update-check parser unaffected (0137-TEST-004)"
}

# --- 0137-TEST-005 (Spec-AC-03): timeout bound + zero-network scan ----------

test_010_0137_timeout_and_zero_network() {
  log_info "Test: sleeping doctor under --timeout-ms 1000 -> bounded named timeout SKIP; no network/LLM primitive in helper or postambles (0137-TEST-005)..."
  command -v node >/dev/null 2>&1 || { log_skip "0137-TEST-005: node not available"; return 0; }
  [[ -f "$HELPER_MJS" ]] || log_fail "0137-TEST-005: helper missing: $HELPER_MJS"

  local work root out err start end elapsed
  work="$(mktemp -d "${TMPDIR:-/tmp}/aai-0137-t005.XXXXXX")"; work="$(cd "$work" && pwd)"
  out="$work/out.log"; err="$work/err.log"
  root="$work/root"; make_helper_root "$root"
  write_stub_doctor "$work/stub-sleep.js" sleep

  start=$(date +%s)
  run_helper "$work" "$out" "$err" --root "$root" --doctor "$work/stub-sleep.js" --timeout-ms 1000
  end=$(date +%s)
  elapsed=$(( end - start ))
  [[ "$HELPER_RC" == "0" ]] || log_fail "0137-TEST-005: timeout arm expected exit 0, got $HELPER_RC"
  [[ "$elapsed" -lt 15 ]] \
    || log_fail "0137-TEST-005: helper took ${elapsed}s — not bounded by the 1000ms timeout plus grace"
  grep -qF 'DOCTOR-REPORT SKIP doctor timed out after 1s - update unaffected' "$out" \
    || log_fail "0137-TEST-005: timeout arm line wrong: $(cat "$out")"
  [[ "$(count_doctor_reports "$root")" == "0" ]] || log_fail "0137-TEST-005: timeout arm must not write a report"

  # Zero-network pin: the helper and BOTH postamble regions carry no network
  # or LLM primitive from the pinned token set, and the helper imports only
  # node built-ins.
  local netre="Invoke-WebRequest|Invoke-RestMethod|curl |wget |git fetch|git ls-remote|git clone|fetch\(|node:https?\b|from ['\"]https?['\"]"
  if grep -qE "$netre" "$HELPER_MJS"; then
    log_fail "0137-TEST-005: helper references a network primitive: $(grep -nE "$netre" "$HELPER_MJS" | head -3)"
  fi
  if grep -E "^import .* from" "$HELPER_MJS" | grep -vq "from 'node:"; then
    log_fail "0137-TEST-005: helper imports a non-builtin module: $(grep -E '^import ' "$HELPER_MJS")"
  fi
  local sh_post ps1_post
  sh_post="$work/sh-postamble.txt"; ps1_post="$work/ps1-postamble.txt"
  awk '/Doctor field report/{f=1} /^echo "## Next"$/{f=0} f' "$UPDATE_SH" > "$sh_post"
  awk '/Doctor field report/{f=1} /Write-Host "## Next"/{f=0} f' "$UPDATE_PS1" > "$ps1_post"
  [[ -s "$sh_post" ]] || log_fail "0137-TEST-005: sh postamble section not found in aai-update.sh"
  [[ -s "$ps1_post" ]] || log_fail "0137-TEST-005: ps1 postamble section not found in aai-update.ps1"
  if grep -qE "$netre" "$sh_post" "$ps1_post"; then
    log_fail "0137-TEST-005: a postamble references a network primitive: $(grep -nE "$netre" "$sh_post" "$ps1_post" | head -3)"
  fi

  rm -rf "$work"
  log_pass "Timeout bounded with the named SKIP; helper + postambles zero-network, builtin-only imports (0137-TEST-005)"
}

# --- 0137-TEST-006 (Spec-AC-03): SKIP passthrough byte-verbatim -------------

test_011_0137_skip_passthrough_verbatim() {
  log_info "Test: doctor JSON with CAT-14/CAT-15 SKIP lands byte-verbatim in the report's fenced block (0137-TEST-006)..."
  command -v node >/dev/null 2>&1 || { log_skip "0137-TEST-006: node not available"; return 0; }
  [[ -f "$HELPER_MJS" ]] || log_fail "0137-TEST-006: helper missing: $HELPER_MJS"

  local work root out err doc stub report extracted
  work="$(mktemp -d "${TMPDIR:-/tmp}/aai-0137-t006.XXXXXX")"; work="$(cd "$work" && pwd)"
  out="$work/out.log"; err="$work/err.log"
  root="$work/root"; make_helper_root "$root"

  # The exact document the stub will print (the non-Windows CAT-14/15 shape).
  doc="$work/doc.json"
  node -e '
    const fs = require("fs");
    fs.writeFileSync(process.argv[1], JSON.stringify({
      root: "stub", generatedAt: "2026-01-01T00:00:00.000Z",
      categories: [
        { id: "CAT-01", name: "Core Files", status: "PASS", reason: "stub" },
        { id: "CAT-14", name: "Windows Self-Test", status: "SKIP", reason: "not running on a Windows host" },
        { id: "CAT-15", name: "Windows Environment", status: "SKIP", reason: "not running on a Windows host" },
      ],
      verdict: "CLEAN", issues: 0, exit: 0,
    }, null, 2) + "\n");
  ' "$doc"
  stub="$work/stub-passthrough.js"
  printf 'process.stdout.write(require("fs").readFileSync(%s, "utf8"));\n' "\"$doc\"" > "$stub"

  run_helper "$work" "$out" "$err" --root "$root" --doctor "$stub"
  [[ "$HELPER_RC" == "0" ]] || log_fail "0137-TEST-006: expected exit 0, got $HELPER_RC ($(cat "$err"))"
  report="$(find "$root/docs/ai/reports" -maxdepth 1 -name 'doctor-*.md' | head -1 || true)"
  [[ -n "$report" ]] || log_fail "0137-TEST-006: no report written"
  extracted="$work/extracted.json"
  awk '/^```json$/{f=1;next} /^```$/{f=0} f' "$report" > "$extracted"
  cmp -s "$doc" "$extracted" \
    || log_fail "0137-TEST-006: fenced JSON block is not byte-identical to the doctor stdout (diff: $(diff "$doc" "$extracted" | head -5))"
  grep -qF '"status": "SKIP"' "$extracted" || log_fail "0137-TEST-006: SKIP categories missing from the embedded JSON"

  rm -rf "$work"
  log_pass "SKIP categories pass through byte-verbatim inside the fenced block (0137-TEST-006)"
}

# --- 0137-TEST-007 (Spec-AC-04): provenance matrix ---------------------------

test_012_0137_provenance_matrix() {
  log_info "Test: provenance header — pin values, AAI_VERSION fallback, literal UNKNOWN, timestamp/platform/machine always present (0137-TEST-007)..."
  command -v node >/dev/null 2>&1 || { log_skip "0137-TEST-007: node not available"; return 0; }
  [[ -f "$HELPER_MJS" ]] || log_fail "0137-TEST-007: helper missing: $HELPER_MJS"

  local work out err stub root report
  work="$(mktemp -d "${TMPDIR:-/tmp}/aai-0137-t007.XXXXXX")"; work="$(cd "$work" && pwd)"
  out="$work/out.log"; err="$work/err.log"
  stub="$work/stub-clean.js"; write_stub_doctor "$stub" clean

  # Arm 1: stamped pin wins.
  root="$work/root-pin"; make_helper_root "$root"
  mkdir -p "$root/.aai/system"
  cat > "$root/.aai/system/AAI_PIN.md" <<'PIN'
# AAI Pin

- Source path: /tmp/somewhere
- Template version: v9.9.9-test
- Template commit: abc1234def
- Synced at (UTC): 2026-08-13T00:00:00Z
PIN
  run_helper "$work" "$out" "$err" --root "$root" --doctor "$stub"
  [[ "$HELPER_RC" == "0" ]] || log_fail "0137-TEST-007: pin arm expected exit 0, got $HELPER_RC"
  report="$(find "$root/docs/ai/reports" -maxdepth 1 -name 'doctor-*.md' | head -1 || true)"
  [[ -n "$report" ]] || log_fail "0137-TEST-007: pin arm wrote no report"
  grep -qF -- '- AAI version: v9.9.9-test' "$report" \
    || log_fail "0137-TEST-007: pin arm must carry the pin's Template version (got: $(grep -F 'AAI version' "$report" || true))"
  grep -qF -- '- AAI commit: abc1234def' "$report" \
    || log_fail "0137-TEST-007: pin arm must carry the pin's Template commit"

  # Arm 2: no pin, AAI_VERSION.md fallback.
  root="$work/root-fallback"; make_helper_root "$root"
  printf '# AAI Version\n\n- Version: v8.8.8-fallback\n' > "$root/docs/ai/AAI_VERSION.md"
  run_helper "$work" "$out" "$err" --root "$root" --doctor "$stub"
  report="$(find "$root/docs/ai/reports" -maxdepth 1 -name 'doctor-*.md' | head -1 || true)"
  [[ -n "$report" ]] || log_fail "0137-TEST-007: fallback arm wrote no report"
  grep -qF -- '- AAI version: v8.8.8-fallback' "$report" \
    || log_fail "0137-TEST-007: fallback arm must carry AAI_VERSION.md's Version value"
  grep -qF -- '- AAI commit: UNKNOWN' "$report" \
    || log_fail "0137-TEST-007: fallback arm has no pin commit — must say UNKNOWN"

  # Arm 3: neither — the literal UNKNOWN, never invented.
  root="$work/root-unknown"; make_helper_root "$root"
  run_helper "$work" "$out" "$err" --root "$root" --doctor "$stub"
  report="$(find "$root/docs/ai/reports" -maxdepth 1 -name 'doctor-*.md' | head -1 || true)"
  [[ -n "$report" ]] || log_fail "0137-TEST-007: unknown arm wrote no report"
  grep -qF -- '- AAI version: UNKNOWN' "$report" \
    || log_fail "0137-TEST-007: unknown arm must say the literal UNKNOWN"

  # Every report: Generated at (UTC) ISO 8601, Platform with node version,
  # sanitized Machine tag.
  grep -qE -- '^- Generated at \(UTC\): [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}' "$report" \
    || log_fail "0137-TEST-007: Generated at (UTC) line missing/not ISO 8601"
  local nodever
  nodever="$(node --version)"
  grep -qF -- "node $nodever" "$report" \
    || log_fail "0137-TEST-007: Platform line must carry the node version ($nodever)"
  grep -qE -- '^- Machine: [a-z0-9-]+$' "$report" \
    || log_fail "0137-TEST-007: Machine line missing or not sanitized to [a-z0-9-]"
  grep -qE -- '^- Doctor exit: 0 ' "$report" \
    || log_fail "0137-TEST-007: Doctor exit line missing"

  rm -rf "$work"
  log_pass "Provenance: pin wins, AAI_VERSION falls back, UNKNOWN never invented; timestamp/platform/machine present (0137-TEST-007)"
}

# --- 0137-TEST-008 (Spec-AC-04): retention cap, foreign files untouched ------

test_013_0137_retention_cap() {
  log_info "Test: 12 pre-seeded doctor reports + 1 new -> exactly 10 newest remain; sync-conflicts + validation files untouched (0137-TEST-008)..."
  command -v node >/dev/null 2>&1 || { log_skip "0137-TEST-008: node not available"; return 0; }
  [[ -f "$HELPER_MJS" ]] || log_fail "0137-TEST-008: helper missing: $HELPER_MJS"

  local work root out err stub i n
  work="$(mktemp -d "${TMPDIR:-/tmp}/aai-0137-t008.XXXXXX")"; work="$(cd "$work" && pwd)"
  out="$work/out.log"; err="$work/err.log"
  root="$work/root"; make_helper_root "$root"
  mkdir -p "$root/docs/ai/reports"
  stub="$work/stub-clean.js"; write_stub_doctor "$stub" clean

  # 12 old doctor-shape files (name-sortable timestamps, all older than now).
  for i in 01 02 03 04 05 06 07 08 09 10 11 12; do
    printf 'old %s\n' "$i" > "$root/docs/ai/reports/doctor-202501${i}T000000Z-oldhost.md"
  done
  printf 'conflict advisory\n' > "$root/docs/ai/reports/sync-conflicts-20250101T000000Z.md"
  printf 'validation report\n' > "$root/docs/ai/reports/validation-CHANGE-0001-20250101T000000Z.md"

  run_helper "$work" "$out" "$err" --root "$root" --doctor "$stub"
  [[ "$HELPER_RC" == "0" ]] || log_fail "0137-TEST-008: expected exit 0, got $HELPER_RC ($(cat "$err"))"

  n="$(count_doctor_reports "$root")"
  [[ "$n" == "10" ]] || log_fail "0137-TEST-008: expected exactly 10 doctor-shape files after the run, got $n"
  # The newest survive: the just-written one plus the highest-stamped seeds;
  # the 3 oldest seeds are gone.
  [[ ! -f "$root/docs/ai/reports/doctor-20250101T000000Z-oldhost.md" ]] \
    || log_fail "0137-TEST-008: oldest seed must be pruned"
  [[ ! -f "$root/docs/ai/reports/doctor-20250103T000000Z-oldhost.md" ]] \
    || log_fail "0137-TEST-008: third-oldest seed must be pruned"
  [[ -f "$root/docs/ai/reports/doctor-20250112T000000Z-oldhost.md" ]] \
    || log_fail "0137-TEST-008: newest seed must survive"
  # Foreign name shapes are untouchable by construction.
  [[ -f "$root/docs/ai/reports/sync-conflicts-20250101T000000Z.md" ]] \
    || log_fail "0137-TEST-008: sync-conflicts file must be untouched"
  [[ -f "$root/docs/ai/reports/validation-CHANGE-0001-20250101T000000Z.md" ]] \
    || log_fail "0137-TEST-008: validation file must be untouched"

  rm -rf "$work"
  log_pass "Retention: cap 10 on the doctor shape only, foreign report files untouched (0137-TEST-008)"
}

# --- 0137-TEST-009 (Spec-AC-01): ps1 parity structural pin -------------------

test_014_0137_ps1_parity_structural() {
  log_info "Test: ps1 postamble structural parity — same helper, try/catch, SKIP fallback, ASCII-only; sh invocation or-guarded (0137-TEST-009)..."

  [[ -f "$UPDATE_PS1" ]] || log_fail "0137-TEST-009: aai-update.ps1 not found"

  grep -qF '## Doctor field report' "$UPDATE_PS1" \
    || log_fail "0137-TEST-009: ps1 missing the Doctor field report section"
  grep -qF 'update-doctor-report.mjs' "$UPDATE_PS1" \
    || log_fail "0137-TEST-009: ps1 does not invoke the ONE helper (update-doctor-report.mjs)"
  grep -qF 'DOCTOR-REPORT SKIP' "$UPDATE_PS1" \
    || log_fail "0137-TEST-009: ps1 missing the DOCTOR-REPORT SKIP fallback string"

  local work ps1_post
  work="$(mktemp -d "${TMPDIR:-/tmp}/aai-0137-t009.XXXXXX")"
  ps1_post="$work/ps1-postamble.txt"
  awk '/Doctor field report/{f=1} /Write-Host "## Next"/{f=0} f' "$UPDATE_PS1" > "$ps1_post"
  [[ -s "$ps1_post" ]] || log_fail "0137-TEST-009: could not extract the ps1 postamble region"
  grep -q 'try {' "$ps1_post" || log_fail "0137-TEST-009: ps1 postamble not try-wrapped"
  grep -q '} catch' "$ps1_post" || log_fail "0137-TEST-009: ps1 postamble has no catch arm"
  # ASCII-only postamble bytes (0136 field lesson: 5.1 BOM-less ANSI read).
  if tr -d '\n\r\t' < "$ps1_post" | LC_ALL=C grep -q '[^ -~]'; then
    log_fail "0137-TEST-009: ps1 postamble carries non-ASCII bytes"
  fi
  # sh arm: helper invocation or-guarded so set -e cannot propagate a crash.
  grep -qF 'update-doctor-report.mjs" --root "$TARGET" || echo "DOCTOR-REPORT SKIP' "$UPDATE_SH" \
    || log_fail "0137-TEST-009: sh helper invocation is not or-guarded with the SKIP fallback"

  rm -rf "$work"
  log_pass "ps1 postamble parity: one helper, try/catch, ASCII-only; sh or-guarded (0137-TEST-009)"
}

# --- 0137-TEST-010 (Spec-AC-04): documentation pins --------------------------

test_015_0137_documentation_pins() {
  log_info "Test: USER_GUIDE names the field report + attach loop; product docs exist and point; CHANGELOG carries the unreleased entry (0137-TEST-010)..."

  local ug="$PROJECT_ROOT/docs/USER_GUIDE.md"
  local pd="$PROJECT_ROOT/docs/product/aai-update.md"
  local dd="$PROJECT_ROOT/docs/product/aai-doctor.md"
  local cl="$PROJECT_ROOT/CHANGELOG.md"

  grep -qi 'doctor field report' "$ug" \
    || log_fail "0137-TEST-010: docs/USER_GUIDE.md does not name the doctor field report"
  grep -qiE 'attach.*(issue|filing)' "$ug" \
    || log_fail "0137-TEST-010: docs/USER_GUIDE.md does not state the attach-when-filing-an-issue loop"

  [[ -f "$pd" ]] || log_fail "0137-TEST-010: docs/product/aai-update.md does not exist"
  grep -q '^capability: aai-update$' "$pd" \
    || log_fail "0137-TEST-010: aai-update.md frontmatter capability is not aai-update"
  local section
  for section in "What it does" "How to use it" "Data model" "Interfaces and contracts" "Limits and non-goals"; do
    grep -qF "## $section" "$pd" \
      || log_fail "0137-TEST-010: aai-update.md missing required section: $section"
  done
  if grep -qE '<(capability slug|2-6 sentences|Commands / UI paths)' "$pd"; then
    log_fail "0137-TEST-010: aai-update.md still carries template placeholders"
  fi

  grep -qi 'field report' "$dd" \
    || log_fail "0137-TEST-010: docs/product/aai-doctor.md does not point at the field report"

  grep -qE '^## \[unreleased\] .*CHANGE-0137' "$cl" \
    || log_fail "0137-TEST-010: CHANGELOG.md has no unreleased heading entry for CHANGE-0137"

  log_pass "Documentation pins: USER_GUIDE loop, product docs, doctor pointer, CHANGELOG entry (0137-TEST-010)"
}

# --- 0137-TEST-011 (Spec-AC-05): governance set ------------------------------

test_016_0137_governance_set() {
  log_info "Test: registration checker clean; suite-map + PROFILES + prompt-diet ledger trued up (0137-TEST-011)..."
  command -v node >/dev/null 2>&1 || { log_skip "0137-TEST-011: node not available"; return 0; }

  local rc=0
  ( cd "$PROJECT_ROOT" && node .aai/scripts/check-test-registration.mjs ) >/dev/null 2>&1 || rc=$?
  [[ "$rc" == "0" ]] || log_fail "0137-TEST-011: check-test-registration.mjs reports orphans (exit $rc)"

  # suite-map: the aai-update row names the helper (selection stays truthful).
  awk '/^  aai-update:$/{f=1;next} /^  [a-z]/{f=0} f' "$PROJECT_ROOT/tests/skills/suite-map.yaml" \
    | grep -qF '.aai/scripts/update-doctor-report.mjs' \
    || log_fail "0137-TEST-011: suite-map.yaml aai-update row does not name update-doctor-report.mjs"

  # PROFILES: the helper classified exactly once, under core.
  local n_total n_core
  n_total=$(grep -cF -- '- .aai/scripts/update-doctor-report.mjs' "$PROJECT_ROOT/.aai/system/PROFILES.yaml" || true)
  [[ "$n_total" == "1" ]] \
    || log_fail "0137-TEST-011: PROFILES.yaml must list the helper exactly once, got $n_total"
  n_core=$(awk '/^core:$/{f=1;next} /^extended:$/{f=0} f' "$PROJECT_ROOT/.aai/system/PROFILES.yaml" \
    | grep -cF -- '- .aai/scripts/update-doctor-report.mjs' || true)
  [[ "$n_core" == "1" ]] \
    || log_fail "0137-TEST-011: PROFILES.yaml helper entry must sit under core:, got $n_core there"

  # Prompt-diet ledger: one entry for the SKILL_UPDATE relay clause, and the
  # TEST-012 checkpoint bumped off the pre-change -7210 pin.
  grep -q 'update-doctor-field-report' "$PROJECT_ROOT/tests/skills/lib/prompt-diet-ledger.sh" \
    || log_fail "0137-TEST-011: prompt-diet ledger carries no update-doctor-field-report entry"
  if grep -qE 'want -7210\)' "$PROJECT_ROOT/tests/skills/test-aai-prompt-diet.sh"; then
    log_fail "0137-TEST-011: test-aai-prompt-diet.sh TEST-012 checkpoint still pins the pre-change -7210"
  fi

  log_pass "Governance set: registration clean, suite-map + PROFILES + ledger trued up (0137-TEST-011)"
}

# --- 0137-TEST-012 (Spec-AC-03, SEAM-1): real doctor engine crossing ---------

test_017_0137_real_engine_crossing() {
  log_info "Test: helper over the REAL vendored aai-doctor.mjs — JSON parses, verdict matches the line, CAT-01..CAT-16 present (0137-TEST-012)..."
  command -v node >/dev/null 2>&1 || { log_skip "0137-TEST-012: node not available"; return 0; }
  [[ -f "$HELPER_MJS" ]] || log_fail "0137-TEST-012: helper missing: $HELPER_MJS"
  [[ -f "$DOCTOR_MJS" ]] || log_fail "0137-TEST-012: vendored doctor missing: $DOCTOR_MJS"

  local work root out err report extracted line rc
  work="$(mktemp -d "${TMPDIR:-/tmp}/aai-0137-t012.XXXXXX")"; work="$(cd "$work" && pwd)"
  out="$work/out.log"; err="$work/err.log"
  root="$work/root"; make_helper_root "$root"
  # Minimal non-git fixture root: the real doctor degrades per its own
  # contract (CAT-08 SKIP, most categories WARN/FAIL) — that IS the crossing.
  printf '# fixture\n' > "$root/README.md"

  run_helper "$work" "$out" "$err" --root "$root" --doctor "$DOCTOR_MJS"
  [[ "$HELPER_RC" == "0" ]] || log_fail "0137-TEST-012: expected helper exit 0, got $HELPER_RC ($(cat "$err"))"
  report="$(find "$root/docs/ai/reports" -maxdepth 1 -name 'doctor-*.md' | head -1 || true)"
  [[ -n "$report" ]] || log_fail "0137-TEST-012: no report written from the real engine"
  extracted="$work/extracted.json"
  awk '/^```json$/{f=1;next} /^```$/{f=0} f' "$report" > "$extracted"
  line="$(head -1 "$out")"

  rc=0
  node -e '
    const fs = require("fs");
    const doc = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const line = process.argv[2];
    const ids = (doc.categories || []).map((c) => c.id);
    for (let i = 1; i <= 16; i++) {
      const id = "CAT-" + String(i).padStart(2, "0");
      if (!ids.includes(id)) { console.error("missing " + id); process.exit(1); }
    }
    const tok = doc.verdict === "CLEAN" ? "DOCTOR CLEAN" : `DOCTOR ISSUES(${doc.issues})`;
    if (!line.startsWith(tok)) {
      console.error(`verdict token mismatch: line "${line}" vs JSON ${tok}`);
      process.exit(1);
    }
    if (process.platform !== "win32") {
      for (const id of ["CAT-14", "CAT-15"]) {
        const c = doc.categories.find((x) => x.id === id);
        if (!c || c.status !== "SKIP") {
          console.error(`${id} must be honestly SKIPped on a POSIX host, got ${c && c.status}`);
          process.exit(1);
        }
      }
    }
  ' "$extracted" "$line" 2> "$work/node-err.log" || rc=$?
  [[ "$rc" == "0" ]] \
    || log_fail "0137-TEST-012: real-engine JSON/verdict assertions failed: $(cat "$work/node-err.log")"

  rm -rf "$work"
  log_pass "Real engine crossing: report JSON parses, CAT-01..CAT-16 present, verdict matches the emitted line (0137-TEST-012)"
}

# ===========================================================================
# CHANGE-0138 — doctor/config honesty batch (spec-doctor-honesty-batch).
# BOM parity (Spec-AC-04), unreadable-config + prune-failure honesty
# (Spec-AC-05), product-doc/CHANGELOG pins (Spec-AC-06). Log lines labelled
# 0138-TEST-xxx after that spec's Test Plan ids.
# ===========================================================================

# --- 0138-TEST-004 (Spec-AC-04): BOM behavioral pin, helper side -------------
test_018_0138_bom_config_helper() {
  log_info "Test: EF BB BF + first-line post_update_doctor: off is honored — exact disabled line, no report, one stdout line, exit 0 (0138-TEST-004)..."
  command -v node >/dev/null 2>&1 || { log_skip "0138-TEST-004: node not available"; return 0; }
  [[ -f "$HELPER_MJS" ]] || log_fail "0138-TEST-004: helper missing: $HELPER_MJS"

  local work root out err stub lines
  work="$(mktemp -d "${TMPDIR:-/tmp}/aai-0138-t004.XXXXXX")"; work="$(cd "$work" && pwd)"
  out="$work/out.log"; err="$work/err.log"
  stub="$work/stub-clean.js"; write_stub_doctor "$stub" clean

  # Arm 1: UTF-8 BOM immediately followed by the column-0 key on line one.
  root="$work/root-bom"; make_helper_root "$root"
  printf '\357\273\277post_update_doctor: off\n' > "$root/docs/ai/update-config.yaml"
  run_helper "$work" "$out" "$err" --root "$root" --doctor "$stub"
  [[ "$HELPER_RC" == "0" ]] || log_fail "0138-TEST-004: BOM arm expected exit 0, got $HELPER_RC"
  lines=$(wc -l < "$out" | tr -d ' ')
  [[ "$lines" == "1" ]] || log_fail "0138-TEST-004: BOM arm expected exactly 1 stdout line, got $lines: $(cat "$out")"
  [[ "$(cat "$out")" == "DOCTOR-REPORT SKIP disabled by config (post_update_doctor: off)" ]] \
    || log_fail "0138-TEST-004: BOM must not hide the first-line off dial (got: $(cat "$out"))"
  [[ "$(count_doctor_reports "$root")" == "0" ]] \
    || log_fail "0138-TEST-004: BOM arm must not write a report (dial is off)"

  # Arm 2 (negative control): a BOM byte sequence on a NON-first line is
  # content (ZWNBSP), not a BOM — only index 0 is stripped, exactly once, so
  # the key stays hidden and the run behaves as on.
  root="$work/root-zwnbsp"; make_helper_root "$root"
  printf '# leading comment\n\357\273\277post_update_doctor: off\n' > "$root/docs/ai/update-config.yaml"
  run_helper "$work" "$out" "$err" --root "$root" --doctor "$stub"
  [[ "$HELPER_RC" == "0" ]] || log_fail "0138-TEST-004: ZWNBSP arm expected exit 0, got $HELPER_RC"
  lines=$(wc -l < "$out" | tr -d ' ')
  [[ "$lines" == "1" ]] || log_fail "0138-TEST-004: ZWNBSP arm expected exactly 1 stdout line, got $lines: $(cat "$out")"
  [[ "$(count_doctor_reports "$root")" == "1" ]] \
    || log_fail "0138-TEST-004: a mid-file ZWNBSP-prefixed key must NOT act as a dial (doctor must run)"

  rm -rf "$work"
  log_pass "BOM+off honored on line one; mid-file ZWNBSP is content; one stdout line in every arm (0138-TEST-004)"
}

# --- 0138-TEST-005, structural half (Spec-AC-04): twin-identical strip pin ---
test_019_0138_bom_twin_structural_pin() {
  log_info "Test: the byte-identical BOM strip statement exists exactly once in BOTH config parsers (0138-TEST-005 structural)..."
  local check_mjs="$PROJECT_ROOT/.aai/scripts/update-check.mjs"
  [[ -f "$HELPER_MJS" ]] || log_fail "0138-TEST-005: helper missing: $HELPER_MJS"
  [[ -f "$check_mjs" ]] || log_fail "0138-TEST-005: update-check.mjs missing: $check_mjs"

  local strip='if (raw.charCodeAt(0) === 0xFEFF) raw = raw.slice(1);'
  local n1 n2 l1 l2
  n1=$(grep -cF "$strip" "$HELPER_MJS" || true)
  n2=$(grep -cF "$strip" "$check_mjs" || true)
  [[ "$n1" == "1" ]] || log_fail "0138-TEST-005: update-doctor-report.mjs must carry the strip statement exactly once, got $n1"
  [[ "$n2" == "1" ]] || log_fail "0138-TEST-005: update-check.mjs must carry the strip statement exactly once, got $n2"
  # Byte-identical including indentation: neither side may drift alone (D3).
  l1="$(grep -F "$strip" "$HELPER_MJS")"
  l2="$(grep -F "$strip" "$check_mjs")"
  [[ "$l1" == "$l2" ]] \
    || log_fail "0138-TEST-005: strip lines are not byte-identical: [$l1] vs [$l2]"

  log_pass "Twin-identical BOM strip pinned in both parsers, byte-for-byte (0138-TEST-005 structural)"
}

# --- 0138-TEST-006 (Spec-AC-05): exists-but-unreadable config honesty --------
test_020_0138_unreadable_config_warns() {
  log_info "Test: directory-shaped --config -> ONE named stderr WARNING, still default-on; absent config stays silent (0138-TEST-006)..."
  command -v node >/dev/null 2>&1 || { log_skip "0138-TEST-006: node not available"; return 0; }
  [[ -f "$HELPER_MJS" ]] || log_fail "0138-TEST-006: helper missing: $HELPER_MJS"

  local work root out err stub lines errlines
  work="$(mktemp -d "${TMPDIR:-/tmp}/aai-0138-t006.XXXXXX")"; work="$(cd "$work" && pwd)"
  out="$work/out.log"; err="$work/err.log"
  stub="$work/stub-clean.js"; write_stub_doctor "$stub" clean

  # Arm 1: --config points at a DIRECTORY — readFileSync fails EISDIR
  # (exists-but-unreadable, works even as root; D5 portable injection).
  root="$work/root-eisdir"; make_helper_root "$root"
  mkdir -p "$root/cfg-as-dir"
  run_helper "$work" "$out" "$err" --root "$root" --config "$root/cfg-as-dir" --doctor "$stub"
  [[ "$HELPER_RC" == "0" ]] || log_fail "0138-TEST-006: EISDIR arm expected exit 0, got $HELPER_RC"
  lines=$(wc -l < "$out" | tr -d ' ')
  [[ "$lines" == "1" ]] || log_fail "0138-TEST-006: EISDIR arm expected exactly 1 stdout line, got $lines: $(cat "$out")"
  grep -q '^DOCTOR CLEAN - full report: ' "$out" \
    || log_fail "0138-TEST-006: unreadable config must still default ON (doctor runs): $(cat "$out")"
  [[ "$(count_doctor_reports "$root")" == "1" ]] \
    || log_fail "0138-TEST-006: unreadable-config arm must write the report (default on)"
  errlines=$(wc -l < "$err" | tr -d ' ')
  [[ "$errlines" == "1" ]] || log_fail "0138-TEST-006: expected exactly 1 stderr line, got $errlines: $(cat "$err")"
  grep -qF 'WARNING' "$err" || log_fail "0138-TEST-006: stderr line is not a named WARNING: $(cat "$err")"
  grep -qF "$root/cfg-as-dir" "$err" || log_fail "0138-TEST-006: stderr WARNING must name the config path: $(cat "$err")"
  grep -qF '(EISDIR)' "$err" || log_fail "0138-TEST-006: stderr WARNING must name the error code: $(cat "$err")"

  # Arm 2 (negative control): an ABSENT config stays stderr-silent and on.
  root="$work/root-absent"; make_helper_root "$root"
  run_helper "$work" "$out" "$err" --root "$root" --doctor "$stub"
  [[ "$HELPER_RC" == "0" ]] || log_fail "0138-TEST-006: absent arm expected exit 0, got $HELPER_RC"
  lines=$(wc -l < "$out" | tr -d ' ')
  [[ "$lines" == "1" ]] || log_fail "0138-TEST-006: absent arm expected exactly 1 stdout line, got $lines"
  [[ ! -s "$err" ]] || log_fail "0138-TEST-006: an absent config (ENOENT) must stay silent on stderr: $(cat "$err")"

  rm -rf "$work"
  log_pass "Unreadable config: one named stderr WARNING (path + code), still on; ENOENT silent; stdout cardinality kept (0138-TEST-006)"
}

# --- 0138-TEST-007 (Spec-AC-05): prune-failure stderr budget ------------------
test_021_0138_prune_failure_budget() {
  log_info "Test: undeletable directory-shaped report -> max ONE stderr line per run; shaped files beyond cap still pruned; writable run silent (0138-TEST-007)..."
  command -v node >/dev/null 2>&1 || { log_skip "0138-TEST-007: node not available"; return 0; }
  [[ -f "$HELPER_MJS" ]] || log_fail "0138-TEST-007: helper missing: $HELPER_MJS"

  local work root out err stub lines errlines
  work="$(mktemp -d "${TMPDIR:-/tmp}/aai-0138-t007.XXXXXX")"; work="$(cd "$work" && pwd)"
  out="$work/out.log"; err="$work/err.log"
  stub="$work/stub-clean.js"; write_stub_doctor "$stub" clean

  # Arm 1: one undeletable DIRECTORY whose name matches the report shape
  # (unlinkSync on a directory fails on every platform — D5), plus shaped
  # FILES beyond the cap that must still be pruned past the failure.
  root="$work/root-dirtrap"; make_helper_root "$root"
  mkdir -p "$root/docs/ai/reports/doctor-20250101T000000Z-adir.md"
  local i
  for i in 02 03 04 05; do
    printf 'old %s\n' "$i" > "$root/docs/ai/reports/doctor-202501${i}T000000Z-oldhost.md"
  done
  run_helper "$work" "$out" "$err" --root "$root" --doctor "$stub" --max-reports 3
  [[ "$HELPER_RC" == "0" ]] || log_fail "0138-TEST-007: dir-trap arm expected exit 0, got $HELPER_RC"
  lines=$(wc -l < "$out" | tr -d ' ')
  [[ "$lines" == "1" ]] || log_fail "0138-TEST-007: dir-trap arm expected exactly 1 stdout line, got $lines: $(cat "$out")"
  grep -q '^DOCTOR CLEAN - full report: ' "$out" \
    || log_fail "0138-TEST-007: prune failure must never degrade the run's stdout line: $(cat "$out")"
  errlines=$(wc -l < "$err" | tr -d ' ')
  [[ "$errlines" == "1" ]] || log_fail "0138-TEST-007: expected exactly ONE stderr line per run, got $errlines: $(cat "$err")"
  grep -qF 'WARNING retention prune failed for' "$err" \
    || log_fail "0138-TEST-007: stderr line is not the named prune warning: $(cat "$err")"
  grep -qF "doctor-20250101T000000Z-adir.md" "$err" \
    || log_fail "0138-TEST-007: prune warning must name the undeletable path: $(cat "$err")"
  if grep -qF ' more' "$err"; then
    log_fail "0138-TEST-007: a single failure must not claim additional failures: $(cat "$err")"
  fi
  # Shaped files beyond the cap were still pruned despite the failure; the
  # newest survive (cap 3 = new report + 0105 + 0104).
  [[ ! -f "$root/docs/ai/reports/doctor-20250102T000000Z-oldhost.md" ]] \
    || log_fail "0138-TEST-007: shaped file beyond the cap must still be pruned past the failure"
  [[ ! -f "$root/docs/ai/reports/doctor-20250103T000000Z-oldhost.md" ]] \
    || log_fail "0138-TEST-007: shaped file beyond the cap must still be pruned past the failure"
  [[ -f "$root/docs/ai/reports/doctor-20250104T000000Z-oldhost.md" ]] \
    || log_fail "0138-TEST-007: in-cap shaped file must survive"
  [[ -f "$root/docs/ai/reports/doctor-20250105T000000Z-oldhost.md" ]] \
    || log_fail "0138-TEST-007: in-cap shaped file must survive"
  [[ -d "$root/docs/ai/reports/doctor-20250101T000000Z-adir.md" ]] \
    || log_fail "0138-TEST-007: the undeletable directory fixture vanished (bad fixture)"

  # Arm 2: several failures -> STILL one line, 'and N more' appended.
  root="$work/root-twodirs"; make_helper_root "$root"
  mkdir -p "$root/docs/ai/reports/doctor-20250101T000000Z-adir.md"
  mkdir -p "$root/docs/ai/reports/doctor-20250102T000000Z-bdir.md"
  for i in 03 04 05; do
    printf 'old %s\n' "$i" > "$root/docs/ai/reports/doctor-202501${i}T000000Z-oldhost.md"
  done
  run_helper "$work" "$out" "$err" --root "$root" --doctor "$stub" --max-reports 3
  [[ "$HELPER_RC" == "0" ]] || log_fail "0138-TEST-007: two-dirs arm expected exit 0, got $HELPER_RC"
  errlines=$(wc -l < "$err" | tr -d ' ')
  [[ "$errlines" == "1" ]] || log_fail "0138-TEST-007: two failures must still emit exactly ONE stderr line, got $errlines: $(cat "$err")"
  grep -qF 'and 1 more' "$err" \
    || log_fail "0138-TEST-007: multi-failure line must append 'and 1 more': $(cat "$err")"
  lines=$(wc -l < "$out" | tr -d ' ')
  [[ "$lines" == "1" ]] || log_fail "0138-TEST-007: two-dirs arm expected exactly 1 stdout line, got $lines"

  # Arm 3 (negative control): fully writable prune emits ZERO prune stderr.
  root="$work/root-writable"; make_helper_root "$root"
  mkdir -p "$root/docs/ai/reports"
  for i in 01 02 03 04 05; do
    printf 'old %s\n' "$i" > "$root/docs/ai/reports/doctor-202501${i}T000000Z-oldhost.md"
  done
  run_helper "$work" "$out" "$err" --root "$root" --doctor "$stub" --max-reports 3
  [[ "$HELPER_RC" == "0" ]] || log_fail "0138-TEST-007: writable arm expected exit 0, got $HELPER_RC"
  [[ ! -s "$err" ]] || log_fail "0138-TEST-007: a fully writable run must add zero stderr: $(cat "$err")"
  lines=$(wc -l < "$out" | tr -d ' ')
  [[ "$lines" == "1" ]] || log_fail "0138-TEST-007: writable arm expected exactly 1 stdout line, got $lines"

  rm -rf "$work"
  log_pass "Prune budget: one stderr line per run naming the first failed path (+ count), files still pruned, writable run silent (0138-TEST-007)"
}

# --- 0138-TEST-009 slice (Spec-AC-06): update product-doc + CHANGELOG pins ---
test_022_0138_documentation_pins() {
  log_info "Test: aai-update.md states BOM tolerance + the named degrade lines/budgets; CHANGELOG carries the CHANGE-0138 heading (0138-TEST-009)..."

  local pd="$PROJECT_ROOT/docs/product/aai-update.md"
  local cl="$PROJECT_ROOT/CHANGELOG.md"
  [[ -f "$pd" ]] || log_fail "0138-TEST-009: docs/product/aai-update.md does not exist"

  grep -qi 'BOM' "$pd" \
    || log_fail "0138-TEST-009: aai-update.md does not document the BOM tolerance"
  grep -qF 'retention prune failed' "$pd" \
    || log_fail "0138-TEST-009: aai-update.md does not name the prune degrade line"
  grep -qiE 'at most (one|two)' "$pd" \
    || log_fail "0138-TEST-009: aai-update.md does not state the one-line-per-run stderr budget"
  grep -qiE 'unreadable' "$pd" \
    || log_fail "0138-TEST-009: aai-update.md does not document the exists-but-unreadable config warning"

  grep -qE '^## \[unreleased\] — .*CHANGE-0138' "$cl" \
    || log_fail "0138-TEST-009: CHANGELOG.md has no unreleased heading entry for CHANGE-0138"

  log_pass "Update product doc tells the new degrade truths; CHANGELOG heading present (0138-TEST-009 slice)"
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
  test_006_0137_update_writes_field_report
  test_007_0137_helper_failure_matrix
  test_008_0137_induced_failure_update_runs
  test_009_0137_config_matrix
  test_010_0137_timeout_and_zero_network
  test_011_0137_skip_passthrough_verbatim
  test_012_0137_provenance_matrix
  test_013_0137_retention_cap
  test_014_0137_ps1_parity_structural
  test_015_0137_documentation_pins
  test_016_0137_governance_set
  test_017_0137_real_engine_crossing
  test_018_0138_bom_config_helper
  test_019_0138_bom_twin_structural_pin
  test_020_0138_unreadable_config_warns
  test_021_0138_prune_failure_budget
  test_022_0138_documentation_pins

  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}

main "$@"
