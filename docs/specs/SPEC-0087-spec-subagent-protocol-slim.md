---
id: spec-subagent-protocol-slim
type: spec
number: 87
status: done
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0061-subagent-protocol-slim.md
  rfc: null
  pr:
    - 161
  commits:
    - 52cdc55dd25a0515c81486ae75d554873f71988d
---

# Implementation Spec — Slim the per-dispatch subagent contract (brief-first, result-block-only handoff)

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0061-subagent-protocol-slim.md
- Decision records: SPEC-0004 (single-writer rule), SPEC-0018 (MODEL row),
  SPEC-0021 (review anti-gaming), SPEC-0026 (work-item brief / Return Record
  single-source), SPEC-0043 + SPEC-0085 (harness-reported usage capture) —
  all pin protocol prose by grep; every pin is enumerated in the Test Plan.
- Technology contract: docs/TECHNOLOGY.md
- Auditor roadmap item 3 (2026-07-26); aligned with phase-boundary-compaction.

## Problem

`.aai/SUBAGENT_PROTOCOL.md` (223 lines / ~1850 words) is passed WHOLE to every
spawned subagent (ORCHESTRATION_PARALLEL workstream inputs; SKILL_LOOP /
VALIDATION dispatch context). A dispatched unit needs only ~400 words of duty
(result block, timing, single-writer, allowed-write); it re-pays ~1450 words of
orchestrator-only material (decomposition criteria, MODEL contract table,
validator spawning, review anti-gaming, harness-usage capture, merge protocol,
delivery gate, platform fallback) on EVERY spawn (4–6 spawns per work item).

## Solution (relocation + pointer — no rule text changes)

Split into two files with **each rule living exactly once**:

1. NEW `.aai/SUBAGENT_CONTRACT.md` — the subagent-facing duty sheet (≤ 60
   lines): result block YAML + timing rules, the single-writer CORE (subagent
   MUST NOT write STATE, allowed-write list, subagent-binding rationalization
   rows), and a one-line "you do NOT self-report token usage" honesty note.
2. `.aai/SUBAGENT_PROTOCOL.md` stays the ORCHESTRATOR-side document (everything
   that binds the dispatching side) and carries a head pointer naming
   `.aai/SUBAGENT_CONTRACT.md` as the per-dispatch payload.
3. Dispatch-context references that name the *subagent payload* are retargeted
   to the CONTRACT file (byte-neutral 17-char rename: `SUBAGENT_PROTOCOL` →
   `SUBAGENT_CONTRACT`, same length). References to orchestrator-only material
   (merge protocol, validator spawning, harness-usage capture) stay on
   `SUBAGENT_PROTOCOL.md`.

Out of scope: any semantic change to a rule (pure relocation + pointer);
role-prompt body changes beyond reference retargeting; BRIEF_TEMPLATE
structural changes (only the single-source path citation is updated).

## Section → destination classification (CORE PLANNING DELIVERABLE)

Every section of the current `.aai/SUBAGENT_PROTOCOL.md`, classified by WHO it
binds and its destination. "Grep pins" names the test that locks the prose in
place (retarget obligations are in the Test Plan).

