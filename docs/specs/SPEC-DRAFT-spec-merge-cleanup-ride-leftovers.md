---
id: spec-merge-cleanup-ride-leftovers
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: 48494616fb4589b5d381005a20092539f23bdd1079c6d2526be94a6145fc72c0
ceremony_level: 2
links:
  requirement: merge-cleanup-ride-leftovers
  rfc: null
  pr: []
  commits: []
---

# Spec — /aai-merge cleanup handles the ride's own leftovers instead of refusing

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/CHANGE-DRAFT-merge-cleanup-ride-leftovers.md (owner
  menu answer 2026-10-11 "Všechny tři v jedné jízdě (Recommended)")
- Engine: .aai/scripts/merge-cleanup.mjs (`LEDGERS`, `planSync`, `syncBase`,
  `resumeSync`, `worktreeVerdict`, `removeWorktree`, `PLANNERS`,
  `runApplyOrPlan`, `buildReport`, `renderReport`, `emit`, `mergedRefs`)
- Roadmap writer whose output this scope recognises: .aai/scripts/roadmap-edit.mjs
  (`cmdShipAppend`, `cmdAdvance`)
- Canon (not changed): .aai/SKILL_MERGE.prompt.md (the AAI_MERGE block launches
  `node "$AAI_ORIGIN/.aai/scripts/merge-cleanup.mjs" apply ...` from the main
  checkout), .aai/SKILL_SHIP.prompt.md step 1a (ship-append) and step 4
  (product docs)
- Product doc: docs/product/directed-merge-and-post-merge-cleanup.md (written
  by the ship step after the loop completes)
- Prior art: docs/specs/SPEC-0218-spec-directed-merge-and-post-merge-cleanup.md
  (D8 base sync, D11 resume), docs/specs/SPEC-0221-spec-merge-cleanup-submodule-worktree.md
  (late re-verify before the destructive call), docs/specs/SPEC-0222-spec-merge-cleanup-delete-remote-branch.md
  (step order, fixture helpers)
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, git CLI)

## Registry items closed by this scope

None. `node .aai/scripts/follow-ups.mjs list` at 6d12eb41 (173 open) holds no
item about the roadmap overlap, ride-worktree ledger appends or the engine
reload.

## Registry items assessed, not closed

- `fu-merge-pending-diverged-regression` (resume after a crash): this scope
  changes `resumeSync` only so that a non-ledger journal entry regenerates the
  index only when it IS the index (D4); the missing pending_diverged arms stay
  the item's own subject.
