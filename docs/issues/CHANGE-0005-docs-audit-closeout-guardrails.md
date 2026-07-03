---
id: CHANGE-0005
type: change
status: done
links:
  rfc: RFC-0002
  spec: SPEC-0011
  pr:
    - 27
  commits:
    - bbaef61
    - 34b32e5
    - 221c398
---

# Change Request: Prevent "git-closed but AAI-unreconciled" specs (docs-audit closeout guardrails)

Frontmatter status values: draft | implementing | done | deferred | rejected | superseded

## Summary
- Add preventive closeout guardrails to the RFC-0002 docs-audit engine (plus the
  loop/wrap-up/flush closeout path) so a spec cannot reach `status: done` at the
  git level while its AAI doc closeout (Acceptance Criteria Status table +
  telemetry) is left unreconciled.
- Turn three currently *after-the-fact* / *silent* failure modes into *preventive*
  or *loud* ones: a close-time completeness gate, telemetry-at-close invariant,
  a Review-By truthfulness cross-check, near-miss AC-table detection, and an
  opt-in pre-commit hard block.

## Motivation / Business Value
- Reported from downstream project fh-workspace (2026-07-03). Work items get closed
  at the GIT level (merged PR + `chore(…): close` commit + independent Validation-PASS
  report) while the AAI DOC closeout is never finished. Docs drift into a bad state
  and are only caught after the fact by `docs-audit.mjs` (`probable-partial` /
  `probable-false-done`), often many commits later.
- This undermines trust in every `status: done` spec: the engine detects the drift
  but nothing PREVENTS it, and one malformation class is silently mis-reported.
- Evidence (one real batch, 2026-07): 12 specs — CHANGE-139/140/141/142/143/144,
  ISSUE-037/039/044, PRD-051/052, ISSUE-050 — all `status: done` with merged PRs,
  exhibited:
  - AC Status tables left entirely `planned` (CHANGE-139: 9/9 rows), or **missing**
    the mandated `## Acceptance Criteria Status` table (8 specs), or a non-canonical
    shape the engine silently mis-handles.
  - **Silent mis-report:** a column headed `Evidence (TEST)` (not exactly `Evidence`)
    parsed as "no evidence" → `probable-false-done` for a row that DID cite evidence.
  - Invalid `Review-By` tokens shipped unnoticed (`driver`, bare `Validation`) until a
    whole-doc skip excluded the doc from INDEX.md.
  - No closeout telemetry (`ac_status` / `code_review_completed` / `work_item_closed`)
    for 10 of the 12.
  - **Truthfulness hole:** AC rows carried `Review-By: code-review` although only 2 of
    12 had any code-review artifact/event; the audit passes on a *valid token*
    regardless of whether the claim is *true*.

## Scope
- In scope:
  - G1 — Close-time completeness gate (`docs-audit.mjs --gate <DOC-ID>`, exit 1 on fail),
    wired into `aai-loop` closeout, `aai-wrap-up`, `aai-flush`.
  - G2 — Telemetry-at-close invariant (`ac_status` per row + `work_item_closed` with
    `validation` and `code_review` fields; check/assert on missing close event).
  - G3 — Review-By truthfulness cross-check → new verdict `review-claim-unbacked`.
  - G4 — Near-miss AC-table detection → explicit WARNING instead of silent skip.
  - G5 — Opt-in pre-commit hard block extending the `AAI:INDEX-AUTOGEN` hook.
  - Tests in the docs-audit engine test suite covering all of the above.
- Out of scope:
  - Retro-fixing already-drifted docs in downstream repos (operator remediation via
    `/aai-docs-audit`).
  - Deciding whether a merged PR "counts as" a code review — this only requires that a
    *claim* of code review be backed by a recorded artifact/event, not that review be
    mandatory.

## Affected Area
- `.aai/scripts/lib/docs-model.mjs` — `parseAcTable` (hasGate/Evidence/Review-By parsing),
  `parseReviewBy`, `REVIEW_BY_LABELS/METHODS`, `TERMINAL_AC`.
- `.aai/scripts/lib/docs-audit-core.mjs` — drift heuristics (`probable-partial` /
  `probable-false-done`), `rowHasEvidence`; add G3/G4 verdicts + G1 gate mode.
- `.aai/scripts/docs-audit.mjs` — add `--gate <DOC-ID>`.
- `.aai/scripts/generate-docs-index.mjs` — add G4 near-miss warnings to its violations companion.
- `.aai/scripts/install-pre-commit-hook.sh` / `.ps1` — G5 block.
- Skills `aai-loop`, `aai-wrap-up`, `aai-flush` — invoke G1 + emit G2 telemetry at close.
- Config `docs/ai/docs-audit.yaml` — enforce vs. report-only gating.

