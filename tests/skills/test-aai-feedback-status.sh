#!/usr/bin/env bash
#
# Test: RFC-0012 friction feedback DISCOVERY status
# (.aai/scripts/aai-feedback-status.mjs).
#
# Offline counts (spool observations + pending drafts) + a read-only gh auth
# probe (mocked). No mutation, no network beyond `gh auth status`.

set -u
TEST_NAME="test-aai-feedback-status"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/assert-payload.sh
. "$SCRIPT_DIR/lib/assert-payload.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"
SCRIPT="$PROJECT_ROOT/.aai/scripts/aai-feedback-status.mjs"

cleanup() { [ -n "${TD:-}" ] && [ -z "${KEEP_TEST_DIR:-}" ] && rm -rf "$TD"; }
trap cleanup EXIT
log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_info() { echo "INFO: $*"; }
log_skip() { echo "SKIP: $*"; exit 42; }
command -v node >/dev/null 2>&1 || log_skip "node not found"
[ -f "$SCRIPT" ] || log_fail "status script missing: $SCRIPT"

setup() {
  TD="$(mktemp -d "${TMPDIR:-/tmp}/aai-fbstatus.XXXXXX")"
  mkdir -p "$TD/friction/pending-issues" "$TD/bin"
  printf '{"a":1}\n{"a":2}\n{"a":3}\n' > "$TD/friction/observations.jsonl"
  : > "$TD/friction/pending-issues/v1_x.md"; : > "$TD/friction/pending-issues/v1_y.md"
  GH_CALLS="$TD/gh_calls"; : > "$GH_CALLS"
}
# mock gh with a controllable exit code ($1)
mock_gh() { printf '#!/usr/bin/env bash\necho "$@" >> "%s"\nexit %s\n' "$GH_CALLS" "$1" > "$TD/bin/gh"; chmod +x "$TD/bin/gh"; }
run() { AAI_FRICTION_DIR="$1" AAI_GH_BIN="${2:-$TD/bin/gh}" node "$SCRIPT" "${@:3}"; }
jq_field() { node -e 'const r=JSON.parse(require("fs").readFileSync(0,"utf8"));process.stdout.write(String(r[process.argv[1]]))' "$1"; }

# --- TEST-001: counts observations + drafts --------------------------------
test_001_counts() {
  log_info "Test: reports the spool observation count and pending-draft count (TEST-001)..."
  mock_gh 0
  local out; out="$(run "$TD/friction" "$TD/bin/gh" --json)"
  [ "$(printf '%s' "$out" | jq_field observations)" = "3" ] || log_fail "TEST-001: observations must be 3"
  [ "$(printf '%s' "$out" | jq_field drafts)" = "2" ] || log_fail "TEST-001: drafts must be 2"
  log_pass "counts observations (3) and pending drafts (2); valid --json (TEST-001)"
}

# --- TEST-002: gh state (ready / unauth / absent) --------------------------
test_002_gh_state() {
  log_info "Test: reports gh state without ever failing the caller (TEST-002)..."
  mock_gh 0
  [ "$(run "$TD/friction" "$TD/bin/gh" --json | jq_field gh)" = "ready" ] || log_fail "TEST-002: authed gh -> ready"
  mock_gh 1
  local out; out="$(run "$TD/friction" "$TD/bin/gh")"; local code=$?
  [ "$code" = "0" ] || log_fail "TEST-002: must never fail the caller (exit $code)"
  assert_payload_contains_i "$out" "gh auth login" "TEST-002: unauthenticated gh -> 'gh auth login' hint"
  [ "$(run "$TD/friction" "/nonexistent/gh" --json | jq_field gh)" = "absent" ] || log_fail "TEST-002: missing gh -> absent"
  log_pass "gh state ready/unauthenticated/absent surfaced; caller never fails (TEST-002)"
}

