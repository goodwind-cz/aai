#!/usr/bin/env bash
#
# Test: suite-reuse.mjs (spec-precise-suite-evidence-reuse, spec-reuse-for-docs-reading-suites).
#
# Library and CLI rows run as node:test cases in tests/skills/lib/suite-reuse.test.mjs
# (each selected by its TEST id prefix, so mutation-run.mjs can target one row);
# TEST-3188 is a shell-native contract row. Rows that drive the REAL framework
# (TEST-3165, 3173, 3175, 3177, 3179, 3180) run it on a throwaway git repository
# carrying byte copies of the framework, the helper and its imports. Rows that
# need the Pester file, the prompts or the analysis note (TEST-3184..3187, 3189)
# are added by the later run of this change.
#
# SUITE_REUSE_FRAMEWORK and SUITE_REUSE_RELEASE_DRY_RUN override the files under
# test; they exist only so a RED observation can run the new rows against the
# baseline copies of those two files.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-suite-reuse"
# Path math without a cd inside a command substitution (cd-subshell-leak gate).
_src="${BASH_SOURCE[0]}"
[[ "$_src" == */* ]] || _src="./$_src"
SCRIPT_DIR="${_src%/*}"
[[ "$SCRIPT_DIR" == /* ]] || SCRIPT_DIR="$PWD/$SCRIPT_DIR"
SCRIPT_DIR="${SCRIPT_DIR%/.}"
PROJECT_ROOT="${SCRIPT_DIR%/tests/skills}"
NODE_TEST="$PROJECT_ROOT/tests/skills/lib/suite-reuse.test.mjs"
FRAMEWORK_FILE="${SUITE_REUSE_FRAMEWORK:-$PROJECT_ROOT/tests/skills/test-framework.sh}"
RELEASE_DRY_RUN="${SUITE_REUSE_RELEASE_DRY_RUN:-$PROJECT_ROOT/.aai/scripts/release-dry-run.mjs}"
WORK_BASES=()
cleanup_bases() {
  local b
  if [[ ${#WORK_BASES[@]} -gt 0 ]]; then
    for b in "${WORK_BASES[@]}"; do rm -rf "$b"; done
  fi
}
trap cleanup_bases EXIT

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

check_deps() {
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
}

# node_cases <TEST-id>: run the node:test cases whose name starts with the id.
# A pattern that matches nothing would pass vacuously, so the TAP tally must
# show at least one passing case and no failing one.
node_cases() {
  local id="$1" out="" rc=0 passed failed
  out="$(env -u AAI_ROLE node --test --test-reporter=tap --test-name-pattern="^$id " "$NODE_TEST" 2>&1)" || rc=$?
  passed="$(printf '%s\n' "$out" | sed -n 's/^# pass \([0-9][0-9]*\)$/\1/p')"
  failed="$(printf '%s\n' "$out" | sed -n 's/^# fail \([0-9][0-9]*\)$/\1/p')"
  if [[ "$rc" -ne 0 || "${failed:-1}" != 0 || "${passed:-0}" -lt 1 ]]; then
    printf '%s\n' "$out" | sed -n '1,60p' >&2
    log_fail "$id node cases failed (rc=$rc pass=${passed:-?} fail=${failed:-?})"
  fi
  log_pass "$id ($passed node case(s))"
}

# ---- framework fixtures (seams S1 to S4 and S6) ----

# new_base: a fresh scratch directory holding repo/ (the fixture repository) and
# m/ (suite run markers, outside the repository so a suite can count its own
# executions without being an input).
new_base() {
  local b
  b="$(mktemp -d "${TMPDIR:-/tmp}/aai-suite-reuse-fx.XXXXXX")"
  WORK_BASES+=("$b")
  mkdir -p "$b/repo" "$b/m"
  printf '%s\n' "$b"
}

# fx_suite <base> <suite> <exit code> [print-env]: tests/skills/test-<suite>.sh
# appends one line to its marker per execution and exits with the given code.
fx_suite() {
  local base="$1" suite="$2" code="$3" printenv="${4:-}"
  {
    echo '#!/usr/bin/env bash'
    printf "echo run >> '%s/m/%s'\n" "$base" "$suite"
    if [[ -n "$printenv" ]]; then echo 'echo "reuse-env=${AAI_SUITE_REUSE-unset}"'; fi
    printf 'exit %s\n' "$code"
  } > "$base/repo/tests/skills/test-$suite.sh"
}

# build_fx <base> <suite>...: the repository, committed. The first suite exits 0.
build_fx() {
  local base="$1" r="$1/repo" suite
  shift
  mkdir -p "$r/tests/skills" "$r/.aai/scripts/lib" "$r/docs/ai/tests"
  cp "$FRAMEWORK_FILE" "$r/tests/skills/test-framework.sh"
  cp "$PROJECT_ROOT"/.aai/scripts/lib/* "$r/.aai/scripts/lib/"
  cp "$PROJECT_ROOT/.aai/scripts/suite-reuse.mjs" "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" "$r/.aai/scripts/"
  mkdir -p "$r/tests/skills/lib" && cp "$PROJECT_ROOT/tests/skills/lib/read-trace.cjs" "$r/tests/skills/lib/"
  printf 'tests/skills/results/\ndocs/ai/tests/test-runs.jsonl\n' > "$r/.gitignore"
  for suite in "$@"; do fx_suite "$base" "$suite" 0; done
  fx_manifest_rows "$base" "$@"
  (
    cd "$r" && git init -q -b main && git config user.email 'suite-reuse@example.invalid' \
      && git config user.name 'suite-reuse' && git add -A && git commit -q -m fixture
  ) || log_fail "fixture repository could not be committed"
}

# fx_manifest_rows <base> <suite>...: suite-map rows and the manifest.
fx_manifest_rows() {
  local base="$1" r="$1/repo" suite first=1 rows="" entries="" core
  shift
  core="$1"
  for suite in "$@"; do
    rows="${rows}  $suite:
    globs:
      - tests/skills/test-$suite.sh
"
    if [[ "$first" -eq 0 ]]; then entries="$entries,"; fi
    entries="$entries\"$suite\":{\"inputs\":[],\"live\":false,\"note\":\"fixture suite reads only its closure\"}"
    first=0
  done
  rows="${rows}  aai-suite-reuse:
    globs:
"
  for suite in "$@"; do rows="${rows}      - tests/skills/test-$suite.sh
"; done
  printf 'core:\n  - %s\nfull_run_triggers:\n  shared_lib_globs:\n    - .aai/scripts/lib/**\nsuites:\n%s' "$core" "$rows" > "$r/tests/skills/suite-map.yaml"
  printf '{"version":1,"suites":{%s}}\n' "$entries" > "$r/tests/skills/suite-reuse.json"
}

# fw_run <base> [VAR=val ...] -- <framework args>: one real framework run, in the
# fixture, with every reuse-relevant ambient variable cleared first (the wrapper
# that runs THIS suite exports AAI_SUITE_REUSE=0, and CI exports CI).
fw_run() {
  local base="$1" envs=()
  shift
  while [[ "$1" != "--" ]]; do envs+=("$1"); shift; done
  shift
  (
    cd "$base/repo" && env -u AAI_ROLE -u CI -u GITHUB_ACTIONS -u AAI_SUITE_REUSE -u AAI_TEST_REF_ID \
      AAI_TEST_PARALLEL=1 ${envs[@]+"${envs[@]}"} bash tests/skills/test-framework.sh "$@"
  )
}

# fw_go <base> <rc var> <out var> [VAR=val ...] -- <framework args>: run and capture.
OUT=""; RC=0
fw_go() {
  local base="$1"
  shift
  RC=0
  OUT="$(fw_run "$base" "$@" 2>&1)" || RC=$?
}

marker_count() { # <base> <suite>
  if [[ -f "$1/m/$2" ]]; then wc -l < "$1/m/$2" | tr -d ' '; else echo 0; fi
}
store_run_id() { # <base> <suite>
  sed -n 's/.*"run_id": "\([^"]*\)".*/\1/p' "$1/repo/tests/skills/results/reuse/$2.json" 2>/dev/null || true
}
newest_run_dir() { # <base>
  ls -1d "$1"/repo/tests/skills/results/test-* | sort | tail -n 1
}
helper_check() { # <base> <suite> [mode]  -> prints the helper's check line
  local base="$1" suite="$2" mode="${3:-selected}"
  mkdir -p "$base/chk"
  (
    cd "$base/repo" && env -u AAI_ROLE -u CI -u GITHUB_ACTIONS -u AAI_SUITE_REUSE AAI_TEST_PARALLEL=1 \
      node .aai/scripts/suite-reuse.mjs check --root "$base/repo" --run-dir "$base/chk" --mode "$mode" --isolation on --suite "$suite"
  )
}
show_out() { printf '%s\n' "$OUT" | sed -n '1,120p' >&2; }
expect() { # <label> <haystack> <needle>
  [[ "$2" == *"$3"* ]] || { printf '%s\n' "$2" | sed -n '1,80p' >&2; log_fail "$1: expected output to contain: $3"; }
}
expect_not() { # <label> <haystack> <needle>
  [[ "$2" != *"$3"* ]] || { printf '%s\n' "$2" | sed -n '1,80p' >&2; log_fail "$1: output must not contain: $3"; }
}

test_3166_inputs_tracked_and_untracked() { node_cases TEST-3166; }
test_3168_env_component() { node_cases TEST-3168; }
test_3169_args_component() { node_cases TEST-3169; }
test_3170_runtime_component() { node_cases TEST-3170; }
test_3171_policy_component() { node_cases TEST-3171; }
test_3174_manifest_invalid() { node_cases TEST-3174; }
test_3176_record_refusals() { node_cases TEST-3176; }
test_3195_bash_startup_hook() { node_cases TEST-3195; }
test_3196_record_no_identity() { node_cases TEST-3196; }
test_3178_off_modes() { node_cases TEST-3178; }
test_3181_log_missing() { node_cases TEST-3181; }
test_3182_lint_and_live_manifest() { node_cases TEST-3182; }
test_3183_select_suites_import() { node_cases TEST-3183; }

# test_3192: the validator's r1 repro shape on a fixture. A suite reads a data file
# it names by a path literal; after that file is renamed the suite must execute
# again (and fail on the missing read), never be reported REUSED.
test_3192_renamed_read_file_not_reused() {
  local base r id
  base="$(new_base)"
  r="$base/repo"
  build_fx "$base" aai-fx
  mkdir -p "$r/docs/data"
  printf 'payload\n' > "$r/docs/data/probe.txt"
  {
    echo '#!/usr/bin/env bash'
    printf "echo run >> '%s/m/aai-fx'\n" "$base"
    echo 'grep -q payload "$(dirname "$0")/../../docs/data/probe.txt" || { echo "probe read failed"; exit 1; }'
    echo 'exit 0'
  } > "$r/tests/skills/test-aai-fx.sh"
  # docs/data/probe.txt is the only path literal the suite names.
  (cd "$r" && git add -A && git commit -q -m 'suite reads docs/data/probe.txt')
  fw_go "$base" -- --skill aai-fx
  [[ "$RC" -eq 0 ]] || { show_out; log_fail "TEST-3192: run 1 exited $RC"; }
  fw_go "$base" -- --skill aai-fx
  expect "TEST-3192 unchanged" "$OUT" "REUSED (run "
  [[ "$(marker_count "$base" aai-fx)" -eq 1 ]] || log_fail "TEST-3192: the unchanged second run executed the suite"
  (cd "$r" && git mv docs/data/probe.txt docs/data/probe-renamed.txt)
  id="$(helper_check "$base" aai-fx)"
  expect "TEST-3192 helper" "$id" "RUN aai-fx reason=inputs"
  fw_go "$base" -- --skill aai-fx
  expect_not "TEST-3192 renamed" "$OUT" "REUSED"
  [[ "$(marker_count "$base" aai-fx)" -eq 2 ]] || log_fail "TEST-3192: the suite was not executed after its read file was renamed"
  [[ "$RC" -ne 0 ]] || log_fail "TEST-3192: the suite must fail on the missing read, got exit 0"
  log_pass "TEST-3192 (rename of a read file: RUN reason=inputs, executed, not REUSED)"
}



# test_3165: a second selected run of an unchanged declared suite reports it
# REUSED with the first run's provenance and does not execute it.
test_3165_reused_not_executed() {
  local base id
  base="$(new_base)"
  build_fx "$base" aai-fx
  fw_go "$base" -- --skill aai-fx
  [[ "$RC" -eq 0 ]] || log_fail "TEST-3165: run 1 exited $RC"
  expect "TEST-3165 run 1" "$OUT" "Evidence reuse: on (0 of 1 suites reused"
  [[ "$(marker_count "$base" aai-fx)" -eq 1 ]] || log_fail "TEST-3165: run 1 did not execute the suite once"
  id="$(store_run_id "$base" aai-fx)"
  [[ -n "$id" ]] || log_fail "TEST-3165: run 1 left no store entry"
  fw_go "$base" -- --skill aai-fx
  [[ "$RC" -eq 0 ]] || { show_out; log_fail "TEST-3165: run 2 exited $RC"; }
  expect "TEST-3165 run 2" "$OUT" "aai-fx"
  expect "TEST-3165 run 2" "$OUT" "REUSED (run $id, "
  expect "TEST-3165 run 2" "$OUT" ", log tests/skills/results/$id/aai-fx.log)"
  [[ "$(marker_count "$base" aai-fx)" -eq 1 ]] || log_fail "TEST-3165: run 2 executed the suite (marker $(marker_count "$base" aai-fx))"
  log_pass "TEST-3165 (second run REUSED naming run $id, suite executed once)"
}

# test_3173: not declared, live and an invalid manifest each execute the suite.
test_3173_undeclared_live_invalid() {
  local base id r chk
  base="$(new_base)"
  r="$base/repo"
  build_fx "$base" aai-fx aai-fy
  fw_go "$base" -- --skill aai-fx
  [[ "$RC" -eq 0 ]] || log_fail "TEST-3173: seed run exited $RC"
  cp "$r/tests/skills/suite-reuse.json" "$base/manifest.orig"
  # (a) removed from the manifest
  printf '{"version":1,"suites":{"aai-fy":{"inputs":[],"live":false,"note":"x"}}}\n' > "$r/tests/skills/suite-reuse.json"
  chk="$(helper_check "$base" aai-fx)"
  expect "TEST-3173 undeclared" "$chk" "RUN aai-fx reason=not-declared"
  fw_go "$base" -- --skill aai-fx
  [[ "$RC" -eq 0 && "$(marker_count "$base" aai-fx)" -eq 2 ]] || log_fail "TEST-3173: undeclared suite was not executed (rc=$RC marker $(marker_count "$base" aai-fx))"
  expect_not "TEST-3173 undeclared" "$OUT" "REUSED"
  # (b) live true
  printf '{"version":1,"suites":{"aai-fx":{"inputs":[],"live":true,"note":"x"}}}\n' > "$r/tests/skills/suite-reuse.json"
  chk="$(helper_check "$base" aai-fx)"
  expect "TEST-3173 live" "$chk" "RUN aai-fx reason=live"
  fw_go "$base" -- --skill aai-fx
  [[ "$RC" -eq 0 && "$(marker_count "$base" aai-fx)" -eq 3 ]] || log_fail "TEST-3173: live suite was not executed (marker $(marker_count "$base" aai-fx))"
  # (c) an unknown key disables reuse for the whole run
  printf '{"version":1,"suites":{"aai-fx":{"inputs":[],"live":false,"note":"x","extra":1}}}\n' > "$r/tests/skills/suite-reuse.json"
  chk="$(helper_check "$base" aai-fx)"
  expect "TEST-3173 invalid" "$chk" "RUN aai-fx reason=manifest-invalid"
  fw_go "$base" -- --skill aai-fx
  [[ "$RC" -eq 0 && "$(marker_count "$base" aai-fx)" -eq 4 ]] || log_fail "TEST-3173: suite ran under an invalid manifest was not executed (marker $(marker_count "$base" aai-fx))"
  expect_not "TEST-3173 invalid" "$OUT" "REUSED"
  node_cases TEST-3173
  log_pass "TEST-3173 (not-declared, live and manifest-invalid each execute the suite)"
}

# test_3175: a recorded suite that then fails loses its record; an exit-42 suite
# is never recorded.
test_3175_fail_forgets_skip_not_recorded() {
  local base r chk
  base="$(new_base)"
  r="$base/repo"
  build_fx "$base" aai-fx aai-fs
  fw_go "$base" -- --skill aai-fx
  [[ -f "$r/tests/skills/results/reuse/aai-fx.json" ]] || log_fail "TEST-3175: passing run left no store entry"
  fx_suite "$base" aai-fx 1
  fw_go "$base" -- --skill aai-fx
  [[ "$RC" -eq 1 ]] || log_fail "TEST-3175: failing run exited $RC, expected 1"
  [[ ! -e "$r/tests/skills/results/reuse/aai-fx.json" ]] || log_fail "TEST-3175: failing run kept the store entry"
  fx_suite "$base" aai-fx 0
  chk="$(helper_check "$base" aai-fx)"
  expect "TEST-3175 after fail" "$chk" "RUN aai-fx reason=no-record"
  fw_go "$base" -- --skill aai-fx
  [[ "$RC" -eq 0 && "$(marker_count "$base" aai-fx)" -eq 3 ]] || log_fail "TEST-3175: suite fixed after a failure was not executed (rc=$RC marker $(marker_count "$base" aai-fx))"
  fx_suite "$base" aai-fs 42
  fw_go "$base" -- --skill aai-fs
  [[ "$RC" -eq 0 ]] || log_fail "TEST-3175: skipping suite exited $RC"
  [[ ! -e "$r/tests/skills/results/reuse/aai-fs.json" ]] || log_fail "TEST-3175: an exit-42 suite was recorded"
  # A check call that fails (OFF helper-failed) still forgets the record of a suite
  # that then fails: the helper is swapped for a shim whose check exits 1.
  fw_go "$base" -- --skill aai-fx
  [[ -f "$r/tests/skills/results/reuse/aai-fx.json" ]] || log_fail "TEST-3175: passing run before the shim left no store entry"
  mv "$r/.aai/scripts/suite-reuse.mjs" "$r/.aai/scripts/suite-reuse-real.mjs"
  cat > "$r/.aai/scripts/suite-reuse.mjs" <<'SHIM'
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
if (process.argv[2] === 'check') process.exit(1);
const real = fileURLToPath(new URL('./suite-reuse-real.mjs', import.meta.url));
const r = spawnSync(process.execPath, [real, ...process.argv.slice(2)], { stdio: 'inherit' });
process.exit(r.status === null ? 1 : r.status);
SHIM
  fx_suite "$base" aai-fx 1
  fw_go "$base" -- --skill aai-fx
  expect "TEST-3175 helper-failed" "$OUT" "Evidence reuse: off (helper-failed)"
  [[ "$RC" -eq 1 ]] || log_fail "TEST-3175: failing run under a failing check exited $RC, expected 1"
  [[ ! -e "$r/tests/skills/results/reuse/aai-fx.json" ]] || log_fail "TEST-3175: a failing suite kept its record when the check call failed"
  log_pass "TEST-3175 (fail forgets, fixed suite runs as no-record, exit 42 not recorded, forget survives a failed check)"
}

# test_3177: full sweep, CI, GITHUB_ACTIONS, opt-out and isolation off each execute
# despite a valid record; only a local full sweep writes the store.
test_3177_off_modes_execute() {
  local base r id1 id2 sum1 sum2
  base="$(new_base)"
  r="$base/repo"
  build_fx "$base" aai-fx aai-fy
  fw_go "$base" -- --skill aai-fx
  id1="$(store_run_id "$base" aai-fx)"
  [[ -n "$id1" ]] || log_fail "TEST-3177: seed run left no store entry"
  fw_go "$base" -- 
  [[ "$RC" -eq 0 ]] || log_fail "TEST-3177: full run exited $RC"
  expect "TEST-3177 full" "$OUT" "Evidence reuse: off (full-sweep)"
  expect_not "TEST-3177 full" "$OUT" "REUSED"
  [[ "$(marker_count "$base" aai-fx)" -eq 2 ]] || log_fail "TEST-3177: full sweep did not execute the suite"
  id2="$(store_run_id "$base" aai-fx)"
  [[ -n "$id2" && "$id2" != "$id1" ]] || log_fail "TEST-3177: full sweep did not refresh the record ($id1 / $id2)"
  sum1="$(cksum < "$r/tests/skills/results/reuse/aai-fx.json")"
  fw_go "$base" AAI_SUITE_REUSE=0 -- --skill aai-fx
  expect "TEST-3177 opt-out" "$OUT" "Evidence reuse: off (opt-out)"
  [[ "$(marker_count "$base" aai-fx)" -eq 3 ]] || log_fail "TEST-3177: opt-out run did not execute the suite"
  fw_go "$base" CI=true -- --skill aai-fx
  expect "TEST-3177 ci" "$OUT" "Evidence reuse: off (ci)"
  [[ "$(marker_count "$base" aai-fx)" -eq 4 ]] || log_fail "TEST-3177: CI run did not execute the suite"
  fw_go "$base" GITHUB_ACTIONS=true -- --skill aai-fx
  expect "TEST-3177 github actions" "$OUT" "Evidence reuse: off (ci)"
  [[ "$(marker_count "$base" aai-fx)" -eq 5 ]] || log_fail "TEST-3177: GITHUB_ACTIONS run did not execute the suite"
  fw_go "$base" AAI_TEST_ISOLATION=0 -- --skill aai-fx
  expect "TEST-3177 isolation off" "$OUT" "Evidence reuse: off (isolation-off)"
  [[ "$(marker_count "$base" aai-fx)" -eq 6 ]] || log_fail "TEST-3177: isolation-off run did not execute the suite"
  sum2="$(cksum < "$r/tests/skills/results/reuse/aai-fx.json")"
  [[ "$sum1" == "$sum2" ]] || log_fail "TEST-3177: an opt-out, CI or isolation-off run changed the store entry"
  log_pass "TEST-3177 (full-sweep, opt-out, ci, isolation-off execute; only the full sweep records)"
}

# test_3179: each suite runs with AAI_SUITE_REUSE=0 in its own environment, and
# release-dry-run.mjs starts the framework with AAI_SUITE_REUSE=0.
test_3179_fresh_mandatory_callers() {
  local base r log m line
  base="$(new_base)"
  r="$base/repo"
  build_fx "$base" aai-fx
  fx_suite "$base" aai-fx 0 printenv
  (cd "$r" && git add -A && git commit -q -m suite)
  fw_go "$base" -- --skill aai-fx
  [[ "$RC" -eq 0 ]] || log_fail "TEST-3179: framework run exited $RC"
  expect "TEST-3179 suite env" "$OUT" "Evidence reuse: on"
  log="$(newest_run_dir "$base")/aai-fx.log"
  grep -qxF 'reuse-env=0' "$log" || log_fail "TEST-3179: the suite did not see AAI_SUITE_REUSE=0 ($(cat "$log"))"

  # release-dry-run: a fixture whose only reader (a suite naming CHANGELOG) is run
  # through a stub framework that records the variable it was started with.
  base="$(new_base)"
  r="$base/repo"
  mkdir -p "$r/tests/skills"
  printf '#!/usr/bin/env bash\nprintf "reuse=%%s\\n" "${AAI_SUITE_REUSE-unset}" >> "%s/m/stub"\n' "$base" > "$r/tests/skills/test-framework.sh"
  printf '#!/usr/bin/env bash\n# reads CHANGELOG.md\n' > "$r/tests/skills/test-aai-fx.sh"
  printf '# Changelog\n\n## [unreleased] — fixture\n\n- fixture entry.\n' > "$r/CHANGELOG.md"
  (cd "$r" && git init -q -b main && git config user.email 'suite-reuse@example.invalid' && git config user.name 'suite-reuse' \
    && git add -A && git commit -q -m fixture) || log_fail "TEST-3179: release fixture could not be committed"
  m=0
  env -u AAI_ROLE AAI_SUITE_REUSE=1 node "$RELEASE_DRY_RUN" --root "$r" --jobs 1 --timeout-seconds 60 --budget-seconds 120 > "$base/rdr.out" 2>&1 || m=$?
  [[ -f "$base/m/stub" ]] || { sed -n '1,40p' "$base/rdr.out" >&2; log_fail "TEST-3179: release-dry-run (rc=$m) never started the framework"; }
  while IFS= read -r line; do
    [[ "$line" == "reuse=0" ]] || log_fail "TEST-3179: release-dry-run started the framework with '$line'"
  done < "$base/m/stub"
  log_pass "TEST-3179 (suite env 0; release-dry-run starts the framework with AAI_SUITE_REUSE=0)"
}

# test_3180: a mixed run reports the reused suite in metrics.jsonl and the
# summary, and keeps total, passed and the isolation invariant on executed suites.
test_3180_reused_accounting() {
  local base r dir ledger iso deg total
  base="$(new_base)"
  r="$base/repo"
  build_fx "$base" aai-fx aai-fy
  fw_go "$base" -- --skill aai-fx
  fw_go "$base" -- --skill aai-fx --skill aai-fy
  [[ "$RC" -eq 0 ]] || log_fail "TEST-3180: mixed run exited $RC"
  dir="$(newest_run_dir "$base")"
  grep -q '"skill":"aai-fx","status":"REUSED","reused_from_run":"test-[^"]*","reused_log":"tests/skills/results/test-[^"]*/aai-fx.log"' "$dir/metrics.jsonl" \
    || log_fail "TEST-3180: metrics.jsonl has no REUSED line for aai-fx: $(cat "$dir/metrics.jsonl")"
  grep -q '"skill":"aai-fy","status":"PASS"' "$dir/metrics.jsonl" || log_fail "TEST-3180: aai-fy has no PASS metrics line"
  expect "TEST-3180 summary" "$OUT" "Reused:  1"
  expect "TEST-3180 summary" "$OUT" "Passed:  1 (100%)"
  expect "TEST-3180 summary" "$OUT" "Total:   1"
  ledger="$(tail -n 1 "$r/docs/ai/tests/test-runs.jsonl")"
  [[ "$ledger" == *'"reused":1,'* && "$ledger" == *'"total":1,'* ]] || log_fail "TEST-3180: ledger line lacks reused:1 and total:1: $ledger"
  total="$(printf '%s' "$ledger" | sed -n 's/.*"total":\([0-9]*\),.*/\1/p')"
  iso="$(printf '%s' "$ledger" | sed -n 's/.*"suites_isolated":\([0-9]*\),.*/\1/p')"
  deg="$(printf '%s' "$ledger" | sed -n 's/.*"suites_degraded":\([0-9]*\),.*/\1/p')"
  [[ $((iso + deg)) -eq "$total" ]] || log_fail "TEST-3180: isolation invariant broken ($iso + $deg != $total)"
  expect_not "TEST-3180 summary" "$OUT" "ACCOUNTING BROKEN"
  # A run in which every suite is reused still writes the Reused line to summary.txt.
  fw_go "$base" -- --skill aai-fx --skill aai-fy
  [[ "$RC" -eq 0 ]] || { show_out; log_fail "TEST-3180: all-reused run exited $RC"; }
  expect "TEST-3180 all-reused console" "$OUT" "Reused:  2"
  dir="$(newest_run_dir "$base")"
  grep -q '^Reused:  2' "$dir/summary.txt" || log_fail "TEST-3180: all-reused run summary.txt has no Reused line: $(cat "$dir/summary.txt")"
  log_pass "TEST-3180 (REUSED metrics line, Reused summary incl. summary.txt of an all-reused run, ledger reused=1 total=1, isolation invariant)"
}

# test_3188: PROFILES core rows, selection through the real select-suites.mjs, no shell option.
test_3188_profiles_selection_and_source_shape() {
  local src="$PROJECT_ROOT/.aai/scripts/suite-reuse.mjs"
  local profiles="$PROJECT_ROOT/.aai/system/PROFILES.yaml"
  local selector="$PROJECT_ROOT/.aai/scripts/select-suites.mjs"
  local f out
  grep -qxF '  - .aai/scripts/suite-reuse.mjs' "$profiles" \
    || log_fail "TEST-3188: PROFILES.yaml lacks the suite-reuse.mjs core row"
  grep -qxF '  - .aai/scripts/lib/checkout-trace.mjs' "$profiles" \
    || log_fail "TEST-3188: PROFILES.yaml lacks the checkout-trace.mjs core row"
  for f in .aai/scripts/suite-reuse.mjs tests/skills/suite-reuse.json tests/skills/test-framework.sh .aai/scripts/release-dry-run.mjs; do
    out="$(printf '%s\n' "$f" | node "$selector" --files-from - --repo-root "$PROJECT_ROOT")" \
      || log_fail "TEST-3188: select-suites.mjs failed for $f"
    [[ $'\n'"$out" =~ $'\n'SELECTED\ aai-suite-reuse($|[[:space:]]) ]] \
      || log_fail "TEST-3188: $f does not select aai-suite-reuse (got: $(printf '%s' "$out" | tr '\n' ';'))"
  done
  if grep -qE 'shell:[[:space:]]*true' "$src"; then log_fail "TEST-3188: suite-reuse.mjs sets shell: true"; fi
  log_pass "TEST-3188 (core rows, selection, no shell option)"
}

# test_3267: the helper has the D3 identity line, holds no source-text reader and stays small;
# the trace module stays small and imports only node: modules and tree-hash.
test_3267_source_shape() {
  local src="$PROJECT_ROOT/.aai/scripts/suite-reuse.mjs"
  local mod="$PROJECT_ROOT/.aai/scripts/lib/checkout-trace.mjs"
  local lines imp line word
  [[ -f "$mod" ]] || log_fail "TEST-3267: $mod does not exist"
  lines="$(wc -l < "$src" | tr -d ' ')"
  [[ "$lines" -le 600 ]] || log_fail "TEST-3267: suite-reuse.mjs has $lines lines (cap 600)"
  while IFS= read -r imp; do
    case "$imp" in
      node:*|./select-suites.mjs|./lib/tree-hash.mjs|./lib/runtime-file.mjs|./lib/checkout-trace.mjs) ;;
      *) log_fail "TEST-3267: suite-reuse.mjs imports '$imp'" ;;
    esac
  done < <(sed -n "s/^import .* from '\\([^']*\\)';\$/\\1/p" "$src")
  grep -qxF "import { armTrace, collectTrace } from './lib/checkout-trace.mjs';" "$src" \
    || log_fail "TEST-3267: suite-reuse.mjs lacks the D8 checkout-trace import"
  line="$(grep -m1 'IDENTITY_COMPONENTS = ' "$src" || true)"
  [[ "$line" == "const IDENTITY_COMPONENTS = ['inputs', 'paths', 'env', 'args', 'runtime', 'policy', 'history'];" ]] \
    || log_fail "TEST-3267: IDENTITY_COMPONENTS line differs from the D3 literal: $line"
  for word in computeClosure TOKEN_RE HISTORY_RE MARKER_RE MINIMAL_TREE_FRAMEWORK; do
    if grep -q "$word" "$src"; then log_fail "TEST-3267: suite-reuse.mjs still contains $word"; fi
  done
  lines="$(wc -l < "$mod" | tr -d ' ')"
  [[ "$lines" -le 200 ]] || log_fail "TEST-3267: checkout-trace.mjs has $lines lines (cap 200)"
  while IFS= read -r imp; do
    case "$imp" in
      node:*|./tree-hash.mjs) ;;
      *) log_fail "TEST-3267: checkout-trace.mjs imports '$imp'" ;;
    esac
  done < <(sed -n "s/^import .* from '\\([^']*\\)';\$/\\1/p" "$mod")
  log_pass "TEST-3267 (identity literal, no source-text reader, line caps, imports)"
}

