---
id: spec-ride-status-and-resume
type: spec
number: 264
status: done
frozen_sha256: 21b7fd4e81cf9217084af142c46fd7a04195a476f9992ba5da75f9e232adeb93
mutation_gate: v1
ceremony_level: 2
links:
  requirement: ride-status-and-resume
  rfc: RFC-0017
  pr: []
  commits: []
---

# Ride status view and resume probe: one read-only status from decide(), an already-done probe, and a /aai-ship resume that picks up the current ride

SPEC-FROZEN: true

## Links

- Intake: docs/issues/CHANGE-0238-ride-status-and-resume.md
- Umbrella: docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md
  (section 5, phase 4; this slice closes phase 4)
- Prior art: SPEC-0192 (strategy binding, `implementation_strategy.ref_id`,
  TEST-005 in tests/skills/test-aai-orchestration-dispatch.sh),
  spec-ride-state-handoff-to-worktree (ride-handoff.mjs carries strategy and
  worktree decision into a worktree), spec-git-platform-detected-at-bootstrap
  (lib/platform-adapter.mjs `resolvePlatform`, `createAdapter`,
  `listDependents`), CHANGE-0009 (orchestration-dispatch.mjs `decide()` and
  `buildSnapshot()`)
- House example of a frozen spec: docs/specs/SPEC-0263-spec-provider-adapter-surfaces-closing-slice.md
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, Node 24 baseline,
  Node 22 floor; Bash 3.2 and GNU Bash for suites)
- Baseline commit: `51840bde` (main at planning time)

## Implementation strategy

- Strategy: tdd
- Rationale: new behavior on a new script plus four prompt seams. Every row
  has an observable RED on the baseline (the script does not exist, the prompt
  lines are absent), and the status view's core claim, agreement with the
  dispatcher, is a cross-boundary assertion that must be seen failing under a
  mutation before it counts. Mutation gate v1 applies.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound; touches three core prompts, PROFILES.yaml, the
  suite map and the prompt-diet ledger; mutation runs temporarily rewrite
  `.aai/scripts/ride-status.mjs`, `.aai/SKILL_PR.prompt.md`, PROFILES.yaml and
  the diet ledger; the main checkout is shared with other sessions. No file is
  in `protected_paths_l3` (docs/ai/docs-audit.yaml): state.mjs, state-engine
  and orchestration-dispatch.mjs are imported, never edited. So not required.
- User decision: undecided
- Base ref: main
- Worktree branch/path: chosen by Implementation Preparation
- Inline review scope: the list in "Files Implementation touches" below.
- Code review required: true.

## What Planning measured

All measured at `51840bde`; inputs, not attestations.

### M1 Existing readers the status view reuses

- `.aai/scripts/orchestration-dispatch.mjs` exports `decide(snapshot, opts)`
  (line 338, pure) and `buildSnapshot(statePath, root)` (line 940, read-only:
  STATE via lib/state-engine.mjs, spec frontmatter, METRICS flush record,
  EVENTS close/confirm/verdict scan, git tree hash, roadmap gate without
  `--override`). The CLI runs only under `isMain` (line 1837), so importing it
  has no side effect. Its only writes are behind `--confirm` in `main()`.
- `buildSnapshot` already returns `close_event_present`,
  `close_event_superseded_by_reopen` and `flushed` for the focus ref.
- `lib/platform-adapter.mjs` exports `resolvePlatform({ repoRoot })` and
  `createAdapter(platform, { cwd, runner })`; the github adapter's
  `listDependents(branch, 'head')` runs `gh pr list --state open --head
  <branch> --json number --limit 100` (read only), the azure adapter maps
  `'head'` to `--source-branch`, and the generic adapter returns a named skip.
  A recorded `platform:` in docs/ai/pr-config.yaml wins over the detected
  remote, so a fixture can record `platform: github` over a local bare origin.
- `lib/tree-hash.mjs` `computeTreeHash(dir)` hashes tracked plus untracked
  files and names STATE.yaml and LOOP_TICKS.jsonl explicitly
  (`RUNTIME_ALLOWLIST`), so it proves a no-write claim over runtime state too.
- `AAI_GH_BIN` and a `gh` stub first on PATH are the house stub conventions
  (tests/skills/test-aai-merge-cleanup.sh `write_gh_stub`, pr-platform.mjs).

### M2 Real gaps

- No single surface prints current action, evidence, blocker and next decision.
  `aai-live` reads harness sessions, not STATE; `loop-digest.mjs` reads
  LOOP_TICKS; SKILL_LOOP's LOOP SUMMARY prints four raw STATE fields.
- `/aai-ship` resume does not resume. SKILL_SHIP step 3 says "re-run /aai-ship
  to resume", but INPUT with neither a need nor a path runs
  `ride-select.mjs next`. Measured: with `current_focus.ref_id:
  ride-status-and-resume` in STATE, `node .aai/scripts/ride-select.mjs next
  --json` returned `downstream-pr-ceremony-reliability`, a different ride.
- SKILL_PR step 5 pushes and runs `gh pr create` with no look at what already
  exists; SKILL_SHIP step 5 asks for "report that URL and skip a second
  create" in prose with no command behind it.
- The worktree decision is not bound to a ref. `state.mjs cmdSetWorktree`
  writes no `ref_id`; `metrics-flush.mjs applyPartialReset` (line 920) resets
  `last_validation` and `code_review` but not `worktree`; `buildSnapshot`
  reads `worktree.user_decision` without a ref check. A decision recorded for
  ride A therefore satisfies rule 8 for ride B after a partial flush or a
  retarget. The only complete fix stamps a ref in `state.mjs set-worktree`,
  a protected L3 surface. See D9.

### M3 Already satisfied (dropped, evidence)

