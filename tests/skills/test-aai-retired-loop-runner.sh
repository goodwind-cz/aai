#!/usr/bin/env bash
#
# Test: aai-retired-loop-runner
# (docs/specs/SPEC-DRAFT-spec-retire-shell-loop-runner.md, TEST-3403..3415)
#
# The shell loop runner retirement: autonomous-loop.sh / .ps1 are deprecation launchers
# that name /aai-loop, change nothing and exit 1. Every case here works in fresh mktemp
# fixtures; nothing touches the repository checkout.
#
# bash 3.2 compatible (no ${var^^}, no declare -A).
#
# Usage:
#   bash tests/skills/test-aai-retired-loop-runner.sh                       # run all
#   bash tests/skills/test-aai-retired-loop-runner.sh test_3403_sh_retired_run
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-retired-loop-runner"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SH_LAUNCHER="$PROJECT_ROOT/.aai/scripts/autonomous-loop.sh"
PS1_LAUNCHER="$PROJECT_ROOT/.aai/scripts/autonomous-loop.ps1"
PESTER_FILE="$PROJECT_ROOT/tests/skills/retired-loop-runner.Tests.ps1"
D1_LINE="autonomous-loop: retired - the autonomous-loop shell runner is retired (RFC-0017 phase 5) and will be deleted in the next release; replacement: /aai-loop; nothing was changed"

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
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  log_pass "Dependencies checked"
}

setup_fixture() {
  TEST_DIR="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/aai-retired-loop-runner-suite.XXXXXX")" && pwd -P)"
}

# need_tool <TEST id> <tool>: 0 when present; fail on CI when absent; named SKIP-CASE otherwise.
need_tool() {
  command -v "$2" >/dev/null 2>&1 && return 0
  [[ -z "${CI:-}" ]] || log_fail "$1: $2 is required on CI but is not on PATH"
  echo "SKIP-CASE: $1 needs $2, which is not installed here"
  return 1
}

# make_fixture <dir>: a clean committed repository whose docs/ai holds only .gitkeep.
make_fixture() {
  local d="$1"
  mkdir -p "$d/docs/ai"
  : > "$d/docs/ai/.gitkeep"
  git -C "$d" init -q
  git -C "$d" config user.email fixture@example.invalid
  git -C "$d" config user.name fixture
  git -C "$d" config commit.gpgsign false
  git -C "$d" add -A
  git -C "$d" commit -q -m fixture
}

