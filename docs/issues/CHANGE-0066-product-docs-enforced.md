---
id: product-docs-enforced
number: 66
type: change
status: draft
user_visible: true
links:
  pr: []
  commits: []
---

# Change — Product docs enforced at close + USER_GUIDE rollup generated from them

## Summary
- Product artifacts (docs/product/<ref>.md: functional description, data
  model, interfaces) exist as a convention but nothing enforces them, and
  USER_GUIDE remains a hand-drifting monolith (two catch-up CHANGEs in its
  history). Add a product-doc gate to the close ceremony (warn by default,
  enforce dial in docs-audit.yaml) and a deterministic USER_GUIDE rollup
  section generated from product docs, refreshed best-effort at close.

## Motivation / Business Value
- Original operator assignment: the factory must leave behind data models,
  interface descriptions, and user-facing functional documentation. Today 4
  of 110 delivered items carry a product doc; the rest predate the
  convention and nothing stops new user-visible scopes from skipping it.
- USER_GUIDE drift is a documented chronic failure (CHANGE-0041/0057).

## Scope
- In scope:
  - close-work-item.mjs: product-doc gate — when closing a work item whose
    spec/intake declares user_visible: true (new optional frontmatter key,
    absent = not gated), require docs/product/<ref>.md to exist and carry
    non-placeholder sections; report-only WARNING by default, refusal under
    product_doc_gate: enforce in docs/ai/docs-audit.yaml (same dial family
    as close_gate).
  - New .aai/scripts/generate-userguide-rollup.mjs: renders a
    marker-delimited "Delivered features (generated)" section in
    docs/USER_GUIDE.md from docs/product/*.md frontmatter + "What it does"
    first paragraph, sorted by updated date; idempotent; never touches
    content outside its markers; invoked best-effort from the close
    ceremony after the overview regen.
  - PRODUCT_TEMPLATE: add the user_visible convention note.
  - Tests: gate fixtures (gated missing doc -> warn; enforce -> exit
    nonzero + rollback-safe refusal BEFORE any write; ungated absent key ->
    silent), rollup idempotence + marker containment + placeholder
    rejection.
  - PROFILES classification for the new script (extended).
- Out of scope: backfilling product docs for the 106 legacy items; any
  USER_GUIDE restructure outside the generated section; INTERFACES.md
  extraction automation (future).

## Affected Area
- .aai/scripts/close-work-item.mjs, new .aai/scripts/
  generate-userguide-rollup.mjs, .aai/templates/PRODUCT_TEMPLATE.md,
  .aai/system/PROFILES.yaml, docs/USER_GUIDE.md (markers), docs/ai/
  docs-audit.yaml (dial doc), tests/skills (close-work-item + new rollup
  stanzas).

## Desired Behavior (To-Be)
- Closing a user_visible scope without a real product doc warns loudly
  (or refuses under enforce, before any status flip); USER_GUIDE carries an
  always-current generated section listing delivered features with links;
  legacy items unaffected.

## Acceptance Criteria
- AC-001: gate fires only when user_visible: true (fixture triad: gated
  missing -> WARNING; enforce -> refusal exit != 0 with nothing written;
  absent key -> silent) (suite-verified).
- AC-002: placeholder detection — a product doc whose Data model or
  Interfaces section still carries template placeholder text counts as
  missing (fixture-verified).
- AC-003: rollup renders only between its markers, is byte-idempotent on
  second run, and sorts by updated desc (suite-verified).
- AC-004: close ceremony invokes the rollup best-effort after overview
  regen; rollup failure never changes close exit code (negative control).
- AC-005: no regression — close-work-item + new rollup suites green
  locally; full run on PR CI.

## Verification
- bash tests/skills/test-aai-close-work-item.sh (+ gate stanzas)
- bash tests/skills/test-aai-userguide-rollup.sh (new)
- PR CI full framework.

## Constraints / Risks
- No secrets referenced (secrets preflight skipped).
- Ceremony L2 expected (close-work-item/USER_GUIDE not protected — verify).
- Gate must check BEFORE the close ceremony's first write (refusal is not a
  rollback path); warn-by-default preserves current behavior repo-wide.
- Markers in USER_GUIDE must never eat hand-written content — containment
  test mandatory.

## Notes
- Roadmap ride #6 (original-assignment gap: enforced product artifacts +
  generated user docs). Autopilot intake: metrics question skipped,
  human_time_minutes null.
