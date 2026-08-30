#!/usr/bin/env bash
#
# Test: aai-overview — token economics overview v2
# (docs/specs/SPEC-0089-spec-token-economics-end-to-end.md, TEST-005..007)
# and the dev-progress-hub "In flight now" section
# (docs/specs/SPEC-0093-spec-dev-progress-hub.md, TEST-001..006).
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
#   - TEST-001/002 (dev-progress-hub Spec-AC-01): fixture STATE.yaml + 6 loop
#     ticks render an "In flight now" section with focus/phase/strategy/
#     worktree/validation/review chips, and exactly the last 5 ticks newest
#     first.
#   - TEST-003 (dev-progress-hub Spec-AC-02): STATE absent, ticks absent, and
#     ticks present-but-empty all omit the section entirely and exit 0.
#   - TEST-004 (dev-progress-hub Spec-AC-03): a malformed JSONL tick line
#     never shifts or shrinks the rendered 5-tick window.
#   - TEST-005 dph (dev-progress-hub Spec-AC-04, SEAM): overview-data.json's
#     in_flight block matches the SAME run's rendered HTML — one model field,
#     two renderers, no drift possible between them.
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
# Pipe-free payload assertions (spec-assertions-must-not-die-on-their-own-payload).
# shellcheck source=lib/assert-payload.sh
. "$SCRIPT_DIR/lib/assert-payload.sh"
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

# write_state_yaml <path> <ref> <focus-type> <phase> <strategy> <worktree-rec>
#   <worktree-decision> <validation-status> <review-status>
# — minimal fixture matching the REAL docs/ai/STATE.yaml shape generate-
# overview.mjs's readState()/findActiveWorkItem() line-discipline parser
# reads: current_focus + a matching active_work_items[] entry (for phase),
# implementation_strategy, worktree, code_review, last_validation, human_input.
write_state_yaml() {
  local p="$1" ref="$2" ftype="$3" phase="$4" strategy="$5" wrec="$6" wdec="$7" vstatus="$8" rstatus="$9"
  cat > "$p" <<EOF
project_status: active
current_focus:
  type: $ftype
  ref_id: $ref
  primary_path: docs/issues/fixture.md
  spec_path: null
active_work_items:
  - ref_id: $ref
    status: in_progress
    phase: $phase
implementation_strategy:
  selected: $strategy
  source: docs/specs/fixture.md
  rationale: fixture
worktree:
  recommendation: $wrec
  user_decision: $wdec
  base_ref: main
  branch: null
  path: null
  inline_review_scope: fixture
code_review:
  required: true
  status: $rstatus
  scope: fixture
  base_ref: null
  head_ref: null
  pr: null
  report_paths: []
  notes: fixture
last_validation:
  status: $vstatus
  run_at_utc: 2026-07-27T00:00:00Z
  ref_id: $ref
  evidence_paths: []
  notes: fixture
human_input:
  required: false
  question: null
EOF
}

