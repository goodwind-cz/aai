---
id: harness-surfaces-drift-unguarded
type: issue
number: null
status: draft
links:
  pr: []
  commits: []
---

# Harness surfaces drift for months because nothing compares them

## Summary
- The per-harness integration surfaces (`.codex/skills/`, `.gemini/skills/`,
  `.cursor/rules/aai.mdc`, root `AGENTS.md`) have drifted from
  `.claude/skills/` for months, and no test, script, or registry item
  compares them. The owner found it by hand: Codex does not offer
  `/aai-ship`.

## Type
- bug

## Impact
- `.claude/skills/` carries 39 skills; `.codex/skills/` and `.gemini/skills/`
  carry 31 each. Eight are missing from both, identically: `aai-ship`,
  `aai-overview`, `aai-factory-report`, `aai-docs-audit`, `aai-docs-canon`,
  `aai-feedback-triage`, `aai-feedback-upsert`, `aai-test-canon`.
- Codex discovers project skills from `.codex/skills/` only, so those eight
  are genuinely invisible there — the owner's observed symptom.
- The drift is old, not a recent slip: the newest skill in `.codex/skills/`
  dates to 2026-03-29, while `aai-ship`/`aai-overview` landed 2026-07-26,
  `aai-docs-audit` 2026-07-19 and `aai-factory-report` 2026-07-30.
- `.cursor/rules/aai.mdc` has not changed since 2026-03-19 and now states a
  falsehood: "Skills are prompt files. Invoke by reading and following the
  file." Cursor has had native skills since then, discovers them from
  `.cursor/skills/`, `.agents/skills/` AND — for compatibility —
  `.claude/skills/` and `.codex/skills/`, invoked as `/skill-name` or
  attached as `@skill-name`. The rule teaches the harness's users a workflow
  the harness no longer requires, and hardcodes 5 of the 39 skills.
- Severity/priority: P2. Nothing is corrupted, but a whole harness silently
  offers a reduced feature set, and the owner reports Cursor is about to
  become a heavily used surface.

## Current Behavior
- `aai-sync.{sh,ps1}` copies `.codex/skills`, `.gemini/skills` and
  `.cursor/rules/aai.mdc` from the vendored source to a target with
  `copy_replace`. It never compares the skill SET against `.claude/skills/`,
  so a skill added to `.claude/` alone propagates nowhere and nothing warns.
- `tests/skills/` mentions `.codex/skills` only as a `skills.local` gitignore
  assertion in the bootstrap suite, and `.cursor` only inside a directory
  list in the layer-profiles suite. No parity assertion exists anywhere.
- The mirrors are NOT verbatim copies (each has its own shorter
  `description` and no `model:` line), so the gap cannot be closed by a
  blanket copy and is invisible to a byte-comparison.

## Expected Behavior
- Every skill exposed to Claude Code is exposed to the harnesses this repo
  claims to support, or its absence is a recorded, deliberate decision.
- `.cursor/rules/aai.mdc` describes Cursor as it exists today: native skill
  discovery (including the `.claude/skills/` compatibility path), correct
  `.mdc` frontmatter per the current Cursor rules documentation, no
  hardcoded partial skill list that goes stale the next time a skill lands.
- A suite arm compares the harness skill sets and fails on any divergence,
  so the next drift is caught the day it appears rather than after five
  months by a human noticing a missing slash command.

## Steps to Reproduce (if applicable)
1) `ls .claude/skills | wc -l` -> 39; `ls .codex/skills | grep -v README | wc -l` -> 31.
2) `comm -23 <(ls .claude/skills | sort) <(ls .codex/skills | grep -v README | sort)`
   -> the eight names above; same for `.gemini/skills`.
3) Open Codex in this repo: `/aai-ship` is not offered.
4) `git log -1 --date=short --format=%ad -- .cursor/rules/aai.mdc` -> 2026-03-19.

## Verification
- A new suite arm computes the three skill-name sets and fails on any
  difference, shown red against the pre-fix tree and green after.
- `ls` counts equal across `.claude/skills`, `.codex/skills`,
  `.gemini/skills` after the fix.
- `.cursor/rules/aai.mdc` contains no claim contradicted by the current
  Cursor documentation, and no enumerated skill list that can go stale.

## Constraints / Risks
- The mirrors carry harness-specific descriptions; generating them by copy
  would flatten that difference. Either the difference is meaningful (then
  the eight new shims are authored, not copied) or it is not (then say so
  and normalize deliberately) — decide, do not drift again.
- Cursor loads BOTH `.claude/skills/` and `.codex/skills/`, so all 31 shared
  names are offered twice with different descriptions and the Cursor
  documentation does not state a dedup or precedence rule. Whatever the fix
  does must not make that worse; naming the ambiguity is in scope, resolving
  Cursor's internal behavior is not.
- Root `AGENTS.md` is titled "Codex Instructions (Shim)" but Cursor reads
  root `AGENTS.md` too; the title now misdescribes its audience.
- `.aai/*.prompt.md` corpus is at 0/2048 headroom — if any prompt byte is
  needed, it is measured and ledgered 1:1 (TEST-012 pin currently 2392).
  `.cursor/rules/aai.mdc`, `AGENTS.md` and the mirror `SKILL.md` files are
  OUTSIDE that corpus glob (verify before assuming).
- No secrets referenced.

## Notes
- Cursor documentation consulted 2026-08-25: rules live in `.cursor/rules`
  as `.mdc` with `description` / `globs` / `alwaysApply` frontmatter, four
  activation modes, "keep rules under 500 lines", `@file` references
  recommended to keep rules short and non-stale; skills load from
  `.agents/skills/`, `.cursor/skills/`, `~/` equivalents and the
  `.claude/skills/` + `.codex/skills/` compatibility paths.
- Codex documentation consulted 2026-08-25: project skills are discovered
  from `.codex/skills/` (any directory with a `SKILL.md`), invoked via
  `/skills` or `$skill-name`.
- This issue records ONLY the drift and the missing guard. Whether the repo
  should also ship `.cursor/skills/` is a Planning decision, not an intake
  assumption.
