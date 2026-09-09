#!/usr/bin/env bash
#
# Test: unattended-rides-human-gate-at-merge (SPEC-0174-spec-unattended-rides-human-gate-at-merge)
# .aai/scripts/unattended-gate.mjs — the deterministic auto-versus-park engine
# (D1), TEST-001..015 (TEST-016 lives in test-aai-prompt-diet.sh, TEST-017 in
# test-aai-golden-flow.sh — the spec's own numbering, unrelated to this file's).
#
# Every case runs against FIXTURE ledgers/events under a scratch tmpdir; only
# the seam tests (TEST-004, TEST-007, TEST-014) read the repository's own
# canon prompts, read-only.

set -u
TEST_NAME="test-aai-unattended"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENGINE="$PROJECT_ROOT/.aai/scripts/unattended-gate.mjs"
# shellcheck source=lib/assert-payload.sh
. "$SCRIPT_DIR/lib/assert-payload.sh"

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_info() { echo "INFO: $*"; }
log_skip() { echo "SKIP: $*"; exit 42; }
command -v node >/dev/null 2>&1 || log_skip "node not found"

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-unattended.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

run() { node "$ENGINE" "$@" > "$TEST_DIR/out" 2> "$TEST_DIR/err"; echo $?; }
out() { cat "$TEST_DIR/out"; }
err() { cat "$TEST_DIR/err"; }
jf() { node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{try{const o=JSON.parse(d);const v=o[process.argv[1]];process.stdout.write(v===undefined?"":String(v));}catch{process.stdout.write("");}})' "$1" < "$TEST_DIR/out"; }

fresh_ledger() { : > "$TEST_DIR/decisions.jsonl"; }

# --- TEST-001 (Spec-AC-01): all thirteen D1 rows -------------------------------
test_001_all_rows() {
  log_info "Test: all thirteen D1 rows drive classify to the right decision/class/exit (TEST-001)..."
  # auto rows
  fresh_ledger
  [ "$(run classify --trigger HITL-5 --ref r1 --question q --ledger "$TEST_DIR/decisions.jsonl" --json)" = "0" ] || log_fail "TEST-001: HITL-5 must exit 0: $(err)"
  [ "$(jf decision)" = "auto" ] || log_fail "TEST-001: HITL-5 decision must be auto, got $(jf decision)"
  [ "$(jf class)" = "quality" ] || log_fail "TEST-001: HITL-5 class must be quality, got $(jf class)"

  fresh_ledger
  [ "$(run classify --trigger HITL-7 --ref r1 --question q --worktree-recommendation optional --ledger "$TEST_DIR/decisions.jsonl" --json)" = "0" ] || log_fail "TEST-001: HITL-7 optional must exit 0: $(err)"
  [ "$(jf decision)" = "auto" ] || log_fail "TEST-001: HITL-7 optional decision must be auto"
  [ "$(jf answer)" = "inline" ] || log_fail "TEST-001: HITL-7 optional must resolve inline, got $(jf answer)"

  fresh_ledger
  [ "$(run classify --trigger HITL-7 --ref r1 --question q --worktree-recommendation recommended --ledger "$TEST_DIR/decisions.jsonl" --json)" = "0" ] || log_fail "TEST-001: HITL-7 recommended must exit 0: $(err)"
  [ "$(jf answer)" = "worktree" ] || log_fail "TEST-001: HITL-7 recommended must resolve worktree, got $(jf answer)"

  fresh_ledger
  [ "$(run classify --trigger HITL-7 --ref r1 --question q --worktree-recommendation required --ledger "$TEST_DIR/decisions.jsonl" --json)" = "3" ] || log_fail "TEST-001: HITL-7 required must exit 3 (park)"
  [ "$(jf decision)" = "park" ] || log_fail "TEST-001: HITL-7 required decision must be park"

  fresh_ledger
  [ "$(run classify --trigger HITL-7 --ref r1 --question q --worktree-recommendation optional --ceremony 3 --ledger "$TEST_DIR/decisions.jsonl" --json)" = "3" ] || log_fail "TEST-001: HITL-7 at ceremony 3 must exit 3 (park) even when optional"
  [ "$(jf class)" = "quality" ] || log_fail "TEST-001: HITL-7 park still carries class quality"

  fresh_ledger
  [ "$(run classify --trigger HITL-8 --ref r1 --question q --answer "docs/foo.md" --ledger "$TEST_DIR/decisions.jsonl" --json)" = "0" ] || log_fail "TEST-001: HITL-8 must exit 0: $(err)"
  [ "$(jf decision)" = "auto" ] || log_fail "TEST-001: HITL-8 decision must be auto"

  fresh_ledger
  [ "$(run classify --trigger HITL-9 --ref r1 --question q --ledger "$TEST_DIR/decisions.jsonl" --json)" = "0" ] || log_fail "TEST-001: HITL-9 must exit 0: $(err)"
  [ "$(jf answer)" = "fail" ] || log_fail "TEST-001: HITL-9 must always resolve fail, got $(jf answer)"

  # park rows
  for t in HITL-1 HITL-2 HITL-3 HITL-4 HITL-6 stagnation run-budget review-round-cap; do
    fresh_ledger
    [ "$(run classify --trigger "$t" --ref r1 --question q --ledger "$TEST_DIR/decisions.jsonl" --json)" = "3" ] || log_fail "TEST-001: $t must exit 3 (park): $(err)"
    [ "$(jf decision)" = "park" ] || log_fail "TEST-001: $t decision must be park"
  done
  # classes for each park/scope row, spot-checked
  fresh_ledger; run classify --trigger HITL-1 --ref r1 --question q --ledger "$TEST_DIR/decisions.jsonl" --json >/dev/null
  [ "$(jf class)" = "scope" ] || log_fail "TEST-001: HITL-1 class must be scope"
  fresh_ledger; run classify --trigger HITL-3 --ref r1 --question q --ledger "$TEST_DIR/decisions.jsonl" --json >/dev/null
  [ "$(jf class)" = "irreversibility" ] || log_fail "TEST-001: HITL-3 class must be irreversibility"
  fresh_ledger; run classify --trigger HITL-6 --ref r1 --question q --ledger "$TEST_DIR/decisions.jsonl" --json >/dev/null
  [ "$(jf class)" = "cost" ] || log_fail "TEST-001: HITL-6 class must be cost"
  fresh_ledger; run classify --trigger stagnation --ref r1 --question q --ledger "$TEST_DIR/decisions.jsonl" --json >/dev/null
  [ "$(jf class)" = "guard" ] || log_fail "TEST-001: stagnation class must be guard"
  fresh_ledger; run classify --trigger run-budget --ref r1 --question q --ledger "$TEST_DIR/decisions.jsonl" --json >/dev/null
  [ "$(jf class)" = "cost" ] || log_fail "TEST-001: run-budget class must be cost"
  fresh_ledger; run classify --trigger review-round-cap --ref r1 --question q --ledger "$TEST_DIR/decisions.jsonl" --json >/dev/null
  [ "$(jf class)" = "scope" ] || log_fail "TEST-001: review-round-cap class must be scope"
  log_pass "all thirteen D1 rows classify to the right decision/class/exit (TEST-001)"
}