# --- TEST-003: no mutation / offline for counts ----------------------------
test_003_no_mutation() {
  log_info "Test: no mutating gh call; only a read-only auth probe (TEST-003)..."
  # static: no mutating gh CALL (quoted array args) — the `next:` hint text may
  # name the upsert/--confirm command, but the script itself must not invoke it.
  grep -qE "'issue'|'create'|-X POST|createIssue|'--confirm'" "$SCRIPT" && log_fail "TEST-003: status must have no mutating gh call site" || true
  mock_gh 0; : > "$GH_CALLS"
  run "$TD/friction" "$TD/bin/gh" >/dev/null
  # POSITIVE CONTROL (fu-learned-positive-control-for-absence): the absence
  # check below proves nothing if gh was never invoked at all — assert the
  # read-only probe actually ran before trusting its silence.
  [ -s "$GH_CALLS" ] || log_fail "TEST-003: \$GH_CALLS is empty — gh was never invoked, so the absence-of-mutation check below proves nothing"
  # the ONLY gh call may be `auth status` (read-only)
  if grep -vqE "^auth status$" "$GH_CALLS" && [ -s "$GH_CALLS" ]; then
    grep -qE "issue create|-X POST" "$GH_CALLS" && log_fail "TEST-003: made a mutating gh call: $(cat "$GH_CALLS")"
  fi
  log_pass "no mutating gh call; only read-only auth status (TEST-003)"
}

# --- TEST-004: empty spool -> SILENT (no output), exit 0 -------------------
# The wrap-up nudge (SKILL_WRAP_UP step 6) must be silent when nothing is
# captured — it prints its output verbatim ONLY when non-silent. So the human
# path must emit NOTHING on an empty loop (bot-review P2: Copilot + Codex).
test_004_empty() {
  log_info "Test: nothing captured -> SILENT (empty stdout), exit 0 (TEST-004)..."
  mock_gh 0
  local out; out="$(run "$TD/empty" "$TD/bin/gh")"; local code=$?
  [ "$code" = "0" ] || log_fail "TEST-004: empty must exit 0"
  [ -z "$out" ] || log_fail "TEST-004: empty must be SILENT (no stdout), got: $out"
  # --json still emits the object even when empty (a programmatic caller wants the zeros).
  local jout; jout="$(run "$TD/empty" "$TD/bin/gh" --json)"
  [ "$(printf '%s' "$jout" | jq_field observations)" = "0" ] || log_fail "TEST-004: --json must still emit observations:0 when empty"
  log_pass "empty spool -> SILENT human line, --json still emits, exit 0 (TEST-004)"
}

# write_report <dir> <total_observations> <candidate_count> — writes a
# minimal but real triage-report.json shape (aai-feedback-triage.mjs's own
# REPORT_SCHEMA) with exactly <candidate_count> review_candidate clusters
# among 5 total clusters, so `candidates` is unambiguous.
write_report() {
  local dir="$1" total="$2" cands="$3"
  node -e '
    const fs = require("fs");
    const [dir, total, cands] = process.argv.slice(1);
    const n = Number(cands);
    const clusters = [];
    for (let i = 0; i < 5; i++) {
      clusters.push({
        fingerprint: "v1:c" + i,
        failure_class: "deterministic_script_failure",
        harness: "claude",
        recurrence: 1,
        score: i < n ? 9 : 1,
        decision: i < n ? "review_candidate" : "retain",
        auto_publishable: false,
      });
    }
    const report = {
      schema: "aai-triage/v1", mode: "local", threshold: 4,
      total_observations: Number(total), kept: Number(total), dropped: [], clusters,
    };
    fs.writeFileSync(dir + "/triage-report.json", JSON.stringify(report, null, 2) + "\n");
  ' "$dir" "$total" "$cands"
}

