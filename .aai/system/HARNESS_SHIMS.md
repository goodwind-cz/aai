<!--
  .aai/system/HARNESS_SHIMS.md — fragment text for the six root instruction shims.

  Read by .aai/scripts/lib/harness-shims.mjs, driven by
  .aai/scripts/sync-harness-skills.mjs (--check / --write) under the `shims:`
  section of .aai/system/HARNESS_SKILLS.yaml. NOT hand-copied into the shims:
  edit a fragment here, then run `node .aai/scripts/sync-harness-skills.mjs --write`.

  FORMAT. A fragment starts at a line that is exactly
      <!-- fragment: <id> -->
  (id [a-z0-9-]+) and its text is every byte after that line up to the next
  fragment line or the end of the file. These bytes before the first fragment
  line are a header and are ignored. A shim is its row's fragments concatenated
  in order, with {{name}} and {{cli}} (the only two placeholders) replaced by
  the row's values. Blank lines between sections belong to the fragment above
  them, so keep the final newline(s) of a fragment exactly as the shim needs.
-->
<!-- fragment: claude-title -->
# Claude Instructions (Shim)

<!-- fragment: agents-title -->
# Agent Instructions (Shim)

<!-- fragment: pointer-body -->
This file is intentionally minimal to prevent duplicated or conflicting guidance.

## Canonical instructions
- Primary agent guide: .aai/AGENTS.md
- Human playbook: .aai/PLAYBOOK.md
- Canonical prompts: .aai/*.prompt.md
- Intake entrypoints: listed in .aai/AGENTS.md
- Canonical workflow: .aai/workflow/WORKFLOW.md
- Technology contract (authoritative): docs/TECHNOLOGY.md
- Learned rules (project-specific): docs/knowledge/LEARNED.md

## Rules
- Do not define workflow here.
- Do not create alternate role definitions here.
- If any guidance conflicts with .aai/AGENTS.md/.aai/PLAYBOOK.md, follow .aai/AGENTS.md/.aai/PLAYBOOK.md.

## How to proceed
1) Read .aai/AGENTS.md
2) Follow .aai/ORCHESTRATION.prompt.md to decide the next role
3) Execute only the dispatched role prompt
<!-- fragment: wrapper-title -->
# {{name}} Instructions (Shim)

<!-- fragment: wrapper-intro -->
This file is intentionally minimal to avoid duplicated guidance.

## Canonical sources
- Agent guide: `.aai/AGENTS.md`
- Playbook: `.aai/PLAYBOOK.md`
- Prompts: `.aai/*.prompt.md`
- Workflow: `.aai/workflow/WORKFLOW.md`
- Technology contract: `docs/TECHNOLOGY.md`

<!-- fragment: skill-discovery-heading -->
## Skill discovery (AAI prefix)
<!-- fragment: no-skill-list -->
- This shim intentionally lists no skills — inline lists rot. The canonical
  catalog is `SKILLS.md` (root) and the Skills Catalog section of
  `docs/USER_GUIDE.md`.
<!-- fragment: wrapper-tree -->
- {{name}} wrapper tree: `.{{cli}}/skills/` mirrors the skill set; each skill maps
  `/aai-<name>` to a `.aai/SKILL_<NAME>.prompt.md` prompt file.
- Invocation pattern: `{{cli}} --prompt-file .aai/SKILL_<NAME>.prompt.md`
  (e.g. `{{cli}} --prompt-file .aai/SKILL_INTAKE.prompt.md`).
- Project-local generated skills live in `.claude/skills/` and must use `aai-` prefix.
- Dynamic {{name}} index is written to `.{{cli}}/skills.local/README.md` by `/aai-bootstrap`.

<!-- fragment: wrapper-how-to-proceed -->
## How to proceed
1) Read `.aai/AGENTS.md`.
2) Use `aai-*` skills for orchestration/intake/loop.
3) Keep Requirement -> Spec -> Implementation -> Evidence traceability.
<!-- fragment: copilot-main -->
# Copilot Instructions (Shim)

This repository uses a single canonical workflow and a prompt suite for consistent agent behavior.

## Canonical sources
- Agent guide: /.aai/AGENTS.md
- Playbook: /.aai/PLAYBOOK.md
- Prompts: /.aai/*.prompt.md
- Intake entrypoints: /.aai/AGENTS.md
- Workflow: /.aai/workflow/WORKFLOW.md
- Technology contract: /docs/TECHNOLOGY.md

## Rules
- Do not introduce alternative workflows or role systems.
- Do not assume frameworks or tools not documented in /docs/TECHNOLOGY.md.
- Prefer changes that preserve traceability:
  Requirement → Spec → Implementation → Evidence

## Suggested developer flow
- Use .aai/ORCHESTRATION.prompt.md to select the next role step.
- Validate with .aai/VALIDATION.prompt.md before claiming completion.

<!-- fragment: copilot-project-skills -->
- Project-specific generated skills are in `.claude/skills/` and use `aai-` prefix.
<!-- fragment: cursor-rule -->
---
description: AAI workflow rules — always active when working in this project
globs: "**/*"
alwaysApply: true
---

# AAI (Autonomous Agent Interface)

This project uses AAI for structured Planning → Implementation → Validation
workflows.

## Always do this first
Read `.aai/AGENTS.md` before starting any development work.

## Skills are native in Cursor
Cursor discovers project skills directly from `.agents/skills/` (and, for
compatibility, `.claude/skills/` and `.codex/skills/`) — invoke one with
`/skill-name` rather than reading a prompt file by hand.
For anything not covered by a skill, use `@file` to pull in the relevant
`.aai/*.prompt.md` or `.aai/AGENTS.md` section instead of this file trying to
enumerate one.

## Core rules
- Requirements → Spec → Implementation → Evidence (traceability required)
- Never claim completion without running tests and checking exit codes
- Do not invent frameworks — read `docs/TECHNOLOGY.md` first
- If `docs/ai/STATE.yaml` exists, read it before any role dispatch

## Workflow
Orchestration dispatches Planning → Implementation → Validation automatically.
Invoke any AAI skill with `/skill-name` to start work, run the full cycle, or
unblock a human decision — see `.aai/AGENTS.md` for the full skill catalog.