# test_3261..3266: node:test cases in tests/skills/lib/suite-reuse.test.mjs.
test_3261_trace_module() { node_cases TEST-3261; }
test_3262_traced_input_edit() { node_cases TEST-3262; }
test_3263_path_list() { node_cases TEST-3263; }
test_3264_history_only_when_git_read() { node_cases TEST-3264; }
test_3265_index_read_whole_tree() { node_cases TEST-3265; }
test_3266_env_from_files_read() { node_cases TEST-3266; }

# test_3260: a declared fixture suite run through the real framework leaves a trace naming
# exactly the checkout files it read (bash cat, grep, source; node readFileSync), replaced
# (sed -i) or deleted, and none it only created or never touched.
test_3260_trace_lists_what_the_suite_read() {
  local base r dir out
  base="$(new_base)"
  r="$base/repo"
  build_fx "$base" aai-fx
  printf 'a\n' > "$r/a.txt"; printf 'xline\n' > "$r/b.txt"; printf 'C=1\n' > "$r/c.sh"
  printf 'd\n' > "$r/d.txt"; printf 'old\n' > "$r/e.txt"; printf 'f\n' > "$r/f.txt"; printf 'u\n' > "$r/u.txt"
  cat > "$r/tests/skills/test-aai-fx.sh" <<'EOS'
#!/usr/bin/env bash
cat a.txt > /dev/null
grep -q xline b.txt
source ./c.sh
node -e "require('fs').readFileSync('d.txt')"
sed -i.bak 's/old/new/' e.txt
rm f.txt
echo g > g.txt
exit 0
EOS
  (cd "$r" && git add -A && git commit -q -m trace-suite) || log_fail "TEST-3260: fixture could not be committed"
  fw_go "$base" -- --skill aai-fx
  [[ "$RC" -eq 0 ]] || { show_out; log_fail "TEST-3260: framework run exited $RC"; }
  dir="$(newest_run_dir "$base")"
  [[ -f "$dir/aai-fx.reuse-arm.json" && -f "$dir/aai-fx.reuse-trace.json" ]] \
    || { ls "$dir" >&2; log_fail "TEST-3260: the run left no arm or trace file"; }
  out="$(TRACE="$dir/aai-fx.reuse-trace.json" node -e '
    const t = JSON.parse(require("fs").readFileSync(process.env.TRACE, "utf8"));
    const names = Object.keys(t.inputs).filter((p) => !p.startsWith(".git/")).sort();
    const want = ["a.txt", "b.txt", "c.sh", "d.txt", "e.txt", "f.txt", "tests/skills/test-aai-fx.sh"];
    const bad = [];
    if (JSON.stringify(names) !== JSON.stringify(want)) bad.push("inputs " + names.join(","));
    if (t.canary !== true) bad.push("canary " + t.canary);
    if (t.git_read !== false) bad.push("git_read " + t.git_read);
    if (t.index_read !== false) bad.push("index_read " + t.index_read);
    console.log(bad.length ? "FAIL " + bad.join("; ") : "OK");
  ')"
  [[ "$out" == OK ]] || log_fail "TEST-3260: $out"
  log_pass "TEST-3260 (trace names the read, replaced and deleted files; not the untouched or created ones)"
}

