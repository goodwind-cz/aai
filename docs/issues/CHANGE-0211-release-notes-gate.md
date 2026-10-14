---
id: release-notes-gate
type: change
number: 211
status: done
links:
  pr:
    - 465
  commits: []
---

# Change: notes gate for shipped-surface pull requests

## Summary
Every pull request that changes a shipped surface must add an `## [unreleased]`
entry or carry an explicit `no-notes: <reason>` marker. The check runs locally
in `/aai-pr` and as a CI job. This ride owns the shared classifier and marker
rules. It is the first half of the split of `release-one-command-no-findings`.

## Motivation / Business Value
The v2026.10.12 release found missing changelog notes only at cut time. The
combined ride then failed two validation rounds. The owner chose to split it
on 2026-10-13. This half closes the notes gap at PR time so a later release
ride can consume one classifier instead of a second copy.

## Scope
- In scope:
  - A dependency-free notes gate. Shipped surfaces include `.aai/**`,
    `.github/**`, root executable scripts, and harness skill/agent trees
    (`.claude/**`, `.codex/**`, `.agents/**`, `.gemini/**`). Docs-only,
    test-only, and evidence-only diffs are exempt.
  - The gate reads the compared patch and the PR body. Added notes must be
    new rollable text. A `no-notes:` marker needs a non-empty reason. An
    unreadable body or history fails closed. Body text is data, never executed.
  - Local `/aai-pr` checks the staged patch and the proposed body before push.
    A pull_request CI job checks the PR commit range and body.
  - The shared shipped-surface classifier and marker parser live in one module
    that a later release ride can import. This ride does not classify merged
    release ranges and does not merge anything.
  - Prompt, profile, suite-map, and user/technology notes for this gate only.
- Out of scope:
  - Release dry-run, confirm, merge, tag, workflow watch, branch cleanup, and
    PowerShell capture. Those belong to `release-finish-one-command`.
  - Changing branch protection in the remote repository. Document how an
    operator makes the check required.

## Affected Area
- `.aai/scripts/release-notes-gate.mjs` and the shared classifier module it
  exports
- `.aai/SKILL_PR.prompt.md` step 3b
- `.github/workflows/skill-suite.yml` or the PR workflow job that runs the gate
- `tests/skills/test-aai-release-notes.sh`
- profile, suite-map, CHANGELOG, and the prompt-diet ledger entries for this gate

## Desired Behavior (To-Be)
A pull request that changes a shipped surface and has neither a new unreleased
entry nor a non-empty `no-notes:` reason fails locally and in CI. A pull
request with either passes. A docs-only pull request passes without a notes
entry. The classifier is importable by the release ride without duplicating
the marker rules.

## Acceptance Criteria
- AC-001: A diff that changes a shipped surface without a new nonempty
  `## [unreleased]` entry or a nonempty `no-notes:` marker fails the gate,
  both locally in `/aai-pr` and in CI. A diff with either passes. A docs-only
  diff passes. An empty marker, an unchanged old section, and a bare scaffold
  fail.
- AC-002: The shipped-surface decision and the marker parser are one module.
  The release-finish ride is not modified to copy those rules.
- AC-003: Prompt, profile, suite-map, and technology/user notes describe this
  gate and pass the prompt-diet checkpoint for the files this ride edits.

## Verification
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release-notes.sh`
- The prompt-diet and profile checks named by the frozen child spec.

## Constraints / Risks
- Parent evidence stays in the worktree
  `/private/tmp/aai-release-one-command-worktree` and in
  `docs/ai/reports/VALIDATION-20261013T220533Z-release-one-command-no-findings.md`.
  That tree is preserved, not a license to commit the release-finish half.
- The marker must stay cheap so internal-only rides are not blocked by ceremony.
- Prompt-corpus governance applies to edited `.aai` prompts.

## Notes
- Split from `release-one-command-no-findings` by owner decision
  `docs/decisions/DECISION-release-one-command-no-findings-split.md`.
- Sibling, not started here: `release-finish-one-command`.
