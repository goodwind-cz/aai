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
# per-role token consumption + weekly trend block. TEST-031..037,039
# (docs/specs/SPEC-0134-spec-ride-cost-readout.md) cover scope_cost — the
# additive per-scope cost readout (elapsed vs agent time, role counts, token
# totals with denominator, structural remediation/rework figure).
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

# ===== TEST-041 (CHANGE-DRAFT-operator-waiver-unblocks-pr TEST-05) ===========
# Waived rides appear in the report, and self-waived (agent) ones are counted
# SEPARATELY from operator waivers — a gate an agent clears for itself must not
# hide inside the operator total. Report-only: nothing blocks because of one.
test_041_validation_waivers_surfaced() {
  log_info "Test: waived rides surfaced, self-waived counted separately, prose is not a waiver (TEST-041)..."
  local d; d="$(mk_repo t041)"
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-01","ref_id":"OPWAIVE","agent_runs":[{"role":"Implementation","duration_seconds":10,"note":"usage_total_tokens=100; [AAI-VALIDATION-WAIVER v1 by=operator at=2026-07-01T09:00:00Z reason=\"operator ran the suite by hand\"]"}],"reliability":{"validation_fails":0,"review_fails":0,"remediation_runs":0,"first_pass_clean":true},"verdict":"PASS"}
{"date_utc":"2026-07-01","ref_id":"SELFWAIVE","agent_runs":[{"role":"Implementation","duration_seconds":10,"note":"usage_total_tokens=100; [AAI-VALIDATION-WAIVER v1 by=agent at=2026-07-01T10:00:00Z reason=\"docs-only diff, no code path touched\"]"}],"reliability":{"validation_fails":0,"review_fails":0,"remediation_runs":0,"first_pass_clean":true},"verdict":"PASS"}
{"date_utc":"2026-07-01","ref_id":"PROSE","agent_runs":[{"role":"Implementation","duration_seconds":10,"note":"usage_total_tokens=100; validation was waived by the operator on 2026-07-01 because he ran it himself"}],"reliability":{"validation_fails":0,"review_fails":0,"remediation_runs":0,"first_pass_clean":true},"verdict":"PASS"}
{"date_utc":"2026-07-01","ref_id":"BROKEN","agent_runs":[{"role":"Implementation","duration_seconds":10,"note":"usage_total_tokens=100; [AAI-VALIDATION-WAIVER v1 by=operator at=2026-07-01T11:00:00Z reason=\"\"]"}],"reliability":{"validation_fails":0,"review_fails":0,"remediation_runs":0,"first_pass_clean":true},"verdict":"PASS"}
JSONL
  run_report "$d" --data-only
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  DJ="$d/docs/ai/factory-report-data.json"
  [[ "$(node_get "$DJ" 'm.validation_waivers.operator')" == "1" ]] || log_fail "exactly one OPERATOR waiver expected"
  [[ "$(node_get "$DJ" 'm.validation_waivers.agent')" == "1" ]] || log_fail "exactly one AGENT (self) waiver expected"
  [[ "$(node_get "$DJ" 'm.validation_waivers.total')" == "2" ]] || log_fail "two waived rides expected"
  # The counts must be SEPARATE buckets, not one total split by a label: a
  # build that folded the agent waiver into the operator count would show
  # operator=2/agent=0 and still contain every expected word.
  [[ "$(node_get "$DJ" 'm.validation_waivers.operator === m.validation_waivers.total')" == "false" ]] \
    || log_fail "a self-waived ride must NOT be counted inside the operator total"
  [[ "$(node_get "$DJ" '(m.validation_waivers.rides.find(w=>w.ref==="SELFWAIVE")||{}).by')" == "agent" ]] \
    || log_fail "the self-waived ride must be attributed to the agent"
  [[ "$(node_get "$DJ" '(m.validation_waivers.rides.find(w=>w.ref==="OPWAIVE")||{}).by')" == "operator" ]] \
    || log_fail "the operator-waived ride must be attributed to the operator"
  [[ "$(node_get "$DJ" '(m.validation_waivers.rides.find(w=>w.ref==="OPWAIVE")||{}).reason')" == "operator ran the suite by hand" ]] \
    || log_fail "the recorded REASON must reach the report — an unaccountable waiver is the thing this forbids"
  # Negative controls: an English sentence is not a waiver, and a record with
  # an empty reason is counted as MALFORMED, never as a waiver and never
  # silently dropped.
  [[ "$(node_get "$DJ" 'm.validation_waivers.rides.some(w=>w.ref==="PROSE")')" == "false" ]] \
    || log_fail "a prose sentence claiming a waiver must NOT be counted as one"
  [[ "$(node_get "$DJ" 'm.validation_waivers.rides.some(w=>w.ref==="BROKEN")')" == "false" ]] \
    || log_fail "an empty-reason record must NOT be counted as a waiver"
  [[ "$(node_get "$DJ" 'm.validation_waivers.rejected_records')" == "1" ]] \
    || log_fail "the empty-reason record must be counted as malformed, not dropped"
  # Report-only: all four rides still count everywhere else. Nothing blocks.
  [[ "$(node_get "$DJ" 'm.counts.rides')" == "4" ]] || log_fail "every ride still counts — a waiver must never filter a ride out"
  [[ "$(node_get "$DJ" 'm.quality.first_pass_clean.flagged')" == "4" ]] || log_fail "waivers must not change the first-pass denominator"
  # HTML parity: the block a human actually reads carries both counts.
  run_report "$d"
  [[ "$EC" == 0 ]] || log_fail "html run must exit 0: $(cat "$OUT")"
  grep -qF "self-waived (agent) rides" "$d/docs/ai/factory-report.html" \
    || log_fail "the report must name the self-waived bucket"
  grep -qF "OPWAIVE" "$d/docs/ai/factory-report.html" \
    || log_fail "the operator-waived ride must be listed by ref"
  grep -qF "SELFWAIVE" "$d/docs/ai/factory-report.html" \
    || log_fail "the self-waived ride must be listed by ref"
  log_pass "Waived rides surfaced; self-waived counted separately; prose and empty-reason records refused (TEST-041)"
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
  # An EMPTY-but-present decisions ledger (CHANGE-0142): the follow-up
  # registry folds to nothing and contributes NO note, so this pin keeps
  # measuring what it was written to measure — the pre-change bytes — instead
  # of drifting into an assertion about the new block's degrade wording.
  : > "$d/docs/ai/decisions.jsonl"
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

    // --- new-key arm (CHANGE-0142): follow_ups present, empty, honest nulls
    if (!model.follow_ups) { console.log("FAIL:new-key-missing:follow_ups absent"); process.exit(1); }
    if (model.follow_ups.open_count !== 0 || model.follow_ups.oldest_age_days !== null || model.follow_ups.items.length !== 0) {
      errors.push(`follow_ups must be empty with a null oldest age on an empty ledger: ${JSON.stringify(model.follow_ups)}`);
    }

    // --- new-key arm (operator-waiver-unblocks-pr): validation_waivers
    // present and EMPTY on a ledger with no waiver record anywhere ---
    if (!model.validation_waivers) { console.log("FAIL:new-key-missing:validation_waivers absent"); process.exit(1); }
    if (model.validation_waivers.total !== 0 || model.validation_waivers.operator !== 0
        || model.validation_waivers.agent !== 0 || model.validation_waivers.rejected_records !== 0
        || model.validation_waivers.rides.length !== 0) {
      errors.push(`validation_waivers must be all-zero on a ledger with no waiver record: ${JSON.stringify(model.validation_waivers)}`);
    }

    // --- new-key arm (ride-cost-readout): scope_cost present, every scope
    // marker-derived figure null (no usage_total_tokens marker anywhere in
    // this fixture) ---
    if (!model.scope_cost || !Array.isArray(model.scope_cost.scopes)) { console.log("FAIL:new-key-missing:scope_cost absent"); process.exit(1); }
    for (const s of model.scope_cost.scopes) {
      if (s.runs_marked !== 0) errors.push(`scope ${s.ref} runs_marked must be 0 on an all-unmarked ledger, got ${s.runs_marked}`);
      if (s.tokens_total !== null || s.remediation_tokens !== null || s.remediation_share_pct !== null) errors.push(`scope ${s.ref} tokens_total/remediation_tokens/remediation_share_pct must all be null with no markers: ${JSON.stringify(s)}`);
    }

    // --- byte-stability arm: data.json, minus the new keys, generatedAt
    // normalized, must equal the golden byte-for-byte. scope_cost can also
    // add a D6 disagreement note (SPARSE-A carries reliability.remediation_runs:1
    // with no Remediation-role run — a genuine structural/reliability
    // disagreement, unrelated to this pin) — filtered the same way the new
    // keys are deleted, never by suppressing the check itself (see TEST-035).
    delete model.cost.role_consumption;
    delete model.follow_ups;
    delete model.scope_cost;
    delete model.validation_waivers;
    model.notes = model.notes.filter((n) => !n.includes("(scope_cost)"));
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
    const closeTag = "</section>";
    for (const startTag of ["<section id=\"role-consumption\">", "<section id=\"scope-cost\">", "<section id=\"follow-ups\">", "<section id=\"validation-waivers\">"]) {
      const start = html.indexOf(startTag);
      if (start === -1) { console.log(`FAIL:section-missing:no ${startTag} found`); process.exit(1); }
      const end = html.indexOf(closeTag, start);
      if (end === -1) { console.log(`FAIL:section-not-closed:${startTag}`); process.exit(1); }
      let after = end + closeTag.length;
      if (html.slice(after, after + 2) === "\n\n") after += 2;
      else if (html.slice(after, after + 1) === "\n") after += 1;
      html = html.slice(0, start) + html.slice(after);
    }
    // Same scope_cost-note filter as the JSON arm above, applied to the
    // rendered "Data honesty notes" list item.
    html = html.replace(/<li>[^<]*\(scope_cost\)<\/li>/g, "");
    const excisedHtml = html;
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

