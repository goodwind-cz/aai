# Code review round 2: sync-on-node (L3, one dual-verdict pass)

```yaml
review:
  scope: "git diff 46712c91..a2e8609d (feat/sync-on-node; the code_review.scope path list in docs/ai/STATE.yaml, 70 files)"
  spec: docs/specs/SPEC-0310-spec-sync-on-node.md (frozen L3; amendments through run 9 / DR-32, DR-33 in docs/ai/decisions.jsonl)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "tests/skills/lib/sync-reference.mjs:74-91 removeOwnScratch (children first, marker last since 0d74d6c4); TEST-4000 incl. the new marker-last case (node:test re-run here: pass)" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/aai-sync.mjs:28-35 imports; check-vendored-script-deps exit 0 (run here); TEST-4001 pass" }
      - { ac: Spec-AC-03, call: compliant, citation: "aai-sync.mjs:46-57 ancestorIsFile/targetInSource, :177-183 and :219 realpathSync.native, :221-231 refusals, :242-251 DR-33; TEST-4003 DR-32 case ran (not skipped) on APFS and DR-33 case pass; round-1 repro B1 now exits 0 (refused, source 322 -> 322 files)" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/lib/resolve-base.mjs:21-37; TEST-4004 pass" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/scripts/lib/gitignore-block.mjs:118-158; TEST-4005 pass" }
      - { ac: Spec-AC-06, call: compliant, citation: "aai-sync.mjs header :12-20, no legacy move; TEST-4006 pass" }
      - { ac: Spec-AC-07, call: compliant, citation: "aai-sync.mjs:315-351, :498-508 planPrune empty-set refusal, :566-593 stepCore; TEST-4007 pass" }
      - { ac: Spec-AC-08, call: compliant, citation: "aai-sync.mjs:281-296 underRoot (now also an identity walk), :410-437 copyTree/copyReplace, :595-618; TEST-4008 pass; round-1 repro N1 exits 0 (refused up front by DR-33)" }
      - { ac: Spec-AC-09, call: compliant, citation: "aai-sync.mjs:620-832; TEST-4009 pass" }
      - { ac: Spec-AC-10, call: compliant, citation: "aai-sync.mjs:850-1005; lib/merge-hooks-json.mjs DR-31 hunk; TEST-4010 pass" }
      - { ac: Spec-AC-11, call: compliant, citation: "aai-sync.mjs:1010-1126; TEST-4011 pass; the DR-23 case is renamed to what it checks on POSIX (aai-sync.test.mjs:2522) and the Windows form is hosted H2 (fu-parity-win-source-path reopened)" }
      - { ac: Spec-AC-12, call: compliant, citation: "tests/skills/lib/git-env-scrub.sh; TEST-4012 in validation r3 sweep" }
      - { ac: Spec-AC-13, call: compliant, citation: "TEST-4013 bash corpus (node:test re-run here, 168/168 with resolve-base)" }
      - { ac: Spec-AC-14, call: compliant, citation: "TEST-4014 PowerShell corpus under pwsh 7 (re-run here: pass); Windows PowerShell 5.1 is cannot_verify" }
      - { ac: Spec-AC-15, call: compliant, citation: ".aai/scripts/aai-sync.sh 9 lines, the D-LAUNCH text; no lib/gitignore-block.sh left in .aai; TEST-4015 in validation r3 sweep" }
      - { ac: Spec-AC-16, call: compliant, citation: ".aai/scripts/aai-sync.ps1 18 lines, no param block; TEST-4016 in sweep (pwsh 7 only)" }
      - { ac: Spec-AC-17, call: compliant, citation: "tests/skills/lib/install-parity.mjs third twin; TEST-4017 in sweep (Windows legs H2 cannot_verify)" }
      - { ac: Spec-AC-18, call: compliant, citation: "sync-upgrade.test.mjs U0-U4; PROFILES.yaml core :105 aai-sync.mjs, :203 gitignore-block.mjs, :208 merge-hooks-json.mjs, :221 resolve-base.mjs; no updater (old bash/ps1 at bf0148d6^ or the module) sources lib/gitignore-block.sh; TEST-4018 in sweep" }
      - { ac: Spec-AC-19, call: compliant, citation: "suite-map.yaml, suite-weights.tsv, ps1-quality.yml; TEST-4019 in sweep" }
      - { ac: Spec-AC-20, call: cannot-verify, citation: "row stays implementing: CHANGELOG/README/USER_GUIDE/RFC arms present (TEST-4020); product-doc arm and the DR-31/32/33 + guard-config CHANGELOG sentences deferred by D-DOCS to after LOOP COMPLETE" }
      - { ac: Spec-AC-21, call: compliant, citation: "follow-ups.mjs list: 14 closed, fu-parity-win-source-path open again, 3 filed open; tests/skills/test-aai-sync-docs.sh:175-232 TEST-4021" }
      - { ac: Spec-AC-22, call: compliant, citation: "docs/analysis/node-first-remaining-plan.md section 6; TEST-4022 in sweep" }
      - { ac: Spec-AC-23, call: compliant, citation: "docs/ai/docs-audit.yaml, .aai/templates/docs-audit.template.yaml, WORKFLOW.md; TEST-4023" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-sync.mjs, line: 191,
          issue: "the DR-32 identity walk (ancestorIsFile, :46-55, used at :57, :246, :295) compares Number dev/ino from fs.statSync; on Windows Node's Number ino loses precision above 2^53 (NTFS file references carry the sequence number in the high 16 bits), and some volumes report ino 0 or non-unique ids, so two different directories can compare equal",
          failure_scenario: "Windows: the source root and an ancestor of the target (or a new subdirectory under the target) on one volume share a sequence number and fall in one 2^11-wide rounding bucket, or the volume reports ino 0 for both (some network or virtual drives): resolveRoots refuses with 'target ... is the source ... or lies inside it' although the paths are unrelated, or underRoot refuses a mutation mid-run (exit 1, the target partly synced). Fails closed, nothing outside the target is touched. Not reproduced (no Windows host), so NON-BLOCKING" }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-sync.mjs, line: 219,
          issue: "fs.realpathSync.native(src) and (target) are not guarded; where GetFinalPathNameByHandle fails (a volume without a DOS name, some RAM-disk or virtual drive drivers) the JS realpathSync used before worked and the native call throws",
          failure_scenario: "Windows, source or target on such a volume: the run prints 'aai-sync: internal error: <code>, realpath ...' and exits 1 before any write; before the remediation the same sync ran. Fails closed. Not reproduced, so NON-BLOCKING" }
  cannot_verify:
    - { claim: "realpathSync.native on Windows yields one spelling for drive-letter case, 8.3 short names, subst drives (resolved to the backing drive), mapped drives and UNC (\\\\server\\share) and junctions, so DR-32 holds there (read from libuv's GetFinalPathNameByHandleW path, not run)", closes_with: "a case-variant and a subst/junction TEST-4003 case on the windows-parity job" }
    - { claim: "the Windows ino behaviour behind the first NON-BLOCKING finding (precision, ino 0 volumes, ReFS Dev Drive ids)", closes_with: "a Windows run of TEST-4003 plus a probe on a ReFS Dev Drive, or the bigint stat change" }
    - { claim: "the .ps1 launcher under Windows PowerShell 5.1 (List[string] splatting, -File argument passing, stderr under a redirected host)", closes_with: "ps1-quality windows-5_1 job running aai-sync.Tests.ps1 (H1, H3)" }
    - { claim: "Windows-native DRs DR-11, DR-20, DR-21, DR-23 and the parity third twin on Windows", closes_with: "windows-parity / windows-5_1 / windows-wsl1 runs of the PR (H2)" }
    - { claim: "Linux CI (Node 22) for the corpora and the upgrade proof", closes_with: "the PR's Linux gate run" }
    - { claim: "an update of a real released install over the network path of /aai-update", closes_with: "U1 runs from a local git archive; a hosted /aai-update from the release tag would close it" }
  overall: pass
```

