#!/usr/bin/env bash
#
# Test: aai-metrics — deterministic metrics flush + report scripts
# (CHANGE-0009 / spec-mechanize-deterministic-ticks, TEST-006..014).
#
# Verifies .aai/scripts/metrics-flush.mjs and .aai/scripts/metrics-report.mjs:
#   - flush happy-path golden ledger line incl. PRICING lookup_rules cost
#     resolution (strip-[..], alias, longest-prefix, unknown) (TEST-006)
#   - timing fidelity ±1s, null-never-estimated (TEST-007)
#   - criteria negatives, each with a named skip reason (TEST-008)
#   - per-run null-token WARNING lines, never aggregated (TEST-009)
#   - LINE-SURGICAL cleanup: commented schema header + untouched blocks
#     byte-identical (TEST-010)
#   - partial-flush H5 reset with flush-provenance notes (TEST-011)
#   - full reset + ephemeral cleanup with the protected set (TEST-012)
#   - transactionality: ledger-before-reset, crash resume, --dry-run (TEST-013)
#   - report golden: byte-deterministic markdown (TEST-014)
#
# Truth-scoring (SPEC-0032-spec-truth-scoring, RES-0001 P3) — TEST-006/TEST-014
# goldens extended (strategy + reliability fields / Per-Strategy Reliability
# section), plus:
#   - reliability derivation matrix per spec rules R1-R6 (TEST-017)
#   - per-strategy reliability report golden, old lines n/a (TEST-018)
#
# ALL fixtures are scratch temp-dir repos (path-flag overrides); the real
# runtime files are NEVER touched. bash 3.2 compatible.
#
# Exit codes: 0 pass, 1 fail, 42 skip.

set -euo pipefail

TEST_NAME="aai-metrics"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Pipe-free payload assertions (spec-assertions-must-not-die-on-their-own-payload).
# shellcheck source=lib/assert-payload.sh
. "$SCRIPT_DIR/lib/assert-payload.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FLUSH="$PROJECT_ROOT/.aai/scripts/metrics-flush.mjs"
REPORT="$PROJECT_ROOT/.aai/scripts/metrics-report.mjs"
NOW_PIN="2026-07-15T12:00:00Z"

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
  [[ -f "$FLUSH" ]] || log_fail "flush script not found: $FLUSH (RED until CHANGE-0009 lands)"
  [[ -f "$REPORT" ]] || log_fail "report script not found: $REPORT (RED until CHANGE-0009 lands)"
  log_pass "Dependencies checked"
}

setup_fixture() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-metrics-test.XXXXXX")"
}

# --- fixture builders ---------------------------------------------------------

# mk_repo <name> — isolated repo root with the real docs/ai layout. Echoes dir.
mk_repo() {
  local d="$TEST_DIR/$1"
  rm -rf "$d"
  mkdir -p "$d/docs/ai/tdd" "$d/docs/ai/reports" "$d/docs/issues" "$d/docs/specs"
  printf '# ledger comment header\n' > "$d/docs/ai/METRICS.jsonl"
  write_pricing "$d/PRICING.yaml"
  printf '%s' "$d"
}

write_pricing() {
  cat > "$1" <<'YAML'
# fixture pricing table (CHANGE-0009 metrics suite)
schema_version: 2
lookup_rules:
  order:
    - strip-bracket-suffix
    - model-aliases
    - exact-match
    - longest-prefix
    - unknown-fallback
  strip_suffix_pattern: "\\[[^\\]]*\\]$"
model_aliases:
  sonnet-latest: claude-sonnet-5
models:
  claude-opus-4-8:
    input_usd_per_m: 5.00
    output_usd_per_m: 25.00
  claude-sonnet-5:
    input_usd_per_m: 3.00
    output_usd_per_m: 15.00
  unknown:
    input_usd_per_m: null
    output_usd_per_m: null
YAML
}

# The canonical flush STATE fixture: full schema with the commented header
# (incl. the orchestration lines the orchestration-mode suite asserts on the
# real file — the exact lines a whole-file re-serialization destroyed).
# $1 file; $2 items: "single" (CHANGE-0001 only) | "two" (CHANGE-0001 done +
# CHANGE-0002 in_progress); $3 vstatus (default pass); $4 rstatus (default pass)
write_flush_state() {
  local f="$1" items="${2:-single}" vstatus="${3:-pass}" rstatus="${4:-pass}"
  cat > "$f" <<YAML
# docs/ai/STATE.yaml - AAI runtime state (managed by orchestration; humans need not edit)
#
# CANONICAL SCHEMA / INVARIANTS (authoritative; see .aai/SKILL_CHECK_STATE.prompt.md)
#   project_status:            active | paused
#   last_validation.status:    pass | fail | not_run
#   updated_at_utc:            ISO 8601 UTC
#   orchestration.mode:        auto | single | parallel   (RFC-0005 / SPEC-0005; default auto)
#   orchestration.k:           integer chosen fan-out for the last tick (1 when single)
#   orchestration.groups:      last selector partition [{kind: parallel|sequential, scopes: [...]}]
#     The whole orchestration block is OPTIONAL: an absent block == auto (back-compat).
project_status: active
current_focus:
  type: intake_change
  ref_id: CHANGE-0001
  primary_path: docs/issues/CHANGE-0001-golden.md
active_work_items:
  - ref_id: CHANGE-0001
    status: done
    phase: validation
    primary_path: docs/issues/CHANGE-0001-golden.md
    spec_path: docs/specs/SPEC-0001-fx.md
YAML
  if [[ "$items" == "two" ]]; then
    cat >> "$f" <<YAML
  - ref_id: CHANGE-0002
    status: in_progress
    phase: implementation
    primary_path: docs/issues/CHANGE-0002-other.md
YAML
  fi
  cat >> "$f" <<YAML
implementation_strategy:
  selected: tdd
  source: docs/specs/SPEC-0001-fx.md
  rationale: >-
    Fixture strategy rationale.
worktree:
  recommendation: optional
  user_decision: inline
  base_ref: main
  branch: null
  path: null
  inline_review_scope: >-
    fixture inline scope
  rationale: null
code_review:
  required: true
  status: $rstatus
  scope: >-
    fixture review scope
  base_ref: main
  head_ref: null
  pr: null
  report_paths:
  - docs/ai/reviews/review-fixture.md
  notes: null
last_validation:
  status: $vstatus
  run_at_utc: 2026-07-15T11:00:00Z
  ref_id: CHANGE-0001
  evidence_paths:
  - docs/ai/reports/validation-fixture.md
  notes: null
human_input:
  required: false
  question: null
locks:
  implementation: true
orchestration:
  mode: single
  k: 1
  groups:
  - kind: sequential
    scopes:
    - null
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
    CHANGE-0001:
      human_time_minutes:
        intake: null
        reviews: null
      agent_runs:
        - role: Planning
          model_id: claude-opus-4-8[1m]
          started_utc: 2026-07-15T10:00:00Z
          ended_utc: 2026-07-15T10:02:00Z
          duration_seconds: 120
          tokens_in: 1000000
          tokens_out: 100000
          cost_usd: null
        - role: Implementation
          model_id: sonnet-latest
          started_utc: 2026-07-15T10:02:00Z
          ended_utc: 2026-07-15T10:12:00Z
          duration_seconds: 600
          tokens_in: 2000000
          tokens_out: 200000
          cost_usd: null
        - role: Validation
          model_id: claude-sonnet-5-20260101
          started_utc: 2026-07-15T10:12:00Z
          ended_utc: 2026-07-15T10:13:40Z
          duration_seconds: 100
          tokens_in: 1000000
          tokens_out: 1000000
          cost_usd: null
        - role: Code Review
          model_id: mystery-9000
          started_utc: 2026-07-15T10:13:40Z
          ended_utc: 2026-07-15T10:14:40Z
          duration_seconds: 60
          tokens_in: 10
          tokens_out: 10
          cost_usd: null
YAML
  if [[ "$items" == "two" ]]; then
    cat >> "$f" <<YAML
    CHANGE-0002:
      human_time_minutes:
        intake: null
        reviews: null
      agent_runs:
        - role: Planning
          model_id: claude-other
          started_utc: 2026-07-15T09:00:00Z
          ended_utc: 2026-07-15T09:01:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null
YAML
  fi
  cat >> "$f" <<YAML

updated_at_utc: 2026-07-15T11:30:00Z
YAML
}

write_ticks() {  # $1 file — 90s + 30s review pauses -> ceil(120/60) = 2 min
  cat > "$1" <<'JSONL'
{"type":"tick","tick":1,"role":"Planning","scope":"CHANGE-0001","started_utc":"2026-07-15T10:00:00Z"}
{"type":"human_resume","resumed_utc":"2026-07-15T10:30:00Z","resumed_epoch":1786790000,"review_duration_seconds":90}
{"type":"human_resume","resumed_utc":"2026-07-15T11:00:00Z","resumed_epoch":1786792000,"review_duration_seconds":30}
JSONL
}

write_golden_doc() {  # $1 repo root
  cat > "$1/docs/issues/CHANGE-0001-golden.md" <<'MD'
# Golden fixture item

Body.
MD
}

# --- metrics-flush-strands-completed-refs (--sweep) fixtures -------------------

# write_sweep_state <file> <REF:STATUS...> — a lean sweep-focused STATE
# fixture (no golden-header comment block — that's TEST-010's concern, not
# ours). last_validation is not_run/ref_id null and code_review.required is
# false so the DEFAULT gate never fires for ANY of these refs — isolates the
# sweep gate from the default gate entirely, one test at a time.
# Each REF gets one active_work_items entry at STATUS (done|in_progress) plus
# a metrics.work_items entry with exactly one agent_run (runs.length>0, so
# only the provenance gate — not the "no agent_runs" skip — is under test).
write_sweep_state() {
  local f="$1"
  shift
  {
    echo "project_status: active"
    echo "current_focus:"
    echo "  type: none"
    echo "  ref_id: null"
    echo "  primary_path: null"
    echo "active_work_items:"
    local spec ref status
    for spec in "$@"; do
      ref="${spec%%:*}"
      status="${spec##*:}"
      echo "  - ref_id: $ref"
      echo "    status: $status"
      echo "    phase: validation"
      echo "    primary_path: docs/issues/${ref}.md"
    done
    cat <<'YAML'
implementation_strategy:
  selected: tdd
  source: null
  rationale: null
worktree:
  recommendation: not_needed
  user_decision: undecided
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
  status: not_run
  run_at_utc: null
  ref_id: null
  evidence_paths: []
  notes: null
human_input:
  required: false
  question: null
locks:
  implementation: true
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
YAML
    for spec in "$@"; do
      ref="${spec%%:*}"
      cat <<REFYAML
    $ref:
      human_time_minutes:
        intake: null
        reviews: null
      agent_runs:
        - role: Implementation
          model_id: claude-sonnet-5
          started_utc: 2026-07-15T09:00:00Z
          ended_utc: 2026-07-15T09:10:00Z
          duration_seconds: 600
          tokens_in: 1000000
          tokens_out: 100000
          cost_usd: null
REFYAML
    done
    echo ""
    echo "updated_at_utc: 2026-07-15T11:30:00Z"
  } > "$f"
}

write_closed_event() {  # $1 file $2 ref $3 ts — append one work_item_closed line
  printf '{"v":1,"ts":"%s","actor":"test","event":"work_item_closed","ref":"%s","payload":{}}\n' "$3" "$2" >> "$1"
}

# --- retire-stranded-nonworkitem-metric (--retire) fixtures -------------------
# write_retire_state <file> <ref> [vstatus=not_run] [vref=null] — a minimal
# STATE with EXACTLY one metrics.work_items entry <ref> carrying two agent_runs
# (Planning 120s, Implementation 600s) and NO active_work_items entry for it
# (the stranded, never-a-work-item shape the retire mode targets). Defaults:
# last_validation not_run / ref_id null and code_review not_run/false, so the
# DEFAULT flush gate never names <ref> — this isolates the retire guards. Pass
# vstatus=pass vref=<ref> to make <ref> flushable-by-the-default-predicate
# (the fail-closed guard must then REFUSE the retire).
write_retire_state() {
  local f="$1" ref="$2" vstatus="${3:-not_run}" vref="${4:-null}"
  cat > "$f" <<YAML
project_status: active
current_focus:
  type: none
  ref_id: null
  primary_path: null
active_work_items: []
implementation_strategy:
  selected: tdd
  source: null
  rationale: null
worktree:
  recommendation: not_needed
  user_decision: undecided
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
  status: $vstatus
  run_at_utc: null
  ref_id: $vref
  evidence_paths: []
  notes: null
human_input:
  required: false
  question: null
locks:
  implementation: true
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
    $ref:
      human_time_minutes:
        intake: null
        reviews: null
      agent_runs:
        - role: Planning
          model_id: claude-sonnet-5
          started_utc: 2026-07-15T10:00:00Z
          ended_utc: 2026-07-15T10:02:00Z
          duration_seconds: 120
          tokens_in: null
          tokens_out: null
          cost_usd: null
        - role: Implementation
          model_id: claude-opus-4-8
          started_utc: 2026-07-15T10:02:00Z
          ended_utc: 2026-07-15T10:12:00Z
          duration_seconds: 600
          tokens_in: null
          tokens_out: null
          cost_usd: null

updated_at_utc: 2026-07-15T11:30:00Z
YAML
}

# --- SPEC-0054 seam fixtures (flush no longer emits close events; real audit +
# close-work-item.mjs cross-tool seam) -------------------------------------------

# write_frontmatter_doc <path> <id> <type> <status> — a real frontmatter'd doc
# so close-work-item.mjs (frontmatter id resolution) and docs-audit.mjs (real
# drift heuristics) both see a proper doc, not the header-only golden fixture.
write_frontmatter_doc() {
  local f="$1" id="$2" type="$3" status="$4"
  mkdir -p "$(dirname "$f")"
  cat > "$f" <<EOF
---
id: $id
type: $type
status: $status
links:
  pr: []
  commits: []
---

# Fixture doc $id

Body.
EOF
}

write_audit_config() {  # $1 file — report-only audit config (no enforced hardFail noise)
  cat > "$1" <<'YAML'
legacy_until_date: 2020-01-01
stale_after_days: 90
scan_exclude: []
backlog_globs: []
close_gate: report-only
doc_number_guard: report-only
protected_paths_l3: []
YAML
}

# mk_seam_repo <name> — mk_repo PLUS a real git repo + docs-audit config +
# empty EVENTS.jsonl, for tests that cross the flush <-> docs-audit <->
# close-work-item.mjs seam (SEAM-1, SPEC-0054).  Echoes dir.
mk_seam_repo() {
  local d
  d="$(mk_repo "$1")"
  write_audit_config "$d/docs/ai/docs-audit.yaml"
  : > "$d/docs/ai/EVENTS.jsonl"
  git init -q "$d"
  git -C "$d" config user.email test@example.com
  git -C "$d" config user.name "AAI Test"
  printf '%s' "$d"
}

# event_count <events-file> <event-name> <ref> — count of matching JSONL lines.
event_count() {
  local f="$1" ev="$2" ref="$3"
  [[ -f "$f" ]] || { echo 0; return; }
  grep -cF "\"event\":\"$ev\",\"ref\":\"$ref\"" "$f" || true
}

# run_flush <root> [extra flags...] — combined output in $OUT, exit in $EC.
OUT=""
EC=0
run_flush() {
  local d="$1"
  shift
  OUT="$d/flush-out.log"
  EC=0
  (cd "$PROJECT_ROOT" && node .aai/scripts/metrics-flush.mjs \
    --state "$d/docs/ai/STATE.yaml" \
    --metrics "$d/docs/ai/METRICS.jsonl" \
    --ticks "$d/docs/ai/LOOP_TICKS.jsonl" \
    --pricing "$d/PRICING.yaml" \
    --events "$d/docs/ai/EVENTS.jsonl" \
    --now "$NOW_PIN" "$@" > "$OUT" 2>&1) || EC=$?
}

ledger_lines() {  # non-comment, non-blank ledger line count
  grep -cv -e '^#' -e '^$' "$1/docs/ai/METRICS.jsonl" || true
}

# --- TEST-006: flush happy-path golden -----------------------------------------

test_006_flush_golden() {
  log_info "Test: happy-path flush appends the EXACT golden ledger line (TEST-006)..."
  local d
  d="$(mk_repo t6)"
  write_flush_state "$d/docs/ai/STATE.yaml" single
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  write_golden_doc "$d"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "flush must exit 0 (got $EC): $(cat "$OUT")"
  [[ "$(ledger_lines "$d")" == 1 ]] || log_fail "exactly one ledger line must be appended"
  grep -v -e '^#' -e '^$' "$d/docs/ai/METRICS.jsonl" > "$d/got.jsonl"
  cat > "$d/want.jsonl" <<'GOLDEN'
{"date_utc":"2026-07-15","ref_id":"CHANGE-0001","title":"Golden fixture item","human_time_minutes":{"intake":null,"reviews":2},"agent_runs":[{"role":"Planning","model_id":"claude-opus-4-8[1m]","started_utc":"2026-07-15T10:00:00Z","ended_utc":"2026-07-15T10:02:00Z","duration_seconds":120,"tokens_in":1000000,"tokens_out":100000,"cost_usd":7.5,"cost_basis":"decomposed","harness":null,"tokens_total":null,"verdict":null,"verdict_basis":"none"},{"role":"Implementation","model_id":"sonnet-latest","started_utc":"2026-07-15T10:02:00Z","ended_utc":"2026-07-15T10:12:00Z","duration_seconds":600,"tokens_in":2000000,"tokens_out":200000,"cost_usd":9,"cost_basis":"decomposed","harness":null,"tokens_total":null,"verdict":null,"verdict_basis":"none"},{"role":"Validation","model_id":"claude-sonnet-5-20260101","started_utc":"2026-07-15T10:12:00Z","ended_utc":"2026-07-15T10:13:40Z","duration_seconds":100,"tokens_in":1000000,"tokens_out":1000000,"cost_usd":18,"cost_basis":"decomposed","harness":null,"tokens_total":null,"verdict":null,"verdict_basis":"note"},{"role":"Code Review","model_id":"mystery-9000","started_utc":"2026-07-15T10:13:40Z","ended_utc":"2026-07-15T10:14:40Z","duration_seconds":60,"tokens_in":10,"tokens_out":10,"cost_usd":null,"cost_basis":"none","harness":null,"tokens_total":null,"verdict":null,"verdict_basis":"note"}],"totals":{"human_time_minutes":2,"agent_duration_seconds":880,"total_cost_usd":null,"cost_basis":"mixed"},"strategy":"tdd","reliability":{"validation_fails":0,"review_fails":0,"remediation_runs":0,"first_pass_clean":true,"basis":"note"},"verdict_basis":"global-block","verdict":"PASS"}
GOLDEN
  diff -u "$d/want.jsonl" "$d/got.jsonl" > "$d/golden.diff" 2>&1 \
    || log_fail "ledger line must byte-equal the golden (strip-[1m] 7.5, alias 9, longest-prefix 18, unknown null): $(cat "$d/golden.diff")"
  # The ledger entry survives a JSON round-trip (no Date objects ever).
  node -e '
    const l = require("fs").readFileSync(process.argv[1], "utf8").trim();
    const o = JSON.parse(l);
    if (JSON.stringify(o) !== l) { console.error("round-trip mismatch"); process.exit(1); }
  ' "$d/got.jsonl" || log_fail "entry must deep-equal its own JSON round-trip"
  grep -qF "CHANGE-0001" "$OUT" || log_fail "report must name the flushed ref: $(cat "$OUT")"
  log_pass "Golden ledger line exact: [1m]-strip, alias, longest-prefix, unknown->null, clean strategy+reliability (TEST-006)"
}

# --- TEST-007: timing fidelity ---------------------------------------------------

test_007_timing_fidelity() {
  log_info "Test: bad/mismatched/future timestamps -> duration null, NEVER estimated (TEST-007)..."
  local d
  d="$(mk_repo t7)"
  write_flush_state "$d/docs/ai/STATE.yaml" single
  # Rewrite the runs with timing defects: (1) missing ended, (2) unparseable
  # started, (3) duration != delta by >1s, (4) delta ok within ±1s (KEPT),
  # (5)... future stamps handled via run 1 replacement below.
  node -e '
    const fs = require("fs");
    const p = process.argv[1];
    let s = fs.readFileSync(p, "utf8");
    // run1 (Planning): ended_utc far-future -> null duration
    s = s.replace("          started_utc: 2026-07-15T10:00:00Z\n          ended_utc: 2026-07-15T10:02:00Z\n          duration_seconds: 120",
                  "          started_utc: 2026-07-15T10:00:00Z\n          ended_utc: 2027-01-01T00:00:00Z\n          duration_seconds: 120");
    // run2 (Implementation): unparseable started -> null
    s = s.replace("          started_utc: 2026-07-15T10:02:00Z\n          ended_utc: 2026-07-15T10:12:00Z\n          duration_seconds: 600",
                  "          started_utc: not-a-timestamp\n          ended_utc: 2026-07-15T10:12:00Z\n          duration_seconds: 600");
    // run3 (Validation): duration 100 but delta is 100 -> make duration 250 (mismatch >1s)
    s = s.replace("          duration_seconds: 100", "          duration_seconds: 250");
    // run4 (Code Review): duration 61 vs delta 60 -> within ±1s tolerance, KEPT
    s = s.replace("          duration_seconds: 60\n          tokens_in: 10", "          duration_seconds: 61\n          tokens_in: 10");
    fs.writeFileSync(p, s);
  ' "$d/docs/ai/STATE.yaml"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "flush must exit 0 (got $EC): $(cat "$OUT")"
  grep -v -e '^#' -e '^$' "$d/docs/ai/METRICS.jsonl" > "$d/got.jsonl"
  node -e '
    const o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8").trim());
    const durs = o.agent_runs.map(r => r.duration_seconds);
    const want = [null, null, null, 61];
    if (JSON.stringify(durs) !== JSON.stringify(want)) {
      console.error("durations: got " + JSON.stringify(durs) + " want " + JSON.stringify(want)); process.exit(1);
    }
    if (o.totals.agent_duration_seconds !== 61) { console.error("totals must sum only the trusted duration (61), got " + o.totals.agent_duration_seconds); process.exit(1); }
  ' "$d/got.jsonl" || log_fail "timing fidelity durations wrong: $(cat "$d/got.jsonl")"
  log_pass "Future/unparseable/mismatched timing -> null; ±1s tolerance kept; sums trust only valid runs (TEST-007)"
}

# --- TEST-008: criteria negatives ------------------------------------------------

test_008_criteria_negatives() {
  log_info "Test: FAIL verdict / review missing / zero runs / already-in-ledger all skip with named reasons (TEST-008)..."
  local d
  # (a) validation FAIL -> skipped.
  d="$(mk_repo t8a)"
  write_flush_state "$d/docs/ai/STATE.yaml" single fail pass
  cp "$d/docs/ai/METRICS.jsonl" "$d/ledger.before"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "(a) nothing-to-flush must exit 0 (got $EC): $(cat "$OUT")"
  cmp -s "$d/docs/ai/METRICS.jsonl" "$d/ledger.before" || log_fail "(a) ledger must stay byte-identical"
  grep -qiE "CHANGE-0001.*(fail|verdict|PASS)" "$OUT" || log_fail "(a) report must name the verdict reason: $(cat "$OUT")"
  grep -qiF "nothing to flush" "$OUT" || log_fail "(a) report must say Nothing to flush: $(cat "$OUT")"

  # (b) review required + not_run -> skipped.
  d="$(mk_repo t8b)"
  write_flush_state "$d/docs/ai/STATE.yaml" single pass not_run
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "(b) must exit 0 (got $EC): $(cat "$OUT")"
  [[ "$(ledger_lines "$d")" == 0 ]] || log_fail "(b) nothing may be appended"
  grep -qiE "CHANGE-0001.*review" "$OUT" || log_fail "(b) report must name the review reason: $(cat "$OUT")"

  # (c) zero agent_runs -> skipped.
  d="$(mk_repo t8c)"
  write_flush_state "$d/docs/ai/STATE.yaml" single
  node -e '
    const fs = require("fs"); const p = process.argv[1];
    let s = fs.readFileSync(p, "utf8");
    // Replace the whole agent_runs block with an inline empty list.
    s = s.replace(/      agent_runs:\n(?: {8}.*\n| {10}.*\n)*/m, "      agent_runs: []\n");
    fs.writeFileSync(p, s);
  ' "$d/docs/ai/STATE.yaml"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "(c) must exit 0 (got $EC): $(cat "$OUT")"
  [[ "$(ledger_lines "$d")" == 0 ]] || log_fail "(c) nothing may be appended"
  grep -qiE "CHANGE-0001.*(agent_run|no runs)" "$OUT" || log_fail "(c) report must name the zero-runs reason: $(cat "$OUT")"

  # (d) already in ledger AND absent from STATE -> nothing to flush, no dup.
  d="$(mk_repo t8d)"
  write_flush_state "$d/docs/ai/STATE.yaml" single pass pass
  node -e '
    const fs = require("fs"); const p = process.argv[1];
    let s = fs.readFileSync(p, "utf8");
    s = s.replace(/metrics:\n(?:  .*\n| {4,}.*\n|\n)*?\nupdated_at_utc:/m, "\nupdated_at_utc:");
    fs.writeFileSync(p, s);
  ' "$d/docs/ai/STATE.yaml"
  printf '{"date_utc":"2026-07-01","ref_id":"CHANGE-0001","agent_runs":[]}\n' >> "$d/docs/ai/METRICS.jsonl"
  cp "$d/docs/ai/METRICS.jsonl" "$d/ledger.before"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "(d) must exit 0 (got $EC): $(cat "$OUT")"
  cmp -s "$d/docs/ai/METRICS.jsonl" "$d/ledger.before" || log_fail "(d) ledger must stay byte-identical (no duplicate line)"
  grep -qiF "nothing to flush" "$OUT" || log_fail "(d) report must say Nothing to flush: $(cat "$OUT")"
  log_pass "Criteria negatives all skip with named reasons; ledger untouched (TEST-008)"
}

# --- TEST-009: null-token WARNING lines -------------------------------------------

