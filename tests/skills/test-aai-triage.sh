#!/usr/bin/env bash
#
# Test: aai-triage
# (docs/specs/SPEC-DRAFT-spec-node-first-second-slice.md, TEST-2501..2520)
#
# The L1 triage pair is one Node module (.aai/scripts/triage.mjs) plus two thin
# launchers (triage.sh, triage.ps1). Every function below runs alone under
# single-function dispatch: bash tests/skills/test-aai-triage.sh <function>.
# Fixtures are temporary git repositories holding copies of the launchers and the
# module; the real repository is only read.
#
# bash 3.2 compatible (no ${var^^}, no declare -A).
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-triage"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TRIAGE_SH="$PROJECT_ROOT/.aai/scripts/triage.sh"
TRIAGE_PS1="$PROJECT_ROOT/.aai/scripts/triage.ps1"
TRIAGE_MJS="$PROJECT_ROOT/.aai/scripts/triage.mjs"
TRIAGE_NODE_TEST="$PROJECT_ROOT/tests/skills/lib/triage.test.mjs"
TRIAGE_PESTER="$PROJECT_ROOT/tests/skills/triage.Tests.ps1"
RFC17="$PROJECT_ROOT/docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md"
UNKNOWN_LINE="### Triage verdict: UNKNOWN (node or triage.mjs unavailable)"

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then echo "INFO: keeping fixture at $TEST_DIR"; return 0; fi
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then rm -rf "$TEST_DIR"; fi
}
trap cleanup EXIT

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

check_deps() {
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
}

setup_fixture() { TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-triage-test.XXXXXX")"; }

# need_tool <TEST id> <tool>: 0 when present; otherwise fail when CI is set, and
# print a named SKIP-CASE line (still 0 after the caller returns) when it is not.
need_tool() {
  command -v "$2" >/dev/null 2>&1 && return 0
  [[ -z "${CI:-}" ]] || log_fail "$1: $2 is required on CI but is not on PATH"
  echo "SKIP-CASE: $1 needs $2, which is not installed here"
  return 1
}

# run_triage_node_tests <TEST id>: the module must exist, the node:test cases that
# start with the id must pass, and zero passing tests is a failure.
run_triage_node_tests() {
  local id="$1" out rc=0
  [[ -f "$TRIAGE_MJS" ]] || log_fail "$id: .aai/scripts/triage.mjs does not exist"
  [[ -f "$TRIAGE_NODE_TEST" ]] || log_fail "$id: tests/skills/lib/triage.test.mjs does not exist"
  out="$(node --test --test-name-pattern "$id" "$TRIAGE_NODE_TEST" 2>&1)" || rc=$?
  if [[ "$rc" != 0 ]]; then
    printf '%s\n' "$out" >&2
    log_fail "$id: node --test exited $rc"
  fi
  if [[ ! "$out" =~ pass\ [1-9] ]]; then
    printf '%s\n' "$out" >&2
    log_fail "$id: node --test reported zero passing tests for the pattern"
  fi
}

