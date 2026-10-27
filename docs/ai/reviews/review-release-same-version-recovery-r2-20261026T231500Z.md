```yaml
review:
  scope: origin/main...HEAD (20ee3591..a5abcf7b) in /private/tmp/aai-relrec, branch change/release-same-version-recovery; focus r1 closure and remediation f09333ad
  spec: docs/specs/SPEC-0255-spec-release-same-version-recovery.md (amended: D11, Spec-AC-03/07 extended, TEST-118..122)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "release-finish.mjs:592 recutIfMoved, :633-653 push/follow/edit ; TEST-101 (sh + pwsh arm), TEST-102, TEST-114 green (reviewer re-run at a5abcf7b)" }
      - { ac: Spec-AC-02, call: compliant, citation: "release-finish.mjs:411 (fromHead null when never pushed and no PR) ; TEST-113 green" }
      - { ac: Spec-AC-03, call: compliant, citation: "abandonRecut :379-401, settlePrAfterPreflight :403-407, fold :421-425, allowedHeads :418-419, pushRelease PR re-read :473 ; TEST-103/104/105/116/117/118/119/120/122 green; reviewer probes PROBE-MERGED, PROBE-WINDOW (r1 reproducers) now rc=0; PROBE-RESTORE exact restore; PROBE-FOREIGN-LOCAL refuses with journal byte-identical" }
      - { ac: Spec-AC-04, call: compliant, citation: "stage('recut') :439 ; TEST-111 green" }
      - { ac: Spec-AC-05, call: compliant, citation: "unchangedBase :361 detail, :667/:675 ; TEST-112 green" }
      - { ac: Spec-AC-06, call: compliant, citation: "releasePreflight :456-469, pushRelease :471-477 ; TEST-106, TEST-107 green" }
      - { ac: Spec-AC-07, call: compliant, citation: "preflightSeconds :42-44, :564 ; detached spawn + process.kill(-pid) :446-449 ; TEST-108, TEST-121 green (POSIX). Windows arm disclosed as a limit in D11(c); see INFO-1 and cannot_verify" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-109, TEST-110 green; SKILL_RELEASE.prompt.md measured 4921 B" }
      - { ac: Spec-AC-09, call: cannot-verify, citation: "deferred post-merge live acceptance; TEST-115 prints SKIP without AAI_RELEASE_LIVE_ACCEPTANCE" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/release-finish.mjs, line: 644,
          issue: "A re-cut that is pushed and journaled, whose PR GitHub then merges on the OLD head (before headRefOid followed the push), refuses identity on every later run; nothing rolls the journal back to the merged binding, so the release is never published without hand-editing the journal",
          failure_scenario: "pushRelease reads PR OPEN, the leased push lands, then a merge of the old head (auto-merge firing on a re-run check of the old head, or an operator click) completes before GitHub processes the push. Journal: stage pushed, head=H2, recuts=[H1->H2], notes=new rollup. Every run: :641 poll returns MERGED with headRefOid=H1, :646 refuses 'preserve the journal for recovery'. Reproduced (reviewer PROBE-OLDHEAD-MERGE): two runs rc=20 with that refusal, releases=0. The remediator named this window as untested. abandonRecut's restore logic (drop the last recuts entry, restore fromBase/fromHead, recompute notes) would close it." }
    info:
      - "INFO-1 release-finish.mjs:449 — on win32 spawnSync has already terminated the runner when taskkill /PID <runner> /T /F runs, so the Windows branch most likely reaches no process at all (the comment says it reaches 'children the dead runner still parents'; a dead runner parents none). D11(c) discloses the Windows leak as a documented limit, so this is wording, not a spec deviation. State it as 'Windows: a timed-out test process is not killed'."
      - "INFO-2 release-finish.mjs:449 — process.kill(-r.pid,'SIGKILL') also runs after a normal exit; if the group is empty and the pid was recycled as a new group leader, an unrelated group is killed. Window is tiny; ESRCH is caught."
      - "INFO-3 release-finish.mjs:659 — `if(!head)pushRelease();` ignores pushRelease's false return; safe today only because record.pr is always null on that path."
      - "INFO-4 spec Implementation plan steps 2 and 4 still name the pre-remediation literals (`if(pr.state==='MERGED')return;`, `if(remote!==record.recut.fromHead&&remote!==record.head)refuse('head-moved',`, `p=>p.headRefOid===record.head`); the Mutation cells were amended and recorded in decisions.jsonl, the plan prose was not."
  cannot_verify:
    - { claim: "GitHub updates an open PR's headRefOid after a force-push and gh pr edit --body-file works on it; how wide the old-head-merge window of NB-1 is on real GitHub", closes_with: "Spec-AC-09 live run on PR #504" }
    - { claim: "Windows: taskkill /T on an already-terminated runner pid kills nothing (INFO-1)", closes_with: "a Windows run of the TEST-121 shape" }
    - { claim: "The selected tests (tests/skills/lib/recheck.test.mjs today) run from a linked worktree of the production repository with the operator's full environment (gh credentials included) and do not write shared refs or config", closes_with: "audit of the selected tests' git/gh invocations, or running the preflight from a throwaway clone with a scrubbed env" }
    - { claim: "The 60 s default command() timeout is enough for `git worktree add --detach` of the real repository during the preflight", closes_with: "timing of the live run (Spec-AC-09)" }
    - { claim: "Mutation evidence binds to the reviewed head", closes_with: "mutation-gate.mjs run by Validation on the validated tree (the reviewer's copy of the gitignored records reported GATE PASS 21 rows, exempt=1 TEST-115)" }
  overall: pass
```

security_relevant: false

# Code review — release-same-version-recovery (round 2)

Scope: `git diff origin/main...HEAD` in `/private/tmp/aai-relrec` (20ee3591..a5abcf7b), 14 files; the remediation is f09333ad. Spec: `docs/specs/SPEC-0255-spec-release-same-version-recovery.md`, amended with D11, extended Spec-AC-03 and Spec-AC-07, and rows TEST-118 to TEST-122. Reviewer: claude-opus-5-5. The worktree was read-only; all runs were in scratch clones under `scratchpad/rr-cr-r2/`.

Coaching check: the dispatch listed what to re-probe (the r1 probes, abandonRecut correctness, any new wedge). It did not pre-rate findings or exclude areas. Nothing to record. The full scope was reviewed.

## Evidence run by the reviewer (clone of a5abcf7b, `env -u AAI_ROLE`)

- `bash tests/skills/test-aai-release.sh <selector>` for test_731 to test_750, test_739, test_740 and test_745: all rc=0. That gives PASS for TEST-101 to TEST-114 and TEST-116 to TEST-122. TEST-115 prints its named SKIP.
- Whole suite `bash tests/skills/test-aai-release.sh`: rc=0 in 472 s, `ALL TESTS PASSED`, 126 PASS lines, only the named TEST-115 SKIP (covers TEST-010/011/015/016/033/060-086 regression).
- `mutation-gate.mjs --spec <spec>` over a copy of the gitignored records: `GATE PASS: 21 row(s) satisfied degraded=0 unstamped=0 uncomparable=0 exempt=1`. The TEST-118 history holds one STAYED GREEN record (22:48:53Z) and a later RED (22:49:45Z), after the row was amended to assert "no new worktree prepared". That amendment is recorded in decisions.jsonl.
- `spec-lint.mjs --path <spec>`: LINT PASS. `spec-amend list --strict`: rc=0. Three unsigned-tracked contract amendments are listed under `fu-amend-release-same-version-recovery`.
- r1 reproducers, re-run unchanged against the new engine:
  - PROBE-MERGED (pending re-cut stopped after `payload`, PR merged externally): both runs rc=0, releases=1, no new head pushed. Closed.
  - PROBE-WINDOW (re-cut pushed but not journaled, base moved again): both runs rc=0. Closed.
- New r2 probes:
  - PROBE-RESTORE: for each stop step `recut`, `worktree` and `payload`, PR merged externally, then resume. Each run gives rc=0, and the journal's `baseHead`, `head`, `content` and `notes` are byte-equal to the journal before the re-cut. `recut` is null, no `recuts` entry exists, the local release branch is absent, no extra worktree exists, the release body equals the original notes, release-branch pushes=1 (only the first cut), and `pr edit`=0. abandonRecut restores exactly.
  - PROBE-FOREIGN-LOCAL (pending re-cut plus merged PR, local `chore/release-v1` moved to a foreign commit): `REFUSED: head-moved — Local refs/heads/chore/release-v1 is <sha>, not a head of this release`, and the journal is byte-identical.
  - PROBE-OLDHEAD-MERGE: the re-cut is pushed and journaled (stopped after `pushed`), then PR #1 is merged on the old head H1. Two runs, each rc=20: `REFUSED: identity — Release PR #1 is MERGED on <H1>, not on the re-cut head <H2>; preserve the journal for recovery`. releases=0. This is NB-1.
- `spawnSync(..., {detached:true})` on Node v22.23.1 puts the child in its own process group (pgid == pid). The process-group kill therefore works as designed on POSIX.

## r1 closure

| r1 finding | Status at a5abcf7b | Evidence |
|---|---|---|
| BLOCKING-1: pending re-cut force-pushed onto a MERGED PR and wedged | closed | `recutIfMoved` :372 sends a MERGED PR with a pending `recut` to `abandonRecut`. `pushRelease` :473 re-reads the PR and never pushes to a non-OPEN PR. `settlePrAfterPreflight` drops on MERGED and refuses on CLOSED. The poll at :643 accepts non-OPEN and never edits. Covered by TEST-118 and TEST-119 (both arms), PROBE-MERGED and PROBE-RESTORE. |
| NB-1: preflight timeout orphans the test process | closed on POSIX; Windows is a disclosed limit | Detached group and `process.kill(-pid)` at :446-449. TEST-121 green. See INFO-1. |
| NB-2: pushed-but-unjournaled pending re-cut wedges on a re-moved base | closed | Fold at :421-425 moves the lease to the pushed head. TEST-120 green; PROBE-WINDOW rc=0. |
| NB-3: PR state read once, minutes before the push | closed for the preflight window | PR re-read in `pushRelease` after the preflight. The remaining window (merge after the push, before GitHub follows) is NB-1 of this round. |
| INFO: ancestry failure reported as `base-rewritten` | promoted | `fu-release-recut-ancestry-cause-name` (P3) is in decisions.jsonl. |

## abandonRecut correctness (requested focus)

- All checks run before any mutation, in this order: merged head vs `fromHead`; the `fromHead` CHANGELOG blob vs a fresh rollup of `fromBase:CHANGELOG.md`; the local branch head vs the release's own heads. Only after all three pass are the worktree, the local ref and the record changed. A refusal leaves the journal byte-identical (PROBE-FOREIGN-LOCAL).
- The notes check reads the merged `fromHead` blob, not the working tree.
- `rollup()` depends only on the CHANGELOG text and the version (no date), so recomputing it on a later day reproduces the original. PROBE-RESTORE shows `content` and `notes` byte-equal.
- Nothing is published from a head that was not merged. On the drop path, `record.head` returns to `fromHead`, the merged head. Publication then checks the merge commit, tag and notes against that binding.
- Case A: the re-cut was pushed and then merged on the new head, and only the journal write was missing. The engine folds the re-cut into `recuts` and keeps the new binding, which is consistent with the merged content.
- The local-branch "ours" set includes `record.baseHead` and `cut.fromBase`. Deleting `chore/release-v1` when it points at a base commit loses nothing, because the commit stays reachable from the base.

## AC table walk

See the YAML block. All rows TEST-101 to TEST-122 pass at a5abcf7b. Spec-AC-03 was non-compliant in r1 and is compliant now: the merged-with-pending-re-cut clause (stopped after `recut`, or refused `release-preflight`), the merged-during-preflight clause, the pushed-not-journaled clause and the absent-branch clause are each tested and were each reproduced by the reviewer's probes. Spec-AC-09 is deferred by design.

## Deviations from the frozen spec (all listed)

1. Carried from r1 and still present: the pre-checks call site (:667) still runs `unchangedBase()` and does not re-cut. This is consistent with D5 ("one re-cut per invocation") and was disclosed.
2. The Implementation plan prose still names three pre-remediation literals (INFO-4). The matching Mutation cells were amended, and the amendments are recorded.
3. D11, Spec-AC-03/07 and TEST-118 to TEST-122 were added after freeze. They are recorded as unsigned contract amendments tracked by `fu-amend-release-same-version-recovery` (P2). The owner's sign-off is owed. This is not a code defect.
4. The stub mode `merge-after-preflight` named in TEST-119's description does not exist as a mode. The arm uses a selected test file (`MERGER`) that merges during the preflight. The behaviour is equivalent and arguably more faithful, but the row text does not match the implementation.

## Findings

### NB-1: a re-cut merged by GitHub on the old head after the push wedges permanently (release-finish.mjs:641-647)
How to reproduce: run PROBE-OLDHEAD-MERGE. The engine refuses `identity … preserve the journal for recovery` on every run and publishes 0 releases. No recovery procedure is documented, and none exists short of editing the journal by hand. The engine does fail closed, and no false record is written.

The window is narrow. It is the time between the leased push and GitHub processing the synchronize event, during which a merge of the old head has to complete. The remediator disclosed this window as untested.

Fix direction: in the non-OPEN branch, when `followed.state==='MERGED'` and `followed.headRefOid` equals the last `recuts` entry's `fromHead`, pop that entry and restore the binding the same way `abandonRecut` does. That means recomputing from `fromBase`, verifying against the `fromHead` blob, and then letting cleanup delete the pushed-but-unmerged head.

A related tail of the same root: abandonRecut case C on a pushed-not-journaled head that GitHub merged on `fromHead`. Publication succeeds, but cleanup refuses `cleanup-head-moved` because the remote branch holds the unmerged new head. The release is still published, so the impact is lower.

Recommended disposition: promote to follow-up P3, `follow-ups.mjs add --id fu-release-recut-merged-old-head --ref release-same-version-recovery --severity P3`. It is a narrow external race, it fails closed, it leaves no false record, and it is disclosed. Alternatively, remediate in tree if another round happens anyway.

### INFO (non-gating)
INFO-1 to INFO-4 are in the YAML block. INFO-1 recommends fixing the code comment and the D11(c) wording so they say what the Windows branch actually achieves (state what a guard compares).

## cannot_verify
See the YAML block. Five items: live GitHub head-follow and edit behaviour (Spec-AC-09), the Windows taskkill behaviour, the preflight running repository tests with the operator's environment from a linked worktree of the production repository, the 60 s `worktree add` budget on the real repository, and mutation evidence that is local-only.

## Warning dispositions (H6)
- NB-1: recommended (b), a typed follow-up `fu-release-recut-merged-old-head` at P3, recorded by the orchestrator. Disposition (d), accepted residual, is also admissible: P3, a race that has never been observed, fail-closed, no false record. If the orchestrator chooses (d), the report line to quote is: `accepted residual: NB-1 old-head merge after a re-cut push refuses identity until manual journal repair; narrow external race, fail-closed, no false record`.
- INFO-1 to INFO-4: no disposition owed.

## Next steps
Code review passes. Validation r2 proceeds independently. The orchestrator records the NB-1 disposition and runs `set-code-review`. The owner owes sign-off on `fu-amend-release-same-version-recovery` and `fu-amend-release-one-shot-finish-d8046a`. Spec-AC-09 is verified after merge.
