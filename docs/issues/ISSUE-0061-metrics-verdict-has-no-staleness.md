---
id: metrics-verdict-has-no-staleness
type: issue
number: 61
status: draft
---

# P2 backlog cluster: agent-shell-can-write-the-shipping-repo (2 items)

## Summary
- Consolidated registry intake for 2 open P2 follow-up(s) filed against `agent-shell-can-write-the-shipping-repo`: `fu-metrics-verdict-has-no-staleness`, `fu-overview-bakes-untracked-state`. Filed via batch intake (owner directive: intake all P2 clusters first, ship the highest-value ones next).

## Type
- bug

## Current Behavior
- **`fu-metrics-verdict-has-no-staleness`**: the metrics ledger records verdict PASS with no notion of whether the verdict covers the final bytes, so a ride whose last work lands after its last review is counted as reviewed-and-passed
  - Measured: measured on the ISSUE-0045 flush: the record says verdict PASS while two Remediation runs (08:58 and 10:27) landed after the final Code Review ended at 08:46. The orchestrator disclosed that in the PR body and in the AC evidence, but the factory-quality report reads the ledger, not the prose, so its quality figures count post-review code as reviewed. Every ride that remediates after its last review has this shape
  - Source: bot review on PR 300 (Codex on METRICS.jsonl); docs/ai/METRICS.jsonl last record for isolation-shares-the-shipping-git

- **`fu-overview-bakes-untracked-state`**: docs/ai/overview.html and overview-data.json are tracked artefacts generated from docs/ai/STATE.yaml, which is untracked by design, so every commit of them bakes one machine's local state into the repository
  - Measured: measured 2026-08-28 on PR 300: git ls-files docs/ai/STATE.yaml returns nothing and generate-overview.mjs reads it as an optional local file, so another clone or CI regenerating the overview produces different content and the committed version is not reproducible. It also published a contradiction - the same ride appeared under In flight now with both verdicts not_run AND in Delivered with status done. Not new to that PR: close-work-item and the allocator regenerate these files and SKILL_PR step 3 treats them as expected companions, so the pattern is systemic
  - Source: bot review on PR 300 (Copilot on overview-data.json and overview.html, Codex on the in-flight contradiction); .aai/scripts/generate-overview.mjs:90; .gitignore:63

## Expected Behavior
- Each item's own Expected Behavior is scoped at Planning/implementation time from the measured decision text above — this intake's job is to make the cluster a numbered, trackable work item, not to pre-design the fix.

## Notes
- Registry ref: `agent-shell-can-write-the-shipping-repo`. This intake may close some, all, or none of the member `fu-*` ids depending on what Planning finds still applies when work starts — do not assume every listed item survives triage unchanged (two sibling items in this same backlog were found already-fixed-but-not-closed today; check before implementing).
