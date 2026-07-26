---
id: spec-friction-capture-default-on
type: spec
number: 88
status: draft
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0062-friction-capture-default-on.md
  rfc: RFC-0012
  pr: []
  commits: []
---

# Spec — Activate the friction feedback loop: default-on shadow capture + wrap-up triage feed

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0062-friction-capture-default-on.md
- RFC: docs/rfc/RFC-0012-aai-self-improvement-feedback-loop.md (Phase 1/2), docs/rfc/RFC-0013-friction-record-v2-redaction.md
- Object under change: .aai/system/FRICTION_PROTOCOL.md ("Skill wiring (shadow capture)" seam)
- Technology contract: docs/TECHNOLOGY.md

## Problem (root cause, not symptom)

RFC-0012 shipped the entire capture stack (CLI, schema v1/v2, redaction, offline
triage, review-mode upsert, discovery nudge) and `docs/ai/friction/` still holds
only `.gitkeep`. The stack works; nothing feeds it. The intake asks Planning to
root-cause the zero-capture reality before designing the fix. The table below maps
this session's four known AAI-owned friction events against the taxonomy, the
exclusions, and the seam AS WRITTEN, and answers for each: would the seam have
captured it, and if not, WHERE does it structurally fail.

### Root-cause table — would the seam-as-written have captured each event

| Event | Best taxonomy fit | Seam-as-written capture? | Structural failure locus |
|-------|-------------------|--------------------------|--------------------------|
| Validator subagents stalling on dead monitors | abstraction_leak_recovery (recovery work from an AAI abstraction leak) | No | Recall-dependence plus exclusion-too-broad. A stall has no clean event where the seam says "record now"; mid-stall the agent is recovering, not filing. The "transient provider/network failures" exclusion invites misclassifying a dead-monitor stall as transient, so the ownership gate reads NOT-AAI. |
| Spec AC-table escaped-pipe parser break caught only by CI | deterministic_script_failure (deterministic AAI parser/contract failure) | No | Missing hook point plus no salient in-session signal. The parser SILENTLY drops the row; the authoring agent sees no error, so recall has nothing to trigger on. CI caught it later, and the seam names no "CI check failure handled" hook, so the CI-handling context never records either. |
| Stale L3 zero-diff test landmines | missing_or_invalid_artifact (invalid AAI-owned test file) | No | Recall-dependence plus no gate-failure hook. Discovered only when they detonate mid-debug; the agent is chasing green, and the seam offers no "gate/lint/test failure on a canon file" hook that makes capture the default at that deterministic moment. |
| Prompt-diet headroom-cap trap | contract_violation (documented AAI contract that traps the caller) or abstraction_leak_recovery | No | Recall-dependence plus "working-as-designed" bias. Hitting the cap forces a ledger true-up (recovery work); the agent completes it and moves on, reading the trap as expected behavior rather than friction, and "when in doubt, do not record" biases toward silence. No hook fires at the cap breach. |

### The one structural root cause (what the four share)

Every row fails for the SAME reason: the seam is **purely recall-dependent**. It
says "While running any AAI skill, record ONLY when you hit evidence ... When in
doubt, do not record." Capture therefore requires the agent, mid-failure, to (a)
notice the event is AAI-owned, (b) remember the protocol exists, (c) pause recovery
to build a JSON observation and invoke the CLI, and (d) overcome an explicit
do-not-record bias. There is NO deterministic point in any workflow where the
prompt makes capture the DEFAULT (best-effort) action. Zero captures is the exact
predicted outcome of a recall-only seam. Two secondary contributors amplify it:
the exclusion list is broad enough to swallow real AAI failures (dead-monitor
stall read as "transient"), and there is no hook at the two moments AAI-owned
failures are MOST salient and deterministic — a recorded validation FAIL, a
dispatched remediation, and a canon-file gate/lint/CI failure.

### What the design must therefore do (follows from the table)