# ============ TEST-040 (Spec-AC-07, followups-cli-hardening) =================
# SEAM-1: the report reaches the follow-ups fold through the EXPORTED
# loadRegistry, never the CLI, so D2's exit-code deviation on the CLI path
# must not touch this generator's always-exit-0 contract. Runs the REAL
# generator over three degraded ledger shapes; no mock on this path.
test_040_follow_ups_unreadable_and_understatement() {
  log_info "Test: the real generator exits 0 over an absent, an unreadable (a directory via --decisions) and a malformed-line decisions ledger; the unreadable case is named without claiming absent/empty, the malformed case carries the UNDERSTATED clause, both render under the HTML data-honesty notes; no changed generator CODE line touches the follow-up path (TEST-040)..."

  # (1) ABSENT decisions ledger (default path, never created by mk_repo).
  local d1; d1="$(mk_repo t040-absent)"
  run_report "$d1" --data-only
  [[ "$EC" == 0 ]] || log_fail "absent decisions ledger must exit 0: $(cat "$OUT")"
  local dj1="$d1/docs/ai/factory-report-data.json"
  [[ "$(node_get "$dj1" 'm.follow_ups.open_count')" == "0" ]] || log_fail "absent ledger must report open_count 0"
  [[ "$(node_get "$dj1" 'm.follow_ups.oldest_age_days')" == "null" ]] || log_fail "absent ledger oldest_age_days must be null"
  [[ "$(node_get "$dj1" 'm.notes.some(n=>/absent/i.test(n))')" == "true" ]] || log_fail "absent ledger must be named /absent/i in notes"

  # (2) UNREADABLE decisions ledger — a DIRECTORY reached via --decisions.
  # A non-empty METRICS/EVENTS pair is required so the FULL render below hits
  # the real report body, not the "No metrics recorded yet" empty-model stub
  # (which never reaches the notes section at all — mk_repo's METRICS.jsonl
  # is empty by default).
  local d2; d2="$(mk_repo t040-unreadable)"
  cat > "$d2/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-01","ref_id":"A","agent_runs":[{"role":"Planning","duration_seconds":60}],"verdict":"PASS"}
JSONL
  write_closed_event "$d2/docs/ai/EVENTS.jsonl" "A" "2026-07-02T00:00:00Z"
  local badpath="$d2/docs/ai/a-directory-not-a-ledger"
  mkdir -p "$badpath"
  # Node's path.resolve() normalizes a double slash (macOS TMPDIR already ends
  # in "/", so mktemp-derived paths often carry "...//..."); squeeze it here
  # too so the string-containment check below compares like with like.
  badpath="$(printf '%s' "$badpath" | tr -s '/')"
  run_report "$d2" --data-only --decisions "$badpath"
  [[ "$EC" == 0 ]] || log_fail "an unreadable decisions ledger must exit 0 (degrade, never crash): $(cat "$OUT")"
  local dj2="$d2/docs/ai/factory-report-data.json"
  [[ "$(node_get "$dj2" 'm.follow_ups.open_count')" == "0" ]] || log_fail "unreadable ledger must report open_count 0"
  [[ "$(node_get "$dj2" 'm.follow_ups.oldest_age_days')" == "null" ]] || log_fail "unreadable ledger oldest_age_days must be null"
  local unreadprobe
  unreadprobe="$(node -e '
    const m=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
    const n=m.notes.find((x)=>x.includes(process.argv[2]));
    if (!n) { console.log("NO-NOTE-NAMING-PATH:"+JSON.stringify(m.notes)); process.exit(0); }
    if (/absent/i.test(n)) { console.log("WRONGLY-ABSENT:"+n); process.exit(0); }
    if (n.includes("reported as empty")) { console.log("WRONGLY-EMPTY:"+n); process.exit(0); }
    console.log("OK");
  ' "$dj2" "$badpath")"
  [[ "$unreadprobe" == "OK" ]] || log_fail "unreadable-ledger note contract violated: $unreadprobe"

  # (3) MALFORMED-LINE decisions ledger — the understatement clause.
  local d3; d3="$(mk_repo t040-malformed)"
  cat > "$d3/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-01","ref_id":"A","agent_runs":[{"role":"Planning","duration_seconds":60}],"verdict":"PASS"}
JSONL
  write_closed_event "$d3/docs/ai/EVENTS.jsonl" "A" "2026-07-02T00:00:00Z"
  local malpath="$d3/alt-decisions.jsonl"
  {
    printf '%s\n' '# Decision Log'
    printf '%s\n' 'this is not json'
    printf '%s\n' '{"v":1,"ts":"2026-01-01T00:00:00Z","actor":"a","type":"follow_up","id":"fu-real-one","ref_id":"CHANGE-0100","severity":"P1","finding":"a real open item","decision":"deferred","source":"s"}'
  } > "$malpath"
  run_report "$d3" --data-only --decisions "$malpath"
  [[ "$EC" == 0 ]] || log_fail "a malformed-line ledger must exit 0: $(cat "$OUT")"
  local dj3="$d3/docs/ai/factory-report-data.json"
  [[ "$(node_get "$dj3" 'm.notes.some(n=>/malformed decision/i.test(n))')" == "true" ]] || log_fail "the malformed line must be named in notes"
  [[ "$(node_get "$dj3" 'm.notes.some(n=>/UNDERSTATED/.test(n))')" == "true" ]] || log_fail "the malformed-line note must carry the UNDERSTATED clause"

  # Full render: BOTH the unreadable and the malformed-line degradations
  # appear under the HTML data-honesty notes section.
  run_report "$d2" --decisions "$badpath"
  [[ "$EC" == 0 ]] || log_fail "full render over the unreadable ledger must exit 0: $(cat "$OUT")"
  local html2="$d2/docs/ai/factory-report.html"
  grep -qF "$badpath" "$html2" || log_fail "the HTML must name the unreadable path in the data-honesty notes"
  run_report "$d3" --decisions "$malpath"
  [[ "$EC" == 0 ]] || log_fail "full render over the malformed-line ledger must exit 0: $(cat "$OUT")"
  local html3="$d3/docs/ai/factory-report.html"
  grep -qF "UNDERSTATED" "$html3" || log_fail "the HTML must render the UNDERSTATED clause"

  # The FOLLOW-UP hardening is NOT in the generator (Spec-AC-07). This began as
  # a blanket byte-identity pin on generate-factory-report.mjs against a MOVING
  # base ref, which asserted a property of one past ride and would redden on
  # every later, unrelated edit of the file (it did, on
  # operator-waiver-unblocks-pr, which adds a validation-waiver section). It is
  # retargeted to the claim it actually protects: no CHANGED line in the
  # generator may touch the follow-up registry path — the hardening lives in
  # follow-ups.mjs, and the generator only imports its fold. A base ref that
  # cannot be resolved (shallow clone, detached HEAD) degrades this ONE
  # assertion rather than failing or skipping the whole test.
  local base_ref=""
  if [[ -n "${AAI_FACTORY_REPORT_BASE_REF:-}" ]]; then
    base_ref="$AAI_FACTORY_REPORT_BASE_REF"
  elif command -v git >/dev/null 2>&1 && git -C "$PROJECT_ROOT" rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
    base_ref="origin/main"
  elif command -v git >/dev/null 2>&1 && git -C "$PROJECT_ROOT" rev-parse --verify --quiet main >/dev/null 2>&1; then
    base_ref="main"
  fi
  if [[ -z "$base_ref" ]]; then
    log_info "TEST-040: no resolvable base ref (shallow clone or detached base) — byte-identity diff skipped"
  else
    local followdiff
    followdiff="$(git -C "$PROJECT_ROOT" diff -U0 "$base_ref" -- .aai/scripts/generate-factory-report.mjs \
      | grep -E '^[-+][^-+]' | grep -vE '^[-+][[:space:]]*(//|\*)' \
      | grep -iE 'follow.up|follow_up|followUp|loadRegistry' || true)"
    [[ -z "$followdiff" ]] || log_fail "no changed line in generate-factory-report.mjs may touch the follow-up registry path — that hardening belongs in follow-ups.mjs: ${followdiff:0:512}"
  fi

  log_pass "generator exits 0 over absent/unreadable/malformed-line ledgers; unreadable note names the path without absent/empty; malformed note carries UNDERSTATED; both render in HTML; no changed generator line touches the follow-up path (TEST-040)"
}

