#!/usr/bin/env bash
#
# Test: USER_GUIDE <-> .claude/skills both-direction anti-drift reconciliation
# (docs/specs/SPEC-0127-spec-reporting-docs-true-up.md, TEST-007..009,
#  Spec-AC-01/Spec-AC-02; intake CHANGE-0140 AC-001/AC-002).
#
# Forward (TEST-007): every ANCHORED /aai-* slash-command mention in
# docs/USER_GUIDE.md must resolve to a .claude/skills/<name> directory OR be
# listed in the explicit ALLOWED_GENERATED array below (bootstrap-generated
# downstream example skills). The anchor (D2, widened by CHANGE-0141): the
# mention's `/` is preceded by start-of-line, whitespace, backtick, `(`,
# `|` (table cell) or `[` (markdown-link label) — which structurally
# excludes script paths (`.aai/scripts/aai-sync.sh`: `/` preceded by `s`)
# and URLs (`https://aai-reports-x.pages.dev`: preceded by `/`), so neither
# class ever needs a fuzzy allowlist. A miss FAILS naming the mention and
# its line number.
#
# Reverse (TEST-008): every vendored .claude/skills/aai-* directory must
# have a `/<name>` mention in docs/USER_GUIDE.md. The exception array is
# EMPTY after this scope (aai-factory-report was fixed, not excepted). A
# miss FAILS naming the skill.
#
# Truth pins (TEST-009, Spec-AC-01): the two dead feedback alias comments
# are gone, the hand-authored /aai-factory-report section exists OUTSIDE the
# AAI:USERGUIDE-ROLLUP markers (with a vs-/aai-dashboard comparison), and
# the command table + quick reference list it.
#
# Read-only over the real repo tree — no fixtures, nothing is mutated.
# bash 3.2 compatible (no ${var^^}, no declare -A, no mapfile). Here-strings
# instead of pipes into while-loops (set -euo pipefail safety; LEARNED
# test-harness shell-options trap).
#
# Usage:
#   bash tests/skills/test-aai-userguide-drift.sh                  # run all
#   bash tests/skills/test-aai-userguide-drift.sh test_007_forward
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-userguide-drift"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GUIDE="$PROJECT_ROOT/docs/USER_GUIDE.md"
SKILLS_DIR="$PROJECT_ROOT/.claude/skills"

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

check_deps() {
  log_info "Checking dependencies..."
  [[ -f "$GUIDE" ]] || log_fail "docs/USER_GUIDE.md not found: $GUIDE"
  [[ -d "$SKILLS_DIR" ]] || log_fail ".claude/skills not found: $SKILLS_DIR"
  log_pass "Dependencies checked"
}

# D2 anchored extractor: `/` preceded by BOL, whitespace, backtick, `(`, `|`
# or `[` (CHANGE-0141 Spec-AC-03: markdown-link-form mentions `[/aai-x](…)`
# were a forward false negative); name is aai- plus lowercase kebab segments.
MENTION_RE='(^|[[:space:]]|`|\(|\||\[)/aai-[a-z0-9]+(-[a-z0-9]+)*'

# Bootstrap-generated downstream example skills documented as generator
# OUTPUT (USER_GUIDE bootstrap example block) — legitimate mentions with no
# vendored .claude/skills directory. The ONLY forward exceptions (D2).
ALLOWED_GENERATED="aai-test-unit aai-test-e2e aai-build"

# extract_mentions <file> -> "<line>:<name>" per anchored mention
extract_mentions() {
  local raw m line name out=""
  raw="$(grep -onE "$MENTION_RE" "$1" || true)"
  while IFS= read -r m; do
    [[ -n "$m" ]] || continue
    line="${m%%:*}"
    name="$(sed -E 's|.*/(aai-[a-z0-9-]+).*|\1|' <<<"$m")"
    out="${out}${line}:${name}
"
  done <<<"$raw"
  printf '%s' "$out"
}

test_007_forward_reconcile() {  # TEST-007 (Spec-AC-02)
  log_info "Test: forward reconcile — every anchored /aai-* mention resolves to .claude/skills/<name> or ALLOWED_GENERATED (TEST-007)..."

  # Structural self-check: the anchor must exclude script paths and URLs and
  # admit a real slash mention (negative + positive control on the extractor
  # itself, not on the guide).
  local probe
  probe="$(mktemp "${TMPDIR:-/tmp}/aai-userguide-drift-probe.XXXXXX")"
  {
    echo 'run bash .aai/scripts/aai-sync.sh from the root'
    echo 'see https://aai-reports-abc123.pages.dev for the page'
    echo 'invoke `/aai-probe-positive` when needed'
    echo 'see [/aai-probe-link](https://example.com/docs) for details'
  } > "$probe"
  local probe_hits
  probe_hits="$(extract_mentions "$probe")"
  rm -f "$probe"
  grep -q "aai-probe-positive" <<<"$probe_hits" \
    || log_fail "TEST-007 extractor self-check: anchored positive control not extracted"
  # Link-form positive control (CHANGE-0141 Spec-AC-03): a regressed
  # extractor that drops `[` from the anchor class fails HERE, before ever
  # touching the guide.
  grep -q "aai-probe-link" <<<"$probe_hits" \
    || log_fail "TEST-007 extractor self-check: markdown-link-form positive control [/aai-probe-link](...) not extracted"
  grep -q "aai-sync" <<<"$probe_hits" \
    && log_fail "TEST-007 extractor self-check: script path .aai/scripts/aai-sync.sh must NOT match the anchor"
  grep -q "aai-reports" <<<"$probe_hits" \
    && log_fail "TEST-007 extractor self-check: URL host aai-reports-*.pages.dev must NOT match the anchor"

  local mentions misses="" entry line name
  mentions="$(extract_mentions "$GUIDE")"
  [[ -n "$mentions" ]] || log_fail "TEST-007 no anchored /aai-* mention found at all in docs/USER_GUIDE.md (extractor broken?)"
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    line="${entry%%:*}"
    name="${entry#*:}"
    if [[ -d "$SKILLS_DIR/$name" ]]; then continue; fi
    if [[ " $ALLOWED_GENERATED " == *" $name "* ]]; then continue; fi
    log_info "TEST-007 UNRESOLVED mention: /$name at docs/USER_GUIDE.md:$line (no .claude/skills/$name, not in ALLOWED_GENERATED)"
    misses="${misses} /$name@$line"
  done <<<"$mentions"
  [[ -z "$misses" ]] \
    || log_fail "TEST-007 forward reconcile: unresolved skill mention(s):$misses"
  log_pass "TEST-007 forward reconcile: every anchored /aai-* mention resolves (or is an explicit generated-example exception)"
}

