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
