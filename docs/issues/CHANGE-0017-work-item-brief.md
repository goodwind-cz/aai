---
id: work-item-brief
type: change
number: 17
status: done
links:
  research: RES-0001
  pr:
    - 72
  commits:
    - 715bc81
---

# Change — Self-Contained Work-Item Brief as Subagent Handoff

## Summary
- Planning emits a compact self-contained brief per work item (BMAD story
  pattern, RES-0001 P2 rec 9): AC-to-task links, relevant canon excerpts, and
  a Return Record section the subagent fills — instead of "go read the spec".

## Motivation / Business Value
- Dispatched subagents each re-read the spec + canon from scratch (RES-0001
  F3: repeated cold reads); dispatch prompts are hand-written per dispatch
  (orchestrator improvisation). A generated brief makes handoffs cheaper and
  deterministic, and the Return Record structures result reporting for the
  orchestrator (SUBAGENT_PROTOCOL result block made concrete).

## Scope
- In scope: brief TEMPLATE (.aai/templates/BRIEF_TEMPLATE.md: Scope & why /
  AC-task map / Constraints & canon pointers (paths, never full copies) /
  Evidence contract / Return Record skeleton); PLANNING step emitting
  docs/ai/briefs/<ref>.md (gitignored runtime artifact, like reports);
  SUBAGENT_PROTOCOL: dispatch context = the brief path + diff scope (briefs
  are the default handoff when present, degrade to spec-path when absent);
  ORCHESTRATION dispatch inputs mention the brief when it exists; grep test
  stanza; .gitignore entry.
- Out of scope: retrofitting old scopes; orchestration-dispatch.mjs logic
  (inputs list is display text).

## Acceptance Criteria
- AC-001: BRIEF_TEMPLATE.md exists (<=60 lines) with the 5 sections; PLANNING
  emits the brief as a numbered step; gitignore covers docs/ai/briefs/.
- AC-002: SUBAGENT_PROTOCOL names the brief as default handoff with the
  degrade clause; ORCHESTRATION wrapper unchanged in behavior (<=40 lines
  cap preserved).
- AC-003: grep test stanza wired; suites green; prompt-diet floor holds;
  repo audit strict CLEAN.
