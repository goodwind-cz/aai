# Implementation Spec: PRD-AAI-REMOTE-ORCHESTRATION-01

## Links
- Requirement: [PRD-AAI-REMOTE-ORCHESTRATION-01](../requirements/PRD-AAI-REMOTE-ORCHESTRATION-01.md)
- Decision records: n/a
- Technology contract: [docs/TECHNOLOGY.md](../TECHNOLOGY.md)

## Spec status
- SPEC-FROZEN: true

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
| AC-006 | Spec-AC-008 | `/usage` response includes quota window, used percentage, and reset timestamp per provider. | `bash tests/remote-orchestration/test-008-usage-view.sh` -> structured usage payload contains required fields for both providers. |
| AC-007 | Spec-AC-009 | Telegram command names and behavior align with AAI skills where they overlap. | `bash tests/remote-orchestration/test-009-command-skill-alignment.sh` -> mapping table validates required command coverage. |
| AC-008 | Spec-AC-010 | Inline actions and form-based task intake reduce required free-text input for common operations. | `bash tests/remote-orchestration/test-010-interactive-ux-actions.sh` -> scripted UI flow completes with button/form payloads. |
| AC-009 | Spec-AC-011 | Repo-first artifacts remain canonical; runtime-only coordination data is stored in host runtime storage. | `bash tests/remote-orchestration/test-011-repo-vs-runtime-boundary.sh` -> state/docs remain in repo, queue/lease remains host-only. |
| AC-010 | Spec-AC-012 | Every run writes an auditable manifest with required identity and artifact fields. | `bash tests/remote-orchestration/test-012-run-manifest.sh` -> manifest schema validation passes. |
| AC-011 | Spec-AC-013 | Default runtime is single controller + SQLite + concurrency=1 with no mandatory Redis/Postgres/worker pool. | `bash tests/remote-orchestration/test-013-resource-defaults.sh` -> runtime config defaults match constraints. |
| AC-012 | Spec-AC-014 | Memory model uses repo docs + explicit handoff + runtime DB, without hidden shared memory dependency. | `bash tests/remote-orchestration/test-014-memory-contract.sh` -> handoff packet and runtime records are explicit. |
| AC-013 | Spec-AC-015 | Approval events gate phase transitions and are persisted as durable records. | `bash tests/remote-orchestration/test-015-approval-gates.sh` -> transitions blocked without approval and logged on approval. |
| AC-013a | Spec-AC-016 | `Approve implementation` is enabled only when required planning artifacts and manifest exist. | `bash tests/remote-orchestration/test-016-approve-implementation-prereqs.sh` -> gate stays disabled until prerequisites are present. |
| AC-013b | Spec-AC-017 | `Approve validation` is enabled only when implementation summary and validation targets exist. | `bash tests/remote-orchestration/test-017-approve-validation-prereqs.sh` -> gate stays disabled until prerequisites are present. |
| AC-014 | Spec-AC-018 | Migration path from local AAI usage to remote-controlled operation is documented and executable. | `bash tests/remote-orchestration/test-018-migration-path.sh` -> onboarding/migration doc and command path validate. |

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
| TEST-008 | Spec-AC-008 | unit | tests/remote-orchestration/test-008-usage-view.sh | Verifies `/usage` payload fields for both providers. | green |
| TEST-009 | Spec-AC-009 | integration | tests/remote-orchestration/test-009-command-skill-alignment.sh | Validates command-to-skill alignment table constraints. | green |
| TEST-010 | Spec-AC-010 | e2e | tests/remote-orchestration/test-010-interactive-ux-actions.sh | Confirms button/form flow can drive common operator actions. | green |
| TEST-011 | Spec-AC-011 | integration | tests/remote-orchestration/test-011-repo-vs-runtime-boundary.sh | Ensures repo truth and host runtime data boundaries are enforced. | green |
| TEST-012 | Spec-AC-012 | integration | tests/remote-orchestration/test-012-run-manifest.sh | Validates required fields in emitted run manifest. | green |
| TEST-013 | Spec-AC-013 | unit | tests/remote-orchestration/test-013-resource-defaults.sh | Checks default runtime resource policy values. | green |
| TEST-014 | Spec-AC-014 | integration | tests/remote-orchestration/test-014-memory-contract.sh | Verifies explicit handoff packet and runtime memory contract. | green |
| TEST-015 | Spec-AC-015 | integration | tests/remote-orchestration/test-015-approval-gates.sh | Validates approval gate blocking and durable approval audit records. | green |
| TEST-016 | Spec-AC-016 | unit | tests/remote-orchestration/test-016-approve-implementation-prereqs.sh | Verifies prereq gating for `Approve implementation`. | green |
| TEST-017 | Spec-AC-017 | unit | tests/remote-orchestration/test-017-approve-validation-prereqs.sh | Verifies prereq gating for `Approve validation`. | green |
| TEST-018 | Spec-AC-018 | integration | tests/remote-orchestration/test-018-migration-path.sh | Validates migration checklist and runnable onboarding path. | green |

Status values: pending -> red -> green.

## Verification
- Commands (planned):
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
  - `bash tests/remote-orchestration/test-015-approval-gates.sh`
  - `bash tests/remote-orchestration/test-016-approve-implementation-prereqs.sh`
  - `bash tests/remote-orchestration/test-017-approve-validation-prereqs.sh`
  - `bash tests/remote-orchestration/test-018-migration-path.sh`
- Evidence artifacts:
  - command logs under `docs/ai/reports/`
  - run manifests under host runtime storage with references in repo reports
  - validation summary report under `docs/ai/reports/`
- PASS criteria:
  - all TEST-xxx entries are `green`
  - validation verdict is `pass` with non-empty evidence paths


