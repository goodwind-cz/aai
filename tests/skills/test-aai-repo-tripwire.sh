#!/usr/bin/env bash
#
# Test: a suite must not be able to write to the shipping repository
# (spec-suites-must-not-touch-the-shipping-repo).
#
# Covers TEST-001..TEST-012 from
# docs/specs/SPEC-0137-spec-suites-must-not-touch-the-shipping-repo.md.
#
# The tripwire under test lives in .aai/scripts/lib/repo-tripwire.sh and is
# armed at the two funnels every suite enters through: tests/skills/
# test-framework.sh (the one CI runs) and .aai/scripts/aai-run-tests.sh (the
# one roles invoke ad hoc).
#
# EVERY funnel arm here runs the REAL funnel file, byte-copied into a throwaway
# git repository, never a re-implementation of it: the fixture suites inside
# that repository deliberately commit, modify a tracked file and create an
# untracked one, which is exactly what cannot be rehearsed against the real
# checkout. The one arm that DOES use the real checkout (TEST-006) only reads
# it, and its whole assertion is that nothing changed.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -uo pipefail

TEST_NAME="aai-repo-tripwire"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

# The ONE thing disposable-worktree isolation
# (spec-suites-run-in-a-disposable-worktree) had to change in an existing suite.
# Every framework arm below runs a BYTE COPY of test-framework.sh over fixture
# suites whose whole job is to dirty their own fixture repository. With
# isolation on, those fixtures dirty a throwaway worktree instead and the
# tripwire never sees the write it exists to catch — which is the right
# behaviour and the wrong test. MEASURED, twice, rather than reasoned: remove
# this export and 6 of the 12 arms go RED (TEST-001, TEST-002, TEST-008,
# TEST-009, TEST-011, TEST-012) against a 12/12 green control. The other six
# stay green; whether any of those then passes for the wrong reason was not
# measured. Either way the suite stops testing the tripwire, so isolation is
# off for this suite's children only.
# It does not weaken the guard: nothing here writes to the real checkout, and
# the outer framework's own tripwire still watches this suite.
export AAI_TEST_ISOLATION=0

TRIPWIRE_LIB="$PROJECT_ROOT/.aai/scripts/lib/repo-tripwire.sh"
FRAMEWORK="$PROJECT_ROOT/tests/skills/test-framework.sh"
WRAPPER="$PROJECT_ROOT/.aai/scripts/aai-run-tests.sh"

FAILED=0
WORKDIRS=()