- `fu-merge-foreign-journal-archive-path` (`mergeLedgerTails` names the
  current PR's archive dir): not touched.
- `fu-ledger-merge-byte-prefix-edge` (ledger-merge.mjs byte-prefix test): this
  scope adds its own whole-line proof (D6) and does not change ledger-merge.mjs.

## Implementation strategy

- Strategy: tdd
- Rationale: autopilot default (intake: "Planning decides"). All three changes
  relax a refusal that today protects data: a roadmap edit, unpushed ledger
  lines and the worktree removal. Each relaxation is safe only through a
  predicate (ride-only roadmap hunk, byte-exact append-only proof, one-shot
  re-exec guard) that looks exactly like a wider one until a test is seen
  failing without it. Every Spec-AC gets a stored RED and a mutation that
  reddens it. STATE holds an intake-sourced strategy for
  `slowest-suite-hot-spots`; its ref_id differs, so it is stale and is replaced.

## Isolation and review

- Worktree recommendation: required
- Worktree rationale: PR-bound change to the destructive cleanup engine; the
  main checkout is shared with another session and is itself the object the
  engine rewrites. No `protected_paths_l3` surface.
- User decision: worktree (autopilot default, already recorded in STATE)
- Base ref: main 6d12eb41
- Worktree branch/path: change/merge-cleanup-ride-leftovers at
  /Users/ales/Projects/aai-change-merge-cleanup-ride-leftovers
- Inline review scope: .aai/scripts/merge-cleanup.mjs,
  tests/skills/test-aai-merge-cleanup.sh,
  docs/product/directed-merge-and-post-merge-cleanup.md, CHANGELOG.md,
  docs/issues/CHANGE-DRAFT-merge-cleanup-ride-leftovers.md,
  docs/specs/SPEC-DRAFT-spec-merge-cleanup-ride-leftovers.md,
  docs/ai/roadmap.yaml
- Code review required: true (engine and test change).

## Phasing

One ride, 6 Spec-ACs, 6 TEST rows. Expected three TDD dispatches:
(A) TEST-045, TEST-046 (roadmap); (B) TEST-047, TEST-048 (ledger tails);
(C) TEST-049, TEST-050 (engine reload); (D) TEST-051, TEST-052, TEST-053 (remediation rounds 1 and 2: the
tail resume key and report count, the re-exec child exit, the reset record and the done record per archive); then V1 to V5.

## Measured facts (scratch repos, git 2.54.0, node from PATH, 2026-10-11)

- F1 A tracked file in a linked worktree that differs from HEAD only by an
  appended line shows in `git status --porcelain -z` as ` M <path>` (index
  column blank, worktree column `M`).
- F2 `git worktree remove <path>` refuses that worktree
  (`contains modified or untracked files, use --force`); after the file is
  rewritten with its exact HEAD blob bytes, `git status --porcelain` is empty
  and a plain `git worktree remove` exits 0 (no `--force`).
- F3 `roadmap-edit.mjs ship-append --ref foo --intake <change-typed intake>`
  on `pairs: [earlier]` / `wave_2: [foo, later]` inserts exactly the two lines
  `  - capability: foo` and `    status: active` after the last pair block and
  deletes the `  - foo` line from `wave_2`. Its certification
  (`ride-select.mjs validate`) needs a document under `--docs` whose id
  matches every pair capability; an `issue`-typed intake is a named no-op
  (`MAINT_TYPES`).
- F4 The engine today: a dirty tracked file in the main checkout that the
  incoming range also changes and that is neither in `LEDGERS` nor
  `docs/INDEX.md` gives `REFUSE overlap <rel>` from `planSync` (exit 3, nothing
  written); any `git status --porcelain` output in the ride worktree gives
  `REFUSE worktree_dirty <path>` from `worktreeVerdict`; the engine module is
  loaded once per process, so a fast-forward that rewrites
  `.aai/scripts/merge-cleanup.mjs` takes effect only on the next process.

## Design decisions

### Roadmap overlap (intake scope 1)

- D1 The ride's identity is `mergedRefs(ctx)`: the frontmatter ids of the
  intake docs (any type but spec) that the merge commit added or changed with
  `status: done` and `links.pr` naming this PR (the same set the `state` and
  `sign-amendments` steps use). An empty set means no roadmap change is ever
  ride-only.
- D2 `stripRideEntries(text, refs)` is a pure line-based function over the
  closed roadmap shape (roadmap-edit.mjs header): it removes every pair block
  whose first line is exactly `  - capability: <ref>` with `<ref>` in `refs`
  (the block runs until the next line that is not indented by four spaces or
  more), and every line exactly `  - <ref>` with `<ref>` in `refs`
  (the `wave_2` entries ship-append deletes, F3). Comments and every other
  line stay. Line endings are kept.
- D3 `roadmapRideOnly(ctx, head, target)` is true only when ALL hold:
  - the main checkout's `docs/ai/roadmap.yaml` exists, is not staged
    (`git diff --cached` does not list it), and is readable;
  - `stripRideEntries(local) === stripRideEntries(HEAD blob)` (every local
    change is confined to the ride's own entries);
  - the incoming blob (`target:docs/ai/roadmap.yaml`) carries a pair block
    `  - capability: <ref>` for every ride ref whose block or `wave_2` line
    differs between the HEAD blob and the local file (taking the incoming file
    loses no record of the ride; A2).
  In `planSync`, a dirty `docs/ai/roadmap.yaml` that the incoming range also
  changes is added to `plan.roadmap` when the predicate holds and otherwise
  refuses `overlap docs/ai/roadmap.yaml` exactly as today. A dirty roadmap the
  incoming range does not change is left alone (unchanged behaviour).
- D4 `syncBase` treats `plan.roadmap` like the index: archive the local bytes
  with `archiveFile` (reason `pre_sync_local_state`, step `sync-base`,
  destination `sync/docs/ai/roadmap.yaml`), journal it in the pending file as
  a non-ledger entry, write the HEAD blob, fast-forward; after the
  fast-forward the file is the incoming blob and nothing is re-applied. The
  failed-fast-forward `restore` writes the local bytes back (same as the
  index). `resumeSync` regenerates the index after a completed fast-forward
  only when a journalled non-ledger entry is `docs/INDEX.md`
  (`entries.some((e) => e.rel === INDEX_PATH)`), never for the roadmap.
- D5 The `sync-base` planner adds the line
  `take incoming docs/ai/roadmap.yaml (archive ride entry <ref>[, <ref>])`
  when `plan.roadmap` holds; plan writes nothing.

### Ledger appends in the ride worktree (intake scope 2)

- D6 Append-only proof for one ride-worktree file `rel`:
  - `rel` is in the engine's `LEDGERS` list (`docs/ai/EVENTS.jsonl`,
    `docs/ai/decisions.jsonl`, `docs/ai/METRICS.jsonl`,
    `docs/ai/tests/test-runs.jsonl`); no second list is introduced;
  - its porcelain entry is exactly ` M` (F1): unstaged modification only;
  - `H` = `git cat-file blob HEAD:<rel>` in the worktree exists, and the
    working bytes `B` satisfy `B.length > H.length` and
    `B.subarray(0, H.length).equals(H)` (byte-exact prefix);
  - `H` is empty or ends with `\n`, and the tail `T = B.subarray(H.length)`
    ends with `\n` (whole lines only).
  The anchor line is `const appendOnly = ` (the conjunction of the prefix and
  whole-line tests).
- D7 `worktreeVerdict(ctx, wt, { allowTails })`: with `allowTails` true, a
  worktree whose every porcelain entry passes D6 is clean; any other entry
  (another modified file, a staged change, an untracked non-ignored file, a
  non-append ledger edit, a partial last line) still returns
  `['worktree_dirty', wt.path]`. `planChecks` and the first check in
  `removeWorktree` pass `allowTails: true`; the late re-verify right before
  `git worktree remove` passes `allowTails: false` (strict), so lines appended
  after the move stop the run with `worktree_dirty` (exit 4) instead of
  reaching a `--force` removal; a re-run moves them.
- D8 `moveLedgerTails(ctx, wt)` runs in `removeWorktree` after the first
  verdict and before the submodule archives. Per qualifying ledger, in
  `LEDGERS` order:
  1. archive `T` with `archiveFile` (source a temporary file holding exactly
     `T`; destination `worktree-ledger-tails/<rel>` under the PR archive
     root; original `worktree:<rel>`; reason `ride_ledger_tail`; step
     `remove-worktree`);
  2. `already` = the longest candidate among the earlier archives that carry
     an append-intent record (below) for this ledger and are a byte prefix of
     `T` and occur in the main checkout's ledger at a line start (offset 0 or
     preceded by `\n`) at or after the ledger length that intent recorded
     (`mainLen`). `T`'s own archive has no intent yet, so a first run appends
     all of `T`, a line that is already in the ledger included. Right before
     the append the engine journals `{ step: 'ledger-append', status:
     'intent', ledger, archive, sha256, mainLen, lines }` (`lines` = the lines
     of the segment about to be appended) and passes
     `crashAt('ledger-move-after-intent')`; then it appends
     `T.subarray(already)` to the main checkout's `<rel>` (created with its
     directory when absent). A non-empty main ledger that does not end with
     `\n` stops with `ledger_unaligned <rel>` (exit 4) before any byte is
     appended to it;
  3. `crashAt('ledger-move-after-append')`, then the journal record `{ step:
     'ledger-append', status: 'done', ledger, archive, sha256, lines }`. A
     satisfied intent whose done record a crash lost gets it on the re-run, so
     every completed append has exactly one done record. A crash between the
     intent and the append leaves an intent the content test does not find
     (nothing appended, so the re-run appends the segment once); a crash after
     the append leaves one it finds (the re-run appends nothing more);
  4. compare-then-write: when the worktree file still equals `B`, write `H`
     to it; otherwise stop `worktree_dirty <rel> changed during the move`
     (exit 4);
  5. after that write, the journal record `{ step: 'ledger-append', status:
     'reset', ledger, archive }`. A reset record retires every earlier intent
     of the ledger: its bytes were moved and the ride file rewritten, so a
     later ride tail identical to it is new content and is appended, never
     skipped as already moved (the resume test reads only the intents after
     the last reset record). Each archive gets one done record per append, a
     second intent for the same archive included.
  The archive, the intent and the done record make a re-run after a crash at
  any point idempotent: no tail byte is appended twice and none is lost. A
  hand-copied tail with no intent is appended again (a visible duplicate in an
  append-only ledger, never a silent loss). The residual false skip needs a
  crash, a re-run and a byte-identical block at or after `mainLen` that
  another writer put there. A main ledger rewritten shorter between a crash
  and the re-run, with the tail kept in it, gets the tail appended again (a
  visible duplicate, not a loss). A crash between the step 4 write and the
  step 5 reset record leaves that intent live: a later ride tail identical to
  the tail just moved (or to its first lines) is then skipped as already
  moved, and the skipped copy survives only in the archive; new lines after
  it are still appended once.
