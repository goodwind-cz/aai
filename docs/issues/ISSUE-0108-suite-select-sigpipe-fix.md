---
id: suite-select-sigpipe-fix
type: issue
number: 108
status: done
links:
  pr: []
  commits: []
---

# test-aai-suite-select.sh TEST-016 fails intermittently on CI with printf EPIPE under pipefail

## Summary
- `tests/skills/test-aai-suite-select.sh` `test_1760_weights_provenance` (TEST-016) feeds the weights header to early-exiting readers (`printf '%s\n' "$header" | awk '... exit'`). Under `set -euo pipefail` on the CI runner, which ignores SIGPIPE, a reader that exits before printf finishes makes printf fail with `printf: write error: Broken pipe` and the suite fails.
- Seen on PR #525, run 41440642523, job 125261551064 (https://github.com/goodwind-cz/aai/actions/runs/41440642523/job/125261551064); it passed on rerun. Follow-up `fu-suite-select-sigpipe-test016` records it.

## Type
- bug

## Impact
- Intermittent CI red on unrelated PRs, one rerun each. Internal test only (tests/skills is not shipped downstream). Severity P3.

## Current Behavior
- Lines 1940 and 1943 of the suite pipe a printf into `awk ... exit`. The race is timing dependent; the header is small, so most runs pass.

## Expected Behavior
- No reader in this suite exits before its writer has finished; every assertion keeps its meaning. A deterministic test pins the property under ignored SIGPIPE with an oversized header.

## Steps to Reproduce (if applicable)
1) `bash -c 'set -euo pipefail; trap "" PIPE; h=$(seq 1 200000 | sed "s/^/# /"); r=$(printf "%s\n" "$h" | awk "/^# 1\$/ {print; exit}")'` prints `printf: write error: Broken pipe` and exits 1 under bash 3.2/5.

## Verification
- `env -u AAI_ROLE bash tests/skills/test-aai-suite-select.sh` exit 0, and the new test passes with the fix and fails on the baseline pipeline form.

## Constraints / Risks
- Test-only. Other suites with the same pipe shape are out of scope and listed in the spec.
