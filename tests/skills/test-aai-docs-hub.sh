#!/usr/bin/env bash
#
# Test: aai-docs-hub — deterministic skills catalog generator
# (docs/specs/SPEC-0102-spec-docs-hub-generator.md, TEST-001..007).
#
# Verifies .aai/scripts/generate-docs-hub.mjs:
#   - TEST-001 (Spec-AC-01): every skill directory under a fixture's
#     .claude/skills/ is present in the catalog; the reported/pinned count
#     equals the LIVE directory listing, not a cached/hardcoded number.
#   - TEST-002 (Spec-AC-01): a skill whose prompt file has no "## Goal"
#     section degrades with a visible NOTE (never a silent omission), both
#     in the JSON `notes` array and in the rendered HTML.
#   - TEST-003 (Spec-AC-01): a skill whose SKILL.md references no
#     .aai/SKILL_*.prompt.md at all (script-first skill, e.g. real-world
#     aai-overview) degrades with its own distinct NOTE.
#   - TEST-004 (Spec-AC-02): byte-idempotence — two runs over unchanged
#     inputs produce byte-identical HTML (no timestamp in the HTML body);
#     only the JSON's generatedAt field is run-to-run.
#   - TEST-005 (Spec-AC-01): stale-catalog regression guard — regenerating
#     after new skill directories appear on disk always reflects the live
#     count and names every skill; nothing is ever silently missing (the
#     exact "27/35 skills stale" bug class this generator replaces).
#   - TEST-006 (Spec-AC-01): docs/skill-catalog-data.json shape — top-level
#     keys and per-skill keys are exactly the documented set.
#   - TEST-007 (Spec-AC-01): an unreadable/absent .claude/skills/ tree
#     degrades to an empty (0-skill) catalog, exit 0 — never a crash.
#
# ALL fixtures are scratch temp-dir repos (generate-docs-hub.mjs always runs
# with cwd = the fixture dir via `cd "$d" && node ... --output ...`) — the
# real docs/ tree is NEVER touched. bash 3.2 compatible (no ${var^^}, no
# declare -A; every fixture path is built on its own `local` line per
# LEARNED.md 2026-07-27 cross-reference discipline).
#
# Usage:
#   bash tests/skills/test-aai-docs-hub.sh            # run all tests
#   bash tests/skills/test-aai-docs-hub.sh test_001_all_skills_present_count_pin
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-docs-hub"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GENERATOR="$PROJECT_ROOT/.aai/scripts/generate-docs-hub.mjs"

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
  [[ -f "$GENERATOR" ]] || log_fail "generate-docs-hub.mjs not found: $GENERATOR"
  log_pass "Dependencies checked"
}

setup_fixture() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-docs-hub-test.XXXXXX")"
}

# --- fixture builders ---------------------------------------------------------

# mk_repo <name> -> echoes fixture repo dir with an empty .claude/skills tree.
mk_repo() {
  local d="$TEST_DIR/$1"
  rm -rf "$d"
  mkdir -p "$d/.claude/skills" "$d/.aai" "$d/docs"
  printf '%s' "$d"
}

# write_skill <repo> <skill-name> <description> [model] [prompt-name]
# — writes .claude/skills/<skill-name>/SKILL.md. When prompt-name is given,
# the body references .aai/SKILL_<prompt-name>.prompt.md (mirroring the real
# corpus's own wrapper phrasing) so findPromptRef() can locate it; omitted
# entirely, the skill is a script-first skill with no prompt reference.
write_skill() {
  local repo="$1" name="$2" desc="$3" model="${4:-}" prompt="${5:-}"
  local dir="$repo/.claude/skills/$name"
  mkdir -p "$dir"
  {
    echo "---"
    echo "name: $name"
    echo "description: $desc"
    [[ -n "$model" ]] && echo "model: $model"
    echo "---"
    echo ""
    if [[ -n "$prompt" ]]; then
      echo "Read the file \`.aai/SKILL_${prompt}.prompt.md\` from the current project root and follow its instructions exactly. Invoke this as \`/$name\`."
    else
      echo "Run \`node .aai/scripts/some-script.mjs\` from the project root."
    fi
  } > "$dir/SKILL.md"
}