1. Convert the seam from recall-only to **default-on at deterministic hook points**
   — name the hooks in the protocol and wire a thin best-effort capture pointer at
   each one in the owning prompts (validation FAIL, remediation dispatch,
   canon-file gate/lint/CI failure). This kills recall-dependence at exactly the
   moments the four events occurred.
2. Keep the ownership gate but stop the broad exclusions from eating AAI-owned
   failures at those hooks: at a deterministic AAI hook the default is ATTEMPT (the
   taxonomy + best-effort swallow still apply; the change is the default, not the
   gate).
3. Close the loop on the OUTPUT side: make wrap-up step 6 ALWAYS surface a
   non-empty spool as a triage report plus proposed-intake one-liners, so captured
   data becomes visible action instead of a silent file.
4. Preserve every existing invariant: best-effort, never masks the caller, local
   only, no network, no schema change, no new external destination.

## Implementation strategy
- Strategy: loop
- Rationale: The change is prompt/protocol wiring plus a wrap-up prose step plus
  grep/integration guard tests — mechanical, low-risk, single-domain. No new
  script logic: the capture CLI (schema v2, best-effort, atomic append) and the
  triage engine already exist and are separately tested. RED-GREEN per test adds
  little signal beyond the mandatory RED-proof, which is required here regardless
  of strategy: every AC-gating guard test MUST be observed FAILING on the current
  (un-wired) tree before its green counts (grep guards fail today because the hook
  enumeration and pointers do not yet exist; the negative-control test fails today
  because the swallow contract is not yet asserted at the hook).

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: Documentation/prompt/protocol wiring plus test edits, no code
  logic and no protected surface; trivially reversible and confined to one domain.
  A worktree adds overhead without safety benefit. (Matches the sibling friction
  wiring specs, which shipped inline.)
- User decision: undecided
- Base ref: main (branch feat/friction-capture-default-on)
- Worktree branch/path: n/a
- Inline review scope: .aai/system/FRICTION_PROTOCOL.md, .aai/VALIDATION.prompt.md,
  .aai/REMEDIATION.prompt.md, .aai/SKILL_PR.prompt.md, .aai/SKILL_WRAP_UP.prompt.md,
  tests/skills/test-aai-friction-wiring.sh, tests/skills/lib/prompt-diet-ledger.sh,
  docs/specs/SPEC-0088-spec-friction-capture-default-on.md,
  docs/issues/CHANGE-0062-friction-capture-default-on.md, CHANGELOG.md

## Acceptance Criteria Mapping

For each intake AC:

- Maps to: CHANGE AC-001
- Spec-AC-01: The FRICTION_PROTOCOL "Skill wiring (shadow capture)" seam enumerates
  deterministic hook points (at minimum: validation FAIL, remediation dispatch, and
  canon-file gate/lint/CI failure) as the default-on capture moments, and each
  owning prompt (VALIDATION, REMEDIATION, and SKILL_PR for the CI point) carries a
  thin grep-verifiable pointer that invokes best-effort capture at its hook. The
  existing seam heading and the exact record command line are preserved (existing
  pins do not break).
  - Verification: `bash tests/skills/test-aai-friction-wiring.sh` (hook-enumeration
    and per-prompt pointer cases) exit 0; existing TEST-001/TEST-004 pins still pass.

- Maps to: CHANGE AC-002
- Spec-AC-02: Running the documented record command with a fixture AAI-owned
  schema-v2 observation appends exactly one valid v2 spool line carrying the v2
  structured-signal keys; a fixture whose failure_class is outside the closed
  taxonomy (an excluded, non-AAI case) is rejected with a non-zero exit and no
  spool line, proving the taxonomy remains the ownership gate.
  - Verification: `bash tests/skills/test-aai-friction-wiring.sh` (v2 record case +
    exclusion-rejection case) exit 0.

