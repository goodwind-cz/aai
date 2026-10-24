#!/usr/bin/env bash
#
# Test: aai-expert-fetch
# (docs/specs/SPEC-DRAFT-spec-node-first-third-slice.md, TEST-2601..2633)
#
# The expert prompt fetcher is one Node module (.aai/scripts/expert-fetch.mjs)
# plus two thin launchers (expert-fetch.sh, expert-fetch.ps1). Every function
# below runs alone under single-function dispatch:
#   bash tests/skills/test-aai-expert-fetch.sh <function>
# Fixture roots are temporary directories holding copies of the launchers, the
# module and a fixture registry (the real registry plus three D-table experts).
# The stub gh is a script named by AAI_GH_BIN: no test runs a real gh.
#
# bash 3.2 compatible (no ${var^^}, no declare -A).
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-expert-fetch"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EF_SH="$PROJECT_ROOT/.aai/scripts/expert-fetch.sh"
EF_PS1="$PROJECT_ROOT/.aai/scripts/expert-fetch.ps1"
EF_MJS="$PROJECT_ROOT/.aai/scripts/expert-fetch.mjs"
EF_NODE_TEST="$PROJECT_ROOT/tests/skills/lib/expert-fetch.test.mjs"
EF_PESTER="$PROJECT_ROOT/tests/skills/expert-fetch.Tests.ps1"
REAL_REGISTRY="$PROJECT_ROOT/.aai/system/EXPERT_REGISTRY.yaml"
RFC17="$PROJECT_ROOT/docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md"
UNAVAILABLE_LINE="ERROR: expert-fetch needs node (expert-fetch.mjs unavailable)"
NODE_BIN=""
STUB=""
STUB_LOG=""
STUB_PROMPT=""

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
  NODE_BIN="$(command -v node)"
}

# real_path <dir>: the symlink-free absolute path (Node resolves a module by its real path).
real_path() { node -e 'process.stdout.write(require("fs").realpathSync(process.argv[1]))' "$1"; }

setup_fixture() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-expert-test.XXXXXX")"
  TEST_DIR="$(real_path "$TEST_DIR")"
}

# need_tool <TEST id> <tool>: 0 when present; otherwise fail when CI is set, and
# print a named SKIP-CASE line (still 0 after the caller returns) when it is not.
need_tool() {
  command -v "$2" >/dev/null 2>&1 && return 0
  [[ -z "${CI:-}" ]] || log_fail "$1: $2 is required on CI but is not on PATH"
  echo "SKIP-CASE: $1 needs $2, which is not installed here"
  return 1
}

# run_node_tests <TEST id>: the module must exist, the node:test cases that start
# with the id must pass, and zero passing tests is a failure.
run_node_tests() {
  local id="$1" out rc=0
  [[ -f "$EF_MJS" ]] || log_fail "$id: .aai/scripts/expert-fetch.mjs does not exist"
  [[ -f "$EF_NODE_TEST" ]] || log_fail "$id: tests/skills/lib/expert-fetch.test.mjs does not exist"
  out="$(node --test --test-name-pattern "$id" "$EF_NODE_TEST" 2>&1)" || rc=$?
  if [[ "$rc" != 0 ]]; then
    printf '%s\n' "$out" >&2
    log_fail "$id: node --test exited $rc"
  fi
  if [[ ! "$out" =~ pass\ [1-9] ]]; then
    printf '%s\n' "$out" >&2
    log_fail "$id: node --test reported zero passing tests for the pattern"
  fi
}

# write_registry <file>: the real registry plus the three D-table experts.
write_registry() {
  {
    cat "$REAL_REGISTRY"
    printf '  zblocked:\n    path: 09-meta-orchestration/orchestrator.md\n    use_in: [implementation]\n'
    printf '  znouse:\n    path: 02-language-specialists/znouse.md\n'
    printf '  zafter:\n    path: 02-language-specialists/zafter.md\n    use_in: [tdd-green]\n'
  } > "$1"
}

# ensure_stub: the stub gh (logs its arguments, prints base64 of the fixture
# prompt wrapped at 60 columns with LF) and the fixture prompt.
ensure_stub() {
  [[ -n "$STUB" && -f "$STUB" ]] && return 0
  STUB="$TEST_DIR/stub-gh.sh"; STUB_LOG="$TEST_DIR/stub-gh.log"; STUB_PROMPT="$TEST_DIR/stub-prompt.md"
  printf '%s\n' '---' 'name: typescript-pro' 'description: fixture' '---' '# TypeScript Pro' 'Body line one' '---' \
    'Body after dash' 'Never run git push origin main' 'Final line' > "$STUB_PROMPT"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' 'printf "%s\n" "$*" >> "$STUB_LOG"'
    printf '%s\n' 'if [[ "${STUB_FAIL:-}" == 1 ]]; then exit 1; fi'
    printf '%s\n' 'base64 < "$STUB_PROMPT" | tr -d "\n" | fold -w 60'
    printf '%s\n' 'echo'
  } > "$STUB"
  chmod +x "$STUB"
  : > "$STUB_LOG"
}

# expected_clean <file>: the stub prompt after sanitising (the git push line is removed).
expected_clean() { grep -v 'git push' "$STUB_PROMPT" > "$1" || true; }

# mk_bin <name> <tool>...: a directory of symlinks to the named tools; prints its path.
mk_bin() {
  local d="$TEST_DIR/bin-$1" t; shift
  rm -rf "$d"; mkdir -p "$d"
  for t in "$@"; do ln -s "$(command -v "$t")" "$d/$t"; done
  printf '%s' "$d"
}

# mk_root <name>: sets FX to a fixture root holding copies of the launchers and
# the module under .aai/scripts/ and the fixture registry under .aai/system/.
FX=""
mk_root() {
  FX="$TEST_DIR/$1"
  rm -rf "$FX"
  mkdir -p "$FX/.aai/scripts" "$FX/.aai/system"
  local f
  for f in "$EF_SH" "$EF_PS1" "$EF_MJS"; do
    [[ ! -f "$f" ]] || cp "$f" "$FX/.aai/scripts/" || log_fail "fixture $1: cannot copy $f"
  done
  write_registry "$FX/.aai/system/EXPERT_REGISTRY.yaml"
}

pinned_sha() { sed -n 's/^  pinned_sha: "\(.*\)"$/\1/p;/^  pinned_sha:/q' "$REAL_REGISTRY"; }
key_count() { grep -cE '^  [a-z][a-z0-9_-]*:[[:space:]]*$' "$1" || true; }

