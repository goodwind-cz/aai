#!/usr/bin/env bash
#
# Test: aai-validate-skills
# (docs/specs/SPEC-DRAFT-spec-node-first-small-pairs.md, TEST-3201..3205, 3211..3213, 3216..3221)
#
# validate-skills is one Node module (.aai/scripts/validate-skills.mjs) plus two
# thin launchers; aai-live moves the same way (its own rows live in
# test-aai-live-status.sh); the pre-compact hook script is retired. This suite also carries
# the rows that pin the wiring (PROFILES, suite map, ps1-quality path lists), the
# RFC-0017 remaining-pairs inventory and the line budget. Every function runs
# alone under single-function dispatch:
#   bash tests/skills/test-aai-validate-skills.sh <function>
#
# bash 3.2 compatible (no ${var^^}, no declare -A).
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-validate-skills"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VS_SH="$PROJECT_ROOT/.aai/scripts/validate-skills.sh"
VS_PS1="$PROJECT_ROOT/.aai/scripts/validate-skills.ps1"
VS_MJS="$PROJECT_ROOT/.aai/scripts/validate-skills.mjs"
VS_NODE_TEST="$PROJECT_ROOT/tests/skills/lib/validate-skills.test.mjs"
VS_PESTER="$PROJECT_ROOT/tests/skills/validate-skills.Tests.ps1"
LIVE_SH="$PROJECT_ROOT/.aai/scripts/aai-live.sh"
LIVE_PS1="$PROJECT_ROOT/.aai/scripts/aai-live.ps1"
LIVE_MJS="$PROJECT_ROOT/.aai/scripts/aai-live.mjs"
PROFILES="$PROJECT_ROOT/.aai/system/PROFILES.yaml"
SUITE_MAP="$PROJECT_ROOT/tests/skills/suite-map.yaml"
WORKFLOW="$PROJECT_ROOT/.github/workflows/ps1-quality.yml"
RFC17="$PROJECT_ROOT/docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md"
SMOKE_PS1="$PROJECT_ROOT/tests/self-hosting/test-self-hosting-smoke.ps1"
V7_LINE="ERROR: validate-skills needs node (validate-skills.mjs unavailable)"
L11_LINE="aai-live: refused - node not found in PATH or aai-live.mjs missing"
# The retired script's name is built from two parts so this file never names it (TEST-3213 scans tracked files).
RETIRED="pre-compact""-save"
REQUIRED_FILES=".aai/SKILL_CHECK_STATE.prompt.md .aai/SKILL_INTAKE.prompt.md .aai/SKILL_LOOP.prompt.md .aai/SKILL_HITL.prompt.md .aai/SKILL_BOOTSTRAP.prompt.md .aai/SKILL_VALIDATE_REPORT.prompt.md .aai/SKILL_CANONICALIZE.prompt.md .aai/SKILL_TDD.prompt.md .aai/SKILL_WORKTREE.prompt.md .aai/SKILL_CODE_REVIEW.prompt.md .aai/SKILL_SHARE.prompt.md .aai/scripts/aai-bootstrap.sh"

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

real_path() { node -e 'process.stdout.write(require("fs").realpathSync(process.argv[1]))' "$1"; }

setup_fixture() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-vs-test.XXXXXX")"
  TEST_DIR="$(real_path "$TEST_DIR")"
}

need_tool() {
  command -v "$2" >/dev/null 2>&1 && return 0
  [[ -z "${CI:-}" ]] || log_fail "$1: $2 is required on CI but is not on PATH"
  echo "SKIP-CASE: $1 needs $2, which is not installed here"
  return 1
}

run_node_tests() {
  local id="$1" out rc=0
  [[ -f "$VS_MJS" ]] || log_fail "$id: .aai/scripts/validate-skills.mjs does not exist"
  [[ -f "$VS_NODE_TEST" ]] || log_fail "$id: tests/skills/lib/validate-skills.test.mjs does not exist"
  out="$(node --test --test-name-pattern "$id" "$VS_NODE_TEST" 2>&1)" || rc=$?
  if [[ "$rc" != 0 ]]; then
    printf '%s\n' "$out" >&2
    log_fail "$id: node --test exited $rc"
  fi
  if [[ ! "$out" =~ pass\ [1-9] ]]; then
    printf '%s\n' "$out" >&2
    log_fail "$id: node --test reported zero passing tests for the pattern"
  fi
}

