---
id: spec-hermes-agent-skill-discovery
type: spec
number: 259
status: done
frozen_sha256: 5e1c51a2bb337b6c23812d2226d2092c688461185004b6032b2d9f1dcd5b98d4
ceremony_level: 2
links:
  requirement: hermes-agent-skill-discovery
  rfc: null
  pr: []
  commits: []
---

# Hermes Agent discovery of the universal AAI catalog

SPEC-FROZEN: true

## Context and scope

Requirement: docs/issues/CHANGE-0234-hermes-agent-skill-discovery.md.
Technology contract: docs/TECHNOLOGY.md.

Expose the existing universal catalog through Hermes native skill selection using the already-generated `.agents/skills` tree. Deliver a documented setup and refresh procedure plus executable native integration coverage. No new catalog, home-directory installer, agent workflow, or Hermes-specific wrapper tree is needed. The supported installation is AAI's extended profile in a Git checkout; core-profile completeness is excluded because its existing missing-prompt issue is independently tracked. No global Hermes configuration or personal skills are modified by tests.

Registry items closed by this scope: none.
Related open `fu-sync-core-profile-dangling-wrappers` remains open: this scope explicitly supports extended installations and does not repair core pruning. `fu-sync-symlinked-tree-root`, `fu-sync-ps1-dangling-src-symlink`, and `fu-sync-invalid-utf8-names-linux` concern existing sync hardening, not this documentation/native-consumer integration; no new sync writer is introduced.

## Verified Hermes discovery contract

Planning inspected the installed Hermes source at revision `bf0203a794a07aac3ff764972ab9087baa4e4f4e`, under `/Users/ales/.hermes/hermes-agent`, on 2026-10-28 UTC. This exact source revision is the support baseline; package metadata says `0.0.0` and is not a meaningful compatibility version. Implementation must record the source revision actually used for native proof and disclose if different.

- `agent/skill_utils.py`: `PROJECT_SKILLS_SUBDIRS` includes `.hermes/skills` and `.agents/skills`. Project identity is the nearest `.git` ancestor (directory or worktree file), derived from the session working directory. Home itself is excluded.
- Project discovery requires that root in `skills.trusted_project_dirs` for the active Hermes profile, and is disabled by `skills.project_discovery: false`. Existing user disabling and quarantine decisions remain effective; setup never bypasses them.
- `hermes_cli/main_agent_cmds.py`, `_cmd_skills_trust`: `hermes skills trust [path]` records trust; repeating it reports already trusted. Use the intended profile when running this command. Explicit trust alone cannot substitute for the session's project working directory.
- `tools/skills_tool.py` and `hermes_cli/skills_hub.py`: native skill listing shares the tiered catalog; trusted project skills precede profile skills. Same-tier conflicting content can be ambiguous and must not be overwritten or hidden by AAI.
- `agent/skill_commands.py`: `get_interactive_skill_commands()` supplies the interactive slash-command map; `build_skill_invocation_message()` loads the selected wrapper. `reload_skills()` backs `/reload-skills`. A fresh session in the same project is the fallback refresh procedure.
- Existing `.agents/skills/aai-intake/SKILL.md` points to `.aai/SKILL_INTAKE.prompt.md` in the current project and diagnoses an absent prompt. No prompt duplication is needed.

Source inspection verifies the contract, not end-to-end delivery. A Planning launcher probe with an isolated HERMES_HOME triggered fresh dependency provisioning and was stopped after a network failure. Implementation must reuse a prepared runtime with an isolated data root; it must not install dependencies as a side effect of an ordinary regression run. No native completion claim is made here.

## Implementation strategy

- Strategy: loop
- Rationale: existing discovery and synchronization already provide the behavior; one focused pass adds documentation and native-consumer regression evidence without inventing a production adapter. Observe RED by controlled fixture mutations and missing documentation before recording green; storage of RED is optional for loop.

## Isolation and review

