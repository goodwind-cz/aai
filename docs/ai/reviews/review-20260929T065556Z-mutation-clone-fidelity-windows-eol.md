```yaml
review:
  scope: "git diff origin/main...HEAD (HEAD 58034c7) limited to .aai/scripts/mutation-run.mjs .aai/scripts/lib/tree-hash.mjs tests/skills/test-aai-mutation-gate.sh docs/issues/ISSUE-DRAFT-mutation-clone-fidelity-windows-eol.md docs/specs/SPEC-DRAFT-spec-mutation-clone-fidelity-windows-eol.md docs/knowledge/FACTS.md docs/INDEX.md (PR #406)"
  spec: docs/specs/SPEC-DRAFT-spec-mutation-clone-fidelity-windows-eol.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/mutation-run.mjs:486-505 overlayTrackedWorkingTreeBytes, :570 call; TEST-001 green (reviewer re-run exit 0); replay RED" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/mutation-run.mjs:545-553 copy skip, :613-615 D4 filtered copy; TEST-002 green but non-discriminating (NB-1)" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/scripts/lib/tree-hash.mjs:149-177, .aai/scripts/mutation-run.mjs:626-629; TEST-003 green (reviewer re-run exit 0); replay RED" }
    deviations:
      - "Spec D4 (\"This ride adds no write to ROOT\") violated: the overlay writes through a clone-side symlink into the source working tree (B2, reproduced)."
      - "TEST-001 Test Plan row says the clone file bytes equal source bytes; the test asserts only exit 0 (indirect via the D4 hash)."
      - "TEST-002 Test Plan row says scratch.tmp is absent from the clone; the test asserts only exit 0 (NB-1)."
      - "STATE worktree.inline_review_scope omits docs/INDEX.md, which the spec Isolation section names."
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/mutation-run.mjs, line: 553,
          issue: "Root-level untracked files are silently dropped from the clone (no NOTE, no record field), and nothing checks that the unmutated clone is green, so a test that needs a new root-level file fails for the missing file and is recorded RED.",
          failure_scenario: "Fixture: committed lib/greeting.mjs plus a suite asserting an untracked root-level marker.txt exists; mutation --sed 's/comment-a/comment-b/' (comment only). PR runner: RED, first_fail 'TEST-9001 root-level marker.txt missing', exit 0. origin/main runner: STAYED GREEN, exit 5. A TDD ride that adds any root-level file (rides commit after validation, so it is untracked at mutation time) gets a false-RED record that mutation-gate accepts." }
      - { rank: BLOCKING, file: .aai/scripts/mutation-run.mjs, line: 499,
          issue: "copyFileSync(src, dst) follows a symlink already at dst, so the overlay writes outside the clone, including into the shipping tree. Reachable now that a failed git apply is only a warning (line 535).",
          failure_scenario: "HEAD tracks lib/cfg as an absolute symlink to <repo>/lib/data.txt; working tree typechanges lib/cfg to a regular file and dirties a tracked binary (git apply fails, is tolerated). Overlay copies the new lib/cfg bytes through the clone's still-checked-out symlink: the source repo's lib/data.txt is overwritten (git status shows ' M lib/data.txt'), then D4 refuses with exit 3. With the link pointing outside the repo, the outside file is clobbered and the run records RED with no warning." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-mutation-gate.sh, line: 2937,
          issue: "TEST-002 asserts only exit 0; the pre-change origin/main runner also exits 0 on the identical scenario (scratch.tmp copied and hashed on both sides). Only its one-line mutation reddens it; deleting both coupled filters (copy skip and D4 delete) survives.",
          failure_scenario: "Regression reintroducing root-level untracked copy+compare (the pre-change behavior) passes TEST-002 unchanged." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-mutation-gate.sh, line: 2980,
          issue: "TEST-003 depends on the host's global git config: with core.autocrlf=true (Git for Windows default) the clone checkout CRLFs every file, so greeting.mjs matches and other paths mismatch.",
          failure_scenario: "HOME with .gitconfig core.autocrlf=true: test_003 FAIL 'TreeMismatchError missing path' (exit 1), while test_001 still passes. The suite reds on exactly the platform this ride targets." }
  cannot_verify:
    - { claim: "The ride fixes the reported Windows (core.autocrlf=true, mixed EOL) mutation run end-to-end, including --replay.",
        closes_with: "A real Windows run through the .ps1 wrapper on a dirty mixed-EOL tree (CI has only ps1-quality on Windows); TEST-001 is a Linux simulation with a local-only autocrlf fixture." }
    - { claim: "Overlay I/O cost on large tracked trees is acceptable (spec R1).",
        closes_with: "Timed mutation-run on a large repo, before/after." }
    - { claim: "Downgrading git apply failure to a warning is always safe because the overlay plus D4 backstop cover it.",
        closes_with: "Shown unsafe for the symlink-typechange case (B2); other typechange/deletion/mode shapes after a failed apply are not tested." }
  overall: fail
```

