# Implementation Spec: PRD-AAI-REMOTE-ORCHESTRATION-01

## Links
- Requirement: [PRD-AAI-REMOTE-ORCHESTRATION-01](../requirements/PRD-AAI-REMOTE-ORCHESTRATION-01.md)
- Decision records: n/a
- Technology contract: [docs/TECHNOLOGY.md](../TECHNOLOGY.md)

## Spec status
- SPEC-FROZEN: true

## Implementation restart note
- This implementation was restarted from the already-created intake artifacts (`PRD`, `RFC`, `SPEC`) after detecting that the earlier branch state only proved contract files, not a runnable control-plane.
- Corrected guardrail sentence: the failure was not only that a documented contract was mistaken for finished implementation, but that the branch lacked a hard DoD and release gate requiring a runnable control-plane, CLI-backed end-to-end verification, and validation evidence before any TEST-xxx or `last_validation` could be marked green/pass.
- From this point forward, remote-orchestration `green` means the TypeScript CLI in `apps/control-plane/src/cli.ts` executed successfully through the corresponding test flow.
- Implementation direction is intentionally derived from `SuperTurtle` and `NanoClaw`: headless CLI providers and Telegram command ergonomics from `SuperTurtle`, host-side mount isolation and single-process runtime shape from `NanoClaw`.
- Reopened on `2026-03-20` because the branch still lacked the remaining runtime-critical parts required by the PRD/RFC: real provider session probing/usage sync, actual worker launch, a long-lived host process, and a live Telegram polling adapter.

## Acceptance Criteria Mapping

