---
id: spec-false-open-drift-heuristic
type: spec
number: 39
status: draft
ceremony_level: 2
links:
  change: false-open-drift-heuristic
  rfc: null
  pr: []
  commits: []
---

# SPEC — Docs-Audit `probable-false-open` Drift Heuristic

SPEC-FROZEN: true

## Links
- Change: false-open-drift-heuristic
  (docs/issues/CHANGE-0027-false-open-drift-heuristic.md)
- Mirrors: `probable-false-done` heuristic (docs/specs/SPEC-0001, RFC-0002)
- Boundary discipline inherited from: CHANGE-0002 D11 (sibling-ID roll-up)
- Technology contract: docs/TECHNOLOGY.md

## Problem
On 2026-07-17 the audit reported CLEAN while 49 delivered work items still sat
in `draft`/`implementing`/`accepted` — the close ceremony was skipped and no
heuristic caught it. The only false-open detector today is
`probable-stale-open`, which never fires for recently touched docs. The engine
needs the mirror of `probable-false-done`: a doc in an open status whose
delivery is already evidenced in git/events/its own AC table must be flagged
`probable-false-open` (report-only; the operator decides closure, RFC-0002).

## Ceremony level
`ceremony_level: 2` — edits the docs-audit drift engine and its digest, plus
tests and two doc surfaces. Not a small single-surface fix; none of the
touched paths is on `protected_paths_l3` (checked against
docs/ai/docs-audit.yaml on 2026-07-16: state engine, allocator, pre-commit
hosts, WORKFLOW.md, CONSTITUTION.md only). Full pipeline applies.

## Implementation strategy
- Strategy: tdd
- Rationale: new drift-verdict behavior on the governance engine with real
  heuristic-precision risk (sibling-ID cross-matches, intake-commit false
  positives, precedence vs `probable-stale-open`). Each signal and each
  negative control needs regression proof; mirrors the SPEC-0036 precedent
  for changes to this same file.
- RED-proof obligation: every AC-gating test stanza below must be observed
  FAILING against the unmodified engine before the change (save the RED log
  under docs/ai/tdd/). A stanza that never failed proves nothing.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: PR-bound feature work on the drift engine consumed by
  the pre-commit host and the index generator; isolation keeps main's audit
  output stable while fixtures/tests churn. Not `required` — no
  protected-path (L3) surface, no migration, fully additive engine change.
- User decision: undecided (Implementation Preparation must ask the operator
  before any implementation starts)
- Base ref: main (47d2ddf at planning time)
- Inline review scope (explicit paths, if inline is later selected):
  - .aai/scripts/lib/docs-audit-core.mjs
  - .aai/scripts/docs-audit.mjs
  - tests/skills/test-aai-docs-audit.sh
  - docs/USER_GUIDE.md
  - .claude/skills/aai-docs-audit/SKILL.md
  - docs/specs/SPEC-0039-spec-false-open-drift-heuristic.md (this spec)
  - docs/issues/CHANGE-0027-false-open-drift-heuristic.md (links backfill at close)

## Design decisions (frozen)

- D1 — Eligible statuses: exactly `draft`, `implementing`, `accepted`
  (a new `FALSE_OPEN_STATUSES` set; the existing `OPEN_STATUSES`
  {draft, implementing} that drives `probable-stale-open` is NOT changed).
  `proposed` is deliberately out of scope (intake names three statuses);
  recorded as a follow-up candidate in Notes.
- D2 — Delivery evidence is ANY of three signals:
  (a) a delivery commit whose SUBJECT (`%s`) mentions the doc id or its
      numbered file prefix (fileId) under the D4 boundary rules;
  (b) an `ac_evidence` event whose ref equals the id or rolls up
      (`ref === id || ref.startsWith(id + '/')` — same discipline as
      false-done, CHANGE-0002 D11);
  (c) a fully terminal canonical AC Status table: `ac.hasGate`, >= 1 row,
      every row's normalized base status in `TERMINAL_AC`, and every `done`
      row with non-empty Evidence (reuses `normalizeAcStatus` +
      `rowHasEvidence` — no parser fork).
- D3 — Delivery commit: subject matches
  `/^(feat|fix|chore)(\([^)]*\))?!?:/` AND the commit hash is NOT in the
  doc's add-commit set (`git log --diff-filter=A --format=%H -- <rel>`,
  no `--follow` per CHANGE-0002 D13). This excludes the intake commit even
  when the intake itself was committed as `feat:`; merge subjects
  (`Merge pull request ...`) and `docs:`/`test:` commits never count.
