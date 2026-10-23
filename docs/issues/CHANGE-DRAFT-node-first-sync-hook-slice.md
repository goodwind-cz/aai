---
id: node-first-sync-hook-slice
type: change
number: null
status: draft
capability: node-first-core
parent: smaller-node-core-and-faster-feedback
links:
  pr: []
  commits: []
---

# Move the first sync/hook behavior from paired Bash and PowerShell scripts to one Node module

## Summary
- RFC-0017 phase 3: migrate common sync/hook behavior to Node in small slices,
  with native platform parity, and retire the superseded counterparts.
- Today 18 behaviors exist twice, once as `.aai/scripts/<name>.sh` and once as
  `<name>.ps1` (about 9,300 lines together). Every fix has to be made, reviewed
  and tested twice, and the two copies drift.
- This change delivers the first slice: one paired behavior becomes one
  importable Node module, with the `.sh` and `.ps1` files kept only as thin
  launchers (or removed where no caller needs them).

## Motivation / Business Value
- One implementation per behavior halves the maintenance and review cost of
  that behavior and removes a class of Bash/PowerShell drift bugs.
- Node-level logic can be tested with `node:test` directly instead of through
  two shell suites, which also shortens CI.
- The first slice sets the pattern (module layout, launcher shape, parity
  evidence, retirement) that later slices reuse.

## Scope
- In scope:
  - Planning picks ONE pair for the first slice, by measured evidence:
    duplicated lines, how often it runs (every commit, every sync, rarely),
    bug or drift history between the two copies, and how much
    platform-specific behavior it contains. Candidates, smallest first:
    validate-skills, live-spool, triage, pre-compact-save, pre-commit-checks,
    migrate-yaml-to-jsonl, aai-update. Out of bounds for this first slice:
    process supervision (aai-run-tests, aai-reap-tests, autonomous-loop) and
    the two largest pairs (aai-sync, install-pre-commit-hook), unless Planning
    shows a small self-contained part of them is the better first slice.
  - The behavior moves into an importable, dependency-free ESM module under
    `.aai/scripts/` (logic as exported functions, a thin CLI for arguments,
    output and exit codes).
  - Parity: the existing tests of both copies keep passing against the new
    implementation on Linux and native Windows (the existing Windows CI job),
    plus new `node:test` cases for the logic.
  - The `.sh` and `.ps1` files become small launchers that call Node, kept for
    command compatibility and approval prefixes; or are removed when nothing
    calls them (callers checked in skills, prompts, hooks, workflows and
    downstream sync manifests).
  - Downstream projects keep working after `aai-sync` (the manifest and
    profiles still ship what the launchers need).
- Out of scope:
  - More than one pair.
  - Any change to the behavior's observable output or exit codes, unless a
    drift between the two copies forces choosing one; that choice is recorded.
  - Process supervision and bootstrap before Node is installed.

## Affected Area
- `.aai/scripts/<chosen pair>.{sh,ps1}` and a new `.aai/scripts/<name>.mjs`
  (and `lib/` module if useful)
- Their tests under `tests/skills/` and new `tests/skills/lib/*.test.mjs`
- Sync manifest or profiles if the shipped file set changes
- docs/rfc/RFC-0017 phase 3 row

## Desired Behavior (To-Be)
- The chosen behavior has exactly one implementation, in Node.
- Running it through the old `.sh` or `.ps1` command still works and gives the
  same output and exit codes as before on both platforms.
- The removed duplicate code is gone from the repository.

## Acceptance Criteria
- AC-001: The chosen behavior's logic lives in one Node module; the `.sh` and
  `.ps1` files contain no copy of that logic (launcher only, or removed).
- AC-002: The pre-existing tests for both copies pass unchanged (or with a
  recorded, justified adjustment) against the Node implementation on Linux and
  on the native Windows CI job.
- AC-003: New `node:test` cases cover the module's logic, including the cases
  where the two old copies behaved differently.
- AC-004: A downstream install made by `aai-sync` still runs the behavior.
- AC-005: The RFC-0017 phase 3 row records this slice and the pattern it set.
- AC-006: Net line count of the chosen pair plus the new module is lower than
  before, and the measurement is recorded.

## Verification
- Command(s) and expected results:
  - The chosen behavior's suites and the new `node:test` file pass (rc 0).
  - The Windows CI job passes on the pull request.
  - A scratch `aai-sync` install runs the behavior from the launcher.

## Constraints / Risks
- Node must be available wherever the behavior runs; where a caller could run
  before Node is installed, the slice is the wrong one (Planning checks this).
- Windows parity is proven only by the hosted Windows job.
- Changing a shipped script is consumer-visible: merge needs the owner's menu.
- No secrets referenced.

## Notes
- Source: RFC-0017 "Owner decisions (2026-10-22)", order item 5 (phases 3 to
  5 in order, each with its own specification) and Proposal section 1.
- Node floor: Node 22 downstream, Node 24 CI (CHANGE-0221).
- Assumption (autopilot default): Planning chooses the pair; the owner is not
  asked unless the evidence is evenly split between candidates.
