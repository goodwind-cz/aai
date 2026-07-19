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
  **RESOLVED 2026-07-17 (DEBT-0002/SPEC-0048):** the fixed byte floor was
  calibrated for the SPEC-0017 diet corpus and never re-baselined as later
  canon-mandated additions (dual-verdict review taxonomy, VALIDATION 8a,
  CEREMONY LANE, RED_CLASS, SECRETS PREFLIGHT, doc-number reservation,
  ceremony-lane surfaces) legitimately grew it. Fix: a `JUSTIFIED_GROWTH_BYTES`
  ledger constant (6144 B, itemized inline) is credited into the reduction —
  `BASELINE_PROMPT_BYTES`/`REQUIRED_REDUCTION_BYTES` stay unchanged (rewriting
  them would erase history and IS the blank-raise anti-pattern) — plus a new
  `0 <= headroom <= HEADROOM_CAP` (2048 B) anti-bloat guard so the credit
  cannot be padded and future unjustified growth still fails. Also raised the
  TEST-011 thin-wrapper line ceiling 40->45 (zero headroom broke live on a
  1-line canon growth). `test_017`'s pre-existing-shortfall tolerance in
  `test-aai-ceremony-levels.sh` is removed — a plain exit-0 assertion now
  suffices, and the full ceremony suite is green end to end. (Source:
  DEBT-0002 TDD Implementation, docs/ai/tdd/red-20260717T185005Z-*.log,
  docs/ai/tdd/red-20260717T185240Z-*.log,
  docs/ai/tdd/green-20260717T185321Z-*.log,
  docs/ai/tdd/green-20260717T185451Z-*.log.)

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

## Session 2026-07-17/19 (workflow-hardening arc + spec-id collision cascade)

- Spec DRAFT slugs MUST be `spec-`-prefixed (`id: spec-<change-slug>`). A spec
  named with a bare-slug id collides with its change/issue's id; the audit's
  `byId` map is last-writer-wins, so one doc silently overwrites the other and
  the audit still reports CLEAN. Four collisions shipped this session
  (SPEC-0048/0049/0051/0056) before being caught. Defence-in-depth now exists
  at three layers: lint at freeze (`spec-lint` `spec-id-shape`, SPEC-0058),
  detect at audit (`docs-audit` duplicate-doc-id, SPEC-0057), fail-closed at
  close (`close-work-item.mjs`). (Source: ISSUE-0015 remediation; SPEC-0057/0058.)
- Mechanize any recurring agent-hand-performed governance ceremony that has
  correctness rules. The close ceremony (status flip + links + the exact
  slug-ref event set + re-audit) was ~10 manual steps and tripped
  false-open/false-done 3× before `close-work-item.mjs` made it
  correct-by-construction (snapshot -> apply -> self-verify via the real audit
  -> rollback on drift). Same for `metrics-flush` (stop emitting wrong-ref
  close events) and worktree telemetry (reconcile at PR). (Source: CHANGE-0037/
  0038/0039.)
- A new audit/lint GATE must be validated against the WHOLE existing corpus AND
  all test fixtures before merge — not just its own scope's tests. The SPEC-0057
  duplicate-id detector correctly flipped the real repo to NEEDS-TRIAGE (3 real
  latent collisions). The SPEC-0058 `spec-id-shape` rule shipped under-migrated:
  it flagged bare-slug `type:spec` TEST FIXTURES (indistinguishable from real
  specs by content or filename), breaking `test-aai-ceremony-levels.sh` on main.
  Run the full suite matrix, not just the declared scope. (Source: SPEC-0057/
  0058; ceremony-levels fallout, CHANGE-0040.)
- `close-work-item.mjs` self-verifies full-CLEAN, so it CANNOT close a scope
  whose own change makes the repo NEEDS-TRIAGE (e.g. shipping a detector that
  flags pre-existing debt) — hand-close those, then remediate. It also
  fail-closes on an ambiguous/duplicate id — a guardrail that caught the
  SPEC-0056 collision. (Source: SPEC-0056/0057 close.)
- The prompt-diet byte floor re-breaches on EVERY scope that adds
  `.aai/*.prompt.md` prose; the anti-bloat guard only flags it when the suite
  runs (main was silently red by 764 B this session). Bumping the
  `JUSTIFIED_ADDITIONS` ledger is now part of definition-of-done for any
  prompt-touching scope, and the credit is an itemized summed array (not a magic
  number) so the fix is a self-documenting data append. (Source: DEBT-0002,
  CHANGE-0040.)
