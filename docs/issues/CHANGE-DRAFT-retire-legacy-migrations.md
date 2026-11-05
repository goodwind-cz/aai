---
id: retire-legacy-migrations
type: change
number: null
status: draft
capability: retire-legacy-migrations
parent: smaller-node-core-and-faster-feedback
links:
  pr: []
  commits: []
---

# Retire the legacy migration scripts and port migrate-state-to-local to Node

## Summary
- Ride 1 of the [remaining-scripts plan](../analysis/node-first-remaining-plan.md)
  (RFC-0017 phase 5), as revised after the Codex review on PR #531.
- (a) Retire `migrate-yaml-to-jsonl` (.sh/.ps1) and `aai-canonicalize`
  (.sh/.ps1) together with the `/aai-canonicalize` skill: its prompt
  `.aai/SKILL_CANONICALIZE.prompt.md`, the skill wrappers in every harness
  tree, the catalog rows, the profile classification and every doc and test
  pin.
- (b) Port `migrate-state-to-local` (.sh/.ps1) to one Node module with thin
  launchers and the same effects; its callers stay unchanged.

## Motivation / Business Value
- About 893 code lines of twin duplication (non-blank, non-comment) leave the
  shipped layer: aai-canonicalize 223/228, migrate-yaml-to-jsonl 78/99,
  migrate-state-to-local 122/143 (plan section 2, re-measured on main
  `f324b66f`).
- aai-canonicalize and migrate-yaml-to-jsonl are one-off migrations with no
  change since July and March 2026; migrate-yaml-to-jsonl needs python3 and
  PyYAML. Yet `SKILL_CANONICALIZE.prompt.md`, `SKILLS.md`, `AGENTS.md` and the
  user guide still advertise them, so an agent can still run them.
- migrate-state-to-local is live: `aai-doctor.mjs` and both `aai-sync` twins
  send legacy projects to it. Its two copies already drift (the PowerShell
  copy adds 16 ignore entries, the shell copy 6), so one implementation fixes
  real drift, not only duplication.

## Scope
- In scope:
  - Owner decision 2026-11-05 (plan section 4, item 2): a retired script stays
    ONE release as a deprecation launcher, then it is deleted in a later
    release. Each retired `.sh` and `.ps1` becomes a launcher of at most 20
    lines that prints that the script (and, for aai-canonicalize, the skill)
    is retired, names the replacement or "none", changes nothing, and exits
    non-zero.
  - The `/aai-canonicalize` skill: the prompt becomes a short retirement
    notice; the wrappers under `.claude`, `.agents`, `.codex` and `.gemini`
    say it is retired; the `SKILLS.md`, `AGENTS.md`, user guide and generated
    catalog rows follow; the prompt-diet ledger and TEST-012 pin are trued up
    for the shrink.
  - Follow the pre-compact-save retirement precedent (CHANGE-0239 /
    SPEC-0265) and keep the wrappers eligible for the aai-sync retired-wrapper
    prune (sync-prune-retired-skill-wrappers) once the prompt is deleted in
    the later release.
  - `migrate-state-to-local`: one Node module, a thin `.sh` and `.ps1`
    launcher, the same effects (untrack STATE, LOOP_TICKS and the runtime
    evidence paths, add the ignore entries, create `EVENTS.jsonl`, the dirty
    tree and git refusals, the dry run, the summary and next-step text), the
    measured drift between the two copies recorded and one behavior chosen.
    Follow the reaper precedent (CHANGE-0241 / SPEC-0267): `node:test` per
    behavior, Pester parity on the native Windows job, and a scratch
    `aai-sync` install proving the launchers.
  - Node is a hard prerequisite (owner decision 2026-11-05, plan section 4,
    item 1): a launcher without Node refuses with an install hint.
  - RFC-0017: the remaining-pairs table and the phase 5 row get one sentence
    each for this slice; phase 5 stays `in progress`.
  - Before/after code-line measurement with the plan's method.
