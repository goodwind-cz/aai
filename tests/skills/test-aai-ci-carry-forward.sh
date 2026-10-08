#!/usr/bin/env bash
#
# Test: CI carry-forward of a previous successful full-mode run (CHANGE
# post-validation-pushes-reuse-test-results / SPEC
# spec-post-validation-pushes-reuse-test-results, Batch D: TEST-1720..1726,
# Spec-AC-07 and Spec-AC-08).
#
# Verifies .aai/scripts/ci-select.mjs: it finds the newest older commit of the
# PR with a completed successful FULL-mode skill-suite run through the GitHub
# API, prints the previous head SHA and run id, selects over the delta only,
# and fails safe to the whole-PR selector output on every other cell.
#
# No network: the API is replaced by a recorded-response fixture
# (--api-fixture, a map of request path to {status, body}) and every request is
# logged (--request-log). Fixtures are real git repos (git init -b main, own
# user.email/name) under a scratch dir.
#
# The script under test is overridable via CI_SELECT_SCRIPT, the whole-PR
# selector via SELECT_SUITES_SCRIPT.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-ci-carry-forward"
# Path math without a cd inside a command substitution (cd-subshell-leak gate).
_src="${BASH_SOURCE[0]}"
[[ "$_src" == */* ]] || _src="./$_src"
SCRIPT_DIR="${_src%/*}"
[[ "$SCRIPT_DIR" == /* ]] || SCRIPT_DIR="$PWD/$SCRIPT_DIR"
SCRIPT_DIR="${SCRIPT_DIR%/.}"
PROJECT_ROOT="${SCRIPT_DIR%/tests/skills}"
SCRIPT="${CI_SELECT_SCRIPT:-$PROJECT_ROOT/.aai/scripts/ci-select.mjs}"
SELECTOR="${SELECT_SUITES_SCRIPT:-$PROJECT_ROOT/.aai/scripts/select-suites.mjs}"
WORKFLOW_FILE="${CI_CARRY_FORWARD_WORKFLOW:-$PROJECT_ROOT/.github/workflows/skill-suite.yml}"
BASE_WORKFLOW_SHA="045e632e"

TEST_DIR=""
cleanup() {
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
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

# ---- fixture helpers -------------------------------------------------

new_scratch() {
  if [[ -z "${TEST_DIR:-}" || ! -d "$TEST_DIR" ]]; then
    TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-ci-carry-forward.XXXXXX")"
  fi
}

fx_git() {  # <repo> <git args...>
  local repo="$1"; shift
  [[ -n "$repo" && "$repo" == /* ]] || log_fail "fixture path must be non-empty and absolute: '$repo'"
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$repo" "$@"
}

fx_commit() {  # <repo> <message> <path...> — write a path, commit it
  local repo="$1" msg="$2"; shift 2
  local p
  for p in "$@"; do
    mkdir -p "$repo/${p%/*}"
    printf '%s\n' "$msg" >> "$repo/$p"
    fx_git "$repo" add "$p" || log_fail "fixture: git add $p failed"
  done
  fx_git "$repo" commit -q -m "$msg" || log_fail "fixture: commit '$msg' failed"
}

# mk_pr <name> <variant> — fixture repo with a main base and a PR branch `feat`.
# variants: full (c1 unmapped, c2+c3 ledger only), selected (c1 mapped only),
# inelig (c3 touches a code path), long (c1 unmapped then 21 ledger commits),
# Sets REPO C1 C2 C3 (C3 is the head).
mk_pr() {
  local name="$1" variant="$2"
  REPO="$TEST_DIR/$name"
  mkdir -p "$REPO"
  fx_git "$REPO" init -q -b main || log_fail "fixture: init failed"
  fx_git "$REPO" config user.email "fixture@example.invalid" || log_fail "fixture: config email failed"
  fx_git "$REPO" config user.name "Fixture" || log_fail "fixture: config name failed"
  fx_git "$REPO" symbolic-ref HEAD refs/heads/main || log_fail "fixture: symbolic-ref failed"
  mkdir -p "$REPO/tests/skills" "$REPO/core" "$REPO/feature" "$REPO/docs/ai"
  cat > "$REPO/tests/skills/suite-map.yaml" <<'EOF'
core:
  - aai-core

inert_globs:
  - docs/ai/reports/**

carry_forward_globs:
  - docs/ai/EVENTS.jsonl

full_run_triggers:
  shared_lib_globs:
    - .aai/scripts/lib/**

suites:
  aai-core:
    globs:
      - core/**

  aai-feature:
    globs:
      - feature/**
      - docs/ai/EVENTS.jsonl
EOF
  printf 'x\n' > "$REPO/core/a.txt"
  printf 'x\n' > "$REPO/feature/a.txt"
  printf 'x\n' > "$REPO/docs/ai/EVENTS.jsonl"
  fx_git "$REPO" add -A || log_fail "fixture: add base failed"
  fx_git "$REPO" commit -q -m base || log_fail "fixture: base commit failed"
  fx_git "$REPO" checkout -q -b feat || log_fail "fixture: checkout feat failed"
  case "$variant" in
    selected)
      fx_commit "$REPO" c1 feature/a.txt
      fx_commit "$REPO" c2 docs/ai/EVENTS.jsonl
      fx_commit "$REPO" c3 docs/ai/EVENTS.jsonl
      ;;
    inelig)
      fx_commit "$REPO" c1 weird/unmapped.txt
      fx_commit "$REPO" c2 docs/ai/EVENTS.jsonl
      fx_commit "$REPO" c3 feature/x.js
      ;;
    long)
      fx_commit "$REPO" c1 weird/unmapped.txt
      local i=0
      while [[ $i -lt 21 ]]; do
        fx_commit "$REPO" "e$i" docs/ai/EVENTS.jsonl
        i=$((i + 1))
      done
      ;;
    *)
      fx_commit "$REPO" c1 weird/unmapped.txt
      fx_commit "$REPO" c2 docs/ai/EVENTS.jsonl
      fx_commit "$REPO" c3 docs/ai/EVENTS.jsonl
      ;;
  esac
  C3="$(fx_git "$REPO" rev-parse HEAD)" || log_fail "fixture: rev-parse head failed"
  C2="$(fx_git "$REPO" rev-parse 'HEAD~1')" || log_fail "fixture: rev-parse c2 failed"
  C1="$(fx_git "$REPO" rev-list --max-parents=1 --reverse main..HEAD | sed -n 1p)" || log_fail "fixture: rev-parse c1 failed"
}

write_event() {  # <file> <action> <head sha> [repo full_name] [ref]
  printf '{"action":"%s","pull_request":{"head":{"sha":"%s","ref":"%s","repo":{"full_name":"%s"}}}}\n' \
    "$2" "$3" "${5:-feat}" "${4:-o/r}" > "$1"
}

job() {  # <name> <conclusion>
  printf '{"name":"%s","conclusion":"%s"}' "$1" "$2"
}

J_SELECT="select suites (PR impact analysis; full elsewhere)"
J_GATE="skill test suite (tests/skills/, via test-framework.sh)"
J_LEG="skill test suite (full framework, via test-framework.sh)"
J_SELECTED="skill suite (selected, via test-framework.sh --skill)"

# jobs_resp <variant>
jobs_resp() {
  case "$1" in
    full)
      printf '{"total_count":5,"jobs":[%s,%s,%s,%s,%s]}' \
        "$(job "$J_SELECT" success)" "$(job "$J_LEG (1)" success)" "$(job "$J_LEG (2)" success)" \
        "$(job "$J_SELECTED" skipped)" "$(job "$J_GATE" success)" ;;
    selected-mode)
      printf '{"total_count":4,"jobs":[%s,%s,%s,%s]}' \
        "$(job "$J_SELECT" success)" "$(job "$J_LEG" skipped)" \
        "$(job "$J_SELECTED" success)" "$(job "$J_GATE" success)" ;;
    both-ran)
      printf '{"total_count":4,"jobs":[%s,%s,%s,%s]}' \
        "$(job "$J_SELECT" success)" "$(job "$J_LEG (1)" success)" \
        "$(job "$J_SELECTED" success)" "$(job "$J_GATE" success)" ;;
    failed-leg)
      printf '{"total_count":5,"jobs":[%s,%s,%s,%s,%s]}' \
        "$(job "$J_SELECT" success)" "$(job "$J_LEG (1)" success)" "$(job "$J_LEG (2)" failure)" \
        "$(job "$J_SELECTED" skipped)" "$(job "$J_GATE" success)" ;;
    *) log_fail "unknown jobs variant $1" ;;
  esac
}

# run_entry <id> <sha> <conclusion> [branch] [repo]
run_entry() {
  printf '{"id":%s,"head_sha":"%s","event":"pull_request","conclusion":"%s","head_branch":"%s","head_repository":{"full_name":"%s"},"html_url":"https://github.com/o/r/actions/runs/%s","created_at":"2026-10-08T10:00:00Z"}' \
    "$1" "$2" "$3" "${4:-feat}" "${5:-o/r}" "$1"
}

runs_path() {  # <sha>
  printf '/repos/o/r/actions/workflows/skill-suite.yml/runs?event=pull_request&status=completed&head_sha=%s&per_page=20' "$1"
}
jobs_path() {  # <run id>
  printf '/repos/o/r/actions/runs/%s/jobs?filter=latest&per_page=100' "$1"
}

# fixture accumulator: fx_reset, fx_add <path> <status> <body-json>, fx_write <file>
FX_ENTRIES=""
fx_reset() { FX_ENTRIES=""; }
fx_add() {
  local e
  e="$(printf '"%s":{"status":%s,"body":%s}' "$1" "$2" "$3")"
  if [[ -z "$FX_ENTRIES" ]]; then FX_ENTRIES="$e"; else FX_ENTRIES="$FX_ENTRIES,$e"; fi
}
fx_add_raw() {  # <path> <status> <raw text>
  local e
  e="$(printf '"%s":{"status":%s,"raw":"%s"}' "$1" "$2" "$3")"
  if [[ -z "$FX_ENTRIES" ]]; then FX_ENTRIES="$e"; else FX_ENTRIES="$FX_ENTRIES,$e"; fi
}
fx_write() { printf '{%s}\n' "$FX_ENTRIES" > "$1"; }

fx_runs() {  # <sha> <total> <entries joined by comma>
  fx_add "$(runs_path "$1")" 200 "{\"total_count\":$2,\"workflow_runs\":[$3]}"
}

CS_TOKEN="tok"
CS_OUT=""
CS_CODE=0
# cs_run <repo> <event file> <fixture file> <request log> [extra args...]
cs_run() {
  local repo="$1" ev="$2" fx="$3" log="$4"; shift 4
  [[ -n "$repo" && "$repo" == /* && -d "$repo" ]] || log_fail "cs_run: bad fixture dir '$repo'"
  : > "$log"
  CS_CODE=0
  CS_OUT="$(env -u GITHUB_TOKEN ${CS_TOKEN:+GITHUB_TOKEN=$CS_TOKEN} node "$SCRIPT" --base-ref main \
    --event "$ev" --repo o/r --workflow-file skill-suite.yml --repo-root "$repo" \
    --api-fixture "$fx" --request-log "$log" "$@" 2>/dev/null)" || CS_CODE=$?
}

whole_pr() {  # <repo> — the whole-PR selector output, today's behaviour
  node "$SELECTOR" --base-ref main --repo-root "$1"
}

has_line() {  # <payload> <fixed line>
  local _l
  while IFS= read -r _l; do
    [[ "$_l" == "$2" ]] && return 0
  done <<EOF
$1
EOF
  return 1
}

has_prefix() {  # <payload> <prefix>
  local _l
  while IFS= read -r _l; do
    [[ "$_l" == "$2"* ]] && return 0
  done <<EOF
$1
EOF
  return 1
}

# expect_none <label> <expected reason> — CS_OUT must be today's whole-PR lines
# byte for byte plus exactly one CARRY_FORWARD none line.
expect_none() {
  local label="$1" reason="$2" expected
  expected="$(whole_pr "$REPO")"$'\n'"CARRY_FORWARD none reason=$reason"
  if [[ "$CS_OUT" != "$expected" ]]; then
    log_fail "$label: expected whole-PR lines plus 'CARRY_FORWARD none reason=$reason' (exit 0), got exit $CS_CODE: $CS_OUT"
  fi
  [[ "$CS_CODE" == "0" ]] || log_fail "$label: exit must be 0, got $CS_CODE"
}

# standard anchor fixture: c2 has a failed run, c1 has a full-mode success (run 22)
std_fixture() {  # <file> [c1 jobs variant] [c1 run branch] [c1 run repo]
  fx_reset
  fx_runs "$C2" 1 "$(run_entry 11 "$C2" failure)"
  fx_runs "$C1" 1 "$(run_entry 22 "$C1" success "${3:-feat}" "${4:-o/r}")"
  fx_add "$(jobs_path 22)" 200 "$(jobs_resp "${2:-full}")"
  fx_write "$1"
}

job_block() {  # <workflow> <job>
  awk -v job="  $2:" '
    $0 == job { on=1; print; next }
    on && /^  [A-Za-z0-9_-]+:/ { exit }
    on { print }
  ' "$1"
}

job_run_text() {  # <workflow> <job> — the run: block scalars de-indented
  job_block "$1" "$2" | awk '
    inrun {
      match($0, /^ */)
      if (RLENGTH >= indent) { print substr($0, indent + 1); next }
      if ($0 ~ /^[[:space:]]*$/) { print ""; next }
      inrun = 0
    }
    /^ *run: *\|/ { match($0, /^ */); inrun = 1; indent = RLENGTH + 2 }
  '
}

