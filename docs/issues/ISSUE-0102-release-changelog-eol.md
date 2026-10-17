---
id: release-changelog-eol
type: issue
number: 102
status: done
user_visible: false
capability: release-command-finish
links:
  pr: []
  commits: []
---

# Release finish drops the CHANGELOG trailing newline when it rolls the release

## Summary
- `.aai/scripts/release-finish.mjs` reads the base CHANGELOG with `git('show', `${baseHead}:CHANGELOG.md`)` (main, about line 398). `git()` (about line 50) returns `stdout.trim()`, so the source handed to `rollup()` has no trailing newline (and no leading whitespace or BOM). `rollup()` then sees `newline=false` and the rolled content written into the release worktree (about line 425, `fs.writeFileSync(..., record.content)`) ends without a final newline.
- `rollup()` also normalizes every CRLF to LF across the whole file, so it rewrites line endings of regions it does not otherwise touch.
- The resume path that adopts a prepared branch (about line 411) compares `trim(...)` of the branch CHANGELOG with `trim(record.content)`, so a prepared branch whose bytes differ only in whitespace, EOF or line endings is accepted as the authorized payload.

## Type
- bug

## Impact
- Every `/aai-release --confirm` run: the release PR's CHANGELOG fails the released-region guard in CI, so no release can be merged. Live evidence: release PR #473 (v2026.10.17.2, branch chore/release-v2026.10.17.2, head cb0f6732), suite aai-release TEST-025: "v2026.10.17 released region matches but the file EOF state differs (live=no-newline tag=newline)".
- Breaks the promise in .aai/SKILL_RELEASE.prompt.md and the old shell transform: the rollup is byte-preserving outside the rolled headings.
- Severity/priority: P1 (blocks every release).

## Current Behavior
- Base CHANGELOG ending in `\n` is rolled to content ending without `\n`.
- A CRLF CHANGELOG is rolled to an all-LF file.
- Resume accepts a prepared release commit whose CHANGELOG differs from the journal content only in whitespace or EOF.

## Expected Behavior
- The rolled CHANGELOG bytes equal the rollup transform applied to the exact base blob bytes: a trailing newline is kept, a missing trailing newline stays missing, leading bytes are kept, and line endings of every untouched line are kept (CRLF stays CRLF).
- Prepared-branch identity on resume compares exact bytes of the committed CHANGELOG with the journal content.
- Notes extraction (`record.notes`) and audit reads may stay normalized; only written file bytes must be exact.

## Steps to Reproduce (if applicable)
1) In the release fixture (tests/skills/test-aai-release.sh `test_700_one_command_finish`), whose CHANGELOG ends with a newline, run the finish engine with `--version v1 --confirm`.
2) Read `CHANGELOG.md` at the prepared release commit (`chore/release-v1`).
3) Result: the last byte is not `\n`. Expected: it is.

## Verification
- New RED-first tests in tests/skills/test-aai-release.sh assert exact rolled bytes for three base shapes (trailing newline, no trailing newline, CRLF) against a hand-written expected byte string.
- A resume test with a prepared commit whose CHANGELOG differs from the journal only at EOF refuses `identity`; the exact-bytes commit is still adopted.
- Whole aai-release suite stays green; CI TEST-025 passes on the next release PR.

## Constraints / Risks
- Assumption: only the engine changes; the bash and PowerShell frontends just forward to it.
- Assumption: a journal written by the defective engine (content without the newline) must not be silently resumed into a release while no PR exists; Planning decides how resume detects it.
- Out of scope: the in-flight broken release PR #473 and its journal. Its recovery is an operator action (close PR #473, delete the release branch and its journal, then cut a fresh release with the fixed engine).
- Out of scope: follow-up fu-release-required-contexts-unreported (required contexts that have not reported yet); it is recorded in docs/ai/decisions.jsonl and committed with this intake unchanged.
- release-finish.mjs is copied into the learned-routing suite fixtures; that suite must stay green.
- Secrets preflight: no secret referenced.

## Notes
- Metrics: human_time_minutes null (autopilot default). No clarifying questions asked; assumptions above. Implementation-mode choice skipped (autopilot); Planning decides.
- Other `git()`/`trim` uses checked: audit reads of CHANGELOG, notes comparison against the published release body, and ref/sha reads are normalization-safe; the only trimmed value that becomes written file bytes is the `git show` read of the base CHANGELOG.
