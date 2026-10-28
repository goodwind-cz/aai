#!/usr/bin/env bash
#
# Test: Codex rollout usage reader (SPEC spec-codex-usage-missing-from-run-budgets,
# TEST-3101..3121; TEST-3121 is opt-in via AAI_CODEX_SMOKE=1).
#
# Every fixture is built at run time in a mktemp CODEX_HOME with synthetic,
# metadata-shaped lines only (no message content); HOME points at an empty dir.
# No network. Single-row dispatch for mutation-run.mjs:
#   bash tests/skills/test-aai-codex-usage.sh --test TEST-3101
#   bash tests/skills/test-aai-codex-usage.sh test_3101_record_window_sums
#
# Exit codes: 0 all passed, 1 failed, 42 skipped (missing dependencies).

set -euo pipefail

TEST_NAME="aai-codex-usage"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/pipe-safe.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLI="${CODEX_USAGE_CLI:-$PROJECT_ROOT/.aai/scripts/codex-usage.mjs}"

TMP_ROOT=""
cleanup() {
  if [[ -n "${TMP_ROOT:-}" && -d "$TMP_ROOT" ]]; then rm -rf "$TMP_ROOT"; fi
}
trap cleanup EXIT

log_pass() { echo "PASS: $*"; }
CUR_TEST=""
log_fail() { echo "FAIL: ${CUR_TEST:+$CUR_TEST: }$*" >&2; exit 1; }
run_one() { local n="${1#test_}"; CUR_TEST="TEST-${n%%_*}"; "$1"; }
log_skip() { echo "SKIP: $*"; exit 42; }

check_deps() {
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aai-codex-usage.XXXXXX")"
  mkdir -p "$TMP_ROOT/home"
}

# --- fixture builders (synthetic, metadata-shaped lines only) -----------------
new_home() { # new_home <name> -> prints a fresh CODEX_HOME path with both dirs
  local h="$TMP_ROOT/$1"
  [[ -n "$1" ]] || log_fail "new_home needs a name"
  rm -rf "$h"; mkdir -p "$h/sessions/2026/10/01" "$h/archived_sessions"
  echo "$h"
}
mk_meta() { # file id parent ts cwd [session_id]
  local parent="null"; [[ "$3" == "-" ]] || parent="\"$3\""
  printf '{"timestamp":"%s","type":"session_meta","payload":{"id":"%s","session_id":"%s","parent_thread_id":%s,"timestamp":"%s","cwd":"%s","source":"cli"}}\n' \
    "$4" "$2" "${6:-s-$2}" "$parent" "$4" "$5" >> "$1"
}
mk_rec() { # file thread resp ts in out total [cached] [reasoning]  (use - to omit a field)
  local f="$1" th="$2" rid="$3" ts="$4" u="" kv
  local names=(input_tokens output_tokens total_tokens cached_input_tokens reasoning_output_tokens)
  local vals=("$5" "$6" "$7" "${8:--}" "${9:--}") i
  for i in 0 1 2 3 4; do
    [[ "${vals[$i]}" == "-" ]] && continue
    kv="\"${names[$i]}\":${vals[$i]}"
    u="${u:+$u,}$kv"
  done
  printf '{"timestamp":"%s","type":"token_usage_record","payload":{"thread_id":"%s","session_id":"s-%s","turn_id":"t1","response_id":"%s","usage":{%s}}}\n' \
    "$ts" "$th" "$th" "$rid" "$u" >> "$f"
}
mk_snap() { # file ts in out total  | file ts null
  if [[ "$3" == "null" ]]; then
    printf '{"timestamp":"%s","type":"event_msg","payload":{"type":"token_count","info":null}}\n' "$2" >> "$1"
  else
    printf '{"timestamp":"%s","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":%s,"output_tokens":%s,"total_tokens":%s}}}}\n' \
      "$2" "$3" "$4" "$5" >> "$1"
  fi
}
mk_compaction() { printf '{"timestamp":"%s","type":"compacted","payload":{}}\n' "$2" >> "$1"; }

# run_cli <codex_home> <args...> -> sets OUT and RC (never dies under set -e)
run_cli() {
  local h="$1"; shift
  RC=0
  OUT="$(env -u CODEX_THREAD_ID CODEX_HOME="$h" HOME="$TMP_ROOT/home" node "$CLI" "$@" 2>&1)" || RC=$?
}
# jv <json> <js expression over o> -> JSON text of the value
jv() { node -e 'const o=JSON.parse(process.argv[1]);const v=eval(process.argv[2]);console.log(JSON.stringify(v===undefined?null:v))' "$1" "$2"; }

expect_eq() { # expect_eq <label> <expected> <actual>
  [[ "$2" == "$3" ]] || log_fail "$1: expected [$2] got [$3] (out: ${OUT:0:300})"
}

# --- Spec-AC-01 ---------------------------------------------------------------
test_3101_record_window_sums() {
  local h f; h="$(new_home h3101)"; f="$h/sessions/2026/10/01/rollout-a.jsonl"
  mk_meta "$f" T1 - 2026-10-01T09:00:00Z /repo
  mk_rec "$f" T1 r1 2026-10-01T10:00:00Z 10 5 15
  mk_rec "$f" T1 r2 2026-10-01T10:30:00Z 20 10 30
  mk_rec "$f" T1 r4 2026-10-01T11:00:00Z 100 100 200   # at B, written EARLIER than r3
  mk_rec "$f" T1 r3 2026-10-01T10:45:00Z 5 5 10        # late-written, stamped inside
  mk_rec "$f" T1 r0 2026-10-01T09:59:59Z 1000 1000 2000 # before A
  run_cli "$h" observe --thread T1 --from 2026-10-01T10:00:00Z --to 2026-10-01T11:00:00Z --json
  expect_eq rc 0 "$RC"
  expect_eq input 35 "$(jv "$OUT" o.usage.input_tokens)"
  expect_eq output 20 "$(jv "$OUT" o.usage.output_tokens)"
  expect_eq total 55 "$(jv "$OUT" o.usage.total_tokens)"
  expect_eq basis '"response_records"' "$(jv "$OUT" o.basis)"
  log_pass "TEST-3101 record window sums are half-open and file-order independent"
}

test_3102_response_id_dedupe() {
  local h f g; h="$(new_home h3102)"; f="$h/sessions/2026/10/01/rollout-a.jsonl"; g="$h/archived_sessions/rollout-a.jsonl"
  mk_meta "$f" T1 - 2026-10-01T09:00:00Z /repo
  mk_rec "$f" T1 r1 2026-10-01T10:00:00Z 10 5 15
  mk_rec "$f" T1 r1 2026-10-01T10:00:00Z 10 5 15
  mk_rec "$f" T1 r2 2026-10-01T10:10:00Z 20 10 30
  cp "$f" "$g"
  run_cli "$h" observe --thread T1 --from 2026-10-01T09:00:00Z --to 2026-10-01T12:00:00Z --json
  expect_eq rc 0 "$RC"
  expect_eq total 45 "$(jv "$OUT" o.usage.total_tokens)"
  expect_eq degraded '[]' "$(jv "$OUT" o.degraded)"
  mk_rec "$g" T1 r2 2026-10-01T10:10:00Z 99 99 198   # same id, different usage
  run_cli "$h" observe --thread T1 --from 2026-10-01T09:00:00Z --to 2026-10-01T12:00:00Z --json
  expect_eq total2 45 "$(jv "$OUT" o.usage.total_tokens)"
  expect_eq conflict '["conflicting_duplicate"]' "$(jv "$OUT" o.degraded)"
  log_pass "TEST-3102 a response id counts once across files; conflicting repeat degrades"
}

