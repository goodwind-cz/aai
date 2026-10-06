---
id: spec-worktree-lacks-vendored-aai-layer-downstream
type: spec
number: 209
status: done
mutation_gate: v1
frozen_sha256: 1948f469ad2d6cd88848dd7947507f696e3c15ea099dce30f66b4edc7b8d2cab
ceremony_level: 2
links:
  requirement: worktree-lacks-vendored-aai-layer-downstream
  rfc: null
  pr:
    - 433
  commits:
    - 5f5fb10a
---

# Spec — Seed the installed AAI layer before entering a downstream worktree

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/ISSUE-0093-worktree-lacks-vendored-aai-layer-downstream.md
- Technology contract: docs/TECHNOLOGY.md
## Registry items closed by this scope

none

Registry scan: `node .aai/scripts/follow-ups.mjs list` on 2026-10-06.
`fu-seed-partial-verdict-unasserted` concerns the disposable test runner's
seeding verdict; `fu-seeded-copies-lesson-no-guard` concerns pre-pull cleanup
of untracked project documents. Neither is closed by copying installed AAI
infrastructure into a feature worktree. `fu-realpath-allocate-doc-number-l3`
and `fu-measurement-ledger-old-reader` concern other consumers, not this seed.

## Implementation strategy

- Strategy: tdd
- Rationale: Owner chose full TDD at intake on 2026-10-03; the matching
  `implementation_strategy.ref_id` and `source: intake` are present in STATE.
  Preserve that choice. Every TEST row owes observed RED, GREEN and a
  behavior-relevant mutation; do not count MODULE_NOT_FOUND as the final RED
  proof for a newly introduced helper.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: Multi-surface runtime and prompt fix with integration
  fixtures; isolation protects concurrent work. The source repository tracks
  its layer and can host this implementation independently of the downstream
  bug. Planning does not create a worktree.
- User decision: undecided
- Base ref: main
- Worktree branch/path: implementation preparation resolves for this scope;
  STATE's existing roadmap-maintenance worktree belongs to another scope.
- Inline review scope: .aai/SKILL_WORKTREE.prompt.md, .aai/scripts/worktree-seed.mjs,
  .aai/system/PROFILES.yaml, tests/skills/test-aai-worktree-seed.sh,
  tests/skills/aai-worktree-seed.Tests.ps1, tests/skills/test-aai-worktree.sh,
  tests/skills/suite-map.yaml, tests/skills/lib/prompt-diet-ledger.sh,
  .github/workflows/ps1-quality.yml, .github/workflows/skill-suite.yml,
  tests/skills/test-aai-suite-select.sh,
  tests/skills/test-aai-prompt-diet.sh, CHANGELOG.md, docs/USER_GUIDE.md,
  docs/issues/ISSUE-0093-worktree-lacks-vendored-aai-layer-downstream.md,
  docs/specs/SPEC-0209-spec-worktree-lacks-vendored-aai-layer-downstream.md
- Code review required: true; explicit paths above, plus scoped TDD evidence.

## Acceptance Criteria Mapping

The intake has no numbered ACs. Its Expected Behavior and Verification bullets
map as follows. Commands and evidence keys refer to the Verification section.

