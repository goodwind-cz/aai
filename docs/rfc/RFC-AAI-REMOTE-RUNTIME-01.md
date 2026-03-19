# RFC-AAI-REMOTE-RUNTIME-01

## Summary
This RFC proposes a remote runtime for AAI based on a single host-level control plane, per-task git worktrees, and Docker-isolated workers. Telegram is the primary operator interface, but repository artifacts remain the source of truth for workflow state, requirements, specs, evidence, and reports.

## Problem
AAI currently assumes local, session-bound execution. The desired model is different:
- operators should be able to drive work remotely from Telegram;
- agent execution should remain isolated and reproducible;
- multiple projects should be managed from one host installation;
- provider choice should span Claude Code and Codex;
- the system must stay resource-efficient and preserve AAI's disciplined docs/state flow.

## Goals
- Provide a Linux-first, WSL-friendly runtime that can orchestrate AAI work remotely.
- Reuse AAI workflow semantics instead of inventing a parallel control model.
- Keep each task isolated via `branch -> worktree -> container`.
- Make Telegram interactions skill-aligned and low-friction.
- Support provider-aware routing using subscription/usage signals.
- Preserve deployability into downstream projects by keeping project-specific runtime concerns outside canonical synced assets.

## Non-goals
- Running a permanent worker fleet.
- Building a generic cluster scheduler.
- Treating Telegram chat history as persistent project memory.
- Replacing frozen spec driven implementation with free-form chat execution.

## Decision
Adopt a single long-lived `aai-control-plane` Node/TypeScript process running on the Linux host, preferably as a `systemd --user` service. Use Docker only for ephemeral task runners. `docker compose` is optional for local packaging and support services, but it is not the primary orchestration mechanism.

### Why not `docker compose` as the main scheduler
- Compose is optimized for static service topology, not dynamic per-task worker creation.
- Running the controller inside Docker would usually require Docker socket access or another remote Docker API path, which weakens isolation.
- A direct host process can manage worktrees, local files, provider CLIs, SQLite, and system services with less overhead.
- The resource-saving target of `v1` is better met by one idle controller plus zero active workers.

### Recommended runtime mode
- `aai-control-plane` runs on the host as a Node process.
- SQLite in WAL mode stores queue state, leases, chat sessions, provider usage snapshots, and run registry data.
- Telegram integration uses long polling in `v1` to avoid extra ingress requirements.
- Each executable run spawns a Docker container with:
  - one writable mount for the assigned worktree,
  - optional read-only cache/config mounts,
  - explicit CPU/memory limits,
  - no Docker socket.

## Architecture

### Components
- `aai-control-plane`
  - owns queueing, approvals, provider routing, runtime persistence, and Telegram integration
- `project-registry`
  - maps project IDs to local repository paths, default providers, limits, and allowed commands
- `worktree-manager`
  - creates and cleans task-scoped worktrees and branches
- `provider-router`
  - chooses Claude Code or Codex based on phase, project policy, operator override, and usage budget
- `runner-launcher`
  - builds task manifests and starts Docker workers
- `report-publisher`
  - writes manifests and chat-facing summaries with links to repo artifacts

### Core execution model
- One work item maps to one branch, one worktree, and one worker container.
- Planner, implementer, and validator may run as separate runs against the same worktree, but each run is individually manifested.
- Subagents, if introduced later, must receive child worktrees rather than sharing one writable mount.

## Multi-project installation and onboarding
- Install the control plane once on the host.
- Register each managed project with a local command such as `/aai-remote-register`.
- Store project-local runtime configuration outside sync-managed canonical assets, for example under `docs/ai/project-overrides/remote-control.yaml`.
- Generate lightweight project-local skills for convenience, while keeping canonical universal skills in the AAI layer.

### Config ownership split
- Canonical AAI repo owns:
  - universal prompts, skills, schemas, and templates
  - product/architecture docs such as PRD, RFC, and SPEC
- Project repo owns portable project settings:
  - `project_id`
  - `default_branch`
  - `default_provider_policy`
  - `phase_provider_preferences`
  - `allowed_docker_profile`
  - optional project-specific command restrictions
- Host runtime owns non-portable operational bindings:
  - absolute local repository path
  - allowed Telegram users and chat IDs
  - provider CLI session health and usage snapshots
  - queue state, schedules, run manifests, and leases

This split keeps downstream deployment portable while still allowing one host to manage many local checkouts.

### Why this deployment model
- It matches the user's requirement for one host managing multiple projects.
- It avoids copying host secrets and daemon config into downstream repositories.
- It preserves the current AAI sync/update model where canonical assets stay reusable and project specifics remain local.

