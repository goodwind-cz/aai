```yaml
review:
  scope: "git diff origin/main...HEAD (HEAD 99efa22, merge-base e21dd1b) limited to .aai/scripts/mutation-run.mjs .aai/scripts/lib/tree-hash.mjs tests/skills/test-aai-mutation-gate.sh docs/issues/ISSUE-0087-mutation-clone-fidelity-windows-eol.md docs/specs/SPEC-0193-spec-mutation-clone-fidelity-windows-eol.md docs/knowledge/FACTS.md docs/INDEX.md (PR #406)"
  spec: docs/specs/SPEC-0193-spec-mutation-clone-fidelity-windows-eol.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/mutation-run.mjs:495-518 overlayTrackedWorkingTreeBytes, :583 call; TEST-001 reviewer re-run exit 0; replay RED" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/mutation-run.mjs:563-581 untracked loop copies root-level paths, :632-635 D4 over the full map; TEST-002 re-run exit 0 and fails on the origin/main runner; reviewer B1 repro STAYED GREEN exit 5" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/scripts/lib/tree-hash.mjs:149-177, .aai/scripts/mutation-run.mjs:643-646; TEST-003 re-run exit 0, also exit 0 under a global core.autocrlf=true HOME; replay RED" }
    deviations:
      - "Spec D4 (\"This ride adds no write to ROOT\") and amended D2 (\"Overlay unlinks the clone destination before write so a leftover symlink cannot write through to ROOT\") are still violated when the leftover symlink is a parent directory rather than the leaf (B2r, reproduced)."
      - "TEST-002 Test Plan row says \"a NOTE names the copied root-level path\"; the NOTE at mutation-run.mjs:590 prints a count only and the test asserts only the phrase 'root-level untracked'."
      - "ISSUE Expected Behavior \"Unrelated untracked files do not participate in clone-fidelity\" (and Verification item 3) is dropped by the D2 reversal, with no descope line in the spec; the spec Problem section and R2 still describe the old root-level omission."
      - "TEST-001 Test Plan row says the clone file bytes equal the source bytes; the test asserts exit 0 only (equal D4 hash is indirect evidence). Carried from round 1."
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/mutation-run.mjs, line: 571,
          issue: "B2 is only half fixed. unlinkIfExists(dst) lstat-checks the leaf, but mkdirSync(path.dirname(dst)), lstat and copyFileSync all resolve through a symlinked ANCESTOR still present in the clone. Both the untracked loop (:571-577) and the overlay (:503-512) then delete and rewrite the link target. It is reachable because a failed git apply is now only a warning (:547-549); origin/main threw there before any copy.",
          failure_scenario: "HEAD tracks lnk as an absolute symlink to <repo>/data (data/f.txt = SHIPPING-DATA) plus a binary lib/blob.bin. Working tree: rm lnk; mkdir lnk; lnk/f.txt = LOCAL-REGULAR; rewrite blob.bin (so git apply fails). Staged or unstaged, the PR runner overwrites the source repo's data/f.txt with LOCAL-REGULAR (git status ' M data/f.txt'), then refuses with exit 3. With lnk pointing outside the repo, the outside file is clobbered. On the same fixtures the origin/main runner exits 1 and writes nothing." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-mutation-gate.sh, line: 2920,
          issue: "No test pins the round-1 B2 leaf guard. Removing all three unlinkIfExists(dst) calls leaves the full suite green.",
          failure_scenario: "Scratch runner with the three calls deleted: the full suite passes (exit 0, 'All aai-mutation-gate tests passed'), and the round-1 leaf repro overwrites the source lib/data.txt again. A refactor that drops the guard ships silently." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-mutation-gate.sh, line: 2920,
          issue: "The test is named test_002_unrelated_untracked_omitted but now asserts the opposite behavior (root-level untracked is copied). The spec Verification section and the mutation-TEST-002 replay record both cite that name.",
          failure_scenario: "Replay prints 'RED TEST-002: still reddens (... test_002_unrelated_untracked_omitted)'. A reader of the record or the spec concludes root-level untracked files are omitted from clone-fidelity, which is false since 99efa22." }
      - { rank: NON-BLOCKING, file: docs/knowledge/FACTS.md, line: 16,
          issue: "The fact 'Root-level untracked paths are skipped on copy and stripped only from the D4 comparison copy of sourceTreeFiles' is false on HEAD.",
          failure_scenario: "FACTS.md is loaded as fact memory. The next agent touching buildIsolatedClone trusts a skip/strip that no longer exists, for example when it adds the --include ride or debugs a D4 mismatch naming a root file." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0193-spec-mutation-clone-fidelity-windows-eol.md, line: 179,
          issue: "Spec R2 ('Root-level-only omit may still copy a nested scratch path') and the Problem sentence 'Unrelated dirty/untracked files also enter the hash' describe the pre-99efa22 design. The ISSUE requirement that unrelated untracked files not participate is dropped with no descope line.",
          failure_scenario: "Validation or closeout walks ISSUE Verification item 3 against the spec and finds neither a covering AC nor a recorded descope. The issue can close as delivered while one expected behavior was silently abandoned." }
  cannot_verify:
    - { claim: "The ride fixes the reported Windows (core.autocrlf=true, mixed EOL) mutation run end-to-end, including --replay and the .ps1 wrapper.",
        closes_with: "A real Windows run on a dirty mixed-EOL tree. CI runs only ps1-quality on Windows; TEST-001 is a Linux simulation with a fixture-local autocrlf." }
    - { claim: "Overlay I/O cost on large tracked trees is acceptable (spec R1).",
        closes_with: "Timed mutation-run on a large repository, before and after." }
    - { claim: "Tolerating a failed git apply is safe once the overlay and the D4 backstop run.",
        closes_with: "B2r shows it is unsafe for a symlinked-ancestor typechange. Other shapes after a failed apply (directory to file, mode-only, submodule gitlink, deletions under a symlinked ancestor) are untested." }
    - { claim: "Root-level untracked files that Windows cannot copy (locked or permission-denied) no longer block a run.",
        closes_with: "A Windows fixture with a locked root-level file. On Linux the skip-by-name path gives a D4 'removed:' refusal, which contradicts the earlier 'NOTE: copied N' line." }
  overall: fail
```

