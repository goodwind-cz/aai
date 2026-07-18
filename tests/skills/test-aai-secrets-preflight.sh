#!/usr/bin/env bash
#
# Test: intake secrets preflight (CHANGE-0034 /
# docs/specs/SPEC-0045-spec-intake-secrets-preflight.md, TEST-001..006).
#
# Covers the never-echo secrets preflight helper (.aai/scripts/secrets-preflight.mjs)
# and its lean intake wiring (.aai/INTAKE_COMMON.md, .aai/INTAKE_CHANGE.prompt.md,
# .aai/INTAKE_ISSUE.prompt.md, .aai/templates/CHANGE_TEMPLATE.md,
# .aai/templates/ISSUE_TEMPLATE.md):
#   - TEST-001 (Spec-AC-01): classification matrix — env set/empty/unset,
#     JSON dotted key present/""/null/absent-key/absent-file/non-object-hop,
#     .env KEY=v/KEY=/absent -> exists/empty/missing; every run exits 0;
#     stdout is exactly one `ref status` line per check.
#   - TEST-002 (Spec-AC-02): never-echo matrix (security) — a sentinel value
#     planted in an env var, a JSON value, a .env value, and inside a
#     MALFORMED JSON file; combined stdout+stderr of every invocation shape
#     (success, parse-error, unreadable-file, usage-error, partial-degrade)
#     never contains the sentinel; parse/unreadable paths emit only the
#     fixed-string notes (never Node's raw SyntaxError text).
#   - TEST-003 (Spec-AC-01, Spec-AC-04): exit contract — no args / orphan
#     --key / unknown flag / .yaml file -> 2 with fixed messages; a run
#     whose statuses include `missing` still exits 0 (non-blocking posture).
#   - TEST-004 (Spec-AC-03, Spec-AC-04): canon grep contract — INTAKE_COMMON
#     SECRETS PREFLIGHT block names the script path, all three statuses, the
#     never-print rule, the skip rule, the non-blocking rule; CHANGE/ISSUE
#     SHARED POLICY lines name the block; prompt-diet guard rail (exactly
#     one `Read .aai/INTAKE_COMMON.md` per intake prompt) still holds.
#   - TEST-005 (Spec-AC-03): e2e dry-run (Seams 1+2) — the documented
#     --env/--file/--key invocation form is executed verbatim against real
#     fixtures; a DRAFT intake doc constructed per the block's instructions
#     passes strict docs-audit and records exists/missing without the
#     sentinel.
#   - TEST-006 (Spec-AC-05): additive/budget regression — repo-wide strict
#     docs-audit exits 0; the 8 INTAKE_* files stay <= 240 combined lines;
#     both templates keep every pre-change heading; test-aai-intake.sh
#     still exits 0.
#
# SPEC-0049 / ISSUE-0010 additions (quoting-aware `.env` multiline fidelity):
#   - TEST-007 (Spec-AC-01): a quoted multiline value's interior `KEY=`-shaped
#     lines are never read as top-level assignments — interior-only key ->
#     `missing`, a key shadowed by an interior fragment still resolves to its
#     real (later) top-level assignment, a plain key after the block is still
#     found, both `"..."` and `'...'` multiline forms are handled, and the
#     multiline key itself classifies `exists`.
#   - TEST-008 (Spec-AC-02): empty classification — `KEY=`, `KEY=""`,
#     `KEY=''`, and a real empty assignment shadowed by an earlier multiline
#     interior fragment all classify `empty`, never `exists`.
#   - TEST-009 (Spec-AC-03): adversarial never-echo on the new parser paths —
#     a sentinel inside a multiline interior line and inside an
#     unterminated-quote value never appears in combined stdout+stderr for
#     any invocation shape; every run exits 0.
#   - TEST-010 (Spec-AC-03): full-suite regression — TEST-001..006 re-run
#     individually through the aai-run-tests.sh wrapper and stay green.
#
# ISSUE-0013 / SPEC-0056 addition (unterminated-quote value classifies
# toward `missing`, safe direction):
#   - TEST-011 (Spec-AC-01, Spec-AC-02, Spec-AC-03): a target key whose
#     quoted value opens but never closes before EOF (bare `KEY="`@EOF,
#     non-empty `"`-interior@EOF, non-empty `'`-interior@EOF) classifies
#     `missing`, never `exists`; negative controls (properly-closed
#     multiline, `KEY=""`/`KEY=''`, unquoted `KEY=v`) prove no
#     over-correction; sentinel inside an unterminated value never leaks.
#   - TEST-009 was EDITED (single assertion): the UNTERMINATED status
#     assertion flips `exists` -> `missing` to match the new safe direction.
#
# Fixture diversity checklist (SPEC-0013 H7), mapped:
#   - degenerate/empty            -> empty JSON {} / empty .env file (TEST-001)
#   - zero-remainder               -> single-check invocation, exactly one
#                                      stdout line, nothing else (TEST-001)
#   - multi-source/multi-writer    -> multi-check invocation incl. duplicate
#                                      --env NAME (idempotent two lines) (TEST-001)
#   - mid-operation failure        -> one good --file + one malformed --file
#                                      in the SAME invocation; the malformed
#                                      file's failure degrades only its own
#                                      checks, the good file's checks are
#                                      unaffected (TEST-002)
#   - negative control              -> near-miss key names that must NOT
#                                      false-match (db.password_typo,
#                                      FOOBAR) (TEST-001)
#
# ALL fixtures are scratch temp-dir files (or a single ephemeral docs/issues/
# DRAFT deleted on exit for TEST-005). No real secret is ever used; every
# "secret" is a synthetic sentinel string that exists only for this run.
#
# bash 3.2 compatible (no ${var^^}, no declare -A). Run via
# .aai/scripts/aai-run-tests.sh per the LEARNED wrapper rule.
#
# Usage:
#   bash tests/skills/test-aai-secrets-preflight.sh            # run all tests
#   bash tests/skills/test-aai-secrets-preflight.sh test_002_never_echo_matrix
#                                                                # run one test
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-secrets-preflight"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

HELPER="$PROJECT_ROOT/.aai/scripts/secrets-preflight.mjs"
INTAKE_COMMON="$PROJECT_ROOT/.aai/INTAKE_COMMON.md"
INTAKE_CHANGE="$PROJECT_ROOT/.aai/INTAKE_CHANGE.prompt.md"
INTAKE_ISSUE="$PROJECT_ROOT/.aai/INTAKE_ISSUE.prompt.md"
CHANGE_TEMPLATE="$PROJECT_ROOT/.aai/templates/CHANGE_TEMPLATE.md"
ISSUE_TEMPLATE="$PROJECT_ROOT/.aai/templates/ISSUE_TEMPLATE.md"
DOCS_AUDIT="$PROJECT_ROOT/.aai/scripts/docs-audit.mjs"
INTAKE_TEST_SUITE="$SCRIPT_DIR/test-aai-intake.sh"
RUN_TESTS_SH="$PROJECT_ROOT/.aai/scripts/aai-run-tests.sh"
E2E_DRAFT="docs/issues/CHANGE-DRAFT-secrets-preflight-e2e-fixture.md"

