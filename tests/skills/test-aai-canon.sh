#!/usr/bin/env bash
#
# Test: canon.mjs build / claims — the dispatch payload is ASSEMBLED and
# ASSERTED, never pasted, and a withdrawn claim's correction is checkable,
# not hand-swept (SPEC-DRAFT-spec-canon-is-a-build-artifact,
# Spec-AC-01..Spec-AC-10, TEST-674..TEST-689; wave 3, sweep 7).
#
# TEST-682..689 (run 2) add: `build --print-hash` (Spec-AC-06 — S2, the
# PAYLOAD/TELEMETRY seam: TEST-682/683 run BOTH canon.mjs's own hash and
# `lib/prompt-hash.mjs`'s independently and assert they agree, never mocking
# either); the ORCHESTRATION.prompt.md wiring (Spec-AC-07 — S3: TEST-684
# EXTRACTS the prompt's own `canon.mjs build` command with a pinned pattern
# and EXECUTES it, never merely asserting the prompt contains a string);
# and `claims` (Spec-AC-08..10 — the withdrawn-claim sweep, driven by a
# DECLARED claim list in CANON.yaml, reaching the repository root via
# CHANGELOG.md, covering present/future tense).
#
# TEST-690..699 (run 3, the final run) add: `claims --report` (Spec-AC-11 —
# the GENERATED enumeration of documents carrying their OWN dated correction
# annotation for a claim, closing fu-spec-d6-enumeration-stale; TEST-691 reads
# BOTH the report's own numbers and SPEC-0148's dated addendum block and
# compares them value-to-value, never a literal in the test); `check --section
# validation_waiver` (Spec-AC-12 — the waiver grammar RENDERED from
# validation-waiver.mjs's own exported constants and asserted verbatim against
# that file's own header, plus a literal-version sweep over `.aai/**` and
# `tests/skills/**`); `check --section decision_citations` (Spec-AC-13 — every
# `owner decision <ref>, <date>` citation in `.aai/*.prompt.md` resolved
# against `docs/ai/decisions.jsonl`); and `check --all` / `build` for every
# declared role against the LIVE tree (Spec-AC-15 — a gate proved only on
# fixtures has never met the corpus it governs).
#
# D3 (anti-vacuity, the whole reason this suite exists): every order/count/
# uniqueness assertion below parses `canon.mjs build`'s STDOUT — the
# ASSEMBLED PAYLOAD — never the manifest it was built from. TEST-675 pins
# this literally: it swaps a fixture manifest's first two sections and
# asserts the PAYLOAD sequence swapped, which a check that merely re-read
# the manifest could never catch.
#
# Fixtures are scratch temp-dir trees (mktemp), never the real repo tree,
# except the explicit "live tree" arms (674's baseline, 677's live-clean
# half, 681), which are READ-ONLY against `.aai/system/CANON.yaml` and the
# real prompt corpus — canon.mjs build never writes anything.
#
# bash 3.2 compatible (no ${var^^}, no declare -A, no mapfile).
#
# Usage:
#   bash tests/skills/test-aai-canon.sh          # run all
#   bash tests/skills/test-aai-canon.sh 674       # one arm, by TEST id prefix
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-canon"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CANON="$PROJECT_ROOT/.aai/scripts/canon.mjs"
LIVE_MANIFEST="$PROJECT_ROOT/.aai/system/CANON.yaml"

# shellcheck source=tests/skills/lib/assert-payload.sh
. "$SCRIPT_DIR/lib/assert-payload.sh"
# shellcheck source=tests/skills/lib/pipe-safe.sh
. "$SCRIPT_DIR/lib/pipe-safe.sh"

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
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  [[ -f "$CANON" ]] || log_fail "canon.mjs not found: $CANON"
  [[ -f "$LIVE_MANIFEST" ]] || log_fail "CANON.yaml not found: $LIVE_MANIFEST"
}

setup_fixture() { TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-canon-test.XXXXXX")"; }

# --- helpers -----------------------------------------------------------------

# run_canon <cwd> <manifest-rel-to-cwd> <role> <ref> — sets CANON_OUT / CANON_ERR
# (file paths) and CANON_RC. Never touches the real repo: <cwd> is either the
# real repo root (read-only build) or a scratch fixture tree.
run_canon() {
  local cwd="$1" manifest="$2" role="$3" ref="$4"
  CANON_OUT="$(mktemp "$TEST_DIR/canon-out.XXXXXX")"
  CANON_ERR="$(mktemp "$TEST_DIR/canon-err.XXXXXX")"
  set +e
  ( cd "$cwd" && node "$CANON" build --role "$role" --ref "$ref" --manifest "$manifest" >"$CANON_OUT" 2>"$CANON_ERR" )
  CANON_RC=$?
  set -e
}

expect_rc() {
  local want="$1" what="$2"
  [[ "$CANON_RC" -eq "$want" ]] \
    || log_fail "$what: expected exit $want, got $CANON_RC — stderr: $(payload_preview "$(cat "$CANON_ERR")")"
}

expect_rc_nonzero() {
  local what="$1"
  [[ "$CANON_RC" -ne 0 ]] \
    || log_fail "$what: expected a non-zero exit, got 0 — stdout: $(payload_preview "$(cat "$CANON_OUT")")"
}

# run_canon_hash <cwd> <manifest-rel-to-cwd> <role> <ref> — same as
# run_canon but adds --print-hash (Spec-AC-06). Sets CANON_OUT / CANON_ERR /
# CANON_RC the same way.
run_canon_hash() {
  local cwd="$1" manifest="$2" role="$3" ref="$4"
  CANON_OUT="$(mktemp "$TEST_DIR/canon-hash-out.XXXXXX")"
  CANON_ERR="$(mktemp "$TEST_DIR/canon-hash-err.XXXXXX")"
  set +e
  ( cd "$cwd" && node "$CANON" build --role "$role" --ref "$ref" --manifest "$manifest" --print-hash >"$CANON_OUT" 2>"$CANON_ERR" )
  CANON_RC=$?
  set -e
}

# reference_prompt_hash <root> <role-prompt-rel-path> -> the digest
# `.aai/scripts/lib/prompt-hash.mjs`'s OWN computeEffectivePromptHash prints
# for the same tree — an INDEPENDENT second call (S2), never a re-read of
# canon.mjs's output.
reference_prompt_hash() {
  local root="$1" role_rel="$2"
  node --input-type=module -e "
import { computeEffectivePromptHash } from '$PROJECT_ROOT/.aai/scripts/lib/prompt-hash.mjs';
process.stdout.write(computeEffectivePromptHash(process.argv[1], process.argv[2]) + '\n');
" "$role_rel" "$root"
}

# run_claims <cwd> [extra canon.mjs claims args...] — sets CANON_OUT /
# CANON_ERR / CANON_RC. <cwd> is either PROJECT_ROOT (live tree, read-only)
# or a scratch COPIED tree (Spec-AC-09/10) — canon.mjs claims never writes
# anything.
run_claims() {
  local cwd="$1"
  shift
  CANON_OUT="$(mktemp "$TEST_DIR/canon-claims-out.XXXXXX")"
  CANON_ERR="$(mktemp "$TEST_DIR/canon-claims-err.XXXXXX")"
  set +e
  ( cd "$cwd" && node "$CANON" claims "$@" >"$CANON_OUT" 2>"$CANON_ERR" )
  CANON_RC=$?
  set -e
}

# run_canon_report <cwd> — `claims --report` against the LIVE default
# manifest at <cwd>. Sets CANON_OUT / CANON_ERR / CANON_RC.
run_canon_report() {
  local cwd="$1"
  CANON_OUT="$(mktemp "$TEST_DIR/canon-report-out.XXXXXX")"
  CANON_ERR="$(mktemp "$TEST_DIR/canon-report-err.XXXXXX")"
  set +e
  ( cd "$cwd" && node "$CANON" claims --report >"$CANON_OUT" 2>"$CANON_ERR" )
  CANON_RC=$?
  set -e
}

# run_canon_check <cwd> [canon.mjs check args...] — sets CANON_OUT / CANON_ERR
# / CANON_RC. <cwd> is PROJECT_ROOT (live tree, read-only) or a scratch
# fixture tree with its own `.aai/system/CANON.yaml` at the default path.
run_canon_check() {
  local cwd="$1"
  shift
  CANON_OUT="$(mktemp "$TEST_DIR/canon-check-out.XXXXXX")"
  CANON_ERR="$(mktemp "$TEST_DIR/canon-check-err.XXXXXX")"
  set +e
  ( cd "$cwd" && node "$CANON" check "$@" >"$CANON_OUT" 2>"$CANON_ERR" )
  CANON_RC=$?
  set -e
}

