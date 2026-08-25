---
id: spec-harness-surfaces-drift-unguarded
type: spec
number: null
status: implementing
ceremony_level: 2
links:
  requirement: docs/issues/ISSUE-DRAFT-harness-surfaces-drift-unguarded.md
  rfc: null
  pr: []
  commits: []
---

# Spec — harness skill surfaces are generated from one source and gated by one arm

SPEC-FROZEN: true

## Headline: there are FOUR mirrors, not three, and the fourth proves the drift was mechanical

The intake enumerated `.claude/skills`, `.codex/skills`, `.gemini/skills` and
`.cursor/rules/aai.mdc`. Planning measured a fourth tracked skill tree the intake
did not know about: **`.agents/skills/`, 33 directories, tracked in git since
2026-07-17, copied by no sync script at all** (`grep -n '\.agents'
.aai/scripts/aai-sync.sh .aai/scripts/aai-sync.ps1` returns nothing). It is
Cursor's FIRST documented project-skills path, so it is not a dead directory —
it is the one Cursor reads before any compatibility path.

That fourth tree also settles decision D1 on evidence rather than taste.
`.agents/skills/aai-auto-trigger/SKILL.md` says, twice:

    .Codex/triggers.json

The real path is `.claude/triggers.json`. A capitalised `.Codex/` is what a
blind `Claude` to `Codex` text substitution produces, and it has been shipping
in a tracked file for five weeks. The mirrors were never hand-authored in a
harness-specific idiom; they are the frozen output of a substitution nobody
re-ran, and one of them is visibly corrupt.

Measured divergence at planning time (all commands under `/bin/bash -c` with
`/usr/bin/grep`, `AAI_ROLE=subagent`):

| Surface | Skill dirs | Missing vs `.claude/skills` | Extra |
|---|---|---|---|
| `.claude/skills` | 39 | — | — |
| `.agents/skills` | 33 | aai-factory-report, aai-feedback-triage, aai-feedback-upsert, aai-overview, aai-release, aai-ship | none |
| `.codex/skills` | 31 plus README | aai-docs-audit, aai-docs-canon, aai-factory-report, aai-feedback-triage, aai-feedback-upsert, aai-overview, aai-ship, aai-test-canon | none |
| `.gemini/skills` | 31 plus README | same eight | none |

`.codex/skills` and `.gemini/skills` are byte-identical to each other except
three tokens: the README title, and the word `Codex` versus `Gemini` inside the
`aai-release` and `aai-update` descriptions. Twenty-eight of the thirty-one
shared descriptions differ from `.claude/skills`, and the differences are AGE,
not idiom — `.codex/skills/aai-pr/SKILL.md` carries the Claude description
verbatim minus the close-ceremony clause added later; `.agents/skills/aai-loop`
carries it minus the ceremony-lane clause; `.agents/skills/aai-docs-audit`
carries it minus `duplicate-doc-id`. Three descriptions are already identical to
Claude's, which a deliberate idiom would not permit.

One divergence is a functional regression, not cosmetics: fifteen
`.claude/skills` wrappers carry the `<SUBAGENT-STOP>` block; only three of the
`.codex/skills` copies do. A Codex subagent dispatched into a role can therefore
walk into `/aai-loop` in twelve places where a Claude subagent is stopped.

## Links
- Requirement: docs/issues/ISSUE-DRAFT-harness-surfaces-drift-unguarded.md
- Suite that gains the guard: tests/skills/test-aai-hygiene-pack.sh
- Selector contract: tests/skills/suite-map.yaml
- Vendored-layer classification contract: .aai/system/PROFILES.yaml
- Prompt-corpus ledger: tests/skills/lib/prompt-diet-ledger.sh
- Technology contract: docs/TECHNOLOGY.md

## Decisions

### D1 — The mirrors become GENERATED, not eight more hand-authored shims

Chosen: a deterministic generator, `.aai/scripts/sync-harness-skills.mjs`,
projects `.claude/skills/*/SKILL.md` into all three mirror trees under one
declared per-tree transform, and refuses to guess.

