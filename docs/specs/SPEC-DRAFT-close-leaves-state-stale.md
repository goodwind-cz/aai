---
id: spec-close-leaves-state-stale
type: spec
number: null
status: implementing
ceremony_level: 2
links:
  requirement: close-leaves-state-stale
  rfc: null
  pr: []
  commits: []
---

# Spec — the close ceremony reconciles STATE, and the dispatcher never plans a closed scope

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/ISSUE-DRAFT-close-leaves-state-stale.md
- Decision records: none new (design decisions D1-D8 recorded in this spec)
- Technology contract: docs/TECHNOLOGY.md

## Problem in one paragraph

`close-work-item.mjs` is the deterministic close ceremony: it flips document
frontmatter, stamps links, emits the close event set, and self-verifies against
the real docs-audit engine with total rollback on drift. It never touches
`docs/ai/STATE.yaml`. So the moment a ride closes, STATE still describes the
finished scope as in-flight — `active_work_items[ref].status: in_progress`, and
`current_focus.primary_path` / `spec_path` still naming the pre-allocation
`*-DRAFT-*` files the allocator renamed during the PR step. On the next
orchestration tick `orchestration-dispatch.mjs` reads that STATE, computes
`close_event_present: true` for the focus ref — and then rule 5 (spec file
missing) or rule 6 (spec frontmatter status not draft/implementing) dispatches
Planning onto the scope the very same snapshot reports as closed. Rule 4b, the
arm that exists for exactly this state, cannot fire because it requires the
work item to be `done`. Registry `fu-dispatch-targets-closed-scope` (P2) records
the 2026-08-14 instance (four hand edits); the CHANGE-0165 ride on 2026-08-24/25
paid three stumbles in one tick sequence. This scope wires the truth the two
scripts already hold into the two places that ignore it.

## The decisions

### D1 — the reconcile is a first-class step of the close ceremony, not a caller's chore

`close-work-item.mjs` gains ONE new responsibility: after its self-verify audit
passes, reconcile `docs/ai/STATE.yaml` so it stops describing the just-closed
scope as in-flight. Three fields, all reachable through the sanctioned CLI:

- `active_work_items[<ref>].status` -> `done`
- `active_work_items[<ref>].primary_path` / `.spec_path` -> the paths of the
  documents this very run just resolved on disk (`resolveDoc`'s `rel`), which
  are by construction the post-allocation numbered files
- `current_focus.primary_path` / `.spec_path` -> the same paths, and only when
  `current_focus.ref_id` names this scope

### D2 — the CLI surface suffices; nothing needs the engine API to WRITE

Measured against `.aai/scripts/state.mjs` (protected, never edited):

- `set-phase --ref <r> --phase <p> --status done --path <primary> --spec-path <spec>`
  writes all three work-item fields in one atomic call. `--phase` is REQUIRED by
  the CLI, so the reconcile must READ the item's existing phase and pass it back
  unchanged — it never invents a phase.
- `set-focus --type <t> --ref <r> --path <primary> --spec-path <spec>` writes the
  focus fields. `--type` is REQUIRED, so the existing `current_focus.type` is
  likewise read and passed back unchanged.

Reading those two values is the only gap, and it is a READ. It is served by
importing `loadState` / `findBlock` / `readScalar` / `unquoteScalar` from
`.aai/scripts/lib/state-engine.mjs` — using the protected module, not editing
it, exactly as `metrics-flush.mjs` and `orchestration-dispatch.mjs` already do.
No STOP-and-report condition is reached: every field the intake demands is
writable through the existing subcommands.

### D3 — the transaction shape: named partial, never rollback, never a raw STATE write

Article 6 of docs/CONSTITUTION.md gives `docs/ai/STATE.yaml` exactly one writer,
`state.mjs`. A whole-transaction rollback of the reconcile would mean
`close-work-item.mjs` writing STATE bytes itself. The intake permits the other
arm — "roll back whole OR leave a named, detectable partial state, never a
silent half-close" — so this spec takes it, and Article 6 stays intact:

- The reconcile runs STRICTLY AFTER the existing self-verify passes, i.e. after
  the point where the close is already durable and audited CLEAN. It is
  therefore OUTSIDE the existing `try` block, and a reconcile failure NEVER
  triggers `rollback()`. The doc/event transaction's own snapshot, apply,
  self-verify and rollback behavior is byte-unchanged.
- Nothing-written failures (STATE absent, unreadable, a shape the sanctioned
  CLI cannot express, the R-GUARD refusal of D4, or the FIRST command failing)
  are a NAMED SKIP: one `close-work-item: WARN (state-reconcile) — <reason>`
  line on stderr that echoes the exact `state.mjs` commands an operator or the
  orchestrator must run, and exit 0. The close is correct; the bookkeeping is
  reported as not done. This is the Article 4 degrade-and-report arm.
- A genuine mid-apply partial (command 1 succeeded, command 2 failed) is the one
  case where our own action left STATE half-written. It gets a NEW exit code 6,
  a `close-work-item: PARTIAL (state-reconcile)` stderr block naming how many of
  how many commands applied and echoing the remaining ones verbatim. Exit 6 is
  additive: exits 3/4/5 were added the same way and `.aai/SKILL_PR.prompt.md`
  enumerates only 0/1/2, so no prompt file changes.

### D4 — the single-writer marker is honored, never stripped

`state.mjs` refuses every mutator with exit 3 under `AAI_ROLE=subagent`
(SPEC-0113 R-GUARD). `close-work-item.mjs` MUST NOT unset or filter that marker
out of the child environment — defeating the guardrail is worse than a stale
STATE. Under the marker the reconcile is a D3 named skip whose WARN line names
the R-GUARD as the reason and prints the commands, which is precisely the
`state_update_commands` shape the orchestrator already knows how to execute.

### D5 — the reconcile is scoped, and never hijacks a foreign focus

The work-item arm fires only when `active_work_items` contains an item whose
`ref_id` is in this close's identity set (the primary doc's frontmatter `fmId`
plus its display `fileIds` — the same two-pass identity `resolveDoc` uses, so a
STATE keyed on `ISSUE-0031` and a close keyed on the slug still meet). The focus
arm fires only when `current_focus.ref_id` is in that same set. A close for a
ref STATE does not name is a clean no-op. The `--ref` passed to `set-phase` is
the ref string STATE itself holds, verbatim, because the CLI locates the item by
exact `ref_id` match. `--spec-path` is written only when `--spec` was given: with
no spec argument this ceremony has no authority over that field and leaves it.

### D6 — which STATE: the one at the close's own root

`docs/ai/STATE.yaml` at `process.cwd()` — the same file this script's two
existing STATE readers (`countRemediationRuns`, `scanAgentRuns`) already read.
One convention, no fork. `.aai/SKILL_PR.prompt.md` step 5c can run the close
from a linked worktree, whose STATE is a different, gitignored file from the
main checkout's; when `resolveEvidenceRoot(ROOT) !== ROOT` the reconcile emits an
advisory naming which STATE it wrote and that the main checkout's is untouched.
Writing into another checkout is deliberately NOT done: it is a cross-checkout
write into a file whose single-writer discipline is prompt-level. The residual
is bounded by D7 — a stale main-checkout STATE can no longer produce a wrong
dispatch, only a flagged halt.

### D7 — the dispatcher guard constrains rules 5 and 6, and reorders nothing

SPEC-0012 G3 emergent routing is canon, so the rule table's ORDER and every
existing predicate stay exactly as they are. Rules 5 and 6 gain one shared
precondition on their VERDICT:

```
closedFocus = s.close_event_present === true
              && s.close_event_superseded_by_reopen !== true
```

When rule 5's or rule 6's match condition holds AND `closedFocus` is true, the
verdict becomes `needs_llm` with the named reason `closed_focus_stale_state`
(rule field preserved as `5` / `6`), instead of `dispatch Planning`. Rules 4a and
4b are evaluated BEFORE 5/6 and are untouched, so a focus that is genuinely
retargetable or flushable still takes those arms first — which is exactly the
route the D1 reconcile now unblocks. Rule 7 needs no guard: a closed spec carries
frontmatter status `done`, so rule 6 always matches first and rule 7 is
unreachable for this state.

### D8 — re-opening is a real lane, and the guard must not misfire on it