- D9 `planChecks` also refuses `ledger_unaligned <rel>` (exit 3, nothing
  written) when a qualifying ledger's main-checkout copy is non-empty and does
  not end with `\n` at plan time.
- D10 Report: a durable `moved` list derived from the journal's `ledger-append`
  `done` records, one entry per ledger (JSON `moved: [{ ledger, lines, sha256,
  archive }]`, `lines` = the sum of the `lines` of that ledger's done records,
  one per archive, i.e. the lines actually appended, never the lines of a tail
  a resume found already moved); the text output prints
  `  moved <n> line(s) worktree:<rel> -> <rel>` per entry; the saved report
  gains a `## Moved ledger lines` section (`- none` when empty). The
  `remove-worktree` step detail stays the worktree path. The
  `remove-worktree` planner adds `move <n> line(s) worktree:<rel> -> <rel>`
  per qualifying ledger.

### Engine replaced by the merge (intake scope 3)

- D11 At startup the engine records `ENGINE_FILE` (the realpath of
  `fileURLToPath(import.meta.url)`) and `ENGINE_STARTUP_SHA` (sha256 of the
  bytes read from it once, at module load).
- D12 `reexecIfReplaced(ctx)` runs in apply mode right after the
  `sync-base` step's journal write and its `STOP_AFTER` check, whatever the
  step's status. It returns without effect when the guard variable
  `REEXEC_ENV` (`AAI_MERGE_CLEANUP_REEXECED`) is set to any non-empty value
  (`if (process.env[REEXEC_ENV]) return null;`), when `ENGINE_FILE` is not
  inside `ctx.origin` (a sync cannot have replaced it), or when the on-disk
  sha256 equals `ENGINE_STARTUP_SHA`. Otherwise it appends one journal record
  `{ step: 'reexec', status: 'done', detail: '<old12> -> <new12>' }`, writes
  one stderr line `merge-cleanup: engine replaced by sync-base (<old12> ->
  <new12>); re-executing once`, and runs
  `spawnSync(process.execPath, [...process.execArgv, ENGINE_FILE, ...process.argv.slice(2)],
  { stdio: ['inherit', 'pipe', 'inherit'], env: { ...process.env, [REEXEC_ENV]: ENGINE_STARTUP_SHA } })`
  with the unchanged working directory (stdout piped, stderr inherited). The
  child's exit `0` or `4` passes through with its stdout forwarded. Any other
  outcome, a status such as `1` (a merged engine that does not load) or `3`
  (a refusal that, after the parent's writes, canon would read as "nothing
  written"), or a signal, prints one `STOPPED reexec_child_exit_<n|signal>`
  line on stdout, sends the child's held stdout to stderr and exits `4`;
  `stop('reexec_failed', ...)` on a spawn error. The parent writes nothing to
  stdout before the child, so `--json` stays one JSON document (the stop
  line is the engine's only stopped shape).
- D13 The guard is honoured in production (not a test seam): a stray value
  can only suppress a re-exec, which is today's behaviour.
- D14 The re-executed run starts from the top (gh read, gate, plan checks);
  every step the parent completed is a noop by the existing idempotency
  (archives deduplicated, drafts gone, `sync-base` `already_at_target`). When
  `REEXEC_ENV` holds a 64-hex value that differs from its own startup sha, the
  child inserts the synthetic step
  `{ id: 'reload-engine', status: 'done', detail: 'engine <old12> -> <new12> after sync-base' }`
  right after `sync-base` in its steps (journalled like any done step, so the
  child saves a report); `reload-engine` is not in `STEP_IDS`, so
  `STOP_AFTER` cannot name it. Inherited test seams (`STOP_AFTER`,
  `CRASH_AT`) apply to the child, which is how an interrupted re-exec is
  produced; the next apply loads the new engine from disk and needs no
  re-exec.

## Implementation anchors (the mutation rows depend on these spellings)

- `const ROADMAP_PATH = 'docs/ai/roadmap.yaml';`
- `function stripRideEntries(text, refs) {` (D2)
- `function roadmapRideOnly(ctx, head, target) {` (D3)
- `const appendOnly = ` (D6)
- `function moveLedgerTails(ctx, wt) {` (D8) and `crashAt('ledger-move-after-append')`
- `const REEXEC_ENV = 'AAI_MERGE_CLEANUP_REEXECED';`
- `function reexecIfReplaced(ctx) {` (D12) containing
  `if (process.env[REEXEC_ENV]) return null;`
- STEP_IDS keeps the literal sequence `'delete-remote-branch', 'report',` and
  HANDLERS keeps `'delete-remote-branch': deleteRemoteBranch,` (the fixture
  variant engine of TEST-049 and TEST-050 is generated by replacing them).

## Seams

- S1 roadmap-edit.mjs ship-append to sync-base: TEST-045 produces the main
  checkout's local entry with the real `roadmap-edit.mjs ship-append` (F3:
  a change-typed scratch intake with id `foo`, `--roadmap` and `--docs` of
  the origin, every other pair backed by a doc), never with a hand-written
  imitation; the incoming side carries the block as close-work-item's advance
  leaves it (`status: done`).
- S2 Ride worktree ledger to main checkout ledger: TEST-047 asserts on the
  main checkout's file bytes (`tail -c <len>` compared with the appended
  bytes) and on the archived tail file, never on the report alone.
