---
id: spec-precommit-residual-defects
type: spec
number: 304
status: done
frozen_sha256: 4452cd62173b0a2e2268177736df5aeab7003839631aaed5b61be763e0b3e7e4
mutation_gate: v1
ceremony_level: 3
links:
  requirement: precommit-residual-defects
  rfc: null
  pr: []
  commits: []
---

# Commit-time guards: a deleted spec is not read, the hook reads NUL-separated lists, one re-read absorbs an index race, and no check uses a builtin redirection

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/ISSUE-0124-precommit-residual-defects.md
  (follow-ups `fu-staged-gate-deleted-spec-policy`,
  `fu-hook-gate-quoted-doc-skip`, `fu-precommit-index-race-block`,
  `fu-pcc-other-builtin-redir`; P3 each).
- Prior scopes this one builds on (closed, not edited):
  docs/specs/SPEC-0300-spec-hook-gate-staged-content.md (D1 staged doc set,
  D3 hook `--staged`, residual risks), docs/specs/SPEC-0301-spec-precommit-blob-read-cost.md
  (D13 descriptor safety and count cross-checks),
  docs/specs/SPEC-0302-spec-precommit-sentinel-trap.md (D6, the two items
  it left open).
- Technology contract: docs/TECHNOLOGY.md (bash 3.2 suites through
  `.aai/scripts/aai-run-tests.sh`; Node stdlib only).

## Implementation strategy

- Strategy: tdd
- Rationale: guards on an L3 protected surface and on the docs close gate.
  Each defect is seen failing on the unchanged code first (TEST-3915 to
  TEST-3919); the static pin and the moved pins guard behaviour by text, so
  their failing observation is the mutation record. Not chosen at intake
  (autopilot); Planning chose it.

## Isolation and review

- Worktree recommendation: required
- Worktree rationale: L3 protected surface (`.aai/scripts/pre-commit-checks.sh`
  is in `protected_paths_l3`); the main checkout carries other sessions'
  uncommitted files.
- User decision: worktree (owner directive in the dispatch brief)
- Base ref: origin/main at 152cad00
- Worktree branch/path: fix/precommit-residual-defects at
  /Users/ales/Projects/aai-worktrees/precommit-residual-defects
- Review required: true
- Review scope (explicit paths): .aai/scripts/pre-commit-checks.sh;
  .aai/scripts/lib/docs-audit-core.mjs;
  .aai/templates/git-hooks/pre-commit-index.sh;
  tests/skills/test-aai-pre-commit-checks.sh;
  tests/skills/test-aai-docs-audit.sh; tests/skills/test-aai-git-ref-guard.sh;
  CHANGELOG.md;
  docs/product/docs-close-gate.md;
  docs/issues/ISSUE-0124-precommit-residual-defects.md;
  docs/specs/SPEC-0304-spec-precommit-residual-defects.md.

## Decisions

- D1 (a staged deletion is not read; `fu-staged-gate-deleted-spec-policy`).
  Policy: a doc the commit deletes is not part of the commit. In
  `readStagedDocSet` (`.aai/scripts/lib/docs-audit-core.mjs`) the paths
  named by one `git diff --cached --relative --name-only -z --no-renames
  --diff-filter=D -- docs` are dropped from the candidate set before any
  blob is read. An intake whose linked spec the commit deletes (`git rm`, or
  `git rm --cached`) therefore fails `--gate-file --staged` with the
  existing `no linked spec` reason instead of passing on HEAD's copy. The
  HEAD fallback stays for a path absent from the index that the commit does
  not delete; the index lists every other tracked path (unmerged ones
  included), so in practice HEAD no longer supplies a doc. A failing `git
  diff` throws, and `gateFile` already turns a throw in staged mode into
  `staged mode could not read the index` (exit 1). This replaces SPEC-0300
  D1's "absent from the index falls back to HEAD" for deletions; TEST-3861's
  first case, which asserted that fallback through `git rm --cached`, is
  re-pinned to the new verdict. The gate's configuration keeps its HEAD
  fallback (`loadStagedConfig`): deleting `docs/ai/docs-audit.yaml` in a
  commit keeps HEAD's settings, so a deletion cannot downgrade the gate.