test_009_null_token_warnings() {
  log_info "Test: one VISIBLE WARNING line per null-token run, never aggregated (TEST-009)..."
  local d n
  d="$(mk_repo t9)"
  write_flush_state "$d/docs/ai/STATE.yaml" single
  node -e '
    const fs = require("fs"); const p = process.argv[1];
    let s = fs.readFileSync(p, "utf8");
    // Null the tokens of runs 1+2 (Planning, Implementation).
    s = s.replace("          tokens_in: 1000000\n          tokens_out: 100000", "          tokens_in: null\n          tokens_out: null");
    s = s.replace("          tokens_in: 2000000\n          tokens_out: 200000", "          tokens_in: null\n          tokens_out: null");
    fs.writeFileSync(p, s);
  ' "$d/docs/ai/STATE.yaml"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "flush must exit 0 (got $EC): $(cat "$OUT")"
  n="$(grep -c 'cost unattributable — tokens not recorded' "$OUT" || true)"
  [[ "$n" == 2 ]] || log_fail "exactly TWO warning lines expected, one per null-token run (got $n): $(cat "$OUT")"
  grep -qE 'WARNING CHANGE-0001 run Planning \(claude-opus-4-8\[1m\]\): cost unattributable' "$OUT" \
    || log_fail "warning must name ref, role and model: $(cat "$OUT")"
  grep -qE 'WARNING CHANGE-0001 run Implementation \(sonnet-latest\): cost unattributable' "$OUT" \
    || log_fail "second warning must name its own run: $(cat "$OUT")"
  node -e '
    const lines = require("fs").readFileSync(process.argv[1], "utf8").split("\n").filter(l => l.trim() && !l.startsWith("#"));
    const o = JSON.parse(lines[0]);
    if (o.agent_runs[0].cost_usd !== null || o.agent_runs[1].cost_usd !== null) { console.error("null-token runs must keep cost null"); process.exit(1); }
    if (o.totals.total_cost_usd !== null) { console.error("totals cost must be null when any run cost is null"); process.exit(1); }
  ' "$d/docs/ai/METRICS.jsonl" || log_fail "null-token cost handling wrong"
  log_pass "Per-run WARNING lines visible and un-aggregated; costs stay null (TEST-009)"
}

# --- TEST-010: line-surgical header preservation ----------------------------------

test_010_header_preservation() {
  log_info "Test: commented schema header + untouched blocks byte-identical after flush (TEST-010)..."
  local d
  d="$(mk_repo t10)"
  write_flush_state "$d/docs/ai/STATE.yaml" single
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  cp "$d/docs/ai/STATE.yaml" "$d/state.before"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "flush must exit 0 (got $EC): $(cat "$OUT")"
  # (a) EVERY comment line survives byte-identical, in order (the commented
  # schema header is what the manual yaml.dump flush destroyed).
  grep '^#' "$d/state.before" > "$d/comments.before" || true
  grep '^#' "$d/docs/ai/STATE.yaml" > "$d/comments.after" || true
  diff -u "$d/comments.before" "$d/comments.after" > "$d/comments.diff" 2>&1 \
    || log_fail "comment lines must survive byte-identical (yaml.dump-style rewrite detected): $(cat "$d/comments.diff")"
  # (b) untouched top-level blocks byte-identical: project_status, human_input,
  # orchestration, tdd_cycle.
  local key
  for key in human_input orchestration tdd_cycle; do
    sed -n "/^${key}:/,/^[a-z_]*:/p" "$d/state.before" | sed '$d' > "$d/${key}.before"
    sed -n "/^${key}:/,/^[a-z_]*:/p" "$d/docs/ai/STATE.yaml" | sed '$d' > "$d/${key}.after"
    cmp -s "$d/${key}.before" "$d/${key}.after" \
      || log_fail "untouched block '${key}' must stay byte-identical: $(diff "$d/${key}.before" "$d/${key}.after")"
  done
  grep -qF "project_status: active" "$d/docs/ai/STATE.yaml" || log_fail "project_status line must survive"
  # (c) the orchestration-mode suite's real-STATE schema-header greps still
  # pass on the flushed file shape (the regression a manual flush caused).
  grep -qiE "orchestration\.mode:.*auto.*single.*parallel" "$d/docs/ai/STATE.yaml" \
    || log_fail "schema header must still document orchestration.mode (orchestration-mode suite grep)"
  grep -qiE "orchestration\.k" "$d/docs/ai/STATE.yaml" || log_fail "schema header must still document orchestration.k"
  grep -qiE "orchestration\.groups" "$d/docs/ai/STATE.yaml" || log_fail "schema header must still document orchestration.groups"
  grep -qiE "absent.*auto" "$d/docs/ai/STATE.yaml" || log_fail "schema header must keep the absent==auto note"
  # (d) check-state green on the flushed file.
  (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs "$d/docs/ai/STATE.yaml" > "$d/ck.log" 2>&1) \
    || log_fail "check-state must pass after flush: $(cat "$d/ck.log")"
  # (e) no whole-file YAML serialization anywhere in the flush script.
  grep -qiE 'yaml\.dump|safeDump|js-yaml' "$FLUSH" && log_fail "metrics-flush.mjs must not use a YAML serializer"
  log_pass "Line-surgical flush: header + untouched blocks byte-identical, check-state green (TEST-010)"
}

# --- TEST-011: partial-flush H5 ----------------------------------------------------

test_011_partial_flush() {
  log_info "Test: partial flush resets verdict blocks with flush provenance; other items untouched (TEST-011)..."
  local d
  d="$(mk_repo t11)"
  write_flush_state "$d/docs/ai/STATE.yaml" two
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  # An old report that FULL cleanup would prune — partial flush must keep it.
  echo old > "$d/docs/ai/reports/validation-old.md"
  touch -t 202601010000 "$d/docs/ai/reports/validation-old.md"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "flush must exit 0 (got $EC): $(cat "$OUT")"
  [[ "$(ledger_lines "$d")" == 1 ]] || log_fail "only CHANGE-0001 may flush"
  local st="$d/docs/ai/STATE.yaml"
  # CHANGE-0001 gone from metrics + active_work_items; CHANGE-0002 untouched.
  grep -qE '^ {4}CHANGE-0001:' "$st" && log_fail "flushed metrics entry must be removed"
  grep -qE '^ {4}CHANGE-0002:' "$st" || log_fail "other metrics entries must stay"
  grep -qF "claude-other" "$st" || log_fail "other item's agent_runs must stay byte-present"
  grep -qF "ref_id: CHANGE-0002" "$st" || log_fail "other active_work_items entry must stay"
  sed -n '/^active_work_items:/,/^[a-z_]*:/p' "$st" | grep -qF "ref_id: CHANGE-0001" \
    && log_fail "flushed done item must leave active_work_items"
  # Verdict blocks reset with FLUSH provenance (never the remediation marker).
  sed -n '/^last_validation:/,/^[a-z_]*:/p' "$st" > "$d/lv.block"
  grep -qE '^ {2}status: not_run$' "$d/lv.block" || log_fail "last_validation must reset to not_run"
  grep -qF "reset after flush of CHANGE-0001" "$d/lv.block" || log_fail "reset note must carry flush provenance"
  grep -qF "pending independent re-validation" "$d/lv.block" && log_fail "reset must NOT use reset-block's remediation marker"
  grep -qE '^ {2}ref_id: null$' "$d/lv.block" || log_fail "leaked last_validation.ref_id must be nulled"
  grep -qE '^ {2}evidence_paths: \[\]$' "$d/lv.block" || log_fail "leaked evidence_paths must be emptied"
  sed -n '/^code_review:/,/^[a-z_]*:/p' "$st" > "$d/cr.block"
  grep -qE '^ {2}status: not_run$' "$d/cr.block" || log_fail "code_review must reset to not_run"
  grep -qE '^ {2}required: false$' "$d/cr.block" || log_fail "code_review.required must reset to false"
  # telemetry-fields-not-prose D8: scope/base_ref/head_ref are an INPUT to a
  # LATER step, not verdict state — a partial reset PRESERVES them and stamps
  # scope_ref_id naming the flushed ref instead of nulling them out.
  grep -qF "fixture review scope" "$d/cr.block" || log_fail "D8: code_review.scope must be PRESERVED (not nulled) on a partial reset"
  grep -qE '^ {2}base_ref: main$' "$d/cr.block" || log_fail "D8: code_review.base_ref must be PRESERVED (not nulled) on a partial reset"
  grep -qE '^ {2}head_ref: null$' "$d/cr.block" || log_fail "code_review.head_ref (already null in the fixture) stays null"
  grep -qE '^ {2}scope_ref_id: CHANGE-0001$' "$d/cr.block" || log_fail "D8: code_review.scope_ref_id must name the flushed ref"
  grep -qE '^ {2}report_paths: \[\]$' "$d/cr.block" || log_fail "leaked report_paths must be emptied"
  # NOT a full reset: strategy untouched, ticks + old report survive.
  grep -qE '^ {2}selected: tdd$' "$st" || log_fail "implementation_strategy must stay untouched on partial flush"
  [[ -f "$d/docs/ai/LOOP_TICKS.jsonl" ]] || log_fail "LOOP_TICKS must survive a partial flush"
  [[ -f "$d/docs/ai/reports/validation-old.md" ]] || log_fail "ephemeral cleanup must be SKIPPED when work remains"
  (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs "$st" > "$d/ck.log" 2>&1) \
    || log_fail "check-state must pass after partial flush: $(cat "$d/ck.log")"
  log_pass "Partial-flush H5: verdict blocks reset with flush provenance, other work untouched, no cleanup (TEST-011)"
}

# --- TEST-012: full reset + ephemeral cleanup ---------------------------------------

test_012_full_reset_cleanup() {
  log_info "Test: full reset defaults + ephemeral cleanup honoring the protected set (TEST-012)..."
  local d
  d="$(mk_repo t12)"
  write_flush_state "$d/docs/ai/STATE.yaml" single
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  # Ephemeral candidates.
  echo old > "$d/docs/ai/reports/validation-old.md"
  touch -t 202601010000 "$d/docs/ai/reports/validation-old.md"
  echo new > "$d/docs/ai/reports/validation-new.md"
  echo latest > "$d/docs/ai/reports/LATEST.md"
  touch -t 202601010000 "$d/docs/ai/reports/LATEST.md"
  mkdir -p "$d/docs/ai/reports/screenshots/oldrun"
  echo shot > "$d/docs/ai/reports/screenshots/oldrun/a.png"
  touch -t 202601010000 "$d/docs/ai/reports/screenshots/oldrun/a.png" "$d/docs/ai/reports/screenshots/oldrun"
  echo oldtdd > "$d/docs/ai/tdd/red-old.log"
  touch -t 202607010000 "$d/docs/ai/tdd/red-old.log"
  echo newtdd > "$d/docs/ai/tdd/green-new.log"
  # TRACKED dotfile keepers (gitignore carve-outs depend on them) — even when
  # older than every prune window they must survive (ISSUE-0007 bundled nit).
  : > "$d/docs/ai/tdd/.gitkeep"
  touch -t 202601010000 "$d/docs/ai/tdd/.gitkeep"
  : > "$d/docs/ai/reports/.gitkeep"
  touch -t 202601010000 "$d/docs/ai/reports/.gitkeep"
  # Protected set.
  echo '{"d":1}' > "$d/docs/ai/decisions.jsonl"
  mkdir -p "$d/docs/ai/published"
  echo pub > "$d/docs/ai/published/page.html"
  # NON-BLOCKING-A (review-telemetry-fields-not-prose-20260913T105322Z): a
  # scope_ref_id stamped by an OLDER flush must not survive a FULL reset.
  awk '/^code_review:/{print; print "  scope_ref_id: CHANGE-9999"; next} {print}' \
    "$d/docs/ai/STATE.yaml" > "$d/docs/ai/STATE.yaml.tmp" && mv "$d/docs/ai/STATE.yaml.tmp" "$d/docs/ai/STATE.yaml"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "flush must exit 0 (got $EC): $(cat "$OUT")"
  local st="$d/docs/ai/STATE.yaml"
  # Full reset defaults (STATE_FALLBACK.md flush-reset list).
  sed -n '/^last_validation:/,/^[a-z_]*:/p' "$st" | grep -qE '^ {2}status: not_run$' || log_fail "last_validation.status must reset"
  sed -n '/^last_validation:/,/^[a-z_]*:/p' "$st" | grep -qE '^ {2}run_at_utc: null$' || log_fail "run_at_utc must null on full reset"
  sed -n '/^last_validation:/,/^[a-z_]*:/p' "$st" | grep -qE '^ {2}ref_id: null$' || log_fail "last_validation.ref_id must null on full reset (STATE_FALLBACK parity)"
  sed -n '/^implementation_strategy:/,/^[a-z_]*:/p' "$st" | grep -qE '^ {2}selected: undecided$' || log_fail "strategy must reset to undecided"
  sed -n '/^worktree:/,/^[a-z_]*:/p' "$st" | grep -qE '^ {2}recommendation: not_needed$' || log_fail "worktree.recommendation must reset"
  sed -n '/^worktree:/,/^[a-z_]*:/p' "$st" | grep -qE '^ {2}user_decision: undecided$' || log_fail "worktree.user_decision must reset"
  sed -n '/^code_review:/,/^[a-z_]*:/p' "$st" | grep -qE '^ {2}required: false$' || log_fail "code_review.required must reset"
  sed -n '/^code_review:/,/^[a-z_]*:/p' "$st" | grep -qE '^ {2}scope_ref_id: null$' || log_fail "code_review.scope_ref_id (stamped by an older flush) must be cleared to null on a full reset (NON-BLOCKING-A)"
  sed -n '/^current_focus:/,/^[a-z_]*:/p' "$st" | grep -qE '^ {2}type: none$' || log_fail "focus type must reset to none"
  sed -n '/^current_focus:/,/^[a-z_]*:/p' "$st" | grep -qE '^ {2}ref_id: null$' || log_fail "focus ref must null"
  sed -n '/^locks:/,/^[a-z_]*:/p' "$st" | grep -qE '^ {2}implementation: true$' || log_fail "locks.implementation must stay true"
  grep -qE '^metrics:' "$st" && log_fail "emptied metrics block must be removed entirely"
  grep -qE '^active_work_items: \[\]$' "$st" || log_fail "emptied active_work_items must become []"
  # Ephemeral cleanup.
  [[ ! -f "$d/docs/ai/LOOP_TICKS.jsonl" ]] || log_fail "LOOP_TICKS.jsonl must be deleted on full reset"
  [[ ! -f "$d/docs/ai/reports/validation-old.md" ]] || log_fail ">30d validation report must be pruned"
  [[ -f "$d/docs/ai/reports/validation-new.md" ]] || log_fail "recent validation report must survive"
  [[ -f "$d/docs/ai/reports/LATEST.md" ]] || log_fail "LATEST.md must ALWAYS survive"
  [[ ! -d "$d/docs/ai/reports/screenshots/oldrun" ]] || log_fail ">30d screenshots dir must be pruned"
  [[ ! -f "$d/docs/ai/tdd/red-old.log" ]] || log_fail ">7d tdd evidence must be pruned"
  [[ -f "$d/docs/ai/tdd/green-new.log" ]] || log_fail "recent tdd evidence must survive"
  # Dotfile keepers survive every sweep regardless of age (ISSUE-0007 nit a).
  [[ -f "$d/docs/ai/tdd/.gitkeep" ]] || log_fail "TRACKED docs/ai/tdd/.gitkeep must survive the >7d tdd sweep (dotfile keeper protection)"
  [[ -f "$d/docs/ai/reports/.gitkeep" ]] || log_fail "docs/ai/reports/.gitkeep must survive the reports sweep"
  # Protected set NEVER deleted.
  [[ -f "$d/docs/ai/METRICS.jsonl" ]] || log_fail "METRICS.jsonl is protected"
  [[ -f "$d/docs/ai/decisions.jsonl" ]] || log_fail "decisions.jsonl is protected"
  [[ -f "$st" ]] || log_fail "STATE.yaml is protected"
  [[ -f "$d/docs/ai/published/page.html" ]] || log_fail "published/ is protected"
  # SPEC-0054 Option A: flush no longer owns the close lifecycle
  # (close-work-item.mjs does) — it must not touch EVENTS.jsonl at all, even
  # on a full reset (RED pre-fix: doc_lifecycle + work_item_closed were
  # emitted here, best-effort).
  [[ ! -f "$d/docs/ai/EVENTS.jsonl" ]] \
    || log_fail "flush must never create/write EVENTS.jsonl — close-work-item.mjs owns the close lifecycle: $(cat "$d/docs/ai/EVENTS.jsonl")"
  (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs "$st" > "$d/ck.log" 2>&1) \
    || log_fail "check-state must pass after full reset: $(cat "$d/ck.log")"
  log_pass "Full reset defaults + cleanup: ticks deleted, >30d pruned, LATEST + protected set kept, NO close events (flush is metrics-ledger only) (TEST-012)"
}

# --- TEST-013: transactionality ------------------------------------------------------

test_013_transactionality() {
  log_info "Test: crash between ledger append and STATE commit -> original preserved; resume is cleanup-only; --dry-run writes nothing (TEST-013)..."
  local d
  d="$(mk_repo t13)"
  write_flush_state "$d/docs/ai/STATE.yaml" single
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  cp "$d/docs/ai/STATE.yaml" "$d/state.before"

  # (a) --dry-run first: prints the full plan JSON, writes NOTHING.
  run_flush "$d" --dry-run
  [[ "$EC" == 0 ]] || log_fail "(a) --dry-run must exit 0 (got $EC): $(cat "$OUT")"
  node -e '
    const raw = require("fs").readFileSync(process.argv[1], "utf8");
    const start = raw.indexOf("{");
    const o = JSON.parse(raw.slice(start));
    if (!o.dry_run) { console.error("plan JSON must carry dry_run: true"); process.exit(1); }
    if (!Array.isArray(o.flush) || o.flush[0] !== "CHANGE-0001") { console.error("plan must name the flushable ref"); process.exit(1); }
  ' "$OUT" || log_fail "(a) --dry-run must print the plan JSON: $(cat "$OUT")"
  cmp -s "$d/docs/ai/STATE.yaml" "$d/state.before" || log_fail "(a) --dry-run must not touch STATE"
  [[ "$(ledger_lines "$d")" == 0 ]] || log_fail "(a) --dry-run must not append to the ledger"
  [[ -f "$d/docs/ai/LOOP_TICKS.jsonl" ]] || log_fail "(a) --dry-run must not clean up"

  # (b) injected crash AFTER the ledger append, BEFORE the STATE commit.
  EC=0
  (cd "$PROJECT_ROOT" && AAI_FLUSH_INJECT_CRASH=after-ledger node .aai/scripts/metrics-flush.mjs \
    --state "$d/docs/ai/STATE.yaml" --metrics "$d/docs/ai/METRICS.jsonl" \
    --ticks "$d/docs/ai/LOOP_TICKS.jsonl" --pricing "$d/PRICING.yaml" \
    --events "$d/docs/ai/EVENTS.jsonl" --now "$NOW_PIN" > "$d/crash.log" 2>&1) || EC=$?
  [[ "$EC" != 0 ]] || log_fail "(b) injected crash must not exit 0"
  [[ "$(ledger_lines "$d")" == 1 ]] || log_fail "(b) the ledger line must already be durable (ledger-before-reset)"
  cmp -s "$d/docs/ai/STATE.yaml" "$d/state.before" || log_fail "(b) STATE must stay byte-identical after the crash (original preserved)"

  # (c) resume: ref already in ledger + still in STATE -> cleanup-only, NO
  # duplicate ledger line.
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "(c) resume must exit 0 (got $EC): $(cat "$OUT")"
  [[ "$(ledger_lines "$d")" == 1 ]] || log_fail "(c) resume must NOT append a second ledger line"
  grep -qE '^ {4}CHANGE-0001:' "$d/docs/ai/STATE.yaml" && log_fail "(c) resume must complete the STATE cleanup"
  grep -qiE "resume|already in (the )?ledger" "$OUT" || log_fail "(c) report must say it resumed an interrupted flush: $(cat "$OUT")"
  (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs "$d/docs/ai/STATE.yaml" > "$d/ck.log" 2>&1) \
    || log_fail "(c) check-state must pass after resume: $(cat "$d/ck.log")"
  log_pass "Ledger-before-reset ordering, crash-preserved STATE, idempotent cleanup-only resume, dry-run inert (TEST-013)"
}

# --- TEST-014: report golden -----------------------------------------------------------

test_014_report_golden() {
  log_info "Test: metrics-report output byte-deterministic and equal to the golden (TEST-014)..."
  local d="$TEST_DIR/t14"
  mkdir -p "$d"
  cat > "$d/PRICING.yaml" <<'YAML'
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
  model-b:
    input_usd_per_m: 5.00
    output_usd_per_m: 25.00
  unknown:
    input_usd_per_m: null
    output_usd_per_m: null
YAML
  cat > "$d/METRICS.jsonl" <<'JSONL'
# ledger comment
{"date_utc":"2026-07-01","ref_id":"AAA-0001","title":"First","human_time_minutes":{"intake":5,"reviews":5},"agent_runs":[{"role":"Implementation","model_id":"model-b","started_utc":"2026-07-01T10:00:00Z","ended_utc":"2026-07-01T10:10:00Z","duration_seconds":600,"tokens_in":1000000,"tokens_out":100000,"cost_usd":null}],"totals":{"human_time_minutes":10,"agent_duration_seconds":600,"total_cost_usd":null},"verdict":"PASS"}
{"date_utc":"2026-07-02","ref_id":"AAA-0002","title":"Second","human_time_minutes":{"intake":null,"reviews":null},"agent_runs":[{"role":"Planning","model_id":"model-a","started_utc":"2026-07-02T10:00:00Z","ended_utc":"2026-07-02T10:05:00Z","duration_seconds":300,"tokens_in":null,"tokens_out":null,"cost_usd":null},{"role":"Validation","model_id":"model-b","started_utc":"2026-07-02T10:05:00Z","ended_utc":"2026-07-02T10:10:00Z","duration_seconds":300,"tokens_in":2000000,"tokens_out":200000,"cost_usd":9}],"totals":{"human_time_minutes":0,"agent_duration_seconds":600,"total_cost_usd":null},"verdict":"PASS"}
JSONL
  cat > "$d/want.md" <<'GOLDEN'
## AAI Metrics Summary

### Per Work Item
| ref_id | title | human (min) | agent (sec) | cost USD | cost basis | agent tokens (undecomposed) | leverage | verdict |
|--------|-------|-------------|-------------|----------|------------|------------------------------|----------|---------|
| AAA-0001 | First | 10 | 600 | $7.50 | n/a | n/a | 1.0x | PASS |
| AAA-0002 | Second | 0 | 600 | ~$9.00 | n/a | n/a | n/a | PASS |

Note: "~" prefix on cost means partial (some runs had null token data).

### Totals
- Human time: 10 min
- Agent time: 1200 sec (20.0 min)
- Total cost: ~$16.50
- Average leverage: 2.0x (agent-seconds per human-second)
- Features delivered (PASS): 2

### Per Model Breakdown
| model_id | runs | tokens_in | tokens_out | cost USD |
|----------|------|-----------|------------|----------|
| model-a | 1 | n/a | n/a | n/a |
| model-b | 2 | 3000000 | 300000 | $16.50 |

### Per-Role Token Rollup
| role | agent tokens (undecomposed) |
|------|------------------------------|
| Implementation | n/a |
| Planning | n/a |
| Validation | n/a |

Note: undecomposed tokens are display-only — never converted to a USD figure (the marker carries no in/out split to price).

### Per-Strategy Reliability
| strategy | items | first-pass clean | avg validation fails | avg review fails | avg remediations | basis |
|----------|-------|------------------|----------------------|------------------|------------------|-------|
| n/a | 2 | n/a | n/a | n/a | n/a | n/a |

Note: reliability derives from runs recorded at flush; older ledger lines without it render n/a.
GOLDEN
  runrep() { (cd "$PROJECT_ROOT" && node .aai/scripts/metrics-report.mjs --metrics "$d/METRICS.jsonl" --pricing "$d/PRICING.yaml"); }
  runrep > "$d/run1.md" 2> "$d/run1.err" || log_fail "report must exit 0: $(cat "$d/run1.err")"
  runrep > "$d/run2.md" 2>/dev/null || log_fail "second run must exit 0"
  cmp -s "$d/run1.md" "$d/run2.md" || log_fail "identical input bytes must yield identical output bytes"
  diff -u "$d/want.md" "$d/run1.md" > "$d/golden.diff" 2>&1 \
    || log_fail "report must byte-equal the golden: $(cat "$d/golden.diff")"
  # Empty / comment-only ledger.
  printf '# only comments\n' > "$d/empty.jsonl"
  local out ec=0
  out="$( (cd "$PROJECT_ROOT" && node .aai/scripts/metrics-report.mjs --metrics "$d/empty.jsonl" --pricing "$d/PRICING.yaml") 2>&1 )" || ec=$?
  [[ "$ec" == 0 ]] || log_fail "empty ledger must exit 0 (got $ec): $out"
  [[ "$out" == "No metrics recorded yet." ]] || log_fail "empty ledger must print the exact message (got: $out)"
  # Corrupt line -> exit 1 naming the line number.
  printf '{"ref_id":"OK-1","agent_runs":[]}\n{broken\n' > "$d/bad.jsonl"
  ec=0
  out="$( (cd "$PROJECT_ROOT" && node .aai/scripts/metrics-report.mjs --metrics "$d/bad.jsonl" --pricing "$d/PRICING.yaml") 2>&1 )" || ec=$?
  [[ "$ec" == 1 ]] || log_fail "corrupt ledger line must exit 1 (got $ec): $out"
  assert_payload_contains "$out" "line 2" "corrupt-line error must name the line number: $out"
  log_pass "Report byte-deterministic, golden-exact, ~ partial marker, lex model order, empty + corrupt handled (TEST-014)"
}

test_015_fallback_ref_id_parity() {  # ISSUE-0007 TEST-005 / Spec-AC-05 (SPEC-0019 deviation-3 follow-up)
  log_info "Test: STATE_FALLBACK.md flush-reset last_validation line carries ref_id: null (parity with applyFullReset) (ISSUE-0007 TEST-005)..."
  local fb="$PROJECT_ROOT/.aai/STATE_FALLBACK.md"
  [[ -f "$fb" ]] || log_fail "missing $fb"
  # The hand-edit full-reset list must name every field the primary path nulls:
  # applyFullReset writes last_validation.ref_id: null, so the fallback line
  # must include it (a hand flush that skips it leaves a stale ref_id).
  grep -E '^\s*- last_validation' "$fb" | grep -qF 'ref_id: null' \
    || log_fail "STATE_FALLBACK.md last_validation flush-reset line must include 'ref_id: null': $(grep -E '^\s*- last_validation' "$fb")"
  # And the primary path really nulls it (the parity being documented).
  grep -qF "'ref_id', 'null'" "$FLUSH" \
    || log_fail "metrics-flush.mjs applyFullReset must null last_validation.ref_id"
  log_pass "STATE_FALLBACK full-reset list carries last_validation ref_id: null — hand-edit parity with applyFullReset (ISSUE-0007 TEST-005)"
}

# --- TEST-009 (remediation): full reset over 0-relative-indent lists ----------------

