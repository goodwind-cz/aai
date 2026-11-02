#!/usr/bin/env bash
#
# Test: aai-reap-tests
# (docs/specs/SPEC-0267-spec-node-first-reap-tests.md, TEST-3230..3250)
#
# The test-process reaper is one Node module (.aai/scripts/aai-reap-tests.mjs)
# plus two thin launchers (.aai/scripts/aai-reap-tests.sh and .ps1). SAFETY: every
# real-process case here uses only self-terminating Node sleepers (90 s) in a fresh
# mktemp workspace, kills strictly by recorded pid (and only while that pid still
# shows the fixture's own command line), and never uses pkill, killall or a name.
# The reaper is never pointed at the real workspace or at a root.
#
# bash 3.2 compatible (no ${var^^}, no declare -A).
#
# Usage:
#   bash tests/skills/test-aai-reap-tests.sh                  # run all
#   bash tests/skills/test-aai-reap-tests.sh test_3236_launchers_thin
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-reap-tests"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MJS="$PROJECT_ROOT/.aai/scripts/aai-reap-tests.mjs"
SH_LAUNCHER="$PROJECT_ROOT/.aai/scripts/aai-reap-tests.sh"
PS1_LAUNCHER="$PROJECT_ROOT/.aai/scripts/aai-reap-tests.ps1"
NODE_TEST="$PROJECT_ROOT/tests/skills/lib/aai-reap-tests.test.mjs"
PESTER_FILE="$PROJECT_ROOT/tests/skills/aai-reap-tests.Tests.ps1"
RFC17="$PROJECT_ROOT/docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md"
R16_LINE="aai-reap-tests: refused - node not found in PATH or aai-reap-tests.mjs missing; nothing was reaped"
SLEEPERS=""   # "<pid>" list of every sleeper this suite started

cleanup() {
  kill_sleepers
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then echo "INFO: keeping fixture at $TEST_DIR"; return 0; fi
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then rm -rf "$TEST_DIR"; fi
}
trap cleanup EXIT

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  log_pass "Dependencies checked"
}

setup_fixture() {
  TEST_DIR="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/aai-reap-tests-suite.XXXXXX")" && pwd -P)"
}

# need_tool <TEST id> <tool>: 0 when present; fail on CI when absent; named SKIP-CASE otherwise.
need_tool() {
  command -v "$2" >/dev/null 2>&1 && return 0
  [[ -z "${CI:-}" ]] || log_fail "$1: $2 is required on CI but is not on PATH"
  echo "SKIP-CASE: $1 needs $2, which is not installed here"
  return 1
}

# ---- sleepers: self-terminating Node processes, killed by recorded pid only ----

# start_sleeper <dir>: sets SLP to the pid of `node -e <sleep 90 s> vitest <dir>/worker` (does not fork a subshell).
SLP=""
start_sleeper() {
  node -e 'setTimeout(function () {}, 90000)' vitest "$1/worker" >/dev/null 2>&1 &
  SLP=$!
  disown "$SLP" 2>/dev/null || true
  SLEEPERS="$SLEEPERS $SLP"
}

# kill_sleepers: SIGKILL each recorded pid while it still shows this suite's TEST_DIR in its command line.
kill_sleepers() {
  local p args
  for p in $SLEEPERS; do
    args="$(ps -o args= -p "$p" 2>/dev/null || true)"
    [[ -n "$TEST_DIR" && "$args" == *"$TEST_DIR"* ]] && kill -9 "$p" >/dev/null 2>&1 || true
  done
  SLEEPERS=""
}

# is_alive <pid>: 0 while the process exists and is not a zombie.
is_alive() {
  local st
  st="$(ps -o stat= -p "$1" 2>/dev/null || true)"
  st="${st//[[:space:]]/}"
  [[ -n "$st" && "$st" != Z* ]]
}

