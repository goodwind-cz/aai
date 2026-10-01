---
id: roadmap
type: product
capability: roadmap
status: current
delivered_by:
  - roadmap-serves-downstream-projects
spec: docs/specs/SPEC-DRAFT-spec-roadmap-serves-downstream-projects.md
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

## How to use it

Run `/aai-roadmap` to see the roadmap and pick an action from the menu. Each
question comes with a recommended default.

- `/aai-roadmap` or `/aai-roadmap show` prints the next item, what is done and
  what waits, and whether the maintenance budget is on or off.
- `/aai-roadmap add` puts a capability on the list (at the end by default);
  `/aai-roadmap reorder` moves one; `/aai-roadmap done` and `/aai-roadmap drop`
  finish or remove one.
- `/aai-roadmap harvest` ranks candidates from drafts and friction against one
  sentence of direction and lets you pick.
- `/aai-roadmap budget` turns the maintenance budget on or off. It is off unless
  you turn it on.
- `/aai-roadmap off` removes the roadmap after a confirmation that defaults to
  keeping it.
- `/aai-ship` with no argument takes the next roadmap item.

The Roadmap section of the User Guide walks through three cases: no roadmap, a
roadmap without a budget and a roadmap with a budget.

What the skill runs underneath: `ride-select.mjs show` and `roadmap-edit.mjs`
(`add`, `move`, `done`, `drop`, `budget`, `off`), plus `roadmap-propose.mjs` for
harvest. After a write the skill checks the result with `ride-select.mjs
validate` and puts the file back exactly as it was if the check fails.

## Data model

The roadmap is one file, `docs/ai/roadmap.yaml`: an optional `budget:` block, a
`pairs:` list in build order (each entry a capability with a status of planned,
active or done, and optionally a bound maintenance ride), and an optional
`wave_2:` list of later ideas. The budget is switched on by the presence of the
`budget:` block with `maintenance_per_capability: 1`; leaving it out switches it
off. Maintenance lines in a project that switches the budget off stay in the
file, inactive, so switching it on again loses nothing. No other file or record
is introduced.

## Interfaces and contracts

- `/aai-roadmap [action]`: the skill; menu with a recommended default per
  question. Stable.
- `ride-select.mjs show [--json]`: read-only; prints the next item, done count,
  waiting items, wave 2 and the budget posture; `no roadmap` and exit 0 when
  there is none, exit 2 when the file is invalid. `next --json` gains a `path`
  field naming the document that resolves the next item.
- `ride-select.mjs validate`: a roadmap with no `budget:` block is now valid; a
  `budget:` block that is present must still carry `maintenance_per_capability: 1`.
- `ride-select.mjs gate`: without a budget it admits maintenance and capability
  rides on or off the roadmap and still refuses a finished work item or one with
  no document; with a budget it behaves exactly as before.
- `roadmap-edit.mjs add|move|done|drop|budget on|budget off|off --confirm|ship-append|advance`:
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

- Request: docs/issues/CHANGE-DRAFT-roadmap-serves-downstream-projects.md
- Spec: docs/specs/SPEC-DRAFT-spec-roadmap-serves-downstream-projects.md
- Validation evidence: docs/ai/tdd/spec-roadmap-serves-downstream-projects/
