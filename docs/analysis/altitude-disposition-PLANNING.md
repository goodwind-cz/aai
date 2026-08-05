---
id: altitude-disposition-planning
type: research
number: null
status: draft
links:
  pr: []
  commits: []
---

# Analysis — rule-disposition ledger for `.aai/PLANNING.prompt.md`

Phase 1 of `docs/issues/CHANGE-0113-altitude-prompt-experiment.md`. The pilot
prompt is **PLANNING**, not SKILL_CODE_REVIEW: the Phase-0 unhobbling audit
(`docs/analysis/unhobbling-audit.md` §7, "Design warning for the experiment")
established that CODE_REVIEW carries only 1,437 B (13.6 %) of removable weight
against 35 grep assertions, so a −30/−40 % target there could only come out of
the load-bearing verdict contract and H2 (compression-vs-altitude **at equal
bytes**) would be untestable. PLANNING was named in that same paragraph as the
alternative. **This document changes no prompt.**

## Method

- **Subject** = `.aai/PLANNING.prompt.md` as it stands on `main` **after**
  CHANGE-0122 (strategy-scaled evidence, step 7) and CHANGE-0120 (atomic freeze
  through `spec-freeze.mjs`, step 10): **11,526 B / 176 lines**, sha256
  `4cd89c13…`. The Phase-0 audit measured 12,772 B / 186 lines; the delta is
  CHANGE-0114's diet ride (the RATIONALIZATION TABLE and the multi-line STRICT
  RULES block are already gone) plus the two additions above. Every audit row for
  PLANNING has therefore been re-checked against the current text; rows that the
  diet ride already applied are recorded in "Already applied" below rather than
  re-proposed.
- **Dispositions** are the four classes the task fixes:
  `keep-as-principle` | `move-to-script-gate` | `behavioral-probe-candidate` |
  `delete-redundant`. Exactly one class per row; where a kept principle would
  *also* make a good probe, the probe is noted in the row, not double-counted.
- **Pin coupling** was resolved by reading each suite that names the file and
  matching its literal `grep`/`assert` patterns back to the line they hit.
  `tests/skills/suite-map.yaml` entries are change-triggers, not assertions, and
  are not counted as pins.

## Summary

| disposition | rows |
|---|---:|
| keep-as-principle | 24 |
| move-to-script-gate | 10 |
| behavioral-probe-candidate | 5 |
| delete-redundant | 5 |
| **total** | **44** |

Pinned rows: **13 of 44** (30 %). Unpinned rows: 31. Every `delete-redundant`
and `move-to-script-gate` row below is pin-free **except** R18, R27, R30 and R37,
whose surviving pin sites are named in-row.

## The ledger

