---
id: spec-roadmap-takes-direction
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: 77c3d1503fcd10651d42426ea69cd350ecef31f75c9f21fd30b3a1c6cf7c36a9
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-DRAFT-roadmap-takes-direction.md
  rfc: null
  pr: []
  commits: []
---

# Spec — the roadmap takes a direction from the owner instead of only refusing rides

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-DRAFT-roadmap-takes-direction.md
- Owner decisions: `capability-roadmap-drives-rides`, `maintenance-budget-one-to-one`
  (hitl_decision, 2026-09-05, docs/ai/decisions.jsonl)
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, no dependencies)

## Implementation strategy
- Strategy: tdd
- Rationale: the whole value of this scope is a RANKING, and a ranking is the
  easiest thing in software to ship vacuously. Three rides this month shipped a
  control that only proved "an output was produced". Every ranking criterion
  below is therefore written as a MOVEMENT (candidate B overtakes candidate A
  when one named input changes) and must be observed failing before the
  comparator exists. A `loop` strategy would let a comparator that sorts by
  nothing pass every row.

## Isolation and review
- Worktree recommendation: required
- Worktree rationale: edits `.aai/scripts/ride-select.mjs`, which every ride's
  gate and the autonomous dispatch both execute; a broken parse in the shipping
  tree fails every ride closed.
- User decision: worktree
- Base ref: main (53f30445)
- Worktree branch/path: feat/roadmap-takes-direction / ../aai-feat-direction
  (already created; no new isolation decision is owed)
- Inline review scope: not applicable

## Ceremony level

Level 2. `.aai/scripts/ride-select.mjs` is not in `protected_paths_l3`
(docs/ai/docs-audit.yaml lines 84-92 name state.mjs, state-engine.mjs,
state-core.mjs, allocate-doc-number.mjs, pre-commit-checks.sh/.ps1,
WORKFLOW.md, CONSTITUTION.md — verified 2026-09-27), and no other protected
surface is touched.

## What is established before this scope starts

Every number below was re-measured in this worktree on 2026-09-27 with the
repository's own readers. Three intake measurements were wrong and are
corrected here.

1. **CORRECTION — the roadmap is read by THREE scripts, not five.** The intake
   names `ride-select.mjs`, `orchestration-dispatch.mjs`,
   `nothing-left-behind.mjs`, `close-work-item.mjs` and
   `check-vendored-script-deps.mjs`. Measured with
   `grep -rln roadmap .aai/scripts/`: only the first three ever open the file.
   `close-work-item.mjs` mentions "roadmap-paired" in a comment and in its
   `--paired <slug>` flag help and never reads `docs/ai/roadmap.yaml`;
   `check-vendored-script-deps.mjs` mentions `roadmapGate()` in one comment
   about a different script. The intake's headline claim — read by N, written
   by none — survives the correction; the N does not.
2. Written by none: confirmed. No script under `.aai/` writes
   `docs/ai/roadmap.yaml`. The only writer is a human with an editor.
3. **13 open draft intakes**, confirmed: `grep -l '^status: draft'
   docs/issues/*.md` returns 14, of which one is this ride's own draft.
4. **824 friction observations**, confirmed: `wc -l` over
   `docs/ai/friction/observations.jsonl` in the primary checkout. The spool is
   gitignored (`.gitignore:50 docs/ai/friction/**`) and is EMPTY in this
   worktree — the harvest must degrade on an empty spool, not fail.
5. **125 open follow-ups**, confirmed: `node .aai/scripts/follow-ups.mjs list`
   prints `shown=125 open=125 closed=399 total=524`.
6. The roadmap is exhausted: `node .aai/scripts/ride-select.mjs next --json`
   returns `{"next":null,"wave_1":"complete","wave_2":[...4 slugs]}`, and
   `validate` prints `roadmap OK: 11 pair(s), 4 wave-2 item(s)`. Both rides
   since wave 3 closed ran on `--override` (`grep -c ride_gate_override
   docs/ai/EVENTS.jsonl` = 4, the last two dated 2026-09-25 and 2026-09-27).
7. **CORRECTION — friction is a weak CAPABILITY source and a strong evidence
   source.** Running `aai-feedback-triage.mjs` over the real 824-row spool
   yields 74 clusters and only **3 review candidates** at the shipped
   threshold of 4. 819 of the 824 observations are one `skill_id` in one
   `skill_phase` (`aai-run-tests` / `test-execution` /
   `deterministic_script_failure`). A triage cluster carries only
   `fingerprint`, `failure_class`, `harness`, `recurrence`, `score`,
   `decision` — no subject text at all. A harvest that turned clusters into
   capability proposals verbatim would print up to 74 rows labelled by a hash.
   D8 and Spec-AC-11 answer this: friction contributes only
   `review_candidate` clusters, always under a label derived from the spool's
   own `skill_id` + `failure_class`, never a bare fingerprint.
8. **CORRECTION — "what it blocks" measured as follow-up back-references is
   ZERO for every draft intake.** Cross-joining
   `follow-ups.mjs list --json` against the 13 drafts' frontmatter ids returns
   0 for all 13; open follow-up `ref_id`s point at SHIPPED capability slugs
   (`update-installs-ref-guard-undisclosed` 28, `friction-channel-sweep` 23,
   `close-ceremony-sweep` 21, `mutation-gate-for-tests` 16,
   `test-framework-sweep` 11). This is why D3 puts the follow-up backlog on the
   MAINTENANCE side, where its counts are large and varying, and why the
   capability-side evidence inputs (D9) are the three that actually vary on
   today's corpus.
