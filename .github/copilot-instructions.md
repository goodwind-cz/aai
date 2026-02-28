# Copilot Instructions (Shim)

This repository uses a single canonical workflow and a prompt suite for consistent agent behavior.

## Canonical sources
- Agent guide: /AGENTS.md
- Playbook: /PLAYBOOK.md
- Prompts: /ai/*.prompt.md
- Intake entrypoints: /AGENTS.md
- Workflow: /docs/workflow/WORKFLOW.md
- Technology contract: /docs/TECHNOLOGY.md

## Rules
- Do not introduce alternative workflows or role systems.
- Do not assume frameworks or tools not documented in /docs/TECHNOLOGY.md.
- Prefer changes that preserve traceability:
  Requirement → Spec → Implementation → Evidence

## Suggested developer flow
- Use ai/ORCHESTRATION.prompt.md to select the next role step.
- Validate with ai/VALIDATION.prompt.md before claiming completion.

## AAI Skills (post-sync)
- Universal AAI skill commands:
  - `/aai-check-state` -> `ai/SKILL_CHECK_STATE.prompt.md`
  - `/aai-intake` -> `ai/SKILL_INTAKE.prompt.md`
  - `/aai-loop` -> `ai/SKILL_LOOP.prompt.md`
  - `/aai-hitl` -> `ai/SKILL_HITL.prompt.md`
  - `/aai-bootstrap` -> `ai/SKILL_BOOTSTRAP.prompt.md`
  - `/aai-validate-report` -> `ai/SKILL_VALIDATE_REPORT.prompt.md`
- Project-specific generated skills are in `.claude/skills.local/` and use `aai-` prefix.
