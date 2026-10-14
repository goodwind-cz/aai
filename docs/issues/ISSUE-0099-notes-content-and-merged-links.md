---
id: notes-content-and-merged-links
type: issue
number: 99
status: done
links:
  pr: []
  commits: []
---

# Issue: distinguish new notes and pin merged PR link handling

## Summary
Repair a reproduced notes-content defect remaining after PR 465: cosmetic replacements of old notes satisfy the release-notes gate. Separately verify the disputed claim that the merged-ride regression guard overlooks canonical block-list PR links. This is a separate focused ride after the previous scope reached its review-round cap. Release preparation depends on this repair.

## Type
bug

## Impact
Priority P2. Shipped changes can bypass the new-notes requirement without new note content. Separately, TEST-026 models only inline PR links; add canonical block-list assurance without assuming the predicate is broken.

## Current Behavior
`hasAddedNotes` accepts a nonempty added patch line even when it replaces the same old note with trailing spaces or changes only CRLF/LF endings. The external report says `rideMerged` requires a same-line PR value, but inspection and a Planning regex probe show `\s*` crossing the newline and capturing `- 465` from a canonical block list. That diagnosis is disputed; actual-verdict regression coverage will determine whether any predicate repair is justified. The already repaired Git object-prefix lookup and fail-closed lookup error behavior must remain intact.

## Expected Behavior
- AC-001: A shipped change with only cosmetic trailing-space/tab or LF/CRLF replacements of existing note content refuses in both staged and base/head modes unless an explicit nonempty no-notes reason exists.
- AC-002: Truly new note text and substantive edits, including changed interior whitespace within inline code, still pass. Preserve all existing shipped classifier, comment/backtick, merge-base, body-data and entry-boundary behavior.
- AC-003: The actual merged-ride verdict rejects an unsigned contract row for a done document with a nonempty `links.pr` list in either inline or block form. Empty/missing/null links, unrelated body text and unmerged documents remain negative; Git lookup errors remain explicit failures.

## Steps to Reproduce (if applicable)
1. In a disposable Git repository commit a shipped file and a titled unreleased entry with `- Existing note.`.
2. Stage a shipped change and replace that note only with `- Existing note. `, or convert the unchanged changelog to CRLF. Run the current gate with a neutral body: it accepts incorrectly. Commit and repeat via base/head.
3. In the merge-cleanup suite's existing TEST-026 predicate fixture, represent a done merged document with `links:` then `  pr:` then `    - 465`. Feed an unsigned-tracked row alongside the 300 signed controls. Assert that the actual predicate rejects the row; this is a preservation control, not an assumed RED.

## Verification
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release-notes.sh`: negative cosmetic cases and substantive positive cases must match the expected gate exits in both modes.
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-merge-cleanup.sh`: actual extracted verdict must reject canonical inline and block-list unsigned merged cases while preserving negative and Git-error controls.
- RED observations first, then green per-test evidence and independent validation; no implementation is claimed by this intake.

## Constraints / Risks
Node stdlib only and bash 3.2-compatible tests. Limit implementation to the gate and two existing suites with normal governance/evidence/CHANGELOG companions. Do not strip all whitespace indiscriminately: inline code may carry meaningful spacing. Do not edit workflow, prompts, profiles, older scope docs, parent PR or release-finish. No secret is referenced. No remote mutation is part of this scope.

## Notes
- Source: https://github.com/goodwind-cz/aai/pull/465#discussion_r4269660260
- Source: https://github.com/goodwind-cz/aai/pull/465#discussion_r4269660273
- Both comment bodies were retrieved read-only during Planning on 2026-10-14.
- Parent executed `/private/tmp/aai-notes-whitespace-repro.mjs` through the canonical wrapper: staged gate expected exit 1, actual exit 0 with PASS; wrapper exited 1 as RED. Planning read the reproducer source; this is parent-owned observed evidence, not a Planning test execution.
- Planning regex probe for block-list PR links produced `match: - 465, nonempty: true`; no claim is made yet about the complete extracted verdict in that case.
- Scope and loop strategy derive from the explicit remediation dispatch; no new capability or user decision is pending.
