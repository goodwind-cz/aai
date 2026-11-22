# Code review: sync-on-node (L3, one dual-verdict pass)

```yaml
review:
  scope: "git diff 46712c91..b3af756e (feat/sync-on-node; the code_review.scope path list in docs/ai/STATE.yaml, 66 files)"
  spec: docs/specs/SPEC-0310-spec-sync-on-node.md (frozen L3, amendments in docs/ai/decisions.jsonl through run 8 / DR-31)
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "tests/skills/test-aai-sync-node.sh:66-90 safe_rm_own, :162-180 run_sync_scratch; tests/skills/lib/sync-reference.mjs removeOwnScratch; TEST-4000 (node:test re-run here: pass)" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/aai-sync.mjs:28-47 (imports, anchors, one spawnSync, writeFd); TEST-4001 pass" }
      - { ac: Spec-AC-03, call: non-compliant, citation: "B1: aai-sync.mjs:173-176,206-209 - a target that names the source with different letter case on a case-insensitive file system is not refused and a source file is deleted; repro docs/ai/reviews/review-sync-on-node-20261122T175713Z-repro-B1.sh exit 1" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/lib/resolve-base.mjs:21-37; aai-update.mjs, aai-bootstrap.mjs, install-pre-commit-hook.mjs delegate; TEST-4004 pass" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/scripts/lib/gitignore-block.mjs:118-139 reconcile order, :86-114 self-heal exact match + wx temp; TEST-4005 pass (K09j covers DR-12)" }
      - { ac: Spec-AC-06, call: compliant, citation: "aai-sync.mjs holds no legacy move (header :12-20); TEST-4006 pass" }
      - { ac: Spec-AC-07, call: compliant, citation: "aai-sync.mjs:286-322 sticky profile and parseCoreList, :469-479 planPrune Set lookup and empty-set refusal, :537-564 stepCore; TEST-4007 pass" }
      - { ac: Spec-AC-08, call: compliant, citation: "aai-sync.mjs:252-267 underRoot (as the spec defines it: the parent's real path), :381-408 copyTree/copyReplace, :226-247 DR-7/DR-29; TEST-4008 pass. Spec-design gap N1 recorded under code_quality" }
      - { ac: Spec-AC-09, call: compliant, citation: "aai-sync.mjs:596-730 wrapper predicate and skill trees, :732-789 knowledge, seeds, shims; TEST-4009 pass" }
      - { ac: Spec-AC-10, call: compliant, citation: "aai-sync.mjs:829-976 Copilot shim and hooks merge; lib/merge-hooks-json.mjs DR-31 hunk; TEST-4010 pass" }
      - { ac: Spec-AC-11, call: compliant, citation: "aai-sync.mjs:981-1097 one clock read, pin, GIT_SELECTORS scrub, closing lines; TEST-4011 pass (the DR-23 case is vacuous, N2; DR-23 is not in the AC-11 text)" }
      - { ac: Spec-AC-12, call: compliant, citation: "tests/skills/lib/git-env-scrub.sh; TEST-4012 in sweep test-20261122-171344 (validation r2)" }
      - { ac: Spec-AC-13, call: compliant, citation: "TEST-4013 bash corpus pass (node:test re-run here, 165/165)" }
      - { ac: Spec-AC-14, call: compliant, citation: "TEST-4014 PowerShell corpus under pwsh 7 (node:test re-run here: pass); Windows 5.1 is cannot_verify" }
      - { ac: Spec-AC-15, call: compliant, citation: ".aai/scripts/aai-sync.sh equals the D-LAUNCH text, 9 lines, mode 100755; lib/gitignore-block.sh absent; check-vendored-script-deps exit 0 (run here); TEST-4015 in sweep" }
      - { ac: Spec-AC-16, call: compliant, citation: ".aai/scripts/aai-sync.ps1 18 lines, no param block; tests/skills/aai-sync.Tests.ps1 five cases; TEST-4016 in sweep (pwsh 7 only; H1 5.1 cannot_verify)" }
      - { ac: Spec-AC-17, call: compliant, citation: "tests/skills/lib/install-parity.mjs node twin sync argv, syref getter; TEST-4017 in sweep (H2 cannot_verify)" }
      - { ac: Spec-AC-18, call: compliant, citation: "tests/skills/lib/sync-upgrade.test.mjs U0-U4; PROFILES core holds aai-sync.mjs, resolve-base.mjs, gitignore-block.mjs, merge-hooks-json.mjs (.aai/system/PROFILES.yaml:105,203,208,221); TEST-4018 in sweep" }
      - { ac: Spec-AC-19, call: compliant, citation: "suite-map.yaml, suite-weights.tsv, ps1-quality.yml both path lists; TEST-4019 in sweep" }
      - { ac: Spec-AC-20, call: cannot-verify, citation: "row 'implementing': CHANGELOG/README/USER_GUIDE/RFC arms present (TEST-4020 in sweep); product-doc arm deferred by the D-DOCS text to after LOOP COMPLETE" }
      - { ac: Spec-AC-21, call: compliant, citation: "follow-ups.mjs list: 15 closed, 3 filed open; TEST-4021 in sweep (one closure rests on the vacuous DR-23 case, N2)" }
      - { ac: Spec-AC-22, call: compliant, citation: "docs/analysis/node-first-remaining-plan.md section 6; TEST-4022 in sweep; phase 5 stays in progress" }
      - { ac: Spec-AC-23, call: compliant, citation: "docs/ai/docs-audit.yaml:100, .aai/templates/docs-audit.template.yaml:74, WORKFLOW.md:82-83; tests/skills/test-aai-ceremony-levels.sh:726 TEST-4023" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/aai-sync.mjs, line: 173,
          issue: "DR-5 overlap refusal and underRoot's not-under-the-source check compare realpathSync strings; fs.realpathSync keeps the caller's letter case, so on a case-insensitive file system the same directory spelled differently passes both checks",
          failure_scenario: "macOS (APFS default) or Windows (NTFS default): node <src>/.aai/scripts/aai-sync.mjs <src spelled SRC> (or C:\\work\\aai\\.aai\\scripts\\aai-sync.ps1 -TargetRoot c:\\Work\\AAI): not refused; the first copyReplace removes <src>/.aai/AGENTS.md (dst is the same file), copyTree then fails ENOENT, exit 1 with 'internal error'; the source lost a file. backed-by: docs/ai/reviews/review-sync-on-node-20261122T175713Z-repro-B1.sh (exit 1)" }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-sync.mjs, line: 252,
          issue: "underRoot checks only the parent's real path, so a delete or copy-replace of an entry that CONTAINS the source passes; a source inside the target is explicitly allowed (D-ROOTS)",
          failure_scenario: "source vendored at <t>/.aai/upstream: an extended sync's stale clean (:575-583) removes .aai/upstream (the running source), then also .aai/workflow because the source is gone, and the run exits 0. backed-by: docs/ai/reviews/review-sync-on-node-20261122T175713Z-repro-N1.sh (exit 1)" }
      - { rank: NON-BLOCKING, file: tests/skills/lib/aai-sync.test.mjs, line: 2467,
          issue: "TEST-4011 'DR-23 native paths: with platform win32 ...' passes io.platform, which the module never reads (aai-sync.mjs:1171 documents it); on POSIX the case asserts POSIX paths and passes for any implementation, and fu-parity-win-source-path was closed on this source",
          failure_scenario: "a change that writes Git-Bash style /c/... paths on win32 still passes TEST-4011 on every POSIX host; only hosted H2 would see it, and the ledger already reads the follow-up as test-backed" }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-sync.ps1, line: 14,
          issue: "Windows PowerShell 5.1 passes native arguments with its legacy quoting: a quoted argument ending in a backslash, an embedded double quote and an empty string do not reach node unchanged (the old .ps1 bound -TargetRoot natively)",
          failure_scenario: "PS 5.1: .\\.aai\\scripts\\aai-sync.ps1 -TargetRoot 'C:\\My Projects\\app\\' reaches node as 'C:\\My Projects\\app\"' and exits 1 'Target directory does not exist'; fails closed, nothing written. Not reproduced here (no 5.1 host); unbacked, so NON-BLOCKING" }
      - { rank: NON-BLOCKING, file: CHANGELOG.md, line: 33,
          issue: "the release note does not say that the seeded docs-audit template now lists .aai/scripts/lib/guard-config.mjs under protected_paths_l3 (Spec-AC-23), nor that existing projects add it by hand (the PR #580 entry's precedent)",
          failure_scenario: "an existing consumer updates; its project-owned docs/ai/docs-audit.yaml is not rewritten, so a guard-config change in that project is not FULL_RUN protected-l3, and nothing in the release notes tells the owner to add the row" }
      - { rank: NON-BLOCKING, file: tests/skills/lib/sync-reference.mjs, line: 85,
          issue: "removeOwnScratch removes the ownership marker as part of one recursive rm; an interrupted removal leaves an unmarked tree that no helper will ever remove (by design they refuse unmarked trees)",
          failure_scenario: "observed: ${TMPDIR}/aai-sy-corpus-kr1-X7WG52 (13:30Z, 5883 entries, tree-ref and tree-mod, no .aai-sy-owned) left by an earlier run; every killed or timed-out corpus case can add another" }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/merge-hooks-json.mjs, line: 170,
          issue: "DR-31 writeAtomic unlinks a pre-existing entry at .<name>.<pid>.tmp, a file the run did not create; Spec-AC-08 and the D-COPY N1 rule say a temp the run did not create is never deleted, DR-31 prescribes the removal",
          failure_scenario: "a regular file at hooks/.hooks.json.<pid>.tmp in the target (an earlier run's leftover with the same pid) is removed; the pre-DR-31 code overwrote it" }
  cannot_verify:
    - { claim: "the .ps1 launcher under Windows PowerShell 5.1 (List[string] splatting to a native command, -File argument passing, stderr under a redirected host)", closes_with: "ps1-quality windows-5_1 job running aai-sync.Tests.ps1 and the 5.1 smoke (H1, H3)" }
    - { claim: "B1 on NTFS (expected to bite the same way: Node's JS realpathSync keeps the typed case on win32)", closes_with: "the B1 repro or a fixed case-variant test on the windows job" }
    - { claim: "Windows-native DRs DR-11, DR-20, DR-21, DR-23 and the parity third twin on Windows", closes_with: "windows-parity / windows-5_1 / windows-wsl1 runs of the PR (H2)" }
    - { claim: "Linux CI (Node 22) for the corpora and the upgrade proof", closes_with: "the PR's Linux gate run" }
    - { claim: "an update of a real released install (v2026.11.13 tag) over the network path of /aai-update", closes_with: "U1 runs from a local git archive of 077ee649; a hosted /aai-update from the release tag would close it" }
  overall: fail
```