# file_listing <dir>: sorted relative file list with content hashes, .git excluded.
file_listing() { (cd "$1" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(cksum < "$f")"; done); }

# assert_retired_run <TEST id> <label> <fixture> <before listing> <so> <se> <rc>: the D1 contract.
assert_retired_run() {
  local id="$1" label="$2" fx="$3" before="$4" so="$5" se="$6" rc="$7"
  [[ "$rc" == 1 ]] || log_fail "$id: $label exited $rc, expected 1"
  [[ ! -s "$so" ]] || log_fail "$id: $label wrote to stdout"
  [[ "$(cat "$se")" == "$D1_LINE" ]] || log_fail "$id: $label stderr was: $(cat "$se")"
  [[ ! -e "$fx/docs/ai/STATE.yaml" && ! -e "$fx/docs/ai/LOOP_TICKS.jsonl" ]] || log_fail "$id: $label created STATE.yaml or LOOP_TICKS.jsonl"
  [[ -z "$(git -C "$fx" status --porcelain)" ]] || log_fail "$id: $label left git status non-empty"
  [[ "$(file_listing "$fx")" == "$before" ]] || log_fail "$id: $label changed the file listing"
}

# scratch_bin <dir>: a PATH directory holding coreutils links only (no node, python3, codex, claude).
scratch_bin() {
  local b="$1" t p
  mkdir -p "$b"
  for t in cat ls env; do
    p="$(command -v "$t" 2>/dev/null || true)"
    if [[ -n "$p" && -x "$p" ]]; then ln -s "$p" "$b/$t"; fi
  done
}

test_3403_sh_retired_run() {
  local fx="$TEST_DIR/sh fx" bin="$TEST_DIR/bin-sh" so="$TEST_DIR/t.out" se="$TEST_DIR/t.err" before sh sh_path rc variant
  mkdir -p "$fx"
  make_fixture "$fx"
  scratch_bin "$bin"
  before="$(file_listing "$fx")"
  for sh in bash sh dash; do
    sh_path="$(command -v "$sh")" || { echo "SKIP-CASE: TEST-3403 needs $sh"; continue; }
    for variant in skill none; do
      rc=0
      if [[ "$variant" == skill ]]; then
        ( cd "$fx" && PATH="$bin" "$sh_path" "$SH_LAUNCHER" --mode skill --agent-command codex --max-iterations 1 --auto-init-state ) >"$so" 2>"$se" || rc=$?
      else
        ( cd "$fx" && PATH="$bin" "$sh_path" "$SH_LAUNCHER" ) >"$so" 2>"$se" || rc=$?
      fi
      assert_retired_run TEST-3403 "autonomous-loop.sh under $sh ($variant)" "$fx" "$before" "$so" "$se" "$rc"
    done
  done
  log_pass "TEST-3403: autonomous-loop.sh prints the D1 line, exits 1 and changes nothing under bash, sh and dash with no node, python3, codex or claude on PATH"
}

test_3404_ps1_retired_run() {
  need_tool TEST-3404 pwsh || return 0
  local fx="$TEST_DIR/ps1 fx" bin="$TEST_DIR/bin-ps1" so="$TEST_DIR/p.out" se="$TEST_DIR/p.err" before rc variant pwsh_path
  pwsh_path="$(command -v pwsh)"
  mkdir -p "$fx"
  make_fixture "$fx"
  scratch_bin "$bin"
  before="$(file_listing "$fx")"
  for variant in skill none dry; do
    rc=0
    case "$variant" in
      skill) ( cd "$fx" && PATH="$bin" "$pwsh_path" -NoProfile -File "$PS1_LAUNCHER" -Mode skill -AgentCommand codex -MaxIterations 1 -AutoInitState ) >"$so" 2>"$se" || rc=$? ;;
      none) ( cd "$fx" && PATH="$bin" "$pwsh_path" -NoProfile -File "$PS1_LAUNCHER" ) >"$so" 2>"$se" || rc=$? ;;
      dry) ( cd "$fx" && PATH="$bin" "$pwsh_path" -NoProfile -File "$PS1_LAUNCHER" -DryRun ) >"$so" 2>"$se" || rc=$? ;;
    esac
    assert_retired_run TEST-3404 "autonomous-loop.ps1 ($variant)" "$fx" "$before" "$so" "$se" "$rc"
  done
  log_pass "TEST-3404: autonomous-loop.ps1 prints the D1 line, exits 1 and changes nothing under pwsh for skill-mode switches, no argument and -DryRun"
}

test_3405_pester() {
  [[ -f "$PESTER_FILE" ]] || log_fail "TEST-3405: tests/skills/retired-loop-runner.Tests.ps1 does not exist"
  need_tool TEST-3405 pwsh || return 0
  local has out rc=0
  has="$(pwsh -NoProfile -Command 'if (Get-Module Pester -ListAvailable | Where-Object { $_.Version.Major -ge 5 }) { "yes" } else { "no" }' 2>/dev/null || echo no)"
  if [[ "$has" != yes ]]; then
    echo "SKIP-CASE: TEST-3405 needs Pester 5 (the ps1-quality gate job is the authoritative runner)"
    return 0
  fi
  out="$(env -u AAI_ROLE PESTER_FILE="$PESTER_FILE" pwsh -NoProfile -Command '
    $cfg = New-PesterConfiguration
    $cfg.Run.Path = $env:PESTER_FILE
    $cfg.Run.PassThru = $true
    $cfg.Output.Verbosity = "Normal"
    $r = Invoke-Pester -Configuration $cfg
    Write-Host "PESTER-RESULT: Total=$($r.TotalCount) Passed=$($r.PassedCount) Failed=$($r.FailedCount) Skipped=$($r.SkippedCount)"
    if ($r.FailedCount -gt 0 -or $r.SkippedCount -gt 0 -or $r.TotalCount -lt 3) { exit 1 }
    exit 0
  ' 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-3405: retired-loop-runner.Tests.ps1 failed, skipped a case or ran fewer than 3 cases (rc=$rc)"; }
  log_pass "TEST-3405: retired-loop-runner.Tests.ps1 passes with no skip under pwsh ($(printf '%s\n' "$out" | sed -n 's/^PESTER-RESULT: //p'))"
}

