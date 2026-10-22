---
id: slim-standing-role-context
type: change
number: null
status: draft
links:
  pr: []
  commits: []
---

# Change: Slim the standing role context (LEARNED.md first)

Frontmatter status values: draft | implementing | done | deferred | rejected | superseded

## Summary
- Stop loading the whole `docs/knowledge/LEARNED.md` into every role dispatch.
  Keep the mandatory hazards always loaded; load incident narratives and
  history only when they are relevant to the task, or move them to an
  on-demand file.
- First child of RFC-0017 (smaller Node core and faster feedback), phase 4,
  first in the owner-approved order of 2026-10-22.

## Motivation / Business Value
- `canon.mjs build --role Validation --ref HEAD` measured 59,764 bytes on
  2026-10-22 (main `01de2119`). `LEARNED.md` is 27,638 bytes of that, about 46%.
  Other roles: Implementation 45,303 B, Planning 46,570 B, Remediation 40,188 B.
- Every dispatch pays for this prefix. Most of `LEARNED.md` is undated
  `## Session …` running logs and incident narratives, not active rules.
- Smaller standing context means fewer input tokens per ride and less noise
  for the agent, in this repository and downstream.

## Scope
- In scope:
  - A split of `LEARNED.md` content into an always-loaded part (mandatory
    hazards and active rules) and an on-demand part (incident narratives,
    session logs, history), with no lesson deleted.
  - The canon/prompt assembly change that loads only the always-loaded part,
    and a defined way for a role to reach the on-demand part when relevant.
  - Keeping the effective-prompt-hash telemetry (`canon.mjs` and
    `.aai/scripts/lib/prompt-hash.mjs`) consistent with what is actually
    assembled.
  - Downstream behavior: a downstream project's own `LEARNED.md`, unsplit,
    keeps working unchanged (back-compatible); the split is opt-in by layout.
  - Before/after measurement of all four role prefixes.
- Out of scope:
  - Slimming role prompts, `SUBAGENT_CONTRACT.md` or other canon inputs
    (later RFC-0017 phase 4 slices).
  - Provider adapter generation.
  - Rewriting the content or judgement of existing lessons beyond moving them.

## Affected Area
- `docs/knowledge/LEARNED.md` (and any new on-demand file next to it).
- `.aai/scripts/canon.mjs` build and its manifest; `.aai/scripts/lib/prompt-hash.mjs`.
- Lints that read `LEARNED.md` (`tests/skills/lib/learned-guard-lints.mjs`,
  `tests/skills/test-aai-hygiene-pack.sh`) and the wrap-up skill that appends lessons.
- Downstream sync/template if the vendored layer ships a LEARNED template.

## Desired Behavior (To-Be)
- The Validation prefix built by `canon.mjs build --role Validation --ref HEAD`
  is at least 50% smaller than 59,764 bytes, measured on the same tree shape.
- Every mandatory hazard that is loaded today is still loaded in every role.
- A lesson is never lost: everything moved out of the always-loaded part
  remains in the repository and reachable by a documented path.
- New lessons from `/aai-wrap-up` land in the right part by a stated rule.
- A downstream project with a single, unsplit `LEARNED.md` sees no change in
  behavior.

## Acceptance Criteria
- AC-001: The Validation prefix measured by `canon.mjs build --role Validation --ref HEAD` is at most 29,882 bytes (50% of the 59,764-byte baseline), and the other three roles shrink by the same moved byte count.
- AC-002: A deterministic check proves every always-loaded hazard entry present before the change is present in the always-loaded part after it (no silent drop).
- AC-003: Every byte of lesson text removed from the always-loaded part exists in the on-demand part (lessons moved, not deleted), checked by a test.
- AC-004: The effective-prompt-hash computed by `canon.mjs` and by `prompt-hash.mjs` still agree on one tree and still cover exactly what is assembled (TEST-682/683 class).
- AC-005: A fixture downstream project with a single unsplit `LEARNED.md` builds the same prefix as before the change.
- AC-006: Roles have a documented, deterministic way to read the on-demand part when a task touches its subject.

## Verification
- Command(s) and expected results:
  - `node .aai/scripts/canon.mjs build --role <R> --ref HEAD | wc -c` for all four roles, before and after.
  - The affected skill suites (canon, prompt-hash, hygiene pack, sync seed) pass.

## Constraints / Risks
- Risk: an always-needed hazard moved to the on-demand part stops being
  applied. Mitigation: AC-002 and an explicit classification rule.
- Risk: prompt-corpus governance (diet ledger, TEST-012 pins) and frozen hash
  pins move with the canon change; budget for re-pins.
- Risk: downstream projects vendor this layer; the change must not require
  them to restructure their own `LEARNED.md`.
- No secret is referenced.

## Notes
- Parent: [RFC-0017](../rfc/RFC-0017-smaller-node-core-and-faster-feedback.md), owner decisions of 2026-10-22, order item 1.
- Assumption: Planning chooses the split mechanism (section marker in one
  file, or a second on-demand file); either satisfies the ACs.
- Human intake time: not asked (autopilot `/aai-ship`), recorded as null.
