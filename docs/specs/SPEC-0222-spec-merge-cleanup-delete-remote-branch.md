---
id: spec-merge-cleanup-delete-remote-branch
type: spec
number: 222
status: implementing
mutation_gate: v1
frozen_sha256: 8bc81ccf7a49660909be2817ebb37c52c2812f6c2c4ceb5764e37a87df423af9
ceremony_level: 2
links:
  requirement: merge-cleanup-delete-remote-branch
  rfc: null
  pr: []
  commits: []
---

# Spec — /aai-merge deletes the merged remote branch by lease, and its block passes the agent's safety check

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/CHANGE-0209-merge-cleanup-delete-remote-branch.md
  (owner direction 2026-10-11: "Podle mě by měl dělat i to mazání větve a
  neměl by mit problém s bezpečnostn kontrolou")
- Engine: .aai/scripts/merge-cleanup.mjs (`STEP_IDS`, `PR_FIELDS`,
  `readAndGate`, `deleteBranch`, `HANDLERS`, `PLANNERS`, `remoteBranchNote`,
  `buildReport`, `emit`, `reportStep`)
- Canon: .aai/SKILL_MERGE.prompt.md (step 2 blocks, step 3, hard rules)
- Product doc: docs/product/directed-merge-and-post-merge-cleanup.md (written
  by the ship step after the loop completes)
- Prior art: docs/specs/SPEC-0218-spec-directed-merge-and-post-merge-cleanup.md
  (D10 "remote branches are never deleted here"; its Spec-AC-06 clause "the
  remote branch intact" and the matching TEST-010 assertions are superseded
  by this owner direction, D9 below), docs/specs/SPEC-0221-spec-merge-cleanup-submodule-worktree.md
  (step order, resume, fixture helpers)
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, git CLI)

## Registry items closed by this scope

None. `node .aai/scripts/follow-ups.mjs list` at 029e9884 (171 open) holds
no item about remote branch deletion or about the `bash -c` wrapper.

## Registry items assessed, not closed

- `fu-merge-foreign-journal-archive-path`, `fu-merge-pending-diverged-regression`
  (same engine, base-sync subject; this scope does not touch `syncBase`).
- `fu-merge-preflight-checks-not-started` (preflight gates; not touched).
- `fu-constitution-art7-directed-merge` (Constitution wording about merges;
  deleting a merged head ref is not a merge).

## Implementation strategy

- Strategy: tdd
- Rationale: autopilot default (intake: "Planning decides"). The scope adds
  the first outward-facing, irreversible effect to the engine: a deleted
  remote ref that held unmerged commits cannot be recovered from this
  checkout. The safety lives in a compare-and-swap that looks exactly like a
  plain delete until a test is seen failing without it (the race arm of
  TEST-037). Every Spec-AC gets a stored RED and a mutation that reddens it.
  STATE holds an intake-sourced strategy for `slowest-suite-hot-spots`; its
  ref_id differs, so it is stale and is replaced.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound change to a destructive engine step, the
  canon prompt and three suites; no `protected_paths_l3` surface. The main
  checkout is shared with another session.
- User decision: worktree (autopilot default, already recorded in STATE)
- Base ref: main 029e9884
- Worktree branch/path: change/merge-cleanup-delete-remote-branch at
  /Users/ales/Projects/aai-change-merge-cleanup-delete-remote-branch
- Inline review scope: .aai/scripts/merge-cleanup.mjs,
  .aai/SKILL_MERGE.prompt.md, tests/skills/test-aai-merge-cleanup.sh,
  tests/skills/aai-merge-cleanup.Tests.ps1,
  tests/skills/lib/prompt-diet-ledger.sh, tests/skills/test-aai-prompt-diet.sh,
  tests/skills/test-aai-pr-preflight.sh,
  docs/product/directed-merge-and-post-merge-cleanup.md, CHANGELOG.md, the
  intake and this spec
- Code review required: true (engine, canon and test change).

## Phasing