| Requirement AC | Spec-AC | Verifiable implementation statement | Verification (command + expected evidence) |
|---|---|---|---|
| AC-001 | Spec-AC-001 | Control plane can register and operate at least two projects from one host install. | `bash tests/remote-orchestration/test-001-multi-project-registration.sh` -> report shows two active project records. |
| AC-002 | Spec-AC-002 | Every run creates one branch, one worktree, one container manifest with scoped mounts. | `bash tests/remote-orchestration/test-002-worktree-container-isolation.sh` -> manifest proves 1:1 mapping and mount scope. |
| AC-003 | Spec-AC-003 | Project-local portable policy file controls provider defaults and routing policy. | `bash tests/remote-orchestration/test-003-project-policy-load.sh` -> loaded policy matches project override file. |
| AC-003a | Spec-AC-004 | Host-only bindings (repo path, chat ACL, provider session state, queue) are excluded from project repo config. | `bash tests/remote-orchestration/test-004-host-only-bindings.sh` -> host DB contains bindings, repo config omits them. |
| AC-004 | Spec-AC-005 | Telegram can create, inspect, approve, pause, resume, and stop work items without mutating requirement/spec sources in chat. | `bash tests/remote-orchestration/test-005-telegram-control-flow.sh` -> command flow succeeds and writes repo artifacts. |
| AC-005 | Spec-AC-006 | Provider router supports explicit `claude`/`codex` selection plus auto/fallback policy. | `bash tests/remote-orchestration/test-006-provider-routing.sh` -> router decisions include explicit and fallback branches. |
| AC-005a | Spec-AC-007 | Provider auth supports only host CLI subscription sessions; API keys are rejected in config validation. | `bash tests/remote-orchestration/test-007-cli-subscription-only.sh` -> API credential fields fail validation. |
| AC-006 | Spec-AC-008 | `/usage` reports provider quota windows when telemetry exists and otherwise returns readiness plus conservative routing capacity hints. | `bash tests/remote-orchestration/test-008-usage-view.sh` -> structured usage payload contains required fields and capacity guidance. |
| AC-007 | Spec-AC-009 | Telegram command names and behavior align with AAI skills where they overlap. | `bash tests/remote-orchestration/test-009-command-skill-alignment.sh` -> mapping table validates required command coverage. |
| AC-008 | Spec-AC-010 | Inline actions and form-based task intake reduce required free-text input for common operations. | `bash tests/remote-orchestration/test-010-interactive-ux-actions.sh` -> scripted UI flow completes with button/form payloads. |
| AC-009 | Spec-AC-011 | Repo-first artifacts remain canonical; runtime-only coordination data is stored in host runtime storage. | `bash tests/remote-orchestration/test-011-repo-vs-runtime-boundary.sh` -> state/docs remain in repo, queue/lease remains host-only. |
| AC-010 | Spec-AC-012 | Every run writes an auditable manifest with required identity and artifact fields. | `bash tests/remote-orchestration/test-012-run-manifest.sh` -> manifest schema validation passes. |
| AC-011 | Spec-AC-013 | Default runtime is single controller + SQLite + concurrency=1 with no mandatory Redis/Postgres/worker pool. | `bash tests/remote-orchestration/test-013-resource-defaults.sh` -> runtime config defaults match constraints. |
| AC-012 | Spec-AC-014 | Memory model uses repo docs + explicit handoff + runtime DB, without hidden shared memory dependency. | `bash tests/remote-orchestration/test-014-memory-contract.sh` -> handoff packet and runtime records are explicit. |
| AC-012a | Spec-AC-014a | Docker worker receives provider login context only via read-only provider session mount plus explicit env/handoff metadata; the image must already contain the CLI binary. | `bash tests/remote-orchestration/test-033-docker-subagent-contract.sh` -> fake docker runner shows session mount, handoff path, and provider env contract. |
| AC-012b | Spec-AC-014b | Parallel child tasks under one parent work item use distinct `task_key` worktrees/manifests/logs while sharing only an explicit `parallel_group` label. | `bash tests/remote-orchestration/test-034-parallel-subtask-shards.sh` -> sibling shard manifests have different worktrees and explicit parallel metadata. |
| AC-013 | Spec-AC-015 | Approval events gate phase transitions and are persisted as durable records. | `bash tests/remote-orchestration/test-015-approval-gates.sh` -> transitions blocked without approval and logged on approval. |
| AC-013a | Spec-AC-016 | `Approve implementation` is enabled only when required planning artifacts and manifest exist. | `bash tests/remote-orchestration/test-016-approve-implementation-prereqs.sh` -> gate stays disabled until prerequisites are present. |
| AC-013b | Spec-AC-017 | `Approve validation` is enabled only when implementation summary and validation targets exist. | `bash tests/remote-orchestration/test-017-approve-validation-prereqs.sh` -> gate stays disabled until prerequisites are present. |
| AC-014 | Spec-AC-018 | Migration path from local AAI usage to remote-controlled operation is documented and executable. | `bash tests/remote-orchestration/test-018-migration-path.sh` -> onboarding/migration doc and command path validate. |
| AC-014 | Spec-AC-019 | Generated launcher supports simple background start, status, stop, restart, logs, probe, and interactive provider login commands for daily operator use. | `bash tests/remote-orchestration/test-029-daemon-manager.sh` -> daemon manager flow shows readable status/probe output and supports stop/start lifecycle. |
| AC-014 | Spec-AC-020 | Installer reuses existing values by default and forces an explicit preserve-vs-overwrite decision before replacing setup state. | `bash tests/remote-orchestration/test-030-wizard-reuses-existing-values.sh` -> wizard offers existing values, masked token reuse, and preserve semantics without manual file edits. |
| AC-014 | Spec-AC-021 | Installer wizard defaults the managed repo path from the existing install state when one managed project is already known. | `bash tests/remote-orchestration/test-031-summary-default-repo-path.sh` -> wizard offers the existing managed repo path instead of the current worktree path. |
| AC-014a | Spec-AC-022 | Installer stays short, while a separate `auth setup` flow reuses native Claude/Codex CLI login and prints exact native login commands instead of trapping OAuth inside the wrapper. | `bash tests/remote-orchestration/test-032-wizard-provider-login-flow.sh` -> install prints `auth setup`, then native provider login plus `auth status` reaches ready provider sessions. |

## Implementation plan
- Control-plane modules:
  - `registry` (projects + host bindings split)
  - `router` (provider selection + usage-aware fallback)
  - `queue` (work item lifecycle + approvals)
  - `runner` (branch/worktree/container lifecycle + manifests)
  - `telegram` (command adapter + interactive actions)
- Data flows:
  - Telegram command -> controller command handler -> queue/registry/router -> run creation -> manifest/report update.
  - Run completion -> report publisher -> repo artifact links -> Telegram status/log output.