- Two operational hazards for the loop: (1) inline validation that runs
  `git checkout`/`stash` mutates the SHARED working tree — prefer worktree
  isolation for git-mutating roles. (2) Concurrent audit-touching test suites
  cross-contaminate: each drops ephemeral DRAFT docs into `docs/` while another
  runs a repo-wide strict audit -> spurious failures. Serialize them.
  (Source: ISSUE-0012 validation; CHANGE-0040 validation.)

## Session 2026-07-19 (skill-suite CI gate + Linux portability)

- A test runner that forces `sh <file>` on `#!/usr/bin/env bash` suites produces
  FALSE PASSES (bash-only syntax like process substitution `< <(…)` or arrays
  either errors early or is silently mis-parsed). Honor each suite's shebang
  (`bash "$f"` or execute directly). A serialized full-suite sweep that forced
  `sh` hid a real red (`verify-gate` TEST-006) and mis-flagged `hooks-overlay`;
  the shebang-honoring rerun surfaced 15 real failures the first pass masked.
  (Source: this session's `otestuj` v1 vs v2 runners.)
- NEVER `git clean` under `docs/` in a verification/iteration loop — the intake
  DRAFTs, frozen spec, and review report of the in-flight scope are UNTRACKED but
  wanted; `git clean` deletes them. Restore only tracked telemetry
  (`git checkout -- docs/ai/EVENTS.jsonl docs/ai/METRICS.jsonl docs/INDEX.md`).
  A `git clean -fdq docs/` between suite runs destroyed a spec+issue+review
  mid-loop (recovered by re-prompting the still-alive Planning/Review subagents).
- Metrics flush (rule 14) fires BEFORE the operator's PR step and its
  partial-flush reset (SPEC-0013 H5, triggered by a stale sibling work item like
  `pr-67-post-merge-review`) nulls `last_validation`/`code_review` — so
  `SKILL_PR` preconditions then fail. Truthfully RE-RECORD the genuine PASS
  verdicts (evidence already exists) before the PR ceremony. Candidate workflow
  fix: defer rule 14 until after PR, or don't partial-reset the just-flushed
  focus ref. (Source: PR #115/#116 ceremonies this session.)
- Skill suites are written/run on macOS (BSD tools) but CI runs Ubuntu (GNU) —
  latent BSD/GNU breakage passes locally, fails only in CI. Concrete traps found:
  `mktemp -t <bare-prefix>` errors "too few X's" on GNU (use a full `…​.XXXXXX`
  template, identical on both); `stat -f '%u'` SUCCEEDS on GNU as
  `--file-system` (wrong data) so `stat -f || stat -c` never falls through — try
  GNU `stat -c` FIRST. (Source: CHANGE-0043/SPEC-0062, RC2/RC4.)
- A fresh CI checkout lacks per-dev gitignored runtime files (`docs/ai/STATE.yaml`
  RFC-0001, `docs/ai/tdd/*.log`) and lacks a local `main` branch (detached PR
  checkout / temp repos default to `master` or an empty ref). Suites must be
  hermetic: self-seed the precondition via the canonical initializer (or
  soft-skip when genuinely absent, degrade-and-report), and build fixture repos
  with `git init -b main`. Do NOT assume a developer's environment on CI.
  (Source: CHANGE-0043 RC1/RC3.)
- The single highest-leverage structural win: skill suites were never gated in CI
  (only docs-numbering + ps1-quality ran), so reds accumulated invisibly — one
  merged red (verify-gate), three test-infra reds, and 15 Linux-portability
  failures. Adding `.github/workflows/skill-suite.yml` (run every suite honoring
  shebangs, fail on any red, slow self-hosting smoke in a separate timeboxed job)
  is the prevention. Corollary: an aggregate runner MUST dump a failing suite's
  output tail ALWAYS (not only under `--verbose`), else CI failures are opaque —
  this diagnostic change is what made the Linux root-cause analysis possible from
  the CI log alone. (Source: CHANGE-0042/0043.)
- When only CI reproduces a failure (platform-specific), CI IS the authoritative
  validator — the loop's Validation/Review subagents run on the local host and
  cannot attest green-on-Linux. Weave CI into the loop: implementer pushes, the
  CI run is the RED->GREEN evidence, Validation verifies `gh run` conclusion +
  headSha-matches-HEAD + local non-regression. (Source: CHANGE-0043 loop.)