| Requirement | Spec-AC | Verification | Observable and evidence |
|---|---|---|---|
| Same installed layer, skills, version and profile | Spec-AC-01 | V1, TEST-001 and TEST-002 | Real core and extended installations reproduce missing layer before seed; seed returns 0; installed file inventory and SHA-256 bytes match, including AAI_PIN; V1 log |
| First AAI command succeeds | Spec-AC-02 | V1, TEST-003 and TEST-011 | Seeded worktree executes check-state --repair then check-state with exit 0 and stamped STATE; setup resolves the source repository root even when invoked from a subdirectory; V1 log |
| Never dispatch into an incomplete worktree | Spec-AC-03 | V1, TEST-004 and TEST-005 | Named nonzero refusal; origin STATE unchanged; no success decision or dispatch marker; V1 log |
| Source repository still works | Spec-AC-04 | V1, TEST-006 | Tracked branch-local layer bytes survive unchanged; seed exit 0; state initializer runs; V1 log |
| Never accidentally track the vendored layer | Spec-AC-05 | V1, TEST-007 | Every seeded untracked file remains ignored and absent from git add -A index; runtime sentinels absent; V1 log |
| Windows and both supported shells | Spec-AC-06 | V2, TEST-008 | Shared Node seeder works from PowerShell on space-containing paths without links or privileged APIs; real native downstream fixture passes; V2 log |
| Copy drift and independent ownership addressed | Spec-AC-07 | V1, TEST-009 | Rerun is byte-idempotent; source-only update leaves target bytes and pin unchanged; conflicting existing ignored destination is refused unchanged; V1 log |
| New layer file and prompt growth obligations | Spec-AC-08 | V1 and V3, TEST-010 | Core installation includes helper; profile classification and prompt-diet checks exit 0; suite-map routes helper changes to regression suite; V1/V3 logs |

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN setup seeds a downstream checkout the system SHALL copy the installed infrastructure inventory and bytes for core and extended profiles, including all four installed skill roots and the pin. | done | docs/ai/reports/VALIDATION-20261006T181711Z-worktree-lacks-vendored-aai-layer-downstream.md; TEST-001/002 | — | Exclusions in D2 |
| Spec-AC-02 | WHEN seeding succeeds the worktree SHALL execute its own canonical state initializer and state check with exit 0. | done | docs/ai/reports/VALIDATION-20261006T181711Z-worktree-lacks-vendored-aai-layer-downstream.md; TEST-003 | — | No live STATE carry |
| Spec-AC-03 | WHEN the source, target, ignore safety or copy operation is invalid the system SHALL report a named reason, return nonzero and stop before recording setup success or dispatching a role. | done | docs/ai/reports/VALIDATION-20261006T181711Z-worktree-lacks-vendored-aai-layer-downstream.md; TEST-004/005 | — | Test both helper and prompt ordering |
| Spec-AC-04 | WHEN the destination tracks its AAI files the system SHALL preserve those files byte-for-byte, including branch-local changes, and permit initialization. | done | docs/ai/reports/VALIDATION-20261006T181711Z-worktree-lacks-vendored-aai-layer-downstream.md; TEST-006 | — | Never overwrite tracked files |
| Spec-AC-05 | WHEN infrastructure is seeded the system SHALL leave every newly copied file ignored and untracked and SHALL copy zero excluded runtime files. | done | docs/ai/reports/VALIDATION-20261006T181711Z-worktree-lacks-vendored-aai-layer-downstream.md; TEST-007 | — | Includes staging probe |
| Spec-AC-06 | WHEN invoked from bash or Windows PowerShell 5.1 or pwsh 7 the shared seeder SHALL satisfy the same downstream success and refusal behavior without creating symlinks. | deferred | docs/ai/reports/VALIDATION-20261006T181711Z-worktree-lacks-vendored-aai-layer-downstream.md; TEST-008 | 2026-10-20 | Pre-PR Bash real downstream and macOS pwsh evidence passed; neither proves native Windows. Windows PowerShell 5.1 and pwsh 7 Pester fixture checks are required in PR CI before merge; see the measurement amendment below. |
| Spec-AC-07 | WHEN the origin is updated after seeding the worktree SHALL retain its independent installed snapshot; identical reruns SHALL succeed unchanged and conflicting reruns SHALL refuse without replacing existing files. | done | docs/ai/reports/VALIDATION-20261006T181711Z-worktree-lacks-vendored-aai-layer-downstream.md; TEST-009 | — | No automatic cross-worktree update |
| Spec-AC-08 | WHEN core profile distribution and test selection run the helper SHALL be installed, selected for regression, and accounted for by the profile and prompt-growth ledgers. | done | docs/ai/reports/VALIDATION-20261006T181711Z-worktree-lacks-vendored-aai-layer-downstream.md; TEST-010 | — | V3 profiles and prompt-diet-final logs also pass |

## Implementation plan

### D1 — One portable seed operation

Add `.aai/scripts/worktree-seed.mjs`, Node stdlib only, callable from the
originating checkout before changing directories:

`node .aai/scripts/worktree-seed.mjs --source <absolute-source-root> --target <absolute-worktree-root>`

The CLI must resolve and validate both repository roots, refuse identical or
nested roots, and require the target to be an existing registered linked
worktree of the same Git common directory. Use Git plumbing and canonical
paths, not guesses about `.git` being a directory. A normal local clone is
not a target for this operation. The shared `.mjs` is the shell-parity
implementation; do not add duplicated bash and PowerShell copy engines.

### D2 — Installed snapshot and safety boundary

