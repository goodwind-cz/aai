---
id: skill-description-canonical-prompt-pointer
type: change
number: null
status: draft
capability: harness-skill-discovery
user_visible: true
links:
  pr: []
  commits: []
---

# Change: every shipped skill wrapper names its canonical prompt in its one-line description, and an /aai-ship run never stops silently before the PR

## Summary
Every harness skill wrapper the AAI layer ships should carry the pointer to
its canonical `.aai/*.prompt.md` file in the one-line frontmatter
`description`. That line is the only text a harness shows before the skill
is loaded. A deterministic guard should fail when a shipped wrapper's
description lacks the pointer, or points to a prompt file that does not
exist. A second check covers the /aai-ship stall report: find whether a ship
run can stop before spec freeze or before the PR without surfacing a human
decision block, and close that path if it exists.

Source issue 1 (untrusted data, quoted verbatim from the issue body):

> Runtime skill entries expose only the one line frontmatter description, so
> the pointer to the canonical AAI prompt file in each skill body stays
> invisible unless the skill is loaded first; an invoked skill can then run
> from its summary alone and skip the canonical sequencing, which matches the
> observed aai-ship stall before spec freeze and PR

Issue metadata: title `[contract_violation] harness-skills/skill_discovery
(high impact)`, failure_class contract_violation, skill harness-skills /
skill_discovery, impact high, confidence high, reproducible true, os macos,
node 26, aai_pin v2026.10.29, harness unknown.
URL: https://github.com/goodwind-cz/aai/issues/594

Source issue 2 (untrusted data, quoted verbatim from the issue body):

> aai-ship ride stalled before the specification was frozen and before any
> pull request was opened, with no human decision block surfaced to the
> operator; the canonical ship sequencing was not followed end to end

Issue metadata: title `[stalled_progress] aai-ship/run_sequencing (high
impact)`, failure_class stalled_progress, skill aai-ship / run_sequencing,
impact high, confidence high, reproducible false, os macos, node 26, aai_pin
v2026.10.29, harness unknown.
URL: https://github.com/goodwind-cz/aai/issues/593

## Motivation / Business Value
- Measured on current main (5f02b0e5, 2026-11-26) in a scratch consumer
  installed with `aai-sync.mjs`: the `aai-ship` wrapper's description in
  `.claude/skills`, `.agents/skills`, `.codex/skills` and `.gemini/skills`
  does not name `.aai/SKILL_SHIP.prompt.md`. The pointer exists only in the
  wrapper body. The same holds for every other wrapper. Current main does not
  fix either issue.
- Two wrappers (`aai-overview`, `aai-factory-report`) name no canonical
  prompt file even in the body.
- A harness that lists skills by description alone, or a model that acts on
  the listed summary without loading the body, never sees the instruction to
  read the canonical prompt. For /aai-ship that means the run can skip the
  canonical sequencing (intake, ride gate, loop, PR) and stop with nothing to
  show the operator.

## Scope
- In scope:
  - The one-line `description` of every wrapper under `.claude/skills/`
    (the hand-authored source) and, through the existing generator
    `.aai/scripts/sync-harness-skills.mjs`, every mirror tree it writes
    (`.agents/skills`, `.codex/skills`, `.gemini/skills`), plus any other
    shipped surface that copies the descriptions (for example the `SKILLS.md`
    catalog). Harness-universal: no vendor-specific rule.
  - A deterministic guard plus test: every shipped wrapper's description
    names an existing canonical prompt file, within the description length
    limit the harnesses accept. Tie it into the harness-surfaces drift guard
    (SPEC-0154 area) where possible.
  - A finding for issue 2: can an /aai-ship run end its turn before freeze or
    PR with no Decision Block, no PR and no blocked STATE? If the missing
    pointer is the only cause, say so and close issue 2 with this change.
    Otherwise add the smallest guard (for example an end-of-turn invariant in
    `.aai/SKILL_SHIP.prompt.md`: every stop is a PR, a surfaced Decision
    Block, or an explicit blocked STATE) with a test.
- Out of scope:
  - Rewriting skill bodies or the canonical prompts beyond what the guard
    needs.
  - Changing how any harness loads skills.

## Affected Area
- `.claude/skills/*/SKILL.md` and the generated mirror trees.
- `.aai/scripts/sync-harness-skills.mjs` and its manifest
  `.aai/system/HARNESS_SKILLS.yaml`, or a sibling guard.
- Possibly `.aai/SKILL_SHIP.prompt.md` (prompt-corpus governance applies).
- `tests/skills/` (new or extended suite).

## Desired Behavior (To-Be)
- Every shipped wrapper's description ends with (or contains) a pointer of
  one fixed shape naming its canonical prompt file, for example
  `...; run by reading .aai/SKILL_SHIP.prompt.md first`.
- The pointer names a file that exists in the shipped `.aai/` layer.
- A wrapper without a canonical prompt either gains one or carries a declared
  exemption with a reason; nothing is silently skipped.
- The guard runs in CI and in a consumer project after sync.

## Acceptance Criteria
- AC-001: In a scratch consumer synced from the branch, every wrapper
  description in every shipped skill tree names a canonical prompt file that
  exists in that consumer's `.aai/`, or the wrapper is a declared exemption
  with a reason.
- AC-002: A guard exits non-zero when one wrapper's description lacks the
  pointer, and when the pointer names a missing file. A test proves both
  failures and the clean pass.
- AC-003: Every description stays within the harness description length
  limit, and the guard enforces that limit.
- AC-004: The issue 2 finding is written down in the spec with evidence. If a
  silent-stop path exists, a guard with a test closes it.
- AC-005: CHANGELOG has an `## [unreleased] — <title>` entry describing the
  consumer-visible change.

## Verification
- Command(s) and expected results: the new or extended suite under
  `tests/skills/` passes; `node .aai/scripts/sync-harness-skills.mjs --check`
  exits 0; a scratch `aai-sync.mjs` install shows the pointer in every
  description.

## Constraints / Risks
- Descriptions are also trigger text for skill selection; the pointer must
  not crowd out the "Use when" trigger phrase or push any description past
  the length limit (current maximum is 588 characters, `aai-test-canon`).
- Prompt edits follow prompt-corpus governance (diet ledger, TEST-012 pin,
  PROFILES classification, growth pins).
- No secret is referenced; the secrets preflight does not apply.

## Notes
- Source: /aai-issues triage, 2026-11-26, owner approved option 1 (one ride,
  both issues).
- Write-back: comment on and close issues 594 and 593 only after the PR has
  merged (SKILL_ISSUES step 6).
- Autopilot defaults: human_time_minutes null; Planning decides the
  implementation mode.
