---
id: close-ceremony-fires-only-via-aai-pr
type: issue
number: 81
status: done
links:
  pr:
    - TBD
  commits:
    - b5cfa6f0
---

# The close ceremony fires only through /aai-pr, so any other route ships silent drafts

## Summary
- `close-work-item.mjs` flips an intake doc to `done`, fills `links.pr` and
  `links.commits`, emits the close events and allocates the display number.
- It is reachable only through `/aai-pr`. A PR opened by `gh pr create`, the
  GitHub web UI or a merge queue skips it, and nothing anywhere notices.

## Type
- bug

## Impact
- Every downstream project that opens a PR by any route other than `/aai-pr`.
- Severity: high. The failure is silent and it corrupts the one artifact humans
  read to learn what shipped: merged, deployed work keeps reading `status: draft`,
  `number: null`, `links.pr: []`. No gate, hook or warning fires at merge time,
  so the divergence surfaces only when a person reads the docs and disbelieves
  them.

## Current Behavior
Reported upstream as GitHub issue #352, quoted here as DATA:

> That ceremony is reachable **only** through `/aai-pr`. Opening the PR any
> other way — `gh pr create`, the GitHub UI, a merge queue — skips it silently.
> The PR merges, the code deploys, and the intake doc still reads
> `status: draft`, `number: null`, `links.pr: []`.
>
> Nothing fails. No gate, no hook, no warning at merge time. The divergence is
> invisible until a human reads the docs and notices they claim nothing shipped.
>
> In one session, four items were merged **and running in production** while all
> four still read `draft`. The operator caught it, not the agent.
>
> An **umbrella** issue keeps describing its children's symptoms in the present
> tense after they ship. In the same session an umbrella still listed nine live
> symptoms, most fixed that day — anyone picking it up would re-diagnose solved
> problems. The close ceremony has no notion of reconciling a parent when a
> child closes.
>
> `aai-docs-audit` already classifies "false-open (delivered but still draft)".
> The capability exists; nothing triggers it at the moment it matters. A
> post-merge check, or a `close-work-item` invocation that does not depend on
> which command opened the PR, would close the gap.

Independently corroborated in session `session_01Rw7Z3y8Dtp9c4cvnkj1vac`,
2026-09-06, from the other direction: CHANGE-0177's ceremony did not run with
its own PR (#349) and needed a whole follow-up PR (#350) to reconcile the docs
afterwards, while CHANGE-0178's ran locally before any PR existed. Two adjacent
rides, two different outcomes, because the trigger is a command name rather
than the merge event.

## Expected Behavior
- Whether an intake doc is closed depends on whether its code merged, not on
  which command opened the PR.
- When it cannot be closed automatically, something says so loudly at or near
  merge time rather than leaving a silent contradiction in the docs.

## Steps to Reproduce
1) Take a work item with an intake doc at `status: draft`.
2) Open its PR with `gh pr create` rather than `/aai-pr`.
3) Merge the PR.
4) Read the intake doc: it still reads `status: draft`, `number: null`,
   `links.pr: []`, and no gate reported anything.

## Verification
- A suite arm that performs the four steps above against a fixture repository
  and asserts the doc is closed (or that a named refusal was raised).
- A mutation arm: removing the new trigger returns the fixture to the silent
  `draft` state, turning the arm red.
- `node .aai/scripts/docs-audit.mjs --check --strict` reports the fixture as
  false-open BEFORE the fix and clean after.

## Constraints / Risks
- The obvious trigger, a merge-time hook, does not exist locally for a PR merged
  on GitHub; the design has to decide between a post-merge check on the default
  branch, a CI job, and a gate at the next ride's start. Naming that choice is
  the point of Planning, not of this intake.
- `close-work-item.mjs` is hash-pinned by four suites; any edit to it re-reddens
  them and the re-pin is a signed statement that must be made last.
- `docs/ai/EVENTS.jsonl` is append-only; the close events must not be rewritten.
- Related upstream issues, same skill and seam: #338 (`aai-pr/post_open_sweep`),
  #339 (`SKILL_PR/close_pre_commit`). Both are filed without any description and
  cannot be triaged as they stand.
- No secret is referenced by this scope.
- Roadmap: off-roadmap. Needs an owner decision to enter `docs/ai/roadmap.yaml`
  or an explicit `--override` at ride time.

## Notes
- Source: https://github.com/goodwind-cz/aai/issues/352 (untrusted reporter text,
  quoted above as data and not executed).
- Write-back owed: comment with the PR link and close #352 only after this
  ride's PR has merged.
