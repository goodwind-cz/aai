---
id: ci-node-24-baseline
type: change
number: null
status: draft
capability: ci-feedback-speed
parent: smaller-node-core-and-faster-feedback
links:
  pr: []
  commits: []
---

# Move CI to Node 24 and publish the supported Node floor

## Summary
- Every Node step in CI is pinned to Node 20 (`actions/setup-node@v4` with
  `node-version: '20'`: 1 in close-gate.yml, 2 in docs-numbering.yml, 8 in
  skill-suite.yml). Node 20 is end-of-life.
- RFC-0017 owner decision 2 (2026-10-22): Node 24 is the development and CI
  baseline; Node 22 stays supported downstream until an announced transition;
  Node 20 is dropped from CI.
- No supported Node floor is declared anywhere: docs/TECHNOLOGY.md records it
  as UNKNOWN, and doctor does not check the Node version.
- RFC-0017 step 4 of the owner-approved order.

## Motivation / Business Value
- CI tests on an end-of-life runtime that neither developers nor downstream
  projects should run.
- Downstream projects get no signal when their Node is below what AAI
  supports, so a too-old runtime fails later and less clearly.

## Scope
- In scope:
  - Switch every `node-version: '20'` in .github/workflows to Node 24.
  - Keep Node 22 working downstream: add a minimal Node 22 compatibility
    check only if it fits inside an existing job (RFC-0017 decision 4: no
    extra runner unless it saves more than two minutes). Otherwise record the
    Node 22 floor as documented-only and say so.
  - Declare the floor in docs/TECHNOLOGY.md: Node 24 baseline, Node 22
    minimum supported downstream, Node 20 unsupported.
  - Make doctor report a Node major below the supported floor (advisory WARN,
    never a hard failure), so downstream users see it.
  - Update the RFC-0017 phase/order table to mark this step.
  - Fix stale "Node 20" comments in tooling (for example ci-select.mjs).
- Out of scope:
  - Using Node 24-only language or stdlib features in shipped `.aai/` code
    (Node 22 must keep working).
  - Windows jobs that use the runner's preinstalled Node (ps1-quality.yml,
    native-worktree-seed): unchanged unless Planning finds they pin Node 20.
  - Phases 3 to 5 of RFC-0017.

## Affected Area
- .github/workflows/{close-gate,docs-numbering,skill-suite}.yml
- docs/TECHNOLOGY.md
- .aai/scripts/aai-doctor.mjs (and its tests)
- docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md

## Desired Behavior (To-Be)
- All Linux CI jobs run on Node 24; no workflow references Node 20.
- The supported floor is written in one place (docs/TECHNOLOGY.md) and doctor
  warns when the running Node is below it.
- Node 22 support is either exercised by a check in an existing job or
  explicitly recorded as documented-only.

## Acceptance Criteria
- AC-001: No file under .github/workflows sets a Node version other than 24
  (except a Node 22 compatibility step, if added); a test fails if Node 20 is
  reintroduced.
- AC-002: docs/TECHNOLOGY.md states Node 24 baseline, Node 22 minimum
  downstream, Node 20 unsupported, with no remaining UNKNOWN floor.
- AC-003: doctor reports WARN (not FAIL) with the running and minimum major
  when Node is below 22, and stays silent on 22 and above; covered by tests.
- AC-004: Node 22 compatibility is either run in an existing CI job without a
  new runner, or recorded as documented-only with the reason.
- AC-005: CI on the pull request is green on Node 24.

## Verification
- Command(s) and expected results:
  - `grep -rn "node-version" .github/workflows` lists only 24 (and the 22
    compatibility step, if added).
  - `node .aai/scripts/aai-doctor.mjs --json` on the dev machine shows no Node
    floor warning.
  - The doctor suite and the workflow guard test pass.
  - The pull request's checks pass.

## Constraints / Risks
- Node 24 may change behavior that tests depend on (for example stricter
  child-process or stream handling); CI on the pull request is the proof.
- A test that pins workflow content may need the new version.
- Doctor output is consumer-visible: merging needs the owner's merge menu.
- No secrets referenced.

## Notes
- Source: RFC-0017 "Owner decisions (2026-10-22)", decisions 1.4, 2 and 4.
- Assumption (autopilot default): the floor check lives in doctor only; no
  script refuses to run on an old Node.
- Also carried by this ride: the owner-directed merge of #493 (2026-10-23)
  signs the open amendment item fu-amend-spec-docs-audit-suite-speed.
