```yaml
review:
  scope: "git diff origin/main (a83f7b0f) -- .aai/scripts/mutation-run.mjs .aai/scripts/mutation-gate.mjs .aai/scripts/lib/mutation-record.mjs .aai/scripts/close-work-item.mjs .aai/scripts/spec-lint.mjs .aai/scripts/spec-freeze.mjs tests/skills/lib/close-work-item-pin.sh tests/skills/test-aai-mutation-gate.sh tests/skills/test-aai-close-work-item.sh tests/skills/test-aai-spec-lint.sh tests/skills/test-aai-session-lock.sh tests/skills/test-aai-test-canon.sh docs/specs/SPEC-0181-spec-mutation-gate-for-tests.md CHANGELOG.md (uncommitted tree, worktree fix/p2-mutation-tooling)"
  spec: docs/specs/SPEC-0315-spec-mutation-tooling-p2-fixes.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "mutation-run.mjs:434-452 assertRegularTarget, :1082-1087 source check, :484 clone check; TEST-4110 PASS (outside arm is vacuous, NB-1)" }
      - { ac: Spec-AC-02, call: compliant, citation: "mutation-run.mjs:383 new RegExp(parsed.pattern, parsed.flags); TEST-4111 PASS" }
      - { ac: Spec-AC-03, call: compliant, citation: "test-aai-session-lock.sh:314, test-aai-test-canon.sh:1189; TEST-4112 and TEST-4113 PASS" }
      - { ac: Spec-AC-04, call: compliant, citation: "mutation-run.mjs:1094-1105 read once, :1031-1035 storePatchCopy(bytes); TEST-4114 PASS" }
      - { ac: Spec-AC-05, call: compliant, citation: "mutation-run.mjs:458-467 parseCheck, :507-509 refusal; TEST-4115 PASS" }
      - { ac: Spec-AC-06, call: compliant, citation: "mutation-gate.mjs:328 guard; TEST-4116 PASS" }
      - { ac: Spec-AC-07, call: compliant, citation: "close-work-item.mjs:783-795 isPostMergeClose, mutationGateArgs; TEST-4117 PASS; pin TEST-533 PASS (hash 2307a652...)" }
      - { ac: Spec-AC-08, call: compliant, citation: "mutation-run.mjs:652-670, :680-689; TEST-4118 PASS" }
      - { ac: Spec-AC-09, call: compliant, citation: "lib/mutation-record.mjs:150-158 stampForFileName; TEST-4119 PASS; TEST-474 PASS" }
      - { ac: Spec-AC-10, call: compliant, citation: "spec-lint.mjs:604,622-624; spec-freeze.mjs:93; TEST-4120 PASS; repo-wide spec-lint shows 0 hits of the new rule" }
      - { ac: Spec-AC-11, call: compliant, citation: "mutation-run.mjs checkOne; TEST-4121 PASS (match-count assertion is weak, INFO)" }
      - { ac: Spec-AC-12, call: compliant, citation: "CHANGELOG heading present; SPEC-0181 amendment heading present; spec-amend list --strict rc=0; none of the 12 ids open; TEST-4122 PASS" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/mutation-run.mjs, line: 506,
          issue: "D1's regular-file check runs before git apply but not after it. A --patch that changes the target's type to a symlink (delete 100644 + new 120000 on the same path) passes both foreign-path guards, and lines 505-506 then read and write THROUGH the planted link, outside the clone.",
          failure_scenario: "A patch that replaces lib/greeting.mjs with a symlink to an absolute path outside the repo, run with --target lib/greeting.mjs. Observed: the victim file outside the repo was rewritten (non-UTF-8 bytes ff fe became ef bf bd ef bf bd), and a STAYED GREEN record was written. The closed follow-up fu-mutation-target-symlink-unchecked says to 'resolve it before the write', and that is not done on the patch seam." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-mutation-gate.sh, line: 3311,
          issue: "TEST-4110's outside-the-repo arm cannot fail. The needle 'outside' is also part of the fixture file name outside.txt.",
          failure_scenario: "With assertRegularTarget mutated to return (the spec's own mutation), --target ../outside.txt exits 2 with 'ENOENT ... aai-mutation-XXXX/outside.txt'. rc==2 and 'outside' both still match, so the arm passes on the mutant." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0181-spec-mutation-gate-for-tests.md, line: 2342,
          issue: "The amendment names TEST-474/492/500 as the edited rotated-name expectations. TEST-501's rotated-name expectation was edited the same way (test-aai-mutation-gate.sh:1662) and is not named. The assertion-form rewrites of TEST-509/517/007 are not disclosed either.",
          failure_scenario: "Someone auditing which frozen SPEC-0181 tests changed reads the amendment and misses TEST-501, so the disclosure record is incomplete." }
      - { rank: NON-BLOCKING, file: .aai/scripts/close-work-item.mjs, line: 2019,
          issue: "The remedy suffix is chosen only by whether the close is pre-merge, never by why the gate refused.",
          failure_scenario: "The evidence tree exists, but a row's record has verdict STAYED GREEN. The pre-merge close prints '| remedy: close in the checkout that holds the evidence, or pass --commit <merge sha>', which points the operator at the wrong fix." }
      - { rank: NON-BLOCKING, file: .aai/scripts/close-work-item.mjs, line: 783,
          issue: "isPostMergeClose accepts any --commit that is an ancestor of the upstream default ref. It does not check that this scope's change is merged.",
          failure_scenario: "In the authoring worktree with no evidence tree, an agent gets exit 8, then retries with --commit $(git rev-parse origin/main) as the remedy text suggests. --require-evidence is dropped, the gate DEGRADES to exit 0 and the close stands without evidence. Its only trace is a wrong sha in links.commits." }
  cannot_verify:
    - { claim: "Windows correctness of assertRegularTarget (win32 path.sep split), parseCheck's 'bash' resolution, removeCloneTrackedDelete and the stamped names on NTFS",
        closes_with: "a Windows run of tests/skills/test-aai-mutation-gate.sh TEST-4110/4115/4118/4119. skill-suite.yml's only windows-latest job runs Pester TEST-008, so the spec's 'Hosted ... including the Windows legs' does not exercise item 9" }
    - { claim: "The two live m-flag cells and the 69 g-flag cells replay as the spec states (m now anchors per line; g unchanged)",
        closes_with: "mutation-run.mjs --replay on the specs holding those cells" }
    - { claim: "The full sweep and the pin-consumer suites (hygiene-pack, doc-numbering, follow-ups, doc-number-reservation, repo-tripwire) are green",
        closes_with: "the validator's sweep log; this review ran only the 15 scoped test functions plus TEST-533" }
    - { claim: "Downstream projects that run TDD in one checkout and close in another now get exit 8 under enforce (an intended behaviour change)",
        closes_with: "a downstream close after aai-update; named in the spec's Residual risks" }
    - { claim: "The new suite code runs on Linux CI bash 5 with /usr/bin/grep",
        closes_with: "the hosted skill-suite run on the PR head (this review ran on macOS bash 3.2 only)" }
  overall: fail
```