# ---- tests -----------------------------------------------------------

test_1720_anchor_found_past_failed_run_and_logged() {  # Spec-AC-07
  log_info "Test: newest candidate failed, older full-mode success is the anchor; SHA and run id printed (TEST-1720)..."
  new_scratch
  mk_pr t1720 full
  write_event "$TEST_DIR/t1720.event" synchronize "$C3"
  std_fixture "$TEST_DIR/t1720.fx"
  cs_run "$REPO" "$TEST_DIR/t1720.event" "$TEST_DIR/t1720.fx" "$TEST_DIR/t1720.log"
  [[ "$CS_CODE" == "0" ]] || log_fail "TEST-1720: exit must be 0, got $CS_CODE: $CS_OUT"
  has_line "$CS_OUT" "CARRY_FORWARD sha=$C1 run=22 url=https://github.com/o/r/actions/runs/22" \
    || log_fail "TEST-1720: expected the CARRY_FORWARD line naming the previous head SHA and run id, got: $CS_OUT"
  has_line "$CS_OUT" "DELTA base=$C1" || log_fail "TEST-1720: expected the delta selection, got: $CS_OUT"
  has_line "$CS_OUT" "CORE aai-core reason=core" || log_fail "TEST-1720: expected the CORE line, got: $CS_OUT"
  has_prefix "$CS_OUT" "SELECTED aai-feature" || log_fail "TEST-1720: expected the delta SELECTED line, got: $CS_OUT"
  if has_prefix "$CS_OUT" "FULL_RUN"; then
    log_fail "TEST-1720: no line may start with FULL_RUN in carry-forward mode, got: $CS_OUT"
  fi
  local want got
  want="$(runs_path "$C2")"$'\n'"$(runs_path "$C1")"$'\n'"$(jobs_path 22)"
  got="$(sed 's/^GET //' "$TEST_DIR/t1720.log")"
  [[ "$got" == "$want" ]] \
    || log_fail "TEST-1720: request log must list exactly the runs queries (event, status, full head_sha) and the jobs query (filter=latest). want: $want got: $got"
  log_pass "TEST-1720: older full-mode success anchors the delta; previous head SHA and run id printed (TEST-1720)"
}