- Strategy for another ref is never reused: `buildSnapshot` demotes
  `strategy_selected` to `undecided` when `implementation_strategy.ref_id`
  differs from the focus ref (orchestration-dispatch.mjs, the `stratRef`
  block after line 1010), pinned by SPEC-0192 TEST-005
  (`test_192_stale_strategy_is_undecided`). PLANNING principle 3 already keeps
  an intake-sourced choice. Nothing is built for it; the status view only
  shows it (D6).
- A recorded worktree decision is never asked again for the same ride:
  rule 8 fires only on `user_decision: undecided`, and ride-handoff.mjs `out`
  writes `user_decision: worktree` into the worktree STATE. Nothing is built.
- Model routing is not a per-ride question: `suggested_model` comes from
  `.aai/system/MODEL_ROUTING.yaml` (`loadModelRouting`, `suggestModel`) on
  every tick. No STATE field records a routing choice, so nothing can be
  lost on resume. Dropped.
- Ledger effects are already idempotent at their writers: close-work-item.mjs
  exits 0 on an already-closed item (SKILL_PR step 5c), rule 14 returns
  `already_flushed` once METRICS holds the flush record, and the dispatcher's
  `phase_confirmed` and `validation_verdict` stamps are first-observation
  only. The probe reports the two ride-level ledger facts from the existing
  snapshot fields (D7) and adds no ledger parser.
- release-finish.mjs and merge-cleanup.mjs already journal and resume their
  own external effects. Out of this slice.

### M4 Prompt bytes

- `.aai/SKILL_SHIP.prompt.md` 8383 B, `.aai/SKILL_PR.prompt.md` 32905 B,
  `.aai/SKILL_LOOP.prompt.md` 32171 B (`/usr/bin/wc -c`).
- `cat .aai/*.prompt.md | /usr/bin/wc -c` = 372603; TEST-012 pin
  (`want_growth` in tests/skills/test-aai-prompt-diet.sh) = 64396.
- Highest TEST-3xxx in docs/specs, tests and .aai: TEST-3143. This spec uses
  TEST-3144 to TEST-3162.

## Decisions

### D1 One new read-only script, no protected edit, no launcher, no skill

- New `.aai/scripts/ride-status.mjs`, Node stdlib only, two modes:
  `node .aai/scripts/ride-status.mjs [--json] [--state <p>] [--root <dir>]`
  (status) and `node .aai/scripts/ride-status.mjs probe [--json] [--branch <b>]
  [--state <p>] [--root <dir>]` (probe).
- It imports `buildSnapshot` and `decide` from orchestration-dispatch.mjs,
  readers from lib/state-engine.mjs (`loadState`, `findBlock`, `readScalar`,
  `unquoteScalar`), `parseFrontmatter` from lib/docs-model.mjs, and
  `resolvePlatform` and `createAdapter` from lib/platform-adapter.mjs.
- It never passes `confirm` to `decide()` and calls none of the dispatcher's
  `--confirm` writers. It writes no file in either mode: the source contains
  none of `writeFileSync`, `appendFileSync`, `renameSync`, `mkdirSync`,
  `rmSync`, `unlinkSync`, `copyFileSync`, and no `shell: true`. Child
  processes are `git` and the platform adapter only, with argument arrays.
- No edit to state.mjs, lib/state-engine.mjs, lib/state-core.mjs or
  orchestration-dispatch.mjs. No `.sh`/`.ps1` launcher pair: it is invoked as
  `node .aai/scripts/ride-status.mjs`, the same form on POSIX and PowerShell,
  like orchestration-dispatch.mjs. No new skill wrapper (the public skill list
  does not grow).
- Line cap: 400.
- Exit codes: 0 report printed (status and probe, whatever the content);
  2 usage error (unknown flag, missing value); 1 internal error.

### D2 Status output

Text mode prints exactly these lines, in this order:

```
ride: <ref_id> (<focus type>) spec=<spec_path or none> ceremony=<0..3>
current action: phase=<phase or none> status=<status or none>; dispatcher: <verdict> rule <rule or none> -> <role or none>[ reasons=<r1,r2>]
evidence: validation=<status>[ for <ref_id>][ <path1,path2>]; review=<status> required=<true or false>[ <paths>]; tdd=<tdd_cycle status or none> mutation_records=<n>; pr=<links.pr joined by comma, or none>
blocker: <kind>[: <detail>]
next decision: <actor>: <command> - <why>
decisions: strategy=<selected> ref=<ref_id or none> reused=<true or false>; worktree=<recommendation>/<user_decision> ref_binding=none
```

With no focus (`current_focus.ref_id` null) the first line is
`ride: none (no current focus)` and the other five lines are still printed
(current action `phase=none status=none`, evidence values `none`), so every
consumer reads the same six labels. `--json` prints one object with keys
`ref_id`, `focus_type`, `spec_path`, `ceremony_level`, `current_action`
(`phase`, `status`, `verdict`, `rule`, `role`, `reasons`), `evidence`
(`validation` {`status`, `ref_id`, `for_focus`, `evidence_paths`},
`code_review` {`required`, `status`, `report_paths`}, `tdd` {`status`,
`test_id`, `mutation_records`}, `pr` [..]), `blocker` {`kind`, `detail`},
`next_decision` {`actor`, `command`, `why`}, `decisions` {`strategy`
{`selected`, `ref_id`, `reused`}, `worktree` {`recommendation`,
`user_decision`, `ref_binding`}}.

`current_action.verdict`, `rule`, `role` and `reasons` are copied from
`decide(snapshot)` for the snapshot `buildSnapshot` returned. When
`buildSnapshot` reports problems, they are the dispatcher CLI's own
`needs_llm` with those problems as reasons. No rule logic is re-implemented.

### D3 Next decision (closed table, first match)

