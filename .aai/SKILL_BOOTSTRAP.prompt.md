# Bootstrap Skill - Dynamic AAI Skills

## Goal
Detect project architecture and generate project-specific `aai-*` skills that are:
- directly visible to Claude (`.claude/skills/`)
- preserved by `aai-sync` (target-only skill folders are not removed)
- discoverable for Codex and Gemini via local index files
- concrete, idempotent, and safe for already configured projects

## Default Path

Use the deterministic generator first:

```bash
./.aai/scripts/aai-bootstrap.sh . --dry-run
```

Review the dry-run summary. If it is acceptable and there are no conflicts:

```bash
./.aai/scripts/aai-bootstrap.sh .
```

If `.aai/scripts/aai-bootstrap.sh` is missing, stop and report:
"aai-bootstrap generator not found - expected .aai/scripts/aai-bootstrap.sh. Run aai-sync/update first."

## What the Generator Detects

The generator scans repository evidence for:
- package managers and manifests (`package.json`, lockfiles, `pyproject.toml`, `Cargo.toml`, `go.mod`, `pom.xml`, Gradle files)
- task runners (`Makefile`, `justfile`)
- test frameworks (`playwright.config.*`, `cypress.config.*`, `jest.config.*`, `vitest.config.*`, `pytest.ini`, language defaults)
- build/lint toolchain (`vite.config.*`, `webpack.config.*`, `tsconfig.json`, `Dockerfile`, ESLint/Biome/Ruff configs)
- deploy paths (`wrangler.toml`, `vercel.json`, `netlify.toml`, deploy/publish/release scripts)
- CI/CD hints (`.github/workflows/`)
- authentication signals for E2E tests

## Generated Outputs

The generator may create/update:
- `.claude/skills/aai-test-e2e/SKILL.md` (only if an E2E command is detected)
- `.claude/skills/aai-test-unit/SKILL.md` (only if a unit test command is detected)
- `.claude/skills/aai-build/SKILL.md` (only if a build/typecheck command is detected)
- `.claude/skills/aai-lint/SKILL.md` (only if a lint/static-check command is detected)
- `.claude/skills/aai-deploy/SKILL.md` (only if a deploy path is detected)
- `.claude/skills/AAI_DYNAMIC_SKILLS.md`
- `.codex/skills.local/README.md`
- `.gemini/skills.local/README.md`
- `.gitignore` cache-path hygiene entries

## Safety Rules

- Never manually overwrite an existing dynamic skill file.
- The generator refuses to replace unmarked files unless `--force` is passed.
- Use `--force` only after explicit user confirmation and only for the listed conflict paths.
- Do not delete existing skills.
- Do not write dynamic skills into `.claude/skills.local/`.
- Do not fabricate commands. If no concrete command is detected, leave that skill skipped and report why.
- Do not store real passwords, API keys, session cookies, or tokens in `SKILL.md` or committed docs.

## Authentication Handling

When E2E tooling and auth signals are detected, generated E2E skills include a prerequisites section.

Credential policy:
- Prefer non-secret references such as env var names from `.env.e2e`, `.env.test`, or `.env.testing`.
- If `docs/knowledge/FACTS.md` already has `## Test Credentials`, reference that section.
- If no safe reference exists, ask the user one question in their language:
  "The app uses authentication. Which non-secret credential reference should E2E tests use? Provide env var names or say 'skip'."
- If the user provides actual secret values, do not write them to files. Ask for env var names or a secret-manager reference instead.

## Report Results

Final output must include:
- detected architecture summary
- auth note if auth was detected
- generated/updated file list
- skipped skill list with reasons
- ready-to-use commands, for example `/aai-test-e2e`, `/aai-test-unit`, `/aai-build`, `/aai-lint`