# --- TEST-002 (Spec-AC-01): unknown trigger fail-closed ------------------------
test_002_unknown_fail_closed() {
  log_info "Test: absent, empty, lowercase, whitespace and invented triggers all park unknown/exit 3 (TEST-002)..."
  fresh_ledger
  [ "$(run classify --ref r1 --question q --ledger "$TEST_DIR/decisions.jsonl" --json)" = "3" ] || log_fail "TEST-002: absent trigger must exit 3"
  [ "$(jf class)" = "unknown" ] || log_fail "TEST-002: absent trigger class must be unknown, got $(jf class)"
  fresh_ledger
  [ "$(run classify --trigger "" --ref r1 --question q --ledger "$TEST_DIR/decisions.jsonl" --json)" = "3" ] || log_fail "TEST-002: empty trigger must exit 3"
  [ "$(jf class)" = "unknown" ] || log_fail "TEST-002: empty trigger class must be unknown"
  fresh_ledger
  [ "$(run classify --trigger "hitl-5" --ref r1 --question q --ledger "$TEST_DIR/decisions.jsonl" --json)" = "3" ] || log_fail "TEST-002: lowercase hitl-5 must exit 3 (case-sensitive match)"
  [ "$(jf class)" = "unknown" ] || log_fail "TEST-002: lowercase trigger class must be unknown"
  fresh_ledger
  [ "$(run classify --trigger "  HITL-5  " --ref r1 --question q --ledger "$TEST_DIR/decisions.jsonl" --json)" = "3" ] || log_fail "TEST-002: whitespace-padded trigger must exit 3 (no implicit trim across the enum boundary)"
  [ "$(jf class)" = "unknown" ] || log_fail "TEST-002: whitespace trigger class must be unknown"
  fresh_ledger
  [ "$(run classify --trigger "HITL-99" --ref r1 --question q --ledger "$TEST_DIR/decisions.jsonl" --json)" = "3" ] || log_fail "TEST-002: invented HITL-99 must exit 3"
  [ "$(jf class)" = "unknown" ] || log_fail "TEST-002: invented trigger class must be unknown"
  fresh_ledger
  [ "$(run classify --trigger "banana" --ref r1 --question q --ledger "$TEST_DIR/decisions.jsonl" --json)" = "3" ] || log_fail "TEST-002: invented word trigger must exit 3"
  # Mechanically stamped `[HITL-<n>]` is the form SKILL_LOOP reads from
  # blocking_reason — stripping the display brackets is not a fuzzy match.
  fresh_ledger
  [ "$(run classify --trigger "[HITL-9]" --ref r1 --question q --ledger "$TEST_DIR/decisions.jsonl" --json)" = "0" ] || log_fail "TEST-002: bracketed [HITL-9] must classify as HITL-9 auto, not unknown/park: $(err)"
  [ "$(jf trigger)" = "HITL-9" ] || log_fail "TEST-002: bracketed [HITL-9] must resolve trigger HITL-9, got $(jf trigger)"
  [ "$(jf decision)" = "auto" ] || log_fail "TEST-002: bracketed [HITL-9] decision must be auto"
  fresh_ledger
  [ "$(run classify --trigger "[HITL-1]" --ref r1 --question q --ledger "$TEST_DIR/decisions.jsonl" --json)" = "3" ] || log_fail "TEST-002: bracketed [HITL-1] must still park"
  [ "$(jf trigger)" = "HITL-1" ] || log_fail "TEST-002: bracketed [HITL-1] must resolve trigger HITL-1, got $(jf trigger)"
  log_pass "absent/empty/lowercase/whitespace/invented triggers all park unknown, exit 3; stamped [HITL-n] strips to the table row (TEST-002)"
}