wait_gone() {  # wait_gone <pid> <seconds>
  local i=0
  while is_alive "$1" && [[ "$i" -lt $(($2 * 10)) ]]; do sleep 0.1; i=$((i + 1)); done
  ! is_alive "$1"
}

# run_node_tests <TEST id>: the module and node test file must exist; cases named with the id must
# pass; zero passing tests is a failure (a pattern that matches nothing is not a pass).
run_node_tests() {
  local id="$1" out rc=0
  [[ -f "$MJS" ]] || log_fail "$id: .aai/scripts/aai-reap-tests.mjs does not exist"
  [[ -f "$NODE_TEST" ]] || log_fail "$id: tests/skills/lib/aai-reap-tests.test.mjs does not exist"
  out="$(env -u AAI_ROLE node --test --test-name-pattern "$id" "$NODE_TEST" 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "$id: node --test exited $rc"; }
  [[ "$out" =~ pass\ [1-9] ]] || { printf '%s\n' "$out" >&2; log_fail "$id: node --test reported zero passing tests for the pattern"; }
}

test_3230_etime() {
  run_node_tests TEST-3230
  log_pass "TEST-3230: etimeToSecs maps every valid etime and gives -1 for the unparseable, out-of-range and impossible ones"
}

test_3231_config_and_decide() {
  run_node_tests TEST-3231
  log_pass "TEST-3231: parseConfig and decide follow R-6, R-7 and R-8"
}

test_3232_matching() {
  run_node_tests TEST-3232
  log_pass "TEST-3232: matching and workspace normalisation follow R-1 to R-5 per platform"
}

test_3233_snapshot_and_tree() {
  run_node_tests TEST-3233
  log_pass "TEST-3233: snapshot parsing, self and parent exclusion and the subtree walk hold"
}

test_3234_run_posix() {
  run_node_tests TEST-3234
  log_pass "TEST-3234: run on POSIX kills groups and subtrees, waits once, reports four lines and degrades on a listing failure"
}

test_3235_run_win32() {
  run_node_tests TEST-3235
  log_pass "TEST-3235: run on win32 calls taskkill per candidate and delegates to WSL per R-12"
}

# launcher_problems <file> <max lines>: prints problems common to both launchers (empty when clean).
launcher_problems() {
  node -e '
    const fs = require("fs");
    const [file, max, r16] = process.argv.slice(1);
    const buf = fs.readFileSync(file);
    const s = buf.toString("latin1");
    const bad = [];
    if (buf.some((b) => b > 0x7e)) bad.push("byte above 0x7E");
    const lines = s.split("\n").length - (s.endsWith("\n") ? 1 : 0);
    if (lines > Number(max)) bad.push(lines + " lines, cap " + max);
    if (!s.includes("aai-reap-tests.mjs")) bad.push("no reference to aai-reap-tests.mjs");
    for (const t of ["vitest", "esbuild", "etime", "taskkill", "Get-CimInstance", "wsl", "SAFETY INVARIANT"]) if (s.includes(t)) bad.push("holds " + t);
    if (s.split(r16).length !== 2) bad.push("the R-16 line is not present exactly once");
    process.stdout.write(bad.join("; "));
  ' "$1" "$2" "$R16_LINE"
}

test_3236_launchers_thin() {
  local bad code
  bad="$(launcher_problems "$SH_LAUNCHER" 10)"
  [[ -z "$bad" ]] || log_fail "TEST-3236: aai-reap-tests.sh: $bad"
  bad="$(launcher_problems "$PS1_LAUNCHER" 12)"
  [[ -z "$bad" ]] || log_fail "TEST-3236: aai-reap-tests.ps1: $bad"
  [[ "$(head -n 1 "$SH_LAUNCHER")" == "#!/bin/sh" ]] || log_fail "TEST-3236: the sh launcher must start with #!/bin/sh"
  code="$(sed 's/#.*$//' "$SH_LAUNCHER")"
  [[ "$code" != *"[["* ]] || log_fail "TEST-3236: the sh launcher must not use a double-bracket test"
  [[ "$code" != *BASH_SOURCE* ]] || log_fail "TEST-3236: the sh launcher must not use BASH_SOURCE"
  [[ -x "$SH_LAUNCHER" ]] || log_fail "TEST-3236: the sh launcher must be executable"
  grep -qF 'export AAI_REAP_WORKSPACE="${AAI_REAP_WORKSPACE:-$PWD}"' "$SH_LAUNCHER" \
    || log_fail "TEST-3236: the sh launcher lacks the workspace export line"
  log_pass "TEST-3236: both launchers are thin, ASCII, token-free and carry the R-16 line once"
}

