```yaml
review:
  scope: "git diff origin/main...HEAD (HEAD a0f1d3d, merge-base e21dd1b) limited to .aai/scripts/mutation-run.mjs .aai/scripts/lib/tree-hash.mjs tests/skills/test-aai-mutation-gate.sh docs/issues/ISSUE-DRAFT-mutation-clone-fidelity-windows-eol.md docs/specs/SPEC-DRAFT-spec-mutation-clone-fidelity-windows-eol.md docs/knowledge/FACTS.md docs/INDEX.md (PR #406)"
  spec: docs/specs/SPEC-DRAFT-spec-mutation-clone-fidelity-windows-eol.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/mutation-run.mjs:525-548 overlayTrackedWorkingTreeBytes, :614 call; TEST-001 reviewer re-run exit 0; replay RED; also exit 0 under HOME core.autocrlf=true" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/mutation-run.mjs:587-612 untracked loop copies root-level paths, :619-622 NOTE names them, :665-668 D4 over the full map; TEST-002 reviewer re-run exit 0; origin/main runner fails the NOTE assertion; B1 repro STAYED GREEN exit 5" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/scripts/lib/tree-hash.mjs:149-177, .aai/scripts/mutation-run.mjs:674-678; TEST-003 reviewer re-run exit 0, also exit 0 under HOME core.autocrlf=true; replay RED" }
      - { ac: Spec-AC-04, call: compliant,
          citation: ".aai/scripts/mutation-run.mjs:498-523 ensureCloneParentDirs, :486-493 unlinkIfExists; TEST-004/005 reviewer re-run exit 0; replay RED; reviewer staged-outside / unstaged-leaf / outside-leaf probes leave ROOT bytes unchanged, exit 0" }
    deviations:
      - "TEST-001 Test Plan row says the clone file bytes equal the source working-tree bytes; the test asserts exit 0 only (equal D4 hashes are indirect evidence). Carried from rounds 1-2; not an AC miss."
      - "D1's informal 'clone tracked files byte-identical' is incomplete for a tracked delete when git apply failed: overlay skips ENOENT and leaves the clone copy (NB-1). Spec-AC-01's WHEN is the CRLF dirty-file shape, which holds."
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/mutation-run.mjs, line: 544,
          issue: "After git apply is warning-only, overlay copies existing tracked working-tree files but does not remove a clone copy whose source path is gone (lstat ENOENT is skipped). D4 then refuses (exit 3) instead of reproducing a working tree that deleted that path.",
          failure_scenario: "HEAD tracks lib/doomed.txt and a binary lib/blob.bin. Working tree deletes doomed.txt and rewrites blob.bin so git apply fails. Runner prints 'skipping tracked overlay lib/doomed.txt (ENOENT ...)', then TreeMismatchError 'added: lib/doomed.txt', exit 3. Mutation never runs. Observed in /tmp/review-r3-mcf/delete." }
  cannot_verify:
    - { claim: "The ride fixes the reported Windows (core.autocrlf=true, mixed EOL) mutation run end-to-end, including --replay and the .ps1 wrapper.",
        closes_with: "A real Windows run on a dirty mixed-EOL tree. CI runs only ps1-quality on Windows; TEST-001 is a Linux simulation with a fixture-local autocrlf." }
    - { claim: "Overlay I/O cost on large tracked trees is acceptable (spec R1).",
        closes_with: "Timed mutation-run on a large repository, before and after." }
    - { claim: "ensureCloneParentDirs can replace a leftover directory symlink or junction on native Windows Node (fs.unlinkSync of a dir symlink).",
        closes_with: "A native Windows Node fixture (not WSL) with HEAD tracking a directory symlink, dirty binary, working tree replaced by a real directory. Linux TEST-004 cannot speak to that unlink." }
    - { claim: "An uncopyable root-level untracked file (locked or permission-denied) behaves as spec R2 (NOTE counts it, D4 removed:).",
        closes_with: "A Windows locked-file fixture, as the spec already names cannot_verify." }
  overall: pass
```

# Code review (round 3): mutation-clone-fidelity-windows-eol

- Reviewer: independent dispatched Code Review, read-only on implementation files.
- Branch and HEAD: `cursor/mutation-clone-fidelity-windows-eol-a7ce` at `a0f1d3d46c6dde3a1ccedcaba1b17301de700181`. Base `origin/main`, merge-base `e21dd1b`.
- PR: https://github.com/goodwind-cz/aai/pull/406
- Spec: `docs/specs/SPEC-DRAFT-spec-mutation-clone-fidelity-windows-eol.md` (frozen, L2). `spec-lint --strategy tdd` PASS exit 0. `spec-amend list --strict` exit 0.
- Overall: PASS. spec_compliance PASS. code_quality PASS with one NON-BLOCKING warning.

## Scope preflight

