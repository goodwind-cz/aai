# AAI Skills Reference

This document describes all universal skills included in the AAI framework.
Skills are session-scoped, multi-step prompts that compose workflow actions into reusable commands.

## Quick Reference

| # | Skill | Description | Claude | Codex / Gemini |
|---|-------|-------------|--------|----------------|
| 1 | aai-check-state | Validate STATE.yaml health before running roles | `/aai-check-state` | `--prompt-file .aai/SKILL_CHECK_STATE.prompt.md` |
| 2 | aai-intake | Route new work to the correct intake form | `/aai-intake` | `--prompt-file .aai/SKILL_INTAKE.prompt.md` |
| 3 | aai-loop | Run autonomous Planning-Implementation-Validation cycles | `/aai-loop` | `--prompt-file .aai/SKILL_LOOP.prompt.md` |
| 4 | aai-hitl | Resolve human-in-the-loop pauses and record decisions | `/aai-hitl` | `--prompt-file .aai/SKILL_HITL.prompt.md` |
| 5 | aai-bootstrap | Detect project architecture and generate dynamic skills | `/aai-bootstrap` | `--prompt-file .aai/SKILL_BOOTSTRAP.prompt.md` |
| 6 | aai-validate-report | Generate validation report with screenshots | `/aai-validate-report` | `--prompt-file .aai/SKILL_VALIDATE_REPORT.prompt.md` |
| 7 | aai-canonicalize | Migrate legacy paths and consolidate AAI layout | `/aai-canonicalize` | `--prompt-file .aai/SKILL_CANONICALIZE.prompt.md` |
| 8 | aai-share | Publish Markdown reports to Cloudflare Pages | `/aai-share` | `--prompt-file .aai/SKILL_SHARE.prompt.md` |
| 9 | aai-tdd | Enforced RED-GREEN-REFACTOR test-driven development | `/aai-tdd` | `--prompt-file .aai/SKILL_TDD.prompt.md` |
| 10 | aai-worktree | Manage git worktrees for parallel development | `/aai-worktree` | `--prompt-file .aai/SKILL_WORKTREE.prompt.md` |
| 11 | aai-flush | Flush metrics from STATE.yaml to METRICS.jsonl and clean up | `/aai-flush` | `--prompt-file .aai/SKILL_FLUSH.prompt.md` |

## Skills in Detail

### aai-check-state

Validates `docs/ai/STATE.yaml` for structural correctness before any role runs.
Use when you suspect state corruption or before starting a new work session.

```bash
# Claude
/aai-check-state

# Codex
codex --prompt-file .aai/SKILL_CHECK_STATE.prompt.md
```

### aai-intake

Routes new work to the correct intake form (PRD, Change, Issue, Hotfix, TechDebt, Research, RFC, Release).
Asks minimal questions to classify the request and produce a structured document.

```bash
# Claude
/aai-intake

# Codex
codex --prompt-file .aai/SKILL_INTAKE.prompt.md
```

### aai-loop

Runs autonomous Planning -> Implementation -> Validation -> Remediation cycles.
Continues until a stop condition is met: `project_status=paused`, `human_input.required=true`, or `last_validation.status=pass`.

```bash
# Claude
/aai-loop

# Codex
codex --prompt-file .aai/SKILL_LOOP.prompt.md
```

### aai-hitl

Resolves human-in-the-loop pauses. Reads the blocking question from STATE.yaml, surfaces it to the human, records the decision in `docs/decisions/DECISION-*.md` and `docs/ai/decisions.jsonl`, then unblocks STATE.yaml.

```bash
# Claude
/aai-hitl

# Codex
codex --prompt-file .aai/SKILL_HITL.prompt.md
```

### aai-bootstrap

Detects project architecture (package manager, test frameworks, build tools, CI/CD) and generates optimized dynamic skills in `.claude/skills/`. Also refreshes cross-agent discovery indexes for Codex and Gemini.

```bash
# Claude
/aai-bootstrap

# Codex
codex --prompt-file .aai/SKILL_BOOTSTRAP.prompt.md
```

**Generated skills** (examples): `aai-test-e2e`, `aai-test-unit`, `aai-build`, `aai-lint`, `aai-deploy`.

### aai-validate-report

Generates a validation report with screenshots and executable evidence. Produces a Markdown report suitable for sharing.

```bash
# Claude
/aai-validate-report

# Codex
codex --prompt-file .aai/SKILL_VALIDATE_REPORT.prompt.md
```

### aai-canonicalize