# test_3268, test_3269: node:test cases in tests/skills/lib/suite-reuse.test.mjs.
test_3268_record_refusals_trace() { node_cases TEST-3268; }
test_3269_canary() { node_cases TEST-3269; }

# admit_run <base> [VAR=val ...] -- <lint --admit args>: run the fixture's own helper; sets OUT and RC.
admit_run() {
  local base="$1" envs=()
  shift
  while [[ "$1" != "--" ]]; do envs+=("$1"); shift; done
  shift
  RC=0
  OUT="$(env -u AAI_ROLE -u CI -u GITHUB_ACTIONS -u AAI_SUITE_REUSE ${envs[@]+"${envs[@]}"} \
    node "$base/repo/.aai/scripts/suite-reuse.mjs" lint --root "$base/repo" --admit "$@" 2>&1)" || RC=$?
}
commit_fx() { (cd "$1/repo" && git add -A && git commit -q -m "$2") || log_fail "fixture could not be committed ($2)"; }

# test_3270: a suite that reads a file and restores its access time hides the read from the
# trace; the poisoned run (every unread file overwritten) fails, so admission refuses it.
test_3270_poisoned_run() {
  local base r
  base="$(new_base)"; r="$base/repo"
  build_fx "$base" hide
  printf 'the-secret\n' > "$r/secret.txt"
  printf '#!/usr/bin/env bash\nline="$(head -n 1 secret.txt)"\ntouch -a -t 199901010000 secret.txt\n[[ "$line" == "the-secret" ]] || exit 1\nexit 0\n' > "$r/tests/skills/test-hide.sh"
  commit_fx "$base" hide
  admit_run "$base" --
  [[ "$RC" -eq 1 ]] || { printf '%s\n' "$OUT" >&2; log_fail "TEST-3270: expected exit 1, got $RC"; }
  expect "TEST-3270" "$OUT" "ADMIT-FAIL hide "
  expect "TEST-3270" "$OUT" "poisoned run failed"
  log_pass "TEST-3270 (a hidden read fails the poisoned run, admission exits 1)"
}