INTAKE_FILES=(
  .aai/INTAKE_CHANGE.prompt.md
  .aai/INTAKE_HOTFIX.prompt.md
  .aai/INTAKE_ISSUE.prompt.md
  .aai/INTAKE_PRD.prompt.md
  .aai/INTAKE_RELEASE.prompt.md
  .aai/INTAKE_RESEARCH.prompt.md
  .aai/INTAKE_RFC.prompt.md
  .aai/INTAKE_TECHDEBT.prompt.md
)

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then
    echo "INFO: keeping fixture at $TEST_DIR"
  elif [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
  rm -f "$PROJECT_ROOT/$E2E_DRAFT"
}
trap cleanup EXIT

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  [[ -f "$INTAKE_COMMON" ]] || log_fail "INTAKE_COMMON.md not found: $INTAKE_COMMON"
  [[ -f "$INTAKE_CHANGE" ]] || log_fail "INTAKE_CHANGE.prompt.md not found: $INTAKE_CHANGE"
  [[ -f "$INTAKE_ISSUE" ]] || log_fail "INTAKE_ISSUE.prompt.md not found: $INTAKE_ISSUE"
  [[ -f "$CHANGE_TEMPLATE" ]] || log_fail "CHANGE_TEMPLATE.md not found: $CHANGE_TEMPLATE"
  [[ -f "$ISSUE_TEMPLATE" ]] || log_fail "ISSUE_TEMPLATE.md not found: $ISSUE_TEMPLATE"
  [[ -f "$DOCS_AUDIT" ]] || log_fail "docs-audit.mjs not found: $DOCS_AUDIT"
  [[ -f "$INTAKE_TEST_SUITE" ]] || log_fail "test-aai-intake.sh not found: $INTAKE_TEST_SUITE"
  [[ -f "$RUN_TESTS_SH" ]] || log_fail "aai-run-tests.sh not found: $RUN_TESTS_SH"
  # NOTE: HELPER is intentionally NOT required here — TEST-001..003 RED
  # naturally (invocation fails / wrong exits) while the script does not yet
  # exist, per the spec's RED-proof note.
  log_pass "Dependencies checked"
}

setup_fixture() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-secrets-preflight-test.XXXXXX")"
}

# Runs `node $HELPER <args...>`, redirecting stdout to $1 and stderr to $2
# separately. Echoes the exit code on stdout (nothing else). Never trips
# `set -e` regardless of the helper's exit code.
run_helper() {
  local outfile="$1" errfile="$2"
  shift 2
  local code=0
  node "$HELPER" "$@" > "$outfile" 2> "$errfile" || code=$?
  echo "$code"
}

assert_exit() {
  local desc="$1" expected="$2" actual="$3"
  [[ "$actual" == "$expected" ]] \
    || log_fail "$desc: expected exit $expected, got $actual"
}

assert_stdout_line() {
  local desc="$1" outfile="$2" expected_line="$3"
  grep -qxF "$expected_line" "$outfile" \
    || log_fail "$desc: expected stdout line '$expected_line' not found (got: $(cat "$outfile" 2>/dev/null))"
}

refute_stdout_line() {
  local desc="$1" outfile="$2" bad_line="$3"
  grep -qxF "$bad_line" "$outfile" \
    && log_fail "$desc: unexpected stdout line '$bad_line' present" || true
}

# --- TEST-001 (Spec-AC-01): classification matrix ---------------------------

