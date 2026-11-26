---
id: spec-azure-rejects-doc-number-reservation-push
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: 204f26df129b12fd072e466426c8896011cab166dee83c8bdc082e7c627e86e5
ceremony_level: 3
links:
  requirement: azure-rejects-doc-number-reservation-push
  rfc: null
  pr: []
  commits: []
---

# Doc-number reservation on Azure Repos: a non-atomic create-only transport chosen by platform detection

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/ISSUE-DRAFT-azure-rejects-doc-number-reservation-push.md
- Prior scopes: CHANGE-0035 / SPEC-0047 (origin reservation protocol, D2 to D5,
  D7), CHANGE-0085 / SPEC-0103 (`pr-platform.mjs` classification), the
  git-platform-detected-at-bootstrap ride (`lib/platform-adapter.mjs`
  `resolvePlatform`).
- In-flight overlap: PR #535 (CHANGE-0247 / SPEC-0275, "portable bounded
  document-number reservations"), owned by another agent. See D-535.
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, bash 3.2 suites).

## Implementation strategy

- Strategy: tdd
- Rationale: owner-recommended option recorded at intake. The allocator is an
  L3 protected surface; every new behaviour is first observed failing on the
  unchanged allocator against an Azure-shaped stub origin, and every Test Plan
  row is bound to a mutation that reddens it.

## Isolation and review

- Worktree recommendation: required
- Worktree rationale: L3 protected surface (.aai/scripts/allocate-doc-number.mjs),
  and the main checkout carries another session's uncommitted files.
- User decision: worktree (owner directed an own worktree in the ride brief)
- Base ref: origin/main at 13ede646
- Worktree branch/path: fix/azure-rejects-doc-number-reservation-push at
  /Users/ales/Projects/aai-worktrees/azure-docnum-reservation
- Review required: true
- Review scope: origin/main...HEAD of fix/azure-rejects-doc-number-reservation-push.
- Merge: the owner merges (L3); the orchestrator opens the pull request only.

## Root cause (Planning, 2026-11-26)

### Measured (local stub, git 2.54.0, macOS)

A bare origin with `receive.advertiseAtomic=false` and a clone whose pre-push
hook prints the git-lfs advisory text, pushing exactly the argv main sends
today (`git push --atomic --force-with-lease=<ref>: origin <sha>:<ref>`):

```
Locking support detected on remote "origin". Consider enabling it with:
  $ git config lfs..locksverify true ../origin.git
fatal: the receiving end does not support --atomic push
rc=128
```

No ref is created. The pre-push hook runs first and exits 0, then the git
client itself refuses because the server did not advertise the `atomic`
capability. That is why the operator's report quotes the git-lfs line: it is
the first line of the output, not the cause. The same push without `--atomic`
succeeds against the same stub (`* [new reference]`), and a second
create-only push of the same ref is rejected with `(stale info)`, so the
create-only lease works without atomic support.

Not the cause, measured: the git-lfs pre-push hook (exit 0, the non-atomic
push succeeds with the hook still installed); the empty-expected
`--force-with-lease` (succeeds and still rejects a duplicate without atomic).

### Documented, not measured live

Azure DevOps Repos does not advertise atomic push. Source: Microsoft Q&A
"(ado) (repo) support for git push atomic" (2025-05-01, accepted answer), user
running `AzureDevOps_M254_20250410.4`: `git push --atomic origin [branch] [tag]`
fails with `fatal: the receiving end does not support --atomic push`; the
answer states Azure Repos runs a custom Git server that does not advertise
`--atomic` and that the setting cannot be changed, also on-premises.

### Assumed, not verified

- Azure Repos accepts a push to a ref outside `refs/heads/` and `refs/tags/`
  (`refs/aai/docnums/*`). No Azure documentation was found either way. The
  operator's failing push never reached ref validation (the client aborted
  first), so the report is no evidence against it. If Azure refuses the
  namespace, this scope does not fix numbering on Azure; it surfaces the
  remote's own reason verbatim (Spec-AC-05) so the next report names it. A
  live check is filed as a follow-up (fu-azure-docnum-live-namespace).
