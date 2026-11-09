---
id: release-corpus-hermetic
type: issue
number: 111
status: done
links:
  pr: []
  commits: []
---

# Release corpus measurement needs a hermetic test environment

## Summary
The independently executed SPEC-0257 Spec-AC-05 corpus failed on 2026-11-07. Two Pester assertions assumed an absent AAI_TEST_TIMEOUT, the release reader exceeded 540 seconds, the 1080-second corpus budget expired, and another linked worktree's commit invalidated the all-refs source-preservation proof.

## Type
bug

## Impact
The blocked AC has Review-By 2026-11-10 and will block repository-wide Validation PASS after that date. The owner selected a separate repair and isolated remeasurement rather than extending the obligation.

## Current Behavior
Inherited AAI_TEST_TIMEOUT=4500 changes the two tests' expected default timeout from 3000. The corpus completed ordinary in 819.580989125 seconds and interrupted rolled at 257.739127292 seconds. Another session changed refs/heads/refactor/pre-commit-checks-ps1-retire during the measurement. No product regression or causal attribution of the runtime overrun has been established.

## Expected Behavior
Pester cases establish and restore the timeout environment they require. Independent Validation measures the complete current ordinary/rolled corpus in an independent Git repository with bounded concurrency four, preserves source files/index/refs, records every reader result and host/interpreter identity, and keeps hosted timing unverified until actual CI. Close legacy Spec-AC-05 by measurement only when all readers pass.

## Steps to Reproduce
1. Set AAI_TEST_TIMEOUT=4500 and execute tests/skills/aai-win-dispatch.Tests.ps1 through the canonical wrapper and Pester.
2. Observe TEST-001 and TEST-013 expecting default-sourced 3000 but receiving env-sourced 4500.
3. Compare against the same invocation with AAI_TEST_TIMEOUT absent.

## Verification
Capture failing-before and passing-after evidence for the inherited-timeout Pester invocation, including preservation of the caller environment. Run relevant Windows fallback and PowerShell quality checks. Independently execute release-dry-run.mjs --both --jobs 4 with production reader and total budgets on a source snapshot with its own .git; record source identity and all results. Run TEST-007. Do not convert incomplete or failed corpus output into PASS.

## Constraints / Risks
No merge, main push, release, or release --confirm. No changes to other agents' worktrees. Keep production timeouts unchanged unless new evidence supports a separately recorded scope amendment. Do not weaken the source-preservation check; isolate its source repository instead. Run roles sequentially and no ledger/report writes during the corpus. This scope does not execute SPEC-0046's remaining real-Windows MV protocol; the owner chose manual execution by 2026-11-17. No secrets are referenced.

## Notes
Owner authorization: response "1" selecting separate repair and isolated remeasurement in this session. Prior immutable report: /Users/ales/Projects/aai-worktrees/spec-0257-ac05/docs/ai/reports/VALIDATION-20261107T1940Z-spec-0257-ac05.md. Prior raw JSON and log remain beside it under docs/ai/tdd/. Existing approved isolation is continued in /private/tmp/aai-release-corpus-hermetic on fix/release-corpus-hermetic. Human intake time is unknown; Planning chooses implementation strategy. Deliver a green, independently reviewed PR and report the merge checkpoint.

## Supersession (2026-11-09, owner decision option 1)
Authority: docs/decisions/DECISION-release-corpus-hermetic-scope-20261109.md. Upstream PR #543 (main c4706b80ad347a7b244c7198110bda1f3aece648) closed SPEC-0257 Spec-AC-05 with an independent final-tree corpus (digest: docs/ai/reviews/evidence-spec-0257-ac05-final-corpus-20261108.md, sha256 e98c6a22296b526378f750608675e032d62dc4757e1f588aeb075e60503545f3). SPEC-0280 Spec-AC-02 (isolated remeasurement) and Spec-AC-03 (legacy row closure) are therefore superseded; no new corpus runs and SPEC-0257 stays identical to origin/main. The "Close legacy Spec-AC-05 by measurement" expectation and the corpus Verification text above are historical for this scope. Still required: the Pester fixture isolation repairs (Spec-AC-01, Spec-AC-04), one full current-tree framework sweep by independent Validation, independent Review and a green PR. Prior 1800/3600 observations stay historical; no production-budget compliance (540/1080) is claimed.
