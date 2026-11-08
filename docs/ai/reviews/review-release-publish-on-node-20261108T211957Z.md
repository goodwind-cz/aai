```yaml
review:
  scope: "git diff main...1129a9b6 (branch refactor/release-publish-on-node), STATE code_review.scope plus docs/ai/EVENTS.jsonl docs/ai/decisions.jsonl docs/ai/tests/test-runs.jsonl"
  spec: docs/specs/SPEC-0282-spec-release-publish-on-node.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/aai-release.mjs:17-23,190-214,247-251; TEST-3520 (6 node:test cases) PASS" }
      - { ac: Spec-AC-02, call: compliant, citation: "aai-release.mjs:43-63,199-201; TEST-3521 DB-01..DB-05 PASS (DB-05 walks 4 modes x 2 versions)" }
      - { ac: Spec-AC-03, call: compliant, citation: "aai-release.mjs:131-188; TEST-3522 DB-06..09,11,14 and TEST-3537 PASS" }
      - { ac: Spec-AC-04, call: compliant, citation: "aai-release.sh:6-12, aai-release.ps1:17-32; TEST-3523 DB-12, DB-13 and the 11-invocation sh/ps1 parity matrix PASS" }
      - { ac: Spec-AC-05, call: compliant, citation: "aai-release.mjs:74-87; TEST-3524 and TEST-3538 PASS" }
      - { ac: Spec-AC-06, call: compliant, citation: "lib/platform-adapter.mjs:157-184; TEST-3525 PASS" }
      - { ac: Spec-AC-07, call: compliant, citation: "release-finish.mjs:60-70,488,569 and every host.* call site; TEST-3526 PASS; spawn options and refusal text equal the old command() for gh" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-3527 PASS (DB-01..DB-21, each begins one test name)" }
      - { ac: Spec-AC-09, call: compliant, citation: "aai-release.sh 7 code lines, mode 100755; TEST-3528 PASS" }
      - { ac: Spec-AC-10, call: compliant, citation: "aai-release.ps1 25 code lines; TEST-3529 PASS (Pester Total=12 Passed=12 Failed=0 Skipped=0, pwsh 7 local)" }
      - { ac: Spec-AC-11, call: compliant, citation: "TEST-3530 PASS" }
      - { ac: Spec-AC-12, call: compliant, citation: "PROFILES.yaml:98; TEST-3531 PASS" }
      - { ac: Spec-AC-13, call: compliant, citation: "test-aai-release.sh TEST-019/TEST-015 copier, test-aai-learned-routing.sh:75-77; TEST-3532 PASS" }
      - { ac: Spec-AC-14, call: compliant, citation: "suite-map.yaml, ps1-quality.yml:85-86,117-118, PROFILES.yaml; TEST-3533 PASS" }
      - { ac: Spec-AC-15, call: compliant, citation: "RFC-0017 pair row removed and sentences added; SKILL_RELEASE.prompt.md:84, 4921 bytes; TEST-3534 PASS" }
      - { ac: Spec-AC-16, call: compliant, citation: "TEST-3535 PASS (before 319, after 32, removed 287, module 217)" }
      - { ac: Spec-AC-17, call: compliant, citation: "aai-release.mjs:249; TEST-3536 PASS" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: CHANGELOG.md, line: 35,
          issue: "The shipped CHANGELOG entry says the module holds 212 code lines. The delivered file holds 217: 1d22fbac added 5 lines and the entry was not re-measured. TEST-3535 itself prints 217.",
          failure_scenario: "A reader or a release note that quotes the entry gets a wrong measurement. The CHANGELOG is consumer-visible and rolls into the release body, so this is a false record." }
      - { rank: NON-BLOCKING, file: .aai/SKILL_RELEASE.prompt.md, line: 86,
          issue: "Exit 20 is documented only as 'finish refused'. Since DB-07, a local cut (--confirm --no-remote) also exits 20 when a git step fails, with no Resume line. The DB-14 exits 130 and 143 have no 'exit N =' line at all.",
          failure_scenario: "An agent follows SKILL_RELEASE on a local cut whose git commit fails (for example, no identity). It relays a 'finish refused' with a resume command that does not exist. An interrupted cut that returns 130 has no documented meaning for the agent to relay." }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-release.sh, line: 8,
          issue: "One branch covers both 'node absent' and 'aai-release.mjs absent', and both print 'Node.js 22 or later is required'. The ps1 launcher does the same (aai-release.ps1:19-20). The spec (D-LAUNCH) prescribes this.",
          failure_scenario: "A partial or hand-copied downstream install has aai-release.sh but not aai-release.mjs. The user, who has Node 24 installed, is told to install Node, and the actual cause (the missing module) is never named." }
  cannot_verify:
    - { claim: "Windows PowerShell 5.1 and native-Windows pwsh parity: DB-10, DB-11, DB-12 and the captured-stderr case that exits 12", closes_with: "hosted ps1-quality Windows jobs green with release-cut.Tests.ps1 discovered and not skipped (H1)" }
    - { claim: "The release-dry-run required CI job stays within budget with tests/skills/lib/aai-release.test.mjs in its reader corpus (about 25 s locally)", closes_with: "hosted release-dry-run job on the PR head (H2)" }
    - { claim: "The real gh CLI accepts every D-HOST argv unchanged. The tests prove argv equality with the old call sites over stubs, not against a live gh.", closes_with: "a real release run (owner-operated), or gh --help argv inspection for the gh version in use" }
    - { claim: "DB-14 on Windows: an interrupted cut may leave a temporary worktree", closes_with: "a Windows interrupt probe (residual risk the spec names)" }
    - { claim: "The rest of the repository is unaffected. This review ran only node --test aai-release.test.mjs (35/35) and test-aai-release-cut.sh (rc 0). The validator's r1 full sweep recorded 127/131 with 3 failed; their triage is in the validation report, not re-checked here.", closes_with: "validation r1 sweep triage, or a pre-PR sweep" }
    - { claim: "Owner acceptance of the three unsigned contract amendments (15:57:14Z, 19:54:07Z, 21:11:30Z; DB-14 widening and narrowing, DB-20, DB-21)", closes_with: "owner sign-off that closes fu-amend-spec-release-publish-on-node" }
  overall: pass
```

