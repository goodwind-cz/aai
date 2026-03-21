# AAI Control Plane

This is the runnable TypeScript control-plane for the remote-orchestration stack.

Operator onboarding:

- English: [docs/REMOTE_ORCHESTRATION_USER_GUIDE.md](../../docs/REMOTE_ORCHESTRATION_USER_GUIDE.md)
- Czech: [docs/REMOTE_ORCHESTRATION_USER_GUIDE.cs.md](../../docs/REMOTE_ORCHESTRATION_USER_GUIDE.cs.md)

## Runtime model

- Production host process: `node apps/control-plane/dist/cli.js`
- Development host process: `node --experimental-strip-types apps/control-plane/src/cli.ts`
- Host runtime state: SQLite in WAL mode
- Worker shape: manifest-first, git-worktree-backed launch with `process` and `docker` execution modes
- Operator surface: Telegram command registry, inline actions, callback handling, and long-poll daemon mode
- Docker subagent auth model: the selected provider session home is mounted read-only into the worker, but the worker image must already contain the matching `claude` or `codex` CLI
- Docker subagent memory model: the worker reads repo docs from `/workspace`, run metadata from `/workspace/.aai-control-plane-run.json`, and the explicit handoff packet from `/workspace/.aai-handoff.json`

## Direct inspirations

- `SuperTurtle`: headless CLI driver pattern, Telegram command surface, safe callback parsing, Claude/Codex dual-driver operation
- `NanoClaw`: single host process, SQLite runtime, explicit mount allowlist outside the repo, container-first isolation model

## Implemented modules

- `registry.ts`: multi-project registration and host-only bindings
- `provider-router.ts`: explicit, phase-aware, usage-aware provider routing plus CLI-subscription session probe/sync
- `queue.ts`: work items and durable approval records
- `runner.ts`: worktree allocation, manifest generation, process/docker launch, run inspection, handoff packet generation
- `telegram.ts`: command registry loading, inline actions, callback parsing, live Telegram polling/serve loop, session-aware project selection
- `mount-security.ts`: host-side allowlist validation for extra mounts
- `cli.ts`: thin operator-facing entrypoint for all above flows

## Prerequisites

- Node.js `>=20`
- `git`
- `bash`
- provider CLIs already authenticated in subscription mode on the host
- optional for container execution: Docker

## Install

```bash
npm --prefix apps/control-plane run install:wizard
```

The installer:

- runs `npm install` and `npm run build`
- initializes the host SQLite DB
- creates `docs/ai/project-overrides/remote-control.yaml` only if missing
- registers the project on the host
- auto-detects `claude` and `codex` CLIs from the current Linux/WSL shell
- probes provider binaries and stores host-side metadata in SQLite
- uses `claude auth status --json` as the default Claude subscription probe
- if a provider is already logged in, shows the current account and lets the operator keep it with Enter or switch with `s`
- if a provider is not logged in yet, offers to open the native interactive login flow immediately
- explains the browser or device-code style flow when the provider requires a link click and one-time code confirmation
- records missing CLIs as unavailable and tells the operator to install them manually instead of trying to use them
- reuses existing values from the last install summary, runtime env, project config, and SQLite registration so the operator can keep them by pressing Enter
- asks only a few setup questions and generates a ready-to-run launcher script
- if existing config/runtime files are detected, it asks `Overwrite existing config/runtime state? [y/N]`
- pressing Enter or `N` keeps the current config, DB, env, launcher, and summary files
- `y` rewrites config/runtime files and reinitializes the SQLite DB

In WSL the detected CLI path is typically the real Linux path, for example `$(command -v claude)` such as `/home/ales/.local/bin/claude`.

## Runtime commands

All operator-facing commands are available as npm scripts. The pattern is:

```bash
npm --prefix apps/control-plane run <script-name> -- <cli args>
```

Use `--` only when you need to pass flags through to the underlying CLI command.
The npm scripts run through `apps/control-plane/scripts/run-cli.sh`, which prefers a native Linux Node from `~/.nvm` on WSL hosts and only falls back to `node.exe` if needed.
If you want machine-readable JSON without npm banners, use `npm --silent --prefix apps/control-plane run ...`.

### Initialize runtime DB

```bash
npm --prefix apps/control-plane run build
npm --prefix apps/control-plane run init -- --db .runtime/control-plane.db
```

### Register a project manually

