---
id: smaller-node-core-and-faster-feedback
type: rfc
number: 17
status: implementing
umbrella: true
links:
  spec: null
  pr: []
  commits: []
---

# RFC: A smaller Node.js core and faster development feedback

## Context

The owner asks for an independent assessment of AAI: reduce duplicated Bash and
PowerShell logic, shorten tests and development cycles, consume fewer tokens,
and improve stability, autonomy, and usability. This RFC records an analysis
and a proposed direction; it does not authorize or implement a runtime rewrite.

Assessment date: 2026-10-21, Europe/Prague. Local baseline:
`71c7475a137793622188112d47b54c9a57adc71e` on main. Existing unrelated intake and
index edits were present before this analysis. Counts below include comments
and blank lines; they measure maintenance surface, not executable complexity
or a line-by-line duplicate detection result.

### Evidence from the current tree

| Observation | Measurement | Evidence and implication |
|---|---:|---|
| Runtime scripts | 116 MJS files / 61,367 lines; 24 shell files / 8,628 lines; 19 PowerShell files / 6,580 lines | Tracked files under `.aai/scripts/`, recursively. Node already holds most logic. |
| Shell/PowerShell counterparts | 18 pairs / 12,442 combined lines | Matching stems, not 12,442 proven duplicate lines. There is substantial parallel implementation to inspect and consolidate. |
| Largest counterpart surfaces | hook installer 2,410 lines; sync 2,126; test wrapper 1,900 | Migration should target common policy and filesystem operations; process and shell semantics need real platform adapters. |
| Shell tests | 123 files / 147,357 lines | Tracked `.sh` files under `tests/`, including helpers. There are 109 discoverable `test-aai-*.sh` suites. |
| Large suites | docs-audit 8,820 lines; hygiene-pack 5,987 | Both are always-on core suites in `tests/skills/suite-map.yaml`. Small changes pay their regression-suite cost. |
| Test framework | 2,115 shell lines | `iso_create` clones the complete repository per suite with a separate Git directory, then seeds working-tree differences and local runtime inputs. |
| Existing testable core | docs-audit core exports 28 declarations | `.aai/scripts/lib/docs-audit-core.mjs` already exposes an API; a migration pilot can use it without inventing a new runtime architecture. |
| Prompt inventory | 68 prompt files / 365,041 bytes | Inventory is not the context used on every task. |
| Actual Validation dispatch prefix | 59,764 bytes | Output of `canon.mjs build --role Validation --ref HEAD`; includes four sections, including all of `LEARNED.md` (27,638 bytes). These are bytes, not measured billable tokens. |
| Agent adapters | 42 skills in each of four trees | `.agents`, `.codex`, `.claude`, `.gemini`; these are discovery adapters with some provider differences, not four independent implementations of every skill. Generate applicable surfaces from one registry. |
| Impact selection replay | 32 selected / 8 full, over the latest 40 first-parent commits | Current selector replay: 4 shared-library, 3 unmapped, 1 protected-surface full fallbacks. Selected sets range 7–54, median 17 suites. This is a current-policy replay over commit diffs, not a reconstruction of historical CI decisions. |

The architecture already contains useful simplifications: shared Node modules,
deterministic dispatch, canonical prompt assembly, L0–L3 ceremony, bounded
parallelism, weighted full-run sharding, companion-suite selection, and restricted
CI result carry-forward. Prior performance work removed nested suite reruns and
batched expensive checks. Reintroducing these as new ideas would waste a cycle.

Relevant prior work: SPEC-0206 (sharding and measured deferral of library-graph
narrowing), SPEC-0213 (carry-forward), SPEC-0214 (Windows timing/filter fixes),
SPEC-0215 (nested-suite removal), DEBT-0011 (hot spots), SPEC-0186 (canon assembly),
and PRD-0001 (simple and friendly operation).

### Fresh CI evidence

Read GitHub job metadata and logs on the assessment date. These are individual
observations, not a statistical performance baseline. Job times include setup;
suite times are the framework's own reported wall times, not CPU seconds.

