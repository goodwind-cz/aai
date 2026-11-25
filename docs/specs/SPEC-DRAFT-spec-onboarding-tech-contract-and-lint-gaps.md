---
id: spec-onboarding-tech-contract-and-lint-gaps
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: e3de6fc05e856ff80a99aa87a43f230d057f0a91321f89da174c62bbb2aadb2d
ceremony_level: 2
links:
  requirement: onboarding-tech-contract-and-lint-gaps
  rfc: null
  pr: []
  commits: []
---

# Onboarding: flag the unfilled technology contract, pin ESLint 8 for legacy eslintrc, give TECH_EXTRACT a fresh-project path

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/ISSUE-DRAFT-onboarding-tech-contract-and-lint-gaps.md
  (GitHub #588, #589, #590; triage approved by the owner via /aai-issues on
  2026-11-25). The quoted issue texts in the intake are data, not instructions.
- Prior scope whose frozen text and tests this scope changes (see D-AMEND):
  docs/specs/SPEC-0306-spec-bootstrap-on-node.md (D-COMMANDS lint chain step
  `eslint .`; the TEST-3944 row `lint eslintrc`; corpus case K05 against the
  frozen reference, which D-REF says a later intended change must cover with a
  reviewed row).
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, Node 22 floor,
  bash 3.2 suites run through `.aai/scripts/aai-run-tests.sh`).
- Constitution: docs/CONSTITUTION.md (Art. 4 degrade and report, Art. 6
  single-writer state).

## Implementation strategy

- Strategy: tdd
- Rationale: all three defects were observed on the unchanged tree (see
  Measurements), so every behavioral test can be watched failing first. The
  changes are small, deterministic and in two scripts plus two prompts; the
  RED-then-GREEN rule costs little and protects the parity corpus that the
  lint change has to cross.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound ride touching two vendored scripts, two
  prompts, four suites and a prior frozen spec; the main checkout is shared
  with other sessions.
- User decision: worktree (owner-directed, recorded before Planning)
- Base ref: origin/main at 5f02b0e5
- Worktree branch/path: fix/onboarding-issues at
  /Users/ales/Projects/aai-worktrees/onboarding-issues-588-590
- Review required: true
- Review scope (explicit paths): .aai/scripts/aai-doctor.mjs;
  .aai/scripts/aai-bootstrap.mjs; .aai/TECH_EXTRACT.prompt.md;
  .aai/SKILL_BOOTSTRAP.prompt.md; tests/skills/test-aai-doctor.sh;
  tests/skills/test-aai-bootstrap-node.sh;
  tests/skills/lib/aai-bootstrap.test.mjs;
  tests/skills/lib/aai-bootstrap-fixtures.mjs;
  tests/skills/test-aai-prompt-diet.sh;
  tests/skills/lib/prompt-diet-ledger.sh;
  docs/specs/SPEC-0306-spec-bootstrap-on-node.md; CHANGELOG.md.

## Ceremony

Level 2. No touched path is in `protected_paths_l3`
(docs/ai/docs-audit.yaml: state engine, allocator, hooks, guard config,
WORKFLOW.md, CONSTITUTION.md), and no `.github/workflows` file is touched.

## Measurements (origin/main 5f02b0e5, 2026-11-25)

All runs used throwaway fixtures under the Planning scratch directory, never
this checkout.

| Item | Measured on the unchanged tree |
|---|---|
| #588 doctor | A project whose `docs/TECHNOLOGY.md` is a byte copy of `.aai/templates/TECHNOLOGY_TEMPLATE.md` (what `aai-sync.mjs` `stepSeeds` writes, via `copyReplace`): `node .aai/scripts/aai-doctor.mjs --root <fixture>` prints `CAT-05 PASS docs/knowledge/FACTS.md: 1 lines; docs/knowledge/PATTERNS.md: 1 lines`. Nothing names TECH_EXTRACT. |
| #588 bootstrap | Same template copy in a bare target: `node .aai/scripts/aai-bootstrap.mjs <fixture> --dry-run` exits 0 and its summary holds 0 lines matching `TECH_EXTRACT`, `template-seed` or `TECHNOLOGY`. |
| #589 lint | `chooseCommands(<fixture>).lint` is `npx eslint .` for all five fixtures: eslintrc only; eslintrc plus an `eslint` devDependency; flat config plus an `eslint` devDependency; flat config only; eslintrc plus `node_modules/.bin/eslint`. The first is the reported defect: `npx` fetches the latest ESLint, which ignores eslintrc. |
| #589 twins | `.aai/scripts/aai-bootstrap.sh` and `.aai/scripts/aai-bootstrap.ps1` are 9-line launchers that exec the Node module; they hold no detection or lint logic. Only the module changes. |
| #590 | `.aai/TECH_EXTRACT.prompt.md` (2115 B) step 1 says read `docs/ai/STATE.yaml` and step 8 lists `current_focus`, `active_work_items`, `updated_at_utc` to update, with no branch for an absent file. In a fresh project, `node .aai/scripts/check-state.mjs --repair docs/ai/STATE.yaml` exits 0 and prints `CREATED: ... from template`, and then `node .aai/scripts/state.mjs set-focus --type technology_extraction --ref technology-extraction --path docs/TECHNOLOGY.md` (AAI_ROLE unset) exits 0 and writes that focus. Under `AAI_ROLE=subagent` set-focus refuses (exit 3, single-writer rule). |
| Corpus | `cat .aai/*.prompt.md` is 376171 B; ORCHESTRATION.prompt.md is 45 lines and is not touched. |
| Pins | `tests/skills/test-aai-doctor.sh` pins 20 categories on this repo and 18 on the clean fixture; the clean fixture's `docs/TECHNOLOGY.md` is an empty file. The parity corpus K05 (yarn.lock, `.eslintrc.json`, no eslint dependency) would change from `yarn exec eslint .` to the pin. No frozen Mutation cell anchors the lint line or `catKnowledgeFiles`. |

