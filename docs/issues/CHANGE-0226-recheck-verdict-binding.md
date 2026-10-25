---
id: recheck-verdict-binding
type: change
number: 226
status: done
capability: lean-agent-context
parent: smaller-node-core-and-faster-feedback
links:
  pr: []
  commits: []
---

# Bind re-check verdicts to STATE and turn delta re-checks on by default

## Summary
- RFC-0017 phase 4, second slice. The delta re-check mode from CHANGE-0225 /
  SPEC-0250 (PR #498) ships opt-in because its eligibility trusts `check_*`
  stamps in the tracked `docs/ai/EVENTS.jsonl`, which a delta can rewrite or
  forge (uncommitted, amend, rebase, squash, pre-base commit, `git replace`,
  hand append). This slice binds each judged round's verdict to state the
  delta cannot write, so eligibility no longer trusts the tracked ledger.
- Owner decision 2026-10-24 (menu answer "Zapnout po ověření"): once
  validation proves the binding closes every known shape, delta becomes the
  default; `AAI_RECHECK_MODE=full` keeps a per-run opt-out. The owner confirms
  the flip at the merge menu.
- The ride also signs the owner-directed merge of PR #498.

## Motivation / Business Value
- Repeat Validation and Code Review rounds hold about a third of a ride's
  tokens and half its time (SPEC-0250 baseline). The delta payload is about a
  third of a full one, but it saves nothing while it is off.

## Scope
- In scope:
  - Planning designs the binding: where the verdict record lives (gitignored
    STATE written by state.mjs, which already refuses subagent writes, or an
    equivalent store the delta cannot edit), what it binds (role, ref, the
    head the checker was handed, the security marker of its report, the
    report path and digest), and how eligibility reads it instead of the
    EVENTS stamps. EVENTS stamps may stay as telemetry.
  - Eligibility refuses delta when the bound record is missing, ambiguous,
    or disagrees with the tree (for example a bound head that is not an
    ancestor, a report whose digest changed).
  - TEST-2742 (the pinned residual) flips to full for every shape it pins,
    and new tests cover each shape the reviews found: uncommitted rewrite,
    amend, rebase, squash, rewrite committed before the base, `git replace`,
    forged hand append, merge `-s ours`.
  - The default flips to delta (opt-out `AAI_RECHECK_MODE=full`), with the
    spec, protocol, WORKFLOW and CHANGELOG updated, once the above is
    proven. If validation cannot prove it, the flip is left out and the
    owner is told.
  - Folded P3 follow-ups in the same files: `fu-recheck-escalation-mode-blind`
    (the checker learns the round mode), `fu-recheck-escalation-merge-mismatch`
    (serial and parallel paths agree on merging nothing from an escalated
    round), `fu-recheck-comments-overclaim-scope` (recheck.mjs comment).
  - Sign the owner-directed merge of PR #498: every unsigned contract
    amendment the #498 ride recorded (on spec-cheap-transitions-slice and the
    cross-spec ones on ride-state-handoff-to-worktree, node-first-third-slice,
    roadmap-serves-downstream-projects, canon-is-a-build-artifact) is signed
    with the owner's merge as the source, and their trackers close.
- Out of scope:
  - Rewriting EVENTS.jsonl or STATE storage formats beyond the new record.
  - The spec-amend merge-signature fold bug (`fu-amend-list-shows-unsigned-signed`).
  - Generated provider adapters.

## Acceptance Criteria
- AC-001: A judged round's verdict is bound in a store the delta cannot
  write, and delta eligibility reads that binding, not the tracked ledger.
- AC-002: Every tamper shape listed in Scope gives full under the new
  default, each pinned by a test with a mutation record; TEST-2742 no
  longer pins a residual.
- AC-003: Delta is the default; `AAI_RECHECK_MODE=full` (and any value that
  is not `delta`, unset included only if Planning keeps opt-in) behaves as
  the spec states; the spec, SUBAGENT_PROTOCOL, WORKFLOW and CHANGELOG say
  exactly what the code does.
- AC-004: The three folded P3 follow-ups are closed by the change.
- AC-005: The RFC-0017 phase 4 row records this slice and stays `in progress`.
- AC-006: The #498 amendments are signed with the owner's merge as the
  source and their trackers are closed.

## Verification
- The changed scripts' suites pass (rc 0) locally and in a CI-like clean
  clone (env -i, no STATE, Linux container for argv-heavy suites).
- A replay of every review/validation probe from PR #498 gives full.

## Constraints / Risks
- L3: touches WORKFLOW.md and dispatch. Every round of this ride runs with
  `AAI_RECHECK_MODE=full`; the mechanism never judges its own delivery.
- Lessons from PR #498: state what a guard compares, never list guarantees;
  move spec rows before recording an amendment; read `--strict` rc without a
  pipe; any large JSON goes on stdin (Linux 128 KiB argv cap); CI has no
  harness env.
- STATE is gitignored and per-worktree: the binding must survive the ride
  handoff to a worktree and the merge-cleanup archive, or degrade to full.
- Consumer-visible (default flips): merge needs the owner's menu.
- No secrets referenced.

## Notes
- Source: owner menu answer 2026-10-24 "Zapnout po ověření (Recommended)";
  RFC-0017 phase 4; SPEC-0250 D4 residual; `fu-recheck-verdict-not-bound-to-check`.
