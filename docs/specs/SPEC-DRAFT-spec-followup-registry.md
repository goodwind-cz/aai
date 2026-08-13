---
id: spec-followup-registry
type: spec
number: null
status: implementing
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0142-followup-registry.md
  rfc: null
  pr: []
  commits: []
---

# Spec — typed, queryable follow-up registry on the existing decision ledger

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0142-followup-registry.md
- Ledger this scope extends (no new store): docs/ai/decisions.jsonl
- The one pre-existing typed entry (the schema seed): docs/ai/decisions.jsonl line 92, 2026-08-11T05:20:00Z, ref telemetry-completeness
- Append discipline reused: .aai/scripts/append-event.mjs (auto-filled v/ts/actor, single `fs.appendFileSync` line write) and .aai/scripts/learned-append.mjs (pure-append structural gate, atomic write)
- Fail-closed ledger reader that constrains us: .aai/scripts/routine-emit.mjs `checkAuthorization` (any malformed non-comment line poisons the WHOLE ledger)
- Other decisions.jsonl consumers: .aai/scripts/aai-doctor.mjs CAT-07 (entry count), .aai/scripts/metrics-flush.mjs PROTECTED set
- Report surface chosen: .aai/scripts/generate-factory-report.mjs (+ docs/ai/factory-report-data.json); regenerated at every close by close-work-item.mjs `regenerateFactoryReportBestEffort()`
- Report surface NOT chosen: .aai/scripts/generate-overview.mjs (see D4)
- Emission surface (the only prompt-corpus byte spent): .aai/SKILL_CODE_REVIEW.prompt.md "WARNINGS POLICY WITH TEETH" clause (b)
- Pin that constrains that reword: tests/skills/test-aai-hygiene-pack.sh test_014 (literals `docs/ai/decisions.jsonl`, `follow-up ref`, `conditional`)
- Prompt-diet governance: tests/skills/lib/prompt-diet-ledger.sh + tests/skills/test-aai-prompt-diet.sh (TEST-012 checkpoint currently -6044, headroom 1622/2048, HEADROOM_CAP 2048)
- Layer classification: .aai/system/PROFILES.yaml (pinned by tests/skills/test-aai-layer-profiles.sh TEST-001)
- CI selection map: tests/skills/suite-map.yaml (row required per tests/skills/test-aai-hygiene-pack.sh AC-003 pin)
- Product doc (capability `aai-decisions`, per the intake frontmatter): docs/product/aai-decisions.md
- Product doc kept truthful for the changed surface: docs/product/factory-performance-report.md
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, zero network, canonical test invocation)
- External lesson applied to id design: github/spec-kit#4065 (dense sequential ids force renumbering, which invalidates every existing citation)

Ceremony justification: level 2 (Planning RAISES the intake's declared level 1
— recorded here rather than silently). The scope is not a single-surface fix:
it adds a new `.aai/**` executable, appends 14 lines to a telemetry ledger that
`routine-emit.mjs` reads FAIL-CLOSED over its entire contents, changes a
generator, and moves prompt-corpus bytes. No `protected_paths_l3` path is
touched (checked against the live list: state.mjs, lib/state-engine.mjs,
lib/state-core.mjs, allocate-doc-number.mjs, pre-commit-checks.sh/.ps1,
.aai/workflow/WORKFLOW.md, docs/CONSTITUTION.md — none in scope), so level 3 is
not owed. Level 2 is the honest default; the owner may direct level 1 and the
lane will prune accordingly. Every Test Plan row below names a directly
executable local command regardless of level.

## Summary

Measured today, on this branch: `docs/ai/decisions.jsonl` holds 95 JSON entries
and exactly ONE with `"type": "follow_up"` — while 14 distinct FOLLOW-UP
clauses sit buried in the free-text `decision` field of 11
`review_nb_disposition` entries spanning 10 refs (CHANGE-0128, -0129, -0130,
-0131, -0135 x5, -0137 x2, -0139 x2, -0140), six of them created on 2026-08-13
alone. Nothing in `.aai/scripts` can list them.

The cost is already paid and evidenced: the "regenerate the generated pages
AFTER the allocator renames the spec" lesson was recorded as prose in the
CHANGE-0140 disposition and then repeated verbatim as a defect during
CHANGE-0141 — a recorded lesson nothing could surface.

This scope adds the smallest thing that closes that loop and nothing more: a
typed entry shape on the ledger that already exists, one deterministic CLI that
folds and lists it, a backfill that appends and never rewrites, and one
read-only block in the report that already regenerates itself at every close.

THE HARD CONSTRAINT (owner-stated, first-class design force): per-ride token
cost must not rise. No new agent, no new LLM step, no new mandatory prompt
reading. Every decision below that could have traded tokens for elegance was
resolved toward tokens — see D2 (a helper instead of hand-authored JSON,
because it is FEWER emitted tokens, not because it is tidier), D4 (an existing
self-regenerating surface instead of a new page), D5 (a documented,
self-verifying manual step instead of half-wiring a 1216-line transactional
script) and D7 (a near-byte-neutral reword of an existing clause in an
already-read prompt instead of any new prompt text anywhere).

## Design decisions recorded at planning time (do not re-derive)

### D1 — entry shape and id form (slug-based, block allocation rejected)

Two record types, both appended to `docs/ai/decisions.jsonl`, both reusing the
ledger's EXISTING key vocabulary (`v`, `ts`, `actor`, `type`, `ref_id`,
`finding`, `decision`, `source` — the keys 89-93 of the current 95 entries
already carry) so no consumer sees an alien shape:

