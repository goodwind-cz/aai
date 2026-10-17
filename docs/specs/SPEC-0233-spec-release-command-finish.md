---
id: spec-release-command-finish
type: spec
number: 233
status: done
frozen_sha256: ce9bcf837327a094ab0a42f436df748c13374ce08fd6c6cdca27c83928a04b84
ceremony_level: 2
capability: release-command-finish
user_visible: true
links:
  requirement: release-command-finish
  rfc: null
  pr: []
  commits: []
---

# Finish a bound release with remote-snapshot audit and safe resume

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0213-release-command-finish.md
- Dependency: standalone release-notes-pr-gate reviewed commit, supplied by orchestration before Implementation; shared isShipped and same-line hasNoNotesReason contracts are consumed, not reimplemented here.
- Technology contract: docs/TECHNOLOGY.md
- Prior evidence: docs/ai/reports/VALIDATION-20261013T205600Z-release-one-command-no-findings.md; docs/ai/reports/VALIDATION-20261013T220533Z-release-one-command-no-findings.md; docs/ai/tdd/release-one-command-audit-split-fixes.log. Original broad FAIL reports and spec are immutable context, not this split's verdict.

## Implementation strategy
- Strategy: loop
- Rationale: extract the existing finish source/fixes into a dedicated dependency-based worktree, exercise real Git/transport/process seams in one focused pass and obtain independent validation. Distinguish original late prechange replay from fresh observed RED controls; never retroactively claim original broad TDD chronology.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: remote-mutating release behavior and explicit dependency commit need a dedicated split branch, preserving the broad source workspace and immutable failed reports.
- User decision: undecided
- Base ref: fix/notes-content-and-merged-links, exact reviewed commit c9a04429d6e2af0c133a86c0b3d2c2662572442f (PR #466, stacked on PR #465). Local dependency is verified; remote CI/bot settlement and owner merges remain separate gates.
- Inline review scope: .aai/scripts/aai-release.sh .aai/scripts/aai-release.ps1 .aai/scripts/release-finish.mjs .aai/SKILL_RELEASE.prompt.md .aai/system/PROFILES.yaml .github/workflows/release.yml .github/workflows/ps1-quality.yml tests/skills/test-aai-release.sh tests/skills/test-aai-release-notes.sh tests/skills/aai-win-dispatch.Tests.ps1 tests/skills/test-aai-learned-routing.sh tests/skills/suite-map.yaml tests/skills/test-aai-suite-select.sh tests/skills/test-aai-pr-preflight.sh tests/skills/lib/prompt-diet-ledger.sh tests/skills/test-aai-prompt-diet.sh docs/USER_GUIDE.md docs/TECHNOLOGY.md docs/product/release-command-finish.md docs/SKILL_CATALOG.html docs/skill-catalog-data.json CHANGELOG.md
- Code review required: true, plus this intake/spec and normal evidence/index companions. Notes-gate implementation, SKILL_PR and skill-suite CI gate changes belong to the dependency and must not appear as new finish changes. The bounded notes-suite lifetime adjustment below is owned by this finish scope; it changes no functional gate assertion.
- Additional compatibility review scope: `tests/skills/test-aai-docs-audit.sh` and `tests/skills/test-aai-sweep-parallel.sh`. The independent full sweep exposed their product lifecycle assertion and nested heartbeat fixture failure. Reproduce and isolate each cause before a minimal correction; retain strict product alignment and heartbeat progress/termination assertions. Release publication failure remains subject to the same root-cause gate. No release or platform acceptance requirement is relaxed.

## Constitution deviations

Article 7: owner's explicit 2026-10-12 direction in the intake authorizes `/aai-release --confirm` to merge only the release PR bound to the invocation's repository, explicit version, branch and pushed head. Resume must prove that identity from durable metadata and authoritative remote facts. Merge uses `--match-head-commit` after all required checks pass; no auto/admin bypass. Other PRs retain their existing authorization boundary. This development ride itself opens a PR and performs no live release or merge. The justified release-only exception requires no edit to constitution or workflow canon.

## Acceptance Criteria Mapping

Commands R, P, H, C below decide named assertions, with exact logs under Evidence contract.

| Requirement | Spec-AC | Verification | Observable |
|-------------|---------|--------------|------------|
| AC-001 | Spec-AC-01 | R TEST-001..003 | Genuine omissions refuse before release refs/push/PR; historical exemptions pass; audit parent equals remote snapshot |
| AC-002 | Spec-AC-02 | R TEST-004..005 | Real pending exit8 reaches watcher; no failed/degraded/missing-check merge; bound head and observed base preserved |
| AC-003 | Spec-AC-03 | R TEST-006 | Actual workflow shell publishes all sections; peeled tag and release body equal merge payload before cleanup |
| AC-004 | Spec-AC-04 | R TEST-007..009 | Every transition restarts without duplication, exact head lease and dependency checks preserve moved branches/caller data |
| AC-005 | Spec-AC-05 | P TEST-010 and H TEST-011 | Native normal/empty/error controls on real Windows 5.1/pwsh7 and Linux; hosted Linux TEST033 completed20 skips0 |
| AC-006 | Spec-AC-06 | R TEST-012 and C TEST-013 | Notes implementation is inherited; current consumption/profile/closure and finish companions pass |

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN confirming a release the audit SHALL use the authoritative remote base SHA and both Git change modes, refuse genuine unnoted shipped history before release mutations, and exempt only proven CHANGELOG-only, previous release or valid same-line marker history; write-free preview SHALL refuse unavailable remote objects | done | TEST-001..003 green (test-aai-release rc 0 at 4833ed55); docs/ai/reports/VALIDATION-20261017T120212Z-release-command-finish.md | — | — |
| Spec-AC-02 | WHEN CI settles green and bound release identity remains valid the engine SHALL merge only that PR/head with match-head-commit after rechecking its audited remote base; pending exit8 SHALL wait, while failed/degraded/malformed/empty checks, moved base or head SHALL refuse before merge | done | TEST-004..005 green (test-aai-release rc 0 at 4833ed55); docs/ai/reports/VALIDATION-20261017T120212Z-release-command-finish.md | — | — |
| Spec-AC-03 | WHEN the PR merges the engine SHALL await successful release.yml for its merge SHA and verify the remote peeled tag SHA and exact rolled multi-section release notes before cleanup | done | TEST-006 green (test-aai-release rc 0 at 4833ed55); docs/ai/reports/VALIDATION-20261017T120212Z-release-command-finish.md | — | — |
| Spec-AC-04 | WHEN resumed at any recorded transition the engine SHALL complete only missing actions without a duplicate PR/merge/tag/release; leased branch cleanup and safe registered-base sync SHALL preserve unrelated caller bytes and refuse unsafe changes truthfully | done | TEST-007..009 green (test-aai-release rc 0, test_702); hosted CR-3 identity PASS on win32 (ps1-quality 39030229655); docs/ai/reports/VALIDATION-20261017T120212Z-release-command-finish.md | — | — |
| Spec-AC-05 | Required native SHA/URL normal, empty and error cases SHALL execute successfully on actual Windows PowerShell5.1 and Windows pwsh7 plus Linux pwsh; TEST033 SHALL complete20 consecutive actual executions on the hosted Linux CI runner with zero skips | done | TEST-010/011 green: hosted ps1-quality 39030229655 on 4833ed55 (Linux TEST033 completed=20 skips=0, Pester 156/0/0; Windows 5.1 and pwsh7 152/0/4); docs/ai/reports/VALIDATION-20261017T120212Z-release-command-finish.md | — | — |
| Spec-AC-06 | Finish prompt and product docs SHALL describe narrow authorization, version-specific resume, compatibility skips and remote-snapshot/race limits; actual profiles/selector/fixture/prompt-accounting/generated companion checks SHALL pass | done | TEST-012/013 green (win-fallback, follow-ups, release rc 0; spec-lint 0; full sweep r8 109/109 at 2f13ad79); docs/ai/reports/VALIDATION-20261017T120212Z-release-command-finish.md | — | — |

## Implementation plan

1. Start a dedicated finish worktree from the reviewed notes dependency commit through orchestration. Extract only the scoped release engines, shared finish helper, actual release-workflow notes block and declared fixture/native/companion changes. Keep the broad source tree and original reports unmodified. Consume gate classification and marker functions; never let gh files lacking mode override a Git-proven shipped change. Record dependency SHA and finish scoped diff separately from inherited notes changes.
2. Resolve the authoritative remote base with ls-remote before preparing. Confirm may obtain absent objects with `fetch --no-tags --no-write-fetch-head` without writing tracking refs or FETCH_HEAD, then verify the remote snapshot is unchanged. Roll/audit that exact SHA; journal baseHead and prepared parent bind it. Evaluate raw NUL Git diff with old/new modes, including extensionless executable addition/deletion/chmod and caller detached at an older tag. Required gh metadata must be valid; missing history/PR details never guesses clean. Preview checks remote SHA using available objects only, preserves refs/index/user files/journal/GitHub state, and names the fetch-before-preview remedy if objects are missing. These object-cache reads/writes do not relax the no release branch/commit/push/PR before audit rule.
3. After a genuine omission refuse with one named cause before preparing release mutations. Complete noted history, CHANGELOG-only and previous release PRs, or valid no-notes marker produce zero false NAMED/WARNING/REFUSE findings on the normal path. Same-line parser comes from the dependency. Before pre-PR resume preparation, before waiting and immediately before merge, require remote base to still equal the audited snapshot. A benign stale tracking ref can succeed against the actual authoritative remote SHA; staleness alone is not a blanket refusal. A later changed remote base refuses conservatively and retains journal/PR, without silently absorbing unaudited history on same-version resume.
4. Bind durable repository/version/base/head/PR/merge state in Git metadata, reread remote facts, validate exact PR identity and parse actual gh required-checks JSON/status semantics. Pending exit8 with populated valid pending checks reaches actual watch-ci; transport errors, empty/malformed checks and deadline/degradation do not pass. Recheck required checks/head/base before pinned squash merge; no auto/admin flags. Every failure prints exactly one named reason plus executable `--version <version> --confirm` resume command, reports already completed irreversible steps, and performs no subsequent stage. An unchanged moved base may continue refusing on resume; docs explain deliberate fresh audited cut/operator recovery rather than claiming automatic rebase/re-audit.
5. After merge select/wait bounded release.yml run on that merge SHA; workflow shell uses all rolled sections and publishes idempotently. Verify peeled remote tag points to merge SHA and GitHub release body equals rolled notes (only documented outer whitespace normalization allowed). Wrong SHA/body/run/failure refuses before cleanup. Publication failure may already leave a merged PR/tag; no rollback or globally atomic release claim. Client does not directly publish tags/releases; repos with no release.yml retain explicit manual-tag skip. No-remote remains local cut with remote-stage skip; dry-run plus confirm remains write-free.
6. Resume after worktree/payload/prepared/pushed/PR/merged/workflow/verified/remote-delete/local-delete/synced stages without duplicate remote artifacts; remote identity mismatch/ambiguous existing PR refuses. Remote deletion uses expected-head lease, fresh head check and dependent PR check, including actual concurrent push after check. Local cleanup removes only the safe release branch. Locate a registered base checkout; safe ff advances it while dirty/detached/feature caller bytes stay exact. Dirty overlap, divergence, hidden edits or moved head refuse; absent base reports a truthful skip. Do not stash/reset/prune/overwrite owner state.
7. Both frontends use shared dependency-free finish behavior. Fix/validate native stdout at its capture origin and require nonempty full SHA/URL before use; error outputs cannot become success values. Keep actual native helper execution in tests: Node delegation alone is insufficient proof of capture. Retain 5.1/pwsh7 parse/runtime portability, shell bash3.2 fixtures, dot-source safety, normal offline engine cases and all nonretired test registrations.
8. Prompt/public docs reflect only this finish contract and snapshot limits. Measured SKILL_RELEASE growth has its own prompt ledger entry/checkpoint relative to the reviewed notes dependency. Classify new finish helper, map its dependency closure, repair learned-routing fixtures so copied frontends include helper imports, update selection and PR preflight companion pins, and regenerate both catalog files. Do not transplant old broad prompt credits or silently retire old tests by leaving orphan definitions. Retire exactly the two notes-suite assertions that perpetually forbid release-finish.mjs and its profile: SPEC-0229 scoped that absence to its original ride, whose immutable commit b2e4e620d253da7601f8e27fa0cf41fff264177e, PR #465, independent evidence and source reports remain preserved. Keep every live classifier, marker, added-notes, lexical, staged/range and local-PR/CI assertion, including the 24 substantive/cosmetic controls from PR #466. The current notes suite must still require the gate profile. Finish TEST-012/013 must require the real helper, exact core classification, shared classifier/marker imports and actual audit consumption, plus frontend-to-helper-to-gate/runtime-file copied fixture closure. These current composition checks replace the obsolete lifetime assertions explicitly; do not skip them or claim the helper remains absent. Do not embed historical Git objects in the shipped runtime test suite.

## Known remote guarantee and residual race

The client guarantees its payload/audit uses one observed authoritative remote base and refuses any base move observed at its named recheck boundaries. `gh pr merge --match-head-commit` pins the PR head only. There is an external race between the last base observation and GitHub's merge; a base change in that interval can enter the merge without client observation. No atomic base-conditional API, proof that all history at the eventual merge was audited, or universal no-publication guarantee after that interval is promised. Record this limitation in prompt/product docs and independent review. Exercise the actual separate-origin push during CI and after the last observation; the latter proves the limit exists, not a fictitious refusal requirement.

## Platform evidence and sequencing gate

The contract is fully specified and may freeze now; lack of runtime evidence is a later completion gate, not a missing design decision. Preserve the original hosted Linux20 and real Windows5.1/7 requirements without waiver. Prior Linux ARM64 Docker20 proves container behavior only; original reports say hosted and Windows native proof were unavailable. Local/container logs, static YAML/pins or parsing cannot satisfy hosted/Windows rows.

Complete extraction, all possible local tests and independent code review first. P can run on an available real Windows execution host independently of source publication. H needs the final source/workflow committed and pushed to a ref GitHub can execute. Normal PR ceremony demands Validation PASS before committing/pushing, while this spec demands hosted proof before Validation PASS: this is a real commit-before-CI sequencing deadlock if no separately authorized evidence-staging route exists. Planning grants no exception, no provisional PASS, no early AC-done flip and no automatic push. At that later point orchestration presents the concrete reviewed diff, outstanding platform facts and exact narrowly scoped evidence-staging commit/push/run proposal to the owner, citing `.aai/SKILL_PR.prompt.md` and `.aai/VALIDATION.prompt.md`; absent authorization or a real platform host, mark cannot_verify and keep Validation non-PASS. Owner may explicitly change the contract via normal amendment, but no silent downscope occurs. Do not ask that permission during Planning.

Registry items closed by this scope: fu-release-ps1-empty-precut-sha (verify obsolete empty SHA cannot flow into a restore/use on either relevant path before recording actual closure).

Out-of-scope registry items: fu-constitution-art7-directed-merge (general protected constitution wording); release-unlogged-pr-three-classes is already closed in current registry; no duplicate closure claim is created.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---------|---------|------|----------------------|-------------|----------|--------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-release.sh | Actual history exemption controls and genuine omission/blank marker refusal; positive nonexempt shipped PR proves audit ran | Let no-notes regex cross newline | green |
| TEST-002 | Spec-AC-01 | integration | tests/skills/test-aai-release.sh | Actual raw Git executable add/delete/chmod with remote filename list; detached old caller and stale tracking ref refusal; benign authoritative docs-only base passes | Ignore Git old/new modes when gh file list arrives | green |
| TEST-003 | Spec-AC-01 | integration | tests/skills/test-aai-release.sh | Missing remote objects preview refuses with no refs/FETCH_HEAD/journal writes; confirm fetches objects without tracking/FETCH_HEAD changes and parent binds exact snapshot | Audit origin tracking ref instead of authoritative SHA | green |
| TEST-004 | Spec-AC-02 | integration | tests/skills/test-aai-release.sh | Exact deny-default transport argv/values, pending status8 real watcher transition, populated malformed/empty/error checks refuse and zero merges | Treat checks exit8 as transport failure | green |
| TEST-005 | Spec-AC-02 | integration | tests/skills/test-aai-release.sh | Separate-origin base/head push before production recheck and resume refuses; known external last-observation race probe recorded honestly | Omit final observed-base comparison | green |
| TEST-006 | Spec-AC-03 | integration | tests/skills/test-aai-release.sh | Actual release.yml publish shell over two sections; workflow SHA/body/tag mismatch stops cleanup; expected exact notes/tag positive | Extract only first rolled section | green |
| TEST-007 | Spec-AC-04 | integration | tests/skills/test-aai-release.sh | Eleven interruption points and resumed real remote facts yield one PR/merge/tag/release; foreign identity refuses; same-version completed rerun idempotent | Recreate PR on resume | green |
| TEST-008 | Spec-AC-04 | integration | tests/skills/test-aai-release.sh | Real expected-head deletion lease race and dependent PR/changed branch refusal; local safe release branch retained on failure | Remove remote expected-head lease | green |
| TEST-009 | Spec-AC-04 | integration | tests/skills/test-aai-release.sh | Dirty detached and feature worktree plus clean registered base, overlap/divergence and no-base paths; no-remote/manual-workflow and byte/ref/journal dry-run controls | Reset caller branch during base sync | green |
| TEST-010 | Spec-AC-05 | integration | tests/skills/aai-win-dispatch.Tests.ps1 | Real native helper SHA/URL normal-empty-error controls plus frontend parity under Windows5.1 and Windows pwsh7; Linux pwsh actual helper arms | Accept empty captured SHA | pending |
| TEST-011 | Spec-AC-05 | integration | .github/workflows/ps1-quality.yml | Hosted Linux20 actual test_033 calls with non-skipped count20; assert green run/source SHA and read full raw log | Convert repetition failure or skip to success | pending |
| TEST-012 | Spec-AC-06 | contract | tests/skills/test-aai-release.sh | Prompt/public docs authorize bound PR only and disclose remote race/resume/manual/offline behavior; real helper classification/docs inventory and shared-gate consumption replace two historical absence assertions | Claim atomic remote base pin | green |
| TEST-013 | Spec-AC-06 | contract | tests/skills/test-aai-learned-routing.sh | Real helper import closure in copied fixture plus profile/selector/prompt-diet/preflight/hygiene/catalog/update companion outcomes | Copy frontend without helper imports | green |

## Verification

- R: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release.sh` -> all declared finish assertions green and original nonretired regressions accounted for; external transport stubs deny unknown arrays and wrong values. TEST-001..009/012 are split mappings, not an instruction to renumber frozen tests in old spec.
- P Windows5.1: `powershell -NoProfile -File .aai/scripts/aai-run-tests.ps1 powershell -NoProfile -Command "Invoke-Pester -Path tests/skills/aai-win-dispatch.Tests.ps1 -CI"` on actual Windows, with runtime-version/OS/source-SHA logged. Repeat the wrapped native Pester command using Windows pwsh7, retaining the canonical outer PowerShell wrapper. Linux `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release.sh test_701_native_capture_controls` must execute real helper arms, no skip. Function-selector argument may be adjusted to existing registered test with evidence; named runtime matrix is unchanged.
- H (after authorized evidence staging only): `gh workflow run ps1-quality.yml --ref <recorded pushed finish branch>` then `gh run view <exact run id> --log` and `--json headSha,status,conclusion` -> same source SHA, successful actual Linux20 step with completed20/skips0, plus actual Windows5.1/pwsh7 native Pester output when that workflow supplies P. No run id or branch is invented; orchestration binds actual ids at invocation.
- C: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh --skill aai-learned-routing --skill aai-layer-profiles --skill aai-suite-select --skill aai-pr-preflight --skill aai-prompt-diet --skill aai-hygiene-pack --skill aai-docs-hub --skill aai-update --skill aai-deslop` -> each declared selected result accounted for and exit0; note unmet/environmental proof honestly. Include normal close/corpus gates before delivery.

## Evidence contract

- Ref release-command-finish, source/dependency SHA, TEST/AC ids, exact command, transport arrays/values, exit code, fixture identities and observed output. Per-test green proof docs/ai/tdd/release-command-finish-green.log; companion proof docs/ai/tdd/release-command-finish-companions.log; Windows/native proof docs/ai/tdd/release-command-finish-platform.log; hosted raw run/log provenance docs/ai/tdd/release-command-finish-hosted.log. Loop demands observed RED proof, optional storage docs/ai/tdd/release-command-finish-red.log.
- Original broad postimplementation replay is labeled late-baseline, not RED-first. For newly extracted split tests observe pre-extraction failures on notes dependency base; named refusal tests require actual incorrect-success scratch mutation or known prior failure reproduction with correct stage positive controls, never MODULE_NOT_FOUND as behavioral proof. Preserve immutable old reports.
- Do not mark platform AC terminal until P and H are produced and read. Record cannot_verify without passing it when host/staging unavailable. Independent Validation report uses aai-outcome-v1 and returns identical outcome_report/set-validation evidence paths; review records dual verdict and external residual race. Freeze only defines the future contract; no implementation PASS is claimed by Planning.