# mk_fixture <name> [audit-stdout]: sets FX to a committed scratch git repository
# holding copies of the launchers and the module under .aai/scripts/ and, when an
# audit text is given, a stub docs-audit.mjs that prints exactly that text.
FX=""
mk_fixture() {
  FX="$TEST_DIR/$1"
  rm -rf "$FX"
  mkdir -p "$FX/.aai/scripts"
  git -C "$FX" init -q -b main || log_fail "fixture $1: git init failed"
  git -C "$FX" config user.email "test@example.invalid" || log_fail "fixture $1: git config failed"
  git -C "$FX" config user.name "AAI Test" || log_fail "fixture $1: git config failed"
  local f
  for f in "$TRIAGE_SH" "$TRIAGE_PS1" "$TRIAGE_MJS"; do
    [[ ! -f "$f" ]] || cp "$f" "$FX/.aai/scripts/" || log_fail "fixture $1: cannot copy $f"
  done
  if [[ $# -ge 2 ]]; then
    node -e 'require("fs").writeFileSync(process.argv[1], "process.stdout.write(" + JSON.stringify(process.argv[2]) + ");\n")' \
      "$FX/.aai/scripts/docs-audit.mjs" "$2" || log_fail "fixture $1: cannot write the stub audit"
  fi
  git -C "$FX" add -A || log_fail "fixture $1: git add failed"
  git -C "$FX" commit -q -m init || log_fail "fixture $1: git commit failed"
}

AUDIT_OK=$'- Mode: quick\n- Scanned: 3\n- Tracked: 2\n### Verdict: OK\n'
AUDIT_BAD=$'- Mode: quick\n### Verdict: NEEDS-TRIAGE\n'

# ======================= TEST-2501..2506 (module, node:test) ===================
test_2501_module_report_order() {
  run_triage_node_tests TEST-2501
  log_pass "TEST-2501: buildReport returns the lines in D1 order, LF joined, exit 0"
}

test_2502_module_ascii_header() {
  run_triage_node_tests TEST-2502
  log_pass "TEST-2502: the header uses an ASCII hyphen and the report is ASCII"
}

test_2503_module_unknown_status() {
  run_triage_node_tests TEST-2503
  log_pass "TEST-2503: an empty project_status prints unknown"
}

test_2504_module_bom_inputs() {
  run_triage_node_tests TEST-2504
  log_pass "TEST-2504: a leading BOM in STATE.yaml and LOOP_TICKS.jsonl is ignored"
}

test_2505_module_case_sensitive() {
  run_triage_node_tests TEST-2505
  log_pass "TEST-2505: the audit marker is case-sensitive"
}

test_2506_module_crlf_tick() {
  run_triage_node_tests TEST-2506
  log_pass "TEST-2506: a CRLF tick line is printed without CR"
}

# ======================= TEST-2507..2508 (module CLI) ==========================
# cli_run <fixture> <label> [args...]: runs the module CLI by absolute path (cwd
# irrelevant); sets CLI_OUT, CLI_RC and fails when stderr is not empty.
CLI_OUT=""; CLI_RC=0
cli_run() {
  local fx="$1" label="$2"; shift 2
  CLI_RC=0
  CLI_OUT="$(node "$fx/.aai/scripts/triage.mjs" "$@" 2> "$TEST_DIR/cli.err")" || CLI_RC=$?
  [[ ! -s "$TEST_DIR/cli.err" ]] || log_fail "TEST-2507: stderr must stay empty ($label): $(cat "$TEST_DIR/cli.err")"
}

test_2507_module_cli_gate() {
  [[ -f "$TRIAGE_MJS" ]] || log_fail "TEST-2507: .aai/scripts/triage.mjs does not exist"
  mk_fixture t2507a "$AUDIT_BAD"
  local a="$FX"
  printf 'x\n' > "$a/one.txt"; printf 'y\n' > "$a/two.txt"
  cli_run "$a" "bad audit, --check" --check
  [[ "$CLI_OUT" == *"- Working tree: 2 uncommitted change(s)"* ]] || log_fail "TEST-2507: must count 2 porcelain lines, got: $CLI_OUT"
  [[ "$CLI_OUT" == *"### Triage verdict: NEEDS-ATTENTION (1 area(s))"* ]] || log_fail "TEST-2507: NEEDS-TRIAGE must raise the verdict, got: $CLI_OUT"
  [[ "$CLI_RC" == 1 ]] || log_fail "TEST-2507: --check must exit 1 on NEEDS-TRIAGE, got $CLI_RC"
  cli_run "$a" "bad audit, no flag"
  [[ "$CLI_RC" == 0 ]] || log_fail "TEST-2507: without --check the exit code must be 0, got $CLI_RC"
  mk_fixture t2507b
  printf 'x\n' > "$FX/one.txt"
  cli_run "$FX" "no audit, --check" --check
  [[ "$CLI_OUT" == *"- Docs audit: skipped (node or docs-audit.mjs unavailable)"* ]] || log_fail "TEST-2507: the skipped line is missing, got: $CLI_OUT"
  [[ "$CLI_RC" == 0 ]] || log_fail "TEST-2507: a skipped audit must exit 0 under --check, got $CLI_RC"
  mk_fixture t2507c $'foo\n'
  cli_run "$FX" "foo audit, --check" --check
  [[ "$CLI_OUT" == *"- Docs audit: (no output)"* ]] || log_fail "TEST-2507: the no-output line is missing, got: $CLI_OUT"
  [[ "$CLI_RC" == 0 ]] || log_fail "TEST-2507: an unmatched audit must exit 0 under --check, got $CLI_RC"
  log_pass "TEST-2507: the module CLI counts porcelain lines, gates on NEEDS-TRIAGE only, keeps stderr empty"
}

test_2508_module_read_only() {
  [[ -f "$TRIAGE_MJS" ]] || log_fail "TEST-2508: .aai/scripts/triage.mjs does not exist"
  local bad
  bad="$(node -e '
    const s = require("fs").readFileSync(process.argv[1], "utf8");
    const out = ["readFileSync(0", "process.stdin", "writeFileSync", "appendFileSync", "mkdirSync", "renameSync"].filter((t) => s.includes(t));
    process.stdout.write(out.join(", "));
  ' "$TRIAGE_MJS")"
  [[ -z "$bad" ]] || log_fail "TEST-2508: the module source holds forbidden tokens: $bad"
  mk_fixture t2508 "$AUDIT_OK"
  mkdir -p "$FX/docs/ai"
  printf 'project_status: active\n' > "$FX/docs/ai/STATE.yaml"
  printf '{"t":1}\n{"t":2}\n' > "$FX/docs/ai/LOOP_TICKS.jsonl"
  printf 'x\n' > "$FX/one.txt"
  local before="$TEST_DIR/t2508.before" after="$TEST_DIR/t2508.after"
  { git -C "$FX" status --porcelain; find "$FX" -path "$FX/.git" -prune -o -type f -print | sort; } > "$before"
  cli_run "$FX" "read-only run" --check
  [[ "$CLI_RC" == 0 && "$CLI_OUT" == *"project_status=active"* ]] || log_fail "TEST-2508: positive control failed, the CLI must report the fixture state (rc=$CLI_RC out=$CLI_OUT)"
  { git -C "$FX" status --porcelain; find "$FX" -path "$FX/.git" -prune -o -type f -print | sort; } > "$after"
  cmp -s "$before" "$after" || log_fail "TEST-2508: git status or the file list changed across a CLI run"
  log_pass "TEST-2508: the module source has no stdin or write calls and a run changes nothing"
}

# ======================= TEST-2509..2511 (launchers) ===========================
# launcher_check <file>: prints one reason per violated rule (empty when thin).
launcher_check() {
  node -e '
    const fs = require("fs");
    const buf = fs.readFileSync(process.argv[1]);
    const text = buf.toString("latin1");
    const bad = [];
    if (buf.some((b) => b > 0x7e)) bad.push("non-ASCII byte");
    const lines = text.split("\n"); if (lines[lines.length - 1] === "") lines.pop();
    if (lines.length > 14) bad.push("more than 14 lines (" + lines.length + ")");
    if (!text.includes("triage.mjs")) bad.push("no reference to triage.mjs");
    for (const t of ["project_status", "LOOP_TICKS", "STATE.yaml", "porcelain", "docs-audit", "NEEDS-", "CLEAN",
      "Select-String", "grep", "tail", "awk"]) {
      if (text.includes(t)) bad.push("logic token " + t);
    }
    const n = text.split("### Triage verdict: UNKNOWN (node or triage.mjs unavailable)").length - 1;
    if (n !== 1) bad.push("UNKNOWN literal appears " + n + " times");
    process.stdout.write(bad.join("; "));
  ' "$1"
}

test_2509_launchers_thin() {
  local f bad
  for f in "$TRIAGE_SH" "$TRIAGE_PS1"; do
    bad="$(launcher_check "$f")"
    [[ -z "$bad" ]] || log_fail "TEST-2509: ${f##*/} is not a thin launcher: $bad"
  done
  log_pass "TEST-2509: both launchers are ASCII, short, logic-free and call the module"
}

test_2510_sh_launcher_without_node() {
  local bin="$TEST_DIR/t2510-bin" t out rc flag
  rm -rf "$bin"; mkdir -p "$bin"
  for t in bash dirname; do ln -s "$(command -v "$t")" "$bin/$t"; done
  rc=0; PATH="$bin" "$bin/bash" -c 'command -v node >/dev/null 2>&1' || rc=$?
  [[ "$rc" != 0 ]] || log_fail "TEST-2510: positive control failed, node still resolves under the test PATH"
  mk_fixture t2510
  for flag in "" "--check"; do
    rc=0; out="$(PATH="$bin" "$bin/bash" "$FX/.aai/scripts/triage.sh" $flag 2> "$TEST_DIR/t2510.err")" || rc=$?
    [[ "$rc" == 0 ]] || log_fail "TEST-2510: without node the launcher must exit 0, got $rc ($flag)"
    [[ "$out" == "$UNKNOWN_LINE" ]] || log_fail "TEST-2510: without node the stdout must be exactly the UNKNOWN line, got: $out"
    [[ ! -s "$TEST_DIR/t2510.err" ]] || log_fail "TEST-2510: stderr must stay empty without node"
  done
  command -v node >/dev/null 2>&1 || log_fail "TEST-2510: positive control failed, node must resolve on the real PATH"
  mkdir -p "$TEST_DIR/t2510-nomod"
  cp "$TRIAGE_SH" "$TEST_DIR/t2510-nomod/triage.sh" || log_fail "TEST-2510: cannot copy the launcher"
  for flag in "" "--check"; do
    rc=0; out="$(bash "$TEST_DIR/t2510-nomod/triage.sh" $flag 2> "$TEST_DIR/t2510.err")" || rc=$?
    [[ "$rc" == 0 && "$out" == "$UNKNOWN_LINE" ]] || log_fail "TEST-2510: without the module the launcher must print exactly the UNKNOWN line and exit 0 (rc=$rc out=$out)"
    [[ ! -s "$TEST_DIR/t2510.err" ]] || log_fail "TEST-2510: stderr must stay empty without the module"
  done
  log_pass "TEST-2510: triage.sh degrades to the UNKNOWN line without node or module"
}

test_2511_ps1_launcher_fallback_and_exit() {
  need_tool TEST-2511 pwsh || return 0
  local bin="$TEST_DIR/t2511-bin" out rc flag
  rm -rf "$bin"; mkdir -p "$bin"
  ln -s "$(command -v pwsh)" "$bin/pwsh"
  rc=0; PATH="$bin" "$bin/pwsh" -NoProfile -Command 'if (Get-Command node -ErrorAction SilentlyContinue) { exit 1 } else { exit 0 }' || rc=$?
  [[ "$rc" == 0 ]] || log_fail "TEST-2511: positive control failed, node still resolves under the test PATH"
  mk_fixture t2511 "$AUDIT_BAD"
  for flag in "" "-Check"; do
    rc=0; out="$(PATH="$bin" "$bin/pwsh" -NoProfile -File "$FX/.aai/scripts/triage.ps1" $flag 2> "$TEST_DIR/t2511.err")" || rc=$?
    [[ "$rc" == 0 && "$out" == "$UNKNOWN_LINE" ]] || log_fail "TEST-2511: without node the launcher must print exactly the UNKNOWN line and exit 0 (rc=$rc out=$out)"
    [[ ! -s "$TEST_DIR/t2511.err" ]] || log_fail "TEST-2511: stderr must stay empty without node"
  done
  command -v node >/dev/null 2>&1 || log_fail "TEST-2511: positive control failed, node must resolve on the real PATH"
  mkdir -p "$TEST_DIR/t2511-nomod"
  cp "$TRIAGE_PS1" "$TEST_DIR/t2511-nomod/triage.ps1" || log_fail "TEST-2511: cannot copy the launcher"
  for flag in "" "-Check"; do
    rc=0; out="$(pwsh -NoProfile -File "$TEST_DIR/t2511-nomod/triage.ps1" $flag 2> "$TEST_DIR/t2511.err")" || rc=$?
    [[ "$rc" == 0 && "$out" == "$UNKNOWN_LINE" ]] || log_fail "TEST-2511: without the module the launcher must print exactly the UNKNOWN line and exit 0 (rc=$rc out=$out)"
    [[ ! -s "$TEST_DIR/t2511.err" ]] || log_fail "TEST-2511: stderr must stay empty without the module"
  done
  rc=0; pwsh -NoProfile -File "$FX/.aai/scripts/triage.ps1" -Check > "$TEST_DIR/t2511.out" 2>&1 || rc=$?
  [[ "$rc" == 1 ]] || log_fail "TEST-2511: -Check against a NEEDS-TRIAGE audit must exit 1, got $rc"
  rc=0; pwsh -NoProfile -File "$FX/.aai/scripts/triage.ps1" > "$TEST_DIR/t2511.out" 2>&1 || rc=$?
  [[ "$rc" == 0 ]] || log_fail "TEST-2511: without -Check the exit code must be 0, got $rc"
  log_pass "TEST-2511: triage.ps1 degrades to the UNKNOWN line and returns the module exit code"
}

# ======================= TEST-2512..2513 (parity, Pester) ======================
# par_fixture <name> <audit-or-"-"> <state-or-"-"> <ticks-or-"-"> <changes 0|1>
par_fixture() {
  if [[ "$2" == "-" ]]; then mk_fixture "$1"; else mk_fixture "$1" "$2"; fi
  mkdir -p "$FX/docs/ai"
  if [[ "$3" != "-" ]]; then printf '%b' "$3" > "$FX/docs/ai/STATE.yaml"; fi
  if [[ "$4" != "-" ]]; then printf '%b' "$4" > "$FX/docs/ai/LOOP_TICKS.jsonl"; fi
  if [[ "$5" == 1 ]]; then printf 'x\n' > "$FX/one.txt"; printf 'y\n' > "$FX/two.txt"; fi
}

# run_side <fixture> <out-file> <cmd...>: stdout to the file with the timestamp
# removed; sets SIDE_RC.
SIDE_RC=0
run_side() {
  local fx="$1" out="$2"; shift 2
  SIDE_RC=0
  "$@" > "$out.raw" 2> "$out.err" || SIDE_RC=$?
  sed 's/^## AAI L1 Triage - .*/## AAI L1 Triage - T/' "$out.raw" > "$out"
  [[ ! -s "$out.err" ]] || log_fail "TEST-2512: stderr must stay empty ($*): $(cat "$out.err")"
}

test_2512_launcher_parity() {
  need_tool TEST-2512 pwsh || return 0
  [[ -f "$TRIAGE_MJS" ]] || log_fail "TEST-2512: .aai/scripts/triage.mjs does not exist"
  local d="$TEST_DIR/t2512" name rc_sh rc_ps rc_ps2 bom=$'\xef\xbb\xbf' i=0
  rm -rf "$d"; mkdir -p "$d"
  local names="clean state-ticks-changes empty-status bom-state lower-audit bad-audit crlf-ticks"
  for name in $names; do
    case "$name" in
      clean) par_fixture "t2512-$name" - - - 0 ;;
      state-ticks-changes) par_fixture "t2512-$name" "$AUDIT_OK" 'project_status: active\n' '{"t":1}\n{"t":2}\n' 1 ;;
      empty-status) par_fixture "t2512-$name" "$AUDIT_OK" 'project_status:\n' - 0 ;;
      bom-state) par_fixture "t2512-$name" "$AUDIT_OK" "${bom}project_status: active\n" "${bom}"'{"t":3}\n' 0 ;;
      lower-audit) par_fixture "t2512-$name" $'- mode: quick\n### verdict: needs-triage\n' - - 0 ;;
      bad-audit) par_fixture "t2512-$name" "$AUDIT_BAD" - - 1 ;;
      crlf-ticks) par_fixture "t2512-$name" "$AUDIT_OK" 'project_status: active\n' '{"t":1}\r\n{"t":2}\r\n' 0 ;;
    esac
    i=$((i + 1))
    run_side "$FX" "$d/$name.sh" bash "$FX/.aai/scripts/triage.sh" --check; rc_sh="$SIDE_RC"
    run_side "$FX" "$d/$name.ps" pwsh -NoProfile -File "$FX/.aai/scripts/triage.ps1" -Check; rc_ps="$SIDE_RC"
    run_side "$FX" "$d/$name.ps2" pwsh -NoProfile -File "$FX/.aai/scripts/triage.ps1" --check; rc_ps2="$SIDE_RC"
    [[ "$rc_sh" == "$rc_ps" && "$rc_sh" == "$rc_ps2" ]] || log_fail "TEST-2512: exit codes differ for $name (sh=$rc_sh ps=$rc_ps ps-long=$rc_ps2)"
    cmp -s "$d/$name.sh" "$d/$name.ps" || log_fail "TEST-2512: stdout differs between triage.sh and triage.ps1 -Check for $name"
    cmp -s "$d/$name.sh" "$d/$name.ps2" || log_fail "TEST-2512: stdout differs between triage.sh and triage.ps1 --check for $name"
    if [[ "$name" == bad-audit ]]; then
      [[ "$rc_sh" == 1 && "$rc_ps" == 1 ]] || log_fail "TEST-2512: positive control failed, bad-audit must exit 1 on both sides (sh=$rc_sh ps=$rc_ps)"
    fi
  done
  [[ "$i" == 7 ]] || log_fail "TEST-2512: expected seven fixtures, ran $i"
  log_pass "TEST-2512: triage.sh and triage.ps1 give identical stdout and exit codes for seven fixtures"
}

