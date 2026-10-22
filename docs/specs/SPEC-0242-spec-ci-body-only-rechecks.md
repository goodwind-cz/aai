---
id: spec-ci-body-only-rechecks
type: spec
number: 242
status: done
frozen_sha256: f0a93d760cd3c9b0bc3e9cfd0018ecd042fbfbeec810ba85e424f844ad9fee59
ceremony_level: 2
links:
  requirement: ci-body-only-rechecks
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Body-only PR rechecks with proven source evidence

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/CHANGE-0217-ci-body-only-rechecks.md
- Parent: docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md
- Prior contract: docs/specs/SPEC-0213-spec-post-validation-pushes-reuse-test-results.md
- Technology contract: docs/TECHNOLOGY.md

## Scope and baseline

At baseline `b2c00799dac6411e009a554124b12e8515c82363`, skill-suite subscribes to
`edited`, but ci-select only carries evidence on `synchronize`. The select job,
skill regression, native Windows seed and self-hosting smoke therefore repeat
on a body edit. Release notes already reads the event body; the aggregate gate
currently does not depend on that job. This scope adds one explicit body-reuse
mode to that existing mechanism, retaining normal selection and carry-forward.

No local Validation-policy change, broad result cache, scheduler redesign,
branch-protection change, new dependency, new runtime floor or parent-RFC
closure is included. Other workflows retain their existing triggers. Level 2
applies because no path in `protected_paths_l3` is changed; entering one requires
replanning at L3. Planning does not change implementation or create a worktree.

## Implementation strategy

- Strategy: loop
- Rationale: one bounded change crosses the existing Node selector, GitHub run/job evidence and YAML gate. Direct Node decision tests plus executable workflow seams belong in one focused implementation pass. Record behavior failures against the untouched baseline and deliberate negative controls for existing invariants; explicitly disclose when a baseline probe is retrospective rather than test-first. Per-test GREEN remains required. The actual implementation used retrospective baseline proof; no test-first chronology is claimed. No user strategy is recorded for this ref; the STATE strategy for another ref is stale.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound workflow changes and unrelated draft/index edits in the main checkout require an isolated reviewable branch. Existing ship defaults may resolve this recommendation at Preparation; Planning creates nothing.
- User decision: undecided
- Base ref: main
- Inline review scope: .github/workflows/skill-suite.yml, .aai/scripts/ci-select.mjs, tests/skills/lib/ci-body-recheck.test.mjs, tests/skills/test-aai-ci-carry-forward.sh, tests/skills/test-aai-suite-select.sh, tests/skills/test-aai-release-notes.sh, tests/skills/suite-map.yaml, docs/product/ci-test-impact-selection.md, docs/product/release-notes-gate.md, docs/analysis/ci-body-only-rechecks.md, CHANGELOG.md, docs/issues/CHANGE-0217-ci-body-only-rechecks.md, docs/specs/SPEC-0242-spec-ci-body-only-rechecks.md
- Code review: required, independent dual verdict over this explicit scope against main. No protected-path exception is granted.

## Design and boundaries

### D1: Eligibility and compatibility

Extend `.aai/scripts/ci-select.mjs`; keep pure classification/proof functions
importable there and retain its existing CLI/selector fallback. A new successful
mode is explicitly named `body-reuse`; it is not an empty selected suite set.
Only a `pull_request` `edited` event whose `changes` has exactly the `body` key,
a well-formed previous body, and a changed current body can qualify. Null is an
allowed absent body; other non-string body values are malformed. Missing changes,
unknown keys, title/base/mixed edits, and every other action are ineligible.
`ci-full` always wins. Fork PRs conservatively use ordinary validation.

Eligibility also requires complete repository, PR number, head repository/ref/SHA,
base repository/ref/SHA, current workflow identity and actual execution checkout
identity. Bind the checkout to the event head/base and to the workflow bytes being
executed. Use the same pinned checkout for all source jobs that can be reused,
including full, selected, Windows seed and smoke; a source job may not independently
resolve a moving merge ref. Different source/base/checkout/workflow inputs refuse
reuse even if the source-head string happens to match.

### D2: Evidence provenance

