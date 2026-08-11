---
id: evidence-path-gate
number: 131
type: change
status: done
user_visible: false
ceremony_level: 1
links:
  commits:
    - 2ecb9163779205f5afd5031c1439d73d65ad749a
  pr:
    - 245
---

# Change — Close-time evidence-path gate: cited evidence must resolve from the main tree

## Summary
- Real incident (CHANGE-0127 ride, 2026-08-08): the implementer worked in
  an isolated worktree and stored TDD RED/GREEN evidence there; the spec's
  AC Status table cited docs/ai/tdd/ paths that did NOT resolve from the
  main tree. Only the validator's manual sweep caught it (finding N4) and
  the files were hand-copied minutes before the worktree was deleted —
  otherwise the spec would forever cite evidence that no longer exists.
- This is the one graph-failure mode from the 5-layer audit (2026-08-11)
  the factory does not cover mechanically: "a merge silently drops one
  branch's result". Ledger lines have reconcile-telemetry.mjs; evidence
  FILES have nothing.
- Add a deterministic close-time gate: every file path cited in the
  closing spec's AC Status Evidence column must be resolvable from the
  repo root, else the close refuses (dial-controlled, same pattern as the
  existing close gates).

## Acceptance Criteria
- AC-001: a check (inside close-work-item.mjs or a small lib it calls)
  extracts path-shaped tokens from the closing spec's AC Status Evidence
  cells and verifies each exists from the repo root; non-path evidence
  text (commands, run IDs, prose) is never treated as a path — the
  extraction is conservative (only tokens matching tracked-tree-like or
  docs/ai/ evidence path shapes) so prose can never false-positive the
  gate.
- AC-002: dial `evidence_path_gate` in guard-config (enforce |
  report-only, fail-open default report-only, same grammar and consumer
  pattern as usage_capture_gate); report-only WARNS naming every
  unresolvable path; enforce REFUSES the close before any write. AAI core
  ships the dial report-only; flip is a later KPI decision.
- AC-003: gitignored-but-present evidence (docs/ai/tdd/** exists on disk
  but is untracked by design) counts as RESOLVABLE — the gate checks
  existence, not tracking; an absent file is the only failure.
- AC-004: tests RED-first covering: resolvable tracked path, resolvable
  gitignored path, absent path under report-only (warn, exit 0), absent
  path under enforce (refuse, no write), prose/run-ID cells never parsed
  as paths; suites + registration + spec-lint clean.
