```yaml
review:
  scope: "git diff b6f740783f6df8885bfc49a56fb3b4225f7538e5..cbf0cdcd (31 files, +1537/-438; branch change/release-finish-one-command)"
  spec: docs/specs/SPEC-DRAFT-spec-release-command-finish.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/release-finish.mjs:108-134 (remote-tag history boundary, refuses unavailable tag objects; CR-1 fixed), :148-175, :289-297, :329-333; TEST-001..003 (internal 004/005/016/023/027..032/041..043) green in r6 sweep and mutation matrix" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/release-finish.mjs:301-310 (exit 0/1/8 semantics, empty/malformed refuse), :385-397 (OPEN, base recheck, watcher, settled pass, identity, head, base, --match-head-commit, no auto/admin); TEST-004/005" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/release-finish.mjs:400-403 (merge-SHA run, peeled tag, trimmed body equality before cleanup); .github/workflows/release.yml:79-86 (no auto-generated fallback, error propagation); TEST-006/022" }
      - { ac: Spec-AC-04, call: non-compliant, citation: "CR-3 .aai/scripts/release-finish.mjs:349,351,366,406 - on Windows the temporary preparation worktree is never recognised as registered, never removed, and local cleanup refuses permanently; CR-2 (prior review) fixed at :239-275" }
      - { ac: Spec-AC-05, call: compliant, citation: "Validation r6: hosted run 39020377328 at cbf0cdcd - Windows PowerShell 5.1 and pwsh7 Pester 152/0/4 with native empty/normal SHA+URL cases; Linux completed=20 skips=0 (.github/workflows/ps1-quality.yml:171-189); test_701 native controls" }
      - { ac: Spec-AC-06, call: compliant, citation: ".aai/SKILL_RELEASE.prompt.md (narrow authorization, resume, race, skips); docs/product/release-command-finish.md; PROFILES core entry; suite-map; prompt-diet ledger +247; catalogs; r6 full sweep 109/109 incl. declared companions" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/release-finish.mjs, line: 351, issue: "Preparation worktree identity is matched by exact string between a Node realpath and git worktree list --porcelain output (also :366); on Windows these never match (backslash vs forward slash, possible 8.3 short names)", failure_scenario: "Windows operator runs aai-release.ps1 -Version v1 -Confirm. Worktree is added and committed; :366 finds no registered worktree so it is never removed and record.worktree is cleared. After merge, tag and release are verified and the remote branch deleted, :406 sees branch chore/release-v1 checked out (in the helper's own leaked temp worktree) and refuses cleanup-worktree. Every resume refuses identically; base sync never runs. A crash between worktree add and commit (:352/:356) likewise makes resume fail on 'worktree add' of an already-checked-out branch." }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-release.ps1, line: 283, issue: "PS1 preview adds --online whenever gh is authenticated, without the origin-remote check the shell frontend has (aai-release.sh:73)", failure_scenario: "Reproduced: local-only repo (no origin), gh authenticated, pwsh aai-release.ps1 -DryRun exits 20 'git-command - git ls-remote origin ...'; aai-release.sh --dry-run in the same repo exits 0 with a plan. Pre-diff PS1 printed the plan." }
      - { rank: NON-BLOCKING, file: .aai/scripts/release-finish.mjs, line: 388, issue: "requiredChecks() refuses an empty required-check list immediately after gh pr create, before watch-ci (which already treats empty as not-yet-registered and keeps polling) is reached", failure_scenario: "Normal first confirm: PR is created and ~2-3 s later gh pr checks --required reports no checks (Actions jobs not yet queued) -> REFUSED github-checks/required-checks; the operator must resume. Fail-closed and spec-permitted (empty refuses), but likely on most first runs." }
      - { rank: NON-BLOCKING, file: .aai/scripts/release-finish.mjs, line: 146, issue: "Validation N6-1: heading-identity accept counts a rolled heading once per PR, so one surviving byte-identical heading satisfies two PRs (same class as the existing notes.includes(title) accept at :168)", failure_scenario: "Two PRs add '## [unreleased] - fix: typo' with different bodies; a later commit drops one entry; both PRs pass the audit and the release merges (validation probe P9)." }
      - { rank: NON-BLOCKING, file: .aai/scripts/release-finish.mjs, line: 316, issue: "Version is validated only by check-ref-format, not against the release.yml tag pattern 'v?[0-9]...' that the publication workflow and the history boundary (:118) both require", failure_scenario: "Operator passes --version stable-2026: PR is merged irreversibly, release.yml finds no release commit and exits success, then :402 refuses tag-mismatch after merge with nothing published." }
      - { rank: NON-BLOCKING, file: docs/product/release-command-finish.md, line: 16, issue: "Product doc states the work awaits independent validation and that Windows/hosted proof is pending; Links say validation evidence pending. Validation r6 PASS and hosted run 39020377328 now exist", failure_scenario: "Doc merged as-is records a false 'pending' status and no evidence link for a delivered capability." }
      - { rank: NON-BLOCKING, file: .aai/SKILL_RELEASE.prompt.md, line: 82, issue: "Exit-code table promises 12/13/15/16 for conditions the remote --confirm path now reports as exit 20 from release-finish (malformed-notes, empty-notes, tag-exists, github-command)", failure_scenario: "Agent relays 'exit 15 = existing tag' guidance but receives exit 20 'tag-exists' on the remote path; or gh unauthenticated gives 20 instead of documented 16." }
  cannot_verify:
    - { claim: "release-finish.mjs end-to-end behaviour on Windows (PowerShell 5.1/pwsh7 delegating to Node): worktree, journal, claim, base-index sync", closes_with: "One TEST-033-style finish fixture executed on the hosted windows-latest job (both engines); CR-3 predicts it fails at cleanup-worktree" }
    - { claim: "Live GitHub semantics: gh pr checks --required output when no check is registered yet, required-check registration latency, gh run list --commit, squash title feeding release.yml's tag regex", closes_with: "A real disposable-repo release run against github.com; current proof uses exact transport stubs and the real workflow shell" }
    - { claim: "Documented external race between the final base observation and GitHub's merge", closes_with: "Not closable client-side (no atomic base-conditional merge API); accepted spec limitation, disclosed in prompt and product doc" }
  overall: fail
```