- Edge cases:
  - provider telemetry unavailable
  - stale worktree or missing branch
  - approval timeout and explicit pause
  - host restart during running work item
  - project removed from host registry while queued work exists

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Status |
|---|---|---|---|---|---|
| TEST-001 | Spec-AC-001 | integration | tests/remote-orchestration/test-001-multi-project-registration.sh | Registers two projects and verifies host-level management. | green |
| TEST-002 | Spec-AC-002 | integration | tests/remote-orchestration/test-002-worktree-container-isolation.sh | Verifies branch/worktree/container 1:1 isolation contract. | green |
| TEST-003 | Spec-AC-003 | integration | tests/remote-orchestration/test-003-project-policy-load.sh | Loads portable project policy from project-local override file. | green |
| TEST-004 | Spec-AC-004 | integration | tests/remote-orchestration/test-004-host-only-bindings.sh | Confirms non-portable bindings are persisted only in host runtime storage. | green |
| TEST-005 | Spec-AC-005 | integration | tests/remote-orchestration/test-005-telegram-control-flow.sh | Exercises core Telegram command lifecycle for one work item. | green |
| TEST-006 | Spec-AC-006 | unit | tests/remote-orchestration/test-006-provider-routing.sh | Validates explicit provider selection and fallback branches. | green |
| TEST-007 | Spec-AC-007 | unit | tests/remote-orchestration/test-007-cli-subscription-only.sh | Rejects API-key configuration and accepts CLI-subscription mode only. | green |
| TEST-008 | Spec-AC-008 | unit | tests/remote-orchestration/test-008-usage-view.sh | Verifies `/usage` payload fields plus routing capacity hints for both providers. | green |
| TEST-009 | Spec-AC-009 | integration | tests/remote-orchestration/test-009-command-skill-alignment.sh | Validates command-to-skill alignment table constraints. | green |
| TEST-010 | Spec-AC-010 | e2e | tests/remote-orchestration/test-010-interactive-ux-actions.sh | Confirms button/form flow can drive common operator actions. | green |
| TEST-011 | Spec-AC-011 | integration | tests/remote-orchestration/test-011-repo-vs-runtime-boundary.sh | Ensures repo truth and host runtime data boundaries are enforced. | green |
| TEST-012 | Spec-AC-012 | integration | tests/remote-orchestration/test-012-run-manifest.sh | Validates required fields in emitted run manifest. | green |
| TEST-013 | Spec-AC-013 | unit | tests/remote-orchestration/test-013-resource-defaults.sh | Checks default runtime resource policy values. | green |
| TEST-014 | Spec-AC-014 | integration | tests/remote-orchestration/test-014-memory-contract.sh | Verifies explicit handoff packet and runtime memory contract. | green |
| TEST-033 | Spec-AC-014a | e2e | tests/remote-orchestration/test-033-docker-subagent-contract.sh | Verifies Docker subagent launch receives read-only provider session mount and explicit handoff/task-transfer metadata. | green |
| TEST-034 | Spec-AC-014b | integration | tests/remote-orchestration/test-034-parallel-subtask-shards.sh | Verifies sibling shard runs get unique task-key worktrees/manifests while sharing an explicit parallel-group label. | green |
| TEST-015 | Spec-AC-015 | integration | tests/remote-orchestration/test-015-approval-gates.sh | Validates approval gate blocking and durable approval audit records. | green |
| TEST-016 | Spec-AC-016 | unit | tests/remote-orchestration/test-016-approve-implementation-prereqs.sh | Verifies prereq gating for `Approve implementation`. | green |
| TEST-017 | Spec-AC-017 | unit | tests/remote-orchestration/test-017-approve-validation-prereqs.sh | Verifies prereq gating for `Approve validation`. | green |
| TEST-018 | Spec-AC-018 | integration | tests/remote-orchestration/test-018-migration-path.sh | Validates migration checklist and runnable onboarding path. | green |
| TEST-019 | Spec-AC-007 | integration | tests/remote-orchestration/test-019-provider-session-probe.sh | Probes real CLI-subscription style provider sessions and persists session health/usage snapshots. | green |
| TEST-020 | Spec-AC-002 | e2e | tests/remote-orchestration/test-020-run-launch.sh | Launches one real worker process from a manifest and records run/log artifacts. | green |
| TEST-021 | Spec-AC-005 | e2e | tests/remote-orchestration/test-021-telegram-live-polling.sh | Drives a work item through a live Telegram long-poll adapter using a local Telegram API fixture. | green |
| TEST-022 | Spec-AC-018 | integration | tests/remote-orchestration/test-022-standard-runtime-build.sh | Builds the control-plane to `dist/` and validates documented install/run commands without `--experimental-strip-types`. | green |
| TEST-023 | Spec-AC-018 | integration | tests/remote-orchestration/test-023-install-script.sh | Validates one-command host installer flow, generated project config, project registration, and provider autodetection without manual file edits. | green |
| TEST-024 | Spec-AC-005 | integration | tests/remote-orchestration/test-024-missing-provider-fallback.sh | Validates missing provider CLIs are recorded, operators are told to install them manually, and auto-routing avoids unavailable providers. | green |
| TEST-025 | Spec-AC-018 | e2e | tests/remote-orchestration/test-025-install-wizard.sh | Validates the SuperTurtle-style interactive install wizard, generated runtime env, and printed run command. | green |
| TEST-026 | Spec-AC-018 | integration | tests/remote-orchestration/test-026-npm-scripts.sh | Validates the documented npm wrapper scripts can drive the main operator command surface via `npm --prefix apps/control-plane run <script> -- ...`. | green |
| TEST-027 | Spec-AC-005 | integration | tests/remote-orchestration/test-027-telegram-setup-info.sh | Validates Telegram onboarding helpers can verify the bot token and surface chat/user IDs needed for installer ACL setup. | green |
| TEST-028 | Spec-AC-020 | e2e | tests/remote-orchestration/test-028-existing-state-policy.sh | Validates preserve and overwrite modes keep or reset config/runtime state exactly as documented. | green |
| TEST-029 | Spec-AC-019 | e2e | tests/remote-orchestration/test-029-daemon-manager.sh | Validates the generated daemon manager can start in background, show readable status, re-probe providers, and stop cleanly. | green |
| TEST-030 | Spec-AC-020 | e2e | tests/remote-orchestration/test-030-wizard-reuses-existing-values.sh | Validates the wizard reuses existing values, preserves masked secrets, and requires an explicit preserve-vs-overwrite choice when setup state already exists. | green |
| TEST-031 | Spec-AC-021 | e2e | tests/remote-orchestration/test-031-summary-default-repo-path.sh | Validates the wizard reuses the existing managed repo path from install summary/runtime state. | green |
| TEST-032 | Spec-AC-022 | e2e | tests/remote-orchestration/test-032-wizard-provider-login-flow.sh | Validates install -> auth setup flow that prints native login commands and reaches ready sessions after separate CLI login. | green |

