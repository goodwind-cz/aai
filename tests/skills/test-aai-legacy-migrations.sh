#!/usr/bin/env bash
#
# Test: aai-legacy-migrations
# (docs/specs/SPEC-0273-spec-retire-legacy-migrations.md, TEST-3380..3402)
#
# The legacy-migration retirement: migrate-state-to-local is one Node module
# (.aai/scripts/migrate-state-to-local.mjs) behind thin launchers, and
# aai-canonicalize / migrate-yaml-to-jsonl are deprecation launchers. Every case
# here works in fresh mktemp fixtures; nothing touches the repository checkout.
#
# bash 3.2 compatible (no ${var^^}, no declare -A).
#
# Usage:
#   bash tests/skills/test-aai-legacy-migrations.sh                       # run all
#   bash tests/skills/test-aai-legacy-migrations.sh test_3380_pure
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-legacy-migrations"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MJS="$PROJECT_ROOT/.aai/scripts/migrate-state-to-local.mjs"
NODE_TEST="$PROJECT_ROOT/tests/skills/lib/migrate-state-to-local.test.mjs"
SH_LAUNCHER="$PROJECT_ROOT/.aai/scripts/migrate-state-to-local.sh"
PS1_LAUNCHER="$PROJECT_ROOT/.aai/scripts/migrate-state-to-local.ps1"
PESTER_FILE="$PROJECT_ROOT/tests/skills/legacy-migrations.Tests.ps1"
CANON_LINE="aai-canonicalize: retired - the aai-canonicalize script and the /aai-canonicalize skill are retired (RFC-0017 phase 5) and will be deleted in the next release; replacement: none; nothing was changed"
YAML_LINE="migrate-yaml-to-jsonl: retired - the migrate-yaml-to-jsonl script is retired (RFC-0017 phase 5) and will be deleted in the next release; replacement: none; nothing was changed"
D2_LINE="migrate-state-to-local: refused - node not found in PATH or migrate-state-to-local.mjs missing; nothing was changed. Install Node.js 22 or later (https://nodejs.org/) and re-run."

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
  TEST_DIR="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/aai-legacy-migrations-suite.XXXXXX")" && pwd -P)"
}

# run_node_tests <TEST id>: the module and node test file must exist; cases named with the id must
# pass; zero passing tests is a failure (a pattern that matches nothing is not a pass).
run_node_tests() {
  local id="$1" out rc=0
  [[ -f "$MJS" ]] || log_fail "$id: .aai/scripts/migrate-state-to-local.mjs does not exist"
  [[ -f "$NODE_TEST" ]] || log_fail "$id: tests/skills/lib/migrate-state-to-local.test.mjs does not exist"
  out="$(env -u AAI_ROLE node --test --test-name-pattern "$id" "$NODE_TEST" 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "$id: node --test exited $rc"; }
  [[ "$out" =~ pass\ [1-9] ]] || { printf '%s\n' "$out" >&2; log_fail "$id: node --test reported zero passing tests for the pattern"; }
}

test_3380_pure() {
  run_node_tests TEST-3380
  log_pass "TEST-3380: IGNORE_PATTERNS, parseArgs, missingPatterns and gitignoreAppend follow D1"
}

test_3381_effects() {
  run_node_tests TEST-3381
  log_pass "TEST-3381: a legacy fixture is migrated once and a second run is a byte-identical no-op"
}

test_3382_refusals_dry_run() {
  run_node_tests TEST-3382
  log_pass "TEST-3382: every refusal carries its D1 text and exit code, and a dry run changes nothing"
}

# need_tool <TEST id> <tool>: 0 when present; fail on CI when absent; named SKIP-CASE otherwise.
need_tool() {
  command -v "$2" >/dev/null 2>&1 && return 0
  [[ -z "${CI:-}" ]] || log_fail "$1: $2 is required on CI but is not on PATH"
  echo "SKIP-CASE: $1 needs $2, which is not installed here"
  return 1
}

# make_legacy <dir>: a clean committed legacy fixture (CRLF .gitignore, tracked runtime state).
make_legacy() {
  local d="$1"
  mkdir -p "$d/docs/ai/tdd/x" "$d/docs/ai/loop"
  printf 'node_modules\r\n' > "$d/.gitignore"
  echo x > "$d/docs/ai/STATE.yaml"; echo x > "$d/docs/ai/LOOP_TICKS.jsonl"
  echo x > "$d/docs/ai/tdd/.gitkeep"; echo x > "$d/docs/ai/tdd/x/red.log"; echo x > "$d/docs/ai/loop/a.txt"
  git -C "$d" init -q
  git -C "$d" config user.email fixture@example.invalid
  git -C "$d" config user.name fixture
  git -C "$d" config commit.gpgsign false
  git -C "$d" add -A
  git -C "$d" commit -q -m legacy
}

# launcher_problems <file> <sh|ps1>: prints problems of one migrate-state launcher (empty when clean).
launcher_problems() {
  node -e '
    const fs = require("fs");
    const [file, kind] = process.argv.slice(1);
    const buf = fs.readFileSync(file);
    const s = buf.toString("latin1");
    const bad = [];
    if (buf.some((b) => b > 0x7e || (b < 0x20 && b !== 10 && b !== 13 && b !== 9))) bad.push("non-ASCII byte");
    if (s.split("\n").length - (s.endsWith("\n") ? 1 : 0) > 20) bad.push("more than 20 lines");
    if (!s.includes("migrate-state-to-local.mjs")) bad.push("does not name migrate-state-to-local.mjs");
    if (kind === "sh") {
      if (s.split("\n")[0] !== "#!/bin/sh") bad.push("first line is not #!/bin/sh");
      if (s.includes("[[")) bad.push("holds [[");
      if (s.includes("BASH_SOURCE")) bad.push("holds BASH_SOURCE");
    }
    for (const w of ["rm --cached", "ls-files", ".gitignore", "EVENTS.jsonl", "UNTRACK", "docs/ai/"]) {
      if (s.includes(w)) bad.push("holds forbidden string " + w);
    }
    process.stdout.write(bad.join("; "));
  ' "$1" "$2"
}

