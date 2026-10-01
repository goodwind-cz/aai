#!/usr/bin/env bash
#
# Test: SPEC downstream-rides-ask-no-governance-questions — a downstream
# project's ride asks the owner nothing before the merge checkpoint.
# TEST-1207, TEST-1210 .. TEST-1214, TEST-1216.
#
# The roadmap FILE is the posture switch (absent = autopilot, present =
# governed). This suite crosses the seams by running the REAL consumer scripts
# in a fixture project that carries a copy of .aai/scripts/ (whole lib/) and
# uses DEFAULT paths (no --roadmap, no --ledger): the vendored-downstream
# posture. Prose rows pin the canon sentences the agent reads.
#
# set -u like the sibling suites; exit codes are captured as rc=0; cmd || rc=$?.

set -u
TEST_NAME="test-aai-downstream-autopilot"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SHIP="$PROJECT_ROOT/.aai/SKILL_SHIP.prompt.md"
PR="$PROJECT_ROOT/.aai/SKILL_PR.prompt.md"
LOOP="$PROJECT_ROOT/.aai/system/AUTONOMOUS_LOOP.md"
COMMON="$PROJECT_ROOT/.aai/ROLE_COMMON.md"

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_info() { echo "INFO: $*"; }
log_skip() { echo "SKIP: $*"; exit 42; }
command -v node >/dev/null 2>&1 || log_skip "node not found"

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-downstream.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

REF="fixture-ride"

