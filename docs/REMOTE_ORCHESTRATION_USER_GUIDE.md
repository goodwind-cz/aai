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
- executable verification suite with `26` passing tests

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
npm --prefix apps/control-plane run install:wizard
```

This is the preferred path. The installer:

- installs control-plane dependencies
- builds `dist/cli.js`
- initializes `.runtime/control-plane.db`
- creates `docs/ai/project-overrides/remote-control.yaml` only if it does not already exist
- registers the project against the host DB
- auto-detects `claude` and `codex` from the current Linux/WSL shell
- records an install summary under `.runtime/install-summary.<project>.json`
- if a provider CLI is missing, records that state, prints a manual install instruction, and auto-routing will not use that provider
- asks only a few onboarding questions and prints the exact run command at the end

On a WSL host, the detected Claude path should normally match:

```bash
which claude
```

Example shape:

```bash
/home/user/.local/bin/claude
```

No manual YAML editing is required for first install unless you want to override defaults.

If `claude` or `codex` is not installed, the installer will not try to invent a broken fallback. It will:

- mark the provider as `missing` in the host DB
- print a message telling the operator to install that CLI manually
- keep the rest of the control-plane usable
- exclude the missing provider from automatic routing

## Wizard questions

The wizard asks only for:

1. managed project repository path
2. project id
3. default branch
4. allowed Telegram chat ids
5. allowed Telegram user ids
6. Telegram bot token

When it finishes, it generates:

- portable project config
- install summary
- runtime env file
- ready-to-run `run-control-plane.sh` launcher

## Recommended npm commands

Run these from the repo root:

```bash
npm --prefix apps/control-plane run install:wizard
npm --prefix apps/control-plane run build
npm --prefix apps/control-plane run serve:generated
npm --prefix apps/control-plane run test:remote:install
npm --prefix apps/control-plane run validate:remote
```

For any direct control-plane operation, use:

```bash
npm --prefix apps/control-plane run <script-name> -- <args>
```

These npm scripts go through `apps/control-plane/scripts/run-cli.sh`, so on WSL they can fall back to `node.exe` 24+ when the Linux-side `node` is older.
If you need raw JSON without npm banners, add `--silent` before `--prefix`.
If you need the raw JSON output without npm banners, add `--silent` before `--prefix`.

The `package.json` script names mirror the CLI shape, for example:

- `project:register`, `project:list`, `project:show`
- `auth:probe`, `auth:status`
- `router:choose`, `usage:show`
- `queue:create`, `queue:status`, `queue:action`
- `approve:check`, `approve:grant`, `approval:exists`
- `run:prepare`, `run:launch`, `run:inspect`, `run:validate`
- `handoff:build`
- `telegram:registry`, `telegram:interactive`, `telegram:callback`, `telegram:poll`, `telegram:serve`, `telegram:simulate`
- `mounts:template`, `mounts:validate`
- `defaults:show`, `policy:show`

## First-time setup

### 1. Review what the installer created

```bash
cat docs/ai/project-overrides/remote-control.yaml
cat .runtime/install-summary.aai-canonical.json
```

### 2. Optional: manual overrides

If you want a non-interactive install, rerun the installer with flags instead of editing files by hand:

```bash
npm --prefix apps/control-plane run install:host -- \
  --project-id another-project \
  --repo-path /mnt/z/AI/another-project \
  --default-branch main \
  --planning-provider claude \
  --implementation-provider codex \
  --validation-provider codex
```

This still creates or reuses the portable config in the managed repo and keeps host-only values out of it.

### 3. Optional: register a project manually

```bash
npm --prefix apps/control-plane run project:register -- \
  --db .runtime/control-plane.db \
  --project-config docs/ai/project-overrides/remote-control.yaml \
  --repo-path "$PWD" \
  --chat-ids 1001 \
  --user-ids 2001
```

### 4. Optional: probe provider sessions explicitly

Secrets remain in the native provider homes. The control-plane stores only health and usage metadata in SQLite.

```bash
npm --prefix apps/control-plane run auth:probe -- \
  --db .runtime/control-plane.db \
  --provider claude \
  --cli-path "$(command -v claude)" \
  --session-home ~/.claude \
  --probe-args --version

