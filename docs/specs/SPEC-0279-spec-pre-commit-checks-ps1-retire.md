---
id: spec-pre-commit-checks-ps1-retire
type: spec
number: 279
status: done
mutation_gate: v1
frozen_sha256: c494de8b0b3fc4ea0e6298d5caaa3916237d8a663fdb671994671487ced48f55
ceremony_level: 3
links:
  requirement: pre-commit-checks-ps1-retire
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Retire the uncalled PowerShell pre-commit checks and make the bash checks pipe-safe

SPEC-FROZEN: true

## Links

- Requirement: [Retire the uncalled PowerShell pre-commit checks and make the bash checks pipe-safe](../issues/CHANGE-0250-pre-commit-checks-ps1-retire.md).
- Parent: [RFC-0017](../rfc/RFC-0017-smaller-node-core-and-faster-feedback.md),
  phase 5, and the [remaining-scripts plan](../analysis/node-first-remaining-plan.md)
  ride 5 (owner sign-off: yes, on the plan, 2026-11-05).
- Pattern precedents: ride 2, [SPEC-0274](SPEC-0274-spec-retire-shell-loop-runner.md)
  (deprecation launcher kept one release, Pester under the engine running the
  test, a `fu-delete-*` follow-up), and ride 4,
  [SPEC-0278](SPEC-0278-spec-git-hook-bodies-single-source.md) (here-string fix
  of the early-closing reader class, `patch:` mutations for pipe shapes, the
  wiring list named up front, `vendor_hook_installer`).
- Technology contract: docs/TECHNOLOGY.md (bash, PowerShell 5.1 and 7,
  Pester 5, Node stdlib for the existing gates; nothing added).
- Baseline: main `3e6b52d5`.

## Implementation strategy

- Strategy: tdd
- Rationale: the owner asked for TDD in runs of about three Spec-ACs (rides 1
  to 4). Both touched scripts are L3 protected guards; the four large-input
  misfires were reproduced at planning (see Measurements) and must be seen
  failing before the fix, and the launcher, reference and wiring rows are RED
  on the baseline too. Every row carries a mutation.

## Isolation and review

- Worktree recommendation: required
- Worktree rationale: the scope edits two L3 protected surfaces
  (`.aai/scripts/pre-commit-checks.sh` and `.ps1`), so WORKFLOW.md gives the
  worktree gate REQUIRED semantics; the main checkout is shared and holds
  unrelated uncommitted files (docs/INDEX.md, docs/ai/EVENTS.jsonl,
  docs/ai/dashboard*, docs/ai/tests/test-runs.jsonl).
- User decision: worktree (owner decision 2026-11-07, recorded in STATE with
  rationale "owner decision 2026-11-07: own worktree for L3 ride"; not an
  autopilot default)
- Base ref: main
- Worktree branch/path: refactor/pre-commit-checks-ps1-retire at /Users/ales/Projects/aai-worktrees/pre-commit-checks-ps1-retire
- Inline review scope (a plain space-separated path list, as `set-code-review --scope` takes it):
  .aai/scripts/pre-commit-checks.ps1 .aai/scripts/pre-commit-checks.sh
  .aai/AGENTS.md .aai/scripts/lib/guard-config.mjs docs/TECHNOLOGY.md
  docs/ai/docs-audit.yaml
  tests/skills/test-aai-pre-commit-checks.sh tests/skills/pre-commit-checks-retired.Tests.ps1
  tests/skills/lib/pipe-grep-q-ratchet.sh tests/skills/test-aai-hygiene-pack.sh
  tests/skills/test-aai-doc-numbering.sh tests/skills/test-aai-tracked-ignored.sh
  tests/skills/test-aai-cloudflare-share.sh
  tests/skills/test-aai-suite-select.sh tests/skills/suite-map.yaml
  tests/skills/suite-weights.tsv tests/skills/lib/cd-subshell-leak-baseline.tsv
  docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md CHANGELOG.md
  docs/ai/decisions.jsonl
  docs/issues/CHANGE-0250-pre-commit-checks-ps1-retire.md
  docs/specs/SPEC-0279-spec-pre-commit-checks-ps1-retire.md docs/INDEX.md
  (cd-subshell-leak-baseline.tsv only if the ratchet asks for a row;
  guard-config.mjs and docs-audit.yaml are comment-only edits;
  decisions.jsonl only for the two follow-up records).
- Code review required: true, on the most capable tier (L3: mandatory; a
  waiver is flagged to the operator, never auto-accepted).

## Ceremony

- Level 3: the scope touches `.aai/scripts/pre-commit-checks.sh` and
  `.aai/scripts/pre-commit-checks.ps1`, both in `protected_paths_l3`
  (docs/ai/docs-audit.yaml and the WORKFLOW.md defaults).