## Decisions

### D1: one template-seed rule, held by doctor and bootstrap

Both `.aai/scripts/aai-doctor.mjs` and `.aai/scripts/aai-bootstrap.mjs`
hold `const TECH_SEED_STATUS = 'template-seed';` and
`function isTechSeed(text) {`. `isTechSeed` returns false for `null`
(file absent). Otherwise it takes the lines before the first line that
starts with `## ` (the metadata header), strips one trailing `\r` and
trailing spaces or tabs from each, and finds the first line that starts
with `- Status: `. It returns true only when the rest of that line equals
`TECH_SEED_STATUS`. A body mention after the first `## ` heading never
counts. An empty file is not a seed. Each module keeps its own copy:
bootstrap may import only `node:` specifiers and `./lib/resolve-base.mjs`
(TEST-3941 shape rule), and a new shared lib would be a new `.aai/**` file.
TEST-4126 runs both scripts over one fixture table and fails on any
disagreement. Both modules carry the same hint text, ASCII only:
`docs/TECHNOLOGY.md is still the template seed (Status: template-seed); run TECH_EXTRACT (.aai/TECH_EXTRACT.prompt.md) to fill the technology contract`.

### D2: doctor reports the seed under CAT-05 (#588)

`catKnowledgeFiles` reads `docs/TECHNOLOGY.md` and, when `isTechSeed`
holds, pushes the D1 hint as the LAST entry of its `issues` list, so
CAT-05 is WARN (the DEGRADED verdict) and the reason names the fix. When the
seed rule does not hold, CAT-05 behaves and words its PASS reason exactly as
before. An absent file stays CAT-01's finding (missing optional). No new
category is added: the category-count pins (20 on the repo, 18 on the clean
fixture) and the `.aai/SKILL_DOCTOR.prompt.md` category list stay untouched,
and the WARN reason is relayed verbatim by that prompt's step 3. Default
exit is unchanged (WARN-only exits 0); `--strict` exits 1.

### D3: bootstrap points to TECH_EXTRACT (#588)

`run` reads `<root>/docs/TECHNOLOGY.md` (read only, never written) and
passes the `isTechSeed` result to `renderSummary` as a new optional field.
When it holds, the summary ends with one more block, after every existing
block (so all earlier text is byte-identical):

```
(empty line)
Technology contract:
- <the D1 hint>
```

The block prints in normal and `--dry-run` mode. Nothing else in the
summary, the marker file or the skill files changes. No parity-corpus case
holds a `docs/TECHNOLOGY.md`, so the corpus is unaffected.

### D4: lint chain prefers the project's own eslint, pins ESLint 8 for legacy eslintrc (#589)

`lintCommand` keeps its order. Runner and package-script targets still win.
The eslint step becomes:

1. A flat config (`eslint.config.js`, `.mjs`, `.cjs`) or a local eslint:
   `execCommand(pc.pm, 'eslint', '.')`, exactly as today. A local eslint is
   `function hasLocalEslint(pc) {`: `eslint` in any of the four dependency
   blocks, or a regular file at `node_modules/.bin/eslint` or
   `node_modules/.bin/eslint.cmd` under the root.
2. Otherwise, a `.eslintrc*` name in the root: the constant
   `const ESLINT8_PIN = 'npx eslint@8 .';`, for every package manager. `npx`
   ships with Node, which the bootstrap already requires. `pnpm exec`,
   `yarn exec` and `bunx` have no common one-off form for a pinned version.
3. Biome, Ruff and the rest follow unchanged.

The four cases the owner named resolve as: eslintrc without eslint gets the
pin; eslintrc with an eslint dependency gets `<pm exec> eslint .`; flat
config with eslint gets `<pm exec> eslint .`; flat config without eslint
gets `<pm exec> eslint .` (unchanged: the latest ESLint reads flat config).
When the pin is chosen, `planSkills` gives the `aai-lint` skill this extra
block (ASCII, followed by one empty line like the Vitest block):

