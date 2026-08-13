#!/usr/bin/env bash
#
# Test: aai-dashboard generator — real note-carried usage totals + named
# no-data panels
# (docs/specs/SPEC-0127-spec-reporting-docs-true-up.md, TEST-001..006 +
#  TEST-011; intake CHANGE-0140 AC-003/AC-004/AC-005/AC-006).
#
# Covers .aai/scripts/generate-dashboard.mjs + docs/dashboard-template.html:
#   - TEST-001 (Spec-AC-03): fixture ledger with marker-carrying notes
#     (tokens_in/out null): summary.totalTokens, per-day tokensByTime totals
#     and per-skill token stats equal the exact marker sums.
#   - TEST-002 (Spec-AC-03, honesty): a marker is only ever a TOTAL — never
#     split into in/out; explicit finite in/out WINS over a marker (no
#     double count); malformed (`usage_total_tokens=123oops`) and prefixed
#     (`not_usage_total_tokens=456`) markers contribute nothing.
#   - TEST-003 (Spec-AC-04): no-data fixture — the RENDERED HTML carries the
#     named no-data state (`data-panel="..."`) for tokens/tdd/worktree/
#     publish, no bare empty canvas, all template placeholders consumed.
#   - TEST-004 (Spec-AC-04): has-data fixture (incl. one legacy flat entry):
#     all four canvases render, no-data markers absent.
#   - TEST-005 (Spec-AC-03, structural pin / D3): generate-dashboard.mjs
#     IMPORTS extractUsageTotal from ./lib/usage-note.mjs and carries no
#     local copy of the raw marker regex literal (test_120 in
#     test-aai-metrics.sh pins the repo-wide single occurrence).
#   - TEST-006 (Spec-AC-05): .aai/SKILL_DASHBOARD.prompt.md pin — the stale
#     "known gap" caveat is gone, the note-parse behavior is described.
#   - TEST-011 (Spec-AC-06): docs/product/aai-dashboard.md is a REAL product
#     doc (capability aai-dashboard, no placeholder sections per
#     lib/product-doc.mjs).
#
# Fixture diversity checklist (SPEC-0013 H7), mapped:
#   - degenerate/empty       -> TEST-003: runs with zero token signal
#   - zero-remainder         -> TEST-001: exact-sum equality, no tolerance
#   - multi-source           -> TEST-004: ledger entries + one legacy flat
#                               entry in ONE METRICS.jsonl
#   - negative control       -> TEST-002 malformed/prefixed markers;
#                               TEST-004 no-data markers must be ABSENT
#
# ALL fixtures are throwaway files under a mktemp dir; generator runs use
# --metrics/--output pointing INTO the fixture dir (cwd stays PROJECT_ROOT
# so the real docs/dashboard-template.html is exercised — SEAM-2). The real
# docs/ai/ outputs are NEVER touched.
#
# bash 3.2 compatible (no ${var^^}, no declare -A). Here-strings instead of
# pipes into while-loops (set -euo pipefail safety).
#
# Usage:
#   bash tests/skills/test-aai-dashboard.sh                    # run all
#   bash tests/skills/test-aai-dashboard.sh test_001_marker_totals
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-dashboard"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GENERATOR="$PROJECT_ROOT/.aai/scripts/generate-dashboard.mjs"
TEMPLATE="$PROJECT_ROOT/docs/dashboard-template.html"
PROMPT="$PROJECT_ROOT/.aai/SKILL_DASHBOARD.prompt.md"
PRODUCT_DOC="$PROJECT_ROOT/docs/product/aai-dashboard.md"

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
  [[ -f "$GENERATOR" ]] || log_fail "generate-dashboard.mjs not found: $GENERATOR"
  [[ -f "$TEMPLATE" ]] || log_fail "dashboard-template.html not found: $TEMPLATE"
  log_pass "Dependencies checked"
}

setup_fixture() { TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-dashboard-test.XXXXXX")"; }