# ======================= TEST-2601..2610 (module, node:test) ===================
test_2601_registry_parse() { run_node_tests TEST-2601; log_pass "TEST-2601: parseRegistry matches an independent count, CRLF and BOM copies parse alike"; }
test_2602_detect() { run_node_tests TEST-2602; log_pass "TEST-2602: detect maps the old table, matches registry keys literally, empty is code 0"; }
test_2603_check_phase() { run_node_tests TEST-2603; log_pass "TEST-2603: checkPhase reads only the named block and compares the key literally"; }
test_2604_blocked_category() { run_node_tests TEST-2604; log_pass "TEST-2604: a blocked category exits 1 before any gh call"; }
test_2605_size_limit() { run_node_tests TEST-2605; log_pass "TEST-2605: the size limit counts UTF-8 bytes and defaults to 8192"; }
test_2606_injection_and_strip() { run_node_tests TEST-2606; log_pass "TEST-2606: injection patterns reject, dangerous lines strip, case-insensitively"; }
test_2607_fetch_and_cache() { run_node_tests TEST-2607; log_pass "TEST-2607: fetch decodes, writes the cache and SHA file, serves hits, honours --force"; }
test_2608_fetch_failures() { run_node_tests TEST-2608; log_pass "TEST-2608: gh failures leave the cache untouched and exit 1"; }
test_2609_exit_codes() { run_node_tests TEST-2609; log_pass "TEST-2609: unknown key 2, usage 1, missing registry 1, invalid registry 1"; }
test_2610_body() { run_node_tests TEST-2610; log_pass "TEST-2610: --body prints the lines after the second dash line"; }
test_2627_blocked_list_spellings() { run_node_tests TEST-2627; log_pass "TEST-2627: every blocked-list spelling blocks, and the real registry parse is unchanged"; }
test_2628_blocked_list_fails_closed() { run_node_tests TEST-2628; log_pass "TEST-2628: a heading with no readable item refuses and never calls gh"; }
test_2629_body_blocked_check() { run_node_tests TEST-2629; log_pass "TEST-2629: --body refuses a blocked expert and a malformed list"; }
test_2631_cache_write_failure_cleans_up() { run_node_tests TEST-2631; log_pass "TEST-2631: a failed cache write removes its temporary file"; }
test_2632_cache_write_failure_shapes() { run_node_tests TEST-2632; log_pass "TEST-2632: a file or directory in the cache path gives one clean Cannot-write line"; }
test_2634_body_key_guard_planted() { run_node_tests TEST-2634; log_pass "TEST-2634: --body refuses a non-plain key although the file it names exists"; }
test_2635_body_case_variant_blocked() { run_node_tests TEST-2635; log_pass "TEST-2635: --body refuses a case variant of a blocked key although its file is cached"; }
test_2633_blocked_list_residual_shapes() { run_node_tests TEST-2633; log_pass "TEST-2633: duplicate headings, empty items and stray lines keep the blocked list fail closed"; }

# ======================= TEST-2611..2612 (module CLI) ==========================
test_2611_cli_with_stub_gh() {
  [[ -f "$EF_MJS" ]] || log_fail "TEST-2611: .aai/scripts/expert-fetch.mjs does not exist"
  ensure_stub; mk_root t2611
  local bin rc=0 out sha want expected
  bin="$(mk_bin nogh bash env base64 fold tr)"
  PATH="$bin" "$bin/bash" -c 'command -v gh >/dev/null 2>&1' || rc=$?
  [[ "$rc" != 0 ]] || log_fail "TEST-2611: positive control failed, gh still resolves under the test PATH"
  : > "$STUB_LOG"; rc=0
  out="$(PATH="$bin" AAI_GH_BIN="$STUB" STUB_LOG="$STUB_LOG" STUB_PROMPT="$STUB_PROMPT" "$NODE_BIN" "$FX/.aai/scripts/expert-fetch.mjs" typescript 2> "$TEST_DIR/t2611.err")" || rc=$?
  [[ "$rc" == 0 ]] || log_fail "TEST-2611: the CLI exited $rc: $out $(cat "$TEST_DIR/t2611.err")"
  [[ "$out" == "$FX/.aai/cache/experts/typescript.md" ]] || log_fail "TEST-2611: stdout must be exactly the cache path, got: $out"
  [[ ! -s "$TEST_DIR/t2611.err" ]] || log_fail "TEST-2611: stderr must be empty: $(cat "$TEST_DIR/t2611.err")"
  sha="$(pinned_sha)"
  want="api repos/VoltAgent/awesome-claude-code-subagents/contents/categories/02-language-specialists/typescript-pro.md?ref=$sha --jq .content"
  [[ "$(cat "$STUB_LOG")" == "$want" ]] || log_fail "TEST-2611: the stub must receive exactly the pinned contents arguments, got: $(cat "$STUB_LOG")"
  expected="$TEST_DIR/t2611.expected"; expected_clean "$expected"
  cmp -s "$expected" "$FX/.aai/cache/experts/typescript.md" || log_fail "TEST-2611: the cache file is not the sanitized prompt"
  log_pass "TEST-2611: the module CLI fetches through AAI_GH_BIN with exactly the pinned arguments"
}

# import_pin_bad <file>: prints one reason per violation of the stdin and import pins (whole-source scan, any line shape).
import_pin_bad() {
  node -e '
    const s = require("fs").readFileSync(process.argv[1], "utf8");
    const bad = ["readFileSync(0", "process.stdin", "/dev/stdin", "/dev/fd/0", "require("].filter((t) => s.includes(t));
    const want = ["node:child_process", "node:fs", "node:path", "node:url"];
    if (/\bimport\s*\(/.test(s)) bad.push("dynamic import(");
    const mods = [...s.matchAll(/\bfrom\s*([\x27"])([^\x27"]*)\1/g), ...s.matchAll(/\bimport\s*([\x27"])([^\x27"]*)\1/g)].map((m) => m[2]).sort();
    if (mods.join() !== want.join()) bad.push("node imports " + mods.join(" ") + ", want " + want.join(" "));
    const fsNames = [...s.matchAll(/\bimport\s*\{([^}]*)\}\s*from\s*\x27node:fs\x27/g)].map((m) => m[1].split(",").map((n) => n.trim()).filter(Boolean).sort().join(" "));
    const wantFs = "existsSync mkdirSync readFileSync realpathSync renameSync rmSync writeFileSync";
    if (fsNames.join("|") !== wantFs) bad.push("node:fs names " + fsNames.join("|") + ", want " + wantFs);
    process.stdout.write(bad.join(", "));
  ' "$1"
}

