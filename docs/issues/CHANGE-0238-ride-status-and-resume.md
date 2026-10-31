---
id: ride-status-and-resume
type: change
number: 238
status: done
user_visible: true
capability: ride-status-and-resume
links:
  pr: []
  commits: []
---

# Ride status view and authorization-preserving resume

## Summary
- Final slice of RFC-0017 phase 4 ("extend existing lightweight and resume
  paths"), implementing the resume/status part of RFC-0017 section 5 "Make
  autonomy resumable and the public interface small". Two bounded deliverables:
  one deterministic status view for the current ride, and a resume path that
  inspects authoritative state before repeating an external effect and keeps
  already-recorded routine decisions so the owner is not asked again. The
  umbrella RFC stays open; phase 5 remains.

## Motivation / Business Value
- Today the owner learns where a ride stands by reading STATE.yaml, EVENTS,
  the loop's tick lines or the agent's prose. Several surfaces each answer part
  of it: `orchestration-dispatch.mjs` gives the next role, `aai-live` shows
  running harness sessions (and never reads STATE), `/aai-overview` and the
  factory report summarise history, and `/aai-hitl` surfaces a blocked
  question. None answers in one place "what is happening now, what evidence
  exists, what blocks, and what decision is next". RFC-0017 section 5 asks for
  exactly that one view.
- After an interruption (session death, spend limit, context compaction) a
  resumed ride re-derives its position from prose and memory. Repeated
  external effects (a second PR create, a second push, a second ledger record)
  and repeated questions for decisions already recorded (strategy/TDD choice,
  worktree/isolation decision, role routing) are the observed costs. Section 5
  requires inspecting authoritative state first and keeping routine defaults
  and already-granted authorization across a resume.

## Scope
- In scope:
  - A read-only status command (Planning names it; a `state.mjs`-adjacent
    script or a new subcommand) that prints, for the current focus, four
    named fields: current action (phase/status plus the role the dispatcher
    would pick next), evidence so far (validation/review verdicts and their
    report paths, TDD/test-run evidence, PR link if any), blocker (human-input
    question, stagnation, failing gate) or none, and next decision (who must
    act: the loop, or the owner with the exact command). Text and `--json`
    output. It is generated from canonical data (STATE, EVENTS, METRICS,
    decisions.jsonl) through existing readers (state engine,
    `orchestration-dispatch.mjs` `decide()`), never a second state engine, and
    it writes nothing.
  - Resume: a deterministic "already done?" probe for the ride's external
    effects that a resumed ride consults before repeating them. Planning picks
    the minimal set from the ride's real effects (at least: PR already open for
    the branch/ref; branch already pushed at the expected head; a ledger
    record already appended). The probe reads authoritative state (git, the
    platform CLI, the ledgers) and reports done/not-done with evidence.
  - Routine decisions survive a resume: a strategy choice, worktree decision
    and model-routing choice already recorded in STATE for the focus ref are
    reused, and the canonical prompts that would otherwise ask again (Planning,
    the loop's worktree gate, ride-handoff) say to reuse them. A recorded
    decision for a different ref is never reused.
  - Wire the status command into the canonical prompts where a status summary
    is printed today (the loop's stop/summary output and the /aai-ship
    checkpoint may cite it), without changing their decision logic.
  - Product doc, CHANGELOG entry, RFC-0017 phase 4 row (done if this slice
    completes phase 4; umbrella stays open).
- Out of scope:
  - A new state engine, a workflow service, or new lock types (RFC-0017 §5
    forbids them).
  - Changing the dispatcher's decision table or any merge/release authority.
  - Phase 5 (evidence reuse, process adapters).
  - Shrinking the public skill list (a later section-5 slice; file a
    follow-up if Planning finds a concrete cut).
  - Browser/HTML rendering (aai-live stays as it is).

## Acceptance Criteria
- The status command on a fixture STATE with a focus prints the four fields
  with values derived from that fixture, in text and `--json`; with no focus it
  says so and exits 0; it writes no file (proved by a before/after tree hash).
- A fixture with a human-input block reports that question as the blocker and
  the owner as the next actor; a fixture with validation pass and review pass
  reports the PR step as next.
- The already-done probe reports done for an effect that exists (fixture
  branch pushed at head, fixture PR open via a stubbed platform CLI) and
  not-done otherwise, and never performs the effect itself.
- A resumed ride whose STATE already records a strategy and worktree decision
  for the focus ref is not asked for them again (test over the reuse rule);
  a decision recorded for another ref is not reused.
- Cross-platform: any new shell entry point has its PowerShell twin, or the
  command is Node-only with both launchers, per the phase 3 convention.

## Assumptions (autopilot)
- Type is change, not PRD: it extends existing readers and prompts.
- No human-time metric recorded (autopilot default).
- Ceremony and worktree recommendation are Planning's call; a protected
  surface (state.mjs is L3) keeps its human gate.

## Constraints / Risks
- `state.mjs` and the dispatcher are protected surfaces; prefer a new
  read-only script that imports their readers over editing them.
- A status view that disagrees with the dispatcher is worse than none: the
  next-action field must come from `decide()`, not a reimplementation.