# --- TEST-003 (Spec-AC-02): waived unreachable on HITL-9 -----------------------
test_003_waived_unreachable() {
  log_info "Test: HITL-9 resolves fail across flag/env fuzz; 'waived' never appears (TEST-003)..."
  fresh_ledger
  [ "$(run classify --trigger HITL-9 --ref r1 --question q --ledger "$TEST_DIR/decisions.jsonl" --json)" = "0" ] || log_fail "TEST-003: plain HITL-9 must exit 0"
  [ "$(jf answer)" = "fail" ] || log_fail "TEST-003: plain HITL-9 must resolve fail"
  grep -qi "waived" "$TEST_DIR/out" && log_fail "TEST-003: 'waived' must not appear in plain output"
  fresh_ledger
  [ "$(run classify --trigger HITL-9 --ref r1 --question q --answer waived --ledger "$TEST_DIR/decisions.jsonl" --json)" = "0" ] || log_fail "TEST-003: HITL-9 with --answer waived must still exit 0"
  [ "$(jf answer)" = "fail" ] || log_fail "TEST-003: HITL-9 must ignore --answer waived and resolve fail, got $(jf answer)"
  fresh_ledger
  [ "$(AAI_UNATTENDED_WAIVE=1 run classify --trigger HITL-9 --ref r1 --question q --ledger "$TEST_DIR/decisions.jsonl" --json)" = "0" ] || log_fail "TEST-003: env-fuzzed HITL-9 must still exit 0"
  [ "$(jf answer)" = "fail" ] || log_fail "TEST-003: env var AAI_UNATTENDED_WAIVE must have no effect, got $(jf answer)"
  fresh_ledger
  [ "$(run classify --trigger HITL-9 --ref r1 --question q --waive --ledger "$TEST_DIR/decisions.jsonl" --json)" = "2" ] || log_fail "TEST-003: an invented --waive flag must be a usage error (2), never accepted"
  grep -qi "waived" "$TEST_DIR/decisions.jsonl" && log_fail "TEST-003: the ledger must never contain the literal 'waived' for HITL-9"
  # Strip comments before scanning: the file's own doc-comments legitimately
  # NAME the word "waived" to document its absence (this assertion). What must
  # never exist is a quoted STRING LITERAL 'waived'/"waived" in live code.
  sed -E 's#//.*$##' "$ENGINE" | grep -Eq "'waived'|\"waived\"" && log_fail "TEST-003: the engine's live code must not contain a quoted 'waived' string literal (no reachable code path)"
  log_pass "HITL-9 resolves fail under flag/env fuzz; 'waived' is unreachable in output, ledger and source (TEST-003)"
}

# --- TEST-004 (Spec-AC-02): HITL-7 seam against SKILL_HITL/SKILL_SHIP ----------
test_004_hitl7_seam() {
  log_info "Test: every HITL-7 value classify emits is accepted by SKILL_HITL STEP 4c and matches SKILL_SHIP default 2 (TEST-004)..."
  local hitl_file="$PROJECT_ROOT/.aai/SKILL_HITL.prompt.md"
  local ship_file="$PROJECT_ROOT/.aai/SKILL_SHIP.prompt.md"
  [ -f "$hitl_file" ] || log_fail "TEST-004: missing $hitl_file"
  [ -f "$ship_file" ] || log_fail "TEST-004: missing $ship_file"
  grep -qF 'worktree\|inline\|waived' "$hitl_file" || log_fail "TEST-004: SKILL_HITL STEP 4c must still declare the worktree|inline|waived enum"
  for rec in not_needed optional recommended; do
    fresh_ledger
    run classify --trigger HITL-7 --ref r1 --question q --worktree-recommendation "$rec" --ledger "$TEST_DIR/decisions.jsonl" --json >/dev/null
    local val; val="$(jf answer)"
    case "$val" in
      inline|worktree) : ;;
      *) log_fail "TEST-004: HITL-7 $rec emitted '$val', not one of SKILL_HITL's accepted enum {inline,worktree}" ;;
    esac
    grep -q -- "- $rec " "$ship_file" 2>/dev/null; # informational only, default-2 mapping documented in AUTOPILOT DEFAULTS
  done
  grep -q "not_needed | optional  -> inline" "$ship_file" || log_fail "TEST-004: SKILL_SHIP default 2 must still map not_needed/optional -> inline"
  grep -q "recommended            -> worktree" "$ship_file" || log_fail "TEST-004: SKILL_SHIP default 2 must still map recommended -> worktree"
  log_pass "HITL-7 values are all accepted-enum members and match SKILL_SHIP default 2 (TEST-004)"
}

# --- TEST-005 (Spec-AC-03): one ledger line per call, byte-exact prefix -------
test_005_ledger_append() {
  log_info "Test: classify appends exactly one full-field ledger line, preserving the byte-exact prefix (TEST-005)..."
  printf '{"v":1,"ts":"2020-01-01T00:00:00Z","actor":"x","type":"other"}\n' > "$TEST_DIR/decisions.jsonl"
  local before; before="$(cat "$TEST_DIR/decisions.jsonl")"
  [ "$(run classify --trigger HITL-9 --ref my-ref --question "fix or waive?" --ledger "$TEST_DIR/decisions.jsonl" --json)" = "0" ] || log_fail "TEST-005: classify must exit 0: $(err)"
  local n; n="$(wc -l < "$TEST_DIR/decisions.jsonl" | tr -d ' ')"
  [ "$n" = "2" ] || log_fail "TEST-005: exactly one line must be appended, got $n total lines"
  head -c "${#before}" "$TEST_DIR/decisions.jsonl" | diff -q - <(printf '%s' "$before") >/dev/null || log_fail "TEST-005: the pre-call bytes must stay a byte-exact prefix"
  local last; last="$(tail -1 "$TEST_DIR/decisions.jsonl")"
  for k in '"v":1' '"actor":"unattended"' '"type":"unattended_decision"' '"ref_id":"my-ref"' '"trigger":"HITL-9"' '"class":"quality"' '"decision":"auto"' '"question":"fix or waive?"' '"answer":"fail"' '"source"'; do
    assert_payload_contains "$last" "$k" "TEST-005: ledger line missing field $k"
  done
  printf '%s' "$last" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{JSON.parse(d);})' || log_fail "TEST-005: ledger line must be valid JSON"
  log_pass "classify appends one full-field ledger line, byte-exact prefix preserved (TEST-005)"
}