- Worktree recommendation: optional
- Worktree rationale: bounded documentation and tests; no protected production writer changes. Preparation applies the owner's existing isolation decision.
- User decision: undecided
- Base ref: main
- Inline review scope: docs/USER_GUIDE.md, SKILLS.md, README.md if its agent list needs a Hermes link, tests/skills/test-aai-hermes-skills.sh, tests/skills/lib/hermes-skills-smoke.py, tests/skills/suite-map.yaml, tests/skills/suite-weights.tsv, this spec, intake, CHANGELOG.md if appropriate.
- Code review required: true.

## Acceptance Criteria Mapping

| Requirement | Spec-AC | Verification and observable | Evidence |
|---|---|---|---|
| AC-001 | Spec-AC-01 | TEST-001/002: exact expected catalog set equals Hermes interactive command set restricted to managed names; every name has a nonempty description; untrusted project contributes zero managed entries | docs/ai/tdd/hermes-agent-skill-discovery-native.log |
| AC-002 | Spec-AC-02 | TEST-003: native slash expansion for aai-intake includes the current project's existing canonical prompt pointer; prompt exists and is read from that fixture, with no home-project substitution | docs/ai/tdd/hermes-agent-skill-discovery-native.log |
| AC-003 | Spec-AC-03 | TEST-004: two real extended syncs yield identical managed name sets; changed description appears after native reload with one entry per name | docs/ai/tdd/hermes-agent-skill-discovery-native.log |
| AC-004 | Spec-AC-04 | TEST-005: target-only project skill and unrelated isolated-profile skill remain byte-identical after repeated sync; existing generated trees pass their parity check | docs/ai/tdd/hermes-agent-skill-discovery-regression.log |
| AC-005 | Spec-AC-05 | TEST-006: documentation check finds version revision, project path, trust/profile, setup/update, reload, and supported/unsupported coverage; execute its procedure in native fixture | docs/ai/tdd/hermes-agent-skill-discovery-native.log |

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN an extended AAI Git project is trusted in the active profile, Hermes SHALL offer its supported managed skills once each in the native interactive command map with descriptions | done | docs/ai/reports/VALIDATION-hermes-independent-2.md | — | Untrusted baseline is empty |
| Spec-AC-02 | WHEN aai-intake is selected, Hermes SHALL load the existing wrapper directing the current project to .aai/SKILL_INTAKE.prompt.md | done | docs/ai/reports/VALIDATION-hermes-independent-2.md | — | Prove native expansion, no model-call dependency |
| Spec-AC-03 | WHEN setup or update repeats and skills reload, Hermes SHALL show one current entry per managed skill and refreshed descriptions | done | docs/ai/reports/VALIDATION-hermes-independent-2.md | — | Real producer and consumer |
| Spec-AC-04 | WHEN the documented update runs, unrelated project and profile skills SHALL remain byte-identical and existing mirrors SHALL pass parity | done | docs/ai/reports/VALIDATION-hermes-independent-2.md | — | No new writer |
| Spec-AC-05 | The usage guide SHALL identify the exact supported Hermes revision, trust and project requirements, extended setup/update commands, refresh procedure and coverage limits | done | docs/ai/reports/VALIDATION-hermes-independent-2.md | — | No unsupported broad version claim |

## Implementation plan

