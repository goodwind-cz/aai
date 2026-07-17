---
id: single-dual-verdict-review
type: rfc
number: 8
status: done
links:
  research: RES-0001
  spec: spec-single-dual-verdict-review
  pr:
    - 62
  commits:
    - 3619b43
---

# RFC — Replace Two-Stage Code Review With a Single Dual-Verdict Reviewer

## Context

### Problem or opportunity

AAI's code review (SKILL_CODE_REVIEW) runs two stages: spec compliance first,
code quality second. RES-0001 (finding F4) surfaced two facts against it:

1. **Our own telemetry**: review + remediation wall-clock ≈ 88% of straight
   implementation time (METRICS.jsonl, 65 runs across 11 work items). Review
   is AAI's costliest pipeline stage and has never been measured for its
   token cost/benefit.
2. **External eval evidence**: Superpowers ran the same two-reviewer pattern
   and *removed* it in v6.0 after 25 evals showed a single reviewer returning
   TWO verdicts (spec compliance + quality) in one pass delivers equal
   quality at ~50% of the tokens and ~2× the speed. Their v5.0.6 evals had
   already killed spec/plan review loops for the same reason (zero measured
   quality gain at ~25 min overhead each).

This session's practice supports the diagnosis: every review dispatched today
was in fact ONE agent performing both stages sequentially in one context —
the "two stages" are already a single pass in practice; the prompt just makes
it verbose and the evidence contract redundant.

### Drivers/constraints

- Cost: with CHANGE-0010's token capture landing, before/after measurement is
  finally possible; the change should be validated by our own METRICS, not
  only by Superpowers' evals.
- Quality floor: review is the last defense before PR. Any change must keep
  or raise the defect-catch rate (today's reviews caught real defects: CR-1,
  W1/W2 series, the ISSUE-0003→0006 traceability slip).
- Keep AAI's evidence discipline (file:line, failure scenario, warnings
  policy H6, external-review-response H3) — the ceremony around findings is
  not the target, the duplicated pass structure is.
- Anti-gaming: RES-0001 recommended adopting Superpowers' protocol elements
  regardless of pass count (read-only reviewer, orchestrator banned from
  coaching/pre-rating, "cannot verify from diff" verdict, file-based diff
  handoff).

## Proposal

### Recommended option

**Option B — single reviewer, dual verdict, anti-gaming hardened.** One
review dispatch returns two independent verdicts in one structured block:

- `spec_compliance: pass|fail` — diff vs frozen AC table (deviations listed);
- `code_quality: pass|fail` — real defects ranked BLOCKING/NON-BLOCKING with
  file:line + failure scenario;
- plus `cannot_verify: [...]` — claims the diff alone cannot substantiate
  (new verdict class, forces honest gaps instead of silent PASS).

Protocol hardening (adopted with the merge):
1. Reviewer context is read-only on code (already practiced, now contract).
2. The dispatching orchestrator MUST NOT characterize expected findings,
   pre-rate severity, or instruct the reviewer to skip areas ("no coaching").
3. Diff handoff by ref/path list, not pasted inline (keeps the expensive
   context clean; already practiced).
4. Overall review status = pass only when BOTH verdicts pass; warnings keep
   the SPEC-0013 H6 disposition duty (remediate or promote).

Measurement gate (makes this reversible): run the new shape for the next
5+ reviewed scopes, compare METRICS (review tokens, wall-clock, remediation
cycles, defects caught post-merge) against the two-stage history. If quality
regresses, revert is a one-file prompt change.

### Rationale

- Matches measured external evidence AND our observed practice (the two
  stages already execute as one pass; the structure only inflates the prompt
  and the report).
- SKILL_CODE_REVIEW is 766 lines — the largest prompt in the repo
  (RES-0001 F3); the rewrite is also its diet (target ≤ 250 lines).
- The `cannot_verify` verdict converts today's silent gaps into named ones.

## Alternatives Considered

- **Option A — keep two-stage as is.** Pros: no change risk; the pattern did
  catch real defects today. Cons: those catches came from the reviewer's
  single pass, not from the stage separation; costs stay at ~88% of
  implementation time with no measurement plan. Rejected: keeps paying for
  structure with no evidence it earns its cost.
- **Option C — size-adaptive: single dual-verdict for S/M scopes, two-stage
  for L.** Pros: hedges the quality risk on big diffs. Cons: two prompt
  shapes to maintain; no evidence the second pass helps even on L (Superpowers
  measured across sizes); complexity where the measurement gate already
  provides the hedge. Rejected for now; revisit if the measurement gate
  shows size-correlated regressions.
- **Option D — reviewer panel (2-3 parallel reviewers, majority).** Pros:
  diversity catches more. Cons: multiplies the cost we are trying to halve;
  RES-0001 filed panel review under "do NOT adopt" absent evidence. Rejected.

## Consequences

### Technical impact

- SKILL_CODE_REVIEW.prompt.md rewritten (766 → ~250 lines): one pass, dual
  verdict block, anti-gaming contract, H3/H6 retained verbatim.
- `state.mjs set-code-review` unchanged (status still pass/fail); the report
  template gains the dual-verdict + cannot_verify sections.
- Orchestration dispatch (orchestration-dispatch.mjs rule 13) unchanged —
  same role, same gate; only the role prompt changes.
- METRICS: no schema change; measurement uses existing fields + tokens
  (CHANGE-0010).

### Operational impact

- Review dispatches get cheaper and faster; a five-scope measurement window
  validates before the change is considered settled.

### Migration/compatibility notes

- One prompt file + wrapper description; vendored projects pick it up via
  /aai-update. Old reports remain valid history.

## Risks

- **Quality regression on spec compliance** (the dedicated first pass forced
  AC-by-AC reading). Mitigation: the dual-verdict block REQUIRES the AC table
  walk as evidence for the spec_compliance verdict; measurement gate.
- **Verdict blending** (one context letting quality impressions soften
  compliance findings). Mitigation: verdicts must cite disjoint evidence
  sections; `cannot_verify` legitimizes "I could not check this".
- **Anti-gaming rules ignored under autonomy** (orchestrator writes the
  dispatch prompt). Mitigation: the no-coaching rule goes into
  SUBAGENT_PROTOCOL (same tier as the MODEL field), grep-wired by tests.

## Open Questions

- Should the measurement window (5 scopes) be a hard gate recorded in the
  SPEC's AC table, or an operator judgment call at wrap-up?
- Does the remediation loop change (re-review after remediation currently
  re-runs both stages — single pass makes this cheaper automatically)?
- Adopt Superpowers' whole-branch final review on the most capable model as
  a separate, additive step for L scopes — in this RFC or a follow-up?

## Approvals

- Required approvers (roles/names): Project owner (ales@holubec.net).

## Notes

- Sources: RES-0001 F4 + Superpowers sweep (v6.0.0 release evidence, 25-eval
  comparison; v5.0.6 review-loop removal); AAI METRICS.jsonl role-duration
  analysis (review+remediation ≈ 88% of implementation wall-clock).
- Decision deliberately awaits operator direction — this RFC captures the
  proposal; no SPEC or implementation exists yet.
- Decision 2026-07-16: ACCEPTED by project owner (ales@holubec.net) —
  "schvaluji rfc, mergni a rozjed". Option B confirmed; proceed to SPEC and
  implementation with the 5-scope measurement gate.
