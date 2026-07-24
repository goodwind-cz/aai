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
# Truth-scoring (SPEC-DRAFT-truth-scoring, RES-0001 P3) — TEST-006/TEST-014
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
{"date_utc":"2026-07-15","ref_id":"CHANGE-0001","title":"Golden fixture item","human_time_minutes":{"intake":null,"reviews":2},"agent_runs":[{"role":"Planning","model_id":"claude-opus-4-8[1m]","started_utc":"2026-07-15T10:00:00Z","ended_utc":"2026-07-15T10:02:00Z","duration_seconds":120,"tokens_in":1000000,"tokens_out":100000,"cost_usd":7.5},{"role":"Implementation","model_id":"sonnet-latest","started_utc":"2026-07-15T10:02:00Z","ended_utc":"2026-07-15T10:12:00Z","duration_seconds":600,"tokens_in":2000000,"tokens_out":200000,"cost_usd":9},{"role":"Validation","model_id":"claude-sonnet-5-20260101","started_utc":"2026-07-15T10:12:00Z","ended_utc":"2026-07-15T10:13:40Z","duration_seconds":100,"tokens_in":1000000,"tokens_out":1000000,"cost_usd":18},{"role":"Code Review","model_id":"mystery-9000","started_utc":"2026-07-15T10:13:40Z","ended_utc":"2026-07-15T10:14:40Z","duration_seconds":60,"tokens_in":10,"tokens_out":10,"cost_usd":null}],"totals":{"human_time_minutes":2,"agent_duration_seconds":880,"total_cost_usd":null},"strategy":"tdd","reliability":{"validation_fails":0,"review_fails":0,"remediation_runs":0,"first_pass_clean":true},"verdict":"PASS"}
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
  grep -qE '^ {2}scope: null$' "$d/cr.block" || log_fail "leaked code_review.scope must be nulled"
  grep -qE '^ {2}base_ref: null$' "$d/cr.block" || log_fail "leaked code_review.base_ref must be nulled"
  grep -qE '^ {2}head_ref: null$' "$d/cr.block" || log_fail "leaked code_review.head_ref must be nulled"
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
| ref_id | title | human (min) | agent (sec) | cost USD | leverage | verdict |
|--------|-------|-------------|-------------|----------|----------|---------|
| AAA-0001 | First | 10 | 600 | $7.50 | 1.0x | PASS |
| AAA-0002 | Second | 0 | 600 | ~$9.00 | n/a | PASS |

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

### Per-Strategy Reliability
| strategy | items | first-pass clean | avg validation fails | avg review fails | avg remediations |
|----------|-------|------------------|----------------------|------------------|------------------|
| n/a | 2 | n/a | n/a | n/a | n/a |

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
  echo "$out" | grep -qE "line 2" || log_fail "corrupt-line error must name the line number: $out"
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

# --- TEST-017: reliability derivation matrix (SPEC-DRAFT-truth-scoring R1-R6) --------

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
  grep -qF '"strategy":"tdd","reliability":{"validation_fails":1,"review_fails":1,"remediation_runs":2,"first_pass_clean":false},"verdict":"PASS"' "$d/got.jsonl" \
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
  grep -qF '"strategy":null,"reliability":{"validation_fails":0,"review_fails":0,"remediation_runs":0,"first_pass_clean":true},"verdict":"PASS"' "$d/got.jsonl" \
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
| strategy | items | first-pass clean | avg validation fails | avg review fails | avg remediations |
|----------|-------|------------------|----------------------|------------------|------------------|
| loop | 2 | 0/2 (0%) | 0.5 | 0.5 | 1.5 |
| n/a | 1 | n/a | n/a | n/a | n/a |
| tdd | 1 | 1/1 (100%) | 0.0 | 0.0 | 0.0 |

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
    const wantKeys = ["date_utc","ref_id","title","human_time_minutes","agent_runs","totals","strategy","reliability","verdict"];
    const gotKeys = Object.keys(got);
    if (JSON.stringify(gotKeys) !== JSON.stringify(wantKeys)) {
      console.error("ledger entry key set/order changed: got " + JSON.stringify(gotKeys) + " want " + JSON.stringify(wantKeys));
      process.exit(1);
    }
  ' "$d/got.jsonl" || log_fail "ledger entry shape must be byte/shape unchanged by the events-removal"
  log_pass "Ledger record shape unchanged by removing the events emission (TEST-005)"
}

