---
id: precise-suite-evidence-reuse
type: analysis
status: draft
updated: 2026-10-31
---

# Precise reuse of local suite results: measured effect

Spec: docs/specs/SPEC-DRAFT-spec-precise-suite-evidence-reuse.md (D11, Spec-AC-13
as amended by M1). This note reports what reuse bought on three rounds and,
plainly, where it did not. It makes no claim that reuse is faster on the
representative round: on that round it reused nothing.

## Measurements

R1 and R2 were measured on commit 97790628adef95b13736e79e0bb3c8d7a61e2f53
(the branch tip that carried the helper, the manifest and the framework
wiring); R3 was re-measured after validation round 1 on commit
316d1187c28154f0651d964e0fad232a63df6d51, the commit that corrects the manifest
(see the R3 line). Each round ran in a disposable detached worktree of its
commit, never in the shared main checkout. Each round: one seed run with reuse on on the clean tree, a copy of
`tests/skills/results/reuse/` as a snapshot, the round delta applied, then six
samples alternating off (`AAI_SUITE_REUSE=0`) and on, restoring the store from
the snapshot before every on sample. Command per sample:
`bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh --skill <each suite>`
with `AAI_TEST_TIMEOUT=3000` and `AAI_ROLE` unset. Wall seconds are whole
seconds from `date +%s` around the command. "Check s" is the number printed on
the framework line `Evidence reuse: on (<M> of <N> suites reused, check <s>s)`.

- R1: the M5 round of the spec, a remediation-shaped delta of one comment line
  appended to `.aai/scripts/ride-status.mjs`. Suites: aai-check-state,
  aai-docs-content, aai-spec-lint, aai-hygiene-pack, aai-ride-status,
  aai-win-fallback, aai-prompt-diet (7).
- R2: a second round whose delta is one production-script edit that changes
  no docs/ file: one comment line appended to `.aai/scripts/orchestration-mode.mjs`.
  Suites, as selected plus CORE by `select-suites.mjs`: aai-check-state,
  aai-docs-content, aai-spec-lint, aai-hygiene-pack, aai-orchestration-mode,
  aai-prompt-diet (6).
- R3: a supplementary round, added after R1 and R2 reused nothing, to show
  where reuse does help: the five suites declared in the manifest
  (aai-feedback-status, aai-pricing, aai-redact, aai-orchestration-mode,
  aai-runtime-file) re-checked after a comment line was appended to the
  unrelated production script `.aai/scripts/pr-preflight.mjs`. R3 was first
  measured with aai-check-state in the manifest in place of aai-feedback-status
  (4 of 5 reused); validation round 1 showed that aai-check-state reads files
  outside its identity, so it was removed and R3 was measured again on the
  corrected manifest. The table and medians below are the second measurement.
  R1 and R2 stay as first measured: aai-check-state was run in both modes of
  those rounds, so removing it from the manifest changes neither their wall
  time nor their reused count (0).

| Round | Sample | Mode | Wall s | Executed | Reused | Check s |
|---|---|---|---|---|---|---|
| R1 | 1 | off | 93 | 7 | 0 | - |
| R1 | 1 | on | 92 | 7 | 0 | 0 |
| R1 | 2 | off | 93 | 7 | 0 | - |
| R1 | 2 | on | 94 | 7 | 0 | 0 |
| R1 | 3 | off | 92 | 7 | 0 | - |
| R1 | 3 | on | 92 | 7 | 0 | 0 |
| R2 | 1 | off | 91 | 6 | 0 | - |
| R2 | 1 | on | 91 | 6 | 0 | 0 |
| R2 | 2 | off | 90 | 6 | 0 | - |
| R2 | 2 | on | 99 | 6 | 0 | 0 |
| R2 | 3 | off | 106 | 6 | 0 | - |
| R2 | 3 | on | 100 | 6 | 0 | 0 |
| R3 | 1 | off | 4 | 5 | 0 | - |
| R3 | 1 | on | 1 | 0 | 5 | 0 |
| R3 | 2 | off | 5 | 5 | 0 | - |
| R3 | 2 | on | 1 | 0 | 5 | 0 |
| R3 | 3 | off | 5 | 5 | 0 | - |
| R3 | 3 | on | 2 | 0 | 5 | 0 |

