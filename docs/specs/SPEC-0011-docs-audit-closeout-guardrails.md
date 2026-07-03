---
id: SPEC-0011
type: spec
status: done
links:
  change: CHANGE-0005
  rfc: RFC-0002
  requirement: null
  pr: []
  commits: []
---

# SPEC-0011 — Docs-audit closeout guardrails: prevent "git-closed but AAI-unreconciled" specs (CHANGE-0005)

SPEC-FROZEN: true

## Links
- Change request (WHAT/WHY): docs/issues/CHANGE-0005-docs-audit-closeout-guardrails.md
- Docs hygiene / drift authority (engine enhanced here): docs/rfc/RFC-0002-docs-hygiene-and-drift-audit.md
- AC-tracking authority (per-dev STATE, EVENTS as shared log): docs/rfc/RFC-0001-ac-tracking-and-multi-dev-state.md
- Sibling engine specs (same modules): docs/specs/SPEC-0001-docs-hygiene-and-drift-audit.md,
  docs/specs/SPEC-0003-docs-audit-closeout-candidate.md,
  docs/specs/SPEC-0010-docs-index-and-state-tooling-robustness.md
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (this doc)
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Scope

Add preventive closeout guardrails to the RFC-0002 docs-audit engine and the
loop/wrap-up/flush closeout path so a spec cannot reach `status: done` at the git
level while its AAI doc closeout (Acceptance Criteria Status table + telemetry) is
left unreconciled. Five guardrails from CHANGE-0005:

- G1 — close-time completeness gate (`docs-audit.mjs --gate <DOC-ID>`, exit 1 on fail).
- G2 — telemetry-at-close invariant (`work_item_closed` event type + telemetry-at-close check).
- G3 — Review-By truthfulness cross-check → new verdict `review-claim-unbacked`.
- G4 — near-miss AC-table detection → explicit WARNING instead of silent skip/mis-report.
- G5 — opt-in pre-commit hard block extending the `AAI:INDEX-AUTOGEN` hook.

WHAT/WHY lives in CHANGE-0005; this doc defines HOW. The RFC-0002 invariant is
preserved throughout: the engine REPORTS, the operator DECIDES — no doc is ever
auto-edited.

## Problem summaries (verified against live code)

### G1 — `done` is a frontmatter flip with no code-enforced completeness precondition
Nothing in CODE gates the `status: draft/implementing → done` transition on AC-table
completeness. `docs-audit-core.mjs:357-380` detects the AFTER-THE-FACT drift
(`probable-false-done` when `ac.hasGate && (nonTerminal || doneNoEvidence)`, or
`probable-partial` when a spec has no AC table), but only in the full report — it
is not a close-time predicate a caller can consult. There is no `--gate` mode in
`docs-audit.mjs:27-40` (`parseArgs` knows `--check/--quick/--no-event/--strict/
--strict-types/--list/--path` only). The one existing analogue is the AGENT-enforced
AC-status gate in `.aai/VALIDATION.prompt.md` (lines 55-92) and its step 8b
DONE-TRANSITION ASSERTION (lines 128-141) — prose the validating agent is asked to
follow, NOT a code predicate. The `aai-loop` skill does not itself flip a spec to
`done`; it dispatches Validation (via ORCHESTRATION), which performs the flip at
step 8b. `aai-flush` emits `doc_lifecycle` at `.aai/METRICS_FLUSH.prompt.md` step 7
(line 64); `aai-wrap-up` (`.aai/SKILL_WRAP_UP.prompt.md`) runs no docs-audit and
emits no telemetry today.

### G2 — no telemetry-at-close event exists
`append-event.mjs:26` defines a CLOSED event set
`{ac_status, ac_evidence, defer_extended, doc_lifecycle, docs_audit}`. There is NO
`work_item_closed` (nor `code_review_completed`) event type; a `--event
work_item_closed` invocation exits 2 ("unknown event type"). CHANGE-0005 evidence:
10 of 12 drifted specs had no closeout telemetry. Nothing asserts a `status: done`
spec has a corresponding close event.

### G3 — a Review-By label is accepted on validity, never on truthfulness
`docs-model.mjs:92-136` `parseReviewBy` accepts `code-review` as a valid
`REVIEW_BY_LABELS` token; `docs-audit-core.mjs:307-308` only flags a Review-By that
is *malformed* (`kind === 'invalid'`). A row with `Review-By: code-review` passes
even when no code-review artifact/event exists. CHANGE-0005 evidence: 12 rows
claimed `code-review`, only 2 had any review artifact.

### G4 — near-miss AC tables are silently mis-handled
`parseAcTable` (`docs-model.mjs:238-264`) keys "this is an AC table" on an exactly
`## Acceptance Criteria Status` heading (`:243`) AND a header cell exactly equal to
`Review-By` (`:250` `hasGate`). `rowHasEvidence` (`docs-audit-core.mjs:189-192`)
reads the cell keyed EXACTLY `Evidence`. Consequences observed in CHANGE-0005:
(a) a column headed `Evidence (TEST)` becomes key `"Evidence (TEST)"`, so
`row['Evidence']` is undefined → "no evidence" → a false `probable-false-done` for
a row that DID cite evidence (silent mis-report); (b) an AC-looking table under a
non-canonical heading, or a `Review-By`-like column, yields `hasGate:false` → the
doc is silently treated as having no gate table. No signal distinguishes "genuinely
no AC table" from "malformed near-miss AC table".

### G5 — the pre-commit hook has no close gate
`install-pre-commit-hook.sh:60-96` (and the `.ps1` peer) installs the
`AAI:INDEX-AUTOGEN` hook, which only regenerates and stages `docs/INDEX.md`
(+ un-stages the git-ignored companions). It does not inspect a `status: done` flip
nor block a commit that closes a spec whose AC table is unreconciled.