Copy ordinary files/directories under `.aai/`, `.agents/skills/`,
`.claude/skills/`, `.codex/skills/`, and `.gemini/skills/` from the selected
originating checkout. Preserve bytes and executable modes where supported.
Copy the installed inventory, including project additions within these skill
roots; never invoke sync, fetch, an installer, or resolve a newer source.
This retains the profile's omissions and exact `.aai/system/AAI_PIN.md`.
Required source files include AGENTS.md, ORCHESTRATION.prompt.md,
SKILL_WORKTREE.prompt.md, scripts/check-state.mjs, scripts/state.mjs and
templates/STATE_TEMPLATE.yaml. A downstream source also requires its pin.
Absent optional skill roots are named as skipped, not fabricated.

Exclude `.aai/cache/` entirely. Do not copy docs/ai, live STATE, briefs,
telemetry, project documents, `.git`, hook installation state, local harness
configuration, or `skills.local/`. Existing tracked destination files are
authoritative for that branch and are never replaced. For each missing
untracked destination, require Git to report it ignored before copying;
refuse otherwise rather than editing .gitignore. Mixed tracked/ignored
roots are evaluated per file. Preserve unrelated existing destination files.
An existing untracked same-byte file is idempotent; a differing one is a
named conflict, never overwritten. Reject symlinks in traversed source or
destination paths with an actionable path-specific diagnostic; do not follow
links outside these roots or introduce a need for Windows link privileges.

Validate the planned inventory before writes and verify copied bytes before
success. Any filesystem failure returns nonzero with operation and path.
No multi-root atomicity is promised: newly created files may remain after a
copy failure, but no STATE decision, success registry entry or role dispatch
may follow. An identical rerun may finish a partial seed; conflicts refuse.
The helper never writes STATE, modifies Git tracking, creates/removes a
worktree, installs hooks, or changes the origin checkout.

### D3 — Actual workflow seam

Insert seeding between successful `git worktree add` and the first worktree
`check-state.mjs --repair` in Setup Worktree. Capture absolute origin and
target paths before the directory switch. Provide runnable bash and
PowerShell command forms with explicit nonzero handling (including
`$LASTEXITCODE` in PowerShell). Seed failure stops before state initialization,
worktree decision, success registry/metrics, or first role dispatch. Retain
the existing canonical state initializer and session-lock ordering.
Tests execute the documented seed-and-initialize command sequence, with a
dispatch/success sentinel after the gate, rather than merely finding a token.

### D4 — Snapshot lifetime and explicit limits

Report that a downstream worktree receives an independent snapshot of the
origin's installed version/profile. Document in the worktree prompt and
USER_GUIDE: updating the origin does not update existing worktrees; run
`/aai-update` explicitly in the worktree to update that installation. A later
seed attempt from a changed origin refuses conflicts and does not serve as
an updater. Copying also prevents edits in a worktree from modifying the
origin's installed layer. This fixes setup, not every raw `git worktree add`.

Live STATE/brief handoff after Planning is explicitly out of scope: it needs
separate lifecycle semantics, and this change retains fresh initialization.
The disposable test runner path is also out of scope. Source inspection of
`.aai/scripts/aai-run-tests.sh` shows its suite predicate accepts project
`tests/**/test-*.sh` files without an AAI-source-repository check, uses a local
clone now, and overlays only untracked non-ignored files. Thus its missing
ignored layer risk still applies downstream; this fix makes no claim that
the clone gains AAI. Planning did not execute that separate reproduction.
Implementation/Validation must name this limitation in the handoff; do not
silently broaden the linked-worktree CLI to all clones.

### D5 — Distribution and regression integration

Classify the new helper in the core list of `.aai/system/PROFILES.yaml`.
Register the new suite and helper/prompt dependencies in suite-map.yaml using
the existing discovery convention. Add the required JUSTIFIED_ADDITIONS
entry and adjust the TEST-012 checkpoint in the prompt-diet ledger for net
prompt growth; use existing test harness checks, not guessed byte counts.
Record the user-facing fix and snapshot lifetime in CHANGELOG and USER_GUIDE.
Do not modify protected L3 state/allocator/guard/workflow files for this scope.

### Crossings and residual risks

- Installer -> ignored installed files -> real Git checkout -> seeder:
  TEST-001/002 compare actual installed inventories for both profiles.
