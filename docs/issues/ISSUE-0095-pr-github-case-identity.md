---
id: pr-github-case-identity
type: issue
number: 95
status: done
links:
  spec: spec-pr-github-case-identity
  parent: pr-capability-preflight
  pr:
    - 434
  commits:
    - bddaa7657ac0c92dc22f0bc25d4bff7df22cf91c
---

# Compare GitHub repository identity without case sensitivity

## Summary
Repair sealed review B2 as a separate existing-requirement child of pr-capability-preflight, authorized by docs/decisions/DECISION-pr434-identity-split.md. Parent contract: docs/specs/SPEC-0210-spec-pr-capability-preflight.md (AC-001 and AC-005; parent Spec-AC-01 and Spec-AC-05). No new capability.

## Type
bug

## Impact
BLOCKING P2 correctness: the PR readiness identity boundary produces the wrong disposition. This item implements only B2.

## Current Behavior
Origin/input Org/Repo with successful provider nameWithOwner org/repo and URL https://github.com/org/repo runs three probes then returns exit 3 / PROVIDER_RESULT_INVALID. Input differing only by casing from the origin is also refused.

## Expected Behavior
Owner/repository spelling differing only by ASCII case is the same GitHub identity for input/remote and provider-result comparison. Different owner or repository, host, protocol, userinfo, query and fragment remain refused. Effective fetch/push strings remain exactly equal.

## Steps to Reproduce
Use the real disposable Git/provider fixture described in docs/ai/reviews/review-20261008T023456Z-pr434-scp.md section B2, source 1691558c034e13258a31b8288df5642f6263a8cb. Immutable retained counterexamples and positive controls: docs/ai/reviews/pr434-scp-20261008T023456Z/probe.cjs, probe.log and probe-results.json; audit.json and manifest.json bind the retained review. These are cited, not copied or claimed rerun.

## Verification
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-preflight.sh test_001`: focused TEST-001 assertions described in docs/specs/SPEC-0212-spec-pr-github-case-identity.md, exit 0 after behavioral RED.
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-preflight.sh test_007`: focused TEST-007 assertions described in docs/specs/SPEC-0212-spec-pr-github-case-identity.md, exit 0 after behavioral RED.
- Full current parent matrix, native platform runs and final assembly gates remain separately owed.

## Constraints / Risks
Minimal cause change in .aai/scripts/pr-preflight.mjs and focused additions to existing tests/skills/test-aai-pr-preflight.sh. Shared Node matrix is extracted by tests/skills/aai-pr-preflight.Tests.ps1; preserve its delimiter and native compatibility. No provider writes, secrets acquisition, new dependencies, new vendored files or prompt growth. Exact effective fetch/push equality is invariant. Preserve parent evidence and staged dependencies. Existing authorized worktree only; root owns dedicated branch, STATE and ledgers. Work sequentially, never run tests concurrently with report production. No local secret reference is introduced.

## Notes
Strategy tdd is explicitly required by this dispatch. Owner intake time is unavailable; no estimate. Durable slug is the primary identity; root allocates draft numbers before commit if applicable. This child does not reset the parent review cap, close it, or assert Validation/Review PASS.
