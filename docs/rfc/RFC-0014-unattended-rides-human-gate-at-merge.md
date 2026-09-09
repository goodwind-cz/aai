---
id: unattended-rides-human-gate-at-merge
type: rfc
number: 14
status: done
links:
  spec: null
  pr:
    - TBD
  commits:
    - d9638a845d199653f59f0a9850e6124a3eeb712e
---

# RFC (Decision Proposal)

Move the human gate from before the pull request to the merge, and let an
explicitly opted-in unattended ride resolve its own questions best-effort
instead of exiting.

## Context

- Problem or opportunity:

  An overnight ride cannot finish today. `/aai-ship` stops twice before a human
  ever sees a pull request, and both stops are deliberate rather than accidental:

  1. **The ship checkpoint.** On validation PASS with the review gate satisfied,
     step 5 presents the scope and waits: *"STOP and wait. This is a genuine
     human gate — never assume consent."* No PR exists until a human types `y`.
  2. **Any HITL, stagnation, or run-budget escalation.** `SKILL_LOOP` stop
     condition (b) prints the question and EXITS; `/aai-ship` step 3 surfaces it
     verbatim and stops. The loop does not attempt an answer.

  The consequence is that a ride started in the evening parks on its first
  question and the remaining hours are idle. The owner's goal is the opposite:
  start in the evening, find several finished pull requests in the morning, and
  spend human attention on reviewing and merging them rather than on unblocking
  the factory.

- **A structural finding that reframes the first stop.** The factory already
  ships an async-HITL capability (`CHANGE-0102` / `SPEC-0111`,
  `docs/product/async-hitl-platform-comments.md`): a blocking question is posted
  as a comment on the scope's linked GitHub issue or pull request, the ride
  parks, and whichever session runs next picks up the reply and continues. That
  mechanism **requires a thread to post to**. Because the ship checkpoint stops
  *before* the PR is opened, a scope with no pre-existing linked issue has no
  channel available, and the question falls back to blocking a terminal that
  nobody is watching at 02:00.

  So the current gate placement actively defeats a capability the project
  already paid for. Opening the PR earlier is not merely a preference about
  where to put a confirmation — it is what gives every subsequent question a
  durable, asynchronous channel. The two capabilities are complementary and
  currently ordered wrongly.

- Drivers/constraints:
  - Merging stays operator-only. `/aai-ship` never merges or releases, and that
    is not in question here; this RFC moves the gate *to* the merge, it does not
    remove it. An explicit owner override to merge remains explicit and logged.
  - Never silently downgrade rigor (`INTAKE_COMMON`): a cheaper or more
    autonomous lane must be an explicit choice, never a default drift.
  - Article 4 — degrade and report, never guess. An unattended ride that cannot
    decide must park loudly, not proceed quietly.
  - Every automatic decision must be auditable after the fact. The precedent
    exists: `/aai-interrogate` already appends each resolved decision to
    `docs/ai/decisions.jsonl` with its source.

## Proposal

- Recommended option:

  Two separable changes. Either can ship without the other, but the goal needs
  both.

  **P1 — the gate moves to the merge.** On validation PASS with the review gate
  satisfied, `/aai-ship` opens the pull request instead of asking permission to
  open it. The pull request becomes the review surface and the merge becomes the
  single human gate. Rationale: a PR is reversible — it can be closed,
  force-pushed over, or left unmerged indefinitely — whereas a merge is the
  first genuinely costly step. Consent is still required for the irreversible
  action; it is simply asked at the point where it means something. As a
  side effect, the PR thread exists in time to carry async HITL for the rest of
  the ride.

  **P2 — unattended rides resolve their own questions.** An explicitly opted-in
  unattended mode changes `SKILL_LOOP` stop condition (b): before exiting, a
  HITL escalation is put through the resolution ladder `/aai-interrogate`
  already implements — resolve silently from the codebase where the answer is
  there (`inferred: <path>`), otherwise adopt the recommended answer
  (`recommended-default`). Every auto-resolved decision is appended to
  `docs/ai/decisions.jsonl` with its source and reproduced in the morning
  report. Questions above a declared severity boundary do not get this
  treatment: they park and post async-HITL to the now-existing PR thread.

  Unattended mode is opt-in per ride and never the default. Run budget,
  stagnation limit, and `max_ticks` remain in force unchanged — they are the
  guards that keep an unattended night bounded.

- Rationale:

  The pieces already exist and are individually proven; what is missing is that
  they are wired in the wrong order and one of them is not reachable from the
  loop. `/aai-interrogate` is exactly a best-effort answering machine with an
  audit trail, but it runs only at spec freeze. Async HITL is exactly a durable
  question channel, but it needs a thread the current gate placement withholds.
  P1 and P2 connect what is already built rather than introducing a new
  autonomy mechanism.

## Alternatives Considered

- **Option A — status quo plus wider async-HITL adoption.** Rely on async HITL
  alone by always creating a linked issue up front. Pros: no change to the human
  gate; smallest diff. Cons: still requires a human to answer every question,
  merely from a phone rather than a terminal, so a night still stalls on the
  first decision; adds an issue-creation step to every scope.
- **Option B — P1 without P2.** Move the gate to the merge, leave HITL exiting.
  Pros: unblocks the async-HITL channel; genuinely reversible. Cons: the ride
  still exits at the first real question, so the overnight goal is not met — it
  only shortens the morning.
- **Option C — full autonomy including merge.** Rejected. It violates the
  operator-only merge rule and removes the last reversible checkpoint; a wrong
  automatic decision would land on the default branch instead of sitting in an
  unmerged PR.
