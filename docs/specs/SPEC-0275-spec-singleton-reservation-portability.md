---
id: spec-singleton-reservation-portability
type: spec
number: 275
status: done
mutation_gate: v1
frozen_sha256: 5adc771d76d1c05da6e2c626b375fae3a204a975e0ed9f6a7a1aea391a9f8d55
ceremony_level: 3
links:
  requirement: singleton-reservation-portability
  rfc: downstream-pr-ceremony-reliability
  pr: []
  commits: []
---

# Portable bounded document-number reservations

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0247-singleton-reservation-portability.md
- Parent: docs/rfc/RFC-0016-downstream-pr-ceremony-reliability.md, phase B only
- Technology contract: docs/TECHNOLOGY.md

## Implementation strategy
- Strategy: tdd
- Rationale: create-only uniqueness and coupled-family remote writes are protected allocator behavior. Observe each new assertion failing against the prior behavior or a behavior-removing mutation, then capture GREEN and mutation replay. Extend the existing reservation suite; no new suite is needed.

## Isolation and review
- Worktree recommendation: required
- Worktree rationale: protected allocator and adversarial transport fixtures require isolation from the shared checkout and parallel rides.
- User decision: worktree
- Base ref: main
- Worktree branch/path: codex/singleton-reservation-portability at /private/tmp/aai-singleton-reservation-portability; already authorized and established through ride-handoff.
- Review scope: .aai/scripts/allocate-doc-number.mjs, tests/skills/test-aai-doc-number-reservation.sh, tests/skills/test-aai-doc-numbering.sh (only if existing assertions require correction), docs/TECHNOLOGY.md, docs/USER_GUIDE.md, docs/rfc/RFC-0016-downstream-pr-ceremony-reliability.md, docs/issues/CHANGE-0247-singleton-reservation-portability.md, docs/specs/SPEC-0275-spec-singleton-reservation-portability.md, CHANGELOG.md. Runtime evidence is separate. Code review is required.
- No further isolation decision is needed. Owner model override permits Codex roles, with independent implementation and validation; Validation and Review run sequentially.

## Scope and exclusions

Change only phase B reservation transport, its existing executable coverage, and the corresponding user contract. Preserve the exported reserveAtomic API and existing allocator/guard exit and provisional-marker contracts. Do not introduce capability caching, provider preflight, PR resumption, scope/waiver schemas, global-gate changes, phase timing, new suites, prompt edits, or new .aai files. No merge or release is authorized.

Registry items closed by this scope: none

Registry scan: follow-ups.mjs list was read on 2026-11-06. NOT CLOSED: allocator subjects fu-typemap-missing-research-hotfix / fu-issue-0042-half-delivered (type coverage), fu-realpath-allocate-doc-number-l3 (symlink entrypoint), fu-numbering-rewrites-dated-reports (rewrite scope), fu-restamp-slug-links-unverified and fu-restamp-shape-ignores-intake-rename (amendment restamping) remain open because this scope changes transport only.

## Acceptance Criteria Mapping

All verification commands below run from the repository root. R denotes `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-doc-number-reservation.sh`. N denotes the same wrapper with `tests/skills/test-aai-doc-numbering.sh`. The named tests are additions/extensions in the existing suite, not separate suite registrations.

