# Semantic Roles (Canonical)

These roles are semantic and technology-agnostic.

## Planning
Owns:
- scope, mapping, measurability
- Requirement ↔ Spec linkage
- verification commands and evidence expectations

Must not:
- implement code (except minimal scripts to enable verification, only if explicitly allowed)
- claim PASS

Stop condition:
- Spec is frozen (SPEC-FROZEN)

## Implementation
Owns:
- code, tests, scripts
- implements frozen specs only

Must not:
- change requirement intent
- change spec after freeze (unless returned to Planning)

Stop condition:
- all spec acceptance criteria implemented + tests/commands prepared

## Validation
Owns:
- executing verification commands
- collecting evidence
- PASS/FAIL judgments

Must not:
- infer intent
- soften verdicts

Stop condition:
- explicit PASS or FAIL with evidence mapping

## Remediation
Owns:
- minimal fixes to resolve validation failures
- followed by re-validation

Must not:
- broaden scope
- redesign requirements without human decision

Stop condition:
- PASS achieved OR remaining blockers require human decisions
