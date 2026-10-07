---
id: spec-pr-capability-preflight
type: spec
number: 210
status: done
mutation_gate: v1
frozen_sha256: 04dd230905c4d53b36cce42a4af90e1038eb74266cf6996fa2ba59a72a865449
ceremony_level: 2
links:
  requirement: pr-capability-preflight
  rfc: downstream-pr-ceremony-reliability
  pr:
    - 434
  commits:
    - 227ca445e2e828cb428d7e537f2cf791fa9c2a91
---

# Noninteractive provider readiness before PR writes

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/CHANGE-0204-pr-capability-preflight.md
- Umbrella: docs/rfc/RFC-0016-downstream-pr-ceremony-reliability.md, phase A1 only
- Technology contract: docs/TECHNOLOGY.md
- Prior art: docs/specs/SPEC-0103-spec-platform-portable-pr.md
- Registry items closed by this scope: none
- `fu-azure-live-proof-on-adoption` remains open: this ride does not create an external PR or attest a live Azure round trip. `fu-shared-page-check-flags-own-pr` remains open because shared-page conflict enumeration is outside readiness.

## Implementation strategy

- Strategy: tdd
- Rationale: refusal ordering, provider argument binding, bounded processes and preservation of local state are behavioral safety contracts. Every gating test records observed RED before GREEN. The existing intake-sourced choice in STATE belongs to another ref and does not bind this ride.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: provider subprocess experiments and a PR-bound ceremony change benefit from isolation; the current checkout contains unrelated drafts and generated-page edits.
- User decision: undecided
- Base ref: main
- Worktree branch/path: decided by Implementation Preparation
- Inline review scope: .aai/scripts/pr-preflight.mjs .aai/SKILL_PR.prompt.md .aai/system/PROFILES.yaml tests/skills/test-aai-pr-preflight.sh tests/skills/aai-pr-preflight.Tests.ps1 tests/skills/suite-map.yaml tests/skills/lib/prompt-diet-ledger.sh tests/skills/test-aai-prompt-diet.sh tests/skills/test-aai-hygiene-pack.sh docs/issues/CHANGE-0204-pr-capability-preflight.md docs/specs/SPEC-0210-spec-pr-capability-preflight.md docs/USER_GUIDE.md CHANGELOG.md
- Code review required: true; review the explicit paths above plus scoped evidence, including both compatibility and refusal behavior. Do not include unrelated umbrella or roadmap changes as implementation delivery.

## Scope

Deliver one read-only Node CLI and its PR prompt integration. No PR create/resume/stamp, reservation transport changes, scope/waiver schema changes, global gate changes, external writes, automatic installation, credential acquisition or persistent provider config changes. No change to protected L3 paths is planned; adding one requires reclassification and a scope amendment before implementation of that addition.

## Acceptance Criteria Mapping

All verification commands run from the repository root. Define `V` as `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-preflight.sh`. V executes named TEST rows and prints one PASS/FAIL record per row; exit 0 requires every row to pass. Its disposable fixtures invoke the real CLI. Existing framework test filtering is optional; the full V command decides every row.

| Requirement | Spec-AC | Verification | Observable and evidence |
|------------|---------|--------------|-------------------------|
| AC-001 | Spec-AC-01 | V, TEST-001 | Valid explicit identity is returned; missing/mismatched/ambiguous identity exits 2 before provider calls; fixture call log and JSON in scoped TDD log |
| AC-002 | Spec-AC-02 | V, TEST-002 | Azure read_verified with create_permission unknown; exact allowed probe argv and environment observed |
| AC-003 | Spec-AC-03 | V, TEST-003..005 | Each refusal has its specified code, operation and remedy, no secret output; hung probe terminates within bound |
| AC-004 | Spec-AC-04 | V, TEST-006 | Prompt orders CLI before numbered/staged/committed/pushed writes; actual refusal preserves fixture snapshots |
| AC-005 | Spec-AC-05 | V, TEST-007; existing pr-platform suite | GitHub read_verified and generic capability_not_applicable retain provider routes |
| AC-006 | Spec-AC-06 | V, TEST-008; profile and diet suites | New script classified core, selected-suite mapping includes it; measured additions entry and TEST-012 checkpoint match |

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN identity is missing or inconsistent the CLI SHALL refuse before any provider call. | done | docs/ai/reports/VALIDATION-20261007T180720Z-pr-capability-preflight-corrected.md, Original intent and coverage row Spec-AC-01; TEST-001 | — | Independent validation and dual-verdict review PASS; native matrix bound to d223eb06. |
| Spec-AC-02 | WHEN Azure read probes succeed the CLI SHALL report read_verified and unknown create permission. | done | docs/ai/reports/VALIDATION-20261007T180720Z-pr-capability-preflight-corrected.md, Original intent and coverage row Spec-AC-02; TEST-002 | — | Independent validation and dual-verdict review PASS; native matrix bound to d223eb06. |
| Spec-AC-03 | WHEN a prerequisite or probe fails the CLI SHALL return a bounded, named refusal and remedy without disclosing credentials. | done | docs/ai/reports/VALIDATION-20261007T180720Z-pr-capability-preflight-corrected.md, Original intent and coverage row Spec-AC-03; TEST-003..005 | — | Independent validation and dual-verdict review PASS; native matrix bound to d223eb06. |
| Spec-AC-04 | WHEN readiness refuses the ceremony SHALL stop before lifecycle or Git writes. | done | docs/ai/reports/VALIDATION-20261007T180720Z-pr-capability-preflight-corrected.md, Original intent and coverage row Spec-AC-04; TEST-006 | — | Independent validation and dual-verdict review PASS; native matrix bound to d223eb06. |
| Spec-AC-05 | WHEN GitHub or a generic provider is selected the CLI SHALL preserve its declared readiness and ceremony route. | done | docs/ai/reports/VALIDATION-20261007T180720Z-pr-capability-preflight-corrected.md, Original intent and coverage row Spec-AC-05; TEST-007 | — | Independent validation and dual-verdict review PASS; native matrix bound to d223eb06. |
| Spec-AC-06 | WHEN the new vendored script and prompt text are shipped their classification, suite selection and byte accounting SHALL be complete. | done | docs/ai/reports/VALIDATION-20261007T180720Z-pr-capability-preflight-corrected.md, Original intent and coverage row Spec-AC-06; TEST-008 | — | Independent validation and dual-verdict review PASS; native matrix bound to d223eb06. |

