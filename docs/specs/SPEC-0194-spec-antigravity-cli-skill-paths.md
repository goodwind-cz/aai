---
id: spec-antigravity-cli-skill-paths
type: spec
number: 194
status: implementing
mutation_gate: v1
frozen_sha256: dd882522c04fd0457831e26561c07dd7239c2e64be129b323e6767ba4889954e
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0196-antigravity-cli-skill-paths.md
  rfc: null
  pr: []
  commits: []
---

# Spec — publish AAI skills onto the Antigravity CLI home paths

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0196-antigravity-cli-skill-paths.md
- Technology contract: docs/TECHNOLOGY.md
- Existing project mirror: .aai/scripts/sync-harness-skills.mjs and .aai/system/HARNESS_SKILLS.yaml

## Implementation strategy
- Strategy: tdd
- Rationale: The intake left the mode to Planning and recommended full TDD. The change is behavioral and crosses two home trees plus the existing project mirror. Each acceptance criterion needs a RED observation before the publisher exists, then a green run of the same command.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: one new publisher, one suite, and a profiles row. No protected surface. A dedicated branch is enough.
- User decision: inline
- Base ref: main
- Inline review scope: .aai/scripts/publish-home-skills.mjs, .aai/system/PROFILES.yaml, tests/skills/test-aai-home-skills.sh, tests/skills/suite-map.yaml, docs/issues/CHANGE-0196-antigravity-cli-skill-paths.md, docs/specs/SPEC-0194-spec-antigravity-cli-skill-paths.md, docs/ai/EVENTS.jsonl

## Acceptance Criteria Mapping
- Maps to: the intake acceptance criteria for the three Antigravity locations.
- Spec-AC-01: WHEN `--check` runs against a home that has neither destination, the publisher SHALL exit 1 and name both `.gemini/antigravity-cli/skills` and `.gemini/skills`.
- Spec-AC-02: WHEN `--write` runs, the publisher SHALL create `{home}/.gemini/antigravity-cli/skills/{skill}/SKILL.md` and `{home}/.gemini/skills/{skill}/SKILL.md` for every `.claude/skills/{skill}/SKILL.md`, byte-identical to the source, and no other skill directory.
- Spec-AC-03: WHEN `--write` runs a second time against an unchanged source, `--check` SHALL exit 0 and both trees SHALL stay byte-identical to the first write.
- Spec-AC-04: WHEN `GEMINI_HOME`, `CLAUDE_CONFIG_DIR`, and `CODEX_HOME` point elsewhere, the publisher SHALL write only under the explicit `--home` and SHALL leave the project `.agents/skills` tree unchanged.
- Spec-AC-05: WHEN the publisher has written a fixture home, `node .aai/scripts/sync-harness-skills.mjs --check` SHALL still exit 0.
- Spec-AC-06: WHEN the new script exists, `.aai/system/PROFILES.yaml` SHALL list it, so the layer-profile union stays exact.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN --check runs on a home missing both trees the publisher SHALL exit 1 and name .gemini/antigravity-cli/skills and .gemini/skills | done | docs/ai/tdd/antigravity-cli-skill-paths/green-suite.log | — | red: docs/ai/tdd/antigravity-cli-skill-paths/red-test_001_check_names_both_missing_trees.log |
| Spec-AC-02 | WHEN --write runs the publisher SHALL copy every source SKILL.md byte-identical into both home trees and create no extra skill directory | done | docs/ai/tdd/antigravity-cli-skill-paths/green-suite.log | — | red: docs/ai/tdd/antigravity-cli-skill-paths/red-test_002_write_copies_both_trees.log |
| Spec-AC-03 | WHEN --write runs again on an unchanged source --check SHALL exit 0 and both trees SHALL stay byte-identical | done | docs/ai/tdd/antigravity-cli-skill-paths/green-suite.log | — | red: docs/ai/tdd/antigravity-cli-skill-paths/red-test_003_second_write_is_idempotent.log |
| Spec-AC-04 | WHEN GEMINI_HOME CLAUDE_CONFIG_DIR and CODEX_HOME point elsewhere the publisher SHALL write only under --home and SHALL leave .agents/skills unchanged | done | docs/ai/tdd/antigravity-cli-skill-paths/green-suite.log | — | red: docs/ai/tdd/antigravity-cli-skill-paths/red-test_004_ignores_harness_env_and_project_mirror.log |
| Spec-AC-05 | WHEN a fixture home was written sync-harness-skills.mjs --check SHALL still exit 0 | done | docs/ai/tdd/antigravity-cli-skill-paths/green-suite.log | — | red: docs/ai/tdd/antigravity-cli-skill-paths/red-test_005_project_mirror_check_still_passes.log |
| Spec-AC-06 | WHEN the new script exists PROFILES.yaml SHALL list it | done | docs/ai/tdd/antigravity-cli-skill-paths/green-suite.log | — | red: docs/ai/tdd/antigravity-cli-skill-paths/red-test_006_profiles_lists_the_script.log |