test_2513_pester_triage() {
  [[ -f "$TRIAGE_PESTER" ]] || log_fail "TEST-2513: tests/skills/triage.Tests.ps1 does not exist"
  need_tool TEST-2513 pwsh || return 0
  local has out rc=0
  has="$(pwsh -NoProfile -Command 'if (Get-Module Pester -ListAvailable | Where-Object { $_.Version.Major -ge 5 }) { "yes" } else { "no" }' 2>/dev/null || echo no)"
  if [[ "$has" != yes ]]; then
    echo "SKIP-CASE: TEST-2513 needs Pester 5 (the ps1-quality gate job is the authoritative runner)"
    return 0
  fi
  out="$(PESTER_FILE="$TRIAGE_PESTER" pwsh -NoProfile -Command '
    $cfg = New-PesterConfiguration
    $cfg.Run.Path = $env:PESTER_FILE
    $cfg.Run.PassThru = $true
    $cfg.Output.Verbosity = "Normal"
    $r = Invoke-Pester -Configuration $cfg
    Write-Host "TRIAGE-PESTER: Total=$($r.TotalCount) Passed=$($r.PassedCount) Failed=$($r.FailedCount) Skipped=$($r.SkippedCount)"
    if ($r.FailedCount -gt 0 -or $r.SkippedCount -gt 0 -or $r.TotalCount -lt 8) { exit 1 }
    exit 0
  ' 2>&1)" || rc=$?
  if [[ "$rc" != 0 ]]; then
    printf '%s\n' "$out" >&2
    log_fail "TEST-2513: triage.Tests.ps1 failed, skipped a case or ran fewer than 8 cases (rc=$rc)"
  fi
  log_pass "TEST-2513: triage.Tests.ps1 passes with no skip ($(printf '%s\n' "$out" | sed -n 's/^TRIAGE-PESTER: //p'))"
}