- Seeder -> canonical state initializer -> dispatch gate: TEST-003/004/005
  run actual tools and prove success/failure sequencing.
- Branch's tracked checkout -> seeding: TEST-006 preserves branch-local bytes.
- Ignore rules -> Git index: TEST-007 performs `git add -A` in the fixture.
- PowerShell -> Node -> Git/filesystem: TEST-008 executes on Windows, not a
  POSIX stand-in; unavailable local Windows is disclosed until CI evidence.
- Origin update -> independent worktree: TEST-009 asserts both directions of
  isolation and conflict refusal.
- Profile/suite map/prompt ledger -> downstream installation and CI selection:
  TEST-010 and V3.

Concurrent origin updates during seed are not a supported locking protocol;
copy/verification failures must refuse, and callers must not run an updater
against the source during setup. Agent obedience to the prompt cannot be
proven by an automated test; executable command-sequence tests and explicit
ordering checks are the bounded evidence. The helper itself never dispatches.

## Test Plan

All fixture Git repositories configure their own user.name/user.email and
check setup exits. Fixtures live under one private absolute scratch root;
no test writes Git state in the shipping repository. Use TEST selection in
the new suite so each row is directly runnable. Mutation patches below are
concrete required artifacts generated in TDD against the implementation:
each changes the named behavior, never the test or fixture assertions.

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-worktree-seed.sh | Real core sync, commit, worktree add; pre-seed missing layer; post-seed inventory/bytes, four skill roots and pin equal | patch:docs/ai/tdd/spec-worktree-lacks-vendored-aai-layer-downstream/mutation-TEST-001.patch | green |
| TEST-002 | Spec-AC-01 | integration | tests/skills/test-aai-worktree-seed.sh | Real extended sync fixture preserves extended file and installed pin; no network or sync during seed | patch:docs/ai/tdd/spec-worktree-lacks-vendored-aai-layer-downstream/mutation-TEST-002.patch | green |
| TEST-003 | Spec-AC-02 | integration | tests/skills/test-aai-worktree-seed.sh | Execute seeded worktree check-state --repair and check-state, assert stamped file and absence of origin live-state sentinel | patch:docs/ai/tdd/spec-worktree-lacks-vendored-aai-layer-downstream/mutation-TEST-003.patch | green |
| TEST-004 | Spec-AC-03 | integration | tests/skills/test-aai-worktree-seed.sh | Missing source canon, foreign/identical/nested target, symlink and deterministic non-directory destination refuse with path; origin remains unchanged | patch:docs/ai/tdd/spec-worktree-lacks-vendored-aai-layer-downstream/mutation-TEST-004.patch | green |
| TEST-005 | Spec-AC-03 | integration | tests/skills/test-aai-worktree-seed.sh | Execute prompt's setup segment; seed refusal prevents state/decision/dispatch sentinels; success reaches real initializer; assert ordering before success record | patch:docs/ai/tdd/spec-worktree-lacks-vendored-aai-layer-downstream/mutation-TEST-005.patch | green |
| TEST-006 | Spec-AC-04 | integration | tests/skills/test-aai-worktree-seed.sh | Real tracked-layer fixture with differing branch-local tracked file remains unchanged and initializes successfully; mixed roots preserve tracked entries | patch:docs/ai/tdd/spec-worktree-lacks-vendored-aai-layer-downstream/mutation-TEST-006.patch | green |
| TEST-007 | Spec-AC-05 | integration | tests/skills/test-aai-worktree-seed.sh | Stage all in seeded downstream fixture, assert zero infrastructure additions; cache/runtime/local-config sentinels absent; unsafe ignore rule refuses before copy | patch:docs/ai/tdd/spec-worktree-lacks-vendored-aai-layer-downstream/mutation-TEST-007.patch | green |
| TEST-008 | Spec-AC-06 | integration | tests/skills/test-aai-worktree-seed.sh | Real Bash downstream fixture exercises shared Node seeder on spaced paths; local pwsh Pester fixture exercises sync/worktree/seed/init, refusal and no links; native Windows Pester runs are PR CI evidence | patch:docs/ai/tdd/spec-worktree-lacks-vendored-aai-layer-downstream/mutation-TEST-008.patch | green |
| TEST-009 | Spec-AC-07 | integration | tests/skills/test-aai-worktree-seed.sh | Identical rerun unchanged; mutate origin file/pin and target file independently, assert opposite side unchanged; reseed conflict nonzero and destination preserved | patch:docs/ai/tdd/spec-worktree-lacks-vendored-aai-layer-downstream/mutation-TEST-009.patch | green |
| TEST-010 | Spec-AC-08 | contract | tests/skills/test-aai-worktree-seed.sh | Core distribution, suite selection and prompt ledger credit include this helper/change; run existing profile/diet suites | patch:docs/ai/tdd/spec-worktree-lacks-vendored-aai-layer-downstream/mutation-TEST-010.patch | green |
| TEST-011 | Spec-AC-02 | integration | tests/skills/test-aai-worktree-seed.sh; tests/skills/aai-worktree-seed.Tests.ps1 | Invoke the prompt's source-root capture from a repository subdirectory and require both Bash and PowerShell forms to resolve the Git top level | docs/ai/tdd/spec-worktree-lacks-vendored-aai-layer-downstream/red-TEST-011-subdirectory-source-root.md | green |