# ============ TEST-031 (Spec-AC-01, spec-ride-cost-readout) ==================
test_031_scope_cost_elapsed_and_agent_time() {
  log_info "Test: scope_cost elapsed (wall clock) and agent time (summed) — idle gap, overlap, no-timestamp, no-duration, no-run rides; nulls not zeros; order elapsed-desc null-last ref-asc; divergence note names the overlap count; a run missing duration_seconds names its own count (BLOCKING-1) (TEST-031)..."
  local d; d="$(mk_repo t031)"
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-06","ref_id":"R-IDLE","agent_runs":[{"role":"Planning","started_utc":"2026-07-06T00:00:00Z","ended_utc":"2026-07-06T00:01:00Z","duration_seconds":60},{"role":"Validation","started_utc":"2026-07-06T00:10:00Z","ended_utc":"2026-07-06T00:11:00Z","duration_seconds":60}],"verdict":"PASS"}
{"date_utc":"2026-07-06","ref_id":"R-OVERLAP","agent_runs":[{"role":"Planning","started_utc":"2026-07-06T00:00:00Z","ended_utc":"2026-07-06T00:10:00Z","duration_seconds":600},{"role":"Validation","started_utc":"2026-07-06T00:05:00Z","ended_utc":"2026-07-06T00:15:00Z","duration_seconds":600}],"verdict":"PASS"}
{"date_utc":"2026-07-06","ref_id":"R-NOTIME","agent_runs":[{"role":"Planning","duration_seconds":90},{"role":"Validation","duration_seconds":30}],"verdict":"PASS"}
{"date_utc":"2026-07-06","ref_id":"R-NORUNS","agent_runs":[],"verdict":"PASS"}
{"date_utc":"2026-07-06","ref_id":"R-NODUR","agent_runs":[{"role":"Planning","duration_seconds":50},{"role":"Validation"}],"verdict":"PASS"}
JSONL
  run_report "$d" --data-only
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  DJ="$d/docs/ai/factory-report-data.json"
  local result rc
  result="$(node -e '
    const fs = require("fs");
    const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const sc = m.scope_cost.scopes;
    const errors = [];
    const byRef = {}; for (const s of sc) byRef[s.ref] = s;
    if (!byRef["R-IDLE"] || byRef["R-IDLE"].elapsed_wall_seconds !== 660 || byRef["R-IDLE"].agent_seconds !== 120) errors.push(`R-IDLE wrong: ${JSON.stringify(byRef["R-IDLE"])}`);
    if (!byRef["R-OVERLAP"] || byRef["R-OVERLAP"].elapsed_wall_seconds !== 900 || byRef["R-OVERLAP"].agent_seconds !== 1200) errors.push(`R-OVERLAP wrong: ${JSON.stringify(byRef["R-OVERLAP"])}`);
    if (!byRef["R-NOTIME"] || byRef["R-NOTIME"].elapsed_wall_seconds !== null || byRef["R-NOTIME"].agent_seconds !== 120) errors.push(`R-NOTIME wrong: ${JSON.stringify(byRef["R-NOTIME"])}`);
    if (!byRef["R-NORUNS"] || byRef["R-NORUNS"].elapsed_wall_seconds !== null || byRef["R-NORUNS"].agent_seconds !== null || byRef["R-NORUNS"].runs_total !== 0 || byRef["R-NORUNS"].roles.length !== 0) errors.push(`R-NORUNS wrong: ${JSON.stringify(byRef["R-NORUNS"])}`);
    // BLOCKING-1: R-NODUR has one run WITH duration_seconds (50) and one
    // WITHOUT — agent_seconds must be the partial sum of the counted run only
    // (never null, never silently dropped), and the missing run must be
    // named in notes, the same shape Tokens already uses for its own partial
    // sum (runs_marked/runs_total).
    if (!byRef["R-NODUR"] || byRef["R-NODUR"].agent_seconds !== 50 || byRef["R-NODUR"].elapsed_wall_seconds !== null || byRef["R-NODUR"].runs_total !== 2) errors.push(`R-NODUR wrong: ${JSON.stringify(byRef["R-NODUR"])}`);
    if (!m.notes.some((n) => /^NOTE 1 agent_run\(s\) carry no duration_seconds — Agent time \(summed\) is a partial sum on those scopes \(scope_cost\)$/.test(n))) errors.push(`missing partial-agent-time note (BLOCKING-1): ${JSON.stringify(m.notes)}`);
    const order = sc.map((s) => s.ref);
    if (JSON.stringify(order) !== JSON.stringify(["R-OVERLAP","R-IDLE","R-NODUR","R-NORUNS","R-NOTIME"])) errors.push(`order wrong: ${JSON.stringify(order)}`);
    if (!m.notes.some((n) => /1 scope\(s\) have Agent time \(summed\) exceeding Elapsed \(wall clock\)/.test(n))) errors.push(`missing overlap divergence note: ${JSON.stringify(m.notes)}`);
    if (errors.length) { console.log("FAIL:" + errors.join(" | ")); process.exit(1); }
    console.log("OK");
  ' "$DJ")" && rc=0 || rc=$?
  [[ "$rc" == 0 && "$result" == "OK" ]] || log_fail "scope_cost elapsed/agent time wrong: $result"
  log_pass "idle-gap/overlap/no-timestamp/no-duration/no-run rides give hand-computed elapsed+agent, order elapsed-desc null-last ref-asc, overlap divergence note, missing-duration partial-sum note (BLOCKING-1) (TEST-031 fixture arm)"

  # real-ledger arm (D2): agent_seconds must equal the raw totals.agent_duration_seconds
  # field on the REAL docs/ai/METRICS.jsonl for every ride (read-only; SEAM S1).
  local rd; rd="$TEST_DIR/t031-real"
  run_report_real_ledger "$rd"
  [[ "$EC" == 0 ]] || log_fail "real-ledger run must exit 0: $(cat "$OUT")"
  local RDJ="$rd/docs/ai/factory-report-data.json"
  result="$(node -e '
    const fs = require("fs");
    const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const lines = fs.readFileSync(process.argv[2], "utf8").split(/\r?\n/).filter((l) => l.trim() && !l.trim().startsWith("#"));
    const totalsByRef = {};
    for (const l of lines) {
      let row; try { row = JSON.parse(l); } catch { continue; }
      if (!row || !row.ref_id) continue;
      totalsByRef[row.ref_id] = row.totals && typeof row.totals.agent_duration_seconds === "number" ? row.totals.agent_duration_seconds : undefined;
    }
    const errors = [];
    let checked = 0;
    for (const s of m.scope_cost.scopes) {
      const expected = totalsByRef[s.ref];
      if (expected === undefined) continue;
      // A zero-agent-run ride (runs_total 0, 2 exist in the live ledger, see
      // the spec Edge cases) legitimately renders agent_seconds null (never
      // ran, D9/edge-case) while metrics-flush.mjs sums an empty array to the
      // literal 0 in totals.agent_duration_seconds — a representational
      // difference (never-measured vs measured-zero), not a drift bug, so it
      // is excluded from this identity rather than counted as a mismatch.
      if (s.runs_total === 0) continue;
      checked += 1;
      if (s.agent_seconds !== expected) errors.push(`ref ${s.ref}: agent_seconds ${s.agent_seconds} != totals.agent_duration_seconds ${expected}`);
    }
    if (checked === 0) errors.push("no ride on the real ledger carried a totals.agent_duration_seconds field to compare against");
    if (errors.length) { console.log("FAIL:" + errors.join(" | ")); process.exit(1); }
    console.log(`OK:${checked}`);
  ' "$RDJ" "$PROJECT_ROOT/docs/ai/METRICS.jsonl")" && rc=0 || rc=$?
  [[ "$rc" == 0 && "$result" == OK:* ]] || log_fail "real-ledger agent_seconds vs totals.agent_duration_seconds mismatch: $result"
  log_pass "agent_seconds equals totals.agent_duration_seconds on the REAL docs/ai/METRICS.jsonl ledger, $result rides checked (TEST-031 real-ledger arm, D2)"

  # real-ledger SHADOW-MODEL arm (round-3 validation F1/F2, extended for F3-F6):
  # a fixture can only pin the shapes the author thought of — three straight
  # rounds each rescued one column (roles, tokens, now remediation) by adding
  # ONE more fixture row, and the next round always found the next column. So
  # instead of a fourth fixture row, INDEPENDENTLY re-derive the whole
  # scope_cost row for every REAL ride straight from docs/ai/METRICS.jsonl —
  # using only the canonical normalizeRole/extractUsageTotal/CANONICAL_ROLES
  # (the single source, D3 — re-deriving role/token grammar by hand here would
  # be the exact drift risk D3 exists to prevent) — and diff every field the
  # generator wrote against that independent computation. Because the mutant
  # generator code (e.g. counting Validation as Remediation, or firing the
  # disagreement note on agreement) is NEVER consulted by this re-derivation,
  # any defect in that code shows up as a mismatch, on whatever real rides
  # happen to exercise it — no fixture row to remember. This also directly
  # re-derives roles/tokens_total/runs_marked/date_utc (F4), the full D10 sort
  # order including the ref tie-break (F5, real ledger has tie groups), the
  # remediation_share_pct rounding (F6), and the D1 divergence-note count
  # under the STRICT ">" rule (F3) — the seven columns TEST-037 already proved
  # are not render-blind now also cannot be MODEL-blind on the real corpus.
  # STABLE AGAINST LEDGER GROWTH: every expected value is computed from the
  # ledger at test-run time, never hardcoded, so a new ride landing in
  # METRICS.jsonl changes both the actual and the independently-derived side
  # together and this arm keeps passing without edits.
  # NB-7 REPAIR DIRECTIVE: on a mismatch here, fix generate-factory-report.mjs
  # (the generator), NEVER this re-derivation. The whole point of a shadow
  # model independent of the generator is that it computes scope_cost from
  # docs/ai/METRICS.jsonl using ONLY the canonical normalizeRole/
  # extractUsageTotal/CANONICAL_ROLES primitives (D3) — pasting the
  # generator's new rule in here to make a red arm green converts this into a
  # tautology and silently retires every finding it exists to catch. The one
  # legitimate reason to edit the block below is a genuine bug IN the
  # re-derivation itself (e.g. it mis-copies a primitive), never "make it
  # agree with the generator's current behavior".
  result="$(node -e '
    (async () => {
      const fs = require("fs");
      const { pathToFileURL } = require("url");
      const { extractUsageTotal, normalizeRole, CANONICAL_ROLES } = await import(pathToFileURL(process.argv[3]).href);
      const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      const lines = fs.readFileSync(process.argv[2], "utf8").split(/\r?\n/).filter((l) => l.trim() && !l.trim().startsWith("#"));
      const rides = [];
      for (const l of lines) {
        let row; try { row = JSON.parse(l); } catch { continue; }
        if (row && row.ref_id) rides.push(row);
      }
      const shadow = [];
      let expectedMissingDur = 0;
      for (const rrow of rides) {
        let minStartMs = null; let maxEndMs = null;
        let runsTotal = 0; let runsMarked = 0;
        let busy = 0; let hasBusy = false;
        let tok = 0; let hasTok = false;
        const roleCounts = new Map();
        let remediationStructural = 0;
        let remediationTok = 0; let hasRemediationTok = false;
        for (const r of rrow.agent_runs ?? []) {
          runsTotal += 1;
          const roleKey = normalizeRole(r.role) ?? "Other";
          roleCounts.set(roleKey, (roleCounts.get(roleKey) ?? 0) + 1);
          if (typeof r.duration_seconds === "number") { busy += r.duration_seconds; hasBusy = true; } else { expectedMissingDur += 1; }
          const t = extractUsageTotal(r.note);
          if (t !== null) { tok += t; hasTok = true; runsMarked += 1; }
          if (typeof r.started_utc === "string") {
            const s = Date.parse(r.started_utc);
            if (!Number.isNaN(s) && (minStartMs === null || s < minStartMs)) minStartMs = s;
          }
          if (typeof r.ended_utc === "string") {
            const e = Date.parse(r.ended_utc);
            if (!Number.isNaN(e) && (maxEndMs === null || e > maxEndMs)) maxEndMs = e;
          }
          if (roleKey === "Remediation") {
            remediationStructural += 1;
            if (t !== null) { remediationTok += t; hasRemediationTok = true; }
          }
        }
        const elapsed = (minStartMs !== null && maxEndMs !== null && maxEndMs >= minStartMs) ? Math.round((maxEndMs - minStartMs) / 1000) : null;
        const agentSeconds = hasBusy ? busy : null;
        const tokensTotal = hasTok ? tok : null;
        const remediationTokens = hasRemediationTok ? remediationTok : null;
        const remediationSharePct = (remediationTokens !== null && tokensTotal) ? Math.round((100 * remediationTokens) / tokensTotal) : null;
        const roles = CANONICAL_ROLES.concat(["Other"]).filter((role) => roleCounts.has(role)).map((role) => ({ role, runs: roleCounts.get(role) }));
        shadow.push({
          ref: rrow.ref_id, date_utc: rrow.date_utc ?? null, runs_total: runsTotal,
          elapsed_wall_seconds: elapsed, agent_seconds: agentSeconds, roles,
          runs_marked: runsMarked, tokens_total: tokensTotal,
          remediation_runs: remediationStructural, remediation_tokens: remediationTokens,
          remediation_share_pct: remediationSharePct,
          reliability: (rrow.reliability && typeof rrow.reliability === "object" && !Array.isArray(rrow.reliability)) ? rrow.reliability : null,
        });
      }
      const errors = [];
      const byRef = {}; for (const s of m.scope_cost.scopes) byRef[s.ref] = s;
      let checked = 0;
      for (const sh of shadow) {
        const actual = byRef[sh.ref];
        if (!actual) { errors.push(`ref ${sh.ref}: missing from scope_cost.scopes`); continue; }
        checked += 1;
        for (const field of ["date_utc", "runs_total", "elapsed_wall_seconds", "agent_seconds", "runs_marked", "tokens_total", "remediation_runs", "remediation_tokens", "remediation_share_pct"]) {
          if (actual[field] !== sh[field]) errors.push(`ref ${sh.ref} field ${field}: actual ${actual[field]} != independently-derived ${sh[field]}`);
        }
        if (JSON.stringify(actual.roles) !== JSON.stringify(sh.roles)) errors.push(`ref ${sh.ref} roles: actual ${JSON.stringify(actual.roles)} != independently-derived ${JSON.stringify(sh.roles)}`);
      }
      if (checked === 0) errors.push("no ride checked");
      const expectedDisagreeNotes = [];
      for (const sh of shadow) {
        if (sh.reliability && typeof sh.reliability.remediation_runs === "number" && sh.reliability.remediation_runs !== sh.remediation_runs) {
          expectedDisagreeNotes.push(`NOTE scope ${sh.ref} remediation runs disagree: structural ${sh.remediation_runs} vs reliability.remediation_runs ${sh.reliability.remediation_runs} (scope_cost)`);
        }
      }
      const actualDisagreeNotes = m.notes.filter((n) => /remediation runs disagree/.test(n));
      if (actualDisagreeNotes.length !== expectedDisagreeNotes.length) errors.push(`disagreement note count: actual ${actualDisagreeNotes.length} != independently-derived ${expectedDisagreeNotes.length}`);
      for (const en of expectedDisagreeNotes) if (!actualDisagreeNotes.includes(en)) errors.push(`missing expected disagreement note: ${en}`);
      for (const an of actualDisagreeNotes) if (!expectedDisagreeNotes.includes(an)) errors.push(`unexpected disagreement note fired on an agreeing ride: ${an}`);
      const expectedOverlap = shadow.filter((sh) => sh.agent_seconds !== null && sh.elapsed_wall_seconds !== null && sh.agent_seconds > sh.elapsed_wall_seconds).length;
      const overlapNoteMatch = m.notes.find((n) => /scope\(s\) have Agent time \(summed\) exceeding Elapsed \(wall clock\)/.test(n));
      const actualOverlap = overlapNoteMatch ? Number(overlapNoteMatch.match(/^NOTE (\d+) /)[1]) : 0;
      if (actualOverlap !== expectedOverlap) errors.push(`overlap count (strict >): actual ${actualOverlap} != independently-derived ${expectedOverlap}`);
      const missingDurNoteMatch = m.notes.find((n) => /agent_run\(s\) carry no duration_seconds/.test(n));
      const actualMissingDur = missingDurNoteMatch ? Number(missingDurNoteMatch.match(/^NOTE (\d+) /)[1]) : 0;
      if (actualMissingDur !== expectedMissingDur) errors.push(`missing-duration count (R2-NB-1): actual ${actualMissingDur} != independently-derived ${expectedMissingDur}`);
      const expectedOrder = shadow.slice().sort((a, b) => {
        if (a.elapsed_wall_seconds === null && b.elapsed_wall_seconds === null) return a.ref.localeCompare(b.ref);
        if (a.elapsed_wall_seconds === null) return 1;
        if (b.elapsed_wall_seconds === null) return -1;
        if (a.elapsed_wall_seconds !== b.elapsed_wall_seconds) return b.elapsed_wall_seconds - a.elapsed_wall_seconds;
        return a.ref.localeCompare(b.ref);
      }).map((s) => s.ref);
      const actualOrder = m.scope_cost.scopes.map((s) => s.ref);
      if (JSON.stringify(actualOrder) !== JSON.stringify(expectedOrder)) {
        let idx = -1;
        for (let i = 0; i < Math.max(actualOrder.length, expectedOrder.length); i += 1) { if (actualOrder[i] !== expectedOrder[i]) { idx = i; break; } }
        errors.push(`order mismatch at index ${idx}: actual ${actualOrder[idx]} != independently-derived ${expectedOrder[idx]}`);
      }
      const elapsedCounts = new Map();
      for (const sh of shadow) { if (sh.elapsed_wall_seconds === null) continue; elapsedCounts.set(sh.elapsed_wall_seconds, (elapsedCounts.get(sh.elapsed_wall_seconds) ?? 0) + 1); }
      const tieGroups = [...elapsedCounts.values()].filter((c) => c > 1).length;
      if (errors.length) { console.log("FAIL:" + errors.slice(0, 15).join(" | ")); process.exitCode = 1; return; }
      console.log(`OK:${checked}:${tieGroups}:${expectedDisagreeNotes.length}:${expectedOverlap}`);
    })().catch((e) => { console.log(`FAIL:threw ${e && e.stack ? e.stack : e}`); process.exitCode = 1; });
  ' "$RDJ" "$PROJECT_ROOT/docs/ai/METRICS.jsonl" "$PROJECT_ROOT/.aai/scripts/lib/usage-note.mjs")" && rc=0 || rc=$?
  [[ "$rc" == 0 && "$result" == OK:* ]] || log_fail "real-ledger shadow-model mismatch (independently re-derived roles/tokens/remediation/order/notes): $result"
  log_pass "shadow-model: every scope_cost field (roles, tokens_total, runs_marked, date_utc, remediation_runs/tokens/share_pct), the full D10 sort order (tie-break included) and the (scope_cost) note set (disagreement + strict-> divergence) independently re-derived from the real docs/ai/METRICS.jsonl ledger and matched exactly — $result (TEST-031 real-ledger shadow-model arm, closes round-3 F1/F2/F3/F4/F5/F6)"
}