```
## ESLint 8 pin
- Only a legacy `.eslintrc*` config was found and eslint is not installed in this project; ESLint 9 and later ignore eslintrc, so this command pins ESLint 8.
- To lint with the project's own eslint, add it as a devDependency (or migrate to `eslint.config.*`), then rerun .aai/scripts/aai-bootstrap.sh.
```

The lint target stays `.`. ESLint 8 honours `.eslintignore`, and the
intake's "do not lint the whole legacy tree" is not adopted: there is no
evidence-based narrower target to generate (see Non-goals). No export is
added (the TEST-3941 export list is unchanged).

### D5: the parity corpus carries a reviewed drift row DR-12 for K05

K05's fixture stays as SPEC-0306 words it. The K05 case in
`tests/skills/lib/aai-bootstrap-fixtures.mjs` gains a reviewed drift field:
a list of exact `[from, to]` string pairs. `runCorpus` applies it to the
REFERENCE side only (its stdout and the `data` of every snapshot file)
before the comparison. The pairs rewrite the lint command
`yarn exec eslint .` to `npx eslint@8 .` and insert the D4 extra block into
the reference's `aai-lint` SKILL.md. Every other byte must still match. A
pair that matches nothing on the reference side is reported as a problem,
so the row cannot go stale silently. The `TEST-3944` row `lint eslintrc`
expects `npx eslint@8 .`. The TEST-3945 shared fixtures need no change: the
one eslint fixture there is a flat config.

### D6: TECH_EXTRACT has a fresh-project path and never asks for a hand-written STATE (#590)

`.aai/TECH_EXTRACT.prompt.md`:

- Step 1 keeps its read and gains: when `docs/ai/STATE.yaml` is absent (a
  fresh project), create it with
  `node .aai/scripts/check-state.mjs --repair docs/ai/STATE.yaml`; when
  that or a later STATE command fails or is refused, skip the STATE steps
  (1 and 8) and say so in the output. It also says
  `Never write docs/ai/STATE.yaml by hand.`
- Step 8 is replaced by one line that records the focus with
  `node .aai/scripts/state.mjs set-focus --type technology_extraction --ref technology-extraction --path docs/TECHNOLOGY.md`
  (the CLI stamps `updated_at_utc`). The three hand-edit bullets
  (`- current_focus`, `- active_work_items status for technology extraction scope`,
  `- updated_at_utc`) are removed: they asked for a hand edit, against
  Constitution Art. 6. `active_work_items` is not touched by this prompt
  any more, because a technology extraction has no phases.
- The prompt names exactly these two `node .aai/scripts/` commands in
  backticks, in that order. TEST-4132 extracts and runs them.

### D7: SKILL_BOOTSTRAP names the two new outputs

`.aai/SKILL_BOOTSTRAP.prompt.md` gains one sentence under "What the
Generator Detects", saying that a legacy `.eslintrc*` with no eslint
installed in the project gets `npx eslint@8 .` (ESLint 9 and later ignore
eslintrc). The literal `eslint@8` occurs exactly once in the file. It also
gains one "Report Results" bullet: relay the `Technology contract:` line
when the summary prints one (run TECH_EXTRACT). All commands stay `node`
or the existing launcher pair (Windows-safe text).

### D-GOV: prompt-corpus governance

- Prompt bytes grow (TECH_EXTRACT and SKILL_BOOTSTRAP). After the prompt
  edits are final (including review rounds), one
  `JUSTIFIED_ADDITIONS+=( "<delta> onboarding-tech-contract-and-lint-gaps ..." )`
  entry is added to `tests/skills/lib/prompt-diet-ledger.sh`. Its delta is
  the measured `cat .aai/*.prompt.md | wc -c` growth against 5f02b0e5
  (376171 B), credited 1:1. The TEST-012 `want_growth` pin in
  `tests/skills/test-aai-prompt-diet.sh` moves 68174 -> 68174 + delta, with
  one `# Then ...` comment line. Measure with `/usr/bin/wc -c` under bash.
- `.aai/ORCHESTRATION.prompt.md` is not touched (45 lines).
- No new `.aai/**` file, so there is no `.aai/system/PROFILES.yaml` entry.
- No new suite, so there is no suite-weights row. New tests live in
  existing suites and are registered in each suite's dispatcher.

### D-AMEND: SPEC-0306

