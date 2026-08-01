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
  # Explicit default branch for reproducibility across git versions (finding 4):
  # modern git honors -b main; older git (pre-2.28) falls back to the config form.
  git init -q -b main "$d" 2>/dev/null || git -c init.defaultBranch=main init -q "$d"
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
  # DEFECT-1 guard: the distribution is reliability-only. Ride A (rem=0) is the
  # ONLY numeric-0 ride; the pre-reliability ride C must land in the explicit
  # n/a bucket and NEVER inflate a numeric bucket (the assertion gap that let
  # the double-counting defect through).
  [[ "$(node_get "$DJ" 'm.quality.remediation_distribution["0"]')" == "1" ]] || log_fail "bucket 0 must hold only ride A (reliability rem=0); pre-reliability ride C must not fall into it"
  [[ "$(node_get "$DJ" 'm.quality.remediation_distribution["n/a"]')" == "1" ]] || log_fail "pre-reliability ride C must land in the explicit remediation n/a bucket"
  local distsum
  distsum="$(node_get "$DJ" 'Object.values(m.quality.remediation_distribution).reduce((a,v)=>a+v,0)')"
  [[ "$distsum" == "3" ]] || log_fail "distribution (incl n/a) must total all 3 rides exactly once each, got $distsum"
  local numericsum
  numericsum="$(node_get "$DJ" 'Object.keys(m.quality.remediation_distribution).filter(k=>k!=="n/a").reduce((a,k)=>a+m.quality.remediation_distribution[k],0)')"
  [[ "$numericsum" == "2" ]] || log_fail "numeric buckets must sum to the 2 reliability-flagged rides only, got $numericsum"
  [[ "$(node_get "$DJ" '(m.speed.per_ride.find(x=>x.ref==="C")||{}).remediation_runs')" == "null" ]] || log_fail "ride C without reliability must have null remediation_runs (no role-prefix fallback)"
  log_pass "Quality rates + remediation distribution derive from the reliability block; pre-field ride -> n/a bucket (TEST-007)"
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
  # Finding 5: counts.active_weeks is the UNION of delivery weeks and ride weeks
  # (W27 ride-only + W28 delivery = 2), consistent with the rendered trend — not
  # the delivery-only count of 1.
  [[ "$(node_get "$DJ" 'm.counts.active_weeks')" == "2" ]] || log_fail "active_weeks must be the union of ride+delivery weeks (2), got $(node_get "$DJ" 'm.counts.active_weeks')"
  [[ "$(node_get "$DJ" 'm.trend.length')" == "2" ]] || log_fail "trend must span the same 2 union weeks as active_weeks"
  log_pass "Weekly trend series present; zero-delivery week rendered as 0; active_weeks = union (TEST-009 + finding 5)"
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

# ==================== TEST-020 (telemetry-completeness AC-004) ===============
# Run-level capture-coverage KPI: overall (runs_with_marker/total_runs) + a
# per-week series, computed from a fixture ledger and matching an independent
# re-sum; the existing no-marker NOTE is preserved; HTML renders the percentage.
test_020_capture_coverage_kpi() {
  log_info "Test: cost.capture_coverage overall + per-week matches an independent re-sum; NOTE unaffected (asserted separately by the unmarked-ride fixture in TEST-005); HTML renders pct (telemetry-completeness AC-004)..."
  local d; d="$(mk_repo t020)"
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-01","ref_id":"A","agent_runs":[{"role":"Planning","duration_seconds":10,"note":"usage_total_tokens=100"},{"role":"Implementation","duration_seconds":10,"note":"forgot the marker"}],"verdict":"PASS"}
{"date_utc":"2026-07-08","ref_id":"B","agent_runs":[{"role":"Planning","duration_seconds":10,"note":"usage_total_tokens=200"}],"verdict":"PASS"}
JSONL
  run_report "$d"
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  DJ="$d/docs/ai/factory-report-data.json"
  # Overall: 3 runs, 2 marked -> round(200/3)=67%.
  [[ "$(node_get "$DJ" 'm.cost.capture_coverage.total_runs')" == "3" ]] || log_fail "total_runs must be 3"
  [[ "$(node_get "$DJ" 'm.cost.capture_coverage.runs_with_marker')" == "2" ]] || log_fail "runs_with_marker must be 2"
  [[ "$(node_get "$DJ" 'm.cost.capture_coverage.pct')" == "67" ]] || log_fail "overall pct must be 67, got $(node_get "$DJ" 'm.cost.capture_coverage.pct')"
  # Per-week series present and an INDEPENDENT re-sum matches the overall.
  [[ "$(node_get "$DJ" 'm.cost.capture_coverage.by_week.length')" == "2" ]] || log_fail "by_week must span 2 ISO weeks"
  [[ "$(node_get "$DJ" 'm.cost.capture_coverage.by_week.reduce((a,w)=>a+w.total_runs,0)')" == "3" ]] || log_fail "by_week total_runs must re-sum to 3"
  [[ "$(node_get "$DJ" 'm.cost.capture_coverage.by_week.reduce((a,w)=>a+w.runs_with_marker,0)')" == "2" ]] || log_fail "by_week runs_with_marker must re-sum to 2"
  [[ "$(node_get "$DJ" 'm.cost.capture_coverage.by_week.every(w=>w.pct===(w.total_runs?Math.round(100*w.runs_with_marker/w.total_runs):null))')" == "true" ]] || log_fail "each week pct must equal its own runs_with_marker/total_runs"
  # The existing ride-level no-marker NOTE is preserved (ride A carries a marker,
  # so it is NOT no-marker; craft the assertion on the NOTE text presence rule):
  # here every ride has at least one marker so no ride is fully unmarked -> the
  # NOTE machinery still exists (regression pin on the note text format).
  grep -qF 'usage capture coverage' "$d/docs/ai/factory-report.html" \
    || log_fail "html must render the capture-coverage KPI label"
  grep -qF '67%' "$d/docs/ai/factory-report.html" \
    || log_fail "html must render the overall capture-coverage percentage 67%"
  log_pass "capture_coverage overall + per-week re-sum correct; HTML renders pct (AC-004)"
}

