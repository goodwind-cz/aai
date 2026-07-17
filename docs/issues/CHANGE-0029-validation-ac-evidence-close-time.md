---
id: validation-ac-evidence-close-time
type: change
number: 29
status: draft
ceremony_level: 1
links:
  pr: []
  commits: []
---

# Change — Defer `ac_evidence` Emission to Close Ceremony for Open Slug-ID Docs

Ceremony justification: single prompt-file wording change, no engine/test
surface — L1 per SPEC-0030.

## Summary
- `.aai/VALIDATION.prompt.md` step 8a unconditionally directs the validator
  to emit an `ac_evidence` event for every Spec-AC that moved to `done`
  during validation. Amend the step so it withholds that emission for docs
  that are still open and slug-identified, deferring it to the close
  ceremony instead.

## Motivation / Business Value
- Review finding NON-BLOCKING-1 (docs/ai/reviews/review-20260717-091525.md,
  `.aai/VALIDATION.prompt.md:128`): on a slug-id DRAFT spec the only
  available ref for `ac_evidence --ref <id>/Spec-AC-NN` is the frontmatter
  slug (no numbered `fileId` yet). That ref unconditionally trips Arm A of
  the probable-false-open heuristic (`docs-audit-core.mjs` D2(b), preserved
  v1-verbatim), which would flag the still-draft spec `probable-false-open`
  — the exact v1 self-flagging incident CHANGE-0028/CHANGE-0027 exist to
  prevent.
- Disposition recorded in docs/ai/decisions.jsonl
  (ts 2026-07-17T09:19:43Z, ref_id CHANGE-0028, type `review_disposition`):
  "promote-to-follow-up-ref — amend step 8a (+ dispatch RECORDING template
  guidance) to defer ac_evidence emission to close ceremony for open
  slug-id docs."
- This cycle's validator had to override the literal step-8a instruction by
  judgment call (docs/ai/reports/validation-20260717T090900Z-docs-audit-d2-evidence-hardening.md,
  "Findings / notes"); the next slug-DRAFT validator who follows step 8a
  literally will not know to do the same and will re-trigger the incident.

## Scope
- In scope: `.aai/VALIDATION.prompt.md` (step 8a only).
- Out of scope: `.aai/scripts/lib/docs-audit-core.mjs` (heuristic engine
  itself, already hardened by CHANGE-0028), any other VALIDATION.prompt.md
  step, close-ceremony tooling.

## Affected Area
- Validation role prompt (`.aai/VALIDATION.prompt.md`), step 8a
  (`ac_evidence` emission guidance).

## Desired Behavior (To-Be)
- Step 8a's existing behavior is unchanged for numbered docs and for docs
  whose `status` is already `done`: emit `ac_evidence` per completed
  Spec-AC as today.
- For a doc whose frontmatter `status` is still open (`draft` or
  `implementing`) AND whose only matchable ref is the slug `id` (no
  numbered `fileId` yet), the validator MUST NOT emit `ac_evidence` during
  the validation window. Instead it records per-AC evidence in the
  validation report (Requirement -> Evidence citation, as already required
  elsewhere in this prompt) and defers the event emission to the close
  ceremony, which runs after `status` flips to `done` (when the slug ref
  is no longer probed by the open-status heuristic).

## Acceptance Criteria

| AC | Status | Evidence |
|----|--------|----------|
| AC-001: step 8a text is amended to condition `ac_evidence` emission on (numbered doc OR status already done), deferring open slug-id docs to close ceremony | done | `.aai/VALIDATION.prompt.md` amended step 8a (see amendment diff in the corresponding review/change log) |
| AC-002: existing behavior for numbered/done docs is unchanged (no wording removed, only a condition added) | done | diff is additive-only — original emission command line retained verbatim |
| AC-003: `node .aai/scripts/docs-audit.mjs --check --strict --no-event` stays exit 0 after the amendment, with no NEW false-open/drift finding introduced by it | done | audit re-run: exit 0 both before and after this amendment (verified via `git stash` A/B on `.aai/VALIDATION.prompt.md` + this doc); the one pre-existing NEEDS-TRIAGE row (`docs-audit-d2-evidence-hardening`, reason `work_item_closed event`) is CHANGE-0028's own pending-close state, unchanged by this amendment and out of scope (owned by the close ceremony) |

## Verification
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` -> exit 0
  (unchanged from pre-amendment baseline; see AC-003).
- `grep -n "ac_evidence" .aai/VALIDATION.prompt.md` renders the amended step 8a as expected.

## Constraints / Risks
- Prompt-file-only change (no engine, no test surface) — L1 ceremony per
  SPEC-0030 D3 ("Spec artifact (Planning policy)" row); this intake doc
  carries the tech-note and lean AC table in place of a separate SPEC file,
  per the ISSUE-0008 precedent for a small, direct canon edit.
- Risk of under-specifying "slug-id" vs "numbered doc": the amendment must
  key off the same signal the heuristic itself uses (frontmatter `id` vs a
  numbered `fileId` derived from the filename), not a new ad hoc test, to
  avoid drifting from `docs-audit-core.mjs`'s actual matching logic.

## Notes
- Closes the follow-up recorded in docs/ai/decisions.jsonl at
  2026-07-17T09:19:43Z (ref CHANGE-0028).
- Does not touch `docs/ai/STATE.yaml` — STATE ownership stays with the loop
  runner for this tick.