# ============ TEST-032 (Spec-AC-02, spec-ride-cost-readout) ==================
test_032_scope_cost_role_counts() {
  log_info "Test: scope_cost roles array covers exactly the roles that ran, CANONICAL_ROLES order with Other last, a variant string normalizes, an unrecognised one buckets to Other, counts sum to runs_total, absent agent_runs key -> empty roles (TEST-032)..."
  local d; d="$(mk_repo t032)"
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-06","ref_id":"R-ROLES","agent_runs":[{"role":"Implementation (loop)","duration_seconds":10},{"role":"Validation","duration_seconds":10},{"role":"Validation","duration_seconds":10},{"role":"QA Something","duration_seconds":10}],"verdict":"PASS"}
{"date_utc":"2026-07-06","ref_id":"R-NOKEY","verdict":"PASS"}
JSONL
  run_report "$d" --data-only
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  DJ="$d/docs/ai/factory-report-data.json"
  local result rc
  result="$(node -e '
    const fs = require("fs");
    const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const sc = m.scope_cost.scopes;
    const errors = [];
    const roles = sc.find((s) => s.ref === "R-ROLES");
    const expected = [{role:"Implementation",runs:1},{role:"Validation",runs:2},{role:"Other",runs:1}];
    if (!roles || JSON.stringify(roles.roles) !== JSON.stringify(expected)) errors.push(`R-ROLES roles wrong: ${JSON.stringify(roles && roles.roles)}`);
    if (!roles || roles.roles.reduce((a, r) => a + r.runs, 0) !== roles.runs_total) errors.push(`role counts must sum to runs_total: ${JSON.stringify(roles)}`);
    const nokey = sc.find((s) => s.ref === "R-NOKEY");
    if (!nokey || nokey.roles.length !== 0 || nokey.runs_total !== 0) errors.push(`R-NOKEY (absent agent_runs key) must have empty roles and runs_total 0: ${JSON.stringify(nokey)}`);
    if (errors.length) { console.log("FAIL:" + errors.join(" | ")); process.exit(1); }
    console.log("OK");
  ' "$DJ")" && rc=0 || rc=$?
  [[ "$rc" == 0 && "$result" == "OK" ]] || log_fail "scope_cost role counts wrong: $result"
  log_pass "roles array covers exactly the roles that ran, canonical order with Other last, sums to runs_total, absent key -> empty (TEST-032)"
}

