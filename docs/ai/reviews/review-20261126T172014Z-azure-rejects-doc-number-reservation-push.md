# Code review: azure-rejects-doc-number-reservation-push (round 2, after NB-1 remediation)

```yaml
review:
  scope: origin/main...HEAD of fix/azure-rejects-doc-number-reservation-push (HEAD cebded64); delta f305efe7..cebded64 read with extra attention
  spec: docs/specs/SPEC-0320-spec-azure-rejects-doc-number-reservation-push.md (frozen, amendments A1, A2, A3)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/allocate-doc-number.mjs:516-529, 573-594; TEST-4141 PASS" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/allocate-doc-number.mjs:561-591; TEST-4142, TEST-4143 PASS" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/allocate-doc-number.mjs:579-581; TEST-4144 PASS (the loser of an in-flight race is not retried, NB-1)" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/allocate-doc-number.mjs:1341, 1349-1352; TEST-4145 PASS" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/scripts/allocate-doc-number.mjs:508-546, 586-591; TEST-4146, TEST-4147, TEST-4152 PASS; TEST-4152 mutation re-run by reviewer reddens" }
      - { ac: Spec-AC-06, call: compliant, citation: ".aai/scripts/allocate-doc-number.mjs:88-94, 516-529; TEST-4148 PASS" }
      - { ac: Spec-AC-07, call: compliant, citation: "guard not in the diff; TEST-4149 PASS" }
      - { ac: Spec-AC-08, call: compliant, citation: "no hunk inside pushReservation (476-504); dispatch 596-599; TEST-4150 and TEST-001..018, 101..109 PASS" }
      - { ac: Spec-AC-09, call: compliant, citation: "docs/USER_GUIDE.md, docs/TECHNOLOGY.md, CHANGELOG.md, docs/product/azure-rejects-doc-number-reservation-push.md; TEST-4151 PASS; product-doc 'a failed delete is named in the warning' now true on both paths" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/allocate-doc-number.mjs, line: 586,
          issue: "the loser of an in-flight reservation race is classified non-collision: when both pushes read the ref advertisement before either lands, the client lease passes and the server answers '! [remote rejected] <sha> -> <ref> (reference already exists)', which /stale info/ does not match, so reserveAtomic stops instead of retrying the next number. Pre-existing on the default path (there the answer is '(atomic transaction failed)', pushReservation:501); the Azure path inherits it. TEST-4144's concurrent arm accepts 'failed other' as a loser outcome, so it passes either way.",
          failure_scenario: "two clones on Azure allocate a CHANGE at the same moment, both pushes in flight together: one gets CHANGE-0005, the other is stamped number_reserved: false at 0005 with a WARNING, and its later --reserve exits 4 asking for a renumber instead of having landed on 0006. Measured with git 2.54.0 on a local bare with receive.advertiseAtomic=false: 40/40 concurrent create-only pushes of one ref gave the loser 'reference already exists' and never 'stale info' (scratchpad/race); with --atomic on an atomic-capable bare, 20/20 gave 'atomic transaction failed'. Never a duplicate confirmed number." }
  cannot_verify:
    - { claim: "Azure Repos accepts a create push to refs/aai/docnums/*", closes_with: "one live Azure reservation (fu-azure-docnum-live-namespace)" }
    - { claim: "Azure Repos lets the pusher delete its own refs/aai/* ref with a lease (D-ROLLBACK release)", closes_with: "live Azure delete under a Contributor identity; a refusal is now named on both paths (TEST-4152)" }
    - { claim: "Azure Repos advertises refs/aai/* refs, so a sequential duplicate is reported as (stale info) and retried", closes_with: "live ls-remote plus a duplicate push against Azure; if hidden, every collision takes the NB-1 classification (provisional, not retry) and the D3c scan is blind" }
    - { claim: "Azure's server-side wording for a lost in-flight race", closes_with: "a live concurrent push; it decides whether a remedy for NB-1 can match a stable string" }
    - { claim: "LFS_ADVISORY matches the advisory text of the git-lfs versions operators run", closes_with: "capture from a real git-lfs pre-push against a non-locking remote; only fixture text is tested" }
    - { claim: "the new path runs on Windows", closes_with: "a Windows run of the reservation suite (spec residual risk)" }
    - { claim: "this branch and PR #535 compose at runtime after both merge", closes_with: "run the reservation suite on a tree holding both; reviewer re-checked only that #535 is unchanged since 2026-11-07 and that the delta adds lines inside pushReservationSequential, away from #535's allocator hunks" }
    - { claim: "full sweep green and mutation gate PASS at cebded64", closes_with: "docs/ai/reports/VALIDATION-20261126T171700Z-azure-rejects-doc-number-reservation-push.md (144/145, 1 pre-existing skip); reviewer did not re-run the sweep; mutation evidence is gitignored and local-only" }
  overall: pass
```