| Dispatcher result | actor | command | why |
|---|---|---|---|
| buildSnapshot problems | loop | /aai-loop | the loop repairs STATE before its first tick |
| no_action rule 1 | owner | /aai-loop | project_status is paused; unpause it first |
| no_action rule 2 | owner | /aai-hitl | the recorded human question |
| dispatch rule 8 with recommendation required or ceremony 3 | owner | /aai-worktree gate | protected isolation keeps its human gate |
| no_action rule 14 (already_flushed) | loop | /aai-pr | validation and review satisfied, metrics flushed: open the pull request |
| no_action reason scope_complete_no_open_intake | owner | /aai-ship | nothing open: state the next need |
| any other dispatch | loop | /aai-loop | dispatch of the named role and rule |
| needs_llm, or any other no_action | loop | /aai-loop | the loop takes the named edge |

The actor mapping for rule 8 mirrors SKILL_SHIP autopilot default 2. The
command strings are literal.

### D4 Blocker (closed, first match)

1. `state_invalid` with the problems joined, when `buildSnapshot` reports any.
2. `human_input` with `human_input.question`, else `blocking_reason`, when
   `human_input.required` is true (stagnation and run-budget escalations land
   here, since the loop records them as human input).
3. `needs_llm` with the reasons, when the verdict is `needs_llm`.
4. `failing_gate` with `validation` or `code_review`, when
   `last_validation.status` is `fail` or `code_review.status` is `fail`.
5. `none` otherwise.

### D5 Evidence sources

- validation: `last_validation` (`status`, `ref_id`, `evidence_paths`);
  `for_focus` is true only when its `ref_id` equals the focus ref.
- review: `code_review` (`required`, `status`, `report_paths`).
- tdd: `tdd_cycle.status` and `test_id` when `tdd_cycle.spec_path` equals the
  focus spec path, else `none`; `mutation_records` is the count of
  `mutation-TEST-*.txt` files in `docs/ai/tdd/<spec frontmatter id>/` (0 when
  the directory is absent).
- pr: `links.pr` of the focus spec's frontmatter, else of the intake at
  `current_focus.primary_path`, else empty.

### D6 Recorded decisions view

- strategy: `implementation_strategy.selected` and `ref_id`; `reused` is true
  only when that `ref_id` equals the focus ref. This is the same comparison
  `buildSnapshot` makes; the view shows it, it decides nothing.
- worktree: `recommendation` and `user_decision`, with `ref_binding: none`
  printed literally, because the block carries no ref (M2, D9).

### D7 Already-done probe

`probe` reports four effects for the focus ref and branch. Branch is
`--branch`, else `git branch --show-current`; empty means detached.

| Effect | done when | not_done when | unknown or other |
|---|---|---|---|
| pushed | `git ls-remote origin refs/heads/<branch>` sha equals `git rev-parse <branch>` | the remote ref is absent, or its sha differs (detail names both shas) | unknown: no origin remote, ls-remote failed, or no branch |
| pr_open | `adapter.listDependents(branch, 'head')` returns one or more numbers (listed) | it returns an empty list | unknown: a read failure (detail is the adapter reason); skipped: platform unknown or none (generic adapter) |
| closed | `close_event_present` and not `close_event_superseded_by_reopen` | otherwise | not_applicable: no focus |
| flushed | snapshot `flushed` | otherwise | not_applicable: no focus |

- Text mode prints one line per effect: `<effect>: <state>[ <detail>]`,
  preceded by `probe: <ref_id or none> branch=<branch or none>`. `--json`
  prints `{ref_id, branch, effects: {pushed, pr_open, closed, flushed}}`, each
  effect `{state, detail}` and `pr_open` also `prs`.
- The probe ends with one derived line `resume: <verdict>` (and a `resume`
  string key in `--json`), computed read-only from the effects above and the
  close ledger: `merge pr=<n>` when the ride's item is closed, `pr_open` is
  done (the first listed number) and `pushed` is done at head; `pr_step5
  ref=<slug>` when it is closed and the branch is not pushed at head (even
  with an open PR, since step 5 pushes and skips the create) or has no open
  PR; `loop` when the focus is set and not closed, checked before the branch
  test so a ride in flight on a detached HEAD still resumes; `none`
  otherwise. When `pr_open` is unknown (the PR list could not be read) the
  fail-safe rule applies: `pr_step5` only when `pushed` is not_done, else
  `none`, never a merge claim. Only the first of several open PRs is named. With the focus cleared (the close
  ceremony clears it), the item counts as closed only when EVENTS holds a
  `work_item_closed` event whose `ref` equals the branch name after its first
  slash (`feat/<slug>` gives `<slug>`) or the whole branch name, with no later
  `doc_lifecycle` from done for that ref. `merge` and `pr_step5` also require
  the branch not to be the base: origin's default branch from
  `git symbolic-ref refs/remotes/origin/HEAD`, else STATE `worktree.base_ref`,
  else `main`. An invalid STATE gives `none`; a detached HEAD gives `none`
  unless a focus is set and not closed.
- The probe never pushes, never creates or edits a pull request and never
  writes a ledger. The adapter is built with `createAdapter(platform, { cwd })`
  and called only through `listDependents(branch, 'head')`.

### D8 Prompt wiring (no decision logic changes)

- `.aai/SKILL_SHIP.prompt.md` INPUT: with neither a need nor a path, first run
  `node .aai/scripts/ride-status.mjs --json` (`state_invalid` stops), then
  `ride-status.mjs probe`, and act on its `resume:` line: `merge pr=<n>` stops
  and points to `/aai-merge <n>`; `pr_step5 ref=<slug>` runs SKILL_PR
  PRECONDITIONS step 0 through step 5 (step 3b included), after a `set-focus` for
  the slug because the branch guard refuses a cleared focus, taking `--type`
  and `--path` from the slug's closed primary doc; `loop` resumes at RUN
  step 2; `none` goes on to `ride-select.mjs show`.
- `.aai/SKILL_SHIP.prompt.md` step 5: the prose "If unattended chaining
  already opened a PR for the current `ref_id`, report that URL and skip a
  second create." is replaced by a sentence naming
  `ride-status.mjs probe`: `pr_open: done` means report that PR and skip the
  create.
