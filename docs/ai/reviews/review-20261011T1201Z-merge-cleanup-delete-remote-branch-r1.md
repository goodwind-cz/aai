# Code Review r1 — merge-cleanup-delete-remote-branch

```yaml
review:
  scope: "git diff 029e9884..a2a4e174 (branch change/merge-cleanup-delete-remote-branch, worktree)"
  spec: docs/specs/SPEC-0222-spec-merge-cleanup-delete-remote-branch.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/merge-cleanup.mjs deleteRemoteBranch (lease push, [deleted] -> done) + PLANNERS['delete-remote-branch']; TEST-036, TEST-002, TEST-016 Pester" }
      - { ac: Spec-AC-02, call: compliant, citation: "remoteProof remote_moved + lease CAS + stale-info re-read; TEST-037 pre-moved and race arms; mutation row drops the lease" }
      - { ac: Spec-AC-03, call: compliant, citation: "remoteProof { absent: true } + stale-info re-read absent -> noop remote_absent; reportStep counts done only; TEST-038 three arms" }
      - { ac: Spec-AC-04, call: compliant, citation: "isCrossRepository === true -> remote_fork, !== false -> remote_unknown; TEST-039" }
      - { ac: Spec-AC-05, call: compliant, citation: "[ctx.base, defaultBranch].includes(b) -> remote_is_base; check-ref-format -> remote_bad_name; TEST-040" }
      - { ac: Spec-AC-06, call: compliant, citation: "retain('remote_delete_rejected', summary + hook text); ls-remote failure -> remote_unknown; never stop(); TEST-041" }
      - { ac: Spec-AC-07, call: compliant, citation: ".aai/SKILL_MERGE.prompt.md step 2/3/hard rules, PS block $env:AAI_GIT_WRITE = $null, ledger 279 B; TEST-042, prompt-diet TEST-012, pr-preflight want_growth" }
      - { ac: Spec-AC-08, call: compliant, citation: "ghDependents --base + remote_has_dependents / fail-closed remote_unknown; TEST-043 (post-freeze amendment, unsigned-tracked)" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 156,
          issue: "The dependents proof asks only for open PRs whose BASE is the branch (gh pr list --base). An open PR whose HEAD is the same branch is not looked for, so the step deletes a ref another open PR depends on.",
          failure_scenario: "Branch feat is the head of PR #10 (into main) and PR #11 (into release/1.x, same commits). #10 is merged; /aai-merge 10 runs apply. All proofs pass: isCrossRepository false, origin/feat at #10's headRefOid, gh pr list --state open --base feat returns []. The lease push deletes refs/heads/feat and GitHub closes the still-open PR #11. The intake names this a non-goal (Scope, Out: deleting remote branches of other PRs)." }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 1339,
          issue: "For a fork PR the step stops at proof 2 before any ls-remote read, yet the remaining line says origin/<b> retained (remote_fork ...): owner decision, not deleted. Origin usually has no such branch, so the line asks the owner to decide about a branch that does not exist.",
          failure_scenario: "A contributor PR from someone:fix-typo is merged; origin has no fix-typo branch. The report and the remaining channel to the owner say origin/fix-typo was retained and is an owner decision. The owner then checks for a branch that is not there. This happens on every fork PR. The spec mandates it (Spec-AC-04 requires the remaining line), so the fix needs a spec amendment." }
  cannot_verify:
    - { claim: "GitHub rejects a protected-branch, ruleset or no-contents:write deletion with a ! porcelain line or a non-zero exit, so the deletion is retained (spec R1)",
        closes_with: "a live push against a protected branch on a scratch GitHub repo; only the pre-receive stand-in (F4) is exercised" }
    - { claim: "GitHub closes an open PR whose head branch is deleted, and retargets PRs stacked on it (the impact side of the BLOCKING finding and of Spec-AC-08)",
        closes_with: "a scratch GitHub repo with two PRs from one head branch, plus a stacked PR, then the lease push" }
    - { claim: "Windows native: the step's ls-remote/push output parsing (LF split, porcelain columns) behaves as on POSIX",
        closes_with: "the CI ps1-quality Pester run (TEST-016) on windows-latest; it covers only the happy path (spec R5). A CR in the output can only turn a match into absent or remote_unknown, never into a deletion: the lease still guards the push" }
    - { claim: "the origin remote is the PR's repository when remote.origin.url is a local path or an unparsable alias (checkRepo skips the comparison)",
        closes_with: "nothing in-tree. The lease limits the impact to a ref sitting exactly at the merged head oid, and readAndGate proved the merge commit on origin/<base>" }
    - { claim: "the post-freeze Spec-AC-08 amendment record is committed with the PR (validation r3 noted it lives only in the uncommitted docs/ai/decisions.jsonl)",
        closes_with: "git show <PR head>:docs/ai/decisions.jsonl contains the 2026-10-11T11:40:03Z record" }
  overall: fail
```

## Scope and preflight

- Scope: `git diff 029e9884..a2a4e174` in worktree
  /Users/ales/Projects/aai-change-merge-cleanup-delete-remote-branch
  (STATE `worktree.user_decision: worktree`, base main). The uncommitted files
  in the worktree (EVENTS, decisions, roadmap, test-runs ledgers) are outside
  the reviewed range.
- Spec: docs/specs/SPEC-0222-spec-merge-cleanup-delete-remote-branch.md
  (frozen, with the Spec-AC-08 post-freeze amendment). Intake:
  docs/issues/CHANGE-0209-merge-cleanup-delete-remote-branch.md.
- Dispatch note: the dispatch prompt listed focus areas. They were not
  severity pre-ratings or scope exclusions. The full scope was reviewed.