security_relevant: false

## Scope and contract

- Scope: `git diff origin/main...HEAD`, HEAD cebded64, 5 commits, 12 files. `docs/ai/STATE.yaml` has `worktree.user_decision: worktree`, so the branch diff is the scope. `git status --porcelain` shows `docs/ai/EVENTS.jsonl` and `docs/ai/tests/test-runs.jsonl` modified (ledger appends) and the untracked round-1 review report; none is code under review.
- Delta reviewed with extra attention: `git diff f305efe7..HEAD` (allocator +3 lines, TEST-4152, spec Amendment A3, decisions and ledger appends).
- Contract: the frozen spec and the intake docs/issues/ISSUE-0128-azure-rejects-doc-number-reservation-push.md.
- Dispatch check: the dispatch did not pre-rate findings or exclude areas. It pointed at the delta and asked for the whole scope, and the whole scope was reviewed.

## AC table walk

| Spec-AC | Call | Citation |
|---|---|---|
| 01 | compliant | `reservationTransportFor` picks `azure-sequential` on `platform === 'azure'`; `pushReservationSequential` pushes without `--atomic`. TEST-4141 PASS. |
| 02 | compliant | Sorted per-ref pushes, sha-bound release newest first, collision classification kept. TEST-4142, TEST-4143 PASS. |
| 03 | compliant | Same first ref for every contender, create-only lease. TEST-4144 PASS. The AC ("grant that number to exactly one") holds even in an in-flight race. The loser is not retried, though (NB-1). |
| 04 | compliant | `--reserve` dispatches through `reservationPush` (1341). TEST-4145 PASS. On the collision path the refused-release WARNING now prints before `die(4)`. |
| 05 | compliant | `describePushFailure`, `LFS_ADVISORY`, `URL_USERINFO`; the delta's line 590 prints the `could not release` lines on the collision path. TEST-4146, TEST-4147, TEST-4152 PASS. Putting TEST-4152 under Spec-AC-05 stretches that AC's wording (non-collision refusal), but Amendment A3 discloses it. |
| 06 | compliant | Guarded dynamic import, `remote !== 'origin'` short-circuit. TEST-4148 PASS. |
| 07 | compliant | Guard untouched. TEST-4149 PASS. |
| 08 | compliant | `pushReservation` has no hunk. TEST-4150 and every pre-existing test PASS. |
| 09 | compliant | USER_GUIDE, TECHNOLOGY, CHANGELOG (per-entry `## [unreleased] —` heading), product doc. TEST-4151 PASS. The product-doc sentence that round 1 found false is now true. |

TEST evidence (reviewer runs):
- `env -u AAI_ROLE XDG_CACHE_HOME=$(mktemp -d) bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-doc-number-reservation.sh`: exit 0, 40 PASS lines, "All doc-number-reservation tests passed." TEST-4141 to TEST-4152 are all defined and registered in `main()`.
- TEST-4152 bite: the Test Plan mutation (`if (collision && released.length)` to `if (false)`) applied to a `git archive HEAD` copy in the scratchpad (never the worktree). `test_312_azure_release_failure_named` then FAILS with "Expected 'could not release refs/aai/docnums/FAMA-0006' in .../arm1.err".
- Round-1 NB-1 repro (`scratchpad/repro/release-failure-silent-on-collision.sh <worktree>`): it now prints "not reproduced" and exits 0.
- Mutation anchors: every Implementation-plan anchor, plus A3's new anchor, occurs exactly once in the allocator. `node --check` passes. `spec-amend.mjs list --strict` exits 0, and A3 is listed as `unsigned-tracked` by `fu-amend-azure-rejects-doc-number-d5f519` (open, P2, owner sign-off owed).
- `git ls-files -ci --exclude-standard` is empty. No reports, tdd or reviews files are committed in the diff.

### Deviations from the frozen spec