security_relevant: true

## Scope and inputs

- Worktree /Users/ales/Projects/aai-worktrees/sync-on-node, branch feat/sync-on-node, HEAD a2e8609d, base 46712c91. `git status`: only docs/ai/EVENTS.jsonl modified (pre-existing, not this review). `git ls-files -ci --exclude-standard`: empty.
- Read: the round-1 report and both repros, the remediation commits 0d74d6c4 and 51b52166, aai-sync.mjs in full at HEAD, lib/gitignore-block.mjs, lib/resolve-base.mjs, both launchers, the merge-hooks-json, PROFILES and RUNTIME_IGNORE hunks, the D-ROOTS and D-DRIFT sections including the run 9 amendment, the AC table, the validation r3/r3b notes and the follow-up records of the ref.
- Run here (scratch only, no full sweep, every probe under an own mktemp directory removed on exit):
  - `env -u AAI_ROLE node --test tests/skills/lib/resolve-base.test.mjs tests/skills/lib/aai-sync.test.mjs`: 168 pass, 0 fail, 0 skipped, 132 s. The DR-32 case ran on APFS and was not skipped.
  - Round-1 repro B1: exit 0. The case variant is refused, and the source holds 322 files before and after.
  - Round-1 repro N1: exit 0. The source inside `<t>/.aai/upstream` is refused and survives.
  - check-vendored-script-deps exit 0; `spec-amend list --strict` exit 0; `spec-lint --path <spec>` LINT PASS.
  - Probes `scratchpad/cr-r2/probes.sh` against a `git archive` of HEAD:
    - P1: a case-variant spelling of a legitimate target syncs, exit 0.
    - P3: a source at `<t>/.claude/worktrees/x` is refused (the filed overbreadth).
    - P4: a source vendored at `<t>/vendor/aai` syncs, exit 0, and the source stays intact.
    - P5: a symlinked alias of the source is refused.
    - P6: a case-variant subdirectory of the source is refused.
