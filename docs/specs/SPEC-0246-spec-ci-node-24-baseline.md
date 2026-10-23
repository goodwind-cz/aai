---
id: spec-ci-node-24-baseline
type: spec
number: 246
status: done
mutation_gate: v1
frozen_sha256: 5527ed2fe70e9af9d4ea5f9b53f5a15a5b3353c06334d43b70de5dc04c833e6c
ceremony_level: 2
links:
  requirement: ci-node-24-baseline
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Move CI to Node 24 and publish the supported Node floor

SPEC-FROZEN: true

## Links

- Requirement: [Move CI to Node 24 and publish the supported Node floor](../issues/CHANGE-0221-ci-node-24-baseline.md).
- Parent: [RFC-0017](../rfc/RFC-0017-smaller-node-core-and-faster-feedback.md),
  owner decisions 1.4 (order step 4), 2 (Node floor) and 4 (runner budget).
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, Bash 3.2 and GNU Bash).
- Baseline commit: `c6d86ed8` (main at planning time; the ride branch adds only the intake).

## Implementation strategy

- Strategy: hybrid
- Rationale: the doctor category and the three guard tests change what the
  factory proves and are new behavior, so each of those rows goes RED first on
  the baseline and carries a mutation record (TDD). The workflow edits, the
  TECHNOLOGY.md text, the RFC row and the stale comment are mechanical edits
  done in loop mode, but every one of them is pinned by a mutation-gated row.
  Every row's RED is natural on the baseline: the workflows pin Node 20, the
  doctor has no Node check and TECHNOLOGY.md says UNKNOWN.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound change to required CI workflows and a
  consumer-visible doctor category; the ride already runs in its own linked
  worktree.
- User decision: worktree
- Base ref: main
- Worktree branch/path: change/ci-node-24 at /private/tmp/aai-ci-node-24
- Inline review scope: .github/workflows/close-gate.yml;
  .github/workflows/docs-numbering.yml; .github/workflows/skill-suite.yml;
  .aai/scripts/aai-doctor.mjs; .aai/scripts/ci-select.mjs; docs/TECHNOLOGY.md;
  docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md;
  tests/skills/test-aai-doctor.sh; tests/skills/test-aai-hygiene-pack.sh;
  docs/product/aai-doctor.md; CHANGELOG.md;
  docs/issues/CHANGE-0221-ci-node-24-baseline.md; this spec.
- Code review required: true.

## What Planning measured

Facts on the planning tree (macOS arm64, local Node 22.23.1, Homebrew Node 26.12.0):

- Eleven `actions/setup-node@v4` steps pin `node-version: '20'`: close-gate.yml 1,
  docs-numbering.yml 2, skill-suite.yml 8. One of the eight is the Windows job
  `native-worktree-seed`, so the intake's out-of-scope clause for Windows jobs
  does not apply to it: it pins Node 20 and moves to 24. ps1-quality.yml and
  release.yml have no setup-node step and stay unchanged.
- No test pins a `node-version` value (`grep -rn node-version tests/ .aai/` is
  empty). Suites that read workflow files (ci-carry-forward, close-reconcile,
  doc-numbering, release, release-notes) pin other lines only.
- Node 24 deprecation exposure: no use of `url.parse`, `util.is*`, `util._extend`,
  `new Buffer`, `fs.exists`, `SlowBuffer`, `process.binding`, recursive `rmdir`,
  `punycode`, `tls.createSecurePair`, and no `shell: true` spawn (DEP0190) under
  `.aai/scripts` or `tests`; no suite asserts a DeprecationWarning or
  ExperimentalWarning on stderr. Under Node 26 (newer than 24) the four
  `node:test` files pass 45 of 45 and `aai-doctor.mjs` exits 0 with no warning.
  This is a proxy; Node 24 itself is proved by hosted check H1.
- The selector maps `.github/workflows/docs-numbering.yml` to nothing, so the PR
  runs the full framework (`FULL_RUN reason=unmapped`) on Node 24.
- `process.version` is configurable: a `--import` preload that redefines it is
  seen by the doctor (probe: `v20.11.1` reported), so the floor check is testable
  end to end through the real CLI with no production test seam.
