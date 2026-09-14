---
id: spec-dispatch-state-sweep
type: spec
number: 180
status: done
ceremony_level: 3
links:
  requirement: docs/issues/CHANGE-0186-dispatch-state-sweep.md
  rfc: null
  pr:
    - TBD
  commits:
    - 0ecf727e
---

# Spec — the dispatch loop and STATE say the truth about the ride they are running

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0186-dispatch-state-sweep.md
- Paired maintenance half: docs/issues/ISSUE-0040-focus-and-validation-state-go-stale-silently.md
- Mandate: docs/project-sessions/2026-09-13-wave-3-subsystem-sweeps.md (wave 3, sweep 3)
- Sweep 1 (merged, the floor this builds on): docs/specs/SPEC-0178-spec-telemetry-fields-not-prose.md
- Routing predecessor: docs/specs/SPEC-0177-spec-harness-universal-routing.md
- Staleness-advisory origin: docs/specs/SPEC-0012 routing rules; the G2 advisory in `.aai/scripts/orchestration-dispatch.mjs`
- Close-ceremony origin: docs/specs/SPEC-0153-spec-close-leaves-state-stale.md
- Technology contract: docs/TECHNOLOGY.md
- Frozen bucket: docs/ai/tdd/spec-dispatch-state-sweep/bucket-open-2026-09-13.txt

## Implementation strategy
- Strategy: tdd
- Rationale: recorded at intake (`## Notes`: "Ceremony 2, TDD, mutation checks"), and correct on the evidence. Every AC here changes a DECISION the unattended loop makes on its own — which role to dispatch, whether a write is refused, whether a number is null. A green run over a decision that was never observed taking the wrong branch proves nothing about the branch. Two of the items in this bucket (`fu-validation-staleness-undetected`, `fu-orchestrator-monitor-uses-gnu-find`) exist precisely because a check that could not fail was read as a measurement.

## Isolation and review
- Worktree recommendation: required
- Worktree rationale: the scope edits `.aai/scripts/state.mjs` and `.aai/scripts/lib/state-engine.mjs`, both listed in `protected_paths_l3` in `docs/ai/docs-audit.yaml`, AND `.aai/scripts/orchestration-dispatch.mjs`, which the orchestration loop executes on every tick. A half-applied edit inline does not merely fail a test, it breaks the loop driving the ride. Two other wave-3 sweeps run concurrently in sibling worktrees, and the main checkout is shared between sessions (P1 scar, 2026-09-06).
- User decision: worktree
- Base ref: main (082ad4aa)
- Worktree branch/path: `feat/dispatch-state-sweep` at `../aai-feat-dispatch-state-sweep` (already created)
- Inline review scope: not applicable — see the review scope list below.

Review scope (exact paths, the list `set-code-review --scope` records):

`.aai/scripts/state.mjs .aai/scripts/lib/state-engine.mjs .aai/scripts/lib/iso-time.mjs .aai/scripts/append-event.mjs .aai/scripts/orchestration-dispatch.mjs .aai/scripts/heartbeat.mjs .aai/scripts/metrics-flush.mjs .aai/scripts/check-committed-scope.mjs .aai/scripts/generate-overview.mjs .aai/scripts/watch-ci.mjs .aai/scripts/check-dispatch-text.mjs .aai/SUBAGENT_PROTOCOL.md .aai/SKILL_PR.prompt.md .aai/SKILL_CODE_REVIEW.prompt.md .aai/SKILL_WORKTREE.prompt.md .aai/METRICS_FLUSH.prompt.md .aai/STATE_FALLBACK.md .aai/system/PROFILES.yaml tests/skills/test-aai-state.sh tests/skills/test-aai-orchestration-dispatch.sh tests/skills/test-aai-heartbeat.sh tests/skills/test-aai-metrics.sh tests/skills/test-aai-overview.sh tests/skills/test-aai-learned-routing.sh tests/skills/test-aai-layer-profiles.sh tests/skills/lib/prompt-diet-ledger.sh .aai/scripts/follow-ups.mjs .aai/scripts/spec-amend.mjs .aai/scripts/update-check.mjs tests/skills/test-aai-update-check.sh tests/skills/test-aai-prompt-diet.sh tests/skills/test-aai-r-guard.sh docs/specs/SPEC-0180-spec-dispatch-state-sweep.md docs/issues/CHANGE-0186-dispatch-state-sweep.md docs/issues/ISSUE-0040-focus-and-validation-state-go-stale-silently.md`

Expected companions (not part of the scope list above, but MUST be staged alongside it — review-dispatch-state-sweep-20260913T221903Z NB-10 / validation-round3 N25): `docs/ai/decisions.jsonl` carries both of this spec's post-freeze `spec_amendment` records and the `fu-amend-spec-dispatch-state-sweep` owner-signoff tracker, and is otherwise silently droppable at staging with every gate still green (`spec-amend list --strict` and `docs-audit --check --strict --no-event` both go clean on its absence, since a gate that finds nothing is indistinguishable from a gate that found compliance). `docs/ai/tests/test-runs.jsonl` carries this ride's run ledger (the `amend-run`/`append-run` records Spec-AC-05/06 depend on) and must be staged for the same reason — an unstaged run ledger leaves the delivered tree's own evidence unreproducible for the next reader.

## Registry items closed by this scope

`node .aai/scripts/follow-ups.mjs list --status open --json` was re-derived in
full at freeze on 2026-09-13 (172 open items). The frozen bucket file holds 27;
three of those are no longer open (sweep 1 closed them this morning) and four
live items in the same subsystem were filed after the bucket file was written or
arrive with ISSUE-0040's own group. The dispositioned set is therefore 31 —
18 closed, 13 not closed with a reason. Nothing is deferred.

CLOSED FULLY:

- `fu-setfocus-keeps-stale-spec-path` (P2) — closed by Spec-AC-01. `set-focus` to a new ref leaves no field of the previous scope behind, and a ref/spec_path disagreement is refused rather than warned about.
- `fu-validation-staleness-undetected` (P2) — closed by Spec-AC-02. The `validation_verdict_stale` advisory becomes rule 11s: a standing pass whose tree hash moved routes to Validation mechanically, with no LLM judgment and no `reset-block --force`.
- `fu-overview-shows-closed-ride-inflight` (P2) — closed by Spec-AC-03. STATE gains a terminal phase and a `clear-focus` mutator; the overview's in-flight section is null for a closed ride on both independent inputs.
- `fu-flush-vacates-code-review-gate` (P2) — closed by Spec-AC-04. The partial-flush reset stops writing `code_review.required: false`; `required` is planning-set policy, not verdict state. This is the exact remainder SPEC-0178 D8 named and deliberately left.
- `fu-usage-marker-omission-unfixable` (P2) — closed by Spec-AC-05 and Spec-AC-06. Omission is flagged at append time and becomes correctable through a sanctioned `amend-run`, so the recovery no longer requires disarming the usage gate.
- `fu-ts-precision-unify-source` (P2) — closed by Spec-AC-07. One clock module, imported by both producers; the mixed-precision comparison trap is removed at the source instead of at each call site.
- `fu-orchestrator-monitor-uses-gnu-find` (P2) — closed by Spec-AC-08. A portable, exit-coded liveness command exists and is named as THE check; a failed probe can no longer render as the number zero.
- `fu-orchestrator-does-not-watch-ci` (P2) — closed by Spec-AC-09. The PR ceremony's post-push step polls the checks to settlement through a script, rather than idling until the owner asks.
- `fu-uncarved-dispatch-lanes` (P2) — closed by Spec-AC-10. The three dispatchable prompts that direct a subagent at a STATE mutator carry the D1 carve in reconciled wording, and STATE_FALLBACK's hand-edit path is reconciled with it.
- `fu-dispatch-prompt-coaching-bias` (P2) — closed by Spec-AC-11. The contract forbids a ranked answer key in a dispatch, and a guard reads the dispatch text rather than trusting the author.
- `fu-role-guard-blocks-own-fixtures` (P2) — closed by Spec-AC-12. The single-writer guard refuses the shipping STATE and permits a role's own fixture.
- `fu-heartbeat-slot-name-not-injective` (P3) — closed by Spec-AC-13. A sanitization collision is detected and named instead of one ride's progress silently overwriting another's.
- `fu-heartbeat-gc-only-runs-on-write` (P3) — closed by Spec-AC-14. The GC also runs on the read path, so a quiet repository reaps.
- `fu-heartbeat-pid-field-is-decorative` (P3) — closed by Spec-AC-15. The field is renamed to what it actually holds and documented as not a liveness handle.
- `fu-routing-effort-suffix-unnoted` (P3) — closed by Spec-AC-16. A suffixed effort header produces the same NOTE the other suffixed headers already produce, instead of exit 0 with zero stderr bytes.
- `fu-blob-check-ledger-append-noise` (P3) — closed by Spec-AC-17. An append to an append-only ledger is named distinctly from a divergence, so the gate stops being one people learn to wave through.
- `fu-metrics-verdict-has-no-staleness` (P2) — closed by Spec-AC-19. The ledger line records whether the recorded verdict covers the final bytes, derived mechanically rather than disclosed in prose.
- `fu-metrics-flush-advises-git-restore` (P3) — closed by Spec-AC-20. The runtime warning stops telling an agent to run a restoring git command on an append-only ledger in the same sentence that cites the append-only rule.

## Registry items rejected by this scope

NOT CLOSED, with the reason:

- `fu-verify-staged-set-after-commit` (P2) — wrong subsystem: sweep 4 (the close and PR ceremony). It is about verifying `git show --stat` after a commit.
- `fu-ac-flip-must-precede-close` (P3) — wrong subsystem: sweep 4. Ordering inside the close ceremony.
- `fu-main-push-conflicts-open-pr` (P2) — wrong subsystem: sweep 4. A push-to-main and open-PR interaction in the release and PR lane.
- `fu-close-gate-status-trigger-blind` (P2) — wrong subsystem: sweep 4. The close-ceremony gate's trigger predicate.
- `fu-routing-file-overwritten-on-update` (P2) — wrong subsystem: sweep 5 (sync and update). `MODEL_ROUTING.yaml` sitting in PROFILES core and being copy_replaced by `/aai-update`.
- `fu-flush-window-closes-on-verdict-reset` (P2) — duplicate: already CLOSED by sweep 1 (SPEC-0178 Spec-AC-06 and Spec-AC-07). It is absent from the live open set re-derived at freeze; the bucket file predates that close.
- `fu-reliability-marker-is-freetext` (P2) — duplicate: already CLOSED by sweep 1 (SPEC-0178 Spec-AC-03 and Spec-AC-04). Absent from the live open set.
- `fu-flush-nulls-review-scope-before-pr` (P2) — duplicate: already CLOSED by sweep 1 (SPEC-0178 Spec-AC-09). Absent from the live open set.
- `fu-amend-metrics-flush-invalidate-59abba` (P2) — owner menu. Sign-off owed on two unsigned post-freeze amendments to SPEC-0163. No code can discharge it.
- `fu-amend-spec-role-progress-heartbeat` (P2) — owner menu. Sign-off owed on three unsigned post-freeze amendments to SPEC-0164. No code can discharge it.
- `fu-role-guard-noops-close-work-item` (P2) — wrong subsystem: sweep 2 owns `.aai/scripts/close-work-item.mjs`. The state.mjs half of the class ships here as Spec-AC-12, which is what makes `test_047` of `tests/skills/test-aai-orchestration-dispatch.sh` green under the marker; the remaining half is close-work-item's own write to the SHIPPING STATE, which stays refused by design and needs sweep 2's decision about how that script behaves under the marker.
- `fu-tdd-skips-full-sweep` (P2) — wrong subsystem: sweep 2 (the test framework and `aai-run-tests.sh` suite selection). It is additionally governed by the owner's standing sweep-cost decision of 2026-09-13 (selected plus CORE between rounds, one full sweep before close), so a code change here would re-litigate a recorded human choice.
- `fu-validation-ignores-suite-selector` (P2) — wrong subsystem: sweep 2. It asks that a Validation dispatch run what `select-suites` returns; the selector is sweep 2's surface.

`docs/issues/DEBT-0003-console-log-then-exit-across-41-clis.md` is an OPEN
INTAKE of its own and owns four further registry items in this neighbourhood
(`fu-cli-exit-truncates-pipe-sweep`, `fu-orchestrator-probe-touched-git`,
`fu-orchestrator-git-add-scope-bleed`, `fu-filed-list-trusted-again`). The
wave-3 mandate row lists DEBT-0003 under sweep 3; this spec does NOT absorb it,
because it is a filed intake with its own scope and its own explicit refusal to
inherit a count. That is a scope call the owner may reverse — see
`## Residual risks and owner questions`.

## What is established before this scope starts

Every number below was measured on 2026-09-13 against this worktree
(`feat/dispatch-state-sweep`, based on main 082ad4aa) under `bash` with
`/usr/bin/grep` — `grep` is aliased to ugrep in the authoring shell and zsh
rewrites glob-looking arguments, so neither is trusted here.

