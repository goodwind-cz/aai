---
id: ride-cost-readout
number: 148
type: change
status: draft
user_visible: true
ceremony_level: 1
capability: factory-performance-report
links:
  pr: []
  commits: []
---

# Change — what a scope cost, without anyone adding it up by hand

## Summary
- The factory records every role run but never totals one scope. Answering
  "how long did this take" or "how many tokens" means reading
  `docs/ai/METRICS.jsonl` by hand, which is what happened four times on
  2026-08-16/17.
- Add a per-scope cost section to the existing factory report: elapsed span,
  runs per role, tokens overall and by role, and how much of that went into
  rounds that ended in a finding. Report-only.

## Motivation / Business Value
- CHANGE-0145 ran about 30 hours across five validation rounds, CHANGE-0146
  about 15 across five. Nobody saw either number until it was computed by hand
  after the fact. Seen while the ride was running, the decision to stop would
  have come earlier — the owner asked for exactly that twice.
- The value is deciding about scope, not another check. Nothing here gates,
  refuses or changes an exit code.

## Scope
- In scope: aggregation over the already-committed `docs/ai/METRICS.jsonl`, and
  a new section in `.aai/scripts/generate-factory-report.mjs`'s output.
- Out of scope: any new data collection; any gate or budget enforcement; the
  dashboard (`generate-dashboard.mjs`) — one surface at a time.

## Affected Area
- `.aai/scripts/generate-factory-report.mjs`
- `docs/ai/factory-report.html` and `factory-report-data.json` (generated)
- the factory-report test suite

## Desired Behavior (To-Be)
- For each closed scope the report shows: elapsed span from the first run's
  start to the last run's end; the count of runs per role; total tokens and a
  per-role split; and a rework figure — the share spent on rounds that ended in
  a finding.
- A scope with no usable data says so by name rather than rendering zeros.

## Acceptance Criteria
- AC-001: for a scope with runs, the report shows an elapsed span computed from
  the first `started_utc` and the last `ended_utc` in that scope's `agent_runs`.
- AC-002: the report shows a per-role run count for that scope.
- AC-003: token totals come from the canonical `extractUsageTotal` in
  `.aai/scripts/lib/usage-note.mjs`, never from a private regex, and a run
  whose note carries no usage marker contributes nothing rather than zero.
- AC-004: the rework figure is derived structurally — every `Remediation` run
  is a round that ended in a finding — and never from prose in a note.
- AC-005: a scope whose runs carry no usage markers renders a named no-data
  line, not a zero.
- AC-006: no exit code changes and no gate is introduced.
- AC-007: the section renders in both the HTML and the JSON form.

## Verification
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-factory-report.sh`
- `node .aai/scripts/generate-factory-report.mjs` over this repo, then read the
  CHANGE-0145 and CHANGE-0146 rows against the hand figures recorded in the
  ride reports (roughly 30 h / 15 h, five validation rounds each)
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` clean

## Constraints / Risks
- **The premise was checked before writing this and only half holds.** Verified
  on 2026-08-17:
  - `docs/ai/LOOP_TICKS.jsonl` is gitignored (`.gitignore:80`) and
    per-developer local, so tick counts CANNOT appear in a committed report.
    They are dropped from the ask; do not reintroduce them by reading that file.
  - `tokens_in` and `tokens_out` in `agent_runs` are `null` in practice. The
    real figure lives in the `note` as `usage_total_tokens=N`, which is why
    AC-003 binds to the canonical parser the dashboard already uses.
  - There is no schema field marking a round as having ended in a finding. The
    `verdict=fail` text some notes carry is an ad-hoc convention invented
    mid-ride and is not consistent; AC-004 therefore derives rework from the
    presence of `Remediation` runs instead.
- `totals.agent_duration_seconds` is summed agent time, not wall clock; the two
  differ by a lot when roles run in the background. Say which one is shown.
- Extend the existing generator. Only create a new file if the aggregation
  genuinely does not belong there, and justify it in the spec.
- No secret is referenced by this scope.

## Notes
- Strategy suggestion: direct with targeted tests. This is aggregation over an
  existing ledger with a fixture-driven suite; there is no new subsystem.
- `ceremony_level: 1` is an intake suggestion — one generator plus its suite.
  Planning declares the binding value.
- Related registry items deliberately NOT closed by this scope:
  `fu-context-window-telemetry` (a different measurement) and
  `fu-factory-report-sparkline-scale` (a rendering defect in the same file).
