---
id: spec-ride-state-handoff-to-worktree
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: 464a179bb2e09420a7413c8feaa4f2c7ee934ab7a593ca609f1ab61292da0682
ceremony_level: 2
links:
  requirement: ride-state-handoff-to-worktree
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Hand a ride's STATE to its worktree and back, carrying only that ride

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/CHANGE-DRAFT-ride-state-handoff-to-worktree.md
- Parent: docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md (owner decisions of 2026-10-22, order item 2, "ride reliability")
- Reused, not duplicated: .aai/SKILL_WORKTREE.prompt.md (fresh init), .aai/scripts/lib/state-engine.mjs (atomic write), .aai/scripts/metrics-flush.mjs (ledger gates), .aai/scripts/merge-cleanup.mjs (post-merge steps), .aai/scripts/orchestration-dispatch.mjs (rule 5/6 closed-focus guard)
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values

- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred: entire spec postponed; explain reason in this section
- rejected: spec was abandoned; explain rationale
- superseded: replaced by a newer spec; set links to the replacement

## Baseline and measurements (Planning, 2026-10-22)

Baseline tree: main `d28244196e8d4b9e78b03b181f7dfc3dfde34bf2`.

Measured on the archived evidence of PR #491
(`docs/ai/archive/merge-cleanup/pr-491/`, local and gitignored in the main
checkout), using the baseline scripts against scratch copies:

- M1. The origin STATE left after #491 merged
  (`manual/docs/ai/STATE.main-before.yaml`, 2,519 lines) still had
  `current_focus.ref_id: slim-standing-role-context`, that ride's work item
  `phase: planning status: in_progress`, and a `metrics.work_items` row with
  one Planning run (started 2026-10-22T16:18:38Z). The same run is present in
  the main METRICS.jsonl entry for that ref (flushed from the worktree).
- M2. `orchestration-dispatch.mjs --state <that file>` returns
  `verdict: needs_llm`, `rule: 5`, `reasons: [closed_focus_stale_state]`.
  The dispatcher detects the stale origin but nothing deterministic heals it;
  it was repaired by hand.
- M3. The origin STATE carried 37 `metrics.work_items` rows with 152 runs;
  36 rows (151 runs) belong to other refs. The ride worktree's final STATE
  (`worktree/docs/ai/STATE.yaml`) carried the same 36 foreign rows, which is
  the whole-STATE copy the LEARNED memory `worktree-carry-live-state`
  prescribes. The worktree also carried another ride's `last_validation`
  history and the origin's `worktree` block named a third ride's
  branch and path (`change/docs-audit-node-test-pilot`).
- M4. On that copied STATE, `metrics-flush.mjs --dry-run --sweep` (no `--ref`)
  plans to FLUSH three foreign refs (`reaper-test-018-etime-shape-guard`,
  `spec-vagueness-gate`, `simple-and-friendly-to-use`) and to resume-clean
  eight more. Run inside a ride worktree, those land in that ride's PR
  diff; this is the #482/#484 leak class (a foreign run with an alias model
  id turned main red on pricing FAIL-002).
- M5. `metrics-flush.mjs --dry-run --ref slim-standing-role-context` (with and
  without `--sweep`) on the same file selects only that ref and classifies it
  `resume` (already in the ledger, cleanup-only). So `--ref` restriction and
  the idempotent-resume gate already prevent a DOUBLE METRICS entry; the
  double count named in the intake does not reproduce. What remains broken is
  (a) every unrestricted flush/sweep in a worktree that holds a copied STATE
  (M4) and (b) the stale origin focus that wedges dispatch (M2).
- M6. `close-work-item.mjs` state-reconcile writes only the worktree's own
  STATE and says the main checkout's STATE is untouched (by design).
  `merge-cleanup.mjs` archives the worktree STATE (`archive-runtime`) but has
  no step that touches the origin STATE; its former `state` step was removed
  by SPEC-0225 because at the time it fired 0 of 8 runs (focus already
  cleared at close for inline rides). That removal did not consider a ride
  whose STATE was copied into a worktree after Planning, which is #491's
  shape.

Scope sized to M4 and M2: a deterministic move of exactly one ride into its
worktree, and a post-merge reconcile of the origin. No change to
metrics-flush.mjs, state.mjs or the STATE format.

## Implementation strategy

