# Code review: azure-rejects-doc-number-reservation-push (round 1)

```yaml
review:
  scope: origin/main...HEAD of fix/azure-rejects-doc-number-reservation-push (HEAD f305efe7)
  spec: docs/specs/SPEC-0320-spec-azure-rejects-doc-number-reservation-push.md (frozen, amendments A1, A2)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/allocate-doc-number.mjs:516-529, 573-596; TEST-4141 PASS" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/allocate-doc-number.mjs:561-591; TEST-4142, TEST-4143 PASS (deviation D1 below on a refused release)" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/allocate-doc-number.mjs:579-581 (sorted order, createOnlyLease); TEST-4144 PASS" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/allocate-doc-number.mjs:1338; TEST-4145 PASS" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/scripts/allocate-doc-number.mjs:509-511, 533-546, 585-589; TEST-4146, TEST-4147 PASS" }
      - { ac: Spec-AC-06, call: compliant, citation: ".aai/scripts/allocate-doc-number.mjs:88-94, 516-529; TEST-4148 PASS" }
      - { ac: Spec-AC-07, call: compliant, citation: "guard untouched by the diff; TEST-4149 PASS (pins unchanged behaviour, validation N7)" }
      - { ac: Spec-AC-08, call: compliant, citation: "pushReservation unedited (diff has no hunk in it); .aai/scripts/allocate-doc-number.mjs:593-596; TEST-4150 + TEST-001..018, 101..109 PASS" }
      - { ac: Spec-AC-09, call: compliant, citation: "docs/USER_GUIDE.md:1182-1200, docs/TECHNOLOGY.md:62-66, CHANGELOG.md:33, docs/product/azure-rejects-doc-number-reservation-push.md; TEST-4151 PASS (one product-doc sentence is false on the collision path, NB-1)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/allocate-doc-number.mjs, line: 609,
          issue: "a failed release on the collision path is silent: pushReservationSequential builds 'could not release <ref>: <reason>' into res.error, but reserveAtomic's collision branch (609-610) and runReserveCompletion's collision die (1346-1347) never print res.error",
          failure_scenario: "Azure, coupled FAMA+FAMB at 6, FAMB-0006 already taken, server refuses the delete of the just-claimed FAMA-0006 (e.g. no Force push permission on the namespace): reserveAtomic returns ok at 7, stderr is empty, FAMA-0006 stays orphaned in origin, and the operator never learns deletes are refused. Repro: /private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/repro/release-failure-silent-on-collision.sh <worktree> exits 1 with 'DEFECT REPRODUCED'." }
  cannot_verify:
    - { claim: "Azure Repos accepts a create push to refs/aai/docnums/*", closes_with: "one live Azure reservation (fu-azure-docnum-live-namespace)" }
    - { claim: "Azure Repos lets the pusher delete its own refs/aai/* ref with a lease (D-ROLLBACK release)", closes_with: "live Azure delete under a Contributor identity (fu-azure-docnum-live-namespace); until NB-1 is fixed a refusal on the collision path would not even be visible" }
    - { claim: "Azure Repos advertises refs/aai/* refs, so the client-side create-only lease sees an existing ref and reports (stale info)", closes_with: "live ls-remote + duplicate push against Azure; if refs/aai/* are hidden the server answers with a remote-rejected line, which is classified non-collision (provisional) instead of a retry, and the D3c ls-remote scan is blind" }
    - { claim: "LFS_ADVISORY matches the advisory text of the git-lfs versions operators run", closes_with: "capture from a real git-lfs pre-push against a non-locking remote; only fixture text is tested" }
    - { claim: "the new path runs on Windows", closes_with: "a Windows run of the reservation suite (spec residual risk)" }
    - { claim: "this branch and PR #535 compose at runtime after both merge", closes_with: "run the reservation suite on a tree holding both changes; reviewer only did a 3-way merge-file simulation and read #535's harness" }
    - { claim: "full sweep green and mutation gate PASS", closes_with: "validation round 2 report (144/145 pass, 1 named pre-existing skip); reviewer did not re-run the sweep; mutation evidence is gitignored and local-only" }
  overall: pass
```

security_relevant: false

## Scope and contract

