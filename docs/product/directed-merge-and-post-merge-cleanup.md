---
id: directed-merge-and-post-merge-cleanup
type: product
capability: directed-merge-and-post-merge-cleanup
status: current
delivered_by:
  - directed-merge-and-post-merge-cleanup
spec: docs/specs/SPEC-0218-spec-directed-merge-and-post-merge-cleanup.md
updated: 2026-10-10
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

When anything is uncertain, it stops and names the reason rather than guessing.
Running it again, or after an interruption, finishes the remaining steps and
reports the completed ones as no-ops.

## How to use it

- Merge and clean up: `/aai-merge 447` in a session where you have just told
  the agent to merge that pull request. The agent runs the gates, records your
  words, prints one merge command pinned to the checked head commit, runs it,
  and then cleans up.
- Clean up after a pull request someone already merged: `/aai-merge 447` on a
  merged pull request skips the merge and runs the cleanup only.
- Read-only look first:
  `node .aai/scripts/merge-cleanup.mjs plan --pr 447` lists every step and
  target without changing anything.

## Data model

- Archive: `docs/ai/archive/merge-cleanup/pr-<n>/` in the main checkout
  (gitignored). It holds the archived drafts, the ride's STATE and ignored
  evidence, the saved local ledger tail, a `manifest.jsonl` with sha256 per
  archived file, and a `sync/pending.json` journal while a base sync is in
  flight.
- Run report: `docs/ai/reports/merge-cleanup-pr<n>-<UTC>.md` (gitignored):
  verified base and head, archived paths, retained changes, the audit verdict,
  and the steps still remaining.
- Decision record: one `directed_merge` line in `docs/ai/decisions.jsonl`
  carrying your verbatim direction, the pull request number and the head commit
  the merge is pinned to. It is written once, before the merge runs.

## Interfaces and contracts

- `/aai-merge <PR>` skill in all four skill trees, backed by
  `.aai/SKILL_MERGE.prompt.md` (bash and PowerShell blocks).
- `node .aai/scripts/merge-cleanup.mjs preflight --pr <n> --expect-head <sha>
  --directed-by human --direction "<words>" [--origin <abs>] [--json]`: gates
  for an open pull request. It never merges; on success it prints one
  `gh pr merge <n> --squash --match-head-commit <sha>` line.
- `merge-cleanup.mjs plan --pr <n>` (read-only) and
  `merge-cleanup.mjs apply --pr <n> --pid <harness pid> [--direction "<words>"]
  [--archive-divergent <path>]...` (cleanup after a merged pull request).
- Exit codes: 0 complete, 2 usage error, 3 refused before any change
  (`REFUSE <reason> <detail>`), 4 stopped mid-way (a re-run resumes), 10
  preflight ready.
- Refusal reasons include `no_direction`, `not_open`, `draft`,
  `head_changed`, `checks_failing`, `not_mergeable`, `sweep_missing`,
  `repo_mismatch`, `not_merged`, `merge_commit_not_on_base`,
  `base_diverged`, `overlap`, `untracked_collision`, `ledger_rewritten`,
  `worktree_dirty`, `worktree_missing`, `tip_mismatch`, `session_locked`.
- Test-only environment variables (`AAI_MERGE_CLEANUP_GH_NODE`,
  `AAI_MERGE_CLEANUP_STOP_AFTER`, `AAI_MERGE_CLEANUP_CRASH_AT`) do nothing
  unless `AAI_MERGE_CLEANUP_TEST_SEAMS=1` is also set.

## Limits and non-goals

- It merges only the pull request you name, only at the head commit it
  checked, and never bypasses branch protection. It never merges merely
  because a ride opened a pull request.
- No forced worktree removal, no `git branch -D`, no `git clean`, reset or
  stash, and no deletion of remote branches.
- A draft whose content differs from the delivered document is kept, with a
  named reason, unless you pass `--archive-divergent` for it.
- It does not report on every worktree in the repository; that broader report
  is a separate request (ISSUE-0091).
- Native Windows is covered by the PowerShell block and its CI tests; the
  GitHub field shapes are exercised through a stub in tests.

## Links

- Request: docs/issues/CHANGE-0206-directed-merge-and-post-merge-cleanup.md
- Spec: docs/specs/SPEC-0218-spec-directed-merge-and-post-merge-cleanup.md
- Validation evidence: docs/ai/reports/VALIDATION-r3-directed-merge-and-post-merge-cleanup.md
