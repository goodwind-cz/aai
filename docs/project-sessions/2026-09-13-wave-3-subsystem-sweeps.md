# Wave 3 — subsystem sweeps, owner-mandated (2026-09-13)

Why this exists: on 2026-09-13 the owner directed that everything substantial
be resolved, GitHub issues included, without regard to the pairing limits, so
that the framework is as functional as possible. This document records what
"everything substantial" measured to, why the wave-2 pair order cannot get
there, and the mechanism that replaces it. Ledger: `hitl_decision` of
2026-09-13 with `ref_id: wave-3-subsystem-sweeps` (mandate) and
`ref_id: harness-universal-routing` (the one-off merge of PR #376).

## What was measured on 2026-09-13

| source | count |
|---|---|
| open GitHub issues (after closing #352 and #371, fixed by #372 and #373) | 6 |
| draft intakes that are not machine clusters | 22 (10 CHANGE, 5 DEBT, 7 ISSUE) |
| machine-clustered `P2 backlog cluster` ISSUE drafts | 30 |
| open follow-ups | 165 (1 P1, 97 P2, 67 P3); 64 older than 20 days |

The open follow-ups fall into six subsystems by their own text:
close ceremony / docs-audit / index / overview 47; test framework / hygiene /
isolation 46; dispatch / state / telemetry 31; friction and feedback 6;
sync / update / doctor 5; canon and subagent contract 6; 24 fit no bucket by
keyword and are placed by hand below.

## Why pairing cannot drain this

One ride closes one item and costs three to five hours of ceremony
(validation rounds, review, a 32-minute sweep, a 25-minute CI run, bot
threads). Pair 1 of wave 2 measured that exactly: one capability, four
validation rounds, one review, six CI runs. Under a 1:1 budget the four
remaining wave-2 pairs would close eight registry items. The registry is 165.

## The mechanism: one ride per subsystem

A sweep is a ceremony-2 TDD spec whose scope is a whole registry bucket. Every
item in the bucket ends in exactly one of two states, both recorded in the
ledger: fixed, with a test that a named mutation reddens; or rejected, with
the reason (`follow-ups.mjs close --status dropped`). Nothing is deferred to a
later ride. The ceremony is unchanged and is what makes "functional" a true
statement: TDD, mutation checks, independent validation, dual-verdict review,
full sweep, green CI, bot threads answered and resolved.

`docs/ai/roadmap.yaml` keeps its closed shape: each sweep is the capability of
a pair whose maintenance half is the largest single draft in that bucket, so
`ride-select` stays the gate and the 1:1 rule is not edited, only filled.

Under the wave-3 mandate the standing merge authorization of 2026-09-12 covers
every sweep that is internal; `update-installs-ref-guard-undisclosed` changes
consumer git behaviour and stays owner-merged. Two sweeps may run concurrently
in separate worktrees when their subsystems are disjoint.

## Order, and what each sweep carries

| # | sweep (capability) | maintenance half | carries | why here |
|---|---|---|---|---|
| 1 | telemetry-fields-not-prose (wave-2 pair 1, maintenance half) | (already paired) | CHANGE-0183, `fu-flush-window-closes-on-verdict-reset`, `fu-flush-nulls-review-scope-before-pr`, verdict-marker items | every later sweep is judged on this ledger |
| 2 | test-framework-sweep | residuals-of-the-per-suite-clone-ride (CHANGE-0166) | CHANGE-0180 (the only P1), the nested layer-profiles CI-only failure, `fu-nested-profiles-hides-missing-list`, DEBT-0004, DEBT-0006, ISSUE-0039/0041/0043/0044, GitHub #368, the 46 framework items | the sweep is the 32-minute cost every other ride pays; its flakes cost PR #376 five CI runs |
| 3 | dispatch-state-sweep | focus-and-validation-state-go-stale-silently (ISSUE-0040) | the 31 dispatch/state items, `fu-role-guard-*` class, `fu-routing-*` residuals, DEBT-0003 | the loop every tick runs |
| 4 | close-ceremony-sweep | unrecorded-spec-amendment-is-invisible (CHANGE-0181) | the 47 close/docs-audit/index/overview items, CHANGE-0184, ISSUE-0042, GitHub #338 #339 #370, `fu-check-committed-scope-folded`, `fu-overview-regen-eats-untracked` | the largest bucket and the one that shipped three false statements this month |
| 5 | update-installs-ref-guard-undisclosed (ISSUE-0083) | agents-tree-not-synced | GitHub #369, `fu-routing-file-overwritten-on-update`, the 5 sync/doctor items | consumer-visible; owner merges |
| 6 | friction-channel-sweep | hand-authored-friction-is-second-class (CHANGE-0172) | CHANGE-0179, GitHub #361, the 6 friction items | closes the channel the owner reads |
| 7 | canon-is-a-build-artifact | mutation-gate-for-tests | DEBT-0005, DEBT-0007, CHANGE-0167, the 6 canon/subagent items, `review-round-cap-in-validation-canon` text | rules bind by construction; the gate turns this month's lesson into a guard |

`standardized-backlog-drain` moves to the deferred list: with the buckets
swept there is nothing left for it to drain, and CHANGE-0180 / CHANGE-0184 ride
inside sweeps 2 and 4.

The 30 machine-clustered ISSUE drafts are an index of the follow-up registry,
not work; they are closed as superseded by the sweeps that own their items
(this chore), so the intake list shows only work.

## What the owner will see

One PR per sweep, each carrying the list of items it fixed and the list it
rejected with reasons. Owner attention is needed for the merge of sweep 5 and
for any HITL menu a sweep raises. Estimate: about one factory-day per sweep.

## Re-order of 2026-09-14 (owner decision)

Sweeps 1, 2 and 3 each needed three to five validation rounds, and most
BLOCKING findings were one class: a control that claimed a property it did not
test. The owner chose (menu answer A) to ride the mutation gate next, before
the close-ceremony, ref-guard and friction sweeps, so those run under a
structural guard instead of under the validator alone. New order after sweep
3: mutation-gate-for-tests (paired with CHANGE-0181), close-ceremony-sweep,
update-installs-ref-guard-undisclosed (owner merges), friction-channel-sweep,
canon-is-a-build-artifact last. Ledger: `hitl_decision` of 2026-09-14,
`ref_id: wave-3-subsystem-sweeps`.
