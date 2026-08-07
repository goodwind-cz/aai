# AAI-TEMPLATE
# Universal Pattern Library (AAI managed)
#
# THIS FILE IS MANAGED BY aai-sync — do not add project-specific patterns here.
# Project-specific patterns belong in docs/knowledge/PATTERNS.md.
#
# HOW TO USE (for agents):
#   1. Read the INDEX table below (cheap — ~1 line per pattern).
#   2. Identify patterns whose Tags overlap with the current task.
#   3. Load full text of matching patterns only. Skip the rest.
#
# HOW TO ADD A PATTERN:
#   - Add a row to INDEX with name, tags, anchor.
#   - Add the pattern entry below with the matching anchor.
#   - Keep each entry under 10 lines. Split large patterns instead.
#   - To promote a project pattern here: copy it, add evidence, open PR to template repo.

## INDEX

| Pattern | Tags | Anchor |
|---------|------|--------|
| _(no universal patterns yet — add via template repo PR)_ | — | — |
| win-escalation-hygiene | windows, permissions, escalation, sandbox, codex | #win-escalation-hygiene |

---

## Patterns

<!-- Pattern entry format:
### <Name> {#anchor}
Tags: tag1, tag2, tag3
Context: <when to use — one line>
Pattern: <what to do — max 5 lines>
Rationale: <why it works — one line>
Evidence: <file path or commit where first confirmed>
-->

## Anti-patterns

<!-- Anti-pattern entry format:
### <Name> {#anchor}
Tags: tag1, tag2
Problem: <what goes wrong>
Instead: <what to do instead>
Evidence: <where this was learned>
-->

## win-escalation-hygiene
Tags: windows, permissions, escalation, sandbox, codex
- Escalation is a PER-COMMAND necessity decided fresh each time — never a
  sticky mode. After a `CreateProcessAsUserW` 1920-class sandbox failure,
  retry the NEXT command non-escalated first.
- NEVER re-request approval for a command the operator explicitly allowed —
  repeated prompts for pre-approved commands are operator-hostile friction.
- When escalation is genuinely needed, state WHY in one line when asking.
- Evidence: owner-reported Codex/Windows session 2026-08-07 — one 1920 error
  sticky-escalated everything incl. an allowed Get-Content.