test_2612_no_stdin_and_write_set() {
  [[ -f "$EF_MJS" ]] || log_fail "TEST-2612: .aai/scripts/expert-fetch.mjs does not exist"
  local bad rc=0
  bad="$(import_pin_bad "$EF_MJS")"
  [[ -z "$bad" ]] || log_fail "TEST-2612: the module source can read standard input or imports more than the pinned set: $bad"
  # The pin must bite on every import line shape (review r3 NB-2): each mutated copy has to be flagged.
  local shape ms
  ms="$TEST_DIR/t2612.mut.mjs"
  for shape in "import 'node:net';" "import net from 'node:net'" "import {
  connect } from 'node:net';" "export { connect } from 'node:net';" "export * from 'node:net'" "const n = await import ('node:net');" "const m = await import('node:net');" "import
  ('node:net');"; do
    { printf '%s\n' "$shape"; cat "$EF_MJS"; } > "$ms"
    [[ -n "$(import_pin_bad "$ms")" ]] || log_fail "TEST-2612: the import pin missed this shape: $shape"
  done
  ensure_stub; mk_root t2612
  local before="$TEST_DIR/t2612.before" after="$TEST_DIR/t2612.after"
  find "$FX" -type f | sort > "$before"
  AAI_GH_BIN="$STUB" STUB_LOG="$STUB_LOG" STUB_PROMPT="$STUB_PROMPT" "$NODE_BIN" "$FX/.aai/scripts/expert-fetch.mjs" typescript > "$TEST_DIR/t2612.out" 2>&1 < /dev/null || rc=$?
  [[ "$rc" == 0 ]] || log_fail "TEST-2612: positive control failed, the fetch must exit 0 (rc=$rc: $(cat "$TEST_DIR/t2612.out"))"
  find "$FX" -type f | sort > "$after"
  local added; added="$(comm -13 "$before" "$after" | sed "s|^$FX/||" | tr '\n' ' ')"
  [[ "$added" == ".aai/cache/experts/.sha_typescript .aai/cache/experts/typescript.md " ]] || log_fail "TEST-2612: a fetch must add exactly the two cache files, added: $added"
  [[ -z "$(comm -23 "$before" "$after")" ]] || log_fail "TEST-2612: a fetch must remove no file"
  log_pass "TEST-2612: the module imports only the pinned node:* set, never reads standard input, and a fetch writes only the two cache files"
}

# TEST-2630: the bash launcher fails closed on blocked-list spellings and a malformed list.
test_2630_launcher_blocked_list() {
  [[ -f "$EF_MJS" ]] || log_fail "TEST-2630: .aai/scripts/expert-fetch.mjs does not exist"
  ensure_stub; mk_root t2630
  local reg="$FX/.aai/system/EXPERT_REGISTRY.yaml" real="$TEST_DIR/t2630.real" case_name rc out heading
  cp "$reg" "$real"
  for case_name in comment-heading comment-line quoted empty; do
    case "$case_name" in
      comment-heading) heading=$'blocked_categories:   # policy\n  - 09-meta-orchestration\n  - 08-business-product' ;;
      comment-line) heading=$'blocked_categories:\n  # AAI policy\n\n    - 09-meta-orchestration\n    - 08-business-product' ;;
      quoted) heading=$'blocked_categories:\n  - "09-meta-orchestration"\n  - \'08-business-product\'' ;;
      empty) heading=$'blocked_categories:\n  # nothing' ;;
    esac
    node -e '
      const fs = require("fs");
      const t = fs.readFileSync(process.argv[1], "utf8").replace(/blocked_categories:[\s\S]*?\n\n/, () => process.argv[3] + "\n\n");
      fs.writeFileSync(process.argv[2], t);
    ' "$real" "$reg" "$heading" || log_fail "TEST-2630: cannot write the $case_name registry"
    : > "$STUB_LOG"; rc=0
    if [[ "$case_name" == empty ]]; then
      out="$(AAI_GH_BIN="$STUB" STUB_LOG="$STUB_LOG" STUB_PROMPT="$STUB_PROMPT" bash "$FX/.aai/scripts/expert-fetch.sh" typescript 2>&1)" || rc=$?
      [[ "$rc" == 1 ]] || log_fail "TEST-2630: $case_name: a malformed list must exit 1, got $rc: $out"
      [[ "$out" == "ERROR: blocked_categories in the registry has no readable item; refusing to serve experts" ]] || log_fail "TEST-2630: $case_name: wrong message: $out"
    else
      out="$(AAI_GH_BIN="$STUB" STUB_LOG="$STUB_LOG" STUB_PROMPT="$STUB_PROMPT" bash "$FX/.aai/scripts/expert-fetch.sh" zblocked 2>&1)" || rc=$?
      [[ "$rc" == 1 ]] || log_fail "TEST-2630: $case_name: a blocked expert must exit 1, got $rc: $out"
      [[ "$out" == "ERROR: Category '09-meta-orchestration' is blocked in registry" ]] || log_fail "TEST-2630: $case_name: wrong message: $out"
    fi
    [[ ! -s "$STUB_LOG" ]] || log_fail "TEST-2630: $case_name: gh must never run, the stub log holds: $(cat "$STUB_LOG")"
  done
  # D-22 through the launcher: a real file planted above the experts directory must never be printed.
  cp "$real" "$reg"
  printf 'PLANTED-SECRET\n' > "$FX/.aai/cache/x.md" 2>/dev/null || { mkdir -p "$FX/.aai/cache"; printf 'PLANTED-SECRET\n' > "$FX/.aai/cache/x.md"; }
  rc=0; out="$(AAI_GH_BIN="$STUB" STUB_LOG="$STUB_LOG" bash "$FX/.aai/scripts/expert-fetch.sh" --body ../x 2>/dev/null)" || rc=$?
  [[ "$rc" == 1 && -z "$out" ]] || log_fail "TEST-2630: --body ../x must exit 1 with empty stdout, got $rc: $out"
  out="$(AAI_GH_BIN="$STUB" STUB_LOG="$STUB_LOG" bash "$FX/.aai/scripts/expert-fetch.sh" --body ../x 2>&1 >/dev/null)" || true
  [[ "$out" == "ERROR: Expert '../x' not cached. Run expert-fetch.sh ../x first." ]] || log_fail "TEST-2630: wrong --body ../x refusal: $out"
  # case and dot variants with a cached file of their own: only the key guard can refuse them (review r4 NB-2).
  mkdir -p "$FX/.aai/cache/experts"
  local variant
  for variant in Zblocked type.script; do
    printf 'PLANTED-SECRET\n' > "$FX/.aai/cache/experts/$variant.md"
    rc=0; out="$(AAI_GH_BIN="$STUB" STUB_LOG="$STUB_LOG" bash "$FX/.aai/scripts/expert-fetch.sh" --body "$variant" 2>/dev/null)" || rc=$?
    [[ "$rc" == 1 && -z "$out" ]] || log_fail "TEST-2630: --body $variant must exit 1 with empty stdout, got $rc: $out"
  done
  log_pass "TEST-2630: the launcher refuses a blocked expert for every list spelling and a malformed list, with gh never called"
}

