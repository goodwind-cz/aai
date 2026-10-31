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

Measured on commit 97790628adef95b13736e79e0bb3c8d7a61e2f53 (the branch tip
that carries the helper, the manifest and the framework wiring), in a
disposable detached worktree of that commit, never in the shared main
checkout. Each round: one seed run with reuse on on the clean tree, a copy of
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
  (aai-check-state, aai-pricing, aai-redact, aai-orchestration-mode,
  aai-runtime-file) re-checked after a comment line was appended to the
  unrelated production script `.aai/scripts/pr-preflight.mjs`.

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
| R3 | 1 | off | 5 | 5 | 0 | - |
| R3 | 1 | on | 3 | 1 | 4 | 0 |
| R3 | 2 | off | 5 | 5 | 0 | - |
| R3 | 2 | on | 3 | 1 | 4 | 0 |
| R3 | 3 | off | 4 | 5 | 0 | - |
| R3 | 3 | on | 3 | 1 | 4 | 0 |

Round R1 medians: off 93 s, on 92 s, reused 0 of 7 suites (worst off 93 s, worst on 94 s).

Round R2 medians: off 91 s, on 99 s, reused 0 of 6 suites (worst off 106 s, worst on 100 s).

Round R3 medians: off 5 s, on 3 s, reused 4 of 5 suites (worst off 5 s, worst on 3 s).

Every check time is 0 s (limit 5 s). On R1 and R2 the on and off medians differ
by run-to-run noise only (92 against 93, 99 against 91): nothing was reused, so
the on mode did the same work plus a sub-second identity calculation.

Environment: host Apple M4 Max, 16 logical CPUs, macOS 27.0.1 (Darwin 27.0.0 arm64);
Node v22.23.1; Bash GNU bash 3.2.57(1)-release (the system bash the framework
runs under); Git 2.54.0 (Apple Git-157).

### Where reuse helps

Reuse helps for a suite whose complete identity is narrow: its suite file, the
shared-library tree, the harness and a handful of named data files. R3 shows
it: four of the five manifest suites (aai-check-state missed, see below) were
reported REUSED and skipped, wall time 5 s to 3 s. The absolute saving is
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

Two further misses in R1 and R2 are not docs-related. aai-check-state is in
the manifest, but its test file writes into a fixture sandbox under
`$sandbox/.aai/scripts/`, a literal that the closure rule reads as a directory
and expands to the 176 files of `.aai/scripts/` (plus lib and templates), so any
production-script edit changes its identity (R1 reason: changed
`.aai/scripts/ride-status.mjs`; R2 and R3: the edited script). The orchestrator
decision for this ride kept that rule (no relaxation for write positions)
because a false hit is the main hazard. aai-orchestration-mode is the suite
whose own input was edited in R2, a legitimate miss.

## Manifest suites

aai-check-state, aai-pricing, aai-redact, aai-orchestration-mode,
aai-runtime-file (five suites, `tests/skills/suite-reuse.json`). Of the M5
round, aai-check-state is the only one listed; the other six M5 suites are
not declared, for the reasons above.
