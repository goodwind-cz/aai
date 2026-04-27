# AAI Repository

A canonical, reusable AAI that standardizes workflows, roles, prompts, and documentation for agent-driven development. It provides a minimal, consistent structure so humans and AI agents (Codex/ChatGPT, Claude, Copilot) can collaborate using the same sources of truth.

## 📚 Quick Links

- **[USER_GUIDE.md](USER_GUIDE.md)** - 🆕 Complete user guide with all 23 skills, workflows, and best practices
- **[SKILL_CATALOG.html](SKILL_CATALOG.html)** - 🆕 Interactive skill explorer (generate with `/aai-docs-hub`)
- **[TODO.md](TODO.md)** - 🆕 Future enhancements roadmap
- **[ai/DECAPOD_INTEGRATION.md](ai/DECAPOD_INTEGRATION.md)** - 🆕 Compliance framework integration
- **[../.aai/system/SELF_HOSTING.md](../.aai/system/SELF_HOSTING.md)** - Self-hosting contract for evolving AAI with AAI

**New to AAI?** Start with the [USER_GUIDE.md](USER_GUIDE.md) for a complete walkthrough.

## 1) Project Title & Description
**AAI (Canonical)** — a lightweight governance and prompt suite that enforces a single workflow, clear role semantics, and evidence-based validation.

## 2) What this repository is for
Use this repo to bootstrap or normalize an AI-ready documentation and prompt system. It provides:
- A single canonical workflow and role definition.
- Prompt-driven orchestration and validation.
- Knowledge hygiene (facts, UI map, archive).
- Templates for requirements, specs, decisions, and knowledge.

## 3) Assumptions about the environment
- You have Git installed.
- You have either a POSIX shell (bash/zsh) or Windows PowerShell 5.1+ / PowerShell 7+ installed.
- You can edit Markdown files and run CLI commands.
- If using GitHub Codespaces, you can run commands from the terminal.
- AI agents can read the canonical files in this repository.

## 4) Directory and file structure overview
```
.
├── .aai/                          # AAI system
│   ├── *.prompt.md                # Canonical prompts
│   ├── AGENTS.md
│   ├── PLAYBOOK.md
│   ├── workflow/WORKFLOW.md
│   ├── roles/ROLES.md
│   ├── templates/                 # Document templates
│   ├── scripts/                   # Helper scripts
│   ├── system/                    # System docs
│   └── knowledge/                 # Universal patterns
├── CLAUDE.md
├── install.ps1                    # PowerShell one-line installer entrypoint
├── install.sh                     # Bash/curl one-line installer entrypoint
├── docs/
│   ├── ai/                        # Persistent runtime state
│   ├── knowledge/FACTS.md
│   ├── knowledge/UI_MAP.md
│   └── archive/analysis/
└── .github/
    └── copilot-instructions.md
```

## 5) How to use this AAI (step-by-step)
### Installation
From the target project directory:

PowerShell:

```powershell
irm https://raw.githubusercontent.com/goodwind-cz/aai/main/install.ps1 | iex
```

Bash:

```bash
curl -fsSL https://raw.githubusercontent.com/goodwind-cz/aai/main/install.sh | bash
```

This downloads the canonical repository and syncs the AAI layer into the current directory.

Review-first variant:

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

After installation:

```bash
git status
git diff
/aai-bootstrap
/aai-doctor
```

Manual alternative:

PowerShell:

```powershell
git clone https://github.com/goodwind-cz/aai.git
cd aai
powershell -ExecutionPolicy Bypass -File .\install.ps1 -TargetRoot C:\path\to\your-project
```

Bash:

```bash
git clone https://github.com/goodwind-cz/aai.git
cd aai
bash ./install.sh --target-root /path/to/your-project
```

### Bootstrap
Bootstrap only when normalizing an existing repo into this structure.
```bash
cat .aai/BOOTSTRAP.prompt.md
```
Use an AI agent to follow the prompt’s instructions.

### Orchestration
Orchestration decides the next role based on repository state.
```bash
cat .aai/ORCHESTRATION.prompt.md
```
Parallel and human-in-the-loop options:
```bash
cat .aai/ORCHESTRATION_PARALLEL.prompt.md
cat .aai/ORCHESTRATION_HITL.prompt.md
```

