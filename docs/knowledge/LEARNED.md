# Project-Specific Learned Rules

**Where a lesson goes** (Operator contract rule 5, `.aai/AGENTS.md`). Anything
that must behave correctly *wherever AAI is installed* is implemented as a
GUARD in the vendored layer — a script, a test, a canon rule. This file records
only what is **local to this repository and its environment**.

The split was not theoretical. The entry of 2026-07-03 below said a content
check must read the staged blob, never the worktree; the same mistake shipped
twice on 2026-09-06 (PR #346, PR #347). A note asks the next author to remember.
A guard does not.
(That 2026-07-03 entry now lives in `history/LEARNED-HISTORY.md`.)

Every **dated** entry — the `- [YYYY-MM-DD] …` lines below — carries one marker:
- `[local]` — a quirk of this repository or its environment; the note IS the fix.
- `[guard → <id>]` — the enforcement belongs in the layer. The id is the
  follow-up that will build it, or the guard that already does. **Nothing is
  deleted when it moves**: removing a lesson because its enforcement changed
  hands is how the lesson is lost.

The older `## Session …` sections further down are an undated running log.
They were triaged 2026-09-25 (spec-friction-channel-sweep Spec-AC-10,
closing `fu-triage-undated-learned-log`): every bullet under a `## Session …`
heading now carries exactly one `[local]` or `[guard → <id>]` marker, placed
right after the leading `- ` (these bullets predate the dated-entry
convention above, so the marker sits without a `[YYYY-MM-DD]` prefix). A
lint (`tests/skills/lib/learned-guard-lints.mjs` rule `session-marker`,
enforced by `tests/skills/test-aai-hygiene-pack.sh`) now refuses a Session
bullet that carries no marker — it pins that a marker EXISTS, not that it is
the right one; the triage judgement itself was applied by one reader to
twenty bullets in one pass and is disclosed as a residual risk of that scope.

**On-demand history.** Lessons whose guard is already in force, or that are marked `**RESOLVED`, live in `docs/knowledge/history/LEARNED-HISTORY.md` (when present; a project that never split this file has no such file). Read it on demand: `grep -n '^## \|^- ' docs/knowledge/history/LEARNED-HISTORY.md`. The rule: a guard entry whose id does not start `fu-`, or whose text says `guard shipped:` or `routed to canon`, and any entry marked `**RESOLVED`, is history; every `[local]` entry and every pending guard stays here. New lessons append here (`learned-append.mjs`, default target); a scope that ships an entry's guard, or marks it `**RESOLVED`, moves that entry verbatim to the history file in the same change.

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

## Workflow
<!-- Example: - [2026-03-08] Always run /aai-bootstrap after adding new npm packages (source: debugging session) -->

## Architecture
<!-- Example: - [2026-03-08] Use queue for email sending, never synchronous in request handler (source: code review) -->

## Conventions
<!-- Example: - [2026-03-08] Write repository documents in English, chat in user's language (source: project rule) -->

## Session 2026-07-15/16 (P1 delivery + follow-ups)

- [local] `tests/skills/test-aai-worktree.sh` fails deterministically in its scratch-git
  fixture on this machine ("Commit not found in feature branch") — known
  pre-existing environmental failure, reproduced on clean main repeatedly.
  Verify suspected regressions against a DISPOSABLE WORKTREE cut from the BASE
  ref (`git worktree add --detach <path> main` — the default HEAD would give
  you your own branch), never via `git stash`: stashing reverts the SHARED
  working tree and HAZ-RESTORE in `.aai/SUBAGENT_CONTRACT.md` prohibits it.
  (Source: CHANGE-0012/0010/0009 validation runs, 2026-07-15.)
- [local] `docs/ai/archive/worktrees/` is this repo's local, untracked convention for
  archiving a worktree's STATE.yaml before `git worktree remove` (established
  2026-07-15; consumed by ledger-recovery flushes). Do not delete casually.
- [local] Universal workflow lessons from this session (merge-conflict resolution,
  no-number-prediction, verify-merge, cleanup-after-MERGED, enforce flip)
  were promoted INTO the vendored layer (SPEC learned-to-layer-promotion) —
  they deliberately do NOT live here, so vendored projects inherit them.

## Session 2026-07-16/17 (RES-0001 tail + delta-spec lifecycle)

