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
- Parallel fan-out model: each bounded child task gets its own `task_key`, isolated worktree, manifest, container name, and handoff packet; auto-routing stays conservative unless provider usage telemetry permits more lanes

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
- uses `codex login status` as the default Codex subscription probe
- follows the SuperTurtle-style rule that install/start reuse your existing native CLI authentication instead of trapping OAuth inside the wrapper
- generates explicit `auth setup`, `auth status`, and `usage` launcher commands after install
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
  --probe-args login,status
```

### Prepare and launch a run

```bash
npm --prefix apps/control-plane run run:prepare -- \
  --db .runtime/control-plane.db \
  --project-id aai-canonical \
  --ref-id PRD-AAI-REMOTE-ORCHESTRATION-01 \
  --task-key backend-diff \
  --parallel-group impl-fanout \
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
bash .runtime/run-control-plane.sh start-debug 9230
bash .runtime/run-control-plane.sh debug 9230
bash .runtime/run-control-plane.sh probe
bash .runtime/run-control-plane.sh auth setup
bash .runtime/run-control-plane.sh auth status
bash .runtime/run-control-plane.sh usage
```

Equivalent npm shortcuts:

```bash
npm --prefix apps/control-plane run daemon:start
npm --prefix apps/control-plane run daemon:status
npm --prefix apps/control-plane run daemon:stop
npm --prefix apps/control-plane run daemon:restart
npm --prefix apps/control-plane run daemon:logs
npm --prefix apps/control-plane run daemon:probe
npm --prefix apps/control-plane run daemon:auth:setup
npm --prefix apps/control-plane run daemon:auth:status
npm --prefix apps/control-plane run daemon:usage
```

The launcher starts the Telegram daemon in the background and returns immediately. `auth setup` reuses existing native Claude/Codex CLI login and, when a provider is not ready, prints the exact native login command without trying to drive OAuth inside the wrapper. `auth status` shows provider readiness and routing capacity hints. `usage` shows provider usage telemetry when available plus the recommended number of parallel lanes. The launcher and CLI wrapper pass `--no-warnings`, so the `node:sqlite` experimental warning is suppressed in normal operator use.

### Debug startup variants

Use these launcher variants when you want to attach VS Code to the running Node process:

```bash
# Background daemon with Node inspector
bash .runtime/run-control-plane.sh start-debug 9230

# Foreground daemon with Node inspector
bash .runtime/run-control-plane.sh debug 9230
```

Preferred VS Code profile in `.vscode/launch.json`:

- `AAI Control Plane: TS Breakpoints (One Click)`

This profile runs pre-launch tasks that:

- build TypeScript once
- start the control-plane in foreground debug mode on port 9230
- start `tsc --watch` for incremental rebuilds

You can use any free port in range 1-65535.

If breakpoints do not stop:

- confirm the selected profile is `AAI Control Plane: TS Breakpoints (One Click)`
- check that the breakpoint is solid red (not hollow/unbound)
- run `npm --prefix apps/control-plane run build` once to refresh `dist/*.map`
- place the first breakpoint in a path that is definitely hit by your action

For example, Telegram `/usage` hits capacity rendering paths (`describeProviderCapacity`), while provider selection (`chooseProvider`) is hit by routing commands such as `router choose` or run preparation/launch flows.

### WSL auth troubleshooting

If `auth status` reports `error` even though direct `claude`/`codex` commands work, check provider command resolution first.

```bash
type -a claude
type -a codex
```

On WSL, the first resolved path should be a Linux path (for example `/home/<user>/.local/bin/claude` and `/home/<user>/.nvm/.../bin/codex`), not a Windows shim under `/mnt/c/Users/.../AppData/Roaming/npm`.

Quick recovery for Codex optional dependency errors on WSL:

```bash
npm install -g @openai/codex@latest --include=optional
hash -r
codex --version
```

Then re-run:

```bash
bash .runtime/run-control-plane.sh auth status
```

Expected healthy state:

- both providers show `status: ok`
- `dispatch` is not `blocked`
- `usage` may still be unavailable and keep routing conservative (`recommended_parallel_runs=1`) until telemetry is synced

Watch the structured daemon log:

```bash
bash .runtime/run-control-plane.sh logs
npm --prefix apps/control-plane run daemon:logs
```

If structured logging has no entries yet, `logs` automatically falls back to the console log and prints an explicit fallback message instead of staying silent.

### Script map

- `init`
- `project:register`, `project:list`, `project:show`
- `auth:validate`, `auth:probe`, `auth:mark-missing`, `auth:status`
- `auth:validate`, `auth:probe`, `auth:mark-missing`, `auth:status`
- `router:choose`, `usage:show`
- `queue:create`, `queue:status`, `queue:action`
- `approve:check`, `approve:grant`, `approval:exists`
- `run:prepare`, `run:launch`, `run:inspect`, `run:validate`
- `handoff:build`
- `telegram:registry`, `telegram:interactive`, `telegram:callback`, `telegram:get-me`, `telegram:setup-info`, `telegram:poll`, `telegram:serve`, `telegram:simulate`
- `serve:generated`, `daemon:start`, `daemon:status`, `daemon:stop`, `daemon:restart`, `daemon:logs`, `daemon:probe`, `daemon:auth:setup`, `daemon:auth:status`, `daemon:usage`, `daemon:login:claude`, `daemon:login:codex`
- `mounts:template`, `mounts:validate`
- `defaults:show`, `policy:show`
- `test:remote`, `test:remote:install`, `test:remote:provider-session`, `test:remote:run-launch`, `test:remote:telegram`, `test:remote:telegram-setup`, `test:remote:runtime-build`, `test:remote:daemon`, `test:remote:npm`, `validate:remote`

## Verification

```bash
npm --prefix apps/control-plane run validate:remote
```

The current suite contains `34` CLI-backed tests, including:
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
- separate auth-setup flow that reuses native CLI sessions after install and prints direct provider login commands instead of trapping OAuth inside the wrapper
- docker subagent contract coverage for read-only session mount and explicit handoff packet transfer
- parallel subtask shard coverage for unique worktree/container lanes under one parent work item
- npm wrapper coverage for the documented operator command surface

`green` in the remote-orchestration spec is backed by executable control-plane flows, not by file-content smoke checks.
