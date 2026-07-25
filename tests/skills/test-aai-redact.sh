#!/usr/bin/env bash
#
# Test: RFC-0013 hard redactor (.aai/scripts/lib/aai-redact.mjs), TEST-110.
#
# The redactor is the privacy trust boundary: deny-by-default, fail-closed. A
# clean short string is certified; anything with a secret/identity/location token
# (or over the length cap, or control chars) fails closed so the caller DROPS it.

set -u
TEST_NAME="test-aai-redact"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"
MOD="$PROJECT_ROOT/.aai/scripts/lib/aai-redact.mjs"

# Bare provider prefixes (not secrets on their own). Sensitive fixtures are
# assembled as "${_PREFIX}<fabricated-body>" at runtime so the committed file
# never holds a contiguous, scannable provider-secret literal — while the
# runtime string still matches the redactor's structural detectors.
_AKIA="AKIA"
_GHP="ghp_"
_SK="sk_live_"
_RK="rk_live_"

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_info() { echo "INFO: $*"; }
log_skip() { echo "SKIP: $*"; exit 42; }

command -v node >/dev/null 2>&1 || log_skip "node not found"
[ -f "$MOD" ] || log_fail "redactor module missing: $MOD"

# redact <string> -> prints "ok" or "drop:<reason>"
redact() {
  node --input-type=module -e '
    const { redactSummary } = await import(process.argv[1]);
    const r = redactSummary(process.argv[2]);
    process.stdout.write(r.ok ? "ok" : ("drop:" + r.reason));
  ' "$MOD" "$1"
}

assert_ok() {
  local desc="$1" s="$2" got; got="$(redact "$s")"
  [ "$got" = "ok" ] || log_fail "$desc: expected ok, got '$got' for: $s"
}
assert_drop() {
  local desc="$1" s="$2" got; got="$(redact "$s")"
  case "$got" in drop:*) : ;; *) log_fail "$desc: expected DROP, got '$got' for: $s" ;; esac
}

main() {
  echo "=== $TEST_NAME ==="

  # Clean short human summaries pass.
  assert_ok "clean prose" "planning step failed on a missing transition"
  assert_ok "clean with punctuation" "the spec froze but the AC table had a dangling id"

  # Each detector class must fail closed.
  assert_drop "url"          "see http://example.com/x for detail"
  assert_drop "https url"    "at https://internal.corp/secret"
  assert_drop "email"        "reported by ales@holubec.net"
  assert_drop "abs path"     "crashed at /Users/ales/.ssh/id_rsa"
  assert_drop "win path"     "broke at C:\\Users\\ales\\secret.txt"
  assert_drop "ipv4"         "connected to 10.0.0.1 and hung"
  assert_drop "git remote"   "cloning git@github.com:acme/private failed"
  # Secret-shaped fixtures are assembled from fragments so the committed file
  # contains no contiguous provider-secret literal (which would trip GitHub
  # secret scanning) while the runtime string still matches the redactor.
  assert_drop "aws key"      "leaked ${_AKIA}FAKEKEY0EXAMPLE99 oops"
  assert_drop "pem"          "found -----BEGIN RSA PRIVATE KEY----- inline"
  assert_drop "gh token"     "token ${_GHP}fakeghtoken0123456789abcdef leaked"
  assert_drop "high entropy" "hash deadbeefdeadbeefdeadbeefdeadbeefdeadbeef here"
  assert_drop "user handle"  "blame @someuser for the config"
  assert_drop "long digits"  "account 123456789012 overflowed"
  assert_drop "fqdn"         "resolved host build.internal today"
  assert_drop "fqdn multi"   "api.customer.tech returned 500"
  assert_drop "fqdn unlisted" "build.internal.corp went down"

  # Regression: adversarial bypasses found in independent validation (must DROP).
  assert_drop "rel path no-slash"  "home/ales/.ssh/id_rsa"
  assert_drop "rel path deep"      "Users/ales/Projects/aai/secret.txt"
  assert_drop "ipv6 loopback"      "::1"
  assert_drop "ipv6 linklocal"     "fe80::1"
  assert_drop "ipv6 doc"           "2001:db8::1"
  assert_drop "stripe sk_live"     "${_SK}fakestripekey000111222333"
  assert_drop "stripe rk_live"     "${_RK}fakerestrictedkey0001112223"
  assert_drop "md5 hex secret"     "d41d8cd98f00b204e9800998ecf8427"
  assert_drop "twilio sid"         "AC1234567890abcdef1234567890abcd"

  # Regression: 2nd-pass bypasses (unicode/charset + short token + glued ip).
  assert_drop "zwsp stripe"        "$(printf 'sk\xe2\x80\x8b_live\xe2\x80\x8b_fakestripekey000111222333')"
  assert_drop "single-slash path"  "app/config.env was wrong"
  assert_drop "windows unc"        "\\\\server\\share\\file.txt"
  assert_drop "short mixed token"  "key was Ab3dEf7hIj0kLm2N"
  assert_drop "fullwidth digits"   "$(printf 'account \xef\xbc\x94\xef\xbc\x91\xef\xbc\x92\xef\xbc\x93 charged')"
  assert_drop "ipv4 glued"         "server10.0.0.5used"
  # Regression: 3rd-pass — separator-broken PII digit groups.
  assert_drop "credit card"        "card 4111-1111-1111-1111 declined"
  assert_drop "ssn"                "ssn was 123-45-6789"
  assert_drop "phone"              "call 555-123-4567 today"
  # Clean AAI-style summaries with dots/hyphens/underscores must still pass.
  assert_ok   "script name dots"   "close-work-item.mjs exited 4 on a numbered collision"
  assert_ok   "yaml name"          "STATE.yaml had duplicate keys; check-state flagged it"
  assert_ok   "underscore file"    "AAI_PIN.md was missing the template version line"
  assert_ok   "underscore file 2"  "FRICTION_PROTOCOL.md needed a fifth section"
  assert_ok   "long slug"          "the spec-friction-shadow-capture-wiring item merged"
  assert_ok   "skill name SK"      "SKILL_VALIDATE_REPORT threw during validation"
  assert_ok   "AC-initial word"    "ACtually the transition script passed"

  # Length + control-char + empty fail closed.
  local long; long="$(printf 'x%.0s' $(seq 1 250))"
  assert_drop "over length"  "$long"
  assert_drop "newline"      "$(printf 'line1\nline2')"
  assert_drop "empty"        ""
  assert_drop "whitespace"   "   "

  log_pass "redactor: clean certified; every detector class + length/control/empty fail closed (TEST-110)"
  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}
main "$@"