## Design decisions (load-bearing — read before implementing)

### G1 — `--gate <DOC-ID>` is a pure structural predicate
Add `gateDoc(root, docId)` to `docs-audit-core.mjs` returning `{ ok, reasons[],
found }`. It resolves `docId` against the scanned docs (frontmatter `id` or
filename id), parses the AC table via the shared `parseAcTable` + `normalizeAcStatus`,
and FAILS (`ok:false`) when ANY of:
- the doc has no canonical `## Acceptance Criteria Status` gate table (`hasGate:false`
  or zero rows) — reason "missing AC Status table";
- any AC row's normalized base status is non-terminal (`!TERMINAL_AC.has(base)`) —
  reason names the offending Spec-AC(s);
- any `done` row has empty Evidence (reuse `rowHasEvidence`) — reason names the row(s);
- any `Review-By` token is schema-invalid (`parseReviewBy().kind === 'invalid'`) —
  reason names the row(s).
`docs-audit.mjs` adds `--gate <DOC-ID>`: prints the reasons, exits **1** on
`ok:false`, **0** on `ok:true`, **2** when the id resolves to no scanned doc. The
predicate is OFFLINE (no git/event probing) so it is deterministic and testable.
It reuses `parseAcTable`/`normalizeAcStatus`/`TERMINAL_AC`/`rowHasEvidence`/
`parseReviewBy` — no parser fork. `--gate` is scope-limited to the one doc and never
emits a `docs_audit` event.

Rationale for keeping G1 structural-only (no truthfulness): truthfulness is G3, a
separate verdict with a separate AC. Keeping the gate offline+structural makes it a
fast, deterministic close-time predicate the hook and skills can call cheaply.

### G2 — add `work_item_closed` (+ `code_review_completed`) event types; assert at close
Extend `append-event.mjs` `EVENT_TYPES` with:
- `work_item_closed` — required `--ref <DOC-ID>`; payload `{ validation, code_review }`
  (free-text/status tokens, e.g. `validation: pass`, `code_review: pass|waived|none`);
- `code_review_completed` — required `--ref <DOC-ID>`; payload `{ verdict }`
  (e.g. `pass|fail`) + optional `--report <path>`.
Add a report-only telemetry-at-close check in `docs-audit-core.mjs`: a doc committed
`status: done` with NO `work_item_closed` event whose `ref` equals the id (or
rolls up `id/<suffix>`, mirroring the existing `ac_evidence` roll-up at
`docs-audit-core.mjs:374-375`) is surfaced (verdict/annotation `missing-close-telemetry`,
report-only — does NOT feed `hardFail`). The closeout skills EMIT `ac_status` per
row + `work_item_closed` on a successful close.

### G3 — `review-claim-unbacked` verdict (report-only, cross-checked against events+artifacts)
In `docs-audit-core.mjs`, after AC parsing, for any row whose `parseReviewBy(...).label`
(case-insensitive) is `code-review`, require corroboration:
- a `code_review_completed` event, OR a `work_item_closed` event with a
  `code_review` value matching `/^pass/i`, whose `ref` equals or rolls up to the
  doc id; OR
- a `docs/ai/{reviews,reports}/` artifact whose filename contains the doc id
  (`*<ID>*`).
Absent all corroboration → verdict `review-claim-unbacked` (drift report, report-only;
NOT `hardFail`, consistent with the RFC-0002 report-not-block posture). The same
mechanism generalizes to any label asserting a process step, but this spec ships the
`code-review` case as the concrete, tested instance. Positive control: a backed claim
yields NO verdict.

Residual risk (recorded): G3 depends on artifact/event naming conventions
(`docs/ai/{reviews,reports}/*<ID>*`, `code_review_completed` / `work_item_closed`);
a convention mismatch could yield a false `review-claim-unbacked`. Mitigated by (a)
report-only (never blocks), (b) triple corroboration source (two event shapes + an
artifact glob), (c) an explicit positive-control test.

### G4 — near-miss detection: explicit WARNING, never a silent skip/mis-report
Add `detectNearMissAcTable(content)` to `docs-model.mjs` returning `{ warnings[] }`,
fired when the doc LOOKS like it carries an AC table but is not canonical:
- a heading matching `/acceptance criteria/i` that is NOT exactly
  `## Acceptance Criteria Status`; OR
- inside the AC section, a column header matching `/^evidence\b.+/i` (e.g.
  `Evidence (TEST)`) rather than exactly `Evidence`; OR
- a `Review-By`-like column header (e.g. `Review By`, `ReviewBy`, `Review-by (...)`)
  that is not exactly `Review-By`.
Warning text: "malformed AC table — treated as missing/no-evidence, verdict may be
inaccurate", naming the offending heading/column. Surfaced in BOTH `docs-audit.mjs`
(its own WARNING section) AND `generate-docs-index.mjs` (appended to the
`docs/INDEX.violations.md` companion, mirroring `acStatusViolations`). Detection is
narrow by construction so the canonical `## Acceptance Criteria Status` + exact
`Evidence` / `Review-By` shape never trips it (negative control).

### G5 — opt-in pre-commit hard block, config-gated, `.sh`/`.ps1` parity
Extend the installed `AAI:INDEX-AUTOGEN` hook body (both `install-pre-commit-hook.sh`
and `.ps1`) with a close-gate block: for every staged spec whose diff ADDS a
`status: done` frontmatter line, run `node .aai/scripts/docs-audit.mjs --gate <ID>`;
if it exits non-zero AND `docs/ai/docs-audit.yaml` sets `close_gate: enforce`, abort
the commit (exit 1) printing the specific reasons; otherwise print a non-blocking
warning and continue (report-only default — absent config or `close_gate: report-only`
never blocks). The block is guarded by the same `AAI:INDEX-AUTOGEN` marker and keeps
`.sh`/`.ps1` behavior at parity (CHANGE-0005 vendoring constraint).

