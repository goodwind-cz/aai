#!/usr/bin/env bash
set -euo pipefail

passed=0
failed=0
declare -a passed_tests=()
declare -a failed_tests=()

for t in tests/remote-orchestration/test-*.sh; do
  test_name="$(basename "$t")"
  if [[ "$test_name" == "test-lib.sh" ]]; then
    continue
  fi
  printf '[RUN ] %s\n' "$test_name"
  if bash "$t"; then
    printf '[ OK ] %s\n' "$test_name"
    passed=$((passed + 1))
    passed_tests+=("$test_name")
  else
    printf '[FAIL] %s\n' "$test_name" >&2
    failed=$((failed + 1))
    failed_tests+=("$test_name")
    break
  fi
done

printf '\nValidation summary\n'
printf '  Passed: %d\n' "$passed"
printf '  Failed: %d\n' "$failed"

if [[ "${#passed_tests[@]}" -gt 0 ]]; then
  printf '  OK:\n'
  for test_name in "${passed_tests[@]}"; do
    printf '    - %s\n' "$test_name"
  done
fi

if [[ "${#failed_tests[@]}" -gt 0 ]]; then
  printf '  Failed tests:\n' >&2
  for test_name in "${failed_tests[@]}"; do
    printf '    - %s\n' "$test_name" >&2
  done
  exit 1
fi