test_3103_subset_semantics() {
  local h f; h="$(new_home h3103)"; f="$h/sessions/2026/10/01/rollout-a.jsonl"
  mk_meta "$f" T1 - 2026-10-01T09:00:00Z /repo
  mk_rec "$f" T1 r1 2026-10-01T10:00:00Z 100 50 150 40 20
  mk_rec "$f" T1 r2 2026-10-01T10:05:00Z 10 10 20 4 2
  run_cli "$h" observe --thread T1 --from 2026-10-01T09:00:00Z --to 2026-10-01T12:00:00Z --json
  expect_eq input 110 "$(jv "$OUT" o.usage.input_tokens)"
  expect_eq output 60 "$(jv "$OUT" o.usage.output_tokens)"
  expect_eq total 170 "$(jv "$OUT" o.usage.total_tokens)"
  expect_eq cached 44 "$(jv "$OUT" o.usage.cached_input_tokens_subset)"
  expect_eq reasoning 22 "$(jv "$OUT" o.usage.reasoning_output_tokens_subset)"
  expect_eq no-cache-key 'null' "$(jv "$OUT" o.usage.cached_input_tokens)"
  expect_eq degraded '[]' "$(jv "$OUT" o.degraded)"
  mk_rec "$f" T1 r3 2026-10-01T10:10:00Z 10 10 999 0 0
  run_cli "$h" observe --thread T1 --from 2026-10-01T09:00:00Z --to 2026-10-01T12:00:00Z --json
  expect_eq inconsistent '["inconsistent_total"]' "$(jv "$OUT" o.degraded)"
  expect_eq kept 1169 "$(jv "$OUT" o.usage.total_tokens)"
  log_pass "TEST-3103 subsets reported separately; total is input plus output"
}

# --- Spec-AC-02 ---------------------------------------------------------------
test_3104_cumulative_delta_and_reset() {
  local h f; h="$(new_home h3104)"; f="$h/sessions/2026/10/01/rollout-a.jsonl"
  mk_meta "$f" T1 - 2026-10-01T09:00:00Z /repo
  mk_snap "$f" 2026-10-01T09:30:00Z 60 40 100
  mk_snap "$f" 2026-10-01T10:10:00Z 90 60 150
  mk_snap "$f" 2026-10-01T10:20:00Z 90 60 150   # identical repeat
  mk_snap "$f" 2026-10-01T10:30:00Z null        # info null
  mk_snap "$f" 2026-10-01T10:40:00Z 120 80 200
  mk_snap "$f" 2026-10-01T12:30:00Z 900 900 1800 # at/after B
  run_cli "$h" observe --thread T1 --from 2026-10-01T10:00:00Z --to 2026-10-01T12:00:00Z --json
  expect_eq rc 0 "$RC"
  expect_eq basis '"cumulative_snapshot"' "$(jv "$OUT" o.basis)"
  expect_eq total 100 "$(jv "$OUT" o.usage.total_tokens)"
  expect_eq input 60 "$(jv "$OUT" o.usage.input_tokens)"
  expect_eq output 40 "$(jv "$OUT" o.usage.output_tokens)"
  expect_eq degraded '[]' "$(jv "$OUT" o.degraded)"
  # no baseline before A: delta is the last snapshot itself
  run_cli "$h" observe --thread T1 --from 2026-10-01T08:00:00Z --to 2026-10-01T12:00:00Z --json
  expect_eq total-from-zero 200 "$(jv "$OUT" o.usage.total_tokens)"
  # counter reset
  local g; g="$h/sessions/2026/10/01/rollout-b.jsonl"
  mk_meta "$g" T2 - 2026-10-01T09:00:00Z /repo
  mk_snap "$g" 2026-10-01T09:30:00Z 60 40 100
  mk_snap "$g" 2026-10-01T10:10:00Z 120 80 200
  mk_snap "$g" 2026-10-01T10:40:00Z 30 20 50
  mk_snap "$g" 2026-10-01T11:00:00Z 50 30 80
  run_cli "$h" observe --thread T2 --from 2026-10-01T10:00:00Z --to 2026-10-01T12:00:00Z --json
  expect_eq reset-total 180 "$(jv "$OUT" o.usage.total_tokens)"
  expect_eq reset-in 110 "$(jv "$OUT" o.usage.input_tokens)"
  expect_eq reset-out 70 "$(jv "$OUT" o.usage.output_tokens)"
  expect_eq reset-flag '["counter_reset"]' "$(jv "$OUT" o.degraded)"
  expect_eq non-negative true "$(jv "$OUT" 'Object.values(o.usage).every((x) => x === null || x >= 0)')"
  # NB-A: an untimed snapshot is surfaced as a degraded reason, never silently dropped or counted
  local ut; ut="$h/sessions/2026/10/01/rollout-ut.jsonl"
  mk_meta "$ut" T9 - 2026-10-01T09:00:00Z /repo
  mk_snap "$ut" 2026-10-01T10:01:00Z 60 40 100
  printf '%s\n' '{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":300,"output_tokens":200,"total_tokens":500}}}}' >> "$ut"
  run_cli "$h" observe --thread T9 --from 2026-10-01T09:00:00Z --to 2026-10-01T12:00:00Z --json
  expect_eq rc-untimed-snap 0 "$RC"
  expect_eq untimed-snap true "$(jv "$OUT" 'o.degraded.includes("missing_field:timestamp")')"
  run_cli "$h" budget --thread T9 --since 2026-10-01T09:00:00Z --max-run-tokens 1000000 --json
  expect_eq budget-untimed-snap '"degraded"' "$(jv "$OUT" o.enforcement)"
  log_pass "TEST-3104 cumulative delta, null/identical skip, counter reset segments"
}

test_3105_cumulative_compaction_flag() {
  local h f; h="$(new_home h3105)"; f="$h/sessions/2026/10/01/rollout-a.jsonl"
  mk_meta "$f" T1 - 2026-10-01T09:00:00Z /repo
  mk_snap "$f" 2026-10-01T10:10:00Z 90 60 150
  mk_compaction "$f" 2026-10-01T10:20:00Z
  mk_snap "$f" 2026-10-01T10:40:00Z 120 80 200
  run_cli "$h" observe --thread T1 --from 2026-10-01T10:00:00Z --to 2026-10-01T12:00:00Z --json
  expect_eq in-window '["cumulative_may_omit_compaction"]' "$(jv "$OUT" o.degraded)"
  run_cli "$h" observe --thread T1 --from 2026-10-01T10:30:00Z --to 2026-10-01T12:00:00Z --json
  expect_eq outside '[]' "$(jv "$OUT" o.degraded)"
  log_pass "TEST-3105 a compaction inside the window flags the cumulative basis only"
}

