---
id: reuse-for-docs-reading-suites
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

# Make suite-result reuse work for the expensive suites that read docs/

## Summary
- CHANGE-0240 / SPEC-0266 added reuse of a local suite pass when the suite's
  complete input identity is unchanged. Only three cheap suites qualify, and a
  representative re-validation round reused nothing: the expensive suites
  (aai-docs-content, aai-spec-lint, aai-hygiene-pack, aai-prompt-diet,
  aai-ride-status, aai-win-fallback, ...) read `docs/` and the ledgers, whose
  identity changes on every run (follow-up `fu-reuse-docs-closure-suites`, P2).
- This ride makes those suites reusable without a false hit, so that a
  re-validation round actually saves wall time.

## Motivation / Business Value
- The measured saving today is 16 s to 10 s on the three cheap suites and zero
  on a real re-validation round; the expensive suites are where the minutes
  are (90+ s per round measured, ~75 min for a full sweep).
- The owner asked for it on 2026-11-02 (menu answer "1 a 3").

## Scope
- In scope:
  - Planning measures the three mechanisms recorded in
    docs/analysis/precise-suite-evidence-reuse.md that keep those identities
    moving, and decides how each is removed:
    - the framework's own append to the tracked
      `docs/ai/tests/test-runs.jsonl`, and the EVENTS/STATE churn under
      `docs/ai/`;
    - shared-library prose literals in `tests/skills/lib/` that pull the
      whole `docs/` tree into a closure;
    - the real-history marker (HEAD as part of the identity).
  - The source-text path reader of SPEC-0266 took 14 validation rounds to
    make fail-closed and still has known gaps. Planning must weigh, with
    measurements, replacing or complementing it with the suite's ACTUAL read
    set observed at run time (for example a Node/bash read trace recorded on
    the passing run and stored with the record), and choose the approach that
    gives an exact identity for these suites. A trace-based identity must
    still fail closed on anything it did not observe (writes, network,
    subprocesses outside the trace).
  - At least the six suites named above become reusable where their real
    inputs are unchanged, and are added to the manifest with the admission
    gate passing.
  - Measurement: a representative re-validation round (a remediation-shaped
    delta of one production line, selected suites plus CORE) with reuse off
    and on, recorded in the analysis note; the product doc
    `docs/product/precise-suite-evidence-reuse.md` updated.
- Out of scope:
  - Reuse in CI, on main, nightly, release or for the full sweep before close
    (unchanged: they always execute).
  - The process-adapter migrations (separate rides).

## Affected Area
- `.aai/scripts/suite-reuse.mjs`, `tests/skills/test-framework.sh`,
  `tests/skills/suite-reuse.json`, possibly `tests/skills/lib/*` prose and the
  test-runs ledger write
- `docs/specs` (new spec), `docs/analysis/precise-suite-evidence-reuse.md`,
  `docs/product/precise-suite-evidence-reuse.md`

## Desired Behavior (To-Be)
- A re-validation round whose delta does not touch an expensive suite's real
  inputs reports that suite as REUSED, with provenance, and the round is
  measurably faster.
- No false hit: a change to any file the suite actually reads, its
  environment, arguments, runtime or policy makes it run.

## Acceptance Criteria
- AC-001: The six named suites are in the manifest and pass the admission
  gate.
- AC-002: For each of them, editing a file it really reads makes it RUN, and
  editing a file it does not read (including the ledgers it does not read)
  leaves it REUSED; tested.
- AC-003: The framework's own ledger writes no longer change the identity of
  a suite that does not read them.
- AC-004: The chosen identity method fails closed on anything it cannot
  account for (tested with at least one unobserved-read case).
- AC-005: A representative re-validation round is measured with reuse off and
  on (at least three samples each) and the result is recorded, saving or not.

## Verification
- suite-reuse node tests and suite pass; admission gate passes for the
  manifest; the measurement is in the analysis note.

## Constraints / Risks
- The main risk is a false hit (a stale pass reported as fresh). Planning must
  state, in the spec, exactly what the identity compares, with one general
  caveat, not a list of guarantees (state-what-a-guard-compares memory); a
  hand-written parser in a gate is the failure class to avoid
  (security-parser-strict-format-upfront memory).
- Changes to the shared prompt canon (SKILL_VERIFY reuse exception) need the
  prompt-diet ledger and the TEST-012 pin.
- Runs in parallel with `node-first-reap-tests` in its own worktree; full
  sweeps of the two rides are not run at the same time.
- No secrets referenced.

## Notes
- Source: follow-up `fu-reuse-docs-closure-suites` (P2) and the analysis note
  of CHANGE-0240; owner menu answer 2026-11-02 "Mergni to a pak 1 a 3".
- Assumption (autopilot default): one ride; Planning may split it (for example
  ledger-write change first, trace identity second) if the evidence says so.
