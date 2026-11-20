# Code review — precommit-residual-defects (r1)

```yaml
review:
  scope: >-
    uncommitted worktree diff vs origin/main 152cad00 (branch fix/precommit-residual-defects), explicit paths:
    .aai/scripts/pre-commit-checks.sh .aai/scripts/lib/docs-audit-core.mjs
    .aai/templates/git-hooks/pre-commit-index.sh tests/skills/test-aai-pre-commit-checks.sh
    tests/skills/test-aai-docs-audit.sh tests/skills/test-aai-git-ref-guard.sh CHANGELOG.md
    docs/product/docs-close-gate.md docs/issues/ISSUE-0124-precommit-residual-defects.md (untracked)
    docs/specs/SPEC-0304-spec-precommit-residual-defects.md (untracked)
  spec: docs/specs/SPEC-0304-spec-precommit-residual-defects.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/lib/docs-audit-core.mjs:2033,2036; TEST-3915 (test-aai-docs-audit.sh:9815) and re-pinned TEST-3861 (:9677) green in this review" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/templates/git-hooks/pre-commit-index.sh:12-17,70-75,113; TEST-3916 (test-aai-docs-audit.sh:9863) green in this review" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/templates/git-hooks/pre-commit-index.sh:139-145,162; TEST-3917 (test-aai-docs-audit.sh:9901) green in this review" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/pre-commit-checks.sh:131-141 plus unchanged post-parse checks; TEST-3918 (test-aai-pre-commit-checks.sh:1102) green in this review" }
      - { ac: Spec-AC-05, call: compliant, citation: "pre-commit-checks.sh:383,415,464 (subshell command -v), :472-496 (pcc_next_line walk); TEST-3919 (:1137) green in this review" }
      - { ac: Spec-AC-06, call: compliant, citation: "no << in pre-commit-checks.sh, every command -v in subshell form; TEST-3920 (:1163) green in this review (see B1 for the test's name)" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-3921 (:1173) green in this review (runs TEST-3451/3454/3461/3873/3880/3881/3885)" }
      - { ac: Spec-AC-08, call: compliant, citation: "CHANGELOG.md:33; docs/product/docs-close-gate.md:87; TEST-3922 (:1183) green in this review" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/test-aai-pre-commit-checks.sh, line: 1163,
          issue: "test_3920_no_builtin_redirection_text names a universal negative (the script text holds no builtin redirection) but asserts only two textual forms: no '<<' and every 'command -v' in '( command -v x )'",
          failure_scenario: "a later edit adds 'hash node >/dev/null 2>&1' (or 'type', 'read x < f', 'echo .. >&2' on a builtin) to pre-commit-checks.sh; TEST-3920 stays green (repro docs/ai/reviews/review-precommit-residual-defects-20261120T011041Z-repro-B1.sh exits 1, output in the .out sibling)" }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/docs-audit-core.mjs, line: 2033,
          issue: "the '--relative' flag that makes the deleted list comparable with ls-files paths when the AAI root is a subdirectory of the repository is not pinned by any test",
          failure_scenario: "a refactor drops '--relative'; at a subdirectory root the deleted list holds top-level paths (sub/docs/..), no rel matches, and a git-rm'd linked spec passes the gate on HEAD's copy again (scratch probe: mutant exit 0 'GATE PASS', real code exit 1 'no linked spec'); TEST-3915 runs at the top level only, so it stays green" }
      - { rank: NON-BLOCKING, file: .aai/templates/git-hooks/pre-commit-index.sh, line: 70,
          issue: "pre-existing, not introduced by this diff: the close-gate and body-lint lists use --diff-filter=ACM with git's default rename detection, so a doc renamed in the commit (status R) is in neither list",
          failure_scenario: "git mv docs/issues/ISSUE-DRAFT-x.md docs/issues/ISSUE-0001-x.md plus the status: done flip in one commit: 'git diff --cached --name-only -z --diff-filter=ACM' prints nothing (git 2.54.0, R083), so the hook neither close-gates nor body-lints the doc even under enforce" }
  cannot_verify:
    - { claim: "the hook template and pre-commit-checks.sh behave the same under GNU userland and bash 5 (Linux CI)", closes_with: "the Ubuntu CI run of test-aai-pre-commit-checks.sh and test-aai-docs-audit.sh on the PR" }
    - { claim: "the hook runs correctly under Git for Windows (Git Bash: mktemp -d, read -d '', the EXIT trap)", closes_with: "a Windows Git Bash run of TEST-3916/TEST-3917; not in CI (spec residual risk)" }
    - { claim: "on Linux (glibc regex) a STATE.yaml holding a byte invalid in the locale matches CHECKs 1, 5 and 6 as grep did", closes_with: "a Linux run of the INFO-1 fixture below; on macOS the same input already ends the script at awk (exit 2) before and after the change" }
    - { claim: "the pipe probe ($(echo ok)) always fails whenever the following pipeline could not make its pipe", closes_with: "argument from equal descriptor needs plus TEST-3885 at ulimit -n 6; no test sweeps the limit between 6 and 256" }
  overall: fail
```

