---
id: roadmap-serves-downstream-projects
type: change
number: 201
status: done
capability: roadmap
user_visible: true
links:
  pr:
    - 419
  commits:
    - d1ed3a43ed5187e2e9fb42a5ec05e045257cb394
---

# The roadmap is an ordered capability list with an opt-in maintenance budget and its own skill

## Summary
- Rework `docs/ai/roadmap.yaml` so a downstream project can use it as what most projects want: an ordered list of capabilities to build. The 1:1 capability-to-maintenance pairing becomes an opt-in budget that this repository keeps.
- Give the roadmap a user-invocable skill, `/aai-roadmap`, with menu-driven actions instead of raw `node .aai/scripts/...` calls, and document when and how to use it.

## Motivation / Business Value
- The roadmap today does two jobs in one file: capability ORDER, and a maintenance BUDGET that was this repository's 2026-09-05 brake against fix-only drift (owner decisions capability-roadmap-drives-rides and maintenance-budget-one-to-one). Downstream projects inherit the brake whether they need it or not.
- `ride-select.mjs` hard-codes the brake: `budget.maintenance_per_capability` must be exactly 1; a capability-only pair never advances, because `next` insists on a `bind` after the capability is done; a fix not on the roadmap is refused, and "is this maintenance" is guessed from the intake type and words in the title.
- A project that wants only new capabilities in order has to hand-edit `status: done`, bind maintenance it does not want, or override the gate on every fix.
- No skill covers the roadmap and README/PLAYBOOK do not explain it. The only user path is `node .aai/scripts/ride-select.mjs` and `node .aai/scripts/roadmap-propose.mjs` with their flags.
- Owner direction 2026-10-01: users work through `/aai-intake` and `/aai-ship`; the roadmap must be usable without knowing scripts, and pairing must not be forced.

## Scope
- In scope:
  - Roadmap shape: `budget:` becomes OPTIONAL. Absent budget = unlimited maintenance: no pairing requirement, no bind proposals, fixes/chores/tests always admitted. Present `budget.maintenance_per_capability: 1` = today's behavior, unchanged (this repository keeps its file as is). The closed shape stays parseable; any new key is additive.
  - `ride-select.mjs` `gate`/`next`/`validate` follow the budget switch. Without a budget, `gate` admits maintenance rides and admits a capability that is not yet on the roadmap (see the append rule below); with a budget, today's refusals stay.
  - Roadmap advance on delivery: closing a work item whose ref is a roadmap capability marks that pair `done` (and with a budget, the pair is done only when both halves are done, as today). This must not require a hand edit.
  - `/aai-roadmap` skill (`.claude/skills/aai-roadmap/SKILL.md` + `.aai/SKILL_ROADMAP.prompt.md`, registered like other skills): actions `show`, `add <capability> [--at <n>]`, `reorder`, `harvest "<direction>"`, `done <ref>`, `drop <ref>`, `budget on|off`, `off` (delete the file = back to autopilot posture). Every action is a menu with a recommended default; every write goes through a deterministic script and is validated by `ride-select.mjs validate`.
  - `/aai-ship` integration: with no argument and a roadmap present, ship takes the next roadmap item (`ride-select.mjs next`); with an argument that is a new capability not on the roadmap and no budget, ship appends it to the roadmap with one reported line instead of refusing.
  - Documentation: "Roadmap: when and how" section in `docs/USER_GUIDE.md` and a short pointer in `README.md`, with worked examples without a roadmap, with a roadmap and no budget, and with a budget; `docs/product/roadmap.md`; AGENTS.md operator contract rule 4 restated (roadmap = order; budget = opt-in).
- Out of scope: changing this repository's roadmap content or its budget; merge authorization; the unattended run budget; renaming existing scripts; a GUI.

## Affected Area
- `.aai/scripts/ride-select.mjs`, `.aai/scripts/roadmap-propose.mjs`, the dispatch twin in `.aai/scripts/orchestration-dispatch.mjs`, `.aai/scripts/nothing-left-behind.mjs` (reads roadmap pairs), the close path (`close-work-item.mjs` or a sibling invoked from SKILL_PR step 4c)
- `.aai/SKILL_SHIP.prompt.md`, `.aai/SKILL_LOOP.prompt.md`, `.aai/AGENTS.md`, new `.aai/SKILL_ROADMAP.prompt.md`, new `.claude/skills/aai-roadmap/SKILL.md`, `.aai/system/PROFILES.yaml`
- `docs/USER_GUIDE.md`, `README.md`, new `docs/product/roadmap.md`
- Tests under `tests/skills/` (ride-select, roadmap-propose, close ceremony, new skill suite), suite-map, prompt-diet ledger