# build_waiver_fixture <dir> <version> — a COPY of the real
# validation-waiver.mjs + its lib/cli-pipe-guard.mjs dependency (canon.mjs's
# `check --section validation_waiver` dynamically imports the file from
# <dir>, never the shipped one, so a fixture bump is what the check actually
# reads), with `WAIVER_VERSION` bumped to <version>, plus a manifest
# declaring v1 as the only legacy version and a planted stale `v2` literal
# under tests/skills/** (Spec-AC-12's second declared glob).
build_waiver_fixture() {
  local d="$1" version="$2"
  mkdir -p "$d/.aai/scripts/lib" "$d/.aai/system" "$d/tests/skills"
  cp "$PROJECT_ROOT/.aai/scripts/validation-waiver.mjs" "$d/.aai/scripts/validation-waiver.mjs"
  cp "$PROJECT_ROOT/.aai/scripts/lib/cli-pipe-guard.mjs" "$d/.aai/scripts/lib/cli-pipe-guard.mjs"
  sed -i.bak "s/^export const WAIVER_VERSION = [0-9][0-9]*;/export const WAIVER_VERSION = ${version};/" \
    "$d/.aai/scripts/validation-waiver.mjs"
  rm -f "$d/.aai/scripts/validation-waiver.mjs.bak"
  cat > "$d/tests/skills/fixture-waiver-usage.sh" <<'EOF'
# fixture: a stale v2 literal under tests/skills/** for TEST-693's sweep.
REC="[AAI-VALIDATION-WAIVER v2 by=operator ref=FIXTURE at=2026-01-01T00:00:00Z reason=\"x\"]"
EOF
  cat > "$d/.aai/system/CANON.yaml" <<'EOF'
historical: []
annotation_window: 6
claims: []
roles:
  FixtureRole: .aai/ROLE.prompt.md
sections: []
standing_hazards: 0
byte_ceiling: 20000
uniqueness_exceptions: []
waiver_legacy_versions:
  - version: 1
    reason: fixture legacy version
EOF
}

# build_claims_copy <dir> — a COPIED tree (Spec-AC-09's own wording) built
# from the LIVE, unmodified `.aai/system/CANON.yaml` and
# `docs/ai/decisions.jsonl`, plus the LIVE `CHANGELOG.md` at the copy's
# repository root — proving the REAL declared corpus, not a synthetic
# narrower one, reaches root. Callers plant into CHANGELOG.md or a new
# docs/ file under this tree; canon.mjs claims is never run against the
# real repo root.
build_claims_copy() {
  local d="$1"
  mkdir -p "$d/.aai/system" "$d/docs/ai"
  cp "$PROJECT_ROOT/.aai/system/CANON.yaml" "$d/.aai/system/CANON.yaml"
  cp "$PROJECT_ROOT/docs/ai/decisions.jsonl" "$d/docs/ai/decisions.jsonl"
  cp "$PROJECT_ROOT/CHANGELOG.md" "$d/CHANGELOG.md"
}

# section_ids <payload-file> -> space-joined section id sequence, extracted
# the SAME way a real caller would (Spec-AC-01 Verification's own grep).
section_ids() {
  /usr/bin/grep -n '^<<<AAI-CANON-SECTION ' "$1" | sed -E 's/^[0-9]+:<<<AAI-CANON-SECTION //' | tr '\n' ' ' | sed 's/ $//'
}

# manifest_section_ids <manifest-file> -> the manifest's OWN declared order,
# read directly off the file text (never off canon.mjs's internal state).
# Scoped to the `sections:` block only (an awk state machine, not a bare
# grep) — CANON.yaml's `claims:` block also has `  - id: <value>` entries
# (Spec-AC-08) and a bare grep would fold the claim id into this sequence.
manifest_section_ids() {
  awk '
    /^sections:/ { insec=1; next }
    insec && /^[^ ]/ { insec=0 }
    insec && /^  - id: / { sub(/^  - id: /, ""); print }
  ' "$1" | tr '\n' ' ' | sed 's/ $//'
}

# write_fixture_manifest <dir> <sections-order-csv> <standing_hazards> <byte_ceiling> <exceptions-block>
# sections-order-csv is one of "contract,role,learned,scope" or "role,contract,learned,scope".
write_fixture_manifest() {
  local dir="$1" order="$2" hazards="$3" ceiling="$4" exceptions="$5"
  local f="$dir/CANON.yaml"
  {
    echo "roles:"
    echo "  FixtureRole: .aai/ROLE.prompt.md"
    echo "sections:"
    local id
    IFS=',' read -r -a ids <<< "$order"
    for id in "${ids[@]}"; do
      case "$id" in
        contract) echo "  - id: contract"; echo "    type: file"; echo "    path: .aai/SUBAGENT_CONTRACT.md" ;;
        role)     echo "  - id: role"; echo "    type: role" ;;
        learned)  echo "  - id: learned"; echo "    type: file"; echo "    path: docs/knowledge/LEARNED.md" ;;
        scope)    echo "  - id: scope"; echo "    type: scope" ;;
      esac
    done
    echo "standing_hazards: $hazards"
    echo "byte_ceiling: $ceiling"
    if [[ -n "$exceptions" ]]; then
      echo "uniqueness_exceptions:"
      printf '%s\n' "$exceptions"
    else
      echo "uniqueness_exceptions: []"
    fi
  } > "$f"
}

# base_fixture_tree <dir> [contract-file-content] — a minimal, VALID fixture:
# 5 distinct "- HAZ-" lines (no duplicates), a role prompt, a learned file,
# and a manifest in natural order (contract, role, learned, scope). Callers
# override specific files/manifest fields per arm.
base_fixture_tree() {
  local dir="$1"
  mkdir -p "$dir/.aai" "$dir/docs/knowledge"
  cat > "$dir/.aai/SUBAGENT_CONTRACT.md" <<'EOF'
# Fixture Contract

## Standing hazards

- HAZ-ONE — one thing.
- HAZ-TWO — two thing.
- HAZ-THREE — three thing.
- HAZ-FOUR — four thing.
- HAZ-FIVE — five thing.
EOF
  cat > "$dir/.aai/ROLE.prompt.md" <<'EOF'
# Fixture Role Prompt

- Do the role's job.
EOF
  cat > "$dir/docs/knowledge/LEARNED.md" <<'EOF'
# Fixture Learned

- A learned note.
EOF
  write_fixture_manifest "$dir" "contract,role,learned,scope" 5 20000 ""
}

# --- TEST-674 ------------------------------------------------------------------
# Build the Validation payload from the LIVE manifest; the payload's own
# section-id sequence (read from STDOUT, not the manifest) must equal the
# manifest's declared sequence, contract first, scope last.
test_674_build_order_live() {
  run_canon "$PROJECT_ROOT" ".aai/system/CANON.yaml" "Validation" "TEST-674-ref"
  expect_rc 0 "TEST-674 live build"
  local got want first last
  got="$(section_ids "$CANON_OUT")"
  want="$(manifest_section_ids "$LIVE_MANIFEST")"
  [[ "$got" == "$want" ]] \
    || log_fail "TEST-674: payload section order [$got] != manifest declared order [$want]"
  first="$(echo "$got" | awk '{print $1}')"
  last="$(echo "$got" | awk '{print $NF}')"
  [[ "$first" == "contract" ]] || log_fail "TEST-674: first section must be contract, got $first"
  [[ "$last" == "scope" ]] || log_fail "TEST-674: last section must be scope, got $last"
  log_pass "TEST-674 the live payload's section order equals the manifest's declared order, contract first, scope last (order=[$got])"
}

