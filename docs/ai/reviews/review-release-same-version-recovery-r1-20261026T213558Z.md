```yaml
review:
  scope: origin/main...HEAD (20ee3591..e8e0ded6) in /private/tmp/aai-relrec, branch change/release-same-version-recovery
  spec: docs/specs/SPEC-0255-spec-release-same-version-recovery.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "release-finish.mjs:363-399,593-605 ; TEST-101 (sh + pwsh arm), TEST-102, TEST-114 re-run green by reviewer" }
      - { ac: Spec-AC-02, call: compliant, citation: "release-finish.mjs:383 (fromHead null pre-push), 435-438 ; TEST-113 green" }
      - { ac: Spec-AC-03, call: non-compliant, citation: "MERGED clause holds only from a clean journal (TEST-105). With a pending recut (left by any interrupted or release-preflight-refused re-cut) and PR #1 MERGED, release-finish.mjs:370 returns, then :593-597 force-pushes a NEW head onto the merged PR's branch and :601 waits forever; exit 20, 0 releases (reviewer probe PROBE-MERGED). Refusal arms (lease race, closed, tag, rewritten, foreign head) compliant: TEST-103/104/116/117 green" }
      - { ac: Spec-AC-04, call: compliant, citation: "stage('recut') :399, resume via :593-605 ; TEST-111 green" }
      - { ac: Spec-AC-05, call: compliant, citation: "unchangedBase :361 new detail, :627 ; TEST-112 green" }
      - { ac: Spec-AC-06, call: compliant, citation: "releasePreflight :414-427, pushRelease :429-434 ; TEST-106, TEST-107 green" }
      - { ac: Spec-AC-07, call: compliant, citation: "preflightSeconds parse :42-44, :524, spawn timeout :405 ; TEST-108 green (but see NB-2: timeout orphans the test subprocess)" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-109, TEST-110 green; SKILL_RELEASE 4921 B measured" }
      - { ac: Spec-AC-09, call: cannot-verify, citation: "deferred post-merge live acceptance; TEST-115 SKIPs without AAI_RELEASE_LIVE_ACCEPTANCE" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/release-finish.mjs, line: 593,
          issue: "A pending re-cut is pushed even when the bound PR is already MERGED; the post-push block then waits for a merged PR's head to follow and never finishes",
          failure_scenario: "Re-cut refused release-preflight (or interrupted at recut/worktree/payload) -> journal holds recut pending, head null/unpushed. Operator merges the old PR by hand (or a re-run flaky check lets armed auto-merge fire). Next --confirm: recutIfMoved returns at :370 (MERGED), :593 sees record.recut and force-pushes a new head onto the merged PR's branch (violates D2/D9 'a merged PR is never re-cut'), :601 boundedPoll times out 'identity' on every subsequent run; release never published/verified, journal notes already replaced by the unmerged rollup. Reproduced: PROBE-MERGED, two runs rc=20 'REFUSED: identity — Bounded wait expired', release branch moved, releases=0." }
      - { rank: NON-BLOCKING, file: .aai/scripts/release-finish.mjs, line: 405,
          issue: "Preflight timeout SIGKILLs only the `node --test` runner; the per-file test subprocess is orphaned and keeps running in the deleted worktree",
          failure_scenario: "A selected test hangs (or busy-loops): spawnSync returns ETIMEDOUT after AAI_RELEASE_PREFLIGHT_SECONDS, the worktree is removed, but `node <file>` keeps running indefinitely (reviewer probe: spawnSync node --test with timeout 1000 returned in 1.0s, `node s.test.mjs` still alive afterwards). Each release attempt leaks up to two such processes (rolled + base run)." }
      - { rank: NON-BLOCKING, file: .aai/scripts/release-finish.mjs, line: 383,
          issue: "A pending re-cut whose new head was already pushed (crash between pushRelease and the :597 journal write) keeps the ORIGINAL fromHead lease when the base moves again, so the engine wedges",
          failure_scenario: "Re-cut pushes H2, process dies before stage('pushed'); base moves again; next run passes the remote===record.head guard (:390), re-cuts to H3 and pushes with lease on fromHead H1 while remote is H2 -> git 'stale info' (git-command); every later run refuses head-moved (remote H2 is neither H1 nor H3). Fail-closed but needs manual journal repair. Reproduced: PROBE-WINDOW." }
      - { rank: NON-BLOCKING, file: .aai/scripts/release-finish.mjs, line: 366,
          issue: "PR state is read once at the start of the re-cut, then the re-cut runs a re-audit, commit and up to 2x900 s preflight before the force-push; a merge in that window lands in the BLOCKING finding's stuck path",
          failure_scenario: "Operator re-runs the red check on the old head while the re-cut preflight runs; armed auto-merge merges PR #1; the leased push still succeeds (branch unchanged) and :601 then waits on a merged PR forever. Mitigation: re-read PR state immediately before pushRelease and treat MERGED in the :599 block (same fix family as the BLOCKING finding)." }
  cannot_verify:
    - { claim: "GitHub updates an open PR's headRefOid after a force-push and gh pr edit --body-file works on it", closes_with: "Spec-AC-09 live run on PR #504" }
    - { claim: "tests/skills/lib/recheck.test.mjs (and future CHANGELOG-reading node tests) never write into the shared repository's refs/config when run from a linked worktree of the production repo", closes_with: "audit of the selected tests' git invocations, or running the preflight under a throwaway clone instead of a linked worktree" }
    - { claim: "The 60 s default command() timeout is enough for `git worktree add --detach` of the real repository during preflight", closes_with: "timing of the live run (Spec-AC-09)" }
    - { claim: "Mutation evidence (16 RED records) binds to the reviewed head", closes_with: "mutation-gate.mjs --spec on the validated head (evidence is local-only, gitignored)" }
  overall: fail
```