Query the existing read-only Actions API seam for earlier runs at the SAME head.
The qualifying run must belong to this repository, PR, branch, base and workflow,
be completed/successful, and have a complete successful source-validation job set
at one identified run attempt. Support both ordinary full mode (every expected
full shard) and ordinary selected mode (one runner or every expected selected
shard). A reuse-only run cannot anchor another reuse: require actual source jobs.
An earlier delta carry-forward run may be conservatively rejected.

Require a workflow-produced, API-readable execution-identity record from the
anchor attempt, not a PR-body claim or only the run-list `head_sha`. A successful
identity step with a strict versioned name containing the pinned checkout SHA is
one small implementation option; validate its actual checkout and expose enough
identity to reject a moved base/workflow. Old runs without that proof are not
eligible. Do not assume `pull_requests` metadata alone records the checkout used.
The full and selected plans must provide enough evidence to detect a missing
shard; 'at least one successful leg' is insufficient. Reject duplicate/conflicting
proof and missing/skipped/failed/cancelled/in-flight expected jobs. Required
source components include select, relevant skill jobs, native seed, smoke and
tracked-ignored; the prior aggregate gate and prior workflow must be successful.

Use bounded reads: at most 20 candidate runs, at most 100 jobs per response,
15-second per-request timeout, and no unbounded pagination. Incomplete pages,
missing token, permissions/rate limits, malformed JSON, network/git error,
ambiguous identity and changed attempts fall back with an explicit reason.
Bind job reads to the reported attempt and recheck run completion/attempt before
accepting it. Exclude the current run. Log run ID, attempt, URL and source/base/
checkout identity for accepted evidence; never print token or body contents.

### D3: Current checks and aggregate gate

On `body-reuse`, run `select`, `release-notes`, `tracked-ignored`, and the existing
named aggregate gate. Skip both selected variants, full matrix, native Windows
seed and self-hosting smoke. There must be zero framework or platform-regression
invocations in that path. Continue to run release notes against this event's body
and event base/head, including when the source check is reused. Body text remains
data through a file, never shell code or a decision directive.

Keep the exact required context `skill test suite (tests/skills/, via test-framework.sh)`
and the `release notes` context. Extend the aggregate dependency/verdict seam to
require the current PR release-notes job. On non-PR events its skipped result is
expected. The aggregate runs with `always()` and fails for failed selection,
missing/unknown mode, missing reuse proof, failed current checks or a missing
required source result in ordinary modes. Skipped source jobs are acceptable
only in a proven body-reuse mode. No synthetic status/check write is introduced.
Existing PR cancellation remains conservative: an edit that cancels the first
source run has no successful anchor and runs source validation again.

### D4: Test and documentation integration

Put direct built-in Node tests in `tests/skills/lib/ci-body-recheck.test.mjs` and
invoke them from the existing `aai-ci-carry-forward` suite. Add the exact path to
that suite's mapping. Reuse existing workflow extraction seams to execute actual
mode-output and aggregate run blocks; update old shape pins only when replaced
by equal or stronger behavior assertions. Keep ordinary carry-forward tests.
Update the two existing product documents and one measured report; leave RFC-0017
open. Do not introduce another `.aai` module or edit the prompt corpus in this
bounded design.

## Seams and residual risks

- S1: event payload plus server run/job data -> pure decision -> CLI mode output.
- S2: CLI output -> real workflow outputs/conditions -> zero source dispatches.
- S3: event body file -> real release-notes CLI -> current aggregate failure.
- S4: workflow checkout/plan identity -> server evidence -> next edit's decision.
- S5: Node test file -> suite-map selection -> existing framework execution.

S4 additionally requires hosted proof; local fixtures cannot attest GitHub's
payload or skip semantics. API reads are snapshots, not an atomic guarantee
against a later rerun/base move. Same checkout/workflow identity does not freeze
hosted runner images, network services or mutable action tags; this bounded mode
reuses successful source evidence, not a claim that the external environment is
immutable. Explicit `ci-full`, pushes to main, schedules and dispatch retain full
execution. Over-conservative fallback is acceptable and must be reported.

## Acceptance Criteria Mapping

