---
id: spec-notes-content-and-merged-links
type: spec
number: 230
status: done
frozen_sha256: b02255d7f6ca343aeec9b8a314d99048d8e86bddb1c164b39bd04c685385175b
ceremony_level: 2
links:
  requirement: notes-content-and-merged-links
  rfc: null
  pr: []
  commits: []
---

# Notes content comparison and canonical merged PR links

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/ISSUE-0099-notes-content-and-merged-links.md
- Existing contract: docs/specs/SPEC-0229-spec-release-notes-gate.md (read only)
- Technology contract: docs/TECHNOLOGY.md

## Implementation strategy
- Strategy: loop
- Rationale: one bounded repair in an existing CLI plus regression assurance for an existing test predicate; observe targeted regressions on the pinned baseline, then implement and run all declared controls in one pass. No mutation-gate contract is introduced. No matching intake-sourced strategy is being overridden.
- Ceremony: L2 because the scope crosses the Git patch/notes seam and the committed frontmatter/test-verdict seam. No configured L3 protected path is touched.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: retain the previous ride unchanged and isolate this dependent repair.
- User decision: worktree
- Base ref: b2e4e620d253da7601f8e27fa0cf41fff264177e
- Worktree branch/path: parent-provided /private/tmp/aai-notes-content-and-merged-links-worktree
- Inline review scope: .aai/scripts/release-notes-gate.mjs tests/skills/test-aai-release-notes.sh tests/skills/test-aai-merge-cleanup.sh CHANGELOG.md and this ride's governance/evidence companions
- Code review: required; review the full base-to-result diff.

## Constitution deviations

None.

## Acceptance Criteria Mapping

| Requirement | Spec-AC | Verification | Observable |
| --- | --- | --- | --- |
| AC-001 | Spec-AC-01 | N, TEST-001..002 | cosmetic-only replacements refuse with exit 1 in staged and range modes |
| AC-002 | Spec-AC-02 | N, TEST-003..004 | substantive additions/edits pass with exit 0; existing negative controls continue to refuse |
| AC-003 | Spec-AC-03 | M, TEST-005..006 | inline and block PR links reach unsigned-merged rejection; negative and Git-error cases remain distinguished |

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
| --- | --- | --- | --- | --- | --- |
| Spec-AC-01 | WHEN a shipped diff changes existing unreleased notes only by trailing spaces/tabs or LF/CRLF endings the gate SHALL exit 1 without an explicit exemption, in both staged and merge-base/head modes | done | docs/ai/tdd/notes-content-and-merged-links-notes.log | — | TEST-001..002 |
| Spec-AC-02 | WHEN the compared diff adds or substantively edits visible note content the gate SHALL exit 0, including changed interior inline-code spacing, while preserving existing exemption, comment/code, entry, history and merge-base controls | done | docs/ai/tdd/notes-content-and-merged-links-notes.log | — | TEST-003..004 |
| Spec-AC-03 | WHEN the actual TEST-026 verdict receives an unsigned contract row for a done committed doc with nonempty inline or block-list links.pr it SHALL exit 1 naming unsigned merged amendments; valid unmerged/empty-link cases SHALL remain allowed and Git errors SHALL fail explicitly | done | docs/ai/tdd/notes-content-and-merged-links-merged.log | — | TEST-005..006 |

## Implementation plan

1. Extend the existing notes suite with real Git fixtures that stage a shipped change, neutral body, and an old titled note. Pin the defect before changing production. Exercise trailing spaces, trailing tabs, whole-file LF-to-CRLF and CRLF-to-LF with unchanged words. Commit each fixture and assert the same result through the actual base/head CLI.
2. Make note novelty depend on substantive compared content, rather than the mere presence of an added patch line. Compare with the correct preimage (HEAD for staged mode and the resolved merge base for range mode), or implement an equivalent patch comparison. Treat line terminators and trailing horizontal whitespace as cosmetic. Preserve interior characters and spacing, especially in inline-code spans; no blanket whitespace deletion/collapse. Cosmetic edits mixed with a genuinely new or changed note must still pass. The scope does not promise a general Markdown semantic-equivalence engine, duplicate-note deduplication policy, or arbitrary paragraph reflow analysis.
3. Keep target content sourced from the index/head blob. Preserve shipped classifier exports, explicit marker parser, matched/unmatched backticks and global comments, released-region boundaries, missing-history/body refusal, no text execution, and merge-base semantics. Any helper signature extension must remain compatible with current callers or update all actual callers within the allowed scope; no new module/profile entry.
4. Verify the existing TEST-026 merged predicate recognizes canonical `links.pr` values in frontmatter, including `pr: [465]` and `pr:` followed by an indented `- 465`. Use an existing parser only if its observed output matches this contract; otherwise a bounded frontmatter parser is sufficient. Do not match body text, an unrelated key or a following sibling key as a PR value. A valid negative result is distinct from unreadable Git history/blob errors. Preserve exact id/done checks and the repaired single Git object prefix. The bot's specific same-line-only diagnosis is disputed: Planning observed the current regex crossing the newline and capturing `- 465`. Do not change the predicate merely to agree with that report. Add the real-verdict controls first; change predicate logic only if an executable case demonstrates an actual violation of these bounded requirements, and name that root cause.
5. Exercise the real extracted verdict program in disposable committed Git repositories. Maintain the signed backlog controls and add inline/block-list positives plus empty/missing/null and non-done negatives. Errors must produce a named diagnostic, not silently classify as unmerged. All fixtures stay in the parent-dispatched absolute scratch location, never real source/STATE/ledgers.
6. Add one focused CHANGELOG entry; update only this ride's evidence and governance companions. No workflow, prompt, profile, remote setting, prior frozen doc, parent PR or release-finish edits.

