---
id: precise-suite-evidence-reuse
type: product
capability: precise-suite-evidence-reuse
status: current
delivered_by:
  - precise-suite-evidence-reuse
spec: docs/specs/SPEC-0266-spec-precise-suite-evidence-reuse.md
updated: 2026-11-01
---

# Reuse of local suite results

## What it does

A local test run can skip a suite whose result is already known: when a suite
passed earlier and nothing it depends on has changed since, the framework
reports it as REUSED, names the run it came from and points at that run's
log, instead of executing it again. "Nothing changed" is checked against a
complete input identity of the suite: the bytes of every file it reads, the
relevant environment, its arguments, the Node version and platform, the runner
policy and its own history. Anything the checker cannot account for makes the
suite run. A reused result is never reported as a new execution, and the
full sweep before close, CI, main, nightly and release always execute every
suite.

## How to use it

- It is on by default for local runs of `tests/skills/test-framework.sh`
  (selected suites, `--skill`). Turn it off for a run with
  `AAI_SUITE_REUSE=0`.
- Only suites declared in `tests/skills/suite-reuse.json` can be reused.
  A suite qualifies only when its whole closure is known; check one with
  `node .aai/scripts/suite-reuse.mjs explain <suite>`.
- `node .aai/scripts/suite-reuse.mjs lint` checks the manifest; `lint
  --minimal-tree` additionally runs each declared suite in a tree that holds
  only its declared inputs (the admission gate).
- Roles that may cite a reused suite: Implementation and TDD GREEN
  re-checks, Remediation re-checks, and intermediate Validation and Code
  Review rounds. They cite it as reused with the original run id and log and
  read that log. TDD RED observations and mutation runs never reuse.

## Data model

- `tests/skills/suite-reuse.json` (tracked): `version` and, per suite,
  `inputs` (extra files it reads), `live` (true means never reusable) and a
  `note` saying why the closure is complete.
- `tests/skills/results/reuse/` (gitignored, local only): one record per
  suite with the identity hash, its six component hashes, the run id, the
  finished time, the log path and the log's sha256. A failed or skipped suite
  removes its record.
- Run outputs: `metrics.jsonl` gains `status: REUSED` with `reused_from_run`
  and `reused_log`; the `docs/ai/tests/test-runs.jsonl` line gains `reused`
  while `total` stays the executed count.

## Interfaces and contracts

- `node .aai/scripts/suite-reuse.mjs check|record|forget|lint|explain`: the
  helper the framework calls. `check` prints `REUSE` or `RUN reason=<why>`
  per suite (for example `inputs-unresolvable`, `no-record`, `log-missing`,
  or the first identity component that changed).
- `lint` reasons include `not-gate-selected` and `gate-row-missing`.
- Framework output: `Evidence reuse: on (<M> of <N> suites reused, check
  <s>s)`, a `REUSED (run …, …, log …)` line per reused suite and a
  `Reused: <M>` summary line.
- `AAI_SUITE_REUSE=0` turns reuse off; the framework sets it for every suite
  it executes, and `release-dry-run.mjs` sets it for the release check.
- `.aai/SKILL_VERIFY.prompt.md` "Reuse exception" and
  `.aai/VALIDATION.prompt.md` step 5 state when reused evidence counts.

## Limits and non-goals

- The saving is small today. Three suites reuse (aai-feedback-status,
  aai-pricing, aai-redact); on a re-check of the declared suites the wall
  time went from 16 s to 10 s. The expensive suites read `docs/` and the
  ledgers, which change with every role action, so they never qualify; see
  docs/analysis/precise-suite-evidence-reuse.md.
- The read set is found by reading the suite's source text, not by tracing it
  at run time. Every shape the reader cannot resolve makes the suite run; a
  few rare shapes that no declared suite uses are known gaps, tracked as
  follow-ups.
- A bash startup hook is not part of the identity. When `BASH_ENV` or `ENV`
  is set and non-empty, every suite runs (reason `bash-startup-hook`); the
  hook file is never hashed.
- Not cached, ever: live effects (permissions, remote refs, release
  publication, locks), CI, main and nightly runs, and the full sweep before
  close.
- The runner process adapters (aai-run-tests, aai-reap-tests,
  autonomous-loop) are unchanged; their migration is a later RFC-0017 phase 5
  slice.

## Links

- Request: docs/issues/CHANGE-0240-precise-suite-evidence-reuse.md
- Spec: docs/specs/SPEC-0266-spec-precise-suite-evidence-reuse.md
- Measurement: docs/analysis/precise-suite-evidence-reuse.md
- Validation evidence: docs/ai/reports/VALIDATION-precise-suite-evidence-reuse-r12.md