# write_prompt <repo> <prompt-name> <goal-body-or-empty>
# — writes .aai/SKILL_<prompt-name>.prompt.md. An empty goal body omits the
# "## Goal" heading entirely (degrade case); a non-empty body includes it.
write_prompt() {
  local repo="$1" prompt="$2" goal="$3"
  {
    echo "# ${prompt} Skill"
    echo ""
    if [[ -n "$goal" ]]; then
      echo "## Goal"
      echo "$goal"
      echo ""
    fi
    echo "## Instructions"
    echo "1. Do the thing."
    echo ""
    echo "BEGIN NOW."
  } > "$repo/.aai/SKILL_${prompt}.prompt.md"
}

# run_generator <repo> [extra args...] -> writes docs/SKILL_CATALOG.html +
# docs/skill-catalog-data.json into <repo>/docs; combined output in $OUT,
# exit code in $EC.
OUT=""
EC=0
run_generator() {
  local d="$1"
  shift
  OUT="$d/docs-hub-run.log"
  EC=0
  (cd "$d" && node "$GENERATOR" --output "$d/docs/SKILL_CATALOG.html" "$@" > "$OUT" 2>&1) || EC=$?
}

data_json() { cat "$1/docs/skill-catalog-data.json"; }

node_get() {  # node_get <json-file> <js-expr-using-m> — prints result
  node -e '
    const fs = require("fs");
    const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const expr = process.argv[2];
    // eslint-disable-next-line no-eval
    process.stdout.write(String(eval(expr)));
  ' "$1" "$2"
}

# --- TEST-001 (Spec-AC-01): all skills present, count pin ---------------------

test_001_all_skills_present_count_pin() {
  log_info "Test: every fixture skill is present in the catalog; the reported count equals the live directory listing (docs-hub-generator TEST-001)..."
  local d
  d="$(mk_repo t001)"
  write_skill "$d" "aai-alpha" "Use when doing alpha things." "" "ALPHA"
  write_prompt "$d" "ALPHA" "Do the alpha thing."
  write_skill "$d" "aai-beta" "Use when doing beta things." "haiku" "BETA"
  write_prompt "$d" "BETA" "Do the beta thing."
  write_skill "$d" "aai-gamma" "Use when doing gamma things." "" "GAMMA"
  write_prompt "$d" "GAMMA" "Do the gamma thing."

  run_generator "$d"
  [[ "$EC" == 0 ]] || log_fail "generator must exit 0: $(cat "$OUT")"

  local live_count
  live_count="$(ls -d "$d"/.claude/skills/*/ | wc -l | tr -d ' ')"
  [[ "$live_count" == "3" ]] || log_fail "fixture setup bug: expected 3 live skill dirs, got $live_count"

  local dj="$d/docs/skill-catalog-data.json"
  local reported
  reported="$(node_get "$dj" 'm.skillsCount')"
  [[ "$reported" == "$live_count" ]] \
    || log_fail "skillsCount ($reported) must equal the live .claude/skills listing ($live_count)"

  local html="$d/docs/SKILL_CATALOG.html"
  grep -qF "${live_count} skills" "$html" \
    || log_fail "footer must carry the literal '<N> skills' count pin, got: $(grep -oE '[0-9]+ skills' "$html" || echo 'no match')"

  local s
  for s in aai-alpha aai-beta aai-gamma; do
    node_get "$dj" "m.skills.some(x=>x.dir===\"$s\")" | grep -qF "true" \
      || log_fail "skill $s missing from skill-catalog-data.json"
    grep -qF "$s" "$html" || log_fail "skill $s missing from rendered HTML"
  done
  node_get "$dj" 'm.skills.find(x=>x.dir==="aai-beta").model' | grep -qF "haiku" \
    || log_fail "aai-beta model field must be extracted from frontmatter (haiku)"

  log_pass "All 3 fixture skills present; reported count equals the live listing (docs-hub-generator TEST-001)"
}

