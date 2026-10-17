```yaml
review:
  scope: "c9a04429d6e2af0c133a86c0b3d2c2662572442f to complete local working/staged/untracked 29-path snapshot in /private/tmp/aai-finish-r2-local-source.json"
  spec: docs/specs/SPEC-DRAFT-spec-release-command-finish.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: non-compliant, citation: ".aai/scripts/release-finish.mjs:109; CR-1 actual absent-local-tag audit and confirm probes" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/release-finish.mjs:178 and :262; producer R internal TEST006/010/016/017; documented last-observation race retained" }
      - { ac: Spec-AC-03, call: cannot-verify, citation: ".aai/scripts/release-finish.mjs:278; original independent publication F2 unresolved; targeted TEST022 supports propagation fix only" }
      - { ac: Spec-AC-04, call: non-compliant, citation: ".aai/scripts/release-finish.mjs:151; CR-2 actual checkout switch advances feature and reports base synced" }
      - { ac: Spec-AC-05, call: cannot-verify, citation: "TEST010/011 missing actual Windows5.1/Windows7 and hosted Linux20 final-source provenance" }
      - { ac: Spec-AC-06, call: cannot-verify, citation: "Producer nine companions and targeted compatibility corrections support implementation; current full sweep not executed; this independent review fails" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/release-finish.mjs, line: 109, issue: "A missing local tag bypasses the historical notes audit", failure_scenario: "Origin retains previous release v0, but a no-tags/local-tag-missing checkout has an unnoted shipped PR; git describe fails and audit returns empty, allowing confirmation to merge and publish." }
      - { rank: BLOCKING, file: .aai/scripts/release-finish.mjs, line: 151, issue: "Base synchronization can advance an unrelated checked-out branch", failure_scenario: "After selecting the registered main checkout, another process checks out feature before merge --ff-only; the helper advances feature, leaves main unchanged and reports Base synced/complete." }
  cannot_verify:
    - { claim: "Required Windows PowerShell5.1 and Windows pwsh7 native normal/empty/error behavior", closes_with: "Actual named Windows runtime executions, source identity and raw logs for TEST010" }
    - { claim: "Twenty final-source hosted Linux TEST033 executions with no skips", closes_with: "Authorized source staging followed by actual hosted workflow run/head SHA/raw log showing completed20 skips0 for TEST011" }
    - { claim: "Current full-suite recovery and cause/resolution of original publication F2", closes_with: "Causal reproduction or defensible attribution of F2 and authorized fresh independent current-tree full sweep; ten prior targeted passes are not causal proof" }
    - { claim: "Live GitHub end-to-end service behavior", closes_with: "Separate authorized service execution against the bound source; current proof uses actual Git/workflow shell with exact GitHub transport stubs" }
  overall: fail
```

# Independent Code Review — release-command-finish

Both specification compliance and code quality **FAIL**. Two concrete defects were reproduced on the unchanged helper. Required platform and current full-suite evidence also remain unavailable. This report does not replace or relax the existing Validation FAIL.

Review started at the actual captured UTC `2026-10-14T17:42:38Z`. The initial canonical-instruction read preceded that capture. Actual model identity and usage are unavailable; no granted-model, model-diversity or token-usage claim is made.

## Scope and independence

Root: `/private/tmp/aai-release-command-finish-integrated-worktree`; branch `fix/release-command-finish`; base/HEAD `c9a04429d6e2af0c133a86c0b3d2c2662572442f`. STATE selects `worktree`, with no inline scope. I ran my own `git status --porcelain`, `git diff --stat <base>`, and scoped `git diff <base> -- ...`; read the two untracked files directly; and reviewed the full 29-path snapshot. The staged intake/spec and all ledger/index/evidence companions are included. No unrelated source changes were excluded. No review coaching attempt was observed.

The exact scope is:

```text
.aai/SKILL_RELEASE.prompt.md
.aai/scripts/aai-release.ps1
.aai/scripts/aai-release.sh
.aai/scripts/release-finish.mjs
.aai/system/PROFILES.yaml
.github/workflows/ps1-quality.yml
.github/workflows/release.yml
CHANGELOG.md
docs/INDEX.md
docs/SKILL_CATALOG.html
docs/TECHNOLOGY.md
docs/USER_GUIDE.md
docs/ai/EVENTS.jsonl
docs/ai/decisions.jsonl
docs/ai/tests/test-runs.jsonl
docs/issues/CHANGE-DRAFT-release-command-finish.md
docs/product/release-command-finish.md
docs/skill-catalog-data.json
docs/specs/SPEC-DRAFT-spec-release-command-finish.md
tests/skills/aai-win-dispatch.Tests.ps1
tests/skills/lib/prompt-diet-ledger.sh
tests/skills/suite-map.yaml
tests/skills/test-aai-docs-audit.sh
tests/skills/test-aai-learned-routing.sh
tests/skills/test-aai-pr-preflight.sh
tests/skills/test-aai-prompt-diet.sh
tests/skills/test-aai-release-notes.sh
tests/skills/test-aai-release.sh
tests/skills/test-aai-sweep-parallel.sh
```

Read the frozen spec, intake, canonical guide/role/subagent contract, orchestration instructions, technology contract, learned rules, both independent Validation reports, checked remediation/R2 handoffs, producer R/platform and companion evidence, and remediation RED/GREEN evidence. The frozen Platform evidence and sequencing gate expressly permits this independent review before a later owner evidence-staging decision. Review placement supplies no PR readiness, platform waiver or commit/push authority.

## Blocking code findings

### CR-1 — Refuse unavailable release history instead of treating local tag absence as clean

**BLOCKING**, `.aai/scripts/release-finish.mjs:109` (also audit consumption at line209).

`audit()` runs local `git describe --tags --abbrev=0 <remote-base-sha>` and returns `[]` for every nonzero exit. A full-history clone made with `--no-tags`, a shallow clone, or a checkout lacking the previous release tag can therefore skip all historical shipped-change checks. Authoritative base-object lookup does not repair this: it fetches only when the commit object is absent, with `--no-tags`. The presence of the previous tag on origin is never considered.

The scratch probe used the existing real Git fixture and unchanged helper. With local `v0` present, audit prints `#299 feat: shipped 299` for an unnoted `.aai/scripts/omission.mjs` change. After deleting only the disposable local `v0`, origin still reports `refs/tags/v0`, but the same online audit exits0 with empty stdout. A separate confirm probe then exits0, makes exactly one merge call, publishes `v1`, and reports complete. The merged file is `change 299`; the published notes contain only alpha/#101 and beta/#102, with no #299. This proves a release mutation and publication bypass, not merely an incomplete diagnostic.

Fix the history boundary using authoritative evidence; distinguish a proven first release from unavailable history/tag metadata. Preserve write-free preview and no-tracking-ref/FETCH_HEAD writes during confirm. Add a real no-tags/partial-history regression with a prior remote release and a genuinely unnoted shipped PR; require refusal before creating release refs/PR or obtain and audit the verified history safely.

### CR-2 — Bind final synchronization to the selected base branch and head

**BLOCKING**, `.aai/scripts/release-finish.mjs:151` (checkout selection/checks at lines140–150).

`syncBase()` selects a worktree by its initial branch, reads its HEAD/status, then issues `git merge --ff-only <merge>` in that directory. It never binds the mutating operation to the selected branch/head. If another process switches that worktree to an existing feature branch after selection, Git merges into that feature branch. The helper unconditionally prints `Base: synced` and records `synced`.

A scratch Git wrapper inserted an actual `git checkout -q feature` immediately before the production `merge --ff-only` command. No production source was changed. The fixture started main and feature at `00e7088603a46713d4548bd78ca2b7c8f9c7ec8c`; the helper exited0 and reported complete/Base synced. Feature advanced to the release merge `282103f297c5d6a75c08d57ad262f210e49b9366`, main remained at the original SHA, and the checkout remained on feature. Thus the wrong branch and checkout were modified and the success record is false. This is a local checkout race, distinct from the explicitly accepted remote-base/GitHub-merge race.

Use a guarded synchronization approach that refuses a changed checkout/head and cannot apply the operation to a foreign branch; verify the intended base branch and resulting HEAD before recording success. Add an actual branch-switch/moved-head boundary regression that verifies both branches and caller bytes.

## Specification and test walk

Calls below separate source/test support from missing final evidence. A locally reproduced implementation violation is non-compliant; a required execution with no proof is cannot-verify.