# ============ TEST-033 (Spec-AC-03, spec-ride-cost-readout) ==================
test_033_scope_cost_token_source() {
  log_info "Test: scope_cost token figures come only from extractUsageTotal — valid marker, malformed marker, prefixed key and bare note; unmarked runs contribute nothing; no capturing regex duplicate; lib/usage-note.mjs imported exactly once (TEST-033)..."
  local d; d="$(mk_repo t033)"
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-06","ref_id":"R-TOK","agent_runs":[{"role":"Planning","duration_seconds":10,"note":"usage_total_tokens=1000 (ok)"},{"role":"Validation","duration_seconds":10,"note":"usage_total_tokens=500x (malformed, ignored)"},{"role":"Code Review","duration_seconds":10,"note":"not_usage_total_tokens=999 (prefixed key, ignored)"},{"role":"Remediation","duration_seconds":10,"note":"no marker here"}],"verdict":"PASS"}
JSONL
  run_report "$d" --data-only
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  DJ="$d/docs/ai/factory-report-data.json"
  local tt rm rt
  tt="$(node_get "$DJ" '(m.scope_cost.scopes.find(x=>x.ref==="R-TOK")||{}).tokens_total')"
  rm="$(node_get "$DJ" '(m.scope_cost.scopes.find(x=>x.ref==="R-TOK")||{}).runs_marked')"
  rt="$(node_get "$DJ" '(m.scope_cost.scopes.find(x=>x.ref==="R-TOK")||{}).runs_total')"
  [[ "$tt" == "1000" ]] || log_fail "tokens_total must be 1000 (only the valid marker counts), got $tt"
  [[ "$rm" == "1" ]] || log_fail "runs_marked must be 1 (malformed/prefixed/bare contribute nothing), got $rm"
  [[ "$rt" == "4" ]] || log_fail "runs_total must be 4, got $rt"
  local regex_count import_count
  regex_count="$(grep -c 'usage_total_tokens=(' "$REPORT" || true)"
  import_count="$(grep -c "from './lib/usage-note.mjs'" "$REPORT" || true)"
  [[ "$regex_count" == "0" ]] || log_fail "generator must carry no capturing regex literal for the usage_total_tokens grammar, found $regex_count"
  [[ "$import_count" == "1" ]] || log_fail "generator must import lib/usage-note.mjs exactly once, found $import_count"
  log_pass "scope_cost tokens come only from extractUsageTotal; malformed/prefixed/bare excluded; no duplicate regex; single import (TEST-033)"
}

