---
id: directed-merge-and-post-merge-cleanup
type: product
capability: directed-merge-and-post-merge-cleanup
status: current
delivered_by:
  - directed-merge-and-post-merge-cleanup
  - merge-direction-signs-amendments
  - merge-cleanup-submodule-worktree
  - merge-cleanup-delete-remote-branch
  - merge-cleanup-ride-leftovers
  - merge-cleanup-resolves-framework-friction
spec: docs/specs/SPEC-0218-spec-directed-merge-and-post-merge-cleanup.md
updated: 2026-10-25
---

# Merge a named pull request and clean up after it

## What it does

`/aai-merge <PR>` finishes a ride in one step. It checks the pull request you
named, merges it only because you asked for that exact pull request, and then
cleans up after it. For an already merged pull request it does the cleanup
alone.

The cleanup archives before it removes anything. Leftover draft copies of the
delivered documents move to an archive, but only when their exact bytes are in
the pull request. The main checkout fast-forwards to the new base while your
other uncommitted work stays as it was. Append-only ledgers keep the incoming
history as a byte-exact prefix, with local lines added after it. The merged
work item leaves the current focus, and the ride worktree and its local branch
are removed once they are proven finished.

The merged branch on origin is deleted too, by compare-and-swap against the
merged head, so a branch someone pushed to after the merge is never deleted.
It is kept, with a named reason on a `remaining:` line, when it moved, when the
pull request came from a fork, when it is the base or default branch, when
another open pull request is based on it or opened from it, when the server
refuses the delete, or when any of that cannot be read. A kept branch never
stops the rest of the cleanup.

A ride worktree with git submodules is removed too, but only after every
submodule, nested ones included, is proven safe to lose. Each one must be
clean, have a remote, and have its checked-out commit, every local branch and
every local tag on that remote, with no stash. Ignored single files inside a
submodule (a `.env`, say) and each submodule's local tags (names and annotated
tag objects) are archived first. Wholly ignored directories
(`node_modules/`, `dist/`) are removed but named in the plan and the report.
If any submodule fails the proof, nothing is removed and the reason names the
submodule. Preflight shows the same blocker as a `cleanup blocked:` line before
the merge command, so you know before you direct the merge.

Your merge direction is also your signature. The contract amendments a ride
made to its frozen spec after freeze are signed by the same words you used to
merge it: preflight lists them as `signs on merge:` lines before the merge
command, and the cleanup signs them once the merge is on the base. A tracker of
owed sign-offs closes when every contract amendment it tracks is signed. There
is no separate sign-off question before the merge. A merge made without your
direction (a lane or standing merge) signs nothing.

The cleanup also handles the traces a ride leaves behind itself:

- **The ride's own roadmap entry.** A roadmap entry the ride wrote into the
  main checkout is set aside into the archive, and the merged roadmap is taken.
  This is only when the local change touches nothing but that ride's entry;
  any other local roadmap change still stops the cleanup.
- **Ledger lines written after the last commit.** Lines appended to the ride
  worktree's append-only ledgers after its last commit (test-run records,
  events) move byte for byte to the main checkout's ledgers, and the worktree
  is then removed. Any other edit there still stops the cleanup.
- **A changed cleanup engine.** When the merged pull request changes the
  cleanup engine itself, the new engine finishes the run in the same
  invocation.

Every refusal or stopped step is sorted into one of five outcomes, by one table
in the engine, and printed as an `OUTCOME <json>` line the agent routes instead
of improvising:

- **Fixed by the cleanup.** A leftover draft whose content matches the numbered
  document, a roadmap change the merged roadmap already contains, a generated
  page, or a missing pull-request link. It archives first, then fixes.
- **Kept.** Your uncommitted work in a worktree, a main checkout on another
  branch or with its own commits, a staged roadmap change, a branch that moved.
  Nothing there is touched; the step is reported as `Kept: ...` and the other
  steps finish.
