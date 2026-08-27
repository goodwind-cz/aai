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
# An arm whose LEVER is unavailable on this machine has neither passed nor
# failed, and calling it either is a lie. Codex reviewed the first fix for the
# vanishing arms and was right: turning "silently absent" into log_pass turned
# a hole into a false green, which is worse. UNCOVERED is its own verdict,
# counted here and reported by main, so the absence is visible in the tally
# without being counted as a test that ran.
UNCOVERED=0
log_uncovered() { echo "UNCOVERED $*"; UNCOVERED=$((UNCOVERED + 1)); }
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
# guard is a regression wearing a guard's clothes. Sub-arms (e), (f) and (g) pin
# the framework opt-out from all three sides: a decoy WORD must not buy it, the
# genuine framework invocation must still get it, and the genuine framework PATH
# carried as an argument of another suite must not buy it either.
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

  # (g) THE SECOND DECOY — the same class as (e), one variable over, and the one
  # still live when Codex reviewed PR #267. Making the match exact left the SCAN
  # over every argument, so a WRITING suite that merely CARRIES the genuine
  # framework path as one of its own arguments bought the opt-out for the whole
  # invocation: the suite ran against the shipping checkout, and because this
  # funnel's tripwire is report-only its writes stayed and the run still exited
  # 0. Measured before the fix on this fixture: ` M tracked.txt` +
  # `?? untracked-dirt.txt`, with the suite reporting the fixture root as its
  # own. The opt-out now reads the EXECUTED script only.
  rc=0
  rm -f "$evid/wroot.txt"
  before="$(repo_state "$d")"
  ( cd "$d" && AAI_FRICTION_CAPTURE=0 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-wsuite.sh 0 tests/skills/test-framework.sh ) >/dev/null 2>&1 || rc=$?
  after="$(repo_state "$d")"
  [[ "$rc" -eq 0 ]] || { log_info "TEST-005(g): exit=$rc (want the command's own 0)"; ok=0; }
  [[ -s "$evid/wroot.txt" ]] || { log_info "TEST-005(g): the suite never ran, so the arm proves nothing"; ok=0; }
  # Same `cd … && pwd -P` comparison as (e), and for the same measured reason.
  local seen_g="" root_g
  [[ -s "$evid/wroot.txt" ]] && seen_g="$(cd "$(cat "$evid/wroot.txt")" 2>/dev/null && pwd -P)"
  root_g="$(cd "$d" && pwd -P)"
  [[ -n "$seen_g" && "$seen_g" == "$root_g" ]] \
    && { log_info "TEST-005(g): the genuine framework path passed as an ARGUMENT of another suite turned isolation OFF — the suite ran at $seen_g, i.e. IN the shipping repository"; ok=0; }
  [[ "$before" == "$after" ]] \
    || { log_info "TEST-005(g): the shipping repository MOVED when the framework path rode along as a suite argument. before=[$before] after=[$after]"; ok=0; }

  # No registration and no directory survives any of them.
  local n_reg
  n_reg=$(( $(git -C "$d" worktree list 2>/dev/null | wc -l) - 1 ))
  [[ "$n_reg" -eq 0 ]] \
    || { log_info "TEST-005: $n_reg disposable checkout(s) still registered: $(git -C "$d" worktree list)"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-005 the ad hoc funnel isolates a suite run by relative and by absolute path, leaves exit 0 and exit 7 untouched, leaks no worktree, still runs a non-suite command in the real tree, still isolates when a decoy argument named my-test-framework.sh is present, still isolates when the GENUINE tests/skills/test-framework.sh path rides along as an argument of another suite, and still excludes the genuine test-framework.sh invocation itself so its run ledger lands in the real tree" \
    || log_fail "TEST-005 the wrapper isolates a suite run"
}

# ---------------------------------------------------------------------------
# TEST-006 (AC-006) — a BOUND-CONFORMANCE smoke check, not real-repo evidence
# (remediation round 1 F-4): the same FIXTURE run twice, once with isolation
# off and once on, over enough suites that whole-second timing resolution
# cannot dominate the per-suite figure. The fixture is a two-file byte-copy
# repository, not the ~72 MB shipping repository, so its ms/suite number
# proves the mechanism stays under the 2000ms bound on SOME repository — it is
# not the real per-suite `git clone --local --no-hardlinks` cost, which scales
# with repository size and is measured separately (Spec-AC-06's validation
# evidence, not this arm).
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
    || { log_info "TEST-006: isolation added ${ms}ms per suite over $n suites on the FIXTURE repo (baseline ${off_s}s, isolated ${on_s}s) — the bound is 2000ms"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-006 isolation adds ${ms}ms of wall clock per suite on the FIXTURE repo, measured over $n suites (baseline ${off_s}s, isolated ${on_s}s), against a 2000ms bound (a fixture-scoped bound-conformance check, not real-repo cost evidence)" \
    || log_fail "TEST-006 added wall clock per suite"
}

# ===========================================================================
# TEST-101..107 (spec-a-run-must-say-whether-isolation-armed)
#
# The arms above prove isolation WORKS. These prove the run SAYS SO — which is
# the hard precondition for deleting the tripwire: with the tripwire gone, a run
# where isolation never armed would otherwise stay green in silence.
#
# Numbered from 101 so SPEC-0138's TEST-001..006 keep their ids in this file.
#
# The three degrade paths are forced by ENVIRONMENT, never by mutating the
# fixture's byte copy of the framework. A mutated framework only proves that a
# mutated framework counts; an unusable TMPDIR and a gitignored suite file make
# the REAL branches run.
# ===========================================================================

# HERMETIC BY CONSTRUCTION: every fixture run below states the isolation it
# needs, `AAI_TEST_ISOLATION=1` as loudly as `=0`. An arm that merely INHERITED
# the setting is not measuring the path it names — measured on the real
# repository: with `AAI_TEST_ISOLATION=0` exported (a legitimate operator
# action, and the very state this scope exists to report), TEST-101/103/104/
# 105/106/107 all went red while the framework was behaving exactly as
# designed. The fixture framework is a byte copy, so it reads the same
# environment this suite was launched with.
#
# The SPEC-0138 arms above (TEST-001, TEST-003, TEST-005) have the same
# exposure and are deliberately NOT touched here — out of this scope's
# acceptance criteria, filed as `fu-isolation-suite-not-hermetic`.

# iso_status_fixture <dir> — a committed fixture repo with two trivially-passing
# suites. Everything TEST-101..106 needs and nothing else.
iso_status_fixture() {
  local d="$1"
  build_framework_repo "$d"
  write_fixture_suite "$d" t-one 'echo one; exit 0'
  write_fixture_suite "$d" t-two 'echo two; exit 0'
  commit_fixture_repo "$d"
}

# iso_summary_line <output> — the ONE unconditional accounting line. Matched by
# SHAPE, not by a full literal, so the arm fails loudly on a line that exists
# but has stopped carrying numbers.
iso_summary_line() {
  grep -E 'Isolation: [0-9]+/[0-9]+ suite\(s\) isolated; [0-9]+ degraded' <<<"$1" | tail -n 1
}

# iso_expect_counts <label> <output> <isolated> <total> <degraded>
# Vacuity-guarded in both directions: an ABSENT line fails (a run that printed
# nothing must never pass), and a line whose numbers differ fails naming both.
iso_expect_counts() {
  local label="$1" out="$2" want="Isolation: $3/$4 suite(s) isolated; $5 degraded"
  local got
  got="$(iso_summary_line "$out")"
  if [[ -z "$got" ]]; then
    log_info "$label: NO isolation accounting line in the summary at all (the line must print on EVERY run, including the all-clear)"
    return 1
  fi
  if [[ "$got" != *"$want" ]]; then
    log_info "$label: summary said [$got], want a line ending [$want]"
    return 1
  fi
  return 0
}

# iso_ledger_line <fixture> <run_id> — the ledger record for exactly this run.
iso_ledger_line() {
  grep -F "\"run_id\":\"$2\"" "$1/docs/ai/tests/test-runs.jsonl" 2>/dev/null
}

# iso_json_int <line> <key> — one integer field out of a one-line JSON record,
# with no jq dependency. Prints nothing when the key is absent, which is what
# makes an absent field an assertion failure rather than a silent zero.
iso_json_int() {
  local v
  v="$(sed -E "s/.*\"$2\":([0-9]+).*/\1/" <<<"$1")"
  [[ "$v" == "$1" ]] && return 0   # no substitution happened: key absent
  printf '%s\n' "$v"
}

# iso_run_id <output> — the framework prints its results directory; its
# basename IS the RUN_ID the ledger record carries.
iso_run_id() {
  local d
  d="$(grep -F 'Results saved to:' <<<"$1" | tail -n 1 | sed -E 's/.*Results saved to: //')"
  [[ -n "$d" ]] && basename "$d"
}

