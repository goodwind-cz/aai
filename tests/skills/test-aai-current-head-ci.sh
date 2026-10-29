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
  if node --test --test-name-pattern="$id" tests/skills/lib/current-head-ci.test.mjs; then
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
test_2701() { run_case TEST-2701; }
test_2702() { run_case TEST-2702; }
test_2703() { run_case TEST-2703; }
test_2704() { run_case TEST-2704; }
test_2705() { run_case TEST-2705; }
test_2711() { run_case TEST-2711; }
if [ "$#" -gt 0 ]; then
  if ! declare -F "$1" >/dev/null; then
    echo "Unknown selector: $1" >&2
    exit 2
  fi
  "$1"
else
  ALL_TESTS=(test_001 test_002 test_003 test_004 test_2701 test_2702 test_2703 test_2704 test_2705 test_2711)
  for fn in "${ALL_TESTS[@]}"; do
    "$fn"
  done
fi