- Legitimate layouts checked against the new refusals:
  - aai-update (module and the pre-ride bash and ps1 updaters at bf0148d6^) clones into a fresh directory under the system temp. That is never inside a managed target entry, so neither DR-5 nor DR-33 fires.
  - golden-flow refuses an `--out` inside the checkout.
  - The test runner's disposable checkout and its TMPDIR are separate trees.
  - aai-worktree does not run the sync.
  - Parity and the upgrade proof U0-U4 are green in the validation r3 sweep.

## Dispatch note (anti-gaming contract)

The dispatch named focus areas. It asked not to flag the deferred product doc and the CHANGELOG mentions of DR-31/32/33 and the guard-config step. It also restated the budget, which puts pressure on severity: "a BLOCKING must be a real defect with a repro". This is recorded as a scope and severity hint. The full scope was reviewed anyway, and ranks follow this prompt's own rules (BLOCKING needs a failing check or a repro). The deferred items were checked on their own: the D-DOCS text defers them to after LOOP COMPLETE. Spec-AC-20 stays `implementing` and is called cannot-verify here, and the CHANGELOG gap is validation's NB-r3-3 (round-1 N4). Neither is filed again.

## BLOCKING

None. B1 from round 1 is fixed. The roots are canonical (`realpathSync.native`) and the overlap is also decided by device and inode up the ancestors. The repro exits 0, and TEST-4003 DR-32 ran and passed on a case-insensitive file system. Each mechanism alone would refuse the round-1 input on macOS, so the fix does not hinge on one of them.

## NON-BLOCKING (each with its recommended disposition; the orchestrator records it)

- R2-N1 (P3, new): Windows identity by Number ino (aai-sync.mjs:191, used through `ancestorIsFile` at :57, :246 and :295).
  - Before the remediation, a false "same file" answer from `sameFile` only weakened a check (sourceRoot, reverifyTarget). The DR-32/DR-33 walk now turns it into a refusal.
  - Node documents that a Number `ino` on Windows is not guaranteed unique. A 64-bit NTFS file reference with a sequence number of 32 or more exceeds 2^53 and is rounded. Some volumes report 0.
  - Failure: a false refusal before any write, or, very rarely, a mid-run refusal after a partial sync. It fails closed.
  - Recommended: (b) a P3 follow-up `fu-sync-win-ino-identity-precision`. Read the identity stats with `fs.statSync(p, { bigint: true })`, treat `ino === 0n` as unknown (then fall back to the canonical string comparison only), and add a windows-parity TEST-4003 case.
