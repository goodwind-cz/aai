#!/usr/bin/env bash
#
# Test: aai-overview — token economics overview v2
# (docs/specs/SPEC-DRAFT-spec-token-economics-end-to-end.md, TEST-005..007).
#
# Verifies .aai/scripts/generate-overview.mjs:
#   - TEST-005 (Spec-AC-04): overview-data.json per-item token total equals
#     the sum of valid usage_total_tokens=<N> markers across that item's
#     METRICS.jsonl runs (via the shared lib/usage-note.mjs); the counts row
#     exposes the grand total of recorded tokens across delivered items.
#   - TEST-006 (Spec-AC-04, SEAM 2): the overview per-item token sum equals
#     metrics-report.mjs's per-item sum on the SAME METRICS.jsonl fixture —
#     one fixture crossing both consumers, not two mocked unit tests.
#   - TEST-007 (Spec-AC-05): Delivered grouping — a delivered item whose ref
#     is named in a release doc's frontmatter links.members list renders
#     under that release heading; an item named by no release falls back to
#     a close-month group derived from its close date.
#
# ALL fixtures are scratch temp-dir repos (generate-overview.mjs/metrics-
# report.mjs always run with cwd = the fixture dir via --output/--metrics
# flags or a subshell cd) — the real docs/ tree is NEVER touched.
# bash 3.2 compatible (no ${var^^}, no declare -A).
#
# Usage:
#   bash tests/skills/test-aai-overview.sh            # run all tests
#   bash tests/skills/test-aai-overview.sh test_005_per_item_tokens_and_grand_total
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-overview"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OVERVIEW="$PROJECT_ROOT/.aai/scripts/generate-overview.mjs"
REPORT="$PROJECT_ROOT/.aai/scripts/metrics-report.mjs"

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then
    echo "INFO: keeping fixture at $TEST_DIR"
    return 0
  fi
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
  [[ -f "$OVERVIEW" ]] || log_fail "generate-overview.mjs not found: $OVERVIEW"
  [[ -f "$REPORT" ]] || log_fail "metrics-report.mjs not found: $REPORT"
  log_pass "Dependencies checked"
}

setup_fixture() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-overview-test.XXXXXX")"
}

# --- fixture builders ---------------------------------------------------------

# mk_repo <name> -> echoes fixture repo dir with the docs/ scan layout
# generate-overview.mjs reads (missing dirs are tolerated by the generator).
mk_repo() {
  local d="$TEST_DIR/$1"
  rm -rf "$d"
  mkdir -p "$d/docs/issues" "$d/docs/specs" "$d/docs/releases" "$d/docs/ai/reports" "$d/docs/ai/reviews"
  : > "$d/docs/ai/EVENTS.jsonl"
  printf '%s' "$d"
}

write_change_doc() {  # $1 path $2 id $3 status
  cat > "$1" <<EOF
---
id: $2
type: change
status: $3
links:
  pr: []
  commits: []
---

# Change — Fixture $2

## Summary
- fixture doc for overview tests.
EOF
}

