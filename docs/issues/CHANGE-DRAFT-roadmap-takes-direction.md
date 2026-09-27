---
id: roadmap-takes-direction
type: change
number: null
status: draft
capability: roadmap-takes-direction
links:
  pr: []
  commits: []
---

# The roadmap takes a direction from the owner instead of only refusing rides

## Summary
- `docs/ai/roadmap.yaml` is read by five scripts and **written by none**
  (measured 2026-09-27: `ride-select.mjs`, `orchestration-dispatch.mjs`,
  `nothing-left-behind.mjs`, `close-work-item.mjs`,
  `check-vendored-script-deps.mjs` all read it; zero write it).
- So the roadmap can say NO and cannot take YES. Its only input is "the owner
  sits down, ranks candidates in a session doc, and someone hand-writes YAML" —
  which is how wave 1 and wave 2 were produced
  (`docs/project-sessions/2026-09-05-capability-roadmap.md`,
  `2026-09-12-wave-2-roadmap.md`).
- When it runs out it does not ask; it refuses. Wave 3 completed on 2026-09-26
  and since then EVERY new ride is off-roadmap and runs on `--override`.

## Motivation / Business Value
- The roadmap exists to cure a measured disease, quoted from the owner decision
  `capability-roadmap-drives-rides` (2026-09-05): *"Rides were selected from
  whatever the last review surfaced, so guards begot guards and the six fix
  chains consumed the month."*
- Half that cure shipped. The gate refuses off-roadmap fixes, so guards stop
  begetting guards — but nothing carries the owner's DIRECTION in, so the
  factory can only be stopped, never aimed.
- **Downstream this is the whole value.** A vendoring project that turns
  roadmap discipline on today gets a file that blocks fix-chasing and offers no
  way to say what should be built instead. That is why it reads as overhead:
  it is the restraining half without the steering half.
- The three places intent already lands are unconnected to it: 13 open draft
  intakes, 824 friction observations behind a triage engine that already scores
  and clusters them, and ~125 open follow-ups.

## Scope
- In scope: a command that HARVESTS candidates from those three existing
  sources; takes ONE SENTENCE of direction from the owner; proposes a ranked
  slate where every item shows the evidence behind its rank (not a hidden
  score); lets the owner choose by menu rather than by editing YAML; and writes
  a roadmap that `ride-select.mjs validate` accepts.
- In scope: an exhausted roadmap ASKS instead of refusing — when `next` finds no
  unfinished pair it offers the harvest rather than sending every ride to
  `--override`.
- In scope: selecting CAPABILITIES only. The maintenance half is bound at ride
  time from the backlog under the same 1:1 budget, instead of being guessed
  months ahead. This removes half the authoring cost and stops the roadmap
  predicting which fix a not-yet-built capability will need.
- Out of scope: changing the gate's refusal semantics, the 1:1 budget itself,
  or the `--override` escape. This adds an input; it does not loosen the rule.
- Out of scope: deciding what goes on this repository's own wave 2. The command
  must make that decision cheap, not make it.

## Affected Area
- `.aai/scripts/ride-select.mjs` (or a sibling), `.aai/templates/`,
  `.aai/AGENTS.md` rule 4, the friction triage and follow-ups readers as
  candidate sources, `tests/skills/test-aai-ride-select.sh`.

## Desired Behavior (To-Be)
- An owner with no roadmap, or an exhausted one, reaches a valid ranked roadmap
  without writing YAML and without ranking a list by hand.
- Every proposed item states why it is ranked where it is, in terms of evidence
  that already exists (observation counts, what it blocks, how long it has been
  open).
- A project that never opts in is unaffected: no file, no gate, no prompts.

## Notes
- Ceremony 2, TDD. The risk that matters is a proposer that looks helpful and
  ranks by something meaningless; every ranking input must be measurable from
  the repository, and the test must prove a candidate's rank MOVES when its
  evidence changes — not merely that a list came out.