security_relevant: true

## Scope and inputs

- Worktree /Users/ales/Projects/aai-worktrees/sync-on-node, branch feat/sync-on-node, HEAD b3af756e, base 46712c91 (origin/main merged in). `git status`: only docs/ai/EVENTS.jsonl modified (pre-existing, not this review).
- Spec read in full (Decisions, D-DRIFT DR-1 to DR-31, D-UPGRADE, D-SAFETY, AC table); validation reports round 1 and round 2 (PASS) read; the decisions ledger records of the ride listed.
- Read in full: aai-sync.mjs, lib/gitignore-block.mjs, lib/resolve-base.mjs, both launchers, the merge-hooks-json, update, bootstrap and hook-installer hunks, PROFILES/RUNTIME_IGNORE/docs-audit/WORKFLOW hunks, CHANGELOG/README/USER_GUIDE hunks, the helper and safety sections of test-aai-sync-node.sh, aai-sync.test.mjs, sync-upgrade.test.mjs, sync-reference.mjs, git-env-scrub.sh, aai-sync.Tests.ps1, the install-parity.mjs hunk, the ps1-quality and weights hunks.
- Run here (scratch only, no full sweep): `node --test resolve-base.test.mjs aai-sync.test.mjs` 165 pass, 0 fail, 127 s; `check-vendored-script-deps.mjs` exit 0; the B1 and N1 repros (both exit 1 = defect present; both clean up their own mktemp directory, confirmed).

