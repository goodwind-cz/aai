---
id: win-escalation-hygiene
number: 126
type: change
status: done
user_visible: true
ceremony_level: 1
links:
  pr:
    - 233
  commits:
    - fa14a36737eb673f1b0b967d06b3061d23f4250e
---

# Change — Windows escalation hygiene joins the vendored knowledge

## Summary
- Owner-reported downstream friction (Codex/Windows): after one
  `CreateProcessAsUserW` 1920 sandbox error the agent sticky-escalated and
  re-prompted for every command, including an explicitly allowed
  `Get-Content`. The agent itself admitted the permissions mishandling.
- Fix at AAI's honest leverage point — CORRECTED by the owner mid-ride:
  docs/knowledge/LEARNED.md is PROJECT-OWNED and never syncs downstream, so
  the rule's vendored carrier is .aai/knowledge/PATTERNS_UNIVERSAL.md (the
  aai-sync-managed pattern library agents load by tag). The LEARNED entry
  stays for THIS repo's replay; the pattern entry is what reaches Codex on
  other projects — escalation is per-command and never
  sticky; a 1920-class failure means retry the next command non-escalated;
  never re-ask for explicitly allowed commands. Harness-side behavior
  cannot be gated deterministically from the vendored layer — knowledge
  steering is the available lever, stated as such.

## Acceptance Criteria
- AC-001: PATTERNS_UNIVERSAL.md carries the pattern (INDEX row + entry,
  tags windows/permissions/escalation) AND LEARNED.md carries the local
  entry with the incident citation.

## Constraints / Risks
- Ceremony L1, strategy direct, docs-only. Prose steering — effectiveness
  depends on downstream replay/priming; if the friction recurs, escalate to
  a Codex-side config/wrapper intake.