# --- TEST-675 ------------------------------------------------------------------
# D3's own proof: reorder a fixture manifest's first two sections and assert
# the PAYLOAD sequence swapped too — a check reading only the manifest could
# never fail this.
test_675_order_follows_manifest_not_code() {
  local baseline="$TEST_DIR/t675-baseline" swapped="$TEST_DIR/t675-swapped"
  mkdir -p "$baseline" "$swapped"
  base_fixture_tree "$baseline"
  base_fixture_tree "$swapped"
  write_fixture_manifest "$swapped" "role,contract,learned,scope" 5 20000 ""

  run_canon "$baseline" "CANON.yaml" "FixtureRole" "TEST-675-baseline"
  expect_rc 0 "TEST-675 baseline fixture build"
  local base_order swapped_order
  base_order="$(section_ids "$CANON_OUT")"
  [[ "$base_order" == "contract role learned scope" ]] \
    || log_fail "TEST-675 premise: baseline order must be the natural order, got [$base_order]"

  run_canon "$swapped" "CANON.yaml" "FixtureRole" "TEST-675-swapped"
  expect_rc 0 "TEST-675 swapped fixture build"
  swapped_order="$(section_ids "$CANON_OUT")"
  [[ "$swapped_order" == "role contract learned scope" ]] \
    || log_fail "TEST-675: swapping the manifest's first two sections must move the PAYLOAD's first two — expected [role contract learned scope], got [$swapped_order]"
  [[ "$swapped_order" != "$base_order" ]] \
    || log_fail "TEST-675: swapped-manifest payload order must differ from the baseline payload order (vacuous otherwise)"
  log_pass "TEST-675 the payload order follows the manifest's declared order, not a hardcoded one (baseline=[$base_order] swapped=[$swapped_order])"
}

# --- TEST-676 ------------------------------------------------------------------
# A declared section whose source file is absent refuses closed: non-zero
# exit, the named token on stderr, EMPTY stdout — never a truncated payload.
test_676_absent_section_fails_closed() {
  local d="$TEST_DIR/t676"
  mkdir -p "$d/.aai" "$d/docs/knowledge"
  base_fixture_tree "$d"
  # Point the contract section at a file that does not exist.
  sed -i.bak 's#path: \.aai/SUBAGENT_CONTRACT\.md#path: .aai/MISSING_CONTRACT.md#' "$d/CANON.yaml"
  rm -f "$d/CANON.yaml.bak"

  run_canon "$d" "CANON.yaml" "FixtureRole" "TEST-676-ref"
  expect_rc_nonzero "TEST-676 absent section"
  assert_payload_contains "$(cat "$CANON_ERR")" "canon-section-absent: contract .aai/MISSING_CONTRACT.md" \
    "TEST-676: stderr must name the absent section id and path" || return 1
  local out_bytes
  out_bytes="$(wc -c < "$CANON_OUT" | tr -d ' ')"
  [[ "$out_bytes" -eq 0 ]] || log_fail "TEST-676: stdout must be EMPTY on refusal (a truncated payload must never be written), got $out_bytes bytes"

  # Spec-AC-02's OTHER half: a section whose file EXISTS but is EMPTY fails
  # closed the same way as an absent one — "absent OR empty", not just
  # absent. A separate fixture (a present, zero-byte contract file) proves
  # the length-zero branch, never merely the missing-path branch above.
  local d2="$TEST_DIR/t676-empty"
  mkdir -p "$d2/.aai" "$d2/docs/knowledge"
  base_fixture_tree "$d2"
  : > "$d2/.aai/SUBAGENT_CONTRACT.md"
  [[ -f "$d2/.aai/SUBAGENT_CONTRACT.md" && ! -s "$d2/.aai/SUBAGENT_CONTRACT.md" ]] \
    || log_fail "TEST-676: fixture setup: contract file must exist and be empty"

  run_canon "$d2" "CANON.yaml" "FixtureRole" "TEST-676-empty-ref"
  expect_rc_nonzero "TEST-676 present-but-empty section"
  assert_payload_contains "$(cat "$CANON_ERR")" "canon-section-absent: contract .aai/SUBAGENT_CONTRACT.md" \
    "TEST-676: an EMPTY (present, 0-byte) section must refuse the same way as an absent one" || return 1
  local out_bytes2
  out_bytes2="$(wc -c < "$CANON_OUT" | tr -d ' ')"
  [[ "$out_bytes2" -eq 0 ]] || log_fail "TEST-676: stdout must be EMPTY on the empty-section refusal too, got $out_bytes2 bytes"

  log_pass "TEST-676 a declared section refuses closed whether ABSENT or present-but-EMPTY, with the named token and empty stdout"
}

# --- TEST-677 ------------------------------------------------------------------
# The live tree builds clean at the declared 5; a fixture carrying a 6th
# HAZ- rule refuses naming both numbers.
test_677_hazard_count_asserted() {
  run_canon "$PROJECT_ROOT" ".aai/system/CANON.yaml" "Validation" "TEST-677-live"
  expect_rc 0 "TEST-677 live tree must build clean at the declared standing_hazards"

  local d="$TEST_DIR/t677"
  mkdir -p "$d"
  base_fixture_tree "$d"
  cat >> "$d/.aai/SUBAGENT_CONTRACT.md" <<'EOF'
- HAZ-SIX — six thing.
EOF
  # standing_hazards stays declared at 5; the fixture now HAS 6.
  run_canon "$d" "CANON.yaml" "FixtureRole" "TEST-677-fixture"
  expect_rc_nonzero "TEST-677 fixture with a 6th hazard"
  assert_payload_contains "$(cat "$CANON_ERR")" "canon-count-mismatch: standing_hazards declared=5 found=6" \
    "TEST-677: stderr must name both the declared and found counts" || return 1

  # Spec-AC-03 counts LINES matching `^- HAZ-` — anchored at line start, not
  # a bare substring search. An indented or mid-line "- HAZ-" occurrence
  # must NOT inflate the count: a fixture carrying one of each, still
  # declared at 5, must build clean.
  local d3="$TEST_DIR/t677-anchor"
  mkdir -p "$d3"
  base_fixture_tree "$d3"
  cat >> "$d3/.aai/SUBAGENT_CONTRACT.md" <<'EOF'

  - HAZ-SIX — indented, not a line-start rule; must not count.
Text mentioning - HAZ-SEVEN mid-line must not count either.
EOF
  run_canon "$d3" "CANON.yaml" "FixtureRole" "TEST-677-anchor-ref"
  expect_rc 0 "TEST-677 indented/mid-line '- HAZ-' occurrences must not inflate the count (still 5)"

  log_pass "TEST-677 the declared hazard count is asserted against the ASSEMBLED payload (live clean at 5, fixture refuses declared=5 found=6, and an indented/mid-line occurrence is correctly not counted)"
}

