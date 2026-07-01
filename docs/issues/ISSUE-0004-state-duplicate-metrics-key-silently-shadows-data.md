---
id: ISSUE-0004
type: issue
status: done
links:
  pr: []
  commits: []
---

# Issue: a duplicate top-level `metrics:` key in STATE.yaml silently shadows metrics data

## Summary
`docs/ai/STATE.yaml` can end up with **two top-level `metrics:` keys** when
different sessions/agents append metrics independently instead of merging into
the existing block. YAML mapping semantics are last-key-wins, so the parser
silently keeps only the second `metrics:` block and **discards the first** — its
`work_items` (and their `agent_runs`) vanish from every `yaml.safe_load`. No
tool caught it; it was found only by hand during a metrics flush.

## Type
- bug

## Impact
- Who/what is affected? Any multi-session / multi-agent run (esp. a different
  model/session driving a scope concurrently) that appends to `metrics.work_items`
  by writing a fresh `metrics:` block. Observed this session: a parallel session
  (model `deepseek-v4-flash`) appended a second `metrics:` block for RFC-0006, so
  the first block's rows (RFC-0005/0004/CHANGE-0004/RFC-0003 and RFC-0006's
  Planning run) were shadowed on parse, and the RFC-0006 agent_runs were split
  across the two blocks (only Planning visible in the first, the rest in the
  second).
- Severity/priority: **Medium** — silent metrics data loss / corruption. STATE is
  per-developer local, so no cross-dev blast radius, but the flush ledger
  (METRICS.jsonl) was nearly written incomplete because the visible agent_runs
  were only a subset. Also any consumer of `metrics` (dashboards, flush, reports)
  reads a partial/wrong view without any error.

## Current Behavior
STATE writers append `metrics:`/`work_items:`/`<ref>:` blocks without checking
whether a top-level `metrics:` key already exists → a second `metrics:` mapping
key is created. `yaml.safe_load` (and the flush) then see only the last one; the
first block's data is silently gone from the parsed structure (though still
present as dead text in the file).

## Expected Behavior
- STATE has exactly one top-level `metrics:` key. Appends merge into the existing
  `metrics.work_items` mapping.
- If a duplicate top-level key is ever present, tooling detects and reports it
  (fails loud) rather than silently shadowing — ideally `aai-check-state`
  flags/repairs it.

## Steps to Reproduce (if applicable)
1) In `docs/ai/STATE.yaml`, add a second `metrics:` block at the end (as a
   concurrent session would).
2) `python3 -c "import yaml,collections; ..."` — a strict duplicate-key check
   raises; a lenient `yaml.safe_load` silently keeps only the last `metrics:`
   block, dropping the first block's `work_items`.

## Verification
- `aai-check-state` (or a STATE schema validator) detects a duplicate top-level
  key and reports it (add a REPAIR path that merges the blocks).
- STATE-write helpers append into the existing `metrics.work_items` instead of
  emitting a new `metrics:` key (a fixture with an existing metrics block gets one
  merged mapping, never two).
- A regression test: feed a STATE with a duplicate `metrics:` key to the
  validator → non-zero / flagged; after repair → single key, union of both
  blocks' work_items, no data lost.

## Constraints / Risks
- STATE is YAML edited by multiple agents/sessions and by hand; the guard must be
  robust to formatting variation and must not lose data during a merge/repair
  (union the work_items, don't overwrite).
- Fixing the writers (append-into-existing) is the durable fix; the check-state
  guard is the safety net (mirrors the docs-audit "fail loud" philosophy).

## Notes
Found during the ISSUE-0002 closeout flush (this session): the duplicate
`metrics:` key was hand-repaired (blocks merged, both sets of RFC-0006 agent_runs
recovered before flushing to METRICS.jsonl). This issue tracks preventing it.
Component: STATE-write paths (orchestration / role prompts that append
`metrics.work_items.*.agent_runs`) + `.aai/SKILL_CHECK_STATE.prompt.md` /
`aai-check-state`. Related: RFC-0001 (per-dev STATE, EVENTS as shared log),
DEBT-0001 (fail-loud philosophy).
