---
id: downstream-rides-ask-no-governance-questions
type: change
number: 200
status: draft
capability: downstream-autopilot
user_visible: true
links:
  pr: []
  commits: []
---

# Downstream rides ask no roadmap or amendment sign-off questions

## Summary
- A project that vendors AAI and runs `/aai-intake` or `/aai-ship` is asked about two things it never opted into: a roadmap it does not have, and an owner sign-off on a post-freeze spec amendment.
- Make both autonomous by default so the only human gate on a downstream ride is the merge checkpoint, while a project that writes `docs/ai/roadmap.yaml` keeps the strict gate it opted into.

## Motivation / Business Value
- `.aai/AGENTS.md` operator contract rule 4 states that roadmap discipline is opt-in downstream: without `docs/ai/roadmap.yaml` the gate is not consulted. `.aai/scripts/ride-select.mjs` contradicts it: `loadRoadmap` returns `roadmap not readable` for an absent file and `gate` refuses (exit 1). `tests/skills/test-aai-ride-select.sh` TEST-005 asserts that refusal.
- `.aai/SKILL_SHIP.prompt.md` step 1a runs the gate unconditionally and STOPs on any non-zero exit, naming "an unreadable roadmap" as a stop reason. Every downstream `/aai-ship` therefore halts on step 1a and asks the owner for a roadmap or an `--override`.
- `.aai/system/AUTONOMOUS_LOOP.md` section 6a says a post-freeze amendment is a scope change that section 6 assigns to the owner. `.aai/SKILL_PR.prompt.md` amendment gate offers `--signoff owner|none`. A downstream agent reads both as an owner decision and asks the owner to sign, and open `fu-amend-*` items surface in every Planning tick as an owed sign-off.
- Both ceremonies serve the canonical repository's own governance. Downstream, they interrupt the autopilot the ship skill promises: intake in, validated code with tests and docs out, one question at the merge.

## Scope
- In scope:
  - `.aai/scripts/ride-select.mjs`: `gate` distinguishes an ABSENT roadmap (ENOENT) from an unreadable or invalid one. Absent admits with one note line; unreadable or invalid still refuses.
  - `tests/skills/test-aai-ride-select.sh`: flip TEST-005 to the new contract and add a fixture case for a project with no roadmap.
  - `.aai/SKILL_SHIP.prompt.md` step 1a: consult the gate only when the roadmap exists; record the skip in STATE as an autopilot default.
  - `.aai/system/AUTONOMOUS_LOOP.md` section 6a and `.aai/SKILL_PR.prompt.md` amendment gate: `--signoff none` is the autonomous default with no question to the owner; owed sign-offs are reported as one line in the merge checkpoint summary (SKILL_SHIP step 6).
  - A guard test that exercises the ship-flow gates in a fixture project with no roadmap and an amended spec and asserts zero human questions before the merge checkpoint.
  - An explicit posture statement so the canonical repository keeps its strictness: the roadmap file itself is the switch (present = governed, absent = autopilot), documented in AGENTS.md rule 4 and in the ride-select header.
- Out of scope: the roadmap shape, `roadmap-propose.mjs`, the `validate` and `next` subcommands, `spec-amend.mjs` record schema, the unattended run budget, and any change to merge authorization.

## Affected Area
- `.aai/scripts/ride-select.mjs`
- `.aai/SKILL_SHIP.prompt.md`
- `.aai/system/AUTONOMOUS_LOOP.md`
- `.aai/SKILL_PR.prompt.md`
- `.aai/AGENTS.md` operator contract rule 4
- `tests/skills/test-aai-ride-select.sh` and one new guard test under `tests/skills/`