# --- TEST-669 (Spec-AC-11): backlog reporting across four fixture dirs -----
test_669_status_reports_the_backlog() {
  log_info "Test: candidates/report_observations/report_stale reported correctly across six fixture friction dirs (TEST-669)..."
  mock_gh 0

  # Arm 1: no report at all. observations.jsonl already has 3 lines (setup).
  local out
  out="$(run "$TD/friction" "$TD/bin/gh" --json)"
  [ "$(printf '%s' "$out" | jq_field candidates)" = "0" ] || log_fail "TEST-669 arm1: candidates must be 0 with no report"
  [ "$(printf '%s' "$out" | jq_field report_observations)" = "0" ] || log_fail "TEST-669 arm1: report_observations must be 0 with no report"
  [ "$(printf '%s' "$out" | jq_field report_stale)" = "true" ] || log_fail "TEST-669 arm1: report_stale must be true with no report"
  out="$(run "$TD/friction" "$TD/bin/gh")"
  assert_payload_contains "$out" "report: none yet" "TEST-669 arm1: human line must say 'report: none yet'"

  # Arm 2: report matches the spool exactly (3 observations, 2 candidates).
  write_report "$TD/friction" 3 2
  out="$(run "$TD/friction" "$TD/bin/gh" --json)"
  [ "$(printf '%s' "$out" | jq_field candidates)" = "2" ] || log_fail "TEST-669 arm2: candidates must be 2"
  [ "$(printf '%s' "$out" | jq_field report_observations)" = "3" ] || log_fail "TEST-669 arm2: report_observations must be 3"
  [ "$(printf '%s' "$out" | jq_field report_stale)" = "false" ] || log_fail "TEST-669 arm2: report_stale must be false when the report matches the spool"

  # Arm 3: report BEHIND the spool, drafts present — reproduces the measured
  # 65-against-824 shape (spec-friction-channel-sweep "What is established").
  local d3="$TD/d3/friction"; mkdir -p "$d3/pending-issues"
  node -e 'const fs=require("fs");let s="";for(let i=0;i<824;i++)s+=JSON.stringify({a:i})+"\n";fs.writeFileSync(process.argv[1],s);' "$d3/observations.jsonl"
  write_report "$d3" 65 3
  for i in 1 2 3 4 5 6 7; do : > "$d3/pending-issues/v1_x$i.md"; done
  out="$(run "$d3" "$TD/bin/gh" --json)"
  [ "$(printf '%s' "$out" | jq_field observations)" = "824" ] || log_fail "TEST-669 arm3: observations must be 824"
  [ "$(printf '%s' "$out" | jq_field drafts)" = "7" ] || log_fail "TEST-669 arm3: drafts must be 7"
  [ "$(printf '%s' "$out" | jq_field candidates)" = "3" ] || log_fail "TEST-669 arm3: candidates must be 3"
  [ "$(printf '%s' "$out" | jq_field report_observations)" = "65" ] || log_fail "TEST-669 arm3: report_observations must be 65"
  [ "$(printf '%s' "$out" | jq_field report_stale)" = "true" ] || log_fail "TEST-669 arm3: report_stale must be true (65 != 824)"
  out="$(run "$d3" "$TD/bin/gh")"
  assert_payload_contains "$out" "report STALE (65 of 824 triaged)" "TEST-669 arm3: human line must name BOTH numbers"

  # Arm 4: empty spool (no observations, no drafts, no report).
  out="$(run "$TD/empty" "$TD/bin/gh" --json)"
  [ "$(printf '%s' "$out" | jq_field candidates)" = "0" ] || log_fail "TEST-669 arm4: candidates must be 0 on an empty spool"
  [ "$(printf '%s' "$out" | jq_field report_observations)" = "0" ] || log_fail "TEST-669 arm4: report_observations must be 0 on an empty spool"

  # Arm 5 (PR #394 bot review F1): the spool carries ONE malformed line (what
  # a crashed or concurrent writer leaves) next to 3 parseable ones. Before
  # the shared predicate (lib/friction-spool.mjs), `observations` counted
  # every non-blank line (4) while the triage engine's own
  # `total_observations` counts only PARSEABLE lines (3) — so a report whose
  # total matches the triage engine's count could never match `observations`
  # and `report_stale` was pinned true FOREVER, even immediately after a
  # fresh, fully-current triage run. The surface must count what triage
  # counts.
  local d5="$TD/d5/friction"; mkdir -p "$d5"
  printf '{"a":1}\n{"a":2}\nnot valid json\n{"a":3}\n' > "$d5/observations.jsonl"
  write_report "$d5" 3 1
  out="$(run "$d5" "$TD/bin/gh" --json)"
  [ "$(printf '%s' "$out" | jq_field observations)" = "3" ] \
    || log_fail "TEST-669 arm5 (F1): observations must count only the 3 PARSEABLE lines, one malformed line present, got: $(printf '%s' "$out" | jq_field observations)"
  [ "$(printf '%s' "$out" | jq_field report_stale)" = "false" ] \
    || log_fail "TEST-669 arm5 (F1): report_stale must be false once the report's total matches the PARSEABLE count, a malformed line must not pin it stale forever"

  # Arm 6 (PR #394 bot review F2): an EMPTY spool next to a report that
  # PARSES as JSON but is structurally wrong (`clusters` is not an array,
  # `total_observations` is 0) — the exact shape that reads as a healthy,
  # CURRENT report before the fix, because `0 !== 0` alongside an unvalidated
  # `clusters: "corrupt"` normalized to zero candidates. This must fail
  # closed exactly like an absent report instead.
  local d6="$TD/d6/friction"; mkdir -p "$d6"
  printf '{"total_observations":0,"clusters":"corrupt"}\n' > "$d6/triage-report.json"
  out="$(run "$d6" "$TD/bin/gh" --json)"
  [ "$(printf '%s' "$out" | jq_field report_stale)" = "true" ] \
    || log_fail "TEST-669 arm6 (F2): a structurally invalid report (clusters not an array) alongside an empty spool must still read report_stale=true, fail closed like an absent report, got: $(printf '%s' "$out" | jq_field report_stale)"
  [ "$(printf '%s' "$out" | jq_field report_observations)" = "0" ] \
    || log_fail "TEST-669 arm6 (F2): report_observations must be 0 for a structurally invalid report"

  # Arm 6b: same structurally invalid report, but with one observation and
  # one draft present so the human line actually prints — proves the
  # invalid report surfaces exactly like an absent one ("report: none yet"),
  # not silently as a current, healthy report.
  local d6b="$TD/d6b/friction"; mkdir -p "$d6b/pending-issues"
  printf '{"a":1}\n' > "$d6b/observations.jsonl"
  : > "$d6b/pending-issues/v1_z.md"
  printf '{"total_observations":0,"clusters":"corrupt"}\n' > "$d6b/triage-report.json"
  out="$(run "$d6b" "$TD/bin/gh")"
  assert_payload_contains "$out" "report: none yet" "TEST-669 arm6b (F2): a structurally invalid report must surface exactly like an absent one"

  log_pass "candidates/report_observations/report_stale correct across all fixture arms, including a malformed spool line (F1) and a structurally invalid report (F2); human line names both numbers when stale (TEST-669)"
}

