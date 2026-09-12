---
id: spec-friction-publish-hides-required-followup
type: spec
number: 176
status: done
ceremony_level: 2
links:
  requirement: docs/issues/ISSUE-0082-friction-publish-hides-required-followup.md
  rfc: docs/rfc/RFC-0012-aai-self-improvement-feedback-loop.md
  pr:
    - TBD
  commits:
    - da9cab69
---

# Spec — the publish path says the second step exists, and a refused gh call says why

SPEC-FROZEN: true

## Amendment (post-freeze, 2026-09-12 — owner decision on the open question)

This is a FROZEN spec, amended after the freeze and disclosed here rather than
rewritten silently, following the additive-with-disclosure convention already
established (`docs/specs/SPEC-0132-...md`, `docs/specs/SPEC-0153-...md`,
`docs/specs/SPEC-0161-...md`). `SPEC-FROZEN: true` is preserved.

The "Open question handed to the owner" section below asked whether a filed
issue's `evidence_ref` should be omitted or labelled when it cannot travel out
of the reporter's own checkout. The owner decided **(b)**: keep the field, but
label it `reporter-local` so a maintainer does not try to follow a path that
typically cannot resolve for them. Recorded as a `hitl_decision` in
`docs/ai/decisions.jsonl` (2026-09-12, `owner_signoff: true`) against
`fu-evidence-ref-cannot-travel` (P3).

This adds one acceptance criterion and one test to a frozen spec, which
`.aai/system/AUTONOMOUS_LOOP.md` reads as a scope change: **Spec-AC-13** /
**TEST-051** below. It is strictly additive — no existing AC's text moved, no
field was added to or removed from the transmitted record (the value of
`evidence_ref` is unchanged; only its printed label changes), and the decision
carries explicit owner sign-off.

## Amendment 2 (post-freeze, 2026-09-12 — remediation of validation FAIL)

Validation (`docs/ai/STATE.yaml` `last_validation`, run 2026-09-12) returned
`fail` on a BLOCKING finding plus six non-blocking findings. This amendment
records the fixes, following the same additive-with-disclosure convention as
Amendment 1 above. `SPEC-FROZEN: true` is preserved; nothing below moves or
deletes an existing AC's text.