# ======================= TEST-2514 (downstream core install) ===================
test_2514_downstream_core_sync_runs_triage() {
  local t="$TEST_DIR/t2514/target dir" rc out
  rm -rf "$TEST_DIR/t2514"; mkdir -p "$t"
  git -C "$t" init -q -b main || log_fail "TEST-2514: git init of the target failed"
  rc=0; bash "$PROJECT_ROOT/.aai/scripts/aai-sync.sh" "$t" --profile core > "$TEST_DIR/t2514.sync.log" 2>&1 || rc=$?
  [[ "$rc" == 0 ]] || log_fail "TEST-2514: aai-sync.sh --profile core exited $rc: $(cat "$TEST_DIR/t2514.sync.log")"
  [[ -f "$t/.aai/scripts/triage.mjs" ]] || log_fail "TEST-2514: the core target lacks .aai/scripts/triage.mjs"
  rc=0; out="$(bash "$t/.aai/scripts/triage.sh" 2> "$TEST_DIR/t2514.err")" || rc=$?
  [[ "$rc" == 0 ]] || log_fail "TEST-2514: triage.sh in the core target exited $rc: $out"
  [[ "$out" == *"## AAI L1 Triage - "* ]] || log_fail "TEST-2514: the header is missing: $out"
  [[ "$out" == *$'\n- Mode: '* ]] || log_fail "TEST-2514: no '- Mode:' line from the real docs-audit: $out"
  [[ "$out" == *"### Triage verdict: "* ]] || log_fail "TEST-2514: no Triage verdict line: $out"
  [[ "$out" != *UNKNOWN* && "$out" != *"Docs audit: skipped"* ]] || log_fail "TEST-2514: the UNKNOWN or skipped line was printed: $out"
  log_pass "TEST-2514: a core install into a spaced path runs triage.sh with the real docs-audit"
}