1. **Protected surface, hence ceremony 3.** `docs/ai/docs-audit.yaml`
   `protected_paths_l3` lists eight paths; two of them —
   `.aai/scripts/state.mjs` and `.aai/scripts/lib/state-engine.mjs` — are edited
   by this scope. `.aai/scripts/orchestration-dispatch.mjs` is NOT on that list;
   it is in scope for its own reasons.
2. **The role guard is measurably red today.** With `AAI_ROLE=subagent`
   exported, `bash tests/skills/test-aai-check-state.sh` exits 1 with exactly
   one `FAIL:` line ("set-focus on the created STATE must succeed"). With
   `env -u AAI_ROLE` the same suite exits 0 with zero `FAIL:` lines. The three
   CORE suites' fixtures are created by
   `mktemp -d "${TMPDIR:-/tmp}/..."` — outside the repository — in
   `test-aai-check-state.sh:48`, `test-aai-docs-audit.sh:122` and
   `test-aai-hygiene-pack.sh:162,429,691,977,1105`. That location is what makes
   a repo-rooted exemption predicate decidable.
3. **The friction the guard already costs.**
   `tests/skills/test-aai-hygiene-pack.sh` carries 43 occurrences of
   `env -u AAI_ROLE` and `tests/skills/test-aai-git-ref-guard.sh` carries 1.
   Those 44 scrubs are the workaround this scope removes the NEED for.
4. **The guard's shape today.** `.aai/scripts/state.mjs:1139` refuses when
   `STATE_MUTATORS.has(cmd) && process.env.AAI_ROLE === 'subagent'` — with no
   reference at all to WHICH file `--state` names. `STATE_MUTATORS` is the nine
   `MUTATORS` keys plus `reset-block`. `log-tick` and `append-event.mjs` are
   deliberately outside it.
5. **`current_focus` has exactly four fields.** `type`, `ref_id`,
   `primary_path`, `spec_path` (live STATE, and `CLEAR_FIELDS['set-focus']` in
   `state.mjs` lists `spec_path` as the only clearable one). `cmdSetFocus` sets
   `type`, `ref_id` and `primary_path` unconditionally when `--type` is given,
   but touches `spec_path` ONLY when `--spec-path` is passed or `--type none` is
   used — the defect, exactly.
6. **The staleness comparison already exists and is already computed.**
   `withStaleAdvisory` in `orchestration-dispatch.mjs:378-390` is a pure
   function over two snapshot fields (`tree_hash`, `last_validation_verdict`)
   that already requires a standing focus-ref-scoped `pass` on BOTH sides. Its
   only consumer is one `console.error` WARN at line 1603. `decide()` is already
   a thin wrapper around `decideRuleTable()`, so a rule can be added without
   restructuring the table.
7. **Nothing routes on it.** `decideRuleTable` has no arm reading `advisories`.
   A stale pass falls through rule 12 to rule 13 (Code Review) or rule 14
   (Metrics Flush) exactly as a fresh one does.