# check_refusal: the R-16 contract - exit 1, empty stdout, exactly the refusal line on stderr.
check_refusal() {  # check_refusal <label> <stdout file> <stderr file> <rc>
  [[ "$4" == 1 ]] || log_fail "TEST-3237: $1: exit $4, want 1"
  [[ ! -s "$2" ]] || log_fail "TEST-3237: $1: stdout must be empty, got: $(cat "$2")"
  [[ "$(cat "$3")" == "$R16_LINE" ]] || log_fail "TEST-3237: $1: stderr was: $(cat "$3")"
}

test_3237_launcher_refusal_and_pwd() {
  local bin="$TEST_DIR/t3237-bin" nomod="$TEST_DIR/t3237-nomod" o="$TEST_DIR/t3237.out" e="$TEST_DIR/t3237.err" rc t
  rm -rf "$bin" "$nomod"; mkdir -p "$bin" "$nomod"
  for t in sh dash dirname; do
    command -v "$t" >/dev/null 2>&1 && ln -s "$(command -v "$t")" "$bin/$t"
  done
  rc=0; PATH="$bin" "$bin/sh" -c 'command -v node >/dev/null 2>&1' || rc=$?
  [[ "$rc" != 0 ]] || log_fail "TEST-3237: positive control failed, node still resolves under the stripped PATH"
  for t in sh dash; do
    [[ -e "$bin/$t" ]] || continue
    rc=0; PATH="$bin" "$bin/$t" "$SH_LAUNCHER" > "$o" 2> "$e" || rc=$?
    check_refusal "$t launcher without node" "$o" "$e" "$rc"
  done
  cp "$SH_LAUNCHER" "$nomod/aai-reap-tests.sh"
  rc=0; sh "$nomod/aai-reap-tests.sh" > "$o" 2> "$e" || rc=$?
  check_refusal "sh launcher without the module" "$o" "$e" "$rc"
  if need_tool TEST-3237 pwsh; then
    ln -s "$(command -v pwsh)" "$bin/pwsh"
    rc=0; PATH="$bin" "$bin/pwsh" -NoProfile -File "$PS1_LAUNCHER" > "$o" 2> "$e" || rc=$?
    check_refusal "ps1 launcher without node" "$o" "$e" "$rc"
    cp "$PS1_LAUNCHER" "$nomod/aai-reap-tests.ps1"
    rc=0; pwsh -NoProfile -File "$nomod/aai-reap-tests.ps1" > "$o" 2> "$e" || rc=$?
    check_refusal "ps1 launcher without the module" "$o" "$e" "$rc"
  fi
  # Logical path: a sleeper whose command line holds the symlink spelling of the current directory.
  local root="$TEST_DIR/t3237-ws" out
  rm -rf "$root"; mkdir -p "$root/real"; ln -s real "$root/link"
  start_sleeper "$root/link"
  sleep 1.5
  is_alive "$SLP" || log_fail "TEST-3237: fixture sleeper did not start"
  rc=0; (cd "$root/link" && env -u AAI_REAP_WORKSPACE -u AAI_REAP_STEP_START_EPOCH AAI_REAP_MIN_AGE_SECS=0 sh "$SH_LAUNCHER") > "$o" 2>&1 || rc=$?
  out="$(cat "$o")"
  [[ "$rc" == 0 ]] || log_fail "TEST-3237: the launcher failed from the symlinked directory: $out"
  [[ "$out" == "reaped: 1"* ]] || log_fail "TEST-3237: the logical path was not used, got: $out"
  wait_gone "$SLP" 5 || log_fail "TEST-3237: the sleeper at the logical path survived"
  log_pass "TEST-3237: both launchers refuse without node or module; the sh launcher keeps the logical working directory"
}

