---
id: sync-on-node
type: product
capability: sync-on-node
status: current
delivered_by:
  - sync-on-node
spec: docs/specs/SPEC-0310-spec-sync-on-node.md
updated: 2026-11-22
---

# The AAI layer sync runs on Node behind thin launchers

## What it does

The layer sync copies the vendored AAI layer (`.aai/`, the harness skill
folders, the root shims, the managed `.gitignore` blocks, the Session-start
hooks) from a source checkout into a project, prunes files the source no
longer ships, and writes the AAI pin and a conflict advisory. It is what
`/aai-update`, `install.sh` and `install.ps1` run. It now runs as one
Node.js module behind two small launchers instead of two separate bash and
PowerShell scripts that used to drift. The files a sync writes are the same
as before; each behaviour that differs from the old scripts is a numbered,
tested decision. Node.js 22 or later is now required: without it both
launchers refuse, print an install hint and change nothing.

The sync is also stricter about never touching anything outside the
project. It refuses before any write when the target is the source, sits
inside the source, or names the source with other letter case or through a
link; when the source lies inside a directory of the target the sync
replaces; and when a managed path, the `.gitignore`, the shipped hook
snapshot or a merge temp file in the target is a link leading out of the
project.

## How to use it

- macOS, Linux, Git Bash: `./.aai/scripts/aai-sync.sh <target> [--profile core|extended]`
- Windows PowerShell 5.1 or pwsh 7: `powershell -NoProfile -File .aai/scripts/aai-sync.ps1 -TargetRoot <target> [-Profile core|extended]`
- Usually you do not call it yourself: `/aai-update` runs the source's sync.
- An existing install picks up the launchers and the module with its next
  `/aai-update`; the source's own sync is the new launcher, so the first
  update of an old install already runs on Node.
- To check an install: run the sync a second time; it reports no changes,
  and `.aai/system/AAI_PIN.md` names the source commit.

## Data model

None new. The sync writes the same files as before (`.aai/`, harness skill
folders, root shims, `.gitignore` managed blocks, `.aai/system/AAI_PIN.md`,
the advisory under `docs/ai/reports/`, the shipped hook snapshot under
`.aai/cache/hooks-shipped/`). `.aai/scripts/lib/gitignore-block.sh` is gone
from the source; a core-profile target keeps a leftover copy as an unused
target-only script, an extended target loses it with the next sync.

## Interfaces and contracts

- `.aai/scripts/aai-sync.sh` and `.aai/scripts/aai-sync.ps1`: thin launchers
  (no policy) that pass the arguments and the exit code through.
- `.aai/scripts/aai-sync.mjs`: the module holding all sync rules, with two
  shared helpers, `lib/gitignore-block.mjs` (the managed `.gitignore`
  blocks) and `lib/resolve-base.mjs` (the working-directory rule also used by
  the updater, the bootstrap and the git hook installer).
- Exit codes: 0 success; 1 Node missing, a refused target or source (the
  line says which), or an internal error; 2 a usage problem (one error line
  and the usage line on stderr). `-h` prints the help and exits 0.
- New refusals, all before any write: a target equal to, inside, or a
  case or link spelling of the source; a source inside a managed entry of
  the target; a managed path or the `.gitignore` that is a link leaving the
  target. A link at the shipped hook snapshot path or a merge temp name is
  replaced by a regular file instead of being written through.
- Dropped: the moves of the pre-2026-03 layout (`ai/`, `scripts/ai-os-*`,
  the root `PLAYBOOK.md`, `docs/workflow`, `docs/roles`, `docs/templates`
  and the old `docs/ai/*` copies). A project that still has that layout
  removes those paths by hand; `migrate-state-to-local` still handles the
  runtime-state move.

## Limits and non-goals

- Node.js 22 or later is required; there is no shell fallback.
- Windows PowerShell 5.1 and the native Windows legs are proven in CI, not
  on the development host.
- Filed as follow-ups rather than changed: the source-inside-target refusal
  also covers managed folders the sync never replaces wholesale; file
  identity on Windows compares 64-bit ids as numbers; a spaced PowerShell
  5.1 path ending in a backslash is not passed through cleanly.

## Links

- Request: docs/issues/CHANGE-0265-sync-on-node.md
- Spec: docs/specs/SPEC-0310-spec-sync-on-node.md
- Validation evidence: docs/ai/reports/VALIDATION-20261122T2015Z-sync-on-node.md
- Plan: docs/analysis/node-first-remaining-plan.md