# ======================= TEST-2613..2615 (launchers) ===========================
# launcher_check <file> <max lines>: prints one reason per violated rule (empty when thin).
launcher_check() {
  node -e '
    const fs = require("fs");
    const buf = fs.readFileSync(process.argv[1]);
    const text = buf.toString("latin1");
    const bad = [];
    if (buf.some((b) => b > 0x7e)) bad.push("non-ASCII byte");
    const lines = text.split("\n"); if (lines[lines.length - 1] === "") lines.pop();
    if (lines.length > Number(process.argv[2])) bad.push("more than " + process.argv[2] + " lines (" + lines.length + ")");
    if (!text.includes("expert-fetch.mjs")) bad.push("no reference to expert-fetch.mjs");
    for (const t of ["awk", "sed", "base64", "gh api", "blocked_categories", "use_in", "pinned_sha", "REJECTED", "previous",
      "Select-String", "FromBase64String", "Set-Content"]) {
      if (text.includes(t)) bad.push("logic token " + t);
    }
    const n = text.split("ERROR: expert-fetch needs node (expert-fetch.mjs unavailable)").length - 1;
    if (n !== 1) bad.push("D-18 literal appears " + n + " times");
    process.stdout.write(bad.join("; "));
  ' "$1" "$2"
}

test_2613_launchers_thin() {
  local bad
  bad="$(launcher_check "$EF_SH" 10)"
  [[ -z "$bad" ]] || log_fail "TEST-2613: expert-fetch.sh is not a thin launcher: $bad"
  bad="$(launcher_check "$EF_PS1" 20)"
  [[ -z "$bad" ]] || log_fail "TEST-2613: expert-fetch.ps1 is not a thin launcher: $bad"
  log_pass "TEST-2613: both launchers are ASCII, short, logic-free and call the module"
}

test_2614_sh_launcher_without_node() {
  local bin rc out
  bin="$(mk_bin nonode bash dirname)"
  rc=0; PATH="$bin" "$bin/bash" -c 'command -v node >/dev/null 2>&1' || rc=$?
  [[ "$rc" != 0 ]] || log_fail "TEST-2614: positive control failed, node still resolves under the test PATH"
  mk_root t2614
  rc=0; out="$(PATH="$bin" "$bin/bash" "$FX/.aai/scripts/expert-fetch.sh" --list 2> "$TEST_DIR/t2614.err")" || rc=$?
  [[ "$rc" == 1 ]] || log_fail "TEST-2614: without node the launcher must exit 1, got $rc"
  [[ -z "$out" ]] || log_fail "TEST-2614: without node stdout must be empty, got: $out"
  [[ "$(cat "$TEST_DIR/t2614.err")" == "$UNAVAILABLE_LINE" ]] || log_fail "TEST-2614: stderr must be exactly the D-18 line, got: $(cat "$TEST_DIR/t2614.err")"
  command -v node >/dev/null 2>&1 || log_fail "TEST-2614: positive control failed, node must resolve on the real PATH"
  mkdir -p "$TEST_DIR/t2614-nomod"
  cp "$EF_SH" "$TEST_DIR/t2614-nomod/expert-fetch.sh" || log_fail "TEST-2614: cannot copy the launcher"
  rc=0; out="$(bash "$TEST_DIR/t2614-nomod/expert-fetch.sh" --list 2> "$TEST_DIR/t2614.err")" || rc=$?
  [[ "$rc" == 1 && -z "$out" ]] || log_fail "TEST-2614: without the module the launcher must exit 1 with empty stdout (rc=$rc out=$out)"
  [[ "$(cat "$TEST_DIR/t2614.err")" == "$UNAVAILABLE_LINE" ]] || log_fail "TEST-2614: without the module stderr must be exactly the D-18 line, got: $(cat "$TEST_DIR/t2614.err")"
  log_pass "TEST-2614: expert-fetch.sh prints the D-18 line and exits 1 without node or module"
}

# ps_run <fixture> <args...>: runs the ps1 launcher under pwsh -File; sets PS_OUT, PS_ERR, PS_RC.
PS_OUT=""; PS_ERR=""; PS_RC=0
ps_run() {
  local fx="$1"; shift
  PS_RC=0
  PS_OUT="$(pwsh -NoProfile -File "$fx/.aai/scripts/expert-fetch.ps1" "$@" 2> "$TEST_DIR/ps.err")" || PS_RC=$?
  PS_ERR="$(cat "$TEST_DIR/ps.err")"
}

ps_expect() { # <label> <want rc> <want stdout> ; uses PS_*
  [[ "$PS_RC" == "$2" ]] || log_fail "TEST-2615: $1 must exit $2, got $PS_RC (out=$PS_OUT err=$PS_ERR)"
  [[ "$PS_OUT" == "$3" ]] || log_fail "TEST-2615: $1 stdout must be '$3', got: $PS_OUT (err=$PS_ERR)"
}

