---
id: spec-docs-audit-d2-evidence-hardening
type: spec
number: 40
status: done
ceremony_level: 2
links:
  change: docs-audit-d2-evidence-hardening
  rfc: null
  pr:
    - 92
  commits:
    - 6c3ec66
---

# SPEC — Docs-Audit D2(b)/D2(c) Delivery-Evidence Hardening

SPEC-FROZEN: true

## Links
- Change: docs-audit-d2-evidence-hardening
  (docs/issues/CHANGE-0028-docs-audit-d2-evidence-hardening.md)
- Extends/supersedes (decisions only, doc not edited):
  docs/specs/SPEC-0039-spec-false-open-drift-heuristic.md — this spec
  SUPERSEDES SPEC-0039's frozen D2(b) semantics and REFINES D2(c)'s
  corroboration clause; SPEC-0039 itself is done/frozen and stays untouched.
- Source findings: docs/ai/reviews/review-20260716-234625.md section H6
  (NON-BLOCKING-1, NON-BLOCKING-2); dispositions in docs/ai/decisions.jsonl
  (`review_disposition`, ts 2026-07-16T23:50:02Z, ref_id CHANGE-0027).
- Technology contract: docs/TECHNOLOGY.md

## Problem
Two recall gaps in `falseOpenEvidence()` (.aai/scripts/lib/docs-audit-core.mjs):

- NB-1 — D2(c) reads a done row's Evidence cell as TDD-only whenever the cell
  contains `docs/ai/tdd/` ANYWHERE (whole-cell substring test,
  `TDD_LOG_EVIDENCE_RE`). A cell mixing a TDD proof log with a genuine
  delivery reference (commit hash, PR link) never satisfies
  `hasDeliveryEvidence`, so a delivered-and-abandoned spec whose every done
  row is such a mixed cell escapes the AC-table signal entirely.
- NB-2 — D2(b) matches `ac_evidence` event refs against the frontmatter slug
  `id` only. This repo's events use numbered file-prefix refs
  (`SPEC-0039/Spec-AC-01`, `CHANGE-0027`), so D2(b) can never fire for this
  repo's own specs — confirmed live at the CHANGE-0027 close ceremony.

Both fixes are recall-only and must be precision-preserving: the guarded
failure direction is re-flagging in-flight or mid-validation docs (the exact
v1 validation-FAIL class — SPEC-0039 flagged itself mid-implementation until
the `TDD_LOG_EVIDENCE_RE` remediation landed).

## Ceremony level
`ceremony_level: 2` — the scope is one function in the docs-audit drift
engine plus tests and one prose surface, which superficially reads as L1; it
is kept at level 2 because the change alters counting semantics of a
governance heuristic with a documented prior incident of self-flagging the
repo's own in-flight work (SPEC-0039 remediation), so full independent
validation and a mandatory dual-verdict review are warranted. No touched path
is on `protected_paths_l3` (checked against docs/ai/docs-audit.yaml on
2026-07-17: state engine, allocator, pre-commit hosts, WORKFLOW.md,
CONSTITUTION.md only) — L3 does not apply.

## Implementation strategy
- Strategy: tdd
- Rationale: counting-semantics change on the governance drift engine with
  real heuristic-precision risk (false positives on in-flight specs — the
  v1 lesson). Every new counting arm needs a RED-proofed positive stanza and
  a negative control; mirrors the SPEC-0036/SPEC-0039 precedent for changes
  to this same file.
- RED-proof obligation: TEST-001, TEST-002, TEST-006, TEST-008 and TEST-011
  must be observed FAILING against the unmodified engine (RED log under
  docs/ai/tdd/). TEST-003/004/005/007/009/010 are no-regression / guard
  controls that pass before AND after by design (non-vacuous: each fixture
  stanza carries the shared CHANGE-9001 positive control via
  `assert_fo_control_flagged`, per the SPEC-0039 TEST-010/015 precedent).

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: PR-bound change to the drift engine consumed by the
  pre-commit host and index generator; isolation keeps main's audit output
  stable while fixtures churn. Not `required` — no protected (L3) surface,
  no migration, additive engine change.
- User decision: inline (operator pre-decision, recorded in STATE before
  planning): inline on a fresh feature branch off main, created at
  implementation time — no direct work on main.