- Strategy: tdd
- Rationale: two new deterministic writers over the only runtime memory (STATE) plus a new merge-cleanup step. Each property (partition, conservation, foreign-flush impossibility, reconcile, refusal atomicity, resume) is a fixture assertion that must be observed RED against the baseline tree, where the command does not exist, and then against a planted mutation. No intake-recorded strategy exists for this ref (the intake Notes carry no `Implementation mode (user choice):` line).

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound multi-surface change (new script, merge-cleanup step, two prompts, suites, fixtures) in a main checkout shared with other sessions holding unrelated untracked drafts. Not L3: no `protected_paths_l3` path is touched (D7).
- User decision: worktree (already in effect; this ride started in a fresh worktree, autopilot default recorded by the orchestrator before Planning)
- Base ref: main
- Worktree branch/path: change/ride-state-handoff-to-worktree at /private/tmp/aai-ride-state-handoff
- Code review: required, independent dual verdict over the explicit scope in the brief against main.

## Design and boundaries

### D1: One new script, two subcommands

New file `.aai/scripts/ride-handoff.mjs` (Node stdlib only, imports
`lib/state-engine.mjs` and `lib/state-core.mjs` read-only, without changing
them):

```
node .aai/scripts/ride-handoff.mjs out --ref <R> --worktree <abs path>
     [--state <origin STATE path>] [--base-ref <ref>] [--dry-run]
node .aai/scripts/ride-handoff.mjs reconcile --ref <R>
     [--state <origin STATE path>] [--metrics <METRICS.jsonl path>]
     [--branch <ride branch>] [--dry-run]
```

`--state` defaults to `docs/ai/STATE.yaml` under the current directory; the
origin root is the directory three levels above it. `--metrics` defaults to
`<origin root>/docs/ai/METRICS.jsonl`. The worktree STATE is
`<worktree>/docs/ai/STATE.yaml`.

Exit contract: 0 done, resumed or no-op; 1 refusal with
`REFUSE <reason> <detail>` on stdout and nothing written; 2 usage; 3 the
single-writer refusal (D6). Reason codes are a closed set:
`ref_not_in_origin`, `worktree_not_registered`, `worktree_state_not_fresh`,
`hitl_pending`, `draft_conflict`, `origin_runs_not_in_ledger`.
Success lines start `HANDOFF`, `RESUMED`, `RECONCILED` or `NOOP no_trace`.

Why not `state.mjs` subcommands: `state.mjs`, `lib/state-engine.mjs` and
`lib/state-core.mjs` are `protected_paths_l3`, and `state.mjs` is a closed
single-file mutator while `out` writes two STATE files. `metrics-flush.mjs`
is the precedent for a multi-file transaction over the shared engine.

### D2: What belongs to ride R (the partition)

In a STATE file, the ride-bound content for R is exactly:

- `current_focus` when `current_focus.ref_id` is R;
- the `active_work_items` item whose `ref_id` is R;
- the `metrics.work_items` entry keyed R (all its lines, verbatim);
- `implementation_strategy` when its `ref_id` is R;
- `code_review` when its `scope_ref_id` is R;
- `last_validation` when its `ref_id` is R;
- `tdd_cycle` when its `spec_path` is non-null and equals R's spec path;
- from `worktree`, only `recommendation` and `rationale`, and only when
  `current_focus.ref_id` is R (Planning wrote them for the focus; branch,
  path and decision may belong to another session, M3).

Everything else is foreign and is never copied, edited or reordered.

### D3: `out` (origin to worktree)

Preconditions, all checked before any write:
1. R is the origin focus or has an origin active work item, else
   `ref_not_in_origin`.
2. `--worktree` is absolute and appears in
   `git -C <origin root> worktree list --porcelain` (realpath compared), else
   `worktree_not_registered`.
3. The worktree STATE exists (created by the existing Setup Worktree step 4:
   `worktree-seed.mjs` then `check-state.mjs --repair`) and is fresh: no
   `metrics.work_items` runs, no active work item other than R, focus `none`
   or R. Else `worktree_state_not_fresh`, except the resume case in D5.
4. Origin `human_input.required` is not true while the focus is R, else
   `hitl_pending`.
5. Draft carry (D4) has no conflict, else `draft_conflict`.

Effects, in this order: build both new contents in memory; write the archive
directory `<origin root>/docs/ai/archive/handoffs/<R>-<UTC stamp>/` holding a
byte copy of the pre-handoff origin STATE and `record.json`; copy drafts into
the worktree (D4); write the worktree STATE; move the origin's untracked
drafts into the archive directory; write the origin STATE; mark the record
done.

Worktree STATE result: the fresh file with every D2 ride-bound block of the
origin spliced in verbatim (block lines replace the fresh block; the metrics
entry lands under `metrics.work_items`), and its `worktree` block set to
`user_decision: worktree`, `branch` = `git -C <worktree> branch
--show-current`, `path` = realpath of `--worktree`, `base_ref` = `--base-ref`,
else the origin `worktree.base_ref`, else usage exit 2, plus the carried
`recommendation` and `rationale`.