- Out of scope:
  - Deleting the retired launchers, the prompt and the wrappers (the later
    release).
  - Any other pair (autonomous-loop is ride 2).
  - Changing what aai-doctor or aai-sync print about migrate-state-to-local.
  - Moving the ignore set to `.aai/system/RUNTIME_IGNORE.list`.

## Affected Area
- `.aai/scripts/{aai-canonicalize,migrate-yaml-to-jsonl,migrate-state-to-local}.{sh,ps1}`
  and a new `.aai/scripts/migrate-state-to-local.mjs`
- `.aai/SKILL_CANONICALIZE.prompt.md`, `.aai/AGENTS.md`, the four
  `aai-canonicalize/SKILL.md` wrappers, `.codex/skills/README.md`,
  `.gemini/skills/README.md`, `SKILLS.md`, `docs/USER_GUIDE.md`,
  `docs/SKILL_CATALOG.html`, `docs/skill-catalog-data.json`
- `.aai/system/PROFILES.yaml`, `tests/skills/suite-map.yaml`,
  `.github/workflows/ps1-quality.yml`, `tests/skills/lib/prompt-diet-ledger.sh`,
  `tests/skills/test-aai-prompt-diet.sh`,
  `tests/skills/lib/cd-subshell-leak-baseline.tsv`
- `docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md`

## Desired Behavior (To-Be)
- Running a retired script on any platform prints one retirement line on
  stderr and exits non-zero without touching the tree; invoking
  `/aai-canonicalize` explains the retirement and runs nothing.
- `migrate-state-to-local` has one implementation, in Node; the `.sh` and
  `.ps1` commands that aai-doctor, aai-sync and the README name keep working
  with the same effects, apart from the recorded drift choices.

## Acceptance Criteria
- AC-001: The four retired scripts are launchers of at most 20 lines that
  print a retirement line naming the replacement or none, change nothing and
  exit non-zero, on POSIX shells and on PowerShell 5.1 and 7.
- AC-002: The `/aai-canonicalize` prompt and all four wrappers say the skill
  is retired; no shipped prompt, wrapper or catalog row tells an agent to run
  either retired script; the wrappers stay prunable by aai-sync once the
  prompt is deleted.
- AC-003: migrate-state-to-local's logic lives in one Node module; its
  launchers hold no copy of it and refuse with an install hint without Node.
- AC-004: The module produces the same effects as the old copies on a legacy
  fixture (untracked paths, ignore entries, EVENTS.jsonl, refusals, dry run,
  idempotent re-run), with every measured drift case tested.
- AC-005: Parity holds on Linux and macOS and on the native Windows Pester job
  under Windows PowerShell 5.1 and pwsh 7; a scratch aai-sync install runs
  the target's own launchers.
- AC-006: Wiring is complete: PROFILES classifies the module, the suite map
  and the ps1-quality path filter know it, the prompt-diet ledger and
  TEST-012 match the corpus, and the RFC-0017 inventory test passes.
- AC-007: The before and after code lines are measured with the plan's
  method and recorded.

## Verification
- The touched suites and the new `node:test` and Pester files pass (rc 0).
- The Windows CI job passes on the pull request under both engines.
- A scratch `aai-sync` install runs the target's migrate-state-to-local
  launcher on a legacy fixture and the retired launchers refuse there.

## Constraints / Risks
- Changing shipped scripts and a shipped skill is consumer-visible; merge
  stays with the owner, and the retirement is named in the CHANGELOG.
- Windows parity is proven only by the hosted Windows job (lesson of the
  phase 3 slices); a hosted failure is diagnosed with a probe first.
- The migration writes git index state in a target project; tests run only
  on scratch repositories.
- No secrets referenced.

## Notes
- Source: roadmap item `retire-legacy-migrations`; plan
  `docs/analysis/node-first-remaining-plan.md` ride 1; owner decisions
  2026-11-05 (Node prerequisite, one-release deprecation launcher).
- Autopilot defaults: human_time_minutes null; no implementation-mode menu
  (Planning decides).