# Code review — mutation-clone-fidelity-windows-eol

- Reviewer: independent dispatched Code Review (read-only on implementation files)
- Branch / HEAD: `cursor/mutation-clone-fidelity-windows-eol-a7ce` @ `58034c7cc4110d1ff92728e579e4f734ac82371e`, base `origin/main`
- PR: https://github.com/goodwind-cz/aai/pull/406
- Spec: `docs/specs/SPEC-DRAFT-spec-mutation-clone-fidelity-windows-eol.md` (frozen, L2)
- Overall: FAIL. spec_compliance fails on a D4 deviation; code_quality fails with 2 BLOCKING findings.

## Scope preflight

- STATE `worktree.user_decision: inline`; `inline_review_scope` = six paths. The spec Isolation section adds `docs/INDEX.md`, so the review covers seven paths.
- `git diff origin/main...HEAD` also touches `CHANGELOG.md`, `docs/ai/EVENTS.jsonl`, and `docs/ai/decisions.jsonl`. These are out of scope and separable (path-limited diff), so this is not a STOP.
- `git status --porcelain`: ` M docs/ai/EVENTS.jsonl` only, which is out of scope and was pre-existing at dispatch.
- Coaching check: the dispatch did not pre-rate findings or exclude areas. It named the validation report "context, not a rubber stamp". No coaching recorded.

## AC table walk (spec_compliance)

| Spec-AC | Call | Citation |
|---|---|---|
| Spec-AC-01 | compliant | `mutation-run.mjs:486-505` overlay; `:570` call. TEST-001 re-run exit 0; replay RED. |
| Spec-AC-02 | compliant | `mutation-run.mjs:545-553` skip; `:613-615` D4 filtered copy. D7 still receives unstripped `sourceTreeFiles`. TEST-002 re-run exit 0, but non-discriminating (NB-1). The reviewer's false-RED repro independently confirms omission from the clone. |
| Spec-AC-03 | compliant | `tree-hash.mjs:149-177` `isEolOnlyDiff`/`eolOnlyMismatchNote`; `mutation-run.mjs:626-629`. TEST-003 re-run exit 0; replay RED. |

Deviations from the frozen spec:

1. D4: "This ride adds no write to ROOT." Violated under a reachable input (B2): the overlay wrote the source repo's `lib/data.txt`. This fails spec_compliance even though all three AC rows are met.
2. TEST-001 Test Plan says "the clone file bytes equal the source working-tree bytes". The test asserts only `rc == 0`. Equal D4 hashes imply equal per-file hashes, so this is acceptable as indirect evidence, but it is not what the row states.
3. TEST-002 Test Plan says "scratch.tmp is absent from the clone". Not asserted (NB-1).
4. STATE `inline_review_scope` lacks `docs/INDEX.md`, which the spec Isolation section names. STATE/spec drift; the orchestrator should align them.