# --- TEST-678 ------------------------------------------------------------------
# A rule line repeated verbatim within ONE source file refuses, naming the
# normalized text and BOTH line numbers (fu-contract-ledger-rule-stated-twice's
# exact shape).
test_678_duplicate_rule_refused() {
  local d="$TEST_DIR/t678"
  mkdir -p "$d/.aai" "$d/docs/knowledge"
  base_fixture_tree "$d"
  cat > "$d/.aai/SUBAGENT_CONTRACT.md" <<'EOF'
# Fixture Contract

## Standing hazards

- HAZ-ONE — one thing.
- HAZ-TWO — two thing.
- HAZ-THREE — three thing.
- HAZ-FOUR — four thing.
- HAZ-FIVE — five thing.

## Repeated note

- HAZ-ONE — one thing.
EOF
  # 6 total "- HAZ-" lines now present (the duplicate included) — declare 6
  # so the hazard-COUNT check passes and the DUPLICATE check is what fires.
  write_fixture_manifest "$d" "contract,role,learned,scope" 6 20000 ""

  run_canon "$d" "CANON.yaml" "FixtureRole" "TEST-678-ref"
  expect_rc_nonzero "TEST-678 duplicate rule line"
  assert_payload_contains "$(cat "$CANON_ERR")" 'canon-duplicate-rule: "- HAZ-ONE — one thing."' \
    "TEST-678: stderr must name the normalized duplicated text" || return 1
  assert_payload_contains "$(cat "$CANON_ERR")" ".aai/SUBAGENT_CONTRACT.md:5" \
    "TEST-678: stderr must name the FIRST occurrence's file:line" || return 1
  assert_payload_contains "$(cat "$CANON_ERR")" ".aai/SUBAGENT_CONTRACT.md:13" \
    "TEST-678: stderr must name the SECOND occurrence's file:line" || return 1

  # Spec-AC-04's own text: "No DECLARED CANON RULE LINE shall appear twice"
  # — not "no HAZ-prefixed line". CANON.yaml's own LINE-SHAPE DECISION
  # comment records that a narrower `- HAZ-` -only pattern was considered
  # and REJECTED precisely because it would miss a duplicated NON-hazard
  # rule (fu-contract-ledger-rule-stated-twice's own shape). Prove the
  # broad shape is what actually ships: a fixture whose duplicated bullet
  # is NOT HAZ-prefixed must refuse the same way.
  local d2="$TEST_DIR/t678-nonhaz"
  mkdir -p "$d2/.aai" "$d2/docs/knowledge"
  base_fixture_tree "$d2"
  cat > "$d2/.aai/SUBAGENT_CONTRACT.md" <<'EOF'
# Fixture Contract

## Standing hazards

- HAZ-ONE — one thing.
- HAZ-TWO — two thing.
- HAZ-THREE — three thing.
- HAZ-FOUR — four thing.
- HAZ-FIVE — five thing.

## Non-hazard rule

- Never write docs/ai/STATE.yaml.
- Never write docs/ai/STATE.yaml.
EOF
  # 5 "- HAZ-" lines (no duplicate among them) — declare 5 so the
  # hazard-COUNT check passes cleanly and the DUPLICATE check on the
  # non-hazard bullet is what fires.
  write_fixture_manifest "$d2" "contract,role,learned,scope" 5 20000 ""

  run_canon "$d2" "CANON.yaml" "FixtureRole" "TEST-678-nonhaz-ref"
  expect_rc_nonzero "TEST-678 duplicate NON-hazard rule line"
  assert_payload_contains "$(cat "$CANON_ERR")" 'canon-duplicate-rule: "- Never write docs/ai/STATE.yaml."' \
    "TEST-678: a duplicated non-hazard bullet must refuse by the same mechanism, naming its normalized text" || return 1
  assert_payload_contains "$(cat "$CANON_ERR")" ".aai/SUBAGENT_CONTRACT.md:13" \
    "TEST-678: stderr must name the non-hazard duplicate's FIRST occurrence" || return 1
  assert_payload_contains "$(cat "$CANON_ERR")" ".aai/SUBAGENT_CONTRACT.md:14" \
    "TEST-678: stderr must name the non-hazard duplicate's SECOND occurrence" || return 1

  # Spec-AC-04's own "normalized (trimmed, internal whitespace collapsed)"
  # clause: two occurrences that are NOT byte-identical, but collapse to
  # the same normalized text, must still refuse as a duplicate.
  local d3="$TEST_DIR/t678-whitespace"
  mkdir -p "$d3/.aai" "$d3/docs/knowledge"
  base_fixture_tree "$d3"
  cat > "$d3/.aai/SUBAGENT_CONTRACT.md" <<'EOF'
# Fixture Contract

## Standing hazards

- HAZ-ONE — one thing.
- HAZ-TWO — two thing.
- HAZ-THREE — three thing.
- HAZ-FOUR — four thing.
- HAZ-FIVE — five thing.

## Non-hazard rule, whitespace variant

- Never write docs/ai/STATE.yaml.
-  Never  write  docs/ai/STATE.yaml.
EOF
  write_fixture_manifest "$d3" "contract,role,learned,scope" 5 20000 ""

  run_canon "$d3" "CANON.yaml" "FixtureRole" "TEST-678-whitespace-ref"
  expect_rc_nonzero "TEST-678 two occurrences differing only in internal whitespace"
  assert_payload_contains "$(cat "$CANON_ERR")" 'canon-duplicate-rule: "- Never write docs/ai/STATE.yaml."' \
    "TEST-678: two occurrences collapsing to the SAME normalized text must refuse, even though their raw bytes differ" || return 1
  assert_payload_contains "$(cat "$CANON_ERR")" ".aai/SUBAGENT_CONTRACT.md:13" \
    "TEST-678: stderr must name the whitespace-variant duplicate's FIRST occurrence" || return 1
  assert_payload_contains "$(cat "$CANON_ERR")" ".aai/SUBAGENT_CONTRACT.md:14" \
    "TEST-678: stderr must name the whitespace-variant duplicate's SECOND occurrence" || return 1

  log_pass "TEST-678 a rule line repeated within one source file refuses, naming the text and both line numbers — proven for a HAZ-prefixed line, a non-hazard bullet (the shape a HAZ-only pattern would miss), and a whitespace-variant duplicate (the shape a bare-trim normalization would miss)"
}

# --- TEST-679 ------------------------------------------------------------------
# The SAME duplicate, now declared as a uniqueness_exceptions entry with a
# reason: the build exits 0 AND prints the exception with its reason — an
# admitted duplicate is never silent.
test_679_declared_exception_admitted() {
  local d="$TEST_DIR/t679"
  mkdir -p "$d/.aai" "$d/docs/knowledge"
  base_fixture_tree "$d"
  cat > "$d/.aai/SUBAGENT_CONTRACT.md" <<'EOF'
# Fixture Contract

## Standing hazards

- HAZ-ONE — one thing.
- HAZ-TWO — two thing.
- HAZ-THREE — three thing.
- HAZ-FOUR — four thing.
- HAZ-FIVE — five thing.

## Repeated note

- HAZ-ONE — one thing.
EOF
  write_fixture_manifest "$d" "contract,role,learned,scope" 6 20000 \
'  - text: "- HAZ-ONE — one thing."
    reason: "TEST-679 fixture: the repeated note deliberately restates HAZ-ONE for emphasis"'

  run_canon "$d" "CANON.yaml" "FixtureRole" "TEST-679-ref"
  expect_rc 0 "TEST-679 declared exception must open the build"
  assert_payload_contains "$(cat "$CANON_ERR")" 'canon-duplicate-rule-exception: "- HAZ-ONE — one thing." reason="TEST-679 fixture: the repeated note deliberately restates HAZ-ONE for emphasis"' \
    "TEST-679: an admitted duplicate must be printed with its declared reason" || return 1
  log_pass "TEST-679 a declared uniqueness exception admits the duplicate and prints it with its reason"
}

# --- TEST-680 ------------------------------------------------------------------
# A ceiling one byte below the MEASURED payload size refuses, naming both
# numbers. The ceiling is derived from a REAL build's own printed size
# (D3: parses the assembled output), never computed independently in the test.
test_680_over_budget_refused() {
  local d="$TEST_DIR/t680"
  mkdir -p "$d/.aai" "$d/docs/knowledge"
  base_fixture_tree "$d"

  # Same ref both calls: the scope section's byte length depends on the ref
  # string, so a different ref between the measuring and refusing calls would
  # measure a DIFFERENT payload size and make the ceiling comparison drift by
  # exactly that many bytes — not the over-budget behaviour under test.
  run_canon "$d" "CANON.yaml" "FixtureRole" "TEST-680-ref"
  expect_rc 0 "TEST-680 measuring build must succeed under a generous ceiling"
  local measured
  measured="$(/usr/bin/grep -o 'bytes=[0-9]*' "$CANON_ERR" | qhead -n1 | cut -d= -f2)" || true
  [[ -n "$measured" ]] || log_fail "TEST-680: could not read the measured byte size off stderr"

  write_fixture_manifest "$d" "contract,role,learned,scope" 5 "$((measured - 1))" ""
  run_canon "$d" "CANON.yaml" "FixtureRole" "TEST-680-ref"
  expect_rc_nonzero "TEST-680 ceiling one byte below measured"
  assert_payload_contains "$(cat "$CANON_ERR")" "canon-over-budget: measured=$measured ceiling=$((measured - 1))" \
    "TEST-680: stderr must name both the measured size and the ceiling" || return 1
  log_pass "TEST-680 a ceiling one byte below the measured payload refuses, naming measured=$measured ceiling=$((measured - 1))"
}

# --- TEST-681 ------------------------------------------------------------------
# The size the LIVE build prints equals `wc -c` of the CAPTURED payload —
# the printed number is asserted against the real bytes, not decorative
# (the fu-allowlist-count-is-prose-not-asserted lesson).
test_681_size_is_the_real_size() {
  run_canon "$PROJECT_ROOT" ".aai/system/CANON.yaml" "Validation" "TEST-681-ref"
  expect_rc 0 "TEST-681 live build"
  local printed actual
  printed="$(/usr/bin/grep -o 'bytes=[0-9]*' "$CANON_ERR" | qhead -n1 | cut -d= -f2)" || true
  actual="$(wc -c < "$CANON_OUT" | tr -d ' ')"
  [[ -n "$printed" ]] || log_fail "TEST-681: could not read the printed byte size off stderr"
  [[ "$printed" -eq "$actual" ]] \
    || log_fail "TEST-681: printed size ($printed) must equal wc -c of the captured payload ($actual)"
  log_pass "TEST-681 the printed payload size ($printed) equals wc -c of the captured stdout bytes"
}