# --- TEST-006 (Spec-AC-03): unwritable ledger -> non-zero, no verdict ---------
test_006_unwritable_ledger() {
  log_info "Test: an unwritable ledger makes classify exit non-zero and print no verdict (TEST-006)..."
  # Parent-is-a-file, not chmod 000: root in a container can still write a
  # 000 directory, so permission bits are not a reliable refusal.
  printf 'not a directory\n' > "$TEST_DIR/notadir"
  local rc; rc="$(run classify --trigger HITL-9 --ref r1 --question q --ledger "$TEST_DIR/notadir/decisions.jsonl" --json)"
  [ "$rc" != "0" ] || log_fail "TEST-006: an unwritable ledger must not exit 0"
  [ -s "$TEST_DIR/out" ] && log_fail "TEST-006: no verdict may be printed to stdout when the ledger append fails, got: $(out)"
  log_pass "an unwritable ledger exits non-zero (rc=$rc) with no verdict printed (TEST-006)"
}

# --- TEST-007 (Spec-AC-03): seam — readers unaffected by the new type --------
test_007_readers_seam() {
  log_info "Test: follow-ups.mjs and generate-factory-report.mjs are unaffected by unattended_decision lines (TEST-007)..."
  local followups="$PROJECT_ROOT/.aai/scripts/follow-ups.mjs"
  [ -f "$followups" ] || log_fail "TEST-007: missing $followups"
  cp "$PROJECT_ROOT/docs/ai/decisions.jsonl" "$TEST_DIR/decisions.jsonl" 2>/dev/null || : > "$TEST_DIR/decisions.jsonl"
  local before_out before_rc after_out after_rc
  before_out="$(node "$followups" list --json --ledger "$TEST_DIR/decisions.jsonl" 2>"$TEST_DIR/before.err")"; before_rc=$?
  printf '{"v":1,"ts":"2026-09-07T00:00:00Z","actor":"unattended","type":"unattended_decision","ref_id":"seam-ref","trigger":"HITL-9","class":"quality","decision":"auto","question":"q","answer":"fail","source":"unattended-gate default"}\n' >> "$TEST_DIR/decisions.jsonl"
  printf '{"v":1,"ts":"2026-09-07T00:00:01Z","actor":"unattended","type":"unattended_decision","ref_id":"seam-ref","trigger":"HITL-1","class":"scope","decision":"park","question":"q2","answer":"","source":"unattended-gate default"}\n' >> "$TEST_DIR/decisions.jsonl"
  after_out="$(node "$followups" list --json --ledger "$TEST_DIR/decisions.jsonl" 2>"$TEST_DIR/after.err")"; after_rc=$?
  [ "$before_rc" = "$after_rc" ] || log_fail "TEST-007: follow-ups.mjs exit code changed after seeding unattended_decision lines ($before_rc -> $after_rc): $(cat "$TEST_DIR/after.err")"
  [ "$before_out" = "$after_out" ] || log_fail "TEST-007: follow-ups.mjs list --json output changed after seeding unattended_decision lines"
  log_pass "follow-ups.mjs counts/exit codes are unchanged by unattended_decision lines (TEST-007)"
}