- D2 (NUL-separated lists in the hook; `fu-hook-gate-quoted-doc-skip`). The
  index hook template reads its three staged name lists with `-z` into a
  private scratch directory (`mktemp -d`, removed by an EXIT trap) and
  iterates them with `while IFS= read -r -d '' f`: the early "any staged
  path under `docs/`" check, the close-gate list (`--diff-filter=ACM`,
  kept to `docs/{issues,rfc,specs,requirements}/**.md` by a `case`
  pattern) and the body-lint list (`--diff-filter=ACM`, `docs/**.md` minus
  the same excluded directories and `docs/INDEX*`). Each list is still read
  at the point the old one was. A name git would C-quote now reaches the
  gate and the lint under its real path, and `git show ":$f"` reads it.
- D3 (one re-read absorbs an index race; `fu-precommit-index-race-block`).
  `pre-commit-checks.sh` reads the `--raw -z` list and the `--name-only -z`
  list, then counts the NUL terminators of both with `tr` and `wc` before
  the parse. When the list's count is even and is not twice the names'
  count, both lists are read once more. The loop stops after the second
  read whatever it finds, and when the list's count is odd (a malformed
  list, not a race). The parse and the existing post-parse checks then run
  on the last pair: list NULs twice the parsed records (`malformed staged
  list`), names equal to the parsed records (`staged list count mismatch`).
  A list that is still inconsistent after the re-read therefore blocks with
  the same message as before; only a pair that agrees on the second read
  goes on, and the checks then judge that second read. Every count is still
  taken by tools that are not the parse loop. Post-freeze amendment (TDD,
  TEST-3885 at `ulimit -n 6`): with the counts taken before the list is
  opened on descriptor 4, the first command that needs a pipe after that
  open became the batch pipeline, and a pipeline whose pipe cannot be made
  ends bash itself (exit 129, no report). A command substitution that cannot
  make its pipe only comes back empty, so one (`$(echo ok)`) is tried right
  before the pipeline and an empty result blocks with `git cat-file --batch
  failed`.
- D4 (no builtin redirection in the checks; `fu-pcc-other-builtin-redir`).
  CHECKs 1, 5 and 6 match the STATE text with `[[ text =~ re ]]` against
  regexes held in variables (`phase:[^<newline>]*implementation`,
  `phase:[^<newline>]*validation`, `status: *pass`, `required: *true`,
  `status: *(pass|waived)`), the same per-line matches the `grep -q`
  here-strings made. CHECK 3 prints the first three debug matches through
  the same line helper instead of `head -3` on a here-string (post-freeze
  amendment: Spec-AC-06 forbids every `<<` in the script, and this one was
  not listed here). CHECKs 7 and 9 walk their line lists with a helper,
  `pcc_next_line`, that splits by parameter expansion instead of a `while
  read` loop fed by a here-string or a here-document. CHECKs 7, 8 and 9 test
  for a tool with `( command -v <tool> ) >/dev/null 2>&1`: the subshell is a
  forked child, so its redirection needs no saved descriptor in the script's
  own process. After this the script holds no `<<` and no `command -v`
  outside that subshell form; the only builtin redirections left are the
  two permanent `exec` opens of SPEC-0301 D13, which save nothing.
- D5 (out of scope, recorded as follow-ups). CHECK 9 still reports a
  `tracked-ignored.mjs` that cannot run (exit above 1, for instance `spawnSync
  git EMFILE` at a low descriptor limit) as a warning, so a commit that adds
  an ignored path passes then in non-strict mode
  (`fu-pcc-check9-cannot-run-passes`). CHECK 7 keeps its own newline list and
  working-tree read (SPEC-0300 residual risk). The hook still skips a staged
  doc whose blob `git show` cannot read (`fu-hook-gate-show-failure-skips`).
- D6 (consumer record). The gate verdict for a deleted linked spec changes
  and the hook template changes: one CHANGELOG `## [unreleased] — fix: ...`
  heading, and docs/product/docs-close-gate.md says a linked spec the commit
  deletes is not read.

## Acceptance Criteria Mapping

- Spec-AC-01 maps to intake (1): a deleted linked spec is not read (D1).
- Spec-AC-02 maps to intake (2), the close gate and the early docs check
  (D2).
