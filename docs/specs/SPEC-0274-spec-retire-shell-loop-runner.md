---
id: spec-retire-shell-loop-runner
type: spec
number: 274
status: done
frozen_sha256: 34e845b95c1aaad76871c9182202b4656d1eef4e226e2b11915de0e17d1fe032
mutation_gate: v1
ceremony_level: 2
links:
  requirement: retire-shell-loop-runner
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Retire the shell autonomous loop runner in favour of /aai-loop

SPEC-FROZEN: true

## Links

- Requirement: [Retire the shell autonomous loop runner in favour of /aai-loop](../issues/CHANGE-0246-retire-shell-loop-runner.md).
- Parent: [RFC-0017](../rfc/RFC-0017-smaller-node-core-and-faster-feedback.md),
  phase 5, and the [remaining-scripts plan](../analysis/node-first-remaining-plan.md)
  ride 2 with its owner decision of 2026-11-05 (section 4, item 2).
- Pattern precedent: [SPEC-0273](SPEC-0273-spec-retire-legacy-migrations.md)
  (ride 1, PR #533): D3 retirement launchers, D-INV inventory handling, D-DIET
  ledger reclaim, the scratch `aai-sync` install proving the target's launchers.
- Replacement: `/aai-loop` (`.aai/SKILL_LOOP.prompt.md`); unattended rides go
  through `/aai-ship` (`.aai/SKILL_SHIP.prompt.md`, `unattended=true`).
- Technology contract: docs/TECHNOLOGY.md.
- Baseline: main `8293605d`.

## Implementation strategy

- Strategy: tdd
- Rationale: the owner asked for TDD in runs of about three Spec-ACs (ride 1
  precedent). The two launchers are behavior on a consumer-visible core path;
  the documentation, pin, wiring and ledger rows are pinned by inspection tests
  that are RED on the baseline. Every row goes RED first and carries a mutation
  record.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound change to two shipped core-profile scripts, a
  shipped prompt (SKILL_LOOP), AGENTS.md, the prompt-diet ledger, an umbrella
  RFC and existing suites; the main checkout is shared and holds unrelated
  uncommitted files.
- User decision: worktree (autopilot default, recorded via state.mjs
  set-worktree)
- Base ref: main
- Worktree branch/path: refactor/retire-shell-loop-runner at /Users/ales/Projects/aai-worktrees/retire-shell-loop-runner
- Inline review scope (a plain space-separated path list, as `set-code-review --scope` takes it):
  .aai/scripts/autonomous-loop.sh .aai/scripts/autonomous-loop.ps1
  .aai/AGENTS.md .aai/SKILL_LOOP.prompt.md .aai/BOOTSTRAP_DIFF.prompt.md
  .aai/system/AUTONOMOUS_LOOP.md .aai/scripts/generate-overview.mjs
  docs/USER_GUIDE.md README.md docs/TECHNOLOGY.md
  tests/skills/test-aai-check-state.sh tests/skills/test-aai-retired-loop-runner.sh
  tests/skills/retired-loop-runner.Tests.ps1 tests/skills/suite-map.yaml
  tests/skills/suite-weights.tsv tests/skills/lib/prompt-diet-ledger.sh
  tests/skills/test-aai-prompt-diet.sh
  docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md
  docs/ai/decisions.jsonl CHANGELOG.md
  docs/issues/CHANGE-0246-retire-shell-loop-runner.md
  docs/specs/SPEC-0274-spec-retire-shell-loop-runner.md docs/INDEX.md
  (suite-weights.tsv only if the selector asks for a row).
- Code review required: true.

## Measurements behind the decisions

Measured on the planning tree (macOS arm64, bash 5, `/bin/sh`, dash, Node 22,
pwsh 7, git 2.54) on 2026-11-06 at `8293605d`. Windows PowerShell 5.1 was not
available to Planning.

### Lines (the plan's method, section 1)

Code lines are non-blank, non-comment lines
(`grep -cvE '^[[:space:]]*(#|$)'` under bash with `/usr/bin/grep`).

| Script | Total lines | Code lines | Git mode |
|---|---|---|---|
| autonomous-loop.sh | 488 | 409 | 100644 |
| autonomous-loop.ps1 | 464 | 384 | 100644 |

Before: 952 total lines, 793 code lines over the two files.

### Callers and references (tracked files; docs history, CHANGELOG history and test results excluded)

Live, edited by this scope:

- `.aai/AGENTS.md` line 142 `- Use SKILL_LOOP instead of autonomous-loop.sh when running inside a capable agent session.`
  and line 220 `- Loop runners are skill-first by default and enforce this sequence unless explicitly switched to legacy mode.`
  (the second describes the runner's `--mode skill|legacy`). Line 88 (`# Full
  autonomous multi-tick loop (replaces shell loop runner)`) stays: it names no
  file and is true.
- `.aai/SKILL_LOOP.prompt.md` line 4 names both files as what the skill replaces.
- `.aai/BOOTSTRAP_DIFF.prompt.md` line 7 lists `.aai/scripts/autonomous-loop.(sh|ps1)`
  among the canonical files to compare.
- `.aai/system/AUTONOMOUS_LOOP.md` section 8 says the runners provide the
  unattended guarantees (`--propose-only` / `-ProposeOnly`, recovery, digest).
- `.aai/scripts/generate-overview.mjs` line 208: a comment naming the runners as
  legacy tick producers; the normalisation it explains stays (old ledgers keep
  those rows).
- `docs/USER_GUIDE.md` lines 2224 to 2269: section `### Shell loop runners
  (autonomous-loop.sh / .ps1)` with bash and PowerShell invocation examples.
- `README.md` line 218 (`LOOP_TICKS.jsonl` "written by the loop runner
  scripts"; it is written by `state.mjs log-tick` under `/aai-loop`) and line
  239 ("loop runner reference").
- `docs/TECHNOLOGY.md` line 47 (`POSIX shell / bash — installers, loop
  runners, hooks, and test suites`).
- `.aai/system/PROFILES.yaml` lines 107 and 108: both files under `core:`.
  Kept: the launchers ship this release.

Test pins:

- `tests/skills/test-aai-check-state.sh` `test_single_state_creator` greps the
  `.sh` runner for `check-state.mjs --repair` (delegation) and for an inline
  heredoc creator. Rewritten (D-PIN): the launchers create no STATE at all.
- `tests/skills/test-aai-live-status.sh` TEST-016 lists the `.sh` runner among
  files that must not name `generate-live-status`; it skips a missing file.
  Benign, unchanged.
- `tests/skills/test-aai-expert-fetch.sh` TEST-2624 (`inventory_check`) pins the
  RFC-0017 inventory destination of `autonomous-loop` to `phase 5 process
  adapter`. Unchanged (D-INV).
- `tests/skills/test-aai-hygiene-pack.sh` line 1797: a comment recording which
  scripts round 10 rewrote. Historical, unchanged.

Not wired: no suite-map row, no ps1-quality path entry (its
`.aai/scripts/**.ps1` glob already covers the `.ps1`), no cd-subshell-leak
baseline row, no PSScriptAnalyzer exception names the runner.

Added at implementation (additive, contract amendment): the sentence above is
true of the two launchers and false of the new suite. Its `file_listing` helper
holds three `cd` inside a substitution, so
`tests/skills/lib/cd-subshell-leak-baseline.tsv` gains the row
`3 tests/skills/test-aai-retired-loop-runner.sh` (UNSAFE 0, recorded with
`check-cd-subshell-leak.mjs --record`), and `tests/skills/test-aai-hygiene-pack.sh`
moves its suite-map row-count pins from 126 to 127. The nested-suite lint
(allowlist pinned at 5 rows) refuses a suite that runs another whole suite, so
TEST-3409 runs `test_single_state_creator` of `test-aai-check-state.sh` by
sourcing it and TEST-3411 runs `test_manifest_conformance` of
`test-aai-layer-profiles.sh`; both whole suites stay in the Verification list
and `aai-check-state` is core.
TEST-3410 likewise sources only `test_010_audit_and_reduction` and
`test_012_growth_sum_matches_ledger` of `test-aai-prompt-diet.sh` (the whole
suite stays in Verification). The TEST-012 pin move 64288 to 64221 also moves
two companion pins that the original scope did not name:
`tests/skills/test-aai-pr-preflight.sh` (TEST-008 expected sum gains the -67
entry) and `tests/skills/test-aai-legacy-migrations.sh` (TEST-3398 derives its
pin from the ledger entries after its own). TEST-3410 derives its pin the same
way, and `tests/skills/suite-map.yaml` maps the prompt-diet ledger and suite to
the four suites that pin its sum.

Downstream and shipped invocation sweep: no shipped hook (`hooks/*`,
`.aai/templates/hooks/*`), launcher, routine (`.aai/routines/SCRYER.routine.md`),
`aai-sync`, `aai-update`, `aai-bootstrap`, `aai-doctor`, harness skill wrapper
or settings file invokes `autonomous-loop`. Downstream receives the two files
only through the PROFILES `core:` list that `aai-sync` copies; a downstream
user's own cron job or script that calls them is the consumer-visible effect.

Kept, not a caller: `.aai/scripts/loop-digest.mjs` (PROFILES `core:`). The
runner called it at the end of a run, but `/aai-loop` reads
`node .aai/scripts/loop-digest.mjs --json` every tick (SKILL_LOOP step 2) and
`/aai-profile --last-run` uses it. It stays.

### Prompt corpus

`.aai/SKILL_LOOP.prompt.md` 32242 bytes and `.aai/BOOTSTRAP_DIFF.prompt.md`
1190 bytes at `8293605d` (33432 together). The D4 text changes them by -28 and
-39 bytes (expected -67; the delivered delta is measured, not assumed).
`test-aai-prompt-diet.sh` today: TEST-010 headroom 0/2048, TEST-012 pin 64288.
`.aai/AGENTS.md` is outside the TEST-010 glob and carries no ledger cost.

## Decisions

- D-RETIRE (owner decision 2026-11-05): both files stay one release as
  deprecation launchers, then a later release deletes them; nothing is deleted
  here. Follow-up `fu-delete-retired-shell-loop-runner` records the deletion.
- D-EXIT: a launcher exits 1, prints exactly one line on stderr and nothing on
  stdout, ignores every argument, reads no STATE and needs neither Node, Python,
  git nor an agent CLI.
- D-REPL: the replacement named is `/aai-loop`.
- D-PROPOSE: `--propose-only` (a branch plus a temporary pre-push hook that
  blocks pushes) has no `/aai-loop` equivalent and is not ported; `/aai-loop`
  never merges, and `/aai-ship unattended=true` refuses to start without a
  declared run budget. Named in AUTONOMOUS_LOOP section 8, the user guide and
  the CHANGELOG.
- D-PIN: `test_single_state_creator` keeps its subject (one STATE creator) and
  asserts that neither launcher names `STATE_TEMPLATE`, `STATE.yaml` or
  `check-state`.
- D-INV: in the RFC-0017 inventory the `autonomous-loop` row keeps its Pair,
  Lines and Destination cells (TEST-2624 pins the destination; no contract
  amendment), with the Reason cell rewritten.
- D-DIET: the prompt shrink is reclaimed by one negative ledger entry equal to
  the measured byte delta, so TEST-010 headroom stays 0/2048 and the TEST-012
  pin moves by the same number.
- D-SUITE: one new suite `aai-retired-loop-runner` holds every row, as ride 1's
  `aai-legacy-migrations` did; the Pester file covers the `.ps1` under both
  Windows engines on the hosted job.

## Scope and design

### D1. Launchers

Each file is at most 20 lines, ASCII, keeps git mode 100644, holds one comment
line beginning `# RETIRED (RFC-0017 phase 5, retire-shell-loop-runner)` that
says it is a deprecation launcher for one release and the next release deletes
it, then writes exactly one line to stderr and `exit 1`.

- `autonomous-loop.sh`: first line `#!/bin/sh`, then the comment, then
  `echo "<line>" >&2` and `exit 1`.
- `autonomous-loop.ps1`: no param block (so `-Mode`, `-AgentCommand` and every
  other old switch land in `$args` and are ignored), the comment,
  `[Console]::Error.WriteLine('<line>')` and `exit 1`.
- The line (both files):
  `autonomous-loop: retired - the autonomous-loop shell runner is retired (RFC-0017 phase 5) and will be deleted in the next release; replacement: /aai-loop; nothing was changed`
- Neither file holds the words `node`, `python`, `git`, `codex`, `claude`,
  `gemini`, `mkdir`, `rm`, `cp`, `mv`, `STATE`, `LOOP_TICKS` or `SKILL_`.

### D2. Agent-facing text

- `.aai/AGENTS.md`: line 142 becomes
  `- Use SKILL_LOOP to run the autonomous loop; the shell loop runner is retired.`;
  line 220 (`- Loop runners are skill-first ...`) is deleted.
- `.aai/SKILL_LOOP.prompt.md` line 4 becomes
  `This replaces the retired external shell loop runner for agents`
  (line 5 unchanged).
- `.aai/BOOTSTRAP_DIFF.prompt.md`: `.aai/scripts/autonomous-loop.(sh|ps1), ` is
  removed from the list, so line 7 reads `.github/copilot-instructions.md)`.
- `.aai/scripts/generate-overview.mjs` line 208 comment becomes
  `// Legacy producers (the retired shell loop runner, STATE_FALLBACK schema) emit`;
  no code changes.

### D3. AUTONOMOUS_LOOP.md section 8

The heading and the first sentence (the three failure modes) stay. The rest of
the section is replaced by: one sentence that `/aai-loop`
(`.aai/SKILL_LOOP.prompt.md`) and `/aai-ship` (`.aai/SKILL_SHIP.prompt.md`)
provide these guarantees and that the retired shell loop runner no longer does,
then four bullets:

- **Never merges**: a finished scope ends with an open pull request; merging
  stays the operator's action unless a lane in `docs/ai/merge-policy.yaml`
  allows it.
- **Declared budget for unattended rides**: `/aai-ship` with `unattended=true`
  and an existing `--intake` refuses to start without a run budget and caps
  ticks, stagnation and pull requests (`.aai/scripts/unattended-gate.mjs
  preflight`).
- **Self-recovery before HITL**: the existing bullet, unchanged.
- **Wake-up digest** (`.aai/scripts/loop-digest.mjs`): `node
  .aai/scripts/loop-digest.mjs --write` (or `/aai-profile --last-run`) writes
  the summary of the last run to `docs/ai/reports/loop-digest-<stamp>.md`.

The section holds no `--propose-only`, `-ProposeOnly` or `autonomous-loop`.

### D4. Human-facing docs

- `docs/USER_GUIDE.md`: the section from `### Shell loop runners
  (autonomous-loop.sh / .ps1)` to the line before the next `---` becomes the
  heading `### Shell loop runners (retired)` and one single-line paragraph:
  `The shell loop runners \`.aai/scripts/autonomous-loop.sh\` and \`.aai/scripts/autonomous-loop.ps1\` are retired (RFC-0017 phase 5): for one release each prints one retirement line naming \`/aai-loop\`, changes nothing and exits 1, and the next release deletes them. Run \`/aai-loop\` in an agent session instead; for an unattended ride with a declared run budget use \`/aai-ship\` with \`unattended=true\` and an existing intake. The \`--propose-only\` push block has no replacement: \`/aai-loop\` never merges.`
  followed by the kept line
  `Validate skill readiness and evidence with \`.aai/scripts/validate-skills.sh\` / \`.aai/scripts/validate-skills.ps1\`.`
- `README.md` line 218: `written by the loop runner scripts` becomes
  `written by \`state.mjs log-tick\` during \`/aai-loop\``; line 239 drops
  `loop runner reference, `.
- `docs/TECHNOLOGY.md` line 47 drops `loop runners, ` (no technology is added
  or removed; bash still runs installers, hooks and suites).

### D5. Wiring and pins

- `tests/skills/test-aai-check-state.sh` `test_single_state_creator` per D-PIN:
  for each of the two launchers, fail when the file is missing or names
  `STATE_TEMPLATE`, `STATE.yaml` or `check-state`; the pass line says the
  retired launchers create no STATE.
- `tests/skills/suite-map.yaml`: new row `aai-retired-loop-runner` with globs
  `.aai/scripts/autonomous-loop.*`, `tests/skills/test-aai-retired-loop-runner.sh`,
  `tests/skills/retired-loop-runner.Tests.ps1`.
- `tests/skills/suite-weights.tsv`: a row only if the selector or its pin asks
  for one (ride 1 precedent).
- `.aai/system/PROFILES.yaml`: unchanged (both launchers stay under `core:`).
- `.github/workflows/ps1-quality.yml`: unchanged; its `.aai/scripts/**.ps1` and
  `tests/skills/*.Tests.ps1` globs already cover both files, and the native
  Windows Pester jobs pick up the new `*.Tests.ps1` by directory.
- `tests/skills/lib/prompt-diet-ledger.sh`: one entry
  `JUSTIFIED_ADDITIONS+=( "-<N> retire-shell-loop-runner RECLAIMED credit (NEGATIVE entry, ...)" )`
  where -N is the measured byte delta of SKILL_LOOP plus BOOTSTRAP_DIFF against
  `8293605d`; `tests/skills/test-aai-prompt-diet.sh` TEST-012 pin and its
  comment move from 64288 to 64288 minus N.
- Follow-up: `node .aai/scripts/follow-ups.mjs add --id fu-delete-retired-shell-loop-runner
  --ref retire-shell-loop-runner --severity P3` with a finding naming both
  launchers, their PROFILES lines, the D5 suite and Pester file and the
  USER_GUIDE retirement paragraph as what the deleting release removes.

### D6. RFC-0017

- The phase 5 row gains one sentence after the fifth-slice sentence and before
  the remaining-scripts-plan sentence:
  `The sixth slice [retired the shell loop runner](../issues/CHANGE-0246-retire-shell-loop-runner.md): autonomous-loop became a deprecation launcher for one release that names \`/aai-loop\`.`
  Status stays `in progress`; frontmatter untouched. The allocator rewrites
  the link at merge; checks match only the suffix `retire-shell-loop-runner.md`.
- Inventory (D-INV): the `autonomous-loop` row keeps `488/464` and
  `phase 5 process adapter`; its Reason cell becomes
  `retired by the [shell-loop-runner slice](../issues/CHANGE-0246-retire-shell-loop-runner.md); a deprecation launcher for one release naming /aai-loop, deleted in the next`.
  Every other row stays byte for byte.
- After LOOP COMPLETE (ship convention, in the review scope, not a TEST row):
  CHANGELOG `## [unreleased] — refactor(scripts): the shell loop runner is retired in favour of /aai-loop`
  naming the retirement and its one-release window, the replacement, D-PROPOSE
  and the before/after code lines.

## Acceptance Criteria Mapping

- Intake AC-001 maps to Spec-AC-01, Spec-AC-02 and Spec-AC-03, and to hosted
  check H1 (the native Windows Pester jobs under Windows PowerShell 5.1 and
  pwsh 7 run `tests/skills/retired-loop-runner.Tests.ps1`).
- Intake AC-002 maps to Spec-AC-04 and Spec-AC-05.
- Intake AC-003 maps to Spec-AC-05 and Spec-AC-06.
- Intake AC-004 maps to Spec-AC-07, Spec-AC-08, Spec-AC-09, Spec-AC-10 and
  Spec-AC-12.
- Intake AC-005 maps to Spec-AC-11.

## Constitution deviations

None. Article 4 (degrade and report): a retired launcher names itself, the
release that deletes it and its replacement, and exits 1 instead of failing
silently. Article 5 (additive first): both command names stay for one release
and say so on use. Article 2 (simplicity): no new flag, variable or seam;
aai-sync, PROFILES and the ps1-quality workflow are not edited.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN autonomous-loop.sh runs under bash, sh and dash from inside a committed fixture whose docs/ai holds no STATE.yaml, once with --mode skill --agent-command codex --max-iterations 1 --auto-init-state and once with no argument, with PATH holding no node, python3, codex or claude, the system SHALL print exactly the D1 line on stderr, nothing on stdout, exit 1, create no docs/ai/STATE.yaml and no docs/ai/LOOP_TICKS.jsonl, and leave git status empty and the fixture file listing unchanged. | done | docs/ai/reports/VALIDATION-retire-shell-loop-runner-r4.md; docs/ai/tdd/retire-shell-loop-runner/green/suite-retired-loop-runner.log | — | — |
| Spec-AC-02 | WHEN autonomous-loop.ps1 runs under pwsh with -Mode skill -AgentCommand codex -MaxIterations 1 -AutoInitState, with no argument and with -DryRun under the same PATH limits, the system SHALL print exactly the D1 line on stderr, nothing on stdout, exit 1 and leave the fixture unchanged; and tests/skills/retired-loop-runner.Tests.ps1 SHALL pass under Pester 5 with no failed or skipped case and at least 3 cases. | done | docs/ai/reports/VALIDATION-retire-shell-loop-runner-r4.md; docs/ai/tdd/retire-shell-loop-runner/green/suite-retired-loop-runner.log | — | — |
| Spec-AC-03 | Each launcher is at most 20 lines, ASCII only, git mode 100644, holds one line beginning # RETIRED (RFC-0017 phase 5, retire-shell-loop-runner) and the D1 line text, the sh first line is #!/bin/sh, the ps1 has no param block, and neither holds any D1 forbidden word. | done | docs/ai/reports/VALIDATION-retire-shell-loop-runner-r4.md; docs/ai/tdd/retire-shell-loop-runner/green/suite-retired-loop-runner.log | — | — |
| Spec-AC-04 | Over tracked files outside docs/ and tests/ except CHANGELOG.md, plus docs/USER_GUIDE.md and docs/TECHNOLOGY.md, every line naming autonomous-loop is in one of the two launchers or .aai/system/PROFILES.yaml or contains the word retired; AGENTS.md holds the D2 line and no legacy mode line; SKILL_LOOP line 4 and the BOOTSTRAP_DIFF list hold the D2 text; README.md and TECHNOLOGY.md hold no loop runner phrase; USER_GUIDE.md holds the D4 heading and no --agent-command, -AgentCommand or --mode skill example. | done | docs/ai/reports/VALIDATION-retire-shell-loop-runner-r4.md; docs/ai/tdd/retire-shell-loop-runner/green/suite-retired-loop-runner.log | — | — |
| Spec-AC-05 | AUTONOMOUS_LOOP.md section 8 holds the D3 sentence naming /aai-loop and /aai-ship, the four D3 bullets, no --propose-only, -ProposeOnly or autonomous-loop, and every .aai/ path it names exists in the tree; SKILL_LOOP still names loop-digest.mjs --json, and loop-digest.mjs exists and stays listed once under core in PROFILES.yaml. | done | docs/ai/reports/VALIDATION-retire-shell-loop-runner-r4.md; docs/ai/tdd/retire-shell-loop-runner/green/suite-retired-loop-runner.log | — | — |
| Spec-AC-06 | test_single_state_creator in tests/skills/test-aai-check-state.sh names both launchers and fails when either names STATE_TEMPLATE, STATE.yaml or check-state; test-aai-check-state.sh exits 0 on the delivered tree. | done | docs/ai/reports/VALIDATION-retire-shell-loop-runner-r4.md; docs/ai/tdd/retire-shell-loop-runner/green/suite-retired-loop-runner.log | — | — |
| Spec-AC-07 | The prompt-diet ledger holds exactly one retire-shell-loop-runner entry, negative, equal to the delivered byte size of SKILL_LOOP plus BOOTSTRAP_DIFF minus 33432; test-aai-prompt-diet.sh exits 0 with TEST-010 headroom 0 of 2048 and the TEST-012 pin equal to 64288 plus that entry. | done | docs/ai/reports/VALIDATION-retire-shell-loop-runner-r4.md; docs/ai/tdd/retire-shell-loop-runner/green/suite-retired-loop-runner.log | — | — |
| Spec-AC-08 | Wiring per D5: select-suites on .aai/scripts/autonomous-loop.sh and on .aai/scripts/autonomous-loop.ps1 each selects aai-retired-loop-runner; PROFILES.yaml lists each launcher once under core and test-aai-layer-profiles.sh exits 0; both ps1-quality path lists still hold the .aai/scripts/**.ps1 and tests/skills/*.Tests.ps1 globs. | done | docs/ai/reports/VALIDATION-retire-shell-loop-runner-r4.md; docs/ai/tdd/retire-shell-loop-runner/green/suite-retired-loop-runner.log | — | — |
| Spec-AC-09 | WHEN aai-sync.sh --profile core installs into a scratch git target whose path holds a space the system SHALL carry both launchers, and the target's own autonomous-loop.sh under bash and autonomous-loop.ps1 under pwsh, run from inside the target with skill-mode arguments, SHALL each print the D1 line, exit 1 and create no docs/ai/STATE.yaml. | done | docs/ai/reports/VALIDATION-retire-shell-loop-runner-r4.md; docs/ai/tdd/retire-shell-loop-runner/green/suite-retired-loop-runner.log | — | — |
| Spec-AC-10 | The RFC-0017 inventory equals the pair set of the tree (TEST-2624 exits 0), the autonomous-loop row keeps 488/464 and phase 5 process adapter and carries the D6 reason with a link ending retire-shell-loop-runner.md, and the phase 5 row keeps status in progress and holds the D6 sentence exactly once. | done | docs/ai/reports/VALIDATION-retire-shell-loop-runner-r4.md; docs/ai/tdd/retire-shell-loop-runner/green/suite-retired-loop-runner.log | — | — |
| Spec-AC-11 | Measured with the plan's method on the delivered tree, each launcher has at most 2 code lines and at most 20 lines in total, so the two files hold at most 4 code lines against 793 before. | done | docs/ai/reports/VALIDATION-retire-shell-loop-runner-r4.md; docs/ai/tdd/retire-shell-loop-runner/green/suite-retired-loop-runner.log | — | — |
| Spec-AC-12 | follow-ups.mjs list --json holds one open item fu-delete-retired-shell-loop-runner with ref retire-shell-loop-runner, severity P3 and a finding naming autonomous-loop.sh, autonomous-loop.ps1 and PROFILES.yaml. | done | docs/ai/reports/VALIDATION-retire-shell-loop-runner-r4.md; docs/ai/tdd/retire-shell-loop-runner/green/suite-retired-loop-runner.log | — | — |

## Implementation plan

TDD in four runs of about three Spec-ACs; each run stores RED under
`docs/ai/tdd/retire-shell-loop-runner/red/` before its change, GREEN under
`green/`, and one mutation record per row (`node .aai/scripts/mutation-run.mjs`)
before the run's hand-off.

1. Run 1, Spec-AC-01 to 03: write `tests/skills/test-aai-retired-loop-runner.sh`
   (fails on zero passing tests) and `tests/skills/retired-loop-runner.Tests.ps1`,
   then the two launchers (D1).
2. Run 2, Spec-AC-04 to 06: AGENTS, SKILL_LOOP, BOOTSTRAP_DIFF, generate-overview
   comment (D2), AUTONOMOUS_LOOP section 8 (D3), USER_GUIDE, README, TECHNOLOGY
   (D4), the check-state pin (D5).
3. Run 3, Spec-AC-07 to 09: the ledger true-up, the suite map (and weights if
   asked), the scratch install.
4. Run 4, Spec-AC-10 to 12: RFC-0017 (D6), the measurement, the follow-up; then
   the CHANGELOG entry after LOOP COMPLETE.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3403 | Spec-AC-01 | integration | tests/skills/test-aai-retired-loop-runner.sh | test_3403_sh_retired_run builds a committed git fixture with local identity and a docs/ai folder holding only .gitkeep, then runs .aai/scripts/autonomous-loop.sh under bash, sh and dash by absolute path from inside it, with PATH set to a scratch bin holding only coreutils links (no node, python3, codex, claude), once with --mode skill --agent-command codex --max-iterations 1 --auto-init-state and once with no argument: each stderr equals the D1 line, stdout empty, exit 1, no docs/ai/STATE.yaml or LOOP_TICKS.jsonl, git status empty and the fixture listing unchanged | `sed:s/exit 1/exit 0/` on .aai/scripts/autonomous-loop.sh | pending |
| TEST-3404 | Spec-AC-02 | integration | tests/skills/test-aai-retired-loop-runner.sh | test_3404_ps1_retired_run runs .aai/scripts/autonomous-loop.ps1 under pwsh (need_tool pwsh, SKIP-CASE when absent) from inside the TEST-3403 fixture with the same PATH limit, three times: -Mode skill -AgentCommand codex -MaxIterations 1 -AutoInitState, no argument, -DryRun; each stderr equals the D1 line, stdout empty, exit 1, no STATE.yaml, git status empty | `sed:s/exit 1/exit 0/` on .aai/scripts/autonomous-loop.ps1 | pending |
| TEST-3405 | Spec-AC-02 | integration | tests/skills/test-aai-retired-loop-runner.sh | test_3405_pester runs Invoke-Pester on tests/skills/retired-loop-runner.Tests.ps1 with PassThru under pwsh and fails on FailedCount above 0, SkippedCount above 0 or TotalCount below 3 (SKIP-CASE without Pester 5, as SPEC-0273 TEST-3388 does); the cases build a git fixture in TestDrive with local identity and run the ps1 launcher with the engine running the test, with skill-mode switches, with no argument and with -DryRun, each asserting the D1 line on stderr, exit 1 and no docs/ai/STATE.yaml | `sed:s/replacement: \/aai-loop/replacement: none/` on .aai/scripts/autonomous-loop.ps1 | pending |
| TEST-3406 | Spec-AC-03 | inspection | tests/skills/test-aai-retired-loop-runner.sh | test_3406_launchers_thin requires each launcher at most 20 lines, ASCII only, git ls-files -s mode 100644, exactly one line beginning # RETIRED (RFC-0017 phase 5, retire-shell-loop-runner), the D1 line text, the sh first line #!/bin/sh, no param( in the ps1, and none of the D1 forbidden words as a word; positive control: a scratch copy holding git status is reported | `sed:s/exit 1/git status; exit 1/` on .aai/scripts/autonomous-loop.sh | pending |
| TEST-3407 | Spec-AC-04 | inspection | tests/skills/test-aai-retired-loop-runner.sh | test_3407_no_stale_instruction lists tracked files outside docs/ and tests/ except CHANGELOG.md, plus docs/USER_GUIDE.md and docs/TECHNOLOGY.md, and requires every line naming autonomous-loop to sit in a launcher or PROFILES.yaml or to contain retired; requires the D2 AGENTS line, no legacy mode line in AGENTS.md, the D2 SKILL_LOOP line 4 and BOOTSTRAP_DIFF line 7, no loop runner phrase in README.md or docs/TECHNOLOGY.md, the D4 USER_GUIDE heading and no --agent-command, -AgentCommand or --mode skill there; positive control: a fixture list with one extra naming line is reported | `sed:s/the shell loop runner is retired\./run autonomous-loop.sh outside an agent session./` on .aai/AGENTS.md | pending |
| TEST-3408 | Spec-AC-05 | inspection | tests/skills/test-aai-retired-loop-runner.sh | test_3408_unattended_section extracts AUTONOMOUS_LOOP.md section 8 (from its heading to the next ## heading) and requires /aai-loop, /aai-ship, the four D3 bullet labels, no --propose-only, -ProposeOnly or autonomous-loop, and every .aai/ path token in it to exist; requires loop-digest.mjs --json in SKILL_LOOP, the module on disk and its PROFILES core line exactly once | `sed:s/Self-recovery before HITL/Propose-only (--propose-only) and self-recovery before HITL/` on .aai/system/AUTONOMOUS_LOOP.md | pending |
| TEST-3409 | Spec-AC-06 | inspection | tests/skills/test-aai-retired-loop-runner.sh | test_3409_state_creator_pin requires test_single_state_creator in tests/skills/test-aai-check-state.sh to name both launchers and the three D-PIN words, runs env -u AAI_ROLE bash tests/skills/test-aai-check-state.sh (exit 0); positive control: sourcing the suite with PROJECT_ROOT pointed at a scratch copy whose .ps1 launcher names STATE.yaml makes test_single_state_creator report a FAIL | `sed:s/exit 1/exit 1 # docs\/ai\/STATE.yaml/` on .aai/scripts/autonomous-loop.ps1 | pending |
| TEST-3410 | Spec-AC-07 | inspection | tests/skills/test-aai-retired-loop-runner.sh | test_3410_diet requires exactly one ledger line naming retire-shell-loop-runner whose amount is negative and equals the current byte size of SKILL_LOOP plus BOOTSTRAP_DIFF minus 33432, runs test-aai-prompt-diet.sh (exit 0) and requires its output to hold headroom 0/2048 and the TEST-012 pin equal to 64288 plus that amount | `sed:s/ retire-shell-loop-runner RECLAIMED/0 retire-shell-loop-runner RECLAIMED/` on tests/skills/lib/prompt-diet-ledger.sh | pending |
| TEST-3411 | Spec-AC-08 | inspection | tests/skills/test-aai-retired-loop-runner.sh | test_3411_wiring pipes each launcher path to node .aai/scripts/select-suites.mjs --files-from - --repo-root and requires aai-retired-loop-runner in each answer; requires each launcher line exactly once under core: in PROFILES.yaml and runs test-aai-layer-profiles.sh (exit 0); requires both ps1-quality path lists to hold .aai/scripts/**.ps1 and tests/skills/*.Tests.ps1 | `sed:s/      - \.aai\/scripts\/autonomous-loop\.\*/      - .aai\/scripts\/autonomous-loop-gone.*/` on tests/skills/suite-map.yaml | pending |
| TEST-3412 | Spec-AC-09 | e2e | tests/skills/test-aai-retired-loop-runner.sh | test_3412_downstream_install runs aai-sync.sh --profile core into a scratch git target named with a space, requires both launchers there, runs the target's own bash .aai/scripts/autonomous-loop.sh --mode skill --agent-command codex --auto-init-state and pwsh -NoProfile -File .aai/scripts/autonomous-loop.ps1 -Mode skill -AutoInitState (when pwsh is present) from inside it: each stderr equals the D1 line, exit 1, no docs/ai/STATE.yaml created by the run | `sed:s/  - \.aai\/scripts\/autonomous-loop\.sh/  - .aai\/scripts\/autonomous-loop-gone.sh/` on .aai/system/PROFILES.yaml | pending |
| TEST-3413 | Spec-AC-10 | inspection | tests/skills/test-aai-retired-loop-runner.sh | test_3413_rfc runs bash tests/skills/test-aai-expert-fetch.sh test_2624_inventory_matches_tree (exit 0), requires the autonomous-loop row cells 488/464 and phase 5 process adapter and the D6 reason with a link ending retire-shell-loop-runner.md, and the phase 5 row with status in progress and the D6 sentence exactly once | `sed:s/retire-shell-loop-runner\.md\)/retire-shell-loop-gone.md)/` on docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md | pending |
| TEST-3414 | Spec-AC-11 | inspection | tests/skills/test-aai-retired-loop-runner.sh | test_3414_line_budget counts code lines with grep -cvE on the hash comment and blank pattern under bash with /usr/bin/grep when present: each launcher at most 2 code lines and at most 20 in wc -l, the sum at most 4, and prints before 793 and the after sum | `sed:s/# RETIRED \(RFC-0017 phase 5, retire-shell-loop-runner\)/echo a # RETIRED (RFC-0017 phase 5, retire-shell-loop-runner)/` on .aai/scripts/autonomous-loop.sh | pending |
| TEST-3415 | Spec-AC-12 | inspection | tests/skills/test-aai-retired-loop-runner.sh | test_3415_follow_up runs node .aai/scripts/follow-ups.mjs list --status open --json and requires exactly one item fu-delete-retired-shell-loop-runner with ref retire-shell-loop-runner, severity P3 and a finding naming autonomous-loop.sh, autonomous-loop.ps1 and PROFILES.yaml | `sed:s/fu-delete-retired-shell-loop-runner/fu-delete-retired-shell-loop-gone/` on docs/ai/decisions.jsonl | pending |