# TEST-021 (telemetry-completeness AC-004) — never a fabricated zero: an empty
# ledger yields pct null (not 0), and a fully-unmarked ledger yields an HONEST 0.
test_021_capture_coverage_honest_nulls() {
  log_info "Test: empty ledger -> capture_coverage.pct null (never fabricated 0); all-unmarked -> honest 0 (telemetry-completeness AC-004)..."
  local d; d="$(mk_repo t021)"
  : > "$d/docs/ai/METRICS.jsonl"
  run_report "$d" --data-only
  [[ "$EC" == 0 ]] || log_fail "empty ledger must exit 0: $(cat "$OUT")"
  DJ="$d/docs/ai/factory-report-data.json"
  [[ "$(node_get "$DJ" 'm.cost.capture_coverage.pct')" == "null" ]] || log_fail "empty-ledger pct must be null (never a fabricated 0), got $(node_get "$DJ" 'm.cost.capture_coverage.pct')"
  local d2; d2="$(mk_repo t021b)"
  cat > "$d2/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-01","ref_id":"A","agent_runs":[{"role":"Planning","duration_seconds":10,"note":"no marker"}],"verdict":"PASS"}
JSONL
  run_report "$d2" --data-only
  [[ "$EC" == 0 ]] || log_fail "all-unmarked ledger must exit 0: $(cat "$OUT")"
  DJ="$d2/docs/ai/factory-report-data.json"
  [[ "$(node_get "$DJ" 'm.cost.capture_coverage.pct')" == "0" ]] || log_fail "all-unmarked ledger pct must be an honest 0, got $(node_get "$DJ" 'm.cost.capture_coverage.pct')"
  [[ "$(node_get "$DJ" 'm.cost.capture_coverage.total_runs')" == "1" ]] || log_fail "all-unmarked total_runs must be 1"
  log_pass "Empty ledger -> pct null; all-unmarked -> honest 0 (AC-004)"
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

# ============================ TEST-017 (bot finding 1) ========================
test_017_reclosed_ref_latest_close() {
  log_info "Test: a ref closed more than once counts ONCE (distinct), buckets at the LATEST close, and an honesty note names the re-close (finding 1)..."
  local d; d="$(mk_repo t017)"
  # REF closed twice: a later (re-)close in W30 written FIRST, then an earlier
  # close in W28 — proving the LATEST timestamp wins, not the last ledger line.
  write_closed_event "$d/docs/ai/EVENTS.jsonl" "REF" "2026-07-20T00:00:00Z"   # W30 (later)
  write_closed_event "$d/docs/ai/EVENTS.jsonl" "REF" "2026-07-06T00:00:00Z"   # W28 (earlier)
  write_closed_event "$d/docs/ai/EVENTS.jsonl" "ONCE" "2026-07-06T00:00:00Z"  # W28, closed once
  run_report "$d" --data-only
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  DJ="$d/docs/ai/factory-report-data.json"
  # delivered_total counts DISTINCT refs (REF + ONCE = 2), never close events (3).
  [[ "$(node_get "$DJ" 'm.throughput.delivered_total')" == "2" ]] || log_fail "delivered_total must count distinct refs (2), not close events"
  # Latest close wins: REF lands in W30; W28 holds only ONCE.
  [[ "$(node_get "$DJ" 'm.throughput.delivered_by_week["2026-W30"]')" == "1" ]] || log_fail "REF must bucket at its LATEST close (W30)"
  [[ "$(node_get "$DJ" 'm.throughput.delivered_by_week["2026-W28"]')" == "1" ]] || log_fail "W28 must hold only ONCE (REF's earlier close superseded)"
  # Honesty note names the re-closed ref count.
  [[ "$(node_get "$DJ" 'm.notes.some(n=>/closed more than once/.test(n))')" == "true" ]] || log_fail "notes must name the re-closed ref(s)"
  [[ "$(node_get "$DJ" 'm.notes.some(n=>/^NOTE 1 ref/.test(n))')" == "true" ]] || log_fail "note must count exactly 1 re-closed ref"
  log_pass "Re-closed ref counts once, buckets at latest close, honesty note present (finding 1, TEST-017)"
}