# test_3271: the same for a Node read hidden with utimesSync and a suite that never fails on content:
# only the preload cross-check can see it.
test_3271_node_read_cross_check() {
  local base r
  base="$(new_base)"; r="$base/repo"
  build_fx "$base" nodehide
  printf 'n\n' > "$r/n.txt"
  cat > "$r/tests/skills/test-nodehide.sh" <<'EOS'
#!/usr/bin/env bash
node -e "const fs = require('fs'); const st = fs.statSync('n.txt'); fs.readFileSync('n.txt'); fs.utimesSync('n.txt', 946684800, st.mtime)"
exit 0
EOS
  commit_fx "$base" nodehide
  admit_run "$base" --
  [[ "$RC" -eq 1 ]] || { printf '%s\n' "$OUT" >&2; log_fail "TEST-3271: expected exit 1, got $RC"; }
  expect "TEST-3271" "$OUT" "ADMIT-FAIL nodehide "
  expect "TEST-3271" "$OUT" "trace-misses-node-read n.txt"
  log_pass "TEST-3271 (a Node read with a restored access time is caught by the preload cross-check)"
}

# test_3273: an honest suite is admitted; the output shows the read probe as RUN, the unread one as REUSE.
test_3273_admission_pass() {
  local base r
  base="$(new_base)"; r="$base/repo"
  build_fx "$base" ok
  printf 'one\n' > "$r/d1.txt"; printf 'two\n' > "$r/d2.txt"; printf 'three\n' > "$r/d3.txt"
  printf '#!/usr/bin/env bash\ncat d1.txt > /dev/null\nexit 0\n' > "$r/tests/skills/test-ok.sh"
  commit_fx "$base" ok
  admit_run "$base" --
  [[ "$RC" -eq 0 ]] || { printf '%s\n' "$OUT" >&2; log_fail "TEST-3273: expected exit 0, got $RC"; }
  expect "TEST-3273" "$OUT" "ADMIT-PROBE ok read d1.txt RUN"
  expect "TEST-3273" "$OUT" "ADMIT-PROBE ok unread "
  [[ "$OUT" =~ ADMIT-PROBE\ ok\ unread\ [^[:space:]]+\ REUSE ]] || log_fail "TEST-3273: the unread probe did not give REUSE"
  [[ "$OUT" =~ ADMIT-PASS\ ok\ [0-9.]+s\ reads=[0-9]+\ poisoned=[2-9][0-9]* ]] || { printf '%s\n' "$OUT" >&2; log_fail "TEST-3273: no ADMIT-PASS line with reads and poisoned counts"; }
  local mrc=0 mout
  mout="$(env -u AAI_ROLE node "$r/.aai/scripts/suite-reuse.mjs" lint --root "$r" --minimal-tree 2>&1)" || mrc=$?
  [[ "$mrc" -eq 2 ]] || log_fail "TEST-3273: lint --minimal-tree must refuse with exit 2, got $mrc"
  expect "TEST-3273" "$mout" "--minimal-tree was replaced by --admit"
  log_pass "TEST-3273 (ADMIT-PASS with reads and poisoned counts; read probe RUN, unread probe REUSE; the retired --minimal-tree flag exits 2)"
}

