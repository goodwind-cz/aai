# AI Operating Playbook (Canonical)

This repository follows an explicit, agent-compatible operating model.

## Invariants
- Exactly ONE canonical workflow exists: .aai/workflow/WORKFLOW.md
- Requirements, specs, decisions, and knowledge are separated by purpose.
- No acceptance criterion is satisfied without executable evidence.
- PASS without evidence is forbidden.

## Semantic roles
- Planning: scope, mapping, measurability, verification definition
- Implementation: code, tests, scripts (only after spec is frozen)
- Validation: execute verification, collect evidence, issue PASS/FAIL
- Remediation: minimal fixes from FAIL → re-validate

Role names may differ in a project, but semantics must not.

## Lifecycle
1) Bootstrap (one-time or rare): normalize roles/docs/workflow/templates.
2) Technology contract: generate docs/TECHNOLOGY.md from ADR/PRD/config/code.
3) Validation: Requirement → Spec → Implementation → Evidence.
4) Remediation: fix only what the validator proves is missing.
5) Stable: PASS achieved with evidence.

## Knowledge hygiene
- docs/knowledge/FACTS.md is factual memory (no narrative).
- docs/knowledge/UI_MAP.md is UI-to-code trace map.
- docs/archive/analysis/ is immutable history; do not extend archived analyses.
