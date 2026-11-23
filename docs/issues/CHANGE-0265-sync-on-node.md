---
id: sync-on-node
type: change
number: 265
status: done
capability: sync-on-node
user_visible: true
parent: smaller-node-core-and-faster-feedback
links:
  pr: []
  commits: []
---

# Run the AAI layer sync as one Node module behind thin launchers

## Summary
- Ride 12, the last ride of the [remaining-scripts plan](../analysis/node-first-remaining-plan.md)
  (RFC-0017 phase 5; owner sign-off: yes, merge by the owner).
- `.aai/scripts/aai-sync.sh` and `.aai/scripts/aai-sync.ps1` (twins, about
  784 and 871 code lines) move into one Node module. Both files become thin
  launchers (20 lines or fewer, no policy) that refuse without Node and print
  an install hint, like the reaper (CHANGE-0241) and the launchers of rides 9
  to 11 (bootstrap, updater, git hook installer).
- Four slices, per the plan:
  - (a) the `.gitignore` reconcile: the managed blocks, the runtime-sidecar
    seed from `.aai/system/RUNTIME_IGNORE.list` and the duplicate self-heal;
  - (b) profile, copy plan and prune: profile resolution (flag, sticky pin,
    default), the core and extended copy, the core prune, the skill trees,
    the Copilot shim, the hook-registration merge, the seeds, the advisory
    report and the pin;
  - (c) drop the legacy-layout moves (the pre-`.aai/` layout of 2026-03):
    each dropped move is named with its reason, and the
    `migrate-state-to-local` pointer stays;
  - (d) launchers, and the logic of both twins deleted.
- aai-sync is the main consumer install path (`/aai-update`, `install.sh`,
  `install.ps1`), so the old-to-new upgrade is part of the scope, not a
  follow-up.

## Motivation / Business Value
- The twins drift today. Eleven open follow-ups name a sync difference (nine
  of them found by the ride-8 parity harness): `fu-parity-pin-template-spacing`,
  `fu-parity-ps1-timestamp-precision`, `fu-parity-gitignore-block-order`,
  `fu-parity-ps1-hook-exec-bit`, `fu-parity-ps1-report-name-local-time`,
  `fu-parity-ps1-report-backticks`, `fu-parity-win-source-path`,
  `fu-parity-win-ps1-crlf-bom`, `fu-parity-sh-report-stamp-two-reads`,
  `fu-sync-ps1-merge-lib-stderr-5-1`, `fu-sync-ps1-dangling-src-symlink`.
- The prune path has a measured failure class: under `set -o pipefail` an
  early-closing reader (`printf | grep -qxF`) in the core prune loop made the
  pipeline report 141 on a match and pruned core files (the nested
  layer-profiles CI flake). The bash twin carries five comments about this
  class; a port with no shell pipes removes it, and a test must prove a core
  file is never pruned with a large core list.
- Every sync fix is made twice today, in a language pair whose error models
  differ (`set -e` against `ErrorActionPreference Stop`).
- The owner decided (plan section 4, decision 1) that Node is a hard
  prerequisite on the install and update path, so the port needs no shell
  fallback.