# --- metrics-flush-strands-completed-refs: --sweep (TEST-101..109) -------------
# SPEC-DRAFT-spec-metrics-flush-sweep.md D1-D5. Every fixture is a scratch
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
  echo "$usage_out" | grep -qF -- '--sweep' || log_fail "unknown-flag usage string must list --sweep: $usage_out"
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
    const wantKeys = ["date_utc","ref_id","title","human_time_minutes","agent_runs","totals","strategy","reliability","verdict"];
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
{"date_utc":"2026-07-15","ref_id":"CHANGE-0001","title":"Golden fixture item","human_time_minutes":{"intake":null,"reviews":2},"agent_runs":[{"role":"Planning","model_id":"claude-opus-4-8[1m]","started_utc":"2026-07-15T10:00:00Z","ended_utc":"2026-07-15T10:02:00Z","duration_seconds":120,"tokens_in":1000000,"tokens_out":100000,"cost_usd":7.5},{"role":"Implementation","model_id":"sonnet-latest","started_utc":"2026-07-15T10:02:00Z","ended_utc":"2026-07-15T10:12:00Z","duration_seconds":600,"tokens_in":2000000,"tokens_out":200000,"cost_usd":9},{"role":"Validation","model_id":"claude-sonnet-5-20260101","started_utc":"2026-07-15T10:12:00Z","ended_utc":"2026-07-15T10:13:40Z","duration_seconds":100,"tokens_in":1000000,"tokens_out":1000000,"cost_usd":18},{"role":"Code Review","model_id":"mystery-9000","started_utc":"2026-07-15T10:13:40Z","ended_utc":"2026-07-15T10:14:40Z","duration_seconds":60,"tokens_in":10,"tokens_out":10,"cost_usd":null}],"totals":{"human_time_minutes":2,"agent_duration_seconds":880,"total_cost_usd":null},"strategy":"tdd","reliability":{"validation_fails":0,"review_fails":0,"remediation_runs":0,"first_pass_clean":true},"verdict":"PASS"}
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
# SPEC-DRAFT-spec-retire-stranded-nonworkitem-metric. Every fixture is a
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
  echo "$header" | grep -qF -- '--retire' || log_fail "top-of-file comment must document --retire"
  echo "$header" | grep -qF -- '--reason' || log_fail "top-of-file comment must document --reason"
  # (b) unknown-flag usage string lists --retire (grep the parseArgs fail text).
  local usage_out usage_ec=0
  usage_out="$( (cd "$PROJECT_ROOT" && node .aai/scripts/metrics-flush.mjs --bogus-flag 2>&1) )" || usage_ec=$?
  [[ "$usage_ec" == 2 ]] || log_fail "unknown flag must exit 2 (got $usage_ec): $usage_out"
  echo "$usage_out" | grep -qF -- '--retire' || log_fail "unknown-flag usage string must list --retire: $usage_out"
  # (c) SPEC-0054 negative invariant re-verified locally: the prompt file must
  # NOT carry the literal work_item_closed (documenting retire's guard there
  # would risk reintroducing it — retire is documented in the script only).
  local prompt="$PROJECT_ROOT/.aai/METRICS_FLUSH.prompt.md"
  [[ -f "$prompt" ]] || log_fail "missing $prompt"
  grep -qF "work_item_closed" "$prompt" && log_fail "METRICS_FLUSH.prompt.md must NOT contain the literal work_item_closed (SPEC-0054)"
  log_pass "--retire/--reason documented in the script only; prompt file free of work_item_closed (TEST-008)"
}

main() {
  echo "Testing $TEST_NAME (CHANGE-0009 TEST-006..014 + truth-scoring TEST-017/018 + SPEC-0054 TEST-001..005 + --sweep TEST-101..109 + --retire TEST-001..008)"
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
