---
id: scale-adaptive-ceremony
type: rfc
number: null
status: proposed
links:
  research: RES-0001
  spec: null
  pr: []
  commits: []
---

# RFC — Scale-Adaptive Ceremony Levels (right-size the pipeline to the work)

## Context

### Problem or opportunity
AAI runs the same ceremony for a typo-class fix and a subsystem rewrite:
intake doc -> frozen SPEC -> implementation -> independent validation ->
dual-verdict review -> PR. The only relief valve is the hotfix intake. This
session's evidence: ISSUE-0006 (a render-only padding fix) carried the same
artifact weight as SPEC-0019 (a 6-script mechanization). RES-0001 P2 rec 6;
BMAD's scale-adaptive planning (levels 0-4) is the studied prior art.

### Drivers/constraints
- Gates exist because they catch real defects (4 blockers this week) — any
  pruning must be an EXPLICIT, recorded policy, not operator improvisation.
- The mechanized dispatch (orchestration-dispatch.mjs) must stay deterministic
  — levels must be machine-readable from STATE/spec frontmatter.

## Proposal

### Recommended option
Planning declares `ceremony_level: 0..3` in the spec frontmatter, with a
justification line; the gate table prunes BY LEVEL, never silently:
- L0 (typo/docs-only, no behavior change): tech-note in the CHANGE doc
  replaces the SPEC; validation = suite run; review OPTIONAL (operator may
  waive, recorded); same PR ceremony.
- L1 (S fix, single surface): lean SPEC (AC table only); validation =
  independent suite re-run + targeted probe; single dual-verdict review.
- L2 (default today): full current pipeline.
- L3 (protected surfaces: state engine, allocator, guards, workflow canon):
  L2 + mandatory worktree + review on the most capable model + operator
  checkpoint before merge.
Dispatch reads the level from the spec; check-state validates the enum;
docs-audit close gate requires the justification line for L0/L1.

### Rationale
Codifies the exception policy instead of relying on judgment per scope;
levels are auditable (frontmatter + events); the L3 tier ADDS protection
where today's default under-protects (state engine changes ran inline
this week).

## Alternatives Considered
- A: status quo (operator judgment) — rejected: unrecorded, inconsistent.
- B: size heuristics from diff stats — rejected: gameable, post-hoc.
- D: per-type defaults only (hotfix=light) — rejected: type != risk.

## Consequences
- PLANNING + WORKFLOW.md gate table + orchestration-dispatch.mjs (level-aware
  rule table) + check-state enum + docs-audit close gate; M-sized.

## Risks
- Level inflation (everything claims L1). Mitigation: justification line
  required + review may re-classify upward (recorded finding class).

## Open Questions
- Should L3 protected-surface list live in docs-audit.yaml (config) or the
  workflow canon (policy)?

## Approvals
- Required approvers: Project owner (ales@holubec.net).