security_relevant: true

## Scope and spec

- Scope: the uncommitted diff of the worktree `/Users/ales/Projects/aai-worktrees/precommit-residual-defects` (branch `fix/precommit-residual-defects`, HEAD = base `origin/main` 152cad00) on the ten explicit paths named in STATE `code_review.scope`; the issue and spec are untracked new files and were read whole. `docs/ai/EVENTS.jsonl`, `docs/ai/decisions.jsonl` and `docs/ai/tests/test-runs.jsonl` also differ but are ledgers outside the review scope.
- Spec: `docs/specs/SPEC-0304-spec-precommit-residual-defects.md` (frozen, ceremony 3, 8 Spec-AC). Validation r2 PASS: `docs/ai/validation/VALIDATION-precommit-residual-defects-r2.md`.
- Dispatch prompt: it named areas to look at (fail-closed semantics, portability, the re-read loop, the deleted-path skip, hook filters, test bite). It did not pre-rate severity or exclude any area; I reviewed the full scope.
- Safety: `docker ps` failed against the nonexistent socket before any run; no container command was run. Mutations ran only on copies under private `mktemp` and scratch directories.

## AC table walk (Verdict 1: spec_compliance = pass)

| Spec-AC | Call | Citation |
|---|---|---|
| Spec-AC-01 | compliant | `docs-audit-core.mjs:2033` builds the deleted set (`diff --cached --relative --name-only -z --no-renames --diff-filter=D -- docs`), `:2036` skips it. TEST-3915 (rm, rm --cached, keep control) and re-pinned TEST-3861 were green when I ran them. Scratch probes: works at a subdirectory root (exit 1 `no linked spec`, keep control exit 0), on an unborn HEAD (`git diff --cached` rc 0), and with `color.ui=always` (no escape bytes). A rename's old path is listed as D under `--no-renames`, so the stale HEAD copy is dropped (stricter than, and consistent with, TEST-3869, which stays green). |
| Spec-AC-02 | compliant | hook `:12-17` (scratch dir, EXIT trap, `-z` early docs check), `:70-75` and `:113` (`-z` close-gate list and `case` filter). TEST-3916 (alone and with an ASCII companion; reconciled commit moves HEAD) was green when I ran it. |
| Spec-AC-03 | compliant | hook `:139-145`, `:162`. TEST-3917 was green when I ran it. |
| Spec-AC-04 | compliant | `pre-commit-checks.sh:131-141`: at most two reads, then the unchanged post-parse checks (`:179-180` in the new numbering) judge the last pair. TEST-3918 (late secret reported once, clean passes, listdrop still fails closed) was green when I ran it. |
| Spec-AC-05 | compliant | `:383,415,464` subshell `command -v`; `:472-496` parameter-expansion walk. TEST-3919 was green when I ran it. |
| Spec-AC-06 | compliant | `grep '<<'` finds nothing; every `command -v` is in `( command -v x )`. TEST-3920 was green when I ran it. The spec's wording is met; B1 is about the test's name. |
| Spec-AC-07 | compliant | TEST-3921 was green when I ran it (it runs 3451, 3454 numstat `242 39`, 3461 `526/390`, 3873, 3880, 3881, 3885). |
| Spec-AC-08 | compliant | `CHANGELOG.md:33` (one `## [unreleased] — fix: ...` heading); `docs/product/docs-close-gate.md:87`. TEST-3922 was green when I ran it. |

TEST-308 (`test-aai-git-ref-guard.sh`, hook sha256 re-pin) was also green when I ran it.