- Spec-AC-03 maps to intake (2), the body lint (D2).
- Spec-AC-04 maps to intake (3) (D3).
- Spec-AC-05 maps to intake (4), behaviour under a nearly full descriptor
  table (D4).
- Spec-AC-06 maps to intake (4), the class pinned by text (D4).
- Spec-AC-07 maps to preservation and the moved pins.
- Spec-AC-08 maps to the consumer record (D6).

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN a draft intake is committed with a reconciled linked spec and the commit flips the intake to done and removes the spec with git rm, --gate-file --staged on the staged intake SHALL exit 1 and print the no linked spec reason; WHEN the spec is removed with git rm --cached and left reconciled in the working tree, the same SHALL hold; WHEN the spec stays in the index unchanged, the gate SHALL exit 0 through it | done | TEST-3915 red docs/ai/tdd/precommit-residual-defects/red-test_3915_staged_gate_skips_deleted_spec.log; TEST-3915 green docs/ai/tdd/precommit-residual-defects/green-test_3915_staged_gate_skips_deleted_spec.log and docs/ai/tdd/precommit-residual-defects/green-full-suite-docs-audit.log, mutation docs/ai/tdd/spec-precommit-residual-defects/mutation-TEST-3915.txt; validation docs/ai/validation/VALIDATION-precommit-residual-defects-r4.md | — | D1 |
| Spec-AC-02 | WHEN close_gate is enforce and the hook is installed, a commit that flips docs/issues/ISSUE-DRAFT-café.md to done while its linked spec has a non-terminal row SHALL exit non-zero and name the intake id, once with the intake as the only staged path and once with an ASCII docs file staged beside it; WHEN the spec is reconciled in the same commit, the commit SHALL succeed and HEAD SHALL move | done | TEST-3916 red docs/ai/tdd/precommit-residual-defects/red-test_3916_hook_gates_quoted_doc_name.log; TEST-3916 green docs/ai/tdd/precommit-residual-defects/green-test_3916_hook_gates_quoted_doc_name.log and docs/ai/tdd/precommit-residual-defects/green-full-suite-docs-audit.log, mutation docs/ai/tdd/spec-precommit-residual-defects/mutation-TEST-3916.txt; validation docs/ai/validation/VALIDATION-precommit-residual-defects-r4.md | — | D2 |
| Spec-AC-03 | WHEN body_lint is enforce and the hook is installed, a commit that stages docs/specs/notes-ü.md holding a stray closing content tag beside an ASCII docs file SHALL exit non-zero and name the doc in the body-lint line; WHEN the tag is removed, the commit SHALL succeed | done | TEST-3917 red docs/ai/tdd/precommit-residual-defects/red-test_3917_hook_lints_quoted_doc_name.log; TEST-3917 green docs/ai/tdd/precommit-residual-defects/green-test_3917_hook_lints_quoted_doc_name.log and docs/ai/tdd/precommit-residual-defects/green-full-suite-docs-audit.log, mutation docs/ai/tdd/spec-precommit-residual-defects/mutation-TEST-3917.txt; validation docs/ai/validation/VALIDATION-precommit-residual-defects-r4.md | — | D2 |
| Spec-AC-04 | WHEN a git wrapper stages late.txt holding the api_key line right after it answers the first diff --cached --raw read, the script SHALL read both lists twice, SHALL exit 1 reporting the secret in late.txt once, and SHALL print no fail-closed line; WHEN late.txt is clean, the script SHALL exit 0 with a passing summary; WHEN the wrapper drops the last list record on every read, the script SHALL still exit 1 with the single fail-closed line naming staged list count mismatch | done | TEST-3918 red docs/ai/tdd/precommit-residual-defects/red-test_3918_index_race_reread.log; TEST-3918 green docs/ai/tdd/precommit-residual-defects/green-test_3918_index_race_reread.log and docs/ai/tdd/precommit-residual-defects/green-full-suite-pcc.log, mutation docs/ai/tdd/spec-precommit-residual-defects/mutation-TEST-3918.txt; validation docs/ai/validation/VALIDATION-precommit-residual-defects-r4.md | — | D3 |
| Spec-AC-05 | WHEN the script runs at the 256 descriptor limit with descriptors 10 to 254 inherited open and a node shim that closes them, a staged ignored path added with git add -f SHALL give exit 1, the Gitignored path staged for ADD line once and the BLOCKED summary; WHEN STATE requires a code review that has not run and the script runs with --strict under the same table, it SHALL exit 1 printing the review warning and the BLOCKED (strict mode) summary; neither run SHALL print cannot duplicate fd on stderr | done | TEST-3919 red docs/ai/tdd/precommit-residual-defects/red-test_3919_full_descriptor_table_reports.log; TEST-3919 green docs/ai/tdd/precommit-residual-defects/green-test_3919_full_descriptor_table_reports.log and docs/ai/tdd/precommit-residual-defects/green-full-suite-pcc.log, mutation docs/ai/tdd/spec-precommit-residual-defects/mutation-TEST-3919.txt; validation docs/ai/validation/VALIDATION-precommit-residual-defects-r4.md | — | D4 |
| Spec-AC-06 | pre-commit-checks.sh SHALL hold no here-string or here-document (no << sequence) and every command -v in it SHALL be in the subshell form ( command -v name ) | done | TEST-3920 red docs/ai/tdd/precommit-residual-defects/red-test_3920_no_builtin_redirection_text.log; TEST-3920 green docs/ai/tdd/precommit-residual-defects/green-test_3920_no_builtin_redirection_text.log and docs/ai/tdd/precommit-residual-defects/green-full-suite-pcc.log, mutation docs/ai/tdd/spec-precommit-residual-defects/mutation-TEST-3920.txt; validation docs/ai/validation/VALIDATION-precommit-residual-defects-r4.md | — | D4 |
| Spec-AC-07 | bash tests/skills/test-aai-pre-commit-checks.sh SHALL exit 0 with TEST-3454 giving the 3e6b52d5 baseline's output on its seven fixtures and its numstat pin, and the TEST-3461 line-count pin, naming the new measured values; TEST-3451, TEST-3873, TEST-3880, TEST-3881 and TEST-3885 SHALL stay green | done | TEST-3921 green docs/ai/tdd/precommit-residual-defects/green-full-suite-pcc.log, mutation docs/ai/tdd/spec-precommit-residual-defects/mutation-TEST-3921.txt; validation docs/ai/validation/VALIDATION-precommit-residual-defects-r4.md | — | preservation |
| Spec-AC-08 | CHANGELOG.md SHALL hold exactly one unreleased heading for this fix and docs/product/docs-close-gate.md SHALL say that a linked spec the commit deletes is not read | done | TEST-3922 red docs/ai/tdd/precommit-residual-defects/red-test_3922_changelog_and_product_doc.log; TEST-3922 green docs/ai/tdd/precommit-residual-defects/green-test_3922_changelog_and_product_doc.log and docs/ai/tdd/precommit-residual-defects/green-full-suite-pcc.log, mutation docs/ai/tdd/spec-precommit-residual-defects/mutation-TEST-3922.txt; validation docs/ai/validation/VALIDATION-precommit-residual-defects-r4.md | — | D6 |

