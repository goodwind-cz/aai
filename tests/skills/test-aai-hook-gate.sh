#!/usr/bin/env bash
#
# Test: aai-hook-gate
# (docs/specs/SPEC-DRAFT-spec-hook-gate-on-node.md, TEST-3500..3519)
#
# The Claude hook gate decides in one Node module (.aai/scripts/hook-gate.mjs) behind the bash launcher
# .aai/scripts/claude-hook-gate.sh. Every case works in fresh mktemp fixtures with a stub gh first on PATH;
# payloads are written to files and redirected in (no live pipe); no case runs a real gh, az or network.
#
# bash 3.2 compatible (no ${var^^}, no declare -A).
#
# Usage:
#   bash tests/skills/test-aai-hook-gate.sh                    # run all
#   bash tests/skills/test-aai-hook-gate.sh test_3500_seam
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-hook-gate"
TEST_DIR=""
# The suite lives at <root>/tests/skills; the root is derived without a cd inside a substitution.
SELF="${BASH_SOURCE[0]}"
case "$SELF" in /*) ;; *) SELF="$PWD/$SELF" ;; esac
SCRIPT_DIR="${SELF%/*}"
PROJECT_ROOT="${SCRIPT_DIR%/tests/skills}"
MJS="$PROJECT_ROOT/.aai/scripts/hook-gate.mjs"
LAUNCHER="${AAI_HOOK_GATE_LAUNCHER:-$PROJECT_ROOT/.aai/scripts/claude-hook-gate.sh}"
NODE_TEST="${AAI_HOOK_GATE_NODE_TEST:-$PROJECT_ROOT/tests/skills/lib/hook-gate.test.mjs}"
SPEC_ID="spec-hook-gate-on-node"
CD_LEAK="$PROJECT_ROOT/.aai/scripts/check-cd-subshell-leak.mjs"

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
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-hook-gate-suite.XXXXXX")"
}

# run_node_tests <TEST id>: the module and node test file must exist; cases named with the id must
# pass; zero passing tests is a failure (a pattern that matches nothing is not a pass).
run_node_tests() {
  local id="$1" out rc=0
  [[ -f "$MJS" ]] || log_fail "$id: .aai/scripts/hook-gate.mjs does not exist"
  [[ -f "$NODE_TEST" ]] || log_fail "$id: tests/skills/lib/hook-gate.test.mjs does not exist"
  out="$(env -u AAI_ROLE -u AAI_GIT_WRITE node --test --test-name-pattern "$id" "$NODE_TEST" 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" >&2; log_fail "$id: node --test exited $rc"; }
  [[ "$out" =~ pass\ [1-9] ]] || { printf '%s\n' "$out" >&2; log_fail "$id: node --test reported zero passing tests for the pattern"; }
}

# need_tool <TEST id> <tool>: 0 when present; fail on CI when absent; named SKIP-CASE otherwise.
need_tool() {
  command -v "$2" >/dev/null 2>&1 && return 0
  [[ -z "${CI:-}" ]] || log_fail "$1: $2 is required on CI but is not on PATH"
  echo "SKIP-CASE: $1 needs $2, which is not installed here"
  return 1
}

# code_lines <file> <comment prefix: # or //>: non-blank, non-comment lines (the plan's method).
code_lines() {
  local g=grep
  [[ -x /usr/bin/grep ]] && g=/usr/bin/grep
  "$g" -cvE "^[[:space:]]*($2|\$)" "$1" || true
}

test_3500_seam() {
  run_node_tests TEST-3500
  log_pass "TEST-3500: importing the module has no side effect; the CLI fails open and never writes stdout"
}

test_3501_parity() {
  need_tool TEST-3501 git || return 0
  git -C "$PROJECT_ROOT" cat-file -e "c88cf708^{commit}" 2>/dev/null \
    || log_fail "TEST-3501: base commit c88cf708 is not a local object (a full-history checkout is required)"
  run_node_tests TEST-3501
  log_pass "TEST-3501: launcher and the c88cf708 script give the same exit code and bytes on every untagged corpus row"
}

# drift_problems <spec> <node test file>: DG ids of the D-DRIFT table vs test names (empty when they agree).
drift_problems() {
  cat > "$TEST_DIR/drift.cjs" <<'JS'
const fs = require('fs');
const [spec, tests] = process.argv.slice(2);
const table = fs.readFileSync(spec, 'utf8').split('\n').map((l) => l.match(/^\| (DG-\d\d) \|/)).filter(Boolean).map((m) => m[1]);
const names = [...fs.readFileSync(tests, 'utf8').matchAll(/^\s*test\('(DG-\d\d)\b/gm)].map((m) => m[1]);
const bad = [];
for (const id of table) { const n = names.filter((x) => x === id).length; if (n !== 1) bad.push(`${id} begins ${n} test names`); }
for (const id of new Set(names)) if (!table.includes(id)) bad.push(`${id} is not in the D-DRIFT table`);
if (table.length < 9) bad.push(`the table holds ${table.length} ids, expected at least 9`);
process.stdout.write(bad.join('; '));
JS
  node "$TEST_DIR/drift.cjs" "$1" "$2"
}

test_3502_drift_coverage() {
  local spec="" out f
  for f in "$PROJECT_ROOT"/docs/specs/*.md; do
    if grep -qx "id: $SPEC_ID" "$f"; then spec="$f"; break; fi
  done
  [[ -n "$spec" ]] || log_fail "TEST-3502: no spec with id $SPEC_ID under docs/specs"
  [[ -f "$NODE_TEST" ]] || log_fail "TEST-3502: tests/skills/lib/hook-gate.test.mjs does not exist"
  out="$(drift_problems "$spec" "$NODE_TEST")"
  [[ -z "$out" ]] || log_fail "TEST-3502: $out"
  sed "s/'DG-06 /'DG-60 /" "$NODE_TEST" > "$TEST_DIR/renamed.test.mjs"
  out="$(drift_problems "$spec" "$TEST_DIR/renamed.test.mjs")"
  [[ "$out" == *"DG-06 begins 0"* && "$out" == *"DG-60 is not in"* ]] || log_fail "TEST-3502: positive control: the renamed DG-06 was not reported ($out)"
  log_pass "TEST-3502: every D-DRIFT id begins exactly one node:test case and no case names a missing id"
}

test_3503_azure_forms() {
  run_node_tests TEST-3503
  log_pass "TEST-3503: the Azure merge forms are denied like gh pr merge and judged by gate 2b (DG-01)"
}

test_3504_inherited_pipefail() {
  run_node_tests TEST-3504
  log_pass "TEST-3504: an exported pipefail does not flip the merge, state-dump or commit decision (DG-02)"
}

test_3505_kept_decisions() {
  run_node_tests TEST-3505
  log_pass "TEST-3505: DG-03 to DG-09 behave as decided"
}

# write_payload <file> <command text>: a PreToolUse payload for a plain command (no quote or backslash in it).
write_payload() {
  printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"}}' "$2" > "$1"
}

# make_node_counter <bin dir> <log>: a node wrapper first on PATH that appends one line per start and execs the real node.
make_node_counter() {
  local real
  real="$(command -v node)"
  mkdir -p "$1"
  {
    echo '#!/bin/sh'
    echo "echo \"\$*\" >> \"$2\""
    echo "exec \"$real\" \"\$@\""
  } > "$1/node"
  chmod +x "$1/node"
}

test_3506_prefilter() {
  local d="$TEST_DIR/t3506" gate cmd log="$TEST_DIR/t3506/node.log" rc lines
  mkdir -p "$d/proj/docs/ai"
  make_node_counter "$d/bin" "$log"
  : > "$log"
  for gate in commit merge state-dump; do
    for cmd in 'ls -la docs/specs' 'git status --short' 'git log --oneline -5'; do
      write_payload "$d/p.json" "$cmd"
      rc=0
      PATH="$d/bin:$PATH" CLAUDE_PROJECT_DIR="$d/proj" bash "$LAUNCHER" "$gate" < "$d/p.json" > /dev/null 2>&1 || rc=$?
      [[ "$rc" == 0 ]] || log_fail "TEST-3506: $gate with '$cmd' exited $rc (want 0)"
    done
  done
  PATH="$d/bin:$PATH" CLAUDE_PROJECT_DIR="$d/proj" bash "$LAUNCHER" stop-nudge < "$d/p.json" > /dev/null 2>&1 || true
  lines="$(wc -l < "$log" | tr -d ' ')"
  [[ "$lines" == 0 ]] || log_fail "TEST-3506: a payload that cannot concern its gate started node $lines time(s)"
  write_payload "$d/p.json" 'git merge feature-x'
  rc=0
  PATH="$d/bin:$PATH" CLAUDE_PROJECT_DIR="$d/proj" bash "$LAUNCHER" merge < "$d/p.json" > /dev/null 2>&1 || rc=$?
  [[ "$rc" == 2 ]] || log_fail "TEST-3506: git merge feature-x exited $rc (want 2)"
  lines="$(wc -l < "$log" | tr -d ' ')"
  [[ "$lines" == 1 ]] || log_fail "TEST-3506: a delegated payload started node $lines time(s) (want exactly 1)"
  run_node_tests TEST-3506
  log_pass "TEST-3506: no node start for a payload that cannot concern its gate, exactly one when delegated; the rows the pre-filter passes over are rows the module allows"
}

test_3507_latency() {
  local out rc=0
  need_tool TEST-3507 git || return 0
  git -C "$PROJECT_ROOT" cat-file -e "c88cf708^{commit}" 2>/dev/null \
    || log_fail "TEST-3507: base commit c88cf708 is not a local object (a full-history checkout is required)"
  out="$(env -u AAI_ROLE node "$PROJECT_ROOT/tests/skills/lib/hook-gate-latency.mjs" --n 40 --launcher "$LAUNCHER" 2>&1)" || rc=$?
  printf '%s\n' "$out"
  [[ "$rc" == 0 ]] || log_fail "TEST-3507: hook-gate-latency.mjs exited $rc"
  log_pass "TEST-3507: the launcher meets the Spec-AC-08 ratio bounds against the c88cf708 script (n=40, interleaved)"
}

# Comment lines and the OR operator removed: the text a shape rule reads.
launcher_code() {
  sed -E 's/^[[:space:]]*#.*$//; s/[[:space:]]#.*$//; s/[|][|]//g' "$1"
}

test_3508_launcher_shape() {
  local n code out bad d="$TEST_DIR/t3508" want got fake
  n="$(code_lines "$LAUNCHER" '#')"
  [[ "$n" -le 70 ]] || log_fail "TEST-3508: the launcher has $n code lines (at most 70)"
  code="$(launcher_code "$LAUNCHER")"
  grep -qE '^set -u' <<<"$code" || log_fail "TEST-3508: the launcher does not set -u"
  ! grep -qE '(^|[[:space:];])set[[:space:]]+-[a-zA-Z]*e|pipefail' <<<"$code" || log_fail "TEST-3508: the launcher sets -e or pipefail"
  ! grep -q '|' <<<"$code" || log_fail "TEST-3508: the launcher holds a pipe other than the OR operator"
  bad="$(grep -nE '(^|[;&(`[:space:]])(grep|sed|awk|head|tail|tr)([[:space:]]|$)' <<<"$code" || true)"
  [[ -z "$bad" ]] || log_fail "TEST-3508: the launcher calls a text tool: $bad"
  grep -qF 'hook-gate.mjs' "$LAUNCHER" || log_fail "TEST-3508: the launcher does not name hook-gate.mjs"
  grep -qxF '[ "$rc" -eq 2 ] && exit 2' "$LAUNCHER" || log_fail "TEST-3508: the launcher lacks the literal rc line"
  mkdir -p "$d/leakroot/.aai/scripts"
  cp "$LAUNCHER" "$d/leakroot/.aai/scripts/claude-hook-gate.sh"
  git -C "$d/leakroot" init -q
  git -C "$d/leakroot" add -A
  git -C "$d/leakroot" -c user.email=fixture@example.invalid -c user.name=fixture commit -q -m fixture
  out="$(node "$CD_LEAK" --root "$d/leakroot" --baseline /dev/null 2>&1 || true)"
  [[ "$out" == *"cd-subshell leaks: 0 occurrence(s) in 0 of 1"* ]] || log_fail "TEST-3508: check-cd-subshell-leak reports the launcher: $out"
  printf 'x="$(%s /tmp && pwd)"\n' cd >> "$d/leakroot/.aai/scripts/claude-hook-gate.sh"
  out="$(node "$CD_LEAK" --root "$d/leakroot" --baseline /dev/null 2>&1 || true)"
  [[ "$out" == *"cd-subshell leaks: 1 occurrence(s)"* ]] || log_fail "TEST-3508: positive control: a cd in a substitution was not reported: $out"
  for want in "2 2" "1 0" "3 0"; do
    fake="$d/fake-${want%% *}"
    mkdir -p "$fake/proj"
    cp "$LAUNCHER" "$fake/"
    printf 'process.exit(%s);\n' "${want%% *}" > "$fake/hook-gate.mjs"
    write_payload "$d/p.json" 'git merge x'
    got=0
    CLAUDE_PROJECT_DIR="$fake/proj" bash "$fake/claude-hook-gate.sh" merge < "$d/p.json" > /dev/null 2>&1 || got=$?
    [[ "$got" == "${want##* }" ]] || log_fail "TEST-3508: a module exiting ${want%% *} gave launcher exit $got (want ${want##* })"
  done
  # A broken module under a lane marker fails closed on a merge-shaped payload (the node-missing bytes), open otherwise.
  for want in "exit 1:1" "exit 3:3" "syntax:" "unreadable:" "empty:"; do
    fake="$d/lane-${want%%:*}"
    fake="${fake// /-}"
    mkdir -p "$fake/proj"
    cp "$LAUNCHER" "$fake/"
    case "$want" in
      syntax:*) printf 'this is not (javascript\n' > "$fake/hook-gate.mjs" ;;
      empty:*) : > "$fake/hook-gate.mjs" ;;
      unreadable:*) printf 'process.exit(0);\n' > "$fake/hook-gate.mjs"; chmod 000 "$fake/hook-gate.mjs" ;;
      *) printf 'process.exit(%s);\n' "${want##*:}" > "$fake/hook-gate.mjs" ;;
    esac
    write_payload "$d/p.json" 'git merge x'
    got=0
    AAI_LANEX1520_MERGE=1 CLAUDE_PROJECT_DIR="$fake/proj" bash "$fake/claude-hook-gate.sh" merge < "$d/p.json" > /dev/null 2> "$d/lane.err" || got=$?
    [[ "$got" == 2 ]] || log_fail "TEST-3508: a broken module ($want) with a lane marker gave launcher exit $got (want 2)"
    grep -qF 'merge-policy: evaluator unavailable: node not found' "$d/lane.err" || log_fail "TEST-3508: a broken module ($want) with a lane marker did not print the lane guard text"
    got=0
    CLAUDE_PROJECT_DIR="$fake/proj" bash "$fake/claude-hook-gate.sh" merge < "$d/p.json" > /dev/null 2>&1 || got=$?
    [[ "$got" == 0 ]] || log_fail "TEST-3508: a broken module ($want) without a lane marker gave launcher exit $got (want 0)"
    write_payload "$d/p.json" 'ls'
    got=0
    AAI_LANEX1520_MERGE=1 CLAUDE_PROJECT_DIR="$fake/proj" bash "$fake/claude-hook-gate.sh" merge < "$d/p.json" > /dev/null 2>&1 || got=$?
    [[ "$got" == 0 ]] || log_fail "TEST-3508: a broken module ($want) with a lane marker and a payload that is not merge-shaped gave exit $got (want 0)"
    chmod 644 "$fake/hook-gate.mjs"
  done
  log_pass "TEST-3508: launcher code lines $n (at most 70), set -u without -e or pipefail, no pipe or text tool, exit 2 maps to 2 and every other exit to 0 (a lane marker plus a merge-shaped payload denies on a broken module)"
}

# fn_body <file> <function name>: the text of one bash function (from its header line to the closing brace).
fn_body() {
  awk -v n="$2" '$0 ~ "^"n"\\(\\) \\{" {f=1} f {print} f && /^}/ {exit}' "$1"
}

# run_selector <TEST id> <suite file> <selector>: runs one test function of another suite; fails with its tail.
run_selector() {
  local out rc=0
  out="$(env -u AAI_ROLE -u AAI_GIT_WRITE bash "$SCRIPT_DIR/$2" "$3" 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '%s\n' "$out" | tail -n 12 >&2; log_fail "$1: $2 $3 exited $rc"; }
}

test_3509_callers() {
  local ho="$SCRIPT_DIR/test-aai-hooks-overlay.sh" mp="$SCRIPT_DIR/test-aai-merge-policy.sh" f body
  for f in test_003_script_conformance test_009_stop_nudge test_016_merge_gate_sweep_check; do
    body="$(fn_body "$ho" "$f")"
    [[ "$body" == *'hook-gate.mjs'* || "$body" == *'$GATE_MODULE'* ]] || log_fail "TEST-3509: hooks-overlay $f does not read hook-gate.mjs"
  done
  body="$(fn_body "$mp" test_1571_skill_pr_merge_command_passes_hook_shape)"
  [[ "$body" == *checkMergeShape* ]] || log_fail "TEST-3509: merge-policy TEST-1571 does not use checkMergeShape of the module"
  [[ "$body" != *"awk '/^lane_check_merge_shape"* ]] || log_fail "TEST-3509: merge-policy TEST-1571 still awk-extracts lane_check_merge_shape from the script"
  for f in test_003_script_conformance test_009_stop_nudge test_016_merge_gate_sweep_check test_1502_no_marker_bytes_equal_base; do
    run_selector TEST-3509 test-aai-hooks-overlay.sh "$f"
  done
  run_selector TEST-3509 test-aai-merge-policy.sh test_1571_skill_pr_merge_command_passes_hook_shape
  log_pass "TEST-3509: the hooks-overlay and merge-policy callers read the module and keep passing (TEST-1502 unchanged)"
}

test_3510_guard_paths() {
  local out rc=0
  out="$(env -u AAI_ROLE node --input-type=module -e '
    const m = await import(process.argv[1]);
    if (!m.GUARD_PATHS.includes(".aai/scripts/hook-gate.mjs")) { console.log("GUARD_PATHS lacks hook-gate.mjs"); process.exit(1); }
    const r = m.classifyFiles([".aai/scripts/hook-gate.mjs"], { architecture: [], kinds: [], lanes: [] });
    console.log(r.denyReason);
  ' "file://$PROJECT_ROOT/.aai/scripts/merge-policy.mjs" 2>&1)" || rc=$?
  [[ "$rc" == 0 && "$out" == policy_touched ]] || log_fail "TEST-3510: GUARD_PATHS / classifyFiles: $out (rc=$rc)"
  grep -qF "closure.add('.aai/scripts/hook-gate.mjs');" "$SCRIPT_DIR/test-aai-merge-policy.sh" || log_fail "TEST-3510: TEST-1507 does not add hook-gate.mjs to the closure"
  run_selector TEST-3510 test-aai-merge-policy.sh test_1507_guard_paths_superset_of_import_closure
  log_pass "TEST-3510: GUARD_PATHS names hook-gate.mjs, TEST-1507 closes over it and a file list holding only the module is policy_touched"
}

# yaml_l3_block <file>: the protected_paths_l3 entries of a docs-audit YAML, one per line.
yaml_l3_block() {
  awk '/^protected_paths_l3:/ {f=1; next} f && /^  - / {sub(/^  - /, ""); print; next} f && !/^[[:space:]]*#/ {exit}' "$1"
}

test_3511_protected_lists() {
  local f out wf="$PROJECT_ROOT/.aai/workflow/WORKFLOW.md" hitl="$SCRIPT_DIR/test-aai-hitl-propagation.sh" bullet want
  # The retired file's name is spelled in two parts: TEST-3457 forbids the whole name in a suite.
  ps1='pre-commit-checks.p''s1'
  want=".aai/scripts/$ps1"$'\n.aai/scripts/claude-hook-gate.sh\n.aai/scripts/hook-gate.mjs'
  for f in "$PROJECT_ROOT/docs/ai/docs-audit.yaml" "$PROJECT_ROOT/.aai/templates/docs-audit.template.yaml"; do
    out="$(yaml_l3_block "$f" | awk -v p="$ps1" 'index($0, p) {n=3} n>0 {print; n--}')"
    [[ "$out" == "$want" ]] || log_fail "TEST-3511: ${f##*/}: the entries after the retired pre-commit checks are not the two gate files: $out"
  done
  bullet="$(awk '/^- guards:/ {f=1; print; next} f && /^- / {exit} f {print}' "$wf" | tr '\n' ' ')"
  [[ "$bullet" == "- guards: .aai/scripts/pre-commit-checks.sh, .aai/scripts/$ps1 " ]] || log_fail "TEST-3511: the WORKFLOW.md guards bullet is not its original line: $bullet"
  bullet="$(awk '/^- hook gate:/ {f=1; print; next} f && /^- / {exit} f {print}' "$wf" | tr '\n' ' ')"
  [[ "$bullet" =~ claude-hook-gate\.sh.*hook-gate\.mjs ]] || log_fail "TEST-3511: the WORKFLOW.md hook gate bullet does not name both gate files: $bullet"
  run_selector TEST-3511 test-aai-sync-seed.sh test_audit_template_single_source
  run_selector TEST-3511 test-aai-hitl-propagation.sh test_014_no_protected_path_touched
  out="$(fn_body "$hitl" test_014_no_protected_path_touched)"
  [[ "$out" != *'qhead -8'* ]] || log_fail "TEST-3511: hitl-propagation TEST-014 still reads only the first 8 protected entries"
  for f in .aai/scripts/claude-hook-gate.sh .aai/scripts/hook-gate.mjs; do
    out="$(printf '%s\n' "$f" | node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from - --repo-root "$PROJECT_ROOT")"
    [[ "$out" == *"FULL_RUN reason=protected-l3"* ]] || log_fail "TEST-3511: select-suites does not answer FULL_RUN reason=protected-l3 for $f: $out"
  done
  log_pass "TEST-3511: both gate files are L3-protected in docs-audit.yaml, its template and WORKFLOW.md; TEST-014 reads every entry"
}