| Requirement | Spec-AC | Verification and decisive observable | Evidence |
|---|---|---|---|
| AC-001, AC-003 | Spec-AC-01 | V1 TEST-001: valid body-only event accepted; every ineligible event returns ordinary mode with reason | docs/ai/tdd/ci-body-rechecks-node.log |
| AC-001, AC-003, AC-004 | Spec-AC-02 | V1 TEST-002/003: exact full and selected anchors accepted; each independently mismatched identity/result/attempt refused | docs/ai/tdd/ci-body-rechecks-node.log |
| AC-003, AC-004 | Spec-AC-03 | V1 TEST-004: CLI emits explicit mode/evidence or original ordinary selection with reason; bounded API errors never authorize reuse | docs/ai/tdd/ci-body-rechecks-cli.log |
| AC-001, AC-004 | Spec-AC-04 | V1 TEST-005: actual workflow fragments dispatch zero source jobs only for proven reuse; normal modes retain their job set | docs/ai/tdd/ci-body-rechecks-workflow.log |
| AC-002, AC-004 | Spec-AC-05 | V1 TEST-006: removing exemption from current body yields release-notes exit 1 and aggregate exit 1 despite valid source proof; valid body yields 0 | docs/ai/tdd/ci-body-rechecks-body.log |
| AC-003, AC-004 | Spec-AC-06 | V2 TEST-007: existing regression suites pass, direct tests execute through framework and exact changed Node path selects owning suite | docs/ai/tdd/ci-body-rechecks-regression.log |
| AC-005 | Spec-AC-07 | V1 TEST-008: executable evidence-contract check verifies the report declares pending H1/H2, required identity/job/time fields and the pre-merge prohibition; documentation review finds zero unsupported hosted success claims | docs/ai/tdd/ci-body-rechecks-docs.log |

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN an edit is classified the system SHALL allow only proven body-only events into reuse eligibility | done | docs/ai/reports/VALIDATION-20261021T180306Z-ci-body-only-rechecks.md | — | D1 |
| Spec-AC-02 | WHEN an anchor is considered the system SHALL require matching execution inputs and complete successful source evidence | done | docs/ai/reports/VALIDATION-20261021T180306Z-ci-body-only-rechecks.md | — | D2 |
| Spec-AC-03 | WHEN evidence is unavailable or uncertain the system SHALL report the cause and execute ordinary selection | done | docs/ai/reports/VALIDATION-20261021T180306Z-ci-body-only-rechecks.md | — | D1/D2 |
| Spec-AC-04 | WHEN reuse is proven the workflow SHALL skip all named source jobs while retaining its required gate and current checks | done | docs/ai/reports/VALIDATION-20261021T180306Z-ci-body-only-rechecks.md | — | D3 |
| Spec-AC-05 | WHEN the current body violates release-note rules the current release-notes check and aggregate SHALL fail | done | docs/ai/reports/VALIDATION-20261021T180306Z-ci-body-only-rechecks.md | — | D3 |
| Spec-AC-06 | WHEN source validation is required the existing coverage and test selection SHALL remain executable | done | docs/ai/reports/VALIDATION-20261021T180306Z-ci-body-only-rechecks.md | — | D4 |
| Spec-AC-07 | WHEN local implementation is handed off the documentation SHALL define the complete hosted evidence protocol, accurate eligibility and fallback limits, and explicitly pending delivery checks with the parent RFC open | done | docs/ai/reports/VALIDATION-20261021T180306Z-ci-body-only-rechecks.md | — | H1/H2 separately gate delivery |

## Implementation plan

