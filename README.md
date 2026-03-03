# AAI (Canonical)

This repository contains a reusable, low-friction AAI: a single workflow definition, semantic roles, canonical prompts, and templates that help humans and AI agents coordinate with traceability and evidence.


## Pushing AAI layer into a target project

Run the sync script **from this repository** and pass the path to the target project.
The script resolves its own source root automatically — no need to copy it to the target first.

### Bash / Git-Bash
```bash
# From this aai repo:
./.aai/scripts/aai-sync.sh ../maty-ai

# Then in the target project:
cd ../maty-ai
git status
git diff
git add .aai docs CLAUDE.md CODEX.md GEMINI.md README.md SKILLS.md .claude/skills .codex/skills .gemini/skills .github/copilot-instructions.md
git commit -m "Update AAI layer"
```

### PowerShell
```powershell
# From this aai repo:
.\.aai\scripts\aai-sync.ps1 -TargetRoot ..\maty-ai

# Then in the target project:
cd ..\maty-ai
git status
git diff
git add .aai docs CLAUDE.md CODEX.md GEMINI.md README.md SKILLS.md .claude/skills .codex/skills .gemini/skills .github/copilot-instructions.md
git commit -m "Update AAI layer"
```

- Sync scope includes `.aai/**`, `.claude/skills/**`, `.codex/skills/**`, `.gemini/skills/**`, `.github/copilot-instructions.md`, `docs/knowledge`, and root shims (`CLAUDE.md`, `CODEX.md`, `GEMINI.md`, `README.md`, `SKILLS.md`).
- For `.claude/skills/**`, template entries are updated, while target-only local skills are preserved.
- Dynamic project skills should use unique `aai-*` names under `.claude/skills/` so they stay target-only and preserved on sync.
- Runtime files in target `docs/ai` are preserved (not overwritten) if they already exist: `STATE.yaml`, `METRICS.jsonl`, `LOOP_TICKS.jsonl`, `decisions.jsonl`.
- It intentionally does **not** overwrite project docs under `docs/requirements`, `docs/specs`, `docs/decisions`, `docs/releases`, or `docs/issues`.

## What this repository is for
- Standardizing agent workflows (Planning → Implementation → Validation → Remediation).
- Capturing requirements, specs, decisions, and knowledge with clear separation.
- Running low-token intake prompts to start work consistently.

## Assumptions about the environment
- POSIX shell (bash/zsh) and Git available.
- You can run CLI commands and edit Markdown.
- AI agents have read access to .aai/AGENTS.md and prompt files.

## Directory overview
```
.
├── .aai/                          # AAI system (gitignored in target projects)
│   ├── *.prompt.md                # Canonical prompts
│   ├── AGENTS.md                  # Agent guide
│   ├── PLAYBOOK.md                # Operating model
│   ├── workflow/WORKFLOW.md       # Canonical workflow
│   ├── roles/ROLES.md            # Role definitions
│   ├── templates/                 # Document templates
│   ├── scripts/                   # Helper scripts
│   ├── system/                    # System docs (locks, pricing, etc.)
│   └── knowledge/                 # Universal patterns
├── CLAUDE.md                      # Claude shim
├── README.md
├── docs/
│   ├── ai/                        # Persistent runtime state
│   ├── knowledge/                 # Project knowledge
│   ├── issues/
│   ├── specs/
│   ├── rfc/
│   └── releases/
└── .github/
    └── copilot-instructions.md
```

## How to use this AAI (step-by-step)
### Installation
1) Clone or copy this repository into your project.
2) Ensure canonical files are present (see .aai/AGENTS.md).

### Bootstrap (project normalization)
```bash
cat .aai/BOOTSTRAP.prompt.md
```
Use an AI agent to follow the instructions when normalizing an existing repo.

### Orchestration
```bash
cat .aai/ORCHESTRATION.prompt.md
```
Parallel and HITL variants:
```bash
cat .aai/ORCHESTRATION_PARALLEL.prompt.md
cat .aai/ORCHESTRATION_HITL.prompt.md
```

### Planning
```bash
cat .aai/PLANNING.prompt.md
```

### Implementation
```bash
cat .aai/IMPLEMENTATION.prompt.md
```

### Validation
```bash
cat .aai/VALIDATION.prompt.md
```

### Remediation
```bash
cat .aai/REMEDIATION.prompt.md
```

### Reverse analysis
```bash
cat .aai/REVERSE_ANALYSIS_DASH_FASTAPI_CELERY.prompt.md
cat .aai/REVERSE_ANALYSIS_GENERIC.prompt.md
```

### Skills (session-scoped, multi-step)

Skills are higher-level prompts that compose multiple steps within one agent session.
Use them instead of manually chaining individual role prompts.

