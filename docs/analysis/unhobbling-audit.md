---
id: unhobbling-audit
type: research
number: null
status: draft
links:
  pr: []
  commits: []
---

# Analysis — Phase 0 doctor-style unhobbling audit of the AAI role-prompt corpus

Read-only pass over the 10 largest `.aai/*.prompt.md` role prompts against the
July 2026 Anthropic unhobbling rubric (rules→judgment, in-prompt
examples→better tool design, upfront→progressive disclosure, repeated
rules→tool descriptions, manual memory→auto-memory, prose specs→code/test
references). Executes Phase 0 of
`docs/issues/CHANGE-DRAFT-altitude-prompt-experiment.md`. **Changes nothing.**

## Method and conventions

- **Corpus** = the 10 prompts named in the change draft, measured with `wc -c`
  on the branch `feat/altitude-prompt-experiment` @ `070b5d4`.
- **`bytes-estimate` = bytes RECOVERED if the disposition is applied**, not the
  size of the quoted block. For `keep-shortened` rows that is the trim delta,
  not the whole section. This keeps the executive total honest.
- **`pin-coupling`** was computed mechanically, not by eye: a script walked every
  `tests/**/*.sh` and `tests/**/*.mjs`, resolved each shell variable that holds a
  prompt path, and matched every quoted grep pattern on a `grep`/`assert_file`
  line back to the exact line of the prompt it hits (regex patterns re-matched
  against the prompt text). 250 real pins were resolved across the 10 prompts.
  Suites that merely list a prompt path in `tests/skills/suite-map.yaml` (a
  change-trigger map, not an assertion) are NOT counted as pins.
- **Classes** are the change draft's rubric; a row gets the class that best
  explains why the bytes exist, and the class name is justified in-row.

### The governance pin that gates EVERY deletion (read before any diet ride)

`tests/skills/test-aai-prompt-diet.sh` TEST-010 enforces
`0 <= headroom <= HEADROOM_CAP(2048)` where
`headroom = BASELINE(357457) - corpus - extra + credit - REQUIRED(28672)`.
Measured now: `corpus=313505`, `extra=15055`, `credit=1305`,
`reduction=30202`, **`headroom=1530/2048`**.

Consequence: **only 518 B of net corpus shrink can land without touching the
ledger.** Any ride removing more must (a) append a NEGATIVE
`JUSTIFIED_ADDITIONS` entry retiring the freed credit and (b) bump TEST-012's
hard-coded literal `1305` by the same amount (TEST-013 explicitly permits a
leading `-`; precedents: `-3247 core-prompt-diet`, `-9573 decapod-prune`,
`-21517 dashboard-refit`). A 13.5 KB first ride would move the TEST-012 pin
from `1305` to roughly `-12253`. This is the pin migration for every
`delete`/`move-to-*` row below; no row is "free" of it, and no row below
proposes deleting a *pinned sentence* without naming the surviving pin site.

### Evidence base, cutting both ways

Supporting deletion-to-gates:

- `docs/ai/friction/` contains only `.gitkeep` — the default-on FRICTION HOOK
  prose credited at +1881 B (`friction-capture-default-on`) and +453 B
  (`friction-capture-default-on-r2`) across VALIDATION ×2, IMPLEMENTATION,
  REMEDIATION and SKILL_PR has produced **zero captures**. 2.3 KB of prose that
  demonstrably never fires.
- `docs/knowledge/LEARNED.md` 2026-07-17/19: "Mechanize any recurring
  agent-hand-performed governance ceremony that has correctness rules" — the
  close ceremony tripped false-open/false-done 3× as prose and became
  correct-by-construction only as `close-work-item.mjs`.
- `docs/knowledge/LEARNED.md` 2026-07-19: prompt-corpus prose rules re-breach
  silently; "the anti-bloat guard only flags it when the suite runs".

Against blanket deletion (guardrails that still earn their bytes):

- `LEARNED.md` 2026-08-02 (phantom `process.getpgrp()`): a plausible-but-
  nonexistent API "survived author + internal L3-style review"; a *bot* caught
  it. Current-gen models still ship this class.
- `LEARNED.md` 2026-07-01 (ISSUE-0002): ~40 orphaned `vitest` trees / 5.6 GB —
  the LEAK-SAFE wrapper-routing rule is prose-only but backed by a real,
  recent, expensive failure.
- `LEARNED.md` 2026-07-16/17: on delta-stage-3 the dual-verdict review PASSED
  by tracing code while an *independent validator on a different model* FAILED
  it by running fixtures. The independence and adversarial-stance rules have a
  positive record in this repo.
- `LEARNED.md` 2026-07-27 (bash 3.2 `set -u`) and 2026-07-19 (BSD/GNU CI
  divergence): the model-authored code in this repo still produces the exact
  failure classes some prompt rules guard.

Net reading: the **derivable-from-code / repeated-rule / example-to-tool**
classes are safe to cut on this repo's own evidence. The
**verification-instruction** class is safe only where a script already
computes the check. The **obsolete-guardrail** class splits: rationalization
tables and capability negotiation are dead weight; leak-safety, phantom-API
and independence rules are not.

---

## Executive summary

| metric | value |
|---|---|
| corpus (10 prompts) | 149,986 B |
| total deletion/relocation candidate | **36,065 B** |
| candidate share | **24.0 %** |
| safe immediate wins (zero pins, safe classes) | 13,558 B (≈12.6 KB ledger-visible after the two ROLE_COMMON relocations) |
| rows marked `needs-gate-first` | 11 |

### Per-class totals

| class | bytes | share of candidate |
|---|---:|---:|
| derivable-from-code | 11,670 | 32.4 % |
| obsolete-guardrail | 9,480 | 26.3 % |
| repeated-rule | 9,460 | 26.2 % |
| example-to-tool | 3,811 | 10.6 % |
| verification-instruction | 1,294 | 3.6 % |
| severity-filter | 350 | 1.0 % |

### Per-prompt candidate share