## Desired Behavior (To-Be)
- In a project with no `docs/ai/roadmap.yaml`, `node .aai/scripts/ride-select.mjs gate --ref <id>` exits 0 and prints one line stating the roadmap is absent and the gate was not consulted. No file is created.
- In a project whose `docs/ai/roadmap.yaml` exists but cannot be read or does not fit the closed shape, `gate` exits 1 with the existing refusal. Present but invalid is a defect, not a choice.
- `/aai-ship` step 1a on a project with no roadmap records "roadmap absent, gate not consulted (autopilot default)" and continues to the loop. On a project with a roadmap the current behavior is unchanged.
- A post-freeze amendment during a ride is recorded with `spec-amend.mjs add --signoff none` without asking the owner. The ride continues. The PR amendment gate remedy text names `--signoff none` as the default and `--signoff owner` only when a real owner record exists.
- The merge checkpoint (SKILL_SHIP step 6) lists owed amendment sign-offs, when any exist, as one line naming the tracked item ids. It never asks the owner to sign before the PR is open.
- AGENTS.md rule 4 and the ride-select header agree: the presence of `docs/ai/roadmap.yaml` is the switch between governed and autopilot posture.

## Acceptance Criteria
- AC-001: `ride-select.mjs gate` on an absent roadmap path exits 0 and its stdout contains the word `absent`; no file is written at that path.
- AC-002: `ride-select.mjs gate` on a present but malformed roadmap exits 1 with the existing `REFUSED` line; `validate` and `next` on an absent roadmap keep their current behavior.
- AC-003: `tests/skills/test-aai-ride-select.sh` TEST-005 asserts the absent-roadmap ADMIT, and a new case asserts the malformed-roadmap REFUSE separately; the suite passes.
- AC-004: `.aai/SKILL_SHIP.prompt.md` step 1a states the gate is consulted only when `docs/ai/roadmap.yaml` exists and names the STATE rationale text for the skip.
- AC-005: `.aai/system/AUTONOMOUS_LOOP.md` 6a and `.aai/SKILL_PR.prompt.md` amendment gate state that `--signoff none` is the autonomous default and that no owner question is asked mid-ride; SKILL_SHIP step 6 lists owed sign-offs as one line.
- AC-006: A guard test under `tests/skills/` runs the ride gate and the amendment gate in a temporary fixture project with no roadmap and one unsigned amendment, and asserts both exit 0 with no prompt text (no `?`, no `AskUserQuestion`, no `owner must`) in their output.
- AC-007: `.aai/AGENTS.md` rule 4 and the `ride-select.mjs` header comment both state the roadmap file is the posture switch; the prompt-corpus governance checks (diet ledger, TEST-012 line budget, PROFILES classification) pass for every edited prompt.

## Verification
- `bash tests/skills/test-aai-ride-select.sh` passes.
- `bash tests/skills/<new guard test>.sh` passes.
- `node .aai/scripts/ride-select.mjs gate --ref x-y --roadmap /nonexistent.yaml --docs docs` exits 0.
- `env -u AAI_ROLE bash tests/skills/run-all.sh` (or the project's selected suites) passes for the touched surfaces.

## Constraints / Risks
- `ride-select.mjs` is `DENY BY DEFAULT` by design (SPEC-0168). Narrowing that to "present but invalid denies" must not admit a typo'd roadmap path in a governed project: the default path is fixed at `docs/ai/roadmap.yaml`, and `--roadmap` is only ever passed by tests.
- Prompt edits are governed: each edited `.aai/*.prompt.md` needs a diet-ledger entry and a TEST-012 line-budget check.
- No secret is referenced; secrets preflight skipped.
- The canonical repository has a roadmap, so this ride itself is off-roadmap and enters through an owner `--override` that is logged to EVENTS.

## Notes
- Owner direction 2026-10-01: "aai-intake and aai-ship are the entry points; everything else returns validated code, docs and tests autonomously; the owner is asked only at the merge."
- Reproduction in this repository: `node .aai/scripts/ride-select.mjs gate --ref CHANGE-0001 --roadmap /nonexistent/roadmap.yaml` prints `REFUSED — roadmap not readable` and exits 1.
- Autopilot default (SKILL_SHIP): intake metrics question skipped, human_time_minutes null.
- Implementation mode (autopilot recommendation): tdd — behavioral change on a core gate script plus vendored prompts.