## Scope
- In scope:
  - One Node module (Planning names it; `.aai/scripts/aai-sync.mjs` is the
    default) holding all sync policy, accepting the bash form (`<target>
    [--profile core|extended]`, `--profile=<v>`) and the PowerShell form the
    `.ps1` accepts today (`-TargetRoot <t>`, positional target, `-Profile
    <v>`), with the current exit codes or a numbered DR where they differ.
  - Shared helpers in `.aai/scripts/lib/` where more than one module uses
    them. One shared working-directory and base resolution helper (default
    `.aai/scripts/lib/resolve-base.mjs`) used by the updater, the bootstrap,
    the hook installer and the sync module, test-first, closing
    `fu-resolvebase-dotdot-after-symlink` (the updater and the bootstrap check
    the device and inode of the raw `PWD` but return `path.resolve(PWD)`; the
    hook installer fixed it in its round 2).
  - Slice (a), slice (b), slice (c) and slice (d) as in the Summary.
  - Slice (b) names the pipefail and SIGPIPE early-closing-reader hazard class
    and carries a test that no core-listed file is pruned when the core list
    is larger than a pipe buffer.
  - Slice (c) lists every legacy move that is dropped (the `ai/` directory,
    AAI-named files under `scripts/`, `scripts/ai-os-*`, root `PLAYBOOK.md`,
    the `docs/workflow`, `docs/roles` and `docs/templates` contents, six
    system docs under `docs/ai/`, `docs/knowledge/PATTERNS_UNIVERSAL.md`)
    with the reason, and keeps the `migrate-state-to-local` pointer.
  - The frozen bash and PowerShell twins (and the bash reconcile library they
    use) kept as test references under `tests/fixtures/` with a sha256 pin,
    and differential corpora comparing the module against both references in
    scratch trees.
  - `node:test` coverage for every rule and every drift found; each
    behaviour difference from either twin is a numbered decision (DR-n) with
    its reason and a test; each twin divergence is resolved toward one
    behaviour.
  - The ride-8 install-path parity harness runs the Node module as a third
    twin on the sync scenarios.
  - Pester for the `.ps1` launcher under Windows PowerShell 5.1 and pwsh 7 in
    the existing Windows jobs; a scratch `aai-sync` install proving every
    launcher.
  - The bootstrap problem: `/aai-update` and existing installs invoke
    aai-sync, so an old-layout target updating to this version must end up
    with working launchers and module; proven by an old-version to
    new-version scratch update.
  - Safety: tests and replays never delete or kill anything they did not
    provably create; the sync prune deletes only under a target root
    re-verified to be the intended target; an empty target or an empty core
    list is a hard failure; suites clean their own temp directories on
    failure; tests never sync, prune or install into this repository or any
    real repository; tests scrub `GIT_CONFIG_*` and the other repository
    variables; every written or deleted path is asserted under the scratch
    root. Nothing touches a container daemon.
  - `fu-suite-git-env-scrub-class` (P2): the hook-installer suites that pass
    the caller's `GIT_*` through get the same scrub and hooks-path assertion,
    if Planning measures it as cheap and the same class; otherwise Planning
    states why it is deferred.
  - Full wiring: suite map with shared libraries, suite weights, cd-subshell
    baseline, hygiene-pack pins, nested-suite lint, Pester in the Windows
    job, `ps1-quality.yml` path lists, PROFILES classification, prompt-diet
    ledger if a prompt changes, CHANGELOG `## [unreleased] — <title>` entry,
    product doc `docs/product/sync-on-node.md`, RFC-0017 phase 5 note.
  - Close each open sync follow-up the port resolves, with evidence per item.
  - A final re-measure of the plan's section 5 done criteria for phase 5,
    recording what remains.
- Out of scope:
  - Changing what the sync copies or preserves beyond the numbered DRs (the
    profile lists, the skill-wrapper predicate, the hook-registration merge
    algorithm in `lib/merge-hooks-json.mjs`).
  - Porting `aai-run-tests`, `aai-win-selftest.ps1` or `pre-commit-checks.sh`
    (kept native by the plan).
  - `docs/ai/docs-audit.yaml` `protected_paths_l3` (a concurrent ride edits
    it) and PR #535.

## Affected Area
- `.aai/scripts/aai-sync.sh`, `.aai/scripts/aai-sync.ps1`, the new module,
  `.aai/scripts/lib/gitignore-block.sh`, new shared libraries under
  `.aai/scripts/lib/`, `.aai/scripts/aai-update.mjs`,
  `.aai/scripts/aai-bootstrap.mjs`, `.aai/scripts/install-pre-commit-hook.mjs`
  (base resolution only)
- `.aai/system/PROFILES.yaml`, `.aai/system/RUNTIME_IGNORE.list` (comment
  only), prompts naming the sync (invocation text only, if needed),
  `docs/USER_GUIDE.md`, `README.md`