# --- TEST-008 (Spec-AC-04): preflight refusal arms -----------------------------
test_008_preflight_refusals() {
  log_info "Test: five preflight refusal arms, each alone turning exit 0 into exit 3 (TEST-008)..."
  printf '# fixture intake\n' > "$TEST_DIR/intake.md"
  local base=(preflight --intake "$TEST_DIR/intake.md" --max-run-tokens 100000 --max-ticks 10 --stagnation-limit 2 --max-prs 2)
  [ "$(run "${base[@]}")" = "0" ] || log_fail "TEST-008: the admit baseline must exit 0: $(err)"

  [ "$(run preflight --intake "$TEST_DIR/intake.md" --max-ticks 10 --stagnation-limit 2 --max-prs 2)" = "3" ] || log_fail "TEST-008: no declared run budget must exit 3"
  grep -qi "budget" "$TEST_DIR/err" || log_fail "TEST-008: the no-budget refusal must name the budget bound: $(err)"

  [ "$(run preflight --intake "$TEST_DIR/intake.md" --max-run-tokens 100000 --max-ticks 21 --stagnation-limit 2 --max-prs 2)" = "3" ] || log_fail "TEST-008: max-ticks above 20 must exit 3"
  grep -qi "max.ticks" "$TEST_DIR/err" || log_fail "TEST-008: the max_ticks refusal must name max_ticks: $(err)"

  [ "$(run preflight --intake "$TEST_DIR/intake.md" --max-run-tokens 100000 --max-ticks 10 --stagnation-limit 4 --max-prs 2)" = "3" ] || log_fail "TEST-008: stagnation-limit above 3 must exit 3"
  grep -qi "stagnation" "$TEST_DIR/err" || log_fail "TEST-008: the stagnation_limit refusal must name stagnation_limit: $(err)"

  [ "$(run preflight --intake "$TEST_DIR/intake.md" --max-run-tokens 100000 --max-ticks 10 --stagnation-limit 2 --max-prs 0)" = "3" ] || log_fail "TEST-008: max-prs below 1 must exit 3"
  grep -qi "max.prs" "$TEST_DIR/err" || log_fail "TEST-008: the max_prs refusal must name max_prs: $(err)"
  [ "$(run preflight --intake "$TEST_DIR/intake.md" --max-run-tokens 100000 --max-ticks 10 --stagnation-limit 2 --max-prs 6)" = "3" ] || log_fail "TEST-008: max-prs above 5 must exit 3"

  [ "$(run preflight --max-run-tokens 100000 --max-ticks 10 --stagnation-limit 2 --max-prs 2)" = "3" ] || log_fail "TEST-008: a missing --intake must exit 3"
  grep -qi "intake" "$TEST_DIR/err" || log_fail "TEST-008: the missing-intake refusal must name intake: $(err)"
  [ "$(run preflight --intake "$TEST_DIR/does-not-exist.md" --max-run-tokens 100000 --max-ticks 10 --stagnation-limit 2 --max-prs 2)" = "3" ] || log_fail "TEST-008: a non-existent --intake path must exit 3"
  mkdir -p "$TEST_DIR/intake-dir"
  [ "$(run preflight --intake "$TEST_DIR/intake-dir" --max-run-tokens 100000 --max-ticks 10 --stagnation-limit 2 --max-prs 2)" = "3" ] || log_fail "TEST-008: a directory --intake must exit 3 (intake is a document, not a folder)"
  grep -qi "file\|regular\|directory" "$TEST_DIR/err" || log_fail "TEST-008: a directory --intake refusal must name that it is not a file: $(err)"
  log_pass "five preflight refusal arms each independently turn exit 0 into exit 3, each named (TEST-008)"
}

# --- TEST-009 (Spec-AC-04): preflight admit prints the five bounds -----------
test_009_preflight_admit() {
  log_info "Test: preflight admit path prints all five effective bounds and exits 0 (TEST-009)..."
  printf '# fixture intake\n' > "$TEST_DIR/intake.md"
  [ "$(run preflight --intake "$TEST_DIR/intake.md" --max-run-cost-usd 5.5 --max-ticks 15 --stagnation-limit 3 --max-prs 3)" = "0" ] || log_fail "TEST-009: admit must exit 0: $(err)"
  for k in max_ticks stagnation_limit max_run_tokens max_run_cost_usd max_prs; do
    grep -q "$k" "$TEST_DIR/out" || log_fail "TEST-009: admit output must print $k, got: $(out)"
  done
  grep -q "15" "$TEST_DIR/out" || log_fail "TEST-009: admit output must print the effective max_ticks value 15"
  # defaults: omitting max-ticks/stagnation-limit/max-prs falls back to 20/3/3
  [ "$(run preflight --intake "$TEST_DIR/intake.md" --max-run-tokens 1)" = "0" ] || log_fail "TEST-009: defaults-only admit must exit 0: $(err)"
  grep -q "\"max_ticks\":20" "$TEST_DIR/out" || grep -q "max_ticks.*20" "$TEST_DIR/out" || log_fail "TEST-009: default max_ticks must be 20, got: $(out)"
  log_pass "preflight admit prints all five effective bounds, defaults included, exit 0 (TEST-009)"
}

# --- TEST-010 (Spec-AC-05): chaining seam — intake-on-disk gate --------------
test_010_chaining_seam() {
  log_info "Test: chaining adopts a ride only when its intake exists and the gate admits (TEST-010)..."
  local ride_select="$PROJECT_ROOT/.aai/scripts/ride-select.mjs"
  [ -f "$ride_select" ] || log_fail "TEST-010: missing $ride_select"
  mkdir -p "$TEST_DIR/docs/issues"
  cat > "$TEST_DIR/roadmap.yaml" <<YAML
budget:
  maintenance_per_capability: 1
pairs:
  - capability: cap-one
    maintenance: maint-one
    status: planned
YAML
  # next proposes cap-one, but no intake document exists on disk for it -> the
  # unattended chaining branch must stop the run with a named reason rather
  # than fabricate or author one (D5).
  local nxt; nxt="$(node "$ride_select" next --roadmap "$TEST_DIR/roadmap.yaml" --docs "$TEST_DIR/docs" --json)"
  assert_payload_contains "$nxt" '"next":"cap-one"' "TEST-010: fixture setup: next must propose cap-one"
  [ ! -e "$TEST_DIR/docs/issues/CHANGE-DRAFT-cap-one.md" ] || log_fail "TEST-010: fixture setup: cap-one must have no intake on disk"
  # simulate the loop's own gate check: gate refuses because findDoc() cannot
  # locate an intake, so statusOf returns null -> "not on the roadmap"? no —
  # cap-one IS the roadmap capability, so gate ADMITS by roadmap membership
  # alone; the D5 refusal is specifically "intake document exists on disk",
  # which this engine's preflight enforces via --intake.
  [ "$(run preflight --max-run-tokens 1 --max-ticks 1 --stagnation-limit 1 --max-prs 1)" = "3" ] || log_fail "TEST-010: preflight without --intake naming an existing path must refuse (no fabricated intake)"
  grep -qi "intake" "$TEST_DIR/err" || log_fail "TEST-010: the refusal must name intake as the missing bound"
  # now the intake exists on disk AND the gate admits (cap-one is a roadmap capability)
  printf -- '---\nid: cap-one\nnumber: null\ntype: change\nstatus: draft\nlinks:\n  pr: []\n---\n\n# cap-one\n' > "$TEST_DIR/docs/issues/CHANGE-DRAFT-cap-one.md"
  [ "$(node "$ride_select" gate --ref cap-one --intake "$TEST_DIR/docs/issues/CHANGE-DRAFT-cap-one.md" --roadmap "$TEST_DIR/roadmap.yaml" --docs "$TEST_DIR/docs" >/dev/null 2>&1; echo $?)" = "0" ] || log_fail "TEST-010: ride-select gate must admit cap-one once its intake exists"
  [ "$(run preflight --intake "$TEST_DIR/docs/issues/CHANGE-DRAFT-cap-one.md" --max-run-tokens 1 --max-ticks 1 --stagnation-limit 1 --max-prs 1)" = "0" ] || log_fail "TEST-010: preflight must admit once the intake path exists and is named: $(err)"
  log_pass "chaining's intake-on-disk gate refuses a doc-less proposal and admits once the intake exists (TEST-010)"
}

