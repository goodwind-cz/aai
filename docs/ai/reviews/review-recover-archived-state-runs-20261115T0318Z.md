# Code review: recover-archived-state-runs (round 2, delta re-review)

review_started_utc: 2026-11-15T03:18:04Z
Reviewer: claude-opus-5-5, dispatched CODE REVIEW role, read-only on implementation files.
Scope: delta `ecac2cf9..7a8e39c3` on fix/recover-archived-state-runs (worktree
/Users/ales/Projects/aai-worktrees/recover-archived-state-runs), excluding
docs/ai/EVENTS.jsonl, docs/ai/tests/test-runs.jsonl, docs/INDEX.md. The merged-in
origin/main content (#558, 377e6275) is treated as base.
Prior review: docs/ai/reviews/review-recover-archived-state-runs-20261115T0142Z.md (pass/pass
on ecac2cf9, NB-1..NB-4, NB-3 accepted residual).
Spec: docs/specs/SPEC-0292-spec-recover-archived-state-runs.md (SPEC-FROZEN).
Validation: docs/ai/reports/VALIDATION-20261115T0256Z-recover-archived-state-runs.md (r4 PASS on a46c12b4).

security_relevant: false

Commits reviewed:
- 6cf68b17: NB-1 (`--state` excluded from archive copies, NOTE line, TEST-3739 case), NB-2
  (TEST-3749 also keys on `recovered_utc`), NB-4 (CHANGELOG wording).
- aa29ab09: layer-profiles fixture repos set `maintenance.auto false` (race V3-1).
- 3c0d830f: merge of origin/main 377e6275.
- 1ad23961, a46c12b4, 7a8e39c3: telemetry only (EVENTS.jsonl and test-runs.jsonl). Checked
  with `git diff --stat`.

Nothing else changed. `git diff --stat 377e6275 7a8e39c3` shows none of the #558 files
(ROUTING_REFRESH, MODEL_ROUTING, PRICING, routing-table-freshness, universal-routines, the
pricing and routine suites). The merge took them byte-identical to base. The only conflict
was CHANGELOG.md. Against base, it adds exactly this ride's `## [unreleased] — fix:` entry
above the #558 `chore(routing)` entry. Both are separate per-entry headings, there are no
conflict markers, and the base entry is unchanged.

```yaml
review:
  scope: "ecac2cf9..7a8e39c3 (excl. EVENTS.jsonl, test-runs.jsonl, INDEX.md; #558 = base)"
  spec: docs/specs/SPEC-0292-spec-recover-archived-state-runs.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01..03, call: compliant, citation: "unchanged since round 1 (metrics-flush.mjs delta touches only archiveCopies/handleRecoverArchives copy selection); test-aai-metrics.sh green 2026-11-15T03:25Z" }
      - { ac: Spec-AC-04, call: compliant, citation: "metrics-flush.mjs:1690-1709 + 1773-1776 narrow the walk further (the live --state file is never a copy); the 'only STATE*.yaml basenames' rule is unchanged; TEST-3739 green incl. new live-state case" }
      - { ac: Spec-AC-05..11, call: compliant, citation: "no code delta; test-aai-metrics.sh green; r4 full sweep test-20261115-025848 rc 0" }
      - { ac: Spec-AC-12, call: compliant, citation: "METRICS.jsonl unchanged in delta; 65 lines carry recovered_utc 2026-11-15T00:09:46Z (= all 65 recovered_utc lines); TEST-3749 green with the narrowed key" }
      - { ac: Spec-AC-13, call: compliant, citation: "CHANGELOG.md:33-35 one fix heading, wording corrected; TEST-3750 green" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: docs/product/telemetry.md, line: 177,
          issue: "the recovery paragraph does not say that the --state file is excluded when an --archive path covers it (new NOTE behaviour from NB-1)",
          failure_scenario: "an operator who points --archive at docs/ai and sees 'NOTE ...STATE.yaml: is the --state file, not an archived copy; excluded' finds nothing in the product doc that explains it. Cosmetic, the NOTE text explains itself. One sentence would close it" }
  cannot_verify:
    - { claim: "the layer-profiles maintenance.auto fix removes the V3-1 race on every head, not just the ones it was tried on", closes_with: "validator r4 reproduced the race on 6cf68b17 and showed it gone with the fix; on 7a8e39c3 the race does not trigger even without the fix, so there is no in-head negative control; CI runs on the PR" }
    - { claim: "the round-1 cannot_verify items (D8 real-run input equivalence, R2 open-PR overlap, readers outside .aai/scripts)", closes_with: "carried forward unchanged; the delta does not touch them" }
  overall: pass
```

## Prior findings: dispositions

- NB-1, closed. `archiveCopies(paths, stateReal)` compares the realpath of every candidate
  with the realpath of `--state`. On a match it leaves the file out and emits a NOTE. This
  covers both the directory walk and a file named directly by `--archive`, and the realpath
  also catches symlinks. I ran a negative control in a scratch copy of `.aai` with the check
  disabled (`if (false) excluded`), using `--archive docs/ai` and a non-focus ref ARCH-L in
  the live STATE:
  - with the check disabled: one ARCH-L recovery line;
  - with the real code: zero lines and the NOTE.
  The new TEST-3739 case uses the same setup, so it tells the two apart.
- NB-2, closed. The TEST-3749 filter now also requires
  `reconstructed.recovered_utc === '2026-11-15T00:09:46Z'`. All 65 recovered lines in the
  ledger carry that stamp. A later recovery gets a different `--now`, so it no longer moves
  the pin.
- NB-3: accepted residual, unchanged (as recorded in round 1).
- NB-4, closed. The CHANGELOG now says: "a run that is also in the live STATE is written
  from its live fields and a later flush treats it as held". This matches telemetry.md and
  the code (`liveRun(...) ?? run`).

## Other delta

- aa29ab09: test-only. It runs `git config maintenance.auto false` on both fixture source
  repos right after `git init`, before any commit, with a comment that names the race. The
  change is small and fixes the cause. Validator r4 has the evidence: a reproduction on
  6cf68b17 and 5/5 green runs with the fix.
- In TEST-3739, the new case's `cp ... "$e/ledger.before"` is never read afterwards. It
  does no harm, so it is not filed as a finding.

## Evidence run in this review

- `env -u AAI_ROLE -u AAI_GIT_WRITE bash tests/skills/test-aai-metrics.sh`: rc 0, "All
  aai-metrics tests passed" (TEST-3739, TEST-3749 and TEST-3750 PASS).
- The negative control above (scratch dir, removed nothing from the worktree).
- Side effect: the suite regenerated docs/ai/overview-data.json and docs/ai/overview.html in
  the worktree. They were not restored, so the orchestrator decides. I did not touch
  docs/ai/EVENTS.jsonl: its 3 uncommitted lines are from 03:17:48Z, before this review.

## Next steps

Overall: pass. NB-5 (one telemetry.md sentence) is optional and can be folded in or left as
is. Deal with the regenerated overview files before closeout.

review_ended_utc: 2026-11-15T03:26:30Z