## Implementation plan

- `.aai/scripts/lib/docs-audit-core.mjs` `readStagedDocSet`: the deleted set
  and the one-line skip in the candidate loop; the comment above the
  function states the policy (D1).
- `.aai/templates/git-hooks/pre-commit-index.sh`: scratch directory and
  trap after the node check; the three `-z` reads and `read -d ''` loops
  with `case` filters (D2).
- `.aai/scripts/pre-commit-checks.sh`: the read-and-count loop in the
  IN_REPO block; the post-parse checks compare the counts taken there (D3);
  regex variables and `[[ =~ ]]` in CHECKs 1, 5, 6; `pcc_next_line` and the
  parameter-expansion loops in CHECKs 7 and 9; the subshell `command -v` in
  CHECKs 7, 8, 9; the header comment of the staged-content block names the
  re-read (D4).
- `tests/skills/test-aai-docs-audit.sh`: TEST-3915 to TEST-3917; TEST-3861's
  first case re-pinned (D1) with a history comment.
- `tests/skills/test-aai-pre-commit-checks.sh`: TEST-3918 to TEST-3922; a
  `late` wrapper mode; re-pin TEST-3454 numstat and TEST-3461 counts with
  their history comments; the suite header's TEST range.
- `CHANGELOG.md`, `docs/product/docs-close-gate.md` (D6).
- `tests/skills/test-aai-git-ref-guard.sh`: TEST-308's sha256 pin of the
  installed hook body re-pinned to the D2 template (post-freeze amendment
  after VALIDATION r1 B1).
