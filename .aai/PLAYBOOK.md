# AI Operating Playbook (Canonical)

This repository follows an explicit, agent-compatible operating model.

## Invariants
- Exactly ONE canonical workflow exists: .aai/workflow/WORKFLOW.md
- Requirements, specs, decisions, and knowledge are separated by purpose.
- No acceptance criterion is satisfied without executable evidence.
- PASS without evidence is forbidden.

## Semantic roles (six phases — canon: .aai/roles/ROLES.md)
- Planning: scope, mapping, measurability, verification definition, strategy + worktree recommendation
- Implementation Preparation: the worktree gate — human decides worktree vs inline when isolation is recommended or required
- Implementation: code, tests, scripts (only after spec is frozen)
- Validation: execute verification, collect evidence, issue PASS/FAIL
- Code Review: spec compliance first, then code quality; gates merge/PR readiness
- Remediation: minimal fixes from a Validation or Code Review FAIL → re-validate

Role names may differ in a project, but semantics must not.

## Lifecycle
0) Bootstrap (one-time or rare): normalize roles/docs/workflow/templates; generate docs/TECHNOLOGY.md.
1) Intake: route new work via /aai-intake (or an INTAKE_*.prompt.md).
2) Loop: the six phases above, with gates (see .aai/workflow/WORKFLOW.md), until Validation PASS and Code Review PASS with evidence.
3) PR: /aai-pr stages only in-scope paths, commits, pushes, and opens the PR. The agent never merges.
4) Merge: the operator reviews and merges.
5) Closeout: docs-audit close gate before any done-flip, then telemetry flush to METRICS.jsonl.

docs/ai/STATE.yaml is written only through .aai/scripts/state.mjs (the transactional CLI). Never hand-edit it.

## Knowledge hygiene
- docs/knowledge/FACTS.md is factual memory (no narrative).
- docs/knowledge/UI_MAP.md is UI-to-code trace map.
- docs/project-sessions/ is narrative project memory for human-readable session continuity.
- docs/project-sessions/ does not replace specs, decisions, or evidence.
- docs/archive/analysis/ is immutable history; do not extend archived analyses.