### Config — one new key, default report-only
`loadConfig` (`docs-audit-core.mjs:43-84`) gains `close_gate` (values `enforce` |
`report-only`; default `report-only` when the key or the whole file is absent). Only
the CALLERS (G5 hook, G1/G2 skill wiring) consult `close_gate` to decide block-vs-warn;
`--gate` itself always returns the raw predicate exit code. This keeps mid-migration
downstream repos in report-only by default (CHANGE-0005 constraint) while the
predicate stays deterministic. The engine never edits any doc (RFC-0002 invariant).

### Shared
- Reuse existing harnesses. Engine tests go in `tests/skills/test-aai-docs-audit.sh`,
  registered in `main()` BEFORE `test_index_continue_on_error` (the `set -e` suite's
  known pre-existing last-failing test). append-event tests may reuse the same
  harness or `tests/skills/test-framework.sh`.
- RED-proof obligation (all AC-gating tests, any strategy): every gating test must be
  observed FAILING without the change. Self-eval-trap negatives (G4 canonical shape
  must NOT warn; G3 backed claim must NOT flag; `--gate` reconciled doc must exit 0)
  embed a positive control in the same fixture so RED is genuine.
- Do not regress SPEC-0001/0003/0006/0007/0010 or the existing docs-audit / index /
  check-state suites.

## Implementation strategy
- Strategy: hybrid
- Rationale: TDD (RED-GREEN-REFACTOR) for the deterministic, higher-risk engine
  surfaces — the `--gate` structural predicate (a close-time gate other tooling
  depends on), the G3 `review-claim-unbacked` cross-check (truthfulness logic with a
  self-eval-trap positive control), the G4 near-miss detector (a parser change
  consumed by two engines), the `append-event` event-set extension (a closed-set
  contract), and the G5 hook block (a commit-blocking path). Loop for the low-risk
  wiring verified by `grep`: the aai-loop/aai-wrap-up/aai-flush closeout prose (run
  `--gate`, emit `work_item_closed`), the `.sh`/`.ps1` installer parity prose, and
  the config-key documentation. Matches the sibling SPEC-0010 hybrid posture.
- RED-proof obligation applies to every AC-gating test regardless of strategy.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: the scope touches three or more independent modules
  simultaneously — `docs-model.mjs`, `docs-audit-core.mjs`, `docs-audit.mjs`,
  `generate-docs-index.mjs`, `append-event.mjs`, both hook installers
  (`install-pre-commit-hook.sh` + `.ps1`), `docs/ai/docs-audit.yaml`, three skill
  prompts (SKILL_LOOP / SKILL_WRAP_UP / SKILL_FLUSH), and the test suite — and it is
  PR-bound. It is also the very tooling that gates this repo (docs audit + the
  pre-commit path), so isolation is prudent. It is NOT `required`: the changes are
  additive/behavioral (new CLI mode, new verdict, new event type, opt-in hook block),
  there is no schema migration, and the RFC-0002 read-only invariant is preserved.
  Matches the SPEC-0010 `recommended` precedent for the same module cluster.
- User decision: undecided (Planning recommends; Implementation Preparation asks the
  user and records the decision — inline-on-dedicated-branch is an acceptable override
  consistent with SPEC-0010 precedent).
- Base ref: main
- Worktree branch/path: TBD if the user chooses worktree
- Inline review scope (if inline is chosen):
  - `.aai/scripts/lib/docs-model.mjs`
  - `.aai/scripts/lib/docs-audit-core.mjs`
  - `.aai/scripts/docs-audit.mjs`
  - `.aai/scripts/generate-docs-index.mjs`
  - `.aai/scripts/append-event.mjs`
  - `.aai/scripts/install-pre-commit-hook.sh` (+ `.ps1` parity)
  - `docs/ai/docs-audit.yaml`
  - `.aai/VALIDATION.prompt.md` (step 8b), `.aai/METRICS_FLUSH.prompt.md`,
    `.aai/SKILL_WRAP_UP.prompt.md`
  - `tests/skills/test-aai-docs-audit.sh`
  - `docs/specs/SPEC-0011-docs-audit-closeout-guardrails.md`

## Acceptance Criteria Mapping

### G1 — close-time completeness gate

- Maps to: CHANGE-0005 AC-001
  - Spec-AC-01: `node .aai/scripts/docs-audit.mjs --gate <DOC-ID>` exits **1** for a
    `status: done` spec whose AC table is missing, OR has any non-terminal row, OR
    has any `done` row with empty Evidence, OR has any schema-invalid `Review-By`
    token; the printed reasons name the specific failing condition/row. RED-proof:
    pre-fix there is no `--gate` mode (unknown arg / no gate exit path).
  - Verification: TEST-001, TEST-002.

- Maps to: CHANGE-0005 AC-001 (pass case)
  - Spec-AC-02: `--gate <DOC-ID>` exits **0** for a fully-reconciled `status: done`
    spec (canonical AC table present; every row terminal; every `done` row has
    Evidence; every `Review-By` valid), and exits **2** when the id resolves to no
    scanned doc. RED-proof: a mutation that drops one Evidence cell flips the exit to 1.
  - Verification: TEST-003.

### G4 — near-miss AC-table detection

