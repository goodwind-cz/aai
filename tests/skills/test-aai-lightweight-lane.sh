#!/usr/bin/env bash
#
# Test: deterministic PR fast-lane gate (CHANGE lightweight-e2e-lane /
# SPEC spec-lightweight-e2e-lane, TEST-001..016).
#
# Verifies .aai/scripts/lane-gate.mjs — the deterministic, zero-dep,
# always-exit-0 gate that decides whether a ride takes the PR FAST LANE
# (narrowed CI + on-demand sweep) or the unchanged HEAVY lane. The gate is a
# conjunction of FOUR machine-read predicates:
#   1. ceremony_level in {0,1}          (frozen spec frontmatter)
#   2. strategy in {direct,untested,loop} (STATE implementation_strategy)
#   3. select-suites.mjs != FULL_RUN    (no protected-l3/shared-lib/unmapped)
#   4. changed-file count < N AND diff surface classes subset of
#      {docs, prose, <=1 test, <=1 script}
# ANY predicate false, unknown, or degenerate -> HEAVY (fail-closed,
# anti-gaming: a mis-declaration can only ever ADD ceremony).
#
# All fixtures use scratch temp-dir trees carrying their OWN tiny spec,
# STATE, suite-map.yaml and docs-audit.yaml — the real repo is never touched.
# The script under test is overridable via LANE_GATE_SCRIPT.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-lightweight-lane"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Pipe-free payload assertions (spec-assertions-must-not-die-on-their-own-payload).
# shellcheck source=lib/assert-payload.sh
. "$SCRIPT_DIR/lib/assert-payload.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE="${LANE_GATE_SCRIPT:-$PROJECT_ROOT/.aai/scripts/lane-gate.mjs}"

TEST_DIR=""
cleanup() {
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
  [[ -f "$GATE" ]] || log_fail "Gate script not found: $GATE"
  log_pass "Dependencies checked"
}

# ---- fixture helpers -------------------------------------------------