# --- TEST-002 (Spec-AC-01): missing-Goal degrades with a visible NOTE ---------

test_002_missing_goal_degrades_with_note() {
  log_info "Test: a skill whose prompt has no '## Goal' section degrades with a visible NOTE, never a silent omission (docs-hub-generator TEST-002)..."
  local d
  d="$(mk_repo t002)"
  write_skill "$d" "aai-nogoal" "Use when testing the missing-Goal path." "" "NOGOAL"
  write_prompt "$d" "NOGOAL" ""   # no Goal body -> no "## Goal" heading at all

  run_generator "$d"
  [[ "$EC" == 0 ]] || log_fail "generator must exit 0: $(cat "$OUT")"

  local dj="$d/docs/skill-catalog-data.json"
  local goal notes
  goal="$(node_get "$dj" 'm.skills.find(x=>x.dir==="aai-nogoal").goal')"
  [[ "$goal" == "null" ]] || log_fail "aai-nogoal goal must be null (no '## Goal' heading present), got $goal"
  notes="$(node_get "$dj" 'JSON.stringify(m.skills.find(x=>x.dir==="aai-nogoal").notes)')"
  printf '%s' "$notes" | grep -qF 'Goal' \
    || log_fail "aai-nogoal notes array must name the missing Goal section, got: $notes"

  local html="$d/docs/SKILL_CATALOG.html"
  grep -qF "NOTE" "$html" || log_fail "rendered HTML must carry a visible NOTE for the degraded extraction"
  grep -qF "Goal" "$html" || log_fail "rendered HTML NOTE must mention the missing Goal section"

  log_pass "Missing-Goal skill degrades with a visible NOTE in both JSON and HTML, never silently (docs-hub-generator TEST-002)"
}

# --- TEST-003 (Spec-AC-01): no-prompt-reference degrades with its own NOTE ---

test_003_no_prompt_reference_degrades() {
  log_info "Test: a script-first skill with no .aai/SKILL_*.prompt.md reference degrades with a distinct NOTE, goal stays null (docs-hub-generator TEST-003)..."
  local d
  d="$(mk_repo t003)"
  write_skill "$d" "aai-scriptonly" "Use when running the script directly." "" ""  # no prompt param -> no reference

  run_generator "$d"
  [[ "$EC" == 0 ]] || log_fail "generator must exit 0: $(cat "$OUT")"

  local dj="$d/docs/skill-catalog-data.json"
  local promptFile goal notes
  promptFile="$(node_get "$dj" 'm.skills.find(x=>x.dir==="aai-scriptonly").promptFile')"
  [[ "$promptFile" == "null" ]] || log_fail "aai-scriptonly promptFile must be null, got $promptFile"
  goal="$(node_get "$dj" 'm.skills.find(x=>x.dir==="aai-scriptonly").goal')"
  [[ "$goal" == "null" ]] || log_fail "aai-scriptonly goal must be null, got $goal"
  notes="$(node_get "$dj" 'JSON.stringify(m.skills.find(x=>x.dir==="aai-scriptonly").notes)')"
  printf '%s' "$notes" | grep -qF 'prompt' \
    || log_fail "aai-scriptonly notes array must name the missing prompt reference, got: $notes"

  log_pass "Script-first skill (no prompt reference) degrades with its own distinct NOTE (docs-hub-generator TEST-003)"
}

# --- TEST-004 (Spec-AC-02): byte-idempotence ----------------------------------

