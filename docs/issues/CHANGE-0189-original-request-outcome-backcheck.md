---
id: original-request-outcome-backcheck
type: change
number: 189
status: done
user_visible: true
capability: original-request-outcome-backcheck
links:
  pr:
    - 388
  commits:
    - a884179d81201c3a3ae263607682ab63a0594837
---

# Change — Verify original requirements and persisted outcomes

## Summary

Extend existing AAI validation so it explicitly checks that the planned contract
preserves the original request, that evidence describes the actual consumed
result, and that changed or externally stale targets cannot inherit an earlier
completion claim.

## Motivation / Business Value

A scope can satisfy its own spec while omitting a requirement from the original
request. Similarly, a successful command or preview can refer to an unsaved,
wrong-path, wrong-version or obsolete result. Existing independent validation and
current-tree freshness controls provide a foundation; this change makes the
remaining checks explicit and verifiable within that workflow.

Source: [LongHorizon research](../specs/RES-0004-longhorizon-harness-adoption.md).
The operator approved the proposed next step with “pokracuj” after a concrete
proposal to prepare this change through Planning.

## Scope

- In scope: the existing validator's original-request backcheck; conditional
  evidence for saved artifacts/application state; evidence identity and freshness
  at the validation handoff; focused regression scenarios and downstream wiring.
- Planning must identify the smallest existing seams and distinguish semantic
  judgments from deterministic report/identity checks.
- Preserve current-tree invalidation, maker/checker separation, single-writer
  state ownership and explicit handling of unknown evidence.
- Out of scope: a new orchestrator or validator role, importing LongHorizon,
  installing dependencies, a GUI execution service, general rollback, benchmark
  execution, external outreach, or unrelated workflow cleanup.
- The initial continuation produced the intake, frozen spec and work-item brief.
  The subsequent explicit aai-ship invocation authorizes implementation through
  independent validation, review and a pull request under the frozen contract.

## Affected Area

- `.aai/VALIDATION.prompt.md` and its existing report generation/consumption seam.
- `.aai/templates/BRIEF_TEMPLATE.md` or the current evidence handoff, if needed.
- Existing report/state/freshness helpers and focused tests, as determined by
  Planning after reading their actual implementation.
- Prompt-diet accounting and profile classification only when required by the
  resulting file scope. No parallel state database or duplicate report authority.

## Desired Behavior (To-Be)

1. The independent validator inventories material constraints from the original
   intake/request, including preservation and exact-target requirements, and
   compares them with the spec. An omission or weakening is recorded as a gap;
   checking the spec alone cannot justify acceptance.
2. For each applicable outcome, evidence identifies the exact consumed target
   and verification operation. Saved/exported/applied state is confirmed by a
   read-back, reopen or equivalent independent observation when relevant.
3. Required unknown, violated, wrong-target or stale evidence prevents PASS.
   A prose assertion is not independent proof. Mechanical checks validate the
   report and declared evidence identity; they do not claim to decide arbitrary
   natural-language truth or to trust a model-generated label as ground truth.
4. A resumed run reuses existing AAI freshness checks for repository state.
   External/dynamic targets require a current observation or a demonstrably
   valid target revision. An interruption itself does not prove that an immutable
   artifact changed, and should not force unrelated work to repeat.
5. Ordinary repository changes retain a concise evidence contract. GUI/account/
   persistence-specific fields apply only to relevant targets; extra historical
   restrictions must not be invented beyond the original request.

## Acceptance Criteria

- AC-001: A fixture in which a spec omits or weakens a material original-request
  constraint is refused despite otherwise passing implementation evidence. A
  complete, aligned control case is accepted.
- AC-002: A preview-only or wrong-target fixture is refused where persistence
  is required. Independent read-back of the exact saved target is accepted.
- AC-003: Changed-target evidence and an unverified dynamic target after resume
  are refused until refreshed. A matching immutable target and fresh evidence
  are accepted without an unnecessary restart of completed work.
- AC-004: Missing/unknown/contradictory required evidence is refused, including
  superficially complete reports. Tests demonstrate the gate was reached rather
  than accepting a vacuous failure earlier in the pipeline.
- AC-005: The existing validation handoff actually invokes the resulting checks;
  a disconnected schema or an unused helper is insufficient. Existing current-tree
  invalidation and independent validation remain effective.
- AC-006: A normal code-only change passes through the same workflow without
  fabricated GUI fields, duplicate state or new runtime dependencies.

## Verification

Planning will map each criterion to a named command, artifact and observable,
using the canonical test wrapper. Include a pre-change failing observation,
positive controls and tests crossing the real report-to-verdict boundary.

Semantic interpretation is evaluated with explicit adversarial cases and reported
limitations. Do not describe a parser test as proof that an LLM always identifies
every omitted requirement. Existing passing framework tests are not a substitute
for a case that fails without this change.

## Constraints / Risks

- Follow the dependency-free technology contract and platform compatibility.
- Avoid converting a small verification improvement into a general evidence
  database, content-addressed storage service or new orchestration protocol.
- External observations can themselves be stale or incomplete; identify the
  verification horizon and uncertainty without claiming full environment rollback.
- No secrets are referenced by this planning scope.
- Research's five human minutes belong to the research intake, not this change.

## Notes

- Implementation-mode preference: the operator chose to leave the decision to
  Planning. No intake-sourced strategy override applies to this change.
- The initial continuation covered intake and Planning. The Delivery
  authorization below supersedes that boundary; implementation follows the
  frozen spec and applicable workflow gates.
- Roadmap priority must remain explicit: this user-selected planning scope is
  not silently added as a new roadmap pair or paired maintenance allowance.

## Delivery authorization

On 2026-09-23 (Europe/Prague), the operator explicitly invoked `aai-ship` for
this prepared scope. This supersedes the earlier Planning-only boundary.
Autopilot defaults select the recommended worktree and preserve Planning’s TDD
strategy. Human intake time for this continuation is unknown (null); the five
minutes previously reported belong to the research. No merge is requested.

## Implementation base correction

The operator subsequently required work to use the latest `origin/main`
("ale mel by jsi to delat nad poslednim origin main"). The delivery worktree
was created from fetched `origin/main` at
`f84f84ab93348a321b6af803ba53ce0a526f53fc`, and a second successful fetch
confirmed that base before validation. Later remote movement must be checked
before opening the pull request.