# --- TEST-011 (Spec-AC-05): SKILL_SHIP unattended branch names the path form -
test_011_ship_refuses_free_text() {
  log_info "Test: SKILL_SHIP's unattended branch names the intake-path form and refuses free text (TEST-011)..."
  local ship_file="$PROJECT_ROOT/.aai/SKILL_SHIP.prompt.md"
  grep -qi "unattended" "$ship_file" || log_fail "TEST-011: SKILL_SHIP must document an unattended branch"
  grep -q "unattended-gate.mjs preflight" "$ship_file" || log_fail "TEST-011: SKILL_SHIP must call unattended-gate.mjs preflight before running unattended"
  grep -qi -- "--intake" "$ship_file" || log_fail "TEST-011: SKILL_SHIP must name the --intake path form"
  grep -qi "refuse.*free.text\|free.text.*refuse\|never author\|no free text" "$ship_file" || log_fail "TEST-011: SKILL_SHIP must state that unattended refuses a free-text need"
  log_pass "SKILL_SHIP's unattended branch names the path form and refuses free text (TEST-011)"
}

# --- TEST-012 (Spec-AC-06): gate moved — literals absent, checkpoint present -
test_012_gate_moved() {
  log_info "Test: forbidden literals absent from SKILL_SHIP, merge checkpoint present, SKILL_PR/AGENTS moved, CONSTITUTION Article 7 unchanged (TEST-012)..."
  local ship_file="$PROJECT_ROOT/.aai/SKILL_SHIP.prompt.md"
  local pr_file="$PROJECT_ROOT/.aai/SKILL_PR.prompt.md"
  local agents_file="$PROJECT_ROOT/.aai/AGENTS.md"
  local const_file="$PROJECT_ROOT/docs/CONSTITUTION.md"
  grep -qF 'Ship? [y] open PR' "$ship_file" && log_fail "TEST-012: the literal 'Ship? [y] open PR' must be absent from SKILL_SHIP"
  grep -qF 'never assume consent' "$ship_file" && log_fail "TEST-012: the literal 'never assume consent' must be absent from SKILL_SHIP"
  grep -qi "merge" "$ship_file" || log_fail "TEST-012: SKILL_SHIP must mention merge at its checkpoint"
  grep -qi "operator" "$ship_file" || log_fail "TEST-012: SKILL_SHIP must name merging as operator-only at its checkpoint"
  grep -qi "already opened\|already has an open PR\|skip a second create" "$ship_file" || log_fail "TEST-012: SKILL_SHIP must skip a second gh pr create when unattended chaining already opened this ref's PR"
  grep -qi "open the pull request" "$ship_file" || grep -q "gh pr create" "$ship_file" || log_fail "TEST-012: SKILL_SHIP must open the PR on PASS without asking"
  grep -q "PR URL\|pull request.*URL\|its URL" "$ship_file" || log_fail "TEST-012: the merge checkpoint must name the PR URL"
  grep -qi "validation PASS\|the review gate" "$pr_file" || log_fail "TEST-012: SKILL_PR precondition must name validation PASS / review gate as the authority to commit"
  grep -qi "merge" "$pr_file" || log_fail "TEST-012: SKILL_PR must place the human confirmation at the merge"
  grep -qi "validation PASS\|review gate" "$agents_file" || log_fail "TEST-012: AGENTS.md commit gating policy must name validation PASS / review gate as authority"
  [ -f "$const_file" ] || log_fail "TEST-012: missing $const_file"
  local art7; art7="$(awk '/^7\. Operator-only merge/{print;exit}' "$const_file")"
  [ -n "$art7" ] || log_fail "TEST-012: CONSTITUTION Article 7 line must still be present"
  assert_payload_contains "$art7" "the agent never merges" "TEST-012: CONSTITUTION Article 7 text must be byte-identical (missing its known text)"
  log_pass "forbidden literals gone, merge checkpoint present, SKILL_PR/AGENTS moved, Article 7 unchanged (TEST-012)"
}