- The required status checks on main include the job name
  `self-hosting smoke (separate job — bootstraps + re-validates a full copy, ~2-3 min)`.
  That name must not change.

### Node 22 check placement (RFC-0017 decision 4)

Decision: a second `actions/setup-node@v4` step with `node-version: '22'` plus
one short compatibility step at the end of the existing `self-hosting-smoke`
job. No new job and no new runner.

Why that job: it is the job that simulates a downstream install, it runs on
every non-body-reuse event, the aggregate gate already requires its success,
and it is off the critical path. On the latest main run (39934110873) it took
15 s while the skills jobs took 171 to 211 s in parallel.

Measured cost of the step's commands under local Node 22.23.1:

| Command | Local seconds |
|---|---|
| `node --check` over all 117 `.aai/scripts/**/*.mjs` | 2.2 |
| `node --test tests/skills/lib/*.test.mjs` (45 tests) | 8.0 |
| `bash tests/self-hosting/test-self-hosting-smoke.sh` | 5.0 |
| `node .aai/scripts/aai-doctor.mjs --json` | 1.2 to 1.5 |
| Total | about 17 |

Plus one setup-node resolution of Node 22 (normally a hosted tool-cache hit).
Expected job time stays under one minute, against a 10-minute job timeout and
skills jobs of about three minutes, so the added wall time on the PR's critical
path is zero and the added runner time is under one minute per run. A separate
Node 22 job was rejected: it adds a runner for no wall-time saving, which
decision 4 forbids. A full skills run on Node 22 was rejected for the same
reason. Residual risk: Node 22 coverage is the syntax of every shipped script,
the direct Node tests, the install path and the doctor, not every Bash suite.

## Scope and design

### D1. Workflows

- Every `node-version: '20'` in `.github/workflows/close-gate.yml`,
  `docs-numbering.yml` and `skill-suite.yml` becomes `node-version: '24'`
  (11 pins).
- `self-hosting-smoke` keeps its name, `needs`, `if`, `runs-on`, `timeout-minutes`
  and its existing steps in order (the primary smoke runs on Node 24). After the
  step `Run self-hosting smoke test` it gains, in this order:
  1. `- uses: actions/setup-node@v4` with `node-version: '22'`;
  2. a step named exactly `Node 22 compatibility (downstream floor)` whose `run:`
     block starts with `set -euo pipefail` and runs:
     - a version assertion without a pipe into an early-closing reader, e.g.
       `case "$(node --version)" in v22.*) ;; *) echo "expected Node 22, got $(node --version)"; exit 1 ;; esac`;
     - `find .aai/scripts -name '*.mjs' -print0 | xargs -0 -n1 node --check`;
     - `node --test tests/skills/lib/*.test.mjs`;
     - `bash tests/self-hosting/test-self-hosting-smoke.sh`;
     - the doctor on the checkout with `--json` written to a file, where exit 0
       or 1 is accepted (1 is a FAIL category on a bare CI checkout, not a
       crash) and any other exit fails, followed by a `node -e` check that the
       JSON parses and carries no category with id `CAT-20`.
- No other job is added or removed; the number of top-level jobs in
  skill-suite.yml stays as on the baseline.

### D2. Doctor CAT-20 Node Runtime (advisory)

In `.aai/scripts/aai-doctor.mjs`, these exact lines (mutation anchors):

```js
export const NODE_FLOOR_MAJOR = 22;
export const NODE_BASELINE_MAJOR = 24;
```

and an exported `catNodeRuntime(version = process.version)` that:

- parses the major with `/^v(\d+)\./`; no match returns `null` (not reported);
- contains the exact line `if (major >= NODE_FLOOR_MAJOR) return null;` so
  Node 22 and above are silent (no line, no JSON entry, category counts unchanged);
- otherwise returns `cat('CAT-20', 'Node Runtime', 'WARN', <reason>)` with a
  `detail` of `{ running: <version>, running_major, floor_major: 22, baseline_major: 24 }`.
  The literal `'Node Runtime', 'WARN'` appears in that call. The reason names the
  running version, the floor major and the baseline major, for example
  `Node v20.11.1 is below the supported floor (Node 22); AAI is developed and tested on Node 24 — upgrade Node`.