Origin STATE result: every D2 ride-bound block removed or reset to the
`.aai/templates/STATE_TEMPLATE.yaml` values (focus type `none` with null
ref, path and spec path; strategy `undecided` with nulls; code_review and
last_validation template values; tdd_cycle IDLE with nulls); the active work
item and the metrics entry removed; the origin `worktree` block reset to
template values only when its `branch` or `path` names this worktree. Foreign
lines byte-identical. `updated_at_utc` bumped through the engine.

`record.json` (machine-only manifest, JSON per RFC-0017 decision 3):
`{ref, worktree, branch, base_ref, at_utc, runs_moved, drafts_moved,
origin_archive, status}` with `status` `started` then `done`.

`--dry-run` prints the plan (blocks moved, run count, drafts) and writes
nothing anywhere.

### D4: Draft carry

For each of the focus `primary_path`, the spec path, and
`docs/ai/briefs/<R>.md`: absent in the origin, skip; tracked in the origin
(`git ls-files --error-unmatch`), never moved, and copied into the worktree
only if the worktree lacks it; untracked in the origin, copied when the
worktree lacks it, accepted when byte-identical, `draft_conflict` when it
differs. After the worktree STATE is written, each untracked origin copy is
renamed into the archive directory (moved, not deleted). This is what lets
the worktree dispatch the same role as the origin (the spec must be present)
and keeps the origin free of the ride's leftover drafts that merge-cleanup
otherwise reports as `leftover_draft`.

### D5: Resume and atomicity

Each STATE write is the engine's tmp+rename with the pre-rename content
recheck. A crash between the worktree write and the origin write leaves R's
runs in both files. A re-run detects it: the worktree STATE's R metrics entry
is byte-identical to the origin's and the worktree holds no other runs; it
then skips the worktree write, finishes the origin side, prints `RESUMED`,
and the run count is conserved. Test-only fault hook
`AAI_RIDE_HANDOFF_INJECT_CRASH=after-worktree-write`, inert unless set.

### D6: Single-writer guard

When `AAI_ROLE=subagent` is set and either target STATE resolves to a
shipping STATE by the same two-arm rule `state.mjs` uses (inside the
script's own repository root, or `docs/ai/STATE.yaml` of a tree that has
`.aai/scripts/state.mjs`), exit 3 and write nothing. Scratch fixtures outside
every AAI project root are unaffected. The predicate is reimplemented or
moved into a new non-protected lib file; `state.mjs` is not edited.

### D7: `reconcile` (post-merge, origin side)

1. No D2 trace of R in the origin STATE: print `NOOP no_trace`, exit 0, no
   archive, no write.
2. The origin holds a metrics entry for R with runs: every run key
   (`role` plus `started_utc`) must appear among the `agent_runs` of the
   METRICS.jsonl entries whose `ref_id` is R. Otherwise (including no entry)
   `REFUSE origin_runs_not_in_ledger`, exit 1, nothing written. A run is
   never deleted unless the ledger already holds it.
3. Otherwise archive the origin STATE under
   `docs/ai/archive/handoffs/<R>-reconcile-<UTC stamp>/` and write: focus to
   template values when it is R; R's active work item removed; R's metrics
   entry removed; ride-bound blocks reset as in D3; the `worktree` block reset
   only when `--branch` is given and equals `worktree.branch`. Print
   `RECONCILED`. Foreign lines byte-identical.

Reconcile never flushes, never appends to METRICS.jsonl or EVENTS.jsonl, and
never edits a tracked file.

### D8: merge-cleanup step `reconcile-origin`

`merge-cleanup.mjs` gains one step between `sync-base` (so the merged
METRICS ledger is present) and `remove-worktree`:
`resolve plan archive-runtime sync-base reconcile-origin remove-worktree
delete-branch report`. For each ref of `mergedRefs(ctx)` it runs
`ride-handoff.mjs reconcile --ref <R> --state <origin>/docs/ai/STATE.yaml
--metrics <origin>/docs/ai/METRICS.jsonl --branch <headRef>`. Status `done`
when any ref reconciled (journalled), `noop` with detail `no_trace` or
`no_state`, `retained` when a ref refused: the refusal is added to the
report's `remaining` list as an owner decision and the run continues (never
exit 3 or 4 for this step). Plan mode lists `reconcile <R>` targets from a
`--dry-run`. The step id must not contain the substring `state`
(test-aai-merge-cleanup.sh TEST-010 pins the removed `state` step with a
substring match); `merge-cleanup.mjs` stays at most 1,722 lines (TEST-057).

