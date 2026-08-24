---
id: spec-the-registry-has-no-outflow
type: spec
number: 149
status: done
ceremony_level: 1
links:
  requirement: the-registry-has-no-outflow
  rfc: null
  pr:
    - 283
  commits:
    - ba4954a56ee84ed00c1dd4347a51a2708b2a4f82
---

# Spec — the follow-up registry gets an outflow

SPEC-FROZEN: true

Ceremony justification: prose-only policy change (two prompt paragraphs), a
diagnosis document, three LEARNED rules, and append-only ledger status
lines written by the existing CLI. No script, no schema, no new test arm,
no new guard surface; reversible by one revert of the prompt hunks (ledger
appends are history and stay).

## Links
- Requirement: docs/issues/CHANGE-0161-the-registry-has-no-outflow.md
- Diagnosis: docs/analysis/registry-growth-diagnosis.md
- Decision records: docs/ai/decisions.jsonl (append-only status lines)
- Technology contract: docs/TECHNOLOGY.md

## Problem in one paragraph

The follow-up registry grew from 0 to 163 open items in 13 days because the
pipeline mandates that every non-blocking finding become a permanent row
(SKILL_CODE_REVIEW "WARNINGS POLICY WITH TEETH") while nothing in the
pipeline ever reads the registry back — no consumer, no expiry, no cap, no
triage step — and because ~45% of the stock is assurance-strength debt
about the guard apparatus itself, which each fixing ride enlarges. Full
measurements and hypothesis adjudication:
docs/analysis/registry-growth-diagnosis.md.

## Implementation strategy
- Strategy: direct
- Rationale: the deliverables are prose (two prompt paragraphs, one analysis
  document, three learned rules) and append-only ledger lines produced by
  the existing follow-ups.mjs CLI. The evidence is grep-level presence
  probes, existing suites staying green, and checkable ledger arithmetic —
  there is no new module to grow a RED-first cycle around.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: docs and prompt prose only, but the ride edits the
  contested append-only ledger, so an isolated worktree cut from main keeps
  the in-flight rides' checkouts untouched.
- User decision: worktree (scratch worktree, branch change/the-registry-has-no-outflow, base main at f65ae56)
- Inline review scope: .aai/SKILL_CODE_REVIEW.prompt.md,
  .aai/PLANNING.prompt.md, docs/knowledge/LEARNED.md,
  docs/analysis/registry-growth-diagnosis.md, docs/ai/decisions.jsonl
  (appends only), docs/issues/CHANGE-0161-the-registry-has-no-outflow.md,
  this spec, and tests/skills/lib/prompt-diet-ledger.sh plus
  tests/skills/test-aai-prompt-diet.sh only if the corpus byte floor
  requires a ledger true-up.

## Registry items closed by this scope

68 items, enumerated with per-item reasons in
docs/analysis/registry-growth-diagnosis.md section 5: 6 duplicates (5a),
3 lessons closed by LEARNED rules shipped here (5b), 3 unfixable-historical
or environmental (5c), 56 P3 accepted residuals (5d). Owner sign-off for
the appended closures is the merge of the PR carrying them.

## Acceptance Criteria Mapping

- Maps to: AC-001
- Spec-AC-01: The WARNINGS policy in .aai/SKILL_CODE_REVIEW.prompt.md SHALL
  offer disposition (d) "accepted residual" recorded in the review report,
  confined to P3 assurance-strength/maintenance findings with no observed
  bite and no false record; P1/P2 and false-record findings SHALL keep
  dispositions (a)-(c) only.
- Verification: read the policy block; probe
  /usr/bin/grep -c "accepted residual" .aai/SKILL_CODE_REVIEW.prompt.md
  returns a nonzero count and the block names the P3 confinement.

- Maps to: AC-002
- Spec-AC-02: .aai/PLANNING.prompt.md SHALL require the spec's "Registry
  items closed by this scope" line to be derived from a live
  follow-ups.mjs list pass (or the literal none).
- Verification: read the REGISTRY CONSUMER bullet; probe
  /usr/bin/grep -c "REGISTRY CONSUMER" .aai/PLANNING.prompt.md returns 1.

- Maps to: AC-003
- Spec-AC-03: Every open follow-up on base f65ae56 SHALL carry a written
  disposition in the diagnosis document; the branch ledger SHALL contain
  base as a byte-exact prefix plus appended status lines only; open count
  SHALL be at most 100; every appended closure id SHALL appear in the
  diagnosis document's section 5 with its disposition class.