test_2615_ps1_launcher_mapping_and_exit() {
  need_tool TEST-2615 pwsh || return 0
  [[ -f "$EF_MJS" ]] || log_fail "TEST-2615: .aai/scripts/expert-fetch.mjs does not exist"
  local bin="$TEST_DIR/t2615-bin" rc out
  rm -rf "$bin"; mkdir -p "$bin"
  ln -s "$(command -v pwsh)" "$bin/pwsh"
  rc=0; PATH="$bin" "$bin/pwsh" -NoProfile -Command 'if (Get-Command node -ErrorAction SilentlyContinue) { exit 1 } else { exit 0 }' || rc=$?
  [[ "$rc" == 0 ]] || log_fail "TEST-2615: positive control failed, node still resolves under the test PATH"
  mk_root t2615
  rc=0; out="$(PATH="$bin" "$bin/pwsh" -NoProfile -File "$FX/.aai/scripts/expert-fetch.ps1" -List 2> "$TEST_DIR/t2615.err")" || rc=$?
  [[ "$rc" == 1 && -z "$out" ]] || log_fail "TEST-2615: without node the launcher must exit 1 with empty stdout (rc=$rc out=$out)"
  [[ "$(cat "$TEST_DIR/t2615.err")" == "$UNAVAILABLE_LINE" ]] || log_fail "TEST-2615: without node stderr must be exactly the D-18 line, got: $(cat "$TEST_DIR/t2615.err")"
  command -v node >/dev/null 2>&1 || log_fail "TEST-2615: positive control failed, node must resolve on the real PATH"
  mkdir -p "$TEST_DIR/t2615-nomod"
  cp "$EF_PS1" "$TEST_DIR/t2615-nomod/expert-fetch.ps1" || log_fail "TEST-2615: cannot copy the launcher"
  rc=0; out="$(pwsh -NoProfile -File "$TEST_DIR/t2615-nomod/expert-fetch.ps1" -List 2> "$TEST_DIR/t2615.err")" || rc=$?
  [[ "$rc" == 1 && -z "$out" ]] || log_fail "TEST-2615: without the module the launcher must exit 1 with empty stdout (rc=$rc out=$out)"
  [[ "$(cat "$TEST_DIR/t2615.err")" == "$UNAVAILABLE_LINE" ]] || log_fail "TEST-2615: without the module stderr must be exactly the D-18 line, got: $(cat "$TEST_DIR/t2615.err")"
  ps_run "$FX" -Detect ts py docker;                       ps_expect "-Detect ts py docker" 0 $'docker\npython'
  ps_run "$FX" -ExpertKey nosuch;                          ps_expect "-ExpertKey nosuch" 2 ""
  ps_run "$FX" nosuch;                                     ps_expect "positional nosuch" 2 ""
  ps_run "$FX" -Check znouse -Phase tdd-green;             ps_expect "-Check znouse -Phase tdd-green" 2 "not-found"
  ps_run "$FX" --check znouse tdd-green;                   ps_expect "--check znouse tdd-green" 2 "not-found"
  ps_run "$FX" -Check typescript -Phase implementation;    ps_expect "-Check typescript -Phase implementation" 0 "eligible"
  ps_run "$FX" -List
  [[ "$PS_RC" == 0 && "$(grep -c . <<<"$PS_OUT")" == "$(key_count "$FX/.aai/system/EXPERT_REGISTRY.yaml")" ]] \
    || log_fail "TEST-2615: -List must print the registry's key count (rc=$PS_RC)"
  ensure_stub
  mkdir -p "$FX/.aai/cache/experts"
  printf '%s\n' '---' 'name: x' '---' 'cached body' > "$FX/.aai/cache/experts/typescript.md"
  ps_run "$FX" -Body typescript;                           ps_expect "-Body typescript" 0 "cached body"
  log_pass "TEST-2615: expert-fetch.ps1 maps its arguments, returns the module exit code and degrades with the D-18 line"
}

# ======================= TEST-2616..2617 (parity, Pester) ======================
# par_one <label> <seed 0|1> <stub-fail 0|1> <sh args> <ps args>: runs one fixture
# through bash expert-fetch.sh and pwsh expert-fetch.ps1 in the same root with a
# clean cache and an empty stub log, and compares stdout, stderr and exit code.
PAR_RC=0
par_one() {
  local label="$1" seed="$2" sfail="$3" shargs="$4" psargs="$5" side rc d="$TEST_DIR/t2616-out"
  mkdir -p "$d"
  for side in sh ps; do
    rm -rf "$FX/.aai/cache"; : > "$STUB_LOG"
    if [[ "$seed" == 1 ]]; then
      mkdir -p "$FX/.aai/cache/experts"
      printf '%s\n' '---' 'name: x' '---' 'cached body' '---' 'dash kept' > "$FX/.aai/cache/experts/typescript.md"
    fi
    rc=0
    if [[ "$side" == sh ]]; then
      # shellcheck disable=SC2086
      env AAI_GH_BIN="$STUB" STUB_LOG="$STUB_LOG" STUB_PROMPT="$STUB_PROMPT" STUB_FAIL="$sfail" \
        bash "$FX/.aai/scripts/expert-fetch.sh" $shargs > "$d/$label.$side.out" 2> "$d/$label.$side.err" || rc=$?
    else
      # shellcheck disable=SC2086
      env AAI_GH_BIN="$STUB" STUB_LOG="$STUB_LOG" STUB_PROMPT="$STUB_PROMPT" STUB_FAIL="$sfail" \
        pwsh -NoProfile -File "$FX/.aai/scripts/expert-fetch.ps1" $psargs > "$d/$label.$side.out" 2> "$d/$label.$side.err" || rc=$?
    fi
    echo "$rc" > "$d/$label.$side.rc"
    if [[ "$label" == fetch-zblocked ]]; then
      [[ ! -s "$STUB_LOG" ]] || log_fail "TEST-2616: $label ($side) must never call the stub gh, log: $(cat "$STUB_LOG")"
    fi
  done
  cmp -s "$d/$label.sh.out" "$d/$label.ps.out" || log_fail "TEST-2616: stdout differs for $label: sh=$(cat "$d/$label.sh.out") ps=$(cat "$d/$label.ps.out")"
  cmp -s "$d/$label.sh.err" "$d/$label.ps.err" || log_fail "TEST-2616: stderr differs for $label: sh=$(cat "$d/$label.sh.err") ps=$(cat "$d/$label.ps.err")"
  cmp -s "$d/$label.sh.rc" "$d/$label.ps.rc" || log_fail "TEST-2616: exit code differs for $label: sh=$(cat "$d/$label.sh.rc") ps=$(cat "$d/$label.ps.rc")"
  PAR_RC="$(cat "$d/$label.sh.rc")"
}

