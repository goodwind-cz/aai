#!/usr/bin/env bash
#
# Test: RFC-0012 Phase 0 friction capture foundation
# (docs/specs/SPEC-DRAFT-spec-friction-capture-foundation.md, TEST-001..017).
#
# Covers the offline capture foundation:
#   .aai/system/FRICTION_PROTOCOL.md  — canonical taxonomy + schema v1 + D6
#                                       allowlist + fingerprint v1 + redaction.
#   .aai/scripts/aai-friction.mjs     — dependency-free offline `record` CLI.
#   docs/ai/friction/                 — gitignored JSONL spool + .gitkeep.
#   .aai/system/PROFILES.yaml         — classification of both new .aai files.
#
# Test map (each TEST-xxx -> a function below unless noted):
#   TEST-001 (Spec-AC-01) protocol doc has the five required sections.
#   TEST-002 (Spec-AC-02) well-formed record -> exit 0, spool +1, aai_pin
#                         equals the value derived from AAI_PIN.md (Seam 2).
#   TEST-003 (Spec-AC-02) missing required field -> non-zero, names field,
#                         spool unchanged.
#   TEST-004 (Spec-AC-02) wrong-typed field (impact as object) -> non-zero,
#                         names field, spool unchanged.
#   TEST-005 (Spec-AC-03) forbidden identity keys dropped structurally.
#   TEST-006 (Spec-AC-03) a wholly novel key dropped too (deny-by-default,
#                         not a denylist).
#   TEST-007 (Spec-AC-04) static: no networking call in the source (the sole
#                         broad-grep match is the documented `network` prose).
#   TEST-008 (Spec-AC-04) runtime under unroutable proxy env -> exit 0, line.
#   TEST-009 (Spec-AC-05) fingerprint deterministic, `v1:`-tagged,
#                         normalization-stable.
#   TEST-010 (Spec-AC-06) 3 accepted -> 3 parseable lines; a 4th rejected
#                         leaves the count at 3.
#   TEST-011 (Spec-AC-06) static: O_APPEND (appendFileSync) write path, no
#                         read-modify-write of the spool.
#   TEST-012 (Spec-AC-07) bad input inside `&& echo WRAPPER_OK` -> no
#                         WRAPPER_OK, specific documented exit, empty stdout.
#   TEST-013 (Spec-AC-08) generated spool file is gitignored, .gitkeep tracked.
#   TEST-014 (Spec-AC-09) test-aai-layer-profiles.sh green; both new paths
#                         classified exactly once (Seam 1).
#   TEST-015 (Spec-AC-10) --help exits 0 and documents the contract.
#   TEST-016 (Spec-AC-11) every import is node:-prefixed; this file uses full
#                         mktemp templates.
#   TEST-017 (Spec-AC-12) full runner — exercised by test-framework.sh, not a
#                         function here (would recurse). Asserted at suite
#                         level by the parent runner.
#   TEST-018 (Spec-AC-06) N concurrent records against ONE spool -> exactly N
#                         well-formed lines (O_APPEND, no loss/interleave).
#   TEST-019 (Spec-AC-06) an over-cap record whose line would reach PIPE_BUF is
#                         rejected with no spool write; a normal record still
#                         records; N concurrent AT-cap records -> exactly N lines.
#
# Fixture diversity checklist (SPEC-0013 H7), mapped:
#   - degenerate/empty      -> empty spool (0 lines) before first record;
#                              empty `--input` / `{}` object rejected (TEST-003).
#   - zero-remainder         -> single accepted record yields exactly 1 line,
#                              nothing else (TEST-002).
#   - multi-source/multi-writer -> 3 sequential records into ONE spool, each an
#                              independent atomic temp+rename write (TEST-010).
#   - mid-operation failure  -> a rejected 4th record must not leave a partial
#                              or extra line (TEST-010).
#   - negative control       -> a caller who supplies hostname/username/etc. and
#                              a novel key: none may reach the spool (TEST-005/006);
#                              a caller-supplied os_family/aai_pin must be ignored
#                              in favour of the locally derived value (TEST-005).
#
# bash 3.2 compatible (no ${var^^}, no declare -A). Node stdlib only.
#
# Usage:
#   bash tests/skills/test-aai-friction.sh                 # run all tests
#   bash tests/skills/test-aai-friction.sh test_005_...    # run one test
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-friction"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

SCRIPT="$PROJECT_ROOT/.aai/scripts/aai-friction.mjs"
PROTOCOL="$PROJECT_ROOT/.aai/system/FRICTION_PROTOCOL.md"
AAI_PIN="$PROJECT_ROOT/.aai/system/AAI_PIN.md"
PROFILES="$PROJECT_ROOT/.aai/system/PROFILES.yaml"
LAYER_PROFILES_TEST="$SCRIPT_DIR/test-aai-layer-profiles.sh"
REAL_SPOOL="$PROJECT_ROOT/docs/ai/friction/observations.jsonl"
JQ=""