`close_event_present` is computed from the whole append-only `EVENTS.jsonl`, is
never expired, and would therefore stay true forever on a scope someone
legitimately re-opened. This is not hypothetical: `docs/ai/EVENTS.jsonl` lines
1002-1003 carry `doc_lifecycle {"from":"done","to":"implementing"}` for
`ISSUE-0026` and `SPEC-0072` (2026-07-23). The discriminator is ordering in the
same append-only log the same scan already walks: a NEW snapshot field
`close_event_superseded_by_reopen` is true when the last `doc_lifecycle` event
for the focus ref carrying `payload.from === "done"` appears AFTER the last
`work_item_closed` event for that ref. `close_event_present` keeps its exact
current meaning and rule 4b keeps its exact current predicate, so the new field
is purely additive and a snapshot that lacks it (every existing fixture) behaves
as before.

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred: entire spec postponed; explain reason in this section
- rejected: spec was abandoned; explain rationale
- superseded: replaced by a newer spec; set links to the replacement

## Implementation strategy
- Strategy: tdd
- Rationale: both surfaces have a free, exact RED. The dispatcher guard is a
  pure function of a hand-built snapshot object, so a failing arm is a
  twenty-line `decide()` call that costs nothing to observe red first. The
  close-time reconcile has an equally exact RED — a fixture repo whose STATE
  names the closing ref, run the close, assert `status: done`; the pre-fix code
  fails it deterministically. Neither RED needs the implementation to exist,
  and the whole bug class this scope fixes is "a behavior nobody ever asserted",
  which is what RED-first exists to prevent recurring.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: two scripts and two suites; no protected surface, no
  migration, and both suites are hermetic (fixture repos under `TEST_DIR`). The
  one genuinely mutating activity — the bite-proof negative controls of
  Spec-AC-06 — is already bound by HAZ-RESTORE and HAZ-WORKTREE to a disposable
  DETACHED worktree regardless of what the implementation workspace is, so a
  worktree buys isolation the hazards already mandate for the only step needing
  it. Implementation Preparation decides.
- User decision: undecided
- Base ref: main
- Worktree branch/path: fix/post-close-state-truth (current branch, inline)
- Inline review scope: .aai/scripts/close-work-item.mjs,
  .aai/scripts/orchestration-dispatch.mjs,
  tests/skills/test-aai-close-work-item.sh,
  tests/skills/test-aai-orchestration-dispatch.sh,
  docs/specs/SPEC-DRAFT-close-leaves-state-stale.md,
  docs/issues/ISSUE-DRAFT-close-leaves-state-stale.md

## Acceptance Criteria Mapping
- Maps to: docs/issues/ISSUE-DRAFT-close-leaves-state-stale.md "Expected Behavior"
- Spec-AC-01 .. Spec-AC-09 below; verification commands are named per row in
  `## Acceptance Criteria Status` and expanded in `## Verification`.

## Constitution deviations

None. Article 6 (single-writer state) is honored by construction: every STATE
write in this scope is an invocation of `.aai/scripts/state.mjs`, the reconcile
never writes STATE bytes directly (D3 rejects the rollback arm precisely to
avoid that), and the R-GUARD marker is never stripped from the child
environment (D4). Article 4 (degrade and report) governs the named-skip arm;
Article 5 (additive first) governs exit code 6 and the new snapshot field, both
of which leave every existing exit code, rule id and snapshot field unchanged.

## Acceptance Criteria Status