# fixture <dir> <ceremony_level|-> <strategy|-> — builds a fixture repo-root
# with a suite-map, a docs-audit.yaml (protected_paths_l3), a spec (unless
# level is '-'), and a STATE (unless strategy is '-'). Classes exercised by
# the map: docs/** (docs), .aai/*.prompt.md (prose), tests/** (test),
# .aai/scripts/*.mjs (script), plus config/*.yml (a MAPPED but unclassified
# surface -> proves predicate 4 is stricter than predicate 3).
fixture() {
  local dir="$1" level="$2" strategy="$3"
  mkdir -p "$dir/tests/skills" "$dir/docs/specs" "$dir/docs/ai"
  cat > "$dir/tests/skills/suite-map.yaml" <<'YAML'
core:
  - aai-core-a

full_run_triggers:
  shared_lib_globs:
    - .aai/scripts/lib/**

suites:
  aai-core-a:
    globs:
      - docs/**
      - .aai/*.prompt.md
      - tests/**
      - .aai/scripts/*.mjs
      - config/*.yml
YAML
  cat > "$dir/docs/ai/docs-audit.yaml" <<'YAML'
protected_paths_l3:
  - .aai/scripts/state.mjs
  - docs/CONSTITUTION.md
YAML
  # minimal PROFILES: close-work-item is a CORE workflow engine (never fast);
  # any other .aai/scripts path is non-core -> script class fast-eligible.
  mkdir -p "$dir/.aai/system"
  cat > "$dir/.aai/system/PROFILES.yaml" <<'YAML'
core:
  - .aai/scripts/close-work-item.mjs
extended:
  - .aai/scripts/one.mjs
YAML
  if [[ "$level" != "-" ]]; then
    printf -- '---\nid: fx\nstatus: implementing\nceremony_level: %s\n---\n\nbody\n' "$level" \
      > "$dir/docs/specs/SPEC-DRAFT-fx.md"
  fi
  if [[ "$strategy" != "-" ]]; then
    printf 'implementation_strategy:\n  selected: %s\n  source: intake\n' "$strategy" \
      > "$dir/docs/ai/STATE.yaml"
  fi
}

# run_gate <dir> <files...> — invoke the gate via --files-from on a newline
# list; captures stdout+stderr to $OUT and exit code to $CODE.
run_gate() {
  local dir="$1"; shift
  local list="$dir/files.txt"
  printf '%s\n' "$@" > "$list"
  OUT="$(node "$GATE" --repo-root "$dir" --spec "$dir/docs/specs/SPEC-DRAFT-fx.md" \
    --state "$dir/docs/ai/STATE.yaml" --files-from "$list" --max-files 5 2>&1)"
  CODE=$?
}

# run_gate_empty <dir> — invoke with an empty diff.
run_gate_empty() {
  local dir="$1"
  : > "$dir/files.txt"
  OUT="$(node "$GATE" --repo-root "$dir" --spec "$dir/docs/specs/SPEC-DRAFT-fx.md" \
    --state "$dir/docs/ai/STATE.yaml" --files-from "$dir/files.txt" --max-files 5 2>&1)"
  CODE=$?
}

mk() { TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-lightweight-lane.XXXXXX")"; }

# ---- tests -----------------------------------------------------------

test_001_all_true_fast() {  # Spec-AC-01
  log_info "Test: all four predicates true -> LANE fast (TEST-001)..."
  mk; fixture "$TEST_DIR" 1 direct
  run_gate "$TEST_DIR" "docs/x.md" "tests/skills/test-x.sh"
  [[ "$CODE" -eq 0 ]] || log_fail "exit must be 0, got $CODE: $OUT"
  echo "$OUT" | grep -qE '^LANE fast$' || log_fail "expected LANE fast: $OUT"
  log_pass "All predicates true -> fast lane (TEST-001)"
}

test_002_ceremony_l2_heavy() {  # Spec-AC-02
  log_info "Test: ceremony_level 2 -> HEAVY (TEST-002)..."
  mk; fixture "$TEST_DIR" 2 direct
  run_gate "$TEST_DIR" "docs/x.md"
  [[ "$CODE" -eq 0 ]] || log_fail "exit must be 0, got $CODE: $OUT"
  echo "$OUT" | grep -qE '^LANE heavy reason=ceremony_level' || log_fail "expected heavy reason=ceremony_level: $OUT"
  log_pass "L2 -> heavy (TEST-002)"
}

test_003_ceremony_absent_heavy() {  # Spec-AC-02 (fail-closed / degenerate)
  log_info "Test: absent/garbage ceremony_level -> HEAVY (TEST-003)..."
  mk; fixture "$TEST_DIR" 1 direct
  # overwrite the spec with a garbage ceremony token
  printf -- '---\nid: fx\nstatus: implementing\nceremony_level: banana\n---\nbody\n' \
    > "$TEST_DIR/docs/specs/SPEC-DRAFT-fx.md"
  run_gate "$TEST_DIR" "docs/x.md"
  [[ "$CODE" -eq 0 ]] || log_fail "exit must be 0, got $CODE: $OUT"
  echo "$OUT" | grep -qE '^LANE heavy reason=ceremony_level' || log_fail "garbage ceremony must be heavy: $OUT"
  log_pass "Garbage ceremony_level -> heavy (TEST-003)"
}

test_004_strategy_tdd_heavy() {  # Spec-AC-02
  log_info "Test: strategy tdd (not in fast set) -> HEAVY (TEST-004)..."
  mk; fixture "$TEST_DIR" 1 tdd
  run_gate "$TEST_DIR" "docs/x.md"
  [[ "$CODE" -eq 0 ]] || log_fail "exit must be 0, got $CODE: $OUT"
  echo "$OUT" | grep -qE '^LANE heavy reason=strategy' || log_fail "expected heavy reason=strategy: $OUT"
  log_pass "strategy tdd -> heavy (TEST-004)"
}

test_005_strategy_absent_heavy() {  # Spec-AC-02 (fail-closed)
  log_info "Test: absent STATE strategy -> HEAVY (TEST-005)..."
  mk; fixture "$TEST_DIR" 1 -
  run_gate "$TEST_DIR" "docs/x.md"
  [[ "$CODE" -eq 0 ]] || log_fail "exit must be 0, got $CODE: $OUT"
  echo "$OUT" | grep -qE '^LANE heavy reason=strategy' || log_fail "missing strategy must be heavy: $OUT"
  log_pass "absent strategy -> heavy (TEST-005)"
}

test_006_protected_l3_heavy() {  # Spec-AC-02 (reuses select-suites FULL_RUN triad)
  log_info "Test: a protected_paths_l3 path -> HEAVY reason=full_run (TEST-006)..."
  mk; fixture "$TEST_DIR" 1 direct
  run_gate "$TEST_DIR" "docs/CONSTITUTION.md"
  [[ "$CODE" -eq 0 ]] || log_fail "exit must be 0, got $CODE: $OUT"
  echo "$OUT" | grep -qE '^LANE heavy reason=full_run' || log_fail "protected-l3 must be heavy full_run: $OUT"
  log_pass "protected-l3 -> heavy full_run (TEST-006)"
}

test_007_unmapped_heavy() {  # Spec-AC-02
  log_info "Test: an unmapped path -> HEAVY reason=full_run (TEST-007)..."
  mk; fixture "$TEST_DIR" 1 direct
  run_gate "$TEST_DIR" "totally/unmapped/file.txt"
  [[ "$CODE" -eq 0 ]] || log_fail "exit must be 0, got $CODE: $OUT"
  echo "$OUT" | grep -qE '^LANE heavy reason=full_run' || log_fail "unmapped must be heavy full_run: $OUT"
  log_pass "unmapped -> heavy full_run (TEST-007)"
}

test_008_too_many_files_heavy() {  # Spec-AC-02
  log_info "Test: changed-file count >= N -> HEAVY reason=diff_surface (TEST-008)..."
  mk; fixture "$TEST_DIR" 1 direct
  run_gate "$TEST_DIR" "docs/a.md" "docs/b.md" "docs/c.md" "docs/d.md" "docs/e.md"
  [[ "$CODE" -eq 0 ]] || log_fail "exit must be 0, got $CODE: $OUT"
  echo "$OUT" | grep -qE '^LANE heavy reason=diff_surface' || log_fail "over-count must be heavy diff_surface: $OUT"
  log_pass "count >= N -> heavy (TEST-008)"
}

test_009_two_test_files_heavy() {  # Spec-AC-02
  log_info "Test: two test files -> HEAVY (single-test-only) (TEST-009)..."
  mk; fixture "$TEST_DIR" 1 direct
  run_gate "$TEST_DIR" "tests/skills/test-a.sh" "tests/skills/test-b.sh"
  [[ "$CODE" -eq 0 ]] || log_fail "exit must be 0, got $CODE: $OUT"
  echo "$OUT" | grep -qE '^LANE heavy reason=diff_surface' || log_fail "two tests must be heavy: $OUT"
  log_pass "two test files -> heavy (TEST-009)"
}

test_010_two_scripts_heavy() {  # Spec-AC-02
  log_info "Test: two script files -> HEAVY (single-script-only) (TEST-010)..."
  mk; fixture "$TEST_DIR" 1 direct
  run_gate "$TEST_DIR" ".aai/scripts/a.mjs" ".aai/scripts/b.mjs"
  [[ "$CODE" -eq 0 ]] || log_fail "exit must be 0, got $CODE: $OUT"
  echo "$OUT" | grep -qE '^LANE heavy reason=diff_surface' || log_fail "two scripts must be heavy: $OUT"
  log_pass "two script files -> heavy (TEST-010)"
}

test_011_mapped_but_unclassified_heavy() {  # Spec-AC-02 (predicate 4 stricter than 3)
  log_info "Test: a MAPPED but unclassified surface (config/*.yml) -> HEAVY (TEST-011)..."
  mk; fixture "$TEST_DIR" 1 direct
  # config/app.yml is mapped (no FULL_RUN) yet is neither docs/prose/test/script.
  run_gate "$TEST_DIR" "config/app.yml"
  [[ "$CODE" -eq 0 ]] || log_fail "exit must be 0, got $CODE: $OUT"
  echo "$OUT" | grep -qE '^LANE heavy reason=diff_surface' \
    || log_fail "mapped-but-unclassified must be heavy diff_surface (not fast): $OUT"
  log_pass "mapped-but-unclassified -> heavy (TEST-011)"
}

test_012_missing_spec_heavy() {  # Spec-AC-02 (fail-closed)
  log_info "Test: missing spec file -> HEAVY (TEST-012)..."
  mk; fixture "$TEST_DIR" - direct
  OUT="$(node "$GATE" --repo-root "$TEST_DIR" --spec "$TEST_DIR/docs/specs/does-not-exist.md" \
    --state "$TEST_DIR/docs/ai/STATE.yaml" --files-from <(echo "docs/x.md") --max-files 5 2>&1)"; CODE=$?
  [[ "$CODE" -eq 0 ]] || log_fail "exit must be 0, got $CODE: $OUT"
  echo "$OUT" | grep -qE '^LANE heavy reason=ceremony_level' || log_fail "missing spec must be heavy: $OUT"
  log_pass "missing spec -> heavy (TEST-012)"
}

test_013_auditable_predicate_lines() {  # Spec-AC-07
  log_info "Test: fast verdict emits every predicate value (auditable) (TEST-013)..."
  mk; fixture "$TEST_DIR" 0 loop
  run_gate "$TEST_DIR" "docs/x.md" ".aai/scripts/one.mjs"
  [[ "$CODE" -eq 0 ]] || log_fail "exit must be 0, got $CODE: $OUT"
  echo "$OUT" | grep -qE '^LANE fast$' || log_fail "expected fast: $OUT"
  echo "$OUT" | grep -qE '^ceremony_level=0' || log_fail "must emit ceremony_level value: $OUT"
  echo "$OUT" | grep -qE '^strategy=loop' || log_fail "must emit strategy value: $OUT"
  echo "$OUT" | grep -qE '^changed_files=2' || log_fail "must emit changed_files value: $OUT"
  echo "$OUT" | grep -qE '^suite_selection=' || log_fail "must emit suite_selection value: $OUT"
  echo "$OUT" | grep -qE '^diff_classes=' || log_fail "must emit diff_classes value: $OUT"
  log_pass "predicate values are auditable (TEST-013)"
}

test_014_always_exit_zero() {  # Spec-AC-01 (never fails the ceremony)
  log_info "Test: degenerate inputs still exit 0, defaulting to HEAVY (TEST-014)..."
  mk
  # no --spec, no --state, no --files-from: everything missing -> heavy, exit 0
  OUT="$(node "$GATE" --repo-root "$TEST_DIR" 2>&1)"; CODE=$?
  [[ "$CODE" -eq 0 ]] || log_fail "missing-everything must still exit 0, got $CODE: $OUT"
  echo "$OUT" | grep -qE '^LANE heavy' || log_fail "missing-everything must be heavy: $OUT"
  log_pass "always exit 0, degenerate -> heavy (TEST-014)"
}

test_015_ceremony_l0_fast() {  # Spec-AC-01 (boundary: L0 also fast)
  log_info "Test: ceremony_level 0 is also fast-eligible (TEST-015)..."
  mk; fixture "$TEST_DIR" 0 untested
  run_gate "$TEST_DIR" "docs/x.md"
  [[ "$CODE" -eq 0 ]] || log_fail "exit must be 0, got $CODE: $OUT"
  echo "$OUT" | grep -qE '^LANE fast$' || log_fail "L0 + untested must be fast: $OUT"
  log_pass "L0 boundary -> fast (TEST-015)"
}

test_016_empty_diff_fast() {  # Spec-AC-01 (degenerate empty diff, gate-metadata still ok)
  log_info "Test: empty diff with ok ceremony/strategy -> fast (TEST-016)..."
  mk; fixture "$TEST_DIR" 1 direct
  run_gate_empty "$TEST_DIR"
  [[ "$CODE" -eq 0 ]] || log_fail "exit must be 0, got $CODE: $OUT"
  echo "$OUT" | grep -qE '^LANE fast$' || log_fail "empty diff must be fast: $OUT"
  echo "$OUT" | grep -qE '^changed_files=0' || log_fail "empty diff must report changed_files=0: $OUT"
  log_pass "empty diff -> fast (TEST-016)"
}

test_017_docs_only_close_diff_never_full() {  # Spec-AC-04 (EFFECT 1/2)
  log_info "Test: a docs-only close-commit diff routes to CORE via the REAL select-suites, never FULL_RUN (TEST-017)..."
  local selector="$PROJECT_ROOT/.aai/scripts/select-suites.mjs"
  [[ -f "$selector" ]] || log_skip "select-suites.mjs not found: $selector"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  # The exact surfaces a close-work-item.mjs commit touches: doc frontmatter
  # (docs/issues|specs/**), the append-only events log, and the regen'd INDEX.
  local diff="docs/issues/CHANGE-0095-contract-headroom.md
docs/specs/SPEC-0053-spec-deterministic-close-ceremony.md
docs/ai/EVENTS.jsonl
docs/INDEX.md"
  local out
  out="$(printf '%s\n' "$diff" | node "$selector" --repo-root "$PROJECT_ROOT" --files-from - 2>&1)"
  echo "$out" | grep -qE '^FULL_RUN' && log_fail "docs-only close diff must NOT trigger FULL_RUN: $out"
  echo "$out" | grep -qE '^CORE aai-docs-audit reason=core$' \
    || log_fail "docs-only close diff must route to the CORE aai-docs-audit suite: $out"
  log_pass "docs-only close-commit diff stays CORE-only, never FULL_RUN (TEST-017)"
}

test_018_skill_pr_fast_lane_contract() {  # Spec-AC-03/AC-07 (grep-contract)
  log_info "Test: SKILL_PR wires the fast-lane gate, on-demand sweep, and the mandatory internal review compensating control (TEST-018)..."
  local pr="$PROJECT_ROOT/.aai/SKILL_PR.prompt.md"
  [[ -f "$pr" ]] || log_fail "SKILL_PR.prompt.md not found: $pr"
  local ok=1
  grep -qF "lane-gate.mjs" "$pr" || { log_info "TEST-018: SKILL_PR must invoke lane-gate.mjs"; ok=0; }
  grep -qF "LANE fast" "$pr" || { log_info "TEST-018: SKILL_PR must name the LANE fast verdict"; ok=0; }
  grep -qiF "optional-on-demand" "$pr" || { log_info "TEST-018: 5d fast-lane sweep must be optional-on-demand"; ok=0; }
  grep -qiF "sweep skipped (fast" "$pr" || { log_info "TEST-018: fast-lane sweep-skip note missing"; ok=0; }
  grep -qiF "internal dual-verdict" "$pr" || { log_info "TEST-018: mandatory internal dual-verdict review (compensating control) missing"; ok=0; }
  grep -qiF "re-arm" "$pr" || { log_info "TEST-018: sweep re-arm path missing"; ok=0; }
  grep -qiF "## Lane" "$pr" || { log_info "TEST-018: PR body ## Lane auditability section missing"; ok=0; }
  # HEAVY lane stays the default (byte-for-byte) — the prose must say so.
  grep -qiF "HEAVY lane" "$pr" || { log_info "TEST-018: HEAVY lane default not named"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "SKILL_PR fast-lane gate + on-demand sweep + mandatory internal review pinned (TEST-018)" \
    || log_fail "TEST-018 SKILL_PR fast-lane contract"
}

# --- TEST-019 — rename-blindness closed: a renamed protected file -> heavy ----
# (validation RR-rename-blindness) --no-renames surfaces delete+add, so the
# protected SOURCE path reaches the predicates even when git would report R100.
test_019_rename_blindness() {
  log_info "Test: renamed protected file (delete+add via --no-renames) -> heavy (TEST-019)..."
  mk; fixture "$TEST_DIR" 1 direct
  run_gate "$TEST_DIR" ".aai/scripts/state.mjs" "docs/renamed-state.md"
  [[ "$CODE" -eq 0 ]] || log_fail "exit must be 0, got $CODE: $OUT"
  echo "$OUT" | grep -qE '^LANE heavy' || log_fail "TEST-019: protected rename slipped through: $OUT"
  # both diff readers must pass --no-renames so the source path stays visible
  grep -qF -- "--no-renames" "$GATE" || log_fail "TEST-019: lane-gate diff reader missing --no-renames"
  grep -qF -- "--no-renames" "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" \
    || log_fail "TEST-019: select-suites diff reader missing --no-renames"
  log_pass "Renamed protected source stays visible -> heavy (TEST-019)"
}

# --- TEST-020 — prose (prompt corpus) capped at 1 -----------------------------
# (validation RR-prose-uncapped) a multi-prompt ride keeps the external sweep.
test_020_prose_cap() {
  log_info "Test: 2 prompt-corpus files -> heavy (prose max 1); 1 -> fast (TEST-020)..."
  mk; fixture "$TEST_DIR" 1 direct
  run_gate "$TEST_DIR" ".aai/SKILL_DEBUG.prompt.md" ".aai/SKILL_SCOUT.prompt.md"
  echo "$OUT" | grep -qE '^LANE heavy reason=diff_surface' || log_fail "TEST-020: 2 prompts must be heavy: $OUT"
  mk; fixture "$TEST_DIR" 1 direct
  run_gate "$TEST_DIR" ".aai/SKILL_DEBUG.prompt.md"
  echo "$OUT" | grep -qE '^LANE fast$' || log_fail "TEST-020: single prompt unexpectedly heavy: $OUT"
  log_pass "Prose cap: 2 prompts heavy, 1 prompt fast (TEST-020)"
}

# --- TEST-021 — core workflow script never fast (bot P1) ----------------------
test_021_core_script_heavy() {
  log_info "Test: PROFILES-core workflow script (close-work-item.mjs) -> heavy (TEST-021)..."
  mk; fixture "$TEST_DIR" 1 direct
  run_gate "$TEST_DIR" ".aai/scripts/close-work-item.mjs"
  echo "$OUT" | grep -qE '^LANE heavy' || log_fail "TEST-021: core engine slipped into fast lane: $OUT"
  # a genuinely non-core script stays fast-eligible (negative control)
  mk; fixture "$TEST_DIR" 1 direct
  run_gate "$TEST_DIR" "docs/x.md"
  echo "$OUT" | grep -qE '^LANE fast$' || log_fail "TEST-021: docs-only control unexpectedly heavy: $OUT"
  log_pass "Core workflow engine -> heavy; control fast (TEST-021)"
}

# --- TEST-022 — missing protected-path config -> heavy (bot P2) ----------------
test_022_missing_protected_config_heavy() {
  log_info "Test: absent docs/ai/docs-audit.yaml -> heavy reason=protected_config_missing (TEST-022)..."
  mk; fixture "$TEST_DIR" 1 direct
  rm -f "$TEST_DIR/docs/ai/docs-audit.yaml"
  run_gate "$TEST_DIR" "docs/x.md"
  echo "$OUT" | grep -qE '^LANE heavy reason=protected_config_missing' \
    || log_fail "TEST-022: missing protected config must fail closed: $OUT"
  log_pass "Missing protected-path config -> heavy fail-closed (TEST-022)"
}

test_023_intake_ceremony_fallback() {  # CHANGE lane-intake-ceremony
  log_info "Test: spec-less ride reads ceremony from intake frontmatter; source labeled (TEST-023)..."
  mk; fixture "$TEST_DIR" 1 direct
  rm -f "$TEST_DIR/docs/specs/SPEC-DRAFT-fx.md"
  mkdir -p "$TEST_DIR/docs/issues"
  printf -- '---\nid: fx\nceremony_level: 1\n---\n' > "$TEST_DIR/docs/issues/CHANGE-DRAFT-fx.md"
  local list="$TEST_DIR/files.txt"; printf 'docs/x.md\n' > "$list"
  # spec-less invocation = NO --spec flag at all (SKILL_PR passes --spec only
  # when a spec exists; an explicit-but-missing path is the TEST-023d arm)
  OUT="$(node "$GATE" --repo-root "$TEST_DIR" \
    --intake "$TEST_DIR/docs/issues/CHANGE-DRAFT-fx.md" \
    --state "$TEST_DIR/docs/ai/STATE.yaml" --files-from "$list" --max-files 5 2>&1)"; CODE=$?
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-023: exit must be 0, got $CODE: $OUT"
  echo "$OUT" | grep -qE '^LANE fast$' || log_fail "TEST-023: spec-less + intake L1 must be fast: $OUT"
  assert_payload_contains "$OUT" "source=intake" "TEST-023: predicate line must label source=intake: $OUT"
  # garbage intake level -> heavy (fail-closed unchanged)
  printf -- '---\nid: fx\nceremony_level: banana\n---\n' > "$TEST_DIR/docs/issues/CHANGE-DRAFT-fx.md"
  OUT="$(node "$GATE" --repo-root "$TEST_DIR" --intake "$TEST_DIR/docs/issues/CHANGE-DRAFT-fx.md" \
    --state "$TEST_DIR/docs/ai/STATE.yaml" --files-from "$list" --max-files 5 2>&1)"
  echo "$OUT" | grep -qE '^LANE heavy reason=ceremony_level$' \
    || log_fail "TEST-023: garbage intake level must stay fail-closed heavy: $OUT"
  # EXPLICIT --spec pointing at a missing file -> heavy, NO intake fallback
  # (bot P2: a stale/misspelled spec path must not silently downgrade)
  printf -- '---\nid: fx\nceremony_level: 1\n---\n' > "$TEST_DIR/docs/issues/CHANGE-DRAFT-fx.md"
  OUT="$(node "$GATE" --repo-root "$TEST_DIR" --spec "$TEST_DIR/docs/specs/NO-SUCH-SPEC.md" \
    --intake "$TEST_DIR/docs/issues/CHANGE-DRAFT-fx.md" \
    --state "$TEST_DIR/docs/ai/STATE.yaml" --files-from "$list" --max-files 5 2>&1)"
  echo "$OUT" | grep -qE '^LANE heavy reason=ceremony_level$' \
    || log_fail "TEST-023: explicit missing --spec must fail closed, not fall back to intake: $OUT"
  assert_payload_contains "$OUT" "source=spec-missing" "TEST-023: predicate line must label source=spec-missing: $OUT"
  # both absent -> heavy (today's default preserved)
  rm -f "$TEST_DIR/docs/issues/CHANGE-DRAFT-fx.md"
  OUT="$(node "$GATE" --repo-root "$TEST_DIR" --intake "$TEST_DIR/docs/issues/CHANGE-DRAFT-fx.md" \
    --state "$TEST_DIR/docs/ai/STATE.yaml" --files-from "$list" --max-files 5 2>&1)"
  echo "$OUT" | grep -qE '^LANE heavy reason=ceremony_level$' \
    || log_fail "TEST-023: no spec + no intake must stay heavy: $OUT"
  log_pass "Intake-frontmatter ceremony fallback: fast when L0/1, fail-closed otherwise (TEST-023)"
}

test_024_spec_wins_over_intake() {  # CHANGE lane-intake-ceremony (anti-downgrade)
  log_info "Test: a present spec ALWAYS wins — intake cannot downgrade a spec'd ride (TEST-024)..."
  mk; fixture "$TEST_DIR" 2 direct
  mkdir -p "$TEST_DIR/docs/issues"
  printf -- '---\nid: fx\nceremony_level: 1\n---\n' > "$TEST_DIR/docs/issues/CHANGE-DRAFT-fx.md"
  local list="$TEST_DIR/files.txt"; printf 'docs/x.md\n' > "$list"
  OUT="$(node "$GATE" --repo-root "$TEST_DIR" --spec "$TEST_DIR/docs/specs/SPEC-DRAFT-fx.md" \
    --intake "$TEST_DIR/docs/issues/CHANGE-DRAFT-fx.md" \
    --state "$TEST_DIR/docs/ai/STATE.yaml" --files-from "$list" --max-files 5 2>&1)"
  echo "$OUT" | grep -qE '^LANE heavy reason=ceremony_level$' \
    || log_fail "TEST-024: spec L2 must beat intake L1 (no downgrade shopping): $OUT"
  assert_payload_contains "$OUT" "source=spec" "TEST-024: source must be spec: $OUT"
  log_pass "Spec precedence pinned — intake can never downgrade (TEST-024)"
}

main() {
  echo "Testing $TEST_NAME (lightweight-e2e-lane / spec-lightweight-e2e-lane)"
  check_deps
  test_001_all_true_fast
  test_002_ceremony_l2_heavy
  test_003_ceremony_absent_heavy
  test_004_strategy_tdd_heavy
  test_005_strategy_absent_heavy
  test_006_protected_l3_heavy
  test_007_unmapped_heavy
  test_008_too_many_files_heavy
  test_009_two_test_files_heavy
  test_010_two_scripts_heavy
  test_011_mapped_but_unclassified_heavy
  test_012_missing_spec_heavy
  test_013_auditable_predicate_lines
  test_014_always_exit_zero
  test_015_ceremony_l0_fast
  test_016_empty_diff_fast
  test_017_docs_only_close_diff_never_full
  test_018_skill_pr_fast_lane_contract
  test_019_rename_blindness
  test_020_prose_cap
  test_021_core_script_heavy
  test_022_missing_protected_config_heavy
  test_023_intake_ceremony_fallback
  test_024_spec_wins_over_intake
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
