# Codex Instructions (Shim)

This file is intentionally minimal to avoid duplicated guidance.

## Canonical sources
- Agent guide: `AGENTS.md`
- Playbook: `PLAYBOOK.md`
- Prompts: `ai/*.prompt.md`
- Workflow: `docs/workflow/WORKFLOW.md`
- Technology contract: `docs/TECHNOLOGY.md`

## Skill discovery (AAI prefix)
- Universal skills:
  - `/aai-check-state` -> `ai/SKILL_CHECK_STATE.prompt.md`
  - `/aai-intake` -> `ai/SKILL_INTAKE.prompt.md`
  - `/aai-loop` -> `ai/SKILL_LOOP.prompt.md`
  - `/aai-hitl` -> `ai/SKILL_HITL.prompt.md`
  - `/aai-bootstrap` -> `ai/SKILL_BOOTSTRAP.prompt.md`
- Project-local generated skills live in `.claude/skills.local/` and must use `aai-` prefix.

## How to proceed
1) Read `AGENTS.md`.
2) Use `aai-*` skills for orchestration/intake/loop.
3) Keep Requirement -> Spec -> Implementation -> Evidence traceability.