# test_3274: --changed-since admits only changed entries; CI turns admission off.
test_3274_changed_since_and_ci() {
  local base r
  base="$(new_base)"; r="$base/repo"
  build_fx "$base" aa bb
  admit_run "$base" -- --changed-since HEAD
  [[ "$RC" -eq 0 ]] || { printf '%s\n' "$OUT" >&2; log_fail "TEST-3274: ADMIT-NONE run exited $RC"; }
  expect "TEST-3274 none" "$OUT" "ADMIT-NONE"
  expect_not "TEST-3274 none" "$OUT" "ADMIT-PASS"
  sed -i.bak 's/"aa":{"inputs":\[\],"live":false,"note":"fixture suite reads only its closure"}/"aa":{"inputs":[],"live":false,"note":"changed note"}/' "$r/tests/skills/suite-reuse.json"
  rm -f "$r/tests/skills/suite-reuse.json.bak"
  admit_run "$base" -- --changed-since HEAD
  [[ "$RC" -eq 0 ]] || { printf '%s\n' "$OUT" >&2; log_fail "TEST-3274: changed-entry run exited $RC"; }
  expect "TEST-3274 changed" "$OUT" "ADMIT-PASS aa "
  expect_not "TEST-3274 changed" "$OUT" " bb "
  admit_run "$base" CI=true -- --changed-since HEAD
  [[ "$RC" -eq 0 ]] || log_fail "TEST-3274: CI run exited $RC"
  expect "TEST-3274 ci" "$OUT" "ADMIT-OFF ci"
  expect_not "TEST-3274 ci" "$OUT" "ADMIT-PASS"
  log_pass "TEST-3274 (ADMIT-NONE, only the changed entry admitted, ADMIT-OFF ci)"
}