cleanup() {
  if [ -n "${KEEP_TEST_DIR:-}" ]; then
    echo "INFO: keeping fixture at $TEST_DIR"
  elif [ -n "${TEST_DIR:-}" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
  # Remove any real-spool artifact TEST-013 wrote into the working tree.
  rm -f "$REAL_SPOOL"
  rm -f "$PROJECT_ROOT"/docs/ai/friction/.tmp-* 2>/dev/null || true
}
trap cleanup EXIT

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git  >/dev/null 2>&1 || log_skip "git not found"
  [ -f "$AAI_PIN" ] || log_fail "AAI_PIN.md not found: $AAI_PIN"
  [ -f "$PROFILES" ] || log_fail "PROFILES.yaml not found: $PROFILES"
  [ -f "$LAYER_PROFILES_TEST" ] || log_fail "test-aai-layer-profiles.sh not found"
  # NOTE: SCRIPT and PROTOCOL are intentionally NOT required here — the RED
  # phase runs against the absent script/doc so each TEST-xxx fails on its own
  # assertion (product_red), not a missing-precondition skip.
  log_pass "Dependencies checked"
}

setup_fixture() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-friction-test.XXXXXX")"
  OUT="$TEST_DIR/rec.out"; ERR="$TEST_DIR/rec.err"
  # Small node JSONL reader used by assertions (stdlib only). Ops:
  #   keys <file> [idx]   -> sorted comma-joined keys of a line (default last)
  #   get  <file> <key> [idx] -> String(value) or the sentinel __UNDEF__
  #   count <file>        -> number of non-empty lines
  #   parseall <file>     -> "OK" iff every non-empty line JSON.parses
  JQ="$TEST_DIR/jsonl.mjs"
  cat > "$JQ" <<'NODE'
import { readFileSync } from 'node:fs';
const a = process.argv.slice(2);
const op = a[0];
const file = a[1];
let lines = [];
try { lines = readFileSync(file, 'utf8').split('\n').filter((l) => l.trim().length > 0); } catch { lines = []; }
function pick(i) {
  const idx = (i === undefined || i === '') ? lines.length - 1 : Number(i);
  return JSON.parse(lines[idx]);
}
if (op === 'keys') process.stdout.write(Object.keys(pick(a[2])).sort().join(','));
else if (op === 'get') { const v = pick(a[3])[a[2]]; process.stdout.write(v === undefined ? '__UNDEF__' : String(v)); }
else if (op === 'count') process.stdout.write(String(lines.length));
else if (op === 'parseall') { for (const l of lines) JSON.parse(l); process.stdout.write('OK'); }
process.exit(0);
NODE
}

# --- generic helpers --------------------------------------------------------

# run_record <spooldir> <input-file-or-dash> [extra env assignments already
# exported by caller] : runs `node SCRIPT record --input <arg>` with the spool
# redirected to <spooldir>, capturing stdout/stderr into $OUT/$ERR and echoing
# the exit code. Never trips set -e.
# OUT / ERR are fixed paths set in setup_fixture. run_record runs inside a
# command substitution (a subshell), so it must not rely on assigning globals
# here — it only reads them and writes to the on-disk files.
OUT=""; ERR=""
run_record() {
  local spooldir="$1" input="$2"
  local code=0
  AAI_FRICTION_SPOOL_DIR="$spooldir" node "$SCRIPT" record --input "$input" \
    > "$OUT" 2> "$ERR" || code=$?
  echo "$code"
}

spool_count() { node "$JQ" count "$1"; }
line_keys()   { node "$JQ" keys "$1" "${2:-}"; }
line_get()    { node "$JQ" get "$1" "$2" "${3:-}"; }

assert_exit() {
  local desc="$1" expected="$2" actual="$3"
  [ "$actual" = "$expected" ] || log_fail "$desc: expected exit $expected, got $actual"
}

assert_key_absent() {
  local desc="$1" keys="$2" key="$3"
  case ",$keys," in
    *",$key,"*) log_fail "$desc: forbidden key '$key' present in spool line (keys=$keys)" ;;
  esac
}

assert_key_present() {
  local desc="$1" keys="$2" key="$3"
  case ",$keys," in
    *",$key,"*) : ;;
    *) log_fail "$desc: expected key '$key' missing from spool line (keys=$keys)" ;;
  esac
}

# The exact aai_pin derivation the script uses, replicated for TEST-002: the
# `Template version` field of AAI_PIN.md, trimmed; empty or a `<...>` sync
# placeholder -> the literal `unknown`.
compute_expected_pin() {
  local raw
  raw="$(sed -n 's/^- Template version:[[:space:]]*//p' "$AAI_PIN" | head -1)"
  raw="$(printf '%s' "$raw" | sed 's/[[:space:]]*$//')"
  case "$raw" in
    ""|"<"*) printf 'unknown' ;;
    *) printf '%s' "$raw" ;;
  esac
}