- Maps to: CHANGE AC-003
- Spec-AC-03: SKILL_WRAP_UP step 6, on a NON-EMPTY spool, runs the offline triage
  engine and surfaces the top review-candidate clusters as proposed-intake
  one-liners; on an EMPTY spool it stays silent. The triage engine produces a
  report with at least one cluster from a non-empty fixture spool.
  - Verification: `bash tests/skills/test-aai-friction-wiring.sh` (wrap-up triage
    grep + triage-on-fixture-spool integration case) exit 0;
    `bash tests/skills/test-aai-feedback-status.sh` exit 0 (empty-spool silence
    unregressed).

- Maps to: CHANGE AC-004
- Spec-AC-04: A hook-point capture that FAILS (e.g. an unwritable spool directory)
  leaves the primary step's own exit code unchanged, and the seam plus every hook
  pointer state the best-effort / never-mask / swallow contract.
  - Verification: `bash tests/skills/test-aai-friction-wiring.sh` (negative-control
    case: capture failure preserves the wrapper exit code) exit 0.

- Maps to: CHANGE AC-005
- Spec-AC-05: No regression. The targeted friction, friction-wiring, prompt-diet,
  hygiene-pack, and feedback-status suites pass locally, and the prompt-diet ledger
  is trued up for the in-glob prose growth (one new JUSTIFIED_ADDITIONS entry plus
  the TEST-012 checkpoint bumped from its current 27805 to the re-summed value).
  The full framework run is binding on PR CI.
  - Verification: `bash tests/skills/test-aai-prompt-diet.sh` exit 0;
    `bash tests/skills/test-aai-friction.sh` exit 0;
    `bash tests/skills/test-aai-friction-wiring.sh` exit 0;
    `bash tests/skills/test-aai-hygiene-pack.sh` exit 0; PR CI full run green.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC    | Description                                                        | Status  | Evidence | Review-By | Notes |
|------------|-------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Seam enumerates deterministic hooks plus wired best-effort pointers | done | docs/ai/tdd/friction-capture-default-on-GREEN-wiring-full.log (TEST-001..004 pass) | —         | Implementation, pre-validation |
| Spec-AC-02 | v2 record via documented command; excluded case rejected           | done | docs/ai/tdd/friction-capture-default-on-GREEN-wiring-full.log (TEST-012/013 pass) | —         | Implementation, pre-validation |
| Spec-AC-03 | Wrap-up step 6 triage plus proposed intakes; empty stays silent    | done | docs/ai/tdd/friction-capture-default-on-GREEN-wiring-full.log (TEST-014/015 pass) | —         | Implementation, pre-validation |
| Spec-AC-04 | Capture failure never changes the primary step exit code           | done | docs/ai/tdd/friction-capture-default-on-GREEN-wiring-full.log (TEST-016 pass) | —         | Implementation, pre-validation |
| Spec-AC-05 | No regression; prompt-diet ledger trued up; CI binding             | done | docs/ai/tdd/friction-capture-default-on-GREEN-prompt-diet.log and friction-capture-default-on-GREEN-companions.log (all exit 0) | —         | Local suites green; PR CI full run remains binding |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan

Components/modules affected:
- `.aai/system/FRICTION_PROTOCOL.md` (system doc, NOT prompt corpus, no ledger
  cost): extend the "Skill wiring (shadow capture)" seam with a "Deterministic hook
  points" subsection. Enumerate the hooks and state that at each one capture is the
  DEFAULT best-effort attempt (not recall-gated), that the taxonomy and the
  best-effort/swallow/never-mask contract still apply, and that a hook capture uses
  schema v2. Keep the exact heading `## Skill wiring (shadow capture)` and the exact
  line `node .aai/scripts/aai-friction.mjs record --input <path or ->` intact.
  MUST NOT introduce any Phase-2 token inside the seam section (the wiring suite
  TEST-005 rejects `aai-feedback-triage`, `feedback.yaml`, `upsert`, and any
  `gh issue/pr/api` inside the seam) — the triage wiring lives in SKILL_WRAP_UP,
  not the seam.
