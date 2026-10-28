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
    exact)
      # exactly CANDIDATE_CAP (20) commits on the PR: every candidate is searched
      fx_commit "$REPO" c1 weird/unmapped.txt
      local j=0
      while [[ $j -lt 19 ]]; do
        fx_commit "$REPO" "x$j" docs/ai/EVENTS.jsonl
        j=$((j + 1))
      done
      ;;
    *)
      fx_commit "$REPO" c1 weird/unmapped.txt
      fx_commit "$REPO" c2 docs/ai/EVENTS.jsonl
      fx_commit "$REPO" c3 docs/ai/EVENTS.jsonl
      ;;
  esac
  MAIN_SHA="$(fx_git "$REPO" rev-parse main)" || log_fail "fixture: rev-parse main failed"
  C3="$(fx_git "$REPO" rev-parse HEAD)" || log_fail "fixture: rev-parse head failed"
  C2="$(fx_git "$REPO" rev-parse 'HEAD~1')" || log_fail "fixture: rev-parse c2 failed"
  C1="$(fx_git "$REPO" rev-list --max-parents=1 --reverse main..HEAD | sed -n 1p)" || log_fail "fixture: rev-parse c1 failed"
}

# EV_PR / EV_BASE_REF / EV_BASE_SHA: the event's pull_request number and base
# (defaults: PR 7 into main at the fixture's main sha); an empty EV_PR omits
# the number so the malformed-payload cell can be built.
EV_PR="7"
EV_BASE_REF="main"
EV_BASE_SHA=""
write_event() {  # <file> <action> <head sha> [repo full_name] [ref]
  local bsha="${EV_BASE_SHA:-$MAIN_SHA}" extra=""
  [[ -n "$EV_PR" ]] && extra="\"number\":$EV_PR,"
  printf '{"action":"%s","pull_request":{%s"head":{"sha":"%s","ref":"%s","repo":{"full_name":"%s"}},"base":{"ref":"%s","sha":"%s"}}}\n' \
    "$2" "$extra" "$3" "${5:-feat}" "${4:-o/r}" "$EV_BASE_REF" "$bsha" > "$1"
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
    sharded-selected-mode)
      printf '{"total_count":5,"jobs":[%s,%s,%s,%s,%s]}' \
        "$(job "$J_SELECT" success)" "$(job "$J_LEG" skipped)" \
        "$(job "$J_SELECTED" skipped)" "$(job 'skill suite (selected sharded, via test-framework.sh --skill) (1)' success)" "$(job "$J_GATE" success)" ;;
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

# RUN_PRS: the run's pull_requests[] (default: PR 7 into main at the fixture's
# main sha, what GitHub reports for a same-repo PR run).
RUN_PRS=""
# run_entry <id> <sha> <conclusion> [branch] [repo]
run_entry() {
  local prs="$RUN_PRS"
  [[ -n "$prs" ]] || prs="$(printf '[{"number":7,"base":{"ref":"main","sha":"%s"}}]' "$MAIN_SHA")"
  printf '{"id":%s,"head_sha":"%s","event":"pull_request","conclusion":"%s","head_branch":"%s","head_repository":{"full_name":"%s"},"pull_requests":%s,"html_url":"https://github.com/o/r/actions/runs/%s","created_at":"2026-10-08T10:00:00Z"}' \
    "$1" "$2" "$3" "${4:-feat}" "${5:-o/r}" "$prs" "$1"
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
  # CI_SELECT_SELECTOR swaps the selector script under ci-select.mjs; it is a
  # test seam, so the workflow must never set it anywhere (validation NB-4).
  if grep -qF 'CI_SELECT_SELECTOR' "$WORKFLOW_FILE"; then
    log_fail "TEST-1722: the workflow must never set the test-only CI_SELECT_SELECTOR override"
  fi
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

  # exactly 20 commits and no covering run: every candidate was searched, so this
  # is no-covering-run, not candidate-cap (review F5)
  mk_pr t1723-exact exact
  write_event "$ev" synchronize "$C3"
  fx_reset
  for c in $(fx_git "$REPO" rev-list --max-count=20 "$C3" "^main"); do
    [[ "$c" == "$C3" ]] && continue
    fx_runs "$c" 0 ""
  done
  fx_write "$fx"
  cs_run "$REPO" "$ev" "$fx" "$lg"; expect_none "TEST-1723 exactly 20 commits" no-covering-run
  log_pass "TEST-1723: nine fail-safe cells print whole-PR lines identical to select-suites plus a named reason (TEST-1723)"
}