Test counts by type: integration 3, inspection 9, e2e 1 (13).

Seams crossed (Principle 2): each launcher under every engine that runs it
(TEST-3403, TEST-3404, TEST-3405; Windows PowerShell 5.1 and pwsh 7 on native
Windows in H1); aai-sync's profile copy to the target's own launchers
(TEST-3412); the rewritten check-state pin read by its own suite (TEST-3409);
the RFC inventory read by SPEC-0249's check (TEST-3413); the ledger read by
test-aai-prompt-diet (TEST-3410); select-suites reading the suite map and
layer-profiles reading PROFILES (TEST-3411); the follow-up ledger read by
follow-ups.mjs (TEST-3415).

## Verification

- `env -u AAI_ROLE -u AAI_GIT_WRITE bash tests/skills/test-aai-retired-loop-runner.sh`
  exits 0 (13 rows), plus the touched and selected suites:
  test-aai-check-state.sh, test-aai-prompt-diet.sh, test-aai-layer-profiles.sh,
  test-aai-expert-fetch.sh, test-aai-live-status.sh, test-aai-hygiene-pack.sh,
  test-aai-harness-shims.sh, test-aai-spec-amend.sh,
  test-aai-downstream-autopilot.sh, test-aai-merge-cleanup.sh,
  test-aai-overview.sh (generate-overview comment only). No full
  sweep is required by this spec; Validation decides its own.
