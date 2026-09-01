---
id: spec-intake-staleness-preflight-warning
type: spec
number: 158
status: done
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0168-intake-staleness-preflight-warning.md
  rfc: null
  pr:
    - 327
  commits:
    - 019e96a
---

# Intake warns, once and silently-by-default, that the checkout it is running in is stale

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0168-intake-staleness-preflight-warning.md
- Decision records: intake `## Notes` (soft warning not a hard gate; real
  current truth via `git fetch` over local-cache comparison) — both honoured
  verbatim below.
- Technology contract: docs/TECHNOLOGY.md

## Problem restatement (measured, not assumed)

Measured on this tree before specifying anything:

- Nine files make up the shared intake entry point: `.aai/SKILL_INTAKE.prompt.md`
  (the router) and the eight `.aai/INTAKE_{CHANGE,HOTFIX,ISSUE,PRD,RELEASE,RESEARCH,RFC,TECHDEBT}.prompt.md`
  per-type prompts. Every one of the eight carries exactly one line
  `SHARED POLICY — Read .aai/INTAKE_COMMON.md and apply its four blocks
  (language policy, durable doc identity, post-save check, metrics question)`
  and the router carries the same line saying `five blocks` (it additionally
  names the implementation mode choice). Not one of the nine performs any
  check on the freshness of the checkout before its first question.
- `.aai/INTAKE_COMMON.md` (6430 B) currently holds five `## ` blocks plus
  `## SECRETS PREFLIGHT`. It is the correct single home for a sixth shared
  block: it is the only file all nine already read, and its blocks are already
  applied by reference rather than restated per type.
- The check itself must NOT live in the prompt as prose. `.aai/INTAKE_COMMON.md`
  is inside `tests/skills/test-aai-prompt-diet.sh` TEST-010's *extra accounting*
  (line 329: `[[ -f .aai/INTAKE_COMMON.md ]] && extra=$((extra + ...))`), and the
  eight per-type prompts plus the router are inside its live `.aai/*.prompt.md`
  glob (line 327). Every byte of prose added here is charged against the
  SPEC-0017 diet floor. A script under `.aai/scripts/` is charged nothing.
- Prior art for exactly this shape already exists and must be reused rather than
  reinvented: `.aai/scripts/layer-drift.mjs` `git()` (lines 122-134) runs bounded,
  prompt-free git plumbing — `spawnSync('git', argv, { timeout, env: { ...process.env,
  GIT_TERMINAL_PROMPT: '0' } })` — and both it and `.aai/scripts/update-check.mjs`
  declare `const DEFAULT_TIMEOUT_MS = 10_000` as this repo's standing bound on a
  git call that may reach the network.
- This repository has no `.gitmodules`. Every submodule assertion in this spec is
  therefore exercised against a purpose-built scratch fixture, never against the
  shipping tree.
- A hard pin blocks the naive edit: `tests/skills/test-aai-implementation-mode.sh`
  line 78 asserts `grep -qF "five blocks" "$SKILL_INTAKE"`. Adding a sixth shared
  block reddens that suite unless the pin is moved in the same change. This is a
  companion obligation of the scope, not a surprise for Implementation to discover.

What this scope therefore builds: one new script that answers "is this checkout
behind?" deterministically and silently, and one shared prompt block, referenced
from nine files by one line each, that runs it before the first question and
relays whatever it printed.

## Registry items closed by this scope

none. `node .aai/scripts/follow-ups.mjs list` reports 78 open items. Three name
the intake family and were read line by line before this claim:
`fu-intake-templates-lack-number-key` (P3 — seven intake TEMPLATES carry no
`number:` key), `fu-intake-dir-unanchored-research-hotfix` (P2 — the
`.aai/INTAKE_COMMON.md` DURABLE DOC IDENTITY table row and the per-type prompt
can drift together to a wrong directory for research and hotfix), and
`fu-typemap-missing-research-hotfix` (P2 — `allocate-doc-number.mjs` TYPE_MAP has
no research/hotfix row). The middle one shares FILES with this scope
(`.aai/INTAKE_COMMON.md` and the eight per-type prompts) but not its SUBJECT:
closing it requires a new pin tying each per-type prompt's opening directory line
to the shared table's row, which is doc-identity work with its own fixtures and no
overlap with a staleness preflight. Widening this diff into it would break the
scope-only constraint the intake sets. Not closed, deliberately.
`fu-staleness-source-line-self-certifies` matches on the word "staleness" only —
it concerns `docs/INDEX.md` regeneration, a different subject entirely.

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred: entire spec postponed; explain reason in this section
- rejected: spec was abandoned; explain rationale
- superseded: replaced by a newer spec; set links to the replacement