9. Inputs that DO vary on today's corpus, measured: `blocks:` frontmatter is
   carried by exactly 2 documents, both naming `standardized-backlog-drain` (a
   wave-2 slug), so `blocks_in` is 2 for one candidate and 0 for the rest; the
   drafts' first-commit dates range 2026-08-28 to 2026-09-07 (30d to 20d), so
   `age_days` separates them.
10. `nothing-left-behind.mjs` already tolerates an absent maintenance half:
    `readRoadmapPairs` returns `{capability, maintenance: null, status}` and
    `roadmapPairedOpen` starts `if (!pair || !pair.maintenance) return []`
    (lines 190-222). No change is needed there — only a seam test.
11. Current prompt-diet ledger checkpoint: the last `JUSTIFIED_ADDITIONS` entry
    in `tests/skills/lib/prompt-diet-ledger.sh` moves the TEST-012 pin to
    **37762** with headroom 1942/2048.
12. `tests/skills/suite-map.yaml` maps suite `aai-ride-select` to globs
    `.aai/scripts/ride-select.mjs` and `docs/ai/roadmap.yaml`.

## Decisions

**D1 — Two surfaces, not one.** A new sibling `.aai/scripts/roadmap-propose.mjs`
owns `harvest`, `write` and `bind`. `ride-select.mjs` keeps `validate`, `next`
and `gate` and changes ONLY where a capability-only pair would otherwise break
it. Rationale: `ride-select.mjs` is executed by every ride's gate and by
`orchestration-dispatch.mjs` rule 4a; folding a harvester into it would double a
291-line script on the factory's hottest refusal path.

**D2 — The closed shape gains exactly one relaxation: `maintenance:` becomes
OPTIONAL.** The grammar is otherwise byte-identical — `budget` still must be 1,
pairs still ordered, `status` still `planned|active|done`, the slug regex, the
duplicate scan and `wave_2` all unchanged. A pair with no `maintenance:` line is
a capability whose maintenance slot is UNBOUND. The live
`docs/ai/roadmap.yaml` parses unchanged because all 11 of its pairs carry the
line (Spec-AC-02 is that regression proof).

**D3 — The 1:1 budget keeps being enforced by the file's own shape.** One
`maintenance:` line per pair IS one maintenance ride per capability. Binding a
maintenance ride WRITES that line; from then on the shipped gate logic enforces
the budget with no change at all. `gate` is deliberately NOT taught to admit an
unbound maintenance ride on the fly: a side-effect-free gate cannot record
consumption, and a gate that records consumption is a gate that mutates the
roadmap while refusing rides. The off-roadmap maintenance refusal stays exit 1
and gains one sentence naming the bind command (Spec-AC-05). This is the answer
to the ride's riskiest question: the existing file is untouched, `gate`'s pair
logic is untouched, `isFirstUnfinished` is untouched.

**D4 — `next` proposes a bind instead of returning a null ref.** Today
`nextRide` on a started capability whose `maintenance` is null would compute
`statusOf(docs, null)` and return `{ ref: null }` — a latent defect the
relaxation in D2 would activate. It returns a `bind` action naming the
capability and the exact `roadmap-propose.mjs bind` command instead.

**D5 — An exhausted roadmap offers the harvest.** `next` with no unfinished pair
keeps printing the wave-2 list and adds the runnable harvest command; `--json`
gains a `harvest_command` field. It still exits 0; it does not prompt, block or
write.

**D6 — Ranking is a printed lexicographic tuple, never a hidden score.** The
order is `(direction DESC, observations DESC, blocks_in DESC, age_days DESC,
id ASC)`. Every component is printed on the candidate's own row. A weighted sum
is refused by construction: it would let one input silently dominate and give
the owner a number instead of a reason. The `id ASC` tail makes the order total
and deterministic.

**D7 — Direction match is counted, printed token overlap.** The owner's one
sentence and the candidate's label (`id` plus its `# ` title) are lowercased,
split on non-alphanumerics, filtered to tokens of 4+ characters that are not in
a closed 40-word stopword list, and intersected. `direction` is the count of
DISTINCT shared tokens and the matched tokens themselves are printed. Direction
is the PRIMARY key — that is what "direction in" means — and evidence orders
what the sentence does not separate.

**D8 — Three candidate sources, each with a readable label.**
- `intake`: `docs/issues/*.md` with `status: draft` and a `type` in the
  capability set `{change, prd, requirement, rfc, research}`. Maintenance types
  (`issue`, `techdebt`, `hotfix`, `chore`, `test`, `ci`) are excluded — the
  roadmap now carries capabilities only. Label: the frontmatter `id` plus the
  `# ` title.
- `wave_2`: every slug in the roadmap's own `wave_2` list that is not already a
  pair. Label: the slug.
- `friction`: only clusters `aai-feedback-triage.mjs` decides
  `review_candidate`, joined back to the spool by `fingerprint` through
  `lib/friction-spool.mjs` `readSpoolRows` to recover `skill_id`, `skill_phase`
  and `failure_class`. Label: `friction-<skill_id>-<failure_class>`, slugified.
  Never a bare fingerprint. An absent or empty spool contributes zero
  candidates and one printed NOTE, not an error.