| Requirement | Spec-AC | Verification | Observable and evidence |
|---|---|---|---|
| AC-001 | Spec-AC-01 | R, TEST-201 | Singleton succeeds on a real bare origin with receive.advertiseAtomic=false; exactly one ref created, no --atomic, unique reservation commit and empty expected lease preserved. Stored RED/GREEN logs and remote ref/object snapshots. |
| AC-002 | Spec-AC-02 | R, TEST-202 and TEST-203 | Coupled success creates every member; collision leaves the unclaimed peer absent at that number and retries the whole pair; unsupported atomic creates zero refs and stops after one push. |
| AC-003 | Spec-AC-03 | R, TEST-204 | push, fetch and ls-remote have finite per-call timeouts; deterministic hanging transport returns within the configured bound plus 2000 ms, without collision retry. Logs identify operation and timeout. |
| AC-003, AC-004 | Spec-AC-04 | R, TEST-205 | Each injected timeout, unsupported atomic, permission and connectivity error produces its own named category and remedy; non-collision errors have one push attempt, genuine stale-info lease rejection alone retries. |
| AC-001, AC-004 | Spec-AC-05 | R, TEST-206 and existing TEST-007/016/017/018 | Actual allocation and --reserve consume the new transport; success clears/omits provisional marker, failure preserves it; collision completion exits 4; same-HEAD contenders cannot reserve the same number. |
| AC-004 | Spec-AC-06 | R and N, TEST-207 | Both existing allocator suites exit 0, preserving no-origin, dry-run, guard, unique-object, candidate-scan and rewrite behavior. |
| AC-005 | Spec-AC-07 | R, TEST-208 | TECHNOLOGY and USER_GUIDE describe actual unique-object singleton/coupled behavior, finite timeout and remedies; RFC B cites this change and is in progress/done while RFC remains draft and other phases remain unchanged. |

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN a singleton reservation targets a server without atomic capability the allocator SHALL create one create-only reservation without requiring atomic support. | done | docs/ai/tdd/spec-singleton-reservation-portability/TEST-001-green.log | — | TEST-201 |
| Spec-AC-02 | WHEN a coupled family reserves multiple refs the allocator SHALL retain atomic all-or-nothing writes and SHALL refuse unsupported atomic transport without partial refs. | done | docs/ai/tdd/spec-singleton-reservation-portability/TEST-002-green.log | — | TEST-202, TEST-203 |
| Spec-AC-03 | WHEN any allocator reservation network operation stalls the allocator SHALL terminate that call within its finite timeout and report the operation and timeout outcome. | done | docs/ai/tdd/spec-singleton-reservation-portability/TEST-004-green.log | — | TEST-204 |
| Spec-AC-04 | WHEN reservation transport fails the allocator SHALL classify the cause and retry only confirmed create-only collisions. | done | docs/ai/tdd/spec-singleton-reservation-portability/TEST-005-green.log | — | TEST-205 |
| Spec-AC-05 | WHEN allocation or --reserve calls reservation transport the allocator SHALL preserve its existing marker, collision, uniqueness and exit-code contract. | done | docs/ai/tdd/spec-singleton-reservation-portability/TEST-006-green.log | — | TEST-206 |
| Spec-AC-06 | Existing allocator regression suites SHALL continue to pass. | done | docs/ai/tdd/spec-singleton-reservation-portability/TEST-007-green.log | — | TEST-207 |
| Spec-AC-07 | User-facing reservation documentation and RFC phase B status SHALL match this slice and preserve the open umbrella RFC. | done | docs/ai/tdd/spec-singleton-reservation-portability/TEST-008-green.log | — | TEST-208 |

## Implementation plan

1. Keep each attempt's globally unique dangling commit and every empty expected-value lease. Select --atomic by ref count: absent for one, mandatory for more than one. Never retry a coupled push without atomic support and never push members separately.
2. Bound every allocator network subprocess: reservation push, reservation-ref ls-remote, base-ref fetch, and origin candidate-scan fetch. Default per-call timeout is 30000 ms. The implementation may provide an explicitly documented, positive-integer bounded override for deterministic fixture tests; it must reject invalid/unbounded values or retain the finite default with a visible warning. Do not apply the network timeout to local git object/index commands. Preserve existing degrade-and-report fallbacks; a failure does not imply a reservation succeeded. This is a per-call limit, not a total batch-duration guarantee.
3. Preserve stdout/stderr sufficiently to report operation, remote, cause and a concrete retry/access/connectivity/server-support remedy. Never include environment or credentials in diagnostics. Timeout classification outranks partial stale-info output. Unknown or ambiguous errors remain non-collision failures. Genuine stale-info collisions keep the existing next-number cap; connectivity, denied writes and unsupported atomic must not become retry storms. Timeout may leave remote outcome unknown: retain provisional status and explain inspection/reconciliation, without promising rollback or assuming remote absence.
4. Cross the public CLI seams using disposable repositories. Successful singleton allocation must rename/stamp the doc with no provisional marker on a non-atomic remote. For --reserve, singleton success removes marker; non-collision failure keeps marker and warning/exit 0; existing ref exits 4, leaves file unchanged and names renumbering. Coupled unsupported transport must keep provisional status and create zero refs in the deterministic rejecting fixture.
5. Extend existing suite functions and register them in main; keep fixtures hermetic, bash 3.2 compatible, Node stdlib only. A Git PATH shim may record/hold/fail selected network calls but must delegate actual object/ref operations to real Git. Real receive.advertiseAtomic=false bare-origin controls establish capability behavior; shims alone do not.
6. Correct stale HEAD/unconditional --atomic examples in TECHNOLOGY and USER_GUIDE. Document configured timeout behavior, operation-specific recovery and uncertain timeout outcome. Add one rollable CHANGELOG entry. RFC phase B becomes in progress citing singleton-reservation-portability during work and done only with verified delivery; other phases and RFC draft remain unchanged.