| Run | Observation |
|---|---|
| [39497742559](https://github.com/goodwind-cz/aai/actions/runs/39497742559), sync PR | Selected mode: 22 suites, one runner, job 516 s (8:36). docs-audit 223 s, release 211 s, sync-seed 201 s, metrics 173 s, hygiene-pack 119 s. |
| [39494880782](https://github.com/goodwind-cz/aai/actions/runs/39494880782), spec evidence closeout | Selected mode: 8 suites, job 163 s. docs-audit alone reports 148 s; hygiene-pack 87 s. |
| [39393915564](https://github.com/goodwind-cz/aai/actions/runs/39393915564), successful nightly | Full mode: four job durations 390, 195, 190, 168 s. Slowest/mean = 1.65. The slowest shard includes docs-audit 221 s, sync-seed 212 s, release 160 s. |
| [39499112150](https://github.com/goodwind-cz/aai/actions/runs/39499112150), current local main SHA | Full run fails in `aai-pricing`: historical model ID `cursor-grok-4.6-high` resolves to unknown. This analysis does not establish which change introduced the mismatch. |

The stored weight for `aai-release` is 10 s, versus 160–211 s in the inspected
logs. The weight file has 106 rows while discovery finds 109 suites; missing
weights degrade scheduling, not membership. Selected-mode CI sorts names and
uses one runner; full-mode CI distributes across four runners. Fewer selected
tests therefore need not mean a shorter wait.

An illustrative four-worker simulation of the 22 observed suite durations gives
487 s in alphabetical order and 396 s longest-first, before setup and isolation
overhead. This is a scheduling hypothesis (about 19% in this model), not a
promised improvement: concurrency changes can alter actual suite durations.

The successful nightly also reports `aai-state SKIP (39.0s)`. The suite has
whole-suite `exit 42` paths when real local `STATE.yaml` is absent. A green job
is therefore not evidence that every state scenario executed. Preserve the
distinction between passed, skipped, failed, and not executed.

### Diagnosis

AAI's maintenance cost is amplified by coupling between policy text, runtime
operations, fixtures, repository history, telemetry, and verification ceremony.
Shell mirrors are one visible part. Merely translating them would leave the
largest test and workflow costs in place.

Specific mechanisms:

- Many behavior checks cross a CLI boundary and build filesystem/Git context
  even when a direct function call would suffice. Repeated Node startup is one
  candidate cost; its share has not been measured in this analysis.
- Isolation protects against real historical incidents. Making every suite
  reproduce a complete working repository is expensive infrastructure around
  tests that should often need only input objects or a tiny temporary directory.
- `test-aai-hygiene-pack.sh` pins literal prompt sentences, including historical
  merge wording. Text edits can trigger widespread test maintenance even when
  the intended contract is unchanged. Preserve checks of required safety rules;
  reduce checks of incidental wording and implementation shape.
- `SKILL_VERIFY.prompt.md` requires reruns at completion boundaries and says to
  rerun a whole suite when blast radius is uncertain. That policy is conservative
  but conflicts with efficient reuse unless input identity and validation
  responsibility become explicit. Existing CI carry-forward only handles a
  restricted class of later documentation/ledger changes.
- Several shape-specific YAML parsers exist because the technology contract
  forbids dependencies. The format is human-friendly, but a custom dialect in
  every consumer creates correctness and testing costs.
- Operational history is loaded as standing agent context. `LEARNED.md` alone is
  about 46% of the measured Validation prefix; byte reduction here is a stronger
  starting hypothesis than shortening individual status messages.

## Proposal

Adopt an incremental Node-first architecture, with a small public interface,
importable domain functions, explicit effect adapters, and proportionate
verification. Each migration removes its superseded implementation after parity
is established. Avoid an indefinite second stack.

### 1. Make one implementation own each behavior

- Keep dependency-free ESM for the first migrations. There is no immediate need
  for TypeScript, a build pipeline, a daemon, or a new orchestration framework.
- Move common sync/update, hook policy, manifest, and filesystem behavior into
  importable Node modules. CLI frontends handle arguments, output, and exit codes.
- Retain small `.sh` and `.ps1` launchers for existing command compatibility and
  stable approval prefixes. Keep actual platform-specific behavior in named
  adapters: process groups, Windows process trees, shell quoting, bootstrap
  before Node is installed, and permissions.
- Migrate process supervision last. Node's test runner does not guarantee cleanup
  of arbitrary detached subprocess trees; preserve and test the current contract.
- Extend the existing profile/manifest machinery to produce provider wrappers;
  avoid adding another overlapping registry. Provider-specific descriptions and
  discovery paths remain supported. Generated files carry a source marker and
  are checked for drift instead of being hand-maintained in four places.
- Publish a supported Node floor and test it. Recommend Node 24 LTS for the next
  baseline, with a compatibility decision for downstream Node 22 users. Current
  workflows pin Node 20, which the official release table lists as EOL on the
  assessment date. Do not silently drop an installed downstream runtime.

### 2. Separate validation of data from regression tests of the validator

Create three execution classes using the existing selection mechanism:

| Class | Typical check | Isolation |
|---|---|---|
| Fast logic and contracts | Parse, classify, map, plan, schema, invariant | `node:test`, direct imports, data fixtures; no repository clone |
| CLI and filesystem integration | Arguments, exit codes, stdout/stderr, file writes, real Git behavior | Temporary directory; tiny self-owned Git repository only when required |
| System and platform | Sync into downstream, hook installation, process cleanup, end-to-end recovery | Dedicated isolated checkout and actual OS coverage |

On a documentation edit, run the real document validator on changed documents
and the inexpensive required corpus-wide identity/link checks. Do not rerun
every fixture proving how the validator itself behaves unless its implementation,
schema, policy inputs, or dependencies changed. A corpus check and a regression
suite of the corpus checker answer different questions.

Pilot with docs-audit using its existing exported functions; then split
hygiene-pack into stable contract checks and slower integration scenarios.
Retain representative CLI boundary tests and real-corpus validation. Keep
independent adversarial cases for state, deletion, and permission boundaries.
Migration must map old behavioral assertions to replacement checks; deleting
tests because they are slow is not the proposal.

Require isolation by construction for new tests. Do not share writable fixtures,
use linked worktrees as a substitute for independent Git state, or disable the
existing tripwire around unmigrated suites. Unit-level process isolation is not
a filesystem security sandbox.

### 3. Fix scheduling first, then make selection and reuse precise

Immediate changes with bounded scope:

1. Refresh duration weights from recent successful runs and schedule selected
   suites longest-first too. Benchmark both wall time and total runner time.
2. Let large selected sets use the existing shard path when measured duration
   justifies another runner. Keep tiny selected sets on one runner. Do not always
   allocate four runners just because full mode does.
3. Cancel superseded read-only PR verification runs for the same PR. Do not apply
   that cancellation policy to releases or externally mutating jobs.
4. Stop restarting expensive tests on a PR-body edit when only the release-notes
   decision depends on the body; keep an always-reporting aggregate gate and
   bind reused results to the correct source and policy inputs.

Then refine the existing suite map to explicit domain inputs, including imported
code, fixtures, prompts, configuration, and intentional corpus reads. Keep
unknown inputs on a full-run fallback. Do not start with a new general-purpose
dependency graph: SPEC-0206 already measured why that alone was low leverage.

Cache only deterministic checks with a complete input identity: transitive
source/test/configuration bytes, relevant environment, arguments, Node version,
OS/architecture, runner policy, and history when a check reads it. Changes to
untracked relevant files must invalidate local evidence too. A cache hit is
reported as reused evidence with provenance, never a new execution. Reconcile
this explicitly with the freshness policy before enabling cross-role reuse.
External permissions, remote refs, release publication, locks, and other live
effects are rechecked at action time and are not cached as test success.

During migration retain full runs on main/nightly and require full/platform
checks before merging changes to the relevant protected or cross-cutting
surfaces. Narrowing must preserve the dependency closure; an unselected failure
found later is evidence to fix the selection model, not proof of equivalence.

### 4. Reduce agent context and move routine work into deterministic commands

- Retain `canon.mjs`, but compose a short invariant set, the dispatched role's
  instructions, and task-relevant knowledge. Keep mandatory hazards always
  present. Fetch historical incident narratives only when relevant.
- Measure actual harness input/output/cache tokens per comparable completed
  task. Byte budgets are a useful diagnostic but not a substitute for token cost.
- Make policy and test-plan outputs structured. Let code decide routine state
  transitions, scope checks, and required validation; use the model for design,
  implementation, ambiguous analysis, and independent judgment.
- Keep six semantic roles where their responsibilities matter, but avoid forcing
  every cheap transition to create another large model context. Extend existing
  L0/L1 paths rather than inventing a competing workflow. Protected state,
  destructive actions, security, and public contracts retain independent checks.
- Consolidate machine-owned manifests into a single strict representation per
  domain. Prefer JSON for new machine-only data. If human-authored YAML remains
  necessary, evaluate one maintained parser in an explicit technology-contract
  amendment against the actual cost of bespoke parsers. Do not rewrite
  transactional STATE storage or append-only ledgers as a side effect of this RFC.

### 5. Make autonomy resumable and the public interface small

Build on deterministic dispatch and the release completion journal already in
AAI. Model an operation as prepare, perform, verify, and checkpoint, with a
stable operation identity. After interruption, inspect authoritative state
before repeating an external effect. Reuse the existing state writer and locks;
avoid a second state engine or a distributed workflow service.

The normal user journey should expose only a few concepts: propose work, run or
continue it, inspect status, and complete the authorized delivery. Retain expert
skills but load their detailed catalogs on demand. One status view should state
the current action, evidence, blocker, and next decision. Routine defaults and
already-granted authorization survive resumes; the user should not have to
choose TDD, role routing, or isolation repeatedly for ordinary work.

A compact low-risk change can carry problem, acceptance criteria, and evidence
in one artifact through the existing lightweight lane. Reserve a separate RFC
for an actual architectural decision. Reports and indexes should be generated
views of canonical data; do not make the agent reconcile several copies.

## Alternatives Considered

| Option | Benefits | Costs / decision |
|---|---|---|
| Continue local optimizations only | Small changes, low migration risk | Useful first step, but preserves duplicate policy and expensive test boundaries. Insufficient as the whole program. |
| Translate every shell file into Node at once | One language quickly | High compatibility risk; can port 147k lines of inefficient test structure unchanged. Reject. |
| Incremental Node core plus layered tests and leaner context | Removes recurring costs while retaining contracts | Needs temporary parity work and explicit retirement of old paths. Recommended. |
| Adopt Nx, Turborepo, Bazel, or another workflow framework wholesale | Mature task/cache primitives | Integration, configuration, and dependency costs are not justified for this single vendored toolkit yet. Borrow the principles first. |
| Remove Windows or independent checks | Immediate apparent savings | Changes the product and weakens guarantees. Not required for the proposed gains. |
| Replace all YAML/state with a database | Stronger querying and schemas | Violates current file portability expectations and greatly expands migration. Defer; simpler manifests can improve without this. |

### External comparisons and what to borrow

- [Node's built-in test runner](https://nodejs.org/docs/latest-v24.x/api/test.html)
  provides assertions integration, test discovery/execution, process isolation,
  concurrency, reporting, and sharding. Use its standard runner instead of
  reproducing general test-runner behavior in shell. It does not solve AAI's
  application-level repository isolation or subprocess-tree contract.
- [Nx affected tasks](https://nx.dev/docs/features/ci-features/affected) uses
  changed inputs and dependency relationships to select work. AAI should evolve
  its existing selector toward declared inputs after reducing broad fixtures.
- [Nx caching](https://nx.dev/docs/concepts/how-caching-works) keys reuse from
  task inputs, including configuration and runtime values. Borrow input identity
  and provenance; installing Nx is not necessary to evaluate this approach.
- [Bazel hermeticity](https://bazel.build/basics/hermeticity) emphasizes declared
  inputs, isolation, and reproducibility. Apply this to test fixture boundaries
  before adding caching; do not infer reproducibility from a passing local run.
- [OpenSpec](https://openspec.dev/) presents a compact explore/propose/apply/
  verify/archive interface. Borrow the small user-facing vocabulary and optional
  detail, not its implementation or a claim that it outperforms AAI. No
  comparative token/latency benchmark was performed here.
- [Node release status](https://nodejs.org/en/about/previous-releases) supports
  making the runtime support window explicit: 24 and 22 are LTS, 20 is EOL at
  the time of this assessment.

## Consequences

Expected benefits are fewer places to change a behavior, shorter local feedback,
more reliable parallel tests, less repeated agent context, and fewer human
interruptions. The magnitude is not established until the pilot is measured.

Compatibility work remains real: launcher arguments, exit codes, encoding,
line endings, filenames with spaces, symlinks, staged Git blobs, process trees,
and idempotent external effects must preserve explicit contracts.

The intended simplification is a net reduction of maintained implementations,
bespoke runners, parser dialects, and manually repeated instructions. No new
permanent audit service or extra approval workflow is proposed.

## Rollout Status

The owner invoked `/aai-ship` for this RFC. Planning selected incremental
delivery; the first child covers scheduling foundations only. The phase order
prioritizes measurable feedback improvements and defers the riskiest platform
behavior. Completing that child must not close this umbrella RFC.

| Phase | Description | Status | Delivered by |
|---|---|---|---|
| 0 | Baseline representative local/CI checks; separate the observed main pricing failure and state-suite skip from speed work | in progress | `selected-ci-scheduling-foundation`; main pricing repair landed separately in #484 |
| 1 | Refresh scheduling weights, selected longest-first, conditional reuse of existing sharding, superseded-run cancellation | done | Scheduling foundations merged in #485; conditional selected sharding merged in #486; body-only rechecks merged in #489; superseded pull-request runs are cancelled by the workflow concurrency group |
| 2 | Move docs-audit logic cases to `node:test`; retain CLI/corpus tests; split always-on content validation from engine regression | done | [Body-lint Node test pilot](../issues/CHANGE-0216-docs-audit-node-test-pilot.md) migrated five body-lint groups; [matched measurements](../analysis/docs-audit-node-test-pilot.md); docs-audit suite-speed child cut the ordinary suite median 31.9% by sharing real-corpus work and moving the closeout cases to Node ([note](../analysis/docs-audit-suite-speed.md)); the [content/engine split](../issues/CHANGE-DRAFT-docs-audit-content-engine-split.md) made the 24 live-corpus cases an always-on `aai-docs-content` suite, left the engine regression suite to engine inputs, and moved the last measured-beneficial Node cluster, the five `--gate`-only cases ([note](../analysis/docs-audit-content-engine-split.md)) |
| 3 | Migrate common sync/hook behavior to Node in small slices, with native platform parity and retired counterparts | done | [First Node-first slice](../issues/CHANGE-0222-node-first-sync-hook-slice.md) moved the live-status spool hook (live-spool pair 133 to 116 lines): one Node module and two launchers, tested with `node:test` plus Pester on the native Windows job; the [second slice](../issues/CHANGE-0223-node-first-second-slice.md) moved the L1 triage snapshot (triage pair 140 to 129 lines), a behavior with an exit-code gate and two child processes; the [third slice](../issues/CHANGE-0224-node-first-third-slice.md) moved the expert prompt fetcher (expert-fetch pair 444 to 230 lines), a behavior with a network fetch, a cache and two security filters, and closed phase 3 with the remaining-pairs inventory below |
| 4 | Slim role context and generate provider adapters; extend existing lightweight and resume paths | in progress | [Cheap transitions slice](../issues/CHANGE-0225-cheap-transitions-slice.md) adds a delta re-check mode: a Validation or Code Review round that follows a judged round and whose delta touches only non-production paths gets a slim payload instead of the full role prompt and LEARNED (Code Review 32720 to 11395 bytes, Validation 45467 to 11394 bytes per dispatch, measured by `tests/skills/lib/recheck-measure.mjs`); never at L3, never for a production, protected or security-relevant delta, never on a first round; this ride runs full. The [recheck verdict binding slice](../issues/CHANGE-0226-recheck-verdict-binding.md) records each judged round in the `check_binding` block of STATE (`state.mjs bind-check`) so eligibility compares that block instead of the tracked ledger stamps; the same slice turned the delta re-check on by default (`AAI_RECHECK_MODE=full` turns it off for a run) as its last commit. Provider adapter generation: the [provider adapter registry slice](../issues/CHANGE-0228-provider-adapter-registry-slice.md) (PR #502) |
| 5 | Introduce precise evidence reuse where inputs are declared; migrate remaining process adapters only with native evidence | not started | No child intake yet |
| order 4 | Node 24 CI baseline and published floor | done | [Node 24 CI baseline](../issues/CHANGE-0221-ci-node-24-baseline.md) |

### Remaining paired scripts after phase 3

A pair is `.aai/scripts/<name>.sh` plus `<name>.ps1` with no `<name>.mjs`; the line counts were measured at the delivery commit of the third slice.

| Pair | Lines sh/ps1 | Destination | Reason |
|---|---|---|---|
| `aai-canonicalize` | 276/281 | later candidate | one-off structure migration; its telemetry step depends on migrate-yaml-to-jsonl (python3 and PyYAML) |
| `aai-live` | 125/90 | later candidate | already requires Node; what remains is browser-opener choice around generate-live-status.mjs, which a later slice can fold into that generator |
| `aai-reap-tests` | 368/419 | phase 5 process adapter | reaps process groups and Windows process trees (process supervision migrates last) |
| `aai-release` | 365/414 | later candidate | 779 lines with git and gh write effects and the most active history; its finish step already lives in release-finish.mjs |
| `aai-run-tests` | 958/942 | phase 5 process adapter | supervises suite processes, timeouts and orphan cleanup |
| `aai-sync` | 1039/1087 | platform adapter kept on purpose | installs AAI into a target before Node is guaranteed there (bootstrap before Node is installed) |
| `aai-update` | 180/188 | platform adapter kept on purpose | a caller runs before Node is installed (SPEC-0248) |
| `autonomous-loop` | 488/464 | phase 5 process adapter | supervises agent child processes |
| `cloudflare-share` | 78/69 | later candidate | external deploy with a write effect; needs a staged-deploy test seam; the sh copy's grep -oP fails on macOS |
| `install-pre-commit-hook` | 1313/1097 | platform adapter kept on purpose | hook installation, file permissions and symlinked configuration |
| `migrate-state-to-local` | 162/175 | platform adapter kept on purpose | git-only legacy migration that aai-sync names for a target that may not have Node yet; retire with RFC-0001 legacy support instead of porting |
| `migrate-yaml-to-jsonl` | 126/151 | later candidate | needs a general YAML parser that Node's stdlib lacks; one-off (SPEC-0248) |
| `pre-commit-checks` | 323/281 | platform adapter kept on purpose | L3 protected surface whose checks 1 to 7 run without Node; a move needs its own L3 scope |
| `pre-compact-save` | 77/87 | later candidate | no shipped install wires the hook (SPEC-0248) |
| `validate-skills` | 47/55 | later candidate | twelve file-existence checks with cosmetic drift (SPEC-0248) |

Suggested first implementation scope: scheduling improvements plus a separate
docs-audit pilot. Do not combine scheduler, state storage, prompt governance,
and Windows process supervision into one large specification.

The scheduling foundation child is done and merged in #485:
[Selected CI scheduling foundation](../specs/SPEC-0239-spec-selected-ci-scheduling-foundation.md).
[Conditional selected CI sharding](../specs/SPEC-0240-spec-selected-ci-conditional-sharding.md),
with its [intake](../issues/CHANGE-0215-selected-ci-conditional-sharding.md),
merged in #486 at `a15065159a26af9cdbe6d57a193de9ca35da7389`.
Its five paired local measurements recorded median wall time 279.169 to 172.843
seconds for one fixed nine-suite set, with summed runner time up 17.894%; those
figures describe that child, not this program's aggregate improvement.
The current child is the [docs-audit body-lint Node pilot](../specs/SPEC-0241-spec-docs-audit-node-test-pilot.md):
five legacy body-lint groups now use direct `node:test` cases while CLI/corpus
coverage stays in Bash. Its [pilot report](../analysis/docs-audit-node-test-pilot.md)
records five paired matched runs: median 2.005992 to 0.569638 seconds and 126
fewer lines across the three test files. These figures describe only the
matched cluster; no whole-suite speedup or production PowerShell/Bash reduction
is claimed.
Body-only rechecks merged in #489. Document-content CI/hygiene separation
remains a separate follow-on; this umbrella RFC stays open. Runtime support changes,
sync policy, hook policy, lean context/generated adapters, resume/status,
deterministic evidence reuse and process adapters each require their own
bounded contract and evidence before a final program-wide reconciliation.
Required migration isolation or protected-surface decisions apply when those
concrete later scopes are ready, not to this first scheduling child.

### Proposed success criteria

Targets below are engineering hypotheses for Planning to validate, not achieved
results or guarantees. Record baseline and after on the same hardware/runtime,
with at least five representative runs, reporting sample count, median, worst
observed time, and runner-seconds. Measure p95 only once enough samples exist.

| Measure | Proposed target |
|---|---|
| Local feedback for the migrated logic domain | At most 10 s; no full repository clone |
| Ordinary document-only CI gate | At most 60 s median, while retaining actual content/corpus invariants |
| Typical scoped behavior-change CI | At most 120 s median on the defined sample |
| Full regression check | At most 240 s median for the slowest skills job at no greater runner budget |
| Common shell policy | One Node owner per migrated operation; legacy launcher parity demonstrated and old policy removed |
| Validation prefix | Reduce measured bytes by at least 50% while retaining all mandatory hazards; confirm benefit with actual task token usage |
| Agent efficiency | At least 30% fewer input tokens on comparable low-risk tasks; report cache effects separately |
| Reliability | No newly missing assertions, unexplained skips, shipping-tree writes, orphaned child processes, or duplicated external effects in the migration scenarios |
| User effort | No new routine decisions; at most one bundled request when a substantive decision is actually missing |

## Risks

- Under-selection or stale cache: declare non-code inputs, fail to full on
  uncertainty, shadow-compare selection during migration, retain corpus and
  protected-surface checks. Never equate a cached test with a fresh remote check.
- Loss of platform behavior: retain adapters and test natively on Windows 5.1/7,
  Linux, and macOS where their contracts differ. Portability is not proved by
  changing the implementation language.
- Weak replacement tests: preserve behavioral mapping, representative adversarial
  cases, and mutation checks for critical invariants. Avoid copying the
  implementation as its only oracle.
- Optimizing the wrong bottleneck: collect suite execution, fixture preparation,
  subprocess count, scheduling wait, and cleanup separately during the pilot.
  Static line counts do not prove where time is spent.
- Growing a migration framework: use existing manifests, CLI entrypoints, and
  state mechanisms. Each slice has an explicit deletion endpoint and rollback.
- Governance drag: changes to test contracts, role-context requirements, runtime
  baseline, or evidence freshness need explicit amendments to their current
  authoritative documents; until then the current rules still apply.

## Open Questions

None open. The owner resolved the four decision points on 2026-10-22; see
Owner decisions below.

### Owner decisions (2026-10-22)

1. **Direction.** Node-first incremental consolidation is approved, with native
   platform support retained. Remaining work runs in this order, one bounded
   child scope each:
   1. Slim the standing role context (phase 4, first slice): `LEARNED.md` is
      about 46% of the Validation prefix; mandatory hazards stay always loaded,
      incident narratives load only when relevant.
   2. Ride reliability (not in the original phases): a ride worktree starts
      from a STATE that carries only its own work item, so foreign runs never
      reach the metrics flush. Observed in #482/#484, where a copied STATE
      flushed another ref's run and turned main red.
   3. Finish the phase 2 docs-audit `node:test` migration and the
      content/engine CI separation.
   4. Move CI to Node 24.
   5. Phases 3 to 5 in order, each with its own specification.
2. **Node support floor.** Node 24 is the development and CI baseline. Node 22
   stays supported downstream until an announced transition; Node 20 is
   end-of-life and is dropped from CI.
3. **Data formats.** YAML stays where a human edits the file (STATE, roadmap,
   PRICING). New machine-only manifests use JSON. Existing machine-only YAML is
   not migrated by this RFC.
4. **Runner budget.** Selected-mode sharding adds a runner only when it is
   expected to cut wall time by more than two minutes; otherwise one runner.

## Approvals

Required approver for the architectural direction and explicit contract changes:
the project owner. The owner approved the direction and the four decisions
above on 2026-10-22 (recorded in `docs/ai/decisions.jsonl`). Each child scope
still carries its own specification, validation and review; this approval
changes no runtime, workflow or technology contract by itself.

## Notes

- Interpretation: the owner's reference to duplicated "ps+ a hash" code means
  PowerShell and Bash; the repository's paired scripts support that reading.
- No secret values are needed or referenced.
- Implementation mode: not selected; Planning decides per child scope. Current
  deliverable is documentation only. Future core/state/process behavior requires
  the rigor appropriate to those changes.
- Human intake time (user-reported, 2026-10-21): 1 minute
  (`human_time_minutes.intake: 1`). Recorded here because `state.mjs` has no
  human-time mutation command; runtime STATE was not hand-edited.
- Reproduction: tracked inventory via `git ls-files -z` and byte/line counts;
  suite discovery via `test-aai-*.sh`; current-policy replay via
  `select-suites.mjs --files-from -` over each of the last 40 first-parent commit
  diffs; prompt prefix via `canon.mjs build --role Validation --ref HEAD`;
  CI metadata via `gh run view <run-id> --json jobs` and linked job logs.
- Runtime tests were not rerun for this analysis. Current-tree measurements,
  source inspection, existing CI evidence, and document validation have different
  evidentiary scope; this document does not claim the repository is green.