# ---------------------------------------------------------------------------
# TEST-101 (Spec-AC-01, Spec-AC-02) — THE UNMUTATED CONTROL. A run where
# nothing went wrong still states its isolation status. This is the arm that
# makes the line's presence a pinned fact: a line that appears only on failure
# is one a reader learns to expect the absence of, and a machine cannot tell
# "isolation was fine" from "this build predates the line".
# ---------------------------------------------------------------------------
test_101_the_all_clear_run_states_its_isolation_status() {
  local d out rc=0 ok=1
  d="$(new_fixture)" || return
  iso_status_fixture "$d" || { log_fail "TEST-101 fixture repo init failed"; return; }

  out="$(AAI_TEST_ISOLATION=1 bash "$d/tests/skills/test-framework.sh" 2>&1 | strip_ansi)" || rc=$?

  [[ "$rc" -eq 0 ]] || { log_info "TEST-101: framework exit=$rc (want 0): $out"; ok=0; }
  # Vacuity guard: the suites must actually have run, or "2/2 isolated" is a
  # statement about a run that never happened.
  grep -qE 'aai-t-one +PASS' <<<"$out" || { log_info "TEST-101: the fixture suites did not run: $out"; ok=0; }
  iso_expect_counts "TEST-101" "$out" 2 2 0 || ok=0
  grep -qF 'runs degraded' <<<"$out" \
    && { log_info "TEST-101: a clean run emitted a degrade NOTE: $out"; ok=0; }
  grep -qF 'suite(s) ran degraded' <<<"$out" \
    && { log_info "TEST-101: a clean run emitted the degraded WARNING line: $out"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-101 an all-clear run prints 'Isolation: 2/2 suite(s) isolated; 0 degraded' with no degrade NOTE and no degraded warning (the unmutated control for TEST-102..104)" \
    || log_fail "TEST-101 the all-clear run states its isolation status"
}

# ---------------------------------------------------------------------------
# TEST-102 (Spec-AC-01, Spec-AC-02) — DEGRADE PATH 1 ALONE: the global probe
# fails. Forced with AAI_TEST_ISOLATION=0, which is a real probe branch
# (iso_probe), not a mutation. Every suite must be counted degraded, and the
# probe's own reason must reach the summary — a count with no reason sends the
# reader back into the scrollback this line exists to replace.
# ---------------------------------------------------------------------------
test_102_the_global_probe_degrade_is_counted() {
  local d out rc=0 ok=1
  d="$(new_fixture)" || return
  iso_status_fixture "$d" || { log_fail "TEST-102 fixture repo init failed"; return; }

  out="$(AAI_TEST_ISOLATION=0 bash "$d/tests/skills/test-framework.sh" 2>&1 | strip_ansi)" || rc=$?

  [[ "$rc" -eq 0 ]] || { log_info "TEST-102: framework exit=$rc (want 0 — this is reporting, not a gate): $out"; ok=0; }
  grep -qE 'aai-t-one +PASS' <<<"$out" || { log_info "TEST-102: the fixture suites did not run: $out"; ok=0; }
  iso_expect_counts "TEST-102" "$out" 0 2 2 || ok=0
  grep -qF 'Reason(s): AAI_TEST_ISOLATION=0' <<<"$out" \
    || { log_info "TEST-102: the summary named no reason, or the wrong one: $out"; ok=0; }
  # ATTRIBUTION: this must be the PROBE path, not one of the per-suite paths.
  grep -qF 'no disposable checkout could be made' <<<"$out" \
    && { log_info "TEST-102: the run took the no-checkout path, so this arm is not testing the probe path: $out"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-102 a global probe degrade counts every suite degraded (0/2 isolated; 2 degraded), names AAI_TEST_ISOLATION=0 as the reason, and leaves exit 0" \
    || log_fail "TEST-102 the global probe degrade is counted"
}

# ---------------------------------------------------------------------------
# TEST-103 (Spec-AC-01, Spec-AC-02) — DEGRADE PATH 2 ALONE: iso_create fails.
# Forced by pointing TMPDIR at a REGULAR FILE, which is the framework's ONLY use
# of TMPDIR (the mktemp -d in iso_create), so it reaches that function's
# `|| return 1` and nothing else. The reason must be the no-checkout one,
# distinguishing this path from TEST-102's.
# ---------------------------------------------------------------------------
test_103_the_no_checkout_degrade_is_counted() {
  local d out rc=0 ok=1 badtmp
  d="$(new_fixture)" || return
  iso_status_fixture "$d" || { log_fail "TEST-103 fixture repo init failed"; return; }
  # A REGULAR FILE, not a missing directory. `mkdtemp` under a file is ENOTDIR
  # and nothing can turn a file into a directory behind the arm's back — whereas
  # a merely-absent TMPDIR is racy: measured here, an unrelated node process
  # sharing the exported TMPDIR created it (leaving a `node-compile-cache`
  # inside) between the guard and the run, and the arm then measured a perfectly
  # isolated run and called it a bug.
  badtmp="$d/tmpdir-is-a-file"
  printf 'not a directory\n' > "$badtmp"
  [[ -f "$badtmp" && ! -d "$badtmp" ]] \
    || { log_info "TEST-103: the unusable TMPDIR is not a plain file, so mktemp could succeed and the arm proves nothing"; ok=0; }

  out="$(TMPDIR="$badtmp" AAI_TEST_ISOLATION=1 bash "$d/tests/skills/test-framework.sh" 2>&1 | strip_ansi)" || rc=$?

  [[ "$rc" -eq 0 ]] || { log_info "TEST-103: framework exit=$rc (want 0): $out"; ok=0; }
  # Vacuity guard. NOT `<suite> +PASS` on one line: a degraded suite has its
  # NOTE printed BETWEEN the progress prefix and its result, so the two are on
  # different lines. Measured here — the single-line form made this arm fail on
  # a run that was working perfectly.
  grep -qE 'Passed: +2 \(100%\)' <<<"$out" \
    || { log_info "TEST-103: the fixture suites did not all run and pass: $out"; ok=0; }
  iso_expect_counts "TEST-103" "$out" 0 2 2 || ok=0
  grep -qF "Isolation: 'aai-t-one' runs degraded — no disposable checkout could be made" <<<"$out" \
    || { log_info "TEST-103: the per-suite no-checkout NOTE did not fire, so this arm is not testing that path: $out"; ok=0; }
  grep -qF 'Reason(s): no disposable checkout could be made' <<<"$out" \
    || { log_info "TEST-103: the summary named no reason, or the wrong one: $out"; ok=0; }
  # ATTRIBUTION: the probe must have SUCCEEDED, or this is TEST-102 again.
  grep -qF 'every suite runs isolated' <<<"$out" \
    || { log_info "TEST-103: the probe itself degraded, so this arm is not testing the per-suite path: $out"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-103 a per-suite iso_create failure counts every suite degraded (0/2 isolated; 2 degraded) with the no-disposable-checkout reason, on a run whose probe succeeded" \
    || log_fail "TEST-103 the no-checkout degrade is counted"
}

# ---------------------------------------------------------------------------
# TEST-104 (Spec-AC-01, Spec-AC-02) — DEGRADE PATH 3 ALONE: the suite is not in
# the disposable checkout. Forced with a gitignored-but-present suite file,
# which every seeding step misses by construction: discover_tests globs the
# FILESYSTEM, while the checkout is HEAD (the file is not committed) plus
# `ls-files --others --exclude-standard` (it is ignored) plus the seed list (it
# is not on it).
#
# This is also the MIXED run, and that is the point: the other two suites stay
# isolated, so the arm proves the counter is per-suite rather than per-run.
# ---------------------------------------------------------------------------
test_104_the_suite_missing_from_the_checkout_is_counted() {
  local d out rc=0 ok=1
  d="$(new_fixture)" || return
  build_framework_repo "$d"
  write_fixture_suite "$d" t-one 'echo one; exit 0'
  write_fixture_suite "$d" t-two 'echo two; exit 0'
  printf 'tests/skills/results/\ndocs/ai/tests/test-runs.jsonl\ntests/skills/test-aai-t-ghost.sh\n' > "$d/.gitignore"
  write_fixture_suite "$d" t-ghost 'echo ghost; exit 0'
  commit_fixture_repo "$d" || { log_fail "TEST-104 fixture repo init failed"; return; }
  git -C "$d" check-ignore -q tests/skills/test-aai-t-ghost.sh \
    || { log_info "TEST-104: the ghost suite is not gitignored, so it would be seeded and the arm proves nothing"; ok=0; }

  out="$(AAI_TEST_ISOLATION=1 bash "$d/tests/skills/test-framework.sh" 2>&1 | strip_ansi)" || rc=$?

  [[ "$rc" -eq 0 ]] || { log_info "TEST-104: framework exit=$rc (want 0): $out"; ok=0; }
  # Vacuity guard, same lesson as TEST-103: the degraded suite's NOTE sits
  # between its progress prefix and its result, so assert discovery and the
  # aggregate rather than one line.
  grep -qF 'Found 3 test(s)' <<<"$out" \
    || { log_info "TEST-104: the ghost suite was not discovered, so nothing could take the missing-from-checkout path: $out"; ok=0; }
  grep -qE 'Passed: +3 \(100%\)' <<<"$out" \
    || { log_info "TEST-104: not all three suites ran to a PASS: $out"; ok=0; }
  iso_expect_counts "TEST-104" "$out" 2 3 1 || ok=0
  grep -qF "Isolation: 'aai-t-ghost' (tests/skills/test-aai-t-ghost.sh) runs degraded" <<<"$out" \
    || { log_info "TEST-104: the per-suite NOTE did not name the ghost suite: $out"; ok=0; }
  grep -qF 'Reason(s): a suite was not in the disposable checkout' <<<"$out" \
    || { log_info "TEST-104: the summary named no reason, or the wrong one: $out"; ok=0; }
  # ATTRIBUTION, both directions: the probe succeeded and no OTHER suite degraded.
  grep -qF 'every suite runs isolated' <<<"$out" \
    || { log_info "TEST-104: the probe itself degraded, so this arm is not testing the per-suite path: $out"; ok=0; }
  grep -qF 'no disposable checkout could be made' <<<"$out" \
    && { log_info "TEST-104: a suite also took the no-checkout path, so two paths fired and the arm is not isolating one: $out"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-104 a suite missing from the disposable checkout is the ONLY one counted degraded on a mixed run (2/3 isolated; 1 degraded), named on its own NOTE line, with the other two still isolated" \
    || log_fail "TEST-104 the suite missing from the checkout is counted"
}

# ---------------------------------------------------------------------------
# TEST-105 (Spec-AC-03) — the run ledger carries the same two numbers as the
# summary line of the SAME run_id, on a clean run and on a fully degraded one.
# The ledger is what survives the scrollback; a summary line nobody kept is not
# an answer to "was that CI run isolated".
#
# The ledger file is removed before each run so the arm can assert there is
# EXACTLY ONE record for the run_id — RUN_ID has one-second resolution, and two
# runs inside one second would otherwise let the arm read the wrong line.
# ---------------------------------------------------------------------------
test_105_the_ledger_carries_the_same_two_numbers() {
  local ok=1 case_name
  for case_name in clean degraded; do
    local d out rc=0 rid line n_iso n_deg n_total want_iso want_deg
    d="$(new_fixture)" || return
    iso_status_fixture "$d" || { log_fail "TEST-105($case_name) fixture repo init failed"; return; }
    rm -f "$d/docs/ai/tests/test-runs.jsonl"

    if [[ "$case_name" == "clean" ]]; then
      want_iso=2; want_deg=0
      out="$(AAI_TEST_ISOLATION=1 bash "$d/tests/skills/test-framework.sh" 2>&1 | strip_ansi)" || rc=$?
    else
      want_iso=0; want_deg=2
      out="$(AAI_TEST_ISOLATION=0 bash "$d/tests/skills/test-framework.sh" 2>&1 | strip_ansi)" || rc=$?
    fi
    [[ "$rc" -eq 0 ]] || { log_info "TEST-105($case_name): framework exit=$rc (want 0): $out"; ok=0; }
    iso_expect_counts "TEST-105($case_name)" "$out" "$want_iso" 2 "$want_deg" || ok=0

    rid="$(iso_run_id "$out")"
    if [[ -z "$rid" ]]; then
      log_info "TEST-105($case_name): no run id could be read from the run output, so no ledger claim can be checked: $out"
      ok=0
      continue
    fi
    line="$(iso_ledger_line "$d" "$rid")"
    if [[ -z "$line" ]]; then
      log_info "TEST-105($case_name): NO ledger record for run_id=$rid (the summary line said one thing and the ledger said nothing)"
      ok=0
      continue
    fi
    [[ "$(wc -l <<<"$line" | tr -d ' ')" == "1" ]] \
      || { log_info "TEST-105($case_name): $(wc -l <<<"$line") ledger records carry run_id=$rid; the arm cannot attribute one"; ok=0; }

    n_iso="$(iso_json_int "$line" suites_isolated)"
    n_deg="$(iso_json_int "$line" suites_degraded)"
    n_total="$(iso_json_int "$line" total)"
    [[ -n "$n_iso" && -n "$n_deg" ]] \
      || { log_info "TEST-105($case_name): the ledger record has no suites_isolated/suites_degraded fields: $line"; ok=0; continue; }
    [[ "$n_iso" == "$want_iso" && "$n_deg" == "$want_deg" ]] \
      || { log_info "TEST-105($case_name): ledger says isolated=$n_iso degraded=$n_deg, summary says isolated=$want_iso degraded=$want_deg — the two surfaces disagree for run_id=$rid"; ok=0; }
    [[ -n "$n_total" && $((n_iso + n_deg)) -eq "$n_total" ]] \
      || { log_info "TEST-105($case_name): the record breaks isolated+degraded==total ($n_iso + $n_deg != ${n_total:-<absent>}): $line"; ok=0; }
  done

  [[ $ok -eq 1 ]] && log_pass "TEST-105 the run-ledger record for a run's own run_id carries suites_isolated and suites_degraded, they match that run's summary line on a clean and on a fully degraded run, and they sum to total" \
    || log_fail "TEST-105 the ledger carries the same two numbers"
}

# ---------------------------------------------------------------------------
# TEST-106 (Spec-AC-04) — a fully degraded run is VISIBLY different from a
# fully isolated one in all three surfaces, with an exit code that is
# IDENTICAL. Report-only is the whole contract here: the moment a degrade can
# turn a run red, an operator's `AAI_TEST_ISOLATION=0` becomes a gate on the
# machine rather than a statement about it, and the one suite that sets it on
# purpose (test-aai-repo-tripwire) would need a carve-out inside the gate.
# ---------------------------------------------------------------------------
test_106_degraded_is_visible_but_never_fatal() {
  local ok=1 outcome
  for outcome in pass fail; do
    local d body_exit want_rc out_iso out_deg rc_iso=0 rc_deg=0 rid_iso rid_deg
    d="$(new_fixture)" || return
    build_framework_repo "$d"
    body_exit=0; want_rc=0
    [[ "$outcome" == "fail" ]] && { body_exit=1; want_rc=1; }
    write_fixture_suite "$d" t-one "echo one; exit $body_exit"
    write_fixture_suite "$d" t-two 'echo two; exit 0'
    commit_fixture_repo "$d" || { log_fail "TEST-106($outcome) fixture repo init failed"; return; }

    # Each run's ledger record is READ while it is the only one on disk. RUN_ID
    # has one-second resolution, so two runs of a 2-suite fixture routinely
    # share it; reading both records after both runs matched the degraded record
    # for BOTH run ids and reported two identical records that never existed.
    # Measured here.
    local li ld
    rm -f "$d/docs/ai/tests/test-runs.jsonl"
    out_iso="$(AAI_TEST_ISOLATION=1 bash "$d/tests/skills/test-framework.sh" 2>&1 | strip_ansi)" || rc_iso=$?
    rid_iso="$(iso_run_id "$out_iso")"
    li="$(iso_ledger_line "$d" "${rid_iso:-none}")"
    rm -f "$d/docs/ai/tests/test-runs.jsonl"
    out_deg="$(AAI_TEST_ISOLATION=0 bash "$d/tests/skills/test-framework.sh" 2>&1 | strip_ansi)" || rc_deg=$?
    rid_deg="$(iso_run_id "$out_deg")"
    ld="$(iso_ledger_line "$d" "${rid_deg:-none}")"

    # THE EXIT CODE IS THE CLAIM: same in both isolation states, and the value
    # the suite's own outcome dictates.
    [[ "$rc_iso" -eq "$want_rc" ]] \
      || { log_info "TEST-106($outcome): the isolated run exited $rc_iso (want $want_rc)"; ok=0; }
    [[ "$rc_deg" -eq "$want_rc" ]] \
      || { log_info "TEST-106($outcome): the DEGRADED run exited $rc_deg (want $want_rc — degrading isolation must not change the verdict)"; ok=0; }

    # SURFACE 1 — the run's own NOTE lines.
    grep -qF 'Isolation: every suite runs isolated' <<<"$out_iso" \
      || { log_info "TEST-106($outcome) surface 1: the isolated run did not say so: $out_iso"; ok=0; }
    grep -qF 'Isolation: every suite runs degraded (AAI_TEST_ISOLATION=0)' <<<"$out_deg" \
      || { log_info "TEST-106($outcome) surface 1: the degraded run did not say so: $out_deg"; ok=0; }
    # SURFACE 2 — the summary accounting line.
    iso_expect_counts "TEST-106($outcome) surface 2 isolated" "$out_iso" 2 2 0 || ok=0
    iso_expect_counts "TEST-106($outcome) surface 2 degraded" "$out_deg" 0 2 2 || ok=0
    # SURFACE 3 — the ledger record, read per run above.
    [[ -n "$li" ]] || { log_info "TEST-106($outcome) surface 3: no ledger record for the isolated run (run_id=${rid_iso:-<none>})"; ok=0; }
    [[ -n "$ld" ]] || { log_info "TEST-106($outcome) surface 3: no ledger record for the degraded run (run_id=${rid_deg:-<none>})"; ok=0; }
    [[ "$(iso_json_int "$li" suites_isolated)" == "2" && "$(iso_json_int "$li" suites_degraded)" == "0" ]] \
      || { log_info "TEST-106($outcome) surface 3: the isolated run's ledger record does not say so: $li"; ok=0; }
    [[ "$(iso_json_int "$ld" suites_isolated)" == "0" && "$(iso_json_int "$ld" suites_degraded)" == "2" ]] \
      || { log_info "TEST-106($outcome) surface 3: the degraded run's ledger record does not say so: $ld"; ok=0; }
  done

  [[ $ok -eq 1 ]] && log_pass "TEST-106 a fully degraded run differs from a fully isolated one in the NOTE lines, the summary line and the ledger record, while the exit code stays the suite's own — 0 for a passing suite and 1 for a failing one in BOTH isolation states" \
    || log_fail "TEST-106 degraded is visible but never fatal"
}

# ---------------------------------------------------------------------------
# TEST-107 (Spec-AC-05) — the ad hoc funnel says the same two words about
# itself, so the two funnels cannot be read as disagreeing. And it stays SILENT
# where isolation does not apply: a build (isolating it would throw the
# artifact away, TEST-005(d)) and the framework invocation itself (which reports
# for its own suites, and whose ledger must land in the real tree, TEST-005(f)).
# A status line on every build is a line the operator learns to skip.
# ---------------------------------------------------------------------------
test_107_the_wrapper_reports_its_own_isolation_status() {
  local d ok=1 rc=0 err
  d="$(new_fixture)" || return
  build_framework_repo "$d"
  write_fixture_suite "$d" wstatus 'echo wstatus; exit "${1:-0}"'
  commit_fixture_repo "$d" || { log_fail "TEST-107 fixture repo init failed"; return; }

  # (a) an isolated suite run says `isolated`, and the exit code is its own.
  err="$( ( cd "$d" && AAI_TEST_ISOLATION=1 AAI_FRICTION_CAPTURE=0 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-wstatus.sh 0 ) 2>&1 >/dev/null )" || rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-107(a): exit=$rc (want the command's own 0)"; ok=0; }
  grep -qF 'AAI-ISOLATION: isolated' <<<"$err" \
    || { log_info "TEST-107(a): an isolated suite run said nothing about it: $err"; ok=0; }
  grep -qF 'AAI-ISOLATION: degraded' <<<"$err" \
    && { log_info "TEST-107(a): an isolated suite run ALSO claimed degraded: $err"; ok=0; }

  # (b) the same run with isolation off says `degraded` and names the reason,
  #     and the exit code is still the command's own — 7, not 0.
  rc=0
  err="$( ( cd "$d" && AAI_TEST_ISOLATION=0 AAI_FRICTION_CAPTURE=0 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-wstatus.sh 7 ) 2>&1 >/dev/null )" || rc=$?
  [[ "$rc" -eq 7 ]] || { log_info "TEST-107(b): exit=$rc (want the command's own 7 — the wrapper contract is untouched)"; ok=0; }
  grep -qF 'AAI-ISOLATION: degraded - AAI_TEST_ISOLATION=0' <<<"$err" \
    || { log_info "TEST-107(b): a degraded suite run did not say so, or named the wrong reason: $err"; ok=0; }

  # (c) a NON-suite command says nothing: isolation was never meant to cover it.
  rc=0
  err="$( ( cd "$d" && AAI_TEST_ISOLATION=1 AAI_FRICTION_CAPTURE=0 bash .aai/scripts/aai-run-tests.sh sh -c 'printf built > iso-status-artifact.txt' ) 2>&1 >/dev/null )" || rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-107(c): exit=$rc (want 0)"; ok=0; }
  grep -qF 'AAI-ISOLATION:' <<<"$err" \
    && { log_info "TEST-107(c): a non-suite command reported an isolation status it was never given: $err"; ok=0; }
  # Vacuity guard: the command must actually have run, or (c) is vacuous.
  [[ "$(cat "$d/iso-status-artifact.txt" 2>/dev/null)" == "built" ]] \
    || { log_info "TEST-107(c): the non-suite command did not run, so the arm proves nothing"; ok=0; }

  # (d) the genuine framework invocation says nothing HERE — it reports for its
  #     own suites, and two funnels reporting one run is how they start to
  #     disagree.
  rc=0
  err="$( ( cd "$d" && AAI_TEST_ISOLATION=1 AAI_FRICTION_CAPTURE=0 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh ) 2>&1 >/dev/null )" || rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-107(d): the framework through the wrapper exited $rc (want 0)"; ok=0; }
  grep -qF 'AAI-ISOLATION:' <<<"$err" \
    && { log_info "TEST-107(d): the wrapper reported an isolation status for the framework, which reports for itself: $err"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-107 the wrapper says 'isolated' for an isolated suite run and 'degraded - AAI_TEST_ISOLATION=0' when it is off, in the framework's own two words, stays silent for a non-suite command and for the framework invocation, and leaves exit 0 and exit 7 untouched" \
    || log_fail "TEST-107 the wrapper reports its own isolation status"
}

# ===========================================================================
# TEST-108..113 (spec-a-half-seeded-checkout-says-it-is-isolated)
#
# TEST-101..107 above prove a run says whether isolation ARMED. These prove it
# says whether the disposable checkout was completely BUILT — the same "nothing
# counts it" defect one axis over. `isolated` stays TRUE for a half-seeded run
# and every arm below asserts that it does, because folding the two together
# would make the word untrue and would make a future CI grep on `degraded` fire
# where nothing could reach the shipping repository.
#
# Numbered from 108 so SPEC-0138's and SPEC-0144's ids are untouched.
#
# THE LEVERS ARE REAL, never a mutation of the fixture's framework copy (SPEC-0144
# D2's rule). All three were measured on git 2.50.1 before being used here:
#   step 1  a smudge-only `filter` attribute (no `clean`) makes the disposable
#           checkout differ from the index, so the working-tree patch cannot
#           apply — `error: … patch does not apply`, rc 1. The git-lfs shape.
#           The smudge COMMAND itself rides in as `GIT_CONFIG_KEY_n`/
#           `GIT_CONFIG_VALUE_n` environment variables on the outer run, not as
#           `.git/config` (spec-isolation-shares-the-shipping-git D1): a linked
#           worktree shares the shipping repository's LOCAL config, but the
#           disposable checkout is now a separate `git clone`, which does not —
#           the same non-inheritance Spec-AC-02 relies on. An environment
#           variable is inherited by every git subprocess in the run regardless
#           of which repository it targets, so the smudge still fires on the
#           checkout's OWN clone-and-checkout step under either mechanism,
#           while the shipping fixture's own working copy (written by `printf`,
#           never checked out) stays unsmudged either way. Measured rejected
#           alternatives for making the SAME divergence purely from committed
#           content (so no environment injection would be needed): the `eol`
#           and `ident` attributes are both attribute-compensated by
#           `git apply` itself (it reverses them before matching context), so
#           neither one ever breaks the apply; a file-to-directory swap
#           (measured — git apply SUCCEEDS, so it proves nothing); and a
#           post-checkout hook chmodding the checkout read-only (works, rc 128,
#           but it breaks steps 2 and 3 in the same run and so cannot isolate
#           step 1).
#   steps   a `chmod 000` source file. `git ls-files --others` and `test -f` only
#   2 + 3   stat, so the file is still SELECTED for copying, and `cp -p` then
#           cannot read it (measured rc 1).
#
# AND EVERY FIXTURE GIVES ALL THREE STEPS GENUINE WORK. On the real repository
# step 2 copies ZERO files today, so a lever that "breaks" a no-op proves
# nothing: each fixture commits a baseline and THEN creates an uncommitted
# tracked edit, an untracked file and a gitignored seed file. TEST-108 asserts
# all three ARRIVED inside the checkout, so the control is a proof of work rather
# than an absence of noise, and TEST-109/110/111 each assert their own artifact
# did NOT arrive, so the lever is proven to have removed content and not merely
# to have printed a warning.

# seed_status_fixture <dir> <evid> <mode> [t_one_exit] — a committed fixture repo
# with two suites, real work at all three seeding steps, and the lever for <mode>
# armed. <mode> is clean | step1 | step2 | step3.
#
# The t-one suite reports what it can SEE from inside its own checkout, which is
# what turns every arm below from "a warning was printed" into "content was lost".
seed_status_fixture() {
  local d="$1" evid="$2" mode="$3" t_one_exit="${4:-0}"
  build_framework_repo "$d"
  printf 'tests/skills/results/\ndocs/ai/tests/test-runs.jsonl\ndocs/ai/STATE.yaml\n' > "$d/.gitignore"
  # The step-1 lever, committed so the disposable checkout inherits it.
  [[ "$mode" == "step1" ]] && printf 'tracked.txt filter=mangle\n' > "$d/.gitattributes"
  write_fixture_suite "$d" t-one "
tail -n 1 \"\$R/tracked.txt\" > '$evid/saw-tracked.txt' 2>/dev/null || : > '$evid/saw-tracked.txt'
cat \"\$R/untracked-seed.txt\" > '$evid/saw-untracked.txt' 2>/dev/null || : > '$evid/saw-untracked.txt'
cat \"\$R/docs/ai/STATE.yaml\" > '$evid/saw-seed.txt' 2>/dev/null || : > '$evid/saw-seed.txt'
echo one
exit $t_one_exit"
  write_fixture_suite "$d" t-two 'echo two; exit 0'
  commit_fixture_repo "$d" || return 1
  # The smudge COMMAND is NOT set here as local `.git/config` — it rides in as
  # GIT_CONFIG_KEY_n/GIT_CONFIG_VALUE_n environment variables on the run
  # instead (seed_run_step1_env below), because a disposable checkout no
  # longer shares the shipping repository's local config (D1). Only the
  # committed `.gitattributes` filter DECLARATION lives here.
  # STEP 1 has work: an uncommitted edit to a tracked file.
  printf 'baseline\nedited-in-the-working-tree\n' > "$d/tracked.txt"
  # STEP 2 has work: an untracked, not-ignored file.
  printf 'untracked payload\n' > "$d/untracked-seed.txt"
  # STEP 3 has work: a gitignored per-dev file, named through the seed list.
  mkdir -p "$d/docs/ai"
  printf 'marker-42\n' > "$d/docs/ai/STATE.yaml"
  return 0
}

# seed_run <fixture> [extra env assignments...] — every fixture run states
# AAI_TEST_ISOLATION and AAI_TEST_ISOLATION_SEED explicitly. Inheriting either is
# the filed defect `fu-isolation-suite-not-hermetic`: with AAI_TEST_ISOLATION=0
# exported (a legitimate operator action) an arm that inherited it would measure
# a run that never took the path it names.
seed_run() {
  local fixture="$1"
  shift
  env AAI_TEST_ISOLATION=1 AAI_TEST_ISOLATION_SEED='docs/ai/STATE.yaml' "$@" \
    bash "$fixture/tests/skills/test-framework.sh" 2>&1 | strip_ansi
}

# SEED_STEP1_ENV — the step-1 smudge lever's command, as GIT_CONFIG_KEY_n/
# GIT_CONFIG_VALUE_n environment assignments for `seed_run` (see the comment
# above `seed_status_fixture` for why an environment variable and not
# `.git/config` post-D1). Defined once so TEST-109 states its exact shape
# rather than re-deriving it inline.
SEED_STEP1_ENV=(
  'GIT_CONFIG_COUNT=1'
  'GIT_CONFIG_KEY_0=filter.mangle.smudge'
  'GIT_CONFIG_VALUE_0=sed s/baseline/MANGLED/'
)

# seed_summary_line <output> — the ONE unconditional accounting line, matched by
# SHAPE so a line that exists but has stopped carrying numbers fails loudly.
seed_summary_line() {
  grep -E 'Seeding: [0-9]+/[0-9]+ suite\(s\) fully seeded; [0-9]+ partial; [0-9]+ skipped' <<<"$1" | tail -n 1
}

# seed_expect_counts <label> <output> <seeded> <total> <partial> <skipped>
# Vacuity-guarded both ways: an ABSENT line fails, and a line whose numbers
# differ fails naming both.
seed_expect_counts() {
  local label="$1" out="$2"
  local want="Seeding: $3/$4 suite(s) fully seeded; $5 partial; $6 skipped"
  local got
  got="$(seed_summary_line "$out")"
  if [[ -z "$got" ]]; then
    log_info "$label: NO seeding accounting line in the summary at all (the line must print on EVERY run, including the all-clear)"
    return 1
  fi
  if [[ "$got" != *"$want" ]]; then
    log_info "$label: summary said [$got], want a line ending [$want]"
    return 1
  fi
  return 0
}

# seed_make_unreadable <path> <label> — arm the steps 2/3 lever, and refuse to
# pretend when it is unavailable. chmod denies nothing to root, so an arm that
# assumed it worked would measure a perfectly seeded run and call it a bug. Same
# shape as TEST-004(d)'s missing-perl branch: NOT COVERED, never a false green.
seed_make_unreadable() {
  chmod 000 "$1" 2>/dev/null
  if cat "$1" >/dev/null 2>&1; then
    log_info "$2: '$1' is still readable after chmod 000 — this user is not denied by file mode (running as root?), so no copy can be made to fail; NOT COVERED on this machine"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# TEST-108 (Spec-AC-01, Spec-AC-03) — THE UNMUTATED CONTROL, on a fixture where
# every seeding step HAS WORK TO DO. It asserts the work was actually done — the
# uncommitted edit, the untracked file and the gitignored seed file are all read
# back from inside the disposable checkout — and then that the run says so, on a
# line that prints when nothing went wrong.
# ---------------------------------------------------------------------------
test_108_the_fully_seeded_run_states_its_seeding_status() {
  local d evid out rc=0 ok=1
  d="$(new_fixture)" || return
  evid="$(new_fixture)" || return
  seed_status_fixture "$d" "$evid" clean || { log_fail "TEST-108 fixture repo init failed"; return; }

  # The fixture must really have work at all three steps, or the control is a
  # statement about three no-ops.
  git -C "$d" diff HEAD --quiet \
    && { log_info "TEST-108: the fixture has an EMPTY working-tree diff, so seeding step 1 had nothing to do and the control proves nothing"; ok=0; }
  [[ -n "$(git -C "$d" ls-files --others --exclude-standard)" ]] \
    || { log_info "TEST-108: the fixture has NO untracked files, so seeding step 2 had nothing to do and the control proves nothing"; ok=0; }
  git -C "$d" check-ignore -q docs/ai/STATE.yaml \
    || { log_info "TEST-108: the fixture's seed path is not gitignored, so step 3 is not the step that carries it and the control proves nothing"; ok=0; }

  out="$(seed_run "$d")" || rc=$?

  [[ "$rc" -eq 0 ]] || { log_info "TEST-108: framework exit=$rc (want 0): $out"; ok=0; }
  grep -qE 'Passed: +2 \(100%\)' <<<"$out" \
    || { log_info "TEST-108: the fixture suites did not all run and pass: $out"; ok=0; }
  # THE PROOF OF WORK: all three seeded artifacts arrived in the checkout.
  [[ "$(cat "$evid/saw-tracked.txt" 2>/dev/null)" == "edited-in-the-working-tree" ]] \
    || { log_info "TEST-108: step 1's uncommitted edit did not reach the checkout (suite saw '$(cat "$evid/saw-tracked.txt" 2>/dev/null)')"; ok=0; }
  [[ "$(cat "$evid/saw-untracked.txt" 2>/dev/null)" == "untracked payload" ]] \
    || { log_info "TEST-108: step 2's untracked file did not reach the checkout (suite saw '$(cat "$evid/saw-untracked.txt" 2>/dev/null)')"; ok=0; }
  [[ "$(cat "$evid/saw-seed.txt" 2>/dev/null)" == "marker-42" ]] \
    || { log_info "TEST-108: step 3's seed path did not reach the checkout (suite saw '$(cat "$evid/saw-seed.txt" 2>/dev/null)')"; ok=0; }
  seed_expect_counts "TEST-108" "$out" 2 2 0 0 || ok=0
  iso_expect_counts "TEST-108 (the isolation axis is untouched)" "$out" 2 2 0 || ok=0
  grep -qF "Seeding: 'aai-t-one' —" <<<"$out" \
    && { log_info "TEST-108: a fully seeded run emitted a per-suite seeding NOTE: $out"; ok=0; }
  grep -qF 'PARTLY SEEDED' <<<"$out" \
    && { log_info "TEST-108: a fully seeded run emitted the partly-seeded WARNING line: $out"; ok=0; }
  grep -qF 'Seeding: ACCOUNTING BROKEN' <<<"$out" \
    && { log_info "TEST-108: the seeding accounting invariant did not hold: $out"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-108 a run whose three seeding steps all had work to do proves all three arrived inside the disposable checkout and prints 'Seeding: 2/2 suite(s) fully seeded; 0 partial; 0 skipped' with no NOTE (the unmutated control for TEST-109..111)" \
    || log_fail "TEST-108 the fully seeded run states its seeding status"
}

# ---------------------------------------------------------------------------
# TEST-109 (Spec-AC-01, Spec-AC-02) — SEEDING STEP 1 ALONE: the working-tree diff
# cannot be replayed. AC-002 lives here as much as AC-001: the isolation line on
# the SAME run must still read 2/2 isolated, because the suites really did run in
# a disposable tree. The seeding line carries the whole difference.
# ---------------------------------------------------------------------------
test_109_the_unreplayable_diff_is_reported() {
  local d evid out rc=0 ok=1
  d="$(new_fixture)" || return
  evid="$(new_fixture)" || return
  seed_status_fixture "$d" "$evid" step1 || { log_fail "TEST-109 fixture repo init failed"; return; }

  out="$(seed_run "$d" "${SEED_STEP1_ENV[@]}")" || rc=$?

  [[ "$rc" -eq 0 ]] || { log_info "TEST-109: framework exit=$rc (want 0 — a failed seed must not abort the run): $out"; ok=0; }
  grep -qE 'Passed: +2 \(100%\)' <<<"$out" \
    || { log_info "TEST-109: the suites did not all run and pass, so the failed seed aborted something it must not: $out"; ok=0; }
  grep -qF "Seeding: 'aai-t-one' — the working-tree diff could not be replayed" <<<"$out" \
    || { log_info "TEST-109: step 1's failure was not reported by name: $out"; ok=0; }
  # THE LOSS IS REAL, not just announced: the uncommitted edit is absent from the
  # checkout the suite ran in.
  [[ "$(cat "$evid/saw-tracked.txt" 2>/dev/null)" != "edited-in-the-working-tree" ]] \
    || { log_info "TEST-109: the uncommitted edit reached the checkout anyway, so the lever did not fire and the arm proves nothing"; ok=0; }
  seed_expect_counts "TEST-109" "$out" 0 2 2 0 || ok=0
  grep -qF 'Reason(s): the working-tree diff could not be replayed' <<<"$out" \
    || { log_info "TEST-109: the summary named no reason, or the wrong one: $out"; ok=0; }
  # AC-002: isolation is UNCHANGED. The suites ran in a disposable tree; that
  # stays true however little of the working tree reached it.
  iso_expect_counts "TEST-109 (isolated must NOT become false)" "$out" 2 2 0 || ok=0
  # ATTRIBUTION: exactly one step failed, so the arm is testing the step it names.
  grep -qF 'untracked file(s) could not be copied' <<<"$out" \
    && { log_info "TEST-109: step 2 also failed, so the arm is not isolating step 1: $out"; ok=0; }
  grep -qF 'seed path(s) could not be copied' <<<"$out" \
    && { log_info "TEST-109: step 3 also failed, so the arm is not isolating step 1: $out"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-109 a working-tree diff that cannot be replayed is reported by name, counts every suite partial (0/2 fully seeded; 2 partial; 0 skipped), leaves the isolation line at 2/2 isolated, loses the uncommitted edit for real, and leaves exit 0" \
    || log_fail "TEST-109 the unreplayable diff is reported"
}

# ---------------------------------------------------------------------------
# TEST-110 (Spec-AC-01, Spec-AC-02) — SEEDING STEP 2 ALONE: an untracked file
# cannot be copied. This is the step that currently copies ZERO files on this
# repository, and the one whose failure can remove a brand-new suite from its own
# checkout.
# ---------------------------------------------------------------------------
test_110_the_uncopyable_untracked_file_is_reported() {
  local d evid out rc=0 ok=1
  d="$(new_fixture)" || return
  evid="$(new_fixture)" || return
  seed_status_fixture "$d" "$evid" step2 || { log_fail "TEST-110 fixture repo init failed"; return; }
  if ! seed_make_unreadable "$d/untracked-seed.txt" "TEST-110"; then
    log_uncovered "TEST-110: file mode denies this user nothing (root?), so no copy can be made to fail — the arm did NOT run and is not counted as passing"
    return
  fi
  [[ -n "$(git -C "$d" ls-files --others --exclude-standard)" ]] \
    || { log_info "TEST-110: git no longer lists the unreadable file as untracked, so step 2 would never try to copy it"; ok=0; }

  out="$(seed_run "$d")" || rc=$?

  [[ "$rc" -eq 0 ]] || { log_info "TEST-110: framework exit=$rc (want 0 — a failed copy must not abort the run): $out"; ok=0; }
  grep -qE 'Passed: +2 \(100%\)' <<<"$out" \
    || { log_info "TEST-110: the suites did not all run and pass, so the failed copy aborted something it must not: $out"; ok=0; }
  grep -qF "Seeding: 'aai-t-one' — 1 of 1 untracked file(s) could not be copied into its disposable checkout (first: untracked-seed.txt)" <<<"$out" \
    || { log_info "TEST-110: step 2's failure was not reported with its count and the offending path: $out"; ok=0; }
  [[ -z "$(cat "$evid/saw-untracked.txt" 2>/dev/null)" ]] \
    || { log_info "TEST-110: the untracked file reached the checkout anyway ('$(cat "$evid/saw-untracked.txt" 2>/dev/null)'), so the lever did not fire and the arm proves nothing"; ok=0; }
  seed_expect_counts "TEST-110" "$out" 0 2 2 0 || ok=0
  grep -qF 'Reason(s): an untracked file could not be copied into the disposable checkout' <<<"$out" \
    || { log_info "TEST-110: the summary named no reason, or the wrong one: $out"; ok=0; }
  iso_expect_counts "TEST-110 (isolated must NOT become false)" "$out" 2 2 0 || ok=0
  grep -qF 'diff could not be replayed' <<<"$out" \
    && { log_info "TEST-110: step 1 also failed, so the arm is not isolating step 2: $out"; ok=0; }
  grep -qF 'seed path(s) could not be copied' <<<"$out" \
    && { log_info "TEST-110: step 3 also failed, so the arm is not isolating step 2: $out"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-110 an untracked file that cannot be copied is reported with its count and its path, counts every suite partial (0/2 fully seeded; 2 partial; 0 skipped), leaves the isolation line at 2/2 isolated, is genuinely absent from the checkout, and leaves exit 0" \
    || log_fail "TEST-110 the uncopyable untracked file is reported"
}

# ---------------------------------------------------------------------------
# TEST-111 (Spec-AC-01, Spec-AC-02) — SEEDING STEP 3 ALONE: a seed path cannot be
# copied. The quietest of the three: the suite still runs, finds the file absent
# and turns its assertion into a passing skip, which is what TEST-003 measures
# from the other direction.
# ---------------------------------------------------------------------------
test_111_the_uncopyable_seed_path_is_reported() {
  local d evid out rc=0 ok=1
  d="$(new_fixture)" || return
  evid="$(new_fixture)" || return
  seed_status_fixture "$d" "$evid" step3 || { log_fail "TEST-111 fixture repo init failed"; return; }
  git -C "$d" check-ignore -q docs/ai/STATE.yaml \
    || { log_info "TEST-111: the seed path is not gitignored, so it would arrive through step 2 instead and the arm would test the wrong step"; ok=0; }
  if ! seed_make_unreadable "$d/docs/ai/STATE.yaml" "TEST-111"; then
    log_uncovered "TEST-111: file mode denies this user nothing (root?), so no copy can be made to fail — the arm did NOT run and is not counted as passing"
    return
  fi

  out="$(seed_run "$d")" || rc=$?

  [[ "$rc" -eq 0 ]] || { log_info "TEST-111: framework exit=$rc (want 0 — a failed copy must not abort the run): $out"; ok=0; }
  grep -qE 'Passed: +2 \(100%\)' <<<"$out" \
    || { log_info "TEST-111: the suites did not all run and pass, so the failed copy aborted something it must not: $out"; ok=0; }
  grep -qF "Seeding: 'aai-t-one' — 1 of 1 seed path(s) could not be copied into its disposable checkout (first: docs/ai/STATE.yaml)" <<<"$out" \
    || { log_info "TEST-111: step 3's failure was not reported with its count and the offending path: $out"; ok=0; }
  [[ -z "$(cat "$evid/saw-seed.txt" 2>/dev/null)" ]] \
    || { log_info "TEST-111: the seed path reached the checkout anyway ('$(cat "$evid/saw-seed.txt" 2>/dev/null)'), so the lever did not fire and the arm proves nothing"; ok=0; }
  seed_expect_counts "TEST-111" "$out" 0 2 2 0 || ok=0
  grep -qF 'Reason(s): a seed path could not be copied into the disposable checkout' <<<"$out" \
    || { log_info "TEST-111: the summary named no reason, or the wrong one: $out"; ok=0; }
  iso_expect_counts "TEST-111 (isolated must NOT become false)" "$out" 2 2 0 || ok=0
  grep -qF 'diff could not be replayed' <<<"$out" \
    && { log_info "TEST-111: step 1 also failed, so the arm is not isolating step 3: $out"; ok=0; }
  grep -qF 'untracked file(s) could not be copied' <<<"$out" \
    && { log_info "TEST-111: step 2 also failed, so the arm is not isolating step 3: $out"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-111 a seed path that cannot be copied is reported with its count and its path, counts every suite partial (0/2 fully seeded; 2 partial; 0 skipped), leaves the isolation line at 2/2 isolated, is genuinely absent from the checkout, and leaves exit 0" \
    || log_fail "TEST-111 the uncopyable seed path is reported"
}

# ---------------------------------------------------------------------------
# TEST-112 (Spec-AC-03, Spec-AC-04) — a partly seeded run is VISIBLY different
# from a fully seeded one in all three surfaces, with an exit code that is
# IDENTICAL. The ledger is the surface that survives the scrollback; a summary
# line nobody kept is not an answer to "was that CI run completely built".
# ---------------------------------------------------------------------------
test_112_partly_seeded_is_visible_but_never_fatal() {
  local ok=1 outcome
  for outcome in pass fail; do
    local d evid_ok evid_bad body_exit want_rc out_ok out_bad rc_ok=0 rc_bad=0
    local rid_ok rid_bad l_ok l_bad n_s n_p n_k n_total
    body_exit=0; want_rc=0
    [[ "$outcome" == "fail" ]] && { body_exit=1; want_rc=1; }

    # Two fixtures rather than two runs of one, because the lever is a property
    # of the fixture. The ledger file is removed before each run so the arm can
    # attribute exactly one record: RUN_ID has one-second resolution and two
    # 2-suite runs routinely share it (measured for TEST-106).
    d="$(new_fixture)" || return
    evid_ok="$(new_fixture)" || return
    seed_status_fixture "$d" "$evid_ok" clean "$body_exit" || { log_fail "TEST-112($outcome) fixture repo init failed"; return; }
    rm -f "$d/docs/ai/tests/test-runs.jsonl"
    out_ok="$(seed_run "$d")" || rc_ok=$?
    rid_ok="$(iso_run_id "$out_ok")"
    l_ok="$(iso_ledger_line "$d" "${rid_ok:-none}")"

    local d2
    d2="$(new_fixture)" || return
    evid_bad="$(new_fixture)" || return
    seed_status_fixture "$d2" "$evid_bad" step2 "$body_exit" || { log_fail "TEST-112($outcome) partial fixture repo init failed"; return; }
    if ! seed_make_unreadable "$d2/untracked-seed.txt" "TEST-112($outcome)"; then
      log_uncovered "TEST-112($outcome): file mode denies this user nothing (root?), so no copy can be made to fail — the arm did NOT run and is not counted as passing"
      return
    fi
    rm -f "$d2/docs/ai/tests/test-runs.jsonl"
    out_bad="$(seed_run "$d2")" || rc_bad=$?
    rid_bad="$(iso_run_id "$out_bad")"
    l_bad="$(iso_ledger_line "$d2" "${rid_bad:-none}")"

    # THE EXIT CODE IS THE CLAIM: identical in both seeding states, and the value
    # the suite's own outcome dictates.
    [[ "$rc_ok" -eq "$want_rc" ]] \
      || { log_info "TEST-112($outcome): the fully seeded run exited $rc_ok (want $want_rc)"; ok=0; }
    [[ "$rc_bad" -eq "$want_rc" ]] \
      || { log_info "TEST-112($outcome): the PARTLY SEEDED run exited $rc_bad (want $want_rc — an incomplete seed must not change the verdict)"; ok=0; }

    # SURFACE 1 — the run's own NOTE lines.
    grep -qF "Seeding: 'aai-t-one' —" <<<"$out_ok" \
      && { log_info "TEST-112($outcome) surface 1: the fully seeded run emitted a seeding NOTE: $out_ok"; ok=0; }
    grep -qF "Seeding: 'aai-t-one' — 1 of 1 untracked file(s) could not be copied" <<<"$out_bad" \
      || { log_info "TEST-112($outcome) surface 1: the partly seeded run did not say so: $out_bad"; ok=0; }
    # SURFACE 2 — the summary accounting line, on BOTH runs.
    seed_expect_counts "TEST-112($outcome) surface 2 seeded" "$out_ok" 2 2 0 0 || ok=0
    seed_expect_counts "TEST-112($outcome) surface 2 partial" "$out_bad" 0 2 2 0 || ok=0
    # SURFACE 3 — the ledger record for each run's own run_id.
    [[ -n "$l_ok" ]] || { log_info "TEST-112($outcome) surface 3: no ledger record for the fully seeded run (run_id=${rid_ok:-<none>})"; ok=0; }
    [[ -n "$l_bad" ]] || { log_info "TEST-112($outcome) surface 3: no ledger record for the partly seeded run (run_id=${rid_bad:-<none>})"; ok=0; }
    [[ "$(iso_json_int "$l_ok" suites_seeded)" == "2" && "$(iso_json_int "$l_ok" suites_partly_seeded)" == "0" ]] \
      || { log_info "TEST-112($outcome) surface 3: the fully seeded run's ledger record does not say so: $l_ok"; ok=0; }
    [[ "$(iso_json_int "$l_bad" suites_seeded)" == "0" && "$(iso_json_int "$l_bad" suites_partly_seeded)" == "2" ]] \
      || { log_info "TEST-112($outcome) surface 3: the partly seeded run's ledger record does not say so: $l_bad"; ok=0; }
    # ...and the invariant the three fields are read by.
    n_s="$(iso_json_int "$l_bad" suites_seeded)"
    n_p="$(iso_json_int "$l_bad" suites_partly_seeded)"
    n_k="$(iso_json_int "$l_bad" suites_seed_skipped)"
    n_total="$(iso_json_int "$l_bad" total)"
    [[ -n "$n_s" && -n "$n_p" && -n "$n_k" ]] \
      || { log_info "TEST-112($outcome): the ledger record is missing one of the three seeding fields: $l_bad"; ok=0; }
    [[ -n "$n_total" && -n "$n_k" && $((n_s + n_p + n_k)) -eq "$n_total" ]] \
      || { log_info "TEST-112($outcome): the record breaks seeded+partly_seeded+seed_skipped==total (${n_s:-?} + ${n_p:-?} + ${n_k:-?} != ${n_total:-<absent>}): $l_bad"; ok=0; }
  done

  [[ $ok -eq 1 ]] && log_pass "TEST-112 a partly seeded run differs from a fully seeded one in the NOTE lines, the summary line and the ledger record, the three ledger fields sum to total, and the exit code stays the suite's own — 0 for a passing suite and 1 for a failing one in BOTH seeding states" \
    || log_fail "TEST-112 partly seeded is visible but never fatal"
}

# ---------------------------------------------------------------------------
# TEST-113 (Spec-AC-05) — the ad hoc funnel reports the same axis in the same
# three words, so the two funnels cannot be read as disagreeing. It stays SILENT
# where isolation does not apply, for the reason TEST-107 gives: a status line on
# every build is a line the operator learns to skip.
# ---------------------------------------------------------------------------
test_113_the_wrapper_reports_its_own_seeding_status() {
  local d evid ok=1 rc=0 err
  d="$(new_fixture)" || return
  evid="$(new_fixture)" || return
  seed_status_fixture "$d" "$evid" clean || { log_fail "TEST-113 fixture repo init failed"; return; }
  write_fixture_suite "$d" wstatus 'echo wstatus; exit "${1:-0}"'

  # (a) a fully seeded suite run says `seeded`, and the exit code is its own.
  err="$( ( cd "$d" && AAI_TEST_ISOLATION=1 AAI_TEST_ISOLATION_SEED='docs/ai/STATE.yaml' AAI_FRICTION_CAPTURE=0 \
      bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-wstatus.sh 0 ) 2>&1 >/dev/null )" || rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-113(a): exit=$rc (want the command's own 0)"; ok=0; }
  grep -qF 'AAI-SEEDING: seeded' <<<"$err" \
    || { log_info "TEST-113(a): a fully seeded suite run said nothing about it: $err"; ok=0; }
  grep -qF 'AAI-ISOLATION: isolated' <<<"$err" \
    || { log_info "TEST-113(a): the isolation line went missing beside the seeding line: $err"; ok=0; }

  # (b) the same run with an unreadable untracked file says `partial`, names the
  #     step, and STILL says `isolated` — the two axes are independent, which is
  #     the whole point of there being two.
  local d2 evid2 rc2=0 err2
  d2="$(new_fixture)" || return
  evid2="$(new_fixture)" || return
  seed_status_fixture "$d2" "$evid2" step2 || { log_fail "TEST-113(b) fixture repo init failed"; return; }
  write_fixture_suite "$d2" wstatus 'echo wstatus; exit "${1:-0}"'
  if seed_make_unreadable "$d2/untracked-seed.txt" "TEST-113(b)"; then
    err2="$( ( cd "$d2" && AAI_TEST_ISOLATION=1 AAI_TEST_ISOLATION_SEED='docs/ai/STATE.yaml' AAI_FRICTION_CAPTURE=0 \
        bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-wstatus.sh 7 ) 2>&1 >/dev/null )" || rc2=$?
    [[ "$rc2" -eq 7 ]] || { log_info "TEST-113(b): exit=$rc2 (want the command's own 7 — the wrapper contract is untouched)"; ok=0; }
    grep -qF 'AAI-SEEDING: partial - an untracked file could not be copied into the disposable checkout' <<<"$err2" \
      || { log_info "TEST-113(b): a partly seeded suite run did not say so, or named the wrong step: $err2"; ok=0; }
    grep -qF 'AAI-ISOLATION: isolated' <<<"$err2" \
      || { log_info "TEST-113(b): a partly seeded run stopped calling itself isolated — the two axes must not be folded together: $err2"; ok=0; }
  else
    log_info "TEST-113(b): NOT COVERED on this machine"
  fi

  # (c) with isolation off there is no checkout, so seeding says `skipped` rather
  #     than nothing at all.
  local rc3=0 err3
  err3="$( ( cd "$d" && AAI_TEST_ISOLATION=0 AAI_TEST_ISOLATION_SEED='docs/ai/STATE.yaml' AAI_FRICTION_CAPTURE=0 \
      bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-wstatus.sh 0 ) 2>&1 >/dev/null )" || rc3=$?
  [[ "$rc3" -eq 0 ]] || { log_info "TEST-113(c): exit=$rc3 (want 0)"; ok=0; }
  grep -qF 'AAI-SEEDING: skipped - no disposable checkout was made' <<<"$err3" \
    || { log_info "TEST-113(c): a run with no checkout said nothing about its seeding: $err3"; ok=0; }
  grep -qF 'AAI-ISOLATION: degraded' <<<"$err3" \
    || { log_info "TEST-113(c): the degraded isolation line that explains the skip is missing: $err3"; ok=0; }

  # (d) a NON-suite command and (e) the genuine framework invocation say nothing
  #     on either axis.
  local rc4=0 err4
  err4="$( ( cd "$d" && AAI_TEST_ISOLATION=1 AAI_TEST_ISOLATION_SEED='docs/ai/STATE.yaml' AAI_FRICTION_CAPTURE=0 \
      bash .aai/scripts/aai-run-tests.sh sh -c 'printf built > seed-status-artifact.txt' ) 2>&1 >/dev/null )" || rc4=$?
  [[ "$rc4" -eq 0 ]] || { log_info "TEST-113(d): exit=$rc4 (want 0)"; ok=0; }
  grep -qF 'AAI-SEEDING:' <<<"$err4" \
    && { log_info "TEST-113(d): a non-suite command reported a seeding status it was never given: $err4"; ok=0; }
  [[ "$(cat "$d/seed-status-artifact.txt" 2>/dev/null)" == "built" ]] \
    || { log_info "TEST-113(d): the non-suite command did not run, so the arm proves nothing"; ok=0; }

  local rc5=0 err5
  err5="$( ( cd "$d" && AAI_TEST_ISOLATION=1 AAI_TEST_ISOLATION_SEED='docs/ai/STATE.yaml' AAI_FRICTION_CAPTURE=0 \
      bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh ) 2>&1 >/dev/null )" || rc5=$?
  [[ "$rc5" -eq 0 ]] || { log_info "TEST-113(e): the framework through the wrapper exited $rc5 (want 0)"; ok=0; }
  grep -qF 'AAI-SEEDING:' <<<"$err5" \
    && { log_info "TEST-113(e): the wrapper reported a seeding status for the framework, which reports per suite for itself: $err5"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-113 the wrapper says 'seeded' for a fully seeded suite run, 'partial' naming the step when an untracked file cannot be copied (while still saying isolated), 'skipped' when no checkout was made, stays silent for a non-suite command and for the framework invocation, and leaves exit 0 and exit 7 untouched" \
    || log_fail "TEST-113 the wrapper reports its own seeding status"
}

# ===========================================================================
# TEST-201..208 (spec-isolation-shares-the-shipping-git)
#
# The arms above prove a suite cannot reach the shipping WORKING TREE or say
# so honestly. These prove the disposable checkout does not share the
# shipping repository's git ADMINISTRATIVE surface at all — the gap D1..D3
# close: a worktree resolves `git rev-parse --git-common-dir` straight into
# `<shipping>/.git`, so refs, `.git/config` and `.git/hooks` are reachable in
# one command even though the working tree is a copy.
#
# Numbered from 201 so SPEC-0138's TEST-001..006 and SPEC-0144/0145's
# TEST-101..113 keep their ids in this file.
# ===========================================================================

# ---------------------------------------------------------------------------
# TEST-201 (Spec-AC-01) — the checkout's OWN `git rev-parse --git-common-dir`,
# resolved through `pwd -P` exactly as D3 resolves it, lands inside the
# disposable base and is not the fixture repository's own common dir. RED on
# the pre-change tree: a worktree's common dir IS the fixture repository's.
# ---------------------------------------------------------------------------
test_201_common_dir_resolves_outside_the_shipping_repo() {
  local d evid tmphome out rc=0 ok=1 ship_common seen tmphome_real
  d="$(new_fixture)" || return
  evid="$d.evid"
  mkdir -p "$evid"
  register_workdir "$evid"
  tmphome="$(new_fixture)" || return
  build_framework_repo "$d"
  write_fixture_suite "$d" t-common "
cd \"\$R\" || exit 1
cd \"\$(git rev-parse --git-common-dir)\" 2>/dev/null || exit 1
pwd -P > '$evid/common.txt'
exit 0"
  commit_fixture_repo "$d" || { log_fail "TEST-201 fixture repo init failed"; return; }
  ship_common="$(cd "$d" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"

  out="$(TMPDIR="$tmphome" bash "$d/tests/skills/test-framework.sh" 2>&1 | strip_ansi)" || rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-201: framework exit=$rc (want 0): $out"; ok=0; }
  [[ -s "$evid/common.txt" ]] || { log_info "TEST-201: the fixture never recorded its resolved common dir: $out"; ok=0; }
  seen="$(cat "$evid/common.txt" 2>/dev/null)"
  tmphome_real="$(cd "$tmphome" && pwd -P)"
  case "$seen" in
    "$tmphome_real"/*) ;;
    *) log_info "TEST-201: the resolved common dir [$seen] is not inside the disposable base [$tmphome_real]"; ok=0 ;;
  esac
  [[ -n "$seen" && "$seen" != "$ship_common" ]] \
    || { log_info "TEST-201: the resolved common dir [$seen] equals the fixture repository's own common dir [$ship_common]"; ok=0; }
  iso_expect_counts "TEST-201" "$out" 1 1 0 || ok=0

  [[ $ok -eq 1 ]] && log_pass "TEST-201 the disposable checkout's own git-common-dir resolves inside the disposable base, never into the fixture repository" \
    || log_fail "TEST-201 the disposable checkout's git common directory does not resolve into the shipping repository"
}

# ---------------------------------------------------------------------------
# TEST-202 (Spec-AC-02) — a config key, a ref and a hooks file written from
# inside the checkout are all unreadable from the shipping repository
# afterwards. The hook path is resolved with `git rev-parse --git-path hooks`
# from INSIDE the checkout, exactly as a real suite would, so under a
# worktree it writes into the SHARED hooks directory the same one command
# away. RED on the pre-change tree for all three surfaces.
# ---------------------------------------------------------------------------
test_202_config_ref_and_hook_are_unreachable_after() {
  local d out rc=0 ok=1 hookdir
  d="$(new_fixture)" || return
  build_framework_repo "$d"
  write_fixture_suite "$d" t-write "
git -C \"\$R\" config --local isolation.probe leaked-value
git -C \"\$R\" update-ref refs/isolation-probe HEAD
hookdir=\"\$(git -C \"\$R\" rev-parse --git-path hooks)\"
mkdir -p \"\$hookdir\" 2>/dev/null
printf '#!/bin/sh\nexit 0\n' > \"\$hookdir/isolation-probe.sh\" 2>/dev/null
exit 0"
  commit_fixture_repo "$d" || { log_fail "TEST-202 fixture repo init failed"; return; }

  out="$(bash "$d/tests/skills/test-framework.sh" 2>&1 | strip_ansi)" || rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-202: framework exit=$rc (want 0): $out"; ok=0; }
  grep -qE 'aai-t-write +PASS' <<<"$out" \
    || { log_info "TEST-202: the writing fixture did not run to a PASS: $out"; ok=0; }
  git -C "$d" config --local --get isolation.probe >/dev/null 2>&1 \
    && { log_info "TEST-202: the config key IS readable from the shipping repository"; ok=0; }
  git -C "$d" rev-parse --verify -q refs/isolation-probe >/dev/null 2>&1 \
    && { log_info "TEST-202: the ref IS readable from the shipping repository"; ok=0; }
  hookdir="$(cd "$d" && git rev-parse --git-path hooks)"
  [[ -f "$d/$hookdir/isolation-probe.sh" ]] \
    && { log_info "TEST-202: the hook file exists in the shipping repository's hooks dir ($d/$hookdir)"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-202 a config key, a ref and a hooks file written from the disposable checkout are all unreadable from the shipping repository afterwards" \
    || log_fail "TEST-202 a config, ref or hook write from the isolated run is unreadable from the shipping repository"
}

# ---------------------------------------------------------------------------
# TEST-203 (Spec-AC-03) — THE MUTATION PROOF. HAZ-RESTORE: the mutation lands
# on the FIXTURE's byte COPY of the framework (already a throwaway file inside
# a disposable git repository), never on tests/skills/test-framework.sh. A
# single, exact substitution reverts iso_create's clone call back to
# `git worktree add --detach`, which is enough to reopen the shared git
# surface and must be caught by the D3 gate: 0 isolated, N degraded, reason
# naming the git surface. RED on the pre-change tree for a second reason: the
# gate does not exist yet, so the (no-op) mutation still reports isolated.
# ---------------------------------------------------------------------------
test_203_the_mutation_proof_gate_catches_a_shared_git_surface() {
  local d out rc=0 ok=1 n=3 i tmp
  d="$(new_fixture)" || return
  build_framework_repo "$d"
  for i in $(seq 1 "$n"); do
    write_fixture_suite "$d" "t-gate$i" 'exit 0'
  done
  commit_fixture_repo "$d" || { log_fail "TEST-203 fixture repo init failed"; return; }

  tmp="$(mktemp "${TMPDIR:-/tmp}/aai-iso-mutate.XXXXXX")" \
    || { log_fail "TEST-203: no scratch file for the mutation"; return; }
  # `mktemp` places this FILE directly under bare $TMPDIR. WORKDIR_REGISTRY's
  # cleanup() only ever `rm -rf`s registered DIRECTORIES (`[[ -d "$d" ]]`
  # guards it) — registering this file's dirname instead of the file itself
  # would hand it the whole system temp directory. Measured: it did, and
  # cleanup() tried to `rm -rf` the host's real /tmp (caught only by
  # "Operation not permitted" on macOS-owned entries). Clean up the file
  # directly instead: a no-op once `mv` below has relocated it away.
  # `&` in a sed REPLACEMENT means "the whole match" — left unescaped, the
  # `2>&1` in the replacement text spliced the ENTIRE original line back into
  # itself, producing `iso_git worktree add ... >/dev/null 2>iso_git clone
  # ...&1` (git then failing on the unrecognised `--local` flag it carried
  # over, not on the gate). Measured. `\&` makes it literal.
  sed 's|iso_git clone --local --no-hardlinks --quiet "$PROJECT_ROOT" "$wt" >/dev/null 2>&1|iso_git worktree add --detach --quiet "$wt" HEAD >/dev/null 2>\&1|' \
    "$d/tests/skills/test-framework.sh" > "$tmp" && mv "$tmp" "$d/tests/skills/test-framework.sh"
  rm -f "$tmp" 2>/dev/null
  grep -qF 'iso_git worktree add --detach --quiet "$wt" HEAD' "$d/tests/skills/test-framework.sh" \
    || { log_fail "TEST-203: the mutation did not take — the sed target has drifted from the real iso_create"; return; }

  out="$(bash "$d/tests/skills/test-framework.sh" 2>&1 | strip_ansi)" || rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-203: framework exit=$rc (want 0 — a degraded run is still a passing run): $out"; ok=0; }
  iso_expect_counts "TEST-203" "$out" 0 "$n" "$n" || ok=0
  grep -qF "the disposable checkout's git surface still resolves to the shipping repository" <<<"$out" \
    || { log_info "TEST-203: the degrade reason does not name the git surface: $out"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-203 THE MUTATION PROOF — a fixture reverted to git worktree add is counted 0 isolated, $n degraded, naming the git-surface reason" \
    || log_fail "TEST-203 a checkout whose git surface is not separated is counted degraded with a named reason"
}

# ---------------------------------------------------------------------------
# TEST-204 (Spec-AC-03) — THE UNMUTATED CONTROL, on the SAME shape of fixture
# as TEST-203: without the mutation the same run reports every suite
# isolated, none degraded, with the ledger's suites_isolated at N.
# ---------------------------------------------------------------------------
test_204_the_unmutated_control_reports_isolated() {
  local d out rc=0 ok=1 n=3 i run_id ledger
  d="$(new_fixture)" || return
  build_framework_repo "$d"
  for i in $(seq 1 "$n"); do
    write_fixture_suite "$d" "t-gate$i" 'exit 0'
  done
  commit_fixture_repo "$d" || { log_fail "TEST-204 fixture repo init failed"; return; }

  out="$(bash "$d/tests/skills/test-framework.sh" 2>&1 | strip_ansi)" || rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-204: framework exit=$rc (want 0): $out"; ok=0; }
  iso_expect_counts "TEST-204" "$out" "$n" "$n" 0 || ok=0
  run_id="$(iso_run_id "$out")"
  [[ -n "$run_id" ]] || { log_info "TEST-204: no RUN_ID could be recovered from the output: $out"; ok=0; }
  if [[ -n "$run_id" ]]; then
    ledger="$(iso_ledger_line "$d" "$run_id")"
    [[ -n "$ledger" ]] || { log_info "TEST-204: no ledger record for run_id=$run_id: $out"; ok=0; }
    [[ "$(iso_json_int "$ledger" suites_isolated)" == "$n" ]] \
      || { log_info "TEST-204: ledger suites_isolated=$(iso_json_int "$ledger" suites_isolated) (want $n): $ledger"; ok=0; }
  fi

  [[ $ok -eq 1 ]] && log_pass "TEST-204 THE UNMUTATED CONTROL — the same shape of fixture unmutated reports $n isolated, 0 degraded, with the ledger's suites_isolated at $n" \
    || log_fail "TEST-204 the unmutated control on the same fixture reports suites_isolated N"
}

# ---------------------------------------------------------------------------
# TEST-205 (Spec-AC-04) — inside the checkout, refs/heads, refs/remotes and
# refs/tags counts match the fixture repository's, `main` and `origin/main`
# both resolve, and the commit count matches. This is the property the
# ref-parity fetch step exists to hold: a bare `git clone --local` alone loses
# every ref but one local head and rewrites `origin/*`.
# ---------------------------------------------------------------------------
test_205_ref_surface_and_history_match_the_shipping_repo() {
  local d evid out rc=0 ok=1
  local want_heads want_tags want_commits want_remotes_list missing
  local got_heads got_tags got_main got_origin got_commits
  d="$(new_fixture)" || return
  evid="$d.evid"
  mkdir -p "$evid"
  register_workdir "$evid"
  build_framework_repo "$d"
  commit_fixture_repo "$d" || { log_fail "TEST-205 fixture repo init failed"; return; }
  ( cd "$d" &&
    git branch second-branch >/dev/null &&
    git tag -a v0.1 -m 'fixture tag' >/dev/null &&
    git update-ref refs/remotes/origin/main "$(git rev-parse HEAD)" )
  write_fixture_suite "$d" t-refs "
{
  git -C \"\$R\" for-each-ref refs/heads | wc -l | tr -d ' '
  git -C \"\$R\" for-each-ref refs/tags | wc -l | tr -d ' '
  git -C \"\$R\" rev-parse --verify -q main >/dev/null 2>&1 && echo yes || echo no
  git -C \"\$R\" rev-parse --verify -q origin/main >/dev/null 2>&1 && echo yes || echo no
  git -C \"\$R\" rev-list --count HEAD
} > '$evid/refs.txt'
git -C \"\$R\" for-each-ref --format='%(refname) %(objectname)' refs/remotes | sort > '$evid/remotes.txt'
exit 0"

  want_heads="$(git -C "$d" for-each-ref refs/heads | wc -l | tr -d ' ')"
  want_tags="$(git -C "$d" for-each-ref refs/tags | wc -l | tr -d ' ')"
  want_commits="$(git -C "$d" rev-list --count HEAD)"
  want_remotes_list="$(git -C "$d" for-each-ref --format='%(refname) %(objectname)' refs/remotes | sort)"

  out="$(bash "$d/tests/skills/test-framework.sh" 2>&1 | strip_ansi)" || rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-205: framework exit=$rc (want 0): $out"; ok=0; }
  [[ -s "$evid/refs.txt" ]] || { log_info "TEST-205: the fixture never recorded its ref surface: $out"; ok=0; }
  if [[ -s "$evid/refs.txt" ]]; then
    { read -r got_heads; read -r got_tags; read -r got_main; read -r got_origin; read -r got_commits; } < "$evid/refs.txt"
    [[ "$got_heads" == "$want_heads" ]] || { log_info "TEST-205: refs/heads count $got_heads (want $want_heads)"; ok=0; }
    [[ "$got_tags" == "$want_tags" ]] || { log_info "TEST-205: refs/tags count $got_tags (want $want_tags)"; ok=0; }
    [[ "$got_main" == "yes" ]] || { log_info "TEST-205: main did not resolve inside the checkout"; ok=0; }
    [[ "$got_origin" == "yes" ]] || { log_info "TEST-205: origin/main did not resolve inside the checkout"; ok=0; }
    [[ "$got_commits" == "$want_commits" ]] || { log_info "TEST-205: HEAD commit count $got_commits (want $want_commits)"; ok=0; }
  fi
  # refs/remotes is a SUPERSET check, not exact-count equality — the D1
  # measurement itself records this (145 shipping vs 182 post-fetch on the
  # real repository): `git clone`'s own default remote-tracking mirroring of
  # the source's LOCAL branches adds entries beyond the shipping repository's
  # own refs/remotes namespace whenever a local branch has no identically
  # named counterpart already there (exactly what `second-branch` is here).
  # What must never happen is LOSING one of the shipping repository's own
  # refs/remotes entries; gaining harmless extras is not a defect.
  if [[ ! -s "$evid/remotes.txt" ]]; then
    log_info "TEST-205: the fixture never recorded its refs/remotes listing: $out"
    ok=0
  else
    missing="$(comm -23 <(printf '%s\n' "$want_remotes_list") "$evid/remotes.txt" 2>/dev/null)"
    [[ -z "$missing" ]] \
      || { log_info "TEST-205: refs/remotes entries present in the shipping repository but missing from the checkout: $missing"; ok=0; }
  fi

  [[ $ok -eq 1 ]] && log_pass "TEST-205 inside the disposable checkout refs/heads and refs/tags counts, main, origin/main and the HEAD commit count all match the fixture repository, and every one of the fixture's own refs/remotes entries is present (extras from clone's own remote-tracking mirroring are not a defect)" \
    || log_fail "TEST-205 the checkout's refs, tags and history match the shipping repository's"
}

# ---------------------------------------------------------------------------
# TEST-206 (Spec-AC-05) — REGRESSION PIN, expected green before this scope's
# change as well as after: the accounting invariant already holds. Not a
# discovery — the spec says so rather than manufacturing a red for it.
# ---------------------------------------------------------------------------
test_206_accounting_invariant_holds_across_a_multi_suite_run() {
  local d out rc=0 ok=1 n=5 i run_id ledger summary s_iso s_deg s_total n_iso n_deg n_total
  d="$(new_fixture)" || return
  build_framework_repo "$d"
  for i in $(seq 1 "$n"); do
    write_fixture_suite "$d" "t-inv$i" 'exit 0'
  done
  commit_fixture_repo "$d" || { log_fail "TEST-206 fixture repo init failed"; return; }

  out="$(bash "$d/tests/skills/test-framework.sh" 2>&1 | strip_ansi)" || rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-206: framework exit=$rc (want 0): $out"; ok=0; }
  summary="$(iso_summary_line "$out")"
  if [[ -z "$summary" ]]; then
    log_info "TEST-206: no isolation summary line: $out"
    ok=0
  else
    s_iso="$(sed -E 's/^.*Isolation: ([0-9]+)\/([0-9]+).*$/\1/' <<<"$summary")"
    s_total="$(sed -E 's/^.*Isolation: ([0-9]+)\/([0-9]+).*$/\2/' <<<"$summary")"
    s_deg="$(sed -E 's/^.*; ([0-9]+) degraded.*$/\1/' <<<"$summary")"
    [[ $((s_iso + s_deg)) -eq "$s_total" && "$s_total" -eq "$n" ]] \
      || { log_info "TEST-206: summary invariant broken: [$summary]"; ok=0; }
  fi

  run_id="$(iso_run_id "$out")"
  [[ -n "$run_id" ]] || { log_info "TEST-206: no RUN_ID recovered: $out"; ok=0; }
  if [[ -n "$run_id" ]]; then
    ledger="$(iso_ledger_line "$d" "$run_id")"
    if [[ -z "$ledger" ]]; then
      log_info "TEST-206: no ledger record for run_id=$run_id"
      ok=0
    else
      n_iso="$(iso_json_int "$ledger" suites_isolated)"
      n_deg="$(iso_json_int "$ledger" suites_degraded)"
      n_total="$(iso_json_int "$ledger" total)"
      [[ -n "$n_iso" && -n "$n_deg" && -n "$n_total" ]] \
        || { log_info "TEST-206: the ledger record is missing a field: $ledger"; ok=0; }
      [[ -n "$n_iso" && -n "$n_deg" && -n "$n_total" && $((n_iso + n_deg)) -eq "$n_total" ]] \
        || { log_info "TEST-206: ledger invariant broken: $ledger"; ok=0; }
    fi
  fi

  [[ $ok -eq 1 ]] && log_pass "TEST-206 (regression pin) suites_isolated plus suites_degraded equals total in both the summary line and the ledger record" \
    || log_fail "TEST-206 the full sweep's accounting invariant holds"
}

# ---------------------------------------------------------------------------
# TEST-207 (Spec-AC-07) — REGRESSION PIN, expected green before this scope's
# change as well as after (D4): the twin carries no isolation logic and
# never will by way of this scope, so it inherits D1..D3 purely by
# delegating to the .sh this scope edits.
# ---------------------------------------------------------------------------
test_207_the_powershell_twin_carries_no_isolation_mechanism() {
  local ps1="$PROJECT_ROOT/.aai/scripts/aai-run-tests.ps1" ok=1
  if [[ ! -f "$ps1" ]]; then
    log_uncovered "TEST-207: $ps1 not found on this machine"
    return
  fi
  /usr/bin/grep -qF 'aai-run-tests.sh' "$ps1" \
    || { log_info "TEST-207: the twin no longer names aai-run-tests.sh"; ok=0; }
  /usr/bin/grep -qi 'git worktree' "$ps1" \
    && { log_info "TEST-207: the twin carries a git worktree invocation of its own"; ok=0; }
  /usr/bin/grep -qi 'git clone' "$ps1" \
    && { log_info "TEST-207: the twin carries a git clone invocation of its own"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-207 (regression pin) aai-run-tests.ps1 names aai-run-tests.sh at least once and carries no git worktree / git clone invocation of its own" \
    || log_fail "TEST-207 the PowerShell entry point inherits the change by delegation and adds no mechanism"
}

# ---------------------------------------------------------------------------
# TEST-208 (Spec-AC-08) — the shipping fixture repository's `.git/worktrees`
# stays absent or empty both DURING (checked from inside the running suite)
# and after a run, and `git worktree list` prints exactly one line
# throughout. RED on the pre-change tree: a live worktree registration exists
# for the whole duration of the suite it belongs to.
# ---------------------------------------------------------------------------
test_208_no_worktree_registration_in_the_shipping_repo() {
  local d evid out rc=0 ok=1 n_lines after
  d="$(new_fixture)" || return
  evid="$d.evid"
  mkdir -p "$evid"
  register_workdir "$evid"
  build_framework_repo "$d"
  write_fixture_suite "$d" t-mid "
if [[ -d '$d/.git/worktrees' ]] && [[ -n \"\$(ls -A '$d/.git/worktrees' 2>/dev/null)\" ]]; then
  echo 'nonempty' > '$evid/mid-worktrees.txt'
else
  echo 'absent-or-empty' > '$evid/mid-worktrees.txt'
fi
git -C '$d' worktree list > '$evid/mid-worktree-list.txt' 2>/dev/null
exit 0"
  commit_fixture_repo "$d" || { log_fail "TEST-208 fixture repo init failed"; return; }

  out="$(bash "$d/tests/skills/test-framework.sh" 2>&1 | strip_ansi)" || rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-208: framework exit=$rc (want 0): $out"; ok=0; }
  [[ -s "$evid/mid-worktree-list.txt" ]] || { log_info "TEST-208: the fixture never recorded a mid-run worktree list: $out"; ok=0; }
  [[ "$(cat "$evid/mid-worktrees.txt" 2>/dev/null)" == "absent-or-empty" ]] \
    || { log_info "TEST-208: .git/worktrees was non-empty WHILE the suite ran"; ok=0; }
  n_lines="$(wc -l < "$evid/mid-worktree-list.txt" | tr -d ' ')"
  [[ "$n_lines" == "1" ]] \
    || { log_info "TEST-208: git worktree list printed $n_lines line(s) mid-run (want exactly 1): $(cat "$evid/mid-worktree-list.txt" 2>/dev/null)"; ok=0; }

  after="$(git -C "$d" worktree list 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$after" == "1" ]] \
    || { log_info "TEST-208: git worktree list printed $after line(s) AFTER the run (want exactly 1)"; ok=0; }
  { [[ ! -d "$d/.git/worktrees" ]] || [[ -z "$(ls -A "$d/.git/worktrees" 2>/dev/null)" ]]; } \
    || { log_info "TEST-208: .git/worktrees is non-empty AFTER the run: $(ls -A "$d/.git/worktrees" 2>/dev/null)"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-208 the shipping repository's .git/worktrees stays absent or empty both during and after the run, and git worktree list prints exactly one line throughout" \
    || log_fail "TEST-208 cleanup writes nothing under the shipping repository's .git"
}

# ---------------------------------------------------------------------------
# TEST-209 (Spec-AC-03, remediation round 1 F-1) — THE MUTATION PROOF for the
# UNRESOLVABLE branch, sub-case (a): the checkout's `.git` is removed right
# after `iso_create` finishes building it, so `iso_separated`'s probe cannot
# resolve a git-common-dir for it at all. D3: "including when the probe cannot
# resolve a path at all" must be counted degraded with the same named reason
# as the EQUAL case. RED against the pre-fix `iso_separated` bytes: `cd ""` is
# a no-op that leaves `pwd -P` reporting the checkout's OWN directory (still
# non-empty, still not equal to the shipping common dir, still not prefixed by
# $PROJECT_ROOT), so the pre-fix gate reads this as separated. HAZ-RESTORE:
# the mutation lands on the FIXTURE's byte copy only.
# ---------------------------------------------------------------------------
test_209_unresolvable_checkout_git_removed_is_degraded() {
  local d out rc=0 ok=1 n=3 i tmp
  d="$(new_fixture)" || return
  build_framework_repo "$d"
  for i in $(seq 1 "$n"); do
    write_fixture_suite "$d" "t-unresolv$i" 'exit 0'
  done
  commit_fixture_repo "$d" || { log_fail "TEST-209 fixture repo init failed"; return; }

  tmp="$(mktemp "${TMPDIR:-/tmp}/aai-iso-mutate.XXXXXX")" \
    || { log_fail "TEST-209: no scratch file for the mutation"; return; }
  sed 's|^  ISO_LAST_WT="$wt"$|  rm -rf "$wt/.git"; ISO_LAST_WT="$wt"|' \
    "$d/tests/skills/test-framework.sh" > "$tmp" && mv "$tmp" "$d/tests/skills/test-framework.sh"
  rm -f "$tmp" 2>/dev/null
  grep -qF 'rm -rf "$wt/.git"' "$d/tests/skills/test-framework.sh" \
    || { log_fail "TEST-209: the mutation did not take — the sed target has drifted from the real iso_create"; return; }

  out="$(bash "$d/tests/skills/test-framework.sh" 2>&1 | strip_ansi)" || rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-209: framework exit=$rc (want 0 — a degraded run is still a passing run): $out"; ok=0; }
  iso_expect_counts "TEST-209" "$out" 0 "$n" "$n" || ok=0
  grep -qF "the disposable checkout's git surface still resolves to the shipping repository" <<<"$out" \
    || { log_info "TEST-209: the degrade reason does not name the git surface: $out"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-209 THE MUTATION PROOF — a checkout whose .git is removed after creation (the probe cannot resolve at all) is counted 0 isolated, $n degraded, naming the git-surface reason" \
    || log_fail "TEST-209 a checkout whose git surface cannot be resolved at all is counted degraded with a named reason"
}

# ---------------------------------------------------------------------------
# TEST-210 (Spec-AC-03, remediation round 1 F-1) — THE MUTATION PROOF for the
# UNRESOLVABLE branch, sub-case (b): the CONCRETE SCAR this scope exists to
# refuse — a linked worktree (the mechanism D1 replaced) whose registration
# under the shipping repository's `.git/worktrees/` has been dropped, measured
# on git 2.50.1 to fail `git rev-parse --git-common-dir` with `fatal: not a
# git repository`. Two mutations on the fixture's byte copy: (1) the same
# clone -> worktree add revert as TEST-203, and (2) the worktree's own admin
# directory (`git -C "$wt" rev-parse --git-dir`, resolved while it is still
# live) is removed right after `iso_create` finishes, deregistering it exactly
# the way the scar state describes. RED against the pre-fix bytes for the same
# reason as TEST-209: `cd ""` stays in the checkout and reports it separated.
# ---------------------------------------------------------------------------
test_210_unresolvable_deregistered_linked_worktree_is_degraded() {
  local d out rc=0 ok=1 n=3 i tmp
  d="$(new_fixture)" || return
  build_framework_repo "$d"
  for i in $(seq 1 "$n"); do
    write_fixture_suite "$d" "t-dereg$i" 'exit 0'
  done
  commit_fixture_repo "$d" || { log_fail "TEST-210 fixture repo init failed"; return; }

  tmp="$(mktemp "${TMPDIR:-/tmp}/aai-iso-mutate.XXXXXX")" \
    || { log_fail "TEST-210: no scratch file for the worktree-add mutation"; return; }
  sed 's|iso_git clone --local --no-hardlinks --quiet "$PROJECT_ROOT" "$wt" >/dev/null 2>&1|iso_git worktree add --detach --quiet "$wt" HEAD >/dev/null 2>\&1|' \
    "$d/tests/skills/test-framework.sh" > "$tmp" && mv "$tmp" "$d/tests/skills/test-framework.sh"
  rm -f "$tmp" 2>/dev/null
  grep -qF 'iso_git worktree add --detach --quiet "$wt" HEAD' "$d/tests/skills/test-framework.sh" \
    || { log_fail "TEST-210: the worktree-add mutation did not take — the sed target has drifted from the real iso_create"; return; }

  tmp="$(mktemp "${TMPDIR:-/tmp}/aai-iso-mutate.XXXXXX")" \
    || { log_fail "TEST-210: no scratch file for the deregistration mutation"; return; }
  sed 's|^  ISO_LAST_WT="$wt"$|  rm -rf "$(git -C "$wt" rev-parse --git-dir 2>/dev/null)"; ISO_LAST_WT="$wt"|' \
    "$d/tests/skills/test-framework.sh" > "$tmp" && mv "$tmp" "$d/tests/skills/test-framework.sh"
  rm -f "$tmp" 2>/dev/null
  grep -qF 'rm -rf "$(git -C "$wt" rev-parse --git-dir 2>/dev/null)"' "$d/tests/skills/test-framework.sh" \
    || { log_fail "TEST-210: the deregistration mutation did not take — the sed target has drifted from the real iso_create"; return; }

  out="$(bash "$d/tests/skills/test-framework.sh" 2>&1 | strip_ansi)" || rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-210: framework exit=$rc (want 0 — a degraded run is still a passing run): $out"; ok=0; }
  iso_expect_counts "TEST-210" "$out" 0 "$n" "$n" || ok=0
  grep -qF "the disposable checkout's git surface still resolves to the shipping repository" <<<"$out" \
    || { log_info "TEST-210: the degrade reason does not name the git surface: $out"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-210 THE MUTATION PROOF — a linked worktree whose registration is dropped after creation (the concrete scar state) is counted 0 isolated, $n degraded, naming the git-surface reason" \
    || log_fail "TEST-210 a deregistered linked worktree is counted degraded with a named reason"
}

# ---------------------------------------------------------------------------
# TEST-211 (Spec-AC-03, remediation round 1 F-1 coverage duty) — THE THIRD
# BRANCH: a checkout whose base directory ends up physically INSIDE
# $PROJECT_ROOT (e.g. a misconfigured TMPDIR) is degraded by the
# `case "$iso_common" in "$PROJECT_ROOT"/*)` arm, with no code mutation at
# all — only TMPDIR is redirected to the fixture repository's OWN resolved
# root, exactly as the validator's own probe reproduced it. HERMETIC BY
# CONSTRUCTION, like TEST-101..107: forced by ENVIRONMENT, not by mutating the
# fixture's byte copy. This branch does not depend on the `cd ""` bug F-1
# fixes, so it is expected GREEN both before and after that fix — it closes a
# coverage gap (no existing arm exercised PREFIX), not a red/green pair. $d is
# resolved with `pwd -P` before use so the comparison is physical-path-to-
# physical-path: the fixture's own PROJECT_ROOT is computed by the identical
# `cd ... && pwd` the real framework uses, so it must start from an
# already-resolved base or the prefix match rests on a macOS
# /var-vs-/private/var spelling mismatch that has nothing to do with the
# property under test.
# ---------------------------------------------------------------------------
test_211_prefix_checkout_under_project_root_is_degraded() {
  local d out rc=0 ok=1 n=3 i
  d="$(new_fixture)" || return
  d="$(cd "$d" 2>/dev/null && pwd -P)" \
    || { log_fail "TEST-211: fixture path could not be resolved"; return; }
  build_framework_repo "$d"
  for i in $(seq 1 "$n"); do
    write_fixture_suite "$d" "t-prefix$i" 'exit 0'
  done
  commit_fixture_repo "$d" || { log_fail "TEST-211 fixture repo init failed"; return; }

  out="$(TMPDIR="$d" bash "$d/tests/skills/test-framework.sh" 2>&1 | strip_ansi)" || rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-211: framework exit=$rc (want 0 — a degraded run is still a passing run): $out"; ok=0; }
  iso_expect_counts "TEST-211" "$out" 0 "$n" "$n" || ok=0
  grep -qF "the disposable checkout's git surface still resolves to the shipping repository" <<<"$out" \
    || { log_info "TEST-211: the degrade reason does not name the git surface: $out"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-211 a checkout whose base lands inside \$PROJECT_ROOT (TMPDIR misconfigured) is counted 0 isolated, $n degraded, naming the git-surface reason" \
    || log_fail "TEST-211 a checkout under \$PROJECT_ROOT is counted degraded with a named reason"
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
  test_101_the_all_clear_run_states_its_isolation_status
  test_102_the_global_probe_degrade_is_counted
  test_103_the_no_checkout_degrade_is_counted
  test_104_the_suite_missing_from_the_checkout_is_counted
  test_105_the_ledger_carries_the_same_two_numbers
  test_106_degraded_is_visible_but_never_fatal
  test_107_the_wrapper_reports_its_own_isolation_status
  test_108_the_fully_seeded_run_states_its_seeding_status
  test_109_the_unreplayable_diff_is_reported
  test_110_the_uncopyable_untracked_file_is_reported
  test_111_the_uncopyable_seed_path_is_reported
  test_112_partly_seeded_is_visible_but_never_fatal
  test_113_the_wrapper_reports_its_own_seeding_status
  test_201_common_dir_resolves_outside_the_shipping_repo
  test_202_config_ref_and_hook_are_unreachable_after
  test_203_the_mutation_proof_gate_catches_a_shared_git_surface
  test_204_the_unmutated_control_reports_isolated
  test_205_ref_surface_and_history_match_the_shipping_repo
  test_206_accounting_invariant_holds_across_a_multi_suite_run
  test_207_the_powershell_twin_carries_no_isolation_mechanism
  test_208_no_worktree_registration_in_the_shipping_repo
  test_209_unresolvable_checkout_git_removed_is_degraded
  test_210_unresolvable_deregistered_linked_worktree_is_degraded
  test_211_prefix_checkout_under_project_root_is_degraded
  echo ""
  # Both halves, because either one alone is a lie on some path: FAILED is
  # blind to a subshell failure, and the registry is blind to a machine where
  # the append itself could not land.
  # Never "All tests passed" while an arm did not run. The tally is the point:
  # a machine where a lever is unavailable must say how much of the suite it
  # actually exercised, or a green here means something different on two hosts
  # and nobody can tell which.
  if [[ "$UNCOVERED" -gt 0 ]]; then
    echo "NOTE: $UNCOVERED arm(s) NOT COVERED on this machine — their lever is unavailable here; the suite exercised less than its full set"
  fi
  if [[ $FAILED -eq 0 && ! -s "$FAILURE_REGISTRY" ]]; then
    if [[ "$UNCOVERED" -gt 0 ]]; then
      echo "All covered tests passed ($UNCOVERED not covered)"
    else
      echo "All tests passed!"
    fi
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
