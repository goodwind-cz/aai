# Remote Orchestration User Guide

This guide explains how to install and use the current remote-orchestration MVP on `feature/remote-orchestration`.

## What works now

- TypeScript host CLI for the control-plane
- SQLite-backed runtime state
- multi-project registration
- provider routing for `Claude Code` and `Codex`
- run manifest preparation for Docker workers
- approval gate evaluation and durable approval records
- Telegram command model and interactive action model
- executable validation suite (`18` CLI-backed tests)

## Design lineage

- From `SuperTurtle`, this MVP keeps the headless CLI pattern and Telegram-first operator model instead of inventing a custom provider protocol.
- From `NanoClaw`, this MVP keeps one host process, SQLite runtime state, and host-side mount validation outside the project repository.

## What is still next

- long-running daemon wrapper (`systemd --user` or equivalent)
- live Telegram transport
- actual Docker worker launch instead of manifest-only preparation

## Prerequisites

- Linux or WSL2 environment
- `git`
- `bash`
- provider CLI subscriptions already authenticated on host (`Claude Code`, `Codex`)
- optional for later runtime phases: Docker engine

Quick checks:

```bash
git --version
bash --version
claude --version || true
codex --help || true
```

## Installation

1. Get the repository and checkout the feature branch:

```bash
git clone <your-aai-repo-url> aai
cd aai
git checkout feature/remote-orchestration
```

2. Confirm the main remote-orchestration files are present:

```bash
ls apps/control-plane/src
ls apps/control-plane/config
ls tests/remote-orchestration
```

3. Initialize a local runtime database:

```bash
node --experimental-strip-types apps/control-plane/src/cli.ts init --db .runtime/control-plane.db
```

4. Validate the installation:

```bash
bash tests/remote-orchestration/run-all.sh
```

Expected result: `18` lines with `PASS`.

## Project configuration

Project-local portable config lives in:

`docs/ai/project-overrides/remote-control.yaml`

Current example:

```yaml
project_id: aai-canonical
default_branch: main
allowed_docker_profile: worker-default
default_provider_policy: auto
phase_provider_preferences:
  planning: claude
  implementation: codex
  validation: codex
```

Do not store host-only values in this file:
- absolute local repo paths
- Telegram user/chat allowlists
- provider session runtime health
- queue or lease runtime state

## Usage

### A) Register a project on one host install

```bash
node --experimental-strip-types apps/control-plane/src/cli.ts project register \
  --db .runtime/control-plane.db \
  --project-config docs/ai/project-overrides/remote-control.yaml \
  --repo-path "$PWD" \
  --chat-ids 1001 \
  --user-ids 2001
```

### B) Inspect provider policy and usage routing

```bash
node --experimental-strip-types apps/control-plane/src/cli.ts policy show \
  --project-config docs/ai/project-overrides/remote-control.yaml

node --experimental-strip-types apps/control-plane/src/cli.ts router choose \
  --project-config docs/ai/project-overrides/remote-control.yaml \
  --usage-file ./usage.json \
  --phase implementation \
  --provider auto
```

### C) Prepare one run for a Docker worker

```bash
node --experimental-strip-types apps/control-plane/src/cli.ts run prepare \
  --db .runtime/control-plane.db \
  --project-id aai-canonical \
  --ref-id PRD-AAI-REMOTE-ORCHESTRATION-01 \
  --repo-path "$PWD" \
  --project-config docs/ai/project-overrides/remote-control.yaml \
  --worktrees-root .runtime/worktrees \
  --container-image ghcr.io/example/aai-worker:preview \
  --provider auto \
  --input-refs docs/requirements/PRD-AAI-REMOTE-ORCHESTRATION-01.md \
  --output-artifacts docs/ai/reports/validation-current.log
```

This writes a run manifest and allocates a worktree directory. In the current MVP it does not launch Docker yet.

### C1) Validate extra mounts against a host allowlist

Create the host allowlist outside the repo, for example:

`~/.config/aai-control-plane/mount-allowlist.json`

You can print a template with:

```bash
node --experimental-strip-types apps/control-plane/src/cli.ts mounts template
```

And validate mounts with:

```bash
node --experimental-strip-types apps/control-plane/src/cli.ts mounts validate \
  --mounts "/home/me/projects/docs|/workspace/extra/docs|ro"
```

### D) Simulate Telegram control flow

```bash
node --experimental-strip-types apps/control-plane/src/cli.ts telegram simulate \
  --db .runtime/control-plane.db \
  --command /intake \
  --project-id aai-canonical \
  --ref-id PRD-AAI-REMOTE-ORCHESTRATION-01 \
  --summary "Start remote orchestration work item"
```

```bash
node --experimental-strip-types apps/control-plane/src/cli.ts telegram interactive
```

```bash
node --experimental-strip-types apps/control-plane/src/cli.ts telegram callback \
  --data "approve:implementation:PRD-AAI-REMOTE-ORCHESTRATION-01"
```

### E) Validate the MVP

```bash
bash tests/remote-orchestration/run-all.sh
```

Current evidence artifact:
- `docs/ai/reports/validation-20260319T215409Z.log`
- `docs/ai/reports/validation-20260319T215409Z.md`

## Telegram command model (target behavior)

- `/intake` (`/new`)
- `/status`
- `/usage`
- `/provider` (`/switch`, `/model`)
- `/projects`
- `/register` (`/aai-remote-register`)
- `/approve`
- `/resume`
- `/stop`
- `/logs` (`/looplogs`, `/pinologs`)

Command mapping source:
- `apps/control-plane/config/command-registry.json`

## Approval gates (target behavior)

`Approve implementation` requires:
- PRD reference
- frozen SPEC reference
- test plan reference
- selected project
- selected provider policy
- generated worktree manifest

`Approve validation` requires:
- implementation summary
- changed-file summary
- validation command set
- report target path
- evidence target path

Gate source:
- `apps/control-plane/config/approval-gates.json`

## Where to read full specs

- `docs/requirements/PRD-AAI-REMOTE-ORCHESTRATION-01.md`
- `docs/rfc/RFC-AAI-REMOTE-RUNTIME-01.md`
- `docs/specs/SPEC-AAI-TELEGRAM-CONTROL-01.md`
- `docs/specs/SPEC-PRD-AAI-REMOTE-ORCHESTRATION-01.md`

## Next implementation step

Wrap the CLI in a long-lived host daemon, then connect:
- live Telegram transport
- real provider CLI session probes
- real Docker worker launch and cleanup