## Implementation strategy
- Strategy: hybrid
- Rationale: the intake recorded no implementation-mode choice (its `## Notes`
  carries no `Implementation mode (user choice):` line; the operator explicitly
  left the call to Planning), and the leftover `implementation_strategy` in STATE
  belongs to a prior unrelated scope, so this is a fresh decision. The scope
  splits cleanly into two classes with genuinely different evidence needs.
  Spec-AC-01..06 specify a NEW script whose dominant failure mode is SILENCE:
  three of those six acceptance criteria (02, 05, 06) are satisfied by printing
  nothing, so a script that is broken into permanent silence passes half the
  suite vacuously. That is precisely the class RED-first exists for, and it is
  compounded here by fixtures that are themselves easy to build wrong (a scratch
  clone that is not actually behind produces a green silence test that proves
  nothing). Those six ACs take the TDD lane: a stored RED artifact under
  `docs/ai/tdd/` per AC-gating test, AND — because RED alone does not defeat
  vacuity on a silence assertion — a recorded BITE PROOF per silence arm (see
  `### Vacuity defence` below). Spec-AC-07..11 are static text and configuration
  pins over files that already exist; a RED-first ceremony there would only
  re-observe that a line not yet written is absent. Those take the direct lane:
  targeted regression tests green plus the scoped diff, each observed failing
  once on the pre-change tree and reported in the return record, with no stored
  RED artifact demanded. Per the `### Evidence by strategy` table, `hybrid` is
  the value that names this split honestly; recording `direct` would understate
  what the silence ACs owe, and recording `tdd` would tax five text pins for
  nothing.

Allowed strategy values:
- loop: implementation agent covers all TEST-xxx entries in one focused pass
- tdd: RED-GREEN-REFACTOR is required per TEST-xxx
- hybrid: TDD for risky/core behavior, loop implementation for low-risk glue or docs
- direct: direct implementation plus targeted regression tests, no RED-first ceremony
- untested: direct implementation with NO tests; allowed only with a recorded rationale
- undecided: planning is incomplete and implementation must not start

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: the scope edits nine prompt files that live suites grep by
  literal string (`test-aai-intake.sh`, `test-aai-implementation-mode.sh`,
  `test-aai-prompt-diet.sh`) and adds a script the new tests EXECUTE, so an
  in-flight edit is immediately visible to any concurrently running suite in the
  same tree. It also mutates the prompt-diet ledger and the TEST-012 pin, whose
  half-applied state reddens two suites at once. The scope is PR-bound and
  touches no `protected_paths_l3` file, so isolation is useful but not mandated —
  `recommended`, not `required`. Implementation Preparation asks and decides.
- User decision: undecided
- Base ref: main
- Worktree branch/path: to be chosen by Implementation Preparation
- Inline review scope: see `## Code review scope` below

## Boundaries and non-goals

In scope:
- `.aai/scripts/intake-staleness-check.mjs` (NEW) — the whole check.
- `.aai/INTAKE_COMMON.md` — one new shared block, `## STALENESS PREFLIGHT`.
- `.aai/SKILL_INTAKE.prompt.md` — a `STEP 0` that applies the block before
  STEP 1, plus its SHARED POLICY line moving `five blocks` -> `six blocks`.
- the eight `.aai/INTAKE_*.prompt.md` — their SHARED POLICY line moving
  `four blocks` -> `five blocks` and naming the preflight first.
- `.aai/system/PROFILES.yaml` — classification of the new script (companion
  obligation: a new `.aai/**` file).
- `tests/skills/lib/prompt-diet-ledger.sh` + `tests/skills/test-aai-prompt-diet.sh`
  — itemized JUSTIFIED_ADDITIONS entry and the TEST-012 `want_growth` pin
  (companion obligation: prompt-corpus byte growth).
- `tests/skills/test-aai-implementation-mode.sh` — the `five blocks` pin moved.
- `tests/skills/test-aai-intake.sh` — the new TEST-020..TEST-029 cases.
- `tests/skills/suite-map.yaml` — the new script added to the `aai-intake` globs.

Explicitly OUT of scope (named because a reader will be tempted):
- Running `git pull`, `git submodule update`, `git merge`, `git rebase`, `git
  checkout`, or ANY command that writes the working tree, the index, or a local
  branch ref. The check reads; it never repairs. `git fetch` is the single
  permitted write and it touches `refs/remotes/*` only.
- Blocking, refusing, or delaying intake on a stale tree. The intake's recorded
  decision is a soft warning; nothing in this scope may return a non-zero exit
  that a prompt could read as a gate.
- `/aai-update` and its sync mechanism (`.aai/scripts/update-check.mjs`,
  `layer-drift.mjs`, `aai-update.{sh,ps1}`). That is a different, existing,
  AAI-LAYER-version question — this scope asks whether the PROJECT checkout is
  behind. No file of that mechanism is edited.