# Writes a well-formed schema-v1 observation to $1. Any extra raw JSON member
# lines are passed as $2 (already comma-prefixed) so callers can inject
# forbidden/novel keys.
write_wellformed() {
  local path="$1" extra="${2:-}"
  cat > "$path" <<JSON
{
  "schema_version": 1,
  "skill_id": "SKILL_TDD",
  "skill_phase": "implementation",
  "failure_class": "deterministic_script_failure",
  "expected_behavior": "the transition script exits 0",
  "observed_behavior": "the transition script threw ENOENT"${extra}
}
JSON
}

# --- TEST-001 (Spec-AC-01): protocol doc sections ---------------------------

test_001_protocol_sections() {
  log_info "Test: FRICTION_PROTOCOL.md has the five required sections, each once (TEST-001)..."
  [ -f "$PROTOCOL" ] || log_fail "TEST-001: $PROTOCOL does not exist"
  local h n
  local headings=(
    "## Failure-class taxonomy"
    "## Observation schema v1"
    "## D6 persisted-field allowlist"
    "## Fingerprint v1 algorithm"
    "## Redaction and privacy policy"
  )
  for h in "${headings[@]}"; do
    n="$(grep -cF "$h" "$PROTOCOL" || true)"
    [ "$n" = "1" ] || log_fail "TEST-001: heading '$h' must appear exactly once (got $n)"
  done
  log_pass "Protocol doc: all five required sections present exactly once (TEST-001)"
}

# --- TEST-002 (Spec-AC-02): well-formed record accepted ---------------------

test_002_wellformed_accepted() {
  log_info "Test: well-formed record -> exit 0, spool +1, derived aai_pin matches AAI_PIN.md (TEST-002)..."
  local sp="$TEST_DIR/sp002"; mkdir -p "$sp"
  local spool="$sp/observations.jsonl"
  write_wellformed "$TEST_DIR/wf002.json"

  [ "$(spool_count "$spool")" = "0" ] || log_fail "TEST-002: spool should start empty"
  local code; code="$(run_record "$sp" "$TEST_DIR/wf002.json")"
  assert_exit "well-formed record" 0 "$code"
  [ "$(spool_count "$spool")" = "1" ] || log_fail "TEST-002: expected exactly 1 spool line ($(cat "$ERR"))"

  local keys; keys="$(line_keys "$spool")"
  assert_key_present "TEST-002" "$keys" "schema_version"
  assert_key_present "TEST-002" "$keys" "os_family"
  assert_key_present "TEST-002" "$keys" "aai_pin"
  assert_key_present "TEST-002" "$keys" "node_major"
  assert_key_present "TEST-002" "$keys" "skill_id"
  assert_key_present "TEST-002" "$keys" "skill_phase"
  assert_key_present "TEST-002" "$keys" "failure_class"
  assert_key_present "TEST-002" "$keys" "fingerprint"
  [ "$keys" = "aai_pin,failure_class,fingerprint,node_major,os_family,schema_version,skill_id,skill_phase" ] \
    || log_fail "TEST-002: spool line key set must be EXACTLY the 8 allowlist keys (got $keys)"

  local got_pin want_pin
  got_pin="$(line_get "$spool" aai_pin)"
  want_pin="$(compute_expected_pin)"
  [ "$got_pin" = "$want_pin" ] \
    || log_fail "TEST-002: persisted aai_pin '$got_pin' must equal AAI_PIN.md-derived '$want_pin' (Seam 2)"

  # os_family is a normalized enum, never the raw platform string.
  local os; os="$(line_get "$spool" os_family)"
  case "$os" in
    linux|macos|windows|unknown) : ;;
    *) log_fail "TEST-002: os_family '$os' is not a normalized enum" ;;
  esac
  log_pass "Well-formed record accepted: exit 0, +1 line, derived aai_pin matches (TEST-002)"
}

# --- TEST-003 (Spec-AC-02): missing required field --------------------------

test_003_missing_field() {
  log_info "Test: missing required field -> non-zero naming the field, spool unchanged (TEST-003)..."
  local sp="$TEST_DIR/sp003"; mkdir -p "$sp"
  local spool="$sp/observations.jsonl"
  # Well-formed minus skill_id.
  cat > "$TEST_DIR/miss003.json" <<'JSON'
{
  "schema_version": 1,
  "skill_phase": "implementation",
  "failure_class": "deterministic_script_failure",
  "expected_behavior": "exits 0",
  "observed_behavior": "threw"
}
JSON
  local code; code="$(run_record "$sp" "$TEST_DIR/miss003.json")"
  [ "$code" != "0" ] || log_fail "TEST-003: missing skill_id must be rejected (got exit 0)"
  grep -qF "skill_id" "$ERR" \
    || log_fail "TEST-003: stderr must name the offending field 'skill_id' (got: $(cat "$ERR"))"
  [ "$(spool_count "$spool")" = "0" ] || log_fail "TEST-003: rejected input must not write a spool line"
  log_pass "Missing required field rejected, field named, no spool write (TEST-003)"
}