- `.aai/SKILL_PR.prompt.md` step 5, immediately before the
  `git push -u origin <branch>` line: run `node .aai/scripts/ride-status.mjs
  probe`; `pushed: done` skips the push, `pr_open: done` skips the create and
  passes the listed number to `watch-ci.mjs --pr`; `unknown` or `skipped`
  proceeds as today.
- `.aai/SKILL_LOOP.prompt.md` TICK LOG FORMAT: after the LOOP SUMMARY block,
  print the output of `node .aai/scripts/ride-status.mjs` verbatim.
- Total growth of the `.aai/*.prompt.md` glob at most 900 B, measured with
  `cat .aai/*.prompt.md | /usr/bin/wc -c` against `51840bde`, credited 1:1 as
  one JUSTIFIED_ADDITIONS entry naming ride-status-and-resume in
  tests/skills/lib/prompt-diet-ledger.sh, and the TEST-012 pin in
  tests/skills/test-aai-prompt-diet.sh moves by the same bytes from 64396.
  ORCHESTRATION.prompt.md and AGENTS.md are not touched.

### D9 Worktree decision ref binding is deferred (disclosed)

The intake asks that a decision recorded for another ref is never reused.
That holds for strategy today (M3). For the worktree decision it does not
(M2), and the only complete fix writes a `ref_id` from `state.mjs
set-worktree` and compares it in `buildSnapshot`, which makes this ride L3.
The owner bounded this slice to non-protected surfaces, so this slice ships
the visibility (`ref_binding=none` in every status) and the close-out files
`fu-worktree-decision-not-ref-bound` (P2) naming the fix: set-worktree stamps
`ref_id` like set-strategy, `buildSnapshot` treats a decided worktree whose
`ref_id` names another ref as `undecided`, a legacy block without `ref_id`
keeps today's behavior, and metrics-flush's full reset nulls it. This is a
scope narrowing against the intake; the owner may promote it into this ride
at L3 instead.
The owner accepted this narrowing at validation round 1 (HITL, decisions.jsonl
type hitl, docs/ai/reports/HITL-ride-status-and-resume-d9.md); the gap stays
open as the P2 follow-up.

## Acceptance Criteria Mapping

- Intake AC-01 (four fields, text and json, no focus, no writes) maps to
  Spec-AC-01, Spec-AC-02 and Spec-AC-03.
- Intake AC-02 (human-input blocker and owner; PR step next) maps to
  Spec-AC-05. The next-action source rule (decide(), never a reimplementation)
  maps to Spec-AC-04.
- Intake AC-03 (already-done probe, stubbed platform CLI, never performs the
  effect) maps to Spec-AC-07, Spec-AC-08 and Spec-AC-09.
- Intake AC-04 (recorded decisions not asked again, foreign ref not reused):
  the strategy half and the not-asked-again half are already satisfied (M3)
  and pinned by SPEC-0192 TEST-005 and rule 8; Spec-AC-06 makes them visible
  in the status view. The worktree foreign-ref half is deferred (D9).
- Intake AC-05 (cross-platform) maps to Spec-AC-11 (Node-only, no launcher,
  argument-array child processes).
- Intake scope "wire the status command into the canonical prompts" and the
  resume path map to Spec-AC-10.
- Intake scope "product doc, CHANGELOG, RFC-0017 phase 4 row" is close-out,
  not an implementation AC (see Close-out steps), so ledger and product writes
  stay out of the validated tree.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN ride-status.mjs runs on a fixture STATE with a focus THEN text mode prints the six D2 lines in order with phase, status, validation status and evidence path, review status and report path, tdd mutation record count and pr link taken from that fixture, and --json prints the same values under the D2 keys | done | docs/ai/tdd/ride-status-and-resume/green/green-TEST-3144.log, docs/ai/tdd/ride-status-and-resume/green/green-TEST-3145.log | — | D2 D5 |
