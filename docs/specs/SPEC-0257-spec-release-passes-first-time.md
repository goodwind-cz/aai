---
id: spec-release-passes-first-time
type: spec
number: 257
status: superseded
mutation_gate: v1
frozen_sha256: 117b35eb9fd7f12959a081930b106c5ae6df7a9b2768b35838a78e5e97fec460
ceremony_level: 2
capability: release-command-finish
links:
  requirement: release-passes-first-time
  rfc: null
  pr: []
  commits: []
---

# Release rollup compatibility and current-head CI results

> Superseded 2026-10-27 by owner split decision
> `docs/decisions/DECISION-release-passes-first-time-split.md`.
> Do not remediate this combined spec further. Children own the split
> scopes: `current-head-ci-reader` and `release-rollup-dry-run`.

SPEC-FROZEN: true

## Links

- Intake: docs/issues/CHANGE-0231-release-passes-first-time.md
- Technology contract: docs/TECHNOLOGY.md
- Product: docs/product/release-command-finish.md

## Implementation strategy

- Strategy: hybrid
- Rationale: TDD for reader discovery, rolled-tree execution, and latest-check selection; direct implementation for workflow wiring, classification, and product prose. A same-name stale failure and a missing language reader are behavioral regressions across multiple consumers.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: multi-surface PR work and destructive test fixtures warrant isolation; the primary checkout already has unrelated index and ledger edits.
- User decision: undecided
- Base ref: main (planning observation 12301faca3efa3910154e9a6d0217f53829b2e62)
- Worktree branch/path: assigned by Implementation Preparation.
- Inline review scope: .aai/scripts/release-finish.mjs, .aai/scripts/watch-ci.mjs, new release dry-run/check-selection helpers and their profile entries, .github/workflows/skill-suite.yml, tests/skills release/check-selection suites and suite-map.yaml, CHANGELOG.md, docs/product/release-command-finish.md, this spec and its intake, generated docs/INDEX.md, and this ride's append-only evidence.
- Code review required: true.

## Decisions and boundaries

D1. Add a read-only PR release dry-run job to the existing skill-suite workflow. It runs independently of ordinary suite impact selection and body-reuse decisions on every pull_request event accepted by that workflow; the existing aggregate gate requires its success. It does not publish, push, create a PR, edit a PR, merge, or tag. No automatic reruns of infrastructure failures.

D2. Use the release engine's production rollup transform, shared by extraction if needed, in a disposable independent Git clone. Preserve production BOM, newline and historical-section behavior. Preserve source refs, index and files byte-for-byte, except the explicitly requested generated report when untracked (tracked or symlink report destinations refuse); no linked worktree sharing the operator's refs. The clone must make the rolled content visible to runners that create further isolation clones from HEAD. On a tree with no rollable entries, report that fact explicitly and still exercise the discovered readers on the unchanged content. This is not a proof of behavior for a nonexistent new entry.

D3. Discover conservatively from tracked test sources mentioning CHANGELOG (case-insensitive), with explicit ownership of helper sources. The present inventory is 18 files: 15 shell suites, one Node test, one Pester file, and one shell ledger helper owned by a selected shell suite. Execute the complete selected runnable files, including fixture-only/comment false positives; no fixed allowlist of today's live readers and no per-test selector that could miss a newly added assertion in an existing file. A new direct reader in Node, shell or PowerShell must be discovered without editing a map. A matching helper must resolve to a runnable owner through normalized full literal identities in its language context (file-relative Node imports, root-relative literal source paths, recognized script-directory forms), or fail with its path; an unrelated same-basename reference never establishes ownership; do not silently discard it. Discovery is a lexical conservative bound, not a general static proof of arbitrary computed file paths. Document that residual explicitly.