### D9: Canon wiring

- `.aai/SKILL_WORKTREE.prompt.md` step 4 ("If the user chooses worktree"):
  when the ride already has origin STATE (worktree decided after Planning),
  after Setup Worktree run `ride-handoff.mjs out` from the origin instead of
  the worktree `set-focus`; never copy the whole STATE. Both the bash and the
  PowerShell setup blocks name it. The fresh-start path (worktree created
  before any origin STATE for R) is unchanged.
- `.aai/SKILL_SHIP.prompt.md` autopilot default 2 (`recommended -> worktree`)
  names the handoff for the mid-ride decision.
- `.aai/SKILL_MERGE.prompt.md` is not required to change (the step reports
  itself); if it lists steps, the list gains `reconcile-origin`.
- Prompt-corpus growth across these files is at most 900 bytes and is
  credited by one `JUSTIFIED_ADDITIONS` entry in
  `tests/skills/lib/prompt-diet-ledger.sh` with the matching TEST-012
  checkpoint bump in `tests/skills/test-aai-prompt-diet.sh`.
- `.aai/system/PROFILES.yaml` classifies `.aai/scripts/ride-handoff.mjs` as
  `core` (merge-cleanup, a core script, invokes it).
- `tests/skills/suite-map.yaml` gains a row for the new suite; the
  aai-merge-cleanup and aai-worktree rows gain `.aai/scripts/ride-handoff.mjs`.

### D10: Out of scope

STATE format changes; metrics-flush.mjs, state.mjs, state-engine and
state-core edits; merge-cleanup roadmap-overlap handling (separate draft
`merge-cleanup-resolves-framework-friction`); locking beyond session-lock;
automatic invocation of `out` by any script (it is an orchestrator step named
by canon).

## Seams and residual risks

- S1: `ride-handoff.mjs out` (producer) writes the worktree STATE that
  `metrics-flush.mjs` (consumer, unchanged) reads. Crossed by TEST-005 with
  the real flush script in default and sweep dry-run.
- S2: the same worktree STATE is read by `orchestration-dispatch.mjs`.
  Crossed by TEST-004 with the real dispatcher on both sides.
- S3: `reconcile` (producer) rewrites the origin STATE that the real
  `metrics-flush.mjs` and `orchestration-dispatch.mjs` then read. Crossed by
  TEST-009.
- S4: `merge-cleanup.mjs apply` (caller) and `ride-handoff.mjs reconcile`
  (callee) across a real merged fixture repository and the merged METRICS
  ledger. Crossed by TEST-011 in the merge-cleanup suite's own fixture world.
- S5: Setup Worktree's fresh STATE (`check-state.mjs --repair`) is the input
  `out` requires. Crossed by TEST-001, which builds the worktree STATE through
  the real initializer, never a hand-written fixture.

Residual risks:
- R1: an orchestrator that keeps running `state.mjs append-run` in the origin
  after the handoff re-creates an origin row for R. `reconcile` cleans it only
  if the ledger holds those runs; otherwise it is reported as remaining.
  A guard inside `state.mjs` would be L3 and is not attempted.
- R2: Windows. The script uses `path` and `fs.realpathSync` and spawns only
  `git` and `node`; its suite is node:test, which runs on Windows, but no
  Pester case is added. Windows coverage of `out` is by construction, not by a
  Windows CI assertion.
- R3: `reconcile-origin` may fire rarely once canon names `out` (like the
  removed `state` step). Its expected firing cases are legacy whole-copy rides
  and R1. If it stays at zero over many merges, a later debt scope may remove
  it again; the disclosure here is the evidence trail.
- R4: Constitution Article 6 deviation (below).

## Acceptance Criteria Mapping

