# AAI — autonomous AI development that has to prove it

**An AI agent that plans, implements, tests, validates and reviews your feature in an autonomous loop — and cannot mark anything "done" unless a machine-checked gate says the evidence actually exists. You keep the merge button.**

AAI is a vendorable workflow layer for AI coding agents (Claude Code, Codex, Gemini). One command drops it into any repository and turns "the agent said it works" into a disciplined pipeline: intake → frozen spec with measurable acceptance criteria → TDD with RED-proofed tests → **independent validation in a separate context and a different model** → adversarial code review → gated closeout with telemetry. Every claim leaves a trail; every "done" is challenged before it counts.

## Why it is different

- **"Done" is gated, not declared.** `docs-audit --gate` refuses to close a spec whose acceptance table has a non-terminal row, an evidence-free "done", or an invalid sign-off. An opt-in pre-commit hook blocks the commit itself — and it gates the *staged* content, not what happens to be on disk.
- **Validation is genuinely independent.** A fresh subagent with a clean context and a different model than the implementer — because self-evaluation rubber-stamps. In this repo's own history the independent pass repeatedly caught real bugs that a fully green test suite had hidden.
- **Claims are cross-checked.** A test must first fail (RED-proof) before its pass means anything; a "code-review" sign-off without a recorded review artifact is flagged as `review-claim-unbacked`; docs with almost-right structure trigger warnings instead of silent misreads.
- **The human stays the operator.** Human-in-the-loop gates for scope and isolation decisions, and a PR ceremony (`/aai-pr`) with a hard rule: the agent never merges. These guardrails run on this repository itself — they have even stopped their own author mid-release until close telemetry existed.
- **Engineering hygiene built in.** Transactional runtime state (`state.mjs` — atomic writes, strict flags, no silent typo-drops), leak-safe test execution (no orphaned process trees), drift-aware docs with body linting, append-only audit events, per-change metrics.
- **Vendorable and low-friction.** Ships as prompts + small Node/shell tools, no framework lock-in; wrappers for `.claude`, `.codex` and `.gemini`; backward-compatible updates via `/aai-update`.

## Quick start

```bash
# 1. Install into your project (bash; PowerShell variant below)
curl -fsSL https://raw.githubusercontent.com/goodwind-cz/aai/main/install.sh | bash

# 2. Describe work in one sentence — AAI routes it to the right intake form
/aai-intake "Add password reset via email"

# 3. Run the autonomous loop: Planning → Implementation → Validation → Review
/aai-loop

# 4. Open the PR (scope-only staging, changelog entry, never merges)
/aai-pr
```