# write_ledger_entry <file> <date> <ref> <runs-json>
# Appends one work-item ledger line whose agent_runs come from <runs-json>
# (a JSON array literal; each element may carry role/started_utc/tokens_in/
# tokens_out/note/duration_seconds/worktree).
write_ledger_entry() {
  local f="$1" date="$2" ref="$3" runs="$4"
  node -e '
    const fs = require("fs");
    const [file, date, ref, runsJson] = process.argv.slice(1);
    const defaults = { role: "Run", model_id: "m", started_utc: null, ended_utc: null,
      duration_seconds: null, tokens_in: null, tokens_out: null, cost_usd: null };
    const runs = JSON.parse(runsJson).map((r) => ({ ...defaults, ...r }));
    const entry = { date_utc: date, ref_id: ref, title: "fixture " + ref,
      human_time_minutes: { intake: 0, reviews: 0 }, agent_runs: runs,
      totals: { human_time_minutes: 0, agent_duration_seconds: 0, total_cost_usd: null },
      verdict: "PASS" };
    fs.appendFileSync(file, JSON.stringify(entry) + "\n");
  ' "$f" "$date" "$ref"  "$runs"
}

# run_generator <metrics> <output> [extra flags...] -> exit code in EC,
# stdout+stderr in $OUT
EC=0
OUT=""
run_generator() {
  local metrics="$1" output="$2"
  shift 2
  OUT="$TEST_DIR/generator-out.txt"
  EC=0
  (cd "$PROJECT_ROOT" && node "$GENERATOR" --metrics "$metrics" --output "$output" "$@") > "$OUT" 2>&1 || EC=$?
}

# json_probe <data.json> <expr> — evaluates a JS expression over parsed data
# `d`, prints the result.
json_probe() {
  node -e '
    const fs = require("fs");
    const d = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    console.log(String(eval(process.argv[2])));
  ' "$1" "$2"
}

test_001_marker_totals() {  # TEST-001 (Spec-AC-03)
  log_info "Test: marker-carrying notes (tokens null) produce exact summary/per-day/per-skill token totals (TEST-001)..."
  local d="$TEST_DIR/t001"
  mkdir -p "$d"
  : > "$d/METRICS.jsonl"
  # Day 1: 1000 (plain marker) + 2500 (parenthesized marker, bracketed model
  # id nearby, sentence-boundary period). Day 2: 500.
  write_ledger_entry "$d/METRICS.jsonl" "2026-08-01" "FIX-0001" '[
    {"role":"Implementation","started_utc":"2026-08-01T10:00:00Z","note":"usage_total_tokens=1000 (harness total; in/out not exposed)"},
    {"role":"Validation","started_utc":"2026-08-01T12:00:00Z","note":"run ok (usage_total_tokens=2500) actual_model=claude-opus-4-8[1m]."}
  ]'
  write_ledger_entry "$d/METRICS.jsonl" "2026-08-02" "FIX-0002" '[
    {"role":"Implementation","started_utc":"2026-08-02T09:00:00Z","note":"done. usage_total_tokens=500."}
  ]'
  run_generator "$d/METRICS.jsonl" "$d/dashboard.html" --data-only
  [[ "$EC" == 0 ]] || log_fail "generator must exit 0 (got $EC): $(cat "$OUT")"
  local data="$d/dashboard-data.json"
  [[ -f "$data" ]] || log_fail "dashboard-data.json not written next to output"

  local got
  got="$(json_probe "$data" 'd.summary.totalTokens')"
  [[ "$got" == "4000" ]] || log_fail "TEST-001 summary.totalTokens must be 4000 (1000+2500+500), got $got"
  got="$(json_probe "$data" 'd.tokensByTime["2026-08-01"].total')"
  [[ "$got" == "3500" ]] || log_fail "TEST-001 tokensByTime[2026-08-01].total must be 3500, got $got"
  got="$(json_probe "$data" 'd.tokensByTime["2026-08-02"].total')"
  [[ "$got" == "500" ]] || log_fail "TEST-001 tokensByTime[2026-08-02].total must be 500, got $got"
  got="$(json_probe "$data" 'd.skillStats.filter(s => s.name === "Implementation")[0].avgTokens')"
  [[ "$got" == "750" ]] || log_fail "TEST-001 Implementation avgTokens must be 750 ((1000+500)/2), got $got"
  got="$(json_probe "$data" 'd.skillStats.filter(s => s.name === "Validation")[0].avgTokens')"
  [[ "$got" == "2500" ]] || log_fail "TEST-001 Validation avgTokens must be 2500, got $got"
  grep -q 'Total tokens: 4000' "$OUT" || log_fail "TEST-001 CLI summary line must report 'Total tokens: 4000': $(cat "$OUT")"
  log_pass "TEST-001 marker sums: totalTokens 4000, per-day 3500/500, per-skill 750/2500 (exact)"
}

