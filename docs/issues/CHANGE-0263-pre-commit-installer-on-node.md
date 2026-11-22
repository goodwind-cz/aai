---
id: pre-commit-installer-on-node
type: change
number: 263
status: done
capability: pre-commit-installer-on-node
user_visible: true
parent: smaller-node-core-and-faster-feedback
links:
  pr: []
  commits: []
---

# Run the git hook installer as one Node module behind thin launchers

## Summary
- Ride 11 of the [remaining-scripts plan](../analysis/node-first-remaining-plan.md)
  (RFC-0017 phase 5; owner sign-off: yes, merge by the owner).
- `.aai/scripts/install-pre-commit-hook.sh` and
  `.aai/scripts/install-pre-commit-hook.ps1` (twins, about 749 code lines
  each) move into one Node module. Both files become thin launchers (20
  lines or fewer, no policy) that refuse without Node and print an install
  hint, like the reaper (CHANGE-0241), the bootstrap launchers (ride 9) and
  the updater launchers (ride 10).
- Three slices, per the plan:
  - (a) one resolved mode and one guard policy, read and written through
    `.aai/scripts/lib/guard-config.mjs`;
  - (b) slot attestation and upgrade: the hooks directory Git resolves,
    absent, AAI-owned, older-AAI (upgrade in place) and foreign slots;
  - (c) launchers, and migration of the source-shape pins against both
    installers (about 99 against the `.ps1`) to behaviour tests.
- The three hook bodies stay single-sourced in the shared templates from
  ride 4 (`.aai/templates/git-hooks/`); the module reads them, it does not
  embed them.

## Motivation / Business Value
- The twins drift today, and about a dozen open follow-ups name it:
  `fu-installer-flag-lattice-no-mode` (P2: six flags resolve as an
  unsequenced boolean lattice; `--uninstall --decline-ref-guard` exits 0
  leaving the pre-commit hook installed, `--print <bogus>` exits 0),
  `fu-three-readers-three-whitespaces` (P2: the `.ps1`, the shell mirror
  and the JS reader read the same `ref_guard` line three ways),
  `fu-seterr-suspended-left-of-or` (P2), `fu-installer-want-refguard-overloaded`,
  `fu-ps1-writeerror-terminates-before-exit`, `fu-ps1-symlink-config-replaced`,
  `fu-ps1-decline-not-disclosed`, `fu-ps1-refusal-no-manual-merge`,
  `fu-ps1-decline-force-advice-wrong`, `fu-ps1-enable-refguard-no-rationale`,
  `fu-ps1-setcontent-rewrites-seed-eol`, `fu-hook-tmpl-final-lf-parity`,
  `fu-hook-installer-not-a-repo-msg`, `fu-uninstall-refguard-leaves-armed`,
  `fu-doubled-key-has-no-repair`.
- Every installer fix is made twice today, and the `.ps1` side is covered
  mostly by pins on its source text, which break on a legitimate edit and
  pass on a behaviour regression.
- The owner decided (plan section 4, decision 1) that Node is a hard
  prerequisite on the install and update path, so the port needs no shell
  fallback.

## Scope
- In scope:
  - One Node module (Planning names it; `.aai/scripts/install-pre-commit-hook.mjs`
    is the default) holding all installer policy, accepting both the bash
    long-flag form (`--force`, `--uninstall`, `--print [kind]`,
    `--hooks <csv>`, `--decline-ref-guard`, `--arm-ref-guard`, `-h|--help`)
    and the PowerShell parameter form the `.ps1` accepts today, with the
    current exit codes or a numbered DR where they differ.
  - Slice (a): every flag combination resolves to exactly one mode before
    any write; contradictory combinations are refused with a usage exit;
    the `ref_guard` policy is read and written only through
    `guard-config.mjs` (one reader for all three whitespace cases, a
    symlinked config is written through, not replaced; line endings of the
    seeded file are kept).
  - Slice (b): the hooks directory is the one Git resolves
    (`git rev-parse --git-path hooks/<name>`, honouring `core.hooksPath`
    and linked worktrees); each selected slot is attested (absent,
    AAI-owned and current, AAI-owned and older, foreign, symlinked,
    unprovable) before any slot is written, so a refusal never leaves a
    partial install; an older AAI pre-commit hook is upgraded in place as
    today.
  - Slice (c): both scripts rewritten as thin launchers; source-shape pins
    against either installer migrated to behaviour tests on the module (or
    kept as launcher pins), each migrated pin named.
  - The frozen bash and PowerShell twins kept as test references under
    `tests/fixtures/` with a sha256 pin, and a differential corpus comparing
    the module against both references in scratch repositories.
  - `node:test` coverage for every rule and every drift found; each
    behaviour difference from either twin is a numbered decision (DR-n)
    with its reason and a test; each twin divergence is resolved toward one
    behaviour.
  - The ride-8 install-path parity harness runs the Node module as a third
    twin on the hook-installer scenarios.
  - Pester for the `.ps1` launcher under Windows PowerShell 5.1 and pwsh 7
    in the existing Windows job; a scratch `aai-sync` install proving both
    launchers run the module.
  - Close each open installer follow-up the port resolves, with evidence
    per item.
  - Full wiring: suite map with shared libraries, suite weights,
    cd-subshell baseline, hygiene-pack pins, nested-suite lint, Pester in
    the Windows job, `ps1-quality.yml` path lists, prompt-diet ledger if a
    prompt changes.
  - CHANGELOG `## [unreleased] — <title>` entry (the hook installer now
    requires Node downstream).