`runDoctor` appends `catNodeRuntime()` as the last entry (the existing
`filter(Boolean)` drops `null`). The header comment's category list and the
"Only CAT-01, CAT-02, and CAT-06 can produce FAIL" note gain CAT-20 as
WARN-capped. No script refuses to run on an old Node (intake assumption kept).
`.aai/SKILL_DOCTOR.prompt.md` relays output verbatim and needs no change, so no
prompt-corpus bytes are added.

### D3. Floor declaration

`docs/TECHNOLOGY.md`:

- The `Runtime(s)` bullet replaces the UNKNOWN-floor clause with: Node 24 is the
  development and CI baseline, Node 22 is the minimum supported downstream, Node 20
  is unsupported (end-of-life); doctor CAT-20 warns below the floor.
- The Version Matrix Node.js row becomes
  `Node.js` / `24 baseline; 22 minimum downstream; 20 unsupported` / `confirmed` /
  `setup-node pins in .github/workflows; NODE_FLOOR_MAJOR in .aai/scripts/aai-doctor.mjs`.
- The Open Questions bullet about the unpinned Node version is removed.

### D4. Stale comment and RFC row

- `.aai/scripts/ci-select.mjs`: `Node stdlib only (Node 20 global fetch).` becomes
  `Node stdlib only (Node 22+ global fetch).`
- RFC-0017 Rollout Status table gains one row: first cell `order 4`, second cell
  exactly `Node 24 CI baseline and published floor`, third cell `done`, fourth
  cell a link whose target ends in `ci-node-24-baseline.md` (the intake; the
  allocator renames the file and rewrites the link at merge). Owner decisions
  and other rows are unchanged.

### D5. Delivery documents (after LOOP COMPLETE, not acceptance criteria)

`docs/product/aai-doctor.md` gains a CAT-20 paragraph, and `CHANGELOG.md` gains one
`## [unreleased] — ci: move CI to Node 24 and publish the Node floor` entry.
Both are written after the metrics flush (ship convention), are in the review
scope, and are not gated by a TEST row.

## Acceptance Criteria Mapping

- Intake AC-001 maps to Spec-AC-01 (pins and the reintroduction guard).
- Intake AC-002 maps to Spec-AC-03 and Spec-AC-04 (declared floor and its
  agreement with the doctor and the workflows).
- Intake AC-003 maps to Spec-AC-05 and Spec-AC-06 (WARN below 22, silent at 22
  and above, not FAIL).
- Intake AC-004 maps to Spec-AC-02 (Node 22 check inside the existing job) and
  hosted check H2 (its cost).
- Intake AC-005 (CI green on Node 24) is hosted check H1. It is verified after
  normal PR creation and before merge-readiness; it is deliberately not a
  Spec-AC, because a local run cannot attest it.
