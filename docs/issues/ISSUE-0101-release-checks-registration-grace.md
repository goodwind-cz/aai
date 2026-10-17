---
id: release-checks-registration-grace
number: 101
type: issue
status: done
user_visible: false
capability: release-command-finish
links:
  pr: []
  commits: []
---

# Release finish refuses before GitHub registers the required checks

## Summary
- `.aai/scripts/release-finish.mjs` `requiredChecks()` treats an empty required-check list as a hard refusal (`required-checks`, "No required checks reported"). Right after `gh pr create` GitHub has not yet registered the required check runs against the new head (about 2-3 s), so the list is empty and the first `/aai-release --confirm` refuses before `watch-ci.mjs` is ever reached. `watch-ci.mjs` already treats an empty list as "not registered yet" and waits.

## Type
- bug

## Impact
- Operators running `/aai-release --confirm`: most first runs end in a refusal and need a resume run, although nothing is wrong.
- Severity/priority: P2 (fail-closed, no unsafe merge; costs a manual resume). Ledger follow-up `fu-release-checks-registration-grace`, ref `release-command-finish`, source review NB-2 (release-finish.mjs:388).

## Current Behavior
- Main path (release-finish.mjs ~line 441): the pre-watch `requiredChecks()` call runs immediately after PR creation. `requiredChecks()` refuses when `gh pr checks --required` returns `[]`, and the caller also refuses when the list is empty or holds a non-pass/pending bucket.
- Only after that does it spawn `watch-ci.mjs --pr N --required`, whose empty-list handling (watch-ci.mjs ~line 154) is "no checks reported yet" and polls until `--max-wait-seconds`.
- The post-watch `requiredChecks()` call (~line 445) also refuses on an empty list, which is correct there (CI settled).

## Expected Behavior
- The pre-watch step tolerates a bounded registration window: poll for required checks to appear, with a timeout, then refuse with a named reason (for example `required-checks`, "No required checks registered within <N>s") if still empty.
- Consistent with watch-ci's empty-list semantics. Fail-closed is preserved: a genuinely empty list after the grace still refuses; failed/skipped/cancelled required checks still refuse immediately.

## Steps to Reproduce (if applicable)
1) Run `/aai-release --confirm` on a repo with required status checks, so a release PR is created.
2) Observe `release-finish.mjs` call `gh pr checks <pr> --required` within 2-3 s of `gh pr create`.
3) Result: refusal `required-checks: No required checks reported`; a second (resume) run proceeds normally.

## Verification
- Test with a stubbed `gh` that returns `[]` for the first K calls then a pending/pass list: release-finish reaches watch-ci and does not refuse.
- Stub that always returns `[]`: refusal with the named registration-timeout reason after the bounded grace (test uses a short grace override).
- Stub with a failed required check: immediate refusal, no waiting.
- Existing release-finish test suite stays green.

## Constraints / Risks
- Assumption (Planning decides): the grace is bounded (default a few tens of seconds), overridable for tests, and shares the poll interval conventions with watch-ci.
- Assumption: a branch with genuinely no required checks configured keeps today's documented behavior (refusal), only delayed by the bounded grace; Planning should confirm against the SPEC for `release-command-finish` whether that case is spec-permitted or needs a distinct reason.
- Do not weaken the post-watch settled check.
- release-finish.mjs may be hash-pinned by tests; follow the repo's re-pin procedure.
- Secrets preflight: no secret referenced.

## Notes
- Metrics: human_time_minutes null (autopilot default). No clarifying questions asked; assumptions above.
- Ledger decision on the follow-up: "fail-closed and spec-permitted; a bounded registration grace then refusal would still comply".