One ride, 7 Spec-ACs, 7 TEST rows. Expected three TDD dispatches:
(A) TEST-036, TEST-037, TEST-038 (delete, lease, absent and idempotence,
plus the TEST-010 and TEST-002 supersession edits and the stub field list);
(B) TEST-039, TEST-040, TEST-041 (fork, base/default/name, rejection and
unreadable remote); (C) TEST-042 (canon, Pester twin, corpus pins), then V1
to V4.

## Measured facts (scratch repo, git 2.54.0, 2026-10-11)

Measured in a scratch bare origin plus a clone, `GIT_CONFIG_GLOBAL=/dev/null`.

- F1 `git push --porcelain --force-with-lease=refs/heads/ride:<oid> origin :refs/heads/ride`
  with the remote at `<oid>`: exit 0, porcelain line
  `-<TAB>:refs/heads/ride<TAB>[deleted]`; the remote ref is gone and the
  clone's `refs/remotes/origin/ride` (if any) is removed with it.
- F2 Same command with the remote advanced past `<oid>`: exit 1, line
  `!<TAB>(delete):refs/heads/ride<TAB>[rejected] (stale info)`; the remote
  ref is unchanged.
- F3 Same command with the remote ref already absent: exit 1, the same
  `[rejected] (stale info)` line as F2. Absence and movement are therefore
  told apart only by re-reading the remote after a stale rejection.
- F4 A pre-receive hook that exits 1 on the bare: exit 1, line
  `!<TAB>:refs/heads/ride<TAB>[remote rejected] (pre-receive hook declined)`;
  the remote ref is unchanged (the shape of a GitHub protected-branch refusal).
- F5 `git ls-remote --symref origin HEAD refs/heads/ride` prints
  `ref: refs/heads/main<TAB>HEAD`, the HEAD oid, and the ride oid in ONE read:
  the default branch and the remote head come from the same call.
- F6 The AAI:CLOSE-GATE pre-push hook skips a deletion (all-zero local sha);
  the AAI:REF-GUARD reference-transaction hook guards only `refs/heads/main`,
  so the push needs no new guard permission (the block already sets
  `AAI_GIT_WRITE=1`).

## Design decisions

- D1 Step. A new apply step `delete-remote-branch` runs after `delete-branch`
  and before `report`; `STEP_IDS` gains it in that position, so
  `AAI_MERGE_CLEANUP_STOP_AFTER=delete-remote-branch` is valid. Because every
  earlier step either completed or refused/stopped first, the remote is only
  ever touched after the worktree and local branch proofs passed.