# test_3275: the live manifest lists the eleven suites, each live false with a note, each selected by the gate row.
test_3275_live_manifest() {
  local out rc=0 src suite f
  out="$(env -u AAI_ROLE node "$PROJECT_ROOT/.aai/scripts/suite-reuse.mjs" lint --root "$PROJECT_ROOT" 2>&1)" || rc=$?
  [[ "$rc" -eq 0 ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-3275: lint exited $rc"; }
  src="$(MAN="$PROJECT_ROOT/tests/skills/suite-reuse.json" node -e '
    const m = JSON.parse(require("fs").readFileSync(process.env.MAN, "utf8")).suites;
    const want = ["aai-docs-content","aai-spec-lint","aai-hygiene-pack","aai-prompt-diet","aai-ride-status","aai-win-fallback","aai-feedback-status","aai-pricing","aai-redact","aai-orchestration-mode","aai-runtime-file"];
    const bad = want.filter((s) => !m[s] || m[s].live !== false || typeof m[s].note !== "string" || !m[s].note.trim());
    console.log(bad.length ? "FAIL " + bad.join(",") : "OK");
  ')"
  [[ "$src" == OK ]] || log_fail "TEST-3275: manifest entries missing or unqualified: $src"
  for suite in aai-docs-content aai-spec-lint aai-hygiene-pack aai-prompt-diet aai-ride-status aai-win-fallback; do
    f="tests/skills/test-$suite.sh"
    out="$(printf '%s\n' "$f" | node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from - --repo-root "$PROJECT_ROOT")" \
      || log_fail "TEST-3275: select-suites.mjs failed for $f"
    [[ $'\n'"$out" =~ $'\n'SELECTED\ aai-suite-reuse($|[[:space:]]) ]] || log_fail "TEST-3275: $f does not select aai-suite-reuse"
  done
  log_pass "TEST-3275 (lint clean, eleven qualified entries, six named suite files select the gate)"
}

LIVE_ADMIT_OUT=""
# test_3276: the live admission over every suite that differs from main (all eleven on this branch).
test_3276_live_admission() {
  local out rc=0 n
  if [[ -n "${CI:-}" && "${CI:-}" != false || "${GITHUB_ACTIONS:-}" == true ]]; then
    out="$(env -u AAI_ROLE node "$PROJECT_ROOT/.aai/scripts/suite-reuse.mjs" lint --root "$PROJECT_ROOT" --admit --changed-since main 2>&1)" || rc=$?
    [[ "$rc" -eq 0 && "$out" == *"ADMIT-OFF ci"* ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-3276: expected ADMIT-OFF ci under CI"; }
    LIVE_ADMIT_OUT="$out"
    log_pass "TEST-3276 (ADMIT-OFF ci)"
    return 0
  fi
  out="$(env -u AAI_ROLE -u AAI_SUITE_REUSE node "$PROJECT_ROOT/.aai/scripts/suite-reuse.mjs" lint --root "$PROJECT_ROOT" --admit --changed-since main 2>&1)" || rc=$?
  [[ "$rc" -eq 0 ]] || { printf '%s\n' "$out" | grep -E '^ADMIT-' >&2; log_fail "TEST-3276: live admission exited $rc"; }
  LIVE_ADMIT_OUT="$out"
  n="$(printf '%s\n' "$out" | grep -c '^ADMIT-PASS ' || true)"
  expect_not "TEST-3276" "$out" "ADMIT-FAIL"
  [[ "$n" -ge 1 || "$out" == *"ADMIT-NONE"* ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-3276: no ADMIT-PASS or ADMIT-NONE line, so nothing was admitted"; }
  log_pass "TEST-3276 ($n ADMIT-PASS lines on the live manifest)"
}

# test_3272: framework ledger writes are not inputs of a suite that does not read them,
# and a ledger read through a path built at run time is (the false hit this scope removes).
test_3272_ledgers_not_inputs() {
  local base r chk n1 n2
  base="$(new_base)"
  r="$base/repo"
  build_fx "$base" aai-fx aai-fy
  printf 'tests/skills/results/\ndocs/ai/STATE.yaml\n' > "$r/.gitignore"
  printf '{"e":1}\n' > "$r/docs/ai/EVENTS.jsonl"
  printf '{"seed":1}\n' > "$r/docs/ai/tests/test-runs.jsonl"
  printf 'state: 1\n' > "$r/docs/ai/STATE.yaml"
  printf '#!/usr/bin/env bash\necho run >> '"'%s/m/aai-fy'"'\nf=docs/ai/EVENTS\ncat "$f.jsonl" > /dev/null\nexit 0\n' "$base" > "$r/tests/skills/test-aai-fy.sh"
  (cd "$r" && git add -A && git commit -q -m ledgers) || log_fail "TEST-3272: fixture could not be committed"
  fw_go "$base" -- --skill aai-fx --skill aai-fy
  [[ "$RC" -eq 0 ]] || { show_out; log_fail "TEST-3272: run 1 exited $RC"; }
  n1="$(wc -l < "$r/docs/ai/tests/test-runs.jsonl" | tr -d ' ')"
  fw_go "$base" -- --skill aai-fx --skill aai-fy
  [[ "$RC" -eq 0 ]] || { show_out; log_fail "TEST-3272: run 2 exited $RC"; }
  expect "TEST-3272 run 2" "$OUT" "Reused:  2"
  n2="$(wc -l < "$r/docs/ai/tests/test-runs.jsonl" | tr -d ' ')"
  [[ "$n2" -gt "$n1" ]] || log_fail "TEST-3272: the framework did not append to test-runs.jsonl ($n1 / $n2)"
  printf '{"e":2}\n' >> "$r/docs/ai/EVENTS.jsonl"
  printf 'state: 2\n' > "$r/docs/ai/STATE.yaml"
  chk="$(helper_check "$base" aai-fx)"
  expect "TEST-3272 fx" "$chk" "REUSE aai-fx "
  chk="$(helper_check "$base" aai-fy)"
  expect "TEST-3272 fy" "$chk" "RUN aai-fy reason=inputs changed docs/ai/EVENTS.jsonl"
  log_pass "TEST-3272 (framework ledger append, EVENTS append and STATE edit leave aai-fx REUSED; aai-fy reads EVENTS through a built path and runs)"
}

# test_3277: arm and collect run around a declared suite only, serially and in a wave,
# never when reuse is opted out, and a failing arm does not change the verdict.
test_3277_framework_wiring() {
  local base r dir mode
  for mode in 1 2; do
    base="$(new_base)"
    r="$base/repo"
    build_fx "$base" aai-fx
    fx_suite "$base" aai-fz 0
    printf '  aai-fz:\n    globs:\n      - tests/skills/test-aai-fz.sh\n' >> "$r/tests/skills/suite-map.yaml"
    (cd "$r" && git add -A && git commit -q -m undeclared) || log_fail "TEST-3277: fixture could not be committed"
    fw_go "$base" AAI_TEST_PARALLEL="$mode" -- --skill aai-fx --skill aai-fz
    [[ "$RC" -eq 0 ]] || { show_out; log_fail "TEST-3277: run (parallel $mode) exited $RC"; }
    dir="$(newest_run_dir "$base")"
    [[ -f "$dir/aai-fx.reuse-arm.json" && -f "$dir/aai-fx.reuse-trace.json" ]] \
      || { ls "$dir" >&2; log_fail "TEST-3277: declared suite left no arm or trace file (parallel $mode)"; }
    [[ ! -e "$dir/aai-fz.reuse-arm.json" && ! -e "$dir/aai-fz.reuse-trace.json" ]] \
      || log_fail "TEST-3277: an undeclared suite was traced (parallel $mode)"
    fw_go "$base" AAI_SUITE_REUSE=0 AAI_TEST_PARALLEL="$mode" -- --skill aai-fx --skill aai-fz
    dir="$(newest_run_dir "$base")"
    [[ ! -e "$dir/aai-fx.reuse-arm.json" && ! -e "$dir/aai-fx.reuse-trace.json" ]] \
      || log_fail "TEST-3277: an opted-out run was traced (parallel $mode)"
  done
  base="$(new_base)"
  r="$base/repo"
  build_fx "$base" aai-fx
  sed 's/^export function armTrace(.*/&\n  throw new Error("arm sabotaged");/' "$r/.aai/scripts/lib/checkout-trace.mjs" > "$r/ct.tmp" && mv "$r/ct.tmp" "$r/.aai/scripts/lib/checkout-trace.mjs"
  (cd "$r" && git add -A && git commit -q -m sabotage) || log_fail "TEST-3277: fixture could not be committed"
  fw_go "$base" -- --skill aai-fx
  [[ "$RC" -eq 0 ]] || { show_out; log_fail "TEST-3277: a failing arm changed the verdict (exit $RC)"; }
  expect "TEST-3277 failing arm" "$OUT" "Passed:  1 (100%)"
  [[ ! -e "$(newest_run_dir "$base")/aai-fx.reuse-arm.json" ]] || log_fail "TEST-3277: sabotaged arm still wrote a file"
  log_pass "TEST-3277 (declared suite traced serially and in a wave; undeclared and opted-out not; failing arm keeps the verdict)"
}

# test_3278: the Reuse exception paragraph says files read, and the prompt glob did not grow past the baseline commit.
test_3278_canon_wording() {
  local verify="$PROJECT_ROOT/.aai/SKILL_VERIFY.prompt.md" para now=0 was=0 f base=5e9f1350 n
  para="$(awk '/^## Iron Law/ {seen=1} seen && /^Reuse exception:/ {p=1} p && NF==0 {exit} p {print}' "$verify")"
  [[ "$para" == *"files read"* ]] || log_fail "TEST-3278: the Reuse exception paragraph lacks 'files read'"
  [[ "$para" != *"declared inputs"* ]] || log_fail "TEST-3278: the Reuse exception paragraph still says 'declared inputs'"
  if git -C "$PROJECT_ROOT" cat-file -e "$base^{commit}" 2>/dev/null; then
    now="$(cat "$PROJECT_ROOT"/.aai/*.prompt.md | wc -c | tr -d ' ')"
    while IFS= read -r f; do
      n="$(git -C "$PROJECT_ROOT" show "$base:$f" | wc -c | tr -d ' ')"
      was=$((was + n))
    done < <(git -C "$PROJECT_ROOT" ls-tree --name-only "$base" .aai/ | grep '^\.aai/[^/]*\.prompt\.md$')
    [[ "$now" -le "$was" ]] || log_fail "TEST-3278: cat .aai/*.prompt.md is $now B, baseline $base is $was B"
  else
    log_info "TEST-3278: baseline commit $base is not available here, size comparison skipped"
  fi
  log_pass "TEST-3278 (Reuse exception says files read; prompt glob $now B, baseline $was B)"
}

# test_3190: the guarded select-suites.mjs still runs as the entry point and prints
# its selection (CLI contract); the full contract is the unchanged aai-suite-select
# suite, run in Verification. This row exists so the guard's mutation record can
# name a TEST id in a FAIL line.
test_3190_select_suites_cli_still_runs() {
  local selector="$PROJECT_ROOT/.aai/scripts/select-suites.mjs" out rc=0
  out="$(printf '%s\n' .aai/scripts/ride-status.mjs | node "$selector" --files-from - --repo-root "$PROJECT_ROOT")" || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-3190: select-suites.mjs exited $rc as the entry point"
  [[ $'\n'"$out" =~ $'\n'SELECTED\ aai-ride-status($|[[:space:]]) ]] \
    || log_fail "TEST-3190: select-suites.mjs printed no SELECTED aai-ride-status line (got: $(printf '%s' "$out" | tr '\n' ';'))"
  log_pass "TEST-3190 (select-suites.mjs entry point prints its selection)"
}

# test_3184: the Pester twin passes at least 4 cases under pwsh 7, none failed,
# none skipped. Skips the suite when pwsh or Pester 5 is absent (never fakes it).
test_3184_pester_twin() {
  local file="$PROJECT_ROOT/tests/skills/suite-reuse.Tests.ps1" out="" rc=0 tally f s t
  command -v pwsh >/dev/null 2>&1 || log_skip "pwsh not found (TEST-3184)"
  [[ -f "$file" ]] || log_fail "TEST-3184: $file does not exist"
  out="$(env -u AAI_ROLE pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop; \$r = Invoke-Pester -Path '$file' -PassThru -Output None; Write-Output ('TALLY F=' + \$r.FailedCount + ' S=' + \$r.SkippedCount + ' T=' + \$r.TotalCount)" 2>&1)" || rc=$?
  tally="$(printf '%s\n' "$out" | sed -n 's/^TALLY //p' | tail -n 1)"
  if [[ "$rc" -ne 0 || -z "$tally" ]]; then
    printf '%s\n' "$out" | sed -n '1,40p' >&2
    log_fail "TEST-3184: pwsh Pester run failed (rc=$rc): $tally"
  fi
  f="${tally#F=}"; f="${f%% *}"
  s="${tally#*S=}"; s="${s%% *}"
  t="${tally#*T=}"
  [[ "$f" == 0 && "$s" == 0 && "$t" -ge 4 ]] || log_fail "TEST-3184: Pester tally $tally (want F=0 S=0 T>=4)"
  log_pass "TEST-3184 (Pester $tally)"
}

# test_3185: both path lists of ps1-quality.yml carry the helper entry.
test_3185_workflow_path_lists() {
  local wf="$PROJECT_ROOT/.github/workflows/ps1-quality.yml" ev n
  for ev in push pull_request; do
    n="$(awk -v ev="$ev" '
      /^on:/ {on=1; next}
      on && /^[^ #]/ {on=0}
      on && /^  [a-z_]+:/ {cur=$1; sub(":","",cur); next}
      on && cur==ev && $0=="      - '"'"'.aai/scripts/suite-reuse.mjs'"'"'" {c++}
      END {print c+0}' "$wf")"
    [[ "$n" == 1 ]] || log_fail "TEST-3185: $ev list has $n .aai/scripts/suite-reuse.mjs entries (want 1)"
  done
  log_pass "TEST-3185 (push and pull_request lists carry .aai/scripts/suite-reuse.mjs)"
}

# test_3186: the Reuse exception paragraph and the VALIDATION step 5 c2 sentence.
test_3186_canon_reconciliation() {
  local verify="$PROJECT_ROOT/.aai/SKILL_VERIFY.prompt.md" val="$PROJECT_ROOT/.aai/VALIDATION.prompt.md"
  local para c2 term
  para="$(awk '/^## Iron Law/ {seen=1} seen && /^Reuse exception:/ {p=1} p && NF==0 {exit} p {print}' "$verify")"
  [[ -n "$para" ]] || log_fail "TEST-3186: SKILL_VERIFY has no Reuse exception: paragraph after the Iron Law"
  [[ "$(awk '/^## Gate function/ {exit} /^Reuse exception:/ {print "y"}' "$verify")" == y ]] \
    || log_fail "TEST-3186: the Reuse exception: paragraph is not directly in the Iron Law section"
  for term in REUSED 'original run' log 'full sweep before close' CI main nightly release; do
    [[ "$para" == *"$term"* ]] || log_fail "TEST-3186: Reuse exception paragraph lacks '$term'"
  done
  c2="$(awk '/^   c2\) SUITE SCOPE PER ROUND/ {p=1} p && /^   c3\)|^   d\)/ {exit} p {print}' "$val")"
  [[ -n "$c2" ]] || c2="$(sed -n '/c2) SUITE SCOPE PER ROUND/,/TWO ROUNDS MAX/p' "$val")"
  [[ "$c2" == *REUSED* && "$c2" == *'intermediate round'* ]] || log_fail "TEST-3186: VALIDATION step 5 c2 lacks REUSED and intermediate round"
  log_pass "TEST-3186 (Reuse exception paragraph and VALIDATION c2 sentence)"
}

# test_3187: exactly one ledger entry names precise-suite-evidence-reuse, with a
# leading byte count in 1..600. TEST-010/TEST-012 are proved by the prompt-diet suite.
test_3187_ledger_entry() {
  local ledger="$PROJECT_ROOT/tests/skills/lib/prompt-diet-ledger.sh" n bytes
  n="$(grep -c '^JUSTIFIED_ADDITIONS+=( "[0-9][0-9]* precise-suite-evidence-reuse ' "$ledger" || true)"
  [[ "$n" == 1 ]] || log_fail "TEST-3187: $n ledger entries name precise-suite-evidence-reuse (want exactly 1)"
  bytes="$(sed -n 's/^JUSTIFIED_ADDITIONS+=( "\([0-9][0-9]*\) precise-suite-evidence-reuse .*/\1/p' "$ledger")"
  [[ "$bytes" -ge 1 && "$bytes" -le 600 ]] || log_fail "TEST-3187: ledger credit $bytes B is outside 1..600"
  log_pass "TEST-3187 (one ledger entry, $bytes B)"
}

# test_3189: the analysis note carries a Measurements section with at least 3
# samples per mode in each round, reused counts, medians, bounded check times,
# versions, and the plain statements (no comparison of the two medians).
test_3189_analysis_note() {
  local note="$PROJECT_ROOT/docs/analysis/precise-suite-evidence-reuse.md" out
  [[ -f "$note" ]] || log_fail "TEST-3189: $note does not exist"
  out="$(NOTE="$note" node -e '
    const fs = require("fs");
    const t = fs.readFileSync(process.env.NOTE, "utf8");
    const fail = (m) => { console.log("FAIL " + m); process.exit(0); };
    const lines = t.split("\n");
    if (!lines.includes("## Measurements")) fail("no ## Measurements line");
    const rows = lines.filter((l) => /^\| *[A-Za-z0-9-]+ *\| *[0-9]+ *\| *(off|on) *\|/.test(l)).map((l) => l.split("|").map((c) => c.trim()));
    const rounds = [...new Set(rows.map((r) => r[1]))];
    if (rounds.length < 2) fail("fewer than 2 rounds in the sample table");
    for (const rd of rounds) for (const mode of ["off", "on"]) {
      const n = rows.filter((r) => r[1] === rd && r[3] === mode).length;
      if (n < 3) fail("round " + rd + " has " + n + " " + mode + " samples (want 3)");
      if (!new RegExp("^Round " + rd + " medians:.*off.*on.*reused", "m").test(t)) fail("no medians line for round " + rd);
    }
    for (const r of rows) {
      const check = Number(r[7]);
      if (r[3] === "on" && !(check <= 5)) fail("check time " + r[7] + " above 5 s");
    }
    if (!/\b[0-9a-f]{40}\b/.test(t)) fail("no 40-character commit sha");
    for (const w of ["Node", "Bash", "Git"]) if (!new RegExp(w + "[^\\n]*[0-9]+\\.[0-9]+").test(t)) fail("no " + w + " version");
    if (!/^### Where reuse helps/m.test(t)) fail("no Where reuse helps section");
    if (!/^### Why the docs-closure suites miss/m.test(t)) fail("no Why the docs-closure suites miss section");
    console.log("OK " + rows.length + " samples in " + rounds.length + " rounds");
  ')"
  [[ "$out" == OK* ]] || log_fail "TEST-3189: ${out:-node produced no output}"
  log_pass "TEST-3189 (analysis note: ${out#OK })"
}

# test_3279: the analysis note carries the trace-identity measurement of D11: rounds R0 and R1 with at least
# three samples per mode, medians, a per-suite outcome for each of the eight suites, read counts, arm plus
# collect milliseconds, a 40-character sha and the tool versions.
test_3279_trace_measurements() {
  local note="$PROJECT_ROOT/docs/analysis/precise-suite-evidence-reuse.md" out
  [[ -f "$note" ]] || log_fail "TEST-3279: $note does not exist"
  out="$(NOTE="$note" node -e '
    const t = require("fs").readFileSync(process.env.NOTE, "utf8");
    const fail = (m) => { console.log("FAIL " + m); process.exit(0); };
    const lines = t.split("\n");
    const at = lines.indexOf("## Measurements (trace identity)");
    if (at < 0) fail("no ## Measurements (trace identity) line");
    let end = lines.findIndex((l, i) => i > at && /^## /.test(l));
    if (end < 0) end = lines.length;
    const sec = lines.slice(at, end);
    const text = sec.join("\n");
    const rows = sec.filter((l) => /^\| *R[01] *\| *[0-9]+ *\| *(off|on) *\|/.test(l)).map((l) => l.split("|").map((c) => c.trim()));
    for (const rd of ["R0", "R1"]) for (const mode of ["off", "on"]) {
      const n = rows.filter((r) => r[1] === rd && r[3] === mode).length;
      if (n < 3) fail("round " + rd + " has " + n + " " + mode + " samples (want 3)");
      if (!new RegExp("^Round " + rd + " medians:.*off.*on.*reused", "m").test(text)) fail("no medians line for round " + rd);
    }
    for (const s of ["aai-check-state", "aai-docs-content", "aai-spec-lint", "aai-hygiene-pack", "aai-pr-preflight", "aai-prompt-diet", "aai-ride-status", "aai-win-fallback"]) {
      if (!sec.some((l) => l.startsWith("| " + s + " |") && /REUSED|RUN reason=/.test(l))) fail("no REUSED or RUN outcome row for " + s);
      if (!sec.some((l) => l.startsWith("| " + s + " |") && /[0-9]+ files|not traced/.test(l))) fail("no read count for " + s);
    }
    if (!/arm plus collect[^\n]*[0-9]+ ms/i.test(text)) fail("no arm plus collect milliseconds");
    if (!/\b[0-9a-f]{40}\b/.test(text)) fail("no 40-character commit sha");
    for (const w of ["Node", "Bash", "Git"]) if (!new RegExp(w + "[^\\n]*[0-9]+\\.[0-9]+").test(text)) fail("no " + w + " version");
    console.log("OK " + rows.length + " samples");
  ')"
  [[ "$out" == OK* ]] || log_fail "TEST-3279: ${out:-node produced no output}"
  log_pass "TEST-3279 (trace-identity measurements: ${out#OK })"
}

# test_3300: a suite that reads the git index is REUSED on an unchanged rerun although the framework
# appended its run line to the tracked ledger docs/ai/tests/test-runs.jsonl after each run.
test_3300_ledger_append_reused() {
  local base r n1 n2 n3
  base="$(new_base)"
  r="$base/repo"
  build_fx "$base" aai-fx aai-ix
  printf 'tests/skills/results/\n' > "$r/.gitignore"
  printf '{"seed":1}\n' > "$r/docs/ai/tests/test-runs.jsonl"
  printf 'a\n' > "$r/a.txt"
  printf '#!/usr/bin/env bash\necho run >> '"'%s/m/aai-ix'"'\ngit status --porcelain > /dev/null 2>&1\ncat a.txt > /dev/null\nexit 0\n' "$base" > "$r/tests/skills/test-aai-ix.sh"
  (cd "$r" && git add -A && git commit -q -m ledger) || log_fail "TEST-3300: fixture could not be committed"
  fw_go "$base" -- --skill aai-ix
  [[ "$RC" -eq 0 ]] || { show_out; log_fail "TEST-3300: run 1 exited $RC"; }
  n1="$(wc -l < "$r/docs/ai/tests/test-runs.jsonl" | tr -d ' ')"
  fw_go "$base" -- --skill aai-ix
  [[ "$RC" -eq 0 ]] || { show_out; log_fail "TEST-3300: run 2 exited $RC"; }
  n2="$(wc -l < "$r/docs/ai/tests/test-runs.jsonl" | tr -d ' ')"
  [[ "$n2" -gt "$n1" ]] || log_fail "TEST-3300: run 1 did not append to the ledger ($n1 / $n2)"
  if [[ "$OUT" != *"REUSED (run "* ]]; then
    printf '%s\n' "$(helper_check "$base" aai-ix)" >&2
    show_out
    log_fail "TEST-3300: run 2 did not report aai-ix REUSED"
  fi
  fw_go "$base" -- --skill aai-ix
  [[ "$RC" -eq 0 ]] || { show_out; log_fail "TEST-3300: run 3 exited $RC"; }
  n3="$(wc -l < "$r/docs/ai/tests/test-runs.jsonl" | tr -d ' ')"
  [[ "$n3" -gt "$n2" ]] || log_fail "TEST-3300: run 2 did not append to the ledger ($n2 / $n3)"
  expect "TEST-3300 run 3" "$OUT" "REUSED (run "
  [[ "$(marker_count "$base" aai-ix)" -eq 1 ]] || log_fail "TEST-3300: the suite executed more than once ($(marker_count "$base" aai-ix))"
  log_pass "TEST-3300 (index-reading suite REUSED across two framework ledger appends)"
}
test_3301_ledger_tolerance_rules() { node_cases TEST-3301; }
test_3302_tolerance_scope() { node_cases TEST-3302; }

# test_3304: an index-reading suite that fails when the last ledger line is the appended probe line is refused.
test_3304_tail_read_refused() {
  local base r
  base="$(new_base)"; r="$base/repo"
  build_fx "$base" tailread
  printf 'a\n' > "$r/a.txt"
  printf '#!/usr/bin/env bash\ngit status --porcelain > /dev/null 2>&1\ncat a.txt > /dev/null\nlast="$(tail -n 1 docs/ai/tests/test-runs.jsonl 2>/dev/null || true)"\n[[ "$last" != *AAI-REUSE-POISON* ]] || exit 1\nexit 0\n' > "$r/tests/skills/test-tailread.sh"
  commit_fx "$base" tailread
  admit_run "$base" --
  [[ "$RC" -eq 1 ]] || { printf '%s\n' "$OUT" >&2; log_fail "TEST-3304: expected exit 1, got $RC"; }
  expect "TEST-3304" "$OUT" "ADMIT-FAIL tailread "
  expect "TEST-3304" "$OUT" "appended-ledger run failed"
  log_pass "TEST-3304 (a suite that reads the appended ledger line fails admission)"
}

# test_3305: an index-reading suite that ignores the ledger gets the appended probe line; a suite without index_read gets none.
test_3305_tail_ignored_admitted() {
  local base r
  base="$(new_base)"; r="$base/repo"
  build_fx "$base" tailok plain
  printf 'a\n' > "$r/a.txt"
  printf '#!/usr/bin/env bash\ngit status --porcelain > /dev/null 2>&1\ncat a.txt > /dev/null\nexit 0\n' > "$r/tests/skills/test-tailok.sh"
  printf '#!/usr/bin/env bash\ncat a.txt > /dev/null\nexit 0\n' > "$r/tests/skills/test-plain.sh"
  commit_fx "$base" tailok
  admit_run "$base" --
  [[ "$RC" -eq 0 ]] || { printf '%s\n' "$OUT" >&2; log_fail "TEST-3305: expected exit 0, got $RC"; }
  expect "TEST-3305" "$OUT" "ADMIT-PROBE tailok appended docs/ai/tests/test-runs.jsonl PASS"
  expect "TEST-3305" "$OUT" "ADMIT-PASS tailok "
  expect "TEST-3305" "$OUT" "ADMIT-PASS plain "
  expect_not "TEST-3305" "$OUT" "ADMIT-PROBE plain appended"
  log_pass "TEST-3305 (index-reading suite gets the appended probe PASS; the non-index suite gets none)"
}
test_3303_append_prefix_recorded() { node_cases TEST-3303; }

FIVE_INDEX_SUITES="aai-docs-content aai-spec-lint aai-hygiene-pack aai-prompt-diet aai-win-fallback"

# test_3306: lint is clean on the live repository and the five index-reading suites say what their identity tolerates.
test_3306_live_notes() {
  local lrc=0 lout out
  lout="$(env -u AAI_ROLE node "$PROJECT_ROOT/.aai/scripts/suite-reuse.mjs" lint --root "$PROJECT_ROOT" 2>&1)" || lrc=$?
  [[ "$lrc" -eq 0 ]] || { printf '%s\n' "$lout" >&2; log_fail "TEST-3306: lint exited $lrc"; }
  out="$(ROOT="$PROJECT_ROOT" SUITES="$FIVE_INDEX_SUITES" node -e '
    const m = JSON.parse(require("fs").readFileSync(process.env.ROOT + "/tests/skills/suite-reuse.json", "utf8"));
    const bad = process.env.SUITES.split(" ").filter((s) => !(m.suites[s] && m.suites[s].note.includes("docs/ai/tests/test-runs.jsonl")));
    console.log(bad.length ? "MISSING " + bad.join(",") : "OK");
  ')"
  [[ "$out" == OK ]] || log_fail "TEST-3306: manifest notes do not name docs/ai/tests/test-runs.jsonl: $out"
  log_pass "TEST-3306 (lint clean; the five index-reading notes name the run ledger)"
}

# test_3307: the live admission of TEST-3276 admitted each changed index-reading suite with the appended probe.
test_3307_live_appended_probes() {
  local s n=0
  if [[ -z "$LIVE_ADMIT_OUT" ]]; then
    # Run alone (mutation-run dispatch): do the admission here and judge its lines, not its exit code.
    LIVE_ADMIT_OUT="$(env -u AAI_ROLE -u AAI_SUITE_REUSE node "$PROJECT_ROOT/.aai/scripts/suite-reuse.mjs" lint --root "$PROJECT_ROOT" --admit --changed-since main 2>&1 || true)"
  fi
  if [[ "$LIVE_ADMIT_OUT" == *"ADMIT-OFF ci"* ]]; then log_pass "TEST-3307 (ADMIT-OFF ci)"; return 0; fi
  for s in $FIVE_INDEX_SUITES; do
    if [[ "$LIVE_ADMIT_OUT" == *"ADMIT-PASS $s "* ]]; then
      n=$((n + 1))
      expect "TEST-3307 $s" "$LIVE_ADMIT_OUT" "ADMIT-PROBE $s appended docs/ai/tests/test-runs.jsonl PASS"
    fi
  done
  [[ "$n" -ge 1 ]] || { printf '%s\n' "$LIVE_ADMIT_OUT" | grep -E '^ADMIT-' >&2; log_fail "TEST-3307: none of the five index-reading suites was admitted"; }
  log_pass "TEST-3307 ($n live index-reading suites admitted with the appended probe)"
}

# test_3308: the analysis note holds the before and after measurement of the ledger append.
test_3308_ledger_append_measurements() {
  local note="$PROJECT_ROOT/docs/analysis/precise-suite-evidence-reuse.md" out
  out="$(NOTE="$note" SUITES="$FIVE_INDEX_SUITES" node -e '
    const fs = require("fs");
    const lines = fs.readFileSync(process.env.NOTE, "utf8").split("\n");
    const fail = (m) => { console.log("FAIL " + m); process.exit(0); };
    const at = lines.indexOf("## Measurements (ledger append)");
    if (at < 0) fail("no ## Measurements (ledger append) line");
    let end = lines.findIndex((l, i) => i > at && /^## /.test(l));
    if (end < 0) end = lines.length;
    const sec = lines.slice(at, end);
    const text = sec.join("\n");
    if ((text.match(/\b[0-9a-f]{40}\b/g) || []).length < 2) fail("fewer than two 40-character shas");
    const row = (when, s) => sec.find((l) => l.startsWith("| " + when + " | " + s + " |"));
    for (const s of process.env.SUITES.split(" ")) {
      const b = row("before", s), a = row("after", s);
      if (!b || !a) fail("no before or after row for " + s);
      if (!b.includes("RUN reason=inputs changed docs/ai/tests/test-runs.jsonl")) fail("before row of " + s + " lacks the ledger RUN reason");
      if (!/REUSED/.test(a)) fail("after row of " + s + " is not REUSED");
    }
    const all = sec.filter((l) => /^\| (before|after) \|/.test(l)).length;
    if (all < 22) fail("only " + all + " before or after rows (want 22)");
    for (const w of ["Node", "Bash", "Git"]) if (!new RegExp(w + "[^\\n]*[0-9]+\\.[0-9]+").test(text)) fail("no " + w + " version");
    console.log("OK " + all + " rows");
  ')"
  [[ "$out" == OK* ]] || log_fail "TEST-3308: ${out:-node produced no output}"
  log_pass "TEST-3308 (ledger append measurements: ${out#OK })"
}

main() {
  echo "Testing $TEST_NAME (spec-precise-suite-evidence-reuse, spec-reuse-for-docs-reading-suites)"
  check_deps
  test_3166_inputs_tracked_and_untracked
  test_3260_trace_lists_what_the_suite_read
  test_3261_trace_module
  test_3262_traced_input_edit
  test_3263_path_list
  test_3264_history_only_when_git_read
  test_3265_index_read_whole_tree
  test_3266_env_from_files_read
  test_3267_source_shape
  test_3278_canon_wording
  test_3268_record_refusals_trace
  test_3269_canary
  test_3270_poisoned_run
  test_3271_node_read_cross_check
  test_3273_admission_pass
  test_3274_changed_since_and_ci
  test_3275_live_manifest
  test_3276_live_admission
  test_3307_live_appended_probes
  test_3272_ledgers_not_inputs
  test_3277_framework_wiring
  test_3168_env_component
  test_3169_args_component
  test_3170_runtime_component
  test_3171_policy_component
  test_3165_reused_not_executed
  test_3173_undeclared_live_invalid
  test_3174_manifest_invalid
  test_3175_fail_forgets_skip_not_recorded
  test_3176_record_refusals
  test_3195_bash_startup_hook
  test_3196_record_no_identity
  test_3177_off_modes_execute
  test_3178_off_modes
  test_3179_fresh_mandatory_callers
  test_3180_reused_accounting
  test_3181_log_missing
  test_3182_lint_and_live_manifest
  test_3183_select_suites_import
  test_3188_profiles_selection_and_source_shape
  test_3190_select_suites_cli_still_runs
  test_3192_renamed_read_file_not_reused
  test_3184_pester_twin
  test_3185_workflow_path_lists
  test_3186_canon_reconciliation
  test_3187_ledger_entry
  test_3189_analysis_note
  test_3279_trace_measurements
  test_3300_ledger_append_reused
  test_3301_ledger_tolerance_rules
  test_3302_tolerance_scope
  test_3303_append_prefix_recorded
  test_3304_tail_read_refused
  test_3305_tail_ignored_admitted
  test_3306_live_notes
  test_3308_ledger_append_measurements
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Single-function invocation mode (mutation-run.mjs positional dispatch).
  if [[ -n "${1:-}" ]]; then
    "$1"
  else
    main "$@"
  fi
fi