- Base ref: main (47d2ddf at planning time)
- Inline review scope (explicit paths):
  - .aai/scripts/lib/docs-audit-core.mjs
  - tests/skills/test-aai-docs-audit.sh
  - docs/USER_GUIDE.md
  - .claude/skills/aai-docs-audit/SKILL.md (only if its wording is touched)
  - docs/specs/SPEC-0040-spec-docs-audit-d2-evidence-hardening.md (this spec)
  - docs/issues/CHANGE-0028-docs-audit-d2-evidence-hardening.md (links backfill at close)

## Design decisions (frozen)

- D1 — Blast radius: only `falseOpenEvidence()` and its private helpers/
  constants in `.aai/scripts/lib/docs-audit-core.mjs` change. SPEC-0039's
  D1 (eligible statuses), D3 (add-commit exclusion), D4 (mention boundary),
  D5 (precedence), D6 (frozen drafts), D7 (--quick skip), D8 (report-only
  wiring), D9 (suggestedStep) and D10 (reasons) are all inherited unchanged.
  No new CLI flags, digest fields, counts, or event payload fields.
- D2 — D2(c) v2 (mixed Evidence cells): a done row counts toward
  `hasDeliveryEvidence` iff `rowHasEvidence(row)` AND (
  (a) the cell contains NO `docs/ai/tdd/` mention — the v1 arm, preserved
  byte-identically; OR
  (b) NEW: the cell contains a delivery-grade citation).
  A delivery-grade citation is EXACTLY one of:
  (i) a git-verified commit hash — a maximal token matching
      `(?<![0-9A-Za-z])[0-9a-f]{7,40}(?![0-9A-Za-z])` (lowercase hex,
      boundary-guarded so tokens embedded in longer alphanumerics such as
      `green-20260716T233008Z` never match) that RESOLVES in the audited
      repo: `git rev-parse --quiet --verify <token>^{commit}` exits 0;
  (ii) a PR reference — `PR #N` / `PR#N` (case-insensitive,
      `/\bPR\s*#\d+/i`) or a pull-URL path segment (`/\/pull\/\d+(?![0-9])/`).
  Explicitly NOT delivery-grade (precision rule): bare `#N`, re-verification
  or audit prose, `docs/ai/tdd/` paths, ac_evidence-style refs written in
  prose (`SPEC-NNNN/Spec-AC-NN` — validation-window-ambiguous, the exact v1
  FAIL class), and hash-shaped tokens that do NOT resolve in git. A cell
  citing ONLY TDD logs plus such prose stays suppressed — this keeps
  SPEC-0039's own Spec-AC-07 row unflagged (CHANGE-0028 AC-003).
- D3 — D2(b) v2 (event matching), three arms:
  - Arm A (v1, preserved verbatim): `ac_evidence` whose
    `ref === doc.id || ref.startsWith(doc.id + '/')` counts unconditionally
    (frozen SPEC-0039 semantics; keeps existing TEST-006 fixture green).
  - Arm B (NEW): `ac_evidence` whose ref matches `doc.fileId` under the same
    roll-up boundary (`ref === fileId || ref.startsWith(fileId + '/')`),
    applicable only when `doc.fileId` is non-null AND `!== doc.id`, counts
    IFF the in-flight discriminator passes: `payload.commit` is a string
    whose trimmed WHOLE value matches `/^[0-9a-f]{7,40}$/`. Structural, not
    phrasing-based: the validation-window class
    (`"validation-<ts> re-verified PASS (...)"`) is excluded because its
    payload.commit is a descriptive sentence, regardless of future wording.
    `payload.evidence` never counts; an absent `payload.commit` never counts.
    No git-existence check for Arm B (a close-time event may cite a hash
    later rewritten by rebase; hash-shape alone already fully excludes the
    in-flight class).
  - Arm C (NEW): `work_item_closed` whose ref matches EITHER id candidate
    (doc.id or doc.fileId, same roll-up boundary) counts unconditionally —
    it is emitted only by the close ceremony/flush, never during validation;
    its presence against a still-open doc is definitionally false-open drift
    (the live CHANGE-0027 incident that motivated NB-2).
- D4 — Reasons (SPEC-0039 D10 inherited): arms A/B reuse the existing
  `ac_evidence event` reason string; arm C adds `work_item_closed event`;
  the D2(c) reason string `AC Status table fully terminal with evidence`
  is unchanged (existing stanzas grep these literals).
- D5 — Precision-first invariant: every new counting arm ships with a
  negative control in the same suite, and the real-repo audit
  (`node .aai/scripts/docs-audit.mjs --check --strict --no-event`) must be
  CLEAN both MID-implementation (the suite's real-repo stanzas run on every
  green cycle) and after — the heuristic must never flag the repo's own
  in-flight work, including this spec itself.
