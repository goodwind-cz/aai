---
id: update-on-node
type: product
capability: update-on-node
status: current
delivered_by:
  - update-on-node
spec: docs/specs/SPEC-0307-spec-update-on-node.md
updated: 2026-11-21
---

# The AAI layer updater runs on Node behind thin launchers

## What it does

`/aai-update` refreshes a project's vendored AAI layer from the canonical
repository: it fetches the source (a local checkout, or a clone through gh,
git, then an anonymous git clone), runs the source's sync into the project,
and prints the changed files, the AAI_PIN lines, the newest conflict report,
the doctor field report and the next steps. It now runs as one Node.js
module behind two small launchers. The bash and PowerShell copies of the
updater used to drift; they now share one behaviour. Each launcher keeps
running the sync it ran before (`aai-sync.sh` from the shell launcher,
`aai-sync.ps1` from PowerShell). Node.js 22 or later is now required:
without it, both launchers refuse, print an install hint and change nothing.

## How to use it

- macOS, Linux, Git Bash: `./.aai/scripts/aai-update.sh [--repo <slug|url|path>] [--ref <ref>] [--dry-run] [--keep-temp] [--force]`
- Windows PowerShell 5.1 or pwsh 7: `powershell -NoProfile -File .aai/scripts/aai-update.ps1` with the same long flags, or `-Repo`, `-Ref`, `-DryRun`, `-KeepTemp`, `-Force`.
- Or ask the agent for `/aai-update`, which picks the right launcher.
- An older install updates once through its old updater, which brings in
  the new launchers and module; every later update runs on Node.

## Data model

None. What the sync writes into the project is unchanged; the updater
creates nothing outside the project except its own temporary clone
directory (`aai-src.*` in the temp directory), which it removes on every
exit path unless `--keep-temp` is given.

## Interfaces and contracts

- `.aai/scripts/aai-update.sh`: thin launcher (sh, bash, dash); names the
  bash sync runner and passes arguments and the exit code through.
- `.aai/scripts/aai-update.ps1`: thin launcher for Windows PowerShell 5.1
  and pwsh 7; names its own engine as the sync runner and restores the
  caller's environment afterwards.
- `.aai/scripts/aai-update.mjs`: the module holding all update logic.
- Exit codes: 0 success; 1 an unknown argument, a flag without a value, or
  Node missing (the message says which); 2 refused because the project
  looks like the canonical AAI repository (`--force` overrides); 3 the
  source could not be fetched (git missing is named); 4 the fetched source
  has no sync script; a failing sync passes its own exit code through;
  130 or 143 when the updater itself is interrupted (Ctrl-C or SIGTERM),
  with its temporary clone removed and nothing later run.
- Behaviour that changed from the old copies, each a numbered decision in
  the spec: help never runs an update; an unknown argument and a missing
  flag value are errors; the canonical-repo check ignores case; a dry-run
  starts no git command in a local source; a failing sync ends the run under
  PowerShell too; a clone killed by a signal the updater did not receive is
  a failed attempt and the next method is tried, as before.

## Limits and non-goals

- Node.js 22 or later is required; there is no shell fallback.
- The sync itself is not ported here; it is a later ride.
- Filed as follow-ups rather than changed: a local source checkout is
  switched to `--ref`; the kept temp path is not printed; a spaced
  PowerShell 5.1 path ending in a backslash, and non-console PowerShell
  hosts as the sync runner, are not handled.

## Links

- Request: docs/issues/CHANGE-0262-update-on-node.md
- Spec: docs/specs/SPEC-0307-spec-update-on-node.md
- Validation evidence: docs/ai/reports/VALIDATION-20261121T100745Z-update-on-node.md
