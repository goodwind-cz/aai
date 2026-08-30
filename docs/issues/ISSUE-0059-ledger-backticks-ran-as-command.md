---
id: ledger-backticks-ran-as-command
type: issue
number: 59
status: draft
---

# P2 backlog cluster: intake-numbers-some-doc-types-immediately (6 items)

## Summary
- Consolidated registry intake for 6 open P2 follow-up(s) filed against `intake-numbers-some-doc-types-immediately`: `fu-ledger-backticks-ran-as-command`, `fu-intake-dir-pin-is-set-not-opening`, `fu-intake-dir-unanchored-research-hotfix`, `fu-intake-table-parser-asymmetry`, `fu-intake-common-fallback-numbers-doc`, `fu-report-ids-exceed-registry-cap`. Filed via batch intake (owner directive: intake all P2 clusters first, ship the highest-value ones next).

## Type
- bug

## Current Behavior
- **`fu-ledger-backticks-ran-as-command`**: unescaped backticks inside a double-quoted bash string in tests/skills/lib/prompt-diet-ledger.sh ran as command substitution on every source, printing 'extra: command not found' to stderr and silently deleting the word from the ledger text
  - Measured: the ledger is the record justifying every prompt byte added to the repo, and it was quietly corrupting its own entries while emitting an error nobody read; found only because this ride happened to edit the same entry
  - Source: remediation of intake-numbers-some-doc-types-immediately, 2026-08-21; reproduced, then removed — no backtick remains in any JUSTIFIED_ADDITIONS entry

- **`fu-intake-dir-pin-is-set-not-opening`**: Spec-AC-02 and its AC-Status Evidence cell say every per-type prompt's OPENING directory line, but tests/skills/test-aai-intake.sh TEST-013 pins the file-wide SET of docs/<dir> mentions, which is also fence-blind and therefore brittle in the other direction
  - Measured: deleting the opening line and naming the directory only in a footnote stays green, so the pin does not defend D3's rationale that a prompt read in isolation must say where to write; and the first legitimate cross-reference or fenced example path added to any intake prompt reddens TEST-013 for a non-defect. Named fu-intake-dir-pin-is-set-not-opening-line in the round-2 report (41 chars, over the cap)
  - Source: validation round2 F6 mutation A5; docs/ai/reviews/review-20260821T074214Z-intake-numbers-some-doc-types-immediately.md NB-8 and cannot_verify 1

- **`fu-intake-dir-unanchored-research-hotfix`**: for the two intake types TYPE_MAP does not know (research, hotfix) the .aai/INTAKE_COMMON.md table row and the per-type prompt can drift together to a wrong directory with the whole intake suite green
  - Measured: TEST-013 pins prompt-to-table agreement, not correctness; moving the research row and INTAKE_RESEARCH's opening line both to docs/releases keeps rc 0. Adjacent to fu-typemap-missing-research-hotfix; fixing that closes this too. Named fu-intake-dir-unanchored-for-research-and-hotfix in the round-2 report (48 chars, over the 40-char id cap)
  - Source: docs/ai/validation/validation-20260821T072908Z-intake-numbers-some-doc-types-immediately-round2.md F5 mutation A4

- **`fu-intake-table-parser-asymmetry`**: tests/skills/test-aai-intake.sh intake_table_lines requires single-space table cells while the shipped parseIntakeTypeTable in .aai/scripts/docs-audit.mjs allows \s*, so a double-spaced ninth row is live in the gate and invisible to the arm that pins row count, prefix and directory
  - Measured: the two spellings are still not aligned; this remediation added a two-readings-agree cross-check to TEST-013 so the divergence is now DETECTED and named, but the underlying strictness asymmetry (and TEST-014's table-removal grep -v sharing the same single-space assumption) remains. Named fu-intake-table-parser-strictness-asymmetry in the round-2 report (43 chars, over the cap)
  - Source: validation round2 F8 mutation A7; review-20260821T074214Z NB-4

- **`fu-intake-common-fallback-numbers-doc`**: the legacy FALLBACK block in .aai/INTAKE_COMMON.md still instructs scan-and-mint of docs/<type>/<TYPE>-000N-<slug>.md, which is exactly the numbered filename the new --intake-file predicate rejects
  - Measured: the POST-SAVE escape hatch excuses only a MISSING docs-audit.mjs, not a missing allocator, so on an older AAI layer that has docs-audit.mjs but no allocator the role follows the fallback, writes a numbered file, then hits 'fix the FILENAME and re-run until both pass' with no reachable fixed point. Round-1 finding F5, neither fixed nor filed
  - Source: round-1 validation of intake-numbers-some-doc-types-immediately F5; review-20260821T074214Z NB-5 (.aai/INTAKE_COMMON.md:27)

- **`fu-report-ids-exceed-registry-cap`**: roles routinely write follow-up ids into their reports that the registry CLI refuses, because the ids exceed the hard 40-character cap, so a finding reported as filed can never have been filed under that name
  - Measured: four of six ids named in one round-2 report were refused with exit 2 when someone finally tried; this is a mechanical cause of the reported-as-filed pattern that has recurred four times in four days, and it is invisible because nobody runs the add command that would have failed
  - Source: remediation of intake-numbers-some-doc-types-immediately, 2026-08-21; the four were shortened and each shortened entry names its original long id verbatim

## Expected Behavior
- Each item's own Expected Behavior is scoped at Planning/implementation time from the measured decision text above — this intake's job is to make the cluster a numbered, trackable work item, not to pre-design the fix.

## Notes
- Registry ref: `intake-numbers-some-doc-types-immediately`. This intake may close some, all, or none of the member `fu-*` ids depending on what Planning finds still applies when work starts — do not assume every listed item survives triage unchanged (two sibling items in this same backlog were found already-fixed-but-not-closed today; check before implementing).
