#!/usr/bin/env bash
set -euo pipefail
SCRIPT_PATH="${BASH_SOURCE[0]}"
case "$SCRIPT_PATH" in
  /*) ;;
  *) SCRIPT_PATH="$PWD/$SCRIPT_PATH" ;;
esac
ROOT="${SCRIPT_PATH%/*}/../.."
[[ -n "$ROOT" && "$ROOT" = /* ]] || exit 2
cd "$ROOT"
run_case() {
  local id="$1"
  if node --test --test-name-pattern="$id" tests/skills/lib/release-first.test.mjs; then
    echo "PASS $id"
  else
    echo "FAIL $id" >&2
    return 1
  fi
}
test_001() { run_case TEST-001; }
test_002() { run_case TEST-002; }
test_003() { run_case TEST-003; }
test_004() { run_case TEST-004; }
test_005() { run_case TEST-005; }
test_006() { run_case TEST-006; }
test_007() { run_case TEST-007; }
test_008() { run_case TEST-008; }
test_009() { run_case TEST-009; }
test_010() { run_case TEST-010; }
test_011() { run_case TEST-011; }
if [ "$#" -gt 0 ]; then
  if ! declare -F "$1" >/dev/null; then
    echo "Unknown selector: $1" >&2
    exit 2
  fi
  "$1"
else
  ALL_TESTS=(test_001 test_002 test_003 test_004 test_005 test_006 test_007 test_008 test_009 test_010 test_011)
  for fn in "${ALL_TESTS[@]}"; do
    "$fn"
  done
fi
