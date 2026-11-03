---
id: reuse-local-ledger-append
type: change
number: 243
status: done
capability: precise-suite-evidence-reuse
parent: smaller-node-core-and-faster-feedback
user_visible: true
links:
  pr: []
  commits: []
---

# An unchanged rerun reuses the suites that read the git index

## Summary
- `tests/skills/test-framework.sh` appends one line to the tracked
  `docs/ai/tests/test-runs.jsonl` at the end of every run. A suite whose
  access trace shows it read the git index counts every tracked file in its
  identity (SPEC-0268, `computeIdentity` in `.aai/scripts/suite-reuse.mjs`),
  so the framework's own append moves that identity and even a zero-delta
  rerun misses reuse. Measured in `docs/analysis/precise-suite-evidence-reuse.md`
  (R0 rows: every index-reading suite `RUN reason=inputs changed
  docs/ai/tests/test-runs.jsonl`).
- Follow-up `fu-reuse-local-ledger-append` (P2). This ride closes it.

## Motivation / Business Value
- Five of the eleven manifest suites read the git index (aai-docs-content,
  aai-spec-lint, aai-hygiene-pack, aai-prompt-diet, aai-win-fallback). They
  are the expensive ones (about 100 s of a selected run). Today none of them
  can ever be reused locally, because every run of the framework invalidates
  their record by its own write.
- Re-validation and remediation rounds re-run exactly these suites; a
  zero-delta or unrelated-delta round should not pay for them again.

## Scope
- In scope:
  - The identity rule in `.aai/scripts/suite-reuse.mjs` (and, only if Planning
    chooses that route, the framework's ledger write in
    `tests/skills/test-framework.sh`) so that the framework's own ledger append
    no longer moves the identity of an index-reading suite.
  - Tests in `tests/skills/test-aai-suite-reuse.sh` (TEST ids TEST-3300..3329).
  - Product doc `docs/product/precise-suite-evidence-reuse.md` (Limits) and a
    measurement section in `docs/analysis/precise-suite-evidence-reuse.md`.
  - Manifest notes in `tests/skills/suite-reuse.json` where they state what the
    identity of an index-reading suite is.
- Out of scope:
  - Splitting the large suites' corpus-wide cases from their fixture cases
    (`fu-reuse-split-corpus-cases`, the next ride).
  - EVENTS / decisions / STATE churn from role actions and the other
    docs-closure causes (`fu-reuse-docs-closure-suites`).
  - Any change to CI carry-forward, the PR sweep, recheck or merge-cleanup
    ledger handling.

## Affected Area
- `.aai/scripts/suite-reuse.mjs` (identity comparison), possibly
  `tests/skills/test-framework.sh` (ledger write), `tests/skills/suite-reuse.json`
  (notes), `tests/skills/test-aai-suite-reuse.sh`, product and analysis docs.

## Desired Behavior (To-Be)
- A rerun of the manifest suites with no edit between the two runs reports
  every index-reading suite REUSED (given a recorded pass), while any real
  change to a tracked file the identity covers still produces a miss.

## Acceptance Criteria
- AC-001: After a seed run of the suites in `tests/skills/suite-reuse.json`, a
  zero-delta rerun reports each of the five index-reading suites REUSED
  (measured before and after the change, recorded in the analysis doc).
- AC-002: An edit of any tracked file other than the framework's own ledger
  append (including an edit of an existing line of
  `docs/ai/tests/test-runs.jsonl`) still makes an index-reading suite miss.
- AC-003: A suite whose trace did not read the git index keeps today's
  identity rule unchanged.
- AC-004: The spec states exactly what the identity compares afterwards plus
  one general caveat.

## Verification
- Command(s) and expected results:
  - `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh --skill aai-suite-reuse` passes.
  - A seed run plus zero-delta rerun of the manifest suites shows the five
    index-reading suites REUSED on the rerun.

## Constraints / Risks
- Weakening the identity: a suite that genuinely reads test-runs.jsonl must
  still see changes it depends on. Planning measures who reads the ledger
  before choosing.
- Consumers of the tracked ledger (CI carry-forward globs, PR sweep stale-head
  ledger set, recheck / dispatch tree hash exclusions, merge-cleanup ledger
  union, check-committed-scope ledger set) must not change behavior.
- No secret is referenced.

## Notes
- Assumptions (autopilot, recorded instead of questions): CHANGE type
  (behavior change of one internal mechanism, limited scope); the narrowest fix
  that the measurements support wins; no owner metrics question
  (human_time_minutes null); Planning decides the implementation strategy.
- Candidates named by the need: (a) the framework writes its run line to an
  untracked local file, or outside the traced window, and something else lands
  it in the tracked ledger; (b) the framework-owned ledger path is excluded
  from the compared identity for the suites where that is safe.
- Prior work: SPEC-0266 (CHANGE-0240), SPEC-0268 (CHANGE-0242),
  `docs/product/precise-suite-evidence-reuse.md`.