- D4 — Mention boundary (CHANGE-0002 D11 extended to slugs):
  numbered ids (`TYPE-NNNN`): `(?<![0-9A-Za-z])<id>(?![0-9])` — trailing `-`
  allowed so a basename mention `CHANGE-0009-<slug>` counts for CHANGE-0009,
  but CHANGE-030 never matches inside CHANGE-0301;
  slug ids: `(?<![0-9A-Za-z-])<id>(?![0-9A-Za-z-])` — a slug never matches
  inside a longer sibling slug.
- D5 — Precedence: for an eligible open doc the false-open check runs BEFORE
  the stale-open check; a doc that is both stale and delivery-evidenced gets
  `probable-false-open` (the actionable verdict). Docs without delivery
  evidence keep exactly today's stale-open behavior.
- D6 — Frozen-in-body drafts (`status: draft` + `SPEC-FROZEN: true`) are
  checked too: the false-open probe runs before the existing
  aligned/tracked-open early exit. Rationale: 37 of the 39 incident-era specs
  carried the marker — skipping them would blind the heuristic to its main
  motivating class. A frozen draft WITHOUT delivery evidence keeps today's
  `aligned` / `tracked-open` outcome byte-identically.
- D7 — `--quick` mode skips the check entirely (no git/EVENTS probes), same
  as every other drift heuristic.
- D8 — Report-only wiring: verdict `probable-false-open` sets `cls: 'drifted'`
  so it flows into the existing Drift report section, `counts.drifted`, and
  the NEEDS-TRIAGE tally. It NEVER feeds `hardFail`. Additive telemetry:
  `counts.falseOpen`, a `False-open: N` item on the digest summary line, and
  a `--false-open` field on the emitted `docs_audit` event.
- D9 — `suggestedStep` gains the case: `probable-false-open` →
  "confirm delivery, then run close ceremony (status flip + links.pr/commits
  + doc_lifecycle/work_item_closed events)". Shared by docs-audit.mjs AND
  generate-docs-index.mjs (INDEX.audit.md) — one definition, no fork.
- D10 — Evidence citation: the verdict's reasons name the evidencing signal —
  short hash(es) of up to 3 delivering commits, or "ac_evidence event", or
  "AC Status table fully terminal with evidence".

## Acceptance Criteria Mapping

- Maps to: CHANGE-0027 AC-001
  - Spec-AC-01: An eligible open-status doc (each of `draft`, `implementing`,
    `accepted`) whose id or numbered file prefix appears in a later
    feat/fix/chore commit subject is reported `probable-false-open`, with at
    least one evidencing short commit hash in the drift-report Evidence cell.
  - Verification: fixture repo — intake commit, then `feat: deliver <ID>`
    touching another file; `node .aai/scripts/docs-audit.mjs` digest carries
    the row + hash. Suite stanza exits 0.
- Maps to: CHANGE-0027 AC-002
  - Spec-AC-02: A freshly intaken doc is NOT flagged: (a) only its own
    add-commit references it, even when that commit is `feat:`-prefixed;
    (b) later non-delivery mentions (`docs:`, `Merge pull request ...`
    subjects) do not flag either.
  - Verification: fixture negative controls; digest carries no
    `probable-false-open` row for those docs.
- Maps to: CHANGE-0027 Constraints (sibling-ID boundary, CHANGE-0002 D11)
  - Spec-AC-03: No cross-match: an open CHANGE-030 is NOT flagged by
    `feat: ... CHANGE-0301 ...`; a slug id is NOT flagged by a commit
    mentioning only a longer sibling slug that contains it.
  - Verification: fixture boundary stanzas; no false-open row for the sibling.
- Maps to: CHANGE-0027 Desired Behavior (event signal)
  - Spec-AC-04: An eligible open doc with an `ac_evidence` event (ref equal or
    rolled-up `<id>/...`) is flagged `probable-false-open` with the event
    named in reasons.
  - Verification: fixture EVENTS.jsonl line; digest row present.
- Maps to: CHANGE-0027 Desired Behavior (AC-table signal)
  - Spec-AC-05: An eligible open doc whose canonical AC Status table is fully
    terminal with evidenced done rows is flagged; a doc whose table has any
    non-terminal row (or a done row without Evidence) is NOT flagged by this
    signal.
  - Verification: fixture pair (terminal vs non-terminal table); exactly the
    terminal one flags.