- Independent run: TEST-036 to TEST-043 each PASS through
  `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-merge-cleanup.sh TEST-0xx`.
  Validation r3 records the whole suite (42 PASS), the Pester TEST-016 run, an
  8/8 mutation replay and GATE PASS.

## AC table walk

Every Spec-AC is compliant. Citations are in the YAML block. Spot checks
against the frozen design:

- D2 order is name, fork, ls-remote, base/default, absent/moved, dependents,
  as written. The proofs fail closed: a missing default branch, a missing
  isCrossRepository field and an unreadable dependents list are all
  `remote_unknown`.
- D3: the lease is always `refs/heads/<b>:<40-hex head>`, because a head that
  is not 40 hex is `remote_moved` before the push. The refspec starts with
  `:`, so it cannot be read as an option. `<b>` passed BASE_NAME_RE, the
  no-leading-dash check and check-ref-format. There is no `--force`, no
  `--no-verify` and no `--delete` without the lease.
- D4/D5: the push has a spawn error/timeout branch (`remote_unknown`), and
  stale info triggers a re-read. Every other outcome is
  `remote_delete_rejected`, and no path calls `stop()` or `refuse()`. A
  signal-killed push (status null, no error) falls to
  `git push exited null` and is retained. The step never throws.
- D6/D7: the remaining line comes from the step result, and only `done`
  results produce a saved report. Plan reads the same proof and pushes
  nothing (TEST-036 world digest).
- Deviations from the frozen spec: none found beyond the recorded Spec-AC-08
  amendment.

## Findings

### BLOCKING-1: an open PR whose head is the same branch is not a "dependent"

- File: .aai/scripts/merge-cleanup.mjs:156 (`ghDependents` listArgs) and
  :924-933 (`remoteProof` proof 6).
- What is wrong: proof 6 runs only
  `gh pr list --state open --base <b>`. It never asks whether another open PR
  uses `<b>` as its head.
- Repro (code path; the deny-by-default gh stubs never see a `--head`
  query): in the TEST-036 world, imagine a second open PR #11 with head
  `ride/foo` into another base. `remoteProof` returns `{ oid }` because
  `--base ride/foo` lists nothing. `git push --force-with-lease=... origin :refs/heads/ride/foo`
  then deletes the ref, and on GitHub that closes #11. The lease cannot help
  here: the ref sits exactly at the merged head.
- Why BLOCKING: this is an outward-facing effect on someone else's open work.
  It is the exact case the intake excludes (Scope, Out: "Deleting remote
  branches of other PRs"). The step otherwise fails closed in every
  uncertain case, so this gap goes against its own safety claim.
- Recommended fix (remediate-in-tree): widen proof 6 to also list open PRs
  with `--head <b>`, or make one query that covers both, and retain with
  `remote_has_dependents` naming those numbers. A `--head` match on a fork
  PR with the same branch name only adds a false retention, which is the safe
  side. Then:
  - add a TEST-043 arm (or a new TEST row) where the stub lists an open PR
    for `--head ride/foo`;
  - add a mutation row that drops the head query;
  - add the matching argv to the bash and Pester gh stubs (D8 seam);
  - record a post-freeze amendment of Spec-AC-08 / D2 step 6 under the same
    additive-with-disclosure convention as the existing one.

### NON-BLOCKING-1: the fork retention names a branch origin does not have

- File: .aai/scripts/merge-cleanup.mjs:1339-1343 (`remoteBranchNote`), fed
  by :904 (proof 2).
- Scenario: a merged fork PR whose head branch does not exist on origin. The
  report says `origin/<b> retained (remote_fork: ...): owner decision, not deleted`
  on every fork PR, about a ref that is not there.
- The spec requires this (Spec-AC-04, TEST-039), so it is compliant. It still
  leaves a misleading line on the owner channel.
- Recommended disposition: promote to a follow-up
  (`fu-merge-fork-remaining-line`, P3). Report a fork as `noop remote_fork`,
  or keep the line only when origin actually has `<b>`. This needs a spec
  amendment, so it does not belong in this ride.

### INFO (no gate)

- `ghDependents` relies on gh's implicit repository resolution instead of
  `--repo <slug of pr.url>`. `gh pr view` uses the same resolution and
  checkRepo pins it, so no failure was found. Passing `--repo` would make
  the dependents read independent of the gh default repo.
- One apply against an unresponsive remote can spend up to 3 x 120 s
  (ls-remote, dependents, push; the stale re-read can add more). Plan mode
  now also makes the ls-remote and gh reads.
- Test quality is good. Every remote assertion reads the bare origin itself.
  The race arms use a shim that acts between the proof and the push, which
  is what makes the CAS mutation (TEST-037 row) meaningful. The TEST-039
  mutation is caught by the reason string, not by a deletion, because
  proof 2's `!== false` still retains. That is defence in depth, not a gap.
- Canon text: "Run the block as the command itself, never through `bash -c`,
  `sh -c` or `eval`" is clear. Neither block contains rm, Remove-Item or
  --force. The PowerShell block clears `AAI_GIT_WRITE` before the throw, so
  a failing apply does not leak the variable.

## Warning dispositions (H6)

- BLOCKING-1: remediate in tree (blocks merge).
- NON-BLOCKING-1: promote to a typed follow-up (`fu-merge-fork-remaining-line`,
  P3). The orchestrator files it. A read-only reviewer does not.

## Next steps

1. Remediation: add the head-dependents query, test arm, mutation row, stub
   argv in both suites, and the spec amendment (BLOCKING-1).
2. Orchestrator files the NON-BLOCKING-1 follow-up.
3. Re-review (r2) of the remediation delta, then Validation of the delta.
4. Commit the Spec-AC-08 amendment record in docs/ai/decisions.jsonl with the
   PR (cannot_verify item 5).
