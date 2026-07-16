# AAI Skills Reference

This document describes all universal skills included in the AAI framework.
Skills are session-scoped, multi-step prompts that compose workflow actions into reusable commands.

## Quick Reference

The table lists the full set of universal skills; rows are unnumbered on purpose
so the list cannot drift from a hard-coded count. The source of truth is the
set of wrapper directories in `.claude/skills/`.

| Skill | Description | Claude | Codex / Gemini |
|-------|-------------|--------|----------------|
| aai-check-state | Validate STATE.yaml health before running roles | `/aai-check-state` | `--prompt-file .aai/SKILL_CHECK_STATE.prompt.md` |
| aai-intake | Route new work to the correct intake form | `/aai-intake` | `--prompt-file .aai/SKILL_INTAKE.prompt.md` |
| aai-loop | Run autonomous Planning-Implementation-Validation cycles | `/aai-loop` | `--prompt-file .aai/SKILL_LOOP.prompt.md` |
| aai-hitl | Resolve human-in-the-loop pauses and record decisions | `/aai-hitl` | `--prompt-file .aai/SKILL_HITL.prompt.md` |
| aai-bootstrap | Detect project architecture and generate dynamic skills | `/aai-bootstrap` | `--prompt-file .aai/SKILL_BOOTSTRAP.prompt.md` |
| aai-update | Re-sync vendored AAI layer from canonical git `main` | `/aai-update` | `--prompt-file .aai/SKILL_UPDATE.prompt.md` |
| aai-validate-report | Generate validation report with screenshots | `/aai-validate-report` | `--prompt-file .aai/SKILL_VALIDATE_REPORT.prompt.md` |
| aai-canonicalize | Migrate legacy paths and consolidate AAI layout | `/aai-canonicalize` | `--prompt-file .aai/SKILL_CANONICALIZE.prompt.md` |
| aai-share | Publish Markdown reports to Cloudflare Pages | `/aai-share` | `--prompt-file .aai/SKILL_SHARE.prompt.md` |
| aai-tdd | Enforced RED-GREEN-REFACTOR test-driven development | `/aai-tdd` | `--prompt-file .aai/SKILL_TDD.prompt.md` |
| aai-worktree | Manage git worktrees for parallel development | `/aai-worktree` | `--prompt-file .aai/SKILL_WORKTREE.prompt.md` |
| aai-flush | Flush metrics from STATE.yaml to METRICS.jsonl and clean up | `/aai-flush` | `--prompt-file .aai/SKILL_FLUSH.prompt.md` |
| aai-test-skills | Run the AAI skill test framework and suites | `/aai-test-skills` | `--prompt-file .aai/SKILL_TEST_SKILLS.prompt.md` |
| aai-docs-hub | Generate documentation hub and skill catalog pages | `/aai-docs-hub` | `--prompt-file .aai/SKILL_DOCS_HUB.prompt.md` |
| aai-decapod | Run compliance advisory workflow with Decapod | `/aai-decapod` | `--prompt-file .aai/SKILL_DECAPOD.prompt.md` |
| aai-auto-trigger | Suggest and auto-trigger relevant skills for context | `/aai-auto-trigger` | `--prompt-file .aai/SKILL_AUTO_TRIGGER.prompt.md` |
| aai-dashboard | Build metrics dashboard artifacts from telemetry | `/aai-dashboard` | `--prompt-file .aai/SKILL_DASHBOARD.prompt.md` |
| aai-code-review | Run AI-assisted code review on PRs/changes | `/aai-code-review` | `--prompt-file .aai/SKILL_CODE_REVIEW.prompt.md` |
| aai-profile | Profile workflows for token/time optimization | `/aai-profile` | `--prompt-file .aai/SKILL_PROFILE.prompt.md` |
| aai-doctor | Environment health check (files, skills, git, knowledge) | `/aai-doctor` | `--prompt-file .aai/SKILL_DOCTOR.prompt.md` |
| aai-replay | Surface relevant past learnings for current context | `/aai-replay` | `--prompt-file .aai/SKILL_REPLAY.prompt.md` |
| aai-session-journal | Create or resume a named human-readable project discussion session | `/aai-session-journal` | `--prompt-file .aai/SKILL_SESSION_JOURNAL.prompt.md` |
| aai-wrap-up | Session wrap-up with learnings capture and next steps | `/aai-wrap-up` | `--prompt-file .aai/SKILL_WRAP_UP.prompt.md` |
| aai-docs-audit | Docs hygiene and drift audit (orphan/false-done/stale) | `/aai-docs-audit` | `--prompt-file .aai/SKILL_DOCS_AUDIT.prompt.md` |
| aai-docs-canon | Consolidate layered docs into a canonical per-domain layer | `/aai-docs-canon` | `--prompt-file .aai/SKILL_DOCS_CANON.prompt.md` |
| aai-test-canon | Consolidate fragmented tests into a canonical per-domain suite | `/aai-test-canon` | `--prompt-file .aai/SKILL_TEST_CANON.prompt.md` |
| aai-pr | Scope-audited commit, push, and PR creation (never merges) | `/aai-pr` | `--prompt-file .aai/SKILL_PR.prompt.md` |
| aai-verify | Verification-before-completion gate (IDENTIFY-RUN-READ-VERIFY-CLAIM) | `/aai-verify` | `--prompt-file .aai/SKILL_VERIFY.prompt.md` |
| aai-debug | Systematic-debugging root-cause gate (READ-REPRODUCE-ISOLATE-FIX-AT-CAUSE) | `/aai-debug` | `--prompt-file .aai/SKILL_DEBUG.prompt.md` |

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

