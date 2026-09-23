---
id: spec-original-request-outcome-backcheck
type: spec
number: 183
status: implementing
ceremony_level: 2
links:
  requirement: original-request-outcome-backcheck
  rfc: null
  pr: []
  commits: []
---

# Spec — Original-request and persisted-outcome backcheck

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/CHANGE-0189-original-request-outcome-backcheck.md
- Research: docs/specs/RES-0004-longhorizon-harness-adoption.md
- Technology contract: docs/TECHNOLOGY.md

This is a frozen implementation contract, not implementation evidence. The
initial operator continuation covered Planning; the subsequent explicit
`aai-ship` invocation authorizes delivery through implementation, validation,
review and a pull request. This does not change the behavioral contract.

## Implementation strategy

- Strategy: tdd
- Rationale: the change decides whether validation evidence may reach PASS.
  Negative controls at the report-to-handoff boundary need observed RED before
  implementation. Planning chose the strategy; no intake-sourced choice applies.
  Semantic evaluation supplements deterministic tests and does not turn an LLM
  assessment into a mechanical proof.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: isolate changes to the validation completion boundary and
  disposable test fixtures from runtime reports and unrelated working changes.
- User decision: worktree (aai-ship autopilot); implementation used the
  dedicated feature worktree.
- Base ref: f84f84ab93348a321b6af803ba53ce0a526f53fc (origin/main at dispatch)
- Code review required: true; explicit scoped diff, independent dual verdict.
- Inline review scope: the exact paths listed in Implementation plan below;
  include only this scope's hunks. Unrelated changes need separate handling.

Ceremony justification: level 2 changes several validation seams but no path in
`protected_paths_l3` or the workflow's protected defaults. No state engine,
pre-commit guard, workflow canon or constitution change is authorized.

## Constitution deviations

Article 5: new Validation PASS result blocks must carry `outcome_report`; old
PASS blocks without it are refused by the upgraded handoff checker. This is an
intentional narrow compatibility break: silently accepting missing evidence
would defeat the requirement. Regenerate a current report when reusing a legacy
PASS. Historical reports remain untouched, other roles and FAIL/BLOCKED result
blocks retain their existing contract. The runtime report is additive Markdown.
Articles 1–4 and 6–7 have no deviations: measured evidence, one small checker,
plain files and stdlib, explicit refusals, existing STATE owner, no merge action.

## Scope and existing seams

The inspected routine producer is `.aai/VALIDATION.prompt.md`: its coverage,
verdict and evidence output has no dedicated report template. The optional
`.aai/SKILL_VALIDATE_REPORT.prompt.md` first runs that flow and then writes a
presentation report; it must preserve the authoritative outcome block.
`check-role-output.mjs --file` is already invoked by SUBAGENT_PROTOCOL's merge
step before returned state commands are run. `state.mjs set-validation` records
paths and a timestamp; it does not read report contents. `orchestration-dispatch`
compares current repository tree identity with the existing validation stamp.
The session-resident loop can stop on a prior PASS before dispatching a role.

Extend these seams, with one dependency-free checker and one structured block
inside the existing `docs/ai/reports/VALIDATION-<run_id>-<scope>.md` report. Do not
create a second evidence database, report authority, validator role, GUI service,
external adapter framework, orchestrator, runtime dependency, or benchmark.
No rollback, remote publication, outreach or unrelated cleanup belongs here.

Registry items closed by this scope: none

Registry scan: `node .aai/scripts/follow-ups.mjs list` on 2026-09-22 found 91 open
items. Related subjects deliberately remain open: `fu-rolecommon-ac-row-canon-conflict`
is the existing AC-flip policy conflict, not original-request checking;
`fu-check-committed-scope-folded` concerns staged-path parsing; and
`fu-openct-unrdbl-report` concerns factory report counts. This change neither
claims nor requires those fixes. Existing AC-status semantics stay intact.

Replay: searched original, validation, evidence, target, freshness, independence,
proof and report across knowledge files and decisions. LEARNED's staged-blob
TOCTOU lesson requires checking consumed bytes, and its whole-corpus lesson
requires classifying legacy reports rather than testing fixtures alone. Project
PATTERNS and FACTS contain no populated relevant entries; universal INDEX has no
overlapping pattern. No auto-memory source was supplied. Prior decisions about
false evidence and test-selector false success inform the non-vacuity controls.

