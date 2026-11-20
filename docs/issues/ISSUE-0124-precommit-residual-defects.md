---
id: precommit-residual-defects
type: issue
capability: docs-close-gate
number: 124
status: done
links:
  pr: []
  commits: []
---

# Four residual defects in the commit-time guards

## Summary
Four P3 follow-ups left by PRs #569 to #571 (ISSUE-0122 / SPEC-0300,
DEBT-0016 / SPEC-0301, ISSUE-0123 / SPEC-0302), taken together because they
touch the same two guards:

1. `fu-staged-gate-deleted-spec-policy`: `docs-audit.mjs --gate-file
   --staged` reads a linked spec that the commit deletes (`git rm`) from HEAD,
   so an intake done-flip passes on the copy of a spec the commit removes.
2. `fu-hook-gate-quoted-doc-skip`: the index hook template
   `.aai/templates/git-hooks/pre-commit-index.sh` builds its staged doc lists
   from `git diff --cached --name-only` without `-z`. Git C-quotes a name
   with non-ASCII bytes (`"docs/issues/ISSUE-caf\303\251.md"`), so such a doc
   misses the `^docs/` filters and skips the close gate and the body lint.
   When it is the only staged docs file, the hook also exits before it
   regenerates the index.
3. `fu-precommit-index-race-block`: `pre-commit-checks.sh` reads the staged
   list (`--raw -z`) and then a second list (`--name-only -z`) for a count
   cross-check. An index change by another process between the two reads
   blocks the commit with `staged list count mismatch`, although nothing is
   wrong with what is staged.
4. `fu-pcc-other-builtin-redir`: CHECKs 1, 5, 6 and 9 of
   `pre-commit-checks.sh` still use here-strings and a here-document, and
   CHECKs 7, 8 and 9 run `command -v <tool> >/dev/null 2>&1`, a builtin with
   a redirection. When the descriptor table is nearly full, bash 3.2 cannot
   save a descriptor for a builtin's redirection: it prints `cannot duplicate
   fd`, applies the redirection anyway and never restores it, so the rest of
   the run, including the blocking error and the summary, goes to
   `/dev/null`.

## Type
bug

## Impact
- Every project that vendors the layer: the installed index hook (close gate
  and body lint, enforce mode) and `pre-commit-checks.sh` (CHECK 2 secrets,
  CHECK 9 gitignored paths).
- (1) and (2) let a governed doc pass a gate that `close_gate: enforce` or
  `body_lint: enforce` asks to block.
- (3) refuses a correct commit (safe direction, but a false block).
- (4) hides the reason for a block and the summary line; a commit made under
  these conditions cannot be told apart from one that passed.
- Severity: P3 each. `pre-commit-checks.sh` is an L3 protected surface.

## Current Behavior
- (1) An intake flips to `status: done`; the commit also runs `git rm` on its
  reconciled linked spec. `--gate-file --staged` exits 0 through the HEAD
  copy of the deleted spec.
- (2) With `close_gate: enforce`, a commit that flips
  `docs/issues/ISSUE-DRAFT-café.md` to done with a non-terminal linked spec
  succeeds; the hook never gates it.
- (3) A git wrapper that stages one more file right after the `--raw` read
  makes the run exit 1 with `staged list count mismatch`.
- (4) At the default limit of 256 descriptors with descriptors 10 to 254
  inherited open, a run with an added gitignored path exits 1 but prints
  neither the `Gitignored path staged for ADD` line nor the `BLOCKED` summary;
  stderr shows two `redirection error: cannot duplicate fd` lines.

## Expected Behavior
- (1) A doc the commit deletes is not part of the commit: the staged gate
  does not read it, and an intake whose linked spec the commit deletes fails
  with the `no linked spec` reason.
- (2) The hook reads its staged name lists NUL-separated, so every staged doc
  is gated and linted under its real name, whatever bytes it holds.
- (3) One concurrent index change between the two reads is absorbed by one
  re-read of both lists; a list that is still inconsistent blocks as today.
- (4) The checks use no here-string, no here-document and no redirection on a
  builtin, so the blocking line and the summary are printed under the same
  descriptor pressure.

## Steps to Reproduce (if applicable)
1) (1) In a fixture, commit a reconciled spec linked from a draft intake; flip
   the intake to done, `git rm` the spec, stage both; run
   `node .aai/scripts/docs-audit.mjs --gate-file <staged intake copy> --staged`:
   exit 0.
2) (2) Install the hook with `close_gate: enforce`; commit a draft intake named
   `ISSUE-DRAFT-café.md` and a non-terminal linked spec; flip the intake to
   done and commit: the commit succeeds.
3) (3) Put a `git` wrapper first on PATH that runs `git add late.txt` after
   answering the first `diff --cached --raw`; run the checks: exit 1,
   `staged list count mismatch`.
4) (4) `git add -f` an ignored path; run the checks under `ulimit -n 256` with
   descriptors 10 to 254 open and a `node` shim that closes them: exit 1, no
   reason line, no summary.

## Verification
- Failing-first cases in `tests/skills/test-aai-pre-commit-checks.sh` and
  `tests/skills/test-aai-docs-audit.sh`, each proven RED against the
  unchanged code or recorded as a mutation.
- Both suites pass through `.aai/scripts/aai-run-tests.sh`.

## Constraints / Risks
- `.aai/scripts/pre-commit-checks.sh` is an L3 protected surface: ceremony
  level 3, the owner merges.
- Fail-closed semantics are kept: an incomplete read blocks, never passes.
- Bash 3.2 compatible; GNU and BSD userland.
- Secrets preflight: no secret referenced.

## Notes
- Assumption (autopilot): the policy for (1) is that a staged deletion removes
  the doc from the commit's doc set; the gate's configuration keeps its HEAD
  fallback, so deleting `docs/ai/docs-audit.yaml` in a commit cannot
  downgrade the gate.
- Assumption (autopilot): the retry in (3) is one re-read; a second
  inconsistent pair goes on to the existing count checks, which block.
- Assumption (autopilot): (4) is fixed for the whole class in the script, not
  only the four CHECKs the follow-up names (CHECKs 7 and 8 have the same
  `command -v` redirection).