test_004_byte_idempotence() {
  log_info "Test: two runs over unchanged inputs produce byte-identical HTML; only JSON generatedAt varies (docs-hub-generator TEST-004)..."
  local d
  d="$(mk_repo t004)"
  write_skill "$d" "aai-one" "Use when doing one things." "" "ONE"
  write_prompt "$d" "ONE" "Do one thing."
  write_skill "$d" "aai-two" "Use when doing two things." "" "TWO"
  write_prompt "$d" "TWO" "Do two things."

  run_generator "$d"
  [[ "$EC" == 0 ]] || log_fail "first run must exit 0: $(cat "$OUT")"
  cp "$d/docs/SKILL_CATALOG.html" "$d/first.html"
  local gen1
  gen1="$(node_get "$d/docs/skill-catalog-data.json" 'm.generatedAt')"

  sleep 1
  run_generator "$d"
  [[ "$EC" == 0 ]] || log_fail "second run must exit 0: $(cat "$OUT")"
  local gen2
  gen2="$(node_get "$d/docs/skill-catalog-data.json" 'm.generatedAt')"

  diff -q "$d/first.html" "$d/docs/SKILL_CATALOG.html" >/dev/null \
    || log_fail "rendered HTML must be byte-identical across unchanged-input runs"
  [[ "$gen1" != "$gen2" ]] \
    || log_fail "test setup bug: JSON generatedAt did not advance across the 1s sleep (clock issue, not a generator bug)"
  grep -qF "$gen1" "$d/docs/SKILL_CATALOG.html" \
    && log_fail "rendered HTML must carry NO timestamp in its body (found generatedAt value embedded)"

  log_pass "HTML is byte-identical across repeated runs; only JSON generatedAt varies, never embedded in HTML (docs-hub-generator TEST-004)"
}

# --- TEST-005 (Spec-AC-01): stale-catalog regression guard --------------------

test_005_stale_catalog_detection() {
  log_info "Test: regenerating after new skill directories appear always reflects the live count and names every skill (docs-hub-generator TEST-005)..."
  local d
  d="$(mk_repo t005)"
  write_skill "$d" "aai-first" "Use when doing first things." "" "FIRST"
  write_prompt "$d" "FIRST" "Do the first thing."
  write_skill "$d" "aai-second" "Use when doing second things." "" "SECOND"
  write_prompt "$d" "SECOND" "Do the second thing."

  run_generator "$d"
  [[ "$EC" == 0 ]] || log_fail "first run must exit 0: $(cat "$OUT")"
  local count1
  count1="$(node_get "$d/docs/skill-catalog-data.json" 'm.skillsCount')"
  [[ "$count1" == "2" ]] || log_fail "expected 2 skills before drift, got $count1"

  # Simulate the real-world drift this generator replaces (catalog was
  # 27/35 skills stale): add 3 MORE skill directories to the SAME fixture,
  # mirroring an upstream skill-sweep that added new skills.
  write_skill "$d" "aai-third" "Use when doing third things." "" "THIRD"
  write_prompt "$d" "THIRD" "Do the third thing."
  write_skill "$d" "aai-fourth" "Use when doing fourth things." "" "FOURTH"
  write_prompt "$d" "FOURTH" "Do the fourth thing."
  write_skill "$d" "aai-fifth" "Use when doing fifth things." "" "FIFTH"
  write_prompt "$d" "FIFTH" "Do the fifth thing."

  run_generator "$d"
  [[ "$EC" == 0 ]] || log_fail "second run must exit 0: $(cat "$OUT")"
  local count2
  count2="$(node_get "$d/docs/skill-catalog-data.json" 'm.skillsCount')"
  [[ "$count2" == "5" ]] || log_fail "expected 5 skills after drift, got $count2 (catalog is stale: not tracking the live listing)"

  local dj="$d/docs/skill-catalog-data.json" html="$d/docs/SKILL_CATALOG.html" s missing=""
  for s in aai-first aai-second aai-third aai-fourth aai-fifth; do
    local present
    present="$(node_get "$dj" "m.skills.some(x=>x.dir===\"$s\")")"
    if [[ "$present" != "true" ]]; then
      missing="$missing $s"
    fi
    grep -qF "$s" "$html" || missing="$missing $s(html)"
  done
  [[ -z "$missing" ]] || log_fail "regenerated catalog is missing skill(s):$missing"

  log_pass "Regeneration always reflects the live listing; no skill ever silently missing after drift (docs-hub-generator TEST-005)"
}