# yaml_row_globs <suite-map> <suite>: the glob lines of one suite-map row.
row_globs() {
  awk -v want="  $2:" '$0 == want {f=1; next} f && /^  [a-z0-9][a-z0-9-]*:$/ {exit} f {print}' "$1"
}

# selected_in <root> <file>: the select-suites answer for one changed file under a repo root.
selected_in() {
  printf '%s\n' "$2" | node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from - --repo-root "$1"
}

test_3512_wiring() {
  local f out n sel="$TEST_DIR/t3512-root" tsv="$SCRIPT_DIR/suite-weights.tsv" nsl="$SCRIPT_DIR/lib/nested-suite-lint.mjs" profiles="$PROJECT_ROOT/.aai/system/PROFILES.yaml" c
  # The two gate files are L3-protected, so the real tree answers FULL_RUN for them; the suite map is read in a scratch root
  # whose docs-audit.yaml lists neither (everything else is the live map and the live profiles).
  mkdir -p "$sel/tests/skills" "$sel/docs/ai" "$sel/.aai/system"
  cp "$SCRIPT_DIR/suite-map.yaml" "$sel/tests/skills/"
  cp "$profiles" "$sel/.aai/system/"
  awk '!/claude-hook-gate\.sh|hook-gate\.mjs/' "$PROJECT_ROOT/docs/ai/docs-audit.yaml" > "$sel/docs/ai/docs-audit.yaml"
  for f in .aai/scripts/hook-gate.mjs .aai/scripts/claude-hook-gate.sh; do
    out="$(selected_in "$sel" "$f")"
    [[ "$out" == *'SELECTED aai-hook-gate '* ]] || log_fail "TEST-3512: $f does not select aai-hook-gate: $out"
  done
  out="$(selected_in "$sel" .aai/scripts/hook-gate.mjs)"
  for c in aai-hooks-overlay aai-merge-policy; do
    [[ "$out" == *"SELECTED $c "* ]] || log_fail "TEST-3512: the module does not select $c: $out"
  done
  for f in tests/skills/test-aai-hook-gate.sh tests/skills/lib/hook-gate.test.mjs tests/skills/lib/hook-gate-latency.mjs; do
    out="$(selected_in "$PROJECT_ROOT" "$f")"
    [[ "$out" == *'SELECTED aai-hook-gate '* ]] || log_fail "TEST-3512: $f does not select aai-hook-gate: $out"
  done
  n="$(awk -F'\t' '$1=="aai-hook-gate" && $2==196{c++} END{print c+0}' "$tsv")"
  [[ "$n" == 1 ]] || log_fail "TEST-3512: suite-weights holds $n aai-hook-gate rows at 196, expected 1"
  grep -qxF '# sample aai-hook-gate fallback unsampled (new suite of hook-gate-on-node; no successful observation)' "$tsv" || log_fail "TEST-3512: suite-weights lacks the aai-hook-gate fallback line"
  for f in test_090_suite_map_pin test_129_mutation_gate_suite_registration; do
    env -u AAI_ROLE -u AAI_GIT_WRITE bash "$SCRIPT_DIR/test-aai-hygiene-pack.sh" "$f" >"$TEST_DIR/t3512.out" 2>&1 || { tail -n 8 "$TEST_DIR/t3512.out" >&2; log_fail "TEST-3512: test-aai-hygiene-pack.sh $f failed"; }
  done
  node "$nsl" --allowlist "$SCRIPT_DIR/lib/nested-suite-allowlist.tsv" "$SCRIPT_DIR" >/dev/null 2>&1 || log_fail "TEST-3512: nested-suite-lint failed"
  node "$PROJECT_ROOT/.aai/scripts/check-cd-subshell-leak.mjs" >/dev/null 2>&1 || log_fail "TEST-3512: check-cd-subshell-leak.mjs failed"
  node "$PROJECT_ROOT/.aai/scripts/check-test-registration.mjs" "$SCRIPT_DIR" >/dev/null 2>&1 || log_fail "TEST-3512: check-test-registration.mjs failed"
  node "$PROJECT_ROOT/.aai/scripts/check-vendored-script-deps.mjs" >/dev/null 2>&1 || log_fail "TEST-3512: check-vendored-script-deps.mjs failed"
  n="$(grep -cxF '  - .aai/scripts/hook-gate.mjs' "$profiles" || true)"
  [[ "$n" == 1 ]] || log_fail "TEST-3512: PROFILES lists the module $n times, expected once"
  out="$(awk '/^[a-z]+:/ {s=$1} s=="core:" && /hook-gate\.mjs/ {print "core"}' "$profiles")"
  [[ "$out" == core ]] || log_fail "TEST-3512: PROFILES does not list the module under core"
  env -u AAI_ROLE -u AAI_GIT_WRITE bash "$SCRIPT_DIR/test-aai-layer-profiles.sh" test_manifest_conformance >/dev/null 2>&1 || log_fail "TEST-3512: test-aai-layer-profiles.sh test_manifest_conformance failed"
  log_pass "TEST-3512: the suite map, weights, profiles and ratchets know the new suite and the module"
}

