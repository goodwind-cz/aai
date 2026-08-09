---
id: scryer-mcp-and-shallow
number: 129
type: change
status: draft
user_visible: true
ceremony_level: 2
---

# Change — Scryer template v2: MCP-aware merge sweep + shallow-clone-honest health

## Summary
- First production runs of the morning scryer (2026-08-08/09, cloud cron
  trig_01XpMxioptoJ7j32YKzzaKnR) exposed two environment realities the
  SCRYER.routine.md contract does not handle:
  1. The cloud container has NO gh CLI. The 2026-08-09 run improvised the
     merge sweep via GitHub MCP tools (list_pull_requests worked, 0 open
     PRs) — read path proven, merge path untested and completely
     unspecified by the contract. The E2E probe #234 failed to merge only
     because the then-prompt knew gh alone.
  2. The disposable cloud checkout is a SHALLOW clone: docs-audit reported
     24 probable-false-done items (old doc IDs) that are CLEAN locally —
     the history-based heuristics see no commits. The digest presented an
     environment artifact as findings.
- Fix at the template level (single source of truth since CHANGE-0128),
  then re-arm the live routine FROM the template — its first
  template-rendered deployment.

## Acceptance Criteria
- AC-001: .aai/routines/SCRYER.routine.md merge-sweep step declares the
  tool ladder explicitly: gh when available, else GitHub MCP tools
  (list/get PR, checks, comments, merge); the digest MUST name which path
  ran; merge remains the ONLY write action on either path; all other
  contract elements (gates, [L3], UNTRUSTED DATA) unchanged.
- AC-002: HEALTH step becomes shallow-honest: before docs-audit it ensures
  full history (git fetch --unshallow best-effort); when full history is
  NOT available the digest names the shallow-clone artifact and SKIPs the
  false-done classes instead of reporting them as findings; never crashes
  (resilience contract).
- AC-003: routine-emit.mjs render, golden fixture, and affected TEST rows
  updated so the template change stays byte-for-byte pinned; suites green;
  no governance drift (PROFILES/diet untouched unless prompt bytes move —
  SCRYER.routine.md is not a .prompt.md).
- AC-004 (orchestrator-owned, post-merge): live routine updated via
  RemoteTrigger with the template-rendered merge-enabled prompt
  (routine_authorization record exists), immediate test run fired
  (test-at-creation rule), and a disposable probe PR verifies the MCP
  merge path end-to-end; result recorded in decisions.jsonl.