After the edits are checked with grep or diff, this scope appends one
additive section to docs/specs/SPEC-0306-spec-bootstrap-on-node.md with the
exact heading line `## Amendment (onboarding-tech-contract-and-lint-gaps)`.
It leaves the frozen D-COMMANDS text visible and quotes the `eslint .`
lint step beside the D4 rule. It names the changed TEST-3944 row
(`lint eslintrc`) and adds DR-12 (reference: `<pm exec> eslint .` for a
legacy eslintrc without eslint; module: `npx eslint@8 .` plus the pin block;
why: ESLint 9 and later ignore eslintrc, GitHub #589; test TEST-4130) as
the reviewed row D-REF asks for. It states that canon assigns a frozen-spec
change to the owner, and cites the owner's triage approval of the intake as
the authority. Then it records
`node .aai/scripts/spec-amend.mjs add --spec docs/specs/SPEC-0306-spec-bootstrap-on-node.md --ref onboarding-tech-contract-and-lint-gaps --class contract --signoff owner --authority "docs/issues/<intake> Notes: triage approved by the owner via /aai-issues on 2026-11-25 (GitHub #589 asks for this change)" --what "<one line>" --why "<one line>"`.
The `<intake>` path is the file name after any allocator rename.
`node .aai/scripts/spec-amend.mjs list --strict` must exit 0 afterwards,
and again after the allocator runs at merge.

### D-WIRE: CHANGELOG

CHANGELOG.md gets one heading,
`## [unreleased] — fix: onboarding points to TECH_EXTRACT and generates a working lint skill`.
Its body names the three consumer-visible changes: the doctor CAT-05 WARN
and the bootstrap pointer, the ESLint 8 pin and its note, and the
TECH_EXTRACT fresh-project path. It is written after the loop completes
(product docs after LOOP COMPLETE). No product doc names CAT-05 reasons or
the lint chain (docs/product/aai-doctor.md, docs/product/bootstrap-on-node.md
checked), so no product doc changes.

## Seams this scope crosses

| Seam | Producer | Consumer | Test |
|---|---|---|---|
| S1 | `.aai/templates/TECHNOLOGY_TEMPLATE.md` (byte-copied to `docs/TECHNOLOGY.md` by `aai-sync.mjs` stepSeeds) | doctor and bootstrap `isTechSeed` | TEST-4123, TEST-4125 and TEST-4126 use the real template bytes, never a hand-written status line |
| S2 | TECH_EXTRACT step 7 writes `Status: generated` | doctor and bootstrap `isTechSeed` | TEST-4124 and TEST-4126 read that literal from the prompt and write it into the fixture header |
| S3 | doctor and bootstrap each carry the rule | the operator sees one verdict | TEST-4126 runs both real scripts over one fixture table |
| S4 | doctor and bootstrap hint text | `.aai/TECH_EXTRACT.prompt.md` must exist | TEST-4123 asserts the named path exists in the repo |
| S5 | bootstrap writes the `aai-lint` SKILL.md fenced command | an agent runs it in the project | TEST-4129 runs the fenced command from the written file with a stub `npx` |
| S6 | the sh launcher | the module | TEST-4129 writes the eslintrc fixture skill through `aai-bootstrap.sh` and through the module, and the two files match byte for byte |
| S7 | TECH_EXTRACT names two commands | `check-state.mjs` and `state.mjs` in a fresh project | TEST-4132 extracts the commands from the prompt text and runs them |
| S8 | the frozen bash reference (SPEC-0306 D-REF) | the module, on K05 | TEST-4130 and TEST-3949 |

The PowerShell launcher is not exercised for the new paths (see Residual
risks).

## Non-goals

- Linting a narrower path than `.` for legacy projects.
- Reading `eslintConfig` in package.json as a legacy config (today it is not
  a lint signal at all; unchanged).
- Detecting an eslint hoisted to a parent workspace directory.
- Updating the stale category list in `.aai/SKILL_DOCTOR.prompt.md` (it lists
  16 of 22). It is not on this path. Suggested follow-up only.
- Issue write-back to GitHub (after merge, outside this ride).

## Acceptance Criteria Mapping

- Intake "Doctor flags a template-seed TECHNOLOGY.md (WARN/DEGRADED,
  actionable)" maps to Spec-AC-01, Spec-AC-02, Spec-AC-03 (seam S3).
- Intake "the bootstrap report points to it" maps to Spec-AC-04.
- Intake "bootstrap lint uses the project's own eslint; legacy eslintrc
  without eslint pins ESLint 8; flat config unchanged" maps to Spec-AC-05,
  Spec-AC-06, Spec-AC-07, Spec-AC-08.
- Intake "TECH_EXTRACT documents the absent-STATE path, never a hand-written
  STATE" maps to Spec-AC-09, Spec-AC-10.