# mk_bin <name> <tool>...: a directory of symlinks to the named tools; prints its path.
mk_bin() {
  local d="$TEST_DIR/bin-$1" t; shift
  rm -rf "$d"; mkdir -p "$d"
  for t in "$@"; do ln -s "$(command -v "$t")" "$d/$t"; done
  printf '%s' "$d"
}

# mk_target <name> [skip-file] [dir-file] [ticks 0|1]: a target root with the twelve required files (minus skip-file,
# dir-file as a directory) plus the bootstrap marker and, unless ticks is 0, a tick log holding a skill entry; prints it.
mk_target() {
  local t="$TEST_DIR/$1" skip="${2:-}" dirf="${3:-}" ticks="${4:-1}" f
  rm -rf "$t"; mkdir -p "$t"
  for f in $REQUIRED_FILES; do
    mkdir -p "$t/$(dirname "$f")"
    if [[ "$f" == "$dirf" ]]; then mkdir -p "$t/$f"
    elif [[ "$f" != "$skip" ]]; then : > "$t/$f"; fi
  done
  mkdir -p "$t/.claude/skills"; : > "$t/.claude/skills/AAI_DYNAMIC_SKILLS.md"
  if [[ "$ticks" == 1 ]]; then mkdir -p "$t/docs/ai"; printf '%s\n' '{"mode":"skill"}' > "$t/docs/ai/LOOP_TICKS.jsonl"; fi
  printf '%s' "$t"
}

# launcher_bad <file> <max lines> <module name> <banned token>...: prints one reason per violation, empty when thin.
launcher_bad() {
  local file="$1" max="$2" mod="$3"; shift 3
  node -e '
    const fs = require("fs");
    const [file, max, mod, ...banned] = process.argv.slice(1);
    const buf = fs.readFileSync(file);
    const s = buf.toString("latin1");
    const bad = [];
    if (buf.some((b) => b > 0x7e)) bad.push("byte above 0x7E");
    const lines = s.split("\n").length - (s.endsWith("\n") ? 1 : 0);
    if (lines > Number(max)) bad.push(lines + " lines, cap " + max);
    if (!s.includes(mod)) bad.push("no reference to " + mod);
    for (const t of banned) if (s.includes(t)) bad.push("holds " + t);
    process.stdout.write(bad.join("; "));
  ' "$file" "$max" "$mod" "$@"
}

# ======================= TEST-3201..3202 (module, node:test) ===================
test_3201_required_and_first_missing() { run_node_tests TEST-3201; log_pass "TEST-3201: REQUIRED order, the four bash lines, first missing path only, a directory counts as missing"; }
test_3202_warnings_and_target() { run_node_tests TEST-3202; log_pass "TEST-3202: WARN texts on stdout, literal skill-tick substring, missing target line"; }

# ======================= TEST-3203..3205 (launchers) ===========================
test_3203_vs_launchers_thin() {
  local bad n
  [[ -f "$VS_MJS" ]] || log_fail "TEST-3203: .aai/scripts/validate-skills.mjs does not exist"
  bad="$(launcher_bad "$VS_SH" 10 validate-skills.mjs SKILL_)"
  [[ -z "$bad" ]] || log_fail "TEST-3203: validate-skills.sh: $bad"
  bad="$(launcher_bad "$VS_PS1" 15 validate-skills.mjs SKILL_)"
  [[ -z "$bad" ]] || log_fail "TEST-3203: validate-skills.ps1: $bad"
  for n in "$VS_SH" "$VS_PS1"; do
    [[ "$(grep -cF -- "$V7_LINE" "$n" || true)" == 1 ]] || log_fail "TEST-3203: $(basename "$n") must hold the V-7 line exactly once"
  done
  [[ -x "$VS_SH" ]] || log_fail "TEST-3203: validate-skills.sh must keep its executable bit"
  log_pass "TEST-3203: both validate-skills launchers are thin, ASCII, name the module and hold the V-7 line once"
}