test_3238_real_posix_safety() {
  run_node_tests TEST-3238
  log_pass "TEST-3238: the sh launcher reaps only the two pre-step in-workspace trees and leaves no process behind"
}

test_3239_pester_reap() {
  [[ -f "$PESTER_FILE" ]] || log_fail "TEST-3239: tests/skills/aai-reap-tests.Tests.ps1 does not exist"
  need_tool TEST-3239 pwsh || return 0
  local has out rc=0
  has="$(pwsh -NoProfile -Command 'if (Get-Module Pester -ListAvailable | Where-Object { $_.Version.Major -ge 5 }) { "yes" } else { "no" }' 2>/dev/null || echo no)"
  if [[ "$has" != yes ]]; then
    echo "SKIP-CASE: TEST-3239 needs Pester 5 (the ps1-quality gate job is the authoritative runner)"
    return 0
  fi
  out="$(env -u AAI_ROLE PESTER_FILE="$PESTER_FILE" pwsh -NoProfile -Command '
    $cfg = New-PesterConfiguration
    $cfg.Run.Path = $env:PESTER_FILE
    $cfg.Run.PassThru = $true
    $cfg.Output.Verbosity = "Normal"
    $r = Invoke-Pester -Configuration $cfg
    Write-Host "PESTER-RESULT: Total=$($r.TotalCount) Passed=$($r.PassedCount) Failed=$($r.FailedCount) Skipped=$($r.SkippedCount)"
    if ($r.FailedCount -gt 0 -or $r.SkippedCount -gt 0 -or $r.TotalCount -lt 4) { exit 1 }
    exit 0
  ' 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-3239: aai-reap-tests.Tests.ps1 failed, skipped a case or ran fewer than 4 cases (rc=$rc)"; }
  log_pass "TEST-3239: aai-reap-tests.Tests.ps1 passes with no skip ($(printf '%s\n' "$out" | sed -n 's/^PESTER-RESULT: //p'))"
}

test_3240_existing_reaper_cases() {
  local out rc=0
  [[ -f "$MJS" ]] || log_fail "TEST-3240: .aai/scripts/aai-reap-tests.mjs does not exist"
  out="$(env -u AAI_ROLE bash "$PROJECT_ROOT/tests/skills/test-aai-run-tests.sh" 005 006 012 013 015 016 017 018 021 023 030 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" | tail -n 25 >&2; log_fail "TEST-3240: the unchanged real-process reaper cases exited $rc"; }
  log_pass "TEST-3240: the real-process reaper cases of test-aai-run-tests.sh pass through the sh launcher"
}

test_3241_adjusted_cases() {
  local out rc=0 f
  [[ -f "$MJS" ]] || log_fail "TEST-3241: .aai/scripts/aai-reap-tests.mjs does not exist"
  out="$(env -u AAI_ROLE bash "$PROJECT_ROOT/tests/skills/test-aai-run-tests.sh" 019 022 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" | tail -n 25 >&2; log_fail "TEST-3241: test-aai-run-tests.sh 019 022 exited $rc"; }
  rc=0; out="$(env -u AAI_ROLE bash "$PROJECT_ROOT/tests/skills/test-aai-win-fallback.sh" 009 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" | tail -n 25 >&2; log_fail "TEST-3241: test-aai-win-fallback.sh 009 exited $rc"; }
  f="$(sed -n '/^test_019() {/,/^}/p' "$PROJECT_ROOT/tests/skills/test-aai-run-tests.sh")"
  [[ "$f" == *aai-reap-tests.mjs* || "$f" == *REAP_MJS* ]] || log_fail "TEST-3241: run-tests test_019 does not read the module"
  f="$(sed -n '/^test_022() {/,/^}/p' "$PROJECT_ROOT/tests/skills/test-aai-run-tests.sh")"
  [[ "$f" == *aai-reap-tests.mjs* || "$f" == *REAP_MJS* ]] || log_fail "TEST-3241: run-tests test_022 does not use the module"
  f="$(sed -n '/^test_009() {/,/^}/p' "$PROJECT_ROOT/tests/skills/test-aai-win-fallback.sh")"
  [[ "$f" == *aai-reap-tests.mjs* || "$f" == *REAP_MJS* ]] || log_fail "TEST-3241: win-fallback test_009 does not read the module"
  log_pass "TEST-3241: the adjusted TEST-019, TEST-022 and win-fallback TEST-009 read the module and pass"
}