test_001_classification_matrix() {
  log_info "Test: classification matrix env/json/.env -> exists/empty/missing; exit 0; one line per check (TEST-001)..."
  local f="$TEST_DIR"
  local out err code

  # --- env var checks: set / empty / unset / whitespace-only ---
  out="$f/t1-env-set.out"; err="$f/t1-env-set.err"
  code=$(SECRETS_PF_SET=hello run_helper "$out" "$err" --env SECRETS_PF_SET)
  assert_exit "env set" 0 "$code"
  assert_stdout_line "env set" "$out" "env:SECRETS_PF_SET exists"

  out="$f/t1-env-empty.out"; err="$f/t1-env-empty.err"
  code=$(SECRETS_PF_EMPTY='' run_helper "$out" "$err" --env SECRETS_PF_EMPTY)
  assert_exit "env empty" 0 "$code"
  assert_stdout_line "env empty" "$out" "env:SECRETS_PF_EMPTY empty"

  out="$f/t1-env-unset.out"; err="$f/t1-env-unset.err"
  unset SECRETS_PF_TOTALLY_UNSET_VAR_XYZ 2>/dev/null || true
  code=$(run_helper "$out" "$err" --env SECRETS_PF_TOTALLY_UNSET_VAR_XYZ)
  assert_exit "env unset" 0 "$code"
  assert_stdout_line "env unset" "$out" "env:SECRETS_PF_TOTALLY_UNSET_VAR_XYZ missing"

  out="$f/t1-env-ws.out"; err="$f/t1-env-ws.err"
  code=$(SECRETS_PF_WS='   ' run_helper "$out" "$err" --env SECRETS_PF_WS)
  assert_exit "env whitespace" 0 "$code"
  assert_stdout_line "env whitespace-only counts as exists (length semantics only)" "$out" "env:SECRETS_PF_WS exists"

  # --- JSON checks: exists / empty-string / null / absent-key / absent-file /
  #     non-object hop / non-string terminal (number) / negative control ---
  # NOTE: db.password_typo is deliberately ABSENT (not just present-with-null)
  # so the negative-control check below proves no near-miss/substring match.
  cat > "$f/config.json" <<JSON
{
  "db": {
    "password": "irrelevant-fixture-value",
    "empty_field": "",
    "null_field": null,
    "number_field": 42
  },
  "top": "a-plain-string"
}
JSON

  out="$f/t1-json-exists.out"; err="$f/t1-json-exists.err"
  code=$(run_helper "$out" "$err" --file "$f/config.json" --key db.password)
  assert_exit "json exists" 0 "$code"
  assert_stdout_line "json exists" "$out" "file:$f/config.json#db.password exists"

  out="$f/t1-json-empty.out"; err="$f/t1-json-empty.err"
  code=$(run_helper "$out" "$err" --file "$f/config.json" --key db.empty_field)
  assert_exit "json empty string" 0 "$code"
  assert_stdout_line "json empty string" "$out" "file:$f/config.json#db.empty_field empty"

  out="$f/t1-json-null.out"; err="$f/t1-json-null.err"
  code=$(run_helper "$out" "$err" --file "$f/config.json" --key db.null_field)
  assert_exit "json null -> empty" 0 "$code"
  assert_stdout_line "json null classifies as empty (explicit rule)" "$out" "file:$f/config.json#db.null_field empty"

  out="$f/t1-json-number.out"; err="$f/t1-json-number.err"
  code=$(run_helper "$out" "$err" --file "$f/config.json" --key db.number_field)
  assert_exit "json non-string terminal" 0 "$code"
  assert_stdout_line "json number coerces via length test -> exists" "$out" "file:$f/config.json#db.number_field exists"

  out="$f/t1-json-abskey.out"; err="$f/t1-json-abskey.err"
  code=$(run_helper "$out" "$err" --file "$f/config.json" --key db.absent_key)
  assert_exit "json absent key" 0 "$code"
  assert_stdout_line "json absent key" "$out" "file:$f/config.json#db.absent_key missing"

  out="$f/t1-json-absfile.out"; err="$f/t1-json-absfile.err"
  code=$(run_helper "$out" "$err" --file "$f/does-not-exist.json" --key db.password)
  assert_exit "json absent file" 0 "$code"
  assert_stdout_line "json absent file" "$out" "file:$f/does-not-exist.json#db.password missing"

  out="$f/t1-json-nonobj.out"; err="$f/t1-json-nonobj.err"
  code=$(run_helper "$out" "$err" --file "$f/config.json" --key top.nested)
  assert_exit "json dotted key traversing non-object" 0 "$code"
  assert_stdout_line "json dotted key through a string terminal -> missing" "$out" "file:$f/config.json#top.nested missing"

  # negative control: a near-miss key name that must NOT false-match db.password
  out="$f/t1-json-negctrl.out"; err="$f/t1-json-negctrl.err"
  code=$(run_helper "$out" "$err" --file "$f/config.json" --key db.password_typo)
  assert_exit "json negative control" 0 "$code"
  assert_stdout_line "near-miss key must not accidentally match db.password (negative control)" "$out" "file:$f/config.json#db.password_typo missing"

  # degenerate/empty: an empty JSON object
  printf '{}' > "$f/empty.json"
  out="$f/t1-json-degenerate.out"; err="$f/t1-json-degenerate.err"
  code=$(run_helper "$out" "$err" --file "$f/empty.json" --key any.key)
  assert_exit "json degenerate empty object" 0 "$code"
  assert_stdout_line "degenerate empty JSON object -> missing" "$out" "file:$f/empty.json#any.key missing"

  # --- .env checks: exists / empty / absent / export-quoted-empty / negative control ---
  cat > "$f/fixture.env" <<ENVV
FOO=bar
EMPTY_KEY=
export EXPORTED_KEY=exported-value
export QUOTED_EMPTY=""
ENVV

  out="$f/t1-envfile-exists.out"; err="$f/t1-envfile-exists.err"
  code=$(run_helper "$out" "$err" --file "$f/fixture.env" --key FOO)
  assert_exit ".env exists" 0 "$code"
  assert_stdout_line ".env KEY=v -> exists" "$out" "file:$f/fixture.env#FOO exists"

  out="$f/t1-envfile-empty.out"; err="$f/t1-envfile-empty.err"
  code=$(run_helper "$out" "$err" --file "$f/fixture.env" --key EMPTY_KEY)
  assert_exit ".env empty" 0 "$code"
  assert_stdout_line ".env KEY= -> empty" "$out" "file:$f/fixture.env#EMPTY_KEY empty"

  out="$f/t1-envfile-export.out"; err="$f/t1-envfile-export.err"
  code=$(run_helper "$out" "$err" --file "$f/fixture.env" --key EXPORTED_KEY)
  assert_exit ".env export KEY=v" 0 "$code"
  assert_stdout_line ".env export KEY=v -> exists" "$out" "file:$f/fixture.env#EXPORTED_KEY exists"

  out="$f/t1-envfile-qempty.out"; err="$f/t1-envfile-qempty.err"
  code=$(run_helper "$out" "$err" --file "$f/fixture.env" --key QUOTED_EMPTY)
  assert_exit ".env export KEY=\"\"" 0 "$code"
  assert_stdout_line "quote-stripped empty value -> empty" "$out" "file:$f/fixture.env#QUOTED_EMPTY empty"

  out="$f/t1-envfile-absent.out"; err="$f/t1-envfile-absent.err"
  code=$(run_helper "$out" "$err" --file "$f/fixture.env" --key ABSENT_KEY)
  assert_exit ".env absent key" 0 "$code"
  assert_stdout_line ".env absent key -> missing" "$out" "file:$f/fixture.env#ABSENT_KEY missing"

  # negative control: near-miss KEY name must not prefix-match FOO
  out="$f/t1-envfile-negctrl.out"; err="$f/t1-envfile-negctrl.err"
  code=$(run_helper "$out" "$err" --file "$f/fixture.env" --key FOOBAR)
  assert_exit ".env negative control" 0 "$code"
  assert_stdout_line "near-miss KEY must not prefix-match FOO (negative control)" "$out" "file:$f/fixture.env#FOOBAR missing"

  # degenerate/empty: empty .env file
  : > "$f/empty.env"
  out="$f/t1-envfile-degenerate.out"; err="$f/t1-envfile-degenerate.err"
  code=$(run_helper "$out" "$err" --file "$f/empty.env" --key ANY_KEY)
  assert_exit ".env degenerate empty file" 0 "$code"
  assert_stdout_line "degenerate empty .env file -> missing" "$out" "file:$f/empty.env#ANY_KEY missing"

  # zero-remainder: a single-check invocation produces EXACTLY one stdout
  # line, nothing else.
  out="$f/t1-zero-remainder.out"; err="$f/t1-zero-remainder.err"
  code=$(SECRETS_PF_SOLO=x run_helper "$out" "$err" --env SECRETS_PF_SOLO)
  assert_exit "zero-remainder single check" 0 "$code"
  local nlines
  nlines=$(wc -l < "$out" | tr -d ' ')
  [[ "$nlines" == "1" ]] \
    || log_fail "zero-remainder: expected exactly 1 stdout line, got $nlines"

  # multi-source/multi-writer: multiple checks incl. a duplicate --env NAME
  # in ONE invocation -> two independent (idempotent) lines.
  out="$f/t1-multi.out"; err="$f/t1-multi.err"
  code=$(SECRETS_PF_MULTI=y run_helper "$out" "$err" \
    --env SECRETS_PF_MULTI --env SECRETS_PF_MULTI \
    --file "$f/config.json" --key db.password \
    --file "$f/fixture.env" --key FOO)
  assert_exit "multi-writer invocation" 0 "$code"
  nlines=$(wc -l < "$out" | tr -d ' ')
  [[ "$nlines" == "4" ]] \
    || log_fail "multi-writer: expected exactly 4 stdout lines, got $nlines"
  local dup_count
  dup_count=$(grep -cxF "env:SECRETS_PF_MULTI exists" "$out")
  [[ "$dup_count" == "2" ]] \
    || log_fail "multi-writer: duplicate --env NAME must yield two independent lines, got $dup_count"

  log_pass "Classification matrix: env/json/.env -> exists/empty/missing, exit 0, one line per check (TEST-001)"
}

# --- TEST-002 (Spec-AC-02): never-echo matrix (security, RED-first) --------

