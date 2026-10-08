---
id: pr-generic-url-validity
type: issue
number: 94
status: implementing
links:
  spec: spec-pr-generic-url-validity
  parent: pr-capability-preflight
  pr: []
  commits: []
---

# Refuse malformed scheme URLs before generic readiness

## Summary
Repair sealed review B1 as a separate existing-requirement child of pr-capability-preflight, authorized by docs/decisions/DECISION-pr434-identity-split.md. Parent contract: docs/specs/SPEC-0210-spec-pr-capability-preflight.md (AC-001 and AC-005; parent Spec-AC-01 and Spec-AC-05). No new capability.

## Type
bug

## Impact
BLOCKING P2 correctness: the PR readiness identity boundary produces the wrong disposition. This item implements only B1.

## Current Behavior
Identical effective fetch/push `https://github.com:bad/Org/Repo.git` returns exit 0 / CAPABILITY_NOT_APPLICABLE with zero provider calls although real Git rejects the malformed port.

## Expected Behavior
Malformed explicit scheme URLs return exit 2 / IDENTITY_INVALID before generic success or provider calls. Lawful unrecognized-host URLs and explicit local mode retain CAPABILITY_NOT_APPLICABLE.

## Steps to Reproduce
Use the real disposable Git/provider fixture described in docs/ai/reviews/review-20261008T023456Z-pr434-scp.md section B1, source 1691558c034e13258a31b8288df5642f6263a8cb. Immutable retained counterexamples and positive controls: docs/ai/reviews/pr434-scp-20261008T023456Z/probe.cjs, probe.log and probe-results.json; audit.json and manifest.json bind the retained review. These are cited, not copied or claimed rerun.

## Verification
- TEST-001 behavioral RED/GREEN: `docs/ai/tdd/spec-pr-generic-url-validity/red-TEST-001.log` and `green-TEST-001.log`; mutation record `docs/ai/tdd/spec-pr-generic-url-validity/mutation-TEST-001.txt`.
- TEST-007 behavioral RED/GREEN: `docs/ai/tdd/spec-pr-generic-url-validity/red-TEST-007.log` and `green-TEST-007.log`; mutation record `docs/ai/tdd/spec-pr-generic-url-validity/mutation-TEST-007.txt`.
- Full shared eight-row Bash matrix: `docs/ai/tdd/spec-pr-generic-url-validity/full8row.log`, exit 0. Native platform runs and final assembly gates remain separately owed.

## Constraints / Risks
Minimal cause change in .aai/scripts/pr-preflight.mjs and focused additions to existing tests/skills/test-aai-pr-preflight.sh. Shared Node matrix is extracted by tests/skills/aai-pr-preflight.Tests.ps1; preserve its delimiter and native compatibility. No provider writes, secrets acquisition, new dependencies, new vendored files or prompt growth. Exact effective fetch/push equality is invariant. Preserve parent evidence and staged dependencies. Existing authorized worktree only; root owns dedicated branch, STATE and ledgers. Work sequentially, never run tests concurrently with report production. No local secret reference is introduced.

## Notes
Strategy tdd is explicitly required by this dispatch. Owner intake time is unavailable; no estimate. Durable slug is the primary identity; root allocates draft numbers before commit if applicable. This child does not reset the parent review cap, close it, or assert Validation/Review PASS.