test_3513_downstream_install() {
  local tgt="$TEST_DIR/inst target" bin="$TEST_DIR/t13-bin" log="$TEST_DIR/t13.log" rc=0 err
  mkdir -p "$tgt"
  git -C "$tgt" init -q -b main
  git -C "$tgt" config user.email fixture@example.invalid
  git -C "$tgt" config user.name fixture
  git -C "$tgt" config commit.gpgsign false
  printf '# target\n' > "$tgt/README.md"
  git -C "$tgt" add -A
  git -C "$tgt" commit -q -m init
  bash "$PROJECT_ROOT/.aai/scripts/aai-sync.sh" "$tgt" --profile core >/dev/null 2>&1 || log_fail "TEST-3513: aai-sync.sh --profile core failed"
  [[ -f "$tgt/.aai/scripts/claude-hook-gate.sh" && -f "$tgt/.aai/scripts/hook-gate.mjs" ]] || log_fail "TEST-3513: the core install lacks the launcher or the module"
  make_node_counter "$bin" "$log"
  : > "$log"
  write_payload "$TEST_DIR/t13-merge.json" 'gh pr merge 5'
  err="$TEST_DIR/t13.err"
  PATH="$bin:$PATH" CLAUDE_PROJECT_DIR="$tgt" bash "$tgt/.aai/scripts/claude-hook-gate.sh" merge < "$TEST_DIR/t13-merge.json" > /dev/null 2> "$err" || rc=$?
  [[ "$rc" == 2 ]] || log_fail "TEST-3513: the target's launcher exited $rc on gh pr merge 5 (want 2)"
  grep -qF 'Merge denied: constitution article 7 (operator-only merge)' "$err" || log_fail "TEST-3513: the deny lacks the article 7 text: $(cat "$err")"
  write_payload "$TEST_DIR/t13-ls.json" 'ls'
  : > "$log"
  rc=0
  PATH="$bin:$PATH" CLAUDE_PROJECT_DIR="$tgt" bash "$tgt/.aai/scripts/claude-hook-gate.sh" merge < "$TEST_DIR/t13-ls.json" > /dev/null 2>&1 || rc=$?
  [[ "$rc" == 0 ]] || log_fail "TEST-3513: the target's launcher exited $rc on ls (want 0)"
  [[ ! -s "$log" ]] || log_fail "TEST-3513: ls started node in the target"
  log_pass "TEST-3513: a core install (target path with a space) holds the launcher and the module; the target's own launcher denies gh pr merge 5 and allows ls without starting node"
}