```
{"v":1,"ts":"<ISO8601Z>","actor":"<slug>","type":"follow_up",
 "id":"fu-<slug>","ref_id":"<ref of the scope that RAISED it>",
 "severity":"P1|P2|P3","finding":"<what, one line>",
 "decision":"<why deferred / what to do, one line>",
 "source":"<evidence path, review report, or thread url>",
 "origin":"backfill"          // OPTIONAL, backfill entries only (D3)
 "source_ts":"<ISO8601Z>"}    // OPTIONAL, backfill entries only (D3)
```

```
{"v":1,"ts":"<ISO8601Z>","actor":"<slug>","type":"follow_up_status",
 "id":"fu-<slug>","status":"done|dropped",
 "resolved_by":"<ref of the scope that resolved it, or a reason for dropped>",
 "source":"<commit sha, PR url, or evidence path>"}
```

`status` lives ONLY on `follow_up_status`. A `follow_up` entry is `open` by
construction — an append-only ledger cannot carry mutable state on the
original line, and inventing an `"status":"open"` field on it would invite
exactly the retro-edit AC-003 forbids.

ID FORM — `^fu-[a-z0-9]+(-[a-z0-9]+)*$`, max 40 chars, chosen from three
candidates:
- dense sequential (`FU-001`, `FU-002`): REJECTED on the github/spec-kit#4065
  lesson named in the intake. Dense numbering forces renumbering whenever two
  branches allocate concurrently, and a renumbered id silently invalidates
  every prose citation and commit-message reference already written against it
  — the exact failure this registry exists to prevent.
- block-allocated numbers (per-branch ranges): rejected as a whole allocator
  mechanism (this repo already runs one, `allocate-doc-number.mjs`, and it is
  an L3 protected surface) for a payload of 14 items.
- SLUG (chosen): collision-free without coordination, meaningful in a commit
  message (`closes fu-bom-first-line-key`), never renumbered, never reused.
  Uniqueness is enforced at WRITE time by the tool (duplicate `--id` on `add`
  is a usage error, exit 2) and tolerated at READ time (first occurrence
  wins, duplicate named in a NOTE) so a hand-written line can never crash a
  reader.

D1b — LEGACY ID-LESS FOLDING. The one pre-existing `follow_up` (line 92) has no
`id`. It is NOT rewritten and NOT re-emitted as a duplicate. The reader derives
`fu-<ref_id-slug>-<yyyymmddThhmm>` from its `ref_id` + `ts`
(`fu-telemetry-completeness-20260811T0520`), lists it under that id, accepts it
as a `close` target, and NAMES the derivation in a NOTE (AGENTS.md
degrade-with-NOTE convention; Constitution art. 4).

D1c — FOLD ALGORITHM (the registry state is a projection, never a stored view):
read every non-blank, non-`#` line; for each `id`, take the FIRST `follow_up`
as the item, then apply every `follow_up_status` for that id in `ts` order,
latest wins. A `follow_up_status` whose id has no `follow_up` is DANGLING:
counted, named in a NOTE, never fatal, never listed as an item.

### D2 — emission via a tiny `add` subcommand, not a hand-authored line

Measured on token cost per use, which is the deciding criterion here:

- Hand-authored JSON line: the agent must emit the full object inline
  (~130-180 output tokens for a real entry) AND must first recall or re-read
  the exact key set to get it right. Worse, it is not merely expensive — it is
  UNSAFE at this seam: `routine-emit.mjs checkAuthorization` fails closed over
  the ENTIRE file, so one malformed hand-written line silently revokes merge
  authorization for every scheduled routine, with no error anywhere near the
  cause.
- `node .aai/scripts/follow-ups.mjs add --id fu-x --ref CHANGE-0142 --severity
  P2 --what "…" --why "…" --source "…"`: ~60-90 output tokens, `v`/`ts`/`actor`
  auto-filled exactly as `append-event.mjs` does it, and the JSON is
  machine-serialized so the malformed-line class is structurally unreachable
  from the sanctioned path.

The helper wins on BOTH axes. It writes with a single `fs.appendFileSync` of
`JSON.stringify(entry) + '\n'` (the house JSONL pattern: append-event.mjs:145,
metrics-flush.mjs:734, aai-friction.mjs:379 — one `appendFileSync` of one line
is atomic enough for concurrent single-line appends and is what every other
ledger in this repo already relies on). No read-modify-write, no lock file: we
never rewrite, so `learned-append.mjs`'s lock/atomic-rename ceremony buys
nothing here and would only add failure modes.

### D3 — backfill by pure append, with a mechanical 1:1 accounting rule

Every existing line stays BYTE-IDENTICAL. The backfill only appends.

Accounting rule (mechanical, so no judgement call can hide a dropped item):
for each pre-change ledger line whose `decision` contains K occurrences of the
literal `FOLLOW-UP`, the backfill appends EXACTLY K lines carrying
`"source_ts": "<that line's ts>"` and `"origin": "backfill"`. Each appended
line is one of:
- a `follow_up` (the normal case: a genuine deferral), or
- a `follow_up_status` (when the clause is a BACK-REFERENCE recording that an
  earlier follow-up was resolved rather than a new deferral — clause [9],
  2026-08-13T02:26, is of this shape).

