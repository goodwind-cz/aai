---
id: onboarding-tech-contract-and-lint-gaps
type: issue
capability: project-onboarding
user_visible: true
number: 127
status: done
links:
  pr: []
  commits: []
---

# Onboarding leaves the technology contract empty and generates a broken lint skill

## Summary
Sources: three GitHub issues filed by the friction feedback channel from one
downstream onboarding run (Windows, Node 24, layer pin v2026.11.24, Claude
harness). Their titles and excerpts, quoted as data:

- #588 https://github.com/goodwind-cz/aai/issues/588

  > [missing_or_invalid_artifact] SKILL_BOOTSTRAP/report (medium impact)
  >
  > Neither aai-bootstrap nor aai-doctor detects that TECHNOLOGY.md is still
  > the unfilled template seed (Status: template-seed); doctor CAT-05 passes
  > and nothing points the operator to TECH_EXTRACT, so the technology
  > contract silently stays empty.

- #589 https://github.com/goodwind-cz/aai/issues/589

  > [deterministic_script_failure] SKILL_BOOTSTRAP/lint-detection (medium impact)
  >
  > aai-bootstrap generates an unpinned 'npx eslint .' lint skill when the
  > project has only a legacy .eslintrc config and eslint is not a
  > dependency; npx then pulls ESLint 9, which ignores eslintrc, so the
  > generated skill is broken. It should pin ESLint 8 for eslintrc configs
  > and not lint the whole legacy tree by default.

- #590 https://github.com/goodwind-cz/aai/issues/590

  > [contradictory_instructions] TECH_EXTRACT/preflight (low impact)
  >
  > TECH_EXTRACT.prompt.md requires reading and updating STATE.yaml, but in
  > a freshly synced project STATE.yaml does not exist yet (doctor CAT-06
  > says the first loop tick creates it); the prompt gives no fallback for
  > this case.

All three hit the same first-run path: sync the layer, run bootstrap and
doctor, then fill the technology contract. Each leaves the operator with a
wrong or missing artifact and no pointer to the fix.

## Type
bug

## Impact
- Every project that adopts the layer for the first time.
- #588: `docs/TECHNOLOGY.md` stays at the template seed while doctor reports
  CAT-05 PASS; every later role reads an empty technology contract.
- #589: the generated lint skill runs `npx eslint .`, which fetches the
  latest ESLint (flat config only) and fails on a project whose only config
  is a legacy `.eslintrc*`.
- #590: the operator following TECH_EXTRACT on a fresh project has no
  documented path when `docs/ai/STATE.yaml` is absent, and may hand-write it.
- Severity: P3 (medium/medium/low impact, manual workaround exists).

## Current Behavior
- `aai-doctor.mjs` CAT-05 (Knowledge Files) passes when `docs/TECHNOLOGY.md`
  exists, regardless of its `Status: template-seed` line; the bootstrap report
  does not mention TECH_EXTRACT.
- `aai-bootstrap.mjs` emits `<pm exec> eslint .` whenever an eslint config
  (`.eslintrc*` or `eslint.config.*`) or an eslint dependency exists, with no
  version pin, whether or not eslint is installed locally.
- `.aai/TECH_EXTRACT.prompt.md` tells the agent to read and update
  `docs/ai/STATE.yaml` with no branch for the file being absent.

## Expected Behavior
- Doctor flags a `docs/TECHNOLOGY.md` still at template-seed status
  (WARN/DEGRADED, not PASS) with an actionable "run TECH_EXTRACT" line, and
  the bootstrap report points to it.
- Bootstrap's lint command uses the project's own eslint when it is a
  dependency or a local bin; with only a legacy `.eslintrc*` and no local
  eslint it pins ESLint 8, or reports clearly that no lint command was
  generated. Flat config (`eslint.config.*`) behavior is unchanged when
  eslint is present.
- TECH_EXTRACT documents what to do when `docs/ai/STATE.yaml` is absent
  (initialize through the canonical state tooling, or skip the STATE update
  with a note) and never asks for a hand-written STATE file.

## Steps to Reproduce (if applicable)
1) Fresh temp project with the layer synced and `docs/TECHNOLOGY.md` copied
   from `.aai/templates/TECHNOLOGY_TEMPLATE.md`; run
   `node .aai/scripts/aai-doctor.mjs` — CAT-05 reports PASS.
2) Fresh temp project with `package.json` (no eslint dependency) and
   `.eslintrc.json`; run bootstrap detection — the lint skill is the
   unpinned `npx eslint .`.
3) Fresh temp project with no `docs/ai/STATE.yaml`; read
   `.aai/TECH_EXTRACT.prompt.md` — no fallback for the missing file.

## Verification
- Skill-suite cases with temp fixtures (no network, stubbed npx/eslint, no
  real repos): doctor on a template-seed TECHNOLOGY.md vs a filled one;
  bootstrap lint detection for legacy eslintrc without eslint, eslintrc with
  eslint dependency, flat config with eslint, flat config without eslint;
  TECH_EXTRACT prompt text names the absent-STATE path.
- sh/ps1/Node twins of touched code agree.

## Constraints / Risks
- Prompt edits follow the prompt-corpus governance (diet-ledger entry,
  TEST-012 bump, PROFILES classification).
- Tests must never install packages from the network, touch real repos, or
  write to the owner's home.
- Secrets preflight: no secret referenced.

## Notes
- Triage approved by the owner via /aai-issues on 2026-11-25; one ride covers
  all three issues because they share the onboarding path and the bootstrap
  and doctor surfaces.
- Issue write-back (comment + close) happens only after the PR merges.
- Autopilot intake: human_time_minutes null; implementation mode left to
  Planning.