# Independent Code Review - release-command-finish (re-review)

**Verdict: FAIL.** One BLOCKING code finding, CR-3, makes the confirmed finish unable to complete on Windows. For the same reason Spec-AC-04 is non-compliant. CR-1 and CR-2 from the prior review are fixed. The other five ACs comply.

## Scope and independence

- Root: `/Users/ales/Projects/aai-change-release-finish-one-command`, branch `change/release-finish-one-command`, HEAD `cbf0cdcd`.
- Scope: `git diff b6f740783f6df8885bfc49a56fb3b4225f7538e5..cbf0cdcd` (base = origin/main, 31 files). I reviewed the full diff myself.
- STATE: `worktree.user_decision: worktree`, `inline_review_scope: null`. `git status --porcelain` shows only `docs/ai/tests/test-runs.jsonl` modified. That file is test telemetry outside the scope, so the scope is clean.
- Dispatch note: the dispatch listed risk classes to look at (irreversible actions, races, fail-open, injection, PS5.1 portability, operator boundary). It neither pre-rated severity nor excluded any area. I recorded this as area focus, not coaching, and reviewed the full scope anyway.

## Prior findings

- **CR-1 (missing local tag bypasses audit): FIXED.** `historyBoundary` (release-finish.mjs:108-134) now takes release tags from `git ls-remote --tags origin` on confirm. It refuses when a tag's commit object is unavailable or the clone is shallow. A first release audits the complete history (`previous=''`). It also refuses if remote tags move during the audit (:173). Offline preview uses local tags, and a missing tag there widens the audit rather than skipping it. Validation r6 mutants mB/mC are guarded by TEST-031/032.
- **CR-2 (base sync advances a switched checkout): FIXED.** `syncBase` (:239-275) behaves as follows:
  - It holds Git's own `index.lock` as a token-owned claim before checking `symbolic-ref HEAD`, so a porcelain checkout or switch cannot run concurrently.
  - It locks the base ref with an `update-ref --stdin` prepared transaction that carries the expected old value.
  - It updates the tree via `read-tree -u -m` on a private index.
  - It re-verifies HEAD and the ref before recording `synced`.
  - Residual (INFO): HEAD itself is not locked. Only a plumbing `git symbolic-ref` by another process could still redirect it, and the post-check at :267 then refuses truthfully. The code comment at :183-184 overstates this as "HEAD and index locks".

