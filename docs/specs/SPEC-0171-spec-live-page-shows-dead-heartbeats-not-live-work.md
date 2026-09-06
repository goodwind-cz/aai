---
id: spec-live-page-shows-dead-heartbeats-not-live-work
type: spec
number: 171
status: done
ceremony_level: 2
links:
  requirement: live-page-shows-dead-heartbeats-not-live-work
  rfc: null
  pr:
    - 351
  commits:
    - 1412b4830e6924ad64506b8a759eed9966238217
---

# The live page shows dead heartbeats as agents and hides the live work

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0178-live-page-shows-dead-heartbeats-not-live-work.md
- Decision records: `ride_gate_override` in docs/ai/EVENTS.jsonl, 2026-09-06
- Technology contract: docs/TECHNOLOGY.md

## Root cause

Two independent causes, one per defect.

Defect 1 — the graveyard. `heartbeat.mjs` tends its directory on the WRITE path
only: `cmdWrite` calls `reapAsides(dir, SLOT_PREFIX, now, GC_WINDOW_MS)` before
it writes, and `cmdRead` tends nothing. A slot is therefore removed only when
some other role happens to write a heartbeat within the following 24 hours. It
also has no notion of liveness at all — `cmdRead` reports `age_seconds` as an
explicit FACT and leaves the verdict to the caller, and the only caller,
`aai-live-serve.mjs`, turns age into the word "stale" and lists the row anyway.
So a slot whose process died is indistinguishable from a slot whose process is
merely quiet, and once every role has stopped writing, nothing ever removes it.
Observed 2026-09-06: three slots from 2026-09-03 and 2026-09-04 with pids 7053,
52554 and 95962, none of them a running process, listed under the heading
"Agents" on a page whose purpose is to say what is running now.

Defect 2 — the discarded detail. `generate-live-status.mjs` already produces
`live_sessions`, one record per session with `harness`, `sessionId`, `project`
and `state`. `aai-live-serve.mjs` reads that payload, keeps only
`sessions_active`, `sessions_total`, the harness list and the spend totals, and
renders the single sentence "N active of M sessions". The per-session detail —
the only data in the whole payload that answers "what is happening now" — is
dropped between the file and the page.

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred: entire spec postponed; explain reason in this section
- rejected: spec was abandoned; explain rationale
- superseded: replaced by a newer spec; set links to the replacement

## Implementation strategy
- Strategy: hybrid
- Rationale: the liveness classification decides whether a row is shown or
  withheld and is the half that can lie in the dangerous direction, so it is
  taken RED-first per TEST. The page rendering is presentation glue over data
  the server already holds and is taken as a focused implementation pass with
  targeted assertions on the served bytes.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: two scripts and two suites, no schema and no protected
  path; a dedicated branch gives the isolation this scope needs. A worktree is
  useful only because another session may still be active in this checkout.
- User decision: undecided
- Base ref: main, AFTER PR #349 merges — that PR is unmerged and rewrites 134
  lines of `.aai/scripts/aai-live-serve.mjs` and 149 of its suite, so branching
  off today's `main` would develop against bytes that are about to be replaced.
- Worktree branch/path: fix/live-page-shows-dead-heartbeats-not-live-work
- Inline review scope: .aai/scripts/heartbeat.mjs, .aai/scripts/aai-live-serve.mjs,
  tests/skills/test-aai-heartbeat.sh, tests/skills/test-aai-live-serve.sh

## Acceptance Criteria Mapping
- Maps to: CHANGE AC-001 through AC-008
- See the Acceptance Criteria Status table below for the implementation-oriented
  statements and the Verification column of the Test Plan for the commands.

## Constitution deviations

