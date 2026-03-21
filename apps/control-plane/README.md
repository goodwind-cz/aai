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
- records missing CLIs as unavailable and tells the operator to install them manually instead of trying to use them
- asks only a few setup questions and generates a ready-to-run launcher script

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
  --probe-args --version
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
npm --prefix apps/control-plane run serve:generated
```

The launcher and CLI wrapper pass `--no-warnings`, so the `node:sqlite` experimental warning is suppressed in normal operator use.

Watch the structured daemon log:

```bash
npm --prefix apps/control-plane run logs:tail
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
- `mounts:template`, `mounts:validate`
- `defaults:show`, `policy:show`
- `test:remote`, `test:remote:install`, `test:remote:provider-session`, `test:remote:run-launch`, `test:remote:telegram`, `test:remote:telegram-setup`, `test:remote:runtime-build`, `test:remote:npm`, `validate:remote`

## Verification

```bash
npm --prefix apps/control-plane run validate:remote
```

The current suite contains `27` CLI-backed tests, including:
- provider session probe and usage sync
- live Telegram long-poll fixture flow
- Telegram token and ID discovery helpers for onboarding
- real run launch with worktree/log artifacts
- standard `tsc -> dist` runtime verification
- one-command host installer flow
- missing-provider fallback and operator install prompt behavior
- interactive install wizard with generated run command
- npm wrapper coverage for the documented operator command surface

`green` in the remote-orchestration spec is backed by executable control-plane flows, not by file-content smoke checks.
