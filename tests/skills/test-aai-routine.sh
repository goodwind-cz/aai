#!/usr/bin/env bash
#
# Test: universal standing routines — on-demand, agent-neutral routine
# template + emitter (CHANGE-0128-universal-routines /
# SPEC-DRAFT-spec-universal-routines.md).
#
# Verifies .aai/routines/SCRYER.routine.md (contract elements + closed
# placeholder set), .aai/scripts/routine-emit.mjs (render, per-harness
# emission, merge-rights guard, TEST AT CREATION footer), the thin wrapper
# .aai/SKILL_ROUTINE.prompt.md (on-demand pin + automatic-surface isolation),
# the four skill-tree wrappers, the live docs/ai/decisions.jsonl
# routine_authorization record (append-only), and the SKILLS.md row.
#
# The script/template/prompt under test are overridable so the RED phase can
# prove these tests genuinely discriminate (before any of these files
# existed, every invocation failed):
#   AAI_ROUTINE_SCRIPT        script under test (default .aai/scripts/routine-emit.mjs)
#   AAI_ROUTINE_TEMPLATE      template under test (default .aai/routines/SCRYER.routine.md)
#   AAI_ROUTINE_PROMPT        wrapper prompt under test (default .aai/SKILL_ROUTINE.prompt.md)
#   AAI_ROUTINE_WRAPPER_ROOT  root under which <tree>/skills/aai-routine/SKILL.md
#                             is looked up (default project root)
#
# Usage:
#   bash tests/skills/test-aai-routine.sh            # run all (TEST-001..022)
#   bash tests/skills/test-aai-routine.sh 001 011     # run only selected tests
#
# Exit codes:
#   0  - All selected tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -uo pipefail

TEST_NAME="aai-routine"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SCRIPT="${AAI_ROUTINE_SCRIPT:-$PROJECT_ROOT/.aai/scripts/routine-emit.mjs}"
TEMPLATE="${AAI_ROUTINE_TEMPLATE:-$PROJECT_ROOT/.aai/routines/SCRYER.routine.md}"
PROMPT_DOC="${AAI_ROUTINE_PROMPT:-$PROJECT_ROOT/.aai/SKILL_ROUTINE.prompt.md}"
WRAPPER_ROOT="${AAI_ROUTINE_WRAPPER_ROOT:-$PROJECT_ROOT}"
FIXDIR="$PROJECT_ROOT/tests/fixtures/routines"
GOLDEN="$FIXDIR/scryer-claude-merge.golden.txt"
REAL_DECISIONS="$PROJECT_ROOT/docs/ai/decisions.jsonl"
# merge-base of feat/universal-routines with main, captured before this
# scope touched docs/ai/decisions.jsonl at all (append-only proof anchor).
BASELINE_SHA="8e4f9ac945101b7fa887a14f117f5f26328e1c85"

TMP_ROOT=""
FAILED=0

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; FAILED=1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

cleanup() {
  if [[ -n "${TMP_ROOT:-}" && -d "$TMP_ROOT" ]]; then
    rm -rf "$TMP_ROOT"
  fi
}
trap cleanup EXIT

check_deps() {
  log_info "Checking dependencies..."
  command -v bash >/dev/null 2>&1 || log_skip "bash not found"
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v mktemp >/dev/null 2>&1 || log_skip "mktemp not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aai-routine-test.XXXXXX")"
  log_pass "Dependencies checked"
}

# Run the emitter with args; capture stdout to OUT, stderr to ERR, exit to RC.
OUT=""; ERR=""; RC=0
run_emit() {  # run_emit [args...]
  local errf
  errf="$(mktemp "$TMP_ROOT/err.XXXXXX")"
  OUT="$(node "$SCRIPT" "$@" 2>"$errf")"; RC=$?
  ERR="$(cat "$errf")"
  rm -f "$errf"
}

# Convenience: the four "full argument set" flags shared by most tests.
BASE_ARGS=(--routine SCRYER --repo owner/repo --schedule "0 7 * * *" --model claude-sonnet-5 --tz Europe/Prague)

# json_field <json-string-on-stdin> <dotted.path>
json_field() {
  local path="$1"
  node -e '
    let d = "";
    process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => {
      let v = JSON.parse(d);
      for (const seg of process.argv[1].split(".")) v = v == null ? undefined : v[seg];
      console.log(v === undefined ? "" : (typeof v === "object" ? JSON.stringify(v) : v));
    });
  ' "$path"
}

# write_prompt_field <json-line> <dest-file> — decode the .prompt field's
# real (unescaped) text into dest, byte-exact (no bash var round-trip).
write_prompt_field() {
  local json_line="$1" dest="$2"
  printf '%s' "$json_line" | node -e '
    let d = "";
    process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => {
      process.stdout.write(JSON.parse(d).prompt);
    });
  ' > "$dest"
}

first_line() { printf '%s\n' "$1" | sed -n '1p'; }