test_1721_job_name_constants_match_workflow() {  # Spec-AC-07
  log_info "Test: ci-select job-name constants equal the name: values in skill-suite.yml (TEST-1721)..."
  local consts gate leg sel
  consts="$(node --input-type=module -e 'import(process.argv[1]).then((m) => { console.log(m.GATE_JOB); console.log(m.FULL_LEG_JOB); console.log(m.SELECTED_JOB); })' "file://$SCRIPT")" \
    || log_fail "TEST-1721: could not import the job-name constants from $SCRIPT"
  gate="$(printf '%s\n' "$consts" | sed -n 1p)"
  leg="$(printf '%s\n' "$consts" | sed -n 2p)"
  sel="$(printf '%s\n' "$consts" | sed -n 3p)"
  [[ -n "$gate" && -n "$leg" && -n "$sel" ]] || log_fail "TEST-1721: a constant is empty: $consts"
  local n
  for n in "$gate" "$leg" "$sel"; do
    grep -qxF "    name: $n" "$WORKFLOW_FILE" \
      || log_fail "TEST-1721: skill-suite.yml has no job 'name: $n' (constant drifted from the workflow)"
  done
  [[ "$gate" == "skill test suite (tests/skills/, via test-framework.sh)" ]] \
    || log_fail "TEST-1721: the gate constant must stay the required-check name, got: $gate"
  log_pass "TEST-1721: gate, full-leg and selected job-name constants equal the workflow names (TEST-1721)"
}