| Spec-AC-02 | WHEN current_focus.ref_id is null THEN the first line is ride: none (no current focus), the five other labels are printed, --json carries ref_id null, and the exit code is 0 | done | docs/ai/tdd/ride-status-and-resume/green/green-TEST-3146.log | — | D2 |
| Spec-AC-03 | WHEN status or probe runs on any test fixture THEN computeTreeHash of the fixture root and the STATE bytes are identical before and after, and the gh stub and the bare origin record no write | done | docs/ai/tdd/ride-status-and-resume/green/green-TEST-3147.log | — | D1 D7 |
| Spec-AC-04 | WHEN ride-status.mjs --json and orchestration-dispatch.mjs (no --confirm) run on the same fixture THEN current_action verdict, rule, role and reasons equal the dispatcher JSON for at least five fixtures covering a dispatch, rule 2, rule 14 no_action, a needs_llm edge and an invalid STATE | done | docs/ai/tdd/ride-status-and-resume/green/green-TEST-3148.log | — | D2 |
| Spec-AC-05 | WHEN the fixture has human_input.required true THEN blocker is human_input with the question text and next decision is owner /aai-hitl; WHEN validation and review pass for the focus and METRICS holds its flush record THEN next decision is loop /aai-pr; validation fail gives blocker failing_gate validation; rule 8 with recommendation required gives owner /aai-worktree gate and with recommended at ceremony 2 gives loop /aai-loop | done | docs/ai/tdd/ride-status-and-resume/green/green-TEST-3149.log, docs/ai/tdd/ride-status-and-resume/green/green-TEST-3150.log | — | D3 D4 |
| Spec-AC-06 | WHEN implementation_strategy.ref_id equals the focus ref THEN decisions show reused true and current action is not Planning rule 7; WHEN it names another ref THEN reused is false and current action is Planning rule 7; the worktree part always prints ref_binding none | done | docs/ai/tdd/ride-status-and-resume/green/green-TEST-3151.log | — | D6 |
| Spec-AC-07 | WHEN the probe runs in a fixture clone of a bare origin THEN pushed is done when the branch is pushed at its local head, not_done naming both shas when a local commit is ahead, not_done when the remote branch is absent, and unknown when there is no origin remote | done | docs/ai/tdd/ride-status-and-resume/green/green-TEST-3152.log | — | D7 |
| Spec-AC-08 | WHEN pr-config.yaml records platform github and a gh stub answers the head-branch list THEN pr_open is done with the listed number for one open PR, not_done for an empty list, unknown when the stub exits 1, and skipped when the recorded platform is none; the stub log holds only pr list calls with --head and the branch, and the bare origin refs are unchanged | done | docs/ai/tdd/ride-status-and-resume/green/green-TEST-3153.log, docs/ai/tdd/ride-status-and-resume/green/green-TEST-3154.log | — | D7 |
| Spec-AC-09 | WHEN EVENTS holds a work_item_closed event for the focus ref THEN closed is done, and not_done when a later doc_lifecycle from done supersedes it or no event exists; flushed is done exactly when METRICS holds the focus flush record; both are not_applicable with no focus; the probe also ends with one resume line, merge pr=n when closed with an open PR and a pushed head, pr_step5 ref=slug when closed without a pushed head (even with an open PR) or without an open PR (with the focus cleared the ref comes from a work_item_closed event for the current non-base branch), loop for an unclosed focus including on a detached HEAD, and none for a fresh branch, the base branch, a superseded close, an invalid STATE, or a closed ride whose PR list is unreadable while pushed at head (an unreadable list with no pushed head gives pr_step5), with a matching resume key in json | done | docs/ai/tdd/ride-status-and-resume/green/green-TEST-3155.log, docs/ai/tdd/ride-status-and-resume/green/green-TEST-3161.log, docs/ai/tdd/ride-status-and-resume/green/green-TEST-3163.log | — | D7 |
| Spec-AC-10 | SKILL_SHIP INPUT runs ride-status.mjs --json before ride-select.mjs show and stops on blocker kind state_invalid, then runs ride-status.mjs probe and acts on its resume line: resume merge pr=n stops and points to /aai-merge with the listed number, resume pr_step5 ref=slug runs SKILL_PR from PRECONDITIONS step 0 with a set-focus for the slug first and then step 5, resume loop resumes at RUN step 2, resume none runs ride-select.mjs show; SKILL_SHIP step 5 and SKILL_PR step 5 run ride-status.mjs probe before the push and create and skip each on done; SKILL_LOOP prints ride-status.mjs after the LOOP SUMMARY; the glob grows at most 900 B, credited by one ledger entry naming ride-status-and-resume, and test-aai-prompt-diet.sh TEST-010 and TEST-012 pass | done | docs/ai/tdd/ride-status-and-resume/green/green-TEST-3156.log, docs/ai/tdd/ride-status-and-resume/green/green-TEST-3157.log, docs/ai/tdd/ride-status-and-resume/green/green-TEST-3159.log, docs/ai/tdd/ride-status-and-resume/green/green-TEST-3160.log, docs/ai/tdd/ride-status-and-resume/green/green-TEST-3162.log, docs/ai/tdd/ride-status-and-resume/green/green-TEST-3164.log | — | D8 |
| Spec-AC-11 | PROFILES.yaml core lists .aai/scripts/ride-status.mjs; select-suites.mjs selects aai-ride-status for ride-status.mjs and for each of the three edited prompts; no ride-status.sh or ride-status.ps1 exists; the source holds no file-write call named in D1 and no shell option; ride-status.mjs is at most 400 lines | done | docs/ai/tdd/ride-status-and-resume/green/green-TEST-3158.log | — | D1 |

## Implementation plan

- `.aai/scripts/ride-status.mjs`: arg parsing (D1), `buildSnapshot` plus
  `decide` (D2), STATE readers for the evidence and decision blocks (D5, D6),
  the D3 and D4 tables as two small functions over the dispatcher output,
  text and JSON renderers, and the `probe` mode (D7). `runMain` from
  lib/cli-pipe-guard.mjs for the EPIPE-safe exit, as the dispatcher does.
- `tests/skills/lib/ride-status.test.mjs` (node:test): a fixture builder
  (temp dir, `git init` with its own `user.email` and `user.name`, STATE,
  docs/TECHNOLOGY.md, .aai/workflow/WORKFLOW.md, a frozen spec, EVENTS,
  METRICS, docs/ai/tdd/<id>/), a bare origin with `symbolic-ref HEAD`, and a
  `gh` stub on PATH that logs argv to a file and answers from a fixture file.
  Every case name starts with its TEST id.
- `tests/skills/test-aai-ride-status.sh`: the ride-handoff.sh shape
  (`node_cases <TEST-id>` with a TAP tally that refuses a vacuous match), plus
  the shell-native rows TEST-3156 to TEST-3158.
- Prompts per D8; the diet ledger entry and the TEST-012 pin last, after the
  prompt bytes are final (measure, then credit).
- `tests/skills/suite-map.yaml`: new `aai-ride-status` row with globs
  `.aai/scripts/ride-status.mjs`, `.aai/scripts/orchestration-dispatch.mjs`,
  `.aai/scripts/lib/platform-adapter.mjs`, `.aai/SKILL_SHIP.prompt.md`,
  `.aai/SKILL_PR.prompt.md`, `.aai/SKILL_LOOP.prompt.md`,
  `tests/skills/lib/ride-status.test.mjs`.
- `.aai/system/PROFILES.yaml`: core row for ride-status.mjs, with a one-line
  comment (SKILL_SHIP, SKILL_PR and SKILL_LOOP, all core, call it).
- Edge cases: a STATE without `tdd_cycle` or `code_review.report_paths`
  (read as none or empty); a spec without frontmatter `links.pr`; a detached
  HEAD for the probe; a branch name with a slash (`feat/x`); CRLF STATE (the
  engine already normalizes). No large JSON through argv; fixtures pass files.