# ======================= TEST-2515..2520 (wiring and records) ==================
test_2516_suite_map_selects_triage() {
  local p out
  for p in .aai/scripts/triage.sh .aai/scripts/triage.ps1 .aai/scripts/triage.mjs tests/skills/lib/triage.test.mjs tests/skills/triage.Tests.ps1; do
    out="$(node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from - <<<"$p")"
    [[ "$out" != *FULL_RUN* ]] || log_fail "TEST-2516: $p gives a FULL_RUN line: $out"
    [[ "$out" == *"SELECTED aai-triage"* ]] || log_fail "TEST-2516: $p does not select aai-triage: $out"
  done
  log_pass "TEST-2516: all five suite paths select aai-triage"
}

test_2517_ps1_quality_filter_has_module() {
  local wf="$PROJECT_ROOT/.github/workflows/ps1-quality.yml" out
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
    const want = "\x27.aai/scripts/triage.mjs\x27";
    const bad = [];
    for (const k of ["push", "pull_request"]) {
      if (!lists[k] || lists[k].length === 0) bad.push(k + ": no path list");
      else if (!lists[k].includes(want)) bad.push(k + ": lacks the module");
    }
    if (lists.push && lists.pull_request && JSON.stringify(lists.push) !== JSON.stringify(lists.pull_request)) bad.push("lists differ");
    process.stdout.write(bad.join("; "));
  ' "$wf")"
  [[ -z "$out" ]] || log_fail "TEST-2517: ps1-quality.yml path filter: $out"
  log_pass "TEST-2517: both path lists contain the module and are identical"
}

