#!/bin/bash
export AAI_ROLE=subagent AAI_TEST_ISOLATION=0 TMPDIR=/private/tmp/aai-pr434-final-recheck-scratch AAI_PREFLIGHT_SCRATCH=/private/tmp/aai-pr434-final-recheck-scratch/fixtures
export AAI_REAP_STEP_START_EPOCH=$(date +%s)
out=/private/tmp/aai-pr-capability-preflight/docs/ai/reports/pr434-final-recheck-20261008T134948Z
bash .aai/scripts/aai-run-tests.sh node /private/tmp/aai-pr-capability-preflight/docs/ai/reports/pr434-final-validation-20261008T133306Z/adversarial.cjs /private/tmp/aai-pr434-final-recheck-scratch 007 > "$out/adversarial-reaped.log" 2>&1
result=$?
printf 'adversarial-reaped %s\n' "$result" >> "$out/exits.txt"
bash .aai/scripts/aai-reap-tests.sh >> "$out/adversarial-reaped.log" 2>&1
exit "$result"