## Seams and residual risks

- S1: Git index and commit-range patches/preimages enter the production CLI; TEST-001..004 assert its exit/message, not a mock parser result.
- S2: committed canonical frontmatter becomes the real extracted merge-cleanup verdict; TEST-005..006 assert the resulting unsigned-row decision and error diagnostic.
- Corpus: inspect the real root CHANGELOG against the revised comparison and representative canonical docs with both PR-list forms. Use an unchanged-content negative and a genuine-addition positive control; do not mutate the corpus. Record count and exact commands during Validation.
- Hosted CI/native Windows are separate environment evidence; a local run does not attest them. No new remote contract is introduced.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
| --- | --- | --- | --- | --- | --- | --- |
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-release-notes.sh | trailing-space/tab old-note replacements refuse both real CLI modes; explicit no-notes reason remains a positive control | restore added-line-only eligibility | green |
| TEST-002 | Spec-AC-01 | integration | tests/skills/test-aai-release-notes.sh | LF/CRLF-only whole-file changes refuse both modes, with shipped changes asserted present | compare raw line terminators as new note content | green |
| TEST-003 | Spec-AC-02 | integration | tests/skills/test-aai-release-notes.sh | new note, changed words, interior inline-code spacing, and mixed cosmetic plus new content pass in staged/range fixtures | strip all whitespace or reject every replacement | green |
| TEST-004 | Spec-AC-02 | regression | tests/skills/test-aai-release-notes.sh | existing classifier/exemption/body/history/comments/backticks/entry-boundary/merge-base controls remain green; staged read ignores unstaged companion edits | bypass contextual parsing or read working-tree notes | green |
| TEST-005 | Spec-AC-03 | integration | tests/skills/test-aai-merge-cleanup.sh | actual verdict rejects unsigned merged rows for inline and canonical block-list links.pr with >=300 signed controls | replace newline-tolerant whitespace with horizontal-only whitespace in PR lookup | green |
| TEST-006 | Spec-AC-03 | integration | tests/skills/test-aai-merge-cleanup.sh | missing/empty inline/empty block/null PR links, following sibling and body-only decoys, non-done or absent docs allow unmerged; unreadable ref/blob fails contextually | swallow Git lookup failures or treat sibling/body content as PR link | green |

## Verification

- N: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release-notes.sh` — suite exit 0, per-case expected CLI exits 0/1 as above.
- M: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-merge-cleanup.sh` — suite exit 0, both canonical merged controls demonstrably hit rejection, negative and error arms hit their named branches.
- Full independent L2 Validation follows the canonical role and repository suite-selection policy; targeted commands above define the direct regression evidence, not a waiver of normal validation.
- Evidence targets: docs/ai/tdd/notes-content-and-merged-links-notes.log and docs/ai/tdd/notes-content-and-merged-links-merged.log. Record TEST mappings, command, exit, fixture identity and source snapshot. RED observation of the new defect controls is required before repair; storing it at docs/ai/tdd/notes-content-and-merged-links-red.log is recommended, not a per-test mutation requirement. Existing regression controls may start green.

## Evidence contract

Loop strategy requires observed RED proof for newly added defect assertions, followed by per-TEST green evidence. The whitespace defect has parent-owned RED from `/private/tmp/aai-notes-whitespace-repro.mjs` (wrapped run: expected gate 1, actual 0; wrapper 1). The canonical block-list diagnosis remains disputed, with a Planning regex control returning `- 465`; TEST-005 is allowed to begin green because it preserves existing behavior, not manufacture a defect. Any predicate correction requires its own observed failing control before repair. No implementation/validation claim is made by Planning. Independent Validation produces one aai-outcome-v1 report binding this intake/spec and exact target snapshot; review returns independent spec-compliance and code-quality verdicts with explicit cannot_verify. Parent remains sole STATE writer. Append-only ledgers retain their base bytes.

Registry items closed by this scope: none.

Registry scan used `follow-ups.mjs list --status open --json`. Related changelog items fu-changelog-exit12-second-arm, fu-changelog-merge-gate-optin, fu-changelog-shape-third-statement, fu-claims-report-drops-root-annotation and fu-release-unlogged-pr-three-classes concern release/preamble/report wording outside notes novelty and remain open. fu-amend-spec-release-notes-gate concerns owner sign-off on the older spec and is not discharged by this new spec or its parser fix. Other merge-cleanup follow-ups concern production cleanup/signing/archival paths, not this local regression predicate, and remain outside scope.

Relevant replay: docs/knowledge/LEARNED.md requires real corpus-shaped fixtures and positive controls for absence claims; those rules drive S1/S2 and the canonical block-list fixture here. No general YAML framework or new governance machinery is proposed.
