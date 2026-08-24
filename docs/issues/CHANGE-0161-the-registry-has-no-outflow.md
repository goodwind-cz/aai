---
id: the-registry-has-no-outflow
number: 161
type: change
status: draft
user_visible: false
ceremony_level: 1
capability: aai-follow-ups
links:
  pr: []
  commits: []
---

# Change — the follow-up registry has an intake mandate and no outflow

Ceremony justification: prose-only policy change, a diagnosis document,
three learned rules, and append-only ledger status lines written by the
existing CLI; no script, no schema, no new test arm, no new guard surface.

## Summary
- `docs/ai/decisions.jsonl` holds 162 open follow-ups on `main` (f65ae56),
  opened over 13 days. Rides close one or two and open five; the trend is
  accelerating (net +39 on 2026-08-21 alone).
- Diagnosis (docs/analysis/registry-growth-diagnosis.md): the pipeline has a
  conservation law — every non-blocking review or validation finding MUST be
  remediated or filed (`SKILL_CODE_REVIEW` "WARNINGS POLICY WITH TEETH") —
  and the registry has no consumer: no pipeline step reads it, no expiry, no
  cap, no disposition cheaper than a permanent row. Nearly half the stock is
  assurance-strength debt about the test apparatus itself, and apparatus
  rides file 11-28 items each while product rides file 1-6, so fixing the
  registry's own subjects grows the registry.
- Correction: (1) give reviews an honest disposition that is NOT a registry
  row — "accepted residual", recorded in the review report, confined to P3
  assurance/maintenance findings with no observed bite and no false record;
  (2) make Planning a consumer — the spec's "Registry items closed by this
  scope" line must be derived from a live `follow-ups.mjs` listing; (3)
  triage the existing stock with a written per-item disposition, closing
  only what survives checking (duplicates, lesson-items resolved by a
  LEARNED rule, unfixable-historical rows, and an owner-gated P3
  accepted-residual batch whose approval is the merge of this PR).

## Motivation / Business Value
- The registry exists so "the ten that matter" are visible. At 162 open rows
  it hides them (the 2026-08-19 owner triage said exactly this at 67 open,
  dropped 22, and the stock regrew to 161 within five days).
- Every finding stays durable: the review and validation reports under
  docs/ai/ are tracked and cited by each row. The registry is a queue of
  intended work, not the archive of observations; this change makes that
  distinction explicit instead of implicit and violated.

## Scope
- In scope: `.aai/SKILL_CODE_REVIEW.prompt.md` (warnings policy disposition),
  `.aai/PLANNING.prompt.md` (registry consumer step),
  `docs/knowledge/LEARNED.md` (three rules that close three lesson-shaped
  rows), `docs/ai/decisions.jsonl` (append-only status lines via
  `follow-ups.mjs close`), `docs/analysis/registry-growth-diagnosis.md`
  (new), prompt-diet ledger companion edits if the corpus byte floor
  requires them.
- Out of scope: any `protected_paths_l3` file (WORKFLOW.md, state.mjs, ...);
  any new script, guard, test arm, or CLI flag — the diagnosis says new
  guard surface is the fuel, so the correction deliberately adds none;
  P1/P2 dispositions other than duplicate/lesson/unfixable (severity
  assigned by the filer is respected).

## Affected Area
- Code review ceremony (warnings disposition), planning ceremony (spec
  registry line), the follow-up registry stock.

## Desired Behavior (To-Be)
- A reviewer confronted with a P3 "this guard could be stronger" finding can
  record it as an accepted residual in the review report, with the reason,
  instead of minting a permanent registry row.
- A planner freezing a spec has read the open registry slice that overlaps
  the scope and either closes items with the ride or says why not.
- The open registry fits on two screens and every row is work someone
  intends to do.

## Acceptance Criteria

| Spec-AC    | Status | Evidence                                                                 |
|------------|--------|--------------------------------------------------------------------------|
| Spec-AC-01 | done   | SPEC-0149 AC table row 1; validation-20260824T090149Z round1 TEST-201    |
| Spec-AC-02 | done   | SPEC-0149 AC table row 2; validation round1 TEST-202                     |
| Spec-AC-03 | done   | SPEC-0149 AC table row 3; open=95, 68 appends 0 deletions, prefix proven |
| Spec-AC-04 | done   | SPEC-0149 AC table row 4; diagnosis sections 1-6                         |
| Spec-AC-05 | done   | SPEC-0149 AC table row 5; prompt-diet green, headroom 1174/2048          |

Detail (AC-00N maps to Spec-AC-0N in SPEC-0149):
- AC-001: SKILL_CODE_REVIEW's warnings policy offers an accepted-residual
  disposition confined to P3 assurance-strength/maintenance findings with no
  observed bite and no false record anywhere; the review report line must
  carry the reason; P1/P2 findings and anything that bit or left a false
  record still require remediation or a registry row.
- AC-002: PLANNING requires the spec's "Registry items closed by this scope"
  line to be derived from a live `node .aai/scripts/follow-ups.mjs list`
  pass over the scope's subjects.
- AC-003: every open follow-up on the base commit carries a written
  disposition in docs/analysis/registry-growth-diagnosis.md; ledger closures
  are appended only for dispositions that survive checking (duplicate with
  the primary named, lesson with the LEARNED rule cited, unfixable-historical
  with the reason, P3 accepted-residual batch with reopen-on-bite wording and
  owner approval = merge of this PR); open count on this branch is <= 100
  and no closure claims a fix that did not happen.
- AC-004: docs/analysis/registry-growth-diagnosis.md records the growth
  mechanism with the discriminating measurements (per-day flow, per-ride
  nets, source classes, closure lifespans, the 2026-08-19 natural
  experiment) and adjudicates the candidate hypotheses.
- AC-005: prompt-corpus governance is honored: tests/skills
  test-aai-prompt-diet.sh is green on this branch (with a ledger entry and
  TEST-012 pin bump if net prompt growth exceeds standing headroom).

## Verification
- `node .aai/scripts/follow-ups.mjs list | head -1` on the branch reports
  open <= 100; every appended status line names its reason and the base
  ledger remains a byte-exact prefix (`git diff main -- docs/ai/decisions.jsonl`
  shows appends only).
- `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-prompt-diet.sh`
  and `tests/skills/test-aai-follow-ups.sh` pass.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event --path <each
  new/edited doc>` passes.

## Constraints / Risks
- decisions.jsonl is append-only and contested by in-flight rides; the PR
  merge must union with base order preserved (base a byte-exact prefix).
- The accepted-residual disposition could be abused to silence real
  findings; the policy text confines it to P3, no-bite, no-false-record, and
  keeps the reason in a tracked report.
- No secrets referenced.

## Notes
- Implementation mode (user choice): direct — prose/docs/ledger scope; the
  evidence is suite greens plus checkable ledger appends, not new tests.
- Diagnosis and full triage table: docs/analysis/registry-growth-diagnosis.md.
