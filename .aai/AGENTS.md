# Agent Guide (Canonical)

This repository uses a reusable AAI.

## Canonical sources
- Workflow (single source): .aai/workflow/WORKFLOW.md
- Semantic roles: .aai/roles/ROLES.md
- Technology contract: docs/TECHNOLOGY.md (created by .aai/TECH_EXTRACT.prompt.md)
- Fact memory: docs/knowledge/FACTS.md
- Pattern library (project): docs/knowledge/PATTERNS.md
- Pattern library (universal, sync-managed): .aai/knowledge/PATTERNS_UNIVERSAL.md
- UI map: docs/knowledge/UI_MAP.md
- Prompts: ai/*.prompt.md
- Subagent protocol: .aai/SUBAGENT_PROTOCOL.md
- Human playbook: PLAYBOOK.md
- Coordination locks (optional): .aai/system/LOCKS.md
- Metrics ledger: docs/ai/METRICS.jsonl
- Model pricing: .aai/system/PRICING.yaml
- Loop tick log: docs/ai/LOOP_TICKS.jsonl
- Learned rules: docs/knowledge/LEARNED.md
- Decision log: docs/ai/decisions.jsonl
- Project session journal index: docs/project-sessions/INDEX.md

To update the AAI layer from a template worktree, see .aai/scripts/aai-sync.(sh|ps1) and .aai/system/AAI_PIN.md.

## How to run (recommended)
1) Decide next action:
   - Run .aai/ORCHESTRATION.prompt.md (single)
   - Or .aai/ORCHESTRATION_PARALLEL.prompt.md (parallel, resource-sensitive)
   - Or .aai/ORCHESTRATION_HITL.prompt.md (human decision gating)

2) Execute the dispatched role:
   - Planning / Implementation / Validation / Remediation
   - Planning: .aai/PLANNING.prompt.md
   - Implementation: .aai/IMPLEMENTATION.prompt.md
   - Validation: .aai/VALIDATION.prompt.md
   - Remediation: .aai/REMEDIATION.prompt.md
   - Follow the referenced prompt file exactly.


### Entry points (low-token)

```
Follow .aai/INTAKE_PRD.prompt.md
Follow .aai/INTAKE_CHANGE.prompt.md
Follow .aai/INTAKE_ISSUE.prompt.md
Follow .aai/INTAKE_RESEARCH.prompt.md
Follow .aai/INTAKE_HOTFIX.prompt.md
Follow .aai/INTAKE_TECHDEBT.prompt.md
Follow .aai/INTAKE_RFC.prompt.md
Follow .aai/INTAKE_RELEASE.prompt.md
Follow .aai/ORCHESTRATION.prompt.md
Follow .aai/ORCHESTRATION_PARALLEL.prompt.md
Follow .aai/ORCHESTRATION_HITL.prompt.md
Follow .aai/BOOTSTRAP_DIFF.prompt.md
Follow .aai/GENERATE_README.prompt.md
Follow .aai/METRICS_FLUSH.prompt.md
Follow .aai/METRICS_REPORT.prompt.md
Follow .aai/MEMORY_REVIEW.prompt.md
```

### Skills (agent-invocable, session-scoped)

Skills are higher-level entry points that compose multiple steps within a single agent session.
Use them when the agent supports subagent spawning or sequential tool use.

#### Universal Skills (AAI Template)
```text
Follow .aai/SKILL_LOOP.prompt.md         # Full autonomous multi-tick loop (replaces shell loop runner)
Follow .aai/SKILL_INTAKE.prompt.md       # Universal intake router — auto-detects type from description
Follow .aai/SKILL_HITL.prompt.md         # Human-in-the-loop resolver — surfaces blocked question, unblocks state
Follow .aai/SKILL_CHECK_STATE.prompt.md  # STATE.yaml health check — validates all invariants
Follow .aai/SKILL_BOOTSTRAP.prompt.md    # Generate project-specific optimized skills
Follow .aai/SKILL_VALIDATE_REPORT.prompt.md # Validation report with screenshot evidence for chat review
Follow .aai/SKILL_CANONICALIZE.prompt.md # Canonicalize repository structure (migration, cleanup)
Follow .aai/SKILL_TDD.prompt.md          # Enforced RED-GREEN-REFACTOR test-driven development (Superpowers pattern)
Follow .aai/SKILL_WORKTREE.prompt.md     # Git worktree management for parallel development (Superpowers pattern)
Follow .aai/SKILL_SHARE.prompt.md        # Publish reports to Cloudflare Pages with shareable URL
Follow .aai/SKILL_FLUSH.prompt.md        # Manual metrics flush & state cleanup (when loop doesn't complete it)
Follow .aai/SKILL_DOCTOR.prompt.md       # Environment health check — validates files, skills, knowledge, git (pro-workflow)
Follow .aai/SKILL_REPLAY.prompt.md       # Contextual learning replay — surfaces relevant past learnings (pro-workflow)
Follow .aai/SKILL_SESSION_JOURNAL.prompt.md # Named project session journal — human-readable cross-agent discussion trail
Follow .aai/SKILL_WRAP_UP.prompt.md      # Session wrap-up — capture learnings, propose rules, prepare next session (pro-workflow)
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
- Preserved during `aai-sync` updates

See [.aai/system/DYNAMIC_SKILLS.md](.aai/system/DYNAMIC_SKILLS.md) for details.

Skill selection guide:

- Use SKILL_LOOP instead of autonomous-loop.sh when running inside a capable agent session.
- Use SKILL_INTAKE instead of picking a specific INTAKE_*.prompt.md manually.
- Use SKILL_HITL after SKILL_LOOP pauses with "LOOP PAUSED — Human decision required".
- Use SKILL_CHECK_STATE before any role dispatch to catch state drift or corruption.
- Use SKILL_BOOTSTRAP on first use or after architecture changes to generate project-specific skills.
- Use SKILL_VALIDATE_REPORT when validation must include screenshot evidence and a chat-readable report.
- Use SKILL_CANONICALIZE when migrating legacy AAI structure or cleaning up scattered artifacts.
- **NEW:** Use SKILL_TDD for test-driven development with mandatory RED-GREEN-REFACTOR cycles.
- **NEW:** Use SKILL_WORKTREE for parallel development using git worktrees (isolates features/tasks).
- **NEW:** Use SKILL_DOCTOR to diagnose the full AAI environment (broader than CHECK_STATE).
- **NEW:** Use SKILL_REPLAY to surface relevant past learnings before starting work.
- **NEW:** Use SKILL_SESSION_JOURNAL to create or resume a named project discussion thread in the user's language.
- **NEW:** Use SKILL_WRAP_UP at the end of a session to capture learnings and prepare next session.
- **NEW:** SKILL_LOOP now supports checkpoint_mode (none/staged/paranoid) for phase-gated approval.

### Skill Invocation (Claude vs Codex)

- Claude-style slash command:
  - `/aai-test-e2e`, `/aai-test-unit`, `/aai-build`, `/aai-lint`, `/aai-deploy`
- Codex-style prompt-file execution:
  - `codex --prompt-file .aai/SKILL_CHECK_STATE.prompt.md`
  - `codex --prompt-file .aai/SKILL_INTAKE.prompt.md`
  - `codex --prompt-file .aai/SKILL_LOOP.prompt.md`
  - `codex --prompt-file .aai/SKILL_CANONICALIZE.prompt.md`
- Bootstrap also writes dynamic indexes:
  - `.codex/skills.local/README.md`
  - `.gemini/skills.local/README.md`
- Loop runners are skill-first by default and enforce this sequence unless explicitly switched to legacy mode.

## External Expert Subagents

AAI can dynamically fetch domain-expert prompts from [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents) to enhance implementation quality.

- Protocol: `.aai/EXPERT_RESOLVE.prompt.md` (how to detect, fetch, inject experts)
- All operations go through CLI: `bash .aai/scripts/expert-fetch.sh --detect|--check|--body|--list`
- **Do NOT read `.aai/system/EXPERT_REGISTRY.yaml`** — the script reads it internally
- Experts are used in: Implementation (step 3b), TDD GREEN (phase 2.0), TDD REFACTOR (phase 3.0)
- Experts NEVER participate in: RED phase, Validation, Planning, Orchestration
- Security: pinned SHA, size limit, tool whitelist, injection pattern detection, scope isolation

## Communication Style (pro-workflow)

When running skills or loop ticks, use minimal, action-focused updates:

1. **Use symbols** instead of prose:
   - ✓ completed action
   - ⚙ in progress
   - ⚠ warning
   - ✗ error / blocked
   - ⏸ paused / waiting for input

2. **One-line status** per major action:
   ```
   ⚙ RED phase: writing failing test for password validation
   ✓ Test fails as expected → evidence captured
   ⚙ GREEN phase: minimal implementation
   ✓ All tests pass
   ```

3. **No preambles** like "I will now...", "Let me check...", "I can see that..."
   Just state what is happening or what completed.

4. **Exception: checkpoints and decisions** — these should be detailed and clear.

5. **Exception: errors and blockers** — explain enough for the user to act.

Source: Inspired by pro-workflow communication style (https://github.com/rohitg00/pro-workflow)

## Quality Gates (pre-commit)

Before committing, run quality gate checks (`.aai/scripts/pre-commit-checks.sh` or `.ps1`):
- Secrets detection in staged files (BLOCKS commit)
- Debug statement scan (warning)
- TODO/FIXME markers (warning)
- TDD evidence completeness (warning)
- Validation report existence (warning)

Skills that commit (/aai-tdd, /aai-loop, /aai-validate-report) should run these checks automatically.
Use `--strict` flag to treat warnings as errors.

## Learned Rules

Project-specific learned rules are stored in `docs/knowledge/LEARNED.md`.
This file is loaded into context for every session.
When a user corrects a mistake, propose adding a rule:
- "Should I remember: '<rule text>'?"
- If approved, append to the appropriate section with date and source.

Project discussion continuity belongs in `docs/project-sessions/`.
Use that folder for human-readable narrative rationale and session resume context.
Do not use it as a substitute for specs, decisions, facts, or validation evidence.

## Rules
- Do not claim PASS without executable evidence.
- Do not invent technologies: read docs/TECHNOLOGY.md first.
- Archived analyses are read-only; new knowledge goes into FACTS.md, PATTERNS.md, and UI_MAP.md.
- PATTERNS_UNIVERSAL.md is sync-managed — never write to it directly; suggest promotions via report.
- If CLAUDE.md, CODEX.md, GEMINI.md, or Copilot instructions conflict with this file, follow this file.
- Bootstrap must preserve scaffolding assets: never delete .aai/templates/*,
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
