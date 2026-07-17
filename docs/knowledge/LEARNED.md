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
- [2026-07-04] When a feature worktree was seeded with copies of not-yet-committed docs from the main checkout, delete those stale untracked copies in the main checkout (and reset generated files like docs/INDEX.md) BEFORE `git pull` after the PR merges — otherwise the pull silently aborts on the untracked-vs-incoming collision while its output still prints "Updating …" (source: post-merge of PR #34/#36; the tail of the pull output hid the abort).

## Architecture
<!-- Example: - [2026-03-08] Use queue for email sending, never synchronous in request handler (source: code review) -->
- [2026-07-01] Framework-owns-HOW invariant: the target project declares WHAT to run (its test/build command); AAI owns HOW it runs. Every externally-spawned process must be (a) in its own killable process group, (b) resource-bounded (e.g. vitest `maxForks`), (c) reaped on the step boundary (scoped to `$PWD`+etime, never global), and (d) accounted for in the tick log. Prefer safe-by-construction via `aai-bootstrap` defaults over post-hoc remediation. Silent resource growth is a bug — make it visible (source: ISSUE-0002).
- [2026-07-03] A pre-commit content check must evaluate the STAGED blob (`git show ":<path>"`), never the worktree file. Detecting a change via `git diff --cached` but then validating the on-disk file is a TOCTOU hole: a staged, unreconciled change can pass whenever the worktree holds compensating unstaged edits, so the bad staged version is still committed. Gate what is actually being committed (source: PR #27 F2 — Codex found the SPEC-0011 G5 close-gate hook gating the worktree instead of the staged spec).

## Conventions
<!-- Example: - [2026-03-08] Write repository documents in English, chat in user's language (source: project rule) -->

## Session 2026-07-15/16 (P1 delivery + follow-ups)

- `tests/skills/test-aai-worktree.sh` fails deterministically in its scratch-git
  fixture on this machine ("Commit not found in feature branch") — known
  pre-existing environmental failure, reproduced on clean main repeatedly.
  Verify suspected regressions via stash/main comparison before chasing it.
  (Source: CHANGE-0012/0010/0009 validation runs, 2026-07-15.)
- `docs/ai/archive/worktrees/` is this repo's local, untracked convention for
  archiving a worktree's STATE.yaml before `git worktree remove` (established
  2026-07-15; consumed by ledger-recovery flushes). Do not delete casually.
- Universal workflow lessons from this session (merge-conflict resolution,
  no-number-prediction, verify-merge, cleanup-after-MERGED, enforce flip)
  were promoted INTO the vendored layer (SPEC learned-to-layer-promotion) —
  they deliberately do NOT live here, so vendored projects inherit them.

## Session 2026-07-17 (CHANGE-0030/SPEC-0041 TDD)

- `tests/skills/test-aai-prompt-diet.sh` TEST-010 (corpus byte-budget floor,
  `BASELINE_PROMPT_BYTES` / `REQUIRED_REDUCTION_BYTES`) already FAILS on clean
  main — reproduced via git-stash comparison before touching anything (net
  reduction 28187 bytes < 28672 required, ~485B short at c144736/PR #92).
  Known pre-existing, out-of-scope environmental failure, same category as
  the 2026-07-15 `test-aai-worktree.sh` entry above: verify via stash/main
  comparison before chasing it as a regression. `test_010_seam_survival` in
  `tests/skills/test-aai-ceremony-levels.sh` re-runs this suite and therefore
  ALSO fails pre-existing (the whole `set -euo pipefail` script aborts at that
  point) — run new/other stanzas via the file's single-function invocation
  mode (`bash tests/skills/test-aai-ceremony-levels.sh <fn>`), or order `main`
  to run unrelated stanzas before `test_010_seam_survival`, to avoid masking
  their results. (Source: CHANGE-0030/SPEC-0041 TDD Implementation, TEST-007
  RED/GREEN evidence, docs/ai/tdd/ceremony-lane-green.log.)

## Session 2026-07-16/17 (RES-0001 tail + delta-spec lifecycle)

- Per-scope metrics are LOST if a worktree's `STATE.yaml` is not archived to
  `docs/ai/archive/worktrees/` BEFORE `git worktree remove`. The archive
  convention already existed (see above), but it was not followed for the
  l1-close-gate / delta-stage-2 / delta-stage-3 scopes this session, so their
  ledger entries are unrecoverable — and reconstructing them post-hoc would
  fabricate reliability data (forbidden by SPEC-0032 truth-scoring). Fix the
  ORDER: `cp <wt>/docs/ai/STATE.yaml docs/ai/archive/worktrees/STATE-<slug>-<ts>.yaml`
  (or run the metrics flush) as the FIRST post-MERGED cleanup step, before
  removing the worktree. (Source: this session's wrap-up.)
- Two independent gates are not redundant: on delta-stage-3 the dual-verdict
  review PASSED by tracing the code, but independent validation on a DIFFERENT
  model FAILED it by actually running multi-run fixtures — catching a tombstone
  deletion that reused a retired REQ id. For deterministic writers, a validator
  that executes adversarial multi-run scenarios beats static review. Keep both.
  (Source: SPEC-0038 validation, PR #88.)