1. Write direct decision and proof tests; observe RED against the original behavior. Export minimal pure helpers from ci-select and keep effects in its current adapter.
2. Add strict same-head proof lookup, source identity publication and explicit CLI mode. Preserve synchronize carry-forward and ordinary selection output.
3. Pin source-job checkouts; wire body mode, source conditions, current release notes and fail-closed aggregate. Execute extracted workflow fragments in tests with realistic fixtures.
4. Register direct tests in the existing suite and map; run targeted regression and independent negative controls. Prepare product wording and a report that distinguishes pending hosted evidence.
5. After PR creation, obtain H1/H2; independently verify actual run attempts, jobs and logs, then finalize measured documentation and completion evidence. Do not call pending hosted evidence a completed acceptance criterion.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Status |
|---|---|---|---|---|---|
| TEST-001 | Spec-AC-01 | unit | tests/skills/lib/ci-body-recheck.test.mjs | Body-only classification, null/string bodies, missing/mixed/unknown changes, non-edit events, ci-full, fork and malformed identity | pending |
| TEST-002 | Spec-AC-02 | unit | tests/skills/lib/ci-body-recheck.test.mjs | Positive full, selected single and selected sharded anchors; one-field head/base/repo/PR/workflow/checkout mismatches, legacy/reuse/delta evidence refusal | pending |
| TEST-003 | Spec-AC-02 | unit | tests/skills/lib/ci-body-recheck.test.mjs | Missing/duplicate/conflicting jobs, omitted shard, skipped/failed/cancelled/in-flight jobs, wrong or changing attempt, failed workflow and current-run rejection | pending |
| TEST-004 | Spec-AC-03 | integration | tests/skills/lib/ci-body-recheck.test.mjs | Real CLI using exact-request API fixtures and tiny Git context: output mode/evidence, fallback byte compatibility, 403/429/malformed/incomplete/timeout/no-token paths and bounded reads | pending |
| TEST-005 | Spec-AC-04 | integration | tests/skills/lib/ci-body-recheck.test.mjs | Consume real selector output in workflow mode block and evaluate real job conditions; execute actual aggregate block across ordinary/reuse/missing-proof/error cases and checkout pins | pending |
| TEST-006 | Spec-AC-05 | integration | tests/skills/lib/ci-body-recheck.test.mjs | Real release-notes CLI with shipped-file fixture and no added notes: valid exemption to blank/removed exemption, shell-looking body stays data, actual aggregate rejects current failure | pending |
| TEST-007 | Spec-AC-06 | integration | tests/skills/test-aai-ci-carry-forward.sh | Framework runs direct cases; exact-path mapping, synchronize carry-forward, selected scheduling, ordinary gate and release-note regressions remain green | pending |
| TEST-008 | Spec-AC-07 | integration | tests/skills/lib/ci-body-recheck.test.mjs | Check report evidence schema/protocol and pending status before hosted execution; independently review current product eligibility/fallback text and open RFC | pending |

### RED observations and negative controls

Before implementation, TEST-001/002/004/005 demonstrate absence of a working
body-reuse mode; TEST-006 demonstrates the old aggregate can ignore a failed
release-notes result; TEST-007 demonstrates the new direct file is not registered.
TEST-003 must be observed failing against a deliberately weakened proof predicate
in the dispatch scratch copy, with an otherwise eligible positive control first.
For TEST-008 observe missing protocol/report fields before implementation and
remove a required evidence field in a scratch negative control. For H1/H2 verify
the intake's cited pre-change body-edit source executions, or obtain a fresh
baseline, before claiming the zero-repeat improvement. Record commands, observed assertions and
identities in the per-AC logs. Storage of RED is optional for loop, but the RED
observation itself is not. A missing import is preliminary wiring failure, not
proof that a negative identity/result assertion is sensitive.

Independent Validation must remove the base/checkout equality, accept one failed
source job, omit an expected shard, and bypass current-body failure in separate
scratch mutations. Each must redden its named assertion; always prove the valid
case reaches the decision first. No mutation touches the shipping tree.

## Verification

V1: `bash .aai/scripts/aai-run-tests.sh node --test tests/skills/lib/ci-body-recheck.test.mjs`
returns 0, all TEST-001..006 and TEST-008 groups execute with zero failed/skipped groups. Use
`--test-name-pattern` for focused RED runs and record the exact runtime version.
Support the workflow's Node 20 without introducing a new runtime requirement.

V2: `AAI_TEST_PARALLEL=1 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh --skill aai-ci-carry-forward --skill aai-suite-select --skill aai-release-notes`
returns 0; record suite counts and any skips. Run selector-derived impacted/core
checks required by the current Validation canon; this spec does not waive or
rewrite that policy. Newly added direct groups must have zero skips.

