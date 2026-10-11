---
id: spec-done-work-item-stays-in-current-focus
type: spec
number: 224
status: done
mutation_gate: v1
frozen_sha256: 36df79865313f129723dfbf9136927a91f85c82df4e5b03fbaa43dd6f48028e4
ceremony_level: 2
links:
  requirement: null
  rfc: null
  intake: docs/issues/ISSUE-0098-done-work-item-stays-in-current-focus.md
  pr:
    - 456
  commits:
    - df3a569422103ab58e2e5994d845678736a239b0
---

# Spec — A closed ride with no flushable telemetry gets a sanctioned exit, and rule 4b stops prescribing a remedy that cannot act

SPEC-FROZEN: true

## Links
- Requirement: none (bug intake, `docs/issues/ISSUE-0098-done-work-item-stays-in-current-focus.md`)
- Decision records: SPEC-0075 (`--retire`, the symmetric sanctioned exit), SPEC-0180 (`clear-focus` wiring), SPEC-0192 (the `set-strategy` refusal this scope must not weaken), SPEC-0053/SPEC-0054 (`close-work-item.mjs` owns the close lifecycle)
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred: entire spec postponed; explain reason in this section
- rejected: spec was abandoned; explain rationale
- superseded: replaced by a newer spec; set links to the replacement

## Problem, as measured

Reproduced on a scratch fixture (`/private/tmp/.../scratchpad/wedge/repo`, a
STATE whose `current_focus.ref_id` is `wedged-ref`, an `active_work_items`
entry for it with `status: done`, a committed `work_item_closed` event for it
in EVENTS.jsonl, an empty METRICS.jsonl, and a `metrics.work_items` block that
holds only an unrelated ref):

1. `orchestration-dispatch.mjs --state <fx> --root <fx>` returns
   `"rule":"4b","role":"Metrics Flush","reasons":["closed_but_unflushed_focus"]`,
   exit 0.
2. `metrics-flush.mjs --ref wedged-ref --dry-run` returns exit 0 with
   `"flush": []` and `skipped` holding ONLY the other ref
   (`not selected (--ref restriction)`). The named ref is absent from `skipped`
   entirely: it was never a candidate, not a candidate that was filtered out.
3. Adding `--sweep` changes nothing: exit 0, `"flush": []`.
4. `metrics-flush.mjs --retire wedged-ref --dry-run` refuses, exit 1:
   `"wedged-ref" is not present in metrics.work_items — nothing to retire`.
5. So `flushed` can never become true, rule 4b fires on every tick, and the
   done item keeps `current_focus` indefinitely.

A SECOND wedge shape was measured on the same fixture with the row PRESENT but
carrying `agent_runs: []`:

6. `--ref wedged-ref --sweep --dry-run` skips it, exit 0:
   `"no agent_runs recorded in STATE metrics"`.
7. `--retire wedged-ref --dry-run` refuses it, exit 1:
   `would flush (a committed work_item_closed event exists ...) — flush it, do
   not retire`.
   Two arms of the SAME script contradict each other: one says flush it, the
   other refuses to flush it.

Why the row can be missing at all: `metrics.work_items[<ref>]` is created ONLY
as a side effect of `state.mjs append-run` auto-init (`state.mjs:1282`), while
`active_work_items[<ref>].status: done` plus a committed `work_item_closed`
event are reachable with zero `append-run` calls. `state.mjs:886-890` already
records, in its own words, that minting a row for a ref with no recorded runs
"would mint a metrics entry the flush can then never flush", "which is how
strands are born" — so guaranteeing the row is explicitly the wrong fix, and
this spec does not take that route.

## Implementation strategy
- Strategy: tdd
- Rationale: `metrics-flush.mjs` is a closed-contract single-file line-surgical
  STATE mutator with a stated high blast radius (`:6`, `:19-20`), and the whole
  defect class here is "a guard and its prescribed remedy disagree about what is
  actionable". Only a recorded RED per arm proves the new refusals actually
  refuse and the new success path actually releases; an untested or direct lane
  would re-ship exactly the silent-no-op shape this scope removes. No intake
  choice was recorded in STATE (`set-strategy` was blocked by the very bug), and
  the intake's `## Notes` carries no `Implementation mode (user choice):` line —
  it states "Planning picks the strategy", so this is Planning's call, not an
  override of a human one.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: the shipping checkout is shared between live sessions
  (a second session has retargeted it mid-ride before), and the subject under
  test is the live `docs/ai/STATE.yaml` plus the committed append-only
  `docs/ai/EVENTS.jsonl` — the two files a mistake here damages irreversibly.
  An isolated worktree keeps every fixture mutation off the shared tree. Not
  `required`: all ACs are provable on scratch fixtures via the path-injection
  flags, so inline with an explicit review scope is a defensible operator
  override.
- User decision: undecided
- Base ref: main
- Worktree branch/path: to be chosen by Implementation Preparation
- Inline review scope: `.aai/scripts/metrics-flush.mjs`,
  `.aai/scripts/orchestration-dispatch.mjs`,
  `tests/skills/test-aai-metrics.sh`,
  `tests/skills/test-aai-orchestration-dispatch.sh`

## Design decision — why a sanctioned release, and not the three alternatives

| Option | Verdict |
|---|---|
| Guarantee a `metrics.work_items` row exists for anything closable | REJECTED. `state.mjs:886-890` already records that a row with no runs can never flush and "is how strands are born". It converts wedge W1 into wedge W2. |
| Let the flush mint a METRICS.jsonl entry for a row-less closed ref | REJECTED. `metrics-flush.mjs:61-63` holds completion provenance durable, "fail-closed otherwise, reported, never fabricated". A ledger line built from nothing is a false reliability record, and the factory report reads that ledger. |
| Prescribe the existing `state.mjs clear-focus --ref <slug>` from rule 4b | REJECTED as the whole fix. `clear-focus` nulls `current_focus` and stamps the item done, but writes NO durable record that the ride's telemetry was absent, so the absence becomes invisible rather than recorded; it also carries the open defect `fu-clearfocus-announces-unwritten-phase` (replaces an existing `phase:`/`status:` line, never inserts a missing one, and announces `phase=closed status=done` unconditionally). This spec therefore adds no new reliance on `clear-focus` for a focus that still has a done work item. One narrow exception (remediation round 2, finding B2): when the focus has NO `active_work_items` entry at all, `--release` cannot act (Spec-AC-04 refuses an absent item, and loosening that would contradict it), the committed `work_item_closed` event is already the durable record, and there is no item line for the `clear-focus` defect to mishandle, so rule 4b prints `state.mjs clear-focus --ref <ref>` for exactly that shape (Spec-AC-18). |
| A sanctioned `--release` exit in `metrics-flush.mjs`, plus a rule-4b precondition | SELECTED. It mirrors the `--retire` exit (SPEC-0075) that already lives in this file for the mirror-image case, reuses this file's existing surgical STATE helpers, records the absence as a durable event instead of inventing a number, and is EXPLICIT — never an auto-repair that fires on "looks closed". |

