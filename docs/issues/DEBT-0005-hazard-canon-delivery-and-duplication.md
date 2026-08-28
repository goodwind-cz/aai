---
id: hazard-canon-delivery-and-duplication
type: techdebt
number: 5
status: draft
links:
  pr: []
  commits: []
---

# The rules that bind agents are prose whose delivery, uniqueness and counts nothing asserts

## Debt Summary
- The Standing hazards live in `.aai/SUBAGENT_CONTRACT.md` on the argument that every
  dispatch copies them in. Nothing assembles that payload and no test pins the ordering,
  the same file states one rule twice, a runtime warning tells agents to do the exact
  thing a hazard forbids, and a count printed as evidence is asserted by nobody. Six
  registry items, one mechanism: canon that is stated and not enforced.

## Root Cause
- The contract is a document, not a build artifact. Its guarantees ("the subagent always
  receives this", "no rule is stated twice", "this count is current") are properties of a
  process, and the process is an agent following prose.

## Current Cost / Risk
Verified in a disposable clone of `origin/main` (`c6b32d0`):

- `fu-contract-prefix-order-unenforced` (P2). The cap argument rests on the CONTRACT being
  copied stable-first into the dispatch prefix. That ordering lives only as prose at
  `.aai/ORCHESTRATION_PARALLEL.prompt.md:142-143` ("Context: a copy of
  .aai/SUBAGENT_CONTRACT.md (stable, first), then scope and inputs (variable, last — keeps
  the prefix cacheable)"). No code assembles the payload and no test pins the ordering:
  SPEC-0110 TEST-033 compares the file-bytes hash, not the assembled prompt. When the copy
  is omitted — as it was for the Validation dispatch of the very scope that filed this —
  the hazards are strictly WORSE placed than before: previously unskippable dispatch prose,
  now behind a Read the subagent may skip, with the cap re-based 60 to 90 on a cost model
  that only holds when the copy is present.
- `fu-contract-ledger-rule-stated-twice` (P3). Measured with
  `/usr/bin/grep -n 'append-only' .aai/SUBAGENT_CONTRACT.md`: hits at lines 27, 31 and 72.
  HAZ-LEDGER states the rule at `:27-31`, and the Single-writer MAY-write list restates it
  at `:72` ("docs/ai/EVENTS.jsonl via append-event.mjs (the append-only, commutative audit
  log)"). Spec-AC-05 pins that no rule sentence is duplicated, but its two hygiene arms
  compare CONTRACT against PROTOCOL, so an INTRA-file duplication passes them.
- `fu-metrics-flush-advises-git-restore` (P3). `.aai/scripts/metrics-flush.mjs:801-803`
  emits "EVENTS is append-only per RFC-0001 — restore from git before continuing" to
  whatever agent runs the flush: it tells the agent to run a restoring git command on a
  tracked append-only ledger in the same sentence that cites the append-only rule. That is
  HAZ-RESTORE's forbidden move, recommended by the runtime. The honest remedy for a
  detected shrink is to re-append, not to restore.
- `fu-usage-marker-omission-unfixable` (P2). A run appended without a usage marker cannot
  be corrected: `append-run` only appends, STATE hand-edits are forbidden, and the only
  recovery is toggling `usage_capture_gate` off and back. Hit for real during a close; the
  recovery requires disarming the gate to get past it, which is the carve-out shape this
  repository keeps removing. The 2026-08-11 entry that first recorded this defect is
  itself malformed (no id, no severity), so it never appeared in any severity filter.
- `fu-allowlist-count-is-prose-not-asserted` (P2). "TEST-011's path/group count lives only
  in a `log_pass` string and a comment, so it goes stale silently on every merge that adds
  a group and no arm ever notices." Measured three times in one day on PR 280: 31 stale
  before the edit, 32 after, 34 after merging main — the suite stayed GREEN each time while
  the number it printed was wrong. NOT INDEPENDENTLY LOCATED: searching the clone for that
  arm (`/usr/bin/grep -rn 'TEST-011'` across `tests/skills/*.sh`, plus greps for
  "case groups" and allowlist counters) did not resolve it to a file and line. Planning
  must find the arm before scoping this member.
- `fu-empty-path-cd-stays-in-shipping-repo` (P2) is the scar HAZ-CD cites, and is the
  clearest demonstration that a hazard in prose does not bind: the incident happened after
  the hazard was written. It is filed in full detail with the agent-shell boundary intake
  and is listed here only because it belongs to this registry group.

## Target State
- The contract's delivery is a property of the payload, not of an agent's memory: either
  the dispatch payload is assembled by code that puts the contract first, or a test reads
  an actual dispatch payload and asserts the ordering.
- Each rule appears once in the corpus, and the uniqueness check covers intra-file
  duplication.
- No runtime string recommends an action a hazard forbids.
- Every number printed as evidence is asserted by the arm that prints it, or is not
  printed.
- A missing usage marker has a forward-only repair path that does not require disarming
  the gate.

## Scope
- In scope: the delivery, uniqueness and self-assertion of the hazard/contract corpus, and
  the two runtime surfaces that contradict it (`metrics-flush.mjs`, the usage-marker
  recovery path).
- Out of scope: the CONTENT of the hazards. They are not being rewritten here.
- Out of scope: the structural boundary that would make HAZ-SCRATCH unnecessary — filed
  separately as the agent-shell intake.

## Plan / Migration
- Pin the dispatch prefix ordering with a test that reads an assembled payload, not a file
  hash.
- Extend the duplication hygiene arm to compare a file against itself.
- Replace the `metrics-flush.mjs` advice with a re-append instruction.
- Locate the TEST-011 counter, then either assert the count or delete it from the pass
  line.
- Design a forward-only correction for a missing usage marker.

## Verification
- Deleting the contract copy from a dispatch payload fails a test.
- Duplicating any rule sentence within `.aai/SUBAGENT_CONTRACT.md` fails the hygiene arm.
- `/usr/bin/grep -rn 'restore from git' .aai/scripts` returns nothing.
- Adding a case group changes the asserted count or reddens the arm.

## Constraints / Risks
- Assembling the dispatch payload in code is a real change to how the orchestrator works
  and interacts with the prompt-cache economics the cap argument rests on.
- The prompt-diet ledger governs every byte added to `.aai/**`; any prose change here owes
  a ledger entry and a TEST-012 bump.

## Notes
- Registry ids covered: `fu-contract-prefix-order-unenforced`,
  `fu-contract-ledger-rule-stated-twice`, `fu-metrics-flush-advises-git-restore`,
  `fu-usage-marker-omission-unfixable`, `fu-allowlist-count-is-prose-not-asserted`,
  `fu-empty-path-cd-stays-in-shipping-repo` (detailed in the agent-shell intake).