- `node .aai/scripts/spec-lint.mjs --path <this spec>` and
  `node .aai/scripts/mutation-gate.mjs` for this spec pass.
- H1 (hosted): the ps1-quality Windows jobs pass under Windows PowerShell 5.1
  and pwsh 7 with `retired-loop-runner.Tests.ps1` discovered and not skipped.

## Evidence contract

ref_id `retire-shell-loop-runner`; RED, GREEN and mutation evidence under
`docs/ai/tdd/retire-shell-loop-runner/` (gitignored); each AC row's Evidence
names its green log and mutation record; the validation report and review
verdict under `docs/ai/reports/` and `docs/ai/reviews/`.

### Evidence by strategy

tdd: a stored RED artifact per AC-gating test plus the verification matrix
above.

## Residual risks

- Windows PowerShell 5.1 parity is proven only on the hosted job (H1);
  Planning had no 5.1 engine.
- A downstream cron job, CI step or wrapper script that calls either runner
  fails with exit 1 from the release that ships this; the CHANGELOG and the
  user guide name the replacement. No shipped AAI path calls them.
- `--propose-only` has no replacement (D-PROPOSE); a downstream user who relied
  on its pre-push block loses it. `/aai-loop` never merges.
- The retirement relies on the later release deleting both launchers;
  `fu-delete-retired-shell-loop-runner` records it, nothing enforces it.
- `docs/product/precise-suite-evidence-reuse.md` line 137 still says the
  autonomous-loop migration is a later phase 5 slice; product docs under
  docs/ are left as delivered history.
- `tests/skills/test-aai-live-status.sh` TEST-016 keeps the `.sh` path in its
  list; it skips a missing file, so the deleting release needs no edit there.

Registry items closed by this scope: none.