## Verification

- V1: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-worktree-seed.sh`
  must exit 0 and report all declared POSIX test cases executed and passed.
  Individual case form: append `--test TEST-001` (likewise other POSIX IDs).
- V2: `powershell -NoProfile -Command "Invoke-Pester -Path tests/skills/aai-worktree-seed.Tests.ps1 -EnableExit"`
  and the same invocation using `pwsh` on Windows must exit 0, with zero
  failed or skipped declared tests. This is the native Pester lane, not a bash
  test bypass; use existing ps1-quality CI jobs for Windows evidence.
- V3: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-layer-profiles.sh`
  and `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh`
  must exit 0. Run the existing aai-worktree suite for regression and inspect
  any failure against base rather than assuming it is new.
- Lint: `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0209-spec-worktree-lacks-vendored-aai-layer-downstream.md`.
- Mutation replay: `node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-0209-spec-worktree-lacks-vendored-aai-layer-downstream.md`.

Store output and exits at
`docs/ai/tdd/worktree-lacks-vendored-aai-layer-downstream-{red,green,validation}.log`;
label TEST IDs and platform in each segment. Mutation records belong at
`docs/ai/tdd/spec-worktree-lacks-vendored-aai-layer-downstream/mutation-TEST-xxx.txt`.

## Amendment — TEST-008 measurement and Windows evidence timing (2026-10-06)

The original Spec-AC-06 functional promise, Windows crossing, TEST-008 native
fixture description and V2 command above remain the target. For the pre-PR
handoff, V1's real Bash downstream TEST-008 case and a local macOS pwsh run of
`tests/skills/aai-worktree-seed.Tests.ps1` are executable evidence. The
behavior-relevant TEST-008 mutation changes `.aai/scripts/worktree-seed.mjs`
and is measured by `test_008_spaces` in the Bash suite because
`mutation-run.mjs` does not execute Pester. The Pester fixture itself remains
mandatory under native Windows PowerShell 5.1 and pwsh 7 in pull-request CI.
The `skill-suite` native Windows job feeds the branch-protected aggregate gate;
the `ps1-quality` Windows job also checks the three cases. Each engine must
pass all three cases with none skipped before merge. Local pwsh on macOS does
not establish either native Windows verdict. Spec-AC-06 is deferred until
those CI results exist;
TEST-008's green status denotes executable pre-PR local and mutation evidence,
not completion of native Windows acceptance.

RED first: TEST-001 reproduces the original missing ignored layer on the
pre-change checkout. For a new CLI, establish a parseable no-op skeleton and
observe semantic assertions fail; syntax/missing-tool failures are not RED.
Tests for existing safety behavior must be shown failing under the specific
declared removal mutation, with that distinction recorded. For prompt and
ledger rows, observe absent wiring/credit failure before adding the change.
No suite run or product PASS is claimed by Planning.

## Evidence contract

Every artifact records ref_id, Spec-AC and TEST links, exact command and
platform, exit code, log path and diff/commit identity. TDD requires stored
RED per AC-gating test, GREEN output and behavior-relevant mutation records.
Validation independently repeats the declared matrix and reports any missing
Windows coverage as unverified, not a passing local substitute. All TEST
rows become green only with their evidence; AC terminal states must cite
`docs/ai/tdd/` proof artifacts. The authoritative Validation report includes
an admissible aai-outcome-v1 block and the returned evidence path matches it.
