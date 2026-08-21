# Pipe-free payload assertions
# (spec-assertions-must-not-die-on-their-own-payload, Spec-AC-02).
#
# WHY THIS EXISTS
#   printf '%s\n' "$out" | grep -qF "$needle"
# reports FAILURE on a payload that MATCHED, once "$out" passes the 64 KiB pipe
# buffer. `grep -q` exits at the first match, the writer takes SIGPIPE (141),
# and `set -o pipefail` promotes that to the pipeline's status. Measured on this
# machine: 17978 B and 52194 B pass 20/20; 90778 B and 181779 B fail 20/20. It
# is a threshold at the buffer, not a race — which is why it reddens CI while
# passing locally, on the same assertion, depending only on how much the fixture
# grew.
#
# The safe form is a shell pattern match: no pipe, no second process, nothing to
# take a signal. These helpers wrap it so the SAFE form is also the SHORT form,
# and so the failure message stays bounded — the incident that produced this
# spec printed a FAIL line with 46 KB of findings after `got:`.
#
# NOT a replacement for assert_contains / assert_not_contains. Those grep a
# FILE, with no pipe, and are not affected by this defect. The `payload` in the
# name is the distinction: these take a STRING already in a variable.
#
# This file is a PURE library: no `set -u`, no `set -e`, no `cd`, no test
# execution. It is only ever sourced. bash-3.2 / Windows-Git-Bash safe: no
# `declare -A`, no `mapfile`, no `${var@Q}`.

# Longest payload excerpt any failure message may print. 512 B is enough to see
# the head of a findings block and short enough that a CI log stays readable.
ASSERT_PAYLOAD_PREVIEW_BYTES=512

# payload_preview <payload> — a bounded excerpt plus the TRUE total
# size, so a truncated preview can never be mistaken for the whole payload.
# `local LC_ALL=C` is load-bearing, not decoration: ${#var} counts CHARACTERS,
# so a UTF-8 findings blob would under-report its own size in a message that
# says "bytes" (measured: a 29-byte Czech string reports 20 under LANG=C.UTF-8).
# `local` restores the caller's locale on return.
#
# PUBLIC. An rc-check whose failure message prints the same findings payload
# ("the unmutated control must stay green, got: $out") has the same 46 KB
# problem without being an assertion about content, so it needs the bound
# without needing the match.
payload_preview() {
  local LC_ALL=C
  local _ap_p="$1" _ap_n="${#1}"
  if [ "$_ap_n" -le "$ASSERT_PAYLOAD_PREVIEW_BYTES" ]; then
    printf '%s' "$_ap_p"
  else
    printf '%s... [%s bytes total, truncated to %s]' \
      "${_ap_p:0:$ASSERT_PAYLOAD_PREVIEW_BYTES}" \
      "$_ap_n" "$ASSERT_PAYLOAD_PREVIEW_BYTES"
  fi
}

# _assert_payload_report <message> — hand the failure to the SUITE's own
# log_fail when it has one, so the suite's exit convention is preserved; fall
# back to stderr + return 1 for a suite that has none.
_assert_payload_report() {
  if declare -F log_fail >/dev/null 2>&1; then
    log_fail "$1"
  else
    printf 'FAIL: %s\n' "$1" >&2
  fi
  return 1
}

# An EMPTY needle matches every payload (`case "" in *""*` is true), so an
# assertion whose needle expanded to nothing would pass forever while testing
# nothing. Both helpers refuse it rather than answering it — a vacuity guard on
# the guard itself.
_assert_payload_needle_ok() {
  if [ "$#" -lt 2 ] || [ -z "$2" ]; then
    _assert_payload_report "${3:-assertion} was given an EMPTY needle — an empty needle matches everything, so this assertion could never fail (vacuous). Check the variable that produced it."
    return 1
  fi
  return 0
}

# assert_payload_contains <payload> <needle> [message]
# Pipe-free. Returns 0 on match; on miss names the needle and prints a BOUNDED
# prefix of the payload.
assert_payload_contains() {
  _assert_payload_needle_ok "$@" || return 1
  local _ap_payload="$1" _ap_needle="$2" _ap_msg="${3:-}"
  case "$_ap_payload" in
    *"$_ap_needle"*) return 0 ;;
  esac
  _assert_payload_report "${_ap_msg:-payload must contain the needle} (needle: '$_ap_needle'), got: $(payload_preview "$_ap_payload")"
}

# assert_payload_not_contains <payload> <needle> [message]
assert_payload_not_contains() {
  _assert_payload_needle_ok "$@" || return 1
  local _ap_payload="$1" _ap_needle="$2" _ap_msg="${3:-}"
  case "$_ap_payload" in
    *"$_ap_needle"*)
      _assert_payload_report "${_ap_msg:-payload must NOT contain the needle} (needle: '$_ap_needle'), got: $(payload_preview "$_ap_payload")"
      ;;
    *) return 0 ;;
  esac
}
