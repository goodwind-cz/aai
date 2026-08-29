#!/usr/bin/env bash
#
# Test: the skills sweep runs suites CONCURRENTLY at a bounded width, without
# losing a verdict, mis-attributing a tripwire detection, or corrupting the
# append-only run ledger (spec-sweep-runs-in-parallel / CHANGE-0166).
#
# Every arm here drives the REAL tests/skills/test-framework.sh, byte-copied
# into a throwaway git repository, and measures BEHAVIOUR:
#   - concurrency is proven by WALL CLOCK against sleeping fixture suites, not
#     by the presence of an `&` in the source. A grep for parallel constructs
#     is exactly the vacuous probe this scope's own intake had to correct.
#   - attribution is proven by PRODUCING the contention — a suite that really
#     commits into the fixture's shipping repository while two siblings really
#     run beside it — and reading who gets blamed.
#   - append serialisation is proven by real concurrent appenders writing
#     MULTI-LINE records and checking each record came out contiguous, not by
#     asserting that a lock exists.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -uo pipefail

TEST_NAME="aai-sweep-parallel"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

FRAMEWORK="$PROJECT_ROOT/tests/skills/test-framework.sh"
TRIPWIRE_LIB="$PROJECT_ROOT/.aai/scripts/lib/repo-tripwire.sh"
APPEND_LOCK_LIB="$PROJECT_ROOT/.aai/scripts/lib/append-lock.sh"
ASSERT_LIB="$PROJECT_ROOT/tests/skills/lib/assert-payload.sh"

FAILED=0
# Both registries are FILES for the reason test-aai-suite-isolation.sh's header
# spells out: every `new_fixture` call site is a command substitution, so an
# array append or a FAILED=1 inside one is invisible to the parent.
WORKDIR_REGISTRY="$(mktemp "${TMPDIR:-/tmp}/aai-sweep-parallel-registry.XXXXXX")" \
  || { echo "FAIL $TEST_NAME: no workdir registry could be made; refusing to run a suite that would then leak every fixture it creates" >&2; exit 1; }
FAILURE_REGISTRY="$(mktemp "${TMPDIR:-/tmp}/aai-sweep-parallel-failures.XXXXXX")" \
  || { rm -f "$WORKDIR_REGISTRY"; echo "FAIL $TEST_NAME: no failure registry could be made" >&2; exit 1; }

register_workdir() { printf '%s\n' "$1" >> "$WORKDIR_REGISTRY"; }

cleanup() {
  local d
  while IFS= read -r d; do
    [[ -n "$d" && -d "$d" ]] || continue
    rm -rf "$d"
  done < "$WORKDIR_REGISTRY"
  rm -f "$WORKDIR_REGISTRY" "$FAILURE_REGISTRY"
}
trap cleanup EXIT

log_pass() { echo "PASS $*"; }
log_fail() { echo "FAIL $*" >&2; FAILED=1; printf '%s\n' "$*" >> "$FAILURE_REGISTRY"; }
log_skip() { echo "SKIP $*"; exit 42; }
log_info() { echo "  $*"; }
UNCOVERED=0
log_uncovered() { echo "UNCOVERED $*"; UNCOVERED=$((UNCOVERED + 1)); }

strip_ansi() { sed -E "s/$(printf '\033')\[[0-9;]*m//g"; }

check_deps() {
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  [[ -f "$FRAMEWORK" ]] || log_skip "$FRAMEWORK not found"
  [[ -f "$TRIPWIRE_LIB" ]] || log_skip "$TRIPWIRE_LIB not found"
  [[ -f "$APPEND_LOCK_LIB" ]] || log_skip "$APPEND_LOCK_LIB not found"
  [[ -f "$ASSERT_LIB" ]] || log_skip "$ASSERT_LIB not found"
  # shellcheck source=lib/assert-payload.sh
  source "$ASSERT_LIB"
}

