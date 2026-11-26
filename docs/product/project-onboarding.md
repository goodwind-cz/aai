---
id: project-onboarding
type: product
capability: project-onboarding
status: current
delivered_by:
  - onboarding-tech-contract-and-lint-gaps
spec: docs/specs/SPEC-0317-spec-onboarding-tech-contract-and-lint-gaps.md
updated: 2026-11-26
---

# First-run onboarding: technology contract pointer, working lint skill, fresh-project TECH_EXTRACT

## What it does

The first run on a freshly synced project now points you to the one step that
is easy to miss: filling the technology contract. `/aai-doctor` reports a
warning when `docs/TECHNOLOGY.md` is still the unfilled template seed, and
`/aai-bootstrap` ends its summary with the same pointer, so the contract no
longer stays empty without anyone noticing. Bootstrap also generates a lint
skill that works for a project with only a legacy `.eslintrc*` config, and
the TECH_EXTRACT prompt says what to do when `docs/ai/STATE.yaml` does not
exist yet.

## How to use it

- Run `/aai-doctor` (or `node .aai/scripts/aai-doctor.mjs`). When
  `docs/TECHNOLOGY.md` still says `- Status: template-seed` in its header,
  the Knowledge Files category (CAT-05) is WARN with the line
  `docs/TECHNOLOGY.md is still the template seed (Status: template-seed); run TECH_EXTRACT (.aai/TECH_EXTRACT.prompt.md) to fill the technology contract`.
  `--strict` turns that WARN into exit 1.
- Run `/aai-bootstrap` (or `.aai/scripts/aai-bootstrap.sh`, with or without
  `--dry-run`). In the same case its summary ends with a
  `Technology contract:` block carrying that line.
- Follow `.aai/TECH_EXTRACT.prompt.md`. On a fresh project it creates STATE
  with `node .aai/scripts/check-state.mjs --repair docs/ai/STATE.yaml`, and
  records its focus with
  `node .aai/scripts/state.mjs set-focus --type technology_extraction --ref technology-extraction --path docs/TECHNOLOGY.md`.
  If either command fails, it skips the STATE steps and says so. STATE is
  never written by hand.

## Data model

None.

## Interfaces and contracts

- `aai-doctor.mjs` CAT-05: WARN (was PASS) for a template-seed
  `docs/TECHNOLOGY.md`; LF, CRLF and BOM copies are detected. A filled
  contract keeps the same PASS line as before.
- `aai-bootstrap.mjs` summary: a trailing `Technology contract:` block for a
  template-seed contract, in normal and dry-run mode. The file itself is
  never modified.
- `aai-bootstrap.mjs` lint command:
  - flat config (`eslint.config.*`), with or without eslint installed:
    `<pm exec> eslint .` (unchanged);
  - legacy `.eslintrc*` with eslint as a dependency or in
    `node_modules/.bin`: `<pm exec> eslint .` (unchanged);
  - legacy `.eslintrc*` with no local eslint: `npx eslint@8 .`, with an
    `## ESLint 8 pin` note in the generated skill, because ESLint 9 and
    later ignore eslintrc;
  - a local eslint bin with no eslint config does not select eslint, so
    Biome, Ruff and the other detectors behave as before.
- `.aai/TECH_EXTRACT.prompt.md`: a documented absent-STATE path and a single
  `state.mjs set-focus` call in place of hand edits to STATE.

## Limits and non-goals

- The pin is checked against a stubbed `npx`; whether ESLint 8 lints a given
  legacy project (its plugins, its rules) is up to that project. Adding
  eslint as a devDependency, or migrating to `eslint.config.*`, removes the
  pin.
- The lint target stays `.`; bootstrap does not narrow it to a subset of a
  legacy tree.
- `eslintConfig` inside `package.json` is not treated as an eslintrc config.
- A `docs/TECHNOLOGY.md` that lost its `- Status:` header line is not flagged.
- TECH_EXTRACT's `set-focus` replaces an active focus without checking;
  tracked as follow-up `fu-tech-extract-focus-clobber`.

## Links

- Request: docs/issues/ISSUE-0127-onboarding-tech-contract-and-lint-gaps.md
  (GitHub #588, #589, #590)
- Spec: docs/specs/SPEC-0317-spec-onboarding-tech-contract-and-lint-gaps.md
- Validation evidence: docs/ai/reports/VALIDATION-20261126T000626Z-onboarding-tech-contract-and-lint-gaps.md