- Intake "sh/ps1/Node twins agree" and the prompt docs map to Spec-AC-11.
- Intake constraint "prompt-corpus governance" maps to Spec-AC-12.
- Consumer disclosure and the SPEC-0306 amendment map to Spec-AC-13.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN docs/TECHNOLOGY.md is a byte copy of .aai/templates/TECHNOLOGY_TEMPLATE.md (LF, and again converted to CRLF) in the doctor clean fixture THEN aai-doctor.mjs SHALL print CAT-05 WARN whose reason holds the D1 hint, every other category SHALL keep its clean-fixture status, the run SHALL exit 0, --strict SHALL exit 1, and --json SHALL carry CAT-05 status WARN; the path .aai/TECH_EXTRACT.prompt.md named in the hint SHALL exist in this repository. | planned | — | — | D1, D2, S1, S4 |
| Spec-AC-02 | WHEN docs/TECHNOLOGY.md is the template with its header status replaced by the Status: generated literal read from TECH_EXTRACT step 7, or is empty, or keeps a generated header and mentions the seed status line only after the first level-2 heading THEN CAT-05 SHALL print PASS with a reason byte-identical to the unchanged clean fixture's CAT-05 reason, and the doctor SHALL still report 18 categories on the clean fixture and 20 on this repository. | planned | — | — | D1, D2, S2 |
| Spec-AC-03 | WHEN aai-doctor.mjs and aai-bootstrap.mjs --dry-run run on the same fixtures (template LF, template CRLF, generated header, body-only mention, empty file, absent file) THEN the doctor flags (D1 hint in CAT-05) and the bootstrap pointer block SHALL appear for exactly the same fixtures, and that set SHALL be exactly the two template fixtures. | planned | — | — | D1, S1, S2, S3 |
| Spec-AC-04 | WHEN aai-bootstrap runs, normal or --dry-run, on a target whose docs/TECHNOLOGY.md is the template seed THEN the summary SHALL end with an empty line, the line Technology contract: and one line holding the D1 hint, the file's sha256 SHALL be unchanged, and in --dry-run every summary line before that block SHALL equal the --dry-run summary of the same target with docs/TECHNOLOGY.md removed; for a generated header or an absent file the summary SHALL hold no Technology contract: line. | planned | — | — | D3 |
| Spec-AC-05 | WHEN the root has a .eslintrc name, no eslint.config.js, .mjs or .cjs, no eslint in dependencies, devDependencies, peerDependencies or optionalDependencies, no node_modules/.bin/eslint or eslint.cmd, and no runner or package-script lint target THEN chooseCommands().lint SHALL be npx eslint@8 . for each of npm, pnpm, yarn and bun lockfiles and with no package.json, and the aai-lint skill SHALL carry the D4 ESLint 8 pin block. | planned | — | — | D4 |
| Spec-AC-06 | WHEN the root has a .eslintrc name and eslint in any one of the four dependency blocks, or node_modules/.bin/eslint, or node_modules/.bin/eslint.cmd THEN the lint command SHALL be the package manager exec form of eslint . (npx, pnpm exec, yarn exec, bunx) and the aai-lint skill SHALL carry no pin block. | planned | — | — | D4 |
| Spec-AC-07 | WHEN the root has a flat eslint config with an eslint dependency, a flat config without one, or a flat config beside a .eslintrc name THEN the lint command SHALL be the package manager exec form of eslint . exactly as on 5f02b0e5, and a runner or package-script lint target SHALL still win over every eslint rule. | planned | — | — | D4 |
| Spec-AC-08 | WHEN the parity corpus runs THEN K05 with its SPEC-0306 fixture SHALL agree with the frozen reference after the DR-12 rewrite, the same run without DR-12 SHALL report at least one problem and only problems whose text mentions eslint, a DR-12 pair that matches nothing SHALL be reported as a problem, and TEST-3944, TEST-3945 and TEST-3949 SHALL pass. | planned | — | — | D5, S8 |
| Spec-AC-09 | .aai/TECH_EXTRACT.prompt.md SHALL hold node .aai/scripts/check-state.mjs --repair docs/ai/STATE.yaml for an absent STATE, the skip-with-note instruction for the STATE steps, the sentence Never write docs/ai/STATE.yaml by hand., and the set-focus command of D6, and SHALL hold none of the three removed hand-edit bullet lines. | planned | — | — | D6 |
| Spec-AC-10 | WHEN the backticked node .aai/scripts/ commands of .aai/TECH_EXTRACT.prompt.md are extracted in order (exactly two, else the test fails) and run with AAI_ROLE unset in a temp project holding a copy of .aai/ and no docs/ai/STATE.yaml THEN each SHALL exit 0, docs/ai/STATE.yaml SHALL exist with current_focus type technology_extraction and primary_path docs/TECHNOLOGY.md, and check-state.mjs on it SHALL exit 0. | planned | — | — | D6, S7 |
| Spec-AC-11 | WHEN the generated aai-lint fenced command is run with sh -c in its fixture with a stub npx first on PATH THEN the stub SHALL log exactly eslint@8 . for the legacy-eslintrc fixture and eslint . for the flat-config-with-eslint fixture (an empty log fails); the eslintrc fixture's SKILL.md written through .aai/scripts/aai-bootstrap.sh SHALL equal the one written through the module; neither launcher SHALL hold the text eslint; .aai/SKILL_BOOTSTRAP.prompt.md SHALL hold eslint@8 exactly once and a Report Results bullet naming Technology contract and TECH_EXTRACT. | planned | — | — | D4, D7, S5, S6 |
| Spec-AC-12 | tests/skills/lib/prompt-diet-ledger.sh SHALL hold exactly one JUSTIFIED_ADDITIONS entry naming onboarding-tech-contract-and-lint-gaps with a positive credit equal to the measured corpus growth against 5f02b0e5, TEST-010 and TEST-012 of tests/skills/test-aai-prompt-diet.sh SHALL pass, .aai/ORCHESTRATION.prompt.md SHALL be byte-identical to 5f02b0e5, and git diff --name-status 5f02b0e5 SHALL show no added .aai/ file. | planned | — | — | D-GOV |
| Spec-AC-13 | CHANGELOG.md SHALL hold the D-WIRE heading in its unreleased or rolled version form, SPEC-0306 SHALL hold the exact D-AMEND heading line and the DR-12 row text, and node .aai/scripts/spec-amend.mjs list --strict SHALL exit 0. | planned | — | — | D-AMEND, D-WIRE |