# --- TEST-682 ------------------------------------------------------------------
# `build --print-hash` in a fixture tree equals `lib/prompt-hash.mjs`'s OWN
# computeEffectivePromptHash for the same role prompt (S2: call BOTH real
# implementations on one tree, never mock either).
test_682_hash_matches_prompt_hash() {
  local d="$TEST_DIR/t682"
  mkdir -p "$d"
  base_fixture_tree "$d"

  run_canon_hash "$d" "CANON.yaml" "FixtureRole" "TEST-682-ref"
  expect_rc 0 "TEST-682 print-hash build"
  local canon_hash ref_hash
  canon_hash="$(cat "$CANON_OUT")"
  ref_hash="$(reference_prompt_hash "$d" ".aai/ROLE.prompt.md")"
  [[ -n "$canon_hash" ]] || log_fail "TEST-682: canon.mjs printed no hash"
  [[ "$canon_hash" == "$ref_hash" ]] \
    || log_fail "TEST-682: canon.mjs build --print-hash ($canon_hash) != computeEffectivePromptHash ($ref_hash)"
  log_pass "TEST-682 build --print-hash equals computeEffectivePromptHash for the same fixture tree ($canon_hash)"
}

# --- TEST-683 ------------------------------------------------------------------
# A one-byte change to the fixture contract changes BOTH digests to the SAME
# new value — the telemetry hash moves with the contract, not just the role
# prompt.
test_683_hash_moves_with_the_contract() {
  local d="$TEST_DIR/t683"
  mkdir -p "$d"
  base_fixture_tree "$d"

  run_canon_hash "$d" "CANON.yaml" "FixtureRole" "TEST-683-ref"
  expect_rc 0 "TEST-683 baseline print-hash build"
  local hash_before ref_before
  hash_before="$(cat "$CANON_OUT")"
  ref_before="$(reference_prompt_hash "$d" ".aai/ROLE.prompt.md")"
  [[ "$hash_before" == "$ref_before" ]] \
    || log_fail "TEST-683 premise: baseline digests must already agree (canon=$hash_before ref=$ref_before)"

  printf '.' >> "$d/.aai/SUBAGENT_CONTRACT.md"

  run_canon_hash "$d" "CANON.yaml" "FixtureRole" "TEST-683-ref"
  expect_rc 0 "TEST-683 mutated print-hash build"
  local hash_after ref_after
  hash_after="$(cat "$CANON_OUT")"
  ref_after="$(reference_prompt_hash "$d" ".aai/ROLE.prompt.md")"
  [[ "$hash_after" == "$ref_after" ]] \
    || log_fail "TEST-683: after the one-byte contract change the digests must still agree (canon=$hash_after ref=$ref_after)"
  [[ "$hash_after" != "$hash_before" ]] \
    || log_fail "TEST-683: a one-byte contract change must move the digest, got the same value twice ($hash_before)"
  log_pass "TEST-683 a one-byte contract change moves both digests to the same new value ($hash_before -> $hash_after)"
}

# --- TEST-684 ------------------------------------------------------------------
# .aai/ORCHESTRATION.prompt.md carries the orchestrator's OWN
# `canon.mjs build` command line; EXTRACT it with a pinned pattern and
# EXECUTE it — asserting a prompt CONTAINS a string would be prose checking
# prose (D8, the exact debt this ride repays).
test_684_prompt_command_runs() {
  local orch="$PROJECT_ROOT/.aai/ORCHESTRATION.prompt.md"
  [[ -f "$orch" ]] || log_fail "TEST-684: .aai/ORCHESTRATION.prompt.md not found"

  local matches match_count extracted
  matches="$(/usr/bin/grep -oE '`node \.aai/scripts/canon\.mjs build[^`]*`' "$orch")" || true
  match_count="$(printf '%s\n' "$matches" | /usr/bin/grep -c . || true)"
  [[ "$match_count" -eq 1 ]] \
    || log_fail "TEST-684: expected exactly one pinned canon.mjs build command line in $orch, found $match_count"
  extracted="${matches#\`}"
  extracted="${extracted%\`}"

  local run_out run_err run_rc
  run_out="$(mktemp "$TEST_DIR/t684-run-out.XXXXXX")"
  run_err="$(mktemp "$TEST_DIR/t684-run-err.XXXXXX")"
  set +e
  ( cd "$PROJECT_ROOT" && eval "$extracted" >"$run_out" 2>"$run_err" )
  run_rc=$?
  set -e
  [[ "$run_rc" -eq 0 ]] \
    || log_fail "TEST-684: executing the prompt's own command ($extracted) must exit 0, got $run_rc — stderr: $(payload_preview "$(cat "$run_err")")"

  local first
  first="$(/usr/bin/grep -m1 '^<<<AAI-CANON-SECTION ' "$run_out" | sed -E 's/^<<<AAI-CANON-SECTION //')"
  [[ "$first" == "contract" ]] \
    || log_fail "TEST-684: the executed command's payload must be contract-first, got first section '$first'"

  local lc
  lc="$(wc -l < "$orch" | tr -d ' ')"
  [[ "$lc" -le 45 ]] \
    || log_fail "TEST-684: .aai/ORCHESTRATION.prompt.md must stay at or under its 45-line ceiling, got $lc"

  log_pass "TEST-684 the prompt's own canon.mjs build command line executes (exit 0, contract-first, $lc/45 lines)"
}

# --- TEST-685 ------------------------------------------------------------------
# A fixture claim naming a `hitl_decision` timestamp absent from the ledger
# refuses with `claim-record-unresolvable`, naming the claim id.
test_685_claim_record_must_resolve() {
  local d="$TEST_DIR/t685"
  mkdir -p "$d/.aai/system" "$d/docs/ai"
  cat > "$d/docs/ai/decisions.jsonl" <<'EOF'
{"v":1,"ts":"2020-01-01T00:00:00Z","type":"hitl_decision","ref_id":"unrelated-decision","decision":"n/a"}
EOF
  cat > "$d/.aai/system/CANON.yaml" <<'EOF'
historical: []
annotation_window: 6
claims:
  - id: fixture-claim
    decision_ts: 2099-01-01T00:00:00Z
    decision_ref: does-not-exist
    corpus:
      - "*.md"
    patterns:
      - unreachable claim text
roles:
  FixtureRole: .aai/ROLE.prompt.md
sections: []
standing_hazards: 0
byte_ceiling: 20000
uniqueness_exceptions: []
EOF

  run_claims "$d" "--manifest" ".aai/system/CANON.yaml"
  expect_rc_nonzero "TEST-685 unresolvable claim record"
  assert_payload_contains "$(cat "$CANON_ERR")" "claim-record-unresolvable: fixture-claim does-not-exist 2099-01-01T00:00:00Z" \
    "TEST-685: stderr must name the claim id, decision ref and decision timestamp" || return 1

  # The fixture above changes BOTH decision_ref and decision_ts at once, so
  # it cannot tell whether the TIMESTAMP half of the match is compared at
  # all. Isolate it: a record whose ref_id MATCHES the claim's declared
  # decision_ref but whose ts does NOT must still refuse — proving
  # `decision_ts` is independently asserted, not just `decision_ref`.
  local d2="$TEST_DIR/t685-ts-only"
  mkdir -p "$d2/.aai/system" "$d2/docs/ai"
  cat > "$d2/docs/ai/decisions.jsonl" <<'EOF'
{"v":1,"ts":"1999-01-01T00:00:00Z","type":"hitl_decision","ref_id":"does-not-exist","decision":"n/a"}
EOF
  cp "$d/.aai/system/CANON.yaml" "$d2/.aai/system/CANON.yaml"

  run_claims "$d2" "--manifest" ".aai/system/CANON.yaml"
  expect_rc_nonzero "TEST-685 matching ref_id but mismatched decision_ts"
  assert_payload_contains "$(cat "$CANON_ERR")" "claim-record-unresolvable: fixture-claim does-not-exist 2099-01-01T00:00:00Z" \
    "TEST-685: a ref_id match with a mismatched decision_ts must still refuse (the ts half is not decorative)" || return 1

  log_pass "TEST-685 a claim whose decision timestamp is absent from the ledger refuses, naming the claim id — proven with decision_ref and decision_ts mismatched together AND with decision_ts isolated"
}