# --- TEST-004 (Spec-AC-02): wrong-typed field -------------------------------

test_004_wrong_type() {
  log_info "Test: wrong-typed field (impact as object) -> non-zero naming the field, spool unchanged (TEST-004)..."
  local sp="$TEST_DIR/sp004"; mkdir -p "$sp"
  local spool="$sp/observations.jsonl"
  write_wellformed "$TEST_DIR/wt004.json" ',
  "impact": { "nested": true }'
  local code; code="$(run_record "$sp" "$TEST_DIR/wt004.json")"
  [ "$code" != "0" ] || log_fail "TEST-004: object-typed impact must be rejected (got exit 0)"
  grep -qF "impact" "$ERR" \
    || log_fail "TEST-004: stderr must name the offending field 'impact' (got: $(cat "$ERR"))"
  [ "$(spool_count "$spool")" = "0" ] || log_fail "TEST-004: rejected input must not write a spool line"
  log_pass "Wrong-typed field rejected, field named, no spool write (TEST-004)"
}

# --- TEST-005 (Spec-AC-03): forbidden identity keys dropped -----------------

test_005_forbidden_keys_dropped() {
  log_info "Test: forbidden identity keys (+ caller-supplied derived fields) dropped structurally (TEST-005)..."
  local sp="$TEST_DIR/sp005"; mkdir -p "$sp"
  local spool="$sp/observations.jsonl"
  write_wellformed "$TEST_DIR/id005.json" ',
  "hostname": "build-box-17.corp.internal",
  "absolute_path": "/Users/secret-person/proj/aai",
  "repo_remote": "git@github.com:private-org/secret-repo.git",
  "username": "secret-person",
  "project_id": "PRIV-4242",
  "os_family": "caller-lied-os",
  "aai_pin": "9.9.9-caller-supplied",
  "node_major": 999'
  local code; code="$(run_record "$sp" "$TEST_DIR/id005.json")"
  assert_exit "record with identity keys still accepted" 0 "$code"
  [ "$(spool_count "$spool")" = "1" ] || log_fail "TEST-005: expected 1 spool line"

  local keys; keys="$(line_keys "$spool")"
  assert_key_absent "TEST-005" "$keys" "hostname"
  assert_key_absent "TEST-005" "$keys" "absolute_path"
  assert_key_absent "TEST-005" "$keys" "repo_remote"
  assert_key_absent "TEST-005" "$keys" "username"
  assert_key_absent "TEST-005" "$keys" "project_id"
  [ "$keys" = "aai_pin,failure_class,fingerprint,node_major,os_family,schema_version,skill_id,skill_phase" ] \
    || log_fail "TEST-005: spool line must contain ONLY the 8 allowlist keys (got $keys)"

  # Locally derived fields must NOT trust caller-supplied values.
  [ "$(line_get "$spool" os_family)" != "caller-lied-os" ] \
    || log_fail "TEST-005: os_family must be derived locally, not the caller's value"
  [ "$(line_get "$spool" aai_pin)" != "9.9.9-caller-supplied" ] \
    || log_fail "TEST-005: aai_pin must be derived locally, not the caller's value"
  [ "$(line_get "$spool" node_major)" != "999" ] \
    || log_fail "TEST-005: node_major must be derived locally, not the caller's value"
  log_pass "Forbidden identity keys dropped; derived fields not caller-trusted (TEST-005)"
}

# --- TEST-006 (Spec-AC-03): novel unknown key dropped (deny-by-default) ------

test_006_novel_key_dropped() {
  log_info "Test: a wholly novel key never named in the protocol is dropped (deny-by-default) (TEST-006)..."
  local sp="$TEST_DIR/sp006"; mkdir -p "$sp"
  local spool="$sp/observations.jsonl"
  write_wellformed "$TEST_DIR/novel006.json" ',
  "extra_debug_note": "this field is invented and appears nowhere in the protocol",
  "another_unlisted_field": 12345'
  local code; code="$(run_record "$sp" "$TEST_DIR/novel006.json")"
  assert_exit "record with novel key still accepted" 0 "$code"
  local keys; keys="$(line_keys "$spool")"
  assert_key_absent "TEST-006" "$keys" "extra_debug_note"
  assert_key_absent "TEST-006" "$keys" "another_unlisted_field"
  [ "$keys" = "aai_pin,failure_class,fingerprint,node_major,os_family,schema_version,skill_id,skill_phase" ] \
    || log_fail "TEST-006: novel keys prove deny-by-default; only the 8 allowlist keys may survive (got $keys)"
  log_pass "Novel unknown key dropped — allowlist is deny-by-default, not a denylist (TEST-006)"
}

