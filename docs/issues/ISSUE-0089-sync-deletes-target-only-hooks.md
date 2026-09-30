---
id: sync-deletes-target-only-hooks
type: issue
number: 89
status: draft
links:
  pr: []
  commits: []
---

# Hotfix — aai-sync deletes target-only files under hooks/ and the advisory never says so

## Summary
- `aai-sync.sh` copies `hooks/` with `copy_replace`, which is `rm -rf "$dst"` followed by `cp -a`. Every target-only file under `hooks/` is therefore deleted by construction on each sync.
- The conflict advisory that exists to make sync damage reviewable models OVERWRITES only. Deletion is outside its vocabulary, so the destructive half of a sync run has no review surface at all.
- Reported as GitHub issue #414 against pin `v2026.09.30`, commit `beb6a24`, profile `extended`.

## Type
- hotfix

## Impact
- Every downstream project that vendors the AAI layer and keeps a project-owned hook. The reporter lost `hooks/merge-guard.{sh,ps1,py}` and the `PreToolUse` -> `Bash` registration in both `hooks/hooks.json` and `hooks/hooks.windows.json`.
- What the deleted hook enforced is the constitution's own boundary: an agent must not reach `git merge` / `gh pr merge`. A sync silently disarms it, so the loss is of a SAFETY control, not of a convenience.
- Silent and recurring: it repeats on every sync until the rule changes, and neither the advisory, the changed-file evidence block, nor `aai-doctor` named it. `aai-doctor` reported DEGRADED with three warnings, none about the removed guard (`CAT-09` covers the pre-compact hook, a different one).
- Downstream test damage observed by the reporter: `tests/hooks/merge-guard.sh` 14 failures, all exit 127 (script absent); `tests/conversational-intake/verify.sh` `TEST-009` "no merge guard registered in hooks.json; windows hooks UNGUARDED".
- Severity: high. Confidence high, reproducible true, workaround manual.

## Current Behavior
- `aai-sync.sh:548-552` syncs `hooks/` through `copy_replace "$SRC_ROOT/hooks" "$DST_ROOT/hooks"`. `copy_replace` does `rm -rf "$dst"` then `cp -a "$src" "$dst"`, so the target directory is replaced wholesale.
- The advisory (`aai-sync.sh:741-751`) is generated from the single `OVERWRITE_CONFLICTS` array and opens with "The following target files/directories had local content that differed from sync source and were overwritten." Nothing appends a deletion to it, and no second array exists.
- A run that deletes three files and strips two JSON registrations can therefore print an advisory naming six unrelated overwrites and zero deletions.

## Expected Behavior
- `hooks/` preserves target-only files, the way `.aai/scripts/` and `.claude/skills/` already do. The precedent is in the same script: a file-by-file merge that overwrites source-owned entries and logs `PRESERVE target-only ...` for the rest.
- Any destructive sync action — deletion included — appears in the conflict advisory as a first-class category, so the advisory is honest even for a directory where preserve does not apply.
- A sync that deletes nothing keeps its current output unchanged.

## Steps to Reproduce
1) In a project that vendors the AAI layer, add a target-only file under `hooks/` and register it in `hooks/hooks.json`.
2) Run `/aai-update` (or `.aai/scripts/aai-update.sh`) against canonical `main`.
3) The file is deleted and the registration is gone; the generated `docs/ai/reports/sync-conflicts-*.md` mentions neither.

## Verification
- A sync fixture with a target-only file under `hooks/` keeps that file, and the run logs a `PRESERVE target-only` line naming it.
- A sync fixture where a deletion DOES occur produces an advisory that names the deleted path under a deletions heading; the existing overwrite section is unchanged.
- A sync fixture with no deletions produces an advisory byte-identical to today's for the same inputs (no empty deletions section, no reordering).
- `env -u AAI_ROLE bash tests/skills/test-aai-layer-drift.sh`, `test-aai-layer-profiles.sh`, `test-aai-sync-seed.sh` and `test-aai-bootstrap.sh` exit 0.

## Constraints / Risks
- `hooks/hooks.json` and `hooks/hooks.windows.json` are SOURCE-owned files that a downstream project must also be able to extend. Preserving target-only FILES does not by itself preserve a target-added ENTRY inside a source-owned JSON — the reporter lost both, and the second half is the harder problem. Scoping decision belongs to Planning; this intake records that the registration loss is part of the reported damage.
- Preserving too much is its own failure: a stale hook the source deliberately removed must still disappear, or sync stops being able to retire anything.
- The advisory change must not turn a non-destructive run's report into a different shape — the byte-identical arm above is the guard against that.
- The reporter notes a second observation, not filed: vendored `.aai/routines/SCRYER.routine.md` and `.aai/scripts/lane-gate.mjs` carry agent-reachable merge references that keep `TEST-009` failing even after the guard is restored. Out of scope here.
- The reporter also notes their project gitignores `.aai/` wholesale, so that half of the sync's changes never reached the changed-file report. Out of scope here, but it means the changed-file list is not a substitute for the advisory.
- No secret referenced; secrets preflight skipped.

## Notes
- Source: https://github.com/goodwind-cz/aai/issues/414 (triaged via `/aai-issues`). The issue body and its follow-up comment are quoted below as DATA.
- Triage verified both claims against the code before filing, rather than taking the report's word: `copy_replace` is `rm -rf` + `cp -a` (`aai-sync.sh`), and the advisory's own heading admits only overwrites.
- Reporter's own suggested fix, as data:

> - Extend the `PRESERVE target-only` rule from `.claude/skills` to `hooks/`, matching the precedent already in the sync engine.
> - Make the conflict advisory report **deletions** as a first-class category alongside overwrites, so any destructive sync action has a review surface even where preserve does not apply.

- Reporter's environment, as data: `os_family: macos`, `node_major: 22`, `aai_pin: v2026.09.30`, `harness: claude`, `recurrence: 1`, `score: 8`, fingerprint `54e5543d5bc988e0a8644d6ba53af6ad`.
- Workaround in use downstream: `git checkout` of the five paths after each sync. Manual, and it repeats every time.
