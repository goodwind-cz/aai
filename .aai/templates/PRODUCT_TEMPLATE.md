---
id: <work-item ref_id>
type: product
status: current
spec: <docs/specs/SPEC-XXXX-....md>
updated: <YYYY-MM-DD>
---

# <Feature name — user-facing>

<!--
Product artifact for a delivered, user-visible scope (one per work item;
UPDATE the existing doc for follow-up scopes touching the same feature).
Written for a READER OF THE PRODUCT, not of the pipeline: no workflow
jargon, no AC ids in prose. Keep every section; write "None." when a
section genuinely has no content — an empty heading is drift, an explicit
"None." is a statement. English, plain Markdown, no emoji.

CONVENTION (spec-product-docs-enforced D1-D2): setting `user_visible: true`
on the primary work-item doc's (change/issue/prd) frontmatter is what makes
THIS product doc required at close time. The filename slug here must equal
that primary doc's frontmatter `id` (docs/product/<id>.md) — close-work-item.mjs
looks this file up by that exact slug. Without a real doc at that path (every
required section below — "What it does", "Data model", "Interfaces and
contracts" — filled in, not left as an unfilled `<...>` placeholder), closing
a `user_visible: true` scope warns loudly by default, or refuses outright
under `product_doc_gate: enforce` in docs/ai/docs-audit.yaml. A section that
genuinely has nothing to report still needs the explicit literal "None." —
that counts as filled; an empty or placeholder-only section does not.
-->

<!--
GENERATED ROLLUP: every real (non-placeholder) product doc under
docs/product/*.md is picked up automatically by
`node .aai/scripts/generate-userguide-rollup.mjs`, which renders the "What it
does" first paragraph + links into the "Delivered features (generated)"
section of docs/USER_GUIDE.md. No extra step needed beyond writing this file
correctly.
-->

## What it does

<2-6 sentences of functional description: the need it serves, what a user
can now do, and any visible behavior change. Plain language.>

## How to use it

<Commands / UI paths / API calls with a minimal working example. For a flag
or config key: default value and where it lives.>

## Data model

<Entities/records/files this feature introduces or changes: name, fields
worth knowing, where stored, retention. "None." if no data shape changed.>

## Interfaces and contracts

<Public surfaces this feature adds or changes: CLI commands and exit codes,
API endpoints, file formats, events, env vars. One line each: surface,
shape, stability promise. "None." if no public surface changed.>

## Limits and non-goals

<Known boundaries, unsupported cases, and what was deliberately left out.>

## Links

- Request: <docs/issues/... intake doc>
- Spec: <docs/specs/...>
- Validation evidence: <docs/ai/reports/...>
