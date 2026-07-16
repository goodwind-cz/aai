---
id: state-list-append-indent
type: issue
number: 7
status: done
links:
  pr:
    - 63
  commits:
    - 26b21b7
---

# Issue — state.mjs List-Field Writes Emit Mis-Indented Sibling Items (invalid YAML)

## Summary
- Appending to an existing list field (observed on `code_review.report_paths`
  and `last_validation.evidence_paths`) writes the new sibling at 2-space
  indent under a 4-space list, producing YAML that PyYAML rejects while
  check-state.mjs (top-level-keys-only) still passes.

## Steps to Reproduce
1. `set-code-review --report <a>` (list gets one 4-space item), later
   `set-code-review --report <b>` for the same scope on a state where the
   field already carries an item.
2. `python3 -c "import yaml; yaml.safe_load(open('docs/ai/STATE.yaml'))"` →
   ParserError "expected <block end>, but found '-'".

## Expected
- New list items are written at the list's existing indent; the file stays
  parseable by any YAML reader.

## Actual
- Three sightings on 2026-07-15 (main STATE ×2 fields, archived worktree
  STATEs ×2 files); hand-repaired each time.

## Acceptance Criteria
- AC-001: appending to a populated list field yields a sibling at identical
  indent; PyYAML round-trip passes (add to the state suite).
- AC-002: check-state gains a whole-file YAML-parse smoke check (or the
  line-engine validates list-block shape on write) so this class fails loud.
- AC-003: regression stanza covering report_paths and evidence_paths appends.