## Provider model

### Authentication
- Provider access is managed on the host through installed CLIs authenticated against the user's subscription in headless mode, not through direct API keys.
- The controller detects and validates availability of Claude Code and Codex separately.
- Direct API mode is out of scope for `v1`.
- Project config and operator commands can select:
  - preferred provider,
  - fallback provider,
  - phase-specific preference,
  - strict single-provider mode.

### Routing policy
- Planning and research may prefer one provider while implementation or review prefers another.
- Operator override from Telegram always wins for the current work item unless forbidden by project policy.
- Budget-aware routing uses subscription quota window, usage percentage, cooldown, and reset time rather than pretending a stable provider-agnostic "tokens remaining" number always exists.

### `SuperTurtle` influence
- `SuperTurtle` demonstrates the value of a chat-first agent controller and provider/session awareness.
- The AAI design keeps that interaction style but separates it from a stricter repo-first execution model and a provider router that treats Claude Code and Codex as first-class peers.

## Memory model

### Source of truth
- Repository docs remain authoritative:
  - `docs/requirements/*`
  - `docs/specs/*`
  - `docs/decisions/*` when present
  - `docs/ai/STATE.yaml`
  - `docs/ai/reports/*`
  - `docs/knowledge/*`

### Runtime memory
- Controller-local SQLite stores:
  - chat sessions,
  - active jobs,
  - leases,
  - provider usage snapshots,
  - run registry,
  - approval events.

### Handoff memory
- Every worker run receives an explicit handoff payload assembled from repo truth and runtime metadata.
- Worker outputs are merged back into repo artifacts and runtime records.
- `v1` does not require a vector database. Retrieval or embeddings may be added later as read-only acceleration, not as authority.

## Telegram interface

### Command philosophy
- Reuse AAI skill concepts where possible.
- Mirror successful `SuperTurtle` patterns where they improve operator ergonomics.
- Prefer structured interactions over free-form typing for high-frequency actions.

### Core commands
- `/new` or `/intake`
  - start a new work item
- `/status`
  - show queue, active runs, approvals, and latest evidence
- `/usage`
  - show provider budget state and routing implications
- `/provider`
  - choose provider policy for current work item
- `/projects`
  - select or inspect managed projects
- `/approve`
  - approve a waiting gate
- `/stop`
  - stop a queued or running work item
- `/resume`
  - continue a paused work item
- `/logs`
  - show controller or run logs
- `/agents`
  - show active workers and subagents
- `/schedule`
  - inspect or create scheduled jobs
- `/debug`
  - show runtime diagnostics intended for operators

### Rich Telegram UX
- Inline buttons for approve/reject, resume/stop, provider selection, and project selection.
- Reply keyboards for common actions after each status response.
- Telegram Web App form for rich task submission when scope, project, provider, and approval policy must be selected together.
- Tables should be rendered as aligned code blocks or compact sections when native tables are unavailable.

## Approval gates

### `Approve implementation`
This gate becomes available only when all of the following exist:
- PRD reference
- frozen SPEC reference
- test plan reference
- selected project
- selected provider policy
- generated branch/worktree manifest

### `Approve validation`
This gate becomes available only when all of the following exist:
- implementation summary
- changed-file summary
- validation command set
- report target path
- evidence target path

This is intentionally stricter than `SuperTurtle`, because AAI is preserving repo-first requirements, specs, test plans, and reports as auditable artifacts.

## Resource policy
- Default concurrency is `1`.
- Workers are launched only when work exists.
- No warm pool in `v1`.
- The controller performs low-frequency background checks for provider health and scheduled jobs.
- Support services are limited to SQLite and local files in `v1`.

## Security boundaries
- No Docker socket inside workers.
- No writable access outside the assigned worktree.
- Host secrets remain host-scoped.
- Project registration must allow an allowlist of executable commands and images.

## Delivery phases
- Phase 1:
  - branch/worktree setup, PRD/RFC/SPEC, and runtime schemas
- Phase 2:
  - host controller skeleton, project registry, SQLite runtime model
- Phase 3:
  - Telegram bot flows and provider routing
- Phase 4:
  - Docker runners, approvals, manifests, validation/report publishing
- Phase 5:
  - multi-project fixtures, resource tuning, and operator hardening

## Remaining work
- Define concrete SQLite tables and file layout for the host runtime.
- Define the exact schema for `docs/ai/project-overrides/remote-control.yaml`.
- Implement provider telemetry adapters for CLI-only subscription mode.