test_1724_failsafe_table_anchor_cells() {  # Spec-AC-08
  log_info "Test: anchor fail-safe cells (selected-mode, failed leg, fork, branch, not-ancestor, ineligible) (TEST-1724)..."
  new_scratch
  mk_pr t1724 full
  local ev="$TEST_DIR/t1724.event" fx="$TEST_DIR/t1724.fx" lg="$TEST_DIR/t1724.log"
  write_event "$ev" synchronize "$C3"

  std_fixture "$fx" sharded-selected-mode
  cs_run "$REPO" "$ev" "$fx" "$lg"; expect_none "conditional TEST-005 matrix success cannot anchor" no-full-mode-run
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
  # The mode derivation now has a third, proof-bearing body-reuse arm. The
  # direct Node suite executes that real block and pins ordinary behavior.
  c="$(job_run_text "$WORKFLOW_FILE" select | awk '/^if echo "\$OUT"/ { on=1 } on { print } on && /^fi$/ { exit }')"
  [[ -n "$c" && "$c" == *'BODY_REUSE '* && "$c" == *'mode=full'* && "$c" == *'mode=selected'* ]] \
    || log_fail "TEST-1726: expected explicit body-reuse and ordinary modes"
  # Conditional sharding extends the selected branch. Pin the required name
  # and exact full success line; TEST-005 executes the entire new gate table.
  b="$(job_block "$base" gate | awk '/^    name:/ {print}')"
  c="$(job_block "$WORKFLOW_FILE" gate | awk '/^    name:/ {print}')"
  [[ -n "$b" && "$b" == "$c" ]] || log_fail "TEST-1726: required gate name changed"
  b="$(job_run_text "$base" gate | awk '/needs.skills-full.result.*full-mode run failed/ {print}')"
  c="$(job_run_text "$WORKFLOW_FILE" gate | awk '/needs.skills-full.result.*full-mode run failed/ {print}')"
  [[ -n "$b" && "$b" == "$c" ]] || log_fail "TEST-1726: full-mode success line changed"
  c="$(job_block "$WORKFLOW_FILE" skills-full)"
  [[ -n "$c" && "$c" == *'needs.select.outputs.checkout_sha'* && "$c" == *'source_identity'* \
    && "$c" == *'shard-plan-check.sh --check'* ]] \
    || log_fail "TEST-1726: full job lost pinned checkout, proof, or shard check"
  log_pass "TEST-1726: zero selected requests; non-PR, ci-full, full proof and required gate name retain contracts"

}