- **Retried.** A failed fetch or a dropped connection during the cleanup. The
  agent reruns the same block without asking, at most twice in a row; the
  second retry only when the item, origin HEAD, the journal's done lines or the
  manifest's row count differ from the retrying run. A failed platform read in
  preflight is not retried; it goes straight to you.
- **A question with a recommendation.** A leftover draft that differs from the
  numbered document, or a roadmap clash the merged roadmap does not contain.
  The agent asks one menu for all of them, then runs the block again with your
  answers in `AAI_DECIDE` (exit 6 means an answer is still owed).
- **Needs you.** A missing login or a closed pull request. The `Needs you:`
  line says exactly what to do and which command to run again.

The run ends with a plain report: `Merge:`, `Cleanup:`, the `Kept:` items, the
open `Decision:` items and the `Needs you:` items. Running it again, or after
an interruption, finishes the remaining steps and reports the completed ones as
no-ops.

## How to use it

- Merge and clean up: `/aai-merge 447` in a session where you have just told
  the agent to merge that pull request. The agent runs the gates, records your
  words, prints one merge command pinned to the checked head commit, runs it,
  and then cleans up. The agent runs the cleanup block exactly as written, as
  the command itself, never wrapped in `bash -c`, `sh -c` or `eval`: a wrapper
  hides the script from the agent's own safety check, which may then refuse it.
- Clean up after a pull request someone already merged: `/aai-merge 447` on a
  merged pull request skips the merge and runs the cleanup only.
- Sign the backlog of rides merged before this existed, once, on a recorded
  owner decision: `node .aai/scripts/merge-cleanup.mjs sign-merged
  --authority-ts <ts of your decision record> --origin "$PWD" --dry-run`
  shows what would be signed and closed; the same command without `--dry-run`
  does it. Pass `--origin` with the checkout whose ledger should carry the
  signatures (the ride worktree, so they ship in its pull request); without it
  every mode reads and writes the main checkout (the first git worktree).
- Answer the cleanup's question: the agent shows the `Decision:` items as one
  menu and reruns the block with `AAI_DECIDE="<id>=<option>,..."` (or
  `--decide`). An option that was not offered prints `IGNORED` and changes
  nothing.
- Read-only look first:
  `node .aai/scripts/merge-cleanup.mjs plan --pr 447` lists every step and
  target without changing anything.

## Data model

- Archive: `docs/ai/archive/merge-cleanup/pr-<n>/` in the main checkout
  (gitignored). It holds the archived drafts, the ride's STATE and ignored
  evidence, the saved local ledger tail, a `manifest.jsonl` with sha256 per
  archived file, and a `sync/pending.json` journal while a base sync is in
  flight. Ignored files and tag refs (`.aai-submodule-tags/tags.txt` plus raw
  annotated tag objects) from ride submodules go under `worktree-submodules/`;
  wholly ignored directories that were removed without an archive are listed
  in `removed.jsonl` and in the report section `## Removed, not archived`.
- Remote branch: the `delete-remote-branch` step reports `done <branch>`,
  `noop remote_absent`, or `retained <reason> <fact>`; a retained branch also
  gets a `remaining:` line in the report.
- Run report: `docs/ai/reports/merge-cleanup-pr<n>-<UTC>.md` (gitignored):
  verified base and head, archived paths, retained changes, the audit verdict,
  and the steps still remaining.
- Decision record: one `directed_merge` line in `docs/ai/decisions.jsonl`
  carrying your verbatim direction, the pull request number and the head commit
  the merge is pinned to. It is written once, before the merge runs.
- Signatures: one `spec_amendment_classification` line per signed amendment
  (`owner_signoff: true`, `classifies_record: <record key>`) whose `source`
  names the pull request, the merged head, your words and the merge commit
  (for `sign-merged`: the decision's timestamp, your answer, the pull request
  and the base commit that delivered the ride). A closed tracker is one
  `follow_up_status` line. Both are appended to `docs/ai/decisions.jsonl`.

