# Dynamic Skills System

## Overview

AI-OS supports **dynamic, project-specific skills** that automatically adapt to your project's architecture, optimizing token usage and developer efficiency.

## How It Works

### 1. Bootstrap Detection

Run `/aai-bootstrap` in any AI-OS enabled project to:

1. **Detect architecture** - Scans for package managers, test frameworks, build tools, MCP servers
2. **Generate optimized skills** - Creates project-specific shortcuts in `.claude/skills.local/`
3. **Preserve on sync** - `ai-os-sync` never overwrites `.claude/skills.local/`

### 2. Skill Types

#### Universal Skills (from AI-OS template)
- `/aai-intake` - Universal work intake router
- `/aai-loop` - Autonomous multi-tick loop
- `/aai-hitl` - Human-in-the-loop resolver
- `/aai-check-state` - View STATE.yaml
- `/aai-bootstrap` - Generate project-specific skills

Location: `.claude/skills/` (synced from ai-os template)

#### Project-Specific Skills (auto-generated)
- `/aai-test-e2e` - Run E2E tests (Playwright/Cypress)
- `/aai-test-unit` - Run unit tests (Jest/Vitest/Pytest)
- `/aai-build` - Build commands (Vite/Webpack/tsc)
- `/aai-lint` - Lint and format (ESLint/Prettier/Ruff)
- `/aai-deploy` - Deployment shortcuts
- **Custom skills** - Add your own in `.claude/skills.local/`

Location: `.claude/skills.local/` (project-owned, never synced)

## Usage

### Initial Setup

```bash
# 1. Sync AI-OS into your project
cd /path/to/ai-os
./scripts/ai-os-sync.sh /path/to/your-project

# 2. Run bootstrap in your project
cd /path/to/your-project
# In Claude Code:
/aai-bootstrap
```

### Example: E2E Testing Skill

**Before bootstrap:**
```
You: "Run Playwright tests for the login flow"
Claude: *reads playwright.config.ts, package.json, checks MCP servers, constructs command, runs test*
Tokens: ~500
```

**After bootstrap:**
```
You: /aai-test-e2e login
Claude: *runs optimized test command from pre-generated skill*
Tokens: ~50
```

**Result:** 90% token reduction for common tasks!

## Architecture Detection

The bootstrap skill detects:

### Languages & Package Managers
- Node.js (npm, yarn, pnpm)
- Python (pip, poetry, pipenv)
- Rust (cargo)
- Go (go mod)
- Java (maven, gradle)

### Test Frameworks
- **E2E:** Playwright, Cypress, Selenium
- **Unit:** Jest, Vitest, Mocha, Pytest, Cargo test
- **Integration:** Supertest, pytest-django

### Build Tools
- Vite, Webpack, Rollup, esbuild
- TypeScript compiler
- Rust cargo
- Go build

### MCP Servers
- Playwright MCP (preferred for browser automation)
- Filesystem MCP
- GitHub MCP
- Custom MCP servers

### CI/CD
- GitHub Actions
- GitLab CI
- Docker
- Kubernetes

## Token Optimization Strategies

### 1. MCP Server Preference
```
✅ Use Playwright MCP server (offloads work)
❌ Fall back to local CLI if MCP unavailable
```

### 2. Incremental Commands
```bash
# Instead of:
npm test  # runs all 500 tests

# Use:
npm test -- --onlyChanged  # runs 5 tests
```

### 3. Smart Defaults
```bash
# Pre-configured in skill:
npx playwright test --grep "@smoke"  # fast smoke tests
npx playwright test path/to/specific.spec.ts  # targeted test
```

### 4. Build Caching
```bash
# Type check only (no emit):
npx tsc --noEmit

# Incremental build:
npm run build -- --watch
```

## Sync Behavior

### What Gets Synced (ai-os-sync)
- `.claude/skills/` - Universal AI-OS skills ✓
- `ai/` - AI-OS prompts ✓
- `docs/{workflow,roles,templates}` - AI-OS framework ✓
- `scripts/ai-os-sync.*` - Sync scripts ✓

### What Gets Preserved
- `.claude/skills.local/` - **Project-specific skills** ✓
- `docs/ai/STATE.yaml` - Runtime state ✓
- `docs/ai/METRICS.jsonl` - Metrics ✓
- `docs/{requirements,specs,decisions}` - Project docs ✓

## Creating Custom Skills

Add your own project-specific skills to `.claude/skills.local/`:

```bash
mkdir -p .claude/skills.local/my-skill
```

Create `.claude/skills.local/my-skill/SKILL.md`:
```markdown
---
name: my-skill
description: Custom shortcut for my specific workflow
---

# My Custom Skill

Run my custom command:

\`\`\`bash
npm run my-custom-command --with-flags
\`\`\`
```

Use it: `/my-skill`

## Best Practices

### 1. Run Bootstrap After Architecture Changes
```bash
# Added Playwright? Re-run bootstrap:
/aai-bootstrap
```

### 2. Commit .claude/skills.local/ to Git
```bash
# Project-specific skills are part of the project
git add .claude/skills.local/
git commit -m "Add optimized test skills"
```

### 3. Document Custom Skills
Update `.claude/skills.local/README.md` when adding custom skills.

### 4. Use MCP Servers When Available
Bootstrap automatically detects and prefers MCP servers for efficiency.

## Codex Agent Compatibility

Skills work for **both** Claude Code and Codex agents:

- **Claude Code:** Interactive `/skill-name` commands
- **Codex:** Programmatic skill invocation via Skill tool

Same skills, same efficiency, different interfaces.

## Examples

### TypeScript + Playwright Project

**Bootstrap detects:**
- package.json, tsconfig.json
- playwright.config.ts
- vite.config.ts

**Generates:**
- `/aai-test-e2e` → `npx playwright test`
- `/aai-test-unit` → `npx vitest`
- `/aai-build` → `npm run build`
- `/aai-lint` → `npm run lint -- --fix`

### Python + FastAPI Project

**Bootstrap detects:**
- pyproject.toml, poetry.lock
- pytest.ini
- Dockerfile

**Generates:**
- `/aai-test-unit` → `poetry run pytest`
- `/test-integration` → `poetry run pytest tests/integration`
- `/aai-lint` → `poetry run ruff check . --fix`
- `/aai-deploy` → `docker build -t app .`

## Troubleshooting

### Bootstrap doesn't detect my framework
Add detection patterns to `ai/SKILL_BOOTSTRAP.prompt.md` and re-sync.

### Skill not found after bootstrap
Check `.claude/skills.local/README.md` for generated skills list.

### ai-os-sync overwrote my custom skill
Move custom skills from `.claude/skills/` to `.claude/skills.local/`.

## Future Enhancements

- Auto-refresh skills on architecture changes
- Skill analytics (most used, token savings)
- Shared skill marketplace
- Multi-project skill templates