- Maps to: CHANGE-0027 AC-003
  - Spec-AC-06: The digest carries the false-open rows in the Drift report,
    the summary line carries `False-open: N`, the overall verdict flips to
    NEEDS-TRIAGE when any exist, and the `docs_audit` event in EVENTS.jsonl
    carries the false-open count.
  - Verification: digest grep (`probable-false-open`, `False-open:`,
    `NEEDS-TRIAGE`) + EVENTS.jsonl tail grep on the fixture repo.
- Maps to: CHANGE-0027 AC-004
  - Spec-AC-07: Existing verdicts are unchanged: the full pre-existing
    docs-audit suite passes unmodified; `--quick` output carries no
    false-open probe; precedence per D5 (stale + delivered → false-open;
    stale without delivery evidence → `probable-stale-open` exactly as
    today).
  - Verification: `.aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-docs-audit.sh`
    exits 0 (all pre-existing stanzas intact) + precedence/quick stanzas.
- Maps to: CHANGE-0027 Motivation (incident class: frozen drafts)
  - Spec-AC-08: A `status: draft` spec carrying `SPEC-FROZEN: true` WITH
    delivery evidence is flagged `probable-false-open`; the same doc WITHOUT
    delivery evidence keeps today's `aligned` / `tracked-open` classification.
  - Verification: fixture pair of frozen drafts; digest shows exactly one row.
- Maps to: CHANGE-0027 Affected Area (digest consumers)
  - Spec-AC-09: Downstream surfaces carry the new verdict: INDEX.audit.md
    (generate-docs-index.mjs) renders the false-open row with the D9
    suggested step (seam test); docs/USER_GUIDE.md verdict list and the
    aai-docs-audit SKILL.md description mention false-open.
  - Verification: run generate-docs-index.mjs on the fixture and grep
    INDEX.audit.md; grep the two doc surfaces in the repo.

## Seam analysis (cross-feature integration)

- SEAM-1: `drift[]` + shared `suggestedStep()` are consumed by BOTH
  docs-audit.mjs (digest) and generate-docs-index.mjs (INDEX.audit.md).
  Covered end-to-end by TEST-012 (produce verdict in the engine, assert the
  rendered INDEX.audit.md row on the other side).
- SEAM-2: the `docs_audit` event payload written via append-event.mjs into
  docs/ai/EVENTS.jsonl (read back by audits/telemetry). Covered by TEST-008
  (assert the appended event line carries the false-open count).
- SEAM-3 (residual risk, not automatable): human-facing verdict enumerations
  in docs/USER_GUIDE.md and .claude/skills/aai-docs-audit/SKILL.md are prose;
  TEST-014 greps for the token but cannot verify prose accuracy. Operator
  review at code-review time covers wording.

## Constitution deviations

None. (Article 5 additive-first checked explicitly: the only behavior change
for pre-existing inputs is D5 — a doc that is BOTH stale and
delivery-evidenced upgrades from `probable-stale-open` to the more actionable
`probable-false-open`. Both are report-only drift verdicts in the same digest
table and the same NEEDS-TRIAGE tally; no consumer branches on the
`probable-stale-open` string for that input class. Documented here and
gated by TEST-009 rather than treated as a breaking change.)

## Acceptance Criteria Status

Tracks per-Spec-AC delivery state. Separate from per-test lifecycle below.