# --- TEST-007 (Spec-AC-04): no networking call (static) ---------------------

test_007_no_network_static() {
  log_info "Test: static grep — no networking call in aai-friction.mjs source (TEST-007)..."
  [ -f "$SCRIPT" ] || log_fail "TEST-007: $SCRIPT does not exist (cannot verify absence of net calls)"
  # The broad token grep from Spec-AC-04. Its ONLY documented false positive is
  # the prose word `network` (the no-network guarantee in comments/--help),
  # which contains the substring `net`. We remove lines mentioning that word
  # and assert nothing else matches — i.e. no import of / call into a net,
  # http(s), socket, child_process, or `gh` primitive survives.
  local broad residual
  broad="$(grep -inE 'net|http|https|fetch|child_process|socket|gh ' "$SCRIPT" || true)"
  residual="$(printf '%s\n' "$broad" | grep -vE 'network' | grep -vE '^\s*$' || true)"
  [ -z "$residual" ] \
    || log_fail "TEST-007: source contains non-false-positive networking token(s):
$residual"
  # Belt-and-braces: no networking module import in any form.
  grep -qiE "node:(net|http|https|http2|dgram|tls|dns)|child_process|['\"]net['\"]|WebSocket|createConnection" "$SCRIPT" \
    && log_fail "TEST-007: a networking module/primitive is imported or referenced" || true
  log_pass "No networking call in source (sole broad-grep match is documented 'network' prose) (TEST-007)"
}

# --- TEST-008 (Spec-AC-04): runs offline under unroutable proxy -------------

test_008_offline_runtime() {
  log_info "Test: record succeeds with unroutable proxy env vars set (TEST-008)..."
  local sp="$TEST_DIR/sp008"; mkdir -p "$sp"
  local spool="$sp/observations.jsonl"
  write_wellformed "$TEST_DIR/wf008.json"
  local code=0
  HTTP_PROXY="http://192.0.2.1:9" HTTPS_PROXY="http://192.0.2.1:9" \
  http_proxy="http://192.0.2.1:9" https_proxy="http://192.0.2.1:9" \
  AAI_FRICTION_SPOOL_DIR="$sp" node "$SCRIPT" record --input "$TEST_DIR/wf008.json" \
    > "$TEST_DIR/o8.out" 2> "$TEST_DIR/o8.err" || code=$?
  assert_exit "offline record" 0 "$code"
  [ "$(spool_count "$spool")" = "1" ] || log_fail "TEST-008: offline record must write exactly 1 line"
  log_pass "Record runs offline under unroutable proxy env; 1 line written (TEST-008)"
}

# --- TEST-009 (Spec-AC-05): fingerprint determinism + normalization ---------

test_009_fingerprint_determinism() {
  log_info "Test: fingerprint deterministic, v1:-tagged, normalization-stable (TEST-009)..."
  local a="$TEST_DIR/sp009a" b="$TEST_DIR/sp009b" c="$TEST_DIR/sp009c"
  mkdir -p "$a" "$b" "$c"
  write_wellformed "$TEST_DIR/wf009.json"
  # A normalization-variant: only case/whitespace differ in fingerprinted
  # (non-persisted) fields expected_behavior / observed_behavior.
  cat > "$TEST_DIR/wf009norm.json" <<'JSON'
{
  "schema_version": 1,
  "skill_id": "SKILL_TDD",
  "skill_phase": "implementation",
  "failure_class": "deterministic_script_failure",
  "expected_behavior": "   THE   Transition Script    Exits 0   ",
  "observed_behavior": "The Transition SCRIPT   threw   ENOENT"
}
JSON
  run_record "$a" "$TEST_DIR/wf009.json"     >/dev/null
  run_record "$b" "$TEST_DIR/wf009.json"     >/dev/null
  run_record "$c" "$TEST_DIR/wf009norm.json" >/dev/null

  local fa fb fc
  fa="$(line_get "$a/observations.jsonl" fingerprint)"
  fb="$(line_get "$b/observations.jsonl" fingerprint)"
  fc="$(line_get "$c/observations.jsonl" fingerprint)"
  case "$fa" in v1:*) : ;; *) log_fail "TEST-009: fingerprint must be v1:-tagged (got '$fa')" ;; esac
  [ "$fa" = "$fb" ] || log_fail "TEST-009: byte-identical inputs must yield equal fingerprints ($fa vs $fb)"
  [ "$fa" = "$fc" ] \
    || log_fail "TEST-009: case/whitespace-only variation must normalize to the same fingerprint ($fa vs $fc)"
  log_pass "Fingerprint deterministic, v1:-tagged, normalization-stable (TEST-009)"
}

# --- TEST-010 (Spec-AC-06): atomic multi-line, rejected leaves count --------

