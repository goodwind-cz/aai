# AAI Remote Orchestration PRD

## Intent
- Build a remote orchestration layer for AAI that lets an operator control feature development from Telegram while preserving AAI's repo-first workflow, frozen specifications, test evidence, and validation reports.
- The system must run primarily on Linux under WSL-hosted environments, isolate execution in Docker workers with mounted project worktrees, and support both Claude Code and Codex as configurable providers authenticated through host-level CLI subscription sessions.

## Scope
- In scope:
  - A central host-level `aai-control-plane` process for queueing, orchestration, provider routing, approvals, and reporting.
  - Per-task git worktrees and Docker-isolated workers for planning, implementation, validation, and reporting.
  - Telegram bot flows aligned with AAI skills and enriched with interactive controls such as inline buttons, menus, and Telegram Web App forms when useful.
  - Dual-provider operation with Claude Code and Codex, including host-level headless CLI subscription authentication, provider preference rules, and usage-aware routing.
  - Multi-project onboarding where one host installation manages multiple project repositories through project-local registration and configuration.
  - Repo-first persistence of requirements, specs, decisions, reports, and AAI state.
- Out of scope:
  - Kubernetes or multi-host distributed scheduling in `v1`.
  - A separate full web dashboard as the primary operator interface.
  - Shared autonomous long-term vector memory as a source of truth.
  - Automatic billing reconciliation against provider invoices.
  - Broad provider support beyond Claude Code and Codex in `v1`.

## Acceptance Criteria
- AC-001: `v1` can be installed once on a Linux host or Linux-in-WSL host and manage multiple registered project repositories without copying the whole service into each project.
- AC-002: Every executable work item runs in an isolated git worktree and an associated Docker container bound only to that worktree and required read-only support mounts.
- AC-003: A registered project can declare remote-control preferences and routing policy through portable project-local configuration and project-local AAI skills without polluting canonical sync-managed assets.
- AC-003a: Host-specific bindings such as absolute repository path, Telegram allowlists, provider session health, and runtime queue state are stored only in host runtime storage, not in project repos.
- AC-004: Telegram can create, inspect, approve, pause, resume, and stop work items without the chat becoming the source of truth for requirements, specs, test plans, or reports.
- AC-005: The system supports both Claude Code and Codex, including explicit provider selection, task-class preference, and fallback policy when one provider is unavailable or over budget.
- AC-005a: `v1` uses only host-authenticated CLI subscription sessions for Claude Code and Codex; direct API-key or token-based provider mode is not supported.
- AC-006: The system exposes a `/usage`-style budget view that reports provider quota windows, current usage percentage, and next reset time, and the router can use that signal to reduce concurrency or switch providers.
- AC-007: Telegram command flows are aligned with existing AAI skills where they overlap, including intake, status, logs, validation, approvals, and worktree-oriented execution.
- AC-008: Telegram interactions use structured controls where possible, including inline approve/reject buttons, project pickers, provider pickers, and form-style task submission for high-friction inputs.
- AC-009: AAI state, frozen specs, test plans, decisions, and reports remain repo-first artifacts; runtime coordination state that does not belong in the repo is stored separately by the controller.
- AC-010: Each run produces an auditable manifest containing project, branch, worktree, container image, provider, input document references, commit SHA, and output artifact references.
- AC-011: `v1` defaults to resource-saving behavior: a single long-lived controller process, SQLite for runtime state, default concurrency of `1`, and no mandatory Redis, Postgres, or always-on worker pool.
- AC-012: The memory model for `v1` relies on repo docs plus explicit handoff payloads and controller runtime state; no hidden shared memory is required for correctness.
- AC-012a: When a work item runs in Docker, the worker receives provider login context only through a read-only mount of the selected provider session home plus explicit env hints; the worker image itself must already contain the corresponding CLI binary.
- AC-013: Operator approvals must gate implementation and validation transitions, and the approval trail must be preserved as durable artifacts.
- AC-013a: `Approve implementation` requires at minimum a PRD, a frozen spec, a test plan, a selected project, a selected provider policy, and a generated worktree manifest.
- AC-013b: `Approve validation` requires at minimum an implementation summary, changed-file summary, validation command set, and report/evidence target paths.
- AC-014: The feature includes a documented migration path from manual local AAI use toward remote-controlled multi-project operation without breaking existing canonical workflows.

## Non-functional constraints
- Prioritize Linux filesystem paths inside WSL over `/mnt/c` mounts for active repositories.
- Worker containers must not receive the Docker socket.
- Host-level Telegram secrets and provider CLI session material must stay outside project repositories.
- No provider API keys or long-lived API tokens are required or stored by `v1`.
- The control plane should remain usable on modest hardware and tolerate host restarts by recovering runtime state from durable local storage.
- The operator experience should minimize manual typing in Telegram for common actions.

## Notes
- Preferred deployment shape for `v1` is one host-level service plus ephemeral Docker workers.
- Provider preference is policy-driven and may differ by phase, for example planning vs implementation.
- This document defines WHAT/WHY, not HOW.
