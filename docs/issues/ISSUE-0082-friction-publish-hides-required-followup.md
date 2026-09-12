---
id: friction-publish-hides-required-followup
type: issue
number: 82
status: done
links:
  pr:
    - 373
  commits:
    - da9cab69
---

# The friction publish flow files an unactionable issue and never says a second step is required

## Summary
- `aai-feedback-upsert.mjs --publish <fp> --confirm` prints exactly one line on
  success: `filed issue for v1:<fp> in <destination>`. Then it stops.
- What lands upstream is a title, six enum fields and an `evidence_ref` that, in
  the common case, is a path inside a private downstream repository the
  maintainer cannot open. The diagnosis, the reproduction and the suggested fix
  stay in the reporter's head.
- The convention that makes such an issue actionable — a hand-written
  `## Analysis (reporter follow-up)` comment — exists and is used
  (`goodwind-cz/aai#369`, `#370`, and `#371` itself), but it is transmitted only
  by having previously seen one. It appears in NONE of the four places a
  first-time reporter would look: `SKILL_FEEDBACK_UPSERT.prompt.md`, `--help`,
  the success line, or the prepared draft in `pending-issues/<fp>.md`.
- A second, separate defect in the same file: `runGh`'s
  `catch { return { ok: false } }` erases the cause of a failure, so a GitHub
  SECONDARY rate limit on `gh search` is reported to the operator as
  `gh search unavailable` while `gh api rate_limit` reads a full primary quota.
  The operator is pointed at the wrong thing.

## Type
- bug

## Impact
- Affected: every reporter using the sanctioned upstream friction channel, and
  every maintainer receiving from it.
- The reporter sees `filed issue …`, reads it as done, and moves on. The issue
  then sits upstream unactionable and looks like noise. Reported verbatim in
  `goodwind-cz/aai#371`: "That is what happened here: I filed #370, reported it
  as done, and a human asked whether anything could actually be done with it.
  They were right."
- `#371` is its own reproduction — the structured record is the entire thing the
  maintainer received, and the reporter added the analysis by hand because
  nothing in the flow asked for it.
- The rate-limit half has its own cost: a prepare run over roughly 40 candidates
  trips the secondary limit, every subsequent confirmed publish then fails
  closed with a message naming the wrong subsystem, and it clears on its own in
  under a minute — so the operator debugs a problem that has already gone away.
- Severity: medium. Nothing is corrupted and no data is lost; the channel
  produces artifacts nobody can act on, which is a throughput-without-yield
  failure rather than a destructive one.

## Current Behavior
- On success the publish path prints one line naming the fingerprint and the
  destination. It does not print the issue number or URL, although the number is
  already in hand from the `gh issue create` response — so the operator has to
  go and search for what they just filed.
- Nothing states that a follow-up comment is required for the issue to be
  actionable.
- `pending-issues/<fp>.md`, the draft the operator reviews before confirming,
  carries no placeholder for the analysis.
- When `gh search` returns HTTP 403 from the secondary rate limiter, the refusal
  surfaces as `gh search unavailable` with no exit status and no stderr line.

## Expected Behavior
- The success line names the issue URL and states plainly that the record is
  prose-free by design and that an analysis comment is required, including the
  runnable `gh issue comment <n> --repo <destination> --body-file <file>`.
- The prepared draft carries a commented-out `## Analysis (reporter follow-up)`
  skeleton, so the shape is visible before the operator confirms.
- `SKILL_FEEDBACK_UPSERT.prompt.md` states the convention, so an agent running
  the flow knows the work is not finished at "filed".
- A refused `gh` call surfaces enough to diagnose it — at minimum the exit
  status or the first stderr line — so a secondary rate limit is distinguishable
  from an unavailable subsystem.

## Steps to Reproduce (if applicable)
1) Run `aai-feedback-upsert.mjs` in prepare mode until a candidate exists in
   `docs/ai/friction/pending-issues/`.
2) Publish it: `--publish <fp> --confirm`.
3) Observe the single success line. It carries no URL, no issue number and no
   mention of a required follow-up. Grep `--help` and
   `.aai/SKILL_FEEDBACK_UPSERT.prompt.md` for the convention: absent from both.
4) Read the filed issue as a maintainer who cannot open the reporter's
   `evidence_ref` path. Nothing in it says what happened.
5) For the second defect: run a prepare pass over roughly 40 candidates to trip
   the secondary limiter, then attempt a confirmed publish. Observe
   `gh search unavailable` while `gh api rate_limit --jq .resources.search`
   reports the primary quota full.

## Verification
- A confirmed publish prints the issue URL and the follow-up instruction with a
  copy-pasteable `gh issue comment` line naming the real issue number.
- `docs/ai/friction/pending-issues/<fp>.md` contains a commented-out
  `## Analysis (reporter follow-up)` skeleton, and that skeleton never reaches
  the filed issue body.
- `/usr/bin/grep -n "Analysis (reporter follow-up)" .aai/SKILL_FEEDBACK_UPSERT.prompt.md`
  returns a line.
- A `gh` call refused with a non-zero exit surfaces that exit status or its
  first stderr line at the point of refusal; a test that injects a 403 shows the
  message naming the rate limiter rather than the subsystem.
- `tests/skills/test-aai-friction.sh` and the feedback-channel suites stay green.

## Constraints / Risks
- The prose-free record itself is NOT in scope and must not change. The reporter
  states this explicitly in `#371`: the D6 allowlist is working as intended and
  the redaction posture stays as it is. This intake is about telling the
  operator that a second step exists, not about capturing prose automatically.
- Related but distinct: `CHANGE-0179` asks whether the record should carry a
  description at all. `#371` answers that question in the negative from the
  reporter's side, so `CHANGE-0179` should be re-read in light of it rather than
  implemented alongside — its open decision may now be settled.
- The skeleton in `pending-issues/<fp>.md` must be inert: it is a draft the
  publish path reads, so a placeholder that leaked into a filed body would put
  unredacted prose upstream, which is the exact hazard the prose-free design
  exists to prevent.
- Surfacing `gh` stderr must not surface a token or a URL carrying one; the
  first stderr line of a 403 is safe, a blanket dump is not.
- No secret is referenced by this scope; secrets preflight skipped.

## Notes
- Source: `goodwind-cz/aai#371`, filed 2026-09-12 by the repository owner
  through the friction channel, with a detailed follow-up comment added by hand
  — itself the demonstration of the gap.
- The `evidence_ref` on `#371`
  (`docs/ai/friction/pending-issues/v1_641c0158c589ebc280ad6d7f696f13a7.md`)
  does not resolve in this checkout, and the fingerprint appears in neither
  `docs/ai/friction/observations.jsonl` nor `upsert-ledger.jsonl` here. That is
  a third instance of the same theme, not merely an inconvenience: the field
  that is supposed to carry the evidence points at a machine-local, untracked
  path. Worth deciding whether `evidence_ref` should be omitted when it cannot
  travel, rather than printed as though it could be followed.
- The reporter's own diagnosis of the 403 is exact and worth preserving:
  `gh api rate_limit --jq .resources.search` reported 30/30 remaining while
  `gh search issues` returned HTTP 403, which identifies it as a SECONDARY
  rate limit — a class `rate_limit` does not report at all.