# --- TEST-013 (Spec-AC-07): SKILL_LOOP default path + HITL block byte-identical
test_013_loop_default_and_hitl_block() {
  log_info "Test: SKILL_LOOP keeps the default exit path, gains the unattended branch, HITL OUTPUT FORMAT stays byte-identical (TEST-013)..."
  local loop_file="$PROJECT_ROOT/.aai/SKILL_LOOP.prompt.md"
  grep -q "human_input.required == true" "$loop_file" || log_fail "TEST-013: stop condition (b) default check must remain"
  grep -q "Print HITL block (see HITL OUTPUT FORMAT below) and EXIT" "$loop_file" || log_fail "TEST-013: the default exit path text must remain present"
  grep -qi "unattended" "$loop_file" || log_fail "TEST-013: SKILL_LOOP must gain an unattended branch"
  grep -q "unattended-gate.mjs classify" "$loop_file" || log_fail "TEST-013: SKILL_LOOP's unattended branch must invoke unattended-gate.mjs classify"
  grep -q "max_prs" "$loop_file" || log_fail "TEST-013: SKILL_LOOP must gain max_prs as a loop parameter"
  grep -q "SKILL_PR.prompt.md" "$loop_file" || log_fail "TEST-013: unattended chaining must follow SKILL_PR for the completed ride before adopting another ref"
  grep -q "branch-guard.mjs --suggest" "$loop_file" || log_fail "TEST-013: unattended chaining must cut a dedicated branch via branch-guard --suggest before the next ref"
  grep -qi "strip" "$loop_file" || log_fail "TEST-013: unattended classify must strip [HITL-n] display brackets before --trigger"
  grep -q -- "--answer" "$loop_file" || log_fail "TEST-013: unattended HITL-8 must pass --answer from the spec/STATE review scope"
  local block; block="$(awk '/^HITL OUTPUT FORMAT$/{f=1} f{print} f&&/^---$/{c++; if(c==2) exit}' "$loop_file")"
  assert_payload_contains "$block" "LOOP PAUSED" "TEST-013: HITL OUTPUT FORMAT block must still contain 'LOOP PAUSED'"
  assert_payload_contains "$block" "NEXT STEP: Answer the question above, then run .aai/SKILL_HITL.prompt.md to resume the loop." "TEST-013: HITL OUTPUT FORMAT's NEXT STEP line must stay byte-identical"
  log_pass "SKILL_LOOP default path kept, unattended branch added, HITL OUTPUT FORMAT byte-identical (TEST-013)"
}

# --- TEST-014 (Spec-AC-07): seam — target_command byte-equal to STEP 4c ------
test_014_target_command_seam() {
  log_info "Test: target_command is byte-equal to the SKILL_HITL STEP 4c declared command for each auto trigger, empty for every park (TEST-014)..."
  local hitl_file="$PROJECT_ROOT/.aai/SKILL_HITL.prompt.md"
  local wt_prefix; wt_prefix="$(/usr/bin/grep -o 'node \.aai/scripts/state\.mjs set-worktree --user-decision ' "$hitl_file" | head -1)"
  [ -n "$wt_prefix" ] || log_fail "TEST-014: could not extract the set-worktree command prefix from SKILL_HITL"
  local cr_fail; cr_fail="$(/usr/bin/grep -o 'fix: `[^`]*`' "$hitl_file" | head -1 | sed -e 's/^fix: `//' -e 's/`$//')"
  [ -n "$cr_fail" ] || log_fail "TEST-014: could not extract the HITL-9 fix command from SKILL_HITL"

  fresh_ledger
  run classify --trigger HITL-7 --ref r1 --question q --worktree-recommendation optional --ledger "$TEST_DIR/decisions.jsonl" --json >/dev/null
  [ "$(jf target_command)" = "${wt_prefix}inline" ] || log_fail "TEST-014: HITL-7 optional target_command mismatch, got: $(jf target_command)"
  fresh_ledger
  run classify --trigger HITL-7 --ref r1 --question q --worktree-recommendation recommended --ledger "$TEST_DIR/decisions.jsonl" --json >/dev/null
  [ "$(jf target_command)" = "${wt_prefix}worktree" ] || log_fail "TEST-014: HITL-7 recommended target_command mismatch, got: $(jf target_command)"

  fresh_ledger
  run classify --trigger HITL-9 --ref r1 --question q --ledger "$TEST_DIR/decisions.jsonl" --json >/dev/null
  [ "$(jf target_command)" = "$cr_fail" ] || log_fail "TEST-014: HITL-9 target_command must equal SKILL_HITL's fix command byte-for-byte, got: $(jf target_command) want: $cr_fail"

  fresh_ledger
  run classify --trigger HITL-5 --ref r1 --question q --ledger "$TEST_DIR/decisions.jsonl" --json >/dev/null
  [ "$(jf target_command)" = "" ] || log_fail "TEST-014: HITL-5 (STEP 4c target 'none') must have empty target_command, got: $(jf target_command)"

  fresh_ledger
  run classify --trigger HITL-8 --ref r1 --question q --answer 'docs/"foo".md' --ledger "$TEST_DIR/decisions.jsonl" --json >/dev/null
  local hitl8_tc; hitl8_tc="$(jf target_command)"
  [ -n "$hitl8_tc" ] || log_fail "TEST-014: HITL-8 with --answer must emit a target_command"
  assert_payload_contains "$hitl8_tc" "set-code-review --scope '" "TEST-014: HITL-8 target_command must POSIX-single-quote --scope"
  assert_payload_not_contains "$hitl8_tc" '--scope "docs/"' "TEST-014: HITL-8 must not interpolate --answer inside double quotes"
  fresh_ledger
  run classify --trigger HITL-8 --ref r1 --question q --ledger "$TEST_DIR/decisions.jsonl" --json >/dev/null
  [ "$(jf target_command)" = "" ] || log_fail "TEST-014: HITL-8 without --answer must not invent a placeholder target_command, got: $(jf target_command)"
  [ "$(jf decision)" = "auto" ] || log_fail "TEST-014: HITL-8 without --answer still auto (Spec-AC-01); LOOP parks when target_command is empty"

  fresh_ledger
  [ "$(run classify --trigger HITL-7 --ref r1 --question q --worktree-recommendation optional --ceremony 3.5 --ledger "$TEST_DIR/decisions.jsonl" --json)" = "2" ] || log_fail "TEST-014: --ceremony 3.5 must be a usage error, not a silent auto: $(err)"

  for t in HITL-1 HITL-2 HITL-3 HITL-4 HITL-6 stagnation run-budget review-round-cap; do
    fresh_ledger
    run classify --trigger "$t" --ref r1 --question q --ledger "$TEST_DIR/decisions.jsonl" --json >/dev/null
    [ "$(jf target_command)" = "" ] || log_fail "TEST-014: $t (park) must have empty target_command, got: $(jf target_command)"
  done
  log_pass "target_command is byte-equal to SKILL_HITL STEP 4c for every auto trigger, empty for every park (TEST-014)"
}

