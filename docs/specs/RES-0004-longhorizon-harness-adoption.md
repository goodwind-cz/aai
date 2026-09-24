---
id: longhorizon-harness-adoption
type: research
number: 4
status: draft
links:
  pr: []
  commits: []
---

# Research — LongHorizon-Harness adoption and collaboration

## Research Question

Which ideas from AMAP-ML/LongHorizon-Harness would improve AAI, which duplicate
existing capabilities, and where would integration or upstream collaboration
offer more value than copying the project?

## Scope

- In scope: source-level architecture comparison, evidence and recovery
  semantics, benchmark credibility, ranked adoption opportunities, a bounded
  experiment, and concrete collaboration proposals.
- Out of scope: implementation, installing or launching the harness, paid model
  runs, changing AAI's active workflow state, or contacting upstream maintainers.
- Consumers: the AAI owner and maintainers, including downstream projects that
  vendor AAI. Assume the primary product remains a software factory, with GUI
  workflows an optional extension.

## Success Criteria

- Explain what the upstream implementation actually guarantees, with pinned
  source references and limitations separated from reported results.
- Map recommendations to existing AAI files and identify duplication.
- Recommend a small next step and a measurable experiment, without treating
  suggested work as filed or approved implementation.

## Constraints

- Timebox: one research pass in this session; no benchmark execution.
- Access/data/tools: public upstream repository, paper/project material, and
  local AAI source. No credentials or private task data are needed.
- Saved document in English; operator discussion in Czech.
- AAI's [technology contract](../TECHNOLOGY.md) requires dependency-free Node
  tooling. Upstream Python/FastAPI and frontend dependencies must remain outside
  the vendored core if a later experiment uses the runtime.
- The initial intake was an unnumbered draft despite containing findings.
  Delivery numbering does not itself authorize implementation or roadmap changes;
  the subsequent change scope records those decisions separately.

## Method

