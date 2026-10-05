---
id: roadmap-maintenance-budget-advisory
type: change
number: 203
status: draft
links:
  pr: []
  commits: []
---

# Change Request: Advisory maintenance budget on the roadmap

Frontmatter status values: draft | implementing | done | deferred | rejected | superseded

## Summary
- Add a third roadmap budget posture between "on" (mandatory 1:1 maintenance) and "off" (no maintenance at all): `advisory`. Maintenance is never required, but `ride-select next` proposes a maintenance ride on its own when enough maintenance is waiting, or when open problems relate to the capability just delivered.

## Motivation / Business Value
- Today `docs/ai/roadmap.yaml` has two postures (CHANGE-0201): a `budget:` block with `maintenance_per_capability: 1` makes every capability wait for a bound maintenance half, and no block makes maintenance invisible to `next`. Any other value is rejected by `ride-select.mjs validate`.
- The mandatory posture blocked PR #430: a delivered capability could not be marked done until a maintenance item was bound, although the owner did not want one at that moment. The owner switched this repository to "off" on 2026-10-05 for that reason.
- "Off" loses the useful half of the brake: nobody is reminded that maintenance is piling up, or that the capability just delivered left follow-ups behind (PR #430 left four).
- Owner direction 2026-10-05: maintenance should be optional and only proposed when there is a lot of it waiting, or when it is relevant.

## Scope
- In scope:
  - Roadmap shape: `budget.mode: advisory` with `budget.maintenance_threshold: <n>`. The existing `maintenance_per_capability: 1` form stays valid and means `on`; an absent block stays `off`.
  - `ride-select.mjs next` in advisory mode: proposes a maintenance ride when the waiting count reaches the threshold, or when open follow-ups reference the capability that was just closed; otherwise returns the next capability as in `off`.
  - `ride-select.mjs gate` in advisory mode behaves exactly like `off` (never refuses on budget grounds).
  - `/aai-roadmap budget` offers `on | advisory | off`; `roadmap-edit.mjs budget advisory --threshold <n>`.
  - `/aai-ship` with no argument relays an advisory proposal as a menu: take the proposed maintenance ride (recommended when the trigger fired) or continue with the next capability.
- Out of scope: changing what counts as a capability; automatic binding; the merge policy.

## Affected Area
- `.aai/scripts/ride-select.mjs`, `.aai/scripts/roadmap-edit.mjs`, `.aai/scripts/lib/roadmap-model.mjs`, `.aai/scripts/follow-ups.mjs` (read-only count), `.aai/SKILL_ROADMAP.prompt.md`, `.aai/SKILL_SHIP.prompt.md`, `docs/product/roadmap.md`, `docs/USER_GUIDE.md`, `tests/skills/test-aai-ride-select.sh`, `tests/skills/test-aai-roadmap.sh`.

## Desired Behavior (To-Be)
- `budget: { mode: advisory, maintenance_threshold: 5 }` validates; a missing or non-positive threshold is invalid.
- "Waiting maintenance" counts open P1/P2 follow-ups plus open (not done, not deferred) DEBT and ISSUE intakes; P3 follow-ups do not count, so a large low-severity backlog does not fire the proposal on every call.
- "Relevant" means at least one open follow-up whose `ref` equals the capability that was closed most recently.
- When either trigger fires, `next --json` returns `{"action":"propose_maintenance", "reason":"threshold|related", "candidates":[...]}` with the highest-severity candidates first, plus the next capability as the alternative; it never returns `bind` and never blocks.
- When neither fires, `next` returns the next capability, as in `off`.

## Acceptance Criteria
- AC-001: `ride-select.mjs validate` accepts `mode: advisory` with a positive integer `maintenance_threshold` and rejects advisory without a threshold, a non-integer threshold, and an unknown mode; the existing `maintenance_per_capability: 1` form and the absent block validate unchanged.
- AC-002: In advisory mode `gate` admits every ref `off` admits and refuses every ref `off` refuses (same fixture set, byte-identical verdict lines).
- AC-003: In advisory mode `next` returns `propose_maintenance` with `reason=threshold` when waiting maintenance reaches the threshold, `reason=related` when an open follow-up references the most recently closed capability, and the next capability otherwise; P3 follow-ups never count toward the threshold.
- AC-004: `roadmap-edit.mjs budget advisory --threshold <n>` writes a valid file and refuses invalid input with the file byte-identical; `/aai-roadmap budget` offers the three postures as a menu.
- AC-005: SKILL_SHIP relays an advisory proposal as a menu without asking any other question; prompt-corpus governance holds (diet ledger, TEST-012 pin, PROFILES).
- AC-006: `docs/product/roadmap.md` and the USER_GUIDE roadmap section describe the three postures with a worked example each.

## Verification
- `tests/skills/test-aai-ride-select.sh` and `tests/skills/test-aai-roadmap.sh` fixtures for each AC, mutation-gated.

## Constraints / Risks
- Counting must be cheap and deterministic (no network); it reads the follow-up ledger and the docs tree.
- A threshold that is too low turns advisory into nagging; the default proposed by `/aai-roadmap` should be measured against this repository's backlog (P1/P2 count) before it is chosen.

## Notes
- Origin: PR #430 (configurable-merge-policy-lanes) was blocked by the mandatory 1:1 budget; the owner switched this repository to `off` on 2026-10-05 and asked for this middle posture.