test_1722_workflow_select_job_wiring() {  # Spec-AC-07
  log_info "Test: select job has actions: read, passes github.token, no fixture flags, no secrets (TEST-1722)..."
  local block run
  block="$(job_block "$WORKFLOW_FILE" select)"
  [[ -n "$block" ]] || log_fail "TEST-1722: job 'select' not found"
  case "$block" in
    *"permissions:"*"actions: read"*) : ;;
    *) log_fail "TEST-1722: the select job must declare 'actions: read'" ;;
  esac
  case "$block" in
    *"contents: read"*) : ;;
    *) log_fail "TEST-1722: the select job must keep 'contents: read'" ;;
  esac
  case "$block" in
    *'GITHUB_TOKEN: ${{ github.token }}'*) : ;;
    *) log_fail "TEST-1722: the select step must pass github.token as GITHUB_TOKEN" ;;
  esac
  run="$(job_run_text "$WORKFLOW_FILE" select)"
  case "$run" in
    *"node .aai/scripts/ci-select.mjs"*) : ;;
    *) log_fail "TEST-1722: the select step must invoke ci-select.mjs" ;;
  esac
  case "$block" in
    *"--api-fixture"*|*"--request-log"*) log_fail "TEST-1722: the workflow must never pass the test-only fixture flags" ;;
  esac
  case "$block" in
    *"secrets."*) log_fail "TEST-1722: the select job must reference no secrets.* value" ;;
  esac
  log_pass "TEST-1722: select job wiring is actions: read + github.token, no fixtures, no secrets (TEST-1722)"
}