# write_tick <ticks-file> <tick-num> <role> <scope> <duration_seconds> <harness>
# — appends one well-formed LOOP_TICKS.jsonl row (real-shape fields).
write_tick() {
  printf '{"type":"tick","tick":%s,"role":"%s","scope":"%s","started_utc":"2026-07-27T00:00:00Z","ended_utc":"2026-07-27T00:00:30Z","duration_seconds":%s,"exit_code":0,"harness_version":"%s"}\n' \
    "$2" "$3" "$4" "$5" "$6" >> "$1"
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

# --- TEST-001/002 (Spec-AC-01): In-flight section render + newest-first order ---

test_dph01_in_flight_renders_focus_and_chips() {
  log_info "Test: fixture STATE + ticks render the In-flight section with focus/phase/strategy/worktree/validation/review chips (dev-progress-hub TEST-001)..."
  local d
  d="$(mk_repo dph01)"
  write_state_yaml "$d/docs/ai/STATE.yaml" "FIX-DPH1" "intake_change" "implementation" "tdd" "recommended" "inline" "pass" "not_run"
  local i
  for i in 1 2 3 4 5 6; do
    write_tick "$d/docs/ai/LOOP_TICKS.jsonl" "$i" "Role$i" "scope-$i" "$((i * 10))" "h$i.0"
  done
  run_overview "$d"
  [[ "$EC" == 0 ]] || log_fail "overview must exit 0: $(cat "$OUT")"
  local html="$d/docs/ai/overview.html"
  grep -qF "In flight now" "$html" || log_fail "missing 'In flight now' section heading"
  # Localize chip assertions to the In-flight section only (PR #167 review):
  # tokens like "pass"/"inline" appear elsewhere in overview.html.
  local section
  section="$(awk '/In flight now/,/<\/section>/' "$html")"
  grep -qF "FIX-DPH1" "$html" || log_fail "missing focus ref"
  assert_payload_contains "$section" "implementation" "missing focus phase chip"
  grep -qF "tdd" "$html" || log_fail "missing strategy chip"
  grep -qF "recommended" "$html" || log_fail "missing worktree recommendation chip"
  assert_payload_contains "$section" "inline" "missing worktree user-decision chip"
  assert_payload_contains "$section" "pass" "missing validation-status chip"
  grep -qF "not_run" "$html" || log_fail "missing review-status chip"
  log_pass "In-flight section renders focus/phase/strategy/worktree/validation/review (dev-progress-hub TEST-001)"
}

test_dph02_last_five_ticks_newest_first() {
  log_info "Test: exactly the last 5 ticks render, newest first; the oldest (tick 1) is excluded (dev-progress-hub TEST-002)..."
  local d
  d="$(mk_repo dph02)"
  write_state_yaml "$d/docs/ai/STATE.yaml" "FIX-DPH2" "intake_change" "validation" "loop" "optional" "waived" "fail" "pass"
  local i
  for i in 1 2 3 4 5 6; do
    write_tick "$d/docs/ai/LOOP_TICKS.jsonl" "$i" "Role$i" "scope-$i" "$((i * 10))" "h$i.0"
  done
  run_overview "$d"
  [[ "$EC" == 0 ]] || log_fail "overview must exit 0: $(cat "$OUT")"
  local dj="$d/docs/ai/overview-data.json"
  local count order has_one
  count="$(node_get "$dj" 'm.in_flight?.ticks?.length')"
  [[ "$count" == "5" ]] || log_fail "expected exactly 5 ticks in in_flight.ticks, got $count"
  order="$(node_get "$dj" 'm.in_flight?.ticks?.map(t=>t.tick)?.join(",")')"
  [[ "$order" == "6,5,4,3,2" ]] || log_fail "expected newest-first order 6,5,4,3,2, got $order"
  has_one="$(node_get "$dj" 'm.in_flight?.ticks?.some(t=>t.tick===1)')"
  [[ "$has_one" == "false" ]] || log_fail "tick 1 (the 6th-oldest) must not appear in the last-5 window"
  node -e '
    const fs = require("fs");
    const html = fs.readFileSync(process.argv[1], "utf8");
    const order = ["scope-6", "scope-5", "scope-4", "scope-3", "scope-2"];
    let last = -1;
    for (const s of order) {
      const idx = html.indexOf(s);
      if (idx === -1) { console.error("missing " + s + " in rendered HTML"); process.exit(1); }
      if (idx < last) { console.error("out of order at " + s); process.exit(1); }
      last = idx;
    }
  ' "$d/docs/ai/overview.html" || log_fail "rendered ticks must appear newest-first in the HTML table"
  log_pass "Last 5 ticks render newest first; the 6th-oldest tick is excluded (dev-progress-hub TEST-002)"
}

# --- TEST-003 (Spec-AC-02): graceful omission -------------------------------

test_dph03_graceful_omission() {
  log_info "Test: STATE absent, ticks absent, and ticks present-but-empty all omit the section entirely and exit 0 (dev-progress-hub TEST-003)..."
  local dA dB dC inflight

  dA="$(mk_repo dph03a)"
  write_tick "$dA/docs/ai/LOOP_TICKS.jsonl" 1 "Role1" "scope-1" 10 "h1.0"
  run_overview "$dA"
  [[ "$EC" == 0 ]] || log_fail "STATE-absent case must exit 0: $(cat "$OUT")"
  grep -qF "In flight now" "$dA/docs/ai/overview.html" && log_fail "STATE-absent case must omit the In-flight section"
  inflight="$(node_get "$dA/docs/ai/overview-data.json" 'm.in_flight')"
  [[ "$inflight" == "null" ]] || log_fail "STATE-absent case must have in_flight null, got $inflight"

  dB="$(mk_repo dph03b)"
  write_state_yaml "$dB/docs/ai/STATE.yaml" "FIX-DPH3B" "intake_change" "implementation" "tdd" "recommended" "inline" "pass" "not_run"
  run_overview "$dB"
  [[ "$EC" == 0 ]] || log_fail "ticks-absent case must exit 0: $(cat "$OUT")"
  grep -qF "In flight now" "$dB/docs/ai/overview.html" && log_fail "ticks-absent case must omit the In-flight section"
  inflight="$(node_get "$dB/docs/ai/overview-data.json" 'm.in_flight')"
  [[ "$inflight" == "null" ]] || log_fail "ticks-absent case must have in_flight null, got $inflight"

  dC="$(mk_repo dph03c)"
  write_state_yaml "$dC/docs/ai/STATE.yaml" "FIX-DPH3C" "intake_change" "implementation" "tdd" "recommended" "inline" "pass" "not_run"
  : > "$dC/docs/ai/LOOP_TICKS.jsonl"
  run_overview "$dC"
  [[ "$EC" == 0 ]] || log_fail "ticks-empty case must exit 0: $(cat "$OUT")"
  grep -qF "In flight now" "$dC/docs/ai/overview.html" && log_fail "ticks-empty case must omit the In-flight section"
  inflight="$(node_get "$dC/docs/ai/overview-data.json" 'm.in_flight')"
  [[ "$inflight" == "null" ]] || log_fail "ticks-empty case must have in_flight null, got $inflight"

  log_pass "STATE-absent, ticks-absent, and ticks-empty all gracefully omit the section (dev-progress-hub TEST-003)"
}

# --- TEST-004 (Spec-AC-03): malformed tick line never consumes a slot -------

test_dph04_malformed_line_no_slot_consumed() {
  log_info "Test: a JSON-parse-invalid line among 6 valid ticks does not shift or shrink the rendered 5-tick window (dev-progress-hub TEST-004)..."
  local d
  d="$(mk_repo dph04)"
  write_state_yaml "$d/docs/ai/STATE.yaml" "FIX-DPH4" "intake_change" "code_review" "hybrid" "required" "worktree" "pass" "pass"
  write_tick "$d/docs/ai/LOOP_TICKS.jsonl" 1 "Role1" "scope-1" 10 "h1.0"
  write_tick "$d/docs/ai/LOOP_TICKS.jsonl" 2 "Role2" "scope-2" 20 "h1.0"
  write_tick "$d/docs/ai/LOOP_TICKS.jsonl" 3 "Role3" "scope-3" 30 "h1.0"
  write_tick "$d/docs/ai/LOOP_TICKS.jsonl" 4 "Role4" "scope-4" 40 "h1.0"
  write_tick "$d/docs/ai/LOOP_TICKS.jsonl" 5 "Role5" "scope-5" 50 "h1.0"
  printf '{"type":"tick","tick":99,"role":"Broken","scope":"unterminated\n' >> "$d/docs/ai/LOOP_TICKS.jsonl"
  write_tick "$d/docs/ai/LOOP_TICKS.jsonl" 6 "Role6" "scope-6" 60 "h1.0"
  run_overview "$d"
  [[ "$EC" == 0 ]] || log_fail "malformed-line fixture must still exit 0: $(cat "$OUT")"
  local dj="$d/docs/ai/overview-data.json"
  local order count
  order="$(node_get "$dj" 'm.in_flight?.ticks?.map(t=>t.tick)?.join(",")')"
  [[ "$order" == "6,5,4,3,2" ]] || log_fail "malformed line must not shift the 5-tick window; expected 6,5,4,3,2, got $order"
  count="$(node_get "$dj" 'm.in_flight?.ticks?.length')"
  [[ "$count" == "5" ]] || log_fail "malformed line must not shrink the window below 5, got $count"
  log_pass "Malformed tick line is skipped and never occupies one of the 5 slots (dev-progress-hub TEST-004)"

  # Shape arms (PR #167 review + Codex P2 legacy-producer tolerance):
  # (a) a legacy tick WITHOUT role/scope is kept, normalized to placeholders;
  # (b) a JSON-valid row with a non-tick type is dropped without a slot.
  local d2
  d2="$(mk_repo dph04b)"
  write_state_yaml "$d2/docs/ai/STATE.yaml" "FIX-DPH4B" "intake_change" "implementation" "tdd" "required" "inline" "not_run" "not_run"
  write_tick "$d2/docs/ai/LOOP_TICKS.jsonl" 1 "Role1" "scope-1" 10 "h1.0"
  printf '{"type":"tick","tick":2,"started_utc":"2026-07-27T00:00:00Z","duration_seconds":5}\n' >> "$d2/docs/ai/LOOP_TICKS.jsonl"
  printf '{"type":"docs_audit","tick":98,"role":"NotATick","scope":"x"}\n' >> "$d2/docs/ai/LOOP_TICKS.jsonl"
  write_tick "$d2/docs/ai/LOOP_TICKS.jsonl" 3 "Role3" "scope-3" 30 "h1.0"
  run_overview "$d2"
  [[ "$EC" == 0 ]] || log_fail "shape-arm fixture must exit 0: $(cat "$OUT")"
  local dj2="$d2/docs/ai/overview-data.json" order2 legacyrole
  order2="$(node_get "$dj2" 'm.in_flight?.ticks?.map(t=>t.tick)?.join(",")')"
  [[ "$order2" == "3,2,1" ]] || log_fail "legacy tick kept + non-tick dropped; expected 3,2,1, got $order2"
  legacyrole="$(node_get "$dj2" 'm.in_flight?.ticks?.[1]?.role')"
  [[ "$legacyrole" == "(legacy tick)" ]] || log_fail "legacy tick must normalize role placeholder, got $legacyrole"
  log_pass "Legacy role-less tick normalized and kept; JSON-valid non-tick row dropped (shape arms)"
}

# --- TEST-005 dph (Spec-AC-04, SEAM): overview-data.json mirrors the render -

test_dph05_data_json_mirrors_render() {
  log_info "Test: SEAM — overview-data.json's in_flight block matches the SAME run's rendered HTML, field for field (dev-progress-hub TEST-005)..."
  local d
  d="$(mk_repo dph05)"
  write_state_yaml "$d/docs/ai/STATE.yaml" "FIX-DPH5" "intake_issue" "remediation" "hybrid" "optional" "waived" "fail" "fail"
  local i
  for i in 1 2 3 4 5 6; do
    write_tick "$d/docs/ai/LOOP_TICKS.jsonl" "$i" "Role$i" "scope-$i" "$((i * 10))" "h$i.0"
  done
  run_overview "$d"
  [[ "$EC" == 0 ]] || log_fail "overview must exit 0: $(cat "$OUT")"
  local dj="$d/docs/ai/overview-data.json"
  local html="$d/docs/ai/overview.html"
  local jref jphase jstrategy jwrec jwdec jvstatus jrstatus
  jref="$(node_get "$dj" 'm.in_flight?.focus?.ref')"
  jphase="$(node_get "$dj" 'm.in_flight?.focus?.phase')"
  jstrategy="$(node_get "$dj" 'm.in_flight?.strategy')"
  jwrec="$(node_get "$dj" 'm.in_flight?.worktree?.recommendation')"
  jwdec="$(node_get "$dj" 'm.in_flight?.worktree?.user_decision')"
  jvstatus="$(node_get "$dj" 'm.in_flight?.validation_status')"
  jrstatus="$(node_get "$dj" 'm.in_flight?.review_status')"
  [[ "$jref" == "FIX-DPH5" ]] || log_fail "in_flight.focus.ref mismatch: $jref"
  [[ "$jphase" == "remediation" ]] || log_fail "in_flight.focus.phase mismatch: $jphase"
  [[ "$jstrategy" == "hybrid" ]] || log_fail "in_flight.strategy mismatch: $jstrategy"
  [[ "$jwrec" == "optional" ]] || log_fail "in_flight.worktree.recommendation mismatch: $jwrec"
  [[ "$jwdec" == "waived" ]] || log_fail "in_flight.worktree.user_decision mismatch: $jwdec"
  [[ "$jvstatus" == "fail" ]] || log_fail "in_flight.validation_status mismatch: $jvstatus"
  [[ "$jrstatus" == "fail" ]] || log_fail "in_flight.review_status mismatch: $jrstatus"
  local v
  for v in "$jref" "$jphase" "$jstrategy" "$jwrec" "$jwdec"; do
    grep -qF "$v" "$html" || log_fail "SEAM violated: HTML must show in_flight value '$v' present in overview-data.json"
  done
  log_pass "SEAM: overview-data.json in_flight block matches the same run's rendered HTML (dev-progress-hub TEST-005)"
}

main() {
  echo "Testing $TEST_NAME (token-economics-end-to-end TEST-005..007 + dev-progress-hub TEST-001..006)"
  check_deps
  setup_fixture
  test_005_per_item_tokens_and_grand_total
  test_005b_no_marker_item_is_null
  test_006_seam_overview_report_agreement
  test_007_release_grouping_and_close_month_fallback
  test_dph01_in_flight_renders_focus_and_chips
  test_dph02_last_five_ticks_newest_first
  test_dph03_graceful_omission
  test_dph04_malformed_line_no_slot_consumed
  test_dph05_data_json_mirrors_render
  echo ""
  log_pass "All $TEST_NAME tests passed (dev-progress-hub TEST-006: full-suite regression check)"
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