# --- TEST-006 (Spec-AC-01): JSON shape ----------------------------------------

test_006_json_shape() {
  log_info "Test: docs/skill-catalog-data.json carries exactly the documented top-level and per-skill keys (docs-hub-generator TEST-006)..."
  local d
  d="$(mk_repo t006)"
  write_skill "$d" "aai-shape" "Use when checking JSON shape." "" "SHAPE"
  write_prompt "$d" "SHAPE" "Check the shape."

  run_generator "$d"
  [[ "$EC" == 0 ]] || log_fail "generator must exit 0: $(cat "$OUT")"

  local dj="$d/docs/skill-catalog-data.json"
  local top_keys skill_keys
  top_keys="$(node -e '
    const m = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    console.log(Object.keys(m).sort().join(","));
  ' "$dj")"
  [[ "$top_keys" == "degradedCount,generatedAt,skills,skillsCount" ]] \
    || log_fail "unexpected top-level JSON keys: $top_keys"

  skill_keys="$(node -e '
    const m = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    console.log(Object.keys(m.skills[0]).sort().join(","));
  ' "$dj")"
  [[ "$skill_keys" == "description,dir,goal,model,name,notes,promptFile" ]] \
    || log_fail "unexpected per-skill JSON keys: $skill_keys"

  log_pass "docs/skill-catalog-data.json carries exactly the documented shape (docs-hub-generator TEST-006)"
}

# --- TEST-007 (Spec-AC-01): absent .claude/skills degrades to empty, exit 0 --

test_007_absent_skills_dir_empty_catalog() {
  log_info "Test: an absent .claude/skills/ tree degrades to a 0-skill catalog, exit 0, never a crash (docs-hub-generator TEST-007)..."
  local d="$TEST_DIR/t007"
  rm -rf "$d"
  mkdir -p "$d/.aai" "$d/docs"   # deliberately no .claude/skills

  run_generator "$d"
  [[ "$EC" == 0 ]] || log_fail "generator must exit 0 even with no .claude/skills/: $(cat "$OUT")"
  local count
  count="$(node_get "$d/docs/skill-catalog-data.json" 'm.skillsCount')"
  [[ "$count" == "0" ]] || log_fail "expected 0 skills with no .claude/skills/ dir, got $count"
  grep -qF "0 skills" "$d/docs/SKILL_CATALOG.html" \
    || log_fail "HTML footer must show '0 skills', not omit the pin"

  log_pass "Absent .claude/skills/ tree degrades to a clean 0-skill catalog, exit 0 (docs-hub-generator TEST-007)"
}

test_008_unknown_flag_exits_2_writes_nothing() {  # review pin (PR #180): documented contract
  log_info "Test: an unknown flag exits 2 with usage and writes NOTHING (docs-hub-generator TEST-008)..."
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/aai-docs-hub.XXXXXX")"
  local rc=0
  (cd "$d" && node "$GENERATOR" --data-onl > out.log 2>&1) || rc=$?
  [[ "$rc" -eq 2 ]] || log_fail "unknown flag must exit 2, got $rc: $(cat "$d/out.log")"
  grep -q "unknown flag" "$d/out.log" || log_fail "unknown flag must be named: $(cat "$d/out.log")"
  [[ ! -e "$d/docs/SKILL_CATALOG.html" && ! -e "$d/docs/skill-catalog-data.json" ]] \
    || log_fail "unknown flag must never write catalog outputs"
  log_pass "Unknown flag exits 2, names the flag, writes nothing (docs-hub-generator TEST-008)"
}

main() {
  echo "Testing $TEST_NAME (spec-docs-hub-generator TEST-001..007)"
  check_deps
  setup_fixture
  test_001_all_skills_present_count_pin
  test_002_missing_goal_degrades_with_note
  test_003_no_prompt_reference_degrades
  test_004_byte_idempotence
  test_005_stale_catalog_detection
  test_006_json_shape
  test_007_absent_skills_dir_empty_catalog
  test_008_unknown_flag_exits_2_writes_nothing
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