- None open. Round 1's D1 ("a refused release is named, never silent" was false on the collision path) is closed by the delta and TEST-4152.
- Amendment A3 is a `contract`-class post-freeze amendment without owner sign-off. It is disclosed and tracked (`fu-amend-azure-rejects-doc-number-d5f519`). The owner accepts or reverses it.

## Delta review (f305efe7..cebded64)

- Allocator line 590: `if (collision && released.length) console.error(\`WARNING: ${released.join('\n')}\`);`. It prints only on the collision path, so the non-collision path does not print twice (its caller already puts `res.error` into the provisional warning at 1285 and 1352). It covers both callers: `reserveAtomic`'s silent retry and `runReserveCompletion`'s `die(4)`. When a coupled family has more than one release failure, the lines after the first carry no `WARNING:` prefix. That is cosmetic and has no failure mode.
- TEST-4152: arm 1 asserts the collision-path stderr and arm 2 the non-collision `res.error`. The hook refuses deletes and the FAMB-0009 create only. Arm 1's retry at 7 is therefore not affected, and the round-1 follow-up fu-azure-docnum-release-fail-test is legitimately closed by it.
- Spec A3 and the ledger entries: verified against the text. The amendment exists in the spec, the Test Plan row and the AC-05 evidence cell list TEST-4152, and `frozen_sha256` was re-pinned.
- The amendment cites the round-1 report, which is still untracked in the worktree. It must be staged with the scope (SKILL_CODE_REVIEW report staging), or the spec's citation dangles after merge.

## Findings

### NB-1 (NON-BLOCKING, P3): a lost in-flight race is provisional, not retried

- Where: .aai/scripts/allocate-doc-number.mjs:586 (`const collision = /stale info/i.test(r.out);`), which mirrors pushReservation:501. The test gap is tests/skills/test-aai-doc-number-reservation.sh:1131-1143.
- Failure scenario: two clones push the same reservation ref while both pushes are in flight. Each client read the advertisement before the other's update landed, so the create-only lease passes on both. The server then refuses the second update with `! [remote rejected] <sha> -> <ref> (reference already exists)`. That line does not contain "stale info", so the push is a non-collision failure, and the losing allocation is stamped `number_reserved: false` at the winner's number instead of retrying at N+1. That loser's `--reserve` later exits 4 (renumber). Measured: 40/40 concurrent non-atomic pushes gave this message to the loser. 20/20 concurrent `--atomic` pushes on the default path gave `(atomic transaction failed)`, so the class predates this change.
- Why not BLOCKING: this change did not introduce it (the default path shares it, and D-GENERIC forbids editing `pushReservation`). It never yields a duplicate confirmed number: the marker plus the guard catch it. Spec-AC-03's wording still holds. TEST-4144's concurrent arm records `failed other` for such a loser and still passes, so the suite neither proves nor disproves a retry.
- Recommended disposition: (b) a typed follow-up, P3, suggested id `fu-docnum-inflight-race-not-collision` (not filed by the reviewer). Suggested what: treat a `(reference already exists)` remote rejection on a create-only push as a collision (Azure path first; default path once #535 settles `pushReservation`), and make TEST-4144's concurrent arm assert the loser's outcome. Disposition (d) is not available because the defect was measured biting at the git level.

### INFO (no failure mode, does not gate)

- I-1: `const AZURE_PUSH_FLAGS = [];` is still a mutation anchor only (carried from round 1).
- I-2: The multi-line refused-release WARNING prefixes only its first line.

## Composition with PR #535 (read only)

PR #535 is unchanged since 2026-11-07 (head b1c76b98, CONFLICTING with main). Its allocator hunks are at the header, `createReservationCommit`, `pushReservation` and the `git()` helper. The delta adds three lines inside `pushReservationSequential`, which is new code #535 does not have. Round 1's composition analysis (clean 3-way merge of the allocator, one mechanical both-add conflict in the test file) is unaffected by the delta. Nothing was posted to #535 or changed on it.

## Warning dispositions (H6)

- NB-1 (P3): recommended (b), a typed follow-up `fu-docnum-inflight-race-not-collision` (suggested, not filed). The orchestrator records it with `follow-ups.mjs add` and names the id in `code_review.notes`.

## Next steps

1. Orchestrator: file the NB-1 follow-up, then record this review with the command below.
2. Stage both review reports (round 1 and this one) with the scope at PR time.
3. The owner signs off on or reverses Amendment A3 (`fu-amend-azure-rejects-doc-number-d5f519`).