| # | lines | rule / instruction | disposition | enforcement / surviving home | pin coupling |
|---|---|---|---|---|---|
| R01 | 1 | "You are an autonomous PLANNING AGENT." | keep-as-principle | — | none |
| R02 | 3-6 | REQUIRED CAPABILITIES (read/write files, read/update STATE, spawn subagents "optional; skip decomposition if platform does not support it") | delete-redundant | harness contract; and the decomposition fallback has no referent — the current PROCESS contains no decomposition step | none |
| R03 | 8-11 | GOAL (convert intake requirements into a measurable spec; recommend strategy/isolation/review scope) | keep-as-principle | — | none |
| R04 | 14 | "No code implementation in planning." | behavioral-probe-candidate | nothing at runtime inspects what a Planning run wrote; probe asserts the run's diff touches only `docs/specs/**`, `docs/ai/**` | none |
| R05 | 15 | "Do not claim PASS." | behavioral-probe-candidate | `check-role-output.mjs` validates the result-block *shape*, not the verdict token; probe asserts no pass verdict in a Planning result block | none |
| R06 | 16 | "Every acceptance criterion must be measurable and verifiable." | keep-as-principle | `spec-lint.mjs` checks AC **id/status shape** (`ac-id-gap`, `ac-status-invalid`, `done-without-evidence`) — never measurability. This is the role's core judgment. | none |
| R07 | 17 | "Read docs/TECHNOLOGY.md before making any tooling/framework assumptions." | keep-as-principle | one home per rule; the other copies live in IMPLEMENTATION L18 and REMEDIATION | none |
| R08 | 18 | "Read and respect docs/ai/STATE.yaml before planning." | delete-redundant | step 1 (L34) states the same thing *with the actual predicate* (not paused, no blocking human input) | none |
| R09 | 19-20 | "Do not create a git worktree during Planning…" | behavioral-probe-candidate | probe asserts `git worktree list` is unchanged across a Planning run; the recommendation half stays as R28 | none |
| R10 | 22-26 | PATTERN CONTEXT (INDEX-first pattern loading) | delete-redundant | **byte-identical** to IMPLEMENTATION L25-29; relocate to `.aai/ROLE_COMMON.md`, which already hosts five such shared blocks, and leave a pointer | none |
| R11 | 30-32 | Validate STATE invariants; repair through orchestration or block | move-to-script-gate | `node .aai/scripts/check-state.mjs [--repair]` already computes and repairs the invariant set | none |
| R12 | 33 | Replay relevant learnings (`SKILL_REPLAY` semantics) | keep-as-principle | one-line pointer; correct shape already | none |
| R13 | 34 | Verify planning is allowed (project not paused, no blocking human input) | move-to-script-gate | `orchestration-dispatch.mjs` consumes exactly these STATE fields and refuses to dispatch Planning otherwise | none |
| R14 | 35 | Determine target scope from `current_focus` / `active_work_items` | move-to-script-gate | `orchestration-dispatch.mjs` `decide()` returns the scope and the dispatch; the prompt re-derives it by hand | none |
| R15 | 36 | Read the scope's requirement/intake artifacts | keep-as-principle | — | none |
| R16 | 37-44 | COMPANION OBLIGATIONS CHECK (closed 2-entry list: prompt-corpus growth -> diet-ledger true-up; new `.aai/**` file -> PROFILES classification) | keep-as-principle *(strong probe candidate)* | **no auto-detection script exists** — the block says so itself. A probe can assert: a fixture scope that adds prompt bytes yields a spec whose Test Plan names `tests/skills/lib/prompt-diet-ledger.sh` | **heaviest pinned block in the file** — `test-aai-hygiene-pack.sh:918-957`: heading grep, position-before-`Create or update docs/specs`, and 7 literal greps (`prompt corpus`, `JUSTIFIED_ADDITIONS`, `tests/skills/lib/prompt-diet-ledger.sh`, `.aai/**`, `classif`, `.aai/system/PROFILES.yaml`) plus an **exactly-2 bullet count** |
| R17 | 45 | Create or update `docs/specs/SPEC-<id>.md` from SPEC_TEMPLATE | keep-as-principle (one line) | `.aai/templates/SPEC_TEMPLATE.md` owns the shape | `hygiene-pack:924` uses `Create or update docs/specs` as the R16 position anchor — the literal must survive |
| R18 | 46-50 | Declaring Deltas (RFC-0011): ADDED/MODIFIED/REMOVED blocks against `REQ-<DOMAIN>[-NNN]` | move-to-script-gate | `SPEC_TEMPLATE.md` ships the (inert, commented) `## Deltas` example; `lib/docs-model.mjs parseDeltasSection` parses it; `spec-lint.mjs` emits the D2 violation codes | `test-aai-delta-stage2.sh:197-199` — `Deltas`, `canonical` (case-ins), `RFC-0011`. A pointer-form row must keep all three tokens |
| R19 | 51-52 | Requirement AC -> Spec-AC -> verification command(s) -> expected evidence | keep-as-principle | this mapping is the role's product | none |
| R20 | 53-58 | Test Plan table mechanics (stable TEST-xxx ids, type, target path, one-line description, status `pending`) | move-to-script-gate | the columns are owned by `SPEC_TEMPLATE.md`; `spec-lint.mjs` parses the table and emits `test-ac-malformed` / `test-ac-unknown` | none |
| R21 | 59 | "Every Spec-AC must have at least one TEST-xxx entry." | behavioral-probe-candidate | `spec-lint` checks TEST->AC (`test-ac-unknown`), **never AC->TEST**; the reverse direction has no detector. Probe: a fixture spec with an untested AC must not freeze | none |
| R22 | 60-64 | RED-proof obligation (an AC-gating test must be seen FAILING first, under any strategy) | keep-as-principle | `tdd-evidence-check.mjs` enforces RED_CLASS on **tdd lanes only**; `loop`/`hybrid` rides have no detector | none |
| R23 | 65-76 | Seam analysis + one crossing INTEGRATION test per seam; untestable seam -> residual risk | keep-as-principle *(probe candidate)* | audit `needs-gate-first` #8: VALIDATION 5f enforces it in prose only | none |
| R24 | 77-82 | RESPECT A PRE-RECORDED INTAKE CHOICE (`source: intake` -> keep, never silently override) | keep-as-principle | written from reported user friction; nothing mechanical protects a recorded choice | `test-aai-implementation-mode.sh:86-87` — `RESPECT A PRE-RECORDED INTAKE CHOICE`, `source: intake` |
| R25 | 83-91 | Strategy rubric (`tdd` / `loop` / `hybrid` / `direct` / `untested` selection criteria) | keep-as-principle | judgment; `state.mjs set-strategy` validates the **enum only** | none |
| R26 | 92 | "Never leave `undecided` on a frozen spec." | move-to-script-gate | `spec-lint.mjs` already computes `frozen-without-strategy` | none |
| R27 | 93-95 | Write AC/Verification demands from the strategy's row in SPEC_TEMPLATE `### Evidence by strategy` | move-to-script-gate | the table lives in `SPEC_TEMPLATE.md`; `spec-lint.mjs --strategy` emits `strategy-evidence-mismatch` at freeze | `test-aai-spec-lint.sh:1018` — regex `evidence.*strategy\|strategy.*evidence` must still match somewhere in the file |
| R28 | 96-105 | Worktree isolation rubric (`required`/`recommended`/`optional`/`not_needed` + rationale, create nothing) | keep-as-principle | **now the single home** — `SKILL_WORKTREE.prompt.md:282-284` was rewritten by the CHANGE-0114 diet to point *here*. `state.mjs set-worktree` validates the enum only | none (but SKILL_WORKTREE names this step in prose) |
| R29 | 106-111 | Review plan (`code_review.required` true/false criteria; inline scope = explicit paths or diff range) | keep-as-principle | `state.mjs set-code-review` validates the enum only | none |
| R30 | 112-115 | Freeze ONLY via `spec-freeze.mjs`; freeze is ATOMIC; either half alone is `half-frozen` | move-to-script-gate | `spec-freeze.mjs` **refuses** rather than half-freeze; `spec-lint.mjs` emits `half-frozen` after the fact. A one-line pointer suffices | `hygiene-pack:692` greps the literal `Set SPEC-FROZEN: true` as the *ordering anchor* for R36 (freeze < emit < STATE) |
| R31 | 115-117 | Freeze preconditions: all Spec-AC measurable **and** every Spec-AC has a TEST-xxx **and** strategy not `undecided` | behavioral-probe-candidate | verified: `spec-freeze.mjs` checks frontmatter parse + status transition only. It enforces **none** of these three | none |
| R32 | 118-122 | Constitution check -> `## Constitution deviations` (`None.` or article+deviation+justification); unjustifiable deviation blocks freeze | keep-as-principle | no script reads `docs/CONSTITUTION.md` | `test-aai-constitution.sh:126-133` — `Constitution deviations` and `docs/CONSTITUTION.md` must sit **inside** the `10) … 11)` slice |
| R33 | 123-130 | Ceremony level: declare `ceremony_level: 0..3`; meaning lives ONLY in the WORKFLOW table; L0/L1 need a `Ceremony justification: ` line; absent = implicit L2 | keep-as-principle | value validated by `spec-lint` `ceremony-level-invalid`; the protected-surface list is config (`docs/ai/docs-audit.yaml protected_paths_l3`); the *meaning* is `.aai/workflow/WORKFLOW.md` | `test-aai-ceremony-levels.sh:659-662` and `:1128-1147` — positive: `ceremony_level`, `Ceremony justification:`, `.aai/workflow/WORKFLOW.md`, `L0/L1`; **negative**: no `typo/docs-only`, no `MANDATORY when the scope touches`, and no 4-level `\|…L0…L1…L2…L3…\|` table row anywhere in the file |
| R34 | 131-134 | Dispatch lane: the level SELECTS 0/1 lightweight vs 2/3 full; at L0/L1 every TEST-xxx row must name a directly executable command | keep-as-principle | `orchestration-dispatch.mjs` reads the level but does not police the Test Plan's executability | `test-aai-ceremony-levels.sh:1141-1145` — `dispatch lane` (case-ins), `L0/L1` |
| R35 | 135-136 | Post-freeze advisory: run `spec-lint.mjs --path <spec>`, report-only, degrade if absent | keep-as-principle | already the correct pointer shape | `test-aai-spec-lint.sh:397-414` — `spec-lint` on **≤2 lines**, an adjacent `absent` degrade clause, an adjacent `advisor` marker |
| R36 | 137-142 | Emit the work-item brief from BRIEF_TEMPLATE; skip while SPEC-FROZEN false; PATHS not pasted bodies; leave Return Record blank; briefs are gitignored | keep-as-principle | `.aai/templates/BRIEF_TEMPLATE.md` owns the structure and (byte-identically) the subagent return skeleton | `hygiene-pack:687-700` — `docs/ai/briefs/`, `.aai/templates/BRIEF_TEMPLATE.md`, `SPEC-FROZEN is false`, `gitignored runtime artifact`, **plus** the ordering assertion freeze < emit < STATE; and `^11) Emit the work-item brief` is pinned four times (ceremony ×2, constitution, spec-lint) |
| R37 | 143-153 | STATE writes: the five `state.mjs` subcommands with their flags | move-to-script-gate | this block *is already* the unhobbled shape — a tool interface, not a rule. `state.mjs` owns enum validation, atomic write and `updated_at_utc` | `^12) Update docs/ai/STATE.yaml` pinned four times (ceremony ×2, constitution, spec-lint); `Update docs/ai/STATE.yaml — PRIMARY PATH` (`hygiene-pack:694`) is the R36 ordering anchor; `loop\|tdd\|hybrid\|direct\|untested` (`implementation-mode:88`) |
| R38 | 147-151 | Skip `set-strategy` when respecting an intake choice; lift `Implementation mode (user choice):` from the intake's `## Notes`; `untested` needs a non-empty rationale | keep-as-principle | behavioral rule about *whose* choice wins, not a CLI fact | none |
| R39 | 154-155 | "Each command validates its enums, writes atomically, and bumps the real `updated_at_utc` itself…" | delete-redundant | derivable from `state.mjs` usage output and `lib/state-engine.mjs`'s header | none |
| R40 | 156 | FALLBACK -> `.aai/STATE_FALLBACK.md` | keep-as-principle | already the mandated pointer form | `test-aai-prompt-diet.sh:243-262` TEST-006/007 — the `state.mjs is absent` occurrence must be the **≤2-line pointer form naming `.aai/STATE_FALLBACK.md`** |
| R41 | 158-159 | STRICT RULES — "Do not use unverifiable language without numeric thresholds." | delete-redundant | folds into R06's measurability principle without loss (the "numeric thresholds" clause moves into that sentence) | none |
| R42 | 161-171 | FINAL OUTPUT REQUIRED — 11 bullets restating what steps 4-11 already produce | move-to-script-gate | the handoff shape is owned by `.aai/SUBAGENT_CONTRACT.md` and mechanically checked by `check-role-output.mjs`; only the role-specific items (freeze status, worktree decision-required flag, brief path) need naming | none |
| R43 | 173-174 | METRICS pointer -> `.aai/ROLE_COMMON.md (role: Planning)` | keep-as-principle | correct pointer shape already | `test-aai-token-capture.sh:172-183` — `ROLE_COMMON.md` **and** `(role: Planning)` on the **same line**, plus a **negative** grep forbidding the `Subagent-mode carve-out` body |
| R44 | 176 | "BEGIN NOW." | keep-as-principle | — | none |