## Interfaces and contracts

- `/aai-merge <PR>` skill in all four skill trees, backed by
  `.aai/SKILL_MERGE.prompt.md` (bash and PowerShell blocks).
- `node .aai/scripts/merge-cleanup.mjs preflight --pr <n> --expect-head <sha>
  --directed-by human --direction "<words>" [--origin <abs>] [--json]`: gates
  for an open pull request. It never merges; on success it prints one
  `gh pr merge <n> --squash --match-head-commit <sha>` line, preceded by one
  `signs on merge: <record key> <ref> <what>` line per amendment the merge
  will sign (or `signs on merge: none`); `--json` carries them as
  `signs_on_merge`. A submodule that would stop the cleanup prints one
  `cleanup blocked: <reason> <detail>` line before the merge command, and
  `--json` carries `cleanup_blockers` (an empty array when there is none);
  it never refuses the merge.
- `merge-cleanup.mjs plan --pr <n>` (read-only) and
  `merge-cleanup.mjs apply --pr <n> --pid <harness pid> [--direction "<words>"]
  [--archive-divergent <path>]...` (cleanup after a merged pull request).
  Its `sign-amendments` step runs right after the base sync; it signs only
  when the ledger holds your `directed_merge` for that pull request and head,
  and otherwise reports `no_human_direction`. The report lists `signed` record
  keys and `closed` trackers. Its `delete-remote-branch` step runs after the
  local branch is deleted: it reads `git ls-remote --symref origin` plus two
  `gh pr list --state open` queries (`--base` and `--head` the branch) and
  deletes with `git push --porcelain --force-with-lease=refs/heads/<b>:<merged
  head> origin :refs/heads/<b>`. Retained reasons: `remote_moved`,
  `remote_fork`, `remote_is_base`, `remote_bad_name`,
  `remote_has_dependents` (naming the pull requests), `remote_delete_rejected`
  and `remote_unknown`. The push URL of `origin` must equal its fetch URL
  (one URL each, after `pushurl` and `pushInsteadOf` rewrites); otherwise the
  branch is kept as `remote_unknown` before any remote is read.
- `merge-cleanup.mjs sign-merged --authority-ts <ts> [--exclude <fu-id>]...
  [--base <name>] [--dry-run] [--origin <abs>] [--json]`: signs the contract
  amendments of rides that are done on the base with a pull request delivered
  by a first-parent commit, and closes the trackers left fully signed. It
  takes no `--pr`. Its authority is one `by: human` `hitl_decision` with an
  answer; a `directed_merge` (your words about one pull request) does not
  authorize it. Trackers it leaves open are reported with the reason
  (`excluded`, `unmerged:<ref>`, `unclassified:<key>`, `no_contract_records`).
- Exit codes: 0 complete or kept, 2 usage error, 3 refused
  (`REFUSE <reason> <detail>` with an `OUTCOME` line), 4 stopped mid-way (a
  re-run resumes), 6 a decision is pending, 10 preflight ready. The agent routes
  each `OUTCOME` line by its class and state; it never finishes a step by hand.
- Refusal reasons include `no_direction`, `not_open`, `draft`,
  `head_changed`, `checks_failing`, `not_mergeable`, `sweep_missing`,
  `repo_mismatch`, `not_merged`, `merge_commit_not_on_base`,
  `base_diverged`, `overlap`, `untracked_collision`, `ledger_rewritten`,
  `worktree_dirty`, `worktree_missing`, `tip_mismatch`, `session_locked`,
  `submodule_dirty`, `submodule_unpushed`, `submodule_stash`,
  `submodule_no_remote`, `submodule_unverifiable` (each naming the submodule
  path; the same reason stops `apply` with exit 4 when it appears only after
  the proof passed),
  `signs_unknown` (preflight cannot derive what the merge signs), and for
  `sign-merged` `no_owner_decision` (the timestamp names no single
  `by: human` `hitl_decision` with an answer in the ledger the refusal names),
  `base_unreadable`, `ledger_unreadable`.