| Requirement | Spec-AC | Verification and decisive observable | Evidence |
|---|---|---|---|
| AC-002 | Spec-AC-01 | TEST-001: worktree STATE after out carries R's blocks and zero lines naming the two foreign refs | docs/ai/tdd/ride-handoff-ac01.log |
| AC-002 | Spec-AC-02 | TEST-002: origin foreign entries byte-identical, R removed, archive and record present | docs/ai/tdd/ride-handoff-ac02.log |
| AC-003 | Spec-AC-03 | TEST-003: R's run count sums exactly, origin side zero | docs/ai/tdd/ride-handoff-ac03.log |
| AC-001 | Spec-AC-04 | TEST-004: real dispatcher same rule and role on both sides; check-state exit 0 | docs/ai/tdd/ride-handoff-ac04.log |
| Owner decision item 2 | Spec-AC-05 | TEST-005: real flush dry-run default and sweep names only R in the worktree | docs/ai/tdd/ride-handoff-ac05.log |
| AC-001 | Spec-AC-06 | TEST-006: drafts carried, conflicts refused | docs/ai/tdd/ride-handoff-ac06.log |
| Constraints | Spec-AC-07 | TEST-007: every refusal leaves both STATE files byte-identical; subagent exit 3 | docs/ai/tdd/ride-handoff-ac07.log |
| Constraints | Spec-AC-08 | TEST-008: injected crash then re-run conserves runs | docs/ai/tdd/ride-handoff-ac08.log |
| AC-004 | Spec-AC-09 | TEST-009: reconcile on the M1-shaped origin, then real flush and dispatcher | docs/ai/tdd/ride-handoff-ac09.log |
| AC-004 | Spec-AC-10 | TEST-010: reconcile refuses unledgered runs and no-ops on no trace | docs/ai/tdd/ride-handoff-ac10.log |
| AC-004 | Spec-AC-11 | TEST-011: merge-cleanup apply runs reconcile-origin; rerun noop | docs/ai/tdd/ride-handoff-ac11.log |
| AC-005 | Spec-AC-12 | TEST-012: prompts name the handoff and no whole-STATE copy | docs/ai/tdd/ride-handoff-ac12.log |
| Verification | Spec-AC-13 | TEST-013, TEST-014: companions green and no protected path in the diff | docs/ai/tdd/ride-handoff-ac13.log |

## Constitution deviations

- Article 6 (single-writer state): `ride-handoff.mjs` writes
  `docs/ai/STATE.yaml` through `lib/state-engine.mjs` `writeState` (the same
  duplicate-key scan, tmp+rename and concurrency recheck `state.mjs` uses)
  rather than through `state.mjs` itself. Justified: `metrics-flush.mjs` has
  written STATE through the same engine since CHANGE-0009; the handoff spans
  two STATE files, which the single-file `state.mjs` contract excludes; and
  putting it in `state.mjs` would make this a ceremony L3 change. The
  single-writer intent is kept: only the orchestrator runs it, and the D6
  guard refuses a dispatched subagent. The owner may instead require the
  `state.mjs` route at L3.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN ride-handoff.mjs out runs for ride R against a fixture origin STATE holding runs, active items and ref-bound blocks for R and for two foreign refs, the worktree STATE SHALL contain R's focus, active item, metrics entry (lines byte-identical to the origin's), strategy, code_review and last_validation, and grep -c for each foreign ref id over the worktree STATE SHALL be 0 | done | docs/ai/tdd/ride-handoff-ac01.log | tdd | D2, D3 |