Pre-change inventory derived this planning pass (the numbers the tests pin):
14 clauses across 11 source entries at ts
2026-08-08T14:15, 2026-08-09T10:47, 2026-08-11T21:22, 2026-08-11T23:18,
2026-08-13T01:26 (x4), 2026-08-13T02:26, 2026-08-13T10:50, 2026-08-13T11:22,
2026-08-13T15:48, 2026-08-13T16:05, 2026-08-13T18:47.

Backfill entries carry a FRESH `ts` (the moment of the backfill — lying about
when the line was written is the retro-edit in another costume) and cite the
original moment in `source_ts`. Where a clause is demonstrably already
resolved by shipped work (at minimum: the 2026-08-13T18:47 CHANGE-0140 clause,
resolved by CHANGE-0141 / SPEC-0128 / PR #256, and the CAT-16
Commands:-anchored probe clause resolved by CHANGE-0138), the backfill appends
the `follow_up` AND a paired `follow_up_status` — history is reconstructed
honestly, never edited.

History-integrity proof: `git show <base>:docs/ai/decisions.jsonl` must be a
byte-exact PREFIX of the working-tree file (the `isPureAppend` predicate from
learned-append.mjs:217, applied as a test rather than as a gate).

### D4 — report surface: the FACTORY REPORT, not the overview

Chosen: `.aai/scripts/generate-factory-report.mjs` →
`docs/ai/factory-report-data.json` + `docs/ai/factory-report.html`.

Four reasons, in order of weight:
1. SEMANTIC FIT. The factory report is the factory-health/quality trend layer
   ("what does it deliver, how fast, at what cost, at what QUALITY"). Ageing
   deferred work is a quality-debt metric. `generate-overview.mjs` is the
   stakeholder "what shipped / what waits on YOU" page — an open follow-up is
   neither shipped nor a human decision, and putting it there would train a
   non-technical reader to ignore the page.
2. ZERO ADDED CEREMONY. `close-work-item.mjs` already calls
   `regenerateFactoryReportBestEffort()` on every close, so the block refreshes
   itself with no new step, no new invocation, no prompt byte.
3. CHEAP DETERMINISTIC OBSERVABLE. `--data-only` writes
   `factory-report-data.json`, so every AC-004 assertion is a JSON field check,
   not HTML scraping.
4. HONESTY MACHINERY ALREADY THERE. Its `notes` array is the established
   degrade-with-NOTE channel, and it "always exits 0 on a readable/absent
   ledger; a malformed JSONL line is skipped and named, never fatal" — exactly
   the report-only contract AC-004 demands.

DATA PLUMBING NEEDED (confirmed minimal by reading the generator): one extra
input path + `--decisions <path>` flag alongside the existing
`--metrics`/`--events`/`--releases`, one call into the shared fold, one
`follow_ups` block in the model, one rendered section. ONE non-obvious edge:
the generator's existing JSONL reader (line ~117) was written for METRICS/EVENTS
and does not skip `#` comment lines — `decisions.jsonl` opens with a 15-line
`#` header. The fold is therefore imported from `follow-ups.mjs`, not
re-implemented, and the comment-line case is a named test.

CODE-SHARING SHAPE: the fold + reader are EXPORTED from
`.aai/scripts/follow-ups.mjs` (with the standard `isMain` entry guard —
precedent: branch-guard.mjs:282, aai-issues.mjs:325, hitl-channel.mjs:445,
generate-dashboard.mjs:449) and imported by the generator. Deliberately NOT
placed in `.aai/scripts/lib/`: that directory is a
`full_run_triggers.shared_lib_globs` entry, so a new module there escalates
every future touching PR to a FULL_RUN, and it would cost a second new `.aai`
file. One file, one PROFILES row.

### D5 — closing loop: self-verifying `close` subcommand, DOCUMENTED manual step; close-work-item is NOT wired

Honest assessment, as the intake demanded.

Wiring `--resolves fu-x` into `close-work-item.mjs` would mean extending its
transaction (D6 of SPEC-0053: snapshot every doc's bytes + the EVENTS.jsonl
byte-LENGTH, apply, self-verify against the real docs-audit engine, and on any
drift restore every file and TRUNCATE EVENTS.jsonl back to the snapshot length)
to a SECOND append-only ledger. That rollback arm is a `truncate` on a
telemetry ledger. A bug there does not fail a close — it deletes decision
history, and this repo already carries a learned rule about exactly that class
(`git restore docs/ai/EVENTS.jsonl` wiping close telemetry). Paying that risk,
plus the L3-adjacent review weight of a 1216-line transactional script, to save
one typed command is a bad trade for a 14-item registry.

Chosen instead:
`node .aai/scripts/follow-ups.mjs close --id fu-x --resolved-by CHANGE-0143
--source <sha>` appends the `follow_up_status` line and then PROVES the flip by
RE-READING the ledger from disk and re-folding: it prints the folded item's new
status and exits 0 only when the re-read shows it. That is literally what
AC-005 asks for ("the tool proves the flip by re-reading the ledger"), and it
is stronger than a wired-but-unverified mutation.

The step is documented in exactly two non-ledgered places — `docs/product/
aai-decisions.md` and the script's own `--help`/header — and costs zero prompt
bytes. Residual risk, written down not waved away: nothing FORCES the close, so
a resolved follow-up can linger as open. The compensating control is D4 — an
ageing open item is visible in a report that regenerates itself at every close.
Report-only, by design: this scope adds no gate anywhere.

### D6 — exit contract (refining the intake's wording, deliberately)