- STATE `worktree.user_decision: inline`. `inline_review_scope` is the seven paths above and matches the spec Isolation section.
- `git status --porcelain` was empty at the start and at the end of reviewer probes.
- `git diff origin/main...HEAD` also touches `CHANGELOG.md`, `docs/ai/EVENTS.jsonl`, `docs/ai/decisions.jsonl`, and the two prior review reports. Those are out of scope and separable with a path-limited diff, so this is not a STOP.
- Coaching check: the dispatch named prior reports as items to re-verify without inheriting verdicts, and said last_validation is on an older HEAD. It did not pre-rate new findings or exclude any area. No coaching recorded. Full seven-path scope reviewed.

## Prior-item re-verification (current tree; scratch copies only)

| Prior item | Result on a0f1d3d | Evidence |
|---|---|---|
| r1 B1: root-level untracked omitted, false RED | Cleared | Fixture suite requires untracked root `marker.txt`; comment-only mutation is `STAYED GREEN`, exit 5; NOTE names `marker.txt`. |
| r1 B2: leaf symlink write-through (in-repo / outside) | Cleared | TEST-005 exit 0, `lib/data.txt` stays `SHIPPING-DATA`. Reviewer outside-leaf probe: outside bytes stay `OUTSIDE-ORIGINAL`, exit 0. Replay TEST-005 RED. |
| r2 B2r: ancestor symlink write-through | Cleared | TEST-004 staged+unstaged in-repo and unstaged outside exit 0. Reviewer **staged-outside** arm (not in TEST-004): outside `f.txt` stays `OUTSIDE-ORIGINAL`, exit 0. Replay TEST-004 RED. |
| r1 NB-1: TEST-002 did not discriminate | Cleared | `AAI_MUTATION_RUN` = origin/main runner: TEST-002 fails on the NOTE assertion (exit 1). |
| r1 NB-2: TEST-003 depended on global git config | Cleared | TEST-003 and TEST-001 pass (exit 0) with `HOME` pointing at a `.gitconfig` that sets `core.autocrlf=true`. |
| r2 NB-1: leaf `unlinkIfExists` unpinned | Cleared | TEST-005 mutation `sed:s/unlinkIfExists\(dst\);//g` still reddens on replay. |
| r2 NB-2: TEST-002 name stated the opposite | Cleared | Function is `test_002_root_untracked_copied`; spec Verification cites that name. |
| r2 NB-3: FACTS.md described the old skip/strip | Cleared | FACTS now states copy+hash and parent-walk + leaf unlink, with TEST-002/004/005 evidence. |
| r2 NB-4: ISSUE unrelated-untracked dropped with no descope | Cleared | Spec Problem + Mapping + ISSUE Notes name the descope and the false-RED reason. |
| STATE inline scope omitted INDEX | Cleared (already on r2 tree) | STATE and spec Isolation both list `docs/INDEX.md`. INDEX lists the spec (4 done) and the ISSUE draft. |

## AC table walk (spec_compliance)

| Spec-AC | Call | Citation |
|---|---|---|
| Spec-AC-01 | compliant | Overlay at `mutation-run.mjs:525-548`, called at `:614`. TEST-001 re-run exit 0, including under global autocrlf. Replay RED. |
| Spec-AC-02 | compliant | Untracked loop copies root-level paths; NOTE at `:619-622` names `scratch.tmp`. TEST-002 re-run exit 0. Discriminates against origin/main. B1 repro stays green. |
| Spec-AC-03 | compliant | `tree-hash.mjs:149-177`; `eolSuffix` at `mutation-run.mjs:674-678`. TEST-003 re-run exit 0 with and without global autocrlf. Replay RED. |
| Spec-AC-04 | compliant | `ensureCloneParentDirs` + `unlinkIfExists` on overlay, untracked copy, and allowlist writers. TEST-004/005 re-run exit 0. Replay 2/2 RED. Extra staged-outside / unstaged-leaf / outside-leaf probes do not write ROOT. |

Deviations from the frozen spec (neither is an AC miss):

1. TEST-001 Test Plan says clone bytes equal source bytes; the test asserts exit 0 only. Equal D4 hashes imply equal per-file hashes.
2. Overlay does not delete clone copies of tracked paths that are gone in the working tree when `git apply` failed (NB-1). Spec-AC-01's WHEN (CRLF dirty file) still holds.

TEST evidence: TEST-001..005 exist and pass. Replay `node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-DRAFT-spec-mutation-clone-fidelity-windows-eol.md` reports 5/5 still RED, 0 inconclusive, exit 0. TEST-471 (pre-existing dirty-tree clone-fidelity) still passes.

## Findings (code_quality)

No BLOCKING findings.

### NB-1 (NON-BLOCKING, P2): overlay does not reproduce a tracked delete after a failed `git apply` (`mutation-run.mjs:544`, enabled by `:577`)

`git apply` failure is a warning so overlay can be the fidelity source of truth. Overlay then `lstat`s each `git ls-files` path and, on ENOENT, skips. The clone still holds the HEAD copy. D4 reports `added: <path>` and throws `TreeMismatchError` (exit 3).

Reproduction (`/tmp/review-r3-mcf/delete`):