test_3385_launchers_thin() {
  local out mode ctl
  out="$(launcher_problems "$SH_LAUNCHER" sh)"; [[ -z "$out" ]] || log_fail "TEST-3385: sh launcher: $out"
  out="$(launcher_problems "$PS1_LAUNCHER" ps1)"; [[ -z "$out" ]] || log_fail "TEST-3385: ps1 launcher: $out"
  mode="$(git -C "$PROJECT_ROOT" ls-files -s -- .aai/scripts/migrate-state-to-local.sh | cut -d' ' -f1)"
  [[ "$mode" == 100755 ]] || log_fail "TEST-3385: sh launcher git mode is '$mode', not 100755"
  ctl="$TEST_DIR/ctl.sh"
  { cat "$SH_LAUNCHER"; echo 'git rm --cached x'; } > "$ctl"
  out="$(launcher_problems "$ctl" sh)"
  [[ "$out" == *"rm --cached"* ]] || log_fail "TEST-3385: positive control: a launcher holding rm --cached was not reported"
  log_pass "TEST-3385: both migrate-state launchers are thin, ASCII, POSIX (sh) and hold no migration logic"
}

# assert_refused <TEST id> <label> <stdout file> <stderr file> <rc> <fixture>
assert_refused() {
  local id="$1" label="$2" so="$3" se="$4" rc="$5" fx="$6"
  [[ "$rc" == 1 ]] || log_fail "$id: $label exited $rc, expected 1"
  [[ ! -s "$so" ]] || log_fail "$id: $label wrote to stdout"
  [[ "$(cat "$se")" == "$D2_LINE" ]] || log_fail "$id: $label stderr was: $(cat "$se")"
  [[ -z "$(git -C "$fx" status --porcelain)" ]] || log_fail "$id: $label changed the fixture"
  [[ "$(od -An -c "$fx/.gitignore" | tr -d ' \n')" == "node_modules\r\n" ]] || log_fail "$id: $label changed .gitignore"
}

test_3386_refusal_no_node() {
  local fx="$TEST_DIR/refuse fx" bin="$TEST_DIR/nonode-bin" sh_path sh rc so se copy
  mkdir -p "$fx" "$bin"
  make_legacy "$fx"
  ln -sf "$(command -v git)" "$bin/git"; ln -sf "$(command -v dirname)" "$bin/dirname"
  so="$TEST_DIR/r.out"; se="$TEST_DIR/r.err"
  for sh in bash sh dash; do
    sh_path="$(command -v "$sh")" || { echo "SKIP-CASE: TEST-3386 needs $sh"; continue; }
    rc=0; ( cd "$fx" && PATH="$bin" "$sh_path" "$SH_LAUNCHER" "$fx" ) >"$so" 2>"$se" || rc=$?
    assert_refused TEST-3386 "sh launcher under $sh without node" "$so" "$se" "$rc" "$fx"
  done
  copy="$TEST_DIR/nomodule"; mkdir -p "$copy"; cp "$SH_LAUNCHER" "$copy/migrate-state-to-local.sh"
  rc=0; ( cd "$fx" && sh "$copy/migrate-state-to-local.sh" "$fx" ) >"$so" 2>"$se" || rc=$?
  assert_refused TEST-3386 "sh launcher copy without the module" "$so" "$se" "$rc" "$fx"
  if need_tool TEST-3386 pwsh; then
    cp "$PS1_LAUNCHER" "$copy/migrate-state-to-local.ps1"
    rc=0; ( cd "$fx" && pwsh -NoProfile -File "$copy/migrate-state-to-local.ps1" -TargetRoot "$fx" ) >"$so" 2>"$se" || rc=$?
    assert_refused TEST-3386 "ps1 launcher copy without the module" "$so" "$se" "$rc" "$fx"
  fi
  log_pass "TEST-3386: without node or without the module each launcher prints the D2 refusal, exits 1 and changes nothing"
}

# assert_migrated <TEST id> <label> <fixture>: the Spec-AC-02 effects on a launcher-migrated fixture.
assert_migrated() {
  local id="$1" label="$2" fx="$3" tracked n
  tracked="$(git -C "$fx" ls-files | sort | tr '\n' ' ')"
  [[ "$tracked" == ".gitignore docs/ai/tdd/.gitkeep " ]] || log_fail "$id: $label tracked set is: $tracked"
  n="$(grep -c -E '^(!?docs/ai/|docs/INDEX.audit.md)' "$fx/.gitignore" || true)"
  [[ "$n" == 16 ]] || log_fail "$id: $label .gitignore holds $n runtime entries, expected 16"
  [[ -f "$fx/docs/ai/EVENTS.jsonl" && ! -s "$fx/docs/ai/EVENTS.jsonl" ]] || log_fail "$id: $label EVENTS.jsonl is missing or not empty"
}

test_3387_sh_launcher_e2e() {
  local base="$TEST_DIR/e2e space" src sh sh_path fx so rc
  mkdir -p "$base"
  src="$base/src"; mkdir -p "$src"; make_legacy "$src"
  so="$TEST_DIR/e.out"
  for sh in bash sh dash; do
    sh_path="$(command -v "$sh")" || { echo "SKIP-CASE: TEST-3387 needs $sh"; continue; }
    fx="$base/arg-$sh"; cp -R "$src" "$fx"
    rc=0; ( cd "$TEST_DIR" && "$sh_path" "$SH_LAUNCHER" "$fx" ) >"$so" 2>&1 || rc=$?
    [[ "$rc" == 0 ]] || { cat "$so" >&2; log_fail "TEST-3387: $sh with an argument exited $rc"; }
    grep -qxF "Target: $fx" "$so" || log_fail "TEST-3387: $sh with an argument did not print Target: $fx"
    assert_migrated TEST-3387 "$sh with an argument" "$fx"
    fx="$base/cwd-$sh"; cp -R "$src" "$fx"
    rc=0; ( cd "$fx" && "$sh_path" "$SH_LAUNCHER" ) >"$so" 2>&1 || rc=$?
    [[ "$rc" == 0 ]] || { cat "$so" >&2; log_fail "TEST-3387: $sh with no argument exited $rc"; }
    grep -qxF "Target: $fx" "$so" || log_fail "TEST-3387: $sh with no argument did not print Target: $fx"
    assert_migrated TEST-3387 "$sh with no argument" "$fx"
  done
  fx="$base/dry"; cp -R "$src" "$fx"
  rc=0; ( cd "$TEST_DIR" && sh "$SH_LAUNCHER" "$fx" --dry-run ) >"$so" 2>&1 || rc=$?
  [[ "$rc" == 0 ]] || log_fail "TEST-3387: --dry-run exited $rc"
  grep -qxF 'Dry-run only. Re-run without the dry-run flag to apply.' "$so" || log_fail "TEST-3387: --dry-run was not forwarded to the module"
  [[ -z "$(git -C "$fx" status --porcelain)" && ! -e "$fx/docs/ai/EVENTS.jsonl" ]] || log_fail "TEST-3387: --dry-run changed the fixture"
  log_pass "TEST-3387: the sh launcher migrates a fixture in a path with a space under bash, sh and dash, with and without an argument, and forwards --dry-run"
}