# Code review (round 2): mutation-clone-fidelity-windows-eol

- Reviewer: independent dispatched Code Review, read-only on implementation files.
- Branch and HEAD: `cursor/mutation-clone-fidelity-windows-eol-a7ce` at `99efa22`. Base `origin/main`, merge-base `e21dd1b`.
- PR: https://github.com/goodwind-cz/aai/pull/406
- Spec: `docs/specs/SPEC-0193-spec-mutation-clone-fidelity-windows-eol.md` (frozen, L2). `spec-lint --strategy tdd` passes and `spec-amend list --strict` exits 0.
- Overall: FAIL. Round-1 B1 is cleared. Round-1 B2 is cleared for the leaf shape only; the same write-through remains through a symlinked parent directory (B2r).

## Scope preflight

- STATE `worktree.user_decision: inline`. `inline_review_scope` now lists seven paths, including `docs/INDEX.md`, which matches the spec Isolation section. The round-1 drift is fixed.
- `git status --porcelain` was clean at the start.
- `git diff origin/main...HEAD` also touches `CHANGELOG.md`, `docs/ai/EVENTS.jsonl`, `docs/ai/decisions.jsonl`, and the round-1 review report. These are out of scope and separable with a path-limited diff, so this is not a STOP.
- Coaching check: the dispatch named the round-1 BLOCKING items as context to re-verify. It did not pre-rate new findings or exclude any area. No coaching is recorded, and the full seven-path scope was reviewed.

## Round-1 item re-verification (current tree, scratch copies only)

| Round-1 item | Result on 99efa22 | Evidence |
|---|---|---|
| B1: root-level untracked omitted, causing a false RED | Cleared | Fixture suite requires untracked root `marker.txt`; a comment-only mutation gives `STAYED GREEN`, exit 5. It was RED with exit 0 in round 1. |
| B2: leaf symlink write-through (repo target) | Cleared | Round-1 `fx3` shape: source `lib/data.txt` stays `SHIPPING-DATA`, and the run records RED. |
| B2: leaf symlink write-through (outside target) | Cleared | The outside file stays `OUTSIDE-ORIGINAL`. |
| B2: symlinked parent directory (new shape, same defect class) | Not cleared (B2r) | See the B2r section. |
| NB-1: TEST-002 did not discriminate | Remediated | `AAI_MUTATION_RUN=<origin/main runner>` makes test_002 fail with exit 1 on the NOTE assertion. |
| NB-2: TEST-003 depended on global git config | Remediated | test_003 passes (exit 0) with `HOME` pointing at a `.gitconfig` that sets `core.autocrlf=true`. |
| STATE inline scope omitted INDEX | Remediated | STATE now lists `docs/INDEX.md`. |

## AC table walk (spec_compliance)