TEST evidence: TEST-001..003 exist and pass. The full suite `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-mutation-gate.sh` passes (exit 0, "All aai-mutation-gate tests passed"). `node .aai/scripts/mutation-run.mjs --replay --spec <spec>` reports 3/3 still redden, 0 inconclusive.

## Findings (code_quality)

### B1 — BLOCKING — false RED from silently omitted root-level untracked payload (`mutation-run.mjs:545-553`, `:613-615`)

The root-level filter drops every untracked path without a `/` from the clone and prints nothing about it. That breaks the AGENTS.md Degrade-with-NOTE rule. The runner never checks that the unmutated clone is green, and `classifyVerdict` records RED for any FAIL line naming the test id. So a test that depends on a new root-level file fails in the clone for the missing file, and the runner records that as the mutation being caught.

Reproduction (scratch `/tmp/review-mcf-4634/fx`):

- Committed `lib/greeting.mjs` holds `// comment-a` followed by `console.log('hello')`.
- The suite asserts the greeting output and that `$FROOT/marker.txt` exists. `marker.txt` is an untracked root-level file. The suite passes in the source tree.
- The mutation is `--sed 's/comment-a/comment-b/'`, a comment-only change, so the correct verdict is STAYED GREEN.
- PR runner: `RED`, `first_fail: FAIL: TEST-9001 root-level marker.txt missing`, exit 0. No NOTE is printed.
- `origin/main` runner (`git archive origin/main .aai/scripts`): `STAYED GREEN`, exit 5.

This path is likely to be hit: AAI rides commit after validation, so any file a ride adds at the repository root is untracked when the mutation runs. For example, a new root config, a `conftest.py` in a flat Python layout, or a root doc a test asserts on.

The spec's R2 covers only the opposite risk (nested scratch still copied). D2 as frozen causes this, so fixing it needs a Planning amendment to D2. Candidate directions, which are Planning's call:

- Copy root-level untracked files best-effort but keep them out of the D4 comparison on both sides. This fits the intake's "do not participate in clone-fidelity" while keeping the payload.
- At minimum, print a NOTE line and add a record field naming every omitted path.
- Run a baseline unmutated check in the clone and downgrade to INCONCLUSIVE if it is not green.

### B2 — BLOCKING — overlay writes through a clone-side symlink, into the shipping tree (`mutation-run.mjs:499`, enabled by `:535`)

`fs.copyFileSync(src, dst)` opens `dst` without `O_NOFOLLOW`. If `dst` in the clone is still a symlink from checkout, the bytes land at the link target. Before this diff, a failed `git apply` threw, so the clone's HEAD state never reached a copy step. The diff turns that failure into a warning, and `git apply` is atomic, so one failing hunk (a dirty binary, or the EOL-context failure this ride is about) leaves every typechange unapplied.

Reproduction (scratch `/tmp/review-mcf-4634/fx3`):

- HEAD tracks `lib/cfg` as an absolute symlink to `<fixture>/lib/data.txt` ("SHIPPING-DATA"), plus a binary `lib/blob.bin`.
- In the working tree, `lib/cfg` becomes a regular file "LOCAL-REGULAR" and `blob.bin` is rewritten.
- Run output: `git apply did not reproduce ... patch does not apply`, then exit 3 with `changed: lib/data.txt`.
- Afterwards the source repo's `lib/data.txt` contains `LOCAL-REGULAR` and `git status` shows ` M lib/data.txt`. The user's shipping file was overwritten, which violates spec D4 and SPEC-0181 D7.
- Variant `fx2`: the link points outside the repo. The outside file is clobbered, D4 passes, and the run records RED with no warning.

Fix direction: remove `dst` before `copyFileSync` (for example `fs.rmSync(dst, { force: true })`, with a directory-vs-file guard) or copy with `COPYFILE_EXCL` after unlinking. Add a RED-first regression test for the typechange-after-failed-apply shape.

### NB-1 — NON-BLOCKING (P2) — TEST-002 does not pin the omission (`test-aai-mutation-gate.sh:2920-2939`)