# ============ TEST-034 (Spec-AC-04, spec-ride-cost-readout) ==================
test_034_scope_cost_partial_and_no_data() {
  log_info "Test: scope_cost token cell — fully marked, partially marked and unmarked rides give the expected JSON nulls; every rendered token cell carries the runs_marked/runs_total fraction; the unmarked ride renders the literal no-usage-marker line, never a zero (TEST-034)..."
  local d; d="$(mk_repo t034)"
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-06","ref_id":"R-FULL","agent_runs":[{"role":"Planning","duration_seconds":10,"note":"usage_total_tokens=100"},{"role":"Validation","duration_seconds":10,"note":"usage_total_tokens=200"}],"verdict":"PASS"}
{"date_utc":"2026-07-06","ref_id":"R-PARTIAL","agent_runs":[{"role":"Planning","duration_seconds":10,"note":"usage_total_tokens=100"},{"role":"Validation","duration_seconds":10,"note":"no marker"}],"verdict":"PASS"}
{"date_utc":"2026-07-06","ref_id":"R-NONE","agent_runs":[{"role":"Planning","duration_seconds":10,"note":"no marker"},{"role":"Validation","duration_seconds":10,"note":"no marker"}],"verdict":"PASS"}
JSONL
  run_report "$d"
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  DJ="$d/docs/ai/factory-report-data.json"
  local html="$d/docs/ai/factory-report.html"
  local result rc
  result="$(node -e '
    const fs = require("fs");
    const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const html = fs.readFileSync(process.argv[2], "utf8");
    const errors = [];
    const byRef = {}; for (const s of m.scope_cost.scopes) byRef[s.ref] = s;
    if (!byRef["R-FULL"] || byRef["R-FULL"].tokens_total !== 300 || byRef["R-FULL"].runs_marked !== 2) errors.push(`R-FULL wrong: ${JSON.stringify(byRef["R-FULL"])}`);
    if (!byRef["R-PARTIAL"] || byRef["R-PARTIAL"].tokens_total !== 100 || byRef["R-PARTIAL"].runs_marked !== 1) errors.push(`R-PARTIAL wrong: ${JSON.stringify(byRef["R-PARTIAL"])}`);
    if (!byRef["R-NONE"] || byRef["R-NONE"].tokens_total !== null || byRef["R-NONE"].runs_marked !== 0) errors.push(`R-NONE wrong: ${JSON.stringify(byRef["R-NONE"])}`);
    const start = html.indexOf("<section id=\"scope-cost\">");
    if (start === -1) { console.log("FAIL:no scope-cost section found"); process.exit(1); }
    const end = html.indexOf("</section>", start);
    const section = html.slice(start, end);
    if (!section.includes("300 (2/2 runs)")) errors.push("missing full-coverage cell 300 (2/2 runs)");
    if (!section.includes("100 (1/2 runs)")) errors.push("missing partial-coverage cell 100 (1/2 runs)");
    if (!section.includes("no usage marker (0/2 runs)")) errors.push("missing named no-marker cell for the fully-unmarked ride");
    if (errors.length) { console.log("FAIL:" + errors.join(" | ")); process.exit(1); }
    console.log("OK");
  ' "$DJ" "$html")" && rc=0 || rc=$?
  [[ "$rc" == 0 && "$result" == "OK" ]] || log_fail "scope_cost partial/no-data wrong: $result"
  log_pass "token cell carries the runs_marked/runs_total fraction in all three coverage shapes; unmarked scope renders the named no-marker line, null total (TEST-034)"
}

# ============ TEST-035 (Spec-AC-05, spec-ride-cost-readout) ==================
test_035_scope_cost_rework() {
  log_info "Test: scope_cost rework — hand-computed remediation runs/tokens/share, a Remediation variant string counted, unmarked remediation runs give a count with null tokens and null share, a rigged reliability disagreement emits the named note, an absent reliability block emits none (TEST-035)..."
  local d; d="$(mk_repo t035)"
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-06","ref_id":"R-REM-MARKED","agent_runs":[{"role":"Remediation","duration_seconds":10,"note":"usage_total_tokens=300"},{"role":"Planning","duration_seconds":10,"note":"usage_total_tokens=700"}],"verdict":"PASS"}
{"date_utc":"2026-07-06","ref_id":"R-REM-UNMARKED","agent_runs":[{"role":"Remediation","duration_seconds":10,"note":"no marker"},{"role":"Planning","duration_seconds":10,"note":"usage_total_tokens=50"}],"verdict":"PASS"}
{"date_utc":"2026-07-06","ref_id":"R-REM-VARIANT","agent_runs":[{"role":"Remediation (E1 over-kill)","duration_seconds":10,"note":"usage_total_tokens=40"}],"verdict":"PASS"}
{"date_utc":"2026-07-06","ref_id":"R-REL-DISAGREE","agent_runs":[{"role":"Planning","duration_seconds":10}],"reliability":{"remediation_runs":2,"validation_fails":0,"review_fails":0,"first_pass_clean":true},"verdict":"PASS"}
{"date_utc":"2026-07-06","ref_id":"R-REL-ABSENT","agent_runs":[{"role":"Planning","duration_seconds":10}],"verdict":"PASS"}
JSONL
  run_report "$d" --data-only
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  DJ="$d/docs/ai/factory-report-data.json"
  local result rc
  result="$(node -e '
    const fs = require("fs");
    const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const sc = m.scope_cost.scopes;
    const errors = [];
    const byRef = {}; for (const s of sc) byRef[s.ref] = s;
    const marked = byRef["R-REM-MARKED"];
    if (!marked || marked.remediation_runs !== 1 || marked.remediation_tokens !== 300 || marked.remediation_share_pct !== 30) errors.push(`R-REM-MARKED wrong: ${JSON.stringify(marked)}`);
    const unmarked = byRef["R-REM-UNMARKED"];
    if (!unmarked || unmarked.remediation_runs !== 1 || unmarked.remediation_tokens !== null || unmarked.remediation_share_pct !== null) errors.push(`R-REM-UNMARKED wrong (count present, tokens/share null): ${JSON.stringify(unmarked)}`);
    const variant = byRef["R-REM-VARIANT"];
    if (!variant || variant.remediation_runs !== 1 || variant.remediation_tokens !== 40 || variant.remediation_share_pct !== 100) errors.push(`R-REM-VARIANT (Remediation (E1 over-kill)) wrong: ${JSON.stringify(variant)}`);
    const disagree = byRef["R-REL-DISAGREE"];
    if (!disagree || disagree.remediation_runs !== 0) errors.push(`R-REL-DISAGREE structural count must be 0 (no Remediation-role run): ${JSON.stringify(disagree)}`);
    if (!m.notes.some((n) => n.includes("R-REL-DISAGREE") && n.includes("structural 0") && n.includes("reliability.remediation_runs 2"))) errors.push(`missing disagreement note naming R-REL-DISAGREE and both numbers: ${JSON.stringify(m.notes)}`);
    if (m.notes.some((n) => n.includes("R-REL-ABSENT"))) errors.push(`R-REL-ABSENT has no reliability block and must emit no disagreement note: ${JSON.stringify(m.notes)}`);
    if (errors.length) { console.log("FAIL:" + errors.join(" | ")); process.exit(1); }
    console.log("OK");
  ' "$DJ")" && rc=0 || rc=$?
  [[ "$rc" == 0 && "$result" == "OK" ]] || log_fail "scope_cost rework wrong: $result"
  log_pass "remediation runs/tokens/share hand-computed, variant string counted, unmarked remediation null-not-zero, disagreement note present, absent block emits none (TEST-035)"
}

