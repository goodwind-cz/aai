---
id: release-notes-gate
type: product
capability: release-notes-gate
status: current
delivered_by:
  - release-notes-gate
spec: docs/specs/SPEC-0229-spec-release-notes-gate.md
updated: 2026-10-13
---

# Release notes gate

## What it does

A pull request that changes a shipped surface must add a new unreleased changelog entry, or say why it has no notes. Shipped surfaces are the AAI layer, GitHub workflows, harness skill trees, and root executables. Documentation, tests, and evidence-only changes are exempt. An old unchanged entry, an empty scaffold, and a blank reason do not count.

## How to use it

`/aai-pr` runs the check on the staged patch and the final proposed pull request body before commit or push. To skip notes, put one line in that body: `no-notes: <reason>`. The reason must contain text after the colon. CI runs the same check on the pull request range and body. An operator may mark the `release notes` job required. This repository does not change branch protection.

## Data model

None.

## Interfaces and contracts

`node .aai/scripts/release-notes-gate.mjs --staged --body-file <path>` checks the index. `node .aai/scripts/release-notes-gate.mjs --base <sha> --head <sha> --body-file <path>` checks a commit range. Exit 0 prints a PASS line. Exit 1 prints `REFUSED: release-notes` and does not execute the body. `isShipped` and `hasNoNotesReason` are exports of that module.

## Limits and non-goals

The gate does not merge a pull request and does not cut a release. It does not classify already-merged release ranges. A missing Git history or an unreadable body fails closed.

## Links

- Request: docs/issues/CHANGE-0211-release-notes-gate.md
- Spec: docs/specs/SPEC-0229-spec-release-notes-gate.md
- Validation evidence: docs/ai/reports/VALIDATION-20261013T235143Z-release-notes-gate.md