- HEAD tracks `lib/doomed.txt` (`KEEPME`) and binary `lib/blob.bin`.
- Working tree: delete `doomed.txt`, rewrite `blob.bin`.
- Output: `git apply did not reproduce ... cannot apply binary patch`, `skipping tracked overlay lib/doomed.txt (ENOENT ...)`, exit 3, `added: lib/doomed.txt`.
- Before this ride the same shape threw on apply (exit 1) and also never ran the mutation. This is not a write-through and not a false RED. It is a remaining INCONCLUSIVE hole in the "overlay replaces apply" claim, for any tree that combines a tracked delete with an apply-failing hunk (dirty binary, or the EOL apply failure this ride targets).

A file-to-directory typechange plus dirty binary (reviewer P8) succeeded (exit 0, RED recorded). The hole is specifically "source path missing, clone still has the file".

Recommended disposition: (b) promote to a follow-up ref. Suggested id `fu-mutation-overlay-tracked-deletes` (not filed; reviewer is read-only). Do not take (d): the bite was observed (exit 3).

## cannot_verify

1. End-to-end Windows fix (`core.autocrlf=true`, mixed EOL, `.ps1` wrapper, `--replay`). Closes with a real Windows run.
2. Overlay I/O cost on large trees (R1). Closes with a timed before/after run.
3. Native Windows `unlinkSync` of a leftover directory symlink or junction inside `ensureCloneParentDirs`. Linux TEST-004 cannot speak to it. Closes with a native Windows Node fixture.
4. Locked / permission-denied root-level untracked file (spec R2). Closes with a Windows locked-file fixture.

## Warning dispositions (H6)

- NB-1 (P2): recommended (b) `follow-ups.mjs add --id fu-mutation-overlay-tracked-deletes --ref mutation-clone-fidelity-windows-eol --severity P2 --what "overlay skips ENOENT so a tracked delete plus failed git apply still INCONCLUSIVE (exit 3)" --why "apply is warning-only; overlay copies existing files but does not remove clone leftovers" --source docs/ai/reviews/review-20260929T073508Z-mutation-clone-fidelity-windows-eol.md`. Reviewer does not file it.
- No BLOCKING findings. No (d) accepted residual.

## Reviewer evidence (commands run, all exit codes read)

- TEST-001..005 selected: each exit 0 via `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-mutation-gate.sh test_*`.
- TEST-471 smoke: exit 0.
- Replay: 5/5 RED, 0 inconclusive, exit 0.
- `spec-lint --path <spec> --strategy tdd`: LINT PASS, exit 0.
- `spec-amend list --strict`: exit 0 (this spec's amendments are unsigned-tracked under `fu-amend-mutation-clone-fidelity-8bfdf9`).
- r1 B1 repro: `STAYED GREEN`, exit 5.
- r1 NB-1: origin/main runner + TEST-002 exit 1 (missing NOTE).
- r1 NB-2: TEST-003 and TEST-001 exit 0 under global autocrlf HOME.
- Spec-AC-04 extra arms: staged-outside, unstaged-leaf, outside-leaf: ROOT/outside bytes unchanged, exit 0.
- NB-1 deletion probe: exit 3, `added: lib/doomed.txt`.
- File-to-directory leftover + dirty binary: exit 0.
- All probes under `/tmp/review-r3-mcf` and `/tmp/review-r3-mcf2`. Shipping `git status --porcelain` empty.

## Next steps

1. Orchestrator records H6 for NB-1 (file the follow-up or remediate). Unsigned spec amendments on this ride already sit on `fu-amend-mutation-clone-fidelity-8bfdf9` (owner sign-off owed; not a code defect).
2. This is the third review round. It is not finding-bearing for BLOCKING items; prior BLOCKING items are cleared. No split is required for a PASS.
3. Merge/PR readiness still needs a Validation PASS on this HEAD (`last_validation` is on an older tree).

## state_update_commands

Dispatched reviewer (D1): do not run these. Orchestrator merges:

```bash
node .aai/scripts/state.mjs set-code-review \
  --required true --status pass \
  --scope "git diff origin/main...HEAD (HEAD a0f1d3d, merge-base e21dd1b) limited to .aai/scripts/mutation-run.mjs .aai/scripts/lib/tree-hash.mjs tests/skills/test-aai-mutation-gate.sh docs/issues/ISSUE-DRAFT-mutation-clone-fidelity-windows-eol.md docs/specs/SPEC-DRAFT-spec-mutation-clone-fidelity-windows-eol.md docs/knowledge/FACTS.md docs/INDEX.md (PR #406)" \
  --base-ref origin/main \
  --report docs/ai/reviews/review-20260929T073508Z-mutation-clone-fidelity-windows-eol.md \
  --notes "PASS; H6 NB-1 overlay-tracked-delete residual -> follow-up fu-mutation-overlay-tracked-deletes (recommended, not filed)"

node .aai/scripts/state.mjs append-run \
  --ref mutation-clone-fidelity-windows-eol \
  --role "Code Review" \
  --model cursor-grok-4.6 \
  --started 2026-09-29T07:27:00Z \
  --verdict pass \
  --note "usage_capture=none; PASS review-20260929T073508Z; prior B1/B2/B2r cleared; H6 NB-1 fu-mutation-overlay-tracked-deletes recommended not filed"
```