test_3242_amendment_records() {
  local json="$TEST_DIR/t3242.json" out
  node "$PROJECT_ROOT/.aai/scripts/spec-amend.mjs" list --json > "$json"
  out="$(node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const want = [["SPEC-0046", "TEST-006 and TEST-009 re-homed"], ["SPEC-0064", "TEST-004 and TEST-005 re-homed"],
      ["SPEC-0083", "TEST-022 re-homed"], ["SPEC-0121", "TEST-007, TEST-008 and TEST-009 re-homed"], ["SPEC-0249", "TEST-2624 drops aai-reap-tests"]];
    const mine = j.items.filter((i) => i.ref_id === "node-first-reap-tests" && i.amendment_class === "contract");
    const bad = [];
    for (const [id, what] of want) {
      const hit = mine.find((i) => String(i.spec).startsWith("docs/specs/" + id + "-") && String(i.what).startsWith(what));
      if (!hit) bad.push(id + ": no contract record beginning " + what);
    }
    process.stdout.write(bad.join("; "));
  ' "$json")"
  [[ -z "$out" ]] || log_fail "TEST-3242: $out"
  log_pass "TEST-3242: five contract amendment records of this ride name the re-homed specs"
}

test_3243_no_ps_reaper_logic() {
  local list="$TEST_DIR/t3243.files" out names='Get-ReapCandidates|Invoke-ReapNative|Invoke-ReapDispatch|Get-ReapWslDelegationArgs|Get-StepStartFromEpoch'
  [[ -f "$MJS" ]] || log_fail "TEST-3243: .aai/scripts/aai-reap-tests.mjs does not exist"
  git -C "$PROJECT_ROOT" ls-files > "$list"
  out="$(node -e '
    const fs = require("fs"); const path = require("path"); const re = new RegExp(process.argv[2]); const base = process.argv[3];
    const hits = [];
    for (const f of fs.readFileSync(process.argv[1], "utf8").split("\n")) {
      if (!f || f.startsWith("docs/") || f === "tests/skills/test-aai-reap-tests.sh" || f === "tests/skills/lib/aai-reap-tests.test.mjs") continue;
      let s; try { s = fs.readFileSync(path.join(base, f), "utf8"); } catch { continue; }
      if (re.test(s)) hits.push(f);
    }
    process.stdout.write(hits.join(" "));
  ' "$list" "$names" "$PROJECT_ROOT")"
  [[ -z "$out" ]] || log_fail "TEST-3243: files outside docs still name a retired PowerShell reaper function: $out"
  # Positive control: the same scan reports a fixture file that names one.
  mkdir -p "$TEST_DIR/t3243fx"; printf 'x Get-ReapCandidates y\n' > "$TEST_DIR/t3243fx/a.txt"
  out="$(node -e '
    const re = new RegExp(process.argv[1]); process.stdout.write(re.test(require("fs").readFileSync(process.argv[2], "utf8")) ? "reported" : "missed");
  ' "$names" "$TEST_DIR/t3243fx/a.txt")"
  [[ "$out" == reported ]] || log_fail "TEST-3243: positive control failed, the scan missed a fixture naming Get-ReapCandidates"
  if grep -qE "^Describe 'aai-reap-tests" "$PROJECT_ROOT/tests/skills/aai-win-dispatch.Tests.ps1"; then
    log_fail "TEST-3243: aai-win-dispatch.Tests.ps1 still has an aai-reap-tests Describe"
  fi
  [[ "$(grep -c 'SAFETY INVARIANT' "$MJS")" == 1 ]] || log_fail "TEST-3243: the module must hold SAFETY INVARIANT exactly once"
  if grep -q 'SAFETY INVARIANT' "$SH_LAUNCHER" "$PS1_LAUNCHER"; then log_fail "TEST-3243: a launcher holds SAFETY INVARIANT"; fi
  log_pass "TEST-3243: no PowerShell reaper logic is left outside docs; the safety words live once in the module"
}

