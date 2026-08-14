---
id: close-regenerate-order
number: 143
type: change
status: draft
user_visible: false
ceremony_level: 1
capability: aai-pr
---

# Change — generated pages are regenerated AFTER the spec number is allocated, by machine not by discipline

## Summary
- Owner ask 2026-08-14 via /aai-ship: "chci to zapojené do close-work-item
  nebo pinované testem, ne jako lidskou disciplínu".
- Field evidence, twice in one day: the ride's generated pages (USER_GUIDE
  rollup, overview, factory report, dashboard) were produced BEFORE
  allocate-doc-number.mjs renamed `SPEC-DRAFT-<slug>.md` to
  `SPEC-<NNNN>-<slug>.md`, so they shipped links to a path that no longer
  existed. Caught by review bots on PR #255 and again on PR #256 — the
  second time after the lesson had already been written down. A recorded
  lesson that nothing enforces is not a control.
- The ordering is not documented anywhere as a contract either: the close
  ceremony does not own it, and no test fails when it is violated.

## Acceptance Criteria
- AC-001 (machine-enforced ordering): the close path makes the correct
  order structural rather than remembered — either close-work-item.mjs
  regenerates the affected pages itself after allocation, or it refuses/
  warns loudly when a generated page still references a SPEC-DRAFT path
  for the ref being closed. Planning picks one and records why, including
  what it costs when the generators are absent or slow.
- AC-002 (detection, not just prevention): a test FAILS when any tracked
  generated page (docs/USER_GUIDE.md, docs/ai/overview.{html,json},
  docs/ai/factory-report.{html,json}, docs/ai/dashboard.{html,json})
  contains a `SPEC-DRAFT-` reference whose numbered counterpart exists —
  RED-proven by replaying the exact PR #255 shape.
- AC-003 (honest degradation): when a generator is unavailable or fails,
  the close still completes and says so in one named line; the ordering
  guard never becomes a new hard gate that can block a close on a machine
  without the generators.
- AC-004: no change to the close ceremony's existing exit contract or to
  its EVENTS/STATE transaction semantics; the snapshot/rollback arm stays
  byte-identical in behavior.
- AC-005: tests per conventions RED-first with RED_CLASS stamped at
  capture; docs updated truthfully (the close-ceremony product doc and any
  guidance that currently implies the human does this by hand).
