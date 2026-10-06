---
id: roadmap
type: product
capability: roadmap
status: current
delivered_by:
  - roadmap-serves-downstream-projects
spec: docs/specs/SPEC-0202-spec-roadmap-serves-downstream-projects.md
updated: 2026-10-01
---

# Roadmap: an ordered list of what to build next

## What it does

A project can now keep a roadmap: an ordered list of the capabilities it wants
built, in the order it wants them. You work with it through `/aai-roadmap`,
which shows the list and offers a menu for every change, and through `/aai-ship`,
which with no argument takes the next item on the list. Nobody edits the roadmap
file by hand and nobody has to type a script.

The pairing of every capability with one maintenance ride (the maintenance
budget) is now optional. Without it the roadmap only orders the work: fixes and
chores are admitted at any time and an out-of-order request is not refused. With
it, every capability is paired 1:1 with one maintenance ride and the ride gate
refuses a maintenance ride whose capability has not started. A project with no
roadmap at all behaves as it always did: nothing is ordered and nothing is
consulted.

The roadmap also keeps itself current. When a ride ships a new capability the
roadmap does not yet list, `/aai-ship` appends it and reports one line; during the
close ceremony, before the push, the finished item is marked done so the next `/aai-ship`
moves on.

A third, advisory posture sits between off and on: the roadmap proposes a
maintenance ride instead of requiring one. `/aai-ship` with no argument never
refuses for it; it only sometimes answers `propose_maintenance`, naming the
waiting items and the alternative it would otherwise have taken.

## Worked examples

### Off

No `budget:` block. `/aai-roadmap add` orders capabilities; `/aai-ship` with no
argument takes the next one; nothing is ever refused for being out of order.

### On

`/aai-roadmap budget` then pick `on`. Every capability is paired 1:1 with one
maintenance ride, and the gate refuses a maintenance ride whose capability has
not started.

### Advisory

`/aai-roadmap budget` then pick `advisory` and a threshold -- or accept the
recommended one `ride-select.mjs waiting` reports as `recommended_threshold`.
The roadmap gains `mode: advisory` and a `maintenance_threshold`; the gate
never refuses, but `/aai-ship` with no argument may answer
`propose_maintenance` once waiting maintenance reaches the threshold or
relates to the capability just closed -- a one-line menu offers riding it
first or continuing as planned.

## How to use it

Run `/aai-roadmap` to see the roadmap and pick an action from the menu. Each
question comes with a recommended default.

- `/aai-roadmap` or `/aai-roadmap show` prints the next item, what is done and
  what waits, and whether the maintenance budget is on, advisory or off.
- `/aai-roadmap add` puts a capability on the list (at the end by default);
  `/aai-roadmap reorder` moves one; `/aai-roadmap done` and `/aai-roadmap drop`
  finish or remove one.
- `/aai-roadmap harvest` ranks candidates from drafts and friction against one
  sentence of direction and lets you pick.
- `/aai-roadmap budget` picks the budget posture: on, advisory (with a
  threshold) or off. It is off unless you change it.
- `/aai-roadmap off` removes the roadmap after a confirmation that defaults to
  keeping it.
- `/aai-ship` with no argument takes the next roadmap item, or an advisory
  `propose_maintenance` menu when one is waiting.

The Roadmap section of the User Guide walks through four cases: no roadmap, a
roadmap without a budget, a roadmap with a budget, and a roadmap with an
advisory budget.

What the skill runs underneath: `ride-select.mjs show|waiting` and
`roadmap-edit.mjs` (`add`, `move`, `done`, `drop`, `budget`, `off`), plus
`roadmap-propose.mjs` for harvest. After a write the skill checks the result
with `ride-select.mjs validate` and puts the file back exactly as it was if
the check fails.

## Data model

The roadmap is one file, `docs/ai/roadmap.yaml`: an optional `budget:` block, a
`pairs:` list in build order (each entry a capability with a status of planned,
active or done, and optionally a bound maintenance ride), and an optional
`wave_2:` list of later ideas. The budget is switched on by the presence of the
`budget:` block with `maintenance_per_capability: 1`; leaving it out switches it
off. A `budget:` block carrying `mode: advisory` and a positive integer
`maintenance_threshold` instead switches it to advisory: the pairing stays
inactive (the gate behaves as off) and `next` only ever proposes. Maintenance
lines in a project that switches the budget off stay in the file, inactive, so
switching it on again loses nothing. No other file or record is introduced.

## Interfaces and contracts

- `/aai-roadmap [action]`: the skill; menu with a recommended default per
  question. Stable.
- `ride-select.mjs show [--json]`: read-only; prints the next item, done count,
  waiting items, wave 2 and the budget posture (on, advisory with its
  threshold, or off); `no roadmap` and exit 0 when there is none, exit 2 when
  the file is invalid. `next --json` gains a `path` field naming the document
  that resolves the next item, and under advisory may instead answer
  `propose_maintenance` (reason, waiting candidates, and the `alternative` it
  would otherwise have returned) without ever refusing.
- `ride-select.mjs waiting [--json]`: read-only, works in every posture; counts
  open P1/P2 follow-ups and open issue/techdebt intakes and reports
  `recommended_threshold`.
- `ride-select.mjs validate`: a roadmap with no `budget:` block, or an advisory
  `budget:` block (`mode: advisory` plus `maintenance_threshold`), is valid; an
  on `budget:` block must still carry `maintenance_per_capability: 1`.
- `ride-select.mjs gate`: without a budget, or under advisory, it admits
  maintenance and capability rides on or off the roadmap and still refuses a
  finished work item or one with no document; with the 1:1 budget on it
  behaves exactly as before.
- `roadmap-edit.mjs add|move|done|drop|budget on|budget advisory --threshold <n>|budget off|off --confirm|ship-append|advance`:
  exit 0 on success or a named no-op, 1 on a refusal with the file unchanged,
  2 on a usage error. `ship-append` and `advance` are run by `/aai-ship` and
  `/aai-pr`; they never turn a roadmap on by themselves.
- `roadmap-propose.mjs write` on a missing roadmap no longer creates a budget.

## Limits and non-goals

- Without a budget, an item taken out of order is admitted; a project that wants
  ranked refusals turns the budget on. A switch for strict order without the 1:1
  pairing is not provided.
- Appending a new capability is decided by the type of its intake document only;
  a fix filed as a change lands on the roadmap and is marked done at close.
- Someone who closes a work item by hand outside `/aai-pr` does not advance the
  roadmap; without a budget the next-item lookup skips finished work anyway, and
  with a budget `/aai-roadmap done` or the next `/aai-pr` closes the gap.
- Edits write plain line endings and are verified by the validator rather than
  preserved byte for byte inside a moved entry.
- The shipped close ceremony itself is unchanged; the roadmap advance is a
  separate step run beside it.

## Links

- Request: docs/issues/CHANGE-0201-roadmap-serves-downstream-projects.md
- Spec: docs/specs/SPEC-0202-spec-roadmap-serves-downstream-projects.md
- Validation evidence: docs/ai/tdd/spec-roadmap-serves-downstream-projects/