- Test-only environment variables (`AAI_MERGE_CLEANUP_GH_NODE`,
  `AAI_MERGE_CLEANUP_STOP_AFTER`, `AAI_MERGE_CLEANUP_CRASH_AT`,
  `AAI_MERGE_CLEANUP_TOUCH_AT`, `AAI_MERGE_CLEANUP_FAIL_IGNORED_LS` and
  `AAI_MERGE_CLEANUP_FAIL_IGNORED_LS_AT`) do nothing
  unless `AAI_MERGE_CLEANUP_TEST_SEAMS=1` is also set.

## Limits and non-goals

- It merges only the pull request you name, only at the head commit it
  checked, and never bypasses branch protection. It never merges merely
  because a ride opened a pull request.
- No forced worktree removal except for a ride worktree with submodules, and
  then only by the engine after the proof above; no `git branch -D`, no
  `git clean`, reset or stash. The only remote branch it deletes is the merged
  pull request's own head branch on origin, and only at the merged head.
- A pull request opened from or onto the branch between the dependents check
  and the push is not seen. A fork pull request with the same branch name
  keeps our branch (over-retention, never a wrong delete). A fork pull
  request's `remaining:` line names an origin branch that may not exist.
- The submodule proof reads the remote-tracking refs as they are (no fetch),
  so a stale ref can report a pushed commit as unpushed; fetch and re-run.
  A file written into a submodule between the last check and the removal, or
  a commit reachable only from notes or other custom refs, is not protected.
  A forced removal with submodules is not exercised on native Windows.
- Moved ledger lines are matched through an append-intent record in the run
  journal. A crash between the ride-ledger reset and its journal record can
  make a later, byte-identical ride tail count as already moved; that copy
  then lives only in the archive. A main ledger rewritten shorter between a
  crash and the re-run gets the tail appended again (a visible duplicate).
  A replaced engine that fails stops with `STOPPED reexec_child_exit_<n|signal>`
  (exit 4).
- A draft whose content differs from the delivered document is kept, with a
  named reason, unless you pass `--archive-divergent` for it.
- The engine cannot prove that `--direction` words are yours; only the skill
  rule (it runs on your explicit `/aai-merge <n>`) keeps an agent from
  inventing them.
- It does not report on every worktree in the repository; that broader report
  is a separate request (ISSUE-0091).
- Native Windows is covered by the PowerShell block and its CI tests; the
  GitHub field shapes are exercised through a stub in tests.

## Links

- Request: docs/issues/CHANGE-0206-directed-merge-and-post-merge-cleanup.md
- Spec: docs/specs/SPEC-0218-spec-directed-merge-and-post-merge-cleanup.md
- Validation evidence: docs/ai/reports/VALIDATION-r3-directed-merge-and-post-merge-cleanup.md
- Signing request: docs/issues/CHANGE-0208-merge-direction-signs-amendments.md
- Signing spec: docs/specs/SPEC-0220-spec-merge-direction-signs-amendments.md
- Submodule request: docs/issues/ISSUE-0097-merge-cleanup-submodule-worktree.md
- Submodule spec: docs/specs/SPEC-0221-spec-merge-cleanup-submodule-worktree.md
- Remote-branch request: docs/issues/CHANGE-0209-merge-cleanup-delete-remote-branch.md
- Remote-branch spec: docs/specs/SPEC-0222-spec-merge-cleanup-delete-remote-branch.md
- Ride-leftovers request: docs/issues/CHANGE-0210-merge-cleanup-ride-leftovers.md
- Ride-leftovers spec: docs/specs/SPEC-0223-spec-merge-cleanup-ride-leftovers.md
