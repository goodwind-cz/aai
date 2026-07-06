# docs/ — Documentation Index

This directory holds the project-generated and runtime documentation layers of
AAI. For installation and orientation, start at the repository
[README](../README.md); for how to use every skill and workflow, read the
[User Guide](USER_GUIDE.md).

## Key documents

- [USER_GUIDE.md](USER_GUIDE.md) — the manual: full skills catalog, workflows, loop runner reference, self-hosting contract, troubleshooting and FAQ.
- [INDEX.md](INDEX.md) — auto-generated catalog of all tracked docs (status, progress, refs). Do not hand-edit; regenerate with `node .aai/scripts/generate-docs-index.mjs`.
- [TECHNOLOGY.md](TECHNOLOGY.md) — the authoritative technology contract for this repository.
- [TODO.md](TODO.md) — future enhancements roadmap.
- [SKILL_CATALOG.html](SKILL_CATALOG.html) — interactive skill explorer; generate with `/aai-docs-hub`.

## Subdirectories

- `requirements/` — product requirements (PRDs) produced by intake.
- `specs/` — frozen, measurable specifications that gate implementation.
- `rfc/` — proposals with options, tradeoffs, and approvers.
- `issues/` — bug reports and hotfix records.
- `releases/` — release plans with executable gates and sign-offs.
- `knowledge/` — project knowledge: `FACTS.md`, `PATTERNS.md`, `UI_MAP.md`, `LEARNED.md` (learned project-specific rules).
- `roles/`, `templates/`, `workflow/` — project-doc mount points, seeded per project (canonical sources live under `.aai/`).
- `ai/` — runtime layer: `STATE.yaml` (per-developer, gitignored), append-only JSONL logs (`EVENTS`, `METRICS`, `LOOP_TICKS`, `decisions`), reports, reviews. See the [README Orientation section](../README.md#orientation).
- `archive/analysis/` — immutable archived analyses; never extend them.

## Canonical sources (outside docs/)

- Workflow: [.aai/workflow/WORKFLOW.md](../.aai/workflow/WORKFLOW.md) — the only authoritative workflow definition.
- Agent guide: [.aai/AGENTS.md](../.aai/AGENTS.md) · Human playbook: [.aai/PLAYBOOK.md](../.aai/PLAYBOOK.md).
- Self-hosting contract: [.aai/system/SELF_HOSTING.md](../.aai/system/SELF_HOSTING.md).
- Change history: [CHANGELOG.md](../CHANGELOG.md).