test_002_marker_honesty() {  # TEST-002 (Spec-AC-03)
  log_info "Test: honesty — marker never split into in/out; explicit in/out wins over marker; malformed/prefixed markers contribute nothing (TEST-002)..."
  local d="$TEST_DIR/t002"
  mkdir -p "$d"
  : > "$d/METRICS.jsonl"
  write_ledger_entry "$d/METRICS.jsonl" "2026-08-03" "FIX-0003" '[
    {"role":"Implementation","started_utc":"2026-08-03T10:00:00Z","tokens_in":100,"tokens_out":50,"note":"usage_total_tokens=999 (explicit fields win; marker must be ignored)"},
    {"role":"Validation","started_utc":"2026-08-03T11:00:00Z","note":"usage_total_tokens=123oops (malformed value)"},
    {"role":"Planning","started_utc":"2026-08-03T12:00:00Z","note":"not_usage_total_tokens=456 (prefixed key)"},
    {"role":"Remediation","started_utc":"2026-08-03T13:00:00Z","note":"usage_total_tokens=200"}
  ]'
  run_generator "$d/METRICS.jsonl" "$d/dashboard.html" --data-only
  [[ "$EC" == 0 ]] || log_fail "generator must exit 0 (got $EC): $(cat "$OUT")"
  local data="$d/dashboard-data.json" got

  # 150 (explicit, marker ignored — no double count) + 200 (marker) + 0 + 0.
  got="$(json_probe "$data" 'd.summary.totalTokens')"
  [[ "$got" == "350" ]] || log_fail "TEST-002 summary.totalTokens must be 350 (150 explicit + 200 marker; malformed/prefixed 0), got $got"
  # A marker is a TOTAL: the in/out series carry ONLY the explicit fields.
  got="$(json_probe "$data" 'd.tokensByTime["2026-08-03"].input')"
  [[ "$got" == "100" ]] || log_fail "TEST-002 day input must be 100 (explicit only — marker never split into in/out), got $got"
  got="$(json_probe "$data" 'd.tokensByTime["2026-08-03"].output')"
  [[ "$got" == "50" ]] || log_fail "TEST-002 day output must be 50 (explicit only — marker never split into in/out), got $got"
  got="$(json_probe "$data" 'd.tokensByTime["2026-08-03"].total')"
  [[ "$got" == "350" ]] || log_fail "TEST-002 day total must be 350, got $got"
  got="$(json_probe "$data" 'd.skillStats.filter(s => s.name === "Validation")[0].avgTokens')"
  [[ "$got" == "0" ]] || log_fail "TEST-002 malformed marker must contribute 0 tokens, got $got"
  got="$(json_probe "$data" 'd.skillStats.filter(s => s.name === "Planning")[0].avgTokens')"
  [[ "$got" == "0" ]] || log_fail "TEST-002 prefixed marker must contribute 0 tokens, got $got"
  log_pass "TEST-002 honesty: explicit wins (150), marker stays a total (200), malformed/prefixed contribute 0, in/out never fabricated"
}

test_003_no_data_panels() {  # TEST-003 (Spec-AC-04)
  log_info "Test: whole-dataset-absent sources render the named no-data state in the RENDERED HTML (TEST-003)..."
  local d="$TEST_DIR/t003"
  mkdir -p "$d"
  : > "$d/METRICS.jsonl"
  # Runs exist but carry NO token signal (null tokens, notes without any
  # valid marker), no red/green/refactor role, no worktree, no share/publish.
  write_ledger_entry "$d/METRICS.jsonl" "2026-08-04" "FIX-0004" '[
    {"role":"Implementation","started_utc":"2026-08-04T10:00:00Z","note":"usage_capture=none (honest absence, no total)"},
    {"role":"Validation","started_utc":"2026-08-04T11:00:00Z"}
  ]'
  run_generator "$d/METRICS.jsonl" "$d/dashboard.html"
  [[ "$EC" == 0 ]] || log_fail "generator must exit 0 (got $EC): $(cat "$OUT")"
  local html="$d/dashboard.html"
  [[ -f "$html" ]] || log_fail "rendered dashboard.html missing"

  local panel
  for panel in tokens tdd worktree publish; do
    grep -q "data-panel=\"$panel\"" "$html" \
      || log_fail "TEST-003 rendered HTML must carry the named no-data state for '$panel' (data-panel=\"$panel\")"
  done
  grep -q 'No data recorded in this dataset' "$html" \
    || log_fail "TEST-003 no-data state must carry the visible text 'No data recorded in this dataset'"
  # In place of the canvas — never a bare empty axis.
  local id
  for id in tokenChart tddChart worktreeChart publishChart; do
    grep -q "<canvas id=\"$id\"" "$html" \
      && log_fail "TEST-003 canvas '$id' must NOT render when its whole-dataset source is absent (bare empty axis)"
  done
  grep -q '{{PANEL_' "$html" \
    && log_fail "TEST-003 unconsumed {{PANEL_*}} placeholder leaked into the rendered HTML"
  # The token no-data state is an ABSENCE state, not a zero-value chart:
  # summary still reports 0 tokens honestly.
  local got
  got="$(json_probe "$d/dashboard-data.json" 'd.summary.totalTokens')"
  [[ "$got" == "0" ]] || log_fail "TEST-003 zero-signal dataset must report totalTokens 0, got $got"
  log_pass "TEST-003 no-data fixture: named no-data state for tokens/tdd/worktree/publish, no bare canvas, placeholders consumed"
}

