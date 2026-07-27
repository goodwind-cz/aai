---
id: doctor-determinize
number: 79
type: change
status: draft
user_visible: false
links:
  pr: []
  commits: []
---

# Change — aai-doctor: replace prose-computed categories with one deterministic script

## Summary
- Skill-sweep finding (group B): SKILL_DOCTOR is 10.7 KB and only 2 of 13
  categories call real scripts (docs-audit --quick, layer-drift); the other
  11 (~20 file-existence/line-count checks + git status parsing) are prose
  instructing the LLM to compute what a script computes cheaper and without
  variance. Build .aai/scripts/aai-doctor.mjs covering the mechanical 11,
  slim the prompt to a thin wrapper (mirrors the proven CAT-11/13 pattern).

## Acceptance Criteria
- AC-001: aai-doctor.mjs reproduces all mechanical category verdicts on
  this repo byte-stably (suite-verified fixtures).
- AC-002: SKILL_DOCTOR.prompt.md shrinks to a thin wrapper; prompt-diet
  ledger reflects the REDUCTION; TEST-012 pin updated RED-first.
- AC-003: no regression — doctor smoke on a fixture target project.

## Constraints / Risks
- Ceremony L2; prompt-corpus governance triggered (reduction).
