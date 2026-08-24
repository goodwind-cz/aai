# Code Review — the-registry-has-no-outflow (dual verdict)

Reviewer: the same session agent that authored the scope (fresh-eyes ride,
2026-08-24). CONFLICT DECLARED: this is not an independent review; the PR's
external bot reviews and the owner's merge decision are the independent
gates. This report walks the AC table and the diff honestly, but its
independence is limited and stated.

Scope reviewed (clean diff vs main at f65ae56):
.aai/SKILL_CODE_REVIEW.prompt.md, .aai/PLANNING.prompt.md,
docs/knowledge/LEARNED.md, docs/analysis/registry-growth-diagnosis.md,
docs/ai/decisions.jsonl (68 appended lines),
docs/issues/CHANGE-0161-the-registry-has-no-outflow.md,
docs/specs/SPEC-0149-spec-the-registry-has-no-outflow.md.

## spec_compliance: PASS

AC-table walk (all rows terminal `done` with evidence citing validation
round 1; report: docs/ai/validation/validation-20260824T090149Z-the-
registry-has-no-outflow-round1.md):
- Spec-AC-01 policy disposition (d): present once, P3-confined, no-bite,
  no-false-record clauses all in the block; (a)-(c) unchanged. VERIFIED.
- Spec-AC-02 REGISTRY CONSUMER bullet in PLANNING: present once, names the
  CLI and the spec line, placed beside the companion-obligations check so
  planners read both. VERIFIED.
- Spec-AC-03 triage: 68 appended status lines, 0 deletions, base ledger a
  byte-exact prefix (Buffer compare), open 163 -> 95, every appended id
  listed in diagnosis section 5 under its class. VERIFIED.
- Spec-AC-04 diagnosis: sections 1-6 with the tables. VERIFIED by reading.
- Spec-AC-05 prompt-diet: suite green, headroom 1174/2048 absorbed the
  prompt growth, no ledger true-up needed. VERIFIED.

## code_quality: PASS

BLOCKING: none found.
NON-BLOCKING findings and dispositions (per the WARNINGS POLICY, including
the new (d) this scope introduces — used once, on itself, deliberately):
- NB-1: the LEARNED rule for NUL scanning gives a node one-liner with a
  placeholder `f` variable the reader must fill; a copy-paste-runnable form
  would be kinder. Disposition: accepted residual: cosmetic wording in a
  knowledge file; no behavior, no false record.
- NB-2: the diagnosis doc hard-embeds today's counts (163/95/68), which
  will drift as the ledger moves. Disposition: remediated in-place — the
  doc pins its measurement to main@f65ae56 in its Scope line, so the
  numbers are stamped to a commit, not to "now".
- NB-3: triage scripts (triage-plan.mjs, run-triage.mjs) live in scratch
  and are not committed; the PR carries their OUTPUT (the appended lines +
  the section-5 lists), which is re-checkable without them. Disposition:
  accepted residual: committing one-shot scripts would add exactly the
  kind of surface this scope argues against; the verification is a
  ten-line re-derivation from the ledger.

## cannot_verify (mandatory list)

- Whether the 56 accepted-residual P3 findings are truly biteless — only
  their own filed text and evidence were read; the guards were not
  re-mutated here. The drop wording says "reopen on first bite".
- Whether the flake disposition for fu-layer-profiles-sync-idempotence-
  flake holds — not reproduced in this session.
- CI behavior of the full framework sweep on this branch (20-28 min,
  serial) — left to the PR's CI run.
- The merge-time union of docs/ai/decisions.jsonl against whatever lands
  on main first — the PR description carries the prefix-order instruction.

Verdict: PASS (conditional on the declared conflict; external review and
owner merge are the independent checks).
