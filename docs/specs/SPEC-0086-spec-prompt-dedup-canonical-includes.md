---
id: spec-prompt-dedup-canonical-includes
type: spec
number: 86
status: done
ceremony_level: 2
links:
  requirement: prompt-dedup-canonical-includes
  rfc: null
  pr:
    - 159
  commits:
    - bd4142d7bdbb316f4fd329b7d45698be435c7356
---

# Implementation Spec — Prompt dedup: canonical sources for ceremony rules, AC gate, and role boilerplate

SPEC-FROZEN: true

## Links
- Requirement/intake: docs/issues/CHANGE-0059-prompt-dedup-canonical-includes.md
- Technology contract: docs/TECHNOLOGY.md
- Workflow canon (pointer target, OUT of scope): .aai/workflow/WORKFLOW.md "Ceremony levels"
- Gate script (behavior OUT of scope): .aai/scripts/docs-audit.mjs `--gate` /
  .aai/scripts/lib/docs-audit-core.mjs `gateContent`
- Learned rules: docs/knowledge/LEARNED.md (prompt-diet-floor-credit-drift; EVENTS restore)

## Frontmatter status values
- draft: spec being written
- implementing: spec frozen, work in flight
- done: all Spec-AC terminal; validation PASS recorded

## Scope summary

Replace re-narrated duplications in the prompt corpus with thin pointers to a
single canonical source, in three places, WITHOUT any behavior change:

1. **D5 subagent-mode metrics/append-run boilerplate** — currently duplicated
   VERBATIM in FIVE role prompts (planning found a 5th copy the intake did not
   list): `.aai/PLANNING.prompt.md`, `.aai/IMPLEMENTATION.prompt.md`,
   `.aai/VALIDATION.prompt.md`, `.aai/REMEDIATION.prompt.md`, and
   `.aai/SKILL_TDD.prompt.md`. Extract the shared body into ONE new file
   `.aai/ROLE_COMMON.md` (mirroring the existing `.aai/INTAKE_COMMON.md`
   shared-block pattern); each role prompt keeps a ≤2-line pointer naming its
   role.
2. **Ceremony-level rule restatement in PLANNING step 10** — trim the paraphrase
   of the four level meanings and the protected-surface MANDATORY-L3 mechanic
   (both re-narrate the WORKFLOW.md table) down to a WORKFLOW.md pointer, while
   KEEPING the role-specific residue Planning alone owns (declaring
   `ceremony_level`, the `Ceremony justification:` line, the dispatch-lane/L0-L1
   consequence).
3. **VALIDATION AC STATUS GATE** — delegate the mechanical checks the gate script
   PROVABLY computes to a mandatory `docs-audit.mjs --gate <ref>` invocation, and
   RETAIN as prose ONLY the rules the script does NOT compute (see the critical
   finding below).

Corpus byte DELTA is strictly NEGATIVE. Companion obligations both fire: a NEW
`.aai/**` file (PROFILES.yaml classification) and the prompt-diet floor
accounting (the shrink must be reconciled so headroom stays in [0, HEADROOM_CAP]).

## CRITICAL FINDING — the AC-gate script does NOT compute the temporal rules

