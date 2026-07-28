---
id: docs-hub-generator
type: product
status: current
spec: docs/specs/SPEC-0102-spec-docs-hub-generator.md
updated: 2026-07-28
---

# Skills catalog (docs hub)

## What it does

`docs/SKILL_CATALOG.html` is a searchable, self-contained page listing
every AAI skill with its description, model hint and Goal extract. It is
generated deterministically from the live `.claude/skills/` tree and
regenerated automatically at every work-item close, so it can no longer
drift out of date (the old hand-authored catalog was missing 8 of 35
skills).

## How to use it

- Open `docs/SKILL_CATALOG.html` in a browser (search box filters live;
  no network needed) or publish it with `/aai-share`.
- Regenerate manually: `node .aai/scripts/generate-docs-hub.mjs`
  (`--data-only` for JSON only, `--output <path>` to redirect; an unknown
  flag exits 2 and writes nothing).
- `/aai-docs-hub` runs the generator and relays the summary; ask
  explicitly if you also want LLM categorization commentary.

## Data model

- `docs/skill-catalog-data.json` — `generatedAt`, `skillsCount`, and one
  entry per skill: `dir`, `name`, `description`, `model`, `goal`,
  `promptPath`, `notes[]` (visible degrade reasons, never silent).

## Interfaces and contracts

- Exit 0 on success (including a 0-skill degrade with NOTE), 2 on CLI
  misuse writing nothing. HTML is byte-idempotent on unchanged inputs;
  the footer skill count always equals the live directory listing
  (suite-pinned).

## Limits

- Categorization/relationship inference is not computed — by design it is
  an optional LLM add-on, requested explicitly.
