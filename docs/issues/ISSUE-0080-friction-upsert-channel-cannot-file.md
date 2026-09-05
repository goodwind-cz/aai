---
id: friction-upsert-channel-cannot-file
number: 80
type: issue
status: done
links:
  pr:
    - TBD
  commits:
    - TBD
---

# The friction upsert channel cannot file a single issue — two stacked defects, both invisible to a permissive `gh` mock

## Summary
- `/aai-feedback-upsert` is the sanctioned upstream channel for AAI-layer friction
  (RFC-0012 Phase 2c). Exercised end-to-end for the first time on 2026-09-04 with
  53 spooled observations and 7 `review_candidate` clusters, it filed **zero**
  issues and can never file any.
- Two independent defects sit in series. Each alone is sufficient to block every
  publish; neither is reachable by the existing suite.

## Type
- bug

## Impact
- Every AAI installation using the sanctioned feedback channel: friction is
  captured, gated, scored and clustered locally, and then silently cannot leave
  the machine. The failure presents as `blocked_dedup_unavailable`, which reads
  like a transient network hiccup rather than a permanent defect.
- Severity/priority: high. The whole point of RFC-0012 is the upstream hop, and
  the upstream hop has never worked.

## Current Behavior

### D1 — the dedup search passes a flag value `gh` rejects
`.aai/scripts/aai-feedback-upsert.mjs` `dedupSearch()` calls:

```
gh search issues --repo <dest> --match body aai-friction:<fp> --state all --json number --limit 1
```

`gh search issues` accepts only `--state {open|closed}`. `all` is not a valid
value, so the call exits non-zero every time, on every fingerprint, on every
machine. `runGh` degrades to `{ok:false}`, `dedupSearch` returns
`{searched:false}`, and the confirm path fails closed:

```
aai-feedback-upsert: could not verify dedup for <fp> (gh search unavailable) — refusing to create
```

The fail-closed behavior is correct and should stay. The bug is that the
precondition it guards can never be satisfied.

### D2 — the configured label does not exist in the destination
`.aai/feedback.yaml` pins `labels: [aai-friction]`, and the create path passes
`--label aai-friction`. `goodwind-cz/aai` has no such label. `gh issue create`
refuses an unknown label, so even with D1 fixed the write fails at the last step.

### D3 (contributing) — the suite's `gh` mock accepts every argument
`tests/skills/test-aai-feedback-upsert.sh` stubs `gh` with a shell script that
records its argv and `exit 0`s unconditionally. It never validates a flag, a flag
value, or a label. The mock is therefore strictly more permissive than the real
CLI, and the suite is green while the real command is rejected. The mock proves
"we called gh", never "the call is one gh would accept".

This is the same shape as the already-filed friction that an untested guard
message is an untested instruction: here, an unasserted argv is an unasserted
contract.

## Expected Behavior
- `dedupSearch` issues a call real `gh` accepts. Omitting `--state` searches all
  states, which is the intended semantics.
- The create path either uses a label that exists in the destination, or ensures
  it, or degrades to filing without the label rather than failing the write.
- The suite pins the exact flag skeleton of every `gh` call the engine emits, so
  a flag drift fails a test instead of silently disabling the channel, and pins
  the mutating create's destination and content by value.
- A cluster the engine knows it cannot publish is not advertised with a
  `--publish` command that will refuse; prepare output distinguishes "ready to
  file" from "blocked".

## Steps to Reproduce
1) Set `triage.mode: review` in `.aai/feedback.yaml`.
2) `node .aai/scripts/aai-feedback-triage.mjs`
3) `node .aai/scripts/aai-feedback-upsert.mjs`
   Observe every candidate reported as `blocked_dedup_unavailable`, each still
   followed by a `--publish ... --confirm` command.
4) `node .aai/scripts/aai-feedback-upsert.mjs --publish <fp> --confirm`
   Observe the fail-closed refusal.
5) Run the search by hand to see the real cause:
   `gh search issues --repo goodwind-cz/aai --match body aai-friction:<fp> --state all --json number --limit 1`
   → `invalid argument "all" for "--state" flag: valid values are {open|closed}`
6) `gh label list --repo goodwind-cz/aai --json name --jq '.[].name' | grep aai-friction`
   → no match.

## Verification
- `bash tests/skills/test-aai-feedback-upsert.sh` — passes, including new cases
  that fail against the pre-fix engine (argv contract for search and create).
- Hand-run of the corrected search returns `[]` with exit 0.
- A prepare run reports the candidates as publishable rather than blocked.

## Constraints / Risks
- The fail-closed dedup refusal must survive the fix untouched; a search that
  cannot run must still refuse to create.
- Tightening the mock may expose further latent argv drift in the same suite;
  that is the point, but it may widen the change.
- Creating the destination label is a repository change, not a code change, and
  needs the owner. Degrading to a labelless create keeps the channel working
  without one.

## Notes
- Found while executing the owner's request to process the friction backlog; the
  request is blocked on this.
- Budget note (not a defect): `max_new_issues_per_7d: 3` against 7 current
  candidates means the backlog drains over three weeks by design.