### aai-update

Re-syncs the current project's vendored AAI layer from the `main` branch of the canonical git repository. Supports private upstream repositories by preferring authenticated checkout, reports any sync conflict advisory, and recommends post-update checks such as `/aai-bootstrap`, `/aai-doctor`, and `/aai-test-skills`.

```bash
# Claude
/aai-update
/aai-update --dry-run

# Codex
codex --prompt-file .aai/SKILL_UPDATE.prompt.md
```

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

### aai-doctor

Performs a comprehensive environment health check of the entire AAI project: core files, role prompts, skills, knowledge files, STATE.yaml, telemetry, git status, and pre-compact hook configuration. Broader than `/aai-check-state` which only validates STATE.yaml invariants.

```bash
# Claude
/aai-doctor

# Codex
codex --prompt-file .aai/SKILL_DOCTOR.prompt.md
```

Inspired by [pro-workflow](https://github.com/rohitg00/pro-workflow) `/doctor` command.

### aai-replay

Surfaces relevant past learnings for the current work context. Reads STATE.yaml to determine focus, then searches `docs/knowledge/LEARNED.md`, `docs/knowledge/PATTERNS.md`, `docs/knowledge/FACTS.md`, and `docs/ai/decisions.jsonl` for keyword matches. Shows only relevant results.

```bash
# Claude
/aai-replay                    # Auto-detect context from STATE.yaml
/aai-replay authentication     # Search for specific topic

# Codex
codex --prompt-file .aai/SKILL_REPLAY.prompt.md
```

Inspired by [pro-workflow](https://github.com/rohitg00/pro-workflow) `/replay` command.

### aai-session-journal

Creates or updates a named project discussion journal in `docs/project-sessions/`. This is the durable, agent-neutral place for human-readable rationale, ongoing discussion context, and resume notes in the user's language. It is intentionally separate from runtime state and from formal delivery artifacts.

```bash
# Claude
/aai-session-journal "Authentication redesign"

# Codex
codex --prompt-file .aai/SKILL_SESSION_JOURNAL.prompt.md
```

Use it when:
- you want a named session you can return to later
- multiple agents will work from subsets of information
- you need a human-language trail of why direction changed
- you want continuity that does not depend on vendor chat history

Outputs:
- `docs/project-sessions/INDEX.md`
- `docs/project-sessions/SESSION-<slug>.md`

### aai-wrap-up

Session wrap-up ritual that captures learnings, summarizes accomplishments, proposes new rules for `docs/knowledge/LEARNED.md`, checks for uncommitted work, and prepares context for the next session. Can be auto-triggered when the user says "bye", "done", "hotovo", etc.

```bash
# Claude
/aai-wrap-up

# Codex
codex --prompt-file .aai/SKILL_WRAP_UP.prompt.md
```

Inspired by [pro-workflow](https://github.com/rohitg00/pro-workflow) `/wrap-up` command.

### aai-docs-audit

Docs hygiene and drift audit (RFC-0002). Classifies every governed doc as
orphan, false-done, stale, or clean, and verifies acceptance criteria against
the actual code ("verify <DOC-ID>"). Also provides the offline close gate
(`--gate <DOC-ID>`) and body lint (`--lint-body`, `--lint-body-file`) used by
the pre-commit hook (`close_gate` / `body_lint` config keys, report-only by
default). The audit reports; the operator decides — docs are edited only in
the operator-approved remediation/verify modes.

```bash
# Claude
/aai-docs-audit

# Codex
codex --prompt-file .aai/SKILL_DOCS_AUDIT.prompt.md
```

### aai-docs-canon

Docs canonicalization (RFC-0003). Consolidates layered intake/specs/RFCs into
one canonical, function-categorized doc per domain in `docs/canonical/`,
preserving and back-linking originals in `docs/_archive/`. Two phases:
Phase 1 analyzes and proposes an AI domain map gated by human approval;
Phase 2 auto-synthesizes the canonical docs, archives originals, and reports
drift on re-run.

```bash
# Claude
/aai-docs-canon

# Codex
codex --prompt-file .aai/SKILL_DOCS_CANON.prompt.md
```

### aai-test-canon

Test canonicalization (RFC-0006). Consolidates fragmented per-change/issue
tests into a canonical per-domain layer in `tests/canonical/` (anchored on the
canonical docs domain map), preserving and back-linking originals in
`tests/_archive/`. Phase 1 builds a traceability matrix and coverage-gap
report gated by human approval; Phase 2 consolidates the tests, scaffolds
failing/pending RED stubs for uncovered acceptance criteria (handing off to
`aai-tdd`), and reports drift on re-run.

```bash
# Claude
/aai-test-canon

# Codex
codex --prompt-file .aai/SKILL_TEST_CANON.prompt.md
```

### aai-pr

PR ceremony for a validated, review-passed scope. Derives the scope file-list
from STATE/spec, stages ONLY in-scope paths, audits staged-vs-scope, commits
with project conventions, pushes, and opens the PR via `gh pr create`.
It never merges — merging is an operator action.

```bash
# Claude
/aai-pr

# Codex
codex --prompt-file .aai/SKILL_PR.prompt.md
```

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
/aai-replay          # Surface relevant past learnings
/aai-session-journal # Create or resume named discussion thread
/aai-intake          # Start new work
/aai-loop            # Run autonomous cycles (supports checkpoint_mode=staged)
/aai-hitl            # Resolve human decision (if loop pauses)
/aai-validate-report # Generate evidence report
/aai-flush           # Flush metrics & clean state (if loop didn't)
/aai-share report.md # Share report publicly
/aai-wrap-up         # Capture session learnings
```
