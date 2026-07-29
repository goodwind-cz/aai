#!/usr/bin/env bash
#
# Test: aai-factory-report
# (docs/specs/SPEC-DRAFT-spec-factory-performance-report.md, TEST-001..014)
#
# Verifies .aai/scripts/generate-factory-report.mjs — the deterministic
# Factory Performance Report generator over docs/ai/METRICS.jsonl +
# docs/ai/EVENTS.jsonl (+ docs/releases/*.md links.members). Two cross-
# generator SEAM tests share ONE fixture with metrics-report.mjs (TEST-011)
# and generate-overview.mjs (TEST-012); TEST-013 drives the REAL
# close-work-item.mjs with a rigged generator failure (negative control).
#
# ALL fixtures are scratch temp-dir repos — the real docs/ tree is NEVER
# touched. bash 3.2 compatible (no ${var^^}, no declare -A).
#
# Usage:
#   bash tests/skills/test-aai-factory-report.sh                 # run all
#   bash tests/skills/test-aai-factory-report.sh test_003_lead_time
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-factory-report"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPORT="$PROJECT_ROOT/.aai/scripts/generate-factory-report.mjs"
METRICS_REPORT="$PROJECT_ROOT/.aai/scripts/metrics-report.mjs"
OVERVIEW="$PROJECT_ROOT/.aai/scripts/generate-overview.mjs"
CLOSE_SCRIPT="$PROJECT_ROOT/.aai/scripts/close-work-item.mjs"

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
  [[ -f "$REPORT" ]] || log_fail "generate-factory-report.mjs not found: $REPORT"
  log_pass "Dependencies checked"
}

setup_fixture() { TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-factory-report-test.XXXXXX")"; }

# --- fixture builders ---------------------------------------------------------

mk_repo() {  # mk_repo <name> -> echoes fixture repo dir
  local d="$TEST_DIR/$1"
  rm -rf "$d"
  mkdir -p "$d/docs/issues" "$d/docs/specs" "$d/docs/releases" "$d/docs/ai"
  : > "$d/docs/ai/EVENTS.jsonl"
  : > "$d/docs/ai/METRICS.jsonl"
  printf '%s' "$d"
}

write_closed_event() {  # <events_file> <ref> <ts>
  printf '{"v":1,"ts":"%s","actor":"test","event":"work_item_closed","ref":"%s","payload":{}}\n' "$3" "$2" >> "$1"
}