- `.aai/VALIDATION.prompt.md` (prompt corpus): thin best-effort friction-hook
  pointer at the FAIL-verdict point (step 8) and the canon-file gate/lint failure
  point (step 5), naming the seam and the record command form.
- `.aai/REMEDIATION.prompt.md` (prompt corpus): thin best-effort friction-hook
  pointer at the dispatch/categorize point (step 1/2) for the AAI-owned root cause.
- `.aai/SKILL_PR.prompt.md` (prompt corpus): thin best-effort friction-hook pointer
  at the post-open CI-failure handling point (step 5d) for the "CI check failure
  handled" hook.
- `.aai/SKILL_WRAP_UP.prompt.md` (prompt corpus): extend step 6 so a non-empty
  spool ALWAYS runs the triage engine and lists top review-candidate clusters as
  proposed-intake one-liners; empty spool stays silent (unchanged silence
  contract).
- `tests/skills/test-aai-friction-wiring.sh`: extend with the new hook-enumeration,
  per-prompt pointer, v2-record, exclusion-rejection, wrap-up-triage, and
  negative-control cases (new suite-local TEST ids appended after the existing
  TEST-007, no renumbering of TEST-001..007).
- `tests/skills/lib/prompt-diet-ledger.sh`: one new JUSTIFIED_ADDITIONS entry for
  the measured in-glob growth of VALIDATION/REMEDIATION/SKILL_PR/SKILL_WRAP_UP; the
  entry's leading byte field is the measured deficit so the re-summed
  JUSTIFIED_GROWTH_BYTES lands headroom within [0, 2048]. The TEST-012 checkpoint
  constant (currently 27805) is bumped to the re-summed value.

Data flows / seams (PLANNING step 6a):
- SEAM A (protocol seam to owning prompts): the hook enumeration produced in
  FRICTION_PROTOCOL is CONSUMED by the wired prompts. Crossed end-to-end by TEST-005
  below (run the documented command from a hook fixture, assert the real spool line).
- SEAM B (capture spool to wrap-up triage): capture at a hook writes the spool,
  which SKILL_WRAP_UP step 6 consumes via the triage engine to produce the report
  and proposed intakes. Crossed end-to-end by TEST-007 (produce a spool line via the
  CLI, then run the triage engine, assert clusters), not two mocked unit tests.
- SEAM C (prompt corpus to prompt-diet ledger, companion): grown prompts consume the
  ledger's headroom; crossed by TEST-010 (real prompt-diet suite green after the
  ledger true-up).

Edge cases:
- Empty spool: wrap-up step 6 and the discovery nudge both stay silent (do not
  regress test-aai-feedback-status TEST-004).
- Capture failure at a hook (unwritable dir, absent CLI, rejected input): swallowed,
  primary exit code preserved (Spec-AC-04).
- Existing pins: seam heading, record command line, no-Phase-2-token-in-seam,
  AGENTS.md no-`failure_class` — all preserved.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                        | Description                                                                                  | Status  |