# vs_par <label> <target>: runs the sh and the ps1 launcher on the target and compares stdout, stderr and exit code.
vs_par() {
  local label="$1" t="$2" side rc d="$TEST_DIR/t3204-out"
  mkdir -p "$d"
  for side in sh ps; do
    rc=0
    if [[ "$side" == sh ]]; then bash "$VS_SH" "$t" > "$d/$label.$side.out" 2> "$d/$label.$side.err" || rc=$?
    else pwsh -NoProfile -File "$VS_PS1" -TargetRoot "$t" > "$d/$label.$side.out" 2> "$d/$label.$side.err" || rc=$?; fi
    echo "$rc" > "$d/$label.$side.rc"
  done
  cmp -s "$d/$label.sh.out" "$d/$label.ps.out" || log_fail "TEST-3204: stdout differs for $label: sh=$(cat "$d/$label.sh.out") ps=$(cat "$d/$label.ps.out")"
  cmp -s "$d/$label.sh.err" "$d/$label.ps.err" || log_fail "TEST-3204: stderr differs for $label: sh=$(cat "$d/$label.sh.err") ps=$(cat "$d/$label.ps.err")"
  cmp -s "$d/$label.sh.rc" "$d/$label.ps.rc" || log_fail "TEST-3204: exit code differs for $label: sh=$(cat "$d/$label.sh.rc") ps=$(cat "$d/$label.ps.rc")"
  PAR_RC="$(cat "$d/$label.sh.rc")"
}
PAR_RC=0

test_3204_vs_launcher_parity() {
  need_tool TEST-3204 pwsh || return 0
  [[ -f "$VS_MJS" ]] || log_fail "TEST-3204: .aai/scripts/validate-skills.mjs does not exist"
  local t rc out bin
  vs_par full "$(mk_target t3204-full)"
  [[ "$PAR_RC" == 0 ]] || log_fail "TEST-3204: the full fixture must exit 0 on both sides, got $PAR_RC"
  vs_par req-only "$(mk_target t3204-req "" "" 0)"
  [[ "$PAR_RC" == 0 ]] || log_fail "TEST-3204: the required-only fixture must exit 0, got $PAR_RC"
  vs_par one-missing "$(mk_target t3204-miss .aai/SKILL_TDD.prompt.md)"
  [[ "$PAR_RC" == 1 ]] || log_fail "TEST-3204: positive control failed, a missing file must exit 1 on both sides, got $PAR_RC"
  vs_par dir-at-required "$(mk_target t3204-dir "" .aai/SKILL_TDD.prompt.md)"
  [[ "$PAR_RC" == 1 ]] || log_fail "TEST-3204: a directory at a required path must exit 1 on both sides, got $PAR_RC"
  vs_par missing-target "$TEST_DIR/t3204-no-such-target"
  [[ "$PAR_RC" == 1 ]] || log_fail "TEST-3204: a missing target must exit 1 on both sides, got $PAR_RC"
  # V-7: without node, and without the module.
  bin="$(mk_bin t3204 bash dirname pwsh)"
  rc=0; PATH="$bin" "$bin/bash" -c 'command -v node >/dev/null 2>&1' || rc=$?
  [[ "$rc" != 0 ]] || log_fail "TEST-3204: positive control failed, node still resolves under the test PATH"
  t="$(mk_target t3204-nonode)"
  rc=0; out="$(PATH="$bin" "$bin/bash" "$VS_SH" "$t" 2> "$TEST_DIR/t3204.err")" || rc=$?
  [[ "$rc" == 1 && -z "$out" && "$(cat "$TEST_DIR/t3204.err")" == "$V7_LINE" ]] || log_fail "TEST-3204: sh without node: rc=$rc out=$out err=$(cat "$TEST_DIR/t3204.err")"
  rc=0; out="$(PATH="$bin" "$bin/pwsh" -NoProfile -File "$VS_PS1" -TargetRoot "$t" 2> "$TEST_DIR/t3204.err")" || rc=$?
  [[ "$rc" == 1 && -z "$out" && "$(cat "$TEST_DIR/t3204.err")" == "$V7_LINE" ]] || log_fail "TEST-3204: ps1 without node: rc=$rc out=$out err=$(cat "$TEST_DIR/t3204.err")"
  command -v node >/dev/null 2>&1 || log_fail "TEST-3204: positive control failed, node must resolve on the real PATH"
  mkdir -p "$TEST_DIR/t3204-nomod"
  cp "$VS_SH" "$VS_PS1" "$TEST_DIR/t3204-nomod/" || log_fail "TEST-3204: cannot copy the launchers"
  rc=0; out="$(bash "$TEST_DIR/t3204-nomod/validate-skills.sh" "$t" 2> "$TEST_DIR/t3204.err")" || rc=$?
  [[ "$rc" == 1 && -z "$out" && "$(cat "$TEST_DIR/t3204.err")" == "$V7_LINE" ]] || log_fail "TEST-3204: sh without the module: rc=$rc out=$out err=$(cat "$TEST_DIR/t3204.err")"
  rc=0; out="$(pwsh -NoProfile -File "$TEST_DIR/t3204-nomod/validate-skills.ps1" -TargetRoot "$t" 2> "$TEST_DIR/t3204.err")" || rc=$?
  [[ "$rc" == 1 && -z "$out" && "$(cat "$TEST_DIR/t3204.err")" == "$V7_LINE" ]] || log_fail "TEST-3204: ps1 without the module: rc=$rc out=$out err=$(cat "$TEST_DIR/t3204.err")"
  log_pass "TEST-3204: validate-skills.sh and validate-skills.ps1 give identical stdout, stderr and exit codes for five fixtures and print the V-7 line without node or module"
}