| prompt | bytes | candidate | % | pin files |
|---|---:|---:|---:|---:|
| SKILL_WORKTREE | 15,245 | 9,842 | **64.6 %** | **0** |
| SKILL_TDD | 17,870 | 5,879 | 32.9 % | 3 |
| IMPLEMENTATION | 9,748 | 2,242 | 23.0 % | 2 |
| SKILL_LOOP | 24,833 | 5,168 | 20.8 % | 5 |
| PLANNING | 12,772 | 2,565 | 20.1 % | 6 |
| VALIDATION | 19,220 | 3,817 | 19.9 % | 10 |
| SKILL_HITL | 9,862 | 1,851 | 18.8 % | 2 |
| ORCHESTRATION_PARALLEL | 8,498 | 1,548 | 18.2 % | 6 |
| SKILL_CODE_REVIEW | 10,605 | 1,437 | **13.6 %** | 1 |
| SKILL_PR | 21,333 | 1,716 | **8.0 %** | 11 |

### Top-10 largest single deletions, repo-wide

| # | site | quote | class | bytes | pins |
|---|---|---|---|---:|---|
| 1 | SKILL_WORKTREE 163-239 | `cat > docs/ai/STATE.yaml <<EOF` | derivable-from-code | 1,893 | none |
| 2 | SKILL_LOOP 253-298 | "CHECKPOINT GATE (if checkpoint_mode" | example-to-tool | 1,750 | none |
| 3 | VALIDATION 232-245 | "RATIONALIZATION TABLE (stop and correct" | obsolete-guardrail | 1,606 | none |
| 4 | SKILL_TDD 13-78 | "Phase 0: Orchestration Preflight" | derivable-from-code | 1,600 | 2 lines only |
| 5 | PLANNING 152-163 | "RATIONALIZATION TABLE (stop and correct" | obsolete-guardrail | 1,570 | none |
| 6 | IMPLEMENTATION 119-128 | "RATIONALIZATION TABLE (stop and correct" | obsolete-guardrail | 1,014 | none |
| 7 | SKILL_WORKTREE 481-519 | "Best Practices / When to Use Worktrees" | repeated-rule | 1,000 | none |
| 8 | SKILL_TDD 372-400 | "Safety & Enforcement / Hard Blocks" | repeated-rule | 950 | none |
| 9 | SKILL_WORKTREE 420-462 | "Integration with AAI Workflow" | example-to-tool | 941 | none |
| 10 | SKILL_WORKTREE 331-383 | "Command: Cleanup Worktree" | derivable-from-code | 900 | none |