- Scope: `git diff origin/main...HEAD` on fix/azure-rejects-doc-number-reservation-push, HEAD f305efe7, 4 commits, 12 files. `docs/ai/STATE.yaml` worktree.user_decision is `worktree`, so the branch diff is the scope. `git status --porcelain` shows only `docs/ai/EVENTS.jsonl` and `docs/ai/tests/test-runs.jsonl` modified (ledger appends from earlier rounds and from the targeted suite run below), both outside the code under review.
- Contract: the frozen spec above and the intake docs/issues/ISSUE-0128-azure-rejects-doc-number-reservation-push.md.
- Dispatch check: the dispatch named focus files and asked for a composition judgement on PR #535; it did not pre-rate findings or exclude areas. The whole diff was reviewed.

## AC table walk

| Spec-AC | Call | Citation |
|---|---|---|
| 01 singleton confirmed on Azure | compliant | `reservationTransportFor` (allocate-doc-number.mjs:516-529) picks `azure-sequential` on `platform === 'azure'`; `pushReservationSequential` (573-591) pushes without `--atomic`. TEST-4141 PASS, asserts the ref in the real bare origin and no WARNING. |
| 02 coupled family, partial claim released | compliant | Sorted per-ref pushes (579), release newest first with an sha-bound lease (561-569), collision keeps classification (586-589). TEST-4142, TEST-4143 PASS. Deviation D1 below. |
| 03 race, one winner | compliant | Create-only lease per ref, same first ref for all contenders. TEST-4144 PASS; its sequential arm deterministically kills the `--force` mutation. |
| 04 `--reserve` completes a provisional doc | compliant | Call site 1338 now dispatches. TEST-4145 PASS (guard 4, reserve 0, guard 0, taken ref exits 4 with marker kept). |
| 05 refusal reason verbatim, one push | compliant | `describePushFailure` (533-546), `LFS_ADVISORY`/`URL_USERINFO` (509-510). TEST-4146 (one hook invocation, remote line verbatim) and TEST-4147 (masking, both advisory variants) PASS. |
| 06 selected only by resolvePlatform | compliant | Guarded dynamic import (88-94), `remote !== 'origin'` short-circuit (516). TEST-4148 PASS: URL arm, github/unknown/none/azure probe arm, github on a non-atomic stub stays provisional. |
| 07 guard still catches cross-branch | compliant | Guard code not in the diff. TEST-4149 PASS; it pins unchanged behaviour (validation N7, carried). |
| 08 default transport unchanged | compliant | No hunk inside `pushReservation`; default dispatch at 593-596. TEST-4150 and the pre-existing TEST-001..018 and 101..109 PASS in the run below. Only new default-path work: one `git remote get-url origin` per process and the import of `pr-platform.mjs`, which has no import-time side effects (`runMain` is behind `isMain`). Both files are in the `core:` list of `.aai/system/PROFILES.yaml` (lines 197, 244), so a core-profile downstream gets the adapter and never sees the NOTE line. |
| 09 user docs | compliant | USER_GUIDE paragraph, TECHNOLOGY bullet, CHANGELOG per-entry `## [unreleased] —` heading, product doc. TEST-4151 PASS. One product-doc sentence ("a failed delete is named in the warning") is false on the collision path, see NB-1. |

TEST evidence: every Test Plan id (TEST-4141 to TEST-4151) exists in tests/skills/test-aai-doc-number-reservation.sh and is registered in `main()`. Reviewer run: `env -u AAI_ROLE XDG_CACHE_HOME=$(mktemp -d) bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-doc-number-reservation.sh` exit 0, 39 PASS lines, "All doc-number-reservation tests passed." RED and GREEN logs exist under docs/ai/tdd/azure-rejects-doc-number-reservation-push/ and mutation records under docs/ai/tdd/spec-azure-rejects-doc-number-reservation-push/ (11 files), local and gitignored.

### Deviations from the frozen spec

- D1: Root cause, "Assumed, not verified", second bullet says "A refused release is named, never silent." D-ROLLBACK's literal text ("named in the error text") holds inside `pushReservationSequential`, but on the collision path both callers discard that text, so a refused release is silent there. Same root as NB-1.
- No other deviation found. The anchors the Implementation plan lists each occur once.

## Findings

### NB-1 (NON-BLOCKING, P2): a failed release is silent when the failing push was a collision