## Dispatch note (anti-gaming contract)

The dispatch named focus areas and asked not to flag two items (the product doc and a DR-31 CHANGELOG mention). Recorded as a scope hint; the full scope was reviewed anyway. Both items were checked independently: the product doc is deferred by the spec's own D-DOCS text (AC-20 is `implementing`, called cannot-verify here), and the missing DR-31 mention is validation round 2's NB-r2-1, not re-filed here.

## BLOCKING

### B1. The DR-5 refusal and the path guard are defeated by letter case (aai-sync.mjs:173-176, 206-209, 266)

`isUnderOrSame` is a string prefix test over `fs.realpathSync` results. `fs.realpathSync` resolves links but keeps the case the caller typed (measured on this host: `realpathSync('.../ABC')` returns `.../ABC`, `realpathSync.native` returns `.../Abc`). The macOS and Windows default file systems are case-insensitive, so one directory has many spellings.

Failing scenario (repro `review-sync-on-node-20261122T175713Z-repro-B1.sh`, exit 1): a scratch layer at `<w>/Src`, then `node <w>/Src/.aai/scripts/aai-sync.mjs <w>/SRC`. The exact spelling is refused (`ERROR: target ... is the source ...; nothing was written.`). The case variant is not refused. The extended copy runs `copyReplace(<src>/.aai/AGENTS.md, <target>/.aai/AGENTS.md)` on what is one file: `rmSync` deletes it and `copyTree` fails with ENOENT. The run exits 1 with `aai-sync: internal error`, and the source lost `.aai/AGENTS.md` (322 files, then 321). On Windows the same input is `C:\work\aai\.aai\scripts\aai-sync.ps1 -TargetRoot c:\Work\AAI`, which Windows users type routinely.