- Azure lets a pusher delete a ref it created (needed for the coupled-family
  release in D-ROLLBACK). A refused release is named, never silent.

## Decisions

### D-DETECT: the Azure transport is chosen by the shared platform resolution

`reservationTransportFor(root, remote)` returns `azure-sequential` only when
`remote` is `origin` and `resolvePlatform({ repoRoot: root }).platform` from
`.aai/scripts/lib/platform-adapter.mjs` is `azure`; every other answer
(github, unknown, none, a legacy fallback, an invalid record) returns
`default`. That function is the one resolution rule every platform consumer
already shares: the column-0 `platform:` key of docs/ai/pr-config.yaml wins,
otherwise `pr-platform.mjs` classifies the origin URL (dev.azure.com,
ssh.dev.azure.com, *.visualstudio.com). An on-premises Azure DevOps Server on
its own hostname reaches the Azure transport by recording `platform: azure`.
No environment variable, flag or blanket bypass selects it.

The adapter is loaded with a dynamic import at module load, guarded: a layer
without it (a partial fixture that vendors only the allocator) resolves to
`default` and, only when a reservation push is attempted, prints one
`NOTE: platform detection unavailable (<reason>) — using the default reservation transport`
line on stderr.

### D-AZURE: sequential create-only pushes, no `--atomic`

`pushReservationSequential(root, remote, refNames)` creates one unique
reservation commit (the existing `createReservationCommit`), then pushes the
refs one at a time in ascending lexicographic order, each as
`git push --force-with-lease=<ref>: <remote> <sha>:<ref>` with no
`--atomic`. A singleton is therefore one push whose argv equals the
non-atomic singleton argv of PR #535. The fixed order means two clones
racing for the same family number contend on the same first ref, so the
loser fails before it holds anything.

### D-ROLLBACK: a coupled family is released on a partial claim

When push k of n fails, every ref already claimed in this attempt is deleted
with `git push --force-with-lease=<ref>:<sha> <remote> :<ref>`, newest first,
so only a ref still pointing at this attempt's unique commit is removed. The
result keeps the failing push's classification: `(stale info)` is a
collision and the whole family retries the next number (existing cap 50);
anything else is a non-collision failure and the existing D4 provisional
path applies. A release that fails is named in the error text
(`could not release <ref>: <reason>`); the orphan ref only burns that number,
which the candidate scan (D3c) never re-grants.

### D-REASON: the remote's reason verbatim, the git-lfs advisory set aside

On the Azure transport the error text is the push output with the git-lfs
locking advisory lines removed (`Locking support detected on remote ...` and
the `$ git config lfs.<url>.locksverify true` line that follows it), every
other line kept verbatim, and URL userinfo masked (`https://user:pat@host` to
`https://host`). When advisory lines were removed the text ends with
`(git-lfs locking advisory omitted: it is not the rejection reason)`.

### D-COMPLETE: existing provisional docs complete through `--reserve`

`--reserve --path <doc>` goes through the same dispatch, so on Azure it
completes a doc already stamped `number_reserved: false` by the old failure,
removes the marker, and the guard passes. Collision still exits 4 and keeps
the marker. No migration script: the guard already names the command per doc.

### D-GENERIC: GitHub and generic behaviour stay byte-identical

`pushReservation` is not edited. The dispatch replaces only its two call
sites (`reserveAtomic`, `runReserveCompletion`) with
`reservationPush(root, remote, refNames)`, which calls `pushReservation`
unchanged for `default`.

### D-535: how this composes with PR #535

