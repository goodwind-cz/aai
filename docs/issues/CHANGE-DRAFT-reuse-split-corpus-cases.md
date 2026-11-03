---
id: reuse-split-corpus-cases
type: change
number: null
status: draft
capability: precise-suite-evidence-reuse
parent: smaller-node-core-and-faster-feedback
user_visible: true
links:
  pr: []
  commits: []
---

# Fixture cases of the whole-corpus suites are reused after an ordinary edit

## Summary
- Five reuse-manifest suites read the git index or every tracked file:
  aai-docs-content, aai-spec-lint, aai-hygiene-pack, aai-prompt-diet and
  aai-win-fallback. Their trace identity is therefore every tracked file, so
  any edit anywhere in the checkout makes each of them run again
  (SPEC-0268, SPEC-0270; `docs/analysis/precise-suite-evidence-reuse.md`).
- A trace identity cannot be narrower than the true read set. The way to
  reuse more is to move the cases that read the whole corpus into their own
  suite, so the cases that read only their fixtures and the code under test
  get a narrow identity and are reused after an ordinary edit.
- Follow-up `fu-reuse-split-corpus-cases` (P2). This ride closes it.

## Motivation / Business Value
- These five suites are the expensive ones of a selected local run (about
  100 s, aai-hygiene-pack alone about 95 s). Re-validation and remediation
  rounds re-run them after every edit, although most of their cases test a
  fixture and cannot change their verdict when an unrelated file changes.
- The previous ride (PR #527, SPEC-0270) made a zero-delta rerun reuse them;
  an ordinary one-file edit still reruns all five in full.

## Scope
- In scope:
  - Measure, per case of each of the five suites, whether it reads the
    corpus or the git index, or only its fixtures and the code under test,
    and its wall time.
  - Split, for the suites where the measurement shows it pays off, the
    whole-corpus cases into a separate suite, following the precedent of the
    aai-docs-audit / aai-docs-content split (SPEC-0260).
  - Keep the wiring consistent: CI suite selection (`tests/skills/suite-map.yaml`
    rows, core list, companions), `tests/skills/suite-reuse.json` entries and
    admission notes, `tests/skills/suite-weights.tsv`, the Windows/Pester
    mirrors if any, and every pinned suite count or suite list.
  - A measurement section in `docs/analysis/precise-suite-evidence-reuse.md`
    and the Limits of `docs/product/precise-suite-evidence-reuse.md`.
- Out of scope:
  - Any change to the reuse identity rule in `.aai/scripts/suite-reuse.mjs`
    or to the access trace.
  - Changing what any case asserts, its TEST id or its meaning.
  - EVENTS / decisions / STATE churn from role actions (`fu-reuse-docs-closure-suites`).
  - Suites other than the five named.

## Affected Area
- `tests/skills/test-aai-{spec-lint,hygiene-pack,prompt-diet,win-fallback}.sh`
  and `tests/skills/test-aai-docs-audit.sh` (definition files), new corpus
  suite files, `tests/skills/suite-map.yaml`, `tests/skills/suite-reuse.json`,
  `tests/skills/suite-weights.tsv`, suites that pin the suite map or suite
  counts, analysis and product docs.

## Desired Behavior (To-Be)
- After an ordinary edit (one product doc or one production script that the
  fixture cases do not read), the fixture half of each split suite is
  reported REUSED and only the corpus half runs.
- The corpus cases still run on every change that can turn them red, with no
  lost coverage: every case runs exactly once in a full run, in exactly one
  suite, under its existing TEST id.

## Acceptance Criteria
- AC-001: A per-case measurement of the five suites (corpus or git-index read
  versus fixture-only, and wall time) is recorded in the analysis doc, and the
  spec names which suites are split and why the others are not.
- AC-002: For each split suite, the union of the cases of its two halves
  equals the baseline case list, with no case in both halves and every TEST id
  and assertion unchanged.
- AC-003: CI suite selection selects the corpus half for every path that
  selected the original suite, and the core list keeps every always-on corpus
  check; the suite map, the reuse manifest, the weights and every pinned suite
  count agree.
- AC-004: After a representative ordinary edit (one product doc, and one
  production script), the analysis doc reports, before and after, how many of
  the split suites are reused and the wall-time saving.

## Verification
- Command(s) and expected results:
  - `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh --skill <each touched suite>` passes.
  - `node .aai/scripts/select-suites.mjs` over the real map selects the corpus
    halves for every glob that selected the original suite.
  - A seed run plus an ordinary-edit rerun shows the fixture halves REUSED.

## Constraints / Risks
- A split that leaves a corpus-reading case in a fixture half would give that
  half a narrow identity it does not have: the admission run of
  `suite-reuse.mjs lint --admit` and the access trace are the check, not
  reading the source.
- More suites mean more CI jobs or a longer selected list; a split must save
  more than it costs.
- The checkout is shared with other sessions: work happens in a worktree.
- No secret is referenced.

## Notes
- Assumptions (autopilot, recorded instead of questions): CHANGE type
  (test-layer restructuring of an internal mechanism, limited scope); a split
  is planned only for suites where the measurement shows a saving; no owner
  metrics question (human_time_minutes null); Planning decides the
  implementation strategy.
- Prior work: SPEC-0260 (content/engine split precedent), SPEC-0266,
  SPEC-0268, SPEC-0270, `docs/product/precise-suite-evidence-reuse.md`.