cleanup() {
  local d
  for d in "${WORKDIRS[@]:-}"; do
    [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
  done
}
trap cleanup EXIT

log_pass() { echo "PASS $*"; }
log_fail() { echo "FAIL $*" >&2; FAILED=1; }
log_skip() { echo "SKIP $*"; exit 42; }
log_info() { echo "  $*"; }

check_deps() {
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  command -v bash >/dev/null 2>&1 || log_skip "bash not found"
  [[ -f "$TRIPWIRE_LIB" ]] || log_skip "$TRIPWIRE_LIB not found"
  [[ -f "$FRAMEWORK" ]] || log_skip "$FRAMEWORK not found"
  [[ -f "$WRAPPER" ]] || log_skip "$WRAPPER not found"
}

# strip_ansi — the framework colours its progress lines; assertions read text.
strip_ansi() { sed -E "s/$(printf '\033')\[[0-9;]*m//g"; }

new_fixture() {
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/aai-tripwire-fixture.XXXXXX")"
  if [[ -z "$d" || "$d" != /* ]]; then
    log_fail "new_fixture: unsafe temp dir '$d'"
    return 1
  fi
  WORKDIRS+=("$d")
  echo "$d"
}

# write_fixture_suite <repo> <name> <body>
# Writes tests/skills/test-aai-<name>.sh. $R inside the body is the repo root.
write_fixture_suite() {
  local repo="$1" name="$2" body="$3"
  {
    echo '#!/usr/bin/env bash'
    echo 'set -uo pipefail'
    echo 'R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"'
    echo "$body"
  } > "$repo/tests/skills/test-aai-$name.sh"
}

# build_framework_repo <dir> — a throwaway git repository carrying a BYTE COPY
# of the real framework and the real tripwire library, plus a tracked file the
# fixture suites can dirty. tests/skills/results/ is gitignored exactly as it
# is in the real repository: the framework writes each suite's log there
# BETWEEN the two snapshots, so an un-ignored results dir would make every
# suite read dirty. That coupling is asserted for the real tree in TEST-005.
build_framework_repo() {
  local d="$1"
  mkdir -p "$d/tests/skills" "$d/.aai/scripts/lib" "$d/docs/ai/tests"
  cp "$FRAMEWORK" "$d/tests/skills/test-framework.sh"
  cp "$TRIPWIRE_LIB" "$d/.aai/scripts/lib/repo-tripwire.sh"
  printf 'baseline\n' > "$d/tracked.txt"
  printf 'tests/skills/results/\ndocs/ai/tests/test-runs.jsonl\n' > "$d/.gitignore"
}

commit_fixture_repo() {
  local d="$1"
  (
    cd "$d" &&
    git init -q -b main &&
    git config user.email 'tripwire-test@example.com' &&
    git config user.name 'tripwire-test' &&
    git add -A &&
    git commit -q -m 'fixture baseline'
  )
}

# ---------------------------------------------------------------------------
# TEST-001 (Spec-AC-01) — a deliberately dirty suite turns the framework run
# red, and the failure names the suite and the paths it touched. The same run
# carries a clean suite as the in-run green control.
# ---------------------------------------------------------------------------
test_001_framework_bites_on_a_dirty_suite() {
  local d out rc=0 ok=1
  d="$(new_fixture)" || return
  build_framework_repo "$d"
  write_fixture_suite "$d" t-clean 'echo "clean fixture: writes nothing"; exit 0'
  write_fixture_suite "$d" t-dirty '
printf "dirt\n" >> "$R/tracked.txt"
printf "x\n" > "$R/untracked-dirt.txt"
echo "dirty fixture: wrote to the shipping repository"
exit 0'
  commit_fixture_repo "$d" || { log_fail "TEST-001 fixture repo init failed"; return; }

  out="$(bash "$d/tests/skills/test-framework.sh" 2>&1 | strip_ansi)" || rc=$?
  [[ "$rc" -eq 1 ]] || { log_info "TEST-001: framework exit=$rc (want 1)"; ok=0; }

  grep -qE '^\[ *1/ *2\] +aai-t-clean +PASS' <<<"$out" \
    || { log_info "TEST-001: the clean control suite did not PASS: $out"; ok=0; }
  grep -qE 'aai-t-dirty .*FAIL.*\[TRIPWIRE\]' <<<"$out" \
    || { log_info "TEST-001: the dirty suite was not marked FAIL [TRIPWIRE]: $out"; ok=0; }
  grep -qF "AAI-TRIPWIRE FAIL: test suite 'aai-t-dirty'" <<<"$out" \
    || { log_info "TEST-001: the violation report does not name the offending suite: $out"; ok=0; }
  grep -qF 'AAI-TRIPWIRE   now:  M tracked.txt' <<<"$out" \
    || { log_info "TEST-001: the report does not name the modified tracked path: $out"; ok=0; }
  grep -qF 'AAI-TRIPWIRE   now: ?? untracked-dirt.txt' <<<"$out" \
    || { log_info "TEST-001: the report does not name the created untracked path: $out"; ok=0; }
  grep -qF 'Tripwire: 1 suite(s) failed the shipping-repository tripwire' <<<"$out" \
    || { log_info "TEST-001: the summary does not count the violation: $out"; ok=0; }
  grep -qF 'Failed:  1' <<<"$out" \
    || { log_info "TEST-001: the aggregate does not count the tripwire failure as a failure: $out"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-001 a dirty suite turns the framework run red, naming the suite and both changed paths; the clean suite in the same run still passes" \
    || log_fail "TEST-001 framework tripwire bite"
}

# ---------------------------------------------------------------------------
# TEST-002 (Spec-AC-01) — the P1 shape: a suite that COMMITS. The tripwire
# reports the HEAD move, not merely a working-tree difference (a commit leaves
# `git status` clean, so a status-only comparison would see nothing at all).
# ---------------------------------------------------------------------------
test_002_framework_bites_on_a_commit() {
  local d out rc=0 ok=1 head_before head_after
  d="$(new_fixture)" || return
  build_framework_repo "$d"
  write_fixture_suite "$d" t-commit '
printf "committed dirt\n" >> "$R/tracked.txt"
git -C "$R" add -A >/dev/null 2>&1
git -C "$R" commit -q -m "a suite committed to main" >/dev/null 2>&1
echo "commit fixture: HEAD moved and the working tree is clean again"
exit 0'
  commit_fixture_repo "$d" || { log_fail "TEST-002 fixture repo init failed"; return; }
  head_before="$(git -C "$d" rev-parse HEAD)"

  out="$(bash "$d/tests/skills/test-framework.sh" 2>&1 | strip_ansi)" || rc=$?
  head_after="$(git -C "$d" rev-parse HEAD)"

  [[ "$rc" -eq 1 ]] || { log_info "TEST-002: framework exit=$rc (want 1)"; ok=0; }
  [[ "$head_before" != "$head_after" ]] \
    || { log_info "TEST-002: the fixture did not actually commit, so this arm proves nothing"; ok=0; }
  grep -qE 'aai-t-commit .*FAIL.*\[TRIPWIRE\]' <<<"$out" \
    || { log_info "TEST-002: a committing suite was not marked FAIL [TRIPWIRE]: $out"; ok=0; }
  grep -qF "AAI-TRIPWIRE   HEAD moved: $head_before -> $head_after" <<<"$out" \
    || { log_info "TEST-002: the report does not name both HEAD shas: $out"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-002 a suite that commits is caught by the HEAD half of the snapshot and both shas are named" \
    || log_fail "TEST-002 framework tripwire HEAD arm"
}

# ---------------------------------------------------------------------------
# TEST-003 (Spec-AC-04) — a suite that never ran must not read as clean. The
# exit-42-is-SKIP contract is unchanged, and a skipped suite, a crashed suite
# and an unguarded snapshot are each reported as NOT ATTESTED rather than
# folded into the clean count.
# ---------------------------------------------------------------------------
test_003_skipped_and_crashed_are_not_clean() {
  local d out rc=0 ok=1
  d="$(new_fixture)" || return
  build_framework_repo "$d"
  write_fixture_suite "$d" t-clean 'echo "clean"; exit 0'
  write_fixture_suite "$d" t-crash 'echo "crashed before completing" >&2; exit 3'
  write_fixture_suite "$d" t-skip 'echo "SKIP: dependency missing"; exit 42'
  commit_fixture_repo "$d" || { log_fail "TEST-003 fixture repo init failed"; return; }

  out="$(bash "$d/tests/skills/test-framework.sh" 2>&1 | strip_ansi)" || rc=$?
  # The crashed suite is a genuine failure, so the run is red for that reason.
  [[ "$rc" -eq 1 ]] || { log_info "TEST-003: framework exit=$rc (want 1, the crashed suite)"; ok=0; }

  grep -qE 'aai-t-skip +SKIP' <<<"$out" \
    || { log_info "TEST-003: exit 42 no longer maps to SKIP: $out"; ok=0; }
  grep -qF 'Skipped: 1' <<<"$out" \
    || { log_info "TEST-003: the skipped suite is not counted as skipped: $out"; ok=0; }
  grep -qE 'aai-t-skip .*\[tripwire NOT ATTESTED — suite skipped \(exit 42\), it never ran\]' <<<"$out" \
    || { log_info "TEST-003: a skipped suite is not reported as NOT ATTESTED: $out"; ok=0; }
  grep -qE 'aai-t-crash .*\[tripwire NOT ATTESTED — suite exited 3 before completing\]' <<<"$out" \
    || { log_info "TEST-003: a crashed suite is not reported as NOT ATTESTED: $out"; ok=0; }
  # Exactly one of the three suites ran to completion with the tree untouched.
  grep -qF 'Tripwire: 1/3 suite(s) attested clean; 2 not attested' <<<"$out" \
    || { log_info "TEST-003: the attested/not-attested accounting is wrong: $out"; ok=0; }
  grep -qF 'Tripwire: 1 suite(s) failed the shipping-repository tripwire' <<<"$out" \
    && { log_info "TEST-003: a run with no violation still reported one: $out"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-003 exit-42-is-SKIP still holds, and a skipped or crashed suite is reported NOT ATTESTED rather than counted clean" \
    || log_fail "TEST-003 skipped/crashed are not clean"
}

# ---------------------------------------------------------------------------
# TEST-004 (Spec-AC-05) — the unmutated green control, and the cost bound. A
# run in which nothing touches the repository is green, every suite keeps its
# own exit code, and the tripwire spends EXACTLY one `git status` pair per
# suite (counted through a PATH shim, not read off the source).
# ---------------------------------------------------------------------------
test_004_clean_run_is_green_and_costs_one_status_pair() {
  local d out rc=0 ok=1 real_git trace n_status n_suites
  real_git="$(command -v git)"
  [[ -n "$real_git" ]] || { log_fail "TEST-004: cannot resolve the real git binary"; return; }

  d="$(new_fixture)" || return
  build_framework_repo "$d"
  write_fixture_suite "$d" t-clean 'echo "clean"; exit 0'
  write_fixture_suite "$d" t-clean-two 'echo "also clean"; exit 0'
  write_fixture_suite "$d" t-skip 'exit 42'
  commit_fixture_repo "$d" || { log_fail "TEST-004 fixture repo init failed"; return; }
  n_suites=3

  trace="$d/git-trace.log"
  mkdir -p "$d/shim"
  {
    echo '#!/bin/sh'
    echo "printf '%s\\n' \"\$*\" >> \"$trace\""
    echo "exec $real_git \"\$@\""
  } > "$d/shim/git"
  chmod +x "$d/shim/git"

  out="$(PATH="$d/shim:$PATH" bash "$d/tests/skills/test-framework.sh" 2>&1 | strip_ansi)" || rc=$?

  [[ "$rc" -eq 0 ]] || { log_info "TEST-004: a clean run exited $rc (want 0): $out"; ok=0; }
  grep -qF 'Passed:  2' <<<"$out" || { log_info "TEST-004: clean suites did not pass: $out"; ok=0; }
  grep -qF 'Skipped: 1' <<<"$out" || { log_info "TEST-004: exit 42 did not stay SKIP: $out"; ok=0; }
  grep -qF 'Failed:' <<<"$out" && { log_info "TEST-004: a clean run reported failures: $out"; ok=0; }
  grep -qF 'TRIPWIRE' <<<"$out" && { log_info "TEST-004: a clean run emitted a violation report: $out"; ok=0; }
  grep -qF 'Tripwire: 2/3 suite(s) attested clean; 1 not attested' <<<"$out" \
    || { log_info "TEST-004: clean-run attestation accounting wrong: $out"; ok=0; }

  n_status="$(grep -c -- '--no-optional-locks .* status --porcelain=v1' "$trace" 2>/dev/null || echo 0)"
  [[ "$n_status" -eq $((2 * n_suites)) ]] \
    || { log_info "TEST-004: tripwire spent $n_status status calls over $n_suites suites (want $((2 * n_suites)) — one pair each)"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-004 an untouched tree keeps the run green and every exit code intact, at exactly one git status pair per suite (measured: $n_status calls over $n_suites suites)" \
    || log_fail "TEST-004 clean-run control + status-pair bound"
}

# ---------------------------------------------------------------------------
# TEST-005 (Spec-AC-05) — the tripwire's own working files must be invisible
# to it. The framework writes each suite's log into tests/skills/results/
# BETWEEN the two snapshots, so if that directory ever stopped being ignored
# the tripwire would fire on every suite and mean nothing.
# ---------------------------------------------------------------------------
test_005_results_dir_is_ignored_in_the_real_repo() {
  local ok=1
  # Ask about the LOG PATH the framework actually writes, not about the bare
  # directory: a `dir/`-suffixed .gitignore pattern is directory-only, and
  # `git check-ignore` cannot tell that a path is a directory when the path
  # does not exist on disk, so `check-ignore tests/skills/results` reports
  # not-ignored on a fresh clone that has never run the suite. Measured
  # 2026-08-19; it made this arm fail in two unrelated mutation lanes.
  if ! (cd "$PROJECT_ROOT" && git check-ignore -q tests/skills/results/test-run-id/some-skill.log); then
    log_info "TEST-005: the framework's per-suite log path under tests/skills/results/ is NOT git-ignored in this repository — the log is written between the two snapshots, so every suite would trip the tripwire and the check would mean nothing"
    ok=0
  fi
  [[ $ok -eq 1 ]] && log_pass "TEST-005 tests/skills/results is git-ignored, so the framework's own run artifacts cannot masquerade as a suite's write" \
    || log_fail "TEST-005 results dir ignored"
}

# ---------------------------------------------------------------------------
# TEST-006 (Spec-AC-03) — the two suites that used to rewrite tracked files run
# to completion against the REAL checkout and leave `git status --porcelain=v1`
# and HEAD byte-identical. Demonstrated by running them, per the AC.
# ---------------------------------------------------------------------------
test_006_fixed_suites_leave_the_real_tree_untouched() {
  local ok=1 suite rc before after state
  # shellcheck source=lib/../../.aai/scripts/lib/repo-tripwire.sh
  source "$TRIPWIRE_LIB"
  for suite in test-aai-doc-numbering test-aai-deslop; do
    before="$(mktemp)"; after="$(mktemp)"
    aai_tripwire_snapshot "$PROJECT_ROOT" "$before"
    rc=0
    (cd "$PROJECT_ROOT" && bash "tests/skills/$suite.sh") >/dev/null 2>&1 || rc=$?
    aai_tripwire_snapshot "$PROJECT_ROOT" "$after"
    state="$(aai_tripwire_state "$before" "$after")"
    if [[ "$state" != "clean" ]]; then
      log_info "TEST-006: $suite left the shipping repository $state (suite exit $rc)"
      aai_tripwire_report "$before" "$after" "$suite" "AAI-TRIPWIRE" | while IFS= read -r l; do log_info "$l"; done
      ok=0
    fi
    if [[ "$rc" -ne 0 && "$rc" -ne 42 ]]; then
      log_info "TEST-006: $suite exited $rc — it must run to COMPLETION against the real tree, not abort early"
      ok=0
    fi
    rm -f "$before" "$after"
  done
  [[ $ok -eq 1 ]] && log_pass "TEST-006 test-aai-doc-numbering and test-aai-deslop both run to completion against the real checkout leaving HEAD and git status --porcelain=v1 byte-identical" \
    || log_fail "TEST-006 fixed suites leave the real tree untouched"
}

# ---------------------------------------------------------------------------
# TEST-007 (Spec-AC-02) — the same violation is caught at the second funnel,
# .aai/scripts/aai-run-tests.sh. Report-only there by design: the wrapper's
# exit code is a pinned contract, so it is proven UNCHANGED in both the clean
# and the dirty case. A tripwire that could not arm because the INSTALLATION is
# broken (no library) says so; one that could never arm because the ENVIRONMENT
# has no usable git is silent per run, since that is not news about the run.
# ---------------------------------------------------------------------------
test_007_wrapper_reports_the_same_violation() {
  local d out rc=0 ok=1
  d="$(new_fixture)" || return
  mkdir -p "$d/.aai/scripts/lib"
  cp "$WRAPPER" "$d/.aai/scripts/aai-run-tests.sh"
  cp "$TRIPWIRE_LIB" "$d/.aai/scripts/lib/repo-tripwire.sh"
  printf 'baseline\n' > "$d/tracked.txt"
  # Each invocation must produce a DISTINCT porcelain line. `git status
  # --porcelain=v1` reports the change CLASS, not the content: a second append
  # to an already-" M" file leaves the status output byte-identical, so a
  # fixture that only appended twice would make arm (c) unfalsifiable. See the
  # spec's D7 for the same limitation stated as a shipped property.
  {
    echo '#!/usr/bin/env bash'
    echo "printf 'dirt\\n' >> \"$d/tracked.txt\""
    echo "printf 'x\\n' > \"$d/dirt-\$\$.txt\""
    echo 'exit "${1:-0}"'
  } > "$d/dirty.sh"
  commit_fixture_repo "$d" || { log_fail "TEST-007 fixture repo init failed"; return; }

  # (a) clean command: no tripwire output at all, exit code untouched.
  out="$(bash "$d/.aai/scripts/aai-run-tests.sh" true 2>&1)" || rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-007(a): clean run exit=$rc (want 0)"; ok=0; }
  grep -qF 'AAI-TRIPWIRE' <<<"$out" \
    && { log_info "TEST-007(a): a clean run emitted tripwire output: $out"; ok=0; }

  # (b) dirty command exiting 0: reported, exit code still 0.
  rc=0
  out="$(bash "$d/.aai/scripts/aai-run-tests.sh" bash "$d/dirty.sh" 0 2>&1)" || rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-007(b): exit=$rc (want the command's own 0 — the wrapper contract is report-only)"; ok=0; }
  grep -qF 'AAI-TRIPWIRE FAIL: the wrapped command' <<<"$out" \
    || { log_info "TEST-007(b): the wrapper did not report the violation: $out"; ok=0; }
  grep -qF 'AAI-TRIPWIRE   now:  M tracked.txt' <<<"$out" \
    || { log_info "TEST-007(b): the wrapper report does not name the changed path: $out"; ok=0; }

  # (c) dirty command exiting 7: the real exit code still surfaces unchanged.
  rc=0
  out="$(bash "$d/.aai/scripts/aai-run-tests.sh" bash "$d/dirty.sh" 7 2>&1)" || rc=$?
  [[ "$rc" -eq 7 ]] || { log_info "TEST-007(c): exit=$rc (want the command's own 7)"; ok=0; }
  grep -qF 'AAI-TRIPWIRE FAIL: the wrapped command' <<<"$out" \
    || { log_info "TEST-007(c): the wrapper did not report the violation: $out"; ok=0; }

  # (d) library missing: the wrapper says it is unarmed instead of staying
  # silent, and still runs the command with its own exit code.
  local d2 out2 rc2=0
  d2="$(new_fixture)" || return
  mkdir -p "$d2/.aai/scripts/lib"
  cp "$WRAPPER" "$d2/.aai/scripts/aai-run-tests.sh"
  commit_fixture_repo "$d2" || { log_fail "TEST-007 second fixture repo init failed"; return; }
  out2="$(bash "$d2/.aai/scripts/aai-run-tests.sh" sh -c 'exit 5' 2>&1)" || rc2=$?
  [[ "$rc2" -eq 5 ]] || { log_info "TEST-007(d): exit=$rc2 (want 5)"; ok=0; }
  grep -qF 'AAI-TRIPWIRE: NOTE - not armed' <<<"$out2" \
    || { log_info "TEST-007(d): a missing tripwire library degraded SILENTLY: $out2"; ok=0; }

  # (e) an environment where the tripwire can NEVER arm (the checkout is not a
  # git repository at all, which is what the WSL1 CI leg looks like from inside
  # WSL: git cannot read /mnt/d) must not print a per-run note. The fact is a
  # constant of the machine, and on that boundary the line displaced
  # aai-run-tests.ps1's own AAI-BRANCH diagnostic on every invocation.
  local d3 out3 rc3=0
  d3="$(new_fixture)" || return
  mkdir -p "$d3/.aai/scripts/lib"
  cp "$WRAPPER" "$d3/.aai/scripts/aai-run-tests.sh"
  cp "$TRIPWIRE_LIB" "$d3/.aai/scripts/lib/repo-tripwire.sh"
  # Deliberately NOT a git repository: no commit_fixture_repo here.
  out3="$(bash "$d3/.aai/scripts/aai-run-tests.sh" sh -c 'exit 0' 2>&1)" || rc3=$?
  [[ "$rc3" -eq 0 ]] || { log_info "TEST-007(e): exit=$rc3 (want 0)"; ok=0; }
  [[ -n "$out3" ]] && { log_info "TEST-007(e): a tripwire that could never arm still wrote to the wrapper's stderr: $out3"; ok=0; }

  # (f) the opposite case must stay loud: the before-snapshot WAS taken and the
  # command then made the repository unreadable. That is news about this run.
  local d4 out4 rc4=0
  d4="$(new_fixture)" || return
  mkdir -p "$d4/.aai/scripts/lib"
  cp "$WRAPPER" "$d4/.aai/scripts/aai-run-tests.sh"
  cp "$TRIPWIRE_LIB" "$d4/.aai/scripts/lib/repo-tripwire.sh"
  printf 'baseline\n' > "$d4/tracked.txt"
  commit_fixture_repo "$d4" || { log_fail "TEST-007 fourth fixture repo init failed"; return; }
  out4="$(bash "$d4/.aai/scripts/aai-run-tests.sh" sh -c "rm -rf '$d4/.git'; exit 9" 2>&1)" || rc4=$?
  [[ "$rc4" -eq 9 ]] || { log_info "TEST-007(f): exit=$rc4 (want the command's own 9)"; ok=0; }
  [[ -d "$d4/.git" ]] && { log_info "TEST-007(f): the fixture did not actually remove .git, so this arm proves nothing"; ok=0; }
  grep -qF 'the after-snapshot of' <<<"$out4" \
    || { log_info "TEST-007(f): a repository made unreadable mid-run was reported SILENTLY: $out4"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-007 the ad hoc funnel reports the same violation naming the command and the path, leaves every exit code untouched, is silent on a clean run and where the tripwire could never arm, and names both a missing library and a repository made unreadable mid-run" \
    || log_fail "TEST-007 wrapper funnel"
}

# ---------------------------------------------------------------------------
# TEST-008 (Spec-AC-06) — the known-offender ratchet, exercised against the
# SHIPPED allowlist rather than a test-only injection: the fixture suites are
# named after the real entries (aai-metrics, aai-state, aai-hitl-propagation)
# and dirty the real paths, so the arm reads the same table CI reads. Three
# properties in one run: an entry inside its paths warns and does not fail, an
# entry OUTSIDE its paths still fails, and an unlisted suite still fails
# (Spec-AC-01 intact). The drain report that used to print STALE for an entry
# whose suite changed nothing is deleted (D8) — "changed nothing in this run" is
# also true of a suite that skipped or crashed, so the line told the operator to
# delete a live entry. NOTHING here asserts that absence: no arm constrains
# framework output for an unused entry, so reintroducing a drain would not turn
# this arm red. Left uncovered deliberately — the ratchet is transitional
# (owner hitl_decision 2026-08-19: tripwire, ratchet and hashing are deleted
# once suites run in a disposable worktree).
# ---------------------------------------------------------------------------
test_008_known_offender_ratchet() {
  local d out rc=0 ok=1
  d="$(new_fixture)" || return
  build_framework_repo "$d"
  mkdir -p "$d/docs/ai"
  printf 'index\n' > "$d/docs/INDEX.md"
  printf '<html>\n' > "$d/docs/ai/overview.html"
  printf '{}\n' > "$d/docs/ai/overview-data.json"

  # On the list, and stays inside the two paths its entry names.
  write_fixture_suite "$d" metrics '
printf "regenerated\n" >> "$R/docs/ai/overview.html"
printf "regenerated\n" >> "$R/docs/ai/overview-data.json"
exit 0'
  # On the list for docs/INDEX.md only. It writes that path AND one its entry
  # does not name, which is the case an entry must not cover. The second path is
  # a NEW untracked file rather than one of the paths above: aai-metrics runs
  # first in the discovery order and has already dirtied those, and D7 means a
  # second write to an already-dirty path leaves porcelain byte-identical — a
  # fixture built that way reads clean and proves nothing (measured, first run).
  write_fixture_suite "$d" state '
printf "my own path\n" >> "$R/docs/INDEX.md"
printf "stray\n" > "$R/stray-from-state.txt"
exit 0'
  # Not on the list at all: the ratchet must not have relaxed the default.
  write_fixture_suite "$d" t-dirty '
printf "dirt\n" >> "$R/tracked.txt"
exit 0'
  # On the list, but writes nothing. It is one of the two suites the
  # attested-clean assertion below counts; nothing here asserts what the run
  # says ABOUT its unused entry (see the header note).
  write_fixture_suite "$d" hitl-propagation 'echo "clean now"; exit 0'
  write_fixture_suite "$d" t-clean 'echo "clean"; exit 0'
  commit_fixture_repo "$d" || { log_fail "TEST-008 fixture repo init failed"; return; }

  out="$(bash "$d/tests/skills/test-framework.sh" 2>&1 | strip_ansi)" || rc=$?

  [[ "$rc" -eq 1 ]] || { log_info "TEST-008: framework exit=$rc (want 1 — two suites are outside the ratchet)"; ok=0; }

  # (a) allowlisted suite, listed paths: warns loudly, does not fail the run.
  grep -qE 'aai-metrics .*PASS.*\[tripwire ALLOWED' <<<"$out" \
    || { log_info "TEST-008(a): an allowlisted suite inside its paths did not pass with an ALLOWED label: $out"; ok=0; }
  grep -qF "AAI-TRIPWIRE WARNING: test suite 'aai-metrics' changed the shipping repository." <<<"$out" \
    || { log_info "TEST-008(a): no WARNING naming the allowlisted suite: $out"; ok=0; }
  grep -qF 'allowed by the known-offender ratchet: fu-metrics-suite-writes-real-overview' <<<"$out" \
    || { log_info "TEST-008(a): the WARNING does not name the registry item: $out"; ok=0; }
  grep -qF 'AAI-TRIPWIRE   changed: docs/ai/overview.html' <<<"$out" \
    || { log_info "TEST-008(a): the WARNING does not name the changed path: $out"; ok=0; }
  grep -qF 'Tripwire: 1 known-offender suite(s) changed the shipping repository inside their allowlisted paths' <<<"$out" \
    || { log_info "TEST-008(a): the aggregate does not count allowlisted writes separately: $out"; ok=0; }

  # (b) allowlisted suite, UNLISTED path: still fails. An entry is scoped to
  # its paths, never blanket permission for the suite that holds it.
  grep -qE 'aai-state .*FAIL.*\[TRIPWIRE\]' <<<"$out" \
    || { log_info "TEST-008(b): an allowlisted suite dirtying an unlisted path did not fail: $out"; ok=0; }
  grep -qF "NOTE: 'aai-state' is on the known-offender ratchet (fu-state-suite-writes-real-index) for: docs/INDEX.md" <<<"$out" \
    || { log_info "TEST-008(b): the failure does not explain which entry was exceeded: $out"; ok=0; }
  grep -qF 'It also changed: stray-from-state.txt' <<<"$out" \
    || { log_info "TEST-008(b): the failure does not name the unlisted path: $out"; ok=0; }
  grep -qE 'aai-state .*PASS' <<<"$out" \
    && { log_info "TEST-008(b): writing one listed path bought a pass for an unlisted one: $out"; ok=0; }

  # (c) Spec-AC-01 intact: a suite that is not on the list still fails.
  grep -qE 'aai-t-dirty .*FAIL.*\[TRIPWIRE\]' <<<"$out" \
    || { log_info "TEST-008(c): a NON-allowlisted dirty suite no longer fails the run: $out"; ok=0; }
  grep -qF 'Failed:  2' <<<"$out" \
    || { log_info "TEST-008(c): the aggregate does not count exactly the two non-ratcheted failures: $out"; ok=0; }

  # An allowlisted write is never folded into the attested-clean count.
  grep -qF 'Tripwire: 2/5 suite(s) attested clean; 3 not attested' <<<"$out" \
    || { log_info "TEST-008: allowlisted/failed suites are miscounted in the attestation line: $out"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-008 the seeded ratchet warns for a known offender inside its listed paths, still fails it outside them, and still fails an unlisted suite" \
    || log_fail "TEST-008 known-offender ratchet"
}

# ---------------------------------------------------------------------------
# TEST-009 (Spec-AC-04) — an unavailable after-snapshot must not read as clean.
# A suite that destroys .git leaves the tripwire with nothing to compare; before
# this branch existed the framework exited 0 with a PASS line for exactly this
# fixture (fu-tripwire-unavailable-not-red). It now fails closed.
# ---------------------------------------------------------------------------
test_009_unavailable_after_snapshot_fails_closed() {
  local d out rc=0 ok=1
  d="$(new_fixture)" || return
  build_framework_repo "$d"
  write_fixture_suite "$d" t-nuke '
printf "dirt\n" >> "$R/tracked.txt"
rm -rf "$R/.git"
echo "nuke fixture: wrote to the repository, then removed .git"
exit 0'
  commit_fixture_repo "$d" || { log_fail "TEST-009 fixture repo init failed"; return; }

  out="$(bash "$d/tests/skills/test-framework.sh" 2>&1 | strip_ansi)" || rc=$?

  [[ "$rc" -eq 1 ]] || { log_info "TEST-009: framework exit=$rc (want 1 — an unreadable repository must not be green): $out"; ok=0; }
  [[ -d "$d/.git" ]] && { log_info "TEST-009: the fixture did not actually destroy .git, so this arm proves nothing"; ok=0; }
  grep -qE 'aai-t-nuke .*FAIL.*\[TRIPWIRE UNAVAILABLE\]' <<<"$out" \
    || { log_info "TEST-009: a suite that left no readable snapshot was not failed: $out"; ok=0; }
  grep -qF 'left no readable snapshot of the shipping repository' <<<"$out" \
    || { log_info "TEST-009: the failure does not say why it fired: $out"; ok=0; }
  grep -qF 'An unavailable snapshot is not evidence of a clean tree, so this fails closed.' <<<"$out" \
    || { log_info "TEST-009: the failure does not state the fail-closed rule: $out"; ok=0; }
  grep -qE 'aai-t-nuke .*PASS' <<<"$out" \
    && { log_info "TEST-009: the suite still reads as a PASS: $out"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-009 a suite that leaves the repository unreadable fails closed instead of reading as clean" \
    || log_fail "TEST-009 unavailable after-snapshot fails closed"
}

# ---------------------------------------------------------------------------
# TEST-010 (Spec-AC-04) — the other half of the same honesty rule, and the
# reason TEST-009 keys on the BEFORE snapshot: a framework run in a directory
# that is not a git repository at all was never armed. That degrades with a
# named note on the suite's OWN progress line — it must not be a bare PASS, and
# it must not fail the run either.
# ---------------------------------------------------------------------------
test_010_unarmed_run_is_labelled_not_failed() {
  local d out rc=0 ok=1
  d="$(new_fixture)" || return
  build_framework_repo "$d"
  write_fixture_suite "$d" t-clean 'echo "clean"; exit 0'
  # Deliberately NOT a git repository: no commit_fixture_repo here.

  out="$(bash "$d/tests/skills/test-framework.sh" 2>&1 | strip_ansi)" || rc=$?

  [[ "$rc" -eq 0 ]] || { log_info "TEST-010: an unarmed run exited $rc (want 0 — not being a git repository is not a suite failure): $out"; ok=0; }
  grep -qE 'aai-t-clean .*PASS.*\[tripwire NOT ARMED' <<<"$out" \
    || { log_info "TEST-010: an exit-0 suite with an unarmed tripwire printed a bare PASS instead of naming it: $out"; ok=0; }
  grep -qF 'Tripwire: 0/1 suite(s) attested clean; 1 not attested' <<<"$out" \
    || { log_info "TEST-010: an unarmed suite was folded into the attested count: $out"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-010 a run whose tripwire could not arm at all labels every progress line NOT ARMED and stays green" \
    || log_fail "TEST-010 unarmed run labelled on its own line"
}

# ---------------------------------------------------------------------------
# TEST-011 (Spec-AC-06) — the ratchet must not manufacture the masking it is
# exempted under. D7 says a SECOND write to an already-dirty path leaves
# `git status --porcelain=v1` byte-identical; the ratchet is what produces the
# first write, so on a CLEAN checkout the first allowlisted suite dirties
# docs/INDEX.md and every later writer of that path — listed or not — used to
# read clean: a bare PASS and a place in the attested count. Three suites write
# ONE path in sequence, which is the only order in which the defect appears.
# ---------------------------------------------------------------------------
test_011_ratchet_paths_are_content_watched() {
  local d out rc=0 ok=1 appended
  d="$(new_fixture)" || return
  build_framework_repo "$d"
  mkdir -p "$d/docs/ai"
  printf 'index\n' > "$d/docs/INDEX.md"

  # Runs first (sort order): on the list, writes its listed path. From here on
  # docs/INDEX.md is ' M' and its status line can no longer move.
  write_fixture_suite "$d" hitl-propagation '
printf "first listed write\n" >> "$R/docs/INDEX.md"
exit 0'
  # On the list for the same path, and writes it SECOND. Its entry is live, so
  # it must read ALLOWED rather than the bare PASS the masking produced.
  write_fixture_suite "$d" state '
printf "second listed write\n" >> "$R/docs/INDEX.md"
exit 0'
  # Not on the list at all, writes the same path THIRD. Spec-AC-06's "a suite
  # that is not on the list still fails" has to survive the ratchet firing.
  write_fixture_suite "$d" zz-evil '
printf "unlisted write\n" >> "$R/docs/INDEX.md"
exit 0'
  commit_fixture_repo "$d" || { log_fail "TEST-011 fixture repo init failed"; return; }

  out="$(bash "$d/tests/skills/test-framework.sh" 2>&1 | strip_ansi)" || rc=$?

  # The fixture must really have written three times, or the arm proves nothing.
  appended="$(grep -c 'write$' "$d/docs/INDEX.md" 2>/dev/null || echo 0)"
  [[ "$appended" -eq 3 ]] \
    || { log_info "TEST-011: the three fixture suites appended $appended line(s), want 3 — the arm is not measuring what it claims"; ok=0; }

  [[ "$rc" -eq 1 ]] || { log_info "TEST-011: framework exit=$rc (want 1 — the unlisted third writer must turn the run red): $out"; ok=0; }
  grep -qE 'aai-zz-evil .*FAIL.*\[TRIPWIRE\]' <<<"$out" \
    || { log_info "TEST-011: an UNLISTED suite writing an already-dirty ratchet path did not fail: $out"; ok=0; }
  grep -qF "AAI-TRIPWIRE FAIL: test suite 'aai-zz-evil'" <<<"$out" \
    || { log_info "TEST-011: the violation block does not name the unlisted suite: $out"; ok=0; }
  grep -qF 'content changed (git status class unmoved, caught by the ratchet-path hash): docs/INDEX.md' <<<"$out" \
    || { log_info "TEST-011: the violation names no path, so the report is undiagnosable: $out"; ok=0; }
  grep -qE 'aai-state .*PASS.*\[tripwire ALLOWED' <<<"$out" \
    || { log_info "TEST-011: the SECOND listed writer did not read as ALLOWED (a bare PASS is the masked reading): $out"; ok=0; }
  grep -qF 'Tripwire: 0/3 suite(s) attested clean' <<<"$out" \
    || { log_info "TEST-011: a masked writer was folded into the attested-clean count: $out"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-011 a second and a third write to one ratchet path are seen: the listed writer reads ALLOWED, the unlisted writer fails the run naming the path, and none of the three counts as attested clean" \
    || log_fail "TEST-011 ratchet paths are content-watched"
}

# ---------------------------------------------------------------------------
# TEST-012 (Spec-AC-06) — two ways the table itself can lie, both silent before
# this arm. A path field is matched LITERALLY: without `set -f` around the split
# it is a glob, and `docs/*` would exempt whatever it matches in the framework's
# working directory. A second entry for one suite is unreachable behind the
# first-match lookup. This is the one arm that must inject entries, so it edits
# the byte copy's table and says so; every other ratchet arm reads the shipped
# table.
# ---------------------------------------------------------------------------
test_012_ratchet_table_collisions_are_named() {
  local d out rc=0 ok=1
  d="$(new_fixture)" || return
  build_framework_repo "$d"
  mkdir -p "$d/docs/ai"
  printf 'index\n' > "$d/docs/INDEX.md"
  printf '<html>\n' > "$d/docs/ai/overview.html"

  # Inject three entries at the head of the shipped table.
  local injected="$d/tests/skills/framework-injected.tmp"
  awk '
    { print }
    /^TRIPWIRE_KNOWN_OFFENDERS=\(/ && !done {
      print "  \"aai-dup-victim|fu-dup-first-entry|docs/INDEX.md\""
      print "  \"aai-dup-victim|fu-dup-second-entry|docs/ai/overview.html\""
      print "  \"aai-glob-suite|fu-glob-entry|docs/*\""
      done = 1
    }
  ' "$d/tests/skills/test-framework.sh" > "$injected" && mv "$injected" "$d/tests/skills/test-framework.sh"
  grep -qF 'fu-dup-second-entry' "$d/tests/skills/test-framework.sh" \
    || { log_fail "TEST-012 could not inject the colliding entries"; return; }

  # Covered ONLY by the dead second entry, so it must still fail.
  write_fixture_suite "$d" dup-victim '
printf "dup\n" >> "$R/docs/ai/overview.html"
exit 0'
  # docs/INDEX.md is exactly what `docs/*` expands to in the framework's CWD, so
  # this suite passes if and only if the path field was glob-expanded.
  write_fixture_suite "$d" glob-suite '
printf "glob\n" >> "$R/docs/INDEX.md"
exit 0'
  commit_fixture_repo "$d" || { log_fail "TEST-012 fixture repo init failed"; return; }

  # Run WITH the fixture root as the working directory: a glob in an entry can
  # only widen against the CWD, so running from anywhere else would make the
  # arm pass for the wrong reason.
  out="$( cd "$d" && bash tests/skills/test-framework.sh 2>&1 | strip_ansi )" || rc=$?

  [[ -f "$d/docs/INDEX.md" ]] \
    || { log_info "TEST-012: docs/INDEX.md is absent, so 'docs/*' would have matched nothing anyway and the glob half proves nothing"; ok=0; }
  [[ "$rc" -eq 1 ]] || { log_info "TEST-012: framework exit=$rc (want 1 — neither suite is covered): $out"; ok=0; }
  grep -qF "DUPLICATE ratchet entry for suite 'aai-dup-victim'" <<<"$out" \
    || { log_info "TEST-012: a colliding second entry was dropped silently: $out"; ok=0; }
  grep -qE 'aai-dup-victim .*FAIL.*\[TRIPWIRE\]' <<<"$out" \
    || { log_info "TEST-012: the dead second entry still exempted its suite, so the warning describes the wrong behaviour: $out"; ok=0; }
  grep -qF "names path 'docs/*', which contains a glob metacharacter" <<<"$out" \
    || { log_info "TEST-012: a glob-shaped entry path was accepted without a word: $out"; ok=0; }
  grep -qE 'aai-glob-suite .*FAIL.*\[TRIPWIRE\]' <<<"$out" \
    || { log_info "TEST-012: 'docs/*' was expanded against the working directory and exempted a path it does not name: $out"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-012 a duplicate ratchet entry is named and stays dead, and a glob-shaped entry path is named and matches nothing instead of silently widening to the working directory" \
    || log_fail "TEST-012 ratchet table collisions are named"
}

main() {
  echo "=== Test: $TEST_NAME (spec-suites-must-not-touch-the-shipping-repo) ==="
  check_deps
  test_001_framework_bites_on_a_dirty_suite
  test_002_framework_bites_on_a_commit
  test_003_skipped_and_crashed_are_not_clean
  test_004_clean_run_is_green_and_costs_one_status_pair
  test_005_results_dir_is_ignored_in_the_real_repo
  test_006_fixed_suites_leave_the_real_tree_untouched
  test_007_wrapper_reports_the_same_violation
  test_008_known_offender_ratchet
  test_009_unavailable_after_snapshot_fails_closed
  test_010_unarmed_run_is_labelled_not_failed
  test_011_ratchet_paths_are_content_watched
  test_012_ratchet_table_collisions_are_named
  echo ""
  if [[ $FAILED -eq 0 ]]; then
    echo "All tests passed!"
    exit 0
  fi
  echo "Some tests failed."
  exit 1
}

main "$@"
