---
id: install-path-parity-harness
type: change
number: 254
status: done
capability: install-path-parity-harness
parent: smaller-node-core-and-faster-feedback
links:
  pr: []
  commits: []
---

# Run both twins of sync, update and the hook installer into scratch targets and diff what they leave behind

## Summary
- Ride 8 of the [remaining-scripts plan](../analysis/node-first-remaining-plan.md)
  (RFC-0017 phase 5). Test-only: no production code changes.
- A parity harness runs the bash twin (`.sh`) and the PowerShell twin
  (`.ps1`) of `aai-sync`, `aai-update` and
  `install-pre-commit-hook` into scratch targets over a matrix of realistic
  scenarios, and compares the resulting trees (paths, bytes, executable bit
  where it means something) and the exit codes.
- Known divergences live in a reviewed allowlist with one reason each; any
  divergence not on the list fails, and so does a list row that matches
  nothing.
- The harness takes a third twin by registration, so the Node
  implementations of rides 9 to 12 are compared against both shell twins
  without a new harness.

## Motivation / Business Value
- Rides 9 to 12 (bootstrap, update, installer and sync on Node) replace about
  1,650 duplicated code lines on the main consumer install path. The plan
  orders them behind a harness that proves what the twins do today, on
  Linux, macOS and native Windows, so a port can be held to it.
- Today no suite runs both twins of `aai-sync` or `aai-update` on the same
  input and compares the result. `test-aai-git-hook-templates.sh` compares
  the hook bytes the two installers write for a few cases; the
  `install-pre-commit-hook.ps1` side otherwise has 9 open `fu-ps1-*` items.
- Measured at intake (macOS arm64, bash 3.2, pwsh 7.6.3, Node 22, scratch
  source built from `main` `396c3cbb`): a fresh `aai-sync` takes about 3 to 4
  seconds per twin, `aai-update` about 4 to 5, the hook installer about 1.
  The first comparison already shows real divergences: the
  `- Template version:` line of `AAI_PIN.md` (two spaces against one), the
  `Synced at` precision (seconds against seven fraction digits), the order
  and header text of the `.gitignore` blocks, the executable bit of
  `hooks/session-start.sh` (set by the bash twin only), and the
  `sync-conflicts-<stamp>.md` file name (UTC in bash, local time in
  PowerShell).

## Scope
- In scope:
  - A Node driver under `tests/skills/lib/` that builds the scratch sources
    and targets, runs the twins, snapshots and normalizes the trees, diffs
    every pair of twins and applies the allowlist.
  - A scenario matrix: fresh install, re-run (idempotent), update over an
    older install, profiles core and extended, existing and foreign hook
    slots, `.gitignore` states, a target path with a space; a fast default
    set and a heavier opt-in set.
  - The allowlist file, with each divergence the harness finds entered with
    one reason, and a follow-up filed with evidence for each one that is a
    real twin bug.
  - A bash suite for Linux and macOS (PowerShell twin under pwsh 7) and a
    Pester file that runs the same driver natively on Windows under
    PowerShell 5.1 and pwsh 7 in the existing Windows job.
  - Full wiring: suite map, suite weights, hygiene pins, the cd-subshell
    baseline, the nested-suite lint, the ps1-quality path filter.
- Out of scope:
  - Fixing a divergence (production code stays untouched), unless the spec
    names a trivial fix explicitly.
  - Comparing console output (only trees and exit codes are compared).
  - The Node twins themselves (rides 9 to 12).
  - `aai-bootstrap` (no twin).

## Affected Area
- `tests/skills/` (new suite, new Pester file, new lib files, wiring files)
- `.github/workflows/ps1-quality.yml` (path filter only)
- `docs/ai/decisions.jsonl` (follow-up items for divergences found, via `follow-ups.mjs`)

## Desired Behavior (To-Be)
- One command on Linux or macOS, and the Windows Pester run, report every
  divergence between the twins per scenario, fail on any divergence not on
  the allowlist, and fail on a stale allowlist row.
- Adding a third twin is a registry entry naming its commands; the harness
  then compares it with both shell twins.

## Acceptance Criteria
- AC-001: For every scenario of the default matrix, both twins run into
  scratch targets built the same way, and the harness compares their trees
  (paths, bytes, executable bit on POSIX) and exit codes per step.
- AC-002: A divergence not on the allowlist fails the run and names the
  scenario, path, kind and twin pair; an allowlist row that matches nothing
  fails the run; every row carries a non-empty reason.
- AC-003: Normalizations are a fixed, documented list, each with a reason;
  nothing else is normalized.
- AC-004: A third twin registered in the driver is compared against both
  shell twins with no other change (proved with a test twin).
- AC-005: The suite runs on Linux and macOS with pwsh 7 and the Pester file
  runs the driver under Windows PowerShell 5.1 and pwsh 7 in the existing
  Windows job, with no skip.
- AC-006: The default matrix fits the CI budget (measured runtime recorded;
  an opt-in full matrix exists).
- AC-007: Wiring is complete and each real divergence found is a follow-up
  with evidence.

## Verification
- The new suite passes with `env -u AAI_ROLE -u AAI_GIT_WRITE bash
  .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-install-parity.sh`.
- The Pester file passes under pwsh 7 locally and under both engines in the
  Windows CI job.

## Constraints / Risks
- Windows job time: the windows-5_1 job already measured up to 20.6 minutes
  against a 30-minute bound; the Windows set must stay small.
- The Windows expected-skip count is pinned (4) and POSIX Pester must not
  skip, so the Pester file never skips.
- `aai-update --repo <dir>` checks out a ref in that directory, so update
  scenarios need a scratch source repository, never the checkout.
- Secrets preflight: no local secret is referenced by this scope.

## Notes
- Source: roadmap item `install-path-parity-harness`; plan ride 8 (owner
  sign-off: no).
- Related open items the harness exercises: `fu-ps1-setcontent-rewrites-seed-eol`,
  `fu-three-readers-three-whitespaces`, `fu-ps1-symlink-config-replaced`.
- Worktree: owner-directed own worktree.
- Autopilot defaults: human_time_minutes null; no implementation-mode menu
  (Planning decides).