Rationale: the alternative — authoring eight shims in "the mirrors' own idiom" —
presupposes an idiom, and the measurements above say there is not one. What
looks like harness-specific wording is a 2026-03-era snapshot plus a
name-substitution artifact (`.Codex/triggers.json`) that no author would have
written. Hand-authoring eight files would leave 28 stale descriptions, 12
missing `<SUBAGENT-STOP>` blocks and one corrupt path in place, and would
re-create the same two-file chore the next time a skill lands — a chore the
guard would then have to catch every single time, which is a guard used as a
task queue rather than a safety net. Generation collapses the whole class:
the mirror content stops being a thing anyone can get wrong, the guard degenerates
to `--check` exiting zero, and the only judgement left is the transform table,
which is declared once in data and reviewed once. The cost is that a genuinely
harness-specific description becomes impossible without a manifest entry; that
cost is paid deliberately, because no such description was found to exist.

The declared transform, recorded in `.aai/system/HARNESS_SKILLS.yaml`:

| Tree | Body | `name` | `description` | `model` key | Generated README |
|---|---|---|---|---|---|
| `.agents/skills` | verbatim | verbatim | verbatim | carried | no |
| `.codex/skills` | verbatim | verbatim | verbatim | dropped | yes |
| `.gemini/skills` | verbatim | verbatim | verbatim | dropped | yes |

`model:` is dropped from the Codex and Gemini trees because neither vendor
documents that key and neither documents ignoring unknown ones; that matches
what those trees already do today (zero `model:` lines). It is carried into
`.agents/skills` because that tree is already a verbatim copy and Cursor reads
`.claude/skills` — which necessarily carries the key — as a first-class source
anyway, so dropping it there would buy nothing and diverge from the source for
no stated reason.

### D2 — This repo does NOT ship `.cursor/skills/`

Chosen: no `.cursor/skills/` directory, now or later, and this paragraph exists
so the next reader does not "fix" its absence.

Rationale: Cursor loads project skills from `.agents/skills/`, `.cursor/skills/`
and — for compatibility — `.claude/skills/` and `.codex/skills/`. This repo
already ships three of those four. A fourth copy would be a fourth place to
drift, a third duplicate offering of every skill name inside one harness, and
zero additional skills visible to Cursor, because everything a `.cursor/skills/`
copy could offer is already offered by `.agents/skills/`. The correct number of
copies is fewer, not more; shipping `.cursor/skills/` moves in the wrong
direction while claiming to fix something.

### D3 — The duplicate offering is NAMED, not resolved

Cursor loads `.agents/skills/`, `.claude/skills/` and `.codex/skills/`, and this
repo ships all three, so every one of the 39 skill names is offered to Cursor
three times. Cursor's documentation states no dedup rule and no precedence order
across those directories, so what a Cursor user sees is undefined by the vendor
and cannot be resolved from this repo. What this scope CAN do, and does, is make
the three copies agree: after normalization the three offerings of a given name
carry an identical `name` and an identical `description`, so whichever one wins,
the user reads the same sentence. That is strictly better than today, where the
three copies carry three different descriptions of the same skill. The ambiguity
is recorded in the header of `.aai/system/HARNESS_SKILLS.yaml` — the file
someone must open to add or remove a tree — rather than only in this spec, which
that person has no reason to read.

### D4 — The guard lives in `tests/skills/test-aai-hygiene-pack.sh`, not a new suite