# --- Spec-AC-03 ---------------------------------------------------------------
test_3106_missing_partial_malformed() {
  local h f; h="$(new_home h3106)"; f="$h/sessions/2026/10/01/rollout-a.jsonl"
  mk_meta "$f" T1 - 2026-10-01T09:00:00Z /repo
  mk_rec "$f" T1 r1 2026-10-01T10:00:00Z 10 - 10
  run_cli "$h" observe --thread T1 --from 2026-10-01T09:00:00Z --to 2026-10-01T12:00:00Z --json
  expect_eq rc 0 "$RC"
  expect_eq output-null null "$(jv "$OUT" o.usage.output_tokens)"
  expect_eq input 10 "$(jv "$OUT" o.usage.input_tokens)"
  expect_eq reason true "$(jv "$OUT" 'o.degraded.includes("missing_field:output_tokens")')"
  # truncated last line (write in progress)
  printf '{"timestamp":"2026-10-01T10:05:00Z","type":"token_usa' >> "$f"
  run_cli "$h" observe --thread T1 --from 2026-10-01T09:00:00Z --to 2026-10-01T12:00:00Z --json
  expect_eq rc-partial 0 "$RC"
  expect_eq partial true "$(jv "$OUT" o.partial_tail)"
  expect_eq no-malformed false "$(jv "$OUT" 'o.degraded.includes("malformed_line")')"
  # malformed middle line
  local g; g="$h/sessions/2026/10/01/rollout-b.jsonl"
  mk_meta "$g" T2 - 2026-10-01T09:00:00Z /repo
  echo 'this is not json' >> "$g"
  mk_rec "$g" T2 r9 2026-10-01T10:00:00Z 1 1 2
  run_cli "$h" observe --thread T2 --from 2026-10-01T09:00:00Z --to 2026-10-01T12:00:00Z --json
  expect_eq malformed true "$(jv "$OUT" 'o.degraded.includes("malformed_line")')"
  expect_eq partial-false false "$(jv "$OUT" o.partial_tail)"
  expect_eq total2 2 "$(jv "$OUT" o.usage.total_tokens)"
  # a record with no timestamp is surfaced, not dropped silently
  local u; u="$h/sessions/2026/10/01/rollout-u.jsonl"
  mk_meta "$u" T3 - 2026-10-01T09:00:00Z /repo
  printf '%s\n' '{"type":"token_usage_record","payload":{"thread_id":"T3","response_id":"r1","usage":{"input_tokens":5,"output_tokens":5,"total_tokens":10}}}' >> "$u"
  mk_rec "$u" T3 r2 2026-10-01T10:00:00Z 1 1 2
  run_cli "$h" observe --thread T3 --from 2026-10-01T09:00:00Z --to 2026-10-01T12:00:00Z --json
  expect_eq untimed true "$(jv "$OUT" 'o.degraded.includes("missing_field:timestamp")')"
  expect_eq untimed-total 2 "$(jv "$OUT" o.usage.total_tokens)"
  # a reversed window is a usage error, not zeros
  run_cli "$h" observe --thread T3 --from 2026-10-01T12:00:00Z --to 2026-10-01T09:00:00Z --json
  expect_eq rc-reversed 2 "$RC"
  # NB-C: a newline-terminated malformed last line is a complete corrupt record, not a partial tail
  local lm; lm="$h/sessions/2026/10/01/rollout-lm.jsonl"
  mk_meta "$lm" T4 - 2026-10-01T09:00:00Z /repo
  mk_rec "$lm" T4 r1 2026-10-01T10:00:00Z 5 5 10
  printf '%s\n' '{"timestamp":"2026-10-01T10:05:00Z","type":"token_usage_record","payload":{BROKEN}}' >> "$lm"
  run_cli "$h" observe --thread T4 --from 2026-10-01T09:00:00Z --to 2026-10-01T12:00:00Z --json
  expect_eq lastmal-degraded true "$(jv "$OUT" 'o.degraded.includes("malformed_line")')"
  expect_eq lastmal-partial false "$(jv "$OUT" o.partial_tail)"
  log_pass "TEST-3106 missing is null not zero; partial tail and malformed line are distinguished"
}

test_3107_unavailable_reasons() {
  local h f; h="$(new_home h3107)"; f="$h/sessions/2026/10/01/rollout-a.jsonl"
  mk_meta "$f" T1 - 2026-10-01T09:00:00Z /repo
  mk_rec "$f" T1 r1 2026-10-01T10:00:00Z 1 1 2
  mk_meta "$h/sessions/2026/10/01/rollout-e.jsonl" TE - 2026-10-01T09:00:00Z /repo
  local args=(--from 2026-10-01T09:00:00Z --to 2026-10-01T12:00:00Z --json)
  run_cli "$TMP_ROOT/does-not-exist" observe --thread T1 "${args[@]}"
  expect_eq rc-unreadable 4 "$RC"; expect_eq reason-unreadable '"source_unreadable"' "$(jv "$OUT" o.reason)"
  expect_eq usage-null null "$(jv "$OUT" o.usage)"
  run_cli "$h" observe --thread auto "${args[@]}"
  expect_eq rc-auto 4 "$RC"; expect_eq reason-auto '"thread_identity_unresolved"' "$(jv "$OUT" o.reason)"
  run_cli "$h" observe --thread NOPE "${args[@]}"
  expect_eq rc-unknown 4 "$RC"; expect_eq reason-unknown '"thread_not_found"' "$(jv "$OUT" o.reason)"
  run_cli "$h" observe --thread TE "${args[@]}"
  expect_eq rc-empty 4 "$RC"; expect_eq reason-empty '"no_usage_events"' "$(jv "$OUT" o.reason)"
  # negative control: env-resolved thread reads fine
  RC=0; OUT="$(CODEX_HOME="$h" HOME="$TMP_ROOT/home" CODEX_THREAD_ID=T1 node "$CLI" observe --thread auto "${args[@]}" 2>&1)" || RC=$?
  expect_eq rc-env 0 "$RC"; expect_eq total-env 2 "$(jv "$OUT" o.usage.total_tokens)"
  log_pass "TEST-3107 four unavailable reasons exit 4 with usage null"
}

# --- Spec-AC-04 ---------------------------------------------------------------
test_3108_first_meta_identity() {
  local h f; h="$(new_home h3108)"; f="$h/sessions/2026/10/01/rollout-child.jsonl"
  mk_meta "$f" C P 2026-10-01T09:30:00Z /wt
  mk_meta "$f" P - 2026-10-01T09:00:00Z /repo          # forked history: parent's meta
  mk_rec "$f" P rp1 2026-10-01T09:10:00Z 500 500 1000   # parent's forked record
  mk_rec "$f" C rc1 2026-10-01T10:00:00Z 7 3 10
  mk_rec "$f" X rx1 2026-10-01T10:01:00Z 400 400 800    # foreign thread
  run_cli "$h" observe --thread C --from 2026-10-01T08:00:00Z --to 2026-10-01T12:00:00Z --json
  expect_eq rc 0 "$RC"
  expect_eq total 10 "$(jv "$OUT" o.usage.total_tokens)"
  expect_eq input 7 "$(jv "$OUT" o.usage.input_tokens)"
  run_cli "$h" observe --thread P --from 2026-10-01T08:00:00Z --to 2026-10-01T12:00:00Z --json
  expect_eq parent-not-found 4 "$RC"
  log_pass "TEST-3108 first session_meta binds identity; foreign thread records are ignored"
}