security_relevant: false

# Code review: release-publish-on-node (head 1129a9b6)

## Scope

- Diff: `git diff main...HEAD` on `refactor/release-publish-on-node`, head `1129a9b6`, base `main` (`c88cf708`). Worktree clean at review time.
- Spec: `docs/specs/SPEC-0282-spec-release-publish-on-node.md` (frozen, ceremony 2, `frozen_sha256` bca0e089...).
- Scope gap: the STATE scope omits three paths that the branch changes: `docs/ai/EVENTS.jsonl`, `docs/ai/decisions.jsonl` and `docs/ai/tests/test-runs.jsonl`. All three are append-only ledger lines. I reviewed them: the doc_lifecycle, check_dispatched and validation_verdict events; 9 decision lines (6 spec_amendment, 2 follow_up, plus the amendment fu); and one sweep record. None of them carries a defect.
- The STATE scope names `tests/skills/lib/cd-subshell-leak-baseline.tsv`, which the branch does not change. The spec expects that: the ratchet asked for no row.
- Dispatch prompt: it lists the areas the diff touches and calls release "sensitive". It does not pre-rate findings or exclude any area. I record no coaching attempt and reviewed the full scope.
- Run by this reviewer: `node --test tests/skills/lib/aai-release.test.mjs` passed 35/35. `aai-run-tests.sh bash tests/skills/test-aai-release-cut.sh` exited 0, with every TEST-3520..3538 row PASS and Pester 12/12 under pwsh 7. `spec-amend list --strict`: 3 unsigned-tracked records for this ref, 0 untracked. `git ls-files -ci`: no ignored file is committed.

## Spec compliance: AC walk

The verdict is pass: all 17 rows are compliant (see the YAML). The TEST-3520..3538 rows exist in `tests/skills/test-aai-release-cut.sh` and pass on this head.

Deviations from the frozen text:

1. D-MOD says the module imports `run` from `release-cut.mjs`. It imports `main as cutMain` (`aai-release.mjs:17`). `main` is `run` with the real deps, which is what `deps.cut` needs, so the behaviour is the same as the spec's intent. `parseArgs` also takes `(argv, env)` rather than `(argv)`. `deps` gains `tick`, `arm`, `disarm` and `interrupted` (the DB-14 seam) and does not use `readFile`.
2. D-WIRE and D-RFC say SKILL_RELEASE changes by one line. Two lines change: the exit-16 line is replaced by the exit-14 line, and the exit-20 line drops `/16` (validation r1 N3). The byte count is unchanged (4921 = 4921), so no prompt-diet true-up applies.
3. D-TESTS does not mention `test_701_native_capture_controls` in `test-aai-release.sh`. The branch deletes it, as a necessary consequence of deleting `Invoke-NativeChecked`, and check-test-registration stays green.
4. DB-14 was amended three times after freeze, and DB-20 and DB-21 were added. The ledger records each change, but they are unsigned contract amendments. They are tracked by `fu-amend-spec-release-publish-on-node` (open, P2). The owner sign-off is still owed.