This breaks Spec-AC-03 ("a target equal to or inside the source ... refused with exit 1 before any file in the target or the source changes"), DR-5's stated reason ("a sync must never damage its source"), and the CHANGELOG and USER_GUIDE sentences that promise the refusal. The old twins had no refusal at all, so this is not a regression against them. It is a hole in a new guarantee the ride ships and documents, on the primary development platform.

Fix direction (not applied, read-only review): compare identity, not spelling. Options: `fs.realpathSync.native` for `srcReal`, `targetReal` and inside `underRoot` (canonical case on darwin and win32), or walk the ancestors of the target's real path comparing `(dev, ino)` with the source root's stat. Then add a case-variant K case (skipped with a named reason on a case-sensitive file system) and run the repro.

## NON-BLOCKING (each with its recommended disposition; the orchestrator records it)

- N1 (P2). underRoot guards only the parent (aai-sync.mjs:252-267, as D-ROOTS defines it). A source inside the target is allowed, but when it lies inside a managed entry the run deletes or replaces, the run removes its own source. Repro `...-repro-N1.sh` (exit 1): source at `<t>/.aai/upstream`. The extended stale clean removes `.aai/upstream`, and then `.aai/workflow` because the source is now gone. The run exits 0. The core prune is safe here: the guard refuses, exit 1. `.codex/skills` and `.gemini/skills` are replaced wholesale and have the same shape. Recommended: remediate in tree together with B1, since it is the same function. Refuse in `resolveRoots` when `srcReal` lies under a managed entry, or refuse in `mustGuard` when the guarded entry contains the source. Record a spec amendment, because the D-ROOTS text defines underRoot as parent-only. Otherwise (b) a P2 follow-up.
- N2 (P3). The DR-23 case is vacuous: `run()` documents an injectable `platform` (aai-sync.mjs:1171) that nothing reads. TEST-4011 "with platform win32" (aai-sync.test.mjs:2467) passes for any implementation on POSIX, and `fu-parity-win-source-path` was closed on it. This leaves a record that is weaker than it reads, so disposition (d) does not apply. Recommended: (a) rename the case to what it checks, drop or honour the seam, and cite H2 as the closing evidence, or (b) a follow-up.
- N3 (P3). Windows PowerShell 5.1 legacy native-argument quoting at aai-sync.ps1:14. A quoted path ending in `\`, an embedded `"`, and an empty argument do not reach node unchanged. For example, `-TargetRoot 'C:\My Projects\app\'` reaches node as `C:\My Projects\app"`, exits 1 and writes nothing. The old .ps1 bound the parameter natively. Not reproduced here. Recommended: (b) a P3 follow-up, either to normalise in the launcher without policy (for example, strip one trailing backslash from each element) or to document it, with a 5.1 Pester case.
- N4 (P3). The CHANGELOG does not mention the guard-config `protected_paths_l3` addition or the manual step for existing projects. Recommended: (a) remediate in the post-review CHANGELOG step, together with the DR-31 sentence that NB-r2-1 already owes.
- N5 (P3). Observed bite: an unmarked scratch leftover, `${TMPDIR}/aai-sy-corpus-kr1-X7WG52` from 13:30Z. `removeOwnScratch` deletes the marker inside one recursive rm, so an interrupted removal can never be cleaned by the helpers. The review did not touch it; the owner may remove it by hand. Recommended: (b) a P3 follow-up: remove the children first and the marker last.
- N6 (P3). `writeAtomic` (merge-hooks-json.mjs:170) unlinks a pre-existing entry at its pid-named temp. DR-31 says to remove it, while Spec-AC-08 and D-COPY say never to delete a temp the run did not create. accepted residual: the temp name carries the run's own pid inside the target's hooks/ directory, the pre-DR-31 code overwrote the same entry, nothing outside the target is touched, and the two spec sentences should be reconciled in the next amendment the orchestrator writes.

## Deviations from the frozen spec (listed even where reasonable)

1. D-COPY names "temp files (the self-heal, the advisory, the pin)". The module writes the advisory and the pin in place through `writeManaged` (unlink a link, then writeFileSync), as the bash twin did with `cat >`. Only the self-heal uses an exclusive temp.
2. Ceremony and D-WIRE still say that docs/ai/docs-audit.yaml and WORKFLOW.md are not touched. Spec-AC-23 (an owner scope addition, amendment recorded) touches both. The amendment discloses this, but the older sentences remain in the text.
3. D-MODULE lists `platform` among the injectable `io` fields, but it has no effect (N2).
4. underRoot is implemented exactly as specified (parent only). The gap is in the spec design (N1).
5. Spec-AC-20's product-doc arm is deferred by the D-DOCS text (the row stays `implementing`).

## INFO

- The weights fallback 196 for aai-sync-node is set by the spec. The suite took 493 s in the round-2 sweep, so the scheduler will under-weight it until a sample is recorded.
- Test safety is otherwise sound: every sync invocation goes through `run_sync_scratch` / `runSync` / `runInProcess` / `run()` with `GIT_*` and `AAI_*` scrubbed and the target asserted under an own marked root. The EXIT trap and the `after()` hooks clean up. No docker, pkill or killall. The upgrade proof reads this checkout only through `git ls-files` and `git archive`.
- PROFILES core holds the module and every lib that it and the three switched modules import (including merge-hooks-json.mjs and guard-config.mjs), so an old core target gets working launchers on its first update. U1 proves this, and `check-vendored-script-deps` exits 0.

## Next steps

Remediation for B1, with N1 in the same function, RED first through the two repros (each exits 0 once fixed), plus a case-variant corpus or TEST-4003 case. Then a re-review of the delta. Record a disposition for each of N1 to N6 before closeout.
