# Gemini Instructions (Shim)

This file is intentionally minimal to avoid duplicated guidance.

## Canonical sources
- Agent guide: `.aai/AGENTS.md`
- Playbook: `.aai/PLAYBOOK.md`
- Prompts: `.aai/*.prompt.md`
- Workflow: `.aai/workflow/WORKFLOW.md`
- Technology contract: `docs/TECHNOLOGY.md`

## Skill discovery (AAI prefix)
- This shim intentionally lists no skills — inline lists rot. The canonical
  catalog is `SKILLS.md` (root) and the Skills Catalog section of
  `docs/USER_GUIDE.md`.
- Gemini wrapper tree: `.gemini/skills/` mirrors the skill set; each skill maps
  `/aai-<name>` to a `.aai/SKILL_<NAME>.prompt.md` prompt file.
- Invocation pattern: `gemini --prompt-file .aai/SKILL_<NAME>.prompt.md`
  (e.g. `gemini --prompt-file .aai/SKILL_INTAKE.prompt.md`).
- Project-local generated skills live in `.claude/skills/` and must use `aai-` prefix.
- Dynamic Gemini index is written to `.gemini/skills.local/README.md` by `/aai-bootstrap`.

## How to proceed
1) Read `.aai/AGENTS.md`.
2) Use `aai-*` skills for orchestration/intake/loop.
3) Keep Requirement -> Spec -> Implementation -> Evidence traceability.