# launcher_problems <file> <D1 line>: prints problems of one launcher (empty when clean).
launcher_problems() {
  node -e '
    const fs = require("fs");
    const [file, want] = process.argv.slice(1);
    const buf = fs.readFileSync(file);
    const s = buf.toString("latin1");
    const bad = [];
    if (buf.some((b) => b > 0x7e || (b < 0x20 && b !== 10 && b !== 13 && b !== 9))) bad.push("non-ASCII byte");
    if (s.split("\n").length - (s.endsWith("\n") ? 1 : 0) > 20) bad.push("more than 20 lines");
    const marks = s.split(/\r?\n/).filter((l) => l.startsWith("# RETIRED (RFC-0017 phase 5, retire-shell-loop-runner)"));
    if (marks.length !== 1) bad.push("RETIRED comment lines: " + marks.length);
    if (!s.includes(want)) bad.push("D1 line text missing");
    if (file.endsWith(".sh") && s.split("\n")[0] !== "#!/bin/sh") bad.push("first line is not #!/bin/sh");
    if (file.endsWith(".ps1") && /^\s*param\s*\(/mi.test(s)) bad.push("holds a param block");
    const w = s.match(/\b(node|python\w*|git|codex|claude|gemini|mkdir|rm|cp|mv)\b/);
    if (w) bad.push("names " + w[0]);
    for (const x of ["STATE", "LOOP_TICKS", "SKILL_"]) if (s.includes(x)) bad.push("holds " + x);
    process.stdout.write(bad.join("; "));
  ' "$1" "$2"
}

test_3406_launchers_thin() {
  local name f out mode ctl
  for name in autonomous-loop.sh autonomous-loop.ps1; do
    f="$PROJECT_ROOT/.aai/scripts/$name"
    [[ -f "$f" ]] || log_fail "TEST-3406: $name does not exist"
    out="$(launcher_problems "$f" "$D1_LINE")"; [[ -z "$out" ]] || log_fail "TEST-3406: $name: $out"
    mode="$(git -C "$PROJECT_ROOT" ls-files -s -- ".aai/scripts/$name" | cut -d' ' -f1)"
    [[ "$mode" == 100644 ]] || log_fail "TEST-3406: $name git mode is '$mode', not 100644"
  done
  ctl="$TEST_DIR/ctl-retired.sh"
  { cat "$SH_LAUNCHER"; echo 'git status'; } > "$ctl"
  out="$(launcher_problems "$ctl" "$D1_LINE")"
  [[ "$out" == *"git"* ]] || log_fail "TEST-3406: positive control: a launcher holding git status was not reported"
  log_pass "TEST-3406: both launchers are thin, ASCII, mode 100644, carry the RETIRED comment and the D1 line and name no tool"
}

# stale_lines <newline list of tracked files> <root>: lines that name autonomous-loop outside the allowed set.
stale_lines() {
  node -e '
    const fs = require("fs");
    const [list, root] = process.argv.slice(1);
    const allowed = new Set([".aai/scripts/autonomous-loop.sh", ".aai/scripts/autonomous-loop.ps1", ".aai/system/PROFILES.yaml"]);
    const keepDocs = new Set(["docs/USER_GUIDE.md", "docs/TECHNOLOGY.md"]);
    const out = [];
    for (const f of list.split("\n").filter(Boolean)) {
      if ((f.startsWith("docs/") && !keepDocs.has(f)) || f.startsWith("tests/") || f === "CHANGELOG.md" || allowed.has(f)) continue;
      let t; try { t = fs.readFileSync(root + "/" + f, "utf8"); } catch { continue; }
      t.split("\n").forEach((l, i) => { if (/autonomous-loop/.test(l) && !/retired/.test(l)) out.push(f + ":" + (i + 1)); });
    }
    process.stdout.write(out.join(" "));
  ' "$1" "$2"
}

test_3407_no_stale_instruction() {
  local files out agents="$PROJECT_ROOT/.aai/AGENTS.md" guide="$PROJECT_ROOT/docs/USER_GUIDE.md"
  files="$(git -C "$PROJECT_ROOT" ls-files)"
  out="$(stale_lines "$files" "$PROJECT_ROOT")"
  [[ -z "$out" ]] || log_fail "TEST-3407: tracked files still tell anyone to run the runner: $out"
  printf 'run autonomous-loop.sh now\n' > "$TEST_DIR/fixture-extra.md"
  out="$(stale_lines "$files"$'\n'"fixture-extra.md" "$TEST_DIR" 2>/dev/null || true)"
  [[ "$out" == *fixture-extra.md* ]] || log_fail "TEST-3407: positive control: a fixture file naming the runner was not reported"
  grep -qxF -- '- Use SKILL_LOOP to run the autonomous loop; the shell loop runner is retired.' "$agents" || log_fail "TEST-3407: AGENTS.md lacks the D2 SKILL_LOOP line"
  if grep -qE 'Loop runners are skill-first|legacy mode' "$agents"; then log_fail "TEST-3407: AGENTS.md still holds the legacy mode line"; fi
  [[ "$(sed -n 4p "$PROJECT_ROOT/.aai/SKILL_LOOP.prompt.md")" == 'This replaces the retired external shell loop runner for agents' ]] || log_fail "TEST-3407: SKILL_LOOP line 4 is not the D2 text"
  [[ "$(sed -n 7p "$PROJECT_ROOT/.aai/BOOTSTRAP_DIFF.prompt.md")" == '.github/copilot-instructions.md)' ]] || log_fail "TEST-3407: BOOTSTRAP_DIFF line 7 is not the D2 text"
  if grep -qiE 'loop runner' "$PROJECT_ROOT/README.md" "$PROJECT_ROOT/docs/TECHNOLOGY.md"; then log_fail "TEST-3407: README.md or docs/TECHNOLOGY.md still holds a loop runner phrase"; fi
  grep -qxF -- '### Shell loop runners (retired)' "$guide" || log_fail "TEST-3407: USER_GUIDE.md lacks the D4 heading"
  if grep -qE -- '--agent-command|-AgentCommand|--mode skill' "$guide"; then log_fail "TEST-3407: USER_GUIDE.md still holds a runner invocation example"; fi
  log_pass "TEST-3407: no live instruction tells anyone to run the runner and every doc carries the D2 and D4 text"
}

test_3408_unattended_section() {
  local sec tok loop="$PROJECT_ROOT/.aai/SKILL_LOOP.prompt.md" n
  sec="$(awk '/^## 8\)/{f=1;print;next} /^## /{f=0} f' "$PROJECT_ROOT/.aai/system/AUTONOMOUS_LOOP.md")"
  [[ -n "$sec" ]] || log_fail "TEST-3408: AUTONOMOUS_LOOP.md has no section 8"
  for tok in '/aai-loop' '/aai-ship' '**Never merges**' '**Declared budget for unattended rides**' '**Self-recovery before HITL**' '**Wake-up digest**'; do
    [[ "$sec" == *"$tok"* ]] || log_fail "TEST-3408: section 8 lacks $tok"
  done
  for tok in '--propose-only' '-ProposeOnly' 'autonomous-loop'; do
    [[ "$sec" != *"$tok"* ]] || log_fail "TEST-3408: section 8 still holds $tok"
  done
  for tok in $(printf '%s\n' "$sec" | grep -oE '\.aai/[A-Za-z0-9_./-]+' | sed 's/[.,;:)]*$//' | sort -u); do
    [[ -e "$PROJECT_ROOT/$tok" ]] || log_fail "TEST-3408: section 8 names $tok, which does not exist"
  done
  grep -qF 'loop-digest.mjs --json' "$loop" || log_fail "TEST-3408: SKILL_LOOP no longer names loop-digest.mjs --json"
  [[ -f "$PROJECT_ROOT/.aai/scripts/loop-digest.mjs" ]] || log_fail "TEST-3408: loop-digest.mjs is gone"
  n="$(awk '/^core:/{f=1;next} /^[a-z]/{f=0} f && $0=="  - .aai/scripts/loop-digest.mjs"{c++} END{print c+0}' "$PROJECT_ROOT/.aai/system/PROFILES.yaml")"
  [[ "$n" == 1 ]] || log_fail "TEST-3408: PROFILES core lists loop-digest.mjs $n times, expected 1"
  log_pass "TEST-3408: section 8 names /aai-loop and /aai-ship with the four bullets, no propose-only text, and loop-digest.mjs stays"
}

test_3409_state_creator_pin() {
  local suite="$PROJECT_ROOT/tests/skills/test-aai-check-state.sh" body out rc=0 scratch="$TEST_DIR/pin-root"
  body="$(awk '/^test_single_state_creator\(\)/{f=1} f{print} f && /^}/{exit}' "$suite")"
  [[ -n "$body" ]] || log_fail "TEST-3409: test_single_state_creator is missing"
  for tok in autonomous-loop.sh autonomous-loop.ps1 STATE_TEMPLATE STATE.yaml check-state; do
    [[ "$body" == *"$tok"* ]] || log_fail "TEST-3409: test_single_state_creator does not name $tok"
  done
  out="$(env -u AAI_ROLE bash -c 'source "$1"; test_single_state_creator' _ "$suite" 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" | tail -n 15 >&2; log_fail "TEST-3409: test_single_state_creator exited $rc on the tree"; }
  mkdir -p "$scratch/.aai/scripts"
  cp "$SH_LAUNCHER" "$scratch/.aai/scripts/autonomous-loop.sh"
  { cat "$PS1_LAUNCHER"; echo '# docs/ai/STATE.yaml'; } > "$scratch/.aai/scripts/autonomous-loop.ps1"
  rc=0
  out="$(env -u AAI_ROLE bash -c 'source "$1"; PROJECT_ROOT="$2"; test_single_state_creator' _ "$suite" "$scratch" 2>&1)" || rc=$?
  [[ "$rc" != 0 && "$out" == *FAIL* ]] || log_fail "TEST-3409: positive control: a launcher naming STATE.yaml did not make test_single_state_creator fail"
  log_pass "TEST-3409: the single-creator pin names both launchers and the three D-PIN words, passes on the tree and fails on a launcher naming STATE.yaml"
}