H1 (post-PR, pre-merge): obtain one completed successful ordinary skill-suite run
on the final candidate source, using the new identity publication. Because this
ride edits the workflow, expect normal full selection. Capture run metadata and
all attempt jobs with read-only `gh api repos/goodwind-cz/aai/actions/runs/<run-id>`
and `gh api repos/goodwind-cz/aai/actions/runs/<run-id>/attempts/<attempt>/jobs?per_page=100`;
retain complete pagination if present and relevant select/source logs. Verify
all expected source components ran successfully, including Windows and smoke.

H2 (post-PR, pre-merge): edit only the PR body while preserving valid content and
wait for completion, then make one further harmless body-only edit. Both runs
must use the same head/base/checkout/workflow identity as H1, retain the required
check names and finish current checks/aggregate successfully, execute zero skill
framework/native-seed/smoke jobs, and cite H1 as actual source evidence rather
than chaining reuse. Capture full metadata/job lists and decision logs. If the
base moves, repeat H1 at the new identity; do not mix trees for measurement.

Record run URLs/IDs/attempts, source/base/checkout SHAs, job conclusions, actual
executed source-job count (H1 greater than zero; H2 exactly zero), and observed
sum of job durations/wall time for each run. Disclose skips, cancellations,
queue time and unavailable billing fields. This is an observed work-avoidance
claim, not a statistical speed or monetary guarantee. Do not infer token savings.

### Lifecycle ordering and delivery boundary

All seven implementation Spec-AC and TEST-001..008 are locally verifiable.
Pre-PR Validation must establish their full evidence chain, including actual
report/protocol checks for Spec-AC-07, and explicitly record H1/H2 as PENDING
DELIVERY CHECKS. Then independent review and the normal SKILL_PR close-before-push
sequence may run. This is the boundary already documented in
`docs/specs/SPEC-0239-spec-selected-ci-scheduling-foundation.md`, Amendment — local
acceptance and hosted delivery checks; it does not authorize a draft-PR bypass
or waive a Validation/Review gate. Closing implementation documents records local
implementation acceptance, not fulfillment of intake AC-005's hosted requirement.

After normal PR creation the orchestrator obtains H1/H2 and an independent
validator verifies their raw evidence before any delivery-complete, merge-ready
or parent-rollout claim. Keep both obligations visible in the PR and report until
fulfilled. Missing evidence remains pending; failed evidence enters remediation.
If host/API behavior prevents proof, report that delivery blocker and retain
conservative source execution; do not weaken D2. RFC-0017 stays open throughout.

## Amendment — local acceptance and hosted delivery checks

The initial freeze placed hosted TEST-008 inside the implementation acceptance
table. That ordering could not truthfully satisfy SKILL_PR's Validation PASS
precondition before a PR existed. This amendment makes Spec-AC-07/TEST-008 the
local documentation and evidence-protocol contract, and retains H1/H2 as separate
mandatory post-PR, pre-merge delivery checks. It changes the lifecycle boundary,
not the required hosted outcomes, and is disclosed with signoff none.

## Evidence contract

Every artifact records ref `ci-body-only-rechecks`, Spec-AC/TEST IDs, actual
command and exit code, source SHA/diff, and evidence path. Loop evidence is
per-test GREEN plus observed RED and independent negative controls. Logs live
under `docs/ai/tdd/ci-body-rechecks-*.log`; the tracked measured report is
`docs/analysis/ci-body-only-rechecks.md`. Validation's authoritative report uses
`aai-outcome-v1` and is returned consistently as `outcome_report` and
`set-validation --evidence`. No implementation PASS or hosted result is claimed
by this planning document.

## Registry review

Adjacent open items remain outside this scope: fu-watchdog-3000-exceeds-ci-timeout
concerns timeout policy; fu-lib-graph-narrowing-after-sharding concerns shared-lib
impact; fu-framework-discover-exit-swallowed concerns framework discovery;
fu-shard-check-regex-arm-unpinned and fu-shard-check-twin-basename concern shard
checker inputs; fu-suite-select-pin-product-docs concerns another mapping;
fu-tracked-ignored-rev-cat-file-batch concerns tracked-ignored performance;
fu-sync-seed-cache-no-ci-gain concerns sync fixture timing. They do not authorize
body reuse and are not repaired by skipping identical validated source work.
Registry items closed by this scope: none.
