---
id: provider-adapter-registry
type: product
capability: provider-adapter-registry
status: current
delivered_by:
  - provider-adapter-registry-slice
spec: docs/specs/SPEC-0253-spec-provider-adapter-registry-slice.md
updated: 2026-10-25
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
  overrides block as before.
- **AGENTS.md on update.** `aai-sync` installs the root `AGENTS.md` like
  `CLAUDE.md`. It used to delete a project's own copy without saying so. A
  project copy that differs is now named in the conflict advisory before it is
  replaced.

## Limits and non-goals

- Only these six files are generated. Other surfaces that still repeat the
  skill set, such as the `SKILLS.md` quick reference, are listed as follow-ups
  with their measurements.
- On a project checked out with CRLF line endings, the bash `aai-sync` can read
  a Copilot override block as empty and replace it
  (`fu-sync-sh-crlf-override-block`); the PowerShell twin keeps it.
