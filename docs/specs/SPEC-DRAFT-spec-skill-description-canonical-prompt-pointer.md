---
id: spec-skill-description-canonical-prompt-pointer
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: 0ab665c0cbc59837a58d5073d941ef6605f7548cc406cda57d878c93303f46d4
ceremony_level: 2
links:
  requirement: skill-description-canonical-prompt-pointer
  rfc: null
  pr: []
  commits: []
---

# Every shipped skill wrapper names its canonical source in its description, and an /aai-ship turn never ends silently

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/CHANGE-DRAFT-skill-description-canonical-prompt-pointer.md
  (GitHub issues #594 `contract_violation` harness-skills/skill_discovery and
  #593 `stalled_progress` aai-ship/run_sequencing; owner approved one ride
  for both, 2026-11-26).
- Prior scopes this one builds on (closed, not edited, no amendment):
  SPEC-0154 (harness-surfaces-drift-unguarded: the generator, the manifest,
  the verbatim description transform), spec-layer-profiles D3 (wrappers are
  profile-independent and self-report an absent prompt),
  spec-provider-adapter-surfaces-closing-slice (the opt-in `catalog:`
  manifest section whose discipline the new `pointer:` section copies).
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, Node 22 floor,
  bash 3.2 suites run through `.aai/scripts/aai-run-tests.sh`).

## Implementation strategy

- Strategy: tdd
- Rationale: every new guard behaviour can be watched failing on the
  unchanged tree first. The live tree carries no pointer today, so the
  live-tree and consumer tests are RED before the wrapper edits; the
  refusal tests are RED before the guard code exists; the SKILL_SHIP text
  tests are RED before the prompt edit. The wrapper description edits are
  data that those same tests turn green.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound ride that rewrites 42 wrappers in four
  trees, the generator and a canonical prompt; the main checkout is shared
  with other sessions.
- User decision: worktree (autopilot default; ride already isolated in
  worktree)
- Base ref: origin/main at 5f02b0e5
- Worktree branch/path: fix/skill-discovery-pointer at
  /Users/ales/Projects/aai-worktrees/skill-discovery-594-593
- Review required: true
- Review scope (explicit paths): .claude/skills; .agents/skills;
  .codex/skills; .gemini/skills; .aai/scripts/sync-harness-skills.mjs;
  .aai/system/HARNESS_SKILLS.yaml; .aai/SKILL_SHIP.prompt.md;
  docs/SKILL_CATALOG.html; docs/skill-catalog-data.json;
  tests/skills/test-aai-harness-shims.sh;
  tests/skills/test-aai-hygiene-pack.sh;
  tests/skills/test-aai-downstream-autopilot.sh;
  tests/skills/test-aai-prompt-diet.sh;
  tests/skills/lib/prompt-diet-ledger.sh;
  tests/skills/test-aai-pr-preflight.sh;
  tests/skills/test-aai-suite-reuse.sh; CHANGELOG.md.

## Measurements (origin/main 5f02b0e5, 2026-11-26)

Consumer measurements used throwaway consumers under the Planning scratch
directory, installed with `node .aai/scripts/aai-sync.mjs <dst>` and
`--profile core`, with HOME and XDG_CACHE_HOME redirected into the scratch
directory. This repository tracks `.aai/` and the skill trees; a downstream
project ignores both, so no consumer claim is measured here.

| Item | Measured |
|---|---|
| M1 | 42 wrappers in `.claude/skills`. No description names its canonical source; the pointer exists only in the wrapper body. Description lengths 88 to 588 characters (`aai-test-canon`). |
| M2 | 40 wrapper bodies name `.aai/SKILL_<NAME>.prompt.md`, always the name-derived path, and it exists. `aai-overview` and `aai-factory-report` name no prompt; their bodies run `node .aai/scripts/generate-overview.mjs` and `node .aai/scripts/generate-factory-report.mjs`. |
| M3 | Four unquoted descriptions hold `: ` inside a plain YAML scalar, which a strict YAML parser rejects (a plain scalar may not contain a colon followed by a space): `aai-debug`, `aai-deslop`, `aai-loop`, `aai-wrap-up`. The quote characters they hold: debug none, deslop and loop one apostrophe each, wrap-up twelve double quotes. |
| M4 | Extended consumer (the no-flag default): 42 wrappers in each of the four trees, every body reference exists, and the consumer's own `sync-harness-skills.mjs --check` exits 0 (trees, 6 shims, 42 catalog rows). |
| M5 | Core consumer: 42 wrappers in each tree, but 22 body references are absent (20 extended prompts and the two extended scripts). The consumer's `--check` exits 0 (catalog 22 rows). PROFILES.yaml line 30 declares wrappers profile-independent and self-reporting. |
| M6 | `aai-bootstrap.mjs` writes project wrappers into `.claude/skills` only, marked `AAI-DYNAMIC-SKILL:START`, with a description that names the project command, not an AAI source. |
| M7 | `docs/SKILL_CATALOG.html` and `docs/skill-catalog-data.json` are committed outputs of `generate-docs-hub.mjs` that carry every description; `test-aai-deslop.sh` TEST-014 fails when they differ from a fresh render. |
| M8 | `SKILLS.md` Quick Reference rows are never rewritten by the generator (existing rows are not compared), so they keep their hand-written short descriptions. |
| M9 | Fixture manifests in `test-aai-hygiene-pack.sh` (test_110, test_112 and others) and `test-aai-harness-shims.sh` (mk_cat_root) are self-written, without any new section. test_118 and test_119 rewrite the live `aai-wrap-up` description to a pointer-less text in a clone carrying the live manifest, then expect `--check` to exit 0. |

