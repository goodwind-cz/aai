---
id: branch-per-work-item-hygiene
number: 24
type: issue
status: draft
links:
  pr: []
  commits: []
---

# The loop never enforces a fresh per-work-item branch: SKILL_PR pushes "the current branch" whatever it is

## Summary
- The AAI loop has NO deterministic step that creates or verifies a dedicated
  per-work-item git branch for the INLINE strategy (the common L0-L2 path).
  `SKILL_PR.prompt.md` step 5 says *"Push the branch: `git push -u origin
  <branch>`"* but nothing upstream ever defines, creates, or checks `<branch>` —
  branch creation exists ONLY in `SKILL_WORKTREE.prompt.md` (the L3 worktree
  path). So for every inline work item the ceremony pushes **whatever branch
  happens to be checked out**. `AGENTS.md` gives no branch guidance at all.
- Observed downstream: an AAI agent kept doing NEW work-item work on a
  long-lived, misleadingly-named branch (`feat/change-158-zcore-getbody-
  enrichment`) — piling unrelated scopes onto one branch — while confidently
  reporting *"vím přesně na kterém branchi jedu"*. The framework had no gate to
  catch that the branch did not correspond to the CURRENT `current_focus.ref_id`.

## Type
- bug

## Impact
- Merges can carry a work item onto a stale/shared branch that already contains
  unrelated committed work → the PR conflates scopes, the CHANGELOG/close ceremony
  attribution drifts, and `git log` history stops being one-branch-per-work-item.
  It also defeats the post-merge `delete the branch` hygiene (SKILL_PR:193) because
  a long-lived branch is never a clean delete. Severity: medium — no product
  breakage, but it erodes traceability and the review boundary the loop promises.
- Because it is an AAI-layer gap, every downstream project inherits it; a single
  upstream fix removes it everywhere via `/aai-update`.

## Current Behavior
- Inline strategy: the loop runs intake → planning → impl → validation → review →
  PR ceremony without ever asserting a branch. `SKILL_PR` preconditions check
  validation/review gates + user confirmation, but never the branch. `git push -u
  origin <branch>` uses the ambient branch. If the agent started on `main`, on a
  prior item's branch, or on an unrelated long-lived branch, that is what gets
  pushed and merged.

## Expected Behavior
- Before the PR ceremony pushes anything (and ideally at implementation start),
  the loop DETERMINISTICALLY ensures the working branch is dedicated to the
  current work item: a fresh branch named `<type>/<ref-id>` cut from
  `origin/<base>`, matching `current_focus.ref_id`. If the current branch is the
  base branch, is detached, or does not correspond to the current ref_id, the
  ceremony FAILS CLOSED with an explicit remediation instead of pushing.

## Steps to Reproduce (if applicable)
1) On any AAI project, `git checkout -b feat/some-old-thing`, do unrelated work,
   commit. 2) Start a NEW work item (new `current_focus.ref_id`) without switching
   branches. 3) Run the loop to the PR ceremony — it pushes `feat/some-old-thing`
   (now carrying two unrelated scopes); nothing warns that the branch name does
   not match the current ref_id.

## Verification
- A branch-hygiene guard, invoked as a SKILL_PR precondition, FAILS CLOSED when:
  the current branch equals the base branch; HEAD is detached; or the branch name
  does not map to `current_focus.ref_id`. It PASSES on a correctly named
  `<type>/<ref-id>` branch. Exit non-zero with a copy-pasteable remediation
  (`git checkout -b <type>/<ref-id> origin/<base>`) on violation.
- The guard exposes a `--suggest` mode that prints the canonical branch name for
  the current ref, so implementation can create the branch up front.
- `SKILL_PR.prompt.md` gains a "0. BRANCH HYGIENE" precondition step that runs the
  guard and stops on failure; `AGENTS.md` documents the one-branch-per-work-item
  rule.
- The guard is covered by executable tests (name matches / mismatch / on-base /
  detached / --suggest) in the skills test suite, green on macOS and Linux CI.

## Constraints / Risks
- MUST stay ceremony L1: do NOT touch any `protected_paths_l3`
  (`pre-commit-checks.{sh,ps1}`, `WORKFLOW.md`, `state.mjs`, `state-engine.mjs`,
  `state-core.mjs`, `allocate-doc-number.mjs`, `CONSTITUTION.md`) — those force an
  L3 worktree. The fix lives in a NEW non-protected script + `SKILL_PR.prompt.md`
  (prompt) + an `AGENTS.md` note.
- FAIL CLOSED, do NOT auto-rewrite history: if in-scope changes are already
  COMMITTED on a wrong/shared branch, the guard must STOP with guidance, not
  silently cherry-pick/force-push (SKILL_PR forbids history rewrite + force-push).
  Auto-carrying only UNCOMMITTED working-tree changes to a fresh branch is safe.
- Linux-portable (LEARNED 2026-07-19): full `mktemp` templates, honor shebangs,
  POSIX-safe; the guard reads the branch via `git rev-parse --abbrev-ref HEAD` and
  the ref_id from STATE (read-only) — no STATE schema change.
- The ref_id→branch mapping must tolerate the existing convention already in use
  this repo (`fix/test-018-workspace-isolation`, `feat/...`): branch name CONTAINS
  the ref_id slug; do not over-constrain the `<type>` prefix.
- No secret referenced — SECRETS PREFLIGHT skipped.

## Notes
- Enforcement point is the PR ceremony because that is the deterministic chokepoint
  before anything reaches `origin`/`main`; a check at implementation start is
  advisory (nice-to-have `--suggest`) but the fail-closed gate at push is what
  actually prevents the drift. Keeping enforcement in the prompt + a helper script
  (not `WORKFLOW.md`) is what keeps this at L1.