test_3244_downstream_core_sync() {
  local t="$TEST_DIR/t3244/target dir" ws rc=0 out
  rm -rf "$TEST_DIR/t3244"; mkdir -p "$t"
  bash "$PROJECT_ROOT/.aai/scripts/aai-sync.sh" "$t" --profile core > "$TEST_DIR/t3244.sync.log" 2>&1 || rc=$?
  [[ "$rc" == 0 ]] || log_fail "TEST-3244: aai-sync.sh --profile core exited $rc: $(cat "$TEST_DIR/t3244.sync.log")"
  local f
  for f in aai-reap-tests.mjs aai-reap-tests.sh aai-reap-tests.ps1; do
    [[ -f "$t/.aai/scripts/$f" ]] || log_fail "TEST-3244: the core target lacks .aai/scripts/$f"
  done
  ws="$t/ws"; mkdir -p "$ws"
  start_sleeper "$ws"
  sleep 2
  is_alive "$SLP" || log_fail "TEST-3244: fixture sleeper did not start"
  out="$(env -u AAI_REAP_STEP_START_EPOCH AAI_REAP_WORKSPACE="$ws" AAI_REAP_MIN_AGE_SECS=1 sh "$t/.aai/scripts/aai-reap-tests.sh" 2>&1)" \
    || log_fail "TEST-3244: the target's sh launcher failed: $out"
  [[ "$out" == "reaped: 1"* ]] || log_fail "TEST-3244: expected reaped: 1, got: $out"
  wait_gone "$SLP" 5 || log_fail "TEST-3244: the sleeper survived the target's launcher"
  if need_tool TEST-3244 pwsh; then
    mkdir -p "$t/empty"
    out="$(env -u AAI_REAP_STEP_START_EPOCH AAI_REAP_WORKSPACE="$t/empty" pwsh -NoProfile -File "$t/.aai/scripts/aai-reap-tests.ps1" 2>&1)" \
      || log_fail "TEST-3244: the target's ps1 launcher failed: $out"
    [[ "$out" == "reaped: 0"* ]] || log_fail "TEST-3244: expected reaped: 0 from the ps1 launcher, got: $out"
  fi
  kill_sleepers
  log_pass "TEST-3244: a core sync into a spaced path installs the module and both launchers and they reap correctly"
}

test_3245_profiles_core() {
  local out
  out="$(node -e '
    const lines = require("fs").readFileSync(process.argv[1], "utf8").split("\n");
    const name = ".aai/scripts/aai-reap-tests.mjs";
    const bad = []; let section = null; const at = [];
    lines.forEach((l, i) => { const m = /^([a-z_]+):\s*$/.exec(l); if (m) section = m[1]; if (l.trim() === "- " + name) at.push(section); });
    if (at.length !== 1) bad.push("listed " + at.length + " times");
    else if (at[0] !== "core") bad.push("listed under " + at[0]);
    process.stdout.write(bad.join("; "));
  ' "$PROJECT_ROOT/.aai/system/PROFILES.yaml")"
  [[ -z "$out" ]] || log_fail "TEST-3245: PROFILES.yaml: $out"
  log_pass "TEST-3245: the module is classified once, in the core list"
}

