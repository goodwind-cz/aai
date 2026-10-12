---
id: pr-ceremony-fewer-commits
type: techdebt
number: 14
status: done
links:
  pr: []
  commits: []
---

# Tech Debt: the PR ceremony stops adding commits after the content commit

## Debt Summary
- Recent PRs (#452 to #456) each carried 3 or 4 commits that exist only for
  the ceremony: number, close with `--pr TBD`, `--stamp-pr N`, and a
  committed `pr_sweep` record. Each push re-runs required CI. PR #448
  re-recorded `pr_sweep` 4 times.
- The steps invalidate each other. A ledger commit after `pr_sweep` makes
  the head stale. INDEX.md rewrites a clock line on every commit, which needs
  a whitelist. About 16 ordering rules are kept mostly in memory files.

## Root Cause
- Each record was added as a fix for one incident, without removing the
  record it overlapped. Two of these records are dead after the squash merge:
  - `links.commits` names ride commits that are not on main (verified:
    598e4f5e of CHANGE-0210 is not an ancestor of origin/main).
  - `links.pr` duplicates the `(#N)` already in the squash subject.

## Current Cost / Risk
- 2 or 3 extra commits and 1 to 4 extra CI rounds per PR. In
  `.aai/SKILL_PR.prompt.md` (574 lines), roughly 200 lines cover this.
- `lib/pr-sweep.mjs` (238 lines), the `lane-gate --sweep-check` stale-head
  logic, and `close-before-push-guard.mjs` (166 lines; it duplicates
  `nothing-left-behind` docs_open).

## Target State
- **Bot review threads:** GitHub's "require conversation resolution" blocks
  the merge while a thread is unresolved. The agent still reads and answers
  bot comments. No committed `pr_sweep` record, no `--sweep-check`, no
  stale-head rule.
- **Close:** runs once, before the content commit. No `--pr TBD|NONE`
  sentinel, no `--stamp-pr` transaction, no stale-TBD scanner.
  `links.commits` is no longer stamped. `links.pr` is derived from git or
  `gh` when a reader needs it.
- **docs/INDEX.md:** deterministic, with no clock line, so a commit never
  dirties it by itself.
- **Duplicate checks:** `close-before-push-guard.mjs` is deleted, and the
  `pr-preflight` and `pr-platform` probes become one probe.

## Scope
- In scope: `SKILL_PR`, `close-work-item.mjs` (its hash pin is re-pinned
  once, last), `lane-gate.mjs`, `lib/pr-sweep.mjs`, `claude-hook-gate` merge
  gate, `merge-policy`, `generate-docs-index.mjs`, `docs-audit` consumers of
  links.pr and links.commits, `nothing-left-behind`, and the related tests.
- Out of scope: the allocator renaming files (a separate, bigger product
  decision), and validation or review gates.
- Owner action: enable "Require conversation resolution before merging" on
  main. This is a repo setting the owner confirms; the ride does not change
  it unasked.

## Plan / Migration
- Step 1 (lowest risk): deterministic INDEX.
- Step 2: replace `pr_sweep` with conversation resolution, after the owner
  enables the setting.
- Step 3: one close, no sentinels or stamps. Existing docs keep their
  `links`; readers tolerate both shapes.

## Verification
- A ride from PASS to open PR produces exactly one content commit plus at
  most one ceremony commit, measured on the next real ride.
- `docs-audit --strict` passes for docs closed in both the old and the new
  shape.
- A test proves an unresolved bot thread blocks the merge (via
  merge-policy or GitHub); a positive control proves a resolved one passes.

## Constraints / Risks
- `close-work-item.mjs` hash pin: batch every edit, re-pin last.
- Downstream projects without the GitHub setting keep bot-thread checking
  through `merge-policy`. Decide this in Planning.

## Notes
- Owner direction 2026-10-12: "3 Odlehčení PR ceremonie".
