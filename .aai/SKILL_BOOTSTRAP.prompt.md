# Bootstrap Skill - Dynamic AAI Skills

## Goal
Detect project architecture and generate project-specific `aai-*` skills that are:
- directly visible to Claude (`.claude/skills/`)
- preserved by `aai-sync` (target-only skill folders are not removed)
- discoverable for Codex and Gemini via local index files

## Instructions

### 1. Detect Project Architecture

Scan repository root for:
- package manager (`package.json`, `pyproject.toml`, `poetry.lock`, `Cargo.toml`, `go.mod`)
- test frameworks (`playwright.config.*`, `cypress.*`, `jest.config.*`, `vitest.config.*`, `pytest.ini`)
- build/lint toolchain (`vite.config.*`, `webpack.config.*`, `tsconfig.json`, `Dockerfile`, lint configs)
- CI/CD hints (`.github/workflows/`)
- optional MCP availability (`mcp list`)
- authentication & test credentials (see step 1b)

### 1b. Detect Authentication & Test Credentials

When an E2E test framework is detected, probe for authentication:

**Detection signals** (scan for any of these):
- Login page/component: `login`, `sign-in`, `auth` in routes, pages, or components
- Auth middleware: `auth`, `session`, `jwt`, `passport`, `next-auth`, `clerk` in config/middleware
- Protected routes: route guards, `requireAuth`, `withAuth` wrappers
- Existing test fixtures: `globalSetup`, `beforeAll` with login, `storageState`, seed scripts

**If auth is detected:**
1. Check `docs/knowledge/FACTS.md` for existing test credentials section.
2. Check `.env.test`, `.env.testing`, or `.env.e2e` for test user variables.
3. Check Playwright `globalSetup` or Cypress `support/commands` for existing login helpers.
4. If credentials are already documented → use them in generated E2E skill.
5. If credentials are NOT found → ask the user ONE question (in their language):
   "The app uses authentication. What test user should E2E tests use? (email + password, or 'skip' if no login needed)"
6. Save the answer to `docs/knowledge/FACTS.md` under a `## Test Credentials` section.
7. Never store credentials in SKILL.md files directly — reference `FACTS.md` instead.

**If no auth detected** → skip this step silently.

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

#### E2E Skill Auth Integration

When generating `aai-test-e2e/SKILL.md` and auth was detected in step 1b:
- Include a "Prerequisites" section referencing `docs/knowledge/FACTS.md` for test credentials.
- If Playwright `globalSetup` or `storageState` exists, reference it so tests reuse a single login session.
- If no `globalSetup` exists, include a note to create one (login once per run, not per test).
- Example snippet for generated SKILL.md:
  ```
  ## Prerequisites
  - Test credentials: see docs/knowledge/FACTS.md → "Test Credentials"
  - Auth session: managed via globalSetup (login once, reuse storageState)
  ```

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
