---
id: single-writer-canon-contradiction
type: change
number: 165
status: draft
links:
  pr: []
  commits: []
---

# Resolve the single-writer canon contradiction and arm the serial R-GUARD

## Summary
- The single-writer rule for `docs/ai/STATE.yaml` is stated in two mutually
  contradictory ways, and the CLI guard that should enforce it never fires on
  the serial pipeline — the pipeline every real ride uses.
- `SUBAGENT_CONTRACT.md` (RFC-0004 / SPEC-0004 D7) declares: a dispatched
  subagent MUST NOT write STATE; it returns a result block and the orchestrator
  is the SOLE writer. `state.mjs` enforces this via R-GUARD S1 (SPEC-0113):
  every STATE mutator exits 3 when `AAI_ROLE=subagent` is set.
- Yet the serial role prompts direct the dispatched role to run the mutations
  itself: PLANNING step 12 (`set-focus`/`set-phase`/`set-strategy`/
  `set-worktree`/`set-code-review`), IMPLEMENTATION step 10, VALIDATION step 9,
  REMEDIATION (`reset-block`/`set-phase`) — with no mention of the result-block
  alternative.
- And unlike `ORCHESTRATION_PARALLEL.prompt.md` (line ~144) and the
  `SUBAGENT_PROTOCOL.md` ENV row, the serial `ORCHESTRATION.prompt.md` dispatch
  instructions never require exporting `AAI_ROLE=subagent` into the payload —
  so on serial rides the guard is structurally unarmed.

## Motivation / Business Value
- Observed bite (registry `fu-subagent-state-write-contradiction`, P2): on one
  ride Planning raised the contradiction unprompted and Validation declared it
  as a formal deviation — two roles independently lost time to canon that
  disagrees with itself in writing.
- A guard that only fires when an env var happens to be set is a false
  assurance: the written enforcement story ("enforced at the CLI chokepoint,
  not merely in prose" — SUBAGENT_PROTOCOL ENV row) is currently untrue for
  the serial pipeline.
- The registry policy after CHANGE-0161 files only what bites or lies; this
  item does both.

## Scope
- In scope: deciding the single truth; aligning all six prose surfaces
  (`SUBAGENT_CONTRACT.md`, `SUBAGENT_PROTOCOL.md`, `ORCHESTRATION.prompt.md`
  dispatch instructions, `PLANNING.prompt.md`, `IMPLEMENTATION.prompt.md`,
  `VALIDATION.prompt.md`, `REMEDIATION.prompt.md` state-update steps); a test
  that pins the alignment so the contradiction cannot silently return.
- Out of scope: any change to `state.mjs` / `lib/state-engine.mjs` /
  `lib/state-core.mjs` (protected_paths_l3; R-GUARD S1 already exists and is
  correct — the defect is that nothing arms it serially); any change to the
  parallel pipeline's semantics (it is already internally consistent); any
  reworking of the result-block schema.

## Affected Area
- AAI workflow canon: subagent contract, subagent protocol, serial
  orchestration dispatch, four role prompts, skill test suite.

## Desired Behavior (To-Be)
- Exactly one normative statement of who executes `state.mjs` STATE mutations
  on the serial pipeline, stated in one canonical place; every other surface
  is consistent with it (restating is acceptable only where it cannot drift —
  otherwise refer).
- Whichever side is chosen, the serial dispatch and the guard agree with the
  prose: either (a) sole-writer holds — serial dispatch payloads must carry
  `AAI_ROLE=subagent`, and the role prompts' state-update steps say "as a
  dispatched subagent, return these commands in the result block; the
  orchestrator executes them" — or (b) the serial path is a named carve in the
  contract, and the guard/protocol text stops claiming chokepoint enforcement
  it does not deliver. Planning decides which truth wins and records why.
- A suite test fails if a role prompt directs a dispatched subagent to mutate
  STATE while the contract forbids it, or if the serial dispatch instructions
  lack the arming line the decision requires.

## Acceptance Criteria
- AC-001: A grep of the seven surfaces finds no statement contradicting the
  chosen rule: no surface simultaneously forbids and directs direct subagent
  STATE mutation for the serial pipeline.
- AC-002: The serial `ORCHESTRATION.prompt.md` dispatch instructions and the
  `SUBAGENT_PROTOCOL.md` ENV row agree on when `AAI_ROLE=subagent` must be
  exported, and the role prompts' state-update steps are executable as written
  under that setting (no step a compliant subagent cannot perform).
- AC-003: A new or extended skill-suite test pins the alignment and fails on
  reintroduction of the contradiction (bite-proved both directions during
  implementation: shown red against the pre-fix text, green after).
- AC-004: Prompt-diet accounting holds: corpus delta of `.aai/*.prompt.md` is
  measured under `/usr/bin/grep`-safe conditions and ledgered at the measured
  amount; TEST-010 and TEST-012 pass in the full suite.
- AC-005: The registry item `fu-subagent-state-write-contradiction` is closed
  with `resolved_by` pointing at this change, only after the fix is merged.

## Verification
- `bash tests/skills/test-framework.sh` — full sweep green, including the new
  pin test and the prompt-diet gates.
- Manual read of the seven surfaces confirms one truth, no contradiction.

## Constraints / Risks
- Prompt-diet headroom is 0/2048: every added byte in `.aai/*.prompt.md` costs
  a full ledger entry. `SUBAGENT_CONTRACT.md` and `SUBAGENT_PROTOCOL.md` are
  outside the corpus glob — prefer carrying normative text there, and keep the
  in-corpus deltas minimal (ideally net-negative by absorbing the restatements
  this change removes).
- ORCHESTRATION.prompt.md is capped at 40 lines (governance checklist).
- protected_paths_l3 includes WORKFLOW.md — if alignment turns out to require
  touching it, that edit needs explicit owner sign-off first; the intake
  assumption is that it does not.
- Risk: option (a) changes the operational habit of every serial ride (roles
  stop running state.mjs themselves); the orchestrator must actually execute
  the returned commands, or phases stop advancing. The pin test cannot verify
  runtime behavior — only the prose alignment; runtime regression would
  surface as stuck phases on the next ride.
- No secrets referenced (SECRETS PREFLIGHT skipped).

## Notes
- Registry: `fu-subagent-state-write-contradiction` (P2, ref
  deslop-scope-and-unrequested-engine).
- Precedent: CHANGE-0164 resolved the AC-flip canon contradiction through this
  same route (decide one truth, align surfaces, pin with a test).
- Related but distinct: the parallel pipeline already carries the arming line
  and the sole-writer merge protocol; nothing there changes.