- Suites run with `env -u AAI_ROLE` and under the suite's own
  `set -euo pipefail` (no bare `rc=$?`, no `grep | head` early-closing reader).

### Seams crossed

- ride-status.mjs and the dispatcher CLI on one fixture: both real programs
  run and their verdict, rule, role and reasons are compared (TEST-3148). A
  mocked `decide()` is not used anywhere.
- ride-status probe, lib/platform-adapter.mjs and the platform CLI: the real
  adapter spawns the stub `gh` first on PATH; the assertion reads the stub's
  argv log and the bare origin's refs on the other side (TEST-3153,
  TEST-3154).
- probe and git: a real bare origin and a real clone (TEST-3152).
- probe and the ledgers: EVENTS and METRICS written in the fixture are read
  through the real `buildSnapshot` (TEST-3155).
- Prompts and the script: the inspection rows assert the exact command the
  prompts name is the script's real CLI form (TEST-3156); the suite map and
  PROFILES rows run through the real select-suites.mjs (TEST-3158).
- Residual, not automatable: whether an agent following SKILL_SHIP actually
  resumes instead of re-intaking is an agent behavior; TEST-3156 proves the
  canon says it, not that a model obeys it.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3144 | Spec-AC-01 | integration | tests/skills/test-aai-ride-status.sh | node case TEST-3144: focus fixture (phase implementation, validation pass for the focus with one evidence path, review pass with one report path, tdd_cycle on the focus spec, two mutation records, spec links.pr 77); text mode prints the six labels in D2 order and each value from the fixture | `sed:s/next decision: /next step: /` on .aai/scripts/ride-status.mjs | green |