|----------|------------|-------------|---------------------------------------------|----------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-friction-wiring.sh    | Seam enumerates deterministic hooks naming validation-FAIL, remediation-dispatch, canon gate/lint/CI failure | green |
| TEST-002 | Spec-AC-01 | unit        | tests/skills/test-aai-friction-wiring.sh    | VALIDATION and REMEDIATION each carry a grep-verifiable best-effort friction-hook pointer to the seam | green |
| TEST-003 | Spec-AC-01 | unit        | tests/skills/test-aai-friction-wiring.sh    | SKILL_PR carries the CI-failure hook pointer; existing seam heading and record command pins still pass | green |
| TEST-004 | Spec-AC-01 | unit        | tests/skills/test-aai-friction-wiring.sh    | Negative control: removing the hook enumeration or any wired pointer fails the guard (teeth) | green |
| TEST-005 | Spec-AC-02 | integration | tests/skills/test-aai-friction-wiring.sh    | SEAM A: documented record command with a v2 AAI-owned fixture appends exactly one v2 spool line, exit 0 | green |
| TEST-006 | Spec-AC-02 | integration | tests/skills/test-aai-friction-wiring.sh    | A fixture with a non-taxonomy (excluded) failure_class is rejected non-zero with no spool line | green |
| TEST-007 | Spec-AC-03 | integration | tests/skills/test-aai-friction-wiring.sh    | SEAM B: non-empty fixture spool run through the triage engine yields a report with at least one cluster | green |
| TEST-008 | Spec-AC-03 | unit        | tests/skills/test-aai-friction-wiring.sh    | SKILL_WRAP_UP step 6 names the triage invocation plus proposed-intake surfacing and keeps the empty-spool silence contract | green |
| TEST-009 | Spec-AC-04 | integration | tests/skills/test-aai-friction-wiring.sh    | Negative control: a hook capture into an unwritable spool preserves the primary step exit code | green |
| TEST-010 | Spec-AC-05 | integration | tests/skills/test-aai-prompt-diet.sh        | Prompt-diet suite green with the new JUSTIFIED_ADDITIONS entry and TEST-012 checkpoint re-summed from 27805 | green |
| TEST-011 | Spec-AC-05 | integration | tests/skills/test-aai-friction.sh           | Friction, hygiene-pack, and feedback-status suites green; no existing pin regressed | green |

Notes:
- Every Spec-AC has at least one TEST-xxx entry.
- RED status correction (validation R1, 2026-07-26): the recorded RED logs show
  the wiring guards (suite TEST-008/009/010/011/015) failed RED as predicted,
  but suite TEST-012/013/014/016 (spec TEST-005/006/007/009 arms exercising the
  pre-existing v2 CLI / triage engine / exit-code isolation from earlier
  RFC-0012/0013 scopes) legitimately PASSED pre-change — the paragraph below
  over-claimed them as failing. Green-only-pre-change is correct for those
  arms; the RED-proof obligation applies to the NEW wiring guards only.
- RED-proof obligation (all strategies): each AC-gating test above MUST be observed
  FAILING on the current un-wired tree before its green counts. TEST-001..004 and
  TEST-008 fail today (hook enumeration, pointers, and triage step do not exist);
  TEST-009 fails today (swallow not asserted at the hook); TEST-005/006/007 fail
  today against the un-updated seam recipe. Record the RED run for each.
- Suite-local case IDs are appended after the existing TEST-007 in
  test-aai-friction-wiring.sh; do NOT renumber the existing TEST-001..007 cases.

## Verification
- `bash tests/skills/test-aai-friction-wiring.sh` — exit 0 (hooks, pointers,
  v2-record, exclusion, wrap-up triage, negative control).
- `bash tests/skills/test-aai-friction.sh` — exit 0 (no capture-CLI regression).
- `bash tests/skills/test-aai-prompt-diet.sh` — exit 0 (ledger trued up, checkpoint bumped).
- `bash tests/skills/test-aai-hygiene-pack.sh` — exit 0 (wrap-up pins unregressed).
- `bash tests/skills/test-aai-feedback-status.sh` — exit 0 (empty-spool silence unregressed).
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0088-spec-friction-capture-default-on.md` — structural findings (advisory).
- `node .aai/scripts/docs-audit.mjs --check` — exit 0.
- PR CI full framework run — binding.
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.

## Evidence contract
For each implementation, validation, and code review artifact, record:
- ref_id: friction-capture-default-on
- Spec-AC and TEST-xxx links
- command or review scope
- exit code or review verdict
- evidence path (test log under tests/skills/results/ or the RED/GREEN logs)
- commit SHA when available

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
