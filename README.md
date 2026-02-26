# AI Operating System (Canonical)

This repository contains a reusable, low-friction AI Operating System: a single workflow definition, semantic roles, canonical prompts, and templates that help humans and AI agents coordinate with traceability and evidence.


## Pushing AI-OS layer into a target project

Run the sync script **from this repository** and pass the path to the target project.
The script resolves its own source root automatically — no need to copy it to the target first.

### Bash / Git-Bash
```bash
# From this ai-os repo:
./scripts/ai-os-sync.sh ../maty-ai

# Then in the target project:
cd ../maty-ai
git status
git diff
git add ai docs AGENTS.md PLAYBOOK.md CLAUDE.md scripts .claude/skills .github/copilot-instructions.md
git commit -m "Update AI-OS layer"
```

### PowerShell
```powershell
# From this ai-os repo:
.\scripts\ai-os-sync.ps1 -TargetRoot ..\maty-ai

# Then in the target project:
cd ..\maty-ai
git status
git diff
git add ai docs AGENTS.md PLAYBOOK.md CLAUDE.md scripts .claude/skills .github/copilot-instructions.md
git commit -m "Update AI-OS layer"
```

- Sync scope includes `ai/**`, `.claude/skills/**`, `.github/copilot-instructions.md`, `docs/workflow`, `docs/roles`, `docs/templates`, `docs/knowledge`, `docs/ai`, and root shims.
- For `.claude/skills/**`, template entries are updated, while target-only local skills are preserved.
- Runtime files in target `docs/ai` are preserved (not overwritten) if they already exist: `STATE.yaml`, `METRICS.jsonl`, `LOOP_TICKS.jsonl`, `decisions.jsonl`.
- It intentionally does **not** overwrite project docs under `docs/requirements`, `docs/specs`, `docs/decisions`, `docs/releases`, or `docs/issues`.

## What this repository is for
- Standardizing agent workflows (Planning → Implementation → Validation → Remediation).
- Capturing requirements, specs, decisions, and knowledge with clear separation.
- Running low-token intake prompts to start work consistently.

## Assumptions about the environment
- POSIX shell (bash/zsh) and Git available.
- You can run CLI commands and edit Markdown.
- AI agents have read access to AGENTS.md and prompt files.

## Directory overview
```
.
├── AGENTS.md
├── PLAYBOOK.md
├── CLAUDE.md
├── README.md
├── ai/
├── docs/
│   ├── workflow/
│   ├── roles/
│   ├── knowledge/
│   ├── templates/
│   ├── issues/
│   ├── specs/
│   ├── rfc/
│   └── releases/
└── .github/
    └── copilot-instructions.md
```

## How to use this AI Operating System (step-by-step)
### Installation
1) Clone or copy this repository into your project.
2) Ensure canonical files are present (see AGENTS.md).

### Bootstrap
```bash
cat ai/BOOTSTRAP.prompt.md
```
Use an AI agent to follow the instructions when normalizing an existing repo.

### Orchestration
```bash
cat ai/ORCHESTRATION.prompt.md
```
Parallel and HITL variants:
```bash
cat ai/ORCHESTRATION_PARALLEL.prompt.md
cat ai/ORCHESTRATION_HITL.prompt.md
```

### Planning
```bash
cat ai/PLANNING.prompt.md
```

### Implementation
```bash
cat ai/IMPLEMENTATION.prompt.md
```

### Validation
```bash
cat ai/VALIDATION.prompt.md
```

### Remediation
```bash
cat ai/REMEDIATION.prompt.md
```

### Reverse analysis
```bash
cat ai/REVERSE_ANALYSIS_DASH_FASTAPI_CELERY.prompt.md
cat ai/REVERSE_ANALYSIS_GENERIC.prompt.md
```

### Skills (session-scoped, multi-step)

Skills are higher-level prompts that compose multiple steps within one agent session.
Use them instead of manually chaining individual role prompts.