test_3383_hostile_names() {
  run_node_tests TEST-3383
  log_pass "TEST-3383: hostile tracked names are untracked literally, run no command and keep .gitkeep tracked"
}

test_3402_refused_name() {
  run_node_tests TEST-3402
  log_pass "TEST-3402: a name git refuses to remove (git~1, non-UTF-8) exits 1 with the index unchanged and no untracked claim"
}

test_3384_rm_failure() {
  run_node_tests TEST-3384
  log_pass "TEST-3384: a failing git rm prints the D1 error, exits 1 and writes nothing else"
}

test_3388_pester() {
  [[ -f "$PESTER_FILE" ]] || log_fail "TEST-3388: tests/skills/legacy-migrations.Tests.ps1 does not exist"
  need_tool TEST-3388 pwsh || return 0
  local has out rc=0
  has="$(pwsh -NoProfile -Command 'if (Get-Module Pester -ListAvailable | Where-Object { $_.Version.Major -ge 5 }) { "yes" } else { "no" }' 2>/dev/null || echo no)"
  if [[ "$has" != yes ]]; then
    echo "SKIP-CASE: TEST-3388 needs Pester 5 (the ps1-quality gate job is the authoritative runner)"
    return 0
  fi
  out="$(env -u AAI_ROLE PESTER_FILE="$PESTER_FILE" pwsh -NoProfile -Command '
    $cfg = New-PesterConfiguration
    $cfg.Run.Path = $env:PESTER_FILE
    $cfg.Run.PassThru = $true
    $cfg.Output.Verbosity = "Normal"
    $r = Invoke-Pester -Configuration $cfg
    Write-Host "PESTER-RESULT: Total=$($r.TotalCount) Passed=$($r.PassedCount) Failed=$($r.FailedCount) Skipped=$($r.SkippedCount)"
    if ($r.FailedCount -gt 0 -or $r.SkippedCount -gt 0 -or $r.TotalCount -lt 7) { exit 1 }
    exit 0
  ' 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-3388: legacy-migrations.Tests.ps1 failed, skipped a case or ran fewer than 7 cases (rc=$rc)"; }
  log_pass "TEST-3388: legacy-migrations.Tests.ps1 passes with no skip under pwsh ($(printf '%s\n' "$out" | sed -n 's/^PESTER-RESULT: //p'))"
}

