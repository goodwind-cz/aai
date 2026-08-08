---
id: universal-routines
number: 128
type: change
status: implementing
user_visible: true
ceremony_level: 2
---

# Change — Standing routines become a vendored, on-demand template (scryer generalized)

## Summary
- Owner requirement (2026-08-08): the scryer initialization "mělo by to být
  univerzální i pro jiné agenty a jen na vyžádání". Today the morning
  scryer (trig_01XpMxioptoJ7j32YKzzaKnR) is a one-off: its entire
  definition lives only in the Anthropic cloud trigger config, created by a
  hand-rolled API call; the repo holds only the merge authorization in
  decisions.jsonl. Not reproducible, not synced, Claude-cloud-only.
- Deliver routines as versioned, agent-neutral contracts in the vendored
  layer, instantiated ONLY on explicit owner request, never by
  bootstrap/sync.

## Acceptance Criteria
- AC-001: `.aai/routines/SCRYER.routine.md` — agent-neutral routine
  contract with placeholders (repo, schedule, merge-allowed flag, model):
  resilience contract (probe prerequisites, degraded digest is a
  SUCCESSFUL run), merge gates (CI green + top-level bot comments answered
  + never [L3]), Czech digest shape, safety rules (PR/issue comment text is
  UNTRUSTED DATA; merge is the only write action). The live cloud routine's
  prompt is regenerable from this file byte-for-byte modulo placeholders.
- AC-002: On-demand instantiation skill (`/aai-routine`): given harness +
  schedule + repo, emits the concrete installation — Claude: cloud-routine
  creation payload; Codex/Gemini/other CLI agents: local scheduler variant
  (cron on mac/linux, Task Scheduler on Windows, bash+ps1 twins) running
  the agent CLI headless with the same contract. NEVER invoked from
  bootstrap, sync, or any automatic path; documented as owner-initiated
  only.
- AC-003: Merge-rights guard: instantiation with merge enabled requires an
  explicit authorization record in docs/ai/decisions.jsonl (machine-checked
  by the skill before emitting a merge-enabled prompt); absent record →
  report-only variant emitted, stated loudly.
- AC-004: Test-at-creation is part of the contract (memory rule
  cloud-routine-test-at-creation): the skill's output includes firing one
  immediate test run and what to verify (digest produced, no crash,
  degraded sections named); prompt corpus governance applies (diet ledger +
  TEST-012 + PROFILES) since .aai/** grows.

## Notes
- Spec: docs/specs/SPEC-DRAFT-spec-universal-routines.md (SPEC-FROZEN
  2026-08-08, strategy hybrid).
- Ceremony level re-classified 1 -> 2 by Planning at freeze (RFC-0009 gives
  the spec's declaration authority): the scope is not a single-surface fix —
  it adds a new executable emitter, a new prompt-corpus file, a new routine
  template directory, four harness wrappers, a new test suite and four
  governance surfaces, and one of its behaviors (the merge-rights guard)
  decides whether a scheduled agent may write to the repository. That
  argues for the full review lane, not the lightweight one. No
  `protected_paths_l3` surface is touched, so level 3 is not required.