test_008_reverse_reconcile() {  # TEST-008 (Spec-AC-02)
  log_info "Test: reverse reconcile — every vendored .claude/skills/aai-* has a /<name> mention in USER_GUIDE (TEST-008)..."

  # EMPTY after this scope (D2): aai-factory-report is fixed, not excepted.
  local REVERSE_EXCEPTIONS=""

  local dir name misses="" count=0
  for dir in "$SKILLS_DIR"/aai-*/; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    count=$((count + 1))
    if [[ -n "$REVERSE_EXCEPTIONS" && " $REVERSE_EXCEPTIONS " == *" $name "* ]]; then continue; fi
    if ! grep -qE "(^|[[:space:]]|\`|\(|\|)/${name}([^a-z0-9-]|$)" "$GUIDE"; then
      log_info "TEST-008 UNDOCUMENTED vendored skill: $name (no anchored /$name mention in docs/USER_GUIDE.md)"
      misses="${misses} $name"
    fi
  done
  [[ "$count" -gt 0 ]] || log_fail "TEST-008 no .claude/skills/aai-* directories found (repo layout changed?)"
  [[ -z "$misses" ]] \
    || log_fail "TEST-008 reverse reconcile: vendored skill(s) missing from USER_GUIDE:$misses"
  log_pass "TEST-008 reverse reconcile: all $count vendored skills are mentioned (exception array empty)"
}

test_009_truth_pins() {  # TEST-009 (Spec-AC-01)
  log_info "Test: truth pins — dead feedback aliases gone, /aai-factory-report documented outside the rollup markers (TEST-009)..."
  local ok=1

  if grep -qF '# or /aai-feedback-triage' "$GUIDE"; then
    log_info "TEST-009 dead alias comment still present: '# or /aai-feedback-triage' (no .claude/skills/aai-feedback-triage exists)"
    ok=0
  fi
  if grep -qF '# or /aai-feedback-upsert' "$GUIDE"; then
    log_info "TEST-009 dead alias comment still present: '# or /aai-feedback-upsert' (no .claude/skills/aai-feedback-upsert exists)"
    ok=0
  fi
  # The feedback section itself must SURVIVE (intake correction: the scripts
  # are real; only the skill aliases were dead).
  if ! grep -qF 'node .aai/scripts/aai-feedback-triage.mjs' "$GUIDE" \
    || ! grep -qF 'node .aai/scripts/aai-feedback-upsert.mjs' "$GUIDE"; then
    log_info "TEST-009 feedback SCRIPT documentation must stay (the .mjs engines exist and are vendored)"
    ok=0
  fi

  local section_line begin_line
  section_line="$(grep -nF '#### `/aai-factory-report`' "$GUIDE" || true)"
  if [[ -z "$section_line" ]]; then
    log_info "TEST-009 missing hand-authored section heading: '#### \`/aai-factory-report\`'"
    ok=0
  else
    section_line="${section_line%%:*}"
    begin_line="$(grep -nE '^<!--[ \t]*AAI:USERGUIDE-ROLLUP:BEGIN' "$GUIDE" || true)"
    begin_line="${begin_line%%:*}"
    if [[ -n "$begin_line" && "$section_line" -ge "$begin_line" ]]; then
      log_info "TEST-009 /aai-factory-report section sits INSIDE the generated rollup (line $section_line >= marker line $begin_line) — hand prose must live outside the markers"
      ok=0
    fi
    # The section must carry the vs-/aai-dashboard comparison (D1b).
    local section_body
    section_body="$(sed -n "${section_line},$((section_line + 40))p" "$GUIDE")"
    if ! grep -q 'aai-dashboard' <<<"$section_body"; then
      log_info "TEST-009 /aai-factory-report section lacks the when-vs-/aai-dashboard comparison"
      ok=0
    fi
  fi

  if ! grep -qE '^\|[ ]*`/aai-factory-report`' "$GUIDE"; then
    log_info "TEST-009 command table row for /aai-factory-report missing"
    ok=0
  fi
  if ! grep -qE '^-[ ]*`/aai-factory-report`' "$GUIDE"; then
    log_info "TEST-009 quick-reference entry for /aai-factory-report missing"
    ok=0
  fi

  [[ $ok -eq 1 ]] \
    && log_pass "TEST-009 truth pins: dead aliases gone, feedback scripts kept, /aai-factory-report section + table row + quick-ref present outside markers" \
    || log_fail "TEST-009 truth pins (see INFO lines above)"
}

main() {
  echo "=== Test: $TEST_NAME ==="
  check_deps
  if [[ $# -gt 0 ]]; then
    "$1"
  else
    test_007_forward_reconcile
    test_008_reverse_reconcile
    test_009_truth_pins
  fi
  echo "=== All $TEST_NAME tests passed ==="
}

main "$@"