Rationale: it is the only suite that already treats the harness trees as a SET.
Its `skill_trees()` helper enumerates `.claude .gemini .codex` and eight existing
arms iterate it asserting per-skill wrapper properties. Its suite-map row already
globs `.claude/skills/**/SKILL.md`, `.codex/skills/**/SKILL.md` and
`.gemini/skills/**/SKILL.md`. Decisively, it is a `core:` suite, so it runs on
EVERY selected-mode PR regardless of the diff — and a parity guard that suite
selection can skip is the exact failure mode this issue is about
(`fu-ratchet-not-selected-on-rise` is the same shape, already in the registry).
A new suite would also need its own suite-map row to satisfy the hygiene pack's
own AC-003 pin, so "new suite" costs a row either way and loses the always-on
property. `skill_trees()` is extended to include `.agents`, so the eight
existing cross-tree arms start covering the fourth tree as a side effect.

### D5 — `aai-sync.{sh,ps1}` are NOT touched by this scope

`.agents/skills/` is copied by neither sync script, so a vendored downstream
project never receives it. That is a real distribution gap and it is NOT fixed
here: the sync scripts carry a byte-identity test
(`test-aai-layer-profiles.sh` `test_default_byte_identity`) and two
managed-prefix lists that a new tree must enter consistently, which is a
distinct change with a distinct blast radius. Filed as a registry follow-up
rather than dropped — see `## Registry items closed by this scope`.

## Implementation strategy
- Strategy: tdd
- Rationale: this scope has an unusually cheap and unusually honest RED, because
  the bug is live in the tracked tree. Write the parity arm first and it fails on
  the real repository — eight missing directories in two trees, six in a third,
  a `.Codex/triggers.json` in a fourth — with no fixture construction at all.
  The selector arm has the same property: `.cursor/rules/aai.mdc` and
  `.agents/skills/aai-ship/SKILL.md` both return `FULL_RUN reason=unmapped`
  today, measured. Writing the guard after the normalization would mean the arm
  had never once been observed failing against the drift it exists to catch,
  which for a guard is the whole of its evidence. RED first, then run the
  generator, is therefore both the cheapest order and the only order that
  produces evidence.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: the normalization rewrites or creates roughly 120 tracked
  files across four directory trees in one mechanical pass. A disposable
  worktree keeps that churn separable from the hand-written surfaces (generator,
  manifest, suite arms, Cursor rule) if the transform table needs a second
  iteration, and makes "regenerate and diff" a cheap experiment rather than a
  commit. Independently, the Spec-AC-05 bite proofs are bound to disposable
  DETACHED worktrees by HAZ-RESTORE and HAZ-WORKTREE regardless of where
  implementation runs. Implementation Preparation asks and decides.
- User decision: undecided
- Base ref: main
- Worktree branch/path: fix/harness-surface-parity (current branch)
- Inline review scope: .aai/scripts/sync-harness-skills.mjs,
  .aai/system/HARNESS_SKILLS.yaml, .aai/system/PROFILES.yaml,
  tests/skills/test-aai-hygiene-pack.sh, tests/skills/suite-map.yaml,
  .cursor/rules/aai.mdc, AGENTS.md, .agents/skills, .codex/skills,
  .gemini/skills, docs/specs/SPEC-DRAFT-harness-surfaces-drift-unguarded.md,
  docs/issues/ISSUE-DRAFT-harness-surfaces-drift-unguarded.md, CHANGELOG.md

## Acceptance Criteria Mapping

- Maps to: the intake's Expected Behavior bullets 1 to 3.

**Spec-AC-01 — every harness tree offers every skill.**
WHEN the four skill trees are compared THEN `.agents/skills`, `.codex/skills`
and `.gemini/skills` each contain exactly the same set of skill directories as
`.claude/skills`, with no directory missing and none extra.
Verification: for each tree T in `.agents .codex .gemini`, the command
`comm -3 <(ls .claude/skills | sort) <(for n in $(ls T/skills); do test -f T/skills/$n/SKILL.md && echo $n; done | sort) | wc -l`
prints `0`. Pre-change this prints 6, 8 and 8.
Evidence: the three counts, and `ls .claude/skills | wc -l` equal to
`ls .codex/skills | wc -l` minus one for the README.

