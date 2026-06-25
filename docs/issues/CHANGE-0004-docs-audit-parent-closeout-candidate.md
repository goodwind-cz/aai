---
id: CHANGE-0004
type: change
status: done
links:
  rfc: RFC-0002
  spec: SPEC-0003
  change: CHANGE-0003
  pr:
    - 12
  commits:
    - 9379752
---

# Change Request: docs-audit parent-closeout-candidate detection

## Summary
- Add a docs-audit hygiene check that flags a non-terminal parent document
  (e.g. an RFC or PRD with status `proposed` / `accepted` / `implementing`)
  whose linked implementation spec(s) are all `done`, as a **closeout
  candidate**. The audit reports it for human closeout; it never auto-closes.

## Motivation / Business Value
- Recurring process gap: when work flows intake -> spec -> implementation, the
  loop roles (Planning/Implementation/Validation/Code Review) operate on the
  SPEC and correctly advance the SPEC to `done`, but nothing advances the
  originating RFC/PRD. Its status stays non-terminal, so `generate-docs-index`
  buckets it under "Active (implementing)" and it looks unfinished long after
  the work shipped.
- Observed twice: RFC-0001 had to be closed retroactively
  (commit e838b43, "false-done remediation via docs-audit verify"), and
  RFC-0003 (this skill's own RFC) stayed `proposed` after its SPEC-0002 reached
  `done` and the work merged (PR #11) until it was hand-corrected.
- docs-audit is already the project's hygiene authority (RFC-0002) and already
  closed RFC-0001 via verify mode; surfacing this class continuously (CI +
  loop ticks) is the durable, philosophy-consistent fix ("audit reports;
  operator decides").

## Scope
- In scope:
  - A new read-only classification in the docs-audit engine: a parent doc in a
    non-terminal status whose every linked spec (via `links.spec`, and the
    reverse `spec.links.rfc` / spec `ref_id` association already used by the
    engine) is `done` => `closeout-candidate`.
  - Surface it in the audit report (its own section/verdict) and make it
    available to the index generator if cheap, OR at least to `--list` /
    `--check` output. Default report-only.
  - A test in the docs-audit test suite proving: (a) parent open + all linked
    specs done => flagged; (b) parent open + a linked spec still open => NOT
    flagged; (c) parent already terminal => NOT flagged.
- Out of scope:
  - Auto-closing the parent (an RFC/PRD may spawn multiple specs/PRs and is only
    truly done when all implementing work is done; closing is a human decision).
  - Changing the loop/orchestration to propagate status (kept as a possible
    future follow-up; this change is the detection/safety-net half).
  - Reworking the index status buckets.

## Affected Area
- `.aai/scripts/lib/docs-audit-core.mjs` (classification engine).
- `.aai/scripts/docs-audit.mjs` (report surfacing) if the section is rendered
  there.
- `tests/skills/test-aai-docs-audit.sh` (new case).
- Possibly `.aai/scripts/generate-docs-index.mjs` only if a "Closeout
  candidates" line is cheap to surface; otherwise leave the index unchanged.

## Desired Behavior (To-Be)
- Running `node .aai/scripts/docs-audit.mjs --check` (or `--list`) over a repo
  where an RFC/PRD is non-terminal but all of its linked specs are `done`
  reports that parent as a `closeout-candidate` with the linked done spec id(s)
  and a suggested next step ("advance <ID> to done / accepted; record the
  implementing commit"). The verdict does not hard-fail `--check` by default
  (it is an advisory hygiene signal, not a broken-reference error), unless a
  later decision wires it into strict CI.

## Acceptance Criteria
- AC-001: Given a parent doc with `status` in {proposed, accepted, implementing}
  and at least one linked spec, where EVERY linked spec has `status: done`, the
  audit classifies the parent as `closeout-candidate` and lists the satisfying
  spec id(s).
- AC-002: Given the same parent but with at least one linked spec NOT `done`
  (draft/implementing/blocked), the parent is NOT classified as
  `closeout-candidate`.
- AC-003: Given a parent already in a terminal status (done/rejected/
  superseded/deferred), it is NOT classified as `closeout-candidate`.
- AC-004: The new classification is read-only — running the audit makes no edits
  to any document (no frontmatter mutation outside the operator-approved
  remediate mode).
- AC-005: Existing docs-audit behavior is unchanged for docs with no linked
  specs or no parent relationship (no new false positives); the existing
  docs-audit test suite still passes except for the one known pre-existing
  failure unrelated to this change.

## Verification
- `bash tests/skills/test-aai-docs-audit.sh` — new closeout-candidate case(s)
  green; pre-existing pass count preserved.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` over a fixture
  with RFC(proposed)+SPEC(done) => reports the RFC as a closeout-candidate.
- RED-proof: the new test must be observed failing before the engine change
  (the classification does not yet exist).

## Constraints / Risks
- Must not introduce false positives for docs whose "linked spec" association is
  indirect or many-to-one; reuse the engine's existing id/links resolution
  rather than inventing a second one.
- Keep it report-only by default to honor the "audit reports; operator decides"
  contract and avoid wrongly closing a multi-spec RFC.
- Touches the shared docs-audit engine consumed by intake gating, loop ticks,
  and CI — guard with tests and confirm no regression in the existing suite.

## Notes
- Origin: retrospective on the aai-docs-canon loop (RFC-0003) — diagnosis that
  the RFC->SPEC handoff leaves the parent's status orphaned from the
  implementation lifecycle, with no role or rule owning closeout.
- Related prior art: CHANGE-0003 (docs-audit verify mode) is the mechanism that
  closed RFC-0001; this change makes the same closeout need detectable
  proactively rather than only via a manual verify pass.