npm --prefix apps/control-plane run auth:probe -- \
  --db .runtime/control-plane.db \
  --provider codex \
  --cli-path "$(command -v codex)" \
  --session-home ~/.codex \
  --probe-args --version
```

Inspect synced metadata:

```bash
npm --prefix apps/control-plane run auth:status -- --db .runtime/control-plane.db
npm --prefix apps/control-plane run usage:show -- --db .runtime/control-plane.db
```

If a provider exposes a machine-readable usage command on your host, rerun `auth probe` with `--usage-args ...` for that provider.

## Main operator flows

### Route a provider

```bash
npm --prefix apps/control-plane run router:choose -- \
  --db .runtime/control-plane.db \
  --project-config docs/ai/project-overrides/remote-control.yaml \
  --phase implementation \
  --provider auto
```

### Prepare and launch one run

```bash
npm --prefix apps/control-plane run run:prepare -- \
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
npm --prefix apps/control-plane run run:launch -- \
  --db .runtime/control-plane.db \
  --manifest .runtime/worktrees/aai-canonical-PRD-AAI-REMOTE-ORCHESTRATION-01/run-manifest.json \
  --mode process \
  --worker-command ./path/to/worker.js
```

Launch in Docker mode:

```bash
npm --prefix apps/control-plane run run:launch -- \
  --db .runtime/control-plane.db \
  --manifest .runtime/worktrees/aai-canonical-PRD-AAI-REMOTE-ORCHESTRATION-01/run-manifest.json \
  --mode docker
```

Inspect the run:

```bash
npm --prefix apps/control-plane run run:inspect -- \
  --db .runtime/control-plane.db \
  --run-id <run_id>
```

### Validate extra mounts

Print the allowlist template:

```bash
npm --prefix apps/control-plane run mounts:template
```

Validate requested mounts:

```bash
npm --prefix apps/control-plane run mounts:validate -- \
  --mounts "/home/me/shared-docs|/workspace/shared-docs|ro"
```

### Telegram control surface

Registry and interaction model:

```bash
npm --prefix apps/control-plane run telegram:registry -- \
  --config apps/control-plane/config/command-registry.json

npm --prefix apps/control-plane run telegram:interactive
```

Run the long-poll daemon:

```bash
npm --prefix apps/control-plane run telegram:serve -- \
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

1. Run the installer wizard.
   Expected: `.runtime/control-plane.db`, `docs/ai/project-overrides/remote-control.yaml`, `.runtime/install-summary.<project>.json`, `.runtime/control-plane.env`, and `.runtime/run-control-plane.sh` exist.
2. Check detected provider paths.
   Expected: the install summary shows Linux/WSL paths such as `/home/user/.local/bin/claude`, not guessed placeholder paths.
   Also expected: the installer prints the exact `bash .runtime/run-control-plane.sh` command.
3. Probe both provider sessions if you want an explicit refresh.
   Expected: `auth status` shows `status=ok` for installed CLIs.
   If one CLI is not installed, expected: `auth status` shows `status=missing` and auto-routing avoids it.
4. Prepare one run.
   Expected: a git worktree and `run-manifest.json` appear under `.runtime/worktrees`.
5. Launch one run in process mode.
   Expected: `run inspect` shows `status=done` and a log path.
6. Start Telegram daemon and send `/intake <project> <ref> <summary>`.
   Expected: work item becomes `queued` and bot responds with inline actions.
7. Press `Stop` or `Resume`.
   Expected: work item status changes in DB and bot confirms callback.
8. Run the full validation suite.
   Expected: all `26` tests print `PASS`.

## Automated verification

Run the complete suite:

```bash
npm --prefix apps/control-plane run validate:remote
```

Target result: `26/26 PASS`.

Focused checks:

```bash
npm --prefix apps/control-plane run test:remote:install
npm --prefix apps/control-plane run test:remote:provider-session
npm --prefix apps/control-plane run test:remote:run-launch
npm --prefix apps/control-plane run test:remote:telegram
npm --prefix apps/control-plane run test:remote:runtime-build
npm --prefix apps/control-plane run test:remote:npm
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