- R2-N2 (P3, new): unguarded `fs.realpathSync.native` in resolveRoots (aai-sync.mjs:219).
  - On a Windows volume where the native call fails but the JS realpath worked, the sync now exits 1 with `internal error` before any write. It fails closed and is not reproduced.
  - Recommended: fold it into the same follow-up as R2-N1. Fall back to `fs.realpathSync` and keep the dev/ino walk, which needs no spelling, or refuse with a named line instead of `internal error`.
- Carried, already recorded, no new action:
  - fu-sync-dr33-overbroad-managed-refusal. Confirmed by probe P3: `<t>/.claude/worktrees/x` is refused, and the line says "which the sync replaces" although `.claude` is never replaced wholesale. P3 stays right, since it fails closed and no shipped flow places a source there.
  - fu-sync-dr33-test-non-aai-entries. The DR-33 case covers only `.aai`, and the underRoot identity clause is still unexercised.
  - fu-sync-ps1-51-native-arg-quoting (round-1 N3).
  - Round-1 N4: the post-LOOP-COMPLETE CHANGELOG step, with NB-r3-3.
  - Round-1 N6: accepted residual. The temp name carries the run's own pid inside the target's `hooks/`. The run 9 amendment (c) reconciles Spec-AC-08 and D-COPY with DR-31, and nothing outside the target is touched.
- Remediated since round 1:
  - B1: commit 0d74d6c4, repro exit 0, TEST-4003 DR-32.
  - N1: commit 0d74d6c4, repro exit 0, TEST-4003 DR-33.
  - N2: the case was renamed, the `platform` seam was dropped from the D-MODULE list, and fu-parity-win-source-path was reopened. TEST-4021 asserts it is open.
  - N5: children first and the marker last, with the TEST-4000 case. The pre-existing unmarked leftover `${TMPDIR}/aai-sy-corpus-kr1-X7WG52` from 13:30Z is still there; it predates the fix, and the owner may remove it by hand.

## Regression check of the remediation

- read-trace.cjs (51b52166) keeps `realpathSync.native` as a traced property of the wrapper. Without it, every suite that syncs under the admission preload crashed with "is not a function". Correct, and limited to the test preload.
- The main guard (aai-sync.mjs:1221) now reads both sides through `realpathSync.native`. The two sides name the same file, so the readings agree. A fallback on both sides gives the same `path.resolve` strings as before.
- underRoot now walks the ancestors of every mutation's parent, which adds about ten stats per guarded mutation. With hundreds of mutations per sync the cost is negligible.
- Logical paths (`roots.target`, `roots.src`) are still used only for messages, the scrub and the joins. Every containment comparison is between two native real paths, or by identity. A case-variant or subst-drive target therefore stays consistent (probe P1).
- A dangling managed top-level link inside a case-variant target is now refused by DR-7, because the fallback reads the link text against the logical spelling. With the exact spelling, the same tree fails with `internal error` at the up-front `mkdir` (pre-existing twin class: `mkdir -p` on a dangling link). The case-variant path fails earlier and cleaner. No finding.

## Deviations from the frozen spec

The run 9 amendment discloses all of the round-1 deviations, and D-COPY, Ceremony, D-WIRE, D-MODULE and Spec-AC-08 now read with that amendment. Remaining:

1. The DR-33 refusal set is MANAGED_TOP minus `docs`, `docs/ai` and `.gitignore`. That is broader than "a managed entry the run deletes or replaces" in the DR-33 row (fu-sync-dr33-overbroad-managed-refusal).
2. Spec-AC-20's product-doc arm is deferred by D-DOCS.

## INFO

- Commit 0d74d6c4 carries `Co-Authored-By: Claude Sonnet 5.5`, where the ride rules prescribe the Opus line exactly. It is accurate if that run was on Sonnet. The squash message at merge decides what lands.
- The weights fallback 196 for aai-sync-node is still below the measured ~490 s (round-1 INFO).
- Test safety still holds. The new DR-32, DR-33 and marker-last cases run inside `scratch()` roots with the `after()` cleanup, and the chmod is restored in `finally`. The runs here left nothing in TMPDIR (only the 13:30Z leftover noted above).

## Next steps

None block this ride. Record R2-N1 and R2-N2 as one P3 follow-up, or as two. The deferred docs step (product doc, CHANGELOG DR-31/32/33 and the guard-config manual step) follows LOOP COMPLETE as planned.