test_010_atomic_multi_line() {
  log_info "Test: 3 accepted -> 3 parseable lines; a rejected 4th leaves the count at 3 (TEST-010)..."
  local sp="$TEST_DIR/sp010"; mkdir -p "$sp"
  local spool="$sp/observations.jsonl"
  write_wellformed "$TEST_DIR/wf010.json"
  local i code
  for i in 1 2 3; do
    code="$(run_record "$sp" "$TEST_DIR/wf010.json")"
    assert_exit "accepted record #$i" 0 "$code"
  done
  [ "$(spool_count "$spool")" = "3" ] || log_fail "TEST-010: expected exactly 3 spool lines"
  [ "$(node "$JQ" parseall "$spool")" = "OK" ] || log_fail "TEST-010: every spool line must independently JSON.parse"
  # 4th, schema-invalid.
  cat > "$TEST_DIR/bad010.json" <<'JSON'
{ "schema_version": 1, "skill_id": "SKILL_TDD" }
JSON
  code="$(run_record "$sp" "$TEST_DIR/bad010.json")"
  [ "$code" != "0" ] || log_fail "TEST-010: schema-invalid 4th record must be rejected"
  [ "$(spool_count "$spool")" = "3" ] || log_fail "TEST-010: rejected record must leave the count at 3"
  log_pass "Atomic writes: 3 parseable lines; rejected 4th leaves count at 3 (TEST-010)"
}

# --- TEST-011 (Spec-AC-06): atomic O_APPEND write path (static) -------------

test_011_atomic_append_static() {
  log_info "Test: source appends via O_APPEND (appendFileSync), never a read-modify-write of the spool (TEST-011)..."
  [ -f "$SCRIPT" ] || log_fail "TEST-011: $SCRIPT does not exist"
  # Correct atomic mechanism for an append log under concurrency: a single
  # O_APPEND write per line (appendFileSync), NOT a read-modify-write.
  grep -qF "appendFileSync" "$SCRIPT" \
    || log_fail "TEST-011: source must append atomically with appendFileSync (O_APPEND)"
  # The read-modify-write anti-pattern must be gone: no readFileSync of the
  # spool target, no rewrite-then-rename of the whole file inside appendLine.
  grep -qE "readFileSync\(\s*target" "$SCRIPT" \
    && log_fail "TEST-011: appendLine must not read the spool back (read-modify-write loses concurrent lines)" || true
  grep -qE "renameSync" "$SCRIPT" \
    && log_fail "TEST-011: the temp-file + rename append path must be gone (it is not concurrency-safe for an append log)" || true
  log_pass "Atomic O_APPEND append path present; no read-modify-write of the spool (TEST-011)"
}

# --- TEST-012 (Spec-AC-07): capture never masks the caller ------------------

test_012_never_masks_caller() {
  log_info "Test: bad input inside '&& echo WRAPPER_OK' -> no WRAPPER_OK, specific exit, empty stdout (TEST-012)..."
  local sp="$TEST_DIR/sp012"; mkdir -p "$sp"
  cat > "$TEST_DIR/bad012.json" <<'JSON'
{ "not_a_valid": "observation" }
JSON
  local out="$TEST_DIR/w12.out" err="$TEST_DIR/w12.err" code=0
  # Wrapper idiom: WRAPPER_OK must never print on a rejected capture.
  ( AAI_FRICTION_SPOOL_DIR="$sp" node "$SCRIPT" record --input "$TEST_DIR/bad012.json" \
      && echo WRAPPER_OK ) > "$out" 2> "$err" || code=$?
  grep -qF "WRAPPER_OK" "$out" \
    && log_fail "TEST-012: WRAPPER_OK printed — a rejected capture must exit non-zero" || true
  # Specific, documented validation exit code (3) — NOT node's default uncaught
  # exception code (1).
  assert_exit "documented validation exit code" 3 "$code"
  [ ! -s "$out" ] || log_fail "TEST-012: stdout must be empty on rejection (got: $(cat "$out"))"
  log_pass "Capture never masks the caller: no WRAPPER_OK, exit 3, empty stdout (TEST-012)"
}

# --- TEST-013 (Spec-AC-08): gitignored spool, tracked .gitkeep --------------

test_013_gitignore() {
  log_info "Test: generated spool file gitignored; .gitkeep tracked (TEST-013)..."
  # Write into the REAL spool dir via the default path (no override).
  write_wellformed "$TEST_DIR/wf013.json"
  local code=0
  node "$SCRIPT" record --input "$TEST_DIR/wf013.json" >/dev/null 2> "$TEST_DIR/g13.err" || code=$?
  assert_exit "default-spool record" 0 "$code"
  [ -f "$REAL_SPOOL" ] || log_fail "TEST-013: default record must create $REAL_SPOOL"
  git -C "$PROJECT_ROOT" check-ignore -q "docs/ai/friction/observations.jsonl" \
    || log_fail "TEST-013: docs/ai/friction/observations.jsonl must be gitignored"
  local st
  st="$(git -C "$PROJECT_ROOT" status --porcelain -- docs/ai/friction/observations.jsonl)"
  [ -z "$st" ] || log_fail "TEST-013: generated spool file must not show in git status (got: $st)"
  git -C "$PROJECT_ROOT" ls-files --error-unmatch docs/ai/friction/.gitkeep >/dev/null 2>&1 \
    || log_fail "TEST-013: docs/ai/friction/.gitkeep must be tracked"
  rm -f "$REAL_SPOOL"
  log_pass "Spool gitignored, .gitkeep tracked (TEST-013)"
}