## File-level pins (not dispositioned rows — they gate any rewrite)

| pin | what it constrains |
|---|---|
| `tests/skills/test-aai-prompt-diet.sh` TEST-010/012/013 + `tests/skills/lib/prompt-diet-ledger.sh` | the **corpus byte budget**: `0 <= headroom <= 2048`. Two ledger entries already cite this file by name (`566 planning-companion-obligations`, `216 CHANGE-0122-strategy-scaled-evidence`, and CHANGE-0120's `+237 B` freeze routing). Any real shrink of PLANNING must append a NEGATIVE `JUSTIFIED_ADDITIONS` entry and move the TEST-012 literal by the same delta — this is R16's own rule applied to the rewrite |
| `test-aai-ceremony-levels.sh` (×2), `test-aai-constitution.sh`, `test-aai-spec-lint.sh` | **step-numbering guard**: `^11) Emit the work-item brief`, `^12) Update docs/ai/STATE.yaml`, and **no `^13) `**. A rewrite that drops the numbered-step spine breaks four suites at once |
| `test-aai-layer-profiles.sh:256`, `.aai/system/PROFILES.yaml:52`, `aai-doctor.mjs:123`, `test-aai-doctor.sh:94` | the file must **exist** at `.aai/PLANNING.prompt.md` in a core install |
| `tests/skills/suite-map.yaml` (9 entries) | change-trigger map only — not an assertion, not a pin |

## Already applied by CHANGE-0114 (audit rows now closed)

The Phase-0 audit's PLANNING rows for the RATIONALIZATION TABLE (1,570 B, zero
pins) and the multi-line STRICT RULES block (204 B) are **gone from the current
file**; the surviving single STRICT RULES line is R41. The SKILL_WORKTREE
duplicate of the recommendation levels is also gone, which *raises* R28's value:
step 8 is now the only home for that rubric in the corpus.

