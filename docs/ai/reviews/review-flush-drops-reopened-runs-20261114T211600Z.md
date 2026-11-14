```yaml
review:
  scope: af555d1b8ee217463d0976097591ba758761201f..a783df5f (delta re-check, PR #556)
  spec: docs/specs/SPEC-0291-spec-flush-drops-reopened-runs.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-07, call: compliant,
          citation: "lib/metrics-flush-record.mjs:52-121; factory-report:241; metrics-report:207; generate-dashboard.mjs:190-211; golden-flow.mjs:334-343; TEST-3728..3733 green this round" }
      - { ac: Spec-AC-01..06, call: compliant,
          citation: "unchanged by the delta except AC-06 CHANGELOG/telemetry.md additions; TEST-3727 green inside test-aai-metrics.sh this round" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/metrics-flush-record.mjs, line: 98,
          issue: "the fold keeps only the latest segment's validation_waiver, so a waiver recorded on an earlier segment of the same ref is dropped from the factory report's waiver section",
          failure_scenario: "segment 1 carries an operator waiver and segment 2 an agent waiver: base reports operator 1 / agent 1, head reports operator 0 / agent 1 with the ride shown as agent self-waived, which contradicts generate-factory-report.mjs:462 (a ride carrying both kinds is reported as OPERATOR)" }
  cannot_verify:
    - { claim: "downstream consumer ledgers hold only single-line refs",
        closes_with: "a scan of a downstream METRICS.jsonl; the byte-identity check here used this repo's ledger with its one continuation line removed" }
  overall: pass
```

security_relevant: false

# Code Review delta re-check: flush-drops-reopened-runs (PR #556)

- Role: Code Review (delta re-check under `.aai/RECHECK_DELTA.prompt.md`)
- Spec: `docs/specs/SPEC-0291-spec-flush-drops-reopened-runs.md`. Spec-AC-07 was added by a disclosed amendment, recorded in decisions.jsonl as an unsigned-tracked row under `fu-amend-spec-flush-drops-reopened-runs`.
- Range: `af555d1b..a783df5f` (commits 62907009 and a783df5f)
- Started 2026-11-14T21:08:10Z, ended 2026-11-14T21:16:00Z

## Prior findings

| Prior finding | Status | Evidence observed this round |
|---|---|---|
| Review 191328Z NB-1 (P3): continuation lines re-record human time | Still open, tracked by `fu-continuation-rerecords-human-time`. The readers now mitigate it. | `mergeSegments` takes the maximum, not the sum (metrics-flush-record.mjs:63-65, 75). TEST-3731 asserts `human 15` and `- Human time: 15 min` and is green this round. |
| Review 195051Z NB-R1 (P3): restamp recorded as an unverified-cause amendment | Still open, tracked | `spec-amend list --strict` rc 0. It shows 2 unsigned-tracked rows (19:20:51Z and 20:25:28Z) under `fu-amend-spec-flush-drops-reopened-runs`, status open. |
| Validation 2045Z NB-1: telemetry.md said the dashboard uses `foldRideSegments` | **Fixed** in a783df5f | telemetry.md now reads "the dashboard's work-item count counts distinct `ref_id` values directly". That matches generate-dashboard.mjs:193-210. |
| Validation 2045Z NB-2: human-time sub-fields are maxed separately | Still open, covered by `fu-continuation-rerecords-human-time` | metrics-flush-record.mjs:65 is unchanged. |
| Validation 2045Z NB-3: AC-07 evidence cited a range path that does not exist | **Fixed** in a783df5f | The spec at line 323 now names six files. `ls` shows all six `docs/ai/tdd/spec-flush-drops-reopened-runs/mutation-TEST-372{8,9}/373{0..3}.txt` files exist. |
| Validation 2045Z NB-4: the latest-date loop is not pinned for out-of-order lines | Still open, filed | decisions.jsonl has `fu-fold-latest-date-unpinned` (P3, 21:07:43Z). Probe: out-of-order lines give date 2026-11-12 (the latest) and verdict FAIL (from the last line), as documented. |

## Delta read: foldRideSegments and the readers

- **Ordering.** The merged record sits at the position of the ref's last line. Single-line refs and pass-through records keep their positions. Runs are concatenated in ledger order, using the same run objects, so the `_cost` that metrics-report sets on each run survives the fold.
- **Null handling.** Probes ran against the HEAD library at `<scratch>/probe/fold-probe.mjs`:
  - A segment with no totals gives `total_cost_usd: null`, and its seconds come from its runs.
  - With no totals or reliability anywhere, neither key is invented.
  - `null`, a string, and a record without `ref_id` all pass through.
  - A `worktree_create` event with the same ref passes through unfolded.
  - `ref_id` `r` and `R` stay separate refs: matching is exact.
