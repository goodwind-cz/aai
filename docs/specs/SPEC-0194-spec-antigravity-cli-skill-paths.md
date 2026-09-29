---
id: spec-antigravity-cli-skill-paths
type: spec
number: 194
status: done
mutation_gate: v1
frozen_sha256: d9e456bece29ae8517f02c141f525c5f2c03474fb26ad4bca7646fad16b1b8ee
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0196-antigravity-cli-skill-paths.md
  rfc: null
  pr:
    - 407
  commits:
    - a7204fdf62b3e1bd4db77e08a138275ea6fc4ab3
---

# Spec — keep AAI skills on the Antigravity CLI project path

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0196-antigravity-cli-skill-paths.md
- Technology contract: docs/TECHNOLOGY.md
- Existing project mirror: .aai/scripts/sync-harness-skills.mjs and .aai/system/HARNESS_SKILLS.yaml

## Implementation strategy
- Strategy: tdd
- Rationale: The owner correction removed the home publisher. What remains is behavioral: the project mirror must stay, and a script that writes the CLI's home lookup paths must not. Each acceptance criterion is gated by a test that has been seen failing under its declared mutation.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: no new publisher. The correction deletes the home installer and locks the existing project mirror.
- User decision: inline
- Base ref: main
- Inline review scope: .aai/scripts/sync-harness-skills.mjs, .aai/system/HARNESS_SKILLS.yaml, .aai/system/PROFILES.yaml, tests/skills/test-aai-antigravity-project-skills.sh, tests/skills/suite-map.yaml, docs/issues/CHANGE-0196-antigravity-cli-skill-paths.md, docs/specs/SPEC-0194-spec-antigravity-cli-skill-paths.md

## Acceptance Criteria Mapping
- Maps to the owner correction on PR 407: skills stay in the project directory Antigravity CLI reads.
- Spec-AC-01: The in-repo path `.agents/skills/{skill_name}/SKILL.md` SHALL remain the Antigravity project surface, byte-identical to `.claude/skills/{skill_name}/SKILL.md` for a carried skill, and `node .aai/scripts/sync-harness-skills.mjs --check` SHALL exit 0.
- Spec-AC-02: This repository SHALL NOT copy or install skills into `~/.gemini/antigravity-cli/skills/` or `~/.gemini/skills/`. `publish-home-skills.mjs` SHALL NOT exist, PROFILES.yaml SHALL NOT list it, and no script under `.aai/scripts` SHALL name `antigravity-cli`.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | .agents/skills/{skill}/SKILL.md stays the project mirror and sync-harness-skills.mjs --check exits 0 | done | docs/ai/tdd/antigravity-cli-skill-paths/green-project-mirror.log | — | owner correction: project path only |
| Spec-AC-02 | no publisher writes ~/.gemini/antigravity-cli/skills or ~/.gemini/skills; publish-home-skills.mjs is absent | done | docs/ai/tdd/antigravity-cli-skill-paths/green-project-mirror.log | — | home paths are a CLI lookup table, not install targets |

## Implementation plan
- Keep `.claude/skills` as the only hand-authored source.
- Keep `.agents/skills` in `REQUIRED_MIRROR_TREES` and in `HARNESS_SKILLS.yaml` as `.agents/skills|carry|no`. Do not add a home tree to that list.
- Do not add `publish-home-skills.mjs`. Do not write `~/.gemini/antigravity-cli/skills` or `~/.gemini/skills`.
- The committed `.gemini/skills` directory is the Gemini CLI project mirror. It is not a user-home install and stays as it is.
- Do not add `.cursor/skills/`.
- Registry items closed by this scope: none.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---------|---------|------|----------------------|-------------|----------|--------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-antigravity-project-skills.sh | sync --check exits 0 and a source SKILL.md is byte-identical under .agents/skills | sed:s/REQUIRED_MIRROR_TREES = \['\.agents\/skills'/REQUIRED_MIRROR_TREES = ['.agents\/skills-off'/ | green |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-antigravity-project-skills.sh | publish-home-skills.mjs is absent, PROFILES.yaml does not list it, and no .aai/scripts file names antigravity-cli | sed:s/\.agents\/skills/.gemini\/antigravity-cli\/skills/ | green |

## Verification
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-antigravity-project-skills.sh` exits 0.
- `node .aai/scripts/sync-harness-skills.mjs --check` exits 0.
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0194-spec-antigravity-cli-skill-paths.md` is advisory.

## Evidence contract
- ref_id: antigravity-cli-skill-paths
- Each Spec-AC maps to the TEST row above. Green evidence is the suite log. Mutation records live under docs/ai/tdd/spec-antigravity-cli-skill-paths/.

### Evidence by strategy

| Strategy | Evidence this spec may demand |
|----------|--------------------------------|
| tdd / hybrid | stored RED artifact per AC-gating test (docs/ai/tdd/) plus the full verification matrix — unchanged |
| loop | per-TEST-xxx green runs; RED-proof observed, storage optional |
| direct | targeted regression tests green (exit codes) plus the scoped diff — NO stored RED artifact, NO matrix beyond the declared versions |
| untested | the recorded strategy rationale plus the scoped diff — no test suites demanded for the scope itself |