The intake asked for "non-zero reserved for usage errors only". Taken
literally that leaves a failed write-verification indistinguishable from
success, which would defeat AC-005. The contract is therefore:

- `0` — success. INCLUDES a non-empty backlog (never an error), an empty
  backlog, a skipped malformed line, and an idempotent re-close.
- `1` — write path ONLY: the post-append re-read did not show the expected
  state. The READ/LIST path can never return 1.
- `2` — usage error: unknown flag, missing required flag, bad `--id` shape,
  duplicate id on `add`, unknown id on `close`, unreadable ledger.

So the intake's real intent holds exactly: on the query path, 0 and 2 are the
only outcomes and backlog size never moves the code.

### D7 — the ONE prompt-corpus byte spend, budgeted at <= 200 B net

Zero prompt bytes was the first candidate and it fails on effect: a rule nobody
reads at the moment of need is the status quo, which is what produced 14 prose
clauses and 1 typed entry.

The chosen spend is a REWORD of text that already exists and is already read by
exactly the role that needs it. `.aai/SKILL_CODE_REVIEW.prompt.md` "WARNINGS
POLICY WITH TEETH" already says every WARNING must be "(b) promoted to a
`docs/ai/decisions.jsonl` entry (decision id + rationale)" — and "decision id"
names a thing that does not exist in this repo today. Making that clause
concrete (naming `follow_up` and the `follow-ups.mjs add` invocation) is the
highest-leverage byte in the scope and adds NO new reading: the file is already
loaded by the code-review role and by nothing else.

BUDGET, and it is an acceptance criterion, not an aspiration:
- net delta over TEST-010's live `.aai/*.prompt.md` glob <= 200 B;
- if delta > 0: one new `JUSTIFIED_ADDITIONS` entry of EXACTLY the measured
  delta, and TEST-012's pin moves -6044 -> -6044 + delta, leaving headroom
  unchanged at 1622/2048 (well inside HEADROOM_CAP 2048);
- if delta <= 0: no ledger entry, pin stays -6044 (a shrink of this size is
  absorbed as headroom per TEST-010's own remediation rule).
- The reword MUST preserve test_014's three literals (`docs/ai/decisions.jsonl`,
  `follow-up ref`, `conditional`) — hygiene-pack test_014 is the pin.
- Nothing is added to `.aai/AGENTS.md`, to any other prompt, or to any
  always-read surface. Per-ride cost for a ride with no code review: +0.

### D8 — layer classification consequence

Because D7 puts the invocation inside a `core`-profile prompt
(`.aai/SKILL_CODE_REVIEW.prompt.md`), `.aai/scripts/follow-ups.mjs` MUST be
classified `core` in `.aai/system/PROFILES.yaml` — a `core`-only sync that
shipped the instruction without the script would hand a downstream project a
prompt naming a missing file. (Same reasoning `lib/product-doc.mjs` records for
itself.) This is the PLANNING companion-obligation #2 entry.

### D9 — everything is locally provable

Every verification below is a local command: the new bash suite and the four
existing suites via `bash .aai/scripts/aai-run-tests.sh …` (canonical
invocation, CHANGE-0139), `node .aai/scripts/follow-ups.mjs …` against fixture
ledgers under `mktemp`, `node .aai/scripts/generate-factory-report.mjs
--data-only` against fixture and real ledgers, `git show <base>:…` for the
history-integrity byte compare, and node one-liners for JSON field probes. Zero
network, Node stdlib only (docs/TECHNOLOGY.md). No claim in this spec depends
on CI.

## Implementation strategy
- Strategy: hybrid
- Rationale: The five behavior arms get TDD with stored RED artifacts, and each
  has a genuinely deterministic RED available today: AC-001/002/005 fail on the
  pre-change tree because the script does not exist (captured as a real
  observation, not asserted); AC-003's accounting test fails against the
  pre-backfill ledger (14 clauses, 0 typed backfill entries); AC-004 fails
  because `factory-report-data.json` carries no `follow_ups` key. Two tests
  would PASS unchanged and therefore get MUTATION RED instead, explicitly:
  TEST-005 (history integrity — RED is a planted rewrite of an existing ledger
  line, which the check must reject) and TEST-009 (consumer seams — RED is a
  planted malformed appended line, which `routine-emit` must still fail closed
  on). The governance/docs companions (AC-007) run the loop lane with the RED
  observed but storage optional. STATE's `implementation_strategy` currently
  carries the PREVIOUS scope (`selected: hybrid`, `source:
  SPEC-DRAFT-spec-changelog-payload-hardening.md`) and the CHANGE-0142 intake
  records no `Implementation mode (user choice):` line, so no user choice is
  being overridden.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: the work already lives on the dedicated branch
  feat/followup-registry; no parallel scope shares these files, and the one
  shared-state surface (docs/ai/decisions.jsonl) is append-only, so a worktree
  would not reduce the only real collision risk.
- User decision: undecided
- Base ref: main
- Worktree branch/path: feat/followup-registry (existing branch, inline)
- Inline review scope: .aai/scripts/follow-ups.mjs,
  .aai/scripts/generate-factory-report.mjs, .aai/SKILL_CODE_REVIEW.prompt.md,
  .aai/system/PROFILES.yaml, tests/skills/test-aai-follow-ups.sh,
  tests/skills/suite-map.yaml, tests/skills/lib/prompt-diet-ledger.sh,
  tests/skills/test-aai-prompt-diet.sh, docs/ai/decisions.jsonl,
  docs/product/aai-decisions.md, docs/product/factory-performance-report.md,
  docs/specs/SPEC-DRAFT-spec-followup-registry.md,
  docs/issues/CHANGE-0142-followup-registry.md, CHANGELOG.md