| Skill | Command | Replaces |
| --- | --- | --- |
| Autonomous loop | `cat ai/SKILL_LOOP.prompt.md` | `autonomous-loop.sh` / `.ps1` |
| Intake router | `cat ai/SKILL_INTAKE.prompt.md` | manually picking `INTAKE_*.prompt.md` |
| Human-in-the-loop resolver | `cat ai/SKILL_HITL.prompt.md` | manual STATE.yaml editing after human pause |
| State health check | `cat ai/SKILL_CHECK_STATE.prompt.md` | manual STATE.yaml inspection |

Typical skill flow:

```bash
# Start new work without knowing the intake type:
cat ai/SKILL_INTAKE.prompt.md

# Run full autonomous loop inside one agent session:
cat ai/SKILL_LOOP.prompt.md

# Loop paused for human decision? Resolve and resume:
cat ai/SKILL_HITL.prompt.md

# Suspect state corruption before a role runs:
cat ai/SKILL_CHECK_STATE.prompt.md
```

## When to run each action
- Use `ai/ORCHESTRATION.prompt.md` first to choose the next role from repository state.
- Use `ai/PLANNING.prompt.md` when orchestration dispatches Planning, or when requirement-to-spec mapping/measurability is missing.
- Use `ai/IMPLEMENTATION.prompt.md` when orchestration dispatches Implementation and the target spec is frozen.
- Use `ai/TECH_EXTRACT.prompt.md` when `docs/TECHNOLOGY.md` is missing or needs first-time creation.
- Use `ai/TECH_UPDATE_DIFF.prompt.md` when `docs/TECHNOLOGY.md` already exists and repo changes may have altered the technology contract.
- Use `ai/VALIDATION.prompt.md` after implementation changes to produce executable evidence and PASS/FAIL.
- Use `ai/REMEDIATION.prompt.md` only after a validation FAIL.
- Use `ai/BOOTSTRAP.prompt.md` only when normalizing a non-canonical repository structure.

## Low-token intake (forms)
Use these entrypoints for all new work (see AGENTS.md for the authoritative list):
```bash
cat ai/INTAKE_PRD.prompt.md
cat ai/INTAKE_CHANGE.prompt.md
cat ai/INTAKE_ISSUE.prompt.md
cat ai/INTAKE_RESEARCH.prompt.md
cat ai/INTAKE_HOTFIX.prompt.md
cat ai/INTAKE_TECHDEBT.prompt.md
cat ai/INTAKE_RFC.prompt.md
cat ai/INTAKE_RELEASE.prompt.md
```

## Intake language and efficiency policy
- You can provide intake answers in your preferred language.
- The assistant should ask follow-up questions in your language.
- Saved repository documents must always be written in English.
- Intake should stay token-light: ask only high-impact missing fields.
- If minor details are missing, continue with explicit assumptions.

## Intake router (when to use what)
- `INTAKE_PRD`: New feature/product requirement with measurable acceptance criteria.
- `INTAKE_CHANGE`: Small enhancement or behavior change with limited scope.
- `INTAKE_ISSUE`: Bug report with reproducible steps.
- `INTAKE_HOTFIX`: Urgent production issue requiring severity + rollback plan.
- `INTAKE_TECHDEBT`: Refactor/maintainability/performance debt item.
- `INTAKE_RESEARCH`: Spike/research question with timebox and deliverables.
- `INTAKE_RFC`: Proposal where options/tradeoffs and approvers are needed.
- `INTAKE_RELEASE`: Release/hotfix planning with executable gates and sign-offs.

Template mapping:
- `INTAKE_ISSUE` and `INTAKE_HOTFIX` -> `docs/templates/ISSUE_TEMPLATE.md`
- `INTAKE_CHANGE` -> `docs/templates/CHANGE_TEMPLATE.md`
- `INTAKE_TECHDEBT` -> `docs/templates/TECHDEBT_TEMPLATE.md`
- `INTAKE_PRD` -> `docs/templates/REQUIREMENT_TEMPLATE.md`
- `INTAKE_RFC` -> `docs/templates/RFC_TEMPLATE.md`
- `INTAKE_RELEASE` -> `docs/templates/RELEASE_TEMPLATE.md`