- A PowerShell twin of the new script. The check is invoked from a prompt by an
  agent that always has `node` (every other intake step already invokes `node`),
  so the `.mjs` is platform-complete on its own; there is no `.ps1` mirror
  obligation here, unlike the installer/hook family.
- Caching or throttling the fetch across intakes (the `update-check.mjs`
  throttle-cache pattern). One intake, one probe; a cache would reintroduce the
  stale-answer problem the feature exists to remove.
- No file under `protected_paths_l3` is touched. Verified against
  `docs/ai/docs-audit.yaml` lines 74-82: `state.mjs`, `state-engine.mjs`,
  `state-core.mjs`, `allocate-doc-number.mjs`, `pre-commit-checks.sh`,
  `pre-commit-checks.ps1`, `.aai/workflow/WORKFLOW.md`, `docs/CONSTITUTION.md`
  are all outside this scope. No L3 escalation is required.

## Design decisions

- D1 — the check is a SCRIPT, invoked by one line. `.aai/scripts/intake-staleness-check.mjs`
  holds all logic. The prompt block says what to run and what to do with the
  output, nothing about how staleness is computed. This is the intake's own
  named lower-cost path and it keeps the prompt-corpus charge to the block plus
  nine one-line edits.
- D2 — the block lives in `.aai/INTAKE_COMMON.md`, not in `.aai/SKILL_INTAKE.prompt.md`
  alone. A per-type prompt can be invoked directly, bypassing the router; the
  intake requires all eight types to get the preflight. `INTAKE_COMMON.md` is the
  only file all nine already read.
- D3 — output prefix is `AAI-STALE: `, one line per stale ref, on stdout. The
  intake's `⚠` example is illustrative ("e.g."). This repo's own convention for a
  machine-greppable named diagnostic is an `AAI-<TOPIC>: ` prefix
  (`AAI-ENV-ERROR:`, `AAI-SPAWN-ERROR:`, `AAI-BRANCH:` — docs/TECHNOLOGY.md), and
  the SPEC template forbids decorative icons. A literal prefix is also what makes
  Spec-AC-01/02/03 countable rather than judged.
- D4 — TIMEOUTS. Per-`git fetch` bound: **5000 ms**. Total preflight wall-clock
  budget across the superproject fetch and every submodule fetch: **10000 ms**;
  once the budget is spent, remaining submodules are skipped silently. Justified
  concretely, as the intake demands: 5000 ms is this repo's existing bound for
  probing a possibly-unavailable external process (`update-check.mjs`
  `pwshAvailable`, `aai-doctor.mjs` line 484 both use `5_000`), and 10000 ms is
  exactly `DEFAULT_TIMEOUT_MS` in both `layer-drift.mjs` and `update-check.mjs` —
  so the whole preflight can never cost the operator more wall clock than the one
  network probe this repo already accepts elsewhere. A per-fetch bound alone is
  not enough: N submodules x 5 s is unbounded in N, and an intake author waiting
  to type is the case the intake says must never hang. Both are overridable
  (`--timeout-ms`, `--budget-ms`) so the tests can drive them deterministically.
- D5 — NO INTERACTIVE PROMPT, ever. The fetch runs with `GIT_TERMINAL_PROMPT=0`
  (the `layer-drift.mjs` pattern) AND with credential helpers and askpass
  disabled for that invocation, so a private remote in a keychain environment
  degrades exactly like an unreachable one instead of raising a dialog. A failed
  auth is indistinguishable from no network by design (intake Constraints).
- D6 — EXIT CODE IS ALWAYS 0 for every runtime outcome, including every
  degradation. Exit 2 is reserved for CLI usage errors when a human runs it by
  hand with a bad flag, mirroring `update-check.mjs`. Nothing a prompt sees can
  be read as a gate.
- D7 — the submodule comparison ref is `submodule.<name>.branch` from
  `.gitmodules` when configured, else the submodule remote's default branch
  resolved from `refs/remotes/origin/HEAD`. When neither resolves, that submodule
  degrades silently and the others are still reported.

## Seams this change crosses