Report-and-refuse over auto-repair (intake constraint): nothing in this scope
clears a focus on its own. Rule 4b stops dispatching an unactionable role and
instead REPORTS `needs_llm` naming the remedy; the owner or a human runs it. The reason string is deliberately NOT one of the named reasons
in `.aai/ORCHESTRATION.prompt.md` step 4 ("handle ONLY the named reasons"), the
same as the existing `closed_focus_stale_state`: the LLM orchestrator reports it
and stops, and the printed command is run by the owner or a human (RR-1). No
prompt-corpus byte changes, so no diet-ledger obligation arises (remediation
round 1, finding N4). The remedy itself re-checks the same durable provenance
`--sweep` demands and refuses without it, so it cannot clear past an incomplete
close: a close ceremony that has not emitted `work_item_closed` is refused, a close
ceremony whose `active_work_items` status is not yet `done` is refused, a close
that a later re-open from `done` supersedes is refused (Spec-AC-16), and a `fail`
verdict naming the ref is refused (Spec-AC-15: a release never erases a failed
verdict, and the flush's fail-precedence is not inverted).

## Implementation plan

Components/modules affected (the complete file list — nothing else is in scope):
- `.aai/scripts/metrics-flush.mjs`
- `.aai/scripts/orchestration-dispatch.mjs`
- `tests/skills/test-aai-metrics.sh`
- `tests/skills/test-aai-orchestration-dispatch.sh`

Named code shapes this spec MANDATES (the mutation anchors below are one-token
substitutions on these, following the SPEC-0205 convention; a rename at
implementation time is allowed and requires a mechanical restamp of the
affected Mutation cells, disclosed in the TDD record):
- `metrics-flush.mjs`: `const RELEASED_EVENT = 'work_item_released';`
- `metrics-flush.mjs`: `function handleRelease(ctx) {`, structurally disjoint
  from the flush loop exactly as `handleRetire` is, branched to from `main()`
  before the loop so the no-`--release` behavior is byte-unchanged by
  construction.
- `metrics-flush.mjs`: a pre-loop guard
  `if (opts.ref !== null && !entries.some(e => e.ref === opts.ref))` that
  `fail(..., 1)`s, so an explicitly named non-candidate is never an empty
  success.
- `metrics-flush.mjs`: `const releaseLedgerEntries = [];` — the literal
  statement of "a release builds no ledger entry", so a mutation can make it
  non-empty and the no-fabrication test must catch it.
- `metrics-flush.mjs`: the appended event's payload carries
  `telemetry: 'absent'` — absence as a recorded value, never a zero.
- `metrics-flush.mjs`: the named predicate `releaseWouldFlushByDefaultGate`
  (`vStatus === 'pass' && refMatches(vRef, ref)`) is used by `handleRetire`
  ONLY. Remediation round 1 removed it from `handleRelease`: the default gate
  never flushes a ref with zero `agent_runs`, so a release refusal built on it
  was false for exactly the refs `--release` exists for and re-created the
  wedge (dispatch named `--release`, `--release` refused).
- `metrics-flush.mjs`: `function closeSupersededByReopen(eventsPath, ref)` — the
  same notion as `close_event_superseded_by_reopen` in dispatch: the last
  `work_item_closed` for the ref is followed by a `doc_lifecycle` event whose
  `payload.from` is `done`. `handleRelease` refuses such a close (Spec-AC-16).
- `metrics-flush.mjs`: `function applyReleaseReset(...)` — the partial reset used
  when other work is in flight; it rewrites a verdict block only when that block
  names the released ref (Spec-AC-14).
- `orchestration-dispatch.mjs`: `const UNFLUSHABLE_REASON = 'closed_focus_unflushable_no_flushable_metrics';`
- `orchestration-dispatch.mjs`: snapshot field
  `focus_flushable_runs: focusRef ? agentRunsFor(lines, focusRef).length : 0`
  (`agentRunsFor` is ALREADY imported in this file from
  `lib/state-engine.mjs`; it returns `[]` both for an absent row and for an
  `agent_runs: []` row, which is exactly the union of W1 and W2).
- `orchestration-dispatch.mjs`: the rule-4b arm gains the precondition
  `if (s.focus_flushable_runs < 1)` -> `needsLlm(s, [UNFLUSHABLE_REASON, remedy], '4b')`.

Data flows:
- `--release <ref>` reads STATE (`active_work_items`, `metrics.work_items`,
  `current_focus`, `last_validation`) and EVENTS.jsonl; commits STATE through the
  same `writeState` atomic tmp+rename+recheck path the flush uses; and only then
  appends ONE event to EVENTS.jsonl. STATE-before-EVENTS (remediation round 3,
  PR bot review: the event claims a release, so it must never precede the commit
  that can still be rejected). Before the commit it writes a transient in-flight
  record `<state>.release-pending` (gitignored) holding the event; after the
  event is durable it removes it. METRICS.jsonl is never written, and read (the
  ledger-presence probe) only on the resume path below.
- After removing the released ref's done `active_work_items` entry, `--release`
  of the focused ref uses a full reset when no non-done active work remains
  (the flush path's `applyFullReset`), else `applyReleaseReset`: only a
  `last_validation` whose `ref_id` names the released ref, and only a
  `code_review` whose `scope_ref_id` names it, are reset to `not_run`, with the
  note `reset after release of <ref>`; another ride's verdict blocks stay
  byte-identical (Spec-AC-14). No archive record is ever written, because
  `--release` satisfies no part of the default validation gate.
- Rule 4b reads one extra pure STATE value. No clock, no writes, no new
  filesystem reads — the dispatch's stated invariant is preserved.

Edge cases:
- `--release` on a ref that is NOT `current_focus.ref_id`: the done work item is
  removed and the event is appended, but `current_focus` stays byte-unchanged
  (Spec-AC-03). Nulling a focus the call is not in is the shared-worktree hazard
  `clear-focus` already refuses.
- `--release` on a ref whose metrics row exists and carries runs: refused, with
  the message naming the flush as the correct action (Spec-AC-05).
- `--release` on a ref with a `last_validation` pass naming it and ZERO runs:
  ALLOWED (Spec-AC-05 as amended). The default gate sets its skip reason
  `no agent_runs recorded in STATE metrics` for a zero-run ref and never sees a
  row-less ref, so nothing would flush it; refusing here made dispatch name a
  command that refused. This is the natural post-close shape of a ride that
  recorded no `append-run`. A pass naming a ref whose row carries runs is
  refused by the runs arm.
- `--release` on a ref a `fail` verdict names (`last_validation.status` fail with
  `ref_id` naming it, or `code_review.status` fail with `scope_ref_id` naming it):
  refused as an incomplete close (Spec-AC-15). A fail naming another ride does
  not block.
- `--release` on a ref whose latest `work_item_closed` is followed by a
  `doc_lifecycle` event with `payload.from` `done`: refused (Spec-AC-16); a
  close recorded after the re-open makes it releasable again. Dispatch applies
  the same notion: a superseded close is not routed to rule 4b.
- `--release` combined with `--ref` or `--sweep` (or `--retire`): usage error,
  exit 2, nothing written (Spec-AC-17).
- `--release` on the focused ref when no other non-done work remains (the
  full-reset branch) and `last_validation` or `code_review` is `fail` without
  naming the ref (another ref, a null `ref_id`, no `scope_ref_id`): refused
  before any write, dry-run included, because the full reset would otherwise
  erase a verdict the release does not own (Spec-AC-19; round 2 finding N7).
  Dispatch never routes a fail to rule 4b, so only a direct call reaches this.
- A closed focus whose ref is absent from `active_work_items` and has no
  flushable runs: rule 4b reports `needs_llm` with the distinct reason
  `closed_focus_item_absent_no_flushable_metrics` and prints
  `node .aai/scripts/state.mjs clear-focus --ref <ref>`, never `--release`,
  which refuses that shape (Spec-AC-18; round 2 finding B2).
- `--release` close provenance uses the dispatcher's own ref matching (exact or
  path component, `refMatches`): a `work_item_closed` event whose ref is
  `docs/issues/CHANGE-0001` for the focus `CHANGE-0001` is a close for both, so the
  `--release` command dispatch prints cannot refuse the very event dispatch
  accepted (Spec-AC-20; PR bot review P1). `scanCloseEvents` is the one scan
  behind the close probe and the re-open probe. `closedRefs` stays exact because
  it is the `--sweep` and `--retire` predicate and must equal close-work-item's.
- An interrupted release is resumable and never leaves a false record
  (Spec-AC-21; PR bot review P2). In-flight record plus the item still in STATE
  means the commit never happened (crash, or a concurrent-modification
  rejection): the record is dropped and the release is evaluated afresh, so a
  run added meanwhile still refuses. In-flight record plus the item gone from
  STATE, no row, no ledger line, a valid close and the focus not on the ref means
  the commit landed and only the event is missing: the retry appends exactly that
  event (skipped if an identical line is already present) and removes the
  record. No other state yields a resume, so the existing refusal for a ref
  absent from `active_work_items` is unchanged.
- `--release --dry-run`: prints the plan and still refuses every arm the real
  run refuses, so a dry run is never a preview of a bypass (Spec-AC-07,
  mirroring `handleRetire`'s guards-before-dry-run ordering).
- A ref satisfying neither `--release` nor `--retire` does not exist by
  construction after this scope: `--retire` owns "row present, not a work item",
  `--release` owns "work item closed, no flushable telemetry". The two refusal
  messages now cross-reference each other (Spec-AC-12).
- An EVENTS.jsonl that cannot be read leaves the close-event probe false, which
  makes `--release` refuse. Fail-closed, unchanged from `--sweep`.

Explicitly NOT in scope (each with its reason):
- `state.mjs` is a `protected_paths_l3` surface. Distinguishing a STALE closed
  focus from a LIVE other focus in `set-strategy`'s refusal text (the intake's
  optional ask) would touch it and force ceremony level 3 on this whole scope.
  Filed as a follow-up instead; `set-strategy`'s exit 2 and its refusal
  semantics are byte-unchanged here, as SPEC-0192 requires.
- `.aai/INTAKE_COMMON.md`'s LIVE OTHER FOCUS branch is unchanged: it reads
  `set-strategy`'s exit code, which this scope does not touch. No prompt-corpus
  bytes are added by this scope, so the prompt-diet companion obligation does
  not apply.
- `clear-focus`'s own defect (`fu-clearfocus-announces-unwritten-phase`) is
  untouched; this scope adds no reliance on `clear-focus`.
- `.aai/METRICS_FLUSH.prompt.md` is unchanged. The Metrics Flush role runs the
  script with no `--ref` and never needs `--release`, because rule 4b stops
  dispatching that role for the unflushable case. Verified: the prompt's RUN
  step 1 invokes `metrics-flush.mjs` bare, and `--ref` appears there only in the
  `--sweep --ref <id>` note.

## Seams this change crosses

| Seam | Who produces, who consumes | Covered by |
|---|---|---|
| `metrics-flush.mjs` writes STATE that `orchestration-dispatch.mjs` then reads to pick the next rule | release writes; dispatch reads | TEST-1394 runs `--release` for real on a fixture and then runs the REAL dispatch binary over the resulting STATE, asserting the rule changed. Not two unit tests around a mock. |
| `--release` appends to `docs/ai/EVENTS.jsonl`, which `close-work-item.mjs` owns as the close-lifecycle emitter (SPEC-0054) | release appends a NON-lifecycle event | TEST-1385 asserts the appended event's `event` field is `work_item_released` and that zero `work_item_closed` or `doc_lifecycle` lines are added, so the sole-emitter rule is not broken. |
| `--release` resets verdict blocks the PR ceremony's preconditions read | release writes `code_review`; SKILL_PR reads it | TEST-1391 asserts the post-release STATE carries zero occurrences of `AAI-VALIDATION-ARCHIVED` — the false-archive shape that once made both SKILL_PR preconditions read satisfied for a ride that satisfied neither. |
| The `--ref` exit-code change is a CLI boundary other callers may depend on | corpus callers | TEST-1383 is a negative control: the bare flush with no `--ref` is byte-for-byte unaffected. The corpus was enumerated: `.aai/METRICS_FLUSH.prompt.md` invokes the script with no `--ref`; no other `.aai/**` caller passes `--ref`. |
| Rule 4b's `needs_llm` remedy must act on every shape rule 4b reports it for | dispatch names the command; `--release` runs it | TEST-1740 parses the command out of the real dispatch output for every fixture shape (including `last_validation` pass naming the focus), runs it for real, and re-dispatches. A detector and its remedy can no longer disagree unnoticed. |
| Rule 4b's item-absent arm must name a remedy that acts | dispatch names `clear-focus`; `state.mjs` runs it | TEST-1746 builds the item-absent shapes (row absent or empty, `last_validation` not_run or pass naming the focus), parses the printed `clear-focus` command from the real dispatch output, runs it for real, and re-dispatches. |
| `--release` accepts exactly the close events dispatch accepts | dispatch matches `work_item_closed` by `refMatches`; `--release` matches by the same semantics | TEST-1748 writes a path-qualified close ref, parses the printed command from the real dispatch output, runs it, and re-dispatches. |
| A release whose STATE commit can fail must not have claimed it in EVENTS | release writes STATE then EVENTS; the dispatcher and audit read EVENTS | TEST-1749 kills the process between the two writes and TEST-1750 forces the commit rejection, asserting EVENTS and the retry each time. |
| Rule 4b's two arms must stay distinguishable: unflushable refuses, flushable still dispatches | one function, two outcomes | TEST-1392 and TEST-1393 are a matched pair, and TEST-1393's mutation inverts the precondition so the working arm must break. |

A seam no automated test crosses, written down rather than left out: the real
`docs/ai/STATE.yaml` and `docs/ai/LOOP_TICKS.jsonl` are gitignored, so CI can
never assert against the live files. Fixture coverage IS the verification for
this scope. No gate is added that would degrade to exit 0 when STATE is absent.

## Acceptance Criteria Mapping

- Intake "a ref rule 4b dispatches for MUST be actionable, or the dispatcher
  must route it somewhere that can act" -> Spec-AC-09, Spec-AC-10, Spec-AC-11
- Intake "a closed work item with no row reaches a terminal, flushed state
  rather than wedging" -> Spec-AC-02, Spec-AC-03, Spec-AC-11
- Intake "a no-op remedy is never silently satisfying" -> Spec-AC-01, Spec-AC-12
- Intake "do not fabricate the ledger entry; a missing row must flush as absent"
  -> Spec-AC-06, Spec-AC-08
- Intake "report-and-refuse beats auto-repair; evaluate the close-ceremony
  ordering, not just the happy path" -> Spec-AC-04, Spec-AC-05, Spec-AC-07
- Remediation round 1 (validation findings B1, N1, N2, N3, N5) -> Spec-AC-05
  (amended), Spec-AC-13, Spec-AC-14, Spec-AC-15, Spec-AC-16, Spec-AC-17; N4 is a
  documented non-change (see `## Design decision`, report-and-refuse paragraph)
- Remediation round 2 (validation findings B2, N7) -> Spec-AC-18, Spec-AC-19
- Remediation round 3 (PR bot review P1, P2) -> Spec-AC-20, Spec-AC-21
- Intake "do not weaken the SPEC-0192 refusal" -> out of scope by construction,
  recorded under `## Implementation plan`; Spec-AC set touches no `state.mjs` byte

## Constitution deviations

- Article 6 (single-writer state). `--release` adds a second STATE-writing
  entry point inside `.aai/scripts/metrics-flush.mjs` rather than in
  `.aai/scripts/state.mjs`. Justified: `metrics-flush.mjs` is ALREADY a
  sanctioned STATE writer built on the same `lib/state-engine.mjs` line engine
  (`:19-20`), the operation spans EVENTS.jsonl plus STATE in one ordered
  transaction which `state.mjs`'s closed single-file contract cannot express,
  and the mirror-image exit `--retire` (SPEC-0075) already lives in exactly
  this file. The alternative, `state.mjs`, is a `protected_paths_l3` surface;
  putting the change there would raise this scope to ceremony level 3 for no
  correctness gain.
- Article 5 (additive first). One existing CLI behavior changes, not just
  grows: `--ref <ref>` naming a ref absent from `metrics.work_items` moves from
  exit 0 with `"flush": []` to exit 1 with a named refusal. Justified and
  disclosed: the old exit 0 is the defect (an explicitly named ref reported as
  an empty success), the intake names it as required behavior, and the caller
  corpus was enumerated — no `.aai/**` caller passes `--ref`, and the bare
  invocation is pinned byte-unchanged by TEST-1383.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN `metrics-flush.mjs --ref <ref>` is given a ref absent from STATE `metrics.work_items` THEN it exits 1, stderr names the ref and says it is not a flush candidate and names `--release` as the exit for a closed work item, and stdout carries no `flush` key | done | docs/ai/tdd/done-work-item-stays-in-current-focus-green-TEST-1382.log, docs/ai/tdd/done-work-item-stays-in-current-focus-green-TEST-1383.log; mutation: docs/ai/tdd/spec-done-work-item-stays-in-current-focus/mutation-TEST-1382.txt, docs/ai/tdd/spec-done-work-item-stays-in-current-focus/mutation-TEST-1383.txt | — | measured baseline is exit 0 with `"flush": []` and the ref missing from `skipped` |
| Spec-AC-02 | WHEN `metrics-flush.mjs --release <ref>` runs against a STATE whose `active_work_items` entry for the ref has `status: done`, whose `metrics.work_items` has no row for the ref, and an EVENTS.jsonl carrying a committed `work_item_closed` for the ref THEN it exits 0, EVENTS.jsonl gains exactly one line whose `event` is `work_item_released`, and the ref appears zero times in the post-run `active_work_items` block | done | docs/ai/tdd/done-work-item-stays-in-current-focus-green-TEST-1384.log, docs/ai/tdd/done-work-item-stays-in-current-focus-green-TEST-1385.log; mutation: docs/ai/tdd/spec-done-work-item-stays-in-current-focus/mutation-TEST-1384.txt, docs/ai/tdd/spec-done-work-item-stays-in-current-focus/mutation-TEST-1385.txt | — | the terminal state the wedge never reached |
| Spec-AC-03 | WHEN the released ref equals `current_focus.ref_id` THEN the post-run `current_focus` carries `type: none` and `ref_id: null`, and WHEN the released ref is some other closed ref THEN the whole `current_focus` block is byte-identical before and after | done | docs/ai/tdd/done-work-item-stays-in-current-focus-green-TEST-1386.log; mutation: docs/ai/tdd/spec-done-work-item-stays-in-current-focus/mutation-TEST-1386.txt | — | never clears a focus the call is not in |
| Spec-AC-04 | WHEN `--release <ref>` is invoked with no committed `work_item_closed` event for the ref, or with `active_work_items[ref].status` not `done`, or with the ref absent from `active_work_items` THEN each case exits 1, names the failing condition, and leaves EVENTS.jsonl and STATE.yaml byte-identical as `cmp` reports exit 0 | done | docs/ai/tdd/done-work-item-stays-in-current-focus-green-TEST-1387.log, docs/ai/tdd/done-work-item-stays-in-current-focus-green-TEST-1388.log; mutation: docs/ai/tdd/spec-done-work-item-stays-in-current-focus/mutation-TEST-1387.txt, docs/ai/tdd/spec-done-work-item-stays-in-current-focus/mutation-TEST-1388.txt | — | fail-closed on the same durable provenance `--sweep` demands; cannot clear past an incomplete close |
| Spec-AC-05 | WHEN `--release <ref>` is invoked on a ref whose `metrics.work_items` row carries at least one `agent_runs` entry THEN it exits 1 and stderr says the ref would flush and to flush it rather than release it, leaving EVENTS.jsonl and STATE.yaml byte-identical; and WHEN the ref has zero runs (row absent or `agent_runs: []`) and `last_validation` records `status: pass` naming it THEN `--release` still exits 0 and removes the ref | done | docs/ai/tdd/done-work-item-stays-in-current-focus-green-TEST-1389.log, docs/ai/tdd/done-work-item-stays-in-current-focus-green-TEST-1390.log; mutation: docs/ai/tdd/spec-done-work-item-stays-in-current-focus/mutation-TEST-1389.txt, docs/ai/tdd/spec-done-work-item-stays-in-current-focus/mutation-TEST-1390.txt | — | the truth gate is never bypassable through the new door; amended in remediation round 1: the former `last_validation` pass arm is removed because the default gate never flushes a zero-run ref, so it refused refs that nothing would flush |
| Spec-AC-06 | WHEN `--release <ref>` succeeds THEN `cmp` over `docs/ai/METRICS.jsonl` before and after exits 0, and `/usr/bin/grep -cF <ref> docs/ai/METRICS.jsonl` prints 0 | done | docs/ai/tdd/done-work-item-stays-in-current-focus-green-TEST-1391.log; mutation: docs/ai/tdd/spec-done-work-item-stays-in-current-focus/mutation-TEST-1391.txt | — | the hard no-fabrication constraint, asserted on the SUCCESS path, not only on refusals |
| Spec-AC-07 | WHEN `--release <ref> --dry-run` runs on the Spec-AC-02 fixture THEN it exits 0, stdout JSON carries a `release` key naming the ref, and `cmp` exits 0 for all three of STATE.yaml, EVENTS.jsonl and METRICS.jsonl; and WHEN `--dry-run` is combined with any Spec-AC-04 or Spec-AC-05 arm THEN it still exits 1 | done | docs/ai/tdd/done-work-item-stays-in-current-focus-green-TEST-1392.log; mutation: docs/ai/tdd/spec-done-work-item-stays-in-current-focus/mutation-TEST-1392.txt | — | guards precede the dry-run branch, as `handleRetire` already orders them |
| Spec-AC-08 | WHEN `--release <ref>` succeeds THEN the appended event's payload records the telemetry as absent and carries no token, duration or cost number, and the post-run STATE contains zero occurrences of `AAI-VALIDATION-ARCHIVED` | done | docs/ai/tdd/done-work-item-stays-in-current-focus-green-TEST-1398.log; mutation: docs/ai/tdd/spec-done-work-item-stays-in-current-focus/mutation-TEST-1398.txt | — | absence is RECORDED, not fabricated as zeroes, and no false validation archive is minted |
| Spec-AC-09 | WHEN `orchestration-dispatch.mjs` runs against a STATE whose focus work item is done, whose focus ref is not in METRICS.jsonl, for which a committed `work_item_closed` event exists, and whose `metrics.work_items` carries zero `agent_runs` for that ref THEN it exits 4 with `"verdict":"needs_llm"`, `"rule":"4b"`, and `reasons` containing both the literal `closed_focus_unflushable_no_flushable_metrics` and an element naming `metrics-flush.mjs --release` | done | docs/ai/tdd/done-work-item-stays-in-current-focus-green-TEST-1393.log; mutation: docs/ai/tdd/spec-done-work-item-stays-in-current-focus/mutation-TEST-1393.txt | — | measured baseline is exit 0 dispatching Metrics Flush; one arm, both wedge shapes, because `agentRunsFor` returns `[]` for an absent row and for `agent_runs: []` alike |
| Spec-AC-10 | WHEN the same fixture is changed only by giving the focus ref a `metrics.work_items` row with one `agent_runs` entry THEN dispatch still exits 0 with `"rule":"4b"` and `"role":"Metrics Flush"` | done | docs/ai/tdd/done-work-item-stays-in-current-focus-green-TEST-1394.log, docs/ai/tdd/done-work-item-stays-in-current-focus-green-TEST-1395.log; mutation: docs/ai/tdd/spec-done-work-item-stays-in-current-focus/mutation-TEST-1394.txt, docs/ai/tdd/spec-done-work-item-stays-in-current-focus/mutation-TEST-1395.txt | — | the arm that works today is not pruned |
| Spec-AC-11 | WHEN `--release <ref>` has been run on the Spec-AC-02 fixture THEN a second `orchestration-dispatch.mjs` run over the SAME fixture returns a `rule` other than `4b` and `reasons` containing `no_focus_ref` | done | docs/ai/tdd/done-work-item-stays-in-current-focus-green-TEST-1396.log; mutation: docs/ai/tdd/spec-done-work-item-stays-in-current-focus/mutation-TEST-1396.txt | — | the wedge is gone rather than masked; this is the same terminal state a normal full-reset flush produces, verified against a focus-nulled fixture during planning |
| Spec-AC-12 | WHEN `--retire <ref>` is invoked on a ref whose `metrics.work_items` row carries zero `agent_runs` and for which a committed `work_item_closed` event exists THEN it still exits 1 and its refusal names `--release` as the correct exit instead of telling the caller to flush a ref the flush skips | done | docs/ai/tdd/done-work-item-stays-in-current-focus-green-TEST-1397.log; mutation: docs/ai/tdd/spec-done-work-item-stays-in-current-focus/mutation-TEST-1397.txt | — | removes the measured self-contradiction between `--retire` and the sweep gate |
| Spec-AC-13 | WHEN dispatch returns rule 4b `needs_llm` for a closed zero-run focus whose work item is done (item-absent shapes: Spec-AC-18), on every fixture shape (row absent or `agent_runs: []`, crossed with `last_validation` not_run or pass naming the focus) THEN the `metrics-flush.mjs --release <ref> --reason` command its reasons print exits 0 when run, and a second dispatch over the resulting STATE returns a `rule` other than `4b` | done | docs/ai/tdd/done-work-item-stays-in-current-focus-green-TEST-1740.log; mutation: docs/ai/tdd/spec-done-work-item-stays-in-current-focus/mutation-TEST-1740.txt | — | detector and remedy agree for every shape rule 4b reports; validation round 1 finding B1 |
| Spec-AC-14 | WHEN `--release` releases the focused ref while other non-done work is in flight THEN a `last_validation` or `code_review` block that does not name the released ref is byte-identical afterwards, a block that does name it is reset to `not_run`, and no note reads `reset after flush` | done | docs/ai/tdd/done-work-item-stays-in-current-focus-green-TEST-1741.log; mutation: docs/ai/tdd/spec-done-work-item-stays-in-current-focus/mutation-TEST-1741.txt | — | another ride's verdicts survive; validation round 1 finding N1 |
| Spec-AC-15 | WHEN `--release <ref>` is invoked and `last_validation` is `fail` with `ref_id` naming the ref, or `code_review` is `fail` with `scope_ref_id` naming it THEN it exits 1 naming the fail verdict and leaves STATE.yaml, EVENTS.jsonl and METRICS.jsonl byte-identical, with and without `--dry-run`; and a fail naming another ride does not block | done | docs/ai/tdd/done-work-item-stays-in-current-focus-green-TEST-1742.log; mutation: docs/ai/tdd/spec-done-work-item-stays-in-current-focus/mutation-TEST-1742.txt | — | decision: refuse as an incomplete close rather than keep the verdict untouched, because a release removes the work item and a fail verdict with no item to remediate would be stranded; validation round 1 finding N2 |
| Spec-AC-16 | WHEN the latest `work_item_closed` event for the ref is followed by a `doc_lifecycle` event whose `payload.from` is `done` THEN `--release` exits 1 naming the re-open and writes nothing, a close recorded after the re-open makes it releasable, and dispatch does not route that focus to rule 4b (`close_event_superseded_by_reopen` true, `rule` other than `4b`) | done | docs/ai/tdd/done-work-item-stays-in-current-focus-green-TEST-1743.log, docs/ai/tdd/done-work-item-stays-in-current-focus-green-TEST-1744.log; mutation: docs/ai/tdd/spec-done-work-item-stays-in-current-focus/mutation-TEST-1743.txt, docs/ai/tdd/spec-done-work-item-stays-in-current-focus/mutation-TEST-1744.txt | — | a superseded close does not count as closed; validation round 1 finding N3 |
| Spec-AC-17 | WHEN `--release <ref>` is combined with `--ref` or `--sweep` THEN it exits 2 with a mutually-exclusive message and writes nothing | done | docs/ai/tdd/done-work-item-stays-in-current-focus-green-TEST-1745.log; mutation: docs/ai/tdd/spec-done-work-item-stays-in-current-focus/mutation-TEST-1745.txt | — | like `--release` with `--retire`; validation round 1 finding N5 |
| Spec-AC-18 | WHEN `orchestration-dispatch.mjs` runs against a closed focus (committed `work_item_closed`, no flushable runs) whose ref is absent from `active_work_items`, on every fixture shape (row absent or `agent_runs: []`, crossed with `last_validation` not_run or pass naming the focus) THEN it exits 4 with rule `4b`, `reasons` containing `closed_focus_item_absent_no_flushable_metrics` and a `state.mjs clear-focus --ref` command and no `--release` element, the printed command exits 0 when run, and a second dispatch returns a `rule` other than `4b` | done | docs/ai/tdd/done-work-item-stays-in-current-focus-green-TEST-1746.log; mutation: docs/ai/tdd/spec-done-work-item-stays-in-current-focus/mutation-TEST-1746.txt | — | detector and remedy agree for the item-absent shape; validation round 2 finding B2 |
| Spec-AC-19 | WHEN `--release <ref>` releases the focused ref with no other non-done work in flight and `last_validation` or `code_review` is `fail` without naming the ref THEN it exits 1 naming the fail verdict and leaves STATE.yaml, EVENTS.jsonl and METRICS.jsonl byte-identical, with and without `--dry-run` | done | docs/ai/tdd/done-work-item-stays-in-current-focus-green-TEST-1747.log; mutation: docs/ai/tdd/spec-done-work-item-stays-in-current-focus/mutation-TEST-1747.txt | — | a release never erases a fail verdict it does not own; validation round 2 finding N7 |
| Spec-AC-20 | WHEN a committed `work_item_closed` event names the focus by a path-qualified ref (`docs/issues/CHANGE-0001` for focus `CHANGE-0001`) and dispatch returns rule `4b` THEN the `--release` command it prints exits 0 when run on that fixture, and a second dispatch returns a `rule` other than `4b` | done | docs/ai/tdd/done-work-item-stays-in-current-focus-green-TEST-1748.log; mutation: docs/ai/tdd/spec-done-work-item-stays-in-current-focus/mutation-TEST-1748.txt | — | release provenance uses the dispatcher ref matching; PR bot review P1 |
| Spec-AC-21 | WHEN a release dies after the STATE commit but before its event, or its STATE commit is rejected for concurrent modification THEN EVENTS.jsonl carries no `work_item_released` event for the ref, a retry after the death appends exactly one event and leaves STATE untouched, a retry after the rejection releases exactly once, and a retry after the rejection where a run was added refuses with EVENTS.jsonl byte-identical and the in-flight record removed | done | docs/ai/tdd/done-work-item-stays-in-current-focus-green-TEST-1749.log; mutation: docs/ai/tdd/spec-done-work-item-stays-in-current-focus/mutation-TEST-1749.txt | — | EVENTS never claims a release that did not happen; PR bot review P2 |

Status values: planned | implementing | done | deferred | blocked | rejected
- planned: AC defined, no implementation started
- implementing: work in flight; not allowed at PASS claim time
- done: implementation complete; requires non-empty Evidence naming a docs/ai/tdd artifact at hand-off
- deferred: explicitly postponed; requires Review-By in the future (minimum +14 days) + Notes naming target doc or reason
- blocked: implementation cannot proceed; requires Review-By + Notes naming blocker
- rejected: AC will not be implemented; requires Notes with rationale

## Test Plan

Mutation cells are one-token substitutions, either on the named shapes this
spec MANDATES under `## Implementation plan` or on bytes measured to be unique
in the current files. Measured under plain `bash` with `/usr/bin/grep -cF`
at `9f718c08`:
`if (opts.ref && ref !== opts.ref)` = 1 on `.aai/scripts/metrics-flush.mjs`;
`if (opts.retire !== null) {` = 1 on the same file;
`is not present in metrics.work_items — nothing to retire` = 1 on the same file;
`retire refused: "${ref}" would flush (a committed work_item_closed event exists` = 1 on the same file;
`return dispatchFor('Metrics Flush', s, '4b', { reasons: ['closed_but_unflushed_focus'] });` = 1 on `.aai/scripts/orchestration-dispatch.mjs`.
A mutation that targets a shape this spec mandates but implementation renames
must be restamped mechanically and the restamp disclosed in the TDD record.

Restamp at implementation (disclosed): `mutation-run.mjs --sed` takes a
JavaScript RegExp, so every `(`, `)`, `{`, `[` and `.` in a pattern must be
escaped or the pattern matches a different string (measured: the original
TEST-1382 cell left the target byte-identical and was refused). All Mutation
cells below are the escaped forms. Three cells also changed in substance, because
the original could not redden its own test: TEST-1391 now substitutes a
one-element array (the original named a variable that does not exist in
`handleRelease`, so it would die with a ReferenceError instead of fabricating a
line); TEST-1396 now inverts the `focusRef === ref` branch (the original only
rewrote a reason string on a line the post-release dispatch never reaches);
TEST-1397 now forces `noRuns` false (the original left the new `--release` hint
intact, so the message still named it).

Every RED observation is recorded under `docs/ai/tdd/` as
`done-work-item-stays-in-current-focus-red-<TEST-ID>.log`, and every mutation
result as
`docs/ai/tdd/spec-done-work-item-stays-in-current-focus/mutation-<TEST-ID>.txt`.
All fixtures are scratch temp-dir repos driven through the existing
`--state` / `--metrics` / `--events` / `--ticks` / `--pricing` and
`--state` / `--root` path-injection flags, following the `mk_repo` and
`write_flush_state` idiom already in `tests/skills/test-aai-metrics.sh`. The
real runtime files are never touched.

| Test ID  | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|----------|---------|------|----------------------|-------------|----------|--------|
| TEST-1382 | Spec-AC-01 | integration | tests/skills/test-aai-metrics.sh | `--ref <absent-ref> --dry-run` exits 1, stderr names the ref and `--release`, stdout has no `flush` key | sed:s/!entries\.some\(e => e\.ref === opts\.ref\)/false/ | green |
| TEST-1383 | Spec-AC-01 | integration | tests/skills/test-aai-metrics.sh | negative control: a bare flush with no `--ref` over the canonical fixture is byte-for-byte the pre-change plan, so the new guard cannot fire on the default path | sed:s/if \(opts\.ref && ref !== opts\.ref\)/if (true)/ | green |
| TEST-1384 | Spec-AC-02 | integration | tests/skills/test-aai-metrics.sh | `--release` on the row-less closed fixture exits 0 and the ref disappears from `active_work_items` | sed:s/if \(opts\.release !== null\) \{/if (false) {/ | green |
| TEST-1385 | Spec-AC-02 | integration | tests/skills/test-aai-metrics.sh | EVENTS.jsonl gains exactly one line, its `event` is `work_item_released`, and zero `work_item_closed` or `doc_lifecycle` lines are added | sed:s/'work_item_released'/'work_item_closed'/ | green |
| TEST-1386 | Spec-AC-03 | integration | tests/skills/test-aai-metrics.sh | releasing the focused ref nulls `current_focus`; releasing a non-focused closed ref leaves the `current_focus` block byte-identical | sed:s/if \(focusRef === ref\) \{/if (true) {/ | green |
| TEST-1387 | Spec-AC-04 | integration | tests/skills/test-aai-metrics.sh | no committed `work_item_closed` event: exit 1, named reason, `cmp` clean on EVENTS and STATE | sed:s/if \(!hasCloseEventFor\(eventsPath, ref\)\) \{/if (false) {/ | green |
| TEST-1388 | Spec-AC-04 | integration | tests/skills/test-aai-metrics.sh | `active_work_items[ref].status` is `in_progress`, and separately the ref is absent from `active_work_items`: both exit 1, both `cmp` clean | sed:s/statusByRef\.get\(ref\) !== 'done'/false/ | green |
| TEST-1389 | Spec-AC-05 | integration | tests/skills/test-aai-metrics.sh | a row with one `agent_runs` entry is refused with a flush-it-do-not-release message, `cmp` clean | sed:s/releaseEntry\.runs\.length > 0/false/ | green |
| TEST-1390 | Spec-AC-05 | integration | tests/skills/test-aai-metrics.sh | `last_validation` pass naming a zero-run ref (row absent, and row with `agent_runs: []`) does not block: release exits 0, the ref leaves STATE, METRICS.jsonl is byte-identical | sed:s/if \(vStatus === 'fail' && refMatches\(vRef, ref\)\) \{/if (releaseWouldFlushByDefaultGate(vStatus, vRef, ref) ? true : vStatus === 'fail' && refMatches(vRef, ref)) {/ | green |
| TEST-1391 | Spec-AC-06 | integration | tests/skills/test-aai-metrics.sh | after a successful release `cmp` on METRICS.jsonl exits 0 and `grep -cF <ref>` on it is 0 | sed:s/const releaseLedgerEntries = \[\];/const releaseLedgerEntries = [{ ref_id: ref }];/ | green |
| TEST-1398 | Spec-AC-08 | integration | tests/skills/test-aai-metrics.sh | the appended event payload records telemetry absent and carries no token, duration or cost number, and the post-release STATE holds zero `AAI-VALIDATION-ARCHIVED` occurrences | sed:s/telemetry: 'absent'/telemetry: 'zero'/ | green |
| TEST-1392 | Spec-AC-07 | integration | tests/skills/test-aai-metrics.sh | `--release --dry-run` prints a `release` key and `cmp` is clean on STATE, EVENTS and METRICS; the same dry run on the Spec-AC-04 and Spec-AC-05 arms still exits 1 | sed:s/if \(opts\.dryRun\) \{/if (false) {/ | green |
| TEST-1393 | Spec-AC-09 | integration | tests/skills/test-aai-orchestration-dispatch.sh | the row-less closed focus yields exit 4, `needs_llm`, rule `4b`, and both reason elements; the `agent_runs: []` variant yields the identical verdict | sed:s/s\.focus_flushable_runs < 1/false/ | green |
| TEST-1394 | Spec-AC-10 | integration | tests/skills/test-aai-orchestration-dispatch.sh | negative control: a focus ref with one recorded `agent_runs` entry still dispatches Metrics Flush at rule 4b, exit 0 | sed:s/s\.focus_flushable_runs < 1/s.focus_flushable_runs >= 1/ | green |
| TEST-1395 | Spec-AC-10 | integration | tests/skills/test-aai-orchestration-dispatch.sh | the snapshot field itself reports the real count, so a focus with a run is never reported as unflushable | sed:s/agentRunsFor\(lines, focusRef\)\.length : 0/0 : 0/ | green |
| TEST-1396 | Spec-AC-11 | integration | tests/skills/test-aai-orchestration-dispatch.sh | seam: run the real `--release`, then the real dispatch over the resulting STATE, and assert the rule is not `4b` and `reasons` contains `no_focus_ref` | sed:s/if \(focusRef === ref\) \{/if (false) {/ | green |
| TEST-1397 | Spec-AC-12 | integration | tests/skills/test-aai-metrics.sh | `--retire` on the zero-run closed ref exits 1 and its message names `--release` | sed:s/const noRuns = entry\.runs\.length === 0;/const noRuns = false;/ | green |
| TEST-1740 | Spec-AC-13 | integration | tests/skills/test-aai-orchestration-dispatch.sh | seam: for rule-4b needs_llm fixtures (row absent and row empty, each with last_validation not_run and with pass naming the focus) the printed --release command is parsed and run for real, exits 0, and a second dispatch is not rule 4b | sed:s/if \(vStatus === 'fail' && refMatches\(vRef, ref\)\) \{/if (releaseWouldFlushByDefaultGate(vStatus, vRef, ref) ? true : vStatus === 'fail' && refMatches(vRef, ref)) {/ | green |
| TEST-1741 | Spec-AC-14 | integration | tests/skills/test-aai-metrics.sh | other work in flight: another ride's last_validation and code_review stay byte-identical, blocks naming the released ref reset with a release note, a mixed case resets only the matching block, and no note says reset after flush | sed:s/if \(refMatches\(vRefNow, ref\)\) \{/if (true) {/ | green |
| TEST-1742 | Spec-AC-15 | integration | tests/skills/test-aai-metrics.sh | a fail verdict naming the ref (last_validation, and code_review scope_ref_id) is refused with and without dry-run and writes nothing, while a fail naming another ride does not block | sed:s/if \(vStatus === 'fail' && refMatches\(vRef, ref\)\) \{/if (false) {/ | green |
| TEST-1743 | Spec-AC-16 | integration | tests/skills/test-aai-metrics.sh | a work_item_closed followed by a doc_lifecycle from done is refused naming the re-open and writes nothing, and a later re-close is releasable | sed:s/if \(closeSupersededByReopen\(eventsPath, ref\)\) \{/if (false) {/ | green |
| TEST-1744 | Spec-AC-16 | integration | tests/skills/test-aai-orchestration-dispatch.sh | dispatch over a reopen-superseded close (row absent, and row with a run) reports the superseded flag true and never returns rule 4b or either 4b reason | sed:s/s\.close_event_present === true\n        && s\.close_event_superseded_by_reopen !== true/s.close_event_present === true/ | green |
| TEST-1745 | Spec-AC-17 | integration | tests/skills/test-aai-metrics.sh | --release with --ref and with --sweep each exit 2 naming mutual exclusion and write nothing | sed:s/opts\.release !== null && \(opts\.ref/false && (opts.ref/ | green |
| TEST-1746 | Spec-AC-18 | integration | tests/skills/test-aai-orchestration-dispatch.sh | seam: for item-absent closed-focus fixtures (row absent and empty, each with last_validation not_run and pass naming the focus) dispatch prints the item-absent reason and a clear-focus command, no --release element, the command is run for real and exits 0, and a second dispatch is not rule 4b | sed:s/s\.focus_flushable_runs < 1 && s\.work_item == null/false/ | green |
| TEST-1747 | Spec-AC-19 | integration | tests/skills/test-aai-metrics.sh | full-reset branch: a fail verdict not naming the ref (last_validation naming another ref, last_validation with null ref, code_review with null scope_ref_id) is refused with and without dry-run and writes nothing | sed:s/if \(remainingNow\.every\(it => it\.status === 'done'\)\) \{/if (false) {/ | green |
| TEST-1748 | Spec-AC-20 | integration | tests/skills/test-aai-orchestration-dispatch.sh | seam: with a path-qualified work_item_closed ref, for rule-4b fixtures (row absent and empty, each with last_validation not_run and pass naming the focus) the printed --release command is parsed and run for real, exits 0, and a second dispatch is not rule 4b | sed:s/if \(!hasCloseEventFor\(eventsPath, ref\)\) \{/if (!closedRefs(eventsPath).has(ref)) {/ | green |
| TEST-1749 | Spec-AC-21 | integration | tests/skills/test-aai-metrics.sh | a release killed after the STATE commit leaves EVENTS byte-identical, a dry run over it writes nothing, the retry appends exactly one event and leaves STATE untouched, and a further release refuses without a duplicate | sed:s/hasCloseEventFor\(eventsPath, ref\) && !closeSupersededByReopen\(eventsPath, ref\)\) \{/false) {/ | green |
| TEST-1750 | Spec-AC-21 | integration | tests/skills/test-aai-metrics.sh | a STATE commit rejected for concurrent modification leaves no event, the retry releases exactly once, and a retry after a run was added refuses with EVENTS byte-identical and the in-flight record removed | sed:s/const pendingTmp = /appendReleaseEvent(eventsPath, event); const pendingTmp = / | green |

Test status values: pending -> red -> green

## Verification

Commands to run (every one of them from the repository root):
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-metrics.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-orchestration-dispatch.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-state.sh` — the
  SPEC-0192 `set-strategy` refusal and the strategy-enum pins must not move
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-check-state.sh` — always-on core suite
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-orchestration-mode.sh` — reads the same STATE schema header
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh` with
  `AAI_TEST_TIMEOUT=3000` for the full sweep, once, before close
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0224-spec-done-work-item-stays-in-current-focus.md`
- `node .aai/scripts/docs-audit.mjs --strict`

Evidence artifacts: the per-TEST RED logs and mutation records named under
`## Test Plan`, plus the fixture directories each test builds and the stdout of
each dispatch and flush invocation quoted in the validation report.

PASS criteria: all TEST-xxx in status green AND all Spec-AC in a terminal
status AND both named suites green AND the three non-scope suites above green
(non-regression) AND `docs-audit --strict` CLEAN.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: `done-work-item-stays-in-current-focus`
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available

### Evidence by strategy

Recorded strategy is `tdd`, so the demanded evidence is the `tdd / hybrid` row:
a stored RED artifact per AC-gating test under `docs/ai/tdd/` plus the full
verification matrix above, and a verified Mutation cell per Test Plan row.

| Strategy     | Evidence this spec may demand                                   |
|--------------|-----------------------------------------------------------------|
| tdd / hybrid | stored RED artifact per AC-gating test (docs/ai/tdd/) plus the full verification matrix — unchanged |
| loop         | per-TEST-xxx green runs; RED-proof observed, storage optional    |
| direct       | targeted regression tests green (exit codes) plus the scoped diff — NO stored RED artifact, NO matrix beyond the declared versions |
| untested     | the recorded strategy rationale plus the scoped diff — no test suites demanded for the scope itself |

## Registry items closed by this scope

none. Read from `node .aai/scripts/follow-ups.mjs list` (168 open items) and
scanned for this scope's subjects; this scope closes no registry item. (The body
opens with the `none` sentinel on purpose: `follow-ups.mjs verify-closures` reads
a leading `fu-` id in an unlabelled bullet as a closure CLAIM, and the three
items named below are neighbours, not claims.)

Open items whose subject this scope TOUCHES, and why each stays open:
- `fu-clearfocus-announces-unwritten-phase` (P3) — a defect inside
  `state.mjs`'s `clear-focus`. This scope deliberately adds no reliance on
  `clear-focus` and does not touch `state.mjs` (an L3 protected surface), so the
  defect is neither triggered nor fixed here. Stays open.
- `fu-verdict-coverage-same-second-true` (P3) — lives in
  `metrics-flush.mjs`'s `verdictAfterLastImplementer`, a function no AC in this
  spec reads or writes. Batching it in would mean editing the default verdict
  gate while adding a disjoint branch, which is the shape the file's own header
  warns against. Stays open.
- `fu-set-strategy-ref-shape` (P2) — `set-strategy --ref` shape validation,
  inside `state.mjs`. Same L3 reason as above. Stays open.

Correction to the intake: `fu-overview-shows-closed-ride-inflight` is recorded
as **done** in `docs/ai/decisions.jsonl` (a `follow_up_status` record,
`resolved_by: dispatch-state-sweep`, 2026-09-13). The intake lists it as open;
it is not, and this scope does not need to close it.

## Residual risks

- RR-1. Full autonomy is deliberately not delivered. After this scope an
  unflushable closed focus REPORTS `needs_llm` and waits for the remedy to be
  run; it does not self-heal. That is the intake's own constraint
  (report-and-refuse over auto-repair) and the cost is one human or
  human step per occurrence. The `needs_llm` reason is not in the orchestration
  prompt's named-reasons list, so the LLM orchestrator reports and stops
  (precedent: `closed_focus_stale_state`); the owner or a human runs the
  printed command.
- RR-2. A released ride is absent from `docs/ai/METRICS.jsonl` forever, so the
  factory report never counts it. This is an accepted, disclosed telemetry loss
  — the alternative is a fabricated reliability record — and the
  `work_item_released` event is the durable record that the loss happened and
  why.
- RR-3. The real `docs/ai/STATE.yaml` and `docs/ai/LOOP_TICKS.jsonl` are
  gitignored, so no CI assertion can ever run against the live files. Every AC
  here is fixture-proved. A regression that only manifests against a live STATE
  shape no fixture reproduces would not be caught.
- RR-4. Rule 4b's new precondition reads one more STATE value. If a future STATE
  shape makes `agentRunsFor` return `[]` for a row that DOES carry runs, rule 4b
  would refuse a flushable focus instead of dispatching it — a visible refusal
  rather than a silent wedge, but still a regression. TEST-1394 and TEST-1395
  are the matched negative controls against exactly that.
- RR-5. The caller enumeration for the `--ref` exit-code change covered
  `.aai/**` and the test suites. A downstream vendored project that scripts
  `metrics-flush.mjs --ref` around an absent ref and treats exit 0 as success
  would newly see exit 1. Disclosed under `## Constitution deviations`,
  Article 5.

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
