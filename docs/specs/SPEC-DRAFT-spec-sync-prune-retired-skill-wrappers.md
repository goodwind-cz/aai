---
id: spec-sync-prune-retired-skill-wrappers
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: 59498bbd9356f395ee078f46b83fe3e479dbae5d9c10f5691ed9476769d4361f
ceremony_level: 2
capability: aai-update
user_visible: true
links:
  requirement: sync-prune-retired-skill-wrappers
  rfc: null
  pr: []
  commits: []
---

# Sync removes retired template skill wrappers from .claude/skills and .agents/skills

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/ISSUE-DRAFT-sync-prune-retired-skill-wrappers.md
- Engines changed: .aai/scripts/aai-sync.sh, .aai/scripts/aai-sync.ps1
- Read, not changed: .aai/scripts/sync-harness-skills.mjs (carries `.claude/skills` bodies verbatim into `.agents/skills`), .aai/scripts/aai-doctor.mjs (CAT-03 orphaned-wrapper check), .aai/scripts/aai-bootstrap.sh (`render_skill`, target-only dynamic skills)
- Retirement precedent: commit 070a6163 (CHANGE-0077 / PR #177) removed `aai-decapod` from both trees and `.aai/SKILL_DECAPOD.prompt.md`
- Technology contract: docs/TECHNOLOGY.md (bash-3.2 compatible shell, PowerShell 5.1 compatible mirror)

## Implementation strategy
- Strategy: tdd
- Rationale: the change adds a deletion to a sync that until now deleted nothing under these two trees, in a directory where projects keep their own skills. The safety boundary is a shape matcher; a false positive destroys project content. Each removal arm is RED on the pre-change engine (it removes nothing), and each preservation arm, which is GREEN on the pre-change engine by construction, gets its RED from a recorded mutation that weakens exactly one condition of the matcher. Two engines must agree, so the parity arm is RED-first too.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: two engines plus the slowest sync suite, PR-bound; the shared main checkout is used by other sessions.
- User decision: worktree (recorded before Planning, autopilot default)
- Base ref: main
- Worktree branch/path: fix/sync-prune-retired-skill-wrappers at /private/tmp/aai-sync-prune-retired-skill-wrappers-worktree
- Inline review scope: n/a (worktree)
- Code review required: true; scope .aai/scripts/aai-sync.sh .aai/scripts/aai-sync.ps1 tests/skills/test-aai-sync-seed.sh docs/product/aai-update.md CHANGELOG.md docs/specs/SPEC-DRAFT-spec-sync-prune-retired-skill-wrappers.md docs/issues/ISSUE-DRAFT-sync-prune-retired-skill-wrappers.md

## Constitution deviations

None.

Article 5 (additive first): this is a deliberate behavior change at the sync boundary. It is explicit and documented: every removal prints a named line, is listed in the existing sync advisory report, and is described in docs/product/aai-update.md and the CHANGELOG entry. Article 4: nothing is removed in silence. Article 2: the matcher is derived from the 42 shipped wrappers, nothing speculative.

## Facts measured by Planning (2026-10-19)

- aai-sync.sh "Claude Code skills" (lines 379-399) and "Agents skill index" (lines 516-546) iterate source entries only and end with `PRESERVE target-only skills under: ...`. aai-sync.ps1 lines 343-365 and 520-548 mirror them. `.codex/skills` and `.gemini/skills` are replaced wholesale (no defect).
- The extended-profile stale cleanup (aai-sync.sh lines 351-361, ps1 317-324) runs BEFORE the skills blocks and removes `.aai/SKILL_<NAME>.prompt.md` once the source drops it, appending to `DELETIONS` / `$deletions`, which the advisory report (aai-sync.sh 855-890) renders under `## Deleted items`.
- `.claude/skills` is the only hand-authored tree; sync-harness-skills.mjs carries every body verbatim into `.agents/skills` (it only drops the `model:` key). It does not generate the shim text itself, so the shim shape below is derived from the 42 shipped wrappers in each tree: 39 delegate to one `.aai/SKILL_<X>.prompt.md`; 16 of those open with a 3-line `<SUBAGENT-STOP>` block; `aai-merge` invokes as `/aai-merge <PR>` (arguments inside the backticks); `aai-docs-hub` also carries a README.md; `aai-factory-report` and `aai-overview` run a node script and reference no prompt. Frontmatter keys used: name, description, model. No shipped wrapper is CRLF.
- The retired `aai-decapod` wrapper at 070a6163^ is byte-identical in both trees and has the plain shape (no SUBAGENT-STOP block).
- aai-bootstrap.sh writes target-only dynamic skills (`aai-test-unit`, `aai-test-e2e`, `aai-build`, `aai-lint`) via `render_skill`: a `# <name>` heading and a fenced command, no `.aai/SKILL_` delegation. They must survive.
- aai-doctor.mjs CAT-03 reports WARN `orphaned: <dir> -> .aai/SKILL_X.prompt.md` for any `.claude/skills/aai-*` wrapper whose referenced prompt is missing in the target: the user-visible symptom this scope removes.
- aai-sync has no dry-run or preview path; `aai-update --dry-run` prints `Would run: ... aai-sync ...` and never invokes the sync. The intake's dry-run constraint is therefore satisfied without new code (no AC).

## Design decisions

- D1 Placement. In each of the two blocks, after the existing source-copy loop and before the `PRESERVE target-only skills under:` line, one shared bash helper `remove_retired_skill_wrappers() {` (taking the tree's relative path, `.claude/skills` or `.agents/skills`) walks the TARGET tree and, for each entry whose name has no entry in the SOURCE tree of the same path, calls `is_retired_skill_wrapper() {` and removes the entry when it returns 0. The PowerShell mirror uses one helper for both trees and `function Test-RetiredSkillWrapper([string]$EntryPath, [string]$EntryName) {` (inline parameter list; no `param()` block). The `PRESERVE target-only skills under:` line stays.
- D2 Retired-wrapper predicate. `is_retired_skill_wrapper` / `Test-RetiredSkillWrapper` return true only when ALL hold, and every check lives inside the predicate:
  1. the entry is a real directory, not a symlink and not a file;
  2. the entry name does not match `aai-project-*` (project-owned by convention);
  3. the directory contains exactly one entry, a regular file whose on-disk name is exactly `SKILL.md` (byte-exact, case-sensitive: a lowercase `skill.md` does not qualify even on a case-insensitive filesystem);
  4. the file, read as raw bytes (a leading UTF-8 BOM is NOT stripped, so a BOM-prefixed file is not a shim and is preserved by both engines), after removing every CR byte and ignoring trailing blank lines, starts with a `---` line, has a closing `---` line, and its frontmatter has a line `name: <entry name>` (other frontmatter lines are not inspected);
  5. the body's non-blank lines are exactly, in order: an optional block of a `<SUBAGENT-STOP>` line, one or more lines, and a `</SUBAGENT-STOP>` line; then the line ``Read the file `.aai/SKILL_<X>.prompt.md` from the current project root and follow its instructions exactly`` continued on the same line by any text that contains ``Invoke this as ` ``, ends with `.` and contains no further `.aai/` reference (AMENDED during implementation and tightened in remediation, see the spec_amendment records for this ref_id in docs/ai/decisions.jsonl: the shipped `aai-auto-trigger` and `aai-roadmap` wrappers carry extra clauses and backticks around the invoke text, but a wrapper that also names another `.aai/` path is not a pure shim); then the line ``If `.aai/SKILL_<X>.prompt.md` does not exist, say: "SKILL_<X> not found — are you in an AAI project? Expected: .aai/SKILL_<X>.prompt.md"``; where `<X>` matches `[A-Z0-9_]+` and is the same in all four places;
  6. `"$SRC_ROOT/.aai/SKILL_<X>.prompt.md"` does not exist (the SOURCE layer, never the target).
  Hidden (dot-prefixed) entry names are never candidates: both engines skip them (bash by glob, ps1 by an explicit name check).
- D3 Removal record. The helper removes the directory, appends `<tree>/<name>` (for example `.claude/skills/aai-retired`) to `DELETIONS` / `$deletions`, and prints exactly `  CLEAN removed retired skill wrapper: <tree>/<name>` once per removed entry. The existing advisory report then lists it under `## Deleted items` with no new code.
- D4 Pinned literals (the Test Plan's mutations address them; changing one is a spec amendment): in aai-sync.sh the strings `remove_retired_skill_wrappers() {`, `is_retired_skill_wrapper() {`, `CLEAN removed retired skill wrapper: `, `<SUBAGENT-STOP>`, `follow its instructions exactly`, `aai-project-*` and `"$SRC_ROOT/.aai/SKILL_` each first occur inside the new helper or predicate, and the predicate strips CR with `tr -d '\r'` (the idiom aai-sync.sh already uses at line 76) as the first `tr -d '\r'` after the predicate's header; in aai-sync.ps1 `function Test-RetiredSkillWrapper(` and the same CLEAN text.
- D5 Profile independence. The predicate runs identically under `--profile core` and `extended` and always consults the source layer. Core-profile targets that receive wrappers whose prompts the core prune removed are a different defect and out of scope (see Out of scope).
- D6 Engine portability. bash 3.2 (no associative arrays, no `mapfile`, no `${var,,}`), no node dependency added to the sync path; PowerShell 5.1 (`Get-Content -Raw`, `-ceq`/`-cmatch` for case-sensitive comparison of names and lines).

## Out of scope

- Core-profile wrappers whose prompt is pruned from the target but still shipped by the source (D5). Registered at close as a follow-up, subject "core profile ships skill wrappers whose prompts the core prune removes".
- Non-directory legacy entries (for example the `.claude/skills/check-state.md` style removed by 361809e2) and multi-file template wrappers (`aai-docs-hub` shape): preserved; a future retirement of a multi-file wrapper still dangles (residual, recorded).
- `.codex/skills` and `.gemini/skills` (already wholesale-replaced).

## Acceptance Criteria Mapping

| Requirement | Spec-AC | Verification | Observable |
|-------------|---------|--------------|------------|
| Expected: retired shim removed in both trees, named, recorded | Spec-AC-01 | R test_820 | both dirs gone, two CLEAN lines, doctor CAT-03 PASS |
| Constraints: shape match is line-ending and trailing-newline tolerant; shipped variants count | Spec-AC-02 | R test_821, test_822 | SUBAGENT-STOP, argument-invoke, CRLF and no-final-newline wrappers removed |
| Expected: everything else stays | Spec-AC-03 | R test_823, test_824, test_825 | every preserved fixture byte-identical, no CLEAN line names it |
| Expected: recorded like the other sync deletions | Spec-AC-04 | R test_826 | advisory report lists both removed paths under Deleted items |
| Risk: false negatives on real shipped wrappers | Spec-AC-05 | R test_827 | every single-file shipped shim removed once retired; aai-docs-hub kept |
| Existing behavior: a quiet sync stays quiet | Spec-AC-06 | R test_828 | zero CLEAN retired lines, no advisory report |
| Expected: bash and PowerShell behave the same | Spec-AC-07 | R test_829, test_830 | identical CLEAN line sets and surviving trees across engines |

R = `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-sync-seed.sh <selector>`; exit 0 and the row's `PASS: TEST-8xx` line decide each row. The PowerShell rows follow the suite's convention: without `pwsh` they print a named SKIP line and set `PWSH_ARM_SKIPPED=1` (suite exit 42), never a silent pass.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN a target was synced from a source carrying `aai-retired` (decapod-shaped shim in `.claude/skills` and `.agents/skills` plus `.aai/SKILL_RETIRED.prompt.md`) and is then synced by aai-sync.sh from a source carrying none of the three, the system SHALL remove both wrapper directories and the prompt, print `CLEAN removed retired skill wrapper: .claude/skills/aai-retired` and `CLEAN removed retired skill wrapper: .agents/skills/aai-retired` exactly once each, and `node .aai/scripts/aai-doctor.mjs --root <target> --json` SHALL report CAT-03 status PASS | done | docs/ai/tdd/spec-sync-prune-retired-skill-wrappers/green-820.log | — | pre-change: dirs survive, CAT-03 WARN orphaned aai-retired |
| Spec-AC-02 | WHEN target-only wrappers whose prompts the source does not ship are (a) a shim opening with a 3-line SUBAGENT-STOP block and invoking as `/aai-gone <PR>`, and (b) a plain shim saved with CRLF line endings and no final newline, a bash sync SHALL remove each from both trees with one CLEAN line per removed path | done | docs/ai/tdd/spec-sync-prune-retired-skill-wrappers/green-821.log; docs/ai/tdd/spec-sync-prune-retired-skill-wrappers/green-822.log | — | — |
| Spec-AC-03 | WHEN the target carries in both trees target-only entries that fail any one D2 condition (an `aai-project-x` shim whose prompt is absent; a shim with one extra prose line; a shim plus a notes.md; a shim whose `name:` differs from its directory; a shim whose Read and not-found lines name different prompts; a non-directory `aai-file.md`; a symlink to a shim directory; a dynamic skill generated by the real aai-bootstrap.sh in the target; a shim delegating to `.aai/SKILL_TDD.prompt.md`, which the source ships) a bash sync SHALL leave every one byte-identical (sha256 of every file, and the symlink still a symlink) and print no CLEAN line naming any of them | done | docs/ai/tdd/spec-sync-prune-retired-skill-wrappers/green-823.log; docs/ai/tdd/spec-sync-prune-retired-skill-wrappers/green-824.log; docs/ai/tdd/spec-sync-prune-retired-skill-wrappers/green-825.log | — | GREEN pre-change by construction; RED via mutation |
| Spec-AC-04 | WHEN the Spec-AC-01 second sync runs, the advisory report it names SHALL contain `- Path: .claude/skills/aai-retired` and `- Path: .agents/skills/aai-retired` under `## Deleted items` | done | docs/ai/tdd/spec-sync-prune-retired-skill-wrappers/green-826.log | — | — |
| Spec-AC-05 | WHEN a bash sync runs into a target first synced from the full fixture source, from a copy of that source with every shipped wrapper that references a `.aai/SKILL_*.prompt.md`, and those prompts, removed from both trees, the system SHALL print one CLEAN line for each such wrapper whose directory holds only SKILL.md (at least 38 per tree, set computed by the test from file count and prompt reference, not by the predicate) and SHALL keep `aai-docs-hub` in both trees | done | docs/ai/tdd/spec-sync-prune-retired-skill-wrappers/green-827.log | — | proves the matcher accepts every shipped shape, incl. the .agents copies |
| Spec-AC-06 | WHEN a target already synced from the current source, plus one `aai-project-x` skill, is re-synced by aai-sync.sh, the output SHALL contain zero `CLEAN removed retired skill wrapper` lines and the run SHALL write no `sync-conflicts-*.md` report | done | docs/ai/tdd/spec-sync-prune-retired-skill-wrappers/green-828.log | — | GREEN pre-change; RED via mutation |
| Spec-AC-07 | WHEN the Spec-AC-01, Spec-AC-02 and Spec-AC-03 fixtures are synced by aai-sync.ps1 under pwsh, the sorted set of `CLEAN removed retired skill wrapper:` lines and the sorted list of surviving paths with sha256 under both trees SHALL equal the bash engine's on identical inputs, and the ps1 advisory report SHALL list both aai-retired paths under Deleted items | done | docs/ai/tdd/spec-sync-prune-retired-skill-wrappers/green-829.log; docs/ai/tdd/spec-sync-prune-retired-skill-wrappers/green-830.log | — | named SKIP without pwsh |

## Implementation plan

Components: `.aai/scripts/aai-sync.sh` (predicate, helper, two call sites); `.aai/scripts/aai-sync.ps1` (mirror); `tests/skills/test-aai-sync-seed.sh` (fixture builders and test_820..test_830, registered in `main()`); at ship time only, after LOOP COMPLETE: one paragraph in `docs/product/aai-update.md` and a `## [unreleased] — <title>` CHANGELOG entry (product docs are not part of the frozen AC table; the ship flow writes them after the flush).

Test fixtures: build sources with `_fixture_source_copy` and first syncs with `_sync_cached` wherever the first sync's output is discarded (the suite is the slowest in the sweep, fu-sync-seed-cache-no-ci-gain); re-syncs and captured stdout call the engine directly via `_hooks_run_engine`. Shim fixtures are written from the decapod bytes at 070a6163^ with the name substituted, not hand-retyped. The bootstrap dynamic skill comes from running the target's own `.aai/scripts/aai-bootstrap.sh` on a target seeded so that bootstrap emits at least one `aai-*` dynamic skill (the test asserts it exists before the re-sync, otherwise log_fail).

Edge cases: an empty target tree; a source without the tree (block skipped, nothing removed, unchanged); entry names with spaces are not produced by any shipped wrapper and are handled by quoting, not tested; a predicate read error (unreadable SKILL.md) returns false (preserve), never aborts the sync under `set -e`.

## Seams

- Stale `.aai` cleanup to skills block (same run): the cleanup removes the prompt first, the predicate reads the SOURCE layer; TEST-820 drives both in one real two-step sync and asserts both outcomes.
- Sync to advisory report: DELETIONS written by the new helper, rendered by the existing report block; TEST-826 reads the real report file.
- Sync to aai-doctor CAT-03: the doctor reads the synced target; TEST-820 runs the real doctor on it.
- sync-harness-skills.mjs to the predicate: `.agents/skills` bodies are generated copies; TEST-827 runs the predicate over the real shipped bytes of both trees.
- aai-bootstrap.sh to sync: bootstrap writes target-only skills the sync must keep; TEST-823 generates one with the real script.
- bash engine to ps1 engine: TEST-829 compares both engines' outputs on identical inputs.
- Residual, no automated test: Windows PowerShell 5.1 on a real Windows host (CI's Windows leg runs Pester suites, not this bash suite); covered only by D6's 5.1-compatible idioms and code review.

Registry items closed by this scope: none

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---------|---------|------|----------------------|-------------|----------|--------|
| TEST-820 | Spec-AC-01 | integration | tests/skills/test-aai-sync-seed.sh | test_820_retired_wrapper_removed_both_trees: two-step sync (source with aai-retired, then without); both dirs and the prompt gone, two CLEAN lines once each, doctor CAT-03 PASS | sed:s/is_retired_skill_wrapper\(\) \{/is_retired_skill_wrapper() { return 1;/ | green |
| TEST-821 | Spec-AC-02 | integration | tests/skills/test-aai-sync-seed.sh | test_821_subagent_stop_and_arg_invoke_shim_removed: SUBAGENT-STOP + `/aai-gone <PR>` shim removed in both trees | sed:s/<SUBAGENT-STOP>/<SUBAGENT-STOP-X>/ | green |
| TEST-822 | Spec-AC-02 | integration | tests/skills/test-aai-sync-seed.sh | test_822_crlf_no_final_newline_shim_removed: CRLF, no final newline shim removed in both trees | sed:s/(is_retired_skill_wrapper\(\) \{[\s\S]*?)tr -d '\\r'/$1cat/ | green |
| TEST-823 | Spec-AC-03 | integration | tests/skills/test-aai-sync-seed.sh | test_823_non_shim_entries_preserved: extra line, extra file, name mismatch, mixed refs, a shim with a further .aai/ reference, a lowercase skill.md-only dir, a BOM-prefixed shim, a hidden dot-dir shim, non-directory, symlink and bootstrap dynamic skill all byte-identical, no CLEAN line names them | sed:s/is_retired_skill_wrapper\(\) \{/is_retired_skill_wrapper() { return 0;/ | green |
| TEST-824 | Spec-AC-03 | integration | tests/skills/test-aai-sync-seed.sh | test_824_project_prefixed_shim_preserved: aai-project-x shim with an absent prompt byte-identical in both trees | sed:s/aai-project-\*/aai-project-never-*/ | green |
| TEST-825 | Spec-AC-03 | integration | tests/skills/test-aai-sync-seed.sh | test_825_shim_with_shipped_prompt_preserved: target-only shim delegating to SKILL_TDD byte-identical in both trees | sed:s/(is_retired_skill_wrapper\(\) \{[\s\S]*?)"\$SRC_ROOT\/\.aai\/SKILL_/$1"\/nonexistent\/.aai\/SKILL_/ | green |
| TEST-826 | Spec-AC-04 | integration | tests/skills/test-aai-sync-seed.sh | test_826_removal_listed_in_advisory: the report named on stdout lists both aai-retired paths under Deleted items | sed:s/(remove_retired_skill_wrappers\(\) \{[\s\S]*?)DELETIONS\+=/$1IGNORED_DELETIONS+=/ | green |
| TEST-827 | Spec-AC-05 | integration | tests/skills/test-aai-sync-seed.sh | test_827_every_shipped_shim_shape_recognized: strip all prompt-delegating wrappers and their prompts from a fixture source; one CLEAN line per single-file wrapper per tree (at least 38 each), aai-docs-hub kept | sed:s/follow its instructions exactly/follow its instruction exactly/ | green |
| TEST-828 | Spec-AC-06 | integration | tests/skills/test-aai-sync-seed.sh | test_828_quiet_resync_prints_no_retired_clean: re-sync with only aai-project-x target-only; zero CLEAN retired lines, no sync-conflicts report | sed:s/(remove_retired_skill_wrappers\(\) \{)/$1 echo "  CLEAN removed retired skill wrapper: probe";/ | green |
| TEST-829 | Spec-AC-07 | integration | tests/skills/test-aai-sync-seed.sh | test_829_ps1_retired_removal_parity: ps1 on the Spec-AC-01 and Spec-AC-02 fixtures; CLEAN line set and surviving tree equal bash's; ps1 advisory lists both aai-retired paths | sed:s/(function Test-RetiredSkillWrapper\([^)]*\) \{)/$1 return $false;/ (target .aai/scripts/aai-sync.ps1) | green |
| TEST-830 | Spec-AC-07 | integration | tests/skills/test-aai-sync-seed.sh | test_830_ps1_preservation_parity: ps1 on the Spec-AC-03 fixtures; every preserved entry byte-identical and the surviving tree equals bash's | sed:s/(function Test-RetiredSkillWrapper\([^)]*\) \{)/$1 return $true;/ (target .aai/scripts/aai-sync.ps1) | green |

RED plan: TEST-820, 821, 822, 826, 827 and 829 must be observed failing on the pre-change tree (the engines remove nothing) and that output stored under docs/ai/tdd/spec-sync-prune-retired-skill-wrappers/. TEST-823, 824, 825, 828 and 830 pass on the pre-change tree by construction (preservation is today's behavior); their pre-change GREEN is recorded, and their RED is the mutation-run.mjs record for the row's mutation. Every row's mutation record is required by mutation-gate.mjs at close. Default mutation target: .aai/scripts/aai-sync.sh.

## Verification

- Per row: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-sync-seed.sh <test_82x_...>`.
- Whole suite and the other sync consumers stay green: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-sync-seed.sh`, `... tests/skills/test-aai-layer-profiles.sh`, `... tests/skills/test-aai-layer-drift.sh`, `... tests/skills/test-aai-update.sh`, `... tests/skills/test-aai-doctor.sh`, plus `node .aai/scripts/sync-harness-skills.mjs --check` exit 0 (no skill tree changed). Full sweep with `AAI_TEST_TIMEOUT=3000` once before close.
- Mutation evidence: `node .aai/scripts/mutation-run.mjs --spec docs/specs/SPEC-DRAFT-spec-sync-prune-retired-skill-wrappers.md ...` per row, then `node .aai/scripts/mutation-gate.mjs --spec <spec>` exit 0.
- PASS criteria: all TEST rows green with pwsh present (exit 0, not 42), all Spec-AC terminal, mutation gate clean.

## Evidence contract

For each artifact record ref_id `sync-prune-retired-skill-wrappers`, the Spec-AC and TEST id, the command, its exit code, the evidence path under docs/ai/tdd/spec-sync-prune-retired-skill-wrappers/ or docs/ai/reports/, and the commit SHA.

### Evidence by strategy

Strategy tdd: a stored RED artifact per AC-gating test (pre-change failure for the removal and parity rows, mutation record for the preservation rows) plus the verification matrix above.