```bash
npm --prefix apps/control-plane run project:register -- \
  --db .runtime/control-plane.db \
  --project-config docs/ai/project-overrides/remote-control.yaml \
  --repo-path "$PWD" \
  --chat-ids 1001 \
  --user-ids 2001
```

### Probe host-authenticated provider sessions

```bash
npm --prefix apps/control-plane run auth:probe -- \
  --db .runtime/control-plane.db \
  --provider claude \
  --cli-path "$(command -v claude)" \
  --session-home ~/.claude \
  --probe-args auth,status,--json

npm --prefix apps/control-plane run auth:probe -- \
  --db .runtime/control-plane.db \
  --provider codex \
  --cli-path "$(command -v codex)" \
  --session-home ~/.codex \
  --probe-args --help
```

### Prepare and launch a run

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

npm --prefix apps/control-plane run run:launch -- \
  --db .runtime/control-plane.db \
  --manifest .runtime/worktrees/aai-canonical-PRD-AAI-REMOTE-ORCHESTRATION-01/run-manifest.json \
  --mode docker
```

### Run the Telegram daemon

```bash
bash .runtime/run-control-plane.sh start
```

Operator commands:

```bash
bash .runtime/run-control-plane.sh status
bash .runtime/run-control-plane.sh stop
bash .runtime/run-control-plane.sh restart
bash .runtime/run-control-plane.sh logs
bash .runtime/run-control-plane.sh probe
bash .runtime/run-control-plane.sh login claude
bash .runtime/run-control-plane.sh login codex
```

Equivalent npm shortcuts:

```bash
npm --prefix apps/control-plane run daemon:start
npm --prefix apps/control-plane run daemon:status
npm --prefix apps/control-plane run daemon:stop
npm --prefix apps/control-plane run daemon:restart
npm --prefix apps/control-plane run daemon:logs
npm --prefix apps/control-plane run daemon:probe
npm --prefix apps/control-plane run daemon:login:claude
npm --prefix apps/control-plane run daemon:login:codex
```

The launcher starts the Telegram daemon in the background and returns immediately. `status` shows whether the daemon is running, where the DB/logs are, and a readable provider/project summary. `probe` re-checks provider login state and reports whether usage telemetry is available. The launcher and CLI wrapper pass `--no-warnings`, so the `node:sqlite` experimental warning is suppressed in normal operator use.

Watch the structured daemon log:

```bash
bash .runtime/run-control-plane.sh logs
npm --prefix apps/control-plane run daemon:logs
```

### Script map

- `init`
- `project:register`, `project:list`, `project:show`
- `auth:validate`, `auth:probe`, `auth:mark-missing`, `auth:status`
- `router:choose`, `usage:show`
- `queue:create`, `queue:status`, `queue:action`
- `approve:check`, `approve:grant`, `approval:exists`
- `run:prepare`, `run:launch`, `run:inspect`, `run:validate`
- `handoff:build`
- `telegram:registry`, `telegram:interactive`, `telegram:callback`, `telegram:get-me`, `telegram:setup-info`, `telegram:poll`, `telegram:serve`, `telegram:simulate`
- `serve:generated`, `daemon:start`, `daemon:status`, `daemon:stop`, `daemon:restart`, `daemon:logs`, `daemon:probe`, `daemon:login:claude`, `daemon:login:codex`
- `mounts:template`, `mounts:validate`
- `defaults:show`, `policy:show`
- `test:remote`, `test:remote:install`, `test:remote:provider-session`, `test:remote:run-launch`, `test:remote:telegram`, `test:remote:telegram-setup`, `test:remote:runtime-build`, `test:remote:daemon`, `test:remote:npm`, `validate:remote`

## Verification

```bash
npm --prefix apps/control-plane run validate:remote
```

The current suite contains `33` CLI-backed tests, including:
- provider session probe and usage sync
- live Telegram long-poll fixture flow
- Telegram token and ID discovery helpers for onboarding
- real run launch with worktree/log artifacts
- standard `tsc -> dist` runtime verification
- one-command host installer flow
- missing-provider fallback and operator install prompt behavior
- interactive install wizard with generated run command
- background daemon start/status/stop/probe/login flow
- wizard reuse of existing values with preserve-vs-overwrite state handling
- wizard fallback to the existing managed repo path when one install state is already known
- wizard provider-login UX for keeping the current subscription session or reopening a browser/device-code style login flow
- docker subagent contract coverage for read-only session mount and explicit handoff packet transfer
- npm wrapper coverage for the documented operator command surface

`green` in the remote-orchestration spec is backed by executable control-plane flows, not by file-content smoke checks.