PR #535 (open, not merged, conflicting with main since 2026-11-07) drops
`--atomic` for singleton pushes on every server, keeps one `--atomic` push for
a coupled family and refuses a coupled family on a server without atomic
support ("never push members separately"), and routes push, fetch and
ls-remote through a timeout wrapper with categorized diagnostics. It does not
read the platform, has no path for a coupled family on Azure, and replaces
the remote's output with a category remedy. So #535 alone would fix
singletons on Azure (namespace acceptance assumed) and leave coupled families
permanently provisional there.

This scope composes with it:
- It never edits `pushReservation`, `git()` or the fetch and ls-remote paths
  that #535 rewrites; it changes two call sites #535 does not touch. A merge
  of either PR after the other has no overlapping hunk in the allocator.
- The non-atomic sequential path runs only on `azure`, so #535's TEST-203
  (a generic non-atomic server refuses a coupled family with one push) keeps
  holding.
- Its user-doc additions are new paragraphs placed away from the lines #535
  rewrites in docs/USER_GUIDE.md and docs/TECHNOLOGY.md.
- After #535 lands, the Azure path should use #535's bounded `networkGit`
  for its pushes; filed as fu-azure-docnum-network-deadline (the two PRs
  cannot share the helper before one of them merges).

## Acceptance Criteria Mapping

- Expected Behavior 1 (collision-safe confirmed number on Azure): Spec-AC-01,
  Spec-AC-02, Spec-AC-03.
- Expected Behavior 2 (detected up front, guard accepts, collisions caught,
  no permanent provisional marker): Spec-AC-04, Spec-AC-06, Spec-AC-07.
- Expected Behavior 3 (reason verbatim, git-lfs advisory not the cause):
  Spec-AC-05.
- Constraint "GitHub and generic unchanged": Spec-AC-06, Spec-AC-08.
- Constraint "existing provisional docs need a path": Spec-AC-04.
- User-facing contract: Spec-AC-09.

Verification command for every row, from the repository root (R):
`env -u AAI_ROLE XDG_CACHE_HOME=$(mktemp -d) bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-doc-number-reservation.sh [selector]`.

Azure-shaped stub used by the tests: a local bare origin with
`receive.advertiseAtomic=false`, a clone pre-push hook that prints the
git-lfs advisory text and exits 0, and `platform: azure` in the fixture's
docs/ai/pr-config.yaml (or an Azure origin URL, Spec-AC-06). Every git run in
the new tests carries `GIT_ALLOW_PROTOCOL=file`, so no transport other than
the local file system can be reached.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN the platform resolves to azure and origin does not advertise atomic push the allocator SHALL reserve a singleton number with exit 0, create the reservation ref and stamp no provisional marker. | done | docs/ai/tdd/azure-rejects-doc-number-reservation-push/green-test_301_azure_singleton_confirmed.log | — | TEST-4141 |
| Spec-AC-02 | WHEN the platform resolves to azure the allocator SHALL reserve every member of a coupled family without atomic push, and WHEN one member is already taken it SHALL leave no ref of this attempt at that number and retry the family at the next number. | done | docs/ai/tdd/azure-rejects-doc-number-reservation-push/green-test_302_azure_coupled_family_confirmed.log | — | TEST-4142, TEST-4143 |
| Spec-AC-03 | WHEN two clones on azure reserve the same starting number concurrently the allocator SHALL grant that number to exactly one of them. | done | docs/ai/tdd/azure-rejects-doc-number-reservation-push/green-test_304_azure_race_one_winner.log | — | TEST-4144 |
| Spec-AC-04 | WHEN a doc stamped number_reserved false exists on azure the allocator SHALL complete it with --reserve (marker removed, ref created, guard exit 0) and SHALL exit 4 keeping the marker when the ref is taken. | done | docs/ai/tdd/azure-rejects-doc-number-reservation-push/green-test_305_azure_reserve_completes_provisional.log | — | TEST-4145 |
| Spec-AC-05 | WHEN the azure reservation push is refused for a non-collision reason the allocator SHALL make exactly one push, stamp the provisional marker and print the remote's reason lines verbatim with the git-lfs advisory removed and URL credentials masked. | done | docs/ai/tdd/azure-rejects-doc-number-reservation-push/green-test_306_azure_rejection_reason_verbatim.log | — | TEST-4146, TEST-4147 |
| Spec-AC-06 | The azure transport SHALL be selected only when resolvePlatform answers azure (recorded platform or Azure origin URL) and SHALL NOT be selected for github, unknown or none. | done | docs/ai/tdd/azure-rejects-doc-number-reservation-push/green-test_308_transport_selected_by_detection.log | — | TEST-4148 |
| Spec-AC-07 | WHEN the platform resolves to azure the merge guard SHALL still exit 4 on a cross-branch number collision. | done | docs/ai/tdd/azure-rejects-doc-number-reservation-push/green-test_309_azure_guard_cross_branch_collision.log | — | TEST-4149 |
| Spec-AC-08 | The existing reservation suite tests SHALL pass unchanged and the default transport SHALL keep calling the unedited pushReservation. | done | docs/ai/tdd/azure-rejects-doc-number-reservation-push/green-suite-reservation.log | — | TEST-4150 |
| Spec-AC-09 | docs/USER_GUIDE.md, docs/TECHNOLOGY.md, CHANGELOG.md and the product doc SHALL describe the Azure transport, its detection and the --reserve completion. | done | docs/ai/tdd/azure-rejects-doc-number-reservation-push/green-test_311_azure_docs.log | — | TEST-4151 |

