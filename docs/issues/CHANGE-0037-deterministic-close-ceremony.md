---
id: deterministic-close-ceremony
type: change
number: 37
status: done
links:
  pr:
    - 105
  commits:
    - 4bb6d81
---

# Change — Deterministic close-ceremony mechanism (no agent-improvised close)

## Summary
- Add a deterministic `close-work-item.mjs` that performs the entire
  work-item close ceremony correctly-by-construction — frontmatter status
  transition, `links.pr`/`links.commits` stamping, and the complete, correctly-
  reffed event set (`doc_lifecycle`, `work_item_closed`, `ac_evidence`) — then
  self-verifies the audit stays CLEAN. Wire it into the close flow so no AAI
  deployment depends on an agent hand-performing the ceremony.

## Motivation / Business Value
- The close ceremony is currently 100% agent-improvised: read the doc, flip
  `draft|implementing → done`, regex-edit `links.pr`/`links.commits`, emit
  `doc_lifecycle` + `work_item_closed` + `ac_evidence` (for BOTH the change and
  its spec) with the exact ref form the audit expects, then re-run the audit.
  Nothing enforces the order, completeness, or ref form. Observed failure modes
  in one session (all recurring, all silent-until-audit):
  - **status-flip miss** — flipping `draft→done` when the doc was actually
    `implementing` is a no-op; the doc stays open and trips `probable-false-open`
    (hit on SPEC-0046).
  - **ref-form mismatch** — emitting `work_item_closed`/`ac_evidence` with a
    numbered ref (`CHANGE-0027`) instead of the doc's slug `id` leaves the audit
    unable to match, flagging `probable-false-done`; required manual re-emit with
    slug refs (hit on CHANGE-0027, CHANGE-0035).
  - **incomplete event set** — forgetting the spec's `doc_lifecycle`/
    `work_item_closed` while doing the change's.
  These are governance-integrity failures: a mis-closed doc silently
  misrepresents project state. The workflow must remove the failure class, not
  rely on agent memory — this matters most in OTHER deployments where a less
  careful agent performs the close.

## Scope
- In scope: new `.aai/scripts/close-work-item.mjs` (stdlib-only, deterministic,
  idempotent, fail-closed, self-verifying); wiring the close step into the
  canonical close flow (`.aai/SKILL_PR.prompt.md` and/or the loop's post-review
  close) so the ceremony is a script call, not prose steps; its test suite.
- Out of scope: the merge boundary (still operator-only); the metrics flush
  (`metrics-flush.mjs` stays its own step); worktree telemetry reconciliation
  (separate follow-up, see Notes).

## Affected Area
- Close ceremony across the loop / PR skill; docs governance integrity.

## Desired Behavior (To-Be)
- `node .aai/scripts/close-work-item.mjs --ref <slug> --pr <N> --commit <sha>
  [--spec <spec-slug>]`:
  1. Resolves the doc(s) by slug `id`; reads each doc's ACTUAL current status.
  2. Transitions `draft|implementing → done` (no-op-safe if already done);
     stamps `links.pr` / `links.commits` (append, no duplicate).
  3. Emits the complete event set with the doc's slug `id` as ref:
     `doc_lifecycle <actual>→done`, `work_item_closed`, and `ac_evidence`
     (and the spec's, when `--spec` given) — the exact ref form the audit
     matches on.
  4. Regenerates the INDEX and runs the audit; asserts CLEAN. If the audit is
     not CLEAN (e.g. a heuristic trips), it reports the finding and exits
     non-zero WITHOUT leaving a half-closed state — fail-closed.
- The close flow invokes this script; the agent no longer hand-edits frontmatter
  or hand-emits close events.

## Acceptance Criteria
- AC-001: closing a work item via the script flips status from its ACTUAL
  current value (draft OR implementing) to done — an already-`implementing` doc
  is closed correctly (the SPEC-0046 failure cannot recur).
- AC-002: all emitted close events use the doc's slug `id` ref form; a
  post-close `docs-audit` is CLEAN with no `probable-false-done`/`false-open`
  for the closed ref (the CHANGE-0027/0035 ref-mismatch failure cannot recur).
- AC-003: with `--spec`, BOTH the change and the spec get the complete event set
  and both flip to done; the pair is never half-closed.
- AC-004: idempotent + fail-closed — re-running on an already-closed item makes
  no duplicate events/links and exits 0; if the post-close audit is not CLEAN
  the script exits non-zero and names the finding.
- AC-005: the canonical close flow (SKILL_PR / loop) references the script as
  the close step; the prose no longer instructs hand-editing frontmatter or
  hand-emitting close events.

## Verification
- New `tests/skills/test-aai-close-work-item.sh`: fixtures for draft-close,
  implementing-close, change+spec pair, idempotent re-run, and an
  audit-not-CLEAN fail-closed case; assert CLEAN audit + correct slug-ref events
  after each; existing suites green.

## Constraints / Risks
- Deterministic, stdlib-only, no network; must reuse the existing
  `append-event.mjs` / audit engine (no forked event schema).
- Fail-closed: never leave a partially-closed doc.

## Notes
- Root cause: the close ceremony is unmechanized (no script existed as of
  2026-07-18). Related recurring workflow gaps observed the same session, tracked
  as SEPARATE follow-ups so this scope stays single-surface:
  (a) worktree telemetry split — a metrics-flush run in the main checkout while
  implementation runs in a worktree strands the ledger record outside the PR
  (manually reconciled on PR #99);
  (b) subagent self-append carve-out is prompt-only, occasionally violated;
  (c) inline validation running `git checkout` in the shared tree (risk of
  disturbing uncommitted scope work) — prefer worktree isolation.
