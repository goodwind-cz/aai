# SPEC-AAI-TELEGRAM-CONTROL-01

## Goal
Define the Telegram-facing control surface, project registration model, and budget-aware provider behavior for the AAI remote orchestration feature.

## Scope
- Telegram commands, aliases, and interactive flows.
- Mapping between Telegram actions and existing AAI concepts/skills.
- Provider selection and `/usage` behavior.
- Project registration and multi-project switching.
- Worktree and deployability rules for downstream projects.

## Command registry

| Command | Aliases | Purpose | AAI alignment |
|---|---|---|---|
| `/intake` | `/new` | Create a new work item | `aai-intake` |
| `/status` |  | Show active queue, approvals, and latest evidence | orchestration state |
| `/usage` |  | Show provider budget/quota status and router recommendation | provider router |
| `/provider` | `/switch`, `/model` | Override or inspect provider choice for the current work item | provider policy |
| `/projects` |  | List managed projects and select default target | project registry |
| `/register` | `/aai-remote-register` | Register current project with the host controller | project onboarding |
| `/approve` |  | Approve a waiting gate such as implementation or validation | HITL/approvals |
| `/resume` |  | Resume a paused work item | orchestration control |
| `/stop` |  | Cancel or stop a queued/running work item | orchestration control |
| `/logs` | `/looplogs`, `/pinologs` | Fetch controller logs or a specific run log bundle | diagnostics |
| `/agents` | `/sub` | Show active workers and child tasks | worker visibility |
| `/schedule` | `/cron` | Inspect or create a scheduled run | scheduled orchestration |
| `/context` |  | Show the frozen spec, current focus, and key artifact links | repo truth summary |
| `/debug` |  | Show runtime diagnostics for operators | support mode |
| `/restart` |  | Restart controller-managed bot session or a failed run where safe | operations |

## Command behavior requirements
- Spec-AC-001: `/intake` must require project selection before a work item is enqueued when multiple projects are registered and no default project is set.
- Spec-AC-002: `/status` must show at minimum project, ref ID, branch, phase, provider, gate state, and last report artifact.
- Spec-AC-003: `/usage` must show both Claude Code and Codex budget state side by side when both are configured.
- Spec-AC-004: `/provider` must support `auto`, `claude`, `codex`, and `project-default`.
- Spec-AC-005: `/approve` must only appear as an enabled action when a gate is explicitly waiting.
- Spec-AC-006: `/register` must create or update project-local remote control configuration rather than embedding host secrets in the repo.
- Spec-AC-007: `/logs` must support a concise summary mode and a detailed mode for one selected run.
- Spec-AC-008: `/context` must summarize repo-first truth from `STATE.yaml`, frozen requirements/specs, and latest reports.
- Spec-AC-009: interactive buttons must exist for common state transitions so the operator does not need to type commands for approve, stop, resume, provider switch, or project switch.
- Spec-AC-010: command names and aliases should remain compatible with `SuperTurtle` expectations where that does not conflict with AAI semantics.
- Spec-AC-011: project registration and operator setup must never ask for provider API keys; provider availability is derived only from host-installed authenticated CLIs.

## Interactive UX

### Primary inline actions
- `Approve implementation`
- `Approve validation`
- `Pause`
- `Resume`
- `Stop`
- `Use Claude`
- `Use Codex`
- `Use Auto Router`
- `Switch Project`
- `Open Latest Report`

### Reply keyboard defaults
- `New Task`
- `Status`
- `Usage`
- `Projects`
- `Logs`

### Telegram Web App flow
- Use a compact form when a new task needs:
  - project
  - title
  - description
  - requested phase target
  - provider preference
  - approval policy
- The Web App submits structured JSON to the control plane, which then writes repo-first artifacts before any implementation run starts.

## Provider usage policy
- Usage data should be captured as:
  - provider name
  - time window label
  - used percentage
  - reset timestamp
  - collection timestamp
  - optional per-run CLI-reported usage statistics
- Router policy:
  - `0-70%`: normal routing
  - `70-85%`: prefer project default but reduce background work
  - `85-95%`: prefer alternate provider when allowed
  - `95%+`: require explicit operator override or wait until reset
- If no provider telemetry is available from the authenticated CLI, the system reports uncertainty explicitly and falls back to configured preference instead of inventing precision.

## Project registration model
- The host installation maintains a registry database of projects.
- Each project stores its local remote-control settings in `docs/ai/project-overrides/remote-control.yaml`.
- Project-local generated skills may exist under `.claude/skills/`, `.codex/skills/`, or `.gemini/skills/` using unique `aai-*` names so sync preserves them.
- Registration must capture:
  - project ID
  - local repo path
  - default branch
  - allowed Docker image profile
  - default provider policy
  - allowed Telegram users or chat IDs
- Registration must not capture provider API credentials.

## Worktree and deployability rules
- Worktree-local runtime progress lives in that worktree's `docs/ai/STATE.yaml`.
- Host runtime data must not be written into sync-managed canonical assets unless it is a repo-first artifact by design.
- Controller-only runtime files belong in host storage, not inside project repos.
- Downstream deploy validation must use fixture projects to ensure the remote-control feature does not pollute ordinary AAI sync/update flows.

## Initial test plan
- TEST-001: registering one project creates project-local config and host registry entry.
- TEST-002: registering a second project forces project selection in Telegram before `/intake`.
- TEST-003: `/usage` renders both providers and the router recommendation.
- TEST-004: `/provider codex` overrides an auto-routed task and is visible in `/status`.
- TEST-005: `/approve` button appears only when a gate is waiting.
- TEST-006: `/logs` summary and detailed run modes both resolve the correct run.
- TEST-007: `/register` never writes host secrets into project files.
- TEST-008: one work item results in one branch, one worktree, and one worker manifest.
- TEST-009: project fixture sync/update still preserves project-local dynamic skills and remote-control config.
- TEST-010: operator can complete a common path of `project select -> intake -> approve -> status -> logs` with buttons only.