### Seams and residual risks

S1: transport argv -> real Git receive capability and remote refs: TEST-201/202/203 assert real ref existence and absence, not just argv. S2: child-process timeout/error -> retry policy -> remote writes: TEST-204/205 assert attempt counts, time bound and snapshots. S3: reservation result -> allocation/--reserve -> frontmatter and merge guard: TEST-206 runs real CLI and existing marker guard. S4: executable behavior -> product contract and umbrella rollout: TEST-208 checks both documentation and RFC state. Existing TEST-016/017 cross unique-object production into real lease rejection for identical-HEAD contenders.

Hermetic fixtures do not establish live Azure behavior, native Windows transport runtime behavior, arbitrary Git credential-helper descendant termination, or a globally atomic bound over a multi-call batch. Report these limits; do not claim a live downstream reproduction. A timed-out write may have reached the remote. The lease still protects existing refs, but this scope adds no reservation ownership/reconciliation protocol.

## Test Plan

Each row is executed by R (and N where stated). New suite test numbers 201–208 are suggested function labels; TEST IDs below are frozen contract identifiers. Mutation targets are .aai/scripts/allocate-doc-number.mjs except TEST-008 which targets docs/TECHNOLOGY.md. Measurement refinement 2026-11-06: executable replacements below target the implemented transport seams; TEST-005 and TEST-006 each require both arms. The shared deadline mutation is observed independently by all four network-call arms, whose subprocess lifetimes are measured separately from local allocation work. Recorded with spec-amend as measurement-only; no contract change.

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-doc-number-reservation.sh | TEST-201: real non-atomic bare server accepts singleton; lease argv empty expected, new object differs from HEAD and prior attempt; remote ref exists. | `sed:s/refNames.length > 1/refNames.length >= 1/` forces singleton atomic capability. | green |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-doc-number-reservation.sh | TEST-202: supported coupled success and pre-existing-member collision; neither partial peer at collided number, pair retries to next. | `sed:s/refNames.length > 1/refNames.length > 99/` removes coupled atomic protection. | green |
| TEST-003 | Spec-AC-02 | integration | tests/skills/test-aai-doc-number-reservation.sh | TEST-203: receive.advertiseAtomic=false refuses coupled reservation; both absent, one push, non-collision diagnostic; no singleton fallback. | `sed:s/refNames.length > 1/refNames.length > 99/` permits a coupled write on the real non-atomic server. | green |
| TEST-004 | Spec-AC-03 | integration | tests/skills/test-aai-doc-number-reservation.sh | TEST-204: stall each network operation separately, observe bounded return and operation+timeout; normal quick negative control, bounded configuration tests if override exists. | `sed:s/, timeout, killSignal:/, killSignal:/` removes the shared network deadline; all four independently stalled call arms must report over-bound failure. | green |
| TEST-005 | Spec-AC-04 | integration | tests/skills/test-aai-doc-number-reservation.sh | TEST-205: table-driven permission/connectivity/unsupported/timeout/unknown failures including remote rejected unpacker, misleading stale-info in timeout; one attempt and named remedy; real stale-info alone retries. | `sed:s/if \(\/!.*\.test\(output\)\)/if (\/rejected\/i.test(output))/` broadens collision; separately `sed:s/const category = networkFailure\(e, output\);/const category = 'unknown';/` collapses categories. Both must fail. | green |
| TEST-006 | Spec-AC-05 | integration | tests/skills/test-aai-doc-number-reservation.sh | TEST-206: full singleton allocate and --reserve success on non-atomic remote; completion failure leaves marker/exit 0; collision exits 4; existing same-HEAD singleton/coupled controls. | `sed:s/const sha = createReservationCommit\(root\);/const sha = git(root, ['rev-parse', 'HEAD']);/` reuses HEAD; separately `sed:s/const leases = refNames.map\([^\n]+/const leases = [];/` removes leases. Both must fail. | green |
| TEST-007 | Spec-AC-06 | integration | tests/skills/test-aai-doc-number-reservation.sh | TEST-207: existing reservation and doc-numbering suites pass, selected together through suite-map; no nested suite invocation. | `sed:s/return `refs\/aai\/docnums\/\$\{displayIdStr\}`;/return `refs\/aai\/broken-docnums\/${displayIdStr}`;/` changes the public namespace. | green |
| TEST-008 | Spec-AC-07 | integration | tests/skills/test-aai-doc-number-reservation.sh | TEST-208: exact singleton/coupled/default-timeout documentation assertions and RFC B link/status with other-phase preservation. | `sed:s/30000 ms/0 ms/g` falsifies the documented finite default. | green |