- Maps to: CHANGE-0005 AC-002
  - Spec-AC-03: A near-miss AC table with an `Evidence (TEST)` column (rather than
    `Evidence`) produces a distinct near-miss WARNING from `docs-audit.mjs` — NOT a
    silent `probable-false-done` mis-report for a row that cites evidence. RED-proof:
    pre-fix the same fixture emits `probable-false-done` with no near-miss warning.
  - Verification: TEST-004.

- Maps to: CHANGE-0005 AC-002 (non-canonical heading / Review-By-like column, both surfaces)
  - Spec-AC-04: An AC-looking table under a non-canonical heading (heading matches
    `/acceptance criteria/i` but ≠ `## Acceptance Criteria Status`) or with a
    `Review-By`-like column emits a near-miss WARNING in BOTH `docs-audit.mjs` output
    AND the `generate-docs-index.mjs` `docs/INDEX.violations.md` companion — not a
    silent no-table classification. Negative control: the canonical
    `## Acceptance Criteria Status` + exact `Evidence`/`Review-By` shape emits NO
    near-miss warning.
  - Verification: TEST-005.

### G3 — Review-By truthfulness cross-check

- Maps to: CHANGE-0005 AC-003
  - Spec-AC-05: An AC row with `Review-By: code-review` and NO corroborating
    `code_review_completed` / `work_item_closed(code_review: pass*)` event AND no
    `docs/ai/{reviews,reports}/*<ID>*` artifact yields verdict `review-claim-unbacked`
    in the docs-audit drift report. RED-proof: pre-fix the row passes silently (only a
    malformed Review-By is flagged today).
  - Verification: TEST-006.

- Maps to: CHANGE-0005 AC-003 (positive control — backed claim clears)
  - Spec-AC-06: The SAME doc with a corroborating review event OR a
    `docs/ai/reviews/*<ID>*` artifact present yields NO `review-claim-unbacked`
    verdict (proves the check is a real cross-check, not an accept/reject-all).
  - Verification: TEST-007.

### G2 — telemetry-at-close invariant

- Maps to: CHANGE-0005 AC-004 (event type + telemetry-at-close check)
  - Spec-AC-07: `append-event.mjs` accepts `--event work_item_closed --ref <DOC-ID>`
    (payload `validation` + `code_review`) and `--event code_review_completed --ref
    <DOC-ID>` (payload `verdict`), rejecting unknown events with exit 2; and
    `docs-audit.mjs` surfaces a report-only `missing-close-telemetry` signal for a
    `status: done` doc that has NO `work_item_closed` event referencing it, which
    clears once the event is present. RED-proof: pre-fix `--event work_item_closed`
    exits 2 ("unknown event type") and no close-telemetry check exists.
  - Verification: TEST-008, TEST-009.

- Maps to: CHANGE-0005 AC-004 (closeout wiring — the real done-flip + telemetry sites)
  - Spec-AC-08: The closeout path is wired to the gate at its ACTUAL code-flip site:
    `.aai/VALIDATION.prompt.md` step 8b (the DONE-TRANSITION ASSERTION, lines 128-141)
    instructs running `docs-audit.mjs --gate <DOC-ID>` before writing `status: done`
    and emitting `ac_status` per row + `work_item_closed` on success — refusing the
    flip when `close_gate: enforce`, or emitting a blocking-class warning when
    report-only. `.aai/METRICS_FLUSH.prompt.md` (aai-flush, step 7, ~line 64) also
    emits `work_item_closed` alongside its `doc_lifecycle`, and `.aai/SKILL_WRAP_UP.prompt.md`
    gains a closeout step that runs `--gate` and surfaces the result. Verified by
    `grep` across those three prompts for the `--gate` invocation, the
    `work_item_closed` emission, and the enforce/report-only branch text.
  - Verification: TEST-010.

### G5 + config — enforcement gating (opt-in) and the read-only invariant

- Maps to: CHANGE-0005 AC-005 (config gating; absent → report-only)
  - Spec-AC-09: Enforcement respects `docs/ai/docs-audit.yaml`: with `close_gate:
    enforce` a failing gate blocks the caller (hook/skill) path; with the key or the
    whole config absent, or `close_gate: report-only`, a failing gate warns but never
    blocks. `loadConfig` exposes `close_gate` with a `report-only` default. RED-proof:
    pre-fix there is no `close_gate` key (`loadConfig` returns no such field).
  - Verification: TEST-011.

- Maps to: CHANGE-0005 AC-005 + Scope G5 (pre-commit hard block, `.sh`/`.ps1` parity)
  - Spec-AC-10: The installed pre-commit hook aborts a commit that adds a
    `status: done` frontmatter line to a spec failing the G1 gate WHEN `close_gate:
    enforce`, printing the specific reasons; in report-only default it warns and lets
    the commit proceed; a reconciled done-flip commits clean. `install-pre-commit-hook.sh`
    and `install-pre-commit-hook.ps1` embed the gate-block at parity, guarded by the
    `AAI:INDEX-AUTOGEN` marker. RED-proof: pre-fix the hook has no close-gate block
    (an unreconciled done-flip commits without objection).
  - Verification: TEST-012, TEST-013.

- Maps to: CHANGE-0005 AC-005 (RFC-0002 invariant: audit REPORTS, operator DECIDES)
  - Spec-AC-11: Running `--gate`, the G3/G4 audit, and the closeout path against a
    fixture mutates NO doc file (byte/hash unchanged) — the engine never auto-edits a
    doc. Verified by hashing every fixture doc before/after the new code paths run.
  - Verification: TEST-014.

### Shared — test coverage & no regression

