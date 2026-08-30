---
id: typemap-missing-research-hotfix
type: issue
number: 72
status: draft
---

# P2 backlog cluster: spec-intake-numbers-some-doc-types-immediately (2 items)

## Summary
- Consolidated registry intake for 2 open P2 follow-up(s) filed against `spec-intake-numbers-some-doc-types-immediately`: `fu-typemap-missing-research-hotfix`, `fu-ceremony-test016-blanket-byte-pin`. Filed via batch intake (owner directive: intake all P2 clusters first, ship the highest-value ones next).

## Type
- bug

## Current Behavior
- **`fu-typemap-missing-research-hotfix`**: allocate-doc-number.mjs TYPE_MAP has no research and no hotfix row, so --type research and --type hotfix exit 2 as unknown types
  - Measured: the intake type table in .aai/INTAKE_COMMON.md now covers all eight types, but the allocator can only build a DRAFT path for six of them; the gap is invisible until someone passes --type research
  - Source: measured 2026-08-21: TYPE_MAP keys are rfc,spec,issue,change,techdebt,debt,prd,requirement,release; resolveType throws on anything else. Not fixed in this ride because .aai/scripts/allocate-doc-number.mjs is protected_paths_l3 and editing it forces ceremony 3 (spec-intake-numbers-some-doc-types-immediately D4)

- **`fu-ceremony-test016-blanket-byte-pin`**: test-aai-ceremony-levels.sh TEST-016 pins .aai/scripts/lib/docs-audit-core.mjs with a bare git diff --exit-code, so ANY later scope that touches that shared library fails a test written for SPEC-0041
  - Measured: the pin says byte-untouched by this scope but has no scope qualifier, and the same file comment already concedes the guardrail is verified functionally by cases (a)/(b)/(c) beside it; it is a standing false positive for every future scope, the same class as fu-test011-branch-diff-allowlist-tax
  - Source: measured 2026-08-21: full run [ 4/81] aai-ceremony-levels FAIL — docs-audit-core.mjs must be byte-untouched by this scope. spec-intake-numbers-some-doc-types-immediately worked around it by moving its three functions into .aai/scripts/docs-audit.mjs (D7) rather than editing a pin owned by another spec

## Expected Behavior
- Each item's own Expected Behavior is scoped at Planning/implementation time from the measured decision text above — this intake's job is to make the cluster a numbered, trackable work item, not to pre-design the fix.

## Notes
- Registry ref: `spec-intake-numbers-some-doc-types-immediately`. This intake may close some, all, or none of the member `fu-*` ids depending on what Planning finds still applies when work starts — do not assume every listed item survives triage unchanged (two sibling items in this same backlog were found already-fixed-but-not-closed today; check before implementing).