security_relevant: false

# Code review — release-same-version-recovery (round 1)

Scope: `git diff origin/main...HEAD` in `/private/tmp/aai-relrec` (20ee3591..e8e0ded6), 13 files. Spec: `docs/specs/SPEC-0255-spec-release-same-version-recovery.md` (frozen). Reviewer: claude-opus-5-5, read-only on the worktree; suites run in a scratch clone.

Coaching check: the dispatch listed questions to examine (lease, crash resume, preflight classification, parity) but did not pre-rate findings or exclude areas. No coaching recorded. Full scope reviewed.

## Evidence run by the reviewer

All in a scratch clone of HEAD e8e0ded6, `env -u AAI_ROLE bash tests/skills/test-aai-release.sh <selector>`:
- test_731..744, 739, 740, 745: all rc=0 (TEST-101 incl. pwsh arm, pwsh present at /opt/homebrew/bin/pwsh; TEST-115 prints SKIP).
- PROBE-MERGED (reviewer-added case in a second scratch clone): firstCut, move base, re-cut stopped after `payload`, PR #1 merged by a runner clone. Two runs: `rc 20 REFUSED: identity — Bounded wait expired`, release branch moved from the first head to a new SHA, `releases 0`.
- PROBE-WINDOW: re-cut stopped after `pushed`, journal rewritten to the pre-journal-write state (recut pending, head H2 already on remote), base moved again. Run 1: `REFUSED: git-command — git push ... --force-with-lease=...:<H1> ...` (stale info). Run 2: `REFUSED: head-moved — Remote release head <H2> is neither the journaled head <H1> nor the pending re-cut head <H3>`.
- Orphan probe: `spawnSync(node,['--test',file],{timeout:1000,killSignal:'SIGKILL'})` on a 40 s test returned in 1.004 s ETIMEDOUT; `pgrep` still showed `node s.test.mjs` afterwards.
- Mutation records: 16 files under docs/ai/tdd/spec-release-same-version-recovery/, all `verdict: RED` (read, not re-run).

## AC table walk

See the YAML block. Spec-AC-03 is non-compliant for one reachable precondition: the AC states "WHEN a re-cut is due ... WHEN PR #1 is MERGED and the base has moved, the run SHALL exit 0, publish one release and push nothing new to the release branch". TEST-105 checks this only from a journal with no pending `recut`. With a pending re-cut, which the spec deliberately leaves after a `release-preflight` refusal (D6: "the journal keeps the unpushed head"), the run exits 20, publishes nothing and pushes a new head.

## Deviations from the frozen spec (all listed, including reasonable ones)

1. Implementation plan step 2 says to replace the `unchangedBase()` call sites at the old lines 466 and 520 with `recutIfMoved()`. The old pre-checks call site (now :619) still calls `unchangedBase()`. The effect: a base move between the start of the run and the checks wait refuses `base-moved` with the same-version text instead of re-cutting. This is consistent with D5 "one re-cut per invocation" and the implementer disclosed it. Acceptable, but it is a deviation.
2. Stub mode `closed` was not added. TEST-103's closed arm edits the stub state directly, as TEST-083 does. Disclosed; equivalent.
3. TEST-105 passes on the old engine. Disclosed; the row rests on its mutation (RED recorded).
4. D10: the amendment is recorded against SPEC-0236 in decisions.jsonl without owner sign-off; `fu-amend-release-one-shot-finish-d8046a` is filed (P2). This is not a code defect, but the owner owes the sign-off.
5. The spec's "Edge cases decided here" keeps the original `fromHead` lease for a pending re-cut on a re-moved base. The spec did not consider the case where the pending head was already pushed. That case is NB-2 (PROBE-WINDOW).

