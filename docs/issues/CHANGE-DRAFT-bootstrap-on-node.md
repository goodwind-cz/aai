---
id: bootstrap-on-node
type: change
number: null
status: draft
capability: bootstrap-on-node
parent: smaller-node-core-and-faster-feedback
links:
  pr: []
  commits: []
---

# Run the project bootstrap as one Node module behind thin launchers

## Summary
- Ride 9 of the [remaining-scripts plan](../analysis/node-first-remaining-plan.md)
  (RFC-0017 phase 5; owner sign-off: yes).
- `.aai/scripts/aai-bootstrap.sh` (about 920 code lines, no twin) moves into
  one Node module. `aai-bootstrap.sh` becomes a thin launcher and a new
  `aai-bootstrap.ps1` launcher gives Windows a native bootstrap. Both
  launchers are 20 lines or fewer, carry no policy, and refuse without Node
  with an install hint, like the reaper launchers (CHANGE-0241).
- Three slices: (a) detection and planning (architecture, package manager,
  task runners, auth, the skill plan); (b) rendering and writes (skill
  files, marker and index files, the managed-file preflight, the
  `.gitignore` runtime block, dry-run and force); (c) the opt-in Claude
  hooks overlay, the git platform record, and the launchers.

## Motivation / Business Value
- Bootstrap is the last large script on the install path with no Windows
  equivalent: a Windows consumer without Git Bash cannot run it at all.
- The owner decided (plan section 4) that Node is a hard prerequisite on
  the install and update path, so the port no longer needs a bash fallback.
- One module in Node can be unit-tested per detection rule; today every
  rule is covered only through end-to-end runs of the bash script.

## Scope
- In scope:
  - One Node module under `.aai/scripts/` holding all bootstrap policy, with
    the current command-line surface (`[target-root] [--dry-run] [--force]
    [--with-claude-hooks] [-h|--help]`) and exit codes (0, 1 conflict, 2
    usage, 3 refused hooks overlay).
  - `aai-bootstrap.sh` rewritten as a thin launcher; new `aai-bootstrap.ps1`
    launcher; both vendored by `aai-sync` (PROFILES) and named where the
    current script is named as a required file (`validate-skills.mjs`).
  - `node:test` coverage for each detection and rendering rule and for
    every drift found between the bash script and the Node module.
  - The ride-8 install-path parity harness extended with a bootstrap
    operation so the bash script (the reference, kept as a test fixture
    for the comparison) and the Node module are compared on the same
    scratch targets; byte-equivalent trees and exit codes on every scenario
    the bash bootstrap supports.
  - Pester for the `.ps1` launcher under Windows PowerShell 5.1 and pwsh 7
    in the existing Windows job.
  - A scratch `aai-sync` install proving both launchers run the module.
  - Full wiring: suite map with shared libraries, suite weights,
    cd-subshell baseline, hygiene-pack pins, nested-suite lint, Pester in
    the Windows job.
  - CHANGELOG `[unreleased]` entry (downstream bootstrap now requires Node).
- Out of scope:
  - Any change to what bootstrap detects or writes (the port is
    behaviour-preserving; a bash bug found is recorded and either kept for
    parity or fixed in both with a named reason).
  - `aai-update`, `aai-sync`, the pre-commit installer (rides 10 to 12).
  - The shared libraries bootstrap already calls (`merge-hooks-json.mjs`,
    `platform.mjs`, `gitignore-block.sh` for the sync twins) beyond reading
    the same inputs.

## Affected Area
- `.aai/scripts/aai-bootstrap.sh`, new `.aai/scripts/aai-bootstrap.mjs`
  (name decided in Planning), new `.aai/scripts/aai-bootstrap.ps1`
- `.aai/system/PROFILES.yaml`, `.aai/scripts/validate-skills.mjs`,
  `.aai/SKILL_BOOTSTRAP.prompt.md` (invocation text only, if needed)
- `tests/skills/` (bootstrap suites, parity harness op, new node:test and
  Pester files, wiring files)
- `CHANGELOG.md`

## Desired Behavior (To-Be)
- `bash .aai/scripts/aai-bootstrap.sh [args]`, `sh` of the same, and
  `powershell -File .aai/scripts/aai-bootstrap.ps1 [args]` all run the Node
  module with the same arguments and exit with its code.
- On every scenario the current bash bootstrap supports, the Node module
  leaves a byte-identical tree and the same exit code; stdout differs only
  where a documented normalization (the run timestamp) applies.
- Without Node, both launchers print one refusal line with an install hint
  and exit non-zero, writing nothing.

## Acceptance Criteria
- AC-001: Detection and planning (slice a) produce the same detected
  architecture, commands and skill plan as the bash script for every
  fixture project of `test-aai-bootstrap.sh` and the parity scenarios,
  proved by `node:test` per rule.
- AC-002: Rendering and writes (slice b) produce byte-identical files,
  `.gitignore` blocks, dry-run output and conflict refusals; `--force`
  semantics unchanged.
- AC-003: The hooks overlay and the platform record (slice c) behave as
  today, including exit 3 on a refused or impossible overlay and the
  relayed platform lines.
- AC-004: The parity harness compares the bash bootstrap and the Node
  module as twins on a bootstrap scenario set and passes with no new
  allowlist row except one with a reviewed reason.
- AC-005: The `.sh` and `.ps1` launchers are 20 lines or fewer, hold no
  policy, pass arguments and exit codes through, and refuse without Node
  with an install hint; Pester proves the `.ps1` under 5.1 and 7; a scratch
  `aai-sync` install runs both.
- AC-006: Existing bootstrap and hooks-overlay suites pass unchanged
  against the launcher; wiring is complete; CHANGELOG entry present.

## Verification
- `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-bootstrap.sh`
  and the hooks-overlay, parity and new suites pass.
- The Pester file passes under pwsh 7 locally and both engines in CI.

## Constraints / Risks
- The bash script's run timestamp (`NOW_UTC`) appears in generated files;
  parity needs one documented normalization for it.
- The Windows job's time budget is tight; the bootstrap Pester set stays
  small.
- No test may reach a container daemon or delete anything it did not
  create; bootstrap writes only under scratch targets in tests.
- Secrets preflight: no local secret is referenced by this scope.

## Notes
- Source: roadmap item `bootstrap-on-node`; plan ride 9 (owner sign-off:
  yes, merge by the owner).
- Precedents: CHANGE-0241 (reaper), SPEC-0284 (parity harness),
  SPEC-0283 (hook gate on Node).
- Worktree: owner-directed own worktree.
- If the ride outgrows one PR, slices (a)+(b) ship first and (c) becomes
  the next ride.
- Autopilot defaults: human_time_minutes null; no implementation-mode menu
  (Planning decides).