# --- TEST-014 (Spec-AC-09): PROFILES classification / layer-profiles green ---

test_014_profiles_classified() {
  log_info "Test: both new .aai paths classified once; test-aai-layer-profiles.sh green (TEST-014, Seam 1)..."
  local n
  n="$(grep -cF "  - .aai/scripts/aai-friction.mjs" "$PROFILES" || true)"
  [ "$n" = "1" ] || log_fail "TEST-014: .aai/scripts/aai-friction.mjs must be classified exactly once (got $n)"
  n="$(grep -cF "  - .aai/system/FRICTION_PROTOCOL.md" "$PROFILES" || true)"
  [ "$n" = "1" ] || log_fail "TEST-014: .aai/system/FRICTION_PROTOCOL.md must be classified exactly once (got $n)"
  local lp_log="$TEST_DIR/layer-profiles.log" code=0
  bash "$LAYER_PROFILES_TEST" > "$lp_log" 2>&1 || code=$?
  [ "$code" = "0" ] \
    || log_fail "TEST-014: test-aai-layer-profiles.sh must exit 0 (got $code): $(tail -20 "$lp_log")"
  log_pass "PROFILES classifies both new files; layer-profiles suite green (TEST-014)"
}

# --- TEST-015 (Spec-AC-10): --help documents the contract -------------------

test_015_help() {
  log_info "Test: --help exits 0 and documents record/--input/allowlist/network (TEST-015)..."
  local out="$TEST_DIR/help.out" err="$TEST_DIR/help.err" code=0
  node "$SCRIPT" --help > "$out" 2> "$err" || code=$?
  assert_exit "--help" 0 "$code"
  grep -qF "record"    "$out" || log_fail "TEST-015: --help must mention 'record'"
  grep -qF -- "--input" "$out" || log_fail "TEST-015: --help must mention '--input'"
  grep -qF "allowlist" "$out" || log_fail "TEST-015: --help must mention 'allowlist'"
  grep -qF "network"   "$out" || log_fail "TEST-015: --help must mention 'network'"
  log_pass "--help documents record/--input/allowlist/network, exit 0 (TEST-015)"
}

# --- TEST-016 (Spec-AC-11): node:-only imports; full mktemp templates -------

test_016_portability() {
  log_info "Test: every import node:-prefixed; this file uses full mktemp templates (TEST-016)..."
  [ -f "$SCRIPT" ] || log_fail "TEST-016: $SCRIPT does not exist"
  # Every `import ... from '<target>'` target must start with node: — keep only
  # import lines whose module is NOT node:-prefixed; that set must be empty.
  local bad
  bad="$(grep -nE "^import[^\"']*from ['\"]" "$SCRIPT" | grep -vE "from ['\"]node:" || true)"
  [ -z "$bad" ] || log_fail "TEST-016: non-node: import target(s) present:
$bad"
  # No CommonJS require of a bare package either.
  grep -qE "require\(['\"][^n.]" "$SCRIPT" \
    && log_fail "TEST-016: bare require() of an external package present" || true
  # This test file itself uses a full mktemp -d template (not a bare mktemp).
  grep -qE 'mktemp -d "\$\{TMPDIR:-/tmp\}/aai-friction-test\.XXXXXX"' "${BASH_SOURCE[0]}" \
    || log_fail "TEST-016: this test must use a full mktemp -d XXXXXX template"
  log_pass "node:-only imports; full mktemp templates (TEST-016)"
}

# --- TEST-018 (Spec-AC-06): concurrent records lose no line ------------------

test_018_concurrent_no_loss() {
  log_info "Test: N concurrent records against ONE spool -> exactly N well-formed lines, no loss (TEST-018)..."
  local sp="$TEST_DIR/sp018"; mkdir -p "$sp"
  local spool="$sp/observations.jsonl"
  write_wellformed "$TEST_DIR/wf018.json"
  local n=20 i
  # Spawn N concurrent record processes writing to the SAME spool file. A
  # read-modify-write append loses lines here (two processes read the same
  # snapshot; the later rename overwrites the earlier line); an O_APPEND
  # per-line append does not.
  for i in $(seq 1 "$n"); do
    AAI_FRICTION_SPOOL_DIR="$sp" node "$SCRIPT" record --input "$TEST_DIR/wf018.json" \
      >/dev/null 2>&1 &
  done
  wait
  local got; got="$(spool_count "$spool")"
  [ "$got" = "$n" ] \
    || log_fail "TEST-018: expected exactly $n lines after $n concurrent records, got $got (lines lost -> non-atomic append)"
  [ "$(node "$JQ" parseall "$spool")" = "OK" ] \
    || log_fail "TEST-018: every line after concurrent append must independently JSON.parse (corruption/interleave)"
  log_pass "Concurrent records: $n concurrent writers -> exactly $n well-formed lines, no loss (TEST-018)"
}