| Seam   | Producer                                   | Consumer                                          | Risk if untested                                                                                  | Covered by |
|--------|--------------------------------------------|---------------------------------------------------|---------------------------------------------------------------------------------------------------|------------|
| SEAM-1 | `.aai/INTAKE_COMMON.md` STALENESS PREFLIGHT block | the eight per-type `.aai/INTAKE_*.prompt.md`  | a block only the router applies leaves seven of eight intake types with no preflight at all         | TEST-026   |
| SEAM-2 | `.aai/INTAKE_COMMON.md` block body          | `.aai/SKILL_INTAKE.prompt.md` STEP 0              | the preflight is applied AFTER the first question, i.e. after the artifact is already being drafted | TEST-027   |
| SEAM-3 | `intake-staleness-check.mjs` stdout          | the prompt that relays it                          | the prompt greps for a prefix the script does not emit, so a real warning is silently swallowed     | TEST-020, TEST-022, TEST-026 |
| SEAM-4 | the new `.aai/**` file                       | `.aai/system/PROFILES.yaml` union + core sync      | an unclassified file reddens `test-aai-layer-profiles.sh` TEST-001 and is pruned from core targets  | TEST-028   |
| SEAM-5 | the nine prompt-file edits                   | `test-aai-prompt-diet.sh` TEST-010/TEST-012 floor  | uncredited growth breaches the diet floor, or a padded credit breaches HEADROOM_CAP=2048            | TEST-029   |
| SEAM-6 | the sixth shared block                       | `test-aai-implementation-mode.sh` `five blocks` pin | an unmoved pin reddens a suite this scope never intended to touch                                   | TEST-030   |
| SEAM-7 | `intake-staleness-check.mjs` `git fetch`     | the operator's real repository state               | a check that repairs instead of reporting mutates the tree the author is about to describe          | TEST-023   |
| SEAM-8 | the new script path                          | `suite-map.yaml` selector                          | a later edit to the script selects no suite, so CI covers it by accident or not at all              | TEST-031   |

Residual risk no automated test in this repo crosses: real credential-helper
behaviour on a developer machine with a GUI keychain (macOS Keychain, Windows
Credential Manager) against a genuinely private remote. TEST-024 exercises the
auth-failure path with an unreachable authenticated URL and closed stdin, which
proves the no-hang and no-output contract but cannot prove that no OS-level
dialog appears on a machine configured with a GUI helper. D5's helper-disabling
is the mitigation; the residual is field-only. Second residual: whether the
LLM actually obeys the block and runs the script before its first question is
not machine-verifiable — TEST-026/TEST-027 pin the wiring (the block exists, all
nine reference it, and the reference precedes each file's first-question line),
which is the strongest deterministic proxy available and the same proxy
`test-aai-implementation-mode.sh` TEST-002 already uses for ordering.

## Constitution deviations

None.

## Acceptance Criteria Mapping

- Maps to: the intake's AC-001..AC-006 and its Verification fixtures A-E.
- Spec-AC-01 <- intake AC-001 / Fixture A (branch behind).
- Spec-AC-02 <- intake AC-002 / Fixture B (fully current, silent).
- Spec-AC-03 <- intake AC-003 / Fixture C (submodule behind).
- Spec-AC-04 <- intake AC-004 / Fixture E (tree-mutation proof).
- Spec-AC-05 <- intake AC-005 / Fixture D (no network, bounded).
- Spec-AC-06 <- intake AC-006 (no upstream / detached HEAD, submodule survives).
- Spec-AC-07..11 deliver the intake's Affected Area (all eight types get it via
  the shared entry point) and its Constraints section's named bookkeeping
  (PROFILES classification, diet ledger + TEST-012 pin) plus the pin this scope
  necessarily disturbs.

## Acceptance Criteria Status