Code review required: true (new executable code, a generator change, a schema,
a prompt-corpus edit and new tests); scope = the explicit path list above as a
diff against main.

## Companion obligations check (closed list)
- Prompt corpus bytes move: YES — `.aai/SKILL_CODE_REVIEW.prompt.md` clause (b)
  reword (D7). Folded into scope and into the Test Plan: a
  `JUSTIFIED_ADDITIONS` entry of exactly the measured delta in
  `tests/skills/lib/prompt-diet-ledger.sh` plus the matching TEST-012 pin move
  in `tests/skills/test-aai-prompt-diet.sh` (TEST-010 row below). No
  `.aai/AGENTS.md` byte changes.
- New `.aai/**` file: YES — `.aai/scripts/follow-ups.mjs`. Folded into scope
  and into the Test Plan: a `core:` classification row in
  `.aai/system/PROFILES.yaml` (D8), pinned by
  `tests/skills/test-aai-layer-profiles.sh` TEST-001 (TEST-010 row below).

## Acceptance Criteria Mapping

- Maps to: CHANGE-0142 AC-001
- Spec-AC-01: WHEN work is deferred THEN it is recorded as one appended
  `docs/ai/decisions.jsonl` line of the D1 `follow_up` shape — `v`, `ts`,
  `actor`, `type`, `id` matching `^fu-[a-z0-9]+(-[a-z0-9]+)*$` (max 40),
  `ref_id`, `severity` in P1/P2/P3, one-line `finding`, one-line `decision`,
  `source` — with resolution carried by a separate appended `follow_up_status`
  line, never by editing the original; the tool REFUSES a malformed id or a
  duplicate id at write time (exit 2) and tolerates both at read time by
  naming them in a NOTE.
- Verification: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-follow-ups.sh` exits 0 with the schema/id arm green (valid add accepted and re-read; bad id shape, duplicate id and missing required flag each exit 2 with nothing appended — asserted by byte-length compare of the fixture ledger before and after).

- Maps to: CHANGE-0142 AC-002
- Spec-AC-02: WHEN `node .aai/scripts/follow-ups.mjs list` runs THEN it prints
  the folded open registry deterministically (same input, byte-identical
  output), honours `--ref`, `--status` and `--age-days` filters and `--json`,
  exits 0 for an empty AND a non-empty backlog, exits 2 only on usage error
  per D6, performs zero network I/O and invokes no LLM.
- Verification: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-follow-ups.sh` exits 0 with the query arm green (two identical runs byte-compare equal; each filter narrows to the expected id set; `--json` parses and matches the text rows; empty and non-empty backlogs both exit 0; an unknown flag exits 2); plus a source pin that the script imports no `node:http`/`node:https`/`node:net` and calls no `fetch`.

- Maps to: CHANGE-0142 AC-003
- Spec-AC-03: WHEN the backfill lands THEN for every pre-change ledger line
  whose `decision` contains K occurrences of `FOLLOW-UP` there are EXACTLY K
  appended lines carrying `origin: "backfill"` and `source_ts` equal to that
  line's `ts` (14 in total across the 11 source entries listed in D3), and the
  pre-change file is a byte-exact PREFIX of the post-change file.
- Verification: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-follow-ups.sh` exits 0 with the backfill arm green — a node probe recomputing the per-`ts` clause counts from `git show <base>:docs/ai/decisions.jsonl` and matching them against the working-tree backfill entries (total 14), plus a byte-prefix compare of the two files.

- Maps to: CHANGE-0142 AC-004
- Spec-AC-04: WHEN `node .aai/scripts/generate-factory-report.mjs --data-only`
  runs THEN `docs/ai/factory-report-data.json` carries a `follow_ups` block
  with `open_count`, `oldest_age_days` and a per-item list including id, ref,
  severity and age in days, the HTML carries the matching section, the exit
  code is 0 for an empty, a non-empty, a `#`-commented, an absent and a
  malformed-line ledger (each degradation NAMED in the existing `notes`
  array), and no exit contract or gate anywhere changes.
- Verification: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-factory-report.sh` exits 0 with the new follow-ups arm green (fixture ledgers under mktemp via `--decisions`, JSON field probes, the five degradation cases each exit 0 with a named note); `node .aai/scripts/generate-factory-report.mjs --data-only` against the real ledger exits 0 and reports the live open count.

- Maps to: CHANGE-0142 AC-005
- Spec-AC-05: WHEN `node .aai/scripts/follow-ups.mjs close --id <id>
  --resolved-by <ref>` runs THEN a `follow_up_status` line is APPENDED (the
  `follow_up` line untouched), the tool RE-READS the ledger from disk, re-folds
  it, prints the item's new status and exits 0 only when the re-read confirms
  it (exit 1 if it does not, exit 2 for an unknown id); a re-close of an
  already-closed id is idempotent with a NOTE and exit 0; and the manual
  invocation is documented in `docs/product/aai-decisions.md` and in the
  script's `--help`, with `close-work-item.mjs` deliberately NOT wired (D5).
- Verification: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-follow-ups.sh` exits 0 with the close arm green (append-only compare, post-close list shows done + resolved_by, unknown id exits 2 with nothing appended, re-close exits 0 with the NOTE, and a mutated-verification fixture exits 1); `grep -c 'follow-ups.mjs close' docs/product/aai-decisions.md` >= 1 and `git diff main -- .aai/scripts/close-work-item.mjs` is empty.

