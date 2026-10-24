---
id: node-first-second-slice
type: change
number: 223
status: done
capability: node-first-core
parent: smaller-node-core-and-faster-feedback
links:
  pr: []
  commits: []
---

# Move the second paired sync/hook behavior to one Node module

## Summary
- RFC-0017 phase 3, second slice: one more behavior that exists as both
  `.aai/scripts/<name>.sh` and `<name>.ps1` moves to one importable Node module,
  and the two scripts become thin launchers (or are removed where nothing calls
  them).
- It reuses the pattern from the first slice (CHANGE-0222 / SPEC-0247,
  live-spool): one dependency-free ESM module, two launchers, `node:test` for
  the logic and Pester on the native Windows CI job for parity.

## Motivation / Business Value
- Each pair moved halves the maintenance and review cost of that behavior and
  removes a source of Bash/PowerShell drift.
- The second slice tests whether the pattern holds for a behavior with more
  logic than live-spool, before phase 3 continues.

## Scope
- In scope:
  - Planning picks ONE pair by measured evidence: duplicated lines, how often
    it runs, drift or bug history between the two copies, platform-specific
    behavior, and whether any caller can run before Node is installed.
    Remaining candidates: validate-skills, triage, pre-compact-save,
    pre-commit-checks, migrate-yaml-to-jsonl, aai-update. Out of bounds:
    process supervision (aai-run-tests, aai-reap-tests, autonomous-loop) and
    the two largest pairs (aai-sync, install-pre-commit-hook).
  - The behavior moves into `.aai/scripts/<name>.mjs` (exported functions plus
    a thin CLI); the `.sh` and `.ps1` become launchers or are removed when no
    caller needs them (skills, prompts, hooks, workflows, sync manifest).
  - Parity: the existing tests of both copies pass against the new
    implementation on Linux and native Windows (Windows PowerShell 5.1 and
    pwsh 7), plus new `node:test` cases for the logic and for every measured
    drift between the copies.
  - Downstream installs made by `aai-sync` keep working.
  - Sign the owner-directed merge of PR #495 (merged 2026-10-23): the unsigned
    contract amendments on spec-node-first-sync-hook-slice and the allocator
    restamp are signed, and `fu-amend-spec-node-first-sync-hook-slice` closes.
- Out of scope:
  - More than one pair.
  - Observable output or exit-code changes beyond the recorded drift choices.

## Affected Area
- `.aai/scripts/<chosen pair>.{sh,ps1}` and a new `.aai/scripts/<name>.mjs`
- Their tests under `tests/skills/`, a new `tests/skills/lib/<name>.test.mjs`
  and a Pester file
- `.aai/system/PROFILES.yaml`, `tests/skills/suite-map.yaml`,
  `.github/workflows/ps1-quality.yml` path lists as needed
- docs/rfc/RFC-0017 phase 3 row; the behavior's product doc if one exists

## Desired Behavior (To-Be)
- The chosen behavior has exactly one implementation, in Node.
- Running it through the old `.sh` or `.ps1` command still works on both
  platforms with the same output and exit codes, apart from recorded drift
  choices.

## Acceptance Criteria
- AC-001: The chosen behavior's logic lives in one Node module; the `.sh` and
  `.ps1` contain no copy of it (launcher only, or removed).
- AC-002: The pre-existing tests for both copies pass (or carry a recorded,
  justified adjustment) on Linux and on the native Windows CI job under both
  Windows PowerShell 5.1 and pwsh 7.
- AC-003: New `node:test` cases cover the logic, including every case where
  the two copies behaved differently.
- AC-004: A downstream install made by `aai-sync` still runs the behavior.
- AC-005: The RFC-0017 phase 3 row records this slice.
- AC-006: The net line count of the pair plus the module is lower than before,
  and the measurement is recorded.
- AC-007: The #495 amendments are signed with the owner's merge as the source,
  and `fu-amend-spec-node-first-sync-hook-slice` is closed.

## Verification
- The behavior's suites and the new `node:test` file pass (rc 0).
- The Windows CI job passes on the pull request under both engines.
- A scratch `aai-sync` install runs the behavior from the launcher.

## Constraints / Risks
- Lessons from slice 1:
  - Windows parity is proven only by the hosted Windows PowerShell 5.1 Pester
    job; the spec plans it as a hosted check.
  - A .NET Framework stdin writer prefixes a UTF-8 BOM to a child's stdin; any
    stdin-reading module must tolerate one.
  - A hosted failure is diagnosed with a probe before code changes (slice 1
    spent two rounds on disproven hypotheses).
- A caller that can run before Node is installed makes the pair the wrong
  choice (Planning checks this).
- Changing a shipped script is consumer-visible: merge needs the owner's menu.
- No secrets referenced.

## Notes
- Source: RFC-0017 "Owner decisions (2026-10-22)", order item 5; first slice
  CHANGE-0222 / SPEC-0247 (PR #495).
- Assumption (autopilot default): Planning chooses the pair; the owner is not
  asked unless the evidence is evenly split.