test_1723_failsafe_table_api_and_event_cells() {  # Spec-AC-08
  log_info "Test: every API/event fail-safe cell yields today's whole-PR lines plus a named reason (TEST-1723)..."
  new_scratch
  mk_pr t1723 full
  local ev="$TEST_DIR/t1723.event" fx="$TEST_DIR/t1723.fx" lg="$TEST_DIR/t1723.log"

  write_event "$ev" opened "$C3"; std_fixture "$fx"
  cs_run "$REPO" "$ev" "$fx" "$lg"; expect_none "TEST-1723 action opened" action-opened
  write_event "$ev" reopened "$C3"
  cs_run "$REPO" "$ev" "$fx" "$lg"; expect_none "TEST-1723 action reopened" action-reopened

  write_event "$ev" synchronize "$C3"
  CS_TOKEN=""
  cs_run "$REPO" "$ev" "$fx" "$lg"; expect_none "TEST-1723 no token" no-token
  CS_TOKEN="tok"

  # HTTP 403 / 500 on the newest candidate: stop, do NOT continue to the valid
  # anchor behind it.
  local st
  for st in 403 500; do
    fx_reset
    fx_add "$(runs_path "$C2")" "$st" 'null'
    fx_runs "$C1" 1 "$(run_entry 22 "$C1" success)"
    fx_add "$(jobs_path 22)" 200 "$(jobs_resp full)"
    fx_write "$fx"
    cs_run "$REPO" "$ev" "$fx" "$lg"; expect_none "TEST-1723 HTTP $st" "api-$st"
  done

  fx_reset
  fx_add_raw "$(runs_path "$C2")" 200 '{not json'
  fx_runs "$C1" 1 "$(run_entry 22 "$C1" success)"
  fx_add "$(jobs_path 22)" 200 "$(jobs_resp full)"
  fx_write "$fx"
  cs_run "$REPO" "$ev" "$fx" "$lg"; expect_none "TEST-1723 malformed JSON" api-json

  fx_reset
  fx_runs "$C2" 25 "$(run_entry 11 "$C2" failure)"
  fx_runs "$C1" 1 "$(run_entry 22 "$C1" success)"
  fx_add "$(jobs_path 22)" 200 "$(jobs_resp full)"
  fx_write "$fx"
  cs_run "$REPO" "$ev" "$fx" "$lg"; expect_none "TEST-1723 total_count above entries" pagination

  # candidate cap: 19 older candidates, none with a run, the anchor sits beyond the cap
  mk_pr t1723-long long
  write_event "$ev" synchronize "$C3"
  fx_reset
  local c
  for c in $(fx_git "$REPO" rev-list --max-count=20 "$C3" "^main"); do
    [[ "$c" == "$C3" ]] && continue
    fx_runs "$c" 0 ""
  done
  fx_write "$fx"
  cs_run "$REPO" "$ev" "$fx" "$lg"; expect_none "TEST-1723 candidate cap" candidate-cap
  log_pass "TEST-1723: nine fail-safe cells print whole-PR lines identical to select-suites plus a named reason (TEST-1723)"
}