# --- TEST-686 ------------------------------------------------------------------
# `claims` over the LIVE tree exits 0 and reports the number of files
# scanned as non-zero — an EMPTY scan must never look like a CLEAN one (the
# fu-allowlist-count-is-prose-not-asserted lesson, reapplied here).
test_686_live_claims_clean() {
  run_claims "$PROJECT_ROOT"
  expect_rc 0 "TEST-686 live claims run"
  local scanned
  scanned="$(/usr/bin/grep -o 'scanned=[0-9]*' "$CANON_ERR" | qhead -n1 | cut -d= -f2)" || true
  [[ -n "$scanned" ]] || log_fail "TEST-686: could not read the scanned-file count off stderr"
  [[ "$scanned" -gt 0 ]] \
    || log_fail "TEST-686: scanned count must be non-zero (an empty scan cannot look clean), got $scanned"
  log_pass "TEST-686 the live tree's claims run exits 0 and scanned $scanned files"
}

# --- TEST-687 ------------------------------------------------------------------
# The declared corpus reaches the REPOSITORY ROOT: an un-annotated planted
# assertion of the withdrawn claim in a COPIED tree's CHANGELOG.md is
# reported with its file:line and a non-zero exit; removing it exits 0.
# (Closes fu-sweep-scope-excludes-repo-root.)
test_687_root_changelog_in_corpus() {
  local d="$TEST_DIR/t687"
  mkdir -p "$d"
  build_claims_copy "$d"

  local before planted_line
  before="$(wc -l < "$d/CHANGELOG.md" | tr -d ' ')"
  printf '%s\n' "AAI-CANON-TEST-687-PLANT: They are deleted by a separate change." >> "$d/CHANGELOG.md"
  planted_line=$((before + 1))

  run_claims "$d"
  expect_rc_nonzero "TEST-687 planted root-level claim"
  assert_payload_contains "$(cat "$CANON_ERR")" "claim-live-assertion: tripwire-permanent CHANGELOG.md:$planted_line" \
    "TEST-687: stderr must name CHANGELOG.md and the planted line number" || return 1

  local tmp="$d/CHANGELOG.md.tmp"
  /usr/bin/grep -v '^AAI-CANON-TEST-687-PLANT:' "$d/CHANGELOG.md" > "$tmp"
  mv "$tmp" "$d/CHANGELOG.md"
  run_claims "$d"
  expect_rc 0 "TEST-687 after removing the planted line"

  # `annotation_window: 6` is a BOUND, not "any later annotation exempts
  # everything before it": a correction/withdrawal marker further than 6
  # lines AFTER the hit must NOT exempt it. Plant a hit, then 7 filler
  # lines (pushing a CORRECTION marker to i+8, one past the declared
  # window's i+6 reach), and assert the hit is still reported live.
  local d2="$TEST_DIR/t687-window"
  mkdir -p "$d2"
  build_claims_copy "$d2"
  local before2 hit_line
  before2="$(wc -l < "$d2/CHANGELOG.md" | tr -d ' ')"
  {
    printf '%s\n' "AAI-CANON-TEST-687-FAR: They are deleted by a separate change."
    printf 'filler line %s\n' 1 2 3 4 5 6 7
    printf '%s\n' "**CORRECTION (2026-08-23).** too far away to exempt the hit above."
  } >> "$d2/CHANGELOG.md"
  hit_line=$((before2 + 1))

  run_claims "$d2"
  expect_rc_nonzero "TEST-687 a correction marker further than annotation_window (6) lines away must not exempt"
  assert_payload_contains "$(cat "$CANON_ERR")" "claim-live-assertion: tripwire-permanent CHANGELOG.md:$hit_line" \
    "TEST-687: a hit whose only nearby annotation sits BEYOND the declared window must still be reported" || return 1

  log_pass "TEST-687 the declared corpus reaches CHANGELOG.md at the repository root (planted at line $planted_line, clean after removal), and annotation_window is a bound — a correction 8 lines away does not exempt a hit at line $hit_line"
}

# --- TEST-688 ------------------------------------------------------------------
# The declared pattern set covers BOTH present-tense variants ("are/is
# deleted by a separate change"), each reported on its OWN line — not just
# the first hit found (fu-sweep-regex-misses-present-tense's exact shape).
test_688_present_tense_matched() {
  local d="$TEST_DIR/t688"
  mkdir -p "$d"
  build_claims_copy "$d"
  cat > "$d/docs/plant-688.md" <<'EOF'
AAI-CANON-TEST-688-A: They are deleted by a separate change.
AAI-CANON-TEST-688-B: It is deleted by a separate change.
EOF

  run_claims "$d"
  expect_rc_nonzero "TEST-688 present-tense variants"
  assert_payload_contains "$(cat "$CANON_ERR")" "claim-live-assertion: tripwire-permanent docs/plant-688.md:1" \
    "TEST-688: the 'are deleted' variant (line 1) must be reported" || return 1
  assert_payload_contains "$(cat "$CANON_ERR")" "claim-live-assertion: tripwire-permanent docs/plant-688.md:2" \
    "TEST-688: the 'is deleted' variant (line 2) must be reported" || return 1
  log_pass "TEST-688 both present-tense variants are each reported on their own line"
}

# --- TEST-689 ------------------------------------------------------------------
# A negative control — a sentence about deletion that does NOT assert the
# withdrawn claim — is NOT reported: the pattern set is not a bare substring
# sweep on the word "deleted".
test_689_negative_control() {
  local d="$TEST_DIR/t689"
  mkdir -p "$d"
  build_claims_copy "$d"
  cat > "$d/docs/plant-689.md" <<'EOF'
AAI-CANON-TEST-689-CONTROL: We deleted a temporary file during cleanup.
EOF

  run_claims "$d"
  expect_rc 0 "TEST-689 negative control must not trip the sweep"
  assert_payload_not_contains "$(cat "$CANON_ERR")" "docs/plant-689.md" \
    "TEST-689: the negative-control line must not be reported" || return 1
  log_pass "TEST-689 a sentence about deletion that does not assert the withdrawn claim is not reported"
}

# --- TEST-690 ------------------------------------------------------------------
# `claims --report` GENERATES the per-doc-type counts by scanning the live
# corpus for the claim's OWN dated correction annotations — never hand-counted
# (closes fu-spec-d6-enumeration-stale). Measured 2026-09-25: 3 specs, 4 intakes.
test_690_enumeration_is_generated() {
  run_canon_report "$PROJECT_ROOT"
  expect_rc 0 "TEST-690 live claims --report"
  local specs intakes
  specs="$(/usr/bin/grep -o 'specs=[0-9]*' "$CANON_ERR" | qhead -n1 | cut -d= -f2)" || true
  intakes="$(/usr/bin/grep -o 'intakes=[0-9]*' "$CANON_ERR" | qhead -n1 | cut -d= -f2)" || true
  [[ -n "$specs" && -n "$intakes" ]] || log_fail "TEST-690: could not read specs=/intakes= counts off stderr"
  [[ "$specs" -eq 3 ]] || log_fail "TEST-690: expected the generated specs count to be 3, got $specs"
  [[ "$intakes" -eq 4 ]] || log_fail "TEST-690: expected the generated intakes count to be 4, got $intakes"

  # The origin-doc exclusion (Spec-AC-11) must NEVER be silent — same
  # never-silent-exception discipline TEST-679 pins for uniqueness_exceptions,
  # applied here to origin_docs. Assert the live report actually PRINTS the
  # exclusion and its declared reason, naming the excluded path.
  assert_payload_contains "$(cat "$CANON_ERR")" "canon-claims-report-origin-excluded: id=tripwire-permanent docs/specs/SPEC-0137-spec-suites-must-not-touch-the-shipping-repo.md reason=\"" \
    "TEST-690: the origin-doc exclusion must be printed, naming the excluded path and a non-empty reason" || return 1

  log_pass "TEST-690 claims --report generates specs=$specs intakes=$intakes from the live corpus, and its origin-doc exclusion is printed (never silent)"
}