D4. Execute Node with node:test, shell suites with the existing test-framework process/isolation conventions, and PowerShell tests with Pester and EnableExit semantics. Missing interpreter/module, unowned reader, timeout, runner failure, or selected-file failure is a named nonzero result; never a green skip. All selected files remain scheduled even when one fails. For a failed rolled run, execute the corresponding ordinary snapshot as a diagnostic and distinguish rollup-only from baseline failure. A finite total budget can exhaust before all scheduled executions finish: retain the full selected inventory, completed results and explicit pending file/arm identities, report budget-exhausted and diagnostic-incomplete rather than inventing a baseline conclusion, and exit nonzero; either remains nonzero for this CI job. Output each reader path, disposition, duration and a final summary. Bound child processes and reap them. Scrub Git override and credential variables in the new executor, disable push remotes and credential helpers in scratch copies, and do not fetch/install dependencies from inside tests.

D5. Keep same-name reruns from deciding current-head results. A single shared reader/normalizer is consumed by watch-ci and every release-engine required-check read. Resolve and bind the PR head SHA, obtain check identity/order from authoritative GitHub data, reject other-head observations, and select only the newest run of each check name. Do not use response order or success preference. Pagination is mandatory. A newer pending run supersedes an older terminal failure; newest failure or cancellation remains failure. Stale successes cannot mask newer failures. Actions observations use one total ordering key: authoritative workflow creation time, workflow ID, then check-run ID. Metadata is fetched once per workflow per observation, including completed jobs, so queued and started jobs use the same clock. External check runs and legacy statuses use their own consistent identity clocks; ambiguous mixed provenance refuses. A head change during observation requires a new consistent read or a named refusal, never PASS on mixed heads. Preserve legacy status-context handling and --required filtering; malformed/ambiguous identities and transport failures cannot become PASS. The release engine additionally binds its expected journal head. Existing registration grace, required-context presence, timeout, skipped-check and merge-queue semantics remain intact. Avoiding a body edit alone does not establish the watch-ci acceptance criterion, so this scope fixes the reader rather than relying on edit timing.

D6. New .aai files receive exactly one entry in .aai/system/PROFILES.yaml. Update suite-map ownership for the new scripts/tests. Product documentation describes the dry-run coverage, current-head/latest-run rule, missing-tool behavior and measured runtime. Do not promise immunity to infrastructure failures or arbitrary untracked/computed-path tests.

## Planning measurements and feasibility

Observed on 2026-10-27 at main 12301faca3efa3910154e9a6d0217f53829b2e62:

