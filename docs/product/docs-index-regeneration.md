---
id: docs-index-regeneration
type: product
capability: docs-index-regeneration
status: current
delivered_by:
  - index-schema-warning-prominence
spec: docs/specs/SPEC-0314-spec-index-schema-warning-prominence.md
updated: 2026-11-25
---

# Docs index regeneration

## What it does

The docs index generator rebuilds `docs/INDEX.md` from the frontmatter of the project documents, on every docs commit through the installed pre-commit hook and on demand. A document whose frontmatter breaks the schema (for example an unknown `status`) cannot be indexed, so the generator leaves it out and keeps going. That used to be easy to miss: the one line about the dropped document sat in the middle of a long list of standing warnings. The generator now prints the dropped documents as a block at the very end of its output, headed `DROPPED from docs/INDEX.md`, with one line per document and one line telling you how to fix it. Documents that sit in no index section (coverage gaps) are summarised in a single line; the full list stays in the index under "Coverage gaps".

## How to use it

Run `node .aai/scripts/generate-docs-index.mjs`. The last block on stderr names every dropped document, the reason, and a `Fix:` line with the allowed `status` values, the Review-By forms (an ISO date, a skill label, `label:date`, or `<actor> <method>`) and the companion file `docs/INDEX.violations.md`.

Add `--verbose` to also list each coverage-gap document on stderr instead of the one summary line. The flag is off by default and is not used by the hook. Add `--strict` (or run `lint-docs`) to exit 1 on a schema violation or a coverage gap, as before (it stops at the first kind of violation it meets).

## Data model

None. `docs/INDEX.md` and `docs/INDEX.violations.md` are written byte for byte as before, whether or not `--verbose` is given.

## Interfaces and contracts

- `generate-docs-index.mjs` stderr: a `DROPPED` block as the last output when a document is dropped by a schema violation; nothing when none is. Stable wording of the header; the per-document line keeps the existing reason text.
- `generate-docs-index.mjs --verbose`: new flag, lists each coverage-gap document on stderr; no effect on files or exit codes.
- Exit codes: unchanged. A default run exits 0; `--strict` exits 1 on a violation or a coverage gap.

## Limits and non-goals

- The `DROPPED` block is last in the generator's output, not in the hook's: the hook's own close-gate and body-lint lines, when they fire, still follow it.
- The list of documents without frontmatter (the trailing `N warning(s):` list) is unchanged.
- A project on an older pin keeps the old output until it runs `/aai-update`.

## Links

- Request: docs/issues/ISSUE-0125-index-schema-warning-prominence.md
- Spec: docs/specs/SPEC-0314-spec-index-schema-warning-prominence.md
- Validation evidence: docs/ai/tdd/index-schema-warning-prominence/
