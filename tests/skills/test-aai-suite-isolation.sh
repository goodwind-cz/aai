#!/usr/bin/env bash
#
# Test: every suite runs in a disposable worktree
# (spec-suites-run-in-a-disposable-worktree).
#
# Covers TEST-001..TEST-006 from
# docs/specs/SPEC-0138-spec-suites-run-in-a-disposable-worktree.md.
#
# The isolation under test is armed at the two funnels every suite enters
# through: tests/skills/test-framework.sh (the one CI runs) and
# .aai/scripts/aai-run-tests.sh (the one roles invoke ad hoc).
#
# EVERY arm runs the REAL funnel file, byte-copied into a throwaway git
# repository, never a re-implementation of it. The fixture suites inside that
# repository deliberately try to modify a tracked file, create an untracked one
# and COMMIT — which is exactly what cannot be rehearsed against the real
# checkout, and exactly what has to fail to reach the repository now.
#
# This is the inverse of tests/skills/test-aai-repo-tripwire.sh: there the same
# fixtures MUST reach the repository so the tripwire can catch them, which is
# why that suite turns isolation off for its children. Both suites are true at
# once, and the pair is the honest statement of the design.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -uo pipefail

TEST_NAME="aai-suite-isolation"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

TRIPWIRE_LIB="$PROJECT_ROOT/.aai/scripts/lib/repo-tripwire.sh"
FRAMEWORK="$PROJECT_ROOT/tests/skills/test-framework.sh"
WRAPPER="$PROJECT_ROOT/.aai/scripts/aai-run-tests.sh"

FAILED=0
# A FILE, not an array, and that is the whole fix. Every `new_fixture` call site
# is a command substitution, which runs in a SUBSHELL: an array append inside
# one is invisible to the parent, so the EXIT trap used to drain an empty list
# and every fixture directory survived the run (measured: 34 leaked directories
# per clean run). This is the identical defect D4 documents in iso_create, which
# is what makes it embarrassing here of all places. An append to a file crosses
# the subshell boundary.
WORKDIR_REGISTRY="$(mktemp "${TMPDIR:-/tmp}/aai-isolation-registry.XXXXXX")" \
  || { echo "FAIL $TEST_NAME: no workdir registry could be made; refusing to run a suite that would then leak every fixture it creates" >&2; exit 1; }
register_workdir() { printf '%s\n' "$1" >> "$WORKDIR_REGISTRY"; }

# The SAME subshell boundary, one variable over, and the reason this is a file
# too rather than a one-line tidy. `log_fail` sets FAILED=1, and every one of
# the fifteen `new_fixture` call sites is `d="$(new_fixture)"` — a command
# substitution, so a `log_fail` reached from inside it sets FAILED in a subshell
# that then exits. Measured with `mktemp -d` forced to fail: all six arms
# returned early, the suite printed six FAIL lines and "All tests passed!", and
# exited 0. The diagnostic already crossed the boundary because it goes to
# stderr (stdout is the substitution's captured value); the VERDICT did not.
# It crosses the same way the workdir list does — through a file.
FAILURE_REGISTRY="$(mktemp "${TMPDIR:-/tmp}/aai-isolation-failures.XXXXXX")" \
  || { rm -f "$WORKDIR_REGISTRY"; echo "FAIL $TEST_NAME: no failure registry could be made; refusing to run a suite that could then fail without saying so" >&2; exit 1; }

cleanup() {
  local d
  while IFS= read -r d; do
    [[ -n "$d" && -d "$d" ]] || continue
    # A fixture repo may still own registered worktrees if an arm died between
    # creating one and asserting on it; drop them before the directory goes, or
    # the next `git worktree list` in that repo reports a path that is gone.
    if [[ -d "$d/.git" ]]; then
      git -C "$d" worktree prune >/dev/null 2>&1 || true
    fi
    rm -rf "$d"
  done < "$WORKDIR_REGISTRY"
  rm -f "$WORKDIR_REGISTRY" "$FAILURE_REGISTRY"
}
trap cleanup EXIT

