---
id: spec-close-ceremony-fires-only-via-aai-pr
type: spec
number: 175
status: done
ceremony_level: 2
links:
  requirement: docs/issues/ISSUE-0081-close-ceremony-fires-only-via-aai-pr.md
  rfc: null
  pr:
    - TBD
  commits:
    - b5cfa6f0
---

# Spec — the close ceremony fires on the merge, not on the command that opened the PR

SPEC-FROZEN: true

## Links
- Requirement: `docs/issues/ISSUE-0081-close-ceremony-fires-only-via-aai-pr.md` (upstream GitHub issue #352, quoted there as untrusted data)
- Roadmap: the MAINTENANCE half of the pair whose capability half `spec-simple-and-friendly-to-use` (SPEC-0172, PR #355) is done — `docs/ai/roadmap.yaml`, wave 1
- Reused, not reimplemented: `.aai/scripts/close-work-item.mjs` (the whole close transaction; hash-pinned by four suites and NOT edited here), `.aai/scripts/lib/docs-audit-core.mjs` `scanAuditDocs` (what counts as a doc), `.aai/scripts/lib/docs-model.mjs` `parseFrontmatter` + `TERMINAL_DOC_STATUS`, `.aai/scripts/lib/cli-pipe-guard.mjs`, `.aai/scripts/docs-audit.mjs --check --strict` (the after-state assertion), `.aai/scripts/golden-flow.mjs` fixture shape (bare origin with `HEAD -> refs/heads/main`)
- Technology contract: `docs/TECHNOLOGY.md` (Node stdlib only, zero dependencies, bash 3.2 suites, PowerShell mirrors only where an installer or runner already has one)

Registry items closed by this scope: none. `node .aai/scripts/follow-ups.mjs list` at plan time reports shown=151 open=151 closed=207 total=358. Items whose subject this scope touches, and why each stays open: `fu-ac-flip-must-precede-close` (P3) is about the ORDER of the AC-Status flip inside `SKILL_PR` step 4c — this scope adds a second, route-independent entry point to the same ceremony and changes no ordering inside it; `fu-overview-shows-closed-ride-inflight` (P2) is STATE having no terminal phase after a close, downstream of the close and untouched here; `fu-orchestrator-does-not-watch-ci` (P2) is the orchestrator not watching CI after a push — this scope ADDS a CI signal that follow-up is about consuming, and closing it would require the orchestrator change this scope does not make; `fu-ceremony-test016-blanket-byte-pin` (P2) is a blanket byte pin on `docs-audit-core.mjs`, which this scope does not edit (it only imports from it).

## Amendment (post-freeze, 2026-09-11 and 2026-09-12 — remediation and owner acceptance)

This is a FROZEN spec, amended at remediation and disclosed here rather than
rewritten silently. `SPEC-FROZEN: true` is preserved; the mechanism is the
additive-with-disclosure convention `docs/specs/SPEC-0072-...md`,
`docs/specs/SPEC-0132-...md`, `docs/specs/SPEC-0153-...md` and
`docs/specs/SPEC-0163-...md` already established.

1. **The `code_with_open_doc` arm is REMOVED, on an explicit owner decision
   recorded 2026-09-11.** Independent Validation ran a CI-faithful replay of
   40 real pushes on this repository's own `main` (each commit checked out
   detached, the gate run over `<sha>^..<sha>`). Per-arm precision on that
   corpus: `frozen_work_merged` 1 true / 0 false; `code_with_open_doc` 1
   true / 7 false, with 3 of the 4 firing pushes carrying ZERO true items —
   "the doc was added by the same range" does not discriminate a delivery
   from a backlog intake filed alongside unrelated code (a squash-merged
   ride adds its own docs in the same commit whether or not the ride is
   done). D5 gives the CI job no dial, so every one of those false pushes
   would have turned `main` red. The owner weighed that against the arm's
   sole true positive (PRD-0001 at #355) and decided to drop the arm
   entirely rather than tune it. Removed from `.aai/scripts/close-reconcile.mjs`
   (D2, `computeItems` — the `rangeHasNonDoc` tracking it depended on is
   removed too) and from `tests/skills/test-aai-close-reconcile.sh`;
   confirmed ABSENT from `.github/workflows/close-gate.yml`, which invokes
   the CLI by name only and never referenced arm codes, so nothing there
   changes. D2 now names ONE arm.

   Spec-AC-01 is AMENDED below rather than retired: it traces to the
   intake's Expected Behavior bullet 1 ("closure depends on the merge, not
   the command"), which is still true and still needs a `--check`-mode
   positive test, so TEST-001 is repointed at the arm that remains —
   `frozen_work_merged` — instead of being deleted. TEST-003, TEST-004,
   TEST-006, TEST-009, TEST-010 and TEST-011's fixtures move from
   `status: draft` plus an incidental touched non-doc path to
   `status: implementing`, so each continues to exercise a firing item
   through the arm that remains; no test's OWN assertions change (paired
   close, append-only, pr-number-unknown refusal, workflow replay,
   route-independent close, the mutation control). Test ids stay stable.

2. **The recall gap this narrows was already open, and stays open on
   purpose.** Recall on the three documented post-merge close-ceremony
   escapes in this repository's history was 1 of 3 with BOTH arms in
   place, and stays 1 of 3 with `code_with_open_doc` removed: its one true
   positive (PRD-0001 at #355) is the SAME push where the paired spec
   `SPEC-0172` already fired `frozen_work_merged`, so that PUSH still turns
   the CI job red even though PRD-0001 itself no longer surfaces as its own
   named item — the escape this corpus counts as "detected" (`#356`
   reconciling `#355`) is detected via `SPEC-0172` either way. Two of the
   three escapes (`#350` reconciling `#349`, `#358`
   reconciling `#357`) went undetected under BOTH arms, because the doc
   already read `status: done` at the delivery sha the gate inspected —
   what those follow-up PRs actually reconciled was `links.commits` and
   close telemetry, not the frontmatter status this design reads. That is
   a limitation of D1/D2's whole shape (git-alone, status-driven), not
   something the removed arm was covering, and this remediation does not
   attempt a better discriminator (out of scope by the dispatch that
   authorized this amendment). Filed as `fu-close-gate-status-trigger-blind`
   (P2, already open in the follow-ups ledger) — the recall gap is
   knowingly left open there, not here.

3. **Non-blocking, recorded, not fixed (in scope discipline, not by
   oversight).**
   - Mutation M4 (`RANGE_BEFORE` env var renamed to a typo) leaves both
     TEST-008 and TEST-009 green: both supply the range through the
     script's own `RANGE_BEFORE`/`RANGE_SHA` contract directly rather than
     through a live GitHub Actions `env:` substitution, so neither catches
     a renamed variable in the workflow's `env:` block. Seam S4 stays
     half-covered. Recorded, not fixed.
   - `docs/issues/ISSUE-0081-close-ceremony-fires-only-via-aai-pr.md`'s
     Verification bullet 3 ("docs-audit reports the fixture false-open
     BEFORE the fix and clean after") is unmapped in the Acceptance
     Criteria Mapping above; only the "clean after" half is asserted
     anywhere in this spec's Test Plan (TEST-004). Recorded, not remapped.
   - `.aai/scripts/close-work-item.mjs` hardcodes `validation: pass` into
     its `work_item_closed` event. `close-reconcile.mjs --apply` is a
     second, route-independent entry point into that same hardcoding, for
     rides that by construction never ran the validation pipeline —
     `close-work-item.mjs` itself is PROTECTED (hash-pinned by four
     suites) and is not edited by this scope (D3). Recorded as **R6**
     below rather than fixed.

4. **ADDED 2026-09-12 — the frozen-marker branch of Spec-AC-01 ships untested,
   by owner acceptance.** Independent Validation round 2 (Opus 5, fresh
   context) widened the corpus replay to 150 pushes and confirmed both earlier
   blockers fixed: the shipped one-arm gate measured 2 true / 0 false, 100%
   precision, firing on 1.3% of pushes, against 69 items across 17 reddened
   pushes for the restored two-arm gate. The same round found one NEW gap of
   the same class as the mutation-control defect it had just cleared: removing
   `|| isFrozen` reddens nothing. The owner was given both remedies — one
   fixture, or acceptance as a disclosed residual — and chose acceptance. See
   R8. Nothing about the implementation changed for this item; only this
   disclosure was added.

5. **ADDED 2026-09-12 (code review round 3, docs/ai/reviews/review-20260911T222047Z.md)
   — BLOCKING-1 (the gate half-closed the pair and self-certified CLEAN)
   and BLOCKING-2 (`umbrella: true` was not exempt) fixed at cause in
   `computeItems()`; Spec-AC-08 corrected to state what the gate actually
   proves.**

   **BLOCKING-1.** `spec-freeze.mjs` is the SOLE writer of
   `status: implementing`, and writes it ONLY to `docs/specs/**` (census: 0
   of 268 `docs/issues` docs have ever carried it — 45 `draft`, 223 `done`).
   A primary/intake doc therefore never independently satisfies D2's arm,
   and `pairItems()` — which can only pair a spec TO a primary already
   present as an item — never saw it: `--apply` closed the spec alone,
   leaving the primary `draft` with `links.pr: []` (issue #352's own
   corruption, reproduced by the reviewer), and a repeat `--check` over the
   SAME range then read the spec fresh off disk at `done` (terminal,
   skipped) and the primary still `draft` and non-firing — CLEAN, over a
   half-closed pair. Fixed with a second pass in `computeItems()`: for
   every SPEC touched by the same range whose id is `spec-<primary id>`
   (`pairItems()`'s own naming convention, unchanged) and whose status
   shows the pair's delivery is underway or already recorded
   (`implementing`, the frozen marker, or already `done` — the
   half-closed-replay case), its primary becomes an item too whenever that
   primary is present in the SAME range and still non-terminal. `--apply`
   now closes both in the one transaction `pairItems()` already built;
   `--check` keeps reporting the primary instead of going CLEAN once it is
   a genuine item. Bounded deliberately to primary and spec BOTH touched by
   the same range (matching the reproduced corruption and this factory's
   single-squash-merge convention) — a spec-only range whose primary was
   never touched by any commit in the push is NOT covered; not reproduced,
   not required by the round-3 dispatch, left open.
   Covered by TEST-003 (the pairing fix, on the draft-intake +
   implementing-spec shape the corpus actually produces — TEST-003's own
   fixture moved OFF the both-`implementing` shape it used pre-round-3,
   which never exercised this gap) plus a second fixture in the same test
   proving a pre-existing half-closed pair never reads CLEAN.

   **BLOCKING-2.** `close-reconcile.mjs` carried zero `umbrella` handling,
   so a deliberately-open multi-phase parent (frontmatter `umbrella: true`,
   e.g. `docs/rfc/RFC-0012`, `status: implementing` today) fired
   `frozen_work_merged` on every child-phase delivery that merely touched
   it, with no dial (D5) and no legitimate clearing action — the parent is
   SUPPOSED to stay open. Fixed by reusing `docs-audit-core.mjs`'s OWN
   umbrella predicate verbatim (`String(fm.umbrella ?? '').toLowerCase()
   === 'true'`, read, not re-derived): a marked doc is skipped before
   either arm pass runs, so it can never become an item on its own account
   nor be resolved as a pairing primary. New Spec-AC-10 / TEST-013.
   Residual R2's earlier claim that nothing regressed from the missing
   umbrella awareness was itself wrong (the gate DID misfire on the
   umbrella parent's own delivery pushes, not just fail to reconcile a
   child into it) — corrected there.

   **Spec-AC-08 correction.** Independent Code Review's spec_compliance
   verdict (fail) found Spec-AC-08 proven only on a fixture whose intake
   doc itself reached `status: implementing` — a state 0 of 268
   `docs/issues` docs have ever carried, since `spec-freeze.mjs` never
   writes that status to an intake. TEST-010 and TEST-011 are rebuilt on
   the shape the corpus actually produces (intake `draft`, paired spec
   `implementing`), asserting the INTAKE doc specifically ends `done`; the
   AC row text below is corrected to match. TEST-003's fixture moves the
   same way for the same reason.

   Correction to Amendment item 1: "no test's OWN assertions change" was
   already false for TEST-011 at round 1 (Step A was added — recorded as a
   round-2 NON-BLOCKING finding, not fixed until now) and is false again
   here for TEST-003, TEST-010 and TEST-011, whose fixture SHAPES change in
   this round (a draft primary + implementing spec pair, replacing an
   independently-`implementing` primary). The invariant that DID hold, both
   times, is narrower than item 1 claimed: test IDs and what each ID is
   evidence FOR (Spec-AC mapping) stay stable; the fixtures and assertions
   inside a given ID have changed twice now, each time disclosed here.

6. **ADDED 2026-09-12 (round-4 code review,
   docs/ai/reviews/review-20260912T000107Z.md NB-1) — correction to Amendment
   item 5's disclosed bound: the real gap is the pairing KEY, not spec-only
   ranges.** Item 5 above named the bound as "a spec-only range whose primary
   was never touched by any commit in the push is NOT covered." That
   sentence is true but is not the bound the round-4 reviewer reproduced,
   and it undersells what is actually missing. `pairItems()` pairs a spec to
   a primary only when the spec's frontmatter id is the EXACT string
   `spec-<primary id>`. For 3 of 161 spec ids in this corpus that convention
   does not hold (example: `docs/specs/SPEC-0068`'s id
   `spec-metrics-flush-sweep` against its primary's own id
   `metrics-flush-strands-completed-refs`). For those pairs — even with BOTH
   primary and spec touched by the SAME range — the pairing pass never
   matches: `--apply` still closes the spec alone, the primary is left
   `draft` with `links.pr: []` (issue #352's corruption, surviving
   verbatim), and a repeat `--check` prints `CLEAN`. This is a strict
   narrowing of the pre-round-3 defect (which hit 100% of pairs) but is the
   SAME false-record shape, so it cannot be an accepted residual under H6.
   Filed as `fu-close-reconcile-pair-id-convention` (P2, open,
   `docs/ai/decisions.jsonl` 2026-09-12T00:03:51Z) rather than fixed in this
   round; not reproduced against, and not required by, the round-3 dispatch
   that authored item 5's original text.

## What is actually missing

The capability half already shipped the ENGINE of a route-independent check: `.aai/scripts/nothing-left-behind.mjs` names a `docs_open` class whose header cites this exact upstream issue. What it did NOT ship is a route-independent TRIGGER — the gate is invoked from one place, a bullet in `.aai/SKILL_PR.prompt.md` step 5, and it takes `--ref <slug>`, a value only the ride that is running knows. A PR opened with `gh pr create`, through the GitHub UI, or by a merge queue never reaches that bullet, and after the merge no `--ref` exists for anyone to pass.

Measured, this repository is the proof: `close-work-item.mjs` is named by `.aai/SKILL_PR.prompt.md` and by nothing else in `.aai/`. CHANGE-0177 shipped in PR #349 without its ceremony and needed a whole follow-up PR (#350) to reconcile the docs; CHANGE-0178, one ride later, ran it locally. Two adjacent rides, two outcomes, because the trigger is a command name.

`docs-audit.mjs` already classifies `probable-false-open` and `.github/workflows/docs-numbering.yml` already runs `docs-audit.mjs --check --strict` on every push to `main`. Neither closes the gap, for two separate reasons that this spec's design turns on:
1. It is REPORT-ONLY by design (`continue-on-error: true`, an `::warning::`, `doc_number_guard` gating only the enforce step). A warning on a green job is exactly the silence the issue reports.
2. Its false-open verdict needs DELIVERY EVIDENCE — `falseOpenEvidence` arms read a `work_item_closed` event, an `ac_evidence` event, a METRICS flush record, a terminal AC table, or a commit whose message mentions the doc id. Every one of those is an artifact the SKIPPED ceremony would have produced. A ride that never ran the ceremony leaves no evidence, so the heuristic that exists to catch it is the one thing it cannot catch. This is why the new gate reads the MERGE, not the ledgers.

## Design decisions

- **D1 — the trigger is the pushed range on the default branch, read with git alone.** New CLI `.aai/scripts/close-reconcile.mjs --range <A>..<B>`. Its whole input is `git diff --name-only <A>..<B>`, `git log --format=%H%x09%s <A>..<B>` and each touched doc's post-merge frontmatter. It never asks which command opened the PR, never calls a PR API, and needs no `--ref`: the range names the work. Every route that lands code on `main` — `/aai-pr`, `gh pr create` + `gh pr merge`, the GitHub UI, a merge queue, a direct push — produces exactly one pushed range, so exactly one thing triggers it.

- **D2 — one named delivery arm, so an intake-only PR is never a false positive.** A touched doc is an ITEM only when its post-merge frontmatter `status` is non-terminal (`TERMINAL_DOC_STATUS`, the shared list — not a second copy) AND the arm fires, printed with the item:
  - `frozen_work_merged` — the doc's own status is `implementing`, or the doc body carries the frozen marker line that `spec-freeze.mjs` writes. Frozen means work was in flight; the range landed it.
  A range that only ADDS a `draft` intake doc matches neither this arm nor any other and is CLEAN. This is the one false-positive class that would make the gate unusable downstream, and it is designed out rather than tuned out.
  **AMENDED 2026-09-11 (see `## Amendment`, item 1) — a second arm,
  `code_with_open_doc` (fired when the range ALSO touched a path
  `scanAuditDocs` does not admit as a doc: "code merged while the doc reads
  draft"), shipped at first implementation and was REMOVED here on an owner
  decision after a CI-faithful 40-push corpus replay measured it at 1 true /
  7 false with 3 of 4 firing pushes carrying zero true items. The recall gap
  this leaves is knowingly open, filed as `fu-close-gate-status-trigger-blind`.

- **D3 — the remediation is `close-work-item.mjs`, invoked as a child process, never re-implemented.** `--apply` spawns `node .aai/scripts/close-work-item.mjs --ref <slug> --pr <N> --commit <sha>` once per item, adding `--spec <spec-slug>` when the paired spec doc is in the same range. That script keeps sole ownership of the status flip, the links stamping, the event set, the self-verify and the rollback; `close-reconcile.mjs` contains no frontmatter write and no `EVENTS.jsonl` write of its own. `close-work-item.mjs` is hash-pinned by four suites and is not edited by this scope, so none of those pins move.

- **D4 — the PR number comes from the merge subject or it does not come at all.** `<N>` is the trailing `(#N)` of a commit subject in the range — the squash-merge convention every commit on this repository's `main` carries. When no subject in the range has one, the item is reported with `pr: unknown` and `--apply` REFUSES that item by name and exits non-zero, writing nothing for it. A guessed number is never stamped; this mirrors the discipline already encoded in `close-work-item.mjs`'s `TBD` sentinel, whose own header says the historical highest-plus-one read was "luck, not procedure".

- **D5 — loud at merge time is a CI job on push to main that FAILS.** `.github/workflows/close-gate.yml`, `on: push: branches: [main]`, runs `--check` over `${{ github.event.before }}..${{ github.sha }}` and, on a non-zero exit, emits one `::error::` per item and fails the job. No `continue-on-error`, no report-only dial. The justification for having no dial: on a push to `main` the merge has ALREADY happened, so this job gates nothing and blocks nobody — failing it is purely the notification, and the issue is specifically that the existing warning-shaped notification is invisible. An unusable `before` (the all-zero sha of a new branch or a force push, or an empty value on `workflow_dispatch`) falls back to `HEAD^..HEAD`; a range git cannot resolve is exit 2 and a failed job, never a silent pass.

- **D6 — docs-audit is the after-state assertion, not the detector.** After `--apply`, `docs-audit.mjs --check --strict --no-event` must be clean over the fixture. The gate detects from the merge; the audit confirms the corpus agrees. The two never share a verdict, so neither masks the other.

- **D7 — what this scope deliberately does not do.** No local `post-merge` git hook (a project with no CI stays uncovered — residual R1). No umbrella-parent reconciliation when a child closes (the issue's second half — a distinct capability over a parent/child relation this repository does not model — residual R2, corrected 2026-09-12: the earlier text here claimed the `umbrella: true` marker meant "nothing regresses"; code review round 3 BLOCKING-2 found the marker was not even READ by this gate, so an umbrella parent's OWN delivery pushes misfired `frozen_work_merged` — fixed, see Amendment item 5 and Spec-AC-10; R2 now names only the reconciliation gap that remains, not a false all-clear). No edit to `.aai/*.prompt.md` or `.aai/AGENTS.md`, and therefore no prompt-diet ledger true-up: the whole point is a trigger that is not prose an agent has to remember.

## Constitution deviations

None.

## Implementation strategy
- Strategy: tdd
- Rationale: every acceptance criterion here is a refusal or a non-refusal of a gate, and a gate that has never been observed failing is indistinguishable from one that cannot fire — the exact defect class the issue reports. RED first per arm is therefore the evidence, not the ceremony. STATE already carried `implementation_strategy.selected: tdd` with `source: intake`, but its recorded rationale names a DIFFERENT ref (`update-installs-ref-guard-undisclosed`), so it is a stale carry-over rather than a choice recorded for this scope; the VALUE is kept unchanged and only the rationale and source are re-recorded against this spec. Disclosed to the operator in the Planning return.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: the scope adds a CLI that SPAWNS the close ceremony and a workflow that runs on push to `main`. Its suite must merge into a fixture repository and assert real frontmatter writes and a real `EVENTS.jsonl` append, and HAZ-SCRATCH plus the shared-worktree incident of 2026-09-06 both say that kind of arm belongs outside the shipping tree. Not `required`: no `protected_paths_l3` surface is touched.
- User decision: undecided
- Base ref: main
- Worktree branch/path: <decided by Implementation Preparation>
- Inline review scope: `.aai/scripts/close-reconcile.mjs .github/workflows/close-gate.yml tests/skills/test-aai-close-reconcile.sh tests/skills/suite-map.yaml .aai/system/PROFILES.yaml docs/specs/SPEC-0175-spec-close-ceremony-fires-only-via-aai-pr.md docs/issues/ISSUE-0081-close-ceremony-fires-only-via-aai-pr.md`

## Acceptance Criteria Mapping
- Maps to: the intake's "Expected Behavior" bullet 1 (closure depends on the merge, not the command) -> Spec-AC-01, Spec-AC-03, Spec-AC-08
- Maps to: the intake's "Expected Behavior" bullet 2 (loud at or near merge time) -> Spec-AC-05, Spec-AC-06, Spec-AC-07
- Maps to: the intake's "Constraints / Risks" bullet 2 (close-work-item.mjs is hash-pinned) -> Spec-AC-04
- Maps to: the intake's "Constraints / Risks" bullet 3 (EVENTS.jsonl is append-only) -> Spec-AC-03
- Maps to: the intake's "Verification" bullet 2 (a mutation arm) -> Spec-AC-08
- Maps to: the closed companion-obligation list (a new `.aai/**` file) -> Spec-AC-09
- Maps to: code review round 3 BLOCKING-2 (an umbrella parent must never misfire this gate) -> Spec-AC-10 (ADDED 2026-09-12, Amendment item 5)

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN a pushed range leaves a non-terminal work-item doc at status implementing (or carrying the frozen marker), close-reconcile.mjs --check SHALL exit 1 and print one line per item naming the doc path, the arm frozen_work_merged, the delivery sha and the literal remediation command starting `node .aai/scripts/close-work-item.mjs --ref`. Verified by TEST-001 on a fixture repository. | done | docs/ai/tdd/green-close-reconcile-TEST-001-20260911T203049Z.log | — | AMENDED 2026-09-11 (see Amendment item 1); the reported gap, read from git alone |
| Spec-AC-02 | WHEN a pushed range only ADDS a draft intake doc and touches no path outside the scanAuditDocs corpus, close-reconcile.mjs --check SHALL exit 0 and print CLEAN. Verified by TEST-002. | done | docs/ai/tdd/green-close-reconcile-TEST-002-20260911T152431Z.log | — | intake-only PR is not a false positive |
| Spec-AC-03 | WHEN close-reconcile.mjs --apply runs over a range with one item, the doc SHALL afterwards read `status: done` with the parsed PR number in links.pr and the delivery sha in links.commits, a re-run of --check SHALL exit 0 printing CLEAN, docs-audit.mjs --check --strict --no-event SHALL exit 0 over the fixture, and the pre-apply bytes of docs/ai/EVENTS.jsonl SHALL remain a byte-exact prefix of the post-apply file; a paired primary+spec item SHALL close in ONE close-work-item.mjs invocation, and a range left half-closed (spec done, primary still non-terminal) SHALL NOT report CLEAN. Verified by TEST-003 and TEST-004. | done | docs/ai/tdd/green-close-reconcile-TEST-003-20260911T231850Z.log (red, BLOCKING-1: docs/ai/tdd/red-close-reconcile-TEST-003-20260911T224334Z.log) and TEST-004: docs/ai/tdd/green-close-reconcile-ALL-20260912T072943Z.log (full-suite green on the SHIPPED bytes; re-cited a second time 2026-09-12 per validation F1 - the NB-6 re-citation itself went stale when the round-4 NON-BLOCKING clearances landed 7.5h after that log) | — | HAZ-LEDGER asserted, not assumed; AMENDED 2026-09-12 (Amendment item 5, BLOCKING-1) — TEST-003's fixture moved to the draft-primary + implementing-spec shape the corpus produces, plus a half-closed-pair regression guard; TEST-004's citation RE-AMENDED 2026-09-12 (NB-6) — the prior log predated the TEST-003 fixture flip |
| Spec-AC-04 | The delivery commit SHALL leave .aai/scripts/close-work-item.mjs byte-identical to its base-ref version, measured by `git diff --exit-code <base>..HEAD -- .aai/scripts/close-work-item.mjs` exiting 0, and the four suites that hash-pin it SHALL stay green. Verified by TEST-005 and the suite run named in Verification. | done | docs/ai/tdd/green-close-reconcile-TEST-005-20260911T152431Z.log; four-suite pin run in tests/skills/results/ | — | the hash-pin constraint from the intake |
| Spec-AC-05 | WHEN no commit subject in the range carries a trailing `(#N)`, close-reconcile.mjs --apply SHALL exit non-zero, print a line naming that item and the reason pr-number-unknown, and leave the doc frontmatter byte-identical. Verified by TEST-006. | done | docs/ai/tdd/green-close-reconcile-ALL-20260912T072943Z.log (full-suite green on the SHIPPED bytes; re-cited a second time 2026-09-12 per validation F1 - the NB-6 re-citation itself went stale when the round-4 NON-BLOCKING clearances landed 7.5h after that log) | — | never a guessed PR number; citation RE-AMENDED 2026-09-12 (NB-6) — the prior log predated the round-3 remediation |
| Spec-AC-06 | WHEN --range is absent, empty, all-zero, or names a ref git cannot resolve, close-reconcile.mjs SHALL exit 2 with a message naming the offending range value, in both --check and --apply. Verified by TEST-007. | done | docs/ai/tdd/green-close-reconcile-TEST-007-20260911T152431Z.log | — | fail-closed, never a silent 0 |
| Spec-AC-07 | .github/workflows/close-gate.yml SHALL trigger on push to main, SHALL invoke close-reconcile.mjs --check with the pushed range, SHALL carry no continue-on-error key, and its command line run against a fixture with a non-clean range SHALL exit non-zero after printing at least one line beginning `::error::`. Verified by TEST-008 (structure) and TEST-009 (behavior). | done | docs/ai/tdd/green-close-reconcile-TEST-008-20260911T152431Z.log and TEST-009: docs/ai/tdd/green-close-reconcile-ALL-20260912T072943Z.log (full-suite green on the SHIPPED bytes; re-cited a second time 2026-09-12 per validation F1 - the NB-6 re-citation itself went stale when the round-4 NON-BLOCKING clearances landed 7.5h after that log) | — | the loud signal at merge time; TEST-009's citation RE-AMENDED 2026-09-12 (NB-6) — the prior log predated the round-3 remediation |
| Spec-AC-08 | A fixture ride that opens and merges its change WITHOUT ever invoking /aai-pr or .aai/SKILL_PR.prompt.md, whose INTAKE doc stays `draft` throughout (paired with a spec that reaches `implementing` — the shape spec-freeze.mjs and close-work-item.mjs actually produce; `implementing` never lands on an intake doc in this corpus) SHALL end with that INTAKE doc at `status: done` after the gate runs; and the MUTATION control, exercising the real close-reconcile.mjs then stubbing it to exit 0, SHALL first show the real binary flagging the fixture, then return the SAME intake doc to its original `draft` status when stubbed, and turn the arm red when the implementation is stubbed or absent. Verified by TEST-010 and TEST-011. | done | docs/ai/tdd/green-close-reconcile-TEST-010-20260911T224414Z.log (red: docs/ai/tdd/red-close-reconcile-TEST-010-20260911T224341Z.log) and TEST-011: docs/ai/tdd/green-close-reconcile-TEST-011-20260911T224414Z.log | — | AMENDED 2026-09-12 (Amendment item 5, code review round 3 spec_compliance non-compliant) — the prior row text was proven only on a fixture whose INTAKE doc itself reached `implementing`, a state 0 of 268 docs/issues docs have ever carried; corrected to the draft-intake + implementing-spec pair the corpus actually produces. AMENDED 2026-09-11 (see Amendment item 1) history: route independence plus the intake's mutation arm, now exercising the real binary (was tautological pre-remediation) |
| Spec-AC-09 | .aai/scripts/close-reconcile.mjs SHALL appear exactly once across the two lists in .aai/system/PROFILES.yaml and SHALL be mapped to a suite in tests/skills/suite-map.yaml, with tests/skills/test-aai-layer-profiles.sh and tests/skills/test-aai-hygiene-pack.sh green. Verified by TEST-012. | done | docs/ai/tdd/green-close-reconcile-TEST-012-20260911T152431Z.log; neighbour-suite run in tests/skills/results/ | — | closed companion-obligation list, new .aai file entry |
| Spec-AC-10 | ADDED 2026-09-12 (Amendment item 5, code review round 3 BLOCKING-2). WHEN a touched doc's frontmatter carries `umbrella: true` (docs-audit-core.mjs's own predicate, read verbatim, string-compared case-insensitively — never a second, weaker notion of it), close-reconcile.mjs SHALL treat that doc as exempt from every arm regardless of its own status, in both --check and --apply. Verified by TEST-013. | done | docs/ai/tdd/green-close-reconcile-TEST-013-20260911T224414Z.log (red: docs/ai/tdd/red-close-reconcile-TEST-013-20260911T224341Z.log) | — | a deliberately-open multi-phase parent (e.g. docs/rfc/RFC-0012) must never misfire this gate |

## Implementation plan

Components/modules affected:
- NEW `.aai/scripts/close-reconcile.mjs` — the gate. Node stdlib plus the shared libs named in Links. Grammar: `--range <A>..<B>` (required), `--root <dir>` (default `process.cwd()`), `--check` (default) or `--apply`. Exit 0 clean, 1 items found or an apply that could not complete, 2 usage or unresolvable range.
- NEW `.github/workflows/close-gate.yml` — `on: push: branches: [main]` plus `workflow_dispatch`, `permissions: contents: read`, `fetch-depth: 0`, node 20, one step that resolves the range and runs the CLI.
- NEW `tests/skills/test-aai-close-reconcile.sh` — the suite, bash 3.2, under the framework's own `set -euo pipefail`.
- EDIT `tests/skills/suite-map.yaml` — one suite entry mapping the CLI, the workflow and the suite.
- EDIT `.aai/system/PROFILES.yaml` — one `core` entry (the gate is workflow engine, not reporting).
- EDIT `docs/issues/ISSUE-0081-close-ceremony-fires-only-via-aai-pr.md` — closed by the ceremony at PR time, not by hand.
- NOT EDITED: `.aai/scripts/close-work-item.mjs`, `.aai/scripts/lib/docs-audit-core.mjs`, `.aai/scripts/lib/docs-model.mjs`, every `.aai/*.prompt.md`.

Data flows:
1. `git diff --name-only A..B` gives the changed path set; `scanAuditDocs(root)` splits it into docs and non-docs using the SAME admission predicate docs-audit uses.
2. Each changed doc is read at its post-merge state; `parseFrontmatter` gives `id` and `status`; `TERMINAL_DOC_STATUS` decides non-terminal.
3. `git log --format=%H%x09%s A..B` gives the delivery sha (newest commit in the range) and the PR number (trailing `(#N)` of any subject in the range, newest first).
4. `--check` prints and exits; `--apply` spawns `close-work-item.mjs` per item and re-reads the doc to confirm the flip before reporting success.

Edge cases:
- A range whose docs are all terminal already: CLEAN, exit 0, idempotent on re-run.
- A doc deleted by the range: not an item (nothing to close).
- A doc present in the range whose frontmatter has no `id`: reported as an item with reason `slug-unresolvable` and refused by `--apply` (fail-closed, never skipped silently — the shape `buildOpenIntakes` already treats as UNMAPPABLE).
- A merge commit plus its squashed parents in one range: the PR number is taken from the newest subject that carries one, so a range containing several merges stamps each item with the number of the merge that carried it only when one range equals one push; a multi-merge push reports every item and names the sha per item.
- An intake doc and its spec both in the range: one `close-work-item.mjs` invocation with `--spec`, never two.
- Windows: the CLI is Node-only and needs no PowerShell mirror; the suite is bash and is skipped on the PowerShell leg exactly as its siblings are.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-close-reconcile.sh | fixture repo, ride branch merged into main leaving a doc at status implementing, --check exits 1 and names doc, arm frozen_work_merged, sha and the close-work-item remediation (AMENDED 2026-09-11, Amendment item 1) | green |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-close-reconcile.sh | intake-only range that adds a draft doc and nothing else, --check exits 0 and prints CLEAN | green |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-close-reconcile.sh | --apply closes a draft-primary + implementing-spec pair via the real close-work-item.mjs in ONE invocation, re-check exits 0, frontmatter carries the parsed PR number and the delivery sha; a second, separately-built half-closed pair (spec already done, primary still draft) proves --check never reports CLEAN over it (AMENDED 2026-09-12, Amendment item 5, BLOCKING-1) | green |
| TEST-004 | Spec-AC-03 | integration | tests/skills/test-aai-close-reconcile.sh | SEAM ledger, the pre-apply EVENTS.jsonl bytes are a byte-exact prefix of the post-apply file and docs-audit --check --strict --no-event exits 0 over the fixture | green |
| TEST-005 | Spec-AC-04 | unit | tests/skills/test-aai-close-reconcile.sh | close-work-item.mjs is unchanged against the base ref and close-reconcile.mjs contains no write to a docs path of its own | green |
| TEST-006 | Spec-AC-05 | integration | tests/skills/test-aai-close-reconcile.sh | range whose subjects carry no trailing PR number, --apply exits non-zero naming pr-number-unknown and the doc bytes are unchanged | green |
| TEST-007 | Spec-AC-06 | unit | tests/skills/test-aai-close-reconcile.sh | missing, empty, all-zero and unresolvable --range each exit 2 naming the value, in --check and --apply | green |
| TEST-008 | Spec-AC-07 | unit | tests/skills/test-aai-close-reconcile.sh | the workflow file triggers on push to main, names close-reconcile.mjs --check, and carries no continue-on-error key | green |
| TEST-009 | Spec-AC-07 | integration | tests/skills/test-aai-close-reconcile.sh | the workflow command line replayed against a non-clean fixture exits non-zero and prints a line beginning with the GitHub error annotation prefix | green |
| TEST-010 | Spec-AC-08 | e2e | tests/skills/test-aai-close-reconcile.sh | a whole ride merged without SKILL_PR, intake `draft` paired with a spec at `implementing`, ends with the INTAKE doc done after the gate, asserted end to end in the fixture (AMENDED 2026-09-12, Amendment item 5: fixture corrected off an intake that itself reached `implementing`, a state the corpus never produces) | green |
| TEST-011 | Spec-AC-08 | e2e | tests/skills/test-aai-close-reconcile.sh | MUTATION control, first exercises the REAL close-reconcile.mjs on the SAME draft-intake/implementing-spec pair (fails RED if it is missing or degraded), then the gate stubbed to exit 0 returns the intake doc to its original `draft` status (AMENDED 2026-09-11, Amendment item 1: was tautological pre-remediation, never referenced the real binary; AMENDED 2026-09-12, Amendment item 5: fixture corrected the same way as TEST-010) | green |
| TEST-012 | Spec-AC-09 | unit | tests/skills/test-aai-close-reconcile.sh | PROFILES.yaml classifies the new file exactly once and suite-map.yaml maps it, with the layer-profiles and hygiene-pack suites green | green |
| TEST-013 | Spec-AC-10 | integration | tests/skills/test-aai-close-reconcile.sh | ADDED 2026-09-12 (Amendment item 5, BLOCKING-2): a doc carrying frontmatter `umbrella: true` at `status: implementing` fires neither arm -> --check exits 0 CLEAN | green |

Every Spec-AC has at least one TEST row and every TEST row names a Spec-AC. Test ids are stable after freeze; TEST-013 is a round-3 ADDITION (a new id, not a renumbering of an existing one).

### Seams this Test Plan crosses

- **S1 close-reconcile -> close-work-item** (TEST-003, TEST-010): the gate produces the invocation, the real ceremony script consumes it, and the assertion is made on the OTHER side — the doc's own bytes after the child process returns. No mock of `close-work-item.mjs` anywhere in the suite.
- **S2 close-reconcile -> the docs-audit corpus definition** (TEST-001, TEST-002): what counts as a doc, and therefore which touched paths are even candidates for an item, comes from `scanAuditDocs`. TEST-002 is the negative side of the same seam. (AMENDED 2026-09-11, Amendment item 1: this seam previously also gated the now-removed `code_with_open_doc` arm's non-doc-path test; `scanAuditDocs` still decides doc-path admission for the one arm that remains.)
- **S3 close-reconcile -> EVENTS.jsonl** (TEST-004): append-only is asserted on the real file bytes after a real apply, not argued from the fact that `close-work-item.mjs` is careful.
- **S4 the workflow -> the CLI exit contract** (TEST-008, TEST-009): the workflow's own command line is replayed, so a drift between what the YAML runs and what the CLI promises reddens.
- **S5 the new `.aai/**` file -> PROFILES and suite-map** (TEST-012): a new vendored file that no profile classifies fails `test-aai-layer-profiles.sh` against the LIVE tree.
- **S6 residual, no automated test** — the GitHub `push` event itself. Nothing local can prove that GitHub delivers `github.event.before` for a merge-queue merge; TEST-009 replays the command line with a supplied range instead. Written down here rather than left out.
- **S7 close-reconcile -> docs-audit-core.mjs's umbrella predicate** (TEST-013, ADDED 2026-09-12, Amendment item 5): the umbrella exemption re-reads `fm.umbrella` with the SAME string comparison `docs-audit-core.mjs` uses for its own suppression, not a re-derived copy; `docs-audit-core.mjs` itself is not imported or edited for this — the seam is the shared CONVENTION (frontmatter field name and comparison), asserted independently on close-reconcile.mjs's own fixture.

### RED observation, recorded before any green

Strategy is `tdd`, so each AC-gating test is observed FAILING before its implementation exists, and the RED artifact is stored under `docs/ai/tdd/` per the Evidence contract. The pre-change tree makes the first observation trivial and honest: `.aai/scripts/close-reconcile.mjs` does not exist, so TEST-001 through TEST-007 and TEST-010 fail with a `MODULE_NOT_FOUND`-shaped non-zero exit, and TEST-008 and TEST-009 fail because `.github/workflows/close-gate.yml` does not exist.

**AMENDED 2026-09-11 (see `## Amendment`, item 1) — TEST-011 is RED the SAME
direction as the others, not the opposite.** As first delivered, TEST-011
built its own throwaway stub and never invoked `$CLOSE_RECONCILE` at all, so
it PASSED unchanged whether the real script existed, worked, or was deleted
(measured by independent Validation: PASSES with `close-reconcile.mjs`
DELETED from the tree; its pre-implementation RED log carried `RED_CLASS:
n/a`, which `tdd-evidence-check.mjs --red` correctly rejects as UNCLASSIFIED
— `n/a` is not `product_red` or `infra_fail`). The redesigned TEST-011
exercises the real binary FIRST (Step A: `node "$CLOSE_RECONCILE" --check`
on the fixture, asserting `rc=1` and `arm=frozen_work_merged`) before
building and running the mutation stub (Step B). Pre-implementation, Step A
fails the same `MODULE_NOT_FOUND`-shaped way as TEST-001..010, so TEST-011 is
now genuinely RED before the implementation exists, classified
`product_red` (the test's own `log_fail` line is reached and printed) —
reproduced in a scratch git worktree, never in the shipping tree:
`docs/ai/tdd/red-close-reconcile-TEST-011-20260911T203036Z.log`, accepted by
`tdd-evidence-check.mjs --red` (rc=0). The same worktree reproduction with
`close-reconcile.mjs` replaced by an always-`exit 0` stub also fails Step A
(`rc=0`, not `1`), confirming the control now catches "stubbed" as well as
"absent" per the remediation that amended this test.

Each RED run is recorded with its command, exit code and first output lines in the per-AC evidence log.

## Verification

Commands to run:
- `bash tests/skills/test-aai-close-reconcile.sh` — the new suite, all thirteen rows green.
- `bash tests/skills/test-framework.sh --skill aai-close-work-item --skill aai-doc-numbering --skill aai-follow-ups --skill aai-orchestration-dispatch` — the four suites that pin `close-work-item.mjs` content (`tests/skills/lib/close-work-item-pin.sh` and the two pre-change blob pins).
- `bash tests/skills/test-framework.sh --skill aai-golden-flow --skill aai-docs-audit --skill aai-layer-profiles --skill aai-hygiene-pack` — the neighbours this scope's new file and map entries touch.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` — clean over this repository.
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0175-spec-close-ceremony-fires-only-via-aai-pr.md` — clean.
- `node .aai/scripts/check-test-registration.mjs tests/skills` — no orphan test function in the new suite.
- `git diff --exit-code <base>..HEAD -- .aai/scripts/close-work-item.mjs` — exit 0.
- The full sweep before close, with `AAI_TEST_TIMEOUT=3000`.

Evidence artifacts: the suite log under `tests/skills/results/`, the per-AC RED artifacts under `docs/ai/tdd/`, the fixture paths named by each failing assertion, and the delivery commit sha.

PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.

## Evidence contract
- ref_id: `close-ceremony-fires-only-via-aai-pr`
- Spec-AC and TEST-xxx links: as mapped in the two tables above, one row each way.
- command or review scope: the commands under Verification; review scope as recorded under Isolation and review.
- exit code or review verdict: recorded per command, never inferred from a summary line.
- evidence path: `docs/ai/tdd/` for the RED artifacts, `tests/skills/results/` for the suite runs.
- commit SHA or diff range: the delivery commit, stamped by the close ceremony into `links.commits`.

### Evidence by strategy

Strategy is `tdd`: a stored RED artifact is owed per AC-gating test, plus the full verification matrix above.

## Residual risks

- **R1 — a project with no CI is uncovered.** The trigger is a GitHub Actions job. A downstream project that merges locally or has Actions disabled gets the CLI but no automatic firing. The local `post-merge` git hook that would cover it is named in D7 as out of scope; suggested follow-up `fu-close-gate-needs-local-hook`.
- **R2 — an umbrella parent is still not reconciled when a child closes.** The issue's second half is untouched: a parent still describes shipped symptoms in the present tense after a child delivers, and this gate does nothing to update it. Suggested follow-up `fu-umbrella-parent-not-reconciled`. CORRECTED 2026-09-12 (Amendment item 5): the earlier text here also claimed the `umbrella: true` marker meant this gate itself regressed nothing; code review round 3 BLOCKING-2 found the opposite — `close-reconcile.mjs` did not read the marker at all, so a parent's OWN delivery pushes (e.g. `docs/rfc/RFC-0012`, `status: implementing` + `umbrella: true`) misfired `frozen_work_merged` with no dial and no legitimate clearing action. That half is now fixed (Spec-AC-10 / TEST-013); this residual narrows to the reconciliation gap only.
- **R3 — the PR number depends on a subject convention.** `(#N)` is the squash-merge subject shape on this repository and the GitHub default; a project that rewrites subjects gets `pr: unknown` and a refused `--apply` item rather than a wrong number. Loud, and by D4 deliberate.
- **R4 — a push containing several merges.** Every item is still reported and each carries its own sha, but a single push that lands two PRs can attribute the newest PR number to both. `--apply` stamps per item from the newest subject in the range; the mitigation is that the CI trigger is per push and a merge-queue push carries one merge. Named, not tested.
- **R5 — a red `main` job is a new noise source.** By D5 it blocks nothing, but it does turn the default branch red until the reconcile runs. Accepted deliberately: the whole issue is that the current signal is too quiet to be seen.
- **R6 — ADDED 2026-09-11 (Amendment item 3) — `close-work-item.mjs` hardcodes `validation: pass` into `work_item_closed`, and `close-reconcile.mjs --apply` is a second, route-independent way to reach it.** A ride closed through this gate, by construction, never ran `/aai-pr` or the validation pipeline SKILL_PR gates on — the whole point of D1 is that this trigger does not care which route delivered the code. The `work_item_closed` event it produces nonetheless carries an unretractable `validation: pass` claim identical to one a real independent Validation would have written. Pre-existing in `close-work-item.mjs` (out of scope here — PROTECTED, hash-pinned by four suites, D3), but newly REACHABLE through a route that skips validation entirely. No mitigation designed here; named so it is not silently inherited. Not filed as a follow-up id at remediation time — left for the operator to triage against the existing `close-work-item.mjs` backlog.
- **R7 — ADDED 2026-09-11 (Amendment item 2) — a doc already `status: done` at the delivery sha is invisible to this gate.** Two of the three documented post-merge close-ceremony escapes in this repository's history (`#350` for `#349`, `#358` for `#357`) went undetected under both the original two-arm design and the amended one-arm design, because the doc's frontmatter already read `done` by the time the reconciling range ran — what those follow-ups actually fixed was `links.commits` and close telemetry, not a non-terminal status. D1/D2 read only post-merge doc status; a status-driven trigger structurally cannot see this class. Filed as `fu-close-gate-status-trigger-blind` (P2, open); explicitly out of scope for this remediation to design against.
- **R8 — ADDED 2026-09-12 (Amendment item 4) — Spec-AC-01's frozen-marker clause is implemented but not tested, and that is ACCEPTED, not overlooked.** Independent Validation round 2 found by mutation that deleting the `|| isFrozen` disjunct from the surviving arm leaves the 12-row suite fully green: every fixture now carries `status: implementing`, so the marker branch is never the reason an item fires. The branch is live and correct on probe (a `draft` doc carrying `SPEC-FROZEN: true` yields rc=1 and `arm=frozen_work_merged`) and is named verbatim in Spec-AC-01 "(or carrying the frozen marker)" and in D2. Over a 150-push CI-faithful replay BOTH real true positives fired through the `implementing` disjunct, so the untested branch is defense-in-depth, not load-bearing. The owner was offered the fixture (about 15 lines, validated RED) and chose to accept the gap as a disclosed residual instead, on the recorded ground that a third remediation round costs more than the risk it retires. Recorded as `hitl_decision` in `docs/ai/decisions.jsonl`, 2026-09-12.
- **R9 — ADDED 2026-09-12 (validation round 3, finding F3) — the recall census stated in Amendment item 2 and R7 is REFUTED by a wider corpus, and the correction matters for whoever picks the gap up.** Those passages say "the three documented escapes in this repository's history" and quote recall as 1 of 3. An independent 200-push CI-faithful replay found at least EIGHT post-merge reconciliations in the window, with the shipped gate catching 2 — recall 25%, and that is an UPPER bound, because ground truth here is commit-subject archaeology and a silently never-reconciled escape leaves no subject to find. The misses split into three mechanisms, not one: two because the doc already read `status: done` at the delivery sha (R7's mechanism, correct as far as it goes), THREE because the intake stayed `draft` with no paired spec at all (a class no passage in this spec names, and one that is safe only because Amendment item 1 removed the `code_with_open_doc` arm), and one because the doc was not in the delivery range. `fu-close-gate-status-trigger-blind`'s own text names only the already-done mechanism, so a reader taking that follow-up is aimed at a quarter of the problem. Precision is unaffected and remains 100% (4 of 4 items over 200 pushes, firing rate 1.0%).