None as shipped. The frozen design narrowed `heartbeat.mjs read --json`'s
`slots` field, which is not an additive edit and was justified here at length.
Amendment 2 removed that narrowing: `slots` is unchanged, the only addition to
that file is a `degraded` entry for a prefixed non-slot entry, and the
withholding happens in the PRESENTATION layer (`aai-live-serve.mjs`), where the
page's own contract already distinguishes shown from marked. The earlier
Article 5 justification is retained in git history rather than here, because a
deviation that no longer exists must not read as one that does.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN the live server builds /data.json THEN the roles array SHALL carry only heartbeat slots whose age is at or below the hide window of 3600 s; a slot older than that SHALL NOT be presented as an agent (Amendment 2 — freshness, not a pid probe) | done | TEST-013 green, mutation-proved: dropping the filter, and narrowing it to STALE_AFTER_S, both turn the suite red. Against the LIVE repository the Agents table went from three slots dated 2026-09-03/04 to none. | 2026-09-06 | — |
| Spec-AC-02 | WHEN slots are withheld by that window THEN /data.json SHALL carry roles_withheld with their count and the age of the NEWEST withheld slot, so a reader can tell minutes-old work from a graveyard, and the page SHALL render that line under the Agents table (Amendment 2) | done | TEST-013 green: roles_withheld carries count 1 and a newest age over 200000 s, and the served page states 'older slot(s) on disk'. Mutation-proved on both the count and the age. | 2026-09-06 | fails open |
| Spec-AC-03 | WHEN a slot is older than STALE_AFTER_S but at or below the hide window THEN it SHALL still be listed and marked stale exactly as today — hiding is more destructive than marking, so the window fails open and a role that pauses for ten minutes never disappears (Amendment 2) | done | TEST-002 (pre-existing) and TEST-013 together: a 10-minute-old slot is still listed and marked stale. The mutation that narrows the hide window to STALE_AFTER_S is caught by TEST-002, which is the fail-open guarantee stated as an assertion. | 2026-09-06 | degrade-with-NOTE |
| Spec-AC-04 | WHEN the heartbeat directory holds an entry whose name starts with hb- but does not end in .json THEN read SHALL name it in degraded rather than ignore an entry its own GC is free to delete | done | TEST-022 in tests/skills/test-aai-heartbeat.sh green and mutation-proved; the read now names a prefixed non-json entry the GC is free to delete instead of ignoring it. Closes fu-heartbeat-read-narrower-than-gc. | 2026-09-06 | closes fu-heartbeat-read-narrower-than-gc |
| Spec-AC-05 | WHEN the live server serves /data.json THEN the payload SHALL carry one object per live session with its harness and project and state fields taken from the live-status payload | done | TEST-014 green via the new --live-status-script seam (added alongside --state / --answers / --heartbeat-dir / --results-dir): a fixture payload of two running and one finished session yields exactly two rows carrying harness, project and state, with the finished one still in sessions_total. Three mutations caught. | 2026-09-06 | — |
| Spec-AC-06 | WHEN the served page renders THEN it SHALL show one row per running session with harness and project and the scan timestamp the rows came from and SHALL summarise non-running sessions as a count rather than as rows | done | TEST-014 green: the page carries a Live sessions section rendering one row per running session plus the scan timestamp. Against the live repository it showed three running sessions including the one driving the page. | 2026-09-06 | — |
| Spec-AC-07 | WHEN the heartbeat directory holds only dead slots THEN the page Agents section SHALL read that no agent has a live heartbeat | done | TEST-013 second arm: a directory holding only three-day-old slots yields zero agents and still reports one slot on disk — the reported defect end to end. | 2026-09-06 | the reported defect end to end |
| Spec-AC-08 | WHEN the SPEC-0167 refusal set is exercised THEN every refusal SHALL behave exactly as before and the server SHALL still write no file other than the gitignored answer ledger | done | TEST-001, TEST-005, TEST-009, TEST-010 and TEST-011 unchanged and green: non-loopback host exits 2, the CSRF refusal set is intact on four independent grounds, and the serve+poll cycle still writes only the gitignored answer ledger. TEST-007's rule that every innerHTML sink visibly escapes caught two new multi-line sinks and both were collapsed onto one line rather than exempted. | 2026-09-06 | regression fence |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan

Components affected:
- `.aai/scripts/aai-live-serve.mjs` — `readRoles` applies the freshness window
  and returns `{roles, withheld, degraded}`; `readLive` keeps the per-session
  rows; the page grows a Live sessions table and a withheld line under Agents;
  a `--live-status-script` test seam joins the existing ones.
- `.aai/scripts/heartbeat.mjs` — the readdir names a prefixed non-slot entry in
  `degraded` instead of ignoring it. `slots` and the GC are untouched.