The follow-up registry is NOT a capability source (measurement 8); it is the
backlog the maintenance half binds from (D3).

**D9 — Evidence per candidate, all measurable from this repository, all
printed.**
- `observations`: the count of OPEN follow-ups whose `ref_id` equals the
  candidate id, read from `node .aai/scripts/follow-ups.mjs list --json`, plus,
  for a friction candidate, its cluster's `recurrence`.
- `blocks_in`: the count of documents under `--docs` whose frontmatter
  `blocks:` names the candidate id and whose own `status` is not terminal,
  read through `lib/docs-model.mjs` `parseFrontmatter`.
- `age_days`: whole days between today and the candidate's first-commit date
  (`git log --diff-filter=A --format=%cs -- <path>`, last line). An untracked
  or date-less candidate gets `age_days: 0` and the printed note
  `age unknown`.

**D10 — The written roadmap is certified by the REAL validator or rolled back.**
`write` appends the picked candidates as `status: planned` capability-only
pairs, leaving every pre-existing byte unchanged, then executes
`node .aai/scripts/ride-select.mjs validate --roadmap <the written path>` as a
child process. A non-zero exit restores the original bytes (or deletes the file
it created), exits 1 and prints the validator's own stderr verbatim. There is no
second copy of the roadmap parser anywhere in this scope, and Spec-AC-12's test
asserts the real validator was the thing that ran.

**D11 — Opt-in is untouched.** `roadmap-propose.mjs` executes only when invoked
by name. It is wired into no automatic path: no `.aai/*.prompt.md` step, no
skill, no `orchestration-dispatch.mjs` branch invokes it. A project with no
`docs/ai/roadmap.yaml` sees no file, no gate and no prompt, exactly as today —
`roadmapGate()`'s absent-file arm is not modified.

**D12 — An empty harvest refuses to write.** Zero candidates means `write` exits
1 with `nothing harvested` and creates nothing. A pairs-less roadmap is invalid
to the shipped validator anyway; refusing before the write keeps the failure
legible instead of surfacing as a parse error.

**D13 — `bind` proves the maintenance ref came from the backlog.** `bind
--capability <slug> --ref <maintenance-ref>` refuses unless (a) `<slug>` is a
pair in the roadmap whose maintenance slot is unbound, and (b) `<maintenance-ref>`
either matches an OPEN follow-up id in the registry or resolves to a document
under `--docs`. On success it writes exactly one `maintenance:` line into that
pair and re-validates through D10's same real-validator-or-rollback path.

## Constitution deviations

None.

## Acceptance Criteria Mapping

- Maps to: docs/issues/CHANGE-DRAFT-roadmap-takes-direction.md "Desired Behavior"

- Spec-AC-01: WHEN `validate` runs against a roadmap whose last pair carries no
  `maintenance:` line THEN it exits 0 and reports that pair in its count.
  - Verification: `node .aai/scripts/ride-select.mjs validate --roadmap <fixture>`
    exits 0 and stdout matches `roadmap OK: 2 pair(s)`.
- Spec-AC-02: WHEN `validate` runs against the shipped `docs/ai/roadmap.yaml`
  after the relaxation THEN it still exits 0 with the identical summary line.
  - Verification: `node .aai/scripts/ride-select.mjs validate` exits 0 and
    stdout is exactly `roadmap OK: 11 pair(s), 4 wave-2 item(s)`.
- Spec-AC-03: WHEN `next` reaches a pair whose capability has STARTED and whose
  maintenance slot is unbound THEN it names that capability and the runnable
  bind command, and never emits an empty or null ref.
  - Verification: `node .aai/scripts/ride-select.mjs next --roadmap <fixture>
    --docs <fixture-docs> --json` exits 0, its `action` field is `bind`, its
    `capability` field is the slug, and its `command` field contains
    `roadmap-propose.mjs bind`.
- Spec-AC-04: WHEN `next` finds no unfinished pair THEN its output carries the
  runnable harvest command alongside the wave-2 list.
  - Verification: `node .aai/scripts/ride-select.mjs next --json` exits 0 and
    the JSON `harvest_command` field contains
    `roadmap-propose.mjs harvest --direction`.
- Spec-AC-05: WHEN `gate` refuses an off-roadmap maintenance ref THEN it still
  exits 1 and its refusal names the bind command as well as the backlog command.
  - Verification: `node .aai/scripts/ride-select.mjs gate --ref some-flake-fix
    --roadmap <fixture> --docs <fixture-docs>` exits 1 and stderr contains both
    `follow-ups.mjs add` and `roadmap-propose.mjs bind`.
- Spec-AC-06: WHEN `harvest` runs THEN every candidate row prints its source and
  all four ranking components by name.
  - Verification: `node .aai/scripts/roadmap-propose.mjs harvest --direction
    "<sentence>" --json` exits 0 and every element of `candidates` carries
    non-null `source`, `label`, `direction`, `direction_tokens`,
    `observations`, `blocks_in` and `age_days`.
- Spec-AC-07: WHEN the direction sentence changes so that it shares tokens with
  candidate B instead of candidate A THEN B's rank rises above A's.
  - Verification: two `harvest --json` runs over the SAME fixture with two
    different `--direction` values; `candidates[0].id` is A in the first run
    and B in the second, and B's `direction` value differs between them.
