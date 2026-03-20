# AAI Control Plane MVP

This is a runnable TypeScript MVP for the remote-orchestration control plane.

## Runtime model

- Host process: `node.exe --experimental-strip-types apps/control-plane/src/cli.ts`
- Host runtime state: SQLite in WAL mode
- Worker shape: manifest-first, Docker-ready run preparation
- Operator surface: Telegram command registry plus interactive action model

## Direct inspirations

- `SuperTurtle`: headless CLI driver pattern, Telegram command surface, safe callback parsing, Claude/Codex dual-driver operation
- `NanoClaw`: single host process, SQLite runtime, explicit mount allowlist outside the repo, container-first isolation model

## Implemented modules

- `registry.ts`: multi-project registration and host-only bindings
- `provider-router.ts`: explicit, phase-aware, usage-aware provider routing
- `queue.ts`: work items and durable approval records
- `runner.ts`: worktree directory allocation, manifest generation, handoff packet generation
- `telegram.ts`: command registry loading, inline actions, callback parsing, simulated Telegram lifecycle
- `mount-security.ts`: host-side allowlist validation for extra mounts
- `cli.ts`: thin operator-facing entrypoint for all above flows

## Example commands

```bash
node --experimental-strip-types apps/control-plane/src/cli.ts init --db .runtime/control-plane.db

node --experimental-strip-types apps/control-plane/src/cli.ts project register \
  --db .runtime/control-plane.db \
  --project-config docs/ai/project-overrides/remote-control.yaml \
  --repo-path "$PWD" \
  --chat-ids 1001 \
  --user-ids 2001

node --experimental-strip-types apps/control-plane/src/cli.ts run prepare \
  --db .runtime/control-plane.db \
  --project-id aai-canonical \
  --ref-id PRD-AAI-REMOTE-ORCHESTRATION-01 \
  --repo-path "$PWD" \
  --project-config docs/ai/project-overrides/remote-control.yaml \
  --worktrees-root .runtime/worktrees \
  --container-image ghcr.io/example/aai-worker:preview \
  --provider auto
```

## Verification

```bash
bash tests/remote-orchestration/run-all.sh
```

`green` in the remote-orchestration spec is now backed by this CLI and the test suite above, not by file-content smoke checks.