- Where: .aai/scripts/allocate-doc-number.mjs:609-610 (`reserveAtomic` retries on `res.collision` and drops `res.error`), and :1346-1347 (`runReserveCompletion` dies with a fixed collision message and no `res.error`). The release text is built at :587-589.
- Failure scenario: on Azure a coupled family FAMA+FAMB reserves at 6 while FAMB-0006 already exists. FAMA-0006 is claimed, FAMB-0006 collides, and the release of FAMA-0006 is refused by the server. `reserveAtomic` returns `{ ok: true, number: 7 }`, nothing is printed, and FAMA-0006 stays in origin. Measured with a pre-receive hook that refuses deletes: stderr 0 bytes, refs FAMA-0006, FAMA-0007, FAMB-0006, FAMB-0007 in origin. Repro: /private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/repro/release-failure-silent-on-collision.sh (run with the worktree root as its argument; exits 1 and prints `DEFECT REPRODUCED`).
- Why it matters more than a burned number: the spec does not know whether Azure lets a Contributor delete a `refs/aai/*` ref, and it relies on a refused release being named so the first field report says so. On the collision path, which is the main reason a release runs at all, that signal never appears. The product doc (docs/product/azure-rejects-doc-number-reservation-push.md:56-57) also states "a failed delete is named in the warning", which is false on this path. Numbering integrity is not affected: an orphan only burns a number.
- Not covered by existing follow-ups: fu-azure-docnum-release-fail-test asks only for a test of the branch, and fu-azure-docnum-release-orphan is about the non-collision path, whose WARNING does carry the text.
- Recommended disposition: (a) remediate in this branch. For example, `pushReservationSequential` returns the release failures in their own field, and `reserveAtomic` and `runReserveCompletion` print them as a `WARNING:` before retrying or dying. Add a regression test in the shape of the repro above, which also closes fu-azure-docnum-release-fail-test. If that is deferred, use (b): a typed follow-up at P2, and correct the product-doc sentence in the meantime, because it is a false record and so cannot be accepted as a residual.

### INFO (no failure scenario, does not gate)

- I-1: `const AZURE_PUSH_FLAGS = [];` (allocate-doc-number.mjs:508) exists only as a mutation anchor for TEST-4142. It is harmless, but it reads as configuration.
- I-2: The concurrent arm of TEST-4144 cannot prove that the two node processes overlap. The deterministic sequential arm carries the mutation kill, so coverage holds.

## Composition with PR #535 (read only; nothing posted to or changed on #535)

PR #535 is open and CONFLICTING with main (last updated 2026-11-07). In `allocate-doc-number.mjs` it rewrites the body of `pushReservation` and adds `networkGit` plus a fetch/ls-remote branch in `git()`.

- Allocator text: the spec claims there is no overlapping hunk, and that holds. A 3-way `git merge-file` of this branch with #535 (base: #535's base blob 9cb521afa) is clean, and so is the two-step merge main+#535 then this branch. The result passes `node --check`. #535's last changed line in `pushReservation` and this branch's insertion point have unchanged lines between them, and this branch's call sites (607, 1338) are lines #535 does not touch.
- Runtime: #535's `transport_probe` git shim records only push/fetch/ls-remote and passes `git remote get-url origin` through to the real git. Its fixtures have a local origin and no platform record, so they resolve to the `default` transport and #535's push-count and argv assertions (TEST-201 to TEST-206) are unaffected. This was judged from reading, not run (see cannot_verify).
- Other files: the test file has one both-add conflict at the insertion point after `test_109` (both PRs append new test functions there). A union resolution is mechanical, and the `main()` registrations merge cleanly. docs/TECHNOLOGY.md and CHANGELOG.md merge cleanly. docs/USER_GUIDE.md conflicts only in the generated "Delivered features" section, which #535 already conflicts on against main; the narrative Azure paragraph does not conflict.
- Policy difference for the owner at merge: #535 deliberately replaces git stderr with a category remedy ("never credential-bearing Git stderr"), while the Azure path quotes git output verbatim with URL userinfo masked, as the intake requires. After both merge, the two transports disclose differently. That follows from the spec (D-535 names it), but the owner should know. The missing deadline on the Azure path is already tracked as fu-azure-docnum-network-deadline.

## Warning dispositions (H6)

- NB-1: recommended (a) remediate-in-tree. The orchestrator records the chosen artifact. Fallback is (b), a typed follow-up (suggested id `fu-azure-docnum-release-silent-on-collision`, P2, not filed by the reviewer) plus correcting the product-doc sentence.

## Next steps

1. Remediate NB-1 with a RED-first test (pre-receive hook refusing deletes, collision at member 2, assert a `could not release` WARNING). Then re-run the targeted suite and the mutation row for TEST-4143.
2. Re-review is a delta round on the allocator and the test file.
