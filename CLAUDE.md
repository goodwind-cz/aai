# Claude Instructions (Shim)

This file is intentionally minimal to prevent duplicated or conflicting guidance.

## Canonical instructions
- Primary agent guide: .aai/AGENTS.md
- Human playbook: .aai/PLAYBOOK.md
- Canonical prompts: .aai/*.prompt.md
- Intake entrypoints: listed in .aai/AGENTS.md
- Canonical workflow: .aai/workflow/WORKFLOW.md
- Technology contract (authoritative): docs/TECHNOLOGY.md

## Rules
- Do not define workflow here.
- Do not create alternate role definitions here.
- If any guidance conflicts with .aai/AGENTS.md/.aai/PLAYBOOK.md, follow .aai/AGENTS.md/.aai/PLAYBOOK.md.

## How to proceed
1) Read .aai/AGENTS.md
2) Follow .aai/ORCHESTRATION.prompt.md to decide the next role
3) Execute only the dispatched role prompt
