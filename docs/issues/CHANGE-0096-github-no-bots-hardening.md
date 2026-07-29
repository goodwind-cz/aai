---
id: github-no-bots-hardening
number: 96
type: change
status: done
user_visible: false
links:
  parent: docs/issues/CHANGE-0085-platform-portable-pr.md
  spec: docs/specs/SPEC-0103-spec-platform-portable-pr.md
  pr:
    - 199
  commits:
    - ca338c9354fd6e080aa0c0cbe73c71d79a922884
---

# Change — R1 GitHub-no-bots hardening: reviewer_bots knob so the PR sweep never waits for bots that will never arrive

## Summary
- SPEC-0103/CHANGE-0085 made the PR ceremony platform-portable: pr-platform.mjs
  classifies the remote (github/azure/unknown/none) and SKILL_PR step 5d
  substitutes an internal SKILL_CODE_REVIEW whenever the platform has no bot
  layer, detected as `platform != github`.
- Residual gap GITHUB-WITHOUT-BOTS: on a GitHub repo where NO reviewer bots
  (Copilot/Codex) are installed, GitHub IS detected, so the bot path is taken
  and the empty-sweep shortcut ("no bot findings" -> stop) is legal — but the
  sweep can WAIT for inline comments that will never arrive, and no internal
  review is substituted, so review is silently skipped.
- Fix (deterministic, no LLM judgment): a repo-local `reviewer_bots` knob in
  docs/ai/pr-config.yaml, surfaced by pr-platform.mjs as
  `reviewer_bots=<expected|none|unknown>`, plus a bounded-wait belt-and-braces
  rule in SKILL_PR 5d. absent == none (assume-none) routes github-without-bots
  through the same internal-review fallback as Azure; the empty-sweep shortcut
  is legal only when `reviewer_bots == expected`.

## Scope
- In scope:
  - pr-platform.mjs: read the repo-local reviewer_bots knob (column-0 line scan
    of docs/ai/pr-config.yaml, --pr-config override for tests, cwd-independent
    default via git rev-parse --show-toplevel) and emit reviewer_bots in the
    text line and --json. Closed tri-state expected/none/unknown; absent file
    or key == none; invalid value == unknown (stderr warn, fail-open).
  - SKILL_PR step 5/5d: PLATFORM GATE notes the reviewer_bots field; the
    empty-sweep shortcut is gated on reviewer_bots == expected; the
    REVIEWER-FALLBACK CONTRACT detection widens from platform != github to zero
    bot-authored threads AND reviewer_bots != expected; a BOUNDED-WAIT rule
    (default 10 minutes after CI green) guarantees the sweep never waits forever.
  - docs/ai/pr-config.yaml: this repo declares reviewer_bots expected (it has
    Copilot + Codex) so its existing bot-sweep behavior is preserved.
  - tests: reviewer_bots classification fixtures + text/json shape + a
    grep-contract pin on the 5d hardening; prompt-diet ledger true-up.
- Out of scope: probing GitHub for installed apps at runtime (no normal-token
  API); auto-seeding pr-config.yaml into target repos (assume-none makes the
  file optional — future enhancement, mirroring update-config seeding).

## Acceptance Criteria
- AC-001: pr-platform.mjs classifies reviewer_bots deterministically as
  expected/none/unknown from the docs/ai/pr-config.yaml knob (absent == none,
  invalid == unknown with a stderr warning, exit still 0) and emits it in both
  text and --json output; suite-verified.
- AC-002: SKILL_PR 5d empty-sweep shortcut is legal only when reviewer_bots ==
  expected; a GitHub repo with reviewer_bots none/unknown/absent takes the
  internal SKILL_CODE_REVIEW fallback; grep-pinned.
- AC-003: SKILL_PR 5d carries a bounded-wait rule so the bot sweep never waits
  indefinitely for comments that will never arrive; grep-pinned.

## Verification
- bash tests/skills/test-aai-pr-platform.sh (TEST-011 updated, TEST-019..022 new)
- bash tests/skills/test-aai-prompt-diet.sh (ledger true-up + TEST-012 pin)
- RED/GREEN evidence under docs/ai/tdd/*-github-no-bots.log and
  docs/ai/tdd/*-diet-ledger-bump.log

## Constraints / Risks
- Ceremony L2. Deterministic knob + bounded wait; no live external service.
- Behavior change: a github-with-bots repo that never adopts the knob now takes
  the internal-review fallback (safe direction — review still happens) instead
  of the bot-only sweep. Repos with bots opt into reviewer_bots expected.