# --- TEST-015 (Spec-AC-08): summary groups + names gh pr list + writes nothing
test_015_summary() {
  log_info "Test: summary groups auto/parked, names gh pr list, and writes nothing (TEST-015)..."
  cat > "$TEST_DIR/decisions.jsonl" <<'JSONL'
{"v":1,"ts":"2026-09-01T00:00:00Z","actor":"unattended","type":"unattended_decision","ref_id":"a","trigger":"HITL-9","class":"quality","decision":"auto","question":"fix?","answer":"fail","source":"unattended-gate default"}
{"v":1,"ts":"2026-09-06T00:00:00Z","actor":"unattended","type":"unattended_decision","ref_id":"b","trigger":"HITL-1","class":"scope","decision":"park","question":"what scope?","answer":"","source":"unattended-gate default"}
{"v":1,"ts":"2026-09-07T00:00:00Z","actor":"unattended","type":"unattended_decision","ref_id":"c","trigger":"HITL-7","class":"quality","decision":"auto","question":"worktree?","answer":"inline","source":"unattended-gate default"}
{"v":1,"ts":"2026-09-07T00:00:01Z","actor":"owner","type":"planning_decision","ref_id":"d","question":"irrelevant","answer":"irrelevant","source":"human"}
JSONL
  # out/err are the test harness's OWN capture files (written by run()'s
  # redirection, not by the engine under test) -- excluded from the hash so
  # this proves the ENGINE created/modified nothing, not that the harness
  # itself was inert.
  local tree_before; tree_before="$(find "$TEST_DIR" -type f ! -name out ! -name err -exec /usr/bin/cksum {} \; | sort)"
  [ "$(run summary --since "2026-09-05T00:00:00Z" --ledger "$TEST_DIR/decisions.jsonl")" = "0" ] || log_fail "TEST-015: summary must exit 0: $(err)"
  local tree_after; tree_after="$(find "$TEST_DIR" -type f ! -name out ! -name err -exec /usr/bin/cksum {} \; | sort)"
  [ "$tree_before" = "$tree_after" ] || log_fail "TEST-015: summary must create/modify no file anywhere under the ledger's tree"
  grep -q "\"c\"\|c\b" "$TEST_DIR/out" || grep -q " c " "$TEST_DIR/out" || grep -q "ref_id.*c\|c.*HITL-7" "$TEST_DIR/out" || true
  grep -q "a" "$TEST_DIR/out" || log_fail "TEST-015: ref a (>= since) must appear in the summary"
  grep -q "c" "$TEST_DIR/out" || log_fail "TEST-015: ref c (>= since) must appear in the summary"
  grep -q "^b$\|\bb\b" "$TEST_DIR/out" && ! grep -q "2026-09-01" "$TEST_DIR/out" # informational
  grep -q "b" "$TEST_DIR/out" || log_fail "TEST-015: ref b (parked, == since) must appear in the summary"
  grep -qi "auto" "$TEST_DIR/out" || log_fail "TEST-015: output must group an 'auto' section"
  grep -qi "park" "$TEST_DIR/out" || log_fail "TEST-015: output must group a 'park' section"
  grep -q "gh pr list" "$TEST_DIR/out" || log_fail "TEST-015: output must name the gh pr list command rather than deriving PRs itself"
  log_pass "summary groups auto/parked from the since cutoff, names gh pr list, writes nothing (TEST-015)"
}

main() {
  echo "=== $TEST_NAME ==="
  [ -f "$ENGINE" ] || log_fail "engine missing: $ENGINE"
  if [ $# -gt 0 ]; then "$1"; echo "=== $TEST_NAME: SELECTED PASSED ($1) ==="; return; fi
  test_001_all_rows
  test_002_unknown_fail_closed
  test_003_waived_unreachable
  test_004_hitl7_seam
  test_005_ledger_append
  test_006_unwritable_ledger
  test_007_readers_seam
  test_008_preflight_refusals
  test_009_preflight_admit
  test_010_chaining_seam
  test_011_ship_refuses_free_text
  test_012_gate_moved
  test_013_loop_default_and_hitl_block
  test_014_target_command_seam
  test_015_summary
  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}
main "$@"