- S3 Engine to `git worktree remove`: the strict late verdict (D7) is checked
  through the real removal: TEST-048's late arm asserts the worktree still
  exists and still holds the late line.
- S4 Old engine process to new engine file: TEST-049 and TEST-050 run the
  engine from a tracked copy inside the fixture origin, so the real
  fast-forward replaces the very file the parent was loaded from; the variant
  is generated at test time from the engine under test, so a mutation of the
  engine is present in both parent and child.
- S5 Report to owner: the JSON `moved` list, the text `moved` lines, the
  saved report section and the `reload-engine` step are the only channel to
  the owner; TEST-047 and TEST-049 assert them.

## Acceptance Criteria Mapping

- Intake AC-001 (ride-only hunk archived, incoming taken) -> Spec-AC-01;
  (foreign or mixed hunk refuses, nothing written, widening mutation) ->
  Spec-AC-02.
- Intake AC-002 (appends moved byte-exact, archived, worktree removed) ->
  Spec-AC-03; (non-append edit, other file, untracked refuse, mutation) ->
  Spec-AC-04.
- Intake AC-003 (marker step in one run, re-run noop) -> Spec-AC-05;
  (exactly one re-exec, interrupted re-exec resumes, guard mutation) ->
  Spec-AC-06.
- Remediation round 1 (additive, disclosed by spec_amendment records): validation NB-1 and
  review findings 1 and 2 (the tail resume key and the moved count) -> Spec-AC-07;
  validation NB-2 and review finding 3 (the re-exec child exit) -> Spec-AC-08.