- **F1 (BLOCKING, Spec-AC-09/D7) — the rate-limit signature missed the wording
  the source issue documents, and TEST-042's fixture could not detect that.**
  `goodwind-cz/aai#371`'s "Aside" pastes the line the reporter actually
  observed: `HTTP 403: API rate limit exceeded for user ID …`. The original
  `RATE_LIMIT_SIGNATURE_RE = /secondary rate limit/i` never matched it, so the
  hint never fired on the exact case the Aside exists to fix, and TEST-042's
  own fixture used GitHub's literal `secondary rate limit` wording — exactly
  what the regex was built to match — so it could never prove the signature
  covers what was actually observed. Fixed at cause, both parts:
  - `RATE_LIMIT_SIGNATURE_RE` is now `/rate limit exceeded|secondary rate
    limit/i` — it matches the reporter's own line AND GitHub's literal
    secondary wording.
  - `RATE_LIMIT_HINT` no longer asserts which class fired. The reporter's own
    wording (`API rate limit exceeded for user ID …`) is ALSO GitHub's genuine
    PRIMARY-limit message, so unconditionally claiming "secondary" would be a
    new wrong claim on a real primary hit. The hint instead states the fact
    the reporter established by direct measurement (`gh api rate_limit` read
    30/30 while the search call still refused): `gh api rate_limit` does not
    reliably report this refusal class, because `gh search issues` has its
    own throttle. It still names `gh api rate_limit` and the word secondary
    (Spec-AC-09's literal requirement), so no AC text changed.
  - TEST-042's fixture is now the reporter's own LITERAL line (not a string
    shaped to satisfy the regex), plus a second case keeping GitHub's literal
    secondary wording so both real wordings stay covered.
  - TEST-041 gained a negative-direction assertion: an ordinary,
    non-rate-limit refusal must carry NO rate-limit hint at all. This is what
    kills mutation U-07 (the hint printed unconditionally on every refusal),
    which the original suite could not detect because nothing asserted the
    hint's ABSENCE.
- **F6/F7 (Spec-AC-14, new) — `gh issue create`'s stdout URL was printed
  verbatim and uncertified.** `ISSUE_URL_RE`'s host component admitted
  userinfo (`user:token@host`), and nothing checked the parsed owner/repo
  against the configured destination. Validation probes P7/P8 showed a
  credentialed URL and a foreign-host URL both printed as "your filed issue".
  Fixed at cause: `parseIssueUrl(stdout, destination)` now returns a
  certification verdict, not a bare match. Two checks, both on the PARSED
  pieces: the host may not contain `@` (userinfo/credential shape), and the
  parsed owner/repo must equal `cfg.destination` (case-insensitive) — the same
  principle D3 already applies to the printed `--repo`, applied here to the
  printed URL. A shape match that fails certification is a NAMED refusal
  (`NOTE: the reported URL … was not printed`), distinct from D2's generic
  "could not read the issue number" degrade for a shape that never matched at
  all — never a silent reuse of that generic text, and never a silent drop.
  New tests TEST-052 (embedded userinfo) and TEST-053 (foreign host/repo),
  both mutation-checked against the certification check being removed
  entirely (the two probes reproduce validation's P7/P8 exactly). The shared
  test stub's default `issue create` response now echoes back the real
  `--repo` it was given (the way real `gh` does) instead of a hardcoded,
  unrelated `x/y` — the previous literal could never distinguish a legitimate
  response from a host/repo mismatch, since it was itself always a mismatch
  against every test's configured `goodwind-cz/aai` destination (R5 already
  flagged this class of shared-fixture edit; the whole suite was re-run, all
  green). `validation-2026-09-12-hostile-probes.sh`'s own stub and its P9/P10
  fixtures received the same correction, so those probes demonstrate D1's
  first-line rule in isolation rather than an artifact of the stub's
  unrelated placeholder repo.
- **F2 (Spec-AC-11 edge case) — the empty-stderr edge case had no reachable
  test.** `${SEARCH_STDERR:-search failed}` / `${CREATE_STDERR:-create
  failed}` make a truly empty stderr unreachable through the stub (bash
  `:-` fires on unset OR empty). The stub gained `SEARCH_STDERR_EMPTY` /
  `CREATE_STDERR_EMPTY` knobs to force a genuinely empty stderr. New test
  TEST-054, mutation-checked against `ghFailDetail`'s `if (!first) return
  null;` early return being removed (kills mutation U-08). Behaviour was
  already correct; only the fixture was unreachable.
- **F3 (Spec-AC-01 edge cases) — D1's "first line only" and the URL shape's
  tail anchor were untested.** Both were already correctly implemented; no
  test exercised the boundary. New tests TEST-055 (a non-matching first line
  before a valid URL on a later line must not extract that URL; kills
  mutation U-05) and TEST-056 (trailing junk after the issue number must not
  be accepted; kills mutation U-12).
- **F4 (Spec-AC-03, TEST-038 strengthened) — the enclosure check was
  order-only, not adjacency.** The draft body also carries an unrelated
  `<!-- aai-friction:<fp> -->` marker comment earlier in the file; a
  line-order check ("some opener before the heading, some closer after it")
  was satisfied by THAT marker even when the skeleton's own opener was
  deleted (mutation U-02). TEST-038 now pins the exact, byte-contiguous
  skeleton block (opener immediately followed by the heading, closer
  immediately following the prose) as a single substring, which no other
  comment in the file can satisfy. Re-verified: reddens under U-02.
- **F5 (Spec-AC-10 edge case) — truncate-before-redact ordering was
  untested.** New test TEST-057: a first line over 200 characters, uniformly
  safe throughout (no detector match anywhere in it, not only in the first
  200), must still print its truncated, certified prefix. Reversing the order
  (redact the full line, then truncate the result) makes `redactSummary`'s own
  length cap fail the certification outright regardless of content, which is
  exactly what the test's `assert_payload_not_contains … "suppressed"`
  catches. Mutation-checked: reddens under the reversed order.

New Spec-AC-14 (below) and six new tests (TEST-052 to TEST-057, Test Plan
below) are additive; no existing AC's text moved and no residual risk was
deleted (R1 is amended in place, disclosed, not deleted).

## Amendment 3 (post-freeze, 2026-09-12 — remediation of a second validation FAIL, owner override of the two-round cap)

Round 2 independent validation returned `fail` again: BLOCKING B1 (the host
was never pinned, so round-1 probe P8 and TEST-053's own fixture could not
prove Amendment 2's certification closed the class rather than one probe of
it), plus a non-blocking survivor V-M10 (the collateral stub fix made every
green fixture's certified URL owner/repo byte-identical to `cfg.destination`,
silently disabling the spec-NAMED "printing the URL's own owner/repo instead
of `cfg.destination`" mutation control) and a factually wrong causal clause in
`RATE_LIMIT_HINT`. Per `VALIDATION.prompt.md` c2, a third finding-bearing round
is normally a STOP whose only instruction is to split the ride; the owner
overrode that cap explicitly (`hitl_decision`, `docs/ai/decisions.jsonl`,
2026-09-12T13:55:30Z, `owner_signoff: true`) because the leak was introduced by
Spec-AC-01 itself (printing the URL verbatim is the reporter's own request),
so splitting would have shipped the exact hazard behind a test that denies it.
`SPEC-FROZEN: true` is preserved; nothing below moves or deletes an existing
AC's text.

- **B1 (BLOCKING, Spec-AC-14) — the host was never pinned; any host whose
  owner/repo happened to match the destination printed as "your filed
  issue".** Fixed at cause: `parseIssueUrl` now pins the host to the literal
  string `github.com` (case-insensitively), in addition to the existing
  userinfo and destination checks. Because `ISSUE_URL_RE` is anchored
  (`^...$`) and both the host and the owner/repo are now compared for EXACT
  equality against known values (a fixed literal and the admin-configured
  `destination`), every character of a CERTIFIED line is accounted for except
  the issue-number digit run — which `MAX_ISSUE_NUMBER_DIGITS` (10) now also
  bounds. Length and control-character/ANSI-escape filtering on the
  host/owner/repo are therefore closed BY CONSTRUCTION, not by a parallel scan:
  nothing that is not the exact trusted host, the exact configured
  destination, or a digit can survive to be printed. Verified live against
  `validation-2026-09-12-round2-probes.sh` V1-V5, V14 and V16 — all now
  refuse (previously V1-V5 and V16 printed verbatim; V14, an absurdly long
  padded issue number, is a gap this remediation found independently while
  reasoning through what the anchored shape leaves unconstrained, and closes
  with the same check). New tests TEST-058 (foreign host, MATCHING owner/repo
  — the exact case TEST-053 could not isolate) and TEST-059 (oversized issue
  number with an otherwise-legitimate host and destination).
- **V-M10 (Spec-AC-14/D3) — the collateral stub fix silently disabled a
  spec-named mutation control.** The engine's printed `--repo` was, and
  remains, unconditionally `cfg.destination` (never a value read out of the
  URL) — that line did not need to change. What changed is the TEST: new
  TEST-060 supplies a certified URL whose owner/repo differs from
  `cfg.destination` only in case (legal, since the comparison is
  case-insensitive), so the two sources diverge again and the mutation that
  substitutes `parsed.url`'s own owner/repo for `cfg.destination` reddens it,
  as does making the destination comparison case-sensitive (V-M2, the
  opposite-direction survivor from the same round).
- **N2 (RATE_LIMIT_HINT causal clause) — factually wrong.** The hint claimed
  `gh api rate_limit` misses this refusal class "since gh search has its own
  throttle separate from the primary quota it shows". That is false: `gh api
  rate_limit` DOES report the search throttle, as `resources.search` — measured
  live in this session at 30/30 while a search 403 was in play. The true,
  narrower statement: `gh api rate_limit` does not report SECONDARY limits at
  all, and its reading can disagree with whichever endpoint is actually
  enforcing the refusal. The sentence still names `gh api rate_limit` and
  `secondary` (Spec-AC-09's literal requirement), so no AC text changed and no
  test assertion needed to change (TEST-042 pins those two tokens, not the
  causal clause).
- **N4 (weak assertions, V-M2/V-M4/V-M8) — closed.** V-M2 (case-insensitivity
  untested) and V-M4 (printed URL coupled to the raw line, not the certified
  trimmed match) are both closed by TEST-060 and TEST-061 respectively. V-M8
  (TEST-051 greps only the bare token `reporter-local`, so the surrounding
  label prose could drift) is closed by pinning the full labelled line as one
  substring in TEST-051.
- **R6, corrected.** The prior wording claimed URL certification "assumes
  `github.com`" as an unstated, unimplemented assumption. That was itself
  inaccurate — the code implemented no host check at all. It now does (this
  amendment), so R6 below is rewritten to describe the ACTUAL residual: a
  renamed destination repository, not an unpinned host.

Four new tests (TEST-058 to TEST-061, Test Plan above; TEST-051 gains one
exact-line assertion and TEST-052 gains one reason-text assertion) are
additive; no existing AC's text moved and no residual risk was deleted (R6 is
amended in place, disclosed, not deleted).

## Amendment 4 (post-freeze, 2026-09-12 — remediation of two non-blocking validation round-3 findings F-1/F-2)

Round 3 independent validation returned `PASS`. It recorded seven non-blocking
findings; two of them (F-1, F-2) were named as worth one extra test fixture
each rather than as blockers, dispositioned by the validator as follow-ups.
This amendment closes both, following the same additive-with-disclosure
convention as the Amendments above. `SPEC-FROZEN: true` is preserved; nothing
below moves or deletes an existing AC's text, and no shipped behaviour
changed — see `git diff --stat -- .aai/scripts/aai-feedback-upsert.mjs`.

- **F-1 (TEST-STRENGTH, Spec-AC-14) — the host pin's EXACTNESS had no
  control.** TEST-058's existing fixture (`evil.example.com`) proves the host
  pin EXISTS, but shares no suffix with `github.com` at all, so it refuses the
  same way whether the comparison is exact equality or a weakened
  `.endsWith(TRUSTED_ISSUE_HOST)`. TEST-058 gains a second fixture,
  `https://evilgithub.com/goodwind-cz/aai/issues/9` — a host that ENDS WITH
  `github.com` — asserting both that the URL is never printed and that the
  refusal names the host-pin reason text specifically (`the reported URL host
  is not github.com and was not printed`), not merely the URL's absence, so
  the fixture cannot pass by reddening a different check. Verified on a
  scratch copy (HAZ-SCRATCH): weakening `!==` to `.endsWith(TRUSTED_ISSUE_HOST)`
  reddens this new assertion (`filed issue ... https://evilgithub.com/
  goodwind-cz/aai/issues/9` prints); the unmutated engine passes it.
- **F-2 (TEST-STRENGTH, Spec-AC-14) — the destination comparison's EXACTNESS
  had no control.** TEST-060's existing fixture proves the comparison is
  case-INSENSITIVE (an exact match once lower-cased); it does not prove the
  match is still EXACT rather than a PREFIX match, and TEST-053's
  `attacker/repo` fixture shares no prefix with the destination at all so it
  cannot distinguish the two either. TEST-060 gains a second fixture,
  `https://github.com/goodwind-cz/aai-evil/issues/9` — an owner/repo that
  STARTS WITH the configured destination `goodwind-cz/aai` — asserting both
  that the URL is never printed and that the refusal names the
  destination-match reason text specifically (`the reported URL does not
  match the configured destination and was not printed`). Verified on a
  scratch copy: weakening the comparison to
  `!ownerRepo.toLowerCase().startsWith(destination.toLowerCase())` reddens
  this new assertion (`filed issue ... https://github.com/goodwind-cz/
  aai-evil/issues/9` prints); the unmutated engine passes it.

No new Spec-AC and no new Test ID: both fixtures extend the existing TEST-058
and TEST-060 (already mapped to Spec-AC-14), chosen over new TEST-062/063
because each targets the exactness of the SAME comparison its host test
already exercises for existence (F-1) or case-insensitivity (F-2) — keeping
both properties of one comparison under one test id reads clearer than
splitting them, and matches the "one more fixture" cost the validator named.

## Amendment 5 (post-freeze, 2026-09-12 — remediation of three code-review NON-BLOCKING findings, disposition remediate-in-tree)

Code review (`docs/ai/reviews/review-20260912T161126Z.md`) returned `pass` on
both verdicts, with five NON-BLOCKING findings. Three were dispositioned
`remediate-in-tree` (the review's own H6 table, NB-1/NB-2/NB-3); the other two
(NB-4, NB-5) were dispositioned as follow-ups and are out of this scope. This
amendment closes the three in-tree items, following the same
additive-with-disclosure convention as Amendments 1-4 above. `SPEC-FROZEN:
true` is preserved; nothing below moves or deletes an existing AC's text, and
`.aai/scripts/aai-feedback-upsert.mjs` gained only a comment correction — see
`git diff --stat -- .aai/scripts/aai-feedback-upsert.mjs` — no behaviour
changed.

- **NB-1 (Spec-AC-02) — the post-loop `unparseable` return in
  `parseIssueUrl()` (the branch reached only when gh's create stdout is empty
  or all-whitespace) had no test and no mutation control.** The stub's
  `CREATE_STDOUT_OVERRIDE` knob could not produce that input: an EMPTY
  override is indistinguishable from "unset" under `[ -n ]`, so it always fell
  through to the stub's default URL. TEST-037 exercises a DIFFERENT branch
  entirely — a non-empty line that fails to MATCH the URL shape, which hits
  the IN-LOOP `unparseable` return a few lines earlier, not the post-loop one.
  Fixed the same way Amendment 2's remediation F2 fixed the identical shape on
  the stderr side (`CREATE_STDERR_EMPTY`/TEST-054): `tests/skills/test-aai-feedback-upsert.sh`
  gains a dedicated `CREATE_STDOUT_EMPTY` stub knob (checked before the
  override, so it cannot be shadowed by it) and a new test, **TEST-062**,
  which sets it, asserts the exact `NOTE: could not read the issue number from
  gh's output -- fill in <issue-number> below by hand.` sentence (not merely
  the URL's absence — this repository has shipped a right-verdict-wrong-reason
  control four times already), and asserts the printed command falls back to
  the literal placeholder while still naming the configured destination.
  **Mutation control**, verified on an HAZ-SCRATCH scratch copy, never the
  shipping tree: replacing the post-loop return with a fabricated
  `{ certified: true, url: ... }` (the code review's own mutation M-A) leaves
  TEST-001 through TEST-061 all green and reddens only TEST-062 — confirming
  the gap the review found and that this new control, and only this one,
  closes it. The unmutated engine passes TEST-062. No new Spec-AC; one new
  Test ID (TEST-062), mapped to the existing Spec-AC-02. The Edge cases bullet
  below is corrected to say what is now actually tested, rather than pointing
  at Spec-AC-02's unrelated degrade.
- **NB-2 (comment only, no AC, no test) — the comment at
  `.aai/scripts/aai-feedback-upsert.mjs:264` (now :264-267) claimed a value
  the decoder cannot parse "is refused, not let through (fail-closed)"; the
  code has always fallen back to the RAW host and continued, never refused on
  a decode failure alone.** Named by validation round 3 as W-07 and left
  unclosed. The comment is corrected to say what the code does: a decode
  failure falls back to the raw host string, which is safe not because that
  branch refuses anything itself, but because a host that fails to decode can
  never equal the literal `github.com` the exact host pin below requires, so
  it is refused there instead. No behaviour changed; a false record is no
  longer shipped as a comment.
- **NB-3 (R6) — the by-construction claim (this spec's Amendment 3 text above,
  and the matching code comment) is stated absolutely; validation round 3
  measured exactly one exception.** `U+212A KELVIN SIGN` lowercases to ASCII
  `k`. It cannot appear in the pinned host (`github.com` contains no `k`), but
  it CAN survive certification inside the owner/repo when the CONFIGURED
  destination itself contains a `k` or `K` — validation reproduced it
  concretely with `destination: kodak/toolkit`, where
  `https://github.com/<U+212A>oda<U+212A>/tool<U+212A>it/issues/9` certifies
  and prints (`validation-2026-09-12-round3-byconstruction-proof.txt` part 3).
  The shipped destination `goodwind-cz/aai` contains no `k`, so the exception
  set is empty for this repository today. One sentence is added to R6 below
  (rather than to the Amendment 3 prose above, which stays historical/frozen
  as written) because R6 is this spec's living register of accepted residual
  risk, and an accepted-with-reason exception belongs there, not in a
  narrative amendment. No code change: the escaping character is a printable
  letter homoglyph, never a credential, control character, or length
  amplifier, so it does not reopen the leak class Spec-AC-14 closes.

No new Spec-AC. One new Test ID (TEST-062, NB-1, mapped to Spec-AC-02). R6 is
amended in place, disclosed, not deleted, per NB-3.

## Links
- Requirement: `docs/issues/ISSUE-0082-friction-publish-hides-required-followup.md`
- Primary source (the specification proper): `goodwind-cz/aai#371` body plus the reporter's hand-written `## Analysis (reporter follow-up)` comment, read with `gh issue view 371 --repo goodwind-cz/aai --comments`. The reporter is the repository owner; the comment names the symptom, the exact suggested output text, two optional extras ranked by effort, and a precise diagnosis of the 403. This spec implements that comment.
- Reused, not reimplemented: `.aai/scripts/lib/aai-redact.mjs` `redactSummary` (the fail-closed detector set, RFC-0013 D3 — used here to certify a `gh` stderr line before it is printed), `.aai/scripts/aai-feedback-upsert.mjs` `runGh` (the single `gh` seam, widened not replaced), `tests/skills/test-aai-feedback-upsert.sh`'s pinned-argv `gh` stub, `tests/skills/lib/prompt-diet-ledger.sh` (the corpus byte ledger)
- Technology contract: `docs/TECHNOLOGY.md` — Node stdlib only, zero dependencies, bash 3.2 test suites, no PowerShell mirror owed (no installer or runner changes)

Registry items closed by this scope: `fu-friction-issue-body-is-prose-free` (P3) and its correction `fu-friction-prose-free-list-inexact` (P3). `node .aai/scripts/follow-ups.mjs list` at plan time reports shown=158 open=158 closed=207 total=365. Both items record the same complaint — a maintainer reading a filed friction issue cannot act on it because the body carries no free-text description of what went wrong. `#371` answers that complaint from the reporter's own side and REFUSES the remedy those items imply: the body stays prose-free, and actionability comes from a required hand-written follow-up comment instead. Delivering the convention is therefore the resolution of both, and they are closed with that rationale rather than with a body change.

Items whose subject this scope touches and that stay OPEN, with reasons: `fu-friction-label-missing-in-destination` (P3) is an owner action in the destination repository, not a code change, and nothing here touches labelling; `fu-friction-scoring-rewards-recurrence` (P2) is the triage scorer, upstream of this file and untouched; `fu-amend-friction-upsert-channel-ba7701` (P2) is an owner sign-off owed on a previous scope's post-freeze amendment and cannot be discharged by code.

## Implementation strategy
- Strategy: tdd
- Rationale: recorded at intake by the owner (`docs/ai/STATE.yaml` `implementation_strategy.source: intake`) and kept unchanged. Planning agrees on the merits: one half of this scope is a redaction-adjacent guard where a placeholder that leaked into a filed body would put unredacted prose upstream, which is exactly the hazard the prose-free design exists to prevent, and the other half widens the single `gh` seam that four tri-state consumers already branch on.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: five files, one engine, one prompt, three test files; no protected `protected_paths_l3` surface and no fixture that merges into a repository. The suites here run against a `mktemp -d` friction dir and a stubbed `gh`, so nothing writes the shipping tree. Isolation is still useful because this checkout is shared between sessions (`docs/knowledge/LEARNED.md`, shared-worktree P1 2026-09-06), which is why this is `optional` rather than `not_needed`.
- User decision: undecided
- Base ref: main
- Worktree branch/path: to be decided by Implementation Preparation
- Inline review scope: `.aai/scripts/aai-feedback-upsert.mjs` `.aai/SKILL_FEEDBACK_UPSERT.prompt.md` `tests/skills/test-aai-feedback-upsert.sh` `tests/skills/lib/prompt-diet-ledger.sh` `tests/skills/test-aai-prompt-diet.sh` `docs/specs/SPEC-0176-spec-friction-publish-hides-required-followup.md` `docs/issues/ISSUE-0082-friction-publish-hides-required-followup.md`

## What is NOT in scope (the reporter's own fence)

These are the reporter's words in `#371` and they bind this scope:

- The prose-free record itself does not change. "The prose-free record is correct and I am not asking to change it." The D6 allowlist, `buildPayload`'s field set, and the redaction posture stay exactly as they are. No new field is added to the transmitted body and none is removed.
- `docs/issues/CHANGE-0179-friction-issues-arrive-without-a-description.md` asks the opposite question — whether the record should carry prose at all. `#371` answers it in the negative from the reporter's side, so CHANGE-0179's open decision may now be settled. This spec does not implement against CHANGE-0179 and does not close it; re-reading it in light of `#371` is a separate act for the owner.
- `evidence_ref` is deferred, not decided here. See D8 below and "Open question handed to the owner".

## Decisions

- **D1 — the issue number comes from `gh issue create`'s own stdout, and only in the shape a URL has.** `runGh` already returns that stdout and the confirmed path already discards it. The engine parses it against `^https?://[^\s/]+/[^\s/]+/[^\s/]+/issues/(\d+)$` on the first non-empty line and uses the captured integer. Nothing else in gh's stdout is ever echoed: an unparseable stdout degrades (D2) rather than being printed, because printing an arbitrary subprocess blob is the same class of leak this scope is elsewhere closing.
- **D2 — the follow-up instruction is unconditional; only the number is conditional.** If the URL cannot be parsed the engine still prints the prose-free statement and the command skeleton, with a `NOTE:` naming why the number is absent and the literal placeholder `<issue-number>` in the command. The issue exists at that point, so this never changes the exit code: the publish still exits 0. This follows the repository's degrade-with-NOTE convention in `.aai/AGENTS.md` (a generator that degrades must name it in output).
- **D3 — the `--repo` in the printed comment command is `cfg.destination`, never the owner and repo parsed out of the URL.** The destination is the pinned, config-sourced value the write already used; the URL is subprocess output. Two sources for one fact would let a redirected or proxied URL retarget a command the operator is being told to run.
- **D4 — the draft skeleton is a static literal and is structurally commented out.** `prepare()` appends a fixed block to `pending-issues/<fp>.md` after the payload. It interpolates NOTHING — not the fingerprint, not the destination, not one spool field — so there is no value in it that redaction would have to certify. It is wrapped in a single `<!-- ... -->` so the file still renders as the record it previews.
- **D5 — the skeleton's inertness is a property of the publish path, not of the skeleton's wording.** The confirmed publish rebuilds the transmitted body with `buildPayload(rep, cluster, fp)` from the triage report and the spool; it never opens the draft. That is already true today, and this scope pins it with a test that a POISONED draft cannot change one byte of the filed body (Spec-AC-05). Relying on "the current placeholder happens to look harmless" would be exactly the tautological control this repository has shipped twice.
- **D6 — `runGh` returns a diagnosis; a single sanitizer decides what may be printed.** `runGh` captures stderr instead of discarding it and returns `{ ok, stdout, status, stderrFirst }`. One helper, `ghFailDetail(r)`, produces the printable fragment for every refusal site: it takes the FIRST non-empty stderr line, truncates it to 200 characters, and passes it to `redactSummary`. On `ok:true` the certified line is printed; on `ok:false` the fixed literal `stderr suppressed by the redactor` is printed instead. The exit status is printed either way, so a refusal is never bare. Consumers keep their tri-states unchanged: `dedupSearch` still fails CLOSED, `existingLabels` still degrades OPEN.
- **D7 — the secondary-rate-limit hint is a fixed string, matched on the RAW line and printed without it.** The signature test runs against the untruncated, unredacted first stderr line; what is emitted is a constant sentence naming `gh api rate_limit`. So a 403 line that the redactor suppresses still produces the hint, and the hint itself can carry nothing.
- **D8 — `evidence_ref` stays as it is, and the question is handed back.** `#371`'s own `evidence_ref` points at `docs/ai/friction/pending-issues/v1_641c0158c589ebc280ad6d7f696f13a7.md`, a gitignored, machine-local path that does not resolve in this checkout and whose fingerprint is in neither `observations.jsonl` nor `upsert-ledger.jsonl` here. Whether that field should be omitted, or labelled as reporter-local, is a change to WHAT THE TRANSMITTED RECORD CONTAINS — the one thing the reporter fenced off. Deciding it inside this scope would be deciding it on the reporter's behalf against his stated boundary. Registered as an open question for the owner and filed as a follow-up; no code here reads or writes `evidence_ref`.

## Seams

Each crossing is produced on one side and asserted on the other by a real run, never by two mocks agreeing.

- **S1 — `prepare()` writes `pending-issues/<fp>.md`, and the confirmed publish builds the transmitted body from the report and the spool.** Two producers of "what a maintainer sees", one of which must never reach the other. Crossed by TEST-039 and TEST-040: a real prepare run writes the draft, then a real publish run in the same fixture files the issue, and the assertion reads the recorded `gh` argv.
- **S2 — `runGh`'s return shape and the four consumers that branch on it.** Widening the record must not flip a tri-state. Crossed by TEST-048: in one fixture the dedup search fails and the create count must be zero, and the label list fails and the issue must still be filed unlabelled.
- **S3 — what the engine PRINTS and what the engine RUNS.** The success line advertises a mutating `gh issue comment`. Crossed inside TEST-036 by asserting the recorded call log contains zero `issue comment` invocations, so an advertised command can never become an executed one.
- **S4 — three artifacts state one command skeleton: the engine's success output, `--help`, and `.aai/SKILL_FEEDBACK_UPSERT.prompt.md`.** Crossed by TEST-046, which reads all three in one test and requires the same three tokens in each, so they cannot drift apart silently.
- **S5 — `prepare()` writes the draft file and `aai-feedback-status.mjs` counts draft files.** Crossed by TEST-049: a real prepare followed by a real status run must still report one pending draft.
- **S6 — prompt bytes and the prompt-diet floor.** `.aai/SKILL_FEEDBACK_UPSERT.prompt.md` is inside `test-aai-prompt-diet.sh` TEST-010's live glob, so growth there is owed a ledger entry and a TEST-012 pin bump. Crossed by TEST-050, which runs the diet suite itself.
- **S7 — `gh`'s stderr and the redaction canon.** The producing side is a stub emitting hostile stderr; the asserting side is the engine's refusal text. Crossed by TEST-043.

## Acceptance Criteria Mapping

- Maps to: the Expected Behavior list of `docs/issues/ISSUE-0082-friction-publish-hides-required-followup.md`, bullets 1 to 4
- Spec-AC-01 to Spec-AC-02 realise bullet 1 (success line names the URL and the required follow-up)
- Spec-AC-03 to Spec-AC-05 realise bullet 2 (the draft skeleton, and the hazard it must not create)
- Spec-AC-06 to Spec-AC-07 realise bullet 3 (the convention is stated where an agent and an operator look)
- Spec-AC-08 to Spec-AC-11 realise bullet 4 (a refused `gh` call is diagnosable without leaking)
- Spec-AC-12 is the PLANNING companion obligation for prompt-corpus growth

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN a confirmed publish files an issue and gh issue create returns an issue URL, the engine SHALL print that URL on its own line, SHALL state that the record is prose-free by design and an analysis comment is required, SHALL print a runnable gh issue comment command carrying the parsed issue number and the configured destination, and SHALL make zero gh issue comment invocations | done | docs/ai/tdd/spec-friction-publish-hides-required-followup/red-036.txt; green-036.txt; mutation-sweep.txt (sweep 1-2) | — | destination comes from config, never from the URL (D3); TEST-036 |
| Spec-AC-02 | WHEN gh issue create succeeds but its first stdout line does not match the issue-URL shape, the engine SHALL still exit 0, SHALL still print the prose-free statement and the command skeleton with the literal placeholder for the number, SHALL print a NOTE naming that the number could not be read, and SHALL NOT echo the unparsed stdout | done | docs/ai/tdd/spec-friction-publish-hides-required-followup/red-037.txt; green-037.txt | — | the issue exists; a print failure never becomes an exit failure (D2); TEST-037 |
| Spec-AC-03 | WHEN a prepare-only run prepares a draft, docs/ai/friction/pending-issues/<fp>.md SHALL contain the literal heading text Analysis (reporter follow-up) with an HTML comment opener before it and the matching closer after it, and aai-feedback-status SHALL still report exactly one pending draft for that fixture | done | docs/ai/tdd/spec-friction-publish-hides-required-followup/red-038.txt; green-038.txt; green-049.txt; mutation-049.txt | — | static literal, zero interpolation (D4); seam S5; TEST-038/049 |
| Spec-AC-04 | WHEN that prepared fingerprint is then published in the same fixture, the recorded gh issue create argv SHALL contain zero occurrences of the token Analysis (reporter follow-up) and SHALL still contain the marker aai-friction followed by the fingerprint | done | docs/ai/tdd/spec-friction-publish-hides-required-followup/green-039.txt; mutation-039.txt | — | seam S1; RED impossible by construction (mutation control is the evidence); TEST-039 |
| Spec-AC-05 | WHEN the prepared draft on disk is overwritten with unredacted prose and a token-shaped string before the publish, the recorded gh issue create argv SHALL be byte-identical to the argv recorded for the same fixture with an untouched draft | done | docs/ai/tdd/spec-friction-publish-hides-required-followup/green-040.txt; mutation-040.txt | — | proves the mechanism, not the wording (D5); mutation control, not a RED; TEST-040 |
| Spec-AC-06 | .aai/SKILL_FEEDBACK_UPSERT.prompt.md SHALL contain the literal Analysis (reporter follow-up), the literal gh issue comment, and a sentence stating that the work is not finished when the issue is filed | done | docs/ai/tdd/spec-friction-publish-hides-required-followup/red-046.txt; green-046.txt; red-047.txt; green-047.txt; mutation-sweep.txt (sweep 7) | — | the agent-facing half of the convention; TEST-046/047 |
| Spec-AC-07 | The --help output of aai-feedback-upsert.mjs SHALL contain the literal gh issue comment and the words prose-free | done | docs/ai/tdd/spec-friction-publish-hides-required-followup/red-045.txt; green-045.txt; mutation-sweep.txt (sweep 8) | — | one of the reporter's four places; TEST-045 |
| Spec-AC-08 | WHEN gh search issues exits non-zero, the dedup refusal on stderr SHALL name the exit status and the certified first line of that stderr, the process SHALL exit 1, and the recorded gh issue create count SHALL be 0 | done | docs/ai/tdd/spec-friction-publish-hides-required-followup/red-041.txt; green-041.txt; green-048.txt; mutation-048.txt; mutation-sweep.txt (sweep 3) | — | fail-closed behaviour is unchanged; only the message grows; TEST-041/048 |
| Spec-AC-09 | WHEN the first stderr line of a failed gh call matches a rate-limit signature, the refusal SHALL additionally print a fixed sentence naming gh api rate_limit and the word secondary, and that sentence SHALL interpolate nothing from the stderr | done | docs/ai/tdd/spec-friction-publish-hides-required-followup/red-042.txt; green-042.txt; mutation-sweep.txt (sweep 6) | — | matched on the raw line, printed as a constant (D7); TEST-042 |
| Spec-AC-10 | WHEN gh stderr carries a token-shaped string, a URL, or more than one line, the refusal SHALL contain neither the token nor the URL, SHALL contain the literal suppressed placeholder, SHALL still name the exit status, and SHALL contain at most one line originating from gh stderr | done | docs/ai/tdd/spec-friction-publish-hides-required-followup/red-043.txt; green-043.txt; mutation-sweep.txt (sweep 4-5) | — | seam S7; the redactor decides, this scope writes no new detector; TEST-043 |
| Spec-AC-11 | WHEN gh issue create itself exits non-zero, its refusal SHALL name the exit status and the certified first stderr line by the same helper, and the process SHALL exit 1 having appended nothing to the upsert ledger | done | docs/ai/tdd/spec-friction-publish-hides-required-followup/red-044.txt; green-044.txt; mutation-sweep.txt (sweep 3) | — | one sanitizer, every refusal site; TEST-044 |
| Spec-AC-12 | tests/skills/lib/prompt-diet-ledger.sh SHALL carry exactly one new JUSTIFIED_ADDITIONS entry naming this ref whose leading byte count equals the measured growth of .aai/SKILL_FEEDBACK_UPSERT.prompt.md, the TEST-012 pin SHALL move from 24559 by that same amount, and bash tests/skills/test-aai-prompt-diet.sh SHALL exit 0 | done | docs/ai/tdd/spec-friction-publish-hides-required-followup/red-050.txt (finding: absorbed by headroom, no literal RED); green-050.txt; mutation-050.txt | — | PLANNING companion obligation, prompt-corpus arm; re-measured growth +724 B (2103 -> 2827), pin moved 24559 -> 25283; TEST-050 |
| Spec-AC-13 | (Amendment, 2026-09-12) WHEN a filed issue's structured fact list carries an evidence_ref, the templated body SHALL label it reporter-local so a maintainer does not try to follow a path that may not resolve for them, and the field's value SHALL be unchanged | done | docs/ai/tdd/spec-friction-publish-hides-required-followup/red-051.txt; green-051.txt; mutation-sweep.txt (sweep 10) | — | owner hitl_decision against fu-evidence-ref-cannot-travel (P3); TEST-051 |
| Spec-AC-14 | (Amendment 2, 2026-09-12, remediation F6/F7) WHEN gh issue create returns a first stdout line matching the issue-URL shape whose host carries embedded userinfo or whose owner/repo does not equal the configured destination, the engine SHALL NOT print that URL, SHALL print a NAMED refusal distinct from the unparseable-stdout NOTE, SHALL fall back to the literal placeholder in the printed command, and SHALL still target the configured destination in that command | done | tests/skills/test-aai-feedback-upsert.sh TEST-052/TEST-053 (mutation-checked); docs/ai/tdd/spec-friction-publish-hides-required-followup/validation-2026-09-12-hostile-probes.sh P7/P8 re-verified | — | reproduces validation probes P7 (embedded credentials) and P8 (foreign host); same principle as D3 applied to the printed URL |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan

### Components affected
- `.aai/scripts/aai-feedback-upsert.mjs` — `runGh` (capture stderr and status), a new `ghFailDetail` sanitizer, a new `parseIssueUrl` helper, the success block at the end of the confirmed publish path, the dedup refusal, the create refusal, the `HELP` constant, and the draft template in `prepare()`.
- `.aai/SKILL_FEEDBACK_UPSERT.prompt.md` — one new section stating the convention.
- `tests/skills/test-aai-feedback-upsert.sh` — new cases TEST-036 to TEST-050 appended and registered in `main`; the stub's `issue create` response URL changes from `https://github.com/x/y/issues/1` to a non-trivial number so a hardcoded constant cannot satisfy Spec-AC-01; the stub gains `SEARCH_STDERR` and `CREATE_FAIL` knobs so a hostile stderr can be injected without a second stub.
- `tests/skills/lib/prompt-diet-ledger.sh` and `tests/skills/test-aai-prompt-diet.sh` — the ledger entry and the TEST-012 pin.

### Data flows
1. prepare: report and spool to `buildPayload` to `writeFileSync(draft)` with the static skeleton appended. The skeleton is appended AFTER `payload.body` so the marker's position inside the body is unchanged.
2. publish: report and spool to `buildPayload` to `gh issue create` argv to gh stdout to `parseIssueUrl` to the success block. The draft is not on this path and does not become one.
3. refusal: gh stderr to `runGh` to `ghFailDetail` to `redactSummary` to the printed fragment.

### Edge cases
- gh writes the URL with a trailing newline and may precede it with nothing else; parse the first NON-EMPTY line only.
- gh writes nothing to stdout on success (possible under some gh configurations): this is the POST-LOOP `unparseable` return in `parseIssueUrl()`, a different branch than a non-matching line (that hits the IN-LOOP return instead, TEST-037). TEST-062 (Amendment 5) exercises the empty-stdout branch directly via the `CREATE_STDOUT_EMPTY` stub knob, with its own mutation control.
- stderr is empty on a non-zero exit: print the exit status alone, with no detail fragment and no suppression placeholder.
- stderr's first line exceeds 200 characters: truncate to 200 BEFORE redaction, never after. Truncation only shortens, so it cannot construct a string the detectors would have caught in full but miss truncated, except for a token whose recognisable prefix survives while its entropy tail does not — a prefix shorter than 11 characters cannot survive a 200-character cut, so this is not reachable here.
- `existingLabels` failure must keep degrading OPEN even though `runGh` now returns more; this is the regression the widening could plausibly break.

## Test Plan

| Test ID  | Spec-AC | Type | File path (expected) | Description | Status |
|----------|---------|------|----------------------|-------------|--------|
| TEST-036 | Spec-AC-01 | integration | tests/skills/test-aai-feedback-upsert.sh | confirmed publish stdout carries the stub URL, the phrase prose-free, and a gh issue comment line with the stub issue number and the configured destination; the recorded call log has zero issue comment invocations | green |
| TEST-037 | Spec-AC-02 | integration | tests/skills/test-aai-feedback-upsert.sh | stub create emits a non-URL line; exit code is 0, stdout carries NOTE and the placeholder command, and the non-URL line does not appear in stdout | green |
| TEST-038 | Spec-AC-03 | integration | tests/skills/test-aai-feedback-upsert.sh | prepare-only run; the draft contains the heading text with a comment opener on an earlier line and the closer on a later line | green |
| TEST-039 | Spec-AC-04 | integration | tests/skills/test-aai-feedback-upsert.sh | prepare then publish in one fixture; recorded issue create argv has zero occurrences of the heading text and still carries the fingerprint marker | green |
| TEST-040 | Spec-AC-05 | integration | tests/skills/test-aai-feedback-upsert.sh | publish twice in matched fixtures, once with the draft overwritten by prose plus a token-shaped string; the two recorded issue create lines are byte-identical | green |
| TEST-041 | Spec-AC-08 | integration | tests/skills/test-aai-feedback-upsert.sh | search stub exits 1 with a known stderr line; engine stderr names the exit status and that line, exit code is 1, create count is 0 | green |
| TEST-042 | Spec-AC-09 | integration | tests/skills/test-aai-feedback-upsert.sh | search stub exits 1 with an HTTP 403 rate-limit line; engine stderr additionally names secondary and gh api rate_limit | green |
| TEST-043 | Spec-AC-10 | integration | tests/skills/test-aai-feedback-upsert.sh | search stub emits a token-shaped string, a URL and fifty lines; engine stderr contains neither the token nor the URL, contains the suppressed placeholder and the exit status, and matches the stderr sentinel at most once | green |
| TEST-044 | Spec-AC-11 | integration | tests/skills/test-aai-feedback-upsert.sh | create stub exits 1 with a known stderr line; engine stderr names the exit status and that line, exit code is 1, and the upsert ledger gains no line | green |
| TEST-045 | Spec-AC-07 | integration | tests/skills/test-aai-feedback-upsert.sh | --help stdout contains gh issue comment and prose-free, and the command exits 0 | green |
| TEST-046 | Spec-AC-06 | integration | tests/skills/test-aai-feedback-upsert.sh | seam S4 drift guard; the three tokens gh issue comment, --repo and --body-file each appear in the publish stdout, in --help stdout, and in .aai/SKILL_FEEDBACK_UPSERT.prompt.md | green |
| TEST-047 | Spec-AC-06 | integration | tests/skills/test-aai-feedback-upsert.sh | the prompt file contains the heading text and a sentence stating the work is not finished when the issue is filed | green |
| TEST-048 | Spec-AC-08 | integration | tests/skills/test-aai-feedback-upsert.sh | seam S2 tri-state regression; with the search failing the create count is 0 and the exit code is 1, and with only the label list failing the issue is filed with no --label token in the recorded argv | green |
| TEST-049 | Spec-AC-03 | integration | tests/skills/test-aai-feedback-upsert.sh | seam S5; after a prepare that writes the skeleton, aai-feedback-status.mjs still reports one pending draft | green |
| TEST-050 | Spec-AC-12 | integration | tests/skills/test-aai-prompt-diet.sh | the diet suite exits 0 with the new ledger entry present and the bumped TEST-012 pin equal to the independent re-sum | green |
| TEST-051 | Spec-AC-13 | integration | tests/skills/test-aai-feedback-upsert.sh | (Amendment) a present evidence_ref is labelled reporter-local in the templated draft body, with the value itself still present | green |
| TEST-052 | Spec-AC-14 | integration | tests/skills/test-aai-feedback-upsert.sh | (Amendment 2) a gh-reported issue URL carrying embedded userinfo is never printed; a NAMED refusal and the literal placeholder appear instead | green |
| TEST-053 | Spec-AC-14 | integration | tests/skills/test-aai-feedback-upsert.sh | (Amendment 2) a gh-reported issue URL naming a repo other than the configured destination is never printed; the printed command still targets the configured destination | green |
| TEST-054 | Spec-AC-11 | integration | tests/skills/test-aai-feedback-upsert.sh | (Amendment 2) a genuinely empty stderr on a non-zero create exit prints the exit status alone, no suppression placeholder | green |
| TEST-055 | Spec-AC-01 | integration | tests/skills/test-aai-feedback-upsert.sh | (Amendment 2) D1 first-line rule; a non-matching first line before a valid URL on a later line prevents that URL from being extracted | green |
| TEST-056 | Spec-AC-01 | integration | tests/skills/test-aai-feedback-upsert.sh | (Amendment 2) D1 URL shape tail anchor; trailing junk after the issue number is never accepted | green |
| TEST-057 | Spec-AC-10 | integration | tests/skills/test-aai-feedback-upsert.sh | (Amendment 2) a safe first line over 200 characters is truncated before certification, not certified-then-truncated | green |
| TEST-058 | Spec-AC-14 | integration | tests/skills/test-aai-feedback-upsert.sh | (Amendment 3) a gh-reported issue URL on a FOREIGN HOST whose owner/repo still matches the configured destination is never printed; the printed command still targets the configured destination | green |
| TEST-059 | Spec-AC-14 | integration | tests/skills/test-aai-feedback-upsert.sh | (Amendment 3) a gh-reported issue URL with a legitimate host and destination but an implausibly long padded issue number is never printed | green |
| TEST-060 | Spec-AC-14 | integration | tests/skills/test-aai-feedback-upsert.sh | (Amendment 3) a certified URL whose owner/repo differs from the configured destination only in case still prints, and the advertised gh issue comment command names the configured destination's own casing, never the URL's | green |
| TEST-061 | Spec-AC-01 | integration | tests/skills/test-aai-feedback-upsert.sh | (Amendment 3) the printed URL is the certified, trimmed match; trailing whitespace after an otherwise-legitimate stdout line never survives into what is printed | green |
| TEST-062 | Spec-AC-02 | integration | tests/skills/test-aai-feedback-upsert.sh | (Amendment 5, remediation of NB-1) a genuinely EMPTY create stdout hits parseIssueUrl's POST-LOOP unparseable return, distinct from TEST-037's non-matching-line fixture; the exact NOTE reason text appears and the printed command falls back to the placeholder while still naming the configured destination | green |

Test status values: pending to red to green.

## Mutation checks

This repository shipped two tautological controls in its last scope — tests that
stayed green with the implementation deleted — and both were caught only by
mutation testing, one of them by an external bot after four internal rounds. So
each test above is paired here with the source mutation that MUST redden it. The
RED-first observation covers a test whose behaviour does not exist yet; a
mutation control covers a test whose subject is an EXISTING invariant, where a
RED is impossible by construction and its absence is the tautology.

Recorded under `docs/ai/tdd/spec-friction-publish-hides-required-followup/`, one
file per entry, each holding the failing output.

- `red-036.txt` to `red-047.txt`, `red-050.txt` — RED first: TEST-036, TEST-037, TEST-038, TEST-039, TEST-041, TEST-042, TEST-043, TEST-044, TEST-045, TEST-046, TEST-047 and TEST-050 all assert behaviour that does not exist on the pre-change tree, so each is observed FAILING there before any engine edit. A new test that goes green on the unmodified engine is a defect in the test, not a saved cycle.
- `mutation-040.txt` — **required, and the one that matters most.** TEST-040 CANNOT go red on the pre-change tree: today's publish already ignores the draft, so the test passes with this scope's implementation deleted. Its control is a deliberate engine mutation — append `readFileSync(draftPath, 'utf8')` to `payload.body` on the confirmed path — which must make TEST-040 fail. Without that recorded failure, TEST-040 is evidence of nothing.
- `mutation-039.txt` — TEST-039 is half-tautological in the same way: if the skeleton is never added it passes vacuously. Control is the same draft-reading mutation as above, which must make TEST-039 fail because the skeleton then travels.
- `mutation-048.txt` — TEST-048 asserts unchanged tri-states, so it is green before and after. Control is mutating `dedupSearch` to return `searched: true` on `!r.ok`, which must make the fail-closed half fail, plus mutating `existingLabels` to return `read: true` on `!r.ok`, which must make the degrade-open half fail.
- `mutation-049.txt` — TEST-049 asserts an unchanged count. Control is mutating the draft writer to emit the skeleton as a SECOND `.md` file, which must make the count read 2.
- Additional mutations that must redden a named test, run in the same pass and recorded in `mutation-sweep.txt`: hardcoding the printed issue number to a constant must redden TEST-036 (this is why the stub's URL number must not be 1); printing the owner and repository parsed out of the URL instead of `cfg.destination` must redden TEST-036; reverting `runGh` to `catch { return { ok: false } }` must redden TEST-041, TEST-042, TEST-043 and TEST-044; printing every stderr line instead of the first must redden TEST-043; removing the `redactSummary` gate must redden TEST-043; removing the fixed rate-limit sentence must redden TEST-042; deleting the new prompt section must redden TEST-046 and TEST-047; deleting the `--help` line must redden TEST-045; deleting the ledger entry must redden TEST-050.
- **Amendment 3 mutations (validation round 3, remediation of B1 and V-M10)**, recorded in this scope's remediation transcript rather than a separate file — each verified on a scratch copy per HAZ-SCRATCH, never on the shipping tree: removing the `TRUSTED_ISSUE_HOST` host-pin check must redden TEST-058 (round-1 probe P8 and TEST-053's own fixture could not isolate this because their foreign host ALSO mismatched the repo; TEST-058 pins owner/repo to a MATCH so only the host check can save it); removing the `MAX_ISSUE_NUMBER_DIGITS` bound must redden TEST-059; taking the printed `--repo` from `parsed.url`'s own owner/repo instead of `cfg.destination` must redden TEST-060 (this is the exact mutation the spec already named above for TEST-036, restated here because the collateral stub fix made every fixture's certified URL byte-identical to `cfg.destination`, so TEST-036 alone could no longer distinguish the two sources; TEST-060 uses a case-differing URL so the two sources diverge again); making the destination comparison case-sensitive must also redden TEST-060, from the opposite direction (the case-differing URL then fails to certify at all); printing `raw` instead of the trimmed `line` as the certified URL must redden TEST-061; removing the dedicated userinfo detector (both its raw and percent-decoded branches) while leaving the host pin in place does NOT redden TEST-052 on its own — the host pin independently refuses the same fixture (its host is `userinfo@github.com`, never the literal string `github.com`) — so TEST-052 additionally pins the refusal's reason text (`userinfo`), which DOES redden under that mutation; rewording the Spec-AC-13 label prose while keeping the token `reporter-local` must redden the strengthened TEST-051 assertion (V-M8). All six observed reddening exactly as described; none left as a note.

- **Amendment 4 mutations (validation round 3 F-1/F-2, non-blocking test-strength
  findings)**, verified on a scratch copy per HAZ-SCRATCH, never on the shipping
  tree: weakening the host-pin comparison from `!==` to
  `!host.toLowerCase().endsWith(TRUSTED_ISSUE_HOST)` must redden TEST-058's new
  suffix-host assertion; weakening the destination comparison from `!==` to
  `!ownerRepo.toLowerCase().startsWith(destination.toLowerCase())` must redden
  TEST-060's new prefix-repo assertion. Both observed reddening exactly as
  described, and both new assertions pass on the unmutated engine.

- **Amendment 5 mutation (code review NB-1, mutation M-A)**, verified on a
  scratch copy per HAZ-SCRATCH, never on the shipping tree: replacing
  `parseIssueUrl`'s POST-LOOP `return { certified: false, reason:
  'unparseable' };` with a fabricated `return { certified: true, url:
  ...destination.../issues/999999, number: '999999' };` leaves TEST-001
  through TEST-061 entirely green (none of their fixtures reach that branch —
  this is the code review's own observation and the reason NB-1 was found) and
  reddens exactly TEST-062, on its exact-NOTE-text assertion. The unmutated
  engine passes TEST-062.

Any mutation in that list that leaves every test green is a finding to fix in the
test, not a note to file.

**Implementation disclosure (TDD Implementation, 2026-09-12):**
- This paragraph's own list above names TEST-039 as both RED-first (line just
  above) AND tautological (the following bullet). That is a drafting
  inconsistency in this frozen section, not a real double requirement:
  TEST-039's assertion (zero occurrences of a heading text nothing prints
  anywhere on the pre-change tree) is vacuously true before any engine edit, so
  it cannot RED. Treated as mutation-only alongside TEST-040/048/049, per the
  dispatching instruction; `red-039.txt`/`red-040.txt`/`red-048.txt`/
  `red-049.txt` were never produced, and `mutation-039.txt`/`mutation-040.txt`/
  `mutation-048.txt`/`mutation-049.txt` are the recorded evidence instead.
- **TEST-050 is a FIFTH test that could not go RED, discovered only by
  measurement, not predicted here.** The corpus's live headroom at
  implementation time (2046/2048) comfortably absorbs this scope's +724 B
  prompt growth without breaching TEST-010's reduction floor, and TEST-012
  checks the ledger's own internal self-consistency, not the real corpus — so
  neither assertion reddens from an unlogged addition of this size. `red-050.txt`
  records this finding plainly rather than a fabricated failure; `mutation-050.txt`
  (deleting the added ledger entry while leaving the TEST-012 pin bumped) is the
  genuine evidence, and it does redden.
- **`mutation-048.txt`'s label-degrade arm initially passed green under its own
  mutation** (`existingLabels` returning `read: true` with an empty name list on
  failure): the original TEST-048 only asserted `creates=1` and the absence of
  `--label` in the argv, both of which still hold when an unreadable label set
  is silently mis-reported as "does not exist" instead of "could not read".
  Caught here, not left as a tautological control: TEST-048 was strengthened to
  additionally assert the stderr text names the read failure specifically, which
  then reddened under the mutation as required. `mutation-048.txt` records both
  the initial pass and the reddened re-run.
- **Mutation sweep 4 (printing every stderr line instead of the first) initially
  passed green against the original TEST-043**, because a hostile first line
  gets suppressed by the redactor either way, joined or not — the two behaviours
  were indistinguishable under that fixture alone. TEST-043 was extended with a
  second, matched fixture (a SAFE first line followed by a hostile later line):
  the correct engine must print the safe first line verbatim, while the mutation
  corrupts it by folding the hostile later line into the same certification
  pass. This is the boundary the AC actually requires, and it is what now
  reddens.
- **Spec-AC-13 / TEST-051** is the Amendment above, not part of the original
  Test Plan table; it follows the same RED-then-implement-then-GREEN cycle
  (`red-051.txt`, `green-051.txt`) plus a mutation control removing the
  `reporter-local` label (`mutation-sweep.txt`, sweep 10).

**Remediation mutation controls (Amendment 2, 2026-09-12).** Each new or
changed test below was mutation-checked against a scratch copy of the engine
(never the shipping tree); every one reddened as required.

- **TEST-041 (strengthened, negative direction)** — control: `ghRefusalLine`'s
  signature-gated hint replaced with an unconditional `RATE_LIMIT_HINT` (the
  U-07 shape). Reddens: TEST-041's new assertion that an ordinary refusal
  carries no rate-limit hint fails, because the hint now appears everywhere.
- **TEST-042 (fixture replaced)** — control: `RATE_LIMIT_SIGNATURE_RE`
  reverted to `/secondary rate limit/i`. Reddens: the reporter's literal line
  no longer matches, so no hint appears and the "secondary"/"gh api
  rate_limit" assertions fail.
- **TEST-038 (strengthened)** — control: the skeleton's leading `` <!-- ``
  removed from `DRAFT_FOLLOWUP_SKELETON`, its closing `` --> `` left in place
  (the U-02 shape). Reddens: the exact-block substring assertion fails,
  because the unrelated `aai-friction:<fp>` marker comment earlier in the
  file cannot satisfy it the way a line-order check could.
- **TEST-052 / TEST-053 (new, Spec-AC-14)** — control: `parseIssueUrl`'s
  certification checks (userinfo rejection, destination match) removed,
  returning `certified: true` for any shape-matching URL. Reddens: both
  tests' credential/foreign-host content appears verbatim in stdout,
  reproducing validation's P7/P8 exactly.
- **TEST-054 (new, Spec-AC-11 edge case)** — control: `ghFailDetail`'s
  `if (!first) return null;` early return removed, so an empty first line
  falls through to `redactSummary('')` (the U-08 shape). Reddens: the refusal
  prints the bare `stderr suppressed by the redactor` placeholder for a
  stderr that carried nothing at all.
- **TEST-055 (new, Spec-AC-01 edge case)** — control: `parseIssueUrl`'s
  first-line-only `return` replaced with `continue`, so every line is
  scanned (the U-05 shape). Reddens: the URL on the second line is extracted
  and printed, when D1 says only the first non-empty line may ever be read.
- **TEST-056 (new, Spec-AC-01 edge case)** — control: `ISSUE_URL_RE`'s
  trailing `$` removed (the U-12 shape). Reddens: a URL with trailing junk
  after the issue number is accepted and printed verbatim, junk included.
- **TEST-057 (new, Spec-AC-10 edge case)** — control: `ghFailDetail` reordered
  to certify the FULL first line, then truncate the result (the U-06 shape).
  Reddens: a safe line merely over 200 characters fails `redactSummary`'s own
  length cap outright and prints the suppression placeholder, when the
  correct order would have truncated it to a certifiable, safe prefix first.

## Verification

- `bash tests/skills/test-aai-feedback-upsert.sh` exits 0 with TEST-001 to TEST-035 unchanged and TEST-036 to TEST-049 green
- `bash tests/skills/test-aai-feedback-status.sh` exits 0
- `bash tests/skills/test-aai-prompt-diet.sh` exits 0
- `bash tests/skills/test-aai-friction.sh` and `bash tests/skills/test-aai-feedback-triage.sh` exit 0 (unchanged neighbours of the same channel)
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0176-spec-friction-publish-hides-required-followup.md` exits 0
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event --path docs/specs/SPEC-0176-spec-friction-publish-hides-required-followup.md` exits 0
- one full sweep before close with `AAI_TEST_TIMEOUT=3000`
- PASS criteria: every TEST-xxx green, every Spec-AC in a terminal status with non-empty Evidence, and every mutation listed above recorded as having reddened its named test

## Evidence contract

- ref_id: `friction-publish-hides-required-followup`
- RED artifacts (strategy is tdd, so they are owed): `docs/ai/tdd/spec-friction-publish-hides-required-followup/red-<test>.txt`, one per AC-gating test, each the captured FAILING output from the pre-change tree
- Mutation artifacts: `docs/ai/tdd/spec-friction-publish-hides-required-followup/mutation-<test>.txt` and `mutation-sweep.txt` as enumerated above
- Green runs: suite name, full command, exit code, per-test PASS lines
- Review scope: the inline review scope recorded above; `code_review.required` is true
- Commit SHA or diff range recorded at hand-off

## Residual risks

- **R1 — the rate-limit signature is pinned against a stub string, not against real GitHub output. (Amended 2026-09-12, remediation F1.)** The signature now covers TWO real, documented wordings — the reporter's own observed line and GitHub's literal "secondary rate limit" text — rather than one invented string, and the hint no longer asserts which class fired (it states only that `gh api rate_limit` does not reliably report this refusal). The residual narrows but does not close: a THIRD future rewording of either message would still silently stop matching, and the refusal would still degrade to Spec-AC-08's exit status plus the certified first line, which stays diagnosable. Accepted; not fixable without a network test.
- **R2 — the redactor can drop a legitimate diagnostic.** `redactSummary` fires on any URL, any multi-segment path and any 20-character token containing a digit, so a perfectly safe gh error naming a path prints as suppressed. Spec-AC-08's exit status still holds, and loosening the detectors for this one caller would weaken a canon used by the capture pass. Accepted deliberately.
- **R3 — nothing verifies that the operator actually posted the comment.** This scope makes the requirement visible; it does not enforce it. Enforcement would mean reading the destination repository back, which is a network read the prepare path deliberately minimises.
- **R4 — `evidence_ref` can still name a path no maintainer can open.** Deferred by D8, handed back as the open question below.
- **R5 — changing the stub's `issue create` response URL touches a shared fixture. (Realized 2026-09-12, remediation F6/F7.)** The predicted edit happened: the default response now echoes the real `--repo` it was given instead of a hardcoded, unrelated `x/y`, because the new URL certification (Spec-AC-14) needed a stub that can distinguish a legitimate response from a mismatch. The whole suite was re-run (all green); `validation-2026-09-12-hostile-probes.sh`'s own stub received the same correction.
- **R6 — URL certification (Spec-AC-14) pins the host to `github.com` and the owner/repo to the configured destination, with no allowance for a legitimate rename, redirect, or GitHub Enterprise host. (Amended 2026-09-12, remediation of validation round 3 B1.)** The prior wording of this residual claimed the code merely "assumes" `github.com`; the code implemented no host check at all — that was validation round 3's BLOCKING finding, not an accepted residual, and is now fixed (`parseIssueUrl`'s `TRUSTED_ISSUE_HOST` pin). What remains genuinely accepted: if the configured destination repository is renamed on GitHub after `.aai/feedback.yaml` is written, or if the operator points `destination` at a GitHub Enterprise host, a genuine `gh issue create` response would fail certification (wrong owner/repo, or a host that is legitimately not `github.com`) and print the degraded NOTE instead of the true URL — the issue is still filed correctly (certification only gates what is PRINTED, never the create call itself), so the operator loses convenience, not correctness, and can still find the issue via `gh issue comment <issue-number> --repo <destination>` failing loudly, or by checking the destination directly. Accepted: the alternative (trusting any host or owner/repo `gh` reports) is exactly the leak class Spec-AC-14 closes, and both a renamed destination and a GHE host are `feedback.yaml`-level facts the operator owns. **(Amended 2026-09-12, remediation of code-review NB-3.)** The by-construction argument above (Amendment 3) is exact with one measured, accepted exception: `U+212A KELVIN SIGN` lowercases to ASCII `k`, so a destination containing `k` or `K` admits a Kelvin-sign homoglyph standing in for that letter in the certified, printed owner/repo (`validation-2026-09-12-round3-byconstruction-proof.txt` part 3, reproduced concretely with `destination: kodak/toolkit`). It cannot occur in the host, since `github.com` itself contains no `k`. Accepted for the same reason the rest of this residual is: the escaping byte is a printable letter homoglyph, never a credential, control character, or length amplifier, and the shipped destination `goodwind-cz/aai` contains no `k` today, so the exception set is empty for this repository.

## Open question handed to the owner

`evidence_ref` on a filed friction issue frequently points at a gitignored,
machine-local path — `#371`'s own does. Two answers, either acceptable:

- **(a) Omit it when it demonstrably cannot travel.** The engine already knows the
  path shape, and `docs/ai/friction/**` is gitignored by this layer, so a path
  under it can be dropped deterministically. The body loses a field that was
  never actionable.
- **(b) Keep it and label it reporter-local.** One word of prefix in the fact
  line, no field removed, the maintainer stops trying to open it.

Both change the transmitted record, which `#371` fenced off, so neither is taken
here. Recommendation if asked: (b), because it is additive, keeps the field for
the reporter's own later reference, and does not require the engine to reason
about what the destination can resolve.