| Spec-AC-02 | WHEN out completes the origin STATE SHALL keep every foreign metrics entry and active item byte-identical, SHALL hold no metrics entry or active item for R, SHALL have focus type none and template values in every block that named R, and docs/ai/archive/handoffs/R-stamp/ SHALL hold the pre-handoff STATE byte copy and a record.json with status done and runs_moved equal to the moved count | done | docs/ai/tdd/ride-handoff-ac02.log | tdd | D3 |
| Spec-AC-03 | WHEN out completes the number of R's agent runs in the worktree STATE SHALL equal the number in the pre-handoff origin STATE and the number in the post-handoff origin STATE SHALL be 0, and the foreign run count in the origin SHALL be unchanged | done | docs/ai/tdd/ride-handoff-ac03.log | tdd | D3; moved, not copied |
| Spec-AC-04 | WHEN out completes check-state.mjs SHALL exit 0 on both STATE files and orchestration-dispatch.mjs on the worktree (worktree STATE and root) SHALL return the same rule and role as on the pre-handoff origin, for a planned-focus fixture and for a frozen-spec fixture | done | docs/ai/tdd/ride-handoff-ac04.log | tdd | D3, D4; seam S2 |
| Spec-AC-05 | WHEN metrics-flush.mjs --dry-run runs without --ref on the worktree STATE produced by out, with and without --sweep, the union of its flush, swept, resume and skipped keys SHALL be exactly R, while the same command on a whole-STATE copy of the same origin SHALL name at least one foreign ref (negative control) | done | docs/ai/tdd/ride-handoff-ac05.log | tdd | M4; seam S1 |
| Spec-AC-06 | WHEN the focus primary_path, spec path and brief are untracked in the origin out SHALL copy them into the worktree byte-identical and move the origin copies into the archive directory, SHALL leave a tracked origin file in place, and SHALL refuse draft_conflict with both STATE files unchanged when the worktree already holds a differing copy | done | docs/ai/tdd/ride-handoff-ac06.log | tdd | D4 |
| Spec-AC-07 | WHEN out is refused for ref_not_in_origin, worktree_not_registered, worktree_state_not_fresh, hitl_pending or draft_conflict it SHALL exit 1 with REFUSE and that reason and both STATE files SHALL keep their sha256, and WHEN AAI_ROLE=subagent targets a shipping STATE it SHALL exit 3 writing nothing | done | docs/ai/tdd/ride-handoff-ac07.log | tdd | D3, D6 |
| Spec-AC-08 | WHEN out is interrupted by AAI_RIDE_HANDOFF_INJECT_CRASH=after-worktree-write and run again it SHALL print RESUMED, finish the origin side, and the Spec-AC-03 counts SHALL hold | done | docs/ai/tdd/ride-handoff-ac08.log | tdd | D5 |
| Spec-AC-09 | WHEN reconcile runs on an origin STATE shaped like M1 (focus R in planning, one R run that the ledger entry for R holds, foreign rows) it SHALL print RECONCILED, leave no focus, active item or metrics entry for R, keep foreign lines byte-identical, after which metrics-flush.mjs default and --sweep SHALL leave grep -c of R's ref_id in METRICS.jsonl at 1 and orchestration-dispatch.mjs SHALL not report closed_focus_stale_state | done | docs/ai/tdd/ride-handoff-ac09.log | tdd | D7; seam S3 |
| Spec-AC-10 | WHEN the origin holds an R run absent from the ledger entries for R, or no ledger entry exists, reconcile SHALL exit 1 with REFUSE origin_runs_not_in_ledger and the origin STATE SHALL keep its sha256, and WHEN the origin holds no trace of R it SHALL print NOOP no_trace, exit 0 and create no archive | done | docs/ai/tdd/ride-handoff-ac10.log | tdd | D7 |
| Spec-AC-11 | WHEN merge-cleanup.mjs apply runs for a merged PR whose ride's stale focus and ledgered run sit in the origin STATE the step list SHALL be resolve plan archive-runtime sync-base reconcile-origin remove-worktree delete-branch report, reconcile-origin SHALL be done and journalled with the origin STATE reconciled, a re-run SHALL report it noop, and an unledgered run SHALL make it retained with an entry in remaining while apply still exits 0 | done | docs/ai/tdd/ride-handoff-ac11.log | tdd | D8; seam S4 |
| Spec-AC-12 | WHEN the canon is read SKILL_WORKTREE.prompt.md step 4 and both setup blocks SHALL name ride-handoff.mjs out for a worktree decided after Planning, SKILL_SHIP.prompt.md autopilot default 2 SHALL name it, and no prompt SHALL instruct copying a whole STATE.yaml into a worktree | done | docs/ai/tdd/ride-handoff-ac12.log | tdd | D9 |
| Spec-AC-13 | WHEN the scope is validated the prompt-diet ledger SHALL carry an entry equal to the measured prompt growth (at most 900 B) with TEST-012 green, PROFILES.yaml SHALL classify ride-handoff.mjs as core with the layer-profiles suite green, the new suite SHALL have a suite-map row, and git diff --name-only main...HEAD SHALL list no protected_paths_l3 path | done | docs/ai/tdd/ride-handoff-ac13.log | tdd | D1, D9 |

## Implementation plan

1. RED first: write the node:test file and the merge-cleanup suite arms
   against the baseline tree; record each RED in its AC log (command absent,
   or step absent). For TEST-005 also record the negative control on the
   whole-copy fixture (it must name foreign refs on the baseline).
2. Implement `ride-handoff.mjs` (D1 to D7) over the existing engine exports;
   it calls `metricsEntrySpan`, `bumpUpdatedAt` and `fs.realpathSync` by
   those names (the Test Plan mutations target them), plus `loadState`,
   `writeState`, `findBlock`, `editBlock` and `readScalar` as needed. If an engine change seems needed, stop and
   report: that is an L3 re-plan, not an in-scope edit.
3. Add the `reconcile-origin` step to `merge-cleanup.mjs` (D8) and update
   `ALL_STEPS`, `ACTION_STEPS` and TEST-010 targets in
   `tests/skills/test-aai-merge-cleanup.sh`.
4. Canon wiring and companions (D9).
5. Run the Verification suites.

