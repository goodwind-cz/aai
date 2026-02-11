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

To update the AI-OS layer from a template worktree, see scripts/ai-os-sync.(sh|ps1) and docs/ai/AI_OS_PIN.md.

## How to run (recommended)
1) Decide next action:
   - Run ai/ORCHESTRATION.prompt.md (single)
   - Or ai/ORCHESTRATION_PARALLEL.prompt.md (parallel, resource-sensitive)
   - Or ai/ORCHESTRATION_HITL.prompt.md (human decision gating)

2) Execute the dispatched role:
   - Planning / Implementation / Validation / Remediation
   - Follow the referenced prompt file exactly.


### Entry points (low-token)

```
Follow ai/INTAKE_PRD.prompt.md
Follow ai/INTAKE_CHANGE.prompt.md
Follow ai/INTAKE_ISSUE.prompt.md
Follow ai/INTAKE_RESEARCH.prompt.md
Follow ai/INTAKE_HOTFIX.prompt.md
Follow ai/INTAKE_TECHDEBT.prompt.md
Follow ai/INTAKE_RFC.prompt.md
Follow ai/INTAKE_RELEASE.prompt.md
Follow ai/ORCHESTRATION.prompt.md
Follow ai/ORCHESTRATION_PARALLEL.prompt.md
Follow ai/ORCHESTRATION_HITL.prompt.md
Follow ai/BOOTSTRAP_DIFF.prompt.md
Follow ai/GENERATE_README.prompt.md
```

## Rules
- Do not claim PASS without executable evidence.
- Do not invent technologies: read docs/TECHNOLOGY.md first.
- Archived analyses are read-only; new knowledge goes into FACTS.md and UI_MAP.md.
- If CLAUDE.md or Copilot instructions conflict with this file, follow this file.
- Bootstrap must preserve scaffolding assets: never delete docs/templates/*,
  docs/rfc/, or docs/**/.gitkeep placeholders only because they are unreferenced.
- Intake language policy: accept user input in the user's language, but write
  saved repository documents in English.
- Intake efficiency policy: ask only for missing high-impact fields, prefer
  explicit assumptions over long clarification loops, and keep intake token-light.
