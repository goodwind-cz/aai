---
id: merge-direction-signs-amendments
type: change
number: 208
status: done
links:
  pr:
    - 452
  commits:
    - a0f53aeb571f76cc8ff929f50d78d4db54c428f0
---

# The owner's merge direction signs the ride's contract amendments

## Summary
- When the owner directs a merge through `/aai-merge` ("mergni N"), that direction also becomes the owner signature on every unsigned contract-class post-freeze amendment of the ride being merged. A separate "sign the amendments" menu before the merge stops existing.
- One-time backlog: the 36 open `fu-amend-*` sign-off trackers (206 unsigned records) whose rides are already merged get signed, each citing the owner's decision recorded here plus that ride's merge commit, and their trackers close.

## Motivation / Business Value
- Owner decision 2026-10-10. The owner asked "co s temi podpisy amend, nejde to udelat aby to uzivatele neotravovalo" and answered the menu "Merge = podpis + backlog (Recommended)". The question was: should the owner's merge direction ("mergni N") also sign the PR's contract amendments?
- Today a contract amendment is signed only through a dedicated owner menu answer or `classify --signoff owner`. Rides record `--signoff none` by default, so trackers pile up: 36 open trackers aged 2 to 36 days. No gate consumes them, so they are pure backlog noise. When the owner is asked, it is an extra menu at the merge checkpoint that duplicates the merge decision.
- A spec amendment is a scope change owned by the owner. The owner's verbatim merge direction for a PR whose diff and PR body disclose the amendment is the owner deciding on that scope. So recording the direction as the signature is honest, provided the amendments are listed to the owner before the merge.

## Scope
- In scope:
  - `.aai/scripts/merge-cleanup.mjs`:
    - preflight lists the unsigned contract amendments of the ride(s) being merged ("signs on merge: …").
    - apply, after the merge is confirmed, signs them through the existing `spec-amend.mjs classify` path (`--record` keyed, `--signoff owner`). The authority cites the `directed_merge` record (PR number, merged head, direction words). Apply then closes the matching `fu-amend-*` trackers through `follow-ups.mjs`.
  - Canon wording: ROLE_COMMON "POST-FREEZE SPEC AMENDMENT", SKILL_MERGE, SKILL_SHIP step 6 "owed sign-offs", SKILL_PR (PR body lists the amendments that the merge direction will sign). Product doc `docs/product/directed-merge-and-post-merge-cleanup.md` updated.
  - One-time backlog signing in this ride's branch: for every open `fu-amend-*` tracker whose ride's PR is merged on main, sign each of its unsigned contract records via `classify --record`. The authority is this decision plus the merge commit. Then close the tracker.
- Out of scope:
  - Changing the measurement class, or `list --strict` semantics.
  - Signing on any merge that is not owner-directed: standing authority, merge-policy lanes, autonomous merges.
  - Trackers whose ride is not merged, or that belong to another session's in-flight work (e.g. `worktree-lacks-vendored-aai-layer-downstream`). These are reported and left alone.
  - Editing any existing ledger line.

## Affected Area
- `.aai/scripts/merge-cleanup.mjs`, `.aai/scripts/spec-amend.mjs` (only if classify needs a non-interactive authority form it lacks), `.aai/scripts/follow-ups.mjs` (read/close only).
- `.aai/ROLE_COMMON.md`, `.aai/SKILL_MERGE.prompt.md`, `.aai/SKILL_SHIP.prompt.md`, `.aai/SKILL_PR.prompt.md`.
- `docs/ai/decisions.jsonl` (append-only overlays for the backlog).
- Suites: `tests/skills/test-aai-merge-cleanup.sh`, `tests/skills/aai-merge-cleanup.Tests.ps1` (if the ps1 wrapper surface changes), and the prompt-corpus pins.

## Desired Behavior (To-Be)
- `/aai-merge N` preflight prints each unsigned contract amendment of the ride with its record key and one-line `what`, under a "signs on merge" heading. The owner sees what their direction signs.
- After the operator merge, `apply`:
  1. finds the human `directed_merge` record for this PR and merged head;
  2. signs each listed record with `owner_signoff: true`. The authority names the directed_merge (PR, head, direction words); the source is `directed_merge`.
  3. closes each `fu-amend-*` tracker once all its records are signed;
  4. reports the signed keys and closed trackers in its report.
  Re-running apply is idempotent: it neither signs twice nor closes twice.
- With no human `directed_merge` record for the PR+head, apply signs nothing and says so in one line.
- Measurement records and already-signed records are untouched.
- Canon no longer instructs a separate pre-merge signature menu. SKILL_SHIP step 6 shows "signs on merge: <ids>" instead of "owed sign-offs".
- After the backlog step, `follow-ups.mjs list --status open` shows no `fu-amend-*` tracker of a merged ride, and `spec-amend.mjs list --strict` exits 0.

## Acceptance Criteria
- AC-001: An owner-directed apply (human `directed_merge` present for PR+head) signs every unsigned contract record whose ref_id is a ride merged by that PR. Each signature is a new appended overlay with `owner_signoff: true` and an authority naming the PR, head and direction. Proven by a fixture test.
- AC-002: An apply without a human `directed_merge` record for that PR+head signs nothing and closes nothing. Proven by a fixture test, plus a mutation that removes the guard and reddens it.
- AC-003: Measurement records, already-signed records, and records of refs not merged by the PR are untouched (fixture test).
- AC-004: Every `fu-amend-*` tracker whose records are now all signed is closed; one with a still-unsigned record stays open. A second apply run appends nothing (idempotent).
- AC-005: Preflight output lists the to-be-signed records (record key and what) before the merge command is printed (fixture test).
- AC-006: Canon text: ROLE_COMMON, SKILL_MERGE, SKILL_SHIP and SKILL_PR describe the merge direction as the signature, and no longer instruct a separate pre-merge sign-off menu. Corpus pins and diet ledger updated.
- AC-007: Backlog: for every open `fu-amend-*` tracker whose ride is merged on main, all its unsigned contract records are signed through `classify --record`, citing this decision and the merge commit, and the tracker is closed. Trackers left open are listed in the PR body with the reason. `spec-amend list --strict` exits 0, and the existing fold for all other records is unchanged (before/after digest of `list --json` minus the newly signed keys).

## Verification
- Command(s) and expected results:
  - `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-merge-cleanup.sh`: all pass.
  - `node .aai/scripts/spec-amend.mjs list --strict`: exit 0.
  - `node .aai/scripts/follow-ups.mjs list --status open | grep fu-amend-` shows only trackers of unmerged rides.
  - Mutation evidence for AC-002 via `mutation-run.mjs`.

## Constraints / Risks
- Honesty risk: a signature must never be fabricated. Only a human `directed_merge` record carrying the owner's verbatim words authorizes it. Standing or autonomous merges never sign. For the backlog, the authority is this explicit owner answer, cited with its date and words.
- The append-only ledger is never edited in place; signatures are overlays.
- The apply step writes to the main checkout's `decisions.jsonl` (uncommitted, like the existing `directed_merge` line), and the next ride carries it. That precedent stands.
- No secret is referenced (secrets preflight skipped).

## Notes
- Implementation mode (autopilot default): Planning decides.
- Related: SPEC-0218 (directed merge), SPEC-0219 (`classify --record`), and the amendment-signature-asks-the-owner-too-often ride (measurement class).