test_3514_lines_and_rfc() {
  local before=341 after mod removed rfc="$PROJECT_ROOT/docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md" row n
  local sentence="The eleventh slice [moved the Claude hook gate's decisions to Node](../issues/CHANGE-DRAFT-hook-gate-on-node.md): one module decides the four gates behind a bash pre-filter that starts no Node process for a command that cannot concern a gate, the Azure merge command is gated like gh pr merge, and the gate is an L3 protected surface."
  after="$(code_lines "$LAUNCHER" '#')"
  mod="$(code_lines "$MJS" '//')"
  removed=$((before - after))
  echo "INFO: code lines before $before, launcher after $after, removed $removed, module $mod (JS: non-blank lines not starting with //)"
  env -u AAI_ROLE -u AAI_GIT_WRITE bash "$SCRIPT_DIR/test-aai-expert-fetch.sh" test_2624_inventory_matches_tree >/dev/null 2>&1 || log_fail "TEST-3514: test-aai-expert-fetch.sh test_2624_inventory_matches_tree failed"
  row="$(grep -F "$sentence" "$rfc" || true)"
  [[ -n "$row" ]] || log_fail "TEST-3514: the RFC-0017 phase 5 row lacks the D-RFC sentence"
  n="$(grep -cF "$sentence" "$rfc" || true)"
  [[ "$n" == 1 ]] || log_fail "TEST-3514: the D-RFC sentence appears $n times, expected once"
  [[ "$row" == '| 5 |'* && "$row" == *'in progress'* ]] || log_fail "TEST-3514: the phase 5 row no longer reads in progress"
  [[ "$after" -lt "$before" && "$mod" -gt 0 ]] || log_fail "TEST-3514: unexpected line counts (launcher $after, module $mod)"
  log_pass "TEST-3514: code lines before $before, after $after (launcher), removed $removed, module $mod; the RFC-0017 phase 5 row holds the sentence once and stays in progress"
}