- Spec-AC-08: WHEN one open follow-up whose `ref_id` is candidate B is added to
  the registry THEN B's `observations` rises by exactly 1 and B overtakes a
  candidate it previously tied with on direction.
  - Verification: `harvest --json` before and after
    `follow-ups.mjs add --id fu-rank-probe --ref <B> --severity P2 ...` against
    a fixture ledger; B's `observations` goes 0 to 1 and B's index in
    `candidates` decreases.
- Spec-AC-09: WHEN a non-terminal document carrying `blocks: <B>` is added to
  the docs tree THEN B's `blocks_in` rises by exactly 1 and B overtakes a
  candidate it previously tied with on direction and observations.
  - Verification: `harvest --json` before and after writing the blocking
    document; B's `blocks_in` goes 0 to 1 and B's index decreases.
- Spec-AC-10: WHEN two candidates tie on direction, observations and blocks_in
  THEN the one whose first commit is older ranks first.
  - Verification: a fixture git repo commits candidate A on an older date than
    candidate B; `harvest --json` reports `age_days` A greater than B and A's
    index lower.
- Spec-AC-11: WHEN the friction source contributes THEN it contributes only
  clusters the shipped triage decided `review_candidate`, each labelled from
  `skill_id` and `failure_class`, and no candidate label contains a `v1:` hash.
  - Verification: `harvest --json` over a fixture spool holding one
    above-threshold and one below-threshold cluster returns exactly one
    `source: friction` candidate whose `label` contains the fixture's
    `skill_id`, and `grep -c 'v1:' ` over the whole JSON output is 0.
- Spec-AC-12: WHEN `write --pick` runs THEN the roadmap gains the picked
  candidates as `status: planned` capability-only pairs, every pre-existing byte
  is unchanged, and the REAL `ride-select.mjs validate` accepts the result.
  - Verification: `node .aai/scripts/roadmap-propose.mjs write --direction
    "<s>" --pick 1 --roadmap <copy>` exits 0; `diff <(head -n <N> <copy>)
    <original>` is empty; the appended block contains no `maintenance:` line;
    and `node .aai/scripts/ride-select.mjs validate --roadmap <copy>` exits 0.
- Spec-AC-13: WHEN the appended result would not validate THEN the original
  bytes are restored and the command exits 1 reporting the validator's message.
  - Verification: with a stub `ride-select.mjs` forced to exit 1 on a copied
    tree, `write ... --pick 1` exits 1, `cmp <copy> <original>` reports no
    difference, and stderr contains the stub's own refusal text.
- Spec-AC-14: WHEN `bind` names a maintenance ref that is neither an open
  follow-up nor a resolvable document THEN it exits 1 and writes nothing; when
  it names one that is, exactly one `maintenance:` line is added to the named
  pair and the real validator accepts the result.
  - Verification: two runs of `node .aai/scripts/roadmap-propose.mjs bind
    --capability <slug> --ref <r>` against a fixture; the bad ref exits 1 with
    `cmp` clean, the good ref exits 0, `grep -c '^    maintenance:' <copy>`
    rises by exactly 1, and `ride-select.mjs validate --roadmap <copy>` exits 0.
- Spec-AC-15: WHEN a project has not opted in THEN nothing about it changes.
  - Verification: in a fixture tree with no `docs/ai/roadmap.yaml`,
    `harvest --json` exits 0 and writes no file (`test ! -e
    <fixture>/docs/ai/roadmap.yaml`); `write` with zero harvested candidates
    exits 1 and still creates no file; and
    `grep -rl 'roadmap-propose' .aai/*.prompt.md .aai/scripts/orchestration-dispatch.mjs`
    returns no automatic invocation site.
- Spec-AC-16: WHEN the scope's companion obligations are checked THEN the new
  `.aai/**` file is classified and the prompt-corpus growth is ledgered.
  - Verification: `bash tests/skills/test-aai-layer-profiles.sh` exits 0 with
    `.aai/scripts/roadmap-propose.mjs` present in `.aai/system/PROFILES.yaml`,
    and `bash tests/skills/test-aai-prompt-diet.sh` exits 0 with the TEST-012
    pin moved from 37762 by the measured `.aai/AGENTS.md` byte delta.

## Acceptance Criteria Status