test_3410_diet() {
  local ledger="${AAI_RLR_LEDGER:-$PROJECT_ROOT/tests/skills/lib/prompt-diet-ledger.sh}" n amount size want out rc=0
  n="$(grep -c 'retire-shell-loop-runner' "$ledger" || true)"
  [[ "$n" == 1 ]] || log_fail "TEST-3410: $n ledger lines name retire-shell-loop-runner, expected exactly 1"
  amount="$(sed -n 's/^JUSTIFIED_ADDITIONS+=( "\(-[0-9][0-9]*\) retire-shell-loop-runner RECLAIMED .*/\1/p' "$ledger")"
  [[ -n "$amount" ]] || log_fail "TEST-3410: the retire-shell-loop-runner ledger entry is not a negative RECLAIMED entry"
  size=$(( $(wc -c < "$PROJECT_ROOT/.aai/SKILL_LOOP.prompt.md") + $(wc -c < "$PROJECT_ROOT/.aai/BOOTSTRAP_DIFF.prompt.md") ))
  want=$((size - 33432))
  [[ "$amount" == "$want" ]] || log_fail "TEST-3410: the ledger amount is $amount, expected $want ($size minus 33432)"
  out="$(env -u AAI_ROLE bash "$PROJECT_ROOT/tests/skills/test-aai-prompt-diet.sh" test_010_audit_and_reduction 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" | tail -n 15 >&2; log_fail "TEST-3410: test-aai-prompt-diet.sh test_010 exited $rc"; }
  out="$out"$'\n'"$(env -u AAI_ROLE bash "$PROJECT_ROOT/tests/skills/test-aai-prompt-diet.sh" test_012_growth_sum_matches_ledger 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" | tail -n 15 >&2; log_fail "TEST-3410: test-aai-prompt-diet.sh test_012 exited $rc"; }
  [[ "$out" == *'headroom 0/2048'* ]] || log_fail "TEST-3410: TEST-010 headroom is not 0/2048"
  [[ "$out" == *"JUSTIFIED_GROWTH_BYTES == $((64288 + want)) =="* ]] || log_fail "TEST-3410: the TEST-012 pin is not $((64288 + want))"
  log_pass "TEST-3410: one negative ledger entry equal to the prompt shrink ($want B), headroom 0/2048, TEST-012 pin $((64288 + want))"
}