test_002_never_echo_matrix() {
  log_info "Test: never-echo matrix (security) — sentinel in env/json/.env/malformed-json never leaks; parse/unreadable paths emit fixed-string notes only (TEST-002)..."
  local f="$TEST_DIR"
  local sentinel="SENTINEL_9f3a7c2e1b4d_do_not_leak"
  local out err code combined

  # --- (a) success arm: sentinel planted in env, JSON, and .env, all in ONE
  #     invocation (fixture proof over every "found" output path). ---
  cat > "$f/sentinel-good.json" <<JSON
{"cred": {"api_key": "$sentinel"}}
JSON
  cat > "$f/sentinel-good.env" <<ENVV
API_KEY=$sentinel
ENVV

  out="$f/t2-success.out"; err="$f/t2-success.err"
  code=$(SECRETS_PF_SENTINEL="$sentinel" run_helper "$out" "$err" \
    --env SECRETS_PF_SENTINEL \
    --file "$f/sentinel-good.json" --key cred.api_key \
    --file "$f/sentinel-good.env" --key API_KEY)
  assert_exit "success arm" 0 "$code"
  assert_stdout_line "success arm env status" "$out" "env:SECRETS_PF_SENTINEL exists"
  assert_stdout_line "success arm json status" "$out" "file:$f/sentinel-good.json#cred.api_key exists"
  assert_stdout_line "success arm .env status" "$out" "file:$f/sentinel-good.env#API_KEY exists"
  combined="$(cat "$out" "$err" 2>/dev/null)"
  [[ "$combined" != *"$sentinel"* ]] \
    || log_fail "TEST-002 success arm: sentinel leaked into combined stdout+stderr"

  # --- (b) parse-error arm: MALFORMED JSON containing the sentinel. Node's
  #     own JSON.parse SyntaxError can quote file content — the helper must
  #     catch it and print ONLY the fixed note, never err.message. ---
  cat > "$f/sentinel-malformed.json" <<JSON
{"cred": "$sentinel", invalid syntax here
JSON
  out="$f/t2-parse.out"; err="$f/t2-parse.err"
  code=$(run_helper "$out" "$err" --file "$f/sentinel-malformed.json" --key cred)
  assert_exit "parse-error arm (missing is a classification, not a usage error)" 0 "$code"
  assert_stdout_line "parse-error arm status" "$out" "file:$f/sentinel-malformed.json#cred missing"
  combined="$(cat "$out" "$err" 2>/dev/null)"
  [[ "$combined" != *"$sentinel"* ]] \
    || log_fail "TEST-002 parse-error arm: sentinel leaked into combined stdout+stderr"
  grep -qF "parse failed" "$err" \
    || log_fail "TEST-002 parse-error arm: missing fixed 'parse failed' note"
  if grep -qiE "unexpected token|position [0-9]|SyntaxError|at JSON" "$err"; then
    log_fail "TEST-002 parse-error arm: raw Node error text leaked (err.message not suppressed)"
  fi

  # --- (c) unreadable-file arm: co-located with a SEPARATE successful
  #     sentinel-bearing env check in the SAME invocation, proving the
  #     unrelated file failure does not disturb or leak the other check. ---
  out="$f/t2-unreadable.out"; err="$f/t2-unreadable.err"
  code=$(SECRETS_PF_SENTINEL2="$sentinel" run_helper "$out" "$err" \
    --env SECRETS_PF_SENTINEL2 \
    --file "$f/does-not-exist-unreadable.json" --key any.key)
  assert_exit "unreadable-file arm" 0 "$code"
  assert_stdout_line "unreadable-file arm env status" "$out" "env:SECRETS_PF_SENTINEL2 exists"
  assert_stdout_line "unreadable-file arm file status" "$out" "file:$f/does-not-exist-unreadable.json#any.key missing"
  combined="$(cat "$out" "$err" 2>/dev/null)"
  [[ "$combined" != *"$sentinel"* ]] \
    || log_fail "TEST-002 unreadable-file arm: sentinel leaked into combined stdout+stderr"
  grep -qF "unreadable" "$err" \
    || log_fail "TEST-002 unreadable-file arm: missing fixed 'unreadable' note"

  # --- (d) usage-error arm: sentinel present in the process environment
  #     (unrelated to the malformed request) must never appear even on a
  #     hard usage-error exit — proves no env-dump / debug leakage. ---
  out="$f/t2-usage.out"; err="$f/t2-usage.err"
  code=$(SECRETS_PF_SENTINEL3="$sentinel" run_helper "$out" "$err" --key orphan.key)
  assert_exit "usage-error arm" 2 "$code"
  combined="$(cat "$out" "$err" 2>/dev/null)"
  [[ "$combined" != *"$sentinel"* ]] \
    || log_fail "TEST-002 usage-error arm: sentinel leaked into combined stdout+stderr"

  # --- mid-operation-failure fixture (diversity checklist): ONE good file +
  #     ONE malformed file in the SAME invocation. The malformed file's
  #     failure must degrade only ITS OWN checks (partial degrade), never
  #     abort or corrupt the good file's checks. ---
  out="$f/t2-partial.out"; err="$f/t2-partial.err"
  code=$(run_helper "$out" "$err" \
    --file "$f/sentinel-good.json" --key cred.api_key \
    --file "$f/sentinel-malformed.json" --key cred)
  assert_exit "partial-degrade arm" 0 "$code"
  assert_stdout_line "partial-degrade good-file status unaffected" "$out" "file:$f/sentinel-good.json#cred.api_key exists"
  assert_stdout_line "partial-degrade bad-file status degrades to missing" "$out" "file:$f/sentinel-malformed.json#cred missing"
  combined="$(cat "$out" "$err" 2>/dev/null)"
  [[ "$combined" != *"$sentinel"* ]] \
    || log_fail "TEST-002 partial-degrade arm: sentinel leaked into combined stdout+stderr"

  log_pass "Never-echo matrix: sentinel absent from all 5 invocation shapes; parse/unreadable notes are fixed strings only (TEST-002)"
}

# --- TEST-003 (Spec-AC-01, Spec-AC-04): exit contract -----------------------

test_003_exit_contract() {
  log_info "Test: exit contract — no args/orphan --key/unknown flag/.yaml -> 2 with fixed messages; missing-only run still exits 0 (TEST-003)..."
  local f="$TEST_DIR"
  local out err code

  out="$f/t3-noargs.out"; err="$f/t3-noargs.err"
  code=$(run_helper "$out" "$err")
  assert_exit "no args" 2 "$code"

  out="$f/t3-orphankey.out"; err="$f/t3-orphankey.err"
  code=$(run_helper "$out" "$err" --key orphan.key)
  assert_exit "--key without preceding --file" 2 "$code"

  out="$f/t3-unknown.out"; err="$f/t3-unknown.err"
  code=$(run_helper "$out" "$err" --bogus-flag foo)
  assert_exit "unknown flag" 2 "$code"

  cat > "$f/config.yaml" <<'YAML'
db:
  password: whatever
YAML
  out="$f/t3-yaml.out"; err="$f/t3-yaml.err"
  code=$(run_helper "$out" "$err" --file "$f/config.yaml" --key db.password)
  assert_exit ".yaml file rejected as unsupported format" 2 "$code"
  grep -qiE "unsupported" "$err" \
    || log_fail "TEST-003: .yaml rejection must state 'unsupported' in a fixed message"
  grep -qF ".json" "$err" \
    || log_fail "TEST-003: unsupported-format message must name the supported formats"

  # a run whose statuses include 'missing' still exits 0 (non-blocking posture)
  out="$f/t3-missingok.out"; err="$f/t3-missingok.err"
  unset SECRETS_PF_DEFINITELY_UNSET_VAR_XYZ 2>/dev/null || true
  code=$(run_helper "$out" "$err" --env SECRETS_PF_DEFINITELY_UNSET_VAR_XYZ)
  assert_exit "missing status still exits 0 (non-blocking)" 0 "$code"
  assert_stdout_line "missing status line" "$out" "env:SECRETS_PF_DEFINITELY_UNSET_VAR_XYZ missing"

  log_pass "Exit contract: usage errors -> 2 with fixed messages; missing status -> 0 (TEST-003)"
}

# --- TEST-004 (Spec-AC-03, Spec-AC-04): canon grep contract ------------------

test_004_canon_grep_contract() {
  log_info "Test: canon grep contract — INTAKE_COMMON SECRETS PREFLIGHT block + CHANGE/ISSUE policy-line wiring + prompt-diet guard rails hold (TEST-004)..."

  grep -qF "## SECRETS PREFLIGHT (CHANGE-0034)" "$INTAKE_COMMON" \
    || log_fail "TEST-004: INTAKE_COMMON.md missing '## SECRETS PREFLIGHT (CHANGE-0034)' heading"
  grep -qF ".aai/scripts/secrets-preflight.mjs" "$INTAKE_COMMON" \
    || log_fail "TEST-004: SECRETS PREFLIGHT block must name the script path"
  grep -qF "exists" "$INTAKE_COMMON" || log_fail "TEST-004: block must name status 'exists'"
  grep -qF "empty" "$INTAKE_COMMON" || log_fail "TEST-004: block must name status 'empty'"
  grep -qF "missing" "$INTAKE_COMMON" || log_fail "TEST-004: block must name status 'missing'"
  grep -qiE "never (print|cat|echo|log)" "$INTAKE_COMMON" \
    || log_fail "TEST-004: block must state the never-print/never-echo rule"
  grep -qiE "zero extra question" "$INTAKE_COMMON" \
    || log_fail "TEST-004: block must state the zero-extra-questions skip rule"
  grep -qiE "never block|does not block|non-blocking" "$INTAKE_COMMON" \
    || log_fail "TEST-004: block must state the never-blocks-saving rule"

  grep -qF "SECRETS PREFLIGHT" "$INTAKE_CHANGE" \
    || log_fail "TEST-004: INTAKE_CHANGE.prompt.md SHARED POLICY line must name the SECRETS PREFLIGHT block"
  grep -qF "SECRETS PREFLIGHT" "$INTAKE_ISSUE" \
    || log_fail "TEST-004: INTAKE_ISSUE.prompt.md SHARED POLICY line must name the SECRETS PREFLIGHT block"

  # Guard rail (prompt-diet TEST-001): exactly one Read .aai/INTAKE_COMMON.md
  # reference per intake prompt — must still hold after the in-place edit.
  local n rel
  for rel in "${INTAKE_FILES[@]}"; do
    n=$(grep -cF "Read .aai/INTAKE_COMMON.md" "$PROJECT_ROOT/$rel" 2>/dev/null || true)
    [[ "$n" == "1" ]] \
      || log_fail "TEST-004: $rel must reference INTAKE_COMMON.md exactly once (got $n)"
  done

  log_pass "Canon grep contract: SECRETS PREFLIGHT block + policy-line wiring + guard rails hold (TEST-004)"
}

# --- TEST-005 (Spec-AC-03): e2e dry-run (Seams 1+2) --------------------------

test_005_e2e_dry_run() {
  log_info "Test: e2e dry-run — documented --env/--file/--key form matches real grammar; DRAFT doc records statuses per block instructions; strict audit passes; no sentinel (TEST-005)..."
  local f="$TEST_DIR"
  local sentinel="SENTINEL_e2e_9f3a7c2e_do_not_leak"

  # Seam 1: the block documents the literal invocation form the grammar accepts.
  grep -qF -- "--env NAME" "$INTAKE_COMMON" \
    || log_fail "TEST-005: INTAKE_COMMON.md must document the literal --env NAME invocation form"
  grep -qF -- "--file" "$INTAKE_COMMON" \
    || log_fail "TEST-005: INTAKE_COMMON.md must document the --file invocation form"
  grep -qF -- "--key" "$INTAKE_COMMON" \
    || log_fail "TEST-005: INTAKE_COMMON.md must document the --key invocation form"

  # Execute that documented form verbatim against real fixtures.
  cat > "$f/e2e-demo.json" <<JSON
{"api": {"token": "$sentinel"}}
JSON
  local out="$f/t5.out" err="$f/t5.err" code
  unset SECRETS_PF_E2E_MISSING 2>/dev/null || true
  code=$(SECRETS_PF_E2E_DEMO="$sentinel" run_helper "$out" "$err" \
    --env SECRETS_PF_E2E_DEMO --env SECRETS_PF_E2E_MISSING \
    --file "$f/e2e-demo.json" --key api.token)
  assert_exit "e2e documented invocation" 0 "$code"
  assert_stdout_line "e2e env exists status" "$out" "env:SECRETS_PF_E2E_DEMO exists"
  assert_stdout_line "e2e env missing status" "$out" "env:SECRETS_PF_E2E_MISSING missing"
  assert_stdout_line "e2e file exists status" "$out" "file:$f/e2e-demo.json#api.token exists"

  # Construct the artifact exactly per INTAKE_COMMON.md DURABLE DOC IDENTITY +
  # SECRETS PREFLIGHT recorded-results instructions (template's new bullet
  # under Constraints/Risks).
  cat > "$PROJECT_ROOT/$E2E_DRAFT" <<EOF
---
id: secrets-preflight-e2e-fixture
type: change
number: null
status: draft
links:
  pr: []
  commits: []
---

# Change — Secrets preflight e2e dry-run artifact (TEST-005)

## Summary
- Synthetic intake artifact produced per .aai/INTAKE_COMMON.md SECRETS PREFLIGHT instructions.

## Motivation / Business Value
- Proves the intake wiring records preflight results without leaking values.

## Scope
- In scope: this test artifact only.
- Out of scope: everything else.

## Affected Area
- tests/skills/test-aai-secrets-preflight.sh (TEST-005 fixture).

## Desired Behavior (To-Be)
- The strict docs audit accepts this artifact.

## Acceptance Criteria
- AC-001: docs-audit --check --strict --no-event --path exits 0 on this file.

## Verification
- node .aai/scripts/docs-audit.mjs --check --strict --no-event --path <this file>

## Constraints / Risks
- Secrets preflight: env:SECRETS_PF_E2E_DEMO exists; env:SECRETS_PF_E2E_MISSING missing; file:e2e-demo.json#api.token exists

## Notes
- Ephemeral fixture; never committed.
EOF

  if node "$DOCS_AUDIT" --check --strict --no-event --path "$E2E_DRAFT" >/dev/null 2>&1; then
    log_pass "TEST-005a e2e dry-run artifact passes strict audit"
  else
    log_fail "TEST-005: e2e dry-run artifact fails strict audit"
  fi

  grep -qF "exists" "$PROJECT_ROOT/$E2E_DRAFT" \
    || log_fail "TEST-005: doc must record an 'exists' status"
  grep -qF "missing" "$PROJECT_ROOT/$E2E_DRAFT" \
    || log_fail "TEST-005: doc must record a 'missing' status"
  if grep -qF "$sentinel" "$PROJECT_ROOT/$E2E_DRAFT"; then
    log_fail "TEST-005: sentinel leaked into the saved intake doc"
  fi

  rm -f "$PROJECT_ROOT/$E2E_DRAFT"
  log_pass "E2e dry-run: documented invocation form matches real grammar; recorded doc passes strict audit; no sentinel (TEST-005)"
}

# --- TEST-006 (Spec-AC-05): additive/budget regression (RED-waiver) --------

test_006_additive_budget_regression() {
  log_info "Test: additive/budget regression — strict audit 0; intake line budget <=240; template headings intact; test-aai-intake.sh green (TEST-006)..."

  local audit_log="$TEST_DIR/docs-audit.log"
  (node "$DOCS_AUDIT" --check --strict --no-event > "$audit_log" 2>&1) \
    || log_fail "TEST-006: docs-audit --check --strict --no-event must exit 0: $(tail -20 "$audit_log")"

  local total
  total=$(cat "${INTAKE_FILES[@]}" | wc -l | tr -d ' ')
  [[ "$total" -le 240 ]] \
    || log_fail "TEST-006: 8 INTAKE_* files total $total lines (> 240 cap)"

  local h
  local change_headings=(
    "## Summary" "## Motivation / Business Value" "## Scope" "## Affected Area"
    "## Desired Behavior (To-Be)" "## Acceptance Criteria" "## Verification"
    "## Constraints / Risks" "## Notes"
  )
  for h in "${change_headings[@]}"; do
    grep -qF "$h" "$CHANGE_TEMPLATE" \
      || log_fail "TEST-006: CHANGE_TEMPLATE.md missing pre-existing heading '$h'"
  done
  local issue_headings=(
    "## Summary" "## Type" "## Impact" "## Current Behavior" "## Expected Behavior"
    "## Steps to Reproduce (if applicable)" "## Verification" "## Constraints / Risks" "## Notes"
  )
  for h in "${issue_headings[@]}"; do
    grep -qF "$h" "$ISSUE_TEMPLATE" \
      || log_fail "TEST-006: ISSUE_TEMPLATE.md missing pre-existing heading '$h'"
  done

  local intake_regress="$TEST_DIR/intake-regress.log"
  (AAI_TEST_TIMEOUT="${AAI_TEST_TIMEOUT:-600}" \
    "$RUN_TESTS_SH" bash "$INTAKE_TEST_SUITE" > "$intake_regress" 2>&1) \
    || log_fail "TEST-006: tests/skills/test-aai-intake.sh must still exit 0: $(tail -20 "$intake_regress")"

  log_pass "Additive/budget regression: strict audit clean, line budget held, template headings intact, intake suite green (TEST-006)"
}

# --- TEST-007 (Spec-AC-01): quoting-aware multiline scan --------------------

test_007_multiline_quoting_aware() {
  log_info "Test: quoted multiline value's interior KEY= lines are not top-level assignments (TEST-007)..."
  local f="$TEST_DIR"
  local out err code

  cat > "$f/multiline.env" <<'ENVV'
CERT_SENTINEL_KEY="-----BEGIN CERTIFICATE-----
INTERIOR_ONLY_KEY=fragment-should-not-count-as-assignment
SHADOWED_KEY=interior-fragment-should-not-win
-----END CERTIFICATE-----"
SHADOWED_KEY=real-later-value
AFTER_BLOCK=found-me
TOKEN_SINGLE='-----BEGIN TOKEN-----
SINGLE_INTERIOR_KEY=also-should-not-count
-----END TOKEN-----'
ENVV

  # interior-only key (appears ONLY inside a quoted multiline block) -> missing
  out="$f/t7-interior-only.out"; err="$f/t7-interior-only.err"
  code=$(run_helper "$out" "$err" --file "$f/multiline.env" --key INTERIOR_ONLY_KEY)
  assert_exit "interior-only key" 0 "$code"
  assert_stdout_line "interior-only key (double-quoted block) must classify missing, not exists" \
    "$out" "file:$f/multiline.env#INTERIOR_ONLY_KEY missing"

  # shadowed key: an interior fragment shares the name, but a genuine
  # top-level assignment appears after the block -> the real one is found
  # (both non-empty here; TEST-008 covers the empty-shadow RED-proof).
  out="$f/t7-shadowed.out"; err="$f/t7-shadowed.err"
  code=$(run_helper "$out" "$err" --file "$f/multiline.env" --key SHADOWED_KEY)
  assert_exit "shadowed key resolves to real later assignment" 0 "$code"
  assert_stdout_line "shadowed key -> real later (non-empty) assignment classifies exists" \
    "$out" "file:$f/multiline.env#SHADOWED_KEY exists"

  # plain key after the multiline block -> scan resumes correctly, still found
  out="$f/t7-after.out"; err="$f/t7-after.err"
  code=$(run_helper "$out" "$err" --file "$f/multiline.env" --key AFTER_BLOCK)
  assert_exit "key after multiline block" 0 "$code"
  assert_stdout_line "key after multiline block is still found" \
    "$out" "file:$f/multiline.env#AFTER_BLOCK exists"

  # the multiline key itself (non-empty content) -> exists ("..." form)
  out="$f/t7-multiline-key.out"; err="$f/t7-multiline-key.err"
  code=$(run_helper "$out" "$err" --file "$f/multiline.env" --key CERT_SENTINEL_KEY)
  assert_exit "multiline key itself (double-quoted)" 0 "$code"
  assert_stdout_line "multiline key itself classifies exists" \
    "$out" "file:$f/multiline.env#CERT_SENTINEL_KEY exists"

  # '...' single-quoted multiline form: interior fragment -> missing
  out="$f/t7-single-interior.out"; err="$f/t7-single-interior.err"
  code=$(run_helper "$out" "$err" --file "$f/multiline.env" --key SINGLE_INTERIOR_KEY)
  assert_exit "interior key inside single-quoted multiline block" 0 "$code"
  assert_stdout_line "interior key inside '...' block must classify missing, not exists" \
    "$out" "file:$f/multiline.env#SINGLE_INTERIOR_KEY missing"

  # '...' single-quoted multiline key itself -> exists
  out="$f/t7-token-single.out"; err="$f/t7-token-single.err"
  code=$(run_helper "$out" "$err" --file "$f/multiline.env" --key TOKEN_SINGLE)
  assert_exit "single-quoted multiline key itself" 0 "$code"
  assert_stdout_line "single-quoted multiline key itself classifies exists" \
    "$out" "file:$f/multiline.env#TOKEN_SINGLE exists"

  log_pass "Quoting-aware multiline scan: interior lines never satisfy a lookup, shadowed/after/multiline keys resolve correctly, both quote forms handled (TEST-007)"
}

# --- TEST-008 (Spec-AC-02): empty & quoted-empty & shadowed-empty ----------

test_008_empty_and_quoted_empty() {
  log_info "Test: empty classification incl. quoted-empty and multiline-shadowed-empty (TEST-008)..."
  local f="$TEST_DIR"
  local out err code

  cat > "$f/empties.env" <<'ENVV'
PLAIN_EMPTY=
DOUBLE_QUOTED_EMPTY=""
SINGLE_QUOTED_EMPTY=''
CERT_SHADOW="-----BEGIN CERTIFICATE-----
SHADOWED_PLAIN_EMPTY=interior-fragment-nonempty-should-not-win
-----END CERTIFICATE-----"
SHADOWED_PLAIN_EMPTY=
TOKEN_SHADOW='-----BEGIN TOKEN-----
SHADOWED_QUOTED_EMPTY=interior-fragment-nonempty-should-not-win
-----END TOKEN-----'
SHADOWED_QUOTED_EMPTY=''
ENVV

  out="$f/t8-plain.out"; err="$f/t8-plain.err"
  code=$(run_helper "$out" "$err" --file "$f/empties.env" --key PLAIN_EMPTY)
  assert_exit "KEY= plain empty" 0 "$code"
  assert_stdout_line "KEY= classifies empty" "$out" "file:$f/empties.env#PLAIN_EMPTY empty"

  out="$f/t8-dquote.out"; err="$f/t8-dquote.err"
  code=$(run_helper "$out" "$err" --file "$f/empties.env" --key DOUBLE_QUOTED_EMPTY)
  assert_exit 'KEY="" double-quoted empty' 0 "$code"
  assert_stdout_line 'KEY="" classifies empty' "$out" "file:$f/empties.env#DOUBLE_QUOTED_EMPTY empty"

  out="$f/t8-squote.out"; err="$f/t8-squote.err"
  code=$(run_helper "$out" "$err" --file "$f/empties.env" --key SINGLE_QUOTED_EMPTY)
  assert_exit "KEY='' single-quoted empty" 0 "$code"
  assert_stdout_line "KEY='' classifies empty" "$out" "file:$f/empties.env#SINGLE_QUOTED_EMPTY empty"

  # RED-gating arm: a real plain-empty assignment shadowed by an earlier
  # double-quoted multiline block's non-empty interior fragment -> empty,
  # never exists (the pre-fix first-match parser reports exists here).
  out="$f/t8-shadow-plain.out"; err="$f/t8-shadow-plain.err"
  code=$(run_helper "$out" "$err" --file "$f/empties.env" --key SHADOWED_PLAIN_EMPTY)
  assert_exit "multiline-shadowed plain-empty" 0 "$code"
  assert_stdout_line "real empty assignment shadowed by interior fragment must classify empty, not exists" \
    "$out" "file:$f/empties.env#SHADOWED_PLAIN_EMPTY empty"

  # RED-gating arm: a real quoted-empty ('') assignment shadowed by an
  # earlier single-quoted multiline block's non-empty interior fragment.
  out="$f/t8-shadow-quoted.out"; err="$f/t8-shadow-quoted.err"
  code=$(run_helper "$out" "$err" --file "$f/empties.env" --key SHADOWED_QUOTED_EMPTY)
  assert_exit "multiline-shadowed quoted-empty ('')" 0 "$code"
  assert_stdout_line "real KEY='' assignment shadowed by interior fragment must classify empty, not exists" \
    "$out" "file:$f/empties.env#SHADOWED_QUOTED_EMPTY empty"

  log_pass "Empty classification: plain/double/single-quoted empty and both multiline-shadowed-empty arms all classify empty, never exists (TEST-008)"
}

# --- TEST-009 (Spec-AC-03): adversarial never-echo on new paths ------------

test_009_never_echo_multiline() {
  log_info "Test: never-echo on new parser paths — sentinel inside a multiline interior line and an unterminated-quote value never leaks (TEST-009)..."
  local f="$TEST_DIR"
  local sentinel="SENTINEL_ml_7d2c9a1f_do_not_leak"
  local out err code combined

  cat > "$f/never-echo.env" <<ENVV
MULTILINE_WITH_SENTINEL="-----BEGIN CERT-----
INTERIOR_KEY=$sentinel
-----END CERT-----"
AFTER_MULTILINE=found-me
UNTERMINATED="unterminated-$sentinel-to-eof
ENVV

  out="$f/t9.out"; err="$f/t9.err"
  code=$(run_helper "$out" "$err" \
    --file "$f/never-echo.env" --key MULTILINE_WITH_SENTINEL \
    --file "$f/never-echo.env" --key INTERIOR_KEY \
    --file "$f/never-echo.env" --key AFTER_MULTILINE \
    --file "$f/never-echo.env" --key UNTERMINATED)
  assert_exit "never-echo multiline/unterminated invocation" 0 "$code"
  assert_stdout_line "multiline key (contains sentinel) classifies exists" \
    "$out" "file:$f/never-echo.env#MULTILINE_WITH_SENTINEL exists"
  assert_stdout_line "interior key (sentinel-shaped fragment) classifies missing" \
    "$out" "file:$f/never-echo.env#INTERIOR_KEY missing"
  assert_stdout_line "later key after the block is found" \
    "$out" "file:$f/never-echo.env#AFTER_MULTILINE exists"
  assert_stdout_line "unterminated-quote key (consumed to EOF, non-empty) classifies missing (ISSUE-0013 safe direction)" \
    "$out" "file:$f/never-echo.env#UNTERMINATED missing"
  combined="$(cat "$out" "$err" 2>/dev/null)"
  [[ "$combined" != *"$sentinel"* ]] \
    || log_fail "TEST-009: sentinel leaked into combined stdout+stderr on a new parser path"

  log_pass "Never-echo on new paths: sentinel absent from multiline interior, multiline key, and unterminated-quote invocations; all exit 0 (TEST-009)"
}

# --- TEST-010 (Spec-AC-03): full-suite regression ---------------------------

test_010_full_suite_regression() {
  log_info "Test: TEST-001..006 re-run individually via aai-run-tests.sh wrapper, unchanged and green (TEST-010)..."
  local t log_path
  local regression_tests=(
    test_001_classification_matrix
    test_002_never_echo_matrix
    test_003_exit_contract
    test_004_canon_grep_contract
    test_005_e2e_dry_run
    test_006_additive_budget_regression
  )
  for t in "${regression_tests[@]}"; do
    log_path="$TEST_DIR/t10-$t.log"
    (AAI_TEST_TIMEOUT="${AAI_TEST_TIMEOUT:-600}" \
      "$RUN_TESTS_SH" bash "$PROJECT_ROOT/tests/skills/test-aai-secrets-preflight.sh" "$t" \
      > "$log_path" 2>&1) \
      || log_fail "TEST-010: $t must still exit 0 under aai-run-tests.sh: $(tail -20 "$log_path")"
  done

  log_pass "Full-suite regression: TEST-001..006 unchanged and green via aai-run-tests.sh wrapper (TEST-010)"
}

# --- TEST-011 (Spec-AC-01, Spec-AC-02, Spec-AC-03): unterminated-quote
#     safe direction (ISSUE-0013 / SPEC-0056) -----------------------------

test_011_unterminated_quote_safe_direction() {
  log_info "Test: unterminated-quote value classifies missing (safe direction); negative controls prove no over-correction (TEST-011)..."
  local f="$TEST_DIR"
  local sentinel="SENTINEL_ut_3e8f1a2c_do_not_leak"
  local out err code combined

  # Fixture diversity checklist (SPEC-0013 H7), mapped for this narrow,
  # single-classifier-branch fix (no file-load/multi-writer surface is
  # touched — that is already covered by TEST-002):
  #   - degenerate/empty  -> (a) bare KEY="@EOF: the smallest possible
  #                          unterminated value (zero interior bytes).
  #   - zero-remainder     -> the properly-closed multiline negative control
  #                          below: nothing left ambiguous once a real close
  #                          char is found.
  #   - multi-source/multi-writer -> N/A; scope is one classifier branch in
  #                          one file-read path (spec Scope: single surface).
  #   - mid-operation failure -> N/A; no file-load/parse failure path is
  #                          touched by this fix (unchanged, see TEST-002).
  #   - negative control   -> four arms below (properly-closed multiline,
  #                          both quoted-empty forms, unquoted plain value).

  # --- unterminated arms: each lives in its OWN file. An unterminated value
  #     consumes to EOF (SPEC-0049), so nothing meaningful could follow it in
  #     the same file. Each must classify missing, never exists/empty. ---

  # (a) bare KEY="@EOF -- quote opens, nothing else, file ends immediately.
  printf 'BARE_EOF="\n' > "$f/t11-bare-eof.env"
  out="$f/t11-bare.out"; err="$f/t11-bare.err"
  code=$(run_helper "$out" "$err" --file "$f/t11-bare-eof.env" --key BARE_EOF)
  assert_exit "bare unterminated quote at EOF" 0 "$code"
  assert_stdout_line "bare KEY=\"@EOF must classify missing (unterminated safe direction), never exists" \
    "$out" "file:$f/t11-bare-eof.env#BARE_EOF missing"

  # (b) non-empty double-quoted interior running to EOF, never closed.
  cat > "$f/t11-dquote-eof.env" <<ENVV
DQUOTE_INTERIOR="unterminated-$sentinel-to-eof
ENVV
  out="$f/t11-dquote.out"; err="$f/t11-dquote.err"
  code=$(run_helper "$out" "$err" --file "$f/t11-dquote-eof.env" --key DQUOTE_INTERIOR)
  assert_exit "non-empty double-quoted unterminated interior to EOF" 0 "$code"
  assert_stdout_line "non-empty \"-interior@EOF must classify missing, never exists" \
    "$out" "file:$f/t11-dquote-eof.env#DQUOTE_INTERIOR missing"
  combined="$(cat "$out" "$err" 2>/dev/null)"
  [[ "$combined" != *"$sentinel"* ]] \
    || log_fail "TEST-011: sentinel leaked into combined stdout+stderr on the unterminated double-quote path"

  # (c) non-empty single-quoted interior running to EOF, never closed.
  cat > "$f/t11-squote-eof.env" <<ENVV
SQUOTE_INTERIOR='unterminated-$sentinel-to-eof
ENVV
  out="$f/t11-squote.out"; err="$f/t11-squote.err"
  code=$(run_helper "$out" "$err" --file "$f/t11-squote-eof.env" --key SQUOTE_INTERIOR)
  assert_exit "non-empty single-quoted unterminated interior to EOF" 0 "$code"
  assert_stdout_line "non-empty '-interior@EOF must classify missing, never exists" \
    "$out" "file:$f/t11-squote-eof.env#SQUOTE_INTERIOR missing"
  combined="$(cat "$out" "$err" 2>/dev/null)"
  [[ "$combined" != *"$sentinel"* ]] \
    || log_fail "TEST-011: sentinel leaked into combined stdout+stderr on the unterminated single-quote path"

  # --- negative controls: properly-closed values and unquoted values must
  #     NOT be over-corrected toward missing. ---
  cat > "$f/t11-negctrl.env" <<'ENVV'
PROPER_MULTILINE="-----BEGIN CERTIFICATE-----
middle-line-of-cert
-----END CERTIFICATE-----"
DQUOTE_EMPTY=""
SQUOTE_EMPTY=''
UNQUOTED_PLAIN=plain-unquoted-value
ENVV

  out="$f/t11-proper-multiline.out"; err="$f/t11-proper-multiline.err"
  code=$(run_helper "$out" "$err" --file "$f/t11-negctrl.env" --key PROPER_MULTILINE)
  assert_exit "properly-closed multiline negative control" 0 "$code"
  assert_stdout_line "properly-closed multiline (END line bears close char) stays exists, not over-corrected" \
    "$out" "file:$f/t11-negctrl.env#PROPER_MULTILINE exists"

  out="$f/t11-dquote-empty.out"; err="$f/t11-dquote-empty.err"
  code=$(run_helper "$out" "$err" --file "$f/t11-negctrl.env" --key DQUOTE_EMPTY)
  assert_exit 'quoted-empty "" negative control' 0 "$code"
  assert_stdout_line 'KEY="" (closed, quoted-empty) stays empty, not over-corrected to missing' \
    "$out" "file:$f/t11-negctrl.env#DQUOTE_EMPTY empty"

  out="$f/t11-squote-empty.out"; err="$f/t11-squote-empty.err"
  code=$(run_helper "$out" "$err" --file "$f/t11-negctrl.env" --key SQUOTE_EMPTY)
  assert_exit "quoted-empty '' negative control" 0 "$code"
  assert_stdout_line "KEY='' (closed, quoted-empty) stays empty, not over-corrected to missing" \
    "$out" "file:$f/t11-negctrl.env#SQUOTE_EMPTY empty"

  out="$f/t11-unquoted.out"; err="$f/t11-unquoted.err"
  code=$(run_helper "$out" "$err" --file "$f/t11-negctrl.env" --key UNQUOTED_PLAIN)
  assert_exit "unquoted value negative control" 0 "$code"
  assert_stdout_line "unquoted KEY=v stays exists, never flagged unterminated" \
    "$out" "file:$f/t11-negctrl.env#UNQUOTED_PLAIN exists"

  log_pass "Unterminated-quote safe direction: bare/non-empty double/single-quoted EOF arms classify missing; properly-closed multiline/quoted-empty/unquoted negative controls unchanged; no sentinel leak (TEST-011)"
}

main() {
  echo "=== $TEST_NAME ==="
  check_deps
  setup_fixture

  if [[ $# -gt 0 ]]; then
    "$1"
    echo "=== $TEST_NAME: SELECTED TEST PASSED ($1) ==="
    return
  fi

  test_001_classification_matrix
  test_002_never_echo_matrix
  test_003_exit_contract
  test_004_canon_grep_contract
  test_005_e2e_dry_run
  test_006_additive_budget_regression
  test_007_multiline_quoting_aware
  test_008_empty_and_quoted_empty
  test_009_never_echo_multiline
  test_010_full_suite_regression
  test_011_unterminated_quote_safe_direction

  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}

main "$@"