Round R1 medians: off 93 s, on 92 s, reused 0 of 7 suites (worst off 93 s, worst on 94 s).

Round R2 medians: off 91 s, on 99 s, reused 0 of 6 suites (worst off 106 s, worst on 100 s).

Round R3 medians: off 5 s, on 1 s, reused 5 of 5 suites (worst off 5 s, worst on 2 s).

Every check time is 0 s (limit 5 s). On R1 and R2 the on and off medians differ
by run-to-run noise only (92 against 93, 99 against 91): nothing was reused, so
the on mode did the same work plus a sub-second identity calculation.

Environment: host Apple M4 Max, 16 logical CPUs, macOS 27.0.1 (Darwin 27.0.0 arm64);
Node v22.23.1; Bash GNU bash 3.2.57(1)-release (the system bash the framework
runs under); Git 2.54.0 (Apple Git-157).

R3 re-measured on 2026-11-01 at commit cb2cafdd (after the after-literal rule
and the `lib/` allowlist), same delta and procedure, five separate wrapped
framework runs per sample (one per suite, so each sample also carries five
wrapper start-ups): off 16 s in all three samples, on 10 s in all three,
reused 3 of 5 (aai-feedback-status, aai-pricing, aai-redact);
aai-orchestration-mode and aai-runtime-file ran in both modes.

### Where reuse helps

Reuse helps for a suite whose declared identity is narrow: its suite file, the
shared-library tree, the harness and a handful of named data files. R3 shows
it: all five manifest suites were reported REUSED and skipped, wall time 5 s
to 1 s (an all-reused run executes nothing; its summary carries `Reused: 5` and
`Total: 0`). That measurement is tied to its commit: at the head of 2026-11-01 only 3 of the 5 manifest suites can reuse, because aai-orchestration-mode and aai-runtime-file are inputs-unresolvable (a `${VAR:-path}` literal) and always run. The absolute saving is
small because the manifest suites are the cheap, pure ones (weights of a few
seconds). It would grow with more suites qualified into the manifest, but only
suites whose closure stays narrow can qualify honestly.

### Why the docs-closure suites miss

The expensive suites of the representative round are not reusable, by design
and by measurement. `suite-reuse.mjs explain` on aai-docs-content,
aai-spec-lint, aai-hygiene-pack, aai-prompt-diet, aai-ride-status and
aai-win-fallback gives closures of about 3,430 files, 2,506 of them under
docs/, including docs/ai/EVENTS.jsonl and the docs/ai/STATE files. Three
mechanisms keep those identities moving:

- The framework itself appends a line to the tracked
  `docs/ai/tests/test-runs.jsonl` on every run, and EVENTS and STATE change
  with every role action, all under docs/. Any suite whose closure reaches
  docs/ sees a different identity on the very next run, even with no edit.
- Shared-library prose literals: test-side files under `tests/skills/lib/`
  (for example `prompt-diet-ledger.sh`, `docs-audit-live.sh`) name docs/
  directories in text, and the closure follows every such literal, so a suite
  that merely sources the lib inherits the whole docs/ tree.
- These suites also read the real repository history (a history marker in the
  closure), so HEAD is part of the identity.

None of these suites is in the manifest, so they report
`RUN <suite> reason=not-declared`; the rule that errs toward a miss is working
as designed. Listing them would give a false hit risk (R1 of the spec) that the
measured closure shows cannot be bounded by a reviewed `note`.

One further miss in R1 and R2 is not docs-related. aai-orchestration-mode is
the suite whose own input was edited in R2, a legitimate miss.