# Code review: mutation-tooling-p2-fixes

security_relevant: true

- **Scope:** explicit paths (STATE `code_review.scope`), diffed with `git diff origin/main -- <paths>` in `/Users/ales/Projects/aai-worktrees/p2-mutation-tooling` (branch `fix/p2-mutation-tooling`, uncommitted, base a83f7b0f).
- **Spec:** `docs/specs/SPEC-0315-spec-mutation-tooling-p2-fixes.md` (frozen).
- **Reviewer:** dispatched Code Review role, rule 13. `AAI_ROLE=subagent`. No STATE write.

**Coaching record.** The dispatch prompt pre-listed three "known non-blocking" findings (NB-5, NB-r2-1, NB-r2-2) and a "Focus" list. The anti-gaming contract does not allow a dispatcher to characterize expected findings. This is recorded here. I reviewed the full scope anyway and ranked those three findings independently: NB-r2-1 and NB-r2-2 are kept as NON-BLOCKING, and NB-5 is folded into NB-3, which also adds the TEST-501 gap.

## Verdict 1: spec_compliance = pass

Every Spec-AC row is walked in the YAML block above, and every claimed test was run and passed (commands under Evidence).

Deviations from the frozen spec, all minor:
- **D-AMEND disclosure.** It names TEST-474/492/500. TEST-501 was edited the same way and is not named, and the TEST-509/517/007 rewrites are not disclosed either (NB-3).
- **D9 exempt statuses.** D9 says the rule uses "the gate's EXEMPT_STATUSES". `spec-lint.mjs:604` uses a literal copy instead of a shared import. The values are equal today, so this is INFO.
- **Spec-AC Status table.** Every row still reads `planned`. This is expected: SKILL_PR flips the table at close.

## Verdict 2: code_quality = fail (1 BLOCKING)

### BLOCKING-1: a --patch can turn the target into a symlink, and the run writes through it outside the clone

- **Where:** `.aai/scripts/mutation-run.mjs:484-510` (`applyMutation`).
- **The gap:** `assertRegularTarget(cloneDir, targetRel)` runs once, before `git apply`. Neither foreign-path guard looks at file TYPE:
  - `patchPathsPerGit` names only `lib/greeting.mjs`.
  - The tree-hash diff shows only `lib/greeting.mjs` as changed.