test_016_zero_relative_full_reset() {  # ISSUE-0007 TEST-009 / Spec-AC-06 (remediation)
  log_info "Test: full reset over 0-relative-indent lists leaves NO orphaned items (validation-ISSUE-0007-20260715T233312Z probe d) (ISSUE-0007 TEST-009)..."
  # write_flush_state's OWN list shape is 0-relative (report_paths /
  # evidence_paths items at the same column as their key — legal YAML). The
  # validator's probe (d) showed applyFullReset's `report_paths: []` /
  # `evidence_paths: []` setField writes truncated the span one line short
  # (fieldSpan used strict `>`), orphaning the old item below the new `[]`
  # marker: invalid YAML that check-state also missed. This is the exact
  # repro, with the assertions test_011/test_012 were blind to.
  local d
  d="$(mk_repo t16)"
  write_flush_state "$d/docs/ai/STATE.yaml" single
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  # Confirm the fixture really is 0-relative (guards against fixture drift).
  grep -qE '^ {2}report_paths:$' "$d/docs/ai/STATE.yaml" || log_fail "fixture must carry a bare report_paths: key"
  grep -qE '^ {2}- docs/ai/reviews/review-fixture.md$' "$d/docs/ai/STATE.yaml" \
    || log_fail "fixture must carry the 0-relative report_paths item (same column as key)"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "flush must exit 0 (got $EC): $(cat "$OUT")"
  local st="$d/docs/ai/STATE.yaml"
  # No orphaned `- ` lines may survive the whole-field `[]` rewrites.
  grep -qF -- "- docs/ai/reviews/review-fixture.md" "$st" \
    && log_fail "report_paths item orphaned below 'report_paths: []' (fieldSpan excluded the 0-relative span): $(sed -n '/^code_review:/,/^[a-z_]/p' "$st")"
  grep -qF -- "- docs/ai/reports/validation-fixture.md" "$st" \
    && log_fail "evidence_paths item orphaned below 'evidence_paths: []': $(sed -n '/^last_validation:/,/^[a-z_]/p' "$st")"
  sed -n '/^code_review:/,/^[a-z_]/p' "$st" | grep -qE '^ {2}report_paths: \[\]$' || log_fail "report_paths must reset to []"
  sed -n '/^last_validation:/,/^[a-z_]/p' "$st" | grep -qE '^ {2}evidence_paths: \[\]$' || log_fail "evidence_paths must reset to []"
  # The flushed file must be VALID YAML end-to-end (the reader that rejected
  # the corrupted probe output), and check-state must agree.
  if command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" >/dev/null 2>&1; then
    python3 -c "import sys, yaml; yaml.safe_load(open(sys.argv[1]))" "$st" > "$d/py.log" 2>&1 \
      || log_fail "PyYAML must parse the fully-reset STATE: $(cat "$d/py.log")"
  else
    log_info "python3/PyYAML unavailable — round-trip assert skipped (orphan greps above still bind)"
  fi
  (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs "$st" > "$d/ck.log" 2>&1) \
    || log_fail "check-state must pass after the 0-relative full reset: $(cat "$d/ck.log")"
  log_pass "Full reset over 0-relative lists: whole spans consumed, no orphans, PyYAML + check-state clean (ISSUE-0007 TEST-009)"
}

# --- TEST-017: reliability derivation matrix (SPEC-0032-spec-truth-scoring R1-R6) --------

test_017_reliability_derivation() {
  log_info "Test: reliability derived ONLY from recorded runs — FAIL markers counted, PASS/null notes not; suffixed remediation roles counted; undecided strategy -> null (TEST-017)..."
  local d
  # (a) bumpy history: 1 validation FAIL (marker), 1 review FAIL (marker),
  # 2 remediation runs (one with a suffixed role + null note), PASS-noted
  # re-runs NOT counted, original no-note runs NOT counted as fails.
  d="$(mk_repo t17)"
  write_flush_state "$d/docs/ai/STATE.yaml" single
  node -e '
    const fs = require("fs"); const p = process.argv[1];
    let s = fs.readFileSync(p, "utf8");
    const extra = [
      "        - role: Validation",
      "          model_id: claude-v",
      "          note: \"VERDICT: FAIL. AC-2 unmet (adversarial probe)\"",
      "          started_utc: 2026-07-15T10:15:00Z",
      "          ended_utc: 2026-07-15T10:16:00Z",
      "          duration_seconds: 60",
      "          tokens_in: null",
      "          tokens_out: null",
      "          cost_usd: null",
      "        - role: Remediation",
      "          model_id: claude-r",
      "          started_utc: 2026-07-15T10:16:00Z",
      "          ended_utc: 2026-07-15T10:17:00Z",
      "          duration_seconds: 60",
      "          tokens_in: null",
      "          tokens_out: null",
      "          cost_usd: null",
      "        - role: Validation",
      "          model_id: claude-v",
      "          note: >-",
      "            VERDICT: PASS. all clear after remediation",
      "          started_utc: 2026-07-15T10:17:00Z",
      "          ended_utc: 2026-07-15T10:18:00Z",
      "          duration_seconds: 60",
      "          tokens_in: null",
      "          tokens_out: null",
      "          cost_usd: null",
      "        - role: Code Review",
      "          model_id: claude-c",
      "          note: >-",
      "            Stage 1 NON-COMPLIANT. VERDICT: FAIL. E1 blocking",
      "          started_utc: 2026-07-15T10:18:00Z",
      "          ended_utc: 2026-07-15T10:19:00Z",
      "          duration_seconds: 60",
      "          tokens_in: null",
      "          tokens_out: null",
      "          cost_usd: null",
      "        - role: Remediation (E1 blocking)",
      "          model_id: claude-r",
      "          note: null",
      "          started_utc: 2026-07-15T10:19:00Z",
      "          ended_utc: 2026-07-15T10:20:00Z",
      "          duration_seconds: 60",
      "          tokens_in: null",
      "          tokens_out: null",
      "          cost_usd: null",
      "        - role: Code Review (re-review)",
      "          model_id: claude-c",
      "          note: \"VERDICT: PASS. clean\"",
      "          started_utc: 2026-07-15T10:20:00Z",
      "          ended_utc: 2026-07-15T10:21:00Z",
      "          duration_seconds: 60",
      "          tokens_in: null",
      "          tokens_out: null",
      "          cost_usd: null",
    ].join("\n");
    s = s.replace("\n\nupdated_at_utc:", "\n" + extra + "\n\nupdated_at_utc:");
    fs.writeFileSync(p, s);
  ' "$d/docs/ai/STATE.yaml"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "(a) flush must exit 0 (got $EC): $(cat "$OUT")"
  grep -v -e '^#' -e '^$' "$d/docs/ai/METRICS.jsonl" > "$d/got.jsonl"
  grep -qF '"strategy":"tdd","reliability":{"validation_fails":1,"review_fails":1,"remediation_runs":2,"first_pass_clean":false,"basis":"note"},"verdict_basis":"global-block","verdict":"PASS"' "$d/got.jsonl" \
    || log_fail "(a) entry must carry strategy tdd + reliability {1,1,2,false} in order after totals (marker-noted fails only, suffixed remediation counted, PASS/null notes not): $(cat "$d/got.jsonl")"

  # (b) clean history + undecided strategy -> strategy null, counts 0, clean.
  d="$(mk_repo t17b)"
  write_flush_state "$d/docs/ai/STATE.yaml" single
  node -e '
    const fs = require("fs"); const p = process.argv[1];
    let s = fs.readFileSync(p, "utf8");
    s = s.replace("  selected: tdd", "  selected: undecided");
    fs.writeFileSync(p, s);
  ' "$d/docs/ai/STATE.yaml"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "(b) flush must exit 0 (got $EC): $(cat "$OUT")"
  grep -v -e '^#' -e '^$' "$d/docs/ai/METRICS.jsonl" > "$d/got.jsonl"
  grep -qF '"strategy":null,"reliability":{"validation_fails":0,"review_fails":0,"remediation_runs":0,"first_pass_clean":true,"basis":"note"},"verdict_basis":"global-block","verdict":"PASS"' "$d/got.jsonl" \
    || log_fail "(b) undecided strategy must record null; clean run must be first_pass_clean true: $(cat "$d/got.jsonl")"
  log_pass "Reliability derivation matrix per R1-R6: marker-gated fail counts, structural remediation count, honest strategy null (TEST-017)"
}

# --- TEST-018: per-strategy reliability report golden --------------------------------

test_018_report_strategy_golden() {
  log_info "Test: Per-Strategy Reliability section byte-equals the golden; old lines group under n/a (TEST-018)..."
  local d="$TEST_DIR/t18"
  mkdir -p "$d"
  write_pricing "$d/PRICING.yaml"
  cat > "$d/METRICS.jsonl" <<'JSONL'
# ledger comment
{"date_utc":"2026-07-01","ref_id":"OLD-0001","title":"Old line","human_time_minutes":{"intake":null,"reviews":null},"agent_runs":[{"role":"Implementation","model_id":"claude-sonnet-5","started_utc":"2026-07-01T10:00:00Z","ended_utc":"2026-07-01T10:10:00Z","duration_seconds":600,"tokens_in":1000000,"tokens_out":100000,"cost_usd":null}],"totals":{"human_time_minutes":0,"agent_duration_seconds":600,"total_cost_usd":null},"verdict":"PASS"}
{"date_utc":"2026-07-02","ref_id":"NEW-0001","title":"Tdd clean","human_time_minutes":{"intake":null,"reviews":null},"agent_runs":[{"role":"Implementation","model_id":"claude-sonnet-5","started_utc":"2026-07-02T10:00:00Z","ended_utc":"2026-07-02T10:10:00Z","duration_seconds":600,"tokens_in":null,"tokens_out":null,"cost_usd":null}],"totals":{"human_time_minutes":0,"agent_duration_seconds":600,"total_cost_usd":null},"strategy":"tdd","reliability":{"validation_fails":0,"review_fails":0,"remediation_runs":0,"first_pass_clean":true},"verdict":"PASS"}
{"date_utc":"2026-07-03","ref_id":"NEW-0002","title":"Loop bumpy","human_time_minutes":{"intake":null,"reviews":null},"agent_runs":[{"role":"Implementation","model_id":"claude-sonnet-5","started_utc":"2026-07-03T10:00:00Z","ended_utc":"2026-07-03T10:10:00Z","duration_seconds":600,"tokens_in":null,"tokens_out":null,"cost_usd":null}],"totals":{"human_time_minutes":0,"agent_duration_seconds":600,"total_cost_usd":null},"strategy":"loop","reliability":{"validation_fails":1,"review_fails":0,"remediation_runs":2,"first_pass_clean":false},"verdict":"PASS"}
{"date_utc":"2026-07-04","ref_id":"NEW-0003","title":"Loop clean","human_time_minutes":{"intake":null,"reviews":null},"agent_runs":[{"role":"Implementation","model_id":"claude-sonnet-5","started_utc":"2026-07-04T10:00:00Z","ended_utc":"2026-07-04T10:10:00Z","duration_seconds":600,"tokens_in":null,"tokens_out":null,"cost_usd":null}],"totals":{"human_time_minutes":0,"agent_duration_seconds":600,"total_cost_usd":null},"strategy":"loop","reliability":{"validation_fails":0,"review_fails":1,"remediation_runs":1,"first_pass_clean":false},"verdict":"PASS"}
JSONL
  cat > "$d/want-section.md" <<'GOLDEN'
### Per-Strategy Reliability
| strategy | items | first-pass clean | avg validation fails | avg review fails | avg remediations | basis |
|----------|-------|------------------|----------------------|------------------|------------------|-------|
| loop | 2 | 0/2 (0%) | 0.5 | 0.5 | 1.5 | n/a |
| n/a | 1 | n/a | n/a | n/a | n/a | n/a |
| tdd | 1 | 1/1 (100%) | 0.0 | 0.0 | 0.0 | n/a |

Note: reliability derives from runs recorded at flush; older ledger lines without it render n/a.
GOLDEN
  runrep18() { (cd "$PROJECT_ROOT" && node .aai/scripts/metrics-report.mjs --metrics "$d/METRICS.jsonl" --pricing "$d/PRICING.yaml"); }
  runrep18 > "$d/run1.md" 2> "$d/run1.err" || log_fail "report must exit 0: $(cat "$d/run1.err")"
  runrep18 > "$d/run2.md" 2>/dev/null || log_fail "second run must exit 0"
  cmp -s "$d/run1.md" "$d/run2.md" || log_fail "identical input bytes must yield identical output bytes"
  sed -n '/^### Per-Strategy Reliability$/,$p' "$d/run1.md" > "$d/got-section.md"
  diff -u "$d/want-section.md" "$d/got-section.md" > "$d/golden.diff" 2>&1 \
    || log_fail "Per-Strategy Reliability section must byte-equal the golden (lex order, n/a group, X/Y (P%) rate, one-decimal avgs): $(cat "$d/golden.diff")"
  log_pass "Per-Strategy Reliability golden exact; deterministic; old lines n/a (TEST-018)"
}

# --- SPEC-0054 (CHANGE-0038): flush stops emitting close lifecycle events ------------
# close-work-item.mjs (CHANGE-0037/SPEC-0053) is now the SINGLE SOURCE OF TRUTH
# for doc_lifecycle/work_item_closed. TEST-001..004 cross the flush <-> real
# docs-audit engine <-> close-work-item.mjs seam (SEAM-1) — no mocking.

test_019_no_close_events_from_flush() {  # TEST-001 (Spec-AC-01)
  log_info "Test: flush of a draft-closed work item emits ZERO doc_lifecycle/work_item_closed to EVENTS (TEST-001)..."
  local d
  d="$(mk_repo t19)"
  write_flush_state "$d/docs/ai/STATE.yaml" single
  write_frontmatter_doc "$d/docs/issues/CHANGE-0001-golden.md" CHANGE-0001 change draft
  # Edge case (a): EVENTS.jsonl absent before flush -> must STAY absent.
  rm -f "$d/docs/ai/EVENTS.jsonl"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "flush must exit 0 (got $EC): $(cat "$OUT")"
  [[ ! -f "$d/docs/ai/EVENTS.jsonl" ]] \
    || log_fail "flush must not create/touch EVENTS.jsonl (RED pre-fix: doc_lifecycle --from implementing + work_item_closed emitted for a doc that actually closed from draft): $(cat "$d/docs/ai/EVENTS.jsonl")"
  log_pass "Flush emits NO doc_lifecycle/work_item_closed; EVENTS.jsonl stays absent (TEST-001)"
}

test_020_numbered_ref_audit_clean() {  # TEST-002 (Spec-AC-02)
  log_info "Test: numbered STATE ref_id + slug frontmatter id — post-flush docs-audit CLEAN, no flush-attributable finding (TEST-002)..."
  local d
  d="$(mk_seam_repo t20)"
  write_flush_state "$d/docs/ai/STATE.yaml" single
  # Rename the STATE ref from the bare slug CHANGE-0001 to a NUMBERED form
  # (SPEC-0099) while the doc keeps its OWN slug frontmatter id — the exact
  # ref-form mismatch the audit matches on fm.id, never the numbered fileId
  # (spec Problem #2). The doc's filename-derived fileId is "SPEC-0099".
  node -e '
    const fs = require("fs"); const p = process.argv[1];
    let s = fs.readFileSync(p, "utf8");
    s = s.replace(/CHANGE-0001/g, "SPEC-0099");
    fs.writeFileSync(p, s);
  ' "$d/docs/ai/STATE.yaml"
  write_frontmatter_doc "$d/docs/issues/SPEC-0099-golden.md" numbered-fixture-slug spec draft
  git -C "$d" add -A && git -C "$d" commit -q -m "seam fixture t20"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "flush must exit 0 (got $EC): $(cat "$OUT")"
  (cd "$d" && node "$PROJECT_ROOT/.aai/scripts/docs-audit.mjs" --no-event --path docs/issues/SPEC-0099-golden.md > audit.log 2>&1) || true
  grep -qF "probable-false-open" "$d/audit.log" \
    && log_fail "flush must not trip probable-false-open Arm C via the numbered STATE ref (RED pre-fix: work_item_closed --ref SPEC-0099 matches the doc's fileId, not its slug id): $(cat "$d/audit.log")"
  grep -qF "missing-close-telemetry" "$d/audit.log" \
    && log_fail "a still-open (draft) doc must never surface missing-close-telemetry: $(cat "$d/audit.log")"
  log_pass "Numbered STATE ref_id vs slug frontmatter id — flush emits nothing, post-flush audit CLEAN (TEST-002)"
}

test_021_flush_then_close_no_double_emit() {  # TEST-003 (Spec-AC-03)
  log_info "Test: flush THEN close-work-item.mjs — exactly one work_item_closed + one terminal doc_lifecycle per ref (TEST-003)..."
  local d commit="1234567890abcdef1234567890abcdef12345678" cec=0
  d="$(mk_seam_repo t21)"
  write_flush_state "$d/docs/ai/STATE.yaml" single
  write_frontmatter_doc "$d/docs/issues/CHANGE-0001-golden.md" CHANGE-0001 change draft
  git -C "$d" add -A && git -C "$d" commit -q -m "seam fixture t21"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "flush must exit 0 (got $EC): $(cat "$OUT")"
  (cd "$d" && node "$PROJECT_ROOT/.aai/scripts/close-work-item.mjs" --ref CHANGE-0001 --pr 1 --commit "$commit" --review pass > close.log 2>&1) || cec=$?
  [[ "$cec" == 0 ]] || log_fail "close-work-item.mjs must exit 0 after flush: $(cat "$d/close.log")"
  local dl wic
  dl="$(event_count "$d/docs/ai/EVENTS.jsonl" doc_lifecycle CHANGE-0001)"
  wic="$(event_count "$d/docs/ai/EVENTS.jsonl" work_item_closed CHANGE-0001)"
  [[ "$dl" == 1 ]] || log_fail "exactly ONE terminal doc_lifecycle expected for CHANGE-0001 after flush+close (got $dl — RED pre-fix: flush's hardcoded --from implementing double-emits alongside close's correct --from draft): $(cat "$d/docs/ai/EVENTS.jsonl")"
  [[ "$wic" == 1 ]] || log_fail "exactly ONE work_item_closed expected for CHANGE-0001 after flush+close (got $wic): $(cat "$d/docs/ai/EVENTS.jsonl")"
  log_pass "flush -> close-work-item.mjs: single-emission invariant holds (TEST-003)"
}

test_022_close_then_flush_no_double_emit() {  # TEST-004 (Spec-AC-03)
  log_info "Test: close-work-item.mjs THEN flush — flush adds no duplicate close event (TEST-004)..."
  local d commit="abcdef1234567890abcdef1234567890abcdef12" cec=0
  d="$(mk_seam_repo t22)"
  write_flush_state "$d/docs/ai/STATE.yaml" single
  write_frontmatter_doc "$d/docs/issues/CHANGE-0001-golden.md" CHANGE-0001 change draft
  git -C "$d" add -A && git -C "$d" commit -q -m "seam fixture t22"
  (cd "$d" && node "$PROJECT_ROOT/.aai/scripts/close-work-item.mjs" --ref CHANGE-0001 --pr 1 --commit "$commit" --review pass > close.log 2>&1) || cec=$?
  [[ "$cec" == 0 ]] || log_fail "close-work-item.mjs must exit 0: $(cat "$d/close.log")"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "flush must exit 0 after close (got $EC): $(cat "$OUT")"
  local dl wic
  dl="$(event_count "$d/docs/ai/EVENTS.jsonl" doc_lifecycle CHANGE-0001)"
  wic="$(event_count "$d/docs/ai/EVENTS.jsonl" work_item_closed CHANGE-0001)"
  [[ "$dl" == 1 ]] || log_fail "exactly ONE terminal doc_lifecycle expected for CHANGE-0001 after close+flush (got $dl — RED pre-fix: flush re-emits an UNCONDITIONAL doc_lifecycle/work_item_closed with no dedup, on top of close's correct pair): $(cat "$d/docs/ai/EVENTS.jsonl")"
  [[ "$wic" == 1 ]] || log_fail "exactly ONE work_item_closed expected for CHANGE-0001 after close+flush (got $wic): $(cat "$d/docs/ai/EVENTS.jsonl")"
  log_pass "close-work-item.mjs -> flush: flush adds no duplicate close event (TEST-004)"
}

test_023_ledger_shape_unchanged() {  # TEST-005 (Spec-AC-04, regression control)
  log_info "Test: the flushed METRICS.jsonl entry shape is unaffected by the events-removal (regression control) (TEST-005)..."
  local d
  d="$(mk_repo t23)"
  write_flush_state "$d/docs/ai/STATE.yaml" single
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  write_golden_doc "$d"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "flush must exit 0 (got $EC): $(cat "$OUT")"
  grep -v -e '^#' -e '^$' "$d/docs/ai/METRICS.jsonl" > "$d/got.jsonl"
  node -e '
    const fs = require("fs");
    const got = JSON.parse(fs.readFileSync(process.argv[1], "utf8").trim());
    const wantKeys = ["date_utc","ref_id","title","human_time_minutes","agent_runs","totals","strategy","reliability","verdict_basis","verdict"];
    const gotKeys = Object.keys(got);
    if (JSON.stringify(gotKeys) !== JSON.stringify(wantKeys)) {
      console.error("ledger entry key set/order changed: got " + JSON.stringify(gotKeys) + " want " + JSON.stringify(wantKeys));
      process.exit(1);
    }
  ' "$d/got.jsonl" || log_fail "ledger entry shape must be byte/shape unchanged by the events-removal"
  log_pass "Ledger record shape unchanged by removing the events emission (TEST-005)"
}

# --- TEST-134: the partial reset archives the proof it is throwing away --------
# spec-metrics-flush-invalidates-pr-precondition TEST-001 / Spec-AC-01.
#
# applyPartialReset already composes the reset note, stamps `run_at_utc` and
# appends the ledger line from ONE `nowIso` in ONE transaction. This arm pins
# the third use of that instant: one archive record per reset ref, whose `at`
# is BYTE-EQUAL to the `run_at_utc` written beside it and whose day is the
# ledger entry's `date_utc`. Byte equality is the whole recency binding — a
# record one second off must not read as this ride's proof — so every value is
# read back OUT OF THE WRITTEN FILES and compared to each other, never to the
# fixture's own NOW_PIN.
test_134_partial_reset_archives_the_proof() {
  log_info "Test: partial reset appends one archive record per reset ref, bound to run_at_utc and the ledger day (TEST-134, Spec-AC-01)..."
  local d
  d="$(mk_repo t134)"
  write_flush_state "$d/docs/ai/STATE.yaml" two
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "flush must exit 0 (got $EC): $(cat "$OUT")"
  grep -qF "Partial-flush reset applied" "$OUT" \
    || log_fail "TEST-134 premise: this fixture must take the PARTIAL branch: $(cat "$OUT")"

  sed -n '/^last_validation:/,/^[a-z_]*:/p' "$d/docs/ai/STATE.yaml" > "$d/lv.block"
  # The pre-existing prose stays FIRST and unchanged — TEST-011's assertion is
  # the same string, and the record is an addition, not a rewrite.
  grep -qF "reset after flush of CHANGE-0001" "$d/lv.block" \
    || log_fail "TEST-134: the existing flush-provenance prose must survive unchanged: $(cat "$d/lv.block")"
  grep -qF "[AAI-VALIDATION-ARCHIVED v1 ref=CHANGE-0001 at=" "$d/lv.block" \
    || log_fail "TEST-134: the reset note must carry an archive record for the reset ref: $(cat "$d/lv.block")"

  # The three-way binding, all values read back from what was actually written.
  local bound
  bound="$(node -e '
    const fs = require("fs");
    const state = fs.readFileSync(process.argv[1], "utf8");
    const block = (state.match(/^last_validation:\n(?:[ \t].*\n|\n)*/m) || [""])[0];
    const runAt = (block.match(/^  run_at_utc: (\S+)$/m) || [])[1] || "MISSING";
    const at = (block.match(/\[AAI-VALIDATION-ARCHIVED v1 ref=CHANGE-0001 at=([^\]]*)\]/) || [])[1] || "MISSING";
    const line = fs.readFileSync(process.argv[2], "utf8").split("\n").filter((l) => l.trim() && !l.startsWith("#"))[0];
    const e = JSON.parse(line);
    console.log([runAt === at, at === `${e.date_utc}T${at.slice(11)}`, e.ref_id, e.verdict, runAt, at].join("|"));
  ' "$d/docs/ai/STATE.yaml" "$d/docs/ai/METRICS.jsonl")"
  case "$bound" in
    "true|true|CHANGE-0001|PASS|"*) : ;;
    *) log_fail "TEST-134: record.at must equal run_at_utc byte for byte and share the ledger PASS's day — got '$bound'" ;;
  esac

  # SCOPE BOUNDARY, pinned so nobody widens it by accident: the FULL reset is
  # deliberately NOT covered (it nulls current_focus, so branch-guard.mjs
  # refuses long before the validation gate is reached).
  local f
  f="$(mk_repo t134full)"
  write_flush_state "$f/docs/ai/STATE.yaml" single
  write_ticks "$f/docs/ai/LOOP_TICKS.jsonl"
  run_flush "$f"
  [[ "$EC" == 0 ]] || log_fail "full-reset flush must exit 0 (got $EC): $(cat "$OUT")"
  grep -qF "[AAI-VALIDATION-ARCHIVED" "$f/docs/ai/STATE.yaml" \
    && log_fail "TEST-134: the FULL reset is out of scope and must mint no archive record"
  log_pass "Partial reset archives one record per reset ref, bound byte-for-byte to run_at_utc and the ledger day; full reset mints none (TEST-134)"
}

# --- metrics-flush-strands-completed-refs: --sweep (TEST-101..109) -------------
# SPEC-0068-spec-metrics-flush-sweep.md D1-D5. Every fixture is a scratch
# temp-dir repo; the real docs/ai/{STATE.yaml,METRICS.jsonl,EVENTS.jsonl} are
# NEVER touched by these tests.

test_101_sweep_flag_parse() {
  log_info "Test: --sweep flag parses; listed in the unknown-flag usage string; accepted with exit 0 (TEST-101, Spec-AC-01)..."
  local cnt
  cnt="$(grep -c -- '--sweep' "$FLUSH" || true)"
  [[ "$cnt" -ge 1 ]] || log_fail "metrics-flush.mjs must reference --sweep at least once (RED baseline was 0)"
  local d
  d="$(mk_repo t101)"
  write_sweep_state "$d/docs/ai/STATE.yaml" "ITEM-Z:in_progress"
  run_flush "$d" --sweep
  [[ "$EC" == 0 ]] || log_fail "--sweep must be accepted (exit 0, got $EC): $(cat "$OUT")"
  local usage_out usage_ec=0
  usage_out="$( (cd "$PROJECT_ROOT" && node .aai/scripts/metrics-flush.mjs --bogus-flag 2>&1) )" || usage_ec=$?
  [[ "$usage_ec" == 2 ]] || log_fail "unknown flag must still exit 2 (got $usage_ec): $usage_out"
  assert_payload_contains "$usage_out" "--sweep" "unknown-flag usage string must list --sweep: $usage_out"
  log_pass "--sweep parses, is accepted, and is listed in usage (TEST-101)"
}