- D6 — Mid-flight evidence discipline (self-flagging guard): while this scope
  is in flight, its own AC Status table's Evidence cells must cite ONLY
  `docs/ai/tdd/*.log` proofs (no commit hashes, no PR refs) until the close
  ceremony — otherwise D2(c) v2 would correctly flag this very spec. This is
  the existing Evidence-contract convention, restated here as a hard rule.
- D7 — Residual risks (accepted, documented):
  (a) a 7-40 digit purely numeric token in a mixed cell could in principle
      resolve as an abbreviated commit hash (probability ≈ commits/16^7 per
      token — negligible; the git-verify step is exactly what bounds it);
  (b) squash-created-and-delivered docs remain invisible (inherited
      SPEC-0039 blind spot, unchanged);
  (c) Arm A (slug-ref `ac_evidence` without payload filter) retains v1's
      theoretical in-flight exposure; unchanged by design — this repo's
      validation convention emits numbered refs, and narrowing Arm A would
      be a breaking change to frozen, suite-covered v1 semantics.
- D8 — Doc surfaces: the docs/USER_GUIDE.md `probable-false-open` bullet is
  updated to name the `work_item_closed` event and the mixed-cell rule
  (delivery citation anywhere in the cell counts). The aai-docs-audit
  SKILL.md description already says "false-open (delivered but still ...)"
  and needs no change unless review finds drift.

## Acceptance Criteria Mapping

- Maps to: CHANGE-0028 AC-001
  - Spec-AC-01: A done AC row whose Evidence cell cites both a
    `docs/ai/tdd/*.log` path AND a commit hash that exists in the audited
    repo is counted by `hasDeliveryEvidence`; a fixture doc in an open status
    whose EVERY done row is such a mixed cell is flagged
    `probable-false-open` via the AC-table signal.
  - Verification: TEST-001 stanza — fixture repo commit's real short hash
    written into the cell; digest carries the row + the D4 reason literal.
- Maps to: CHANGE-0028 AC-002
  - Spec-AC-02: Same as Spec-AC-01 with a PR-style citation (`PR #91` and a
    `.../pull/91` URL variant) instead of a hash.
  - Verification: TEST-002 stanza; digest carries the row.
- Maps to: CHANGE-0028 AC-003 (negative control, NB-1)
  - Spec-AC-03: A cell replicating SPEC-0039's real Spec-AC-07 row verbatim
    (TDD log path + "repo audit re-verified CLEAN post-fix
    (`node .aai/scripts/docs-audit.mjs --check --strict --no-event` exit 0)"
    prose; no hash/PR ref) is NOT counted, and the real
    docs/specs/SPEC-0039*.md produces no `probable-false-open` verdict on
    the current repo.
  - Verification: TEST-005 stanza (synthetic replica) + TEST-009 (real repo).
- Maps to: CHANGE-0028 AC-004 (negative control)
  - Spec-AC-04: A done row mixing a `docs/ai/tdd/*.log` path with (a)
    arbitrary non-delivery prose, or (b) a hash-shaped token that does NOT
    resolve in the audited repo's git, is NOT counted by
    `hasDeliveryEvidence` — the doc stays unflagged.
  - Verification: TEST-003 (prose) + TEST-004 (unresolvable hash) stanzas;
    both fixtures carry the shared CHANGE-9001 positive control.
- Maps to: CHANGE-0028 AC-005
  - Spec-AC-05: An `ac_evidence` event whose ref is the doc's numbered
    fileId (equal or rolled-up `fileId/...`), on a doc whose frontmatter id
    is a different slug, with `payload.commit` a whole-string plausible git
    hash, causes D2(b) to fire for an open-status fixture doc (reason names
    the ac_evidence event).
  - Verification: TEST-006 stanza (event appended via the real
    append-event.mjs `--commit <hash>`).
- Maps to: CHANGE-0028 AC-006 (negative control, NB-2)
  - Spec-AC-06: The same fixture shape with `payload.commit` a
    validation-window re-verification string
    (`"validation-<ts> re-verified PASS (...)"`), and separately with a
    payload carrying only `--evidence` (no commit key), does NOT trigger
    D2(b); the doc is not reported `probable-false-open`.
  - Verification: TEST-007 stanza; fixture also carries the CHANGE-9001
    positive control.