- Seams crossed: the installed hook runs the template under `git commit`
  (TEST-3916, TEST-3917); the hook passes the staged copy to `docs-audit.mjs
  --gate-file --staged` (TEST-3916); another process changes the index
  between two reads (TEST-3918, by a wrapper that runs the real `git add`);
  the descriptor table the committing process hands down (TEST-3919).
- Bash 3.2 under `set -euo pipefail`; GNU and BSD userland; Node stdlib.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3915 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh | git fixture: draft intake and reconciled spec committed; intake flipped to done and staged; spec removed with git rm (then, in further fixtures, git rm --cached, and git rm at a project root below the repository top level): --gate-file --staged exits 1 with no linked spec; control with the spec untouched exits 0 via the spec; RED on the unchanged code (exit 0 through HEAD) | target `.aai/scripts/lib/docs-audit-core.mjs`; `sed:s/if \(deleted\.has\(rel\)\) continue;//` reads the deleted spec from HEAD again and the case must fail | green |
| TEST-3916 | Spec-AC-02 | integration | tests/skills/test-aai-docs-audit.sh | installed hook, close_gate enforce, core.quotePath true: flip of ISSUE-DRAFT-café.md with a non-terminal spec aborts the commit naming the intake id, alone and beside a staged ASCII doc; with the spec reconciled the commit succeeds; RED on the unchanged template (both commits succeed) | target `.aai/templates/git-hooks/pre-commit-index.sh`; `sed:s/--name-only -z --diff-filter=ACM > "\$_aai_lists\/gated"/--name-only --diff-filter=ACM > "$_aai_lists\/gated"/` reads the close-gate list newline-separated again and the case must fail | green |
| TEST-3917 | Spec-AC-03 | integration | tests/skills/test-aai-docs-audit.sh | installed hook, body_lint enforce, core.quotePath true: docs/specs/notes-ü.md with a stray closing content tag beside an ASCII doc aborts the commit naming the doc; without the tag the commit succeeds; RED on the unchanged template | target `.aai/templates/git-hooks/pre-commit-index.sh`; `sed:s/--name-only -z --diff-filter=ACM > "\$_aai_lists\/linted"/--name-only --diff-filter=ACM > "$_aai_lists\/linted"/` reads the body-lint list newline-separated again and the case must fail | green |
| TEST-3918 | Spec-AC-04 | integration | tests/skills/test-aai-pre-commit-checks.sh | a late wrapper mode stages late.txt after the first --raw answer: with a secret in late.txt exit 1, the secret named once, no fail-closed line, the wrapper log shows two --raw reads; with a clean late.txt exit 0 and a summary; listdrop still fails closed with staged list count mismatch; RED on the unchanged script (fail-closed staged list count mismatch) | target `.aai/scripts/pre-commit-checks.sh`; `sed:s/\[ "\$pcc_try" -ge 2 \]/[ "$pcc_try" -ge 1 ]/` stops after the first read and the case must fail | green |
| TEST-3919 | Spec-AC-05 | integration | tests/skills/test-aai-pre-commit-checks.sh | RUN_HOLD_FDS with a node shim that closes descriptors 10 to 254 before it runs the real node: git add -f ignored.log gives exit 1, the ADD line once and the BLOCKED summary; a review_not_run STATE with --strict gives exit 1, the review warning and BLOCKED (strict mode); no cannot duplicate fd on stderr; RED on the unchanged script (the lines after CHECK 8 go to /dev/null) | target `.aai/scripts/pre-commit-checks.sh`; `sed:s/"\$TRACKED_IGNORED_SCRIPT" \] && \( command -v node \)/"$TRACKED_IGNORED_SCRIPT" ] && command -v node/` puts the builtin redirection back in CHECK 9 and the case must fail | green |
| TEST-3920 | Spec-AC-06 | unit | tests/skills/test-aai-pre-commit-checks.sh | the script holds no << sequence, no redirection on a builtin, a shell function or a compound command other than the two exec opens (a lexical scan, not a parser, that drops quoted text, command substitutions and comments and judges each simple command by its first word after a case pattern; fourteen planted shapes, including hash and type with a redirection, a one-line case arm and a builtin after an unquoted command substitution, must each be seen; a shape outside the planted set can escape it, and TEST-3919 guards the behaviour), and every command -v occurrence is preceded by an opening parenthesis and a space; green on the fixed script, the failing observation is the mutation record | target `.aai/scripts/pre-commit-checks.sh`; `sed:s/\[\[ "\$CODE_REVIEW_BLOCK" =~ \$PCC_RE_REQUIRED \]\]/grep -q "required: *true" <<< "$CODE_REVIEW_BLOCK"/` puts a here-string back in CHECK 6 and the case must fail | green |
| TEST-3921 | Spec-AC-07 | integration | tests/skills/test-aai-pre-commit-checks.sh | runs TEST-3451, TEST-3454 (parity and re-pinned numstat), TEST-3461 (re-pinned line counts), TEST-3873, TEST-3880, TEST-3881 and TEST-3885 by selector; each exits 0 | target `tests/skills/test-aai-pre-commit-checks.sh`; `sed:s/\[\[ "\$numstat" == "/[[ "$numstat" == "9/` breaks the moved numstat pin and the case must fail | green |
| TEST-3922 | Spec-AC-08 | unit | tests/skills/test-aai-pre-commit-checks.sh | grep -c of the CHANGELOG heading equals 1; the product doc says a linked spec the commit deletes is not read | target `docs/product/docs-close-gate.md`; `sed:s/the commit deletes is not read/the commit deletes is read from HEAD/` reverts the product statement and the case must fail | green |