| AC | Call | Evidence |
|---|---|---|
| Spec-AC-01 | non-compliant | Shared classifier, old/new modes and authoritative base reads are implemented at helper108–130/166–176; CR-1 proves unavailable tag/history bypasses the required audit and allows publication. |
| Spec-AC-02 | compliant | Identity133–136, required checks178–186 and merge262–273 retain required-check gates, exit8 watcher handling, observed-base rechecks and pinned head. Producer R internal006/010/016/017 demonstrates gates and explicitly records the external last-observation race. This is code-review support, not a fresh full Validation PASS. |
| Spec-AC-03 | cannot-verify | Helper278–280 verifies successful merge-SHA workflow, peeled tag and all notes before cleanup. Actual workflow error propagation fix and TEST022 are supported by remediation RED/GREEN; original independent F2 publication absence remains unattributed and current full run did not launch. My bounded positive fixtures do not resolve that intermittent history. |
| Spec-AC-04 | non-compliant | Durable runtime-file journal/claim primitives, eleven transition controls and leased remote/local deletions are present. CR-2 violates moved-head/feature-caller preservation and truthful base synchronization. |
| Spec-AC-05 | cannot-verify | Required real Windows5.1/Windows7 and hosted Linux20 evidence absent. Existing macOS Pester135 and local Linux native/20-run evidence cannot satisfy those exact platforms. |
| Spec-AC-06 | cannot-verify | Profile/map/import closure, prompt247-byte accounting, catalog updates and producer nine companions are present. F1/F3 targeted corrections preserve assertions. Current full suite remains unexecuted and this review finds blockers. Draft product lifecycle remains honest. |

| Frozen TEST | Existence / evidence assessment |
|---|---|
| TEST-001 | Actual historical exemption/missing-note/blank-marker controls exist as internal004/005. Producer R green; original independent run passed them. Missing-tag boundary is not covered and fails CR-1. |
| TEST-002 | Actual executable add/delete/chmod, detached/stale caller and benign remote base controls exist in internal016/005. Producer R green; independent full internal016 benign positive failed F2. Targeted post-correction pass does not supersede unresolved F2. |
| TEST-003 | Actual missing-object preview/ref/FETCH_HEAD preservation and confirm snapshot controls exist in internal016; producer proof exists. It verifies the remote commit object, not availability of the release-history tag boundary (CR-1). |
| TEST-004 | Deny-default transport arrays/values and exit8 pending watcher exist in internal006/010. Producer green proof exists; malformed/empty/transport arms are registered. |
| TEST-005 | Separate-origin CI-time base movement and final-observation-window push exist in internal016/017. Producer green log explicitly records the latter as an external limit, not a refusal. |
| TEST-006 | Actual release.yml shell and two-section notes/tag validation exist in internal007/010 and legacy030. Remediation internal022 proves real ENOENT/gh-exit7 propagation and retry. Original F2 remains unknown. |
| TEST-007 | Eleven actual stage interruptions/resumes, foreign identity and completed rerun controls exist in internal011/012; producer R green. Claim concurrency/killed-owner controls020/021 add real process coverage. |
| TEST-008 | Expected-head deletion argv, real lease race and dependent/moved branch refusal exist in internal008/010; producer R green. |
| TEST-009 | Dirty detached/feature worktree, hidden edits, divergence, no-base/manual/offline/dry-run controls exist in internal009/012 plus legacy cases; producer green. Concurrent checkout/head change at final sync is absent and fails CR-2. |
| TEST-010 | Actual native helper normal/empty/error controls exist in function701 and Pester. macOS135 and local Linux source proof exist. Actual Windows5.1 and Windows7 execution is missing: pending. |
| TEST-011 | ps1-quality workflow contains20 repeated actual test_033 calls with skip rejection and completed20 assertion. Local Docker20 is supporting evidence only; actual hosted run/head/raw proof is missing: pending. |
| TEST-012 | Internal015 executes actual copied helper/gate/runtime-file closure and sentinel consumption, plus exact core classification and documentation checks; producer proof exists. Two retired notes-only absence assertions are explicitly replaced while live notes functional checks remain. |
| TEST-013 | Declared nine companion suites have producer green results; copy closure, routing, selector, prompt accounting and catalog inventory changes are in scope. Targeted lifecycle and heartbeat corrections have their own RED/GREEN. No fresh complete current-tree full proof exists. |