- **The failure:** a typechange patch (`deleted file mode 100644` + `new file mode 120000` on the target) passes both guards. Line 505 `fs.readFileSync(targetAbs)` and line 506 `fs.writeFileSync(targetAbs, after)` then follow the planted link to an arbitrary path outside the clone.
- **Observed** (repro below): a victim file outside the repository was rewritten. Its non-UTF-8 bytes `ff fe` came back as `ef bf bd ef bf bd`, and the run wrote a STAYED GREEN record.
- **Why it blocks merge:**
  - This scope closes `fu-mutation-target-symlink-unchecked`. That item's own decision text says "refuse a --target that is not a regular file inside the clone, and resolve it before the write", and its premise "the patch seam is guarded" is false for this shape. Closing it as resolved leaves a false record.
  - The project treats patches as hostile (SPEC-0181 rounds 7/10/11).
- **Remedy:**
  - Call `assertRegularTarget(cloneDir, targetRel)` again right after the `git apply` at line 501, before line 505's read. A throw there is already turned into exit 2 by the normal-run caller and into INCONCLUSIVE by the replay caller.
  - Make `checkOne`'s patch arm refuse the same shape. Today it reports CHECK OK, reading through the link in its scratch dir (read-only).
  - Add a RED-first arm to TEST-4110 or TEST-4121 with a typechange patch, and assert that a victim outside the fixture repo is byte-identical afterwards.
- **backed-by:** repro `/private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/probes/p1-patch-symlink.sh`. It exits 1 on the defect, prints `RESULT: VICTIM OUTSIDE THE CLONE WAS REWRITTEN`, and sources `probes/lib.sh` in the same folder.

Repro core, for when the scratch file is gone:

```bash
# fixture repo with lib/greeting.mjs committed; victim outside the repo with bytes ff fe
git clone -q "$fx" "$gen"; ( cd "$gen" && rm lib/greeting.mjs && ln -s "$victim" lib/greeting.mjs \
  && git add -A && git diff --cached --binary > "$base/sym.patch" )
( cd "$fx" && node .../mutation-run.mjs --spec docs/specs/fixture-spec.md --test-id TEST-9001 \
  --suite tests/skills/fixture-suite.sh --selector test_9001_greet_and_marker \
  --target lib/greeting.mjs --patch "$base/sym.patch" )   # -> exit 5 STAYED GREEN; victim rewritten
```

### NON-BLOCKING

- **NB-1 (test quality, P3): TEST-4110's outside arm is vacuous.**
  - **Where:** `tests/skills/test-aai-mutation-gate.sh:3311`.
  - **Measured:** I ran the spec's own TEST-4110 mutation (`assertRegularTarget` returns at once) on a scratch copy of the scripts (`probes/p3-outside-arm.sh`). The outside arm still exits 2, and its output `ENOENT ... aai-mutation-XXXX/outside.txt` contains the needle `outside`.
  - **Effect:** the TEST-4110 mutation is still killed by the symlink arm, so the gate record stays valid. Only this arm proves nothing.
  - **Disposition:** remediate in tree. Assert `is outside the repository`.
- **NB-2 = validation NB-r2-2 (guard strength, P3): the post-merge predicate accepts any ancestor.**
  - **Where:** `close-work-item.mjs:783`. `isPostMergeClose` accepts any ancestor of origin/main.
  - **Failure:** `--commit <origin/main sha>` in the authoring worktree drops `--require-evidence`, and an absent evidence tree passes again.
  - **Disposition:** promote to a follow-up. Suggested: `fu-postmerge-predicate-any-ancestor`. Remedy direction: require the commit to touch the closed spec's path.
- **NB-3 = validation NB-5, widened (disclosure, P3): the amendment's list of edited tests is incomplete.**
  - **Where:** `SPEC-0181` amendment, around line 2342.
  - **Gap:** TEST-501 is missing from the edited-expectation list. The TEST-509/517/007 assertion rewrites are semantically equivalent but not disclosed.
  - **Disposition:** remediate in tree. Add one sentence to the amendment that names TEST-501 and the three rewrites. The amendment is in scope, and its frozen_sha256 restamp goes through spec-amend.
- **NB-4 = validation NB-r2-1 (message accuracy, P3): the remedy suffix is printed for unrelated refusals.**
  - **Where:** `close-work-item.mjs:2019`.
  - **Effect:** stderr text only; no durable false record.
  - **Disposition:** a follow-up is preferred, because any change to `close-work-item.mjs` forces a pin re-sign. Suggested: `fu-close-remedy-suffix-unconditional`. It can also be folded into BLOCKING-1's remediation round if the pin is re-signed once.

### INFO (does not gate)