test_3411_wiring() {
  local wf="$PROJECT_ROOT/.github/workflows/ps1-quality.yml" n out f
  for f in .aai/scripts/autonomous-loop.sh .aai/scripts/autonomous-loop.ps1; do
    out="$(printf '%s\n' "$f" | node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from - --repo-root "$PROJECT_ROOT")"
    [[ "$out" == *'aai-retired-loop-runner'* ]] || log_fail "TEST-3411: $f does not select aai-retired-loop-runner: $out"
    n="$(awk '/^core:/{f=1;next} /^[a-z]/{f=0} f && $0=="  - '"$f"'"{c++} END{print c+0}' "$PROJECT_ROOT/.aai/system/PROFILES.yaml")"
    [[ "$n" == 1 ]] || log_fail "TEST-3411: PROFILES core lists $f $n times, expected 1"
  done
  env -u AAI_ROLE bash "$PROJECT_ROOT/tests/skills/test-aai-layer-profiles.sh" test_manifest_conformance >/dev/null 2>&1 || log_fail "TEST-3411: test-aai-layer-profiles.sh test_manifest_conformance failed"
  n="$(awk '/^  push:/{s="push"} /^  pull_request:/{s="pr"} /^  workflow_dispatch/{s=""} s!="" && $0=="      - '"'"'.aai/scripts/**.ps1'"'"'"{a[s]++} s!="" && $0=="      - '"'"'tests/skills/*.Tests.ps1'"'"'"{b[s]++} END{print a["push"]+0, a["pr"]+0, b["push"]+0, b["pr"]+0}' "$wf")"
  [[ "$n" == "1 1 1 1" ]] || log_fail "TEST-3411: the ps1-quality path lists hold the ps1 globs '$n' times (script push, script pr, tests push, tests pr), expected 1 1 1 1"
  log_pass "TEST-3411: both launchers select the suite, sit once under core, layer-profiles passes and both ps1-quality path lists keep their globs"
}