**Spec-AC-02 — mirror content is generated and idempotent.**
WHEN `node .aai/scripts/sync-harness-skills.mjs --check` runs THEN it exits 0,
and WHEN `--write` runs immediately afterwards THEN it changes no bytes.
Verification: `node .aai/scripts/sync-harness-skills.mjs --check; echo $?`
prints `0`; then `node .aai/scripts/sync-harness-skills.mjs --write` followed by
`git diff --quiet -- .agents/skills .codex/skills .gemini/skills; echo $?`
prints `0`.
Evidence: both exit codes, plus the `--check` stdout on the PRE-change tree
naming `.Codex/triggers.json` in `.agents/skills/aai-auto-trigger/SKILL.md` as a
content divergence.

**Spec-AC-03 — the transform is declared in data, and the generator refuses to guess.**
WHEN `.aai/system/HARNESS_SKILLS.yaml` does not declare a tree that exists on
disk, or declares a tree with no transform row, THEN the generator exits 2 and
its stderr names the offending tree; it never falls back to a built-in default.
Verification: run the generator with `--manifest <fixture>` against a manifest
copy whose `.codex/skills` entry is deleted; assert exit code 2 and that stderr
contains the literal `.codex/skills`.
Evidence: exit code and the stderr line.

**Spec-AC-04 — the guard is an arm of an existing suite and it is registered.**
`tests/skills/test-aai-hygiene-pack.sh` carries the parity arms, they are listed
in its `main()`, and the whole suite is green.
Verification: `env -u AAI_ROLE bash tests/skills/test-aai-hygiene-pack.sh; echo $?`
prints `0`, and `node .aai/scripts/check-test-registration.mjs tests/skills; echo $?`
prints `0`.
Evidence: both exit codes and the suite's PASS lines for the new arms.

**Spec-AC-05 — the guard bites, with an unmutated control.**
In a disposable detached worktree cut from the base ref, each of three mutations
independently reddens the parity arm while an unmutated run of the same arm in
the same worktree stays green: (a) a new directory added under
`.claude/skills` only, (b) a directory deleted from `.codex/skills` only,
(c) a `description` line edited in `.claude/skills` only.
Verification: for each mutation, `bash tests/skills/test-aai-hygiene-pack.sh
<parity_fn>` exits non-zero and its FAIL line names the offending tree and
skill; the control run of the same function before any mutation exits 0.
Evidence: four transcripts under `docs/ai/tdd/`, one control plus three
mutations, each naming the worktree path.

**Spec-AC-06 — a legitimate exclusion is expressible without disabling the guard.**
An `exclusions` entry in `.aai/system/HARNESS_SKILLS.yaml` naming a tree, a
skill and a non-empty `reason` forgives exactly that one pair; every other pair
is still asserted, and an entry naming a skill that is absent from
`.claude/skills` fails the arm rather than being silently tolerated.
Verification: three fixture-manifest arms — one skill excluded from one tree
passes while the same skill missing from a second tree still fails; an exclusion
with an empty `reason` fails; an exclusion naming `aai-does-not-exist` fails
with a message containing `stale exclusion`.
Evidence: the three exit codes and their FAIL lines.
Note: the shipped manifest carries ZERO exclusions — the fixed point after
normalization is that nothing needs forgiving.

**Spec-AC-07 — the Cursor rule states nothing the current Cursor docs contradict.**
`.cursor/rules/aai.mdc` no longer claims skills are prompt files to be read by
hand, enumerates no subset of skill names or prompt paths, and its frontmatter
uses the documented keys with `alwaysApply: true`.
Verification: `/usr/bin/grep -c 'Skills are prompt files' .cursor/rules/aai.mdc`
prints `0`; `/usr/bin/grep -c '\.aai/SKILL_' .cursor/rules/aai.mdc` prints `0`;
`/usr/bin/grep -c '^alwaysApply: true$' .cursor/rules/aai.mdc` prints `1`;
`/usr/bin/grep -c '^description: ' .cursor/rules/aai.mdc` prints `1`;
`wc -l < .cursor/rules/aai.mdc` is at most 60, well inside Cursor's documented
500-line guidance.
Evidence: the five command outputs.