test_1724_failsafe_table_anchor_cells() {  # Spec-AC-08
  log_info "Test: anchor fail-safe cells (selected-mode, failed leg, fork, branch, not-ancestor, ineligible) (TEST-1724)..."
  new_scratch
  mk_pr t1724 full
  local ev="$TEST_DIR/t1724.event" fx="$TEST_DIR/t1724.fx" lg="$TEST_DIR/t1724.log"
  write_event "$ev" synchronize "$C3"

  std_fixture "$fx" selected-mode
  cs_run "$REPO" "$ev" "$fx" "$lg"; expect_none "TEST-1724 selected-mode success" no-full-mode-run
  std_fixture "$fx" both-ran
  cs_run "$REPO" "$ev" "$fx" "$lg"; expect_none "TEST-1724 full leg ran but selected job did not skip" no-full-mode-run
  std_fixture "$fx" failed-leg
  cs_run "$REPO" "$ev" "$fx" "$lg"; expect_none "TEST-1724 failed full leg" no-full-mode-run
  std_fixture "$fx" full feat other/fork
  cs_run "$REPO" "$ev" "$fx" "$lg"; expect_none "TEST-1724 head repo mismatch" head-mismatch
  std_fixture "$fx" full other-branch o/r
  cs_run "$REPO" "$ev" "$fx" "$lg"; expect_none "TEST-1724 head branch mismatch" head-mismatch

  # anchor not an ancestor of the head (force push): the selector refuses, we fall back
  local wrap="$TEST_DIR/refuse-ancestor.mjs"
  cat > "$wrap" <<EOF
import { spawnSync } from 'node:child_process';
const a = process.argv.slice(2);
if (a.includes('--delta-base')) { console.log('DELTA_REFUSED reason=not-ancestor'); process.exit(0); }
const r = spawnSync(process.execPath, ['$SELECTOR', ...a], { stdio: 'inherit' });
process.exit(r.status === null ? 1 : r.status);
EOF
  std_fixture "$fx" full
  CI_SELECT_SELECTOR="$wrap" cs_run "$REPO" "$ev" "$fx" "$lg"
  expect_none "TEST-1724 anchor not ancestor" delta-refused:not-ancestor

  # ineligible delta path (code changed after the anchor)
  mk_pr t1724-inelig inelig
  write_event "$ev" synchronize "$C3"
  std_fixture "$fx" full
  cs_run "$REPO" "$ev" "$fx" "$lg"; expect_none "TEST-1724 ineligible delta path" delta-refused:ineligible

  # positive control: the same anchor on the clean fixture carries forward
  mk_pr t1724-ok full
  write_event "$ev" synchronize "$C3"
  std_fixture "$fx" full
  cs_run "$REPO" "$ev" "$fx" "$lg"
  has_prefix "$CS_OUT" "CARRY_FORWARD sha=$C1 run=22" || log_fail "TEST-1724: positive control must carry forward, got: $CS_OUT"
  log_pass "TEST-1724: anchor fail-safe cells fall back to whole-PR lines with a named reason (TEST-1724)"
}

