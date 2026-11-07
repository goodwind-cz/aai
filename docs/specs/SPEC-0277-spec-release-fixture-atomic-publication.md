---
id: spec-release-fixture-atomic-publication
type: spec
number: 277
status: done
mutation_gate: v1
frozen_sha256: bcb96cf4ca1f69cc831d5e63b7e989878099748572707c19d921a3a56dc9b4d2
ceremony_level: 2
links:
  requirement: release-fixture-atomic-publication
  rfc: null
  pr:
    - 538
  commits: []
---

# Release fixture atomic transport publication

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/ISSUE-0110-release-fixture-atomic-publication.md
- Decision records: docs/decisions/DECISION-release-fixture-atomic-publication.md
- Technology contract: docs/TECHNOLOGY.md

## Implementation strategy

- Strategy: tdd
- Rationale: A known cross-process truncate/read race has a deterministic reproduction. Establish a failing publication-boundary regression before replacing the fixture publishers; retain original recovery assertions and verify the actual rolled-reader envelope.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: Independent PR repair with process-kill experiments; isolate it from the owner's main and cloudflare worktrees.
- User decision: worktree (already authorized; no further decision needed)
- Base ref: origin/main at bd519bb
- Worktree branch/path: codex/release-fixture-atomic-publication at /private/tmp/aai-release-fixture-atomic-publication
- Review required: true
- Review scope: tests/skills/test-aai-release.sh; this spec; docs/issues/ISSUE-0110-release-fixture-atomic-publication.md; docs/decisions/DECISION-release-fixture-atomic-publication.md; docs/specs/SPEC-0245-spec-docs-audit-suite-speed.md deadline-only companion; exact accompanying append-only decision/event records.

L2 is appropriate because publication and concurrent process recovery share a fixture protocol with release dry-run reader discovery. No protected L3 path is changed. The deadline-only companion preserves its approved contract and does not change runtime behavior.

## Acceptance Criteria Mapping

- Maps to: intake AC-001, AC-002, AC-003.
- Spec-AC-01: WHEN a release fixture transport snapshot is published concurrently with a reader, the fixture SHALL expose a complete previous or next JSON snapshot through every writer, and the existing actual-SIGKILL case SHALL still resume one journal with exactly one PR and one merge.
- Verification: the deterministic boundary regression in `tests/skills/test-aai-release.sh` exercises both stub entry logging and `save()` while the parent parses the real transport path; every held-boundary read parses and equals the previous complete snapshot, and after publication it equals the complete next snapshot. Existing `TEST-021` must report actual SIGKILL and retain its same-head journal, one PR, one merge, claim/reclaim cleanup and foreign-host refusal assertions. The full release suite and rolled-reader rehearsal must exit 0 without parse-error recovery.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN fixture publication overlaps a real transport reader the fixture SHALL expose only complete snapshots and preserve actual-SIGKILL single-journal recovery | done | docs/ai/tdd/release-fixture-atomic-publication-green-final-selected.log; docs/ai/tdd/spec-release-fixture-atomic-publication/mutation-TEST-001.txt | — | Entry/save and actual SIGKILL pass; ordinary/rolled rehearsal 58/58 pass (docs/ai/reports/release-fixture-dry-run-r2.json). Aggregate Validation FAIL is preserved in docs/ai/reports/VALIDATION-release-fixture-atomic-publication.md; owner exception: docs/decisions/DECISION-release-fixture-validation-exception.md; current-head Linux CI required |

## Implementation plan

1. Inventory every transport writer in `test_700_one_command_finish`, including the initial seed, stub entry call-log, stub `save()`, historical/remote helpers, scenario setup and the inline recut subprocess publisher. Use one dependency-free fixture publication primitive, serializable into the generated stub where needed, that writes a unique sibling then atomically renames it over the destination. Preserve JSON schema and clean temporary siblings after errors where possible; fail visibly on publication errors.
2. Before changing publication behavior, add deterministic coverage inside the existing release suite. Prefer the existing `TEST-021` branch, or a narrowly selectable branch in the same `test_700` heredoc if separation improves attribution. A reader must run in a different process from the writer. A file handshake holds the real writer after opening its output but before completing publication. Assert a finite number of reads at that exact boundary, then release and assert the next complete snapshot. Cover entry logging and save separately; waits are bounded and establish ordering rather than probabilistic stress. Use the same writer primitive the fixture actually invokes. No copied substitute writer or only source-text assertion counts.
3. The RED control uses the old direct-to-destination publication with the same boundary instrumentation. Observe the empty/partial read deterministically, store the failure, then repair the publisher. For mutation replay restore direct destination writing at the shared publication primitive in a scratch copy, retaining the handshake. Do not insert delays into normal fixture execution or add parser catches/retries.
4. Audit writer ownership: initialization and parent scenario edits happen before child invocation or after its completion; entry logging and subsequent save within one invocation use one snapshot. Document any exception and serialize only a demonstrated concurrent-writer conflict. Atomic rename guarantees coherent reads, not concurrent read-modify-write merge semantics. Existing simultaneous-confirm and SIGKILL cases must continue to verify their actual writer ordering; do not claim arbitrary multiwriter linearizability.
5. Keep the real shell owner SIGKILL and all existing recovery assertions. Integrate regression into existing suite execution and selected invocation, without a new suite. Check function registration and release-dry-run inventory. Add nested-reader wiring only if an actual new literal nested reader requires it; no wrapper-only dependency shim or broad allowlist expansion.
6. Pure internal fixture scope: product docs skipped. No production release engine, release workflow, allocator, parser, wrapper or CI gate changes; no dependency, parse retry, waiver, merge or release. Preserve the separately owner-approved SPEC-0245/Spec-AC-06 Review-By correction to 2026-11-21 and its exact transferred decision/event; do not restamp, mark deferred evidence done or expand the contract.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-release.sh | Deterministic cross-process entry-log and save boundary reads, followed by existing TEST-021 actual SIGKILL recovery and foreign-host refusal | `patch:docs/ai/tdd/spec-release-fixture-atomic-publication/mutation-TEST-001.patch` restores direct destination open/write in the shared transport publication primitive while retaining boundary handshake; the exact held-boundary JSON assertion must fail | green |

