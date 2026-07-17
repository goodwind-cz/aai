---
id: spec-prompt-layer-diet-phase-1
type: spec
number: 17
status: done
links:
  change: CHANGE-0011
  research: RES-0001
  rfc: null
  pr:
    - 53
  commits:
    - 06cffb5
---

# SPEC — Prompt-layer diet, phase 1 (intake include, delete fiction, footer dedup, caching order + digest)

SPEC-FROZEN: true

## Links
- Change: CHANGE-0011 (docs/issues/CHANGE-0011-prompt-layer-diet-phase-1.md)
- Research: RES-0001 finding F3 / recommendation P1.3
- Technology contract: docs/TECHNOLOGY.md

## Problem (evidence-verified 2026-07-15)

Measured against the working tree at planning time:

1. **Intake duplication.** The 8 `INTAKE_*.prompt.md` files total 480 lines /
   21,469 bytes. Four blocks repeat near-verbatim in all 8 (line refs from
   `INTAKE_CHANGE.prompt.md`):
   - **Language policy** — 3 rule lines ("Accept user responses in any
     language / Keep follow-up questions in the user's language / Output the
     final saved markdown in English only"), lines 12–14. md5-identical ×8.
   - **DURABLE DOC IDENTITY (SPEC-0015 / RFC-0007)** — 11 lines, 27–37.
     md5-identical ×8.
   - **POST-SAVE CHECK (RFC-0002)** — 6 lines, 39–44. md5-identical ×8.
   - **METRICS (after saving the document)** — 10 lines, 46–55. md5-identical
     in 7 of 8; `INTAKE_CHANGE.prompt.md:55` carries typo drift ("If the user
     skips or **no** ref_id is not yet known") — the predicted hand-sync drift
     (RES-0001 F3) already observed.
   `SKILL_INTAKE.prompt.md` (106 lines) duplicates the identity and post-save
   policies again in router wording (STEP 2.4 / 2.5), with one router-only
   superset detail: the SPEC-0013 H1 body-lint explanation in STEP 2.5.
2. **SKILL_PROFILE fiction.** 737 lines / 22,470 bytes. Lines 45–293 are mock
   CLI transcripts with invented numbers; lines 340–471 present
   `.aai/lib/profiler.mjs` (a `Profiler` class) as instrumentation — neither
   `.aai/lib/` nor any profiler script exists; lines 473–634 are JS for
   `detectBottlenecks`/`generateOptimizations` that exist nowhere; the
   `docs/ai/profiles/` output tree (299, 636–658) does not exist. Real,
   existing data sources it ignores: `docs/ai/METRICS.jsonl`,
   `docs/ai/LOOP_TICKS.jsonl`, `docs/ai/PRICING.yaml`,
   `.aai/scripts/generate-dashboard.mjs`, `.aai/scripts/loop-digest.mjs`.
3. **Footer duplication.** The `STATE-WRITE SAFETY (ISSUE-0004 / INV-14)`
   footer (~11 lines) repeats in 5 role prompts (PLANNING:163,
   IMPLEMENTATION:194, VALIDATION:245, REMEDIATION:96, SKILL_TDD:563). The
   multi-line "FALLBACK — if .aai/scripts/state.mjs is absent" hand-edit
   procedure repeats ~21 times across 10 prompts (PLANNING ×2,
   IMPLEMENTATION ×2, VALIDATION ×2, REMEDIATION ×3, SKILL_TDD ×5,
   ORCHESTRATION ×2, ORCHESTRATION_PARALLEL ×1, METRICS_FLUSH ×2,
   SKILL_LOOP ×2 incl. the STATE-WRITE NOTE block at 377–382).
4. **SKILL_LOOP caching + payload.** CACHING DISCIPLINE (lines 365–375) says
   "canonical prompts (.aai/*.prompt.md) **and STATE.yaml** lead the context"
   — STATE.yaml mutates every tick, so placing it in the stable prefix
   guarantees a prompt-cache break at the earliest byte. Step 3 (line 213)
   injects "current docs/ai/STATE.yaml contents" into the orchestrator
   payload even though `ORCHESTRATION.prompt.md` step 1 already mandates the
   orchestrator read `docs/ai/STATE.yaml` from disk itself.
   `.aai/scripts/loop-digest.mjs --json` exists and emits a ~1KB run summary.

## Design decisions

### D1 — Include mechanism: plain `Read <path>` line, no templating
Create `.aai/INTAKE_COMMON.md` holding the four blocks under stable headings:
`## LANGUAGE POLICY`, `## DURABLE DOC IDENTITY (SPEC-0015 / RFC-0007)`,
`## POST-SAVE CHECK (RFC-0002)`, `## METRICS (after saving the document)`.
Block text moves **verbatim** from the current majority copy (the 7-way
identical text; the INTAKE_CHANGE metrics typo is dropped in favor of the
majority wording — behavior identical). Each `INTAKE_*.prompt.md` replaces the
four blocks with exactly one line:

    SHARED POLICY — Read .aai/INTAKE_COMMON.md and apply its four blocks (language policy, durable doc identity, post-save check, metrics question) exactly.

No templating engine, no preprocessor: Claude, Codex, and Gemini agents all
honor a plain "read this file" instruction, and `aai-sync.sh` copies all of
`.aai/*` by glob (verified: copy loop at aai-sync.sh:198–203), so the new file
vendors automatically.

### D2 — SKILL_INTAKE keeps router-only content, points at the include
`SKILL_INTAKE.prompt.md` STEP 2.4 and STEP 2.5 bodies are replaced with 1-line
pointers to the corresponding `INTAKE_COMMON.md` sections. Router-only content
is retained inline: the type map/routing algorithm, STEP 2.6 (index regen —
router-specific), and the SPEC-0013 H1 body-lint note (kept as one retained
paragraph under the STEP 2.5 pointer, since it is not part of the ×8 block).
The LANGUAGE POLICY / EFFICIENCY RULES sections collapse to the shared
pointer.

### D3 — SKILL_PROFILE verdict: DELETE fiction, do not implement
Rewrite `SKILL_PROFILE.prompt.md` to ≤ ~120 lines describing only what exists:
analyze `docs/ai/METRICS.jsonl` + `docs/ai/LOOP_TICKS.jsonl` (+
`docs/ai/PRICING.yaml` when priced), optionally via
`.aai/scripts/loop-digest.mjs` and `.aai/scripts/generate-dashboard.mjs`, and
produce a markdown report under `docs/ai/reports/`. Delete all mock
transcripts, the fictional `Profiler` class, `detectBottlenecks` /
`generateOptimizations` JS, and the `docs/ai/profiles/` format. Implementing a
real profiler is out of scope (that is RES-0001 F2/P1.4 territory). The
`.claude/skills/aai-profile` wrapper needs no change (it only points at the
prompt path).

### D4 — Footer dedup: one shared reference doc, 1-line pointers
Create `.aai/STATE_FALLBACK.md` containing, once: the hand-edit fallback
procedure for a missing `state.mjs` (legacy field lists for focus/phase/
strategy/worktree/code-review/human-input writes, the hand-written
`agent_runs` / tick-line field lists), the STATE-WRITE SAFETY (ISSUE-0004 /
INV-14) duplicate-`metrics:` rules, and the validate/repair commands
(`node .aai/scripts/check-state.mjs [--repair] docs/ai/STATE.yaml`).
In the 10 prompts listed in Problem §3, each multi-line FALLBACK block and
each STATE-WRITE SAFETY / STATE-WRITE NOTE footer is replaced by at most:

    FALLBACK — if .aai/scripts/state.mjs is absent: read .aai/STATE_FALLBACK.md and follow it.

(≤2 lines per occurrence). Primary-path `state.mjs` command lines stay inline
in each prompt — they are role-specific and load-bearing. Progressive
disclosure: the fallback text is loaded only when `state.mjs` is actually
absent, which is never true in this repo.

### D5 — SKILL_LOOP: canon-first/STATE-last + digest payload with degradation
CACHING DISCIPLINE is rewritten so the stable prefix contains ONLY frozen
canon (`.aai/*.prompt.md`); volatile content — STATE.yaml, digest, per-tick
dispatch context — is placed LAST. Step 3's orchestrator payload changes from
"current docs/ai/STATE.yaml contents" to: current tick number + selector
decision + the output of `node .aai/scripts/loop-digest.mjs --json` (~1KB).
This is safe because the orchestrator prompt independently reads
`docs/ai/STATE.yaml` from disk (authoritative source, its step 1).
Documented digest JSON fields (must match loop-digest.mjs reality): `ticks`,
`durationSeconds`, `harnessVersion`, `startedUtc`, `endedUtc`, `scopes[]`,
`finalValidation`, `recoveries`, `recoveryOutcomes[]`, `stopReason`,
`cost{input,output,cacheRead,usd,any}`,
`git{branch,uncommitted,recentCommits[]}`.
DEGRADATION: if `loop-digest.mjs` is absent or `node` fails, fall back to
injecting full STATE.yaml contents (today's behavior) and note the degradation
in the tick line. Step 4 (role dispatch context) is deliberately unchanged.

### D6 — Behavior invariance rule
No intake question order, artifact template, command, or gate changes. The
only permitted text deltas are: block relocation, the 1-line pointers, the
INTAKE_CHANGE typo normalization to majority wording, and the SKILL_LOOP
corrections in D5.

## Implementation strategy
- Strategy: loop
- Rationale: mechanical text refactor (move-verbatim + pointer lines + one
  prompt rewrite) with grep-RED evidence — every wiring test fails naturally
  today (INTAKE_COMMON.md/STATE_FALLBACK.md do not exist; duplicated headers
  present ×8; inverted caching sentence present). No state-layer or script
  code is touched, so RED-GREEN-REFACTOR per test adds no signal beyond the
  grep suite's observed RED run.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: parallel stream with CHANGE-0010 is active; this change
  edits 12+ prompt files including the role prompts the resident loop itself
  executes, plus shared intake surfaces — isolation avoids INDEX/prompt
  cross-talk between the two streams and keeps the live prompt layer stable
  until merge.
- User decision: undecided
- Base ref: main
- Worktree branch/path: <if selected>
- Inline review scope: .aai/INTAKE_COMMON.md, .aai/STATE_FALLBACK.md,
  .aai/INTAKE_CHANGE.prompt.md, .aai/INTAKE_HOTFIX.prompt.md,
  .aai/INTAKE_ISSUE.prompt.md, .aai/INTAKE_PRD.prompt.md,
  .aai/INTAKE_RELEASE.prompt.md, .aai/INTAKE_RESEARCH.prompt.md,
  .aai/INTAKE_RFC.prompt.md, .aai/INTAKE_TECHDEBT.prompt.md,
  .aai/SKILL_INTAKE.prompt.md, .aai/SKILL_PROFILE.prompt.md,
  .aai/SKILL_LOOP.prompt.md, .aai/PLANNING.prompt.md,
  .aai/IMPLEMENTATION.prompt.md, .aai/VALIDATION.prompt.md,
  .aai/REMEDIATION.prompt.md, .aai/SKILL_TDD.prompt.md,
  .aai/ORCHESTRATION.prompt.md, .aai/ORCHESTRATION_PARALLEL.prompt.md,
  .aai/METRICS_FLUSH.prompt.md, tests/skills/test-aai-prompt-diet.sh,
  docs/specs/SPEC-0017-spec-prompt-layer-diet-phase-1.md
- code_review.required: true (canonical workflow prompt layer — every role
  executes these files)

## Acceptance Criteria Mapping

- Maps to: CHANGE-0011 AC-001
  - Spec-AC-01: `.aai/INTAKE_COMMON.md` exists and contains each of the four
    blocks exactly once; all 8 `INTAKE_*.prompt.md` contain the 1-line
    reference and none contains the block bodies; combined line count of the
    8 files ≤ 240 (baseline 480).
  - Verification: TEST-001..003 greps + wc; TEST-004 behavioral dry-run.
- Maps to: CHANGE-0011 AC-002
  - Spec-AC-02: `SKILL_PROFILE.prompt.md` contains zero references to
    non-existent scripts/paths (`profiler.mjs`, `.aai/lib/`,
    `docs/ai/profiles/`, `class Profiler`, ```` ```javascript ```` fences)
    and is ≤ 8,988 bytes (≤40% of the 22,470-byte baseline).
  - Verification: TEST-005 grep + size assertion.
- Maps to: CHANGE-0011 AC-003
  - Spec-AC-03: the hand-edit fallback procedure and STATE-WRITE SAFETY rules
    exist only in `.aai/STATE_FALLBACK.md`; each of the 10 role/orchestration
    prompts references it in ≤2 lines per occurrence, with the unique
    fallback body markers (`Legacy field list`, `never emit a second
    top-level`, `STATE-WRITE SAFETY`) absent from all prompts.
  - Verification: TEST-006, TEST-007 greps.
- Maps to: CHANGE-0011 AC-004
  - Spec-AC-04: SKILL_LOOP's CACHING DISCIPLINE lists only frozen canon in
    the stable prefix and STATE/dispatch last; step 3 payload names
    `loop-digest.mjs --json` with the documented field set and the
    degradation clause; `node .aai/scripts/loop-digest.mjs --json` runs and
    emits exactly the documented keys.
  - Verification: TEST-008 grep + TEST-009 execution.
- Maps to: CHANGE-0011 AC-005
  - Spec-AC-05: repo-wide `docs-audit --check --strict` CLEAN; existing skill
    suites green; before/after `wc -c` across `.aai/*.prompt.md` recorded as
    evidence (expected total reduction ≥ 28KB).
  - Verification: TEST-010.

## Acceptance Criteria Status

| Spec-AC    | Description                                             | Status | Evidence | Review-By | Notes |
|------------|---------------------------------------------------------|--------|----------|-----------|-------|
| Spec-AC-01 | Shared intake include wired ×8, intake lines ≤50%       | done   | docs/ai/tdd/green-prompt-diet-20260715T192011Z.log (TEST-001..004; 232/480 lines) | — | RED: docs/ai/tdd/red-prompt-diet-20260715T191406Z.log |
| Spec-AC-02 | SKILL_PROFILE fiction deleted, ≤40% of baseline size    | done   | docs/ai/tdd/green-prompt-diet-20260715T192011Z.log (TEST-005; 4,714 of 22,470 bytes = 21%) | — | — |
| Spec-AC-03 | Fallback/safety text single-sourced, ≤2-line pointers   | done   | docs/ai/tdd/green-prompt-diet-20260715T192011Z.log (TEST-006..007) | — | — |
| Spec-AC-04 | Canon-first caching + digest payload wired and runnable | done   | docs/ai/tdd/green-prompt-diet-20260715T192011Z.log (TEST-008..009) | — | — |
| Spec-AC-05 | Audit CLEAN, suites green, KB delta measured            | done   | docs/ai/reports/prompt-diet-evidence-20260715.md (TEST-010; net −35,146 B ≥ 28,672 B floor) | — | before/after: docs/ai/tdd/prompt-diet-kb-{before,after}.txt |

## Implementation plan
- New files: `.aai/INTAKE_COMMON.md` (four verbatim blocks),
  `.aai/STATE_FALLBACK.md` (fallback + safety, once),
  `tests/skills/test-aai-prompt-diet.sh` (grep-wiring suite using
  tests/skills/test-framework.sh conventions).
- Edited: 8 `INTAKE_*` prompts (blocks → 1 pointer line), `SKILL_INTAKE`
  (D2), `SKILL_PROFILE` (D3 rewrite), `SKILL_LOOP` (D5), and the 10 prompts
  of Problem §3 (D4 pointers).
- Capture baseline first: `wc -c .aai/*.prompt.md > <evidence>` before any
  edit; re-run after; both land in the evidence artifact and the PR body.
- Edge cases: INTAKE_RELEASE has the blocks at different offsets (identity at
  line 38) — replacement is anchored on headings, not line numbers;
  INTAKE_CHANGE metrics typo normalizes to majority text (D6);
  allocator-absent FALLBACK inside the identity block moves verbatim (it is
  part of the block, not a state.mjs fallback).

## Seam analysis (cross-feature integration)
- Seam 1 — intake flow ↔ docs-audit strict gate: an intake artifact produced
  under the new include must still pass
  `docs-audit.mjs --check --strict --no-event --path`. Covered end-to-end by
  TEST-004 (real dry-run, real audit — not a grep).
- Seam 2 — SKILL_LOOP ↔ loop-digest.mjs: the documented payload must match
  what the script actually emits. Covered by TEST-009 (real execution, key
  comparison).
- Seam 3 — vendoring (aai-sync/aai-update) ↔ new `.aai/*.md` files: verified
  at planning time — aai-sync.sh copies `.aai/*` entry-by-entry by glob
  (lines 198–203), so INTAKE_COMMON.md and STATE_FALLBACK.md vendor with no
  manifest change. Residual risk: none; TEST-001/006 existence checks would
  also fail in a target repo if sync regressed.
- Seam 4 — `.claude/skills/aai-profile` wrapper ↔ SKILL_PROFILE: wrapper
  references only the path, which does not change. No test needed beyond
  existing validate-skills suite (TEST-010).

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                    | Description                                                                                                    | Status  |
|----------|------------|-------------|-----------------------------------------|----------------------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-prompt-diet.sh    | Each of the 8 INTAKE_* files contains the `.aai/INTAKE_COMMON.md` reference line exactly once (grep -c = 1 ×8) | green   |
| TEST-002 | Spec-AC-01 | unit        | tests/skills/test-aai-prompt-diet.sh    | INTAKE_COMMON.md exists; each of the 4 block headings appears exactly once in it and zero times in INTAKE_*     | green   |
| TEST-003 | Spec-AC-01 | unit        | tests/skills/test-aai-prompt-diet.sh    | Combined `wc -l` of the 8 INTAKE_* files ≤ 240 (50% of the 480-line baseline)                                   | green   |
| TEST-004 | Spec-AC-01 | e2e         | docs/ai/reports/ (evidence artifact)    | Behavioral dry-run: one intake (change type) produces a DRAFT artifact that passes docs-audit --check --strict --no-event --path | green   |
| TEST-005 | Spec-AC-02 | unit        | tests/skills/test-aai-prompt-diet.sh    | SKILL_PROFILE: zero matches for profiler.mjs / .aai/lib/ / docs/ai/profiles/ / class Profiler / ```javascript; `wc -c` ≤ 8988 | green   |
| TEST-006 | Spec-AC-03 | unit        | tests/skills/test-aai-prompt-diet.sh    | STATE_FALLBACK.md exists with the body markers; `Legacy field list`, `never emit a second top-level`, `STATE-WRITE SAFETY` match 0 files under .aai/*.prompt.md | green   |
| TEST-007 | Spec-AC-03 | unit        | tests/skills/test-aai-prompt-diet.sh    | Every `state.mjs is absent` occurrence in the 10 prompts is the ≤2-line pointer form naming .aai/STATE_FALLBACK.md | green   |
| TEST-008 | Spec-AC-04 | unit        | tests/skills/test-aai-prompt-diet.sh    | SKILL_LOOP: stable-prefix sentence excludes STATE.yaml; volatile-last sentence includes it; step 3 names `loop-digest.mjs --json` + degradation clause | green   |
| TEST-009 | Spec-AC-04 | integration | tests/skills/test-aai-prompt-diet.sh    | `node .aai/scripts/loop-digest.mjs --json` exits 0 and emits exactly the documented top-level keys              | green   |
| TEST-010 | Spec-AC-05 | integration | docs/ai/reports/ (evidence artifact)    | Repo-wide `docs-audit.mjs --check --strict` exit 0; existing tests/skills suites green; before/after `wc -c` totals recorded, reduction ≥ 28KB | green   |

RED-proof: TEST-001/002/003/005/006/007/008 all FAIL against the current tree
(files absent, headers duplicated ×8, footers present, caching sentence
inverted) — the implementation run must record that observed RED before
edits. TEST-004/009/010 are parity/reality checks executed on the changed
tree with evidence captured.

## Verification
- `bash tests/skills/test-aai-prompt-diet.sh` (RED before edits, GREEN after)
- `node .aai/scripts/loop-digest.mjs --json` (TEST-009)
- Intake dry-run + `node .aai/scripts/docs-audit.mjs --check --strict
  --no-event --path <draft>` (TEST-004)
- `node .aai/scripts/docs-audit.mjs --check --strict` repo-wide +
  `wc -c .aai/*.prompt.md` before/after (TEST-010)
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.

## Estimated corpus reduction (planning-time projection, verified at TEST-010)
- Intake dedup: ~13.6KB removed (4 blocks ×8) − ~1.8KB INTAKE_COMMON.md −
  ~0.8KB pointers ≈ **~11KB net**
- SKILL_PROFILE: 22.5KB → ≤ ~5KB ≈ **~17KB net**
- Footer dedup: ~21 blocks (~6.5KB) − ~1.2KB STATE_FALLBACK.md − pointers ≈
  **~4–5KB net**
- SKILL_LOOP: ≈ neutral in bytes; the payload switch saves the per-tick
  STATE.yaml re-injection (4.4KB today, 27.6KB at RES-0001 measurement) in
  the resident loop context every tick.
- Total static: **~30–33KB** (≈ 25% of RES-0001's realistic 120–150KB F3
  target — the phase-1 slice). AC floor set at ≥ 28KB.

## Evidence contract
For each implementation, validation, and code review artifact, record:
- ref_id (CHANGE-0011 / spec-prompt-layer-diet-phase-1)
- Spec-AC and TEST-xxx links
- command or review scope, exit code or verdict, evidence path
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow.

## Review warning dispositions (2026-07-15)

- N1 (STATE_FALLBACK header overclaimed "read ONLY when state.mjs absent" while
  two prompts reference it on the primary path): REMEDIATED — header now names
  both roles of the file.
- N2 (SKILL_LOOP cited a nonexistent "orchestrator step 1"): REMEDIATED — now
  cites the STATE DISCOVERY (MANDATORY) section.
- N3 (SKILL_TDD pointers name a "TDD-cycle hand-edit rule" without a dedicated
  anchor in STATE_FALLBACK.md): PROMOTED — cosmetic; add an anchor next time
  STATE_FALLBACK.md is edited.
- N4 (STATE_FALLBACK tick-line hand-append omits role/scope that primary-path
  log-tick requires): PROMOTED — text moved verbatim per D6 behavior-invariance;
  pre-existing defect, follow-up candidate (CHANGE-0009 territory).
