---
id: downstream-pr-ceremony-reliability
type: rfc
number: 16
status: draft
links:
  spec: null
  pr: []
  commits: []
---

# RFC — Reliable, bounded and resumable downstream PR ceremony

## Context

The owner supplied the downstream report "Profil posledního aai-pr: Plana
C-index", generated at 2026-10-06T08:26:12Z. This intake analyzes that report
against the AAI source checkout at `bdeb425c` and proposes separately scoped
follow-on work. The downstream raw STATE, ledgers, logs, installed AAI pin
and Azure repository were not supplied or independently inspected here.
Reported historical observations remain attributed to that report.

### Reported outcome and measurement limits

- The reconstructed PR-specific wall-clock interval is 2026-10-05T14:10:55Z
  through 14:52:44Z: 2,509 seconds, or 41:49. It includes human responses
  and cannot be labeled CPU time, tool time or autonomous agent time.
- Previous implementation lifecycle totals 2,228 seconds (37:08) across
  five role runs. It is a different measurement from PR ceremony elapsed
  time; adding the totals would not establish a valid end-to-end duration.
- The downstream report names pushed feature/close commits `399d8e43` and
  `f6f81ddb`. The session was interrupted before documented PR creation and
  PR-number stamping, leaving `pr: [TBD]`.
- A later read-only Azure CLI query failed because `azure-devops` was
  absent and installation prompted interactively before EOFError. This
  proves a capability problem in that later environment; it does not prove
  the interrupted create command ran and failed for that reason.
- No PR creation is evidenced in the supplied report. It is not proof
  that nobody created a PR outside the session. This intake claims neither
  authoritative absence nor a verified Azure round trip.
- Token counts, cost and human-time estimates are null. Preserve null;
  do not infer them from elapsed time or source-code inspection.

| Reported phase | Elapsed | Share of observed PR interval |
|---|---|---|
| Waivers and validation gate | 6:48 | 16.3% |
| Branch/session preparation | 2:09 | 5.1% |
| Numbering and reservations | 13:06 | 31.3% |
| Scope staging and feature commit | 5:43 | 13.7% |
| Close ceremony | 11:51 | 28.3% |
| Pre-push checks and push | 2:12 | 5.3% |
| Create PR and stamp PR | Not completed | Not measured |

Numbering plus close account for 1,497 seconds, or 59.7% of the measured
interval. These phase durations do not isolate the time cost of individual
defects, human decisions, Git networking or tools. Their shares do not
justify a promised speedup or establish which change has greatest ROI.

### Current-source findings

| Concern | Current source evidence | Conclusion and limit |
|---|---|---|
| Azure prerequisite failure discovered late | `.aai/scripts/pr-platform.mjs` classifies remote host and reviewer configuration; `.aai/SKILL_PR.prompt.md` creates Azure PRs after push. | Host detection does not establish CLI/extension/auth/repository access readiness. The reported missing extension needs downstream reproduction with its installed pin. |
| Atomic singleton reservation | `pushReservation()` in `.aai/scripts/allocate-doc-number.mjs` unconditionally passes `--atomic`, also for one ref; its push has no explicit timeout. | The reported unsupported-atomic failure is consistent with current code. Do not generalize one server's capability to every Azure remote. Coupled multi-ref reservations have a distinct all-or-nothing contract. |
| Global amendment and workspace gates | `spec-amend.mjs` `cmdList()` explicitly judges strict mode over the entire ledger and scans frozen specs; `nothing-left-behind.mjs` `filesLeft()` uses whole-root Git status and `auditFindings()` runs a repo-wide strict audit. | Global scope is implemented intentionally, not a mistaken flag. An unrelated file count is not evidence about the PR's committed diff; changing blocking semantics needs a bounded policy and companion tests. |
| Global overdue failure | `.aai/VALIDATION.prompt.md` Rule 3 explicitly makes overdue reviews a repository-wide interrupt for every PASS. | The report's feature-test-green/formal-FAIL split is compatible with current policy. It cannot be silently converted to PASS by a performance fix. |
| PowerShell waiver transport | `validation-waiver.mjs` already exports `formatWaiver()` with a parse-back check, but its CLI reads records and exposes no typed write operation. | A formatter exists; the missing piece is a reliable writer/transport seam. The reported two shell-corrupted writes were not reproduced here. Reuse the existing grammar and scope/actor checks. |
| Scope format mismatch | `state.mjs` `cmdSetCodeReview()` persists `--scope` as text; `check-committed-scope.mjs` splits on whitespace or commas (`/[\s,]+/`). | Semicolon-delimited input is neither normalized nor rejected at this writer. Blindly adding another delimiter would still mishandle legitimate spaces/punctuation in paths. |
| No PR phase records | `.aai/SKILL_PR.prompt.md` has no phase start/end instrumentation. | The supplied report's missing tick records are plausible. Generic tick tools exist, but a role duration is not a PR-operation trace and missing data is not measurable overhead. |

