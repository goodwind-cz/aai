---
id: suite-map-factory-doc-paths
number: 73
type: change
status: done
user_visible: false
links:
  pr:
    - 173
  commits:
    - a61edc9b5f19f1d434e4c6fceb7dd7f5ff6fb2ea
---

# Change — suite-map: map factory doc trees so factory rides actually get selected mode

## Summary
- CHANGE-0071 shipped CI impact selection, but every factory ride commits
  generated/ledger doc paths (docs/INDEX.md, docs/ai/EVENTS.jsonl,
  docs/ai/METRICS.jsonl, docs/USER_GUIDE.md, overview.*, project-sessions
  journal) that had no suite-map row — so selection fail-opened to FULL_RUN
  on every factory PR (observed live on PR #171 and #172:
  `FULL_RUN reason=unmapped path=docs/INDEX.md`). The feature was de facto
  dormant for the factory itself. Add map rows assigning each factory doc
  path to its natural owner suite. Data-file-only change, protected by the
  fail-open design (worst case of a wrong row is over-selection or a
  full run, never silent loss: the three core suites — check-state,
  docs-audit strict, spec-lint — run on every selected-mode PR regardless).

## Motivation / Business Value
- Restores the intended 3-8 min PR loop for the factory's own rides
  (measured: typical ride doc-set now selects 3 core + ~7 owner suites,
  DROPPED 45, instead of 55-suite ~25 min full runs three times per ride).

## Scope
- In scope: tests/skills/suite-map.yaml rows only —
  docs/INDEX.md -> aai-doc-numbering + aai-docs-audit;
  docs/ai/EVENTS.jsonl, docs/project-sessions/**, docs/TECHNOLOGY.md ->
  aai-docs-audit; docs/ai/METRICS.jsonl -> aai-metrics;
  docs/ai/overview.html + overview-data.json -> aai-overview;
  docs/knowledge/** -> aai-learned-append; docs/ai/tdd/** ->
  aai-tdd-evidence; docs/ai/briefs/** -> aai-prune-stale-briefs;
  docs/ai/friction/** -> aai-friction.
- Out of scope: selector/workflow/test logic (unchanged); mapping
  non-factory paths.

## Acceptance Criteria
- AC-001: the typical factory ride doc-set (INDEX, CHANGELOG, EVENTS,
  METRICS, spec+issue, USER_GUIDE, product doc, session journal, LEARNED,
  overview.*) yields a selected-mode verdict with the owner suites listed
  and no FULL_RUN (probe-verified).
- AC-002: suite-select + hygiene-pack + layer-profiles suites stay green
  (no logic change; map stays 100% row-covered).
- AC-003: live proof — this PR's own CI run lands in mode=selected
  (recorded at PR time).

## Verification
- node .aai/scripts/select-suites.mjs --files-from <ride doc-set probe>
- bash tests/skills/test-aai-suite-select.sh; test-aai-hygiene-pack.sh;
  test-aai-layer-profiles.sh
- Live: PR CI select job output.

## Constraints / Risks
- Ceremony L1 (single data file, no protected surface, no script change);
  code review waived with rationale: every new glob names its natural
  owner suite; fail-open + always-on core + post-merge full gate + nightly
  bound the blast radius of a wrong row to over-selection.
- Risk: a doc path mapped to a suite that would NOT catch a real
  regression in it — bounded: the doc-consuming gates (docs-audit strict,
  spec-lint) are core and run always; post-merge full + nightly backstop.

## Notes
- Autopilot intake (blanket run authorization 2026-07-27); follow-up
  observed during CHANGE-0072 ride.