# run_pester <TEST id> <pester file> <min total> <label>: Invoke-Pester with PassThru; fails on a failure, a skip or a short run.
run_pester() {
  local id="$1" file="$2" min="$3" label="$4" has out rc=0
  [[ -f "$file" ]] || log_fail "$id: ${file#"$PROJECT_ROOT"/} does not exist"
  need_tool "$id" pwsh || return 0
  has="$(pwsh -NoProfile -Command 'if (Get-Module Pester -ListAvailable | Where-Object { $_.Version.Major -ge 5 }) { "yes" } else { "no" }' 2>/dev/null || echo no)"
  if [[ "$has" != yes ]]; then
    echo "SKIP-CASE: $id needs Pester 5 (the ps1-quality gate job is the authoritative runner)"
    return 0
  fi
  out="$(PESTER_FILE="$file" PESTER_MIN="$min" pwsh -NoProfile -Command '
    $cfg = New-PesterConfiguration
    $cfg.Run.Path = $env:PESTER_FILE
    $cfg.Run.PassThru = $true
    $cfg.Output.Verbosity = "Normal"
    $r = Invoke-Pester -Configuration $cfg
    Write-Host "PESTER-RESULT: Total=$($r.TotalCount) Passed=$($r.PassedCount) Failed=$($r.FailedCount) Skipped=$($r.SkippedCount)"
    if ($r.FailedCount -gt 0 -or $r.SkippedCount -gt 0 -or $r.TotalCount -lt [int]$env:PESTER_MIN) { exit 1 }
    exit 0
  ' 2>&1)" || rc=$?
  if [[ "$rc" != 0 ]]; then
    printf '%s\n' "$out" >&2
    log_fail "$id: $label failed, skipped a case or ran fewer than $min cases (rc=$rc)"
  fi
  log_pass "$id: $label passes with no skip ($(printf '%s\n' "$out" | sed -n 's/^PESTER-RESULT: //p'))"
}

test_3205_pester_validate_skills() { run_pester TEST-3205 "$VS_PESTER" 4 validate-skills.Tests.ps1; }