aai-check-state was in the manifest when R1 to R3 were first measured, and it
missed in all three rounds, which the first draft of this note put down to the
closure rule reading a sandbox write destination (`$sandbox/.aai/scripts/`) as
a directory of 176 files. That explanation was incomplete and the suite did not
belong in the manifest. Validation round 1 traced its reads and showed that it
also runs `orchestration-dispatch.mjs` against the real checkout, which reads
`docs/TECHNOLOGY.md`, `.aai/workflow/WORKFLOW.md`, `.aai/system/LOCKS.md`,
`.aai/system/MODEL_ROUTING.yaml`, `docs/ai/roadmap.yaml` and `docs/issues/*`
(359 files), none of them in its identity. Renaming `docs/TECHNOLOGY.md` left
the suite reported REUSED although a re-run failed. The suite was removed from
the manifest; the miss in R1 to R3 was thus a symptom of a closure that was
too narrow in one direction and too wide in another, not a tuning problem.

## Manifest suites

aai-feedback-status, aai-pricing, aai-redact, aai-orchestration-mode,
aai-runtime-file (five suites, `tests/skills/suite-reuse.json`). None of the
seven suites of the M5 round qualifies: they either read docs/ broadly or are
dominated by the docs closure described above, so no honest `note` can bound
their reads. Each manifest suite is qualified by a Node fs read trace of the
whole suite plus a literal review of its bash, and TEST-3193 repeats the trace
on every run of the reuse suite, so a manifest entry whose traced Node fs read
falls outside its identity fails the test instead of waiting for a validator
to find it.

The trace is narrower than "reads nothing outside the identity". These read
paths are not traced and are covered only by the literal bash review and the
manifest note: bash `cat`, `grep`, `cp` and `source`; `git` commands; Node
`fs.promises` reads; `fs.copyFileSync` and `fs.cpSync`; and any child process
whose environment drops `NODE_OPTIONS` (release-dry-run.mjs does). A manifest
suite that reads a docs file through bash `cat` passes TEST-3193. The residual
risk R1 therefore stands for those channels.

## Measurements (trace identity)

The SPEC-0266 section above stays as history. This section measures the access
trace identity of the change that replaced the source-text reader, following
the protocol of its D11. Measured commit: 770210a1c5c2081339bcc9482b0a518c9db1f8f8
(the implementation tip), in a disposable detached worktree of that commit,
never in the shared main checkout.

Method. Suites (8): aai-check-state, aai-docs-content, aai-spec-lint,
aai-hygiene-pack, aai-pr-preflight, aai-prompt-diet, aai-ride-status,
aai-win-fallback. One seed run with reuse on; a copy of
`tests/skills/results/reuse/` as the snapshot; then two rounds, each with six
samples alternating off (`AAI_SUITE_REUSE=0`) and on, restoring the store from
the snapshot before every on sample. R0 is the zero delta (no edit). R1 appends
one comment line to `.aai/scripts/pr-preflight.mjs`. Command per sample:
`bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh` with one `--skill` per
suite, `AAI_TEST_TIMEOUT=3000`, `AAI_ROLE` unset. Wall seconds are whole seconds
from `date +%s`; "Executed" is the framework's Total line, "Reused" its Reused
line, "Check s" the number on `Evidence reuse: on (<M> of <N> suites reused, check <s>s)`.
All twelve samples exited 0.

| Round | Sample | Mode | Wall s | Executed | Reused | Check s |
|---|---|---|---|---|---|---|
| R0 | 1 | off | 105 | 8 | 0 | - |
| R0 | 1 | on | 108 | 7 | 1 | 1 |
| R0 | 2 | off | 107 | 8 | 0 | - |
| R0 | 2 | on | 110 | 7 | 1 | 0 |
| R0 | 3 | off | 109 | 8 | 0 | - |
| R0 | 3 | on | 124 | 7 | 1 | 1 |
| R1 | 1 | off | 109 | 8 | 0 | - |
| R1 | 1 | on | 121 | 7 | 1 | 0 |
| R1 | 2 | off | 104 | 8 | 0 | - |
| R1 | 2 | on | 118 | 7 | 1 | 0 |
| R1 | 3 | off | 128 | 8 | 0 | - |
| R1 | 3 | on | 123 | 7 | 1 | 0 |