## What this means for V2

- The 10 `move-to-script-gate` rows are where V2 buys its bytes: they become
  table rows pointing at `spec-lint.mjs`, `spec-freeze.mjs`, `state.mjs`,
  `check-state.mjs`, `orchestration-dispatch.mjs`, `SPEC_TEMPLATE.md`,
  `BRIEF_TEMPLATE.md` and `SUBAGENT_CONTRACT.md`.
- The 5 `behavioral-probe-candidate` rows (R04, R05, R09, R21, R31) are H3's
  probe suite. Note that **three of the five sit at the freeze boundary** (R21,
  R31 and R05) — `spec-freeze.mjs` deliberately checks only atomicity, so the
  preconditions are exactly the place where a shorter prompt could silently
  regress. These probes must exist before V2 could ever ship.
- The 5 `delete-redundant` rows are pin-free and total roughly 1.1 KB.
- The 24 `keep-as-principle` rows are the irreducible core, and 11 of them carry
  pins. V2 keeps every one of them; what changes is that they are stated as four
  principles plus one worked example rather than as 12 numbered steps.

## Caveats

- Pin resolution covers `grep`/`assert_*` assertions with quoted literals or
  resolvable regexes in `tests/skills/*.sh`. Dynamically-built patterns and any
  `*.Tests.ps1` assertions are not covered.
- "Move-to-script-gate" here means *the script already exists and already
  computes the check* — no row proposes building a new gate as a precondition for
  its own deletion, except where the row explicitly says `probe-candidate`.
- Nothing in this document was applied to `.aai/PLANNING.prompt.md`. V0 remains
  the shipped prompt.