# --- TEST-001 — template carries all six contract elements as greppable text
test_001_contract_elements() {
  log_info "TEST-001: template pins prereq probes, resilience rule, three merge gates, Czech digest, UNTRUSTED-DATA rule, merge-only-write rule..."
  [[ -f "$TEMPLATE" ]] || { log_fail "TEST-001: $TEMPLATE missing"; return; }
  local ok=1
  grep -qF "gh --version" "$TEMPLATE" || { log_info "TEST-001: no gh prereq probe"; ok=0; }
  grep -qF "git --version" "$TEMPLATE" || { log_info "TEST-001: no git prereq probe"; ok=0; }
  grep -qF "node --version" "$TEMPLATE" || { log_info "TEST-001: no node prereq probe"; ok=0; }
  grep -qi "SUCCESSFUL run" "$TEMPLATE" || { log_info "TEST-001: no 'SUCCESSFUL run' resilience rule"; ok=0; }
  grep -qF "CI is green" "$TEMPLATE" || { log_info "TEST-001: no CI-green merge gate"; ok=0; }
  grep -qi "bot comments" "$TEMPLATE" || { log_info "TEST-001: no bot-comments merge gate"; ok=0; }
  grep -qF "[L3]" "$TEMPLATE" || { log_info "TEST-001: no [L3] merge gate"; ok=0; }
  grep -qF "Shrnutí" "$TEMPLATE" || { log_info "TEST-001: no Czech digest shape (Shrnutí)"; ok=0; }
  grep -qi "UNTRUSTED DATA" "$TEMPLATE" || { log_info "TEST-001: no UNTRUSTED-DATA rule"; ok=0; }
  grep -qF "Merge is the ONLY write action" "$TEMPLATE" || { log_info "TEST-001: no merge-only-write rule"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-001 all six contract elements present" || log_fail "TEST-001 contract elements"
}

# --- TEST-002 — placeholder set is exactly the four declared tokens --------
test_002_placeholder_closure() {
  log_info "TEST-002: template declares exactly {{REPO}},{{SCHEDULE}},{{MERGE_ALLOWED}},{{MODEL}}, no undeclared token..."
  [[ -f "$TEMPLATE" ]] || { log_fail "TEST-002: $TEMPLATE missing"; return; }
  local actual expected
  actual="$(grep -oE '\{\{[A-Z_]+\}\}' "$TEMPLATE" | sort -u)"
  expected=$'{{MERGE_ALLOWED}}\n{{MODEL}}\n{{REPO}}\n{{SCHEDULE}}'
  if [[ "$actual" == "$expected" ]]; then
    log_pass "TEST-002 placeholder set closed to exactly the 4 declared tokens"
  else
    log_info "TEST-002: actual set:"
    log_info "$actual"
    log_fail "TEST-002 placeholder closure (want: REPO,SCHEDULE,MERGE_ALLOWED,MODEL)"
  fi
}

# --- TEST-003 — render equals golden byte-for-byte --------------------------
test_003_golden_diff() {
  log_info "TEST-003: claude+merge render (full argument set, authorized fixture) equals golden byte-for-byte..."
  run_emit --routine SCRYER --harness claude --os macos --repo owner/repo \
    --schedule "0 7 * * *" --model claude-sonnet-5 --tz Europe/Prague \
    --merge --ref test-ref --decisions "$FIXDIR/decisions-authorized.jsonl"
  if [[ "$RC" -ne 0 ]]; then
    log_fail "TEST-003: exit $RC (want 0); stderr=$ERR"; return
  fi
  local rendered="$TMP_ROOT/t003-render.txt"
  write_prompt_field "$(first_line "$OUT")" "$rendered"
  if [[ ! -f "$GOLDEN" ]]; then
    log_fail "TEST-003: golden fixture $GOLDEN missing"; return
  fi
  if diff -q "$rendered" "$GOLDEN" >/dev/null 2>&1; then
    log_pass "TEST-003 render equals golden byte-for-byte"
  else
    log_info "TEST-003: diff:"
    diff "$rendered" "$GOLDEN" | head -20 | while IFS= read -r line; do log_info "  $line"; done
    log_fail "TEST-003 render != golden"
  fi
}

# --- TEST-004 — two identical renders are byte-identical (idempotence) -----
test_004_idempotent() {
  log_info "TEST-004: rendering twice with identical arguments is byte-identical..."
  local args=(--routine SCRYER --harness claude --os macos --repo owner/repo \
    --schedule "0 7 * * *" --model claude-sonnet-5 --tz Europe/Prague \
    --merge --ref test-ref --decisions "$FIXDIR/decisions-authorized.jsonl")
  run_emit "${args[@]}"
  local out1="$OUT"
  run_emit "${args[@]}"
  local out2="$OUT"
  local f1="$TMP_ROOT/t004-a.txt" f2="$TMP_ROOT/t004-b.txt"
  write_prompt_field "$(first_line "$out1")" "$f1"
  write_prompt_field "$(first_line "$out2")" "$f2"
  if diff -q "$f1" "$f2" >/dev/null 2>&1; then
    log_pass "TEST-004 idempotent render"
  else
    log_fail "TEST-004 two renders differ"
  fi
}

# --- TEST-005 — rendered output contains zero unresolved placeholders ------
test_005_zero_unresolved_placeholders() {
  log_info "TEST-005: rendered prompt contains zero {{ sequences..."
  run_emit --routine SCRYER --harness claude --os macos --repo owner/repo \
    --schedule "0 7 * * *" --model claude-sonnet-5 --tz Europe/Prague \
    --merge --ref test-ref --decisions "$FIXDIR/decisions-authorized.jsonl"
  if [[ "$RC" -ne 0 ]]; then log_fail "TEST-005: exit $RC (want 0)"; return; fi
  local rendered="$TMP_ROOT/t005-render.txt"
  write_prompt_field "$(first_line "$OUT")" "$rendered"
  local n
  n=$(grep -c '{{' "$rendered" || true)
  if [[ "$n" -eq 0 ]]; then
    log_pass "TEST-005 zero unresolved placeholders"
  else
    log_fail "TEST-005: $n unresolved '{{' sequences remain"
  fi
}

# --- TEST-006 — missing required flag exits 2, empty stdout ----------------
test_006_missing_required_flag() {
  log_info "TEST-006: missing --repo exits 2 with empty stdout..."
  run_emit --routine SCRYER --harness claude --os macos \
    --schedule "0 7 * * *" --model claude-sonnet-5 --tz Europe/Prague
  if [[ "$RC" -eq 2 && -z "$OUT" ]]; then
    log_pass "TEST-006 missing --repo -> exit 2, empty stdout"
  else
    log_fail "TEST-006: rc=$RC out='$OUT' (want rc=2, empty stdout)"
  fi
}

# --- TEST-007 — claude payload parses as JSON; fields echo arguments -------
test_007_claude_json_fields() {
  log_info "TEST-007: claude payload JSON.parse's; prompt equals render; cron/model/repo echo arguments..."
  run_emit --routine SCRYER --harness claude --os macos --repo test/repo \
    --schedule "*/5 * * * *" --model my-model --tz UTC
  if [[ "$RC" -ne 0 ]]; then log_fail "TEST-007: exit $RC (want 0); stderr=$ERR"; return; fi
  local line ok=1
  line="$(first_line "$OUT")"
  local cron model repo prompt
  cron=$(printf '%s' "$line" | json_field cron) || ok=0
  model=$(printf '%s' "$line" | json_field model) || ok=0
  repo=$(printf '%s' "$line" | json_field repo) || ok=0
  prompt=$(printf '%s' "$line" | json_field prompt) || ok=0
  [[ "$cron" == "*/5 * * * *" ]] || { log_info "TEST-007: cron='$cron'"; ok=0; }
  [[ "$model" == "my-model" ]] || { log_info "TEST-007: model='$model'"; ok=0; }
  [[ "$repo" == "test/repo" ]] || { log_info "TEST-007: repo='$repo'"; ok=0; }
  [[ -n "$prompt" ]] || { log_info "TEST-007: prompt field empty"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-007 claude JSON parses, fields echo arguments" || log_fail "TEST-007 claude JSON fields"
}

# --- TEST-008 — codex/gemini/generic on macos/linux: crontab + headless CLI
test_008_local_scheduler_macos_linux() {
  log_info "TEST-008: codex/gemini/generic on macos+linux emit crontab line + headless CLI invocation..."
  local ok=1 h o out
  for h in codex gemini generic; do
    for o in macos linux; do
      run_emit --routine SCRYER --harness "$h" --os "$o" --repo owner/repo \
        --schedule "0 7 * * *" --model claude-sonnet-5 --tz Europe/Prague
      if [[ "$RC" -ne 0 ]]; then log_info "TEST-008: $h/$o exit $RC (want 0)"; ok=0; continue; fi
      out="$OUT"
      case "$out" in
        *"Crontab line:"*"0 7 * * *"*) ;;
        *) log_info "TEST-008: $h/$o missing crontab line with schedule"; ok=0 ;;
      esac
      case "$h" in
        codex) grep -qF "codex --prompt-file" <<<"$out" || { log_info "TEST-008: $h/$o missing codex headless invocation"; ok=0; } ;;
        gemini) grep -qF "gemini --prompt-file" <<<"$out" || { log_info "TEST-008: $h/$o missing gemini headless invocation"; ok=0; } ;;
        generic) grep -qF "<agent-cli> --prompt-file" <<<"$out" || { log_info "TEST-008: $h/$o missing generic headless invocation"; ok=0; } ;;
      esac
    done
  done
  [[ $ok -eq 1 ]] && log_pass "TEST-008 codex/gemini/generic macos+linux crontab + headless CLI" || log_fail "TEST-008 local scheduler macos/linux"
}

