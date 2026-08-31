---
id: spec-aai-update-gitignore-drift-reconcile
type: spec
number: 157
status: done
ceremony_level: 2
links:
  requirement: docs/issues/ISSUE-0076-aai-update-gitignore-drift-reconcile.md
  rfc: null
  pr:
    - 326
  commits:
    - d88247a209c1cb3c88724d53c323f67acfc80f8c
---

# aai-update reconciles the runtime-sidecar .gitignore block into existing projects

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/ISSUE-0076-aai-update-gitignore-drift-reconcile.md
  (source: https://github.com/goodwind-cz/aai/issues/325)
- Decision records: CHANGE-0115 (`gitignore-seed`, PR #219 — the bootstrap
  seed); PR #223 (the bash sync-path reconcile)
- Technology contract: docs/TECHNOLOGY.md

## Problem restatement (measured, not assumed)

The intake states that `/aai-update` never reconciles the runtime-sidecar
`.gitignore` block because `aai-update.sh` -> `aai-sync` never calls
`ensure_gitignore()`. That sentence is literally true and its conclusion is
half wrong. Planning measured the real tree before specifying anything.

What is already correct (do NOT re-implement it):

- `.aai/scripts/aai-sync.sh` lines 520-541 ALREADY reconcile the runtime block
  on every sync, reading `.aai/system/RUNTIME_IGNORE.list`. It landed in
  e810522 (PR #223, 2026-08-03), independently of `ensure_gitignore()`.
- Measured on a stale fixture whose `.gitignore` held only `node_modules/`,
  `.env`, `docs/ai/reports/**`, `docs/ai/STATE.yaml`,
  `docs/ai/LOOP_TICKS.jsonl`: `bash .aai/scripts/aai-sync.sh <fixture>` added
  26 patterns and left 0 of the list's 29 patterns missing. A second run left
  the file byte-identical. The POSIX `/aai-update` path is not defective.

What is actually broken — the root cause of the reported symptom:

- `.aai/scripts/aai-sync.ps1` has NO runtime-sidecar reconcile at all. It
  never reads `RUNTIME_IGNORE.list` (measured: zero occurrences in every
  `.aai/scripts/*.ps1`). It seeds only its own hardcoded blocks: `.aai/`,
  `.cloudflare-publish*`, `.wrangler/`, `.aai/cache/`, `docs/ai/reports/**`
  plus two negations, five agent-skill directories, `docs/ai/STATE.yaml` and
  `docs/ai/LOOP_TICKS.jsonl`.
- Measured: `pwsh -NoProfile -File .aai/scripts/aai-sync.ps1 -TargetRoot
  <fixture>` on a `.gitignore` holding only `node_modules/` leaves 24 of the
  29 runtime-sidecar patterns MISSING, and the resulting file's AAI-owned set
  is exactly `docs/ai/reports/**`, `docs/ai/STATE.yaml`,
  `docs/ai/LOOP_TICKS.jsonl` — byte-for-byte the reporter's described state,
  including the specific gaps they name (`docs/ai/briefs`, `tdd`,
  `validation`, `friction`, `archive`, `locks`, `loop`). The reporter's pin
  07d6920 (2026-08-17) POST-dates the bash fix, which is why a bash-only
  explanation cannot account for their observation and the PowerShell path
  can.

The second real defect, and the one the intake's Constraints section names
directly ("one shared implementation, not a second copy that could drift"):

- The runtime-sidecar reconcile is FORKED in bash. `aai-bootstrap.sh`
  `ensure_gitignore()` (lines 742-806) and `aai-sync.sh` (lines 520-541)
  each carry their own copy, with DIFFERENT marker strings. Measured
  consequence on a target that carries the bootstrap marker and then gets
  synced: `grep -c '# AAI runtime sidecars' .gitignore` returns 2. Adding a
  third PowerShell copy without collapsing the bash fork would make drift
  worse, not better.

- `.aai/system/RUNTIME_IGNORE.list`'s own header claims it is consumed by
  `migrate-state-to-local.ps1`. Measured: that file contains zero references
  to the list. The single-source claim the whole design rests on is
  documented inaccurately.

Framing that follows from the measurement: a shell library cannot be shared
across bash and PowerShell, so "one implementation" is unachievable and is
not the goal. The achievable and correct goal is ONE implementation PER
LANGUAGE, both driven by the ONE data file `.aai/system/RUNTIME_IGNORE.list`,
which is the actual single source of truth.

## Registry items closed by this scope

none. `node .aai/scripts/follow-ups.mjs list` reports 79 open items; none
names the runtime-ignore seed, `RUNTIME_IGNORE.list`, or the bootstrap/sync
gitignore fork. The nearest neighbour, `fu-sync-hash-compare-fails-open`,
concerns `file_content_different` hash handling in `aai-sync.sh` and is a
different subject on a different code path — this scope neither fixes nor
touches it.

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred: entire spec postponed; explain reason in this section
- rejected: spec was abandoned; explain rationale
- superseded: replaced by a newer spec; set links to the replacement

## Implementation strategy
- Strategy: direct
- Rationale: the failing observation already exists and is quantified in this
  document (24 of 29 patterns missing after a real `aai-sync.ps1` run; marker
  count 2 after bootstrap-then-sync), so a RED-first ceremony would re-derive
  evidence Planning has already produced and read. The change is a small,
  data-driven shell edit across three call sites with an exact, countable
  observable per acceptance criterion, and the whole risk sits in regression
  (existing projects must not gain duplicates or lose user entries), which
  targeted regression tests cover directly. Per the Evidence-by-strategy
  table, `direct` demands targeted regression tests green plus the scoped
  diff, and NO stored RED artifact — this spec demands no stored RED artifact
  anywhere.

Allowed strategy values:
- loop: implementation agent covers all TEST-xxx entries in one focused pass
- tdd: RED-GREEN-REFACTOR is required per TEST-xxx
- hybrid: TDD for risky/core behavior, loop implementation for low-risk glue or docs
- direct: direct implementation plus targeted regression tests, no RED-first ceremony
- untested: direct implementation with NO tests; allowed only with a recorded rationale
- undecided: planning is incomplete and implementation must not start

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: the scope edits three vendored installer scripts that
  the test suites EXECUTE, and `tests/skills/test-aai-sync-seed.sh` runs the
  real `aai-sync.sh` and `aai-sync.ps1` from the working tree into temp
  targets. An in-flight edit to those scripts is live to every concurrently
  running suite in the same tree. The scope is also PR-bound and touches no
  protected path, so isolation is useful but not mandated.
- User decision: undecided
- Base ref: main
- Worktree branch/path: to be chosen by Implementation Preparation
- Inline review scope: see `## Code review scope` below

## Boundaries and non-goals

In scope:
- `.aai/scripts/aai-sync.ps1` gains the runtime-sidecar reconcile.
- The bash fork collapses into one sourceable library used by both bash
  callers.
- `.aai/system/PROFILES.yaml` classifies the new library file.
- `.aai/system/RUNTIME_IGNORE.list` header is corrected to name its real
  consumers.
- Regression coverage in `tests/skills/test-aai-sync-seed.sh` and the suite
  map glob that selects it.

Explicitly OUT of scope (named because a reader will be tempted):
- Adding an `ensure_gitignore()` CALL to `aai-update.sh`. The update path
  already reconciles through `aai-sync.sh`; a second call site would append
  the same patterns twice through two markers and is the opposite of the fix.
- Any change to `.gitignore` content policy, i.e. adding or removing runtime
  patterns from `RUNTIME_IGNORE.list`.
- The reporter's suggested `aai-doctor` signal for a missing or partial
  runtime-ignore block. The intake itself calls it an ALTERNATIVE, and the
  update-path reconciliation is the actual fix. Not planned here.
- Collapsing pre-existing duplicate marker lines already written into a
  downstream project's `.gitignore` by past syncs. The PowerShell script's
  existing self-heal block is untouched; this scope stops the growth, it does
  not run a migration.
- Any refactor of `aai-sync.sh` or `aai-sync.ps1` beyond the gitignore
  section.
- No file under `protected_paths_l3` is touched. Verified against
  `docs/ai/docs-audit.yaml`: `state.mjs`, `state-engine.mjs`,
  `state-core.mjs`, `allocate-doc-number.mjs`, `pre-commit-checks.sh/.ps1`,
  `.aai/workflow/WORKFLOW.md`, `docs/CONSTITUTION.md` are all outside this
  scope. No L3 escalation is required.

## Seams this change crosses

| Seam   | Producer                          | Consumer                                   | Risk if untested                                                        | Covered by |
|--------|-----------------------------------|--------------------------------------------|-------------------------------------------------------------------------|------------|
| SEAM-1 | .aai/system/RUNTIME_IGNORE.list   | aai-bootstrap.sh, aai-sync.sh, aai-sync.ps1 | three readers of one data file drift apart and seed different sets       | TEST-009, TEST-016 |
| SEAM-2 | aai-bootstrap.sh writes .gitignore | aai-sync.sh appends to the SAME .gitignore | two markers and duplicated patterns accumulate in one file across runs   | TEST-010   |
| SEAM-3 | aai-sync writes .gitignore        | git status in the target project           | patterns present but ineffective leave runtime spools untracked-visible  | TEST-013   |
| SEAM-4 | PROFILES.yaml core list           | aai-sync profile pruning                   | a core-profile target prunes the new library and both bash callers break | TEST-011, TEST-012 |
| SEAM-5 | RUNTIME_IGNORE.list header prose  | a maintainer adding the next consumer      | a false consumer list sends the next edit to the wrong file              | TEST-015   |

Residual risk no automated test in this repo crosses: real Windows
PowerShell 5.1 semantics. Local and CI Linux coverage runs pwsh 7. The
`windows-5_1` job in `.github/workflows/ps1-quality.yml` parse-checks and
smoke-runs `aai-sync.ps1` under genuine 5.1, so a 5.1-only runtime semantic
in the new block surfaces there and not in the local suite. Implementation
must keep the new PowerShell block to 5.1-compatible constructs already used
elsewhere in the same file.

## Constitution deviations

None.

## Acceptance Criteria Mapping

- Maps to: the intake's Expected Behavior and Verification bullets.
- Spec-AC-01..03 deliver the Expected Behavior on the defective path.
- Spec-AC-04..05 deliver the intake's Constraints requirement.
- Spec-AC-06..07 keep the fix alive under profiles and degradation.
- Spec-AC-08 delivers the intake's `git status` verification bullet.
- Spec-AC-09 corrects the single-source documentation the design rests on.

## Acceptance Criteria Status

| Spec-AC    | Description                                                                                                                                                                                                 | Status  | Evidence | Review-By | Notes |
|------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | WHEN aai-sync.ps1 runs against a target whose .gitignore lacks runtime-sidecar patterns the system SHALL append every non-comment non-blank line of .aai/system/RUNTIME_IGNORE.list that is not already present as an exact line, leaving 0 of the list's patterns missing | done | TEST-007, TEST-009, TEST-018 green | — | measured today at 24 missing of 29; 0 missing after fix |
| Spec-AC-02 | WHEN aai-sync.ps1 runs a second time against the same target the system SHALL leave .gitignore byte-identical and every runtime-sidecar pattern SHALL occur exactly once                                      | done | TEST-008, TEST-018 green | — | sha256 equality plus per-pattern count of 1 |
| Spec-AC-03 | WHEN a target .gitignore contains user entries and a comment mentioning a runtime path the PowerShell reconcile SHALL preserve every user line verbatim and in original order and SHALL still seed the mentioned pattern as its own exact line | done | TEST-009, TEST-018 green | — | exact-line match parity with bash |
| Spec-AC-04 | Exactly one bash implementation of the runtime-sidecar reconcile SHALL exist, in .aai/scripts/lib/gitignore-block.sh, and aai-bootstrap.sh and aai-sync.sh SHALL each reach it by sourcing that file rather than by carrying their own append loop over RUNTIME_IGNORE.list | done | TEST-011, TEST-017 green | — | one reader per language is the goal |
| Spec-AC-05 | WHEN a target .gitignore already carries either legacy runtime-sidecar marker line and a later bootstrap or sync run seeds further patterns the system SHALL NOT add a second marker, so grep -c for the marker prefix returns exactly 1                        | done | TEST-010, TEST-017 green | — | measured today at 2; 1 after fix, on both engines |
| Spec-AC-06 | .aai/scripts/lib/gitignore-block.sh SHALL appear in the core list of .aai/system/PROFILES.yaml and SHALL be present in a target after a core-profile sync                                                     | done | TEST-012, TEST-013 green | — | PROFILES companion obligation |
| Spec-AC-07 | WHEN the runtime list file or the shared library is absent the reconcile SHALL skip, emit a note naming the missing path, and return exit status 0 without failing its caller                                 | done | TEST-014 green | — | Constitution article 4 |
| Spec-AC-08 | WHEN the update path syncs a git-initialized target and the AAI runtime files then exist on disk git status --porcelain SHALL report zero paths matching the runtime-sidecar set, on both the bash and the PowerShell engine | done | TEST-015 green | — | the intake's own verification bullet |
| Spec-AC-09 | Every script named in the Consumed by header of .aai/system/RUNTIME_IGNORE.list SHALL contain at least one textual reference to that list file, and every .aai script that reads the list SHALL be named in that header | done | TEST-016 green | — | migrate-state-to-local.ps1 names zero today; header corrected |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan

Components affected:

1. `.aai/scripts/lib/gitignore-block.sh` (NEW). One sourceable function, e.g.
   `aai_gitignore_seed_runtime <gitignore_path> <runtime_list_path>
   [<dry_run>]`, that: reads the list, skips blank and `#` lines, appends only
   patterns absent by exact-line match (`grep -qxF`), writes the marker at
   most once and only when the file carries no line starting with the marker
   PREFIX `# AAI runtime sidecars`, prints one summary line naming the count
   added, and returns 0 when the list path does not exist after printing a
   named skip note. Bash 3.2 compatible (the repo's floor). The function takes
   both paths as parameters precisely because the two callers resolve them
   differently: bootstrap resolves the list relative to its own
   `${BASH_SOURCE[0]}/../system`, while sync prefers `$SRC_ROOT` and falls
   back to `$DST_ROOT`. That resolution stays at each call site; only the
   reconcile moves.

2. `.aai/scripts/aai-bootstrap.sh` — `ensure_gitignore()` keeps its three
   `.cache` patterns and its `DRY_RUN`/`WRITTEN` bookkeeping, and delegates
   the runtime-sidecar half to the library. It must degrade to its current
   named-skip behavior when the library is absent.

3. `.aai/scripts/aai-sync.sh` — the block at lines 520-541 is replaced by the
   list-path resolution it already performs plus one call into the library.

4. `.aai/scripts/aai-sync.ps1` — a NEW block placed alongside the other
   gitignore sections, before the existing self-heal dedup block so the
   self-heal still sees whatever the new block wrote. It resolves the list as
   `$SourceRoot/.aai/system/RUNTIME_IGNORE.list` with a
   `$TargetRoot/.aai/system/RUNTIME_IGNORE.list` fallback, mirroring the bash
   resolution order, and matches lines with the same anchored, CRLF-tolerant
   regex the agent-skill block already uses
   (`"(?m)^" + [regex]::Escape($entry) + "\r?$"`). Windows PowerShell 5.1
   compatible constructs only.

5. `.aai/system/PROFILES.yaml` — add `.aai/scripts/lib/gitignore-block.sh` to
   `core:`, adjacent to the existing `.aai/scripts/lib/append-lock.sh` and
   `.aai/scripts/lib/repo-tripwire.sh` entries.

6. `.aai/system/RUNTIME_IGNORE.list` — header comment corrected to name the
   real consumers.

7. `tests/skills/test-aai-sync-seed.sh` — new cases TEST-007..TEST-016. The
   file already runs both engines and already owns a bash-versus-PowerShell
   parity case (TEST-003), so it is the correct home; its existing local ids
   stop at TEST-006, so the new ids do not collide.

8. `tests/skills/suite-map.yaml` — add `.aai/scripts/lib/gitignore-block.sh`
   and `.aai/system/RUNTIME_IGNORE.list` to the `aai-sync-seed` globs, and the
   library to the `aai-bootstrap` globs, so an edit to either selects the
   suites that cover it.

Data flow: `RUNTIME_IGNORE.list` (data) -> per-language reconcile (bash
library or PowerShell block) -> target `.gitignore` -> `git status` in the
target project.

Edge cases the implementation must handle:
- Target has no `.gitignore` at all. The `.aai/` seed in both sync engines
  already creates it and always terminates its last line, so the runtime
  block never faces a file lacking a trailing newline. Do not reorder the
  runtime block ahead of the `.aai/` seed.
- Target `.gitignore` uses CRLF. The PowerShell block must match with the
  `\r?$` anchor, as the agent-skill block already does.
- Target carries the OLD bootstrap marker text, the OLD sync marker text, or
  both. Marker detection is by PREFIX, never by full string.
- A comment line that merely mentions a pattern must not suppress that
  pattern's seed. This is already asserted for bootstrap in
  `tests/skills/test-aai-bootstrap.sh` and must hold on the PowerShell side.
- `!` negation lines are ordinary patterns to this code and must be seeded in
  list order so the `.gitkeep` placeholders stay tracked.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                | Description                                                                                                    | Status  |
|----------|------------|-------------|-------------------------------------|----------------------------------------------------------------------------------------------------------------|---------|
| TEST-007 | Spec-AC-01 | integration | tests/skills/test-aai-sync-seed.sh  | real aai-sync.ps1 into a temp target whose .gitignore holds only node_modules, then count list patterns absent by exact-line match equals 0 | green   |
| TEST-008 | Spec-AC-02 | integration | tests/skills/test-aai-sync-seed.sh  | second aai-sync.ps1 run leaves the same sha256 and each runtime pattern occurs exactly once                     | green   |
| TEST-009 | Spec-AC-03, Spec-AC-01 | integration | tests/skills/test-aai-sync-seed.sh  | seeded PowerShell target keeps its user lines verbatim and in order and still seeds a pattern only mentioned inside a comment | green   |
| TEST-010 | Spec-AC-05 | integration | tests/skills/test-aai-sync-seed.sh  | target pre-seeded with the legacy bootstrap marker then synced by each engine yields exactly one marker-prefix line and no duplicated pattern | green   |
| TEST-011 | Spec-AC-04 | unit        | tests/skills/test-aai-sync-seed.sh  | static counts show one bash reader of RUNTIME_IGNORE.list under .aai plus one source of the library in each of aai-bootstrap.sh and aai-sync.sh | green   |
| TEST-012 | Spec-AC-06 | unit        | tests/skills/test-aai-sync-seed.sh  | PROFILES.yaml core extraction contains the library path, matching the awk extraction the existing TEST-003 uses  | green   |
| TEST-013 | Spec-AC-06 | integration | tests/skills/test-aai-sync-seed.sh  | aai-sync.sh with --profile core into a temp target leaves the library file present and bootstrap still exits 0 there | green   |
| TEST-014 | Spec-AC-07 | unit        | tests/skills/test-aai-sync-seed.sh  | sourcing the library and calling it with a nonexistent list path prints a note naming that path and returns 0     | green   |
| TEST-015 | Spec-AC-08 | integration | tests/skills/test-aai-sync-seed.sh  | git-initialized target synced by each engine, runtime spool files created, git status --porcelain lists zero runtime-sidecar paths | green   |
| TEST-016 | Spec-AC-09 | unit        | tests/skills/test-aai-sync-seed.sh  | every script named in the list header references the list and every .aai script referencing the list is named in the header | green   |
| TEST-017 | Spec-AC-04, Spec-AC-05 | integration | tests/skills/test-aai-bootstrap.sh  | the pre-existing bootstrap gitignore cases stay green after the extraction, including marker count 1 and pre-existing entries surviving | green   |
| TEST-018 | Spec-AC-01, Spec-AC-02, Spec-AC-03 | integration | tests/skills/test-aai-sync-seed.sh  | bash aai-sync.sh regression on the same fixtures as TEST-007 and TEST-008 so the POSIX path that works today is pinned against the extraction | green   |

Test status values: pending -> red -> green

Notes:
- Every Spec-AC has at least one TEST-xxx row.
- Test IDs are stable after freeze.
- TEST-017 lives in the bootstrap suite because that is where the existing
  `ensure_gitignore()` contract is already asserted; it is a pin on unchanged
  behavior, not new behavior.

### Pre-change failing observations (strategy: direct)

This spec stores no TDD-cycle artifact and demands none. It does require that
each new TEST-xxx row is observed FAILING on the pre-change tree once, and
that the observation is reported in the Implementation return record as a
one-line command plus its observed value. Planning has already produced the
pre-change observations for the headline criteria and records them here so
they are not re-derived:

- Spec-AC-01 pre-change: 24 of 29 runtime patterns missing after
  `pwsh -NoProfile -File .aai/scripts/aai-sync.ps1 -TargetRoot <fixture>`.
- Spec-AC-05 pre-change: `grep -c '# AAI runtime sidecars' .gitignore` returns
  2 on a target carrying the bootstrap marker after a bash sync.
- Spec-AC-09 pre-change: `grep -c RUNTIME_IGNORE
  .aai/scripts/migrate-state-to-local.ps1` returns 0 while the header names
  that file.

## Verification

Directly executable commands:

- `bash tests/skills/test-aai-sync-seed.sh` — TEST-007..TEST-016, TEST-018.
- `bash tests/skills/test-aai-bootstrap.sh` — TEST-017.
- `bash tests/skills/test-aai-layer-profiles.sh` — PROFILES.yaml invariant
  after the core-list addition.
- `bash .aai/scripts/aai-run-tests.sh --suites aai-sync-seed,aai-bootstrap,aai-layer-profiles`
  — the same suites through the canonical isolating wrapper.
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0157-spec-aai-update-gitignore-drift-reconcile.md`
  — spec structure, advisory.
- `pwsh -NoProfile -Command "Invoke-Pester tests/skills/aai-update.Tests.ps1"`
  — the PowerShell entrypoint still parses and runs. Existing coverage, run as
  a regression guard because `aai-sync.ps1` changes underneath it.

PASS criteria: all TEST-xxx in status green AND all Spec-AC in a terminal
status.

## Evidence contract

For each implementation, validation and code review artifact, record: ref_id,
Spec-AC and TEST-xxx links, the command run, the exit code, the evidence path,
and the commit SHA or diff range.

### Evidence by strategy

| Strategy     | Evidence this spec may demand                                   |
|--------------|-----------------------------------------------------------------|
| tdd / hybrid | stored RED artifact per AC-gating test plus the full verification matrix |
| loop         | per-TEST-xxx green runs; RED-proof observed, storage optional    |
| direct       | targeted regression tests green (exit codes) plus the scoped diff — NO stored RED artifact, NO matrix beyond the declared versions |
| untested     | the recorded strategy rationale plus the scoped diff             |

This spec is `direct`. It demands the exit codes of the five suite commands
listed under `## Verification`, the scoped diff, and the per-TEST pre-change
observation lines described above. It demands no `docs/ai/tdd/` artifact.

## Code review scope

Required: true (a real shell and PowerShell code change plus a governance
manifest edit).

Explicit paths:
- `.aai/scripts/lib/gitignore-block.sh` (new)
- `.aai/scripts/aai-bootstrap.sh`
- `.aai/scripts/aai-sync.sh`
- `.aai/scripts/aai-sync.ps1`
- `.aai/system/PROFILES.yaml`
- `.aai/system/RUNTIME_IGNORE.list`
- `tests/skills/test-aai-sync-seed.sh`
- `tests/skills/test-aai-bootstrap.sh`
- `tests/skills/suite-map.yaml`

Diff range: `main..<implementation branch>`

Review must specifically check: that no fourth reader of
`RUNTIME_IGNORE.list` was introduced; that the PowerShell block uses only
Windows PowerShell 5.1 compatible constructs; that marker detection is by
prefix so neither legacy marker string can produce a second marker; and that
the new block sits BEFORE the PowerShell self-heal dedup block.

## Companion obligations

- Prompt corpus (`.aai/*.prompt.md`, `.aai/AGENTS.md`): not touched. No
  prompt-diet ledger entry and no TEST-012 checkpoint bump are owed.
- New `.aai/**` file: YES — `.aai/scripts/lib/gitignore-block.sh`. The
  PROFILES.yaml classification is folded into scope as Spec-AC-06 and into
  the Test Plan as TEST-012 and TEST-013.

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