Data flows:
- heartbeat slot -> `cmdRead` -> `{slots, degraded}` -> `readRoles` (window
  applied here) -> `/data.json` `roles` + `roles_withheld` -> the Agents table.
- `live-status-data.json` `live_sessions` -> `readLive` -> `/data.json`
  `live.sessions` -> the Live sessions table.

Liveness: freshness, not a probe. See Amendment 2 — the recorded `pid` is the
writer's, not the agent's, so it cannot answer the question at all.

Edge cases:
- A clock that lags the reader by more than the window hides a live slot. This
  is the one path where live work disappears, and it is NOT silent: the slot is
  counted in `roles_withheld` with its age, so the page says something is there.
- A future `updated_at` yields a negative age and is SHOWN — the window only
  ever hides what is old, never what is ahead.
- An unparseable `updated_at` is rejected upstream by `isSlotShape` and named in
  `degraded`, never silently dropped.
- `atomicWrite`'s in-flight temps carry the slot prefix; they are excluded from
  the stray report, or a read landing inside a write window would report a
  healthy write as a degrade.
- The stray report is capped at 20 entries plus a count: 3000 stray files
  produced a 452 KB `/data.json` on every five-second poll.

Seams crossed:
- `heartbeat.mjs read --json` to `aai-live-serve.mjs readRoles` — TEST-013 plants
  real slots on disk, starts the actual server against that directory, and
  asserts on the served bytes AND on what `render()` puts in the DOM.
- `generate-live-status.mjs` to `readLive` — TEST-014 drives it through
  `--live-status-script` with a known payload and asserts the rendered rows.

## Test Plan

| Test ID  | Spec-AC | Type | File path | Description | Status |
|----------|---------|------|-----------|-------------|--------|
| TEST-013 | Spec-AC-01 | int | tests/skills/test-aai-live-serve.sh | a three-day-old and a two-hour-old slot are withheld while the fresh and ten-minute ones remain | done |
| TEST-013 | Spec-AC-02 | int | tests/skills/test-aai-live-serve.sh | roles_withheld carries the count and the NEWEST withheld age, and the RENDERED Agents block states it | done |
| TEST-002 | Spec-AC-03 | int | tests/skills/test-aai-live-serve.sh | pre-existing: a ten-minute slot is listed and marked stale — the fail-open guarantee | done |
| TEST-022 | Spec-AC-04 | unit | tests/skills/test-aai-heartbeat.sh | a prefixed non-json entry is named in degraded | done |
| TEST-023 | Spec-AC-04 | unit | tests/skills/test-aai-heartbeat.sh | an in-flight atomicWrite temp is NOT reported as a degrade | done |
| TEST-024 | Spec-AC-04 | unit | tests/skills/test-aai-heartbeat.sh | the stray report is capped and states how many it did not list | done |
| TEST-014 | Spec-AC-05 | int | tests/skills/test-aai-live-serve.sh | two running and one finished session yield exactly two rows with harness, project and state | done |
| TEST-014 | Spec-AC-06 | int | tests/skills/test-aai-live-serve.sh | the RENDERED sessions block carries a row per running session, the scan timestamp and a running-of-total count | done |
| TEST-013 | Spec-AC-07 | int | tests/skills/test-aai-live-serve.sh | a directory of only three-day-old slots yields no agents and still reports what is on disk | done |
| TEST-007 | Spec-AC-08 | int | tests/skills/test-aai-live-serve.sh | pre-existing: every innerHTML sink visibly escapes — it caught two new multi-line sinks in this scope | done |

Mutation battery: 15 mutations across both suites, all caught. The first battery
had four survivors, every one of them a page-rendering claim asserted by
grepping the SERVED TEMPLATE — which contains every heading and literal the page
can ever show, so it passes with the rendering deleted. The assertions now
extract the page's own `render()` and run it against a fake DOM, the technique
TEST-008 already used and documented.

## Verification

