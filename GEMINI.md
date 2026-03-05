# Gemini Instructions (Shim)

This file is intentionally minimal to avoid duplicated guidance.

## Canonical sources
- Agent guide: `.aai/AGENTS.md`
- Playbook: `.aai/PLAYBOOK.md`
- Prompts: `.aai/*.prompt.md`
- Workflow: `.aai/workflow/WORKFLOW.md`
- Technology contract: `docs/TECHNOLOGY.md`

## Skill discovery (AAI prefix)
- Universal skills:
  - `/aai-check-state` -> `.aai/SKILL_CHECK_STATE.prompt.md`
  - `/aai-intake` -> `.aai/SKILL_INTAKE.prompt.md`
  - `/aai-loop` -> `.aai/SKILL_LOOP.prompt.md`
  - `/aai-hitl` -> `.aai/SKILL_HITL.prompt.md`
  - `/aai-bootstrap` -> `.aai/SKILL_BOOTSTRAP.prompt.md`
  - `/aai-validate-report` -> `.aai/SKILL_VALIDATE_REPORT.prompt.md`
  - `/aai-canonicalize` -> `.aai/SKILL_CANONICALIZE.prompt.md`
  - `/aai-share` -> `.aai/SKILL_SHARE.prompt.md`
  - `/aai-tdd` -> `.aai/SKILL_TDD.prompt.md`
  - `/aai-worktree` -> `.aai/SKILL_WORKTREE.prompt.md`
  - `/aai-flush` -> `.aai/SKILL_FLUSH.prompt.md`
- Project-local generated skills live in `.claude/skills/` and must use `aai-` prefix.
- Dynamic Gemini index is written to `.gemini/skills.local/README.md` by `/aai-bootstrap`.

## How to proceed
1) Read `.aai/AGENTS.md`.
2) Use `aai-*` skills for orchestration/intake/loop.
3) Keep Requirement -> Spec -> Implementation -> Evidence traceability.