Migrates legacy AAI content (old directory layouts, moved files) into the canonical `.aai/` structure. Uses the canonicalization script to move files and verify the result.

```bash
# Claude
/aai-canonicalize

# Codex
codex --prompt-file .aai/SKILL_CANONICALIZE.prompt.md
```

### aai-share

Publishes Markdown reports (with embedded images) to Cloudflare Pages. Returns a public shareable URL. Useful for sharing validation reports, decisions, or documentation.

```bash
# Claude
/aai-share docs/ai/reports/VALIDATION_REPORT.md

# Codex
codex --prompt-file .aai/SKILL_SHARE.prompt.md
```

**Prerequisites:**
- Cloudflare account with Pages enabled
- Wrangler CLI installed and authenticated (`npx wrangler whoami`)

**First-time setup:**

```bash
# 1. Create free Cloudflare account at https://dash.cloudflare.com/sign-up

# 2. Install Wrangler CLI
npm install -g wrangler

# 3. Authenticate (opens browser)
wrangler login

# 4. Verify
npx wrangler whoami

# 5. Create Pages project
wrangler pages project create aai-reports
```

**Features:**
- Automatic Markdown to HTML conversion via `share-convert.mjs` (zero dependencies)
- Image support (copies referenced assets to publish dir)
- Per-project branch isolation (repo name → `<repo>.aai-reports.pages.dev`)
- Free hosting on Cloudflare Pages (unlimited sites, 500 builds/month)
- Publishing records saved to `docs/ai/published/history.jsonl`

### aai-tdd

Enforced RED-GREEN-REFACTOR test-driven development cycle with evidence capture at each phase.

```bash
# Claude
/aai-tdd

# Codex
codex --prompt-file .aai/SKILL_TDD.prompt.md
```

**Phases:**
1. **RED** — Write a failing test, capture evidence to `docs/ai/tdd/red-*.log`
2. **GREEN** — Minimal implementation to pass the test, capture evidence
3. **REFACTOR** — Improve code quality without changing behavior, capture evidence

**Prerequisites:** `STATE.yaml` must have `current_focus` and `active_work_items` set.

Inspired by the [Superpowers framework](https://github.com/obra/superpowers).

### aai-flush

Flushes completed work item metrics from `docs/ai/STATE.yaml` into the append-only `docs/ai/METRICS.jsonl` ledger and cleans up stale state. Normally triggered automatically by the loop after a PASS validation, but use this skill manually when:
- The loop exited before completing the flush
- You validated manually outside the loop
- STATE.yaml has stale metrics or done work items that need cleanup

```bash
# Claude
/aai-flush

# Codex
codex --prompt-file .aai/SKILL_FLUSH.prompt.md
```

### aai-worktree

Manages git worktrees for parallel isolated development. Avoids branch-switching overhead when working on multiple tasks simultaneously.

```bash
# Claude
/aai-worktree setup <task-name>
/aai-worktree switch <task-name>
/aai-worktree list
/aai-worktree cleanup <task-name>
/aai-worktree sync <task-name>

# Codex
codex --prompt-file .aai/SKILL_WORKTREE.prompt.md
```

**Commands:**
- `setup` — Create new worktree with AAI state initialized
- `switch` — Move between existing worktrees
- `list` — Show all active worktrees
- `cleanup` — Remove completed worktree, archive STATE.yaml
- `sync` — Rebase worktree on base branch

## Agent-Specific Invocation

| Agent | How to invoke skills |
|-------|---------------------|
| **Claude** | Use slash commands directly: `/aai-bootstrap`, `/aai-tdd`, etc. |
| **Codex** | Pass prompt files: `codex --prompt-file .aai/SKILL_*.prompt.md` |
| **Gemini** | Pass prompt files: `gemini --prompt-file .aai/SKILL_*.prompt.md` |
| **Copilot** | Reference the prompt file in chat: `Follow .aai/SKILL_*.prompt.md` |

## Project-Specific Skills

After running `/aai-bootstrap`, additional skills are generated based on your project's architecture.
These live in `.claude/skills/` and use the `aai-` prefix (e.g., `aai-test-e2e`, `aai-build`).

Dynamic skill indexes are written to:
- `.codex/skills.local/README.md`
- `.gemini/skills.local/README.md`

## Typical Workflow

```
/aai-intake          # Start new work
/aai-loop            # Run autonomous cycles
/aai-hitl            # Resolve human decision (if loop pauses)
/aai-validate-report # Generate evidence report
/aai-flush           # Flush metrics & clean state (if loop didn't)
/aai-share report.md # Share report publicly
```