One integration test spans generated gh stub writer -> actual transport path -> parent JSON reader and release owner SIGKILL -> orphan publisher -> journal resume. Original release suite cases are retained non-regression coverage rather than newly invented TDD claims.

## Verification

All tests run from the repair root with AAI_ROLE and AAI_GIT_WRITE removed through the canonical wrapper. The enclosing role commands may set AAI_ROLE=subagent; the tests themselves must not inherit it.

- Failing-first deterministic selected command (retain exact invocation and selected branch in the log): `env -u AAI_ROLE -u AAI_GIT_WRITE RELEASE_FINISH_CASE=TEST-021 RELEASE_RECUT_CASE=none bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release.sh test_700_one_command_finish`. If a separate narrowly selectable branch is added, run it as well and record its selector. Failure must name the held-boundary parse/snapshot assertion; timeout or unrelated fixture failure is inconclusive.
- GREEN: same selected command, with both entry/save controls reached and original SIGKILL success marker present; `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release.sh` exits 0.
- Registration/inventory: run the repo's existing test-registration checker with its documented interface, then `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh node .aai/scripts/release-dry-run.mjs --list`; verify the actual release suite remains discovered once. No new suite means suite-map/weights changes are unnecessary.
- Rehearsal: `env -u AAI_ROLE -u AAI_GIT_WRITE AAI_TEST_TIMEOUT=3600 bash .aai/scripts/aai-run-tests.sh env -u AAI_TEST_TIMEOUT node .aai/scripts/release-dry-run.mjs --root /private/tmp/aai-release-fixture-rehearsal-source-r2 --both --timeout-seconds 1800 --budget-seconds 3600 --report docs/ai/reports/release-fixture-dry-run-r2.json` on an owned independent Git source fixture whose visible tracked/nonignored-untracked bytes, symlinks and file modes match the stable repair worktree, including tracked deletions. Record that equivalence and the fixture HEAD; disable its remote/push destinations. The rehearsal creates its own committed reader snapshots. The outer wrapper retains its 3600-second ceiling while its child clears AAI_TEST_TIMEOUT so readers exercise their actual default environment. This avoids contaminating the existing Pester default-timeout assertions and isolates the source-proof refs from other authorized worktrees. All executions complete with exitCode 0, including the rolled release reader; review report completeness and reader identities. The local bounds account for an 818-second filesystem-timestamp proxy of the macOS full release run; they are operational test-host limits, not a performance acceptance claim. Current-head Linux CI must pass its unchanged default 540-second reader and 1080-second executor bounds; local execution alone does not establish CI behavior.
- Exactly one full framework sweep before close, after targeted tests and remediation: `env -u AAI_ROLE -u AAI_GIT_WRITE AAI_TEST_TIMEOUT=3600 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh`. Retain the full raw log, run metadata and declared suite/result totals. Do not overlap shipping-tree mutators or another sweep. If it fails, report and triage the named failures; do not rerun a full sweep without owner direction. This ride inherits no PR535 waiver.
- Independently validate and review the final scoped diff. Do not claim execution during Planning.

## Evidence contract

Every artifact records ref_id, Spec-AC-01/TEST-001, actual command/selector, exit code, source snapshot and evidence path. Store failing-first, green selected/full-suite and writer-audit evidence under `docs/ai/tdd/release-fixture-atomic-publication-*.log`; retain diagnostics and reader report under `docs/ai/reports/`. Mutation evidence must use `docs/ai/tdd/spec-release-fixture-atomic-publication/mutation-TEST-001.txt` through mutation-run and its replay. Keep exact recorded observed failures distinct from the inferred CI scheduling mechanism. Validation PASS requires the canonical checked outcome report; no invented timings, tokens or test counts.

### Evidence by strategy

TDD requires stored RED for TEST-001 plus GREEN, mutation replay and the verification matrix above. Shared primitive mutation must redden the deterministic seam assertion; random stress or a static rename grep is insufficient.

## Registry items closed by this scope

Registry items closed by this scope: none.

NOT CLOSED: The open release follow-ups concern production behavior, platform support, notes, recut policy, or existing unrelated fixture assertions; none names transport snapshot publication. `fu-prompt-diet-fixture-real-root-race` and `fu-tripwire-attributes-concurrent-writes` concern different shared-root protocols and remain outside this fixture-local repair.

## Residual risks

Atomic replacement is a same-filesystem visibility guarantee, not durable fsync or multiwriter conflict resolution. The fixture uses sibling files on its temporary filesystem; Windows finish-runtime evidence deferred in earlier specs is not established here. Instrumentation proves the real boundary under controlled ordering, not the historical remote kernel schedule. A killed fixture process may leave an unrenamed sibling within its disposable fixture root; readers must never consume it.