## Acceptance Criteria Status

Every row remains planned until implementation produces evidence. The command
and observable references below resolve to Verification and Test Plan.

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN a declared original requirement is omitted, weakened, violated or unknown, the report checker SHALL refuse PASS; an aligned report SHALL pass. | planned |  |  | V1 TEST-001 green; delivery citation deferred to close. |
| Spec-AC-02 | WHEN an independent validator receives the six natural-language scenarios in S1, it SHALL inventory their material original constraints and report the specified gap or aligned result, with source and evidence citations. | planned |  |  | V2 semantic score 6/6; delivery citation deferred to close. |
| Spec-AC-03 | WHEN persistence is required, preview-only, wrong-target or mismatched saved bytes SHALL be refused; read-back of the exact saved target SHALL pass. | planned |  |  | V1 TEST-003 green; delivery citation deferred to close. |
| Spec-AC-04 | WHEN evidence is reused, changed local targets or dynamic observations older than the supplied verification horizon SHALL be refused; matching immutable targets and current observations SHALL pass without implementation restart. | planned |  |  | V1 TEST-004 green; delivery citation deferred to close. |
| Spec-AC-05 | WHEN a required block, source, evidence file, identity, status or link is missing, malformed or contradictory, the checker SHALL refuse with an outcome-specific reason after the enclosing result is otherwise valid. | planned |  |  | V1 TEST-005 green; delivery citation deferred to close. |
| Spec-AC-06 | WHEN routine validation hands off PASS, standalone Validation SHALL run the checker before state commands and dispatched Validation SHALL be mechanically checked by check-role-output; optional presentation SHALL retain the same block. | planned |  |  | V1 TEST-006/007 green; delivery citation deferred to close. |
| Spec-AC-07 | WHEN the loop starts or resumes with a reusable PASS, it SHALL check the outcome report before completion or dispatch; stale repository evidence SHALL still trigger existing current-tree validation. | planned |  |  | V1/V3 TEST-008/009 green; delivery citation deferred to close. |
| Spec-AC-08 | WHEN a code-only scope is validated, it SHALL pass with repository evidence and no GUI/account/persistence fields; other roles and non-PASS outputs SHALL retain their current behavior. | planned |  |  | V1/V3 TEST-010 green; delivery citation deferred to close. |
| Spec-AC-09 | The checker SHALL ship in the core profile, be selected by the existing test framework, and prompt growth SHALL have measured ledger accounting with no added runtime dependencies. | planned |  |  | V4 TEST-011 green; delivery citation deferred to close. |

## Implementation plan

### D1 — One report contract, two kinds of judgment

Add `.aai/scripts/validation-outcome-check.mjs`, usable as a CLI and imported
pure/read-only checker. Its header and `--help` document the single schema and
exit contract. Use exactly one fenced `aai-outcome-v1` block containing JSON in
the normal Markdown report. Do not extract JSON from arbitrary code examples or
accept the first of multiple blocks. Other report prose remains human-readable.

Required report data:

- Version 1, scope ref, validation start UTC, and source entries for intake and
  frozen spec: repository-relative path and SHA-256 of the bytes actually read.
  If the original request or an authorized correction is not represented by the
  intake, preserve its cited text in this report with provenance. Unavailable
  material source text is unknown and blocks PASS; do not invent a transcript.
- A nonempty requirement inventory with unique IDs, source citation/quote,
  material constraint text, corresponding Spec-AC IDs (empty for a gap), semantic
  assessment (`aligned`, `omitted`, `weakened`, `unknown`) and rationale. Assess
  preservation, exact-target and relevant process constraints from the original
  request, not just numbered intake ACs. Do not invent historical restrictions.
- For each requirement, linked outcome/evidence entries with a unique ID, target
  kind (`repository`, `local_file`, `external`), exact expected identity, observed
  identity, verification operation, evidence file path and SHA-256, observation
  UTC and result (`satisfied`, `violated`, `unknown`). Evidence references must
  resolve; dangling, duplicate and empty links refuse. A required unknown result
  never becomes not-applicable simply to clear the gate.