- Scope bullet "RFC-0017 table" maps to Spec-AC-07; "stale Node 20 comments"
  is part of Spec-AC-01.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | Every node-version value in .github/workflows/*.yml is '24' except exactly one '22' inside job self-hosting-smoke; at least 11 '24' pins exist; no workflow and no .aai/scripts file contains the text Node 20 or node-version '20'. | done | docs/ai/tdd/ci-node-24-baseline/green/test_138_ci_node_pins.log | — | TEST-2301 |
| Spec-AC-02 | Job self-hosting-smoke keeps its exact name, needs, if, runs-on and timeout; after its existing smoke step it has a setup-node step with node-version '22' followed by the step Node 22 compatibility (downstream floor), which runs set -euo pipefail, a Node 22 version assertion with no pipe into grep -q, node --check over every .aai/scripts mjs file, node --test tests/skills/lib/*.test.mjs, the self-hosting smoke script and the doctor JSON check for no CAT-20; skill-suite.yml has the baseline number of jobs. | done | docs/ai/tdd/ci-node-24-baseline/green/test_139_node22_compat_step.log, docs/ai/tdd/ci-node-24-baseline/green/compat-run-node22.log | — | TEST-2302 |
| Spec-AC-03 | docs/TECHNOLOGY.md declares the floor: the Version Matrix Node.js row has the version cell 24 baseline; 22 minimum downstream; 20 unsupported, the Runtime(s) bullet names all three, and no line of the file still calls the Node floor UNKNOWN. | done | docs/ai/tdd/ci-node-24-baseline/green/test_140_technology_node_floor.log | — | TEST-2303 |
| Spec-AC-04 | The floor has one value across its three holders: the doctor's exported NODE_FLOOR_MAJOR equals the TECHNOLOGY.md minimum and the compatibility pin, and NODE_BASELINE_MAJOR equals the TECHNOLOGY.md baseline and every other workflow pin. | done | docs/ai/tdd/ci-node-24-baseline/green/test_141_node_floor_single_value.log | — | TEST-2304 |
| Spec-AC-05 | WHEN the doctor runs on a Node whose major is below 22 (v20.11.1 and v21.7.3 through a preload), the system SHALL print one line starting CAT-20 WARN that names the running version, 22 and 24, and --json SHALL carry a CAT-20 entry with status WARN and detail floor_major 22 and baseline_major 24. | done | docs/ai/tdd/ci-node-24-baseline/green/test_2305_node_floor_warn_below.log | — | TEST-2305 |
| Spec-AC-06 | WHEN the doctor runs below the floor its FAIL count and plain exit code SHALL equal the same run at v22.0.0 and --strict SHALL exit 1; WHEN it runs at v22.0.0, v24.0.0, an unparseable version or the real runtime it SHALL print no CAT-20 line and --json SHALL carry no CAT-20 id. | done | docs/ai/tdd/ci-node-24-baseline/green/test_2306_node_floor_warn_not_fail.log, docs/ai/tdd/ci-node-24-baseline/green/test_2307_node_floor_silent_at_floor.log | — | TEST-2306, TEST-2307 |
| Spec-AC-07 | The RFC-0017 Rollout Status table has one row whose second cell is Node 24 CI baseline and published floor, whose status cell is done and whose link target ends in ci-node-24-baseline.md. | done | docs/ai/tdd/ci-node-24-baseline/green/test_142_rfc0017_node_row.log | — | TEST-2308 |

## Implementation plan

1. RED: add the four hygiene-pack functions and the three doctor functions;
   run each alone on the unchanged tree and store the RED output under
   `docs/ai/tdd/ci-node-24-baseline/red/`.
2. Edit the workflows (D1) and the comment (D4 first bullet); TEST-2301 and
   TEST-2302 go green.
3. Implement CAT-20 (D2); TEST-2305 to TEST-2307 go green.
4. Edit TECHNOLOGY.md and the RFC row (D3, D4); TEST-2303, TEST-2304 and
   TEST-2308 go green.
5. Run the compatibility step's `run:` block, extracted from skill-suite.yml,
   under local Node 22 and record exit code and wall time.
6. Record one mutation per row with `mutation-run.mjs`; run both suites through
   the wrapper.

Seams crossed:

- TECHNOLOGY.md (human-declared floor), aai-doctor.mjs (enforced floor) and the
  workflows (exercised floor and baseline) are three holders of one fact.
  TEST-2304 reads all three real files and fails when any one drifts.
- The doctor's category list is consumed by its own count pins (TEST-015 wants
  19 on this repo, TEST-028 wants 18 on its fixture). CAT-20 is silent at and
  above the floor, so those pins stay untouched; TEST-2307 asserts the silence on
  the real runtime, which is the condition those pins run under.
- The compatibility step consumes the doctor's JSON (no CAT-20 under Node 22).
  That seam is crossed only on hosted CI (H1); locally the same assertion is
  TEST-2307 at v22.0.0. Residual risk, written down: a hosted-only difference
  between the preload and a real Node 22 is caught only by H1.
- Branch protection consumes the job name of self-hosting-smoke; TEST-2302 pins
  it byte for byte.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-2301 | Spec-AC-01 | integration | tests/skills/test-aai-hygiene-pack.sh | test_138_ci_node_pins reads every .github/workflows/*.yml, collects each node-version value with its job, requires all to be 24 except exactly one 22 in self-hosting-smoke and at least 11 pins of 24, and fails on the text Node 20 or node-version '20' in any workflow or .aai/scripts file | `sed:s/node-version: '24'/node-version: '20'/` on .github/workflows/close-gate.yml | green |
| TEST-2302 | Spec-AC-02 | integration | tests/skills/test-aai-hygiene-pack.sh | test_139_node22_compat_step extracts the self-hosting-smoke job block and checks its name, needs, if, runs-on and timeout lines, the step order (smoke, setup-node 22, compat step), each required command in the compat run block, no grep -q pipe, and the top-level job count of skill-suite.yml | `sed:s/node --test tests\/skills\/lib\/\*\.test\.mjs/true/` on .github/workflows/skill-suite.yml | green |
| TEST-2303 | Spec-AC-03 | inspection | tests/skills/test-aai-hygiene-pack.sh | test_140_technology_node_floor parses the Version Matrix Node.js row and the Runtime(s) bullet of docs/TECHNOLOGY.md and fails on a missing value or any line calling the Node floor UNKNOWN | `sed:s/24 baseline; 22 minimum downstream; 20 unsupported/UNKNOWN (no pin)/` on docs/TECHNOLOGY.md | green |
| TEST-2304 | Spec-AC-04 | integration | tests/skills/test-aai-hygiene-pack.sh | test_141_node_floor_single_value imports NODE_FLOOR_MAJOR and NODE_BASELINE_MAJOR from the real aai-doctor.mjs and compares them with the TECHNOLOGY.md row values and with the workflow pins collected as in TEST-2301 | `sed:s/export const NODE_FLOOR_MAJOR = 22;/export const NODE_FLOOR_MAJOR = 21;/` on .aai/scripts/aai-doctor.mjs | green |
| TEST-2305 | Spec-AC-05 | integration | tests/skills/test-aai-doctor.sh | test_2305_node_floor_warn_below runs the real doctor CLI with a TEST_DIR preload faking v20.11.1, then v21.7.3, and asserts one CAT-20 WARN text line naming the version, 22 and 24, plus the --json CAT-20 entry status and detail | `sed:s/if \(major >= NODE_FLOOR_MAJOR\) return null;/return null;/` on .aai/scripts/aai-doctor.mjs | green |
| TEST-2306 | Spec-AC-06 | integration | tests/skills/test-aai-doctor.sh | test_2306_node_floor_warn_not_fail compares the --json FAIL count and the plain exit code at fake v20.11.1 with the same run at fake v22.0.0, and asserts --strict exits 1 at v20.11.1 | `sed:s/'Node Runtime', 'WARN'/'Node Runtime', 'FAIL'/` on .aai/scripts/aai-doctor.mjs | green |
| TEST-2307 | Spec-AC-06 | integration | tests/skills/test-aai-doctor.sh | test_2307_node_floor_silent_at_floor runs the doctor at fake v22.0.0, v24.0.0, an unparseable vX and without a preload, and asserts no CAT-20 text line and no CAT-20 id in --json each time; positive control: the v20.11.1 run of the same helper does print CAT-20 | `sed:s/major >= NODE_FLOOR_MAJOR/major > NODE_FLOOR_MAJOR/` on .aai/scripts/aai-doctor.mjs | green |
| TEST-2308 | Spec-AC-07 | inspection | tests/skills/test-aai-hygiene-pack.sh | test_142_rfc0017_node_row finds the Rollout Status row of RFC-0017 by its second cell and checks the done status and the link target suffix | `sed:s/Node 24 CI baseline and published floor/Node 24 CI move/` on docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md | green |

Test-file note: every row's selector is one function that runs alone under
single-function dispatch (`bash tests/skills/test-aai-hygiene-pack.sh <function>`,
`bash tests/skills/test-aai-doctor.sh <function>`), because `mutation-run.mjs`
runs bash suites only and dispatches one function. Each failure message names
the row's TEST id so `mutation-run.mjs` can attribute the RED. Each new function
is registered once in its suite's `main()`; `check-test-registration.mjs` must
stay at exit 0. The preload is a file written into `TEST_DIR` that redefines
`process.version` and `process.versions.node` with `Object.defineProperty`; it
is passed as `node --import <file> .aai/scripts/aai-doctor.mjs`. Mutation
patterns are JavaScript regular expressions (`(`, `.`, `+`, `*` escaped as
written), and only the g flag would be honoured.

### RED observations and positive controls

- TEST-2301 is RED on the baseline because 11 pins are '20'; TEST-2302 because
  the compatibility step does not exist; TEST-2303 because the row says UNKNOWN;
  TEST-2304 because the doctor exports no floor; TEST-2305 and TEST-2306 because
  no CAT-20 is ever printed; TEST-2308 because the row does not exist. Record
  each under `docs/ai/tdd/ci-node-24-baseline/red/`.
- TEST-2307 passes on the baseline (silence is the old behavior). Its RED is the
  mutation record, and its positive control (the v20.11.1 run must print CAT-20)
  makes it RED on the baseline too, which is the RED to store.
- TEST-2306 has a built-in positive control: it first asserts a CAT-20 WARN
  exists at v20.11.1, so a doctor that never reports passes no part of it.

## Verification

- Hygiene suite: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-hygiene-pack.sh` exits 0.
- Doctor suite: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-doctor.sh` exits 0.
- Pins: `grep -rn "node-version" .github/workflows` lists eleven `'24'` and one `'22'`.
- Doctor on the dev machine: `node .aai/scripts/aai-doctor.mjs --json` carries no `CAT-20`.
- Registration: `node .aai/scripts/check-test-registration.mjs tests/skills` exits 0.
- Compatibility block locally: extract the `run:` block of the step
  `Node 22 compatibility (downstream floor)` from skill-suite.yml and run it with
  bash under local Node 22; exit 0; record wall time (Planning estimate: about 17 s).
- Mutation records: `node .aai/scripts/mutation-run.mjs --spec <this spec> --test-id <id> --suite <suite> --selector <function> --target <file> --sed '<expr>'`
  per row; `node .aai/scripts/mutation-gate.mjs --spec <this spec>` exits 0.
- Spec lint: `node .aai/scripts/spec-lint.mjs --path <this spec>` reports no error.

### Hosted delivery checks (after normal PR creation, before merge-readiness)

These are not Spec-ACs and are not claimed by local Validation.

- H1 (intake AC-005): the PR head's skill-suite run (full framework, because
  docs-numbering.yml is unmapped) and the docs-numbering run conclude success,
  the aggregate gate job succeeds, and the setup-node log of every Node step
  resolves a 24.x version except the compatibility setup-node, which resolves
  22.x; the compatibility step logs the version assertion and exits 0. Evidence:
  run ids, head SHA and the matched log lines from `gh run view <id> --log`.
- H2 (cost, RFC-0017 decision 4): on the H1 run, the self-hosting-smoke job
  takes at most 120 s, the compatibility step at most 90 s, and the job
  completes before the slowest skills job of the same run. Evidence: step and job
  timestamps from `gh run view <id> --json jobs`. A breach is reported with the
  numbers and goes to the owner; it does not silently pass.

## Evidence contract

Per TEST and Spec-AC: command, exit code, output path under
`docs/ai/tdd/ci-node-24-baseline/`, and the mutation record from
`mutation-run.mjs`. Each AC Evidence cell cites a `docs/ai/tdd/` artifact at
hand-off. Strategy hybrid: stored RED per AC-gating test plus the verification
list above. H1 and H2 are recorded separately after PR creation. Planning's own
measurements above are inputs, not attestations of the implementation.

## Risks and rollback

- A Node 24 behavior difference in a Bash suite: Planning found no deprecated
  API in use and Node 26 passes the direct tests, but only H1 proves Node 24.
  A red H1 is diagnosed per suite (`aai-debug`), not waved through.
- Windows `native-worktree-seed` may download Node 24 if its tool cache lacks
  it; that adds seconds, not a failure mode. Recorded in H1 if it happens.
- The action runtimes of `actions/checkout@v4` and `actions/setup-node@v4` are
  GitHub's own concern and out of scope; this spec changes the Node used by the
  job steps only.
- Rollback is one revert of the scope's files.

## Registry disposition

Related open registry items, all left open:

- `fu-watchdog-3000-exceeds-ci-timeout` cites skill-suite.yml line numbers that
  this change shifts by two lines at most; its subject (timeouts) is untouched.
- `fu-test439-single-line-guard-grep` concerns the doctor's main guard, which is
  unchanged.
- `fu-sweep-check-not-a-required-check` concerns docs-numbering.yml's required
  status, which is unchanged.

Registry items closed by this scope: none.