| Spec-AC    | Description                                              | Status  | Evidence | Review-By | Notes |
|------------|----------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | delivery-commit signal flags open doc, hash cited        | done    | TEST-001 green — docs/ai/tdd/green-20260716T233008Z-change0027-remediation-full-suite.log | TDD | — |
| Spec-AC-02 | intake-only / non-delivery mentions never flag           | done    | TEST-002/003 green — docs/ai/tdd/green-20260716T233008Z-change0027-remediation-full-suite.log | TDD | — |
| Spec-AC-03 | sibling-ID and sibling-slug boundary respected           | done    | TEST-004/005 green — docs/ai/tdd/green-20260716T233008Z-change0027-remediation-full-suite.log | TDD | — |
| Spec-AC-04 | ac_evidence event signal flags                           | done    | TEST-006 green — docs/ai/tdd/green-20260716T233008Z-change0027-remediation-full-suite.log | TDD | — |
| Spec-AC-05 | fully terminal evidenced AC table flags; partial does not | done    | TEST-007 green — docs/ai/tdd/green-20260716T233008Z-change0027-remediation-full-suite.log; corroboration refinement (see Notes) re-verified same run | TDD | — |
| Spec-AC-06 | digest rows + False-open count + NEEDS-TRIAGE + event    | done    | TEST-008 green — docs/ai/tdd/green-20260716T233008Z-change0027-remediation-full-suite.log | TDD | — |
| Spec-AC-07 | existing verdicts unchanged; quick skips; D5 precedence  | done    | TEST-009/010/013/015 green — docs/ai/tdd/green-20260716T233008Z-change0027-remediation-full-suite.log (115 PASS, full suite incl. real-repo-CLEAN regressions); repo audit re-verified CLEAN post-fix (`node .aai/scripts/docs-audit.mjs --check --strict --no-event` exit 0) | TDD | Remediation CHANGE-0027: TEST-015 added (in-flight-spec no-regression control) |
| Spec-AC-08 | frozen-in-body drafts checked; unevidenced stay aligned  | done    | TEST-011 green — docs/ai/tdd/green-20260716T233008Z-change0027-remediation-full-suite.log | TDD | — |
| Spec-AC-09 | INDEX.audit.md seam + USER_GUIDE/SKILL doc surfaces      | done    | TEST-012/014 green — docs/ai/tdd/green-20260716T233008Z-change0027-remediation-full-suite.log | TDD | — |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan
- `.aai/scripts/lib/docs-audit-core.mjs`:
  - new `FALSE_OPEN_STATUSES` set (D1) and a `falseOpenEvidence(root, doc,
    content, events)` helper implementing D2/D3/D4 (reuses `git()`,
    `normalizeAcStatus`, `rowHasEvidence`, `TERMINAL_AC`; new
    boundary-regex helper shared for id + fileId);
  - wire into `runAudit`: before the frozen-marker early exit for frozen
    drafts (D6), and before the stale-open branch for the other eligible
    statuses (D5); skip when `quick` (D7);
  - `counts.falseOpen`; `suggestedStep` case (D9); reasons per D10.
- `.aai/scripts/docs-audit.mjs`: summary line `False-open: N`; `emitEvent`
  passes `--false-open` (D8).
- `tests/skills/test-aai-docs-audit.sh`: new fixture docs + stanzas
  (TEST-001..013); keep bash-3.2 compatibility (no bash-4 features).
- `docs/USER_GUIDE.md` verdict list + `.claude/skills/aai-docs-audit/SKILL.md`
  description: add false-open (Spec-AC-09).
- Edge cases: doc created+delivered in one squash commit is excluded by D3
  (add-commit) — accepted residual blind spot, noted below; DRAFT-slug docs
  have `fileId: null` → id-only matching; lean (L0/L1) AC tables are NOT a
  D2(c) signal in v1 (canonical table only) — noted below.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                    | Description                                                                | Status  |
|----------|------------|-------------|-----------------------------------------|----------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh     | open doc (draft/implementing/accepted) + later `feat:` subject mention → `probable-false-open` row with short hash | green |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-docs-audit.sh     | doc whose only reference is its own `feat:`-prefixed add-commit → not flagged | green |
| TEST-003 | Spec-AC-02 | integration | tests/skills/test-aai-docs-audit.sh     | later `docs:` and merge-subject mentions only → not flagged                 | green |
| TEST-004 | Spec-AC-03 | integration | tests/skills/test-aai-docs-audit.sh     | CHANGE-030 open, `feat: ... CHANGE-0301` → CHANGE-030 not flagged           | green |
| TEST-005 | Spec-AC-03 | integration | tests/skills/test-aai-docs-audit.sh     | slug id not matched inside a longer sibling slug mention                    | green |
| TEST-006 | Spec-AC-04 | integration | tests/skills/test-aai-docs-audit.sh     | `ac_evidence` event (rolled-up ref) → flagged, event named in reasons       | green |
| TEST-007 | Spec-AC-05 | integration | tests/skills/test-aai-docs-audit.sh     | fully terminal evidenced AC table → flagged; non-terminal table control → not flagged | green |
| TEST-008 | Spec-AC-06 | integration | tests/skills/test-aai-docs-audit.sh     | digest: drift row + `False-open: N` summary + NEEDS-TRIAGE; EVENTS.jsonl docs_audit line carries false-open count (SEAM-2) | green |
| TEST-009 | Spec-AC-07 | integration | tests/skills/test-aai-docs-audit.sh     | precedence: stale AND delivered → `probable-false-open`; stale only → `probable-stale-open` unchanged | green |
| TEST-010 | Spec-AC-07 | regression  | tests/skills/test-aai-docs-audit.sh     | full pre-existing suite passes unmodified via `.aai/scripts/aai-run-tests.sh` | green |
| TEST-011 | Spec-AC-08 | integration | tests/skills/test-aai-docs-audit.sh     | frozen-in-body draft: evidenced → flagged; unevidenced → aligned/tracked-open | green |
| TEST-012 | Spec-AC-09 | integration | tests/skills/test-aai-docs-audit.sh     | generate-docs-index.mjs on fixture → INDEX.audit.md carries false-open row + D9 step (SEAM-1) | green |
| TEST-013 | Spec-AC-07 | integration | tests/skills/test-aai-docs-audit.sh     | `--quick` digest carries no false-open probe/row                            | green |
| TEST-014 | Spec-AC-09 | unit        | tests/skills/test-aai-docs-audit.sh     | repo-side grep: USER_GUIDE.md verdict list + SKILL.md description mention false-open | green |
| TEST-015 | Spec-AC-07 | regression  | tests/skills/test-aai-docs-audit.sh     | in-flight-spec no-regression control: a frozen-in-body draft whose AC table is terminal but evidenced ONLY by same-session `docs/ai/tdd/*.log` proof (no delivering commit or `ac_evidence` event) stays aligned/tracked-open, NOT `probable-false-open` — added in remediation (CHANGE-0027) after the real-repo audit flagged the in-flight SPEC-0039 itself | green |