**Spec-AC-08 — the shared root shim names its real audience, and the ambiguity is recorded where it will be read.**
Root `AGENTS.md` is not titled for one harness, and
`.aai/system/HARNESS_SKILLS.yaml` records both D2 and D3 in its header.
Verification: `/usr/bin/grep -c '^# Codex Instructions' AGENTS.md` prints `0`
and `head -1 AGENTS.md` is exactly `# Agent Instructions (Shim)`;
`/usr/bin/grep -c 'cursor/skills' .aai/system/HARNESS_SKILLS.yaml` is at least
`1` and `/usr/bin/grep -c 'three times' .aai/system/HARNESS_SKILLS.yaml` is at
least `1`.
Evidence: the four command outputs.

**Spec-AC-09 — every harness surface selects the guard's suite.**
WHEN a diff touches any harness surface THEN `select-suites.mjs` maps the path
to a suite instead of failing open on an unmapped path.
Verification: for each of `.agents/skills/aai-ship/SKILL.md`,
`.cursor/rules/aai.mdc`, `AGENTS.md`, `.aai/system/HARNESS_SKILLS.yaml` and
`.aai/scripts/sync-harness-skills.mjs`, run
`node .aai/scripts/select-suites.mjs --files-from <file>` and assert the output
contains no line matching `FULL_RUN reason=unmapped` and does contain
`aai-hygiene-pack`. Pre-change, three of the five print
`FULL_RUN reason=unmapped` (measured for `.cursor/rules/aai.mdc` and
`.agents/skills/aai-ship/SKILL.md`).
Evidence: five selector transcripts.

**Spec-AC-10 — nothing else moves.**
The full framework sweep is green; the prompt corpus is byte-unchanged; no
protected or content-pinned file is touched.
Verification: `env -u AAI_ROLE bash tests/skills/test-framework.sh` exits 0;
`/bin/bash -c 'cat .aai/*.prompt.md | wc -c'` prints `315049`;
`env -u AAI_ROLE bash tests/skills/test-aai-prompt-diet.sh` exits 0 with its
TEST-012 pin still `2392`;
`env -u AAI_ROLE bash tests/skills/test-aai-layer-profiles.sh` exits 0 (its
TEST-001 proves both new `.aai/**` files are classified in PROFILES.yaml);
`git diff --name-only main...HEAD` contains none of the eight
`protected_paths_l3` entries and does not contain
`.aai/scripts/close-work-item.mjs`.
Evidence: the four exit codes, the byte count, the pin line, and the diff list.

## Constitution deviations

None. Article 4 (degrade and report) governs the generator's refusal path: an
undeclared tree is named and refused (Spec-AC-03), never silently defaulted.
Article 5 (additive first, public boundaries documented) governs the two new
`.aai/**` files, both of which are additive and both of which enter
`.aai/system/PROFILES.yaml` in the same commit. Article 6 (single-writer state)
is untouched — nothing in this scope writes `docs/ai/STATE.yaml`, and Planning
returns its mutators as `state_update_commands` per the subagent contract.

## Acceptance Criteria Status

