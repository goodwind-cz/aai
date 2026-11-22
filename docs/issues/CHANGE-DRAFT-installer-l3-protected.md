---
id: installer-l3-protected
type: change
number: null
status: done
links:
  pr: []
  commits: []
---

# The git hook installer and the hook bodies it installs are L3 protected surfaces

Frontmatter status values: draft | implementing | done | deferred | rejected | superseded

## Summary
- Add the git hook installer (`.aai/scripts/install-pre-commit-hook.mjs`,
  `.aai/scripts/install-pre-commit-hook.sh`,
  `.aai/scripts/install-pre-commit-hook.ps1`) and the four hook body
  templates it installs (`.aai/templates/git-hooks/pre-commit-index.sh`,
  `pre-commit-guard-checks.sh`, `reference-transaction.sh`, `pre-push.sh`)
  to `protected_paths_l3`.

## Motivation / Business Value
- Follow-up `fu-installer-not-in-l3-protected-paths` (docs/ai/decisions.jsonl,
  P3): the installer writes the ref-guard and close-gate hooks, so a change
  to it, or to a hook body it copies, can weaken the guards it installs
  without the L3 ceremony. Owner decision 2026-11-22: the installer is an
  L3 protected surface.

## Scope
- In scope: `protected_paths_l3` in docs/ai/docs-audit.yaml and in the
  vendored seed .aai/templates/docs-audit.template.yaml (kept identical, the
  sync-seed suite pins that); the canonical defaults list in
  .aai/workflow/WORKFLOW.md "Ceremony levels"; one test that the CI impact
  selector, which reads the live list, classifies each of the seven paths as
  `protected-l3`; a CHANGELOG [unreleased] entry (the seed template reaches
  new installs).
- Out of scope: existing downstream docs-audit.yaml files (project-owned, an
  /aai-update never rewrites them); mechanical diff enforcement of the list;
  the aai-sync scripts.

## Affected Area
- docs/ai/docs-audit.yaml, .aai/templates/docs-audit.template.yaml,
  .aai/workflow/WORKFLOW.md, tests/skills/test-aai-suite-select.sh,
  CHANGELOG.md.

## Desired Behavior (To-Be)
- A spec whose scope touches the installer or a hook body template must
  declare ceremony level 3; the CI impact selector escalates a PR touching
  one of them to a full run (`FULL_RUN reason=protected-l3`); the delta
  re-check refuses a slim round for such a delta (`protected_path:`).

## Acceptance Criteria
- AC-001: both lists carry the seven paths, in the same order.
- AC-002: the selector run against this repository names each of the seven
  paths `FULL_RUN reason=protected-l3`.
- AC-003: WORKFLOW.md "Ceremony levels" lists the installer and the hook
  templates among the protected surfaces.

## Verification
- `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh aai-suite-select aai-sync-seed aai-ceremony-levels`
  exits 0.

## Constraints / Risks
- The change edits the L3 list and WORKFLOW.md (itself protected): ceremony
  level 3, the owner merges.
- No secret referenced.

## Notes
- Assumption (autopilot): the hook body templates are the four files under
  .aai/templates/git-hooks/ named by the installer's TEMPLATE_FILES map.
