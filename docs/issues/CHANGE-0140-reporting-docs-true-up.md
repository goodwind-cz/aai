---
id: reporting-docs-true-up
number: 140
type: change
status: done
user_visible: true
ceremony_level: 1
capability: aai-dashboard
links:
  commits:
    - c54568a
  pr:
    - 255
---

# Change — reporting/docs true-up: USER_GUIDE matches the real skill set, dashboard reads real usage, no empty charts

## Summary
- Owner audit 2026-08-13 ("user docs nesedi uplne s tim jake mame skily ...
  a dashboard taky neukazuje vse, ma prazdne grafy"): three confirmed
  defects. (1) docs/USER_GUIDE.md documents skills/scripts that do not
  exist (the /aai-feedback-triage and /aai-feedback-upsert SKILL aliases —
  the three .mjs engines all exist; Planning corrected this intake claim,
  only the alias mentions were dead) and omits /aai-factory-report entirely
  (shipped in CHANGE-0130). (2) generate-dashboard.mjs reads tokens only
  from tokens_in/tokens_out, which the real ledger never fills — usage
  lives in the run note as `usage_total_tokens=N` (SUBAGENT_PROTOCOL
  capture convention), so token totals and charts render 0. (3) charts
  whose data the ledger cannot feed at all (worktree, publish) render as
  EMPTY panels instead of being hidden or named N/A.

## Acceptance Criteria
- AC-001 (USER_GUIDE truth): every /aai-* skill mention in USER_GUIDE
  refers to a skill that exists in .claude/skills/ (generated-downstream
  examples like /aai-test-unit and illustrative URLs excepted by an
  explicit allowlist); every vendored skill with user-facing value is at
  least listed; the dead feedback-triage/upsert section is removed or
  rewritten to the surviving aai-feedback-status.mjs reality;
  /aai-factory-report gains its section (what it shows, when to use it vs
  /aai-dashboard).
- AC-002 (anti-drift pin): a bash test reconciles USER_GUIDE skill
  mentions against .claude/skills/ in BOTH directions (unknown mention =
  FAIL naming it; undocumented vendored skill = FAIL naming it, with the
  explicit exception list in the test, not in prose) — RED-first against
  the current drift.
- AC-003 (dashboard reads real usage): generate-dashboard.mjs's ledger
  normalizer parses `usage_total_tokens=<N>` from agent_runs[].note into
  the operation's token total (undecomposed — reported as total, never
  fabricated into an in/out split); summary totals, per-skill and
  time-series charts show the real numbers; the factory-report parser is
  the reference for the note grammar (bracketed suffix tolerant).
- AC-004 (no empty panels): chart sections whose source data is absent
  for the whole dataset (worktree, publish today) render a named
  "no data recorded" state or are omitted — never an empty axis; a
  dataset that HAS the data still renders the chart (fixture-proven both
  ways).
- AC-005: tests per conventions RED-first (dashboard data assertions on a
  fixture METRICS.jsonl with note-carried usage; both-ways empty-panel
  fixtures); SKILL_DASHBOARD.prompt.md "Tokens are mostly null" caveat
  updated truthfully (diet ledger + TEST-012 if prompt bytes move);
  product docs truthful.