# ======================= TEST-3211..3213 =======================================
test_3211_existing_tests_pass() {
  local out rc fn
  [[ -f "$VS_MJS" ]] || log_fail "TEST-3211: .aai/scripts/validate-skills.mjs does not exist"
  for fn in test_027_opener_refusal test_031_watch_warmup_opens_existing_html test_037_one_shot_output_flag_opens_correct_file; do
    rc=0; out="$(env -u AAI_ROLE bash "$PROJECT_ROOT/tests/skills/test-aai-live-status.sh" "$fn" 2>&1)" || rc=$?
    [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-3211: live-status $fn exited $rc"; }
  done
  rc=0; out="$(bash "$PROJECT_ROOT/tests/self-hosting/test-self-hosting-smoke.sh" 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-3211: the sh self-hosting smoke exited $rc"; }
  [[ "$out" == *"PASS: self-hosting smoke"* ]] || log_fail "TEST-3211: the smoke printed no PASS line: $out"
  log_pass "TEST-3211: live-status TEST-027, TEST-031, TEST-037 and the sh self-hosting smoke pass on the changed tree"
}

test_3212_ps1_smoke_checks_exit() {
  need_tool TEST-3212 pwsh || return 0
  [[ -f "$SMOKE_PS1" ]] || log_fail "TEST-3212: the ps1 smoke does not exist"
  local block fx full bad rc
  block="$(awk '/validate-skills\.ps1/ { on = 1 } on && /^}/ { exit } on { print }' "$SMOKE_PS1")"
  [[ -n "$block" ]] || log_fail "TEST-3212: no validate-skills call block found in the ps1 smoke"
  fx="$TEST_DIR/t3212-root"; rm -rf "$fx"; mkdir -p "$fx/.aai/scripts"
  cp "$VS_PS1" "$VS_MJS" "$fx/.aai/scripts/" 2>/dev/null || log_fail "TEST-3212: cannot copy the launcher and the module (both must exist)"
  full="$(mk_target t3212-full)"; bad="$(mk_target t3212-bad .aai/SKILL_TDD.prompt.md)"
  { printf '%s\n' '$ErrorActionPreference = "Stop"' "\$root = '$fx'" "\$TargetRoot = '$full'"; printf '%s\n' "$block"; } > "$TEST_DIR/t3212-full.ps1"
  { printf '%s\n' '$ErrorActionPreference = "Stop"' "\$root = '$fx'" "\$TargetRoot = '$bad'"; printf '%s\n' "$block"; } > "$TEST_DIR/t3212-bad.ps1"
  rc=0; pwsh -NoProfile -File "$TEST_DIR/t3212-full.ps1" > /dev/null 2>&1 || rc=$?
  [[ "$rc" == 0 ]] || log_fail "TEST-3212: positive control failed, the block over the full fixture must exit 0, got $rc"
  rc=0; pwsh -NoProfile -File "$TEST_DIR/t3212-bad.ps1" > /dev/null 2>&1 || rc=$?
  [[ "$rc" != 0 ]] || log_fail "TEST-3212: the smoke's validate-skills block must throw over a fixture missing SKILL_TDD"
  log_pass "TEST-3212: the ps1 smoke fails on a non-zero validate-skills exit and passes on a valid root"
}

# retired_offenders <file list>: prints the listed files (one per line) that name the retired script, bar the two allowed ones.
retired_offenders() {
  local f
  while IFS= read -r f; do
    [[ -n "$f" && -f "$f" ]] || continue
    case "$f" in .aai/scripts/aai-doctor.mjs|tests/skills/test-aai-doctor.sh) continue ;; esac
    if grep -qF -- "$RETIRED" "$f"; then printf '%s\n' "$f"; fi
  done
}

test_3213_pre_compact_retired() {
  local f out
  for f in .aai/scripts/"$RETIRED".sh .aai/scripts/"$RETIRED".ps1; do
    [[ ! -e "$PROJECT_ROOT/$f" ]] || log_fail "TEST-3213: $f must be absent"
  done
  ! grep -qF -- "$RETIRED" "$PROFILES" || log_fail "TEST-3213: PROFILES.yaml still names the retired script"
  out="$(cd "$PROJECT_ROOT" && git ls-files | grep -v -e '^docs/' -e '^CHANGELOG\.md$' | retired_offenders)"
  [[ -z "$out" ]] || log_fail "TEST-3213: tracked files still name the retired script: $out"
  printf 'x %s\n' "$RETIRED" > "$TEST_DIR/t3213-decoy.txt"
  out="$(printf '%s\n' "$TEST_DIR/t3213-decoy.txt" | retired_offenders)"
  [[ "$out" == "$TEST_DIR/t3213-decoy.txt" ]] || log_fail "TEST-3213: positive control failed, a naming file must be reported, got: $out"
  log_pass "TEST-3213: both retired files are gone and nothing outside docs and the doctor names them"
}