## Proposal

Create an umbrella roadmap of small rides, each with its own intake/spec,
regression, validation and review. Do not bundle all six recommendations
into one implementation. First make the downstream Azure completion path
usable and resumable; then handle scope/waiver transports and the separately
approved global-gate policy. Add observational phase timing early enough
to measure later changes without making telemetry a new completion blocker.

### A. Noninteractive capability preflight and PR resumption

Before any feature/close commit or push, resolve the explicit repository,
remote, source branch and target branch, then check the chosen PR provider's
client, extension where applicable, and authenticated access without
interactive installation or disclosure of credentials. Bound probe duration
and distinguish missing client/extension, authentication failure, network
failure and unknown permission. Read access is not a guarantee of create
permission; report that limit instead of promising a successful future write.

Missing prerequisites must stop with a named remedy before the irreversible
portion of the ceremony advances. No automatic extension installation is
authorized by this RFC. Preserve the existing GitHub/generic routes.

Persist enough completion information to resume after push without repeating
numbering, committing, closing or creating duplicates. Resolve any existing
PR by repository/source/base identity, verify its identity and stamp its
number through the existing close writer. Multiple matches, unreadable
platform state or uncertain creation outcome are named stop conditions.
A timeout after a create request is not permission to retry a create blindly.
Test push-to-create and create-to-stamp interruptions independently.

### B. Portable bounded reservation transport

For exactly one reservation ref, use a create-only push that does not require
atomic multi-ref support. Preserve the unique reservation commit, empty
expected-value lease, collision detection and non-collision refusal behavior.
Keep true multi-ref coupled-family reservations atomic; unsupported atomic
capability must refuse or degrade through an explicitly defined contract,
not partially reserve a coupled family and claim success.

Bound network operations, name the operation being attempted, and distinguish
timeout, collision, unsupported capability, permission and connectivity
failures. Do not weaken number uniqueness or retry arbitrary errors as
collisions. Do not introduce a capability cache without a concrete need.

### C. Typed scope and waiver writes

Define one shared scope representation and parser for writers and consumers.
Accept a structured path list without losing spaces, commas, semicolons or
Unicode in legitimate filenames; retain explicitly supported diff-range
input. Normalize supported legacy text forms or reject ambiguous inputs at
write time with a remedy. A full STATE migration is not presumed necessary;
Planning must inspect all readers before choosing the compatibility approach.

Add an authorized typed waiver write operation using `formatWaiver()` and
the sole STATE writer. Carry fields through structured arguments/file/stdin
as appropriate, not a nested-quote sentinel assembled in PowerShell.
Preserve actor, explicit owner authority, ref binding, timestamp and reason.
Never manufacture a waiver because feature tests passed or a global gate
is inconvenient. Verify round trips on Windows PowerShell 5.1 and pwsh 7.

### D. Separate inherited findings from introduced scope failures

Classify findings against an explicit, resolvable base identity and the
declared committed/staged/worktree scope, with fingerprints that detect
changed findings rather than path equality alone. Display inherited findings
as inherited, with their origin and continued remediation obligation.
New/worsened findings, touched governed surfaces, security-sensitive gates
and unclassifiable findings must retain the appropriate blocking behavior.
An unavailable baseline cannot silently exempt a finding.

Owner approval is needed before changing intentionally global amendment,
overdue or nothing-left-behind policy. Options include preserving overdue
as a global gate while making unrelated workspace dirt nonblocking, versus
a broader inherited-baseline mode with a maintained global audit backstop.
This proposal selects neither silently. Do not restamp an unchanged base
spec, alter its status or fabricate an amendment simply to clear another PR.

### E. PR phase timing and completion evidence

Record actual phase start/end/outcome for preconditions, numbering, staging,
close, push, create-PR and stamp-PR, including attempted/refused/interrupted
steps and resumed invocations. Bind observations to work-item, repository,
base/head, invocation and platform identities. Plan the schema and consumers
before choosing LOOP_TICKS versus a dedicated trace; avoid hand-written STATE.
Keep total wall time separate from tool duration and human waiting whenever
those signals are available. Missing token/cost/human usage stays null.
Telemetry failure is visible but does not hide the ceremony's own result.

## Alternatives Considered

- Keep manual workarounds: lowest implementation effort, but repeats the
  observed quoting, reservation and interrupted-completion failures.
- One large PR rewriting the ceremony: faster to describe but mixes transport
  defects, schema compatibility and governance decisions; hard to validate
  independently and to attribute improvements. Not recommended.
- Remove all global checks: removes some blocking cost but loses intended
  governance and may silently exempt introduced failures. Not recommended.
- Prompt-only reminders: can improve operator guidance but cannot reliably
  enforce reservation safety, transport round trips or duplicate-free recovery.

## Consequences

Technical impact: provider capability probes, reservation transport,
scope/waiver write interfaces, gate baselines and PR-operation evidence.
Changes to protected state/governance surfaces must be classified during
Planning and follow their existing ceremony requirements.