- **Option D — drive `/aai-ship` from the generic `/loop` skill on an interval.**
  Rejected as a solution to this problem. `/loop` re-invokes a command on a
  schedule but cannot answer a question, so it would re-encounter the same stop
  every interval and burn budget spinning.

## Consequences

- Technical impact:
  - `SKILL_SHIP` steps 5 to 7 reorder: PR creation moves ahead of the human
    gate, and the checkpoint becomes a merge-time surface.
  - `SKILL_LOOP` stop condition (b) gains an unattended branch; the exit path
    stays the default.
  - The interrogate resolution ladder becomes callable from the loop, not only
    at spec freeze. Its decision-recording contract is reused as-is.
- Operational impact:
  - The morning surface changes from "answer a parked question" to "review N
    pull requests and audit the decisions taken on your behalf". That is a
    different kind of attention, and arguably a scarcer one — the RFC should be
    judged on whether that trade is wanted, not only on whether it is possible.
  - Unattended spend concentrates overnight; the run budget guard becomes the
    load-bearing cost control rather than a rarely-hit backstop.
- Migration/compatibility notes:
  - P2 is opt-in; an unflagged ride behaves exactly as today.
  - P1 changes default behavior for every `/aai-ship` invocation and therefore
    needs an explicit owner decision, not a silent rollout.

## Risks

- Primary risks and mitigations:
  - **Best-effort answers on scope questions cause spec drift.** The canon
    already treats a spec amendment as an owner-assigned scope change, so scope
    questions are precisely the class that must not be auto-resolved. Mitigation:
    the severity boundary in P2, plus the `decisions.jsonl` audit trail.
  - **A wrong automatic decision is now more expensive to unwind**, because it
    produces a pull request rather than a parked question. Mitigation: the PR is
    never merged automatically, so the cost is a discarded branch, not a
    reverted main.
  - **Unattended cost overrun.** Mitigation: existing run budget, stagnation
    limit and `max_ticks` stay in force; unattended mode must not be allowed to
    raise them.
  - **Automation complacency** — a morning stack of PRs invites shallower review
    than a single question would have received. No technical mitigation; worth
    naming as an accepted cost.

## Open Questions

- ~~Where exactly does the decide-yourself boundary sit?~~ **DECIDED** — see
  Decisions below.
- ~~Does P1 apply to every ride, or only to unattended rides?~~ **DECIDED** —
  see Decisions below.
- What bounds a night? A maximum number of pull requests, a token budget, a
  wall-clock window, or all three?
- Should an unattended ride be allowed to run intake itself, or only to consume
  drafts a human already wrote? The original request mentions processing draft
  documents, which suggests the latter.
- Does the morning report need to be a distinct artifact, or is
  `decisions.jsonl` plus the PR list sufficient?

## Decisions (owner, 2026-09-07)

**D1 — the boundary is drawn by SUBJECT, not by ceremony level.** A question
about *quality* is resolved autonomously: how to fix a defect, how to word a
finding, which model to route to, how to structure evidence. A question about
*scope, cost, or irreversibility* pauses for a human: changing what the work
item covers, spending beyond a declared budget, or anything that cannot be
undone.

Rejected alternatives and why. **Ceremony level** was rejected because it
misclassifies in practice: the ride that produced RES-0002 was `ceremony_level:
2`, yet every question it raised was a quality question that resolved without
the owner. **Touching the AC table** is sharp and machine-checkable but blind to
cost, and that same ride would have run to the budget ceiling under it. **A
self-declared severity field** was rejected because it relies on a role's
self-assessment, which is the thing observed failing that day — a validator
reported a run duration contradicted by the harness, and a remediator had to
correct the reviewer's own dispatch count.

Evidence behind D1: across that ride, two Validation FAILs and two Code Review
FAILs were all remediated with no human input, while the three genuine human
interventions were a budget decision, a merge authorization, and a git
incident — cost and irreversibility, exactly the two classes D1 reserves.

**D2 — P1 applies to every ride, not only unattended ones.** The human gate
moves from before the pull request to the merge, always. A pull request is
reversible: it can be closed, force-pushed over, or left unmerged. A merge is
the first step that is not, and consent belongs at the step that cannot be
undone. Keeping two different gate placements for interactive and unattended
rides was rejected as a second surface to maintain and test for no safety gain.

A second, independent reason: async HITL (`CHANGE-0102` / `SPEC-0111`) needs a
linked issue or pull request to post its question to. The current placement
withholds that thread until after the gate, so a scope with no pre-existing
issue has no channel and falls back to blocking a terminal. Opening the PR
first gives every later question a durable channel.

Merging remains operator-only; D2 moves the gate, it does not remove it.

## Approvals

- Required approvers (roles/names): repository owner. P1 changes a deliberate
  human gate and P2 introduces autonomous decision-making on the owner's behalf;
  neither may be adopted by an agent's own judgment.

## Notes

- Prompted by a discussion on 2026-09-07 about overnight unattended operation.
  The request as stated: start in the evening, wake to several finished pull
  requests, with the human involved only at the merge.
- Implementation mode (user choice): tdd — behavioral, multi-surface, and it
  touches both a deliberate human gate and autonomous decision-making on the
  owner's behalf, where a regression is expensive and hard to see.
  Recorded here rather than via `state.mjs set-strategy` because
  `implementation_strategy` is a single global block in `docs/ai/STATE.yaml`,
  and writing it now would overwrite the record belonging to the in-flight
  research spike (`mechanical-context-offload-to-cheap-tier`, `untested`).
  Planning treats this note exactly like an intake-sourced record.