# ======================= TEST-3216 (downstream extended install) ===============
test_3216_downstream_extended_sync() {
  local t="$TEST_DIR/t3216/target dir" c="$TEST_DIR/t3216/core dir" rc out stub log home real_t
  rm -rf "$TEST_DIR/t3216"; mkdir -p "$t/.aai/scripts" "$c" "$TEST_DIR/t3216/home"
  git -C "$t" init -q -b main || log_fail "TEST-3216: git init of the extended target failed"
  printf '#!/usr/bin/env bash\n# old hand-wired hook\n' > "$t/.aai/scripts/$RETIRED.sh"
  rc=0; bash "$PROJECT_ROOT/.aai/scripts/aai-sync.sh" "$t" --profile extended > "$TEST_DIR/t3216.sync.log" 2>&1 || rc=$?
  [[ "$rc" == 0 ]] || log_fail "TEST-3216: aai-sync.sh --profile extended exited $rc: $(cat "$TEST_DIR/t3216.sync.log")"
  [[ -f "$t/.aai/scripts/validate-skills.mjs" && -f "$t/.aai/scripts/aai-live.mjs" ]] || log_fail "TEST-3216: the extended target lacks validate-skills.mjs or aai-live.mjs"
  grep -qF -- "PRESERVE target-only script" "$TEST_DIR/t3216.sync.log" || log_fail "TEST-3216: the sync log has no PRESERVE line for the target-only script"
  grep -qF -- "old hand-wired hook" "$t/.aai/scripts/$RETIRED.sh" || log_fail "TEST-3216: the target's retired script was not preserved"
  rc=0; out="$(bash "$t/.aai/scripts/validate-skills.sh" "$t" 2> "$TEST_DIR/t3216.err")" || rc=$?
  [[ "$rc" == 0 && "$out" == *"Skill validation completed."* ]] || log_fail "TEST-3216: the target's validate-skills.sh must exit 0 (rc=$rc out=$out err=$(cat "$TEST_DIR/t3216.err"))"
  stub="$TEST_DIR/t3216-opener.sh"; log="$TEST_DIR/t3216-opener.log"; home="$TEST_DIR/t3216/home"; : > "$log"
  printf '%s\n' '#!/usr/bin/env bash' "if [[ -f \"\$1\" ]]; then echo \"EXISTS \$1\" >> \"$log\"; else echo \"MISSING \$1\" >> \"$log\"; fi" > "$stub"
  chmod +x "$stub"
  real_t="$(real_path "$t")"
  rc=0; HOME="$home" USERPROFILE="$home" CLAUDE_CONFIG_DIR="$home/.claude" CODEX_HOME="$home/.codex" GEMINI_HOME="$home/.gemini" AAI_LIVE_OPENER="$stub" \
    bash "$t/.aai/scripts/aai-live.sh" --output x.html --home "$home" --cache "$home/cache.json" --spool-dir "$home/spool" > "$TEST_DIR/t3216.live.log" 2>&1 || rc=$?
  [[ "$rc" == 0 ]] || log_fail "TEST-3216: the target's aai-live.sh exited $rc: $(cat "$TEST_DIR/t3216.live.log")"
  [[ "$(cat "$log")" == "EXISTS $real_t/x.html" ]] || log_fail "TEST-3216: the opener stub must see the written page, got: $(cat "$log")"
  git -C "$c" init -q -b main || log_fail "TEST-3216: git init of the core target failed"
  rc=0; bash "$PROJECT_ROOT/.aai/scripts/aai-sync.sh" "$c" --profile core > "$TEST_DIR/t3216.core.log" 2>&1 || rc=$?
  [[ "$rc" == 0 ]] || log_fail "TEST-3216: aai-sync.sh --profile core exited $rc: $(cat "$TEST_DIR/t3216.core.log")"
  for out in validate-skills.mjs aai-live.mjs; do
    [[ ! -e "$c/.aai/scripts/$out" ]] || log_fail "TEST-3216: the core target must not hold $out"
  done
  log_pass "TEST-3216: an extended install into a spaced path runs both launchers, keeps the old hook script; a core install holds neither module"
}