- Persistence applicability is semantic: only applicable entries require the
  saved/exported/applied boundary and read-back/reopen observation. A code-only
  repository result needs no account, GUI or save fields. External identity may
  include account/workspace/object/revision only where the request requires it.
  A reason accompanies not-applicable; the checker does not judge that reason's
  truth. Preview output cannot supply a required saved-state observation.
- Local-file observations include the consumed file path and SHA-256, distinct
  from a screenshot/log path. Compare expected and observed canonical paths and
  re-read the consumed bytes. Evidence files and source files are also re-hashed.
  Resolve relative paths against an explicit repository root, never the report's
  directory; do not execute commands or URLs stored in a report.
- External entries declare mutable/dynamic or an immutable revision target.
  Dynamic evidence needs observation at/after the caller's verification horizon.
  An immutable revision exemption requires evidence establishing that the
  required deliverable is that pinned revision, not the live/latest alias.
  Version text alone is not proof of immutability or of the current live target.

The validator independently decides inventory completeness, original intent,
semantic alignment, applicability, truth of read-back and whether an external
revision is truly immutable. The checker enforces shape, links, identities,
bytes, declared statuses and timestamps. A syntactically consistent false claim
can fool it. Its success means the report is mechanically admissible, never that
arbitrary prose or application state has been proven true.

### D2 — Checker and verification horizon

CLI: `node .aai/scripts/validation-outcome-check.mjs --report <path> --ref <ref>
--since <UTC> [--root <repo>]`. The default root is CWD; `--since` is mandatory.
Exit 0 means mechanically admissible; exit 1 is evidence refusal with stable
`OUTCOME-CHECK: <reason>` diagnostics; exit 2 is invalid CLI usage. Missing or
unreadable report/data is an evidence refusal. Unknown schema versions, duplicate
blocks, invalid dates and contradictory required entries fail closed. Compare
current source/evidence/local-target hashes at each invocation. Do not replace
or restamp repository-tree freshness; repository targets continue to rely on the
existing dispatch tree check. No arbitrary age TTL is introduced.

`--since` defines this verification attempt, not when the whole implementation
began. Standalone Validation uses its system-clock start time; dispatched checks
use the result's `started_utc`. The loop captures a new horizon once at entry or
resume and reuses it during that uninterrupted invocation. An interruption does
not invalidate matching immutable file bytes. Dynamic observations predating a
new horizon require renewed observation. Changed immutable bytes still refuse.
Fresh timestamp text is mechanically checked, but the observation's authenticity
is the independent validator's responsibility. No network request is made by
the checker. Future observation dates relative to its system clock refuse.

### D3 — Real handoff and resume wiring

1. VALIDATION steps 2–3 independently reconstruct the original constraints;
   step 6 writes the normal report including D1; before any PASS claim or step 9
   commands, execute D2 and honor refusal. Sole-agent mode then uses the existing
   state CLI. Dispatched mode returns its commands only, plus `outcome_report`
   as a scalar path extension in the existing result block. That path is also
   included in returned `set-validation --evidence` and refers to this scope.
2. `check-role-output.mjs` makes `outcome_report` mandatory for Validation PASS
   only and calls the same checker using scope and started_utc before accepting
   the result. A failure produces `E-OUTCOME-REPORT` and exits 1. Keep the existing
   checks and binary exit contract. Report absence is not a compatibility bypass.
   Do not execute or shell-parse returned state command strings. The protocol
   merge must verify that the report it accepted is the evidence path passed to
   state; a focused prompt clause and handoff scenario test cover that agent-owned
   step. Existing `AAI_ROLE=subagent` enforcement stays unchanged.
3. Standalone and dispatched return paths share the report and checker. Update
   BRIEF_TEMPLATE's evidence guidance and SUBAGENT_CONTRACT's extension guidance;
   keep their Return Record skeletons synchronized. The optional visual-report
   skill preserves the block and reruns its check if rewriting the report;
   `LATEST.md` stays a pointer, never the evidence authority.
