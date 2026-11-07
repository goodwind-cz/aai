---
id: pre-commit-checks-ps1-retire
type: change
number: null
status: draft
capability: pre-commit-checks-ps1-retire
parent: smaller-node-core-and-faster-feedback
links:
  pr: []
  commits: []
---

# Retire the uncalled PowerShell pre-commit checks and make the bash checks pipe-safe

## Summary
- Ride 5 of the [remaining-scripts plan](../analysis/node-first-remaining-plan.md)
  (RFC-0017 phase 5).
- `.aai/scripts/pre-commit-checks.ps1` has no runtime caller: the installed
  git hooks (written by both installers from `.aai/templates/git-hooks/`) and
  the Claude hook gate run `bash .aai/scripts/pre-commit-checks.sh`, because a
  git hook always runs under Git's own shell, on Windows too. Retire the
  `.ps1` to a deprecation launcher for one release that prints one retired
  line naming `pre-commit-checks.sh` and exits 1; a follow-up deletes it in
  the next release.
- Fix `fu-pre-commit-checks-pipe-grep-q` (P2): `.aai/scripts/pre-commit-checks.sh`
  runs under `set -euo pipefail` and pipes a variable into an early-closing
  reader at 7 sites (6 `echo "$var" | grep -q`, 1 `echo "$var" | head -3`).
  Rewrite them to here-strings, as ride 4 did for the hook bodies, and stop
  the pipe-safe ratchet from deferring this file.

## Motivation / Business Value
- The `.ps1` is 281 lines (221 code lines) of a protected guard nobody runs.
  It still costs: two suites run it under pwsh as a parity twin (TEST-809,
  TEST-1708), it must be kept in step with every new check, and the docs tell
  agents to run "the `.sh` or `.ps1`".
- The `.sh` misfires on large input. Reproduced at intake on main `3e6b52d5`
  (bash, scratch repos, 3 of 3 runs each):
  - CHECK 1: a STATE.yaml with `phase: implementation` near the top and
    6000 filler lines after it (384042 bytes) reports "No active
    implementation phase" instead of the TDD warning (the small file warns
    correctly).
  - CHECK 5: the same file with `phase: validation` prints no "No validation
    report found" warning (the small file prints it).
  - CHECK 6: a `code_review:` block with `required: true` followed by a large
    block prints nothing; the gate is skipped (the small block prints
    "Code review gate satisfied").
  - CHECK 3: a staged `.js` file with 20000 `console.log` lines makes the
    script exit 141 (the `head -3` pipe under `set -e`), so the commit is
    blocked and checks 4 to 9 never run (the small file exits 0).
  - This repository's own `docs/ai/STATE.yaml` is 111876 bytes, so CHECK 1
    and CHECK 5 are in the misfire range here.

## Scope
- In scope:
  - `.aai/scripts/pre-commit-checks.ps1` becomes a deprecation launcher (no
    param block, ASCII, one `# RETIRED` line, one stderr line naming
    `.aai/scripts/pre-commit-checks.sh`, exit 1, changes nothing), kept one
    release, and a `fu-delete-*` follow-up that deletes it.
  - `.aai/scripts/pre-commit-checks.sh`: the 7 early-closing pipe sites
    become here-strings; no check changes what it decides on small input.
  - `tests/skills/lib/pipe-grep-q-ratchet.sh` no longer defers
    `pre-commit-checks.sh`; the shipping arm counts it at zero.
  - Every live reference to the `.ps1` as something to run updated:
    `.aai/AGENTS.md`, `docs/TECHNOLOGY.md`, the comments in
    `.aai/scripts/lib/guard-config.mjs` and `docs/ai/docs-audit.yaml`, the
    RFC-0017 inventory row, and the suites that run the `.ps1` as a twin.
  - Tests: a new bash suite (launcher behaviour and shape, the four large-input
    misfires, the ratchet arm, the reference inventory); a Pester file for the
    launcher under Windows PowerShell 5.1 and pwsh 7; a scratch `aai-sync`
    install proving the launcher ships and prints its line.
  - Before/after line measurement with the plan's method.
  - CHANGELOG `## [unreleased] — <title>` per-entry heading.