| # | Section (current) | Lines | Binds | Destination | Grep pins → action |
|---|-------------------|-------|-------|-------------|--------------------|
| 1 | Header / intro | 1–4 | both (framing) | PROTOCOL keeps slimmed header **+ head pointer to CONTRACT**; CONTRACT gets its own header | none |
| 2 | When to decompose | 6–17 | ORCHESTRATOR (dispatcher decides to spawn) | PROTOCOL | none |
| 3 | Subagent call contract (ROLE/SCOPE/**MODEL**/INPUT/EXPECTED_OUTPUT/SYSTEM_PROMPT table) | 18–29 | ORCHESTRATOR (fills dispatch fields) | PROTOCOL | test-aai-state.sh:2032 (MODEL row) → **stays PROTOCOL, no retarget** |
| 4 | Work-item brief handoff (default INPUT) | 31–43 | ORCHESTRATOR (chooses INPUT) | PROTOCOL | hygiene-pack TEST-005 (briefs/, DEFAULTS to the brief, fall back to the spec path, never block…, Return Record…verbatim) → **stays PROTOCOL, no retarget**; reword only the "…below, verbatim" phrase to name `.aai/SUBAGENT_CONTRACT.md` (grep tokens unaffected) |
| 5 | Review dispatch anti-gaming rules | 45–70 | both (orchestrator must-not-coach; reviewer reads via SKILL_CODE_REVIEW pointer) | PROTOCOL | hygiene-pack TEST-005 / test_041 (characterize expected findings, pre-rate severity, scope-exclude, read-only on implementation files, ref/path list, never pasted inline) → **stays PROTOCOL, no retarget** |
| 6 | Spawning a validator in a separate agent | 72–103 | ORCHESTRATOR (dispatcher spawns validator) | PROTOCOL | none directly on PROTOCOL prose |
| 7 | **Result block (mandatory subagent output) + Timing capture rules** | 105–130 | **SUBAGENT** | **CONTRACT** (verbatim fenced YAML — must stay byte-identical to BRIEF_TEMPLATE) | hygiene-pack TEST-002 extracts `subagent_result:` fence from PROTOCOL → **RETARGET to CONTRACT** |
| 8 | Harness-reported usage capture | 132–156 | ORCHESTRATOR ("captured ONLY from the harness-level result visible to the dispatching parent…never from a subagent's own self-report") | PROTOCOL | token-capture TEST-001/002 + SPEC-0085 TEST-008/009 → **stays PROTOCOL, no retarget** |
| 9 | **Single-writer rule (HARD)** — subagent MUST NOT write STATE + MAY-write list + subagent rationalization rows | 158–186 | **SUBAGENT** (core) / ORCHESTRATOR (docs-lock serialization + R-GUARD honesty note) | **CONTRACT** (subagent core + subagent rationalization rows); PROTOCOL keeps a one-line orchestrator serialization note (docs-lock lives in ORCHESTRATION_PARALLEL) | docs-lock TEST-010 (MUST NOT write…STATE.yaml; sole writer; STATE.yaml) → **RETARGET to CONTRACT** |
| 10 | Merge protocol (orchestrator responsibility) | 188–211 | ORCHESTRATOR | PROTOCOL | SPEC-0085 TEST-008 (MANDATORY usage_total_tokens in Merge protocol) → **stays PROTOCOL, no retarget** |
| 11 | Delivery gate (mandatory) | 213–221 | ORCHESTRATOR | PROTOCOL | none |
| 12 | Platform fallback | 223–229 | ORCHESTRATOR | PROTOCOL | none |

Result: only **sections 7 and 9** move to the CONTRACT. Everything grep-pinned
by SPEC-0018/0021/0026(brief)/0043/0085 stays on `SUBAGENT_PROTOCOL.md` and
needs NO retarget; only the two SUBAGENT-binding sections (result block +
single-writer core) move, forcing exactly two test retargets (docs-lock TEST-010,
hygiene-pack TEST-002) plus a BRIEF_TEMPLATE single-source path edit.

Classification correction (risk R-1, from intake): intake AC-001 lists a
"usage-note duty" for the contract. Per section 8, harness-usage capture binds
the ORCHESTRATOR ("never from a subagent's own self-report") — a subagent has
NO usage-reporting duty and the result-block YAML carries no token fields. The
CONTRACT therefore carries only a one-line *prohibition* ("do NOT self-report
token usage — the orchestrator captures it from the harness"); the capture
MECHANISM stays once in `SUBAGENT_PROTOCOL.md` (no duplication). Spec-AC-01
below reflects this corrected content list.

## Implementation strategy
- Strategy: loop
- Rationale: pure relocation of existing prose into a new file + byte-neutral
  reference renames + two test retargets. No new behavior, no algorithm, no
  data change. RED-GREEN-REFACTOR per-test adds little signal over a single
  focused pass. RED-proof is still MANDATORY (see Test Plan): every new/
  retargeted grep assertion MUST be observed FAILING against the pre-change
  tree before its GREEN can count — a grep contract that never failed proves
  nothing (self-evaluation trap).

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: documentation/prompt/test relocation, single logical
  scope, fully reversible, no protected surface, no runtime/state/schema code.
  Implementation branches from `main` AFTER PR #159 merges (a normal feature
  branch; not a worktree). `optional` would also be defensible; `not_needed`
  chosen because the change is docs-class and low-risk.