4. SKILL_LOOP at entry/resume captures its horizon and, before its PASS completion
   stop or role dispatch, checks the current focus's validation report when a
   standing PASS is considered. A missing legacy report or refused check prevents
   completion. Route the current scope to fresh Validation with existing state
   setters through the sole STATE writer; do not restart implementation, mark
   unrelated work failed or modify immutable artifacts. Use the normal dispatch
   path so existing current-tree invalidation still runs. A dynamic target needs
   a fresh observation, not a fabricated clock update. Do not use a prior PASS
   for a different ref. A new Validation within the same loop horizon can proceed
   to review/close without an endless revalidation cycle.

Enforcement boundary: the dispatched merge has a deterministic report gate;
standalone Validation and loop entry/resume invoke it by prompt contract. A
caller that bypasses those prompts and directly runs `state.mjs set-validation
--status pass` can still record PASS. Raw orchestration invoked outside the loop
also has no new external-target resume signal. This scope does not claim a global
state-CLI guard, tamper-proof observations, or universal session interception.
Changing the protected state engine or adding a session protocol is out of scope.

### S1 — Seams and explicit semantic evaluation

- Original source → validator inventory → report: TEST-002 uses six independent
  fresh-context scenarios. Original texts contain (1) an omitted preservation
  constraint, (2) a weakened exact numeric constraint, (3) an aligned code-only
  request, (4) required persistence with preview only, (5) saved wrong path, and
  (6) read-back of the exact required saved file. The first, second, fourth and
  fifth must fail with the actual original constraint cited; third and sixth
  pass. Fixture oracle names are kept from the validator. Score the generated
  reports against that oracle, retaining source text and outputs. Do not supply
  pre-filled assessment labels and call this a test of semantic detection.
- Report → checker → dispatched result acceptance: TEST-006 builds a valid result,
  real report and real files, invokes the actual CLI, then changes one evidence
  condition. The good control must pass; the bad control must fail specifically
  at `E-OUTCOME-REPORT`, not timing, missing fixture, model or AC-status gates.
- Standalone producer → check → state command, and visual rewrite → check:
  TEST-007 exercises the specified sequence in an isolated fixture through the
  real helper and state CLI. Because Markdown is not executable, static order
  assertions supplement this harness; a fresh independent role rehearsal records
  whether the prompt actually followed that sequence. A shell transcription
  alone proves the commands, not agent compliance.
- Loop re-entry → freshness → dispatch/stop: TEST-008 models two invocations with
  explicit horizons, reuses real report/files, then follows the actual checker
  and existing state/dispatch CLIs in a disposable repo. Include fresh dynamic
  evidence advancing to Code Review and unchanged immutable reuse. TEST-009
  reruns the existing tree-change and validator-isolation regression controls.

The finite semantic evaluation is a quality gate for these scenarios, not a
statistical claim about all tasks. No live GUI/network benchmark is required;
local saved-file read-back crosses a real persistence boundary. Authenticating
external observations, unexpected concurrent external edits after observation,
and correct prompt execution outside these rehearsals remain residual risks.

### Exact intended file scope

- `.aai/VALIDATION.prompt.md`
- `.aai/SKILL_LOOP.prompt.md`
- `.aai/SKILL_VALIDATE_REPORT.prompt.md`
- `.aai/SUBAGENT_CONTRACT.md`
- `.aai/SUBAGENT_PROTOCOL.md`
- `.aai/templates/BRIEF_TEMPLATE.md`
- `.aai/scripts/validation-outcome-check.mjs` (new; schema, checker and CLI)
- `.aai/scripts/check-role-output.mjs`
- `.aai/system/PROFILES.yaml` (new checker in core)
- `tests/skills/test-aai-outcome-backcheck.sh` (new, bash 3.2)
- `tests/fixtures/outcome-backcheck/` (only six semantic scenario inputs/oracles
  and the minimal report fixtures for this spec; generated reports stay runtime)
- `tests/skills/test-aai-role-output.sh` and
  `tests/fixtures/role-outputs/validation-valid.md` (new PASS contract integration)