| TEST-3145 | Spec-AC-01 | integration | tests/skills/test-aai-ride-status.sh | node case TEST-3145: the same fixture with --json parses as one object whose D2 keys carry the same values (evidence_paths, report_paths, mutation_records 2, pr 77) | `sed:s/next_decision/nextx_decision/` on .aai/scripts/ride-status.mjs | green |
| TEST-3146 | Spec-AC-02 | integration | tests/skills/test-aai-ride-status.sh | node case TEST-3146: fixture with current_focus.ref_id null; first line equals ride: none (no current focus), the five other labels follow, exit 0; --json ref_id is null | `sed:s/ride: none \(no current focus\)/ride: none/` on .aai/scripts/ride-status.mjs | green |
| TEST-3147 | Spec-AC-03 | integration | tests/skills/test-aai-ride-status.sh | node case TEST-3147: for three fixtures (focus, no focus, invalid STATE) runs status, status --json and probe --json; computeTreeHash of the root and the STATE sha256 are equal before and after each run | `sed:s/const \{ snapshot, problems \} = buildSnapshot\(statePath, root\);/fs.appendFileSync(statePath, "# x\n"); const { snapshot, problems } = buildSnapshot(statePath, root);/` on .aai/scripts/ride-status.mjs | green |
| TEST-3148 | Spec-AC-04 | integration | tests/skills/test-aai-ride-status.sh | node case TEST-3148: five fixtures (TDD dispatch rule 9a, human input rule 2, flushed pass rule 14, review_staleness_unknown needs_llm, duplicate top-level key); runs the real orchestration-dispatch.mjs and ride-status.mjs --json on each and asserts verdict, rule, role and reasons are equal | `sed:s/else d = decide\(snapshot\);/else d = decide({ ...snapshot, human_input_required: true });/` on .aai/scripts/ride-status.mjs | green |
| TEST-3149 | Spec-AC-05 | integration | tests/skills/test-aai-ride-status.sh | node case TEST-3149: human_input.required true with a question gives blocker human_input with that question and next decision owner /aai-hitl; validation fail gives blocker failing_gate validation and actor loop; the needs_llm fixture gives blocker needs_llm with its reason | `sed:s/\/aai-hitl/\/aai-loop/` on .aai/scripts/ride-status.mjs | green |
| TEST-3150 | Spec-AC-05 | integration | tests/skills/test-aai-ride-status.sh | node case TEST-3150: validation pass and review pass for the focus plus a METRICS flush record gives next decision loop /aai-pr; the same without the flush record gives loop /aai-loop (Metrics Flush dispatch); rule 8 with recommendation required gives owner /aai-worktree gate; recommended at ceremony 2 gives loop /aai-loop | `sed:s/\/aai-pr/\/aai-loop/` on .aai/scripts/ride-status.mjs | green |
| TEST-3151 | Spec-AC-06 | integration | tests/skills/test-aai-ride-status.sh | node case TEST-3151: frozen spec, phase planning done, strategy tdd bound to the focus gives reused true and role TDD Implementation; the same strategy bound to OTHER-1 gives reused false and role Planning rule 7; both print ref_binding none | `sed:s/reused: focusRef != null && stratRef === focusRef/reused: focusRef != null \&\& stratRef !== focusRef/` on .aai/scripts/ride-status.mjs | green |
| TEST-3152 | Spec-AC-07 | integration | tests/skills/test-aai-ride-status.sh | node case TEST-3152: bare origin plus clone on branch feat/x; pushed at head gives done; one local commit more gives not_done naming both shas; a never-pushed branch gives not_done; a clone with origin removed gives unknown | `sed:s/ls-remote/ls-remotex/` on .aai/scripts/ride-status.mjs | green |
| TEST-3153 | Spec-AC-08 | integration | tests/skills/test-aai-ride-status.sh | node case TEST-3153: pr-config.yaml platform github, gh stub first on PATH; stub answering one number gives pr_open done with prs [41]; an empty list gives not_done; stub exit 1 gives unknown; platform none gives skipped with no stub call | `sed:s/'head'/'base'/` on .aai/scripts/ride-status.mjs | green |
| TEST-3154 | Spec-AC-08 | contract | tests/skills/test-aai-ride-status.sh | node case TEST-3154: after every probe run of TEST-3153 the stub argv log holds only lines starting pr list and containing --head feat/x, and git ls-remote of the bare origin is byte-identical before and after | `sed:s/listDependents\(branch, 'head'\)/prView(branch)/` on .aai/scripts/ride-status.mjs that makes the probe call the adapter with a pr view argument list | green |
| TEST-3155 | Spec-AC-09 | integration | tests/skills/test-aai-ride-status.sh | node case TEST-3155: EVENTS with a work_item_closed line for the focus gives closed done; adding a later doc_lifecycle line with payload from done gives not_done; no event gives not_done; METRICS flush record gives flushed done, none gives not_done; a no-focus fixture gives not_applicable for both | `sed:s/close_event_superseded_by_reopen/close_event_present/` on .aai/scripts/ride-status.mjs | green |
| TEST-3156 | Spec-AC-10 | inspection | tests/skills/test-aai-ride-status.sh | test_3156: in SKILL_SHIP the INPUT block names ride-status.mjs --json before ride-select.mjs show and names RUN step 2; the step 5 line names ride-status.mjs probe and no longer holds If unattended chaining already opened; in SKILL_PR step 5 ride-status.mjs probe precedes the git push -u origin line and names pushed and pr_open with done; SKILL_LOOP names node .aai/scripts/ride-status.mjs after the LOOP SUMMARY block | `sed:s/ride-status.mjs probe/ride-status.mjs prob/` on .aai/SKILL_PR.prompt.md | green |
| TEST-3157 | Spec-AC-10 | contract | tests/skills/test-aai-ride-status.sh | test_3157: tests/skills/lib/prompt-diet-ledger.sh carries exactly one JUSTIFIED_ADDITIONS entry naming ride-status-and-resume with a leading byte count from 1 to 900; the Verification run of test-aai-prompt-diet.sh proves TEST-010 and TEST-012 | `sed:s/ ride-status-and-resume / ride-status-and-resumx /` on tests/skills/lib/prompt-diet-ledger.sh | green |
| TEST-3158 | Spec-AC-11 | contract | tests/skills/test-aai-ride-status.sh | test_3158: PROFILES.yaml core holds the ride-status.mjs row; the real select-suites.mjs selects aai-ride-status for ride-status.mjs and each of the three prompts; no ride-status.sh or ride-status.ps1 under .aai/scripts; the source holds none of the D1 write calls and no shell true; line count at most 400 | `sed:s/  - \.aai\/scripts\/ride-status\.mjs/  - .aai\/scripts\/ride-statusx.mjs/` on .aai/system/PROFILES.yaml | green |
| TEST-3159 | Spec-AC-10 | integration | tests/skills/test-aai-ride-status.sh | node case TEST-3159: a fixture STATE with a duplicate top-level key gives ref_id null and blocker state_invalid while a no-focus fixture gives ref_id null and a different blocker kind; SKILL_SHIP INPUT names state_invalid and STOP before ride-select.mjs show | `sed:s/state_invalid/state_ok/` on .aai/SKILL_SHIP.prompt.md | green |
| TEST-3160 | Spec-AC-10 | integration | tests/skills/test-aai-ride-status.sh | node case TEST-3160: an unclosed focus fixture and a close superseded by a reopen give resume loop and a closed focus fixture does not; SKILL_SHIP INPUT names RUN step 2 exactly once and inside the resume loop clause | `sed:s/`resume: merge pr=<n>`: STOP/`resume: merge pr=<n>`: RUN step 2/` on .aai/SKILL_SHIP.prompt.md | green |
| TEST-3161 | Spec-AC-09 | integration | tests/skills/test-aai-ride-status.sh | node case TEST-3161: probe prints resume as its last line and json carries the same string; fixtures give none for a fresh feat/new-idea with no ride, for another ref close, for the base branch, for a superseded close and for an invalid STATE; pr_step5 ref=demo for a cleared focus with a matching close event unpushed or behind and for a closed focus unpushed; merge pr=520 with a gh stub listing 520 and pr_step5 when the list is empty | `sed:s/return `pr_step5/return `pr_step4/` on .aai/scripts/ride-status.mjs | green |
| TEST-3162 | Spec-AC-10 | inspection | tests/skills/test-aai-ride-status.sh | node case TEST-3162: each of the four resume clauses of SKILL_SHIP INPUT holds its own action: merge has STOP and /aai-merge n and no resume of anything, pr_step5 has SKILL_PR, PRECONDITIONS step 0, set-focus and step 5 and no RUN step 2, loop has RUN step 2 and no SKILL_PR, none has ride-select.mjs show; INPUT runs ride-status.mjs probe and no longer holds non-base or pushed: not_done | `sed:s/PRECONDITIONS step 0/PRECONDITIONS step 5/` on .aai/SKILL_SHIP.prompt.md | green |
| TEST-3163 | Spec-AC-09 | integration | tests/skills/test-aai-ride-status.sh | node case TEST-3163: a focused unclosed ride on a detached HEAD gives loop and a closed one gives none; a closed ride with a gh stub listing 520 and a local commit ahead of origin gives pr_step5 and after the push gives merge pr=520; with the stub failing, pushed at head gives none and a local commit ahead gives pr_step5 | `sed:s/ && pushed.state === 'done'//` on .aai/scripts/ride-status.mjs | green |
| TEST-3164 | Spec-AC-10 | inspection | tests/skills/test-aai-ride-status.sh | node case TEST-3164: the pr_step5 clause of SKILL_SHIP INPUT names --type and --path and says PRECONDITIONS through step 5 | `sed:s/step 0 through step 5/step 0, then step 5/` on .aai/SKILL_SHIP.prompt.md | green |

RED plan, observed on the baseline `51840bde` before each fix and stored
under `docs/ai/tdd/ride-status-and-resume/red/`:

- TEST-3144 to TEST-3155: `.aai/scripts/ride-status.mjs` does not exist; each
  node case fails on the missing module or a non-zero exit.
- TEST-3156: SKILL_SHIP INPUT names no ride-status.mjs; SKILL_PR step 5 has
  no probe line.
