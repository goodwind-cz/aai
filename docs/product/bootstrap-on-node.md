---
id: bootstrap-on-node
type: product
capability: bootstrap-on-node
status: current
delivered_by:
  - bootstrap-on-node
spec: docs/specs/SPEC-0306-spec-bootstrap-on-node.md
updated: 2026-11-20
---

# Project bootstrap runs on Node, with a native Windows launcher

## What it does

Bootstrap looks at a project (languages, package manager, task runners,
test and build tools, authentication hints) and writes the project's own
dynamic skills, such as a ready-made unit-test or build command, plus the
local skill indexes and the runtime `.gitignore` block. It now runs as one
Node.js module behind two small launchers, a shell one and a new PowerShell
one, so Windows users can bootstrap without Git Bash. The files it writes
are the same, byte for byte, as the previous bash bootstrap produced, except
for a short list of documented corrections (for example, a credential file
without a recognized variable name no longer stops the run silently).
Node.js 22 or later is now required: without it, both launchers refuse,
print an install hint and change nothing.

## How to use it

- macOS, Linux, Git Bash: `bash .aai/scripts/aai-bootstrap.sh [target-root] [--dry-run] [--force] [--with-claude-hooks]`
- Windows PowerShell 5.1 or pwsh 7: `powershell -NoProfile -File .aai/scripts/aai-bootstrap.ps1 [target-root] [--dry-run] [--force] [--with-claude-hooks]`
- Or ask the agent for `/aai-bootstrap`, which picks the right launcher.
- `--dry-run` lists planned writes without changing files; `--force`
  replaces skill files that lack the AAI dynamic marker;
  `--with-claude-hooks` merges the AAI hook overlay into
  `.claude/settings.json`.
- Existing installs get the new launcher and module with `/aai-update`.

## Data model

None. The generated files (`.claude/skills/<name>/SKILL.md`,
`.claude/skills/AAI_DYNAMIC_SKILLS.md`, `.codex/skills.local/README.md`,
`.gemini/skills.local/README.md`, the `.gitignore` blocks,
`docs/ai/pr-config.yaml` platform line) keep their previous shape and
content. On Windows the marker file now records the native target path
(`C:\...`) instead of the Git Bash form (`/c/...`).

## Interfaces and contracts

- `.aai/scripts/aai-bootstrap.sh`: thin launcher (sh/bash/dash); passes
  arguments and the exit code through to the module.
- `.aai/scripts/aai-bootstrap.ps1`: new thin launcher for Windows
  PowerShell 5.1 and pwsh 7; same arguments and exit codes.
- `.aai/scripts/aai-bootstrap.mjs`: the module holding all bootstrap logic.
- Exit codes: 0 success; 1 conflict with an unmarked file, target not
  found, or Node missing (the stderr line says which); 2 usage error;
  3 an explicitly requested hooks overlay could not be installed.
- A target of `--`, `-P` or `-L` is now refused with exit 1 (the bash
  bootstrap used to bootstrap your home directory instead).

## Limits and non-goals

- Node.js 22 or later is required; there is no bash fallback.
- What bootstrap detects and writes did not change; new detection rules are
  out of scope.
- The credential search now uses one rule on every host (skips
  `node_modules`, `.git`, `dist`, `build`; searches hidden files; ignores
  `.gitignore`), so its result no longer depends on whether `rg` is
  installed.
- Kept for parity, filed as follow-ups rather than changed: the docker tag
  keeps a trailing dash for names ending in punctuation; cache patterns are
  compared without carriage-return stripping; generated files name
  `aai-bootstrap.sh` as the generator on Windows too.

## Links

- Request: docs/issues/CHANGE-0261-bootstrap-on-node.md
- Spec: docs/specs/SPEC-0306-spec-bootstrap-on-node.md
- Validation evidence: docs/ai/reports/VALIDATION-20261120T213601Z-bootstrap-on-node-r3.md