- `tests/skills/suite-map.yaml` (register all changed production paths)
- `tests/skills/test-aai-hygiene-pack.sh` (update the top-level suite-count
  pin for the new registered outcome suite)
- `tests/skills/test-aai-close-work-item.sh` (validation-remediation fixture
  role isolation: ordinary disposable close commands explicitly model the
  orchestrator; the deliberate subagent-refusal arm stays explicit)
- `tests/skills/lib/prompt-diet-ledger.sh` (measured JUSTIFIED_ADDITIONS entry)
- `tests/skills/test-aai-prompt-diet.sh` (bump TEST-012 checkpoint)
- This spec, its intake and `docs/INDEX.md` only for normal lifecycle bookkeeping;
  `CHANGELOG.md` and `docs/USER_GUIDE.md` only for this behavior and compatibility
  note. Brief/reports/TDD logs and Planning result are runtime evidence.

Read existing tests and their fixture assumptions before updating them. Do not
weaken unrelated assertions merely because new Validation PASS needs evidence.
No production edits were made by Planning.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Status |
|---|---|---|---|---|---|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-outcome-backcheck.sh | V1: aligned control passes; omitted/weakened/unknown/violated rows each refuse with outcome reason. | green |
| TEST-002 | Spec-AC-02 | manual | tests/fixtures/outcome-backcheck/ | V2: six fresh-context source-to-report semantic scenarios, six correct results and original-constraint citations; keep unedited reports. | green |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-outcome-backcheck.sh | V1: write real saved file, independently reopen it, check correct target; preview/wrong path/modified bytes each refuse. | green |
| TEST-004 | Spec-AC-04 | integration | tests/skills/test-aai-outcome-backcheck.sh | V1: two horizons; old dynamic observations refuse, refreshed ones pass; matching immutable reuse passes, changed bytes refuse. | green |
| TEST-005 | Spec-AC-05 | unit | tests/skills/test-aai-outcome-backcheck.sh | V1: malformed/duplicate/missing block, missing sources/evidence, mismatched hashes, duplicate/dangling IDs, future dates and contradictory required results refuse after valid-envelope control. | green |
| TEST-006 | Spec-AC-06 | integration | tests/skills/test-aai-role-output.sh | V1: actual --file CLI reads report; normal PASS accepts, missing/false-complete report refuses E-OUTCOME-REPORT, no state mutation occurs. | green |
| TEST-007 | Spec-AC-06 | integration | tests/skills/test-aai-outcome-backcheck.sh | V1: standalone report-check-state sequence and visual rewrite preservation; prompt order plus independent rehearsal; poison evidence suppresses state PASS. | green |
| TEST-008 | Spec-AC-07 | integration | tests/skills/test-aai-outcome-backcheck.sh | V1: resume before completion and dispatch, legacy missing report fails, immutable reuse and fresh dynamic advance, unrelated focus unaffected. | green |
| TEST-009 | Spec-AC-07 | regression | tests/skills/test-aai-orchestration-dispatch.sh | V3: existing changed-tree and focus-mismatch controls remain effective; existing independent validator controls remain green. | green |
| TEST-010 | Spec-AC-08 | integration | tests/skills/test-aai-outcome-backcheck.sh | V1/V3: concise code-only block accepted, no fabricated GUI fields; Planning/Implementation/Review and Validation FAIL/BLOCKED compatibility controls. | green |
| TEST-011 | Spec-AC-09 | contract | tests/skills/test-aai-layer-profiles.sh | V4: core import closure, suite selection, dependency absence, measured prompt-diet ledger and checkpoint. | green |

Counts: 7 integration, 1 unit, 1 manual, 1 regression, 1 contract. Every added
suite/test selector must refuse an unknown name; zero selected cases is failure.

## Verification

All test commands run from the repository root through the canonical wrapper.
Use `test-framework.sh --skill` for real suites so its fixture isolation applies.
The following named commands decide the AC observables above:

