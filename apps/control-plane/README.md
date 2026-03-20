# AAI Control Plane

This is the runnable TypeScript control-plane for the remote-orchestration stack.

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

- Node.js `>=24`
- `git`
- `bash`
- provider CLIs already authenticated in subscription mode on the host
- optional for container execution: Docker

## Install

```bash
cd apps/control-plane
npm install
npm run build
node dist/cli.js help
```

## Runtime commands

### Initialize runtime DB

```bash
node apps/control-plane/dist/cli.js init --db .runtime/control-plane.db
```

### Register a project

```bash
node apps/control-plane/dist/cli.js project register \
  --db .runtime/control-plane.db \
  --project-config docs/ai/project-overrides/remote-control.yaml \
  --repo-path "$PWD" \
  --chat-ids 1001 \
  --user-ids 2001
```

### Probe host-authenticated provider sessions

```bash
node apps/control-plane/dist/cli.js auth probe \
  --db .runtime/control-plane.db \
  --provider claude \
  --cli-path /usr/local/bin/claude \
  --session-home ~/.claude \
  --probe-args probe \
  --usage-args usage
```

### Prepare and launch a run

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

node apps/control-plane/dist/cli.js run launch \
  --db .runtime/control-plane.db \
  --manifest .runtime/worktrees/aai-canonical-PRD-AAI-REMOTE-ORCHESTRATION-01/run-manifest.json \
  --mode docker
```

### Run the Telegram daemon

```bash
node apps/control-plane/dist/cli.js telegram serve \
  --db .runtime/control-plane.db \
  --token "$TELEGRAM_BOT_TOKEN" \
  --approval-config apps/control-plane/config/approval-gates.json
```

## Verification

```bash
bash tests/remote-orchestration/run-all.sh
```

The current suite contains `22` CLI-backed tests, including:
- provider session probe and usage sync
- live Telegram long-poll fixture flow
- real run launch with worktree/log artifacts
- standard `tsc -> dist` runtime verification

`green` in the remote-orchestration spec is backed by executable control-plane flows, not by file-content smoke checks.