log_pass() { echo "PASS $*"; }
log_fail() { echo "FAIL $*" >&2; FAILED=1; printf '%s\n' "$*" >> "$FAILURE_REGISTRY"; }
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
  d="$(mktemp -d "${TMPDIR:-/tmp}/aai-isolation-fixture.XXXXXX")"
  if [[ -z "$d" || "$d" != /* ]]; then
    log_fail "new_fixture: unsafe temp dir '$d'"
    return 1
  fi
  register_workdir "$d"
  echo "$d"
}

# write_fixture_suite <repo> <name> <body>
# Writes tests/skills/test-aai-<name>.sh. $R inside the body is the suite's OWN
# resolved project root — which is the whole point: every real suite in this
# repository derives PROJECT_ROOT exactly this way, so a suite that runs from a
# disposable checkout writes into the copy without knowing anything about it.
write_fixture_suite() {
  local repo="$1" name="$2" body="$3"
  {
    echo '#!/usr/bin/env bash'
    echo 'set -uo pipefail'
    echo 'R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"'
    echo "$body"
  } > "$repo/tests/skills/test-aai-$name.sh"
}

# build_framework_repo <dir> — a throwaway git repository carrying BYTE COPIES
# of the real framework, the real wrapper and the real tripwire library, plus a
# tracked file the fixture suites can try to dirty. tests/skills/results/ is
# gitignored exactly as it is in the real repository.
build_framework_repo() {
  local d="$1"
  mkdir -p "$d/tests/skills" "$d/.aai/scripts/lib" "$d/docs/ai/tests"
  cp "$FRAMEWORK" "$d/tests/skills/test-framework.sh"
  cp "$WRAPPER" "$d/.aai/scripts/aai-run-tests.sh"
  cp "$TRIPWIRE_LIB" "$d/.aai/scripts/lib/repo-tripwire.sh"
  printf 'baseline\n' > "$d/tracked.txt"
  printf 'tests/skills/results/\ndocs/ai/tests/test-runs.jsonl\n' > "$d/.gitignore"
}

commit_fixture_repo() {
  local d="$1"
  (
    cd "$d" &&
    git init -q -b main &&
    git config user.email 'isolation-test@example.com' &&
    git config user.name 'isolation-test' &&
    git add -A &&
    git commit -q -m 'fixture baseline'
  )
}

# repo_state <dir> — HEAD plus the verbatim porcelain, the same two halves
# AC-001 names. Kept as one string so a diff of two calls is the whole claim.
repo_state() {
  local d="$1"
  git -C "$d" rev-parse HEAD 2>/dev/null || echo "NO-HEAD"
  git -C "$d" status --porcelain=v1 2>/dev/null || echo "NO-STATUS"
}

# leaked_worktrees <dir> <tmphome> — every way a disposable checkout can
# survive: a registration git still lists, or a directory left on disk.
leaked_worktrees() {
  local d="$1" tmphome="$2" n_reg n_dir
  n_reg=$(( $(git -C "$d" worktree list 2>/dev/null | wc -l) - 1 ))
  n_dir=$(find "$tmphome" -maxdepth 1 -name 'aai-iso-*' 2>/dev/null | wc -l)
  echo $(( n_reg + n_dir ))
}

# ---------------------------------------------------------------------------
# TEST-001 (AC-001) — a suite does not reach the shipping WORKING TREE by
# accident (not `cannot`: the copy is one `git rev-parse --git-common-dir` away
# from the shipping tree's path — see the Summary and D7). The
# fixture suites do the two things the tripwire was built to catch — modify a
# tracked file plus create an untracked one, and COMMIT — and the fixture
# repository comes back byte-identical on both halves of the snapshot.
# What this arm does NOT claim: the shared `.git` is still reachable from the
# copy (refs, config, hooks — measured, spec D7), and nothing here tests that.
# ---------------------------------------------------------------------------
test_001_writes_do_not_reach_the_working_tree_by_accident() {
  local d evid out rc=0 ok=1 before after
  d="$(new_fixture)" || return
  evid="$d.evid"
  mkdir -p "$evid"
  register_workdir "$evid"
  build_framework_repo "$d"
  write_fixture_suite "$d" t-dirty "
printf 'dirt\n' >> \"\$R/tracked.txt\"
printf 'x\n' > \"\$R/untracked-dirt.txt\"
printf '%s\n' \"\$R\" > '$evid/root-dirty.txt'
wc -l < \"\$R/tracked.txt\" | tr -d ' ' > '$evid/lines-dirty.txt'
exit 0"
  write_fixture_suite "$d" t-commit "
printf 'committed dirt\n' >> \"\$R/tracked.txt\"
git -C \"\$R\" add -A >/dev/null 2>&1
git -C \"\$R\" commit -q -m 'a suite committed to main' >/dev/null 2>&1
git -C \"\$R\" rev-parse HEAD > '$evid/head-commit.txt'
exit 0"
  commit_fixture_repo "$d" || { log_fail "TEST-001 fixture repo init failed"; return; }

  before="$(repo_state "$d")"
  out="$(bash "$d/tests/skills/test-framework.sh" 2>&1 | strip_ansi)" || rc=$?
  after="$(repo_state "$d")"

  [[ "$rc" -eq 0 ]] || { log_info "TEST-001: framework exit=$rc (want 0 — neither suite reached the repository): $out"; ok=0; }
  [[ "$before" == "$after" ]] \
    || { log_info "TEST-001: the shipping repository MOVED. before=[$before] after=[$after]"; ok=0; }

  # The arm must not be able to pass by nothing happening: each fixture proves
  # it ran, that it ran somewhere ELSE, and that its write actually landed.
  [[ -f "$evid/root-dirty.txt" ]] || { log_info "TEST-001: the dirty fixture never ran"; ok=0; }
  if [[ -f "$evid/root-dirty.txt" ]]; then
    local seen_root
    seen_root="$(cat "$evid/root-dirty.txt")"
    [[ "$seen_root" != "$d" ]] \
      || { log_info "TEST-001: the dirty fixture ran with PROJECT_ROOT=$seen_root, i.e. IN the shipping repository"; ok=0; }
  fi
  [[ "$(cat "$evid/lines-dirty.txt" 2>/dev/null)" == "2" ]] \
    || { log_info "TEST-001: the dirty fixture's append did not land in its own checkout ($(cat "$evid/lines-dirty.txt" 2>/dev/null) line(s), want 2) — the arm is not measuring what it claims"; ok=0; }
  [[ -s "$evid/head-commit.txt" ]] || { log_info "TEST-001: the committing fixture never committed"; ok=0; }
  if [[ -s "$evid/head-commit.txt" ]]; then
    [[ "$(cat "$evid/head-commit.txt")" != "$(git -C "$d" rev-parse HEAD)" ]] \
      || { log_info "TEST-001: the commit landed on the shipping repository's HEAD"; ok=0; }
  fi
  grep -qE 'aai-t-dirty +PASS' <<<"$out" \
    || { log_info "TEST-001: the dirty fixture did not run to a PASS: $out"; ok=0; }
  grep -qF 'TRIPWIRE' <<<"$out" \
    && { log_info "TEST-001: the tripwire fired, so a write DID reach the repository: $out"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-001 a suite that modifies a tracked file, creates an untracked one and commits leaves HEAD and git status --porcelain=v1 byte-identical, with all three writes landed in the disposable checkout instead" \
    || log_fail "TEST-001 writes do not reach the shipping working tree by accident"
}

# ---------------------------------------------------------------------------
# TEST-002 (AC-002) — the copy is the WORKING TREE, not HEAD. `git worktree
# add` checks out a commit, so the naive form makes an uncommitted edit
# invisible and reports a brand-new suite as `No such file or directory` —
# a TDD RED that can never go red. All three shapes are exercised at once.
# ---------------------------------------------------------------------------
test_002_working_tree_not_head() {
  local d evid out rc=0 ok=1
  d="$(new_fixture)" || return
  evid="$d.evid"
  mkdir -p "$evid"
  register_workdir "$evid"
  build_framework_repo "$d"
  mkdir -p "$d/lib"
  printf 'v1\n' > "$d/lib/prod.txt"
  write_fixture_suite "$d" t-existing "
printf 'ORIGINAL\n' > '$evid/existing.txt'
exit 0"
  commit_fixture_repo "$d" || { log_fail "TEST-002 fixture repo init failed"; return; }

  # (a) an uncommitted edit to an EXISTING suite;
  write_fixture_suite "$d" t-existing "
printf 'EDITED-SUITE\n' > '$evid/existing.txt'
exit 0"
  # (b) an uncommitted edit to a production file a suite reads;
  printf 'v2\n' > "$d/lib/prod.txt"
  # (c) a BRAND-NEW, never-committed suite file, which must be discovered, must
  #     exist in the copy, and must see (b).
  write_fixture_suite "$d" t-brandnew "
printf '%s\n' \"\$(cat \"\$R/lib/prod.txt\")\" > '$evid/brandnew-sees.txt'
exit 0"

  out="$(bash "$d/tests/skills/test-framework.sh" 2>&1 | strip_ansi)" || rc=$?

  [[ "$rc" -eq 0 ]] || { log_info "TEST-002: framework exit=$rc (want 0): $out"; ok=0; }
  grep -qF 'Found 2 test(s)' <<<"$out" \
    || { log_info "TEST-002: the brand-new suite was not discovered: $out"; ok=0; }
  [[ "$(cat "$evid/existing.txt" 2>/dev/null)" == "EDITED-SUITE" ]] \
    || { log_info "TEST-002(a): the run used the COMMITTED suite, not the edited one (got '$(cat "$evid/existing.txt" 2>/dev/null)')"; ok=0; }
  [[ "$(cat "$evid/brandnew-sees.txt" 2>/dev/null)" == "v2" ]] \
    || { log_info "TEST-002(b): the uncommitted production edit was invisible to the run (got '$(cat "$evid/brandnew-sees.txt" 2>/dev/null)', want v2)"; ok=0; }
  grep -qE 'aai-t-brandnew +PASS' <<<"$out" \
    || { log_info "TEST-002(c): the brand-new untracked suite did not run to a PASS — this is the silent-TDD-failure shape: $out"; ok=0; }
  grep -qF 'No such file or directory' <<<"$out" \
    && { log_info "TEST-002(c): a suite was missing from the disposable checkout: $out"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-002 an uncommitted suite edit, an uncommitted production edit and a brand-new untracked suite are all visible to the run" \
    || log_fail "TEST-002 the copy reflects the working tree, not HEAD"
}

# ---------------------------------------------------------------------------
# TEST-003 (AC-003) — the gitignored per-dev files suites READ are seeded, and
# the seeding is load-bearing rather than decorative. Without it four assertion
# groups in this repository (check-state TEST-010/TEST-002, orchestration-mode
# TEST-016 and orchestration-dispatch's repo-wide gate) silently become PASSING
# SKIPS: a greener run that tests less. The negative control in this arm is the
# same run with the seed list pointed elsewhere.
# ---------------------------------------------------------------------------
test_003_gitignored_per_dev_files_are_seeded() {
  local d out rc=0 ok=1
  d="$(new_fixture)" || return
  build_framework_repo "$d"
  printf 'tests/skills/results/\ndocs/ai/tests/test-runs.jsonl\ndocs/ai/STATE.yaml\n' > "$d/.gitignore"
  mkdir -p "$d/docs/ai"
  printf 'marker-42\n' > "$d/docs/ai/STATE.yaml"
  # Reads the gitignored file exactly the way check-state TEST-010 does: it is
  # PRESENT-or-skip, so an absent file is a pass that proved nothing. Here the
  # skip is made loud so the arm can see it.
  write_fixture_suite "$d" t-reads-state '
if [[ ! -f "$R/docs/ai/STATE.yaml" ]]; then
  echo "SKIPPING: no per-dev STATE.yaml present"
  exit 0
fi
grep -q marker-42 "$R/docs/ai/STATE.yaml" || { echo "FAIL: seeded STATE.yaml has the wrong content"; exit 1; }
echo "ASSERTED against the per-dev STATE.yaml"
exit 0'
  commit_fixture_repo "$d" || { log_fail "TEST-003 fixture repo init failed"; return; }
  git -C "$d" check-ignore -q docs/ai/STATE.yaml \
    || { log_info "TEST-003: the fixture's STATE.yaml is not gitignored, so the arm proves nothing"; ok=0; }

  out="$(bash "$d/tests/skills/test-framework.sh" --verbose 2>&1 | strip_ansi)" || rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-003: framework exit=$rc (want 0): $out"; ok=0; }
  grep -qF 'ASSERTED against the per-dev STATE.yaml' <<<"$out" \
    || { log_info "TEST-003: the gitignored per-dev file was NOT seeded, so the assertion turned into a passing skip: $out"; ok=0; }
  grep -qF 'SKIPPING: no per-dev STATE.yaml present' <<<"$out" \
    && { log_info "TEST-003: the run reported the skip, which is the greener-and-emptier failure mode: $out"; ok=0; }

  # NEGATIVE CONTROL, in the same arm: point the seed list at a path that does
  # not exist and the SAME suite must degrade to the skip. Without this the arm
  # could pass on a framework that seeds nothing but happens to be run in a
  # checkout that already carries the file.
  local out2 rc2=0
  out2="$(AAI_TEST_ISOLATION_SEED='docs/ai/not-a-real-file' bash "$d/tests/skills/test-framework.sh" --verbose 2>&1 | strip_ansi)" || rc2=$?
  grep -qF 'SKIPPING: no per-dev STATE.yaml present' <<<"$out2" \
    || { log_info "TEST-003(control): with the seed list emptied the suite did NOT skip, so the seeding is not what made the positive arm pass: $out2"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-003 a gitignored per-dev file the suites read is seeded into the disposable checkout, and with the seed list pointed elsewhere the same assertion degrades to a skip (negative control)" \
    || log_fail "TEST-003 gitignored per-dev files are seeded"
}

# ---------------------------------------------------------------------------
# TEST-004 (AC-004) — the checkout is gone on ALL FOUR exits: a pass, a
# failure, a watchdog kill and an interrupt. A leaked worktree per suite over
# ~80 suites is a real cost, and a leaked REGISTRATION is worse than a leaked
# directory: `git worktree list` then names a path that does not exist.
# ---------------------------------------------------------------------------
test_004_the_checkout_is_removed_on_every_exit() {
  local ok=1

  # (a) a passing run and (b) a failing run, in one fixture each.
  local case_name body_exit
  for case_name in pass fail; do
    local d tmphome out rc=0 leaked
    d="$(new_fixture)" || return
    tmphome="$(new_fixture)" || return
    build_framework_repo "$d"
    body_exit=0
    [[ "$case_name" == "fail" ]] && body_exit=1
    write_fixture_suite "$d" t-$case_name "echo '$case_name fixture'; exit $body_exit"
    commit_fixture_repo "$d" || { log_fail "TEST-004($case_name) fixture repo init failed"; return; }
    out="$(TMPDIR="$tmphome" bash "$d/tests/skills/test-framework.sh" 2>&1 | strip_ansi)" || rc=$?
    if [[ "$case_name" == "pass" ]]; then
      [[ "$rc" -eq 0 ]] || { log_info "TEST-004(a): a passing run exited $rc: $out"; ok=0; }
    else
      [[ "$rc" -eq 1 ]] || { log_info "TEST-004(b): a failing run exited $rc (want 1): $out"; ok=0; }
    fi
    leaked="$(leaked_worktrees "$d" "$tmphome")"
    [[ "$leaked" -eq 0 ]] \
      || { log_info "TEST-004($case_name): $leaked disposable checkout(s) survived: $(git -C "$d" worktree list)"; ok=0; }
  done

  # (c) the watchdog: the framework is killed mid-suite by the real wrapper's
  # inline timeout, which is the exit path that has no `finally` of its own.
  local dc tmphome_c evid_c rc_c=0
  dc="$(new_fixture)" || return
  tmphome_c="$(new_fixture)" || return
  evid_c="$(new_fixture)" || return
  build_framework_repo "$dc"
  write_fixture_suite "$dc" t-sleep "
printf started > '$evid_c/mark'
sleep 30
printf finished > '$evid_c/mark'
exit 0"
  commit_fixture_repo "$dc" || { log_fail "TEST-004(c) fixture repo init failed"; return; }
  ( cd "$dc" && TMPDIR="$tmphome_c" AAI_TEST_TIMEOUT=3 AAI_FRICTION_CAPTURE=0 \
      bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh ) >/dev/null 2>&1 || rc_c=$?
  [[ "$rc_c" -eq 124 ]] \
    || { log_info "TEST-004(c): the wrapper exited $rc_c (want 124 — the watchdog must have fired, or the arm did not test a kill)"; ok=0; }
  [[ "$(cat "$evid_c/mark" 2>/dev/null)" == "started" ]] \
    || { log_info "TEST-004(c): the fixture suite was not killed mid-run (mark='$(cat "$evid_c/mark" 2>/dev/null)'), so the arm proves nothing"; ok=0; }
  local leaked_c
  leaked_c="$(leaked_worktrees "$dc" "$tmphome_c")"
  [[ "$leaked_c" -eq 0 ]] \
    || { log_info "TEST-004(c): $leaked_c disposable checkout(s) survived a watchdog kill: $(git -C "$dc" worktree list)"; ok=0; }

  # (d) an interrupt. Delivered to the whole process group, which is what a
  # Ctrl-C in a terminal actually does — the framework is waiting on a
  # foreground child, so a signal to the framework alone would sit unhandled
  # until that child finished on its own.
  if ! command -v perl >/dev/null 2>&1; then
    log_info "TEST-004(d): perl absent — the interrupt sub-arm needs it to put the framework in its own process group; NOT COVERED on this machine"
  else
    local dd tmphome_d evid_d pid i
    dd="$(new_fixture)" || return
    tmphome_d="$(new_fixture)" || return
    evid_d="$(new_fixture)" || return
    build_framework_repo "$dd"
    write_fixture_suite "$dd" t-sleep "
printf started > '$evid_d/mark'
sleep 30
printf finished > '$evid_d/mark'
exit 0"
    commit_fixture_repo "$dd" || { log_fail "TEST-004(d) fixture repo init failed"; return; }
    # $SIG{INT}='DEFAULT' is not decoration. A background job started by a
    # NON-interactive shell inherits SIGINT set to SIG_IGN (POSIX), and a shell
    # may not trap a signal that was ignored on entry — so without this reset
    # the framework would ignore the interrupt entirely and the arm would
    # measure a 30-second sleep instead of a Ctrl-C. Measured.
    TMPDIR="$tmphome_d" perl -e '$SIG{INT} = "DEFAULT"; use POSIX qw(setsid); setsid(); exec @ARGV' \
      -- bash "$dd/tests/skills/test-framework.sh" >/dev/null 2>&1 &
    pid=$!
    for i in $(seq 1 200); do
      [[ -f "$evid_d/mark" ]] && break
      sleep 0.1
    done
    kill -INT -"$pid" >/dev/null 2>&1
    wait "$pid" >/dev/null 2>&1
    [[ "$(cat "$evid_d/mark" 2>/dev/null)" == "started" ]] \
      || { log_info "TEST-004(d): the fixture suite was not interrupted mid-run (mark='$(cat "$evid_d/mark" 2>/dev/null)'), so the arm proves nothing"; ok=0; }
    local leaked_d
    leaked_d="$(leaked_worktrees "$dd" "$tmphome_d")"
    [[ "$leaked_d" -eq 0 ]] \
      || { log_info "TEST-004(d): $leaked_d disposable checkout(s) survived an interrupt: $(git -C "$dd" worktree list)"; ok=0; }
  fi

  # (e) the REGISTRATION half, on the path where `git worktree remove` cannot
  # do the job. A suite that deletes its own checkout's .git link file leaves
  # `worktree remove` with nothing it recognises, so the directory goes by
  # `rm -rf` and only the fallback deregistration can clear the admin entry.
  # This sub-arm is the ONLY thing holding that fallback: on the happy path
  # `worktree remove` clears the registration itself, so a funnel that dropped
  # the fallback would change nothing observable anywhere else — measured as a
  # mutation that bit nothing until this arm existed. The fallback is scoped to
  # this one checkout's `.git/worktrees/<name>` entry rather than a
  # repository-wide `git worktree prune`, because prune also deregisters an
  # OPERATOR worktree whose directory happens to be unreachable right now.
  local de tmphome_e out_e rc_e=0 leaked_e
  de="$(new_fixture)" || return
  tmphome_e="$(new_fixture)" || return
  build_framework_repo "$de"
  write_fixture_suite "$de" t-unlink '
rm -f "$R/.git"
echo "removed my own checkout gitdir link"
exit 0'
  commit_fixture_repo "$de" || { log_fail "TEST-004(e) fixture repo init failed"; return; }
  out_e="$(TMPDIR="$tmphome_e" bash "$de/tests/skills/test-framework.sh" 2>&1 | strip_ansi)" || rc_e=$?
  [[ "$rc_e" -eq 0 ]] || { log_info "TEST-004(e): the run exited $rc_e (want 0 — a suite wrecking its OWN copy is not a shipping-repository event): $out_e"; ok=0; }
  leaked_e="$(leaked_worktrees "$de" "$tmphome_e")"
  [[ "$leaked_e" -eq 0 ]] \
    || { log_info "TEST-004(e): $leaked_e disposable checkout(s) survived a removal that git could not perform: $(git -C "$de" worktree list)"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-004 the disposable checkout and its git worktree registration are both gone after a passing run, a failing run, a watchdog kill, an interrupt, and a removal git itself could not perform" \
    || log_fail "TEST-004 the checkout is removed on every exit"
}

# ---------------------------------------------------------------------------
# TEST-005 (AC-005) — the ad hoc funnel isolates too, without touching the
# wrapped command's exit code. And it isolates a SUITE RUN, not everything: a
# build run through this wrapper must still leave its artifact behind, or the
# guard is a regression wearing a guard's clothes. Sub-arms (e) and (f) pin the
# framework opt-out from both sides: a decoy argument must not buy it, and the
# genuine framework must still get it.
# ---------------------------------------------------------------------------
test_005_wrapper_isolates_a_suite_run() {
  local d evid ok=1 rc=0 before after
  d="$(new_fixture)" || return
  evid="$d.evid"
  mkdir -p "$evid"
  register_workdir "$evid"
  build_framework_repo "$d"
  write_fixture_suite "$d" wsuite "
printf 'dirt\n' >> \"\$R/tracked.txt\"
printf 'x\n' > \"\$R/untracked-dirt.txt\"
printf '%s\n' \"\$R\" > '$evid/wroot.txt'
exit \"\${1:-0}\""
  commit_fixture_repo "$d" || { log_fail "TEST-005 fixture repo init failed"; return; }

  # (a) a suite run, relative path, exit 0.
  before="$(repo_state "$d")"
  ( cd "$d" && AAI_FRICTION_CAPTURE=0 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-wsuite.sh 0 ) >/dev/null 2>&1 || rc=$?
  after="$(repo_state "$d")"
  [[ "$rc" -eq 0 ]] || { log_info "TEST-005(a): exit=$rc (want the command's own 0)"; ok=0; }
  [[ "$before" == "$after" ]] || { log_info "TEST-005(a): the shipping repository MOVED. before=[$before] after=[$after]"; ok=0; }
  [[ -f "$evid/wroot.txt" ]] || { log_info "TEST-005(a): the suite never ran"; ok=0; }
  [[ "$(cat "$evid/wroot.txt" 2>/dev/null)" != "$d" ]] \
    || { log_info "TEST-005(a): the suite ran IN the shipping repository"; ok=0; }

  # (b) the exit code is the command's own, unchanged, on a failure too.
  rc=0
  ( cd "$d" && AAI_FRICTION_CAPTURE=0 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-wsuite.sh 7 ) >/dev/null 2>&1 || rc=$?
  after="$(repo_state "$d")"
  [[ "$rc" -eq 7 ]] || { log_info "TEST-005(b): exit=$rc (want the command's own 7 — the wrapper contract is untouched)"; ok=0; }
  [[ "$before" == "$after" ]] || { log_info "TEST-005(b): the shipping repository MOVED on the failure path"; ok=0; }

  # (c) an ABSOLUTE suite path is isolated too. A relative one resolves against
  # the new working directory by itself; an absolute one has to be retargeted,
  # and a wrapper that forgets that isolates nothing whenever a role pastes a
  # full path.
  rc=0
  rm -f "$evid/wroot.txt"
  ( cd / && AAI_FRICTION_CAPTURE=0 bash "$d/.aai/scripts/aai-run-tests.sh" bash "$d/tests/skills/test-aai-wsuite.sh" 0 ) >/dev/null 2>&1 || rc=$?
  after="$(repo_state "$d")"
  [[ "$rc" -eq 0 ]] || { log_info "TEST-005(c): exit=$rc (want 0)"; ok=0; }
  [[ -f "$evid/wroot.txt" ]] || { log_info "TEST-005(c): the suite never ran from its absolute path"; ok=0; }
  [[ "$(cat "$evid/wroot.txt" 2>/dev/null)" != "$d" ]] \
    || { log_info "TEST-005(c): an absolute suite path was NOT retargeted, so it ran in the shipping repository"; ok=0; }
  [[ "$before" == "$after" ]] || { log_info "TEST-005(c): the shipping repository MOVED"; ok=0; }

  # (d) NOT everything is isolated. This wrapper also carries builds and
  # generators; discarding their output with the checkout would be a
  # regression, so a non-suite command still runs in the real tree.
  rc=0
  ( cd "$d" && AAI_FRICTION_CAPTURE=0 bash .aai/scripts/aai-run-tests.sh sh -c 'printf built > build-artifact.txt' ) >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-005(d): exit=$rc (want 0)"; ok=0; }
  [[ "$(cat "$d/build-artifact.txt" 2>/dev/null)" == "built" ]] \
    || { log_info "TEST-005(d): a NON-suite command was isolated and its artifact was discarded with the checkout — that is a regression, not a guard"; ok=0; }

  # (e) THE DECOY, and the reason the framework opt-out is not a suffix glob.
  # `*test-framework.sh` was tried against EVERY argument, so one word ending in
  # those characters — needing no file behind it at all — turned isolation off
  # for the whole invocation. The same suite run, with exactly such a word
  # appended, must still be isolated.
  rc=0
  rm -f "$evid/wroot.txt"
  before="$(repo_state "$d")"
  ( cd "$d" && AAI_FRICTION_CAPTURE=0 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-wsuite.sh 0 my-test-framework.sh ) >/dev/null 2>&1 || rc=$?
  after="$(repo_state "$d")"
  [[ "$rc" -eq 0 ]] || { log_info "TEST-005(e): exit=$rc (want 0)"; ok=0; }
  [[ -s "$evid/wroot.txt" ]] || { log_info "TEST-005(e): the suite never ran"; ok=0; }
  # Compared through `cd … && pwd -P`, not as strings: on macOS $TMPDIR ends in
  # a slash, so the fixture path carries a `//` the suite's own `pwd` has
  # already collapsed, and a plain string comparison can never fire. Measured on
  # this machine while proving this arm bites.
  local seen_e="" root_e
  [[ -s "$evid/wroot.txt" ]] && seen_e="$(cd "$(cat "$evid/wroot.txt")" 2>/dev/null && pwd -P)"
  root_e="$(cd "$d" && pwd -P)"
  [[ -n "$seen_e" && "$seen_e" == "$root_e" ]] \
    && { log_info "TEST-005(e): the decoy argument my-test-framework.sh turned isolation OFF — the suite ran at $seen_e, i.e. IN the shipping repository"; ok=0; }
  [[ "$before" == "$after" ]] \
    || { log_info "TEST-005(e): the shipping repository MOVED with a decoy argument present. before=[$before] after=[$after]"; ok=0; }

  # (f) the other direction: the GENUINE framework is still excluded (D5). If
  # the wrapper isolated it, the framework's SCRIPT_DIR — and with it the whole
  # run ledger under tests/skills/results/ — would resolve inside the disposable
  # checkout and be discarded with it. The ledger landing in the real fixture
  # tree is the observable that separates the two.
  rc=0
  rm -rf "$d/tests/skills/results"
  ( cd "$d" && AAI_FRICTION_CAPTURE=0 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh ) >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-005(f): the framework run through the wrapper exited $rc (want 0)"; ok=0; }
  [[ -n "$(ls -A "$d/tests/skills/results" 2>/dev/null)" ]] \
    || { log_info "TEST-005(f): the wrapper isolated the framework — its run ledger went with the disposable checkout instead of landing in the real tree (D5)"; ok=0; }

  # No registration and no directory survives any of the four.
  local n_reg
  n_reg=$(( $(git -C "$d" worktree list 2>/dev/null | wc -l) - 1 ))
  [[ "$n_reg" -eq 0 ]] \
    || { log_info "TEST-005: $n_reg disposable checkout(s) still registered: $(git -C "$d" worktree list)"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-005 the ad hoc funnel isolates a suite run by relative and by absolute path, leaves exit 0 and exit 7 untouched, leaks no worktree, still runs a non-suite command in the real tree, still isolates when a decoy argument named my-test-framework.sh is present, and still excludes the genuine test-framework.sh so its run ledger lands in the real tree" \
    || log_fail "TEST-005 the wrapper isolates a suite run"
}

# ---------------------------------------------------------------------------
# TEST-006 (AC-006) — the cost, MEASURED rather than estimated: the same
# fixture run twice, once with isolation off and once on, over enough suites
# that whole-second timing resolution cannot dominate the per-suite figure.
# ---------------------------------------------------------------------------
test_006_added_wall_clock_per_suite() {
  local d ok=1 n=20 i t0 t1 t2 off_s on_s delta ms
  d="$(new_fixture)" || return
  build_framework_repo "$d"
  for i in $(seq 1 "$n"); do
    write_fixture_suite "$d" "t-perf$i" 'exit 0'
  done
  commit_fixture_repo "$d" || { log_fail "TEST-006 fixture repo init failed"; return; }

  t0=$(date +%s)
  AAI_TEST_ISOLATION=0 bash "$d/tests/skills/test-framework.sh" >/dev/null 2>&1 \
    || { log_info "TEST-006: the isolation-off baseline run failed"; ok=0; }
  t1=$(date +%s)
  bash "$d/tests/skills/test-framework.sh" >/dev/null 2>&1 \
    || { log_info "TEST-006: the isolated run failed"; ok=0; }
  t2=$(date +%s)

  off_s=$(( t1 - t0 ))
  on_s=$(( t2 - t1 ))
  delta=$(( on_s - off_s ))
  # Milliseconds per suite, integer arithmetic only. A negative delta is noise
  # on a whole-second clock, not a speed-up; clamp it so the report cannot
  # claim isolation is free.
  [[ "$delta" -lt 0 ]] && delta=0
  ms=$(( delta * 1000 / n ))

  [[ "$ms" -lt 2000 ]] \
    || { log_info "TEST-006: isolation added ${ms}ms per suite over $n suites (baseline ${off_s}s, isolated ${on_s}s) — the bound is 2000ms"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-006 isolation adds ${ms}ms of wall clock per suite, measured over $n suites (baseline ${off_s}s, isolated ${on_s}s), against a 2000ms bound" \
    || log_fail "TEST-006 added wall clock per suite"
}

main() {
  echo "=== Test: $TEST_NAME (spec-suites-run-in-a-disposable-worktree) ==="
  check_deps
  test_001_writes_do_not_reach_the_working_tree_by_accident
  test_002_working_tree_not_head
  test_003_gitignored_per_dev_files_are_seeded
  test_004_the_checkout_is_removed_on_every_exit
  test_005_wrapper_isolates_a_suite_run
  test_006_added_wall_clock_per_suite
  echo ""
  # Both halves, because either one alone is a lie on some path: FAILED is
  # blind to a subshell failure, and the registry is blind to a machine where
  # the append itself could not land.
  if [[ $FAILED -eq 0 && ! -s "$FAILURE_REGISTRY" ]]; then
    echo "All tests passed!"
    exit 0
  fi
  if [[ $FAILED -eq 0 ]]; then
    echo "Failures reported from a subshell (see stderr above):"
    sed 's/^/  FAIL /' "$FAILURE_REGISTRY"
  fi
  echo "Some tests failed."
  exit 1
}

main "$@"