| Spec-AC    | Description                                                                                                                                                                                                                                                                                  | Status  | Evidence | Review-By | Notes                                                                 |
|------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------|----------|-----------|-----------------------------------------------------------------------|
| Spec-AC-01 | WHEN the current branch of the inspected repository is behind its configured upstream by N greater than or equal to 1 commits the system SHALL print exactly one stdout line matching `^AAI-STALE: branch <branch> is <N> commit(s) behind <upstream> ` and SHALL exit 0                        | done | TEST-020 green; docs/ai/tdd/red-TEST-0020-*.log, docs/ai/tdd/green-TEST-0020-*.log | —| N is the exact `git rev-list --count HEAD..@{u}` value, not an adjective |
| Spec-AC-02 | WHEN the inspected repository is level with its upstream and carries no submodule that is behind the system SHALL write zero bytes to stdout and SHALL exit 0                                                                                                                                   | done | TEST-021 green (bite proof recorded); docs/ai/tdd/red-TEST-0021-*.log, docs/ai/tdd/green-TEST-0021-*.log | —| silence arm — TEST-021 carries a mandatory bite proof                   |
| Spec-AC-03 | WHEN an initialized submodule is behind its comparison ref by N greater than or equal to 1 commits while the superproject branch is level the system SHALL print exactly one line matching `^AAI-STALE: submodule <path> is <N> commit(s) behind ` and zero lines matching `^AAI-STALE: branch` | done | TEST-022 green; docs/ai/tdd/red-TEST-0022-*.log, docs/ai/tdd/green-TEST-0022-*.log | —| independence of the two checks is the assertion                         |
| Spec-AC-04 | WHEN the check runs against a repository with real staleness to detect the byte sequences of `git status --porcelain`, `git rev-parse HEAD`, `git for-each-ref refs/heads` and `git submodule status` SHALL be identical immediately before and immediately after the run                        | done | TEST-023 green; docs/ai/tdd/red-TEST-0023-*.log, docs/ai/tdd/green-TEST-0023-*.log | —| four captures, byte-compared; `refs/remotes/*` deliberately excluded    |
| Spec-AC-05 | WHEN every configured remote is unreachable or refuses authentication and stdin is closed the system SHALL write zero bytes to stdout, SHALL exit 0, and SHALL return within `--budget-ms` plus 2000 ms of wall clock                                                                            | done | TEST-024 green (bite proof recorded); docs/ai/tdd/red-TEST-0024-*.log, docs/ai/tdd/green-TEST-0024-*.log | —| silence arm — bite proof mandatory; timing is measured, not asserted by feel |
| Spec-AC-06 | WHEN the current branch has no configured upstream, or HEAD is detached, the system SHALL print zero lines matching `^AAI-STALE: branch` and SHALL still print the submodule line for a behind submodule in the same repository                                                                  | done | TEST-025 green (bite proof recorded); docs/ai/tdd/red-TEST-0025-*.log, docs/ai/tdd/green-TEST-0025-*.log | —| silence arm plus a positive co-assertion so silence cannot be blanket   |
| Spec-AC-07 | `.aai/INTAKE_COMMON.md` SHALL contain exactly one `## STALENESS PREFLIGHT` heading whose body names `.aai/scripts/intake-staleness-check.mjs`, states that its stdout is relayed verbatim when non-empty, and states that intake proceeds to the first question regardless of its outcome         | done | TEST-026 green; observed failing once on pre-change tree (Implementation return record) | —| the soft-warning decision expressed where the agent reads it            |
| Spec-AC-08 | Each of the nine shared-entry-point files SHALL carry a line naming the staleness preflight, and in each file that line's line number SHALL be lower than the line number of that file's first-question line                                                                                     | done | TEST-026/TEST-027 green; observed failing once on pre-change tree (Implementation return record) | —| eight `BEGIN with` lines plus the router's `STEP 1 — DETECT TYPE`       |
| Spec-AC-09 | `.aai/scripts/intake-staleness-check.mjs` SHALL appear exactly once across the `core:` and `extended:` lists of `.aai/system/PROFILES.yaml`, in the `core:` list, and `tests/skills/test-aai-layer-profiles.sh` SHALL exit 0                                                                     | done | TEST-028/TEST-031 green, test-aai-layer-profiles.sh exit 0; observed failing once on pre-change tree | —| companion obligation: a new `.aai/**` file                             |
| Spec-AC-10 | `tests/skills/lib/prompt-diet-ledger.sh` SHALL carry one new JUSTIFIED_ADDITIONS entry whose leading byte field equals the measured corpus growth of this scope, `want_growth` in `tests/skills/test-aai-prompt-diet.sh` SHALL equal the new independent re-sum, and that suite SHALL exit 0     | done | TEST-010/TEST-012 green in tests/skills/test-aai-prompt-diet.sh, 787 B measured growth, want_growth 7340 -> 8127 | —| measurement under plain bash with `/usr/bin/grep`, never the alias      |
| Spec-AC-11 | `tests/skills/test-aai-implementation-mode.sh` SHALL exit 0 after the shared-block count moves from five to six                                                                                                                                                                                 | done | tests/skills/test-aai-implementation-mode.sh exit 0 (TEST-002 re-run green) | —| the pin this scope necessarily disturbs, moved in the same change       |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan

Components affected:

1. `.aai/scripts/intake-staleness-check.mjs` (NEW). Node ESM, `node:` stdlib
   only, no dependency, `#!/usr/bin/env node`, guarded `main()` in the shape the
   other `.aai/scripts/*.mjs` use.

   CLI: `node .aai/scripts/intake-staleness-check.mjs [--repo <path>]
   [--timeout-ms <n>] [--budget-ms <n>] [--no-fetch]`.
   `--repo` defaults to the current working directory and exists so tests drive
   scratch fixtures without `cd`. `--no-fetch` skips the network entirely and
   compares against whatever remote-tracking refs exist, which makes the compare
   logic testable with zero network. Unknown flag or missing value -> exit 2 with
   a usage line on stderr (D6).

   Flow, in order:
   a. Resolve `--repo` to a git work tree (`git -C <repo> rev-parse --git-dir`).
      Not a repo, or `git` not on PATH -> silent exit 0.
   b. Start the wall-clock budget.
   c. Superproject: resolve `@{u}`. Absent (fresh local branch) or HEAD detached
      -> skip the branch arm silently, continue to submodules. Present -> fetch
      that remote (bounded by `--timeout-ms`, D4/D5), then
      `git rev-list --count HEAD..@{u}`. Count > 0 -> one `AAI-STALE: branch` line.
      Any failure at any step -> skip the branch arm silently.
   d. Submodules: enumerate INITIALIZED submodules only. For each, while budget
      remains: resolve the comparison ref per D7, fetch it bounded, count
      `HEAD..<ref>`, emit one `AAI-STALE: submodule` line when > 0. Any per-submodule
      failure degrades that submodule alone, never the others, never the run.
   e. Exit 0.

   Reuse, do not re-invent: copy the `git()` helper shape from
   `.aai/scripts/layer-drift.mjs` lines 122-134 (`spawnSync`, `timeout`,
   `GIT_TERMINAL_PROMPT: '0'`, `timedOut` detection) rather than writing a fourth
   variant. Extend it with the D5 credential-helper/askpass disabling. Do not
   import from `layer-drift.mjs`: it is a CLI with its own argv contract, and a
   cross-import would put a network probe used by the SessionStart hook on the
   intake path's dependency chain.

2. `.aai/INTAKE_COMMON.md` — a new `## STALENESS PREFLIGHT (before the first
   question)` block. Keep it SHORT; every byte is charged (Spec-AC-10). It must
   state: run the script once before the first question; if stdout is non-empty,
   relay it verbatim to the user; proceed to the first question in every case,
   including a non-empty warning; never run `git pull`, `git submodule update` or
   any other repair on the author's behalf; if the script or `node` is absent
   (older AAI layer), skip silently and continue. Also update this file's own
   opening sentence, which today says "the four universal blocks below".

3. `.aai/SKILL_INTAKE.prompt.md` — a `STEP 0 — STALENESS PREFLIGHT` placed above
   `STEP 1 — DETECT TYPE`, applying the block by reference, plus the SHARED POLICY
   line's `five blocks` -> `six blocks` with the preflight named.

4. The eight `.aai/INTAKE_*.prompt.md` — one line each: `four blocks` -> `five
   blocks`, naming `staleness preflight` FIRST in the parenthesised list so the
   ordering the agent reads matches the ordering it must execute. The line already
   sits above each file's `BEGIN with` line (measured), so Spec-AC-08's ordering
   assertion holds without moving anything else.

5. `.aai/system/PROFILES.yaml` — `.aai/scripts/intake-staleness-check.mjs` added
   to `core:` (the intake flow is the workflow engine, which is the file's own
   stated classification rule), placed among its alphabetical neighbours
   `hitl-channel.mjs` / `install-pre-commit-hook.*`. Note the existing list is not
   strictly sorted at that point (`lane-gate.mjs` precedes `install-*` today);
   match the neighbourhood, do not re-sort the file — a re-sort is an unrequested
   surface change and would be flagged in review.

6. `tests/skills/lib/prompt-diet-ledger.sh` — one appended JUSTIFIED_ADDITIONS
   entry, `"<bytes> intake-staleness-preflight-warning <what and why>"`, whose
   leading field is the MEASURED growth of the live `.aai/*.prompt.md` glob plus
   the `.aai/INTAKE_COMMON.md` extra-accounting delta for this scope, measured
   under plain `bash` with `/usr/bin/grep` and `wc -c` (never the `ugrep` alias).
   `tests/skills/test-aai-prompt-diet.sh` — `want_growth` (currently `7340`, line
   732) bumped to the new independent re-sum, with the customary comment recording
   the before/after byte totals.

7. `tests/skills/test-aai-implementation-mode.sh` — line 78's `"five blocks"`
   becomes `"six blocks"`.

8. `tests/skills/test-aai-intake.sh` — new cases TEST-020..TEST-031. This file
   already owns the intake wiring pins (its local ids stop at TEST-019, so the new
   ids do not collide) and already builds scratch git fixtures, so it is the
   correct home. Every fixture is created under a `mktemp -d` path and removed on
   EXIT; no case may write the shipping repository.

9. `tests/skills/suite-map.yaml` — `.aai/scripts/intake-staleness-check.mjs` added
   to the `aai-intake` globs (line 400-416) so a later edit to the script selects
   the suite that covers it.

Data flow: the operator's checkout (git refs) -> `intake-staleness-check.mjs`
(bounded, read-only) -> stdout `AAI-STALE:` lines -> the shared block's relay ->
the intake author's screen, before the first question.

Edge cases the implementation must handle:
- A local-path submodule fixture needs `git -c protocol.file.allow=always
  submodule add`; modern git refuses local-path submodules otherwise. The tests
  will not build without it.