The identical scenario (untracked `lib/extra.txt` plus root `scratch.tmp`) exits 0 on the `origin/main` runner, where scratch.tmp is copied and hashed on both sides. TEST-002 is RED only under its single-line mutation (removing the copy skip while keeping the D4 delete). Deleting both coupled filters survives, and the Test Plan claim "scratch.tmp is absent from the clone" is never asserted.

Recommended disposition: (a) remediate in tree together with B1. The D2 amendment will reshape this test anyway. Make the fixture suite observe the root file's presence or absence inside the clone.

### NB-2 — NON-BLOCKING (P3) — TEST-003 depends on host global git config (`test-aai-mutation-gate.sh:2941-2987`)

With `HOME` pointing at a `.gitconfig` that sets `core.autocrlf=true`, `test_003_eol_only_mismatch_token` fails with `TreeMismatchError missing path` (exit 1). The clone checkout CRLFs every file, so `greeting.mjs` matches while `.gitignore`, the suite, the spec, and the wrapper all mismatch. `test_001` still passes under the same config. Linux CI is unaffected, but the suite reds on a Windows developer host, which is the platform this ride targets.

Recommended disposition: (a) remediate in tree by pinning the runner invocation's git config in the test (for example `GIT_CONFIG_GLOBAL=/dev/null` or `HOME=<fixture>`). Alternatively (b), a `follow-ups.mjs` P3 entry.

### INFO (non-gating)

- `overlayTrackedWorkingTreeBytes` prints `skipping tracked overlay <path> (ENOENT ...)` for every tracked file deleted in the working tree. This is expected, not a skip, and could be filtered (lstat ENOENT then continue silently).
- The test file mode changed 100644 to 100755. That is harmless; `tests/skills/` already mixes both modes.
- `isEolOnlyDiff` strips every CR, including lone CRs. This is consistent with D3's "differ only by the presence of CR".

## cannot_verify

1. The end-to-end Windows fix (`core.autocrlf=true`, mixed EOL, `.ps1` wrapper, `--replay`). Closes with a real Windows run; CI runs only `ps1-quality` on Windows.
2. Overlay I/O cost on large trees (spec R1). Closes with a timed before/after run on a large repository.
3. The general safety of tolerating a failed `git apply`. B2 shows one unsafe shape; other typechange, deletion, and mode shapes after a failed apply are untested.

## Warning dispositions (H6)

- NB-1 (P2): recommended (a) remediate in tree with B1. The orchestrator records the choice.
- NB-2 (P3): recommended (a) remediate in tree. Fallback (b) is `follow-ups.mjs add --id fu-mutation-test003-global-autocrlf` (suggested, not filed).
- B1 and B2 block. They are not warnings and cannot take disposition (d).

## Reviewer evidence (commands run, all exit codes read)

- Full suite: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-mutation-gate.sh`, exit 0.
- `test_001` / `test_002` / `test_003` selected runs: exit 0 each.
- Replay: `node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-DRAFT-spec-mutation-clone-fidelity-windows-eol.md` reports 3/3 RED, exit 0.
- B1 repro: PR runner exit 0 RED vs origin/main runner exit 5 STAYED GREEN.
- B2 repro: source `lib/data.txt` overwritten; outside-file variant clobbered.
- NB-1 repro: origin/main runner exit 0 on the TEST-002 scenario.
- NB-2 repro: test_003 exit 1 under global `core.autocrlf=true`.
- All experiments ran in `/tmp/review-mcf-4634`. The shipping tree is unchanged: porcelain shows only the pre-existing ` M docs/ai/EVENTS.jsonl`.

## Next steps

1. Send the scope to Planning to amend D2 for B1 (copy root-level untracked but exclude it from comparison, or a NOTE plus record field or baseline check). Also align the STATE inline scope with the spec (`docs/INDEX.md`).
2. Remediation: fix B2 with a RED-first regression test; fix B1 per the amended D2 with RED-first tests; tighten TEST-002 (NB-1) and TEST-003 (NB-2).
3. Re-review: a fresh single pass after remediation.