# ======================= TEST-3217..3221 (wiring and records) ==================
test_3217_profiles_classified() {
  local out
  out="$(node -e '
    const lines = require("fs").readFileSync(process.argv[1], "utf8").split("\n");
    const bad = [];
    let section = null;
    const hits = { "validate-skills.mjs": [], "aai-live.mjs": [] };
    for (const l of lines) {
      const h = /^([a-z_]+):\s*$/.exec(l);
      if (h) section = h[1];
      for (const k of Object.keys(hits)) if (l.trim() === "- .aai/scripts/" + k) hits[k].push(section);
    }
    for (const k of Object.keys(hits)) {
      if (hits[k].length !== 1) bad.push(k + " appears " + hits[k].length + " times");
      else if (hits[k][0] !== "extended") bad.push(k + " is in " + hits[k][0] + ", want extended");
    }
    process.stdout.write(bad.join("; "));
  ' "$PROFILES")"
  [[ -z "$out" ]] || log_fail "TEST-3217: $out"
  log_pass "TEST-3217: both modules are classified once, in the extended list"
}

test_3218_suite_map_selects() {
  local p out want
  for p in .aai/scripts/validate-skills.sh .aai/scripts/validate-skills.ps1 .aai/scripts/validate-skills.mjs tests/skills/lib/validate-skills.test.mjs tests/skills/validate-skills.Tests.ps1 \
    .aai/scripts/aai-live.mjs tests/skills/lib/aai-live.test.mjs tests/skills/aai-live.Tests.ps1; do
    out="$(node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from - <<<"$p")"
    [[ "$out" != *FULL_RUN* ]] || log_fail "TEST-3218: $p gives a FULL_RUN line: $out"
    case "$p" in *aai-live*) want="SELECTED aai-live-status" ;; *) want="SELECTED aai-validate-skills" ;; esac
    [[ "$out" == *"$want"* ]] || log_fail "TEST-3218: $p does not select ${want#SELECTED }: $out"
  done
  log_pass "TEST-3218: every new path selects its suite and none escalates to a full run"
}

# ps1_quality_lists <workflow>: prints the push and pull_request path lists as JSON.
ps1_quality_lists() {
  node -e '
    const lines = require("fs").readFileSync(process.argv[1], "utf8").split("\n");
    const lists = {}; let ev = null, inPaths = false;
    for (const l of lines) {
      let m;
      if ((m = /^  (push|pull_request):\s*$/.exec(l))) { ev = m[1]; inPaths = false; lists[ev] = []; continue; }
      if (/^  \S/.test(l)) { ev = null; inPaths = false; continue; }
      if (ev && /^    paths:\s*$/.test(l)) { inPaths = true; continue; }
      if (ev && inPaths) { if ((m = /^      - (.+)$/.exec(l))) lists[ev].push(m[1].trim()); else inPaths = false; }
    }
    process.stdout.write(JSON.stringify(lists));
  ' "$1"
}

test_3219_ps1_quality_paths() {
  local out
  out="$(ps1_quality_lists "$WORKFLOW" | node -e '
    const lists = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const bad = [];
    for (const k of ["push", "pull_request"]) {
      if (!lists[k] || lists[k].length === 0) { bad.push(k + ": no path list"); continue; }
      for (const m of [".aai/scripts/validate-skills.mjs", ".aai/scripts/aai-live.mjs"]) {
        if (!lists[k].includes("\x27" + m + "\x27")) bad.push(k + ": lacks " + m);
      }
    }
    if (lists.push && lists.pull_request && JSON.stringify(lists.push) !== JSON.stringify(lists.pull_request)) bad.push("lists differ");
    process.stdout.write(bad.join("; "));
  ')"
  [[ -z "$out" ]] || log_fail "TEST-3219: ps1-quality.yml path filter: $out"
  log_pass "TEST-3219: both path lists name both modules and are identical"
}

