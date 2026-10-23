---
id: content-only-ci-lane
type: change
number: null
status: draft
capability: ci-feedback-speed
parent: smaller-node-core-and-faster-feedback
links:
  pr: []
  commits: []
---

# Content-only pull requests run content checks, not engine suites

## Summary
- A pull request whose diff touches only document content (docs prose, intake,
  spec, RFC, analysis and other Markdown outside the engine) runs the
  always-on content checks and skips the skill-suite engine regression legs.
  A diff that touches the engine (`.aai/`, `tests/`, `.github/`, scripts,
  shared libraries, protected paths) keeps today's selected/full behavior.
- RFC-0017 phase 2, second half ("split always-on content validation from
  engine regression"), third child in the owner-approved order of 2026-10-22.

## Motivation / Business Value
- A document-only pull request still waits for the selected skill suite: on
  PR #490 (RFC text only) the critical path was the selected skill-suite job at
  183 s, plus the native Windows worktree-seed leg at 94 s. RFC-0017's target
  for an ordinary document-only CI gate is a median of at most 60 s while
  retaining the actual content and corpus invariants.
- Most rides end with docs/ledger commits (close ceremony, sweep records,
  RFC/decision updates); each of those pushes re-runs engine suites that the
  diff cannot affect.

## Scope
- In scope:
  - A deterministic content-only classification of the PR diff, reusing the
    existing selection seam (`select-suites.mjs` / the `select` job) rather
    than a new service; it fails closed to the engine path on any path it
    cannot classify, on a protected path, or on any uncertainty.
  - A `content` mode in `.github/workflows/skill-suite.yml` that runs the
    content checks (docs-audit, doc numbering, spec/body lints, index
    freshness, release notes, tracked-ignored guard) and skips the skill-suite
    engine legs, the native worktree-seed leg and the self-hosting smoke; the
    `gate` job accepts the content mode as satisfied only when the content
    checks passed.
  - Before/after CI wall-time measurement for content-only pull requests
    (at least five representative runs each, median and worst, runner-seconds),
    recorded in an analysis note linked from RFC-0017.
- Out of scope:
  - Migrating further `test-aai-docs-audit.sh` groups to `node:test` (owner
    decision 2026-10-23: separate, batched children afterwards).
  - Node 24 in CI (next child), ps1-quality workflow behavior, release workflow.
  - Any change to what an engine-touching diff runs.

## Affected Area
- `.github/workflows/skill-suite.yml` (select and gate jobs, job conditions).
- `.aai/scripts/select-suites.mjs` (classification output) and its tests.
- Possibly `.github/workflows/docs-numbering.yml` / `close-gate.yml` only if a
  content check must move; Planning decides.

## Desired Behavior (To-Be)
- Content-only diff: CI runs only content checks; the required `gate` check
  is green when they pass; median wall time to a settled required check set is
  at most 60 s on the measured sample.
- Any engine, test, workflow, script, protected or unclassifiable path in the
  diff: behavior is unchanged from today (selected or full).
- Pushes to main and scheduled runs: unchanged (always full).

## Acceptance Criteria
- AC-001: For a diff containing only content paths, the select job emits the
  content mode and the engine skill-suite legs, native worktree-seed and
  self-hosting smoke are skipped, while docs-audit, numbering, release notes
  and tracked-ignored checks still run.
- AC-002: Any diff containing at least one non-content path (including
  `.aai/**`, `tests/**`, `.github/**`, `docs/ai/docs-audit.yaml` protected
  entries, ledgers that engine tests read, or an unknown path) never selects
  the content mode (fail closed), proven by table-driven cases.
- AC-003: The `gate` job fails when the content mode is selected and any
  content check failed or was skipped unexpectedly.
- AC-004: Push-to-main and scheduled events never use the content mode.
- AC-005: An analysis note records before/after wall time for content-only
  pull requests (at least five runs each; median, worst, runner-seconds), and
  RFC-0017's rollout table names this child.

## Verification
- `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-select-suites.sh`
  (or the suite that owns select-suites) passes with the new cases.
- A real content-only pull request shows the skipped engine legs and a green
  gate; a real engine pull request shows unchanged legs.

## Constraints / Risks
- Under-selection is the main risk: a doc that an engine test reads as a
  fixture or corpus (INDEX, ledgers, canon lists, templates, prompts) must not
  be classified as content. Fail closed; keep the classification list small
  and explicit.
- Branch protection names the required check; the gate job name must stay
  stable.
- Assumption: the extra-runner rule (owner decision: only for a saving above
  2 min) is not triggered; this child removes work, it adds no runner.

## Notes
- Parent: docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md (phase 2).
- Baseline evidence: PR #490 check durations (selected skill suite 183 s,
  native worktree seed 94 s, others 12-17 s).
- PARKED 2026-10-23 by owner decision after Planning: under the fail-closed v1
  content set (docs/rfc, docs/decisions, docs/project-sessions) 0 of the last
  200 merged PRs would have been content-only (every one also touched INDEX, a
  ledger, a spec, CHANGELOG or AAI_VERSION); widening to decisions.jsonl and
  docs/issues reaches only 12/200. The #490 183 s came mainly from the core
  suites, chiefly docs-audit, so RFC-0017 child 3 pivots to speeding up the
  docs-audit suite (benefits every PR). The frozen draft spec
  docs/specs/SPEC-DRAFT-spec-content-only-ci-lane.md is kept on branch
  change/content-only-ci-lane for a later widening ride.