- Existing test changed by this scope, disclosed (review finding 5): TEST-004's dirty-ride
  signal is now a README edit instead of an appended ledger line, because an appended ledger
  line is the very ride leftover that this scope moves instead of refusing. TEST-004's
  assertions (apply on the dirty ride exits 3, the recorded direction survives) are unchanged.
- Intake AC-004: the regression half (existing merge-cleanup tests and Pester
  parity stay green) is the PASS criterion of V1 and V3 for every Spec-AC. The
  docs half (product doc and CHANGELOG describe the three behaviours) is the
  ship step 4 deliverable, written after the loop completes by canon
  (.aai/SKILL_SHIP.prompt.md step 4), so it has no Spec-AC: a suite test on
  it would be red during the loop's own validation. It is checked by V5 at the
  PR ceremony.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN the main checkout's docs/ai/roadmap.yaml differs from HEAD only by the merged ride's own entry (written by the real roadmap-edit.mjs ship-append, incl. its wave_2 removal) and the merged PR carries that capability, the system SHALL exit 0 from apply, SHALL leave roadmap.yaml byte-equal to the merge commit's blob, SHALL record a manifest entry original docs/ai/roadmap.yaml reason pre_sync_local_state whose archived bytes equal the pre-apply local file, and plan SHALL list take incoming docs/ai/roadmap.yaml naming ref foo with the world digest unchanged; WHEN the run is killed at sync-after-rewrite a re-run SHALL exit 0 with the same end state. | planned | — | — | D1 to D5; seam S1 |
| Spec-AC-02 | WHEN the local roadmap change touches another entry (foreign), touches the ride entry and another entry (mixed), is staged, or adds the ride entry while the incoming roadmap carries no block for it, apply SHALL exit 3 with REFUSE overlap docs/ai/roadmap.yaml and SHALL leave the world digest, stash list and reflog unchanged with no archive directory created. | planned | — | — | D3 |
| Spec-AC-03 | WHEN the ride worktree differs from HEAD only by whole appended lines in docs/ai/tests/test-runs.jsonl and docs/ai/EVENTS.jsonl, apply SHALL exit 0 with remove-worktree done and the worktree gone, the main checkout's two ledgers SHALL end with exactly the appended bytes, the manifest SHALL hold one ride_ledger_tail entry per ledger whose archived file equals the tail, the JSON moved list, the text moved lines and the saved report section SHALL name both ledgers with their line counts, and plan SHALL list both moves with the world digest unchanged; WHEN the run is killed at ledger-move-after-append a re-run SHALL exit 0 and every moved line SHALL occur exactly once in the main checkout's ledger. | planned | — | — | D6 to D10; seams S2, S5 |
| Spec-AC-04 | WHEN a ride ledger is edited other than by appending, when its tail lacks a final newline, when the append is staged, or when an append is accompanied by another modified file or an untracked file, apply SHALL exit 3 with REFUSE worktree_dirty and the world digest unchanged; WHEN a line is appended to a ride ledger after the move and before the late re-verify (TOUCH_AT seam), apply SHALL exit 4 with worktree_dirty, the worktree SHALL still exist holding that line, and a re-run SHALL exit 0 with that line present exactly once in the main checkout's ledger. | planned | — | — | D6, D7, D8; seam S3 |
| Spec-AC-05 | WHEN the merged PR changes the tracked engine file the apply process was loaded from (fixture variant with an extra fixture-marker step), one apply run SHALL exit 0, SHALL report the fixture-marker step done and a reload-engine step done naming both sha prefixes, SHALL print one re-executing line on stderr and one JSON document on stdout, and SHALL journal exactly one reexec record; a second apply SHALL exit 0 with no reload-engine step, every action step noop and the world digest unchanged; a merged PR that leaves the engine unchanged SHALL produce no reload-engine step. | planned | — | — | D11 to D14; seams S4, S5 |
| Spec-AC-06 | WHEN the re-executed engine finds its own file changed again during its run (self-touching fixture variant), the system SHALL NOT re-execute a second time: apply SHALL exit 0 and the variant SHALL have been loaded exactly once; WHEN the re-executed run is stopped after the state step (STOP_AFTER seam), apply SHALL exit 4 and a re-run SHALL exit 0 with the fixture-marker step run exactly once overall. | planned | — | — | D12, D13, D14; seam S4 |
| Spec-AC-07 | WHEN a ride ledger tail holds a line byte-identical to one already in the main checkout's ledger, a first apply SHALL append the whole tail byte-exact (the line occurs twice) and the moved list SHALL count it; WHEN the run is killed at ledger-move-after-intent a re-run SHALL append the tail exactly once; WHEN it is killed at ledger-move-after-append a re-run SHALL append nothing more, and in every case the moved list SHALL hold one entry per ledger whose lines equal the lines actually appended, a later late line included. | planned | — | — | D8, D10; remediation r1 (validation NB-1, review finding 1 and 2) |
| Spec-AC-08 | WHEN the re-executed engine exits with a status other than 0 or 4 (a refusal status 3, a merged engine that does not load, or a signal), apply SHALL print one STOPPED reexec_child_exit_ line naming the status or signal as the only stdout line and exit 4; WHEN the child exits 4 on its own stop its output SHALL pass through unchanged. | planned | — | — | D12; remediation r1 (validation NB-2, review finding 3) |
| Spec-AC-09 | WHEN a ride ledger tail is identical to one already moved and the ride file was reset after that move, a re-run SHALL append the later tail again (main holds the line once per write, nothing lost) and the moved list SHALL count both; WHEN several intent records exist for one archive, the journal SHALL hold exactly one done record for that append. | planned | — | — | D8, D10; remediation r2 (validation NB-r2-1 and NB-r2-3) |

