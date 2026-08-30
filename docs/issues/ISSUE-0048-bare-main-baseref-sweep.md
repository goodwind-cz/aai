---
id: bare-main-baseref-sweep
type: issue
number: 48
status: draft
---

# P2 backlog cluster: deslop-corpus-honesty (5 items)

## Summary
- Consolidated registry intake for 5 open P2 follow-up(s) filed against `deslop-corpus-honesty`: `fu-bare-main-baseref-sweep`, `fu-close-before-push-ordering`, `fu-test028-exitcode-not-clean`, `fu-docnumbering-logfail-aborts-suite`, `fu-close-requires-pr-before-it-exists`. Filed via batch intake (owner directive: intake all P2 clusters first, ship the highest-value ones next).

## Type
- bug

## Current Behavior
- **`fu-bare-main-baseref-sweep`**: No guard stops a NEW test or script from pinning a bare 'main' ref that silently never resolves on a pull_request checkout
  - Measured: Fourth occurrence of this exact class in this repository (TEST-024, the follow-ups suite, test-aai-spec-lint.sh, now test-aai-deslop.sh TEST-027/028); each time it was found by review or validation, not by a check, and each time the affected guard degraded to PASS or to a false reason on CI
  - Source: validation round 2 findings V-3/V-4 on spec-deslop-corpus-honesty; docs/knowledge/LEARNED.md 2026-07-19; repo-wide sweep for git show/diff/rev-parse against a literal main is out of this scope

- **`fu-close-before-push-ordering`**: The PR ceremony ordering - run close-work-item.mjs BEFORE the push, not after - is currently only a habit; nothing enforces it, so a ride can push first and then spend a round chasing framework reds that the close would have cleared.
  - Measured: Validation round 4 of this scope proved empirically that the 5 tests/skills/test-framework.sh reds are ride-caused and clear only once close-work-item.mjs has run; when the push lands first those reds are read as genuine CI failures and cost a diagnostic round every ride. Make the ordering a gate in the close ceremony (SKILL_PR step order plus a precondition check) rather than prose an agent has to remember.
  - Source: scope deslop-corpus-honesty, validation round 4, 2026-08-18; .aai/SKILL_PR.prompt.md close ceremony; .aai/scripts/close-work-item.mjs; tests/skills/test-framework.sh

- **`fu-test028-exitcode-not-clean`**: TEST-028 asserts docs-audit is clean by checking its EXIT CODE, but docs-audit exits 0 even at NEEDS-TRIAGE, so the arm is green while the audit is not clean
  - Measured: measured live: TEST-028 green while doc-numbering TEST-013, which greps for the word CLEAN, is red on the same tree; a check that reads a weaker signal than the claim it makes is the recurring defect class this repo has now hit eight times
  - Source: remediation of validation round 6 findings, deslop-corpus-honesty, 2026-08-19; observed while proving the V-1/V-2 fixes

- **`fu-docnumbering-logfail-aborts-suite`**: log_fail in tests/skills/test-aai-doc-numbering.sh calls exit 1, so the first failed assertion aborts the whole suite and every later arm silently never runs
  - Measured: measured 2026-08-19: while docs-audit is NEEDS-TRIAGE the suite aborts at TEST-013 and TEST-014 onward never execute, so a suite that appears to cover doc numbering currently reports on almost nothing, and its own coverage loss is invisible in the output
  - Source: validation round 7 of deslop-corpus-honesty, harness_note (b); reproduced in a scratchpad copy

- **`fu-close-requires-pr-before-it-exists`**: close-work-item.mjs requires --pr <N>, but the correct ceremony order runs it BEFORE the push that creates the PR, so the number must be guessed
  - Measured: the ordering is not optional (fu-close-before-push-ordering proves the framework reds only clear post-close, and fu-close-after-merge-bypasses-ci proves running it after merge bypasses required checks), so the tool forces either a guess or a wrong order; on 2026-08-19 the guess 265 happened to be right, which is luck, not procedure
  - Source: PR ceremony for CHANGE-0150, 2026-08-19; the agent read the highest existing number and stamped N+1

## Expected Behavior
- Each item's own Expected Behavior is scoped at Planning/implementation time from the measured decision text above — this intake's job is to make the cluster a numbered, trackable work item, not to pre-design the fix.

## Notes
- Registry ref: `deslop-corpus-honesty`. This intake may close some, all, or none of the member `fu-*` ids depending on what Planning finds still applies when work starts — do not assume every listed item survives triage unchanged (two sibling items in this same backlog were found already-fixed-but-not-closed today; check before implementing).