- Verification: node .aai/scripts/follow-ups.mjs list (first line, open
  count); git diff main -- docs/ai/decisions.jsonl shows additions only;
  cross-check script over the appended ids vs section 5 lists.

- Maps to: AC-004
- Spec-AC-04: The diagnosis document SHALL record the daily flow, source
  classes, per-ride nets, closure lifespans, the 2026-08-19 natural
  experiment, and the adjudication of the five candidate hypotheses.
- Verification: read docs/analysis/registry-growth-diagnosis.md sections
  1-3; each named measurement is present with its numbers.

- Maps to: AC-005
- Spec-AC-05: Prompt-corpus governance SHALL hold: the prompt-diet suite is
  green on this branch, with a JUSTIFIED_ADDITIONS entry and TEST-012 pin
  bump if net prompt growth exceeded standing headroom.
- Verification: bash .aai/scripts/aai-run-tests.sh
  tests/skills/test-aai-prompt-diet.sh exits 0.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC    | Description                                                    | Status       | Evidence | Review-By | Notes                            |
|------------|----------------------------------------------------------------|--------------|----------|-----------|----------------------------------|
| Spec-AC-01 | review policy offers a P3-confined accepted-residual record    | done | validation-20260824T090149Z round1 TEST-201: both grep probes return 1 | —         | prose only, no new guard         |
| Spec-AC-02 | planning derives the registry line from a live listing         | done | validation-20260824T090149Z round1 TEST-202: probe returns 1 | —         | the registry gains a consumer    |
| Spec-AC-03 | every open item dispositioned; open count at most 100          | done | validation round1 TEST-203/204/207: open=95, diff 68 additions 0 deletions, prefix proven, 68/68 ids in section 5, suite green | —         | appends only, base is a prefix   |
| Spec-AC-04 | diagnosis document carries the discriminating measurements     | done | validation round1 TEST-205: sections 1-6 present with numbers | —         | section 6 lists the unverified   |
| Spec-AC-05 | prompt-diet governance green on this branch                    | done | validation round1 TEST-206: All tests passed, headroom 1174/2048, no true-up owed | —         | headroom absorbed the growth |

## Implementation plan

1. Diagnosis document with triage dispositions (done before freeze — the
   analysis is the input to this spec, not its output).
2. Prompt edits: SKILL_CODE_REVIEW disposition (d); PLANNING registry
   consumer bullet.
3. LEARNED.md: three rules closing the three lesson rows.
4. Ledger appends via follow-ups.mjs close, dry-run on a scratch copy
   first, then the real file; verify the base remains a byte-exact prefix.
5. Prompt-diet true-up if TEST-010 reports a breach.
6. Suites: prompt-diet, follow-ups, docs-audit strict on touched docs.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                 | Description                                                            | Status  |
|----------|------------|-------------|--------------------------------------|------------------------------------------------------------------------|---------|
| TEST-201 | Spec-AC-01 | unit        | .aai/SKILL_CODE_REVIEW.prompt.md     | disposition (d) present once, P3-confined, no-bite no-false-record      | pass    |
| TEST-202 | Spec-AC-02 | unit        | .aai/PLANNING.prompt.md              | REGISTRY CONSUMER bullet present once, names follow-ups.mjs and the line | pass    |
| TEST-203 | Spec-AC-03 | integration | docs/ai/decisions.jsonl              | open count at most 100; git diff vs main shows appends only             | pass    |
| TEST-204 | Spec-AC-03 | integration | docs/analysis/registry-growth-diagnosis.md | every appended closure id appears in section 5 under its class    | pass    |
| TEST-205 | Spec-AC-04 | unit        | docs/analysis/registry-growth-diagnosis.md | sections 1-6 present with the named measurements                  | pass    |
| TEST-206 | Spec-AC-05 | integration | tests/skills/test-aai-prompt-diet.sh | suite green on this branch                                              | pass    |
| TEST-207 | Spec-AC-03 | integration | tests/skills/test-aai-follow-ups.sh  | follow-ups suite green after the appends                                | pass    |

## Verification

- All TEST-2xx rows executed on this branch with output read, not exit
  codes alone; PASS requires all seven green and every Spec-AC terminal.

## Evidence contract

- Validation report under docs/ai/validation/ names each TEST-2xx with the
  observed line quoted; the follow-ups list first line is quoted verbatim
  (shown/open/closed/total); the ledger prefix check quotes the git diff
  stat line.