- Out of scope:
  - Changing the hook bodies themselves (the templates of ride 4) or what
    they check, beyond what the installer reads from them.
  - Porting `aai-sync` (ride 12) or `aai-update` again.
  - Renaming `docs/ai/docs-audit.yaml` (`fu-docs-audit-yaml-misnamed-guard-config`).

## Affected Area
- `.aai/scripts/install-pre-commit-hook.sh`, `.aai/scripts/install-pre-commit-hook.ps1`,
  the new Node module, `.aai/scripts/lib/guard-config.mjs`
- `.aai/system/PROFILES.yaml`, `.aai/SKILL_UPDATE.prompt.md` and other
  prompts naming the installer (invocation text only, if needed),
  `docs/USER_GUIDE.md`
- `tests/skills/` (installer, ref-guard, hook-template, hygiene, doctor,
  parity suites; new node:test and Pester files; wiring files),
  `tests/fixtures/` (frozen references)
- `.github/workflows/ps1-quality.yml`, `CHANGELOG.md`

## Desired Behavior (To-Be)
- `bash .aai/scripts/install-pre-commit-hook.sh [args]` and
  `powershell -File .aai/scripts/install-pre-commit-hook.ps1 [args]` both
  run the Node module with the same arguments and exit with its code.
- On every hook-installer scenario of the parity harness the Node module
  leaves the same hooks, the same `docs/ai/docs-audit.yaml` and the same
  exit code as the reference twins, except where a numbered DR says
  otherwise.
- Without Node, both launchers print one refusal line with an install hint
  and exit non-zero, changing nothing.

## Acceptance Criteria
- AC-001: Every flag combination of either twin resolves to one mode before
  any write; a contradictory combination and an unknown `--print` kind are
  refused with a usage exit and change nothing (node:test per combination).
- AC-002: The `ref_guard` policy is read and written only through
  `guard-config.mjs`; the whitespace, BOM and line-ending cases of
  `fu-three-readers-three-whitespaces` read the same; a symlinked config is
  written through; a doubled key is refused with a repair hint.
- AC-003: Slot attestation covers absent, current AAI, older AAI (upgrade in
  place, every byte outside the guard block kept), foreign, symlinked and
  unprovable slots in the hooks directory Git resolves (including
  `core.hooksPath` and a linked worktree); a refusal in one selected slot
  writes no slot.
- AC-004: The parity harness runs the Node module as a third twin on the
  hook-installer scenarios and passes with no new allowlist row except one
  with a reviewed reason.
- AC-005: Both launchers are 20 lines or fewer, hold no policy, pass
  arguments and exit codes through, and refuse without Node with an install
  hint; Pester proves the `.ps1` under 5.1 and 7; a scratch `aai-sync`
  install runs both.
- AC-006: Source-shape pins against either installer are migrated to
  behaviour tests (each named); existing suites pass; resolved follow-ups
  closed with evidence; wiring complete; CHANGELOG entry present.

## Verification
- `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-git-ref-guard.sh`
  and the hook-template, parity, doctor, hygiene and new suites pass.
- The Pester files pass under pwsh 7 locally and both engines in CI.

## Constraints / Risks
- The installer is on the guard path (it installs the ref-guard and the
  close gate): ceremony L3, merge by the owner.
- `/aai-update` runs the installer after every sync; a consumer updating
  from an older layer runs the new launcher in the same run, so the module
  must be synced before the launcher calls it (Planning checks the order).
- Tests install hooks only into scratch repositories the test created;
  never into this repository or any real one. No test may reach a
  container daemon or delete anything it did not create.
- Secrets preflight: no local secret is referenced by this scope.

## Notes
- Source: roadmap item `pre-commit-installer-on-node`; plan ride 11.
- Precedents: CHANGE-0241 (reaper), CHANGE-0261 / SPEC-0306 (bootstrap on
  Node), CHANGE-0262 / SPEC-0307 (updater on Node), SPEC-0284 (parity
  harness), SPEC-0278 (hook bodies single source).
- Worktree: owner-directed own worktree.
- Autopilot defaults: human_time_minutes null; no implementation-mode menu
  (Planning decides).