- What L3 adds here, per the WORKFLOW.md table: the recorded worktree decision
  (done, owner's); full independent validation, never a delta re-check;
  mandatory code review on the most capable tier; an operator checkpoint
  before merge with an explicit final-diff sign-off. No other owner token is
  needed to edit the surfaces: `test-aai-hitl-propagation.sh` TEST-014
  accepts an L3 touch authorized by a frozen `ceremony_level: 3` spec in the
  same diff, which this spec is.
- Suite selection: `select-suites.mjs` answers `FULL_RUN reason=protected-l3`
  for both scripts, so Validation runs the full sweep
  (`AAI_TEST_TIMEOUT=3600`).

## Measurements behind the decisions

Measured on the planning tree (macOS arm64, bash 5, BSD `/usr/bin/grep`,
Node 22, pwsh 7, git) on 2026-11-07 at `3e6b52d5`. Windows PowerShell 5.1 was
not available to Planning.

### Lines (the plan's method, section 1)

Code lines are non-blank, non-comment lines (`grep -cvE '^[[:space:]]*(#|$)'`
under bash with `/usr/bin/grep`).

| File | Total | Code |
|---|---|---|
| .aai/scripts/pre-commit-checks.sh | 323 | 239 |
| .aai/scripts/pre-commit-checks.ps1 | 281 | 221 |
| test-aai-doc-numbering.sh test_809_check8_ps1_twin | 52 | 44 |
| test-aai-tracked-ignored.sh test_1708_precommit_ps1_parity | 9 | 9 |

The plan's row reads 239/221 (code lines); the RFC-0017 inventory row reads
323/281 (total lines). Both stay as measured history.

### Callers of the `.ps1` (tracked files; history, reviews, reports and test results excluded)

Runtime callers: none.

- Both installers write the AAI:GUARD-CHECKS block from
  `.aai/templates/git-hooks/pre-commit-guard-checks.sh`, which runs
  `bash "$_gc_root/.aai/scripts/pre-commit-checks.sh"`; git runs every hook
  under its own shell, on Windows under Git's bundled bash.
- `.aai/scripts/claude-hook-gate.sh` (commit route) runs
  `.aai/scripts/pre-commit-checks.sh`.
- `.aai/scripts/aai-doctor.mjs` names only the `.sh` (guard-caller check).
- No `.github/workflows/*.yml` and no `tests/skills/*.Tests.ps1` names it;
  `ps1-quality.yml` reaches it only through the `.aai/scripts/**.ps1` glob
  (parse check and PSScriptAnalyzer).
- No `.aai/*.prompt.md` and no `.claude/` skill names it.

Test callers (they run the `.ps1` as a parity twin):

- `tests/skills/test-aai-doc-numbering.sh` `test_809_check8_ps1_twin`
  (static read of the CHECK 8 block plus three pwsh runs).
- `tests/skills/test-aai-tracked-ignored.sh` `test_1708_precommit_ps1_parity`
  through `pc_run <repo> ps1`; `pc_fixture` copies the `.ps1`; line 11 of
  the header names CHECK 9 of `.sh/.ps1`.
- `tests/skills/test-aai-suite-select.sh` `test_1737` lists the `.ps1` among
  the commit-guard scripts (accepted as FULL_RUN).

Other live references:

- `.aai/AGENTS.md` line 262: "(`.aai/scripts/pre-commit-checks.sh` or `.ps1`)".
- `docs/TECHNOLOGY.md` line 214: "`.aai/scripts/pre-commit-checks.sh`/`.ps1`".
- `.aai/scripts/lib/guard-config.mjs` lines 35 and 149: comments naming
  `pre-commit-checks.{sh,ps1}` as grep mirrors.
- `docs/ai/docs-audit.yaml` line 15: comment naming the pre-commit host
  `pre-commit-checks.sh/.ps1`.
- `.aai/system/PROFILES.yaml` line 231 (`core:`), kept for the launcher.
- `tests/skills/suite-map.yaml` lines 313 and 1577 (rows `aai-doc-numbering`
  and `aai-tracked-ignored`).
- `docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md` line 325, the
  `pre-commit-checks` inventory row (`323/281`, `platform adapter kept on
  purpose`, pinned by `test-aai-expert-fetch.sh` TEST-2624).
- Protected-path lists, kept unchanged while the launcher exists:
  `.aai/workflow/WORKFLOW.md` line 75, `docs/ai/docs-audit.yaml` line 90,
  `.aai/templates/docs-audit.template.yaml` line 64.
- Hash pins over either script: none (searched `tests/skills` and
  `.aai/scripts` for sha256, shasum and hash next to the name).

### The early-closing pipe sites of `pre-commit-checks.sh`

Counted with `PGQ_PATTERN` of `tests/skills/lib/pipe-grep-q-ratchet.sh`
under bash with `/usr/bin/grep -nE`, comment lines dropped: 7 sites, which
are 6 pipes into `grep -q` or `grep -qE` and 1 pipe into `head -3`. The
follow-up's wording ("7 `echo $var | grep -q` pipes") is off by that one
`head` site.

| Line | Check | Shape |
|---|---|---|
| 42 | CHECK 1 implementation phase | echo STATE_DATA into grep -q |
| 48 | CHECK 1 validation pass | echo LAST_VALIDATION_BLOCK into grep -q |
| 105 | CHECK 3 debug lines shown | echo matches into head -3 into sed |
| 146 | CHECK 5 validation phase | echo STATE_DATA into grep -q |
| 147 | CHECK 5 validation pass | echo LAST_VALIDATION_BLOCK into grep -q |
| 168 | CHECK 6 review required | echo CODE_REVIEW_BLOCK into grep -q |
| 169 | CHECK 6 review pass or waived | echo CODE_REVIEW_BLOCK into grep -qE |

Pipes into readers that read to EOF (`awk`, `sed`, `grep -E` without a quiet
or max-count flag) are not this class and stay.

### Reproduction (scratch repositories, bash, 3 of 3 runs each)

- CHECK 1: STATE.yaml `current_focus:` / `  phase: implementation` / `notes:`
  followed by 6000 filler lines (384042 bytes): prints "No active
  implementation phase"; the two-line file prints the TDD warning.
- CHECK 5: the same file with `phase: validation` and no report directory:
  no "No validation report found" warning; the two-line file prints it.
- CHECK 6: `code_review:` / `  required: true` / `  status: pass` followed by
  6000 indented filler lines: no code review line at all; the three-line
  block prints "Code review gate satisfied".
- CHECK 3: a staged `app.js` of 20000 `console.log(...)` lines: the script
  exits 141 (`set -e` on the `head -3` pipeline), so checks 4 to 9 never run
  and a commit through the guard block is refused; a 5-line file exits 0.
- A scratch copy with the seven sites rewritten to here-strings decides all
  four large cases as their small twins and exits 0 on the large CHECK 3
  case (prototype only, outside the tree).
- This repository's own `docs/ai/STATE.yaml` is 111876 bytes.

### Prompt corpus

`.aai/AGENTS.md` loses " or `.ps1`" (about 11 bytes): no growth, and
AGENTS.md sits outside TEST-010's live `.aai/*.prompt.md` glob. The floor in
`test-aai-prompt-diet.sh` TEST-746 (AGENTS.md at least 22991 bytes; 23294
now) and the TEST-769 ceiling (24000) both hold. No ledger entry, no TEST-012
move, no companion pin move in `test-aai-pr-preflight.sh`,
`test-aai-legacy-migrations.sh` or `test-aai-retired-loop-runner.sh`. No
`.aai/*.prompt.md` changes; if implementation finds one that must, that is a
scope change (spec amendment), not a fold-in.

## Decisions

### D-LAUNCH. The `.ps1` launcher

`.aai/scripts/pre-commit-checks.ps1` becomes, in this order: one comment line
beginning `# RETIRED (RFC-0017 phase 5, pre-commit-checks-ps1-retire)` saying
it is a deprecation launcher for one release and the next release deletes it;
`[Console]::Error.WriteLine('<line>')`; `exit 1`. No param block, so
`-Strict` and any other argument land in `$args` and are ignored. ASCII only,
git mode 100644, at most 5 lines. The line:

`pre-commit-checks.ps1: retired - the PowerShell pre-commit checks are retired (RFC-0017 phase 5) and will be deleted in the next release; replacement: bash .aai/scripts/pre-commit-checks.sh (the installed hooks already run it); nothing was checked`

The file holds none of these words: `node`, `pwsh`, `git`, `param`,
`Write-Host`, `Write-Error`, `Invoke-`, `Start-Process`, `STATE`, `cp`,
`rm`, `mv`, `mkdir`. Exit 1 is deliberate: a downstream caller that wired
the `.ps1` into its own tooling must see a refusal naming the replacement,
not a silent pass of a secrets guard.

### D-PIPE. The seven sites

Each of the seven sites becomes a here-string: `grep -q <pattern> <<< "$VAR"`
(and `grep -qE`), and `head -3 <<< "$matches" | sed 's/^/    /'`. No other
line of `pre-commit-checks.sh` changes: `git diff --numstat 3e6b52d5 --
.aai/scripts/pre-commit-checks.sh` reads `7 7`. Every message, exit code and
check order stays.

### D-RATCHET. The shipping arm counts the file

`tests/skills/lib/pipe-grep-q-ratchet.sh` drops `PGQ_SHIPPING_DEFERRED_L3`,
its skip line in `pgq_scan_shipping` and the deferral comment; the comment
above `test_128_shipping_scripts_pipe_safe_at_zero` in
`tests/skills/test-aai-hygiene-pack.sh` says the ninth script was fixed by
this scope. `test_128` then gates `pre-commit-checks.sh` at zero like the
other shipping scripts.

### D-REF. Live references

- `.aai/AGENTS.md` line 262 reads
  ``Before committing, run quality gate checks (`.aai/scripts/pre-commit-checks.sh`):``.
- `docs/TECHNOLOGY.md` line 214 names only `.aai/scripts/pre-commit-checks.sh`
  and the installed hook.
- The two comments in `.aai/scripts/lib/guard-config.mjs` and the comment in
  `docs/ai/docs-audit.yaml` name only `pre-commit-checks.sh`.
- `test_809_check8_ps1_twin` (and its call in `main`) leaves
  `test-aai-doc-numbering.sh`; `test_1708_precommit_ps1_parity` (and its
  call), the `ps1` arm of `pc_run`, the `.ps1` copy in `pc_fixture` and the
  `.ps1` in the header comment leave `test-aai-tracked-ignored.sh`;
  `test_1737` in `test-aai-suite-select.sh` drops the `.ps1` from its list.
  The `.sh` cells TEST-806..808 and TEST-1706/1707 keep running unchanged.
- The protected-path lists (WORKFLOW.md, docs-audit.yaml,
  docs-audit.template.yaml) and PROFILES keep the `.ps1` while the launcher
  exists; the D-FU follow-up removes those entries with the file.

### D-WIRE. Wiring, named up front

- `tests/skills/suite-map.yaml`: new row `aai-pre-commit-checks` with globs
  `.aai/scripts/pre-commit-checks.*`, `tests/skills/test-aai-pre-commit-checks.sh`,
  `tests/skills/pre-commit-checks-retired.Tests.ps1`,
  `tests/skills/lib/pipe-grep-q-ratchet.sh`,
  `tests/skills/lib/vendor-hook-installer.sh`, `.aai/templates/git-hooks/**`,
  `.aai/system/PROFILES.yaml`. Rows `aai-doc-numbering` and
  `aai-tracked-ignored` drop `.aai/scripts/pre-commit-checks.ps1`. 129 rows
  become 130.
- `tests/skills/test-aai-hygiene-pack.sh` row-count pins in
  `test_090_suite_map_pin` and `test_129_mutation_gate_suite_registration`
  move from 129 to 130 (message names this suite).
- `tests/skills/suite-weights.tsv`: `aai-pre-commit-checks<TAB>196` (the
  documented unsampled maximum; TEST-3338 pins it) with a
  `# sample aai-pre-commit-checks fallback unsampled (...)` line.
- `tests/skills/lib/nested-suite-lint.mjs` (run by hygiene-pack `test_133`):
  every cross-suite call in the new suite is in selector form; no new
  allowlist row.
- `.aai/scripts/check-cd-subshell-leak.mjs`: a `cd` inside a substitution in
  the new suite needs a recorded row in
  `tests/skills/lib/cd-subshell-leak-baseline.tsv`; the `.sh` row (1) stays.
- `.aai/scripts/check-test-registration.mjs`: every `test_*` of the new suite
  is called, and the removed `test_809` and `test_1708` leave no call.
- `.github/workflows/ps1-quality.yml`: no edit; both path lists already hold
  `.aai/scripts/**.ps1` and `tests/skills/*.Tests.ps1`, and the hosted 5.1
  and pwsh 7 Pester steps discover the new file by directory.
  `test-aai-win-fallback.sh` `test_034` must stay green.
- `.aai/system/PROFILES.yaml`: no edit (the launcher stays one `core:` entry;
  no new `.aai/**` file).
- Prompt corpus: see Measurements (no ledger entry, no pin move).
- Hash pins: none exist over either script; none added.

### D-RFC. RFC-0017

- The `pre-commit-checks` inventory row keeps `323/281` and
  `platform adapter kept on purpose` (TEST-2624 pins the destination; the
  pair stays a pair while the launcher exists). Its reason cell becomes:
  `L3 protected surface; the .ps1 was retired by the [pre-commit-checks slice](../issues/CHANGE-0250-pre-commit-checks-ps1-retire.md), a deprecation launcher for one release naming pre-commit-checks.sh, deleted in the next; the .sh checks 1 to 7 run without Node`.
- Phase 5 row: one sentence after the eighth-slice sentence and before the
  remaining-scripts-plan sentence:
  `The ninth slice [retired the PowerShell pre-commit checks](../issues/CHANGE-0250-pre-commit-checks-ps1-retire.md): the uncalled .ps1 became a deprecation launcher for one release that names pre-commit-checks.sh, and the bash checks no longer pipe into an early-closing reader.`
  Status stays `in progress`; frontmatter untouched. The allocator rewrites
  the links at merge; checks match only the suffix
  `pre-commit-checks-ps1-retire.md`.
- After LOOP COMPLETE (ship convention, in the review scope, not a TEST row):
  CHANGELOG `## [unreleased] — refactor(guards): retire the uncalled PowerShell pre-commit checks; the bash checks stop misfiring on large input`
  naming the launcher line and its exit 1, the four misfires fixed, the
  before and after line counts, and that a caller of the `.ps1` must switch
  to `bash .aai/scripts/pre-commit-checks.sh`.

### D-FU. Follow-ups

- Filed during implementation: `fu-delete-retired-pre-commit-checks-ps1`
  (39 characters), ref `pre-commit-checks-ps1-retire`, severity P3, finding
  naming `pre-commit-checks.ps1`, `PROFILES.yaml`, `WORKFLOW.md`,
  `docs-audit.yaml` and `docs-audit.template.yaml` (the protected-path
  entries) and the RFC-0017 inventory row.
- Closed at ride close (after the last ledger-touching commit, before the
  final sweep): `fu-pre-commit-checks-pipe-grep-q`, resolved by
  `pre-commit-checks-ps1-retire`.

### D-SUITE

One new suite `aai-pre-commit-checks` (`tests/skills/test-aai-pre-commit-checks.sh`)
holds every row, with the `need_tool` helper of rides 3 and 4 (an absent tool
fails on CI, is a named SKIP-CASE locally). Every fixture is a fresh temp git
repository with a local identity; no case touches the checkout's own hooks or
STATE. The baseline script for parity cases is read with
`git show 3e6b52d5:.aai/scripts/pre-commit-checks.sh`. The Pester file
`tests/skills/pre-commit-checks-retired.Tests.ps1` launches the `.ps1` with
the engine running the test (`(Get-Process -Id $PID).Path`), so the hosted
5.1 step tests 5.1 and the pwsh 7 step tests pwsh 7.

## Acceptance Criteria Mapping

- Intake AC-001 maps to Spec-AC-01, Spec-AC-02, Spec-AC-03 and hosted check
  H1 (the native Windows Pester jobs under Windows PowerShell 5.1 and pwsh 7
  run `tests/skills/pre-commit-checks-retired.Tests.ps1`).
- Intake AC-002 maps to Spec-AC-04, Spec-AC-05, Spec-AC-06, Spec-AC-07 and
  Spec-AC-08.
- Intake AC-003 maps to Spec-AC-09, Spec-AC-10 and Spec-AC-13.
- Intake AC-004 maps to Spec-AC-11, Spec-AC-12, Spec-AC-13 and Spec-AC-14.

## Constitution deviations

None. Article 4 (degrade and report): the launcher refuses by name with the
replacement instead of passing silently. Article 5 (additive first): the
`.ps1` keeps its path, exit-code meaning (1 blocks) and PROFILES entry for
one release; the `.sh` keeps every message, exit code and flag. Article 2
(simplicity): no new flag, variable, dependency or runtime.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN .aai/scripts/pre-commit-checks.ps1 runs under pwsh from inside a committed git fixture with a staged file holding a secret-shaped line, once with no argument, once with -Strict and once with -Strict extra, the system SHALL print exactly the D-LAUNCH line on stderr, nothing on stdout, exit 1, and leave git status --porcelain and the staged index of the fixture unchanged. | done | docs/ai/tdd/pre-commit-checks-ps1-retire/green/test_3448_ps1_retired_run.log | — | mutation docs/ai/tdd/spec-pre-commit-checks-ps1-retire/mutation-TEST-3448.txt |
| Spec-AC-02 | tests/skills/pre-commit-checks-retired.Tests.ps1 passes under Pester 5 with at least 3 cases and none failed or skipped, each running the launcher with the engine running the test inside a TestDrive git fixture and asserting the D-LAUNCH line on stderr, exit 1 and an unchanged git status. | done | docs/ai/tdd/pre-commit-checks-ps1-retire/green/test_3449_pester.log | — | mutation docs/ai/tdd/spec-pre-commit-checks-ps1-retire/mutation-TEST-3449.txt |
| Spec-AC-03 | The launcher is at most 5 lines, ASCII only, git mode 100644, holds exactly one line beginning # RETIRED (RFC-0017 phase 5, pre-commit-checks-ps1-retire), the D-LAUNCH line text, exit 1 as its last line, no param block and none of the D-LAUNCH forbidden words as a word. | done | docs/ai/tdd/pre-commit-checks-ps1-retire/green/test_3450_launcher_thin.log | — | mutation docs/ai/tdd/spec-pre-commit-checks-ps1-retire/mutation-TEST-3450.txt |
| Spec-AC-04 | WHEN pre-commit-checks.sh runs under bash on a STATE.yaml holding phase implementation (or phase validation) on line 2 and at least 300000 bytes after it, the system SHALL print the TDD warning (or the No validation report found warning) exactly as on the two-line STATE.yaml; RED on the baseline. | done | docs/ai/tdd/pre-commit-checks-ps1-retire/green/test_3451_large_state_check1_check5.log | — | mutation docs/ai/tdd/spec-pre-commit-checks-ps1-retire/mutation-TEST-3451.txt |
| Spec-AC-05 | WHEN pre-commit-checks.sh runs under bash on a STATE.yaml whose code_review block holds required true and then at least 300000 bytes of indented lines, the system SHALL print Code review gate satisfied with status pass, and with status not_run SHALL print the review warning and, under --strict, exit 1; RED on the baseline. | done | docs/ai/tdd/pre-commit-checks-ps1-retire/green/test_3452_large_code_review_block.log | — | mutation docs/ai/tdd/spec-pre-commit-checks-ps1-retire/mutation-TEST-3452.txt |
| Spec-AC-06 | WHEN a staged app.js holds 20000 console.log lines, pre-commit-checks.sh SHALL exit 0, print the debug warning for app.js followed by exactly 3 indented match lines and reach the summary line; and WHEN git commit runs through a pre-commit hook installed by install-pre-commit-hook.sh in that fixture, the commit SHALL be created; RED on the baseline (exit 141, commit refused). | done | docs/ai/tdd/pre-commit-checks-ps1-retire/green/test_3453_large_debug_list.log | — | mutation docs/ai/tdd/spec-pre-commit-checks-ps1-retire/mutation-TEST-3453.txt |
| Spec-AC-07 | For seven small fixtures (CHECK 1 with and without a validation pass, CHECK 3 with 5 debug lines, CHECK 5 with and without a report, CHECK 6 pass and not_run), the delivered pre-commit-checks.sh SHALL produce stdout, stderr and exit code identical to the baseline script read with git show 3e6b52d5; and git diff --numstat 3e6b52d5 on the script reads 7 7. | done | docs/ai/tdd/pre-commit-checks-ps1-retire/green/test_3454_small_input_parity.log | — | mutation docs/ai/tdd/spec-pre-commit-checks-ps1-retire/mutation-TEST-3454.txt |
| Spec-AC-08 | PGQ_PATTERN of tests/skills/lib/pipe-grep-q-ratchet.sh matches 0 non-comment lines of pre-commit-checks.sh (positive control: 7 in the baseline script read with git show 3e6b52d5); the lib no longer holds PGQ_SHIPPING_DEFERRED_L3; pgq_scan_shipping over the tree totals 0 and test-aai-hygiene-pack.sh test_128_shipping_scripts_pipe_safe_at_zero exits 0. | done | docs/ai/tdd/pre-commit-checks-ps1-retire/green/test_3455_ratchet_counts_the_file.log | — | mutation docs/ai/tdd/spec-pre-commit-checks-ps1-retire/mutation-TEST-3455.txt |
| Spec-AC-09 | Over tracked files outside docs/ and tests/ except CHANGELOG.md, plus docs/TECHNOLOGY.md and docs/ai/docs-audit.yaml, every line naming pre-commit-checks.ps1 or a sh-and-ps1 form of the name (braces, slash or or) is in the launcher, PROFILES.yaml, the WORKFLOW.md protected-surface line, a protected_paths_l3 entry of docs-audit.yaml or docs-audit.template.yaml; AGENTS.md holds the D-REF line. | done | docs/ai/tdd/pre-commit-checks-ps1-retire/green/test_3456_no_live_ps1_reference.log | — | mutation docs/ai/tdd/spec-pre-commit-checks-ps1-retire/mutation-TEST-3456.txt |
| Spec-AC-10 | No tests/skills file other than test-aai-pre-commit-checks.sh and pre-commit-checks-retired.Tests.ps1 names pre-commit-checks.ps1; test_809_check8_ps1_twin and test_1708_precommit_ps1_parity no longer exist; check-test-registration.mjs is clean; test-aai-doc-numbering.sh, test-aai-tracked-ignored.sh and test-aai-suite-select.sh exit 0. | done | docs/ai/tdd/pre-commit-checks-ps1-retire/green/test_3457_suites_stop_running_the_ps1.log | — | mutation docs/ai/tdd/spec-pre-commit-checks-ps1-retire/mutation-TEST-3457.txt |
| Spec-AC-11 | Wiring per D-WIRE: select-suites selects aai-pre-commit-checks for the new suite, the Pester file and the ratchet lib, and answers FULL_RUN protected-l3 for both scripts; the aai-doc-numbering and aai-tracked-ignored rows no longer glob the ps1; suite-weights holds the row; both hygiene-pack pins read 130 and their selectors pass; nested-suite lint, check-cd-subshell-leak and check-test-registration exit 0; both ps1-quality path lists keep both globs and win-fallback test_034 passes; test-aai-prompt-diet.sh exits 0. | done | docs/ai/tdd/pre-commit-checks-ps1-retire/green/test_3458_wiring.log | — | mutation docs/ai/tdd/spec-pre-commit-checks-ps1-retire/mutation-TEST-3458.txt |
| Spec-AC-12 | WHEN aai-sync.sh --profile core installs into a scratch git target whose path holds a space, the target SHALL hold the launcher and pre-commit-checks.sh byte-identical to the source; the target's launcher under pwsh SHALL print the D-LAUNCH line and exit 1, and PGQ_PATTERN SHALL match 0 non-comment lines of the target's pre-commit-checks.sh. | done | docs/ai/tdd/pre-commit-checks-ps1-retire/green/test_3459_downstream_install.log | — | mutation docs/ai/tdd/spec-pre-commit-checks-ps1-retire/mutation-TEST-3459.txt |
| Spec-AC-13 | test-aai-expert-fetch.sh test_2624_inventory_matches_tree exits 0; the pre-commit-checks row keeps 323/281 and platform adapter kept on purpose and holds the D-RFC reason with a link ending pre-commit-checks-ps1-retire.md; the phase 5 row holds the D-RFC sentence exactly once and keeps status in progress. | done | docs/ai/tdd/pre-commit-checks-ps1-retire/green/test_3460_rfc.log | — | mutation docs/ai/tdd/spec-pre-commit-checks-ps1-retire/mutation-TEST-3460.txt |
| Spec-AC-14 | Measured with the plan's method on the delivered tree, the launcher has at most 2 code lines and 5 lines, pre-commit-checks.sh keeps 323 lines and 239 code lines, and the suite prints the before and after counts; follow-ups.mjs list --json holds one open item fu-delete-retired-pre-commit-checks-ps1 with ref pre-commit-checks-ps1-retire, severity P3 and a finding naming pre-commit-checks.ps1, PROFILES.yaml, WORKFLOW.md and docs-audit.yaml. | done | docs/ai/tdd/pre-commit-checks-ps1-retire/green/test_3461_line_budget_and_follow_up.log | — | mutation docs/ai/tdd/spec-pre-commit-checks-ps1-retire/mutation-TEST-3461.txt |

## Implementation plan

TDD in five runs of about three Spec-ACs; each run stores RED under
`docs/ai/tdd/pre-commit-checks-ps1-retire/red/` before its change, GREEN
under `green/`, and one mutation record per row
(`node .aai/scripts/mutation-run.mjs`) before the run's hand-off.

1. Run 1, Spec-AC-04, 05, 06: the suite skeleton, the large-input fixtures
   (the Measurements reproduction), D-PIPE.
2. Run 2, Spec-AC-07, 08: the small-input parity against the baseline,
   D-RATCHET (lib and the hygiene-pack comment).
3. Run 3, Spec-AC-01, 02, 03: D-LAUNCH, the Pester file.
4. Run 4, Spec-AC-09, 10, 11: D-REF (AGENTS, TECHNOLOGY, comments, the three
   suites), D-WIRE.
5. Run 5, Spec-AC-12, 13, 14: the scratch install, D-RFC, the measurement,
   the D-FU delete item; then the CHANGELOG entry after LOOP COMPLETE and the
   close of `fu-pre-commit-checks-pipe-grep-q` at ride close.

Edge cases the runs must keep: `--strict` as the only argument still blocks
on a warning; CHECK 1 with a validation pass still passes; CHECK 7 (pwsh
parse gate on staged `.ps1` files) still parse-checks the launcher when it is
staged; an empty STATE_DATA, LAST_VALIDATION_BLOCK or CODE_REVIEW_BLOCK still
decides as before (a here-string of an empty string is one newline, as echo
was).

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3448 | Spec-AC-01 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_3448_ps1_retired_run (need_tool pwsh) builds a committed git fixture with local identity, stages a file with an api_key line of 12 characters, snapshots git status --porcelain and git diff --cached --name-only, runs pwsh -NoProfile -File on the ps1 with no argument, with -Strict and with -Strict extra: each stderr equals the D-LAUNCH line, stdout empty, exit 1, both snapshots unchanged; RED on the baseline (stdout holds the banner) | `sed:s/exit 1/exit 0/` on .aai/scripts/pre-commit-checks.ps1 | green |
| TEST-3449 | Spec-AC-02 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_3449_pester (need_tool pwsh; SKIP-CASE without Pester 5 locally, as SPEC-0274 TEST-3405) runs Invoke-Pester on tests/skills/pre-commit-checks-retired.Tests.ps1 with PassThru and fails on FailedCount above 0, SkippedCount above 0 or TotalCount below 3; the cases run the launcher with the engine running the test in a TestDrive git fixture with local identity and core.autocrlf false: no argument, -Strict, a staged secret-shaped file | `sed:s/nothing was checked/nothing checked/` on .aai/scripts/pre-commit-checks.ps1 | green |
| TEST-3450 | Spec-AC-03 | inspection | tests/skills/test-aai-pre-commit-checks.sh | test_3450_launcher_thin requires the ps1 at most 5 lines, no byte above 0x7E, git ls-files -s mode 100644, exactly one line beginning # RETIRED (RFC-0017 phase 5, pre-commit-checks-ps1-retire), the D-LAUNCH line text, last line exit 1, no param( and none of the D-LAUNCH forbidden words as a word; positive control: a scratch copy holding Write-Host is reported | `sed:s/exit 1/Write-Host done; exit 1/` on .aai/scripts/pre-commit-checks.ps1 | green |
| TEST-3451 | Spec-AC-04 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_3451_large_state_check1_check5 writes the Measurements STATE.yaml (6000 filler lines, at least 300000 bytes) with phase implementation and then phase validation into fresh fixtures and runs the script with bash: the TDD warning line, then the No validation report found line, each present once, as on the two-line twins; RED on the baseline (both absent) | `patch:docs/ai/tdd/spec-pre-commit-checks-ps1-retire/mutation-TEST-3451.patch` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-3452 | Spec-AC-05 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_3452_large_code_review_block writes a code_review block with required true, then status pass, then 6000 indented filler lines: Code review gate satisfied present; with status not_run: the review warning present and --strict exits 1; RED on the baseline (no review line, --strict exits 0 when no other warning) | `patch:docs/ai/tdd/spec-pre-commit-checks-ps1-retire/mutation-TEST-3452.patch` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-3453 | Spec-AC-06 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_3453_large_debug_list stages app.js of 20000 console.log lines and runs the script: exit 0, the Debug statements in app.js line, exactly 3 following lines starting with four spaces, the summary line present; then vendors the sh installer with vendor_hook_installer, installs the pre-commit hook and runs git commit -m x: exit 0 and HEAD moved; RED on the baseline (exit 141, commit refused) | `patch:docs/ai/tdd/spec-pre-commit-checks-ps1-retire/mutation-TEST-3453.patch` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-3454 | Spec-AC-07 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_3454_small_input_parity builds the seven small fixtures of Spec-AC-07, runs the delivered script and the baseline read with git show 3e6b52d5 in the same fixture, and cmp-compares stdout, stderr and exit code per fixture; requires git diff --numstat 3e6b52d5 on the script to read 7 7 | `sed:s/warn "Code review required but not pass\/waived"/warn "Code review required"/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-3455 | Spec-AC-08 | inspection | tests/skills/test-aai-pre-commit-checks.sh | test_3455_ratchet_counts_the_file sources the ratchet lib, counts PGQ_PATTERN matches in non-comment lines of the script with /usr/bin/grep -cE (want 0) and of git show 3e6b52d5 (want 7), requires no PGQ_SHIPPING_DEFERRED_L3 in the lib, pgq_scan_shipping total 0, and runs test-aai-hygiene-pack.sh test_128_shipping_scripts_pipe_safe_at_zero (exit 0) | `patch:docs/ai/tdd/spec-pre-commit-checks-ps1-retire/mutation-TEST-3455.patch` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-3456 | Spec-AC-09 | inspection | tests/skills/test-aai-pre-commit-checks.sh | test_3456_no_live_ps1_reference greps git ls-files of the Spec-AC-09 corpus for pre-commit-checks.ps1 and the three sh-and-ps1 spellings and requires every hit in the allowlist (by path, and for WORKFLOW.md and the two docs-audit files by line shape); requires the D-REF AGENTS.md line; positive control: a scratch copy of TECHNOLOGY.md with the old line is reported | `patch:docs/ai/tdd/spec-pre-commit-checks-ps1-retire/mutation-TEST-3456.patch` on .aai/AGENTS.md | green |
| TEST-3457 | Spec-AC-10 | inspection | tests/skills/test-aai-pre-commit-checks.sh | test_3457_suites_stop_running_the_ps1 greps tests/skills for pre-commit-checks.ps1 outside the two allowed files (want none), requires no test_809_check8_ps1_twin and no test_1708_precommit_ps1_parity definition, runs check-test-registration.mjs (exit 0) and the selectors test_808_check8_enforce_is_merge_point_aware of test-aai-doc-numbering.sh (that suite has no test_806 or test_807 function), test_1706_precommit_sh_refuses_added_ignored_path and test_1707_precommit_sh_cells of test-aai-tracked-ignored.sh and test_1737_real_map_gitignore_full_and_guard_scripts_select of test-aai-suite-select.sh (exit 0) | `sed:s/cp "\$SCRIPTS_DIR\/pre-commit-checks.sh" /cp "$SCRIPTS_DIR\/pre-commit-checks.sh" "$SCRIPTS_DIR\/pre-commit-checks.ps1" /` on tests/skills/test-aai-tracked-ignored.sh | green |
| TEST-3458 | Spec-AC-11 | inspection | tests/skills/test-aai-pre-commit-checks.sh | test_3458_wiring feeds the suite, the Pester file and the ratchet lib to node .aai/scripts/select-suites.mjs --files-from and requires aai-pre-commit-checks, feeds each script and requires FULL_RUN reason=protected-l3; requires the two rows without the ps1 glob and the suite-weights row; runs test-aai-hygiene-pack.sh test_090_suite_map_pin, test_129_mutation_gate_suite_registration and test_133, check-cd-subshell-leak, check-test-registration, test-aai-win-fallback.sh test_034 and the test-aai-prompt-diet.sh selectors test_010_audit_and_reduction, test_012_growth_sum_matches_ledger, test_746_roadmap_takes_direction_growth_ledgered and test_769_agents_md_ceiling (each exit 0; nested-suite-lint refuses a whole-suite nested run, so Validation runs the whole suite); requires both ps1-quality globs in both path lists | `sed:s/      - tests\/skills\/pre-commit-checks-retired\.Tests\.ps1/      - tests\/skills\/gone.Tests.ps1/` on tests/skills/suite-map.yaml | green |
| TEST-3459 | Spec-AC-12 | e2e | tests/skills/test-aai-pre-commit-checks.sh | test_3459_downstream_install runs aai-sync.sh --profile core into a scratch git target named with a space, cmp-compares the target's launcher and pre-commit-checks.sh with the source, runs the target's launcher with pwsh from inside the target (need_tool pwsh): the D-LAUNCH line, exit 1; counts PGQ_PATTERN in the target's script (want 0) | `sed:s/  - \.aai\/scripts\/pre-commit-checks\.ps1/  - .aai\/scripts\/pre-commit-checks-gone.ps1/` on .aai/system/PROFILES.yaml | green |
| TEST-3460 | Spec-AC-13 | inspection | tests/skills/test-aai-pre-commit-checks.sh | test_3460_rfc runs test-aai-expert-fetch.sh test_2624_inventory_matches_tree (exit 0), requires the pre-commit-checks row to keep 323/281 and platform adapter kept on purpose and to hold the D-RFC reason with a link ending pre-commit-checks-ps1-retire.md, and the phase 5 row to hold the D-RFC sentence exactly once with status in progress | `sed:s/The ninth slice \[retired the PowerShell pre-commit checks\]/The ninth slice [retired the checks]/` on docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md | green |
| TEST-3461 | Spec-AC-14 | inspection | tests/skills/test-aai-pre-commit-checks.sh | test_3461_line_budget_and_follow_up counts lines with wc -l and code lines with grep -cvE on the hash-comment and blank pattern under bash with /usr/bin/grep: launcher at most 5 and 2, script 323 and 239; prints before (323/239 and 281/221) and after; runs follow-ups.mjs list --status open --json and requires exactly one fu-delete-retired-pre-commit-checks-ps1 with ref pre-commit-checks-ps1-retire, severity P3 and a finding naming pre-commit-checks.ps1, PROFILES.yaml, WORKFLOW.md and docs-audit.yaml | `sed:s/fu-delete-retired-pre-commit-checks-ps1/fu-delete-retired-pre-commit-gone-ps1/` on docs/ai/decisions.jsonl | green |

Test counts by type: inspection 7, integration 7, e2e 1 (14 rows; the
Pester file adds at least 3 cases inside TEST-3449).

The mutation strings name the expected implementation shapes; TDD may pick
different spellings and then re-points the mutation at the same behaviour
before the row turns green, recording it in the mutation record. The `patch:`
mutations are written at GREEN (a pipe character cannot sit in this table):
TEST-3451's turns the line-42 here-string back into a pipe from echo into
`grep -q`; TEST-3452's does the same at line 168; TEST-3453's turns the
`head -3` here-string back into a pipe from echo; TEST-3455's adds one pipe
from echo into `grep -q` on a new line; TEST-3456's restores " or `.ps1`" on
AGENTS.md line 262.

Seams crossed (Principle 2): the installed pre-commit hook (template written
by the real installer) and the script it runs under git's bash on a payload
large enough to outrun the reader (TEST-3453); STATE.yaml as written by
other tools and the script's awk and grep readers (TEST-3451, TEST-3452); the
delivered script against its own baseline on the same fixtures (TEST-3454);
the ratchet lib read by hygiene-pack `test_128` (TEST-3455); the launcher
under every engine that can run it (TEST-3448, TEST-3449; Windows PowerShell
5.1 and pwsh 7 on native Windows in H1); aai-sync's core profile copy and the
target's own launcher and script (TEST-3459); select-suites, the hygiene
pins, the nested-suite lint, the cd ratchet and the registration check
reading the new suite (TEST-3458); the RFC inventory read by `test_2624`
(TEST-3460); the follow-up ledger read by `follow-ups.mjs` (TEST-3461).

## Verification

- `env -u AAI_ROLE -u AAI_GIT_WRITE bash tests/skills/test-aai-pre-commit-checks.sh`
  exits 0 (14 rows), plus the touched suites, each with
  `env -u AAI_ROLE -u AAI_GIT_WRITE`: test-aai-hygiene-pack.sh,
  test-aai-doc-numbering.sh, test-aai-tracked-ignored.sh,
  test-aai-suite-select.sh, test-aai-expert-fetch.sh, test-aai-prompt-diet.sh,
  test-aai-hitl-propagation.sh (TEST-014 authorized by this spec),
  test-aai-win-fallback.sh, test-ps1-quality.sh.
- Full sweep: `select-suites.mjs` answers FULL_RUN (protected-l3), so
  Validation runs one full sweep with `AAI_TEST_TIMEOUT=3600` before close
  (intermediate rounds may run the selected suites plus CORE).
- Unchanged surfaces, recorded in the validation report:
  `git diff --stat 3e6b52d5 -- .aai/workflow/WORKFLOW.md .aai/templates/ .aai/scripts/claude-hook-gate.sh .aai/scripts/install-pre-commit-hook.sh .aai/scripts/install-pre-commit-hook.ps1 .aai/system/PROFILES.yaml .github/`
  prints nothing, and no `.aai/*.prompt.md` differs from `3e6b52d5`.
- `node .aai/scripts/spec-lint.mjs --path <this spec>` and
  `node .aai/scripts/mutation-gate.mjs --spec <this spec>` pass.
- H1 (hosted): the ps1-quality Windows jobs pass under Windows PowerShell 5.1
  and pwsh 7 with `pre-commit-checks-retired.Tests.ps1` discovered and not
  skipped, and the parse step passes on the launcher.

## Evidence contract

ref_id `pre-commit-checks-ps1-retire`; RED, GREEN and mutation evidence
under `docs/ai/tdd/pre-commit-checks-ps1-retire/` (gitignored); each AC
row's Evidence names its green log and mutation record; the validation
report and review verdict under `docs/ai/reports/` and `docs/ai/reviews/`.

### Evidence by strategy

tdd: a stored RED artifact per AC-gating test plus the verification matrix
above.

## Residual risks

- Windows PowerShell 5.1 behaviour of the launcher is proven only on the
  hosted job (H1); Planning had no Windows engine.
- A downstream project that calls the `.ps1` from its own tooling now gets
  exit 1 instead of the old checks; this is the intended loud failure, and
  the CHANGELOG names the replacement. Nothing in this repository can see
  such a caller.
- The large-input fixtures depend on the pipe buffer being smaller than the
  payload (at least 300000 bytes against a 64 KB buffer on the measured
  host); a host with a larger buffer would make the RED weaker, never the
  GREEN. The CHECK 3 case exits 141 locally; a runner that ignores SIGPIPE
  gets EPIPE and a non-zero echo instead, which still fails the baseline.
- The `.ps1` stays listed as a protected path, in PROFILES and in the RFC
  inventory until the D-FU delete follow-up runs; `test-aai-hitl-propagation.sh`
  TEST-014 reads the first 8 protected entries (`qhead -8`), so the delete
  ride must check that window when it removes the entry.
- The umbrella RFC-0017 stays open across this child-phase delivery; the
  close may trip the docs-audit false-open on the parent, suppressed with a
  fresh doc_lifecycle event as in earlier slices.

Registry items closed by this scope: `fu-pre-commit-checks-pipe-grep-q`

The pipe-grep item is closed at ride close (D-FU). The other open registry
items near these files (the PowerShell installer items and the allocator
realpath item) concern the installers and the allocator, which this scope
does not change.

## Amendments

### Amendment 1 (implementation, 2026-11-07): follow-through the frozen text did not name

No decision, Spec-AC or mutation changes; two Test Plan rows (TEST-3457, TEST-3458) name the selectors that exist. No owner sign-off was obtained (autonomous default).

- TEST-3457: `test-aai-doc-numbering.sh` has no `test_806` or `test_807` function; the row runs `test_808_check8_enforce_is_merge_point_aware`, and the two tracked-ignored selectors and the suite-select selector by their full names.
- TEST-3458: `nested-suite-lint.mjs` refuses a whole-suite nested run (test-aai-hygiene-pack.sh `test_133`), so the prompt-diet arm runs four selectors (`test_010`, `test_012`, `test_746`, `test_769`); the whole `aai-prompt-diet` suite is run by Validation and by this scope's selected-suite round.
- `test-aai-tracked-ignored.sh` `test_1736_precommit_broken_script_is_not_a_pass` looped over the sh and ps1 flavors through `pc_run`; with the `ps1` arm of `pc_run` gone it loops over sh only (the ps1 arm of this negation control ran the retired checks).
- `test-aai-cloudflare-share.sh` `test_3428_wiring` pins the suite-map row count at 129; it moves to 130, as the Measurements ask for the other pins.
- `tests/skills/lib/cd-subshell-leak-baseline.tsv` gains `3 tests/skills/test-aai-pre-commit-checks.sh` (the three `cd` inside a substitution of the suite preamble that every suite carries).
- The suite and the Pester file assemble the secret-shaped fixture line from two parts (`api` and `_key`), because a literal `api_key = '...'` in a staged test file is itself a CHECK 2 refusal of the commit that adds it.
- `docs/INDEX.md` is regenerated by the pre-commit hook at each commit (review scope already lists it).

