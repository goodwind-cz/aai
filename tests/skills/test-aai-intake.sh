#!/usr/bin/env bash
#
# Test: aai-intake skill
# Tests intake routing and artifact generation
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

# Test metadata
TEST_NAME="aai-intake"
TEST_DIR=""

# Repository root, captured BEFORE setup_test_env cds into the scratch dir.
# TEST-012..TEST-015 (spec-intake-numbers-some-doc-types-immediately) read the
# real prompt corpus and the real scripts from here; they never write to it.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INTAKE_FIXTURE_DIR=""
# One scratch tree for TEST-016..TEST-018 fixtures and mutated script copies.
INTAKE_SCRATCH_DIR=""

# The eight intake types, in the order .aai/INTAKE_COMMON.md lists them.
INTAKE_TYPES="prd change issue hotfix techdebt research rfc release"

# Cleanup function
cleanup() {
  if [[ -n "${TEST_DIR:-}" ]] && [[ -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
  if [[ -n "${INTAKE_FIXTURE_DIR:-}" ]] && [[ -d "$INTAKE_FIXTURE_DIR" ]]; then
    rm -rf "$INTAKE_FIXTURE_DIR"
  fi
  if [[ -n "${INTAKE_SCRATCH_DIR:-}" ]] && [[ -d "$INTAKE_SCRATCH_DIR" ]]; then
    rm -rf "$INTAKE_SCRATCH_DIR"
  fi
}
trap cleanup EXIT

# Logging
log_pass() { echo "✓ $*"; }
log_fail() { echo "✗ $*" >&2; return 1; }
log_skip() { echo "⊘ $*"; exit 42; }
log_info() { echo "  $*"; }

detect_intake_type() {
  local description="$1"
  local normalized
  normalized=$(printf "%s" "$description" | tr '[:upper:]' '[:lower:]')

  case "$normalized" in
    *"new feature"*|*"authentication"*|*"functionality"*)
      echo "prd"
      ;;
    *"bug fix"*|*"throws error"*|*"error"*)
      echo "issue"
      ;;
    *"urgent"*|*"production issue"*|*"all users affected"*)
      echo "hotfix"
      ;;
    *"refactor"*)
      echo "techdebt"
      ;;
    *"research"*)
      echo "research"
      ;;
    *"proposal"*)
      echo "rfc"
      ;;
    *"ui change"*|*"small"*)
      echo "change"
      ;;
    *)
      echo "change"
      ;;
  esac
}

# Check dependencies
check_deps() {
  log_info "Checking dependencies..."

  if ! command -v git &> /dev/null; then
    log_skip "git not found"
  fi

  log_pass "Dependencies checked"
}

# Setup test environment
setup_test_env() {
  log_info "Setting up test environment..."

  # Create temporary directory
  TEST_DIR=$(mktemp -d /tmp/aai-test-intake-XXXXXX)
  cd "$TEST_DIR"

  # Initialize git repository
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"

  # Create directory structure
  mkdir -p docs/intake
  mkdir -p docs/ai
  mkdir -p .aai

  # Create STATE.yaml
  cat > docs/ai/STATE.yaml <<'EOF'
project_status: active
current_focus: null
active_work_items: []
intake_counter:
  prd: 0
  change: 0
  issue: 0
  hotfix: 0
  techdebt: 0
  research: 0
  rfc: 0
  release: 0
EOF

  log_pass "Test environment created: $TEST_DIR"
}

# Helper: Generate intake artifact
generate_intake_artifact() {
  local type="$1"
  local ref_id="$2"
  local title="$3"

  # Portable uppercase (bash 3.2 lacks ${var^^}, the default bash on macOS)
  local type_uc
  type_uc=$(printf '%s' "$type" | tr '[:lower:]' '[:upper:]')

  local intake_file="docs/intake/${type_uc}-$(printf "%03d" "$ref_id").md"

  cat > "$intake_file" <<EOF
# ${type_uc}-$(printf "%03d" "$ref_id"): $title

**Type:** $type
**Created:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Status:** pending

## Description

Test intake for $type type.

## Acceptance Criteria

- Criterion 1
- Criterion 2
EOF

  echo "$intake_file"
}

# Test 1: Detect PRD type
test_detect_prd() {
  log_info "Test 1: Detect PRD type..."

  local description="Add user authentication with email and password, including password reset functionality"

  local detected_type
  detected_type=$(detect_intake_type "$description")

  if [[ "$detected_type" != "prd" ]]; then
    log_fail "Expected prd, detected $detected_type"
  fi

  log_pass "PRD type detected correctly"
}

# Test 2: Detect change type
test_detect_change() {
  log_info "Test 2: Detect change type..."

  local description="Update button color from blue to green on the homepage"

  local detected_type
  detected_type=$(detect_intake_type "$description")

  if [[ "$detected_type" != "change" ]]; then
    log_fail "Expected change, detected $detected_type"
  fi

  log_pass "Change type detected correctly"
}

# Test 3: Detect issue type
test_detect_issue() {
  log_info "Test 3: Detect issue type..."

  local description="Login form throws error when email is empty - reproducible steps included"

  local detected_type
  detected_type=$(detect_intake_type "$description")

  if [[ "$detected_type" != "issue" ]]; then
    log_fail "Expected issue, detected $detected_type"
  fi

  log_pass "Issue type detected correctly"
}

# Test 4: Detect hotfix type
test_detect_hotfix() {
  log_info "Test 4: Detect hotfix type..."

  local description="URGENT: Production database connection failing - all users affected"

  local detected_type
  detected_type=$(detect_intake_type "$description")

  if [[ "$detected_type" != "hotfix" ]]; then
    log_fail "Expected hotfix, detected $detected_type"
  fi

  log_pass "Hotfix type detected correctly"
}

# Test 5: Generate PRD artifact
test_generate_prd_artifact() {
  log_info "Test 5: Generate PRD artifact..."

  local ref_id=1
  local title="User Authentication System"
  local artifact_file

  artifact_file=$(generate_intake_artifact "prd" "$ref_id" "$title")

  if [[ ! -f "$artifact_file" ]]; then
    log_fail "PRD artifact not created: $artifact_file"
  fi

  if ! grep -q "PRD-001" "$artifact_file"; then
    log_fail "PRD artifact missing reference ID"
  fi

  if ! grep -qi "Type.*prd" "$artifact_file"; then
    log_fail "PRD artifact missing type"
  fi

  log_pass "PRD artifact generated: $artifact_file"
}

# Test 6: Generate change artifact
test_generate_change_artifact() {
  log_info "Test 6: Generate change artifact..."

  local ref_id=1
  local title="Update Homepage Button Color"
  local artifact_file

  artifact_file=$(generate_intake_artifact "change" "$ref_id" "$title")

  if [[ ! -f "$artifact_file" ]]; then
    log_fail "Change artifact not created: $artifact_file"
  fi

  if ! grep -q "CHANGE-001" "$artifact_file"; then
    log_fail "Change artifact missing reference ID"
  fi

  log_pass "Change artifact generated: $artifact_file"
}