| Skill | Command | Description |
| --- | --- | --- |
| State health check | `/aai-check-state` | Validate STATE.yaml before running roles |
| Intake router | `/aai-intake` | Route new work to the correct intake form |
| Autonomous loop | `/aai-loop` | Run Planning-Implementation-Validation cycles |
| Human-in-the-loop | `/aai-hitl` | Resolve human pauses and record decisions |
| Bootstrap | `/aai-bootstrap` | Detect architecture, generate dynamic skills |
| Validation report | `/aai-validate-report` | Generate report with screenshots and evidence |
| Canonicalize | `/aai-canonicalize` | Migrate legacy paths into canonical layout |
| Share | `/aai-share <file>` | Publish Markdown to Cloudflare Pages |
| TDD | `/aai-tdd` | Enforced RED-GREEN-REFACTOR cycle with evidence |
| Worktree | `/aai-worktree <cmd>` | Manage git worktrees for parallel development |

See [SKILLS.md](SKILLS.md) for full documentation, prerequisites, and examples.

Typical skill flow:

```bash
/aai-intake              # Start new work
/aai-loop                # Run autonomous cycles
/aai-hitl                # Resolve human decision (if loop pauses)
/aai-validate-report     # Generate evidence report
/aai-share report.md     # Share report publicly
```

Agent-specific invocation:

- **Claude**: use slash commands directly (`/aai-tdd`, `/aai-share`, etc.).
- **Codex**: execute skill prompts (`codex --prompt-file .aai/SKILL_LOOP.prompt.md`).
- **Gemini**: execute skill prompts (`gemini --prompt-file .aai/SKILL_LOOP.prompt.md`).

## When to run each action
- Use `.aai/ORCHESTRATION.prompt.md` first to choose the next role from repository state.
- Use `.aai/PLANNING.prompt.md` when orchestration dispatches Planning, or when requirement-to-spec mapping/measurability is missing.
- Use `.aai/IMPLEMENTATION.prompt.md` when orchestration dispatches Implementation and the target spec is frozen.
- Use `.aai/TECH_EXTRACT.prompt.md` when `docs/TECHNOLOGY.md` is missing or needs first-time creation.
- Use `.aai/TECH_UPDATE_DIFF.prompt.md` when `docs/TECHNOLOGY.md` already exists and repo changes may have altered the technology contract.
- Use `.aai/VALIDATION.prompt.md` after implementation changes to produce executable evidence and PASS/FAIL.
- Use `.aai/REMEDIATION.prompt.md` only after a validation FAIL.
- Use `.aai/BOOTSTRAP.prompt.md` only when normalizing a non-canonical repository structure.

## Low-token intake (forms)
Use these entrypoints for all new work (see .aai/AGENTS.md for the authoritative list):
```bash
cat .aai/INTAKE_PRD.prompt.md
cat .aai/INTAKE_CHANGE.prompt.md
cat .aai/INTAKE_ISSUE.prompt.md
cat .aai/INTAKE_RESEARCH.prompt.md
cat .aai/INTAKE_HOTFIX.prompt.md
cat .aai/INTAKE_TECHDEBT.prompt.md
cat .aai/INTAKE_RFC.prompt.md
cat .aai/INTAKE_RELEASE.prompt.md
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
- `INTAKE_ISSUE` and `INTAKE_HOTFIX` -> `.aai/templates/ISSUE_TEMPLATE.md`
- `INTAKE_CHANGE` -> `.aai/templates/CHANGE_TEMPLATE.md`
- `INTAKE_TECHDEBT` -> `.aai/templates/TECHDEBT_TEMPLATE.md`
- `INTAKE_PRD` -> `.aai/templates/REQUIREMENT_TEMPLATE.md`
- `INTAKE_RFC` -> `.aai/templates/RFC_TEMPLATE.md`
- `INTAKE_RELEASE` -> `.aai/templates/RELEASE_TEMPLATE.md`

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
4) Run `.aai/ORCHESTRATION.prompt.md` immediately after intake output is saved.
5) Use `.aai/ORCHESTRATION_HITL.prompt.md` only for explicit human decisions.

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
- Loop semantics and update rules are defined in `.aai/system/AUTONOMOUS_LOOP.md`.

Runtime append-only logs (JSONL — one JSON object per line, never rewrite):
- `docs/ai/LOOP_TICKS.jsonl` — external timing for each loop tick (written by loop runner scripts).
- `docs/ai/METRICS.jsonl` — completed work item economics (flushed by `.aai/METRICS_FLUSH.prompt.md`).
- `docs/ai/decisions.jsonl` — HITL decisions log (written by `.aai/SKILL_HITL.prompt.md`).

## Autonomous loop runners (no manual STATE editing)
Use the helper scripts to run repeated autonomous ticks until a stop condition:
- `project_status=paused`
- `human_input.required=true`
- `last_validation.status=pass`

Default behavior is now **skill-first**:
1) `.aai/SKILL_CHECK_STATE.prompt.md`
2) `.aai/SKILL_INTAKE.prompt.md`
3) `.aai/SKILL_LOOP.prompt.md`

Legacy orchestration-only behavior is still available via `legacy` mode.

### PowerShell
```powershell
.\.aai\scripts\autonomous-loop.ps1 `
  -Mode skill `
  -AgentCommand 'codex' `
  -MaxIterations 20 `
  -SleepSeconds 1 `
  -AutoInitState
```
PyYAML is auto-installed if missing. Use `-NoAutoInstallPyYaml` to disable auto-install.

