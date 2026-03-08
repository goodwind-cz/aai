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

## AAI Skills (post-sync)
- Universal AAI skill commands:
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
  - `/aai-test-skills` -> `.aai/SKILL_TEST_SKILLS.prompt.md`
  - `/aai-docs-hub` -> `.aai/SKILL_DOCS_HUB.prompt.md`
  - `/aai-decapod` -> `.aai/SKILL_DECAPOD.prompt.md`
  - `/aai-auto-trigger` -> `.aai/SKILL_AUTO_TRIGGER.prompt.md`
  - `/aai-dashboard` -> `.aai/SKILL_DASHBOARD.prompt.md`
  - `/aai-code-review` -> `.aai/SKILL_CODE_REVIEW.prompt.md`
  - `/aai-profile` -> `.aai/SKILL_PROFILE.prompt.md`
  - `/aai-doctor` -> `.aai/SKILL_DOCTOR.prompt.md`
  - `/aai-replay` -> `.aai/SKILL_REPLAY.prompt.md`
  - `/aai-wrap-up` -> `.aai/SKILL_WRAP_UP.prompt.md`
- Project-specific generated skills are in `.claude/skills/` and use `aai-` prefix.