# Test 7: Generate issue artifact
test_generate_issue_artifact() {
  log_info "Test 7: Generate issue artifact..."

  local ref_id=1
  local title="Login Form Validation Error"
  local artifact_file

  artifact_file=$(generate_intake_artifact "issue" "$ref_id" "$title")

  if [[ ! -f "$artifact_file" ]]; then
    log_fail "Issue artifact not created: $artifact_file"
  fi

  if ! grep -q "ISSUE-001" "$artifact_file"; then
    log_fail "Issue artifact missing reference ID"
  fi

  log_pass "Issue artifact generated: $artifact_file"
}

# Test 8: Update STATE.yaml with intake
test_update_state() {
  log_info "Test 8: Update STATE.yaml with intake..."

  # Simulate updating STATE.yaml with new intake
  local ref_id="PRD-001"
  local type="prd"
  local title="User Authentication System"

  # Update intake counter
  local current_count
  current_count=$(grep "prd:" docs/ai/STATE.yaml | awk '{print $2}')
  local new_count=$((current_count + 1))

  # Update STATE.yaml (simplified)
  cat >> docs/ai/STATE.yaml <<EOF

# New intake added
latest_intake:
  ref_id: $ref_id
  type: $type
  title: $title
  created_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

  if ! grep -q "ref_id: $ref_id" docs/ai/STATE.yaml; then
    log_fail "STATE.yaml not updated with intake"
  fi

  log_pass "STATE.yaml updated with intake"
}

# Test 9: Validate artifact structure
test_validate_artifact_structure() {
  log_info "Test 9: Validate artifact structure..."

  local artifact_file="docs/intake/PRD-001.md"

  if [[ ! -f "$artifact_file" ]]; then
    log_fail "Artifact not found for validation"
  fi

  # Check required sections
  local required_sections=("Description" "Acceptance Criteria")

  for section in "${required_sections[@]}"; do
    if ! grep -q "## $section" "$artifact_file"; then
      log_fail "Artifact missing required section: $section"
    fi
  done

  log_pass "Artifact structure validated"
}

# Test 10: Verify intake routing logic
test_verify_routing_logic() {
  log_info "Test 10: Verify intake routing logic..."

  # Test routing logic with different keywords
  local test_cases=(
    "new feature:prd"
    "bug fix:issue"
    "urgent production issue:hotfix"
    "refactor codebase:techdebt"
    "research options:research"
    "proposal for new architecture:rfc"
    "small UI change:change"
  )

  for test_case in "${test_cases[@]}"; do
    local description="${test_case%:*}"
    local expected_type="${test_case#*:}"

    local detected_type
    detected_type=$(detect_intake_type "$description")

    if [[ "$detected_type" != "$expected_type" ]]; then
      log_fail "Routing failed: '$description' -> expected $expected_type, got $detected_type"
    fi
  done

  log_pass "Intake routing logic verified"
}

# Test 11: Verify language policy
test_language_policy() {
  log_info "Test 11: Verify language policy..."

  # Simulate handling non-English input
  local input_description="Nueva funcionalidad de autenticación"  # Spanish
  local output_artifact="docs/intake/PRD-002.md"

  # Create artifact (should be in English)
  generate_intake_artifact "prd" 2 "User Authentication Feature" > /dev/null

  if [[ ! -f "$output_artifact" ]]; then
    log_fail "Artifact not created from non-English input"
  fi

  # Verify artifact is in English
  if ! grep -qi "Type.*prd" "$output_artifact"; then
    log_fail "Artifact not written in English"
  fi

  log_pass "Language policy verified (input: any, output: English)"
}

# --- spec-intake-numbers-some-doc-types-immediately --------------------------
# The intake path used to produce numbered artifacts for the rare types
# (DEBT-0001, DEBT-0002, RES-0001, RESEARCH-0001 all entered history already
# numbered). These four arms pin the fix: the rule is stated where the router
# reads it, the prefix table has one entry per type, a numbered artifact fails a
# check, and nothing that already exists is renamed.

# Emit the single-source type table as "intakeType|type|dir|prefix" lines.
# Read INDEPENDENTLY of the tool (awk over the document, not the tool's own
# parser) on purpose: if docs-audit.mjs ever stopped seeing a row that is
# plainly in the document, TEST-014 — which drives every row of THIS reading
# through the real predicate — would fail with unknown-type rather than
# quietly agreeing with a parser that had gone blind.
intake_table_lines() {
  awk -F'[[:space:]]*\\|[[:space:]]*' \
    '/^\| [a-z]+ \| [a-z]+ \| docs\/[a-z]+ \| [A-Z]+ \|$/ { print $2 "|" $3 "|" $4 "|" $5 }' \
    "${1:-$PROJECT_ROOT/.aai/INTAKE_COMMON.md}"
}

