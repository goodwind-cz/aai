---
id: dispatch-state-sweep
type: change
number: 186
status: done
capability: dispatch-state-sweep
links:
  pr:
    - TBD
  commits:
    - 0ecf727e
---

# The dispatch loop and STATE say the truth about the ride they are running

## Summary
- Wave 3, sweep 3 (`docs/project-sessions/2026-09-13-wave-3-subsystem-sweeps.md`).
  Paired maintenance half: `focus-and-validation-state-go-stale-silently`
  (ISSUE-0040).
- The loop every tick runs (`orchestration-dispatch.mjs`, `state.mjs`,
  `heartbeat.mjs`, `unattended-gate.mjs`, `ride-select.mjs`) has 27 open
  registry items whose common shape is a STATE that outlives the truth:
  `set-focus` keeps the previous scope's `spec_path`; a validation pass
  survives a remediation that rewrote the validated code; STATE has no
  terminal phase or clear-focus, so a closed ride keeps publishing as in
  flight (PR #377 Codex finding, worked around by a regeneration); the
  partial flush vacates the review gate; a run appended without its usage
  marker can never be corrected; timestamps differ in precision between two
  writers; the orchestrator's own liveness check used GNU `find` syntax
  with stderr discarded.
- Four scripts silently no-op a STATE write under `AAI_ROLE=subagent`
  (`fu-role-guard-blocks-own-fixtures`, `fu-role-guard-noops-close-work-item`):
  a role's own `--state <mktemp>` fixture is refused by the single-writer
  guard, and the CORE suites `aai-check-state`, `aai-docs-audit`,
  `aai-hygiene-pack` fail under the marker every ride is told to set.
- `state.mjs` subcommands take different flag shapes (`reset-block <name>
  --force` positional; `set-validation` has no `pending`; `set-phase` needs
  `--ref`); each miss costs an unattended tick.

## Motivation / Business Value
- The dispatcher is the only thing that runs unattended. Every stale field
  is a wrong decision it makes on its own; every silent no-op is a ledger
  line that never happened.
- The Codex finding on PR #377 (a closed ride shown as in flight) is the
  visible symptom the owner reads on the overview page.

## Scope
- In scope, fixed with a test each: `fu-setfocus-keeps-stale-spec-path`,
  `fu-validation-staleness-undetected` (the `validation_verdict_stale`
  advisory becomes a rule: a stale pass routes to re-validation, no LLM
  judgment), `fu-overview-shows-closed-ride-inflight` (a terminal phase and a
  `clear-focus` the close ceremony runs), `fu-flush-vacates-code-review-gate`,
  `fu-usage-marker-omission-unfixable` (with sweep 1's fields the marker is a
  field; an appended run missing them is refused, so omission is impossible
  rather than unfixable), `fu-ts-precision-unify-source`,
  `fu-orchestrator-monitor-uses-gnu-find`, `fu-orchestrator-does-not-watch-ci`
  (the PR ceremony's post-push step watches CI and reports),
  `fu-uncarved-dispatch-lanes`, `fu-dispatch-prompt-coaching-bias` (the
  dispatch template forbids pre-rating findings; a guard reads the dispatch
  text), the `fu-role-guard-*` class (the single-writer guard exempts a
  `--state` path outside `docs/ai/`, so a role's own fixture is writable and
  the CORE suites pass under the marker), the three `fu-heartbeat-*` items,
  `fu-routing-effort-suffix-unnoted`, `fu-blob-check-ledger-append-noise`,
  a `state.mjs --help` per subcommand with one flag grammar.
- Owned by other sweeps, named here so nothing is deferred: the flush items
  (`fu-flush-window-closes-on-verdict-reset`, `fu-reliability-marker-is-freetext`,
  `fu-flush-nulls-review-scope-before-pr`, `fu-metrics-verdict-has-no-staleness`)
  by sweep 1; `fu-close-gate-status-trigger-blind`, `fu-ac-flip-must-precede-close`,
  `fu-main-push-conflicts-open-pr`, `fu-verify-staged-set-after-commit` by
  sweep 4; `fu-routing-file-overwritten-on-update` by sweep 5.
- Owner sign-off items (`fu-amend-metrics-flush-invalidate-59abba`,
  `fu-amend-spec-role-progress-heartbeat`) are presented to the owner as one
  menu at the end of this ride, not fixed by code.
- Out of scope: `close-work-item.mjs` (sweep 4); the routing maps themselves
  (done in SPEC-0177).

## Affected Area
- `.aai/scripts/orchestration-dispatch.mjs`, `.aai/scripts/state.mjs`,
  `.aai/scripts/lib/state-engine.mjs`, `.aai/scripts/heartbeat.mjs`,
  `.aai/scripts/metrics-flush.mjs` (the reset only), `.aai/scripts/append-event.mjs`,
  `.aai/ORCHESTRATION.prompt.md`, `.aai/SUBAGENT_PROTOCOL.md`, `.aai/STATE_FALLBACK.md`,
  `.aai/SKILL_PR.prompt.md` (post-push CI watch), the suites for each.

## Desired Behavior (To-Be)
- `set-focus` to a new ref leaves no field of the previous scope behind.
- A pass verdict whose tree hash no longer matches routes to Validation by
  rule, and the advisory names the rule that fired.
- A closed ride has a terminal phase; the overview shows it as delivered
  the moment the close ceremony runs, with no regeneration by hand.
- A role can write its own `--state` fixture under the subagent marker; the
  guard still refuses `docs/ai/STATE.yaml`.
- Every `state.mjs` subcommand prints one usage line naming its exact flags
  on any bad call.

## Notes
- Bucket on 2026-09-13: 27 open follow-ups matching dispatch, state.mjs,
  append-run, flush, metrics, telemetry, routing, tick, orchestrat, focus,
  verdict, role-guard, heartbeat, unattended, ride-select, roadmap, lane
  and not already in the test-framework bucket; the spec freezes the list.
- Ceremony 2, TDD, mutation checks; runs in a sibling worktree because it
  edits the dispatcher the loop runs every tick.
- Corrected at spec freeze (2026-09-13): the level is **3**, not 2. The scope
  edits `.aai/scripts/state.mjs` and `.aai/scripts/lib/state-engine.mjs`, both
  listed in `protected_paths_l3` in `docs/ai/docs-audit.yaml`, and RFC-0009
  makes L3 mandatory on a protected surface. The declaration lives in
  `docs/specs/SPEC-0180-spec-dispatch-state-sweep.md` frontmatter
  (`ceremony_level: 3`), which is authoritative; this line records the
  correction rather than leaving the intake's estimate reading as the decision.