Status values: pending -> red -> green.

## Verification
- Commands (executed on 2026-03-20):
  - `bash tests/remote-orchestration/test-001-multi-project-registration.sh`
  - `bash tests/remote-orchestration/test-002-worktree-container-isolation.sh`
  - `bash tests/remote-orchestration/test-003-project-policy-load.sh`
  - `bash tests/remote-orchestration/test-004-host-only-bindings.sh`
  - `bash tests/remote-orchestration/test-005-telegram-control-flow.sh`
  - `bash tests/remote-orchestration/test-006-provider-routing.sh`
  - `bash tests/remote-orchestration/test-007-cli-subscription-only.sh`
  - `bash tests/remote-orchestration/test-008-usage-view.sh`
  - `bash tests/remote-orchestration/test-009-command-skill-alignment.sh`
  - `bash tests/remote-orchestration/test-010-interactive-ux-actions.sh`
  - `bash tests/remote-orchestration/test-011-repo-vs-runtime-boundary.sh`
  - `bash tests/remote-orchestration/test-012-run-manifest.sh`
  - `bash tests/remote-orchestration/test-013-resource-defaults.sh`
  - `bash tests/remote-orchestration/test-014-memory-contract.sh`
  - `bash tests/remote-orchestration/test-033-docker-subagent-contract.sh`
  - `bash tests/remote-orchestration/test-015-approval-gates.sh`
  - `bash tests/remote-orchestration/test-016-approve-implementation-prereqs.sh`
  - `bash tests/remote-orchestration/test-017-approve-validation-prereqs.sh`
  - `bash tests/remote-orchestration/test-018-migration-path.sh`
  - `bash tests/remote-orchestration/test-019-provider-session-probe.sh`
  - `bash tests/remote-orchestration/test-020-run-launch.sh`
  - `bash tests/remote-orchestration/test-021-telegram-live-polling.sh`
  - `bash tests/remote-orchestration/test-022-standard-runtime-build.sh`
  - `bash tests/remote-orchestration/test-023-install-script.sh`
  - `bash tests/remote-orchestration/test-024-missing-provider-fallback.sh`
  - `bash tests/remote-orchestration/test-025-install-wizard.sh`
  - `bash tests/remote-orchestration/test-026-npm-scripts.sh`
  - `bash tests/remote-orchestration/test-027-telegram-setup-info.sh`
  - `bash tests/remote-orchestration/test-028-existing-state-policy.sh`
  - `bash tests/remote-orchestration/test-029-daemon-manager.sh`
  - `bash tests/remote-orchestration/test-030-wizard-reuses-existing-values.sh`
  - `bash tests/remote-orchestration/test-031-summary-default-repo-path.sh`
  - `bash tests/remote-orchestration/test-032-wizard-provider-login-flow.sh`
  - `bash tests/remote-orchestration/test-034-parallel-subtask-shards.sh`
  - `bash tests/remote-orchestration/run-all.sh`
  - `cd apps/control-plane && npm install --no-fund --no-audit && npm run build`
  - `npm --prefix apps/control-plane run test:remote:install`
  - `npm --prefix apps/control-plane run validate:remote`
- Evidence artifacts:
  - command logs under `docs/ai/reports/`
  - run manifests under host runtime storage with references in repo reports
  - validation summary report under `docs/ai/reports/`
- PASS criteria:
  - all TEST-xxx entries are `green`
  - validation verdict is `pass` with non-empty evidence paths
  - no TEST-xxx may be marked `green` from file-existence or string-match checks alone