- A repository with `.gitmodules` but NO initialized submodule: enumerate
  initialized ones only, otherwise every uninitialized entry is a wasted fetch
  and a possible spurious line.
- A submodule whose remote has no `refs/remotes/origin/HEAD` and no
  `submodule.<name>.branch`: D7 says degrade that submodule silently.
- HEAD detached in the SUPERPROJECT while a submodule is behind: the branch arm
  must skip without short-circuiting the submodule arm (Spec-AC-06 asserts exactly
  this co-occurrence).
- An upstream configured to a remote that no longer exists in `.git/config`: the
  fetch fails, the arm degrades silently; it must not fall through to comparing
  against a stale local remote-tracking ref and reporting a fabricated count.
- Budget exhaustion mid-submodule-list: stop, print what was already found, exit 0.
  Never print a partial or "could not check" line — the intake's degradation
  decision is SILENT.
- `git` absent from PATH: `spawnSync` returns `error.code === 'ENOENT'`; treat it
  as the same silent no-op, not as an exception.

### Vacuity defence (mandatory, hybrid TDD lane)

Spec-AC-02, Spec-AC-05 and Spec-AC-06 are satisfied by printing nothing, so a
permanently-silent script passes them. RED-first is necessary but not sufficient
here. For each of TEST-021, TEST-024 and TEST-025 the implementation MUST record a
BITE PROOF in its return record: a temporary mutation applied to a COPY of the
script (never the tracked file — `.aai/SUBAGENT_CONTRACT.md` HAZ-RESTORE,
HAZ-SCRATCH) that makes the script unconditionally emit an `AAI-STALE:` line, and
the observation that the arm goes RED under that mutation. An arm that stays green
under a mutation that breaks the behaviour it claims to assert is not evidence and
must be rewritten before GREEN is claimed.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                        | Description                                                                                                                                        | Status  |
|----------|------------|-------------|---------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------|---------|
| TEST-020 | Spec-AC-01 | integration | tests/skills/test-aai-intake.sh             | Fixture A: scratch bare origin plus a clone, three commits pushed to origin behind the clone's back, run the script with `--repo <clone>` and assert exactly one `^AAI-STALE: branch` line naming the branch and the count 3, exit 0 | green   |
| TEST-021 | Spec-AC-02 | integration | tests/skills/test-aai-intake.sh             | Fixture B: clone level with origin, no submodules, assert stdout byte length 0 and exit 0 — carries the mandatory bite proof                          | green   |
| TEST-022 | Spec-AC-03 | integration | tests/skills/test-aai-intake.sh             | Fixture C: superproject level with origin, one initialized submodule pinned two commits behind its own remote, assert exactly one `^AAI-STALE: submodule` line naming the path and 2, and zero `^AAI-STALE: branch` lines | green   |
| TEST-023 | Spec-AC-04 | integration | tests/skills/test-aai-intake.sh             | Fixture E: on the Fixture A plus C tree, capture `git status --porcelain`, `git rev-parse HEAD`, `git for-each-ref refs/heads` and `git submodule status` before and after, assert all four byte-identical                | green   |
| TEST-024 | Spec-AC-05 | integration | tests/skills/test-aai-intake.sh             | Fixture D: origin rewritten to an unroutable URL, stdin closed, `--budget-ms 3000`, assert exit 0, stdout byte length 0, and elapsed wall clock under 5 s — carries the mandatory bite proof                            | green   |
| TEST-025 | Spec-AC-06 | integration | tests/skills/test-aai-intake.sh             | Fixture F: a fresh branch with no upstream, and separately a detached HEAD, each carrying a behind submodule; assert zero `^AAI-STALE: branch` lines and one `^AAI-STALE: submodule` line in both — carries the mandatory bite proof | green   |
| TEST-026 | Spec-AC-07, Spec-AC-08 | unit | tests/skills/test-aai-intake.sh             | static: exactly one `## STALENESS PREFLIGHT` heading in `.aai/INTAKE_COMMON.md`, its body names the script path, the verbatim relay and the proceed-regardless rule; all nine entry-point files name the preflight             | green   |
| TEST-027 | Spec-AC-08 | unit        | tests/skills/test-aai-intake.sh             | static ordering: in each of the eight per-type prompts the preflight line number is lower than that file's `BEGIN with` line, and in the router lower than `STEP 1 — DETECT TYPE`; both directions proven to bite on a mutated copy | green   |
| TEST-028 | Spec-AC-09 | unit        | tests/skills/test-aai-intake.sh             | `.aai/system/PROFILES.yaml` lists the new script exactly once across both lists and in `core:`, using the same awk extraction the layer-profiles suite uses                                                              | green   |
| TEST-029 | Spec-AC-10 | unit        | tests/skills/test-aai-prompt-diet.sh        | the existing TEST-010 floor and TEST-012 `want_growth` pin, re-run after the ledger entry and pin bump: net reduction at or above `REQUIRED_REDUCTION_BYTES`, headroom within `HEADROOM_CAP`, `want_growth` equal to the independent re-sum | green   |
| TEST-030 | Spec-AC-11 | unit        | tests/skills/test-aai-implementation-mode.sh | the existing TEST-002 wiring pin, re-run after the block count moves to six                                                                                                                                             | green   |
| TEST-031 | Spec-AC-09 | unit        | tests/skills/test-aai-intake.sh             | `node .aai/scripts/select-suites.mjs --files-from -` fed `.aai/scripts/intake-staleness-check.mjs` selects the `aai-intake` suite and does not escalate to FULL_RUN for that path alone                                   | green   |
Test status values: pending -> red -> green