- Maps to: CHANGE-0005 AC-006
  - Spec-AC-12: The new G1/G2/G3/G4/G5 behavior is covered by tests in the docs-audit
    engine test suite (gate pass/fail, near-miss warning, review-claim cross-check,
    telemetry-at-close, hook block); `bash tests/skills/test-aai-docs-audit.sh` passes
    except the known pre-existing `test_index_continue_on_error`; on the real repo
    `node .aai/scripts/docs-audit.mjs --check --strict --no-event` exits 0 CLEAN and
    `node .aai/scripts/generate-docs-index.mjs` stays idempotent (two runs
    byte-identical modulo `Generated:`); SPEC-0006/0007/0010 suites still pass.
  - Verification: TEST-015 (regression anchor; TEST-001..014 contribute coverage).

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | G1: `--gate <ID>` exits 1 on missing table / non-terminal row / done-row empty Evidence / invalid Review-By, naming the failing condition; Review-By validity honors `config.review_by_methods` | done | TEST-001 + TEST-002 + TEST-016 PASS in tests/skills/test-aai-docs-audit.sh; impl `gateDoc()` .aai/scripts/lib/docs-audit-core.mjs:591 (threads `config.review_by_methods` into `parseReviewBy`, BP-001) + `--gate` .aai/scripts/docs-audit.mjs; green log docs/ai/tdd/green-spec0011-final-20260703T000811Z.log | — | AC-001; TDD; BP-001 remediation |
| Spec-AC-02 | G1: `--gate <ID>` exits 0 on a fully-reconciled done spec; exits 2 on unresolved id | done | TEST-003 PASS (exit 0 reconciled / 2 unknown / 1 after Evidence-drop mutation) in tests/skills/test-aai-docs-audit.sh; impl `gateDoc()` docs-audit-core.mjs:591; green log docs/ai/tdd/green-spec0011-final-20260703T000811Z.log | — | AC-001; TDD; pass case |
| Spec-AC-03 | G4: `Evidence (TEST)` near-miss column emits a distinct WARNING, not a silent probable-false-done mis-report | done | TEST-004 PASS in tests/skills/test-aai-docs-audit.sh; impl `detectNearMissAcTable()` .aai/scripts/lib/docs-model.mjs:280 surfaced in docs-audit.mjs; green log docs/ai/tdd/green-spec0011-final-20260703T000811Z.log | — | AC-002; TDD |
| Spec-AC-04 | G4: non-canonical heading / Review-By-like column emits near-miss WARNING in BOTH docs-audit + INDEX.violations companion; canonical shape does not warn | done | TEST-005 PASS (near-miss in BOTH docs-audit + INDEX.violations; canonical shape in neither) in tests/skills/test-aai-docs-audit.sh; impl docs-model.mjs:280 + generate-docs-index.mjs writeViolationsReport; green log docs/ai/tdd/green-spec0011-final-20260703T000811Z.log | — | AC-002; SEAM-1; negative control |
| Spec-AC-05 | G3: `Review-By: code-review` with no review event/artifact → verdict `review-claim-unbacked` | done | TEST-006 PASS in tests/skills/test-aai-docs-audit.sh; impl `reviewClaimBacked()` .aai/scripts/lib/docs-audit-core.mjs:149 + G3 loop docs-audit-core.mjs:362-373; green log docs/ai/tdd/green-spec0011-final-20260703T000811Z.log | — | AC-003; TDD |
| Spec-AC-06 | G3: backed claim (event or artifact) → NO `review-claim-unbacked` verdict (positive control) | done | TEST-007 PASS (real `code_review_completed` event producer → real audit consumer clears the verdict) in tests/skills/test-aai-docs-audit.sh; TEST-019 PASS (F4: boundary-aware artifact match — SPEC-0011 artifact does NOT corroborate SPEC-001; exact-id does) impl `reviewArtifactExists()` docs-audit-core.mjs:135; impl docs-audit-core.mjs:149,367; green log docs/ai/tdd/green-spec0011-final-20260703T000811Z.log | — | AC-003; SEAM-2; F4 remediation |
| Spec-AC-07 | G2: append-event accepts `work_item_closed` + `code_review_completed` (exit 2 on unknown); docs-audit surfaces `missing-close-telemetry` (report-only) and it clears when the event exists | done | TEST-008 + TEST-009 PASS in tests/skills/test-aai-docs-audit.sh; TEST-018 PASS (F3: `work_item_closed` requires validation + code_review; empty/partial payload → exit 2) impl append-event.mjs:100; impl EVENT_TYPES .aai/scripts/append-event.mjs:26,100,108 + missing-close-telemetry docs-audit-core.mjs:379; green log docs/ai/tdd/green-spec0011-final-20260703T000811Z.log | — | AC-004; TDD; F3 remediation |
| Spec-AC-08 | G2: closeout wired at real flip site (VALIDATION step 8b) + flush + wrap-up — runs `--gate` before done-flip, emits ac_status + work_item_closed, refuses (enforce) / blocking-warns (report-only) on fail | done | TEST-010 PASS (grep asserts --gate + work_item_closed + enforce/report-only branch in all three prompts) in tests/skills/test-aai-docs-audit.sh; impl .aai/VALIDATION.prompt.md step 8b + .aai/METRICS_FLUSH.prompt.md + .aai/SKILL_WRAP_UP.prompt.md; green log docs/ai/tdd/green-spec0011-final-20260703T000811Z.log | — | AC-004; loop (grep) |
| Spec-AC-09 | Config: `close_gate: enforce` blocks, absent / `report-only` warns; loadConfig exposes `close_gate` default report-only | done | TEST-011 PASS (loadConfig exposes close_gate default report-only; enforce/report-only parsed) in tests/skills/test-aai-docs-audit.sh; impl `loadConfig` .aai/scripts/lib/docs-audit-core.mjs + docs/ai/docs-audit.yaml; green log docs/ai/tdd/green-spec0011-final-20260703T000811Z.log | — | AC-005; TDD |
| Spec-AC-10 | G5: pre-commit hook aborts a failing done-flip when enforce, warns in report-only, commits clean when reconciled; .sh/.ps1 parity | done | TEST-012 (git-fixture: enforce aborts / report-only warns / reconciled clean) + TEST-013 (`.sh` AND `.ps1` embed the close-gate block at parity) PASS in tests/skills/test-aai-docs-audit.sh; TEST-017 PASS (F2: hook gates the STAGED blob via `git show :<path>` → `--gate-file`, not the worktree) impl `gateFile()` docs-audit-core.mjs + `--gate-file` docs-audit.mjs + install-pre-commit-hook.sh/.ps1; impl .aai/scripts/install-pre-commit-hook.sh + .ps1; green log docs/ai/tdd/green-spec0011-final-20260703T000811Z.log | — | AC-005; SEAM-3; TDD + grep parity; F2 remediation |
| Spec-AC-11 | RFC-0002 invariant: --gate + G3/G4 + closeout mutate NO doc file (byte/hash unchanged) | done | TEST-014 PASS (every fixture doc byte-identical before/after --gate + G3/G4 audit) in tests/skills/test-aai-docs-audit.sh; engine never writes a doc (read-only fs probes only); green log docs/ai/tdd/green-spec0011-final-20260703T000811Z.log | — | AC-005; read-only proof |
| Spec-AC-12 | Coverage + no regression: engine suite green (except known test_index_continue_on_error); real-repo docs-audit --check --strict exit 0 CLEAN; index idempotent; SPEC-0006/0007/0010 intact | done | TEST-015 PASS (real-repo audit CLEAN, no false near-miss, INDEX idempotent) in tests/skills/test-aai-docs-audit.sh; suite 68 PASS / 1 pre-existing FAIL (test_index_continue_on_error, confirmed pre-existing on main); green log docs/ai/tdd/green-spec0011-final-20260703T000811Z.log | — | AC-006; regression gate |