- Maps to: CHANGE-0028 Motivation (NB-2 live incident) + dispatch design
  constraint 2 (work_item_closed as delivery-grade)
  - Spec-AC-07: A `work_item_closed` event whose ref matches the doc's
    numbered fileId OR its slug id (roll-up boundary) causes D2(b) to fire
    for an open-status fixture doc, with `work_item_closed event` named in
    reasons — no payload filter (close-ceremony-only event kind).
  - Verification: TEST-008 stanza (both ref forms, events appended via the
    real append-event.mjs — SEAM-1).
- Maps to: CHANGE-0028 AC-007
  - Spec-AC-08: `node .aai/scripts/docs-audit.mjs --check --strict
    --no-event` on the real repo after the fix exits 0 with NO
    `probable-false-open` verdict for SPEC-0039 or any other presently
    open/in-flight doc (AC-003 and AC-006 hold on the real repo, not only in
    fixtures) — and stays CLEAN mid-implementation (D5).
  - Verification: TEST-009 (rides the suite's existing real-repo-CLEAN
    regression stanzas) + an explicit validation-phase run of the command.
- Maps to: CHANGE-0028 AC-008
  - Spec-AC-09: All pre-existing docs-audit behavior is unchanged: D2(a),
    D2(c)'s whole-terminal-table gate, D2(b) Arm A, and every other verdict
    (`probable-false-done`, `probable-stale-open`, `partial`, ...). The full
    suite passes green with the pre-existing stanzas byte-unmodified
    (test-file diff purely additive).
  - Verification: TEST-010 — `.aai/scripts/aai-run-tests.sh bash
    tests/skills/test-aai-docs-audit.sh` exit 0 + `git diff --stat` on the
    suite file shows additions only.
- Maps to: CHANGE-0028 Scope (USER_GUIDE wording if semantics change — they
  do: work_item_closed + mixed-cell rule)
  - Spec-AC-10: The docs/USER_GUIDE.md `probable-false-open` bullet names
    the `work_item_closed` event among the delivery-evidence signals and
    states the mixed-cell rule.
  - Verification: TEST-011 — repo-side grep of the bullet for
    `work_item_closed`; prose accuracy covered by code review (SEAM-4).

## Seam analysis (cross-feature integration)

- SEAM-1: docs/ai/EVENTS.jsonl — written by append-event.mjs (validation,
  flush, close ceremony), read by `falseOpenEvidence()`. Arm B/C are new
  consumptions of that seam. Crossed end-to-end by TEST-006/007/008: events
  are appended with the REAL writer (append-event.mjs), then the audit reads
  them back — no mocked boundary.
- SEAM-2: git object store — D2(c)'s new hash verification
  (`git rev-parse --quiet --verify`) reads the audited repo's history.
  Crossed in both directions by TEST-001 (existing fixture-repo hash counts)
  and TEST-004 (nonexistent hash does not).
- SEAM-3: digest / INDEX.audit.md rendering (docs-audit.mjs +
  generate-docs-index.mjs shared `suggestedStep`) — wiring untouched (D1);
  guarded by the pre-existing SPEC-0039 TEST-012 seam stanza inside the
  TEST-010 full-suite run.
- SEAM-4 (residual risk, not automatable): USER_GUIDE prose accuracy —
  TEST-011 greps the token only; the dual-verdict code review verifies the
  wording (same disposition as SPEC-0039 SEAM-3).

## Constitution deviations

None. (Article 5 additive-first checked explicitly: both v1 counting arms —
D2(c)(a) and D2(b) Arm A — are preserved byte-identically; the change only
ADDS evidence classes, so no pre-existing input can lose or change its
verdict except gaining the intended new flags. Article 2 simplicity: the
intake's "ac_evidence-style ref in prose" citation idea is deliberately NOT
implemented — it is validation-window-ambiguous and the binding CHANGE ACs
do not require it; recorded in D2 and Notes.)

## Acceptance Criteria Status

Tracks per-Spec-AC delivery state. Separate from per-test lifecycle below.

