# Code Review — CHANGE-0142 typed follow-up registry (ceremony level 2)

```yaml
review:
  scope: "git diff 27409cb..HEAD restricted to the spec's inline scope paths (branch feat/followup-registry)"
  spec: docs/specs/SPEC-0129-spec-followup-registry.md (frozen at 27409cb)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/follow-ups.mjs:99,410-451 + tests/skills/test-aai-follow-ups.sh:102-159 (test_001); independently re-probed: 9 hostile id shapes all exit 2" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/follow-ups.mjs:373-408 + test-aai-follow-ups.sh:162-296 (test_002/test_003); --age-days positive arm verified by hand (see NB-4)" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "docs/ai/decisions.jsonl +17 lines; independent recompute from 27409cb:docs/ai/decisions.jsonl = 14 clauses / 11 entries, matching the 14 source_ts lines exactly; byte-prefix PREFIX-OK appended=10718 vs both 27409cb and main" }
      - { ac: Spec-AC-04, call: compliant,
          citation: ".aai/scripts/generate-factory-report.mjs:504-528,665-670,765-774 + test-aai-factory-report.sh test_028/test_029" }
      - { ac: Spec-AC-05, call: compliant,
          citation: ".aai/scripts/follow-ups.mjs:453-497 (append + re-read + re-fold, exit 1 on an unproven flip) + test_008; docs/product/aai-decisions.md:54-68; close-work-item.mjs byte-identical to main" }
      - { ac: Spec-AC-06, call: compliant,
          citation: "test_009 + independent probe: routine-emit still GRANTS over a ledger carrying an adversarial tool-written line, and one planted malformed line revokes it" }
      - { ac: Spec-AC-07, call: compliant,
          citation: "SKILL_CODE_REVIEW.prompt.md 10812 -> 11012 B = exactly +200; only prompt file in the glob touched; diet-ledger entry 200; TEST-012 -6044 -> -5844; PROFILES core row; suite-map aai-follow-ups row; both product docs real" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/follow-ups.mjs, line: 191,
          issue: "A `follow_up_status` record with NO `status` key silently re-opens a closed item and emits NO note — the one hand-written malformation that changes the answer without naming itself.",
          failure_scenario: "Ledger holds a proper done status for fu-x. Someone hand-appends {\"type\":\"follow_up_status\",\"id\":\"fu-x\",\"resolved_by\":\"...\"} (typo, omitted status). Verified live: `list --status all` flips fu-x back to `open`, open_count in the factory report grows by one, and no NOTE explains it — while a BOGUS status VALUE (\"wip\") correctly does emit one (line 195-197)." }
      - { rank: NON-BLOCKING, file: .aai/scripts/follow-ups.mjs, line: 189,
          issue: "Status history is ordered with `String(a.ts).localeCompare(...)` while items are ordered with plain `<`/`>` (line 226-228). localeCompare is locale/ICU dependent; the determinism assertion runs both passes in one locale so it cannot see a divergence.",
          failure_scenario: "Two status records for one id whose ts strings differ only in punctuation-adjacent positions are ordered differently under a different LANG/ICU build on CI than on the author's box → latest-wins picks the wrong record → a closed item lists as open (or `close` exits 1 on a ledger where it exits 0 locally). Fix is a one-line swap to the same codepoint comparison the item sort already uses." }
      - { rank: NON-BLOCKING, file: .aai/scripts/follow-ups.mjs, line: 359-366,
          issue: "`requireReadableLedger` passes for a path that exists and is R_OK but is not a readable FILE (a directory), so D6's `2 — unreadable ledger` degrades to exit 0 with an 'absent' note instead.",
          failure_scenario: "`follow-ups.mjs list --ledger docs/ai` (a plausible typo, or a path that loses read permission between existsSync and readFileSync) prints `shown=0 open=0 total=0` and exits 0. Verified live: rc=0. A wrapper script that gates only on the exit code reads a mis-pathed query as an empty backlog." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-follow-ups.sh, line: 196-198,
          issue: "The `--age-days` arm only asserts the EMPTYING case (`--age-days 10000` → shown=0). A filter hard-wired to return nothing would pass. Spec-AC-02 asks that each filter 'narrow to the expected id set'.",
          failure_scenario: "A future refactor inverts or breaks the age predicate so that every item is dropped; test_002 stays green and the factory report's ageing surface (the scope's only compensating control for R1) silently empties. The behavior is CORRECT today — I verified `--age-days 30` keeps only the 224d item and `--age-days 0` keeps both — so this is a coverage gap, not a defect." }
      - { rank: NON-BLOCKING, file: .aai/scripts/follow-ups.mjs, line: 347,
          issue: "`if (val === undefined || val.startsWith('--')) usageError(...)` refuses any flag VALUE beginning with `--`, so a finding or rationale that starts with a flag-like token cannot be recorded.",
          failure_scenario: "`add --what \"--decisions <path> is undocumented\"` exits 2 with 'flag \"--what\" requires a value'. Verified live: rc=2. The reviewer then hand-writes the line — the exact hand-authoring the whole design exists to prevent (D2)." }
      - { rank: NON-BLOCKING, file: .aai/scripts/generate-factory-report.mjs, line: 510-527,
          issue: "When a ledger line that IS a follow_up is malformed, the report's `open_count` silently under-counts; the note reads `EXCLUDED N malformed decision ledger line(s)` and never says the backlog figure may be understated.",
          failure_scenario: "A truncated append (disk-full, killed process) mangles one follow_up line. The report renders `open follow-ups: 9` with a generic exclusion note; a reader takes 9 as the backlog. Compliant with AC-004 as written (the degradation IS named) — the ask is one clause in the note text." }
  cannot_verify:
    - { claim: "Single-line fs.appendFileSync is atomic against a truly concurrent second writer on this repo's real filesystems (the D2 reasoning I endorse below).",
        closes_with: "A concurrency harness firing N parallel `add` calls at one ledger and asserting N well-formed lines — on APFS, ext4 and the CI runner's FS. Only reasoned about here; not exercised by any test in this scope." }
    - { claim: "Downstream (vendored) projects that receive .aai/scripts/follow-ups.mjs via a `core` sync behave correctly without docs/ai/decisions.jsonl.",
        closes_with: "A sync-into-empty-project fixture. The spec names this as R3; this repo's CI does not exercise downstream repos. I did clear the adjacent hazard statically — see 'Layer coupling' below." }
    - { claim: "The reworded clause (b) actually changes reviewer behavior (the scope's whole emission mechanism, spec R2).",
        closes_with: "Typed-entry growth over the next few rides. Note the branch already carries one live dogfood use (fu-orchestrator-git-add-scope-bleed, uncommitted)." }
    - { claim: "The four RED suites named below are red ONLY because of the pre-close false-open shape and clear on close.",
        closes_with: "The close ceremony's own docs-audit event. I verified the mechanism (spec status: implementing + a terminal AC table) but did not run the close." }
  overall: pass