write_release_doc() {  # <path> <id> <member1> [member2...]
  local path="$1" id="$2"; shift 2
  {
    echo "---"; echo "id: $id"; echo "type: release"; echo "status: done"
    echo "links:"; echo "  pr: []"; echo "  commits: []"
    if [[ $# -gt 0 ]]; then echo "  members:"; local m; for m in "$@"; do echo "    - $m"; done; fi
    echo "---"; echo ""; echo "# Release $id"
  } > "$path"
}

write_change_doc() {  # <path> <id> <status>  (overview-scannable)
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
- fixture doc.
EOF
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

# run_report <dir> [extra args] -> OUT/EC set; writes factory-report* into dir/docs/ai
OUT=""; EC=0
run_report() {
  local d="$1"; shift || true
  OUT="$d/report-run.log"; EC=0
  (cd "$d" && node "$REPORT" --output "$d/docs/ai/factory-report.html" "$@" > "$OUT" 2>&1) || EC=$?
}

DJ=""  # data-json path shortcut for the last run
node_get() {  # node_get <json-file> <expr-using-m>
  node -e '
    const fs=require("fs"); const m=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
    const expr=process.argv[2]; process.stdout.write(String(eval(expr)));
  ' "$1" "$2"
}

# --- close-work-item fixture helpers (TEST-013 negative control) --------------
new_close_repo() {  # <name> -> echoes git-repo dir with enforce-off docs-audit
  local d="$TEST_DIR/$1"
  mkdir -p "$d/docs/issues" "$d/docs/specs" "$d/docs/ai"
  : > "$d/docs/ai/EVENTS.jsonl"
  cat > "$d/docs/ai/docs-audit.yaml" <<'YAML'
legacy_until_date: 2020-01-01
stale_after_days: 90
scan_exclude: []
backlog_globs: []
close_gate: report-only
doc_number_guard: report-only
protected_paths_l3: []
YAML
  git init -q "$d"
  git -C "$d" config user.email test@example.com
  git -C "$d" config user.name test
  git -C "$d" add -A
  git -C "$d" commit -q -m init
  printf '%s' "$d"
}

# ============================ TEST-001 (Spec-AC-01) ==========================
test_001_data_only_blocks_present() {
  log_info "Test: --data-only writes factory-report-data.json with the four KPI blocks and exits 0 (TEST-001)..."
  local d; d="$(mk_repo t001)"
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-01","ref_id":"A","agent_runs":[{"role":"Planning","duration_seconds":60,"note":"usage_total_tokens=100"}],"verdict":"PASS"}
JSONL
  write_closed_event "$d/docs/ai/EVENTS.jsonl" "A" "2026-07-02T00:00:00Z"
  run_report "$d" --data-only
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  DJ="$d/docs/ai/factory-report-data.json"
  [[ -f "$DJ" ]] || log_fail "data.json not written"
  [[ -f "$d/docs/ai/factory-report.html" ]] && log_fail "--data-only must NOT write html"
  local k; for k in throughput speed cost quality; do
    [[ "$(node_get "$DJ" "typeof m.$k")" == "object" ]] || log_fail "missing KPI block: $k"
  done
  log_pass "data-only emits the four KPI blocks, no html, exit 0 (TEST-001)"
}

# ============================ TEST-002 (Spec-AC-02) ==========================
test_002_throughput_week_and_release() {
  log_info "Test: delivered counts per ISO week and per release with close-month fallback (TEST-002)..."
  local d; d="$(mk_repo t002)"
  write_release_doc "$d/docs/releases/REL-1.md" "REL-1" "A"
  write_closed_event "$d/docs/ai/EVENTS.jsonl" "A" "2026-07-06T00:00:00Z"  # 2026-W28
  write_closed_event "$d/docs/ai/EVENTS.jsonl" "B" "2026-07-06T00:00:00Z"  # W28, no release -> month 2026-07
  write_closed_event "$d/docs/ai/EVENTS.jsonl" "C" "2026-06-01T00:00:00Z"  # W23, month 2026-06
  run_report "$d" --data-only
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  DJ="$d/docs/ai/factory-report-data.json"
  [[ "$(node_get "$DJ" 'm.throughput.delivered_by_week["2026-W28"]')" == "2" ]] || log_fail "W28 must have 2 deliveries"
  [[ "$(node_get "$DJ" 'm.throughput.delivered_total')" == "3" ]] || log_fail "delivered_total must be 3"
  local ak bk ck
  ak="$(node_get "$DJ" '(m.throughput.delivered_groups.find(g=>g.refs.includes("A"))||{}).kind')"
  bk="$(node_get "$DJ" '(m.throughput.delivered_groups.find(g=>g.refs.includes("B"))||{}).kind')"
  ck="$(node_get "$DJ" '(m.throughput.delivered_groups.find(g=>g.refs.includes("C"))||{}).label')"
  [[ "$ak" == "release" ]] || log_fail "A must group under a release, got $ak"
  [[ "$bk" == "month" ]] || log_fail "B must fall back to a close-month group, got $bk"
  [[ "$ck" == "2026-06" ]] || log_fail "C close-month label must be 2026-06, got $ck"
  log_pass "Throughput buckets per ISO week and per release with month fallback (TEST-002)"
}

# ============================ TEST-003 (Spec-AC-02) ==========================
test_003_lead_time() {
  log_info "Test: lead_time = close minus earliest start, null when an endpoint is absent, never zero (TEST-003)..."
  local d; d="$(mk_repo t003)"
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-01","ref_id":"WITH","agent_runs":[{"role":"Planning","started_utc":"2026-07-01T00:00:00Z","duration_seconds":60},{"role":"Validation","started_utc":"2026-07-01T01:00:00Z","duration_seconds":60}],"verdict":"PASS"}
{"date_utc":"2026-07-01","ref_id":"NOSTART","agent_runs":[{"role":"Planning","duration_seconds":60}],"verdict":"PASS"}
JSONL
  write_closed_event "$d/docs/ai/EVENTS.jsonl" "WITH" "2026-07-01T02:00:00Z"   # 2h after earliest start
  write_closed_event "$d/docs/ai/EVENTS.jsonl" "NOSTART" "2026-07-01T02:00:00Z"
  run_report "$d" --data-only
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  DJ="$d/docs/ai/factory-report-data.json"
  local wl nl
  wl="$(node_get "$DJ" '(m.throughput.lead_time.per_item.find(x=>x.ref==="WITH")||{}).lead_time_seconds')"
  nl="$(node_get "$DJ" '(m.throughput.lead_time.per_item.find(x=>x.ref==="NOSTART")||{}).lead_time_seconds')"
  [[ "$wl" == "7200" ]] || log_fail "WITH lead time must be 7200s (close - earliest start), got $wl"
  [[ "$nl" == "null" ]] || log_fail "NOSTART lead time must be null (no started_utc), got $nl"
  log_pass "Lead time computed from earliest start; null when unmeasurable, never zero (TEST-003)"
}

# ============================ TEST-004 (Spec-AC-03) ==========================
test_004_role_normalization() {
  log_info "Test: per-role duration split normalizes role variants to canonical roles (TEST-004)..."
  local d; d="$(mk_repo t004)"
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-01","ref_id":"A","agent_runs":[{"role":"Remediation (E1 over-kill)","duration_seconds":30},{"role":"Remediation","duration_seconds":70},{"role":"Implementation (loop)","duration_seconds":50},{"role":"Validation","duration_seconds":40}],"verdict":"PASS"}
JSONL
  run_report "$d" --data-only
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  DJ="$d/docs/ai/factory-report-data.json"
  local rem impl val
  rem="$(node_get "$DJ" '(m.speed.role_split.find(x=>x.role==="Remediation")||{}).duration_seconds')"
  impl="$(node_get "$DJ" '(m.speed.role_split.find(x=>x.role==="Implementation")||{}).duration_seconds')"
  val="$(node_get "$DJ" '(m.speed.role_split.find(x=>x.role==="Validation")||{}).duration_seconds')"
  [[ "$rem" == "100" ]] || log_fail "Remediation split must sum both variants to 100, got $rem"
  [[ "$impl" == "50" ]] || log_fail "Implementation (loop) must normalize under Implementation=50, got $impl"
  [[ "$val" == "40" ]] || log_fail "Validation must be 40, got $val"
  log_pass "Role variants normalize to canonical roles and durations sum (TEST-004)"
}

# ============================ TEST-005 (Spec-AC-04) ==========================
test_005_token_totals() {
  log_info "Test: per-ride and per-role token totals sum valid markers, malformed ignored, no-marker ride null (TEST-005)..."
  local d; d="$(mk_repo t005)"
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-01","ref_id":"A","agent_runs":[{"role":"Planning","duration_seconds":10,"note":"usage_total_tokens=1500 (ok)"},{"role":"Validation","duration_seconds":10,"note":"usage_total_tokens=500x (malformed, ignored)"}],"verdict":"PASS"}
{"date_utc":"2026-07-01","ref_id":"B","agent_runs":[{"role":"Planning","duration_seconds":10,"note":"no marker here"}],"verdict":"PASS"}
JSONL
  run_report "$d" --data-only
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  DJ="$d/docs/ai/factory-report-data.json"
  [[ "$(node_get "$DJ" 'm.cost.tokens_total')" == "1500" ]] || log_fail "tokens_total must be 1500 (malformed ignored, B has none)"
  local plan bnull
  plan="$(node_get "$DJ" '(m.cost.by_role.find(x=>x.role==="Planning")||{}).tokens')"
  [[ "$plan" == "1500" ]] || log_fail "Planning role tokens must be 1500, got $plan"
  bnull="$(node_get "$DJ" '(m.speed.per_ride.find(x=>x.ref==="B")||{}).ref')"
  [[ "$(node_get "$DJ" 'm.cost.tokens_per_ride.measured')" == "1" ]] || log_fail "only 1 ride carries a marker"
  log_pass "Token totals sum valid markers only; malformed ignored; no-marker excluded (TEST-005)"
}

# ============================ TEST-006 (Spec-AC-04) ==========================
test_006_no_usd_anywhere() {
  log_info "Test: NO dollar-amount figure appears in data.json or html; usd field is null (TEST-006, honesty pin)..."
  local d; d="$(mk_repo t006)"
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-01","ref_id":"A","agent_runs":[{"role":"Planning","duration_seconds":10,"note":"usage_total_tokens=1500","cost_usd":null}],"verdict":"PASS"}
JSONL
  write_closed_event "$d/docs/ai/EVENTS.jsonl" "A" "2026-07-02T00:00:00Z"
  run_report "$d"
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  DJ="$d/docs/ai/factory-report-data.json"
  [[ "$(node_get "$DJ" 'm.cost.usd')" == "null" ]] || log_fail "cost.usd must be null"
  # A currency figure is a '$' immediately followed by a digit. It must appear
  # in NEITHER output — the whole point of the tokens-only honesty rule.
  if grep -qE '\$[0-9]' "$DJ"; then log_fail "data.json contains a dollar amount"; fi
  if grep -qE '\$[0-9]' "$d/docs/ai/factory-report.html"; then log_fail "html contains a dollar amount"; fi
  log_pass "No dollar-amount figure in either output; usd null (TEST-006)"
}

# ============================ TEST-007 (Spec-AC-05) ==========================
test_007_quality_from_reliability() {
  log_info "Test: first-pass rate + remediation distribution from reliability; ride without it -> explicit n/a bucket (TEST-007)..."
  local d; d="$(mk_repo t007)"
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-01","ref_id":"A","agent_runs":[{"role":"Planning","duration_seconds":10}],"reliability":{"validation_fails":0,"review_fails":0,"remediation_runs":0,"first_pass_clean":true},"verdict":"PASS"}
{"date_utc":"2026-07-01","ref_id":"B","agent_runs":[{"role":"Planning","duration_seconds":10}],"reliability":{"validation_fails":1,"review_fails":0,"remediation_runs":2,"first_pass_clean":false},"verdict":"PASS"}
{"date_utc":"2026-07-01","ref_id":"C","agent_runs":[{"role":"Planning","duration_seconds":10}],"verdict":"PASS"}
JSONL
  run_report "$d" --data-only
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  DJ="$d/docs/ai/factory-report-data.json"
  [[ "$(node_get "$DJ" 'm.quality.first_pass_clean.flagged')" == "2" ]] || log_fail "flagged must be 2 (C has no reliability)"
  [[ "$(node_get "$DJ" 'm.quality.first_pass_clean.clean')" == "1" ]] || log_fail "clean must be 1"
  [[ "$(node_get "$DJ" 'm.quality.first_pass_clean.rate_pct')" == "50" ]] || log_fail "rate must be 50%"
  [[ "$(node_get "$DJ" 'm.quality.na_reliability')" == "1" ]] || log_fail "na_reliability must be 1 (ride C)"
  [[ "$(node_get "$DJ" 'm.quality.remediation_distribution["2"]')" == "1" ]] || log_fail "one ride has 2 remediation runs"
  log_pass "Quality rates derive from the reliability block; pre-field ride -> n/a bucket (TEST-007)"
}

# ============================ TEST-008 (Spec-AC-06) ==========================
test_008_html_matches_data() {
  log_info "Test: rendered HTML KPI values match factory-report-data.json field for field (TEST-008, SEAM 3)..."
  local d; d="$(mk_repo t008)"
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-01","ref_id":"A","agent_runs":[{"role":"Planning","duration_seconds":120,"note":"usage_total_tokens=4242"}],"reliability":{"validation_fails":0,"review_fails":0,"remediation_runs":0,"first_pass_clean":true},"verdict":"PASS"}
JSONL
  write_closed_event "$d/docs/ai/EVENTS.jsonl" "A" "2026-07-02T00:00:00Z"
  run_report "$d"
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  DJ="$d/docs/ai/factory-report-data.json"
  local html="$d/docs/ai/factory-report.html"
  local tot; tot="$(node_get "$DJ" 'm.cost.tokens_total')"
  [[ "$tot" == "4242" ]] || log_fail "expected tokens_total 4242, got $tot"
  grep -qF "4242" "$html" || log_fail "html must render the tokens_total value 4242 present in data.json"
  grep -qF "100%" "$html" || log_fail "html must render the 100% first-pass rate present in data.json"
  log_pass "HTML renders the same KPI values present in data.json (TEST-008)"
}

# ============================ TEST-009 (Spec-AC-07) ==========================
test_009_weekly_series_zero_week() {
  log_info "Test: each dimension has a per-ISO-week series and a zero-delivery week appears as 0 not omitted (TEST-009)..."
  local d; d="$(mk_repo t009)"
  # Ride active in W27 (no delivery that week); delivery lands in W28.
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-06-29","ref_id":"A","agent_runs":[{"role":"Planning","duration_seconds":30}],"verdict":"PASS"}
{"date_utc":"2026-07-06","ref_id":"B","agent_runs":[{"role":"Planning","duration_seconds":30}],"verdict":"PASS"}
JSONL
  write_closed_event "$d/docs/ai/EVENTS.jsonl" "B" "2026-07-06T00:00:00Z"  # W28 only
  run_report "$d" --data-only
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  DJ="$d/docs/ai/factory-report-data.json"
  # 2026-06-29 is ISO week 2026-W27; it has a ride but zero deliveries.
  local zero present
  zero="$(node_get "$DJ" '(m.trend.find(w=>w.week==="2026-W27")||{}).delivered')"
  present="$(node_get "$DJ" 'm.trend.some(w=>w.week==="2026-W27")')"
  [[ "$present" == "true" ]] || log_fail "trend must include the ride-only week 2026-W27"
  [[ "$zero" == "0" ]] || log_fail "zero-delivery week must show delivered=0 not omitted, got $zero"
  [[ "$(node_get "$DJ" '(m.trend.find(w=>w.week==="2026-W28")||{}).delivered')" == "1" ]] || log_fail "W28 must show 1 delivery"
  log_pass "Weekly trend series present; zero-delivery week rendered as 0 (TEST-009)"
}

# ============================ TEST-010 (Spec-AC-08) ==========================
test_010_malformed_line_noted() {
  log_info "Test: a malformed JSONL line is skipped, named in notes, aggregates intact, exit 0 (TEST-010)..."
  local d; d="$(mk_repo t010)"
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-01","ref_id":"A","agent_runs":[{"role":"Planning","duration_seconds":10,"note":"usage_total_tokens=100"}],"verdict":"PASS"}
{"date_utc":"2026-07-01","ref_id":"B", BROKEN LINE
{"date_utc":"2026-07-01","ref_id":"C","agent_runs":[{"role":"Planning","duration_seconds":10,"note":"usage_total_tokens=200"}],"verdict":"PASS"}
JSONL
  run_report "$d" --data-only
  [[ "$EC" == 0 ]] || log_fail "malformed line must not be fatal, exit 0: $(cat "$OUT")"
  DJ="$d/docs/ai/factory-report-data.json"
  [[ "$(node_get "$DJ" 'm.counts.rides')" == "2" ]] || log_fail "the two valid rides must survive; broken line dropped"
  [[ "$(node_get "$DJ" 'm.cost.tokens_total')" == "300" ]] || log_fail "aggregates from valid rides intact (100+200)"
  [[ "$(node_get "$DJ" 'm.notes.some(n=>/EXCLUDED.*malformed METRICS/.test(n))')" == "true" ]] || log_fail "the exclusion must be named in notes"
  log_pass "Malformed line skipped and named; aggregates intact; exit 0 (TEST-010)"
}

# ============================ TEST-011 (Spec-AC-06, SEAM 1) ==================
test_011_seam_tokens_match_metrics_report() {
  log_info "Test: SEAM 1 — factory-report ride token total equals metrics-report per-item token column on the same METRICS fixture (TEST-011)..."
  [[ -f "$METRICS_REPORT" ]] || log_skip "metrics-report.mjs absent"
  local d; d="$(mk_repo t011)"
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-01","ref_id":"SEAM","title":"seam","human_time_minutes":{"intake":0,"reviews":0},"agent_runs":[{"role":"Planning","model_id":"m","duration_seconds":10,"tokens_in":null,"tokens_out":null,"cost_usd":null,"note":"usage_total_tokens=777 (a)"},{"role":"Validation","model_id":"m","duration_seconds":10,"tokens_in":null,"tokens_out":null,"cost_usd":null,"note":"usage_total_tokens=223 (b)"}],"totals":{"human_time_minutes":0,"agent_duration_seconds":20,"total_cost_usd":null},"verdict":"PASS"}
JSONL
  write_pricing "$d/PRICING.yaml"
  run_report "$d" --data-only
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  DJ="$d/docs/ai/factory-report-data.json"
  local fr rep
  fr="$(node_get "$DJ" 'm.cost.tokens_total')"
  rep="$( (cd "$PROJECT_ROOT" && node "$METRICS_REPORT" --metrics "$d/docs/ai/METRICS.jsonl" --pricing "$d/PRICING.yaml") | grep -E '^\| SEAM \|' | awk -F'|' '{gsub(/ /,"",$7); print $7}')"
  [[ "$fr" == "1000" ]] || log_fail "factory-report tokens must be 777+223=1000, got $fr"
  [[ "$rep" == "1000" ]] || log_fail "metrics-report per-item column must be 1000, got $rep"
  [[ "$fr" == "$rep" ]] || log_fail "SEAM 1 violated: factory ($fr) != report ($rep)"
  log_pass "SEAM 1: factory token total equals metrics-report per-item column on one fixture (TEST-011)"
}

# ============================ TEST-012 (Spec-AC-06, SEAM 2) ==================
test_012_seam_release_grouping_matches_overview() {
  log_info "Test: SEAM 2 — factory-report delivered grouping matches generate-overview delivered_groups on the same release+EVENTS fixture (TEST-012)..."
  [[ -f "$OVERVIEW" ]] || log_skip "generate-overview.mjs absent"
  local d; d="$(mk_repo t012)"
  mkdir -p "$d/docs/ai/reports" "$d/docs/ai/reviews"
  write_change_doc "$d/docs/issues/CHANGE-0001-a.md" "GA" "done"
  write_change_doc "$d/docs/issues/CHANGE-0002-b.md" "GB" "done"
  write_release_doc "$d/docs/releases/REL-1.md" "REL-1" "GA"
  write_closed_event "$d/docs/ai/EVENTS.jsonl" "GA" "2026-05-01T12:00:00Z"
  write_closed_event "$d/docs/ai/EVENTS.jsonl" "GB" "2026-06-01T12:00:00Z"
  run_report "$d" --data-only
  [[ "$EC" == 0 ]] || log_fail "factory must exit 0: $(cat "$OUT")"
  DJ="$d/docs/ai/factory-report-data.json"
  ( cd "$d" && node "$OVERVIEW" --output "$d/docs/ai/overview.html" >/dev/null 2>&1 ) || log_fail "overview run failed"
  local OJ="$d/docs/ai/overview-data.json"
  # GA: both must group it under a release; GB: both under a close-month.
  local fga oga fgb ogb ogb_label fgb_label
  fga="$(node_get "$DJ" '(m.throughput.delivered_groups.find(g=>g.refs.includes("GA"))||{}).kind')"
  oga="$(node_get "$OJ" '(m.delivered_groups.find(g=>g.items.some(i=>i.ref==="GA"))||{}).kind')"
  fgb="$(node_get "$DJ" '(m.throughput.delivered_groups.find(g=>g.refs.includes("GB"))||{}).kind')"
  ogb="$(node_get "$OJ" '(m.delivered_groups.find(g=>g.items.some(i=>i.ref==="GB"))||{}).kind')"
  fgb_label="$(node_get "$DJ" '(m.throughput.delivered_groups.find(g=>g.refs.includes("GB"))||{}).label')"
  ogb_label="$(node_get "$OJ" '(m.delivered_groups.find(g=>g.items.some(i=>i.ref==="GB"))||{}).label')"
  [[ "$fga" == "release" && "$oga" == "release" ]] || log_fail "GA grouping must be release in BOTH (factory=$fga overview=$oga)"
  [[ "$fgb" == "month" && "$ogb" == "month" ]] || log_fail "GB grouping must be month in BOTH (factory=$fgb overview=$ogb)"
  [[ "$fgb_label" == "$ogb_label" ]] || log_fail "SEAM 2 violated: close-month label differs (factory=$fgb_label overview=$ogb_label)"
  log_pass "SEAM 2: factory + overview agree on release membership and close-month label (TEST-012)"
}

# ============================ TEST-013 (Spec-AC-09) ==========================
test_013_close_regen_negative_control() {
  log_info "Test: NEGATIVE CONTROL — a rigged factory-report generator failure leaves the REAL close exit code unchanged, doc still done, no rollback (TEST-013)..."
  [[ -f "$CLOSE_SCRIPT" ]] || log_skip "close-work-item.mjs absent"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  local d; d="$(new_close_repo t013)"
  write_change_doc "$d/docs/issues/CHANGE-0001-t013.md" "t013-slug" "draft"
  git -C "$d" add -A && git -C "$d" commit -q -m "fixture doc"
  # Rig ONLY the factory report to fail: a directory where its data file must be
  # written -> fs.writeFileSync throws EISDIR inside regenerateFactoryReport-
  # BestEffort, which must swallow it (exercises the REAL generator failing).
  mkdir -p "$d/docs/ai/factory-report-data.json"
  local out="$TEST_DIR/t013.out" err="$TEST_DIR/t013.err" code=0
  ( cd "$d" && node "$CLOSE_SCRIPT" --ref t013-slug --pr 13 --commit c0c0c13 > "$out" 2> "$err" ) || code=$?
  [[ "$code" == 0 ]] || log_fail "close must survive a rigged factory-report failure (exit 0), got $code: $(cat "$err")"
  grep -q '^status: done$' "$d/docs/issues/CHANGE-0001-t013.md" \
    || log_fail "close must NOT be rolled back by the generator failure — doc must still be done"
  grep -qi 'factory' "$err" \
    || log_fail "expected an INFO best-effort line naming the factory report on stderr: $(cat "$err")"
  log_pass "Rigged factory-report failure is swallowed: close exit 0, doc still done, no rollback (TEST-013)"
}

# ============================ TEST-014 (Spec-AC-10) ==========================
test_014_empty_ledger() {
  log_info "Test: absent and comment-only METRICS both exit 0 with an empty model and a no-metrics marker (TEST-014)..."
  # (a) absent metrics file
  local da; da="$(mk_repo t014a)"
  rm -f "$da/docs/ai/METRICS.jsonl"
  run_report "$da" --data-only
  [[ "$EC" == 0 ]] || log_fail "absent metrics must exit 0: $(cat "$OUT")"
  [[ "$(node_get "$da/docs/ai/factory-report-data.json" 'm.empty')" == "true" ]] || log_fail "absent metrics must yield empty:true"
  # (b) comment-only metrics file
  local db; db="$(mk_repo t014b)"
  printf '# AAI Metrics Ledger — comment only\n' > "$db/docs/ai/METRICS.jsonl"
  run_report "$db" --data-only
  [[ "$EC" == 0 ]] || log_fail "comment-only metrics must exit 0: $(cat "$OUT")"
  [[ "$(node_get "$db/docs/ai/factory-report-data.json" 'm.empty')" == "true" ]] || log_fail "comment-only metrics must yield empty:true"
  [[ "$(node_get "$db/docs/ai/factory-report-data.json" 'm.empty_reason')" == "no metrics recorded yet" ]] || log_fail "empty_reason marker missing"
  log_pass "Absent and comment-only ledgers exit 0 with an empty model + marker (TEST-014)"
}

main() {
  echo "Testing $TEST_NAME (SPEC spec-factory-performance-report TEST-001..014)"
  check_deps
  setup_fixture
  test_001_data_only_blocks_present
  test_002_throughput_week_and_release
  test_003_lead_time
  test_004_role_normalization
  test_005_token_totals
  test_006_no_usd_anywhere
  test_007_quality_from_reliability
  test_008_html_matches_data
  test_009_weekly_series_zero_week
  test_010_malformed_line_noted
  test_011_seam_tokens_match_metrics_report
  test_012_seam_release_grouping_matches_overview
  test_013_close_regen_negative_control
  test_014_empty_ledger
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