- D2 Proofs, in this order; the first that fails retains the branch with
  that reason (step status `retained`, detail `<reason> <fact>`):
  1. name: `headRefName` matches `BASE_NAME_RE`, does not start with `-`, and
     `git check-ref-format refs/heads/<b>` exits 0, else `remote_bad_name`;
  2. PR head repository: `isCrossRepository === true` gives `remote_fork`;
     any value other than `false` (field absent, null) gives `remote_unknown`;
  3. one `git ls-remote --symref origin HEAD refs/heads/<b>` read (F5); a
     non-zero exit or a spawn error gives `remote_unknown` with the first
     stderr line (the reason TEST-010's `remote_unknown` arm already pins);
  4. base or default: `<b>` equals the PR `baseRefName` or the default branch
     named by the symref line (falling back to the local
     `refs/remotes/origin/HEAD`) gives `remote_is_base`; no default branch
     from either source gives `remote_unknown` (fail closed);
  5. remote head: no `refs/heads/<b>` line gives status `noop`, detail
     `remote_absent`; an oid other than the PR `headRefOid` (or a
     `headRefOid` that is not 40 hex) gives `remote_moved` naming both oids;
  6. dependents (Spec-AC-08, amended twice): two reads, each `gh pr list
     --state open --base <b> --json number --limit 100` and `gh pr list
     --state open --head <b> --json number --limit 100`, each with a 120 s
     timeout (the base read finds PRs stacked on the branch, the head read
     finds PRs opened from it, which deleting the branch would also close);
     any open PR from either read gives `remote_has_dependents` naming the PR
     numbers and whether each is based on the branch or opened from it; either
     read failing, timing out or unparsable gives `remote_unknown` (fail
     closed). The stale-info re-read repeats both reads.
  MERGED and the merge commit on the base are already proven by
  `readAndGate` (refusal before any write); the step does not re-read the PR
  itself, its only gh reads are the two dependents lists of step 6.
- D3 Deletion by compare-and-swap only:
  `const lease = \`--force-with-lease=refs/heads/${b}:${ctx.head}\`;` then
  `git push --porcelain <lease> origin :refs/heads/<b>` with
  `GIT_TERMINAL_PROMPT=0` and a 120 s spawn timeout. Never `--force`, never
  `--no-verify`, never `git push --delete` without the lease, never
  `gh pr merge --delete-branch`.
- D4 Push outcome, read from the porcelain line for `refs/heads/<b>` (F1 to
  F4): `[deleted]` gives `done` (detail `<b>`); `[rejected] (stale info)`
  triggers one re-read (D2 steps 3 to 6): absent gives `noop remote_absent`,
  open dependents give `retained remote_has_dependents`, otherwise
  `retained remote_moved`; any other `!` line or a non-zero exit
  without a porcelain line gives `retained remote_delete_rejected` with the
  first rejection or stderr line; a spawn error or timeout gives
  `retained remote_unknown`.
- D5 Never stops. Every proof failure and push failure is `retained` or
  `noop`; the step never calls `stop()` or `refuse()`, so the report step
  still runs and apply exits 0 when the rest completed.
- D6 Report. `remoteBranchNote` is replaced: a `retained` step yields one
  `remaining:` line `origin/<b> retained (<reason>: <fact>): owner decision,
  not deleted`; `done` and `noop` yield none. The `retained` array of the
  report stays drafts-only (TEST-006 and TEST-007 pin it). The text report
  and the saved Markdown report print the step as
  `delete-remote-branch: <status> (<detail>)`. A rerun whose only non-noop
  step is a still-retained remote saves no new report (`reportStep` counts
  only `done`).
- D7 Plan. `PLANNERS['delete-remote-branch']` evaluates D2 read-only (the
  same ls-remote read, no push) and lists `origin/<b> <head12>` when the
  proofs pass, `retain origin/<b> (<reason>)` when one fails, and nothing
  when the remote branch is absent. Plan writes nothing (world digest
  unchanged, TEST-036).
- D8 One gh read. `PR_FIELDS` gains `isCrossRepository`; it stays the single
  fixed `gh pr view` read (SPEC-0218 D4). The deny-by-default gh stubs in
  tests/skills/test-aai-merge-cleanup.sh and
  tests/skills/aai-merge-cleanup.Tests.ps1 accept the new exact field list,
  and their PR fixtures carry `"isCrossRepository":false`.
- D9 Supersession of SPEC-0218 D10. TEST-010's assertions "the remote branch
  was deleted" (now expected deleted) and `remaining` naming `origin/$BRANCH`
  (now expected absent) flip; its unrelated remote branch `misc-remote`
  assertion stays. The `remote_unknown` arm keeps its two `want` lines (the
  reason and `origin/$BRANCH` are in the retained `remaining:` line).
  TEST-002 (the executed bash and zsh block) gains one assertion that the
  bare has no `refs/heads/$BRANCH` afterwards.
- D10 Canon (SKILL_MERGE.prompt.md):
  - step 2: "never forces" becomes a statement that the merged remote branch
    is deleted only by lease against the merged head and retained otherwise;
    a sentence: run the block as the command itself, never through
    `bash -c`, `sh -c` or `eval` (a wrapped script cannot be checked and is
    refused);
  - step 3: remote branch deletion is no longer an owner action; a retained
    remote branch is relayed with its reason and never deleted by the agent;
  - the PowerShell block clears the variable with `$env:AAI_GIT_WRITE = $null`
    instead of `Remove-Item Env:AAI_GIT_WRITE`, so neither block contains
    `rm`, `Remove-Item` or `--force`;
  - hard rules gain `push --delete` next to `branch -D`.
  Prompt growth is credited in tests/skills/lib/prompt-diet-ledger.sh (key
  `merge-cleanup-delete-remote-branch`, at most 600 B, measured with
  /usr/bin/wc -c), the TEST-012 pin in tests/skills/test-aai-prompt-diet.sh
  moves by exactly that credit, and the `want_growth` sum in
  tests/skills/test-aai-pr-preflight.sh adds the same term.

## Implementation anchors (the mutation rows depend on these spellings)

- `function deleteRemoteBranch(ctx) {` is the handler; `HANDLERS` maps
  `'delete-remote-branch': deleteRemoteBranch`.
- `const lease = ` begins the lease flag line (D3), and the push argv uses
  the variable `lease`.
- the absent test reads `if (remoteOid === '') return` (D2 step 5).
- the fork test reads `ctx.pr.isCrossRepository === true`.
- the base/default test reads `[ctx.base, defaultBranch].includes(b)`.
- the rejection branch reads `return retain('remote_delete_rejected'` where
  `retain(reason, fact)` builds the `retained` result.
- SKILL_MERGE.prompt.md carries the phrase `as the command itself, never
  through`.

## Seams

- S1 Engine to bare remote: TEST-036 to TEST-041 assert on the bare origin
  itself (`git -C "$BARE" rev-parse -q --verify refs/heads/$BRANCH`), never on
  the engine's own report alone.
- S2 Engine to gh: the one field list is shared by the engine and both stubs
  (D8); a mismatch makes every arm `gh_read_failed`, which TEST-036 would
  show as exit 3.
- S3 Prompt block to engine: the executed bash and zsh block (TEST-002, D9)
  and the Pester twin (TEST-016, local pwsh and CI ps1-quality) run the real
  block end to end, including the `AAI_GIT_WRITE` handling.
- S4 Report to owner: the `remaining:` line and the saved report are the only
  channel to the owner for a retained branch; TEST-037, TEST-039, TEST-040
  and TEST-041 assert the line through `--json` `remaining` and the saved
  report file.
- S5 Prompt corpus: the diet ledger, the TEST-012 pin and the pr-preflight
  `want_growth` sum must agree; TEST-042 checks the ledger entry, V2 runs the
  two pin suites.

## Acceptance Criteria Mapping

- Intake AC-001 (delete at merged head) -> Spec-AC-01.
- Intake AC-002 (moved remote retained, CAS mutation) -> Spec-AC-02.
- Intake AC-003 (absent noop, idempotent rerun) -> Spec-AC-03.
- Intake AC-004 (fork, head equal to base, rejected push) -> Spec-AC-04,
  Spec-AC-05, Spec-AC-06.
- Intake AC-005 (SKILL_MERGE step 3, no wrapper, no rm or Remove-Item or
  --force in either block, corpus pins) -> Spec-AC-07.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN apply runs for a merged PR whose head repository is the origin repository and the origin branch is at the PR headRefOid, the system SHALL delete refs/heads/BRANCH on the bare origin (git rev-parse on the bare fails), report the step delete-remote-branch as done with the branch name in the JSON steps, the text output and the saved report, print no remaining line naming origin/BRANCH, and exit 0; plan SHALL list the target origin/BRANCH with the first 12 hex of the head and change nothing (world digest equal). | done | docs/ai/tdd/spec-merge-cleanup-delete-remote-branch/green-TEST-036.log; docs/ai/tdd/spec-merge-cleanup-delete-remote-branch/mutation-TEST-036.txt | tdd | D1, D3, D4, D7; seams S1, S2 |
| Spec-AC-02 | WHEN the origin branch is not at the PR headRefOid, either before apply starts or advanced between the ls-remote proof and the push (git shim race arm), the system SHALL leave the origin branch at the new commit, report delete-remote-branch as retained with reason remote_moved, carry a remaining line naming origin/BRANCH and remote_moved, and exit 0 with remove-worktree and delete-branch done. | done | docs/ai/tdd/spec-merge-cleanup-delete-remote-branch/green-TEST-037.log; docs/ai/tdd/spec-merge-cleanup-delete-remote-branch/mutation-TEST-037.txt | tdd | D2, D3, D4; seam S4 |
| Spec-AC-03 | WHEN the origin branch is already absent, including absent only after a stale-info push rejection, the step SHALL be noop with detail remote_absent and no remaining line; a second apply after a successful first run SHALL exit 0 with every action step noop, SHALL save no new report file, and SHALL leave the world digest unchanged. | done | docs/ai/tdd/spec-merge-cleanup-delete-remote-branch/green-TEST-038.log; docs/ai/tdd/spec-merge-cleanup-delete-remote-branch/mutation-TEST-038.txt | tdd | D2, D4, D6 |
| Spec-AC-04 | WHEN the PR fixture says isCrossRepository true the step SHALL be retained with reason remote_fork, and WHEN the field is absent it SHALL be retained with reason remote_unknown; in both arms the origin branch SHALL still exist, a remaining line SHALL name origin/BRANCH and the reason, and apply SHALL exit 0 with the other action steps done. | done | docs/ai/tdd/spec-merge-cleanup-delete-remote-branch/green-TEST-039.log; docs/ai/tdd/spec-merge-cleanup-delete-remote-branch/mutation-TEST-039.txt | tdd | D2, D5, D8 |
| Spec-AC-05 | WHEN the PR head branch name equals the base branch or the default branch of the remote (bare HEAD symref pointed at it), the step SHALL be retained with reason remote_is_base, and WHEN the head branch name fails git check-ref-format it SHALL be retained with reason remote_bad_name; the named remote branch SHALL still exist and apply SHALL exit 0. | done | docs/ai/tdd/spec-merge-cleanup-delete-remote-branch/green-TEST-040.log; docs/ai/tdd/spec-merge-cleanup-delete-remote-branch/mutation-TEST-040.txt | tdd | D2, D5 |
| Spec-AC-06 | WHEN the origin rejects the deletion (pre-receive hook exits 1) the step SHALL be retained with reason remote_delete_rejected and the hook's rejection text in the detail, and WHEN git ls-remote fails it SHALL be retained with reason remote_unknown; in both arms the origin branch SHALL still exist, apply SHALL exit 0, and the report step SHALL be done with a saved report naming the retained branch under Remaining. | done | docs/ai/tdd/spec-merge-cleanup-delete-remote-branch/green-TEST-041.log; docs/ai/tdd/spec-merge-cleanup-delete-remote-branch/mutation-TEST-041.txt | tdd | D4, D5, D6; seam S4 |
| Spec-AC-07 | SKILL_MERGE.prompt.md SHALL say to run the block as the command itself, never through bash -c, sh -c or eval; step 3 SHALL no longer name remote branch deletion as an owner action and SHALL say a retained remote branch is relayed with its reason and never deleted by the agent; neither the bash nor the PowerShell block SHALL contain rm as a command word, Remove-Item or --force; the PowerShell block SHALL clear the variable with $env:AAI_GIT_WRITE = $null; the prompt-diet ledger SHALL carry an entry keyed merge-cleanup-delete-remote-branch crediting a positive integer of at most 600 bytes. | done | docs/ai/tdd/spec-merge-cleanup-delete-remote-branch/green-TEST-042.log; docs/ai/tdd/spec-merge-cleanup-delete-remote-branch/mutation-TEST-042.txt | tdd | D9, D10; seams S3, S5 |
| Spec-AC-08 | WHEN an open pull request has the head branch as its base (a stacked PR) or as its head (a PR opened from the branch into another base) the step SHALL be retained with reason remote_has_dependents naming the PR numbers, the plan SHALL show the same retention, and the origin branch SHALL still exist with apply exiting 0; WHEN either open-PR query fails the step SHALL be retained with reason remote_unknown and the origin branch SHALL still exist. | done | docs/ai/tdd/spec-merge-cleanup-delete-remote-branch/green-TEST-043.log; docs/ai/tdd/spec-merge-cleanup-delete-remote-branch/mutation-TEST-043.txt | tdd | D2, D5; post-freeze amendment |

## Implementation plan

- .aai/scripts/merge-cleanup.mjs:
  - `STEP_IDS` gains `delete-remote-branch` after `delete-branch`;
    `PR_FIELDS` gains `isCrossRepository`; header comment and HELP name the
    step (D1, D8).
  - `remoteProof(ctx)` (pure read: name check, fork check, one ls-remote
    symref read, base/default check, remote oid) shared by the handler and
    the planner (D2, D7).
  - `deleteRemoteBranch(ctx)` (D3, D4, D5) with a local `retain(reason, fact)`
    helper; `ctx.remote` records the result for the report.
  - `PLANNERS['delete-remote-branch']` (D7).
  - `remoteBranchNote` replaced by a reader of the step result (D6); the
    `remote_unknown` wording stays recognisable for TEST-010.
- tests/skills/test-aai-merge-cleanup.sh: stub field list and
  `write_pr_json` (with an optional `PR_CROSS` override that can drop the
  field), the TEST-010 and TEST-002 edits (D9), functions
  `test_036_*` to `test_042_*`, selector cases and default run order; a git
  shim helper for the race arm (advances the bare's ref, then execs the real
  git push) and reuse of the existing `ls-remote` failure shim. New code is
  verified under the suite's own `set -euo pipefail` (no bare `rc=$?`, no
  `grep | head`), and every bare HEAD change uses `symbolic-ref`.
