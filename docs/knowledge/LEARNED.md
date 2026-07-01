# Project-Specific Learned Rules

<!--
  This file captures corrections and learnings from user feedback.
  Rules here are loaded into context for every session to prevent repeating mistakes.

  Format: - [YYYY-MM-DD] Rule text (source: how this was learned)

  Source: Inspired by pro-workflow learning system (https://github.com/rohitg00/pro-workflow)
-->

## Code Style
<!-- Example: - [2026-03-08] Always use `logger.debug()` instead of `console.log()` (source: user correction) -->

## Testing
<!-- Example: - [2026-03-08] E2E tests must use playwright-mcp server, not local Playwright (source: user preference) -->
- [2026-07-01] A `vitest run` (or any runner) that does not exit on its own is a test-leak bug — an open handle / unhandled rejection (timer, unclosed mock client, dangling promise), NOT "pre-existing teardown noise". Fix the open handle so the process exits; consider `test.dangerouslyIgnoreUnhandledErrors=false` so it FAILS loud instead of hanging (source: ISSUE-0002 — a long aai-loop orphaned ~40 vitest trees / ~5.6 GB).

## Workflow
<!-- Example: - [2026-03-08] Always run /aai-bootstrap after adding new npm packages (source: debugging session) -->
- [2026-07-01] The loop and test skills must NEVER launch `vitest`/`tsc`/dev-servers directly — route every externally-spawned command through the AAI test wrapper (`.aai/scripts/aai-run-tests.sh`) so a hung process can't outlive the step that spawned it (source: ISSUE-0002).

## Architecture
<!-- Example: - [2026-03-08] Use queue for email sending, never synchronous in request handler (source: code review) -->
- [2026-07-01] Framework-owns-HOW invariant: the target project declares WHAT to run (its test/build command); AAI owns HOW it runs. Every externally-spawned process must be (a) in its own killable process group, (b) resource-bounded (e.g. vitest `maxForks`), (c) reaped on the step boundary (scoped to `$PWD`+etime, never global), and (d) accounted for in the tick log. Prefer safe-by-construction via `aai-bootstrap` defaults over post-hoc remediation. Silent resource growth is a bug — make it visible (source: ISSUE-0002).

## Conventions
<!-- Example: - [2026-03-08] Write repository documents in English, chat in user's language (source: project rule) -->