# mk_project <name> — a fixture downstream project: vendored scripts (whole
# lib/, per the test-aai-orchestration-dispatch TEST-567 precedent), an empty
# decisions ledger, one frozen spec, one open intake. NO docs/ai/roadmap.yaml.
mk_project() {
  local d="$TEST_DIR/$1"
  # HAZ-CD: guard BEFORE the rm -rf, never after (code review NB-4).
  [[ -n "$d" && "$d" = /* ]] || { echo "mk_project: fixture path not absolute: '$d'" >&2; exit 1; }
  rm -rf "$d"
  mkdir -p "$d/.aai/scripts/lib" "$d/docs/ai" "$d/docs/specs" "$d/docs/issues"
  cp "$PROJECT_ROOT"/.aai/scripts/{ride-select,spec-amend,follow-ups,orchestration-dispatch}.mjs "$d/.aai/scripts/"
  cp "$PROJECT_ROOT"/.aai/scripts/lib/*.mjs "$d/.aai/scripts/lib/"
  : > "$d/docs/ai/decisions.jsonl"
  cat > "$d/docs/specs/SPEC-0001-fx.md" <<MD
---
id: spec-$REF
type: spec
number: 1
status: implementing
links:
  requirement: docs/issues/CHANGE-0002-fx.md
  pr: []
  commits: []
---

# Spec fixture

SPEC-FROZEN: true
MD
  cat > "$d/docs/issues/CHANGE-0002-fx.md" <<MD
---
id: $REF
type: change
number: 2
status: draft
links:
  pr: []
  commits: []
---

# Fixture intake
MD
  printf '%s' "$d"
}

# in_project <dir> <cmd...> — run from the fixture root; stdout+stderr to
# $OUT, exit code to $RC. HAZ-CD: verified non-empty and absolute.
OUT=""; RC=0
in_project() {
  local d="$1"; shift
  [[ -n "$d" && "$d" = /* ]] || log_fail "in_project: path not absolute: '$d'"
  RC=0
  ( cd "$d" && "$@" ) > "$TEST_DIR/run.out" 2>&1 || RC=$?
  OUT="$(cat "$TEST_DIR/run.out")"
}

# section <file> <start-regex> <end-regex> — lines from the first start match
# up to (not including) the next end match.
section() {
  awk -v s="$2" -v e="$3" '
    started && $0 ~ e { exit }
    $0 ~ s { started = 1 }
    started { print }
  ' "$1"
}

has() { [[ "$1" == *"$2"* ]]; }

test_1207_dispatch_gate_agrees_with_cli_gate() {
  log_info "Test: dispatch open-intake gate.admitted equals the CLI gate verdict for absent, directory and malformed roadmap roots (TEST-1207)..."
  local kind d cli_rc admitted consulted want_consulted
  for kind in absent directory malformed; do
    d="$(mk_project "t1207-$kind")"
    case "$kind" in
      directory) mkdir -p "$d/docs/ai/roadmap.yaml" ;;
      malformed) printf 'this is not a roadmap\n' > "$d/docs/ai/roadmap.yaml" ;;
    esac
    cat > "$d/docs/ai/STATE.yaml" <<YAML
project_status: active
current_focus:
  type: intake_change
  ref_id: CHANGE-0001
  primary_path: docs/issues/CHANGE-0001-none.md
active_work_items:
  - ref_id: CHANGE-0001
    status: done
    phase: validation
    primary_path: docs/issues/CHANGE-0001-none.md
code_review:
  required: true
  status: pass
last_validation:
  status: pass
  ref_id: CHANGE-0001
human_input:
  required: false
  question: null
YAML
    in_project "$d" node .aai/scripts/ride-select.mjs gate --ref "$REF" --intake docs/issues/CHANGE-0002-fx.md
    cli_rc=$RC
    local snap
    ( cd "$d" && node --input-type=module -e '
      import { buildSnapshot } from "./.aai/scripts/orchestration-dispatch.mjs";
      import path from "node:path";
      const root = process.argv[1];
      const { snapshot, problems } = buildSnapshot(path.join(root, "docs/ai/STATE.yaml"), root);
      if (!snapshot) { process.stdout.write("problems:" + problems.join(",")); process.exit(0); }
      const c = (snapshot.open_intakes || []).find((x) => x.ref_id === process.argv[2]);
      process.stdout.write(c && c.gate ? `${c.gate.admitted} ${c.gate.consulted}` : "none");
    ' "$d" "$REF" ) > "$TEST_DIR/snap.out" 2>&1 || log_fail "TEST-1207 ($kind): buildSnapshot probe crashed: $(cat "$TEST_DIR/snap.out")"
    snap="$(cat "$TEST_DIR/snap.out")"
    admitted="${snap%% *}"; consulted="${snap##* }"
    [[ "$snap" != "none" ]] || log_fail "TEST-1207 ($kind): the fixture intake was not an open-intake candidate"
    if [[ "$cli_rc" -eq 0 ]]; then
      [[ "$admitted" == "true" ]] || log_fail "TEST-1207 ($kind): CLI gate exit 0 but dispatch admitted=$admitted"
    else
      [[ "$admitted" == "false" ]] || log_fail "TEST-1207 ($kind): CLI gate exit $cli_rc but dispatch admitted=$admitted"
    fi
    want_consulted="true"; [[ "$kind" == "absent" ]] && want_consulted="false"
    [[ "$consulted" == "$want_consulted" ]] || log_fail "TEST-1207 ($kind): consulted=$consulted, want $want_consulted"
    if [[ "$kind" == "absent" ]]; then
      [[ "$cli_rc" -eq 0 ]] || log_fail "TEST-1207: absent positive control: CLI gate must exit 0, got $cli_rc"
    else
      [[ "$cli_rc" -eq 1 ]] || log_fail "TEST-1207 ($kind): negative control: CLI gate must exit 1, got $cli_rc"
    fi
  done
  log_pass "TEST-1207: dispatch and CLI gate agree on absent (admit, not consulted), directory and malformed (refuse, consulted)"
}

test_1210_ship_step_1a_absent_admit() {
  log_info "Test: SKILL_SHIP 1a states the absent-roadmap admit and the stop reason, step 6 carries a ride gate line (TEST-1210)..."
  local one_a step6
  one_a="$(section "$SHIP" '^   1a\. RIDE GATE' '^   1b\. ')"
  step6="$(section "$SHIP" '^6\. MERGE CHECKPOINT' '^7\. ')"
  [[ -n "$one_a" ]] || log_fail "TEST-1210: SKILL_SHIP step 1a not found"
  has "$one_a" 'roadmap absent' || log_fail "TEST-1210: step 1a must name the 'roadmap absent' admit"
  has "$one_a" 'roadmap absent, gate not consulted (autopilot default)' || log_fail "TEST-1210: step 1a must carry the rationale text 'roadmap absent, gate not consulted (autopilot default)'"
  has "$one_a" 'a present but unreadable or invalid roadmap' || log_fail "TEST-1210: step 1a stop reason must read 'a present but unreadable or invalid roadmap'"
  has "$one_a" 'an unreadable roadmap' && log_fail "TEST-1210: step 1a must not keep the bare 'an unreadable roadmap' stop reason"
  [[ -n "$step6" ]] || log_fail "TEST-1210: SKILL_SHIP step 6 not found"
  has "$step6" 'ride gate:' || log_fail "TEST-1210: step 6 must carry a 'ride gate:' line"
  log_pass "TEST-1210: SKILL_SHIP 1a absent-admit + rationale + stop reason, step 6 ride gate line"
}

test_1211_signoff_none_is_the_no_question_default() {
  log_info "Test: four canon surfaces state signoff none is the autonomous default with no mid-ride owner question; step 6 owed sign-offs line (TEST-1211)..."
  local name body
  local sentence='`--signoff none` is the autonomous default'
  local secs=(
    "AUTONOMOUS_LOOP 6a|$(section "$LOOP" '^### 6a\)' '^### 6b|^## ')"
    "SKILL_PR AMENDMENT GATE|$(section "$PR" '^   - AMENDMENT GATE' '^   - [A-Z]')"
    "ROLE_COMMON POST-FREEZE|$(section "$COMMON" '^## POST-FREEZE SPEC AMENDMENT' '^## [A-Z]')"
    "SKILL_SHIP AUTOPILOT DEFAULTS|$(section "$SHIP" '^AUTOPILOT DEFAULTS' '^RUN')"
  )
  local entry
  for entry in "${secs[@]}"; do
    name="${entry%%|*}"; body="${entry#*|}"
    [[ -n "$body" ]] || log_fail "TEST-1211: section not found: $name"
    has "$body" "$sentence" || log_fail "TEST-1211: $name must state: $sentence"
    has "$body" 'never asked mid-ride' || log_fail "TEST-1211: $name must say the owner is 'never asked mid-ride'"
  done
  local step6
  step6="$(section "$SHIP" '^6\. MERGE CHECKPOINT' '^7\. ')"
  has "$step6" 'owed sign-offs:' || log_fail "TEST-1211: SKILL_SHIP step 6 must carry an 'owed sign-offs:' line"
  has "$step6" 'follow-ups.mjs list --status open --ref' || log_fail "TEST-1211: the owed sign-offs line must name 'follow-ups.mjs list --status open --ref'"
  log_pass "TEST-1211: signoff none default stated on four surfaces, step 6 owed sign-offs line"
}

test_1212_fixture_project_rides_with_no_question() {
  log_info "Test: fixture project, default paths: gate ADMIT, amend --signoff none, list --strict unsigned-tracked=1, no question text (TEST-1212)..."
  local d all=""
  d="$(mk_project t1212)"
  [[ ! -e "$d/docs/ai/roadmap.yaml" ]] || log_fail "TEST-1212: fixture must carry no roadmap"
  in_project "$d" node .aai/scripts/ride-select.mjs gate --ref "$REF" --intake docs/issues/CHANGE-0002-fx.md
  [[ "$RC" -eq 0 ]] || log_fail "TEST-1212: gate must exit 0 on the no-roadmap fixture, got $RC: $OUT"
  has "$OUT" 'ADMIT' || log_fail "TEST-1212: gate must print ADMIT: $OUT"
  all+="$OUT"$'\n'
  in_project "$d" node .aai/scripts/spec-amend.mjs add --spec docs/specs/SPEC-0001-fx.md --ref "$REF" --what "fixture amendment" --why "fixture reason" --signoff none
  [[ "$RC" -eq 0 ]] || log_fail "TEST-1212: spec-amend add --signoff none must exit 0, got $RC: $OUT"
  all+="$OUT"$'\n'
  in_project "$d" node .aai/scripts/spec-amend.mjs list --strict
  [[ "$RC" -eq 0 ]] || log_fail "TEST-1212: spec-amend list --strict must exit 0, got $RC: $OUT"
  has "$OUT" 'unsigned-tracked=1' || log_fail "TEST-1212: list --strict must report unsigned-tracked=1: $OUT"
  all+="$OUT"$'\n'
  [[ ! -e "$d/docs/ai/roadmap.yaml" ]] || log_fail "TEST-1212: the ride must not create a roadmap file"
  has "$all" '?' && log_fail "TEST-1212: ride output contains a question mark: $all"
  has "$all" 'AskUserQuestion' && log_fail "TEST-1212: ride output names AskUserQuestion"
  has "$all" 'owner must' && log_fail "TEST-1212: ride output contains 'owner must'"
  log_pass "TEST-1212: no-roadmap fixture rides gate -> amend -> strict list with no question text"
}

test_1213_malformed_roadmap_still_refuses() {
  log_info "Test: the same fixture with a malformed roadmap makes gate exit 1 (TEST-1213, negative control)..."
  local d
  d="$(mk_project t1213)"
  printf 'this is not a roadmap\n' > "$d/docs/ai/roadmap.yaml"
  in_project "$d" node .aai/scripts/ride-select.mjs gate --ref "$REF" --intake docs/issues/CHANGE-0002-fx.md
  [[ "$RC" -eq 1 ]] || log_fail "TEST-1213: gate with a malformed roadmap must exit 1, got $RC: $OUT"
  has "$OUT" 'REFUSED' || log_fail "TEST-1213: the refusal must say REFUSED: $OUT"
  log_pass "TEST-1213: a present but malformed roadmap still refuses (exit 1)"
}

test_1214_followups_lists_one_amend_item() {
  log_info "Test: after the fixture add, follow-ups list --status open --ref prints exactly one fu-amend line (TEST-1214)..."
  local d n=0 line
  d="$(mk_project t1214)"
  in_project "$d" node .aai/scripts/spec-amend.mjs add --spec docs/specs/SPEC-0001-fx.md --ref "$REF" --what "fixture amendment" --why "fixture reason" --signoff none
  [[ "$RC" -eq 0 ]] || log_fail "TEST-1214: add must exit 0, got $RC: $OUT"
  in_project "$d" node .aai/scripts/follow-ups.mjs list --status open --ref "$REF"
  [[ "$RC" -eq 0 ]] || log_fail "TEST-1214: follow-ups list must exit 0, got $RC: $OUT"
  while IFS= read -r line; do
    [[ "$line" =~ ^open[[:space:]]+fu-amend- ]] && n=$((n + 1))
  done <<< "$OUT"
  [[ "$n" -eq 1 ]] || log_fail "TEST-1214: want exactly one fu-amend item line, got $n: $OUT"
  # negative control: a different ref lists none
  in_project "$d" node .aai/scripts/follow-ups.mjs list --status open --ref some-other-ride
  has "$OUT" 'fu-amend-' && log_fail "TEST-1214: negative control: another ref must list no fu-amend item: $OUT"
  log_pass "TEST-1214: follow-ups list for the ride ref prints exactly one fu-amend item"
}

test_1216_suite_map_row_selects_this_suite() {
  log_info "Test: suite-map carries exactly one aai-downstream-autopilot row and a SKILL_SHIP diff selects it (TEST-1216)..."
  local rows sel ff
  rows="$(awk '/^  aai-downstream-autopilot:/ { n++ } END { print n + 0 }' "$PROJECT_ROOT/tests/skills/suite-map.yaml")"
  [[ "$rows" -eq 1 ]] || log_fail "TEST-1216: want exactly one aai-downstream-autopilot row in suite-map.yaml, got $rows"
  ff="$TEST_DIR/changed.txt"
  printf '.aai/SKILL_SHIP.prompt.md\n' > "$ff"
  ( cd "$PROJECT_ROOT" && node .aai/scripts/select-suites.mjs --files-from "$ff" ) > "$TEST_DIR/sel.out" 2>&1 || log_fail "TEST-1216: select-suites failed: $(cat "$TEST_DIR/sel.out")"
  sel="$(cat "$TEST_DIR/sel.out")"
  has "$sel" 'SELECTED aai-downstream-autopilot' || log_fail "TEST-1216: a SKILL_SHIP diff must select aai-downstream-autopilot: $sel"
  log_pass "TEST-1216: suite-map row present once and selected for a SKILL_SHIP diff"
}

main() {
  echo "=== $TEST_NAME ==="
  test_1207_dispatch_gate_agrees_with_cli_gate
  test_1210_ship_step_1a_absent_admit
  test_1211_signoff_none_is_the_no_question_default
  test_1212_fixture_project_rides_with_no_question
  test_1213_malformed_roadmap_still_refuses
  test_1214_followups_lists_one_amend_item
  test_1216_suite_map_row_selects_this_suite
  echo ""
  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then "$1"; else main; fi
fi