- V1: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh --skill aai-outcome-backcheck --skill aai-role-output`.
  Exit 0 and every listed deterministic TEST case executed with its positive and
  negative assertions. Retain stdout/stderr showing each actual refusal reason.
- V2: after the six independent role runs on S1 inputs,
  `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-outcome-backcheck.sh --semantic-reports docs/ai/reports/original-request-outcome-backcheck/semantic`.
  Implement this explicit scorer mode to read only the six generated reports and
  fixture oracle; exit 0 requires six present cases, zero misclassified results,
  all required source citations, and checker-admissible positive cases. A missing
  or duplicated case fails. Archive role inputs/outputs and the model/context
  provenance actually available. No model is invoked by this command itself.
  The wrapper intentionally excludes ignored runtime reports, so prepare a
  byte-identical outside-tree score root from the archived
  `semantic/candidate/` reports and each archived scenario input, verify it
  against `input-integrity.json`, then run the same wrapped scorer with
  `--semantic-reports /tmp/aai-outcome-semantic-score-input`. This preserves
  the six fixed cases and their original bytes; it is not a fixture rewrite or
  a weaker in-repository fallback.
- V3: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh --skill aai-orchestration-dispatch --skill aai-validator-isolation --skill aai-role-output`.
  Exit 0; name the exercised current-tree and maker/checker controls in the report.
- V4: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh --skill aai-layer-profiles --skill aai-prompt-diet --skill aai-suite-select`.
  Also
  `node .aai/scripts/select-suites.mjs --files-from docs/ai/reports/original-request-outcome-backcheck/changed-paths.txt`
  must select the new suite for every changed production path. Exit 0 alone is
  insufficient: inspect the selected suite IDs. No package manifest or third-party
  import may appear in the scoped diff.

RED first: store `docs/ai/tdd/original-request-outcome-backcheck/TEST-xxx-red.log`
and corresponding green logs for new AC-gating behavior, including RED_CLASS,
exact command, exit and failed assertion. Start with the existing handoff accepting
a complete Validation PASS envelope without the outcome contract; the regression
asserts refusal and must fail on baseline for that reason. Introduce checker
unit cases only once the harness can reach their intended assertion. A missing
executable/module/fixture is infrastructure failure, not the qualifying RED.
For prompt wiring, remove the new call on a disposable copy and observe the
wiring assertion fail; pair this with the real boundary test, not token grep alone.
For existing preservation tests, retain fresh green runs and mutation controls
for any new assertion; do not manufacture a pre-change failure of preserved code.

Semantic RED honesty: run the six scenarios against the old instructions as well
as the proposed instructions in independent contexts. The old validator may
already identify a gap: report that result faithfully. The new report-contract
assertion must fail without the change; do not claim that failure proves improved
semantic reasoning. No scenario may be weakened to obtain a convenient RED.

Corpus sweep: enumerate existing validation Markdown reports and classify counts
as supported v1 / legacy absent block / malformed v1, with paths and reasons.
Run the checker against every v1 instance with its declared horizon and real
files, report stale/missing runtime evidence explicitly. Legacy classification
is not a PASS and does not rewrite history. A legacy report offered as current
handoff/resume evidence is refused until regenerated. Count zero honestly if no
v1 reports exist before implementation. Run one full framework sweep before
close per existing workflow; avoid repeating it for every intermediate round.

Platform matrix: shared Node stdlib checker and bash-3.2 tests; retain macOS/Linux
wrapper behavior and the existing Windows PowerShell 5.1/7 dispatcher contracts.
No PowerShell or wrapper implementation changes are in scope. Record platform
coverage actually executed; unavailable Windows execution remains unverified,
never inferred from a POSIX run.

## Evidence contract

Every artifact names ref `original-request-outcome-backcheck`, Spec-AC/TEST IDs,
command or scoped diff, exit/verdict, path, observed timestamps and commit/diff
identity where available. Use `docs/ai/tdd/original-request-outcome-backcheck/`
for stored RED/GREEN, and `docs/ai/reports/original-request-outcome-backcheck/`
for semantic runs, corpus inventory and rehearsal logs. The independent final
report uses the existing VALIDATION filename convention and records the new
outcome block. Verify RED logs with `tdd-evidence-check.mjs`; infra_fail and
unclassified new logs do not qualify. All new TEST obligations must be green,
semantic score 6/6, and existing gates clear before Validation may claim PASS.
The production behavior has not been tested in Planning.
