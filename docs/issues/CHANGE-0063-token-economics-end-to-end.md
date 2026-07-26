---
id: token-economics-end-to-end
number: 63
type: change
status: draft
links:
  pr: []
  commits: []
---

# Change — Token economics end-to-end: metrics-report reads usage notes; overview v2 shows cost per feature

## Summary
- Close the last gap in the telemetry chain: agent runs now record real
  harness totals as `usage_total_tokens=<N>` notes (SPEC-0043/SPEC-0085),
  but `metrics-report.mjs` and the stakeholder overview ignore them — cost
  per role/feature is still invisible. Teach metrics-report to aggregate the
  note grammar, and upgrade the overview page: per-item agent token totals,
  grouping by release, and automatic regeneration during the close ceremony
  so the page never goes stale.

## Motivation / Business Value
- Auditor roadmap items 7+1 (2026-07-27 order): tiering/routing economics
  (MODEL_ROUTING) cannot be evaluated while reports show n/a; yesterday's
  six rides recorded ~1.6M tokens of real usage notes that no report reads.
- The overview (docs/ai/overview.html) is the operator/stakeholder surface;
  regenerating it manually after each close is exactly the drift the factory
  exists to remove.

## Scope
- In scope:
  - .aai/scripts/metrics-report.mjs: parse the canonical delimited
    `usage_total_tokens=<N>` marker (same boundary regex as metrics-flush)
    from agent_runs notes; per work item report summed undecomposed totals
    (column "agent tokens (undecomposed)"); per role rollup section; never
    fabricate a cost from totals (pricing needs an in/out split — display
    tokens, not USD).
  - .aai/scripts/generate-overview.mjs: per delivered item show summed
    usage-note tokens (from METRICS.jsonl) alongside agent minutes; group
    the Delivered section by release where docs/releases frontmatter links
    items, else by close month; counts row gains total recorded tokens.
  - Auto-regen at close: .aai/scripts/close-work-item.mjs invokes the
    overview generator best-effort after a successful close (swallow
    failures — the close verdict never depends on a report page).
  - Tests: metrics-report marker-parse fixtures (valid, malformed-marker
    falls out, boundary-delimited); overview data joins; close-ceremony
    regen invocation (fixture root).
- Out of scope: pricing/USD computation from undecomposed totals (would
  fabricate an in/out split); dashboard.html; any schema change.

## Affected Area
- .aai/scripts/metrics-report.mjs, .aai/scripts/generate-overview.mjs,
  .aai/scripts/close-work-item.mjs (post-close best-effort hook),
  tests/skills (metrics/report + close-work-item suites), docs.

## Desired Behavior (To-Be)
- `node .aai/scripts/metrics-report.mjs` shows real token totals per work
  item and per role wherever usage notes exist; n/a only where nothing was
  recorded.
- `docs/ai/overview.html` shows tokens per delivered item, groups by
  release, and refreshes itself on every successful close-work-item run.

## Acceptance Criteria
- AC-001: metrics-report sums only canonical delimited markers (fixture:
  valid marker counted; `not_usage_total_tokens=1` and `usage_total_tokens=1x`
  ignored) and renders per-item + per-role token columns (suite-verified).
- AC-002: overview per-item tokens equal the METRICS fixture sums; counts
  header shows the grand total (suite or script-probe verified).
- AC-003: close-work-item on a fixture root regenerates overview-data.json
  best-effort; a generator failure does not change close-work-item's exit
  code (negative control).
- AC-004: Delivered grouping: items linked from a release doc render under
  that release heading; unlinked items fall back to close-month groups.
- AC-005: no regression — targeted suites green locally; full run on PR CI.

## Verification
- bash tests/skills/test-aai-metrics.sh (new report stanzas)
- bash tests/skills/test-aai-close-work-item.sh (regen hook + negative control)
- node .aai/scripts/metrics-report.mjs on the real ledger (spot-check)
- PR CI full framework.

## Constraints / Risks
- No secrets referenced (secrets preflight skipped).
- Ceremony L2 expected: close-work-item.mjs is NOT in the protected_paths_l3
  list (verify at planning); the hook must be strictly best-effort.
- Marker regex must match metrics-flush's boundary semantics exactly —
  divergence would reintroduce the two-definitions risk; import/share or
  test-pin the equivalence.
- Scripts are outside the prompt-diet glob (no ledger cost); PROFILES has
  both scripts classified already (extended) — verify, no new file planned.

## Notes
- Roadmap items 7+1 (auditor report, order confirmed by operator
  2026-07-27 with run-level autonomy incl. merges). Autopilot intake:
  metrics question skipped, human_time_minutes null.