test_3109_archived_and_cwd_change() {
  local h p c; h="$(new_home h3109)"
  p="$h/archived_sessions/rollout-parent.jsonl"; c="$h/sessions/2026/10/01/rollout-child.jsonl"
  mk_meta "$p" P - 2026-10-01T09:00:00Z /repo
  mk_rec "$p" P rp1 2026-10-01T09:10:00Z 4 4 8
  mk_meta "$c" C P 2026-10-01T09:30:00Z /worktree
  mk_rec "$c" C rc1 2026-10-01T10:00:00Z 6 4 10
  local args=(--from 2026-10-01T08:00:00Z --to 2026-10-01T12:00:00Z --json)
  run_cli "$h" observe --thread P "${args[@]}"
  expect_eq rc-parent 0 "$RC"; expect_eq parent-total 8 "$(jv "$OUT" o.usage.total_tokens)"
  run_cli "$h" observe --thread C "${args[@]}"
  expect_eq rc-child 0 "$RC"; expect_eq child-total 10 "$(jv "$OUT" o.usage.total_tokens)"
  # NB-B: a rollout copied into both dirs counts once even without response ids; differing copies degrade
  local nr; nr="$(new_home h3109nr)"
  local n1="$nr/sessions/2026/10/01/rollout-n.jsonl" n2="$nr/archived_sessions/rollout-n.jsonl"
  mk_meta "$n1" TN - 2026-10-01T09:00:00Z /repo
  printf '%s\n' '{"timestamp":"2026-10-01T10:00:00Z","type":"token_usage_record","payload":{"thread_id":"TN","usage":{"input_tokens":100,"output_tokens":10,"total_tokens":110}}}' >> "$n1"
  cp "$n1" "$n2"
  run_cli "$nr" observe --thread TN --from 2026-10-01T09:00:00Z --to 2026-10-01T12:00:00Z --json
  expect_eq dup-file-total 110 "$(jv "$OUT" o.usage.total_tokens)"
  printf '%s\n' '{"timestamp":"2026-10-01T10:30:00Z","type":"token_usage_record","payload":{"thread_id":"TN","usage":{"input_tokens":1,"output_tokens":1,"total_tokens":2}}}' >> "$n2"
  run_cli "$nr" observe --thread TN --from 2026-10-01T09:00:00Z --to 2026-10-01T12:00:00Z --json
  expect_eq noresp-degraded true "$(jv "$OUT" 'o.degraded.includes("missing_field:response_id")')"
  log_pass "TEST-3109 threads are found by id across sessions and archived_sessions"
}

# --- Spec-AC-05 ---------------------------------------------------------------
# tree_home <name> -> P (archived) -> C (sessions AND archived copy) -> G, plus
# D (same parent P, other root session: not part of the run) and U (unrelated).
tree_home() {
  local h p c g d u; h="$(new_home "$1")"
  p="$h/archived_sessions/rollout-p.jsonl"; c="$h/sessions/2026/10/01/rollout-c.jsonl"
  g="$h/sessions/2026/10/01/rollout-g.jsonl"; d="$h/sessions/2026/10/01/rollout-d.jsonl"
  u="$h/sessions/2026/10/01/rollout-u.jsonl"
  mk_meta "$p" P - 2026-10-01T09:00:00Z /repo s-root
  mk_rec "$p" P rp1 2026-10-01T10:00:00Z 10 5 15
  mk_meta "$c" C P 2026-10-01T10:10:00Z /worktree s-root
  mk_rec "$c" C rc1 2026-10-01T10:20:00Z 20 10 30
  cp "$c" "$h/archived_sessions/rollout-c.jsonl"
  mk_meta "$g" G C 2026-10-01T10:30:00Z /guardian s-root
  mk_rec "$g" G rg1 2026-10-01T10:40:00Z 4 2 6
  mk_meta "$d" D P 2026-10-01T10:15:00Z /other s-other
  mk_rec "$d" D rd1 2026-10-01T10:25:00Z 500 500 1000
  mk_meta "$u" U - 2026-10-01T09:00:00Z /elsewhere s-u
  mk_rec "$u" U ru1 2026-10-01T10:00:00Z 900 900 1800
  echo "$h"
}
WIN=(--from 2026-10-01T08:00:00Z --to 2026-10-01T12:00:00Z --json)

test_3110_descendants_no_double_count() {
  local h; h="$(tree_home h3110)"
  local sum=0 t
  for t in P C G; do
    run_cli "$h" observe --thread "$t" "${WIN[@]}"
    expect_eq "rc-$t" 0 "$RC"
    sum=$((sum + $(jv "$OUT" o.usage.total_tokens)))
  done
  expect_eq alone-sum 51 "$sum"
  run_cli "$h" observe --thread P --descendants "${WIN[@]}"
  expect_eq rc 0 "$RC"
  expect_eq total "$sum" "$(jv "$OUT" o.usage.total_tokens)"
  expect_eq input 34 "$(jv "$OUT" o.usage.input_tokens)"
  expect_eq output 17 "$(jv "$OUT" o.usage.output_tokens)"
  expect_eq threads '["P","C","G"]' "$(jv "$OUT" o.threads)"
  expect_eq degraded '[]' "$(jv "$OUT" o.degraded)"
  run_cli "$h" observe --thread C --descendants "${WIN[@]}"
  expect_eq child-tree 36 "$(jv "$OUT" o.usage.total_tokens)"
  log_pass "TEST-3110 descendants sum equals the threads alone; dual-directory child counts once"
}

# --- Spec-AC-06 ---------------------------------------------------------------
write_state_fixture() {
  cat > "$1" <<'YAML'
project_status: active
current_focus:
  type: intake_change
  ref_id: CHANGE-9001
  primary_path: docs/issues/CHANGE-9001-fixture.md
active_work_items:
  - ref_id: CHANGE-9001
    status: done
    phase: validation
    primary_path: docs/issues/CHANGE-9001-fixture.md
    spec_path: docs/specs/SPEC-9001-fixture.md
implementation_strategy:
  selected: loop
  source: docs/specs/SPEC-9001-fixture.md
  rationale: >-
    Fixture strategy rationale.
worktree:
  recommendation: not_needed
  user_decision: waived
  base_ref: main
  branch: null
  path: null
  inline_review_scope: null
  rationale: null
code_review:
  required: false
  status: not_run
  scope: null
  base_ref: main
  head_ref: null
  pr: null
  report_paths: []
  notes: null
last_validation:
  status: pass
  run_at_utc: 2026-07-17T11:00:00Z
  ref_id: CHANGE-9001
  evidence_paths:
    - docs/ai/reports/validation-fixture.md
  notes: null
human_input:
  required: false
  question: null
locks:
  implementation: false
orchestration:
  mode: single
  k: 1
tdd_cycle:
  status: IDLE
  test_id: null
  spec_path: null
  test_path: null
  evidence:
    red: null
    green: null
    refactor: null
metrics:
  work_items:
    CHANGE-9001:
      human_time_minutes:
        intake: null
        reviews: null
      agent_runs: []

updated_at_utc: 2026-07-17T11:00:00Z
YAML
}
write_pricing_fixture() {
  cat > "$1" <<'YAML'
schema_version: 2
lookup_rules:
  order:
    - exact-match
    - unknown-fallback
models:
  claude-test:
    input_usd_per_m: 3.00
    output_usd_per_m: 15.00
  unknown:
    input_usd_per_m: null
    output_usd_per_m: null
YAML
}
# load_flags <json> <key> -> FLAGS array, one element per list item (verbatim)
load_flags() {
  FLAGS=(); local line
  while IFS= read -r line; do FLAGS+=("$line"); done < <(node -e 'for (const x of JSON.parse(process.argv[1])[process.argv[2]]) console.log(x)' "$1" "$2")
}

