---
id: docsaudit-idmention-probe-per-doc
type: issue
number: 52
status: draft
---

# P2 backlog cluster: spec-docs-history-is-one-git-call-per-doc (1 item)

## Summary
- Consolidated registry intake for 1 open P2 follow-up(s) filed against `spec-docs-history-is-one-git-call-per-doc`: `fu-docsaudit-idmention-probe-per-doc`. Filed via batch intake (owner directive: intake all P2 clusters first, ship the highest-value ones next).

## Type
- bug

## Current Behavior
- **`fu-docsaudit-idmention-probe-per-doc`**: docs-audit still spends one git log -1 --grep per document for the id-mention probe
  - Measured: after the add-history walk landed, --check --strict is 3875 ms of which 203 --grep probes at ~19 ms each are ~3.8 s; the intake's 2000 ms target is unreachable without batching them too
  - Source: measured 2026-08-21 on perf/docs-history-single-pass: 211 git calls total, 203 carrying --grep, 1 bulk walk, 2 per-file fallbacks for untracked docs

## Expected Behavior
- Each item's own Expected Behavior is scoped at Planning/implementation time from the measured decision text above — this intake's job is to make the cluster a numbered, trackable work item, not to pre-design the fix.

## Notes
- Registry ref: `spec-docs-history-is-one-git-call-per-doc`. This intake may close some, all, or none of the member `fu-*` ids depending on what Planning finds still applies when work starts — do not assume every listed item survives triage unchanged (two sibling items in this same backlog were found already-fixed-but-not-closed today; check before implementing).