test_1725_seam_s3_yaml_mode_derivation() {  # Spec-AC-08, seam S3
  log_info "Test: SEAM S3 — the workflow's own mode/SUITES derivation over ci-select output (TEST-1725)..."
  new_scratch
  local snippet="$TEST_DIR/derive-snippet.sh"
  job_run_text "$WORKFLOW_FILE" select | awk '/^if echo "\$OUT"/ { on=1 } on { print } on && /^fi$/ { exit }' > "$snippet"
  [[ -s "$snippet" ]] || log_fail "TEST-1725: could not extract the mode derivation from the workflow"
  mk_pr t1725 full
  local ev="$TEST_DIR/t1725.event" fx="$TEST_DIR/t1725.fx" lg="$TEST_DIR/t1725.log"

  derive() {  # <ci-select output> -> $TEST_DIR/gh-output
    local s="$TEST_DIR/derive.sh"
    : > "$TEST_DIR/gh-output"
    { printf 'set -e\nOUT=%q\n' "$1"; cat "$snippet"; } > "$s"
    GITHUB_OUTPUT="$TEST_DIR/gh-output" bash "$s" >/dev/null || log_fail "TEST-1725: the workflow derivation lines failed"
  }

  write_event "$ev" synchronize "$C3"; std_fixture "$fx"
  cs_run "$REPO" "$ev" "$fx" "$lg"
  derive "$CS_OUT"
  local go
  go="$(cat "$TEST_DIR/gh-output")"
  has_line "$go" "mode=selected" || log_fail "TEST-1725: a delta cell must derive mode=selected, got: $go"
  has_prefix "$go" "suites=" || log_fail "TEST-1725: a delta cell must derive a suites= line, got: $go"
  case "$go" in
    *aai-core*aai-feature*|*aai-feature*aai-core*) : ;;
    *) log_fail "TEST-1725: the delta suites must be CORE plus the delta suite, got: $go" ;;
  esac

  write_event "$ev" opened "$C3"
  cs_run "$REPO" "$ev" "$fx" "$lg"
  derive "$CS_OUT"
  go="$(cat "$TEST_DIR/gh-output")"
  has_line "$go" "mode=full" || log_fail "TEST-1725: a fallback cell must derive mode=full, got: $go"
  log_pass "TEST-1725: the YAML derivation gives selected for a delta cell and full for a fallback cell (TEST-1725)"
}