## Spec-compliance AC walk

| Spec-AC | Call | Citation |
|---|---|---|
| Spec-AC-01 | compliant | :289-297 reads the authoritative remote SHA and fetches only on confirm (`--no-tags --no-write-fetch-head`). Preview refuses missing objects (`base-history`). :157-164 classifies raw `-z` modes on both sides through the shared `isShipped`. :167 release-cut exemption; :170 same-line marker through `hasNoNotesReason`. :332 refuses `missing-notes` before any ref, worktree, push or PR. TEST-001..003 green. N6-1 residual noted below. |
| Spec-AC-02 | compliant | :301-310 accepts gh exit 0/1/8 only, cross-checks exit status against buckets, and refuses empty or invalid JSON. :388 accepts pass/pending only before the watcher; :392 requires all pass after it. :393-395 re-checks identity, remote head and base, then `gh pr merge --squash --match-head-commit`. There is no `--auto` or `--admin`. TEST-004/005. |
| Spec-AC-03 | compliant | :401 polls a bounded run for exactly the merge SHA; ambiguous runs, SHA mismatch or a non-success conclusion refuse. :402 peeled tag equals the merge SHA. :403 trimmed body equals the rolled notes. All of this happens before cleanup at :404. release.yml now refuses instead of auto-generating notes and propagates `gh release create` failure. TEST-006/022. |
| Spec-AC-04 | **non-compliant** | **CR-3**: on Windows, preparation-worktree registration is never detected (:351/:366). Leased remote deletion (:405) runs, but local cleanup (:406) refuses permanently, blaming a checkout the helper itself leaked, and base sync never runs. On POSIX the eleven-stage resume, leases and sync controls are sound (TEST-007..009, 026). |
| Spec-AC-05 | compliant | Accepted on Validation r6 evidence: hosted run 39020377328 at cbf0cdcd ran Windows 5.1 and pwsh7 native SHA/URL normal, empty and error cases, plus Linux 20/20 with zero skips. The workflow step is labelled TEST-014 internally; the mapping at test-aai-release.sh:1379 covers it. AC-05's scope is the native-capture controls, not the Node finish on Windows (see cannot_verify). |
| Spec-AC-06 | compliant | Prompt and product doc disclose the narrow authorization, version-specific resume, skips and race. Also present: PROFILES core entry, suite-map entries, learned-routing fixture copying the helper closure, prompt-diet +247 credit, and catalogs. The two notes-suite absence assertions are retired explicitly as the spec plans, and the gate-profile pin is kept. Full sweep 109/109. The product-doc staleness is a NON-BLOCKING item. |

TEST evidence: TEST-001..013 map to the internal cases (mapping at tests/skills/test-aai-release.sh:1379). They are green in the r6 full sweep and the hosted run, per the validation report. I did not re-run the suite; my own run would have appended telemetry to the worktree. I did run two read-only scratch probes, described below.