Deviations from the frozen spec:
- Post-freeze contract amendments to D3 (the pipe probe before the batch pipeline) and D4 (CHECK 3's `head -3` here-string replaced). Both are disclosed in the spec text, unsigned, and tracked by the open `fu-amend-spec-precommit-residual-defects` (validation NB1). They are disclosed and in the direction of the spec's own Spec-AC-06, so I do not count them as non-compliance. They still need the owner's sign-off.
- A measurement amendment adds `tests/skills/test-aai-git-ref-guard.sh` (TEST-308 re-pin) to the scope after VALIDATION r1 B1. It is disclosed.

## Findings (Verdict 2: code_quality = fail)

### B1 — BLOCKING — `tests/skills/test-aai-pre-commit-checks.sh:1163`

The test is named `test_3920_no_builtin_redirection_text`, a universal negative over the script text. It asserts only two forms: no `<<`, and every `command -v` inside `( command -v x )`. Any other builtin redirection, such as `hash`/`type`/`read`/`echo`/`printf`/`:` with `>`, `<` or `>&`, or a redirected `done`, `}` or function call, passes it. This is the exact defect class D4 removes: under a full descriptor table bash 3.2 sends the rest of the report to /dev/null. The review contract makes a name that claims a universal negative over a subset assertion BLOCKING.

- Failure scenario: a later edit adds `hash node >/dev/null 2>&1 || true` before CHECK 9 and TEST-3920 stays green.
- backed-by: repro `docs/ai/reviews/review-precommit-residual-defects-20261120T011041Z-repro-B1.sh`, which exits 1 (`GAP REPRODUCED`). Its output is in the `.out` sibling. It mutates a copy in a private mktemp tree, never the shipping file.
- Context: TEST-3919 does catch that same mutant through behaviour, because it reaches CHECK 9 (I re-ran it on the mutant copy: `FAIL: TEST-3919: the ADD line for ignored.log was not printed once`, with `cannot duplicate fd` on stderr). So the behaviour is guarded on the paths TEST-3919 reaches. What overclaims is the static pin's name.
- Remedy (implementer's choice), either:
  - (a) Prove the negative by extending the awk so it flags any non-comment line that applies a redirection outside an external command, a subshell or a command substitution, allowing only the two `exec` opens and the trap string. A mutation record for the new arm would also be needed.
  - (b) Rename the test to what it asserts, for example `test_3920_no_heredoc_and_subshell_command_v`. The red log, the mutation record and the spec's Test Plan row name the selector, so a rename has to carry those along.

### NB1 — NON-BLOCKING (P3) — `.aai/scripts/lib/docs-audit-core.mjs:2033`

`--relative` is load-bearing only when the AAI root is a subdirectory of the git repository. TEST-3915 runs at the top level, where the flag makes no difference.

- Scratch probe: a repository with the project under `sub/`, where the commit runs `git rm sub/docs/specs/SPEC-0007-y.md` and flips the intake to done. The real code gives exit 1 with `no linked spec`. A mutant without `--relative` gives exit 0 with `GATE PASS via linked spec(s) SPEC-0007`, the same defect D1 closes.
- Recommended disposition: remediate-in-tree, by adding a subdirectory-root case to TEST-3915 plus a mutation row that drops `--relative`. Otherwise promote to a follow-up (suggested id `fu-staged-gate-subdir-deleted-untested`).

### NB2 — NON-BLOCKING (P2, pre-existing) — `.aai/templates/git-hooks/pre-commit-index.sh:70` (and `:139`)

This diff did not introduce the defect, but it rewrote both lines and kept `--diff-filter=ACM`. `git diff --cached` porcelain detects renames by default, so a doc renamed in the commit has status `R` and is in neither the close-gate list nor the body-lint list.

- Scratch probe (git 2.54.0): `git mv docs/issues/ISSUE-DRAFT-x.md docs/issues/ISSUE-0001-x.md` plus the `status: done` flip shows `R083`, and the ACM list is empty. A DRAFT numbered and closed in one commit therefore skips the hook's close gate even under `close_gate: enforce`.
- Recommended disposition: promote to a tracked follow-up (suggested id `fu-hook-gate-skips-renamed-doc`). The fix is out of this spec's scope; `--no-renames` on both lists, or adding `R` to the filter, would close it.

### INFO (non-gating)

- INFO-1: CHECKs 1, 5 and 6 now match a whole block with `[[ =~ ]]`. On macOS in a UTF-8 locale, one byte invalid in the locale on any line makes the match fail, where grep matched per line. Probe: `required: *true` gives no match with `[[ =~ ]]` and a match with grep. End to end the difference is masked on macOS, because the existing awk calls of CHECKs 5 and 6 already die on such a STATE (`awk: towc: multibyte conversion failure`, exit 2, commit blocked) on both the base and the new script. The spec discloses it as a residual risk. A cheap hardening is `pcc_match() { local LC_ALL=C; [[ $1 =~ $2 ]]; }`, which I probed on /bin/bash 3.2.57: it matches.
- INFO-2: the hook comment at `pre-commit-index.sh:98-100` still says linked specs are read from the index "(HEAD when absent there)". Under D1 a deleted spec is not read; the comment is stale.
- INFO-3: the hook now creates its scratch directory on every commit, including non-docs commits. If `mktemp -d` fails, every commit is blocked and the only message is mktemp's own. This fails closed.

## Things checked and found sound

- Re-read loop (`pre-commit-checks.sh:131-141`):
  - It runs at most two reads.
  - It only chooses whether to read again, and never skips a check. The parse and both post-parse count checks always judge the pair that was read last.
  - An odd count breaks at once and blocks as `malformed staged list`.
  - An empty or non-numeric `wc` result makes `[ "" -eq N ]` false, which forces the re-read and then blocks after the parse.
  - An arithmetic abort is caught by the `PCC_PARSED` sentinel, which is keyed on `IN_REPO`.
  - A pair whose counts agree but which came from two index states (same-count change) behaves as before: the list itself is one atomic index snapshot, and the names count is only a cross-check.
  - No inconsistent list goes on to the checks.
- Pipe probe: a failed `$(echo ok)` comes back empty, and `staged_read_fail` blocks.
- Hook `-z` loops: `read -r -d ''` ends the loop at EOF without tripping errexit. The `case` filters equal the old regexes: `*` in a case pattern matches `/`, and `docs/INDEX*` is the same as `^docs/INDEX`. Names git would quote now match. A failing `git diff` now exits the hook nonzero under `set -e`. Before, `|| true` hid such a failure behind a pipeline, which skipped the gate. The new form blocks the commit instead.
- `pcc_next_line` gives the same lines as the old `while read` loops, including the empty-input case (no iterations, where before one empty line matched nothing) and CHECK 7's empty-line skip. `echo "    $PCC_LINE"` cannot be read as an option because the line starts with spaces.
- Remaining builtin redirections: only the two permanent `exec` opens and the trap string. `:442` is inside a command substitution, and `ls` is external.
- `/bin/bash -n` passes on both scripts. `git diff --check` is clean, and `git ls-files -ci --exclude-standard` is empty.

## Commands run (this review)

| Command | Exit |
|---|---|
| `docker ps` (DOCKER_HOST/CONTAINER_HOST nonexistent) | 1 (expected) |
| `env -u AAI_ROLE -u AAI_GIT_WRITE /bin/bash tests/skills/test-aai-pre-commit-checks.sh test_39{18,19,20,21,22}_*` | 0 each |
| `env -u AAI_ROLE -u AAI_GIT_WRITE /bin/bash tests/skills/test-aai-docs-audit.sh test_3861_* test_3915_* test_3916_* test_3917_* test_3869_* test_3863_*` | 0 each |
| `env -u AAI_ROLE -u AAI_GIT_WRITE /bin/bash tests/skills/test-aai-git-ref-guard.sh test_308_installer_contract` | 0 |
| `bash docs/ai/reviews/review-precommit-residual-defects-20261120T011041Z-repro-B1.sh` | 1 (gap reproduced) |
| scratch subdir-root probe, real code / no-`--relative` mutant | gate exit 1 / 0 |
| scratch rename probe (`--diff-filter=ACM` on R083) | empty list |
| `/bin/bash -n` on both scripts; `git diff --check` | 0 |

No full sweep was run; validation r2 ran one (`test-20261120-004301`, rc 0).

## Warning dispositions (H6)

- NB1: recommended remediate-in-tree (subdir-root case in TEST-3915 plus mutation row). Fallback: follow-up `suggested: fu-staged-gate-subdir-deleted-untested`, P3.
- NB2: recommended promote-to-follow-up `suggested: fu-hook-gate-skips-renamed-doc`, P2, because it is pre-existing and outside the frozen scope. The orchestrator files it.
- INFO-1 to INFO-3 do not gate.

## Next steps

1. Fix B1 by (a) or (b) above, with a mutation record for the new or renamed pin.
2. Settle NB1 and NB2 per the dispositions above.
3. Re-review the delta. A full sweep is not needed for a test-only change; run the selected pre-commit-checks suite and the mutation replay.