# The SAME table, read by the SHIPPED parser (docs-audit.mjs's own
# parseIntakeTypeTable), in the same "intakeType|type|dir|prefix" shape.
#
# Independence without a cross-check is only half-built. The awk above and the
# shipped regex both now require exactly one space around every cell
# (fu-intake-table-parser-asymmetry, closed: the shipped regex used to allow
# `\s*`, so a row written with double spaces was LIVE in the gate and
# INVISIBLE to every arm that derives its row universe from the awk —
# TEST-013's counts and TEST-014's per-row drive both do). Comparing the two
# readings is what turns any FUTURE such blind spot into a named failure while
# keeping the independent reader (a tool that only reads its own table proves
# nothing); see the bite check below, which proves that on a deliberately
# reverted (lenient) copy of the parser rather than the shipped one, since the
# shipped one no longer diverges from the awk on this input.
#
# Importing docs-audit.mjs runs its main(); it is invoked from a throwaway
# fixture cwd holding nothing but .aai/INTAKE_COMMON.md, with --quick and
# --no-event, so the audit sees zero docs, appends no EVENTS line and touches
# nothing in this repository. The FIRST argv token after -e is skipped by
# parseArgs (it starts at index 2), hence the leading placeholder. $2 is the
# script to import — defaults to the shipped one; TEST-013's bite check passes
# a mutated scratch copy instead so it never has to import the tracked file
# under a mutated identity (HAZ-RESTORE: mutate a COPY, never the real file).
intake_table_lines_tool() {
  local src="${1:-$PROJECT_ROOT/.aai/INTAKE_COMMON.md}" script="${2:-$PROJECT_ROOT/.aai/scripts/docs-audit.mjs}" cwd out
  cwd=$(mktemp -d "${TMPDIR:-/tmp}/aai-intake-toolparse-XXXXXX")
  mkdir -p "$cwd/.aai"
  cp "$src" "$cwd/.aai/INTAKE_COMMON.md"
  out=$( (cd "$cwd" && node --input-type=module -e '
    import fs from "node:fs";
    const m = await import(process.argv[2]);
    const rows = m.parseIntakeTypeTable(fs.readFileSync(process.argv[3], "utf8"));
    fs.writeFileSync(process.argv[4],
      rows.map(r => [r.intakeType, r.type, r.dir, r.prefix].join("|")).join("\n"));
  ' -- placeholder "$script" "$src" "$cwd/rows.txt" --quick --no-event >/dev/null && cat "$cwd/rows.txt") )
  rm -rf "$cwd"
  printf '%s\n' "$out"
}

# Extract the `docs/<dir>` token(s) named in a per-type intake prompt's
# OPENING section — Spec-AC-02's actual claim, and D3's rationale: a role that
# reads the prompt in isolation, without scrolling past RULES, has to be told
# where to write in that first look. Scoped to the span from the "Goal:"
# marker up to (not including) the "RULES" heading — the file's opening
# paragraph today, but not pinned to exactly one physical line, so a
# legitimate second sentence added to that same paragraph is not a false
# defect. Fence-blind WITHIN that span (a ``` toggle suspends extraction)
# because a worked example inside the opening paragraph must not be read as
# the real directory statement — and content outside the span (fenced or not,
# e.g. a cross-reference in RULES or a footnote near BEGIN) is already outside
# scope and never counted at all, which is what makes a footnote-only
# directory mention (fu-intake-dir-pin-is-set-not-opening direction a) and a
# legitimate fenced example elsewhere (direction b) come out right without
# needing more than this one span rule.
intake_opening_dirs() {
  awk '
    /^Goal:$/ { g = 1; next }
    /^RULES$/ { g = 0 }
    g && /^```/ { infence = !infence; next }
    g && !infence {
      s = $0
      while (match(s, /docs\/[a-z]+/)) {
        print substr(s, RSTART, RLENGTH)
        s = substr(s, RSTART + RLENGTH)
      }
    }
  ' "$1"
}

# Write a minimal intake-shaped artifact. $1 abs path, $2 type, $3 number literal.
intake_write_artifact() {
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<EOF
---
id: demo-slug
number: $3
type: $2
status: draft
links:
  pr: []
  commits: []
---

# Demo

## Summary
- demo
EOF
}

# Run ANY docs-audit script inside a fixture root with arbitrary argv; echo
# "<rc>|<output on one line>". The script path is a parameter so the bite proofs
# in TEST-016..TEST-018 can drive a MUTATED COPY without ever editing the
# tracked one.
intake_run_script() {
  local script="$1" root="$2" out rc
  shift 2
  out=$( (cd "$root" && node "$script" "$@" 2>&1) ) && rc=0 || rc=$?
  printf '%s|%s\n' "$rc" "$(printf '%s' "$out" | tr '\n' ' ')"
}

# Run the SHIPPED guard inside a fixture root; echo "<rc>|<output on one line>".
intake_guard() {
  intake_run_script "$PROJECT_ROOT/.aai/scripts/docs-audit.mjs" "$1" --intake-file "$2"
}

# One scratch tree per suite run, removed by the EXIT trap. Every fixture and
# every mutated script copy below lives under it, so an interrupted run leaves
# nothing behind and nothing is ever written inside the repository.
intake_scratch() {
  if [[ -z "${INTAKE_SCRATCH_DIR:-}" ]]; then
    INTAKE_SCRATCH_DIR=$(mktemp -d "${TMPDIR:-/tmp}/aai-intake-scratch-XXXXXX")
  fi
  mktemp -d "$INTAKE_SCRATCH_DIR/fx-XXXXXX"
}

# A fixture root carrying the single-source table and nothing else: the guard
# resolves .aai/INTAKE_COMMON.md relative to its cwd.
intake_fixture_root() {
  local d
  d=$(intake_scratch)
  mkdir -p "$d/.aai"
  cp "$PROJECT_ROOT/.aai/INTAKE_COMMON.md" "$d/.aai/INTAKE_COMMON.md"
  printf '%s\n' "$d"
}

# Copy the shipped docs-audit CLI plus its lib/ into a scratch tree and apply ONE
# sed expression ($1) to the copy; echo the mutated script's path. Returns 1 when
# the expression changed NOTHING — a bite proof against an unmutated copy proves
# nothing and must fail as a test bug, not pass quietly. sed writes to a new file
# rather than in place: -i is not portable between BSD and GNU sed.
intake_mutant_script() {
  local expr="$1" d
  d=$(intake_scratch)
  mkdir -p "$d/scripts"
  cp -R "$PROJECT_ROOT/.aai/scripts/lib" "$d/scripts/lib"
  sed "$expr" "$PROJECT_ROOT/.aai/scripts/docs-audit.mjs" > "$d/scripts/docs-audit.mjs"
  if cmp -s "$d/scripts/docs-audit.mjs" "$PROJECT_ROOT/.aai/scripts/docs-audit.mjs"; then
    return 1
  fi
  printf '%s\n' "$d/scripts/docs-audit.mjs"
}

# TEST-012 (Spec-AC-01) — every per-type intake prompt states the DRAFT rule.
test_012_every_intake_prompt_carries_the_draft_rule() {
  log_info "TEST-012: every .aai/INTAKE_*.prompt.md states the DRAFT rule..."
  local ok=1 f base n=0 file_ok
  for f in "$PROJECT_ROOT"/.aai/INTAKE_*.prompt.md; do
    base=$(basename "$f")
    n=$((n + 1))
    file_ok=1
    grep -qF -- '-DRAFT-' "$f" \
      || { log_info "TEST-012: $base does not name the -DRAFT- token"; file_ok=0; }
    grep -qF -- 'number: null' "$f" \
      || { log_info "TEST-012: $base does not require number: null"; file_ok=0; }
    grep -qF -- 'status: draft' "$f" \
      || { log_info "TEST-012: $base does not require status: draft"; file_ok=0; }
    # ANCHORED to the RULES block on purpose. A file-wide grep for the pointer
    # asserted NOTHING: the pre-existing "SHARED POLICY — Read
    # .aai/INTAKE_COMMON.md ..." line already gave one hit in every one of the
    # eight prompts before this scope (measured: 1 hit each pre-change, against
    # 0 for `-DRAFT-`), so the sub-assertion was green on the defect it was
    # meant to catch. The pointer has to be part of the RULES bullet a role
    # reads when it is about to name the file — the same section anchoring
    # TEST-014's POST-SAVE assertion needed. One awk, no pipeline: `awk | grep
    # -q` would let grep's early exit SIGPIPE awk and redden the arm under the
    # suite's own `set -o pipefail`.
    awk '/^RULES$/ { f = 1; next }
         /^[A-Z][A-Z ]*$/ { f = 0 }
         /^[[:space:]]*$/ { f = 0 }
         f && index($0, ".aai/INTAKE_COMMON.md") { hit = 1 }
         END { exit hit ? 0 : 1 }' "$f" \
      || { log_info "TEST-012: $base does not point at the single-source table from inside its RULES block"; file_ok=0; }
    if grep -qF -- 'suggested filename' "$f"; then
      log_info "TEST-012: $base still asks for a free 'suggested filename'"
      file_ok=0
    fi
    [[ $file_ok -eq 1 ]] && log_info "  $base: rule present" || ok=0
  done
  # A ninth intake prompt must not be able to appear without the rule: the map
  # in SKILL_INTAKE.prompt.md and this loop must agree on eight.
  if [[ "$n" -ne 8 ]]; then
    log_info "TEST-012: found $n .aai/INTAKE_*.prompt.md files (want 8) — a new intake type needs the rule too"
    ok=0
  fi
  [[ $ok -eq 1 ]] && log_pass "TEST-012 all $n intake prompts carry the DRAFT-shape rule and none asks for a free filename" \
    || log_fail "TEST-012 intake prompts do not state the DRAFT rule"
}

# TEST-013 (Spec-AC-02) — one prefix per type, in one place, matching the tools.
test_013_one_prefix_per_type_matches_the_allocator() {
  log_info "TEST-013: one prefix per type, matching allocate-doc-number.mjs TYPE_MAP..."
  local ok=1 lines seen="" it ty dir pfx n=0 mapped
  # An unparsable or absent table must produce this arm's NAMED failure, not an
  # aborted suite: the command substitution's status is caught, never inherited.
  lines=$(intake_table_lines) || lines=""
  if [[ -z "$lines" ]]; then
    log_fail "TEST-013 .aai/INTAKE_COMMON.md carries no machine-readable type table"
    return
  fi
  while IFS='|' read -r it ty dir pfx; do
    [[ -n "$it" ]] || continue
    n=$((n + 1))
    case " $seen " in
      *" $it "*) log_info "TEST-013: intake type '$it' appears more than once (one prefix per type)"; ok=0 ;;
      *) seen="$seen $it" ;;
    esac
    case " $INTAKE_TYPES " in
      *" $it "*) : ;;
      *) log_info "TEST-013: table row '$it' is not one of the eight intake types"; ok=0 ;;
    esac
    # TYPE_MAP is imported READ-ONLY; allocate-doc-number.mjs is protected_paths_l3.
    mapped=$( (cd "$PROJECT_ROOT" && node -e '
      import("./.aai/scripts/allocate-doc-number.mjs").then((m) => {
        const e = m.TYPE_MAP[process.argv[1]];
        console.log(e ? `docs/${e.dir}|${e.prefix}` : "ABSENT");
      });
    ' "$it") )
    if [[ "$mapped" == "ABSENT" ]]; then
      log_info "  $it -> $dir/$pfx (TYPE_MAP has no entry — see spec D4, filed not fixed)"
    elif [[ "$mapped" != "$dir|$pfx" ]]; then
      log_info "TEST-013: $it -> $dir/$pfx disagrees with TYPE_MAP ($mapped)"
      ok=0
    else
      log_info "  $it -> $dir/$pfx (matches TYPE_MAP)"
    fi
    if [[ "$it" == "research" && "$pfx" != "RES" ]]; then
      log_info "TEST-013: research prefix is '$pfx' (the recorded D2 decision is RES)"
      ok=0
    fi
  done <<< "$lines"
  if [[ "$n" -ne 8 ]]; then
    log_info "TEST-013: table has $n rows (want 8, one per intake type)"
    ok=0
  fi
  # TWO READINGS AGREE (review-20260821T074214Z NB-4). Everything above — and
  # every row TEST-014 drives — comes from intake_table_lines' single-space
  # awk. The shipped parser allows `\s*`, so a row the gate honours can be
  # wholly outside this arm's universe and the count stays 8. Assert the awk's
  # row COUNT and row SET against the tool's own reading of the same file, so
  # a divergence is a named failure here instead of an incidental red in
  # TEST-014's table-removal fixture (whose grep -v shares the assumption).
  local tool_lines n_tool
  tool_lines=$(intake_table_lines_tool) || tool_lines=""
  n_tool=$(printf '%s\n' "$tool_lines" | grep -c '|') || n_tool=0
  if [[ "$n_tool" -ne "$n" ]]; then
    log_info "TEST-013: the shipped parser reads $n_tool row(s), this arm's awk reads $n — a row the gate honours is invisible to the pin"
    ok=0
  elif [[ "$(printf '%s\n' "$lines" | sort)" != "$(printf '%s\n' "$tool_lines" | sort)" ]]; then
    log_info "TEST-013: both readings count $n rows but disagree on their content:"
    log_info "    awk : $(printf '%s\n' "$lines" | sort | tr '\n' ' ')"
    log_info "    tool: $(printf '%s\n' "$tool_lines" | sort | tr '\n' ' ')"
    ok=0
  else
    log_info "  both readings agree: $n rows, identical row set"
  fi
  # Bite check for the cross-check itself. fu-intake-table-parser-asymmetry
  # closed the underlying gap by tightening the SHIPPED parser to the same
  # exactly-one-space rule the awk already used, so a double-spaced ninth row
  # no longer diverges between the two readers on the shipped script — that is
  # the fix working, not the cross-check going vacuous. To prove the
  # cross-check would still bite a FUTURE regression back to leniency, mutate
  # a scratch COPY of the shipped parser (never the tracked file, HAZ-RESTORE)
  # reverting just its whitespace strictness, and require the awk and the
  # MUTATED tool to disagree on the same double-spaced ninth row.
  local bite bite_awk bite_tool mutant
  bite=$(mktemp "${TMPDIR:-/tmp}/aai-intake-ninthrow-XXXXXX")
  cat "$PROJECT_ROOT/.aai/INTAKE_COMMON.md" > "$bite"
  printf '|  spec  |  spec  |  docs/specs  |  SPEC  |\n' >> "$bite"
  mutant=$(intake_mutant_script '/line\.match/ { s/| /|\\s*/g; s/ \\|/\\s*\\|/g; }') || mutant=""
  if [[ -z "$mutant" ]]; then
    log_info "TEST-013: the leniency-revert mutation changed nothing in a copy of docs-audit.mjs (test bug, not a real finding)"
    ok=0
  else
    bite_awk=$(intake_table_lines "$bite" | grep -c '|') || bite_awk=0
    bite_tool=$(intake_table_lines_tool "$bite" "$mutant" | grep -c '|') || bite_tool=0
    if [[ "$bite_awk" -eq "$bite_tool" ]]; then
      log_info "TEST-013: double-spaced ninth row read as $bite_awk by both readers even against the leniency-reverted mutant — the cross-check cannot bite (test bug, not a real finding)"
      ok=0
    else
      log_info "  bite proven: double-spaced ninth row -> awk $bite_awk rows, leniency-reverted mutant $bite_tool rows (the cross-check would catch this regression if the shipped parser ever re-loosened)"
    fi
  fi
  rm -f "$bite"
  # The prefix is stated in ONE place: no per-type prompt may restate one.
  local f base p
  for f in "$PROJECT_ROOT"/.aai/INTAKE_*.prompt.md; do
    base=$(basename "$f")
    for p in PRD CHANGE ISSUE DEBT RES RESEARCH RFC REL; do
      if grep -qF -- "$p-" "$f"; then
        log_info "TEST-013: $base restates the display prefix '$p-' (the table is the only place)"
        ok=0
      fi
    done
  done
  # The DIRECTORY half is NOT single-sourced and deliberately so: a prompt a
  # role reads in isolation has to say where to write. Nine agreeing statements
  # with nothing holding them together is exactly how the RES/RESEARCH split
  # happened, so INTAKE_COMMON claims to be the AUTHORITY for the directory and
  # this pins that claim: every `docs/<dir>` named in a per-type prompt's own
  # OPENING section (not a file-wide scan — fu-intake-dir-pin-is-set-not-opening)
  # must be its own table row's directory, and no other. The prompt filename
  # carries the intake type (INTAKE_TECHDEBT -> techdebt), and the RULES
  # bullet's literal `docs/<dir>/` placeholder cannot collide — angle brackets
  # are not [a-z] — but that bullet sits AFTER the "RULES" heading and is
  # therefore outside intake_opening_dirs' scan span regardless.
  local it_from_file want got
  for f in "$PROJECT_ROOT"/.aai/INTAKE_*.prompt.md; do
    base=$(basename "$f")
    it_from_file=$(printf '%s' "${base#INTAKE_}" | sed 's/\.prompt\.md$//' | tr '[:upper:]' '[:lower:]')
    want=$(printf '%s\n' "$lines" | awk -F'|' -v t="$it_from_file" '$1 == t { print $3 }' | sort -u | tr '\n' ' ')
    got=$(intake_opening_dirs "$f" | sort -u | tr '\n' ' ')
    if [[ "$got" != "$want" ]]; then
      log_info "TEST-013: $base's opening section names directory '${got:-(none)}' for intake type '$it_from_file'; the table row says '${want:-(no row)}'"
      ok=0
    else
      log_info "  $base: opening section directory ${want% } matches the table row for $it_from_file"
    fi
  done
  # Bite check, direction (a) — fu-intake-dir-pin-is-set-not-opening: deleting
  # the real opening-section directory statement and naming the directory only
  # in a footnote used to stay green under the old file-wide-set pin. Build a
  # synthetic prompt (never the tracked file) that does exactly that and
  # require the opening-section reading to come up EMPTY, not 'docs/issues'.
  local bite_a bite_a_got
  bite_a=$(mktemp "${TMPDIR:-/tmp}/aai-intake-openingbite-a-XXXXXX.md")
  cat > "$bite_a" <<'EOF'
You are a TEST INTAKE ASSISTANT.

Goal:
Capture a test item using .aai/templates/TEST_TEMPLATE.md
and save it.

RULES
- NEVER a numbered filename.

(Artifacts for this intake type go under docs/issues/.)
EOF
  bite_a_got=$(intake_opening_dirs "$bite_a" | sort -u | tr '\n' ' ')
  rm -f "$bite_a"
  if [[ -n "$bite_a_got" ]]; then
    log_info "TEST-013: a footnote-only directory mention (opening line deleted) still reads as '${bite_a_got}' — the opening-section pin cannot bite this direction (test bug, not a real finding)"
    ok=0
  else
    log_info "  bite proven (direction a): footnote-only directory mention reads as '(none)' in the opening section, not 'docs/issues'"
  fi
  # Bite check, direction (b) — the FIRST legitimate cross-reference or fenced
  # example path added to any intake prompt used to redden the old file-wide
  # pin for a non-defect. Build a synthetic prompt whose opening section names
  # its real directory AND carries a fenced example citing a DIFFERENT docs/
  # path, and require the opening-section reading to stay exactly the real
  # directory (fence-blind).
  local bite_b bite_b_got
  bite_b=$(mktemp "${TMPDIR:-/tmp}/aai-intake-openingbite-b-XXXXXX.md")
  cat > "$bite_b" <<'EOF'
You are a TEST INTAKE ASSISTANT.

Goal:
Capture a test item using .aai/templates/TEST_TEMPLATE.md
and save it under docs/issues/.

Example cross-reference:
```
See docs/adr/ADR-0001.md for background.
```

RULES
- NEVER a numbered filename.
EOF
  bite_b_got=$(intake_opening_dirs "$bite_b" | sort -u | tr '\n' ' ')
  rm -f "$bite_b"
  if [[ "$bite_b_got" != "docs/issues " ]]; then
    log_info "TEST-013: a legitimate fenced cross-reference inside the opening section reddened the pin ('${bite_b_got:-(none)}' != 'docs/issues ') for a non-defect (test bug, not a real finding)"
    ok=0
  else
    log_info "  bite proven (direction b): a fenced cross-reference to a different docs/ path leaves the opening-section reading as 'docs/issues', unaffected"
  fi
  [[ $ok -eq 1 ]] && log_pass "TEST-013 $n rows (awk and the shipped parser agree, divergence proven detectable), one prefix per type, research=RES, no prefix restated in any prompt, every prompt's OPENING section directory matches its table row (both pin directions proven to bite)" \
    || log_fail "TEST-013 type/prefix table contract"
}

# TEST-014 (Spec-AC-03) — a numbered intake artifact FAILS; its DRAFT twin passes.
test_014_numbered_intake_artifact_fails_the_guard() {
  log_info "TEST-014: numbered-at-intake fails the guard, the DRAFT twin passes..."
  local ok=1 fix lines it ty dir pfx res rc out
  fix=$(mktemp -d /tmp/aai-test-intake-guard-XXXXXX)
  INTAKE_FIXTURE_DIR="$fix"
  mkdir -p "$fix/.aai"
  cp "$PROJECT_ROOT/.aai/INTAKE_COMMON.md" "$fix/.aai/INTAKE_COMMON.md"
  lines=$(intake_table_lines) || lines=""
  if [[ -z "$lines" ]]; then
    rm -rf "$fix"
    INTAKE_FIXTURE_DIR=""
    log_fail "TEST-014 no machine-readable type table to build the per-type artifacts from"
    return
  fi
  while IFS='|' read -r it ty dir pfx; do
    [[ -n "$it" ]] || continue
    intake_write_artifact "$fix/$dir/$pfx-0999-demo-slug.md" "$ty" "999"
    intake_write_artifact "$fix/$dir/$pfx-DRAFT-demo-slug.md" "$ty" "null"
    res=$(intake_guard "$fix" "$dir/$pfx-0999-demo-slug.md")
    rc="${res%%|*}"; out="${res#*|}"
    if [[ "$rc" != "1" ]]; then
      log_info "TEST-014: $it numbered artifact exited $rc (want 1): $out"
      ok=0
    elif [[ "$out" != *"numbered-at-intake"* ]]; then
      log_info "TEST-014: $it numbered artifact failed without a numbered-at-intake finding: $out"
      ok=0
    fi
    local rc_numbered="$rc"
    res=$(intake_guard "$fix" "$dir/$pfx-DRAFT-demo-slug.md")
    rc="${res%%|*}"; out="${res#*|}"
    if [[ "$rc" != "0" ]]; then
      log_info "TEST-014: $it DRAFT twin exited $rc (want 0): $out"
      ok=0
    fi
    log_info "  $it: $pfx-0999 -> $rc_numbered, $pfx-DRAFT -> $rc"
  done <<< "$lines"
  # The RES/RESEARCH split: the losing prefix is refused for a research draft.
  intake_write_artifact "$fix/docs/specs/RESEARCH-DRAFT-demo-slug.md" "research" "null"
  res=$(intake_guard "$fix" "docs/specs/RESEARCH-DRAFT-demo-slug.md")
  rc="${res%%|*}"; out="${res#*|}"
  if [[ "$rc" != "1" || "$out" != *"wrong-prefix-or-dir"* ]]; then
    log_info "TEST-014: RESEARCH-DRAFT for type research exited $rc (want 1 with wrong-prefix-or-dir): $out"
    ok=0
  else
    log_info "  research with the RESEARCH prefix -> 1 (wrong-prefix-or-dir)"
  fi
  # An ABSENT `number:` key is not a pass. The rule is `number: null`, present
  # and explicit; an omitted key used to clear the gate on a `!= null` test
  # while an omitted `status` was caught (validation round 1, F2). Written here
  # rather than through intake_write_artifact, which always emits the key.
  mkdir -p "$fix/docs/issues"
  cat > "$fix/docs/issues/CHANGE-DRAFT-no-number-key.md" <<'EOF'
---
id: demo-slug
type: change
status: draft
links:
  pr: []
  commits: []
---

# Demo

## Summary
- demo
EOF
  res=$(intake_guard "$fix" "docs/issues/CHANGE-DRAFT-no-number-key.md")
  rc="${res%%|*}"; out="${res#*|}"
  if [[ "$rc" != "1" || "$out" != *"number-absent"* ]]; then
    log_info "TEST-014: an artifact with no number key exited $rc (want 1 with number-absent): $out"
    ok=0
  else
    log_info "  DRAFT artifact with the number key omitted -> 1 (number-absent)"
  fi
  # Unreadable artifact -> 2, never a silent pass.
  res=$(intake_guard "$fix" "docs/issues/NOT-THERE.md")
  rc="${res%%|*}"
  if [[ "$rc" != "2" ]]; then
    log_info "TEST-014: missing artifact exited $rc (want 2)"
    ok=0
  else
    log_info "  missing artifact -> 2"
  fi
  # Table removed from the single source -> 2, never a silent pass.
  local fix2
  fix2="$fix/no-table"
  mkdir -p "$fix2/.aai"
  grep -v '^| [a-z]* | [a-z]* | docs/' "$PROJECT_ROOT/.aai/INTAKE_COMMON.md" > "$fix2/.aai/INTAKE_COMMON.md"
  intake_write_artifact "$fix2/docs/issues/DEBT-DRAFT-demo-slug.md" "techdebt" "null"
  res=$(intake_guard "$fix2" "docs/issues/DEBT-DRAFT-demo-slug.md")
  rc="${res%%|*}"; out="${res#*|}"
  if [[ "$rc" != "2" ]]; then
    log_info "TEST-014: a fixture with no type table exited $rc (want 2): $out"
    ok=0
  else
    log_info "  INTAKE_COMMON.md with the table removed -> 2"
  fi
  # The intake flow must actually reach the check — and the mention has to be
  # the INVOCATION inside POST-SAVE CHECK, not the passing reference to the
  # flag in the DURABLE DOC IDENTITY block (which is what an earlier, weaker
  # form of this assertion accepted, so a deleted invocation stayed green).
  if ! awk '/^## POST-SAVE CHECK/{f=1;next} /^## /{f=0} f' \
        "$PROJECT_ROOT/.aai/INTAKE_COMMON.md" \
        | grep -qF -- 'node .aai/scripts/docs-audit.mjs --intake-file <saved-file>'; then
    log_info "TEST-014: the POST-SAVE CHECK block does not invoke docs-audit.mjs --intake-file on the saved file"
    ok=0
  else
    log_info "  POST-SAVE CHECK invokes --intake-file on the saved artifact"
  fi
  rm -rf "$fix"
  INTAKE_FIXTURE_DIR=""
  [[ $ok -eq 1 ]] && log_pass "TEST-014 all 8 types: numbered -> exit 1 (numbered-at-intake), DRAFT -> exit 0; absent number key -> 1; unreadable and table-less -> exit 2" \
    || log_fail "TEST-014 intake numbering guard"
}

# TEST-015 (Spec-AC-04) — existing numbered documents are not renamed.
test_015_existing_numbered_docs_are_not_renamed() {
  log_info "TEST-015: the four historical numbered documents keep their paths..."
  local ok=1 p renames
  for p in \
    docs/issues/DEBT-0001-index-deferred-gap-and-done-with-live-decisions.md \
    docs/issues/DEBT-0002-prompt-diet-byte-budget-true-up.md \
    docs/specs/RES-0001-aai-competitive-gap-and-model-efficiency.md \
    docs/specs/RESEARCH-0001-spec-kit-comparative.md; do
    if [[ -f "$PROJECT_ROOT/$p" ]]; then
      log_info "  present: $p"
    else
      log_info "TEST-015: $p is missing — a display id is a durable primary key and is never renamed"
      ok=0
    fi
  done
  # The rename half needs a usable git tree. When there is none (an exported
  # copy, a sandbox without git), SAY so and check only the four paths — a
  # skipped check is reported, never silently counted as a pass.
  if (cd "$PROJECT_ROOT" && git rev-parse --git-dir >/dev/null 2>&1); then
    renames=$( (cd "$PROJECT_ROOT" && git status --porcelain=v1 -uno -- docs/ | grep -c '^R') || true )
    renames=$(printf '%s' "$renames" | tr -d ' \n')
    [[ -n "$renames" ]] || renames=0
    if [[ "$renames" != "0" ]]; then
      log_info "TEST-015: git status reports $renames renamed path(s) under docs/"
      ok=0
    else
      log_info "  git status: no renamed path under docs/"
    fi
  else
    log_info "  NOTE: no git tree at $PROJECT_ROOT — the working-tree rename check did not run"
  fi
  [[ $ok -eq 1 ]] && log_pass "TEST-015 four historical numbered docs intact, no rename under docs/ in the working tree" \
    || log_fail "TEST-015 existing numbered documents were renamed"
}

# TEST-016 (Spec-AC-03) — a value-taking flag REFUSES an absent or empty value.
# The gate this scope exists to add failed OPEN: main() dispatches on
# truthiness, so `--intake-file "$FILE"` with FILE unset skipped the predicate
# and ran a full repository audit — exit 0 on a clean repo, and a docs_audit
# EVENTS append unless --no-event was also passed. Raised independently by
# Copilot and Codex on PR #269. Fixed once for all five value-taking flags,
# so pinned over all five.
test_016_value_flags_refuse_an_empty_value() {
  log_info "TEST-016: --intake-file and its four siblings refuse an absent/empty value..."
  local ok=1 root flag res rc out mutant
  root=$(intake_fixture_root)
  intake_write_artifact "$root/docs/issues/DEBT-DRAFT-demo-slug.md" techdebt null
  for flag in --intake-file --gate-file --lint-body-file --gate --path; do
    res=$(intake_run_script "$PROJECT_ROOT/.aai/scripts/docs-audit.mjs" "$root" --no-event "$flag" "")
    rc="${res%%|*}"; out="${res#*|}"
    if [[ "$rc" != "2" || "$out" != *"USAGE ERROR"* ]]; then
      log_info "TEST-016: $flag with an EMPTY value exited $rc (want 2 with USAGE ERROR): $out"
      ok=0
    fi
    # The value omitted entirely: the flag is the LAST token, so argv[++i] is
    # undefined rather than "". Same verdict, different code path.
    res=$(intake_run_script "$PROJECT_ROOT/.aai/scripts/docs-audit.mjs" "$root" --no-event "$flag")
    rc="${res%%|*}"; out="${res#*|}"
    if [[ "$rc" != "2" || "$out" != *"USAGE ERROR"* ]]; then
      log_info "TEST-016: $flag with a MISSING value exited $rc (want 2 with USAGE ERROR): $out"
      ok=0
    else
      log_info "  $flag: empty -> 2, missing -> 2"
    fi
  done
  # Unmutated green controls: a real value still works, and the valueless flags
  # are untouched by the guard.
  res=$(intake_guard "$root" "docs/issues/DEBT-DRAFT-demo-slug.md")
  rc="${res%%|*}"; out="${res#*|}"
  if [[ "$rc" != "0" ]]; then
    log_info "TEST-016: control — a VALID --intake-file value exited $rc (want 0): $out"
    ok=0
  else
    log_info "  control: a valid --intake-file value -> 0"
  fi
  res=$(intake_run_script "$PROJECT_ROOT/.aai/scripts/docs-audit.mjs" "$root" --quick --no-event)
  rc="${res%%|*}"
  if [[ "$rc" != "0" ]]; then
    log_info "TEST-016: control — a plain --quick --no-event audit exited $rc (want 0)"
    ok=0
  else
    log_info "  control: --quick --no-event (no value-taking flag) -> 0"
  fi
  # BITE: revert the guard at the --intake-file call site only. The empty value
  # must then be accepted and answered with a FULL AUDIT, which is the exact
  # fail-open both bots reported.
  if mutant=$(intake_mutant_script 's|args.intakeFile = requireValue(tok, argv\[++i\])|args.intakeFile = argv[++i]|'); then
    res=$(intake_run_script "$mutant" "$root" --no-event --intake-file "")
    rc="${res%%|*}"; out="${res#*|}"
    if [[ "$rc" != "0" || "$out" != *"Docs Audit"* ]]; then
      log_info "TEST-016: with requireValue removed, --intake-file \"\" exited $rc without a full audit — the pin cannot bite (test bug): $out"
      ok=0
    else
      log_info "  bite proven: requireValue removed -> --intake-file \"\" runs a full audit at exit 0"
    fi
  else
    log_info "TEST-016: the bite mutation matched nothing in docs-audit.mjs (test bug, not a real finding)"
    ok=0
  fi
  [[ $ok -eq 1 ]] && log_pass "TEST-016 all five value-taking flags exit 2 on an empty and on a missing value; valid values and valueless flags unchanged; fail-open proved reachable without the guard" \
    || log_fail "TEST-016 value-taking flags fail open on an empty value"
}

# TEST-017 (Spec-AC-03) — the findings say what is actually wrong. A correctly
# located numbered file used to collect `wrong-prefix-or-dir` on top of
# `numbered-at-intake` because `Boolean(draft)` sat inside the directory/prefix
# predicate (Copilot, PR #269). The verdict was right and the diagnosis was
# false, which sends the next reader to the wrong fix.
test_017_wrong_prefix_finding_means_wrong_prefix() {
  log_info "TEST-017: wrong-prefix-or-dir is not reported for a correctly located file..."
  local ok=1 root res rc out mutant
  root=$(intake_fixture_root)
  # Correct directory, correct prefix, numbered: ONE finding class about the
  # basename, and it is the numbering.
  intake_write_artifact "$root/docs/issues/DEBT-0001-demo-slug.md" techdebt 1
  res=$(intake_guard "$root" "docs/issues/DEBT-0001-demo-slug.md")
  rc="${res%%|*}"; out="${res#*|}"
  if [[ "$rc" != "1" ]]; then
    log_info "TEST-017: the correctly located numbered file exited $rc (want 1): $out"
    ok=0
  elif [[ "$out" != *"numbered-at-intake"* ]]; then
    log_info "TEST-017: no numbered-at-intake finding on DEBT-0001 in docs/issues: $out"
    ok=0
  elif [[ "$out" == *"wrong-prefix-or-dir"* ]]; then
    log_info "TEST-017: DEBT-0001-demo-slug.md in docs/issues with type techdebt is in the RIGHT place and still reports wrong-prefix-or-dir: $out"
    ok=0
  else
    log_info "  DEBT-0001 in docs/issues (type techdebt) -> 1, numbered-at-intake only"
  fi
  # A genuinely mislocated file still reports it — twice over: wrong PREFIX in
  # the right directory, and the right prefix in the wrong DIRECTORY.
  intake_write_artifact "$root/docs/specs/RESEARCH-DRAFT-demo-slug.md" research null
  res=$(intake_guard "$root" "docs/specs/RESEARCH-DRAFT-demo-slug.md")
  rc="${res%%|*}"; out="${res#*|}"
  if [[ "$rc" != "1" || "$out" != *"wrong-prefix-or-dir"* ]]; then
    log_info "TEST-017: RESEARCH-DRAFT for type research exited $rc without wrong-prefix-or-dir: $out"
    ok=0
  else
    log_info "  wrong prefix (RESEARCH for research) -> 1 with wrong-prefix-or-dir"
  fi
  intake_write_artifact "$root/docs/rfc/DEBT-DRAFT-demo-slug.md" techdebt null
  res=$(intake_guard "$root" "docs/rfc/DEBT-DRAFT-demo-slug.md")
  rc="${res%%|*}"; out="${res#*|}"
  if [[ "$rc" != "1" || "$out" != *"wrong-prefix-or-dir"* ]]; then
    log_info "TEST-017: a techdebt draft under docs/rfc exited $rc without wrong-prefix-or-dir: $out"
    ok=0
  else
    log_info "  wrong directory (techdebt under docs/rfc) -> 1 with wrong-prefix-or-dir"
  fi
  # BITE: put `Boolean(draft) && draft[1] === r.prefix` back into the predicate.
  # The correctly located numbered file must then pick the false finding up again.
  if mutant=$(intake_mutant_script 's|r.dir === dir \&\& r.prefix === basePrefix|r.dir === dir \&\& Boolean(draft) \&\& draft[1] === r.prefix|'); then
    res=$(intake_run_script "$mutant" "$root" --intake-file "docs/issues/DEBT-0001-demo-slug.md")
    rc="${res%%|*}"; out="${res#*|}"
    if [[ "$out" != *"wrong-prefix-or-dir"* ]]; then
      log_info "TEST-017: with Boolean(draft) back inside the predicate the false finding did not reappear — the pin cannot bite (test bug): $out"
      ok=0
    else
      log_info "  bite proven: Boolean(draft) back inside the predicate -> the correctly located file reports wrong-prefix-or-dir again"
    fi
  else
    log_info "TEST-017: the bite mutation matched nothing in docs-audit.mjs (test bug, not a real finding)"
    ok=0
  fi
  [[ $ok -eq 1 ]] && log_pass "TEST-017 wrong-prefix-or-dir reported only for a genuinely wrong prefix or directory; the false finding proved reachable with the fix reverted" \
    || log_fail "TEST-017 wrong-prefix-or-dir diagnosis"
}

# TEST-018 (Spec-AC-03) — the gate enforces the slug constraint the document
# states. `.aai/INTAKE_COMMON.md` requires a kebab-case ASCII slug of at most 48
# characters; the basename regex accepted any run of [a-z0-9-] of any length, so
# `ISSUE-DRAFT--.md`, `ISSUE-DRAFT-foo-.md` and a 49-character slug all passed
# (Codex, PR #269). Boundary pinned at 48 and 49, not "long".
test_018_slug_shape_matches_the_documented_constraint() {
  log_info "TEST-018: the gate enforces the documented kebab-case, <=48-char slug..."
  local ok=1 root res rc out mutant s48 s49 bad
  root=$(intake_fixture_root)
  # Portable 48/49-char slugs without seq or ${var:0:n} arithmetic games.
  s48=$(printf '%048d' 0 | tr '0' 'a')
  s49=$(printf '%049d' 0 | tr '0' 'a')
  if [[ "${#s48}" -ne 48 || "${#s49}" -ne 49 ]]; then
    log_fail "TEST-018 could not build the 48/49-character slugs (got ${#s48}/${#s49})"
    return
  fi
  intake_write_artifact "$root/docs/issues/ISSUE-DRAFT--.md" issue null
  intake_write_artifact "$root/docs/issues/ISSUE-DRAFT-foo-.md" issue null
  intake_write_artifact "$root/docs/issues/ISSUE-DRAFT-$s49.md" issue null
  intake_write_artifact "$root/docs/issues/ISSUE-DRAFT-$s48.md" issue null
  for bad in "docs/issues/ISSUE-DRAFT--.md" "docs/issues/ISSUE-DRAFT-foo-.md"; do
    res=$(intake_guard "$root" "$bad")
    rc="${res%%|*}"; out="${res#*|}"
    if [[ "$rc" != "1" || "$out" != *"slug-not-kebab"* ]]; then
      log_info "TEST-018: $bad exited $rc without slug-not-kebab: $out"
      ok=0
    else
      log_info "  $(basename "$bad") -> 1 (slug-not-kebab)"
    fi
  done
  res=$(intake_guard "$root" "docs/issues/ISSUE-DRAFT-$s49.md")
  rc="${res%%|*}"; out="${res#*|}"
  if [[ "$rc" != "1" || "$out" != *"slug-too-long"* ]]; then
    log_info "TEST-018: a 49-character slug exited $rc without slug-too-long: $out"
    ok=0
  else
    log_info "  49-character slug -> 1 (slug-too-long)"
  fi
  # The boundary itself is the control: exactly 48 is legal and must PASS, so
  # the bound is pinned rather than merely "long slugs fail".
  res=$(intake_guard "$root" "docs/issues/ISSUE-DRAFT-$s48.md")
  rc="${res%%|*}"; out="${res#*|}"
  if [[ "$rc" != "0" ]]; then
    log_info "TEST-018: control — a slug of exactly 48 characters exited $rc (want 0): $out"
    ok=0
  else
    log_info "  control: 48-character slug -> 0"
  fi
  # BITE: take the basename's slug out of the two checks. Every shape above must
  # then be accepted again, which is the state Codex reported.
  if mutant=$(intake_mutant_script 's|const slug = draft\[2\];|const slug = "ok";|'); then
    for bad in "docs/issues/ISSUE-DRAFT--.md" "docs/issues/ISSUE-DRAFT-foo-.md" "docs/issues/ISSUE-DRAFT-$s49.md"; do
      res=$(intake_run_script "$mutant" "$root" --intake-file "$bad")
      rc="${res%%|*}"; out="${res#*|}"
      if [[ "$rc" != "0" ]]; then
        log_info "TEST-018: with the slug checks neutered, $bad still exited $rc (want 0) — the pin cannot bite (test bug): $out"
        ok=0
      fi
    done
    [[ $ok -eq 1 ]] && log_info "  bite proven: with the slug read out of the checks all three malformed slugs are accepted at exit 0"
  else
    log_info "TEST-018: the bite mutation matched nothing in docs-audit.mjs (test bug, not a real finding)"
    ok=0
  fi
  [[ $ok -eq 1 ]] && log_pass "TEST-018 leading/trailing/doubled hyphens and a 49-character slug all exit 1; exactly 48 passes; the permissive shape proved reachable with the checks neutered" \
    || log_fail "TEST-018 documented slug constraint is not enforced"
}

# Main test execution
main() {
  echo "Testing: $TEST_NAME"
  echo "===================="

  check_deps
  setup_test_env

  # Run tests
  test_detect_prd
  test_detect_change
  test_detect_issue
  test_detect_hotfix
  test_generate_prd_artifact
  test_generate_change_artifact
  test_generate_issue_artifact
  test_update_state
  test_validate_artifact_structure
  test_verify_routing_logic
  test_language_policy
  test_012_every_intake_prompt_carries_the_draft_rule
  test_013_one_prefix_per_type_matches_the_allocator
  test_014_numbered_intake_artifact_fails_the_guard
  test_015_existing_numbered_docs_are_not_renamed
  test_016_value_flags_refuse_an_empty_value
  test_017_wrong_prefix_finding_means_wrong_prefix
  test_018_slug_shape_matches_the_documented_constraint

  echo ""
  echo "All tests passed!"
  exit 0
}

main "$@"