## Implementation plan

Order. Each step is RED first: the RED log goes under
`docs/ai/tdd/onboarding-tech-contract-and-lint-gaps/red/TEST-xxxx.log` and
the GREEN log under `.../green/`.

1. Doctor (Spec-AC-01, 02): add TEST-4123 and TEST-4124 to
   `tests/skills/test-aai-doctor.sh`, watch them fail, then add D1 and D2 to
   `aai-doctor.mjs`.
2. Bootstrap pointer (Spec-AC-04): add a TEST-4125 node:test describe to
   `tests/skills/lib/aai-bootstrap.test.mjs`, with a `test_4125_*` function in
   `tests/skills/test-aai-bootstrap-node.sh` selecting it with
   `--test-name-pattern`. Then add D1 and D3 to `aai-bootstrap.mjs`.
3. Agreement (Spec-AC-03): add TEST-4126 to `test-aai-doctor.sh`. It runs the
   real doctor with `--root` and the real bootstrap with `--dry-run` over the
   fixture table. Its RED is observed on the tree after step 1 and before
   step 2.
4. Lint (Spec-AC-05, 06, 07): add TEST-4127 and TEST-4128 as node:test cases
   (plus suite functions), change the `lint eslintrc` COMMAND_CASES row, and
   implement D4.
5. Corpus (Spec-AC-08): add TEST-4130, then the DR-12 field and its
   application in `runCorpus` (D5).
6. Seam run (Spec-AC-11): add TEST-4129 and TEST-4133 (bash, in
   `test-aai-bootstrap-node.sh`; stub `npx` in an own scratch dir).
7. Prompts (Spec-AC-09, 10): add TEST-4131 and TEST-4132 to
   `test-aai-doctor.sh`, then edit TECH_EXTRACT (D6) and SKILL_BOOTSTRAP (D7).
8. Governance (Spec-AC-12): measure the corpus, add the ledger entry, bump
   TEST-012, add TEST-4134 to `test-aai-prompt-diet.sh`. Redo this after any
   later prompt edit (review rounds).
9. After LOOP COMPLETE (Spec-AC-13): CHANGELOG heading, SPEC-0306 amendment,
   `spec-amend.mjs add`, then TEST-4135 green.