- [local] Per-scope metrics are LOST if a worktree's `STATE.yaml` is not archived to
  `docs/ai/archive/worktrees/` BEFORE `git worktree remove`. The archive
  convention already existed (see above), but it was not followed for the
  l1-close-gate / delta-stage-2 / delta-stage-3 scopes this session, so their
  ledger entries are unrecoverable — and reconstructing them post-hoc would
  fabricate reliability data (forbidden by SPEC-0032 truth-scoring). Fix the
  ORDER: `cp <wt>/docs/ai/STATE.yaml docs/ai/archive/worktrees/STATE-<slug>-<ts>.yaml`
  (or run the metrics flush) as the FIRST post-MERGED cleanup step, before
  removing the worktree. (Source: this session's wrap-up.)
- [local] Two independent gates are not redundant: on delta-stage-3 the dual-verdict
  review PASSED by tracing the code, but independent validation on a DIFFERENT
  model FAILED it by actually running multi-run fixtures — catching a tombstone
  deletion that reused a retired REQ id. For deterministic writers, a validator
  that executes adversarial multi-run scenarios beats static review. Keep both.
  (Source: SPEC-0038 validation, PR #88.)

## Session 2026-07-17/19 (workflow-hardening arc + spec-id collision cascade)

- [local] A new audit/lint GATE must be validated against the WHOLE existing corpus AND
  all test fixtures before merge — not just its own scope's tests. The SPEC-0057
  duplicate-id detector correctly flipped the real repo to NEEDS-TRIAGE (3 real
  latent collisions). The SPEC-0058 `spec-id-shape` rule shipped under-migrated:
  it flagged bare-slug `type:spec` TEST FIXTURES (indistinguishable from real
  specs by content or filename), breaking `test-aai-ceremony-levels.sh` on main.
  Run the full suite matrix, not just the declared scope. (Source: SPEC-0057/
  0058; ceremony-levels fallout, CHANGE-0040.)

## Session 2026-07-19 (skill-suite CI gate + Linux portability)

- [local] NEVER `git clean` under `docs/` in a verification/iteration loop — the intake
  DRAFTs, frozen spec, and review report of the in-flight scope are UNTRACKED but
  wanted; `git clean` deletes them.
- [local] **CORRECTION (2026-08-23).** The line above used to continue "restore only
  tracked telemetry (`git checkout -- docs/ai/EVENTS.jsonl docs/ai/METRICS.jsonl
  docs/INDEX.md`)". Do NOT do that. `EVENTS.jsonl` and `METRICS.jsonl` are
  APPEND-ONLY LEDGERS: restoring them drops the close events a finished ride just
  wrote, which reads downstream as a false-done and fails
  `test-aai-doc-numbering.sh` TEST-013. `docs/INDEX.md` is regenerated by the
  pre-commit hook and needs no restore. The advice also contradicted the
  HAZ-RESTORE and HAZ-LEDGER hazards in `.aai/SUBAGENT_CONTRACT.md`, which is
  hashed into the SAME dispatch payload — a role would have read the prohibition
  and its counter-example together. If a ledger must be reverted, re-append the
  correction; never rewrite the bytes. Registry:
  `fu-learned-events-restore-vs-hazards`.
  A `git clean -fdq docs/` between suite runs destroyed a spec+issue+review
  mid-loop (recovered by re-prompting the still-alive Planning/Review subagents).
- [local] Metrics flush (rule 14) fires BEFORE the operator's PR step and its
  partial-flush reset (SPEC-0013 H5, triggered by a stale sibling work item like
  `pr-67-post-merge-review`) nulls `last_validation`/`code_review` — so
  `SKILL_PR` preconditions then fail. Truthfully RE-RECORD the genuine PASS
  verdicts (evidence already exists) before the PR ceremony. Candidate workflow
  fix: defer rule 14 until after PR, or don't partial-reset the just-flushed
  focus ref. (Source: PR #115/#116 ceremonies this session.)
- [local] Skill suites are written/run on macOS (BSD tools) but CI runs Ubuntu (GNU) —
  latent BSD/GNU breakage passes locally, fails only in CI. Concrete traps found:
  `mktemp -t <bare-prefix>` errors "too few X's" on GNU (use a full `…​.XXXXXX`
  template, identical on both); `stat -f '%u'` SUCCEEDS on GNU as
  `--file-system` (wrong data) so `stat -f || stat -c` never falls through — try
  GNU `stat -c` FIRST. (Source: CHANGE-0043/SPEC-0062, RC2/RC4.)
- [local] A fresh CI checkout lacks per-dev gitignored runtime files (`docs/ai/STATE.yaml`
  RFC-0001, `docs/ai/tdd/*.log`) and lacks a local `main` branch (detached PR
  checkout / temp repos default to `master` or an empty ref). Suites must be
  hermetic: self-seed the precondition via the canonical initializer (or
  soft-skip when genuinely absent, degrade-and-report), and build fixture repos
  with `git init -b main`. Do NOT assume a developer's environment on CI.
  (Source: CHANGE-0043 RC1/RC3.)
- [local] When only CI reproduces a failure (platform-specific), CI IS the authoritative
  validator — the loop's Validation/Review subagents run on the local host and
  cannot attest green-on-Linux. Weave CI into the loop: implementer pushes, the
  CI run is the RED->GREEN evidence, Validation verifies `gh run` conclusion +
  headSha-matches-HEAD + local non-regression. (Source: CHANGE-0043 loop.)
- [2026-08-02] [local] Node has NO `process.getpgrp()` (nor getpgid/setpgrp) — the
  POSIX cousins make it read as obviously-real, it survives author + internal
  L3-style review, and a `try/catch` fallback hides the failure at runtime
  (orphan-sweep's self-kill guard silently guarded nothing; a PR bot caught
  it, humans did not). Rule: any NEWLY-CALLED runtime API in a diff gets a
  10-second existence probe (`node -e 'console.log(typeof <api>)'`) before
  review sign-off; known phantoms are pinned by hygiene-pack test_092.
  (Source: CHANGE-0108 bot sweep.)
- [2026-08-05] [guard → fu-learned-positive-control-for-absence] LLM-written tests share the author's blind spots (same model
  writes code AND tests): three concrete failure shapes shipped green suites
  around real defects — (1) a test whose NAME claims a universal negative
  while asserting only refusal paths, (2) fixtures idealized vs the messy
  real corpus (30 nested + 24 backticked + 3 no-H1 specs the fixtures never
  had), (3) a test defined but never wired into main(). What caught the
  defects was never more author tests: it was corpus sweeps (all 114 specs)
  and independent adversarial eyes. Rules now enforced: hygiene test_093
  (check-test-registration.mjs — orphan test functions), VALIDATION
  corpus-sweep rule (parsers must sweep all real instances), review pin on
  overpromising test names. Author tests catch regressions; foreign eyes
  catch illusions. (Source: CHANGE-0120 L2 saga, PR #229.)
- [2026-08-07] [local] Windows sandbox escalation hygiene (Codex harness, live
  operator friction): after a `CreateProcessAsUserW` error 1920 the agent
  sticky-set `require_escalated` and the UI re-prompted for EVERY subsequent
  command — including `Get-Content`, which the operator had explicitly
  allowed. Rules: (1) escalation is a PER-COMMAND necessity decided fresh
  each time, never a sticky mode; after a 1920-class failure run the NEXT
  command non-escalated (do not inherit the escalation); (2) never re-request approval for a command
  the operator has explicitly allowed — repeated prompts for pre-approved
  commands are operator-hostile friction, not caution; (3) if a command
  genuinely needs escalation, say WHY in one line when asking. (Source:
  owner-reported Codex/Windows session, 2026-08-07.)

## Session 2026-08-24 (registry triage — the-registry-has-no-outflow)

- [2026-08-24] [local] A corpus-wide claim correction is completed by READING the
  enumerated files, never by regex: three independent gates each found live
  misses of one sweep by a different route (a directory hole, a
  present-tense hole, occurrences past an already-placed correction in the
  same file). Regex finds candidates; only reading closes the claim.
  (Source: the-tripwire-is-permanent-not-transitional ride; closes
  fu-claim-sweep-needs-reading-not-regex.)
- [2026-08-24] [local] Writing prose ABOUT a control-character escape reliably
  inserts the literal control character into the file: after editing any
  document that discusses escapes (\0, \x00, NUL and kin), scan the file for
  the literal byte before committing (portable probe, BSD grep has no -P:
  node -e 'process.exit(require("fs").readFileSync(process.argv[1]).includes(0)?1:0)' <file>;
  expect exit 0). (Source: docs-model-nul-escape ride; closes
  fu-escape-literals-self-inflict.)