Code checks behind the AC calls:

- **Host calls.** For every gh call site, I compared the old and new release-finish code. The old `command('gh', ...)` spawned with `{cwd: root, encoding: 'utf8', timeout: 60000, maxBuffer: 8 MiB, env: {...process.env}}` and refused `github-command` with `gh <args>: <error|stderr|exit N>`. The adapter's `gh()` (`platform-adapter.mjs:163`) passes the same options. `hostText` (`release-finish.mjs:69`) builds the same refusal text. The calls that may fail (allow-failure: the audit `api`, `contextSource`, `queuedOrRefuse`, `prMerge`) still read the raw result. `checksRunner` matches the github-checks default (32 MiB, 60 s, inherited env).
- **Platform resolution.** `resolveHost` runs after the confirm and version checks and before `auth status` (`:569`). In audit mode it runs only with `--online` (`:565`). An invalid record yields `mismatch: true` (adapter `isMismatch`), so it refuses `platform-mismatch` as the spec's edge-case list requires. An unrecorded remote that is not a known host stays legacy GitHub.
- **In-process finish.** `runCli` (`release-finish.mjs:706-710`) keeps the old catch, finally and exit-code logic. The CLI guard still runs it when `release-finish.mjs` is spawned directly (the audit child of `release-cut.mjs`). No signal handler is armed on the finish path, so killing the node process ends the release, as `exec` did.
- **Local cut.** The reuse rule (a prefix match on the subject, or an ancestor of the base), the base selection, the eight `AAI_VERSION.md` lines and the report all equal the old `.sh` (read at `main:.aai/scripts/aai-release.sh:120-182`). The worktree is removed on every exit path, and the `finally` disarms the handlers.

## Code quality

The verdict is pass: 0 BLOCKING findings, 3 NON-BLOCKING.

- **NB-1 (P3): the CHANGELOG states a stale measurement** (`CHANGELOG.md:35`, "the module holds 212"). The real count is 217, and TEST-3535 prints 217. Since this is a false record in a consumer-visible document, disposition (d) is not allowed. Recommended disposition: (a) remediate in tree by changing 212 to 217. This is a doc-only delta.
- **NB-2 (P3): SKILL_RELEASE does not document the new local-cut exits** (`.aai/SKILL_RELEASE.prompt.md:86`). Exit 20 reads as "finish refused", but a local-cut git-command refusal (DB-07) also exits 20, and 130 and 143 are undocumented. The spec only required the `EXIT` constants to be documented, and they are, so this is not a compliance gap. Recommended disposition: (b) a follow-up via `follow-ups.mjs add --id fu-release-skill-local-cut-exits --ref release-publish-on-node --severity P3`. The 4921-byte cap and the prompt-diet ceremony make an in-tree edit costly here.
- **NB-3 (P3): the missing-module case is reported as missing Node** (`aai-release.sh:8`, `aai-release.ps1:19`). The wording was prescribed by the spec, and the scenario needs a partial install. Recommended disposition: (d), with this line:
  `accepted residual: launcher reports a missing aai-release.mjs as missing Node; spec-prescribed wording, needs a partial install, no observed bite, no false record.`

INFO (not gating):

- `parseArgs` accepts `--launcher` and `--launcher-path` at any argv position, so a user can change the flag spelling of the output. This is harmless.
- A non-Refusal exception in the cut (for example, EACCES writing `AAI_VERSION.md`) still removes the worktree, but it ends in a Node stack trace rather than a named refusal.
- An EPIPE on stdout during an in-process remote finish exits 141 without the `releaseClaim` finally. That is the same class as the old uncaught-EPIPE crash, so it is not a regression.
- The `.ps1` launcher under pwsh 7 exits 0 on a process-group SIGINT, as at baseline. The worktree is still removed, and DB-14, the CHANGELOG and the product doc now state this.

## Cannot verify

See the YAML: H1 (Windows PowerShell 5.1 and native Windows), H2 (the release-dry-run CI job), the real-gh argv contract, DB-14 on Windows, repository-wide regressions beyond the two suites run here, and the owner sign-off on the three contract amendments.

## Warning dispositions (H6)

- NB-1: (a) remediate in tree.
- NB-2: (b) follow-up `fu-release-skill-local-cut-exits` (P3); the orchestrator files it.
- NB-3: (d), with the `accepted residual:` line above.

## Next steps

1. Fix NB-1 (one number in CHANGELOG.md).
2. The orchestrator files NB-2's follow-up.
3. Before the push, close the three registry items named in the spec at the close step (validation r2 N5), and obtain the owner sign-off for `fu-amend-spec-release-publish-on-node` at the merge checkpoint.