- Out of scope:
  - Porting `pre-commit-checks.sh` to Node, or changing any check's logic,
    messages or exit codes beyond the pipe fix.
  - The L3 protected-path lists (`.aai/workflow/WORKFLOW.md`,
    `docs/ai/docs-audit.yaml` `protected_paths_l3`,
    `.aai/templates/docs-audit.template.yaml`): the launcher stays a
    protected file for its one release; the delete follow-up removes the
    entries.
  - Historical docs (closed intakes, specs, reviews, reports, CHANGELOG
    history).

## Affected Area
- `.aai/scripts/pre-commit-checks.ps1`, `.aai/scripts/pre-commit-checks.sh`
  (both L3 protected surfaces)
- `tests/skills/lib/pipe-grep-q-ratchet.sh`, the suites that run or pin the
  `.ps1`, wiring files (suite map, weights, PROFILES)
- `.aai/AGENTS.md`, `docs/TECHNOLOGY.md`, `.aai/scripts/lib/guard-config.mjs`
  (comments), `docs/ai/docs-audit.yaml` (comment)
- `docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md`, `CHANGELOG.md`

## Desired Behavior (To-Be)
- `pwsh -File .aai/scripts/pre-commit-checks.ps1` (and Windows PowerShell 5.1),
  with or without `-Strict`, prints one line on stderr saying the script is
  retired and naming `bash .aai/scripts/pre-commit-checks.sh`, exits 1 and
  checks nothing.
- `bash .aai/scripts/pre-commit-checks.sh` reaches the same decision on a
  large STATE.yaml or a large debug-statement match list as on a small one.

## Acceptance Criteria
- AC-001: The `.ps1` is a deprecation launcher: under pwsh 7 and Windows
  PowerShell 5.1 it prints exactly one retired line naming
  `pre-commit-checks.sh` on stderr, nothing on stdout, exits 1 and leaves
  the fixture unchanged, with and without `-Strict`.
- AC-002: `pre-commit-checks.sh` has zero early-closing pipe sites by the
  ratchet's pattern, the ratchet no longer defers it, and the four
  large-input cases (CHECK 1, CHECK 3, CHECK 5, CHECK 6) decide as their small-input
  twins under `set -o pipefail`.
- AC-003: No live file names the `.ps1` as something to run; the suites that
  ran the `.ps1` as a twin no longer do; the RFC-0017 inventory still equals
  the tree.
- AC-004: A scratch `aai-sync` install carries the launcher and it prints
  its line there; wiring is complete; before and after line counts are
  measured and recorded; a delete follow-up is filed.

## Verification
- The new suite and the touched suites pass (rc 0), run with
  `env -u AAI_ROLE -u AAI_GIT_WRITE`.
- The Windows CI job passes on the pull request under both engines.

## Constraints / Risks
- Both files are L3 protected surfaces: ceremony level 3, an explicit
  recorded worktree decision, mandatory code review on the most capable
  tier, and the owner's final-diff sign-off before merge.
- Consumer-visible: a downstream project that wired the `.ps1` into its own
  tooling now gets exit 1 with the replacement named, not a silent pass; the
  CHANGELOG says so. The owner merges.
- A launcher that exits 0 would silently turn a secrets guard off for such a
  caller; exit 1 is deliberate.
- Secrets preflight: no local secret is referenced by this scope.
- Windows parity is proven only by the hosted Windows job.

## Notes
- Source: roadmap item `pre-commit-checks-ps1-retire`; plan ride 5 (owner
  sign-off: yes, given on the plan 2026-11-05).
- Precedents: CHANGE-0246 / SPEC-0274 (retirement launcher pattern) and
  CHANGE-0249 / SPEC-0278 (here-string fix of the same reader class).
- Count correction: the follow-up says 7 `echo $var | grep -q` pipes; the
  measured split is 6 `grep -q` pipes plus 1 `head -3` pipe (bash,
  `/usr/bin/grep`, the ratchet's `PGQ_PATTERN`).
- Worktree: owner decision 2026-11-07 (own worktree for this L3 ride).
- Autopilot defaults: human_time_minutes null; no implementation-mode menu
  (Planning decides).