Fixtures: a reduced M1-shaped origin STATE (focus R in planning, R with one
run, two foreign refs with runs, ride-bound blocks for R, a foreign
`worktree` block) committed under `tests/fixtures/ride-handoff/`, derived
from the archived #491 shape but with no copied telemetry of real refs beyond
ids. A matching METRICS.jsonl fixture holds the ledger entry for R. Each test
builds a throwaway git repository with `git init -b main`, its own
`user.email`/`user.name`, and a real `git worktree add`; the worktree STATE is
made with the real `check-state.mjs --repair`. Absolute non-empty paths are
checked before every `cd` (HAZ-CD); nothing runs in the shipping tree
(HAZ-SCRATCH).

Edge cases: an R whose metrics entry exists but carries zero runs (moves as
is, runs_moved 0); focus is R but no active item (moves focus only); active
item for R but focus on another ref (moves the item and entry, leaves focus);
CRLF origin (engine normalizes; the byte-identity checks compare after LF
normalization of the pre-file); worktree path given through a symlink
(realpath compare).

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-ride-handoff.sh | Real git repo plus worktree, fresh worktree STATE from check-state --repair, out --ref R; assert R blocks present verbatim and grep -c of each foreign id is 0 | `sed:s/scope_ref_id/scope_ref_xx/g` on .aai/scripts/ride-handoff.mjs | green |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-ride-handoff.sh | Extract each foreign metrics entry and active item before and after and compare bytes; assert R absent, focus none, template values, archive copy sha256 equals pre-file, record.json status done and runs_moved | `sed:s/runs_moved/runs_carried/` on .aai/scripts/ride-handoff.mjs | green |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-ride-handoff.sh | Count R runs in origin-before, worktree-after, origin-after and foreign runs before and after; assert conservation and zero on origin | `sed:s/bumpUpdatedAt\(/bumpUpdatedAtMissing(/` on .aai/scripts/ride-handoff.mjs | green |
| TEST-004 | Spec-AC-04 | integration | tests/skills/test-aai-ride-handoff.sh | check-state exit 0 on both files; orchestration-dispatch rule and role equal on origin-before and worktree-after for a planned-focus and a frozen-spec fixture | `sed:s/realpathSync/realpathSyncMissing/g` on .aai/scripts/ride-handoff.mjs | green |
| TEST-005 | Spec-AC-05 | integration | tests/skills/test-aai-ride-handoff.sh | Real metrics-flush.mjs --dry-run on the worktree STATE with and without --sweep: key union equals R; negative control on a whole-file copy names a foreign ref | `sed:s/metricsEntrySpan\(/metricsEntrySpanMissing(/` on .aai/scripts/ride-handoff.mjs | green |
| TEST-006 | Spec-AC-06 | integration | tests/skills/test-aai-ride-handoff.sh | Untracked intake, spec and brief carried and origin copies archived; tracked origin file untouched; differing worktree copy refused draft_conflict with both sha256 unchanged | `sed:s/draft_conflict/draft_ok/` on .aai/scripts/ride-handoff.mjs | green |
| TEST-007 | Spec-AC-07 | integration | tests/skills/test-aai-ride-handoff.sh | One case per refusal reason asserting exit 1, the reason, and both sha256 unchanged; AAI_ROLE=subagent against a fixture that has .aai/scripts/state.mjs exits 3, and against a plain scratch STATE is unaffected | `sed:s/worktree_state_not_fresh/worktree_state_fresh/` on .aai/scripts/ride-handoff.mjs | green |
| TEST-008 | Spec-AC-08 | integration | tests/skills/test-aai-ride-handoff.sh | Inject crash after the worktree write (exit non-zero, R runs in both files), re-run prints RESUMED, counts conserved, record done | `sed:s/RESUMED/REDONE/` on .aai/scripts/ride-handoff.mjs | green |
| TEST-009 | Spec-AC-09 | integration | tests/skills/test-aai-ride-handoff.sh | M1-shaped origin plus METRICS fixture: reconcile prints RECONCILED; foreign bytes kept; real metrics-flush default and --sweep then grep -c R in METRICS equals 1; real dispatcher reasons lack closed_focus_stale_state | `sed:s/started_utc/started_at/g` on .aai/scripts/ride-handoff.mjs | green |
| TEST-010 | Spec-AC-10 | integration | tests/skills/test-aai-ride-handoff.sh | Unledgered run and missing ledger entry each refuse origin_runs_not_in_ledger with sha256 unchanged; no-trace origin prints NOOP no_trace, exit 0, no archive directory created (positive control: the fixture STATE was read, the command printed its ref) | `sed:s/no_trace/none_found/g` on .aai/scripts/ride-handoff.mjs | green |
| TEST-011 | Spec-AC-11 | integration | tests/skills/test-aai-merge-cleanup.sh | Existing fixture world with origin STATE holding the merged ride's stale focus and a run present in the merged ledger: apply step list, reconcile-origin done and journalled, origin reconciled; rerun noop; unledgered run gives retained plus remaining and exit 0 | `sed:s/'reconcile-origin',//` on .aai/scripts/merge-cleanup.mjs | green |
| TEST-012 | Spec-AC-12 | integration | tests/skills/test-aai-ride-handoff.sh | grep the named prompts for ride-handoff.mjs out in SKILL_WORKTREE step 4 and both setup blocks and SKILL_SHIP default 2; assert no .aai prompt contains a cp or Copy-Item of a STATE.yaml into a worktree path | `sed:s/ride-handoff.mjs out/ride-handoff.mjs/g` on .aai/SKILL_SHIP.prompt.md | green |
| TEST-013 | Spec-AC-13 | integration | tests/skills/test-aai-prompt-diet.sh | Existing TEST-012 with the bumped checkpoint and a new JUSTIFIED_ADDITIONS entry equal to the measured growth; layer-profiles TEST-001 green with ride-handoff.mjs classified core | `sed:s/ ride-state-handoff-to-worktree / renamed-scope /` on tests/skills/lib/prompt-diet-ledger.sh | green |
| TEST-014 | Spec-AC-13 | integration | tests/skills/test-aai-ride-handoff.sh | git diff --name-only main...HEAD contains none of the protected_paths_l3 entries read from docs/ai/docs-audit.yaml; the new suite has a suite-map row and the select-suites replay picks it for a change to ride-handoff.mjs | `sed:s/test-aai-ride-handoff/test-aai-ride-handoff-x/` on tests/skills/suite-map.yaml | green |