| Spec-AC    | Description                                                                                  | Status  | Evidence | Review-By | Notes |
|------------|----------------------------------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | WHEN a pair carries no maintenance line the validator SHALL accept the roadmap                  | done | TEST-715, TEST-716, TEST-717 green; `bash tests/skills/test-aai-ride-select.sh` exit 0 | —         | D2    |
| Spec-AC-02 | WHEN the shipped roadmap is validated after the relaxation it SHALL report the identical summary | done | TEST-718 green; `node .aai/scripts/ride-select.mjs validate` exit 0, stdout `roadmap OK: 11 pair(s), 4 wave-2 item(s)` | —         | regression proof for D2 |
| Spec-AC-03 | WHEN next reaches a started capability with an unbound slot it SHALL propose the bind command    | done | TEST-719, TEST-720 green | —         | D4    |
| Spec-AC-04 | WHEN next finds no unfinished pair it SHALL offer the harvest command                            | done | TEST-721 green | —         | D5    |
| Spec-AC-05 | WHEN gate refuses an off-roadmap maintenance ref it SHALL name the bind command and stay exit 1  | done | TEST-722 green | —         | D3    |
| Spec-AC-06 | WHEN harvest runs every candidate SHALL print its source and all four ranking components         | planned | —        | —         | D6 D9 |
| Spec-AC-07 | WHEN the direction sentence changes the matching candidate SHALL rise in rank                    | planned | —        | —         | movement proof, D7 |
| Spec-AC-08 | WHEN an open follow-up naming a candidate is added that candidate SHALL rise in rank             | planned | —        | —         | movement proof, D9 |
| Spec-AC-09 | WHEN a non-terminal document blocking a candidate is added that candidate SHALL rise in rank     | planned | —        | —         | movement proof, D9 |
| Spec-AC-10 | WHEN candidates tie on every earlier key the older candidate SHALL rank first                    | planned | —        | —         | movement proof, D9 |
| Spec-AC-11 | WHEN friction contributes it SHALL contribute only review candidates under a readable label      | planned | —        | —         | D8, measurement 7 |
| Spec-AC-12 | WHEN write runs the appended roadmap SHALL be accepted by the real validator with prior bytes intact | planned | —    | —         | D10   |
| Spec-AC-13 | WHEN the appended roadmap would not validate the original bytes SHALL be restored and the run refuse | planned | —    | —         | D10   |
| Spec-AC-14 | WHEN bind names a ref that is not in the backlog it SHALL refuse and write nothing                | planned | —        | —         | D13   |
| Spec-AC-15 | WHEN a project has not opted in no file, no gate and no prompt SHALL change                       | planned | —        | —         | D11 D12 |
| Spec-AC-16 | WHEN the companion obligations are checked the new file SHALL be classified and the corpus ledgered | planned | —      | —         | PROFILES + prompt diet |

## Implementation plan

Components affected:
- `.aai/scripts/roadmap-propose.mjs` — NEW. Subcommands `harvest`, `write`,
  `bind`. Flags: `--direction <sentence>`, `--pick <n[,n...]>`,
  `--capability <slug>`, `--ref <slug>`, `--roadmap <path>`, `--docs <dir>`,
  `--ledger <path>`, `--spool <path>`, `--json`. Exit 0 success, 1 refusal,
  2 usage. Node stdlib only.
- `.aai/scripts/ride-select.mjs` — MODIFIED, four narrow edits: `loadRoadmap`
  stops requiring `maintenance` (D2); `validate` skips the document-existence
  check for an unbound slot; `nextRide` returns a bind action instead of a null
  ref (D4) and an exhausted roadmap carries the harvest command (D5); the
  off-roadmap maintenance refusal string gains the bind sentence (D3).
- `.aai/AGENTS.md` rule 4 — one sentence: the roadmap now carries capabilities,
  the maintenance half binds at ride time from the backlog, and both commands
  are named. Corpus bytes, hence the ledger obligation.
- `.aai/system/PROFILES.yaml` — `.aai/scripts/roadmap-propose.mjs` classified
  `core`, immediately after `.aai/scripts/ride-select.mjs`.
- `tests/skills/suite-map.yaml` — `.aai/scripts/roadmap-propose.mjs` added to
  the `aai-ride-select` glob list so the selector runs this suite on a change
  to the new engine.
- `tests/skills/test-aai-ride-select.sh` — MODIFIED, the whole Test Plan below.
- `tests/skills/lib/prompt-diet-ledger.sh` — one `JUSTIFIED_ADDITIONS` append.

Data flows:
- harvest: `docs/issues/*.md` frontmatter + `docs/ai/roadmap.yaml` `wave_2` +
  (`aai-feedback-triage.mjs` clusters joined to `friction-spool.mjs` rows) ->
  candidates; `follow-ups.mjs list --json` + `blocks:` frontmatter + git
  first-commit dates -> evidence; direction sentence -> primary key; ranked
  slate to stdout.
- write / bind: candidates -> appended lines -> `ride-select.mjs validate`
  child process -> keep or restore.

Edge cases:
- Empty or absent friction spool (the state of this very worktree): zero
  friction candidates plus one NOTE line.
- Absent `docs/ai/roadmap.yaml`: `harvest` still works (`wave_2` contributes
  nothing); `write` creates the file with the header comment and the
  `budget: maintenance_per_capability: 1` block before the first pair.
- Untracked candidate document: `age_days: 0` with `age unknown` printed.
- `--pick` out of range or duplicated: usage error, exit 2, nothing written.
- Direction sentence that matches nothing: every `direction` is 0 and the order
  falls through to evidence, printed as such.

## Test Plan

Every row lands in `tests/skills/test-aai-ride-select.sh` unless stated.
Fixtures are per-test temporary trees; no test may pin a live roadmap pair by
INDEX (the shape `fu-roadmap-pair-pinned-by-index` names — derive the pair from
the file under test).

