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
```

## When to run each action
- Use `ai/ORCHESTRATION.prompt.md` first to choose the next role from repository state.
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
- Populate/update it only when a loop run or role action actually starts.
- Loop semantics and update rules are defined in `docs/ai/AUTONOMOUS_LOOP.md`.

## How to write/maintain specs, docs, and prompts
- Use templates in `docs/templates/`.
- Keep workflow canonical in `docs/workflow/WORKFLOW.md`.
- Store verified facts in `docs/knowledge/FACTS.md` and UI mappings in `docs/knowledge/UI_MAP.md`.
- Keep prompts in `ai/*.prompt.md` and avoid duplicates elsewhere.

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