## Implementation plan

- .aai/scripts/merge-cleanup.mjs:
  - `ROADMAP_PATH`, `stripRideEntries`, `roadmapRideOnly`; `planSync` gains
    `plan.roadmap`; `syncBase` archives/journals/rewrites it like the index;
    `resumeSync` keys `regenIndex` on `INDEX_PATH`; the `sync-base` planner
    line (D1 to D5).
  - `ledgerTails(ctx, wt)` (pure: porcelain parse plus D6 proof, returns the
    qualifying tails or null), `worktreeVerdict` option `allowTails`,
    `moveLedgerTails`, the `ledger_unaligned` plan check, the
    `remove-worktree` planner lines, `moved` in `buildReport`, `emit` and
    `renderReport` (D6 to D10).
  - `ENGINE_FILE`, `ENGINE_STARTUP_SHA`, `REEXEC_ENV`, `reexecIfReplaced`, the
    `reload-engine` synthetic step in `runApplyOrPlan`; header comment and HELP
    name the three behaviours (D11 to D14); HELP names them in a "the ride's
    own leftovers" paragraph (added in remediation round 1).
- tests/skills/test-aai-merge-cleanup.sh: functions `test_045_*` to
  `test_050_*`, selector cases, the default run order and the header line;
  fixture options in `build_world` (a tracked `docs/ai/roadmap.yaml` with a
  doc for every pair; a tracked `docs/ai/tests/test-runs.jsonl`; a tracked
  engine copy for S4, e.g. `DOWNSTREAM=1` plus `git add -f
  .aai/scripts/merge-cleanup.mjs` before the ride worktree is created), and a
  variant generator (node with function replacements, never string
  replacements containing `$`) that inserts `'fixture-marker'` into
  `STEP_IDS` and a `fixtureMarker` handler (idempotent: noop when its marker
  file exists) plus optional load-count and self-touch lines driven by
  fixture environment variables; the generator asserts that each replacement
  happened (positive control). New code is verified under the suite's own
  `set -euo pipefail` (no bare `rc=$?`, no `grep | head`).
- docs/product/directed-merge-and-post-merge-cleanup.md and a CHANGELOG
  `## [unreleased] — <title>` entry ending `(merge-cleanup-ride-leftovers)`,
  written by the ship step after the loop completes (V5).
- No prompt changes: .aai/SKILL_MERGE.prompt.md and the Pester twin
  tests/skills/aai-merge-cleanup.Tests.ps1 keep their wrapper surface, so no
  prompt-diet ledger entry, TEST-012 pin or want_growth term, and no new
  `.aai/**` file (no PROFILES.yaml entry).