# --- TEST-670 (Spec-AC-11): stale report never advertises a publish -------
test_670_stale_report_never_advertises_publish() {
  log_info "Test: next names triage (never publish) whenever the report is absent/stale, even with drafts present; a current report still advertises publish; the empty arm stays silent on stdout (TEST-670)..."
  mock_gh 0

  # Drafts present (setup: 2 drafts) + a STALE report (report says 1, spool has 3).
  write_report "$TD/friction" 1 0
  local out; out="$(run "$TD/friction" "$TD/bin/gh" --json)"
  case "$(printf '%s' "$out" | jq_field next)" in
    *aai-feedback-triage.mjs*) : ;;
    *) log_fail "TEST-670: with drafts present and a STALE report, next must name triage, got: $(printf '%s' "$out" | jq_field next)" ;;
  esac
  case "$(printf '%s' "$out" | jq_field next)" in
    *--confirm*) log_fail "TEST-670: next must NEVER advertise a publish while the report is stale, got: $(printf '%s' "$out" | jq_field next)" ;;
    *) : ;;
  esac

  # Drafts present + a CURRENT report (matches the 3-line spool): next
  # reverts to the ordinary publish advertisement.
  write_report "$TD/friction" 3 1
  out="$(run "$TD/friction" "$TD/bin/gh" --json)"
  case "$(printf '%s' "$out" | jq_field next)" in
    *--confirm*) : ;;
    *) log_fail "TEST-670: with drafts present and a CURRENT report, next must advertise the publish, got: $(printf '%s' "$out" | jq_field next)" ;;
  esac

  # Empty spool: stdout stays SILENT (pinned TEST-004 contract), --json still
  # emits the full object including the new fields.
  local human; human="$(run "$TD/empty" "$TD/bin/gh")"
  [ -z "$human" ] || log_fail "TEST-670: empty spool must stay SILENT on stdout even with the new fields, got: $human"
  out="$(run "$TD/empty" "$TD/bin/gh" --json)"
  [ "$(printf '%s' "$out" | jq_field report_stale)" = "true" ] || log_fail "TEST-670: empty arm --json must still emit report_stale"

  log_pass "next names triage over a stale/absent report even with drafts present, reverts to publish once current, and the empty arm stays silent (TEST-670)"
}

main() {
  echo "=== $TEST_NAME ==="
  setup
  if [ $# -gt 0 ]; then
    declare -F "$1" >/dev/null || { echo "Unknown test: $1" >&2; exit 2; }
    "$1"; echo "=== $TEST_NAME: SELECTED PASSED ($1) ==="; return
  fi
  test_001_counts
  test_002_gh_state
  test_003_no_mutation
  test_004_empty
  test_669_status_reports_the_backlog
  test_670_stale_report_never_advertises_publish
  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}
main "$@"