## Implementation plan

1. .aai/scripts/allocate-doc-number.mjs: guarded top-level dynamic import of
   `./lib/platform-adapter.mjs`; `reservationTransportFor` (exported, memoized
   per root); `pushReservationSequential` with `releaseClaims`;
   `describePushFailure` (exported, D-REASON); `reservationPush` dispatch; the
   two call sites. Header comment: a CHANGE paragraph naming this scope.
   Anchors the mutations target, each occurring once:
   `const AZURE_PUSH_FLAGS = [];`, `platform === 'azure'`,
   `=== 'azure-sequential') return pushReservationSequential`,
   `for (const ref of claimed.slice().reverse())`,
   `const LFS_ADVISORY = `, `const res = reservationPush(root, 'origin', refNames);`,
   `const lease = createOnlyLease(ref);`, `.replace(URL_USERINFO, '$1')`; the guard's existing
   `if (baseId != null && baseId !== doc.id) {`.
2. tests/skills/test-aai-doc-number-reservation.sh: `mk_azure_repo` helper
   (mk_repo plus pr-platform.mjs vendored, `receive.advertiseAtomic=false` on
   the bare, the git-lfs-shaped pre-push hook, `platform: azure`), tests
   test_301 to test_311 registered in main. `PROJECT_FILES` gains
   `.aai/scripts/pr-platform.mjs` (lib/*.mjs is already vendored).
3. Docs: one new paragraph in docs/USER_GUIDE.md after the coupled-families
   block, one new bullet in docs/TECHNOLOGY.md before the reservation bullet,
   a CHANGELOG `## [unreleased] — <title>` entry, docs/product doc.

### Seams

- S1 allocator to real git receive capability: TEST-4141 to TEST-4144 assert
  refs present and absent in the real bare origin, not argv.
- S2 platform record and origin URL to transport choice: TEST-4148 drives the
  real `resolvePlatform` through pr-config.yaml and through an Azure URL.
- S3 reservation result to frontmatter and merge guard: TEST-4145 and
  TEST-4149 run the real CLI and the real `--guard`.
- S4 push stderr to operator warning: TEST-4146 reads the CLI's stderr.

### Residual risks

- Live Azure behaviour for the `refs/aai/*` namespace and for deleting a ref
  is assumed (see Root cause); no automated test can cross it.
- A process killed between claim and release leaves an orphan ref; it burns
  one number and nothing else.
- Windows runtime of the new path is not executed locally (CI covers bash
  suites on Linux and macOS only for this suite).

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-4141 | Spec-AC-01 | integration | tests/skills/test-aai-doc-number-reservation.sh | test_301_azure_singleton_confirmed allocates a draft on the Azure-shaped stub and requires exit 0, the renamed file, the ref in the bare origin, no number_reserved line and no WARNING | `sed:s/platform === 'azure'/platform === 'azure-off'/` on .aai/scripts/allocate-doc-number.mjs | green |
| TEST-4142 | Spec-AC-02 | integration | tests/skills/test-aai-doc-number-reservation.sh | test_302_azure_coupled_family_confirmed allocates a coupled FAMA+FAMB draft on the stub and requires both refs at 6 and no marker | `sed:s/const AZURE_PUSH_FLAGS = \[\];/const AZURE_PUSH_FLAGS = ['--atomic'];/` on .aai/scripts/allocate-doc-number.mjs | green |
| TEST-4143 | Spec-AC-02 | integration | tests/skills/test-aai-doc-number-reservation.sh | test_303_azure_coupled_partial_released pre-creates FAMB-0006 and calls reserveAtomic for the pair at 6; requires number 7, FAMA-0006 absent, both 7 refs present | `sed:s/for \(const ref of claimed\.slice\(\)\.reverse\(\)\)/for (const ref of [])/` on .aai/scripts/allocate-doc-number.mjs | green |
| TEST-4144 | Spec-AC-03 | integration | tests/skills/test-aai-doc-number-reservation.sh | test_304_azure_race_one_winner starts two clones of one stub origin in parallel, each reserving CHANGE from 5, and requires the two numbers to differ with exactly one equal to 5, repeated for a coupled pair | `sed:s/const lease = createOnlyLease\(ref\);/const lease = '--force';/` on .aai/scripts/allocate-doc-number.mjs | green |
| TEST-4145 | Spec-AC-04 | integration | tests/skills/test-aai-doc-number-reservation.sh | test_305_azure_reserve_completes_provisional runs --guard (exit 4), --reserve (exit 0, marker gone, ref created), --guard (exit 0), then --reserve on a taken number (exit 4, marker kept) | `sed:s/const res = reservationPush\(root, 'origin', refNames\);/const res = pushReservation(root, 'origin', refNames);/` on .aai/scripts/allocate-doc-number.mjs | green |
| TEST-4146 | Spec-AC-05 | integration | tests/skills/test-aai-doc-number-reservation.sh | test_306_azure_rejection_reason_verbatim adds a pre-receive hook refusing refs/aai/* with a fixed message; requires exit 0, the marker, the hook's message and the remote rejected line in the WARNING, no Locking support line, the omission note and one hook invocation | `sed:s/const LFS_ADVISORY = /const LFS_ADVISORY = \/(?!)\/; const LFS_UNUSED = /` on .aai/scripts/allocate-doc-number.mjs | green |
| TEST-4147 | Spec-AC-05 | unit | tests/skills/test-aai-doc-number-reservation.sh | test_307_push_failure_masks_credentials calls describePushFailure on output naming https://user:secret@dev.azure.com and requires the secret absent and the host present | `sed:s/\.replace\(URL_USERINFO, '\$1'\)/.replace(URL_USERINFO, (m) => m)/` on .aai/scripts/allocate-doc-number.mjs | green |
| TEST-4148 | Spec-AC-06 | integration | tests/skills/test-aai-doc-number-reservation.sh | test_308_transport_selected_by_detection runs four arms. An Azure origin URL with a local pushurl and no record reserves a coupled pair; platform github, an unknown local origin and no origin give default; platform github on the non-atomic stub leaves the coupled pair provisional | `sed:s/platform === 'azure'/platform !== 'none'/` on .aai/scripts/allocate-doc-number.mjs | green |
| TEST-4149 | Spec-AC-07 | integration | tests/skills/test-aai-doc-number-reservation.sh | test_309_azure_guard_cross_branch_collision stages a doc whose number exists on the base ref under another slug on the Azure stub and requires --guard exit 4 naming the cross-branch collision | `sed:s/if \(baseId != null && baseId !== doc\.id\) \{/if (false) {/` on .aai/scripts/allocate-doc-number.mjs | green |
| TEST-4150 | Spec-AC-08 | integration | tests/skills/test-aai-doc-number-reservation.sh | test_310_default_transport_unchanged runs a coupled pair against the non-atomic stub with no platform record and a local origin (default transport) and requires the provisional marker and no ref at that number, then relies on the whole suite run for TEST 001 to 018 and 101 to 109 | `sed:s/=== 'azure-sequential'\) return pushReservationSequential/!== 'none') return pushReservationSequential/` on .aai/scripts/allocate-doc-number.mjs | green |
| TEST-4151 | Spec-AC-09 | inspection | tests/skills/test-aai-doc-number-reservation.sh | test_311_azure_docs greps the USER_GUIDE and TECHNOLOGY paragraphs, the CHANGELOG heading and the product doc for the transport, the detection rule and the --reserve completion | `sed:s/Azure Repos/Azure Repo/g` on docs/USER_GUIDE.md | green |

## Verification

- R for each selector (RED on the unchanged allocator for TEST-4141 to
  TEST-4147 and TEST-4148's positive arm; TEST-4149, TEST-4150 and TEST-4151
  record RED as their mutation run), then R for the whole suite.
- `tests/skills/test-aai-doc-numbering.sh` through the same wrapper.
- Between rounds: the suites from
  `node .aai/scripts/select-suites.mjs --files-from <changed files>` plus CORE.
- One full sweep before close:
  `env -u AAI_ROLE XDG_CACHE_HOME=$(mktemp -d) AAI_TEST_TIMEOUT=3600 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh`.
- `node .aai/scripts/mutation-run.mjs` for every Test Plan row;
  `node .aai/scripts/mutation-gate.mjs` PASS; `spec-amend.mjs list --strict`.

## Evidence contract

- ref_id `azure-rejects-doc-number-reservation-push`. RED and GREEN logs under
  `docs/ai/tdd/azure-rejects-doc-number-reservation-push/`; mutation records
  under `docs/ai/tdd/spec-azure-rejects-doc-number-reservation-push/`.
- Validation report
  `docs/ai/reports/VALIDATION-<ts>-azure-rejects-doc-number-reservation-push.md`;
  review report under docs/ai/reviews/.

### Evidence by strategy

tdd: a stored RED artifact for each AC-gating test plus the verification
above. TEST-4141 to TEST-4148 and TEST-4151 fail on the unchanged tree and
store that RED. TEST-4149 and TEST-4150 hold on the unchanged tree (they pin
behaviour that must not move), so their RED is the named mutation run.

## Registry items closed by this scope

none

## Registry items this scope leaves open

- `fu-azure-live-proof-on-adoption`: the live Azure proof for the PR platform
  adapter; this scope adds its own live item (fu-azure-docnum-live-namespace)
  rather than claiming that one.
- `fu-numbering-rewrites-dated-reports`, `fu-restamp-slug-links-unverified`,
  `fu-restamp-shape-ignores-intake-rename`: allocator rename behaviour, not
  the reservation transport.

## Amendment A1 (Implementation, measurement only, additive with disclosure)

- TEST-4147 Mutation cell: the frozen replacement `'$&'` is itself a
  JavaScript replacement pattern, so mutation-run.mjs expanded it to the
  matched text and the mutated allocator no longer parsed (exit 2, no record).
  The replacement is now `(m) => m`, which makes the same change in behaviour
  (the userinfo is kept, so the credential leaks) without a `$` token.
- TEST-4148 Description: the selector was followed by a colon, which
  mutation-run.mjs read as part of the selector name. Wording only.
- No Spec-AC, verification command or observable changed.