- tests/skills/aai-merge-cleanup.Tests.ps1: the stub's field list, the PR
  fixture's `isCrossRepository`, and in the cleanup It block two assertions:
  the bare has no `refs/heads/<branch>` and `$env:AAI_GIT_WRITE` is null after
  the block (the Pester `Passed: 2` count is unchanged).
- .aai/SKILL_MERGE.prompt.md (D10), tests/skills/lib/prompt-diet-ledger.sh
  entry, tests/skills/test-aai-prompt-diet.sh TEST-012 pin and comment,
  tests/skills/test-aai-pr-preflight.sh `want_growth` term.
- docs/product/directed-merge-and-post-merge-cleanup.md (the new step,
  reasons, the owner-action list) and a CHANGELOG
  `## [unreleased] — <title>` entry, written after the loop completes.
- Edge cases: a branch name with `/` (the fixture's `ride/foo`); the origin
  checkout with no `refs/remotes/origin/HEAD` (symref line still names the
  default); a remote that advertises no HEAD symref (fallback, then fail
  closed); a push that prints a pre-push hook banner on stdout before the
  porcelain lines (parse only lines for `refs/heads/<b>`).

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-036 | Spec-AC-01 | integration | tests/skills/test-aai-merge-cleanup.sh | test_036_remote_branch_deleted_by_lease: build_world; plan exits 0, world digest equal, delete-remote-branch targets contain origin/ride/foo and the head prefix; apply exits 0; the bare has no refs/heads/ride/foo; JSON step done with detail ride/foo; text run of a fresh world prints delete-remote-branch: done; remaining has no origin/ride/foo; the saved report lists the step; the bare's main and an unrelated remote branch are unchanged (positive control) | sed:s/function deleteRemoteBranch\(ctx\) \{/function deleteRemoteBranch(ctx) { return { status: 'noop', detail: 'remote_absent' };/ | green |
| TEST-037 | Spec-AC-02 | integration | tests/skills/test-aai-merge-cleanup.sh | test_037_moved_remote_retained: arm pre-moved (a commit pushed to the bare ride/foo after the merge): apply exits 0, step retained remote_moved, bare ride/foo at the new oid, remaining names origin/ride/foo and remote_moved, remove-worktree and delete-branch done; arm race: a git shim advances the bare ref right before the engine's push; same assertions | sed:s/const lease = .*;/const lease = '--porcelain';/ | green |
| TEST-038 | Spec-AC-03 | integration | tests/skills/test-aai-merge-cleanup.sh | test_038_absent_noop_and_idempotent: arm absent (bare ref deleted before apply): step noop remote_absent, no remaining line; arm race-absent (shim deletes the bare ref right before the push): step noop remote_absent; arm rerun: after a successful apply a second apply exits 0, every action step noop, the saved report count unchanged, world digest unchanged | sed:s/if \(remoteOid === ''\) return/if (false) return/ | green |
| TEST-039 | Spec-AC-04 | integration | tests/skills/test-aai-merge-cleanup.sh | test_039_fork_and_unknown_origin_retained: arm fork (isCrossRepository true): retained remote_fork; arm field absent: retained remote_unknown; each arm: bare ride/foo still exists, remaining names origin/ride/foo and the reason, exit 0, remove-worktree and delete-branch done | sed:s/ctx\.pr\.isCrossRepository === true/false/ | green |
| TEST-040 | Spec-AC-05 | integration | tests/skills/test-aai-merge-cleanup.sh | test_040_base_default_and_bad_name_retained: arm default (bare HEAD symbolic-ref set to refs/heads/ride/foo): retained remote_is_base, bare ride/foo still exists; arm base (PR fixture headRefName main, equal to baseRefName main): retained remote_is_base, bare main unchanged; arm bad name (PR fixture headRefName ride..foo, which passes the planChecks bad_head_name refusal but fails git check-ref-format): retained remote_bad_name; each exits 0 | sed:s/\[ctx\.base, defaultBranch\]\.includes\(b\)/false/ | green |
| TEST-041 | Spec-AC-06 | integration | tests/skills/test-aai-merge-cleanup.sh | test_041_rejected_and_unreadable_never_stop: arm rejected (pre-receive hook on the bare exits 1 with protected branch on stderr): retained remote_delete_rejected with the hook text in the detail; arm unreadable (git shim fails ls-remote): retained remote_unknown; each arm: bare ride/foo still exists, exit 0, report step done, the saved report Remaining section names origin/ride/foo | sed:s/return retain\('remote_delete_rejected'/return stop('remote_delete_rejected'/ | green |
| TEST-042 | Spec-AC-07 | contract | tests/skills/test-aai-merge-cleanup.sh | test_042_canon_runs_block_unwrapped: SKILL_MERGE.prompt.md contains as the command itself, never through followed by bash -c, sh -c and eval; step 3 section has no remote branch deletion owner action and contains retained and never delete; both extracted blocks contain no rm command word, no Remove-Item, no --force; the PowerShell block contains $env:AAI_GIT_WRITE = $null; the prompt-diet ledger has the key merge-cleanup-delete-remote-branch with a positive integer credit of at most 600 | sed:s/as the command itself, never through/as the command itself, or through/ | green |
| TEST-043 | Spec-AC-08 | integration | tests/skills/test-aai-merge-cleanup.sh | test_043_dependents_retain_remote_branch: arm dependents (fake gh lists one open PR based on ride/foo): plan lists retain origin/ride/foo (remote_has_dependents), apply exits 0 with the step retained remote_has_dependents naming the PR number, the gh log shows the pr list query, bare ride/foo still exists; arm unlisted (fake gh fails the pr list query): retained remote_unknown, bare ride/foo still exists; arm head-of (fake gh lists one open PR whose head is ride/foo): plan lists retain origin/ride/foo (remote_has_dependents), apply exits 0 retained remote_has_dependents naming the PR number and saying opened from it, the gh log shows the pr list --head query, bare ride/foo still exists; arm head-unlisted (fake gh fails the pr list --head query): retained remote_unknown, bare ride/foo still exists | sed:s/const opened = dependentNumbers\(ghDependents\(ctx\.origin, b, 'head'\)\);/const opened = [];/ | green |

Mutation targets: .aai/scripts/merge-cleanup.mjs for TEST-036 to TEST-041 and TEST-043;
.aai/SKILL_MERGE.prompt.md for TEST-042. The intake's "a mutation that drops
the compare-and-swap reddens this test" is TEST-037's row: without the lease
the race arm deletes the moved branch.

## Verification

- V1: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-merge-cleanup.sh`
  exits 0 (all functions, TEST-001 to TEST-043 including the edited TEST-002
  and TEST-010). Single test: append the function name or `TEST-0xx`.
- V2: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh`
  and `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-preflight.sh`
  exit 0 (TEST-012 pin, want_growth sum).
- V3 regression: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-merge-cleanup.sh TEST-016`
  (Pester twin under local pwsh) exits 0, the suites
  `node .aai/scripts/select-suites.mjs` picks for the changed paths through
  the wrapper, and `node .aai/scripts/docs-audit.mjs --check --strict`.
- V4 mutation: `node .aai/scripts/mutation-run.mjs` per row on the targets
  above, then `mutation-gate.mjs` at close.
- Lint: `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0222-spec-merge-cleanup-delete-remote-branch.md`.

PASS criteria: every TEST row green with a stored RED and a mutation record,
every Spec-AC terminal, V1 to V3 exit 0.

## Evidence contract

Every artifact records ref_id `merge-cleanup-delete-remote-branch`, the
Spec-AC and TEST ids, the exact command, exit code, log path and diff or
commit identity. TDD stores RED per AC-gating test, GREEN output and one
mutation record per row under
`docs/ai/tdd/spec-merge-cleanup-delete-remote-branch/`. Validation repeats
V1 to V3 independently and re-runs F1 to F5 on its own scratch repo (the
outcome parsing rests on them). The Validation report carries an admissible
aai-outcome-v1 block, and its path is the `set-validation --evidence` value.

### Evidence by strategy

Strategy `tdd`: stored RED artifact per AC-gating test under docs/ai/tdd/
plus the full verification matrix V1 to V4.

## Residual risks

- R1 GitHub-specific refusals (protected branch, rulesets, a token without
  `contents:write`) are exercised only through the pre-receive stand-in (F4);
  their exact stderr wording is not measured. Any `!` line or non-zero exit
  maps to `remote_delete_rejected`, so a wording change cannot turn a refusal
  into a deletion.
- R2 Credentials: with `GIT_TERMINAL_PROMPT=0` a remote needing interactive
  credentials fails fast and is retained (`remote_delete_rejected` or
  `remote_unknown`); an SSH key passphrase prompt through an agent-less
  ssh is not covered by that variable and could wait up to the 120 s timeout.
- R3 The engine cannot make the agent run the block unwrapped; TEST-042 pins
  the wording only. Whether a given harness's safety check accepts the block
  is not testable here; the block is kept free of the words such checks key
  on (rm, Remove-Item, --force).
- R4 A GitHub "automatically delete head branches" setting may delete the
  branch first; that is the `remote_absent` noop path.
- R5 Native Windows: the push path is the same git CLI; only the Pester twin
  (CI ps1-quality, local pwsh) exercises it there, with the bare origin's
  happy path only.

## Assumptions (autopilot, recorded instead of questions)

- A1 Reason names: the intake's five plus `remote_bad_name` for the name
  proof (D2), and `remote_absent` as the noop detail.
- A2 A missing `isCrossRepository` field is `remote_unknown`, not a pass
  (fail closed).
- A3 A missing default branch on both the symref line and the local
  `refs/remotes/origin/HEAD` is `remote_unknown` (fail closed).
- A4 Retained remote branches stay out of the report's drafts-only
  `retained` array; they appear in the step status and `remaining` (D6).
- A5 Ceremony level 2: no `protected_paths_l3` surface; no new `.aai/**`
  file, so no PROFILES entry is owed; the prompt-corpus obligation is folded
  in (D10, TEST-042, V2).
- A6 A post-freeze amendment, if needed, is recorded with `--signoff none`
  (autopilot default) and signed by the owner's later `/aai-merge` direction.
