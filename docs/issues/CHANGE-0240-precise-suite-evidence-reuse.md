---
id: precise-suite-evidence-reuse
type: change
number: 240
status: done
user_visible: true
capability: precise-suite-evidence-reuse
links:
  pr: []
  commits: []
---

# Precise reuse of local suite results with a complete input identity

## Summary
- First slice of RFC-0017 phase 5 ("introduce precise evidence reuse where
  inputs are declared"), implementing the caching rule of RFC-0017 section 3:
  cache only deterministic checks with a complete input identity, report a
  cache hit as reused evidence with provenance, never as a new execution. A
  local suite run whose complete input identity matches an earlier passing run
  is not executed again; the earlier result is reported as reused. The
  process-adapter part of phase 5 (`aai-run-tests`, `aai-reap-tests`,
  `autonomous-loop`) is out of scope and stays for later slices. The umbrella
  RFC stays open.

## Motivation / Business Value
- Re-validation rounds and remediation re-checks re-run suites whose inputs did
  not change since the last passing run in the same ride. A full sweep costs
  about 32 minutes and a selected set several minutes per round; much of that
  repeats work whose result is already known.
- RFC-0017 section 3 and the analysis note on `SKILL_VERIFY.prompt.md` name the
  conflict: the freshness rule ("produced after the last edit to any file in
  scope") is conservative and blocks efficient reuse unless input identity and
  validation responsibility become explicit. This slice makes them explicit.
- Existing CI carry-forward (CHANGE-0205) only covers a restricted class of
  later documentation and ledger changes in CI; local runs have no reuse at all.

## Scope
- In scope:
  - An input identity for one suite run: the bytes of every file the suite
    reads (derived from the existing suite map's declared domain inputs plus
    the suite file itself and the shared test harness), the relevant
    environment variables, the arguments, the Node version, OS and
    architecture, and the runner policy (timeout, isolation mode). Tracked and
    untracked relevant files both count; a change to an untracked relevant file
    invalidates the identity.
  - A suite with an undeclared or unknown input set is never reused (full-run
    fallback). Planning names how "declared" is decided from the suite map and
    which suites qualify.
  - A local reuse record: a passing run records its identity and provenance
    (when it ran, the run log or evidence path, the exit code). A later run
    through the canonical runner with an identical identity reports
    `reused` with that provenance instead of executing; a mismatch or a
    missing record runs normally. Only passing results are reused.
  - An explicit opt-out for a run (an env var or flag) and a statement of
    which roles may consume reused evidence (for example Implementation and
    Remediation re-checks, Validation intermediate rounds) and where a fresh
    execution stays mandatory (the one full sweep before close, CI, main,
    nightly, release). `SKILL_VERIFY.prompt.md` and the dispatch-sweep policy
    are reconciled in text: reused evidence with a matching complete identity
    counts as fresh for the claim it covers, and the report names it reused.
  - Live effects (external permissions, remote refs, release publication,
    locks, network) are never cached as test success; a suite that reads them
    is not reusable.
  - A measurement on one representative re-validation round (wall time with
    and without reuse) recorded in an analysis note.
  - Product doc, CHANGELOG entry, RFC-0017 phase 5 row set to in progress
    (not done; umbrella stays open).
- Out of scope:
  - Migrating `aai-run-tests`, `aai-reap-tests` or `autonomous-loop` to Node
    (later phase 5 slices).
  - Any change to CI, main or nightly runs; CI keeps full runs and its existing
    carry-forward.
  - A general-purpose dependency graph (SPEC-0206 measured it as low leverage);
    the identity uses the suite map's declared inputs.
  - Reusing failing results, or reusing across machines.

## Acceptance Criteria
- A suite that passed is reported `reused` with provenance on a second run
  with an unchanged identity and is not executed (proved by a fixture suite
  that writes a marker when it runs).
- Each identity component invalidates reuse when it changes: a tracked input
  byte, an untracked relevant file, a relevant environment variable, an
  argument, the Node version, the runner policy (one test per component,
  using a fixture and an injectable Node version/platform where needed).
- A suite without declared inputs, a suite marked as reading live effects, a
  failing earlier run and the opt-out all run normally.
- The reuse record never claims a new execution: the runner output and any
  evidence file name the run as reused and cite the original run.
- Windows and POSIX runners behave the same (the shared logic is Node, both
  launchers call it), proved on the native Windows CI job.
- The analysis note records the measured wall time of one re-validation round
  with and without reuse.

## Assumptions (autopilot)
- Type is change, not PRD: it extends the existing runner and suite map.
- No human-time metric recorded (autopilot default).
- Ceremony and worktree recommendation are Planning's call; any protected
  surface keeps its human gate.
- The reuse store is local and gitignored, like other runtime evidence.

## Constraints / Risks
- A false hit (reusing a result whose real inputs changed) silently weakens
  every gate that trusts the runner. The identity must err toward a miss: an
  input the identity cannot see makes the suite non-reusable, never reusable.
- The suite map's globs were written for selection, not for identity; Planning
  checks whether they are complete enough or need an explicit per-suite
  "inputs complete" marker.
- `aai-run-tests.sh` and `.ps1` are large paired scripts; prefer one Node
  helper both call over duplicating logic in each.
