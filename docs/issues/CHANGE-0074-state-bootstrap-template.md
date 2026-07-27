---
id: state-bootstrap-template
number: 74
type: change
status: draft
user_visible: true
links:
  pr: []
  commits: []
---

# Change — ship STATE_TEMPLATE.yaml and teach check-state --repair to create a missing STATE

## Summary
- Universality-proof F1 (docs/project-sessions/2026-07-27-universality-proof.md):
  a virgin target project cannot mechanically init docs/ai/STATE.yaml. The
  canonical schema lives only in the header comment of a file that does not
  exist yet; `check-state.mjs --repair` errors on a missing file;
  `state.mjs` refuses every subcommand; ORCHESTRATION step 4 promises
  "create with canonical schema defaults" that nothing ships. Ship
  `.aai/templates/STATE_TEMPLATE.yaml` (schema header + empty canonical
  defaults) and make `check-state --repair` create the file from it when
  missing (also covering aai-sync/install targets).

## Acceptance Criteria
- AC-001: `check-state.mjs --repair docs/ai/STATE.yaml` on a tree without
  the file creates it byte-equal to the template and exits 0; dispatch on
  the result yields `no_focus_ref` (not `state_file_missing`)
  (suite-verified RED/GREEN).
- AC-002: template carries the schema header verbatim (single source: a
  pin test asserts header equality with the canonical repo STATE.yaml
  comment block, preventing drift).
- AC-003: no regression — check-state suite green; existing-file repair
  behavior byte-unchanged.

## Verification
- tests/skills/test-aai-check-state.sh (extended)

## Constraints / Risks
- Ceremony: L3 ATTENTION — check-state.mjs may fall under pre-commit/
  protected tooling review; verify protected_paths_l3 at planning.
- Risk: template/schema drift — mitigated by the AC-002 pin.

## Notes
- Found by the universality proof; blocks true "state a need on a fresh
  repo" autonomy for target projects.