test_3111_append_run_flush_seam() {
  local h f; h="$(new_home h3111)"; f="$h/sessions/2026/10/01/rollout-a.jsonl"
  mk_meta "$f" T1 - 2026-10-01T09:00:00Z /repo
  mk_rec "$f" T1 r1 2026-10-01T10:00:00Z 100 50 150 40 20
  mk_rec "$f" T1 r2 2026-10-01T10:05:00Z 10 10 20 4 2
  local d="$TMP_ROOT/seam1"; mkdir -p "$d"
  local s="$d/STATE.yaml" m="$d/METRICS.jsonl" tk="$d/TICKS.jsonl" ev="$d/EVENTS.jsonl" pr="$d/PRICING.yaml"
  write_state_fixture "$s"; write_pricing_fixture "$pr"; printf '# header\n' > "$m"; : > "$tk"; : > "$ev"
  run_cli "$h" observe --thread T1 --from 2026-10-01T09:00:00Z --to 2026-10-01T12:00:00Z --json
  expect_eq rc 0 "$RC"
  local ok_json="$OUT"
  load_flags "$ok_json" append_run_flags
  (cd "$PROJECT_ROOT" && env -u AAI_ROLE node .aai/scripts/state.mjs --state "$s" append-run \
    --ref CHANGE-9001 --role Implementation --model claude-test --started 2026-10-01T09:00:00Z "${FLAGS[@]}" > "$d/ar1.log" 2>&1) \
    || log_fail "append-run with printed flags failed: $(cat "$d/ar1.log")"
  run_cli "$h" observe --thread NOPE --from 2026-10-01T09:00:00Z --to 2026-10-01T12:00:00Z --json
  expect_eq rc-unavail 4 "$RC"
  load_flags "$OUT" append_run_flags
  (cd "$PROJECT_ROOT" && env -u AAI_ROLE node .aai/scripts/state.mjs --state "$s" append-run \
    --ref CHANGE-9001 --role Planning --model claude-test --started 2026-10-01T09:00:00Z "${FLAGS[@]}" > "$d/ar2.log" 2>&1) \
    || log_fail "append-run with unavailable flags failed: $(cat "$d/ar2.log")"
  # metrics-flush does not project usage_basis into METRICS; the derived field lives in STATE until the flush.
  node -e 'const t=require("fs").readFileSync(process.argv[1],"utf8");const i=t.indexOf("role: Implementation");process.exit(/usage_basis: field/.test(t.slice(i,i+800))?0:1)' "$s" \
    || log_fail "STATE Implementation run must carry usage_basis: field before the flush"
  (cd "$PROJECT_ROOT" && env -u AAI_ROLE node .aai/scripts/metrics-flush.mjs --state "$s" --metrics "$m" --ticks "$tk" \
    --pricing "$pr" --events "$ev" --now 2026-10-02T12:00:00Z > "$d/flush.log" 2>&1) \
    || log_fail "metrics-flush failed: $(cat "$d/flush.log")"
  local run
  run="$(node -e '
    const L = require("fs").readFileSync(process.argv[1], "utf8").split("\n").filter((l) => l.startsWith("{"));
    const w = JSON.parse(L[L.length - 1]);
    const runs = w.agent_runs || w.runs || [];
    const pick = (r) => ({ role: r.role, harness: r.harness, tokens_in: r.tokens_in, tokens_out: r.tokens_out, tokens_total: r.tokens_total, note: r.note });
    console.log(JSON.stringify(runs.map(pick)));' "$m")"
  expect_eq impl-in 110 "$(jv "$run" 'o.find((r) => r.role === "Implementation").tokens_in')"
  expect_eq impl-out 60 "$(jv "$run" 'o.find((r) => r.role === "Implementation").tokens_out')"
  expect_eq impl-total 170 "$(jv "$run" 'o.find((r) => r.role === "Implementation").tokens_total')"
  expect_eq impl-harness '"codex"' "$(jv "$run" 'o.find((r) => r.role === "Implementation").harness')"
  local tok
  for tok in usage_total_tokens=170 usage_source=codex_rollout codex_thread=T1 \
    usage_interval=2026-10-01T09:00:00Z/2026-10-01T12:00:00Z usage_attribution=run; do
    expect_eq "note-$tok" true "$(jv "$run" "o.find((r) => r.role === \"Implementation\").note.split(/\\s+/).includes(\"$tok\")")"
  done
  expect_eq plan-sentinel true "$(jv "$run" 'o.find((r) => r.role === "Planning").note.split(/\s+/).includes("usage_capture=none")')"
  expect_eq plan-in null "$(jv "$run" 'o.find((r) => r.role === "Planning").tokens_in')"
  expect_eq plan-out null "$(jv "$run" 'o.find((r) => r.role === "Planning").tokens_out')"
  expect_eq plan-total null "$(jv "$run" 'o.find((r) => r.role === "Planning").tokens_total')"
  log_pass "TEST-3111 printed append-run flags round-trip through real state.mjs and metrics-flush"
}

test_3112_log_tick_seam() {
  local h f; h="$(new_home h3112)"; f="$h/sessions/2026/10/01/rollout-a.jsonl"
  mk_meta "$f" T1 - 2026-10-01T09:00:00Z /repo
  mk_rec "$f" T1 r1 2026-10-01T10:00:00Z 100 50 150 40 20
  local d="$TMP_ROOT/seam2"; mkdir -p "$d"
  local s="$d/STATE.yaml" tk="$d/TICKS.jsonl"
  write_state_fixture "$s"; : > "$tk"
  run_cli "$h" observe --thread T1 --from 2026-10-01T09:00:00Z --to 2026-10-01T12:00:00Z --json
  expect_eq rc 0 "$RC"
  load_flags "$OUT" log_tick_flags
  expect_eq tick-flag-count 4 "${#FLAGS[@]}"
  (cd "$PROJECT_ROOT" && env -u AAI_ROLE node .aai/scripts/state.mjs --state "$s" --ticks "$tk" log-tick \
    --tick 1 --role Implementation --scope CHANGE-9001 --started 2026-10-01T09:00:00Z --harness codex "${FLAGS[@]}" > "$d/lt.log" 2>&1) \
    || log_fail "log-tick with printed flags failed: $(cat "$d/lt.log")"
  local line; line="$(node -e 'const L=require("fs").readFileSync(process.argv[1],"utf8").trim().split("\n");console.log(L[L.length-1])' "$tk")"
  expect_eq in 100 "$(jv "$line" o.input_tokens)"
  expect_eq out 50 "$(jv "$line" o.output_tokens)"
  expect_eq no-cache false "$(jv "$line" '"cache_read_tokens" in o')"
  expect_eq no-cost false "$(jv "$line" '"est_cost_usd" in o')"
  log_pass "TEST-3112 printed log-tick flags carry input and output only"
}

# --- Spec-AC-07 ---------------------------------------------------------------
budget_home() { # P (60 + 40 = 100) with child C (50) -> cumulative 150
  local h f c; h="$(new_home "$1")"; f="$h/sessions/2026/10/01/rollout-r.jsonl"; c="$h/sessions/2026/10/01/rollout-c.jsonl"
  mk_meta "$f" R - 2026-10-01T09:00:00Z /repo s-root
  mk_rec "$f" R r1 2026-10-01T10:00:00Z 40 20 60
  mk_rec "$f" R r2 2026-10-01T10:10:00Z 30 10 40
  mk_rec "$f" R r0 2026-10-01T07:00:00Z 9000 9000 18000  # before the run start
  mk_meta "$c" C R 2026-10-01T10:20:00Z /wt s-root
  mk_rec "$c" C rc1 2026-10-01T10:30:00Z 30 20 50
  echo "$h"
}
SINCE=2026-10-01T08:00:00Z

