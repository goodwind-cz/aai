# SKILL: /aai-feedback-triage — offline friction triage (RFC-0012 Phase 2)

Thin wrapper over the deterministic engine `.aai/scripts/aai-feedback-triage.mjs`.
It reads the local friction spool, gates + scores + clusters the observations, and
writes a LOCAL triage report. This slice is OFFLINE — no GitHub token, no network,
no issue writes; `auto` is never producible.

## When to run
Explicitly, or at a safe session boundary (e.g. from `/aai-wrap-up`, or after a
failed AAI skill). Never a resident daemon.

## Run
```
node .aai/scripts/aai-feedback-triage.mjs [--spool <path>] [--config <path>] [--out <path>]
```
Defaults: spool `docs/ai/friction/observations.jsonl`, config `.aai/feedback.yaml`,
out `docs/ai/friction/triage-report.json`. `--help` documents the contract.

## Degrade
Missing/invalid `.aai/feedback.yaml` or an empty spool is not an error — the engine
runs in `local` mode and writes a report (possibly with zero clusters). The engine
performs no network I/O and holds no token; there is nothing to fail on.

## Report
`triage-report.json` lists, per fingerprint cluster: `failure_class`, `recurrence`,
a composite `score` (impact + confidence + reproducible + recurrence), a `decision`
(`review_candidate` at/above the configured threshold, else `retain`), and
`auto_publishable` (always `false` in this slice). Dropped observations are
summarized by gate reason. The operator reviews this locally; the review-mode
upsert that consumes it is a later slice.
