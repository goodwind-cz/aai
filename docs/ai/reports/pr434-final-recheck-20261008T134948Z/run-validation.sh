#!/bin/bash
set -u
export AAI_ROLE=subagent AAI_TEST_ISOLATION=0 TMPDIR=/private/tmp/aai-pr434-final-recheck-scratch AAI_PREFLIGHT_SCRATCH=/private/tmp/aai-pr434-final-recheck-scratch/fixtures AAI_TEST_TIMEOUT=300
out=/private/tmp/aai-pr-capability-preflight/docs/ai/reports/pr434-final-recheck-20261008T134948Z
for task in preflight parent-replay generic-replay case-replay; do
  export AAI_REAP_STEP_START_EPOCH=$(date +%s)
  case "$task" in
    preflight) args=(bash tests/skills/test-aai-pr-preflight.sh);;
    parent-replay) args=(node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-0210-spec-pr-capability-preflight.md);;
    generic-replay) args=(node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-0211-spec-pr-generic-url-validity.md);;
    case-replay) args=(node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-0212-spec-pr-github-case-identity.md);;
  esac
  bash .aai/scripts/aai-run-tests.sh "${args[@]}" > "$out/$task.log" 2>&1
  result=$?
  printf '%s %s\n' "$task" "$result" >> "$out/exits.txt"
  bash .aai/scripts/aai-reap-tests.sh >> "$out/$task.log" 2>&1
 done