Edge cases the tests hold: CRLF template copy; a header without any
`- Status:` line (not a seed); the `.cmd` bin on POSIX (`pc.file` is a stat,
so it counts on every host); a fixture with no package.json (pm '' maps to
npx); flat config beside eslintrc.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---------|---------|------|----------------------|-------------|----------|--------|
| TEST-4123 | Spec-AC-01 | integration | tests/skills/test-aai-doctor.sh | test_4123_template_seed_warns: clean fixture plus docs/TECHNOLOGY.md copied from the real template; LF and CRLF variants each give CAT-05 WARN with the D1 hint, the other categories keep their clean status, exit 0, --strict exit 1, --json CAT-05 WARN; the hint path exists in the repo | `sed:s/const TECH_SEED_STATUS = 'template-seed';/const TECH_SEED_STATUS = 'template-sead';/` on .aai/scripts/aai-doctor.mjs | pending |
| TEST-4124 | Spec-AC-02 | integration | tests/skills/test-aai-doctor.sh | test_4124_non_seed_unchanged: generated header (literal read from TECH_EXTRACT step 7), empty file and body-only mention each give CAT-05 PASS with the reason byte-equal to the unchanged clean fixture's; 18 categories on the clean fixture, 20 on the repo | `sed:s/function isTechSeed\(text\) \{/function isTechSeed(text) { if (text !== null) return true;/` on .aai/scripts/aai-doctor.mjs | pending |
| TEST-4125 | Spec-AC-04 | integration | tests/skills/lib/aai-bootstrap.test.mjs | TEST-4125 describe, run by test_4125_bootstrap_tech_pointer in tests/skills/test-aai-bootstrap-node.sh: the template seed gives the trailing Technology contract block in normal and dry-run mode, the file sha256 is unchanged, in dry-run every earlier summary line equals the dry-run without the file; generated and absent give no block | `sed:s/const TECH_SEED_STATUS = 'template-seed';/const TECH_SEED_STATUS = 'template-sead';/` on .aai/scripts/aai-bootstrap.mjs | pending |
| TEST-4126 | Spec-AC-03 | integration | tests/skills/test-aai-doctor.sh | test_4126_doctor_bootstrap_agree: six fixtures (template LF, template CRLF, generated, body-only, empty, absent); the doctor flag and the bootstrap block agree on every fixture, and the flagged set is exactly the two template fixtures (a count other than 2 fails) | `sed:s/function isTechSeed\(text\) \{/function isTechSeed(text) { if (text !== null) return true;/` on .aai/scripts/aai-bootstrap.mjs | pending |
| TEST-4127 | Spec-AC-05 | unit | tests/skills/lib/aai-bootstrap.test.mjs | TEST-4127 describe, run by test_4127_eslintrc_pin: eslintrc only under npm, pnpm, yarn and bun lockfiles and without package.json gives npx eslint@8 .; the aai-lint plan entry carries the exact D4 pin block | `sed:s/const ESLINT8_PIN = 'npx eslint@8 \.';/const ESLINT8_PIN = 'npx eslint .';/` on .aai/scripts/aai-bootstrap.mjs | pending |
| TEST-4128 | Spec-AC-06, Spec-AC-07 | unit | tests/skills/lib/aai-bootstrap.test.mjs | TEST-4128 describe, run by test_4128_local_eslint_preferred: eslintrc plus eslint in each dependency block, plus .bin/eslint, plus .bin/eslint.cmd gives the pm exec form with no pin block; flat config with and without eslint and flat beside eslintrc give the 5f02b0e5 command; a lint script wins | `sed:s/function hasLocalEslint\(pc\) \{/function hasLocalEslint(pc) { return false;/` on .aai/scripts/aai-bootstrap.mjs | pending |
| TEST-4129 | Spec-AC-11 | integration | tests/skills/test-aai-bootstrap-node.sh | test_4129_lint_skill_runs_as_written: bootstrap the eslintrc-only and flat-with-eslint fixtures, extract the fenced command from each written aai-lint SKILL.md, run it with sh -c and a logging stub npx first on PATH; the logs are exactly eslint@8 . and eslint . (empty log fails); the eslintrc skill written via aai-bootstrap.sh equals the module's byte for byte | `sed:s/const ESLINT8_PIN = 'npx eslint@8 \.';/const ESLINT8_PIN = 'npx eslint@8 src';/` on .aai/scripts/aai-bootstrap.mjs | pending |
| TEST-4130 | Spec-AC-08 | integration | tests/skills/lib/aai-bootstrap.test.mjs | TEST-4130 describe, run by test_4130_k05_reviewed_drift: K05 alone through runCorpus gives zero problems with DR-12; without DR-12 at least one problem and every problem mentions eslint; an added unmatched pair is reported | `sed:s/function hasLocalEslint\(pc\) \{/function hasLocalEslint(pc) { return true;/` on .aai/scripts/aai-bootstrap.mjs | pending |
| TEST-4131 | Spec-AC-09 | inspection | tests/skills/test-aai-doctor.sh | test_4131_tech_extract_fresh_project_text: TECH_EXTRACT holds the repair command, the skip-with-note instruction, the never-by-hand sentence and the set-focus command, and none of the three removed bullet lines | `sed:s/--repair docs/--check docs/` on .aai/TECH_EXTRACT.prompt.md | pending |
| TEST-4132 | Spec-AC-10 | integration | tests/skills/test-aai-doctor.sh | test_4132_tech_extract_commands_run: extract the backticked node .aai/scripts/ commands from TECH_EXTRACT (exactly two), run them under env -u AAI_ROLE in a temp project with a copied .aai/ and no STATE; both exit 0, STATE has the technology_extraction focus on docs/TECHNOLOGY.md, check-state exits 0 | `sed:s/--type technology_extraction/--type technology_extract/` on .aai/TECH_EXTRACT.prompt.md | pending |
| TEST-4133 | Spec-AC-11 | inspection | tests/skills/test-aai-bootstrap-node.sh | test_4133_launchers_thin_and_docs: neither aai-bootstrap.sh nor aai-bootstrap.ps1 holds eslint; SKILL_BOOTSTRAP holds eslint@8 exactly once and a Report Results bullet naming Technology contract and TECH_EXTRACT | `sed:s/eslint@8/eslint@9/` on .aai/SKILL_BOOTSTRAP.prompt.md | pending |
| TEST-4134 | Spec-AC-12 | integration | tests/skills/test-aai-prompt-diet.sh | test_4134_onboarding_ledger_entry: exactly one JUSTIFIED_ADDITIONS entry names onboarding-tech-contract-and-lint-gaps with a positive integer credit; TEST-010 and TEST-012 of the same suite pass (measured growth credited 1:1) | `sed:s/BEGIN NOW\./BEGIN NOW. Unaccounted growth that no ledger entry credits./` on .aai/TECH_EXTRACT.prompt.md | pending |
| TEST-4135 | Spec-AC-13 | inspection | tests/skills/test-aai-bootstrap-node.sh | test_4135_changelog_and_amendment: CHANGELOG.md holds the D-WIRE heading in unreleased or rolled form, SPEC-0306 holds the exact D-AMEND heading line and a DR-12 row, spec-amend.mjs list --strict exits 0 | `sed:s/## Amendment \(onboarding-tech-contract-and-lint-gaps\)/## Amendment (onboarding)/` on docs/specs/SPEC-0306-spec-bootstrap-on-node.md | pending |