test_3246_suite_map_selects() {
  local p out want
  for p in .aai/scripts/aai-reap-tests.mjs tests/skills/test-aai-reap-tests.sh tests/skills/lib/aai-reap-tests.test.mjs tests/skills/aai-reap-tests.Tests.ps1; do
    out="$(node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from - <<<"$p")"
    [[ "$out" != *FULL_RUN* ]] || log_fail "TEST-3246: $p gives a FULL_RUN line: $out"
    [[ "$out" == *"SELECTED aai-reap-tests"* ]] || log_fail "TEST-3246: $p does not select aai-reap-tests: $out"
  done
  out="$(node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from - <<<".aai/scripts/aai-reap-tests.mjs")"
  for want in aai-run-tests aai-win-fallback; do
    [[ "$out" == *"SELECTED $want"* || "$out" == *"COMPANION $want"* ]] || log_fail "TEST-3246: the module does not select $want: $out"
  done
  log_pass "TEST-3246: the module and the new test files select the right suites without a full run"
}

test_3247_ps1_quality_paths() {
  local out
  out="$(node -e '
    const lines = require("fs").readFileSync(process.argv[1], "utf8").split("\n");
    const lists = {}; let ev = null, inPaths = false;
    for (const l of lines) {
      let m;
      if ((m = /^  (push|pull_request):\s*$/.exec(l))) { ev = m[1]; inPaths = false; lists[ev] = []; continue; }
      if (/^  \S/.test(l)) { ev = null; inPaths = false; continue; }
      if (ev && /^    paths:\s*$/.test(l)) { inPaths = true; continue; }
      if (ev && inPaths) { if ((m = /^      - (.+)$/.exec(l))) lists[ev].push(m[1].trim()); else inPaths = false; }
    }
    const want = "\x27.aai/scripts/aai-reap-tests.mjs\x27";
    const bad = [];
    for (const k of ["push", "pull_request"]) {
      if (!lists[k] || lists[k].length === 0) bad.push(k + ": no path list");
      else if (!lists[k].includes(want)) bad.push(k + ": lacks the module");
    }
    if (lists.push && lists.pull_request && JSON.stringify(lists.push) !== JSON.stringify(lists.pull_request)) bad.push("lists differ");
    process.stdout.write(bad.join("; "));
  ' "$PROJECT_ROOT/.github/workflows/ps1-quality.yml")"
  [[ -z "$out" ]] || log_fail "TEST-3247: ps1-quality.yml path filter: $out"
  log_pass "TEST-3247: both path lists name the module and are identical"
}

test_3248_line_budget() {
  local n sum
  if [[ "$(cat "$RFC17")" =~ pair\ 787\ to\ ([0-9]+)\ lines ]]; then n="${BASH_REMATCH[1]}"; else
    log_fail "TEST-3248: the RFC-0017 slice paragraph does not record 'pair 787 to N lines'"
  fi
  [[ -f "$MJS" ]] || log_fail "TEST-3248: .aai/scripts/aai-reap-tests.mjs does not exist"
  sum="$(cat "$MJS" "$SH_LAUNCHER" "$PS1_LAUNCHER" | wc -l | tr -d '[:space:]')"
  [[ "$n" == "$sum" ]] || log_fail "TEST-3248: the RFC records $n lines but the three files total $sum"
  [[ "$n" -le 345 ]] || log_fail "TEST-3248: N=$n exceeds the 345 line budget"
  log_pass "TEST-3248: the RFC records the live line total ($n <= 345)"
}

