---
id: universal-routines
type: product
capability: universal-routines
status: current
delivered_by:
  - CHANGE-0128
spec: docs/specs/SPEC-0115-spec-universal-routines.md
updated: 2026-08-08
---

# Universal standing routines

## What it does

Lets an operator turn a vendored, agent-neutral routine template (for example
the morning "scryer" digest) into a concrete scheduled-agent installation for
any harness, on demand. Previously the morning scryer existed only as a
hand-rolled Anthropic-cloud trigger config: not reproducible, not reviewable,
not portable off Claude Cloud, and never test-fired at creation. Now the
routine is a plain, git-diffable file in the repo, and `/aai-routine` renders
it into the exact payload the operator needs to install — a Claude cloud
routine spec block, or a crontab line + headless-CLI runner (macOS/Linux) /
Windows Scheduled Task (Windows) for Codex, Gemini, or any other CLI agent.
Nothing is installed automatically: the skill only prints text for the
operator (or the harness's own scheduling skill) to install, and it never
runs from bootstrap, sync, or any automatic path.

A merge-enabled routine (one allowed to merge PRs on the operator's behalf)
requires an explicit, machine-checked authorization record in the decisions
ledger; absent one, the routine emits in report-only mode and says so loudly.

## How to use it

- Invoke the `/aai-routine` skill (or, in a harness without skill wrappers,
  ask for "the routine instantiation skill"). It asks for: routine name
  (default `SCRYER`), target harness (`claude`, `codex`, `gemini`, or
  `generic`), target OS (`macos`, `linux`, or `windows`), repository slug,
  cron schedule, model id, timezone, and whether merge should be requested
  (and if so, the authorization ref to check).
- Under the hood it runs:
  ```bash
  node .aai/scripts/routine-emit.mjs --routine SCRYER --harness <harness> \
    --os <os> --repo <slug> --schedule "<cron>" --model <id> --tz <zone> \
    [--merge --ref <ref>]
  ```
- The skill relays the full output verbatim, including any
  `MERGE DISABLED — ...` stderr line, and then walks the operator through the
  emitted `## TEST AT CREATION` block: fire the routine once immediately
  after installing it, and confirm a digest was produced, the run did not
  crash, and any degraded sections are named — before considering the
  instantiation complete.
- For a non-Claude harness, the operator saves the printed prompt text into
  the named `<name>.prompt.md` file next to the runner script(s) before
  installing the crontab line or scheduled task.

## Data model

- **`routine_authorization` record** (new type, appended to
  `docs/ai/decisions.jsonl`, append-only — existing lines are never edited):
  `type: "routine_authorization"`, `ref` (the routine's identifier, e.g.
  `aai-morning-scryer`), `by: "human"`, `grants` (array, must include
  `"merge"`), `constraints` (array, e.g. `ci_green`, `bot_comments_answered`,
  `never_l3`), `derived_from` (provenance pointer to the original human
  decision this record transcribes). The merge guard scans this ledger for a
  line satisfying all four required fields; any read/parse failure, or the
  absence of a matching record, is treated as NO authorization (fail-closed),
  never as an error that skips the check.
- **Routine template** (`.aai/routines/<NAME>.routine.md`): a plain Markdown
  file with a `## Placeholders` documentation block (stripped before
  emission) and a `<!-- MERGE-GATES:START -->` / `<!-- MERGE-GATES:END -->`
  marker pair delimiting the merge-gate section. Exactly four placeholder
  tokens are substituted: `{{REPO}}`, `{{SCHEDULE}}`, `{{MERGE_ALLOWED}}`,
  `{{MODEL}}`. The shipped template is `.aai/routines/SCRYER.routine.md`
  (the morning scryer contract: prerequisite probes, resilience rule,
  three merge gates, Czech digest shape, untrusted-data rule, merge-only-write
  rule).

## Interfaces and contracts

- **`/aai-routine` skill** (`.aai/SKILL_ROUTINE.prompt.md`, wrapped under
  `.claude|.agents|.codex|.gemini/skills/aai-routine/`): on-demand only,
  invocation never appears in bootstrap, sync, loop, or orchestration
  automatic surfaces.
- **`node .aai/scripts/routine-emit.mjs`** — CLI, zero-dep Node stdlib only,
  zero network, emit-only (writes nothing to crontab, launchd, Task
  Scheduler, or any API).
  - Flags: `--routine <NAME>`, `--harness <claude|codex|gemini|generic>`,
    `--os <macos|linux|windows>`, `--repo <slug>`, `--schedule "<cron>"`,
    `--model <id>`, `--tz <zone>`, `[--merge --ref <ref>]`,
    `[--decisions <path>]`, `-h`/`--help`.
  - Exit codes (closed set): `0` emitted (including the degraded
    report-only case); `2` usage error (unknown flag, missing/invalid value,
    a control character in a free-text value, unknown template, or a
    template missing its MERGE-GATES marker pair) — nothing written to
    stdout; `3` an unresolved `{{...}}` placeholder survived render
    (template/value mismatch) — nothing written to stdout.
  - `--harness claude` prints one line of JSON
    (`name, cron, timezone, model, repo, merge_enabled, prompt`) plus a
    handoff instruction naming Claude's own scheduling skill as installer.
    Every other harness/OS combination prints a crontab line + POSIX runner
    (macOS/Linux) or a `Register-ScheduledTask` PowerShell block (Windows),
    always naming both twin filenames (`<name>.sh` / `<name>.ps1`). Every
    emission ends with a `## TEST AT CREATION` block.

## Limits and non-goals

- Byte-for-byte equality between a rendered contract and a LIVE cloud
  trigger's actual prompt is not asserted by any automated test (no cloud
  credentials in CI); the operator re-creates the trigger from the rendered
  output after merge and records the new trigger id in
  `docs/ai/decisions.jsonl`.
- Whether an emitted crontab line or `Register-ScheduledTask` call actually
  installs and fires on a real macOS/Linux/Windows box is not exercised by
  this repo — the mandatory test-at-creation fire is where that failure
  would surface.
- The emitted crontab line's `$(pwd)` is expanded by cron's shell at fire
  time, not at paste time — saving the runner script somewhere other than
  the directory the line was generated from will not resolve as written.
  Known limitation, tracked as a follow-up.
- Codex/Gemini headless-CLI invocation syntax is taken from this repo's own
  documented wrapper conventions, not a live run of those CLIs.
- No routine template ships pre-authorized for merge; a merge-enabled
  instantiation always requires an explicit human-recorded
  `routine_authorization` entry.

## Links

- Request: docs/issues/CHANGE-0128-universal-routines.md
- Spec: docs/specs/SPEC-0115-spec-universal-routines.md
- Review: docs/ai/reviews/review-20260808T132824Z-CHANGE-0128-universal-routines.md