Reviewed on 2026-09-22. Upstream source snapshot:
[`a1dd930614972b92361c1b9cd6aac441a6db5a65`](https://github.com/AMAP-ML/LongHorizon-Harness/commit/a1dd930614972b92361c1b9cd6aac441a6db5a65),
commit dated 2026-08-20; package version 0.1.7. AAI baseline:
`d2328fce897a3bad73fa83eb8bf9b0f354fdfdeb`. The starting branch was reported three
commits behind its tracking branch; no pull or baseline update was performed.
Those original comparisons describe that checkout. The latest-main refresh below
supersedes this baseline limitation for the current AAI comparison.

Read the production `src/lh_harness/` implementation and selected tests, then
compared it with AAI dispatch, state, validation, briefs, recovery and telemetry.
Independent research passes covered local AAI, upstream recovery/isolation,
and experimental evidence. No upstream tests or end-to-end runs were executed:
“implemented” below means present in inspected source, not newly runtime-proven.
Public source reading was explicitly requested; the intake's offline identity
allocation policy was preserved without limiting the requested research.

### Refresh against latest AAI main

On 2026-09-22 UTC, the AAI comparison was refreshed against fetched
`origin/main` at `f84f84ab93348a321b6af803ba53ce0a526f53fc`. This inspected the
four commits after the original `d2328fce` baseline, using their committed source
rather than this feature branch's implementation. Upstream research was not
repeated, and no tests or benchmarks were run for this research refresh.

AAI now has additional controls worth retaining: isolated mutation execution,
recorded target fingerprints, validation replay for marked specs, and frozen
contract hashing that detects undisclosed post-freeze changes. The mutation gate
has explicit legacy/missing-evidence degradations and exempt rows; close-time
record checking is not itself replay. Contract hashing detects changes to a frozen
contract, not constraints omitted when it was first written. These controls
complement the proposed original-request backcheck. See the [mutation gate][aai-mutation],
[validation replay][aai-validation] and [contract projection][aai-contract].

The close-ceremony changes improve repository delivery checks and generated-page
provenance: INDEX and overview enumerate tracked documents, overview excludes
untracked local STATE, and PR ceremony verifies close/stamp commits. This covers
some consumed repository outputs; it does not provide generic saved-artifact or
external-application read-back. The bounded backcheck, controlled pilot and
optional external-executor recommendations therefore remain. Cooperation can
also share mutation-backed evaluator fixtures and frozen-contract drift cases.
The [post-merge correction][aai-reconcile] explicitly reopens ISSUE-0042 after a
false closure, so these controls must not be described as eliminating false
completion. See the [close-ceremony change][aai-close] and [release][aai-release].

## Findings

### Overall assessment

**Adopt selected verification and context practices; retain AAI's orchestration.
Explore LongHorizon as an optional execution service for GUI-heavy tasks only
after a controlled comparison.**

LongHorizon wraps agent CLIs in a manager → executor → auditor loop. Its manager
selects a bounded GUI or CLI subtask; later rounds receive persisted task state,
contract and audit reports. AAI already has durable state, role dispatch,
independent validation, recovery and model routing. The useful difference is
the specificity of LongHorizon's contract and final-application-state checks,
plus its interactive long-running computer-use runtime. [Upstream overview][lh-readme]

### What is worth adopting

| Idea | Existing AAI coverage | Verdict and concrete application |
| --- | --- | --- |
| Independently challenge the task contract against the original request | Validation already requires Requirement → Spec → Implementation → Evidence and an adversarial independent validator. It is not a missing validation layer. | **Adopt a targeted extension.** Require explicit detection of omissions, weakened constraints and substitute deliverables in the spec itself. Add it to validation and its report, not a new reviewer role. |
| Verify the state the user or application actually consumes | AAI checks current-tree evidence and has UI validation, but the inspected brief template is chiefly command/evidence oriented. | **Adopt for relevant tasks.** Identify the target artifact/application state and its persistence boundary: saved/exported/applied, correct account/path/version, with a reopen/read-back check. A screenshot or successful command alone may be insufficient. |
| Cite audited facts in subsequent execution context | AAI has briefs, FACTS, replay and evidence records. | **Pilot a sharper brief format.** Separate accepted facts with evidence references, executor claims awaiting verification, rejected artifacts, and outstanding constraints. Generate this from existing records; avoid another parallel state store. |
| Select relevant prior audit reports for each executor | AAI briefs and keyword replay already limit context. | **Measure before adopting.** Reference scoped evidence rather than whole transcripts; compare correctness and cost against current briefs. Upstream truncation is not semantic retrieval. |
| Fresh-context execution and durable round history | AAI has fresh validators and a fresh-context recovery tick after stagnation. | **Mostly already covered.** Do not restart every role solely to imitate upstream; measure whether recovery quality improves enough to offset context/cache cost. |
| GUI/CLI execution boundary and same-run follow-up messages | AAI is centered on development phases; current host tools already support some GUI work. | **Defer to an optional integration experiment.** Route by the state being changed, not simply by whether the selected tool is a shell or browser. |
| Durable operator command IDs, revisions and receipts | AAI already has durable workflow state; this research did not establish an equivalent cross-process steering protocol. | **Keep for a future interactive supervisor.** Borrow the protocol if AAI needs restart-safe stop/resume/message delivery; do not add it to a simple in-session loop. |
| Independent verification and model/backend assignment | AAI already has both and has current-tree validation freshness checks. | **Keep AAI's implementation.** Do not replace these controls with LongHorizon's text protocol. |
| Product-task benchmark and controlled ablations | Framework tests and operational metrics exist; this research did not establish an equivalent controlled long-task benchmark in AAI. | **Adopt the experimental method.** Measure actual task success, false completion, recovery and cost rather than framework test count. |

Local evidence:
[validation](../../.aai/VALIDATION.prompt.md),
[brief template](../../.aai/templates/BRIEF_TEMPLATE.md),
[replay](../../.aai/SKILL_REPLAY.prompt.md),
[loop recovery](../../.aai/SKILL_LOOP.prompt.md),
[dispatch and freshness](../../.aai/scripts/orchestration-dispatch.mjs),
[state transactions](../../.aai/scripts/lib/state-engine.mjs),
[telemetry](../../.aai/scripts/metrics-flush.mjs), and
[prompt hashing](../../.aai/scripts/lib/prompt-hash.mjs).

The original checkout had stale routing/dispatch roadmap labels. The refreshed
`origin/main` marks routing, test-framework sweep, dispatch/state sweep, mutation
gate and close ceremony done. Recommendations use inspected source and retain
those existing capabilities.

### Mechanisms and limits that matter

**Contract backcheck.** The auditor prompt reconstructs constraints from the
original request and compares the manager's contract against them. It also
distinguishes final-state requirements from historical-process guarantees, so
it does not invent an impossible obligation to prove that a transient action
never happened. This is useful for AAI's tendency toward accumulating ceremony.
It remains an LLM judgment; the stronger instructions do not prove better task
outcomes without an experiment. [Contract rules][lh-prompts]

**Completion has an executable gate, with a limited scope.** The loop accepts a
manager's completion only with an audit classified complete, clean and aligned.
The parser rejects malformed headers and downgrades completion when blocking
constraints are listed. These are real checks over an auditor's report, not a
proof that every factual claim in that report is true. [Audit parser][lh-audit],
[completion gate][lh-manager-done]

**Context is evidence-oriented but still prose.** The manager cites round IDs;
executors receive selected reports. Runtime feedback is kept separate from
auditor findings. Reports are clipped and aggregate context preserves the head
and tail, potentially omitting important middle evidence. AAI should preserve
original evidence references and fetch missing details on demand rather than
copy those character limits as a memory design. [Context assembly][lh-context]

**Resume is not rollback.** The manager reloads round history, state and contract.
The production `Environment` interface exposes execution, screenshots, upload
and download, without a checkpoint/restore operation. Reopening a run does not
undo filesystem writes, database changes, sent messages or GUI actions.
Moreover, a test explicitly permits completion immediately after resume using
an earlier clean audit. There is no mandatory post-resume revalidation in that
path. AAI's current-tree freshness control should be retained and generalized
to external targets before reusing a past verdict. [Resume implementation][lh-resume],
[resume test][lh-resume-test], [environment interface][lh-environment]

**Role separation is not consistently a security boundary.** The Codex adapter
defaults to bypassing approvals and sandboxing when no explicit sandbox mode
is provided. Claude's policy explicitly says its deny-list is role separation,
not a filesystem/process sandbox; auditors retain Bash and computer-use MCP.
Claude's before/after workspace manifest can detect changes within its coverage
but does not undo them or cover every external side effect. Preserve AAI's
independent evidence execution; do not interpret an observation-only auditor
prompt as enforced read-only access. [Codex adapter][lh-codex],
[Claude policy][lh-claude-policy], [workspace guard][lh-claude-guard]

**A potential AAI improvement is an inference, not a proven upstream feature.**
AAI's stagnation predicate tracks changes to focus and validation status, so
accepted progress inside a long phase can be invisible. Evidence-backed progress
units could improve it. This analysis did not establish that LongHorizon already
implements a superior quantitative stagnation detector. Likewise, duration and
round limits do not by themselves solve missing token/cost telemetry.

**Durable steering is a concrete runtime contribution.** The control bus stores
commands and receipts separately, serializes updates, checks command identity
and revisions, and uses durable writes. Resume generations distinguish old stop
commands from new ones. However, instruction draining records an applied receipt
before the manager persists and executes its next prompt. A crash in between is
a possible delivery gap inferred from source, not a reproduced failure; receipt
semantics must distinguish claimed from actually incorporated instructions.
[Control bus][lh-control], [instruction receipt][lh-injection],
[manager incorporation][lh-manager-injection]

### Benchmark evidence

The project reports the following results; none were reproduced in this research.
[Published table][lh-readme]

| Benchmark | Reported baseline → harness | Correct reading |
| --- | --- | --- |
| WeaveBench, 114 tasks | 51.8% → 80.7% pass rate | +28.9 percentage points; the paper defines a pass as score at least 0.8, not perfect fulfillment of every requirement. |
| OSWorld 2.0, 108 tasks | 2.8% → 8.3% full completion | Roughly threefold relative improvement, but +5.5 points and low absolute completion. |
| Terminal-Bench 2.1 | 69.7% → 77.2% success; reported 24% fewer tokens | +7.5 points; compare model, tool access, budgets and retries before transferring the claim. |

An unusually important reproducibility caveat appears in the Terminal-Bench
instructions: the original experiment code and prompts were lost during product
iteration, and the current version reconstructs them. Therefore the evaluation
directory does not establish exact reproducibility of the original headline
numbers. Production runtime and nested evaluation copies must also be treated
as distinct implementations. [Terminal-Bench note][lh-tb],
[evaluation layout][lh-eval]

The paper further limits causal interpretation: its OSWorld comparison uses an
official single-action GUI baseline against a hybrid GUI+CLI harness, with output
tokens rising from 28.9k to 104k per task. The gain cannot be attributed solely
to orchestration under equal tools and cost. WeaveBench uses 2.3 times the
baseline total tokens; the Terminal-Bench reduction is not a universal saving.
For Terminal-Bench, appendix A.3
names Claude Code 2.1.211 while the reproduction README defaults to 2.1.176.
These mismatches should be resolved in any shared reproduction manifest.
[Paper, evaluation and appendix][lh-paper], [Terminal-Bench setup][lh-tb]

### Product and integration fit

The repository declares MIT licensing and version 0.1.7. It contains tests and
an interactive runtime, but this pass establishes neither production reliability
nor a maintenance SLA. The README describes macOS as tested and Windows as not
thoroughly tested. Upstream Python/FastAPI/React architecture is a poor direct
dependency fit for AAI's portable, dependency-free vendored layer.
[Package manifest][lh-package], [license][lh-license], [platform notes][lh-readme]

## Recommendations

### First: one small AAI verification change

**Filed for Planning after operator continuation:**
[`original-request-outcome-backcheck`](../issues/CHANGE-0189-original-request-outcome-backcheck.md).
The operator approved preparing the intake and specification on 2026-09-23
(Europe/Prague). This updates the recommendation's disposition; implementation
and benchmark results are not claimed.

Extend the existing validation report/brief with the original constraint,
its source, the exact consumed target, the independent verification operation,
evidence identity and any unmet condition. A generated artifact should be checked
after saving/reopening; an API change by read-back; a repository change against
the current tree. Unknown required conditions prevent a completion claim.

Keep this concise and conditional: an ordinary code fix does not need GUI or
account fields. Preserve the existing maker/checker separation and scope rules.
Use one existing report schema and guard against duplicated STATE ownership.
This is a proposed behavior change requiring its own acceptance criteria and
tests, not a docs-only implementation implicitly authorized by this research.

### Second: a controlled pilot

**Suggested, not filed:** `longhorizon-comparative-pilot`.

Start with six representative, bounded tasks: two repository changes, two data
or document artifacts, and two mixed browser/CLI tasks. Include preservation
constraints, stale candidate artifacts and a durable save/export requirement.
Compare current AAI, AAI with the proposed backcheck, and standalone LongHorizon.
Use two repeats per task/variant, for 36 runs after a small smoke pass succeeds.

- Pin repository, prompt, fixture and agent CLI versions; use the same model,
  permissions/tool access and per-task wall-clock/token limits where possible.
  Label unavoidable GUI/tool differences explicitly rather than calling the
  comparison a harness-only ablation.
- Inject a planned stop/context restart into matched tasks. Change a target
  between stop and resume to test invalidation of old evidence; include a
  follow-up instruction delivered around the stop boundary.
- An evaluator separate from each harness checks final artifacts against the
  original requirements. Track success, false completion, lost constraints,
  repeated work, recovery success, human interventions, actual tokens/cost and
  elapsed time. Missing usage remains unknown.
- Proposed acceptance: zero false completions in the pilot and a measured
  benefit on targeted failure cases without loss on preservation constraints.
  Report the quality/cost tradeoff; do not infer statistical generality from
  this small sample. Select hard spend limits before executing paid runs.

### Cooperation: contribute evidence and narrow controls first

1. **Reproducible task fixtures and evaluation manifests.** Share synthetic AAI
   scenarios for wrong-target output, weakened specs, stale verdicts, interrupted
   execution and provenance loss. Pair every outcome with exact source/prompt
   versions, input snapshots and a standalone evaluator. This is useful to both
   projects and addresses an explicitly documented upstream reproducibility gap.
2. **Resume freshness and role-boundary regression cases.** Offer a minimal
   reproduction where an externally changed target invalidates an old audit;
   discuss optional target fingerprints/reinspection before changing upstream
   completion semantics. A second narrow contribution can test effective
   auditor permissions across backends. AAI contributes executable controls;
   upstream contributes real GUI/runtime failure cases. Start with existing
   [issue #1](https://github.com/AMAP-ML/LongHorizon-Harness/issues/1), which asks
   directly about re-auditing completed work. Check overlap with
   [PR #68](https://github.com/AMAP-ML/LongHorizon-Harness/pull/68) on stale
   success and [PR #75](https://github.com/AMAP-ML/LongHorizon-Harness/pull/75)
   on MCP isolation before proposing another patch; an open PR is not a
   released capability.
3. **Only then explore an optional external executor.** AAI owns requirements,
   scheduling and final acceptance. It submits one bounded GUI task to a pinned
   LongHorizon runtime in a separate workspace/environment, receives artifacts
   and raw evidence, then performs its own validation. Do not run two top-level
   planners over the same scope or allow both to write AAI STATE.

For the third option, define the boundary before implementation: task/constraint
IDs, allowed targets and actions, limits, evidence paths/fingerprints, result
status and failure reason. Map LongHorizon complete/blocked/incomplete/failed
into AAI handoff states; a remote “complete” is a claim awaiting AAI validation.
Use a subprocess/CLI or a versioned protocol rather than importing Python into
AAI core. Preserve user authorization for application and external actions.

The best first upstream discussion is a small reproducible case plus a testable
proposal, followed by a PR only after agreement on the intended semantics.
No outreach, issue filing or contribution has occurred in this research.

A useful alternative contribution is a PR-triggered portability test matrix.
The inspected release workflow runs Python tests on Ubuntu for version tags or
manual dispatch, without a regular PR trigger or Windows job. Existing Windows
reports [#77](https://github.com/AMAP-ML/LongHorizon-Harness/issues/77) and
[#81](https://github.com/AMAP-ML/LongHorizon-Harness/issues/81) give concrete cases;
contribute tests to ongoing fixes before starting a parallel platform rewrite.
[Release workflow][lh-ci]

## Open Questions

- Which real AAI failures recur often enough to justify the backcheck fields?
- Does per-round verification improve total cost per accepted task, or mainly
  shift cost into manager/auditor calls?
- Which GUI target could serve as a useful first downstream pilot?
- Would upstream accept a versioned evidence/export boundary and stricter
  resume freshness, or should those remain in the optional AAI adapter?
- Can the maintainers recover raw original results and clarify experimental
  differences sufficiently for an exact reproduction?

## Notes

Human intake time: 5 minutes, supplied by the operator in this session. Preserved
here because the installed `state.mjs` has no command for setting human intake
time; STATE was not hand-edited. The operator chose option 1, leaving the
implementation mode to Planning; no strategy override was recorded.
Research findings are complete for this source pass; `status: draft` follows the
intake identity/lifecycle contract and does not imply implementation or benchmark
completion. The original research pass changed this document and the generated
index; the subsequent operator-approved Planning step is tracked in the linked
change intake.

[lh-readme]: https://github.com/AMAP-ML/LongHorizon-Harness/blob/a1dd930614972b92361c1b9cd6aac441a6db5a65/README.md
[lh-prompts]: https://github.com/AMAP-ML/LongHorizon-Harness/blob/a1dd930614972b92361c1b9cd6aac441a6db5a65/src/lh_harness/prompt_texts.py#L225
[lh-audit]: https://github.com/AMAP-ML/LongHorizon-Harness/blob/a1dd930614972b92361c1b9cd6aac441a6db5a65/src/lh_harness/auditor_agent.py#L294
[lh-manager-done]: https://github.com/AMAP-ML/LongHorizon-Harness/blob/a1dd930614972b92361c1b9cd6aac441a6db5a65/src/lh_harness/manager.py#L1522
[lh-context]: https://github.com/AMAP-ML/LongHorizon-Harness/blob/a1dd930614972b92361c1b9cd6aac441a6db5a65/src/lh_harness/role_prompts.py#L643
[lh-resume]: https://github.com/AMAP-ML/LongHorizon-Harness/blob/a1dd930614972b92361c1b9cd6aac441a6db5a65/src/lh_harness/manager.py#L269
[lh-resume-test]: https://github.com/AMAP-ML/LongHorizon-Harness/blob/a1dd930614972b92361c1b9cd6aac441a6db5a65/tests/test_resume_manager_loop.py#L132
[lh-environment]: https://github.com/AMAP-ML/LongHorizon-Harness/blob/a1dd930614972b92361c1b9cd6aac441a6db5a65/src/lh_harness/environment/base.py
[lh-codex]: https://github.com/AMAP-ML/LongHorizon-Harness/blob/a1dd930614972b92361c1b9cd6aac441a6db5a65/src/lh_harness/adapters/codex.py#L57
[lh-claude-policy]: https://github.com/AMAP-ML/LongHorizon-Harness/blob/a1dd930614972b92361c1b9cd6aac441a6db5a65/src/lh_harness/adapters/claude_permissions.py#L33
[lh-claude-guard]: https://github.com/AMAP-ML/LongHorizon-Harness/blob/a1dd930614972b92361c1b9cd6aac441a6db5a65/src/lh_harness/adapters/claude_code.py#L129
[lh-tb]: https://github.com/AMAP-ML/LongHorizon-Harness/blob/a1dd930614972b92361c1b9cd6aac441a6db5a65/eval/TB-harness/README.md#L120
[lh-eval]: https://github.com/AMAP-ML/LongHorizon-Harness/blob/a1dd930614972b92361c1b9cd6aac441a6db5a65/README.md#L523
[lh-package]: https://github.com/AMAP-ML/LongHorizon-Harness/blob/a1dd930614972b92361c1b9cd6aac441a6db5a65/pyproject.toml
[lh-license]: https://github.com/AMAP-ML/LongHorizon-Harness/blob/a1dd930614972b92361c1b9cd6aac441a6db5a65/LICENSE
[lh-control]: https://github.com/AMAP-ML/LongHorizon-Harness/blob/a1dd930614972b92361c1b9cd6aac441a6db5a65/src/lh_harness/supervisor/control_bus.py#L464
[lh-injection]: https://github.com/AMAP-ML/LongHorizon-Harness/blob/a1dd930614972b92361c1b9cd6aac441a6db5a65/src/lh_harness/dashboard/state.py#L1145
[lh-manager-injection]: https://github.com/AMAP-ML/LongHorizon-Harness/blob/a1dd930614972b92361c1b9cd6aac441a6db5a65/src/lh_harness/manager.py#L364
[lh-paper]: https://arxiv.org/html/2608.01964v1
[lh-ci]: https://github.com/AMAP-ML/LongHorizon-Harness/blob/a1dd930614972b92361c1b9cd6aac441a6db5a65/.github/workflows/release.yml

[aai-mutation]: https://github.com/goodwind-cz/aai/blob/f84f84ab93348a321b6af803ba53ce0a526f53fc/.aai/scripts/mutation-gate.mjs
[aai-validation]: https://github.com/goodwind-cz/aai/blob/f84f84ab93348a321b6af803ba53ce0a526f53fc/.aai/VALIDATION.prompt.md#L209
[aai-contract]: https://github.com/goodwind-cz/aai/blob/f84f84ab93348a321b6af803ba53ce0a526f53fc/.aai/scripts/lib/spec-contract-hash.mjs
[aai-close]: https://github.com/goodwind-cz/aai/commit/b477fb3b
[aai-reconcile]: https://github.com/goodwind-cz/aai/commit/65fdfdc9
[aai-release]: https://github.com/goodwind-cz/aai/commit/f84f84ab
