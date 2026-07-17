---
id: spec-lint-duplicate-ac-id
type: issue
number: 11
status: draft
links:
  pr: []
  commits: []
---

# Issue: spec-lint silently drops a duplicate Spec-AC-id row (raw-vs-parsed miss)

## Summary
- When a spec's AC Status table contains two rows with the same `Spec-AC-NN`
  id, the shared table parser keys rows by id and collapses them, silently
  dropping the second row. spec-lint never flags the duplicate, so an AC row
  (potentially non-terminal / unevidenced) escapes the lint and the close gate.

## Root Cause
- `parseAcTable` (shared, in the docs-audit lib) reduces rows into an id-keyed
  structure; a repeated `Spec-AC-NN` overwrites rather than being reported.
  spec-lint consumes the parsed rows without reconciling them against the RAW
  row count, so `raw_rows > parsed_unique_rows` goes unnoticed. spec-lint.mjs
  already carries a comment acknowledging "AC rows the shared parser silently
  drops" but does not yet surface it.

## Current Cost / Risk
- Governance-tooling correctness gap: a duplicate id (copy-paste when adding an
  AC, or a renumber slip) hides a row. If the hidden row is non-terminal or
  unevidenced, the spec can pass spec-lint / close-gate while an acceptance
  criterion is unaddressed — the exact "quietly under-report" failure the lint
  exists to prevent. Report-only lint, but the miss is silent.

## Steps to Reproduce
- A spec AC Status table with two `| Spec-AC-03 | ... |` rows (different bodies);
  `node .aai/scripts/spec-lint.mjs --path <that spec>` — currently no duplicate
  finding; the second row's status/evidence is invisible to the lint.

## Expected vs Actual
- Expected: spec-lint emits a `duplicate-ac-id` finding naming the repeated id
  and the raw-vs-parsed row-count delta; a spec with a duplicate id does not
  pass clean.
- Actual: no finding; second row silently dropped.

## Acceptance Criteria
| AC | Status | Evidence |
|---|---|---|
| AC-001: spec-lint reconciles RAW AC-table data rows against the parsed unique-id rows and emits a `duplicate-ac-id` finding (naming the repeated Spec-AC id) whenever a row is dropped; a fixture spec with a duplicate id fails clean-lint. | pending | |
| AC-002: no false positives — a well-formed table (incl. a legitimate `Spec-AC-NN..MM` range row and the lean/compact AC-table shapes) emits zero duplicate findings; existing spec-lint suite stays green with zero assertion edits. | pending | |

Ceremony justification: single-surface additive lint check in spec-lint.mjs +
regression stanzas; no engine/shared-parser change, no protected path (L1).

## Verification
- New stanzas in `tests/skills/test-aai-spec-lint.sh`: a duplicate-id fixture
  (flagged) + a range-row and compact-table negative control (not flagged);
  `bash` suite exit 0; a real repo spec-lint run stays 0-findings.

## Notes
- Source: spec-lint review disposition in decisions.jsonl (ref `spec-lint`,
  F2 dup-id dropped-row). The bundled `state-engine append-run flow-style
  work_items: {}` tolerance is a SEPARATE surface (state-engine.mjs) and stays
  its own follow-up — out of scope here.