test_102_sweep_flushes_closed_ref() {
  log_info "Test: --sweep flushes a stranded done ref with a durable work_item_closed event; ledger shape-identical (TEST-102, Spec-AC-02)..."
  local d
  d="$(mk_repo t102)"
  write_sweep_state "$d/docs/ai/STATE.yaml" "ITEM-B:done"
  write_closed_event "$d/docs/ai/EVENTS.jsonl" ITEM-B "2026-07-15T10:30:00Z"
  run_flush "$d" --sweep
  [[ "$EC" == 0 ]] || log_fail "sweep must exit 0 (got $EC): $(cat "$OUT")"
  [[ "$(ledger_lines "$d")" == 1 ]] || log_fail "exactly one ledger line must be appended by sweep"
  grep -v -e '^#' -e '^$' "$d/docs/ai/METRICS.jsonl" > "$d/got.jsonl"
  node -e '
    const fs = require("fs");
    const o = JSON.parse(fs.readFileSync(process.argv[1], "utf8").trim());
    const wantKeys = ["date_utc","ref_id","title","human_time_minutes","agent_runs","totals","strategy","reliability","verdict_basis","verdict"];
    if (JSON.stringify(Object.keys(o)) !== JSON.stringify(wantKeys)) { console.error("key set/order changed: " + JSON.stringify(Object.keys(o))); process.exit(1); }
    if (o.ref_id !== "ITEM-B") { console.error("ref_id must be ITEM-B, got " + o.ref_id); process.exit(1); }
    if (o.verdict !== "PASS") { console.error("verdict must be PASS, got " + o.verdict); process.exit(1); }
  ' "$d/got.jsonl" || log_fail "swept ledger line golden key-set/order/verdict wrong: $(cat "$d/got.jsonl")"
  grep -qF "Flushed: ITEM-B" "$OUT" || log_fail "report must name the swept ref: $(cat "$OUT")"
  grep -qE '^ {4}ITEM-B:' "$d/docs/ai/STATE.yaml" && log_fail "swept metrics entry must be surgically removed from STATE"
  grep -qF "ref_id: ITEM-B" "$d/docs/ai/STATE.yaml" && log_fail "swept done active_work_items entry must be surgically removed"
  (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs "$d/docs/ai/STATE.yaml" > "$d/ck.log" 2>&1) \
    || log_fail "check-state must pass after sweep: $(cat "$d/ck.log")"
  log_pass "Sweep flushes a durably-closed stranded ref; ledger shape-identical to a normal flush (TEST-102)"
}

test_103_sweep_fail_closed() {
  log_info "Test: no close event -> SKIP+report, ledger byte-identical; close event but in-flight -> never swept (TEST-103, Spec-AC-03)..."
  local d
  # (a) done, NO close event (degenerate: EVENTS.jsonl exists but is empty).
  d="$(mk_repo t103a)"
  write_sweep_state "$d/docs/ai/STATE.yaml" "ITEM-B:done"
  : > "$d/docs/ai/EVENTS.jsonl"
  cp "$d/docs/ai/METRICS.jsonl" "$d/ledger.before"
  run_flush "$d" --sweep
  [[ "$EC" == 0 ]] || log_fail "(a) must exit 0 (got $EC): $(cat "$OUT")"
  cmp -s "$d/docs/ai/METRICS.jsonl" "$d/ledger.before" || log_fail "(a) ledger must stay byte-identical"
  grep -qiF "no durable work_item_closed event" "$OUT" || log_fail "(a) report must name the fail-closed reason: $(cat "$OUT")"
  grep -qE '^ {4}ITEM-B:' "$d/docs/ai/STATE.yaml" || log_fail "(a) un-swept entry must remain in STATE"

  # (b) NEGATIVE CONTROL: close event present but the item is still in_progress
  # (in-flight) -> must NEVER be swept, regardless of the durable event.
  d="$(mk_repo t103b)"
  write_sweep_state "$d/docs/ai/STATE.yaml" "ITEM-B:in_progress"
  write_closed_event "$d/docs/ai/EVENTS.jsonl" ITEM-B "2026-07-15T10:30:00Z"
  cp "$d/docs/ai/METRICS.jsonl" "$d/ledger.before"
  run_flush "$d" --sweep
  [[ "$EC" == 0 ]] || log_fail "(b) must exit 0 (got $EC): $(cat "$OUT")"
  cmp -s "$d/docs/ai/METRICS.jsonl" "$d/ledger.before" || log_fail "(b) ledger must stay byte-identical (in-flight must never be swept)"
  grep -qiE "in_progress|in-flight" "$OUT" || log_fail "(b) report must name the in-flight reason: $(cat "$OUT")"
  grep -qF "ref_id: ITEM-B" "$d/docs/ai/STATE.yaml" || log_fail "(b) in-flight item must stay byte-present"
  log_pass "Fail-closed: no close event skipped+reported; in-flight-with-close-event never swept (TEST-103)"
}

test_104_default_unchanged() {
  log_info "Test: no-flag run reproduces the TEST-006 golden ledger byte-for-byte; a stranded-but-closed non-focus ref stays SKIPPED without --sweep (TEST-104, Spec-AC-04)..."
  local d
  d="$(mk_repo t104)"
  write_flush_state "$d/docs/ai/STATE.yaml" single
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  write_golden_doc "$d"
  # A stranded done ref, durably closed, that is NOT the last_validation ref —
  # must stay untouched when --sweep is absent.
  node -e '
    const fs = require("fs"); const p = process.argv[1];
    let s = fs.readFileSync(p, "utf8");
    s = s.replace("active_work_items:\n  - ref_id: CHANGE-0001",
      "active_work_items:\n  - ref_id: ITEM-B\n    status: done\n    phase: validation\n    primary_path: docs/issues/ITEM-B.md\n  - ref_id: CHANGE-0001");
    const extra = [
      "    ITEM-B:",
      "      human_time_minutes:",
      "        intake: null",
      "        reviews: null",
      "      agent_runs:",
      "        - role: Implementation",
      "          model_id: claude-sonnet-5",
      "          started_utc: 2026-07-15T09:00:00Z",
      "          ended_utc: 2026-07-15T09:10:00Z",
      "          duration_seconds: 600",
      "          tokens_in: 1000000",
      "          tokens_out: 100000",
      "          cost_usd: null",
    ].join("\n");
    s = s.replace("metrics:\n  work_items:\n    CHANGE-0001:", "metrics:\n  work_items:\n" + extra + "\n    CHANGE-0001:");
    fs.writeFileSync(p, s);
  ' "$d/docs/ai/STATE.yaml"
  write_closed_event "$d/docs/ai/EVENTS.jsonl" ITEM-B "2026-07-15T09:30:00Z"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "flush must exit 0 (got $EC): $(cat "$OUT")"
  [[ "$(ledger_lines "$d")" == 1 ]] || log_fail "only CHANGE-0001 may flush without --sweep"
  grep -v -e '^#' -e '^$' "$d/docs/ai/METRICS.jsonl" > "$d/got.jsonl"
  cat > "$d/want.jsonl" <<'GOLDEN'
{"date_utc":"2026-07-15","ref_id":"CHANGE-0001","title":"Golden fixture item","human_time_minutes":{"intake":null,"reviews":2},"agent_runs":[{"role":"Planning","model_id":"claude-opus-4-8[1m]","started_utc":"2026-07-15T10:00:00Z","ended_utc":"2026-07-15T10:02:00Z","duration_seconds":120,"tokens_in":1000000,"tokens_out":100000,"cost_usd":7.5,"cost_basis":"decomposed","harness":null,"tokens_total":null,"verdict":null,"verdict_basis":"none"},{"role":"Implementation","model_id":"sonnet-latest","started_utc":"2026-07-15T10:02:00Z","ended_utc":"2026-07-15T10:12:00Z","duration_seconds":600,"tokens_in":2000000,"tokens_out":200000,"cost_usd":9,"cost_basis":"decomposed","harness":null,"tokens_total":null,"verdict":null,"verdict_basis":"none"},{"role":"Validation","model_id":"claude-sonnet-5-20260101","started_utc":"2026-07-15T10:12:00Z","ended_utc":"2026-07-15T10:13:40Z","duration_seconds":100,"tokens_in":1000000,"tokens_out":1000000,"cost_usd":18,"cost_basis":"decomposed","harness":null,"tokens_total":null,"verdict":null,"verdict_basis":"note"},{"role":"Code Review","model_id":"mystery-9000","started_utc":"2026-07-15T10:13:40Z","ended_utc":"2026-07-15T10:14:40Z","duration_seconds":60,"tokens_in":10,"tokens_out":10,"cost_usd":null,"cost_basis":"none","harness":null,"tokens_total":null,"verdict":null,"verdict_basis":"note"}],"totals":{"human_time_minutes":2,"agent_duration_seconds":880,"total_cost_usd":null,"cost_basis":"mixed"},"strategy":"tdd","reliability":{"validation_fails":0,"review_fails":0,"remediation_runs":0,"first_pass_clean":true,"basis":"note"},"verdict_basis":"global-block","verdict":"PASS"}
GOLDEN
  diff -u "$d/want.jsonl" "$d/got.jsonl" > "$d/golden.diff" 2>&1 \
    || log_fail "no-flag ledger line must byte-equal the TEST-006 golden: $(cat "$d/golden.diff")"
  grep -qE '^ {4}ITEM-B:' "$d/docs/ai/STATE.yaml" || log_fail "stranded ITEM-B metrics entry must remain (not flushed without --sweep)"
  grep -qF "ref_id: ITEM-B" "$d/docs/ai/STATE.yaml" || log_fail "stranded ITEM-B active_work_items entry must remain"
  grep -qiE "ITEM-B.*(validation verdict|needs PASS)" "$OUT" || log_fail "report must name why ITEM-B was skipped: $(cat "$OUT")"
  log_pass "Default (no-flag) flush byte-identical to TEST-006; stranded-but-closed ref stays skipped without --sweep (TEST-104)"
}

test_105_sweep_state_hygiene() {
  log_info "Test: sweep of two done closed refs while an in_progress ref remains: both removed, in-flight untouched, no spurious verdict reset, check-state green (TEST-105, Spec-AC-05)..."
  local d
  d="$(mk_repo t105)"
  write_sweep_state "$d/docs/ai/STATE.yaml" "ITEM-B:done" "ITEM-D:done" "ITEM-C:in_progress"
  # Give code_review a non-default value to prove a swept NON-focus ref never
  # triggers a spurious verdict-block reset (D5).
  node -e '
    const fs = require("fs"); const p = process.argv[1];
    let s = fs.readFileSync(p, "utf8");
    s = s.replace("code_review:\n  required: false\n  status: not_run", "code_review:\n  required: true\n  status: pass");
    fs.writeFileSync(p, s);
  ' "$d/docs/ai/STATE.yaml"
  write_closed_event "$d/docs/ai/EVENTS.jsonl" ITEM-B "2026-07-15T10:30:00Z"
  write_closed_event "$d/docs/ai/EVENTS.jsonl" ITEM-D "2026-07-15T10:31:00Z"
  run_flush "$d" --sweep
  [[ "$EC" == 0 ]] || log_fail "sweep must exit 0 (got $EC): $(cat "$OUT")"
  [[ "$(ledger_lines "$d")" == 2 ]] || log_fail "exactly two ledger lines expected (ITEM-B + ITEM-D)"
  local st="$d/docs/ai/STATE.yaml"
  grep -qE '^ {4}ITEM-B:' "$st" && log_fail "ITEM-B metrics entry must be removed"
  grep -qE '^ {4}ITEM-D:' "$st" && log_fail "ITEM-D metrics entry must be removed"
  grep -qE '^ {4}ITEM-C:' "$st" || log_fail "ITEM-C (in_progress) metrics entry must remain byte-present"
  grep -qF "ref_id: ITEM-B" "$st" && log_fail "ITEM-B active_work_items entry must be removed"
  grep -qF "ref_id: ITEM-D" "$st" && log_fail "ITEM-D active_work_items entry must be removed"
  grep -qF "ref_id: ITEM-C" "$st" || log_fail "ITEM-C active_work_items entry must remain byte-present"
  sed -n '/^code_review:/,/^[a-z_]*:/p' "$st" | grep -qE '^ {2}required: true$' \
    || log_fail "swept non-focus refs must NOT trigger a spurious code_review reset (D5)"
  sed -n '/^code_review:/,/^[a-z_]*:/p' "$st" | grep -qE '^ {2}status: pass$' \
    || log_fail "swept non-focus refs must NOT reset code_review.status"
  grep -qE '^ {2}selected: tdd$' "$st" || log_fail "partial (non-full) reset must NOT touch implementation_strategy"
  (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs "$st" > "$d/ck.log" 2>&1) \
    || log_fail "check-state must pass after sweep hygiene: $(cat "$d/ck.log")"
  log_pass "STATE hygiene: surgical removal of both swept refs, in-flight untouched, no spurious reset (TEST-105)"
}

test_106_sweep_integrity_refusal() {
  log_info "Test: pre-existing duplicate top-level key under --sweep -> exit 1 integrity refusal, STATE + ledger untouched (TEST-106, Spec-AC-05)..."
  local d
  d="$(mk_repo t106)"
  write_sweep_state "$d/docs/ai/STATE.yaml" "ITEM-B:done"
  write_closed_event "$d/docs/ai/EVENTS.jsonl" ITEM-B "2026-07-15T10:30:00Z"
  # Inject a duplicate top-level key — a structurally invalid planned STATE,
  # the exact invariant the pre-flush guard exists to catch (must still fire
  # correctly with --sweep, never be bypassed by the new flag).
  printf '\nactive_work_items:\n  - ref_id: DUP-0001\n    status: done\n' >> "$d/docs/ai/STATE.yaml"
  cp "$d/docs/ai/STATE.yaml" "$d/state.before"
  cp "$d/docs/ai/METRICS.jsonl" "$d/ledger.before"
  run_flush "$d" --sweep
  [[ "$EC" == 1 ]] || log_fail "must exit 1 (got $EC): $(cat "$OUT")"
  grep -qiE "duplicate top-level key|integrity refusal" "$OUT" || log_fail "must report the integrity refusal reason: $(cat "$OUT")"
  cmp -s "$d/docs/ai/STATE.yaml" "$d/state.before" || log_fail "STATE must stay byte-identical (original preserved)"
  cmp -s "$d/docs/ai/METRICS.jsonl" "$d/ledger.before" || log_fail "ledger must stay byte-identical (nothing written)"
  log_pass "Structurally-invalid STATE under --sweep refuses + rolls back, exactly like the default path (TEST-106)"
}

test_107_sweep_idempotent() {
  log_info "Test: a second --sweep is a no-op; crash-then-resume is cleanup-only with no duplicate ledger line (TEST-107, Spec-AC-06)..."
  local d
  # (a) fully-covered / zero-remainder: second sweep after a successful one.
  d="$(mk_repo t107a)"
  write_sweep_state "$d/docs/ai/STATE.yaml" "ITEM-B:done"
  write_closed_event "$d/docs/ai/EVENTS.jsonl" ITEM-B "2026-07-15T10:30:00Z"
  run_flush "$d" --sweep
  [[ "$EC" == 0 ]] || log_fail "(1) sweep must exit 0 (got $EC): $(cat "$OUT")"
  [[ "$(ledger_lines "$d")" == 1 ]] || log_fail "(1) exactly one ledger line expected"
  run_flush "$d" --sweep
  [[ "$EC" == 0 ]] || log_fail "(2) re-sweep must exit 0 (got $EC): $(cat "$OUT")"
  [[ "$(ledger_lines "$d")" == 1 ]] || log_fail "(2) re-sweep must not append a duplicate line"
  grep -qiF "nothing to flush" "$OUT" || log_fail "(2) re-sweep must report Nothing to flush: $(cat "$OUT")"

  # (b) mid-operation failure: crash AFTER the ledger append, BEFORE the STATE
  # commit -> resume is cleanup-only, no duplicate line.
  d="$(mk_repo t107b)"
  write_sweep_state "$d/docs/ai/STATE.yaml" "ITEM-D:done"
  write_closed_event "$d/docs/ai/EVENTS.jsonl" ITEM-D "2026-07-15T10:30:00Z"
  local ec=0
  (cd "$PROJECT_ROOT" && AAI_FLUSH_INJECT_CRASH=after-ledger node .aai/scripts/metrics-flush.mjs \
    --state "$d/docs/ai/STATE.yaml" --metrics "$d/docs/ai/METRICS.jsonl" \
    --ticks "$d/docs/ai/LOOP_TICKS.jsonl" --pricing "$d/PRICING.yaml" \
    --events "$d/docs/ai/EVENTS.jsonl" --now "$NOW_PIN" --sweep > "$d/crash.log" 2>&1) || ec=$?
  [[ "$ec" != 0 ]] || log_fail "(b) injected crash must not exit 0"
  [[ "$(ledger_lines "$d")" == 1 ]] || log_fail "(b) the ledger line must already be durable pre-crash"
  grep -qE '^ {4}ITEM-D:' "$d/docs/ai/STATE.yaml" || log_fail "(b) STATE must still carry ITEM-D pre-resume (interrupted flush)"
  run_flush "$d" --sweep
  [[ "$EC" == 0 ]] || log_fail "(c) resume sweep must exit 0 (got $EC): $(cat "$OUT")"
  [[ "$(ledger_lines "$d")" == 1 ]] || log_fail "(c) resume must NOT append a second ledger line"
  grep -qE '^ {4}ITEM-D:' "$d/docs/ai/STATE.yaml" && log_fail "(c) resume must complete the STATE cleanup for ITEM-D"
  grep -qiE "resume|already in (the )?ledger" "$OUT" || log_fail "(c) report must say it resumed an interrupted flush: $(cat "$OUT")"
  log_pass "Second sweep is a no-op; crash-then-resume is cleanup-only, no double-flush (TEST-107)"
}

test_108_sweep_targeted_ref() {
  log_info "Test: --sweep --ref B restricts the sweep to the single stranded ref; others report not-selected (TEST-108, Spec-AC-07)..."
  local d
  d="$(mk_repo t108)"
  write_sweep_state "$d/docs/ai/STATE.yaml" "ITEM-B:done" "ITEM-E:done"
  write_closed_event "$d/docs/ai/EVENTS.jsonl" ITEM-B "2026-07-15T10:30:00Z"
  write_closed_event "$d/docs/ai/EVENTS.jsonl" ITEM-E "2026-07-15T10:31:00Z"
  run_flush "$d" --sweep --ref ITEM-B
  [[ "$EC" == 0 ]] || log_fail "targeted sweep must exit 0 (got $EC): $(cat "$OUT")"
  [[ "$(ledger_lines "$d")" == 1 ]] || log_fail "exactly one ledger line (ITEM-B only) expected"
  grep -qF '"ref_id":"ITEM-B"' "$d/docs/ai/METRICS.jsonl" || log_fail "the flushed line must be ITEM-B"
  grep -qF '"ref_id":"ITEM-E"' "$d/docs/ai/METRICS.jsonl" && log_fail "ITEM-E must NOT be flushed by a targeted sweep"
  grep -qE '^ {4}ITEM-E:' "$d/docs/ai/STATE.yaml" || log_fail "ITEM-E must remain in STATE (not selected)"
  grep -qiF "ITEM-E: not selected (--ref restriction)" "$OUT" || log_fail "report must name ITEM-E as not selected: $(cat "$OUT")"
  log_pass "--sweep --ref composes with the existing --ref restriction (TEST-108)"
}

test_109_sweep_seam_close_then_sweep() {
  log_info "Test: SEAM-1 — a REAL close-work-item.mjs run stamps work_item_closed, then --sweep flushes it (no mock); absent EVENTS fail-closes and creates none (TEST-109, Spec-AC-08)..."
  local d commit="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" cec=0
  d="$(mk_seam_repo t109)"
  write_sweep_state "$d/docs/ai/STATE.yaml" "ITEM-B:done"
  write_frontmatter_doc "$d/docs/issues/ITEM-0001-close-seam.md" ITEM-B issue implementing
  git -C "$d" add -A && git -C "$d" commit -q -m "seam fixture t109"
  (cd "$d" && node "$PROJECT_ROOT/.aai/scripts/close-work-item.mjs" --ref ITEM-B --pr 1 --commit "$commit" --review pass > close.log 2>&1) || cec=$?
  [[ "$cec" == 0 ]] || log_fail "close-work-item.mjs must exit 0: $(cat "$d/close.log")"
  local wic
  wic="$(event_count "$d/docs/ai/EVENTS.jsonl" work_item_closed ITEM-B)"
  [[ "$wic" == 1 ]] || log_fail "close-work-item.mjs must stamp exactly one work_item_closed for ITEM-B: $(cat "$d/docs/ai/EVENTS.jsonl")"
  run_flush "$d" --sweep
  [[ "$EC" == 0 ]] || log_fail "sweep after the real close must exit 0 (got $EC): $(cat "$OUT")"
  [[ "$(ledger_lines "$d")" == 1 ]] || log_fail "exactly one ledger line expected (ITEM-B via the real close event)"
  grep -qF '"ref_id":"ITEM-B"' "$d/docs/ai/METRICS.jsonl" || log_fail "the flushed line must be ITEM-B"
  grep -qE '^ {4}ITEM-B:' "$d/docs/ai/STATE.yaml" && log_fail "swept ITEM-B metrics entry must be removed from STATE"

  # Absent EVENTS.jsonl under --sweep -> every stranded ref fail-closed, and
  # sweep must never create the file (READ-ONLY invariant).
  local d2
  d2="$(mk_repo t109b)"
  write_sweep_state "$d2/docs/ai/STATE.yaml" "ITEM-F:done"
  rm -f "$d2/docs/ai/EVENTS.jsonl"
  run_flush "$d2" --sweep
  [[ "$EC" == 0 ]] || log_fail "absent-EVENTS sweep must still exit 0 (fail-closed, not a crash) (got $EC): $(cat "$OUT")"
  [[ "$(ledger_lines "$d2")" == 0 ]] || log_fail "absent-EVENTS sweep must flush nothing"
  [[ ! -f "$d2/docs/ai/EVENTS.jsonl" ]] || log_fail "sweep must never create EVENTS.jsonl"
  grep -qiF "no durable work_item_closed event" "$OUT" || log_fail "absent-EVENTS report must name the fail-closed reason: $(cat "$OUT")"
  log_pass "SEAM-1: real close-work-item.mjs -> sweep flushes it; absent EVENTS fail-closes and creates none (TEST-109)"
}

# --- retire-stranded-nonworkitem-metric: --retire (TEST-001..008) -------------
# SPEC-0075-spec-retire-stranded-nonworkitem-metric. Every fixture is a
# scratch temp-dir repo; the real docs/ai/{STATE.yaml,EVENTS.jsonl} are NEVER
# touched. None of these depend on the real pr-67-post-merge-review entry.

test_110_retire_stranded_ref() {  # TEST-001 (Spec-AC-04) + TEST-002 (Spec-AC-05)
  log_info "Test: --retire on a genuinely stranded ref removes it from STATE + appends one metric_retired event; payload carries reason + discarded_runs (TEST-001/TEST-002)..."
  local d
  d="$(mk_repo t110)"
  write_retire_state "$d/docs/ai/STATE.yaml" STRAY-0001
  # A stranded ref was never closed — EVENTS.jsonl absent before the retire.
  rm -f "$d/docs/ai/EVENTS.jsonl"
  run_flush "$d" --retire STRAY-0001 --reason "mis-recorded, not a work item"
  [[ "$EC" == 0 ]] || log_fail "retire of a stranded ref must exit 0 (got $EC): $(cat "$OUT")"
  # STATE: the entry and the now-empty metrics block are gone (surgical removal).
  grep -qE '^ {4}STRAY-0001:' "$d/docs/ai/STATE.yaml" && log_fail "retired metrics entry must be removed from STATE"
  grep -qE '^metrics:' "$d/docs/ai/STATE.yaml" && log_fail "emptied metrics block must be removed entirely"
  # EVENTS: exactly one metric_retired line appended for the ref.
  [[ -f "$d/docs/ai/EVENTS.jsonl" ]] || log_fail "retire must append the metric_retired event to EVENTS.jsonl"
  local n
  n="$(grep -cF '"event":"metric_retired","ref":"STRAY-0001"' "$d/docs/ai/EVENTS.jsonl" || true)"
  [[ "$n" == 1 ]] || log_fail "exactly one metric_retired event expected (got $n): $(cat "$d/docs/ai/EVENTS.jsonl")"
  # TEST-002: payload.reason + payload.discarded_runs field-exact.
  node -e '
    const fs = require("fs");
    const lines = fs.readFileSync(process.argv[1], "utf8").split("\n").filter(l => l.trim());
    const ev = lines.map(l => JSON.parse(l)).find(o => o.event === "metric_retired" && o.ref === "STRAY-0001");
    if (!ev) { console.error("no metric_retired event"); process.exit(1); }
    for (const k of ["v","ts","actor","event","ref","payload"]) if (!(k in ev)) { console.error("event missing key " + k); process.exit(1); }
    if (ev.payload.reason !== "mis-recorded, not a work item") { console.error("reason wrong: " + JSON.stringify(ev.payload.reason)); process.exit(1); }
    const dr = ev.payload.discarded_runs;
    const want = [
      {role:"Planning",model_id:"claude-sonnet-5",duration_seconds:120},
      {role:"Implementation",model_id:"claude-opus-4-8",duration_seconds:600},
    ];
    if (JSON.stringify(dr) !== JSON.stringify(want)) { console.error("discarded_runs mismatch: got " + JSON.stringify(dr)); process.exit(1); }
  ' "$d/docs/ai/EVENTS.jsonl" || log_fail "metric_retired payload wrong (reason + 2 compact discarded_runs)"
  # The mutated STATE is structurally valid.
  (cd "$PROJECT_ROOT" && node .aai/scripts/check-state.mjs "$d/docs/ai/STATE.yaml" > "$d/ck.log" 2>&1) \
    || log_fail "check-state must pass after retire: $(cat "$d/ck.log")"
  grep -qF "Retired: STRAY-0001" "$OUT" || log_fail "report must name the retired ref: $(cat "$OUT")"
  log_pass "Stranded ref retired: STATE entry removed, one metric_retired event with reason + 2 discarded_runs (TEST-001/TEST-002)"
}