8. **STATE has no terminal phase.** `PHASES` is the same six values —
   `planning, preparation, implementation, validation, code_review, remediation`
   — in three files: `state.mjs:140`, `orchestration-dispatch.mjs:71`, and
   `close-work-item.mjs:1373` (`RECONCILE_PHASES`, sweep 2's file). There is no
   `clear-focus` subcommand: `CMD_FLAGS` holds eleven subcommands and none of
   them clears focus wholesale.
9. **The overview's in-flight test is one field.**
   `generate-overview.mjs:266` builds `inFlight` as non-null whenever
   `state.focus_ref` is truthy and at least one tick parses. `focus_ref` is read
   at line 123 from `current_focus.ref_id`. `ROOT` is `process.cwd()`, so the
   generator is drivable against a fixture tree.
10. **The flush still vacates the gate.** `metrics-flush.mjs:835` inside
   `applyPartialReset` writes `code_review.required: false`. The file's OWN
   comment at lines 1417-1426 already names the hazard: "since this same reset
   also zeroes `code_review.required`, BOTH SKILL_PR preconditions would then
   read satisfied for a ride that satisfied neither." `applyFullReset:904`
   writes the same line and is correct there.
11. **Two clocks.** `lib/state-engine.mjs:39-41` `nowIso()` returns
   `new Date().toISOString().replace(/\.\d+Z$/, 'Z')` (second precision);
   `append-event.mjs:64` writes `new Date().toISOString()` (milliseconds). Five
   further files truncate to seconds with their own private copy of the idiom
   (`check-state.mjs:338`, `golden-flow.mjs:490`, `hitl-channel.mjs:183`,
   `metrics-flush.mjs:1192`, and `share-convert.mjs:203` in a display form).
   `validation-waiver.mjs:201` VALIDATES second precision by exact string
   equality, which fixes the unification direction: downward, to seconds.
12. **The effort headers fall through.**
   `orchestration-dispatch.mjs:1194-1195` test `/^effort_tiers:\s*$/` and
   `/^effort_roles:\s*$/` with no optional `@<suffix>` group, while
   `tiers`, `roles` and `validation_alternate` each match
   `(?:@([A-Za-z0-9_-]+))?` and push to `seenHeaders` for the suffix-rejection
   NOTE sweep. A suffixed effort header therefore reaches the
   `if (/^\S/.test(line))` reset and is discarded silently.
13. **The blob check has no append notion.**
   `.aai/scripts/check-committed-scope.mjs` compares the committed blob against
   the worktree and has no concept of an append-only ledger; `HAZ-LEDGER` in
   `.aai/SUBAGENT_CONTRACT.md` already defines the prefix rule this scope
   reuses.
14. **Suite numbering at freeze.** Highest existing TEST id per owning suite:
   `test-aai-state.sh` 031, `test-aai-orchestration-dispatch.sh` 060,
   `test-aai-heartbeat.sh` 024, `test-aai-metrics.sh` 148,
   `test-aai-overview.sh` 008, `test-aai-learned-routing.sh` 007,
   `test-aai-layer-profiles.sh` 008.
15. **The prompt corpus.** `tests/skills/test-aai-prompt-diet.sh` TEST-010
   measures `.aai/*.prompt.md` plus three extras (`INTAKE_COMMON.md`,
   `STATE_FALLBACK.md`, `ROLE_COMMON.md`). `.aai/SUBAGENT_PROTOCOL.md` is in
   NEITHER set (sweep 1 measurement 11, re-checked here). So prose added to
   SUBAGENT_PROTOCOL.md is corpus-free; prose added to `.aai/SKILL_PR.prompt.md`
   and `.aai/STATE_FALLBACK.md` is NOT.

## Decisions

### D1 — `set-focus` rewrites the whole focus block, and a ref/spec disagreement is refused

When `--type` is given (the retarget case), `cmdSetFocus` writes ALL FOUR fields
of `current_focus`, `spec_path` included: `--spec-path` when supplied, `null`
otherwise. The enumeration is closed and asserted — the test walks the four
field names from a fixture and demands that none of them survives a retarget to
a different ref.

Rejected: emitting a WARNING when `ref_id` and `spec_path` disagree. The
follow-up's own text says "nothing warns" — but a warning on a path the loop
reads unattended is a line nobody sees. The field is derived from the call, so
the disagreement cannot arise.

Kept unchanged: `--clear spec_path` (SPEC-0014 D1) and the `--type none`
normalization. A clear-only invocation still needs no `--type`.

The one BREAKING edge: a caller that today passes `--type`/`--ref`/`--path`
WITHOUT `--spec-path`, intending to keep the existing spec_path, now gets null.
Measured: the only in-repo caller of that shape is
`close-work-item.mjs:1476-1499`, which always computes `targetSpecPath` and
pushes `--spec-path` when it is defined. `.aai/PLANNING.prompt.md` step 12 calls
`set-focus` and then `set-phase --spec-path`, which writes the work item's spec
path, and this scope makes `set-phase --spec-path` also refresh
`current_focus.spec_path` for that ref, so the documented two-call sequence ends
in the same place it does today.

### D2 — The staleness advisory becomes rule 11s, placed before rule 13

`withStaleAdvisory`'s predicate is hoisted into an exported pure function
`isVerdictStale(snapshot)`; `withStaleAdvisory` keeps calling it, so the
advisory line is byte-identical. `decideRuleTable` gains ONE arm, immediately
after rule 12 and before the `vstatus === 'pass' && !vmatch` residue:

```
if (vstatus === 'pass' && isVerdictStale(s)) return dispatchFor('Validation', s, '11s', { reasons: ['validation_verdict_stale'] });
```

The rule is added to the `RULES` table so `--rules` prints it, and the WARN line
at 1603 gains the rule id so the advisory NAMES the rule that fired. Ordering
matters and is asserted: before rule 13 a stale pass would otherwise reach Code
Review, which is the measured incident (a review of bytes a later remediation
rewrote); before rule 14 it would otherwise reach the flush, which is
`fu-metrics-verdict-has-no-staleness`'s shape.

Why this is deterministic and not LLM judgment: both inputs are already computed
by `buildSnapshot` per tick — `tree_hash` from `computeTreeHash` and
`last_validation_verdict` from the ref-filtered EVENTS scan. No new data source,
no new heuristic, and the existing corroboration guards (the event says pass,
STATE says pass, both name the focus ref, both hashes non-null) are reused
unchanged, so the rule is exactly as conservative as the advisory it promotes.

Interplay with SPEC-0178 D7 (`set-validation` stamps the ref it names): the
per-ref stamp in `metrics.work_items[R].validation` is what a later flush reads;
this rule reads the EVENTS stamp. They are different records of the same event
and the rule does not touch the per-ref one. When the dispatched Validation
records its new verdict, `set-validation --ref R` refreshes BOTH — the per-ref
field directly, and the EVENTS stamp on the next `--confirm` tick through the
existing `validationRunAtMs > lastStampMs` freshness test — which is what clears
the rule.

Interplay with standing decision (b) of 2026-09-12 (a remediation that changes
behaviour gets a `--force` re-validation without asking): the rule makes the
common case of that decision mechanical. It does NOT remove `reset-block
--force`; a verdict an operator wants discarded for reasons the tree hash cannot
see still needs it. What changes is that the loop no longer needs an
owner-approved reset to notice a stale pass it can prove is stale.

Stated bound (R1 below): the rule re-fires every tick until a NEWER verdict is
recorded and a `--confirm` tick re-stamps. That is the same polarity as rule 10
(a `fail` re-dispatches Remediation until the verdict moves) and is fail-closed.
Without `--confirm` the stamp never refreshes, so the reason list carries
`restamp_requires_confirm` when `opts.confirm` is false, naming why the loop is
not converging instead of looping silently.

### D3 — A terminal phase plus `clear-focus`, and the close ceremony CALLS it

Two additions, both in `state.mjs` (this scope's file), neither in
`close-work-item.mjs` (sweep 2's file):

1. `PHASES` gains a seventh value, `closed`, in `state.mjs` and in
   `orchestration-dispatch.mjs`. **Amended (validation-round1 N3):** no rule
   arm in `decideRuleTable` NAMES phase `closed` — but no rule arm CONSULTS
   it either, so this is not by itself what keeps a closed item from being
   re-offered. Terminality is actually enforced by `close_event_present` (an
   EVENTS scan the closed-focus guard already runs): the delivered path
   (`clear-focus`, item 2 below) ALSO nulls `current_focus`, so the practical
   exposure is narrow, but phase `closed` with focus still set and no
   matching `work_item_closed` event is reachable (e.g. a hand-run
   `set-phase --phase closed` without `clear-focus`) and rule 5 dispatches
   Planning to it exactly as it would any other phase — reproduced. The
   phase value is real signal for a human or a script reading STATE
   (`generate-overview.mjs`, item 3 below), not an independent dispatch
   guard.
   `close-work-item.mjs`'s `RECONCILE_PHASES` deliberately does NOT gain it —
   an item already closed needs no reconcile — so that file needs no edit for
   this half.
2. A new subcommand `state.mjs clear-focus --ref <REF>` which, in ONE atomic
   write: sets `current_focus.type: none` and nulls `ref_id`, `primary_path`
   and `spec_path`; and sets that ref's work item to `phase: closed`,
   `status: done`. It REFUSES (exit 2, nothing written) when `--ref` does not
   equal the current `current_focus.ref_id`, so it can never clear a focus the
   caller is not in — the shared-worktree hazard (P1, 2026-09-06). It is a
   member of `STATE_MUTATORS`, so the single-writer guard covers it.

`generate-overview.mjs` gains the second, independent input: `inFlight` is null
when `focus_ref` is null (already true) OR when the focus work item's phase is
`closed`. Two inputs rather than one, because the symptom the owner reads is
worth a belt and braces.

**The seam sweep 2 must wire after both merge.** `close-work-item.mjs` already
owns a state-reconcile PLANNER that builds `[bin, args]` command pairs and
executes them in order (`reconcileStatePlan` / `applyStateReconcile`, around
lines 1415-1535). The wiring is one entry appended LAST to `commands`:

```
commands.push(['node', [STATE_CLI, 'clear-focus', '--ref', focusRefId]]);
echo.push(`node .aai/scripts/state.mjs clear-focus --ref ${focusRefId}`);
```

Nothing else in that file changes: the existing `applyStateReconcile` runs it,
the existing WARN/PARTIAL emitters echo it verbatim on failure, and the existing
`env` posture (never touched, D4 of that spec) keeps the marker reaching the
child. Until sweep 2 lands that line, the fix is NOT inert: `.aai/SKILL_PR.prompt.md`
step 4c gains one line instructing the PR ceremony to run `clear-focus` after
`close-work-item.mjs` returns. That line is corpus bytes and is credited in the
prompt-diet ledger (Spec-AC-21).

Rejected: teaching `close-work-item.mjs` to null the focus itself. It would
duplicate the invariant in a second writer, and the file belongs to a concurrent
sweep.

### D4 — The partial flush stops writing `required: false`

`applyPartialReset` stops setting `code_review.required`. `status`,
`report_paths` and `notes` reset exactly as today; `scope`, `base_ref`,
`head_ref` and `scope_ref_id` keep SPEC-0178 D8's behaviour untouched.
`applyFullReset` is UNCHANGED — a full reset means no scope is in flight at all
and the next Planning sets the policy, so zeroing it there is correct.

The argument is D8's own, applied to the one field D8 named and left:
`required` is an INPUT recorded by Planning (`set-code-review --required`), not
a verdict. A flush records what happened; it must not decide what the PR gate
enforces.

Safety of leaving `required: true` standing after a partial flush: rule 13
requires `vstatus === 'pass'`, and the same reset writes
`last_validation.status: not_run` with `ref_id: null`, so no Code Review can be
dispatched off the stale policy. Rule 4a/4b retarget to the next intake, whose
Planning records the policy afresh. Asserted as an arm of the test, not assumed.

### D5 — A costless run is flagged at append time, never silently free

SPEC-0178 D2 refuses a Validation or Code Review `append-run` without
`--verdict`. The remainder is cost, and the answer for cost is NOT a refusal:
refusing loses the record of a run that really happened, which is a worse ledger
than an incomplete one.

`append-run` gains a derived field `usage_basis` with three values:
`field` when `--tokens-total` is given; `note` when it is absent but `--note`
carries a well-formed `usage_total_tokens=<N>` marker (parsed by the existing
`lib/usage-note.mjs`, never a private copy); `absent` when neither. On `absent`
it writes the field AND emits exactly one stderr line naming the ref, the role
and the two ways to supply the number. Exit stays 0.

This is the same field-with-a-labelled-basis shape sweep 1 established for
`reliability.basis` and `cost_basis`, so the flush's existing basis-labelling
has one more honest input rather than a new vocabulary.

Rejected: refusing the append for every role. Measured consequence on the
shipping ledger (sweep 1 measurement 2): 228 of 628 recorded runs carry no
marker. A refusal rule would have rejected 36% of this repository's own history.

### D6 — `amend-run` fills a hole once, and never rewrites a number

The "unfixable" half of the follow-up is that the only recovery was toggling
`usage_capture_gate` off and back — disarming a gate to get past it, the
carve-out shape this repository keeps removing.

New subcommand:
`state.mjs amend-run --ref <R> --role <role> --started <ISO> --tokens-total <N>`.
Contract, every arm fail-closed:

- It locates the ONE `agent_runs` entry under `metrics.work_items[R]` matching
  role and `started_utc`. Zero matches or more than one: exit 2, nothing
  written, the message naming how many matched.
- It refuses when that run's `tokens_total` is already a NUMBER: exit 2,
  nothing written. A recorded number is history; only a null is a hole.
- On success it writes `tokens_total`, flips `usage_basis` to `field`, and adds
  `amended_at_utc`, so the ledger records that the line was corrected rather
  than pretending it was right the first time.
- It is a `STATE_MUTATORS` member.

This is not a hand-edit and not an append: it is a narrow, single-cell
correction with a refusal on every ambiguity, which is what makes it sanctioned
where a hand-edit is not.

### D7 — One clock, second precision, one module

A new module `.aai/scripts/lib/iso-time.mjs` exports exactly one function,
`nowIso()`, returning `new Date().toISOString().replace(/\.\d+Z$/, 'Z')`.
`lib/state-engine.mjs` re-exports it (so its 6 importers are untouched) and
`append-event.mjs` imports it for the `ts` field.

Direction is decided by evidence, not taste: `validation-waiver.mjs:201`
validates an archive record's instant by exact string equality against a
second-truncated render. Moving STATE up to milliseconds would break that
round-trip; moving EVENTS down to seconds breaks nothing, because every EVENTS
consumer parses with `Date.parse` and ordering inside a second is already given
by append order in an append-only ledger.

Behaviour delta at the one comparison the follow-up names
(`recordValidationVerdict`'s `validationRunAtMs > lastStampMs`): today a
second-truncated STATE value against a millisecond event value compares as NOT
newer within the same second (fail-closed, and documented as such at
`orchestration-dispatch.mjs:820-838`). After unification the two instants are
EQUAL within the same second, so the comparison is still NOT newer. Same
polarity, no behaviour change — which is exactly why this is a source
unification and not a routing change.

Out of scope deliberately: the five OTHER private truncation copies named at
measurement 11 (`check-state.mjs`, `golden-flow.mjs`, `hitl-channel.mjs`,
`metrics-flush.mjs`, `share-convert.mjs`). They are correct today and
converting them is a mechanical sweep with no defect behind it; the trap the
follow-up names is the DISAGREEMENT between the two ledger writers, and that
is what this closes. Recorded as R4.

**Amended (validation-round1 B5):** measurement 11 enumerated only the
`.replace(/\.\d+Z$/, 'Z')` idiom and missed a SECOND private idiom,
`` `${new Date().toISOString().slice(0, 19)}Z` ``, carried identically by
`follow-ups.mjs:335` and `spec-amend.mjs:406` — round-1 validation caught
this (both define their own `nowIso`, invisible to a guard anchored on
`^export function nowIso`) and it made Spec-AC-07's "exactly one definition"
clause literally false. Both are now converted to import the shared
`lib/iso-time.mjs` `nowIso` (this remediation), so they are consumers, not
copies — the five files named above are the complete, accurate list of
remaining out-of-scope private copies. `update-check.mjs:746` (measurement-time citation; now line 753 after the
added import) also routes
its `--now`-less fallback through the shared `nowIso` (aliased `sharedNowIso`
to avoid shadowing its own local `nowIso` constant), so it too is a real
consumer, not merely a named one — see the Amendment section for the full
account.

### D8 — Liveness is asked of the heartbeat, not of `find`

The incident was a monitoring probe that failed closed to a NUMBER
indistinguishable from a measurement — `find -newermt` rejected by BSD find,
stderr to `/dev/null`, zero writes reported as a result. The fix is not a
portable `find` incantation; it is that the orchestrator stops inventing one.

`heartbeat.mjs read` gains `--max-age-seconds <N>`: it exits 0 when at least one
slot is fresher than N, exits 4 when every slot is older or there are none, and
exits 3 when the probe itself DEGRADED (directory unreadable, git dir not
resolvable). Three distinct exit codes mean "alive", "nothing alive" and "I
could not tell" can never again render as the same answer. The degrade already
exists in `cmdRead` as the `degraded` array; this only stops it being flattened
into a clean stdout.

`.aai/SUBAGENT_PROTOCOL.md` names that command as THE liveness check (corpus-free,
measurement 15), and a test asserts zero occurrences of `-newermt` anywhere under
`.aai/**` so the GNU-only idiom cannot return through a prompt.

### D9 — After the push, poll to settlement

A new `.aai/scripts/watch-ci.mjs`: given a PR number or the current branch, it
polls `gh pr checks` at a fixed interval to settlement and exits 0 on all-pass,
5 on any failure, 3 when the platform is not GitHub or `gh` is absent (degrade
and report, never a silent zero — the same rule D8 applies). It prints one line
per state transition, so a watching orchestrator has something to relay.

`.aai/SKILL_PR.prompt.md` step 5 gains one line: after the push, run it. Those
bytes are corpus bytes and are credited in the diet ledger (Spec-AC-21).

Rejected: a background poll started by the PR ceremony itself. The ceremony's
own contract ends at the push; a detached poller that outlives it is state
nobody owns. The orchestrator runs the command and waits, which is the same
discipline already demanded of a subagent waiting on a long run.

### D10 — The three uncarved lanes, reconciled in their own words

`fu-uncarved-dispatch-lanes` names three prompts and one fallback, each needing
DIFFERENT wording, which is why a copied clause was never the fix:

- `.aai/SKILL_CODE_REVIEW.prompt.md` grants the STATE write on "an explicit
  instruction", which is broader than D1's sole-agent carve. The wording is
  narrowed to D1's own predicate: sole agent for the ride, `AAI_ROLE` unset.
- `.aai/SKILL_WORKTREE.prompt.md` writes target the NEW worktree's own STATE, so
  the clause cannot be copied verbatim; the text says so explicitly and points
  at the D1 carve for the ORIGINATING tree's STATE.
- `.aai/METRICS_FLUSH.prompt.md`'s degraded path gets the carve plus the
  `state_update_commands:` return shape.
- `.aai/STATE_FALLBACK.md`'s hand-edit path is reconciled: it is the fallback
  for an ABSENT `state.mjs`, never a second door for a dispatched subagent.

A test asserts, for each of the four files, that the carve predicate is present
and that the phrase "an explicit instruction" no longer grants a write. These
are corpus files (`.aai/*.prompt.md` and the `STATE_FALLBACK.md` extra), so the
diet ledger true-up covers them too.

### D11 — A guard reads the dispatch text

`.aai/SUBAGENT_PROTOCOL.md` (corpus-free) gains the rule: a dispatch carries
evidence and reproductions, never a priority order, a ranked list of expected
findings, or a conclusion to weigh first. `.aai/scripts/check-dispatch-text.mjs`
reads a dispatch text from a file or stdin and exits 6 when it finds a
pre-rating shape, naming the line. The closed detector set, derived from the
recorded incident rather than invented:

- an ordered list (`1.`/`2.` or `- P1`/`- P2`) within a section whose heading
  matches `/findings|issues|problems|defects|things to look/i`;
- the literal phrases `in priority order`, `most likely`, `the top ` followed by
  a digit, `ranked`, `answer key`, `start with the`;
- a severity token (`P1`, `P2`, `P3`, `BLOCKING`) applied to something the
  dispatch predicts rather than reports, detected as a severity token on a line
  that also matches `/expect|likely|probably|should find/i`.

It is advisory by default (exit 0 with NOTES) and enforcing under
`--strict`, so it can be wired into the orchestration tick without turning a
false positive into a stopped factory. Every detector is paired with a negative
control in the test: a dispatch that names a reproduction, a measured number and
a file path must exit 0.

### D12 — The single-writer guard asks WHICH file, not just WHO

The guard's stated purpose (`state.mjs:1127-1138`) is the honest/accidental
subagent write to the SHIPPING STATE. It never consults `--state`. It now does,
with a two-armed predicate — refuse when EITHER holds:

- **Arm A (own repo):** the resolved `--state` path is inside the repository
  root of the RUNNING script, computed as
  `path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..')`.
  This covers `docs/ai/STATE.yaml` in the main checkout and in every worktree,
  because each has its own `.aai/scripts/state.mjs`.
- **Arm B (someone else's project):** the resolved path's final three segments
  are exactly `docs/ai/STATE.yaml` AND `<that root>/.aai/scripts/state.mjs`
  exists — i.e. it is some OTHER AAI project's canonical STATE, not a fixture
  that merely happens to sit in a `docs/ai` shaped directory.

Everything else — a `mktemp` fixture, a scratch copy — is permitted. Measurement
2 establishes that all three CORE suites build fixtures outside the repository,
so this is the predicate that makes them green under the marker.

Honesty, unchanged and not softened: this is still a guardrail against habit,
not a security boundary. Arm B narrows the obvious bypass (pointing a copied
script at a real project's STATE) but an agent that unsets the marker still
defeats the whole guard, exactly as documented today.

The 44 `env -u AAI_ROLE` scrubs already in the suites are NOT removed. They
become unnecessary, not harmful, and deleting 44 call sites across a file a
concurrent sweep may also touch is a conflict risk with no defect behind it.
Spec-AC-12 proves the need is gone by running a CORE suite under the marker
WITHOUT scrubbing, which is the claim that matters.

### D13 — Heartbeat: a collision is named, the GC also reaps on read, and `pid` is called what it is

- **Injectivity (`fu-heartbeat-slot-name-not-injective`).** The slot payload
  gains `ref_id_raw` — the UNSANITIZED `--ref` as given. `write` reads the
  existing slot first; when the file exists and its `ref_id_raw` differs from
  this call's, it writes the slot AND emits one stderr line naming both raw
  refs and the shared slot. The progress is never lost (the write still wins,
  because the alternative is a live role with nowhere to report), but the
  collision stops being invisible — which is the whole finding.
- **GC on read (`fu-heartbeat-gc-only-runs-on-write`).** `cmdRead` runs the same
  reap the write path runs, before it lists. The read is already O(directory)
  and already stats every entry for the stray-age test, so the reap adds no new
  I/O class. A read must never be destructive of DATA, and it is not: the reap
  only removes slots past the existing 24h window, exactly as the write path
  does.
- **`pid` (`fu-heartbeat-pid-field-is-decorative`).** The field is renamed
  `writer_pid` and the file header states that it is the pid of the short-lived
  writer, which exits immediately, and is NOT a liveness handle. The corrupt-slot
  validator at `heartbeat.mjs:228` is updated to the new key. Renaming rather
  than removing keeps the forensic value ("which process wrote this") while
  destroying the wrong inference the name invited — the ride that was specified
  around probing that pid is the cost of leaving it.

### D14 — A suffixed effort header gets the NOTE the other suffixed headers get

`effort_tiers` and `effort_roles` match
`/^effort_(tiers|roles)(?:@([A-Za-z0-9_-]+))?:\s*$/`. When a suffix is present
the header is pushed to `seenHeaders` so the existing post-loop suffix sweep
emits its NOTE, and the section is IGNORED (not bound to a harness), because
SPEC-0177 D2 says effort sections are never harness-scoped. Exit code and
`suggested_effort` resolution are unchanged; the only delta is that the NOTE
now exists where today there are zero stderr bytes.

Rejected: making effort headers harness-scopable. That reverses a decision
SPEC-0177 took on its own evidence, and effort never binds a model.

### D15 — An append to an append-only ledger is named as an append

`check-committed-scope.mjs` gains a closed list of append-only ledger paths —
`docs/ai/EVENTS.jsonl`, `docs/ai/decisions.jsonl`, `docs/ai/tests/test-runs.jsonl`
— taken from `HAZ-LEDGER` in `.aai/SUBAGENT_CONTRACT.md`, not invented here.
For a path on that list, when the committed blob is a BYTE-EXACT PREFIX of the
worktree content, the finding is reported as `append` with the added line count
and does NOT count toward the failing set. When it is not a prefix, it is
reported as `divergence` and fails exactly as today.

This keeps the gate failing on the incident it exists for (a dropped or rewritten
path) and stops it firing on the benign ledger growth that happens on most rides
— which is how a gate becomes one people wave through.

### D16 — One flag grammar, printed by every subcommand

`state.mjs` gains a `CMD_USAGE` table DERIVED from the existing `CMD_FLAGS`,
`PHASES`, `FOCUS_TYPES`, `ITEM_STATUSES`, `VALIDATION_STATUSES`,
`REVIEW_STATUSES`, `STRATEGIES`, `RECOMMENDATIONS`, `USER_DECISIONS` and
`RESETTABLE_BLOCKS` constants, so it cannot drift from what the parser accepts.
Each entry renders one usage line carrying: the positional arguments (this is
what `reset-block <name> --force` needs and today's refusals omit), every flag
with required ones marked, and for each enum flag its allowed values (this is
what makes `set-validation` having no `pending` visible before the call, not
after).

Two wirings: `state.mjs <cmd> --help` prints it and exits 0 (`help` joins
`GLOBAL_FLAGS` so it is never an unknown flag), and every `fail()` raised for
that subcommand appends the same line. Three misses in one tick on 2026-09-13 is
the measurement behind this; each miss cost an unattended tick.

### D17 — The ledger says whether the verdict covers the final bytes

`metrics-flush.mjs` writes one more field on the `reliability` block:
`verdict_after_last_implementer`, with three values. It compares, for the
flushed ref, the instant of the LAST recorded verdict (the ref's newest
`validation_verdict` event in EVENTS, or its `last_validation.run_at_utc` when
the event is absent) against the `started_utc` of the LAST `agent_runs` entry
whose role is in `IMPLEMENTER_ROLES` (Implementation, TDD Implementation,
Remediation). `true` when the verdict is later, `false` when an implementer run
started after it, `null` when either instant is missing or unparseable.

That is the exact question the follow-up asks ("a ride whose last work lands
after its last review is counted as reviewed-and-passed") answered from data the
flush already reads, with no tree hashing at flush time — which would be
meaningless, since the tree has moved on by then.

Both consumers keep working unchanged: the field is additive and a legacy line
without it reads as `null`, never as `true`.

Note the division of labour with D2: the RULE prevents a stale pass from
reaching the flush through the loop; this FIELD records the answer for the flush
routes that bypass the loop (`--sweep`, resume). One without the other leaves a
door open.

### D18 — The restore advice becomes re-append advice

`metrics-flush.mjs:801-803` stops emitting "restore from git before continuing"
and emits the honest remedy for a detected ledger shrink: re-append the missing
lines, naming the count and the append-only rule that forbids the restore. This
is a string inside a file this scope already edits for D4 and D17, so it is not
the unrequested-surface class sweep 1 correctly declined to touch from a
different scope.

## Scope

In scope (files edited):

- `.aai/scripts/state.mjs` — D1 (set-focus), D3 (`clear-focus`, phase `closed`),
  D5 (`usage_basis`), D6 (`amend-run`), D12 (guard predicate), D16 (`--help`).
- `.aai/scripts/lib/state-engine.mjs` — D7 (delegate `nowIso` to the new module).
- `.aai/scripts/lib/iso-time.mjs` — NEW, D7.
- `.aai/scripts/append-event.mjs` — D7.
- `.aai/scripts/orchestration-dispatch.mjs` — D2 (rule 11s), D3 (`PHASES`),
  D14 (effort suffix).
- `.aai/scripts/heartbeat.mjs` — D8 (`--max-age-seconds`), D13.
- `.aai/scripts/metrics-flush.mjs` — D4, D17, D18.
- `.aai/scripts/check-committed-scope.mjs` — D15.
- `.aai/scripts/generate-overview.mjs` — D3 (second in-flight input).
- `.aai/scripts/watch-ci.mjs` — NEW, D9.
- `.aai/scripts/check-dispatch-text.mjs` — NEW, D11.
- `.aai/SUBAGENT_PROTOCOL.md` — D8, D11 (corpus-free, measurement 15).
- `.aai/SKILL_PR.prompt.md` — D3 (clear-focus call), D9 (watch-ci call).
- `.aai/SKILL_CODE_REVIEW.prompt.md`, `.aai/SKILL_WORKTREE.prompt.md`,
  `.aai/METRICS_FLUSH.prompt.md`, `.aai/STATE_FALLBACK.md` — D10.
- `.aai/system/PROFILES.yaml` — the three new `.aai/**` files.
- `tests/skills/lib/prompt-diet-ledger.sh` — the corpus true-up.
- `.aai/scripts/follow-ups.mjs` — B5 nowIso consumer: its private `nowIso` is
  removed and it now imports the shared one from `lib/iso-time.mjs`.
- `.aai/scripts/spec-amend.mjs` — B5 nowIso consumer: same fix, same reason.
- `.aai/scripts/update-check.mjs` — B5 nowIso consumer: imports the shared
  definition as `sharedNowIso`.
- `tests/skills/test-aai-update-check.sh` — the update-check fixture
  dependency: its two isolated-directory fixtures now `cp` `lib/iso-time.mjs`
  alongside `update-check.mjs` so the B5 import resolves inside the fixture.
- `tests/skills/test-aai-prompt-diet.sh` — the ledger true-up: TEST-012's
  corpus-growth pin moves 27957 -> 28140 to match the B2 SKILL_PR.prompt.md
  credit recorded in `prompt-diet-ledger.sh`.
- `tests/skills/test-aai-r-guard.sh` — the R-GUARD pin re-pointed: D12's
  narrower guard predicate moves TEST-RG-PIN-03's fixture off a path the
  narrowed guard no longer refuses.
- The seven owning suites named in the Test Plan.

Out of scope, named so nothing is silently dropped:

- `.aai/scripts/close-work-item.mjs`, `tests/skills/test-framework.sh`,
  `.aai/scripts/aai-run-tests.sh`, `branch-guard.mjs`, `session-lock.mjs` —
  sweep 2's surface. D3 states the one line sweep 2 must add.
- The five private second-truncation copies (D7, recorded as R4).
- `docs/issues/DEBT-0003-console-log-then-exit-across-41-clis.md` — an open
  intake of its own.
- The routing maps themselves — SPEC-0177 delivered them.
- Removing the 44 `env -u AAI_ROLE` scrubs (D12).

## Constitution deviations

None.

## Acceptance Criteria Mapping

- Maps to CHANGE-0186-dispatch-state-sweep "Desired Behavior (To-Be)" and to
  ISSUE-0040's three named items; Spec-AC-01 and Spec-AC-02 are ISSUE-0040's
  first two, and Spec-AC-03 is the PR #377 Codex finding the intake names as the
  visible symptom. Spec-AC-18 and Spec-AC-21 carry no registry id: the first
  comes from the three flag-grammar misses measured in one tick on 2026-09-13,
  the second is the Planning companion-obligation check.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN set-focus is called with --type and a NEW --ref against a STATE whose current_focus carries a previous scope's spec_path, all four fields of current_focus SHALL name the new scope and spec_path SHALL be null unless --spec-path was passed; and WHEN set-phase --ref R --spec-path P runs, current_focus.spec_path SHALL equal P for the focused ref. | done | docs/ai/tdd/spec-dispatch-state-sweep/green-TEST-032.txt; validation-round5.txt | — | TEST-032 |
| Spec-AC-02 | WHEN a snapshot carries a standing focus-ref pass verdict whose stamped tree hash differs from the current tree hash, the CLI SHALL emit verdict dispatch with role Validation and rule 11s and reasons containing validation_verdict_stale, SHALL do so before rule 13 and rule 14 can match, SHALL name rule 11s in the WARN line, SHALL list 11s in --rules output, and SHALL add reason restamp_requires_confirm when --confirm is absent. | done | docs/ai/tdd/spec-dispatch-state-sweep/green-TEST-061.txt; validation-round5.txt | — | TEST-061 |
| Spec-AC-03 | WHEN clear-focus --ref R runs on a STATE whose current_focus names R, current_focus.type SHALL be none with ref_id, primary_path and spec_path null and R's work item SHALL be phase closed status done; WHEN --ref names a different ref the call SHALL exit 2 with STATE byte-identical; and generate-overview.mjs run over the resulting tree SHALL render Nothing in flight and write in_flight null. | done | docs/ai/tdd/spec-dispatch-state-sweep/green-TEST-033.txt; green-TEST-009.txt; validation-round5.txt | — | TEST-033, TEST-009 |
| Spec-AC-04 | WHEN a partial-flush reset runs, code_review.required SHALL hold its pre-flush value while status, report_paths and notes reset exactly as today and scope, base_ref, head_ref and scope_ref_id keep SPEC-0178 D8 behaviour; a full reset SHALL still write required false; and the orchestration CLI over the post-partial-reset STATE SHALL NOT dispatch Code Review. | done | docs/ai/tdd/spec-dispatch-state-sweep/green-TEST-149.txt; validation-round5.txt | — | TEST-149 |
| Spec-AC-05 | WHEN append-run is called with --tokens-total the run SHALL carry usage_basis field; WHEN it is absent but the note carries a well-formed usage_total_tokens marker the run SHALL carry usage_basis note; WHEN neither is present the run SHALL carry usage_basis absent, exactly one stderr line SHALL name the ref and role, and the exit code SHALL be 0. | done | docs/ai/tdd/spec-dispatch-state-sweep/green-TEST-034.txt; validation-round5.txt | — | TEST-034 |
| Spec-AC-06 | WHEN amend-run names exactly one agent_runs entry whose tokens_total is null it SHALL write the number, set usage_basis to field and add amended_at_utc; WHEN zero or more than one entry matches, or the matched run already carries a numeric tokens_total, it SHALL exit 2 with STATE byte-identical and the message naming the match count or the existing value. | done | docs/ai/tdd/spec-dispatch-state-sweep/green-TEST-035.txt; validation-round5.txt | — | TEST-035 |
| Spec-AC-07 | The repository SHALL contain exactly one definition of nowIso outside lib/iso-time.mjs re-export, state-engine.mjs and append-event.mjs SHALL both resolve to it, a freshly appended EVENTS line's ts SHALL match the second-precision pattern, and recordValidationVerdict's freshness comparison over a same-second verdict and stamp SHALL still decline to re-stamp. | done | docs/ai/tdd/spec-dispatch-state-sweep/green-TEST-036.txt; validation-round5.txt | — | TEST-036 |
| Spec-AC-08 | WHEN heartbeat.mjs read --max-age-seconds N runs it SHALL exit 0 with at least one slot fresher than N, exit 4 when none is (a merely-absent slot directory, ENOENT, is a cold start and counts as "none is" — exit 4, NOT a degrade), and exit 3 only when the probe ITSELF could not run (e.g. a genuinely unreadable directory, EACCES, or a git-probe failure), with the three cases distinguishable on stderr; and a grep for -newermt over .aai SHALL return zero occurrences. | done | docs/ai/tdd/spec-dispatch-state-sweep/green-TEST-025.txt; validation-round5.txt | — | TEST-025 |
| Spec-AC-09 | WHEN watch-ci.mjs runs against a stubbed gh reporting all checks passed it SHALL exit 0, against one reporting a failure it SHALL exit 5, and with gh absent or the platform not github it SHALL exit 3 naming the degrade; and .aai/SKILL_PR.prompt.md SHALL name the command in its post-push step. | done | docs/ai/tdd/spec-dispatch-state-sweep/green-TEST-062.txt; validation-round5.txt (real PR 378 settles exit 0; arms a-h) | — | TEST-062 |
| Spec-AC-10 | Each of .aai/SKILL_CODE_REVIEW.prompt.md, .aai/SKILL_WORKTREE.prompt.md, .aai/METRICS_FLUSH.prompt.md and .aai/STATE_FALLBACK.md SHALL carry the D1 dispatched-subagent carve predicate, and the phrase granting a STATE write on an explicit instruction SHALL be absent from the corpus. | done | docs/ai/tdd/spec-dispatch-state-sweep/green-TEST-063.txt; validation-round5.txt | — | TEST-063 |
| Spec-AC-11 | WHEN check-dispatch-text.mjs --strict reads a dispatch text containing any detector in the closed set it SHALL exit 6 naming the offending line and the detector; WHEN it reads a dispatch carrying only a reproduction, a measured number and a file path it SHALL exit 0; without --strict a detected shape SHALL exit 0 with a NOTE; and .aai/SUBAGENT_PROTOCOL.md SHALL carry the no-ranked-answer-key rule. | done | docs/ai/tdd/spec-dispatch-state-sweep/green-TEST-064.txt; validation-round5.txt | — | TEST-064 |
| Spec-AC-12 | WHEN AAI_ROLE is subagent, a state.mjs mutator against a --state path outside the running script's repository root SHALL write and exit 0; against docs/ai/STATE.yaml in that root, or against another AAI project's docs/ai/STATE.yaml, it SHALL exit 3 writing nothing; and tests/skills/test-aai-check-state.sh SHALL exit 0 under the marker with no env scrub. | done | docs/ai/tdd/spec-dispatch-state-sweep/green-TEST-037.txt; validation-round5.txt (directory-symlink attack refused, three CORE suites green under the marker) | — | TEST-037 |
| Spec-AC-13 | WHEN two heartbeat writes whose raw --ref values differ sanitize to the same slot, the second SHALL still write, the slot SHALL carry ref_id_raw for the writer that wrote it, and exactly one stderr line SHALL name both raw refs and the shared slot; two writes with the same raw ref SHALL emit no such line. | done | docs/ai/tdd/spec-dispatch-state-sweep/green-TEST-026.txt; validation-round5.txt | — | TEST-026 |
| Spec-AC-14 | WHEN heartbeat.mjs read runs against a directory holding a slot older than the GC window and a fresh slot, the stale slot file SHALL be gone afterwards, the fresh one SHALL remain, and the read SHALL still list the fresh one. | done | docs/ai/tdd/spec-dispatch-state-sweep/green-TEST-027.txt; validation-round5.txt | — | TEST-027 |
| Spec-AC-15 | A slot written by heartbeat.mjs write SHALL carry writer_pid and SHALL NOT carry pid, the corrupt-slot validator SHALL accept the new shape and reject a slot missing writer_pid, and the file header SHALL state that the field is the writer's pid and not a liveness handle. | done | docs/ai/tdd/spec-dispatch-state-sweep/green-TEST-028.txt; validation-round5.txt | — | TEST-028 |
| Spec-AC-16 | WHEN MODEL_ROUTING.yaml carries an effort_tiers or effort_roles header with any suffix, the CLI SHALL emit the same suffix NOTE the tiers and roles headers emit, SHALL leave suggested_effort resolved from the unsuffixed sections only, and SHALL keep its exit code unchanged; an unsuffixed effort header SHALL produce no NOTE. | done | docs/ai/tdd/spec-dispatch-state-sweep/green-TEST-065.txt; validation-round5.txt | — | TEST-065 |
| Spec-AC-17 | WHEN check-committed-scope.mjs compares an append-only ledger whose committed blob is a byte-exact prefix of the worktree content it SHALL report the path as an append with the added line count and SHALL NOT count it as a failure; when the content is not a prefix it SHALL report a divergence and fail exactly as today; a non-ledger path SHALL behave exactly as today in both cases. | done | docs/ai/tdd/spec-dispatch-state-sweep/green-TEST-008.txt; validation-round5.txt | — | TEST-008 |
| Spec-AC-18 | For EVERY subcommand in CMD_FLAGS, state.mjs <cmd> --help SHALL exit 0 and print one usage line naming every flag of that subcommand, marking the required ones, listing the allowed values of each enum flag, and naming the positional arguments where the subcommand takes them; and every refusal raised for that subcommand SHALL carry the same line. | done | docs/ai/tdd/spec-dispatch-state-sweep/green-TEST-038.txt; validation-round5.txt | — | TEST-038 |
| Spec-AC-19 | WHEN a flush writes a ledger line for a ref whose newest recorded verdict is later than the started_utc of its last implementer run, reliability.verdict_after_last_implementer SHALL be true; when an implementer run started after that verdict it SHALL be false; when either instant is missing or unparseable it SHALL be null, never true. | done | docs/ai/tdd/spec-dispatch-state-sweep/green-TEST-150.txt; validation-round5.txt | — | TEST-150 |
| Spec-AC-20 | The metrics-flush shrink warning SHALL instruct the reader to re-append the missing lines, naming the count, and SHALL contain no git restore, git checkout or git reset instruction anywhere in the file's emitted strings. | done | docs/ai/tdd/spec-dispatch-state-sweep/green-TEST-151.txt; validation-round5.txt | — | TEST-151 |
| Spec-AC-21 | .aai/system/PROFILES.yaml SHALL classify all three new .aai files so the layer-profiles union check passes, and tests/skills/lib/prompt-diet-ledger.sh SHALL carry a JUSTIFIED_ADDITIONS entry covering the measured corpus growth with a matching TEST-012 checkpoint. | done | docs/ai/tdd/spec-dispatch-state-sweep/green-TEST-009L.txt; green-TEST-012.txt; validation-round5.txt | — | TEST-009L, TEST-012 |

## Implementation plan

Components affected, in the order the seams make safest:

1. `lib/iso-time.mjs` + `state-engine.mjs` + `append-event.mjs` (D7) — no
   behaviour change, lands first so every later test runs on one clock.
2. `state.mjs` — D12 (guard) first, because it unblocks running the CORE suites
   under the marker for everything that follows; then D16 (`--help`), D1, D5,
   D6, D3's `clear-focus` and `PHASES`.
3. `orchestration-dispatch.mjs` — D3's `PHASES`, D2's rule 11s, D14.
4. `metrics-flush.mjs` — D4, D17, D18.
5. `heartbeat.mjs` — D8, D13.
6. `check-committed-scope.mjs` — D15. `generate-overview.mjs` — D3.
7. New CLIs: `watch-ci.mjs` (D9), `check-dispatch-text.mjs` (D11).
8. Prose: `SUBAGENT_PROTOCOL.md`, `SKILL_PR.prompt.md`, the three uncarved
   prompts and `STATE_FALLBACK.md` (D10).
9. Companion obligations last, because they MEASURE what steps 1-8 added:
   `PROFILES.yaml` entries and the diet-ledger true-up with the TEST-012
   checkpoint re-sum.

Data flows: `state.mjs` writes STATE fields that `orchestration-dispatch.mjs`
reads as a snapshot and `metrics-flush.mjs` reads as runs; `append-event.mjs`
writes EVENTS lines that `orchestration-dispatch.mjs` reads back as the
staleness reference and `metrics-flush.mjs` reads as verdict provenance;
`generate-overview.mjs` renders STATE. Every one of those crossings has a seam
row below.

Edge cases carried explicitly: a legacy STATE with no `usage_basis` and no
`writer_pid`; a work item in phase `closed` meeting each dispatch rule; an
EVENTS file that does not exist; a `--state` path that is a symlink; a
MODEL_ROUTING file with both suffixed and unsuffixed effort headers; a ledger
whose committed blob is EMPTY (every worktree byte is an append).

## Test Plan

Test ids continue each OWNING suite's own sequence; the highest existing id per
suite was measured at freeze (measurement 14). `TEST-009` appears twice under
different suites and is disambiguated in the Notes column of the AC table as
`TEST-009` (overview) and `TEST-009L` (layer-profiles); the Test ID column below
carries the suite path, which is what makes each row unique.

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-032 | Spec-AC-01 | integration | tests/skills/test-aai-state.sh | Retarget leaves nothing behind — a fixture STATE carrying ref A and spec A is retargeted with set-focus --type intake_change --ref B --path P; all four current_focus fields are asserted by name and spec_path is null; a second arm passes --spec-path and asserts it; a third arm runs set-phase --ref B --spec-path Q and asserts current_focus.spec_path is Q; check-state exits 0 after each. | green |
| TEST-033 | Spec-AC-03 | integration | tests/skills/test-aai-state.sh | clear-focus — a fixture whose focus is R and whose work item is in_progress gets clear-focus --ref R; the four focus fields and the work item's phase and status are asserted; a second arm passes --ref S and asserts exit 2 with cmp of STATE identical; a third arm asserts phase closed survives check-state. | green |
| TEST-034 | Spec-AC-05 | integration | tests/skills/test-aai-state.sh | usage_basis three ways — append-run with --tokens-total writes field; with only a usage_total_tokens note marker writes note; with neither writes absent, exits 0, and emits exactly one stderr line naming ref and role; a malformed marker falls to absent, never note. | green |
| TEST-035 | Spec-AC-06 | integration | tests/skills/test-aai-state.sh | amend-run — one matching run with null tokens_total is amended and gains usage_basis field and amended_at_utc; a second call against the now-numeric run exits 2 with STATE identical; a fixture with two runs sharing role and started exits 2 naming the count; a fixture with none exits 2 naming zero. | green |
| TEST-036 | Spec-AC-07 | integration | tests/skills/test-aai-state.sh | One clock — a real append-event.mjs run's ts matches the second-precision pattern, a real state.mjs write's updated_at_utc matches the same pattern, a grep over .aai/scripts finds exactly one nowIso definition outside the re-export, a same-second verdict-and-stamp fixture driven through the dispatch CLI with --confirm appends no second validation_verdict line; and arm (e) takes three real, independent nowIso() calls 20ms apart, boundary-aligned to a wall-clock second with a 90ms margin, and asserts at least one adjacent pair second-truncates to the same string — the direction pin against a millisecond-precision nowIso. | green |
| TEST-037 | Spec-AC-12 | integration | tests/skills/test-aai-state.sh | Guard predicate — under AAI_ROLE=subagent, set-focus against a mktemp fixture exits 0 and the fixture changes; against the repo's own docs/ai/STATE.yaml exits 3 with the file byte-identical; against a synthesized second project whose root carries .aai/scripts/state.mjs exits 3; and tests/skills/test-aai-check-state.sh is invoked under the marker with no env scrub and must exit 0. | green |
| TEST-038 | Spec-AC-18 | integration | tests/skills/test-aai-state.sh | Flag grammar — a loop over every CMD_FLAGS subcommand asserts <cmd> --help exits 0 and its output names every flag of that subcommand; the enum arms assert set-validation lists exactly pass, fail and not_run (and therefore not pending), set-phase lists the seven phases, and reset-block names its positional block argument; and one deliberate bad call per subcommand carries the same usage line on stderr. | green |
| TEST-061 | Spec-AC-02 | integration | tests/skills/test-aai-orchestration-dispatch.sh | Rule 11s — a fixture tree with a committed validation_verdict pass event for the focus ref, a standing STATE pass naming the same ref, and a dirty tracked file so the tree hash differs, dispatches Validation with rule 11s and the reason; ordering arms add a required-and-unrun code_review (must still be 11s, never 13) and an absent ledger entry (must still be 11s, never 14); a fresh-hash control dispatches as today; --rules lists 11s; the WARN line names the rule; a run without --confirm adds restamp_requires_confirm. | green |
| TEST-062 | Spec-AC-09 | integration | tests/skills/test-aai-orchestration-dispatch.sh | watch-ci — arm (a) a stub gh on PATH reporting all checks passed yields exit 0 and a settlement line; (b) one reporting a failed check yields exit 5 naming the check; (c) an empty PATH (no gh) yields exit 3 naming the degrade; (d) a non-GitHub origin yields exit 3 naming the platform mismatch; (e) a pass+terminal-skipping pair settles exit 0 within one poll; (f) a cancel bucket (no fail bucket) yields exit 5 naming the cancelled check; (g) an all-skipping PR yields exit 3, never a settled pass; (h) a check reporting a bucket outside gh's five yields a non-zero, named refusal, never a silent settled-pass; and a grep asserts .aai/SKILL_PR.prompt.md names both watch-ci.mjs after the push step and state.mjs clear-focus after close-work-item.mjs. | green |
| TEST-063 | Spec-AC-10 | unit | tests/skills/test-aai-orchestration-dispatch.sh | Carve reconciliation — each of the four files is asserted to carry the D1 carve predicate (sole agent, AAI_ROLE unset) and the three prompts to carry the state_update_commands return shape; a corpus-wide grep asserts zero occurrences of the explicit-instruction grant. | green |
| TEST-064 | Spec-AC-11 | integration | tests/skills/test-aai-orchestration-dispatch.sh | Coaching-bias guard — one fixture per detector in the closed set exits 6 under --strict naming the line and the detector; the same fixtures exit 0 with a NOTE without --strict; three negative controls (a reproduction command, a measured number, a bare file path list) exit 0 under --strict; stdin and --path inputs agree byte for byte; and SUBAGENT_PROTOCOL.md is asserted to carry the rule. | green |
| TEST-065 | Spec-AC-16 | integration | tests/skills/test-aai-orchestration-dispatch.sh | Effort suffix — a routing fixture with effort_tiers@claude and effort_roles@codex emits one NOTE per header naming the suffix, resolves suggested_effort from the unsuffixed sections only, and keeps the exit code of the equivalent unsuffixed fixture; an invalid suffix emits the same NOTE; an unsuffixed pair emits none. | green |
| TEST-025 | Spec-AC-08 | integration | tests/skills/test-aai-heartbeat.sh | Liveness exit codes — a directory with one slot written seconds ago yields exit 0 under --max-age-seconds 300; the same directory with the slot back-dated past the window yields exit 4; an unreadable directory yields exit 3 with the degrade on stderr; the three stderr texts are asserted distinct; and a grep for -newermt over .aai returns zero. | green |
| TEST-026 | Spec-AC-13 | integration | tests/skills/test-aai-heartbeat.sh | Slot collision — writes for feature/alpha and feature:alpha land in one slot; the second write succeeds, the slot carries ref_id_raw for the second writer, and exactly one stderr line names both raw refs and the slot; two writes with an identical raw ref emit no such line; a 64-char truncation collision takes the same path. | green |
| TEST-027 | Spec-AC-14 | integration | tests/skills/test-aai-heartbeat.sh | GC on read — a directory seeded with one slot back-dated past the window and one fresh slot is read; afterwards the stale file is gone, the fresh file exists, and the read listed the fresh slot; a read of a directory with only fresh slots removes nothing. | green |
| TEST-028 | Spec-AC-15 | integration | tests/skills/test-aai-heartbeat.sh | writer_pid — a real write produces a slot carrying writer_pid and no pid key; a hand-written slot missing writer_pid is reported CORRUPT by read; a hand-written slot carrying the legacy pid key only is reported CORRUPT and not silently accepted; the file header is asserted to carry the not-a-liveness-handle sentence. | green |
| TEST-149 | Spec-AC-04 | integration | tests/skills/test-aai-metrics.sh | Partial reset keeps the gate — a fixture with code_review required true and status pass is partially flushed; required is still true, status is not_run, report_paths and notes are reset, and scope, base_ref, head_ref and scope_ref_id match SPEC-0178 D8; the full-reset arm still writes required false; and the real orchestration CLI over the post-reset STATE does not dispatch Code Review. | green |
| TEST-150 | Spec-AC-19 | integration | tests/skills/test-aai-metrics.sh | Verdict coverage — a fixture whose last implementer run started BEFORE the newest validation_verdict event flushes verdict_after_last_implementer true; the same fixture with a Remediation run started after it flushes false; a fixture with no implementer run, and one with an unparseable instant, each flush null; a legacy ledger line without the field reads null in the consumers. | green |
| TEST-151 | Spec-AC-20 | unit | tests/skills/test-aai-metrics.sh | Shrink advice — a fixture that triggers the ledger-shrink warning emits a message naming the missing line count and the re-append remedy; a grep over metrics-flush.mjs emitted strings returns zero occurrences of git restore, git checkout and git reset. | green |
| TEST-009 | Spec-AC-03 | integration | tests/skills/test-aai-overview.sh | Closed ride is not in flight — a fixture tree whose STATE has been through a real clear-focus is rendered by the real generate-overview.mjs; the HTML carries Nothing in flight and overview-data.json carries in_flight null; a second arm leaves focus set but phase closed and asserts the same, proving the second input is load-bearing; a live-focus control still renders the in-flight section. | green |
| TEST-008 | Spec-AC-17 | integration | tests/skills/test-aai-learned-routing.sh | Append versus divergence — a git fixture where the staged EVENTS.jsonl blob is a byte-exact prefix of the worktree file reports an append with the line count and does not fail; the same fixture with a middle line rewritten reports a divergence and fails; a non-ledger file behaves identically to today in both shapes; an empty committed blob is treated as an append. | green |
| TEST-009L | Spec-AC-21 | unit | tests/skills/test-aai-layer-profiles.sh | Classification — the union check over the live .aai tree passes with the three new files classified, and each of lib/iso-time.mjs, watch-ci.mjs and check-dispatch-text.mjs is asserted present in exactly one of the two lists. | green |
| TEST-012 | Spec-AC-21 | unit | tests/skills/test-aai-prompt-diet.sh | Corpus true-up — the existing checkpoint re-sums against the JUSTIFIED_ADDITIONS entry added for this ride's SKILL_PR.prompt.md, STATE_FALLBACK.md and the three carve prompts, so the measured growth equals the credited growth. | green |

Every Spec-AC has at least one TEST row and every TEST row names exactly one
Spec-AC.

## Mutation checks

RED-first: every test above asserts behaviour that does not exist on the
pre-change tree and is observed FAILING there, recorded as `red-<id>.txt`. Each
mutation below is applied to a scratch COPY (HAZ-SCRATCH, HAZ-RESTORE — never a
shipping file) and its failing output recorded as `mutation-<Mnn>.txt`.

| Mutation | Must redden | What it proves |
|----------|-------------|----------------|
| M1 | TEST-032 | In `cmdSetFocus`, restore the conditional so `spec_path` is written only when `--spec-path` is passed. The retarget arm must go red; a test that only checks `ref_id` cannot see the defect. |
| M2 | TEST-032 | Make `set-phase --spec-path` skip the `current_focus` refresh. The third arm must go red independently of the first two. |
| M3 | TEST-061 | Delete the rule 11s arm from `decideRuleTable`. The whole test goes red — the defining control of the scope. |
| M4 | TEST-061 | Move the rule 11s arm to AFTER rule 13. The ordering arm with a required-and-unrun review must go red while the base arm stays green; this is the arm that proves placement, not existence. |
| M5 | TEST-061 | Move the rule 11s arm to AFTER rule 14. The ledger-absent ordering arm must go red on its own. |
| M6 | TEST-061 | Replace `isVerdictStale` with `() => true`. The fresh-hash control must go red, proving the test can distinguish stale from fresh rather than asserting a constant. |
| M7 | TEST-033 | Make `clear-focus` null the focus fields but leave the work item's phase alone. The phase arm must go red. |
| M8 | TEST-033 | Delete the `--ref` mismatch refusal. The cmp arm must go red even though the first arm stays green. |
| M9 | TEST-009 | Revert `generate-overview.mjs` to the single `focus_ref` input. The phase-closed arm must go red while the cleared-focus arm stays green, proving the second input is load-bearing and not decorative. |
| M10 | TEST-149 | Restore `setField(bl, 2, 'required', ... 'false')` in `applyPartialReset`. The primary arm must go red. |
| M11 | TEST-149 | Also delete the line from `applyFullReset`. The full-reset arm must go red, proving the test distinguishes the two resets rather than grepping the file. |
| M12 | TEST-034 | Hardcode `usage_basis` to the literal `field`. The note and absent arms must go red, proving the label is derived. |
| M13 | TEST-034 | Delete the stderr line on the absent branch. The one-line arm must go red while the field value stays correct. |
| M14 | TEST-035 | Remove the already-numeric refusal from `amend-run`. The second-call arm must go red; overwriting a recorded number must never be silent. |
| M15 | TEST-035 | Change the match from role-and-started to role only. The two-runs arm must go red on ambiguity. |
| M16 | TEST-036 | Give `append-event.mjs` back its own `new Date().toISOString()` (drop its `lib/iso-time.mjs` import). Amended (validation-round1 B5): the ts-pattern arm (b) AND the new named-consumer-import arm (a2) must both go red — the single-definition grep (a) is a DIFFERENT check (no OTHER file defines `nowIso`) and is not expected to move by this mutation. |
| M17 | TEST-036 | Change `nowIso` to keep milliseconds. Amended (validation-round1 B5): arm (e) — two REAL, independently-timed `nowIso()` calls ~60ms apart — must go red (DIFFERENT instead of SAME); arm (d)'s hand-copied same-second control is NOT expected to move (it compares a string to itself, so it cannot pin precision) and is documented as such in its own comment, not claimed as proof. |
| M18 | TEST-037 | Remove arm A from the guard predicate (repo-root containment). The shipping-STATE arm must go red while the fixture arm stays green. |
| M19 | TEST-037 | Remove arm B (the other-project probe). The synthesized-second-project arm must go red independently of arm A. |
| M20 | TEST-037 | Remove the predicate entirely and refuse on the marker alone. The mktemp-fixture arm and the CORE-suite arm must both go red — this is the mutation that proves the friction claim. |
| M21 | TEST-038 | Delete one subcommand's entry from `CMD_USAGE`. The loop must go red naming that subcommand; a test that checks only one hand-picked subcommand is too weak. |
| M22 | TEST-038 | Replace the derived enum rendering with a hardcoded string for `set-validation`. The enum arm must go red the moment the constant and the table disagree. |
| M23 | TEST-025 | Collapse the degrade exit code into the no-slot code. The three-distinct-codes arm must go red — a probe that cannot tell "nothing alive" from "I could not tell" is the original incident. |
| M24 | TEST-025 | Add a `-newermt` occurrence to a file under `.aai/`. The grep arm must go red, proving the guard against the idiom's return is measured. |
| M25 | TEST-026 | Delete the pre-read collision check in `write`. The two-raw-refs arm must go red while the same-ref arm stays green. |
| M26 | TEST-027 | Remove the reap call from `cmdRead`. The stale-file-gone arm must go red; the listing arm must stay green, proving the test separates reaping from presenting. |
| M27 | TEST-028 | Rename `writer_pid` back to `pid` in `write` only. The validator arm must go red, proving writer and validator are asserted against one another and not each in isolation. |
| M28 | TEST-062 | Make `watch-ci.mjs` exit 0 when `gh` is absent. The degrade arm must go red — this is D8's rule applied to a second surface. |
| M29 | TEST-062 | Make it exit 0 on a failed check. The failure arm must go red. |
| M30 | TEST-063 | Restore the explicit-instruction grant in `SKILL_CODE_REVIEW.prompt.md`. The corpus-grep arm must go red. |
| M31 | TEST-064 | Delete one detector from the closed set (each in turn). That detector's fixture must go red while the others stay green. |
| M32 | TEST-064 | Make `--strict` exit 0 on a detection. The strict arms must go red while the advisory arms stay green. |
| M33 | TEST-065 | Revert the effort header regex to the unsuffixed form. The NOTE arms must go red while `suggested_effort` stays correct — proving the test asserts the NOTE, not the resolution. |
| M34 | TEST-008 | Remove the prefix test and treat every ledger path as an append. The rewritten-middle-line arm must go red; a blanket exclusion is the wrong fix and this proves the test can tell. |
| M35 | TEST-008 | Remove the ledger list and treat every path as today. The append arm must go red. |
| M36 | TEST-150 | Hardcode `verdict_after_last_implementer` to `true`. The false and null arms must go red. |
| M37 | TEST-150 | Make the null case fall back to `true`. The unparseable-instant arm must go red — a missing measurement must never render as good news. |
| M38 | TEST-151 | Restore the `restore from git` string. The grep arm must go red. |
| M39 | TEST-009L | Remove one new file from `PROFILES.yaml`. The union check must go red naming that file. |
| M40 | TEST-012 | Bump the corpus by one byte without crediting it. The checkpoint re-sum must go red. |

## Seams

Each row is a boundary this change shares with something it does not own, with
the test that produces on one side and asserts on the other. Two unit tests that
mock the boundary would test the mock.

| Seam | Produced by | Asserted by | Test |
|------|-------------|-------------|------|
| S1 | `state.mjs clear-focus` writes STATE | `generate-overview.mjs` renders it, and the real dispatch CLI must not re-offer a `closed` phase to any rule | TEST-009 drives a REAL `clear-focus` then the REAL generator; TEST-033's third arm runs the real dispatch CLI over the result |
| S2 | `append-event.mjs` writes a `validation_verdict` line | `orchestration-dispatch.mjs` reads it back as the staleness reference on the NEXT tick | TEST-061 seeds EVENTS in the exact shape `append-event.mjs` emits, including `payload.hash`, and TEST-036 asserts the two writers now agree on precision |
| S3 | `state.mjs append-run` writes `usage_basis` | `metrics-flush.mjs parseMetricsEntries` reads any `^ {10}(\w+): value` line into `run[key]` — a string-valued field parses for free, and this one is a string by design | TEST-034 drives a real `append-run`; TEST-150 drives a real flush over runs produced by real `append-run` calls, never a hand-written fixture only |
| S4 | `metrics-flush.mjs applyPartialReset` writes `code_review.*` | the dispatch rule table reads `review.required` one step later, and `check-committed-scope.mjs --from-state` reads `scope`/`scope_ref_id` | TEST-149 runs the REAL dispatch CLI against a STATE produced by a real partial reset |
| S5 | `heartbeat.mjs write` writes a slot | `heartbeat.mjs read` interprets it, and its corrupt-slot validator is the schema gate | TEST-028 writes with the real writer and reads with the real reader, so a rename that updates only one side fails |
| S6 | `state.mjs` refuses or writes under the marker | the CORE suites' own fixtures, which are the reason the exemption exists | TEST-037 runs a REAL CORE suite (`test-aai-check-state.sh`) under the marker with no scrub, rather than asserting the predicate in isolation |
| S7 | this scope's `clear-focus` | `close-work-item.mjs`, sweep 2's file, which must CALL it (D3) | not crossable by an automated test in this scope — recorded as R2, with the exact line sweep 2 must add written down in D3 and the interim `SKILL_PR.prompt.md` instruction tested by TEST-062's grep arm |
| S8 | `lib/iso-time.mjs` | every `nowIso` consumer: `state.mjs`, `metrics-flush.mjs`, `follow-ups.mjs`, `spec-amend.mjs`, `update-check.mjs`, `orchestration-dispatch.mjs`, plus `append-event.mjs` as a new one | TEST-036 asserts a single definition and drives two DIFFERENT producers into one comparison |
| S9 | `check-dispatch-text.mjs` | the orchestration tick that would run it, and the prose rule in SUBAGENT_PROTOCOL.md | TEST-064 asserts the guard and the prose together, so a rule stated without a detector, or a detector without the rule, fails |

## Residual risks and owner questions

- **R1 — rule 11s re-fires until a newer verdict is recorded.** Fail-closed and
  the same polarity as rule 10, with `restamp_requires_confirm` naming why when
  the loop runs without `--confirm`. A tick loop that never confirms will
  re-dispatch Validation indefinitely; that is louder than today's silent stale
  pass, which is the trade taken deliberately.
- **R2 — the close ceremony's call is not wired by this ride.** `clear-focus`
  exists, is tested, and is invoked by `SKILL_PR.prompt.md`; the mechanical call
  inside `close-work-item.mjs` belongs to sweep 2. Until sweep 2 lands, a close
  run outside the PR ceremony leaves the focus set. D3 carries the exact line.
- **R3 — arm B of the guard predicate is a heuristic about someone else's
  repository.** A project that vendors `.aai` without `state.mjs` would not be
  protected by it. Arm A covers every real case in this repository; arm B is a
  narrowing of a documented bypass, not a boundary.
- **R4 — five private second-truncation copies survive** (`check-state.mjs`,
  `golden-flow.mjs`, `hitl-channel.mjs`, `metrics-flush.mjs`,
  `share-convert.mjs`). D7 unifies the two LEDGER writers, which is the
  disagreement the follow-up names. The others are internally consistent and
  converting them has no defect behind it. **Amended (validation-round1 B5,
  N9):** the count of five is now accurate — measurement 11 originally missed
  two MORE private copies (`follow-ups.mjs`, `spec-amend.mjs`, a different
  truncation spelling), which this remediation converted to real consumers of
  `lib/iso-time.mjs` rather than leaving as an inaccurate "five."
- **R5 — the coaching-bias detectors are a closed set derived from one
  incident.** They will miss shapes nobody has written yet. Advisory by default
  is the mitigation; `--strict` is opt-in.
- **OWNER QUESTION.** The wave-3 mandate row for sweep 3 lists DEBT-0003
  (`console-log-then-exit-across-41-clis`) among this sweep's material. This
  spec does NOT absorb it, on the assumption that a separately filed intake with
  its own explicit refusal to inherit a count is its own ride. **Assumption
  taken; proceeding.** If the owner wants it folded in, it is a re-plan of this
  spec, not an amendment — the affected-CLI list has to be derived by reading
  exit paths, which is a scope of comparable size to everything above.

## Verification

Commands, in the order the evidence is produced:

- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-state.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-orchestration-dispatch.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-heartbeat.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-metrics.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-overview.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-learned-routing.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-layer-profiles.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh`
- regression consumers of the edited surfaces:
  `tests/skills/test-aai-check-state.sh`, `tests/skills/test-aai-docs-audit.sh`,
  `tests/skills/test-aai-hygiene-pack.sh`, `tests/skills/test-aai-close-work-item.sh`,
  `tests/skills/test-aai-token-capture.sh`, `tests/skills/test-aai-pr-waiver.sh`
- one full sweep before close, `AAI_TEST_TIMEOUT=3000`
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0180-spec-dispatch-state-sweep.md`
- `env -u AAI_ROLE node .aai/scripts/docs-audit.mjs --check --strict --no-event`

PASS criteria: every TEST-xxx green, every Spec-AC in a terminal status, and
every mutation in `## Mutation checks` observed RED with its output recorded.

## Evidence contract

All evidence for this scope lives under
`docs/ai/tdd/spec-dispatch-state-sweep/`:

- `red-<test-id>.txt` — the failing run of each test on the pre-change tree.
- `green-<test-id>.txt` — the passing run after the edit.
- `mutation-<Mnn>.txt` — the failing run of the named test under the named
  source mutation, applied to a scratch copy.
- `measurements.txt` — the re-run of the `## What is established before this
  scope starts` probes, so every number in this spec is reproducible at review.
- `role-guard-before-after.txt` — the `test-aai-check-state.sh` runs with and
  without the marker, before and after Spec-AC-12 (the friction measurement).
- `bucket-open-2026-09-13.txt` — the frozen bucket (already present).
- `sweep-<ts>.txt` — the full-suite sweep before close.

Each artifact records: ref_id `dispatch-state-sweep`, the Spec-AC and TEST-xxx it
belongs to, the exact command, the exit code, and the commit or diff range it was
produced against.

### Evidence by strategy

Strategy `tdd`: a stored RED artifact per AC-gating test, a stored mutation
artifact per entry in `## Mutation checks`, and the full verification matrix.
That is what the contract above demands.

## Amendment (post-freeze, 2026-09-13 — remediation of validation round 1 FAIL)

Round-1 independent validation (`docs/ai/STATE.yaml` `last_validation`, run
2026-09-13T18:08:54Z; evidence at
`docs/ai/tdd/spec-dispatch-state-sweep/validation-round1.txt`) returned `fail`
on five BLOCKING findings (B1-B5) plus sixteen non-blocking. This amendment
records the remediation, following the same additive-with-disclosure
convention already established (`docs/specs/SPEC-0132-...md`,
`docs/specs/SPEC-0153-...md`, `docs/specs/SPEC-0177-...md`). `SPEC-FROZEN: true`
is preserved; nothing below moves or deletes an existing AC's text.

- **B1 (Spec-AC-12) — a directory symlink defeated the R-GUARD predicate and
  overwrote the shipping STATE.** `isGuardedStatePath` (`state.mjs`) resolved
  `--state` with `path.resolve()` only, never `fs.realpathSync`, so a path
  whose CONTAINING DIRECTORY was a symlink into the repo's own `docs/ai` read
  as an outside-root scratch path while the write landed, through the link,
  on the real file. Fixed at cause: a new `realpathDirTarget()` helper
  realpaths a path's containing directory (falling back to the resolved
  spelling only when that directory does not exist yet, so a fresh scratch
  create is unaffected) before either the Arm A repo-containment check or the
  Arm B sibling-script check runs; `ownRoot` is realpath'd the same way.
  `tests/skills/test-aai-state.sh` gains `test_077_rguard_directory_symlink`
  (TEST-039 / Spec-AC-12): (a) the validator's own repro — a directory
  symlink from a scratch tree onto this repo's real `docs/ai` — now refuses
  exit 3 with the real STATE byte-identical before/after; (b) a plain `..`
  traversal control (no symlink) still refuses, unmoved by the fix; (c) a
  symlink onto an ordinary scratch directory is still ALLOWED (the fix judges
  the target, not "every symlink"); (d) a not-yet-existing scratch leaf falls
  through the guard unrefused (ordinary "not found", not the single-writer
  refusal), proving the realpath fallback does not misfire. Mutation-verified:
  reverting `isGuardedStatePath` to its pre-fix `path.resolve()`-only form
  reddens exactly arm (a) (`FAIL: (a) a directory symlink into the repo's
  docs/ai must refuse exit 3 (got 0)`), independently reproduced twice.
  `lib/state-engine.mjs`'s `writeState` (tmp+rename inside the resolved
  directory) was audited for the same class: it is only ever reached AFTER
  the guard's now-realpath'd decision, so no separate change is needed there;
  the residual TOCTOU between check and write is accepted under the guard's
  existing "habit, not a security boundary" posture (SPEC-0113).

- **B2 (Spec-AC-03/D3) — the interim `SKILL_PR.prompt.md` wiring the frozen
  spec already claimed to ship was never actually written, and the test named
  as covering it tested something else.** `.aai/SKILL_PR.prompt.md` step 4c
  now runs `node .aai/scripts/state.mjs clear-focus --ref <slug>` immediately
  after `close-work-item.mjs` returns (exit 0 or exit 6), before the close
  commit is staged — the D3/S7/R2 claims this spec already made are now true
  in the shipped tree, not merely in prose. `tests/skills/
  test-aai-orchestration-dispatch.sh` TEST-062's grep arm gains a second
  assertion (`grep -qF 'state.mjs clear-focus' "$skillpr"`) alongside its
  existing `watch-ci.mjs` assertion, so it can no longer pass on a file that
  names the wrong command; mutation-verified by removing the new line and
  observing TEST-062 redden on exactly the new assertion, twice, independently
  reproduced. Corpus cost measured under plain bash with `/usr/bin/wc -c`:
  `SKILL_PR.prompt.md` 30288 -> 30471 B (+183), credited 1:1 in
  `tests/skills/lib/prompt-diet-ledger.sh` (new entry, this round), moving
  `tests/skills/test-aai-prompt-diet.sh` TEST-012's pin 27957 -> 28140;
  headroom unchanged at 2046/2048.

- **B3 (Spec-AC-12 / t054a) — D12's narrower R-GUARD predicate and sweep 2's
  `test_054_state_reconcile_warn_and_partial` (t054a) disagree over the same
  fixture shape, and t054a is sweep 2's own uncommitted file.** Not edited
  from this context (editing a concurrent sweep's file blind risks reverting
  its own in-flight changes). Instead:
  `docs/ai/tdd/spec-dispatch-state-sweep/merge-reconcile-t054a.md` records the
  exact conflict and the diff the merge must apply — give
  `new_fixture_repo()` a sibling `.aai/scripts/state.mjs` (any file at that
  path) so Arm B fires for t054a's `AAI_ROLE=subagent` arm, the same way it
  already does for `test-aai-state.sh`'s own `t71-other-project` fixture.
  Verified end-to-end against a scratch copy of `test-aai-close-work-item.sh`
  with that one-line fixture change applied: `test_054_state_reconcile_warn_and_partial`
  passes cleanly under the shipped D12 guard; the SAME test against the
  unmodified tracked file still reproduces the validator's exact failure. This
  is recorded as a cross-sweep reconciliation, not a defect in either sweep
  alone: sweep 2's fixture was indistinguishable from "outside every project"
  under the OLD unconditional marker refusal; D12 correctly narrows that
  refusal to ask WHICH file, and correctly reclassifies that same fixture as
  an ordinary unguarded scratch fixture.

- **B4 (Evidence contract) — 12 of 22 red artifacts carried no `RED_CLASS`
  line, a superseded run-1 artifact was filed under the wrong TEST id, 8
  heartbeat artifacts omitted `Spec-AC`/diff-range fields, and
  `measurements.txt` labeled only 3 of 15 probes.** All four fixed: `RED_CLASS:
  product_red` added to `red-TEST-008/009L/025/026/027/028/038/062/063/064/150/151.txt`
  (each independently checked against the D5 rule — the test's own `FAIL:`
  assertion line is present and reached in every one — before the class was
  assigned); `node .aai/scripts/tdd-evidence-check.mjs --red` now exits 0 on
  all 22 red artifacts under this scope. `green-TEST-149.txt` re-recorded from
  a real re-run of `test_149_partial_reset_keeps_review_gate`, replacing the
  superseded run-1 body (which carried PASS lines for TEST-150/151 but none
  for TEST-149, the AC it was filed under). The 8 heartbeat artifacts
  (`red`/`green-TEST-025/026/027/028.txt`) each gained a `Spec-AC` field
  (08/13/14/15 respectively, per the Test Plan table) and a `diff_range`
  field naming the D8/D13 change. `measurements.txt` gained labeled,
  independently re-measured entries for probes 3-13 and 15 (1, 2, 14 were
  already present), each re-verified here against `git show HEAD:<path>`
  (HEAD 2fb2f4cd, the spec-freeze commit) — all 15 underlying facts hold,
  with two harmless off-by-one line references corrected in the evidence file
  (measurement 6: `withStaleAdvisory` is at line 377 not 378, and its sole
  console.error call is at line 1604 not 1603; measurement 11:
  `append-event.mjs`'s `toISOString()` call is at line 65 not 64) — the
  numbers were never wrong, only two citations were off by one.

- **B5 (Spec-AC-07) — the "exactly one definition of nowIso" clause was false,
  and both mutation guards claiming to prove it were unfalsifiable.**
  `.aai/scripts/follow-ups.mjs:335` and `.aai/scripts/spec-amend.mjs:406` each
  carried their own private, non-exported `nowIso` function (identical
  second-precision output, `.slice(0, 19)` spelling — a DIFFERENT idiom from
  the five files D7 already named as deliberately out of scope), invisible to
  a guard anchored on `^export function nowIso`. Fixed mechanically, the
  preferred remedy the dispatch named: both files now `import { nowIso } from
  './lib/iso-time.mjs'` and their local definitions are removed entirely, so
  the AC's clause is now literally true and Seam S8's consumer list
  (`state.mjs`, `metrics-flush.mjs`, `follow-ups.mjs`, `spec-amend.mjs`,
  `update-check.mjs`, `orchestration-dispatch.mjs`, `append-event.mjs`) is
  accurate. `.aai/scripts/update-check.mjs`'s `--now`-less fallback (originally cited
  at line 746, now line 753 after the added import) now
  also routes through the shared definition (imported under the alias
  `sharedNowIso` to avoid shadowing the file's own local `nowIso` constant,
  which still carries `--now`'s full test-injected precision unchanged) —
  fixing this surfaced a real, independently-confirmed regression: the two
  fixtures in `tests/skills/test-aai-update-check.sh` that copy
  `update-check.mjs` into an isolated directory (`test_hook_detached_auto_sync`
  / TEST-014, and `test_source_agreement` / TEST-018) did not also copy the
  new `lib/iso-time.mjs` dependency, so the real script failed to import and
  the detached sync never wrote an outcome; both fixtures now also copy
  `lib/iso-time.mjs`, and the full 32-test suite is green again (reproduced
  failing before this fix, three consecutive runs, and green after).
  `tests/skills/test-aai-state.sh` TEST-036 is strengthened three ways: arm
  (a)'s grep drops the `^export` anchor (`function nowIso(` anywhere outside
  `lib/iso-time.mjs`), a new arm (a2) asserts each of `append-event.mjs`,
  `follow-ups.mjs`, `spec-amend.mjs` and `update-check.mjs` actually IMPORTS
  the shared definition (not merely "no other file defines one" — a call-site
  revert to a bespoke `toISOString()` leaves zero duplicate definitions but
  still breaks the single clock), and a new arm (e) calls the real `nowIso()`
  twice from two independent processes ~60ms apart and asserts they are
  byte-identical — the actual direction pin M17 always claimed to be but
  wasn't (arm (d)'s pre-existing same-second control hand-copies one string
  into two fields, so it cannot distinguish second- from millisecond-precision
  by construction; kept as a behavioural check, no longer claimed as a
  direction proof). Both M16 and M17 mutation-table rows are corrected to
  name the arms that actually redden (M16: the ts-pattern arm (b) AND the new
  named-consumer arm (a2), not the single-definition grep; M17: the new
  direction arm (e), not the hand-copied same-second control (d)) —
  independently reproduced for both mutations. D7's "five other private
  truncation copies" text and R4's residual-risk entry are corrected: the
  five (`check-state.mjs`, `golden-flow.mjs`, `hitl-channel.mjs`,
  `metrics-flush.mjs`, `share-convert.mjs`) are the complete, accurate
  remaining list now that `follow-ups.mjs` and `spec-amend.mjs` are real
  consumers rather than the two additional private copies measurement 11
  originally missed (N9).

- **B6 (round-3 stale-prose findings N18/N19/N20/N21/N22/N24/N26 — no
  behavioural change, spec/evidence text only).** Round 2's own remediation
  (B6/B7 in `validation-round2.txt`, not separately amended here — that fix
  was applied directly to frozen test/spec text with only a
  `decisions.jsonl` record and no prose disclosure, which is itself what
  N26 flagged) left seven descriptive claims stale against the tree they
  describe. None bears on running behaviour; all seven are corrected here,
  by disclosure, rather than by editing the frozen rows/lists in place.
  - **N18** — the mutation table's M40 row ("Bump the corpus by one byte
    without crediting it. The checkpoint re-sum must go red.") does not
    describe the mutation actually recorded. `mutation-M40.txt` shows the
    mutation that reddens TEST-012 is bumping the dispatch-state-sweep
    LEDGER ENTRY's claimed byte count by 1 (1226 -> 1227) without moving
    `want_growth`'s pin — TEST-012's independent re-sum of the ledger array
    catches that mismatch; a raw corpus-byte bump is invisible to it and
    only trips TEST-010's headroom cap once large enough to matter on its
    own.
  - **N19** — Seam S8's consumer list wrongly names `metrics-flush.mjs` and
    `orchestration-dispatch.mjs` as `lib/iso-time.mjs` consumers. Neither
    is: `metrics-flush.mjs` computes its own `nowIsoStr` at line 1251 (a
    deliberate remaining copy, D7/R4), and `orchestration-dispatch.mjs` has
    no `nowIso` of its own — it stamps timestamps by calling
    `append-event.mjs`. The four real DIRECT importers are
    `append-event.mjs`, `follow-ups.mjs`, `spec-amend.mjs` and
    `update-check.mjs` (aliased `sharedNowIso`); `state.mjs` remains a
    genuine consumer, but indirectly, through `lib/state-engine.mjs`'s own
    import of `lib/iso-time.mjs` (unchanged since D7).
  - **N20** — `orchestration-dispatch.mjs`'s rationale comment at lines
    1618-1622 still describes the millisecond/second precision asymmetry
    ("Both timestamps are ISO 8601 UTC strings, but at DIFFERENT precision
    BY DESIGN") that this ride's own D7 removed: `append-event.mjs` and
    `state.mjs` now both stamp through the one shared `lib/iso-time.mjs`
    clock at second precision, so the asymmetry the comment warns about no
    longer exists in the shipped tree (the comparison logic the comment
    justifies is unaffected and remains correct under either precision).
  - **N21** — `docs/ai/tdd/spec-dispatch-state-sweep/measurements.txt`'s
    "Measurement 14 (final)" section still pins TEST-012's `want_growth` at
    27957; the shipped, correct value is 28140
    (`tests/skills/test-aai-prompt-diet.sh:800`), credited by the B2
    remediation's own +183 B `SKILL_PR.prompt.md` clear-focus line (the
    second `JUSTIFIED_ADDITIONS` entry in
    `tests/skills/lib/prompt-diet-ledger.sh`) after that measurement
    section was written. The evidence file was never revisited; the ledger
    and the shipped test pin are the correct 28140 throughout.
  - **N22** — the eight heartbeat TDD artifacts
    (`{red,green}-TEST-0{25,26,27,28}.txt`) carry a `diff_range:` field
    holding a one-line PROSE description of the change (e.g. "heartbeat.mjs
    D13 (writer_pid replaces pid; corrupt-slot validator requires
    writer_pid)") rather than a file:line or commit range; harmless — every
    claim in the description was independently re-derived by validation
    round 3 — but the field name promises a range, so a future reader
    searching for one will not find it there.
  - **N24** — the spec's own Review-scope list (35 entries) is a strict
    SUPERSET of STATE's `code_review.scope` (32 entries) by exactly the
    three doc paths STATE never carries (this spec's own file,
    `docs/issues/CHANGE-0186-dispatch-state-sweep.md`,
    `docs/issues/ISSUE-0040-focus-and-validation-state-go-stale-silently.md`);
    harmless because `SKILL_PR.prompt.md` step 1 unions both sources when
    deriving the in-scope staging list, but the two lists are not literally
    identical, and no earlier text should be read as claiming they are.
  - **N26** — the mutation table's M17 row and this Amendment's own B5
    bullet (above) both describe TEST-036 arm (e) as calling `nowIso()`
    "from two independent processes ~60ms apart". The shipped arm is ONE
    process, and the gap is 20ms, aligned to a wall-clock second boundary
    before sampling (both the alignment and the 20ms gap are visible in
    `tests/skills/test-aai-state.sh`'s arm (e) probe). The mutation claim
    itself still holds (M17 reddens arm (e), re-verified 20/20 by
    validation round 3 and again in this remediation round); only the two
    descriptions of the arm's mechanics were stale. (This same remediation
    round also strengthened arm (e) itself — NON-BLOCKING-7 /
    review-dispatch-state-sweep-20260913T221903Z — to sample a third point
    and require only one adjacent pair to agree, closing the residual
    event-loop-stall false-red validation round 3 measured; arm (e) is now
    three calls 20ms apart, not two.)

- **B7 (validation round 4 N29/N32/N33, merge-reconcile-t054a.md Remedy 1) —
  the cross-sweep t054a reconciliation landed, two guards this ride shipped
  gained the tests that pin them, and two Test Plan rows describing
  pre-existing tests were understated.**
  - t054a: `docs/ai/tdd/spec-dispatch-state-sweep/merge-reconcile-t054a.md`'s
    Remedy 1 diff was applied verbatim to
    `tests/skills/test-aai-close-work-item.sh`'s `new_fixture_repo()` (a
    sibling `.aai/scripts/state.mjs`, content irrelevant, so Arm B fires
    under `AAI_ROLE=subagent`); `close-work-item.mjs` itself was not
    touched (no re-pin). `env -u AAI_ROLE bash
    tests/skills/test-aai-close-work-item.sh` -> rc 0, 65 PASS (was exactly
    one FAIL, t054a, per validation round 4's own `cannot_verify` entry).
  - N29 — TEST-062 gains arm (g): a stub gh reporting every check
    `skipping` must exit 3 (degrade), never 0 — the same D9 "array of
    nothing meaningful" shape as an empty checks array. Verified: the
    shipped tree passes arm (g); deleting `.aai/scripts/watch-ci.mjs`'s
    "at least one pass" gate reddens arm (g) alone (exit 0, "settled — all
    2 check(s) passed (0 pass, 2 skipped)"), file restored byte-identical
    after.
  - N33 / code review round 2 NON-BLOCKING-1 — `watch-ci.mjs`'s bucket
    model was a closed set with no `else`: a check reporting a bucket
    outside gh's documented five (a future value, or a missing `bucket`
    key) fell through into the settled-pass path, unclassified and
    unaccounted. Fixed at cause: an `unknown` filter over the same
    five-bucket vocabulary now degrades with a named refusal the instant it
    is non-empty, before the settlement check runs — fail-CLOSED, never
    rendered as settled-pass. TEST-062 gains arm (h): one `pass` beside one
    `mystery`-bucket check must exit non-zero, naming the unrecognized
    check. Verified: the shipped tree passes arm (h); reverting to the
    pre-fix fall-through (removing the `unknown` guard) reddens arm (h)
    alone (exit 0, "settled — all 2 check(s) passed (1 pass, 0 skipped)"),
    file restored byte-identical after.
  - N32 — the Test Plan rows for TEST-036 (line 789) and TEST-062 (line
    793) understated their own shipped tests: TEST-036's row now names arm
    (e)'s three-point, boundary-aligned, adjacent-pair form; TEST-062's row
    now names all eight arms (a)-(h), including this round's (g) and (h).
    `spec-lint --path` re-run against this file after the edit: 0 findings.
  - N31 (STATE.yaml prose, not this spec) is not amended here — STATE.yaml
    is the orchestrator's own file and this dispatch is barred from editing
    it. The three review-suggested follow-up ids that do not exist as filed
    (`fu-amend-run-overwrites-note-basis-number`,
    `fu-dispatch-text-detector-self-referential-fp`,
    `fu-verdict-coverage-same-second-reads-true`) and their engine-capped,
    actually-filed replacements (`fu-amend-run-overwrite-note-basis-number`,
    `fu-dispatch-text-detector-self-ref-fp`,
    `fu-verdict-coverage-same-second-true`) are reported to the orchestrator
    in this round's result for STATE's own correction.

Every claim above was grepped or run TRUE against the shipped tree before
this Amendment was written.