test_3113_budget_verdicts() {
  local h; h="$(budget_home h3113)"
  run_cli "$h" budget --thread R --since "$SINCE" --max-run-tokens 150
  expect_eq rc-equal 3 "$RC"
  run_cli "$h" budget --thread R --since "$SINCE" --max-run-tokens 150 --json
  expect_eq verdict '"exhausted"' "$(jv "$OUT" o.verdict)"
  expect_eq cumulative 150 "$(jv "$OUT" o.cumulative_total_tokens)"
  expect_eq limit 150 "$(jv "$OUT" o.limit)"
  expect_eq enforcement '"active"' "$(jv "$OUT" o.enforcement)"
  run_cli "$h" budget --thread R --since "$SINCE" --max-run-tokens 151 --json
  expect_eq rc-below 0 "$RC"; expect_eq within '"within"' "$(jv "$OUT" o.verdict)"
  run_cli "$h" budget --thread R --since "$SINCE" --max-run-tokens 0
  expect_eq rc-zero 2 "$RC"
  run_cli "$h" budget --thread R --since "$SINCE" --max-run-tokens abc
  expect_eq rc-nan 2 "$RC"
  run_cli "$TMP_ROOT/does-not-exist" budget --thread R --since "$SINCE" --max-run-tokens 150
  expect_eq rc-unreadable 4 "$RC"
  [[ "$OUT" == *"NOT enforced"* ]] || log_fail "unavailable line must say NOT enforced (out: $OUT)"
  [[ "$OUT" != *within* ]] || log_fail "unavailable output must never say within (out: $OUT)"
  run_cli "$TMP_ROOT/does-not-exist" budget --thread R --since "$SINCE" --max-run-tokens 150 --json
  expect_eq unknown '"unknown"' "$(jv "$OUT" o.verdict)"
  expect_eq enf-unavail '"unavailable"' "$(jv "$OUT" o.enforcement)"
  # PR #512 Codex P1: a descendant whose only usage line is malformed has no usage
  # events; its tokens are unknown, so the run budget must not read active/within.
  local x; x="$h/sessions/2026/10/01/rollout-x.jsonl"
  mk_meta "$x" X R 2026-10-01T10:40:00Z /wt s-root
  printf '%s\n' '{"timestamp":"2026-10-01T10:45:00Z","type":"token_usage_record","payload":{"thread_id":"X",' '{"timestamp":"2026-10-01T10:46:00Z","type":"session_meta_tail"}' >> "$x"
  run_cli "$h" budget --thread R --since "$SINCE" --max-run-tokens 1000 --json
  expect_eq rc-desc-unavail 4 "$RC"
  expect_eq enf-desc-unavail '"unavailable"' "$(jv "$OUT" o.enforcement)"
  expect_eq reason-desc-unavail '"descendant_unavailable"' "$(jv "$OUT" o.reason)"
  run_cli "$h" budget --thread R --since "$SINCE" --max-run-tokens 1000
  [[ "$OUT" == *"NOT enforced"* && "$OUT" != *within* ]] || log_fail "unavailable descendant must read NOT enforced, never within (out: $OUT)"
  log_pass "TEST-3113 budget exits 3 at the limit, 0 below, 2 on a bad limit, 4 when unreadable"
}

test_3114_budget_parks_via_unattended_gate() {
  local h; h="$(budget_home h3114)"; local ledger="$TMP_ROOT/gate/ledger.jsonl"
  run_cli "$h" budget --thread R --since "$SINCE" --max-run-tokens 100
  expect_eq budget-rc 3 "$RC"
  local grc=0 gout
  gout="$(cd "$PROJECT_ROOT" && env -u AAI_ROLE node .aai/scripts/unattended-gate.mjs classify --trigger run-budget \
    --ref codex-usage-fixture --ledger "$ledger" --json 2>&1)" || grc=$?
  expect_eq gate-rc 3 "$grc"
  expect_eq gate-decision '"park"' "$(jv "$gout" o.decision)"
  expect_eq gate-class '"cost"' "$(jv "$gout" o.class)"
  run_cli "$TMP_ROOT/does-not-exist" budget --thread R --since "$SINCE" --max-run-tokens 100
  expect_eq unavailable-rc 4 "$RC"
  [[ "$OUT" == *"token budget NOT enforced"* ]] || log_fail "unavailable stdout must name the NOT enforced line (out: $OUT)"
  log_pass "TEST-3114 exhausted budget parks through the real unattended gate; unavailable is named"
}

# --- Spec-AC-08 ---------------------------------------------------------------
attr_home() {
  local h p x; h="$(new_home "$1")"; x="$h/sessions/2026/10/01"
  p="$x/rollout-p.jsonl"
  mk_meta "$p" P - 2026-10-01T09:00:00Z /repo s-root
  mk_rec "$p" P rp1 2026-10-01T10:05:00Z 100 100 200
  mk_rec "$p" P rp2 2026-10-01T12:30:00Z 7 3 10
  mk_meta "$x/rollout-c0.jsonl" C0 P 2026-10-01T09:30:00Z /wt0 s-root
  mk_rec "$x/rollout-c0.jsonl" C0 rc0 2026-10-01T10:15:00Z 1 1 2
  mk_meta "$x/rollout-c1.jsonl" C1 P 2026-10-01T10:10:00Z /wt1 s-root
  mk_rec "$x/rollout-c1.jsonl" C1 rc1 2026-10-01T10:20:00Z 10 10 20
  mk_rec "$x/rollout-c1.jsonl" C1 rc1b 2026-10-01T12:40:00Z 2 2 4
  mk_meta "$x/rollout-g1.jsonl" G1 C1 2026-10-01T10:30:00Z /wtg s-root
  mk_rec "$x/rollout-g1.jsonl" G1 rg1 2026-10-01T10:40:00Z 5 5 10
  mk_meta "$x/rollout-c2.jsonl" C2 P 2026-10-01T11:30:00Z /wt2 s-root
  mk_rec "$x/rollout-c2.jsonl" C2 rc2 2026-10-01T11:40:00Z 3 3 6
  echo "$h"
}

test_3115_attribution_rule() {
  local h; h="$(attr_home h3115)"
  run_cli "$h" attribute --parent P --from 2026-10-01T10:00:00Z --to 2026-10-01T11:00:00Z --json
  expect_eq rc-one 0 "$RC"
  expect_eq one-attr '"thread"' "$(jv "$OUT" o.attribution)"
  expect_eq one-threads '["C1","G1"]' "$(jv "$OUT" o.threads)"
  expect_eq one-total 30 "$(jv "$OUT" o.usage.total_tokens)"
  expect_eq one-note true "$(jv "$OUT" 'o.append_run_flags.some((x) => x.split(/\s+/).includes("usage_attribution=thread"))')"
  run_cli "$h" attribute --parent P --from 2026-10-01T10:00:00Z --to 2026-10-01T12:00:00Z --json
  expect_eq two-attr '"interval"' "$(jv "$OUT" o.attribution)"
  expect_eq two-total 238 "$(jv "$OUT" o.usage.total_tokens)"
  expect_eq two-threads true "$(jv "$OUT" 'o.threads[0] === "P" && o.threads.length === 5')"
  run_cli "$h" attribute --parent P --from 2026-10-01T12:00:00Z --to 2026-10-01T13:00:00Z --json
  expect_eq zero-attr '"interval"' "$(jv "$OUT" o.attribution)"
  expect_eq zero-total 14 "$(jv "$OUT" o.usage.total_tokens)"
  run_cli "$h" attribute --parent NOPE --from 2026-10-01T10:00:00Z --to 2026-10-01T11:00:00Z --json
  expect_eq rc-missing 4 "$RC"
  log_pass "TEST-3115 one spawned child binds the role to its thread; zero or two use the interval"
}