- **Shared constant:** `spec-lint.mjs:604` duplicates the gate's `EXEMPT_STATUSES`. Import or export a shared constant.
- **Dotted stamps:** `isRotatedFileName` (`lib/mutation-record.mjs:166`, `[^.]+`) does not match a dotted stamp such as `x-..-..-escape-marker`. It is imported but never called in `mutation-run.mjs`, so it has no effect.
- **TEST-4121 count:** the match-count assertion is the bare needle `"2"`. Assert `matches 2 times`.
- **TEST-4120 comment:** the comment for control D promises a placeholder control that is not asserted.
- **Zero-width pattern:** `--check` counts a zero-width `s/^/x/m` on a one-line file as 2 matches, the second at EOF after the trailing newline. This is correct regex semantics, but it reads as a false AMBIGUOUS.
- **Pre-existing `./` prefix:** a `./`-prefixed `--target` is refused as foreign by the patch guards (run and `--check`), because the string comparison is not normalized.

### Checked and found sound

- **Sed flags:**
  - `gg` gives exit 2 with "Invalid flags".
  - `y` sticky with no match at index 0 gives a byte-identical refusal.
  - `s` dotAll records RED.
  - `d` is refused by the grammar.
- **Patch bytes:** read once, before the clone. Apply uses a per-run copy under `aai-mutation-*/mutation-apply.patch`, and `storePatchCopy` writes the same bytes.
- **parseCheck:** it is asymmetric-safe. It refuses only when before==true and after==false, so a missing checker or an unparseable original never refuses.
- **Tracked-delete removal:**
  - It stays inside the clone: paths come from `git ls-files`, so there is no `..`.
  - It returns on a symlinked or non-directory ancestor, and a leaf symlink is unlinked, never followed.
  - Errors other than ENOENT keep the skip line.
- **stampForFileName:** the output holds only `[A-Za-z0-9._-]`, and the name keeps its `mutation-` prefix, so there is no Windows reserved device name and no traversal.
- **--require-evidence:**
  - Exit 5 per non-exempt row.
  - An all-exempt plan stays at exit 0.
  - The default path is unchanged.
  - The ratchet path still runs.
- **Post-merge callers:** `close-reconcile.mjs:798` passes a main-ancestor delivery sha, so post-merge reconcile behaviour is unchanged. `golden-flow.mjs` closes a `Strategy: loop` spec post-merge, so it is unaffected.
- **Repo-wide spec-lint:** no `mutation-cell-undeclared` hits.
- **Pin:** the hash entry matches the file (TEST-533 PASS).
- **Test hygiene:**
  - New tests use mktemp fixtures registered in `MG_FIXTURE_DIRS`, with HAZ-CD guards.
  - There are no pipes under pipefail in the new assertions.
  - The constructs are bash-3.2-safe.

## cannot_verify

See the YAML block: Windows runtime, replay of existing m/g cells, the full sweep, the downstream close-location change, and Linux CI.

## Warning dispositions (H6)

| Finding | Recommended disposition |
|---|---|
| NB-1 | remediate in tree (same round as BLOCKING-1) |
| NB-2 | follow-up ref, suggested `fu-postmerge-predicate-any-ancestor` (P3) |
| NB-3 | remediate in tree (amendment sentence) |
| NB-4 | follow-up ref, suggested `fu-close-remedy-suffix-unconditional` (P3), or fold in if `close-work-item.mjs` is re-pinned anyway |

The orchestrator records these. The reviewer files none.

## Evidence (commands run)

- **mutation-gate tests:** `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-mutation-gate.sh <fn>` for 4110, 4111, 4112, 4113, 4114, 4115, 4116, 4118, 4119, 4121, 4122 and 474. All rc=0.
- **close-work-item tests:** the same runner on `test-aai-close-work-item.sh` for test_4117 and test_533. Both rc=0.
- **spec-lint test:** the same runner on `test-aai-spec-lint.sh` test_4120. rc=0.
- **Gate on this ride's spec:** `node .aai/scripts/mutation-gate.mjs --spec docs/specs/SPEC-0315-spec-mutation-tooling-p2-fixes.md --require-evidence` printed GATE PASS 13 rows, rc=0.
- **Amendments:** `node .aai/scripts/spec-amend.mjs list --strict` rc=0.
- **Follow-ups:** `follow-ups.mjs list --status open --json` lists none of the 12 ids.
- **Repo-wide lint:** `node .aai/scripts/spec-lint.mjs --json` shows 0 `mutation-cell-undeclared`.
- **Probes** (scratch fixtures only):
  - `probes/p1-patch-symlink.sh`: rc=1, defect reproduced.
  - `probes/p2-misc.sh`: flags and `--check` edges.
  - `probes/p3-outside-arm.sh`: vacuous arm.

## Next steps

1. Remediation round: fix BLOCKING-1 (re-assert after apply, plus the `--check` patch arm) with a RED-first test, then fix NB-1 and NB-3.
2. Run a re-review on the delta.
3. The orchestrator files the NB-2 and NB-4 follow-ups, or folds NB-4 into the round.