# --- TEST-019 (Spec-AC-06): PIPE_BUF line guard + per-field caps -------------

test_019_oversize_line_rejected() {
  log_info "Test: over-cap record (line would reach PIPE_BUF) rejected no-write; normal record records; at-cap concurrency lossless (TEST-019)..."
  local sp="$TEST_DIR/sp019"; mkdir -p "$sp"
  local spool="$sp/observations.jsonl"

  # (a) A skill_id far over the persisted-field cap serializes to a line well
  # above PIPE_BUF (~6221 bytes) -> MUST be rejected before any append, so a
  # line that could interleave under concurrent O_APPEND is never written.
  local big; big="$(head -c 6000 < /dev/zero | tr '\0' a)"
  cat > "$TEST_DIR/big019.json" <<JSON
{
  "schema_version": 1,
  "skill_id": "$big",
  "skill_phase": "implementation",
  "failure_class": "deterministic_script_failure",
  "expected_behavior": "the transition script exits 0",
  "observed_behavior": "the transition script threw ENOENT"
}
JSON
  local code; code="$(run_record "$sp" "$TEST_DIR/big019.json")"
  [ "$code" != "0" ] \
    || log_fail "TEST-019: an over-cap skill_id (6000 chars -> line > PIPE_BUF) must be rejected (got exit 0)"
  grep -qiE "skill_id|length|size|bound" "$ERR" \
    || log_fail "TEST-019: rejection must name the field or the length/size bound (got: $(cat "$ERR"))"
  [ "$(spool_count "$spool")" = "0" ] \
    || log_fail "TEST-019: a rejected over-cap record must not append any spool line"

  # (b) A normal record still records right after the rejection.
  write_wellformed "$TEST_DIR/wf019.json"
  code="$(run_record "$sp" "$TEST_DIR/wf019.json")"
  assert_exit "normal record after over-cap rejection" 0 "$code"
  [ "$(spool_count "$spool")" = "1" ] \
    || log_fail "TEST-019: a normal record must still append exactly one line after a rejection"

  # (c) At-cap-boundary concurrency: N concurrent records whose skill_id is at
  # the 128-char cap (line still < PIPE_BUF) -> exactly N well-formed lines.
  local sp2="$TEST_DIR/sp019b"; mkdir -p "$sp2"
  local spool2="$sp2/observations.jsonl"
  local capid; capid="$(head -c 128 < /dev/zero | tr '\0' a)"
  cat > "$TEST_DIR/cap019.json" <<JSON
{
  "schema_version": 1,
  "skill_id": "$capid",
  "skill_phase": "implementation",
  "failure_class": "deterministic_script_failure",
  "expected_behavior": "the transition script exits 0",
  "observed_behavior": "the transition script threw ENOENT"
}
JSON
  local n=20 i
  for i in $(seq 1 "$n"); do
    AAI_FRICTION_SPOOL_DIR="$sp2" node "$SCRIPT" record --input "$TEST_DIR/cap019.json" \
      >/dev/null 2>&1 &
  done
  wait
  local got; got="$(spool_count "$spool2")"
  [ "$got" = "$n" ] \
    || log_fail "TEST-019: $n concurrent at-cap records must yield exactly $n lines, got $got"
  [ "$(node "$JQ" parseall "$spool2")" = "OK" ] \
    || log_fail "TEST-019: every at-cap concurrent line must independently JSON.parse"
  log_pass "Over-cap line rejected (no write); normal record records; at-cap concurrency lossless (TEST-019)"
}

main() {
  echo "=== $TEST_NAME ==="
  check_deps
  setup_fixture

  if [ $# -gt 0 ]; then
    "$1"
    echo "=== $TEST_NAME: SELECTED TEST PASSED ($1) ==="
    return
  fi

  test_001_protocol_sections
  test_002_wellformed_accepted
  test_003_missing_field
  test_004_wrong_type
  test_005_forbidden_keys_dropped
  test_006_novel_key_dropped
  test_007_no_network_static
  test_008_offline_runtime
  test_009_fingerprint_determinism
  test_010_atomic_multi_line
  test_011_atomic_append_static
  test_012_never_masks_caller
  test_013_gitignore
  test_014_profiles_classified
  test_015_help
  test_016_portability
  test_018_concurrent_no_loss
  test_019_oversize_line_rejected

  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}

main "$@"