| Spec-AC | Call | Citation |
|---|---|---|
| Spec-AC-01 | compliant | `mutation-run.mjs:495-518` overlay, called at `:583`. TEST-001 re-run exit 0; replay RED. |
| Spec-AC-02 | compliant | `mutation-run.mjs:563-581` copies root-level paths; D4 runs over the full map at `:632-635`. TEST-002 re-run exit 0 and it discriminates against `origin/main`; the B1 repro stays green. |
| Spec-AC-03 | compliant | `tree-hash.mjs:149-177`; `mutation-run.mjs:643-646`. TEST-003 re-run exit 0 with and without a global autocrlf. |

Deviations from the frozen spec:

1. D4 and the amended D2 are violated by B2r. D2 now claims that unlinking the clone destination means "a leftover symlink cannot write through to ROOT". That holds for a leaf symlink but not a symlinked ancestor. This alone fails spec_compliance.
2. The TEST-002 Test Plan row says the NOTE names the copied path. `mutation-run.mjs:590` prints only a count.
3. The D2 reversal drops ISSUE Expected Behavior "Unrelated untracked files do not participate in clone-fidelity" without a descope line. The Problem section and R2 still describe the old design (NB-4).
4. TEST-001 still asserts exit 0 only (carried from round 1; equal D4 hashes are indirect evidence).

TEST evidence: TEST-001..003 exist and pass. The full suite `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-mutation-gate.sh` exits 0. `node .aai/scripts/mutation-run.mjs --replay --spec <spec>` reports 3/3 still RED with 0 inconclusive.

## Findings (code_quality)

### B2r (BLOCKING): write-through into ROOT via a symlinked ancestor (`mutation-run.mjs:571-577`, `:503-512`, enabled by `:547-549`)

`unlinkIfExists(dst)` removes a symlink only at the leaf. `fs.mkdirSync(path.dirname(dst), { recursive: true })` accepts an existing symlink-to-directory as the parent. After that, both `lstatSync(dst)`/`unlinkSync(dst)` and `copyFileSync(src, dst)` resolve through it, so the runner deletes and rewrites the link target's file. A clone keeps a HEAD-state symlink only when `git apply` fails, and this diff turned that failure from a throw into a warning.

Reproduction (scratch `/tmp/review-r2-mcf`, script `repro.sh b2-parent` and `b2-parent-out`):

- HEAD tracks `lnk` as an absolute symlink to `<fixture>/data`, where `data/f.txt` holds `SHIPPING-DATA`. HEAD also tracks a binary `lib/blob.bin`.
- In the working tree, `lnk` is replaced by a real directory holding `lnk/f.txt` (`LOCAL-REGULAR`), and `blob.bin` is rewritten.
- Run output: `git apply did not reproduce ... cannot apply binary patch`, then exit 3 with `removed: lnk/f.txt`.
- Afterwards the source repo's `data/f.txt` contains `LOCAL-REGULAR` and `git status` shows ` M data/f.txt`.
- This happens both staged (the overlay loop writes) and unstaged (the untracked loop writes, before the overlay unlinks `clone/lnk`).
- In the outside-target variant, `<outside>/f.txt` is clobbered.
- `origin/main` runner on the same four fixtures: exit 1 on the apply failure, and every target file is unchanged.

