```yaml
review:
  scope: "uncommitted candidate vs origin/main (HEAD = base 3e6b52d58cb19b1d463e39354ce49809a5fc7c93); paths: tests/skills/aai-win-dispatch.Tests.ps1, tests/skills/aai-update.Tests.ps1, docs/specs/SPEC-0280-spec-release-corpus-hermetic.md (untracked), docs/issues/ISSUE-0111-release-corpus-hermetic.md (untracked), docs/specs/SPEC-0257-spec-release-passes-first-time.md, docs/ai/decisions.jsonl, docs/ai/EVENTS.jsonl, docs/ai/tests/test-runs.jsonl"
  spec: docs/specs/SPEC-0280-spec-release-corpus-hermetic.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "tests/skills/aai-win-dispatch.Tests.ps1:103-109 (TEST-001 CLEAR/RESTORE), :932-938 (TEST-013), :1440-1451 (TEST-002 caller-preservation); reviewer re-run in scratch clone: inherited 4500 PRE=POST=4500, absent PRE=POST=absent, 0 failed; expected values unchanged (:111, :941)" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "docs/ai/reports/release-corpus-hermetic-corpus-decision.txt (every predicate PASS, assert_rc=0; 58/58, peak 4, 1800/3600, sourcePreserved, treeSha256 binding, hostedTiming unverified); measured in VALIDATION-20261107T2359Z, carried by VALIDATION-20261108T0044Z sec. 2" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "SPEC-0257 Spec-AC-05 row: reviewer node cell compare vs origin/main -> cells 3-6 (Status/Evidence/Review-By/Notes) changed, Description (cell 2) byte-identical; one measurement paragraph outside the table; one spec_amendment class measurement signoff false for SPEC-0257 (decisions.jsonl 2026-11-08T00:39:45Z); spec-amend list --strict rc 0 (reviewer)" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "tests/skills/aai-update.Tests.ps1:75-119; reviewer re-run in scratch clone with local-path origin: 10/10 incl. guard + control; git diff origin/main -- .aai empty (aai-update.ps1 byte-identical)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0280-spec-release-corpus-hermetic.md, line: 213,
          issue: "The scope's own AC Status table still shows Spec-AC-02 and Spec-AC-03 as planned with evidence '—' although both are met and SPEC-0257 already records the closure",
          failure_scenario: "If the close ceremony is skipped or run by a path that only flips frontmatter, the committed spec reads 'planned' for two satisfied ACs while SPEC-0257 cites this ride as having closed Spec-AC-05; docs-audit --gate for this spec already exits 1 on exactly these two rows (validator sec. 4)" }
  cannot_verify:
    - { claim: "The rewritten aai-update guard Context and the win-dispatch hermetic clears pass on the Windows PowerShell 5.1 and Windows pwsh legs of ps1-quality.yml",
        closes_with: "current-head CI conclusion of the Windows ps1-quality jobs with headSha == PR head" }
    - { claim: "The release reader and complete corpus fit the shipped CI defaults 540/1080 and hosted timing",
        closes_with: "current-head Linux CI skill-suite release dry-run observation on the PR (local test-aai-release.sh took 708.9 s > 540 s per validator)" }
    - { claim: "The committed tree equals the measured/validated candidate (corpus attests treeSha 3fab39e1..., later delta docs+ledgers only)",
        closes_with: "post-commit manifest recompute equal to the final pre-commit manifest, per spec Verification step 4" }
    - { claim: "Corpus measurement itself (58/58) — reviewer read the report and decision assertion but did not re-execute the corpus",
        closes_with: "the carried corpus.json / corpus.log (gitignored) as cited; re-execution not warranted absent new reason" }
  overall: pass
```

security_relevant: false

# Code review — release-corpus-hermetic

- Reviewer: claude-opus-5-5, fresh independent context (dispatched, `AAI_ROLE=subagent`).
- Scope: the uncommitted candidate in /private/tmp/aai-release-corpus-hermetic against origin/main. HEAD equals the base 3e6b52d5. Scope was established from `git status --porcelain`: 6 modified paths and 2 untracked paths, all inside the dispatch path list. Nothing outside the scope is dirty.
- Spec: docs/specs/SPEC-0280-spec-release-corpus-hermetic.md (frozen, Amendments 1-6). Intake: docs/issues/ISSUE-0111-release-corpus-hermetic.md.
- Coaching check: the dispatch named paths, the base, and the evidence. It did not pre-rate findings or exclude any area. No coaching attempt to record.

## Independent checks run by this reviewer

These were run in the scratch clone /private/tmp/release-corpus-hermetic-review-scratch, at base HEAD with the two candidate Pester files copied in. Its origin is a local path, so it is not canonical. Nothing was written to W except this report.

