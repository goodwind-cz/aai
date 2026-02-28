# Bootstrap Skill - Dynamic AAI Skills

## Goal
Detect project architecture and generate project-specific `aai-*` skills that are:
- directly visible to Claude (`.claude/skills/`)
- preserved by `ai-os-sync` (target-only skill folders are not removed)
- discoverable for Codex and Gemini via local index files

## Instructions

### 1. Detect Project Architecture

Scan repository root for:
- package manager (`package.json`, `pyproject.toml`, `poetry.lock`, `Cargo.toml`, `go.mod`)
- test frameworks (`playwright.config.*`, `cypress.*`, `jest.config.*`, `vitest.config.*`, `pytest.ini`)
- build/lint toolchain (`vite.config.*`, `webpack.config.*`, `tsconfig.json`, `Dockerfile`, lint configs)
- CI/CD hints (`.github/workflows/`)
- optional MCP availability (`mcp list`)

### 2. Generate Claude-Visible Dynamic Skills

Create/update these folders in `.claude/skills/`:
- `.claude/skills/aai-test-e2e/SKILL.md` (if E2E stack detected)
- `.claude/skills/aai-test-unit/SKILL.md`
- `.claude/skills/aai-build/SKILL.md`
- `.claude/skills/aai-lint/SKILL.md`
- `.claude/skills/aai-deploy/SKILL.md` (only if deploy path is detectable)

Rules:
- Use `aai-` prefix.
- Never overwrite an existing dynamic skill file without explicit user confirmation.
- Keep generated commands concrete and runnable in the current repository.

### 3. Write Dynamic Skill Marker (required)

Create/update:
- `.claude/skills/AAI_DYNAMIC_SKILLS.md`

This file must include:
- generation timestamp (UTC)
- detected stack summary
- list of generated `aai-*` skill names
- note that these are project-owned dynamic skills

### 4. Write Cross-Agent Discovery Indexes

Create/update:
- `.codex/skills.local/README.md`
- `.gemini/skills.local/README.md`

Both files should list the generated `aai-*` skills and where they live:
- `.claude/skills/<skill-name>/SKILL.md`

### 5. .gitignore Hygiene

Ensure cache paths are ignored, but dynamic skill definitions are committed:
- `.claude/skills/.cache`
- `.codex/skills.local/.cache`
- `.gemini/skills.local/.cache`

### 6. Report Results

Output:
- detected architecture summary
- generated/updated file list
- ready-to-use commands (for example `/aai-test-e2e`, `/aai-test-unit`, `/aai-build`, `/aai-lint`)

## Safety
- Do not fabricate tooling commands.
- Do not delete existing skills.
- Do not write dynamic skills into `.claude/skills.local/`.