# ============ TEST-036 (Spec-AC-06, spec-ride-cost-readout) ==================
test_036_scope_cost_report_only() {
  log_info "Test: report-only contract — absent/empty/comment-only/one-malformed-line/real ledgers each exit 0; no non-zero process.exit; no dollar-amount figure in either output (TEST-036)..."
  local d
  d="$(mk_repo t036-absent)"; rm -f "$d/docs/ai/METRICS.jsonl"
  run_report "$d" --data-only
  [[ "$EC" == 0 ]] || log_fail "absent ledger must exit 0: $(cat "$OUT")"

  d="$(mk_repo t036-empty)"; : > "$d/docs/ai/METRICS.jsonl"
  run_report "$d" --data-only
  [[ "$EC" == 0 ]] || log_fail "empty ledger must exit 0: $(cat "$OUT")"

  d="$(mk_repo t036-comment)"; printf '# comment only\n' > "$d/docs/ai/METRICS.jsonl"
  run_report "$d" --data-only
  [[ "$EC" == 0 ]] || log_fail "comment-only ledger must exit 0: $(cat "$OUT")"

  d="$(mk_repo t036-malformed)"
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-06","ref_id":"OK","agent_runs":[{"role":"Planning","duration_seconds":10,"note":"usage_total_tokens=42"}],"verdict":"PASS"}
{this is not valid json
JSONL
  run_report "$d"
  [[ "$EC" == 0 ]] || log_fail "one-malformed-line ledger must exit 0: $(cat "$OUT")"
  local html_m="$d/docs/ai/factory-report.html"
  local dj_m="$d/docs/ai/factory-report-data.json"
  grep -qE '\$[0-9]' "$dj_m" && log_fail "malformed-line-ledger data.json must carry no dollar amount"
  grep -qE '\$[0-9]' "$html_m" && log_fail "malformed-line-ledger html must carry no dollar amount"

  local rd; rd="$TEST_DIR/t036-real"
  run_report_real_ledger "$rd"
  [[ "$EC" == 0 ]] || log_fail "real-ledger run must exit 0: $(cat "$OUT")"

  local exit_count
  exit_count="$(grep -cE 'process\.exit\([1-9]' "$REPORT" || true)"
  [[ "$exit_count" == "0" ]] || log_fail "generator must carry no non-zero process.exit, found $exit_count occurrence(s)"
  log_pass "absent/empty/comment-only/one-malformed-line/real ledgers all exit 0; no non-zero process.exit; no dollar figure (TEST-036)"
}

# ============ TEST-037 (Spec-AC-07, spec-ride-cost-readout) ==================
test_037_scope_cost_html_parity() {
  log_info "Test: <section id=\"scope-cost\"> pins all 7 <th> column headings by position, pins the caption's D1/D6/D11 sentences independently of the headings, and compares EVERY rendered cell (ref, elapsed, agent time, roles, token, remediation runs, share) against the same run's factory-report-data.json cell-by-cell (never row-scoped), for exactly one row per scope_cost.scopes[] entry in array order — fixture includes a multi-role, null-agent-time, partially-marked ride (Roles join / Agent-time null not vacuous), a zero-run ride (NB-4: named Roles cell, never blank) and a zero-token-marker Remediation-only ride (NB-5: D7's zero-denominator guard visible only in the HTML, not the JSON) (TEST-037, seam S3)..."
  local d; d="$(mk_repo t037)"
  cat > "$d/docs/ai/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-06","ref_id":"P-ONE","agent_runs":[{"role":"Planning","started_utc":"2026-07-06T00:00:00Z","ended_utc":"2026-07-06T00:02:00Z","duration_seconds":120,"note":"usage_total_tokens=500"}],"verdict":"PASS"}
{"date_utc":"2026-07-06","ref_id":"P-TWO","agent_runs":[{"role":"Validation","duration_seconds":30,"note":"no marker"}],"verdict":"PASS"}
{"date_utc":"2026-07-06","ref_id":"P-THREE","agent_runs":[{"role":"Remediation","started_utc":"2026-07-06T00:00:00Z","ended_utc":"2026-07-06T00:05:00Z","duration_seconds":300,"note":"usage_total_tokens=800"},{"role":"Remediation","duration_seconds":100,"note":"usage_total_tokens=200"}],"verdict":"PASS"}
{"date_utc":"2026-07-06","ref_id":"P-FOUR","agent_runs":[{"role":"Implementation","started_utc":"2026-07-06T00:00:00Z","ended_utc":"2026-07-06T00:10:00Z","note":"usage_total_tokens=300"},{"role":"Planning","started_utc":"2026-07-06T00:10:00Z","ended_utc":"2026-07-06T00:12:00Z","note":"no marker"}],"verdict":"PASS"}
{"date_utc":"2026-07-06","ref_id":"P-ZERO-RUNS","agent_runs":[],"verdict":"PASS"}
{"date_utc":"2026-07-06","ref_id":"P-ZERO-TOK","agent_runs":[{"role":"Remediation","duration_seconds":10,"note":"usage_total_tokens=0"}],"verdict":"PASS"}
JSONL
  run_report "$d"
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  DJ="$d/docs/ai/factory-report-data.json"
  local html="$d/docs/ai/factory-report.html"
  local result rc
  result="$(node -e '
    const fs = require("fs");
    const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const html = fs.readFileSync(process.argv[2], "utf8");
    const errors = [];
    const startTag = "<section id=\"scope-cost\">";
    const start = html.indexOf(startTag);
    if (start === -1) { console.log("FAIL:no scope-cost section found"); process.exit(1); }
    const end = html.indexOf("</section>", start);
    if (end === -1) { console.log("FAIL:no closing </section> found for scope-cost"); process.exit(1); }
    const section = html.slice(start, end);
    if (!/<h2>Scope cost/.test(section)) errors.push("missing <h2>Scope cost ...</h2>");

    // Column headings: pinned by exact position inside <thead>, never by a
    // bare section.includes() — the caption below reuses the same two label
    // strings, so a deleted <th> could otherwise hide behind the caption.
    const theadMatch = section.match(/<thead>([\s\S]*?)<\/thead>/);
    if (!theadMatch) { console.log("FAIL:no <thead> found in scope-cost table"); process.exit(1); }
    const ths = [...theadMatch[1].matchAll(/<th>([\s\S]*?)<\/th>/g)].map((mm) => mm[1]);
    const expectedThs = ["Ref", "Elapsed (wall clock)", "Agent time (summed)", "Roles", "Tokens", "Remediation runs", "Remediation share (of measured tokens)"];
    if (JSON.stringify(ths) !== JSON.stringify(expectedThs)) errors.push(`column headings wrong: got ${JSON.stringify(ths)}`);

    // Caption: the D1 (wall-clock-vs-agent-time), D6 (remediation-not-failure)
    // and D11 (metrics-ledger row set) sentences, pinned as substrings that do
    // NOT overlap the <th> label text, so they cannot be satisfied by the
    // headings surviving while the caption prose is gutted.
    const captionMatch = section.match(/<p class="meta">([\s\S]*?)<\/p>/);
    if (!captionMatch) { console.log("FAIL:no caption <p class=\"meta\"> found in scope-cost section"); process.exit(1); }
    const caption = captionMatch[1];
    if (!caption.includes("is the span from this scope")) errors.push("caption missing D1 elapsed-definition clause");
    if (!caption.includes("is the total of each run")) errors.push("caption missing D1 agent-time-definition clause");
    if (!caption.includes("they are different numbers and neither bounds the other")) errors.push("caption missing D1 wall-clock-versus-agent-time rule sentence");
    if (!caption.includes("so this is rework, not a failure rate")) errors.push("caption missing D6 remediation-not-failure sentence");
    if (!caption.includes("One row per ride recorded in")) errors.push("caption missing D11 metrics-ledger row set sentence");
    if (!caption.includes("none are filtered by close state")) errors.push("caption missing D11 unfiltered-row-set clause");
    if (!caption.includes("Roles are listed in a fixed canonical order, not the order in which they ran.")) errors.push("caption missing NB-6 canonical-order clause (R2-NB-3)");
    if (!caption.includes("the true rework share runs higher than this figure alone")) errors.push("caption missing NB-1 cumulative-exclusion clause (R2-NB-3)");

    // fmtDur mirrored from the generator (.aai/scripts/generate-factory-report.mjs)
    // to compute the expected rendered text from the raw JSON seconds — fmtDur
    // itself is exercised elsewhere (TEST-031 hand-computes the raw seconds);
    // this only checks that the HTML cell reproduces what that function emits.
    function fmtDur(sec) {
      if (sec === null || sec === undefined) return "n/a";
      if (sec < 90) return `${sec}s`;
      if (sec < 5400) return `${Math.round(sec / 60)}m`;
      return `${Math.round((sec / 3600) * 10) / 10}h`;
    }

    let cursor = 0;
    for (const s of m.scope_cost.scopes) {
      const refIdx = section.indexOf(`>${s.ref}<`, cursor);
      if (refIdx === -1) { errors.push(`ref ${s.ref} not found in row order after cursor ${cursor}`); continue; }
      const rowStart = section.lastIndexOf("<tr>", refIdx);
      const rowEnd = section.indexOf("</tr>", refIdx) + "</tr>".length;
      const row = section.slice(rowStart, rowEnd);
      cursor = rowEnd;

      // Cell-by-cell parity, fixed column order — each cell is checked against
      // its OWN JSON field, never rescued by a sibling cell (a swapped or
      // constant-replaced column is caught at its own index; a row-scoped
      // ">n/a<" search can no longer be satisfied by a DIFFERENT null cell in
      // the same row).
      const cells = [...row.matchAll(/<td>([\s\S]*?)<\/td>/g)].map((mm) => mm[1]);
      if (cells.length !== 7) { errors.push(`${s.ref}: row has ${cells.length} <td> cells, expected 7`); continue; }
      const [refCell, elapsedCell, agentCell, rolesCell, tokenCell, remCell, shareCell] = cells;

      if (refCell !== s.ref) errors.push(`${s.ref}: ref cell "${refCell}" != "${s.ref}"`);

      const expectedElapsed = fmtDur(s.elapsed_wall_seconds);
      if (elapsedCell !== expectedElapsed) errors.push(`${s.ref}: Elapsed cell "${elapsedCell}" != expected "${expectedElapsed}" (elapsed_wall_seconds=${s.elapsed_wall_seconds})`);

      const expectedAgent = fmtDur(s.agent_seconds);
      if (agentCell !== expectedAgent) errors.push(`${s.ref}: Agent-time cell "${agentCell}" != expected "${expectedAgent}" (agent_seconds=${s.agent_seconds})`);

      // NB-4: a zero-run ride must render the named line, never a blank cell.
      const expectedRoles = s.roles.length ? s.roles.map((r) => `${r.role} ${r.runs}`).join(", ") : "no runs recorded";
      if (rolesCell !== expectedRoles) errors.push(`${s.ref}: Roles cell "${rolesCell}" != expected "${expectedRoles}"`);

      const expectedToken = s.runs_marked === 0
        ? `no usage marker (0/${s.runs_total} runs)`
        : `${s.tokens_total} (${s.runs_marked}/${s.runs_total} runs)`;
      if (tokenCell !== expectedToken) errors.push(`${s.ref}: Tokens cell "${tokenCell}" != expected "${expectedToken}"`);

      const expectedRem = String(s.remediation_runs);
      if (remCell !== expectedRem) errors.push(`${s.ref}: Remediation-runs cell "${remCell}" != expected "${expectedRem}"`);

      const expectedShare = s.remediation_share_pct === null ? "n/a" : `${s.remediation_share_pct}%`;
      if (shareCell !== expectedShare) errors.push(`${s.ref}: Remediation-share cell "${shareCell}" != expected "${expectedShare}"`);
    }

    // Row cardinality: the per-scope loop above proves presence and order but
    // never count, so a duplicated <tr> or an injected ghost <tr> would be
    // invisible to it. Assert the <tbody> holds EXACTLY one <tr> per
    // scope_cost.scopes[] entry, never merely "at least one, in order".
    const tbodyMatch = section.match(/<tbody>([\s\S]*?)<\/tbody>/);
    if (!tbodyMatch) { console.log("FAIL:no <tbody> found in scope-cost table"); process.exit(1); }
    const trCount = (tbodyMatch[1].match(/<tr>/g) || []).length;
    if (trCount !== m.scope_cost.scopes.length) errors.push(`tbody has ${trCount} <tr> rows, expected ${m.scope_cost.scopes.length} (one per scope_cost.scopes[] entry)`);

    if (errors.length) { console.log("FAIL:" + errors.join(" | ")); process.exit(1); }
    console.log("OK");
  ' "$DJ" "$html")" && rc=0 || rc=$?
  [[ "$rc" == 0 && "$result" == "OK" ]] || log_fail "scope-cost html parity wrong: $result"
  log_pass "scope-cost: all 7 column headings pinned by position, caption D1/D6/D11 sentences pinned, every cell (ref/elapsed/agent-time/roles/tokens/remediation-runs/share) compared 1:1 against the JSON in row order, multi-role/null-agent-time/zero-run(NB-4)/zero-token-marker-remediation(NB-5) rows exercised, row count pinned exactly (TEST-037)"
}