Test-file note: `tests/skills/test-aai-ride-handoff.sh` is the registered
suite (suite-map row, hygiene registration); it runs
`node --test tests/skills/lib/ride-handoff.test.mjs` as its first case and
holds TEST-012 and TEST-014. Node test names start with their spec TEST id.
New arms in `tests/skills/test-aai-merge-cleanup.sh` take the next free
suite-local ids and cite this spec's TEST-011 in a comment.

### RED observations and negative controls

Every row's RED is recorded before its GREEN in the named AC log. TEST-001 to
TEST-011 are RED on the baseline because the command or step does not exist;
each also gets its listed mutation applied in a scratch copy (never the
shipping tree, HAZ-SCRATCH and HAZ-RESTORE) through `mutation-run.mjs`.
TEST-005 additionally records its whole-copy negative control naming a
foreign ref on the baseline. Absence assertions (zero foreign ids, no archive
directory, no closed_focus_stale_state) each carry a positive control that the
producing step ran (the success line printed, the file's sha256 changed where
a change is expected).

## Verification

- `env -u AAI_ROLE bash tests/skills/test-aai-ride-handoff.sh` (includes the
  node:test file).
- `env -u AAI_ROLE bash tests/skills/<suite>.sh` for: test-aai-merge-cleanup,
  test-aai-state, test-aai-check-state, test-aai-worktree-seed,
  test-aai-worktree (known local environmental failure per LEARNED; compare
  against a base-ref disposable worktree), test-aai-prompt-diet,
  test-aai-layer-profiles, test-aai-hygiene-pack, test-aai-suite-select.
- The metrics-flush suite(s) that exist on the baseline, unchanged.
- `node .aai/scripts/check-vendored-script-deps.mjs` clean.
- `node .aai/scripts/spec-lint.mjs --path <this spec>` clean;
  `node .aai/scripts/docs-audit.mjs --strict` CLEAN.
- PASS criteria: all TEST-xxx green, all Spec-AC terminal.

## Evidence contract

Every artifact records ref `ride-state-handoff-to-worktree`, Spec-AC and
TEST ids, the actual command and exit code, the head SHA, and the evidence
path. RED and GREEN logs per AC live under
`docs/ai/tdd/ride-handoff-acNN.log`.

### Evidence by strategy

| Strategy | Evidence this spec may demand |
|---|---|
| tdd / hybrid | stored RED artifact per AC-gating test (docs/ai/tdd/) plus the full verification matrix |

Registry items closed by this scope: none. `follow-ups.mjs list` (2026-10-22)
carries no open item on worktree STATE carry, handoff or origin reconcile;
`fu-clearfocus-announces-unwritten-phase` concerns `state.mjs clear-focus`,
which this scope does not call or change.

Suggested follow-ups (not filed):
- suggested: fu-origin-append-run-after-handoff (R1, a state.mjs-side guard, L3).