The intake premise ("`docs-audit.mjs --gate` computes deterministically the
terminal-status check, empty-Evidence check, ISO Review-By date math, AND the
14-day anti-cheat window") is only PARTIALLY correct. Source read of
`.aai/scripts/lib/docs-audit-core.mjs` `gateContent` (lines 1343-1410) and
`parseReviewBy` (`.aai/scripts/lib/docs-model.mjs`) establishes:

| VALIDATION AC STATUS GATE rule | Computed by `--gate`? | Evidence |
|--------------------------------|-----------------------|----------|
| Rule 1 — no silent partials (every AC row terminal) | YES | `gateContent` `checkRows`: pushes `<AC> is non-terminal` |
| Rule 2 — no unsubstantiated done (Evidence non-empty) | YES | `gateContent`: `<AC> is done but Evidence is empty` |
| Rule 4 (format clause) — Review-By must be a valid ISO/label | YES | `gateContent`: `schema-invalid Review-By` via `parseReviewBy` `kind==='invalid'` |
| Rule 3 — overdue review, GLOBAL repo-wide interrupt (past Review-By on any deferred/blocked row in ANY spec) | **NO** | `gateDoc` resolves and gates exactly ONE doc; `parseReviewBy` performs zero temporal comparison |
| Rule 4 (anti-cheat clause) — Review-By must be ≥14 days in the FUTURE | **NO** | `gateContent` only branches on `kind==='invalid'`; no future-window arithmetic anywhere |

Consequence: blindly deleting all "14-day" / "Review-By comparison" prose (the
literal wording of intake AC-004/AC-002) would REGRESS enforcement in the
unattended pipeline — exactly the divergence the change exists to prevent, and
the exact "over-pruning judgment residue" risk the intake's own Constraints
section flags. Because "Behavior changes to `docs-audit.mjs --gate`" are
explicitly OUT of scope, Rules 3 and 4-anti-cheat CANNOT be moved to the script;
they MUST remain as VALIDATION prose. This spec's Spec-AC-02 is scoped
accordingly (delegate Rules 1/2/4-format; retain Rules 3/4-anti-cheat).

## Acceptance Criteria Mapping

- Maps to intake AC-001 → **Spec-AC-01** (ceremony single-source)
  - Spec-AC-01: PLANNING step 10 carries NO paraphrase of the four ceremony
    level meanings and NO restatement of the protected-surface MANDATORY-L3
    mechanic; it points at `.aai/workflow/WORKFLOW.md` "Ceremony levels" as the
    single source, while STILL containing the tokens `ceremony_level`,
    `Ceremony justification:`, `dispatch lane`, and `L0/L1` (the role-specific
    residue that existing pins TEST-008/TEST-015 require). No ceremony markdown
    TABLE ROW (`| ... | L0 | L1 | L2 | L3 |`) appears in PLANNING or VALIDATION;
    the table rows exist only in WORKFLOW.md.
  - Verification: greps in TEST-001/TEST-002; `bash tests/skills/test-aai-ceremony-levels.sh` exit 0.

- Maps to intake AC-002 (CORRECTED per Critical Finding) → **Spec-AC-02**
  - Spec-AC-02: VALIDATION's AC STATUS GATE step names a mandatory
    `docs-audit.mjs --gate <ref>` invocation and honors its exit code for the
    mechanical checks the script computes (terminal-status, empty-Evidence,
    Review-By schema-validity); the prose for those three is reduced to the
    invocation contract. The rules the script does NOT compute — the repo-wide
    overdue-Review-By interrupt (Rule 3) and the ≥14-day-future anti-cheat
    window (Rule 4-anti-cheat) — REMAIN as explicit prose. VALIDATION still
    contains the tokens `14` (as the 14-day window) and the overdue/global
    interrupt wording, by design.
  - Verification: greps in TEST-003; characterization guard TEST-004 proves the
    script does not enforce the temporal rules; `bash tests/skills/test-aai-docs-audit.sh` exit 0.

- Maps to intake AC-003 → **Spec-AC-03** (D5 single-source)
  - Spec-AC-03: the multi-line D5 subagent-mode metrics/append-run BODY (the
    `Capture started_utc` / `PRIMARY PATH … append-run` / `FALLBACK` /
    `Do NOT estimate` block) exists in exactly ONE file, `.aai/ROLE_COMMON.md`.
    Each of the five role prompts (PLANNING, IMPLEMENTATION, VALIDATION,
    REMEDIATION, SKILL_TDD) carries a ≤2-line pointer naming `.aai/ROLE_COMMON.md`
    and its own `--role` value, and each shrinks in byte count vs HEAD.
  - Verification: greps in TEST-005; SEAM round-trip TEST-006.

- Maps to intake AC-004 → **Spec-AC-04** (byte floor + ledger + classification)
  - Spec-AC-04: `cat .aai/*.prompt.md | wc -c` is strictly lower than HEAD
    (before/after recorded). `bash tests/skills/test-aai-prompt-diet.sh` TEST-010
    passes: strict audit clean AND headroom ∈ [0, HEADROOM_CAP]. This requires
    (a) `.aai/ROLE_COMMON.md` added to TEST-010's `extra` accounting (relocation
    neutralization, exactly like INTAKE_COMMON.md / STATE_FALLBACK.md), and
    (b) a reconciling entry in `tests/skills/lib/prompt-diet-ledger.sh`
    `JUSTIFIED_ADDITIONS` (a NEGATIVE-byte "reclaimed" entry sized so headroom
    lands in [0, HEADROOM_CAP]). `.aai/ROLE_COMMON.md` is classified in
    `.aai/system/PROFILES.yaml` (`core`) so layer-profiles stays 100%.
  - Verification: TEST-007 (floor), TEST-008 (before/after bytes), TEST-009 (SEAM: layer-profiles).

