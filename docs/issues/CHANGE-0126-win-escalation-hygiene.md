---
id: win-escalation-hygiene
number: 126
type: change
status: draft
user_visible: true
ceremony_level: 1
links:
  pr: []
  commits: []
---

# Change — Windows escalation hygiene joins the vendored knowledge

## Summary
- Owner-reported downstream friction (Codex/Windows): after one
  CreateProcessAsUserW 1920 sandbox error the agent sticky-escalated and
  re-prompted for every command, including an explicitly allowed
  Get-Content. The agent itself admitted the permissions mishandling.
- Fix at AAI's honest leverage point: a LEARNED.md rule (vendored
  downstream, replayed at task start) — escalation is per-command and never
  sticky; a 1920-class failure means retry the next command non-escalated;
  never re-ask for explicitly allowed commands. Harness-side behavior
  cannot be gated deterministically from the vendored layer — knowledge
  steering is the available lever, stated as such.

## Acceptance Criteria
- AC-001: LEARNED.md carries the rule with the incident citation.

## Constraints / Risks
- Ceremony L1, strategy direct, docs-only. Prose steering — effectiveness
  depends on downstream replay/priming; if the friction recurs, escalate to
  a Codex-side config/wrapper intake.
