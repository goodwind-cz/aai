# Remote Orchestration User Guide

This guide explains how to install, configure, and user-test the remote-orchestration control-plane on `feature/remote-orchestration`.

## What is implemented

- one host control-plane process with SQLite runtime state
- multi-project registration from one install
- provider routing for `Claude Code` and `Codex`
- host-only CLI-subscription session probe and usage sync
- git worktree preparation plus real `process` or `docker` run launch
- live Telegram long polling with inline buttons and callback actions
- durable approval records and gate checks
- executable verification suite with `22` passing tests

## Runtime boundaries

- Repo-canonical:
  - `docs/requirements/*`
  - `docs/rfc/*`
  - `docs/specs/*`
  - `docs/TECHNOLOGY.md`
- Host runtime only:
  - control-plane SQLite database
  - provider session homes and CLI auth state
  - Telegram cursor/session state
  - run logs and transient reports

Do not commit provider sessions, runtime DBs, or local run logs.

## Prerequisites

- WSL2 or Linux host
- Node.js `>=24`
- `git`
- `bash`
- provider CLIs already logged in with subscription mode on the host
- optional for container runs: Docker

Quick checks:

```bash
node -v
git --version
bash --version
claude --version || true
codex --help || true
docker --version || true
```

## Installation

```bash
git clone <your-aai-repo-url> aai
cd aai
git checkout feature/remote-orchestration
cd apps/control-plane
npm install
npm run build
node dist/cli.js help
cd ../..
```

## First-time setup

### 1. Initialize the runtime database

```bash
node apps/control-plane/dist/cli.js init --db .runtime/control-plane.db
```

### 2. Prepare one project policy file

Example `docs/ai/project-overrides/remote-control.yaml`:

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

This file is portable and belongs in the project repo. Do not put host-only values into it.

### 3. Register the project on the host

```bash
node apps/control-plane/dist/cli.js project register \
  --db .runtime/control-plane.db \
  --project-config docs/ai/project-overrides/remote-control.yaml \
  --repo-path "$PWD" \
  --chat-ids 1001 \
  --user-ids 2001
```

### 4. Probe provider sessions

Secrets remain in the native provider homes. The control-plane stores only health and usage metadata in SQLite.

```bash
node apps/control-plane/dist/cli.js auth probe \
  --db .runtime/control-plane.db \
  --provider claude \
  --cli-path /usr/local/bin/claude \
  --session-home ~/.claude \
  --probe-args probe \
  --usage-args usage

node apps/control-plane/dist/cli.js auth probe \
  --db .runtime/control-plane.db \
  --provider codex \
  --cli-path /usr/local/bin/codex \
  --session-home ~/.codex \
  --probe-args probe \
  --usage-args usage
```

Inspect synced metadata:

```bash
node apps/control-plane/dist/cli.js auth status --db .runtime/control-plane.db
node apps/control-plane/dist/cli.js usage show --db .runtime/control-plane.db
```

## Main operator flows

### Route a provider

```bash
node apps/control-plane/dist/cli.js router choose \
  --db .runtime/control-plane.db \
  --project-config docs/ai/project-overrides/remote-control.yaml \
  --phase implementation \
  --provider auto
```

### Prepare and launch one run

```bash
node apps/control-plane/dist/cli.js run prepare \
  --db .runtime/control-plane.db \
  --project-id aai-canonical \
  --ref-id PRD-AAI-REMOTE-ORCHESTRATION-01 \
  --repo-path "$PWD" \
  --project-config docs/ai/project-overrides/remote-control.yaml \
  --worktrees-root .runtime/worktrees \
  --container-image ghcr.io/example/aai-worker:preview \
  --provider auto
```

Launch in local process mode:

```bash
node apps/control-plane/dist/cli.js run launch \
  --db .runtime/control-plane.db \
  --manifest .runtime/worktrees/aai-canonical-PRD-AAI-REMOTE-ORCHESTRATION-01/run-manifest.json \
  --mode process \
  --worker-command ./path/to/worker.js
```

Launch in Docker mode:

```bash
node apps/control-plane/dist/cli.js run launch \
  --db .runtime/control-plane.db \
  --manifest .runtime/worktrees/aai-canonical-PRD-AAI-REMOTE-ORCHESTRATION-01/run-manifest.json \
  --mode docker
```

Inspect the run:

```bash
node apps/control-plane/dist/cli.js run inspect \
  --db .runtime/control-plane.db \
  --run-id <run_id>
```

### Validate extra mounts

Print the allowlist template:

```bash
node apps/control-plane/dist/cli.js mounts template
```

Validate requested mounts:

```bash
node apps/control-plane/dist/cli.js mounts validate \
  --mounts "/home/me/shared-docs|/workspace/shared-docs|ro"
```

### Telegram control surface

Registry and interaction model:

```bash
node apps/control-plane/dist/cli.js telegram registry \
  --config apps/control-plane/config/command-registry.json

node apps/control-plane/dist/cli.js telegram interactive
```

Run the long-poll daemon:

```bash
node apps/control-plane/dist/cli.js telegram serve \
  --db .runtime/control-plane.db \
  --token "$TELEGRAM_BOT_TOKEN" \
  --approval-config apps/control-plane/config/approval-gates.json
```

Useful chat commands:

- `/projects`
- `/intake` and `/new`
- `/status`
- `/usage`
- `/provider`
- `/resume`
- `/stop`

Inline buttons currently cover:

- `Resume`
- `Stop`
- `Use Claude`
- `Use Codex`
- project picker callbacks

## User acceptance checklist

Run these in order on a fresh host:

1. Build the control-plane.
   Expected: `node apps/control-plane/dist/cli.js help` prints command list.
2. Initialize the runtime DB and register one project.
   Expected: `project show` returns repo path, policy, and chat/user ACLs.
3. Probe both provider sessions.
   Expected: `auth status` shows `status=ok` and `usage show --db` returns windows.
4. Prepare one run.
   Expected: a git worktree and `run-manifest.json` appear under `.runtime/worktrees`.
5. Launch one run in process mode.
   Expected: `run inspect` shows `status=done` and a log path.
6. Start Telegram daemon and send `/intake <project> <ref> <summary>`.
   Expected: work item becomes `queued` and bot responds with inline actions.
7. Press `Stop` or `Resume`.
   Expected: work item status changes in DB and bot confirms callback.
8. Run the full validation suite.
   Expected: all `22` tests print `PASS`.

## Automated verification

Run the complete suite:

```bash
bash tests/remote-orchestration/run-all.sh
```

Target result: `22/22 PASS`.

Focused checks:

```bash
bash tests/remote-orchestration/test-019-provider-session-probe.sh
bash tests/remote-orchestration/test-020-run-launch.sh
bash tests/remote-orchestration/test-021-telegram-live-polling.sh
bash tests/remote-orchestration/test-022-standard-runtime-build.sh
```

## Where login state is stored

- Provider secrets/session state:
  - native CLI homes such as `~/.claude` or `~/.codex`
  - never in repo docs
- Control-plane metadata:
  - SQLite tables `provider_sessions`, `provider_usage_snapshots`, `telegram_sessions`
- Repo evidence:
  - requirements, specs, and reports only

## Spec references

- `docs/requirements/PRD-AAI-REMOTE-ORCHESTRATION-01.md`
- `docs/rfc/RFC-AAI-REMOTE-RUNTIME-01.md`
- `docs/specs/SPEC-AAI-TELEGRAM-CONTROL-01.md`
- `docs/specs/SPEC-PRD-AAI-REMOTE-ORCHESTRATION-01.md`
