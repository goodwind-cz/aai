---
id: update-on-node
type: change
number: null
status: draft
capability: update-on-node
user_visible: true
parent: smaller-node-core-and-faster-feedback
links:
  pr: []
  commits: []
---

# Run the AAI layer updater as one Node module behind thin launchers

## Summary
- Ride 10 of the [remaining-scripts plan](../analysis/node-first-remaining-plan.md)
  (RFC-0017 phase 5; owner sign-off: yes).
- `.aai/scripts/aai-update.sh` and `.aai/scripts/aai-update.ps1` (twins,
  about 122 and 138 code lines) move into one Node module. Both files become
  thin launchers (20 lines or fewer, no policy) that refuse without Node and
  print an install hint, like the reaper (CHANGE-0241) and the bootstrap
  launchers (ride 9).
- One slice: argument parsing, the canonical-repo guard, source
  resolution (local checkout or the gh, git, anonymous git clone chain), the
  dry-run plan, running the source's sync, post-sync evidence, the doctor
  field report postamble, and temp cleanup.

## Motivation / Business Value
- The two twins already drift (dry-run upstream line, the conflict advisory
  path, unknown-argument handling, the `Recommended:` line, the AAI_PIN
  pattern order); every fix today has to be made twice.
- The owner decided (plan section 4, decision 1) that Node is a hard
  prerequisite on the install and update path, so the port needs no shell
  fallback.
- One module can be unit-tested per rule; today each rule is covered only
  through end-to-end runs of each twin.
- The bash twin's self-relocation (copying itself to a temp file so the sync
  cannot overwrite the running script) is no longer needed: a launcher that
  `exec`s node, and a module that node has fully loaded, cannot be pulled
  out from under the run.

## Scope
- In scope:
  - One Node module `.aai/scripts/aai-update.mjs` holding all update policy,
    accepting both the bash long-flag form (`--repo`, `--ref`, `--dry-run`,
    `--keep-temp`, `--force`, `-h|--help`) and the PowerShell form (`-Repo`,
    `-Ref`, `-DryRun`, `-KeepTemp`, `-Force`), with the current exit codes
    (0, 1 usage, 2 refused, 3 fetch failed, 4 malformed source).
  - `aai-update.sh` and `aai-update.ps1` rewritten as thin launchers.
  - The frozen bash and PowerShell twins kept as test references under
    `tests/fixtures/` with a sha256 pin, and a differential corpus comparing
    the module against both references.
  - `node:test` coverage for every rule and for every drift found between
    the twins and the module; each behaviour difference from either twin is
    a numbered decision (DR-n) with its reason, and each twin divergence is
    resolved toward one behaviour.
  - The ride-8 install-path parity harness runs the Node module as a third
    twin on the update scenarios.
  - Pester for the `.ps1` launcher under Windows PowerShell 5.1 and pwsh 7
    in the existing Windows job; a scratch `aai-sync` install proving both
    launchers run the module.
  - Full wiring: suite map with shared libraries, suite weights,
    cd-subshell baseline, hygiene-pack pins, nested-suite lint, Pester in
    the Windows job, `ps1-quality.yml` path lists, prompt-diet ledger if a
    prompt changes.
  - CHANGELOG `## [unreleased] — <title>` entry (downstream update now
    requires Node).
- Out of scope:
  - Porting `aai-sync` itself (ride 12); the module still runs the source
    checkout's sync twin.
  - Changing what the sync writes, the doctor field report helper, or the
    hook installer step of `/aai-update` (ride 11).

## Affected Area
- `.aai/scripts/aai-update.sh`, `.aai/scripts/aai-update.ps1`, new
  `.aai/scripts/aai-update.mjs`
- `.aai/system/PROFILES.yaml`, `.aai/SKILL_UPDATE.prompt.md` (invocation
  text only, if needed), any required-file list naming the update script
- `tests/skills/` (update suites, parity harness, new node:test and Pester
  files, wiring files), `tests/fixtures/` (frozen references)
- `.github/workflows/ps1-quality.yml`, `CHANGELOG.md`

## Desired Behavior (To-Be)
- `bash .aai/scripts/aai-update.sh [args]`, `sh` of the same, and
  `powershell -File .aai/scripts/aai-update.ps1 [args]` all run the Node
  module with the same arguments and exit with its code.
- On every update scenario of the parity harness the Node module leaves the
  same tree and exit code as the reference twins, except where a numbered
  DR says otherwise.
- Without Node, both launchers print one refusal line with an install hint
  and exit non-zero, changing nothing.

## Acceptance Criteria
- AC-001: Argument parsing, the canonical-repo guard and source resolution
  (local checkout, clone chain, clone failure exit 3) behave as the twins,
  proved by `node:test` per rule with an injected command seam (no network).
- AC-002: Dry-run, the sync run, post-sync evidence (changed files,
  AAI_PIN lines, conflict advisory), the doctor field report postamble and
  the next-steps block match the reference twins byte for byte after the
  documented normalizations, or differ only by a numbered DR.
- AC-003: Temp clones are removed on every exit path unless `--keep-temp`;
  nothing outside the temp directory the run created is deleted.
- AC-004: The parity harness runs the Node module as a third twin on the
  update scenarios and passes with no new allowlist row except one with a
  reviewed reason.
- AC-005: Both launchers are 20 lines or fewer, hold no policy, pass
  arguments and exit codes through, and refuse without Node with an install
  hint; Pester proves the `.ps1` under 5.1 and 7; a scratch `aai-sync`
  install runs both.
- AC-006: The existing update suites pass against the launchers (or are
  rewritten to the module with each change named); wiring is complete;
  CHANGELOG entry present.

## Verification
- `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-update.sh`
  and the parity and new suites pass.
- The Pester files pass under pwsh 7 locally and both engines in CI.

## Constraints / Risks
- A consumer updating from an older layer runs its OLD update script, which
  syncs in the new launcher and module; the next update runs the new path.
  The old bash twin's self-relocation still protects that one run.
- The module must pick which sync twin of the SOURCE to run (bash on POSIX,
  PowerShell on native Windows); Planning decides and records it as a DR.
- Tests never use the network: clone attempts go through an injectable
  command seam or a local file remote.
- No test may reach a container daemon or delete anything it did not
  create; deletion only under scratch directories the run created.
- Secrets preflight: no local secret is referenced by this scope.

## Notes
- Source: roadmap item `update-on-node`; plan ride 10 (owner sign-off: yes,
  merge by the owner).
- Precedents: CHANGE-0241 (reaper), CHANGE-0261 / SPEC-0306 (bootstrap on
  Node), SPEC-0284 (parity harness).
- Worktree: owner-directed own worktree.
- Autopilot defaults: human_time_minutes null; no implementation-mode menu
  (Planning decides).