test_3412_downstream_install() {
  local tgt="$TEST_DIR/core target" src="${AAI_RLR_SYNC_SRC:-$PROJECT_ROOT}" f rc so="$TEST_DIR/i.out" se="$TEST_DIR/i.err" pre
  mkdir -p "$tgt"
  make_fixture "$tgt"
  bash "$src/.aai/scripts/aai-sync.sh" "$tgt" --profile core >/dev/null 2>&1 || log_fail "TEST-3412: aai-sync.sh --profile core failed"
  for f in autonomous-loop.sh autonomous-loop.ps1; do
    [[ -f "$tgt/.aai/scripts/$f" ]] || log_fail "TEST-3412: the core install lacks .aai/scripts/$f"
  done
  pre=0; [[ -e "$tgt/docs/ai/STATE.yaml" ]] && pre=1
  rc=0; ( cd "$tgt" && bash .aai/scripts/autonomous-loop.sh --mode skill --agent-command codex --auto-init-state ) >"$so" 2>"$se" || rc=$?
  [[ "$rc" == 1 && ! -s "$so" && "$(cat "$se")" == "$D1_LINE" ]] || log_fail "TEST-3412: the target's autonomous-loop.sh gave rc=$rc stderr=$(cat "$se")"
  if need_tool TEST-3412 pwsh; then
    rc=0; ( cd "$tgt" && pwsh -NoProfile -File .aai/scripts/autonomous-loop.ps1 -Mode skill -AutoInitState ) >"$so" 2>"$se" || rc=$?
    [[ "$rc" == 1 && ! -s "$so" && "$(cat "$se")" == "$D1_LINE" ]] || log_fail "TEST-3412: the target's autonomous-loop.ps1 gave rc=$rc stderr=$(cat "$se")"
  fi
  if [[ "$pre" == 0 && -e "$tgt/docs/ai/STATE.yaml" ]]; then log_fail "TEST-3412: a launcher run created docs/ai/STATE.yaml in the target"; fi
  log_pass "TEST-3412: a core install into a path with a space carries both launchers and the target's own launchers refuse with the D1 line"
}

RFC17="${AAI_RLR_RFC:-$PROJECT_ROOT/docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md}"
D6_SENTENCE='The sixth slice [retired the shell loop runner](../issues/CHANGE-DRAFT-retire-shell-loop-runner.md): autonomous-loop became a deprecation launcher for one release that names `/aai-loop`.'