Examples (PowerShell):
```powershell
# Codex CLI
.\.aai\scripts\autonomous-loop.ps1 `
  -Mode skill `
  -AgentCommand 'codex' `
  -MaxIterations 20 `
  -SleepSeconds 1 `
  -AutoInitState

# Claude CLI
.\.aai\scripts\autonomous-loop.ps1 `
  -Mode skill `
  -AgentCommand 'claude' `
  -MaxIterations 20 `
  -SleepSeconds 1 `
  -AutoInitState

# Gemini CLI
.\.aai\scripts\autonomous-loop.ps1 `
  -Mode skill `
  -AgentCommand 'gemini' `
  -MaxIterations 20 `
  -SleepSeconds 1 `
  -AutoInitState

# Legacy mode (custom one-tick command)
.\.aai\scripts\autonomous-loop.ps1 `
  -Mode legacy `
  -TickCommand 'codex --prompt-file .aai/ORCHESTRATION.prompt.md' `
  -MaxIterations 20 `
  -SleepSeconds 1 `
  -AutoInitState
```

In `skill` mode, the script checks `.claude/skills/AAI_DYNAMIC_SKILLS.md` as a bootstrap marker.  
Use `-SkipBootstrapCheck` only when you intentionally skip dynamic skills bootstrap.

### Bash
```bash
./.aai/scripts/autonomous-loop.sh \
  --mode skill \
  --agent-command "codex" \
  --max-iterations 20 \
  --sleep-seconds 1 \
  --auto-init-state
```

Tip:
- Use `-DryRun` (PowerShell) or `--dry-run` (Bash) to verify loop behavior without executing the agent command.
- Validate skill readiness and evidence:
  - PowerShell: `.\.aai\scripts\validate-skills.ps1`
  - Bash: `./.aai/scripts/validate-skills.sh`

## How to write/maintain specs, docs, and prompts
- Use templates in `.aai/templates/`.
- Keep workflow canonical in `.aai/workflow/WORKFLOW.md`.
- Store verified facts in `docs/knowledge/FACTS.md` and UI mappings in `docs/knowledge/UI_MAP.md`.
- Store confirmed reusable patterns in `docs/knowledge/PATTERNS.md` (project-specific).
- Universal cross-project patterns live in `.aai/knowledge/PATTERNS_UNIVERSAL.md` (sync-managed, read-only).
- Keep prompts in `.aai/*.prompt.md` and avoid duplicates elsewhere.
- Follow engineering principles from `.aai/AGENTS.md`: DRY, SOLID, KISS, YAGNI, separation of concerns, testability, explicit error handling, and contract compatibility.

## How to extend this for a new project
1) Copy `.aai/` and `docs/` into your repo.
2) Generate `docs/TECHNOLOGY.md` via `.aai/TECH_EXTRACT.prompt.md`.
3) Use intake prompts to create PRDs, issues, specs, or RFCs.
4) Run orchestration to dispatch the next role.

## Troubleshooting / FAQ
**Q: Can I add another workflow doc?**
A: No. Only `.aai/workflow/WORKFLOW.md` is canonical.

**Q: Where do I list technologies?**
A: `docs/TECHNOLOGY.md` (generated by the tech prompts).

## Canonical references
- AGENTS: `.aai/AGENTS.md`
- PLAYBOOK: `.aai/PLAYBOOK.md`
- Claude shim: `CLAUDE.md`
- Codex shim: `CODEX.md`
- Gemini shim: `GEMINI.md`
- Copilot instructions: `.github/copilot-instructions.md`

## Knowledge management

### Extracting facts and patterns from documents
```bash
cat .aai/DOCS_COMPRESS_TO_FACTS.prompt.md
```
Extracts verified facts → `docs/knowledge/FACTS.md` and confirmed patterns → `docs/knowledge/PATTERNS.md`.
Run after reverse analysis, architecture reviews, or any document that contains verifiable conclusions.

### Pattern loading (automatic in Planning and Implementation)
Agents read only the INDEX table first, then load full text of patterns matching the current task tags.
Project patterns: `docs/knowledge/PATTERNS.md` · Universal patterns: `.aai/knowledge/PATTERNS_UNIVERSAL.md`

### Periodic memory hygiene
```bash
cat .aai/MEMORY_REVIEW.prompt.md
```
Removes stale facts, splits oversized patterns, flags UNVERIFIED entries (unused >90 days), suggests promotions to PATTERNS_UNIVERSAL.md.

## Notes on docs/TECHNOLOGY.md, knowledge, and archives
- `docs/TECHNOLOGY.md` is the authoritative technology contract.
- Living knowledge stores: `docs/knowledge/FACTS.md`, `docs/knowledge/PATTERNS.md`, `.aai/knowledge/PATTERNS_UNIVERSAL.md`, `docs/knowledge/UI_MAP.md`.
- `docs/archive/analysis/` is immutable history.
