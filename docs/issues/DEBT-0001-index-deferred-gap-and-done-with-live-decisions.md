---
id: DEBT-0001
type: techdebt
status: done
links:
  pr: []
  commits: []
---

# Tech Debt: INDEX drops whole-doc `deferred`; `done` can close with live decisions buried as WARNING

## Debt Summary
Two systemic gaps surfaced while triaging CHANGE-075 and CHANGE-128:

1. **Tooling gap — whole-doc `deferred` silently disappears from `docs/INDEX.md`.**
   `deferred` is a valid frontmatter status (accepted by `DOC_STATUS_ENUM`,
   passes `docs-audit`), but `generate-docs-index.mjs` renders doc-level sections
   only for `done`, `draft`, `rejected`/`superseded`, canonical, and legacy.
   There is a *per-AC* "Deferred items" section but **no whole-doc deferred
   section**, so a doc set to `status: deferred` passes every check yet vanishes
   from the index. (CHANGE-075 disappeared this way.)

2. **Process gap — a doc can be closed `done` while live (open) decisions hang
   as a buried WARNING in its spec** instead of being resolved or tracked as a
   first-class item. (CHANGE-128 was marked `done` with two open confirmations
   — RR-1, RR-2 — sitting only as a WARNING.)

The two specific instances are already remediated (CHANGE-075 → `supe√rseded`;
CHANGE-128 → operator-CONFIRMED 2026-06-30 with a regression test). This item
captures the *systemic* fixes so neither class recurs.

## Root Cause
- (1) The index generator's section list is an allow-list of statuses; `deferred`
  was simply never given a doc-level section. No invariant guarantees that every
  validatable doc appears in exactly one section, so a "valid but unrendered"
  status fails open (invisible) rather than failing loud.
- (2) Workflow/close policy permits transitioning to `done` with unresolved
  decisions recorded only as free-text WARNINGs in the spec body. WARNINGs are
  not tracked, not indexed, and not gated — so they are easy to bury and forget.

## Current Cost / Risk
- Items silently drop out of the working set → lost work, no triage, no review-by
  tracking. Erodes trust in `docs/INDEX.md` as the source of truth.
- "Done" overstates reality: closed items can still carry live, unmade decisions,
  so closeout/done counts are misleading and decisions rot unowned.

## Target State
- (1) Every doc with a valid frontmatter status appears in exactly one INDEX
  section. Whole-doc `deferred` is visible (its own section, or folded into a
  visible status section), with review-by surfaced like other tracked items. A
  guard/CI assertion fails loud if any non-legacy doc would render in zero
  sections.
- (2) A doc cannot be closed `done` with unresolved decisions hidden as WARNINGs.
  Open decisions must be either (a) resolved before close, or (b) promoted to a
  first-class, tracked, indexed item (e.g. a per-AC `blocked`/`deferred` row or a
  follow-up doc) — never left as a buried spec WARNING.

## Scope
- In scope:
  - Add a whole-doc `deferred` section to `generate-docs-index.mjs` (and confirm
    `--strict` behavior).
  - Add a coverage invariant: assert every non-legacy doc lands in ≥1 section;
    fail loud otherwise (CI gate via `--strict`).
  - Codify the close-policy rule in the workflow/validation prompts and, if
    feasible, enforce via a `docs-audit` check (warn/fail on `done` docs whose
    body contains unresolved-decision markers / open WARNINGs).
- Out of scope:
  - The already-completed instance fixes for CHANGE-075 and CHANGE-128.
  - Broader redesign of the status enum or the AC tracking model (RFC-0001).

## Plan / Migration
1. `generate-docs-index.mjs`: add a "Deferred (whole-doc)" section rendering
   `byStatus('deferred')`; keep the existing per-AC "Deferred items" section.
2. Add the zero-section coverage invariant + a test that a `deferred` doc now
   appears; wire it into `--strict` so CI fails on regression.
3. Workflow/validation prompts: add the explicit close-policy rule (no `done`
   with live decisions buried as WARNING).
4. Optional `docs-audit` guard: detect `done` docs carrying open-decision markers
   and report them as a first-class finding rather than relying on spec WARNINGs.
- Fallback: changes are additive to the index generator (degrade-and-report
  philosophy already in place); no migration of existing docs required beyond the
  two already fixed.

## Verification
- `node .aai/scripts/generate-docs-index.mjs` — a doc with `status: deferred`
  appears in the index (regression test asserts presence).
- New test: a fixture doc that would render in zero sections makes the generator
  fail under `--strict` (RED before fix, GREEN after).
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` — exits 0 CLEAN
  on the repo after changes.
- (If the audit guard is built) a fixture `done` doc with an open-decision marker
  is flagged by `docs-audit`.

## Constraints / Risks
- Must preserve degrade-and-report: one malformed doc must never block the index.
- The close-policy enforcement must not produce noisy false positives on
  legitimate informational notes; start as report/warn, escalate to gate only if
  signal is clean.
- Keep the per-AC vs whole-doc deferred distinction clear to avoid double-listing.

## Notes
- Trigger: cross-agent triage report, 2026-06-30. Instances CHANGE-075,
  CHANGE-128 (both already remediated). Related: RFC-0001 (AC tracking),
  RFC-0002 (docs hygiene & drift audit). Process learning to fold into the
  workflow: do not close `done` with live decisions; do not use whole-doc
  `deferred` as a way to hide an item — use `superseded`/`rejected` or keep it
  visibly tracked.