Counts: 9 integration, 2 unit, 2 inspection. Seams: S1 (4123, 4125, 4126),
S2 (4124, 4126), S3 (4126), S4 (4123), S5 and S6 (4129), S7 (4132),
S8 (4130 and the existing TEST-3949).

## Verification

- Each touched suite runs whole through the canonical runner with
  `env -u AAI_ROLE` and exits 0: aai-doctor, aai-bootstrap-node,
  aai-bootstrap, aai-prompt-diet. The suites that read the two edited prompts
  also run: aai-win-fallback, aai-routine, aai-run-tests,
  aai-validate-skills. Example:
  `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-doctor.sh`.
- `node .aai/scripts/spec-lint.mjs --path <this spec>` prints LINT PASS.
- `node .aai/scripts/spec-amend.mjs list --strict` exits 0.
- Under bash, `cat .aai/*.prompt.md | /usr/bin/wc -c` minus 376171 equals
  the credit of the onboarding-tech-contract-and-lint-gaps ledger entry
  (Spec-AC-12), and `git diff --quiet 5f02b0e5 -- .aai/ORCHESTRATION.prompt.md`
  exits 0.
- `node .aai/scripts/mutation-run.mjs` writes one RED record per Test Plan
  row (`--check` first), and
  `node .aai/scripts/mutation-gate.mjs --spec <this spec> --require-evidence`
  prints GATE PASS.
- One full sweep before the close, with `AAI_TEST_TIMEOUT=3600`.
- Hosted: the skill-suite run on the pull request head, including the
  Windows legs (the reporter ran Windows; the CRLF case is the local proxy).
- PASS criteria: every TEST-xxx green, every Spec-AC in a terminal status.

## Evidence contract

- ref_id `onboarding-tech-contract-and-lint-gaps`. RED and GREEN logs go
  under `docs/ai/tdd/onboarding-tech-contract-and-lint-gaps/{red,green}/TEST-xxxx.log`,
  and mutation records go under
  `docs/ai/tdd/spec-onboarding-tech-contract-and-lint-gaps/`.
- The validation report is
  `docs/ai/reports/VALIDATION-<ts>-onboarding-tech-contract-and-lint-gaps.md`,
  and the review report is
  `docs/ai/reviews/review-onboarding-tech-contract-and-lint-gaps-<ts>.md`.

### Evidence by strategy

tdd: a stored RED artifact for each AC-gating test plus the verification
above.

## Registry items closed by this scope

none

`node .aai/scripts/follow-ups.mjs list` (351 open) holds no item on the
technology-contract seed, the bootstrap lint chain or TECH_EXTRACT. The
doctor items listed there (`fu-doctor-declined-vocab-undeclared`,
`fu-platform-record-doctor-update-drift`) and the bootstrap platform items
(`fu-platform-*`) are on other subjects and this scope does not touch them.

## Residual risks

- The PowerShell launcher is not run for the new paths. It is a 9-line
  forwarder to the same module (TEST-4133 pins that it holds no lint logic),
  and the windows-parity bootstrap scenarios hold no eslintrc or seed
  fixture. Native Windows evidence for these exact paths is the hosted
  Windows leg only.
- No real ESLint runs (no network). TEST-4129 proves the argv the skill
  passes, not that ESLint 8 lints the project. A legacy project without an
  eslint dependency probably lacks the plugins its `.eslintrc*` names too;
  the pin note tells the operator to add eslint as a devDependency.
- The aai-sync seed path (S1) is covered by using the template bytes that
  `copyReplace` copies, read from `aai-sync.mjs` source, not by running a
  sync. A future sync that rewrites the seed would bypass these tests.
- A hand-edited TECHNOLOGY.md that dropped its `- Status:` line is not
  flagged.
- The SPEC-0306 amendment relies on the owner's triage approval of the
  intake as sign-off. Canon assigns frozen-spec changes to the owner, who may
  reverse it.
