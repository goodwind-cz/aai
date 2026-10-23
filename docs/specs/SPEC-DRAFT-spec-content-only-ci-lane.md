---
id: spec-content-only-ci-lane
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: 0fe97dff1b048da5fa010f15492eaf874b8f1629f99e2e7e0e6edbefcc399e10
ceremony_level: 2
links:
  requirement: content-only-ci-lane
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Content-only pull requests run their corpus arms, not the engine suites

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/CHANGE-DRAFT-content-only-ci-lane.md
- Parent: docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md (phase 2, second half; owner decisions of 2026-10-22, order item 3; owner decision 2026-10-23: CI split only, no further docs-audit node:test migration)
- Reused, not duplicated: .aai/scripts/select-suites.mjs (selection seam, suite-map parser, protected-l3 reader), .github/workflows/skill-suite.yml (select job, aggregate gate, body-reuse precedent of PR #489), .aai/scripts/mutation-run.mjs (isPositionalDispatchSuite), .aai/scripts/aai-run-tests.sh (watchdog wrapper)
- Precedent for local acceptance plus hosted delivery checks: docs/specs/SPEC-0242-spec-ci-body-only-rechecks.md
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values

- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred: entire spec postponed; explain reason in this section
- rejected: spec was abandoned; explain rationale
- superseded: replaced by a newer spec; set links to the replacement

## Baseline and measurements (Planning, 2026-10-23)

Baseline tree: main `34f0cbca` (#492). All figures below were measured during
Planning; none is an implementation result.

Hosted CI today (gh pr view N --json statusCheckRollup, latest run per check,
skill-suite workflow, non-skipped jobs; wall = last completion minus first
start; runner-seconds = sum of job durations):

- PR #490: select 16 s, selected skill suite 183 s, Windows worktree seed 94 s,
  self-hosting smoke 17 s, release notes 12 s, tracked-ignored 12 s, gate 3 s.
  Wall 210 s, runner-seconds 337. The docs-numbering workflow adds 12 s and
  17 s in parallel. Correction to the intake: #490 did not change only RFC
  text. It also changed tests/skills/lib/ci-body-recheck.test.mjs,
  docs/INDEX.md, docs/ai/EVENTS.jsonl and docs/ai/decisions.jsonl, so it is not
  a content-only diff under this spec.
- Context sample of docs-heavy selected-mode PRs #490, #481, #478, #451, #446:
  wall 210, 187, 143, 216, 209 s (median 209, worst 216); runner-seconds 337,
  319, 274, 319, 309 (median 319, worst 337). None of them is content-only
  under this spec. They are context, not the before sample. The before sample
  is the D1 probe below.
- Where the time goes: an RFC-only diff selects exactly the four core suites
  plus their companion aai-prompt-diet (select-suites.mjs replay). Their
  suite-weights.tsv weights are aai-docs-audit 212, aai-hygiene-pack 97,
  aai-spec-lint 38, aai-prompt-diet 8 and aai-check-state 3. The docs-audit
  suite is the critical path.
- Required status checks on main (gh api rules/branches/main): the gate
  `skill test suite (tests/skills/, via test-framework.sh)`, `self-hosting
  smoke (...)` and `doc-numbering guards (...)`. A job skipped by its `if:`
  reports success to branch protection. The body-reuse mode of #489 already
  relies on this for the smoke job.

Population replay (gh pr list --state merged --limit 200, whole-PR file
lists): 59 of the last 200 merged PRs touched only docs/, CHANGELOG.md or
README.md. Under this spec's fail-closed v1 globs, 0 of 200 would have been
content-only. Every docs-only PR also carried docs/INDEX.md, a ledger, a spec,
CHANGELOG or AAI_VERSION, and engine suites read those. Adding INDEX and
EVENTS would still give 0, and adding decisions.jsonl and docs/issues would
give 12. The lane is the mechanism plus a deliberately small, proven set.
Widening it is follow-on work: move each extra path's engine readers into
content arms (see Registry review).

Reader census (static, Planning). Real-checkout reads of the candidate
directories in tests/skills (PROJECT_ROOT, cd "$PROJECT_ROOT" plus a corpus
walker, --docs "$PROJECT_ROOT/docs", cp -R "$PROJECT_ROOT/docs", run_engine
"$PROJECT_ROOT") were found in 39 functions across 12 suites:

- aai-docs-audit: 17 functions, including two helpers;
- aai-deslop: 5;
- aai-ceremony-levels: 4;
- aai-state and aai-ride-select: 3 each;
- aai-hygiene-pack: 2;
- aai-spec-lint, aai-doc-numbering, aai-follow-ups, aai-orchestration-dispatch,
  aai-delta-stage2 and aai-delta-stage3: 1 each.

Two of these readers react to status. aai-ride-select reads
docs/{issues,specs,rfc,releases,requirements} statuses to admit a capability,
and aai-deslop TEST-023 reads the docs/issues and docs/rfc corpus. Neither
suite is selected for a docs/rfc diff today, which is a pre-existing gap.
Literal readers: docs/rfc/RFC-0017-...md (tests/skills/lib/ci-body-recheck.test.mjs), docs/rfc/RFC-0007-...md (test-aai-doc-numbering.sh), docs/project-sessions/INDEX.md (test-aai-hygiene-pack.sh, .aai/AGENTS.md, .aai/SKILL_SESSION_JOURNAL.prompt.md).
The smoke job (aai-sync.sh, install.sh, validate-skills.sh) reads only
docs/knowledge and docs/ai/AAI_VERSION.md from the source tree. The Windows
seed leg reads fixtures only. Neither reads a v1 content glob.

Standalone arm timing (macOS, each function invoked positionally in a scratch
`git clone --local`): 22 of 39 pass standalone, sum 62.1 s, longest 14.4 s
(aai-spec-lint test_011_seam_survival, aai-doc-numbering test_013_regression).
The 17 docs-audit functions fail standalone in about 0.0 s because the suite's
single-function dispatch skips the prelude main() runs (TEST_DIR is unset:
`/c0028-audit.log: Read-only file system`). The real-corpus `docs-audit.mjs
--check --strict --no-event` takes 1.5 s. generate-docs-index.mjs takes about
6 s. docs/INDEX.md carries a `Today (UTC):` line, so any freshness comparison
must strip it, as index_strip_dated already does.

Other workflows: ps1-quality.yml path filters contain no docs/ entry, so the
workflow never runs on a content diff. Its 664 s and 438 s Pester legs on #492
were triggered by .aai/scripts/merge-cleanup.mjs and
.aai/SKILL_WORKTREE.prompt.md. It is out of scope. docs-numbering.yml runs on
every PR (about 30 runner-seconds) and stays unchanged. close-gate.yml runs on
push to main only and stays unchanged. release.yml stays unchanged.

Governance: `.github/**` is not in protected_paths_l3, so ceremony_level is 2.
`.github/**` is in the docs/ai/merge-policy.yaml `architecture: consumer-facing`
globs, and this ride carries a roadmap capability. The PR therefore takes the
operator merge, not the internal-standing lane.

## Implementation strategy

- Strategy: tdd
- Rationale: the classifier, the gate branch, the arm runner and the census guard are all deterministic, and each has an observable RED against the current tree. Under-selection is the dominant risk, so every refusal and every rejection gets a stored RED artifact and a mutation that must redden it. Measurement and trace evidence are not TDD artifacts. They are protocol-checked locally and delivered as post-PR checks D1 to D3.

## Isolation and review

- Worktree recommendation: required
- Worktree rationale: workflow plus selector change on a shared main checkout. Hosted probes need a pushed branch.
- User decision: worktree (recorded before Planning)
- Base ref: main
- Worktree branch/path: change/content-only-ci-lane at /private/tmp/aai-content-only-ci
- Inline review scope: not applicable (worktree)

## Design and boundaries

### D1. Content classification in the existing selector (`--content`)

New mode `node .aai/scripts/select-suites.mjs --content (--base-ref <ref> or
--files-from <path or ->) [--repo-root] [--map] [--docs-audit]`. Its exit
code is always 0, and it prints exactly one of:

- one `CONTENT_ARM <suite> <function>` line per `content_arms:` entry (map
  order), then `CONTENT eligible paths=<n> arms=<m>`;
- a single `CONTENT_REFUSED reason=<reason>[ path=<p>][ reader=<file>]`.

The checks run in this order, and the first failure wins:

1. `no-content-globs` when the map has no `content_globs:` list.
2. `no-arms` when the map has no `content_arms:` list.
3. `bad-arm` for an arm that is not a `test_*` function defined in its
   suite's file, or whose suite file fails `isPositionalDispatchSuite`.
4. `empty-diff`.
5. `not-content` for the first path matching no content glob.
6. `literal-reader` for the first path whose exact repo-relative string
   appears in any tracked file under tests/, .aai/ or .github/.
7. `full-run:<reason>` when the existing classifyPaths result is FULL_RUN.
8. `reader-suite:<suite>` when the selection after companions contains any
   suite outside the empty-diff baseline, which is core plus core companions.
9. `internal-error` for any unreadable input.

The whole-PR diff is the same `git diff --name-only --no-renames
<base>...HEAD` the selector already uses. Without `--content`, every existing
mode is byte-for-byte unchanged, following the `--shards` precedent.

Rule 8 keeps the suite map authoritative. If a future row maps a content path
to a non-core suite, that path automatically stops being content.

### D2. Map lists (tests/skills/suite-map.yaml, read by the existing parser)

Three new optional top-level lists:

- `content_globs:` contains `docs/rfc/**`, `docs/decisions/**` and
  `docs/project-sessions/**`.
- `content_arms:` holds `<suite> <test_function>` items, one per line.
- `content_arm_exempt:` holds `<suite-or-lib-file> <function-or-dash>
  <reason> [<arm>]` items, where reason is `covered-by` (names the covering
  arm) or `literal-only` (the hit names a concrete content file that rule 6
  already excludes).

Each list is absent by default. With no lists the lane never fires, so a
downstream install is unaffected. The initial arms are the census
functions. Planning's 37 test_* functions are dispositioned as arms, and the
two docs-audit helpers (setup_indexarm_snapshots, silence_live_audit) as
covered-by their calling arms. Implementation finalises the list from D5 and
D6 evidence.

The v1 globs are deliberately narrow. The following stay outside the globs,
so they are engine paths:

- docs/INDEX.md, docs/ai/** (all ledgers), docs/specs/** and docs/issues/**;
- docs/analysis/** (unmapped today, so it is a FULL_RUN);
- docs/product/**, docs/knowledge/**, CHANGELOG.md, README.md and every
  other path.

### D3. Workflow: content mode inside the select job

Content mode adds no new job and no new runner.

1. After the existing `select` step, a step `id: content` runs only when
   `steps.select.outputs.mode == 'selected'`. It writes the classifier output
   to content-plan.txt, and writes `mode=content` to GITHUB_OUTPUT only on a
   `CONTENT eligible ` line.
2. A step `id: content-checks` runs only when
   `steps.content.outputs.mode == 'content'`. It runs
   `bash tests/skills/lib/content-arms.sh --run content-plan.txt` and writes
   its stdout proof line as `content_proof=` to GITHUB_OUTPUT.
3. Job outputs change. `mode` becomes the content step's mode, falling back
   to the select step's mode, and a new output `content_proof` is added.
4. The `selected-plan` step additionally requires
   `steps.content.outputs.mode != 'content'`.

Non-PR events, the ci-full label and body-reuse never reach the content step,
because the select step already chose full or body-reuse. A content-only
diff can never carry forward, because carry-forward requires a whole-PR
FULL_RUN.

The `native-worktree-seed` and `self-hosting-smoke` conditions become
`needs.select.outputs.mode != 'body-reuse' && needs.select.outputs.mode !=
'content'`. The skills-selected, skills-selected-sharded and skills-full
conditions stay unchanged, so they already skip in content mode. Job names
stay unchanged.

### D4. Gate honesty

The gate job gets `CONTENT_PROOF: ${{ needs.select.outputs.content_proof }}`
in its env. The seed and smoke success requirements are exempt for content
mode as well as body-reuse. A new branch `elif [ mode = content ]` requires
all of the following:

- the event is pull_request;
- CONTENT_PROOF matches `^ci-content-v1 arms=([1-9][0-9]*) passed=([1-9][0-9]*)$`,
  with both numbers equal;
- skills-selected, skills-selected-sharded, skills-full, native-worktree-seed
  and self-hosting-smoke all report skipped.

The existing select, release-notes and tracked-ignored requirements still
apply. A failed arm fails the content-checks step, so `select` is not success
and the gate fails. A skipped or absent content-checks step leaves no proof,
so the gate fails. A body-edit on a content PR cannot reuse a content-mode
run: proveBodyRun requires seed and smoke success, so it falls back to a
fresh run, which is safe.

### D5. Arm runner (tests/skills/lib/content-arms.sh)

`--run <plan>` reads the `CONTENT_ARM` lines. It runs each arm in its own
`git clone -q --local` of the checkout under one temp root, with
`env -u AAI_ROLE` and the aai-run-tests.sh watchdog (AAI_TEST_TIMEOUT=180),
`--jobs` defaulting to 4. Per-arm status goes to stderr.

The runner prints exactly `ci-content-v1 arms=<total> passed=<passed>` on
stdout, and exits 0, only when total is greater than 0 and every arm exited
0. Otherwise it prints no proof and exits 1.

No arm runs in the checkout itself. Several arms rewrite docs/INDEX.md, and
clones keep concurrent arms apart. Where an arm cannot run standalone,
Implementation makes the suite's single-function dispatch run the prelude
main() runs before that arm. This is a dispatch change, not an arm-body
change. The aai-docs-audit dispatch is the known case.

### D6. Census guard and read trace

tests/skills/lib/content-census.mjs prints `CENSUS <suite> <function>` for
every function in tests/skills/test-aai-*.sh that has a real-checkout read
of a content directory, plus `CENSUS <lib-file> -` for tests/skills/lib/*.mjs
lines naming a content directory next to a ROOT path. It uses the six
Planning patterns, pinned in the brief.

The guard requires three things:

- every census hit is a content arm or has an exempt entry;
- every arm is a defined test_* function in a positional-dispatch suite;
- every covered-by target is an arm.

tests/skills/lib/content-read-trace.cjs is a NODE_OPTIONS preload that logs
fs reads under `docs/(rfc|decisions|project-sessions)/` relative to
AAI_TRACE_ROOT. Implementation runs every suite once under it, each in its
own clone with AAI_TRACE_SUITE set, and records the result in the analysis
note's `## Read trace` section.

Decision rule: every suite with a traced read lists its reading functions,
and each one is an arm or a covered-by exemption. If a reading function
cannot be identified, all of that suite's census functions are listed. If
there are none, the glob is removed from content_globs.

## Seams and residual risks

- S1 selector to workflow: the content step consumes the real classifier
  output (TEST-007 runs the extracted step script against real classifier
  output files).
- S2 workflow to gate: the real gate block runs against content-mode inputs
  (TEST-008 and TEST-009, following the ci-body-recheck gate() pattern).
- S3 map to runner: the runner runs real arms from the real map (TEST-014
  runs one arm; V3 and D2 run the full list).
- S4 suites to census: TEST-013 scans the live suites.
- R1 node-level readers that the static census does not see, such as a
  future test running a corpus walker on the real tree. The read trace is
  one-off evidence, not a guard. Main and nightly still run full, so a miss
  surfaces after merge, which is the existing selection tradeoff.
- R2 suites that scrub env (env -i) are invisible to the tracer. They are
  listed in the note.
- R3 the 60 s median depends on runner speed. If D2 misses it, that is a
  FAIL to remediate (parallelism, arm dedupe), never a silently relaxed
  target.
- R4 the lane fired on 0 of the last 200 merged PRs (Baseline). Its value
  depends on widening it.
- R5 an arm that passes vacuously standalone, for example because a missing
  fixture makes it skip, would weaken parity. The runner treats exit 42
  (SKIP) as failure.

## Acceptance Criteria Mapping

| Requirement | Spec-AC | Verification and decisive observable | Evidence |
|---|---|---|---|
| AC-001 | Spec-AC-01 | TEST-001: synthetic v1 paths print the arm lines and CONTENT eligible | docs/ai/tdd/content-lane-classifier.log |
| AC-002 | Spec-AC-02 | TEST-002..005: each fail-closed case prints its exact CONTENT_REFUSED reason | docs/ai/tdd/content-lane-classifier.log |
| AC-002, AC-004 | Spec-AC-03 | TEST-006: existing modes byte-identical without --content | docs/ai/tdd/content-lane-classifier.log |
| AC-001, AC-004 | Spec-AC-04 | TEST-007: extracted content step yields mode=content only on eligible output; selected-plan excluded | docs/ai/tdd/content-lane-workflow.log |
| AC-003 | Spec-AC-05 | TEST-008..010: real gate exits 0 only with full proof and skipped engine legs | docs/ai/tdd/content-lane-workflow.log |
| AC-001, AC-003 | Spec-AC-06 | TEST-011, TEST-012: runner proof only on full success; checkout untouched | docs/ai/tdd/content-lane-runner.log |
| AC-001, AC-002 | Spec-AC-07 | TEST-013..015 plus V3: census equals dispositions; real arms pass standalone; tracer detects reads | docs/ai/tdd/content-lane-census.log |
| AC-005 | Spec-AC-08 | TEST-016: note, RFC row, product doc and workflow header carry the required fields | docs/ai/tdd/content-lane-docs.log |
| AC-002, AC-004 | Spec-AC-09 | TEST-017: regression suites and ci-body-recheck tests green | docs/ai/tdd/content-lane-regression.log |

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN every changed path matches content_globs and none is literally named under tests/ .aai/ or .github/ and the selection equals the core baseline the selector in --content mode SHALL print one CONTENT_ARM line per content_arms entry then CONTENT eligible with exit 0 | planned | — | — | D1 |
| Spec-AC-02 | WHEN any path is outside the globs or literally read or the diff is empty or FULL_RUN or selects a non-core suite or the map lists are missing or malformed the selector SHALL print one CONTENT_REFUSED line with the exact reason and exit 0 | planned | — | — | D1 D2; ledgers INDEX specs issues analysis CHANGELOG stay engine |
| Spec-AC-03 | WHEN --content is absent every existing selector mode SHALL produce byte-identical output with or without the new map lists | planned | — | — | D1 |
| Spec-AC-04 | WHEN the select job runs on a pull request in selected mode with eligible output the job SHALL publish mode content and a content proof and SHALL skip the selected plan; full and body-reuse and non-PR paths SHALL never consult the classifier | planned | — | — | D3 |
| Spec-AC-05 | WHEN mode is content the gate SHALL pass only on a pull request with a proof whose arms equal passed and are at least 1 and with all five engine legs skipped; the seed and smoke jobs SHALL skip in content mode | planned | — | — | D4 |
| Spec-AC-06 | WHEN the runner executes a plan it SHALL run each arm in its own clone and print the proof line and exit 0 only if every arm exited 0 and at least one ran | planned | — | — | D5 |
| Spec-AC-07 | WHEN tests/skills changes the census guard SHALL fail unless every real-checkout reader of a content directory is an arm or a valid exemption; every content arm SHALL pass standalone on the unmodified tree; the read trace SHALL be recorded with its decision rule applied | planned | — | — | D6; V3 local full list |
| Spec-AC-08 | WHEN local implementation is handed off the analysis note SHALL define the D1 to D3 protocol with pending or measured fields and the read trace and population replay; RFC-0017 phase 2 SHALL name this child; the product doc and workflow header SHALL describe content mode | planned | — | — | D1 to D3 gate delivery separately |
| Spec-AC-09 | WHEN the lane lands the existing selector, carry-forward, body-reuse, tracked-ignored and release-notes coverage SHALL remain green | planned | — | — | regression |

## Implementation plan

1. Run D1 early, because main moves: open the before probe against main.
   Record it as described in the protocol below.
2. Write the tests: TEST-001..006 in test-aai-suite-select.sh;
   TEST-007..012 and TEST-016..017 in test-aai-ci-carry-forward.sh, with the
   node cases in tests/skills/lib/ci-content-lane.test.mjs called by name;
   TEST-013..015 in test-aai-suite-select.sh. Observe RED against the
   current tree and store it under docs/ai/tdd/.
3. Implement D1 and D2. Add the suite-map lists, the parser fields and
   contentMain, and map the new lib files in suite-map: content-arms.sh,
   content-census.mjs and content-read-trace.cjs under aai-suite-select and
   aai-ci-carry-forward, and ci-content-lane.test.mjs under
   aai-ci-carry-forward.
4. Implement D5, the runner. Make every census arm pass standalone, which
   means the docs-audit single-function prelude. Run V3.
5. Implement D3 and D4 in the workflow and its header comment, and update
   docs/product/ci-test-impact-selection.md.
6. Run the D6 read trace and finalise the arm and exempt lists by the
   decision rule. Write docs/analysis/content-only-ci-lane.md with the D1 to
   D3 fields as PENDING where they are not yet measured, and add the
   RFC-0017 rollout row. Keep RFC-0017's status unchanged, because
   ci-body-recheck TEST-008 pins it.
7. Run the regression V2. After the PR exists, run D2 and D3, fill in the
   note, and have an independent validator re-read the raw API data.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-suite-select.sh | test_content_eligible: --content --files-from with docs/rfc/RFC-9001-probe.md, docs/decisions/DECISION-probe.md and docs/project-sessions/2099-01-01-probe.md on the real map; arm lines equal the map list in order and the last line is CONTENT eligible paths=3 arms=N | `sed:s/CONTENT eligible paths=/CONTENT eligibl paths=/` on .aai/scripts/select-suites.mjs | pending |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-suite-select.sh | test_content_not_content_table: one case per engine-class path (tests, .aai scripts and templates, .github, docs/INDEX.md, every docs/ai ledger, docs/specs, docs/issues, docs/analysis, docs/product, docs/knowledge, CHANGELOG.md, README.md, an unknown path) plus one mixed content and engine diff; each prints reason=not-content with the first offending path | `sed:s/if \(!isContentPath\(p, ctx\)\)/if (false)/` on .aai/scripts/select-suites.mjs | pending |
| TEST-003 | Spec-AC-02 | integration | tests/skills/test-aai-suite-select.sh | test_content_literal_reader: RFC-0017 refused with reason=literal-reader and reader=tests/skills/lib/ci-body-recheck.test.mjs; fixture repo naming a content file under tests/ refused, the same path unnamed is eligible (positive control first) | `sed:s/const reader = literalReaders\(p, opts\.repoRoot\);/const reader = null;/` on .aai/scripts/select-suites.mjs | pending |
| TEST-004 | Spec-AC-02 | integration | tests/skills/test-aai-suite-select.sh | test_content_reader_suite_fullrun_empty: fixture map whose non-core suite globs docs/rfc gives reader-suite:<suite>; a content path listed in protected_paths_l3 gives full-run:protected-l3; empty list gives empty-diff | `sed:s/if \(extraSuites\.length > 0\)/if (extraSuites.length < 0)/` on .aai/scripts/select-suites.mjs | pending |
| TEST-005 | Spec-AC-02 | integration | tests/skills/test-aai-suite-select.sh | test_content_config_refusals: no content_globs, empty content_arms, an arm naming an undefined or non-test_ function or a non-positional suite, and an unreadable map each give their exact reason with exit 0 | `sed:s/if \(!definedArm\(/if (false && !definedArm(/` on .aai/scripts/select-suites.mjs | pending |
| TEST-006 | Spec-AC-03 | integration | tests/skills/test-aai-suite-select.sh | test_content_default_modes_unchanged: whole-PR, delta, shard and selected-plan outputs for the existing replay fixtures are byte-identical between the real map and the same map with the three content lists stripped | `sed:s/if \(opts\.content\) return contentMain\(opts\);/return contentMain(opts);/` on .aai/scripts/select-suites.mjs | pending |
| TEST-007 | Spec-AC-04 | integration | tests/skills/test-aai-ci-carry-forward.sh | test_content_workflow_derivation: extracted content step run on real classifier output files writes mode=content only for eligible output; content-checks if and job output expressions pinned; selected-plan if excludes content; select derive block and step order unchanged | `sed:s/echo "mode=content"/echo "mode=selected"/` on .github/workflows/skill-suite.yml | pending |
| TEST-008 | Spec-AC-05 | integration | tests/skills/test-aai-ci-carry-forward.sh | test_content_gate_accepts: real gate block with mode content, proof ci-content-v1 arms=3 passed=3, release notes and tracked success, five engine legs skipped exits 0 | `sed:s/elif \[ "\$\{\{ needs\.select\.outputs\.mode \}\}" = "content" \]; then/elif false; then/` on .github/workflows/skill-suite.yml | pending |
| TEST-009 | Spec-AC-05 | integration | tests/skills/test-aai-ci-carry-forward.sh | test_content_gate_rejects: after the accepting control, each of missing proof, arms 3 passed 2, arms 0, malformed proof, each engine leg success or failure, select failure, push event, release notes failure and tracked failure exits non-zero | `sed:s/\[ "\$\{BASH_REMATCH\[1\]\}" = "\$\{BASH_REMATCH\[2\]\}" \]/true/` on .github/workflows/skill-suite.yml | pending |
| TEST-010 | Spec-AC-05 | integration | tests/skills/test-aai-ci-carry-forward.sh | test_content_job_conditions: seed and smoke if conditions exclude body-reuse and content; skills job conditions and all job names unchanged and equal to the ci-select.mjs constants | `sed:s/ && needs\.select\.outputs\.mode != 'content'//g` on .github/workflows/skill-suite.yml | pending |
| TEST-011 | Spec-AC-06 | integration | tests/skills/test-aai-ci-carry-forward.sh | test_content_arms_runner: fixture repo with a positional fake suite; all-pass plan prints exactly the proof and exits 0; one failing arm, an exit-42 arm, an undefined function and an empty plan each exit 1 with no proof line | `sed:s/\[ "\$passed" -eq "\$total" \]/true/` on tests/skills/lib/content-arms.sh | pending |
| TEST-012 | Spec-AC-06 | integration | tests/skills/test-aai-ci-carry-forward.sh | test_content_arms_isolation: two arms that each rewrite the same tracked file run concurrently and pass; the checkout git status stays empty and its file hash is unchanged | `sed:s/git clone -q --local "\$root" "\$dir"/ln -s "$root" "$dir"/` on tests/skills/lib/content-arms.sh | pending |
| TEST-013 | Spec-AC-07 | integration | tests/skills/test-aai-suite-select.sh | test_content_census_guard: live census equals arms plus exemptions, every arm is a defined test_ function in a positional suite, every covered-by target is an arm; a planted reader function in a scratch copy fails the guard | `sed:s/aai-hygiene-pack test_091_session_journal_index_complete/aai-hygiene-pack test_091_renamed_arm/` on tests/skills/suite-map.yaml | pending |
| TEST-014 | Spec-AC-07 | integration | tests/skills/test-aai-suite-select.sh | test_content_real_arm_positive_control: runner executes the real aai-hygiene-pack test_091_session_journal_index_complete arm on the live tree and prints ci-content-v1 arms=1 passed=1 | `sed:s/^test_091_session_journal_index_complete\(\) \{/test_091_session_journal_index_complete_off() {/m` on tests/skills/test-aai-hygiene-pack.sh | pending |
| TEST-015 | Spec-AC-07 | integration | tests/skills/test-aai-suite-select.sh | test_content_read_trace: a node child under the preload reading docs/rfc/x.md below AAI_TRACE_ROOT is logged with its suite; a read of the same name outside the root and a read of docs/specs are not | `sed:s/fs\.appendFileSync\(logPath, /void (logPath, /` on tests/skills/lib/content-read-trace.cjs | pending |
| TEST-016 | Spec-AC-08 | integration | tests/skills/test-aai-ci-carry-forward.sh | test_content_docs_and_note: the analysis note has the Read trace section and the D1 D2 D3 protocol fields, the population replay and the ps1-quality statement; RFC-0017 phase 2 row links the intake; the product doc and workflow header name content mode, fail-closed and the proof | `sed:s/## Read trace/## Read-trace/` on docs/analysis/content-only-ci-lane.md | pending |
| TEST-017 | Spec-AC-09 | integration | tests/skills/test-aai-ci-carry-forward.sh | test_content_regression_pins: node --test ci-body-recheck.test.mjs and ci-content-lane.test.mjs pass, including the body-reuse gate needs list | `sed:s/needs: \[select, skills-selected, skills-selected-sharded, skills-full, native-worktree-seed, self-hosting-smoke, tracked-ignored, release-notes\]/needs: [select, skills-selected]/` on .github/workflows/skill-suite.yml | pending |

### RED observations and negative controls

Before implementation:

- TEST-001..005 fail. --content is unknown, so the normal selection prints
  and no CONTENT line appears.
- TEST-006 fails, because the stripped-map comparison input does not exist.
- TEST-007..010 fail, because the current gate rejects mode content as an
  invalid selection mode and the content steps are absent.
- TEST-011..015 fail because their files are absent. A missing file is a
  wiring failure, though. Each negative case is shown sensitive only after
  its positive control reaches the decision.
- TEST-016 fails because the note and RFC row are missing.
- TEST-017 is the regression guard: green before and after, and reddened by
  its mutation.

Store each RED observation under docs/ai/tdd/content-lane-*.log with the
command, exit code and assertion text.

Independent Validation runs each of the following in a scratch copy, never
in the shipping tree, and each must redden its named assertion:

- remove the literal-reader scan;
- accept arms not equal to passed;
- let the seed job run in content mode;
- run one arm in the checkout instead of a clone;
- delete one census-listed arm from the map.

## Verification

- V1: `env -u AAI_ROLE AAI_TEST_PARALLEL=1 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh --skill aai-suite-select --skill aai-ci-carry-forward` exits 0 with zero skipped groups, and all TEST-001..017 functions are executed by main.
- V2 (regression): the same wrapper with `--skill aai-tracked-ignored --skill aai-release-notes --skill aai-docs-audit --skill aai-hygiene-pack --skill aai-spec-lint --skill aai-check-state --skill aai-prompt-diet` exits 0, plus the selector-derived impacted set required by the Validation canon. One full sweep runs before close (AAI_TEST_TIMEOUT=3000).
- V3 (full arm list, local): `node .aai/scripts/select-suites.mjs --content --files-from <(printf 'docs/rfc/RFC-9001-probe.md\n') > /tmp/plan.txt && bash tests/skills/lib/content-arms.sh --run /tmp/plan.txt` prints `ci-content-v1 arms=N passed=N`, where N equals the content_arms count, and exits 0. Record the per-arm seconds.
- V4: `node .aai/scripts/spec-lint.mjs --path docs/specs/<this spec>` reports no findings.

### Delivery checks (post-PR, pre-merge; SPEC-0242 lifecycle)

The local Spec-AC-01..09 are validated before the PR. D1 to D3 are separate,
mandatory delivery checks after the PR is opened and before it is merged.
They follow the SPEC-0242 boundary: no draft-PR bypass, and no gate is
waived. Missing evidence stays PENDING, and failed evidence goes to
remediation.

- D1 (before): open probe PR `probe/content-lane-before` against main with
  the current workflow. Make five sequential pushes, each appending one line
  `<!-- content-lane probe N -->` to
  docs/rfc/RFC-0016-downstream-pr-ceremony-reliability.md, which no test
  names. Wait for each run to complete before pushing again, because
  concurrency cancels in-progress runs. The PR body carries a `no-notes:`
  exemption line.
- D2 (after): open probe PR `probe/content-lane-after` with base
  change/content-only-ci-lane and head branched from it, using the same five
  edits. Each run must show:
  - select output mode content and a content_proof with arms equal to passed
    and equal to the content_arms count;
  - the five engine legs skipped and the gate success;
  - all three required checks satisfied.
  The pass criterion is a median wall of 60 s or less, with median
  runner-seconds below the D1 median.
- D3 (negative): one more push to the D2 PR touching
  tests/skills/suite-weights.tsv (comment line). The run must leave content
  mode, and the engine legs must run.

After measurement, close both probe PRs unmerged and delete their branches.

For every run, record the following from read-only `gh api
repos/goodwind-cz/aai/actions/runs/<id>` and `.../attempts/<n>/jobs`:

- run id, attempt, head SHA, base SHA and mode;
- per-job conclusion, started and completed times;
- wall seconds (last completion minus first start, non-skipped jobs);
- runner-seconds (sum of non-skipped job durations);
- queue seconds (run created to first job start).

Report the docs-numbering run separately. Report the sample count, median
and worst for each probe. Disclose base drift between D1 and D2. An
independent validator re-reads the raw API output before any delivery or
merge-ready claim. RFC-0017 stays open.

## Evidence contract

Every artifact records:

- ref `content-only-ci-lane`;
- the Spec-AC and TEST ids;
- the command and its exit code;
- the source SHA or diff;
- the evidence path.

TDD evidence is a stored RED and GREEN per AC-gating test under
docs/ai/tdd/content-lane-*.log, plus the mutation records required by
mutation_gate. The tracked measured report is
docs/analysis/content-only-ci-lane.md. Validation's authoritative report uses
`aai-outcome-v1` and is returned as both `outcome_report` and
`set-validation --evidence`. This planning document claims no implementation
PASS and no hosted result.

## Registry review

Registry items closed by this scope: none.

- fu-docs-audit-suite-has-no-selector (P2) is adjacent. D5 makes the
  docs-audit single-function dispatch run the arms standalone.
  Implementation reports whether that resolves the item's crash-on-arm
  symptom. It is closed only on that evidence; otherwise it stays open with
  a note.
- fu-mutation-selector-vs-bare-dispatch: the runner passes full test_* names
  and requires positional dispatch, so the item stays open and untouched.
- fu-watchdog-3000-exceeds-ci-timeout: the runner pins AAI_TEST_TIMEOUT=180
  per arm inside the select job's 5-minute ceiling. The item itself concerns
  the skills jobs and stays open.

Suggested follow-ups (not filed):

- suggested: fu-content-lane-widen-index-ledgers. Make docs/INDEX.md,
  EVENTS.jsonl, decisions.jsonl and docs/issues content-eligible by moving
  their engine readers into content arms. The replay shows 0 of 200 PRs
  today.
- suggested: fu-rfc-readers-unmapped-selected. aai-deslop, aai-ride-select
  and aai-state read docs/rfc on the real tree, but suite-map does not select
  them for mixed diffs. This is a pre-existing gap.
