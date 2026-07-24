---
id: branch-guard-no-work-item
number: 28
type: issue
status: draft
links:
  pr: []
  commits: []
  github_issues: [135]
---

# branch-guard has no pass for a work-item-less branch, so chore/release/docs branches always fail the SKILL_PR precondition

## Summary
- `.aai/scripts/branch-guard.mjs` (shipped in PR #129 / SPEC-0070, wired as the
  `.aai/SKILL_PR.prompt.md` "0. BRANCH HYGIENE" precondition) decides pass/fail by
  matching the current branch against `current_focus.ref_id`. It assumes EVERY
  branch belongs to a work item. Branches that legitimately do not — `chore/*`
  (telemetry, cleanup), `release/v*` (the `/aai-release` cut), `docs/*` — hit
  order-item 5 ("branch must contain the ref_id slug") and exit 3, or, with a
  cleared focus, order-item 3 ("ref_id empty") and exit 4. There is NO exit path
  that means "this branch correctly has no work item", so the guard fails closed
  and, as a SKILL_PR precondition, stops the ceremony before push.
- Reported as GitHub #135, hit live this session while committing post-merge
  telemetry (PR #132) on `chore/metrics-flush-telemetry`.

## Type
- bug

## Impact
- Any non-work-item branch cannot pass the branch-hygiene precondition: routine
  chores (telemetry/cleanup commits that must NOT go straight to `main`, which the
  guard's own base-branch check (exit 1) correctly forces onto a branch) and, more
  importantly, `/aai-release` cuts (`release/v*` can never match a work-item ref)
  are blocked. Second-order: `current_focus.ref_id` keeps pointing at the LAST
  completed work item after its PR merges, so the guard's remediation string
  advises creating a branch for work that already shipped. AAI-layer -> every
  downstream project inherits it via `/aai-update`. Severity: medium — the guard's
  core fail-closed value (catch a real work-item scope pushed onto a stale/shared
  branch, the #129 purpose) must NOT regress; only the missing "no work item" case
  is the defect.

## Current Behavior
- Decision order (branch mode): (1) in git work tree else exit 4; (2) detached
  HEAD exit 2; (3) STATE unreadable / ref_id empty exit 4; (4) branch == base
  exit 1; (5) branch does not contain ref_id exit 3; (6) pass exit 0. A
  `chore/`/`release/`/`docs/` branch reaches step 5 (or step 3 if focus is cleared)
  and fails. `--suggest` likewise exit-4s on a cleared focus.

## Expected Behavior
- A branch whose name declares it a non-work-item branch passes cleanly with a
  DISTINCT, visible reason (not a silent match), while:
  - the base-branch guard (exit 1) still fires first — a chore is still never
    committed straight to `main`;
  - a real work-item branch that does NOT correspond to the current ref_id STILL
    exits 3 — the #129 anti-drift protection is unchanged;
  - detached HEAD (exit 2) and not-a-git-repo / unreadable STATE (exit 4) are
    unchanged.

## Verification
- A recognized non-work-item branch PREFIX allowlist — `chore/`, `release/`,
  `docs/` — is checked AFTER the base-branch guard (order 4) and BEFORE the
  ref_id-match (order 5). A branch matching an allowlisted prefix exits 0 with a
  distinct message (e.g. "no work item claimed — recognized non-work-item branch
  prefix '<p>'"), regardless of `current_focus`.
- Order preserved and proven by tests: on `main` -> still exit 1 (base wins over
  the allowlist); `chore/x`/`release/vX`/`docs/y` -> exit 0 (new); `feat/unrelated`
  (a work-item type prefix whose name does not contain the current ref_id) -> STILL
  exit 3; detached -> 2; unreadable STATE -> 4. A correctly-named `<type>/<ref-id>`
  branch still exits 0 via the existing order-6 path.
- Covered by new sub-cases in `tests/skills/test-aai-branch-guard.sh` (allowlisted
  prefixes pass; base still wins; a non-allowlisted mismatch still exits 3),
  green on macOS + Linux CI.

## Constraints / Risks
- The allowlist must NOT weaken the anti-drift guarantee: it keys on the branch
  NAME PREFIX only, and only for a closed, explicit set. A work-item branch is
  named `<type>/<ref-id>` (e.g. `fix/...`, `feat/...`) — those prefixes are NOT on
  the allowlist, so a real scope pushed onto a `feat/wrong` branch still exits 3.
  Do NOT add `feat`/`fix`/etc. to the allowlist.
- Keep it a NARROW, deterministic set. If a broader/less-safe exemption is ever
  wanted, prefer an explicit `--no-work-item` flag the caller passes deliberately
  (an act, not an accident) over widening the prefix list — note this as a possible
  future addition, do not build it now unless Planning judges the release path
  needs it.
- `.aai/scripts/branch-guard.mjs` is NOT `protected_paths_l3`. Keep the change to
  the guard + its test to avoid a prompt-diet ledger companion; the guard's own
  usage/comments document the new exit path. Do NOT touch any protected path.
- Read-only, fail-closed unchanged: the guard writes nothing; STATE-unreadable
  still exit 4.
- Portability (LEARNED 2026-07-19): the test spawns throwaway git repos — full
  `mktemp` templates, POSIX-safe, honor shebangs; green on Linux CI + macOS.
- Companion obligations (PLANNING step 3a): branch-guard.mjs is not a
  prompt-corpus file and is not a NEW `.aai/**` file (it already exists, added in
  #129); the test extends the existing suite. Expect no ledger true-up, no
  PROFILES classification.
- No secret referenced — SECRETS PREFLIGHT skipped.

## Notes
- This is the third finding from this session's dogfooding trilogy: #133/#134
  (docs-audit false-open, fixed in SPEC-0073) and this one all came from using the
  freshly-shipped machinery on real cleanup work. The guard did exactly its job on
  `main` (exit 1 blocked a telemetry commit to base); the only gap is that it can't
  say "yes" to the branch that block forces you to create.
