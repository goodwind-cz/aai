---
id: spec-release-notes-gate
type: spec
number: 229
status: done
frozen_sha256: 59a6d614537a5dcda1fd66703f75a6fccf6471880870235dba5649ae1ae18d82
ceremony_level: 2
links:
  requirement: release-notes-gate
  rfc: null
  pr: []
  commits: []
---

# Notes gate for shipped-surface pull requests

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0211-release-notes-gate.md
- Parent split: docs/decisions/DECISION-release-one-command-no-findings-split.md
- Technology contract: docs/TECHNOLOGY.md

## Implementation strategy
- Strategy: loop
- Rationale: one focused pass over a real Git notes gate, the `/aai-pr` call, and the pull_request CI job. Observe each new assertion fail on the pre-change tree, then keep the green integration log. No TDD mutation gate.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: the change touches a prompt, a workflow, and a new script; keep it off main and off the preserved combined release branch.
- User decision: undecided
- Base ref: main
- Inline review scope: .aai/scripts/release-notes-gate.mjs .aai/SKILL_PR.prompt.md .aai/system/PROFILES.yaml .github/workflows/skill-suite.yml tests/skills/test-aai-release-notes.sh tests/skills/suite-map.yaml tests/skills/lib/prompt-diet-ledger.sh tests/skills/test-aai-prompt-diet.sh docs/TECHNOLOGY.md docs/USER_GUIDE.md CHANGELOG.md docs/issues/CHANGE-0211-release-notes-gate.md docs/specs/SPEC-0229-spec-release-notes-gate.md
- Do not edit release-finish, aai-release engines, release.yml, or ps1-quality.yml.

## Constitution deviations

None.

## Acceptance Criteria Mapping

| Requirement | Spec-AC | Verification | Observable |
|-------------|---------|--------------|------------|
| AC-001 | Spec-AC-01 | N, TEST-001..003 | Missing notes refuse; added notes or a nonempty marker pass; docs-only passes |
| AC-002 | Spec-AC-02 | N, TEST-004 | isShipped and hasNoNotesReason export from the gate module; release-finish.mjs is absent |
| AC-003 | Spec-AC-03 | D, TEST-005 | Prompt step names the gate; profile lists the new script; prompt-diet checkpoint passes |

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN a diff changes a shipped surface the notes gate SHALL exit nonzero unless the diff adds a nonempty rollable unreleased entry or the body contains an explicit nonempty no-notes reason; local staged input and the CI base/head input run the same module | done | docs/ai/tdd/release-notes-gate-validation-notes.log | — | TEST-001..003 |
| Spec-AC-02 | The shipped-surface decision and the no-notes marker parser SHALL be exports of release-notes-gate.mjs, and this ride SHALL not add release-finish.mjs | done | docs/ai/tdd/release-notes-gate-validation-notes.log | — | TEST-004 |
| Spec-AC-03 | SKILL_PR step 3b, PROFILES, the suite map, and the prompt-diet ledger SHALL describe this gate and pass their existing checkpoints | done | docs/ai/tdd/release-notes-gate-validation-diet.log | — | TEST-005 |

## Implementation plan

1. Add `.aai/scripts/release-notes-gate.mjs` (Node stdlib only). Shipped surfaces are `.aai/**`, `.github/**`, `.claude/**`, `.codex/**`, `.agents/**`, `.gemini/**`, and root files that are mode 100755 or have an executable-script extension. Docs, tests, and evidence-only diffs are exempt. Added notes come from the compared patch, not an unchanged old section or a bare scaffold. `no-notes:` needs one non-whitespace character after the colon. Missing history or an unreadable body fails with context. Never execute body text.
2. `/aai-pr` step 3b runs `node .aai/scripts/release-notes-gate.mjs --staged --body-file <pr-body-file>` on the final proposed body before commit or push, and CI runs the same module with `--base` and `--head` on `pull_request` (including `edited`). Document that operators may mark the check required. Do not change remote branch protection.
3. Classify the new script in PROFILES. Map it, the prompt, the workflow, and the test to a suite. True-up the prompt-diet ledger for the SKILL_PR edit. Add a CHANGELOG unreleased entry for this gate only.
4. Do not copy the classifier into a release engine and do not modify release finish.

Registry items closed by this scope: none. Open changelog-preamble follow-ups stay open; they are wording, not this gate.

## Seams and residual risks

- S1: a real Git index or commit range enters the notes-gate CLI, and the CLI's exit is what the test asserts (TEST-001..003).
- S2: the same module's exports are what a later release ride imports (TEST-004).
- Hosted CI execution of the new job is outside this development ride. The workflow file is asserted by the suite; the job itself runs on GitHub.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---------|---------|------|----------------------|-------------|----------|--------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-release-notes.sh | Shipped diff without notes refuses staged and range entrypoints; old unchanged entry and blank scaffold refuse | Bypass gate refusal | pending |
| TEST-002 | Spec-AC-01 | integration | tests/skills/test-aai-release-notes.sh | Newly added nonempty notes or a nonempty body marker passes; empty marker refuses; docs-only passes | Treat empty marker as valid | pending |
| TEST-003 | Spec-AC-01 | integration | tests/skills/test-aai-release-notes.sh | Staged and base/head commands agree on one fixture; unreadable body and missing history fail; body stays data | Remove one entrypoint | pending |
| TEST-004 | Spec-AC-02 | integration | tests/skills/test-aai-release-notes.sh | isShipped and hasNoNotesReason are exports; release-finish.mjs is not in the tree; PROFILES lists the gate script only | Duplicate the classifier into a second file | pending |
| TEST-005 | Spec-AC-03 | contract | tests/skills/test-aai-prompt-diet.sh | SKILL_PR names the gate command; suite-map and PROFILES contain the new script; prompt-diet checkpoint passes | Restore the old changelog-only step 3b | pending |

## Verification

- N: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release-notes.sh`
- D: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh` and `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-layer-profiles.sh`
- PASS requires TEST-001..005 green. Record the pre-change RED observation in docs/ai/tdd/release-notes-gate-red.log and the green run in docs/ai/tdd/release-notes-gate-green.log.

## Evidence contract

- Record ref_id, TEST id, command, and exit code. Strategy is loop: store the RED observation and the green log. Do not claim a mutation-gate contract.
- Validation writes one aai-outcome-v1 report. Code review is required over the inline review scope above. This ride does not merge and does not cut a release.