new_fixture() {
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/aai-sweep-parallel.XXXXXX" 2>/dev/null)" || {
    log_fail "new_fixture: mktemp -d failed"
    return 1
  }
  # HAZ-CD: absolute and non-empty is CHECKED, never assumed, before any caller
  # can `cd` into it or `rm -rf` it.
  if [[ -z "$d" || "$d" != /* || ! -d "$d" ]]; then
    log_fail "new_fixture: unsafe temp dir '$d'"
    return 1
  fi
  register_workdir "$d"
  echo "$d"
}

# write_fixture_suite <repo> <name> <body> — $R inside the body is the suite's
# OWN resolved project root, exactly as every real suite derives it.
write_fixture_suite() {
  local repo="$1" name="$2" body="$3"
  {
    echo '#!/usr/bin/env bash'
    echo 'set -uo pipefail'
    echo 'R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"'
    echo "$body"
  } > "$repo/tests/skills/test-aai-$name.sh"
}

build_framework_repo() {
  local d="$1"
  mkdir -p "$d/tests/skills" "$d/.aai/scripts/lib" "$d/docs/ai/tests"
  cp "$FRAMEWORK" "$d/tests/skills/test-framework.sh"
  cp "$TRIPWIRE_LIB" "$d/.aai/scripts/lib/repo-tripwire.sh"
  cp "$APPEND_LOCK_LIB" "$d/.aai/scripts/lib/append-lock.sh"
  printf 'baseline\n' > "$d/tracked.txt"
  printf 'tests/skills/results/\ndocs/ai/tests/test-runs.jsonl\n*.aai-lock/\n' > "$d/.gitignore"
}

commit_fixture_repo() {
  local d="$1"
  (
    cd "$d" &&
    git init -q -b main &&
    git config user.email 'sweep-parallel-test@example.com' &&
    git config user.name 'sweep-parallel-test' &&
    git add -A &&
    git commit -q -m 'fixture baseline'
  )
}

# timed_run <repo> <width> — run the fixture framework at a width and echo
# "<elapsed seconds> <exit code>". The clock is the assertion, so it is read
# from the system, never estimated.
timed_run() {
  local repo="$1" width="$2" s e rc=0
  s=$(date +%s)
  ( cd "$repo" && AAI_TEST_PARALLEL="$width" bash "$repo/tests/skills/test-framework.sh" ) >/dev/null 2>&1 || rc=$?
  e=$(date +%s)
  echo "$(( e - s )) $rc"
}

# verdict_set <repo> — every per-suite verdict of the LAST run, one
# `<suite> <PASS|FAIL|SKIP>` line per suite, sorted. This is the artifact
# AC-001's "same pass/fail set" is compared on, byte for byte.
verdict_set() {
  local repo="$1" latest f name
  latest="$(ls -1d "$repo"/tests/skills/results/*/ 2>/dev/null | sort | tail -n 1)"
  [[ -n "$latest" ]] || return 0
  for f in "$latest"*.result; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f" .result)"
    printf '%s %s\n' "$name" "$(cat "$f")"
  done | sort
}

# ---------------------------------------------------------------------------
# TEST-001 (AC-001) — the sweep really runs suites at the width it is given.
#
# Four fixture suites that do nothing but sleep 3 s. Serially that is >= 12 s
# of sleeping; at width 2 it is two waves, >= 6 s and well under 12; at width 4
# it is one wave, >= 3 s and well under 6. The assertion is on the CLOCK, with
# the bands chosen so that no amount of framework overhead can make a slower
# width look like a faster one. A source grep for `&` or `xargs -P` would pass
# on a file that spawned children and then waited for each in turn; this cannot.
# ---------------------------------------------------------------------------
test_001_width_is_honoured_on_the_clock() {
  local d ok=1 i out1 out2 out4 t1 t2 t4 r1 r2 r4
  d="$(new_fixture)" || return
  build_framework_repo "$d"
  for i in a b c e; do
    write_fixture_suite "$d" "t-sleep-$i" "sleep 3
exit 0"
  done
  commit_fixture_repo "$d" || { log_fail "TEST-001 fixture repo init failed"; return; }

  out1="$(timed_run "$d" 1)"; t1="${out1%% *}"; r1="${out1##* }"
  out2="$(timed_run "$d" 2)"; t2="${out2%% *}"; r2="${out2##* }"
  out4="$(timed_run "$d" 4)"; t4="${out4%% *}"; r4="${out4##* }"

  [[ "$r1" -eq 0 && "$r2" -eq 0 && "$r4" -eq 0 ]] \
    || { log_info "TEST-001: a run failed (width1=$r1 width2=$r2 width4=$r4) — the timings below would then be meaningless"; ok=0; }

  # Lower bounds: a width cannot beat its own sleeping.
  [[ "$t1" -ge 12 ]] || { log_info "TEST-001: serial run took ${t1}s for 4x sleep 3 (want >= 12) — the fixture is not sleeping, so the arm proves nothing"; ok=0; }
  [[ "$t4" -ge 3 ]]  || { log_info "TEST-001: width-4 run took ${t4}s (want >= 3) — the suites did not run"; ok=0; }

  # Upper bounds: this is the whole claim. Generous enough for a loaded
  # machine, tight enough that a serialised implementation cannot pass.
  [[ "$t4" -lt 9 ]]  || { log_info "TEST-001: width 4 took ${t4}s for 4 suites of sleep 3 (want < 9) — the suites did not overlap"; ok=0; }
  [[ "$t2" -lt 12 ]] || { log_info "TEST-001: width 2 took ${t2}s for 4 suites of sleep 3 (want < 12) — two waves of two did not overlap"; ok=0; }
  # And the widths are ordered, which no fixed threshold alone can show.
  [[ "$t4" -le "$t2" ]] || { log_info "TEST-001: width 4 (${t4}s) was slower than width 2 (${t2}s)"; ok=0; }
  [[ "$t2" -lt "$t1" ]] || { log_info "TEST-001: width 2 (${t2}s) was not faster than serial (${t1}s)"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-001 (AC-001) the sweep honours its width on the clock: 4x sleep-3 suites took ${t1}s serially, ${t2}s at width 2 and ${t4}s at width 4" \
    || log_fail "TEST-001 (AC-001) width is honoured"
}

# ---------------------------------------------------------------------------
# TEST-002 (AC-001) — the pass/fail SET is identical concurrently and serially.
#
# The fixture carries one of each outcome the framework distinguishes: two
# passes, a failure, a skip (exit 42) and a crash. The two runs' per-suite
# verdict sets are compared BYTE FOR BYTE, and so are the framework's own
# totals and exit code. A faster sweep that quietly loses or invents a verdict
# is worse than a slow one, so this is the arm that makes the speed legitimate.
# ---------------------------------------------------------------------------
test_002_verdict_set_is_identical_serial_and_concurrent() {
  local d ok=1 rc1=0 rc4=0 v1 v4 sum1 sum4
  d="$(new_fixture)" || return
  build_framework_repo "$d"
  write_fixture_suite "$d" t-pass-a 'echo ok; exit 0'
  write_fixture_suite "$d" t-pass-b 'echo ok; exit 0'
  write_fixture_suite "$d" t-fail   'echo "FAIL something"; exit 1'
  write_fixture_suite "$d" t-skip   'echo skipping; exit 42'
  write_fixture_suite "$d" t-crash  'echo boom; exit 7'
  commit_fixture_repo "$d" || { log_fail "TEST-002 fixture repo init failed"; return; }

  ( cd "$d" && AAI_TEST_PARALLEL=1 bash "$d/tests/skills/test-framework.sh" ) >"$d/serial.out" 2>&1 || rc1=$?
  v1="$(verdict_set "$d")"
  sum1="$(strip_ansi < "$d/serial.out" | /usr/bin/grep -E '^\[(INFO|PASS|FAIL|SKIP)\] (Total:|Passed:|Failed:|Skipped:)' || true)"
  rm -rf "$d/tests/skills/results"

  ( cd "$d" && AAI_TEST_PARALLEL=4 bash "$d/tests/skills/test-framework.sh" ) >"$d/par.out" 2>&1 || rc4=$?
  v4="$(verdict_set "$d")"
  sum4="$(strip_ansi < "$d/par.out" | /usr/bin/grep -E '^\[(INFO|PASS|FAIL|SKIP)\] (Total:|Passed:|Failed:|Skipped:)' || true)"

  [[ -n "$v1" ]] || { log_info "TEST-002: the serial run produced no verdicts at all"; ok=0; }
  if [[ "$v1" != "$v4" ]]; then
    log_info "TEST-002: the verdict sets differ."
    log_info "  serial:     $(printf '%s' "$v1" | tr '\n' ';')"
    log_info "  concurrent: $(printf '%s' "$v4" | tr '\n' ';')"
    ok=0
  fi
  [[ "$rc1" -eq "$rc4" ]] || { log_info "TEST-002: framework exit code differs (serial=$rc1 concurrent=$rc4)"; ok=0; }
  [[ "$sum1" == "$sum4" ]] || { log_info "TEST-002: the summary totals differ. serial='$sum1' concurrent='$sum4'"; ok=0; }
  # The fixture must actually contain a red and a skip, or the comparison is
  # comparing five passes and proves nothing about the interesting outcomes.
  assert_payload_contains "$v1" "t-fail FAIL" "TEST-002: the fixture's failing suite was not reported FAIL serially" || ok=0
  assert_payload_contains "$v1" "t-skip SKIP" "TEST-002: the fixture's skipping suite was not reported SKIP serially" || ok=0
  assert_payload_contains "$v1" "t-crash FAIL" "TEST-002: the fixture's crashing suite was not reported FAIL serially" || ok=0

  [[ $ok -eq 1 ]] && log_pass "TEST-002 (AC-001) the per-suite verdict set, the summary totals and the exit code are byte-identical serially and at width 4 across PASS/FAIL/SKIP/crash" \
    || log_fail "TEST-002 (AC-001) same pass/fail set"
}

# ---------------------------------------------------------------------------
# TEST-003 (AC-002) — a tripwire detection is never pinned on a sibling.
#
# THE CONTENTION IS REAL, not simulated. Isolation stays ON — it has to, since
# an unisolated run is serial by construction (TEST-009) — and the writing
# suite escapes it the way a real escape happens: by naming the shipping
# repository's ABSOLUTE PATH instead of resolving its own root. It genuinely
# commits there while two sibling suites are genuinely running beside it, so
# the HEAD move lands inside all three suites' shared window — the interference
# the intake predicted, and observed once.
#
# Two things must both hold, and they pull in opposite directions:
#   1. the violation is still DETECTED (the run is red and names the writer);
#   2. neither sibling is named as having changed the repository.
# Asserting only (2) would be satisfied by a tripwire that stopped detecting,
# which is worse than a slow sweep. Asserting only (1) would be satisfied by
# blaming everybody.
# ---------------------------------------------------------------------------
test_003_a_sibling_is_never_blamed_for_a_concurrent_detection() {
  local d ok=1 rc=0 out
  d="$(new_fixture)" || return
  build_framework_repo "$d"
  write_fixture_suite "$d" t-a-sleeper "sleep 2
exit 0"
  write_fixture_suite "$d" t-b-sleeper "sleep 2
exit 0"
  write_fixture_suite "$d" t-c-writer "
printf 'committed dirt\n' >> '$d/tracked.txt'
git -C '$d' add -A >/dev/null 2>&1
git -C '$d' commit -q -m 'a suite committed into the shipping repo' >/dev/null 2>&1
exit 0"
  commit_fixture_repo "$d" || { log_fail "TEST-003 fixture repo init failed"; return; }

  out="$( ( cd "$d" && AAI_TEST_PARALLEL=3 bash "$d/tests/skills/test-framework.sh" ) 2>&1 | strip_ansi )" || rc=$?

  # (1) still detected, and the writer is named.
  [[ "$rc" -eq 1 ]] || { log_info "TEST-003: the run exited $rc (want 1 — a suite committed into the shipping repository and that must stay red)"; ok=0; }
  assert_payload_contains "$out" "--- TRIPWIRE VIOLATION (aai-t-c-writer) ---" \
    "TEST-003: the suite that actually committed was not reported as the violator" || ok=0
  assert_payload_contains "$out" "HEAD moved" \
    "TEST-003: the HEAD move the fixture performs was not reported at all" || ok=0

  # (2) neither sibling is blamed — not by a violation block, not by a FAIL
  # line. Both spellings are checked because they are two different lies.
  assert_payload_not_contains "$out" "--- TRIPWIRE VIOLATION (aai-t-a-sleeper) ---" \
    "TEST-003: a sibling that only slept was reported as having changed the shipping repository" || ok=0
  assert_payload_not_contains "$out" "--- TRIPWIRE VIOLATION (aai-t-b-sleeper) ---" \
    "TEST-003: a sibling that only slept was reported as having changed the shipping repository" || ok=0
  # Exactly ONE suite failed. Counting is padding-proof where matching a
  # progress line is not, and "one" is the whole claim: blaming the siblings
  # too would read three.
  assert_payload_contains "$out" "Failed:  1 (" \
    "TEST-003: the run did not fail exactly one suite — a shared window blamed more than the writer" || ok=0

  # (3) the mechanism that makes (1) and (2) compatible said so out loud, so an
  # operator reading the log knows the wave was re-run rather than guessing.
  assert_payload_contains "$out" "re-run SERIALLY" \
    "TEST-003: the contended wave was not announced as re-run serially, so nothing explains how attribution was recovered" || ok=0
  assert_payload_contains "$out" "Concurrency: width 3; 1 wave(s) re-run serially" \
    "TEST-003: the summary did not account for the re-attributed wave" || ok=0

  [[ $ok -eq 1 ]] && log_pass "TEST-003 (AC-002) a HEAD move made by one suite during a concurrent wave is still detected, is attributed to the suite that made it, and is pinned on neither of the two siblings that ran beside it" \
    || log_fail "TEST-003 (AC-002) no sibling is blamed"
}

# ---------------------------------------------------------------------------
# TEST-004 (AC-002) — the concurrent window does not stop DETECTING, including
# on the second write to a path the wave has already dirtied.
#
# The twin of TEST-003, and the reason TEST-003 cannot be satisfied by silence:
# a tripwire that answered "clean" for every wave would pass TEST-003's
# no-sibling-blamed half perfectly. The fixture deliberately uses the write the
# design can LOSE — a second append to an already-modified tracked file, whose
# `git status` class cannot move a second time (see the fixture comment below).
# ---------------------------------------------------------------------------
test_004_a_concurrent_wave_still_fails_on_a_working_tree_write() {
  local d ok=1 rc=0 out
  d="$(new_fixture)" || return
  build_framework_repo "$d"
  write_fixture_suite "$d" t-a-quiet 'exit 0'
  write_fixture_suite "$d" t-b-quiet 'exit 0'
  # A SECOND APPEND TO THE SAME TRACKED FILE, deliberately, because that is the
  # case the concurrent design can lose. `git status --porcelain=v1` reports a
  # path's change CLASS: the wave has already left tracked.txt " M", so when the
  # serial re-attribution run appends again the porcelain output is byte-
  # identical and a status-only window reads CLEAN — the wave notices, the
  # re-run un-notices, and the run goes green with the write landed. Measured on
  # the framework's own tripwire fixture before run_wave added the wave's
  # changed paths to the content-hashed set for the duration of the re-run.
  write_fixture_suite "$d" t-c-dirty "
printf 'dirt\n' >> '$d/tracked.txt'
exit 0"
  commit_fixture_repo "$d" || { log_fail "TEST-004 fixture repo init failed"; return; }

  out="$( ( cd "$d" && AAI_TEST_PARALLEL=3 bash "$d/tests/skills/test-framework.sh" ) 2>&1 | strip_ansi )" || rc=$?
  [[ "$rc" -eq 1 ]] || { log_info "TEST-004: the run exited $rc (want 1) — a working-tree write during a concurrent wave went unreported"; ok=0; }
  assert_payload_contains "$out" "--- TRIPWIRE VIOLATION (aai-t-c-dirty) ---" \
    "TEST-004: the suite that wrote tracked.txt was not named" || ok=0
  assert_payload_contains "$out" "tracked.txt" \
    "TEST-004: the path that changed was not named" || ok=0

  [[ $ok -eq 1 ]] && log_pass "TEST-004 (AC-002) a working-tree write inside a concurrent wave is still caught and still fails the run" \
    || log_fail "TEST-004 (AC-002) detection survives concurrency"
}

# ---------------------------------------------------------------------------
# TEST-005 (AC-003) — concurrent appends are serialised, record by record.
#
# Twelve concurrent appenders, each writing a FORTY-LINE record tagged with its
# own id, through aai_locked_append. Serialised, every record comes out as one
# contiguous block of forty identically-tagged lines. Unserialised, the blocks
# interleave — and this is the shape that makes the arm non-vacuous: a
# single-line payload small enough to ride one atomic write() would survive
# without any lock at all, so the arm would pass on an implementation that has
# none. The multi-write record tests the LOCK, not the kernel.
#
# The pre-existing content is also checked to be a byte-exact PREFIX of the
# result, which is the append-only property HAZ-LEDGER is actually about.
# ---------------------------------------------------------------------------
test_005_concurrent_appends_are_serialised() {
  local d ok=1 f i pids=() blocks lines want_lines
  d="$(new_fixture)" || return
  cp "$APPEND_LOCK_LIB" "$d/append-lock.sh"
  f="$d/ledger.jsonl"
  printf 'PRE-EXISTING-1\nPRE-EXISTING-2\n' > "$f"
  cp "$f" "$d/ledger.before"

  for i in $(seq 1 12); do
    (
      # shellcheck source=/dev/null
      . "$d/append-lock.sh"
      args=()
      for _ in $(seq 1 40); do args+=("worker-$i"); done
      aai_locked_append "$f" "${args[@]}"
    ) &
    pids+=("$!")
  done
  for i in "${pids[@]}"; do wait "$i" || true; done

  want_lines=$(( 2 + 12 * 40 ))
  lines=$(wc -l < "$f" | tr -d ' ')
  [[ "$lines" -eq "$want_lines" ]] \
    || { log_info "TEST-005: the ledger has $lines line(s), want $want_lines — an append was lost or duplicated"; ok=0; }

  # No line may be anything but a whole, expected token: an interleaved write
  # shows up as a line carrying two workers' text spliced together.
  local bad
  bad="$(/usr/bin/grep -cvE '^(PRE-EXISTING-[12]|worker-([1-9]|1[0-2]))$' "$f" || true)"
  [[ "$bad" -eq 0 ]] \
    || { log_info "TEST-005: $bad malformed line(s) in the ledger — appends interleaved mid-line"; ok=0; }

  # Each worker's 40 lines must be ONE contiguous run. `uniq -c` collapses runs,
  # so a serialised file yields exactly 12 worker blocks plus the two preamble
  # lines; an interleaved one yields many more.
  blocks="$(tail -n +3 "$f" | uniq -c | wc -l | tr -d ' ')"
  [[ "$blocks" -eq 12 ]] \
    || { log_info "TEST-005: the 12 records came out as $blocks contiguous block(s) — the appends were not serialised"; ok=0; }

  # Append-only, about the BYTES: the file the run started with is still a
  # byte-exact prefix of the file it ended with.
  local pre_bytes
  pre_bytes=$(wc -c < "$d/ledger.before" | tr -d ' ')
  head -c "$pre_bytes" "$f" > "$d/ledger.prefix"
  cmp -s "$d/ledger.before" "$d/ledger.prefix" \
    || { log_info "TEST-005: the pre-existing content is NOT a byte-exact prefix of the result"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-005 (AC-003) twelve concurrent 40-line appends came out as twelve contiguous records, no malformed line, and the pre-existing bytes are still an exact prefix" \
    || log_fail "TEST-005 (AC-003) appends are serialised"
}

# ---------------------------------------------------------------------------
# TEST-006 (AC-003) — two framework runs against one repository leave the run
# ledger whole.
#
# The end-to-end twin of TEST-005: two real framework processes started at the
# same instant on the same fixture, each appending its own record to
# docs/ai/tests/test-runs.jsonl. Both records must be there, both must parse,
# the pre-run bytes must still be a prefix, and the two runs must not have
# collided on a RUN_ID — which second-resolution ids would do exactly here.
# ---------------------------------------------------------------------------
test_006_two_concurrent_framework_runs_keep_the_ledger_whole() {
  local d ok=1 ledger before_bytes p1 p2 lines ids
  d="$(new_fixture)" || return
  build_framework_repo "$d"
  write_fixture_suite "$d" t-quick 'exit 0'
  commit_fixture_repo "$d" || { log_fail "TEST-006 fixture repo init failed"; return; }
  ledger="$d/docs/ai/tests/test-runs.jsonl"
  printf '{"type":"pre-existing","run_id":"before"}\n' > "$ledger"
  cp "$ledger" "$d/ledger.before"
  before_bytes=$(wc -c < "$d/ledger.before" | tr -d ' ')

  ( cd "$d" && bash "$d/tests/skills/test-framework.sh" ) >/dev/null 2>&1 &
  p1=$!
  ( cd "$d" && bash "$d/tests/skills/test-framework.sh" ) >/dev/null 2>&1 &
  p2=$!
  wait "$p1" || true
  wait "$p2" || true

  lines=$(wc -l < "$ledger" | tr -d ' ')
  [[ "$lines" -eq 3 ]] \
    || { log_info "TEST-006: the ledger has $lines line(s), want 3 (one pre-existing plus one per run)"; ok=0; }

  # Every line whole and parseable. A `node -e` parse is the honest check for
  # a JSONL file; without node the arm says so rather than pretending.
  if command -v node >/dev/null 2>&1; then
    node -e '
      const fs = require("fs");
      const ls = fs.readFileSync(process.argv[1], "utf8").split("\n").filter(Boolean);
      for (const l of ls) JSON.parse(l);
      process.exit(0);
    ' "$ledger" 2>/dev/null \
      || { log_info "TEST-006: at least one ledger line is not parseable JSON — two concurrent appends interleaved"; ok=0; }
  else
    log_uncovered "TEST-006(parse): node is absent, so the JSON-per-line half of this arm did not run"
  fi

  ids="$(sed -n 's/.*"run_id":"\([^"]*\)".*/\1/p' "$ledger" | sort -u | wc -l | tr -d ' ')"
  [[ "$ids" -eq 3 ]] \
    || { log_info "TEST-006: the ledger carries $ids distinct run_id(s), want 3 — two runs started in the same second shared a RUN_DIR"; ok=0; }

  head -c "$before_bytes" "$ledger" > "$d/ledger.prefix"
  cmp -s "$d/ledger.before" "$d/ledger.prefix" \
    || { log_info "TEST-006: the pre-run ledger is NOT a byte-exact prefix of the post-run ledger"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-006 (AC-003) two concurrent framework runs each appended one whole, parseable record under a distinct run_id and left the pre-run bytes an exact prefix" \
    || log_fail "TEST-006 (AC-003) the run ledger survives concurrent framework runs"
}

# ---------------------------------------------------------------------------
# TEST-007 (AC-002 support) — a killed concurrent wave leaks no checkout.
#
# The concurrent path creates its disposable checkouts inside BACKGROUND
# CHILDREN, whose `ISOLATION_BASES+=(...)` the parent cannot see and whose traps
# bash does not inherit. Without the on-disk registration the parent's signal
# traps would drain an empty array while up to WIDTH checkouts stayed on disk.
# The lever is a real kill of a real wave mid-flight.
# ---------------------------------------------------------------------------
test_007_a_killed_wave_leaks_no_checkout() {
  local d tmphome ok=1 pid i leaked
  d="$(new_fixture)" || return
  tmphome="$(new_fixture)" || return
  build_framework_repo "$d"
  for i in a b c; do
    write_fixture_suite "$d" "t-long-$i" "printf started > '$tmphome/mark-$i'
sleep 30
exit 0"
  done
  commit_fixture_repo "$d" || { log_fail "TEST-007 fixture repo init failed"; return; }

  # `exec` so the pid captured below IS the framework: without it bash may keep
  # the subshell as the parent and the TERM would never reach the trap.
  ( cd "$d" && exec env TMPDIR="$tmphome" AAI_TEST_PARALLEL=3 bash "$d/tests/skills/test-framework.sh" ) >/dev/null 2>&1 &
  pid=$!
  for i in $(seq 1 200); do
    [[ -f "$tmphome/mark-a" && -f "$tmphome/mark-b" && -f "$tmphome/mark-c" ]] && break
    sleep 0.1
  done
  if [[ ! -f "$tmphome/mark-c" ]]; then
    kill "$pid" >/dev/null 2>&1
    wait "$pid" >/dev/null 2>&1
    log_uncovered "TEST-007: the wave never got all three suites in flight, so a kill would prove nothing"
    return
  fi
  # The checkouts must genuinely exist at the moment of the kill, or "no leak"
  # is the trivially true statement that nothing was ever created.
  local live
  live=$(find "$tmphome" -maxdepth 1 -name 'aai-iso-*' 2>/dev/null | wc -l | tr -d ' ')
  [[ "$live" -ge 2 ]] \
    || { log_info "TEST-007: only $live disposable checkout(s) were live when the wave was killed (want >= 2), so the arm proves nothing"; ok=0; }

  kill -TERM "$pid" >/dev/null 2>&1
  wait "$pid" >/dev/null 2>&1
  # The framework's TERM trap runs the cleanup; give the removal a moment.
  for i in $(seq 1 50); do
    leaked=$(find "$tmphome" -maxdepth 1 -name 'aai-iso-*' 2>/dev/null | wc -l | tr -d ' ')
    [[ "$leaked" -eq 0 ]] && break
    sleep 0.1
  done
  leaked=$(find "$tmphome" -maxdepth 1 -name 'aai-iso-*' 2>/dev/null | wc -l | tr -d ' ')
  [[ "$leaked" -eq 0 ]] \
    || { log_info "TEST-007: $leaked disposable checkout(s) survived a TERM to a concurrent wave"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-007 (AC-002 support) a concurrent wave killed with $live checkout(s) live on disk left none of them behind" \
    || log_fail "TEST-007 (AC-002 support) a killed wave leaks no checkout"
}

# ---------------------------------------------------------------------------
# TEST-008 (AC-001) — a bad width degrades to serial, loudly, and never to zero.
#
# A width of 0, a negative width or a non-numeric one must not silently disable
# the sweep or spin a wave of nothing. The check is behavioural on the count:
# every suite still runs and is still reported.
# ---------------------------------------------------------------------------
test_008_a_bad_width_degrades_to_serial() {
  local d ok=1 w out rc
  d="$(new_fixture)" || return
  build_framework_repo "$d"
  write_fixture_suite "$d" t-one 'exit 0'
  write_fixture_suite "$d" t-two 'exit 0'
  commit_fixture_repo "$d" || { log_fail "TEST-008 fixture repo init failed"; return; }

  for w in 0 -3 abc ''; do
    rc=0
    out="$( ( cd "$d" && AAI_TEST_PARALLEL="$w" bash "$d/tests/skills/test-framework.sh" ) 2>&1 | strip_ansi )" || rc=$?
    [[ "$rc" -eq 0 ]] || { log_info "TEST-008: AAI_TEST_PARALLEL='$w' made the run exit $rc"; ok=0; }
    assert_payload_contains "$out" "Total:   2" \
      "TEST-008: AAI_TEST_PARALLEL='$w' did not run both suites" || ok=0
    assert_payload_contains "$out" "Passed:  2 (100%)" \
      "TEST-008: AAI_TEST_PARALLEL='$w' did not pass both suites" || ok=0
  done

  [[ $ok -eq 1 ]] && log_pass "TEST-008 (AC-001) a width of 0, a negative width, a non-numeric width and an empty one all still run and report every suite" \
    || log_fail "TEST-008 (AC-001) a bad width degrades to serial"
}

# ---------------------------------------------------------------------------
# TEST-009 (AC-002) — an UNISOLATED run is serial, whatever width it is given.
#
# This is the boundary of what concurrency can be made safe. With isolation on,
# a suite runs in its own clone and cannot reach the shipping tree by ordinary
# means. With it off, every suite runs directly against that tree, and a
# per-suite tripwire window is the only thing that can attribute a write to one
# suite rather than to whichever siblings happened to be running. No width can
# give that guarantee, so the run gives up the speed instead.
#
# Measured on the CLOCK, not on the reason line: four sleep-3 suites at an
# explicit width of 4 must still take >= 12 s with isolation off.
# ---------------------------------------------------------------------------
test_009_an_unisolated_run_is_serial() {
  local d ok=1 i s e t rc=0 out
  d="$(new_fixture)" || return
  build_framework_repo "$d"
  for i in a b c e; do
    write_fixture_suite "$d" "t-sleep-$i" "sleep 3
exit 0"
  done
  commit_fixture_repo "$d" || { log_fail "TEST-009 fixture repo init failed"; return; }

  s=$(date +%s)
  out="$( ( cd "$d" && AAI_TEST_ISOLATION=0 AAI_TEST_PARALLEL=4 bash "$d/tests/skills/test-framework.sh" ) 2>&1 | strip_ansi )" || rc=$?
  e=$(date +%s)
  t=$(( e - s ))

  [[ "$rc" -eq 0 ]] || { log_info "TEST-009: the run exited $rc (want 0)"; ok=0; }
  [[ "$t" -ge 12 ]] || { log_info "TEST-009: an unisolated run of 4x sleep 3 at AAI_TEST_PARALLEL=4 took ${t}s (want >= 12) — the suites overlapped, so a write by one of them could not be attributed to it"; ok=0; }
  assert_payload_contains "$out" "Concurrency: suites run one at a time" \
    "TEST-009: the run did not say it had dropped to one suite at a time" || ok=0
  assert_payload_contains "$out" "isolation is off" \
    "TEST-009: the reason for running serially was not named" || ok=0

  [[ $ok -eq 1 ]] && log_pass "TEST-009 (AC-002) an unisolated run ignores an explicit width and runs one suite at a time (4x sleep-3 took ${t}s at AAI_TEST_PARALLEL=4), naming isolation as the reason" \
    || log_fail "TEST-009 (AC-002) an unisolated run is serial"
}

# ---------------------------------------------------------------------------
# TEST-010 (AC-001) — a wave child does not leak the framework's internals into
# the suite it runs.
#
# THE MEASURED DEFECT this pins. A wave child used to disable its own `tee` with
# a `SUITE_TEE=false suite_execute ...` prefix assignment. A prefix assignment
# is placed in the ENVIRONMENT of the command it precedes, so it travelled into
# `bash <the suite>` and on into any framework that suite runs itself. The real
# casualty was tests/skills/test-aai-suite-isolation.sh, which runs a fixture
# framework with --verbose and reads its output: the inner run inherited the
# flag, its `tee` never fired, and the arm read the missing output as an
# unseeded checkout. It only reproduced when the outer sweep ran concurrently,
# which is the worst kind of test failure to be handed.
#
# The lever is the same one: a suite that runs a NESTED framework with
# --verbose, from inside a concurrent wave, and reads the inner suite's output.
# ---------------------------------------------------------------------------
test_010_a_wave_child_leaks_nothing_into_its_suite() {
  local outer inner ok=1 rc=0 out
  outer="$(new_fixture)" || return
  inner="$(new_fixture)" || return

  build_framework_repo "$inner"
  write_fixture_suite "$inner" t-marker 'echo "INNER-MARKER-9f3a"; exit 0'
  commit_fixture_repo "$inner" || { log_fail "TEST-010 inner fixture repo init failed"; return; }

  build_framework_repo "$outer"
  write_fixture_suite "$outer" t-a-quiet 'exit 0'
  write_fixture_suite "$outer" t-b-nested "
nested=\"\$(bash '$inner/tests/skills/test-framework.sh' --verbose 2>&1)\"
case \"\$nested\" in
  *INNER-MARKER-9f3a*) echo 'the nested --verbose run printed its suite output'; exit 0 ;;
esac
echo 'FAIL: the nested --verbose run did NOT print its suite output'
exit 1"
  commit_fixture_repo "$outer" || { log_fail "TEST-010 outer fixture repo init failed"; return; }

  out="$( ( cd "$outer" && AAI_TEST_PARALLEL=2 bash "$outer/tests/skills/test-framework.sh" ) 2>&1 | strip_ansi )" || rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-010: the outer run exited $rc (want 0) — a wave child changed how the suite's own nested framework behaved"; ok=0; }
  assert_payload_contains "$out" "Passed:  2 (100%)" \
    "TEST-010: the outer run did not pass both suites" || ok=0
  assert_payload_not_contains "$out" "the nested --verbose run did NOT print its suite output" \
    "TEST-010: a wave child leaked a framework-internal flag into the suite it ran, and the suite's own nested framework behaved differently because of it" || ok=0

  [[ $ok -eq 1 ]] && log_pass "TEST-010 (AC-001) a suite running its own nested framework with --verbose from inside a concurrent wave still sees that inner run's suite output — the wave child leaks none of its own execution flags into the suite's environment" \
    || log_fail "TEST-010 (AC-001) a wave child leaks nothing into its suite"
}

main() {
  echo "=== $TEST_NAME ==="
  check_deps
  test_001_width_is_honoured_on_the_clock
  test_002_verdict_set_is_identical_serial_and_concurrent
  test_003_a_sibling_is_never_blamed_for_a_concurrent_detection
  test_004_a_concurrent_wave_still_fails_on_a_working_tree_write
  test_005_concurrent_appends_are_serialised
  test_006_two_concurrent_framework_runs_keep_the_ledger_whole
  test_007_a_killed_wave_leaks_no_checkout
  test_008_a_bad_width_degrades_to_serial
  test_009_an_unisolated_run_is_serial
  test_010_a_wave_child_leaks_nothing_into_its_suite
  echo ""
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
