---
id: merge-cleanup-delete-remote-branch
type: change
number: 209
status: done
links:
  pr:
    - 454
  commits:
    - 61a314b513af2683f7e2fac568c6a124b821fbf9
---

# /aai-merge deletes the merged remote branch itself, and its block passes the agent's safety check

## Summary
- After an owner-directed merge, `merge-cleanup.mjs apply` deletes the ride's remote branch on origin itself. Today it ends with `remaining: origin/<branch> still exists on the remote: delete it yourself`, and the owner must run `git push origin --delete` by hand. The deletion happens only when it is proven safe; otherwise the branch is retained with a named reason and the `remaining:` line stays.
- SKILL_MERGE tells the agent to run the canonical cleanup block as the command itself, never wrapped in `bash -c`, `sh -c` or `eval`. On `/aai-merge 453` such a wrapper made Claude Code's built-in removal check refuse the block, although the block contains no removal.

## Motivation / Business Value
- Owner direction 2026-10-11 (verbatim): "Podle mě by měl dělat i to mazání větve a neměl by mit problém s bezpečnostn kontrolou".
- SPEC-0218 D10 left remote deletion to the owner. In practice every directed merge ends with the same manual command for an already-merged branch whose head equals the merged PR head. That is a mechanical step, not a decision.
- On `/aai-merge 453` the agent wrapped the AAI_MERGE block in `bash -c '...'`. Claude Code refused it: "This command passes a shell -c script that runs rm, and Claude Code could not check the script". The same block run directly passed. The canon should prevent the wrapper, so a merge never stalls on a permission prompt the owner cannot see.

## Scope
- In scope:
  - `.aai/scripts/merge-cleanup.mjs`:
    - A new idempotent apply step `delete-remote-branch`, after `delete-branch`, that deletes `origin/<headRefName>` by compare-and-swap against the merged PR head. For example `git push --force-with-lease=refs/heads/<b>:<head> origin :refs/heads/<b>`, so a branch that moved is never deleted.
    - The report, the plan targets and the `remaining:` line reflect the step.
  - Proof before deletion:
    - the PR is MERGED;
    - the PR head repository is the origin repository (`isCrossRepository` false);
    - the branch is not the base or the default branch;
    - the remote head equals the PR `headRefOid`;
    - the name is valid.
  - Any failed proof, including a push the server rejects (a protected branch), retains the branch with a named reason and keeps the `remaining:` line. It never stops the rest of the cleanup.
  - `.aai/SKILL_MERGE.prompt.md`:
    - step 3: remote deletion is no longer an owner action except when retained;
    - run the block as the command itself, never through `bash -c`, `sh -c` or `eval`;
    - the PowerShell twin stays equivalent.
  - The product doc `docs/product/directed-merge-and-post-merge-cleanup.md` is updated.
- Out of scope:
  - Deleting remote branches of other PRs, forks, or anything that is not the merged PR's head ref.
  - Changing the GitHub repository setting "automatically delete head branches".
  - `gh pr merge --delete-branch`, which stays forbidden.

## Affected Area
- `.aai/scripts/merge-cleanup.mjs`, `.aai/SKILL_MERGE.prompt.md`, `docs/product/directed-merge-and-post-merge-cleanup.md`.
- Suites: `tests/skills/test-aai-merge-cleanup.sh`, the ps1 twin if the wrapper surface changes, and the prompt-corpus pins (diet ledger, TEST-012, pr-preflight want_growth).

## Desired Behavior (To-Be)
- With origin holding the merged head, `apply` reports `delete-remote-branch: done (<branch>)` and prints no `remaining:` line for it. `git ls-remote origin refs/heads/<branch>` is empty afterwards.
- If the remote branch moved after the merge (new commits pushed), apply reports `delete-remote-branch: retained (remote_moved …)`, leaves the branch intact, and keeps a `remaining:` line naming it.
- If the remote branch is already gone, the step is a noop (`remote_absent`), and a re-run of apply is idempotent.
- A fork PR, the base or default branch, an unreadable remote (`remote_unknown`) or a rejected push (`remote_delete_rejected`) is retained with that reason. The rest of apply is not affected.
- SKILL_MERGE states that the block is run as-is, and the block itself contains no command that a removal check flags.

## Acceptance Criteria
- AC-001: A bare-origin fixture with the remote branch at the merged head: apply deletes it (ls-remote empty) and the report records `delete-remote-branch: done`.
- AC-002: The remote branch was advanced after the merge: apply retains it with `remote_moved`, the branch is still at the new commit, and `remaining:` names it. A mutation that drops the compare-and-swap reddens this test.
- AC-003: The remote branch is already absent: the step is a noop, and a second apply run changes nothing.
- AC-004: Fork PR (`isCrossRepository` true), head equal to base, and server-rejected push (fixture pre-receive hook): each is retained with a named reason, and apply still exits 0 with the other steps done.
- AC-005: SKILL_MERGE step 3 no longer lists remote deletion as an owner action except when retained. It says to run the block as the command itself, never through `bash -c`, `sh -c` or `eval`. A test asserts that the bash block and the PowerShell twin contain no `rm`, `Remove-Item -Recurse` or `--force` command. Corpus pins and the diet ledger are updated.

## Verification
- Command(s) and expected results:
  - `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-merge-cleanup.sh`: all pass.
  - Mutation evidence for AC-002 via `mutation-run.mjs`.

## Constraints / Risks
- Deleting a remote ref is outward-facing. The compare-and-swap lease makes it safe against a push that races the cleanup, and the owner-directed `/aai-merge` remains the only entry point.
- The ref-guard hook needs `AAI_GIT_WRITE=1` for the push; the canonical block already sets it.
- The `Remove-Item Env:AAI_GIT_WRITE` line in the PowerShell twin removes an environment variable, not a file. Planning decides whether to rephrase it so a removal check cannot misread it.
- No secret is referenced (secrets preflight skipped).

## Notes
- Implementation mode (autopilot default): Planning decides.
- Related: SPEC-0218 D10 (remote left to the owner; superseded by this owner direction), SPEC-0221 (submodule worktree cleanup).