Deviations from the frozen spec: none substantive.
- Spec base ref is c9a04429, the dependency. The review base is origin/main b6f74078, which already contains the merged dependency, so the delta is the finish scope only.
- The extra audit accepts (`#n` or title cited in the notes, and the PR's own surviving heading at :136-147) define "noted" history. They are not new exemptions, and the owner chose this contract in the r5/r6 HITL entries of decisions.jsonl.

## Code-quality findings

### CR-3 - BLOCKING - Windows path comparison leaks the preparation worktree and blocks cleanup forever

`.aai/scripts/release-finish.mjs:349` stores `fs.realpathSync(fs.mkdtempSync(os.tmpdir()/...))`. On Windows this is a backslash path such as `C:\Users\...\Temp\aai-release-wt.X`, possibly with 8.3 segments. Lines :351 and :366 then search `git worktree list --porcelain` for the exact text `worktree ${wt}`. Git for Windows prints forward-slash paths (`C:/Users/.../aai-release-wt.X`), so the match never succeeds.

**Failure scenario:**
1. A Windows operator runs `aai-release.ps1 -Version v1 -Confirm`, which delegates to Node at aai-release.ps1:124-131.
2. The worktree is added and committed.
3. :366 finds nothing, skips `git worktree remove`, and nulls `record.worktree`.
4. PR, merge, workflow, tag and release verification succeed, and the remote branch is deleted.
5. :406 then finds `branch refs/heads/chore/release-v1` in the worktree list (the helper's own leaked worktree) and refuses `cleanup-worktree - Release branch is checked out`.
6. Every resume repeats this refusal; base sync never runs. Recovery needs a manual `git worktree remove`.

A crash between `worktree add` and the commit fails the same way on resume: :352 sees no registration, so :356 runs `worktree add` on a branch that is already checked out.

No test executes `release-finish.mjs` on Windows. The Windows Pester jobs only match source text (aai-win-dispatch.Tests.ps1:1091-1096), and TEST-033 runs on Linux pwsh.

**Fix:** compare canonical paths instead of strings. For example, `fs.realpathSync.native` on both sides, with separators normalized and case folded on win32; or identify the worktree via `git -C <wt> rev-parse --git-dir`. Add a regression that feeds a forward-slash/backslash variant, or run one finish fixture on `windows-latest`.

The base-sync worktree lookup (:240-241) uses the Git-printed path only as a cwd, so it is unaffected.

### NON-BLOCKING

1. **PS1 preview fails without origin (P2).** aai-release.ps1:283 appends `--online` whenever gh is authenticated. Reproduced in a scratch repo with no origin: PS1 `-DryRun` exits 20 with `REFUSED: git-command - git ls-remote origin ...`, while the shell exits 0 with a plan. This is a regression from pre-diff PS1 and breaks frontend parity. Fix: mirror the shell's `git remote get-url origin` guard. **Disposition: remediate-in-tree** (one-line guard plus a parity case).
2. **First confirm likely refuses before checks register (P2).** At :388, `requiredChecks()` runs about 2-3 s after `gh pr create` and refuses an empty list. `watch-ci.mjs` already treats empty as "not registered yet" and keeps polling within the deadline. This fails closed and complies with the spec's "empty refuses", but it probably forces a resume on most first runs. A bounded registration grace, followed by refusal, would still comply. **Disposition: promote-to-follow-up** (`fu-release-checks-registration-grace`, P2).
3. **N6-1, byte-identical heading counted once (P3).** Carried from validation (`release-finish.mjs:146`, and :168 title accept). **Disposition: promote-to-follow-up** (`fu-release-notes-heading-multiset`, P3, multiset count). N6-2 is accepted by the owner's r6 heading-identity choice. N6-3 refuses in the safe direction. Neither needs action.
4. **Version not checked against the tag pattern (P3).** :316 validates the version only with check-ref-format. A version that does not match release.yml's `v?[0-9]` pattern merges, and then :402 refuses `tag-mismatch` with nothing published. Validate the version against the workflow pattern before mutations when release.yml exists. **Disposition: remediate-in-tree or follow-up** (`fu-release-version-tag-pattern`, P3).
5. **Product doc stale (P3).** docs/product/release-command-finish.md:16 and its Links still say validation and platform proof are pending. **Disposition: remediate-in-tree** at the ship/product-docs step (after LOOP COMPLETE): update the status sentence and add the r6 report and hosted run link.
6. **Prompt exit-code table mismatch (P3).** On the remote confirm path, conditions documented as exits 12/13/15/16 surface as exit 20 with a named cause. **Disposition: remediate-in-tree.** Annotate the codes as apply-to-preview/no-remote, and state that remote confirm reports exit 20 with the cause.

INFO (no gate):
- `AAI_RELEASE_POLL_SECONDS=0` passes :312 but `watch-ci` rejects 0.
- A fork PR whose head branch is named `chore/release-<version>` makes the `--head` lookups (:334, :375) refuse. This is a fail-closed DoS only.
- Removing "dry-run first" from SKILL_RELEASE leaves the operator boundary intact ("Never add confirm/yes yourself"). The owner's `--confirm` now also merges, so restoring a preview-first sentence is advisable.
- release.yml now fails a direct tag push that has no CHANGELOG section, where it used to auto-generate notes. This is an intended behaviour change and is not called out in CHANGELOG.

## Security / injection / boundary check

- **No shell interpolation of untrusted data.** All git/gh calls are argv arrays via `spawnSync`. The PR body is a static template written to `--body-file`. The version reaches the title only as an argv element. Release body and PR body are compared or parsed as data only. The printed resume command quotes the root and any non-simple version.
- **Irreversible steps are guarded:**
  - Push: `--force-with-lease=ref:` expects the branch to be absent.
  - Merge: OPEN state, settled required checks, identity, head, base and `--match-head-commit`.
  - Tags and releases: never published by the client.
  - Remote delete: expected-head lease plus a dependent-PR check.
  - Local delete: `update-ref -d` with the expected old value.
  - Base sync: index lock, ref transaction and post-verification.
- **Journal and claims** use `runtime-file.mjs` (`atomicWrite`, `loadOrDegrade`, `claimExclusive`), so the sidecar rule is satisfied. Same-host dead-PID reclaim is bounded, and live, foreign or corrupt owners never expire.
- **Operator boundary is intact.** `release-finish.mjs` refuses mutations without `--confirm` (:315). Both frontends map `--dry-run` over `--confirm`. The skill keeps "Never add confirm/yes yourself". No other script invokes the helper with `--confirm`.
- **PS 5.1 portability:** `Get-Date -AsUTC` is replaced. `Invoke-NativeChecked` now unrolls its output, which `Select-CapturedValue`'s `@()` handles. Empty captures throw (closes fu-release-ps1-empty-precut-sha). The Node finish path on Windows is CR-3.

## Probes run (read-only, scratch only)

- `git ls-remote --tags origin refs/tags/v1 'refs/tags/v1^{}'` against a real bare origin returns both lines, confirming that :402's peeled lookup works for the annotated tags release.yml creates.
- No-origin parity probe (NB-1): shell `--dry-run` rc 0; PS1 `-DryRun` rc 20 with the `git-command` refusal.
- Real `gh pr view 470 --json headRepository,...` includes `nameWithOwner`, consistent with identity() at :178 (gh 2.93.0).

Scratch: `/private/tmp/claude-501/-Users-ales-Projects-aai/84834df3-26b2-4169-98af-6a142178eee5/scratchpad/{lsr,ps1p}`. No source, STATE, git index, commit, push or GitHub write.

## Warning dispositions (H6)

| Finding | Recommended disposition (orchestrator records) |
|---|---|
| NB-1 PS1 no-origin preview | remediate-in-tree |
| NB-2 checks registration grace | follow-up `fu-release-checks-registration-grace` P2 |
| NB-3 N6-1 heading multiset | follow-up `fu-release-notes-heading-multiset` P3 |
| NB-4 version vs tag pattern | remediate-in-tree, else follow-up `fu-release-version-tag-pattern` P3 |
| NB-5 stale product doc | remediate-in-tree at ship/product-docs step |
| NB-6 exit-code table | remediate-in-tree |

## Next steps

1. Remediate CR-3 with a failing-first regression (path-variant or windows-latest finish fixture), and fold NB-1 and NB-6 into the same round.
2. Record the NB dispositions above.
3. Re-review the remediation diff.
4. Stage this report with the scope's next commit so it does not orphan.