# --- TEST-691 ------------------------------------------------------------------
# SPEC-0148 carries a dated additive block stating the true set; its two
# numbers must equal claims --report's own numbers, read from the report and
# from the spec file — never a literal hard-coded in this test.
test_691_spec0148_block_matches_report() {
  run_canon_report "$PROJECT_ROOT"
  expect_rc 0 "TEST-691 live claims --report"
  local report_specs report_intakes
  report_specs="$(/usr/bin/grep -o 'specs=[0-9]*' "$CANON_ERR" | qhead -n1 | cut -d= -f2)" || true
  report_intakes="$(/usr/bin/grep -o 'intakes=[0-9]*' "$CANON_ERR" | qhead -n1 | cut -d= -f2)" || true
  [[ -n "$report_specs" && -n "$report_intakes" ]] || log_fail "TEST-691: could not read the report's own counts"

  local spec0148="$PROJECT_ROOT/docs/specs/SPEC-0148-spec-the-tripwire-is-permanent-not-transitional.md"
  [[ -f "$spec0148" ]] || log_fail "TEST-691: SPEC-0148 not found: $spec0148"
  local extract_js='
import { readFileSync } from "node:fs";
const t = readFileSync(process.argv[1], "utf8");
const m = /(\d+) specs? \([^)]+\) and (\d+) intakes? \([^)]+\)/.exec(t);
process.stdout.write(m ? m[1] + " " + m[2] : "");
'
  local block_counts block_specs block_intakes
  block_counts="$(node --input-type=module -e "$extract_js" "$spec0148")"
  block_specs="${block_counts%% *}"
  block_intakes="${block_counts##* }"
  [[ -n "$block_specs" && -n "$block_intakes" && "$block_counts" == *" "* ]] \
    || log_fail "TEST-691: SPEC-0148 must carry a dated block stating '<N> specs (...) and <M> intakes (...)'"
  [[ "$block_specs" -eq "$report_specs" ]] \
    || log_fail "TEST-691: SPEC-0148's block states $block_specs specs but the report generated $report_specs"
  [[ "$block_intakes" -eq "$report_intakes" ]] \
    || log_fail "TEST-691: SPEC-0148's block states $block_intakes intakes but the report generated $report_intakes"
  log_pass "TEST-691 SPEC-0148's dated block ($block_specs specs, $block_intakes intakes) equals claims --report's own generated counts"
}

# --- TEST-692 ------------------------------------------------------------------
# The waiver grammar line, RENDERED from validation-waiver.mjs's own exported
# WAIVER_SENTINEL / WAIVER_VERSION / WAIVER_KEY_ORDER, appears VERBATIM as a
# comment line in that file's own header — an INDEPENDENT second render
# (never trusting canon.mjs's internal comparison alone), matching S2's
# both-implementations discipline.
test_692_grammar_rendered_from_code() {
  run_canon_check "$PROJECT_ROOT" --section validation_waiver
  expect_rc 0 "TEST-692 live validation_waiver check"

  # The path is INTERPOLATED into the script, never passed as process.argv[1]:
  # validation-waiver.mjs's own main-guard compares process.argv[1] against
  # its real path (a PROCESS-global array, shared by every dynamically
  # imported module), so passing that same path as our positional arg would
  # spuriously satisfy its own "am I the entry point" check and run its CLI.
  local waiver_path="$PROJECT_ROOT/.aai/scripts/validation-waiver.mjs"
  local render_js="
import { pathToFileURL } from 'node:url';
const mod = await import(pathToFileURL('${waiver_path}').href);
const { WAIVER_SENTINEL, WAIVER_VERSION, WAIVER_KEY_ORDER, WAIVER_PLACEHOLDERS } = mod;
const line = '[' + WAIVER_SENTINEL + ' v' + WAIVER_VERSION + ' '
  + WAIVER_KEY_ORDER.map((k) => k + '=' + WAIVER_PLACEHOLDERS[k]).join(' ') + ']';
process.stdout.write(line);
"
  local rendered
  rendered="$(node --input-type=module -e "$render_js")"
  [[ -n "$rendered" ]] || log_fail "TEST-692: could not independently render the grammar line"
  /usr/bin/grep -qF "$rendered" "$PROJECT_ROOT/.aai/scripts/validation-waiver.mjs" \
    || log_fail "TEST-692: rendered grammar line [$rendered] not found verbatim in validation-waiver.mjs"

  # The bash re-render above proves the LITERAL matches today; it does NOT
  # prove the GATE (`canon.mjs check --section validation_waiver`) would
  # refuse if the header ever drifted from it. Drive the checker itself on a
  # fixture copy: unmodified first (positive control — a clean copy must
  # still pass), then with the header's own grammar comment drifted, which
  # must refuse by name.
  local d="$TEST_DIR/t692"
  mkdir -p "$d"
  build_waiver_fixture "$d" 2
  run_canon_check "$d" --section validation_waiver
  expect_rc 0 "TEST-692 fixture copy, header intact (positive control)"

  sed -i.bak 's/at=<YYYY-MM-DDTHH:MM:SSZ>/at=<TIMESTAMP>/' "$d/.aai/scripts/validation-waiver.mjs"
  rm -f "$d/.aai/scripts/validation-waiver.mjs.bak"
  run_canon_check "$d" --section validation_waiver
  expect_rc_nonzero "TEST-692 fixture copy, header grammar drifted"
  assert_payload_contains "$(cat "$CANON_ERR")" "waiver-grammar-drift: .aai/scripts/validation-waiver.mjs does not carry the rendered grammar line verbatim" \
    "TEST-692: the GATE itself must refuse a drifted header, naming waiver-grammar-drift and the file" || return 1

  log_pass "TEST-692 the independently-rendered grammar line ($rendered) appears verbatim in validation-waiver.mjs's own header, and the GATE refuses when it drifts (clean fixture passes, drifted fixture refuses)"
}

# --- TEST-693 ------------------------------------------------------------------
# The live tree exits 0 (v2 current, v1 declared legacy); a fixture COPY with
# WAIVER_VERSION bumped to 3 refuses, naming the header line plus every stale
# v2 literal under BOTH declared globs (.aai/** and tests/skills/**).
test_693_version_bump_names_every_stale_literal() {
  run_canon_check "$PROJECT_ROOT" --section validation_waiver
  expect_rc 0 "TEST-693 live tree (v2 current, v1 declared legacy)"

  local d="$TEST_DIR/t693"
  mkdir -p "$d"
  build_waiver_fixture "$d" 3

  run_canon_check "$d" --section validation_waiver
  expect_rc_nonzero "TEST-693 fixture with WAIVER_VERSION=3"
  assert_payload_contains "$(cat "$CANON_ERR")" "waiver-grammar-drift:" \
    "TEST-693: stderr must refuse with waiver-grammar-drift" || return 1
  assert_payload_contains "$(cat "$CANON_ERR")" ".aai/scripts/validation-waiver.mjs" \
    "TEST-693: stderr must name the header line's own file" || return 1
  assert_payload_contains "$(cat "$CANON_ERR")" "tests/skills/fixture-waiver-usage.sh" \
    "TEST-693: stderr must name the stale v2 literal under tests/skills/**" || return 1
  log_pass "TEST-693 a WAIVER_VERSION bump refuses, naming the header line and every stale v2 literal under the declared globs"
}