# file_listing <dir>: sorted relative file list with content hashes, .git excluded.
file_listing() { (cd "$1" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(cksum < "$f")"; done); }

test_3389_retired_run() {
  local fx="$TEST_DIR/retired fx" bin="$TEST_DIR/empty-bin" so="$TEST_DIR/t.out" se="$TEST_DIR/t.err" before name line sh sh_path rc
  mkdir -p "$fx" "$bin"
  make_legacy "$fx"
  before="$(file_listing "$fx")"
  for name in aai-canonicalize migrate-yaml-to-jsonl; do
    line="$CANON_LINE"; [[ "$name" == migrate-yaml-to-jsonl ]] && line="$YAML_LINE"
    for sh in bash sh dash; do
      sh_path="$(command -v "$sh")" || { echo "SKIP-CASE: TEST-3389 needs $sh"; continue; }
      rc=0; ( cd "$fx" && PATH="$bin" "$sh_path" "$PROJECT_ROOT/.aai/scripts/$name.sh" . --dry-run ) >"$so" 2>"$se" || rc=$?
      [[ "$rc" == 1 ]] || log_fail "TEST-3389: $name.sh under $sh exited $rc, expected 1"
      [[ ! -s "$so" ]] || log_fail "TEST-3389: $name.sh under $sh wrote to stdout"
      [[ "$(cat "$se")" == "$line" ]] || log_fail "TEST-3389: $name.sh under $sh stderr was: $(cat "$se")"
      [[ -z "$(git -C "$fx" status --porcelain)" ]] || log_fail "TEST-3389: $name.sh under $sh changed the fixture"
      [[ "$(file_listing "$fx")" == "$before" ]] || log_fail "TEST-3389: $name.sh under $sh changed the file listing"
    done
    if need_tool TEST-3389 pwsh; then
      rc=0; ( cd "$fx" && PATH="$bin" "$(command -v pwsh)" -NoProfile -File "$PROJECT_ROOT/.aai/scripts/$name.ps1" -TargetRoot . -DryRun ) >"$so" 2>"$se" || rc=$?
      [[ "$rc" == 1 ]] || log_fail "TEST-3389: $name.ps1 exited $rc, expected 1"
      [[ ! -s "$so" ]] || log_fail "TEST-3389: $name.ps1 wrote to stdout"
      [[ "$(cat "$se")" == "$line" ]] || log_fail "TEST-3389: $name.ps1 stderr was: $(cat "$se")"
      [[ -z "$(git -C "$fx" status --porcelain)" && "$(file_listing "$fx")" == "$before" ]] || log_fail "TEST-3389: $name.ps1 changed the fixture"
    fi
  done
  log_pass "TEST-3389: the four retirement launchers print their D3 line, exit 1 and change nothing, with no node and no python3 on PATH"
}

# retired_problems <file> <expected line>: prints problems of one retirement launcher (empty when clean).
retired_problems() {
  node -e '
    const fs = require("fs");
    const [file, want] = process.argv.slice(1);
    const buf = fs.readFileSync(file);
    const s = buf.toString("latin1");
    const bad = [];
    if (buf.some((b) => b > 0x7e || (b < 0x20 && b !== 10 && b !== 13 && b !== 9))) bad.push("non-ASCII byte");
    if (s.split("\n").length - (s.endsWith("\n") ? 1 : 0) > 20) bad.push("more than 20 lines");
    const marks = s.split(/\r?\n/).filter((l) => l.startsWith("# RETIRED (RFC-0017 phase 5, retire-legacy-migrations)"));
    if (marks.length !== 1) bad.push("RETIRED comment lines: " + marks.length);
    if (!s.includes(want)) bad.push("D3 line text missing");
    const w = s.match(/\b(python\w*|node|git|mv|cp|rm|mkdir)\b/);
    if (w) bad.push("names " + w[0]);
    process.stdout.write(bad.join("; "));
  ' "$1" "$2"
}

test_3390_retired_thin() {
  local name line f out mode ctl
  for name in aai-canonicalize.sh aai-canonicalize.ps1 migrate-yaml-to-jsonl.sh migrate-yaml-to-jsonl.ps1; do
    line="$CANON_LINE"; [[ "$name" == migrate-yaml-to-jsonl* ]] && line="$YAML_LINE"
    f="$PROJECT_ROOT/.aai/scripts/$name"
    out="$(retired_problems "$f" "$line")"; [[ -z "$out" ]] || log_fail "TEST-3390: $name: $out"
    mode="$(git -C "$PROJECT_ROOT" ls-files -s -- ".aai/scripts/$name" | cut -d' ' -f1)"
    [[ "$mode" == 100644 ]] || log_fail "TEST-3390: $name git mode is '$mode', not 100644"
  done
  ctl="$TEST_DIR/ctl-retired.sh"
  { cat "$PROJECT_ROOT/.aai/scripts/migrate-yaml-to-jsonl.sh"; echo 'python3 -c pass'; } > "$ctl"
  out="$(retired_problems "$ctl" "$YAML_LINE")"
  [[ "$out" == *"python3"* ]] || log_fail "TEST-3390: positive control: a launcher holding python3 was not reported"
  log_pass "TEST-3390: the four retirement launchers are thin, ASCII, mode 100644, carry the RETIRED comment and name no tool"
}

test_3396_doctor_seam() {
  local fx="$TEST_DIR/doctor fx" out rc=0 f
  mkdir -p "$fx/docs/ai" "$fx/.aai"
  cp -R "${AAI_LM_SCRIPTS:-$PROJECT_ROOT/.aai/scripts}" "$fx/.aai/scripts"
  echo x > "$fx/docs/ai/STATE.yaml"
  printf 'docs/ai/STATE.yaml\n' > "$fx/.gitignore"
  git -C "$fx" init -q
  git -C "$fx" config user.email fixture@example.invalid
  git -C "$fx" config user.name fixture
  git -C "$fx" config commit.gpgsign false
  git -C "$fx" add -A -f
  git -C "$fx" commit -q -m legacy
  out="$(node "$fx/.aai/scripts/aai-doctor.mjs" --root "$fx" 2>&1)" || true
  [[ "$out" == *INCONSISTENT* && "$out" == *migrate-state-to-local.sh* ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-3396: the doctor did not report INCONSISTENT naming migrate-state-to-local.sh"; }
  ( cd "$fx" && bash .aai/scripts/migrate-state-to-local.sh ) >/dev/null 2>&1 || log_fail "TEST-3396: the named launcher failed"
  git -C "$fx" add .gitignore docs/ai/EVENTS.jsonl
  git -C "$fx" commit -q -m migrate
  out="$(node "$fx/.aai/scripts/aai-doctor.mjs" --root "$fx" 2>&1)" || true
  [[ "$out" != *migrate-state-to-local* ]] || { printf '%s\n' "$out" >&2; log_fail "TEST-3396: the doctor still names migrate-state-to-local after the migration"; }
  for f in .aai/scripts/aai-doctor.mjs .aai/scripts/aai-sync.sh .aai/scripts/aai-sync.ps1 README.md; do
    [[ "$(git -C "$PROJECT_ROOT" show "f324b66f:$f" | grep -F migrate-state-to-local)" == "$(grep -F migrate-state-to-local "$PROJECT_ROOT/$f")" ]] \
      || log_fail "TEST-3396: the migrate-state-to-local lines of $f differ from f324b66f"
  done
  log_pass "TEST-3396: the doctor names the launcher, the launcher clears the finding, and the caller lines equal f324b66f"
}

CANON_PROMPT="$PROJECT_ROOT/.aai/SKILL_CANONICALIZE.prompt.md"
WRAPPER_BODY='Read the file `.aai/SKILL_CANONICALIZE.prompt.md` from the current project root and follow its instructions exactly - it is a retirement notice: explain it to the user and run no script. Invoke this as `/aai-canonicalize`.'
WRAPPER_TREES=".claude/skills .agents/skills .codex/skills .gemini/skills"

# wrapper_problems <SKILL.md>: prints problems of the retired aai-canonicalize wrapper (empty when clean).
wrapper_problems() {
  node -e '
    const fs = require("fs");
    const [file, body] = process.argv.slice(1);
    const s = fs.readFileSync(file, "utf8");
    const bad = [];
    const m = s.match(/^---\n([\s\S]*?)\n---\n/);
    if (!m) bad.push("no frontmatter");
    else {
      if (!/^name: aai-canonicalize$/m.test(m[1])) bad.push("name is not aai-canonicalize");
      const d = m[1].match(/^description: (.*)$/m);
      if (!d || !d[1].startsWith("RETIRED - ")) bad.push("description does not begin RETIRED - ");
      else for (const w of ["RFC-0017 phase 5", "next release", "no replacement", "runs nothing"]) if (!d[1].includes(w)) bad.push("description lacks " + w);
    }
    const lines = s.replace(/^---\n[\s\S]*?\n---\n/, "").split("\n").filter((l) => l.trim() !== "");
    if (lines.length !== 2) bad.push("body has " + lines.length + " non-empty lines");
    if (lines[0] !== body) bad.push("body line 1 differs from D4");
    if (!(lines[1] || "").startsWith("If `.aai/SKILL_CANONICALIZE.prompt.md` does not exist, say:")) bad.push("not-found line missing");
    process.stdout.write(bad.join("; "));
  ' "$1" "$WRAPPER_BODY"
}

test_3391_skill_notice() {
  local out size t first
  [[ -f "$CANON_PROMPT" ]] || log_fail "TEST-3391: the prompt is missing"
  size="$(wc -c < "$CANON_PROMPT" | tr -d ' ')"
  [[ "$size" -le 900 ]] || log_fail "TEST-3391: the prompt is $size bytes, over 900"
  first="$(sed -n 1p "$CANON_PROMPT")"
  [[ "$first" == "# Canonicalize Skill - RETIRED" ]] || log_fail "TEST-3391: the prompt first line is: $first"
  grep -q '^Status: RETIRED (retire-legacy-migrations, RFC-0017 phase 5, 2026-11-05)' "$CANON_PROMPT" || log_fail "TEST-3391: no D4 Status line"
  grep -q '^Replacement: none' "$CANON_PROMPT" || log_fail "TEST-3391: no 'Replacement: none' line"
  grep -qi 'next release deletes' "$CANON_PROMPT" || log_fail "TEST-3391: the prompt does not say the next release deletes the notice"
  if grep -qE '\.sh|\.ps1|-DryRun|--dry-run' "$CANON_PROMPT"; then log_fail "TEST-3391: the prompt names a script file or dry-run flag"; fi
  for t in $WRAPPER_TREES; do
    [[ -f "$PROJECT_ROOT/$t/aai-canonicalize/SKILL.md" ]] || log_fail "TEST-3391: $t/aai-canonicalize/SKILL.md missing"
    cmp -s "$PROJECT_ROOT/.claude/skills/aai-canonicalize/SKILL.md" "$PROJECT_ROOT/$t/aai-canonicalize/SKILL.md" || log_fail "TEST-3391: $t wrapper differs from the .claude copy"
  done
  out="$(wrapper_problems "$PROJECT_ROOT/.claude/skills/aai-canonicalize/SKILL.md")"
  [[ -z "$out" ]] || log_fail "TEST-3391: wrapper: $out"
  env -u AAI_ROLE node "$PROJECT_ROOT/.aai/scripts/sync-harness-skills.mjs" --check >/dev/null 2>&1 || log_fail "TEST-3391: sync-harness-skills --check failed"
  for t in .codex .gemini; do
    grep -qE '^- `/aai-canonicalize` .*RETIRED' "$PROJECT_ROOT/$t/skills/README.md" || log_fail "TEST-3391: $t/skills/README.md row lacks RETIRED"
  done
  node -e '
    const d = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const c = (d.skills || []).find((x) => x.name === "aai-canonicalize");
    if (!c || !JSON.stringify(c).includes("RETIRED")) { console.error("catalog card lacks RETIRED"); process.exit(1); }
  ' "$PROJECT_ROOT/docs/skill-catalog-data.json" || log_fail "TEST-3391: the catalog card for aai-canonicalize lacks RETIRED"
  local hub="$TEST_DIR/hub"
  rm -rf "$hub"; mkdir -p "$hub/docs" "$hub/.aai"
  cp -R "$PROJECT_ROOT/.claude" "$hub/.claude"; cp "$PROJECT_ROOT"/.aai/SKILL_*.prompt.md "$hub/.aai/"
  ( cd "$hub" && node "$PROJECT_ROOT/.aai/scripts/generate-docs-hub.mjs" >/dev/null ) || log_fail "TEST-3391: generate-docs-hub failed in the scratch tree"
  cmp -s "$hub/docs/SKILL_CATALOG.html" "$PROJECT_ROOT/docs/SKILL_CATALOG.html" || log_fail "TEST-3391: docs/SKILL_CATALOG.html is stale against generate-docs-hub"
  [[ "$(grep -v '"generatedAt"' "$hub/docs/skill-catalog-data.json")" == "$(grep -v '"generatedAt"' "$PROJECT_ROOT/docs/skill-catalog-data.json")" ]] || log_fail "TEST-3391: docs/skill-catalog-data.json is stale against generate-docs-hub"
  log_pass "TEST-3391: the skill is a retirement notice in the prompt, four wrappers, two indexes and the catalog"
}

# stale_names <newline list of tracked files> <root>: tracked files outside the allowed set that name a retired script file.
stale_names() {
  node -e '
    const fs = require("fs");
    const [list, root] = process.argv.slice(1);
    const re = /aai-canonicalize\.(sh|ps1)|migrate-yaml-to-jsonl\.(sh|ps1)/;
    const allowed = new Set([".aai/scripts/aai-canonicalize.sh", ".aai/scripts/aai-canonicalize.ps1", ".aai/scripts/migrate-yaml-to-jsonl.sh", ".aai/scripts/migrate-yaml-to-jsonl.ps1", ".aai/system/PROFILES.yaml"]);
    const keepDocs = new Set(["docs/USER_GUIDE.md", "docs/SKILL_CATALOG.html", "docs/skill-catalog-data.json"]);
    const out = [];
    for (const f of list.split("\n").filter(Boolean)) {
      if ((f.startsWith("docs/") && !keepDocs.has(f)) || f.startsWith("tests/") || f === "CHANGELOG.md" || allowed.has(f)) continue;
      let t; try { t = fs.readFileSync(root + "/" + f, "utf8"); } catch { continue; }
      if (re.test(t)) out.push(f);
    }
    process.stdout.write(out.join(" "));
  ' "$1" "$2"
}

test_3392_no_stale_instruction() {
  local files out f
  files="$(git -C "$PROJECT_ROOT" ls-files)"
  out="$(stale_names "$files" "$PROJECT_ROOT")"
  [[ -z "$out" ]] || log_fail "TEST-3392: tracked files still name a retired script: $out"
  printf 'see aai-canonicalize.sh\n' > "$TEST_DIR/fixture-extra.md"
  out="$(stale_names "$files"$'\n'"fixture-extra.md" "$TEST_DIR" 2>/dev/null || true)"
  [[ "$out" == *fixture-extra.md* ]] || log_fail "TEST-3392: positive control: a fixture file naming a retired script was not reported"
  for f in SKILLS.md .aai/AGENTS.md docs/USER_GUIDE.md; do
    out="$(grep -nE 'aai-canonicalize|SKILL_CANONICALIZE' "$PROJECT_ROOT/$f" | grep -vi 'retired' || true)"
    [[ -z "$out" ]] || log_fail "TEST-3392: $f has lines naming the skill without 'retired': $out"
  done
  if grep -qE 'codex --prompt-file .aai/SKILL_CANONICALIZE|Use SKILL_CANONICALIZE' "$PROJECT_ROOT/.aai/AGENTS.md"; then
    log_fail "TEST-3392: AGENTS.md still holds a codex prompt-file line or a Use SKILL_CANONICALIZE line"
  fi
  log_pass "TEST-3392: no tracked instruction names a retired script and every doc line about the skill says retired"
}

# copy_tracked <dest>: the repository's tracked files (working-tree content) copied to <dest>.
copy_tracked() {
  mkdir -p "$1"
  git -C "$PROJECT_ROOT" ls-files -z | tar -C "$PROJECT_ROOT" --null -T - -cf - | tar -C "$1" -xf -
}

# prune_source <dest>: a scratch source copy without the retired prompt and wrappers.
prune_source() {
  local t
  copy_tracked "$1"
  rm -f "$1/.aai/SKILL_CANONICALIZE.prompt.md"
  for t in $WRAPPER_TREES; do rm -rf "$1/$t/aai-canonicalize"; done
}

# require_clause <TEST id>: the repository wrapper carries the D4 retirement clause.
require_clause() {
  local out
  out="$(wrapper_problems "$PROJECT_ROOT/.claude/skills/aai-canonicalize/SKILL.md")"
  [[ -z "$out" ]] || log_fail "$1: the wrapper lacks the D4 retirement clause: $out"
}

# prune_case <TEST id> <engine sh|ps1>
prune_case() {
  local id="$1" engine="$2" src="$TEST_DIR/prune-src-$2" dst keep out tree n
  require_clause "$id"
  prune_source "$src"
  dst="$TEST_DIR/prune-dst-$engine"; keep="$TEST_DIR/prune-keep-$engine"
  for tree in .claude/skills .agents/skills; do
    mkdir -p "$dst/$tree/aai-canonicalize"
    cp "$PROJECT_ROOT/.claude/skills/aai-canonicalize/SKILL.md" "$dst/$tree/aai-canonicalize/SKILL.md"
  done
  if [[ "$engine" == ps1 ]]; then
    out="$(pwsh -NoProfile -File "$src/.aai/scripts/aai-sync.ps1" -TargetRoot "$dst" 2>&1)" || { printf '%s\n' "$out" | tail -n 15 >&2; log_fail "$id: aai-sync.ps1 from the stripped source failed"; }
  else
    out="$(bash "$src/.aai/scripts/aai-sync.sh" "$dst" 2>&1)" || { printf '%s\n' "$out" | tail -n 15 >&2; log_fail "$id: aai-sync.sh from the stripped source failed"; }
  fi
  for tree in .claude/skills .agents/skills; do
    [[ ! -e "$dst/$tree/aai-canonicalize" ]] || log_fail "$id: $tree/aai-canonicalize survived the prune"
    n="$(printf '%s\n' "$out" | grep -cxE "[[:space:]]*CLEAN removed retired skill wrapper: $tree/aai-canonicalize" || true)"
    [[ "$n" == 1 ]] || log_fail "$id: $n CLEAN lines for $tree/aai-canonicalize, expected 1"
  done
  mkdir -p "$keep"
  if [[ "$engine" == ps1 ]]; then
    pwsh -NoProfile -File "$PROJECT_ROOT/.aai/scripts/aai-sync.ps1" -TargetRoot "$keep" >/dev/null 2>&1 || log_fail "$id: aai-sync.ps1 from the unchanged source failed"
  else
    bash "$PROJECT_ROOT/.aai/scripts/aai-sync.sh" "$keep" >/dev/null 2>&1 || log_fail "$id: aai-sync.sh from the unchanged source failed"
  fi
  for tree in .claude/skills .agents/skills; do
    [[ -f "$keep/$tree/aai-canonicalize/SKILL.md" ]] || log_fail "$id: the unchanged source dropped $tree/aai-canonicalize"
  done
}

test_3393_prune_sh() {
  prune_case TEST-3393 sh
  log_pass "TEST-3393: aai-sync.sh removes both retired wrapper copies once and keeps them from the unchanged source"
}

test_3394_prune_ps1() {
  need_tool TEST-3394 pwsh || return 0
  prune_case TEST-3394 ps1
  log_pass "TEST-3394: aai-sync.ps1 removes both retired wrapper copies once and keeps them from the unchanged source"
}

test_3395_downstream_install() {
  local core="$TEST_DIR/core target" ext="$TEST_DIR/ext target" src="${AAI_LM_SYNC_SRC:-$PROJECT_ROOT}" f out rc sh tracked p so="$TEST_DIR/i.out" se="$TEST_DIR/i.err"
  mkdir -p "$core" "$ext"
  make_legacy "$core"
  bash "$src/.aai/scripts/aai-sync.sh" "$core" --profile core >/dev/null 2>&1 || log_fail "TEST-3395: aai-sync.sh --profile core failed"
  for f in migrate-state-to-local.sh migrate-state-to-local.ps1 migrate-state-to-local.mjs; do
    [[ -f "$core/.aai/scripts/$f" ]] || log_fail "TEST-3395: the core install lacks .aai/scripts/$f"
  done
  git -C "$core" add -A
  git -C "$core" commit -q -m "sync" || log_fail "TEST-3395: committing the synced target failed"
  rc=0; ( cd "$core" && bash .aai/scripts/migrate-state-to-local.sh ) >"$so" 2>&1 || rc=$?
  [[ "$rc" == 0 ]] || { cat "$so" >&2; log_fail "TEST-3395: the target's own launcher exited $rc"; }
  tracked="$(git -C "$core" ls-files)"
  for f in docs/ai/STATE.yaml docs/ai/LOOP_TICKS.jsonl docs/ai/tdd/x/red.log docs/ai/loop/a.txt; do
    if grep -qxF "$f" <<< "$tracked"; then log_fail "TEST-3395: $f is still tracked after the target's own launcher"; fi
    [[ -f "$core/$f" ]] || log_fail "TEST-3395: $f is gone from disk"
  done
  grep -qxF 'docs/ai/tdd/.gitkeep' <<< "$tracked" || log_fail "TEST-3395: docs/ai/tdd/.gitkeep is no longer tracked"
  for p in 'docs/ai/STATE.yaml' 'docs/ai/LOOP_TICKS.jsonl' 'docs/ai/tdd/**' 'docs/ai/validation/**' '!docs/ai/tdd/' '!docs/ai/tdd/.gitkeep' 'docs/ai/loop/' 'docs/ai/locks/' 'docs/ai/hitl-channel.json' 'docs/ai/briefs/**' 'docs/ai/reports/**' 'docs/ai/friction/**' 'docs/ai/archive/**' 'docs/ai/.session-context.md' 'docs/ai/.pre-compact-state-backup.yaml' 'docs/INDEX.audit.md'; do
    grep -qxF -- "$p" "$core/.gitignore" || log_fail "TEST-3395: the target .gitignore lacks $p"
  done
  [[ -f "$core/docs/ai/EVENTS.jsonl" ]] || log_fail "TEST-3395: docs/ai/EVENTS.jsonl is missing"
  git -C "$core" add .gitignore docs/ai/EVENTS.jsonl
  git -C "$core" commit -q -m migrate || log_fail "TEST-3395: committing the migration failed"
  [[ -z "$(git -C "$core" status --porcelain)" ]] || log_fail "TEST-3395: the target is not clean after the next-step commit"
  bash "$src/.aai/scripts/aai-sync.sh" "$ext" --profile extended >/dev/null 2>&1 || log_fail "TEST-3395: aai-sync.sh --profile extended failed"
  for f in aai-canonicalize migrate-yaml-to-jsonl; do
    p="$CANON_LINE"; [[ "$f" == migrate-yaml-to-jsonl ]] && p="$YAML_LINE"
    for sh in bash; do
      rc=0; ( cd "$ext" && "$sh" ".aai/scripts/$f.sh" ) >"$so" 2>"$se" || rc=$?
      [[ "$rc" == 1 && ! -s "$so" && "$(cat "$se")" == "$p" ]] || log_fail "TEST-3395: the extended target's $f.sh gave rc=$rc stderr=$(cat "$se")"
    done
    if need_tool TEST-3395 pwsh; then
      rc=0; ( cd "$ext" && pwsh -NoProfile -File ".aai/scripts/$f.ps1" ) >"$so" 2>"$se" || rc=$?
      [[ "$rc" == 1 && ! -s "$so" && "$(cat "$se")" == "$p" ]] || log_fail "TEST-3395: the extended target's $f.ps1 gave rc=$rc stderr=$(cat "$se")"
    fi
  done
  log_pass "TEST-3395: a core install carries and runs the migrate-state launchers, an extended install carries the four retirement launchers"
}

test_3397_wiring() {
  local wf="$PROJECT_ROOT/.github/workflows/ps1-quality.yml" n out id base="$PROJECT_ROOT/tests/skills/lib/cd-subshell-leak-baseline.tsv"
  n="$(awk '/^core:/{f=1;next} /^[a-z]/{f=0} f && $0=="  - .aai/scripts/migrate-state-to-local.mjs"{c++} END{print c+0}' "$PROJECT_ROOT/.aai/system/PROFILES.yaml")"
  [[ "$n" == 1 ]] || log_fail "TEST-3397: PROFILES core lists the module $n times, expected 1"
  env -u AAI_ROLE bash "$PROJECT_ROOT/tests/skills/test-aai-layer-profiles.sh" test_manifest_conformance >/dev/null 2>&1 || log_fail "TEST-3397: test-aai-layer-profiles.sh test_manifest_conformance failed"
  for id in .aai/scripts/migrate-state-to-local.mjs .aai/SKILL_CANONICALIZE.prompt.md; do
    out="$(printf '%s\n' "$id" | node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from - --repo-root "$PROJECT_ROOT")"
    [[ "$out" == *'SELECTED aai-legacy-migrations '* ]] || log_fail "TEST-3397: $id does not select aai-legacy-migrations: $out"
  done
  n="$(awk '/^  push:/{s="push"} /^  pull_request:/{s="pr"} /^  workflow_dispatch/{s=""} s!="" && $0=="      - '"'"'.aai/scripts/migrate-state-to-local.mjs'"'"'"{c[s]++} END{print c["push"]+0, c["pr"]+0}' "$wf")"
  [[ "$n" == "1 1" ]] || log_fail "TEST-3397: the ps1-quality path lists hold the module '$n' times (push pr), expected 1 1"
  for id in test_034 test_035 test_036; do
    env -u AAI_ROLE bash "$PROJECT_ROOT/tests/skills/test-aai-win-fallback.sh" "$id" >/dev/null 2>&1 || log_fail "TEST-3397: test-aai-win-fallback.sh $id failed"
  done
  node "$PROJECT_ROOT/.aai/scripts/check-cd-subshell-leak.mjs" >/dev/null 2>&1 || log_fail "TEST-3397: check-cd-subshell-leak.mjs failed"
  if awk -F'\t' '$2 ~ /(aai-canonicalize|migrate-yaml-to-jsonl)\.sh$/ {f=1} END{exit f?0:1}' "$base"; then
    log_fail "TEST-3397: the cd-subshell baseline still has a row for a retired launcher"
  fi
  log_pass "TEST-3397: PROFILES, the suite map, both ps1-quality path lists and the cd-subshell baseline are wired"
}

test_3398_diet() {
  local ledger="${AAI_LM_LEDGER:-$PROJECT_ROOT/tests/skills/lib/prompt-diet-ledger.sh}" n amount size want out later pin rc=0
  n="$(grep -c 'retire-legacy-migrations' "$ledger" || true)"
  [[ "$n" == 1 ]] || log_fail "TEST-3398: $n ledger lines name retire-legacy-migrations, expected exactly 1"
  amount="$(sed -n 's/^JUSTIFIED_ADDITIONS+=( "-\([0-9][0-9]*\) retire-legacy-migrations .*/\1/p' "$ledger")"
  size="$(wc -c < "$CANON_PROMPT" | tr -d ' ')"
  want=$((1950 - size))
  [[ "$amount" == "$want" ]] || log_fail "TEST-3398: the ledger amount is -$amount, expected -$want (1950 minus $size)"
  out="$(env -u AAI_ROLE bash "$PROJECT_ROOT/tests/skills/test-aai-prompt-diet.sh" test_010_audit_and_reduction 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" | tail -n 15 >&2; log_fail "TEST-3398: test-aai-prompt-diet.sh test_010 exited $rc"; }
  out="$out"$'\n'"$(env -u AAI_ROLE bash "$PROJECT_ROOT/tests/skills/test-aai-prompt-diet.sh" test_012_growth_sum_matches_ledger 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" | tail -n 15 >&2; log_fail "TEST-3398: test-aai-prompt-diet.sh test_012 exited $rc"; }
  [[ "$out" == *'headroom 0/2048'* ]] || log_fail "TEST-3398: TEST-010 headroom is not 0/2048"
  later="$(awk -v pat='retire-legacy-migrations' 'index($0,pat){f=1;next} f && /^JUSTIFIED_ADDITIONS\+=\( "-?[0-9]+ /{s=$0; sub(/^JUSTIFIED_ADDITIONS\+=\( "/,"",s); sub(/ .*/,"",s); t+=s} END{print t+0}' "$ledger")"
  pin=$((65792 - want + later))
  [[ "$out" == *"JUSTIFIED_GROWTH_BYTES == $pin =="* ]] || log_fail "TEST-3398: the TEST-012 pin is not $pin"
  log_pass "TEST-3398: one negative ledger entry equal to the prompt shrink ($want B), headroom 0/2048, TEST-012 pin $pin (65792 - $want plus $later from later entries)"
}

RFC17="${AAI_LM_RFC:-$PROJECT_ROOT/docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md}"
D6_SENTENCE='The fifth slice [retired the legacy migrations](../issues/CHANGE-0245-retire-legacy-migrations.md): aai-canonicalize with its skill and migrate-yaml-to-jsonl became deprecation launchers for one release, and migrate-state-to-local moved to one Node module with thin launchers.'

test_3399_rfc() {
  local row n out rc=0 name
  out="$(env -u AAI_ROLE bash "$PROJECT_ROOT/tests/skills/test-aai-expert-fetch.sh" test_2624_inventory_matches_tree 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" | tail -n 10 >&2; log_fail "TEST-3399: test_2624_inventory_matches_tree exited $rc"; }
  n="$(grep -c '^| `migrate-state-to-local` |' "$RFC17" || true)"
  [[ "$n" == 0 ]] || log_fail "TEST-3399: the inventory still has a migrate-state-to-local row"
  for name in aai-canonicalize migrate-yaml-to-jsonl; do
    row="$(grep "^| \`$name\` |" "$RFC17" || true)"
    [[ -n "$row" ]] || log_fail "TEST-3399: the inventory has no $name row"
    [[ "$row" == *'retire-legacy-migrations.md)'* && "$row" == *'a deprecation launcher for one release, deleted in the next'* ]] || log_fail "TEST-3399: the $name row lacks the D6 reason and link"
    [[ "$row" == *'| later candidate |'* ]] || log_fail "TEST-3399: the $name row lost its later candidate destination"
  done
  row="$(grep '^| 5 | ' "$RFC17" || true)"
  [[ "$row" == *'| in progress |'* ]] || log_fail "TEST-3399: the phase 5 row is not in progress"
  [[ "$row" == *"$D6_SENTENCE"* ]] || log_fail "TEST-3399: the phase 5 row lacks the D6 sentence"
  n="$(grep -cF -- "$D6_SENTENCE" "$RFC17" || true)"
  [[ "$n" == 1 ]] || log_fail "TEST-3399: the D6 sentence appears $n times, expected once"
  log_pass "TEST-3399: the RFC-0017 inventory equals the tree, the two retired rows carry the D6 reason and the phase 5 row the D6 sentence once"
}

# code_lines <file> <comment prefix: # or //>: non-blank, non-comment lines (the plan's method).
code_lines() {
  local g=grep
  [[ -x /usr/bin/grep ]] && g=/usr/bin/grep
  "$g" -cvE "^[[:space:]]*($2|\$)" "$1" || true
}

test_3400_line_budget() {
  local d="${AAI_LM_BUDGET_DIR:-$PROJECT_ROOT/.aai/scripts}" f n sum=0 total
  for f in aai-canonicalize.sh aai-canonicalize.ps1 migrate-yaml-to-jsonl.sh migrate-yaml-to-jsonl.ps1; do
    n="$(code_lines "$d/$f" '#')"
    [[ "$n" -le 2 ]] || log_fail "TEST-3400: $f has $n code lines, expected at most 2"
    sum=$((sum + n))
  done
  for f in migrate-state-to-local.sh migrate-state-to-local.ps1; do
    n="$(code_lines "$d/$f" '#')"
    [[ "$n" -le 10 ]] || log_fail "TEST-3400: $f has $n code lines, expected at most 10"
    sum=$((sum + n))
  done
  n="$(code_lines "$d/migrate-state-to-local.mjs" '//')"
  [[ "$n" -le 160 ]] || log_fail "TEST-3400: migrate-state-to-local.mjs has $n code lines, expected at most 160"
  sum=$((sum + n))
  total="$(wc -l < "$d/migrate-state-to-local.mjs" | tr -d ' ')"
  [[ "$total" -le 200 ]] || log_fail "TEST-3400: migrate-state-to-local.mjs has $total lines, expected at most 200"
  [[ "$sum" -le 188 ]] || log_fail "TEST-3400: the seven files hold $sum code lines, expected at most 188"
  log_pass "TEST-3400: code lines before 893, after $sum (module $n of 160, $total lines of 200)"
}

test_3401_subdir_target() {
  run_node_tests TEST-3401
  log_pass "TEST-3401: a target below the git top level migrates and leaves the rest of the repository tracked"
}

main() {
  echo "Testing $TEST_NAME (SPEC spec-retire-legacy-migrations TEST-3380..3402)"
  check_deps
  setup_fixture
  test_3380_pure
  test_3381_effects
  test_3382_refusals_dry_run
  test_3383_hostile_names
  test_3384_rm_failure
  test_3385_launchers_thin
  test_3386_refusal_no_node
  test_3387_sh_launcher_e2e
  test_3388_pester
  test_3389_retired_run
  test_3390_retired_thin
  test_3391_skill_notice
  test_3392_no_stale_instruction
  test_3393_prune_sh
  test_3394_prune_ps1
  test_3395_downstream_install
  test_3396_doctor_seam
  test_3397_wiring
  test_3398_diet
  test_3399_rfc
  test_3400_line_budget
  test_3401_subdir_target
  test_3402_refused_name
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