Status values: planned | implementing | done | deferred | blocked | rejected.
Gate (per .aai/VALIDATION.prompt.md): any planned/implementing row blocks PASS;
any done row needs non-empty Evidence; deferred/blocked need a future Review-By.

## Implementation plan
- Components/modules affected:
  - `.aai/scripts/lib/docs-model.mjs`:
    - Add `export function detectNearMissAcTable(content)` → `{ warnings: [{kind, detail}] }`
      (heading `/acceptance criteria/i` ≠ canonical; `/^evidence\b.+/i` column;
      `Review-By`-like column). Narrow so the canonical shape never trips.
  - `.aai/scripts/lib/docs-audit-core.mjs`:
    - Add `close_gate` to `loadConfig` (default `report-only`).
    - Add `export function gateDoc(root, docId)` → `{ found, ok, reasons }`, reusing
      the scan + `parseAcTable`/`normalizeAcStatus`/`TERMINAL_AC`/`rowHasEvidence`/
      `parseReviewBy`. Offline (no git/event probing).
    - In `runAudit`, after AC parsing: (G3) for `Review-By: code-review` rows with no
      corroborating event/artifact, set verdict `review-claim-unbacked` (report-only);
      (G2) for `status: done` docs with no `work_item_closed` event referencing the id
      (roll-up like `ac_evidence`), record a report-only `missing-close-telemetry`
      signal; (G4) attach `detectNearMissAcTable` warnings to the doc record. None feed
      `hardFail`.
    - Add a `docs/ai/{reviews,reports}/*<ID>*` artifact probe (read-only fs glob).
  - `.aai/scripts/docs-audit.mjs`:
    - `parseArgs`: add `--gate <DOC-ID>`. When set, call `gateDoc`, print reasons,
      exit 1/0/2; do NOT emit a `docs_audit` event in gate mode.
    - Render G4 near-miss warnings + G3 `review-claim-unbacked` + G2
      `missing-close-telemetry` in the report (report-only sections).
  - `.aai/scripts/generate-docs-index.mjs`:
    - Append G4 near-miss warnings to `writeViolationsReport` (new section in
      `docs/INDEX.violations.md`), mirroring `acStatusViolations`. Doc stays indexed.
  - `.aai/scripts/append-event.mjs`:
    - Add `work_item_closed` and `code_review_completed` to `EVENT_TYPES` with their
      payload validation (mirroring the existing `switch (args.event)` arms).
  - `.aai/scripts/install-pre-commit-hook.sh` (+ `.ps1` parity):
    - Add a close-gate block to the `HOOK` heredoc: for each staged spec adding a
      `status: done` line, run `docs-audit.mjs --gate <ID>`; abort (exit 1) with
      reasons when `close_gate: enforce`, else warn. Same marker + `.ps1` parity.
  - `docs/ai/docs-audit.yaml`: document/add the `close_gate` key (default report-only).
  - `.aai/VALIDATION.prompt.md` (step 8b, the real done-flip site),
    `.aai/METRICS_FLUSH.prompt.md` (aai-flush step 7), `.aai/SKILL_WRAP_UP.prompt.md`:
    add closeout guidance (run `--gate`, emit `work_item_closed`, enforce/report-only
    branch). `.aai/SKILL_LOOP.prompt.md` need not flip done itself; if touched, only a
    pointer to the Validation gate.
  - `tests/skills/test-aai-docs-audit.sh`: add TEST-001..015, registered BEFORE
    `test_index_continue_on_error`.
- Data flows: `--gate` reads on-disk frontmatter + AC table only (offline predicate).
  G3/G4/G2 signals derive from AC tables + `EVENTS.jsonl` + a `docs/ai/{reviews,
  reports}` fs probe, surfaced report-only. The hook/skills consult `close_gate` to
  choose block-vs-warn. No path writes to any doc.