test_1738_anchor_bound_to_current_pr() {  # Spec-AC-08, review P1 (PR #435)
  log_info "Test: the anchor run must belong to the current PR and the same base (TEST-1738)..."
  new_scratch
  mk_pr t1738 full
  local ev="$TEST_DIR/t1738.event" fx="$TEST_DIR/t1738.fx" lg="$TEST_DIR/t1738.log"
  write_event "$ev" synchronize "$C3"

  # positive control: number, base ref and base sha all equal -> anchored
  RUN_PRS=""
  std_fixture "$fx"
  cs_run "$REPO" "$ev" "$fx" "$lg"
  has_prefix "$CS_OUT" "CARRY_FORWARD sha=$C1 run=22" || log_fail "TEST-1738: positive control must anchor, got: $CS_OUT"

  # the run belongs to another PR from the same branch (closed and reopened as a new PR)
  RUN_PRS="[{\"number\":8,\"base\":{\"ref\":\"main\",\"sha\":\"$MAIN_SHA\"}}]"
  std_fixture "$fx"
  cs_run "$REPO" "$ev" "$fx" "$lg"; expect_none "TEST-1738 other PR number" anchor-pr-mismatch

  # same PR number, retargeted base ref
  RUN_PRS="[{\"number\":7,\"base\":{\"ref\":\"release\",\"sha\":\"$MAIN_SHA\"}}]"
  std_fixture "$fx"
  cs_run "$REPO" "$ev" "$fx" "$lg"; expect_none "TEST-1738 retargeted base ref" anchor-base-moved

  # same PR, base branch advanced since the run
  RUN_PRS="[{\"number\":7,\"base\":{\"ref\":\"main\",\"sha\":\"0000000000000000000000000000000000000001\"}}]"
  std_fixture "$fx"
  cs_run "$REPO" "$ev" "$fx" "$lg"; expect_none "TEST-1738 moved base sha" anchor-base-moved

  # fork PR runs report an empty pull_requests array: fail safe
  RUN_PRS="[]"
  std_fixture "$fx"
  cs_run "$REPO" "$ev" "$fx" "$lg"; expect_none "TEST-1738 empty pull_requests" anchor-pr-mismatch

  # several PRs on the run: one matching entry is enough
  RUN_PRS="[{\"number\":9,\"base\":{\"ref\":\"main\",\"sha\":\"$MAIN_SHA\"}},{\"number\":7,\"base\":{\"ref\":\"main\",\"sha\":\"$MAIN_SHA\"}}]"
  std_fixture "$fx"
  cs_run "$REPO" "$ev" "$fx" "$lg"
  has_prefix "$CS_OUT" "CARRY_FORWARD sha=$C1 run=22" || log_fail "TEST-1738: a matching entry among several must anchor, got: $CS_OUT"
  RUN_PRS=""

  # an event payload without the PR number or the base is malformed: fail safe
  EV_PR=""
  write_event "$ev" synchronize "$C3"; std_fixture "$fx"
  cs_run "$REPO" "$ev" "$fx" "$lg"; expect_none "TEST-1738 event without number" event-malformed
  EV_PR="7"
  printf '{"action":"synchronize","pull_request":{"number":7,"head":{"sha":"%s","ref":"feat","repo":{"full_name":"o/r"}}}}\n' "$C3" > "$ev"
  cs_run "$REPO" "$ev" "$fx" "$lg"; expect_none "TEST-1738 event without base" event-malformed
  log_pass "TEST-1738: carry-forward anchors only a run of the same PR number, base ref and base sha (TEST-1738)"
}

test_1806_selected_gate_failure_cases() {
  node - "$WORKFLOW_FILE" <<'JS'
const fs=require('fs'),cp=require('child_process'),assert=require('assert');
const workflow=fs.readFileSync(process.argv[2],'utf8');
const job=workflow.split('  gate:\n')[1].split('\n  self-hosting-smoke:')[0];
const script=job.split('        run: |\n')[1].split('\n').map(l=>l.startsWith('          ')?l.slice(10):l).join('\n');
const good={'select.outputs.selected_runners':'1','skills-selected-sharded.result':'skipped','select.result':'success','select.outputs.mode':'selected','skills-selected.result':'success','skills-full.result':'skipped','native-worktree-seed.result':'success','self-hosting-smoke.result':'success','tracked-ignored.result':'success','release-notes.result':'success','release-dry-run.result':'success','github.event_name':'pull_request'};
const run=data=>cp.spawnSync('bash',['-c',script.replace(/\$\{\{ needs\.([^} ]+) \}\}/g,(_,k)=>data[k]??'').replace(/\$\{\{ github\.event_name \}\}/g,data['github.event_name']??'')],{encoding:'utf8'}).status;
assert.equal(run(good),0); assert.equal(run({...good,'select.outputs.mode':'full','skills-full.result':'success','skills-selected.result':'skipped'}),0);
for(const mode of ['selected','full']) for(const key of ['select.result','native-worktree-seed.result','self-hosting-smoke.result','tracked-ignored.result','release-notes.result','release-dry-run.result',mode==='selected'?'skills-selected.result':'skills-full.result']) for(const fail of ['failure','cancelled','skipped','']) {
 const data={...good,'select.outputs.mode':mode,'skills-full.result':'success',[key]:fail}; assert.notEqual(run(data),0,mode+' '+key+' '+fail);
}

