# Copilot Instructions (Shim)

This repository uses a single canonical workflow and a prompt suite for consistent agent behavior.

## Canonical sources
- Agent guide: /.aai/AGENTS.md
- Playbook: /.aai/PLAYBOOK.md
- Prompts: /.aai/*.prompt.md
- Intake entrypoints: /.aai/AGENTS.md
- Workflow: /.aai/workflow/WORKFLOW.md
- Technology contract: /docs/TECHNOLOGY.md

## Rules
- Do not introduce alternative workflows or role systems.
- Do not assume frameworks or tools not documented in /docs/TECHNOLOGY.md.
- Prefer changes that preserve traceability:
  Requirement → Spec → Implementation → Evidence

## Suggested developer flow
- Use .aai/ORCHESTRATION.prompt.md to select the next role step.
- Validate with .aai/VALIDATION.prompt.md before claiming completion.

## Skill discovery (AAI prefix)
- This shim intentionally lists no skills — inline lists rot. The canonical
  catalog is `SKILLS.md` (root) and the Skills Catalog section of
  `docs/USER_GUIDE.md`.
- Project-specific generated skills are in `.claude/skills/` and use `aai-` prefix.