test_2616_launcher_parity() {
  need_tool TEST-2616 pwsh || return 0
  [[ -f "$EF_MJS" ]] || log_fail "TEST-2616: .aai/scripts/expert-fetch.mjs does not exist"
  ensure_stub; mk_root t2616
  par_one list 0 0 "--list" "-List"
  par_one detect-tsx 0 0 "--detect .TSX py docker" "-Detect .TSX py docker"
  par_one detect-none 0 0 "--detect zzzz" "-Detect zzzz"
  par_one check-eligible 0 0 "--check typescript implementation" "-Check typescript -Phase implementation"
  par_one check-znouse 0 0 "--check znouse tdd-green" "-Check znouse -Phase tdd-green"
  [[ "$PAR_RC" == 2 ]] || log_fail "TEST-2616: positive control failed, the znouse case must exit 2 on both sides, got $PAR_RC"
  par_one check-nophase 0 0 "--check typescript nosuchphase" "-Check typescript -Phase nosuchphase"
  par_one fetch-nosuch 0 0 "nosuch" "-ExpertKey nosuch"
  par_one fetch-zblocked 0 0 "zblocked" "-ExpertKey zblocked"
  par_one fetch-typescript 0 0 "typescript" "-ExpertKey typescript"
  par_one body-typescript 1 0 "--body typescript" "-Body typescript"
  par_one fetch-gh-fails 0 1 "typescript" "-ExpertKey typescript"
  [[ "$PAR_RC" == 1 ]] || log_fail "TEST-2616: a failing gh must exit 1 on both sides, got $PAR_RC"
  log_pass "TEST-2616: expert-fetch.sh and expert-fetch.ps1 give identical stdout, stderr and exit codes for eleven fixtures"
}

test_2617_pester_expert_fetch() {
  [[ -f "$EF_PESTER" ]] || log_fail "TEST-2617: tests/skills/expert-fetch.Tests.ps1 does not exist"
  need_tool TEST-2617 pwsh || return 0
  local has out rc=0
  has="$(pwsh -NoProfile -Command 'if (Get-Module Pester -ListAvailable | Where-Object { $_.Version.Major -ge 5 }) { "yes" } else { "no" }' 2>/dev/null || echo no)"
  if [[ "$has" != yes ]]; then
    echo "SKIP-CASE: TEST-2617 needs Pester 5 (the ps1-quality gate job is the authoritative runner)"
    return 0
  fi
  out="$(PESTER_FILE="$EF_PESTER" pwsh -NoProfile -Command '
    $cfg = New-PesterConfiguration
    $cfg.Run.Path = $env:PESTER_FILE
    $cfg.Run.PassThru = $true
    $cfg.Output.Verbosity = "Normal"
    $r = Invoke-Pester -Configuration $cfg
    Write-Host "EXPERT-FETCH-PESTER: Total=$($r.TotalCount) Passed=$($r.PassedCount) Failed=$($r.FailedCount) Skipped=$($r.SkippedCount)"
    if ($r.FailedCount -gt 0 -or $r.SkippedCount -gt 0 -or $r.TotalCount -lt 11) { exit 1 }
    exit 0
  ' 2>&1)" || rc=$?
  if [[ "$rc" != 0 ]]; then
    printf '%s\n' "$out" >&2
    log_fail "TEST-2617: expert-fetch.Tests.ps1 failed, skipped a case or ran fewer than 11 cases (rc=$rc)"
  fi
  log_pass "TEST-2617: expert-fetch.Tests.ps1 passes with no skip ($(printf '%s\n' "$out" | sed -n 's/^EXPERT-FETCH-PESTER: //p'))"
}

# ======================= TEST-2618 (downstream extended install) ===============
test_2618_downstream_extended_sync_runs_expert_fetch() {
  local t="$TEST_DIR/t2618/target dir" c="$TEST_DIR/t2618/core dir" rc out want
  rm -rf "$TEST_DIR/t2618"; mkdir -p "$t" "$c"
  ensure_stub
  git -C "$t" init -q -b main || log_fail "TEST-2618: git init of the extended target failed"
  rc=0; bash "$PROJECT_ROOT/.aai/scripts/aai-sync.sh" "$t" --profile extended > "$TEST_DIR/t2618.sync.log" 2>&1 || rc=$?
  [[ "$rc" == 0 ]] || log_fail "TEST-2618: aai-sync.sh --profile extended exited $rc: $(cat "$TEST_DIR/t2618.sync.log")"
  [[ -f "$t/.aai/scripts/expert-fetch.mjs" ]] || log_fail "TEST-2618: the extended target lacks .aai/scripts/expert-fetch.mjs"
  want="$(key_count "$t/.aai/system/EXPERT_REGISTRY.yaml")"
  [[ "$want" -gt 0 ]] || log_fail "TEST-2618: the target registry holds no keys"
  rc=0; out="$(bash "$t/.aai/scripts/expert-fetch.sh" --list 2> "$TEST_DIR/t2618.err")" || rc=$?
  [[ "$rc" == 0 && "$(grep -c . <<<"$out")" == "$want" ]] || log_fail "TEST-2618: --list must print $want keys in the target (rc=$rc): $(cat "$TEST_DIR/t2618.err")"
  rc=0; out="$(bash "$t/.aai/scripts/expert-fetch.sh" --check typescript implementation 2> "$TEST_DIR/t2618.err")" || rc=$?
  [[ "$rc" == 0 && "$out" == eligible ]] || log_fail "TEST-2618: --check typescript implementation must print eligible (rc=$rc out=$out)"
  rc=0; out="$(AAI_GH_BIN="$STUB" STUB_LOG="$STUB_LOG" STUB_PROMPT="$STUB_PROMPT" bash "$t/.aai/scripts/expert-fetch.sh" typescript 2> "$TEST_DIR/t2618.err")" || rc=$?
  local real_t; real_t="$(real_path "$t")"
  [[ "$rc" == 0 && "$out" == "$real_t/.aai/cache/experts/typescript.md" ]] || log_fail "TEST-2618: the stub fetch must print a path under the target's cache (rc=$rc out=$out): $(cat "$TEST_DIR/t2618.err")"
  [[ -f "$out" ]] || log_fail "TEST-2618: the cache file does not exist: $out"
  git -C "$c" init -q -b main || log_fail "TEST-2618: git init of the core target failed"
  rc=0; bash "$PROJECT_ROOT/.aai/scripts/aai-sync.sh" "$c" --profile core > "$TEST_DIR/t2618.core.log" 2>&1 || rc=$?
  [[ "$rc" == 0 ]] || log_fail "TEST-2618: aai-sync.sh --profile core exited $rc: $(cat "$TEST_DIR/t2618.core.log")"
  local f
  for f in expert-fetch.sh expert-fetch.ps1 expert-fetch.mjs; do
    [[ ! -e "$c/.aai/scripts/$f" ]] || log_fail "TEST-2618: the core target must not hold $f"
  done
  log_pass "TEST-2618: an extended install into a spaced path runs expert-fetch.sh; a core install holds none of the three files"
}