# --- Spec-AC-09 / Spec-AC-10 ----------------------------------------------------
SENTINEL="SENTINEL-Z9Q-do-not-leak"

# fs_listing <dir> -> path, size and mtime of every file (read-only comparison aid)
fs_listing() {
  node -e 'const fs=require("fs"),p=require("path");const w=(d)=>{for(const e of fs.readdirSync(d,{withFileTypes:true})){const f=p.join(d,e.name);if(e.isDirectory())w(f);else{const s=fs.statSync(f);console.log(f,s.size,s.mtimeMs)}}};w(process.argv[1])' "$1"
}

test_3116_privacy_read_only() {
  local h f; h="$(new_home h3116)"; f="$h/sessions/2026/10/01/rollout-a.jsonl"
  printf '{"timestamp":"2026-10-01T09:00:00Z","type":"session_meta","payload":{"id":"T1","session_id":"s-T1","parent_thread_id":null,"timestamp":"2026-10-01T09:00:00Z","cwd":"/repo","source":"cli","base_instructions":{"text":"%s"},"instructions":"%s"}}\n' "$SENTINEL" "$SENTINEL" >> "$f"
  printf '{"timestamp":"2026-10-01T09:30:00Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"%s"}]}}\n' "$SENTINEL" >> "$f"
  printf '{"timestamp":"2026-10-01T09:31:00Z","type":"response_item","payload":{"type":"function_call","name":"shell","arguments":"%s"}}\n' "$SENTINEL" >> "$f"
  printf '{"timestamp":"2026-10-01T09:32:00Z","type":"response_item","payload":{"type":"function_call_output","output":"%s"}}\n' "$SENTINEL" >> "$f"
  printf '{"timestamp":"2026-10-01T09:33:00Z","type":"event_msg","payload":{"type":"agent_message","message":"%s"}}\n' "$SENTINEL" >> "$f"
  mk_rec "$f" T1 r1 2026-10-01T10:00:00Z 10 5 15
  local c="$h/sessions/2026/10/01/rollout-c.jsonl"
  printf '{"timestamp":"2026-10-01T09:40:00Z","type":"session_meta","payload":{"id":"C1","session_id":"s-T1","parent_thread_id":"T1","timestamp":"2026-10-01T09:40:00Z","cwd":"/wt","source":"cli","base_instructions":"%s"}}\n' "$SENTINEL" >> "$c"
  mk_rec "$c" C1 rc1 2026-10-01T10:10:00Z 1 1 2
  local before_fs before_git all="" sub
  before_fs="$(fs_listing "$h")"; before_git="$(cd "$PROJECT_ROOT" && git status --porcelain)"
  local W=(--from 2026-10-01T08:00:00Z --to 2026-10-01T12:00:00Z)
  for sub in "observe --thread T1 --descendants" "attribute --parent T1" "budget --thread T1 --since 2026-10-01T08:00:00Z --max-run-tokens 1000" "probe --thread T1"; do
    case "$sub" in
      budget*) run_cli "$h" $sub --json; all="$all$OUT" ;;
      probe*) run_cli "$h" $sub --json; all="$all$OUT"; expect_eq probe-json-rc 0 "$RC"; run_cli "$h" $sub; all="$all$OUT"; expect_eq probe-rc 0 "$RC" ;;
      *) run_cli "$h" $sub "${W[@]}" --json; all="$all$OUT"; run_cli "$h" $sub "${W[@]}"; all="$all$OUT" ;;
    esac
  done
  run_cli "$h" observe --thread T1 --descendants "${W[@]}" --json
  expect_eq observed-total 17 "$(jv "$OUT" o.usage.total_tokens)"
  [[ "$all" != *"$SENTINEL"* ]] || log_fail "sentinel leaked into command output"
  [[ "$all" != *"base_instructions"* ]] || log_fail "base_instructions key leaked into command output"
  expect_eq fs-unchanged "$before_fs" "$(fs_listing "$h")"
  expect_eq git-unchanged "$before_git" "$(cd "$PROJECT_ROOT" && git status --porcelain)"
  [[ -z "$(ls -A "$TMP_ROOT/home")" ]] || log_fail "HOME must stay empty (CODEX_HOME must be honored)"
  log_pass "TEST-3116 sentinel content never reaches output; fixture and repository are untouched"
}

test_3117_probe_capabilities() {
  local h f; h="$(new_home h3117)"; f="$h/sessions/2026/10/01/rollout-a.jsonl"
  mk_meta "$f" T1 - 2026-10-01T09:00:00Z /repo
  mk_rec "$f" T1 r1 2026-10-01T10:00:00Z 10 5 15
  run_cli "$h" probe --thread T1 --json
  expect_eq avail-rc 0 "$RC"
  expect_eq avail-logs '"available"' "$(jv "$OUT" o.rollout_logs.status)"
  expect_eq avail-dirs 2 "$(jv "$OUT" o.rollout_logs.dirs.length)"
  expect_eq avail-ident '"resolved"' "$(jv "$OUT" o.thread_identity.status)"
  expect_eq avail-src '"flag"' "$(jv "$OUT" o.thread_identity.source)"
  expect_eq avail-app '"not_integrated"' "$(jv "$OUT" o.app_server_token_events)"
  run_cli "$TMP_ROOT/does-not-exist" probe --json
  expect_eq missing-rc 0 "$RC"
  expect_eq missing-logs '"unavailable"' "$(jv "$OUT" o.rollout_logs.status)"
  expect_eq missing-reason '"source_unreadable"' "$(jv "$OUT" o.rollout_logs.reason)"
  expect_eq missing-ident '"unresolved"' "$(jv "$OUT" o.thread_identity.status)"
  expect_eq missing-app '"not_integrated"' "$(jv "$OUT" o.app_server_token_events)"
  local out rc=0
  out="$(CODEX_THREAD_ID=T1 CODEX_HOME="$h" HOME="$TMP_ROOT/home" node "$CLI" probe --json 2>&1)" || rc=$?
  expect_eq env-rc 0 "$rc"
  expect_eq env-ident '"resolved"' "$(jv "$out" o.thread_identity.status)"
  expect_eq env-src '"env"' "$(jv "$out" o.thread_identity.source)"
  expect_eq env-app '"not_integrated"' "$(jv "$out" o.app_server_token_events)"
  log_pass "TEST-3117 probe reports logs, identity source and never integrates App Server events"
}