| Check | Result |
|---|---|
| Both Pester files run directly through pwsh with AAI_TEST_TIMEOUT=4500 inherited | 122 passed, 0 failed. PRE=POST=4500. The run printed `AAI-TIMEOUT: 4500s (source=env)` for the non-default contexts only. |
| The same run with AAI_TEST_TIMEOUT absent | 122 passed, 0 failed. PRE=POST=absent. |
| Ledger base prefix (EVENTS, decisions, test-runs) | All three files carry origin/main as a byte-exact prefix. |
| SPEC-0257 Spec-AC-05 node cell compare | Only cells 3-6 changed. Description is byte-identical. |
| `spec-amend list --strict` | rc 0 |
| `git diff --quiet origin/main -- .aai .github tests/skills/*.sh tests/skills/lib` | rc 0 (no diff) |
| `git init -q` hint with no global config (git 2.54) | Silent, so it adds no stderr noise to the fixture. |
| aai-update.ps1 `-DryRun` with a slug `-Repo` | Exits before any clone (aai-update.ps1:79 and :118-126). The control case takes no network path. |
| Updater target resolution | `$Target = (Get-Location).Path` (:47). Start-Process inherits the Push-Location location, so the test drives the real guard comparison at :58-59 against its own target. |

I did not re-execute the corpus. The decision-assertion output and the final validation report were read. They are carried, as the dispatch allowed.

## AC walk

- **Spec-AC-01: compliant.**
  - Both default-timeout contexts clear `AAI_TEST_TIMEOUT` with a tagged statement and restore it in `finally` using the two-state idiom. The `Should` expectations are unchanged.
  - TEST-002 captures the caller value in the file-level BeforeAll and asserts it in the last Describe, for both the present and the absent state.
  - RED, GREEN and the manual mutation records are cited in the spec and in the validator's reports. My own re-run is above.
- **Spec-AC-02: compliant.**
  - The decision file holds every predicate in the AC, each marked PASS. That includes the 1800/3600 bounds, `results.length == 2 × 29`, sourcePreserved, the treeSha256 binding to W, and hostedTiming unverified.
  - The CI-default and hosted claims are explicitly disclaimed.
- **Spec-AC-03: compliant.**
  - The conditional held, because AC-02 passed. Only the permitted cells changed, plus the Amendment-5-permitted paragraph outside the table and the spec-amend frozen_sha256 re-stamp.
  - There is exactly one measurement amendment for SPEC-0257, `spec-amend list --strict` returns rc 0, and Review-By is `—`. That is a closure, not a date extension.
- **Spec-AC-04: compliant.**
  - The guard case builds a disposable TestDrive target with an explicit canonical origin and runs the real updater from it.
  - The non-canonical control expects exit 0 and dry-run output. Caller location and the real origin are asserted unchanged.
  - The updater itself is untouched.
- **TEST-xxx entries.** TEST-001, 002, 005 and 006 exist and pass on my re-run. TEST-007 and TEST-482 are existing suite cases. The validator's full sweep had them green (129 discovered, 128 PASS, 1 host skip), and their mutation replays redden.

### Deviations from the frozen spec (all disclosed)

- **Amendment 3** changed the local bounds to 1800/3600 and added Spec-AC-04. It is contract class, and the owner signature is still owed. This is tracked by `fu-amend-spec-release-corpus-hermetic` (P2, open), so it is disclosed, not hidden.
- **Pester mutation rows** were replayed by hand, not by `mutation-run --replay`, which returns rc 1 (D18). This is disclosed in Residual risks, and in a decisions.jsonl agent decision that is not an owner signature.

## Findings

**NB-1 (NON-BLOCKING): the spec's own status table is stale.** SPEC-0280-spec-release-corpus-hermetic.md:213 and :215 still read `planned` / `—` for Spec-AC-02 and Spec-AC-03, but both are satisfied.
- The validator applied the implementing-status carve, under which these rows flip at the close ceremony. So this is a sequencing obligation, not a defect today.
- Failure scenario: the commit goes in and the close ceremony is skipped, or a docs-only closer flips only the frontmatter. The merged spec would then call two satisfied ACs `planned`, while SPEC-0257 cites this ride as the one that closed Spec-AC-05. `docs-audit --gate` already exits 1 on exactly these rows.
- Recommended disposition: **(a) remediate in tree.** Flip both rows to `done` with their evidence (corpus-decision/corpus.json/VALIDATION-20261107T2359Z for AC-02; the SPEC-0257 cell compare and the spec-amend record for AC-03), in the closing commit or by close-work-item, before the PR. The orchestrator records the disposition.

### INFO (does not gate)

- `aai-win-dispatch.Tests.ps1:1438`: the comment "Pester v5 runs Describe blocks in file order, so this is the last one" is true for default Pester 5. A future reordering or randomization option would make TEST-002 vacuous only for leaks introduced after it.
- `aai-update.Tests.ps1:85`: the real-origin preservation assertion cannot currently fail, because nothing in the updater's dry-run path writes git config. It is a cheap belt check, and the location assertion is the one the POP mutation proves.

## cannot_verify

See the YAML block. It covers:
- the Windows PS 5.1 and pwsh CI legs;
- the CI 540/1080 defaults and hosted timing;
- committed-tree equals measured candidate (post-commit manifest);
- the corpus, which I did not re-execute.

## Warning dispositions (H6)

- NB-1: recommended (a), remediate in tree before the PR (flip the AC-02 and AC-03 rows at close).

## Next steps

1. Flip Spec-AC-02 and Spec-AC-03 at close, which handles NB-1.
2. Commit. Recompute the post-commit manifest.
3. Open the PR and observe current-head Linux and Windows CI.
4. Owner sign-off on Amendment 3 stays open as `fu-amend-spec-release-corpus-hermetic`.
