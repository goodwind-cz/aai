---
id: issues-skill
type: product
status: current
spec: docs/specs/SPEC-0104-spec-issues-skill.md
updated: 2026-07-28
---

# Issue triage skill (/aai-issues)

## What it does

`/aai-issues` pulls the open issues sitting on your project's git hosting
platform, triages each one, and — after you approve a short list — starts
the normal intake process for the ones you picked. It runs only when you
invoke it; it never fires automatically from the autonomous loop. On GitHub
it lists real open issues today. On Azure DevOps it explains that work items
live in Azure Boards (not repo issues) and points you at the `az boards`
commands instead of pretending to fetch something that doesn't exist there.
On any other or unrecognized git host it tells you plainly that it can't
fetch issues and to paste them in by hand or use `/aai-intake`.

## How to use it

Run `/aai-issues` (Claude) or `codex --prompt-file .aai/SKILL_ISSUES.prompt.md`
(Codex/Gemini/Copilot). Narrow the fetch with `--label <name>` or
`--limit <n>` if you only want a subset. The skill prints a triage table —
bug, feature, question, or duplicate/out-of-scope, with a suggested next
step for each — and stops for your approval before starting any intake.
Nothing is drafted until you say which items to proceed with.

Under the hood: `node .aai/scripts/aai-issues.mjs [--label <name>] [--limit <n>] [--json]`
prints a stable text table (`ISSUE #<id> [<labels>] <title>`) plus an
`ISSUES <count> platform=<p>` summary line; `--json` prints the full
machine-readable shape.

## Data model

No new persistent records. Each fetched issue is normalized in memory into
`{id, title, labels, excerpt, url}` — the excerpt is the issue body
collapsed to a single line and capped at 280 characters, purely for display;
it is never treated as instructions. Approved items become ordinary intake
documents under `docs/issues/` or `docs/specs/`, linked back to the source
issue's URL.

## Interfaces and contracts

- CLI: `node .aai/scripts/aai-issues.mjs [--label <name>] [--limit <n>]
  [--json] [--input <fixture.json>] [--remote-url <url>]`. Exit 0 for every
  classified or degraded run (a missing `gh`, an unreachable platform, or
  zero open issues are all normal, non-failing outcomes); exit 2 only on a
  bad flag, and nothing is printed in that case.
- Skill: `/aai-issues` — see `.aai/SKILL_ISSUES.prompt.md`.
- Write-back: an issue is only commented on and closed after its ride's pull
  request has merged. On Azure this becomes a work-item state transition
  instead. On an unrecognized platform there is no write-back — the
  disposition is recorded in the intake document only.

## Limits and non-goals

- GitHub is the only platform with a live fetch today. Azure's live
  `az boards` round trip is documented but deferred until a project first
  adopts Azure DevOps (no such remote exists to test against yet).
  GitLab/Bitbucket support is out of scope for this delivery.
- The skill never runs unattended — it is invocation-only, and it never
  starts an intake without one explicit operator approval per batch.
- Issue body text is always treated as data to read, never as instructions
  to follow, even if an issue's text tries to instruct otherwise.

## Links

- Request: docs/issues/CHANGE-0087-issues-skill.md
- Spec: docs/specs/SPEC-0104-spec-issues-skill.md
- Validation evidence: docs/ai/tdd/green-20260728T090000Z-aai-issues.log
