---
id: mutation-clone-fidelity-windows-eol
type: issue
number: null
status: draft
links:
  pr: []
  commits: []
---

# Issue — Mutation runner clone fidelity fails on Windows dirty trees with mixed EOL

## Summary
- `mutation-run.mjs` builds an isolated clone with `git clone`, `git diff HEAD | git apply`, copy of untracked-not-ignored files, then a byte-level tree-hash compare against the source working tree.
- On Windows with `core.autocrlf=true` and mixed LF/CRLF, checkout plus apply change line endings even when Python content is equivalent. Clone-fidelity then refuses or yields `INCONCLUSIVE`, so the mutation never tests the changed behavior.
- Unrelated dirty and untracked files are also reproduced and hashed, even when the mutation only needs a small production/test set.

## Type
- bug

## Impact
- Who/what is affected: TDD rides on Windows (and any `core.autocrlf=true` working tree) that must produce mutation evidence. Observed during `bezdinek-aggregation-block-failure`: targeted tests were green; mutation-run was not usable in the main working tree.
- Severity/priority: high — false block of a correct implementation; long infra debugging; risk of hand-normalizing shipping files.

## Current Behavior
- `buildIsolatedClone()` in `.aai/scripts/mutation-run.mjs`:
  1. `git clone --local --no-hardlinks` of the shipping repo, then checkout HEAD.
  2. Apply `git diff HEAD` from the source tree via `git apply`.
  3. Copy every untracked-not-ignored path (skipping `docs/ai/tdd/**`) with `copyFileSync`.
  4. Compare `computeTreeFileHashes` of source vs clone; mismatch -> `TreeMismatchError` (exit 3 / INCONCLUSIVE on replay).
- Observed on Windows (`core.autocrlf=true`, mixed LF/CRLF, extra dirty/untracked files): clone was not byte-identical; runner stopped at fidelity or INCONCLUSIVE.
- Workaround used: a separate byte-stable snapshot, LF-normalize relevant files, exclude unrelated untracked files, isolate checkout hooks, use the main venv Python, drop stale/INCONCLUSIVE evidence, re-run. After that, TEST-001..TEST-011 all RED as expected (11/11 replay). The tests and mutation definitions were not the defect.

## Expected Behavior
- A mutation run succeeds on Windows with `core.autocrlf=true` without the operator LF-normalizing the shipping tree.
- The source tree may mix LF and CRLF; the isolated copy matches the **working-tree bytes** of in-scope files, not a git-checkout-then-apply reconstruction.
- Unrelated untracked files do not participate in clone-fidelity.
- Mismatch diagnostics name the paths and classify `EOL-only difference` when that is the only delta.
- Mutation evidence is replayable with `--replay` without a hand-built snapshot.
- The isolated mutation never writes the shipping working tree.

## Steps to Reproduce (if applicable)
1. Windows working tree, `core.autocrlf=true`, mix of LF and CRLF in tracked files, plus unrelated untracked files.
2. Have a dirty in-scope production/test change whose unit tests are green.
3. Run `node .aai/scripts/mutation-run.mjs` for those TEST ids (or `--replay` against existing records).
4. Observe clone-fidelity refusal or `INCONCLUSIVE` before the mutated test runs.

## Verification
1. Mutation run passes on Windows with `core.autocrlf=true`.
2. Source tree may mix LF and CRLF; no manual EOL normalization of shipping files.
3. Unrelated untracked files do not affect the run.
4. No manual snapshot and no `.git/info/exclude` edit required.
5. Isolated mutation does not change the shipping working tree.
6. Mutation evidence replays with `--replay` without hand edits.
7. Windows runs go through the platform test wrapper (`.ps1`), not a raw `bash` that can hit WSL.

## Constraints / Risks
- Known risks or constraints: CHANGE-0187 / SPEC-0181 own the mutation gate and D4 clone-fidelity invariant (clone must reproduce the source tree). This issue is a Windows residual of that invariant, not a request to drop D4. Byte overlay of in-scope working-tree files is the report's proposed direction; Planning must keep the "never touch the shipping tree" contract. Explicit `--include <path>` scope is in the source report; treat it as an allowed design option, not a required API, until Planning freezes it. Pair with `prompts-invoke-wsl-bash-on-windows` for how Windows agents launch the runner; do not merge the rides.
- Secrets preflight results (if any secret referenced): none — no local secret is referenced.

## Notes
- Source: local Windows usage report 2026-09-24 (`internal/windows-usage-report.md` in the project store). Not previously filed upstream.
- Related done work that does **not** close this: CHANGE-0187 (`mutation-gate-for-tests`), SPEC-0181 D4 clone-fidelity, ISSUE-0045 (`isolation-shares-the-shipping-git`).
- Assumption: the 11/11 RED replay after the manual snapshot is evidence that the mutations themselves were correct; the defect is reproduction of a Windows dirty tree.