Internal runtime case numbers differ from frozen split TEST numbers; this review used the mapping at test-aai-release.sh:1378 and actual assertions, not name equality. Removed remote open-only legacy functions are replaced by the bound completion/dirty/detached/remote/manual controls; other legacy regressions remain registered. No new universal-negative test-name finding or bespoke replacement for runtime-file load/write/claim primitives was identified.

## Evidence and preservation

Both reviewer commands below completed with actual exit0 because their assertions intentionally prove the defects in the current source. All mutations occur in new disposable fixture repositories under the one authorized scratch directory. GitHub is a strict transport stub; commits, pushes, workflow shell, tags, and the branch switch use real Git. No shipping source, STATE, spec, ledger, index, Git staging, commit, push or external service was mutated.

```sh
PROJECT_ROOT=/private/tmp/aai-release-command-finish-integrated-worktree TMP_ROOT=/private/tmp/aai-finish-final-review-scratch bash .aai/scripts/aai-run-tests.sh node /private/tmp/aai-finish-final-review-scratch/probes.mjs
PROJECT_ROOT=/private/tmp/aai-release-command-finish-integrated-worktree TMP_ROOT=/private/tmp/aai-finish-final-review-scratch bash .aai/scripts/aai-run-tests.sh node /private/tmp/aai-finish-final-review-scratch/confirm-probe.mjs
```

The probe scripts reuse the actual fixture setup extracted from test-aai-release.sh's Node block before `const selected`, then append the independent scenarios described above. Source references continue to point at the unchanged integrated implementation. Evidence files:

| File under `/private/tmp/aai-finish-final-review-scratch/` | SHA256 |
|---|---|
| probes.mjs | 0bf8328329935f4aca3bfc6cb96162449f44c8988dbe033e7a741590a4583036 |
| probes.log | e9f92f62451412591e34e388300df5d3b0473c2ab28e6e4e89ea3722f9f85127 |
| confirm-probe.mjs | 60a684fcd75f3a317b02dcd7b94d3f7a9dd3bd3c8ce78de9b37e53b7a42e3503 |
| confirm-probe.log | ae3e87059aa300a52a93b88163852a98e93fd6d9ef672ffc8087bb7db6b00753 |

Post-probe verification: all29 source hashes equal `/private/tmp/aai-finish-r2-local-source.json`; all three ledger base prefixes remain byte-exact. `node --check .aai/scripts/release-finish.mjs` and `git diff --check` exit0. Runtime API existence probe confirms functions for used crypto randomBytes, process umask/kill, spawnSync, fs realpathSync/mkdtempSync, Atomics.wait, SharedArrayBuffer and String.replaceAll. These checks do not imply platform execution.

## Cannot verify and warning dispositions

- Actual Windows PowerShell5.1 and Windows pwsh7 native helper results and final-source provenance remain required.
- Hosted Linux20 final-source workflow evidence remains required. The spec's sequencing deadlock remains an owner decision after a concrete reviewed diff; this failing review is not authorization to stage/push/run CI.
- Current independent full-suite recovery and original F2 causal resolution remain unknown. Prior full result was105 pass/3 fail/0 skip, exit1. R2 full launch was explicitly rejected before a process existed; no exit code is invented. No denied full launch, process probe or outside-sandbox command was retried or worked around in this review.
- Live GitHub service behavior is not established by the transport fixtures. No live release is claimed.

**H6:** no NON-BLOCKING/WARNING findings were opened. Both CR-1 and CR-2 require remediation in-tree before merge/readiness; neither is accepted residual nor filed as a follow-up by this read-only reviewer. The documented remote final-base-observation race is an explicit scoped limitation, not a newly invented WARNING. Existing unsigned spec-amendment follow-up remains the parent's normal tracked contract-signoff work; this reviewer neither closes nor amends it.

## Next steps

Remediate CR-1 and CR-2 with actual failing-first boundary regressions; refresh affected evidence and obtain fresh independent review/validation. Preserve the original F2 report and the distinction between proven propagation fixes and its unknown root cause. Keep Validation non-PASS and platform rows pending until actual evidence exists. Return only the set-code-review command to the sole STATE writer. Stage this report with the eventual authorized scope commit so it does not orphan.

Review report finished `2026-10-14T17:46:40Z`; captured review duration `242` seconds. Initial canon read and final handoff checker time are outside this report interval.