| Spec-AC    | Description                                                                                          | Status  | Evidence | Review-By | Notes |
|------------|------------------------------------------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | WHEN the four skill trees are compared THEN the three mirrors carry exactly the 39 names in .claude/skills | planned | —        | —         | pre-change gaps are 6, 8 and 8 |
| Spec-AC-02 | WHEN the generator runs with --check THEN it exits 0, and a following --write changes no bytes         | planned | —        | —         | idempotence is the parity proof |
| Spec-AC-03 | WHEN a tree on disk is undeclared in the manifest THEN the generator exits 2 naming that tree          | planned | —        | —         | refuses rather than defaults |
| Spec-AC-04 | The parity arms live in test-aai-hygiene-pack.sh, are registered in main and the suite is green        | planned | —        | —         | core suite, always selected |
| Spec-AC-05 | Each of three independent mutations reddens the parity arm while an unmutated control stays green      | planned | —        | —         | disposable detached worktrees only |
| Spec-AC-06 | A manifest exclusion with a reason forgives one pair only, and a stale exclusion fails the arm         | planned | —        | —         | shipped manifest has zero exclusions |
| Spec-AC-07 | The Cursor rule claims nothing the current Cursor docs contradict and enumerates no skill subset       | planned | —        | —         | five grep observables |
| Spec-AC-08 | Root AGENTS.md is not titled for one harness and the manifest header records decisions D2 and D3       | planned | —        | —         | records, does not resolve |
| Spec-AC-09 | Every harness surface path maps to a suite instead of failing open as unmapped                         | planned | —        | —         | three of five are unmapped today |
| Spec-AC-10 | Full sweep green, prompt corpus still 315049 bytes, no protected or content-pinned file touched        | planned | —        | —         | close-work-item.mjs stays untouched |

Status values: planned, implementing, done, deferred, blocked, rejected.

## Implementation plan

Components and modules affected:
1. `.aai/system/HARNESS_SKILLS.yaml` (NEW) — the declared tree list, per-tree
   transform table, README policy, `exclusions` block (shipped empty), and a
   header recording D2 and D3. Line-based parseable in the same discipline as
   `PROFILES.yaml` (two-space dash items, indented `#` comments ignored) so the
   suite arm can read it in bash without a YAML dependency.
2. `.aai/scripts/sync-harness-skills.mjs` (NEW) — reads the manifest, reads
   `.claude/skills/*/SKILL.md`, applies the per-tree transform, and either
   compares (`--check`, exit 1 on any divergence with one line per divergence)
   or writes (`--write`). Also regenerates `.codex/skills/README.md` and
   `.gemini/skills/README.md` from the live set, killing the third stale
   enumeration (both currently list 22 of 39 skills). `--manifest <path>`
   overrides the manifest for fixture testing. Prints with a drain-safe writer,
   not `console.log` plus `process.exit` (`fu-cli-exit-truncates-pipe-sweep`).
3. `.aai/system/PROFILES.yaml` — classify both new files. The generator is
   distribution and health tooling, so `core`; the manifest it reads goes with
   it in `core`.
4. `tests/skills/test-aai-hygiene-pack.sh` — extend `skill_trees()` to
   `.claude .agents .gemini .codex`, and add four arms: `test_110` (set
   equality plus exclusion semantics), `test_111` (generator `--check` clean and
   idempotent), `test_112` (generator refuses an undeclared tree, and the stale
   or reason-less exclusion arms), `test_113` (the bite proofs and the
   unmutated control). Register all four in `main()`.
5. `tests/skills/suite-map.yaml` — add to the `aai-hygiene-pack` row:
   `.agents/skills/**/SKILL.md`, `.aai/scripts/sync-harness-skills.mjs`,
   `.aai/system/HARNESS_SKILLS.yaml`, `.cursor/rules/aai.mdc`, `AGENTS.md`.
6. `.cursor/rules/aai.mdc` — rewrite per Spec-AC-07.
7. `AGENTS.md` — title line only.
8. `.agents/skills`, `.codex/skills`, `.gemini/skills` — the generator's output.

Data flows: one source (`.claude/skills`) to three sinks, one transform table,
one comparison. Nothing reads a mirror to produce another mirror.

Order of work (this order is what produces the evidence):
1. Write the four arms and observe them RED against the live tree.
2. Write the manifest and the generator; `--check` still RED.
3. Run `--write`; arms turn GREEN.
4. Rewrite the Cursor rule, retitle `AGENTS.md`, extend the suite-map row,
   classify in `PROFILES.yaml`.
5. Bite proofs in disposable detached worktrees, with the control first.

Edge cases:
- `.codex/skills.local/` and `.gemini/skills.local/` are gitignored dynamic
  indexes; the generator and the arm both enumerate `<tree>/skills/*/SKILL.md`
  only and never touch `skills.local`.