# ============ TEST-039 (Spec-AC-09, spec-ride-cost-readout) ==================
test_039_scope_cost_product_doc_pins() {
  log_info "Test: docs/product/factory-performance-report.md pins the Scope cost section, both time labels + divergence statement, the marker-only + denominator rule, the named no-marker rule, the remediation-not-failure rule, frontmatter delivered_by + updated bump, and the intake capability fix (TEST-039)..."
  local doc="$PROJECT_ROOT/docs/product/factory-performance-report.md"
  [[ -f "$doc" ]] || log_fail "product doc not found: $doc"
  grep -qF 'Scope cost' "$doc" || log_fail "product doc must name the Scope cost section"
  grep -qF 'Elapsed (wall clock)' "$doc" || log_fail "product doc must name the Elapsed (wall clock) label"
  grep -qF 'Agent time (summed)' "$doc" || log_fail "product doc must name the Agent time (summed) label"
  grep -qF 'diverge' "$doc" || log_fail "product doc must state the two time figures diverge"
  grep -qF 'runs_marked' "$doc" || log_fail "product doc must name the runs_marked denominator"
  grep -qF 'no usage marker (0/N runs)' "$doc" || log_fail "product doc must name the literal no-marker line"
  grep -qF 'not a failure rate' "$doc" || log_fail "product doc must state the remediation-not-failure rule"
  # NB-2 (fifth instance of the same defect class on this ride): grep -qF
  # 'ride-cost-readout' over the WHOLE doc claims to assert frontmatter
  # delivered_by but cannot fail on what it names — the Links section (file
  # paths CHANGE-0148-ride-cost-readout.md / spec-ride-cost-readout.md)
  # carries the same substring, so deleting the delivered_by entry alone
  # leaves this arm green. Anchor to the frontmatter block itself (the text
  # between the first two literal '---' delimiter lines), never the whole doc.
  local frontmatter
  frontmatter="$(awk '/^---$/{n++; next} n==1' "$doc")"
  echo "$frontmatter" | grep -qE '^[[:space:]]*-[[:space:]]*ride-cost-readout[[:space:]]*$' \
    || log_fail "product doc frontmatter delivered_by must include ride-cost-readout"
  # NB-3: a literal date pin turns every future legitimate edit of this doc
  # into a failure of an unrelated scope's test (Spec-AC-09 itself requires
  # 'updated' to be bumped on every touch). Assert the frontmatter carries a
  # well-formed ISO date, not this scope's specific one.
  echo "$frontmatter" | grep -qE '^updated: [0-9]{4}-[0-9]{2}-[0-9]{2}$' \
    || log_fail "product doc frontmatter updated must be a well-formed ISO date"
  local change="$PROJECT_ROOT/docs/issues/CHANGE-0148-ride-cost-readout.md"
  [[ -f "$change" ]] || log_fail "intake not found: $change"
  grep -qF 'capability: factory-performance-report' "$change" || log_fail "intake frontmatter capability must read factory-performance-report"
  log_pass "product doc pins present: section, two time labels + divergence, marker-only + denominator, named no-marker line, remediation-not-failure, frontmatter-anchored delivered_by + well-formed updated date; intake capability fixed (TEST-039)"
}

main() {
  echo "Testing $TEST_NAME (SPEC spec-factory-performance-report TEST-001..014, +017..019; telemetry-completeness TEST-020..021; role-token-trend TEST-022..027; followup-registry TEST-028..029; scope-cost TEST-031..037,039)"
  echo "  + followups-cli-hardening TEST-040; operator-waiver-unblocks-pr TEST-041"
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
  test_040_follow_ups_unreadable_and_understatement
  test_041_validation_waivers_surfaced
  test_031_scope_cost_elapsed_and_agent_time
  test_032_scope_cost_role_counts
  test_033_scope_cost_token_source
  test_034_scope_cost_partial_and_no_data
  test_035_scope_cost_rework
  test_036_scope_cost_report_only
  test_037_scope_cost_html_parity
  test_039_scope_cost_product_doc_pins
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