## Findings

### BLOCKING-1: a pending re-cut force-pushes onto a MERGED PR and wedges (release-finish.mjs:593-605, with :370)
`recutIfMoved()` returns early on `pr.state==='MERGED'`. `main()` then runs `if(record.recut){ if(remoteHead!==record.head) pushRelease(); ... stage('pushed') }` without checking the PR state. That pushes a newly prepared head onto the merged PR's branch, which contradicts D2 and D9. The block at :599 then polls `headRefOid===record.head`. GitHub does not move a merged PR's head, so every run ends in `REFUSED: identity — Bounded wait expired`. By then the journal's `notes`/`content`/`baseHead` describe the unmerged re-cut, so even past the poll, `notes-mismatch` would refuse publication verification.

How it is reached: (a) a re-cut refused `release-preflight` (designed path), or an interrupt at recut/worktree/payload; (b) the old PR gets merged by hand or by auto-merge; (c) re-run.

Fix direction:
- When the PR is MERGED, discard a pending `recut` and restore the pre-recut binding: keep `fromBase` and recompute the notes from `fromBase:CHANGELOG.md`, or store the old `notes`/`content` in `recut`.
- Never call `pushRelease()` or the :599 block for a PR that is not OPEN. Re-read `pr view` immediately before the push.
- Add a test: pending recut + MERGED PR → exit 0, one release, no push.

Disposition: remediate in tree.

### NB-1: preflight timeout orphans the test subprocess (release-finish.mjs:405)
`node --test <file>` runs the file in a child process. `spawnSync`'s timeout SIGKILLs only the runner. A hanging test survives indefinitely, once per run on the rolled tree and once on the base. TEST-108 does not see this because its sleep is bounded at 20 s.

Fix: spawn the runner detached and kill the process group, or pass `--test-timeout` together with the runner's own isolation flag.

Recommended disposition: remediate in tree, since the code is being touched for BLOCKING-1 anyway. Otherwise promote as P2: `follow-ups.mjs add --id fu-release-preflight-orphan-test-proc`.

### NB-2: an already-pushed pending re-cut on a re-moved base wedges (release-finish.mjs:383-390, 431)
Reproduced (PROBE-WINDOW). The crash window is narrow: it lies between the push and one atomic write. The result is fail-closed but needs manual journal repair.

Fix: when `remote===record.head` and `newBase!==record.baseHead`, first fold the pushed head into `recuts` (or move the lease basis to `remote`), then re-cut.

Recommended disposition: remediate in tree together with BLOCKING-1. Otherwise promote as P3: `fu-release-recut-pushed-pending-lease`.

### NB-3: PR state is read once, minutes before the force-push (release-finish.mjs:366-371 vs 429-434)
The preflight can take up to 2 × `AAI_RELEASE_PREFLIGHT_SECONDS`. A merge inside that window leads into the BLOCKING-1 wedge. A re-read right before `pushRelease()` and a MERGED branch in the :599 block close most of it. The lease does not protect against this, because a merge does not move the head branch.

Recommended disposition: remediate together with BLOCKING-1 (same fix family).

INFO: `merge-base --is-ancestor` failing for a reason other than ancestry (for example a missing object) is reported as `base-rewritten`. Fail-closed; the cause name is only slightly off. No action needed.

## cannot_verify

See the YAML. The live GitHub PR-head follow and `gh pr edit` behaviour are covered only by Spec-AC-09 (deferred). Running the repository's node tests from a linked worktree of the shared production repo assumes those tests do not write the shared refs or config. The mutation evidence is local-only.

## Warning dispositions (H6)
- BLOCKING-1: remediate in tree (required).
- NB-1, NB-2, NB-3: recommended remediate-in-tree in the same remediation round. If the orchestrator defers any of them: NB-1 → P2 follow-up, NB-2 → P3 follow-up, NB-3 → folded into the BLOCKING-1 fix. A read-only reviewer files nothing.

## Next steps
Remediation round (TDD): add a RED case for pending recut + MERGED PR (and optionally PROBE-WINDOW), fix, re-run test_731..744 plus TEST-016/083 and the whole release suite, then re-review.