# --- TEST-694 ------------------------------------------------------------------
# .aai/VALIDATION.prompt.md states STANDING DECISION (a) with its 2026-09-12
# citation, and check --section decision_citations resolves it (and the prior
# review-round-cap citation) against an owner_signoff: true record.
test_694_round_cap_amendment_present() {
  /usr/bin/grep -q "STANDING DECISION (a)" "$PROJECT_ROOT/.aai/VALIDATION.prompt.md" \
    || log_fail "TEST-694: .aai/VALIDATION.prompt.md must carry STANDING DECISION (a)"
  /usr/bin/grep -q "owner decision wave-2-roadmap, 2026-09-12" "$PROJECT_ROOT/.aai/VALIDATION.prompt.md" \
    || log_fail "TEST-694: .aai/VALIDATION.prompt.md must cite 'owner decision wave-2-roadmap, 2026-09-12'"

  run_canon_check "$PROJECT_ROOT" --section decision_citations
  expect_rc 0 "TEST-694 live decision_citations check"
  local resolved
  resolved="$(/usr/bin/grep -o 'resolved=[0-9]*' "$CANON_ERR" | qhead -n1 | cut -d= -f2)" || true
  [[ -n "$resolved" ]] || log_fail "TEST-694: could not read the resolved-citation count off stderr"
  [[ "$resolved" -ge 2 ]] \
    || log_fail "TEST-694: expected at least 2 resolved citations (review-round-cap + wave-2-roadmap), got $resolved"

  # Spec-AC-13's own clause: matching ref_id AND matching date is NOT
  # enough — the record must also carry `owner_signoff: true`. A fixture
  # whose decision record matches ref_id and date exactly but is UNSIGNED
  # (owner_signoff: false) must still refuse — otherwise a decision nobody
  # signed would bind every role reading the citation. This is the arm the
  # frozen Mutation cell below names ("the arm that asserts an unsigned
  # record is refused reddens") and it did not exist before this round.
  local d="$TEST_DIR/t694-unsigned"
  mkdir -p "$d/.aai/system" "$d/docs/ai"
  cat > "$d/docs/ai/decisions.jsonl" <<'EOF'
{"v":1,"ts":"2099-03-04T00:00:00Z","type":"hitl_decision","ref_id":"unsigned-decision","owner_signoff":false,"decision":"n/a"}
EOF
  cat > "$d/.aai/FIXTURE.prompt.md" <<'EOF'
# Fixture prompt
Cites (owner decision unsigned-decision, 2099-03-04) — ref_id and date match, signoff does not.
EOF
  cat > "$d/.aai/system/CANON.yaml" <<'EOF'
historical: []
annotation_window: 6
claims: []
roles:
  FixtureRole: .aai/ROLE.prompt.md
sections: []
standing_hazards: 0
byte_ceiling: 20000
uniqueness_exceptions: []
EOF
  run_canon_check "$d" --section decision_citations
  expect_rc_nonzero "TEST-694 an unsigned decision record (owner_signoff:false) with matching ref_id and date"
  assert_payload_contains "$(cat "$CANON_ERR")" "citation-unresolvable: .aai/FIXTURE.prompt.md:2 ref=unsigned-decision date=2099-03-04" \
    "TEST-694: an unsigned record must refuse the citation by name, naming the prompt file:line" || return 1
  assert_payload_contains "$(cat "$CANON_ERR")" "resolved=0" \
    "TEST-694: an unsigned-only match must not count toward resolved=" || return 1

  log_pass "TEST-694 STANDING DECISION (a) is present, cites wave-2-roadmap 2026-09-12, the citation check resolves $resolved citations, and an unsigned matching record is refused"
}

# --- TEST-695 ------------------------------------------------------------------
# A fixture prompt whose cited decision date is one day off the ledger
# refuses with citation-unresolvable, naming the prompt file:line; the check
# still prints the number of citations it resolved (zero).
test_695_citation_must_resolve() {
  local d="$TEST_DIR/t695"
  mkdir -p "$d/.aai/system" "$d/docs/ai"
  cat > "$d/docs/ai/decisions.jsonl" <<'EOF'
{"v":1,"ts":"2099-01-02T00:00:00Z","type":"hitl_decision","ref_id":"fixture-decision","owner_signoff":true,"decision":"n/a"}
EOF
  cat > "$d/.aai/FIXTURE.prompt.md" <<'EOF'
# Fixture prompt
Cites (owner decision fixture-decision, 2099-01-01) — one day off from the ledger.
EOF
  cat > "$d/.aai/system/CANON.yaml" <<'EOF'
historical: []
annotation_window: 6
claims: []
roles:
  FixtureRole: .aai/ROLE.prompt.md
sections: []
standing_hazards: 0
byte_ceiling: 20000
uniqueness_exceptions: []
EOF

  run_canon_check "$d" --section decision_citations
  expect_rc_nonzero "TEST-695 citation dated one day off the ledger"
  assert_payload_contains "$(cat "$CANON_ERR")" "citation-unresolvable: .aai/FIXTURE.prompt.md:2 ref=fixture-decision date=2099-01-01" \
    "TEST-695: stderr must name the prompt file:line and the unresolved ref/date" || return 1
  assert_payload_contains "$(cat "$CANON_ERR")" "resolved=0" \
    "TEST-695: stderr must print the number of citations it resolved" || return 1
  log_pass "TEST-695 a citation dated one day off the ledger refuses, naming the prompt file:line, resolved=0 printed"
}

# --- TEST-698 ------------------------------------------------------------------
# `check --all` exits 0 against the REAL repository and prints a non-zero
# count for every section it ran — an empty check can never look clean.
test_698_live_check_all() {
  run_canon_check "$PROJECT_ROOT" --all
  expect_rc 0 "TEST-698 live check --all"
  local checked resolved
  checked="$(/usr/bin/grep -o 'checked=[0-9]*' "$CANON_ERR" | qhead -n1 | cut -d= -f2)" || true
  resolved="$(/usr/bin/grep -o 'resolved=[0-9]*' "$CANON_ERR" | qhead -n1 | cut -d= -f2)" || true
  [[ -n "$checked" ]] || log_fail "TEST-698: could not read the validation_waiver checked= count off stderr"
  [[ "$checked" -gt 0 ]] || log_fail "TEST-698: validation_waiver checked count must be non-zero, got $checked"
  [[ -n "$resolved" ]] || log_fail "TEST-698: could not read the decision_citations resolved= count off stderr"
  [[ "$resolved" -gt 0 ]] || log_fail "TEST-698: decision_citations resolved count must be non-zero, got $resolved"
  log_pass "TEST-698 check --all exits 0 against the live tree (checked=$checked waiver literals, resolved=$resolved citations)"
}

# --- TEST-699 ------------------------------------------------------------------
# `build --role <R>` exits 0 for every role the LIVE manifest declares, and
# the declared role count matches the number of successful builds.
manifest_role_names() {
  awk '
    /^roles:/ { insec=1; next }
    insec && /^[^ ]/ { insec=0 }
    insec && /^  [A-Za-z]/ { sub(/:.*/, ""); sub(/^  /, ""); print }
  ' "$1"
}

test_699_live_build_every_role() {
  local roles count built role
  roles="$(manifest_role_names "$LIVE_MANIFEST")"
  count="$(printf '%s\n' "$roles" | qgrep -c .)" || true
  [[ -n "$count" && "$count" -gt 0 ]] || log_fail "TEST-699: could not read any declared role from $LIVE_MANIFEST"
  built=0
  while IFS= read -r role; do
    [[ -n "$role" ]] || continue
    run_canon "$PROJECT_ROOT" ".aai/system/CANON.yaml" "$role" "TEST-699-ref"
    expect_rc 0 "TEST-699 live build --role $role"
    built=$((built + 1))
  done <<< "$roles"
  [[ "$built" -eq "$count" ]] \
    || log_fail "TEST-699: built $built payloads but the manifest declares $count roles"
  log_pass "TEST-699 build --role <R> exits 0 for every one of the $count declared roles"
}

# --- runner ------------------------------------------------------------------

ALL_TESTS="674_build_order_live 675_order_follows_manifest_not_code 676_absent_section_fails_closed 677_hazard_count_asserted 678_duplicate_rule_refused 679_declared_exception_admitted 680_over_budget_refused 681_size_is_the_real_size 682_hash_matches_prompt_hash 683_hash_moves_with_the_contract 684_prompt_command_runs 685_claim_record_must_resolve 686_live_claims_clean 687_root_changelog_in_corpus 688_present_tense_matched 689_negative_control 690_enumeration_is_generated 691_spec0148_block_matches_report 692_grammar_rendered_from_code 693_version_bump_names_every_stale_literal 694_round_cap_amendment_present 695_citation_must_resolve 698_live_check_all 699_live_build_every_role"

main() {
  local requested="${1:-}"
  requested="${requested#test_}"  # mutation-run.mjs's --selector passes the FULL test_* name
  check_deps
  setup_fixture
  local selected="" t
  for t in $ALL_TESTS; do
    if [[ -z "$requested" || "$t" == "$requested"* ]]; then
      selected="$selected $t"
    fi
  done
  if [[ -z "$selected" ]]; then
    log_fail "no arm matches '$requested' (available: $ALL_TESTS)"
  fi
  for t in $selected; do
    "test_${t}"
  done
  echo "ALL TESTS PASSED: $TEST_NAME ($selected )"
}

main "$@"
