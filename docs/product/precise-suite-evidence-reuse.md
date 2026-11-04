---
id: precise-suite-evidence-reuse
type: product
capability: precise-suite-evidence-reuse
status: current
delivered_by:
  - precise-suite-evidence-reuse
  - reuse-for-docs-reading-suites
  - reuse-local-ledger-append
  - reuse-split-corpus-cases
spec: docs/specs/SPEC-0266-spec-precise-suite-evidence-reuse.md
updated: 2026-11-04
---

# Reuse of local suite results

## What it does

A local test run can skip a suite whose result is already known: when a suite
passed earlier and nothing it read has changed since, the framework reports it
as REUSED, names the run it came from and points at that run's log, instead of
executing it again. A reused result is never reported as a new execution, and
the full sweep before close, CI, main, nightly and release always execute
every suite.

What "nothing it read has changed" compares is the trace identity of the
suite. During the passing run the suite works in a disposable checkout and the
operating system's file access times show which files it touched. The identity
holds: the bytes and executable bit of every file inside the checkout (outside
its `.git` directory) that the suite read, replaced or deleted; under `.git`
only HEAD and the refs, and only when the run read the git directory; every
file when the run read the git index, and then for the run ledger
`docs/ai/tests/test-runs.jsonl` only the bytes it held when the run started
(lines appended after the recorded run do not count; any other change to it
does); the list of file
paths in the checkout; the harness files; the relevant environment; the arguments; the runtime (Node version,
platform, CPU architecture, git and bash versions); and the runner policy. Caveat: anything outside the checkout, or
read without its access time moving (for example a stat-only check such as
`[ -s f ]`), is not compared. The same holds for the ledger exception: when an
index-reading suite is admitted locally, the admission gate runs it once with
one non-JSON line appended to the ledger and it must still pass. That probe
catches a suite that parses the ledger strictly, not a lenient reader that
skips lines it cannot parse, and it is not repeated on every run. A suite that
did not read the git index is compared on the ledger exactly.

## How to use it

- It is on by default for local runs of `tests/skills/test-framework.sh`
  (selected suites, `--skill`). Turn it off for a run with
  `AAI_SUITE_REUSE=0`.
- Only suites declared in `tests/skills/suite-reuse.json` can be reused.
  A suite qualifies only when `lint --admit` passes for it; `explain <suite>`
  shows what its last record read.
- `node .aai/scripts/suite-reuse.mjs lint` checks the manifest; `lint
  --admit` is the admission gate: it runs a suite, plants a read probe and an
  unread probe, and refuses a suite whose trace misses a read (a restored
  access time, a node read the trace did not see). It also runs a poisoned
  pass: files on the path list that the suite did not read are overwritten,
  and the suite must still exit 0. `--changed-since REF` admits only entries
  that differ from REF, and a suite whose manifest entry lists `sources` (the definition files its suite file sources, as the two corpus suites do) counts as differing when one of those files differs; `lint` fails on a `sources` path that does not exist. `lint --minimal-tree` is retired and now refuses with
  exit 2.
- Roles that may cite a reused suite: Implementation and TDD GREEN
  re-checks, Remediation re-checks, and intermediate Validation and Code
  Review rounds. They cite it as reused with the original run id and log and
  read that log. TDD RED observations and mutation runs never reuse.

## Data model

- `tests/skills/suite-reuse.json` (tracked): `version` and, per suite,
  `inputs` (extra files it still needs declared), `live` (true means never
  reusable) and a `note` saying why the suite is declared. A suite is declared
  only when `lint --admit` passes for it.
- `tests/skills/results/reuse/` (gitignored, local only): one record per
  suite with the identity hash, its component hashes, the recorded read trace, the run id, the
  finished time, the log path and the log's sha256. A failed or skipped suite
  removes its record.
- Run outputs: `metrics.jsonl` gains `status: REUSED` with `reused_from_run`
  and `reused_log`; the `docs/ai/tests/test-runs.jsonl` line gains `reused`
  while `total` stays the executed count.