# --- TEST-009 — windows emits Register-ScheduledTask + both twin filenames,
#     and the emitted block is VALID, EXECUTABLE PowerShell (Spec-AC-03) -----
# Textual greps alone don't discriminate a broken emission from a working one
# (both contain the literal strings "Register-ScheduledTask" etc). This test
# additionally pipes the extracted windows block through pwsh's own parser
# (Parser::ParseFile) to assert it is AST-clean and forms exactly the three
# intended statements, then round-trips it through stubbed cmdlets to assert
# New-ScheduledTaskAction actually receives a non-empty -Argument (not a
# standalone-statement fragment) and Register-ScheduledTask receives
# -Description. Guarded with the same pwsh-present skip convention
# test-ps1-quality.sh uses (informational skip, never a hard suite failure).
test_009_windows_register_scheduled_task() {
  log_info "TEST-009: windows emits Register-ScheduledTask + both .sh/.ps1 twin filenames, as valid executable PowerShell..."
  run_emit --routine SCRYER --harness codex --os windows --repo owner/repo \
    --schedule "0 7 * * *" --model claude-sonnet-5 --tz Europe/Prague
  if [[ "$RC" -ne 0 ]]; then log_fail "TEST-009: exit $RC (want 0)"; return; fi
  local ok=1
  grep -qF "Register-ScheduledTask" <<<"$OUT" || { log_info "TEST-009: no Register-ScheduledTask"; ok=0; }
  grep -qF "aai-scryer-codex.sh" <<<"$OUT" || { log_info "TEST-009: no .sh twin filename"; ok=0; }
  grep -qF "aai-scryer-codex.ps1" <<<"$OUT" || { log_info "TEST-009: no .ps1 twin filename"; ok=0; }

  local psfile="$TMP_ROOT/t009-block.ps1"
  awk '
    /^PowerShell scheduled task \(Register-ScheduledTask\):$/ { flag=1; next }
    flag && /^$/ { exit }
    flag { print }
  ' <<<"$OUT" > "$psfile"
  [[ -s "$psfile" ]] || { log_info "TEST-009: could not extract windows PowerShell block from emission"; ok=0; }

  if command -v pwsh >/dev/null 2>&1; then
    local checker="$TMP_ROOT/t009-check.ps1"
    cat > "$checker" <<'PS1EOF'
param([Parameter(Mandatory=$true)][string]$Path)
$errs = $null
$tokens = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errs)
$parseErrCount = 0
if ($errs) { $parseErrCount = $errs.Count }
Write-Output ("PARSEERR=" + $parseErrCount)
if ($errs) { foreach ($e in $errs) { Write-Output ("  " + $e.Message) } }
$stmtCount = $ast.EndBlock.Statements.Count
Write-Output ("STMTCOUNT=" + $stmtCount)
if ($parseErrCount -eq 0) {
  function New-ScheduledTaskAction {
    param([string]$Execute, [string]$Argument)
    $global:__CapturedArgument = $Argument
    [pscustomobject]@{ Execute = $Execute; Argument = $Argument }
  }
  function New-ScheduledTaskTrigger {
    param([switch]$Once, $At)
    [pscustomobject]@{ Once = $Once; At = $At }
  }
  function Register-ScheduledTask {
    param([string]$TaskName, $Action, $Trigger, [string]$Description)
    $global:__CapturedDescription = $Description
    $global:__CapturedTaskName = $TaskName
    [pscustomobject]@{ TaskName = $TaskName }
  }
  $global:__CapturedArgument = $null
  $global:__CapturedDescription = $null
  . $Path
  Write-Output ("ARGUMENT=" + $global:__CapturedArgument)
  Write-Output ("DESCRIPTION=" + $global:__CapturedDescription)
}
PS1EOF
    local result parseerr stmtcount argument description
    result="$(pwsh -NoProfile -File "$checker" -Path "$psfile" 2>&1)"
    parseerr="$(grep -m1 '^PARSEERR=' <<<"$result" | cut -d= -f2)"
    stmtcount="$(grep -m1 '^STMTCOUNT=' <<<"$result" | cut -d= -f2)"
    argument="$(grep -m1 '^ARGUMENT=' <<<"$result" | cut -d= -f2-)"
    description="$(grep -m1 '^DESCRIPTION=' <<<"$result" | cut -d= -f2-)"
    if [[ "$parseerr" != "0" ]]; then
      log_info "TEST-009: pwsh AST parse errors (want 0, got '$parseerr'):"
      grep -v '^PARSEERR=\|^STMTCOUNT=\|^ARGUMENT=\|^DESCRIPTION=' <<<"$result" | while IFS= read -r l; do log_info "  $l"; done
      ok=0
    fi
    if [[ "$stmtcount" != "3" ]]; then
      log_info "TEST-009: expected exactly 3 top-level PowerShell statements, got '$stmtcount' (a backslash line-continuation splits the block into extra bogus statements)"
      ok=0
    fi
    if [[ -z "$argument" || "$argument" != *"codex --prompt-file"* ]]; then
      log_info "TEST-009: New-ScheduledTaskAction did not receive the expected non-empty -Argument (got '$argument')"
      ok=0
    fi
    if [[ -z "$description" || "$description" != *"AAI routine SCRYER"* ]]; then
      log_info "TEST-009: Register-ScheduledTask did not receive the expected non-empty -Description (got '$description')"
      ok=0
    fi
  else
    log_info "TEST-009: SKIP pwsh AST-parse/-Argument-bind discriminating check (pwsh not installed — install with 'brew install powershell' to run it, same convention as test-ps1-quality.sh)"
  fi

  [[ $ok -eq 1 ]] && log_pass "TEST-009 windows Register-ScheduledTask + both twins + valid executable PowerShell (pwsh AST parse, -Argument/-Description bound)" || log_fail "TEST-009 windows emission"
}