- Edge cases:
  - `--gate` on a doc with no frontmatter id but a filename id → resolve by filename id.
  - G4: canonical heading with an exact `Evidence` column and a qualified status cell
    (`done (pre-existing)`) → NOT a near-miss (already handled by `normalizeAcStatus`).
  - G3: a `Review-By: code-review` on a non-`done` row still cross-checked (claim is a
    claim regardless of row status); a `label:date` combo whose label is `code-review`
    is also cross-checked.
  - G2 roll-up: `work_item_closed --ref PARENT/<suffix>` satisfies the parent id, and a
    sibling id (e.g. `SPEC-0110` vs `SPEC-011`) must NOT cross-match (reuse the
    existing `id + '/'` boundary discipline).
  - G5: a commit touching a spec that is ALREADY `status: done` (no add of the line)
    must not re-trigger the block; only a diff that ADDS the `status: done` line does.

## Seam analysis
- SEAM-1 (`docs-model.detectNearMissAcTable` → consumed by BOTH `docs-audit.mjs` AND
  `generate-docs-index.mjs`): a shared near-miss detector backing two engines. Risk:
  the two surfaces diverge, or the canonical shape false-positives. Crossed
  end-to-end by TEST-005 (a non-canonical near-miss warns in BOTH the real audit
  output AND the real `docs/INDEX.violations.md`; the canonical shape warns in
  neither).
- SEAM-2 (`append-event` `work_item_closed`/`code_review_completed` → read by
  `docs-audit-core` G3 cross-check): an event produced by the closeout path and read
  by the audit. Risk: the audit does not recognize the exact event/ref shape the
  skills emit. Crossed by TEST-007 (emit a real `code_review_completed` /
  `work_item_closed` event via `append-event.mjs`, then assert the real audit drops
  `review-claim-unbacked` for that doc) — producer on one side, real consumer on the
  other, not two mocked halves.
- SEAM-3 (pre-commit hook → `docs-audit.mjs --gate` + `close_gate` config): the hook
  bakes the gate into the commit path. Risk: the hook mis-detects the done-flip, or
  ignores the config. Crossed by TEST-012 in a real git fixture (stage an unreconciled
  done-flip → hook aborts under enforce, warns under report-only; a reconciled flip
  commits clean).
- SEAM-4 (closeout prompts ↔ gate + telemetry): the real done-flip prompt
  (`VALIDATION.prompt.md` step 8b) plus the flush/wrap-up prompts must call the real
  gate and emit the real event. Verified by TEST-010 (grep those prompts for the
  `--gate` call, the `work_item_closed` emission, and the enforce/report-only branch).
- Residual risk (recorded): G3 artifact/event naming-convention dependency — see the
  G3 design decision. Report-only + triple corroboration source + positive-control
  test mitigate it.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                 | Description | Status |