- **Reliability merge.** The counts are summed. `first_pass_clean` is false if any segment is false, true only if all are true, and null otherwise. Basis is `mixed` when the segments disagree. These rules match the flusher's definition (metrics-flush.mjs:772: the flag is clean when all three counts are 0).
- **`verdict_after_last_implementer`.** It comes from the latest segment, so it is null when the continuation line has no implementer run. No reader consumes this field (grep over `.aai/scripts`), so this is information only, not a finding.
- **Purity and double fold.** The inputs are not mutated, and `fold(fold(x))` deep-equals `fold(x)`. No reader folds twice. `generate-overview.mjs:275-341` already sums per ref and does not fold. `docs-audit-core`, `orchestration-dispatch` and `validation-waiver` only test whether a ref is present, or count per segment. The doctor's CAT-07 counts lines, labelled "entries".
- **Run-level sections still read unfolded lines.** In metrics-report, `--by-effort` and `allRuns` are built before the fold. The dashboard's per-run operations are also unfolded.
- **Byte identity for single-line refs.** Base (af555d1b) and HEAD readers were extracted to scratch and both run on the live ledger with its one continuation line removed (249 lines). The outputs were compared:
  - `metrics-report` and `metrics-report --by-effort` are byte-identical (`cmp`).
  - The factory-report and dashboard HTML and data JSON are identical once `generated*` timestamps are masked.
  - `tokensMedianLast10` is 1514084 for both.
  - On the live ledger the median moves from 1487556 to 1574950, which is the intended fold.
- **Performance.** 20,000 lines across 5,000 refs fold in 47 ms. 3,000 segments of one ref fold in 6 ms. A ~220-line ledger costs nothing measurable.
- **Golden-flow.** The new `r &&` guard also stops a crash on a JSON `null` line; previously `r.agent_runs` threw.
- **Tests.** All four suites run under `set -euo pipefail`. In TEST-3731, the `printf | grep -qF` pipelines feed a few hundred bytes, well under the pipe buffer, so an early-closing reader is not a risk. `grep -c … || true` is safe when nothing matches. TEST-3730 checks the live ledger generically: it sums per ref and re-derives the shadow model independently, so it pins no ledger values. Its mutation bites only because the live ledger holds a multi-line ref. The ledger is append-only, so that remains true.

## Finding

### NB-W1 (NON-BLOCKING, P3): the fold drops the earlier segment's validation_waiver

- Location: `.aai/scripts/lib/metrics-flush-record.mjs:98`. The factory report consumes it at `.aai/scripts/generate-factory-report.mjs:362-475`.
- The issue: `mergeSegments` keeps only the validation_waiver of the latest segment that carries one. Before this delta, each line was its own ride, so both waivers were counted. Now one waiver silently disappears. The factory report's rule (line 462) says a ride carrying both kinds is OPERATOR with `self_waived: true`. After the fold, the report can never see both kinds on one ride.
- Repro: `<scratch>/probe/waiver-repro.sh` with `<scratch>/probe/waiver-ledger.jsonl`.
  - base: `{"operator":1,"agent":1,"rides":[["WR","operator",false],["WR","agent",true]]}`
  - head: `{"operator":0,"agent":1,"rides":[["WR","agent",true]]}`
  - The reverse order (agent waiver, then operator waiver) loses the agent's act, which line 462 says must never disappear.
- Why it is NON-BLOCKING:
  - No multi-line ref in the live ledger carries a waiver, and downstream ledgers have single-line refs, so it has not bitten.
  - Spec-AC-07 does not cover waivers.
  - The gate itself (`validation-waiver.mjs`) is untouched. Only the report surface is affected, so this is not security-relevant.
- Disposition: (a) remediate, or (b) suggested follow-up `suggested: fu-fold-keeps-one-segment-waiver` (P3; I did not file it).
  - Why not (d) `accepted residual`: when it bites, it leaves a false record in the report.
  - Fix shape: carry every distinct segment waiver, for example as a `validation_waivers` array, or have the factory report collect waivers from each folded segment. Then the operator-over-agent rule sees both kinds.

## Commands run this round (exit codes)

- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-factory-report.sh`: 0 (TEST-3728, 3729 and the 3730 arms PASS)
- `... test-aai-metrics.sh`: 0 (TEST-3731, 3727 PASS)
- `... test-aai-dashboard.sh`: 0 (TEST-3732 PASS)
- `... test-aai-golden-flow.sh`: 0 (TEST-3733 PASS)
- `... test-aai-overview.sh`: 0
- `node .aai/scripts/spec-amend.mjs list --strict`: 0
- `git ls-files -ci --exclude-standard`: empty
- Base-vs-head byte-identity run on the single-line ledger: identical, as listed above.

## Warning dispositions (H6)

- NB-W1 (this round): (a) remediate, or (b) `suggested: fu-fold-keeps-one-segment-waiver` (P3).
- Carried, unchanged:
  - `fu-continuation-rerecords-human-time` (NB-1 and validation NB-2)
  - `fu-amend-spec-flush-drops-reopened-runs` (NB-R1)
  - `fu-fold-latest-date-unpinned` (validation NB-4)

## Next steps

1. The orchestrator records `set-code-review` and publishes NB-W1 as a PR thread.
2. Before closeout, either fold the waivers or file the suggested follow-up.