Candidate fix directions (Remediation's call):

- Before any write, walk each ancestor of `dst` inside `cloneDir` with `lstat` and replace a symlinked ancestor with a real directory. Alternatively, require `realpath(path.dirname(dst))` to stay inside `realpath(cloneDir)` and skip or refuse otherwise.
- Or restore the throw on a failed `git apply` unless the failure is limited to paths the overlay provably owns.

Add a RED-first regression test for the symlinked-ancestor shape in both the staged and unstaged forms.

### NB-1 (NON-BLOCKING, P2): the leaf guard is unpinned (`test-aai-mutation-gate.sh`, no test)

A scratch copy of `.aai/scripts` with all three `unlinkIfExists(dst);` calls deleted passes the full suite (exit 0). That same copy overwrites the source `lib/data.txt` in the round-1 leaf repro. Recommended disposition: (a) remediate in tree, together with the B2r regression test.

### NB-2 (NON-BLOCKING, P2): TEST-002's name states the opposite of what it proves (`test-aai-mutation-gate.sh:2920`)

`test_002_unrelated_untracked_omitted` now proves that root-level untracked files are copied. The spec Verification section and the replay output cite the name, which leaves a false record. Recommended disposition: (a) rename it (for example `test_002_root_untracked_copied`), update the spec Verification line, and re-stamp the mutation record. Make the NOTE name the path, or change the Test Plan row to "count".

### NB-3 (NON-BLOCKING, P2): FACTS.md holds a false fact (`docs/knowledge/FACTS.md:16-19`)

"Root-level untracked paths are skipped on copy and stripped only from the D4 comparison copy" no longer matches the code. Recommended disposition: (a) rewrite the bullet to describe the current copy-and-hash behavior, or delete it.

### NB-4 (NON-BLOCKING, P2): the spec leaves an issue requirement undisclosed (`SPEC-DRAFT...:179`, Problem section)

R2 and the Problem sentence describe the old omission design, and the ISSUE bullet "Unrelated untracked files do not participate in clone-fidelity" is dropped with no descope. Recommended disposition: (a) amend the spec via `spec-amend.mjs add` to name that bullet as descoped (with its reason: false RED), and replace R2 with the current residual (an uncopyable root file refuses via D4). Fallback: (c) a tracked follow-up ref for the requirement.

### INFO (non-gating)

- `NOTE: copied N root-level untracked path(s)` comes from the pre-copy set. A root file that is skipped by name still counts as "copied", after which D4 refuses with `removed:`.
- The overlay still prints `skipping tracked overlay <path> (ENOENT ...)` for tracked files deleted in the working tree. A submodule gitlink produces an `unlinkSync`-on-directory skip line. Both are noise, not skips.
- The test file mode changed from 100644 to 100755, which is harmless.
- Reviewer side effect, disclosed: `node .aai/scripts/generate-docs-index.mjs --help` ignores `--help` and rewrote `docs/INDEX.md`, changing only the `Generated:` line. The committed bytes were written back from `git show HEAD:docs/INDEX.md` into a scratch file and copied over, and `git diff --quiet -- docs/INDEX.md` exited 0. The only difference was the timestamp, so the committed INDEX is otherwise current.

## cannot_verify

1. The end-to-end Windows fix (`core.autocrlf=true`, mixed EOL, `.ps1` wrapper, `--replay`). Closes with a real Windows run.
2. Overlay I/O cost on large trees (R1). Closes with a timed before/after run.
3. The general safety of tolerating a failed `git apply`. B2r shows one unsafe shape; directory-to-file, mode-only, gitlink, and deletion-under-a-symlinked-ancestor shapes are untested.
4. Behavior with a locked or permission-denied root-level untracked file on Windows. Closes with a Windows fixture.

## Warning dispositions (H6)

- NB-1 (P2): recommended (a) remediate in tree, bundled with the B2r regression test.
- NB-2 (P2): recommended (a) rename plus spec Verification and record re-stamp. It leaves a false record, so (d) is not allowed.
- NB-3 (P2): recommended (a) fix the FACTS bullet. False record, so (d) is not allowed.
- NB-4 (P2): recommended (a) spec amendment naming the descope. Fallback (c): `suggested: fu-mutation-clone-unrelated-untracked-descope` (not filed).
- B2r blocks. It is not a warning and cannot take disposition (d).

## Reviewer evidence (commands run, all exit codes read)

- Full suite: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-mutation-gate.sh`, exit 0.
- test_001, test_002, and test_003 selected runs: exit 0 each.
- Replay: `node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-0193-spec-mutation-clone-fidelity-windows-eol.md` reports 3/3 RED, exit 0.
- `spec-lint --path <spec> --strategy tdd`: LINT PASS, exit 0. `spec-amend list --strict`: exit 0.
- B1 repro (`repro.sh b1`): `STAYED GREEN`, exit 5.
- B2 leaf repros (`b2-leaf`, `b2-leaf-out`): targets unchanged, RED, exit 0.
- B2r repros (`b2-parent`, `b2-parent-out`, STAGE=1 and STAGE=0): targets overwritten, exit 3. The `origin/main` runner (`git archive origin/main .aai/scripts`) exits 1 on all four with targets unchanged.
- NB-1 guard check: the scratch runner without `unlinkIfExists(dst)` passes the full suite (exit 0) and re-clobbers in `b2-leaf`.
- Round-1 NB checks: test_002 against the `origin/main` runner exits 1; test_003 under a global autocrlf `HOME` exits 0.
- All experiments ran under `/tmp/review-r2-mcf`. The shipping tree `git status --porcelain` was empty at the end, apart from this report.

## Next steps

1. Remediation: fix B2r with a RED-first regression test covering the staged and unstaged symlinked-ancestor shapes. That test also pins the leaf guard (NB-1). Fix NB-2, NB-3, and NB-4 in the same pass.
2. Operator contract rule 3: this is the second finding-bearing review round. If a third round still finds something, split the ride rather than re-verifying it. One way to split: keep the EOL overlay and diagnostics here, and move the `git apply` failure tolerance to its own ride.
3. Re-review with a fresh single pass after remediation.