## Desired Behavior (To-Be)
- Without `docs/ai/roadmap.yaml`: unchanged from CHANGE-0200 (gate admits, not consulted).
- With a roadmap and no `budget:` block:
  - `/aai-ship` with no argument starts the first unfinished capability; with an argument it rides that need. A new capability not yet on the roadmap is appended at the end and the ride proceeds; ship reports one line `roadmap: appended <ref>`.
  - Fix, chore, test, CI and techdebt rides are always admitted.
  - When the capability's work item closes, its roadmap entry becomes `done` and `next` moves to the following entry. `next` never proposes `bind`.
- With a roadmap and `budget.maintenance_per_capability: 1`: today's behavior byte-for-byte (pair order, 1:1 maintenance, bind proposals, off-roadmap refusals, `--override`).
- `/aai-roadmap` with no action shows the roadmap in plain language (next item, done, planned, wave 2, budget on/off) and offers a menu of actions. No action requires the user to type a `node` command.

## Acceptance Criteria
- AC-001: `ride-select.mjs validate` accepts a roadmap with no `budget:` block and accepts this repository's current roadmap unchanged; any other budget value than 1 is still invalid when the block is present.
- AC-002: Without a budget, `gate` admits a maintenance ref that is not on the roadmap and admits a capability ref that is not on the roadmap; with a budget, both refusals behave as today (existing ride-select suite stays green unmodified except where a test asserted the no-budget refusal).
- AC-003: Without a budget, `next` never returns `action: bind`; a done capability-only pair advances to the next pair.
- AC-004: Closing a work item whose primary ref is a roadmap capability flips that pair to `status: done` through a deterministic script, validated by `ride-select.mjs validate`, with the edit committed in the close commit; with a budget, a pair whose maintenance half is open stays open.
- AC-005: `/aai-roadmap` exists as a user-invocable skill, is registered wherever existing skills are registered (skill dir, PROFILES, harness skill sync, suite-map), and each action maps to one deterministic script call that refuses invalid input and leaves the file byte-identical on refusal.
- AC-006: SKILL_SHIP states the no-argument behavior (next roadmap item) and the append-on-new-capability behavior without a budget; a fixture test proves the append writes a valid roadmap.
- AC-007: `docs/USER_GUIDE.md` carries a "Roadmap: when and how" section with the three worked examples; README points to it; `docs/product/roadmap.md` passes the product-doc gate; AGENTS.md rule 4 states roadmap = order, budget = opt-in.
- AC-008: Prompt-corpus governance holds: diet-ledger credit for measured growth, TEST-012 pin, PROFILES classification of every new vendored file, ORCHESTRATION untouched.

## Verification
- `env -u AAI_ROLE bash tests/skills/test-aai-ride-select.sh` and the roadmap-propose suite exit 0.
- New suite for `/aai-roadmap` and the no-budget fixture project exits 0.
- `node .aai/scripts/ride-select.mjs validate` exits 0 on this repository's roadmap.
- Full sweep once before close.

## Constraints / Risks
- `close-work-item.mjs` is hash-pinned by several suites (one byte reddens four suites); prefer a sibling script invoked by the close ceremony, or batch every edit to that file and re-pin last.
- Backward compatibility: this repository's roadmap and its gate behavior must not change; the no-budget path must be a strict addition.
- Appending to the roadmap from `/aai-ship` is a write to a governed file; it must be deterministic, validated, and visible in the PR diff.
- No secret is referenced; secrets preflight skipped.
- This repository has a roadmap with a budget, so this ride itself enters through an owner `--override`, logged to EVENTS.

## Notes
- Owner direction 2026-10-01 (session after PR #416): "shouldn't the roadmap have a skill, users won't call node; what if I want no maintenance, only new capabilities; think about the whole concept".
- Autopilot default (SKILL_SHIP): intake metrics question skipped, human_time_minutes null.
- Implementation mode (autopilot recommendation): tdd — behavioral change on a core gate script, a new skill and the close path.