test_004_has_data_renders_charts() {  # TEST-004 (Spec-AC-04)
  log_info "Test: dataset WITH tdd/worktree/publish/token data (incl. one legacy flat entry) renders charts, no-data markers absent (TEST-004)..."
  local d="$TEST_DIR/t004"
  mkdir -p "$d"
  : > "$d/METRICS.jsonl"
  write_ledger_entry "$d/METRICS.jsonl" "2026-08-05" "FIX-0005" '[
    {"role":"TDD red phase","started_utc":"2026-08-05T10:00:00Z","duration_seconds":30,"note":"usage_total_tokens=1200","worktree":"wt-a"},
    {"role":"TDD green phase","started_utc":"2026-08-05T10:10:00Z","duration_seconds":60,"note":"usage_total_tokens=800","worktree":"wt-a"},
    {"role":"TDD refactor phase","started_utc":"2026-08-05T10:20:00Z","duration_seconds":20,"worktree":"wt-b"}
  ]'
  # Legacy flat operation record (still parsed, no longer written).
  printf '%s\n' '{"timestamp":"2026-08-05T12:00:00Z","skill":"aai-share","operation":"publish","tokens":{"input":300,"output":100},"duration_ms":5000,"status":"success","metadata":{"worktree":"wt-a"}}' >> "$d/METRICS.jsonl"

  run_generator "$d/METRICS.jsonl" "$d/dashboard.html"
  [[ "$EC" == 0 ]] || log_fail "generator must exit 0 (got $EC): $(cat "$OUT")"
  local html="$d/dashboard.html" data="$d/dashboard-data.json"

  local id
  for id in tokenChart tddChart worktreeChart publishChart; do
    grep -q "<canvas id=\"$id\"" "$html" \
      || log_fail "TEST-004 canvas '$id' must render when the dataset HAS the data"
  done
  grep -q 'data-panel=' "$html" \
    && log_fail "TEST-004 no-data marker must be ABSENT when every section has data"
  grep -q '{{PANEL_' "$html" \
    && log_fail "TEST-004 unconsumed {{PANEL_*}} placeholder leaked into the rendered HTML"

  local got
  got="$(json_probe "$data" 'd.summary.totalTokens')"
  [[ "$got" == "2400" ]] || log_fail "TEST-004 totalTokens must be 2400 (1200+800 markers + 400 legacy in/out), got $got"
  got="$(json_probe "$data" 'd.tokensByTime["2026-08-05"].input')"
  [[ "$got" == "300" ]] || log_fail "TEST-004 legacy flat input must flow into the input series (300), got $got"
  got="$(json_probe "$data" 'd.tokensByTime["2026-08-05"].output')"
  [[ "$got" == "100" ]] || log_fail "TEST-004 legacy flat output must flow into the output series (100), got $got"
  got="$(json_probe "$data" 'd.tddStats === null')"
  [[ "$got" == "false" ]] || log_fail "TEST-004 tddStats must be non-null for red/green/refactor roles"
  got="$(json_probe "$data" 'd.worktreeStats["wt-a"]')"
  [[ "$got" == "3" ]] || log_fail "TEST-004 worktreeStats[wt-a] must count 3 operations (2 runs + legacy metadata), got $got"
  got="$(json_probe "$data" 'd.publishStats["2026-08-05"]')"
  [[ "$got" == "1" ]] || log_fail "TEST-004 publishStats must count the aai-share operation, got $got"
  log_pass "TEST-004 has-data fixture: all four charts render, no-data markers absent, legacy flat entry counted (2400 total)"
}