# --- TEST-010 — unknown harness / os each exit 2, empty stdout -------------
test_010_unknown_harness_os() {
  log_info "TEST-010: unknown --harness and unknown --os each exit 2, empty stdout..."
  local ok=1
  run_emit --routine SCRYER --harness bogus --os macos --repo owner/repo \
    --schedule "0 7 * * *" --model m --tz UTC
  [[ "$RC" -eq 2 && -z "$OUT" ]] || { log_info "TEST-010: bad harness rc=$RC out='$OUT'"; ok=0; }
  run_emit --routine SCRYER --harness claude --os bogus --repo owner/repo \
    --schedule "0 7 * * *" --model m --tz UTC
  [[ "$RC" -eq 2 && -z "$OUT" ]] || { log_info "TEST-010: bad os rc=$RC out='$OUT'"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-010 unknown harness/os -> exit 2, empty stdout" || log_fail "TEST-010 unknown harness/os"
}

# --- TEST-011 — authorized fixture -> merge-allowed true + 3 gates ---------
test_011_authorized_merge_enabled() {
  log_info "TEST-011: authorized fixture -> merge_enabled true, all 3 merge gates present, exit 0..."
  run_emit --routine SCRYER --harness claude --os macos --repo owner/repo \
    --schedule "0 7 * * *" --model claude-sonnet-5 --tz Europe/Prague \
    --merge --ref test-ref --decisions "$FIXDIR/decisions-authorized.jsonl"
  if [[ "$RC" -ne 0 ]]; then log_fail "TEST-011: exit $RC (want 0); stderr=$ERR"; return; fi
  local line merge_enabled prompt ok=1
  line="$(first_line "$OUT")"
  merge_enabled=$(printf '%s' "$line" | json_field merge_enabled)
  prompt=$(printf '%s' "$line" | json_field prompt)
  [[ "$merge_enabled" == "true" ]] || { log_info "TEST-011: merge_enabled=$merge_enabled"; ok=0; }
  grep -qF "CI is green" <<<"$prompt" || { log_info "TEST-011: gate 1 missing"; ok=0; }
  grep -qi "bot comments" <<<"$prompt" || { log_info "TEST-011: gate 2 missing"; ok=0; }
  grep -qF "[L3]" <<<"$prompt" || { log_info "TEST-011: gate 3 missing"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-011 authorized -> merge-enabled + 3 gates" || log_fail "TEST-011 authorized fixture"
}

# --- TEST-012 — unauthorized -> report-only + loud stderr, exit 0 ----------
test_012_unauthorized_report_only() {
  log_info "TEST-012: unauthorized fixture -> report-only, loud MERGE DISABLED stderr, exit 0..."
  run_emit --routine SCRYER --harness claude --os macos --repo owner/repo \
    --schedule "0 7 * * *" --model claude-sonnet-5 --tz Europe/Prague \
    --merge --ref test-ref --decisions "$FIXDIR/decisions-unauthorized.jsonl"
  local ok=1
  [[ "$RC" -eq 0 ]] || { log_info "TEST-012: exit $RC (want 0)"; ok=0; }
  local line merge_enabled prompt
  line="$(first_line "$OUT")"
  merge_enabled=$(printf '%s' "$line" | json_field merge_enabled)
  prompt=$(printf '%s' "$line" | json_field prompt)
  [[ "$merge_enabled" == "false" ]] || { log_info "TEST-012: merge_enabled=$merge_enabled"; ok=0; }
  grep -qF "## Merge gates" <<<"$prompt" && { log_info "TEST-012: merge-gate section leaked into report-only render"; ok=0; }
  grep -qF "MERGE DISABLED — no routine_authorization record for ref=test-ref in $FIXDIR/decisions-unauthorized.jsonl" <<<"$ERR" \
    || { log_info "TEST-012: loud stderr line missing/wrong: $ERR"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-012 unauthorized -> report-only + loud stderr" || log_fail "TEST-012 unauthorized fixture"
}

# --- TEST-013 — four near-miss records each yield report-only --------------
test_013_near_miss_records() {
  log_info "TEST-013: 4 near-miss fixtures (wrong ref, by!=human, grants lacking merge, wrong type) all report-only..."
  local ok=1 f line merge_enabled
  for f in decisions-near-miss-wrong-ref.jsonl decisions-near-miss-not-human.jsonl \
           decisions-near-miss-no-merge-grant.jsonl decisions-near-miss-wrong-type.jsonl; do
    run_emit --routine SCRYER --harness claude --os macos --repo owner/repo \
      --schedule "0 7 * * *" --model claude-sonnet-5 --tz Europe/Prague \
      --merge --ref test-ref --decisions "$FIXDIR/$f"
    if [[ "$RC" -ne 0 ]]; then log_info "TEST-013: $f exit $RC (want 0)"; ok=0; continue; fi
    line="$(first_line "$OUT")"
    merge_enabled=$(printf '%s' "$line" | json_field merge_enabled)
    [[ "$merge_enabled" == "false" ]] || { log_info "TEST-013: $f merge_enabled=$merge_enabled (want false)"; ok=0; }
  done
  [[ $ok -eq 1 ]] && log_pass "TEST-013 4 near-miss records all report-only" || log_fail "TEST-013 near-miss records"
}

# --- TEST-014 — absent + truncated decisions files fail closed -------------
test_014_absent_truncated_fail_closed() {
  log_info "TEST-014: absent and truncated decisions files fail closed to report-only, exit 0..."
  local ok=1 line merge_enabled
  run_emit --routine SCRYER --harness claude --os macos --repo owner/repo \
    --schedule "0 7 * * *" --model claude-sonnet-5 --tz Europe/Prague \
    --merge --ref test-ref --decisions "$TMP_ROOT/does-not-exist.jsonl"
  if [[ "$RC" -ne 0 ]]; then log_info "TEST-014: absent-file exit $RC (want 0)"; ok=0; else
    line="$(first_line "$OUT")"; merge_enabled=$(printf '%s' "$line" | json_field merge_enabled)
    [[ "$merge_enabled" == "false" ]] || { log_info "TEST-014: absent-file merge_enabled=$merge_enabled"; ok=0; }
  fi
  run_emit --routine SCRYER --harness claude --os macos --repo owner/repo \
    --schedule "0 7 * * *" --model claude-sonnet-5 --tz Europe/Prague \
    --merge --ref test-ref --decisions "$FIXDIR/decisions-truncated.jsonl"
  if [[ "$RC" -ne 0 ]]; then log_info "TEST-014: truncated-file exit $RC (want 0)"; ok=0; else
    line="$(first_line "$OUT")"; merge_enabled=$(printf '%s' "$line" | json_field merge_enabled)
    [[ "$merge_enabled" == "false" ]] || { log_info "TEST-014: truncated-file merge_enabled=$merge_enabled"; ok=0; }
  fi
  [[ $ok -eq 1 ]] && log_pass "TEST-014 absent + truncated fail closed" || log_fail "TEST-014 fail-closed ledger reads"
}

# --- TEST-015 — live ledger holds exactly one matching record --------------
test_015_live_ledger_record() {
  log_info "TEST-015: live docs/ai/decisions.jsonl holds exactly one matching routine_authorization record..."
  [[ -f "$REAL_DECISIONS" ]] || { log_fail "TEST-015: $REAL_DECISIONS missing"; return; }
  local out
  out=$(node -e '
    const fs = require("fs");
    const lines = fs.readFileSync(process.argv[1], "utf8").split("\n");
    let n = 0, ok = true;
    for (const l of lines) {
      const t = l.trim();
      if (!t) continue;
      let obj;
      try { obj = JSON.parse(t); } catch { continue; }
      if (obj && obj.type === "routine_authorization" && obj.ref === "aai-morning-scryer") {
        n += 1;
        if (obj.by !== "human") ok = false;
        if (!Array.isArray(obj.grants) || !obj.grants.includes("merge")) ok = false;
        if (obj.derived_from === undefined || obj.derived_from === null || obj.derived_from === "") ok = false;
      }
    }
    console.log(JSON.stringify({ n, ok }));
  ' "$REAL_DECISIONS")
  local n ok_field
  n=$(printf '%s' "$out" | json_field n)
  ok_field=$(printf '%s' "$out" | json_field ok)
  if [[ "$n" == "1" && "$ok_field" == "true" ]]; then
    log_pass "TEST-015 exactly one valid routine_authorization record in live ledger"
  else
    log_fail "TEST-015: n=$n ok=$ok_field (want n=1 ok=true)"
  fi
}

# --- TEST-016 — ledger change is append-only ---------------------------------
test_016_ledger_append_only() {
  log_info "TEST-016: first 83 lines of docs/ai/decisions.jsonl byte-unchanged since $BASELINE_SHA..."
  [[ -f "$REAL_DECISIONS" ]] || { log_fail "TEST-016: $REAL_DECISIONS missing"; return; }
  local before after
  before="$TMP_ROOT/t016-before.txt"
  after="$TMP_ROOT/t016-after.txt"
  if ! git -C "$PROJECT_ROOT" show "$BASELINE_SHA:docs/ai/decisions.jsonl" 2>/dev/null | sed -n '1,83p' > "$before"; then
    log_fail "TEST-016: cannot read baseline $BASELINE_SHA:docs/ai/decisions.jsonl"; return
  fi
  sed -n '1,83p' "$REAL_DECISIONS" > "$after"
  if diff -q "$before" "$after" >/dev/null 2>&1; then
    log_pass "TEST-016 first 83 lines byte-unchanged (append-only)"
  else
    log_fail "TEST-016: first 83 lines of $REAL_DECISIONS diverged from baseline"
  fi
}

# --- TEST-017 — live-ledger emit yields merge-allowed true ------------------
test_017_live_ledger_emit() {
  log_info "TEST-017: emit against live ledger, ref=aai-morning-scryer --merge -> merge-allowed true, exit 0..."
  run_emit --routine SCRYER --harness claude --os macos --repo owner/repo \
    --schedule "0 7 * * *" --model claude-sonnet-5 --tz Europe/Prague \
    --merge --ref aai-morning-scryer
  if [[ "$RC" -ne 0 ]]; then log_fail "TEST-017: exit $RC (want 0); stderr=$ERR"; return; fi
  local line merge_enabled
  line="$(first_line "$OUT")"
  merge_enabled=$(printf '%s' "$line" | json_field merge_enabled)
  if [[ "$merge_enabled" == "true" ]]; then
    log_pass "TEST-017 live-ledger emit -> merge-allowed true"
  else
    log_fail "TEST-017: merge_enabled=$merge_enabled (want true); stderr=$ERR"
  fi
}

# --- TEST-018 — verbatim on-demand pin --------------------------------------
test_018_on_demand_pin() {
  log_info "TEST-018: SKILL_ROUTINE.prompt.md pins the verbatim on-demand sentence..."
  [[ -f "$PROMPT_DOC" ]] || { log_fail "TEST-018: $PROMPT_DOC missing"; return; }
  grep -qF "This skill runs ON DEMAND only — never from bootstrap, sync, or any automatic path." "$PROMPT_DOC" \
    && log_pass "TEST-018 on-demand sentence pinned verbatim" \
    || log_fail "TEST-018 on-demand sentence pinned verbatim"
}

# --- TEST-019 — seven automatic surfaces are clean --------------------------
test_019_automatic_surfaces_clean() {
  log_info "TEST-019: 7 automatic surfaces contain neither routine-emit nor aai-routine..."
  local ok=1 f
  local surfaces=(
    "$PROJECT_ROOT/.aai/BOOTSTRAP.prompt.md"
    "$PROJECT_ROOT/.aai/SKILL_BOOTSTRAP.prompt.md"
    "$PROJECT_ROOT/.aai/SKILL_UPDATE.prompt.md"
    "$PROJECT_ROOT/.aai/SKILL_LOOP.prompt.md"
    "$PROJECT_ROOT/.aai/ORCHESTRATION.prompt.md"
    "$PROJECT_ROOT/.aai/scripts/aai-sync.sh"
    "$PROJECT_ROOT/.aai/scripts/aai-sync.ps1"
  )
  for f in "${surfaces[@]}"; do
    if [[ ! -f "$f" ]]; then
      log_info "TEST-019: expected automatic surface $f not found"; ok=0; continue
    fi
    if grep -qE "routine-emit|aai-routine" "$f"; then
      log_info "TEST-019: $f references routine-emit/aai-routine (must stay unwired)"
      ok=0
    fi
  done
  [[ $ok -eq 1 ]] && log_pass "TEST-019 automatic surfaces clean" || log_fail "TEST-019 automatic surfaces"
}

# --- TEST-020 — four wrappers exist with matching shape --------------------
test_020_wrappers_all_trees() {
  log_info "TEST-020: aai-routine wrapper present in .claude/.agents/.codex/.gemini..."
  local ok=1 t w
  for t in .claude .agents .codex .gemini; do
    w="$WRAPPER_ROOT/$t/skills/aai-routine/SKILL.md"
    if [[ ! -f "$w" ]]; then
      log_info "TEST-020: missing $w"; ok=0; continue
    fi
    grep -qF "name: aai-routine" "$w" || { log_info "TEST-020: $w missing frontmatter name"; ok=0; }
    grep -qF ".aai/SKILL_ROUTINE.prompt.md" "$w" || { log_info "TEST-020: $w does not reference SKILL_ROUTINE.prompt.md"; ok=0; }
    grep -qF "SKILL_ROUTINE not found" "$w" || { log_info "TEST-020: $w missing absent-prompt fallback sentence"; ok=0; }
  done
  [[ $ok -eq 1 ]] && log_pass "TEST-020 wrappers present in all four skill trees" || log_fail "TEST-020 wrappers"
}

# --- TEST-021 — every emission ends with TEST AT CREATION ------------------
test_021_test_at_creation_all_emissions() {
  log_info "TEST-021: all 4 harnesses x 2 merge modes carry the TEST AT CREATION block..."
  local ok=1 h m args
  for h in claude codex gemini generic; do
    for m in 0 1; do
      args=(--routine SCRYER --harness "$h" --os macos --repo owner/repo \
        --schedule "0 7 * * *" --model claude-sonnet-5 --tz Europe/Prague)
      if [[ "$m" == "1" ]]; then
        args+=(--merge --ref test-ref --decisions "$FIXDIR/decisions-authorized.jsonl")
      fi
      run_emit "${args[@]}"
      if [[ "$RC" -ne 0 ]]; then log_info "TEST-021: h=$h merge=$m exit $RC (want 0)"; ok=0; continue; fi
      grep -qF "## TEST AT CREATION" <<<"$OUT" || { log_info "TEST-021: h=$h merge=$m missing heading"; ok=0; }
      grep -qF "Verify:" <<<"$OUT" || { log_info "TEST-021: h=$h merge=$m missing Verify: line"; ok=0; }
      grep -qF "a digest was produced" <<<"$OUT" || { log_info "TEST-021: h=$h merge=$m missing verify item 1"; ok=0; }
      grep -qF "the run did not crash" <<<"$OUT" || { log_info "TEST-021: h=$h merge=$m missing verify item 2"; ok=0; }
      grep -qF "any degraded sections are named in the digest" <<<"$OUT" || { log_info "TEST-021: h=$h merge=$m missing verify item 3"; ok=0; }
    done
  done
  [[ $ok -eq 1 ]] && log_pass "TEST-021 TEST AT CREATION present in all 8 combinations" || log_fail "TEST-021 TEST AT CREATION coverage"
}

# --- TEST-022 — SKILLS.md carries one aai-routine row -----------------------
test_022_skills_md_row() {
  log_info "TEST-022: SKILLS.md carries exactly one aai-routine row naming the prompt path..."
  local skills_md="$PROJECT_ROOT/SKILLS.md"
  [[ -f "$skills_md" ]] || { log_fail "TEST-022: $skills_md missing"; return; }
  local n
  n=$(grep -cE '^\| aai-routine \|' "$skills_md" || true)
  local ok=1
  [[ "$n" == "1" ]] || { log_info "TEST-022: $n aai-routine rows (want 1)"; ok=0; }
  grep -qF "SKILL_ROUTINE.prompt.md" "$skills_md" || { log_info "TEST-022: row does not name SKILL_ROUTINE.prompt.md"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-022 SKILLS.md aai-routine row present" || log_fail "TEST-022 SKILLS.md row"
}

ALL_TESTS=(
  test_001_contract_elements
  test_002_placeholder_closure
  test_003_golden_diff
  test_004_idempotent
  test_005_zero_unresolved_placeholders
  test_006_missing_required_flag
  test_007_claude_json_fields
  test_008_local_scheduler_macos_linux
  test_009_windows_register_scheduled_task
  test_010_unknown_harness_os
  test_011_authorized_merge_enabled
  test_012_unauthorized_report_only
  test_013_near_miss_records
  test_014_absent_truncated_fail_closed
  test_015_live_ledger_record
  test_016_ledger_append_only
  test_017_live_ledger_emit
  test_018_on_demand_pin
  test_019_automatic_surfaces_clean
  test_020_wrappers_all_trees
  test_021_test_at_creation_all_emissions
  test_022_skills_md_row
)

main() {
  echo "Testing: $TEST_NAME"
  echo "===================="

  check_deps

  if [[ $# -gt 0 ]]; then
    local sel fn cand
    for sel in "$@"; do
      fn=""
      for cand in "${ALL_TESTS[@]}"; do
        [[ "$cand" == *"_${sel}_"* || "$cand" == "test_${sel}"* ]] && fn="$cand"
      done
      if [[ -n "$fn" ]]; then
        "$fn"
      else
        log_fail "no test matches selector '$sel'"
      fi
    done
  else
    local fn
    for fn in "${ALL_TESTS[@]}"; do
      "$fn"
    done
  fi

  echo ""
  if [[ $FAILED -eq 0 ]]; then
    echo "All tests passed!"
    exit 0
  else
    echo "Some tests FAILED."
    exit 1
  fi
}

main "$@"
