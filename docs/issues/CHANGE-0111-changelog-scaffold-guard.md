---
id: changelog-scaffold-guard
number: 111
type: change
status: done
user_visible: false
links:
  pr:
    - 215
  commits:
    - b4bb8694159f8dda2d6709b12db08e3c9ec49606
---

# Change — CHANGELOG scaffold invariants get a PR-time guard

## Summary
- Recurring class, 3rd occurrence this week: automated CHANGELOG inserts left
  a SECOND bare `## [unreleased]` scaffold (Copilot caught it on #211; it
  re-appeared and the release cut rolled it INSIDE the v2026.08.02 section,
  cleaned by #214). The contract was enforced only at release-cut time
  (MALFORMED refusal) — between cuts, nothing but author discipline, which
  demonstrably fails.
- Deterministic fix: aai-release suite TEST-022 asserts on the LIVE file at
  PR time: exactly ONE bare scaffold, positioned above every versioned
  heading. The suite is already suite-mapped to CHANGELOG.md, so any PR
  touching the changelog runs it.

## Acceptance Criteria
- AC-001: duplicate bare scaffold -> TEST-022 FAILS naming the line numbers
  (RED-proven with a planted duplicate); clean file -> PASS.
- AC-002: scaffold below the first versioned heading -> FAIL.

## Verification
- RED/GREEN run recorded in the ride log; full aai-release suite green.

## Constraints / Risks
- Ceremony L1, strategy direct (single grep-based test; no scripts touched).
- Guards the LIVE repo file only by design — fixture repos in other tests
  construct their own changelogs and are not affected.