test_111_retire_refused_default_flushable() {  # TEST-003 (Spec-AC-01)
  log_info "Test: --retire REFUSES a ref last_validation names with PASS; STATE + EVENTS byte-unchanged (TEST-003)..."
  local d
  d="$(mk_repo t111)"
  write_retire_state "$d/docs/ai/STATE.yaml" FLUSHABLE-0001 pass FLUSHABLE-0001
  : > "$d/docs/ai/EVENTS.jsonl"
  cp "$d/docs/ai/STATE.yaml" "$d/state.before"
  cp "$d/docs/ai/EVENTS.jsonl" "$d/events.before"
  run_flush "$d" --retire FLUSHABLE-0001
  [[ "$EC" == 1 ]] || log_fail "retire of a flushable ref must exit 1 (got $EC): $(cat "$OUT")"
  grep -qiF "would flush" "$OUT" || log_fail "refusal must say the ref would flush: $(cat "$OUT")"
  grep -qiF "last_validation" "$OUT" || log_fail "refusal must name last_validation as the reason: $(cat "$OUT")"
  cmp -s "$d/docs/ai/STATE.yaml" "$d/state.before" || log_fail "STATE must stay byte-identical on refusal"
  cmp -s "$d/docs/ai/EVENTS.jsonl" "$d/events.before" || log_fail "EVENTS must stay byte-identical on refusal"
  log_pass "Retire refuses a last_validation-PASS-named ref (fail-closed truth-gate), nothing written (TEST-003)"
}

test_112_retire_refused_sweep_flushable() {  # TEST-004 (Spec-AC-02)
  log_info "Test: --retire REFUSES a ref with a committed work_item_closed event (regardless of --sweep); no mutation (TEST-004)..."
  local d
  d="$(mk_repo t112)"
  write_retire_state "$d/docs/ai/STATE.yaml" CLOSED-0001
  write_closed_event "$d/docs/ai/EVENTS.jsonl" CLOSED-0001 "2026-07-15T10:30:00Z"
  cp "$d/docs/ai/STATE.yaml" "$d/state.before"
  cp "$d/docs/ai/EVENTS.jsonl" "$d/events.before"
  run_flush "$d" --retire CLOSED-0001
  [[ "$EC" == 1 ]] || log_fail "retire of a durably-closed ref must exit 1 (got $EC): $(cat "$OUT")"
  grep -qiF "would flush" "$OUT" || log_fail "refusal must say the ref would flush: $(cat "$OUT")"
  grep -qiF "work_item_closed" "$OUT" || log_fail "refusal must name the committed work_item_closed event: $(cat "$OUT")"
  cmp -s "$d/docs/ai/STATE.yaml" "$d/state.before" || log_fail "STATE must stay byte-identical on refusal"
  cmp -s "$d/docs/ai/EVENTS.jsonl" "$d/events.before" || log_fail "EVENTS must stay byte-identical on refusal (append-only, never rewritten)"
  log_pass "Retire refuses a ref with a committed work_item_closed event (sweep predicate, unconditional), nothing written (TEST-004)"
}

test_113_retire_refused_not_in_state() {  # TEST-005 (Spec-AC-03)
  log_info "Test: --retire REFUSES a ref absent from metrics.work_items; no mutation (TEST-005)..."
  local d
  d="$(mk_repo t113)"
  write_retire_state "$d/docs/ai/STATE.yaml" PRESENT-0001
  : > "$d/docs/ai/EVENTS.jsonl"
  cp "$d/docs/ai/STATE.yaml" "$d/state.before"
  cp "$d/docs/ai/EVENTS.jsonl" "$d/events.before"
  run_flush "$d" --retire NOT-A-REF
  [[ "$EC" == 1 ]] || log_fail "retire of an absent ref must exit 1 (got $EC): $(cat "$OUT")"
  grep -qiF "not present in metrics.work_items" "$OUT" || log_fail "refusal must say the ref is not present: $(cat "$OUT")"
  cmp -s "$d/docs/ai/STATE.yaml" "$d/state.before" || log_fail "STATE must stay byte-identical on refusal"
  cmp -s "$d/docs/ai/EVENTS.jsonl" "$d/events.before" || log_fail "EVENTS must stay byte-identical on refusal"
  log_pass "Retire refuses an absent ref with a clear message, nothing written (TEST-005)"
}

test_114_retire_dry_run() {  # TEST-006 (Spec-AC-06)
  log_info "Test: --dry-run --retire prints a plan for a retirable ref (writes nothing) and STILL refuses a flushable ref (no bypass) (TEST-006)..."
  local d
  # (a) retirable ref: plan printed, exit 0, nothing written.
  d="$(mk_repo t114a)"
  write_retire_state "$d/docs/ai/STATE.yaml" STRAY-0001
  rm -f "$d/docs/ai/EVENTS.jsonl"
  cp "$d/docs/ai/STATE.yaml" "$d/state.before"
  run_flush "$d" --dry-run --retire STRAY-0001 --reason "not a work item"
  [[ "$EC" == 0 ]] || log_fail "(a) dry-run retire of a retirable ref must exit 0 (got $EC): $(cat "$OUT")"
  node -e '
    const fs = require("fs");
    const raw = fs.readFileSync(process.argv[1], "utf8");
    const o = JSON.parse(raw.slice(raw.indexOf("{")));
    if (!o.dry_run) { console.error("plan must carry dry_run: true"); process.exit(1); }
    if (o.retire !== "STRAY-0001") { console.error("plan must name the ref"); process.exit(1); }
    if (!o.event || o.event.event !== "metric_retired" || o.event.ref !== "STRAY-0001") { console.error("plan must carry the would-be metric_retired event"); process.exit(1); }
  ' "$OUT" || log_fail "(a) dry-run must print the retire plan JSON: $(cat "$OUT")"
  cmp -s "$d/docs/ai/STATE.yaml" "$d/state.before" || log_fail "(a) dry-run must not touch STATE"
  [[ ! -f "$d/docs/ai/EVENTS.jsonl" ]] || log_fail "(a) dry-run must not create/append EVENTS.jsonl: $(cat "$d/docs/ai/EVENTS.jsonl" 2>/dev/null)"

  # (b) flushable ref: STILL refused, same exit/reason as the non-dry-run case,
  # no plan printed, nothing written.
  d="$(mk_repo t114b)"
  write_retire_state "$d/docs/ai/STATE.yaml" FLUSHABLE-0001 pass FLUSHABLE-0001
  : > "$d/docs/ai/EVENTS.jsonl"
  cp "$d/docs/ai/STATE.yaml" "$d/state.before"
  cp "$d/docs/ai/EVENTS.jsonl" "$d/events.before"
  run_flush "$d" --dry-run --retire FLUSHABLE-0001
  [[ "$EC" == 1 ]] || log_fail "(b) dry-run must NOT bypass the guard — a flushable ref must still exit 1 (got $EC): $(cat "$OUT")"
  grep -qiF "would flush" "$OUT" || log_fail "(b) dry-run refusal must name the would-flush reason: $(cat "$OUT")"
  grep -qiF "dry_run" "$OUT" && log_fail "(b) a refused dry-run must NOT print a plan: $(cat "$OUT")"
  cmp -s "$d/docs/ai/STATE.yaml" "$d/state.before" || log_fail "(b) refused dry-run must not touch STATE"
  cmp -s "$d/docs/ai/EVENTS.jsonl" "$d/events.before" || log_fail "(b) refused dry-run must not touch EVENTS"

  # (c) SWEEP-flushable ref (committed work_item_closed, NO last_validation PASS)
  # under --dry-run: the sweep predicate must still refuse — dry-run must not
  # bypass EITHER flushability predicate (code-review coverage-gap closure).
  d="$(mk_repo t114c)"
  write_retire_state "$d/docs/ai/STATE.yaml" CLOSED-0002
  write_closed_event "$d/docs/ai/EVENTS.jsonl" CLOSED-0002 "2026-07-15T10:30:00Z"
  cp "$d/docs/ai/STATE.yaml" "$d/state.before"
  cp "$d/docs/ai/EVENTS.jsonl" "$d/events.before"
  run_flush "$d" --dry-run --retire CLOSED-0002
  [[ "$EC" == 1 ]] || log_fail "(c) dry-run must NOT bypass the sweep predicate — a work_item_closed ref must still exit 1 (got $EC): $(cat "$OUT")"
  grep -qiF "work_item_closed" "$OUT" || log_fail "(c) dry-run sweep refusal must name the committed work_item_closed event: $(cat "$OUT")"
  grep -qiF "dry_run" "$OUT" && log_fail "(c) a refused dry-run must NOT print a plan: $(cat "$OUT")"
  cmp -s "$d/docs/ai/STATE.yaml" "$d/state.before" || log_fail "(c) refused dry-run must not touch STATE"
  cmp -s "$d/docs/ai/EVENTS.jsonl" "$d/events.before" || log_fail "(c) refused dry-run must not touch EVENTS"
  log_pass "Dry-run retire reports a retirable ref without writing, and still refuses a flushable ref via BOTH predicates (no bypass) (TEST-006)"
}

test_116_retire_documented_not_in_prompt() {  # TEST-008 (Spec-AC-08)
  log_info "Test: --retire/--reason documented in metrics-flush.mjs header + usage; METRICS_FLUSH.prompt.md still lacks the literal work_item_closed (TEST-008)..."
  # (a) top-of-file comment block (before the first import) documents both flags.
  local header
  header="$(sed -n '1,/^import /p' "$FLUSH")"
  assert_payload_contains "$header" "--retire" "top-of-file comment must document --retire"
  assert_payload_contains "$header" "--reason" "top-of-file comment must document --reason"
  # (b) unknown-flag usage string lists --retire (grep the parseArgs fail text).
  local usage_out usage_ec=0
  usage_out="$( (cd "$PROJECT_ROOT" && node .aai/scripts/metrics-flush.mjs --bogus-flag 2>&1) )" || usage_ec=$?
  [[ "$usage_ec" == 2 ]] || log_fail "unknown flag must exit 2 (got $usage_ec): $usage_out"
  assert_payload_contains "$usage_out" "--retire" "unknown-flag usage string must list --retire: $usage_out"
  # (c) SPEC-0054 negative invariant re-verified locally: the prompt file must
  # NOT carry the literal work_item_closed (documenting retire's guard there
  # would risk reintroducing it — retire is documented in the script only).
  local prompt="$PROJECT_ROOT/.aai/METRICS_FLUSH.prompt.md"
  [[ -f "$prompt" ]] || log_fail "missing $prompt"
  grep -qF "work_item_closed" "$prompt" && log_fail "METRICS_FLUSH.prompt.md must NOT contain the literal work_item_closed (SPEC-0054)"
  log_pass "--retire/--reason documented in the script only; prompt file free of work_item_closed (TEST-008)"
}

# --- token-capture-canary: 3-way per-run classification (spec TEST-001..003) ---
# SPEC-0085-spec-token-capture-canary.md Spec-AC-01. buildEntry() classifies
# every agent_run into exactly one of decomposed | undecomposed-note |
# capture-missing; decomposed emits neither line, undecomposed-note emits one
# INFO line (naming ref/role/N), capture-missing emits one WARNING (naming
# ref/role) -- never both for the same run.

test_117_classify_decomposed() {
  log_info "Test: a run with numeric tokens_in/out (decomposed) emits NEITHER an INFO nor a WARNING line (spec TEST-001)..."
  local d
  d="$(mk_repo t117)"
  write_flush_state "$d/docs/ai/STATE.yaml" single
  # write_flush_state's default 4 runs all carry numeric tokens_in/out already.
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "flush must exit 0 (got $EC): $(cat "$OUT")"
  grep -qE '^(INFO|WARNING) CHANGE-0001 run ' "$OUT" \
    && log_fail "decomposed runs (numeric tokens) must emit NO classification line: $(cat "$OUT")"
  log_pass "Decomposed runs (numeric tokens) emit no INFO/WARNING classification line (spec TEST-001)"
}

test_118_classify_undecomposed_note() {
  log_info "Test: null-token run with a usage_total_tokens=N note emits exactly one INFO line naming ref/role/N; no WARNING (spec TEST-002)..."
  local d
  d="$(mk_repo t118)"
  write_flush_state "$d/docs/ai/STATE.yaml" single
  node -e '
    const fs = require("fs"); const p = process.argv[1];
    let s = fs.readFileSync(p, "utf8");
    // Null run2 (Implementation) tokens and attach an undecomposed-total note.
    s = s.replace("          tokens_in: 2000000\n          tokens_out: 200000\n          cost_usd: null",
                  "          tokens_in: null\n          tokens_out: null\n          cost_usd: null\n          note: usage_total_tokens=262134 (harness total; in/out not exposed)");
    fs.writeFileSync(p, s);
  ' "$d/docs/ai/STATE.yaml"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "flush must exit 0 (got $EC): $(cat "$OUT")"
  local n
  n="$(grep -cE '^INFO CHANGE-0001 run Implementation' "$OUT" || true)"
  [[ "$n" == 1 ]] || log_fail "exactly one INFO line expected for the undecomposed-note run (got $n): $(cat "$OUT")"
  # telemetry-fields-not-prose review NON-BLOCKING-5 (20260913T114019Z,
  # finding 5): sonnet-latest resolves to a PRICED model, so D5 blends a real
  # cost_usd for this run — the line must say so (basis total-blended), never
  # the stale "unattributable by design" wording beside an attributed cost.
  grep -qE '^INFO CHANGE-0001 run Implementation \(sonnet-latest\): undecomposed total 262134 observed; cost estimated from the total \(cost_basis total-blended\)' "$OUT" \
    || log_fail "INFO line must name ref/role, the observed total, and the TRUE basis (blended, since sonnet-latest prices): $(cat "$OUT")"
  grep -qF '"cost_usd":2.359206,"cost_basis":"total-blended"' "$d/docs/ai/METRICS.jsonl" \
    || log_fail "the ledger must actually carry the blended cost the INFO line now describes: $(cat "$d/docs/ai/METRICS.jsonl")"
  grep -qE '^WARNING CHANGE-0001 run Implementation' "$OUT" \
    && log_fail "an undecomposed-note run must NOT also emit the generic capture-missing WARNING: $(cat "$OUT")"
  log_pass "Undecomposed-note run emits exactly one INFO line naming ref/role/N; no WARNING (spec TEST-002)"
}

test_119_classify_capture_missing() {
  log_info "Test: null-token run with no usage note emits exactly one capture-missing WARNING naming ref/role (spec TEST-003)..."
  local d
  d="$(mk_repo t119)"
  write_flush_state "$d/docs/ai/STATE.yaml" single
  node -e '
    const fs = require("fs"); const p = process.argv[1];
    let s = fs.readFileSync(p, "utf8");
    s = s.replace("          tokens_in: 1000000\n          tokens_out: 1000000\n          cost_usd: null",
                  "          tokens_in: null\n          tokens_out: null\n          cost_usd: null");
    fs.writeFileSync(p, s);
  ' "$d/docs/ai/STATE.yaml"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "flush must exit 0 (got $EC): $(cat "$OUT")"
  local n
  n="$(grep -cE '^WARNING CHANGE-0001 run Validation' "$OUT" || true)"
  [[ "$n" == 1 ]] || log_fail "exactly one capture-missing WARNING expected for the null-token/no-note run (got $n): $(cat "$OUT")"
  grep -qE '^WARNING CHANGE-0001 run Validation \(claude-sonnet-5-20260101\): cost unattributable' "$OUT" \
    || log_fail "WARNING must name ref/role/model with the cost-unattributable wording: $(cat "$OUT")"
  grep -qE '^INFO CHANGE-0001 run Validation' "$OUT" \
    && log_fail "a capture-missing run must NOT also emit an INFO line: $(cat "$OUT")"
  log_pass "Capture-missing run (null tokens, no note) emits exactly one WARNING naming ref/role (spec TEST-003)"
}

# --- token-economics-end-to-end TEST-001..004 --------------------------------
# (SPEC-0089-spec-token-economics-end-to-end). TEST-003/TEST-004 are the
# integrity-critical rows (RED-proof obligation).

# write_ledger_line <file> <ref> <title> <notes-json...> — appends one raw
# METRICS.jsonl line with N runs, each carrying the given note text (role
# Run<i>, no tokens_in/out, cost_usd null). $1 file, $2 ref, $3 title, then
# one note string per run (pass '' for a run with no note field).
write_ledger_line() {
  local f="$1" ref="$2" title="$3"
  shift 3
  node -e '
    const fs = require("fs");
    const [file, ref, title, ...notes] = process.argv.slice(1);
    const runs = notes.map((n, i) => {
      const r = { role: `Run${i}`, model_id: "m", started_utc: null, ended_utc: null,
        duration_seconds: null, tokens_in: null, tokens_out: null, cost_usd: null };
      if (n !== "") r.note = n;
      return r;
    });
    const entry = { date_utc: "2026-07-20", ref_id: ref, title,
      human_time_minutes: { intake: 0, reviews: 0 }, agent_runs: runs,
      totals: { human_time_minutes: 0, agent_duration_seconds: 0, total_cost_usd: null },
      verdict: "PASS" };
    fs.appendFileSync(file, JSON.stringify(entry) + "\n");
  ' "$f" "$ref" "$title" "$@"
}

test_120_shared_lib_grep_contract() {  # token-economics TEST-003 (Spec-AC-01)
  log_info "Test: USAGE_NOTE_RE lives in exactly one source file (lib/usage-note.mjs); flush + report import it, never re-declare it (token-economics TEST-003)..."
  local hits n
  hits="$(grep -rlF 'usage_total_tokens=(\d+)' "$PROJECT_ROOT/.aai/scripts" 2>/dev/null || true)"
  n="$(printf '%s\n' "$hits" | grep -c . || true)"
  [[ "$n" == "1" ]] || log_fail "raw usage-note regex literal must exist in exactly one file (got $n): $hits"
  assert_payload_contains "$hits" ".aai/scripts/lib/usage-note.mjs" "the single source file must be .aai/scripts/lib/usage-note.mjs (got: $hits)"
  grep -qE "from '\\./lib/usage-note\\.mjs'" "$PROJECT_ROOT/.aai/scripts/metrics-flush.mjs" \
    || log_fail "metrics-flush.mjs must import from lib/usage-note.mjs"
  grep -qE "USAGE_NOTE_RE" "$PROJECT_ROOT/.aai/scripts/metrics-flush.mjs" \
    || log_fail "metrics-flush.mjs must reference USAGE_NOTE_RE (imported, not inlined)"
  grep -qE "from '\\./lib/usage-note\\.mjs'" "$PROJECT_ROOT/.aai/scripts/metrics-report.mjs" \
    || log_fail "metrics-report.mjs must import from lib/usage-note.mjs"
  log_pass "Single-source marker grammar: exactly one raw regex literal (lib/usage-note.mjs); flush + report both import it (token-economics TEST-003)"
}

test_121_seam_marker_agreement() {  # token-economics TEST-004 (Spec-AC-01, SEAM 1)
  log_info "Test: SEAM — a note flush classifies undecomposed-INFO is counted by report; a malformed note flush drops is ignored by report (all consumers agree) (token-economics TEST-004)..."
  local d
  d="$(mk_repo t121)"
  write_flush_state "$d/docs/ai/STATE.yaml" single
  node -e '
    const fs = require("fs"); const p = process.argv[1];
    let s = fs.readFileSync(p, "utf8");
    // Implementation run (was numeric 2000000/200000): null tokens + a VALID marker note.
    s = s.replace("          tokens_in: 2000000\n          tokens_out: 200000\n          cost_usd: null",
                  "          tokens_in: null\n          tokens_out: null\n          cost_usd: null\n          note: usage_total_tokens=262134 (harness total; in/out not exposed)");
    // Validation run (was numeric 1000000/1000000): null tokens + a MALFORMED marker note.
    s = s.replace("          tokens_in: 1000000\n          tokens_out: 1000000\n          cost_usd: null",
                  "          tokens_in: null\n          tokens_out: null\n          cost_usd: null\n          note: usage_total_tokens=999x (malformed on purpose)");
    fs.writeFileSync(p, s);
  ' "$d/docs/ai/STATE.yaml"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "flush must exit 0 (got $EC): $(cat "$OUT")"
  grep -qE '^INFO CHANGE-0001 run Implementation \(sonnet-latest\): undecomposed total 262134 observed' "$OUT" \
    || log_fail "flush must classify the valid-marker run as undecomposed-INFO: $(cat "$OUT")"
  grep -qE '^WARNING CHANGE-0001 run Validation' "$OUT" \
    || log_fail "flush must classify the malformed-marker run as capture-missing WARNING (malformed is not an honest total): $(cat "$OUT")"

  local rep_out="$d/report.md"
  (cd "$PROJECT_ROOT" && node .aai/scripts/metrics-report.mjs --metrics "$d/docs/ai/METRICS.jsonl" --pricing "$d/PRICING.yaml") > "$rep_out" \
    || log_fail "report must exit 0 on the flushed ledger: $(cat "$rep_out")"
  grep -qE '^\| CHANGE-0001 \|.*\| 262134 \|' "$rep_out" \
    || log_fail "report's per-item undecomposed-token column must equal the flush-classified total 262134, malformed dropped (got): $(cat "$rep_out")"
  log_pass "Seam: flush's undecomposed-INFO total (262134) is counted by report; the malformed note flush drops is ignored by report — all consumers agree (token-economics TEST-004)"
}

test_122_report_per_item_undecomposed_column() {  # token-economics TEST-001 (Spec-AC-02)
  log_info "Test: Per Work Item undecomposed-token column sums valid markers, ignores malformed + prefixed markers, n/a when none (token-economics TEST-001)..."
  local d="$TEST_DIR/t122"
  mkdir -p "$d"
  write_pricing "$d/PRICING.yaml"
  : > "$d/METRICS.jsonl"
  write_ledger_line "$d/METRICS.jsonl" "BBB-0001" "Multi-run" \
    'usage_total_tokens=1000 (ok)' 'not_usage_total_tokens=5000 (prefixed key, ignored)'
  write_ledger_line "$d/METRICS.jsonl" "BBB-0002" "Malformed only" \
    'usage_total_tokens=42x (malformed value, ignored)'
  write_ledger_line "$d/METRICS.jsonl" "BBB-0003" "No notes" '' ''
  local out="$d/out.md"
  (cd "$PROJECT_ROOT" && node .aai/scripts/metrics-report.mjs --metrics "$d/METRICS.jsonl" --pricing "$d/PRICING.yaml") > "$out" \
    || log_fail "report must exit 0: $(cat "$out")"
  grep -qE '^\| BBB-0001 \|.*\| 1000 \|' "$out" \
    || log_fail "BBB-0001 (1 valid + 1 prefixed-ignored) must sum to 1000: $(cat "$out")"
  grep -qE '^\| BBB-0002 \|.*\| n/a \|' "$out" \
    || log_fail "BBB-0002 (malformed value only) must render n/a: $(cat "$out")"
  grep -qE '^\| BBB-0003 \|.*\| n/a \|' "$out" \
    || log_fail "BBB-0003 (no notes) must render n/a: $(cat "$out")"
  log_pass "Per Work Item undecomposed-token column sums valid markers, drops malformed/prefixed, n/a when none (token-economics TEST-001)"
}

test_123_report_per_role_token_rollup() {  # token-economics TEST-002 (Spec-AC-03)
  log_info "Test: per-role token rollup section sums valid markers by role; tokens only, never a USD figure from undecomposed totals (token-economics TEST-002)..."
  local d="$TEST_DIR/t123"
  mkdir -p "$d"
  write_pricing "$d/PRICING.yaml"
  cat > "$d/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-20","ref_id":"CCC-0001","title":"One","human_time_minutes":{"intake":0,"reviews":0},"agent_runs":[{"role":"Implementation","model_id":"m","tokens_in":null,"tokens_out":null,"cost_usd":null,"note":"usage_total_tokens=700 (a)"}],"totals":{"human_time_minutes":0,"agent_duration_seconds":0,"total_cost_usd":null},"verdict":"PASS"}
{"date_utc":"2026-07-21","ref_id":"CCC-0002","title":"Two","human_time_minutes":{"intake":0,"reviews":0},"agent_runs":[{"role":"Implementation","model_id":"m","tokens_in":null,"tokens_out":null,"cost_usd":null,"note":"usage_total_tokens=300 (b)"},{"role":"Validation","model_id":"m","tokens_in":null,"tokens_out":null,"cost_usd":null,"note":"usage_total_tokens=1x (malformed)"}],"totals":{"human_time_minutes":0,"agent_duration_seconds":0,"total_cost_usd":null},"verdict":"PASS"}
JSONL
  local out="$d/out.md"
  (cd "$PROJECT_ROOT" && node .aai/scripts/metrics-report.mjs --metrics "$d/METRICS.jsonl" --pricing "$d/PRICING.yaml") > "$out" \
    || log_fail "report must exit 0: $(cat "$out")"
  grep -qE '^### Per-Role Token Rollup' "$out" \
    || log_fail "report must render a Per-Role Token Rollup section: $(cat "$out")"
  grep -qE '^\| Implementation \| 1000 \|' "$out" \
    || log_fail "Implementation role must sum 700+300=1000 across items: $(cat "$out")"
  grep -qE '^\| Validation \| n/a \|' "$out" \
    || log_fail "Validation role (malformed-only marker) must render n/a: $(cat "$out")"
  awk '/^### Per-Role Token Rollup/,/^### Per-Strategy Reliability/' "$out" | grep -qE '\$[0-9]' \
    && log_fail "the per-role token rollup section must NEVER render a USD figure from undecomposed totals: $(cat "$out")"
  log_pass "Per-role token rollup sums valid markers by role, tokens only, never fabricates USD (token-economics TEST-002)"
}

test_124_flush_prompt_hash_passthrough() {  # prompt-hash-telemetry TEST-005 / Spec-AC-03
  log_info "Test: flush copies prompt_hash into the ledger byte-unchanged when present; a sibling run without it gets no prompt_hash key (prompt-hash-telemetry TEST-005)..."
  local d
  d="$(mk_repo t124)"
  write_flush_state "$d/docs/ai/STATE.yaml" single
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  write_golden_doc "$d"
  local h="deadbeefcafe1234567890abcdef1234567890abcdef1234567890abcdef12"
  node -e '
    const fs = require("fs");
    const p = process.argv[1];
    const hash = process.argv[2];
    let s = fs.readFileSync(p, "utf8");
    s = s.replace(
      "          cost_usd: null\n        - role: Implementation",
      "          cost_usd: null\n          prompt_hash: " + hash + "\n        - role: Implementation"
    );
    fs.writeFileSync(p, s);
  ' "$d/docs/ai/STATE.yaml" "$h"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "flush must exit 0 (got $EC): $(cat "$OUT")"
  grep -v -e '^#' -e '^$' "$d/docs/ai/METRICS.jsonl" > "$d/got.jsonl"
  node -e '
    const o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8").trim());
    const hash = process.argv[2];
    const planning = o.agent_runs[0];
    const impl = o.agent_runs[1];
    if (planning.role !== "Planning" || planning.prompt_hash !== hash) {
      console.error("Planning run prompt_hash mismatch: " + JSON.stringify(planning)); process.exit(1);
    }
    if (impl.role !== "Implementation" || Object.prototype.hasOwnProperty.call(impl, "prompt_hash")) {
      console.error("Implementation run (no prompt_hash in STATE) must carry NO prompt_hash key: " + JSON.stringify(impl)); process.exit(1);
    }
  ' "$d/got.jsonl" "$h" || log_fail "prompt_hash passthrough wrong: $(cat "$d/got.jsonl")"
  log_pass "flush copies prompt_hash byte-unchanged when present; omits the key entirely when absent (prompt-hash-telemetry TEST-005)"
}