- TEST-3157: the ledger has no ride-status-and-resume entry.
- TEST-3158: PROFILES and the suite map lack the rows.

TDD run split (about three to four ACs per run):

- Run A: Spec-AC-01 to Spec-AC-04 (TEST-3144 to TEST-3148).
- Run B: Spec-AC-05, Spec-AC-06, Spec-AC-11 (TEST-3149 to TEST-3151,
  TEST-3158).
- Run C: Spec-AC-07 to Spec-AC-10 (TEST-3152 to TEST-3157); the diet entry
  last.

## Verification

- Suites, one per call, each with
  `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/<suite>.sh`:
  `test-aai-ride-status.sh`, `test-aai-orchestration-dispatch.sh`,
  `test-aai-prompt-diet.sh`, `test-aai-verify-gate.sh` (shares the diet
  ledger), `test-aai-ride-handoff.sh` (SKILL_SHIP pins),
  `test-aai-layer-profiles.sh`, `test-aai-hygiene-pack.sh` (one suite-map row
  per suite), and whatever
  `node .aai/scripts/select-suites.mjs --base-ref main` selects plus CORE.
  Intermediate rounds run selected plus CORE; one full sweep before close
  with `AAI_TEST_TIMEOUT=3600`.
- `node .aai/scripts/ride-status.mjs` and `node .aai/scripts/ride-status.mjs
  probe` on the live repo exit 0 and print the D2 and D7 lines.
- `node .aai/scripts/spec-lint.mjs --path <this spec>` exits 0.
- `node .aai/scripts/mutation-gate.mjs --spec <this spec>` exits 0 before
  close.
- PASS criteria: every TEST row green, every Spec-AC terminal, mutation gate
  passes.

## Close-out steps (after LOOP COMPLETE, not implementation ACs)

Run by the orchestrator after flush, before the PR. After them, run
`set-code-review` again with this file list as scope.

1. File `fu-worktree-decision-not-ref-bound` (P2) with
   `node .aai/scripts/follow-ups.mjs add`, text from D9.
2. Product doc `docs/product/ride-status-and-resume.md` from
   .aai/templates/PRODUCT_TEMPLATE.md (the intake's `capability:`).
3. RFC-0017 Rollout Status phase 4 row: append this slice (status view,
   already-done probe, /aai-ship resume) and set the row `done`, naming
   `fu-worktree-decision-not-ref-bound` as the residual. Frontmatter
   `status: implementing` and `umbrella: true` stay; phases 0 and 5 remain.
4. CHANGELOG.md: one `## [unreleased] — <title>` heading entry; the prompts
   are shipped surfaces, so `release-notes-gate.mjs --staged` must pass.
5. Regenerate docs/INDEX.md.

## Evidence contract

For each artifact, record the ref_id, the Spec-AC and TEST links, the command,
the exit code, the evidence path, and the commit SHA or diff range.

### Evidence by strategy

tdd: a stored RED artifact per AC-gating test under
docs/ai/tdd/ride-status-and-resume/red/, a mutation record per Test Plan row
under docs/ai/tdd/spec-ride-status-and-resume/, and green suite outputs.

## Files Implementation touches

- .aai/scripts/ride-status.mjs (new)
- tests/skills/lib/ride-status.test.mjs (new)
- tests/skills/test-aai-ride-status.sh (new)
- tests/skills/suite-map.yaml
- .aai/system/PROFILES.yaml (core row for the new script)
- .aai/SKILL_SHIP.prompt.md
- .aai/SKILL_PR.prompt.md
- .aai/SKILL_LOOP.prompt.md
- tests/skills/lib/prompt-diet-ledger.sh
- tests/skills/test-aai-prompt-diet.sh (TEST-012 pin)
- docs/issues/CHANGE-0238-ride-status-and-resume.md
- docs/specs/SPEC-0264-spec-ride-status-and-resume.md
- docs/product/ride-status-and-resume.md (close-out)
- docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md (close-out)
- CHANGELOG.md (close-out)
- docs/ai/decisions.jsonl (append-only: the D9 follow-up)
- docs/INDEX.md (regenerated)
- docs/ai/tdd/** (append-only evidence)

One new `.aai/**` file (ride-status.mjs) is classified in PROFILES.yaml core
(TEST-3158). Three prompt-corpus files grow, so one diet-ledger entry and the
TEST-012 pin are owed (TEST-3157). Not touched: state.mjs, lib/state-engine.mjs,
lib/state-core.mjs, orchestration-dispatch.mjs, metrics-flush.mjs,
ride-handoff.mjs, ORCHESTRATION.prompt.md, AGENTS.md.

## Risks and rollback

- A STATE carrying a stale focus makes a no-argument `/aai-ship` resume that
  ride instead of asking the roadmap. This is the intended behavior and the
  status line names the ride; the owner can pass a need or a path to start
  something else.
- The probe's `pushed` reads the network through `git ls-remote origin`; an
  offline run reads `unknown` and the prompts proceed as today, so the probe
  can only skip an effect, never block one.
- The D3 actor table is a mapping over the dispatcher's output; if a new
  dispatcher rule appears, it falls into the last row (loop /aai-loop) rather
  than breaking. TEST-3148 keeps the action itself bound to `decide()`.
- The worktree decision leak (M2) stays until `fu-worktree-decision-not-ref-bound`
  lands (D9). The status view names it on every run.
- Rollback: revert the PR. Nothing writes state or ledgers, so nothing needs
  undoing beyond the revert.

## Registry disposition

`node .aai/scripts/follow-ups.mjs list` (257 open) has no item on a ride
status view, the resume path, a duplicate push or PR create, or the worktree
decision binding. Related, left open: `fu-release-marker-per-ref` and
`fu-release-normalized-refusal-recovery` (release resume, a different
journal), `fu-shared-page-check-flags-own-pr` (pr-platform push check).

## Registry items closed by this scope

none