- `tests/skills/` (sync-seed, layer-profiles, parity, update, bootstrap,
  hook-installer and hygiene suites; new node:test and Pester files; wiring
  files), `tests/fixtures/` (frozen references)
- `.github/workflows/ps1-quality.yml`, `CHANGELOG.md`, `docs/product/`

## Desired Behavior (To-Be)
- `bash .aai/scripts/aai-sync.sh <target> [--profile core|extended]` and
  `powershell -File .aai/scripts/aai-sync.ps1 -TargetRoot <target> [-Profile
  core|extended]` both run the Node module with the same arguments and exit
  with its code.
- On every sync scenario of the parity harness the Node module leaves the
  same target tree and the same exit code as the reference twins, except
  where a numbered DR says otherwise.
- Without Node, both launchers print one refusal line with an install hint
  and exit non-zero, changing nothing.
- A target installed by the old twins and updated with this version ends
  with the new launchers and the module, and its launchers run.

## Acceptance Criteria
- AC-001: The module resolves its arguments, source root, target root and
  profile before any write; a missing target, an empty target, a target that
  is the source or overlaps it, and an empty core list are refused with a
  non-zero exit and nothing written (node:test per case).
- AC-002: The `.gitignore` reconcile, the core and extended copy, the core
  prune and every other sync surface match the frozen bash reference byte
  for byte in scratch trees, and the frozen PowerShell reference on the
  resulting tree, except for numbered DRs; no core-listed file is pruned with
  a core list larger than a pipe buffer.
- AC-003: Every legacy-layout move is dropped and named with its reason; the
  module deletes nothing outside the managed set of a re-verified target
  root, and the `migrate-state-to-local` pointer is still printed.
- AC-004: One shared base-resolution helper is used by the updater, the
  bootstrap, the hook installer and the sync module, and a `PWD` holding `..`
  after a symbolic link is not trusted by any of them.
- AC-005: The parity harness runs the Node module as a third twin on the sync
  scenarios and passes with no new allowlist row except one with a reviewed
  reason.
- AC-006: Both launchers are 20 lines or fewer, hold no policy, pass
  arguments and exit codes through, and refuse without Node with an install
  hint; Pester proves the `.ps1` under 5.1 and 7; a scratch `aai-sync`
  install runs every launcher; an old-version to new-version scratch update
  ends with working launchers.
- AC-007: Source-shape pins against either twin are migrated to behaviour
  tests (each named); existing suites pass; resolved follow-ups closed with
  evidence; wiring complete; CHANGELOG entry and product doc present; the
  phase 5 done criteria re-measured and what remains recorded.

## Verification
- `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-sync-seed.sh`
  and the layer-profiles, parity, update, bootstrap, hook-installer, hygiene
  and new suites pass.
- The Pester files pass under pwsh 7 locally and both engines in CI.

## Constraints / Risks
- The sync is the consumer install and update path: ceremony L3, merge by the
  owner.
- `/aai-update` runs the SOURCE's sync (the materialized upstream's
  `.aai/scripts/aai-sync.*`), so the first update after this release already
  runs the new launcher and module; Planning states which file set is copied
  and pruned on that first update, also for an older updater.
- The sync deletes files (copy-replace, core prune, stale clean, retired
  wrappers): every delete must stay under the re-verified target root. Tests
  sync only into scratch trees the test created; never into this repository
  or any real one. No test may reach a container daemon or delete anything
  it did not create.
- Secrets preflight: no local secret is referenced by this scope.

## Notes
- Source: roadmap item `sync-on-node`; plan ride 12.
- Precedents: CHANGE-0241 (reaper), CHANGE-0261 / SPEC-0306 (bootstrap on
  Node), CHANGE-0262 / SPEC-0307 (updater on Node), CHANGE-0263 / SPEC-0308
  (hook installer on Node), SPEC-0284 (parity harness).
- Worktree: owner-directed own worktree
  (`/Users/ales/Projects/aai-worktrees/sync-on-node`, branch
  `feat/sync-on-node`).
- Autopilot defaults: human_time_minutes null; no implementation-mode menu
  (Planning decides).
