---
id: node-first-third-slice
type: change
number: null
status: draft
capability: node-first-core
parent: smaller-node-core-and-faster-feedback
links:
  pr: []
  commits: []
---

# Move a third paired behavior to Node and close RFC-0017 phase 3

## Summary
- RFC-0017 phase 3, third and last slice: one more behavior that exists as both
  `.aai/scripts/<name>.sh` and `<name>.ps1` moves to one importable Node module,
  and the two scripts become thin launchers (or are removed where nothing calls
  them).
- It reuses the pattern from the first two slices (CHANGE-0222 / SPEC-0247,
  live-spool; CHANGE-0223 / SPEC-0248, triage).
- The owner decided on 2026-10-24 that phase 3 ends after this slice. The
  slice therefore also records which pairs stay, and why, and marks phase 3
  done.

## Motivation / Business Value
- Each pair moved halves the maintenance and review cost of that behavior and
  removes a source of Bash/PowerShell drift.
- Closing phase 3 with a measured inventory lets phase 4 start without an
  open-ended migration hanging over it; the remaining pairs move to phase 5 or
  stay as named platform adapters.

## Scope
- In scope:
  - Planning picks ONE pair by measured evidence: duplicated lines, how often
    it runs, drift or bug history between the two copies, platform-specific
    behavior, and whether any caller can run before Node is installed.
    Candidates: aai-live, cloudflare-share, expert-fetch,
    migrate-state-to-local, aai-canonicalize, aai-release, validate-skills.
    Already rejected with recorded reasons in SPEC-0248: pre-compact-save,
    migrate-yaml-to-jsonl, pre-commit-checks, aai-update. Out of bounds:
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
  - Phase 3 closeout: the RFC-0017 phase 3 row becomes `done`, and the RFC
    records every remaining `.sh`/`.ps1` pair with its line count and where it
    goes (phase 5 process adapter, platform adapter kept on purpose, or a
    later candidate), with the reason.
  - Sign the owner-directed merge of PR #496 (merged 2026-10-24): the three
    unsigned contract amendments on spec-node-first-second-slice are signed,
    and `fu-amend-spec-node-first-second-slice` closes.
- Out of scope:
  - More than one pair.
  - Observable output or exit-code changes beyond the recorded drift choices.
  - Starting phase 4.

## Affected Area
- `.aai/scripts/<chosen pair>.{sh,ps1}` and a new `.aai/scripts/<name>.mjs`
- Their tests under `tests/skills/`, a new `tests/skills/lib/<name>.test.mjs`
  and a Pester file
- `.aai/system/PROFILES.yaml`, `tests/skills/suite-map.yaml`,
  `.github/workflows/ps1-quality.yml` path lists as needed
- docs/rfc/RFC-0017 phase 3 row and a remaining-pairs inventory; the
  behavior's product doc if one exists

## Desired Behavior (To-Be)
- The chosen behavior has exactly one implementation, in Node.
- Running it through the old `.sh` or `.ps1` command still works on both
  platforms with the same output and exit codes, apart from recorded drift
  choices.
- RFC-0017 shows phase 3 done and says where each remaining pair goes.

## Acceptance Criteria
- AC-001: The chosen behavior's logic lives in one Node module; the `.sh` and
  `.ps1` contain no copy of it (launcher only, or removed).
- AC-002: The pre-existing tests for both copies pass (or carry a recorded,
  justified adjustment) on Linux and on the native Windows CI job under both
  Windows PowerShell 5.1 and pwsh 7.
- AC-003: New `node:test` cases cover the logic, including every case where
  the two copies behaved differently.
- AC-004: A downstream install made by `aai-sync` still runs the behavior.
- AC-005: The net line count of the pair plus the module is lower than before,
  and the measurement is recorded.
- AC-006: The RFC-0017 phase 3 row records this slice and has status `done`;
  the RFC lists every remaining `.sh`/`.ps1` pair with its measured line count,
  destination and reason, and the list matches the tree.
- AC-007: The #496 amendments are signed with the owner's merge as the source,
  and `fu-amend-spec-node-first-second-slice` is closed.

## Verification
- The behavior's suites and the new `node:test` file pass (rc 0).
- The Windows CI job passes on the pull request under both engines.
- A scratch `aai-sync` install runs the behavior from the launcher.
- A test compares the RFC inventory with the pairs present in `.aai/scripts/`.

## Constraints / Risks
- Lessons from slices 1 and 2:
  - Windows parity is proven only by the hosted Windows PowerShell 5.1 Pester
    job; the spec plans it as a hosted check.
  - A .NET Framework stdin writer prefixes a UTF-8 BOM to a child's stdin; any
    stdin-reading module must tolerate one.
  - A hosted failure is diagnosed with a probe before code changes.
  - The review scope set with `set-code-review --scope` is a plain
    space-separated path list.
- A caller that can run before Node is installed makes the pair the wrong
  choice (Planning checks this). A pair that touches the network
  (cloudflare-share, expert-fetch) needs offline test seams.
- Changing a shipped script is consumer-visible: merge needs the owner's menu.
- Closing phase 3 must not close the umbrella RFC (phases 0, 2, 4 and 5 stay
  open).
- No secrets referenced; a pair that reads a token (cloudflare-share) is tested
  without a real one.

## Notes
- Source: RFC-0017 "Owner decisions (2026-10-22)", order item 5; owner menu
  answer 2026-10-24: "Ještě 1 řez, pak uzavřít" (one more slice, then close
  phase 3 with an inventory of what stays).
- Assumption (autopilot default): Planning chooses the pair; the owner is not
  asked unless the evidence is evenly split.