test_1726_no_requests_when_selected_and_workflow_lines_pinned() {  # Spec-AC-08
  log_info "Test: whole-PR selected makes zero API requests; non-PR/ci-full/gate logic unchanged vs base (TEST-1726)..."
  new_scratch
  mk_pr t1726-sel selected
  local ev="$TEST_DIR/t1726.event" fx="$TEST_DIR/t1726.fx" lg="$TEST_DIR/t1726.log"
  write_event "$ev" synchronize "$C3"; std_fixture "$fx"
  cs_run "$REPO" "$ev" "$fx" "$lg"
  expect_none "TEST-1726 whole-PR selected" whole-pr-selected
  [[ ! -s "$lg" ]] || log_fail "TEST-1726: a whole-PR selected cell must make zero API requests, log: $(cat "$lg")"

  mk_pr t1726-full full
  write_event "$ev" synchronize "$C3"; std_fixture "$fx"
  cs_run "$REPO" "$ev" "$fx" "$lg"
  [[ -s "$lg" ]] || log_fail "TEST-1726: positive control — the FULL_RUN cell must make API requests"

  # workflow lines versus the immutable base commit (pinned sha, never origin/main)
  local base="$TEST_DIR/base-skill-suite.yml"
  git -C "$PROJECT_ROOT" show "$BASE_WORKFLOW_SHA:.github/workflows/skill-suite.yml" > "$base" \
    || log_fail "TEST-1726: base commit $BASE_WORKFLOW_SHA is not available (needs full history)"
  local b c
  # non-PR and ci-full branches: from the first `if [[` to the comment before the selector call
  b="$(job_run_text "$base" select | awk '/^if \[\[ "\$\{\{ github.event_name/ { on=1 } /^# fetch-depth: 0 above/ { exit } on { print }')"
  c="$(job_run_text "$WORKFLOW_FILE" select | awk '/^if \[\[ "\$\{\{ github.event_name/ { on=1 } /^# fetch-depth: 0 above/ { exit } on { print }')"
  [[ -n "$b" && "$b" == "$c" ]] || log_fail "TEST-1726: the non-PR and ci-full branches of the select step changed against $BASE_WORKFLOW_SHA"
  # mode derivation lines
  b="$(job_run_text "$base" select | awk '/^if echo "\$OUT"/ { on=1 } on { print } on && /^fi$/ { exit }')"
  c="$(job_run_text "$WORKFLOW_FILE" select | awk '/^if echo "\$OUT"/ { on=1 } on { print } on && /^fi$/ { exit }')"
  [[ -n "$b" && "$b" == "$c" ]] || log_fail "TEST-1726: the mode/SUITES derivation changed against $BASE_WORKFLOW_SHA"
  # gate job: identical apart from the Spec-AC-01 tracked-ignored lines
  b="$(job_block "$base" gate)"
  c="$(job_block "$WORKFLOW_FILE" gate | sed 's/, tracked-ignored\]/]/' | awk '
    /needs\.tracked-ignored\.result/ { skip=3 }
    skip > 0 { skip--; next }
    { print }')"
  [[ -n "$b" && "$b" == "$c" ]] || log_fail "TEST-1726: the gate job name or mode logic changed against $BASE_WORKFLOW_SHA"
  log_pass "TEST-1726: zero requests for a selected PR; non-PR, ci-full and gate logic equal the base (TEST-1726)"
}

main() {
  echo "Testing $TEST_NAME (post-validation-pushes-reuse-test-results, Batch D)"
  check_deps
  test_1720_anchor_found_past_failed_run_and_logged
  test_1721_job_name_constants_match_workflow
  test_1722_workflow_select_job_wiring
  test_1723_failsafe_table_api_and_event_cells
  test_1724_failsafe_table_anchor_cells
  test_1725_seam_s3_yaml_mode_derivation
  test_1726_no_requests_when_selected_and_workflow_lines_pinned
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
