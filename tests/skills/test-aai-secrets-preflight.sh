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

  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}

main "$@"