- Maps to intake AC-005 → **Spec-AC-05** (full suite)
  - Spec-AC-05: `bash tests/skills/test-framework.sh` passes with no pinned-prose
    stanza left asserting removed text.
  - Verification: TEST-010.

## Constitution deviations

None.

- Art. 1 (Evidence before claims): every Spec-AC has an executable grep/suite
  command; no claim without exit codes. Compliant.
- Art. 2 (Simplicity / YAGNI): pure dedup to an existing shared-block pattern;
  no new mechanism, no speculative feature. Compliant.
- Art. 3 (Portability): all edits are plain git-diffable Markdown/bash; the new
  file is a plain `.md`. Compliant.
- Art. 4 (Degrade and report): the D5 pointer preserves the existing
  `state.mjs is absent` FALLBACK clause (moved intact into ROLE_COMMON.md).
  Compliant.
- Art. 5 (Additive first / step numbering): PLANNING steps 11/12 and VALIDATION
  step 2 headings are preserved unrenumbered (pinned by spec-lint TEST-010);
  edits are in-place prose trims, not boundary breaks. Compliant.
- Art. 6 (Single-writer state): no STATE.yaml hand-edit; Planning skips
  state.mjs per the subagent single-writer dispatch constraint. Compliant.
- Art. 7 (Operator-only merge): no merge performed. Compliant.

## Implementation strategy
- Strategy: hybrid
- Rationale: the grep-contract test stanzas that gate the pinned prose
  (TEST-001/003/005/007/009) deserve RED-proof TDD — write/adjust the assertion,
  observe it RED against the current prompts, then edit prompts/ledger/PROFILES
  to GREEN — because the whole point of the change is to avoid gate DIVERGENCE
  and the prompt-diet floor has a cap-bite trap. The pure prose relocation and
  the PROFILES.yaml classification line are low-risk mechanical wiring (loop).

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: PR-bound (/aai-ship) scope touching ≥3 independent
  surfaces — five core role prompts, three test suites, the ledger lib, and
  PROFILES.yaml. Prose-only with no script-behavior change, so an explicit
  inline override with a clean review scope is a reasonable operator choice;
  the DECISION (not the isolation) is what the gate requires.
- User decision: undecided
- Base ref: main (branch feat/prompt-dedup-canonical-includes)
- Inline review scope (if inline selected): .aai/ROLE_COMMON.md,
  .aai/PLANNING.prompt.md, .aai/IMPLEMENTATION.prompt.md,
  .aai/VALIDATION.prompt.md, .aai/REMEDIATION.prompt.md, .aai/SKILL_TDD.prompt.md,
  .aai/system/PROFILES.yaml, tests/skills/test-aai-token-capture.sh,
  tests/skills/test-aai-prompt-diet.sh, tests/skills/lib/prompt-diet-ledger.sh,
  tests/skills/test-aai-ceremony-levels.sh (only if a stanza needs the new
  pointer form), docs/specs/SPEC-0086-spec-prompt-dedup-canonical-includes.md,
  docs/issues/CHANGE-0059-prompt-dedup-canonical-includes.md

## Acceptance Criteria Status

