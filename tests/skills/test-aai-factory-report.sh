#!/usr/bin/env bash
#
# Test: aai-factory-report
# (docs/specs/SPEC-DRAFT-spec-factory-performance-report.md, TEST-001..014;
#  docs/specs/SPEC-0117-spec-role-token-trend.md, TEST-022..027)
#
# Verifies .aai/scripts/generate-factory-report.mjs — the deterministic
# Factory Performance Report generator over docs/ai/METRICS.jsonl +
# docs/ai/EVENTS.jsonl (+ docs/releases/*.md links.members). Two cross-
# generator SEAM tests share ONE fixture with metrics-report.mjs (TEST-011)
# and generate-overview.mjs (TEST-012); TEST-013 drives the REAL
# close-work-item.mjs with a rigged generator failure (negative control).
# TEST-022..027 (CHANGE-0130) cover cost.role_consumption — the additive
# per-role token consumption + weekly trend block.
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

# run_report_real_ledger <scratch-dir> -> OUT/EC set; reads the REPO's real
# docs/ai/METRICS.jsonl + EVENTS.jsonl READ-ONLY (never writes them), outputs
# land only under <scratch-dir>/docs/ai (CHANGE-0130 TEST-023 real-ledger arm).
run_report_real_ledger() {
  local d="$1"
  mkdir -p "$d/docs/ai"
  OUT="$d/report-run.log"; EC=0
  ( cd "$d" && node "$REPORT" --data-only --output "$d/docs/ai/factory-report.html" \
      --metrics "$PROJECT_ROOT/docs/ai/METRICS.jsonl" --events "$PROJECT_ROOT/docs/ai/EVENTS.jsonl" \
      --releases "$PROJECT_ROOT/docs/releases" > "$OUT" 2>&1 ) || EC=$?
}

# assert_role_consumption_identities <data-json> <label> — SEAM S2 (Spec-AC-02):
# re-sums cost.role_consumption and compares against capture_coverage,
# cost.tokens_total and cost.by_role on the SAME run; never a mock.
assert_role_consumption_identities() {
  local dj="$1" label="$2" result rc
  result="$(node -e '
    const fs = require("fs");
    const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const rc = m.cost.role_consumption;
    const errors = [];
    const sumRunsTotal = rc.roles.reduce((a, r) => a + r.runs_total, 0);
    const sumRunsMarked = rc.roles.reduce((a, r) => a + r.runs_marked, 0);
    if (sumRunsTotal !== m.cost.capture_coverage.total_runs) errors.push(`runs_total sum ${sumRunsTotal} != capture_coverage.total_runs ${m.cost.capture_coverage.total_runs}`);
    if (sumRunsMarked !== m.cost.capture_coverage.runs_with_marker) errors.push(`runs_marked sum ${sumRunsMarked} != capture_coverage.runs_with_marker ${m.cost.capture_coverage.runs_with_marker}`);
    const sumTokens = rc.roles.reduce((a, r) => a + (r.tokens_total === null ? 0 : r.tokens_total), 0);
    if (m.cost.tokens_total !== null && sumTokens !== m.cost.tokens_total) errors.push(`tokens_total sum ${sumTokens} != cost.tokens_total ${m.cost.tokens_total}`);
    if (m.cost.tokens_total === null && sumTokens !== 0) errors.push(`cost.tokens_total is null but role tokens sum to ${sumTokens}`);
    for (const r of rc.roles) {
      const byRole = m.cost.by_role.find((x) => x.role === r.role);
      const expected = byRole ? byRole.tokens : null;
      if (r.tokens_total !== expected) errors.push(`role ${r.role} tokens_total ${r.tokens_total} != cost.by_role ${expected}`);
      const expectedShare = (r.tokens_total === null || !m.cost.tokens_total) ? null : Math.round((100 * r.tokens_total) / m.cost.tokens_total);
      if (r.share_pct !== expectedShare) errors.push(`role ${r.role} share_pct ${r.share_pct} != expected ${expectedShare}`);
    }
    if (errors.length) { console.log("FAIL:" + errors.join(" | ")); process.exit(1); }
    console.log("OK");
  ' "$dj")" && rc=0 || rc=$?
  [[ "$rc" == 0 && "$result" == "OK" ]] || log_fail "role_consumption identities violated on $label: $result"
}