## Implementation plan

### Interface and identity seam

Add `.aai/scripts/pr-preflight.mjs --input <UTF-8 JSON file> --json [--timeout-ms <positive integer>]`. Input schema v1 contains `schema_version: 1`, `repo_root` (absolute existing Git checkout), `remote_name`, `source_branch`, `target_branch`. Azure additionally contains `organization_url`, `project`, `repository`; GitHub contains `repository` in owner/name form. Generic provider has no provider repository fields. Refuse unknown keys, empty values, duplicate flags, invalid schema, detached HEAD, missing remote, invalid branch names, source unequal to current branch, source equal to target, and provider identity inconsistent with the actual selected Git remote. Use existing platform classification/sanitization rather than a second host classifier. Parse supported Azure HTTPS/SSH and legacy hosts; refuse ambiguous/unparseable identities with a specific remedy. Target is explicit intent, not a claim that it was remotely read. Resolve local HEAD SHA for result binding. Git commands used for identity are read-only and bounded as provider commands are.

Result JSON v1 contains schema_version, platform, sanitized repository identity, remote_name, source_branch, target_branch, head_sha, outcome, code, operation, remedy and `create_permission: "unknown"`. On success, outcome is `read_verified` (Azure/GitHub) or `capability_not_applicable` (unknown/none). No credential field or raw provider stderr/stdout is emitted. Generic repository.remote strips userinfo, query and fragment before emission; read-only generic readiness still reports capability_not_applicable. Missing remote in a none route is permissible only when input explicitly declares `remote_name: null`; this is the existing local-only ceremony route. All other identity fields remain required. Exit 0 success, 2 input/identity refusal, 3 capability/access refusal, 124 timeout. Errors produce one JSON result and a concise safe stderr remedy.

### Provider seam

Azure probes: `az --version`, `az extension show --name azure-devops --output json --only-show-errors`, then `az repos show --organization <url> --project <project> --repository <repository> --detect false --output json --only-show-errors`. Require a parseable installed-extension record and repository identity matching the request and remote; nonzero or malformed success is refusal. Do not run `az account show` as an Azure DevOps authentication prerequisite: a valid PAT-based DevOps session need not have a subscription login. Repository read is the authenticated-access observation; it never proves PR-create permission.

All probe subprocesses receive closed stdin, `AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no`, `GIT_TERMINAL_PROMPT=0`, `GH_PROMPT_DISABLED=1`; do not persist these settings. Do not pass secrets as argv or print inherited environment values. No login, extension add/update, config set, or provider write command is allowed. GitHub uses `gh --version`, `gh auth status --hostname <resolved host>`, `gh repo view <owner/name> --json nameWithOwner,url`; verify returned identity. Enterprise hosts require host-bound execution; do not fall back to github.com. Generic/none prints the established fallback limitation and invokes neither gh nor az.