test_3413_rfc() {
  local row n out rc=0
  out="$(env -u AAI_ROLE bash "$PROJECT_ROOT/tests/skills/test-aai-expert-fetch.sh" test_2624_inventory_matches_tree 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" | tail -n 10 >&2; log_fail "TEST-3413: test_2624_inventory_matches_tree exited $rc"; }
  row="$(grep '^| `autonomous-loop` |' "$RFC17" || true)"
  [[ -n "$row" ]] || log_fail "TEST-3413: the inventory has no autonomous-loop row"
  [[ "$row" == *'| 488/464 |'* && "$row" == *'| phase 5 process adapter |'* ]] || log_fail "TEST-3413: the autonomous-loop row lost its lines or destination cells"
  [[ "$row" == *'retire-shell-loop-runner.md)'* && "$row" == *'a deprecation launcher for one release naming /aai-loop, deleted in the next'* ]] || log_fail "TEST-3413: the autonomous-loop row lacks the D6 reason and link"
  row="$(grep '^| 5 | ' "$RFC17" || true)"
  [[ "$row" == *'| in progress |'* ]] || log_fail "TEST-3413: the phase 5 row is not in progress"
  [[ "$row" == *"$D6_SENTENCE"* ]] || log_fail "TEST-3413: the phase 5 row lacks the D6 sentence"
  n="$(grep -cF -- "$D6_SENTENCE" "$RFC17" || true)"
  [[ "$n" == 1 ]] || log_fail "TEST-3413: the D6 sentence appears $n times, expected once"
  log_pass "TEST-3413: the RFC-0017 inventory equals the tree, the autonomous-loop row carries the D6 reason and the phase 5 row the D6 sentence once"
}

# code_lines <file>: non-blank, non-hash-comment lines (the plan's method).
code_lines() {
  local g=grep
  [[ -x /usr/bin/grep ]] && g=/usr/bin/grep
  "$g" -cvE '^[[:space:]]*(#|$)' "$1" || true
}

test_3414_line_budget() {
  local d="${AAI_RLR_BUDGET_DIR:-$PROJECT_ROOT/.aai/scripts}" f n total sum=0
  for f in autonomous-loop.sh autonomous-loop.ps1; do
    n="$(code_lines "$d/$f")"
    [[ "$n" -le 2 ]] || log_fail "TEST-3414: $f has $n code lines, expected at most 2"
    total="$(wc -l < "$d/$f" | tr -d ' ')"
    [[ "$total" -le 20 ]] || log_fail "TEST-3414: $f has $total lines, expected at most 20"
    sum=$((sum + n))
  done
  [[ "$sum" -le 4 ]] || log_fail "TEST-3414: the two launchers hold $sum code lines, expected at most 4"
  log_pass "TEST-3414: code lines before 793, after $sum"
}

test_3415_follow_up() {
  local out
  out="$(node "$PROJECT_ROOT/.aai/scripts/follow-ups.mjs" list --status open --json)"
  printf '%s' "$out" | node -e '
    const j = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const m = j.items.filter((i) => i.id === "fu-delete-retired-shell-loop-runner");
    const bad = [];
    if (m.length !== 1) bad.push("open items with the id: " + m.length);
    else {
      const i = m[0];
      if (i.ref_id !== "retire-shell-loop-runner") bad.push("ref_id " + i.ref_id);
      if (i.severity !== "P3") bad.push("severity " + i.severity);
      for (const w of ["autonomous-loop.sh", "autonomous-loop.ps1", "PROFILES.yaml"]) if (!String(i.finding).includes(w)) bad.push("finding lacks " + w);
    }
    if (bad.length) { process.stderr.write(bad.join("; ")); process.exit(1); }
  ' || log_fail "TEST-3415: the follow-up item is wrong or missing"
  log_pass "TEST-3415: one open P3 item fu-delete-retired-shell-loop-runner names both launchers and PROFILES.yaml"
}

main() {
  echo "Testing $TEST_NAME (SPEC spec-retire-shell-loop-runner TEST-3403..3415)"
  check_deps
  setup_fixture
  test_3403_sh_retired_run
  test_3404_ps1_retired_run
  test_3405_pester
  test_3406_launchers_thin
  test_3407_no_stale_instruction
  test_3408_unattended_section
  test_3409_state_creator_pin
  test_3410_diet
  test_3411_wiring
  test_3412_downstream_install
  test_3413_rfc
  test_3414_line_budget
  test_3415_follow_up
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