# rfc_phase3_row: the Rollout Status row whose first cell is 3.
rfc_phase3_row() {
  node -e '
    for (const l of require("fs").readFileSync(process.argv[1], "utf8").split("\n")) {
      if (/^\| 3 \|/.test(l)) { process.stdout.write(l); break; }
    }
  ' "$RFC17"
}

test_2518_rfc_phase3_row() {
  local row; row="$(rfc_phase3_row)"
  [[ -n "$row" ]] || log_fail "TEST-2518: RFC-0017 has no Rollout Status row 3"
  [[ "$row" == *"| Migrate common sync/hook behavior to Node in small slices, with native platform parity and retired counterparts |"* ]] \
    || log_fail "TEST-2518: the phase 3 description cell changed"
  [[ "$row" == *"| in progress |"* ]] || log_fail "TEST-2518: the phase 3 status cell must be in progress"
  [[ "$row" == *'[First Node-first slice](../issues/CHANGE-0222-node-first-sync-hook-slice.md) moved the live-status spool hook (live-spool pair 133 to 116 lines): one Node module and two launchers, tested with `node:test` plus Pester on the native Windows job'* ]] \
    || log_fail "TEST-2518: the first-slice link and text changed"
  [[ "$row" =~ \]\([^\)]*node-first-second-slice\.md\)[^\|]*triage ]] \
    || log_fail "TEST-2518: the phase 3 row lacks a link to node-first-second-slice.md followed by the word triage"
  log_pass "TEST-2518: RFC-0017 phase 3 row keeps the first slice and links the second"
}

