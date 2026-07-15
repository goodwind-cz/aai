---
id: per-type-digit-width
type: issue
number: 6
status: draft
links:
  spec: SPEC-0015
  pr: []
  commits: []
---

# Issue — Allocator/Index Force 4-Digit Numbers, Breaking Types With a 3-Digit Convention (PRD)

## Summary
- SPEC-0015's allocator and the index generator hardcode `padStart(4, '0')`,
  but the pre-existing documented convention for PRD (and prompt examples:
  `PRD-001`, `CHANGE-042`) is 3-digit. Reported by the operator (2026-07-15).

## Steps to Reproduce
1. In a project whose docs use 3-digit ids (e.g. vendored AAI with `PRD-001`),
   run intake → `/aai-pr` allocation for a new PRD.
2. Allocator mints `PRD-0002` (4-digit) next to `PRD-001` — mixed-width
   directory; `generate-docs-index.mjs` renders the existing `PRD-001` doc's
   display id as `PRD-0001`, diverging from its filename.

## Expected
- Number WIDTH follows the type's existing convention: next after `PRD-001` is
  `PRD-002`; index display id matches the filename verbatim. Types with no
  existing docs default to the documented convention: PRD → 3-digit; all other
  prefixes → 4-digit (this repo's universal practice: RFC/SPEC/CHANGE/ISSUE/
  REL/RES/DEBT are all 4-digit).

## Actual
- Uniform 4-digit render everywhere (parse is already width-agnostic `\d{1,5}`
  with numeric compare, so the duplicate guard is NOT blind — render-only bug).

## Acceptance Criteria
- AC-001: allocator derives per-prefix width from the highest-numbered existing
  doc (base ref ∪ local); fixture with `PRD-001` → next allocation is
  `PRD-002`.
- AC-002: empty-type default: PRD → `PRD-001`; a novel prefix → 4-digit
  (regression: RFC/SPEC sequences unchanged, e.g. next SPEC stays `SPEC-0019`).
- AC-003: index display id for a numbered file is taken from the FILENAME
  verbatim (`PRD-001-x.md` → `PRD-001`), never re-padded.
- AC-004: duplicate guard still flags `PRD-001` vs `PRD-0001` (numeric equal)
  and its message shows both offending filenames.
- AC-005: doc-numbering suite green incl. new width stanzas; docs-audit strict
  CLEAN; INTAKE_COMMON wording notes width-follows-type-convention.