Test status values: pending → red → green

Notes:
- Every Spec-AC has at least one TEST-xxx entry.
- All stanzas live in the existing suite file (project convention: one
  bash-3.2-compatible suite per skill, executed only through
  `.aai/scripts/aai-run-tests.sh`).
- RED-proof: TEST-001..009, 011..014 must be observed failing against the
  unmodified engine (TEST-010 is the no-regression control and passes before
  AND after by design). TEST-015 was added in remediation after the initial
  GREEN pass; it is a positive no-regression control against the FIXED engine
  (see Notes below on the D2(c) corroboration refinement) rather than a
  RED-proofed stanza against the unmodified pre-CHANGE-0027 engine.

## Verification
- `.aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-docs-audit.sh`
  → exit 0 (all stanzas, old and new).
- Manual spot-check on a fixture repo: `node .aai/scripts/docs-audit.mjs`
  digest shows the `probable-false-open` row, `False-open: N`, NEEDS-TRIAGE.
- `node .aai/scripts/docs-audit.mjs --quick` on the same fixture: no
  false-open output.
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: CHANGE-0027 (spec: spec-false-open-drift-heuristic)
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path (RED log under docs/ai/tdd/, validation report under
  docs/ai/reports/)
- commit SHA or diff range when available

## Notes
- Residual blind spot (accepted): a doc created AND delivered in the same
  squash commit is excluded by D3's add-commit rule — indistinguishable from
  an intake commit without diff inspection; out of scope v1.
- Follow-up candidates (out of scope v1): `proposed` status eligibility
  (D1); lean L0/L1 AC tables as a D2(c) signal (canonical table only in v1).
- Report-only per RFC-0002: the audit REPORTS; the operator DECIDES closure.
  Auto-remediation and close-gate changes are explicitly out of scope
  (CHANGE-0027 Scope).
- Remediation finding (CHANGE-0027, post-validation-FAIL): the first
  real-repo GREEN run (2026-07-16T23:09Z) preceded the AC Status table below
  being marked fully `done`+evidenced; once that table completed, D2(c) alone
  flagged this very spec `probable-false-open` (repo audit NEEDS-TRIAGE,
  suite aborted at the pre-existing real-repo-CLEAN regression guard) —
  because every done row's Evidence cited only a same-session
  `docs/ai/tdd/*.log` proof artifact, D2(c) could not distinguish "delivered
  and abandoned open" from "in-flight, AC table just completed by TDD, close
  ceremony simply not run yet". Fix (within D2(c)'s own "non-empty Evidence"
  clause, `rowHasEvidence` itself unchanged, no parser fork): at least one
  `done` row's Evidence must cite something other than a `docs/ai/tdd/`
  path for the terminal-AC-table signal to fire alone; `TDD_LOG_EVIDENCE_RE`
  in `falseOpenEvidence()` (docs-audit-core.mjs). D2(a)/(b) are unaffected —
  a commit mention or `ac_evidence` event still flags independently of this
  table-content check. Regression control: TEST-015. See
  docs/ai/reports/validation-CHANGE-0027-20260716T231726Z.md for the FAIL
  report this remediates.