The three RATIONALIZATION TABLEs (VALIDATION, PLANNING, IMPLEMENTATION) total
**4,190 B** and carry **zero pin coupling**. They are the single cleanest
instance of the thesis in this corpus: 26 rows of pre-emptive rebuttals to
things an older model said to itself ("The tests probably pass", "This is
obvious, no test needed", "I'll clean it up / test it after"). Every row's
actual rule is already stated imperatively in the same prompt's PROCESS or
INVARIANT RULES.

---

## 1. `.aai/SKILL_LOOP.prompt.md` — 24,833 B / 404 lines

Pins: 28 across `test-aai-hygiene-pack.sh`, `test-aai-prompt-diet.sh`,
`test-aai-token-capture.sh`, `test-aai-run-tests.sh`,
`test-aai-orchestration-mode.sh`.

| lines | quote (≤10 words) | class | bytes | pin-coupling | disposition |
|---|---|---|---:|---|---|
| 7-11 | "REQUIRED CAPABILITIES — Read and write files" | obsolete-guardrail — capability-negotiation guardrail from an era of heterogeneous harnesses; a current-gen host always has file+shell+subagent tools, and steps 3/4 already carry per-step fallbacks | 290 | none | delete |
| 28-46 | "Emit: `ac_status`: whenever a Spec-AC row" | derivable-from-code — the event set, the auto-filled `v/ts/actor`, the parent/sub-ref roll-up and the best-effort contract are all in `append-event.mjs`'s header/usage | 700 of 931 | `append-event.mjs` @L22 (`hygiene-pack:746`) — pin sits on the surviving invocation line | move-to-script-desc |
| 48-54 | "DOCS HYGIENE TICK CHECK (RFC-0002) Once per tick" | derivable-from-code — `docs-audit.mjs --quick` self-describes; "skip silently if absent" is the corpus-wide degrade convention | 250 of 460 | `aai-docs-audit` @L50 (`test-aai-docs-audit.sh`) | keep-shortened |
| 97-107 | "Also at loop start (once): vendored-layer drift preflight" | derivable-from-code — `layer-drift.mjs`'s own header states read-only/self-bounded/never-block | 300 of 647 | `layer-drift.mjs` @L103 (`hygiene-pack:639`) | keep-shortened |
| 149-153, 162-165 | "Rationale: fresh-context-per-iteration (filesystem-as-memory) is the" | obsolete-guardrail — persuasion prose (Huntley / Ralph Wiggum citations) justifying a rule to a model that might argue with it; the mechanism above it is already imperative | 669 | none | delete |
| 253-298 | "CHECKPOINT GATE (if checkpoint_mode != none)" | example-to-tool / progressive disclosure — 1.9 KB of literal terminal templates for a mode whose default is `none`; loaded on 100 % of ticks, used on ~0 % | 1,750 of 1,943 | none | move-to-script-desc (relocate to `.aai/system/CHECKPOINT_MODES.md`, read only when the caller sets the mode) |
| 339-342 | "FALLBACK (no subagent support) — If this agent" | obsolete-guardrail — subagent-capability negotiation; steps 3 and 4 each already state their own fallback | 216 | none | delete |
| 360-372 | "TICK LOG FORMAT — After the loop exits, print" | derivable-from-code — `loop-digest.mjs --json` returns exactly these fields and is already named at L209-215 | 299 | none | move-to-script-desc |
| 385-386 | "Surface cost in the tick log (step 6) when" | repeated-rule — step 6's COST bullet (L324-327) states this with more precision | 134 | none | delete |
| 393-401 | "STRICT RULES — Do NOT improvise role logic." | repeated-rule — all 7 lines restate step 2b/2d, step 4 and step 6's clock discipline verbatim | 560 | none | delete |

**KEEP inventory.** LOOP PARAMETERS 56-70 (the actual configuration surface).
Stop conditions 2a-2f (control flow, not advice). LEAK-SAFE TEST EXECUTION
71-95 — pinned by `run-tests:279-287` AND `prompt-diet` TEST-019, and backed by
a real 5.6 GB failure (`LEARNED.md` 2026-07-01); the *routing* rule ("never
invoke `vitest` directly") is nonetheless prose-only → `needs-gate-first` if
ever touched. Mode-aware dispatch 184-231 (selector contract, 5 pins).
VALIDATOR INDEPENDENCE 240-246 (pinned; positive record in `LEARNED.md`
2026-07-16/17). Step 6 `--started`/`--harness` MANDATORY wiring and the
`usage_total_tokens` note (token-capture-canary pins; the failure it prevents
— 255 runs with 0 recorded tokens — actually happened). CACHING DISCIPLINE
374-384 (principle; `stable prefix` pinned).

Bytes: total 24,833 · candidate 5,168 · **20.8 %**.

---

## 2. `.aai/SKILL_PR.prompt.md` — 21,333 B / 340 lines

Pins: 71 across 11 suites — the most tightly coupled prompt in the corpus.

| lines | quote (≤10 words) | class | bytes | pin-coupling | disposition |
|---|---|---|---:|---|---|
| 2-11 | "You are a PR CEREMONY AGENT. You turn a" | derivable-from-code — GOAL paraphrases the PROCESS below it | 250 of 467 | `NEVER merge` @L5, `staged-vs-scope audit` @L5, `operator` @L6, `Spec-AC` @L11 (`hooks-overlay`, `hygiene-pack:58/70/72`) — four pinned phrases on three lines | keep-shortened |
| 15-25 | "Exit 0: proceed. Non-zero: STOP — print the guard's" | derivable-from-code — `branch-guard.mjs` prints its own remediation; the prompt re-lists the guard's three fail-closed conditions | 350 of 801 | `BRANCH HYGIENE`/`branch-guard.mjs` @L14, STOP-regex @L17 (`branch-guard:264-268`) | move-to-script-desc |
| 258-271, 272-277, 284-292 | "Zero findings after a green run: the 'no bot" | repeated-rule (intra-section) — the `reviewer_bots == expected` AND bot-demonstrably-reviewed condition is restated in full THREE times inside step 5d, plus a fourth partial in the fallback contract | 800 of 2,698 | `reviewer_bots == expected` @L264, `!= expected` @L266, `REQUIRED before any merge-readiness claim` @L290, `bounded wait` @L292 (`pr-platform:268-405`) — all four survive a single canonical statement | keep-shortened |
| 328-333 | "STRICT RULES — No `git add -A`, no `git add .`" | repeated-rule — step 2 (L71-73) states it with rationale and holds the pins; step 6 owns the merge boundary; step 3 owns the abort rule | 316 | pins live on L71-72 (`hygiene-pack:56/62`) and L309 (`hygiene-pack:68`), NOT on this block | delete |

**KEEP inventory.** Steps 1b/1c/2b/5/5c (allocator, delta-merge, reconcile,
platform gate, close ceremony) — these are *already* the unhobbled shape the
thesis endorses: the prompt sequences deterministic scripts and branches on
their exit codes. Step 5b MERGE-CONFLICT RESOLUTION (L205-219) is pinned
sixfold (`hygiene-pack:599-615`) **and** `needs-gate-first`: the
`grep -n '^<<<<<<<'` pre-add check and the `.git/MERGE_HEAD` two-parent verify
have no runtime enforcement, and the prompt records that the silent-abort case
was actually observed. Step 6 MERGE BOUNDARY (hooks-overlay pins + Constitution
art. 7). Scope-only staging (L71-73) is `needs-gate-first` — the staged-vs-scope
audit is agent-performed, nothing mechanically rejects an out-of-scope path.

**Honest note:** SKILL_PR is the least deletable prompt here by a wide margin
(8.0 %). Its bulk is not guardrail prose but script sequencing plus branch
conditions with real exit-code semantics. Do not force a -40 % target on it.

Bytes: total 21,333 · candidate 1,716 · **8.0 %**.

---

## 3. `.aai/VALIDATION.prompt.md` — 19,220 B / 269 lines

Pins: 34 across 10 suites (the highest suite count in the corpus).

| lines | quote (≤10 words) | class | bytes | pin-coupling | disposition |
|---|---|---|---:|---|---|
| 3-7 | "REQUIRED CAPABILITIES — Read files in the repository" | obsolete-guardrail — capability negotiation | 308 | none | delete |
| 14-25 | "The validator must be a DIFFERENT context from the" | repeated-rule — the SAME rule has three homes: here, SKILL_LOOP 240-246 (pinned), ORCHESTRATION_PARALLEL 102-110 (pinned by `state.sh:2046`). Only this copy is unpinned | 600 of 959 | none on this copy | keep-shortened → one canonical home in `.aai/ROLE_COMMON.md` (which already hosts 5 such blocks), pointer here |
| 28-33 | "Adversarial stance (anti self-evaluation): default to FAIL and" | verification-instruction — Anthropic's first deletion class | 250 of 435 | none | keep-shortened — **this one has a positive record** (`LEARNED.md` 2026-07-16/17: adversarial validator on a different model caught what static review passed). Keep the imperative line, drop the four lines of justification |
| 40-45 | "pydantic-monty or `aai-python-monty` scratchpad output is not validation" | repeated-rule — `ROLE_COMMON.md` PYTHON MONTY SCRATCHPAD already states "never final validation evidence" | 180 of 407 | none | delete the duplicate sentence |
| 129-131 | "Advisory: run `spec-lint.mjs --path <spec_path>` and record" | repeated-rule — PLANNING L129-130 states the same advisory with the same degrade clause | 80 of 130 | `2) Inventory all requirements` @L129 (`spec-lint:421`) — the pin is the step-2 heading, not the advisory sentence | keep-shortened |
| 232-245 | "RATIONALIZATION TABLE (stop and correct any of these)" | obsolete-guardrail — 10 rows of pre-emptive rebuttals presuming a model that talks itself out of running suites; every row's rule is already in PROCESS 5a-5g, INVARIANT RULES, or STRICT RULES | 1,606 | **none** | delete |
| 246-254 | "STRICT RULES — Do not infer intent. Do not soften" | repeated-rule — 9 lines each restating an INVARIANT RULE or a step-5 clause; line 255 (`merged per .aai/SUBAGENT_PROTOCOL.md`) is pinned and stays | 593 | pin at L255 only (`hygiene-pack:828`) | delete L246-254, keep L255 |
| 257-265 | "FINAL OUTPUT REQUIRED — Coverage table (Requirement → Spec" | derivable-from-code — the return shape is owned by `.aai/SUBAGENT_CONTRACT.md` and mechanically checked by `check-role-output.mjs`; only the AC-gate-result line has no script equivalent | 200 of 432 | none | keep-shortened — **needs-gate-first** for the gate-result line |

**KEEP inventory.** AC STATUS GATE L47-92: the MECHANICAL CHECKS half is already
delegated to `docs-audit.mjs --gate` (the correct shape), and the PROSE RULES
half (Rule 3 global overdue interrupt, Rule 4 anti-cheat 14-day floor) is
self-labelled "the script does NOT compute these … do not delete this section,
its removal would regress enforcement" and is pinned five ways
(`docs-audit:5279-5290`) → `needs-gate-first`, verbatim. CEREMONY LANE 94-108
(pinned). STRATEGY-CONDITIONAL EVIDENCE 109-124 (six pins). Step 5c LEAK-SAFE
(two pins ×2 suites). Step 5f seam check and 5g RED-proof. Step 8a's
false-open EXCEPTION — this is *memory of a specific past failure*
(`MEMORY.md` "EVENTS restore wipes close telemetry" / probable-false-open Arm
A) and exactly the kind of repo-specific gotcha the thesis says to keep.
Step 8b close policy + close gate (four pins).

Bytes: total 19,220 · candidate 3,817 · **19.9 %**.

---

## 4. `.aai/SKILL_TDD.prompt.md` — 17,870 B / 424 lines

Pins: 12 across 3 suites — high size, low coupling.

| lines | quote (≤10 words) | class | bytes | pin-coupling | disposition |
|---|---|---|---:|---|---|
| 9 | "Inspired by Superpowers framework's mandatory TDD cycles." | repeated-rule — same attribution line also in SKILL_WORKTREE L9; provenance belongs in `SUPERPOWERS_INTEGRATION.md`, which already exists | 120 | none | delete |
| 13-78 | "Phase 0: Orchestration Preflight — Objective: Reach a TDD-ready" | derivable-from-code — a hand-rolled re-implementation of the tick loop (capped at "max 5 setup ticks") that `orchestration-dispatch.mjs` already computes deterministically | 1,600 of 3,185 | `direct`/`untested` @L64, `do NOT start RED` @L65 (`implementation-mode:109-110`) — step 5 keeps its lines verbatim | keep-shortened (collapse steps 1-4 and 7 into a pointer at `ORCHESTRATION.prompt.md`; keep step 5 strategy gate + step 6 worktree gate) |
| 100-114 | "`npm test [test-file]  # or appropriate command`" | example-to-tool — pseudo-commands for three ecosystems the project does not use; `docs/TECHNOLOGY.md` is the declared source and `aai-run-tests.sh` is the declared runner | 393 | none | delete → replace with "run the command `docs/TECHNOLOGY.md` declares, through `.aai/scripts/aai-run-tests.sh`" |
| 148-158 | "RED Phase Checklist: TEST-xxx selected from spec Test" | verification-instruction — 10 checkboxes restating the 6 numbered steps immediately above them | 516 | none | delete |
| 214-222 | "GREEN Phase Checklist: Implementation added to source code" | verification-instruction | 289 | none | delete |
| 240-263 | "Identify Refactoring Opportunities — Code duplication / Complex conditionals" | obsolete-guardrail — a generic refactoring taxonomy (duplication, poor naming, SOLID) plus a generic "Refactor Code" verb list; a current-gen model does not need to be told these are refactor targets | 599 | none | delete |
| 279-287 | "REFACTOR Phase Checklist: Refactoring completed / All tests still" | verification-instruction | 239 | none | delete |
| 351-370 | "Integration with AAI Workflow / Unified Flow (same spec" | derivable-from-code — the ASCII flow duplicates `.aai/workflow/WORKFLOW.md` and `orchestration-dispatch.mjs` | 823 | none | move-to-script-desc |
| 372-400 | "Safety & Enforcement / Hard Blocks — 1. Cannot skip" | repeated-rule — all six Hard Blocks restate a `**BLOCK:**` line or a Phase-4 gate already in the body | 950 | pin `BLOCKING findings` is at L323 (Phase 4 step 3), above this block | delete |
| 401-409 | "Warnings — 1. Test coverage regression / 2. Over-engineering" | severity-filter — advisory noise with no detector, no gate and no artifact; "Detect if implementation is more complex than needed" is unactionable and muzzle-shaped | 350 | none | delete (or `move-to-probe` if the coverage warning is wanted for real) |

**KEEP inventory.** Phase 1 step 4 RED_CLASS classification + `tdd-evidence-check.mjs`
(five pins, `tdd-evidence:253-261`) — the anti-tautology mechanism, already
script-backed. The fixture-diversity checklist L139-147 (SPEC-0013 H7): no
script computes it, and happy-path-only suites remain a live failure class →
`needs-gate-first`. The RED-proof extension question at L146. Phase 4 step 1b
AC-table reconciliation (pointer to ROLE_COMMON + `--gate`). State-CLI calls
and their FALLBACK lines (pinned `hygiene-pack:245/247`).

Bytes: total 17,870 · candidate 5,879 · **32.9 %**.

---

## 5. `.aai/SKILL_WORKTREE.prompt.md` — 15,245 B / 623 lines

Pins: **0.** No suite greps this file's content. `suite-map.yaml:628` lists the
path as a change-trigger only. This is the highest-value, lowest-risk target in
the corpus.

| lines | quote (≤10 words) | class | bytes | pin-coupling | disposition |
|---|---|---|---:|---|---|
| 1-18 | "What are Git Worktrees? Git worktrees allow multiple working" | derivable-from-code — `git worktree --help`; plus the duplicated Superpowers attribution | 709 | none | delete |
| 163-239 | "`cat > docs/ai/STATE.yaml <<EOF`" | derivable-from-code + repeated-rule — `.aai/templates/STATE_TEMPLATE.yaml` (2,584 B, tracked since CHANGE-0074, pinned to `SKILL_CHECK_STATE`) is the canonical schema. **This copy has already drifted**: no `spec_path`, no `metrics`, no `orchestration` block, and it hard-codes `code_review.required: true` | 1,893 | none | delete → "seed from `.aai/templates/STATE_TEMPLATE.yaml`, then set ref/branch/path" |
| 262-292 | "Command: Switch Worktree — git worktree list" | derivable-from-code — `git worktree list` plus `cd` | 521 | none | delete |
| 294-329 | "Command: List Worktrees — git worktree list --porcelain" | derivable-from-code — including a fabricated example output table | 646 | none | delete |
| 331-383 | "Command: Cleanup Worktree — Remove a completed or abandoned" | derivable-from-code — `git worktree remove` refuses on a dirty tree by itself | 900 of 1,213 | none | keep-shortened — **the archive-STATE-before-remove ordering is `needs-gate-first`**: `LEARNED.md` 2026-07-16/17 records real, unrecoverable metrics loss from doing it in the other order |
| 385-418 | "Command: Sync Worktree — git fetch origin / git rebase" | derivable-from-code | 592 | none | delete |
| 420-462 | "Integration with AAI Workflow / Parallel Feature Development" | example-to-tool — a two-feature walkthrough with invented paths | 941 | none | delete |
| 464-479 | "Token Optimization / Benefits — No Context Pollution … Reduced" | obsolete-guardrail — motivational prose selling the feature to the model | 394 | none | delete |
| 481-519 | "Best Practices / When to Use Worktrees" | repeated-rule — "Recommendation levels" (499-504) is a verbatim second home for PLANNING step 8 (L93-102); "Daily / Weekly / Monthly" cleanup schedule is unenforced aspiration | 1,000 of 1,180 | none | delete (levels keep ONE home, in PLANNING) |
| 520-549 | "Prevent Data Loss — `if [ -n \"$(git status --porcelain)\" ]`" | derivable-from-code — a bash snippet re-implementing a check git performs, plus an invented confirmation menu | 645 | none | delete |
| 550-582 | "Troubleshooting / Worktree creation fails — git worktree prune" | derivable-from-code — `git worktree prune` / `repair` | 553 | none | delete |
| 584-590 | "Track worktree usage in `docs/ai/METRICS.jsonl`" | derivable-from-code — the METRICS schema is owned by `state.mjs` / `metrics-flush.mjs` | 321 | none | delete |
| 592-623 | "Example Session — `$ /aai-worktree setup login main`" | example-to-tool | 727 | none | delete |

**KEEP inventory.** L21-124 "Command: Recommendation Gate" (3,492 B) — the only
behavioral contract in the file, and it is load-bearing: it owns the exact
`WORKTREE DECISION REQUIRED` block that `ROLE_COMMON.md` WORKTREE GATE and
`[HITL-7]` dispatch to, the never-create-without-explicit-confirmation rule,
the inline-scope cleanliness requirement, and the `decisions.jsonl` record. Plus
L126-162, the actual `git worktree add` recipe with the sibling-path convention.
That is ~5.4 KB of real prompt; the other 9.8 KB is a git tutorial.

**Migration note:** this file is the one candidate large enough to be a
one-shot rewrite (SKILL_DOCTOR / SKILL_DASHBOARD precedent), and precisely
because it has zero pins, a rewrite should ADD a small pin set (gate heading,
the decision block text, `never create … without explicit user confirmation`)
so the next diet cannot silently delete the contract.

Bytes: total 15,245 · candidate 9,842 · **64.6 %**.

---

## 6. `.aai/PLANNING.prompt.md` — 12,772 B / 186 lines

Pins: 18 across 6 suites, concentrated on steps 3a, 7, 11 and 12.

| lines | quote (≤10 words) | class | bytes | pin-coupling | disposition |
|---|---|---|---:|---|---|
| 3-6 | "REQUIRED CAPABILITIES — Read and write files in the" | obsolete-guardrail — capability negotiation | 212 | none | delete |
| 22-27 | "PATTERN CONTEXT (load before planning) — For each of" | repeated-rule — byte-identical block in IMPLEMENTATION L25-29; `ROLE_COMMON.md` is the established home for exactly this shape (5 blocks already there) | 329 | none | move-to-script-desc → `ROLE_COMMON.md` + pointer (net ledger effect ≈0: `ROLE_COMMON.md` is inside TEST-010's extra accounting) |
| 93-102 | "Recommend worktree isolation in the spec: `required` for protected" | repeated-rule — second home is SKILL_WORKTREE 499-504 | 0 here | none | keep HERE; the duplicate is deleted in §5 |
| 17 | "Read docs/TECHNOLOGY.md before making any tooling/framework assumptions." | repeated-rule — third home (IMPLEMENTATION L18, VALIDATION L253) | 0 here | none | keep one home |
| 152-163 | "RATIONALIZATION TABLE (stop and correct any of these)" | obsolete-guardrail — 9 rows of pre-emptive rebuttals; each restates step 5/6/6a/7/8/9 or a STRICT RULE | 1,570 | **none** | delete |
| 165-168 | "STRICT RULES — Stop and request human decision if" | repeated-rule — "stop if AC ambiguous" is step 10's freeze condition; "do not implement" is INVARIANT RULES line 1 | 204 | none | delete |
| 170-180 | "FINAL OUTPUT REQUIRED — Planned scope summary" | derivable-from-code — 11 bullets restating what steps 4-11 already produce; the handoff shape is owned by `BRIEF_TEMPLATE.md` + `SUBAGENT_CONTRACT.md` | 250 of 517 | none (the pins are on the step headings L131/L137) | keep-shortened |

**KEEP inventory.** Step 3a COMPANION OBLIGATIONS CHECK (pinned
`hygiene-pack:918`) — this is *the* rule that keeps the diet ledger honest and
is itself the pin-migration reminder for every row in this document. Step 6a
seam analysis (L65-76): repo-specific, non-obvious, and enforced only in
VALIDATION 5f prose → `needs-gate-first`. Step 7 intake-choice respect clause
(two pins) — written from a reported user friction. Step 10 freeze conditions +
ceremony level (pointer to WORKFLOW, correct shape already). Steps 11-12 (seven
pins).

Bytes: total 12,772 · candidate 2,565 · **20.1 %**.

---

## 7. `.aai/SKILL_CODE_REVIEW.prompt.md` — 10,605 B / 224 lines

Pins: 35 greps, all in `test-aai-hygiene-pack.sh` (1 pin FILE — the change
draft's "lowest pin coupling" reading is correct at file granularity, but the
*grep density* is high: 35 assertions, plus a hard `<=250 lines` ceiling and a
negative-grep whitelist in `test_043`).

**This prompt is already post-diet** (766 → 224 lines, RES-0001 F3 /
spec-single-dual-verdict-review) and it is the leanest of the ten. Its
candidate share is the second-lowest in the corpus. I am not padding it.

| lines | quote (≤10 words) | class | bytes | pin-coupling | disposition |
|---|---|---|---:|---|---|
| 2-10 | "ONE review pass, TWO independent verdicts, plus an honest-gaps" | obsolete-guardrail — change-history narrative (RFC/RES-0001 F4 measurement, the "revert path is restoring the prior prompt from git history") plus an **expired** measurement gate ("compares the next 5 reviewed scopes"); 98 reviews have run since | 514 | none — `test_043`'s whitelist merely *permits* the "two-stage" mention; removing it satisfies the negative grep more strongly | delete → history belongs in the spec, not in every dispatch |
| 45-53 | "Before reviewing: 1. Read `docs/ai/STATE.yaml`. 2. Determine" | derivable-from-code — a 6-step recipe for reading two STATE fields and running `git status`; the model reads STATE anyway | 180 of 430 | `DIFF SCOPE PREFLIGHT` @L32 (heading survives) | keep-shortened |
| 55-59 | "Worktree policy: If `worktree.user_decision == worktree`, prefer" | repeated-rule — restates the accepted-scopes list at L37-44 in different words | 309 | none | delete |
| 103-105 | "Overall review status: pass ONLY when both verdicts pass." | repeated-rule — STATE CONTRACT Status rules (L158-162) says the same, and that copy is the one the CLI consumes | 194 | `both verdicts pass` pinned (`hygiene-pack:482`) — **the pin survives at L158** (`` `pass`: both verdicts pass ``), verified case-insensitively | delete |
| 217-221 | "RE-REVIEW AFTER REMEDIATION — The same single pass, automatically" | repeated-rule — says "no special casing" and then re-lists the five steps of the pass | 240 | none | delete |

**KEEP inventory.** ANTI-GAMING CONTRACT L12-30 — pinned six ways
(`hygiene-pack:508-518`) and `needs-gate-first`: nothing mechanically prevents
a dispatcher from pre-rating severity or scope-excluding areas, and this block
was written from measured dogfood friction (review dogfood NB-2, friction 3).
The three verdicts L69-105 (nine pins) — this is the artifact contract. The
SIDECAR LIFECYCLE pin L90-92 (ledger entry `196 runtime-state-consolidation`) —
a real, recent bug class. The structured YAML block L115-136. Report staging
H4 + `docs/validation/` prohibition (pinned; SPEC-0015 review lesson — a real
audit-flip). H6 warnings policy (three pins). External Review Response L187-215
(five pins) — and architecturally correct: SKILL_PR 5d *delegates* here rather
than duplicating, which is already the "one home per rule" shape.

**Design warning for the experiment.** A V1/V2 target of −40 % (≈4,240 B) on
this prompt cannot be met from repetition: only 1,437 B of it is repetition or
dead history. The remaining 2.8 KB would have to come out of the AC-walk /
verdict / anti-gaming contract, i.e. out of the load-bearing part, and 35 greps
sit on top of it. Either lower the pilot's byte target to ≈−14 %, or accept
that V1 and V2 will differ mostly in *phrasing* rather than *size* — in which
case H2 (compression-vs-altitude at equal bytes) becomes untestable on this
pilot. Consider PLANNING (20.1 %, 18 pins) or SKILL_TDD (32.9 %, 12 pins) as
the pilot instead, and note that SKILL_TDD's dispatch count (61) is the
second-highest after CODE_REVIEW's 98.

Bytes: total 10,605 · candidate 1,437 · **13.6 %**.

---

## 8. `.aai/SKILL_HITL.prompt.md` — 9,862 B / 205 lines

Pins: 25 across `test-aai-hitl-propagation.sh` and `test-aai-hitl-channel.sh`,
concentrated on STEP 0 and the STEP 4c tables.

| lines | quote (≤10 words) | class | bytes | pin-coupling | disposition |
|---|---|---|---:|---|---|
| 1-9 | "You are a HITL RESOLUTION AGENT. You handle the" | derivable-from-code — the TRIGGER condition is literally `human_input.required: true`, which `state.mjs` and the loop already report | 150 of 379 | `human_input.required: true` @L8 (`hitl-propagation:289`) | keep-shortened |
| 58-64 | "STEP 3 — VALIDATE ANSWER — The answer is valid" | obsolete-guardrail — tells the model what a sufficient answer is; a current-gen model does not need a definition of "addresses the question". The real contract is the FAIL-CLOSED enum rule at L135-144 | 376 | none | delete → keep only "ask ONE targeted follow-up, then proceed" |
| 66-95 | "STEP 4 — RECORD DECISION — Save the human's decision" | derivable-from-code — two literal templates (a Markdown artifact and a JSONL line) for a file every other role appends to without a template; `.aai/templates/DECISION_TEMPLATE.md` exists | 600 of 943 | none | move-to-script-desc — **`needs-gate-first`**: there is no `state.mjs record-decision` / decision-append helper today, so the templates are the only spec of the shape. Build the helper first |
| 108-115 | rows "`[HITL-1]` Product intent ambiguity … none \| none" | derivable-from-code — six table rows whose entire payload is "no STATE gate, no command" | 400 of 606 | rows 7/8/9 pinned (`hitl-propagation:222-228`); rows 1-6 unpinned | keep-shortened → one line "`HITL-1..6` have no STATE gate" plus the `[HITL-6]` no-waiver-enum caveat (which is real information) |
| 195-202 | "STRICT RULES — The resolver may write `human_input` PLUS" | repeated-rule — a verbatim second copy of the NARROWED GUARDRAIL at L163-171 | 325 | `ONE declared target field`, `via the typed`, `nothing else` pinned (`hitl-propagation:250-255`) — **all three phrases also occur at L164-165**, so the STEP 5 copy satisfies every pin | delete the STRICT RULES copy |

**KEEP inventory.** STEP 0 async channel (eight pins) including the
UNTRUSTED-DATA rule and the token+ref staleness guard — that guard exists
because of a bot-found P1 (`551 async-hitl-botfix`, token reuse across work
items). The STEP 4c trigger→target mapping rows 7/8/9 and the answer
normalization table (nine pins) — this IS the contract. FAIL-CLOSED rule
L135-144 and WRITE ORDERING L150-153 (pinned; the ordering prevents the exact
cleared-with-unset-gate failure the mapping was built to fix). STEP 5 NARROWED
GUARDRAIL L163-171. The `HITL RESOLVED` / `HITL UNRESOLVED` output blocks
(pinned).

Bytes: total 9,862 · candidate 1,851 · **18.8 %**.

---

## 9. `.aai/IMPLEMENTATION.prompt.md` — 9,748 B / 161 lines

Pins: 7 across `test-aai-implementation-mode.sh` and `test-aai-hygiene-pack.sh`.

| lines | quote (≤10 words) | class | bytes | pin-coupling | disposition |
|---|---|---|---:|---|---|
| 3-7 | "REQUIRED CAPABILITIES — Read and write files in the" | obsolete-guardrail — capability negotiation | 318 | none | delete |
| 18 | "Read docs/TECHNOLOGY.md before making any tooling/framework assumptions." | repeated-rule — third home (PLANNING L17, VALIDATION L253) | 90 | none | keep one home |
| 25-29 | "PATTERN CONTEXT (load before implementing) — For each of" | repeated-rule — byte-identical to PLANNING L22-27 | 332 | none | move-to-script-desc → `ROLE_COMMON.md` + pointer |
| 119-128 | "RATIONALIZATION TABLE (stop and correct any of these)" | obsolete-guardrail — 7 rows ("Tests will pass, I don't need to run them", "This is obvious, no test needed", "The change is too small to matter"); each restates INVARIANT RULES, step 4 or step 9 | 1,014 | **none** | delete |
| 140-144 | "STRICT RULES — If spec gaps are found, stop" | repeated-rule — 4 of 4 restate INVARIANT RULES / step 4 / DECOMPOSITION step 5; line 145 is pinned and stays | 288 | pin at L145 only (`hygiene-pack:845`) | delete L140-144, keep L145 |
| 147-155 | "FINAL OUTPUT REQUIRED — Scope and spec reference" | derivable-from-code — the return shape is `SUBAGENT_CONTRACT.md` + `check-role-output.mjs` | 200 of 339 | none | keep-shortened |

**KEEP inventory.** Step 4 strategy enforcement (four pins,
`implementation-mode:97-101`) — the `direct`/`untested` lanes are a user-facing
choice with a CLI-enforced rationale. Step 5 worktree gate (ROLE_COMMON
pointer). Step 6b expert resolution incl. the explicit "do NOT read the
registry file" (a token-economy instruction with a real cost basis). Step 9b
pre-handoff AC reconciliation — its rationale sentence ("A gate-opted spec
reaching Validation with `planned` rows guarantees a wasted
FAIL→Remediation→re-Validation cycle") names a measured cost, not a vibe.
VERIFICATION-BEFORE-COMPLETION L130-131 — pinned (`verify-gate:111`) and backed
by a real gate file → `needs-gate-first` (nothing at runtime enforces it).
FRICTION HOOK L133-138 — see the honesty note: **this one has fired 0 times**,
but it is pinned by `friction-wiring` hostile-mutation tests, so its removal is
a pin migration, not a deletion.

Bytes: total 9,748 · candidate 2,242 · **23.0 %**.

---

## 10. `.aai/ORCHESTRATION_PARALLEL.prompt.md` — 8,498 B / 157 lines

Pins: 20 across 6 suites.

| lines | quote (≤10 words) | class | bytes | pin-coupling | disposition |
|---|---|---|---:|---|---|
| 5-9 | "REQUIRED CAPABILITIES — Read and write files in the" | obsolete-guardrail — capability negotiation, and it contradicts itself ("Spawn concurrent subagent tasks (preferred) OR execute sequentially") with the same fallback restated at L152-156 | 316 | none | delete |
| 26-30 | "STATE OWNERSHIP POLICY — `docs/ai/STATE.yaml` is orchestration-managed runtime" | repeated-rule — the single-writer rule is stated again at L40-42 (pinned) and lives canonically in `.aai/SUBAGENT_CONTRACT.md` | 236 | none (L42 holds the pin) | delete |
| 58-71 | "STATE DISCOVERY — For each scope … classify: NEEDS_PLANNING" | derivable-from-code — `orchestration-dispatch.mjs` computes exactly this classification and returns the dispatch; the prompt re-derives it by hand | 347 | none | move-to-script-desc |
| 117-125 | "State update summary for docs/ai/STATE.yaml (applied by YOU" | repeated-rule — the same three `state.mjs` calls and the same "each bumps `updated_at_utc`" note appear again at L146-149 | 400 of 649 | `Scope, Role, Model, Inputs` @L116 (`state.sh:2048`) — the pinned line is above the block | keep-shortened |
| 152-156 | "If the platform does NOT support concurrent subagents" | obsolete-guardrail — capability negotiation, third statement of the same fallback | 249 | none | delete |

**KEEP inventory.** SCOPE LOCKING L39-56 (six pins) — the acquire/release call
pattern with exit-code branches, already trimmed to a pointer at
`docs-lock.mjs`'s header by CHANGE-0110; correct shape. The selector
cross-reference L19-24 (pinned). MODEL SELECTION L94-101 (pinned;
`MODEL_ROUTING.yaml` makes it a real binding, not advice). VALIDATOR
INDEPENDENCE L102-110 (pinned by `state.sh:2046`) — **recommend making this
pinned copy the single canonical home** and pointing VALIDATION 14-25 and
SKILL_LOOP 240-246 at it. SUBAGENT EXECUTION L127-150 (six pins) incl. the
R-GUARD `AAI_ROLE=subagent` env clause and the cache-friendly stable-first
context ordering (both bot-review-derived).

Bytes: total 8,498 · candidate 1,548 · **18.2 %**.

---

## Suggested first diet ride — safe immediate wins

Rows with **zero pin coupling** AND class in {derivable-from-code,
repeated-rule, verification-instruction}. No behavioral rule loses its only
home; no pinned sentence is touched.

| prompt | lines | what | class | bytes |
|---|---|---|---|---:|
| SKILL_WORKTREE | 163-239 | inline `STATE.yaml` heredoc → seed from `STATE_TEMPLATE.yaml` | derivable-from-code | 1,893 |
| SKILL_WORKTREE | 481-519 | Best Practices / recommendation-levels duplicate | repeated-rule | 1,000 |
| SKILL_TDD | 148-158, 214-222, 279-287 | three phase checklists | verification-instruction | 1,044 |
| SKILL_TDD | 372-400 | Hard Blocks 1-6 | repeated-rule | 950 |
| SKILL_TDD | 351-370 | Unified Flow ASCII diagram | derivable-from-code | 823 |
| SKILL_WORKTREE | 294-329 | List Worktrees | derivable-from-code | 646 |
| SKILL_WORKTREE | 520-549 | Prevent Data Loss bash snippets | derivable-from-code | 645 |
| SKILL_WORKTREE | 385-418 | Sync Worktree | derivable-from-code | 592 |
| VALIDATION | 246-254 | STRICT RULES (keep L255) | repeated-rule | 593 |
| SKILL_LOOP | 393-401 | STRICT RULES | repeated-rule | 560 |
| SKILL_WORKTREE | 550-582 | Troubleshooting | derivable-from-code | 553 |
| SKILL_WORKTREE | 262-292 | Switch Worktree | derivable-from-code | 521 |
| SKILL_CODE_REVIEW | 55-59 | Worktree policy restatement | repeated-rule | 309 |
| SKILL_WORKTREE | 584-590 | METRICS jsonl example | derivable-from-code | 321 |
| SKILL_HITL | 195-202 | STRICT RULES copy of NARROWED GUARDRAIL | repeated-rule | 325 |
| ORCHESTRATION_PARALLEL | 58-71 | STATE DISCOVERY classification list | derivable-from-code | 347 |
| PLANNING | 22-27 | PATTERN CONTEXT → `ROLE_COMMON.md` | repeated-rule | 329 |
| IMPLEMENTATION | 25-29 | PATTERN CONTEXT → `ROLE_COMMON.md` | repeated-rule | 332 |
| SKILL_LOOP | 360-372 | TICK LOG FORMAT → `loop-digest.mjs` | derivable-from-code | 299 |
| IMPLEMENTATION | 140-144 | STRICT RULES (keep L145) | repeated-rule | 288 |
| SKILL_CODE_REVIEW | 217-221 | RE-REVIEW AFTER REMEDIATION | repeated-rule | 240 |
| ORCHESTRATION_PARALLEL | 26-30 | STATE OWNERSHIP POLICY | repeated-rule | 236 |
| PLANNING | 165-168 | STRICT RULES | repeated-rule | 204 |
| SKILL_CODE_REVIEW | 103-105 | "Overall review status" (pin survives L158) | repeated-rule | 194 |
| VALIDATION | 40-45 | Monty-is-not-evidence duplicate sentence | repeated-rule | 180 |
| SKILL_LOOP | 385-386 | cost-surfacing duplicate | repeated-rule | 134 |
| **total** | | | | **13,558** |

Two of these (the PATTERN CONTEXT pair, 661 B) are relocations into
`.aai/ROLE_COMMON.md`, which sits inside TEST-010's extra accounting, so the
ledger-visible shrink is ≈12.6 KB.

**Required companion work for this ride** (PLANNING step 3a COMPANION
OBLIGATIONS, and the reason none of the above is literally free):

1. Append a NEGATIVE `JUSTIFIED_ADDITIONS` entry retiring the freed credit in
   `tests/skills/lib/prompt-diet-ledger.sh`.
2. Bump TEST-012's literal `1305` in `tests/skills/test-aai-prompt-diet.sh` by
   the same delta (≈`-12253` for a 13.5 KB ride). TEST-013 accepts the sign.
3. No `.aai/system/PROFILES.yaml` entry is needed — no new `.aai/**` file.
4. Re-run `test-aai-hygiene-pack.sh`, `test-aai-prompt-diet.sh`,
   `test-aai-verify-gate.sh` (it sources the same ledger) and
   `test-aai-ceremony-levels.sh` (it re-runs the diet suite).

### `needs-gate-first` register (11 rules — prose-only, do NOT delete without building the gate)

| # | rule | where | why no gate today |
|---|---|---|---|
| 1 | route every test command through `aai-run-tests.sh` | SKILL_LOOP 71-95, VALIDATION 137-146 | scripts exist; nothing forces their use |
| 2 | scope-only staging (no `git add -A`) | SKILL_PR 71-73 | the staged-vs-scope audit is agent-performed |
| 3 | no surviving conflict marker; verify `MERGE_HEAD` | SKILL_PR 213-219 | no pre-commit conflict-marker check on the resolution path |
| 4 | AC-gate Rule 3 (global overdue) + Rule 4 anti-cheat | VALIDATION 73-92 | the section says so itself; `--gate` scores one doc, no date math |
| 5 | AC-status-gate line in FINAL OUTPUT | VALIDATION 264-265 | `check-role-output.mjs` validates the result block, not this section |
| 6 | fixture diversity checklist | SKILL_TDD 139-147 | no detector for happy-path-only suites |
| 7 | archive `STATE.yaml` BEFORE `git worktree remove` | SKILL_WORKTREE 347-353 | real loss recorded in `LEARNED.md`; no hook |
| 8 | seam analysis → one crossing integration test | PLANNING 65-76 | VALIDATION 5f enforces it in prose only |
| 9 | reviewer anti-gaming contract | SKILL_CODE_REVIEW 12-30 | nothing inspects the dispatch prompt |
| 10 | decision artifact + JSONL shape | SKILL_HITL 66-95 | no `record-decision` helper exists |
| 11 | verification-before-completion gate | IMPLEMENTATION 130-131 | `SKILL_VERIFY` is a prompt, not a runtime check |

Items 1, 6, 8 and 11 are the best candidates for the behavioral-probe suite the
change draft's H3 requires: each has a tempting shortcut and each can be
asserted on artifacts (exit codes, RED-log presence, integration-test presence,
evidence files) rather than prose.

## Caveats

- Byte estimates for `keep-shortened` rows are judgement calls (typically 40-70 %
  of the block). Exact numbers only exist after the rewrite.
- Pin resolution is mechanical but not exhaustive: it covers `grep`-style
  assertions with quoted literals or resolvable regexes. Dynamically-built
  patterns, and assertions in `tests/skills/*.Tests.ps1`, are not covered.
- `docs/ai/STATE.yaml` and `docs/ai/LOOP_TICKS.jsonl` are gitignored per
  developer, so dispatch counts quoted in the change draft's baseline were not
  re-derived here; this audit ranks by bytes and pin coupling only.
- Nothing here was applied. This document changes no prompt.