RED observations: TEST-3915 to TEST-3919 are written first and run against
the unchanged code; their failing runs are stored as `red-<selector>.log`
under `docs/ai/tdd/precommit-residual-defects/`. TEST-3920 to TEST-3922
guard text and moved pins; their failing observation is the mutation record
under `docs/ai/tdd/spec-precommit-residual-defects/`.

## Verification

- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pre-commit-checks.sh`
- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-docs-audit.sh`
- `/bin/bash -n` on the script and the template; the new cases run under
  `/bin/bash` 3.2.57 on macOS; GNU userland and bash 5 through CI (Ubuntu).
- `node .aai/scripts/mutation-run.mjs --replay --spec <this spec>`
- One full sweep before close (`AAI_TEST_TIMEOUT=3600`).
- PASS criteria: all TEST-xxx green and every Spec-AC terminal.

## Evidence contract

Per artifact: ref_id `precommit-residual-defects`, Spec-AC and TEST-xxx,
command, exit code, evidence path under
`docs/ai/tdd/precommit-residual-defects/` (RED and GREEN logs) and
`docs/ai/tdd/spec-precommit-residual-defects/` (mutation records), commit SHA
once committed.

Registry items closed by this scope: fu-staged-gate-deleted-spec-policy, fu-hook-gate-quoted-doc-skip, fu-precommit-index-race-block, fu-pcc-other-builtin-redir

## Residual risks

- The re-read absorbs one index change between the two reads; a second
  change during the re-read still blocks (safe direction). The checks judge
  a snapshot of the index taken during the hook, as before.
- TEST-3919 needs a `node` shim to reach CHECK 9's parse under the full
  table: without it Node itself cannot open a descriptor and CHECK 9 reports
  that it could not run (D5 follow-up).
- The regex matches in CHECKs 1, 5 and 6 run in the shell's locale; a STATE
  file with bytes invalid in that locale may match differently from `grep`.
  TEST-3454's seven fixtures and TEST-3451's 300 KB STATE pin the ordinary
  case.
- Windows (Git Bash) runs of the suites are not part of CI.
- TEST-3915's subdirectory-root case has no mutation row of its own (the
  row's mutation removes the deletion skip); a mutant that drops
  `--relative` was observed failing it during code review r2, but the
  replay does not re-prove it.