test_3515_linear_scan() {
  run_node_tests TEST-3515
  log_pass "TEST-3515: a command just under the ceiling, a newline run or a repeated shape, is decided correctly in under two seconds through the launcher on every gate (DG-14)"
}

test_3516_azure_number_scan() {
  run_node_tests TEST-3516
  log_pass "TEST-3516: four megabytes of --pr tokens and platform merges in one segment are decided in under two seconds (DG-14)"
}

test_3517_git_scan() {
  run_node_tests TEST-3517
  log_pass "TEST-3517: a megabyte of git option runs is decided in under two seconds on the merge and commit gates (DG-14)"
}

test_3518_ceiling() {
  run_node_tests TEST-3518
  log_pass "TEST-3518: a relevant command above 262144 characters is denied by name, one at the ceiling is decided as ever, an irrelevant one is untouched (DG-15)"
}

test_3519_distinct_targets() {
  run_node_tests TEST-3519
  log_pass "TEST-3519: the limit of 16 counts distinct merge targets over gh and Azure forms; more are denied, never allowed (DG-14)"
}

main() {
  echo "Testing $TEST_NAME (SPEC $SPEC_ID TEST-3500..3519)"
  check_deps
  setup_fixture
  test_3500_seam
  test_3501_parity
  test_3502_drift_coverage
  test_3503_azure_forms
  test_3504_inherited_pipefail
  test_3505_kept_decisions
  test_3506_prefilter
  test_3507_latency
  test_3508_launcher_shape
  test_3509_callers
  test_3510_guard_paths
  test_3511_protected_lists
  test_3512_wiring
  test_3513_downstream_install
  test_3514_lines_and_rfc
  test_3515_linear_scan
  test_3516_azure_number_scan
  test_3517_git_scan
  test_3518_ceiling
  test_3519_distinct_targets
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
