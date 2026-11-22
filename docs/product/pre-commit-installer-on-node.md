---
id: pre-commit-installer-on-node
type: product
capability: pre-commit-installer-on-node
status: current
delivered_by:
  - pre-commit-installer-on-node
spec: docs/specs/SPEC-0308-spec-pre-commit-installer-on-node.md
updated: 2026-11-22
---

# The git hook installer runs on Node behind thin launchers

## What it does

The hook installer puts the three AAI git hooks into the hooks directory
git actually uses (`git rev-parse --git-path hooks/<name>`, which follows
`core.hooksPath` and linked worktrees):

- `pre-commit` (marker AAI:INDEX-AUTOGEN) with its AAI:GUARD-CHECKS block;
- `reference-transaction` (AAI:REF-GUARD), which refuses a write to main
  unless `AAI_GIT_WRITE=1` is set;
- `pre-push` (AAI:CLOSE-GATE).

It also records the ref-guard policy (`ref_guard: armed|declined`) in
`docs/ai/docs-audit.yaml`. `/aai-update` runs it after every sync.

The bash and PowerShell copies of the installer used to drift. They are now
one Node.js module behind two small launchers, so both entries behave the
same way. The hook bodies still come from the shared templates in
`.aai/templates/git-hooks/`.

Node.js 22 or later is now required. Without it, both launchers refuse,
print an install hint and change nothing.

## How to use it

- macOS, Linux, Git Bash: `./.aai/scripts/install-pre-commit-hook.sh [--force] [--uninstall] [--print [index|ref-guard|guard-checks|pre-push]] [--hooks <csv>] [--decline-ref-guard] [--arm-ref-guard]`
- Windows PowerShell 5.1 or pwsh 7: `powershell -NoProfile -File .aai/scripts/install-pre-commit-hook.ps1`. It takes the same long flags or the PowerShell names (`-Force`, `-Uninstall`, `-Print`, `-Hooks`, `-DeclineRefGuard`, `-ArmRefGuard`).
- A plain run installs the missing selected hooks. It leaves current AAI
  hooks alone, and it upgrades an older AAI pre-commit hook in place by
  inserting the guard block. It skips the ref-guard when the policy says
  `declined`.

## Data model

There is no new file. The installer writes only:

- the selected hook files;
- the `ref_guard:` line of `docs/ai/docs-audit.yaml`.

The policy is now read and written only through
`.aai/scripts/lib/guard-config.mjs`. The writer follows a symlinked config
file and keeps the file's mode, its line endings and a leading BOM. When
the file has more than one `ref_guard:` line, `--arm-ref-guard` and
`--decline-ref-guard` repair it.

A run writes a hook only through a temporary file that it created itself
and then renames into place. It never removes a temporary file it did not
create.

## Interfaces and contracts

- `.aai/scripts/install-pre-commit-hook.sh` is a 9-line launcher. It passes
  the arguments and the exit code through.
- `.aai/scripts/install-pre-commit-hook.ps1` is an 18-line launcher. It
  converts PowerShell switches, `-Switch:$false` and comma arrays into the
  module's long flags.
- `.aai/scripts/install-pre-commit-hook.mjs` holds all installer logic.
- Every flag combination resolves to exactly one mode before anything is
  written. These now exit 2 and change nothing:
  - contradictory modes;
  - a flag that has no effect in the mode, such as `--force` with
    `--uninstall`, `--print` or `--decline-ref-guard`, or `--hooks` with
    `--print`;
  - an unknown `--print` kind or `--hooks` token;
  - an unknown argument;
  - the PowerShell abbreviations `-F` and `-Verbose`.
- Every selected slot is checked before any slot is written. A slot is
  refused when it holds one of these, and then the whole run writes
  nothing:
  - a foreign hook (a hook without the AAI marker);
  - a symlink the installer cannot prove it owns;
  - a directory or other non-file;
  - more than one guard block.
- A declined ref-guard slot is neither checked nor written.
  `--decline-ref-guard` is refused when that slot holds a foreign hook
  (including through a symlink), a directory, or a dangling symlink.
- Exit codes:
  - 0: success;
  - 1: refusal, not a repository, git or Node missing;
  - 2: usage error.
- The module differs from the old twins in 23 places. Each one is a
  numbered decision (DR-1 to DR-23) in the spec, with its own test.

## Limits and non-goals

- Node.js 22 or later is required; there is no shell fallback.
- The hook bodies and what they check are unchanged.
- Filed as follow-ups rather than changed:
  - the installer is not yet on the L3 protected-paths list;
  - the same working-directory `..` pattern in the updater and the
    bootstrap module;
  - older test suites that do not clear the caller's `GIT_*` environment;
  - the doubled-key warning wording;
  - the `--hooks --print` line missing from the CHANGELOG.

## Links

- Request: docs/issues/CHANGE-0263-pre-commit-installer-on-node.md
- Spec: docs/specs/SPEC-0308-spec-pre-commit-installer-on-node.md
- Validation evidence: docs/ai/reports/VALIDATION-20261121T232324Z-pre-commit-installer-on-node.md
- Review: docs/ai/reviews/review-pre-commit-installer-on-node-20261122T000337Z.md