1. Add a concise Hermes section to docs/USER_GUIDE.md and discoverability links in SKILLS.md (README.md only if useful). Use existing POSIX and PowerShell extended sync commands; trust is a separate explicit Hermes action, never silently performed by AAI update. Explain active profile and current project/session workspace, `/aai-intake`, `/reload-skills`, and fresh-session fallback. Explain custom disabled/quarantined skills and same-name collisions as Hermes-controlled conditions. Older revisions are unverified; core installations are outside this support baseline. Deprecated wrappers may remain listed with their existing deprecation descriptions; do not claim their retired semantics work.
2. Add one focused shell suite and optional Python smoke helper under tests/skills, with parameters for prepared Hermes source/runtime. Derive expected names/descriptions from the existing generated catalog and its manifest exclusions; never hard-code a second inventory. Standard CI may explicitly report native evidence unavailable when Hermes is absent, but that is not native PASS and cannot satisfy this scope's validation.
3. In one disposable scratch Git project and isolated Hermes home, invoke real AAI extended sync, the native trust handler/CLI, native listing, interactive command discovery and native invocation builder. Pin actual runtime/source identity in evidence. Call real native functions rather than reproducing discovery in a mock. No LLM inference, credentials, or external service call is required to prove wrapper selection. Do not launch intake's downstream workflow as a test.
4. Perform repeat-sync, metadata refresh, and unrelated-skill preservation checks in that same scratch copy. Test a nested working directory. Refresh using the native reload implementation; verify its binding to the CLI command. If live UI is available, capture menu/selection as additional evidence; the native interactive map and selection expansion remain the executable assertion boundary.
5. Register test selection and measured suite weight as needed. Production sync/generator edits are not planned: a discovered defect requires a concrete spec amendment before widening scope.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-hermes-skills.sh | Untrusted project has no managed commands; trust activates exact supported catalog and descriptions using native listing and interactive map | Remove trust in disposable profile and require trusted assertion to fail | green |
| TEST-002 | Spec-AC-01 | integration | tests/skills/test-aai-hermes-skills.sh | Discover from nested project cwd; derive expected names from source and manifest, reject duplicates and unintended exclusions | Delete one generated wrapper only in scratch and require expected-set assertion to fail | green |
| TEST-003 | Spec-AC-02 | integration | tests/skills/test-aai-hermes-skills.sh | Native aai-intake selection expands real wrapper pointing to existing fixture canonical intake prompt | Replace intake wrapper pointer with nonexistent prompt in scratch and require resolution assertion to fail | green |
| TEST-004 | Spec-AC-03 | integration | tests/skills/test-aai-hermes-skills.sh | Real repeated sync plus native reload refreshes changed metadata exactly once | Skip second sync in scratch and require changed-description assertion to fail | green |
| TEST-005 | Spec-AC-04 | integration | tests/skills/test-aai-hermes-skills.sh | Real sync preserves target-only project/profile entries and checks existing mirror parity | Alter unrelated fixture skill bytes and require preservation assertion to fail | green |
| TEST-006 | Spec-AC-05 | contract | tests/skills/test-aai-hermes-skills.sh | Guide declares and native smoke follows supported revision, trust/profile and workspace, extended setup/update and reload procedure | Remove Hermes guide section in scratch and require documentation assertion to fail | green |

## Verification

Run `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-hermes-skills.sh` with the documented native source/runtime arguments or environment. Exit 0 with six executed tests and no native skip is required for this scope. Run `node .aai/scripts/sync-harness-skills.mjs --check` (exit 0), plus relevant existing sync and harness regressions selected by suite-map. For Windows use `powershell -NoProfile -File .aai/scripts/aai-run-tests.ps1 bash tests/skills/test-aai-hermes-skills.sh` under the existing dispatcher contract. Native Hermes evidence is required on the observed macOS installation; do not infer Windows Hermes runtime support from POSIX proof. Unmodified paired sync scripts retain their existing platform contract; execute Windows-specific regression only if a paired script is changed after amendment.

Record six per-test GREEN results, observed negative controls, source SHA, command line, fixture workspace, no-credential runtime setup, and exit codes. Store authoritative logs under docs/ai/tdd/ and a Validation report with aai-outcome-v1. No native-runtime availability means that portion is BLOCKED, not a silently green skip.

## Evidence contract

Every artifact names ref_id `hermes-agent-skill-discovery`, Spec-AC/TEST mappings, command or review scope, exit code or verdict, evidence path, and compared revision/diff where available. Loop requires per-test green evidence and observed RED controls; storing RED is optional. A failed native bootstrap is diagnostic evidence, never proof of skill behavior.

Seams tested: generated universal wrapper -> real Hermes native menu (TEST-001/002); native selection -> project-local canonical entrypoint (TEST-003); real sync -> cache reload -> menu metadata (TEST-004); managed sync -> unrelated project/profile content and other mirrors (TEST-005); published instructions -> native procedure (TEST-006). Residual risk: no model completion is asserted, native interactive-map proof is not a screenshot of every Hermes UI, and versions other than the recorded revision and Windows-native Hermes are unverified.
