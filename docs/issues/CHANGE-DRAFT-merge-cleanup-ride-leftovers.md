---
id: merge-cleanup-ride-leftovers
type: change
number: null
status: draft
links:
  pr: []
  commits: []
---

# /aai-merge cleanup handles the ride's own leftovers instead of refusing

## Summary
- `/aai-merge 454` needed two owner interventions and a second run. The three snags all came from traces the ride itself leaves where the cleanup does not expect them. `merge-cleanup.mjs apply` now handles these three cases itself and keeps refusing everything else:
  - the main checkout's roadmap entry written by the ride's own ship-append;
  - append-only ledger lines written into the ride worktree after its last commit;
  - an engine changed by the merged PR itself.

## Motivation / Business Value
- Owner decision 2026-10-11, menu answer "Všechny tři v jedné jízdě (Recommended)" to "Co s tím aby to fungovalo lépe?".
- Observed on `/aai-merge 454`:
  1. `REFUSE overlap docs/ai/roadmap.yaml`. `/aai-ship` step 1a ship-append wrote `- capability: merge-cleanup-delete-remote-branch` / `status: active` into the main checkout while the ride ran in a worktree. The merged PR carried the same entry with `status: done`. The owner had to approve discarding the local line.
  2. `REFUSE worktree_dirty`. The ride worktree differed from its HEAD only by one appended line in `docs/ai/tests/test-runs.jsonl`, written by the pre-close full test sweep. The agent moved the line to the main checkout's ledger by hand.
  3. The `delete-remote-branch` step introduced by PR #454 did not run on the first apply. The engine was loaded from the main checkout before sync-base fast-forwarded it, so a second apply was needed.
- Every worktree ride hits (1) and usually (2). (3) hits every PR that changes the engine.

## Scope
- In scope (`.aai/scripts/merge-cleanup.mjs`, `tests/skills/test-aai-merge-cleanup.sh`, product doc, CHANGELOG):
  1. Roadmap overlap:
     - A local `docs/ai/roadmap.yaml` change in the main checkout whose every hunk touches only the merged ride's own capability entry is archived (`pre_sync_local_state`), and the incoming file is taken. The ride is the work item the merged PR delivered.
     - Any other local roadmap change still refuses `overlap`.
  2. Ledger appends in the ride worktree:
     - When the ride worktree differs from its committed HEAD only by appended lines in append-only ledgers (`docs/ai/tests/test-runs.jsonl`, `docs/ai/EVENTS.jsonl`, `docs/ai/decisions.jsonl`, or the engine's existing ledger list), apply checks that HEAD is a byte-exact prefix. It then appends exactly those bytes to the main checkout's same ledger, archives them, and treats the worktree as clean for removal.
     - A non-append edit, any other modified file, or an untracked non-ignored file still refuses `worktree_dirty`.
  3. Engine replaced by the merge:
     - After sync-base, if the engine file on disk differs from the running engine's bytes, apply re-executes the new engine once with the same arguments for the remaining steps.
     - The re-executed run never re-executes again (a loop guard), and the journal and idempotency stay intact.
- Out of scope:
  - Moving `/aai-ship` intake or ship-append into the worktree. The cleanup fix covers rides that already exist and downstream projects alike.
  - Committing the main checkout's post-merge ledger lines.

## Affected Area
- `.aai/scripts/merge-cleanup.mjs`; `tests/skills/test-aai-merge-cleanup.sh` (and the Pester twin if the wrapper surface changes); `docs/product/directed-merge-and-post-merge-cleanup.md`; `CHANGELOG.md`.

## Desired Behavior (To-Be)
- With a ride-only roadmap hunk in the main checkout, apply archives it and fast-forwards. A foreign hunk, or a mixed one, refuses `overlap docs/ai/roadmap.yaml` as today.
- A ride worktree whose only differences are ledger appends is removed after the appended lines land in the main checkout's ledgers byte-exact. The report lists the moved lines per ledger.
- When the merged PR changes `merge-cleanup.mjs`, one apply run executes every step of the new engine. The report says the engine was reloaded.

## Acceptance Criteria
- AC-001: Roadmap hunk touching only the merged ride's capability entry: apply exits 0, the local diff is archived, and `roadmap.yaml` equals the incoming base. A foreign or mixed hunk still refuses `overlap` with nothing written (fixture tests, plus a mutation that widens the predicate and reddens the foreign-hunk test).
- AC-002: Ride worktree with appended lines in `test-runs.jsonl` and `EVENTS.jsonl` only: apply removes the worktree, the main checkout's ledgers end with exactly those bytes, and the lines are archived. A non-append edit of a ledger, any other modified file, or an untracked file still refuses `worktree_dirty` (fixture tests plus a mutation).
- AC-003: The merged PR changes the engine (a fixture engine variant with an extra marker step): one apply run reports the marker step, the engine re-executes exactly once, a re-run is a noop, and an interrupted re-exec resumes (fixture tests plus a mutation that drops the loop guard or the re-exec).
- AC-004: The product doc and CHANGELOG describe the three behaviours. Existing merge-cleanup tests stay green, including Pester parity.

## Verification
- Command(s) and expected results:
  - `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-merge-cleanup.sh`: all pass.
  - Mutation evidence per AC via `mutation-run.mjs`.

## Constraints / Risks
- Data safety:
  - Every local change set aside is archived before it is overwritten.
  - Moved ledger lines are byte-exact.
  - Anything not proven to be the ride's own trace keeps refusing.
- The re-exec must not double-run steps or loop. It runs once, carries a guard env or argument, and refuses a second re-exec.
- No secret is referenced (secrets preflight skipped).

## Notes
- Implementation mode (autopilot default): Planning decides.
- This intake and its worktree were created before the ship-append, so this ride does not reproduce snag (1) on its own merge.
- Related: SPEC-0218 (directed merge), SPEC-0221, SPEC-0222.