Tracks per-Spec-AC delivery state. Separate from per-test lifecycle below.

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN close-work-item.mjs exits 0 for ref R against a STATE naming R the system SHALL leave active_work_items R with status done and primary_path plus spec_path equal to the on-disk paths this run resolved, and current_focus primary_path plus spec_path equal to the same paths when current_focus ref_id names R | planned | — | — | verified by reading the fixture STATE after the run, not by the exit code |
| Spec-AC-02 | WHEN docs and events are already closed but STATE still names R as in-flight the system SHALL still reconcile STATE on a re-run, and WHEN STATE is already reconciled it SHALL make zero STATE writes and leave the file byte-identical | planned | — | — | pins both the recovery path and idempotency |
| Spec-AC-03 | WHEN the reconcile cannot run or its first command fails the system SHALL exit 0, print exactly one stderr line matching close-work-item: WARN (state-reconcile) naming the reason and echoing every planned state.mjs command, and leave STATE byte-identical; WHEN a later command fails after an earlier one succeeded it SHALL exit 6 and print a close-work-item: PARTIAL (state-reconcile) block naming applied-of-total and the remaining commands | planned | — | — | the never-a-silent-half-close requirement, both arms |
| Spec-AC-04 | WHEN close-work-item.mjs runs with AAI_ROLE=subagent set the system SHALL leave docs/ai/STATE.yaml byte-identical, take the Spec-AC-03 warn arm naming the single-writer refusal, and never remove AAI_ROLE from the environment it passes to state.mjs | planned | — | — | Article 6 and D4; the marker is honored, not defeated |
| Spec-AC-05 | WHEN decide() receives a snapshot whose close_event_present is true and close_event_superseded_by_reopen is not true the system SHALL never return role Planning from rule 5 or rule 6; it SHALL return verdict needs_llm carrying reason closed_focus_stale_state, while rules 4a and 4b keep firing first on every snapshot where they fire today | planned | — | — | no rule reordering; only the 5 and 6 verdicts are constrained |
| Spec-AC-06 | WHEN the last doc_lifecycle event with payload from done for the focus ref appears after the last work_item_closed event for that ref the system SHALL set close_event_superseded_by_reopen true and rules 5 and 6 SHALL return the byte-identical dispatch verdict they return today | planned | — | — | the re-open negative control; keeps rule 4b byte-unchanged |
| Spec-AC-07 | Every new suite arm SHALL be observed FAILING against the pre-change tree in a disposable detached worktree, with the transcript stored under docs/ai/tdd/, before the change that makes it pass | planned | — | — | tdd strategy; RED-first, bite-proof in both directions |
| Spec-AC-08 | The delivered diff SHALL contain no path listed in protected_paths_l3 of docs/ai/docs-audit.yaml and no byte added to .aai/*.prompt.md or .aai/AGENTS.md, and the full sweep SHALL be green with the prompt-diet TEST-012 pin unchanged at 2284 | planned | — | — | zero in-corpus growth is a design target of D3 and D7, not an accident |
| Spec-AC-09 | At the close ceremony fu-dispatch-targets-closed-scope SHALL read status done in the registry with resolved_by naming this scope, while fu-setfocus-keeps-stale-spec-path SHALL still read open | planned | — | — | registry outflow; the narrowing note lives in this spec's Notes |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan

### Surface 1 — .aai/scripts/close-work-item.mjs

- Header: extend the D8 exit contract with `6` (D3) and add a short `STATE
  RECONCILE (D1-D6)` block describing the step.
- New import: `loadState`, `findBlock`, `readScalar`, `unquoteScalar` from
  `./lib/state-engine.mjs` (read-only use of a protected module).
- `planStateReconcile(root, resolved, args)` — pure, read-only, evaluated with
  the three existing gates BEFORE any write. Returns
  `{ severity: 'none' | 'skip' | 'apply', reason?, statePath, commands: [[bin, args...]], echo: [string] }`:
  - STATE file absent -> `none` (a fixture repo with no STATE is never touched,
    the same non-regression property `scanAgentRuns` already has).
  - Identity set = `resolved[0].fmId` plus `resolved[0].fileIds`.
  - Work-item arm: locate the `active_work_items` item whose `ref_id` is in the
    identity set; capture its verbatim `ref_id`, `phase`, `status`,
    `primary_path`, `spec_path`.
  - Focus arm: `current_focus.ref_id` in the identity set -> capture the
    verbatim `type` and `ref_id`.
  - Unusable shape (`phase` absent or outside the CLI's enum, `type` absent or
    outside the CLI's enum, a ref matching neither `^[A-Z]+-\d+$` nor the slug
    shape) -> `skip` with a reason naming the field. Never a refusal: a STATE
    defect must not block a verified close (Article 4).
  - Every planned value already equal to what STATE holds -> the command is
    dropped; all commands dropped -> `none`.
- `applyStateReconcile(plan)` — runs each command with `execFileSync('node',
  [STATE_CLI, ...])`, `stdio: ['ignore', 'ignore', 'pipe']`, env inherited
  UNCHANGED (D4). Returns `{ applied, total, failedAt, childStderr }`.
- `main()` wiring, in four places:
  1. after the evidence-path gate: `const statePlan = planStateReconcile(...)`.
  2. `--dry-run` JSON gains `stateReconcile: { severity, reason, statePath, commands: plan.echo }`; still writes nothing, still exits 0.
  3. `anyMutationTotal` gains `|| statePlan.severity === 'apply'`, so a repo whose docs are closed but whose STATE is stale reconciles on a re-run (Spec-AC-02) instead of short-circuiting to "nothing to do".
  4. immediately AFTER the existing `try`/`catch` block (self-verify has passed; outside the rollback scope by construction) and BEFORE `pruneBriefs`: `severity === 'apply'` -> `applyStateReconcile`; `severity === 'skip'` -> the WARN line. The success line, brief prune, the four best-effort regens and the friction capture all run unchanged; a `failedAt > 0` partial prints its block and exits 6 as the last statement, a `failedAt === 0` first-command failure degrades to the WARN arm and exits 0.
- Worktree advisory: when `resolveEvidenceRoot(ROOT) !== ROOT`, one extra stderr
  line naming the STATE written and the untouched main-checkout STATE (D6).

### Surface 2 — .aai/scripts/orchestration-dispatch.mjs

- `RULES` rows `5` and `6`: extend the `when` text with the closed-focus
  precondition and the named reason. The table is the single source the
  `--rules` output and `.aai/ORCHESTRATION.prompt.md` point at, so it must stay
  honest.
- `buildSnapshot`: inside the EXISTING `EVENTS.jsonl` scan loop, track the index
  of the last `work_item_closed` for the focus ref and the index of the last
  `doc_lifecycle` whose `payload.from === 'done'` for the focus ref; add
  `close_event_superseded_by_reopen: <boolean>` to the snapshot. No new file
  read, no new pass over the ledger.
- `decideRuleTable`: one `const closedFocus = ...` immediately before rule 5,
  and one guarded branch inside each of the two existing `if` bodies. Rule
  order, predicates and every other verdict untouched.

### Surface 3 — the two suites

- `tests/skills/test-aai-close-work-item.sh`: four new arms plus their `main()`
  registration (hygiene `test_093` / `check-test-registration.mjs` fails an
  orphan test function).
- `tests/skills/test-aai-orchestration-dispatch.sh`: two new arms plus `main()`
  registration.
- `tests/skills/suite-map.yaml` needs no edit: both scripts are already globbed
  to their suites (`aai-close-work-item`, `aai-orchestration-dispatch`).

### Seams this change crosses

| Seam | Producer | Consumer | Crossed by |
|------|----------|----------|------------|
| S1 STATE work-item status | close-work-item reconcile | orchestration-dispatch rules 4a and 4b | TEST-006 runs the real dispatcher CLI against the STATE a real close-work-item run just wrote |
| S2 STATE work-item status | close-work-item reconcile | metrics-flush sweep predicate, which refuses any ref whose active_work_items status is not done | TEST-006 asserts the post-close STATE satisfies that predicate |
| S3 EVENTS ordering | close-work-item event set and any re-open doc_lifecycle | orchestration-dispatch snapshot | TEST-007 builds the ledger through append-event.mjs and reads the CLI state_summary |
| S4 doc path allocation | allocate-doc-number rename at the PR step | STATE paths | TEST-001 resolves the doc under its numbered name and asserts STATE carries that name, not the DRAFT one |

### Edge cases

- STATE absent (fixture repos) — reconcile is a no-op, close unchanged.
- Close ref absent from STATE — no-op, and `current_focus` belonging to another
  scope is never rewritten (D5).
- `--dry-run` — plan reported, nothing written, exit 0 regardless of severity.
- Idempotent re-run on an already-reconciled STATE — zero commands, zero writes.
- `AAI_ROLE=subagent` — named skip, exit 0, marker intact (Spec-AC-04).
- Legacy dispatcher snapshots lacking `close_event_superseded_by_reopen` — the
  `!== true` test treats absent as "not superseded", the fail-closed-to-halt
  polarity every other guard in that file uses.
- A closed focus with a required-but-unsatisfied review reaches rule 6 today and
  gets Planning; under D7 it gets `needs_llm closed_focus_stale_state`. This is
  a deliberate, pinned knock-on: the state was already mis-dispatched and the
  code comment on rule 4b's review guard ("still routes to rule 13") was already
  inaccurate for it. TEST-005 asserts the new verdict explicitly.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | int | tests/skills/test-aai-close-work-item.sh | fixture repo with a numbered doc pair plus a STATE naming the ref with status in_progress and DRAFT paths; after the close, active_work_items status is done and all four path fields name the numbered files | pending |
| TEST-002 | Spec-AC-01 | int | tests/skills/test-aai-close-work-item.sh | scoping controls: a close for a ref absent from STATE writes nothing, and a close whose current_focus names a DIFFERENT ref leaves current_focus byte-identical while the work item still reconciles | pending |
| TEST-003 | Spec-AC-02 | int | tests/skills/test-aai-close-work-item.sh | docs and events already closed plus stale STATE still reconciles on re-run, and an immediately following third run makes zero writes with a byte-identical STATE | pending |
| TEST-004 | Spec-AC-03, Spec-AC-04 | int | tests/skills/test-aai-close-work-item.sh | three arms: AAI_ROLE=subagent gives exit 0, byte-identical STATE, one WARN line naming the single-writer refusal and echoing both commands; an injected first-command failure gives the same warn shape at exit 0; an injected second-command failure gives exit 6 with the PARTIAL block naming 1 of 2 and the remaining command | pending |
| TEST-005 | Spec-AC-05 | unit | tests/skills/test-aai-orchestration-dispatch.sh | pure decide() arms over hand-built snapshots: closed focus plus null spec_path yields needs_llm rule 5 closed_focus_stale_state; closed focus plus spec status done yields the same at rule 6; role is null in both; 4a and 4b precedence arms still return 4a and 4b; a snapshot with close_event_present false still dispatches Planning at 5 and 6 | pending |
| TEST-006 | Spec-AC-05 | e2e | tests/skills/test-aai-orchestration-dispatch.sh | seam S1 and S2 end to end: build a fixture repo, run the real close-work-item.mjs, then run orchestration-dispatch.mjs --human against the STATE it produced and assert the verdict is rule 4b Metrics Flush and never role Planning; also assert the reconciled STATE satisfies metrics-flush's status-must-be-done sweep predicate | pending |
| TEST-007 | Spec-AC-06 | int | tests/skills/test-aai-orchestration-dispatch.sh | re-open negative control: EVENTS carrying work_item_closed then a later doc_lifecycle from done sets close_event_superseded_by_reopen true in state_summary, rules 5 and 6 dispatch Planning exactly as before, and the reverse order (re-open then close) leaves it false | pending |
| TEST-008 | Spec-AC-07 | int | tests/skills/test-aai-close-work-item.sh + tests/skills/test-aai-orchestration-dispatch.sh | bite-proof both directions: in a disposable detached worktree cut from the base ref, TEST-001 through TEST-007 are observed FAILING on the pre-change tree, and each production edit reverted in isolation reddens only its own arms; transcripts stored under docs/ai/tdd/ | pending |
| TEST-009 | Spec-AC-08 | e2e | tests/skills/test-framework.sh | full framework sweep green, honoring each suite shebang, run under env -u AAI_ROLE | pending |
| TEST-010 | Spec-AC-08 | unit | tests/skills/test-aai-prompt-diet.sh | TEST-012 still asserts JUSTIFIED_GROWTH_BYTES equals 2284 with no new ledger entry, and the diff's file list intersected with protected_paths_l3 is empty | pending |
| TEST-011 | Spec-AC-09 | int | tests/skills/test-aai-follow-ups.sh | after the close ceremony, follow-ups.mjs list --status all reports fu-dispatch-targets-closed-scope as done resolved by this scope and fu-setfocus-keeps-stale-spec-path as open | pending |

Test status values: pending -> red -> green

## Verification

Commands, in order, each producing one observable:

1. Spec-AC-01, Spec-AC-02, Spec-AC-03, Spec-AC-04:
   `env -u AAI_ROLE bash tests/skills/test-aai-close-work-item.sh` -> exit 0,
   and the new arms named in its PASS lines.
2. Spec-AC-05, Spec-AC-06:
   `env -u AAI_ROLE bash tests/skills/test-aai-orchestration-dispatch.sh` -> exit 0.
3. Spec-AC-07: the stored RED transcripts under `docs/ai/tdd/` naming each new
   arm and the assertion text it failed on, produced in a worktree created with
   `git worktree add --detach <scratch> main` and removed with
   `git worktree remove <scratch>`.
4. Spec-AC-08:
   `env -u AAI_ROLE bash tests/skills/test-framework.sh` -> exit 0 with zero
   failing suites; `git diff --name-only main...HEAD` -> no line equal to any
   `protected_paths_l3` entry and no line matching `^\.aai/.*\.prompt\.md$` or
   `^\.aai/AGENTS\.md$`; `env -u AAI_ROLE bash tests/skills/test-aai-prompt-diet.sh`
   -> exit 0 with TEST-012 printing 2284.
5. Spec-AC-09: `node .aai/scripts/follow-ups.mjs list --status all` -> one line
   showing `fu-dispatch-targets-closed-scope` done, one showing
   `fu-setfocus-keeps-stale-spec-path` open.
6. Document gates: `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-DRAFT-close-leaves-state-stale.md`
   -> exit 0; `node .aai/scripts/docs-audit.mjs --check --strict --no-event` -> CLEAN.

PASS criteria: every TEST-xxx green AND every Spec-AC in a terminal status.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: close-leaves-state-stale
- Spec-AC and TEST-xxx links per artifact
- command or review scope
- exit code or review verdict
- evidence path: `docs/ai/tdd/red-<ts>-*.log`, `docs/ai/tdd/green-<ts>-*.log`,
  the full-sweep log under `tests/skills/results/`, and the reconcile
  transcripts (fixture STATE before and after)
- commit SHA or diff range: the branch diff against `main` at review time

### Evidence by strategy

Strategy is `tdd`, so this spec demands the stored RED artifact per AC-gating
arm (Spec-AC-07) plus the full verification matrix above.

## Registry items closed by this scope

`fu-dispatch-targets-closed-scope` (P2, ref deslop-scope-and-unrequested-engine)
— closed at the close ceremony with `resolved_by` naming this change.

## Notes

- Consulted `node .aai/scripts/follow-ups.mjs list` at freeze (96 open, 160
  closed). Two neighbours are deliberately NOT closed here:
  - `fu-setfocus-keeps-stale-spec-path` (P2) — NARROWED, not closed. Its root is
    `set-focus`'s own field handling inside protected `state.mjs`, which this
    scope must not edit. What D1 removes is the largest live instance: at close,
    `current_focus.spec_path` is now overwritten with the path this run resolved
    rather than left pointing at the previous scope's spec. The generic case (a
    `set-focus` to a NEW ref with no `--spec-path`, which still inherits the old
    value) is untouched and the entry stays open with that narrowing recorded.
  - `fu-validation-staleness-undetected` (P2) — untouched. It concerns a
    validation pass surviving a later remediation; nothing in D1 or D7 moves it.
- `.aai/ORCHESTRATION.prompt.md` gets ZERO bytes, deliberately. Its exit-4
  handler list is a closed set ("handle ONLY the named reasons, nothing else"),
  so an unlisted `closed_focus_stale_state` leaves the wrapper reporting the JSON
  and stopping — which IS the intake's required outcome (fail-flagged, never
  fail-dispatched). The alternative, folding the reason into the existing
  `no_focus_ref / focus_ref_not_in_active_work_items / no_rule_matched` bullet,
  costs roughly 29 bytes against a corpus with 0 of 2048 headroom and would
  force a `JUSTIFIED_ADDITIONS` entry plus a TEST-012 pin bump for a lane the D1
  fix should make unreachable on a healthy ride. Recorded here so an operator who
  wants the autonomous recovery can ask for it as an explicit follow-up rather
  than discovering the omission.
- The intake's live check ("next real ride's first post-merge tick reaches rule
  4b with no hand edits") holds when the close ran in the checkout the next tick
  reads. When the close ran in a linked worktree (D6), the main checkout's STATE
  stays stale and the tick reaches `needs_llm closed_focus_stale_state` instead
  of rule 4b — flagged, never a wrong dispatch. That residual is named here
  rather than papered over.