Round R0 medians: off 107 s, on 110 s, reused 1 of 8 suites (worst off 109 s, worst on 124 s).

Round R1 medians: off 109 s, on 121 s, reused 1 of 8 suites (worst off 128 s, worst on 123 s).

On did not beat off in either round: the one suite that reuses is the cheapest
of the large ones (aai-ride-status, about 15 s) and it runs concurrently with
the longest suite (aai-hygiene-pack, about 95 s), which sets the wall time, so
reusing it saves nothing on the wall clock. The differences between the
medians (110 against 107, 121 against 109) are run-to-run noise of this
host plus a check of at most 1 s. The lesson is the one the spec predicted.

Per suite, the outcome of every on sample (identical in all three samples of
a round; the RUN reason is what `suite-reuse.mjs check` printed against the
restored store, with the framework's own environment, and the framework
executed exactly the suites it names) and the files the recorded trace read:

| Suite | Files read (record) | R0 on | R1 on |
|---|---|---|---|
| aai-check-state | not traced (not in the manifest) | RUN reason=not-declared | RUN reason=not-declared |
| aai-docs-content | 1536 files, git index read | RUN reason=inputs changed docs/ai/tests/test-runs.jsonl | RUN reason=inputs changed .aai/scripts/pr-preflight.mjs |
| aai-spec-lint | 1481 files, git index read | RUN reason=inputs changed docs/ai/tests/test-runs.jsonl | RUN reason=inputs changed .aai/scripts/pr-preflight.mjs |
| aai-hygiene-pack | 1950 files, git index read | RUN reason=inputs changed docs/ai/tests/test-runs.jsonl | RUN reason=inputs changed .aai/scripts/pr-preflight.mjs |
| aai-pr-preflight | not traced (not in the manifest) | RUN reason=not-declared | RUN reason=not-declared |
| aai-prompt-diet | 1935 files, git index read | RUN reason=inputs changed docs/ai/tests/test-runs.jsonl | RUN reason=inputs changed .aai/scripts/pr-preflight.mjs |
| aai-ride-status | 27 files, git index not read | REUSED | REUSED |
| aai-win-fallback | 1935 files, git index read | RUN reason=inputs changed docs/ai/tests/test-runs.jsonl | RUN reason=inputs changed .aai/scripts/pr-preflight.mjs |

What the table shows. aai-ride-status, which the source-text reader could never
reuse (3,188 inputs, 2,194 unresolvable forms), is reused after a zero delta
and after an edit of an unrelated production script, with 27 files read. The
five large suites read the whole checkout, so they are admitted but are reused
only when no tracked file changed; even the zero delta misses, because the
framework appends a line to the tracked `docs/ai/tests/test-runs.jsonl` after
every run and those suites read that file (follow-up
`fu-reuse-local-ledger-append`). The corpus-wide cases of those suites would
have to be split from their fixture cases to change this
(`fu-reuse-split-corpus-cases`). No edit of the ledger writer was made.

Trace cost: arm plus collect took 178 ms (median of five, range 167 to 219 ms;
arm about 155 ms, collect about 20 ms) on the 1,950-file checkout of the
measured commit, per traced suite, run in-process on a fresh local clone. The
framework's per-suite overhead beyond that is the two helper process starts.

Environment: host Apple M4 Max, 16 logical CPUs, macOS 27.0.1 (Darwin 27.0.0
arm64); Node v22.23.1; Bash GNU bash 3.2.57(1)-release; Git 2.54.0 (Apple
Git-157).