Notes:
- Every Spec-AC has at least one TEST-xxx entry; TEST ids are stable after freeze.
- TEST-029 and TEST-030 are EXISTING suites re-run, not new cases: this scope's
  obligation there is to leave them green after moving the pins they own.
- TEST-020..TEST-025 are the TDD lane (RED artifact stored under `docs/ai/tdd/`,
  plus a bite proof for TEST-021, TEST-024, TEST-025). TEST-026..TEST-031 are the
  direct lane: observed failing once on the pre-change tree, reported in the return
  record, no stored artifact demanded.
- Every fixture is built under `mktemp -d` and removed on EXIT. No case may run a
  restoring git command on a tracked file or write the shipping repository
  (`.aai/SUBAGENT_CONTRACT.md` HAZ-RESTORE / HAZ-SCRATCH / HAZ-CD).
- Suites are bash-3.2 compatible and run through
  `bash .aai/scripts/aai-run-tests.sh` from the repository root.

## Verification

Commands to run:
- `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-intake.sh`
- `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-prompt-diet.sh`
- `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-implementation-mode.sh`
- `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-layer-profiles.sh`
- `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-suite-select.sh`
- `node .aai/scripts/docs-audit.mjs --check --strict --path docs/specs/SPEC-0158-spec-intake-staleness-preflight-warning.md`
- the full framework sweep once, before close.

Evidence artifacts: the per-suite stdout with exit codes; the stored RED artifacts
under `docs/ai/tdd/` for TEST-020..TEST-025; the three bite-proof observations in
the implementation return record; the measured before/after byte totals for the
diet ledger; the scoped diff.

PASS criteria: all TEST-xxx in status green AND all Spec-AC in a terminal status.

## Code review scope

Explicit paths:
- `.aai/scripts/intake-staleness-check.mjs`
- `.aai/INTAKE_COMMON.md`
- `.aai/SKILL_INTAKE.prompt.md`
- `.aai/INTAKE_CHANGE.prompt.md`, `.aai/INTAKE_HOTFIX.prompt.md`,
  `.aai/INTAKE_ISSUE.prompt.md`, `.aai/INTAKE_PRD.prompt.md`,
  `.aai/INTAKE_RELEASE.prompt.md`, `.aai/INTAKE_RESEARCH.prompt.md`,
  `.aai/INTAKE_RFC.prompt.md`, `.aai/INTAKE_TECHDEBT.prompt.md`
- `.aai/system/PROFILES.yaml`
- `tests/skills/test-aai-intake.sh`
- `tests/skills/test-aai-prompt-diet.sh`
- `tests/skills/lib/prompt-diet-ledger.sh`
- `tests/skills/test-aai-implementation-mode.sh`
- `tests/skills/suite-map.yaml`

Review must specifically check: that no code path can exit non-zero at runtime
(D6); that every degradation branch is silent and none prints a "could not check"
line; that the three bite proofs were actually performed and are recorded; and
that the diet-ledger byte figure was MEASURED, not estimated.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: intake-staleness-preflight-warning
- Spec-AC and TEST-xxx links
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available

### Evidence by strategy

| Strategy     | Evidence this spec may demand                                   |
|--------------|-----------------------------------------------------------------|
| tdd / hybrid | stored RED artifact per AC-gating test (docs/ai/tdd/) plus the full verification matrix — unchanged |
| loop         | per-TEST-xxx green runs; RED-proof observed, storage optional    |
| direct       | targeted regression tests green (exit codes) plus the scoped diff — NO stored RED artifact, NO matrix beyond the declared versions |
| untested     | the recorded strategy rationale plus the scoped diff — no test suites demanded for the scope itself |

This spec records `hybrid`. It therefore demands stored RED artifacts for
TEST-020..TEST-025 only, and demands none for TEST-026..TEST-031.

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