# write_release_doc <path> <id> <member1> [member2...] — an additive
# frontmatter links.members block list; call with no members for the
# close-month-fallback fixture (REL-0001-shaped: carries none).
write_release_doc() {
  local path="$1" id="$2"
  shift 2
  {
    echo "---"
    echo "id: $id"
    echo "type: release"
    echo "status: done"
    echo "links:"
    echo "  pr: []"
    echo "  commits: []"
    if [[ $# -gt 0 ]]; then
      echo "  members:"
      local m
      for m in "$@"; do
        echo "    - $m"
      done
    fi
    echo "---"
    echo ""
    echo "# Release $id"
  } > "$path"
}

write_closed_event() {  # $1 events file $2 ref $3 ts
  printf '{"v":1,"ts":"%s","actor":"test","event":"work_item_closed","ref":"%s","payload":{}}\n' "$3" "$2" >> "$1"
}

write_pricing() {
  cat > "$1" <<'YAML'
schema_version: 2
lookup_rules:
  order:
    - strip-bracket-suffix
    - model-aliases
    - exact-match
    - longest-prefix
    - unknown-fallback
model_aliases: {}
models:
  unknown:
    input_usd_per_m: null
    output_usd_per_m: null
YAML
}

# run_overview <dir> -> writes overview-data.json + overview.html into <dir>,
# combined output in $OUT, exit code in $EC.
OUT=""
EC=0
run_overview() {
  local d="$1"
  OUT="$d/overview-run.log"
  EC=0
  (cd "$d" && node "$OVERVIEW" --output "$d/docs/ai/overview.html" > "$OUT" 2>&1) || EC=$?
}

data_json() { cat "$1/docs/ai/overview-data.json"; }

node_get() {  # node_get <json-file> <js-expr-using-m> — prints result
  node -e '
    const fs = require("fs");
    const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const expr = process.argv[2];
    // eslint-disable-next-line no-eval
    process.stdout.write(String(eval(expr)));
  ' "$1" "$2"
}

# --- TEST-005 (Spec-AC-04): per-item tokens + grand total ---------------------

test_005_per_item_tokens_and_grand_total() {
  log_info "Test: overview per-item token total equals METRICS marker sums; counts grand total equals the sum across delivered items (token-economics TEST-005)..."
  local d
  d="$(mk_repo t005)"
  write_change_doc "$d/docs/issues/CHANGE-0001-t005a.md" "CHG-T005A" "done"
  write_change_doc "$d/docs/issues/CHANGE-0002-t005b.md" "CHG-T005B" "done"
  write_closed_event "$d/docs/ai/EVENTS.jsonl" "CHG-T005A" "2026-07-10T12:00:00Z"
  write_closed_event "$d/docs/ai/EVENTS.jsonl" "CHG-T005B" "2026-07-10T13:00:00Z"
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-10","ref_id":"CHG-T005A","title":"Alpha","human_time_minutes":{"intake":0,"reviews":0},"agent_runs":[{"role":"Implementation","model_id":"m","tokens_in":null,"tokens_out":null,"cost_usd":null,"note":"usage_total_tokens=1500 (harness total)"},{"role":"Validation","model_id":"m","tokens_in":null,"tokens_out":null,"cost_usd":null,"note":"usage_total_tokens=500x (malformed, ignored)"}],"totals":{"human_time_minutes":0,"agent_duration_seconds":0,"total_cost_usd":null},"verdict":"PASS"}
{"date_utc":"2026-07-10","ref_id":"CHG-T005B","title":"Beta","human_time_minutes":{"intake":0,"reviews":0},"agent_runs":[{"role":"Implementation","model_id":"m","tokens_in":null,"tokens_out":null,"cost_usd":null,"note":"usage_total_tokens=2500 (harness total)"}],"totals":{"human_time_minutes":0,"agent_duration_seconds":0,"total_cost_usd":null},"verdict":"PASS"}
JSONL
  run_overview "$d"
  [[ "$EC" == 0 ]] || log_fail "overview must exit 0: $(cat "$OUT")"
  local dj="$d/docs/ai/overview-data.json"
  [[ -f "$dj" ]] || log_fail "overview-data.json was not written"
  local a b total
  a="$(node_get "$dj" 'm.delivered.find(x=>x.ref==="CHG-T005A").token_total')"
  b="$(node_get "$dj" 'm.delivered.find(x=>x.ref==="CHG-T005B").token_total')"
  total="$(node_get "$dj" 'm.counts.tokens_total')"
  [[ "$a" == "1500" ]] || log_fail "CHG-T005A token_total must be 1500 (malformed marker ignored), got $a"
  [[ "$b" == "2500" ]] || log_fail "CHG-T005B token_total must be 2500, got $b"
  [[ "$total" == "4000" ]] || log_fail "counts.tokens_total must be the grand total 4000, got $total"
  log_pass "Per-item token totals equal METRICS marker sums; counts grand total is their sum (token-economics TEST-005)"
}

test_005b_no_marker_item_is_null() {
  log_info "Test: a delivered item with no METRICS entry/marker gets token_total null, not zero or n/a-as-string (token-economics TEST-005)..."
  local d
  d="$(mk_repo t005b)"
  write_change_doc "$d/docs/issues/CHANGE-0001-t005c.md" "CHG-T005C" "done"
  write_closed_event "$d/docs/ai/EVENTS.jsonl" "CHG-T005C" "2026-07-10T12:00:00Z"
  : > "$d/docs/ai/METRICS.jsonl"
  run_overview "$d"
  [[ "$EC" == 0 ]] || log_fail "overview must exit 0: $(cat "$OUT")"
  local v
  v="$(node_get "$d/docs/ai/overview-data.json" 'm.delivered.find(x=>x.ref==="CHG-T005C").token_total')"
  [[ "$v" == "null" ]] || log_fail "an item with no recorded marker must have token_total null, got $v"
  log_pass "Item with no METRICS marker gets token_total null (token-economics TEST-005)"
}

# --- TEST-006 (Spec-AC-04, SEAM 2): overview <-> report agreement -------------

test_006_seam_overview_report_agreement() {
  log_info "Test: SEAM — overview per-item token sum equals metrics-report's per-item sum on the SAME METRICS fixture (token-economics TEST-006)..."
  local d
  d="$(mk_repo t006)"
  write_change_doc "$d/docs/issues/CHANGE-0001-t006.md" "CHG-T006" "done"
  write_closed_event "$d/docs/ai/EVENTS.jsonl" "CHG-T006" "2026-07-11T12:00:00Z"
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-11","ref_id":"CHG-T006","title":"Seam item","human_time_minutes":{"intake":0,"reviews":0},"agent_runs":[{"role":"Implementation","model_id":"m","tokens_in":null,"tokens_out":null,"cost_usd":null,"note":"usage_total_tokens=777 (a)"},{"role":"Validation","model_id":"m","tokens_in":null,"tokens_out":null,"cost_usd":null,"note":"usage_total_tokens=223 (b)"}],"totals":{"human_time_minutes":0,"agent_duration_seconds":0,"total_cost_usd":null},"verdict":"PASS"}
JSONL
  write_pricing "$d/PRICING.yaml"

  run_overview "$d"
  [[ "$EC" == 0 ]] || log_fail "overview must exit 0: $(cat "$OUT")"
  local overview_total
  overview_total="$(node_get "$d/docs/ai/overview-data.json" 'm.delivered.find(x=>x.ref==="CHG-T006").token_total')"

  local rep_out="$d/report.md"
  (cd "$PROJECT_ROOT" && node "$REPORT" --metrics "$d/docs/ai/METRICS.jsonl" --pricing "$d/PRICING.yaml") > "$rep_out" \
    || log_fail "report must exit 0: $(cat "$rep_out")"
  local report_total
  report_total="$(grep -E '^\| CHG-T006 \|' "$rep_out" | awk -F'|' '{gsub(/ /,"",$7); print $7}')"

  [[ "$overview_total" == "1000" ]] || log_fail "overview token_total must be 777+223=1000, got $overview_total"
  [[ "$report_total" == "1000" ]] || log_fail "report undecomposed-token column must be 1000, got $report_total"
  [[ "$overview_total" == "$report_total" ]] \
    || log_fail "SEAM violated: overview total ($overview_total) != report total ($report_total) on the same fixture"
  log_pass "Seam: overview per-item token sum (1000) equals metrics-report's per-item sum on the same fixture (token-economics TEST-006)"
}

# --- TEST-007 (Spec-AC-05): Delivered grouping --------------------------------

test_007_release_grouping_and_close_month_fallback() {
  log_info "Test: an item named in a release's links.members renders under that release; an unnamed item falls back to a close-month group (token-economics TEST-007)..."
  local d
  d="$(mk_repo t007)"
  write_change_doc "$d/docs/issues/CHANGE-0001-t007a.md" "CHG-T007A" "done"
  write_change_doc "$d/docs/issues/CHANGE-0002-t007b.md" "CHG-T007B" "done"
  write_change_doc "$d/docs/issues/CHANGE-0003-t007c.md" "CHG-T007C" "done"
  write_release_doc "$d/docs/releases/REL-T007-release.md" "REL-T007" "CHG-T007A"
  write_closed_event "$d/docs/ai/EVENTS.jsonl" "CHG-T007A" "2026-05-01T12:00:00Z"
  write_closed_event "$d/docs/ai/EVENTS.jsonl" "CHG-T007B" "2026-05-15T12:00:00Z"
  write_closed_event "$d/docs/ai/EVENTS.jsonl" "CHG-T007C" "2026-06-01T12:00:00Z"
  : > "$d/docs/ai/METRICS.jsonl"
  run_overview "$d"
  [[ "$EC" == 0 ]] || log_fail "overview must exit 0: $(cat "$OUT")"
  local dj="$d/docs/ai/overview-data.json"

  local a_group b_group c_group
  a_group="$(node_get "$dj" '(m.delivered_groups.find(g=>g.items.some(i=>i.ref==="CHG-T007A"))||{}).kind')"
  b_group="$(node_get "$dj" '(m.delivered_groups.find(g=>g.items.some(i=>i.ref==="CHG-T007B"))||{}).kind')"
  c_group="$(node_get "$dj" '(m.delivered_groups.find(g=>g.items.some(i=>i.ref==="CHG-T007C"))||{}).kind')"
  [[ "$a_group" == "release" ]] || log_fail "CHG-T007A is a release member — must group under kind=release, got $a_group"
  [[ "$b_group" == "month" ]] || log_fail "CHG-T007B is unnamed by any release — must fall back to kind=month, got $b_group"
  [[ "$c_group" == "month" ]] || log_fail "CHG-T007C is unnamed by any release — must fall back to kind=month, got $c_group"

  local b_label c_label
  b_label="$(node_get "$dj" '(m.delivered_groups.find(g=>g.items.some(i=>i.ref==="CHG-T007B"))||{}).label')"
  c_label="$(node_get "$dj" '(m.delivered_groups.find(g=>g.items.some(i=>i.ref==="CHG-T007C"))||{}).label')"
  [[ "$b_label" == "2026-05" ]] || log_fail "CHG-T007B close-month label must derive from its close date (2026-05), got $b_label"
  [[ "$c_label" == "2026-06" ]] || log_fail "CHG-T007C close-month label must derive from its close date (2026-06), got $c_label"

  grep -qF "REL-T007" "$d/docs/ai/overview.html" \
    || log_fail "rendered overview.html must show the release heading for the grouped item"
  grep -qF "2026-05" "$d/docs/ai/overview.html" \
    || log_fail "rendered overview.html must show the close-month fallback heading"

  log_pass "Delivered grouping: release-member item groups under its release; unnamed items fall back to close-month groups (token-economics TEST-007)"
}

main() {
  echo "Testing $TEST_NAME (token-economics-end-to-end TEST-005..007)"
  check_deps
  setup_fixture
  test_005_per_item_tokens_and_grand_total
  test_005b_no_marker_item_is_null
  test_006_seam_overview_report_agreement
  test_007_release_grouping_and_close_month_fallback
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

# Allow sourcing for isolated per-test execution (TDD RED/GREEN evidence);
# run the full suite only when invoked directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then
    check_deps
    setup_fixture
    "$1"
  else
    main
  fi
fi