## Minimal input examples (user input can be Czech; saved doc stays English)
- `INTAKE_CHANGE` example:
  - "V detailu objednavky chci zobrazit i interni kod skladu, kvuli podpore."
- `INTAKE_ISSUE` example:
  - "Pri prihlaseni pres SSO obcas spadne callback s 500; reprodukce na stagingu."
- `INTAKE_PRD` example:
  - "Chci export faktur do CSV kvuli auditu. AC: export do 5s pro 10k radku."
- `INTAKE_RFC` example:
  - "Potrebujeme rozhodnout mezi RabbitMQ a SQS pro asynchronni processing."
- `INTAKE_RELEASE` example:
  - "Release 1.12.0 pristi stredu, scope PRD-014 + SPEC-022, gate: pytest -q."

## Fast operating pattern (more autonomy, fewer tokens)
1) Start with one intake prompt and provide a compact first answer (2-6 lines).
2) Let the assistant ask only missing high-impact questions.
3) Accept assumptions for low-risk details to avoid long Q&A loops.
4) Run `ai/ORCHESTRATION.prompt.md` immediately after intake output is saved.
5) Use `ai/ORCHESTRATION_HITL.prompt.md` only for explicit human decisions.

## Common flows
- **New feature:** INTAKE_PRD → ORCHESTRATION → role cycles → PASS.
- **Small change:** INTAKE_CHANGE → ORCHESTRATION.
- **Issue:** INTAKE_ISSUE → HITL or ORCHESTRATION.
- **Research:** INTAKE_RESEARCH → ORCHESTRATION.
- **Hotfix:** INTAKE_HOTFIX → HITL if risk ≥ medium.
- **Tech debt:** INTAKE_TECHDEBT → ORCHESTRATION.
- **RFC:** INTAKE_RFC → HITL if a decision is required.
- **Release:** INTAKE_RELEASE → Validation → Human Go/No-go.

## Runtime state tracking
- `docs/ai/STATE.yaml` is the runtime state file used by orchestration/autonomous execution.
- The vendored baseline is intentionally empty (`current_focus: none`, `active_work_items: []`).
- In normal operation, orchestration populates/updates it automatically (no manual editing required).
- Populate/update it only when a loop run or role action actually starts.
- Loop semantics and update rules are defined in `docs/ai/AUTONOMOUS_LOOP.md`.

Runtime append-only logs (JSONL — one JSON object per line, never rewrite):
- `docs/ai/LOOP_TICKS.jsonl` — external timing for each loop tick (written by loop runner scripts).
- `docs/ai/METRICS.jsonl` — completed work item economics (flushed by `ai/METRICS_FLUSH.prompt.md`).
- `docs/ai/decisions.jsonl` — HITL decisions log (written by `ai/SKILL_HITL.prompt.md`).

## Autonomous loop runners (no manual STATE editing)
Use the helper scripts to run repeated autonomous ticks until a stop condition:
- `project_status=paused`
- `human_input.required=true`
- `last_validation.status=pass`

`TickCommand` must perform one autonomous cycle:
1) follow `ai/ORCHESTRATION.prompt.md`,
2) execute the dispatched role for the current scope,
3) write back `docs/ai/STATE.yaml`,
4) stop.

### PowerShell
```powershell
.\scripts\autonomous-loop.ps1 `
  -TickCommand '<your-agent-one-tick-command>' `
  -MaxIterations 20 `
  -SleepSeconds 1 `
  -AutoInitState
```

