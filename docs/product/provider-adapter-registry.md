---
id: provider-adapter-registry
type: product
capability: provider-adapter-registry
status: current
delivered_by:
  - provider-adapter-registry-slice
  - provider-adapter-surfaces-closing-slice
spec: docs/specs/SPEC-0253-spec-provider-adapter-registry-slice.md
updated: 2026-10-31
---

# One registry for the per-provider instruction files

## What it does

Every coding agent AAI supports reads its own small instruction file in the
project root: `CLAUDE.md`, `AGENTS.md`, `CODEX.md`, `GEMINI.md`,
`.github/copilot-instructions.md` and `.cursor/rules/aai.mdc`. Each one only
points the agent at the canonical guide in `.aai/`. They used to be kept by
hand, and they drifted: the Copilot file still listed 20 of the 42 skills,
one of them already renamed.

These six files are now generated from one registry, the same way the skill
mirror trees (`.agents/skills`, `.codex/skills`, `.gemini/skills`) already
were. A hand edit to a generated file fails a check before it can merge.

## Data model

- **The registry.** The `shims:` section of `.aai/system/HARNESS_SKILLS.yaml`
  has one row per file: its path, the fragments it is built from, and the two
  values a fragment may use (`{{name}}` and `{{cli}}`). A difference between
  providers is declared in the row, never flattened.
- **The fragment text.** `.aai/system/HARNESS_SHIMS.md` holds every fragment
  once. Text shared by several files, such as the "this shim intentionally
  lists no skills" paragraph, exists in one place.
- **The shipped Copilot versions.** `.aai/system/COPILOT_SHIM_SHIPPED.list`
  holds one normalised hash (CRs and trailing newlines removed) of every
  Copilot file AAI has ever shipped. `--write` appends the current version.

## Interfaces and contracts

- **The generator.** `node .aai/scripts/sync-harness-skills.mjs --write`
  writes all six files from the registry. `--check` writes nothing: it renders
  each file and compares the result byte for byte with the file on disk. It
  prints one `DIVERGE shim <path>` line per file that differs and exits 1, or
  `OK: 6 shim(s) match the registry` and exits 0. It compares bytes only; it
  does not check what an agent does with the text.
- **Refusals.** A broken registry exits 2 and names the cause. So does, in
  both modes and before any write, a shim path, one of its parent directories
  or the shipped list that is a symbolic link, a parent that is not a
  directory, or a shim that is not a regular file. The check reads link type
  only: a hard-linked shim is written like any other file.
- **The gate.** The same `--check` already ran for the skill trees in the
  hygiene suite (test_111), so a changed shim now fails there too. The suite
  `tests/skills/test-aai-harness-shims.sh` covers the registry, the generator
  and the install paths below. `.gitattributes` pins the six files and the
  fragment file to LF, so a Windows checkout does not turn them into a false
  difference.
- **Copilot on update.** When `aai-sync` (bash or PowerShell) finds a
  project's Copilot file whose extra text matches one of the shipped hashes, it
  replaces the file and says so, instead of carrying the old skill list forward
  as a "project override". Text the project really added is kept in the
  overrides block as before. Both installers now read the block the same way
  when the file has CRLF line endings: the bash `aai-sync` used to read it as
  empty and replace the file, losing the project's text.
- **The SKILLS.md quick reference.** The `catalog:` section of the same
  registry points the generator at the Quick Reference table in `SKILLS.md`.
  `--check` prints one `DIVERGE catalog SKILLS.md: missing row <skill>` line
  per skill wrapper in `.claude/skills/` that has no row, and one `orphan row`
  line per row with no skill behind it, and exits 1; a matching table prints
  `OK: <n> skill(s) listed in the SKILLS.md Quick Reference`. `--write` adds
  each missing row from the skill's own description and removes orphan rows;
  rows already there stay byte for byte, and a second run changes nothing. It
  refuses (exit 2) a description containing a pipe, a `SKILLS.md` or parent
  directory that is a symbolic link, and a catalog path that leaves the
  project (absolute, or a `..` segment with either `/` or `\`). The table
  covers universal skills only: a wrapper with no `.aai/SKILL_*.prompt.md` and
  no `node .aai/scripts/*.mjs` command, such as the `aai-test-unit` or
  `aai-build` wrappers `/aai-bootstrap` generates, is left out of both modes
  without a message, and its mirrors are still written. The table now lists all 42 skills; the five it was
  missing (aai-factory-report, aai-live, aai-merge, aai-release,
  aai-roadmap) were added by `--write`.
- **AGENTS.md on update.** `aai-sync` installs the root `AGENTS.md` like
  `CLAUDE.md`. It used to delete a project's own copy without saying so. A
  project copy that differs is now named in the conflict advisory before it is
  replaced.

## Limits and non-goals

- The six instruction files are generated; the `SKILLS.md` quick reference is
  checked and filled in row by row, not rewritten, so its hand-written
  descriptions stay.
- No shipped path runs the catalog check in a downstream project. A project
  skill wrapper that does point at an `.aai/SKILL_*.prompt.md` or a node
  command counts as universal, so `--check` reports a missing row for it until
  `--write` adds one.