test_3220_line_budget() {
  local n sum f
  n="$(node -e 'const m = /three pairs 481 to (\d+) lines/.exec(require("fs").readFileSync(process.argv[1], "utf8")); if (m) process.stdout.write(m[1]);' "$RFC17")"
  [[ -n "$n" ]] || log_fail "TEST-3220: the RFC-0017 slice paragraph does not record 'three pairs 481 to N lines'"
  for f in "$VS_SH" "$VS_PS1" "$VS_MJS" "$LIVE_SH" "$LIVE_PS1" "$LIVE_MJS"; do
    [[ -f "$f" ]] || log_fail "TEST-3220: ${f#"$PROJECT_ROOT"/} does not exist"
  done
  sum="$(cat "$VS_SH" "$VS_PS1" "$VS_MJS" "$LIVE_SH" "$LIVE_PS1" "$LIVE_MJS" | wc -l | tr -d '[:space:]')"
  [[ "$n" == "$sum" ]] || log_fail "TEST-3220: the paragraph records $n lines but the six files total $sum"
  [[ "$n" -le 230 ]] || log_fail "TEST-3220: N=$n must be at most 230"
  log_pass "TEST-3220: the RFC paragraph records the live line total ($n <= 230)"
}

test_3221_rfc_inventory() {
  local out rc fn
  for fn in test_2624_inventory_matches_tree test_2623_rfc_phase3_done; do
    rc=0; out="$(env -u AAI_ROLE bash "$PROJECT_ROOT/tests/skills/test-aai-expert-fetch.sh" "$fn" 2>&1)" || rc=$?
    [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-3221: $fn exited $rc"; }
  done
  out="$(node -e '
    const lines = require("fs").readFileSync(process.argv[1], "utf8").split("\n");
    const at = lines.findIndex((l) => l === "### Remaining paired scripts after phase 3");
    const bad = [];
    if (at < 0) bad.push("inventory heading not found");
    let end = lines.length;
    for (let i = at + 1; i < lines.length; i++) if (/^#{1,3} /.test(lines[i])) { end = i; break; }
    const section = lines.slice(at + 1, end);
    const retired = process.argv[2];
    for (const l of section) {
      if (!/^\|/.test(l)) continue;
      const name = l.split("|")[1].trim().replace(/`/g, "");
      if (["aai-live", retired, "validate-skills"].includes(name)) bad.push("inventory still lists " + name);
    }
    const lastRow = section.map((l, i) => (/^\|/.test(l) ? i : -1)).reduce((a, b) => Math.max(a, b), -1);
    const after = section.slice(lastRow + 1).join("\n");
    if (!/\]\([^)]*node-first-small-pairs\.md\)/.test(after)) bad.push("no slice paragraph with a link ending node-first-small-pairs.md after the table");
    process.stdout.write(bad.join("; "));
  ' "$RFC17" "$RETIRED")"
  [[ -z "$out" ]] || log_fail "TEST-3221: $out"
  log_pass "TEST-3221: the RFC inventory matches the tree, drops the three pairs and carries the slice paragraph"
}

main() {
  echo "Testing $TEST_NAME (SPEC spec-node-first-small-pairs TEST-3201..3221)"
  check_deps
  setup_fixture
  test_3201_required_and_first_missing
  test_3202_warnings_and_target
  test_3203_vs_launchers_thin
  test_3204_vs_launcher_parity
  test_3205_pester_validate_skills
  test_3211_existing_tests_pass
  test_3212_ps1_smoke_checks_exit
  test_3213_pre_compact_retired
  test_3216_downstream_extended_sync
  test_3217_profiles_classified
  test_3218_suite_map_selects
  test_3219_ps1_quality_paths
  test_3220_line_budget
  test_3221_rfc_inventory
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