|----------|------------|-------------|--------------------------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh  | Done spec with a MISSING `## Acceptance Criteria Status` table → `docs-audit.mjs --gate <ID>` exit 1, reason names "missing AC Status table". RED: no `--gate` mode pre-fix. | green |
| TEST-002 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh  | Three done-spec fixtures — one non-terminal AC row; one `done` row with empty Evidence; one schema-invalid `Review-By` (e.g. `driver`) — each `--gate` exit 1 with a reason naming the offending Spec-AC. | green |
| TEST-003 | Spec-AC-02 | integration | tests/skills/test-aai-docs-audit.sh  | Fully-reconciled done spec (canonical table; all rows terminal; done rows have Evidence; valid Review-By) → `--gate` exit 0; unknown id → exit 2. RED: dropping one Evidence cell flips exit to 1. | green |
| TEST-004 | Spec-AC-03 | integration | tests/skills/test-aai-docs-audit.sh  | Done spec with an `Evidence (TEST)` column citing evidence → `docs-audit.mjs` emits the near-miss WARNING, NOT a silent `probable-false-done` for that row. RED: pre-fix emits probable-false-done, no warning. | green |
| TEST-005 | Spec-AC-04 | integration | tests/skills/test-aai-docs-audit.sh  | Non-canonical AC heading / `Review-By`-like column → near-miss WARNING in BOTH `docs-audit.mjs` output AND `docs/INDEX.violations.md`. Negative control: canonical shape warns in neither. | green |
| TEST-006 | Spec-AC-05 | integration | tests/skills/test-aai-docs-audit.sh  | Done spec, `Review-By: code-review`, no review event and no `docs/ai/{reviews,reports}/*<ID>*` artifact → verdict `review-claim-unbacked`. RED: pre-fix the row passes silently. | green |
| TEST-007 | Spec-AC-06 | integration | tests/skills/test-aai-docs-audit.sh  | Same fixture + a real `code_review_completed` / `work_item_closed(code_review:pass)` event (via append-event) OR a `docs/ai/reviews/*<ID>*` artifact → NO `review-claim-unbacked` verdict (positive control). | green |
| TEST-008 | Spec-AC-07 | unit        | tests/skills/test-aai-docs-audit.sh  | `append-event.mjs --event work_item_closed --ref <ID> ...` and `--event code_review_completed --ref <ID> ...` append valid JSONL lines; `--event bogus` exits 2. RED: pre-fix `work_item_closed` exits 2 "unknown event type". | green |
| TEST-009 | Spec-AC-07 | integration | tests/skills/test-aai-docs-audit.sh  | Done spec with no `work_item_closed` event referencing it → `docs-audit.mjs` reports `missing-close-telemetry` (report-only, no hardFail); after emitting the event the signal clears; sibling-id must not cross-match. | green |
| TEST-010 | Spec-AC-08 | unit        | tests/skills/test-aai-docs-audit.sh  | `grep` asserts VALIDATION.prompt.md step 8b + METRICS_FLUSH.prompt.md + SKILL_WRAP_UP.prompt.md closeout runs `docs-audit.mjs --gate <ID>` before done-flip, emits `work_item_closed`, and branches on enforce vs report-only. | green |
| TEST-011 | Spec-AC-09 | integration | tests/skills/test-aai-docs-audit.sh  | With `close_gate: enforce` a failing gate blocks the caller path; with the key/config absent or `report-only` it warns not blocks. `loadConfig` exposes `close_gate` default `report-only`. RED: no `close_gate` key pre-fix. | green |
| TEST-012 | Spec-AC-10 | integration | tests/skills/test-aai-docs-audit.sh  | Git fixture with the installed hook: stage a spec flipping to `status: done` that fails the gate → commit aborts (exit 1, reasons) under `close_gate: enforce`; warns + commits under report-only; a reconciled flip commits clean. RED: pre-fix hook has no close-gate block. | green |
| TEST-013 | Spec-AC-10 | unit        | tests/skills/test-aai-docs-audit.sh  | `grep` asserts `install-pre-commit-hook.sh` AND `.ps1` both embed the close-gate block (gate call + enforce/report-only branch) under the `AAI:INDEX-AUTOGEN` marker (parity). | green |
| TEST-014 | Spec-AC-11 | integration | tests/skills/test-aai-docs-audit.sh  | Hash every fixture doc, run `--gate` + the G3/G4 audit + the closeout path, re-hash → all doc files byte-identical (engine never auto-edits a doc; RFC-0002 invariant). | green |
| TEST-015 | Spec-AC-12 | integration | tests/skills/test-aai-docs-audit.sh  | Regression: docs-audit suite green except known `test_index_continue_on_error`; real-repo `docs-audit --check --strict --no-event` exit 0 CLEAN; `generate-docs-index.mjs` idempotent (two runs byte-identical modulo `Generated:`); SPEC-0006/0007/0010 assertions intact. | green |
| TEST-016 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh  | BP-001: done spec whose only Review-By is a combo token (`sast:<date>`) valid ONLY under `review_by_methods: [sast]` → `--gate` exit 0 WITH the config; control WITHOUT the config → exit 1 naming the Spec-AC + Review-By. RED: pre-fix `gateDoc()` dropped `extraMethods` → configured token mis-gated as invalid (exit 1). | green |
| TEST-017 | Spec-AC-10 | integration | tests/skills/test-aai-docs-audit.sh  | F2 remediation: the pre-commit hook gates the STAGED blob (`git show :<path>` → temp → `--gate-file`), not the worktree — a staged-unreconciled `status: done` aborts under enforce even when the worktree adds Evidence. RED: pre-fix the hook gated the worktree file and let the bad staged spec commit. | green |
| TEST-018 | Spec-AC-07 | unit        | tests/skills/test-aai-docs-audit.sh  | F3 remediation: `--event work_item_closed` requires BOTH `--validation` and `--code-review`; an empty/partial payload exits 2, a complete payload exits 0 and appends the event. RED: pre-fix an empty `work_item_closed` payload exited 0. | green |
| TEST-019 | Spec-AC-06 | integration | tests/skills/test-aai-docs-audit.sh  | F4 remediation: a review artifact named for SPEC-0011 must NOT corroborate a claim for SPEC-001 (digit-boundary match); the exact-id artifact still corroborates. RED: pre-fix `name.includes(id)` false-matched and wrongly cleared `review-claim-unbacked`. | green |

Test status values: pending → red → green. Every Spec-AC has ≥1 TEST-xxx. Test IDs
are stable; do not renumber after freeze.

TDD vs loop per AC: Spec-AC-01/02 (gate), 03/04 (near-miss), 05/06 (G3), 07 (event
set + telemetry check), 09 (config), 10 (hook block), 11 (read-only) are TDD
(RED-proof mandatory). Spec-AC-08 (skill wiring) and the parity half of Spec-AC-10
(TEST-013) are loop (grep-verified). Spec-AC-12 is a regression gate (loop-run of the
suites).

## Verification
- `node .aai/scripts/docs-audit.mjs --gate <DOC-ID>` — exit 1 on an unreconciled
  `done` spec (missing / non-terminal / empty-evidence / invalid-Review-By), exit 0
  when all hold, exit 2 on an unresolved id.
- Fixture with an `Evidence (TEST)` column → `docs-audit.mjs` emits the G4 near-miss
  WARNING (no silent probable-false-done).
- Fixture with `Review-By: code-review` and no review event/artifact → verdict
  `review-claim-unbacked`; add the event/artifact → verdict clears.
- `node .aai/scripts/append-event.mjs --event work_item_closed --ref <ID>
  --validation pass --code-review pass` appends a JSONL line; `--event bogus` exits 2.
- Git fixture: an unreconciled `status: done` flip commit aborts under
  `close_gate: enforce`, warns under report-only, and commits clean when reconciled.
- `bash tests/skills/test-aai-docs-audit.sh` — TEST-001..015 green; pre-existing pass
  set preserved (only `test_index_continue_on_error` known-fails).
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` on the real repo
  exits 0 CLEAN; `node .aai/scripts/generate-docs-index.mjs` idempotent.
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal with evidence.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id (CHANGE-0005 / SPEC-0011)
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY (CHANGE-0005 owns WHAT/WHY).
This document does not define workflow.
Use plain Markdown headings and body text. Do not add emoji or decorative icons
unless there is a strong domain-specific reason.