Read next: **[User Guide](docs/USER_GUIDE.md)** (how to use every skill) · **[.aai/AGENTS.md](.aai/AGENTS.md)** (agent-side entry point) · **[.aai/PLAYBOOK.md](.aai/PLAYBOOK.md)** (human playbook) · **[CHANGELOG](CHANGELOG.md)** · **[latest release](https://github.com/goodwind-cz/aai/releases/latest)** · canonical workflow in [.aai/workflow/WORKFLOW.md](.aai/workflow/WORKFLOW.md).

## Install AAI into the current project

From the target project directory, run:

PowerShell:

```powershell
irm https://raw.githubusercontent.com/goodwind-cz/aai/main/install.ps1 | iex
```

Bash:

```bash
curl -fsSL https://raw.githubusercontent.com/goodwind-cz/aai/main/install.sh | bash
```

This downloads the canonical AAI repository and runs the matching `.aai/scripts/aai-sync.*` script into the current directory.

Safer review-first variant:

PowerShell:

```powershell
irm https://raw.githubusercontent.com/goodwind-cz/aai/main/install.ps1 -OutFile install-aai.ps1
Get-Content .\install-aai.ps1
powershell -ExecutionPolicy Bypass -File .\install-aai.ps1
```

Bash:

```bash
curl -fsSLo install-aai.sh https://raw.githubusercontent.com/goodwind-cz/aai/main/install.sh
less install-aai.sh
bash install-aai.sh
```

Optional environment overrides for the one-liner:

PowerShell:

```powershell
$env:AAI_REF = "main"
$env:AAI_TARGET_ROOT = "C:\path\to\your-project"
irm https://raw.githubusercontent.com/goodwind-cz/aai/main/install.ps1 | iex
Remove-Item Env:\AAI_REF, Env:\AAI_TARGET_ROOT -ErrorAction SilentlyContinue
```

Bash:

```bash
curl -fsSL https://raw.githubusercontent.com/goodwind-cz/aai/main/install.sh |
  AAI_REF=main AAI_TARGET_ROOT=/path/to/your-project bash
```

Or run the installer after cloning/downloading this repository:

PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -TargetRoot C:\path\to\your-project
```

Bash:

```bash
bash ./install.sh --target-root /path/to/your-project
```

After install, review the changes and bootstrap the target project:

```bash
git status
git diff
/aai-bootstrap
/aai-doctor
```

## Pushing AAI layer into a target project

Run the sync script **from this repository** and pass the path to the target project.
The script resolves its own source root automatically — no need to copy it to the target first.

### Bash / Git-Bash
```bash
# From this aai repo:
./.aai/scripts/aai-sync.sh ../your-project

# Then in the target project:
cd ../your-project
git status
git diff
git add .aai docs CLAUDE.md CODEX.md GEMINI.md README_AAI.md SKILLS.md .github/copilot-instructions.md .gitignore
git commit -m "Update AAI layer"
```

### PowerShell
```powershell
# From this aai repo:
.\.aai\scripts\aai-sync.ps1 -TargetRoot ..\your-project

# Then in the target project:
cd ..\your-project
git status
git diff
git add .aai docs CLAUDE.md CODEX.md GEMINI.md README_AAI.md SKILLS.md .github/copilot-instructions.md .gitignore
git commit -m "Update AAI layer"
```

- Sync scope includes `.aai/**`, `.claude/skills/**`, `.codex/skills/**`, `.gemini/skills/**`, `.github/copilot-instructions.md`, `docs/knowledge`, and root shims (`CLAUDE.md`, `CODEX.md`, `GEMINI.md`, `README_AAI.md`, `SKILLS.md`).
- Session-start hooks are synced under `hooks/`, including `hooks/session-start.sh` for POSIX shells and `hooks/session-start.ps1` plus `hooks/hooks.windows.json` for native Windows PowerShell registration.
- For `.claude/skills/**`, template entries are updated, while target-only local skills are preserved.
- Target `.gitignore` is auto-updated to ignore `.claude/skills/`, `.codex/skills/`, `.codex/skills.local/`, `.gemini/skills/`, and `.gemini/skills.local/` (sync-managed artifacts).
- `.github/copilot-instructions.md` is auto-merged: project-specific content is preserved in `docs/ai/project-overrides/copilot-instructions.project.md` and appended under a dedicated Project Overrides section.
- If other local target content is overwritten, sync creates a local-only advisory in `docs/ai/reports/sync-conflicts-*.md`.
- Reports under `docs/ai/reports/` are runtime artifacts and should not be committed; durable conclusions must be promoted into project-owned docs.
- Dynamic project skills should use unique `aai-*` names under `.claude/skills/` so they stay target-only and preserved on sync.
- Runtime files in target `docs/ai` are preserved (not overwritten) if they already exist: `STATE.yaml`, `METRICS.jsonl`, `LOOP_TICKS.jsonl`, `EVENTS.jsonl`, `decisions.jsonl`.
- `docs/ai/STATE.yaml` and `docs/ai/LOOP_TICKS.jsonl` are auto-added to the target `.gitignore` (RFC-0001: per-developer local). Run `bash .aai/scripts/migrate-state-to-local.sh` in the target project to untrack any previously committed copy.
- Missing `docs/TECHNOLOGY.md` is seeded from `.aai/templates/TECHNOLOGY_TEMPLATE.md` and then becomes project-owned.
- It intentionally does **not** overwrite project docs under `docs/requirements`, `docs/specs`, `docs/decisions`, `docs/releases`, `docs/issues`, `docs/rfc`, or `docs/project-sessions`.

## Orientation

### The loop

Every scope moves through six phases, defined canonically in
[.aai/workflow/WORKFLOW.md](.aai/workflow/WORKFLOW.md):
**Planning → Implementation preparation → Implementation → Validation → Code Review → Remediation**.
Implementation preparation is the worktree gate — when Planning recommends
isolation, the agent must ask you before creating a worktree (or accept an
explicit inline override). Validation is performed by an independent subagent
with a clean context and a different model, and Code Review is a separate
adversarial pass; a FAIL from either routes the scope into Remediation and back
through independent re-validation. A finished scope ends with the `/aai-pr`
ceremony opening a pull request — the agent never merges; merging is your action.

### Repository map

```
.aai/                       AAI system: canonical prompts (intake, roles, skills,
                            reverse analysis), scripts/, workflow/WORKFLOW.md,
                            templates/, system/ docs, knowledge/ (universal patterns)
.claude/ .codex/ .gemini/   Per-agent skill wrappers (sync-managed)
hooks/                      Session-start hooks (POSIX, PowerShell, Windows registration)
tests/                      Skill tests (tests/skills/), self-hosting smoke tests,
                            disposable sync fixture (tests/fixtures/target-project/)
docs/requirements|specs|rfc|issues|releases   Tracked work documents (intake output)
docs/knowledge/             Project facts, patterns, UI map, LEARNED.md
docs/roles|templates|workflow                 Project-doc mount points (seeded per project)
docs/ai/                    Runtime layer: state, append-only logs, reports, reviews
CHANGELOG.md                Release-facing change history
install.sh / install.ps1    One-line installer entrypoints
```

### Runtime state and append-only logs

`docs/ai/STATE.yaml` is the runtime state file — written transactionally by the
loop via `.aai/scripts/state.mjs`, never hand-edited, per-developer local and
gitignored (RFC-0001). The JSONL logs are append-only (one JSON object per
line, never rewritten):

- `docs/ai/LOOP_TICKS.jsonl` — external timing per loop tick, written by the loop runner scripts. Per-developer local (gitignored).
- `docs/ai/EVENTS.jsonl` — audit log of AC status transitions and doc lifecycle changes, appended via `.aai/scripts/append-event.mjs`. Shared, committed.
- `docs/ai/METRICS.jsonl` — completed work-item economics, flushed by `.aai/METRICS_FLUSH.prompt.md`. Shared, committed.
- `docs/ai/decisions.jsonl` — human-in-the-loop decisions, written by `.aai/SKILL_HITL.prompt.md`. Shared, committed.

### Intake language policy

- You can provide intake answers in your preferred language; the assistant asks follow-ups in that language.
- Saved repository documents are always written in English.
- Intake stays token-light: only high-impact missing fields are asked; minor gaps proceed as explicit assumptions.

Minimal input examples (Czech input is fine; the saved doc stays English):

- Change: "V detailu objednavky chci zobrazit i interni kod skladu, kvuli podpore."
- Issue: "Pri prihlaseni pres SSO obcas spadne callback s 500; reprodukce na stagingu."
- Feature (PRD): "Chci export faktur do CSV kvuli auditu. AC: export do 5s pro 10k radku."
- RFC: "Potrebujeme rozhodnout mezi RabbitMQ a SQS pro asynchronni processing."
- Release: "Release 1.12.0 pristi stredu, scope PRD-014 + SPEC-022, gate: pytest -q."

## Where everything else lives

- [docs/USER_GUIDE.md](docs/USER_GUIDE.md) — the manual: the full skills catalog, step-by-step workflows, loop runner reference, self-hosting contract, troubleshooting and FAQ.
- [.aai/AGENTS.md](.aai/AGENTS.md) — agent-side entry point and the authoritative list of canonical prompts and sources.
- [.aai/workflow/WORKFLOW.md](.aai/workflow/WORKFLOW.md) — the only authoritative workflow definition (phases, gates, stop conditions).
- [.aai/PLAYBOOK.md](.aai/PLAYBOOK.md) — the human operating playbook.
- [docs/TECHNOLOGY.md](docs/TECHNOLOGY.md) — the authoritative technology contract.
- [docs/knowledge/LEARNED.md](docs/knowledge/LEARNED.md) — project-specific learned rules.
- [CHANGELOG.md](CHANGELOG.md) — what changed, release by release.
- [docs/INDEX.md](docs/INDEX.md) — auto-generated catalog of all tracked docs (status, progress, refs).