### Validation
Run validation after implementation to collect executable evidence.
```bash
cat .aai/VALIDATION.prompt.md
```

### Remediation
Use remediation when validation fails to apply minimal fixes.
```bash
cat .aai/REMEDIATION.prompt.md
```

### Reverse analysis
Use the reverse analysis prompt when mapping UI-to-code in Dash/FastAPI/Celery stacks.
```bash
cat .aai/REVERSE_ANALYSIS_DASH_FASTAPI_CELERY.prompt.md
```
Use the generic reverse analysis prompt for any stack, including external repository references.
```bash
cat .aai/REVERSE_ANALYSIS_GENERIC.prompt.md
```

## 6) Example workflows
### Basic single-threaded flow
```bash
# Decide next role
cat .aai/ORCHESTRATION.prompt.md

# If Planning dispatched
# (Use your agent to execute Planning per prompt)

# If Implementation dispatched
# (Implement per frozen spec)

# If Validation dispatched
cat .aai/VALIDATION.prompt.md
```

### Parallel flow for independent scopes
```bash
cat .aai/ORCHESTRATION_PARALLEL.prompt.md
```

### Human-in-the-loop decision gating
```bash
cat .aai/ORCHESTRATION_HITL.prompt.md
```

## 7) How to write/maintain specs, docs, and prompts
- **Workflow:** Only `.aai/workflow/WORKFLOW.md` is authoritative.
- **Roles:** Use `.aai/roles/ROLES.md` for semantic roles.
- **Requirements and specs:** Use templates in `.aai/templates/`.
- **Knowledge:** Put verified facts in `docs/knowledge/FACTS.md` and UI trace in `docs/knowledge/UI_MAP.md`.
- **Project sessions:** Put human-readable ongoing project discussion in `docs/project-sessions/` when you need durable cross-agent continuity.
- **Prompts:** Keep canonical prompts in `.aai/*.prompt.md` and avoid duplications elsewhere.
- **Engineering practices:** Follow `.aai/AGENTS.md` for DRY, SOLID, KISS, YAGNI, separation of concerns, testability, explicit error handling, and contract compatibility.

## 8) How to extend this for a new project
1. Copy the `.aai/` and `docs/` trees into your repo.
2. Seed `docs/TECHNOLOGY.md` from `.aai/templates/TECHNOLOGY_TEMPLATE.md` and fill it using `.aai/TECH_EXTRACT.prompt.md`.
3. Write requirements and specs using templates.
4. Run orchestration and follow the dispatched role.

## 9) Self-hosting AAI
- Read `.aai/system/SELF_HOSTING.md` for the ownership model.
- Treat `.aai/` and `.aai/templates/` as canonical authoring layer.
- Treat `docs/TECHNOLOGY.md` and other filled docs as project-generated layer.
- Treat `docs/ai/` as runtime layer.
- Verify packaging with:
  - `tests/self-hosting/test-self-hosting-smoke.sh`
  - `tests/self-hosting/test-self-hosting-smoke.ps1`

## 10) Troubleshooting / FAQ
**Q: I want to add another workflow doc.**
A: Don’t. Only `.aai/workflow/WORKFLOW.md` is canonical.

**Q: Can I assume technologies?**
A: No. Always consult `docs/TECHNOLOGY.md` first.

**Q: Where should older analyses go?**
A: Move them to `docs/archive/analysis/` and treat them as immutable.

## 11) Links to AGENTS, CLAUDE, and Copilot instructions
- Agent Guide: `.aai/AGENTS.md`
- Claude shim: `CLAUDE.md`
- Copilot instructions: `.github/copilot-instructions.md`

## 12) Notes about docs/TECHNOLOGY.md, docs/knowledge, and archive usage
- `docs/TECHNOLOGY.md` is the authoritative technology contract (created/updated by the tech prompts).
- `.aai/templates/TECHNOLOGY_TEMPLATE.md` is the canonical structure source.
- `docs/knowledge/FACTS.md` stores verified facts only.
- `docs/knowledge/UI_MAP.md` maps UI to code with evidence.
- `docs/project-sessions/` stores named human-readable project discussion threads and resume points.
- `docs/archive/analysis/` is immutable history; do not extend archived analyses.