## Verification

- RED first: Implementation adds tests in its own worktree and observes the new singleton capability and timeout/diagnostic assertions failing on unchanged behavior. For existing regression obligations and documentation assertions already satisfied, run the named behavior-removing mutation and observe failure. Capture the specific failing assertion, not a missing executable, syntax error or timeout of the whole wrapper.
- Store per-row RED and GREEN under docs/ai/tdd/spec-singleton-reservation-portability/TEST-xxx-red.log and TEST-xxx-green.log. Store mutation results at docs/ai/tdd/spec-singleton-reservation-portability/mutation-TEST-xxx.txt through mutation-run.mjs; replay before handoff. Evidence names must resolve after allocator renames.
- R and N must both exit 0. Between rounds, derive SELECTED plus CORE through `node .aai/scripts/select-suites.mjs --files-from <actual changed-file list>` and run each selected suite through the wrapper with AAI_ROLE and AAI_GIT_WRITE unset.
- Independent Validation performs one full pre-close sweep: `env -u AAI_ROLE -u AAI_GIT_WRITE AAI_TEST_TIMEOUT=3600 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh`. Do not repeat that full sweep between rounds. Record actual outputs, exits and known baseline failures honestly.
- Run `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0275-spec-singleton-reservation-portability.md`, `node .aai/scripts/docs-audit.mjs --gate spec-singleton-reservation-portability`, and `node .aai/scripts/docs-audit.mjs --ac-flip-check spec-singleton-reservation-portability` before implementation handoff; use updated path after numbering.
- PASS requires every TEST row green, every AC terminal with real docs/ai/tdd evidence, appropriate mutation replay and independent Validation plus required sequential dual-verdict Review. Planning asserts only that this contract is frozen.

## Evidence contract

For every RED/GREEN/mutation/validation/review artifact record ref_id singleton-reservation-portability, relevant Spec-AC and TEST IDs, exact command or diff scope, exit/verdict, evidence path, and measured version/platform and diff identity. Capture remote refs before/after and attempt counts for transport cases; show elapsed time and effective deadline for hanging calls. No estimated timing/usage.

### Evidence by strategy

TDD requires stored RED per AC-gating test plus GREEN, behavior-valid mutation replay, and the declared verification matrix. Primary local runtime is macOS Node 24/Git; supported Node floor is 22. CI supplies platform claims only when actually observed. One authoritative Validation report carries aai-outcome-v1; its checked path must match outcome_report and set-validation --evidence. Native Windows or live Azure not executed remains cannot_verify.