const sharded={...good,'select.outputs.selected_runners':'2','skills-selected.result':'skipped','skills-selected-sharded.result':'success'};
assert.equal(run(sharded),0);
for(const key of ['select.result','native-worktree-seed.result','self-hosting-smoke.result','tracked-ignored.result','release-notes.result','release-dry-run.result','skills-selected-sharded.result']) for(const fail of ['failure','cancelled','skipped','']) assert.notEqual(run({...sharded,[key]:fail}),0,'sharded '+key+' '+fail);
for(const count of ['', '0', '3', 'all']) assert.notEqual(run({...good,'select.outputs.selected_runners':count}),0);
for(const mode of ['', 'invalid']) assert.notEqual(run({...good,'select.outputs.mode':mode,'skills-full.result':'success'}),0);
assert(job.includes('needs: [select, skills-selected, skills-selected-sharded, skills-full, native-worktree-seed, self-hosting-smoke, tracked-ignored, release-notes, release-dry-run]'));
assert(workflow.includes('name: skill suite (selected, via test-framework.sh --skill)'));
assert(workflow.includes('name: skill test suite (full framework, via test-framework.sh)'));
assert(workflow.includes('native-worktree-seed:') && workflow.includes('runs-on: windows-latest'));
console.log('PASS conditional TEST-005 single/sharded/full aggregate truth table, stable jobs and platform dependency');
const selected=workflow.split('  skills-selected:\n')[1].split('\n  skills-selected-sharded:')[0];
assert(selected.includes('SELECTED_SUITES: ${{ needs.select.outputs.suites }}'));assert(selected.includes('--check-selected selected-plan.txt tests/skills selected-input.txt'));
assert.equal((selected.match(/bash tests\/skills\/test-framework\.sh /g)||[]).length,1);
assert(workflow.includes('shard-plan-check.sh --check'));
console.log('PASS TEST-005 real aggregate script success/failure/missing cases and ordered data wiring');
JS
}

test_body_direct_path_mapping() {
  local list out
  new_scratch
  list="$TEST_DIR/body-direct-path.txt"
  printf '%s\n' 'tests/skills/lib/ci-body-recheck.test.mjs' > "$list"
  out="$(node "$SELECTOR" --repo-root "$PROJECT_ROOT" --files-from "$list")" \
    || log_fail "TEST-007: selector failed for the exact direct Node path"
  has_prefix "$out" 'SELECTED aai-ci-carry-forward ' \
    || log_fail "TEST-007: direct Node path did not select owning suite: $out"
  if has_prefix "$out" 'FULL_RUN '; then
    log_fail "TEST-007: direct Node path fell open to full: $out"
  fi
  log_pass "TEST-007: exact direct Node path selects aai-ci-carry-forward"
}

main() {
  echo "Testing $TEST_NAME (post-validation-pushes-reuse-test-results, Batch D)"
  check_deps
  node --test "$PROJECT_ROOT/tests/skills/lib/ci-body-recheck.test.mjs" || log_fail "body recheck direct tests failed"
  test_body_direct_path_mapping
  test_1806_selected_gate_failure_cases
  test_1720_anchor_found_past_failed_run_and_logged
  test_1721_job_name_constants_match_workflow
  test_1722_workflow_select_job_wiring
  test_1723_failsafe_table_api_and_event_cells
  test_1724_failsafe_table_anchor_cells
  test_1725_seam_s3_yaml_mode_derivation
  test_1726_no_requests_when_selected_and_workflow_lines_pinned
  test_1738_anchor_bound_to_current_pr
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
