---
id: contract-prefix-order-unenforced
type: issue
number: 50
status: draft
---

# P2 backlog cluster: the-subagent-contract-omits-the-hazards (4 items)

## Summary
- Consolidated registry intake for 4 open P2 follow-up(s) filed against `the-subagent-contract-omits-the-hazards`: `fu-contract-prefix-order-unenforced`, `fu-usage-marker-omission-unfixable`, `fu-allowlist-count-is-prose-not-asserted`, `fu-empty-path-cd-stays-in-shipping-repo`. Filed via batch intake (owner directive: intake all P2 clusters first, ship the highest-value ones next).

## Type
- bug

## Current Behavior
- **`fu-contract-prefix-order-unenforced`**: the D1 cap argument rests on the CONTRACT being copied stable-first into the dispatch prefix, but that ordering lives only as prose in .aai/ORCHESTRATION_PARALLEL.prompt.md:142-143; no code assembles the payload and no test pins the ordering (SPEC-0110 TEST-033 compares the SPEC-0096 file-bytes hash, not the assembled prompt), and the Validation dispatch of this very scope shipped a POINTER to the CONTRACT instead of a copy
  - Measured: when the copy is omitted the hazards are strictly worse placed than before: they were previously unskippable dispatch prose and are now behind a Read the subagent may skip, and the cap was re-based 60->90 on a cost model that only holds when the copy is present
  - Source: .aai/ORCHESTRATION_PARALLEL.prompt.md:142-143; docs/specs/SPEC-0110-spec-cache-friendly-dispatch.md lines 48-53 and AC-002; .aai/scripts/lib/prompt-hash.mjs header; first-hand observation of the Validation dispatch payload for the-subagent-contract-omits-the-hazards on 2026-08-23

- **`fu-usage-marker-omission-unfixable`**: a run appended without a usage marker cannot be corrected: append-run only appends, STATE hand-edits are forbidden, and the only recovery is toggling usage_capture_gate off and back
  - Measured: hit for real closing this ride; the recovery requires disarming the gate to get past it, which is the carve-out shape this repo keeps removing, and the 2026-08-11 entry that first recorded this defect is itself malformed (no id, no severity) so it never appeared in any severity filter
  - Source: close-work-item REFUSED on the round-2 Validation run; dial toggled report-only and back, visible in the same commit

- **`fu-allowlist-count-is-prose-not-asserted`**: TEST-011's path/group count lives only in a log_pass string and a comment, so it goes stale silently on every merge that adds a group and no arm ever notices
  - Measured: measured three times in one day: 31 stale before my edit, 32 after it, 34 after merging main - each time the suite stayed GREEN while the number it printed was wrong. A count nothing asserts is decoration, and this one is printed as if it were evidence
  - Source: PR 280 after merging main: case groups 12, paths 34, printed 32/11

- **`fu-empty-path-cd-stays-in-shipping-repo`**: a bash local a=1 b=$a chain leaves the second variable empty, so a fixture path computed that way is empty and cd "" silently stays in the shipping repository
  - Measured: the 2026-08-22 recurrence of fu-subagent-probe-hits-real-repo existed only in commit prose and a validation report; HAZ-CD needs a scar that resolves for every reader, and the reflog-only commit it cited resolves for nobody but its author
  - Source: validator harness, 2026-08-22: the empty path produced a commit in the shipping tree, undone with reset --mixed

## Expected Behavior
- Each item's own Expected Behavior is scoped at Planning/implementation time from the measured decision text above — this intake's job is to make the cluster a numbered, trackable work item, not to pre-design the fix.

## Notes
- Registry ref: `the-subagent-contract-omits-the-hazards`. This intake may close some, all, or none of the member `fu-*` ids depending on what Planning finds still applies when work starts — do not assume every listed item survives triage unchanged (two sibling items in this same backlog were found already-fixed-but-not-closed today; check before implementing).