# ======================= TEST-2619..2626 (wiring and records) ==================
test_2620_suite_map_selects_expert_fetch() {
  local p out
  for p in .aai/scripts/expert-fetch.sh .aai/scripts/expert-fetch.ps1 .aai/scripts/expert-fetch.mjs tests/skills/lib/expert-fetch.test.mjs tests/skills/expert-fetch.Tests.ps1; do
    out="$(node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from - <<<"$p")"
    [[ "$out" != *FULL_RUN* ]] || log_fail "TEST-2620: $p gives a FULL_RUN line: $out"
    [[ "$out" == *"SELECTED aai-expert-fetch"* ]] || log_fail "TEST-2620: $p does not select aai-expert-fetch: $out"
  done
  log_pass "TEST-2620: all five suite paths select aai-expert-fetch"
}

test_2621_ps1_quality_filter_has_module() {
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
    const want = "\x27.aai/scripts/expert-fetch.mjs\x27";
    const bad = [];
    for (const k of ["push", "pull_request"]) {
      if (!lists[k] || lists[k].length === 0) bad.push(k + ": no path list");
      else if (!lists[k].includes(want)) bad.push(k + ": lacks the module");
    }
    if (lists.push && lists.pull_request && JSON.stringify(lists.push) !== JSON.stringify(lists.pull_request)) bad.push("lists differ");
    process.stdout.write(bad.join("; "));
  ' "$wf")"
  [[ -z "$out" ]] || log_fail "TEST-2621: ps1-quality.yml path filter: $out"
  log_pass "TEST-2621: both path lists contain the module and are identical"
}

# rfc_phase3_row: the Rollout Status row whose first cell is 3.
rfc_phase3_row() {
  node -e '
    for (const l of require("fs").readFileSync(process.argv[1], "utf8").split("\n")) {
      if (/^\| 3 \|/.test(l)) { process.stdout.write(l); break; }
    }
  ' "$RFC17"
}

test_2622_line_budget_recorded() {
  local row n sum
  row="$(rfc_phase3_row)"
  if [[ "$row" =~ expert-fetch\ pair\ 444\ to\ ([0-9]+)\ lines ]]; then n="${BASH_REMATCH[1]}"; else
    log_fail "TEST-2622: the phase 3 row does not record 'expert-fetch pair 444 to N lines'"
  fi
  [[ -f "$EF_MJS" ]] || log_fail "TEST-2622: .aai/scripts/expert-fetch.mjs does not exist"
  sum="$(cat "$EF_SH" "$EF_PS1" "$EF_MJS" | wc -l | tr -d '[:space:]')"
  [[ "$n" == "$sum" ]] || log_fail "TEST-2622: the row records $n lines but the three files total $sum"
  [[ "$n" -le 230 ]] || log_fail "TEST-2622: N=$n must be at most 230"
  log_pass "TEST-2622: the RFC row records the live line total ($n <= 230)"
}

test_2623_rfc_phase3_done() {
  local out
  out="$(node -e '
    const lines = require("fs").readFileSync(process.argv[1], "utf8").split("\n");
    const cells = (n) => {
      const l = lines.find((x) => new RegExp("^\\| " + n + " \\|").test(x));
      return l === undefined ? null : l.split("|").map((c) => c.trim()).slice(1, -1);
    };
    const bad = [];
    const row = cells("3");
    if (!row) bad.push("no row 3");
    else {
      if (row[1] !== "Migrate common sync/hook behavior to Node in small slices, with native platform parity and retired counterparts") bad.push("description changed");
      if (row[2] !== "done") bad.push("status cell is " + row[2]);
      const d = row[3] || "";
      if (!d.includes("[First Node-first slice](../issues/CHANGE-0222-node-first-sync-hook-slice.md) moved the live-status spool hook (live-spool pair 133 to 116 lines): one Node module and two launchers, tested with `node:test` plus Pester on the native Windows job")) bad.push("first-slice text changed");
      if (!d.includes("the [second slice](../issues/CHANGE-0223-node-first-second-slice.md) moved the L1 triage snapshot (triage pair 140 to 129 lines), a behavior with an exit-code gate and two child processes")) bad.push("second-slice text changed");
      if (!/\]\([^)]*node-first-third-slice\.md\)[^|]*expert-fetch/.test(d)) bad.push("no third-slice link followed by expert-fetch");
    }
    const fm = lines.slice(0, 30).join("\n");
    if (!/^status: implementing$/m.test(fm)) bad.push("RFC status is not implementing");
    if (!/^umbrella: true$/m.test(fm)) bad.push("RFC is not umbrella: true");
    for (const [n, want] of [["0", "in progress"], ["2", "in progress"], ["4", "not started"], ["5", "not started"]]) {
      const c = cells(n);
      if (!c || c[2] !== want) bad.push("row " + n + " status is " + (c ? c[2] : "missing") + ", want " + want);
    }
    process.stdout.write(bad.join("; "));
  ' "$RFC17")"
  [[ -z "$out" ]] || log_fail "TEST-2623: $out"
  log_pass "TEST-2623: RFC-0017 phase 3 is done, earlier slice text is unchanged, the umbrella stays implementing"
}

