---
id: spec-pr-generic-url-validity
type: spec
number: 211
status: done
mutation_gate: v1
frozen_sha256: c544471bb969bb4773d86e8420e6df901f3d5f545a67a7c5281b2a90926f2c26
ceremony_level: 1
links:
  requirement: pr-generic-url-validity
  parent: spec-pr-capability-preflight
  rfc: null
  pr:
    - 434
  commits:
    - 6d3f616a96337ff1580968467fadfa9756a87a52
---

# Refuse malformed scheme URLs before generic readiness

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/ISSUE-0094-pr-generic-url-validity.md; existing parent docs/specs/SPEC-0210-spec-pr-capability-preflight.md, AC-001 and AC-005; parent Spec-AC-01 and Spec-AC-05.
- Owner decision: docs/decisions/DECISION-pr434-identity-split.md.
- Sealed counterexample: docs/ai/reviews/review-20261008T023456Z-pr434-scp.md, B1; immutable reviewed source 1691558c034e13258a31b8288df5642f6263a8cb.
- Evidence pointers: docs/ai/reviews/pr434-scp-20261008T023456Z/probe.cjs, probe.log, probe-results.json, manifest.json; current parent eight-row Test Plan and shared native matrix.
- Technology contract: docs/TECHNOLOGY.md.
- Registry items closed by this scope: none.
- fu-amend-spec-pr-capability-preflight remains open: child repair does not sign or discharge parent semantic amendment debt. fu-azure-live-proof-on-adoption remains open: no live provider round trip is in scope.

Ceremony justification: one existing production identity boundary and two focused rows in its existing integration suite; reversible cause fix, no protected_paths_l3 surface, no capability addition. Independent Validation and dual-verdict Review remain required. Parent full integration gates are unchanged.

## Implementation strategy
- Strategy: tdd
- Rationale: dispatch requires behavioral RED first for the independently reproduced identity defect, positive/negative controls and minimal source repair. No matching intake-sourced child strategy exists in current STATE.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: reuse the owner's already authorized /private/tmp/aai-pr-capability-preflight worktree sequentially; no new worktree. Experiments use one private absolute scratch copy specified by the implementation dispatch.
- User decision: worktree
- Base ref: 1691558c034e13258a31b8288df5642f6263a8cb
- Worktree branch/path: root creates fix/pr-generic-url-validity after handoff in /private/tmp/aai-pr-capability-preflight; second child branch base must be the root-confirmed first-child integration head.
- Inline review scope: .aai/scripts/pr-preflight.mjs tests/skills/test-aai-pr-preflight.sh docs/issues/ISSUE-0094-pr-generic-url-validity.md docs/specs/SPEC-0211-spec-pr-generic-url-validity.md, child brief and child-scoped evidence only; pin base/head for each child. Exclude staged parent dependencies from child delivery claims.
- Code review required: true.

## Scope
Repair only B1. Source/test delivery paths are .aai/scripts/pr-preflight.mjs and tests/skills/test-aai-pr-preflight.sh. Planning owns only the child intake/spec/brief and planning companions. No parent capability duplication, source change in Planning, parent closure, cap reset, provider operation or ledger mutation. The parent frozen spec and historical evidence remain immutable during Planning. Root records semantic amendments with signoff none; no owner signature is inferred from split authorization.

## Acceptance Criteria Mapping
All commands run from repository root, serially. Each executes the real CLI through disposable Git repositories and strict provider fixtures, crossing the real input/remote/result seams rather than mocked parser boundaries.

| Requirement | Spec-AC | Verification | Observable and evidence |
|-------------|---------|--------------|-------------------------|
| AC-001 and AC-005; parent Spec-AC-01 and Spec-AC-05 / B1 | Spec-AC-01 | `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-preflight.sh test_001` | Assertions in the named TEST row decide the stated exit, JSON code and provider count; raw RED/GREEN stdout/stderr in docs/ai/tdd/pr-generic-url-validity-red.log and pr-generic-url-validity-green.log |
| Parent exact destination binding and lawful route preservation | Spec-AC-02 | `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-preflight.sh test_007` | Lawful-route positive, intended refusal negatives, exact argv and provider counts decide preservation; same scoped logs |

## Constitution deviations
None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN an effective remote uses explicit scheme syntax with an invalid nonnumeric port, the CLI SHALL return exit 2 / IDENTITY_INVALID and zero provider calls instead of generic success. | done | `docs/ai/tdd/spec-pr-generic-url-validity/green-TEST-001.log`; `docs/ai/tdd/spec-pr-generic-url-validity/mutation-TEST-001.txt` | — | TEST-001 behavioral RED and mutation replay are recorded; independent Validation and Review remain outstanding |
| Spec-AC-02 | WHEN a valid unrecognized-host URL or explicit remote_name null is supplied, the CLI SHALL return exit 0 / CAPABILITY_NOT_APPLICABLE with zero provider calls; malformed port and destination divergence SHALL refuse before providers. | done | `docs/ai/tdd/spec-pr-generic-url-validity/green-TEST-007.log`; `docs/ai/tdd/spec-pr-generic-url-validity/full8row.log`; `docs/ai/tdd/spec-pr-generic-url-validity/mutation-TEST-007.txt` | — | TEST-007 behavioral RED and mutation replay are recorded; independent Validation and Review remain outstanding |

