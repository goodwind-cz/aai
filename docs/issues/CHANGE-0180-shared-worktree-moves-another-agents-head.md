---
id: shared-worktree-moves-another-agents-head
number: 180
type: change
status: draft
links:
  pr: []
  commits: []
---

# One agent's branch switch moves another agent's HEAD mid-ceremony

## Summary
- Two agent sessions working in the same checkout share one `.git/HEAD`. A
  `git checkout` or `git reset --hard` by one silently relocates the other,
  between two of its consecutive commands, with no error on either side.
- The registry already carries the observation as P1
  `fu-head-moved-between-commands`, filed with "The cause is not established"
  and a leading hypothesis. This intake supplies the established cause and asks
  for the guard.

## Motivation / Business Value
- Observed 2026-09-06. Session A was running the close ceremony on
  `fix/live-page-shows-dead-heartbeats`. Session B, in the same working tree,
  ran `git checkout main` followed by `git reset --hard origin/main`. Session A's
  next command found itself on `main`: `close-work-item` reported "no scanned doc
  resolves to id", a regenerated `INDEX` dropped from 477 documents to 475, and a
  stamp commit landed on `main`. The push was refused only because `main` is
  branch-protected here.
- The cause is now established and is not a defect in either session's logic:
  it is two writers on one `.git`. A downstream install without branch
  protection would have taken that commit onto its default branch.
- Every write step in SKILL_PR assumes the branch it checked earlier is still
  the branch it is on. That assumption is false whenever a second session shares
  the tree, and nothing currently tells either one.

## Scope
- In scope: making a shared-checkout HEAD move detectable rather than silent —
  a guard in the vendored layer, since this must hold wherever AAI is installed
  (operator contract rule 5). Mechanism left to Planning: candidates include a
  branch/HEAD assertion carried across the steps of a ceremony that already
  knows its ref_id (`branch-guard.mjs` is the existing seam), and a cheap
  liveness check for a second agent in the same tree.
- Also in scope: correcting `fu-head-moved-between-commands` so the registry
  records the established cause instead of "not established".
- Out of scope: preventing two sessions from sharing a tree (an operator
  choice), any locking scheme across sessions, and changes to `/aai-worktree`.

## Affected Area
- `.aai/scripts/branch-guard.mjs`, the ceremony steps in
  `.aai/SKILL_PR.prompt.md` that perform git writes, and the follow-up registry
  entry.

## Desired Behavior (To-Be)
- A ceremony that has established which branch it works on refuses, loudly and
  before writing, if HEAD is no longer that branch.
- The refusal says what it expected, what it found, and that a concurrent
  session in the same checkout is the likely cause.

## Acceptance Criteria
- AC-001: Given a ceremony step that recorded branch B, when HEAD is moved to a
  different branch before the next write step, that step refuses non-zero and
  names both the expected and the actual branch.
- AC-002: The refusal is raised BEFORE any commit, stage or push, so no write
  lands on the wrong branch.
- AC-003: A detached HEAD and a branch renamed under the session are each
  distinguished from the concurrent-session case in the message, rather than
  collapsed into one generic error.
- AC-004: A single-session run is unaffected: no new prompt, no new refusal, and
  no measurable step added to the common path.
- AC-005: `fu-head-moved-between-commands` carries the established cause. Since
  `follow-ups.mjs` offers only `add` and `close`, the scope states which of the
  two it used and why, rather than editing the append-only record.

## Verification
- A suite arm that starts a ceremony on a fixture branch, moves HEAD out from
  under it with a plain `git checkout` in the same fixture, and asserts the next
  write step refuses and wrote nothing.
- A mutation arm: removing the assertion lets the write land on the wrong branch,
  turning the arm red.
- `node .aai/scripts/follow-ups.mjs list` shows the corrected entry.

## Constraints / Risks
- The guard must not become a per-step prompt or a lock; it is an assertion, and
  its cost must stay near zero on the single-session path (AC-004).
- A false positive here blocks a legitimate ceremony, which is worse than the
  defect for a solo user. Planning should prefer an assertion that can only fire
  on a genuine mismatch over any heuristic about "another session might exist".
- No secret is referenced by this scope.
- Roadmap: off-roadmap maintenance. It needs an owner decision to be added to
  `docs/ai/roadmap.yaml` or an explicit `--override` at ride time.

## Notes
- Sibling intake from the same session: unrecorded-spec-amendment-is-invisible.