| Spec-AC    | Description                                                    | Status  | Evidence | Review-By | Notes |
|------------|----------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | mixed cell TDD log + git-verified hash counts (D2(c) v2)      | done | TEST-001 red — docs/ai/tdd/red-20260717T084615Z-change0028-d2-hardening.log; green — docs/ai/tdd/green-20260717T084815Z-change0028-d2-hardening.log | TDD | — |
| Spec-AC-02 | mixed cell TDD log + PR reference counts                       | done | TEST-002 red — docs/ai/tdd/red-20260717T084615Z-change0028-d2-hardening.log; green — docs/ai/tdd/green-20260717T084815Z-change0028-d2-hardening.log | TDD | — |
| Spec-AC-03 | SPEC-0039 Spec-AC-07-shaped cell stays suppressed              | done | TEST-005 green (control, pre+post pass) — docs/ai/tdd/green-20260717T084815Z-change0028-d2-hardening.log | TDD | — |
| Spec-AC-04 | TDD + non-delivery prose / unresolvable hash stays suppressed  | done | TEST-003/004 green (controls, pre+post pass) — docs/ai/tdd/green-20260717T084815Z-change0028-d2-hardening.log | TDD | — |
| Spec-AC-05 | fileId-ref ac_evidence with hash payload fires (Arm B)         | done | TEST-006 red — docs/ai/tdd/red-20260717T084615Z-change0028-d2-hardening.log; green — docs/ai/tdd/green-20260717T084815Z-change0028-d2-hardening.log | TDD | — |
| Spec-AC-06 | validation-window payload / evidence-only payload never fires  | done | TEST-007 green (control, pre+post pass) — docs/ai/tdd/green-20260717T084815Z-change0028-d2-hardening.log | TDD | — |
| Spec-AC-07 | work_item_closed ref match fires unconditionally (Arm C)       | done | TEST-008 red — docs/ai/tdd/red-20260717T084615Z-change0028-d2-hardening.log; green — docs/ai/tdd/green-20260717T084815Z-change0028-d2-hardening.log | TDD | — |
| Spec-AC-08 | real-repo audit stays CLEAN (mid-implementation and after)     | done | TEST-009 green (control, pre+post pass); real-repo `--check --strict --no-event` re-run exit 0 CLEAN — docs/ai/tdd/green-20260717T084815Z-change0028-d2-hardening.log | TDD | — |
| Spec-AC-09 | pre-existing suite green, stanzas byte-unmodified, additive     | done | TEST-010 — full suite 125/125 PASS; suite-file diff 299 insertions/0 deletions (additive-only) — docs/ai/tdd/green-20260717T084815Z-change0028-d2-hardening.log | TDD | — |
| Spec-AC-10 | USER_GUIDE bullet names work_item_closed + mixed-cell rule     | done | TEST-011 red — docs/ai/tdd/red-20260717T084615Z-change0028-d2-hardening.log; green — docs/ai/tdd/green-20260717T084815Z-change0028-d2-hardening.log | TDD | — |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan
- `.aai/scripts/lib/docs-audit-core.mjs` (only file with behavior change):
  - new module-level constants: `PLAUSIBLE_HASH_RE = /^[0-9a-f]{7,40}$/`
    (whole-string, used by Arm B), a boundary-guarded hash-token extraction
    regex and a PR-reference regex (D2(ii));
  - new private helper `cellHasDeliveryCitation(root, cell)` implementing
    D2(b(i))/(b(ii)) — extracts candidate hash tokens, verifies via the
    existing `git()` wrapper (`rev-parse --quiet --verify <tok>^{commit}`;
    a failed probe simply does not count — Article 4 degrade direction is
    suppression, never a flag);
  - D2(c) block: `hasDeliveryEvidence` becomes
    `rowHasEvidence(r) && (!TDD_LOG_EVIDENCE_RE.test(cell) || cellHasDeliveryCitation(root, cell))`;
  - D2(b) block: implement arms A/B/C per D3 with reasons per D4.
- `tests/skills/test-aai-docs-audit.sh`: append TEST-001..008 stanzas +
  TEST-011 grep (bash-3.2 compatible, reuse `setup_fo_repo`,
  `assert_fo_control_flagged`, `extract_section_h3`); wire into `main()`.
  Pre-existing stanzas are NOT edited (Spec-AC-09).
