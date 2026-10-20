---
id: sync-prune-retired-skill-wrappers
number: 104
type: issue
status: done
user_visible: true
capability: aai-update
links:
  pr: []
  commits: []
---

# Sync leaves retired template skill wrappers behind in .claude/skills and .agents/skills

## Summary
- `aai-sync.sh` and `aai-sync.ps1` copy `.claude/skills/` and `.agents/skills/` entry by entry and deliberately preserve target-only entries, so a project's own skills survive a sync. A template skill that upstream retires (example: `aai-decapod`, removed by CHANGE-0077 / PR #177) is then target-only downstream and survives every later sync, while its `.aai/SKILL_DECAPOD.prompt.md` is removed by the stale-`.aai` cleanup. The harness keeps listing `/aai-decapod`, and invoking it answers "SKILL_DECAPOD not found — are you in an AAI project?".
- `.codex/skills/` and `.gemini/skills/` are replaced wholesale, so they do not have this defect; only the two entry-by-entry trees do.

## Type
- bug

## Impact
- Every downstream repository synced before a template skill was retired and updated after it: the dead skill stays in the skill menu of Claude Code and of every harness reading `.agents/skills/` (Gemini CLI, Cursor), and fails on use. Today this affects `aai-decapod`; it will affect every future retirement.
- Severity/priority: P3. No data loss or unsafe write; a dead menu entry that misleads the operator into thinking the layer is broken.

## Current Behavior
- `.aai/scripts/aai-sync.sh` (block "Claude Code skills", around lines 379-399, and "Agents skill index", around lines 516-546) iterates source entries only and prints `PRESERVE target-only skills under: ...`; nothing ever removes a target entry.
- `.aai/scripts/aai-sync.ps1` (around lines 343-365 and 520-548) mirrors the same behavior.
- The stale top-level `.aai/` cleanup (aai-sync.sh around lines 351-361) removes `.aai/SKILL_<NAME>.prompt.md` once upstream deletes it, so the leftover wrapper points at a file that no longer exists.

## Expected Behavior
- A sync removes a target entry under `.claude/skills/` or `.agents/skills/` only when ALL hold:
  1. the entry name is absent from the source tree of the same path;
  2. its `SKILL.md` has the template shim shape: frontmatter `name:` equal to the directory name, and a body that only delegates to one `.aai/SKILL_<NAME>.prompt.md` (the "Read the file ... and follow its instructions exactly" line plus the "not found" line);
  3. that referenced `.aai/SKILL_<NAME>.prompt.md` does not exist in the source layer.
- Each removal prints a named line (e.g. `CLEAN removed retired skill wrapper: .claude/skills/aai-decapod`) and is recorded like the other sync deletions.
- Everything else stays: project-owned skills (any `aai-project-*` entry, any entry whose `SKILL.md` is not the shim shape, any entry that references a prompt still shipped, any non-directory entry) are preserved exactly as today.
- Bash and PowerShell behave the same.

## Steps to Reproduce (if applicable)
1) Sync the layer into a scratch target from a source that still has `aai-decapod` (e.g. a checkout of commit `070a6163^`).
2) Sync the same target again from current main.
3) Observe `.claude/skills/aai-decapod/` and `.agents/skills/aai-decapod/` still present while `.aai/SKILL_DECAPOD.prompt.md` is gone.

## Verification
- Bash suite: a target carrying a retired shim wrapper in both trees loses both after a sync, with the named line printed; a project-owned skill (`aai-project-x`), a hand-edited non-shim `aai-something` wrapper, and a target-only wrapper whose referenced prompt is still shipped by the source all survive byte-identical.
- PowerShell parity case covering the same fixtures (run where `pwsh` is available, skipped with a named line otherwise, matching the suite's existing convention).
- Existing sync suites stay green.

## Constraints / Risks
- Assumption: the shim-shape check is the safety boundary; a project that hand-edited a retired template wrapper keeps it (it is then project-owned in effect). Planning defines the exact shape match (line-ending and trailing-newline tolerant).
- Risk: a false positive deletes a project's skill. Mitigation: all three conditions above must hold, and the referenced prompt must be absent from the source layer, not merely from the target.
- `--dry-run`/preview paths of the sync (if any) must report the removal without performing it.
- Secrets preflight: no secret referenced.

## Notes
- Metrics: human_time_minutes null (autopilot default). No clarifying questions asked; assumptions above are explicit.
- Implementation mode: not chosen at intake (autopilot); Planning decides.
- Source: owner question about the leftover `aai-decapod` skill, 2026-10-19.