`aai-run-tests.sh` is a process-group WRAPPER: its interface is
`aai-run-tests.sh <command> [args...]`, so it needs a command to run. The three
lines here first passed it `--skill` and `AAI_TEST_TIMEOUT` alone, which exit 1
(`setsid: unrecognized option`) and 2 (usage) — none of the recorded green runs
was reproducible from them (bot review, PR #351). The author had already hit
the same wall once during this ride and still wrote the wrong form down.

- `bash tests/skills/test-aai-heartbeat.sh` — exit 0.
- `bash tests/skills/test-aai-live-serve.sh` — exit 0.
- Either suite through the wrapper, when a process-group kill matters:
  `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-heartbeat.sh`
- Full sweep:
  `AAI_TEST_TIMEOUT=3000 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh`
  The timeout is not optional: the wrapper's watchdog defaults to 300 s and the
  sweep needs about thirty minutes, so without it the run is killed around
  suite 8 of 89 with exit 124, which reads as a hang (`fu-sweep-dies-at-wrapper-default`).
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.

## Evidence contract
- ref_id: live-page-shows-dead-heartbeats-not-live-work
- Spec-AC and TEST-xxx links: as tabulated above.
- TDD half (Spec-AC-01 through Spec-AC-04): a stored RED artifact per test under
  docs/ai/tdd/ before the implementing commit.
- Implementation half (Spec-AC-05 through Spec-AC-08): per-TEST green runs with
  exit codes and the scoped diff; the RED observation is required and recorded
  in the run log, its storage optional.
- Review scope: the four paths named under Isolation and review.
- Commit SHA or diff range recorded at close.

## Registry items closed by this scope

The labels below are the ones `follow-ups.mjs verify-closures` parses, spelled
exactly as it expects. Written as prose ("NOT closed") they are not recognised,
the body counts as unlabelled, and EVERY id in it becomes a closure claim — so
this section reported three misses against the real registry until the labels
were fixed. The words carry meaning to a machine here, not just to a reader.

- CLOSED FULLY: `fu-heartbeat-read-narrower-than-gc` — Spec-AC-04. The read now
  names a prefixed entry it cannot interpret instead of ignoring a file the GC
  beside it is free to delete.
- NOT CLOSED: `fu-heartbeat-slot-name-not-injective` — a write-path collision
  between two refs that sanitize to one slot name. This scope changes the read
  path and the page; closing it would mean redesigning slot naming.
- NOT CLOSED: `fu-layer-profiles-suite-load-fragile` — named because it is the
  known cause of the intermittent red seen on PR #349, not a defect of this
  scope.

## Notes
This document defines HOW, not WHAT/WHY.
This document does not define workflow.

## Amendment 2 (owner-authorized, 2026-09-06) — liveness is freshness, not a pid

AC-001..003 as frozen asked for a probe of the `pid` recorded in each slot.
Implementation found the premise false before writing the guard: `heartbeat.mjs`
`write` stores `pid: process.pid` — the pid of the short-lived `node` process
that writes the slot and exits immediately, not of the agent that goes on
working. The recorded pid is dead within milliseconds of being written.

The probe was built and measured against the live repository before it was
removed. It reported **0 live slots and 3 dead** — which looks exactly like the
fix working, and is in fact the probe hiding every slot there is, live work
included. That is the failure this ride exists to prevent, reproduced by the
ride's own first design.

What ships instead: a heartbeat is a heartbeat. A role that is working refreshes
its slot, so freshness is the only liveness signal the data actually carries.
The Agents table shows slots at or below a one-hour hide window; older ones are
withheld and COUNTED under the table with the age of the newest. `STALE_AFTER_S`
stays at 120 s and keeps MARKING rather than hiding, so a role that pauses to
think for ten minutes is never made to disappear — hiding is more destructive
than marking, so the window fails open.

Deliberately NOT changed: the write contract. Recording a parent pid instead
looks more correct, but its reliability differs per harness, every slot already
on disk still carries an unusable pid, and a freshness window would therefore be
needed anyway — the same result for more work and a wider blast radius. Tracked
as `fu-heartbeat-pid-field-is-decorative`; the GC's write-path-only schedule,
which is why three-day-old slots survived at all, as
`fu-heartbeat-gc-only-runs-on-write`.

Owner sign-off recorded in `docs/ai/decisions.jsonl`
(`heartbeat-liveness-is-freshness-not-pid`, `owner_signoff: true`).