- Maps to: CHANGE-0142 AC-001, AC-003 (consumer seams)
- Spec-AC-06: WHEN the ledger has grown by the backfill and by typed entries
  THEN every existing `docs/ai/decisions.jsonl` consumer behaves exactly as
  before: `routine-emit.mjs` still GRANTS on a valid `routine_authorization`
  record and still FAILS CLOSED on any malformed non-comment line,
  `aai-doctor.mjs` CAT-07 still reports a non-zero entry count without a WARN,
  and `metrics-flush.mjs` still treats `decisions.jsonl` as PROTECTED.
- Verification: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-routine.sh` and `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-doctor.sh` both exit 0; plus the mutation probe in the new suite (a planted malformed appended line makes `routine-emit` refuse — the RED that proves the seam is really crossed).

- Maps to: CHANGE-0142 AC-006
- Spec-AC-07: WHEN the scope completes THEN the governance companions are
  true-ed up and provable — the net `.aai/*.prompt.md` byte delta is <= 200 B
  with the D7 ledger/pin accounting applied (headroom unchanged at 1622/2048),
  `.aai/scripts/follow-ups.mjs` carries a `core:` row in
  `.aai/system/PROFILES.yaml`, `tests/skills/suite-map.yaml` carries an
  `aai-follow-ups` row, every stored RED log for this scope has `RED_CLASS:`
  as line 1 written AT capture, and the two product docs state only what is
  true (registry contract and manual close step in
  `docs/product/aai-decisions.md`; the new follow-ups block named in
  `docs/product/factory-performance-report.md`).
- Verification: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh`, `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-layer-profiles.sh` and `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-hygiene-pack.sh` all exit 0; `git diff main --stat -- .aai` shows no prompt file other than SKILL_CODE_REVIEW; `head -1` of each `docs/ai/tdd/red-*followup-registry*.log` is a `RED_CLASS:` line.

## Constitution deviations

None. (Checked v1 articles 1-7 against the planned scope: every AC rides an
executable local command and stored RED evidence, and no PASS is claimed here
(1); the design reuses the existing ledger, the existing report and the
existing append pattern, adds exactly one new file, and explicitly rejects a
block allocator, a lib/ module and a close-work-item transaction extension as
speculative for a 14-item payload (2); every artifact is a plain git-diffable
JSONL/Markdown/JS file, Node stdlib only, zero network (3); every reader path
degrades with a NAMED note — malformed line, absent ledger, id-less legacy
entry, dangling status, duplicate id — and every write path fails fast with an
exit code and context (4); every change is additive at a public boundary: new
JSONL entry types alongside the existing ones, a new optional `--decisions`
flag, a new subcommand set on a NEW script, no existing exit code or field
touched (5); docs/ai/STATE.yaml is not written by this planning pass — this
session is explicitly barred from it and the orchestrator records
phase/strategy through state.mjs (6); no merge is performed (7).)

## Acceptance Criteria Status

| Spec-AC    | Description                                                                          | Status  | Evidence | Review-By | Notes |
|------------|--------------------------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Typed follow_up + follow_up_status shape on decisions.jsonl; slug id, write-refuse, read-tolerate | planned | —        | —         | D1 records why dense sequential ids were rejected (spec-kit#4065) |
| Spec-AC-02 | follow-ups.mjs list: deterministic, filters, --json, D6 exit contract, zero network   | planned | —        | —         | non-empty backlog is never an error |
| Spec-AC-03 | Backfill: exactly K appended lines per K-clause source line, history byte-identical   | planned | —        | —         | 14 clauses across 11 source entries (D3 inventory) |
| Spec-AC-04 | Factory-report follow_ups block, report-only, degrades with named notes, exit 0 always | planned | —        | —         | surface chosen in D4; regenerated at close already |
| Spec-AC-05 | close subcommand appends and PROVES by re-read; manual step documented; no close wiring | planned | —        | —         | D5 records why close-work-item stays untouched |
| Spec-AC-06 | Existing decisions.jsonl consumers unchanged; fail-closed authorization still bites   | planned | —        | —         | mutation RED required (would pass unchanged) |
| Spec-AC-07 | Governance companions: diet ledger + TEST-012, PROFILES core row, suite-map row, docs | planned | —        | —         | prompt-corpus budget <= 200 B net (D7) |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan

Components affected:
- `.aai/scripts/follow-ups.mjs` — NEW. Node stdlib only, zero network.
  Exports `readDecisionsLedger(path)` (skips blank and `#` lines; a malformed
  non-comment line is COUNTED and NAMED, never fatal — this reader is a
  reporter, unlike routine-emit's authorization reader which must fail closed)
  and `foldFollowUps(records)` (D1c). CLI subcommands `list` (default), `add`,
  `close`; `--help`; `isMain` entry guard so the generator can import it.
  Writes with one `fs.appendFileSync` of one serialized line (D2). The file
  header documents the D1 schema, the D6 exit contract and the D5 manual
  close step — the schema's canonical home, at zero prompt-corpus cost.
- `.aai/scripts/generate-factory-report.mjs` — add `decisionsPath` default
  `docs/ai/decisions.jsonl` + `--decisions <path>`; import the fold; add the
  `follow_ups` model block (`open_count`, `oldest_age_days`, `items[]` with
  id/ref/severity/age_days/what, ordered oldest-first); render one section;
  push a `notes` entry for each degradation (absent ledger, malformed lines
  skipped, id-less legacy folded, dangling status records). Exit contract
  UNCHANGED (always 0 on a readable/absent ledger).
- `docs/ai/decisions.jsonl` — the D3 backfill: 14 appended lines. Existing
  bytes untouched.
- `.aai/SKILL_CODE_REVIEW.prompt.md` — the single clause (b) reword (D7),
  <= 200 B net, test_014 literals preserved.
- `tests/skills/test-aai-follow-ups.sh` — NEW suite (schema/id, query, backfill
  accounting, history prefix, close/self-verify, consumer-seam mutation).
  mktemp fixtures, here-strings never `echo | grep` (the suite runs
  `set -euo pipefail`; a pipeline dies of SIGPIPE on CI — LEARNED
  test-harness shell-options trap). Every `test_*` wired into `main()`
  (check-test-registration.mjs).
- `tests/skills/test-aai-factory-report.sh` — new follow-ups arm (AC-004).
- `tests/skills/suite-map.yaml` — `aai-follow-ups` row (globs:
  `.aai/scripts/follow-ups.mjs`, `docs/ai/decisions.jsonl`); add
  `.aai/scripts/follow-ups.mjs` and `docs/ai/decisions.jsonl` to the
  `aai-factory-report` row's globs too.
- `.aai/system/PROFILES.yaml` — `core:` row for `.aai/scripts/follow-ups.mjs`
  (D8), keeping the list's exact two-space-dash indentation and sort position.
- `tests/skills/lib/prompt-diet-ledger.sh` + `tests/skills/test-aai-prompt-diet.sh`
  — the D7 true-up, only if the measured delta is > 0.
- `docs/product/aai-decisions.md` — NEW product doc (capability `aai-decisions`
  per the intake frontmatter; the required trio `What it does` / `Data model` /
  `Interfaces and contracts` per lib/product-doc.mjs). Carries the schema, the
  CLI grammar, the D6 exit contract and the D5 manual close step.
- `docs/product/factory-performance-report.md` — truthful update naming the new
  `follow_ups` block and the `--decisions` flag.
- `CHANGELOG.md` — one `## [unreleased] — <title>` heading (per-entry heading,
  never bullets under the scaffold — LEARNED).

Data flows / seams (each crossed by a named test, produced on one side and
asserted on the other):
- SEAM-1 `follow-ups.mjs add/close` (writer) -> `routine-emit.mjs
  checkAuthorization` (fail-closed reader over the WHOLE file). This is the
  scope's most dangerous crossing: one malformed line silently revokes routine
  merge rights. Crossed by TEST-009 — a real `routine-emit` invocation against
  a ledger the new tool actually wrote, plus the planted-malformed-line
  mutation proving the fail-closed arm still bites.
- SEAM-2 `follow-ups.mjs` fold (producer) -> `generate-factory-report.mjs`
  section (renderer): ONE fold implementation, two consumers. Crossed by
  TEST-006 asserting the report's `open_count` equals the CLI's `--json` count
  over the same ledger — never two independently computed numbers.
- SEAM-3 the ledger's `#` comment header -> the generator's JSONL reader (which
  does not skip comments today). Crossed by TEST-006's `#`-commented fixture.
- SEAM-4 pre-change ledger bytes -> post-change ledger bytes (history
  integrity). Crossed by TEST-005 with a mutation RED.
- SEAM-5 the reworded prompt clause -> hygiene-pack test_014's literal pins ->
  the prompt-diet byte floor. Crossed by TEST-010.
- SEAM-6 `close-work-item.mjs` `regenerateFactoryReportBestEffort()` ->
  the new report section: the block refreshes at close with no new call.
  Asserted indirectly by TEST-007 (generator exit 0 on every ledger shape) —
  the close path is unmodified, which is itself the claim.

Edge cases:
- `decisions.jsonl` opens with 15 `#` header lines — every reader path must
  skip them (routine-emit already does; the factory-report reader does not yet).
- The one legacy id-less `follow_up` (line 92) — derived id + NOTE (D1b), never
  a duplicate entry, never a rewrite.
- Duplicate id at read time (hand-written line): first wins + NOTE. Duplicate
  id at write time: exit 2, nothing appended.
- Dangling `follow_up_status` (id with no `follow_up`): counted + NOTE, not an
  item, never fatal.
- Malformed non-comment line: named + skipped by the reporter; still FATAL
  (fail-closed) for routine-emit — the two readers differ ON PURPOSE and the
  difference is tested.
- `oldest_age_days` with an unparseable or future `ts`: excluded and named in
  the notes, never a negative age, never a fabricated 0.
- Empty registry: `open_count: 0`, `oldest_age_days: null` (never 0), exit 0.
- Pipeline-free discipline throughout the new suite (`set -euo pipefail` +
  SIGPIPE on CI — LEARNED).
- Ship ordering: regenerate `docs/ai/factory-report.{html,json}` AFTER the
  allocator renames the spec (LEARNED from the CHANGE-0140/0141 repeat — the
  very follow-up this registry exists to have surfaced).

Residual risks (written down, not silently accepted):
- R1 Nothing FORCES a `close`. A resolved follow-up can linger as open until
  someone runs the command. Compensating control: D4's ageing surface. Not
  gated, by design (AC-004 forbids new blocking).
- R2 Emission depends on one reworded clause being followed by the code-review
  role. If the typed-entry count does not grow over the next few rides, the
  cheapest next move is a deterministic reminder inside an existing script
  (for example the wrap-up nudge that already reads the ledger), NOT more
  prompt text. Explicitly out of scope here.
- R3 The `--decisions` flag widens the factory report's input surface; a
  downstream project without `docs/ai/decisions.jsonl` must degrade to a named
  note rather than a crash. Covered by the absent-ledger case in TEST-006, but
  downstream repos are not exercised by this repo's CI.
- R4 `severity` is author-assigned with no calibration; the report orders by
  AGE, not severity, so a mis-assigned P-level cannot hide an item.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                       | Description                                                                 | Status  |
|----------|------------|-------------|--------------------------------------------|-------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-follow-ups.sh        | schema and id discipline: a valid add is accepted and re-read; bad id shape, duplicate id, missing required flag each exit 2 with the fixture ledger byte-length unchanged | pending |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-follow-ups.sh        | query path: two identical runs byte-compare equal; --ref, --status and --age-days each narrow to the expected id set; --json parses and matches the text rows; empty and non-empty backlogs both exit 0; unknown flag exits 2 | pending |
| TEST-003 | Spec-AC-02 | unit        | tests/skills/test-aai-follow-ups.sh        | degrade-with-NOTE and zero-network pins: comment lines skipped, malformed line named and skipped, id-less legacy entry folded under its derived id, dangling status named; source carries no node:http/https/net import and no fetch call | pending |
| TEST-004 | Spec-AC-03 | integration | tests/skills/test-aai-follow-ups.sh        | backfill accounting: per-source-ts clause counts recomputed from the base ledger equal the appended origin:backfill counts, totalling 14 across the 11 source entries | pending |
| TEST-005 | Spec-AC-03 | integration | tests/skills/test-aai-follow-ups.sh        | history integrity: the base ledger is a byte-exact prefix of the working-tree ledger; MUTATION RED — a planted rewrite of an existing line must make this fail | pending |
| TEST-006 | Spec-AC-04 | integration | tests/skills/test-aai-factory-report.sh    | follow_ups block in factory-report-data.json (open_count, oldest_age_days, items with id/ref/severity/age_days) and open_count equals the CLI --json count over the same ledger; comment-header fixture parses | pending |
| TEST-007 | Spec-AC-04 | integration | tests/skills/test-aai-factory-report.sh    | report-only contract: absent, empty, malformed-line and non-empty-backlog ledgers each exit 0 with the degradation named in notes; HTML carries the section; no new gate or exit code | pending |
| TEST-008 | Spec-AC-05 | integration | tests/skills/test-aai-follow-ups.sh        | close path: status appended and the follow_up line untouched; re-read proves the flip; unknown id exits 2 with nothing appended; re-close is idempotent with a NOTE at exit 0; a mutated-verification fixture exits 1 | pending |
| TEST-009 | Spec-AC-06 | integration | tests/skills/test-aai-follow-ups.sh        | consumer seam: routine-emit still grants over the tool-written ledger; MUTATION RED — a planted malformed appended line must make it fail closed; doctor CAT-07 still reports a non-zero count without WARN | pending |
| TEST-010 | Spec-AC-07 | integration | tests/skills/ (prompt-diet, layer-profiles, hygiene-pack) | governance companions: prompt-diet suite green with the TEST-012 pin at -6044 plus the measured delta and headroom 1622/2048; PROFILES TEST-001 green with the new core row; hygiene-pack test_014 literals and the suite-map row pin green | pending |

RED plan (hybrid; every RED observed and stored BEFORE its GREEN work,
`RED_CLASS:` stamped as line 1 AT CAPTURE — `product_red` when the planted
damage reaches the assertion, `infra_fail` otherwise, per SKILL_TDD):
- TEST-001/002/003/008 RED: run the new suite on the pre-change tree — the
  script does not exist, so the arms fail on a real, captured observation
  (`infra_fail` where the failure is "command not found", re-captured as
  `product_red` once the CLI skeleton exists but the behavior does not).
- TEST-004 RED: run the accounting probe against the PRE-backfill ledger — 14
  clauses, 0 matching `origin: backfill` entries. Captured.
- TEST-005 RED (MUTATION — this test would pass unchanged): in a scratch copy,
  rewrite one existing ledger line and confirm the prefix compare FAILS naming
  the first divergent byte offset.
- TEST-006/007 RED: run the pre-change generator with `--data-only` and confirm
  `factory-report-data.json` carries no `follow_ups` key.
- TEST-009 RED (MUTATION — this test would pass unchanged): append a malformed
  non-comment line to a fixture ledger and confirm `routine-emit`'s
  authorization refuses, proving the seam assertion has teeth.
- TEST-010 RED: with the prompt reword applied but the diet ledger NOT trued
  up, the prompt-diet suite fails on the TEST-012 pin — captured before the
  ledger entry lands.

## Verification
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-follow-ups.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-factory-report.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-routine.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-doctor.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-layer-profiles.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-hygiene-pack.sh`
- `node .aai/scripts/follow-ups.mjs list --json` (real ledger; exits 0)
- `node .aai/scripts/generate-factory-report.mjs --data-only` (real ledger; exits 0)
- `node .aai/scripts/check-test-registration.mjs tests/skills`
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-DRAFT-spec-followup-registry.md`
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: followup-registry
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path (docs/ai/tdd/ for RED artifacts per the hybrid strategy;
  `RED_CLASS:` stamped at capture, line 1)
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
