# Agent Guide (Canonical)

This repository uses a reusable AI Operating System.

## Canonical sources
- Workflow (single source): docs/workflow/WORKFLOW.md
- Semantic roles: docs/roles/ROLES.md
- Technology contract: docs/TECHNOLOGY.md (created by ai/TECH_EXTRACT.prompt.md)
- Fact memory: docs/knowledge/FACTS.md
- Pattern library (project): docs/knowledge/PATTERNS.md
- Pattern library (universal, sync-managed): docs/knowledge/PATTERNS_UNIVERSAL.md
- UI map: docs/knowledge/UI_MAP.md
- Prompts: ai/*.prompt.md
- Subagent protocol: ai/SUBAGENT_PROTOCOL.md
- Human playbook: PLAYBOOK.md
- Coordination locks (optional): docs/ai/LOCKS.md
- Metrics ledger: docs/ai/METRICS.jsonl
- Model pricing: docs/ai/PRICING.yaml
- Loop tick log: docs/ai/LOOP_TICKS.jsonl
- Decision log: docs/ai/decisions.jsonl

To update the AI-OS layer from a template worktree, see scripts/ai-os-sync.(sh|ps1) and docs/ai/AI_OS_PIN.md.

## How to run (recommended)
1) Decide next action:
   - Run ai/ORCHESTRATION.prompt.md (single)
   - Or ai/ORCHESTRATION_PARALLEL.prompt.md (parallel, resource-sensitive)
   - Or ai/ORCHESTRATION_HITL.prompt.md (human decision gating)

2) Execute the dispatched role:
   - Planning / Implementation / Validation / Remediation
   - Planning: ai/PLANNING.prompt.md
   - Implementation: ai/IMPLEMENTATION.prompt.md
   - Validation: ai/VALIDATION.prompt.md
   - Remediation: ai/REMEDIATION.prompt.md
   - Follow the referenced prompt file exactly.


### Entry points (low-token)

```
Follow ai/INTAKE_PRD.prompt.md
Follow ai/INTAKE_CHANGE.prompt.md
Follow ai/INTAKE_ISSUE.prompt.md
Follow ai/INTAKE_RESEARCH.prompt.md
Follow ai/INTAKE_HOTFIX.prompt.md
Follow ai/INTAKE_TECHDEBT.prompt.md
Follow ai/INTAKE_RFC.prompt.md
Follow ai/INTAKE_RELEASE.prompt.md
Follow ai/ORCHESTRATION.prompt.md
Follow ai/ORCHESTRATION_PARALLEL.prompt.md
Follow ai/ORCHESTRATION_HITL.prompt.md
Follow ai/BOOTSTRAP_DIFF.prompt.md
Follow ai/GENERATE_README.prompt.md
Follow ai/METRICS_FLUSH.prompt.md
Follow ai/METRICS_REPORT.prompt.md
Follow ai/MEMORY_REVIEW.prompt.md
```

### Skills (agent-invocable, session-scoped)

Skills are higher-level entry points that compose multiple steps within a single agent session.
Use them when the agent supports subagent spawning or sequential tool use.

#### Universal Skills (AI-OS Template)
```text
Follow ai/SKILL_LOOP.prompt.md         # Full autonomous multi-tick loop (replaces shell loop runner)
Follow ai/SKILL_INTAKE.prompt.md       # Universal intake router — auto-detects type from description
Follow ai/SKILL_HITL.prompt.md         # Human-in-the-loop resolver — surfaces blocked question, unblocks state
Follow ai/SKILL_CHECK_STATE.prompt.md  # STATE.yaml health check — validates all invariants
Follow ai/SKILL_BOOTSTRAP.prompt.md    # Generate project-specific optimized skills (NEW)
Follow ai/SKILL_VALIDATE_REPORT.prompt.md # Validation report with screenshot evidence for chat review
Follow ai/SKILL_CANONICALIZE.prompt.md # Intake + migration + canonical cleanup for legacy paths/evidence
```

#### Project-Specific Skills (Auto-Generated)

After running `/aai-bootstrap`, the following skills are auto-generated in `.claude/skills/`:

```text
/aai-test-e2e    # Run E2E tests (Playwright/Cypress) - auto-detects MCP server
/aai-test-unit   # Run unit tests (Jest/Vitest/Pytest) - incremental mode
/aai-build       # Build commands (Vite/Webpack/tsc) - optimized for quick validation
/aai-lint        # Lint and format (ESLint/Prettier/Ruff) - targeted file mode
/aai-deploy      # Deployment shortcuts (if CI/CD detected)
```

**Benefits:**
- 90% token reduction for common tasks
- MCP server integration when available
- Preserved during `ai-os-sync` updates

See [docs/ai/DYNAMIC_SKILLS.md](docs/ai/DYNAMIC_SKILLS.md) for details.

Skill selection guide:

- Use SKILL_LOOP instead of autonomous-loop.sh when running inside a capable agent session.
- Use SKILL_INTAKE instead of picking a specific INTAKE_*.prompt.md manually.
- Use SKILL_HITL after SKILL_LOOP pauses with "LOOP PAUSED — Human decision required".
- Use SKILL_CHECK_STATE before any role dispatch to catch state drift or corruption.
- **NEW:** Use SKILL_BOOTSTRAP on first use or after architecture changes to generate project-specific skills.
- Use SKILL_VALIDATE_REPORT when validation must include screenshot evidence and a chat-readable report.
- Use SKILL_CANONICALIZE when consolidating legacy evidence/validation files into canonical AI-OS paths.

### Skill Invocation (Claude vs Codex)

- Claude-style slash command:
  - `/aai-test-e2e`, `/aai-test-unit`, `/aai-build`, `/aai-lint`, `/aai-deploy`
- Codex-style prompt-file execution:
  - `codex --prompt-file ai/SKILL_CHECK_STATE.prompt.md`
  - `codex --prompt-file ai/SKILL_INTAKE.prompt.md`
  - `codex --prompt-file ai/SKILL_LOOP.prompt.md`
  - `codex --prompt-file ai/SKILL_CANONICALIZE.prompt.md`
- Bootstrap also writes dynamic indexes:
  - `.codex/skills.local/README.md`
  - `.gemini/skills.local/README.md`
- Loop runners are skill-first by default and enforce this sequence unless explicitly switched to legacy mode.

## Rules
- Do not claim PASS without executable evidence.
- Do not invent technologies: read docs/TECHNOLOGY.md first.
- Archived analyses are read-only; new knowledge goes into FACTS.md, PATTERNS.md, and UI_MAP.md.
- PATTERNS_UNIVERSAL.md is sync-managed — never write to it directly; suggest promotions via report.
- If CLAUDE.md, CODEX.md, GEMINI.md, or Copilot instructions conflict with this file, follow this file.
- Bootstrap must preserve scaffolding assets: never delete docs/templates/*,
  docs/rfc/, or docs/**/.gitkeep placeholders only because they are unreferenced.
- Intake language policy: accept user input in the user's language, but write
  saved repository documents in English.
- Intake efficiency policy: ask only for missing high-impact fields, prefer
  explicit assumptions over long clarification loops, and keep intake token-light.
- Commit gating policy: create a commit only after the full intake-scoped task
  is completed, verified with executable evidence, fully documented, and only
  after explicit user confirmation.

## Engineering Best Practices
- Prefer DRY: avoid duplicated logic; extract shared behavior behind clear interfaces.
- Apply SOLID where it improves maintainability, especially Single Responsibility and Dependency Inversion.
- Keep solutions simple (KISS); avoid accidental complexity.
- Use YAGNI: do not implement speculative features before a requirement exists.
- Maintain clear separation of concerns (domain, orchestration, infrastructure, UI).
- Preserve backward compatibility at public boundaries (APIs/events/contracts), or document explicit breaking changes.
- Design for testability: deterministic behavior, small units, and executable verification paths.
- Make errors explicit and actionable: fail fast, surface context, avoid silent failures.
