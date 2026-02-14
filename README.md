# AI Operating System (Canonical)

This repository contains a reusable, low-friction AI Operating System: a single workflow definition, semantic roles, canonical prompts, and templates that help humans and AI agents coordinate with traceability and evidence.


## Updating AI-OS from template (worktree/vendor sync)

Sync AI-OS vendor files from an external template worktree into this repository.

### Bash / Git-Bash
```bash
./scripts/ai-os-sync.sh ../ai-os-template-wt
git status
git diff
git add ai docs AGENTS.md PLAYBOOK.md CLAUDE.md .github/copilot-instructions.md
git commit -m "Update AI-OS layer"
```

### PowerShell
```powershell
.\scripts\ai-os-sync.ps1 -SourceRoot ..\ai-os-template-wt
git status
git diff
git add ai docs AGENTS.md PLAYBOOK.md CLAUDE.md .github/copilot-instructions.md
git commit -m "Update AI-OS layer"
```

- Sync scope includes `ai/**`, `docs/workflow`, `docs/roles`, `docs/templates`, `docs/knowledge`, `docs/ai`, and root shims.
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

## Notes on docs/TECHNOLOGY.md, knowledge, and archives
- `docs/TECHNOLOGY.md` is the authoritative technology contract.
- `docs/knowledge/FACTS.md` and `docs/knowledge/UI_MAP.md` are the only living knowledge stores.
- `docs/archive/analysis/` is immutable history.
