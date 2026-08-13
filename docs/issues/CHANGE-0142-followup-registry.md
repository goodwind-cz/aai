---
id: followup-registry
number: 142
type: change
status: draft
user_visible: false
ceremony_level: 1
capability: aai-decisions
---

# Change — typed, queryable follow-up registry (deferred work stops rotting in prose)

## Summary
- Owner ask 2026-08-13 after the spec-kit analysis ("začni s tím co má pro
  nás přínos a nenavýší ale o moc spotřebu"): adopt the one mechanism their
  field issues surfaced that we genuinely lack — github/spec-kit#641
  ("defer a suggestion during implementation for later review").
- Measured gap in THIS repo: docs/ai/decisions.jsonl carries exactly ONE
  typed `follow_up` entry against 8+ follow-ups buried as prose inside
  `review_nb_disposition` decision fields, and `.aai/scripts` has no tool
  that can list them. Six of those were created on 2026-08-13 alone.
- Cost of the gap, evidenced same-day: the "regenerate generated pages
  AFTER the allocator renames the spec" lesson was recorded as prose in the
  CHANGE-0140 disposition and then repeated verbatim as a defect in
  CHANGE-0141 — a recorded lesson that nothing could surface.
- Deliberate non-goal: no new agent, no new per-ride LLM step. This scope is
  a deterministic script plus report-only surfacing; ride token cost must
  not rise.

## Acceptance Criteria
- AC-001 (typed emission): a documented `follow_up` entry shape is the
  canonical way to defer work — stable id/slug, source ref (the scope that
  raised it), what and why in one line each, severity, created timestamp,
  status open/done/dropped, and the resolving ref when closed. Appended to
  the existing docs/ai/decisions.jsonl (append-only, no new store, no
  history rewrite); the disposition entry keeps its prose and simply cites
  the follow-up ids.
- AC-002 (query tool): `.aai/scripts/follow-ups.mjs` lists open follow-ups
  deterministically — filters by ref, status and age, `--json` for
  machines, stable exit codes (0 clean, non-zero reserved for usage errors
  only; a non-empty backlog is NEVER an error), zero network, zero LLM.
- AC-003 (backfill without rewriting): the follow-ups already recorded as
  prose (grep FOLLOW-UP in decisions.jsonl) are materialized as typed
  entries that cite their source entry's timestamp; the original lines stay
  byte-identical — evidence is never retro-edited.
- AC-004 (rot surfacing, report-only): open follow-ups and their age appear
  in an existing report surface (factory report or overview — Planning
  picks one and states why); nothing new BLOCKS a ride or a release, and no
  existing exit contract changes.
- AC-005 (closing loop): when a scope ships that resolves a follow-up, its
  status flips through the same append-only mechanism, and the tool proves
  the flip by re-reading the ledger; the close ceremony is the natural
  place, so state whether it is wired there or left manual, honestly.
- AC-006: tests per conventions RED-first; product doc updated truthfully;
  any .aai prompt byte spent on the emission rule is measured and ledgered
  (TEST-012 checkpoint currently -6044) and kept minimal.