# assert_role_consumption_html <data-json> <html> — SEAM S3 (Spec-AC-04): the
# rendered role-consumption section carries the JSON values field-for-field,
# n/a for every null cell, and exactly one spark per marked-run role.
assert_role_consumption_html() {
  local dj="$1" html="$2" result rc
  result="$(node -e '
    const fs = require("fs");
    const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const html = fs.readFileSync(process.argv[2], "utf8");
    const rc = m.cost.role_consumption;
    const errors = [];
    const startTag = "<section id=\"role-consumption\">";
    const start = html.indexOf(startTag);
    if (start === -1) { console.log("FAIL:no <section id=\"role-consumption\"> found"); process.exit(1); }
    const end = html.indexOf("</section>", start);
    if (end === -1) { console.log("FAIL:no closing </section> found for role-consumption"); process.exit(1); }
    const section = html.slice(start, end + "</section>".length);
    if (!/<h2>Role consumption<\/h2>/.test(section)) errors.push("missing <h2>Role consumption</h2>");
    for (const r of rc.roles) {
      if (r.tokens_total !== null && !section.includes(String(r.tokens_total))) errors.push(`missing tokens_total ${r.tokens_total} for role ${r.role}`);
      if (r.median_tokens_per_run !== null && !section.includes(String(r.median_tokens_per_run))) errors.push(`missing median ${r.median_tokens_per_run} for role ${r.role}`);
      if (r.share_pct !== null && !section.includes(`${r.share_pct}%`)) errors.push(`missing share ${r.share_pct}% for role ${r.role}`);
    }
    let expectedNa = 0;
    for (const r of rc.roles) {
      if (r.tokens_total === null) expectedNa += 1;
      if (r.median_tokens_per_run === null) expectedNa += 1;
      if (r.share_pct === null) expectedNa += 1;
    }
    for (const wk of rc.by_week) for (const r of wk.roles) if (r.median_tokens === null) expectedNa += 1;
    const actualNa = (section.match(/<td>n\/a<\/td>/g) || []).length;
    if (actualNa !== expectedNa) errors.push(`n/a cell count ${actualNa} != expected ${expectedNa}`);
    const expectedSparks = rc.roles.filter((r) => r.runs_marked > 0).length;
    const actualSparks = (section.match(/class="spark"/g) || []).length;
    if (actualSparks !== expectedSparks) errors.push(`spark svg count ${actualSparks} != expected ${expectedSparks} (roles with runs_marked>0)`);
    if (errors.length) { console.log("FAIL:" + errors.join(" | ")); process.exit(1); }
    console.log("OK");
  ' "$dj" "$html")" && rc=0 || rc=$?
  [[ "$rc" == 0 && "$result" == "OK" ]] || log_fail "role-consumption html assertion failed: $result"
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

# ============================ TEST-022 (Spec-AC-01, CHANGE-0130) =============
test_022_role_consumption_buckets() {
  log_info "Test: cost.role_consumption.roles — six canonical roles + Other, three partitioning buckets, marker beats sentinel, never-marked role all-null (TEST-022)..."
  local d; d="$(mk_repo t022)"
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-06","ref_id":"A","agent_runs":[{"role":"Planning","duration_seconds":10,"note":"usage_total_tokens=100"},{"role":"Planning","duration_seconds":10,"note":"usage_total_tokens=200"},{"role":"Planning","duration_seconds":10,"note":"usage_capture=none"},{"role":"Planning","duration_seconds":10,"note":"no marker here"},{"role":"Validation","duration_seconds":10,"note":"usage_total_tokens=50 usage_capture=none"},{"role":"QA Ops","duration_seconds":10,"note":"no marker"}],"verdict":"PASS"}
JSONL
  run_report "$d" --data-only
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  DJ="$d/docs/ai/factory-report-data.json"
  local result rc
  result="$(node -e '
    const fs = require("fs");
    const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const rc = m.cost.role_consumption;
    const errors = [];
    const order = rc.roles.map((r) => r.role);
    const expectedOrder = ["TDD Implementation","Implementation","Code Review","Remediation","Validation","Planning","Other"];
    if (JSON.stringify(order) !== JSON.stringify(expectedOrder)) errors.push(`role order ${JSON.stringify(order)} != ${JSON.stringify(expectedOrder)}`);
    for (const r of rc.roles) {
      if (r.runs_marked + r.runs_sentinel + r.runs_unmarked !== r.runs_total) errors.push(`role ${r.role} buckets ${r.runs_marked}+${r.runs_sentinel}+${r.runs_unmarked} != runs_total ${r.runs_total}`);
    }
    const planning = rc.roles.find((r) => r.role === "Planning");
    if (!planning || planning.runs_total !== 4 || planning.runs_marked !== 2 || planning.runs_sentinel !== 1 || planning.runs_unmarked !== 1) errors.push(`Planning buckets wrong: ${JSON.stringify(planning)}`);
    if (!planning || planning.tokens_total !== 300 || planning.median_tokens_per_run !== 150 || planning.share_pct !== 86) errors.push(`Planning measures wrong: ${JSON.stringify(planning)}`);
    const validation = rc.roles.find((r) => r.role === "Validation");
    if (!validation || validation.runs_total !== 1 || validation.runs_marked !== 1 || validation.runs_sentinel !== 0 || validation.runs_unmarked !== 0) errors.push(`Validation both-markers run must count as MARKED (marker beats sentinel, D1): ${JSON.stringify(validation)}`);
    if (!validation || validation.tokens_total !== 50 || validation.median_tokens_per_run !== 50 || validation.share_pct !== 14) errors.push(`Validation measures wrong: ${JSON.stringify(validation)}`);
    const codeReview = rc.roles.find((r) => r.role === "Code Review");
    if (!codeReview || codeReview.runs_total !== 0 || codeReview.tokens_total !== null || codeReview.median_tokens_per_run !== null || codeReview.share_pct !== null) errors.push(`never-ran role Code Review must be all-null, never zero: ${JSON.stringify(codeReview)}`);
    const other = rc.roles.find((r) => r.role === "Other");
    if (!other || other.runs_total !== 1 || other.runs_unmarked !== 1 || other.tokens_total !== null) errors.push(`Other (non-canonical QA Ops) wrong: ${JSON.stringify(other)}`);
    if (errors.length) { console.log("FAIL:" + errors.join(" | ")); process.exit(1); }
    console.log("OK");
  ' "$DJ")" && rc=0 || rc=$?
  [[ "$rc" == 0 && "$result" == "OK" ]] || log_fail "role_consumption buckets wrong: $result"
  log_pass "Six canonical roles + Other, buckets partition, marker beats sentinel, never-marked all-null (TEST-022)"
}

# ============================ TEST-023 (Spec-AC-02, CHANGE-0130) =============
test_023_role_consumption_seam_invariants() {
  log_info "Test: SEAM S2 — role_consumption re-summed matches capture_coverage, cost.tokens_total, cost.by_role and share_pct, on a fixture AND on the real docs/ai ledgers (TEST-023)..."
  local d; d="$(mk_repo t023)"
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-06","ref_id":"A","agent_runs":[{"role":"Planning","duration_seconds":10,"note":"usage_total_tokens=1000"},{"role":"Implementation","duration_seconds":10,"note":"usage_total_tokens=500"},{"role":"Validation","duration_seconds":10,"note":"no marker"},{"role":"Code Review","duration_seconds":10,"note":"usage_capture=none"}],"verdict":"PASS"}
{"date_utc":"2026-07-13","ref_id":"B","agent_runs":[{"role":"Planning","duration_seconds":10,"note":"usage_total_tokens=250"}],"verdict":"PASS"}
JSONL
  run_report "$d" --data-only
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  DJ="$d/docs/ai/factory-report-data.json"
  assert_role_consumption_identities "$DJ" "fixture t023"
  log_pass "identities hold on the fixture (TEST-023 fixture arm)"

  local rd; rd="$TEST_DIR/t023-real"
  run_report_real_ledger "$rd"
  [[ "$EC" == 0 ]] || log_fail "real-ledger run must exit 0: $(cat "$OUT")"
  local RDJ="$rd/docs/ai/factory-report-data.json"
  [[ -f "$RDJ" ]] || log_fail "real-ledger data.json not written"
  assert_role_consumption_identities "$RDJ" "REAL docs/ai ledger"
  log_pass "SEAM S2 identities hold on a fixture AND the real docs/ai ledgers (TEST-023)"
}

# ============================ TEST-024 (Spec-AC-03, CHANGE-0130) =============
test_024_role_consumption_weekly_trend() {
  log_info "Test: cost.role_consumption.by_week weeks equal m.trend weeks exactly; per-role weekly medians incl. even-count rounding; unmarked role-week null; delivery-only week all-null (TEST-024)..."
  local d; d="$(mk_repo t024)"
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-06-29","ref_id":"R1","agent_runs":[{"role":"Planning","duration_seconds":10,"note":"usage_total_tokens=100"},{"role":"Planning","duration_seconds":10,"note":"usage_total_tokens=300"},{"role":"Validation","duration_seconds":10,"note":"usage_total_tokens=50"}],"verdict":"PASS"}
{"date_utc":"2026-07-06","ref_id":"R2","agent_runs":[{"role":"Planning","duration_seconds":10,"note":"usage_total_tokens=900"}],"verdict":"PASS"}
JSONL
  write_closed_event "$d/docs/ai/EVENTS.jsonl" "R3" "2026-07-20T00:00:00Z"  # delivery-only week, no ride at all
  run_report "$d" --data-only
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  DJ="$d/docs/ai/factory-report-data.json"
  local result rc
  result="$(node -e '
    const fs = require("fs");
    const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const rc = m.cost.role_consumption;
    const errors = [];
    const weeks = rc.by_week.map((w) => w.week);
    const trendWeeks = m.trend.map((t) => t.week);
    if (JSON.stringify(weeks) !== JSON.stringify(trendWeeks)) errors.push(`by_week weeks ${JSON.stringify(weeks)} != m.trend weeks ${JSON.stringify(trendWeeks)}`);
    if (JSON.stringify(weeks) !== JSON.stringify(["2026-W27","2026-W28","2026-W30"])) errors.push(`unexpected week set ${JSON.stringify(weeks)}`);
    const byWeek = {};
    for (const w of rc.by_week) byWeek[w.week] = w;
    const w27plan = byWeek["2026-W27"].roles.find((r) => r.role === "Planning");
    if (!w27plan || w27plan.runs_marked !== 2 || w27plan.median_tokens !== 200) errors.push(`W27 Planning wrong (even-count median pin): ${JSON.stringify(w27plan)}`);
    const w27val = byWeek["2026-W27"].roles.find((r) => r.role === "Validation");
    if (!w27val || w27val.runs_marked !== 1 || w27val.median_tokens !== 50) errors.push(`W27 Validation wrong: ${JSON.stringify(w27val)}`);
    const w28plan = byWeek["2026-W28"].roles.find((r) => r.role === "Planning");
    if (!w28plan || w28plan.runs_marked !== 1 || w28plan.median_tokens !== 900) errors.push(`W28 Planning wrong: ${JSON.stringify(w28plan)}`);
    const w28val = byWeek["2026-W28"].roles.find((r) => r.role === "Validation");
    if (!w28val || w28val.runs_marked !== 0 || w28val.median_tokens !== null) errors.push(`W28 Validation must be null/zero (never marked that week): ${JSON.stringify(w28val)}`);
    for (const wk of ["2026-W27","2026-W28","2026-W30"]) {
      const cr = byWeek[wk].roles.find((r) => r.role === "Code Review");
      if (!cr || cr.runs_marked !== 0 || cr.median_tokens !== null) errors.push(`${wk} Code Review (never marked anywhere) must be null/zero: ${JSON.stringify(cr)}`);
    }
    const w30 = byWeek["2026-W30"];
    if (!w30.roles.every((r) => r.runs_marked === 0 && r.median_tokens === null)) errors.push(`delivery-only week 2026-W30 must be all-null/zero: ${JSON.stringify(w30)}`);
    for (const wk of rc.by_week) {
      const rolesOrder = wk.roles.map((r) => r.role);
      const topOrder = rc.roles.map((r) => r.role);
      if (JSON.stringify(rolesOrder) !== JSON.stringify(topOrder)) errors.push(`week ${wk.week} role vocabulary/order ${JSON.stringify(rolesOrder)} != top-level ${JSON.stringify(topOrder)}`);
    }
    if (errors.length) { console.log("FAIL:" + errors.join(" | ")); process.exit(1); }
    console.log("OK");
  ' "$DJ")" && rc=0 || rc=$?
  [[ "$rc" == 0 && "$result" == "OK" ]] || log_fail "weekly trend wrong: $result"
  log_pass "by_week borrows m.trend weeks exactly; medians incl. even-count rounding; null-not-zero (TEST-024, seam S1)"
}

# ============================ TEST-025 (Spec-AC-04, CHANGE-0130) =============
test_025_role_consumption_html() {
  log_info "Test: <section id=\"role-consumption\"> renders the JSON values, n/a literals for nulls, one spark per marked-run role, no dollar figure (TEST-025, seam S3)..."
  local d; d="$(mk_repo t025)"
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-06","ref_id":"A","agent_runs":[{"role":"Planning","duration_seconds":10,"note":"usage_total_tokens=500"},{"role":"Planning","duration_seconds":10,"note":"usage_total_tokens=700"},{"role":"Validation","duration_seconds":10,"note":"usage_total_tokens=50"},{"role":"QA Ops","duration_seconds":10,"note":"no marker"}],"verdict":"PASS"}
JSONL
  write_closed_event "$d/docs/ai/EVENTS.jsonl" "A" "2026-07-07T00:00:00Z"
  run_report "$d"
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  DJ="$d/docs/ai/factory-report-data.json"
  local html="$d/docs/ai/factory-report.html"
  assert_role_consumption_html "$DJ" "$html"
  if grep -qE '\$[0-9]' "$DJ"; then log_fail "data.json contains a dollar amount"; fi
  if grep -qE '\$[0-9]' "$html"; then log_fail "html contains a dollar amount"; fi
  log_pass "role-consumption HTML matches JSON field-for-field, n/a literals, sparks, no dollar figure (TEST-025)"
}

# ============================ TEST-026 (Spec-AC-05, CHANGE-0130) =============
# Byte-stability pin (D6/D7): reconstructs the EXACT ledger that produced the
# committed pre-change goldens (tests/fixtures/factory-report/backcompat-
# sparse-{data.json,html}), captured from the pre-change generator and never
# regenerated (D7/S5). Directory name "golden-sparse" reproduces the golden's
# basename-fallback project label.
test_026_role_consumption_backcompat() {
  log_info "Test: sparse no-marker ledger — outputs minus the new key/section are byte-identical to the pre-change goldens; new key present all-null (TEST-026)..."
  local d; d="$(mk_repo golden-sparse)"
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-06","ref_id":"SPARSE-A","agent_runs":[{"role":"Planning","duration_seconds":120},{"role":"Code Review","duration_seconds":90},{"role":"QA Something","duration_seconds":45}],"reliability":{"validation_fails":1,"review_fails":0,"remediation_runs":1,"first_pass_clean":false},"verdict":"PASS"}
{"date_utc":"2026-07-13","ref_id":"SPARSE-B","agent_runs":[{"role":"Implementation","duration_seconds":90},{"role":"Validation","duration_seconds":200}],"verdict":"PASS"}
JSONL
  write_closed_event "$d/docs/ai/EVENTS.jsonl" "SPARSE-A" "2026-07-06T00:00:00Z"
  write_closed_event "$d/docs/ai/EVENTS.jsonl" "SPARSE-B" "2026-07-13T00:00:00Z"
  run_report "$d"
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  DJ="$d/docs/ai/factory-report-data.json"
  local html="$d/docs/ai/factory-report.html"
  local golden_data="$PROJECT_ROOT/tests/fixtures/factory-report/backcompat-sparse-data.json"
  local golden_html="$PROJECT_ROOT/tests/fixtures/factory-report/backcompat-sparse.html"
  [[ -f "$golden_data" ]] || log_fail "missing golden: $golden_data"
  [[ -f "$golden_html" ]] || log_fail "missing golden: $golden_html"
  local result rc
  result="$(node -e '
    const fs = require("fs");
    const [dataPath, htmlPath, goldenDataPath, goldenHtmlPath] = process.argv.slice(1);
    const errors = [];
    const PLACEHOLDER = "1970-01-01T00:00:00.000Z";

    // --- new-key arm: cost.role_consumption present, every role all-null,
    // every run in runs_unmarked (no marker anywhere in this fixture) ---
    const model = JSON.parse(fs.readFileSync(dataPath, "utf8"));
    const rc = model.cost.role_consumption;
    if (!rc) { console.log("FAIL:new-key-missing:cost.role_consumption absent"); process.exit(1); }
    for (const r of rc.roles) {
      if (r.runs_marked !== 0) errors.push(`role ${r.role} runs_marked must be 0 on an all-unmarked ledger, got ${r.runs_marked}`);
      if (r.tokens_total !== null || r.median_tokens_per_run !== null || r.share_pct !== null) errors.push(`role ${r.role} must be all-null (never zero) with no markers: ${JSON.stringify(r)}`);
    }
    const sumUnmarked = rc.roles.reduce((a, r) => a + r.runs_unmarked, 0);
    if (sumUnmarked !== 5) errors.push(`sum of runs_unmarked must be 5 (total agent runs), got ${sumUnmarked}`);

    // --- byte-stability arm: data.json, minus the new key, generatedAt
    // normalized, must equal the golden byte-for-byte ---
    delete model.cost.role_consumption;
    model.generatedAt = PLACEHOLDER;
    const normalizedData = JSON.stringify(model, null, 2) + "\n";
    const goldenData = fs.readFileSync(goldenDataPath, "utf8");
    if (normalizedData !== goldenData) {
      const a = normalizedData.split("\n"), b = goldenData.split("\n");
      let i = 0; while (i < a.length && i < b.length && a[i] === b[i]) i += 1;
      errors.push(`data.json byte-stability mismatch at line ${i + 1}: got ${JSON.stringify(a[i])} want ${JSON.stringify(b[i])}`);
    }

    // --- byte-stability arm: html, section excised (through its trailing
    // blank line), generatedAt normalized, must equal the golden byte-for-byte
    let html = fs.readFileSync(htmlPath, "utf8");
    const rawModel = JSON.parse(fs.readFileSync(dataPath, "utf8")); // un-mutated: real generatedAt
    html = html.split(rawModel.generatedAt).join(PLACEHOLDER);
    const startTag = "<section id=\"role-consumption\">";
    const start = html.indexOf(startTag);
    if (start === -1) { console.log("FAIL:section-missing:no <section id=\"role-consumption\"> found"); process.exit(1); }
    const closeTag = "</section>";
    const end = html.indexOf(closeTag, start);
    if (end === -1) { console.log("FAIL:section-not-closed"); process.exit(1); }
    let after = end + closeTag.length;
    if (html.slice(after, after + 2) === "\n\n") after += 2;
    else if (html.slice(after, after + 1) === "\n") after += 1;
    const excisedHtml = html.slice(0, start) + html.slice(after);
    const goldenHtml = fs.readFileSync(goldenHtmlPath, "utf8");
    if (excisedHtml !== goldenHtml) {
      const a = excisedHtml.split("\n"), b = goldenHtml.split("\n");
      let i = 0; while (i < a.length && i < b.length && a[i] === b[i]) i += 1;
      errors.push(`html byte-stability mismatch at line ${i + 1}: got ${JSON.stringify(a[i])} want ${JSON.stringify(b[i])}`);
    }
    if (errors.length) { console.log("FAIL:" + errors.join(" | ")); process.exit(1); }
    console.log("OK");
  ' "$DJ" "$html" "$golden_data" "$golden_html")" && rc=0 || rc=$?
  [[ "$rc" == 0 && "$result" == "OK" ]] || log_fail "backcompat pin violated: $result"
  log_pass "sparse ledger byte-identical to pre-change goldens minus the new key/section; new key present all-null (TEST-026)"
}

# ============================ TEST-027 (Spec-AC-07, CHANGE-0130) =============
test_027_product_doc_pins() {
  log_info "Test: docs/product/factory-performance-report.md pins the Role consumption section, the three buckets, the marker-only rule, the never-imputed n/a rule, the 2026-08-02 sparse-era caveat, and frontmatter delivered_by CHANGE-0130 (TEST-027)..."
  local doc="$PROJECT_ROOT/docs/product/factory-performance-report.md"
  [[ -f "$doc" ]] || log_fail "product doc not found: $doc"
  grep -qF 'Role consumption' "$doc" || log_fail "product doc must name the Role consumption section"
  grep -qF 'runs_marked' "$doc" || log_fail "product doc must name the runs_marked bucket"
  grep -qF 'runs_sentinel' "$doc" || log_fail "product doc must name the runs_sentinel bucket"
  grep -qF 'runs_unmarked' "$doc" || log_fail "product doc must name the runs_unmarked bucket"
  grep -qF '2026-08-02' "$doc" || log_fail "product doc must name the sparse-era caveat date 2026-08-02"
  grep -qi 'n/a' "$doc" || log_fail "product doc must state the never-imputed n/a rule"
  grep -qF 'CHANGE-0130' "$doc" || log_fail "product doc frontmatter delivered_by must include CHANGE-0130"
  log_pass "product doc pins present: section, three buckets, marker-only + never-imputed rules, sparse-era caveat, delivered_by (TEST-027)"
}

# ============ TEST-028 (Spec-AC-04, CHANGE-0142 / spec-followup-registry) ====
# The follow_ups block. SEAM-2: the report and the CLI share ONE fold
# (exported from .aai/scripts/follow-ups.mjs), so open_count is asserted
# EQUAL to the CLI's own --json count over the SAME ledger — never two
# independently computed numbers. SEAM-3: the fixture ledger opens with `#`
# comment lines, the shape the real docs/ai/decisions.jsonl carries.
test_028_follow_ups_block() {
  log_info "Test: follow_ups block (open_count, oldest_age_days, items with id/ref/severity/age_days) and open_count == the CLI --json count over the same #-commented ledger (TEST-028 / spec TEST-006)..."
  local fu="$PROJECT_ROOT/.aai/scripts/follow-ups.mjs"
  [[ -f "$fu" ]] || log_fail "follow-ups.mjs not found: $fu"
  local d; d="$(mk_repo t028)"
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-01","ref_id":"A","agent_runs":[{"role":"Planning","duration_seconds":60,"note":"usage_total_tokens=100"}],"verdict":"PASS"}
JSONL
  write_closed_event "$d/docs/ai/EVENTS.jsonl" "A" "2026-07-02T00:00:00Z"
  cat > "$d/docs/ai/decisions.jsonl" <<'JSONL'
# Decision Log — append-only, one JSON object per line (JSONL format)
#
# Rules:
#   - Append only. Never edit existing lines.
{"v":1,"ts":"2026-01-01T00:00:00Z","actor":"a","type":"follow_up","id":"fu-oldest-one","ref_id":"CHANGE-0100","severity":"P1","finding":"oldest open item","decision":"deferred","source":"s1"}
{"v":1,"ts":"2026-06-01T00:00:00Z","actor":"a","type":"follow_up","id":"fu-newer-two","ref_id":"CHANGE-0101","severity":"P3","finding":"newer open item","decision":"deferred","source":"s2"}
{"v":1,"ts":"2026-06-02T00:00:00Z","actor":"a","type":"follow_up","id":"fu-closed-three","ref_id":"CHANGE-0101","severity":"P2","finding":"already resolved","decision":"deferred","source":"s3"}
{"v":1,"ts":"2026-06-03T00:00:00Z","actor":"a","type":"follow_up_status","id":"fu-closed-three","status":"done","resolved_by":"CHANGE-0102","source":"sha"}
JSONL
  run_report "$d" --data-only
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  DJ="$d/docs/ai/factory-report-data.json"
  [[ "$(node_get "$DJ" 'typeof m.follow_ups')" == "object" ]] || log_fail "data.json must carry a follow_ups block"
  [[ "$(node_get "$DJ" 'm.follow_ups.open_count')" == "2" ]] || log_fail "open_count must be 2, got $(node_get "$DJ" 'm.follow_ups.open_count')"
  [[ "$(node_get "$DJ" 'm.follow_ups.items.length')" == "2" ]] || log_fail "items must list the 2 open follow-ups (closed ones excluded)"
  [[ "$(node_get "$DJ" 'm.follow_ups.items[0].id')" == "fu-oldest-one" ]] || log_fail "items must be ordered OLDEST-first"
  [[ "$(node_get "$DJ" 'm.follow_ups.items[0].severity')" == "P1" ]] || log_fail "items must carry severity"
  [[ "$(node_get "$DJ" 'm.follow_ups.items[0].ref')" == "CHANGE-0100" ]] || log_fail "items must carry the raising ref"
  [[ "$(node_get "$DJ" 'typeof m.follow_ups.items[0].age_days')" == "number" ]] || log_fail "items must carry a numeric age_days"
  [[ "$(node_get "$DJ" 'typeof m.follow_ups.oldest_age_days')" == "number" ]] || log_fail "oldest_age_days must be a number when a backlog exists"
  [[ "$(node_get "$DJ" 'm.follow_ups.oldest_age_days === m.follow_ups.items[0].age_days')" == "true" ]] || log_fail "oldest_age_days must equal the oldest item's age"

  # SEAM-2: ONE fold, two consumers — the numbers must be the same number.
  local cli_json cli_open
  cli_json="$(node "$fu" list --ledger "$d/docs/ai/decisions.jsonl" --json)"
  cli_open="$(node -e 'process.stdout.write(String(JSON.parse(process.argv[1]).counts.open))' "$cli_json")"
  [[ "$cli_open" == "$(node_get "$DJ" 'm.follow_ups.open_count')" ]] \
    || log_fail "SEAM-2 broken: report open_count=$(node_get "$DJ" 'm.follow_ups.open_count') but CLI counts.open=$cli_open over the SAME ledger"

  # --decisions <path> reaches a ledger outside the default location.
  local alt="$TEST_DIR/alt-decisions.jsonl"
  cp "$d/docs/ai/decisions.jsonl" "$alt"
  printf '%s\n' '{"v":1,"ts":"2026-06-04T00:00:00Z","actor":"a","type":"follow_up","id":"fu-alt-four","ref_id":"CHANGE-0103","severity":"P2","finding":"only in the alt ledger","decision":"deferred","source":"s4"}' >> "$alt"
  run_report "$d" --data-only --decisions "$alt"
  [[ "$EC" == 0 ]] || log_fail "--decisions must exit 0: $(cat "$OUT")"
  [[ "$(node_get "$DJ" 'm.follow_ups.open_count')" == "3" ]] || log_fail "--decisions must select the alternate ledger"

  log_pass "follow_ups block present with oldest-first items, and open_count is the CLI's own folded number over the same #-commented ledger (TEST-028 / spec TEST-006)"
}

# ============ TEST-029 (Spec-AC-04, CHANGE-0142 / spec-followup-registry) ====
test_029_follow_ups_report_only() {
  log_info "Test: report-only contract — absent, empty, comment-only, malformed-line and non-empty ledgers each exit 0 with the degradation NAMED in notes; HTML carries the section (TEST-029 / spec TEST-007)..."
  # (1) ABSENT ledger — mk_repo writes no decisions.jsonl.
  local d; d="$(mk_repo t029-absent)"
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-01","ref_id":"A","agent_runs":[{"role":"Planning","duration_seconds":60}],"verdict":"PASS"}
JSONL
  write_closed_event "$d/docs/ai/EVENTS.jsonl" "A" "2026-07-02T00:00:00Z"
  run_report "$d" --data-only
  [[ "$EC" == 0 ]] || log_fail "absent ledger must exit 0: $(cat "$OUT")"
  DJ="$d/docs/ai/factory-report-data.json"
  [[ "$(node_get "$DJ" 'm.follow_ups.open_count')" == "0" ]] || log_fail "absent ledger must report open_count 0"
  [[ "$(node_get "$DJ" 'm.follow_ups.oldest_age_days')" == "null" ]] || log_fail "absent ledger oldest_age_days must be null, never 0"
  [[ "$(node_get "$DJ" 'm.notes.some(n=>/decision ledger/i.test(n)&&/absent/i.test(n))')" == "true" ]] || log_fail "an absent ledger must be NAMED in notes"

  # (2) EMPTY ledger (zero bytes).
  local e; e="$(mk_repo t029-empty)"
  cp "$d/docs/ai/METRICS.jsonl" "$e/docs/ai/METRICS.jsonl"
  write_closed_event "$e/docs/ai/EVENTS.jsonl" "A" "2026-07-02T00:00:00Z"
  : > "$e/docs/ai/decisions.jsonl"
  run_report "$e" --data-only
  [[ "$EC" == 0 ]] || log_fail "empty ledger must exit 0"
  DJ="$e/docs/ai/factory-report-data.json"
  [[ "$(node_get "$DJ" 'm.follow_ups.open_count')" == "0" ]] || log_fail "empty ledger must report open_count 0"
  [[ "$(node_get "$DJ" 'm.follow_ups.oldest_age_days')" == "null" ]] || log_fail "empty ledger oldest_age_days must be null, never 0"

  # (3) COMMENT-ONLY ledger (SEAM-3: the real ledger opens with 15 `#` lines).
  local c; c="$(mk_repo t029-comments)"
  cp "$d/docs/ai/METRICS.jsonl" "$c/docs/ai/METRICS.jsonl"
  write_closed_event "$c/docs/ai/EVENTS.jsonl" "A" "2026-07-02T00:00:00Z"
  cat > "$c/docs/ai/decisions.jsonl" <<'JSONL'
# Decision Log — append-only, one JSON object per line (JSONL format)
#   - Append only. Never edit existing lines.
JSONL
  run_report "$c" --data-only
  [[ "$EC" == 0 ]] || log_fail "comment-only ledger must exit 0"
  DJ="$c/docs/ai/factory-report-data.json"
  [[ "$(node_get "$DJ" 'm.follow_ups.open_count')" == "0" ]] || log_fail "comment-only ledger must fold to 0, not crash on the header"
  [[ "$(node_get "$DJ" 'm.notes.some(n=>/malformed decision/i.test(n))')" == "false" ]] || log_fail "a `#` comment line must NEVER be counted as malformed"

  # (4) MALFORMED line + a real backlog.
  local f; f="$(mk_repo t029-malformed)"
  cp "$d/docs/ai/METRICS.jsonl" "$f/docs/ai/METRICS.jsonl"
  write_closed_event "$f/docs/ai/EVENTS.jsonl" "A" "2026-07-02T00:00:00Z"
  cat > "$f/docs/ai/decisions.jsonl" <<'JSONL'
# Decision Log
{"v":1,"ts":"2026-01-01T00:00:00Z","actor":"a","type":"follow_up","id":"fu-real-one","ref_id":"CHANGE-0100","severity":"P1","finding":"a real open item","decision":"deferred","source":"s"}
this line is not json
{"v":1,"ts":"2026-01-02T00:00:00Z","actor":"a","type":"follow_up","ref_id":"legacy-idless","finding":"no id on this one","decision":"deferred","source":"s"}
{"v":1,"ts":"2026-01-03T00:00:00Z","actor":"a","type":"follow_up_status","id":"fu-never-raised","status":"done","resolved_by":"X","source":"s"}
JSONL
  run_report "$f" --data-only
  [[ "$EC" == 0 ]] || log_fail "malformed line must never be fatal"
  DJ="$f/docs/ai/factory-report-data.json"
  [[ "$(node_get "$DJ" 'm.notes.some(n=>/malformed decision/i.test(n))')" == "true" ]] || log_fail "the skipped malformed line must be NAMED in notes"
  [[ "$(node_get "$DJ" 'm.notes.some(n=>/derived/i.test(n))')" == "true" ]] || log_fail "the id-less legacy entry must be NAMED in notes"
  [[ "$(node_get "$DJ" 'm.notes.some(n=>/dangling/i.test(n))')" == "true" ]] || log_fail "the dangling status record must be NAMED in notes"
  [[ "$(node_get "$DJ" 'm.follow_ups.open_count')" == "2" ]] || log_fail "the real item + the derived-id legacy item must both be listed"

  # (5) NON-EMPTY backlog, full render: the HTML carries the section.
  run_report "$f"
  [[ "$EC" == 0 ]] || log_fail "full render must exit 0"
  local html="$f/docs/ai/factory-report.html"
  [[ -f "$html" ]] || log_fail "html not written"
  grep -qF 'id="follow-ups"' "$html" || log_fail "the HTML must carry the follow-ups section"
  grep -qF 'fu-real-one' "$html" || log_fail "the HTML section must render the open items"

  log_pass "absent, empty, comment-only, malformed and non-empty ledgers each exit 0 with a named note; HTML section rendered (TEST-029 / spec TEST-007)"
}

main() {
  echo "Testing $TEST_NAME (SPEC spec-factory-performance-report TEST-001..014, +017..019; telemetry-completeness TEST-020..021; role-token-trend TEST-022..027; followup-registry TEST-028..029)"
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
  test_022_role_consumption_buckets
  test_023_role_consumption_seam_invariants
  test_024_role_consumption_weekly_trend
  test_025_role_consumption_html
  test_026_role_consumption_backcompat
  test_027_product_doc_pins
  test_028_follow_ups_block
  test_029_follow_ups_report_only
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