## Desired Behavior (To-Be)
- **G1 (core, preventive):** A spec must pass a completeness gate before its frontmatter
  may flip to `status: done`. The gate fails unless: a `## Acceptance Criteria Status`
  section exists with BOTH a `Review-By` column and an exactly-named `Evidence` column;
  every AC row is terminal (`done|deferred|blocked|rejected`); every `done` row has a
  non-empty `Evidence` cell; every `Review-By` token is schema-valid.
- **G2:** Closeout emits `ac_status` per row + `work_item_closed` (with `validation` and
  `code_review` fields). A doc committed as `status: done` with no corresponding
  `work_item_closed` event referencing it is refused (or loudly warned in report-only).
- **G3:** An AC row with `Review-By: code-review` requires corroborating evidence — a
  `code_review_completed` (or `work_item_closed` with `code_review: pass*`) event
  referencing the doc, OR a `docs/ai/{reviews,reports}/*<ID>*` artifact — otherwise the
  engine emits verdict `review-claim-unbacked`. Same principle for any label asserting a
  process step.
- **G4:** A doc that clearly LOOKS like an AC table but isn't canonical (heading contains
  "Acceptance Criteria" but ≠ `## Acceptance Criteria Status`; a column named
  `Evidence (…)`/`Evidence(TEST)` rather than `Evidence`; a Review-By-like column) emits an
  explicit WARNING ("malformed AC table — treated as missing/no-evidence, verdict may be
  inaccurate") instead of silently classifying it.
- **G5 (opt-in, strongest):** The pre-commit hook aborts a commit that flips a spec's
  frontmatter to `status: done` when that doc fails the G1 gate, printing the specific
  reasons. Gated by `docs/ai/docs-audit.yaml` (enforce); report-only by default.
- **RFC-0002 invariant preserved:** the engine REPORTS, the operator DECIDES — no doc is
  ever auto-edited.

## Acceptance Criteria
- AC-001: `docs-audit.mjs --gate <DOC-ID>` exits non-zero for a `status: done` spec whose
  AC table is missing / has any non-terminal row / any `done` row with empty Evidence /
  any invalid Review-By; exits 0 when all hold.
- AC-002: A near-miss AC table (e.g. `Evidence (TEST)` column, or an AC-looking table under
  a non-canonical heading) produces a distinct WARNING, not a silent no-table/no-evidence
  classification.
- AC-003: An AC row with `Review-By: code-review` and no corroborating review
  event/artifact yields verdict `review-claim-unbacked`.
- AC-004: Loop/`aai-wrap-up` closeout runs the G1 gate and refuses to flip `done` (or, in
  report-only, emits a blocking-class warning) when it fails; emits `ac_status` +
  `work_item_closed` on success.
- AC-005: Enforcement respects `docs/ai/docs-audit.yaml` (absent → report-only); the engine
  never edits any doc (RFC-0002 invariant: audit REPORTS, operator DECIDES).
- AC-006: New behavior covered by tests in the docs-audit engine test suite (gate pass/fail,
  near-miss warning, review-claim cross-check, telemetry-at-close assertion).

## Verification
- `node .aai/scripts/docs-audit.mjs --gate <DOC-ID>` → exit 1 on an unreconciled `done`
  spec (missing/non-terminal/empty-evidence/invalid-Review-By), exit 0 when all hold.
- Feed a fixture with an `Evidence (TEST)` column → engine emits the G4 near-miss WARNING.
- Feed a fixture with `Review-By: code-review` and no review event/artifact → verdict
  `review-claim-unbacked`.
- Run the docs-audit engine test suite → new G1/G2/G3/G4 cases pass green.
- Simulate a closeout with an unreconciled table → loop/wrap-up refuses (or warns in
  report-only) and does not emit `work_item_closed`.

## Constraints / Risks
- Must preserve the RFC-0002 invariant: the audit engine never edits docs; it reports and
  the operator decides (AC-005).
- Enforcement must be opt-in via `docs/ai/docs-audit.yaml` so mid-migration downstream
  repos default to report-only and are not hard-blocked.
- G5 pre-commit block must be strictly opt-in (report-only default) to avoid breaking
  contributor workflows that predate the gate.
- Changes are vendored into downstream projects as `.aai/scripts/…`; keep parity between
  `.sh` and `.ps1` hook installers.
- G3 cross-check depends on event/artifact naming conventions
  (`docs/ai/{reviews,reports}/*<ID>*`, `code_review_completed`/`work_item_closed`); a
  convention mismatch could yield false `review-claim-unbacked` verdicts.

## Notes
- Reported-from: downstream project fh-workspace, 2026-07-03. Enhancement to the RFC-0002
  docs-audit engine + loop/wrap-up/flush closeout.
- Root cause: (1) `done` is a frontmatter flip with no completeness/telemetry precondition;
  (2) the AC-table parser fails silently on near-miss shapes; (3) `Review-By: code-review`
  is accepted as a valid label with no cross-check that a corresponding review
  artifact/event exists.
- Related local work: CHANGE-0001/0002 (docs-audit engine improvements), CHANGE-0003
  (verify mode), CHANGE-0004 (parent-closeout-candidate), all under RFC-0002.