- `rg -l CHANGELOG tests --glob '*.mjs' --glob '*.sh' --glob '*.ps1'` returns 18 files. Runnable shell candidates are canon, deslop, doctor, doc-number-reservation, feedback-upsert, hygiene-pack, learned-routing, merge-policy, orchestration-mode, prompt-diet, release, release-notes, role-output, update and win-fallback. Node: tests/skills/lib/recheck.test.mjs. PowerShell: tests/skills/aai-win-dispatch.Tests.ps1. Helper: tests/skills/lib/prompt-diet-ledger.sh, owned by prompt-diet.
- Existing measured CI weights in tests/skills/suite-weights.tsv sum to 499 seconds for those 15 shell suites (five historical runs per row); four-way LPT gives an ESTIMATED 158-second makespan, not a measurement of the new job. A serial 499-second extra stage is rejected. Run the job concurrently with existing verification and use the existing bounded-width shell runner.
- The actual current Node TEST-2819/TEST-2821 baseline is 2/2 PASS, node:test duration 53.39925 ms, via the canonical wrapper. The complete Node file subsequently passed 85/85 in 136.407 seconds (wrapper exit 0); the wrapper also reported overview-data.json/overview.html changes during the run, so source-preservation is NOT established by this baseline. Parallel scheduling must include Node rather than append its 136 seconds after shell execution. PowerShell and Pester 5.7.1 are installed locally.
- Local history includes 734339e0 (pre-#505 with unreleased-only Node lookups), 20ee3591 (#505 correction), 44e1cabb (#506 recovery), and 16a9947c (#504 release). Read-only local `gh pr view 504/506` could not connect to api.github.com. The orchestrator retrieved actual PR #504 check data via the connected GitHub tool: head 110236e4f9cecb596353e533d70e58b7d97b6418, failed aggregate job 122067316214 in cancelled run 40467767696, then successful aggregate job 122068630843 in run 40467794563 on that same head. Runtime payload: /tmp/release-first-pr504-checks.json. Preserve a minimal provenance-bearing replay fixture from this payload. The #506 engine change drove the re-cut of release PR #504; do not confuse #506 itself with the failed release PR.
- Performance evidence is staged to respect the canonical commit/PR gate. Before Validation PASS, execute and time the complete discovered corpus on local ordinary and rolled snapshots, record each result, total wall time, interpreter versions and machine context, and prove bounded concurrent scheduling. Local evidence establishes rollup compatibility and measured local cost only. Ten minutes remains the green-path operational target. The amended whole-job ceiling is twenty minutes to accommodate slow failure diagnostics: an explicit1080-second executor budget reserves120 seconds for setup/final report/upload within1200 seconds. The540-second per-reader bound is unchanged. This is a finite budget, not a guarantee that arbitrary multiple timeout waves finish; exhaustion retains named partial evidence and remains nonzero. Reports checkpoint before execution and after every reader, including before ordinary diagnostics. After the authorized PR opens, observe its first complete hosted run: report dry-run wall time, runner-seconds where available, queue time, and added verification critical-path delay as max(0, dry-run completion time minus completion of the latest preexisting required verification dependency). A 60-second added-delay target is diagnostic: investigate/optimize an overrun without dropping coverage, and report unresolved delay at the merge checkpoint. Hosted latency/platform claims remain explicitly unverified until that observation; actual PR CI is not a prerequisite for opening the PR that produces it. No temporary PR, pre-validation commit or push is needed.

## Implementation measurement and remaining validation

The frozen implementation snapshot selected 22 runnable files (including the newly tracked rehearsal test itself) and completed 44 executions: ordinary wall 396.621728917s, rolled wall 392.794347333s, total 792.4144535s, peak active four. Machine: darwin arm64 27.0.0, 16 logical CPUs; Node v22.23.1, Bash 3.2.57, PowerShell 7.6.3 and Pester 5.7.1. Source tree SHA256 `25aa1c8b5023cf98ac90e83ec6358547f87c573f60f36cff008ca086cac98182`; raw index and refs preservation were also measured (`docs/ai/tdd/corpus-release-first-frozen.json`). This run failed four executions: hygiene's new cd-subshell count and release's obsolete consumer inference from `--repo`, on both arms. These fixture obligations were repaired after the frozen run; their targeted checks and the new suite must pass before handoff. This is not a final-tree corpus PASS. Independent Validation owns a fresh complete ordinary/rolled execution before it may close Spec-AC-05 or record Validation PASS. Hosted timing remains unverified until post-open CI.

## Acceptance Criteria Mapping

| Intake | Spec criteria | Verification and evidence |
|---|---|---|
| AC-001 | Spec-AC-01, Spec-AC-02, Spec-AC-03, Spec-AC-04 | Candidate discovery, planted Node/shell/Pester readers, actual CLI and workflow aggregate tests; stored RED/GREEN and mutation logs |
| AC-002 | Spec-AC-05 | Pre-PR complete-corpus ordinary/rolled local logs and timing; hosted timing observed after PR creation, with no inferred platform PASS |
| AC-003 | Spec-AC-06, Spec-AC-07 | Real reader-to-watch/release transport fixtures with head identities, reruns and paging |
| AC-004 | Spec-AC-08 | Scratch-clone replay of historical pre-fix and corrected Git trees plus historical-run-shaped transport replay |
| Companion obligations | Spec-AC-09 | Profile, suite ownership and product/CHANGELOG evidence |

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN a new tracked Node, shell or Pester test reads CHANGELOG, discovery SHALL select its complete runnable file without a map edit and SHALL name an unresolved matching helper as an error. | done | docs/ai/tdd/remediation-release-first-final-20261027.log | — | D3 |
| Spec-AC-02 | WHEN a test passes on the ordinary tree and fails after production rollup, the dry-run SHALL exit nonzero, name its file and classify the rollup-only failure for all three languages. | done | docs/ai/tdd/remediation-release-first-final-20261027.log | — | D2-D4 |
| Spec-AC-03 | WHEN dry-run succeeds, fails or times out, it SHALL leave source files/index/refs unchanged, clean its owned scratch resources, and SHALL NOT report missing tooling or baseline failures as success. | done | docs/ai/tdd/remediation-release-first-final-20261027.log | — | D2-D4 |
| Spec-AC-04 | WHEN any accepted PR event runs skill-suite, its aggregate SHALL require the release dry-run even for selected suites and body reuse; all selected language readers SHALL actually execute. | done | docs/ai/tdd/remediation-release-first-final-20261027.log | — | D1 |
| Spec-AC-05 | WHEN the full dry-run executes locally against current main plus this change, every selected reader SHALL pass and the report SHALL state complete-corpus ordinary/rolled wall times, per-reader results, machine/interpreter identity and bounded concurrent scheduling; hosted latency SHALL remain explicitly unverified until the post-open CI observation. | blocked | docs/ai/tdd/final-corpus-release-first.log | 2026-11-10 | Final-tree complete corpus remains an explicit independent Validation obligation after targeted fixture repairs. Post-open target and timing procedure in Planning measurements |
| Spec-AC-06 | WHEN a check name has superseded cancelled/failed runs on the current head, watch-ci and release required-check reads SHALL use only the newest run, waiting for pending and passing on success. | done | docs/ai/tdd/remediation-release-first-final-20261027.log | — | D5 |
| Spec-AC-07 | WHEN newest checks fail, identity is inconsistent, a head moves, a page is missing or the API fails, the shared reader SHALL preserve a named failure/pending/degraded outcome and SHALL NOT accept stale success. | done | docs/ai/tdd/remediation-release-first-final-20261027.log | — | D5 |
| Spec-AC-08 | WHEN historical pre-#505 tests run on their ordinary and rolled snapshots, they SHALL pass ordinary and fail rolled by filename; corrected tests SHALL pass rolled, and the #506-shaped same-head rerun timeline SHALL finish without stale-cancel refusal through both consumers. | done | docs/ai/tdd/remediation-release-first-final-20261027.log | — | Provenance disclosed |
| Spec-AC-09 | New shipped helpers SHALL be profile-classified and suite-mapped, and release product documentation SHALL state actual coverage, limitations and measurements. | done | docs/ai/tdd/remediation-release-first-final-20261027.log | — | D6 |

## Test Plan

Each command below runs through `bash .aai/scripts/aai-run-tests.sh` on POSIX, or the canonical PowerShell wrapper on Windows. The proposed new suite `tests/skills/test-aai-release-first.sh` may delegate to a Node test file; stable TEST IDs remain unchanged. Its selector must dispatch real executed cases, not merely match prose. Tests cross the real CLI/runner boundary; gh is a fixture transport, not a stub of the selection function.

| TEST ID | Spec-AC | Type | File path | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-release-first.sh | Add new readers of each language and a helper; prove complete file selection, ownership and named refusal | Remove PowerShell candidate discovery and observe the Pester candidate disappear; target `.aai/scripts/release-dry-run.mjs`; `sed:s/ps1\)/psx)/` | green |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-release-first.sh | Real Node reader ordinary PASS / rolled FAIL, file named; dual-form control passes | Bypass the production rollup before executing the reader; target `.aai/scripts/release-dry-run.mjs`; `sed:s/fs.writeFileSync\(f,result.content\)/fs.writeFileSync(f,fs.readFileSync(f,'utf8'))/` | green |
| TEST-003 | Spec-AC-02 | integration | tests/skills/test-aai-release-first.sh | Real shell reader ordinary PASS / rolled FAIL through nested isolation, file named | Run shell tests from the original commit instead of the rolled snapshot; target `.aai/scripts/release-dry-run.mjs`; `sed:s/clone\(base,cwd\)/clone(arm==='rolled'?path.join(tmp,'ordinary'):base,cwd)/` | green |
| TEST-004 | Spec-AC-02 | integration | tests/skills/test-aai-release-first.sh | Actual Pester reader ordinary PASS / rolled FAIL, file named | Ignore Pester FailedCount/exit status in the runner; target `.aai/scripts/release-dry-run.mjs`; `sed:s/resolve\(timedOut\?124:code\?\?125\)/resolve(exe.includes('pwsh')?0:timedOut?124:code??125)/` | green |
| TEST-005 | Spec-AC-03 | integration | tests/skills/test-aai-release-first.sh | Source hashes/ref/index controls on success/failure/timeout; missing tool and baseline failure nonzero; no-entry tree reported | Convert missing-tool or timeout result to successful skip; target `.aai/scripts/release-dry-run.mjs`; `sed:s/resolve\(timedOut\?124:code\?\?125\)/resolve(missing?0:timedOut?0:code??125)/` | green |
| TEST-006 | Spec-AC-04 | integration | tests/skills/test-aai-release-first.sh | Workflow job and real CLI execute all three planted readers; aggregate rejects failed dry-run in full/selected/body-reuse modes | Remove dry-run from the aggregate dependency/result check; target `.github/workflows/skill-suite.yml`; `sed:s/release-notes, release-dry-run\]/release-notes]/` | green |
| TEST-007 | Spec-AC-05 | integration | tests/skills/test-aai-release-first.sh | Run complete ordinary/rolled corpus and validate duration/result coverage and bounded concurrency; label hosted latency unverified before CI | Omit an executed reader from the duration/result report and observe the coverage assertion fail; target `.aai/scripts/release-dry-run.mjs`; `sed:s/notes,results,wallSeconds/notes,results:results.slice(1),wallSeconds/` | green |
| TEST-008 | Spec-AC-06 | integration | tests/skills/test-aai-release-first.sh | Feed old failed/cancelled aggregate then newer pending then success through watch-ci and release required-check paths | Reverse the common lexicographic ordering relation and keep the oldest same-name run instead of newest; target `.aai/scripts/lib/github-checks.mjs`; `sed:s/a.order\[i\] > b.order\[i\]/a.order[i] < b.order[i]/` | green |
| TEST-009 | Spec-AC-07 | integration | tests/skills/test-aai-release-first.sh | New failure after old success; other head; head-move; pagination; required-only filtering; malformed and transport-error cases | Drop the head-SHA match predicate in check collection; target `.aai/scripts/lib/github-checks.mjs`; `sed:s/if\(c.head_sha!==head\)/if(false)/` | green |
| TEST-010 | Spec-AC-08 | integration | tests/skills/test-aai-release-first.sh | Replay pre-#505 / post-#505 Git objects in independent scratch clones and captured #504 rerun data from the #506 re-cut flow through real consumers | Run historical checks against the unrolled snapshot for both arms; target `.aai/scripts/lib/release-rollup.mjs`; `sed:s/content:bom\+\[...lines.slice\(0,first\)/content:source,ignored:bom+[...lines.slice(0,first)/` | green |
| TEST-011 | Spec-AC-09 | integration | tests/skills/test-aai-release-first.sh | Profile inventory, suite ownership and product coverage truth | Remove new helper from its profile classification; target `.aai/system/PROFILES.yaml`; `sed:s/  - .aai\/scripts\/lib\/github-checks.mjs\n//` | green |

## Verification and evidence contract

- Run each TEST selector, the complete new suite, existing release suite, existing watch-ci tests in orchestration-dispatch, recheck tests, CI selection/body-reuse tests, and layer-profiles through the canonical wrapper. Use existing impact selection for non-regression; record the exact selection and all failures.
- TEST-001..005 and TEST-008..010 require stored RED evidence before implementation under docs/ai/tdd/, GREEN evidence, and mutation-run evidence in docs/ai/tdd/spec-release-passes-first-time/mutation-TEST-xxx.txt. The workflow, corpus/timing and classification rows also require their declared mutation proof before close under the hybrid contract. A missing future CLI is an initial RED, but final mutation controls must demonstrate that assertions detect behavioral defects.
- Pre-PR runtime evidence includes full-corpus reader inventory, each exit and duration, ordinary/rolled total wall times, current Git SHA or scoped tree identity, machine/interpreter versions, concurrent-runner bound, and source-tree preservation hashes. Do not infer hosted Linux/Windows behavior from a local macOS run. Actual Pester execution is required; a skipped PowerShell probe cannot close the all-languages AC. After the PR opens, add the observed CI run identity and timestamps to the final delivery report, retaining the local evidence unchanged. A missing/incomplete hosted run is reported as unverified, never converted to PASS.
- Historical replay records exact resolved SHAs, ordinary and rolled output, the two regression test IDs and filenames, and corrected positive controls. Stored historical Git content is authoritative for code history. Use the captured #504 check identities above for the same-head cancelled/new-success replay, recording source URLs/IDs and retrieval date. Synthetic pending/head-move variants remain explicitly labeled fixture extensions. No live release action is needed or authorized by replay.
- Each final validation report names ref release-passes-first-time, Spec-AC/TEST links, commands, exit codes, proof paths and diff identity, and includes the required admissible aai-outcome-v1 block. Every AC must be truthfully terminal before PASS.

## Registry items closed by this scope

None.

## Follow-up exclusions

- fu-assertions-pinned-to-one-world: this adds a release-rollup behavioral check, but does not lint moving-ref or last-index assertions; broader item remains open.
- fu-release-preflight-scrubbed-env: the NEW CI executor uses independent clones and scrubbed environment; the existing release-time Node preflight migration is separate from this intake and remains open unless explicitly included by a recorded amendment.
- fu-release-unjournaled-recut-merged-old: journal/cleanup race is out of scope.
- fu-platform-adapter-watch-ci and fu-platform-adapter-release: this change preserves GitHub-only support; cross-platform adapters remain open.
- Other release notes/audit/PS liveness/merge-history/grace issues remain outside dry-run and check-run identity behavior.

## Residual risks

Lexical reader discovery cannot prove computed-path or opaque helper reads. CI timing varies with runner capacity and queueing; the post-open within-run critical-path delta is a diagnostic observation, not a pre-PR acceptance gate or an SLA for GitHub. There remains a check-registration race before any newer run is visible; this change chooses the newest observed run and does not predict future events. Platform-specific infrastructure failures remain operator-rerun territory. Existing release-time preflight environment/shared-ref risks are explicitly not claimed fixed.

## Constitution deviations

None.

## Independent Validation remediation

The first independent Validation failed; its report and artifacts remain unchanged. Remediation adds cloned leaf/ancestor symlink counterexamples, one transitive workflow ordering across all six response permutations and queued workflows, and explicit TAP output for Node readers. The historical fixture now includes actual workflow creation metadata retrieved from GitHub, not invented timestamps. TEST-076 checks the measured one-second deadline after the watcher settles, including a controlled 200ms API response, rather than requiring a machine-dependent minimum poll count. The incomplete sync-seed boundary is TEST-788 PowerShell (earlier progress text saying TEST-777 was stale); targeted verification does not replace the still-owed fresh full sweep. Spec-AC-05 remains unresolved until independent corrected-tree complete-corpus evidence exists, with Review-By 2026-11-10.

## Production runtime policy remediation

Round-two independent production-default evidence completed 42/44 executions; the release file exceeded the old 300-second per-reader cap on both arms. A separate complete release-reader run on supported Node 24.19.0, with process access and no concurrent corpus/framework, passed in 464.411661875 seconds (`docs/ai/tdd/remediation2-release-alone-20261027.json`). The production default is now 540 seconds per reader. All discovered readers are dispatched in descending order of existing suite-weight estimates, with maximum-known fallback for unweighted readers and an explicit named lexical fallback if weight data is unavailable or malformed. Scheduling changes order only, never membership, language coverage or complete-file execution. Reports expose the effective reader bound and estimated dispatch order separately from actual measured durations. At that runtime remediation, the whole CI job ceiling remained ten minutes and the subsequent complete rolled-only rehearsal passed; the failure-path ceiling is superseded by the explicit review remediation below. This runtime-policy adjustment does not itself establish hosted latency, setup/queue overhead, the sixty-second added-delay diagnostic target or independent Validation PASS.

The production-default rolled-only rehearsal on the frozen runtime source passed all 22 readers with no overrides: four jobs, peak active four, 540-second reader cap; rolled arm 519.157193625 seconds, executor total 522.418193167 seconds and canonical wrapper command 523.650773209 seconds. The release reader passed in 474.32500725 seconds. Evidence: `docs/ai/tdd/remediation2-production-default-20261027.json` and `remediation2-production-default-command-20261027.json`. Canonical before/after source fingerprint was identical (`965440e48dc3c43ac245e97f52d0df8a4d0f1696083d9e1991d9200341ecee0d`); executor also attested source files/index/refs preserved. The wrapper measurement leaves 76.349 seconds below the ten-minute ceiling on this local host; hosted setup/upload overhead and platform speed remain unverified. This is complete local rolled-only runtime evidence, not a fresh two-arm corpus or independent Validation verdict. Only these measurement documents and their canonical amendment/index were edited after the frozen run.

## Review remediation — sole standing extension

First and only standing extension under owner wave-2-roadmap (2026-09-12): R1 literal-helper-identity-collision and R2 slow-failure-diagnostic-budget are introduced by, and inseparable from, this new executor. No further extension is authorized. Review evidence is `docs/ai/reviews/review-20261027T155520Z.md`; failing-first assertions are retained with an accepted classified companion in `docs/ai/tdd/remediation3-review-red-classified-20261027.log`.

Resolved literal ownership now compares full normalized paths; unknown/computed references remain uncertainty, never basename proof. The failure diagnostic uses a1080-second total executor budget inside the1200-second workflow ceiling. Both540-second reader arms fit that allowance; setup/upload share the remaining120 seconds, which is an explicit allowance, not a hosted measurement. Ten minutes remains the unchanged green-path target. A larger population of slow or timing-out files can exhaust the budget: preserve all inventory and per-arm pending identities, checkpoint completed output before diagnostics, classify missing baseline evidence as diagnostic-incomplete, reap active children and return nonzero with budget-exhausted. Coverage is neither silently discarded nor called PASS when incomplete. `--both` uses the same total budget. Hosted timing remains unverified. The generated report is the sole named untracked source output; source-preservation proof excludes only that exact path and refuses tracked/symlink report targets.

Independent Validation `VALIDATION-20261027T145016Z-release-passes-first-time.md` passed44/44 corpus executions and115/115 framework suites on the pre-review-remediation source. Those successful immutable records remain valid observations of that snapshot, not proof of these later changes. Fresh changed-boundary and CORE verification is required for this remediation; no repeated full115-suite claim is made here.

Checkpoint follow-through verification: source-tree report directory ancestors and broken symlink leaves refuse before writes; external directory aliases into source also refuse. A budget-killed ordinary execution remains pending and diagnostic-incomplete, never baseline-failure. The13-suite selected+CORE run passed with every suite isolated, fully seeded and attested clean; after these last same-boundary corrections, the complete affected release-first suite passed11 selectors/22 executed cases with zero failures/skips. The wrapper retained its known report-only diagnostic for the framework-owned test-runs ledger append; this was not suppressed or relabeled as a suite failure. The TEST001 mutation now targets the discovery alternative `ps1)` precisely: its old generic first-match spelling hit a newly earlier normalization branch and stayed green, which is preserved as proof-staleness evidence rather than counted RED. These are fix-verification observations, not an independent Validation or Review verdict.
