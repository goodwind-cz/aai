---
id: closeout-display-id-match
number: 56
type: change
status: draft
links:
  spec: null
  pr: []
  commits: []
---

# Closeout candidate: display-id match + Rollout-Status guard

## Summary
- `closeoutCandidatesFor` (docs-audit's "this umbrella's specs are all done →
  suggest closing it" pass) had the SAME latent bug CHANGE-0055 fixed for the
  rollup: it matched a child's reverse `links.rfc`/`links.requirement` against the
  parent's SLUG `id` only, while children link by the numbered DISPLAY id — so for a
  real RFC (slug id) it silently resolved NO children and never fired. Now matched
  on slug id OR display id (and byId keyed on both), like the rollup.
- Fixing the match alone would over-fire: an umbrella whose LINKED specs are all
  done but whose roadmap still has un-spec'd phases (RFC-0012 phases 3-5) would be
  wrongly suggested for close. So closeout now SKIPS any parent whose body declares
  a `## Rollout Status` roadmap with a not-`done` phase row — the human roadmap says
  there is unfinished work beyond the linked specs.

## Type
- change (docs-audit engine; report-only surface; correctness + false-positive guard)

## Motivation / Business Value
- Surfaced while building CHANGE-0055: closeout silently never fired for real
  slug-id umbrellas (it only worked on fixtures that used the display id AS the
  frontmatter id). Fixing it makes the close suggestion actually reachable, and the
  Rollout guard keeps it from firing prematurely on a part-done umbrella.

## Scope
- In scope:
  - `.aai/scripts/lib/docs-audit-core.mjs`: `closeoutCandidatesFor` matches on slug
    id OR display id (byId keyed on both; reverse-link `parentRefs` check; output +
    suggestedStep report the display id). New `hasUnfinishedRolloutPhases(content)`
    helper (locates the `## Rollout Status` "Status" column by header name, robust
    to column order) + a `rolloutUnfinished` flag on each scanned doc record;
    closeout skips a parent when it is set.
  - `tests/skills/test-aai-docs-audit.sh`: two closeout tests (slug-id parent with a
    display-id reverse link is flagged; an all-specs-done umbrella with a not-started
    Rollout phase is NOT flagged), both RED-proofed.
- Out of scope:
  - The rollup (CHANGE-0055, already shipped). No change to hard-fail / exit-code
    behavior — closeout stays report-only.

## Desired Behavior (To-Be)
- On the real repo, closeout now suggests closing RFC-0013 (all its work done, no
  pending Rollout phase) and correctly WITHHOLDS RFC-0012 (Rollout Status shows
  phases 3-5 not started), where before it fired on neither.
- `hasUnfinishedRolloutPhases` returns true iff a `## Rollout Status` table has a
  row whose Status is non-empty and not `done`.

## Acceptance Criteria
- AC-001: a non-terminal rfc parent with a SLUG frontmatter id whose done spec
  reverse-links it by DISPLAY id is flagged as a closeout candidate (the display id
  named in the suggestion). Deterministic fixture test, RED without the match fix.
- AC-002: a parent whose linked specs are ALL done but whose body has a
  `## Rollout Status` row with a not-started phase is NOT flagged; a roadmap-free
  all-done parent still IS (positive control). Deterministic fixture test, RED
  without the guard.
- AC-003: closeout stays report-only (verdict/exit unaffected); the full
  `test-aai-docs-audit.sh` + close-work-item + doc-numbering suites stay green.

## Verification
- `bash tests/skills/test-aai-docs-audit.sh` (all green, incl. the 2 new closeout
  tests); RED-proofed against the slug-only + guard-less engine.
- Regression: close-work-item, doc-numbering pass.
- Real repo: `docs-audit --list` now shows RFC-0013 as a closeout candidate and
  withholds RFC-0012; `--check --strict` verdict CLEAN, exit 0.

## Constraints / Risks
- Closeout is report-only — a wrong suggestion never fails a build; the Rollout
  guard further reduces false positives.
- `hasUnfinishedRolloutPhases` locates the Status column by header name, so it is
  robust to the differing column order of RFC-0012 vs RFC-0013 tables.
- `.aai/scripts/lib/docs-audit-core.mjs` is NOT a protected_paths_l3 path (L2).

## Notes
- Related: umbrella-progress-rollup (CHANGE-0055, the sibling fix + the Rollout
  Status table this guard reads), closeoutCandidatesFor (SPEC-0003, the pass fixed
  here).