## Implementation plan
At the remote identity boundary, distinguish explicit scheme syntax whose URL parse fails from a successfully parsed URL with an unrecognized host. Inspect the effective endpoint before sanitization or fallback can conceal invalid syntax. Keep generic support, SCP/local handling, existing credential redaction and provider-specific validation; do not apply GitHub path/protocol restrictions to all generic hosts.

Extend existing TEST-001 and TEST-007 only; keep their IDs and registration in the Bash and extracted native Node matrix. Adjust strict stub response controls and expected exact argv only as needed for these cases; deny unrelated commands/flags/values. Assert the real provider call count on positives and negatives after probes, never infer safety from an empty log without a reached positive. Assert generic/local zero-provider success separately from zero-provider refusal. Source repair follows observed behavioral RED, not fixture/infrastructure errors.

Seams: real Git effective fetch/push bytes -> identity parser -> provider classification; input repository -> resolved remote identity; allowlisted provider response -> final JSON disposition; Bash matrix -> native Pester extraction. The first three are exercised by TEST-001/007; native execution is a parent final integration obligation, not attested by local Bash. No remote endpoint availability, future create permission or arbitrary agent obedience is claimed.

## Test Plan
Each File path names an existing artifact; its Description supplies a directly executable command. Two integration rows; IDs intentionally reuse the corresponding parent/suite IDs and are not renumbered.

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---------|---------|------|----------------------|-------------|----------|--------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-pr-preflight.sh | `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-preflight.sh test_001`; Extend existing TEST-001 with real Git configured equal malformed fetch/push https://github.com:bad/Org/Repo.git and https://gitlab.com:bad/Org/Repo.git; assert effective bytes equal seeded bytes, exit 2 IDENTITY_INVALID and zero provider calls. Include a lawful GitHub control reaching all three exact allowlisted calls and divergent effective endpoints refusing at git.push-destination. | patch:docs/ai/tdd/spec-pr-generic-url-validity/mutation-TEST-001.patch | green |
| TEST-007 | Spec-AC-02 | integration | tests/skills/test-aai-pr-preflight.sh | `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-preflight.sh test_007`; Extend existing TEST-007 with valid https://gitlab.com/Org/Repo.git generic control and equal generic URL with numeric port 8443; both exit 0 CAPABILITY_NOT_APPLICABLE and zero provider calls. Retain credential/query/fragment redaction and explicit local-null positive; malformed unknown-host port refuses. | patch:docs/ai/tdd/spec-pr-generic-url-validity/mutation-TEST-007.patch | green |

## Verification
- Focused commands: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-preflight.sh test_001` and `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-preflight.sh test_007`, both exit 0 with named PASS records after the fixture assertions execute.
- RED first: TEST-001 malformed github.com:bad fixture must fail on the immutable pre-change source because observed exit is 0 rather than 2. TEST-007 malformed gitlab.com:bad fixture must likewise fail while valid generic/local controls succeed. Record both focused row outcomes under docs/ai/tdd/pr-generic-url-validity-red.log, with command, ref_id, AC/TEST IDs, pre-change SHA/hash, exit and failing assertion. Run new assertions against the pre-change source in the single dispatched scratch copy; second child uses its actual branch base and also cites the immutable parent counterexample. Never mutate or restore a tracked shipping file to establish RED.
- GREEN: docs/ai/tdd/pr-generic-url-validity-green.log records the same commands and newly repaired tree, provider counts, exact argv/host controls and observables. Refusal exit code is the inner CLI's; focused suite exit is 0 when the assertion succeeds. Infrastructure errors are not product RED.
- Mutations: TEST-001 patch must remove only the new malformed explicit scheme refusal, leaving program parseable; TEST-007 patch must remove only the new malformed unknown-host scheme refusal, leaving lawful generic controls reachable. Produce exact patches in the disposable copy and use `node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-0211-spec-pr-generic-url-validity.md`; expect exit 0, two intended behavioral RED records and no inconclusive/syntax-only result. Records only at docs/ai/tdd/spec-pr-generic-url-validity/mutation-TEST-001.txt and mutation-TEST-007.txt. Mutation patch bytes are not claimed tested at Planning.
- After each child, independent scoped Validation and dual-verdict Review. Root integrates only checked child changes, sequentially. Parent final assembly Review, authorized metadata-only close/generated reconciliation, source-bound native/full CI, independent Validation and external sweep remain owed. No child PASS substitutes for those gates.

## Evidence contract
Record child ref_id, Spec-AC/TEST IDs, full executable command, exit, sanitized raw output path, base/head hashes and observed provider-call controls. Stored behavioral RED per both gating rows plus focused GREEN and checked mutation replay are required by tdd. Keep immutable parent failures/manifests via pointers; do not copy the corpus or overwrite prior evidence. Validation emits one checked aai-outcome-v1 report and returns its exact outcome_report and matching set-validation evidence path. Review uses explicit child paths and pinned base/head.

### Evidence by strategy
Tdd: stored RED/GREEN artifacts for TEST-001 and TEST-007, the shared eight-row suite result and two behavioral mutation replays. Independent Validation and Review, native Windows proof, and final parent assembly gates remain outstanding.

## Amendment debt
Parent detailed equality wording must reflect the existing provider identity semantics and malformed-scheme refusal. Root records the child-specific semantic amendment against docs/specs/SPEC-0210-spec-pr-capability-preflight.md via spec-amend.mjs add with --class contract --signoff none. Existing filed fu-amend-spec-pr-capability-preflight remains open; no fake signature, parent cap reset or parent evidence rewrite. Each child may update only its own planned contract through the canonical amendment mechanism if it grows after freeze.
