# AI Operating System Repository

A canonical, reusable AI Operating System that standardizes workflows, roles, prompts, and documentation for agent-driven development. It provides a minimal, consistent structure so humans and AI agents (Codex/ChatGPT, Claude, Copilot) can collaborate using the same sources of truth.

## 1) Project Title & Description
**AI Operating System (Canonical)** — a lightweight governance and prompt suite that enforces a single workflow, clear role semantics, and evidence-based validation.

## 2) What this repository is for
Use this repo to bootstrap or normalize an AI-ready documentation and prompt system. It provides:
- A single canonical workflow and role definition.
- Prompt-driven orchestration and validation.
- Knowledge hygiene (facts, UI map, archive).
- Templates for requirements, specs, decisions, and knowledge.

## 3) Assumptions about the environment
- You have a POSIX shell (bash/zsh) and Git installed.
- You can edit Markdown files and run CLI commands.
- If using GitHub Codespaces, you can run commands from the terminal.
- AI agents can read the canonical files in this repository.

## 4) Directory and file structure overview
```
.
├── AGENTS.md
├── PLAYBOOK.md
├── CLAUDE.md
├── ai/
│   ├── ORCHESTRATION.prompt.md
│   ├── ORCHESTRATION_PARALLEL.prompt.md
│   ├── ORCHESTRATION_HITL.prompt.md
│   ├── VALIDATION.prompt.md
│   ├── REMEDIATION.prompt.md
│   ├── TECH_EXTRACT.prompt.md
│   ├── TECH_UPDATE_DIFF.prompt.md
│   ├── REVERSE_ANALYSIS_DASH_FASTAPI_CELERY.prompt.md
│   └── DOCS_COMPRESS_TO_FACTS.prompt.md
├── docs/
│   ├── workflow/WORKFLOW.md
│   ├── roles/ROLES.md
│   ├── knowledge/FACTS.md
│   ├── knowledge/UI_MAP.md
│   ├── ai/LOCKS.md
│   ├── templates/
│   │   ├── WORKFLOW_TEMPLATE.md
│   │   ├── ROLE_TEMPLATE.md
│   │   ├── REQUIREMENT_TEMPLATE.md
│   │   ├── SPEC_TEMPLATE.md
│   │   ├── DECISION_TEMPLATE.md
│   │   └── KNOWLEDGE_TEMPLATE.md
│   └── archive/analysis/
└── .github/
    └── copilot-instructions.md
```

## 5) How to use this AI Operating System (step-by-step)
### Installation
1. Clone or copy this repository into your project.
2. Ensure the canonical files are present (see Section 4).

### Bootstrap
Bootstrap only when normalizing an existing repo into this structure.
```bash
cat ai/BOOTSTRAP.prompt.md
```
Use an AI agent to follow the prompt’s instructions.

### Orchestration
Orchestration decides the next role based on repository state.
```bash
cat ai/ORCHESTRATION.prompt.md
```
Parallel and human-in-the-loop options:
```bash
cat ai/ORCHESTRATION_PARALLEL.prompt.md
cat ai/ORCHESTRATION_HITL.prompt.md
```

### Validation
Run validation after implementation to collect executable evidence.
```bash
cat ai/VALIDATION.prompt.md
```

### Remediation
Use remediation when validation fails to apply minimal fixes.
```bash
cat ai/REMEDIATION.prompt.md
```

### Reverse analysis
Use the reverse analysis prompt when mapping UI-to-code in Dash/FastAPI/Celery stacks.
```bash
cat ai/REVERSE_ANALYSIS_DASH_FASTAPI_CELERY.prompt.md
```

## 6) Example workflows
### Basic single-threaded flow
```bash
# Decide next role
cat ai/ORCHESTRATION.prompt.md

# If Planning dispatched
# (Use your agent to execute Planning per prompt)

# If Implementation dispatched
# (Implement per frozen spec)

# If Validation dispatched
cat ai/VALIDATION.prompt.md
```

### Parallel flow for independent scopes
```bash
cat ai/ORCHESTRATION_PARALLEL.prompt.md
```

### Human-in-the-loop decision gating
```bash
cat ai/ORCHESTRATION_HITL.prompt.md
```

## 7) How to write/maintain specs, docs, and prompts
- **Workflow:** Only `docs/workflow/WORKFLOW.md` is authoritative.
- **Roles:** Use `docs/roles/ROLES.md` for semantic roles.
- **Requirements and specs:** Use templates in `docs/templates/`.
- **Knowledge:** Put verified facts in `docs/knowledge/FACTS.md` and UI trace in `docs/knowledge/UI_MAP.md`.
- **Prompts:** Keep canonical prompts in `ai/*.prompt.md` and avoid duplications elsewhere.

## 8) How to extend this for a new project
1. Copy the `ai/` and `docs/` trees into your repo.
2. Generate `docs/TECHNOLOGY.md` using `ai/TECH_EXTRACT.prompt.md`.
3. Write requirements and specs using templates.
4. Run orchestration and follow the dispatched role.

## 9) Troubleshooting / FAQ
**Q: I want to add another workflow doc.**
A: Don’t. Only `docs/workflow/WORKFLOW.md` is canonical.

**Q: Can I assume technologies?**
A: No. Always consult `docs/TECHNOLOGY.md` first.

**Q: Where should older analyses go?**
A: Move them to `docs/archive/analysis/` and treat them as immutable.

## 10) Links to AGENTS, CLAUDE, and Copilot instructions
- Agent Guide: `AGENTS.md`
- Claude shim: `CLAUDE.md`
- Copilot instructions: `.github/copilot-instructions.md`

## 11) Notes about docs/TECHNOLOGY.md, docs/knowledge, and archive usage
- `docs/TECHNOLOGY.md` is the authoritative technology contract (created/updated by the tech prompts).
- `docs/knowledge/FACTS.md` stores verified facts only.
- `docs/knowledge/UI_MAP.md` maps UI to code with evidence.
- `docs/archive/analysis/` is immutable history; do not extend archived analyses.