## Decisions

### D1: the pointer shape (#594)

Each wrapper's one-line `description` is the existing trigger text followed
by one space and exactly one of two closing sentences:

- prompt-run wrapper: `Run by reading .aai/SKILL_<NAME>.prompt.md first.`
- script-run wrapper: `Run via node .aai/scripts/<name>.mjs.`

The pointer is a suffix, so the "Use when" trigger phrase stays first, as
the Claude Code skills documentation recommends ("put the key use case
first"). The RETIRED and DEPRECATED prefixes that
`test-aai-legacy-migrations.sh` and `test-aai-hygiene-pack.sh` pin stay
unchanged. Two shapes, not one: a script-run wrapper must not be told to
"read" a generator script, and these two wrappers run exactly that command
(M2). No exemption mechanism is added, because every wrapper resolves to
one of the two shapes; a wrapper that resolves to neither fails the guard
(D4), so nothing is skipped without a name.

### D2: the length limit (#594)

The strictest documented per-description limit across the supported
harnesses is 1024 characters: the Agent Skills specification
(agentskills.io/specification, "Must be 1-1024 characters"), read
2026-11-26. Claude Code caps the listed description at 1,536 characters
(code.claude.com/docs/en/skills). The Codex skills page
(learn.chatgpt.com/docs/build-skills) and the Gemini CLI skills page
(geminicli.com/docs/cli/skills) state no per-description cap. Codex
shortens descriptions when the whole skill list exceeds its budget, and
Claude Code drops descriptions of the least-used skills. Neither is a
per-description limit, so neither can be checked here (Residual risks).
Characters are counted as Unicode code points of the unquoted value
(`[...desc].length`). The longest description after the change is about 640.

### D3: the description is a YAML-safe one-line scalar (#594, found during planning)

A harness that parses frontmatter with a strict YAML parser cannot read the
four wrappers of M3. The guard accepts exactly three forms of the raw text
after `description: `:

- double-quoted: starts and ends with `"`, and the inner text holds no `"`
  and no backslash;
- single-quoted: starts and ends with `'`, and the inner text holds no `'`;
- plain: non-empty, no leading or trailing whitespace, does not start with a
  YAML indicator character (`-?:,[]{}#&*!>'"%@` the pipe character or the
  backtick), holds neither `: ` nor ` #`, and does not end with `:`.

`aai-debug`, `aai-deslop` and `aai-loop` become double-quoted and
`aai-wrap-up` becomes single-quoted (M3 quote counts), so no reader has to
unescape. Every existing reader already strips one pair of surrounding
quotes (`extractDescription`, `generate-docs-hub.mjs` parseFrontmatter, the
Hermes smoke), so the rendered text does not change apart from the pointer.

### D4: the guard lives in sync-harness-skills.mjs --check, opt-in by manifest

- `.aai/system/HARNESS_SKILLS.yaml` gains an optional `pointer:` section
  with exactly one row `<max>|<source>`, shipped as
  `  - 1024|agentskills.io/specification: description must be 1-1024 characters`.
  A manifest without the section checks nothing (the existing fixtures of
  M9 stay valid, the same discipline as `catalog:`). A section with zero
  or two or more rows, a `<max>` that is not an integer in 1..1024, or an
  empty `<source>` exits 2 naming the cause, in both `--check` and
  `--write`, before any write. The bound is the script constant
  `AGENT_SKILLS_DESCRIPTION_MAX = 1024` and the check is the one line
  `if (!(max >= 1 && max <= AGENT_SKILLS_DESCRIPTION_MAX)) {`.
- The check runs over the source tree `.claude/skills` only. The existing
  parity check already proves that the three mirrors carry the same
  description byte for byte, so one source check covers all four trees.
- `function checkPointers(root, rule, models) {` returns
  `{ drift, skipped, count }`. For each wrapper, in sorted order, it reports
  the FIRST failing check as exactly one line
  `DIVERGE pointer <skill>: <reason>`, checking in this order:
  1. `description is not a YAML-safe one-line scalar` —
     `function isYamlSafeScalar(raw) {` (D3);
  2. `description is <n> characters, over the <max> limit` — the count is
     `const chars = [...desc].length;` and the test is the one line
     `if (chars > rule.max) {`;
  3. `description lacks the canonical pointer` —
     `function parsePointer(description) {` returns `{ kind, target }` for
     the D1 suffix preceded by at least one non-space character, else
     `null`;
  4. `names missing file <target>` — the target is not a regular file
     under the root, and `function profileAbsent(root, rel) {` (D5) does
     not excuse it;
  5. `the body names no canonical source` — `function bodyTarget(body) {`
     returns the first `.aai/<NAME>.prompt.md` reference in the body, else
     the first `` `node .aai/scripts/<name>.mjs `` command, else `null`;
  6. `names <target>, the body runs <bodyTarget>` — the description
     pointer differs from the body's target (kind or path).
- `--check` prints the drift lines with the other DIVERGE lines and exits
  1 when any exists. On success it prints, after the existing tree, shim and
  catalog lines, `OK: <count> wrapper description(s) name their canonical source`.
  The existing OK lines do not change (`test-aai-harness-shims.sh` TEST-3003
  pins the tree line).
- `--write` does not run the pointer check: it generates mirrors and cannot
  author a description. Its exit contract is unchanged.

### D5: consumer-shaped wrappers are named, never silently passed

- A core-profile consumer receives every wrapper but not the extended
  sources (M5, layer-profiles D3). `profileAbsent(root, rel)` returns true
  only when `<root>/.aai/system/PROFILES.yaml` lists `rel` under its
  `extended:` list. Then the missing target is the declared profile shape,
  and the wrapper self-reports at run time. A missing target that is not
  listed (a typo, a renamed prompt) is still `names missing file`. In this
  repository every listed path exists, so the exception never fires here.
- A wrapper whose body holds `AAI-DYNAMIC-SKILL:START` is project-generated
  by `/aai-bootstrap` (M6). It is not shipped by the layer and names a
  project command, so it is reported as
  `SKIPPED pointer <skill>: project-generated (AAI-DYNAMIC-SKILL marker)`
  on stdout and is left out of `count` and drift.

### D6: #593 finding and the smallest guard

Finding. A missing pointer (#594) is a plausible cause: a model that acts
on the listed summary without loading the wrapper never reaches the
canonical sequencing. It is not the only plausible cause. Reading
`.aai/SKILL_SHIP.prompt.md`, `.aai/SKILL_LOOP.prompt.md`,
`.aai/ORCHESTRATION.prompt.md` and `ride-status.mjs` on 5f02b0e5:

- Every STOP that the loop and orchestrator define leaves a trace: a HITL
  block with `human_input.required: true` (stop conditions b, e and f, a
  BLOCKED role per the SUBAGENT_PROTOCOL merge protocol), or a printed
  LOOP line plus the LOOP SUMMARY and the `ride-status.mjs` output.
- SKILL_SHIP autopilot default 2 says
  `required OR ceremony L3 -> STOP; a human decides` and names no output
  and no STATE record. Re-running /aai-ship reaches orchestrator rule 8
  again and stops again with nothing on record. This branch fires after
  spec freeze (the worktree decision follows Planning), so it is not the
  reported pre-freeze shape, but it is a silent-stop path.
- SKILL_SHIP has no end-of-turn rule. Its step 7 assumes the ride reaches
  step 6. A turn that ends mid-ride leaves the ride with ride-status
  `blocker: none`, `pr_open: not_done` and `resume: loop`. That happens
  after a dispatch has been announced but not made, while a dispatched
  background subagent is still running, or after context compaction. A
  pre-freeze ride in that state matches #593 exactly: no freeze, no PR, no
  Decision Block, no blocked STATE. Measured: this ride's own STATE before
  Planning reads `blocker: none` and `resume: loop` in `ride-status.mjs`.

Because #593 is `reproducible: false` with harness unknown, the
evidence cannot single out #594. The smallest guard is two prompt edits in
`.aai/SKILL_SHIP.prompt.md`, with no new script:

- Default 2's required/L3 branch parks as `[HITL-7]` (the existing
  "Worktree recommendation unanswered" trigger of SKILL_HITL) with
  `state.mjs set-human-input --required true --reason "[HITL-7] ..."`,
  prints the HITL block and stops. Autopilot still never records the
  worktree decision itself.
- STRICT RULES gains one rule whose anchor text is `END-OF-TURN INVARIANT`.
  A turn of the ride ends only on (a) the step 6 summary with the PR URL,
  (b) the HITL block with `human_input.required` true in STATE, or (c) a
  STOP above with its refusal printed verbatim. Before ending any other
  way, the agent runs `node .aai/scripts/ride-status.mjs`. On
  `blocker: none` it either continues at the `next decision`, or parks
  with
  `node .aai/scripts/state.mjs set-human-input --required true --reason "<why>" --question "<what to decide>"`
  and prints the HITL block. A dispatched subagent that has not returned is
  not a stop.

#593 is closed with this change on that basis: the documented cause
(#594) is fixed, and the other silent paths found are guarded.

## Acceptance Criteria Mapping

- AC-001 (consumer: every wrapper description names an existing canonical
  file, or a declared exemption) maps to Spec-AC-01, Spec-AC-06 and
  Spec-AC-07. Exemptions are the two named consumer shapes of D5, not a
  list.
- AC-002 (the guard fails on a missing pointer and on a pointer to a missing
  file; a test proves both and the clean pass) maps to Spec-AC-02 and
  Spec-AC-05.
- AC-003 (every description within the harness limit, and the guard
  enforces it) maps to Spec-AC-03 and Spec-AC-04.
- AC-004 (the #593 finding with evidence; a guard with a test if a silent
  path exists) maps to D6, Spec-AC-08 and Spec-AC-09.
- AC-005 (CHANGELOG entry) maps to Spec-AC-11.
- Seam found during planning (M7): the committed docs-hub catalog carries
  descriptions and maps to Spec-AC-10.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN sync-harness-skills.mjs --check runs on the live tree THEN it SHALL exit 0 and print OK 42 wrapper description(s) name their canonical source; an independent reader SHALL find in each of the 42 source descriptions exactly one D1 suffix whose target is the body's first canonical reference and an existing file. | done | docs/ai/tdd/skill-description-canonical-prompt-pointer/green/TEST-4130.log | — | D1, M1, M2 |
| Spec-AC-02 | WHEN a wrapper's description lacks the pointer, names a missing file, names a target other than its body's, or its body names no canonical source THEN --check SHALL exit 1 with exactly one DIVERGE pointer line naming that wrapper and the D4 reason; the unmutated fixture SHALL exit 0. | done | docs/ai/tdd/skill-description-canonical-prompt-pointer/green/TEST-4131.log | — | D4 checks 3 to 6 |
| Spec-AC-03 | WHEN a description is an unquoted scalar holding a colon followed by a space, or a double-quoted scalar holding an inner double quote THEN --check SHALL exit 1 naming the wrapper as not a YAML-safe one-line scalar; the same text double-quoted SHALL pass; the four M3 wrappers SHALL be quoted. | done | docs/ai/tdd/skill-description-canonical-prompt-pointer/green/TEST-4132.log | — | D3, M3 |
| Spec-AC-04 | WHEN a description with a valid pointer is 1025 code points long under the shipped 1024 limit THEN --check SHALL exit 1 naming the wrapper, its length and the limit; a 1024 code point description SHALL pass. | done | docs/ai/tdd/skill-description-canonical-prompt-pointer/green/TEST-4133.log | — | D2 |
| Spec-AC-05 | A manifest without a pointer section SHALL check no pointer and print no pointer line; WHEN the pointer section has a max of 0, of 1025, a non-integer max, an empty source, or two rows THEN both --check and --write SHALL exit 2 naming the cause and leave every tree byte-identical. | done | docs/ai/tdd/skill-description-canonical-prompt-pointer/green/TEST-4134.log | — | D4 opt-in |
| Spec-AC-06 | WHEN a pointer target is absent but listed under extended in the root's PROFILES.yaml THEN --check SHALL report no drift for it, and an absent unlisted target SHALL still be named missing; WHEN a wrapper body holds the AAI-DYNAMIC-SKILL marker THEN --check SHALL print SKIPPED pointer for it and exclude it from the count. | done | docs/ai/tdd/skill-description-canonical-prompt-pointer/green/TEST-4135.log | — | D5, M5, M6 |
| Spec-AC-07 | In a scratch consumer installed by aai-sync.mjs with the default profile and another with --profile core, every wrapper in .claude, .agents, .codex and .gemini skills SHALL carry its source description byte for byte with a D1 pointer whose target exists, or (core only) is listed under extended in the consumer's PROFILES.yaml; the consumer's own --check SHALL exit 0 and print the pointer OK line. | done | docs/ai/tdd/skill-description-canonical-prompt-pointer/green/TEST-4136.log | — | AC-001 consumer view, M4, M5 |
| Spec-AC-08 | .aai/SKILL_SHIP.prompt.md STRICT RULES SHALL hold the END-OF-TURN INVARIANT rule naming the three legal endings, ride-status.mjs and the set-human-input park command; autopilot default 2's required or L3 branch SHALL name HITL-7, set-human-input and the HITL block. | done | docs/ai/tdd/skill-description-canonical-prompt-pointer/green/TEST-4137.log | — | D6 |
| Spec-AC-09 | WHEN the set-human-input command the invariant prescribes is run against a scratch STATE whose ride-status reads blocker none THEN state.mjs SHALL exit 0 and ride-status.mjs --json SHALL report blocker kind human_input with the given question. | done | docs/ai/tdd/skill-description-canonical-prompt-pointer/green/TEST-4138.log | — | D6 seam |
| Spec-AC-10 | The committed docs/skill-catalog-data.json SHALL carry every source description verbatim, and test-aai-deslop.sh TEST-014 SHALL pass (committed catalog equals a fresh render). | done | docs/ai/tdd/skill-description-canonical-prompt-pointer/green/TEST-4139.log | — | M7 |
| Spec-AC-11 | CHANGELOG.md SHALL hold the heading ## [unreleased] — Skill wrappers name their canonical source; /aai-ship never ends a turn silently (or its rolled version form). | done | docs/ai/tdd/skill-description-canonical-prompt-pointer/green/TEST-4140.log | — | AC-005 |

## Implementation plan

1. Generator (`.aai/scripts/sync-harness-skills.mjs`), TDD: the `pointer:`
   section parse and validation (D4), `checkPointers`, `isYamlSafeScalar`,
   `parsePointer`, `bodyTarget`, `profileAbsent` and a raw-description
   reader (the existing `extractDescription` strips quotes; D3 needs the
   raw text), the drift and OK wiring in `--check`, and the header USAGE
   and EXIT CONTRACT text. No new file and no new import, so
   `.aai/system/PROFILES.yaml` is unchanged. The clone-based hygiene arms
   (test_118, test_119) seed only the generator file and
   `lib/cli-pipe-guard.mjs` into their clones.
2. Manifest (`.aai/system/HARNESS_SKILLS.yaml`): the `pointer:` section
   with the D2 row, and a CONTRACT paragraph in the header naming the row
   grammar, the opt-in and the exit-2 refusals.
3. Wrappers: append the D1 suffix to all 42 `.claude/skills/*/SKILL.md`
   descriptions, ending the existing text with a period where it has none.
   Quote the four M3 wrappers (D3). Then run
   `node .aai/scripts/sync-harness-skills.mjs --write` to regenerate
   `.agents/skills`, `.codex/skills`, `.gemini/skills` and both READMEs. Never
   hand-edit a mirror.
4. Docs hub: `node .aai/scripts/generate-docs-hub.mjs` regenerates
   `docs/SKILL_CATALOG.html` and `docs/skill-catalog-data.json` (M7).
   `SKILLS.md` is not touched (M8).
5. Existing tests that need the pointer:
   `tests/skills/test-aai-hygiene-pack.sh` test_118 and test_119 seed
   texts become
   `seeded wrapper regression fixture. Run by reading .aai/SKILL_WRAP_UP.prompt.md first.`
   and the idempotence equivalent, so a clone carrying the new manifest
   still begins clean. The sed that writes them must escape the slashes.
   test_113(c) expects a red result and stays as it is.
6. `.aai/SKILL_SHIP.prompt.md` (D6): the default 2 branch and the
   END-OF-TURN INVARIANT rule. Prompt-corpus governance, measured with
   `wc -c` on LF bytes after the edit, credited 1:1:
   - `tests/skills/lib/prompt-diet-ledger.sh`: one new entry
     `JUSTIFIED_ADDITIONS+=( "<N> skill-description-canonical-prompt-pointer SKILL_SHIP default 2 HITL-7 park and END-OF-TURN INVARIANT (measured deficit <N> B, 2026-11-26)" )`;
   - `tests/skills/test-aai-prompt-diet.sh` TEST-012: `local want_growth=68174`
     becomes `68174 + N`;
   - `tests/skills/test-aai-pr-preflight.sh` case 008: the want_growth
     expression gains
     `+<N>/* skill-description-canonical-prompt-pointer SKILL_SHIP end-of-turn invariant ledger credit */`;
   - `tests/skills/test-aai-suite-reuse.sh` TEST-3278: a dated comment line
     and `+ <N>` on the `was=$((was + ...))` sum.
   - Not touched: `.aai/ORCHESTRATION.prompt.md` (its 40-line cap is
     unaffected), `.aai/AGENTS.md`, PROFILES.yaml (no new `.aai/**` file),
     `tests/skills/suite-map.yaml` (the generator, the manifest,
     `.claude/skills/**/SKILL.md` and `.aai/SKILL_SHIP.prompt.md` already
     select aai-harness-shims, aai-hygiene-pack and aai-downstream-autopilot;
     this diff's aai-deslop wrapper edit selects aai-deslop).
7. CHANGELOG.md: the Spec-AC-11 heading with a short body naming the
   pointer suffix, the two shapes, the 1024 limit, the YAML-safe rule, the
   `pointer:` manifest section, and the /aai-ship park and end-of-turn rule.
8. Tests (Test Plan): TEST-4130 to TEST-4136, TEST-4139 and TEST-4140 in
   `tests/skills/test-aai-harness-shims.sh`; TEST-4137 and TEST-4138 in
   `tests/skills/test-aai-downstream-autopilot.sh`. Each one is added to its
   suite's run list and resolves when called by its full `test_*` name.
   Fixtures are `mktemp -d` roots (harness-shims `mk_root` / `TMP_ROOT`,
   registered for cleanup). An empty or relative fixture path is a hard
   failure before any `cd` or `rm`. A consumer install redirects HOME and
   XDG_CACHE_HOME into the fixture. No test writes this checkout, touches
   docker, a remote, or the owner's home.

Seams crossed by a test that produces on one side and reads on the other:

- S1 source description to the four consumer trees through `aai-sync.mjs`
  (TEST-4136: a real sync, read by an independent reader and by the
  consumer's own generator).
- S2 source description to the committed docs-hub catalog (TEST-4139
  plus deslop TEST-014).
- S3 PROFILES.yaml classification to the guard's missing-target rule
  (TEST-4135 fixture, TEST-4136 core consumer).
- S4 the prompt's park command to `state.mjs` and `ride-status.mjs`
  (TEST-4138 runs the command text extracted from the prompt).

## Test Plan

TEST ids 4130 to 4140. Measured free range: the highest id on origin/main
5f02b0e5 below the 9000 fixture band is TEST-4122.

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-4130 | Spec-AC-01 | integration | tests/skills/test-aai-harness-shims.sh | test_4130_live_wrappers_carry_pointer: --check on the live tree exits 0 and prints the pointer OK line with 42; a node helper reads every source description, unquotes it, and asserts one D1 suffix, target equal to the body's first canonical reference, target is an existing file, at most 1024 code points | `sed:s/ Run by reading \.aai\/SKILL_SHIP\.prompt\.md first\.//` on .claude/skills/aai-ship/SKILL.md | green |
| TEST-4131 | Spec-AC-02 | integration | tests/skills/test-aai-harness-shims.sh | test_4131_pointer_refusals: mk_root fixture; four cases (pointer removed; pointer to .aai/SKILL_NOPE.prompt.md; pointer to .aai/SKILL_LOOP.prompt.md on aai-ship; a wrapper whose body names no .aai source), each followed by --write then --check: exit 1 and exactly one DIVERGE pointer line naming the wrapper and the D4 reason text; the unmutated fixture exits 0 | `sed:s/function checkPointers\(root, rule, models\) \{/function checkPointers(root, rule, models) { return { drift: [], skipped: [], count: models.size };/` on .aai/scripts/sync-harness-skills.mjs | green |
| TEST-4132 | Spec-AC-03 | integration | tests/skills/test-aai-harness-shims.sh | test_4132_yaml_safe_scalar: mk_root fixture; an unquoted description holding a colon and a space, and a double-quoted one holding an inner double quote, each exit 1 with not a YAML-safe one-line scalar; the same text double-quoted exits 0; the live aai-debug, aai-deslop and aai-loop descriptions start with a double quote and aai-wrap-up with a single quote | `sed:s/function isYamlSafeScalar\(raw\) \{/function isYamlSafeScalar(raw) { return true;/` on .aai/scripts/sync-harness-skills.mjs | green |
| TEST-4133 | Spec-AC-04 | integration | tests/skills/test-aai-harness-shims.sh | test_4133_length_limit: mk_root fixture; a description padded to 1025 code points (a valid pointer included, one multi-byte character in the padding) exits 1 with description is 1025 characters, over the 1024 limit; padded to exactly 1024 exits 0 | `sed:s/if \(chars > rule\.max\) \{/if (chars > rule.max + 1) {/` on .aai/scripts/sync-harness-skills.mjs | green |
| TEST-4134 | Spec-AC-05 | integration | tests/skills/test-aai-harness-shims.sh | test_4134_pointer_section_opt_in_and_refusals: a three-wrapper fixture whose manifest has no pointer section and pointer-less descriptions exits 0 with no pointer line; pointer sections with max 0, max 1025, max abc, an empty source and two rows each exit 2 naming the cause in --check and --write, with the tree hash unchanged | `sed:s/if \(!\(max >= 1 && max <= AGENT_SKILLS_DESCRIPTION_MAX\)\) \{/if (false) {/` on .aai/scripts/sync-harness-skills.mjs | green |
| TEST-4135 | Spec-AC-06 | integration | tests/skills/test-aai-harness-shims.sh | test_4135_consumer_shaped_exceptions: mk_root fixture; deleting .aai/scripts/generate-overview.mjs while PROFILES.yaml lists it under extended gives no pointer drift, the same deletion with the row removed gives names missing file; a bootstrap-shaped aai-test-unit wrapper with the AAI-DYNAMIC-SKILL marker prints SKIPPED pointer aai-test-unit and the OK count stays 42 | `sed:s/function profileAbsent\(root, rel\) \{/function profileAbsent(root, rel) { return true;/` on .aai/scripts/sync-harness-skills.mjs | green |
| TEST-4136 | Spec-AC-07 | integration | tests/skills/test-aai-harness-shims.sh | test_4136_consumer_view_after_sync: two git-initialised mktemp consumers synced by node .aai/scripts/aai-sync.mjs (default, and --profile core) with HOME and XDG_CACHE_HOME inside the fixture; a node helper compares every wrapper description in the four trees with the source byte for byte and checks the pointer target exists (core: or is listed under extended); each consumer's own --check exits 0 with the pointer OK line | `sed:s/ Run by reading \.aai\/SKILL_INTAKE\.prompt\.md first\.//` on .claude/skills/aai-intake/SKILL.md | green |
| TEST-4137 | Spec-AC-08 | inspection | tests/skills/test-aai-downstream-autopilot.sh | test_4137_ship_end_of_turn_invariant: the SKILL_SHIP STRICT RULES section holds END-OF-TURN INVARIANT, ride-status.mjs, set-human-input and the three endings (step 6, HITL block, STOP printed verbatim); the AUTOPILOT DEFAULTS required or L3 line names HITL-7, set-human-input and HITL block | `sed:s/END-OF-TURN INVARIANT/END-OF-TURN NOTE/` on .aai/SKILL_SHIP.prompt.md | green |
| TEST-4138 | Spec-AC-09 | integration | tests/skills/test-aai-downstream-autopilot.sh | test_4138_park_command_blocks_the_ride: extracts the set-human-input command from the SKILL_SHIP invariant, runs it against a mktemp fixture root whose STATE comes from .aai/templates/STATE_TEMPLATE.yaml with a focus set (ride-status --json reads blocker none first); state.mjs exits 0 and ride-status --json then reads blocker kind human_input carrying the question | `sed:s/set-human-input --required true --reason "<why>"/set-human-input --required yes --reason "<why>"/` on .aai/SKILL_SHIP.prompt.md | green |
| TEST-4139 | Spec-AC-10 | integration | tests/skills/test-aai-harness-shims.sh | test_4139_docs_hub_catalog_carries_descriptions: a node helper reads docs/skill-catalog-data.json and asserts that each of the 42 skills' description equals the unquoted source description; deslop TEST-014 is run in Verification for the render equality | `sed:s/ Run by reading \.aai\/SKILL_SHIP\.prompt\.md first\.//g` on docs/skill-catalog-data.json | green |
| TEST-4140 | Spec-AC-11 | inspection | tests/skills/test-aai-harness-shims.sh | test_4140_changelog_heading: CHANGELOG.md holds the Spec-AC-11 heading in its unreleased or rolled vYYYY.MM.DD form | `sed:s/— Skill wrappers name their canonical source/— Skill wrappers/` on CHANGELOG.md | green |

RED observations are recorded under
`docs/ai/tdd/skill-description-canonical-prompt-pointer/red/TEST-xxxx.log`
before the matching change: TEST-4130, TEST-4136 and TEST-4139 on the
unchanged wrappers; TEST-4131 to TEST-4135 before the guard code;
TEST-4137 and TEST-4138 before the prompt edit; TEST-4140 before the
CHANGELOG entry.

## Verification

- Each touched suite runs whole through the canonical runner with
  `env -u AAI_ROLE` and exits 0: aai-harness-shims, aai-hygiene-pack,
  aai-downstream-autopilot, aai-antigravity-project-skills, aai-deslop,
  aai-docs-hub, aai-legacy-migrations, aai-prompt-diet, aai-pr-preflight,
  aai-suite-reuse, aai-ride-status, aai-ride-handoff and aai-hitl-propagation.
  Example:
  `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-harness-shims.sh`.
- `node .aai/scripts/sync-harness-skills.mjs --check` exits 0 and prints
  `OK: 42 wrapper description(s) name their canonical source`.
- One full sweep before the close, with `AAI_TEST_TIMEOUT=3600`.
- `node .aai/scripts/mutation-run.mjs` writes one RED record per Test Plan
  row (run `--check` first), and
  `node .aai/scripts/mutation-gate.mjs --spec <this spec> --require-evidence`
  prints GATE PASS.
- `node .aai/scripts/spec-amend.mjs list --strict` exits 0 (no amendment is
  planned).
- Hosted: the skill-suite run on the pull request head (Linux and Windows
  legs), since the generator and the sync run on both.
- PASS criteria: every TEST-xxx green, every Spec-AC in a terminal status.

## Evidence contract

- ref_id `skill-description-canonical-prompt-pointer`. RED and GREEN logs go
  under `docs/ai/tdd/skill-description-canonical-prompt-pointer/{red,green}/TEST-xxxx.log`;
  mutation records go under
  `docs/ai/tdd/spec-skill-description-canonical-prompt-pointer/`.
- The validation report is
  `docs/ai/reports/VALIDATION-<ts>-skill-description-canonical-prompt-pointer.md`;
  the review report is
  `docs/ai/reviews/review-skill-description-canonical-prompt-pointer-<ts>.md`.

### Evidence by strategy

tdd: a stored RED artifact for each AC-gating test plus the verification
above.

## Registry items closed by this scope

none.

Scanned with `node .aai/scripts/follow-ups.mjs list` (351 open) for skill,
wrapper, description, harness, catalog, profile and ship subjects. Open
items on subjects this scope touches but does not close, with the reason
for each:

- NOT CLOSED: `fu-sync-core-profile-dangling-wrappers` (P3): core sync
  still copies the wrappers whose extended sources it prunes. D5 makes that
  absence declared and checked (only a PROFILES-extended target is
  excused), but it does not change what the core sync copies.
- NOT CLOSED: `fu-catalog-silent-exclusion` (P3): a universal wrapper
  whose prompt was renamed, or whose body names no source, now fails
  `--check` by name through D4 checks 4 and 5. The catalog library itself
  still leaves it out silently, and the downstream half of the item
  (a bootstrap wrapper that cites a node command gets a row) is untouched.
- NOT CLOSED: `fu-skill-tree-selects-deslop` (P3): the selector gap
  (a wrapper-only diff does not select aai-deslop, whose TEST-014 checks the
  regenerated catalog) is independent of what a description says. This
  ride's own diff selects aai-deslop through its own wrapper glob.

## Residual risks

- Listing budgets: Codex shortens descriptions when the whole skill list
  exceeds its budget (2 percent of the context window, or 8,000 characters
  when the window is unknown), and Claude Code drops whole descriptions of
  the least-used skills. A suffix pointer is the first text a truncation
  from the end removes. The wrapper body still names the source, and Codex
  lists each skill's file path. The 42 descriptions measure 10,025 bytes
  today; with the pointers they total roughly 12,000 characters, over the
  8,000-character fallback. Whether Codex
  cuts from the end is not documented and was not measured.
- D3 is a closed syntactic rule, not a YAML parser: a value it accepts
  could still be read differently by some harness, and it refuses some
  valid YAML (an escaped double-quoted string). Both trade-offs keep every
  naive reader in this repository correct.
- D6 is a prompt rule. No test can prove that a model obeys it. TEST-4137
  pins the text and TEST-4138 proves that the command it prescribes really
  blocks the ride in STATE. #593 was not reproducible, so a recurrence
  after this change needs a fresh report.
- Harness behaviour on the YAML forms of M3 was not run against Codex,
  Gemini, Cursor or Hermes binaries here; D3 rests on the YAML
  specification's plain-scalar rule.
- Ceremony level 2: no file in `protected_paths_l3` (docs/ai/docs-audit.yaml
  and .aai/templates/docs-audit.template.yaml list the same 18 paths), no
  `.aai/workflow/WORKFLOW.md` and no `.github/workflows` file is touched.

## Amendments (post-freeze, additive-with-disclosure)

Recorded by the orchestrator after Implementation, `--signoff none` (the
canon assigns scope changes to the owner; the owner's merge direction signs
this record).

- A1 (corrects M8 and plan step 4): five `SKILLS.md` Quick Reference rows
  (`aai-factory-report`, `aai-live`, `aai-merge`, `aai-release`,
  `aai-roadmap`) are generator-rendered from the wrapper description, so they
  now carry the pointer sentence. TEST-3133 fails without the regeneration.
- A2: the `sync-harness-skills.mjs` line cap in TEST-3014 and TEST-3134 is
  raised from 590 to 720 lines (the guard adds about 120 lines).
- A3: the SKILL_SHIP growth (N = 687 bytes) also moves a fifth pin, the
  SKILL_SHIP offset `rh_now` inside `test-aai-prompt-diet.sh` TEST-012.
- A4: `mk_root` in `test-aai-harness-shims.sh` copies the `SKILL_*.prompt.md`
  files, the two script targets and `PROFILES.yaml` into its fixture, so the
  live manifest's pointer check runs there.
- A5: `test_4019_wiring` in `test-aai-sync-node.sh` pinned every
  `.aai/*.prompt.md` byte-equal to commit 077ee649; the SKILL_SHIP edit
  (D6) breaks that. The byte comparison now skips
  `.aai/SKILL_SHIP.prompt.md`; the file-set equality check still requires it
  to exist, and the TEST-4019 pass text says so.
- A6 (review round 1 remediation, NB-1 and NB-2): the D1 pointer check in
  `sync-harness-skills.mjs` now covers only `aai-` prefixed wrappers, so a
  consumer's own non-AAI skill no longer fails `--check` (TEST-4135 gains a
  user-skill case beside an `aai-` wrapper that still fails). The SKILL_SHIP
  END-OF-TURN INVARIANT gains two legal endings, (d) the INPUT question for the
  need and (e) waiting for an in-flight dispatch to return, never
  re-dispatching it; TEST-4137 pins that text. The SKILL_SHIP growth is
  therefore N = 836 bytes, not 687: every pin that states 687 (ledger entry,
  TEST-012 want_growth and `rh_now`, pr-preflight case 008, TEST-3278) moves
  to 836, and A3 reads 836.