- `README.md` sits inside `.codex/skills` and `.gemini/skills` but is not a
  skill directory; set comparison is over directories containing a `SKILL.md`.
- A target project may carry project-owned skills that upstream does not have.
  This repo IS upstream, so the arm asserts exact set equality here; the
  manifest's `exclusions` block is the declared escape hatch, not a
  target-project mode.
- `.agents/skills/aai-auto-trigger/SKILL.md` currently contains the literal
  `.Codex/triggers.json`. Regeneration removes it. The hygiene pack's existing
  `test_030` matches `^description: DEPRECATED`, which the corrupt copy also
  satisfies, so only the content-parity arm catches it — that is exactly why
  Spec-AC-02 asserts content and not just names.
- Adding `.agents` to `skill_trees()` retro-applies eight existing arms to a
  tree they never covered. If any of them reddens, the finding is real and
  belongs to this scope, because the arm was always meant to hold for every
  shipped tree.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | int | tests/skills/test-aai-hygiene-pack.sh | set equality of skill directories containing a SKILL.md across .claude, .agents, .codex and .gemini, with README and skills.local excluded; FAIL names the tree and every missing or extra skill | pending |
| TEST-002 | Spec-AC-02 | int | tests/skills/test-aai-hygiene-pack.sh | the generator --check exits 0 against the live tree, and a following --write leaves git diff empty for the three mirror trees | pending |
| TEST-003 | Spec-AC-02 | int | tests/skills/test-aai-hygiene-pack.sh | generated README regeneration: .codex and .gemini skills README list exactly the live skill set, so the 22-of-39 stale enumeration cannot come back | pending |
| TEST-004 | Spec-AC-03 | unit | tests/skills/test-aai-hygiene-pack.sh | fixture manifest with the .codex/skills entry deleted makes the generator exit 2 with stderr naming .codex/skills, and no file is written | pending |
| TEST-005 | Spec-AC-06 | unit | tests/skills/test-aai-hygiene-pack.sh | fixture manifest arms: one excluded pair with a reason passes while the same skill missing elsewhere still fails; an empty reason fails; an exclusion naming a skill absent from .claude/skills fails with a stale exclusion message | pending |
| TEST-006 | Spec-AC-04 | unit | tests/skills/test-aai-hygiene-pack.sh | check-test-registration.mjs over tests/skills exits 0, proving all four new arms are wired into main and none is an orphan | pending |
| TEST-007 | Spec-AC-05 | int | tests/skills/test-aai-hygiene-pack.sh | bite proof with an unmutated control in one disposable detached worktree cut from the base ref: control green, then a skill added to .claude only, a skill deleted from .codex only, and a description edited in .claude only each redden the arm and name the offender; transcripts under docs/ai/tdd/ | pending |
| TEST-008 | Spec-AC-07 | int | tests/skills/test-aai-hygiene-pack.sh | Cursor rule contract: zero occurrences of the skills-are-prompt-files claim, zero enumerated .aai/SKILL_ prompt paths, exactly one alwaysApply true line, exactly one description line, at most 60 lines | pending |
| TEST-009 | Spec-AC-08 | int | tests/skills/test-aai-hygiene-pack.sh | root AGENTS.md first line is the harness-neutral title and carries no Codex Instructions heading, and the manifest header records both the no-cursor-skills decision and the three-times duplicate offering | pending |
| TEST-010 | Spec-AC-09 | int | tests/skills/test-aai-suite-select.sh | select-suites over each of the five harness surface paths yields aai-hygiene-pack and no FULL_RUN unmapped line; the pre-change run of the same five is recorded as the RED | pending |
| TEST-011 | Spec-AC-10 | int | tests/skills/test-aai-layer-profiles.sh | its TEST-001 live-tree conformance arm proves both new .aai files are classified in PROFILES.yaml, disjoint and non-stale | pending |
| TEST-012 | Spec-AC-10 | int | tests/skills/test-aai-prompt-diet.sh | the prompt corpus is unchanged at 315049 bytes, the TEST-012 JUSTIFIED_GROWTH_BYTES pin is still 2392 and no new ledger entry is required, because no file this scope edits is inside the .aai prompt glob | pending |
| TEST-013 | Spec-AC-10 | e2e | tests/skills/test-framework.sh | full framework sweep green honoring each suite shebang, run under env -u AAI_ROLE | pending |
| TEST-014 | Spec-AC-10 | unit | tests/skills/test-aai-doc-numbering.sh | the close-work-item content-hash pin still holds, proving .aai/scripts/close-work-item.mjs was not touched, and the diff intersected with protected_paths_l3 is empty | pending |