Operational impact: downstream missing prerequisites are exposed early;
interrupted pushes can resume to a real stamped PR; inherited debt remains
visible. No elapsed-time reduction is promised until comparable traces exist.

Migration/compatibility: preserve existing provider routes and committed
append-only records. A new scope representation must account for every
consumer and downstream older STATE files. Existing policy stays in force
until its replacement is explicitly decided and shipped.

## Rollout Status

| Phase | Description | Status | Delivered by |
|---|---|---|---|
| A | Provider capability preflight and duplicate-safe PR resumption | not started | — |
| B | Singleton reservation portability and bounded network diagnostics | not started | — |
| C | Typed scope and authorized waiver writes | not started | — |
| D | Explicit decision on inherited/global gate policy, then implementation | not started | — |
| E | PR phase instrumentation and evidence-backed before/after measurement | not started | — |

Phases are scope boundaries, not committed scheduling order. Planning can
split A or C further and bring observational E forward. No child rides have
been filed or approved by saving this intake.

## Verification Expectations

- Record the downstream installed AAI pin and exact failing command/error
  before declaring a historical issue reproduced or already fixed upstream.
- Hermetic CLI/Git fixtures exercise missing extension, noninteractive EOF,
  auth/network failures, timeouts, singleton unsupported-atomic transport,
  create-only collision, identical-object lease controls and coupled-family
  all-or-nothing refusal. Assert state/index/remote writes did not occur in
  early prerequisite refusal paths.
- Preserve byte-exact base prefixes of audit ledgers; preserve unrelated
  local work. Tests run only in private disposable repositories.
- Execute scope and waiver writer-to-reader round trips with realistic paths
  and reasons under both native Windows shells. A stub accepting invalid
  command shapes is not proof of Azure compatibility.
- Compare unchanged inherited fixtures with introduced and worsened findings,
  unavailable bases and touched governed surfaces. Verify the chosen global
  policy and its backstop explicitly; do not infer it from a scoped PASS.
- Reproduce push-before-create and create-before-stamp interruptions, including
  an uncertain create response and multiple PR matches. Resume to exactly one
  identified PR and stamped docs, or a named refusal, never false completion.
- Verify trace ordering, identity, real timestamps, exits and unknown usage.
  Compare timings only under stated equivalent conditions.
- Follow up `fu-azure-live-proof-on-adoption`: wiring tests never substitute
  for an authenticated live Azure create/read-back/stamp round trip. Arrange
  that evidence in an authorized downstream fixture; this intake does not
  authorize external PR creation or extension installation.

## Risks

- Scope exemptions can weaken intentional global governance. Require an
  explicit policy decision and adversarial positive/refusal controls.
- Removing atomicity from coupled reservations risks partial ownership.
  Singleton portability must preserve the multi-ref boundary.
- Schema/parser drift can strand scope evidence or silently drop filenames.
  Share representation and inspect all consumers.
- Repeated create attempts after interruption can duplicate PRs. Resolve
  platform state before another mutating request.
- No raw downstream artifacts were inspected here; historical timing and
  shell behavior are supplied evidence, not independent reproduction.
- No local secret value is referenced or inspected in this intake.

## Open Questions

- Which global gates remain intentionally repository-wide, and which admit
  an inherited-baseline mode? Define the non-exemptible conditions.
- Which supported scope representation preserves all required path/range
  inputs with least downstream migration cost?
- Which provider operation can establish useful readiness without pretending
  read access proves PR-create permission?
- Where should phase traces live, and what can the runtime actually report
  about human waiting and tool duration?
- What downstream pin produced the Plana report, and can an authorized Azure
  fixture supply the missing live round-trip evidence?

## Approvals

- Repository/workflow owner approves the global-gate policy and rollout scope.
- Implementation scopes receive normal Planning, executable Validation and
  independent Code Review under their assigned ceremony levels.
- No standing merge authorization, waiver or provider installation is created
  by this RFC.

## Notes

- Source: owner-provided Plana C-index profile, generated
  2026-10-06T08:26:12Z, pasted into this conversation on 2026-10-07.
- Relevant existing evidence debt: `fu-azure-live-proof-on-adoption`;
  platform portability SPEC-0103 and SPEC-0104 explicitly withdrew claims of
  live Azure proof pending real adoption.
- Related intake: `directed-merge-and-post-merge-cleanup`. That scope begins
  with an existing PR and handles merge/cleanup. This RFC addresses delivery
  through creation and stamping, before the merge handoff.
- Detected type: RFC because this is a multi-scope reliability proposal with
  an intentional governance-policy decision, not one small enhancement.
- Implementation mode: owner has not chosen; Planning decides per child
  scope. Behavioral changes affecting remote writes/state/data integrity
  warrant full TDD; policy analysis itself is not code implementation.
- Intake human-time estimate: not supplied. No historical tokens or cost
  were inferred.
