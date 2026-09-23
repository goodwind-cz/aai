---
id: original-request-outcome-backcheck
type: product
capability: original-request-outcome-backcheck
status: current
delivered_by:
  - original-request-outcome-backcheck
spec: docs/specs/SPEC-0183-spec-original-request-outcome-backcheck.md
updated: 2026-09-23
---

# Validation of original requirements and saved results

## What it does

AAI validation compares the original request with the implementation specification and checks evidence for the exact delivered result. Required gaps, unknown results, changed saved files and stale dynamic observations prevent an accepted completion report. Repository changes use a concise evidence record; external-save requirements apply only when the requested outcome needs them.

## How to use it

Run the normal AAI validation workflow. The independent validator writes a validation report containing one `aai-outcome-v1` JSON block. To inspect a report directly, supply its scope and the start time of the verification attempt:

```sh
node .aai/scripts/validation-outcome-check.mjs --report docs/ai/reports/VALIDATION-example.md --ref example --since 2026-09-23T09:00:00Z
```

Paths in the report are relative to the repository root; use `--root` when checking another directory. A resumed loop requires a current observation for dynamic external targets. Unchanged immutable files can reuse their evidence.

## Data model

The existing validation Markdown report gains a versioned JSON block. It records original sources, material requirements, their specification mappings, target identities, verification operations, evidence hashes and observation times. Saved-file outcomes also identify the consumed file and bytes. Reports remain ordinary local runtime evidence; this change adds no database or automatic retention service.

## Interfaces and contracts

- `validation-outcome-check.mjs`: exit 0 means the report is mechanically admissible; exit 1 refuses evidence with an `OUTCOME-CHECK` reason; exit 2 reports invalid command usage.
- Dispatched Validation PASS results include `outcome_report`; the handoff checker reads that report before accepting the result. Legacy PASS results need regenerated evidence. Other roles and non-PASS results retain their existing result contract.
- The routine validator and session loop invoke the same checker. Optional presentation reports preserve the outcome block.

## Limits and non-goals

The independent validator still judges whether the requirement inventory is complete and whether an external observation is truthful. A parser cannot prove those semantic claims. Standalone validation and loop entry follow prompt instructions; direct state-CLI callers can bypass those instructions. Existing repository-tree freshness checks remain responsible for repository changes. This feature does not roll back environments or execute commands and URLs contained in reports.

## Links

- Request: ../issues/CHANGE-0189-original-request-outcome-backcheck.md
- Spec: ../specs/SPEC-0183-spec-original-request-outcome-backcheck.md
- Validation evidence: ../ai/reports/VALIDATION-20260923T084417Z-original-request-outcome-backcheck-pr388-remediation.md