test_3249_rfc_inventory() {
  local out rc=0
  out="$(env -u AAI_ROLE bash "$PROJECT_ROOT/tests/skills/test-aai-expert-fetch.sh" test_2624_inventory_matches_tree 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" | tail -n 15 >&2; log_fail "TEST-3249: TEST-2624 exited $rc"; }
  rc=0; out="$(env -u AAI_ROLE bash "$PROJECT_ROOT/tests/skills/test-aai-expert-fetch.sh" test_2623_rfc_phase3_done 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" | tail -n 15 >&2; log_fail "TEST-3249: TEST-2623 exited $rc"; }
  out="$(node -e '
    const lines = require("fs").readFileSync(process.argv[1], "utf8").split("\n");
    const bad = [];
    if (lines.some((l) => /^\| `aai-reap-tests` \|/.test(l))) bad.push("the inventory still has an aai-reap-tests row");
    const row5 = lines.find((l) => /^\| 5 \|/.test(l)) || "";
    if (!/\]\([^)]*node-first-reap-tests\.md\)/.test(row5)) bad.push("the phase 5 row lacks a link ending node-first-reap-tests.md");
    const at = lines.findIndex((l) => l === "### Remaining paired scripts after phase 3");
    const para = lines.slice(at + 1).filter((l) => /^The \[/.test(l)).some((l) => /\]\([^)]*node-first-reap-tests\.md\)/.test(l));
    if (!para) bad.push("no slice paragraph after the table links node-first-reap-tests.md");
    process.stdout.write(bad.join("; "));
  ' "$RFC17")"
  [[ -z "$out" ]] || log_fail "TEST-3249: $out"
  log_pass "TEST-3249: the RFC inventory equals the tree and links the reaper slice in the phase 5 row and below the table"
}

test_3250_docs_true() {
  local out
  out="$(node -e '
    const fs = require("fs");
    const t = fs.readFileSync(process.argv[1], "utf8");
    const g = fs.readFileSync(process.argv[2], "utf8");
    const bad = [];
    const at = t.indexOf("Reaper age guard");
    if (at < 0) bad.push("TECHNOLOGY.md has no Reaper age guard paragraph");
    else {
      const para = t.slice(at).split(/\n\s*\n/)[0];
      if (!para.includes("aai-reap-tests.mjs")) bad.push("the paragraph does not name aai-reap-tests.mjs");
      if (para.includes("Get-ReapCandidates")) bad.push("the paragraph still names Get-ReapCandidates");
      if (para.includes("-StepStart")) bad.push("the paragraph still names -StepStart");
    }
    const gi = g.indexOf("3. **Scoped reaper");
    const item = gi < 0 ? "" : g.slice(gi, gi + 2000).split(/\n\n/)[0];
    if (!item.includes("aai-reap-tests.mjs") || !/exit 1/.test(item)) bad.push("USER_GUIDE.md item 3 lacks the Node sentence naming aai-reap-tests.mjs and exit 1");
    process.stdout.write(bad.join("; "));
  ' "$PROJECT_ROOT/docs/TECHNOLOGY.md" "$PROJECT_ROOT/docs/USER_GUIDE.md")"
  [[ -z "$out" ]] || log_fail "TEST-3250: $out"
  log_pass "TEST-3250: TECHNOLOGY.md and USER_GUIDE.md describe the Node reaper"
}

main() {
  echo "Testing $TEST_NAME (SPEC spec-node-first-reap-tests TEST-3230..3250)"
  check_deps
  setup_fixture
  test_3230_etime
  test_3231_config_and_decide
  test_3232_matching
  test_3233_snapshot_and_tree
  test_3234_run_posix
  test_3235_run_win32
  test_3236_launchers_thin
  test_3237_launcher_refusal_and_pwd
  test_3238_real_posix_safety
  test_3239_pester_reap
  test_3240_existing_reaper_cases
  test_3241_adjusted_cases
  test_3242_amendment_records
  test_3243_no_ps_reaper_logic
  test_3244_downstream_core_sync
  test_3245_profiles_core
  test_3246_suite_map_selects
  test_3247_ps1_quality_paths
  test_3248_line_budget
  test_3249_rfc_inventory
  test_3250_docs_true
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