# --- Spec-AC-11 -----------------------------------------------------------------
test_3118_prose_wiring_pins() {
  local sl="$PROJECT_ROOT/.aai/SKILL_LOOP.prompt.md" sp="$PROJECT_ROOT/.aai/SUBAGENT_PROTOCOL.md" t
  for t in "codex-usage.mjs budget" "exit 3" "exit 4" "NOT enforced" "run-budget" "max_ticks"; do
    grep -qF -- "$t" "$sl" || log_fail "SKILL_LOOP step 2f must name [$t]"
  done
  for t in "codex-usage.mjs observe" "codex-usage.mjs attribute" "--cache-read" "no cost" "one direct child"; do
    grep -qF -- "$t" "$sp" || log_fail "SUBAGENT_PROTOCOL Codex bullet must name [$t]"
  done
  log_pass "TEST-3118 SKILL_LOOP 2f and SUBAGENT_PROTOCOL carry the Codex wiring"
}

test_3119_registration_pins() {
  local prof="$PROJECT_ROOT/.aai/system/PROFILES.yaml" t sel
  for t in "  - .aai/scripts/codex-usage.mjs" "  - .aai/scripts/lib/codex-rollout.mjs"; do
    grep -qxF -- "$t" "$prof" || log_fail "PROFILES core must list [$t]"
  done
  sel="$(cd "$PROJECT_ROOT" && printf '%s\n' .aai/scripts/codex-usage.mjs .aai/scripts/live-parsers/codex.mjs \
    | node .aai/scripts/select-suites.mjs --files-from - 2>&1)" || log_fail "select-suites failed: $sel"
  grep -qE "^SELECTED aai-codex-usage( |$)" <<<"$sel" || log_fail "suite-map must select aai-codex-usage (got: ${sel:0:200})"
  grep -qE "import \{[^}]*codexHome[^}]*\} from '\.\./lib/codex-rollout\.mjs'" "$PROJECT_ROOT/.aai/scripts/live-parsers/codex.mjs" \
    || log_fail "live-parsers/codex.mjs must import codexHome from the lib"
  log_pass "TEST-3119 PROFILES core, suite-map row and the live parser's shared codexHome"
}

# TEST-3120 (Claude capture preserved) lives in test-aai-token-capture.sh (test_014) plus the
# seven neighbour suites run through aai-run-tests.sh; the protected-file diff against the base is
# a ride-time evidence command, not a suite arm (a bare main ref is not CI-safe, ISSUE-0038).

# --- Spec-AC-12 (opt-in) ----------------------------------------------------------
test_3121_real_smoke_opt_in() {
  if [[ "${AAI_CODEX_SMOKE:-}" != "1" ]]; then echo "SKIP: TEST-3121 opt-in real smoke (set AAI_CODEX_SMOKE=1)"; return 0; fi
  local real="${CODEX_HOME:-$HOME/.codex}"
  [[ -d "$real/sessions" ]] || log_fail "AAI_CODEX_SMOKE=1 but $real/sessions is not readable"
  local pick
  pick="$(node -e '
    const fs=require("fs"),p=require("path");
    const files=[];const w=(d)=>{let es;try{es=fs.readdirSync(d,{withFileTypes:true})}catch{return}for(const e of es){const f=p.join(d,e.name);if(e.isDirectory())w(f);else if(e.name.endsWith(".jsonl"))files.push([f,fs.statSync(f).mtimeMs])}};
    w(p.join(process.argv[1],"sessions"));files.sort((a,b)=>b[1]-a[1]);
    for(const [f] of files){let id=null,last=null,n=0;
      for(const l of fs.readFileSync(f,"utf8").split("\n")){let o;try{o=JSON.parse(l)}catch{continue}
        if(o.type==="session_meta"&&id===null)id=o.payload&&o.payload.id;
        if(o.type==="token_usage_record"&&o.payload&&o.payload.thread_id===id){n++;const t=o.payload.thread_token_usage;if(t&&typeof t.total_tokens==="number")last=t.total_tokens}}
      if(id&&n>0&&last!==null){console.log(JSON.stringify({id,records:n,last_total:last}));process.exit(0)}}
    console.log("null")' "$real")"
  [[ "$pick" != "null" ]] || { echo "SKIP: TEST-3121 no real thread with token_usage_record"; return 0; }
  local id; id="$(jv "$pick" o.id | tr -d '"')"
  local out rc=0
  out="$(CODEX_HOME="$real" node "$CLI" observe --thread "$id" --json 2>&1)" || rc=$?
  expect_eq smoke-rc 0 "$rc"
  OUT="$out"
  expect_eq smoke-total "$(jv "$pick" o.last_total)" "$(jv "$out" o.usage.total_tokens)"
  local probe; probe="$(CODEX_HOME="$real" node "$CLI" probe --json 2>&1)" || true
  local rep="$PROJECT_ROOT/docs/ai/reports/codex-usage-smoke-codex-usage-missing-from-run-budgets.md"
  mkdir -p "$PROJECT_ROOT/docs/ai/reports"
  {
    echo "# Codex usage real smoke (metadata only)"
    echo
    echo "- generated_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "- thread_id: $id"
    echo "- token_usage_records: $(jv "$pick" o.records)"
    echo "- last_thread_token_usage_total (independent): $(jv "$pick" o.last_total)"
    echo "- observe total_tokens: $(jv "$out" o.usage.total_tokens)"
    echo "- observe basis: $(jv "$out" o.basis)"
    echo "- observe degraded: $(jv "$out" o.degraded)"
    echo "- probe rollout_logs: $(jv "$probe" o.rollout_logs.status)"
    echo "- probe thread_identity: $(jv "$probe" o.thread_identity.status) (CODEX_THREAD_ID set: $([[ -n "${CODEX_THREAD_ID:-}" ]] && echo yes || echo no))"
    echo "- probe app_server_token_events: $(jv "$probe" o.app_server_token_events)"
  } > "$rep"
  log_pass "TEST-3121 real smoke total matches the last record; report $rep"
}

ALL_TESTS=(
  test_3101_record_window_sums
  test_3102_response_id_dedupe
  test_3103_subset_semantics
  test_3104_cumulative_delta_and_reset
  test_3105_cumulative_compaction_flag
  test_3106_missing_partial_malformed
  test_3107_unavailable_reasons
  test_3108_first_meta_identity
  test_3109_archived_and_cwd_change
  test_3110_descendants_no_double_count
  test_3111_append_run_flush_seam
  test_3112_log_tick_seam
  test_3113_budget_verdicts
  test_3114_budget_parks_via_unattended_gate
  test_3115_attribution_rule
  test_3116_privacy_read_only
  test_3117_probe_capabilities
  test_3118_prose_wiring_pins
  test_3119_registration_pins
  test_3121_real_smoke_opt_in
)

main() {
  echo "=== Test Suite: $TEST_NAME ==="
  check_deps
  local t fn
  if [[ "${1:-}" == "--test" ]]; then
    t="${2:-}"
    [[ "$t" =~ ^TEST-[0-9]+$ ]] || log_fail "--test wants TEST-<n>, got [$t]"
    fn="$(compgen -A function "test_${t#TEST-}_" | qhead -n1)" || fn=""
    [[ -n "$fn" ]] || log_fail "no test function for $t"
    run_one "$fn"
    return 0
  fi
  if [[ $# -ge 1 ]]; then
    declare -F "$1" >/dev/null 2>&1 || log_fail "unknown test function: $1"
    run_one "$1"
    return 0
  fi
  for t in "${ALL_TESTS[@]}"; do run_one "$t"; done
  echo "=== All $TEST_NAME tests passed ==="
}

main "$@"