- `docs/USER_GUIDE.md`: extend the `probable-false-open` bullet (D8).
- Edge cases: fileId === id docs (numbered frontmatter ids) are fully served
  by Arm A — Arm B's `fileId !== id` clause avoids double semantics;
  DRAFT-slug docs have `fileId: null` → arms A/C-by-id only; `--quick`
  continues to skip the whole probe (D7 inherited — no new stanza needed,
  existing TEST-013 covers the skip).

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                | Description                                                                                     | Status  |
|----------|------------|-------------|-------------------------------------|-------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh | open doc, terminal AC table, every done row mixes TDD log + real fixture-repo short hash → flagged via AC-table signal | red |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-docs-audit.sh | mixed cell with `PR #91` (and a `/pull/91` URL row) → flagged                                    | red |
| TEST-003 | Spec-AC-04 | integration | tests/skills/test-aai-docs-audit.sh | mixed cell TDD log + non-delivery prose only → NOT flagged (no-regression control, pre+post pass) | green |
| TEST-004 | Spec-AC-04 | integration | tests/skills/test-aai-docs-audit.sh | mixed cell TDD log + hash-shaped token absent from git (`abcdef1`) → NOT flagged (git-verify guard control, pre+post pass) | green |
| TEST-005 | Spec-AC-03 | integration | tests/skills/test-aai-docs-audit.sh | verbatim replica of SPEC-0039 Spec-AC-07 Evidence cell → NOT flagged (pre+post pass)             | green |
| TEST-006 | Spec-AC-05 | integration | tests/skills/test-aai-docs-audit.sh | slug-id doc with numbered filename + ac_evidence ref `<fileId>/Spec-AC-01` `--commit <hash>` via append-event.mjs → flagged, reason `ac_evidence event` (SEAM-1) | red |
| TEST-007 | Spec-AC-06 | integration | tests/skills/test-aai-docs-audit.sh | same shape, payload.commit = `validation-<ts> re-verified PASS (...)`; plus `--evidence`-only event → NOT flagged (in-flight discriminator guard, pre+post pass) | green |
| TEST-008 | Spec-AC-07 | integration | tests/skills/test-aai-docs-audit.sh | work_item_closed via append-event.mjs, fileId ref AND slug ref variants → flagged, reason `work_item_closed event` (SEAM-1) | red |
| TEST-009 | Spec-AC-08 | regression  | tests/skills/test-aai-docs-audit.sh | real-repo audit CLEAN (`--check --strict --no-event` exit 0, no probable-false-open row) — rides the existing real-repo-CLEAN stanzas + explicit validation run | green |
| TEST-010 | Spec-AC-09 | regression  | tests/skills/test-aai-docs-audit.sh | full suite via `.aai/scripts/aai-run-tests.sh` exit 0; suite-file diff purely additive (pre-existing stanzas byte-unmodified) | green |
| TEST-011 | Spec-AC-10 | unit        | tests/skills/test-aai-docs-audit.sh | repo-side grep: USER_GUIDE `probable-false-open` bullet names `work_item_closed`                 | red |

Test status values: pending → red → green

Notes:
- Every Spec-AC has at least one TEST-xxx entry.
- RED-proof split per the Implementation strategy section: TEST-001/002/006/
  008/011 RED-proofed against the unmodified engine; TEST-003/004/005/007/
  009/010 are controls passing before AND after (non-vacuous via the shared
  CHANGE-9001 positive control in every fixture repo).
- All stanzas live in the existing suite file (project convention: one
  bash-3.2-compatible suite per skill, executed only through
  `.aai/scripts/aai-run-tests.sh`).

## Verification
- `.aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-docs-audit.sh`
  → exit 0 (all stanzas, old and new; TEST-010).
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` at the repo
  root → exit 0, Verdict CLEAN, `False-open: 0` (TEST-009 / Spec-AC-08); run
  it also mid-implementation after each GREEN cycle (D5).
- `git diff --stat tests/skills/test-aai-docs-audit.sh` → additions only.
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: docs-audit-d2-evidence-hardening / CHANGE-0028
  (spec: spec-docs-audit-d2-evidence-hardening)
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path (RED log under docs/ai/tdd/, validation report under
  docs/ai/reports/)
- commit SHA or diff range when available
- HARD RULE (D6): this spec's own AC Status table Evidence cells cite ONLY
  `docs/ai/tdd/*.log` paths until the close ceremony — no commit hashes or
  PR refs mid-flight (self-flagging guard).

## Notes
- Deliberately out of scope (per CHANGE-0028 Scope + Article 2): D2(a)
  commit-mention matching; removal of the whole-cell TDD exclusion for
  citation-free cells (must remain — AC-003/AC-004 controls);
  "ac_evidence-style ref in Evidence prose" as a delivery citation
  (validation-window-ambiguous — see D2); auto-remediation; close-ceremony
  changes; narrowing Arm A (see D7(c)).
- Follow-up candidates inherited from SPEC-0039 (unchanged): `proposed`
  status eligibility; lean L0/L1 AC tables as a D2(c) signal.
- Report-only per RFC-0002: the audit REPORTS; the operator DECIDES closure.
