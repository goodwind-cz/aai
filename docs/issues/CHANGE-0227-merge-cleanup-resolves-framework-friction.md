---
id: merge-cleanup-resolves-framework-friction
type: change
number: 227
status: draft
capability: directed-merge-and-post-merge-cleanup
user_visible: true
links:
  pr: []
  commits: []
---

# Resolve framework-owned merge friction without handing it to the user

## Summary

An authorized merge and its cleanup must continue through ordinary, recoverable
AAI problems without requiring the user to diagnose the framework or say
"continue". When a real user decision is necessary, present concrete options
with a recommended default and continue after that choice. A raw refusal is
diagnostic input for the framework, not a sufficient user-facing outcome.

## Motivation / Business Value

During PR #485, the merge succeeded but cleanup stopped with
`REFUSE overlap docs/ai/roadmap.yaml`. The agent ended its turn and required the
owner to say "Pokracuj" before investigating and resolving its own leftovers.
The owner explicitly rejected this interaction: users should not have to solve
framework problems. This is a recurring class already partly addressed by
CHANGE-0210, not merely a request to suppress one error message.

## Scope

In scope:

- The merge skill's handling of cleanup refusals and recoverable stops, the
  deterministic cleanup engine, their regression tests and existing product
  documentation.
- Evidence-backed classification into automatic recovery, a user decision
  menu, and a genuinely external blocker with a useful next action.
- The observed roadmap overlap, missing delivery attribution, stale draft
  copies and related framework-generated leftovers from the same merge.
- A reusable interaction rule in the vendored workflow: the framework owns
  diagnosis and recovery; the user decides product intent or meaningful risk.

Out of scope:

- Broad rewrites of unrelated skills or the whole smaller-Node-core RFC.
- Granting new merge authorization, weakening review/CI/head checks or deleting
  ambiguous user work automatically.
- Modifying already-merged Git history or adding a new orchestration service.

## Affected Area

`.aai/SKILL_MERGE.prompt.md`, `.aai/scripts/merge-cleanup.mjs`, the relevant
shared interaction contract, `tests/skills/test-aai-merge-cleanup.sh`, existing
platform coverage where behavior differs, and
`docs/product/directed-merge-and-post-merge-cleanup.md`.

## Desired Behavior (To-Be)

The existing merge instruction covers routine diagnosis, archive-first recovery
and cleanup. For a recognized framework-owned condition, inspect the actual
state, preserve recoverable bytes, apply the supported remedy and resume the
canonical engine in the same interaction. Do not require another merge command
or a generic "continue" for this work.

When evidence is insufficient or a change would affect user-owned work, ask one
decision question with two or three concrete options and a recommendation.
Explain the effect of each option in ordinary language. The agent performs the
selected action; the user does not receive a framework debugging assignment.
For an external blocker such as unavailable credentials or a service outage,
explain the smallest actual user action needed instead of presenting a raw code
as the conclusion.

Keep low-level fail-closed refusals where they protect data. Replace the current
unconditional stop-and-relay skill behavior with recovery or decision handling;
never turn a refusal into an unverified success. Bound retries and detect lack
of progress so recovery cannot loop indefinitely.

## Acceptance Criteria

- AC-001: A supported, recoverable framework-owned cleanup condition is resolved
  and the canonical engine resumes within the original authorized interaction;
  no additional "continue" or repeated merge direction is required.
- AC-002: A PR #485 fixture includes both parent-RFC and child-change roadmap
  additions already represented in the incoming base, with the child changing
  from active to done. Cleanup preserves the active parent and completed child,
  archives the original bytes before mutation, and completes without a raw
  overlap refusal becoming the final user response.
- AC-003: Missing `links.pr` attribution, as observed in CHANGE-0214, does not
  silently make recoverable ownership unrecognizable. Proven identity permits
  the supported recovery; insufficient or conflicting proof produces a decision
  menu without guessing ownership or rewriting historical records.
- AC-004: Proven superseded draft copies and generated artifacts are handled
  automatically with recoverable archives. Divergent or ambiguous drafts lead
  to a concrete menu with a recommended preservation option; merely listing
  `leftover_draft` and ending is not sufficient handling.
- AC-005: A genuinely ambiguous or destructive choice presents two or three
  options with a recommended default and explains their user-visible effects.
  Choosing one resumes the workflow; the user is not asked to edit ledgers,
  repair Git metadata or devise commands.
- AC-006: Head changes, rewritten ledgers, unpushed work, unrelated edits and
  unverifiable identity remain protected. Automated recovery does not bypass
  pinned-head authorization, branch leases, review/CI gates, archive verification
  or append-only history.
- AC-007: Interrupted recovery is resumable and idempotent; bounded retries
  terminate in an actionable decision or external-blocker explanation rather
  than a retry loop, duplicate records or a false completion claim.
- AC-008: The final report clearly distinguishes merge completion, cleanup
  completion and any user decision still pending, using plain language. The
  executable behavior and vendored skill instructions agree; a local learned
  note alone does not satisfy this change.

## Verification

Use isolated Git fixtures for the observed PR #485 state and adverse controls,
including absent PR links, parent/child roadmap overlap, identical versus
divergent drafts, archive failure, interruption and a moved head. Exercise the
real cleanup engine and the skill's refusal-to-recovery/menu routing. Verify
preserved file bytes, ledger prefixes, exact resulting roadmap entries, bounded
attempts and absence of unauthorized deletion or merge.

Run the focused merge-cleanup suite through the canonical test dispatcher.
Planning specifies exact commands, supported recovery classes and test mapping;
this intake does not claim implementation or test results.

## Constraints / Risks

- Keep deterministic mutation and recovery rules in the existing engine and
  canonical writers; do not require ad hoc manual normalization by the agent.
- Derive ownership from inspectable evidence. Missing metadata is a framework
  defect to handle, not permission to broaden the cleanup target.
- Preserve divergent content before any approved removal and retain the
  framework's single-writer and append-only disciplines.
- No secret is referenced; secrets preflight is not applicable.

## Notes

Owner request, translated from Czech, 2026-10-21: the merge problem was a typical
case to resolve automatically or present as a choice, rather than stop on it;
the user does not want to solve framework problems.

Observed evidence: PR #485 merged as
`89e7150e3bdf38c4c61bacacf27a8f9d07cd05af`; the original overlap and subsequent
archive-first workaround are preserved under
`docs/ai/archive/merge-cleanup/pr-485/overlap-resolution/`. After explicit
continuation, the canonical engine synchronized main and removed the worktree
and branches, while retaining three draft files. The merged intake/spec had
empty `links.pr` lists, so `deliveredDoneDocs` could not attribute their refs.

Current `.aai/SKILL_MERGE.prompt.md` explicitly directs the agent to relay
exit-3/4 refusals and stop. This request changes that interaction contract while
retaining the engine's data-protection checks. It is a follow-on to
CHANGE-0210 and the existing capability, not a new product capability.

Implementation mode: leave the decision to Planning unless the owner chooses
otherwise. The behavioral, workflow and data-integrity surfaces warrant a full
TDD recommendation at planning time.