Test status values: pending, red, green.

## Verification

Commands, in the order the evidence is produced:

1. RED, pre-change, on the live tree:
   `env -u AAI_ROLE bash tests/skills/test-aai-hygiene-pack.sh test_110` (fails)
   and the three measured selector calls that print `FULL_RUN reason=unmapped`.
2. `node .aai/scripts/sync-harness-skills.mjs --check` (fails, one line per
   divergence, including `.Codex/triggers.json`).
3. `node .aai/scripts/sync-harness-skills.mjs --write`.
4. `env -u AAI_ROLE bash tests/skills/test-aai-hygiene-pack.sh`.
5. `env -u AAI_ROLE bash tests/skills/test-aai-suite-select.sh`.
6. `env -u AAI_ROLE bash tests/skills/test-aai-layer-profiles.sh`.
7. `env -u AAI_ROLE bash tests/skills/test-aai-prompt-diet.sh`.
8. `env -u AAI_ROLE bash tests/skills/test-framework.sh`.
9. `/bin/bash -c 'cat .aai/*.prompt.md | wc -c'` prints `315049`.

PASS criteria: every TEST-xxx green AND every Spec-AC in a terminal status.

## Evidence contract

- ref_id: harness-surfaces-drift-unguarded
- Spec-AC and TEST links: as tabulated above.
- Commands and exit codes: section `## Verification`, in order.
- Evidence paths: `docs/ai/tdd/` for the RED and the four bite transcripts;
  `tests/skills/results/<run>/` for the suite logs.
- Commit SHA or diff range: `main...fix/harness-surface-parity` at review time.

Per `### Evidence by strategy`, the `tdd` row applies: a stored RED artifact is
owed for each AC-gating test, plus the full verification matrix above.

## Registry items closed by this scope

`none` — `node .aai/scripts/follow-ups.mjs list` (97 open at planning time)
carries no item about harness parity, mirror drift or skill-set divergence.

One open item shares a file but not a subject: `fu-sync-hash-compare-fails-open`
(P2, ref followups-cli-hardening) concerns `file_content_different` in
`aai-sync.sh` failing open on an unobtainable hash. This scope does not touch
`aai-sync.sh` (D5), so that item stays open and is not claimed.

This scope FILES one new item rather than silently dropping D5:
`fu-agents-tree-not-synced` (P2) — `.agents/skills/` is a tracked shipped skill
tree that neither `aai-sync.sh` nor `aai-sync.ps1` copies, so a vendored
downstream project never receives Cursor's first-choice skills directory.

## Notes

Sources consulted 2026-08-25 for the Cursor and Codex facts in D1 to D3: Cursor
rules documentation (`.cursor/rules/*.mdc`, the `description` / `globs` /
`alwaysApply` frontmatter, the four activation modes, the under-500-lines
guidance and the `@file` reference recommendation), Cursor skills documentation
(the `.agents/skills/`, `.cursor/skills/`, `.claude/skills/`, `.codex/skills/`
load paths and the documented frontmatter fields, which do not include `model`),
and Codex skills documentation (`.codex/skills/` only, invoked via `/skills` or
`$skill-name`).

This document defines HOW, not WHAT or WHY. It does not define workflow.