| Spec-AC    | Description                                                                 | Status  | Evidence | Review-By | Notes |
|------------|-----------------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | PLANNING ceremony restatement trimmed to a WORKFLOW.md pointer; residue kept | done | TEST-001/002 green; tdd: docs/ai/tdd/red-20260726T155331Z-test018-step10-pointer.log, green-20260726T155339Z-test018-step10-pointer.log; `bash tests/skills/test-aai-ceremony-levels.sh` exit 0 | — | — |
| Spec-AC-02 | VALIDATION AC gate delegates Rules 1/2/4-format to --gate; retains Rules 3/4-anti-cheat | done | TEST-003/004 green; tdd: docs/ai/tdd/red-20260726T155710Z-test-pdci-validation-gate-delegation.log; `bash tests/skills/test-aai-docs-audit.sh` exit 0 | — | — |
| Spec-AC-03 | D5 carve-out body single-sourced in .aai/ROLE_COMMON.md; 5 prompts point to it | done | TEST-005/006 green; tdd: docs/ai/tdd/red-20260726T155459Z-test003-role-common-pointer.log; `bash tests/skills/test-aai-token-capture.sh` exit 0 | — | — |
| Spec-AC-04 | corpus bytes strictly lower; prompt-diet floor green; PROFILES classifies new file | done | TEST-007/008/009 green; tdd: docs/ai/tdd/report-20260726T163608Z-spec-ac04-byte-floor-reconciliation.log; before=349697 after=345010 (strictly lower); `bash tests/skills/test-aai-prompt-diet.sh` + `bash tests/skills/test-aai-layer-profiles.sh` exit 0 | — | — |
| Spec-AC-05 | full skill test framework green; no stale pinned-prose stanza                | done | Implementation dispatch is barred from running the full `tests/skills/test-framework.sh` (reserved for the orchestrator's Validator); all 6 directly-required suites (`test-aai-prompt-diet.sh`, `test-aai-token-capture.sh`, `test-aai-ceremony-levels.sh`, `test-aai-docs-audit.sh`, `test-aai-verify-gate.sh`, `test-aai-layer-profiles.sh`) + spec-lint + `docs-audit.mjs --check --strict --no-event` all exit 0 in this pass; full-framework confirmation landed: 75/75 suites green on the 2026-08-13 all-green skill-suite run 31661804469 (main CI after PR #249), with this spec's edits long merged — and no stale pinned-prose stanza reported by the prompt-diet suite in any run since | — | reviewed 2026-08-13 at the Review-By checkpoint; the deferral existed only because Implementation dispatch is barred from running the full framework — the orchestrator-side run now exists |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan

Components/files affected:
- NEW `.aai/ROLE_COMMON.md` — canonical shared block. Contains: (a) the single
  literal "Subagent-mode carve-out (D5): …SUBAGENT_PROTOCOL.md…" sentence, and
  (b) the append-run PROCEDURE body (`started_utc` capture, PRIMARY PATH
  `state.mjs append-run --ref <REF-ID> --role <ThisRole> …`, the
  `state.mjs is absent` FALLBACK, the "Do NOT estimate" line). Parameterize the
  role via a `<ThisRole>` placeholder the pointer resolves.
- `.aai/PLANNING.prompt.md`:
  - Step 10: replace the four-level meaning paraphrase + protected-surface
    MANDATORY-L3 restatement with a WORKFLOW.md-table pointer; KEEP
    `ceremony_level`, `Ceremony justification:`, `dispatch lane`, `L0/L1`.
  - METRICS footer: replace the ~14-line block with a pointer to
    `.aai/ROLE_COMMON.md` with `--role Planning`.
- `.aai/IMPLEMENTATION.prompt.md`, `.aai/VALIDATION.prompt.md`,
  `.aai/REMEDIATION.prompt.md`, `.aai/SKILL_TDD.prompt.md`: METRICS footer →
  pointer with the respective `--role` (`Implementation`, `Validation`,
  `Remediation`, `"TDD Implementation"`).
- `.aai/VALIDATION.prompt.md` AC STATUS GATE section: reduce Rules 1/2 and Rule
  4-format to "run `docs-audit.mjs --gate <ref>`; a non-zero exit blocks PASS
  with the printed reasons"; RETAIN the Detection/opt-in preamble, Rule 3
  (repo-wide overdue interrupt) and Rule 4-anti-cheat (≥14-day-future) verbatim
  in intent. Do NOT touch step 8b (close-work-item.mjs / close-policy /
  --gate/enforce/report-only — pinned by other suites), step-2 heading, or the
  spec-lint advisory line.
- `.aai/system/PROFILES.yaml`: add `.aai/ROLE_COMMON.md` under `core`
  (alphabetical position after `.aai/REMEDIATION.prompt.md` /
  before `.aai/SKILL_BOOTSTRAP.prompt.md`, matching existing ordering).
- `tests/skills/test-aai-token-capture.sh` TEST-003: retarget the five-prompt
  loop from "grep the inline carve-out" to "grep the ROLE_COMMON.md pointer in
  each prompt" + one grep proving the canonical body lives in ROLE_COMMON.md.
- `tests/skills/test-aai-prompt-diet.sh` TEST-010: add `.aai/ROLE_COMMON.md` to
  the `extra` accounting.
- `tests/skills/lib/prompt-diet-ledger.sh`: append a NEGATIVE `JUSTIFIED_ADDITIONS`
  reconciliation entry (bytes measured after edits) so headroom ∈ [0, HEADROOM_CAP].
  If a suite forbids a negative entry, fall back to retiring/reducing a specific
  historical entry with a reconciliation note (residual RR-2).

Edge cases / data flows:
- The literal "Subagent-mode carve-out" phrase must end up in exactly ONE file
  (ROLE_COMMON.md) for Spec-AC-03 "exactly one file"; therefore the pointer
  lines must NOT re-use that phrase, and token-capture TEST-003 MUST be updated
  (it is a required test edit, enumerated above) — it cannot stay byte-identical.
- Byte sizing of the negative ledger entry and the `extra` line is
  MEASUREMENT-driven at implementation time; the spec fixes the mechanism, not
  the constants.

## Seam analysis

- SEAM-1 (D5 relocation → append-run behavior): the relocated carve-out must
  still yield a working `state.mjs append-run`. Crossed by TEST-006 (reuse
  token-capture TEST-005's append-run→STATE→flush→METRICS round-trip) — a real
  produce-then-assert, not a mock.
- SEAM-2 (corpus bytes ↔ ledger accounting): the shrink must reconcile against
  the floor+cap. Crossed by TEST-007 running the real TEST-010 over the live
  corpus + real ledger.
- SEAM-3 (new file ↔ profile manifest): a new `.aai/**` file must be classified
  or layer-profiles TEST-001 fails against the LIVE tree. Crossed by TEST-009.
- SEAM-4 (VALIDATION prose ↔ gate script coverage): no automated test executes
  the VALIDATION prompt as an agent, so the correctness of the delegation
  (that --gate truly covers Rules 1/2/4-format and truly does NOT cover
  Rules 3/4-anti-cheat) is proven by source read + characterization guard
  TEST-004, not an end-to-end agent run. Recorded as residual RR-1.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                              | Description                                                                                                   | Status  |
|----------|------------|-------------|---------------------------------------------------|--------------------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-ceremony-levels.sh (new stanza) | PLANNING step 10: no four-level meaning paraphrase / no protected-surface MANDATORY-L3 restatement; a WORKFLOW.md pointer present; `ceremony_level`+`Ceremony justification:`+`dispatch lane`+`L0/L1` retained; no `\| … \| L0 \| L1 \| L2 \| L3 \|` table row in PLANNING/VALIDATION | green |
| TEST-002 | Spec-AC-01 | integration | tests/skills/test-aai-ceremony-levels.sh          | Existing TEST-008 + TEST-015 (step-10 tokens, steps 11/12 survive, no step 13, CEREMONY LANE block) stay green | green |
| TEST-003 | Spec-AC-02 | unit        | tests/skills/test-aai-docs-audit.sh (new stanza)  | VALIDATION AC gate step names `docs-audit.mjs --gate` for the mechanical checks AND retains the repo-wide overdue (Rule 3) + `14`-day-future anti-cheat (Rule 4) prose | green |
| TEST-004 | Spec-AC-02 | integration | tests/skills/test-aai-docs-audit.sh (new stanza)  | Characterization guard: a fixture spec with a PAST and a <14-day-future Review-By on a deferred row still PASSES `docs-audit.mjs --gate` (proves Rules 3/4-anti-cheat are non-delegable → prose retention justified) | green |
| TEST-005 | Spec-AC-03 | unit        | tests/skills/test-aai-token-capture.sh (TEST-003 retarget) | D5 carve-out BODY exists only in `.aai/ROLE_COMMON.md`; each of the 5 role prompts carries a pointer naming ROLE_COMMON.md with its `--role` | green |
| TEST-006 | Spec-AC-03 | integration | tests/skills/test-aai-token-capture.sh (TEST-005) | SEAM-1: append-run note round-trips STATE→flush→METRICS with the relocated carve-out (existing test stays green) | green |
| TEST-007 | Spec-AC-04 | integration | tests/skills/test-aai-prompt-diet.sh (TEST-010)   | SEAM-2: strict audit clean AND headroom ∈ [0, HEADROOM_CAP] with ROLE_COMMON.md in `extra` + reconciling ledger entry | green |
| TEST-008 | Spec-AC-04 | unit        | (evidence log) docs/ai/tdd/ or report             | Record `cat .aai/*.prompt.md \| wc -c` before (HEAD) vs after; after strictly lower | green |
| TEST-009 | Spec-AC-04 | integration | tests/skills/test-aai-layer-profiles.sh (TEST-001)| SEAM-3: PROFILES.yaml classifies `.aai/ROLE_COMMON.md`; 100% classification vs live tree | green |
| TEST-010 | Spec-AC-05 | e2e         | tests/skills/test-framework.sh                    | Full skill suite green; no stale pinned-prose stanza | pending |

RED-proof obligations:
- TEST-001, TEST-003, TEST-005, TEST-007, TEST-009 each gate a Spec-AC and MUST
  be observed FAILING against the current tree before their GREEN counts
  (current: PLANNING still enumerates levels; VALIDATION AC gate does not name
  --gate; carve-out body is in 5 files and ROLE_COMMON.md does not exist;
  headroom would exceed the cap; ROLE_COMMON.md is unclassified). This holds for
  the loop-assigned prose edits too.
- TEST-004 is a CHARACTERIZATION guard of an UNCHANGED, out-of-scope script
  (`--gate`): it is GREEN today by construction and cannot RED without editing
  the script (which is out of scope). It is a regression fence, not an
  AC-gating RED test; the AC-gating RED for Spec-AC-02 is TEST-003.

## Verification
- `bash tests/skills/test-aai-ceremony-levels.sh`
- `bash tests/skills/test-aai-docs-audit.sh`
- `bash tests/skills/test-aai-token-capture.sh`
- `bash tests/skills/test-aai-prompt-diet.sh`
- `bash tests/skills/test-aai-layer-profiles.sh`
- `bash tests/skills/test-framework.sh` (full)
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` (exit 0)
- Recorded before/after `cat .aai/*.prompt.md | wc -c`.
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal with Evidence.

## Evidence contract
Per artifact, record: ref_id (spec-prompt-dedup-canonical-includes), Spec-AC and
TEST-xxx links, command or review scope, exit code / verdict, evidence path,
commit SHA or diff range.

## Residual risks
- RR-1 (SEAM-4): no automated test runs the VALIDATION prompt as an agent, so
  the delegation's semantic correctness rests on the Critical-Finding source
  read + characterization guard TEST-004 + the grep in TEST-003 (that the
  temporal prose is retained). Accepted.
- RR-2: if a prompt-diet suite fixture rejects a NEGATIVE `JUSTIFIED_ADDITIONS`
  entry, implementation falls back to reducing a specific historical ledger
  entry with a reconciliation note (history-preserving); either way headroom
  must land in [0, HEADROOM_CAP]. Low.

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow.