## Interfaces and contracts

- `node .aai/scripts/suite-reuse.mjs check|arm|collect|record|forget|lint|explain`:
  the helper the framework calls (`arm` and `collect` bracket a suite run to
  capture its read trace; `lint --admit [--suite S] [--changed-since REF]` is
  the admission gate). `check` prints `REUSE` or `RUN reason=<why>` per suite
  (for example `no-record`, `log-missing`, `policy`, or the first identity
  component that changed).
- `lint` reasons include `not-gate-selected` and `gate-row-missing`.
- Framework output: `Evidence reuse: on (<M> of <N> suites reused, check
  <s>s)`, a `REUSED (run …, …, log …)` line per reused suite and a
  `Reused: <M>` summary line.
- `AAI_SUITE_REUSE=0` turns reuse off; the framework sets it for every suite
  it executes, and `release-dry-run.mjs` sets it for the release check.
- `.aai/SKILL_VERIFY.prompt.md` "Reuse exception" and
  `.aai/VALIDATION.prompt.md` step 5 state when reused evidence counts.

## Limits and non-goals

- The split. Two of the five large suites are now two suites each: the
  cases that need only a handful of files stay in `aai-hygiene-pack` (66
  cases) and `aai-win-fallback` (27 cases), and the cases that read the git
  index or whole trees (the specs, the suite files, the run ledgers) moved to
  `aai-hygiene-corpus` (29 cases) and `aai-win-fallback-corpus` (5 cases).
  The sum is the same as before: every case runs in exactly one half, and the
  suite tests pin that. After an ordinary edit the two fixture halves are
  reused (they read about 160 and 57 files, not the index); the two corpus
  halves, `aai-docs-content`, `aai-spec-lint` and `aai-prompt-diet` still
  run, because each reads the git index or the whole tree. The corpus half of
  the hygiene pack is also in the always-on CI core, so the core is five
  suites (`aai-check-state`, `aai-docs-content`, `aai-spec-lint`,
  `aai-hygiene-pack`, `aai-hygiene-corpus`).
- Measured saving: on the five-suite re-check, two paired edits (one
  script, one document) went from a median of about 106 s with reuse off to
  about 71 s with it on (two of seven suites reused, three runs each).
  Tables: docs/analysis/precise-suite-evidence-reuse.md, section
  "Measurements (corpus split)". The three other large suites
  (`aai-docs-content`, `aai-spec-lint`, `aai-prompt-diet`) read the git index
  and still rerun after any edit; splitting them is not planned.
- Known gap, filed as `fu-admit-tests-red-on-other-suites`: TEST-3307 and
  TEST-3337 fail on a branch where local admission admits only other
  manifest suites (for example a branch that changes only the pricing suite).
  They pass on main and on this branch.
- Reuse is off where file access times are not recorded (a volume mounted
  without access-time updates, or a failed probe): nothing is recorded
  (`trace-unavailable`) and every suite runs.
- A bash startup hook is not part of the identity. When `BASH_ENV`, `ENV`,
  `SHELLOPTS`, `BASHOPTS` or an exported bash function (`BASH_FUNC_*`) is set
  and non-empty, every suite runs (reason `bash-startup-hook`) and a pass is
  never stored, which also drops any older record of that suite; the hook is
  never hashed. In Windows Git Bash degraded mode the wrapper sets `BASH_ENV`
  itself, so reuse is off there.
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
- Corpus split: docs/issues/CHANGE-0244-reuse-split-corpus-cases.md; spec docs/specs/SPEC-0271-spec-reuse-split-corpus-cases.md
- Trace identity: docs/issues/CHANGE-0242-reuse-for-docs-reading-suites.md; spec docs/specs/SPEC-0268-spec-reuse-for-docs-reading-suites.md
- Validation evidence: docs/ai/reports/VALIDATION-precise-suite-evidence-reuse-r12.md
