---
id: docs-audit-suite-speed
type: change
number: 220
status: done
capability: ci-feedback-speed
parent: smaller-node-core-and-faster-feedback
links:
  pr: []
  commits: []
---

# Make the always-on docs-audit suite measurably faster

## Summary
- `aai-docs-audit` is an always-on core suite and the largest single cost on
  ordinary pull requests: about 212 s on CI (tests/skills/suite-weights.tsv,
  five samples 159-217 s). Every pull request pays it.
- This child moves the costliest docs-audit logic groups from the Bash suite
  to direct `node:test` cases (the pattern proven by the body-lint pilot,
  PR #488) and keeps CLI, hook, predicate and real-corpus coverage in Bash.
- RFC-0017 phase 2, child 3. Replaces the parked content-only CI lane
  (branch change/content-only-ci-lane): Planning evidence showed 0 of the
  last 200 merged PRs would have qualified for that lane, while docs-audit
  dominates the docs-heavy PR critical path.

## Motivation / Business Value
- A faster always-on suite shortens CI feedback for every pull request, not a
  rare subset.
- The pilot measured a 71.6% lower median for the migrated cluster (2.0 s
  Bash vs 0.57 s Node per five groups); most Bash cost is per-case Git
  fixture repositories and CLI launches.

## Scope
- In scope:
  - Per-function cost profile of `tests/skills/test-aai-docs-audit.sh`
    (local and, where available, CI) to choose the batch by measured time,
    not by line count.
  - Migrate one batch of logic groups whose behavior is reachable through
    exported functions of `.aai/scripts/lib/docs-audit-core.mjs` (or a
    minimal new export) into `tests/skills/lib/` `node:test` files, run by
    the ordinary `aai-docs-audit` suite run and mapped in suite-map.
  - Preserve every migrated assertion (migration map: old group -> new Node
    case -> retained CLI/boundary owner), as in the pilot report.
  - Before/after measurement of the ordinary suite run (matched, local) and
    the hosted CI docs-audit duration, recorded in an analysis note and the
    suite-weights row.
- Out of scope:
  - The content-only CI lane (parked), Node 24 in CI, new runners or jobs.
  - Behavior changes to the docs-audit engine itself, beyond a minimal export
    needed to reach logic directly.
  - Migrating the whole suite in one ride; later batches are later children.

## Acceptance Criteria
- AC-001: A per-function cost profile of the docs-audit suite exists and the
  migrated batch is the set chosen by measured cost.
- AC-002: Each migrated Bash group is removed and its assertions exist in
  `node:test` cases with a migration map; no assertion is silently dropped.
- AC-003: The ordinary `aai-docs-audit` suite run still runs the Node cases
  and fails when any Node case fails.
- AC-004: Matched before/after measurement shows the ordinary suite run is
  at least 25% faster locally, and the hosted CI docs-audit duration is
  reported before and after.
- AC-005: CLI rendering, strict/report behavior, hooks, predicates and the
  real-corpus checks remain covered in Bash and pass.

## Verification
- `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-docs-audit.sh`
  passes before and after; the new Node files pass on their own.
- The analysis note's tables are recomputable from the recorded raw timings.

## Constraints / Risks
- Under-coverage is the main risk: a Bash group that also exercises the CLI
  path must keep a CLI owner after migration.
- Hosted CI runs a different Node version than local; report both.
- The suite-weights row and any pinned counts change with the suite; update
  them in the same ride.
- No secret is referenced.

## Notes
- Parent: docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md (phase 2).
- Prior child: docs/analysis/docs-audit-node-test-pilot.md (PR #488).
- Owner decision 2026-10-23: pivot child 3 from the content-only CI lane to
  docs-audit suite speed; migration proceeds in batches.
- Implementation mode: Planning decides (autopilot default).