- Edge cases: a roadmap with CRLF line endings (strip compares lines with
  their endings; a mixed-ending local edit is not ride-only); a ride ref that
  is also a `maintenance:` half of another pair (not stripped, so overlap); a
  ledger present in the ride but absent from the main checkout (created by the
  move); an engine run from outside the origin (no re-exec); a merged engine
  that fails to load (the child's exit code is propagated, a re-run runs the
  same engine).

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-045 | Spec-AC-01 | integration | tests/skills/test-aai-merge-cleanup.sh | test_045_ride_roadmap_entry_taken_from_incoming: roadmap world (pairs other-item done, wave_2 foo and later); main checkout runs the real roadmap-edit ship-append for foo; the ride commit carries the foo block with status done and the wave_2 removal; plan exits 0 with the take incoming line naming foo and an equal world digest; apply exits 0, roadmap.yaml equals git show MC:docs/ai/roadmap.yaml, the manifest names docs/ai/roadmap.yaml pre_sync_local_state and the archived file equals the saved local bytes; arm crash: CRASH_AT sync-after-rewrite exits 137, a re-run exits 0 with the same end state | sed:s/function stripRideEntries\(text, refs\) \{/function stripRideEntries(text, refs) { return text;/ | green |
| TEST-046 | Spec-AC-02 | integration | tests/skills/test-aai-merge-cleanup.sh | test_046_foreign_roadmap_hunk_refuses_overlap: refuse_arm overlap docs/ai/roadmap.yaml for arm foreign (status of other-item edited locally), arm mixed (ship-append for foo plus the other-item edit), arm staged (ride-only change staged with git add), arm incoming-lacks-entry (the PR changes roadmap.yaml elsewhere but carries no foo block); positive control: the ride-only world of TEST-045 is not refused | sed:s/function roadmapRideOnly\(ctx, head, target\) \{/function roadmapRideOnly(ctx, head, target) { return true;/ | green |
| TEST-047 | Spec-AC-03 | integration | tests/skills/test-aai-merge-cleanup.sh | test_047_ride_ledger_appends_moved: ledger world (test-runs.jsonl tracked); one line appended to the ride's test-runs.jsonl and two to its EVENTS.jsonl after the last commit; plan lists both moves, world digest equal; apply exits 0, remove-worktree done, worktree gone, tail -c of each main ledger equals the appended bytes, the manifest holds two ride_ledger_tail entries whose archives equal the tails, JSON moved names both ledgers with lines 1 and 2, the text run of a fresh world prints both moved lines, the saved report has the Moved ledger lines section; arm crash: CRASH_AT ledger-move-after-append exits 137, a re-run exits 0 and count_line of each moved line in the main ledger is 1 | sed:s/function moveLedgerTails\(ctx, wt\) \{/function moveLedgerTails(ctx, wt) { return [];/ | green |
| TEST-048 | Spec-AC-04 | integration | tests/skills/test-aai-merge-cleanup.sh | test_048_non_append_ledger_change_refused: refuse_arm worktree_dirty for arm rewrite (first ledger line replaced in the ride), arm partial (tail without a final newline), arm staged (append then git add), arm plus-file (append plus a modified README.md), arm plus-untracked (append plus stray.txt); each arm: the worktree and branch still exist; arm late: TOUCH_AT before-remove-verify appends to the ride's test-runs.jsonl, apply exits 4 with worktree_dirty, the worktree exists and holds the late line, a re-run exits 0 and the late line occurs once in the main ledger | sed:s/const appendOnly = [^;]*;/const appendOnly = true;/ | green |
| TEST-049 | Spec-AC-05 | integration | tests/skills/test-aai-merge-cleanup.sh | test_049_merged_engine_runs_in_the_same_apply: engine world (tracked engine copy in the origin; the ride commit replaces it with the generated fixture-marker variant); apply --json run from the origin's engine exits 0, stdout parses as one JSON document, steps contain fixture-marker done and reload-engine done whose detail names the first 12 hex of both shas, stderr has exactly one re-executing line, the journal has exactly one reexec record, the marker file has one line; a second apply exits 0 with no reload-engine step, every action step noop, fixture-marker noop and an equal world digest; control: the plain build_world apply reports no reload-engine step | sed:s/function reexecIfReplaced\(ctx\) \{/function reexecIfReplaced(ctx) { return null;/ | green |
| TEST-050 | Spec-AC-06 | integration | tests/skills/test-aai-merge-cleanup.sh | test_050_reexec_runs_once_and_resumes: arm guard: the variant appends a comment to its own file at load and logs each load to a fixture file, refusing with exit 99 on a third load; apply exits 0 and the load log has exactly one variant line; arm interrupted: STOP_AFTER state with test seams, apply exits 4 after the child stopped, a re-run without seams exits 0 with fixture-marker done, no reload-engine step, and the marker file has one line | sed:s/if \(process\.env\[REEXEC_ENV\]\) return null;/if (false) return null;/ | green |
| TEST-051 | Spec-AC-07 | integration | tests/skills/test-aai-merge-cleanup.sh | test_051_ledger_tail_resume_key_and_count: ledger world; arm dup: the ride appends the seed line the main test-runs.jsonl already holds, apply appends it (count 2), tail -c equals the tail, JSON moved lines for test-runs is 1; arm late: CRASH_AT ledger-move-after-append, a late line appended in the ride, the re-run moves each line once and JSON moved holds one EVENTS entry of 3 lines; arm intent: CRASH_AT ledger-move-after-intent exits 137 with the duplicate not yet appended, the re-run appends it once (count 2) and moved is 1; arm after: crash after the append of the duplicate, the re-run appends nothing more (count 2) and moved is 1 | sed:s/for \(const r of readJsonl\(journal\)\) \{/for (const r of []) {/ | green |
| TEST-052 | Spec-AC-08 | integration | tests/skills/test-aai-merge-cleanup.sh | test_052_reexec_child_exit_is_mapped: engine world with the generated variant; arm exit3: the variant prints REFUSE and exits 3 at load, apply exits 4 and stdout is exactly one STOPPED reexec_child_exit_3 line; arm sig: the variant kills itself with SIGKILL, stdout is one STOPPED reexec_child_exit_SIGKILL line; arm syntax: the variant has a syntax error appended, stdout is one STOPPED reexec_child_exit_1 line; control: STOP_AFTER state in the child exits 4 with no reexec_child_exit line | sed:s/if \(r\.status === 0 [^)]*\) \{/if (true) {/ | green |
| TEST-053 | Spec-AC-09 | integration | tests/skills/test-aai-merge-cleanup.sh | test_053_reset_ride_ledger_is_not_a_resume_candidate: ledger world; arm ident: a late line is appended in the ride, TOUCH_AT before-remove-verify appends the byte-identical line again, apply stops with exit 4, the re-run exits 0 and main holds the line twice and the moved list counts 2; arm dint: three crashes (two at intent, one after the append) then a re-run, the duplicate line is in main twice (once appended), the journal holds one done record and moved is 1 | sed:s/else if \(r\.status === 'reset'\) \{ open = \[\]; doneArchives\.clear\(\); \}// | green |

Mutation target: .aai/scripts/merge-cleanup.mjs for every row. The intake's
"mutation that widens the predicate" is TEST-046's row (roadmap) and
TEST-048's row (ledger); "drops the loop guard or the re-exec" is TEST-050's
and TEST-049's row respectively.

## Verification

- V1: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-merge-cleanup.sh`
  exits 0 (TEST-001 to TEST-053 in the default order). Single test: append the
  function name or `TEST-0xx`.
- V2: `node .aai/scripts/mutation-run.mjs` per Test Plan row on the engine,
  then `node .aai/scripts/mutation-gate.mjs` at close.
- V3 regression: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-merge-cleanup.sh TEST-016`
  (Pester twin under local pwsh) exits 0; the suites
  `node .aai/scripts/select-suites.mjs` picks for the changed paths, through
  the wrapper; `node .aai/scripts/docs-audit.mjs --check --strict`.
- V4 lint: `node .aai/scripts/spec-lint.mjs --path <this spec>`.
- V5 (PR ceremony, after ship step 4): `/usr/bin/grep -c 'merge-cleanup-ride-leftovers' CHANGELOG.md`
  is at least 1 on a `## [unreleased] — ` heading, and the product doc names
  the roadmap entry, the moved ledger lines and the engine reload
  (`/usr/bin/grep -c -e roadmap.yaml -e 'ledger lines' -e reload-engine docs/product/directed-merge-and-post-merge-cleanup.md`
  is at least 3).

PASS criteria: every TEST row green with a stored RED and a mutation record,
every Spec-AC terminal, V1 to V4 exit 0; V5 before the PR opens.

## Evidence contract

Every artifact records ref_id `merge-cleanup-ride-leftovers`, the Spec-AC and
TEST ids, the exact command, exit code, log path and diff or commit identity.
TDD stores RED per AC-gating test, GREEN output and one mutation record per
row under `docs/ai/tdd/spec-merge-cleanup-ride-leftovers/`. Validation
repeats V1 to V4 independently and re-measures F1 to F3 on its own scratch
repos (D6 to D8 rest on them). The Validation report carries an admissible
aai-outcome-v1 block, and its path is the `set-validation --evidence` value.

### Evidence by strategy

Strategy `tdd`: stored RED artifact per AC-gating test under docs/ai/tdd/
plus the full verification matrix V1 to V4.

## Residual risks

- R1 Only the engine file itself triggers the re-exec. A merged PR that
  changes only a module the engine imports (`lib/cli-pipe-guard.mjs`,
  `lib/session-lock.mjs`, `lib/docs-model.mjs`) keeps the old module for the
  rest of that run; spawned helpers (state.mjs, ledger-merge.mjs,
  generate-docs-index.mjs, docs-audit.mjs, spec-amend.mjs, follow-ups.mjs) are
  separate processes and already load the merged code.
- R2 A downstream install gitignores `.aai/`, so a merge never replaces the
  engine there and D12 never fires; the behaviour matters in a repository
  that tracks `.aai/` (this one).
- R3 The re-executed run's report shows the parent's steps as noops; their
  done records stay in the journal and their archives in the manifest (and
  so in the report's archived list).
- R4 The compare-then-write in D8 has a window between the last read and the
  write; a concurrent writer is already refused by the session lock proof.
- R5 Hand-copied lines (the incident's manual move) carry no intent record, so
  they are appended again (a visible duplicate in an append-only ledger, never
  a silent loss), as D8 states.

## Assumptions (autopilot, recorded instead of questions)

- A1 The roadmap archive keeps the intake's reason `pre_sync_local_state`
  (no new reason name) so existing report readers stay valid.
- A2 Taking the incoming roadmap requires the incoming file to carry the
  ride's pair block; otherwise the local entry would be the only record and
  the run refuses `overlap` as today (fail closed).
- A3 Lines appended to the main checkout's ledgers by the move stay
  uncommitted (intake out-of-scope line).
- A4 The `reload-engine` and `reexec` names are new report/journal vocabulary;
  no existing reader keys on them.