Examples (PowerShell):
```powershell
# Codex CLI
.\scripts\autonomous-loop.ps1 `
  -TickCommand 'codex --prompt-file ai/ORCHESTRATION.prompt.md' `
  -MaxIterations 20 `
  -SleepSeconds 1 `
  -AutoInitState

# Claude CLI
.\scripts\autonomous-loop.ps1 `
  -TickCommand 'claude --prompt-file ai/ORCHESTRATION.prompt.md' `
  -MaxIterations 20 `
  -SleepSeconds 1 `
  -AutoInitState

# Gemini CLI
.\scripts\autonomous-loop.ps1 `
  -TickCommand 'gemini --prompt-file ai/ORCHESTRATION.prompt.md' `
  -MaxIterations 20 `
  -SleepSeconds 1 `
  -AutoInitState
```

`-TickCommand` expects an executable command string.  
`ORCHESTRATION,prompt` is not valid by itself.
CLI flags differ by version; if needed, replace `--prompt-file ...` with your agent's equivalent option.

### Bash
```bash
./scripts/autonomous-loop.sh \
  --tick-command "<your-agent-one-tick-command>" \
  --max-iterations 20 \
  --sleep-seconds 1 \
  --auto-init-state
```

Tip:
- Use `-DryRun` (PowerShell) or `--dry-run` (Bash) to verify loop behavior without executing the agent command.

## How to write/maintain specs, docs, and prompts
- Use templates in `docs/templates/`.
- Keep workflow canonical in `docs/workflow/WORKFLOW.md`.
- Store verified facts in `docs/knowledge/FACTS.md` and UI mappings in `docs/knowledge/UI_MAP.md`.
- Store confirmed reusable patterns in `docs/knowledge/PATTERNS.md` (project-specific).
- Universal cross-project patterns live in `docs/knowledge/PATTERNS_UNIVERSAL.md` (sync-managed, read-only).
- Keep prompts in `ai/*.prompt.md` and avoid duplicates elsewhere.
- Follow engineering principles from `AGENTS.md`: DRY, SOLID, KISS, YAGNI, separation of concerns, testability, explicit error handling, and contract compatibility.

## How to extend this for a new project
1) Copy `ai/` and `docs/` into your repo.
2) Generate `docs/TECHNOLOGY.md` via `ai/TECH_EXTRACT.prompt.md`.
3) Use intake prompts to create PRDs, issues, specs, or RFCs.
4) Run orchestration to dispatch the next role.

## Troubleshooting / FAQ
**Q: Can I add another workflow doc?**
A: No. Only `docs/workflow/WORKFLOW.md` is canonical.

**Q: Where do I list technologies?**
A: `docs/TECHNOLOGY.md` (generated by the tech prompts).

## Canonical references
- AGENTS: `AGENTS.md`
- PLAYBOOK: `PLAYBOOK.md`
- Claude shim: `CLAUDE.md`
- Copilot instructions: `.github/copilot-instructions.md`

## Knowledge management

### Extracting facts and patterns from documents
```bash
cat ai/DOCS_COMPRESS_TO_FACTS.prompt.md
```
Extracts verified facts → `docs/knowledge/FACTS.md` and confirmed patterns → `docs/knowledge/PATTERNS.md`.
Run after reverse analysis, architecture reviews, or any document that contains verifiable conclusions.

### Pattern loading (automatic in Planning and Implementation)
Agents read only the INDEX table first, then load full text of patterns matching the current task tags.
Project patterns: `docs/knowledge/PATTERNS.md` · Universal patterns: `docs/knowledge/PATTERNS_UNIVERSAL.md`

### Periodic memory hygiene
```bash
cat ai/MEMORY_REVIEW.prompt.md
```
Removes stale facts, splits oversized patterns, flags UNVERIFIED entries (unused >90 days), suggests promotions to PATTERNS_UNIVERSAL.md.

## Notes on docs/TECHNOLOGY.md, knowledge, and archives
- `docs/TECHNOLOGY.md` is the authoritative technology contract.
- Living knowledge stores: `docs/knowledge/FACTS.md`, `docs/knowledge/PATTERNS.md`, `docs/knowledge/PATTERNS_UNIVERSAL.md`, `docs/knowledge/UI_MAP.md`.
- `docs/archive/analysis/` is immutable history.