# inventory_check <rfc> <scripts dir>: prints one problem per line (empty when the table matches the tree).
inventory_check() {
  node -e '
    const fs = require("fs");
    const lines = fs.readFileSync(process.argv[1], "utf8").split("\n");
    const names = fs.readdirSync(process.argv[2]);
    const tree = new Set();
    for (const f of names) {
      const m = /^(.+)\.sh$/.exec(f);
      if (m && names.includes(m[1] + ".ps1") && !names.includes(m[1] + ".mjs")) tree.add(m[1]);
    }
    const bad = [];
    const at = lines.findIndex((l) => l === "### Remaining paired scripts after phase 3");
    if (at < 0) { process.stdout.write("heading not found"); process.exit(0); }
    const rows = [];
    for (let i = at + 1; i < lines.length; i++) {
      if (/^#{1,3} /.test(lines[i])) break;
      if (/^\|/.test(lines[i])) rows.push(lines[i].split("|").map((c) => c.trim()).slice(1, -1));
    }
    const data = rows.filter((r) => r[0] !== "Pair" && !/^-+$/.test(r[0]));
    const listed = new Set();
    const DEST = ["phase 5 process adapter", "platform adapter kept on purpose", "later candidate"];
    const dest = {};
    for (const r of data) {
      const name = r[0].replace(/`/g, "");
      listed.add(name); dest[name] = r[2];
      if (!/^[1-9][0-9]*\/[1-9][0-9]*$/.test(r[1] || "")) bad.push(name + ": Lines cell is not two positive integers: " + r[1]);
      if (!DEST.includes(r[2])) bad.push(name + ": destination is not allowed: " + r[2]);
      if (!r[3]) bad.push(name + ": empty reason");
    }
    const missing = [...tree].filter((n) => !listed.has(n));
    const extra = [...listed].filter((n) => !tree.has(n));
    if (missing.length) bad.push("missing from the table: " + missing.join(", "));
    if (extra.length) bad.push("not a pair in the tree: " + extra.join(", "));
    for (const n of ["aai-run-tests", "aai-reap-tests", "autonomous-loop"]) if (dest[n] !== "phase 5 process adapter") bad.push(n + " must be phase 5 process adapter");
    if (dest["pre-commit-checks"] !== "platform adapter kept on purpose") bad.push("pre-commit-checks must be platform adapter kept on purpose");
    process.stdout.write(bad.join("\n"));
  ' "$1" "$2"
}

test_2624_inventory_matches_tree() {
  local out fx="$TEST_DIR/t2624-tree" n
  out="$(inventory_check "$RFC17" "$PROJECT_ROOT/.aai/scripts")"
  [[ -z "$out" ]] || log_fail "TEST-2624: $out"
  rm -rf "$fx"; mkdir -p "$fx"
  for n in $(ls "$PROJECT_ROOT/.aai/scripts"); do : > "$fx/$n"; done
  : > "$fx/xpair.sh"; : > "$fx/xpair.ps1"
  out="$(inventory_check "$RFC17" "$fx")"
  [[ "$out" == *"missing from the table: xpair"* ]] || log_fail "TEST-2624: positive control failed, an added pair must be reported missing, got: $out"
  log_pass "TEST-2624: the RFC inventory equals the pair set of the tree and fails on an added pair"
}

test_2625_amended_status_checks() {
  local rc=0 out sa="$TEST_DIR/t2625.sa.json"
  out="$(bash "$PROJECT_ROOT/tests/skills/test-aai-live-status.sh" test_2419_rfc_phase3_row 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || log_fail "TEST-2625: test_2419_rfc_phase3_row exited $rc: $out"
  rc=0; out="$(bash "$PROJECT_ROOT/tests/skills/test-aai-triage.sh" test_2518_rfc_phase3_row 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || log_fail "TEST-2625: test_2518_rfc_phase3_row exited $rc: $out"
  node "$PROJECT_ROOT/.aai/scripts/spec-amend.mjs" list --json > "$sa" || log_fail "TEST-2625: spec-amend list failed"
  out="$(node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const bad = [];
    for (const [ref, id] of [["node-first-sync-hook-slice", "TEST-2419"], ["node-first-second-slice", "TEST-2518"]]) {
      const hit = j.items.filter((i) => i.ref_id === ref && i.bucket === "signed" && i.amendment_class === "contract" && String(i.what).startsWith(id));
      if (hit.length < 1) bad.push("no signed contract record of ref " + ref + " whose what begins " + id);
    }
    process.stdout.write(bad.join("; "));
  ' "$sa")"
  [[ -z "$out" ]] || log_fail "TEST-2625: $out"
  log_pass "TEST-2625: the amended status checks pass and both amendment records are signed"
}

test_2626_496_amendments_signed() {
  local sa="$TEST_DIR/t2626.sa.json" fu="$TEST_DIR/t2626.fu.json" out
  node "$PROJECT_ROOT/.aai/scripts/spec-amend.mjs" list --json > "$sa" || log_fail "TEST-2626: spec-amend list failed"
  node "$PROJECT_ROOT/.aai/scripts/follow-ups.mjs" list --status all --json > "$fu" || log_fail "TEST-2626: follow-ups list failed"
  out="$(node -e '
    const fs = require("fs");
    const sa = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const fu = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
    const mine = sa.items.filter((i) => i.ref_id === "node-first-second-slice");
    const bad = [];
    if (mine.length < 3) bad.push("only " + mine.length + " amendment record(s) for node-first-second-slice, want at least 3");
    for (const i of mine) if (i.bucket !== "signed") bad.push(i.record_key + " is " + i.bucket);
    const f = fu.items.find((i) => i.id === "fu-amend-spec-node-first-second-slice");
    if (!f) bad.push("fu-amend-spec-node-first-second-slice is not listed");
    else if (f.status !== "done") bad.push("fu-amend-spec-node-first-second-slice is " + f.status);
    process.stdout.write(bad.join("; "));
  ' "$sa" "$fu")"
  [[ -z "$out" ]] || log_fail "TEST-2626: $out"
  log_pass "TEST-2626: every #496 amendment record is signed and its follow-up is done"
}

main() {
  echo "Testing $TEST_NAME (SPEC spec-node-first-third-slice TEST-2601..2633)"
  check_deps
  setup_fixture
  test_2601_registry_parse
  test_2602_detect
  test_2603_check_phase
  test_2604_blocked_category
  test_2605_size_limit
  test_2606_injection_and_strip
  test_2607_fetch_and_cache
  test_2608_fetch_failures
  test_2609_exit_codes
  test_2610_body
  test_2611_cli_with_stub_gh
  test_2612_no_stdin_and_write_set
  test_2630_launcher_blocked_list
  test_2613_launchers_thin
  test_2614_sh_launcher_without_node
  test_2615_ps1_launcher_mapping_and_exit
  test_2616_launcher_parity
  test_2617_pester_expert_fetch
  test_2618_downstream_extended_sync_runs_expert_fetch
  test_2620_suite_map_selects_expert_fetch
  test_2621_ps1_quality_filter_has_module
  test_2622_line_budget_recorded
  test_2623_rfc_phase3_done
  test_2624_inventory_matches_tree
  test_2625_amended_status_checks
  test_2626_496_amendments_signed
  test_2627_blocked_list_spellings
  test_2628_blocked_list_fails_closed
  test_2629_body_blocked_check
  test_2631_cache_write_failure_cleans_up
  test_2632_cache_write_failure_shapes
  test_2633_blocked_list_residual_shapes
  test_2634_body_key_guard_planted
  test_2635_body_case_variant_blocked
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
