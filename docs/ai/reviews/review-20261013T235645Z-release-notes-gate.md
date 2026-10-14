---
review:
  scope: >-
    .aai/scripts/release-notes-gate.mjs .aai/SKILL_PR.prompt.md
    .aai/system/PROFILES.yaml .github/workflows/skill-suite.yml
    tests/skills/test-aai-release-notes.sh tests/skills/suite-map.yaml
    tests/skills/lib/prompt-diet-ledger.sh tests/skills/test-aai-prompt-diet.sh
    tests/skills/test-aai-pr-preflight.sh tests/skills/test-aai-hygiene-pack.sh
    tests/skills/test-aai-suite-select.sh tests/skills/lib/cd-subshell-leak-baseline.tsv
    docs/TECHNOLOGY.md docs/USER_GUIDE.md docs/product/release-notes-gate.md
    CHANGELOG.md docs/issues/CHANGE-0211-release-notes-gate.md
    docs/specs/SPEC-0229-spec-release-notes-gate.md
    docs/decisions/DECISION-release-one-command-no-findings-split.md
    docs/ai/roadmap.yaml
  spec: docs/specs/SPEC-0229-spec-release-notes-gate.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - ac: Spec-AC-01
        call: compliant
        citation: ".aai/scripts/release-notes-gate.mjs:71 checkNotes; tests/skills/test-aai-release-notes.sh TEST-001..003; docs/ai/tdd/release-notes-gate-validation-notes.log"
      - ac: Spec-AC-02
        call: compliant
        citation: ".aai/scripts/release-notes-gate.mjs:8 isShipped and :13 hasNoNotesReason; TEST-004 asserts exports and that release-finish.mjs is absent"
      - ac: Spec-AC-03
        call: compliant
        citation: ".aai/SKILL_PR.prompt.md step 3b; PROFILES.yaml release-notes-gate.mjs; suite-map aai-release-notes; prompt-diet ledger +259; validation diet and profiles logs exit 0"
  code_quality:
    verdict: pass
    findings:
      - rank: NON-BLOCKING
        file: .github/workflows/skill-suite.yml
        line: 93
        issue: "pull_request types gained edited on the shared workflow trigger, so a body or title edit re-runs every job, not only release-notes."
        failure_scenario: "An operator edits the PR body to add no-notes: reason. GitHub re-runs select and the full suite as well as the notes job."
  cannot_verify:
    - claim: "The hosted release notes job runs on pull_request opened, synchronize, reopened, and edited."
      closes_with: "A green GitHub Actions run of the release notes job on this pull request."
  overall: pass
---

# Code review — release-notes-gate

Spec: docs/specs/SPEC-0229-spec-release-notes-gate.md. Diff is the uncommitted worktree against main. The finish half is absent: no release-finish.mjs, and no edits to the release engines, release.yml, or ps1-quality.yml.

## Spec compliance

Spec-AC-01. `checkNotes` refuses when a shipped path is present and neither a nonempty `no-notes:` reason nor newly added rollable unreleased text exists. Staged and base/head use the same function. TEST-001..003 passed in docs/ai/tdd/release-notes-gate-validation-notes.log.

Spec-AC-02. `isShipped` and `hasNoNotesReason` are exports. TEST-004 imports them and checks an `.aai` path, a mode-100755 root file, and a non-executable README. `release-finish.mjs` is not in the tree and not in PROFILES.

Spec-AC-03. SKILL_PR step 3b names `release-notes-gate.mjs --staged --body-file`. The profile lists the script. The suite map adds `aai-release-notes`. The prompt-diet ledger credits +259 and the diet suite passed.

## Code quality

No blocking defect. The gate reads the body with `readFileSync` and never evals it. Git failures and a missing body throw, and the CLI prints `REFUSED: release-notes` and exits 1. Both old and new diff modes are passed to `isShipped`, so a deleted mode-100755 root file stays shipped. `--no-renames` and `-z` keep paths intact.

NON-BLOCKING: `.github/workflows/skill-suite.yml` line 93 adds `edited` to the workflow-level `pull_request` types. GitHub has no per-job event filter, so a body edit re-runs the whole workflow. The notes job itself is correctly limited to `pull_request` and writes the event body as data before calling the gate. Disposition: accept for this ride. Skipping unrelated jobs on `edited` is a follow-up, not a notes-gate defect.

## Cannot verify

Hosted execution of the new job. Local workflow text, permissions (`contents: read`, `pull-requests: read`), fetch-depth 0, and the ci-carry-forward suite cover the file. They do not replace a GitHub run.

## Next

Overall pass. No blocking finding. Close and open the pull request after the framework sweep. Do not merge.
