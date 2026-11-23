---
id: node-first-phase5-closeout
type: product
capability: node-first-phase5-closeout
status: current
delivered_by:
  - node-first-phase5-closeout
spec: docs/specs/SPEC-DRAFT-spec-node-first-phase5-closeout.md
updated: 2026-11-23
---

# Every shipped script is a thin launcher or kept native on purpose

## What it does

The AAI layer's shell and PowerShell scripts used to carry two copies of the same logic. After this change every script under `.aai/scripts` is either a thin launcher of one Node module (20 code lines or fewer, no policy of its own) or sits on a short, public list of scripts that stay native, each with a stated reason. A check that runs on every pull request fails when a new script is neither. Three smaller things ship with it: `aai-release.ps1` becomes a thin launcher and its module reads the PowerShell flag forms, the failure message of `/aai-share` can no longer print part of a Cloudflare credential, and the install-path parity harness now also runs the shipped sync and update launchers and checks, on the native Windows job, that the update leaves no oddly named directory behind and that the sync records Windows paths in the Windows spelling.

## How to use it

- Release from PowerShell as before: `powershell -NoProfile -File .aai/scripts/aai-release.ps1 -Version v1.2.3 -DryRun`. Flag names are case-insensitive; `-Confirm`, `-Yes`, `-NoRemote` and a switch with `:$true` or `:$false` work as documented. Node.js 22 or later is required; without it the launcher prints its refusal and exits 20.
- See which scripts stay native: the table "Kept native scripts" in `docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md`.
- Run the strict check yourself: `node tests/skills/lib/script-classes.mjs strict --root .` (exit 0 when every script is a launcher or a kept-native row with a reason).
- Read the measured state of the migration in section 7 of `docs/analysis/node-first-remaining-plan.md`.

## Data model

None. The kept-native table is a Markdown table in RFC-0017; the strict check and the plan's section 7 read it and write nothing.

## Interfaces and contracts

- `aai-release.ps1`: thin launcher (20 code lines or fewer, ASCII, no `param` block) that passes its raw arguments to `aai-release.mjs --launcher ps1`; exit codes unchanged (10 outside a git repository, 11 without CHANGELOG.md, 20 without node, the module's own codes otherwise).
- Release flag grammar under PowerShell: unchanged for every documented form and for an unambiguous abbreviation of a documented flag. Changed: a common parameter such as `-Verbose` or `-ErrorAction` is refused as an unknown argument (exit 1); a bare version word is accepted only as the first bare word and only without `-Version`; `-Version` without a value prints `REFUSED: --version needs a value.` and exits 1.
- `/aai-share` failure output: never holds 8 consecutive characters of `CLOUDFLARE_API_TOKEN` or `CLOUDFLARE_API_KEY` and never a raw ESC byte.
- Parity harness report: `host_checks` entries and `AAI-HOST-CHECK <id> <scenario> <twin> <status> checked=<n>` lines (test and CI tooling, not a shipped surface).

## Limits and non-goals

- Five bash scripts stay native on purpose (the Claude hook gate pre-filter and four libraries of the bash test runner and suite framework), together with the four scripts already on the list; porting them is not planned.
- The seven retirement launchers stay for one more release and are then deleted.
- The Windows proofs (no odd directory after an update, drive-letter source path, the PowerShell 5.1 Pester run) exist only on the hosted Windows runner; this document does not claim them until the record of the hosted run is committed.
- Not changed here: the share launcher's argument binding, the update launcher's colon-switch handling and the open follow-ups named in the spec.

## Links

- Request: docs/issues/CHANGE-DRAFT-node-first-phase5-closeout.md
- Spec: docs/specs/SPEC-DRAFT-spec-node-first-phase5-closeout.md
- Validation evidence: docs/ai/tdd/node-first-phase5-closeout/