```

## Scope, and what actually leaked

Reviewed: `git diff 27409cb..HEAD` restricted to the spec's inline scope. Nineteen
paths changed in the range. Against the spec's enumerated `Inline review scope`
list they fall into three groups, and the "exactly three leaked paths" claim in
the dispatch needs a correction:

**In the enumerated scope (12):** `.aai/SKILL_CODE_REVIEW.prompt.md`,
`.aai/scripts/follow-ups.mjs`, `.aai/scripts/generate-factory-report.mjs`,
`.aai/system/PROFILES.yaml`, `CHANGELOG.md`, `docs/ai/decisions.jsonl`,
`docs/product/aai-decisions.md`, `docs/product/factory-performance-report.md`,
`docs/specs/SPEC-0129-spec-followup-registry.md`,
`tests/skills/lib/prompt-diet-ledger.sh`, `tests/skills/suite-map.yaml`,
`tests/skills/test-aai-prompt-diet.sh`, `tests/skills/test-aai-follow-ups.sh`.
(`docs/issues/CHANGE-0142-followup-registry.md` is listed but unchanged in the
range — it predates the freeze.)

**In scope by the spec's own Implementation Plan / Test Plan but MISSING from the
enumerated list (3):** `tests/skills/test-aai-factory-report.sh` (named in the
Implementation plan and carrying TEST-006/007), `docs/ai/factory-report-data.json`
and `docs/ai/factory-report.html` (the spec's Edge-cases section mandates
regenerating them). These are not leaks — they are an incomplete enumeration in
the spec's `Inline review scope` line. I reviewed them as in-scope.

**Genuinely foreign (3, confirmed — and nothing else):**
- `docs/specs/RESEARCH-0001-spec-kit-comparative.md` (386 lines, 100% research)
- `docs/ai/EVENTS.jsonl` (+3 lines, all `spec-kit-comparative` lifecycle/audit)
- `docs/INDEX.md` — **mixed, not purely foreign.** Its diff carries this scope's
  rows (`spec-followup-registry 7 planned → 7 done`, `Product 24 → 25` with the
  new `aai-decisions` row, `factory-performance-report 2 → 3`) AND the research
  doc's rows (`RESEARCH-0001`, `Done 316 → 317`). It is a regenerated index, so
  it cannot be split; the PR will carry the research row.

Confirmed: the leak is exactly those three paths and nothing else. The commit
SUBJECTS are misleading exactly as the dispatch described (8d88219, ba638e0,
33f39ae, dddc780 carry this scope's code under `docs(research)` subjects); the
squash-merge resolves it, and the branch itself already records the lesson as a
live follow-up (`fu-orchestrator-git-add-scope-bleed`, uncommitted).

**Working tree is dirty** (3 files): `docs/ai/decisions.jsonl` (+1 line — the
dogfood follow-up above), `docs/ai/EVENTS.jsonl` (+2 research close events),
`docs/INDEX.md` (regeneration timestamp). None of it invalidates the review; the
uncommitted follow_up carries no `origin`/`source_ts` and no `FOLLOW-UP` literal,
so it cannot perturb TEST-004's accounting (verified by running it).

## Verdict 1 — spec_compliance: PASS

### AC walk

**Spec-AC-01 — compliant.** `FOLLOW_UP_ID_RE` (`follow-ups.mjs:99`) is
`^fu-[a-z0-9]+(-[a-z0-9]+)*$`, `ID_MAX_LEN` 40, both enforced in `cmdAdd` before
any write (`:416-417`). I re-probed nine hostile shapes beyond the suite's five —
`fu-`, `fu`, `FU-x`, `fu--x`, `fu-x-`, `fu-x_y`, `fu-ábc`, `-fu-x`, `fu-x--y` —
all exit 2. Read-tolerate is proven separately (`test_003`): the id-less legacy
line folds under `fu-telemetry-completeness-20260811T0520` with a NOTE, a
duplicate id is first-wins with a NOTE.

**Spec-AC-02 — compliant.** Determinism, `--ref`, `--status`, `--age-days`,
`--json`, exit 0 on both empty and non-empty backlogs, exit 2 on usage errors.
`cmdList` has exactly two exits (0 and the shared `usageError` 2), so "the READ
path can never return 1" is structural, not merely tested. Zero-network is pinned
by a source grep and is true by inspection: the only imports are `node:fs`,
`node:path`, `node:url`.

**Spec-AC-03 — compliant, and independently recomputed.** I re-derived the
histogram from `27409cb:docs/ai/decisions.jsonl` alone:

```
2026-08-08T14:15 1   2026-08-11T23:18 1   2026-08-13T10:50 1   2026-08-13T16:05 1
2026-08-09T10:47 1   2026-08-13T01:26 4   2026-08-13T11:22 1   2026-08-13T18:47 1
2026-08-11T21:22 1   2026-08-13T02:26 1   2026-08-13T15:48 1
total 14 clauses across 11 entries
```

The appended `source_ts`-carrying lines match that per-entry, 14 total, plus 3
`origin: backfill` resolutions with no `source_ts`. Byte-prefix: `PREFIX-OK
appended=10718` against both `27409cb` and `main`.

**Spec-AC-04 — compliant.** `follow_ups` block with `open_count`,
`oldest_age_days` (null, never 0, on an empty registry) and oldest-first `items[]`
carrying id/ref/severity/age_days/what/status; `<section id="follow-ups">` in the
HTML; `--decisions <path>`; every degradation pushed into the existing `notes`
array; exit contract untouched.

**Spec-AC-05 — compliant.** `cmdClose` appends, then re-reads from disk and
re-folds, exiting 0 only when the re-read shows the new status (`:489-496`). The
exit-1 arm is genuinely reachable and tested with a future-dated shadowing status
record. The derived legacy id is an accepted close target because `cmdClose`
deliberately does NOT apply `FOLLOW_UP_ID_RE` (which the derived form, carrying an
uppercase `T`, would fail) — a correct and subtle read-tolerate decision.
`close-work-item.mjs` is byte-identical to main, asserted in-suite.

**Spec-AC-06 — compliant, and independently re-probed.** See "The fail-closed
seam" below.

**Spec-AC-07 — compliant, measured.** `SKILL_CODE_REVIEW.prompt.md` 10812 →
11012 B = **exactly +200**, the D7 ceiling. It is the only file in TEST-010's
`.aai/*.prompt.md` glob that changed. The diet-ledger entry credits `200`;
TEST-012's pin moves −6044 → −5844 (+200, arithmetic consistent); headroom
unchanged 1622/2048. Hygiene `test_014`'s three literals survive: the reword keeps
`docs/ai/decisions.jsonl` (clause b), `follow-up ref` (clause c, untouched) and
`conditional` (the sentence above, untouched). PROFILES gains the `core:` row in
sort position with the required two-space-dash indentation; suite-map gains the
`aai-follow-ups` row and extends `aai-factory-report`'s globs.

### Deviations from the frozen spec (all three disclosed by the implementer)

1. **SEAM-3's premise was false.** The spec (D4, Edge cases, SEAM-3) asserts the
   generator's JSONL reader "does not skip `#` comment lines". It does —
   `generate-factory-report.mjs:128` has `if (t === '' || t.startsWith('#')) continue`
   and has for some time. The implementer says so verbatim in the AC-04 Notes cell
   and keeps the arm as a pin. Honest, correctly disclosed, and it does not
   undermine the decision it partly justified: importing the fold still buys
   SEAM-2 (one implementation, two consumers), which is the load-bearing reason.
2. **A third paired resolution** beyond D3's two named ones — judged below.
3. **The prompt delta landed exactly AT the ceiling (+200 B), not under it.**
   Disclosed in the AC-07 Notes cell and in the ledger entry. Within budget; worth
   naming because "≤ 200" and "= 200" leave no room for a later touch-up on that
   clause without a fresh ledger entry.

Post-freeze edits to the spec are confined to the Status/Evidence/Notes columns of
the AC table and the Status column of the Test Plan. **No AC text, verification
command, or budget was weakened after the freeze** — I diffed the frozen and
current spec line by line. Anti-gaming: clean.

## Verdict 2 — code_quality: PASS (0 BLOCKING, 6 NON-BLOCKING)

### The write-refuse / read-tolerate asymmetry — correct, and stronger than tested

The asymmetry is the design's spine and it holds. `readDecisionsLedger`
(`:111-130`) counts and skips; `foldFollowUps` never throws on a hostile record
(every field access is type-guarded); every reader degradation is named. On the
write side, `cmdAdd` validates id shape, id length, severity, `--origin`,
`--source-ts` and every required flag BEFORE `requireReadableLedger`, and the
payload is `JSON.stringify`d, so the malformed-line class is structurally
unreachable rather than merely tested against.

I attacked it directly: an `add` whose `--what` carried a literal newline, a tab,
escaped quotes, backslashes, backticks and `${...}`, with a `--ref` containing a
double quote. Result: exit 0, one line appended, the file still parses
line-by-line with zero malformed records, and `routine-emit` still GRANTS over it.
That is the claim that matters and it is true.

### Append discipline — the implementer's rejection of tmp+rename is RIGHT

The brief asked for the `learned-append.mjs` tmp+rename ceremony. The implementer
refused it and wrote down why (`follow-ups.mjs:51-56`). I agree, and the reasoning
is stronger than "the house does it this way":

`learned-append.mjs`'s atomic write is a whole-file **read-modify-write**. On an
append-only ledger that is not a safety improvement, it is a *regression*: process
A reads N bytes, process B appends line X, process A renames its N+1-byte image
over the file — **X is gone, silently, with no malformed line to notice**. The
tmp+rename ceremony protects against a torn *rewrite*; this code never rewrites,
so it has nothing to protect and one new way to lose data. A single
`appendFileSync` of one short line under `O_APPEND` cannot lose a concurrent
append; its worst case is a torn tail on a hard kill, which tmp+rename would not
prevent either (it would lose the whole concurrent line instead). Correct call,
correctly justified in the file where the next maintainer will read it.

The newline guard (`:263-279`) is the right companion: it reads the last BYTE (so
a trailing multibyte character can never be mistaken for `\n`) and prefixes one
`\n` only when needed, which is exactly the "torn last line" case `test_001`'s
`t001b` fixture covers. Its statSync/read/append sequence is not atomic, but the
only reachable outcome of a race there is a blank line, which every reader skips.

### The fail-closed seam — verified against the real thing

`routine-emit.mjs:439-471` parses every non-comment line and returns `false` on the
FIRST parse failure. Two independent checks:

- All 113 records in the working-tree ledger parse; 0 malformed. The 17 backfill
  lines carry `type: follow_up` / `follow_up_status`, never `routine_authorization`,
  so they can neither poison the gate nor accidentally grant it.
- Live probe with the hostile-payload ledger above: `MERGE DISABLED` absent
  (granted). Then one planted truncated line: `MERGE DISABLED` present. The seam
  bites in both directions, and `test_009` pins both arms with a real
  `routine-emit` invocation rather than a re-implementation.

`add` cannot emit a line that trips it. The one residual path is a hand-written
line, which is precisely what clause (b)'s "never hand-write it" now says.

### Backfill fidelity, and the third pairing

Fidelity is exact (histogram above). On the judgement call the dispatch asked for
— is the third pairing (`fu-canonical-invocation-generators` raised at
2026-08-13T15:48 under CHANGE-0139 and closed at backfill by CHANGE-0139)
defensible, or is it telemetry the registry should have forbidden?

**Defensible, and the mechanical rule left no better option.** D3's accounting rule
is unconditional: the 15:48 source line carries K=1, so exactly one line must be
appended for it. The clause was a genuine deferral when written; it was then
resolved inside the same ref's PR #254 sweep — which the ledger itself proves in
the 16:05 entry ("the ONLY remaining deferral of the 15:48 routing after the two
generator items were fixed in-tree"). The alternatives are both worse: appending a
bare `follow_up_status` would be DANGLING (no `follow_up` to attach to, silently
dropped from the registry and counted as a degradation); appending only the
`follow_up` would leave the registry asserting an open item that shipped a day
earlier — the registry lying on its first day. The chosen shape reconstructs what
happened, cites the evidence in `source`, and matches D3's "at minimum" wording,
which explicitly anticipated more than the two named pairings.

The one thing worth naming: `resolved_by` equals the raising ref, so this item is
born-and-closed within one ride. That is a real, if slightly odd, history —
"raised and resolved in the same ride" is exactly what happened, and pretending
otherwise would be the retro-edit the design forbids. Not a finding.

### Generator change

`--decisions <path>` follows the file's existing flag idiom exactly; the fold is
imported, not duplicated (SEAM-2), and `test_028` asserts the report's
`open_count` IS the CLI's number over one ledger rather than two independently
computed numbers — the right shape for that assertion. Degradation notes flow
through the existing `notes` array. The byte-stability golden in `test_026` was
correctly extended (new key deleted before compare, empty ledger planted so the
new block contributes no note) rather than regenerated, which preserves what that
pin was written to measure.

Can the report lie? Only in the bounded way named in NB-6: a malformed line that
*is* a follow_up under-counts the backlog behind a generic exclusion note. Absent,
empty, comment-only, malformed and populated ledgers all exit 0 with the
degradation named — I read all five arms of `test_029`.

**Layer coupling — checked and cleared.** `generate-factory-report.mjs` is
`extended:` (PROFILES:230) and now imports `follow-ups.mjs`, which D8 puts in
`core:`. Since the `extended` profile is core + extended, no sync can deliver the
importer without the imported module; a `core`-only project gets a standalone CLI
and no generator. The dangerous direction does not exist. Worth recording because
a `core → extended` import would have been a silent report-killer swallowed by
`regenerateFactoryReportBestEffort()`.

**Import side effects — checked.** `isMain` compares realpaths on both sides
(`:506-515`), so importing the module never runs `main()`, including under macOS's
`/var → /private/var` TMPDIR symlink. The comment records why.

### Governance and product docs

The prompt reword is genuinely the highest-leverage 200 bytes available: it makes
an already-read clause name a thing that now exists, adds no new reading, and puts
the "never hand-write it" rationale at the exact point of use.
`docs/product/aai-decisions.md` is **real, not a placeholder** — 185 lines carrying
the required trio plus a degradation table, the full exit contract, the D5 manual
step with its rationale, and an honest "Limits and non-goals" section that states
R1/R2/R4 in plain language. `docs/product/factory-performance-report.md` is
truthfully updated (new input, new flag, new section, honest null semantics).

### Test quality — could the 7 tests pass against a broken engine?

Mostly no. Both mutation arms are real mutations, not decorations: TEST-005 plants
an actual byte rewrite into a scratch copy and requires the predicate to report a
divergence offset; TEST-009 appends a truncated JSON line and requires a real
`routine-emit` process to print `MERGE DISABLED`. The write-refuse arm asserts
byte-length invariance, not just an exit code, so a refusal that appended garbage
first would fail. TEST-004 recomputes K from the ledger instead of trusting the pin.
TEST-008 asserts the pre-close bytes are a prefix of the post-close file, so a
`close` that rewrote the original line would fail. `test_028` ties two consumers to
one number. The one genuine hole is NB-4 (`--age-days` positive arm). Two smaller
ones, INFO only: `--status dropped` is never exercised, and no test covers a
`follow_up_status` with a missing `status` field — which is how NB-1 survived.

### INFO (never gates)

- The `close` grammar is described three times with two different flag sets: the
  file header (`:70-72`) and the product doc (`:141-142`) omit `--origin` /
  `--source-ts`, which `USAGE` (`:290-292`) and the parser both accept.
- `status: "open"` on a `follow_up_status` is an accepted, undocumented reopen
  value (used by test_008's shadow fixture) that D1 and the product doc do not
  mention.
- `add`'s duplicate-id check is check-then-append (TOCTOU). Two concurrent adds of
  one id produce a duplicate — read-tolerated with a NOTE, exactly as designed.
- `--decisions` with no following value silently falls through to the default,
  matching the pre-existing behavior of `--metrics`/`--events`/`--releases`. Not
  new.
- The committed `docs/ai/factory-report-data.json` says `open_count: 10`; the
  working tree's ledger now folds to 11 (the uncommitted dogfood entry). Expected —
  the report regenerates at close — but the ship-ordering note in the spec applies.

## Full-suite evidence (this ceremony's obligation)

Command: `bash tests/skills/test-framework.sh` (all 78 suites), run by this
reviewer because the validator's own sweep reached only 19/78.

**Result: 78 suites, 74 PASS (94%), 4 FAIL, framework exit 1.**

The four failures are the four the dispatch named, and I confirmed each reduces to
ONE root cause rather than four independent ones:

| Suite | Failing assertion | Root cause |
|---|---|---|
| `aai-docs-audit` | TEST-009 `Expected 'False-open: 0'` on the REAL repo audit | the pre-close false-open |
| `aai-doc-numbering` | TEST-013 `Expected 'CLEAN'` on the real repo audit | same audit |
| `aai-delta-stage3` | TEST-007 `sibling suite failed: test-aai-docs-audit.sh` | cascade of the above |
| `aai-doc-number-reservation` | TEST-011 `existing test-aai-doc-numbering.sh suite stays green` | cascade of the above |

I then ran the audit engine directly (read-only; `docs-audit.mjs` has no
`writeFileSync` and emits no EVENTS line):

```
Scanned: 345 docs | Orphans: 0 | Drifted: 1 | Stale: 0 | False-open: 1 | Obsolete: 0
| spec-followup-registry | probable-false-open | AC Status table fully terminal with evidence |
Verdict: NEEDS-TRIAGE (1 items)
```

**Exactly one doc is implicated, and it is this scope's own spec** — `status:
implementing` with a fully terminal AC table, which is by construction the state a
spec sits in between reconciliation and the close ceremony. The `Drifted: 1` count
is the same doc counted in the drift report, not a second problem, and the leaked
`RESEARCH-0001` doc is NOT implicated (it already carries its own close telemetry).
So: **expected and explained, self-clearing at close — not failures.**

Every suite this scope touches or could plausibly disturb is green:
`aai-follow-ups` PASS (2s), `aai-factory-report` PASS (4s), `aai-prompt-diet` PASS
(10s), `aai-layer-profiles` PASS, `aai-hygiene-pack` PASS, `aai-routine` PASS,
`aai-doctor` PASS (85s), `aai-close-work-item` PASS (47s), `aai-product-docs` PASS,
`aai-suite-select` PASS. `node .aai/scripts/check-test-registration.mjs tests/skills`
is silent (all seven new `test_*` functions wired into `main()`).

**Operational heads-up, not a finding against this scope:** the full-suite run
itself dirtied the real tree — `docs/ai/overview-data.json`, `docs/ai/overview.html`
and `docs/ai/tests/test-runs.jsonl` are now modified. That is the pre-existing
"suite writes into the real tree" class already sitting in the backlog under
`fu-factory-report-sparkline-scale`. Do not stage them with this scope.

## Warning dispositions (H6)

All six findings are NON-BLOCKING. Recommended disposition, for the ORCHESTRATOR
to record (a read-only reviewer files nothing itself):

| # | Finding | Recommended disposition |
|---|---|---|
| NB-1 | status-less `follow_up_status` silently re-opens | **remediate-in-tree** — three lines in `foldFollowUps` plus one fixture line; it is a hole in the contract this scope exists to establish, and it is cheapest to close now |
| NB-2 | `localeCompare` in the status sort | **remediate-in-tree** — one-line swap to the codepoint comparison used 35 lines below |
| NB-3 | directory/unreadable ledger exits 0 on the read path | promote-to-follow-up-ref (`fu-` typed entry) |
| NB-4 | `--age-days` positive arm untested | **remediate-in-tree** — two assertions in test_002 |
| NB-5 | flag values may not begin with `--` | promote-to-follow-up-ref |
| NB-6 | malformed-line note does not say the count may be understated | promote-to-follow-up-ref |

Dogfood note: this scope's own tool is now the sanctioned artifact for the
promote-to-follow-up disposition, and the branch already contains one live use of
it.

## Next steps

1. Orchestrator: record the six dispositions (NB-1/NB-2/NB-4 are cheap in-tree
   fixes; NB-3/NB-5/NB-6 are honest `follow_up` entries against this very ref).
2. At PR time, stage explicit paths. The three foreign paths
   (`RESEARCH-0001-spec-kit-comparative.md`, the research `EVENTS.jsonl` lines) will
   ride along inside `docs/INDEX.md` regardless, since that file is generated and
   mixed; say so in the PR body rather than trying to split it.
3. Regenerate `docs/ai/factory-report.{html,json}` AFTER the allocator renames the
   spec — the spec's own Edge-cases line, and the very lesson
   `fu-changelog-payload-hardening` records.