Codes: IDENTITY_INVALID (exit 2), CLIENT_MISSING, EXTENSION_MISSING, AUTH_FAILED, NETWORK_FAILED, ACCESS_UNKNOWN, PROVIDER_RESULT_INVALID (exit 3), PROBE_TIMEOUT (124), READ_VERIFIED and CAPABILITY_NOT_APPLICABLE (0). Classify only recognized authentication or connectivity signals; arbitrary exit 1, denied/not-found ambiguity, malformed data or unknown permission must never be reclassified as verified readiness. A spawn ENOENT is CLIENT_MISSING; broken/unloadable installed extension is capability failure with an extension remedy, not automatic installation. Print an operator remedy that can be acted on without assuming owner authorization to install/login. A timeout names its probe; no retry loop or cache.

Each subprocess has default timeout 10000 ms, override integer 100..60000 ms for tests/operators, stdout/stderr cap 1 MiB, and bounded termination. Test sleeping CLI with timeout 1000 ms must return 124 within 3000 ms without later probe invocation or a surviving spawned child. Use platform-appropriate termination without shell-interpolating arguments. If a platform cannot enforce the declared termination contract, fail closed and disclose the limit rather than count that matrix arm as PASS.

### Ceremony and distribution seams

After branch hygiene/pin/session lock and existing read-only gates, derive the input from the actual checkout, resolved remote and explicit source/target/provider repository intent. Invoke the CLI in PRECONDITIONS before PROCESS step 1b and any index/lifecycle/Git write. Nonzero means STOP with the safe diagnostic; release the held session lock through its existing release command. Branch pin/session lock runtime writes are existing precondition coordination and are outside the STATE/index/HEAD/reservation preservation snapshot; no document close/status flip is allowed before readiness. The result is an observation at invocation time, not a reusable create authorization. No preflight result is hand-written into STATE.

The prompt is agent-executed prose, so tests can assert ordering and run the exact described CLI with refused/success fixtures, but cannot prove an arbitrary future agent follows the prose. Record that residual seam risk in validation; do not label text inspection as a fully executed ceremony.

Classify the new script as core in `.aai/system/PROFILES.yaml`. Add a pr-preflight suite-map row covering the new script and prompt. Update the hygiene suite inventory pin from 103 to 104 for the new suite. Fold a measured JUSTIFIED_ADDITIONS entry and bumped TEST-012 checkpoint into the existing prompt-diet machinery. Update user guidance and changelog only for this first ride.

## Test Plan

Mutation cells name behavior-removal patch artifacts to be produced in the disposable implementation copy, then exercised and recorded by mutation-run. They are not claims of executed mutations at Planning. Each patch changes the named boundary behavior, must keep the program parseable, and must make its named test FAIL; no syntax-error or missing-command result counts as behavioral RED.

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---------|---------|------|----------------------|-------------|----------|--------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-pr-preflight.sh | Valid Azure/GitHub/local identities plus missing fields, detached/mismatched source, target same as source, remote/provider mismatch and encoded spaces/Unicode; refusal calls zero providers; valid arm calls a provider | patch:docs/ai/tdd/spec-pr-capability-preflight/mutation-TEST-001.patch | green |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-pr-preflight.sh | Exact deny-by-default Azure argv/env and closed stdin; extension missing refuses before repos; PAT-style read succeeds without account probe; mismatched returned repository refuses | patch:docs/ai/tdd/spec-pr-capability-preflight/mutation-TEST-002.patch | green |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-pr-preflight.sh | Missing executable/extension/auth/network/ambiguous denial/malformed outputs return distinct code/remedy/operation and never trigger install or create | patch:docs/ai/tdd/spec-pr-capability-preflight/mutation-TEST-003.patch | green |
| TEST-004 | Spec-AC-03 | integration | tests/skills/test-aai-pr-preflight.sh | Hung probe bounded at 1000 ms, <=3000 ms observed, later probes absent and child no longer running; invalid timeout refuses before spawn | patch:docs/ai/tdd/spec-pr-capability-preflight/mutation-TEST-004.patch | green |
| TEST-005 | Spec-AC-03 | integration | tests/skills/test-aai-pr-preflight.sh | Actual invoked provider emits credential-like synthetic markers/remote userinfo; output contains none, safe diagnostic exists; positive invocation controls and 1 MiB cap refusal | patch:docs/ai/tdd/spec-pr-capability-preflight/mutation-TEST-005.patch | green |
| TEST-006 | Spec-AC-04 | integration | tests/skills/test-aai-pr-preflight.sh | Prompt orders actual CLI before numbering/stage/commit/close/push; refused real CLI fixture preserves STATE bytes/index tree/HEAD/local+remote reservation refs; success proves fixture probe reachable | patch:docs/ai/tdd/spec-pr-capability-preflight/mutation-TEST-006.patch | green |
| TEST-007 | Spec-AC-05 | integration | tests/skills/test-aai-pr-preflight.sh | GitHub host/repository exact binding, missing auth refusal, generic/none no client calls and named fallback; original Azure/GitHub classification unchanged | patch:docs/ai/tdd/spec-pr-capability-preflight/mutation-TEST-007.patch | green |
| TEST-008 | Spec-AC-06 | integration | tests/skills/test-aai-pr-preflight.sh | Core profile and suite-map select real new script; diet ledger addition and checkpoint match actual prompt diff | patch:docs/ai/tdd/spec-pr-capability-preflight/mutation-TEST-008.patch | green |

