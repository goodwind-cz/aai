# Agent Guide (Canonical)

This repository uses a reusable AI Operating System.

## Canonical sources
- Workflow (single source): docs/workflow/WORKFLOW.md
- Semantic roles: docs/roles/ROLES.md
- Technology contract: docs/TECHNOLOGY.md (created by ai/TECH_EXTRACT.prompt.md)
- Fact memory: docs/knowledge/FACTS.md
- UI map: docs/knowledge/UI_MAP.md
- Prompts: ai/*.prompt.md
- Human playbook: PLAYBOOK.md
- Coordination locks (optional): docs/ai/LOCKS.md

## How to run (recommended)
1) Decide next action:
   - Run ai/ORCHESTRATION.prompt.md (single)
   - Or ai/ORCHESTRATION_PARALLEL.prompt.md (parallel, resource-sensitive)
   - Or ai/ORCHESTRATION_HITL.prompt.md (human decision gating)

2) Execute the dispatched role:
   - Planning / Implementation / Validation / Remediation
   - Follow the referenced prompt file exactly.

## Rules
- Do not claim PASS without executable evidence.
- Do not invent technologies: read docs/TECHNOLOGY.md first.
- Archived analyses are read-only; new knowledge goes into FACTS.md and UI_MAP.md.
- If CLAUDE.md or Copilot instructions conflict with this file, follow this file.