test_125_flush_seam1_append_run_prompt_hash() {  # prompt-hash-telemetry TEST-007 (SEAM-1, integration)
  log_info "Test: SEAM-1 — real append-run --prompt-hash then real flush; ledger line carries the exact hash (prompt-hash-telemetry TEST-007)..."
  local d
  d="$(mk_repo t125)"
  write_flush_state "$d/docs/ai/STATE.yaml" single
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  write_golden_doc "$d"
  local h now
  h="feedface0011223344556677889900aabbccddeeff00112233445566778899"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  (cd "$PROJECT_ROOT" && node .aai/scripts/state.mjs --state "$d/docs/ai/STATE.yaml" \
      append-run --ref CHANGE-0001 --role "TDD Implementation" --model claude-test \
      --started "$now" --prompt-hash "$h" > "$d/append.log" 2>&1) \
    || log_fail "seam fixture: real append-run --prompt-hash must exit 0: $(cat "$d/append.log")"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "flush must exit 0 (got $EC): $(cat "$OUT")"
  grep -v -e '^#' -e '^$' "$d/docs/ai/METRICS.jsonl" > "$d/got.jsonl"
  node -e '
    const o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8").trim());
    const hash = process.argv[2];
    const run = o.agent_runs.find(r => r.role === "TDD Implementation");
    if (!run || run.prompt_hash !== hash) {
      console.error("SEAM-1: TDD Implementation run must carry the exact appended hash: " + JSON.stringify(run)); process.exit(1);
    }
  ' "$d/got.jsonl" "$h" || log_fail "SEAM-1 append-run -> flush hash mismatch: $(cat "$d/got.jsonl")"
  log_pass "SEAM-1: real append-run --prompt-hash -> real flush -> exact hash in the emitted ledger line (prompt-hash-telemetry TEST-007)"
}