Review remediation stays within the existing rows: TEST-001 proves real direct/symlink CLI output and exit parity; TEST-002 emits a successful Azure Unicode JSON response split inside a UTF-8 character and proves READ_VERIFIED; byte/time caps remain unchanged. The existing Pester arm also runs canonical Bash on POSIX with the scratch override unset, using an os.tmpdir-based portable default and private per-run fixtures; native Linux evidence must be read from CI, not inferred from macOS.

Remediation coverage includes negative inherited prompt flags on captured Git/Azure/GitHub probes, legacy vs-ssh.visualstudio.com v3 identity, generic credential marker positive controls, LF/CRLF prompt fixtures and a real shallow checkout with the historic baseline object absent. TEST-008 measures canonical LF bytes against the immutable baseline36430 bytes (bdeb425c040ada918dd97e5b878b71e420bad83a), without fetching history.

Patch intentions in order: bypass identity mismatch refusal; allow extension absence through to repos; map unknown provider failure to success; remove subprocess timeout; forward raw stderr; delete prompt preflight invocation; allow GitHub repository mismatch; remove new script core classification. Implementation creates each exact patch before GREEN and proves it bites. A changed mutation measurement is disclosed through the existing amendment writer.

## Verification

- V as defined above, expected exit 0 and all eight named records PASS. RED logs must show the intended assertion failing on the pre-change implementation, not solely absence of the new CLI. Supply a minimal parseable no-op CLI in the scratch baseline when needed, record that baseline transparently, and retain it as evidence.
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-platform.sh`, exit 0: existing platform routes.
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-layer-profiles.sh`, exit 0.
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh`, exit 0, including TEST-012.
- Native Windows: `powershell -NoProfile -File .aai/scripts/aai-run-tests.ps1 powershell -NoProfile -Command "Invoke-Pester -Path tests/skills/aai-pr-preflight.Tests.ps1 -EnableExit"`; the Pester suite also invokes pwsh 7 for the same real Node CLI/provider fixture matrix. Verify argument delivery and hung-process termination under both native shells. Mac/Linux Node subprocess green is not Windows proof. Native Windows availability is an implementation evidence requirement, not currently verified here; if unavailable, arrange an authorized runner or return an explicit validation blocker.
- `node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-0210-spec-pr-capability-preflight.md`, required exit 0 with eight reproduced behavioral RED records. Bash mutations cover shared Node behavior; native Pester has no supported mutation gate and supplies platform seam proof separately.
- All fixtures are private disposable repositories under the dispatched scratch path, never the shipping tree. Byte-exact append-only prefixes are preserved if evidence adds ledger records. No live Azure/GitHub provider write is executed by these tests.

## Evidence contract

Record ref_id pr-capability-preflight, Spec-AC/TEST IDs, full command, exit, sanitized output and immutable base/head when available. RED: docs/ai/tdd/pr-capability-preflight-red.log; GREEN: docs/ai/tdd/pr-capability-preflight-green.log; native shell matrix: docs/ai/tdd/pr-capability-preflight-windows.log; independent validation: docs/ai/tdd/pr-capability-preflight-validation.log. Per-test mutations and replay records live only under docs/ai/tdd/spec-pr-capability-preflight/. Validation returns one checked report with aai-outcome-v1, and its identical report path in outcome_report and set-validation --evidence. No timing reduction or historical downstream reproduction is claimed.

### Evidence by strategy

TDD requires stored intended RED per gating row, subsequent GREEN, behavior-removal replay, and native platform seam proof. Planning has not run these tests: the new CLI and suites do not exist yet.

## Residual risks and source limits

Readiness may expire before create; future create permission stays unknown. Provider error text evolves, so unknown classifications fail closed. Hermetic allowlists prove command binding, not authenticated Azure compatibility; the registry's live-proof debt stays open. The owner-provided downstream pin/raw logs are still unavailable. A phase-A2 resumption spec will handle push/create/stamp interruption independently.

Official command references checked during Planning: [Azure repos show](https://learn.microsoft.com/en-us/cli/azure/repos?view=azure-cli-latest#az-repos-show) and [Azure CLI extension management](https://learn.microsoft.com/en-us/cli/azure/azure-cli-extensions-overview?view=azure-cli-latest). Azure repos commands can dynamically install the extension; the child-only disabling environment and installed-extension check are mandatory.