test_2519_line_budget_recorded() {
  local row n sum
  row="$(rfc_phase3_row)"
  if [[ "$row" =~ triage\ pair\ 140\ to\ ([0-9]+)\ lines ]]; then n="${BASH_REMATCH[1]}"; else
    log_fail "TEST-2519: the phase 3 row does not record 'triage pair 140 to N lines'"
  fi
  sum="$(cat "$TRIAGE_SH" "$TRIAGE_PS1" "$TRIAGE_MJS" | wc -l | tr -d '[:space:]')"
  [[ "$n" == "$sum" ]] || log_fail "TEST-2519: the row records $n lines but the three files total $sum"
  [[ "$n" -lt 140 ]] || log_fail "TEST-2519: N=$n must be below 140"
  log_pass "TEST-2519: the RFC row records the live line total ($n < 140)"
}

test_2520_495_amendments_signed() {
  local sa="$TEST_DIR/t2520.sa.json" fu="$TEST_DIR/t2520.fu.json" out
  node "$PROJECT_ROOT/.aai/scripts/spec-amend.mjs" list --json > "$sa" || log_fail "TEST-2520: spec-amend list failed"
  node "$PROJECT_ROOT/.aai/scripts/follow-ups.mjs" list --status all --json > "$fu" || log_fail "TEST-2520: follow-ups list failed"
  out="$(node -e '
    const fs = require("fs");
    const sa = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const fu = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
    const mine = sa.items.filter((i) => i.ref_id === "node-first-sync-hook-slice");
    const bad = [];
    if (mine.length < 7) bad.push("only " + mine.length + " amendment record(s) for node-first-sync-hook-slice, want at least 7");
    for (const i of mine) if (i.bucket !== "signed") bad.push(i.record_key + " is " + i.bucket);
    const f = fu.items.find((i) => i.id === "fu-amend-spec-node-first-sync-hook-slice");
    if (!f) bad.push("fu-amend-spec-node-first-sync-hook-slice is not listed");
    else if (f.status !== "done") bad.push("fu-amend-spec-node-first-sync-hook-slice is " + f.status);
    process.stdout.write(bad.join("; "));
  ' "$sa" "$fu")"
  [[ -z "$out" ]] || log_fail "TEST-2520: $out"
  log_pass "TEST-2520: every #495 amendment record is signed and its follow-up is done"
}

main() {
  echo "Testing $TEST_NAME (SPEC spec-node-first-second-slice TEST-2501..2520)"
  check_deps
  setup_fixture
  test_2501_module_report_order
  test_2502_module_ascii_header
  test_2503_module_unknown_status
  test_2504_module_bom_inputs
  test_2505_module_case_sensitive
  test_2506_module_crlf_tick
  test_2507_module_cli_gate
  test_2508_module_read_only
  test_2509_launchers_thin
  test_2510_sh_launcher_without_node
  test_2511_ps1_launcher_fallback_and_exit
  test_2512_launcher_parity
  test_2513_pester_triage
  test_2514_downstream_core_sync_runs_triage
  test_2516_suite_map_selects_triage
  test_2517_ps1_quality_filter_has_module
  test_2518_rfc_phase3_row
  test_2519_line_budget_recorded
  test_2520_495_amendments_signed
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