- User decision: undecided
- Base ref: main (post-#159)
- Worktree branch/path: <if selected>
- Inline review scope: .aai/SUBAGENT_CONTRACT.md, .aai/SUBAGENT_PROTOCOL.md,
  .aai/ORCHESTRATION_PARALLEL.prompt.md, .aai/SKILL_LOOP.prompt.md,
  .aai/VALIDATION.prompt.md, .aai/templates/BRIEF_TEMPLATE.md,
  .aai/system/PROFILES.yaml, tests/skills/test-aai-docs-lock.sh,
  tests/skills/test-aai-hygiene-pack.sh, and the AC-001..003 test additions
  (in tests/skills/test-aai-hygiene-pack.sh)

## Acceptance Criteria Mapping

- Maps to: CHANGE AC-001
  - Spec-AC-01: `.aai/SUBAGENT_CONTRACT.md` exists, is ≤ 60 lines, and contains
    (grep-verified tokens): the fenced `subagent_result:` result-block YAML, the
    timing capture rules (`duration_seconds` match tolerance), the single-writer
    core (`MUST NOT` write `STATE.yaml`; orchestrator sole writer), the
    allowed-write list (own scoped files / `docs/ai/tdd/` / `EVENTS.jsonl` via
    `append-event.mjs`), the subagent-binding rationalization rows, and the
    "do NOT self-report token usage" prohibition line.
  - Verification: `test -f`; `wc -l ≤ 60`; grep each token → new hygiene-pack
    test; RED = run against tree with no CONTRACT file (fails).
- Maps to: CHANGE AC-002
  - Spec-AC-02: no rule sentence is duplicated across the two files. A spot-grep
    of 5 canonical phrases finds each in EXACTLY ONE file: (a) `subagent_result:`
    fence → CONTRACT only; (b) `MUST NOT write` … `STATE.yaml` → CONTRACT only;
    (c) `duration_seconds` … match → CONTRACT only; (d) `never from a subagent's
    own self-report` → PROTOCOL only; (e) `MUST NOT characterize expected
    findings` → PROTOCOL only.
  - Verification: for each phrase, count files matching among the two = 1 → new
    hygiene-pack test; RED = pre-change (phrases (a)(b)(c) still in PROTOCOL, 0
    in CONTRACT).
- Maps to: CHANGE AC-003
  - Spec-AC-03: every dispatch reference that names the *subagent payload* names
    `.aai/SUBAGENT_CONTRACT.md`; NO dispatch passes the full
    `SUBAGENT_PROTOCOL.md` as a unit's context. Specifically: ORCHESTRATION_-
    PARALLEL line "a copy of …" + result-block reference + single-writer
    reference → CONTRACT; SKILL_LOOP / VALIDATION validator-payload reference →
    CONTRACT; orchestrator-only refs (merge protocol, validator spawning,
    harness-usage) remain on PROTOCOL. BRIEF_TEMPLATE single-source citation
    names the CONTRACT section.
  - Verification: grep the three prompts + BRIEF_TEMPLATE → new hygiene-pack
    test; RED = pre-change (refs name PROTOCOL as payload).
- Maps to: CHANGE AC-004
  - Spec-AC-04: companion obligations satisfied — (i) `.aai/SUBAGENT_CONTRACT.md`
    classified in `.aai/system/PROFILES.yaml` `core`; (ii) prompt-diet ledger:
    NO true-up needed because the ONLY in-glob (`.aai/*.prompt.md`) edits are
    byte-neutral 17-char renames; the follow-up SKILL_LOOP:18 clause fix
    (code-review disposition) added an itemized +32 B ledger entry, so
    TEST-010 net reduction/headroom are unchanged. Verified, not assumed:
    the corpus measures 345010 at relocation time (+32 B after the clause
    fix) and the TEST-012 pin lands at 27805 (post-#160 base 27773 + 32).
  - Verification: `bash tests/skills/test-aai-layer-profiles.sh` (TEST-001);
    `bash tests/skills/test-aai-prompt-diet.sh` (TEST-010/012); byte-count
    before/after equal.
- Maps to: CHANGE AC-005
  - Spec-AC-05: no regression on the retargeted/adjacent pins — docs-lock,
    hygiene-pack, token-capture, state suites green locally (targeted); the
    binding full-framework run is PR CI (operator direction 2026-07-26: do NOT
    run the full framework locally).
  - Verification: the four targeted suites (below) exit 0 locally; PR CI green.

## Constitution deviations

None.

<!-- docs/CONSTITUTION.md not present in repo (checked); section kept literal
  per template. No canonical requirement is added/modified/removed — this is a
  file relocation of already-canonical protocol prose — so no `## Deltas`
  section. -->

## Acceptance Criteria Status

| Spec-AC    | Description                                                        | Status  | Evidence | Review-By | Notes |
|------------|-------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | CONTRACT file exists, ≤60 lines, required tokens present            | done | `.aai/SUBAGENT_CONTRACT.md` (58 lines); `bash tests/skills/test-aai-hygiene-pack.sh` exit 0 (test_080) | —         | RED: docs/ai/tdd/red-20260726T182723Z-subagent-protocol-slim-new-tests.log |
| Spec-AC-02 | No rule-sentence duplication (5-phrase spot-grep, each in 1 file)   | done | `bash tests/skills/test-aai-hygiene-pack.sh` exit 0 (test_081); retargeted test_060 TEST-002 (`.aai/SUBAGENT_CONTRACT.md` diff) exit 0 | —         | RED: docs/ai/tdd/red-20260726T182723Z-subagent-protocol-slim-{new-tests,hygiene}.log |
| Spec-AC-03 | Dispatch payload refs name CONTRACT; no full-protocol-to-unit       | done | `bash tests/skills/test-aai-hygiene-pack.sh` exit 0 (test_082); `bash tests/skills/test-aai-docs-lock.sh` exit 0 (test_wiring_and_protocol, CONTRACT_DOC retarget) | —         | RED: docs/ai/tdd/red-20260726T182723Z-subagent-protocol-slim-{new-tests,docslock}.log |
| Spec-AC-04 | PROFILES classified + prompt-diet honest (byte-neutral renames)     | done | `bash tests/skills/test-aai-layer-profiles.sh` exit 0 (TEST-001, core=124); `bash tests/skills/test-aai-prompt-diet.sh` exit 0 (TEST-010 headroom within cap); corpus byte count via `wc -c` over the prompt glob equals 345010 at relocation time | —         | renames byte-neutral; the follow-up SKILL_LOOP:18 clause fix carries its own +32 B ledger entry (TEST-012 pin 27805) |
| Spec-AC-05 | No regression — targeted suites green locally; full suite on PR CI  | done | `bash tests/skills/test-aai-token-capture.sh` exit 0; `bash tests/skills/test-aai-state.sh` exit 0 (TEST-008 MODEL row intact) | —         | full framework binding gate = PR CI (operator direction, not run locally) |

## Implementation plan

Components/files affected:
- NEW `.aai/SUBAGENT_CONTRACT.md` (sections 7 + 9 core, verbatim relocation).
- `.aai/SUBAGENT_PROTOCOL.md` — remove sections 7 + 9 core; add head pointer;
  keep one-line orchestrator serialization note; reword the brief-handoff
  "…below, verbatim" phrase to name the CONTRACT (grep tokens preserved).
- `.aai/ORCHESTRATION_PARALLEL.prompt.md` — retarget payload refs (L42
  single-writer, L137 "a copy of…", L139 result block) → CONTRACT; keep L110
  validator spawning + L141 merge protocol → PROTOCOL. All byte-neutral renames.
- `.aai/SKILL_LOOP.prompt.md` — retarget the validator-payload ref (L259 "a
  copy of…") → CONTRACT; keep harness-usage refs (L18/L187/L267/L346) →
  PROTOCOL (token-capture TEST-001 requires a `SUBAGENT_PROTOCOL.md` mention to
  remain). Byte-neutral.
- `.aai/VALIDATION.prompt.md` — retarget the per-subagent payload ref (L206
  "and .aai/SUBAGENT_PROTOCOL.md") → CONTRACT; keep merge-protocol ref (L235) →
  PROTOCOL. Byte-neutral.
- `.aai/templates/BRIEF_TEMPLATE.md` — L35 "Single source: .aai/SUBAGENT_-
  PROTOCOL.md section" → `.aai/SUBAGENT_CONTRACT.md`. Not grep-pinned on the
  path; the section-title string "Result block (mandatory subagent output)"
  (grepped) is unchanged. Outside prompt glob → no ledger impact.
- `.aai/system/PROFILES.yaml` — add `  - .aai/SUBAGENT_CONTRACT.md` to `core`.
- Test retargets + new AC tests (see Test Plan).

Data flows: none (prose relocation). Edge cases: (a) hygiene TEST-002 awk takes
the FIRST ```yaml fence — the CONTRACT's result block must be its first/only
fence (it is); (b) byte-identical Return Record ↔ CONTRACT fence must be
preserved exactly on the move (copy the current lines 109-125 verbatim).

## Seam analysis

- SEAM-1 BRIEF_TEMPLATE Return Record ↔ CONTRACT result block (byte-identical).
  Integration test: hygiene-pack TEST-002 `diff` (retargeted to CONTRACT) —
  produces on the template side, asserts byte-equality against the CONTRACT.
- SEAM-2 dispatch prompts ↔ the file named as the unit payload. Integration
  test: Spec-AC-03 grep across the three prompts + BRIEF_TEMPLATE (payload refs
  resolve to CONTRACT; orchestrator refs to PROTOCOL).
- SEAM-3 harness-usage pins (PROTOCOL) ↔ SKILL_LOOP. Unchanged both sides;
  regression covered by the token-capture suite (both files retained).
- SEAM-4 PROFILES.yaml union ↔ live `.aai/` tree (new file must be classified).
  Integration test: layer-profiles TEST-001 against the LIVE tree.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                    | Description | Status |
|----------|------------|-------------|-----------------------------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-hygiene-pack.sh (new fn) | CONTRACT exists, ≤60 lines, greps: `subagent_result:` fence, `duration_seconds` match, `MUST NOT`+`STATE.yaml`, allowed-write (`docs/ai/tdd/`, `append-event.mjs`), subagent rationalization row, no-self-report-usage line | green |
| TEST-002 | Spec-AC-02 | unit        | tests/skills/test-aai-hygiene-pack.sh (new fn) | 5-phrase spot-grep, each phrase found in EXACTLY ONE of {CONTRACT, PROTOCOL} | green |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-hygiene-pack.sh (new fn) | ORCHESTRATION_PARALLEL/SKILL_LOOP/VALIDATION payload refs name CONTRACT; BRIEF_TEMPLATE single-source cites CONTRACT; PROTOCOL retains merge/validator/harness refs | green |
| TEST-004 | Spec-AC-02 | unit        | tests/skills/test-aai-hygiene-pack.sh (test_060, RETARGET) | Return-Record byte-diff source repointed from PROTOCOL (`$sp`) to a new CONTRACT var; `subagent_result:` extracted from CONTRACT; TEST-005 brief-handoff greps stay on PROTOCOL | green |
| TEST-005 | Spec-AC-02 | unit        | tests/skills/test-aai-docs-lock.sh (test_wiring_and_protocol, RETARGET) | single-writer greps (L415 `MUST NOT write…STATE.yaml`, L417 sole writer, L420 `STATE.yaml`) repointed from `$PROTOCOL_DOC` to new `$CONTRACT_DOC`; ORCHESTRATION_PARALLEL docs-lock + LOCKS.md greps unchanged | green |
| TEST-006 | Spec-AC-04 | integration | tests/skills/test-aai-layer-profiles.sh (TEST-001, existing) | union of PROFILES core+extended equals live `.aai` tree — passes only once `.aai/SUBAGENT_CONTRACT.md` is classified | green |
| TEST-007 | Spec-AC-04 | unit        | tests/skills/test-aai-prompt-diet.sh (TEST-010/012, existing) | relocation edits byte-neutral; the SKILL_LOOP:18 clause fix carries an itemized +32 B entry — `JUSTIFIED_GROWTH_BYTES` re-sums to the TEST-012 pin (27805 post-#160) | green |
| TEST-008 | Spec-AC-05 | integration | tests/skills/test-aai-token-capture.sh (existing) | harness-usage + merge + ROLE_COMMON pins still green; SKILL_LOOP still mentions `SUBAGENT_PROTOCOL.md` (no regression from retargets) | green |
| TEST-009 | Spec-AC-05 | unit        | tests/skills/test-aai-state.sh (TEST-008, existing) | MODEL row still present in `SUBAGENT_PROTOCOL.md` contract table (call-contract table not moved) | green |

RED-proof obligation (all strategies): TEST-001/002/003 must be observed
FAILING against the pre-change tree (no CONTRACT file, refs still name
PROTOCOL); TEST-004/005 must be observed failing after retarget but before the
prose moves (extraction/greps miss on the not-yet-populated CONTRACT). Capture
each RED under `docs/ai/tdd/`.

Grep-pinned test contract inventory (BEFORE freeze — every suite that greps
protocol prose, with its retarget verdict):
- test-aai-docs-lock.sh:415-421 (SPEC-0004 TEST-010) → single-writer → RETARGET → CONTRACT (TEST-005).
- test-aai-hygiene-pack.sh:669-672 (SPEC-0026 TEST-002) → result-block extraction → RETARGET → CONTRACT (TEST-004).
- test-aai-hygiene-pack.sh:501-516 (SPEC-0021 TEST-005) → anti-gaming → NO retarget (stays PROTOCOL).
- test-aai-hygiene-pack.sh:702-709 (SPEC-0026 TEST-005) → brief handoff/MODEL/anti-gaming → NO retarget (stays PROTOCOL).
- test-aai-state.sh:2032 (SPEC-0018 TEST-008) → MODEL row → NO retarget (stays PROTOCOL).
- test-aai-token-capture.sh:120-149,163-182,417-439 (SPEC-0043/0085) → harness usage/merge/ROLE_COMMON → NO retarget (stays PROTOCOL).
- test-aai-layer-profiles.sh:TEST-001 → PROFILES union → new file must be classified.

## Verification
- bash tests/skills/test-aai-hygiene-pack.sh
- bash tests/skills/test-aai-docs-lock.sh
- bash tests/skills/test-aai-layer-profiles.sh
- bash tests/skills/test-aai-prompt-diet.sh
- (regression, targeted) bash tests/skills/test-aai-token-capture.sh
- (regression, targeted) bash tests/skills/test-aai-state.sh
- grep contracts per Spec-AC-01..03; corpus byte count == 345010 at relocation time (+32 B after the SKILL_LOOP:18 clause fix).
- Full framework run: PR CI only (operator direction — not run locally).
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.
- Post-freeze advisory: `node .aai/scripts/spec-lint.mjs --path
  docs/specs/SPEC-0087-spec-subagent-protocol-slim.md` (report-only).

## Evidence contract
For each Implementation / Validation / Code Review artifact, record: ref_id;
Spec-AC + TEST-xxx links; command or review scope; exit code or verdict;
evidence path; commit SHA or diff range when available. RED logs for
TEST-001..005 under `docs/ai/tdd/`.

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow.
