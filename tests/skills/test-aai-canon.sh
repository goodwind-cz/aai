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
  log_pass "TEST-676 an absent declared section refuses closed with the named token and empty stdout"
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
  log_pass "TEST-677 the declared hazard count is asserted against the ASSEMBLED payload (live clean at 5, fixture refuses declared=5 found=6)"
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
  log_pass "TEST-678 a rule line repeated within one source file refuses, naming the text and both line numbers"
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
  log_pass "TEST-685 a claim whose decision timestamp is absent from the ledger refuses, naming the claim id"
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
  log_pass "TEST-687 the declared corpus reaches CHANGELOG.md at the repository root (planted at line $planted_line, clean after removal)"
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

# --- runner ------------------------------------------------------------------

ALL_TESTS="674_build_order_live 675_order_follows_manifest_not_code 676_absent_section_fails_closed 677_hazard_count_asserted 678_duplicate_rule_refused 679_declared_exception_admitted 680_over_budget_refused 681_size_is_the_real_size 682_hash_matches_prompt_hash 683_hash_moves_with_the_contract 684_prompt_command_runs 685_claim_record_must_resolve 686_live_claims_clean 687_root_changelog_in_corpus 688_present_tense_matched 689_negative_control"

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