| Test ID  | Spec-AC    | Type        | File path (expected)                  | Description                                                                 | Mutation                                                                 | Status  |
|----------|------------|-------------|---------------------------------------|-----------------------------------------------------------------------------|--------------------------------------------------------------------------|---------|
| TEST-715 | Spec-AC-01 | integration | tests/skills/test-aai-ride-select.sh  | validate accepts a two-pair fixture whose second pair has no maintenance line | `sed:s/if \(!pr\.status\)/if (pr.maintenance === null) { return { error: 'maintenance required' }; } if (!pr.status)/` in ride-select.mjs loadRoadmap (reconciled: a pipe-free two-statement reintroduction of the old requirement — a literal `\|\|` in a replacement cell corrupts the table and, unescaped, would land a literal backslash in the mutated source) | done |
| TEST-716 | Spec-AC-01 | integration | tests/skills/test-aai-ride-select.sh  | validate skips the document-existence check for an unbound slot on an active pair | `sed:s/if \(ref === null\) continue;//` in ride-select.mjs validate loop      | done |
| TEST-717 | Spec-AC-01 | integration | tests/skills/test-aai-ride-select.sh  | seam — nothing-left-behind over a capability-only pair exits 0 and reports no paired half | `sed:s/if \(!pair \|\| !pair\.maintenance\) return \[\];/if (!pair) return []; pair.maintenance = 'nlb717-other';/` in nothing-left-behind.mjs (reconciled: the literal guard-only removal is unkillable — `String(x) === null` can never be true, so `docs.find` still returns undefined either way; this mutation instead redirects the unbound slot onto a real, non-terminal doc id, exercising the same seam — a spurious "still open" report — observably) | done |
| TEST-718 | Spec-AC-02 | integration | tests/skills/test-aai-ride-select.sh  | validate over the shipped docs/ai/roadmap.yaml still prints the identical summary line | `sed:s/roadmap OK:/roadmap ok:/` in ride-select.mjs validate output        | done |
| TEST-719 | Spec-AC-03 | integration | tests/skills/test-aai-ride-select.sh  | next on a started capability with an unbound slot returns action bind, never a null ref | `sed:s/return { action: 'bind'/return { ref: pr.maintenance/` in ride-select.mjs nextRide | done |
| TEST-720 | Spec-AC-03 | integration | tests/skills/test-aai-ride-select.sh  | the bind action names the capability slug and the runnable roadmap-propose command | `sed:s/roadmap-propose.mjs bind/roadmap-propose bind/` in ride-select.mjs nextRide | done |
| TEST-721 | Spec-AC-04 | integration | tests/skills/test-aai-ride-select.sh  | next on an exhausted roadmap emits harvest_command alongside the wave-2 list  | `sed:s/harvest_command:/harvest_hint:/` in ride-select.mjs next            | done |
| TEST-722 | Spec-AC-05 | integration | tests/skills/test-aai-ride-select.sh  | the off-roadmap maintenance refusal exits 1 and names both the backlog and the bind command | `sed:s/whose maintenance slot is unbound: node \.aai\/scripts\/roadmap-propose\.mjs bind/whose maintenance slot is unbound: echo/` in ride-select.mjs isMaintenance deny (reconciled: `.*$` with no `m` flag cannot match mid-file and, if forced, would delete the statement's own closing backtick/paren/semicolon — a narrower, syntax-safe substring targets the same appended sentence) | done |
| TEST-723 | Spec-AC-06 | integration | tests/skills/test-aai-ride-select.sh  | harvest --json emits source, label, direction, direction_tokens, observations, blocks_in and age_days on every candidate | `sed:s/blocks_in: blocksIn,//` in roadmap-propose.mjs candidate serializer  | pending |
| TEST-724 | Spec-AC-06 | integration | tests/skills/test-aai-ride-select.sh  | harvest draws intake candidates only from draft docs whose type is in the capability set | `sed:s/CAPABILITY_TYPES.has(fm.type)/true/` in roadmap-propose.mjs intake source | pending |
| TEST-725 | Spec-AC-06 | integration | tests/skills/test-aai-ride-select.sh  | harvest draws wave_2 slugs that are not already pairs                          | `sed:s/!pairSlugs.has(slug)/true/` in roadmap-propose.mjs wave2 source      | pending |
| TEST-726 | Spec-AC-07 | integration | tests/skills/test-aai-ride-select.sh  | MOVEMENT — two directions over one fixture swap the top candidate and change its direction count | `sed:s/shared.size/0/` in roadmap-propose.mjs directionMatch               | pending |
| TEST-727 | Spec-AC-07 | integration | tests/skills/test-aai-ride-select.sh  | direction is the PRIMARY sort key — a lower-evidence candidate that matches the sentence outranks a higher-evidence one that does not | `sed:s/b.direction - a.direction 006!!//` in roadmap-propose.mjs comparator | pending |
| TEST-728 | Spec-AC-07 | unit        | tests/skills/test-aai-ride-select.sh  | stopwords and tokens under 4 characters never count as a direction match       | `sed:s/tok.length >= 4/tok.length >= 1/` in roadmap-propose.mjs tokenize    | pending |
| TEST-729 | Spec-AC-08 | integration | tests/skills/test-aai-ride-select.sh  | MOVEMENT — adding one open follow-up naming candidate B raises its observations 0 to 1 and lowers its index | `sed:s/b.observations - a.observations 006!!//` in roadmap-propose.mjs comparator | pending |
| TEST-730 | Spec-AC-08 | integration | tests/skills/test-aai-ride-select.sh  | a CLOSED follow-up naming candidate B does not raise its observations         | `sed:s/it.status === 'open'/true/` in roadmap-propose.mjs observationsFor   | pending |
| TEST-731 | Spec-AC-09 | integration | tests/skills/test-aai-ride-select.sh  | MOVEMENT — adding a non-terminal document with blocks naming B raises blocks_in 0 to 1 and lowers its index | `sed:s/b.blocks_in - a.blocks_in 006!!//` in roadmap-propose.mjs comparator | pending |
| TEST-732 | Spec-AC-09 | integration | tests/skills/test-aai-ride-select.sh  | a TERMINAL document blocking B does not raise its blocks_in                    | `sed:s/!TERMINAL_DOC_STATUS.has(st)/true/` in roadmap-propose.mjs blocksIn  | pending |
| TEST-733 | Spec-AC-10 | integration | tests/skills/test-aai-ride-select.sh  | MOVEMENT — with every earlier key tied the older first-commit date ranks first | `sed:s/b.age_days - a.age_days 006!!//` in roadmap-propose.mjs comparator   | pending |
| TEST-734 | Spec-AC-10 | integration | tests/skills/test-aai-ride-select.sh  | an untracked candidate reports age_days 0 and the literal note age unknown     | `sed:s/age unknown//` in roadmap-propose.mjs ageDays                        | pending |
| TEST-735 | Spec-AC-11 | integration | tests/skills/test-aai-ride-select.sh  | only review_candidate clusters become friction candidates                      | `sed:s/c.decision === 'review_candidate'/true/` in roadmap-propose.mjs friction source | pending |
| TEST-736 | Spec-AC-11 | integration | tests/skills/test-aai-ride-select.sh  | a friction label carries skill_id and failure_class and no v1 fingerprint hash appears in the output | `sed:s/frictionLabel(row)/c.fingerprint/` in roadmap-propose.mjs friction source | pending |
| TEST-737 | Spec-AC-11 | integration | tests/skills/test-aai-ride-select.sh  | an empty or absent spool yields zero friction candidates, exit 0 and one NOTE line | `sed:s/spool is empty/ /` in roadmap-propose.mjs friction NOTE             | pending |
| TEST-738 | Spec-AC-12 | integration | tests/skills/test-aai-ride-select.sh  | write appends planned capability-only pairs, leaves prior bytes identical, and the REAL validator accepts | `sed:s/status: planned/status: active/` in roadmap-propose.mjs pair emitter | pending |
| TEST-739 | Spec-AC-12 | integration | tests/skills/test-aai-ride-select.sh  | the certification runs ride-select.mjs validate as a child process, proven by a shim recording its own argv | `sed:s/'validate', '--roadmap'/'next', '--roadmap'/` in roadmap-propose.mjs certify | pending |
| TEST-740 | Spec-AC-13 | integration | tests/skills/test-aai-ride-select.sh  | a refused certification restores the original bytes, exits 1 and prints the validator stderr | `sed:s/fs.writeFileSync(target, original)//` in roadmap-propose.mjs rollback | pending |
| TEST-741 | Spec-AC-14 | integration | tests/skills/test-aai-ride-select.sh  | bind refuses a ref that is neither an open follow-up nor a resolvable document and writes nothing | `sed:s/if (!openIds.has(ref) 006!! !findDoc(docs, ref))/if (false)/` in roadmap-propose.mjs bind | pending |
| TEST-742 | Spec-AC-14 | integration | tests/skills/test-aai-ride-select.sh  | bind adds exactly one maintenance line to the named pair and the real validator accepts | `sed:s/pair.maintenance !== null/false/` in roadmap-propose.mjs bind slot check | pending |
| TEST-743 | Spec-AC-15 | integration | tests/skills/test-aai-ride-select.sh  | harvest in a tree with no roadmap exits 0 and creates no docs/ai/roadmap.yaml  | `sed:s/if (!candidates.length) refuse/if (false) refuse/` in roadmap-propose.mjs write | pending |
| TEST-744 | Spec-AC-15 | integration | tests/skills/test-aai-ride-select.sh  | no prompt and no dispatch branch invokes roadmap-propose automatically         | `sed:s/roadmap-propose/ride-select/` in the suite's own corpus-scan expectation | pending |
| TEST-745 | Spec-AC-16 | integration | tests/skills/test-aai-layer-profiles.sh | the new .aai script is classified in PROFILES.yaml                           | `sed:s/roadmap-propose.mjs//` in .aai/system/PROFILES.yaml core list | pending |
| TEST-746 | Spec-AC-16 | integration | tests/skills/test-aai-prompt-diet.sh  | the AGENTS.md growth is ledgered and the TEST-012 pin moves from 37762         | `sed:s/JUSTIFIED_ADDITIONS+=( "<n> roadmap-takes-direction/JUSTIFIED_ADDITIONS+=( "0 roadmap-takes-direction/` in tests/skills/lib/prompt-diet-ledger.sh | pending |

Mutation-cell note: the token `006!!` stands for the two-character logical-or
operator in the sed expressions above. A literal pipe character inside a
Markdown table cell breaks `parseTestPlanTable`, and the escaped form has
corrupted AC tables in this repository before (docs/knowledge/LEARNED.md,
`spec-table-pipes-break-parser`). Implementation substitutes the operator when
it records the mutation with `mutation-run.mjs`, and the recorded expression is
what `mutation-gate.mjs` compares — the Mutation cell is reconciled to the
recorded text before close.

## Seams

| Seam | Producer | Consumer | Covered by |
|------|----------|----------|------------|
| S1   | roadmap-propose.mjs write/bind | ride-select.mjs validate, next, gate | TEST-738, TEST-739, TEST-742 |
| S2   | a capability-only pair in roadmap.yaml | nothing-left-behind.mjs readRoadmapPairs | TEST-717 |
| S3   | roadmap.yaml presence and gate refusals | orchestration-dispatch.mjs roadmapGate rule 4a | TEST-722, TEST-743 |
| S4   | docs/ai/decisions.jsonl follow-up registry | harvest observations and bind's backlog check | TEST-729, TEST-730, TEST-741 |
| S5   | docs/ai/friction observations spool and triage clusters | harvest friction candidates | TEST-735, TEST-736, TEST-737 |
| S6   | docs/issues frontmatter via docs-model parseFrontmatter | harvest intake candidates and blocks_in | TEST-724, TEST-731, TEST-732 |
| S7   | .aai/AGENTS.md corpus bytes | tests/skills/test-aai-prompt-diet.sh TEST-010 and TEST-012 | TEST-746 |
| S8   | a new .aai/** path | tests/skills/test-aai-layer-profiles.sh TEST-001 | TEST-745 |

S1 is crossed by producing a real file on one side and running the REAL
validator binary on the other — never a re-implemented parser. S2 and S3 are
crossed by executing the consumer script, not by asserting on the producer's
output shape.

## Residual risks

- R1 — Direction matching is token overlap, which is shallow. A sentence phrased
  in words no candidate uses scores 0 everywhere and the slate falls back to
  evidence order. Mitigated only by printing the matched tokens per candidate so
  the owner can see the sentence missed; not mitigated by the code.
- R2 — Friction contributes almost nothing today (3 review candidates over 824
  observations, measurement 7). The source is wired and tested but its live
  yield is near zero until the spool diversifies. Disclosed rather than fixed:
  raising the triage threshold or re-fingerprinting is `aai-feedback-triage.mjs`
  scope, not this ride's.
- R3 — `observations` and `blocks_in` are both 0 across the entire live corpus
  for the 13 draft intakes (measurement 8). Their ranking effect is proven by
  fixture movement, not by today's data. The inputs are live, the corpus is not
  yet.
- R4 — The maintenance slot can leak: nothing forces `bind` to be run before a
  maintenance ride starts, so an owner who takes one via `--override` consumes
  no slot. D3 chose a non-mutating gate over an enforced binding deliberately;
  the override was already the escape and stays logged.
- R5 — `age_days` reads git, so a shallow clone or an unborn branch yields
  `age unknown` for every candidate and the key goes flat. Degradation is
  printed, not silent.
- R6 — The relaxation in D2 makes `maintenance:` optional everywhere, including
  on a `done` pair. A hand-edited roadmap that DELETES a done pair's
  maintenance line now validates where it previously refused. Accepted: the
  budget's meaning is forward-looking, and `gate` never consults a done pair.

## Verification

- `bash tests/skills/test-aai-ride-select.sh` — exit 0.
- `bash tests/skills/test-aai-layer-profiles.sh` — exit 0.
- `bash tests/skills/test-aai-prompt-diet.sh` — exit 0.
- `bash tests/skills/test-aai-orchestration-dispatch.sh` — exit 0 (it reads
  `docs/ai/roadmap.yaml` through `roadmapGate`).
- `bash tests/skills/test-aai-nothing-left-behind.sh` — exit 0 (S2).
- `bash tests/skills/test-aai-golden-flow.sh` — exit 0 (it names the roadmap).
- `node .aai/scripts/ride-select.mjs validate` — exit 0, stdout unchanged.
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-DRAFT-spec-roadmap-takes-direction.md`
  — exit 0.
- `node .aai/scripts/check-vendored-script-deps.mjs` — CLEAN.
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal AND a RED record
  under `docs/ai/tdd/spec-roadmap-takes-direction/` for each of the 32 rows.

## Evidence contract

- ref_id: roadmap-takes-direction
- Per TEST-xxx: the `mutation-run.mjs` record at
  `docs/ai/tdd/spec-roadmap-takes-direction/mutation-<TEST-id>.txt`, carrying
  `verdict: RED` and the expression the Mutation cell declares.
- Per Spec-AC: the suite command above, its exit code, and the assertion text
  naming the observable.
- Review scope: the branch diff `main..feat/roadmap-takes-direction` over
  `.aai/scripts/roadmap-propose.mjs`, `.aai/scripts/ride-select.mjs`,
  `.aai/AGENTS.md`, `.aai/system/PROFILES.yaml`, `tests/skills/suite-map.yaml`,
  `tests/skills/test-aai-ride-select.sh`,
  `tests/skills/lib/prompt-diet-ledger.sh`.

### Evidence by strategy

Strategy `tdd`: a stored RED artifact per AC-gating test plus the full
verification matrix.

## Registry items closed by this scope

None.

Open items in the same neighbourhood, NOT CLOSED, and why:
- `fu-roadmap-pair-pinned-by-index` (P3) — its own remedy shipped in PR #393
  and whether that closes it is the owner's call on `ref_id`
  `update-installs-ref-guard-undisclosed`, not this scope's. This spec obeys
  the pattern it names: the Test Plan forbids pinning a live roadmap pair by
  index, and every new row runs against its own fixture.
- `fu-amend-roadmap-driven-ride-sele-1e2448` (P2) — an owner sign-off owed on a
  post-freeze amendment to `spec-roadmap-driven-ride-selection-with-budget`.
  Only the owner can discharge it.