test_126_report_prompt_versions_multi_hash() {  # prompt-hash-telemetry TEST-008 (SEAM-2, integration)
  log_info "Test: SEAM-2 — multi-hash ledger fixture yields a Prompt versions section grouping run counts by hash per role (prompt-hash-telemetry TEST-008)..."
  local d="$TEST_DIR/t126"
  mkdir -p "$d"
  write_pricing "$d/PRICING.yaml"
  cat > "$d/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-20","ref_id":"DDD-0001","title":"One","human_time_minutes":{"intake":0,"reviews":0},"agent_runs":[{"role":"Implementation","model_id":"m","tokens_in":null,"tokens_out":null,"cost_usd":null,"prompt_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}],"totals":{"human_time_minutes":0,"agent_duration_seconds":0,"total_cost_usd":null},"verdict":"PASS"}
{"date_utc":"2026-07-21","ref_id":"DDD-0002","title":"Two","human_time_minutes":{"intake":0,"reviews":0},"agent_runs":[{"role":"Implementation","model_id":"m","tokens_in":null,"tokens_out":null,"cost_usd":null,"prompt_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},{"role":"Implementation","model_id":"m","tokens_in":null,"tokens_out":null,"cost_usd":null,"prompt_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}],"totals":{"human_time_minutes":0,"agent_duration_seconds":0,"total_cost_usd":null},"verdict":"PASS"}
{"date_utc":"2026-07-22","ref_id":"DDD-0003","title":"Three","human_time_minutes":{"intake":0,"reviews":0},"agent_runs":[{"role":"Validation","model_id":"m","tokens_in":null,"tokens_out":null,"cost_usd":null,"prompt_hash":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}],"totals":{"human_time_minutes":0,"agent_duration_seconds":0,"total_cost_usd":null},"verdict":"PASS"}
JSONL
  local out="$d/out.md"
  (cd "$PROJECT_ROOT" && node .aai/scripts/metrics-report.mjs --metrics "$d/METRICS.jsonl" --pricing "$d/PRICING.yaml") > "$out" \
    || log_fail "report must exit 0: $(cat "$out")"
  grep -qE '^### Prompt versions' "$out" \
    || log_fail "multi-hash ledger must render a Prompt versions section: $(cat "$out")"
  grep -qE '^\| Implementation \| aaaaaaaaaaaa \| 2 \|' "$out" \
    || log_fail "Implementation/aaaaaaaaaaaa must count 2 runs: $(cat "$out")"
  grep -qE '^\| Implementation \| bbbbbbbbbbbb \| 1 \|' "$out" \
    || log_fail "Implementation/bbbbbbbbbbbb must count 1 run: $(cat "$out")"
  awk '/^### Prompt versions/,0' "$out" | grep -qE '^\| Validation ' \
    && log_fail "Validation has only ONE distinct hash — it must NOT appear in the Prompt versions grouping: $(cat "$out")"
  log_pass "SEAM-2: multi-hash ledger -> Prompt versions section groups run counts by hash per role (prompt-hash-telemetry TEST-008)"
}

test_127_report_no_prompt_versions_single_hash() {  # prompt-hash-telemetry TEST-009 / Spec-AC-04
  log_info "Test: single-hash-per-role ledger yields NO Prompt versions section; report otherwise unchanged (prompt-hash-telemetry TEST-009)..."
  local d="$TEST_DIR/t127"
  mkdir -p "$d"
  write_pricing "$d/PRICING.yaml"
  cat > "$d/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-20","ref_id":"EEE-0001","title":"One","human_time_minutes":{"intake":0,"reviews":0},"agent_runs":[{"role":"Implementation","model_id":"m","tokens_in":null,"tokens_out":null,"cost_usd":null,"prompt_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}],"totals":{"human_time_minutes":0,"agent_duration_seconds":0,"total_cost_usd":null},"verdict":"PASS"}
{"date_utc":"2026-07-21","ref_id":"EEE-0002","title":"Two","human_time_minutes":{"intake":0,"reviews":0},"agent_runs":[{"role":"Implementation","model_id":"m","tokens_in":null,"tokens_out":null,"cost_usd":null,"prompt_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}],"totals":{"human_time_minutes":0,"agent_duration_seconds":0,"total_cost_usd":null},"verdict":"PASS"}
JSONL
  local out="$d/out.md" out_nohash="$d/out-nohash.md"
  (cd "$PROJECT_ROOT" && node .aai/scripts/metrics-report.mjs --metrics "$d/METRICS.jsonl" --pricing "$d/PRICING.yaml") > "$out" \
    || log_fail "report must exit 0: $(cat "$out")"
  grep -qE '^### Prompt versions' "$out" \
    && log_fail "a single hash per role must NEVER render a Prompt versions section: $(cat "$out")"

  # Report otherwise unchanged: an identical ledger with NO prompt_hash field
  # at all must render byte-identical output (module the fixture's own hash
  # section which never fires here either way).
  sed 's/,"prompt_hash":"[0-9a-f]*"//' "$d/METRICS.jsonl" > "$d/METRICS-nohash.jsonl"
  (cd "$PROJECT_ROOT" && node .aai/scripts/metrics-report.mjs --metrics "$d/METRICS-nohash.jsonl" --pricing "$d/PRICING.yaml") > "$out_nohash" \
    || log_fail "report (no prompt_hash field at all) must exit 0: $(cat "$out_nohash")"
  diff -u "$out_nohash" "$out" \
    || log_fail "report output must be identical whether or not prompt_hash is present, when no role has >1 hash: $(diff "$out_nohash" "$out")"
  log_pass "Single hash per role -> no Prompt versions section; report output otherwise unchanged (prompt-hash-telemetry TEST-009)"
}

# --- R-GUARD Stage 2/3: flush-time forensic WARNs (SPEC-0113) -----------------

# rewrite implementation_strategy.{selected,source} on a fixture via the real
# writer (state.mjs set-strategy) — the sanctioned provenance path.
set_strategy_source() {  # <state-file> <selected> <source> [rationale]
  local f="$1" sel="$2" src="$3" rat="${4:-}"
  local args=(set-strategy --selected "$sel" --source "$src")
  [[ -n "$rat" ]] && args+=(--rationale "$rat")
  (cd "$PROJECT_ROOT" && node .aai/scripts/state.mjs --state "$f" "${args[@]}") >/dev/null 2>&1
}

test_133_model_marker_grep_contract() {  # validation-cost-calibration spec TEST-008 (Spec-AC-04)
  log_info "Test: REQUESTED_MODEL_RE/ACTUAL_MODEL_RE raw regex literals each live in exactly one file, lib/usage-note.mjs (spec TEST-008)..."
  local hits n
  hits="$(grep -rlF 'requested_model=' "$PROJECT_ROOT/.aai/scripts" 2>/dev/null || true)"
  n="$(printf '%s\n' "$hits" | grep -c . || true)"
  [[ "$n" == "1" ]] || log_fail "requested_model= raw regex literal must exist in exactly one file (got $n): $hits"
  assert_payload_contains "$hits" ".aai/scripts/lib/usage-note.mjs" "the single source file for requested_model= must be .aai/scripts/lib/usage-note.mjs (got: $hits)"

  hits="$(grep -rlF 'actual_model=' "$PROJECT_ROOT/.aai/scripts" 2>/dev/null || true)"
  n="$(printf '%s\n' "$hits" | grep -c . || true)"
  [[ "$n" == "1" ]] || log_fail "actual_model= raw regex literal must exist in exactly one file (got $n): $hits"
  assert_payload_contains "$hits" ".aai/scripts/lib/usage-note.mjs" "the single source file for actual_model= must be .aai/scripts/lib/usage-note.mjs (got: $hits)"

  log_pass "requested_model=/actual_model= raw regex literals: exactly one file each, lib/usage-note.mjs (TEST-133/spec TEST-008)"
}

test_130_rguard_flush_provenance_warn() {  # r-guard TEST-RG-FLUSH-05 / Spec-AC-05
  log_info "Test: flush WARNs when implementation_strategy.source is not intake/spec-path; silent when sanctioned (r-guard Spec-AC-05)..."
  local d n
  # (a) SANCTIONED source (a spec .md path, the default fixture) -> SILENT.
  d="$(mk_repo t130a)"
  write_flush_state "$d/docs/ai/STATE.yaml" single
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  write_golden_doc "$d"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "(a) flush must exit 0 (got $EC): $(cat "$OUT")"
  n="$(grep -c 'strategy provenance' "$OUT" || true)"
  [[ "$n" == 0 ]] || log_fail "(a) sanctioned source must emit NO provenance WARN (got $n): $(cat "$OUT")"

  # (b) NON-sanctioned source with a normal (non-downgrade) lane -> exactly one
  #     provenance WARNING naming the flushed ref. Still flushes (verdict PASS).
  d="$(mk_repo t130b)"
  write_flush_state "$d/docs/ai/STATE.yaml" single
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  write_golden_doc "$d"
  set_strategy_source "$d/docs/ai/STATE.yaml" tdd subagent-injected
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "(b) flush must still exit 0 (WARN never blocks) (got $EC): $(cat "$OUT")"
  n="$(grep -c 'strategy provenance' "$OUT" || true)"
  [[ "$n" == 1 ]] || log_fail "(b) exactly one provenance WARNING expected (got $n): $(cat "$OUT")"
  grep -qF 'CHANGE-0001' "$OUT" || log_fail "(b) provenance WARN must name the flushed ref: $(cat "$OUT")"
  grep -qF 'subagent-injected' "$OUT" || log_fail "(b) provenance WARN must quote the suspicious source: $(cat "$OUT")"
  [[ "$(ledger_lines "$d")" == 1 ]] || log_fail "(b) WARN-only: the ride must still flush one ledger line"
  log_pass "R-GUARD Stage 2: flush WARNs on non-sanctioned strategy source; silent on a spec-path source (Spec-AC-05)"
}

test_131_rguard_flush_rigor_downgrade() {  # r-guard TEST-RG-FLUSH-06 / Spec-AC-06
  log_info "Test: a downgrade lane (untested) with a non-sanctioned source is flagged as a rigor-downgrade risk; a sanctioned one is not (r-guard Spec-AC-06)..."
  local d n
  # (a) untested + NON-sanctioned source -> rigor-downgrade WARNING (SPEC-0109 RR-3).
  d="$(mk_repo t131a)"
  write_flush_state "$d/docs/ai/STATE.yaml" single
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  write_golden_doc "$d"
  set_strategy_source "$d/docs/ai/STATE.yaml" untested leaked-by-subagent "no reason (injected)"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "(a) flush must exit 0 (got $EC): $(cat "$OUT")"
  n="$(grep -c 'rigor-downgrade' "$OUT" || true)"
  [[ "$n" == 1 ]] || log_fail "(a) exactly one rigor-downgrade WARNING expected (got $n): $(cat "$OUT")"
  grep -qF 'CHANGE-0001' "$OUT" || log_fail "(a) rigor-downgrade WARN must name the flushed ref: $(cat "$OUT")"

  # (b) untested + SANCTIONED source (intake) -> NOT flagged as a downgrade risk.
  d="$(mk_repo t131b)"
  write_flush_state "$d/docs/ai/STATE.yaml" single
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  write_golden_doc "$d"
  set_strategy_source "$d/docs/ai/STATE.yaml" untested intake "operator chose the no-tests lane at intake"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "(b) flush must exit 0 (got $EC): $(cat "$OUT")"
  n="$(grep -c 'rigor-downgrade' "$OUT" || true)"
  [[ "$n" == 0 ]] || log_fail "(b) a sanctioned-source untested lane must NOT be flagged (got $n): $(cat "$OUT")"
  log_pass "R-GUARD Stage 3: downgrade lane + bad source flagged as rigor-downgrade risk; sanctioned lane silent (Spec-AC-06)"
}

test_132_rguard_events_appendonly() {  # r-guard TEST-RG-FLUSH-07 / Spec-AC-07
  log_info "Test: flush flags a docs/ai/EVENTS.jsonl that shrank vs HEAD; append-only + non-git are silent (r-guard Spec-AC-07)..."
  local d n
  # (a) committed EVENTS with 3 lines, working tree truncated to 1 -> WARN.
  d="$(mk_repo t132a)"
  git init -q "$d"
  git -C "$d" config user.email test@example.com
  git -C "$d" config user.name "AAI Test"
  printf 'a\nb\nc\n' > "$d/docs/ai/EVENTS.jsonl"
  git -C "$d" add docs/ai/EVENTS.jsonl >/dev/null 2>&1
  git -C "$d" commit -q -m "seed events" >/dev/null 2>&1
  printf 'a\n' > "$d/docs/ai/EVENTS.jsonl"   # truncation (append-only violation)
  write_flush_state "$d/docs/ai/STATE.yaml" single
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  write_golden_doc "$d"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "(a) flush must exit 0 (WARN never blocks) (got $EC): $(cat "$OUT")"
  n="$(grep -c 'EVENTS append-only' "$OUT" || true)"
  [[ "$n" == 1 ]] || log_fail "(a) exactly one EVENTS append-only WARNING expected on a shrink (got $n): $(cat "$OUT")"

  # (b) append-only working tree (>= HEAD) -> SILENT.
  d="$(mk_repo t132b)"
  git init -q "$d"
  git -C "$d" config user.email test@example.com
  git -C "$d" config user.name "AAI Test"
  printf 'a\nb\n' > "$d/docs/ai/EVENTS.jsonl"
  git -C "$d" add docs/ai/EVENTS.jsonl >/dev/null 2>&1
  git -C "$d" commit -q -m "seed events" >/dev/null 2>&1
  printf 'a\nb\nc\n' > "$d/docs/ai/EVENTS.jsonl"   # append (allowed)
  write_flush_state "$d/docs/ai/STATE.yaml" single
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  write_golden_doc "$d"
  run_flush "$d"
  n="$(grep -c 'EVENTS append-only' "$OUT" || true)"
  [[ "$n" == 0 ]] || log_fail "(b) an append-only EVENTS tree must NOT warn (got $n): $(cat "$OUT")"

  # (c) non-git fixture -> degrade SILENT (no false WARN, no hard git dependency).
  d="$(mk_repo t132c)"
  printf 'a\nb\n' > "$d/docs/ai/EVENTS.jsonl"
  write_flush_state "$d/docs/ai/STATE.yaml" single
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  write_golden_doc "$d"
  run_flush "$d"
  n="$(grep -c 'EVENTS append-only' "$OUT" || true)"
  [[ "$n" == 0 ]] || log_fail "(c) a non-git fixture must degrade silently (got $n): $(cat "$OUT")"
  log_pass "R-GUARD Stage 3: EVENTS.jsonl shrink vs HEAD flagged; append-only + non-git silent (Spec-AC-07)"
}

# --- telemetry-fields-not-prose: TEST-135..143 --------------------------------
#
# write_gate_state <file> <ref> <vstatus> <vref> <agent_runs_yaml> [extra_ref_block]
# — a LEAN gate-focused STATE fixture (modeled on write_retire_state/
# write_sweep_state above): current_focus/active_work_items empty,
# code_review.required false (so the review-required arm of the default gate
# never fires here — isolates the verdict-admission gate this scope adds),
# last_validation at $vstatus/$vref, and metrics.work_items.<ref>.agent_runs
# set to the caller's own YAML block (each line already correctly indented).
# $6, when given, is spliced in as a SIBLING of agent_runs (e.g. a `validation:`
# per-ref block, D6/D7). $7, when given, overrides last_validation.run_at_utc
# (default null) — needed to exercise BLOCKING-1's source (ii) corroboration
# arm with a REAL timestamp (validation round-4 NON-BLOCKING-1: a hardcoded
# null here routed source (ii) through the unconditional fail-closed branch
# and masked the ts-comparison mutation for every prior TEST-144 fixture).
write_gate_state() {
  local f="$1" ref="$2" vstatus="$3" vref="$4" runs="$5" extra="${6:-}" vrunat="${7:-null}"
  cat > "$f" <<YAML
project_status: active
current_focus:
  type: none
  ref_id: null
  primary_path: null
active_work_items: []
implementation_strategy:
  selected: tdd
  source: null
  rationale: null
worktree:
  recommendation: not_needed
  user_decision: undecided
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
  status: $vstatus
  run_at_utc: $vrunat
  ref_id: $vref
  evidence_paths: []
  notes: null
human_input:
  required: false
  question: null
locks:
  implementation: true
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
    $ref:
      human_time_minutes:
        intake: null
        reviews: null
      agent_runs:
$runs
$extra

updated_at_utc: 2026-07-15T11:30:00Z
YAML
}

test_135_field_basis_reliability() {  # TEST-135 / Spec-AC-04
  log_info "Test: field-basis reliability — two Validation runs verdict fail (no note), one Code Review run verdict fail -> counted from the FIELD, basis field (TEST-135)..."
  local d; d="$(mk_repo t135)"
  local runs
  runs='        - role: Validation
          model_id: claude-v
          started_utc: 2026-07-15T10:00:00Z
          ended_utc: 2026-07-15T10:01:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null
          verdict: fail
        - role: Validation
          model_id: claude-v
          started_utc: 2026-07-15T10:01:00Z
          ended_utc: 2026-07-15T10:02:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null
          verdict: fail
        - role: Code Review
          model_id: claude-c
          started_utc: 2026-07-15T10:02:00Z
          ended_utc: 2026-07-15T10:03:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null
          verdict: fail'
  write_gate_state "$d/docs/ai/STATE.yaml" CHANGE-0001 pass CHANGE-0001 "$runs"
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "flush must exit 0 (got $EC): $(cat "$OUT")"
  grep -v -e '^#' -e '^$' "$d/docs/ai/METRICS.jsonl" > "$d/got.jsonl"
  grep -qF '"reliability":{"validation_fails":2,"review_fails":1,"remediation_runs":0,"first_pass_clean":false,"basis":"field"}' "$d/got.jsonl" \
    || log_fail "field-basis fixture must record validation_fails 2, review_fails 1, first_pass_clean false, reliability.basis field: $(cat "$d/got.jsonl")"
  log_pass "Field-basis reliability: verdict fields drive the counts, basis field (TEST-135)"
}

test_136_note_fallback_reliability() {  # TEST-136 / Spec-AC-04
  log_info "Test: note fallback — same 3 runs with the verdict field removed and notes reading VERDICT FAIL (no colon) -> validation_fails 0, basis note, one NOTE line per affected run (TEST-136)..."
  local d; d="$(mk_repo t136)"
  local runs
  runs='        - role: Validation
          model_id: claude-v
          note: "VERDICT FAIL first probe"
          started_utc: 2026-07-15T10:00:00Z
          ended_utc: 2026-07-15T10:01:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null
        - role: Validation
          model_id: claude-v
          note: "VERDICT FAIL second probe"
          started_utc: 2026-07-15T10:01:00Z
          ended_utc: 2026-07-15T10:02:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null
        - role: Code Review
          model_id: claude-c
          note: "VERDICT FAIL review"
          started_utc: 2026-07-15T10:02:00Z
          ended_utc: 2026-07-15T10:03:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null'
  write_gate_state "$d/docs/ai/STATE.yaml" CHANGE-0001 pass CHANGE-0001 "$runs"
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "flush must exit 0 (got $EC): $(cat "$OUT")"
  grep -v -e '^#' -e '^$' "$d/docs/ai/METRICS.jsonl" > "$d/got.jsonl"
  grep -qF '"reliability":{"validation_fails":0,"review_fails":0,"remediation_runs":0,"first_pass_clean":true,"basis":"note"}' "$d/got.jsonl" \
    || log_fail "note-fallback fixture must record validation_fails 0 (colon-less marker invisible), basis note: $(cat "$d/got.jsonl")"
  local n; n="$(grep -c 'no verdict field recorded' "$OUT" || true)"
  [[ "$n" == 3 ]] || log_fail "exactly one NOTE line per affected run (3 runs, no field) expected (got $n): $(cat "$OUT")"
  log_pass "Note fallback: colon-less marker counts 0, basis note, one NOTE per fallback run (TEST-136)"
}

test_137_cost_basis_table() {  # TEST-137 / Spec-AC-05
  log_info "Test: cost basis table — total-blended with bounds, decomposed, none+WARNING, unknown-model null (TEST-137)..."
  local d; d="$(mk_repo t137)"
  # A non-0.5 cost_blend.input_share so the blend value can only be right if
  # the share is actually READ from PRICING (M11).
  cat > "$d/PRICING.yaml" <<'YAML'
schema_version: 2
lookup_rules:
  order:
    - strip-bracket-suffix
    - model-aliases
    - exact-match
    - longest-prefix
    - unknown-fallback
cost_blend:
  input_share: 0.9
model_aliases: {}
models:
  claude-opus-4-8:
    input_usd_per_m: 5.00
    output_usd_per_m: 25.00
  claude-sonnet-5:
    input_usd_per_m: 3.00
    output_usd_per_m: 15.00
  unknown:
    input_usd_per_m: null
    output_usd_per_m: null
YAML
  local runs
  runs='        - role: Implementation
          model_id: claude-opus-4-8
          started_utc: 2026-07-15T10:00:00Z
          ended_utc: 2026-07-15T10:01:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null
          tokens_total: 1000000
        - role: Implementation
          model_id: claude-sonnet-5
          started_utc: 2026-07-15T10:01:00Z
          ended_utc: 2026-07-15T10:02:00Z
          duration_seconds: 60
          tokens_in: 1000000
          tokens_out: 100000
          cost_usd: null
        - role: Implementation
          model_id: claude-sonnet-5
          started_utc: 2026-07-15T10:02:00Z
          ended_utc: 2026-07-15T10:03:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null
        - role: Implementation
          model_id: totally-unpriced-model
          started_utc: 2026-07-15T10:03:00Z
          ended_utc: 2026-07-15T10:04:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null
          tokens_total: 500000
        - role: Implementation
          model_id: claude-sonnet-5
          started_utc: 2026-07-15T10:04:00Z
          ended_utc: 2026-07-15T10:05:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null
          note: "usage_total_tokens=200000 (harness total; in/out not exposed)"
        - role: Implementation
          model_id: totally-unpriced-model
          started_utc: 2026-07-15T10:05:00Z
          ended_utc: 2026-07-15T10:06:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null
          note: "usage_total_tokens=300000 (harness total; in/out not exposed)"'
  write_gate_state "$d/docs/ai/STATE.yaml" CHANGE-0001 pass CHANGE-0001 "$runs"
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "flush must exit 0 (got $EC): $(cat "$OUT")"
  grep -v -e '^#' -e '^$' "$d/docs/ai/METRICS.jsonl" > "$d/got.jsonl"
  # (1) total-blended: 1000000 * (0.9*5 + 0.1*25)/1e6 = 7.0; bounds [5, 25].
  grep -qF '"cost_usd":7,"cost_basis":"total-blended","cost_bounds_usd":[5,25]' "$d/got.jsonl" \
    || log_fail "total-blended run must carry cost_usd 7 (0.9 share read from PRICING), cost_basis total-blended, bounds [5,25]: $(cat "$d/got.jsonl")"
  # (2) decomposed: (1000000*3 + 100000*15)/1e6 = 4.5.
  grep -qF '"cost_usd":4.5,"cost_basis":"decomposed"' "$d/got.jsonl" \
    || log_fail "decomposed run must carry cost_usd 4.5, cost_basis decomposed: $(cat "$d/got.jsonl")"
  # (3) neither -> null, none, existing WARNING. Anchored PER-RUN (not just
  # role-scoped) by asserting BOTH the exact line for the (claude-sonnet-5)
  # neither-run AND that it is the ONLY WARNING line printed — round-5
  # remediation of review NON-BLOCKING-1 / finding 5 (20260913T114019Z): the
  # old role-only regex `.*cost unattributable` was silently satisfied by
  # run (1)'s FALSE WARNING (a field-only priced run misclassified as
  # capture-missing), not by this run's honest one.
  grep -qF '"cost_usd":null,"cost_basis":"none"' "$d/got.jsonl" \
    || log_fail "a run with neither tokens nor total must carry cost_usd null, cost_basis none: $(cat "$d/got.jsonl")"
  grep -qF 'WARNING CHANGE-0001 run Implementation (claude-sonnet-5): cost unattributable — tokens not recorded' "$OUT" \
    || log_fail "the neither-tokens-nor-total run must still print the existing WARNING: $(cat "$OUT")"
  [[ "$(grep -c '^WARNING .*cost unattributable' "$OUT")" == 1 ]] \
    || log_fail "exactly ONE capture-missing WARNING line may print — a field-only or note-only run that priced must never fall to it: $(cat "$OUT")"
  # (4) unknown-priced model with a token total -> STILL null, never fabricated.
  grep -qF '"model_id":"totally-unpriced-model","started_utc":"2026-07-15T10:03:00Z","ended_utc":"2026-07-15T10:04:00Z","duration_seconds":60,"tokens_in":null,"tokens_out":null,"cost_usd":null,"cost_basis":"none"' "$d/got.jsonl" \
    || log_fail "an unknown-priced model with a token total must still yield cost_usd null, cost_basis none (never fabricated): $(cat "$d/got.jsonl")"
  grep -qF 'INFO CHANGE-0001 run Implementation (totally-unpriced-model): undecomposed total 500000 observed; cost unattributable by design' "$OUT" \
    || log_fail "(4) a FIELD-only total on an unpriced model must print INFO 'unattributable by design', never the capture-missing WARNING: $(cat "$OUT")"

  # (1b) round-5 remediation (review NON-BLOCKING-1 / finding 5,
  # 20260913T114019Z): the FIELD-only priced run (1) must print the SAME
  # blended INFO line a note-only priced run gets — the INFO/WARNING gate now
  # reads the same resolved total (field first, note fallback) the cost
  # derivation above already used. Before the fix this run fell to the
  # capture-missing WARNING beside its own priced, total-blended ledger line.
  grep -qF 'INFO CHANGE-0001 run Implementation (claude-opus-4-8): undecomposed total 1000000 observed; cost estimated from the total (cost_basis total-blended)' "$OUT" \
    || log_fail "(1b) a FIELD-only priced run must print the blended INFO line, not the capture-missing WARNING: $(cat "$OUT")"
  # (5)/(6) NON-BLOCKING-5 (review-telemetry-fields-not-prose-20260913T114019Z,
  # finding 5): the INFO line printed beside a NOTE-derived total must say
  # what actually happened to the cost, not an unconditional "unattributable
  # by design" — (5) a PRICED model's note-derived total blends (cost_usd
  # 0.84 = 200000*(0.9*3+0.1*15)/1e6, bounds [0.6,3.0]) and the line must name
  # that basis; (6) an UNPRICED model's note-derived total genuinely cannot
  # attribute a cost, and the line must still say so (true here, unlike (5)).
  grep -qF '"cost_usd":0.8399999999999999,"cost_basis":"total-blended","cost_bounds_usd":[0.6,3]' "$d/got.jsonl" \
    || log_fail "(5) a priced model's note-derived total must blend cost_usd ~0.84, bounds [0.6,3]: $(cat "$d/got.jsonl")"
  grep -qE '^INFO CHANGE-0001 run Implementation \(claude-sonnet-5\): undecomposed total 200000 observed; cost estimated from the total \(cost_basis total-blended\)' "$OUT" \
    || log_fail "(5) the INFO line must name the TRUE basis (blended) rather than claim unattributable beside an attributed cost: $(cat "$OUT")"
  grep -qF '"model_id":"totally-unpriced-model","note":"usage_total_tokens=300000 (harness total; in/out not exposed)","started_utc":"2026-07-15T10:05:00Z","ended_utc":"2026-07-15T10:06:00Z","duration_seconds":60,"tokens_in":null,"tokens_out":null,"cost_usd":null,"cost_basis":"none"' "$d/got.jsonl" \
    || log_fail "(6) an unpriced model's note-derived total must still yield cost_usd null, cost_basis none: $(cat "$d/got.jsonl")"
  grep -qE '^INFO CHANGE-0001 run Implementation \(totally-unpriced-model\): undecomposed total 300000 observed; cost unattributable by design' "$OUT" \
    || log_fail "(6) the INFO line must keep 'unattributable by design' ONLY where it is still true (unpriced model): $(cat "$OUT")"
  log_pass "Cost basis table: total-blended+bounds (share read from PRICING), decomposed, none+WARNING, unknown-model null, and the INFO line's basis wording is TRUE in both directions (TEST-137)"
}

test_138_per_ref_field_basis() {  # TEST-138 / Spec-AC-06
  log_info "Test: per-ref field basis — last_validation not_run/ref_id null but metrics entry carries validation status pass -> flushes, basis per-ref-field (TEST-138)..."
  local d; d="$(mk_repo t138)"
  local runs='        - role: Implementation
          model_id: claude-i
          started_utc: 2026-07-15T10:00:00Z
          ended_utc: 2026-07-15T10:01:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null'
  local extra='      validation:
        status: pass
        at: 2026-07-15T09:00:00Z'
  write_gate_state "$d/docs/ai/STATE.yaml" CHANGE-0001 not_run null "$runs" "$extra"
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  run_flush "$d" --dry-run
  [[ "$EC" == 0 ]] || log_fail "dry-run flush must exit 0 (got $EC): $(cat "$OUT")"
  node -e '
    const o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    if (!o.flush.includes("CHANGE-0001")) { console.error("CHANGE-0001 must be in the flush plan: " + JSON.stringify(o.flush)); process.exit(1); }
    if (o.verdict_basis["CHANGE-0001"] !== "per-ref-field") { console.error("basis must be per-ref-field, got " + JSON.stringify(o.verdict_basis)); process.exit(1); }
  ' "$OUT" || log_fail "dry-run plan must admit CHANGE-0001 naming basis per-ref-field"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "flush must exit 0 (got $EC): $(cat "$OUT")"
  grep -qF '"verdict_basis":"per-ref-field"' "$d/docs/ai/METRICS.jsonl" \
    || log_fail "ledger entry must carry verdict_basis per-ref-field: $(cat "$d/docs/ai/METRICS.jsonl")"

  # (b) PRIORITY: when BOTH the per-ref field AND the global block would
  # independently admit the SAME ref, source 1 (per-ref-field) must win —
  # the fixed order is 1, 2, 3, never re-derived from which one is "easier"
  # (M14: reordering to consult the global block first still admits the ref
  # but mislabels the basis, which a test asserting only "it flushed" cannot
  # see).
  local d2; d2="$(mk_repo t138b)"
  write_gate_state "$d2/docs/ai/STATE.yaml" CHANGE-0001 pass CHANGE-0001 "$runs" "$extra"
  write_ticks "$d2/docs/ai/LOOP_TICKS.jsonl"
  run_flush "$d2"
  [[ "$EC" == 0 ]] || log_fail "(b) flush must exit 0 (got $EC): $(cat "$OUT")"
  grep -qF '"verdict_basis":"per-ref-field"' "$d2/docs/ai/METRICS.jsonl" \
    || log_fail "(b) source 1 (per-ref-field) must win priority over source 2 (global-block) when both independently admit: $(cat "$d2/docs/ai/METRICS.jsonl")"

  log_pass "Per-ref field basis admits a ref last_validation cannot see, naming per-ref-field, and wins priority when the global block would also admit (TEST-138)"
}

test_139_event_basis() {  # TEST-139 / Spec-AC-06
  log_info "Test: event basis — a stranded ref recovered via the LATEST validation_verdict event; latest-fail skips; a malformed line never crashes (TEST-139)..."
  local runs='        - role: Implementation
          model_id: claude-i
          started_utc: 2026-07-15T10:00:00Z
          ended_utc: 2026-07-15T10:01:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null'

  # (a) last_validation names a DIFFERENT ref; EVENTS carries a pass event for
  # CHANGE-0001 -> admitted, basis event.
  local d; d="$(mk_repo t139a)"
  write_gate_state "$d/docs/ai/STATE.yaml" CHANGE-0001 pass CHANGE-9999 "$runs"
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  printf '{"v":1,"ts":"2026-07-15T08:00:00Z","actor":"dispatch","event":"validation_verdict","ref":"CHANGE-0001","payload":{"status":"pass","hash":"deadbeef"}}\n' > "$d/docs/ai/EVENTS.jsonl"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "(a) flush must exit 0 (got $EC): $(cat "$OUT")"
  grep -qF '"verdict_basis":"event"' "$d/docs/ai/METRICS.jsonl" \
    || log_fail "(a) a stranded ref recovered via a durable pass event must carry verdict_basis event: $(cat "$d/docs/ai/METRICS.jsonl")"

  # (b) latest event for the ref is FAIL (an earlier pass exists) -> skipped.
  local d2; d2="$(mk_repo t139b)"
  write_gate_state "$d2/docs/ai/STATE.yaml" CHANGE-0001 pass CHANGE-9999 "$runs"
  write_ticks "$d2/docs/ai/LOOP_TICKS.jsonl"
  {
    printf '{"v":1,"ts":"2026-07-15T07:00:00Z","actor":"dispatch","event":"validation_verdict","ref":"CHANGE-0001","payload":{"status":"pass"}}\n'
    printf '{"v":1,"ts":"2026-07-15T08:00:00Z","actor":"dispatch","event":"validation_verdict","ref":"CHANGE-0001","payload":{"status":"fail"}}\n'
  } > "$d2/docs/ai/EVENTS.jsonl"
  run_flush "$d2"
  [[ "$EC" == 0 ]] || log_fail "(b) flush must exit 0 (got $EC): $(cat "$OUT")"
  [[ "$(ledger_lines "$d2")" == 0 ]] || log_fail "(b) latest-is-fail must NOT flush the ref: $(cat "$d2/docs/ai/METRICS.jsonl")"
  grep -qF "SKIP CHANGE-0001" "$OUT" || log_fail "(b) the skip must name CHANGE-0001: $(cat "$OUT")"

  # (c) a malformed EVENTS line alongside a valid pass line -> no crash, admitted.
  local d3; d3="$(mk_repo t139c)"
  write_gate_state "$d3/docs/ai/STATE.yaml" CHANGE-0001 pass CHANGE-9999 "$runs"
  write_ticks "$d3/docs/ai/LOOP_TICKS.jsonl"
  {
    printf 'not-json-at-all\n'
    printf '{"v":1,"ts":"2026-07-15T08:00:00Z","actor":"dispatch","event":"validation_verdict","ref":"CHANGE-0001","payload":{"status":"pass"}}\n'
  } > "$d3/docs/ai/EVENTS.jsonl"
  run_flush "$d3"
  [[ "$EC" == 0 ]] || log_fail "(c) a malformed EVENTS line must never crash the flush (got $EC): $(cat "$OUT")"
  grep -qF '"verdict_basis":"event"' "$d3/docs/ai/METRICS.jsonl" \
    || log_fail "(c) the ref must still be admitted past the malformed line: $(cat "$d3/docs/ai/METRICS.jsonl")"
  grep -qi 'malformed' "$OUT" || log_fail "(c) the malformed line must produce a NOTE: $(cat "$OUT")"

  log_pass "Event basis: latest-pass recovers a stranded ref, latest-fail skips, a malformed line notes and never crashes (TEST-139)"
}

test_140_default_never_creates_events() {  # TEST-140 / Spec-AC-08
  log_info "Test: a flush with no --sweep over a tree with no docs/ai/EVENTS.jsonl exits 0, flushes by the global block (basis global-block, a field the pre-scope ledger never carried), and the file still does not exist afterwards (TEST-140)..."
  local d; d="$(mk_repo t140)"
  write_flush_state "$d/docs/ai/STATE.yaml" single
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  [[ ! -f "$d/docs/ai/EVENTS.jsonl" ]] || log_fail "fixture setup: EVENTS.jsonl must not pre-exist"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "flush must exit 0 (got $EC): $(cat "$OUT")"
  [[ ! -f "$d/docs/ai/EVENTS.jsonl" ]] || log_fail "the default flush path must NEVER create docs/ai/EVENTS.jsonl"
  grep -qF '"verdict_basis":"global-block"' "$d/docs/ai/METRICS.jsonl" \
    || log_fail "the flushed ledger entry must name basis global-block: $(cat "$d/docs/ai/METRICS.jsonl")"

  # (b) source 3 (the event read) IS actually consulted here (sources 1 and 2
  # both fail) — the interesting case for the existence guard, since a flush
  # whose gate resolves via source 1/2 never calls latestValidationVerdict at
  # all (M17 targets exactly this arm: replacing the existence guard with an
  # unconditional mkdirSync+appendFileSync open must still leave the file
  # absent under the CORRECT implementation, and reddens this arm when it
  # does not).
  local d2; d2="$(mk_repo t140b)"
  local runs='        - role: Implementation
          model_id: claude-i
          started_utc: 2026-07-15T10:00:00Z
          ended_utc: 2026-07-15T10:01:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null'
  write_gate_state "$d2/docs/ai/STATE.yaml" CHANGE-0001 not_run null "$runs"
  write_ticks "$d2/docs/ai/LOOP_TICKS.jsonl"
  [[ ! -f "$d2/docs/ai/EVENTS.jsonl" ]] || log_fail "(b) fixture setup: EVENTS.jsonl must not pre-exist"
  run_flush "$d2"
  [[ "$EC" == 0 ]] || log_fail "(b) flush must exit 0 even with nothing flushable (got $EC): $(cat "$OUT")"
  [[ ! -f "$d2/docs/ai/EVENTS.jsonl" ]] || log_fail "(b) source 3 being CONSULTED must still never create docs/ai/EVENTS.jsonl"
  grep -qF "SKIP CHANGE-0001" "$OUT" || log_fail "(b) CHANGE-0001 must be named in the skip line: $(cat "$OUT")"

  log_pass "Default path flushes by the global block naming its basis, and never creates EVENTS.jsonl even when source 3 is actually consulted (TEST-140)"
}

test_141_partial_reset_preserves_scope() {  # TEST-141 / Spec-AC-09
  log_info "Test: a partial-flush reset preserves code_review scope/base_ref/head_ref and stamps scope_ref_id (TEST-141)..."
  local d; d="$(mk_repo t141)"
  write_flush_state "$d/docs/ai/STATE.yaml" two
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "flush must exit 0 (got $EC): $(cat "$OUT")"
  [[ "$(ledger_lines "$d")" == 1 ]] || log_fail "only CHANGE-0001 may flush"
  sed -n '/^code_review:/,/^[a-z_]*:/p' "$d/docs/ai/STATE.yaml" > "$d/cr.block"
  grep -qE '^ {2}status: not_run$' "$d/cr.block" || log_fail "status must reset to not_run"
  grep -qE '^ {2}report_paths: \[\]$' "$d/cr.block" || log_fail "report_paths must reset to []"
  grep -qF "fixture review scope" "$d/cr.block" || log_fail "scope must be PRESERVED, not nulled"
  grep -qE '^ {2}base_ref: main$' "$d/cr.block" || log_fail "base_ref must be PRESERVED, not nulled"
  grep -qE '^ {2}scope_ref_id: CHANGE-0001$' "$d/cr.block" || log_fail "scope_ref_id must name the flushed ref"
  log_pass "Partial reset preserves code_review scope/base_ref/head_ref and stamps scope_ref_id (TEST-141)"
}

test_142_metrics_report_basis_columns() {  # TEST-142 / Spec-AC-12
  log_info "Test: metrics-report golden over a mixed field/marker/legacy ledger renders a cost-basis marker per ride and a basis column in reliability, byte-deterministically (TEST-142)..."
  local d="$TEST_DIR/t142"
  mkdir -p "$d"
  write_pricing "$d/PRICING.yaml"
  cat > "$d/METRICS.jsonl" <<'JSONL'
{"date_utc":"2026-07-01","ref_id":"FIELD-0001","title":"Field-derived","human_time_minutes":{"intake":null,"reviews":null},"agent_runs":[{"role":"Validation","model_id":"claude-sonnet-5","started_utc":"2026-07-01T10:00:00Z","ended_utc":"2026-07-01T10:01:00Z","duration_seconds":60,"tokens_in":null,"tokens_out":null,"cost_usd":null,"cost_basis":"none","verdict":"fail","verdict_basis":"field"}],"totals":{"human_time_minutes":0,"agent_duration_seconds":60,"total_cost_usd":null,"cost_basis":"none"},"strategy":"tdd","reliability":{"validation_fails":1,"review_fails":0,"remediation_runs":0,"first_pass_clean":false,"basis":"field"},"verdict_basis":"global-block","verdict":"PASS"}
{"date_utc":"2026-07-02","ref_id":"MARKER-0001","title":"Marker-derived","human_time_minutes":{"intake":null,"reviews":null},"agent_runs":[{"role":"Validation","model_id":"claude-sonnet-5","started_utc":"2026-07-02T10:00:00Z","ended_utc":"2026-07-02T10:01:00Z","duration_seconds":60,"tokens_in":null,"tokens_out":null,"cost_usd":null,"cost_basis":"none","verdict":null,"verdict_basis":"note"}],"totals":{"human_time_minutes":0,"agent_duration_seconds":60,"total_cost_usd":null,"cost_basis":"none"},"strategy":"tdd","reliability":{"validation_fails":0,"review_fails":0,"remediation_runs":0,"first_pass_clean":true,"basis":"note"},"verdict_basis":"global-block","verdict":"PASS"}
{"date_utc":"2026-07-03","ref_id":"LEGACY-0001","title":"Pre-scope legacy","human_time_minutes":{"intake":null,"reviews":null},"agent_runs":[{"role":"Implementation","model_id":"claude-sonnet-5","started_utc":"2026-07-03T10:00:00Z","ended_utc":"2026-07-03T10:01:00Z","duration_seconds":60,"tokens_in":null,"tokens_out":null,"cost_usd":null}],"totals":{"human_time_minutes":0,"agent_duration_seconds":60,"total_cost_usd":null},"strategy":"tdd","verdict":"PASS"}
JSONL
  runrep142() { (cd "$PROJECT_ROOT" && node .aai/scripts/metrics-report.mjs --metrics "$d/METRICS.jsonl" --pricing "$d/PRICING.yaml"); }
  runrep142 > "$d/run1.md" 2> "$d/run1.err" || log_fail "report must exit 0: $(cat "$d/run1.err")"
  runrep142 > "$d/run2.md" 2>/dev/null || log_fail "second run must exit 0"
  cmp -s "$d/run1.md" "$d/run2.md" || log_fail "identical input bytes must yield identical output bytes"
  grep -qE '^\| FIELD-0001 \| Field-derived \| 0 \| 60 \| n/a \| none \| n/a \| n/a \| PASS \|$' "$d/run1.md" \
    || log_fail "FIELD-0001 row must carry cost basis 'none' in its own column: $(cat "$d/run1.md")"
  grep -qE '^\| tdd \| 3 \| 1/2 \(50%\) \| 0\.5 \| 0\.0 \| 0\.0 \| mixed \|$' "$d/run1.md" \
    || log_fail "tdd strategy group must render basis mixed (field + note present, legacy excluded from the set) with 1/2 (50%) first-pass-clean over the two reliability-flagged entries: $(cat "$d/run1.md")"
  log_pass "metrics-report basis columns: per-ride cost basis + per-strategy reliability basis, byte-deterministic (TEST-142)"
}

test_143_append_only_prefix() {  # TEST-143 / Spec-AC-14
  log_info "Test: this ride's own flush appends only — the pre-flush ledger is a byte-exact prefix of the post-flush ledger, and the line count grows by exactly the flushed count (TEST-143)..."
  local d; d="$(mk_repo t143)"
  write_flush_state "$d/docs/ai/STATE.yaml" two
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  local pre_bytes pre_lines post_lines
  cp "$d/docs/ai/METRICS.jsonl" "$d/pre-flush.jsonl"
  pre_bytes="$(wc -c < "$d/pre-flush.jsonl" | tr -d ' ')"
  pre_lines="$(ledger_lines "$d")"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "flush must exit 0 (got $EC): $(cat "$OUT")"
  post_lines="$(ledger_lines "$d")"
  local flushed; flushed=$((post_lines - pre_lines))
  [[ "$flushed" -ge 1 ]] || log_fail "at least one ref must have flushed for this assertion to mean anything"
  head -c "$pre_bytes" "$d/docs/ai/METRICS.jsonl" > "$d/prefix.bin"
  cmp -s "$d/prefix.bin" "$d/pre-flush.jsonl" \
    || log_fail "the pre-flush bytes must survive as an exact PREFIX of the post-flush file"
  # This scope's own additive keys must actually be ON the newly appended
  # line — proves the prefix check is exercising THIS scope's flush, not a
  # byte-identity arm that would equally hold before it existed.
  grep -qF '"verdict_basis":"global-block"' "$d/docs/ai/METRICS.jsonl" \
    || log_fail "the newly appended line must carry this scope's verdict_basis field: $(cat "$d/docs/ai/METRICS.jsonl")"
  log_pass "Append-only: pre-flush ledger bytes are an exact prefix of the post-flush ledger; line count grows by the flushed count (TEST-143)"
}

test_144_event_corroboration() {  # TEST-144 / Spec-AC-06 / BLOCKING-1 (review-telemetry-fields-not-prose-20260913T105322Z)
  log_info "Test: a stale validation_verdict pass event must NOT flush a ref whose CURRENT verdict is fail — corroborated against the per-ref D7 field, last_validation, and the run's own verdict field (TEST-144)..."
  local d; d="$(mk_repo t144)"
  local runs='        - role: Validation
          model_id: claude-v
          verdict: fail
          started_utc: 2026-07-20T09:59:00Z
          ended_utc: 2026-07-20T10:00:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null'
  local extra='      validation:
        status: fail
        at: 2026-07-20T10:00:00Z'
  # Reviewer's exact fixture: STATE last_validation.status fail ref CHANGE-0001,
  # per-ref field fail, one Validation run carrying verdict: fail, and an
  # OLDER validation_verdict pass event for the same ref in EVENTS.jsonl.
  write_gate_state "$d/docs/ai/STATE.yaml" CHANGE-0001 fail CHANGE-0001 "$runs" "$extra"
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  printf '{"v":1,"ts":"2026-07-01T10:00:00Z","actor":"dispatch","event":"validation_verdict","ref":"CHANGE-0001","payload":{"status":"pass","hash":"deadbeef"}}\n' > "$d/docs/ai/EVENTS.jsonl"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "flush must exit 0 even when the only candidate ref is skipped (got $EC): $(cat "$OUT")"
  [[ "$(ledger_lines "$d")" == 0 ]] || log_fail "a stale pass event must NOT flush a ref whose current verdict is fail everywhere durable (per-ref field, last_validation, and the run's own verdict): $(cat "$d/docs/ai/METRICS.jsonl")"
  grep -qF "SKIP CHANGE-0001" "$OUT" || log_fail "the skip must name CHANGE-0001: $(cat "$OUT")"
  grep -qF "not admitted" "$OUT" || log_fail "the skip reason must name the corroboration refusal, not a generic message: $(cat "$OUT")"

  # Positive control: a genuinely stranded ref (pass event, NO fail anywhere —
  # no per-ref field, last_validation names a DIFFERENT ref, no Validation run
  # at all) must still flush via source 3, basis event. Guards against
  # eventContradictedByNewerFail over-blocking the exact recovery path D6
  # exists for.
  local d2; d2="$(mk_repo t144b)"
  local runs2='        - role: Implementation
          model_id: claude-i
          started_utc: 2026-07-15T10:00:00Z
          ended_utc: 2026-07-15T10:01:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null'
  write_gate_state "$d2/docs/ai/STATE.yaml" CHANGE-0001 pass CHANGE-9999 "$runs2"
  write_ticks "$d2/docs/ai/LOOP_TICKS.jsonl"
  printf '{"v":1,"ts":"2026-07-01T10:00:00Z","actor":"dispatch","event":"validation_verdict","ref":"CHANGE-0001","payload":{"status":"pass"}}\n' > "$d2/docs/ai/EVENTS.jsonl"
  run_flush "$d2"
  [[ "$EC" == 0 ]] || log_fail "(positive control) flush must exit 0 (got $EC): $(cat "$OUT")"
  grep -qF '"verdict_basis":"event"' "$d2/docs/ai/METRICS.jsonl" \
    || log_fail "(positive control) a genuinely stranded ref with no contradicting fail anywhere must still flush via event: $(cat "$d2/docs/ai/METRICS.jsonl")"

  # ---------------------------------------------------------------------------
  # Validation round-4 NON-BLOCKING-1 (20260913 validation-round4.txt): the
  # fixture above carries all THREE fail signals at once (per-ref field,
  # last_validation, AND a Validation run), so the disjunction masks each arm
  # individually — dropping any one of the three, inverting the ts
  # comparison, or breaking either fail-closed branch still leaves it (and
  # the older-fail positive control) green. Arms (a)-(h) below isolate ONE
  # signal each, so every one of the eight inner mutations reddens a NAMED
  # fixture (matrix reported by the remediation role).
  local impl_only='        - role: Implementation
          model_id: claude-i
          started_utc: 2026-07-15T10:00:00Z
          ended_utc: 2026-07-15T10:01:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null'
  local event_pass_line='{"v":1,"ts":"2026-07-01T10:00:00Z","actor":"dispatch","event":"validation_verdict","ref":"CHANGE-0001","payload":{"status":"pass"}}'

  # (a) ONLY the D7 per-ref field is fail, with a REAL ts newer than the
  # event -> must SKIP. Isolates source (i); vstatus/vref are set so neither
  # source (ii) nor the global-block short-circuit can admit on their own.
  local d_a; d_a="$(mk_repo t144c)"
  write_gate_state "$d_a/docs/ai/STATE.yaml" CHANGE-0001 pass CHANGE-9999 "$impl_only" \
    '      validation:
        status: fail
        at: 2026-07-20T10:00:00Z'
  write_ticks "$d_a/docs/ai/LOOP_TICKS.jsonl"
  printf '%s\n' "$event_pass_line" > "$d_a/docs/ai/EVENTS.jsonl"
  run_flush "$d_a"
  [[ "$EC" == 0 ]] || log_fail "(a) flush must exit 0 (got $EC): $(cat "$OUT")"
  [[ "$(ledger_lines "$d_a")" == 0 ]] || log_fail "(a) per-ref field alone (real newer ts) must block: $(cat "$d_a/docs/ai/METRICS.jsonl")"

  # (b) ONLY last_validation names the ref as fail, with a REAL run_at_utc
  # newer than the event -> must SKIP. Isolates source (ii); write_gate_state
  # historically hardcoded run_at_utc null here, which masked this arm from
  # the ts-inversion mutation (round-4 NON-BLOCKING-1) — now overridden ($7).
  local d_b; d_b="$(mk_repo t144d)"
  write_gate_state "$d_b/docs/ai/STATE.yaml" CHANGE-0001 fail CHANGE-0001 "$impl_only" "" 2026-07-20T10:00:00Z
  write_ticks "$d_b/docs/ai/LOOP_TICKS.jsonl"
  printf '%s\n' "$event_pass_line" > "$d_b/docs/ai/EVENTS.jsonl"
  run_flush "$d_b"
  [[ "$EC" == 0 ]] || log_fail "(b) flush must exit 0 (got $EC): $(cat "$OUT")"
  [[ "$(ledger_lines "$d_b")" == 0 ]] || log_fail "(b) last_validation alone (real newer run_at_utc) must block: $(cat "$d_b/docs/ai/METRICS.jsonl")"

  # (c) ONLY a Validation run's verdict FIELD is fail, with a REAL ended_utc
  # newer than the event -> must SKIP. Isolates source (iii)'s field arm.
  local d_c; d_c="$(mk_repo t144e)"
  local runs_c='        - role: Validation
          model_id: claude-v
          verdict: fail
          started_utc: 2026-07-20T09:59:00Z
          ended_utc: 2026-07-20T10:00:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null'
  write_gate_state "$d_c/docs/ai/STATE.yaml" CHANGE-0001 pass CHANGE-9999 "$runs_c"
  write_ticks "$d_c/docs/ai/LOOP_TICKS.jsonl"
  printf '%s\n' "$event_pass_line" > "$d_c/docs/ai/EVENTS.jsonl"
  run_flush "$d_c"
  [[ "$EC" == 0 ]] || log_fail "(c) flush must exit 0 (got $EC): $(cat "$OUT")"
  [[ "$(ledger_lines "$d_c")" == 0 ]] || log_fail "(c) a Validation run's verdict field alone (real newer ts) must block: $(cat "$d_c/docs/ai/METRICS.jsonl")"

  # (d) ONLY a Validation run's `verdict: none` field PLUS a VERDICT: FAIL
  # note, with a REAL ended_utc newer than the event -> must SKIP. Review
  # NON-BLOCKING-4 / finding 4 (20260913T114019Z): `none` is a legal enum
  # value meaning "no decision" and must NOT mask the note fallback the way
  # a field of `pass` legitimately does — before the fix this fixture
  # FLUSHED (a false PASS).
  local d_d; d_d="$(mk_repo t144f)"
  local runs_d='        - role: Validation
          model_id: claude-v
          verdict: none
          note: "VERDICT: FAIL corroboration probe (d)"
          started_utc: 2026-07-20T09:59:00Z
          ended_utc: 2026-07-20T10:00:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null'
  write_gate_state "$d_d/docs/ai/STATE.yaml" CHANGE-0001 pass CHANGE-9999 "$runs_d"
  write_ticks "$d_d/docs/ai/LOOP_TICKS.jsonl"
  printf '%s\n' "$event_pass_line" > "$d_d/docs/ai/EVENTS.jsonl"
  run_flush "$d_d"
  [[ "$EC" == 0 ]] || log_fail "(d) flush must exit 0 (got $EC): $(cat "$OUT")"
  [[ "$(ledger_lines "$d_d")" == 0 ]] || log_fail "(d) verdict: none must NOT mask a VERDICT: FAIL note (real newer ts) — the note fallback must still block: $(cat "$d_d/docs/ai/METRICS.jsonl")"

  # (e) Older-fail-does-not-block control: the per-ref field is fail but its
  # ts is OLDER than the event -> must still FLUSH via event. Confirms the
  # baseline "latest wins" direction is correct, independent of (a).
  local d_e; d_e="$(mk_repo t144g)"
  write_gate_state "$d_e/docs/ai/STATE.yaml" CHANGE-0001 pass CHANGE-9999 "$impl_only" \
    '      validation:
        status: fail
        at: 2026-06-01T10:00:00Z'
  write_ticks "$d_e/docs/ai/LOOP_TICKS.jsonl"
  printf '%s\n' "$event_pass_line" > "$d_e/docs/ai/EVENTS.jsonl"
  run_flush "$d_e"
  [[ "$EC" == 0 ]] || log_fail "(e) flush must exit 0 (got $EC): $(cat "$OUT")"
  grep -qF '"verdict_basis":"event"' "$d_e/docs/ai/METRICS.jsonl" \
    || log_fail "(e) a fail OLDER than the event must NOT block recovery: $(cat "$d_e/docs/ai/METRICS.jsonl")"

  # (f) Fail-closed on an unparseable FAIL ts: the per-ref field is fail but
  # `at` is null (sub-case f1) or malformed (sub-case f2) -> must still SKIP
  # (ambiguity never manufactures a PASS).
  local d_f1; d_f1="$(mk_repo t144h1)"
  write_gate_state "$d_f1/docs/ai/STATE.yaml" CHANGE-0001 pass CHANGE-9999 "$impl_only" \
    '      validation:
        status: fail
        at: null'
  write_ticks "$d_f1/docs/ai/LOOP_TICKS.jsonl"
  printf '%s\n' "$event_pass_line" > "$d_f1/docs/ai/EVENTS.jsonl"
  run_flush "$d_f1"
  [[ "$EC" == 0 ]] || log_fail "(f1) flush must exit 0 (got $EC): $(cat "$OUT")"
  [[ "$(ledger_lines "$d_f1")" == 0 ]] || log_fail "(f1) a null fail ts must be treated as newer (fail-closed): $(cat "$d_f1/docs/ai/METRICS.jsonl")"

  local d_f2; d_f2="$(mk_repo t144h2)"
  write_gate_state "$d_f2/docs/ai/STATE.yaml" CHANGE-0001 pass CHANGE-9999 "$impl_only" \
    '      validation:
        status: fail
        at: not-a-timestamp'
  write_ticks "$d_f2/docs/ai/LOOP_TICKS.jsonl"
  printf '%s\n' "$event_pass_line" > "$d_f2/docs/ai/EVENTS.jsonl"
  run_flush "$d_f2"
  [[ "$EC" == 0 ]] || log_fail "(f2) flush must exit 0 (got $EC): $(cat "$OUT")"
  [[ "$(ledger_lines "$d_f2")" == 0 ]] || log_fail "(f2) a malformed fail ts must be treated as newer (fail-closed): $(cat "$d_f2/docs/ai/METRICS.jsonl")"

  # (g) Fail-closed on an unparseable EVENT ts: last_validation is fail with
  # a real run_at_utc, but the EVENTS.jsonl line carries no `ts` at all ->
  # must still SKIP (a fail signal is treated as newer than an event whose
  # own ts cannot be read, regardless of the fail's own timestamp).
  local d_g; d_g="$(mk_repo t144i)"
  write_gate_state "$d_g/docs/ai/STATE.yaml" CHANGE-0001 fail CHANGE-0001 "$impl_only" "" 2026-01-01T00:00:00Z
  write_ticks "$d_g/docs/ai/LOOP_TICKS.jsonl"
  printf '{"v":1,"actor":"dispatch","event":"validation_verdict","ref":"CHANGE-0001","payload":{"status":"pass"}}\n' > "$d_g/docs/ai/EVENTS.jsonl"
  run_flush "$d_g"
  [[ "$EC" == 0 ]] || log_fail "(g) flush must exit 0 (got $EC): $(cat "$OUT")"
  [[ "$(ledger_lines "$d_g")" == 0 ]] || log_fail "(g) an event with no ts must be treated as contradicted (fail-closed): $(cat "$d_g/docs/ai/METRICS.jsonl")"

  # (h) Second-precision tie (review NON-BLOCKING-3 / finding 3,
  # 20260913T114019Z): state.mjs's nowIso() truncates to the second while
  # append-event.mjs keeps milliseconds. last_validation's run_at_utc lands
  # in the SAME second as the event but, at raw millisecond precision, is
  # numerically "before" it (0ms < 750ms) purely because its sub-second part
  # was truncated away. A tie must count as newer (fail-closed) -> must SKIP.
  local d_h; d_h="$(mk_repo t144j)"
  write_gate_state "$d_h/docs/ai/STATE.yaml" CHANGE-0001 fail CHANGE-0001 "$impl_only" "" 2026-07-01T10:00:00Z
  write_ticks "$d_h/docs/ai/LOOP_TICKS.jsonl"
  printf '{"v":1,"ts":"2026-07-01T10:00:00.750Z","actor":"dispatch","event":"validation_verdict","ref":"CHANGE-0001","payload":{"status":"pass"}}\n' > "$d_h/docs/ai/EVENTS.jsonl"
  run_flush "$d_h"
  [[ "$EC" == 0 ]] || log_fail "(h) flush must exit 0 (got $EC): $(cat "$OUT")"
  [[ "$(ledger_lines "$d_h")" == 0 ]] || log_fail "(h) a fail inside the event's own second (ms-truncated) must count as a tie and block: $(cat "$d_h/docs/ai/METRICS.jsonl")"

  # (i) round-5 remediation (validation-round5.txt NON-BLOCKING-2): the note
  # fallback's LEGACY sub-case — NO `verdict` field at ALL (not even
  # `verdict: none`) PLUS a VERDICT: FAIL note, with a REAL ended_utc newer
  # than the event -> must still SKIP. Arm (d) above already pins the
  # explicit `verdict: none` case; this arm independently pins the ABSENT
  # field case the reviewer named as the load-bearing production shape ("the
  # ONLY signal that protects a LEGACY stranded ref").
  local d_i; d_i="$(mk_repo t144k)"
  local runs_i='        - role: Validation
          model_id: claude-v
          note: "VERDICT: FAIL corroboration probe (i)"
          started_utc: 2026-07-20T09:59:00Z
          ended_utc: 2026-07-20T10:00:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null'
  write_gate_state "$d_i/docs/ai/STATE.yaml" CHANGE-0001 pass CHANGE-9999 "$runs_i"
  write_ticks "$d_i/docs/ai/LOOP_TICKS.jsonl"
  printf '%s\n' "$event_pass_line" > "$d_i/docs/ai/EVENTS.jsonl"
  run_flush "$d_i"
  [[ "$EC" == 0 ]] || log_fail "(i) flush must exit 0 (got $EC): $(cat "$OUT")"
  [[ "$(ledger_lines "$d_i")" == 0 ]] || log_fail "(i) a LEGACY run with no verdict field at all, only a VERDICT: FAIL note (real newer ts), must still block: $(cat "$d_i/docs/ai/METRICS.jsonl")"

  log_pass "Event corroboration: a stale pass event never overrides a newer fail (per-ref field, last_validation, or a Validation run's own verdict, note-fallback included), a genuinely stranded ref still recovers via event, an older fail never blocks, an unparseable ts on either side fails closed, and a same-second tie counts as newer (TEST-144)"
}

test_145_field_note_disagreement() {  # TEST-145 / Spec-AC-04 / NON-BLOCKING-B (review-telemetry-fields-not-prose-20260913T105322Z)
  log_info "Test: a run whose verdict field and note marker DISAGREE resolves from the FIELD (never the note) and emits exactly one field/note disagreement NOTE per affected run (TEST-145)..."
  local d; d="$(mk_repo t145)"
  local runs
  # (a) field pass, note carries the FAIL marker -> field wins (not counted
  #     as a fail), disagreement reported.
  # (b) field fail, note does NOT carry the marker -> field wins (IS counted
  #     as a fail — the dangerous direction: a note-overrides-field mutant
  #     would hide this exact failure), disagreement reported.
  # (c) field fail, note ALSO carries the marker -> agreement, NO NOTE.
  runs='        - role: Validation
          model_id: claude-v
          verdict: pass
          note: "VERDICT: FAIL disagreement probe (a)"
          started_utc: 2026-07-15T10:00:00Z
          ended_utc: 2026-07-15T10:01:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null
        - role: Validation
          model_id: claude-v
          verdict: fail
          note: "clean note, no marker (b)"
          started_utc: 2026-07-15T10:01:00Z
          ended_utc: 2026-07-15T10:02:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null
        - role: Validation
          model_id: claude-v
          verdict: fail
          note: "VERDICT: FAIL agreement (c)"
          started_utc: 2026-07-15T10:02:00Z
          ended_utc: 2026-07-15T10:03:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null'
  write_gate_state "$d/docs/ai/STATE.yaml" CHANGE-0001 pass CHANGE-0001 "$runs"
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "flush must exit 0 (got $EC): $(cat "$OUT")"
  grep -v -e '^#' -e '^$' "$d/docs/ai/METRICS.jsonl" > "$d/got.jsonl"
  # FIELD resolution: (a) pass -> not a fail, (b) fail -> IS a fail, (c) fail
  # -> IS a fail. validation_fails must be 2 (b, c), never 1 (note-overridden)
  # or 3 (field ignored).
  grep -qF '"reliability":{"validation_fails":2,"review_fails":0,"remediation_runs":0,"first_pass_clean":false,"basis":"field"}' "$d/got.jsonl" \
    || log_fail "field must win in both directions (validation_fails 2, basis field): $(cat "$d/got.jsonl")"
  local n; n="$(grep -c 'field/note disagreement' "$OUT" || true)"
  [[ "$n" == 2 ]] || log_fail "exactly one disagreement NOTE per DISAGREEING run (a, b), none for the agreeing run (c) — expected 2, got $n: $(cat "$OUT")"
  grep -qF 'verdict field is "pass"' "$OUT" || log_fail "the (a) disagreement NOTE must name the field value pass: $(cat "$OUT")"
  grep -qF 'verdict field is "fail"' "$OUT" || log_fail "the (b) disagreement NOTE must name the field value fail: $(cat "$OUT")"
  log_pass "Field/note disagreement: the FIELD always wins (both directions), and each disagreeing run prints exactly one NOTE (TEST-145)"
}
test_146_per_ref_pass_vetoed_by_newer_global_fail() {  # TEST-146 / Spec-AC-06 / Round-7 (PR #378 Codex P1)
  log_info "Test: a per-ref validation pass stamp does not outrank a NEWER same-ref global last_validation fail (TEST-146)..."
  local runs='        - role: Implementation
          model_id: claude-i
          started_utc: 2026-07-15T10:00:00Z
          ended_utc: 2026-07-15T10:01:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null'

  # (a) reviewer's exact sequence: `set-validation --ref CHANGE-0001 --status
  # pass` (per-ref stamp at 09:00:00Z) then a LATER LEGAL `set-validation
  # --status fail` with NO `--ref` (global block: fail, ref_id STILL
  # CHANGE-0001 from the earlier call, run_at_utc 10:00:00Z, newer) -> the
  # newer global fail must VETO the stale per-ref pass: SKIP, zero ledger
  # bytes, reason names the veto.
  local extra='      validation:
        status: pass
        at: 2026-07-15T09:00:00Z'
  local d; d="$(mk_repo t146a)"
  write_gate_state "$d/docs/ai/STATE.yaml" CHANGE-0001 fail CHANGE-0001 "$runs" "$extra" 2026-07-15T10:00:00Z
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "(a) flush must exit 0 (got $EC): $(cat "$OUT")"
  [[ "$(ledger_lines "$d")" == 0 ]] || log_fail "(a) the stale per-ref pass must NOT flush: $(cat "$d/docs/ai/METRICS.jsonl")"
  grep -qF "SKIP CHANGE-0001" "$OUT" || log_fail "(a) the skip must name CHANGE-0001: $(cat "$OUT")"
  grep -qi 'newer last_validation fail' "$OUT" || log_fail "(a) the skip reason must name the newer global fail: $(cat "$OUT")"

  # (b) positive control: the per-ref pass is NEWER (10:00:00Z) than the
  # global fail naming the same ref (09:00:00Z) -> the per-ref pass still
  # wins, basis per-ref-field, exactly like TEST-138.
  local extra2='      validation:
        status: pass
        at: 2026-07-15T10:00:00Z'
  local d2; d2="$(mk_repo t146b)"
  write_gate_state "$d2/docs/ai/STATE.yaml" CHANGE-0001 fail CHANGE-0001 "$runs" "$extra2" 2026-07-15T09:00:00Z
  write_ticks "$d2/docs/ai/LOOP_TICKS.jsonl"
  run_flush "$d2"
  [[ "$EC" == 0 ]] || log_fail "(b) flush must exit 0 (got $EC): $(cat "$OUT")"
  grep -qF '"verdict_basis":"per-ref-field"' "$d2/docs/ai/METRICS.jsonl" \
    || log_fail "(b) a per-ref pass NEWER than the global fail must still flush naming per-ref-field: $(cat "$d2/docs/ai/METRICS.jsonl")"

  # (c) second-precision tie (same convention eventContradictedByNewerFail's
  # Round-4 refinement uses): the per-ref stamp's own `at` carries no
  # sub-second part (implicit .000) while the global fail's run_at_utc lands
  # later in the SAME whole second -> counts as newer (fail-closed) -> vetoed.
  local extra3='      validation:
        status: pass
        at: 2026-07-15T10:00:00Z'
  local d3; d3="$(mk_repo t146c)"
  write_gate_state "$d3/docs/ai/STATE.yaml" CHANGE-0001 fail CHANGE-0001 "$runs" "$extra3" 2026-07-15T10:00:00.750Z
  write_ticks "$d3/docs/ai/LOOP_TICKS.jsonl"
  run_flush "$d3"
  [[ "$EC" == 0 ]] || log_fail "(c) flush must exit 0 (got $EC): $(cat "$OUT")"
  [[ "$(ledger_lines "$d3")" == 0 ]] || log_fail "(c) a same-second tie must count as newer and veto: $(cat "$d3/docs/ai/METRICS.jsonl")"

  log_pass "Per-ref pass veto: a newer same-ref global fail vetoes a stale per-ref pass, an older global fail never blocks a newer per-ref pass, and a same-second tie counts as newer (TEST-146)"
}

test_147_requested_actual_model_passthrough() {  # TEST-147 / Round-7 (PR #378 Codex P1)
  log_info "Test: flush copies requested_model and actual_model into the ledger run entry; a sibling run recording neither carries neither key (TEST-147)..."
  local runs='        - role: Implementation
          model_id: claude-i
          started_utc: 2026-07-15T10:00:00Z
          ended_utc: 2026-07-15T10:01:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null
          requested_model: claude-sonnet-5
          actual_model: claude-haiku-5
        - role: Validation
          model_id: claude-v
          verdict: pass
          started_utc: 2026-07-15T10:02:00Z
          ended_utc: 2026-07-15T10:03:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null'
  local d; d="$(mk_repo t147)"
  write_gate_state "$d/docs/ai/STATE.yaml" CHANGE-0001 pass CHANGE-0001 "$runs"
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "flush must exit 0 (got $EC): $(cat "$OUT")"
  grep -v -e '^#' -e '^$' "$d/docs/ai/METRICS.jsonl" > "$d/got.jsonl"
  node -e '
    const line = require("fs").readFileSync(process.argv[1], "utf8").trim();
    const o = JSON.parse(line);
    const runs = o.agent_runs;
    const impl = runs.find(r => r.role === "Implementation");
    const val = runs.find(r => r.role === "Validation");
    if (impl.requested_model !== "claude-sonnet-5") { console.error("Implementation run must carry requested_model claude-sonnet-5, got " + JSON.stringify(impl.requested_model)); process.exit(1); }
    if (impl.actual_model !== "claude-haiku-5") { console.error("Implementation run must carry actual_model claude-haiku-5, got " + JSON.stringify(impl.actual_model)); process.exit(1); }
    if ("requested_model" in val || "actual_model" in val) { console.error("Validation run recorded neither flag and must carry NEITHER key, got " + JSON.stringify(val)); process.exit(1); }
  ' "$d/got.jsonl" || log_fail "requested_model/actual_model must pass through to the ledger run entry, present only when recorded"
  log_pass "Flush copies requested_model and actual_model into the ledger run entry; a sibling run without them carries neither key (TEST-147)"
}

test_148_scope_ref_id_binds_to_focus() {  # TEST-148 / Spec-AC-09 / Round-7 (PR #378 Codex P2)
  log_info "Test: a partial flush completing multiple refs binds the preserved scope_ref_id to the CURRENT FOCUS ref, not to metrics.work_items array order (TEST-148)..."

  # Shared shape: metrics.work_items lists CHANGE-0002 BEFORE CHANGE-0001 (so
  # array order alone would pick CHANGE-0002); last_validation admits BOTH
  # via a composite ref_id "CHANGE-0002/CHANGE-0001" (refMatches' documented
  # "/"-joined form); a third active work item (CHANGE-0003, in_progress,
  # absent from metrics) keeps the reset PARTIAL, never full.
  write_scope148_state() {
    local f="$1" focus_ref="$2" existing_scope_ref="$3"
    cat > "$f" <<YAML
project_status: active
current_focus:
  type: intake_change
  ref_id: $focus_ref
  primary_path: null
active_work_items:
  - ref_id: CHANGE-0001
    status: done
    phase: validation
    primary_path: docs/issues/CHANGE-0001-a.md
  - ref_id: CHANGE-0002
    status: done
    phase: validation
    primary_path: docs/issues/CHANGE-0002-b.md
  - ref_id: CHANGE-0003
    status: in_progress
    phase: implementation
    primary_path: docs/issues/CHANGE-0003-c.md
implementation_strategy:
  selected: tdd
  source: null
  rationale: null
worktree:
  recommendation: not_needed
  user_decision: undecided
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
  scope_ref_id: $existing_scope_ref
last_validation:
  status: pass
  run_at_utc: 2026-07-15T11:00:00Z
  ref_id: CHANGE-0002/CHANGE-0001
  evidence_paths: []
  notes: null
human_input:
  required: false
  question: null
locks:
  implementation: true
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
    CHANGE-0002:
      human_time_minutes:
        intake: null
        reviews: null
      agent_runs:
        - role: Implementation
          model_id: claude-i
          started_utc: 2026-07-15T09:00:00Z
          ended_utc: 2026-07-15T09:01:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null
    CHANGE-0001:
      human_time_minutes:
        intake: null
        reviews: null
      agent_runs:
        - role: Implementation
          model_id: claude-i
          started_utc: 2026-07-15T10:00:00Z
          ended_utc: 2026-07-15T10:01:00Z
          duration_seconds: 60
          tokens_in: null
          tokens_out: null
          cost_usd: null

updated_at_utc: 2026-07-15T11:30:00Z
YAML
  }

  # (a) focus ref (CHANGE-0001) is AMONG the flushed refs but SECOND in
  # metrics.work_items order (CHANGE-0002 is first) -> scope_ref_id must name
  # CHANGE-0001, not the array-order CHANGE-0002 (M-scope: reverting to
  # flushedRefs[0] reddens this arm).
  local d; d="$(mk_repo t148a)"
  write_scope148_state "$d/docs/ai/STATE.yaml" CHANGE-0001 null
  write_ticks "$d/docs/ai/LOOP_TICKS.jsonl"
  run_flush "$d"
  [[ "$EC" == 0 ]] || log_fail "(a) flush must exit 0 (got $EC): $(cat "$OUT")"
  [[ "$(ledger_lines "$d")" == 2 ]] || log_fail "(a) both CHANGE-0001 and CHANGE-0002 must flush: $(cat "$d/docs/ai/METRICS.jsonl")"
  sed -n '/^code_review:/,/^[a-z_]*:/p' "$d/docs/ai/STATE.yaml" > "$d/cr.block"
  grep -qE '^ {2}scope_ref_id: CHANGE-0001$' "$d/cr.block" \
    || log_fail "(a) scope_ref_id must bind to the current-focus ref CHANGE-0001, not array order: $(cat "$d/cr.block")"

  # (b) focus ref is NOT among the flushed refs (current_focus already moved
  # on to CHANGE-9999), but the PRE-flush scope_ref_id already names
  # CHANGE-0001 — one of the flushed refs, again second in array order — so
  # that existing binding must be PRESERVED rather than overwritten by
  # array-order CHANGE-0002.
  local d2; d2="$(mk_repo t148b)"
  write_scope148_state "$d2/docs/ai/STATE.yaml" CHANGE-9999 CHANGE-0001
  write_ticks "$d2/docs/ai/LOOP_TICKS.jsonl"
  run_flush "$d2"
  [[ "$EC" == 0 ]] || log_fail "(b) flush must exit 0 (got $EC): $(cat "$OUT")"
  sed -n '/^code_review:/,/^[a-z_]*:/p' "$d2/docs/ai/STATE.yaml" > "$d2/cr.block"
  grep -qE '^ {2}scope_ref_id: CHANGE-0001$' "$d2/cr.block" \
    || log_fail "(b) an existing scope_ref_id naming a flushed ref must be PRESERVED, not overwritten by array order: $(cat "$d2/cr.block")"

  log_pass "scope_ref_id binds to the current-focus ref when it is among the flushed refs, else preserves an existing matching binding, never plain array order (TEST-148)"
}


main() {
  echo "Testing $TEST_NAME (CHANGE-0009 TEST-006..014 + truth-scoring TEST-017/018 + SPEC-0054 TEST-001..005 + --sweep TEST-101..109 + --retire TEST-001..008 + token-capture-canary spec TEST-001..003 + token-economics-end-to-end TEST-001..004,011)"
  check_deps
  setup_fixture
  test_006_flush_golden
  test_007_timing_fidelity
  test_008_criteria_negatives
  test_009_null_token_warnings
  test_010_header_preservation
  test_011_partial_flush
  test_012_full_reset_cleanup
  test_013_transactionality
  test_014_report_golden
  test_015_fallback_ref_id_parity
  test_016_zero_relative_full_reset
  test_017_reliability_derivation
  test_018_report_strategy_golden
  test_019_no_close_events_from_flush
  test_020_numbered_ref_audit_clean
  test_021_flush_then_close_no_double_emit
  test_022_close_then_flush_no_double_emit
  test_023_ledger_shape_unchanged
  test_134_partial_reset_archives_the_proof
  test_101_sweep_flag_parse
  test_102_sweep_flushes_closed_ref
  test_103_sweep_fail_closed
  test_104_default_unchanged
  test_105_sweep_state_hygiene
  test_106_sweep_integrity_refusal
  test_107_sweep_idempotent
  test_108_sweep_targeted_ref
  test_109_sweep_seam_close_then_sweep
  test_110_retire_stranded_ref
  test_111_retire_refused_default_flushable
  test_112_retire_refused_sweep_flushable
  test_113_retire_refused_not_in_state
  test_114_retire_dry_run
  test_116_retire_documented_not_in_prompt
  test_117_classify_decomposed
  test_118_classify_undecomposed_note
  test_119_classify_capture_missing
  test_120_shared_lib_grep_contract
  test_121_seam_marker_agreement
  test_122_report_per_item_undecomposed_column
  test_123_report_per_role_token_rollup
  test_124_flush_prompt_hash_passthrough
  test_125_flush_seam1_append_run_prompt_hash
  test_126_report_prompt_versions_multi_hash
  test_127_report_no_prompt_versions_single_hash
  test_130_rguard_flush_provenance_warn
  test_131_rguard_flush_rigor_downgrade
  test_132_rguard_events_appendonly
  test_133_model_marker_grep_contract
  test_135_field_basis_reliability
  test_136_note_fallback_reliability
  test_137_cost_basis_table
  test_138_per_ref_field_basis
  test_139_event_basis
  test_140_default_never_creates_events
  test_141_partial_reset_preserves_scope
  test_142_metrics_report_basis_columns
  test_143_append_only_prefix
  test_144_event_corroboration
  test_145_field_note_disagreement
  test_146_per_ref_pass_vetoed_by_newer_global_fail
  test_147_requested_actual_model_passthrough
  test_148_scope_ref_id_binds_to_focus
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
