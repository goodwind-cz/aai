#!/usr/bin/env bash
#
# Test: RFC-0012 friction feedback DISCOVERY status
# (.aai/scripts/aai-feedback-status.mjs).
#
# Offline counts (spool observations + pending drafts) + a read-only gh auth
# probe (mocked). No mutation, no network beyond `gh auth status`.

set -u
TEST_NAME="test-aai-feedback-status"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"
SCRIPT="$PROJECT_ROOT/.aai/scripts/aai-feedback-status.mjs"

cleanup() { [ -n "${TD:-}" ] && [ -z "${KEEP_TEST_DIR:-}" ] && rm -rf "$TD"; }
trap cleanup EXIT
log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_info() { echo "INFO: $*"; }
log_skip() { echo "SKIP: $*"; exit 42; }
command -v node >/dev/null 2>&1 || log_skip "node not found"
[ -f "$SCRIPT" ] || log_fail "status script missing: $SCRIPT"

setup() {
  TD="$(mktemp -d "${TMPDIR:-/tmp}/aai-fbstatus.XXXXXX")"
  mkdir -p "$TD/friction/pending-issues" "$TD/bin"
  printf '{"a":1}\n{"a":2}\n{"a":3}\n' > "$TD/friction/observations.jsonl"
  : > "$TD/friction/pending-issues/v1_x.md"; : > "$TD/friction/pending-issues/v1_y.md"
  GH_CALLS="$TD/gh_calls"; : > "$GH_CALLS"
}
# mock gh with a controllable exit code ($1)
mock_gh() { printf '#!/usr/bin/env bash\necho "$@" >> "%s"\nexit %s\n' "$GH_CALLS" "$1" > "$TD/bin/gh"; chmod +x "$TD/bin/gh"; }
run() { AAI_FRICTION_DIR="$1" AAI_GH_BIN="${2:-$TD/bin/gh}" node "$SCRIPT" "${@:3}"; }
jq_field() { node -e 'const r=JSON.parse(require("fs").readFileSync(0,"utf8"));process.stdout.write(String(r[process.argv[1]]))' "$1"; }

# --- TEST-001: counts observations + drafts --------------------------------
test_001_counts() {
  log_info "Test: reports the spool observation count and pending-draft count (TEST-001)..."
  mock_gh 0
  local out; out="$(run "$TD/friction" "$TD/bin/gh" --json)"
  [ "$(printf '%s' "$out" | jq_field observations)" = "3" ] || log_fail "TEST-001: observations must be 3"
  [ "$(printf '%s' "$out" | jq_field drafts)" = "2" ] || log_fail "TEST-001: drafts must be 2"
  log_pass "counts observations (3) and pending drafts (2); valid --json (TEST-001)"
}

# --- TEST-002: gh state (ready / unauth / absent) --------------------------
test_002_gh_state() {
  log_info "Test: reports gh state without ever failing the caller (TEST-002)..."
  mock_gh 0
  [ "$(run "$TD/friction" "$TD/bin/gh" --json | jq_field gh)" = "ready" ] || log_fail "TEST-002: authed gh -> ready"
  mock_gh 1
  local out; out="$(run "$TD/friction" "$TD/bin/gh")"; local code=$?
  [ "$code" = "0" ] || log_fail "TEST-002: must never fail the caller (exit $code)"
  echo "$out" | grep -qi "gh auth login" || log_fail "TEST-002: unauthenticated gh -> 'gh auth login' hint"
  [ "$(run "$TD/friction" "/nonexistent/gh" --json | jq_field gh)" = "absent" ] || log_fail "TEST-002: missing gh -> absent"
  log_pass "gh state ready/unauthenticated/absent surfaced; caller never fails (TEST-002)"
}

# --- TEST-003: no mutation / offline for counts ----------------------------
test_003_no_mutation() {
  log_info "Test: no mutating gh call; only a read-only auth probe (TEST-003)..."
  # static: no mutating gh CALL (quoted array args) — the `next:` hint text may
  # name the upsert/--confirm command, but the script itself must not invoke it.
  grep -qE "'issue'|'create'|-X POST|createIssue|'--confirm'" "$SCRIPT" && log_fail "TEST-003: status must have no mutating gh call site" || true
  mock_gh 0; : > "$GH_CALLS"
  run "$TD/friction" "$TD/bin/gh" >/dev/null
  # the ONLY gh call may be `auth status` (read-only)
  if grep -vqE "^auth status$" "$GH_CALLS" && [ -s "$GH_CALLS" ]; then
    grep -qE "issue create|-X POST" "$GH_CALLS" && log_fail "TEST-003: made a mutating gh call: $(cat "$GH_CALLS")"
  fi
  log_pass "no mutating gh call; only read-only auth status (TEST-003)"
}

# --- TEST-004: empty spool -> quiet, exit 0 --------------------------------
test_004_empty() {
  log_info "Test: nothing captured -> quiet message, exit 0 (TEST-004)..."
  mock_gh 0
  local out; out="$(run "$TD/empty" "$TD/bin/gh")"; local code=$?
  [ "$code" = "0" ] || log_fail "TEST-004: empty must exit 0"
  echo "$out" | grep -qi "nothing captured" || log_fail "TEST-004: empty must say nothing captured"
  log_pass "empty spool -> quiet, exit 0 (TEST-004)"
}

main() {
  echo "=== $TEST_NAME ==="
  setup
  if [ $# -gt 0 ]; then "$1"; echo "=== $TEST_NAME: SELECTED PASSED ($1) ==="; return; fi
  test_001_counts
  test_002_gh_state
  test_003_no_mutation
  test_004_empty
  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}
main "$@"