test_005_shared_lib_import_pin() {  # TEST-005 (Spec-AC-03, D3)
  log_info "Test: structural pin — generate-dashboard.mjs imports extractUsageTotal from ./lib/usage-note.mjs, no local regex literal (TEST-005)..."
  grep -qE "from '\\./lib/usage-note\\.mjs'" "$GENERATOR" \
    || log_fail "TEST-005 generate-dashboard.mjs must import from './lib/usage-note.mjs' (D3: the shared grammar is imported, never forked)"
  grep -q 'extractUsageTotal' "$GENERATOR" \
    || log_fail "TEST-005 generate-dashboard.mjs must use extractUsageTotal from the shared lib"
  grep -qF 'usage_total_tokens=(\d+)' "$GENERATOR" \
    && log_fail "TEST-005 generate-dashboard.mjs must NOT carry a local copy of the raw marker regex literal (test_120 single-source contract)"
  log_pass "TEST-005 structural pin: shared-lib import present, no local marker regex literal"
}

test_006_prompt_caveat_truthful() {  # TEST-006 (Spec-AC-05)
  log_info "Test: SKILL_DASHBOARD.prompt.md — stale known-gap caveat gone, note-parse behavior described (TEST-006)..."
  [[ -f "$PROMPT" ]] || log_fail "TEST-006 prompt not found: $PROMPT"
  local ok=1
  if grep -q 'Tokens are mostly null' "$PROMPT"; then
    log_info "TEST-006 stale caveat heading 'Tokens are mostly null' still present"
    ok=0
  fi
  if grep -q 'known gap' "$PROMPT"; then
    log_info "TEST-006 stale 'known gap' wording still present (the gap is fixed — notes are parsed)"
    ok=0
  fi
  if ! grep -qF 'usage_total_tokens=<N>' "$PROMPT"; then
    log_info "TEST-006 prompt must describe the usage_total_tokens=<N> note-parse behavior"
    ok=0
  fi
  if ! grep -q 'usage-note.mjs' "$PROMPT"; then
    log_info "TEST-006 prompt must name the shared grammar source (.aai/scripts/lib/usage-note.mjs)"
    ok=0
  fi
  if ! grep -q 'No data recorded in this dataset' "$PROMPT"; then
    log_info "TEST-006 prompt (troubleshooting row) must describe the named no-data panel state"
    ok=0
  fi
  [[ $ok -eq 1 ]] \
    && log_pass "TEST-006 prompt caveat truthful: note-parse + shared lib + no-data state described, stale gap wording gone" \
    || log_fail "TEST-006 prompt caveat (see INFO lines above)"
}

test_011_product_doc_real() {  # TEST-011 (Spec-AC-06)
  log_info "Test: docs/product/aai-dashboard.md is a REAL product doc per lib/product-doc.mjs (TEST-011)..."
  [[ -f "$PRODUCT_DOC" ]] || log_fail "TEST-011 missing docs/product/aai-dashboard.md (user_visible close gate will demand it)"
  local out
  out="$(node -e '
    import(process.argv[1]).then((lib) => {
      const fs = require("fs");
      const content = fs.readFileSync(process.argv[2], "utf8");
      const missing = lib.missingProductSections(content);
      if (missing.length > 0) { console.log("PLACEHOLDER: " + missing.join(", ")); process.exit(1); }
      const cap = /^capability:[ \t]*(.+)$/m.exec(content);
      if (!cap || cap[1].trim() !== "aai-dashboard") { console.log("BAD-CAPABILITY: " + (cap ? cap[1] : "absent")); process.exit(1); }
      console.log("REAL");
    });
  ' "$PROJECT_ROOT/.aai/scripts/lib/product-doc.mjs" "$PRODUCT_DOC" 2>&1)" \
    || log_fail "TEST-011 product-doc predicate failed: $out"
  [[ "$out" == "REAL" ]] || log_fail "TEST-011 unexpected predicate output: $out"
  log_pass "TEST-011 docs/product/aai-dashboard.md passes the placeholder predicate with capability aai-dashboard"
}

main() {
  echo "=== Test: $TEST_NAME ==="
  check_deps
  setup_fixture
  if [[ $# -gt 0 ]]; then
    "$1"
  else
    test_001_marker_totals
    test_002_marker_honesty
    test_003_no_data_panels
    test_004_has_data_renders_charts
    test_005_shared_lib_import_pin
    test_006_prompt_caveat_truthful
    test_011_product_doc_real
  fi
  echo "=== All $TEST_NAME tests passed ==="
}

main "$@"