## Implementation plan
- Add `.aai/scripts/publish-home-skills.mjs`. Source is `<root>/.claude/skills/*/SKILL.md`. Destinations under `--home` are `.gemini/antigravity-cli/skills` and `.gemini/skills`. `--home` is required. `--root` defaults to the repo. `--check` and `--write` match the sync-harness-skills exit contract (0 clean, 1 divergence, 2 usage).
- Copy each `SKILL.md` byte-identical (the `.agents/skills` carry rule). On `--write`, remove skill directories that are not in the source. Do not write a README. Do not read `HOME`, `GEMINI_HOME`, `CLAUDE_CONFIG_DIR`, or `CODEX_HOME`.
- Classify the script in `.aai/system/PROFILES.yaml` `core:`.
- Do not add the home trees to `REQUIRED_MIRROR_TREES`. Do not add `.cursor/skills/`.
- Registry items closed by this scope: none.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---------|---------|------|----------------------|-------------|----------|--------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-home-skills.sh | --check on an empty fixture home exits 1 and names both destination trees | sed:s/antigravity-cli/antigravity-cli-off/ | green |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-home-skills.sh | --write copies every fixture skill byte-identical into both trees and no extra directory | sed:s/copyFileSync/copyFileSyncOff/ | green |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-home-skills.sh | a second --write then --check exits 0 and the tree hashes match the first write | sed:s/return dest;/fs.appendFileSync(dest, "x"); return dest;/ | green |
| TEST-004 | Spec-AC-04 | integration | tests/skills/test-aai-home-skills.sh | GEMINI_HOME CLAUDE_CONFIG_DIR and CODEX_HOME are ignored and .agents/skills is untouched | sed:s/path\.join\(home, treeRel/path.join(process.env.GEMINI_HOME, treeRel/ | green |
| TEST-005 | Spec-AC-05 | integration | tests/skills/test-aai-home-skills.sh | after a fixture write, sync-harness-skills.mjs --check still exits 0 | sed:s/REQUIRED_MIRROR_TREES = \['\.agents\/skills'/REQUIRED_MIRROR_TREES = ['.agents\/skills-off'/ | green |
| TEST-006 | Spec-AC-06 | integration | tests/skills/test-aai-home-skills.sh | PROFILES.yaml core list contains publish-home-skills.mjs | sed:s/publish-home-skills\.mjs/publish-home-skills-off.mjs/ | green |

## Verification
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-home-skills.sh` exits 0.
- `node .aai/scripts/sync-harness-skills.mjs --check` exits 0.
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0194-spec-antigravity-cli-skill-paths.md` is advisory.

## Evidence contract
- ref_id: antigravity-cli-skill-paths
- Each Spec-AC maps to the TEST row above. RED logs live under docs/ai/tdd/antigravity-cli-skill-paths/. Green evidence is the suite exit code.

### Evidence by strategy

| Strategy | Evidence this spec may demand |
|----------|--------------------------------|
| tdd / hybrid | stored RED artifact per AC-gating test (docs/ai/tdd/) plus the full verification matrix — unchanged |
| loop | per-TEST-xxx green runs; RED-proof observed, storage optional |
| direct | targeted regression tests green (exit codes) plus the scoped diff — NO stored RED artifact, NO matrix beyond the declared versions |
| untested | the recorded strategy rationale plus the scoped diff — no test suites demanded for the scope itself |
