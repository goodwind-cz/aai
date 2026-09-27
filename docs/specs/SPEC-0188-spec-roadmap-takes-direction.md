---
id: spec-roadmap-takes-direction
type: spec
number: 188
status: done
mutation_gate: v1
frozen_sha256: b077e046f7862a20f7b905267c3f3d0e86dc37d523875de2c71e7bbd4c83ca7d
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0194-roadmap-takes-direction.md
  rfc: null
  pr:
    - TBD
  commits:
    - 62dc3085d958d7f8fcf2af292527cb63129f4f69
---

# Spec — the roadmap takes a direction from the owner instead of only refusing rides

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0194-roadmap-takes-direction.md
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
**D7 amendment (post-freeze, remediation round):** the intersection is over a
CONSERVATIVE suffix fold (`normalizeToken`), not the raw token — a
single-letter plural ("options" -> "option"), an `-ies` plural
("categories" -> "category") and a sibilant plural ("boxes" -> "box") are
folded to the same form on BOTH sides before matching. Measured live-corpus
defect this closes: `harvest --direction "decisions as menus"` scored 0
against `decision-menu-options-parser` under exact-token equality — an owner
who has to write the candidate's own exact singular tokens to score a match
does not need the ranking at all, which was the whole premise Spec-AC-07
exists to prove. Disclosed limits: no irregular plurals (child/children), no
derivational forms (decide/decision), no verb inflection (-ing/-ed), and a
handful of singular nouns that themselves end in one "s" (status, campus)
fold to a non-word and simply fail to match anything real — a false
NEGATIVE, never a false positive, the same shape of trade-off D7 already
accepted for the 4-character token floor. See spec_amendment
(docs/ai/decisions.jsonl, ref roadmap-takes-direction) and TEST-726.

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
**D10 amendment (post-freeze, run 3):** a picked candidate sourced (wholly or
partly) from `wave_2` is being PROMOTED into a real pair; leaving its old
`wave_2:` listing in place makes the SAME ref appear in both `pairs` and
`wave_2`, which the closed-shape validator refuses as a duplicate ref.
Measured live-corpus defect: running `write --pick` against a scratch copy of
the SHIPPED `docs/ai/roadmap.yaml`, picking the wave_2 slug
`standardized-backlog-drain`, reddened
`wave_2: "standardized-backlog-drain" appears twice in the roadmap` — found by
running against the live corpus (per this run's own mandate), not by the
fixtures TEST-715..737/747 wrote. `write` now also removes the promoted
slug's own line from `wave_2:` in the SAME edit
(`removeWave2Entries`), still inside the one write-or-rollback transaction.
This narrows Spec-AC-12's "every pre-existing byte is unchanged" to the
PREFIX its own verification actually checks (`head -n <N>`, which never
reaches the `wave_2:` section that follows the pairs list) — the `wave_2`
TAIL may legitimately lose exactly the promoted slug's own line. See
spec_amendment (docs/ai/decisions.jsonl, ref roadmap-takes-direction).

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

**D14 — a candidate id is deduplicated ACROSS sources, richest record wins,
every contributing source is named (post-freeze amendment).** Measured
live-corpus defect: `decision-menu-options-parser` was printed twice by one
`harvest` run — once `[intake]` (its own draft doc) and once `[wave_2]` (the
same slug, unpaired) — because D8's three sources were concatenated with no
id-uniqueness check. `mergeDuplicateCandidates` now collapses every group of
raw candidates sharing an `id` into ONE record before evaluation: the
richest duplicate (a resolved doc `path` outranks none; among two with the
same path-presence, the longer/more descriptive `label` wins) supplies the
kept `label`/`path`, and `source` becomes every contributing source,
comma-joined (`"intake,wave_2"`) — disclosed signal that the owner's menu
would otherwise have shown the same capability twice, never a silent drop of
one source. See spec_amendment (docs/ai/decisions.jsonl, ref
roadmap-takes-direction) and TEST-747.

**D15 — remediation round (validation round 1) amendments.** Independent
validation (docs/ai/tdd/spec-roadmap-takes-direction/validation-round1.txt)
found three BLOCKING defects and four non-blocking ones; this amendment
records the fixes.
- **D15a (BLOCKING-1, F2) — `write` now refuses a `--pick` with no
  `--direction`, and `harvest` prints stable row numbers.** `--pick` is a
  1-based index into the ranking `harvest` printed; `write` re-runs that same
  ranking rather than trusting a caller-supplied selection, so it is only
  safe when handed the EXACT sentence the owner's harvest was run with.
  `--direction` was optional on `write` (defaulting to `""`), so a directed
  harvest's row 1 could be silently written as a DIFFERENT candidate once
  `write` re-ranked with no direction at all — and `harvest`'s own rows
  carried no number for the owner to type in the first place. `write` now
  refuses (usage, exit 2, nothing written) unless `--direction` is given;
  every candidate `harvest` prints (text and `--json`) now carries its
  1-based `index` in the SAME ranked order `write`'s `candidates[pick-1]`
  indexes into. TEST-748..750.
- **D15b (BLOCKING-2, F1) — `bind` refuses a ref whose resolved document is a
  CAPABILITY type.** D13 proved only that a `--ref` comes "from the
  backlog" (an open follow-up id or a resolvable document); it never asked
  whether the resolved document is itself a capability
  (`CAPABILITY_TYPES` — D8's own exclusion, in reverse). Without this check a
  `type: change` intake — an owner decision the gate would otherwise route to
  the roadmap — could be bound straight into another capability's
  maintenance slot, consuming the 1:1 budget and admitting an unranked
  capability with no trace. TEST-751.
  - Considered and rejected: an EVENTS.jsonl append on `write`/`bind`
    mirroring `gate --override`. `--override` bypasses a refusal and needs a
    trace beyond the ride that follows it; `write`/`bind` are not a bypass —
    they are the feature, and their effect is already a byte-diffable,
    reviewed change to `docs/ai/roadmap.yaml` itself, which carries more
    information than an EVENTS line would (see the comment above `cmdWrite`
    in roadmap-propose.mjs for the full reasoning).
- **D15c (BLOCKING-3, F3) — the D10 amendment (`removeWave2Entries`) is now
  pinned by its own test.** The function shipped in run 3 with no Test Plan
  row; deleting its call left TEST-715..747 fully green because none of
  those fixtures promote a wave_2-sourced pick against a roadmap that still
  lists it in `wave_2`. TEST-752 closes that gap: it promotes a pure
  `wave_2` slug and asserts both that the pair is written AND that the old
  `wave_2:` line is gone, against the real validator.
- **D15d (non-blocking, F4) — `intakeCandidates` now excludes already-paired
  slugs**, mirroring `wave2Candidates`'s existing `pairSlugs` exclusion; an
  intake draft's `status` never changes on `write`, so without this a
  harvested-and-written capability kept reappearing in every later harvest —
  the steady state after the very first write. TEST-753.
- **D15e (non-blocking, F6) — the two refusals that name an unbound
  maintenance slot print `unbound`, never the literal word `null`.**
  `ride-select.mjs`'s pair-ahead and doc-missing refusals interpolate a
  pair's `maintenance` field directly; for a capability-only pair (D2) that
  field is JS `null`, which a template literal renders as the three
  characters `null`. TEST-754, TEST-755.
- **D15f (non-blocking, F7) — `write`'s success line discloses when it just
  created a project's first `docs/ai/roadmap.yaml`.** Creating the file (D12)
  switches `orchestration-dispatch.mjs`'s `roadmapGate()` on for every later
  ride in that project; the prior success line said nothing about it.
  TEST-756.
- **Disclosed, not fixed (non-blocking, F5) — `bind` still accepts an open
  follow-up id (D13's first arm) that no consumer can resolve as a
  document.** `ride-select.mjs gate` and `nothing-left-behind.mjs` both
  resolve a maintenance ref to a DOCUMENT id, so a follow-up-id-only bind
  produces a maintenance half the gate refuses and the close ceremony skips
  — the pair can then only finish via `--override`, the exact disease this
  ride exists to treat. Not fixed this round: the smallest correct remedy is
  teaching `gate`/`nothing-left-behind` a new resolvable-ref shape (a
  follow-up id), which is a change to two OTHER scripts' own read paths, not
  a "cheap" local fix in this scope. See R7.
- See docs/ai/tdd/spec-roadmap-takes-direction/validation-round1.txt for the
  full findings text and live-corpus reproductions this amendment answers.

**D16 — remediation round (validation round 2) amendment: D15b's discriminator
was the WRONG AXIS, and the roadmap itself is the right one.** Independent
validation (docs/ai/tdd/spec-roadmap-takes-direction/validation-round2.txt)
measured D15b's `CAPABILITY_TYPES.has(doc.type)` check against the owner's own
data and found it backwards in both directions:
- **B1 (blocking)** — 8 of the 11 maintenance halves on the SHIPPED
  `docs/ai/roadmap.yaml` are `type: change` documents — `CAPABILITY_TYPES`'s
  own majority member. Unbinding and re-binding any of them on a scratch copy
  was REFUSED as "a CAPABILITY type", and the gate's own printed remedy
  (`ride-select.mjs:335`) therefore failed for the commonest real maintenance
  shape in this repository, not an edge case.
- **B2 (blocking)** — the check was also a five-value denylist over an open
  set: 197 live document ids (spec/product/release-typed) resolve to a type
  in NEITHER `CAPABILITY_TYPES` nor `ride-select.mjs`'s own `MAINT_TYPES`, and
  every one of them still bound — defeated further by a trailing YAML comment
  on the type line (`type: change   # issue|change|rfc|spec`, a shape already
  present at `docs/rfc/RFC-0001-…:43`) and by a typeless intake.
`type:` is not where this factory records the capability/maintenance
distinction — the ROADMAP is: a slug is a capability because the OWNER put it
in a `capability:` slot. `bind` now refuses a `--ref` that already appears in
ANY pair's `capability:` slot (a closed set read from the same roadmap `gate`
itself reads, never a guess about an intake's frontmatter), and — decided and
defended here, not merely disclosed — also refuses a `--ref` already bound as
some OTHER pair's `maintenance:` half, because the SAME ref serving two
capabilities at once defeats the 1:1 budget exactly as a duplicate roadmap ref
would (`ride-select.mjs`'s own closed-shape parser already refuses that
shape; `bind` now names the reason itself instead of surfacing the parser's
generic "appears twice" error). `CAPABILITY_TYPES` remains in the file for
`intakeCandidates`' own D8 harvest-source exclusion (an unrelated, correctly
scoped use); it is no longer consulted anywhere in `cmdBind`. TEST-751
rewritten (a 3-pair fixture, refusing a ref that is a DIFFERENT pair's own
capability — N14: a check narrowed to one hardcoded capability name must not
pass); TEST-757 added (a spec-typed and a product-typed ref, neither a
roadmap capability, are both admitted — B2's denylist is gone, not merely
narrowed); TEST-758 added (a ref already bound as another pair's maintenance
half is refused).
- **NB-3 fixed as a consequence.** The gate's off-roadmap maintenance refusal
  advertises a `bind` command (`ride-select.mjs:335`); round 1's type check
  made that command always fail for a `type: change` intake the gate itself
  classifies as maintenance by title/ref words (`isMaintenance`). Since `bind`
  no longer consults `doc.type` at all, the two scripts' classifications can
  no longer disagree. TEST-759 runs the gate's own advertised remedy
  end-to-end and asserts it succeeds.
- **NB-4 fixed at the root, not merely disclosed for `bind`.** The old check's
  answer depended on `resolveDoc`'s first-walk-match order for an id carried
  by two documents (19 live ids measured); `lib/docs-model.mjs` `walk()` now
  sorts each directory's entries by name before recursing, so every
  first-match consumer built on it (not only `bind`) is deterministic across
  machines and filesystems. `bind`'s OWN exposure to this is additionally
  moot by construction: its capability/maintenance decision no longer reads
  `doc.type` (or anything else about WHICH duplicate resolved) at all — only
  roadmap membership. Not separately mutation-pinned: filesystem enumeration
  order cannot be forced deterministically from a portable shell test without
  OS-specific fixtures, and the specific decision it used to influence no
  longer exists to redden.
- **NB-6 fixed.** `ride-select.mjs next` proposed a pair's bound maintenance
  ref even when it resolved to no document under `--docs` (e.g. bound from an
  open follow-up id, D13's first backlog arm, per R7) — handing an autonomous
  loop a ref `gate` immediately refuses, forever: a LIVELOCK, not merely R7's
  "can only finish via `--override`". `nextRide` now checks the same
  `findDoc` resolution `gate`'s own off-roadmap arm uses before proposing a
  bound maintenance ref, and proposes filing its intake instead when nothing
  resolves (`action: 'file-intake'`, mirroring the existing `action: 'bind'`
  shape for an unbound slot). TEST-760. R7's own text is otherwise
  unchanged — the disclosed design point it describes (a follow-up-id-only
  bind still needs `--override` to finish once its intake IS filed and gate
  still won't resolve a follow-up id as a document) stands; only the
  LIVELOCK (never reaching that point because `next` kept re-offering the
  same dead ref) is closed.
- **N15/NB-1 pinned.** `removeWave2Entries`'s own `ids.has(wm[1])` check can
  be narrowed to "any wave_2 line" without reddening TEST-752, because its
  fixture carried exactly one wave_2 entry — deleting every row and deleting
  only the promoted row are indistinguishable there. Live consequence
  (round 2): promoting one wave_2 slug on a scratch copy of the SHIPPED
  roadmap emptied all four of the owner's deferred wave_2 items and
  `validate` still reported OK. TEST-761 widens the fixture to three wave_2
  entries and asserts the two untouched ones survive the promotion.
- See docs/ai/tdd/spec-roadmap-takes-direction/validation-round2.txt for the
  full findings text, the live-corpus reproductions this amendment answers,
  and the mutation probes (N1..N17) it ran.

**D17 — remediation round (validation round 3) amendment: NB-1 fixed, NB-2
disclosed.** Independent validation (docs/ai/tdd/spec-roadmap-takes-direction/
validation-round3.txt) returned PASS with 0 blocking findings — the round 2
remediation is merge-ready — and recommended taking the two non-blocking
findings an owner actually meets now, filing the rest as follow-ups.
- **NB-1 fixed.** D16's NB-6 fix (`findDoc` gating a proposed maintenance ref
  before `next` offers it) covered the maintenance half only; the CAPABILITY
  half (`ride-select.mjs:157`) still returned a pair's capability ref
  unconditionally once its status was not STARTED, even when NO document
  resolved for it at all. This ride's own `write` promotes a wave_2 or
  friction candidate straight into a `capability:` slot with no document
  filed yet far more often than it binds a documentless maintenance ref
  (round 3 measured: 3 of the 4 live wave_2 slugs and every friction
  candidate have no document), so this was the FIRST dead end an owner
  actually met, not a rare edge — validation demonstrated it live end to end
  with `cloud-morning-digest`. `nextRide` now runs the SAME `findDoc`
  resolution before returning a capability ref, and proposes filing its
  intake instead (`action: 'file-intake', half: 'capability'`), mirroring the
  existing maintenance-half shape; the human-text rendering distinguishes the
  two halves so the message never claims a capability ref was "bound as the
  maintenance half of" itself. TEST-762 pins it.
- **NB-2 disclosed, not fixed.** The surviving consequence of D16's B2
  removal — `bind` still accepts any backlog ref, so `gate`'s off-roadmap "an
  owner decision" refusal is answerable by binding that ref into an unbound
  maintenance slot — was reasoned in D16 and asserted by TEST-757, but was
  absent from Residual risks. Added as R8, in the owner's own words, naming
  the roadmap diff in the PR as the real control.
- NB-3..NB-6 (TEST-760's narrow fixture, `bind`'s wave_2-axis reason quality,
  F4's one-sided harvest/write exclusion, a stale `resolveDoc` comment/field)
  are disclosed, not fixed, and tracked as follow-ups against this spec
  rather than folded into this amendment — round 3's own recommendation: none
  of them is worth splitting the ride for.
- See docs/ai/tdd/spec-roadmap-takes-direction/validation-round3.txt for the
  full findings text and the live-corpus reproduction (harvest -> write ->
  next against a scratch copy of the shipped roadmap) this amendment answers.

## Constitution deviations

None.

## Acceptance Criteria Mapping

- Maps to: docs/issues/CHANGE-0194-roadmap-takes-direction.md "Desired Behavior"

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
  all four ranking components by name, and the candidate SET carries no
  duplicate id (D14 amendment).
  - Verification: `node .aai/scripts/roadmap-propose.mjs harvest --direction
    "<sentence>" --json` exits 0 and every element of `candidates` carries
    non-null `source`, `label`, `direction`, `direction_tokens`,
    `observations`, `blocks_in` and `age_days`; over a fixture where one id is
    both an intake draft AND an unpaired wave_2 slug, exactly one candidate
    with that id is printed and its `source` names both contributing sources
    (TEST-747).
- Spec-AC-07: WHEN the direction sentence changes so that it shares
  (suffix-folded, D7 amendment) tokens with candidate B instead of candidate A
  THEN B's rank rises above A's.
  - Verification: two `harvest --json` runs over the SAME fixture with two
    different `--direction` values; `candidates[0].id` is A in the first run
    and B in the second, and B's `direction` value differs between them. The
    sentences use the ORDINARY plural of each candidate's own singular token
    (never the candidate's exact word), so a regression to exact-token
    equality reddens TEST-726.
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
  follow-up nor a resolvable document, OR that already appears in the
  roadmap's own `capability:` slots, OR that is already bound as another
  pair's `maintenance:` half, THEN it exits 1 and writes nothing (D16
  supersedes D15b's document-`type` axis with the roadmap's own
  capability/maintenance slots, measured wrong in both directions by
  validation round 2 B1/B2); when the ref clears all three checks, exactly
  one `maintenance:` line is added to the named pair and the real validator
  accepts the result.
  - Verification: runs of `node .aai/scripts/roadmap-propose.mjs bind
    --capability <slug> --ref <r>` against a fixture; a ref neither an open
    follow-up nor resolvable exits 1 with `cmp` clean (TEST-741); a ref that
    IS another pair's own `capability:` slug exits 1 naming "roadmap
    CAPABILITY" (TEST-751); a ref already bound as another pair's
    `maintenance:` half exits 1 naming that pair (TEST-758); a `type: change`
    ref that is none of those, or a `spec`/`product`-typed one, exits 0,
    `grep -c '^    maintenance:' <copy>` rises by exactly 1, and
    `ride-select.mjs validate --roadmap <copy>` exits 0 (TEST-751, TEST-757).
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
| Spec-AC-01 | WHEN a pair carries no maintenance line the validator SHALL accept the roadmap                  | done | TEST-715, TEST-716, TEST-717, TEST-754, TEST-755 green; `bash tests/skills/test-aai-ride-select.sh` exit 0 | —         | D2, D15e |
| Spec-AC-02 | WHEN the shipped roadmap is validated after the relaxation it SHALL report the identical summary | done | TEST-718 green; `node .aai/scripts/ride-select.mjs validate` exit 0, stdout `roadmap OK: 11 pair(s), 4 wave-2 item(s)` | —         | regression proof for D2 |
| Spec-AC-03 | WHEN next reaches a started capability with an unbound slot it SHALL propose the bind command    | done | TEST-719, TEST-720, TEST-760, TEST-762 green | —         | D4, D16 (NB-6), D17 (NB-1) |
| Spec-AC-04 | WHEN next finds no unfinished pair it SHALL offer the harvest command                            | done | TEST-721 green | —         | D5    |
| Spec-AC-05 | WHEN gate refuses an off-roadmap maintenance ref it SHALL name the bind command and stay exit 1  | done | TEST-722, TEST-759 green | —         | D3, D16 (NB-3) |
| Spec-AC-06 | WHEN harvest runs every candidate SHALL print its source and all four ranking components, and the set SHALL carry no duplicate id | done | TEST-723, TEST-724, TEST-725, TEST-747, TEST-748, TEST-753 green; `bash tests/skills/test-aai-ride-select.sh` exit 0 | —         | D6 D9 D14 D15a D15d |
| Spec-AC-07 | WHEN the direction sentence changes the matching candidate SHALL rise in rank                    | done | TEST-726, TEST-727, TEST-728 green (MOVEMENT); TEST-726 re-pinned to a suffix-fold-specific mutation and its fixture rewritten to a natural plural sentence (remediation round, D7 amendment) | —         | movement proof, D7 |
| Spec-AC-08 | WHEN an open follow-up naming a candidate is added that candidate SHALL rise in rank             | done | TEST-729, TEST-730 green (MOVEMENT) | —         | movement proof, D9 |
| Spec-AC-09 | WHEN a non-terminal document blocking a candidate is added that candidate SHALL rise in rank     | done | TEST-731, TEST-732 green (MOVEMENT) | —         | movement proof, D9 |
| Spec-AC-10 | WHEN candidates tie on every earlier key the older candidate SHALL rank first                    | done | TEST-733, TEST-734 green (MOVEMENT) | —         | movement proof, D9 |
| Spec-AC-11 | WHEN friction contributes it SHALL contribute only review candidates under a readable label      | done | TEST-735, TEST-736, TEST-737 green | —         | D8, measurement 7 |
| Spec-AC-12 | WHEN write runs the appended roadmap SHALL be accepted by the real validator with prior bytes intact | done | TEST-738, TEST-739, TEST-748, TEST-749, TEST-750, TEST-752, TEST-761 green; real write/bind run against a scratch copy of the shipped roadmap (see report) | —         | D10, D10 amendment, D15a, D15c, D16 (N15) |
| Spec-AC-13 | WHEN the appended roadmap would not validate the original bytes SHALL be restored and the run refuse | done | TEST-740 green | —         | D10   |
| Spec-AC-14 | WHEN bind names a ref that is not in the backlog, or that is already a roadmap capability, or that is already bound elsewhere, it SHALL refuse and write nothing | done | TEST-741, TEST-742, TEST-751, TEST-757, TEST-758 green | —         | D13, D16 (supersedes D15b's doc-type axis) |
| Spec-AC-15 | WHEN a project has not opted in no file, no gate and no prompt SHALL change                       | done | TEST-743, TEST-744, TEST-756 green | —         | D11 D12 D15f |
| Spec-AC-16 | WHEN the companion obligations are checked the new file SHALL be classified and the corpus ledgered | done | TEST-745, TEST-746 green; `bash tests/skills/test-aai-layer-profiles.sh` and `bash tests/skills/test-aai-prompt-diet.sh` exit 0 | —         | PROFILES + prompt diet |

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
| TEST-723 | Spec-AC-06 | integration | tests/skills/test-aai-ride-select.sh  | harvest --json emits source, label, direction, direction_tokens, observations, blocks_in and age_days on every candidate | `sed:s/blocks_in: blocksIn,//` in roadmap-propose.mjs candidate serializer  | done |
| TEST-724 | Spec-AC-06 | integration | tests/skills/test-aai-ride-select.sh  | harvest draws intake candidates only from draft docs whose type is in the capability set | `sed:s/CAPABILITY_TYPES.has\(fm.type\)/true/` in roadmap-propose.mjs intake source (reconciled: unescaped parens are a JS regex GROUP, not literal — the declared cell never matched the source) | done |
| TEST-725 | Spec-AC-06 | integration | tests/skills/test-aai-ride-select.sh  | harvest draws wave_2 slugs that are not already pairs                          | `sed:s/!pairSlugs.has\(slug\)/true/` in roadmap-propose.mjs wave2 source (reconciled: same unescaped-paren defect as TEST-724) | done |
| TEST-726 | Spec-AC-07 | integration | tests/skills/test-aai-ride-select.sh  | MOVEMENT — two directions, each the ORDINARY PLURAL of a fixture candidate's own singular token (never its exact word), swap the top candidate and change its direction count | `sed:s/return tok.slice\(0, -1\);/return tok;/` in roadmap-propose.mjs normalizeToken (D7 amendment: re-pinned from the pre-amendment `sed:s/shared.size/0/`, which zeroed matching entirely rather than specifically reverting the plural fold to exact equality) | done |
| TEST-727 | Spec-AC-07 | integration | tests/skills/test-aai-ride-select.sh  | direction is the PRIMARY sort key — a lower-evidence candidate that matches the sentence outranks a higher-evidence one that does not | `sed:s/b.direction - a.direction \|\|//` in roadmap-propose.mjs comparator (006!! resolved to the real escaped operator per the Mutation-cell note; `splitTableCells`'s `(?<!\\)\|` honors the escape) | done |
| TEST-728 | Spec-AC-07 | unit        | tests/skills/test-aai-ride-select.sh  | stopwords and tokens under 4 characters never count as a direction match       | `sed:s/tok.length >= 4/tok.length >= 1/` in roadmap-propose.mjs tokenize    | done |
| TEST-729 | Spec-AC-08 | integration | tests/skills/test-aai-ride-select.sh  | MOVEMENT — adding one open follow-up naming candidate B raises its observations 0 to 1 and lowers its index | `sed:s/b.observations - a.observations \|\|//` in roadmap-propose.mjs comparator (006!! resolved, as TEST-727) | done |
| TEST-730 | Spec-AC-08 | integration | tests/skills/test-aai-ride-select.sh  | a CLOSED follow-up naming candidate B does not raise its observations         | `sed:s/it.status === 'open'/true/` in roadmap-propose.mjs openFollowUpCount | done |
| TEST-731 | Spec-AC-09 | integration | tests/skills/test-aai-ride-select.sh  | MOVEMENT — adding a non-terminal document with blocks naming B raises blocks_in 0 to 1 and lowers its index | `sed:s/b.blocks_in - a.blocks_in \|\|//` in roadmap-propose.mjs comparator (006!! resolved, as TEST-727) | done |
| TEST-732 | Spec-AC-09 | integration | tests/skills/test-aai-ride-select.sh  | a TERMINAL document blocking B does not raise its blocks_in                    | `sed:s/!TERMINAL_DOC_STATUS.has\(st\)/true/` in roadmap-propose.mjs blocksInCount (reconciled: same unescaped-paren defect as TEST-724) | done |
| TEST-733 | Spec-AC-10 | integration | tests/skills/test-aai-ride-select.sh  | MOVEMENT — with every earlier key tied the older first-commit date ranks first | `sed:s/b.age_days - a.age_days \|\|//` in roadmap-propose.mjs comparator   | done |
| TEST-734 | Spec-AC-10 | integration | tests/skills/test-aai-ride-select.sh  | an untracked candidate reports age_days 0 and the literal note age unknown     | `sed:s/age unknown//` in roadmap-propose.mjs ageDays                        | done |
| TEST-735 | Spec-AC-11 | integration | tests/skills/test-aai-ride-select.sh  | only review_candidate clusters become friction candidates                      | `sed:s/c.decision === 'review_candidate'/true/` in roadmap-propose.mjs frictionCandidates | done |
| TEST-736 | Spec-AC-11 | integration | tests/skills/test-aai-ride-select.sh  | a friction label carries skill_id and failure_class and no v1 fingerprint hash appears in the output | `sed:s/const id = frictionLabel\(row\);/const id = c.fingerprint;/` in roadmap-propose.mjs frictionCandidates (reconciled: the bare `frictionLabel(row)` text also matches the function's own definition line, which the naive substitution corrupts into invalid syntax before the usage site is ever reached — narrowed to the one assignment site) | done |
| TEST-737 | Spec-AC-11 | integration | tests/skills/test-aai-ride-select.sh  | an empty or absent spool yields zero friction candidates, exit 0 and one NOTE line | `sed:s/spool is empty/ /` in roadmap-propose.mjs frictionCandidates        | done |
| TEST-747 | Spec-AC-06 | integration | tests/skills/test-aai-ride-select.sh  | D14 amendment — a candidate id reachable from both an intake draft and an unpaired wave_2 slug contributes exactly ONE candidate, its source naming both | `sed:s/const raw = mergeDuplicateCandidates\(rawAll\);/const raw = rawAll;/` in roadmap-propose.mjs buildCandidates | done |
| TEST-738 | Spec-AC-12 | integration | tests/skills/test-aai-ride-select.sh  | write appends planned capability-only pairs, leaves prior bytes identical, and the REAL validator accepts | `sed:s/status: planned/status: active/` in roadmap-propose.mjs pair emitter | done |
| TEST-739 | Spec-AC-12 | integration | tests/skills/test-aai-ride-select.sh  | the certification runs ride-select.mjs validate as a child process, proven by a shim recording its own argv | `sed:s/'validate', '--roadmap'/'next', '--roadmap'/` in roadmap-propose.mjs certify | done |
| TEST-740 | Spec-AC-13 | integration | tests/skills/test-aai-ride-select.sh  | a refused certification restores the original bytes, exits 1 and prints the validator stderr | `sed:s/fs\.writeFileSync\(target, original\);//` in roadmap-propose.mjs rollback (reconciled: unescaped parens are a JS regex GROUP, not literal — the declared cell never matched the source, same class as TEST-724) | done |
| TEST-741 | Spec-AC-14 | integration | tests/skills/test-aai-ride-select.sh  | bind refuses a ref that is neither an open follow-up nor a resolvable document and writes nothing | `sed:s/if \(!openIds\.has\(a\.ref\) && !doc\)/if (false)/` in roadmap-propose.mjs bind (reconciled: the shipped check reads `openIds`/`doc` and `&&`, not the `ref`/`findDoc`/006!! placeholder text the cell's draft used before the code existed) | done |
| TEST-742 | Spec-AC-14 | integration | tests/skills/test-aai-ride-select.sh  | bind adds exactly one maintenance line to the named pair, the real validator accepts, and a same-pair re-bind is refused by name (not merely by certify() catching a duplicate maintenance: line) | `sed:s/pair\.maintenance !== null/false/` in roadmap-propose.mjs bind slot check | done |
| TEST-743 | Spec-AC-15 | integration | tests/skills/test-aai-ride-select.sh  | harvest in a tree with no roadmap exits 0 and creates no docs/ai/roadmap.yaml; write with zero harvested candidates exits 1 and creates none either | `sed:s/if \(!candidates\.length\) refuse/if (false) refuse/` in roadmap-propose.mjs write (reconciled: same unescaped-paren defect as TEST-724/TEST-740) | done |
| TEST-744 | Spec-AC-15 | integration | tests/skills/test-aai-ride-select.sh  | no prompt and no dispatch branch invokes roadmap-propose automatically         | `sed:s/SCAN_PATTERN='roadmap-propose'/SCAN_PATTERN='ride-select'/` in the suite's own corpus-scan expectation (reconciled: the scan pattern lives in its own variable, never a bare inline string, so a mutation of it is unambiguous — target is the suite file itself) | done |
| TEST-745 | Spec-AC-16 | integration | tests/skills/test-aai-layer-profiles.sh | the new .aai script is classified in PROFILES.yaml                           | `sed:s/roadmap-propose.mjs//` in .aai/system/PROFILES.yaml core list | done |
| TEST-746 | Spec-AC-16 | integration | tests/skills/test-aai-prompt-diet.sh  | the AGENTS.md growth is ledgered and the TEST-012 pin moves from 37762         | `sed:s/JUSTIFIED_ADDITIONS\+=\( "100 roadmap-takes-direction/JUSTIFIED_ADDITIONS+=( "0 roadmap-takes-direction/` in tests/skills/lib/prompt-diet-ledger.sh (reconciled: the shipped credit measured 100 B, not a placeholder `<n>`) | done |
| TEST-748 | Spec-AC-06, Spec-AC-12 | integration | tests/skills/test-aai-ride-select.sh  | D15a (validation round 1 F2) — harvest prints stable 1-based row numbers, and write --pick N writes exactly the Nth-ranked candidate off that ranking, never row 1 | `sed:s/c\.index = i \+ 1;/c.index = 1;/` in roadmap-propose.mjs buildCandidates | done |
| TEST-749 | Spec-AC-12 | integration | tests/skills/test-aai-ride-select.sh  | D15a (F2) — write refuses (usage, exit 2) when --direction is omitted, and writes nothing | `sed:s/!a\.direction\) usage\(/false) usage(/` in roadmap-propose.mjs parseArgs | done |
| TEST-750 | Spec-AC-12 | integration | tests/skills/test-aai-ride-select.sh  | D15a (F2) — the same --pick 1 writes a different candidate when --direction changes, proving the sentence's VALUE drives the ranking write uses | `sed:s/direction: a\.direction, docsDir/direction: '', docsDir/` in roadmap-propose.mjs buildCandidates | done |
| TEST-751 | Spec-AC-14 | integration | tests/skills/test-aai-ride-select.sh  | D16 (round 2 B1/N14) — bind refuses a ref that is already a roadmap CAPABILITY on ANY pair (not just the one being bound into), and still accepts a type:change ref that is not one (the 8-of-11 majority shape round 1's type check wrongly refused) | `sed:s/if \(roadmapCapabilities\.has\(a\.ref\)\) {/if (false) {/` in roadmap-propose.mjs cmdBind | done |
| TEST-752 | Spec-AC-12 | integration | tests/skills/test-aai-ride-select.sh  | D15c (F3) — write promoting a wave_2-sourced pick removes the slug from wave_2 and the real validator accepts (pins the D10 amendment's removeWave2Entries, shipped in run 3 with no test) | `sed:s/const baseText = original === null \? null : removeWave2Entries\(original, promotedFromWave2\);/const baseText = original;/` in roadmap-propose.mjs cmdWrite | done |
| TEST-753 | Spec-AC-06 | integration | tests/skills/test-aai-ride-select.sh  | D15d (F4) — harvest excludes an intake draft whose id is already a roadmap capability pair | `sed:s/if \(pairSlugs\.has\(fm\.id\)\) continue;//` in roadmap-propose.mjs intakeCandidates | done |
| TEST-754 | Spec-AC-01 | integration | tests/skills/test-aai-ride-select.sh  | D15e (F6) — the pair-ahead refusal names an unbound maintenance slot as unbound, never the literal word null | `sed:s/ahead\.maintenance \|\| 'unbound'/ahead.maintenance/` in ride-select.mjs gate (pair-ahead deny) | done |
| TEST-755 | Spec-AC-01 | integration | tests/skills/test-aai-ride-select.sh  | D15e (F6) — the doc-missing refusal names an unbound maintenance slot as unbound, never the literal word null | `sed:s/pair\.maintenance \|\| 'unbound'/pair.maintenance/` in ride-select.mjs gate (doc-missing deny) | done |
| TEST-756 | Spec-AC-15 | integration | tests/skills/test-aai-ride-select.sh  | D15f (F7) — write against a project with no roadmap discloses in its success line that the ride gate is now on | `sed:s/const gateNote = existed \? '' :/const gateNote = true ? '' :/` in roadmap-propose.mjs cmdWrite | done |
| TEST-757 | Spec-AC-14 | integration | tests/skills/test-aai-ride-select.sh  | D16 (round 2 B2) — bind admits a spec-typed and a product-typed ref that are not roadmap capabilities: the type denylist is gone, not merely narrowed to a different set | `sed:s/const roadmapCapabilities = new Set\(pairs\.map\(\(p\) => p\.capability\)\);/if (doc && doc.type === 'spec') refuse('type denylist reintroduced'); const roadmapCapabilities = new Set(pairs.map((p) => p.capability));/` in roadmap-propose.mjs cmdBind | done |
| TEST-758 | Spec-AC-14 | integration | tests/skills/test-aai-ride-select.sh  | D16 (decide-and-defend addition) — bind refuses a ref already bound as another pair's maintenance half (one ref cannot serve two capabilities under the 1:1 budget) | `sed:s/if \(boundElsewhere\) {/if (false) {/` in roadmap-propose.mjs cmdBind | done |
| TEST-759 | Spec-AC-05, Spec-AC-14 | integration | tests/skills/test-aai-ride-select.sh  | D16 (NB-3) — the bind command the gate's off-roadmap maintenance refusal advertises actually succeeds for a type:change intake the gate itself classifies as maintenance by ref/title | `sed:s/const roadmapCapabilities = new Set\(pairs\.map\(\(p\) => p\.capability\)\);/if (doc && doc.type === 'change') refuse('type denylist reintroduced'); const roadmapCapabilities = new Set(pairs.map((p) => p.capability));/` in roadmap-propose.mjs cmdBind | done |
| TEST-760 | Spec-AC-03 | integration | tests/skills/test-aai-ride-select.sh  | D16 (NB-6) — next never proposes a bound maintenance ref that resolves to no document; it proposes filing the intake instead (closes the livelock R7 named) | `sed:s/if \(!findDoc\(docsDir, pr\.maintenance\)\) {/if (false) {/` in ride-select.mjs nextRide | done |
| TEST-761 | Spec-AC-12 | integration | tests/skills/test-aai-ride-select.sh  | D16 (NB-1/N15) — promoting one wave_2 slug leaves every OTHER wave_2 entry in place (a widened, 3-entry fixture; the single-entry TEST-752 fixture could not distinguish "delete the promoted row" from "delete every row") | `sed:s/if \(wm && ids\.has\(wm\[1\]\)\) continue;/if (wm) continue;/` in roadmap-propose.mjs removeWave2Entries | done |
| TEST-762 | Spec-AC-03 | integration | tests/skills/test-aai-ride-select.sh  | validation-round3 NB-1 — next never proposes a CAPABILITY ref with no resolvable document (the same livelock TEST-760/NB-6 closed on the maintenance half only — this ride's own write promotes a wave_2 or friction candidate straight into a capability slot with no document far more often) | `sed:s/if \(!findDoc\(docsDir, pr\.capability\)\) {/if (false) {/` in ride-select.mjs nextRide | done |

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
  Remediation-round narrowing (D7 amendment): the overlap now folds a
  conservative plural suffix (options/option, categories/category, boxes/box)
  so an ORDINARY sentence reaches a candidate written in the singular — the
  original defect (exact-token equality required the owner to already know
  the candidate's own slug words) is closed, but the remaining shallowness
  (no synonyms, no derivational forms, no irregular plurals) is unchanged and
  still falls back to evidence order exactly as before.
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
- R7 (D15, disclosed not fixed, validation round 1 F5; LIVELOCK closed by D16,
  validation round 2 NB-6) — `bind` accepts an open follow-up id as a
  maintenance ref (D13's first arm), but `ride-select.mjs gate` and
  `nothing-left-behind.mjs` both resolve a maintenance ref to a DOCUMENT id,
  never a follow-up id. A pair bound this way is refused by `gate` and
  skipped by the close ceremony — it can then only be finished with
  `--override`, the same disease this ride exists to treat. The smallest
  correct remedy touches two OTHER scripts' own ref-resolution paths, not a
  local fix here; tracked as an open item for a future ride, not this one's
  own follow-up ledger (that would blur who owns the fix). D16 closes the
  LIVELOCK this residual's own shape enabled: `next` no longer re-proposes
  the same unresolvable ref forever — it proposes filing the intake instead
  (TEST-760) — but the underlying disclosed gap (a follow-up-id-only bind
  still needs `--override` to finish, even once its intake is filed) is
  unchanged and still belongs to a future ride.
- R8 (validation round 3 NB-2) — `bind` still accepts any backlog ref into an
  unbound maintenance slot, so `gate`'s off-roadmap "an owner decision"
  refusal is answerable by binding that ref into a pair whose capability is
  already implementing: `gate` REFUSES, `bind` converts the refusal into an
  ADMIT in one command, then `gate` ADMITS the same ref as that pair's
  maintenance half. This is round 1's F1 and round 2's B2 residual,
  deliberately not re-closed: D16 established that no reliable discriminator
  exists — document `type:` is the wrong axis, and `ride-select.mjs`'s own
  `isMaintenance` heuristic would misclassify the roadmap's own halves — and
  TEST-757 asserts the permissive behaviour as intended, not merely
  unfixed. The control is the roadmap diff in the PR, not the gate:
  `docs/ai/roadmap.yaml` is tracked, not gitignored, so the bind is a
  reviewable commit; `nothing-left-behind.mjs` counts an uncommitted roadmap
  as `files_left`; `SKILL_PR` resets out-of-scope staging before a PR opens.
  The gate is also narrower than it first appears: the host pair must be
  first-unfinished AND its capability already started — the same bind against
  an unstarted capability ends at "pair first ... is not filed", and against
  a not-first pair at "pair ahead".

## Verification

- `bash tests/skills/test-aai-ride-select.sh` — exit 0.
- `bash tests/skills/test-aai-layer-profiles.sh` — exit 0.
- `bash tests/skills/test-aai-prompt-diet.sh` — exit 0.
- `bash tests/skills/test-aai-orchestration-dispatch.sh` — exit 0 (it reads
  `docs/ai/roadmap.yaml` through `roadmapGate`).
- `bash tests/skills/test-aai-nothing-left-behind.sh` — exit 0 (S2).
- `bash tests/skills/test-aai-golden-flow.sh` — exit 0 (it names the roadmap).
- `node .aai/scripts/ride-select.mjs validate` — exit 0, stdout unchanged.
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0188-spec-roadmap-takes-direction.md`
  — exit 0.
- `node .aai/scripts/check-vendored-script-deps.mjs` — CLEAN.
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal AND a RED record
  under `docs/ai/tdd/spec-roadmap-takes-direction/` for each of the 47 rows
  (42 — 33 plus TEST-747 from the D14 remediation amendment, plus TEST-748..756
  from the D15 remediation amendment answering validation-round1.txt — plus
  TEST-757..761, added by the D16 remediation amendment answering
  validation-round2.txt).

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