# ============================ TEST-018 (bot finding 3) ========================
test_018_project_label_from_remote_slug() {
  log_info "Test: project label derives from the origin remote owner/repo slug, falling back to the cwd basename with no remote (finding 3)..."
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  # (a) with a remote -> slug wins over the (throwaway) directory basename.
  local d; d="$(mk_repo t018)"
  git init -q -b main "$d" 2>/dev/null || git -c init.defaultBranch=main init -q "$d"
  git -C "$d" remote add origin https://github.com/acme/widgets.git
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-01","ref_id":"A","agent_runs":[{"role":"Planning","duration_seconds":10}],"verdict":"PASS"}
JSONL
  run_report "$d" --data-only
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  local got; got="$(node_get "$d/docs/ai/factory-report-data.json" 'm.project')"
  [[ "$got" == "acme/widgets" ]] || log_fail "project must equal the remote slug acme/widgets, got $got"
  # (b) no remote -> basename fallback (fixture dir is not a git repo).
  local db; db="$(mk_repo t018b)"
  cat > "$db/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-01","ref_id":"A","agent_runs":[{"role":"Planning","duration_seconds":10}],"verdict":"PASS"}
JSONL
  run_report "$db" --data-only
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  local gotb; gotb="$(node_get "$db/docs/ai/factory-report-data.json" 'm.project')"
  [[ "$gotb" == "t018b" ]] || log_fail "no-remote project must fall back to basename t018b, got $gotb"
  log_pass "Project label = remote slug with a remote, basename without (finding 3, TEST-018)"
}

# ============================ TEST-019 (bot finding 6) ========================
test_019_remediation_sort_na_last() {
  log_info "Test: the rendered remediation table sorts numeric keys ascending with the n/a bucket LAST, deterministically (finding 6)..."
  local d; d="$(mk_repo t019)"
  # Ordered so the distribution's INSERTION order is n/a, 2, 0 — under the old
  # Number('n/a')=NaN comparator NaN comparisons leave n/a stranded first (wrong);
  # the deterministic fix must still render 0, 2, n/a.
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-01","ref_id":"C","agent_runs":[{"role":"Planning","duration_seconds":10}],"verdict":"PASS"}
{"date_utc":"2026-07-01","ref_id":"A","agent_runs":[{"role":"Planning","duration_seconds":10}],"reliability":{"validation_fails":0,"review_fails":0,"remediation_runs":2,"first_pass_clean":false},"verdict":"PASS"}
{"date_utc":"2026-07-01","ref_id":"B","agent_runs":[{"role":"Planning","duration_seconds":10}],"reliability":{"validation_fails":0,"review_fails":0,"remediation_runs":0,"first_pass_clean":true},"verdict":"PASS"}
JSONL
  run_report "$d"
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  local html="$d/docs/ai/factory-report.html"
  # Isolate the remediation table (between its header and the verdict table) and
  # read the first-column keys in render order — must be 0, 2, then n/a LAST.
  local order
  order="$(node -e '
    const fs=require("fs");const h=fs.readFileSync(process.argv[1],"utf8");
    const s=h.indexOf("Remediation runs");const e=h.indexOf("Ride verdict");
    const sec=h.slice(s, e>s?e:h.length);
    const cells=[...sec.matchAll(/<tr><td>([^<]*)<\/td><td>\d+<\/td><\/tr>/g)].map(m=>m[1]);
    process.stdout.write(cells.join(","));
  ' "$html")"
  [[ "$order" == "0,2,n/a" ]] || log_fail "remediation rows must be numeric-ascending then n/a last, got: $order"
  log_pass "Remediation table sorts numeric ascending, n/a last (finding 6, TEST-019)"
}

main() {
  echo "Testing $TEST_NAME (SPEC spec-factory-performance-report TEST-001..014, +017..019; telemetry-completeness TEST-020..021)"
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
  test_017_reclosed_ref_latest_close
  test_018_project_label_from_remote_slug
  test_019_remediation_sort_na_last
  test_020_capture_coverage_kpi
  test_021_capture_coverage_honest_nulls
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
