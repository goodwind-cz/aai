---
id: spec-vagueness-gate
type: spec
number: 130
status: done
ceremony_level: 1
links:
  requirement: docs/issues/CHANGE-0144-vagueness-gate.md
  rfc: null
  pr:
    - 258
  commits:
    - 745bfc3
---

# Spec — mark it, do not assert it: three spec-lint rules and one freeze precondition

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0144-vagueness-gate.md
- Borrowed mechanism and its bounds: docs/specs/RESEARCH-0001-spec-kit-comparative.md F2 (marker + DON'T GUESS), F12 (cap 3, priority order, DON'T-ASK default list, bounded repair loop), F14 (33 min vs 8 min with no measured quality gain; "ceremony overkill on small tasks" in all four months)
- The local defect this scope answers: commit 27409cb `docs/issues/CHANGE-0140-reporting-docs-true-up.md` asserted that only `aai-feedback-status.mjs` survived; all three engines exist (`.aai/scripts/aai-feedback-{status,triage,upsert}.mjs`) and the current file carries Planning's inline correction
- Engine extended: `.aai/scripts/spec-lint.mjs` (rule set, `IN_FLIGHT_STATUSES` scoping precedent)
- Gate extended: `.aai/scripts/spec-freeze.mjs` (`PRECONDITION_RULES`, exit 3 refusal, nothing written)
- Suites that own these surfaces: tests/skills/test-aai-spec-lint.sh, tests/skills/test-aai-spec-tools.sh, tests/skills/test-aai-prompt-diet.sh (routing already correct in tests/skills/suite-map.yaml — `aai-spec-lint` globs already cover spec-lint.mjs, spec-freeze.mjs and PLANNING.prompt.md)
- Prompt-corpus ledger: tests/skills/lib/prompt-diet-ledger.sh (checkpoint -5844, headroom 1622 within cap 2048)
- Technology contract: docs/TECHNOLOGY.md (canonical test invocation `bash .aai/scripts/aai-run-tests.sh <command...>`)

Ceremony justification: level 1 (declared by the intake and kept). One
behavioral surface — spec-lint's rule set — gains one contiguous rule block;
spec-freeze gains ONE string in an existing array; the prompt corpus gains ONE
sentence in ONE file. Nothing under `protected_paths_l3` is touched (spec-lint
and spec-freeze are not in that list), no exit code, CLI flag or output
contract moves, and every acceptance criterion below names a directly
executable local command (L1 rule: the Test Plan IS the declared validation
scope).

## Summary

Our spec vocabulary has no way to say "I could not verify this". An unverified
claim therefore reads exactly like a verified one, and the factory's cheapest
possible correction — a human answering one question at freeze — never gets
asked for. Spec-kit's answer (F2) is a prohibition, not a virtue: mark the
ambiguity with one canonical marker and DO NOT GUESS; nothing progresses while
a marker survives.

The whole scope is: three deterministic rules inside the existing
`lintContent()` pass, one of them added to spec-freeze's existing
`PRECONDITION_RULES` array, and one sentence in `.aai/PLANNING.prompt.md`.
No new script, no new step, no new agent invocation, no new flag, no new exit
code. That budget is not modesty — it is the finding in F14: the only
adversarial measurement in the entire spec-kit corpus is a controlled test
where spec-driven ceremony cost 33 min against 8 min of plain prompting with
NO measured quality gain, and "ceremony overkill on small tasks" is the most
repeated field complaint. A gate that adds a step to the ride would cost more
than the class of defect it catches.

## Design decisions recorded at planning time (do not re-derive)

### D1 — the marker: `[NEEDS-CLARIFICATION: <specific question>]` (hyphenated, uppercase, bracketed)

Canonical spelling, one form only, in intake and spec bodies:

```
[NEEDS-CLARIFICATION: does the close gate read this field, or only the index?]
```

(That example sits in a FENCED block on purpose — under the specimen rule of
D2 it is a specimen, not a live marker, which is how this spec documents the
vocabulary and still freezes. An INDENTED four-space code block would NOT be
masked; fenced blocks and inline code spans are the whole exemption.)

Collision check run over the whole repo before choosing (`grep -rIn`,
excluding `.git` and `node_modules`):

- `NEEDS CLARIFICATION` (spec-kit's own spacing) — 2 hits, both in
  `docs/specs/RESEARCH-0001-spec-kit-comparative.md` lines 70 and 352, where
  the upstream rule is QUOTED in italics (no code span). A rule keyed on the
  spaced form would therefore match our own research doc's quotation of the
  thing it describes — the classic self-flagging shape that already cost
  `strategy-evidence-mismatch` a special case.
- `NEEDS-CLARIFICATION` (hyphenated) — 0 hits anywhere in the tree.
- `UNVERIFIED` — 3 hits in `.aai/MEMORY_REVIEW.prompt.md` as a live flag word;
  rejected.
- `TBD` — 5 hits, four of them legitimate ("Worktree branch/path: TBD");
  rejected.
- `CLARIFY:` / `ASSUMED` / `[?]` — 0 hits, but each is a weaker grep target
  (`CLARIFY:` collides with ordinary prose the moment anyone writes the verb).

The hyphenated form wins on three counts: zero collisions today; it can never
match the upstream spelling already quoted in our corpus, so the document that
records the borrowed rule stays clean forever; and it is ONE token, so a human
grep is `grep -rn 'NEEDS-CLARIFICATION' docs/` with no whitespace tolerance
and the detector needs no `\s+` — one literal, one meaning.

Detection is anchored on the literal opening token `[NEEDS-CLARIFICATION`,
case-sensitive, whether or not the `: question]` tail is well formed: a
truncated or mistyped marker is still an unresolved marker (fail closed). The
uppercase-only rule is deliberate — prose that happens to say "needs
clarification" is NOT a marker and is not detected (see D5).

RESOLUTION IS DELETION. There is no "resolved" annotation form and no second
grammar: you answer the question, write the answer as the claim, and the
marker line disappears. That makes every resolution a visible diff hunk a
reviewer can read, at the cost of nothing.

### D2 — where the gate fires: detect in spec-lint, block in spec-freeze's existing precondition array

One detector, two consumers — the same split that already exists for
`ac-without-test`:

1. `.aai/scripts/spec-lint.mjs` `lintContent()` gains ONE contiguous block
   emitting three rules (below). Report-only, exit 1 on findings, exit 0 clean
   — the documented contract, unchanged. No new flag, no new exit code.
2. `.aai/scripts/spec-freeze.mjs` gains `'unresolved-clarification'` in its
   existing `PRECONDITION_RULES` array. `freezePreconditions()` already lints
   the WOULD-BE-FROZEN content and refuses with exit 3 writing nothing, so the
   blocking behavior is inherited whole — zero new control flow.

The three rule ids:

- `unresolved-clarification` — BLOCKING at freeze. One finding per occurrence,
  each carrying its 1-based line and the question text (truncated at 90 chars,
  matching the existing excerpt convention).
- `clarification-cap-exceeded` — ADVISORY. Never a precondition (D3).
- `ac-vague-term` — ADVISORY. Never a precondition (D4).

UNRESOLVED, precisely: at least one occurrence of the literal token
`[NEEDS-CLARIFICATION` in the normalized document, OUTSIDE fenced code blocks
and inline code spans, in a document whose frontmatter `status` is one of
`IN_FLIGHT_STATUSES` (draft, proposed, accepted, implementing). Terminal
statuses (done, superseded, rejected, deferred, legacy, unknown) produce
nothing — identical scoping and identical justification to `ac-without-test`:
a terminal doc is history, and re-litigating it yields noise, not action.

SPECIMEN EXEMPTION: a marker inside a fenced code block or an inline code span
is a specimen, not an occurrence. This is what lets this spec, the USER_GUIDE
section, and the test fixtures name the vocabulary without self-flagging, and
it is deterministic (no heuristics, no self-reference special case). The
masking helper replaces masked characters with spaces but PRESERVES newlines
and `|`, so line numbers stay exact and table geometry cannot shift. The mask
is used by the two new rules ONLY — no pre-existing rule's input changes.

WHAT "REACHING FREEZE" MECHANICALLY MEANS, and the limit that follows: the
precondition gate runs inside `spec-freeze.mjs` only when `changed` is true,
i.e. on a real transition. An already-frozen spec is a documented idempotent
no-op, so a marker added AFTER freeze is REPORTED by spec-lint (and by
Validation step 1's advisory line) but refuses nothing. Recorded, not hidden.

### D3 — cap 3, the priority order, the DON'T-ASK list

Cap: more than 3 unresolved markers in one in-flight document emits exactly
ONE additional `clarification-cap-exceeded` finding, at the line of the fourth
occurrence, naming the count, the cap and the priority order. Advisory by
construction: at freeze the allowed number of markers is ZERO, so a blocking
cap would be dead code that can never fire without
`unresolved-clarification` firing first and harder. The cap exists for the
pre-freeze window, where its only job is to stop a planner from converting
"ask the human" into a questionnaire — F12's own reason for the number.

Priority order when trimming to the cap (F12, adopted verbatim):
scope > security/privacy > UX > technical detail.

DON'T-ASK defaults — never mark, never demand a marker, just apply the
project's recorded default:

| # | Never ask about | Why not, in THIS repo |
|---|---|---|
| 1 | data retention | every durable artifact is an append-only plain file (Constitution art. 3); nothing here has a retention policy to decide |
| 2 | performance budgets | acceptance criteria in this factory are pass/fail command observables; no surface carries a latency or throughput SLO |
| 3 | error-handling behavior | canon already decides it — degrade gracefully with an explicit report, fail fast with context (Constitution art. 4) |
| 4 | auth / authorization | there is no auth surface; the CLI inherits the operator's `gh auth` session and merging is operator-only (art. 7) |
| 5 | integration patterns | docs/TECHNOLOGY.md is the authoritative contract; the answer is "read it", never "ask the human" |

No parser can tell what a marker is ABOUT, so the DON'T-ASK list is authoring
guidance, not an enforced rule. It is recorded here and compressed into the
one PLANNING sentence; the enforced half is the cap and the freeze gate.

### D4 — vagueness detection is ADVISORY, and `fast` is measured out of the list

Word list, closed, case-insensitive, whole-word: `scalable`, `secure`,
`robust`, `quickly`. Scanned in the `Description` cell of the Acceptance
Criteria Status table (canonical gate table or L0/L1 lean table), on in-flight
documents only, over the masked text of D2. One `ac-vague-term` finding per
offending AC row, carrying the row's line.

`fast` — named by the intake — is DELIBERATELY EXCLUDED, on measurement. In
this corpus `grep -rInE '^\|.*\bfast\b' docs/specs/*.md` returns 12 table rows
across 6 specs, and every single one is domain vocabulary, not vagueness:
"fails fast", "fail-fast", "fast path", "prints LANE fast", "rc 0 fast",
"fast-eligible". Measured false-positive rate 12/12, measured true positives
0. Shipping it would mean the rule's only observable effect on the existing
corpus is noise — which is precisely the failure mode F12 warns about. Its
vagueness sense is still covered by `quickly` and, more importantly, by the AC
table's own contract (an AC that cannot fail is not one — PLANNING principle
1). The same grep over the other four words returns 0 rows, which is why they
survive. Any future word must clear the same measurement.

The rule is advisory FOREVER, not "advisory in v1", for a reason that will not
change: it detects a WORD, never the absence of quantification. No parser can
decide whether "secure" in a given cell is a wish or a shorthand for a named
threat model, and the measured-criterion judgment already belongs to Planning
and to review. A blocking word-list rule would be a keyword tax.

### D5 — the honest limits (what this gate does NOT catch)

Stated here, and stated again in the USER_GUIDE section, because the failure
mode of a gate like this is that people believe it:

1. **The CHANGE-0140 shape is NOT caught.** The false claim ("only
   `aai-feedback-status.mjs` exists") carried NO marker. Nothing in this scope
   inspects the truth of an assertion, so a confident false statement passes
   every rule here, cleanly. What actually changes that shape is upstream of
   the linter: the authoring rule (DO NOT GUESS — mark it), bounded by the
   DON'T-ASK list so the marker stays cheap enough to use, plus the reviewer's
   own verification duty. The gate makes the marked case impossible to forget;
   it does nothing about the unmarked case. Do not describe it as a
   false-claim detector.
2. **Resolution is not verified.** Deleting a marker satisfies the gate
   whether or not the question was answered. The gate buys a visible diff, not
   honesty.
3. **Markers added after freeze block nothing** (D2's `changed` guard).
4. **Spelling variants are invisible**: lowercase, spaced ("NEEDS
   CLARIFICATION"), or prose ("needs clarification") are not markers.
5. **Intake documents are gated by nothing automatic.** No pipeline runs
   spec-lint over `docs/issues/**`; an intake is only linted when someone
   points `--path` at it. Cheap to do, never enforced — enforcing it would
   mean a new step, which AC-005 forbids.
6. **`ac-vague-term` reads only the AC table's Description cell.** The
   `## Acceptance Criteria Mapping` bullets, the Summary and every narrative
   section are not scanned. The Description cell is the one cell every gate
   (docs-audit, the close gate, the index) already reads; widening the scan is
   a separate, measured decision.
7. **The question's quality is not judged.** A marker asking a DON'T-ASK
   question blocks the freeze exactly as hard as a good one.

### D6 — everything locally provable

Every verification below is a local command with no network and no service:
`node .aai/scripts/spec-lint.mjs --path <fixture>` and its exit code, `node
.aai/scripts/spec-freeze.mjs --path <fixture>` (plus `--dry-run` and a `cmp`
proving nothing was written), the two bash suites through the canonical
wrapper `bash .aai/scripts/aai-run-tests.sh bash tests/skills/<suite>.sh`,
`grep` contracts over `.aai/PLANNING.prompt.md` and `docs/USER_GUIDE.md`,
`wc -c` for the prompt-byte delta, and `git diff` for the untouched-surface
claims. Fixtures live in the suites' existing mktemp scratch roots and are
written with here-documents (the suites run `set -euo pipefail`; no pipelines
in new test code — LEARNED test-harness shell-options trap).

One non-vacuity note recorded honestly: the repo currently has ZERO in-flight
specs (measured — all 129 lint clean and all carry terminal statuses), so a
"real corpus stays clean" arm proves nothing about rules scoped to in-flight
documents. The non-vacuity witnesses are therefore (a) the fixture arms, (b) a
control fixture derived from the real `SPEC-0112` rows with its status flipped
to `implementing`, which contains four `fast` rows and must stay clean, and
(c) THIS spec itself, which becomes the corpus's only in-flight document at
freeze and documents the whole vocabulary in code spans — if the specimen
exemption is wrong, the corpus scan says so immediately.

## Implementation strategy
- Strategy: hybrid
- Rationale: the three rules and the freeze precondition each have a cheap,
  deterministic RED available on the pre-change tree — a fixture carrying live
  markers produces ZERO findings and FREEZES successfully today, which is the
  gap itself — so they are TDD with stored RED artifacts, `RED_CLASS:` stamped
  as line 1 at capture time. The prompt sentence, the ledger true-up and the
  USER_GUIDE correction are loop-lane glue pinned by grep contracts and by the
  existing TEST-012 pin. STATE carries no intake-sourced strategy choice for
  this scope (the intake has no `Implementation mode (user choice):` line), so
  this is Planning's call and the orchestrator should record it with
  `--source docs/specs/SPEC-0130-spec-vagueness-gate.md`.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: the work already lives on the dedicated branch
  feat/spec-vagueness-gate; no parallel scope touches spec-lint.mjs,
  spec-freeze.mjs or PLANNING.prompt.md
- User decision: undecided
- Base ref: main
- Worktree branch/path: feat/spec-vagueness-gate (existing branch, inline)
- Inline review scope: .aai/scripts/spec-lint.mjs, .aai/scripts/spec-freeze.mjs,
  .aai/PLANNING.prompt.md, tests/skills/test-aai-spec-lint.sh,
  tests/skills/test-aai-spec-tools.sh, tests/skills/lib/prompt-diet-ledger.sh,
  tests/skills/test-aai-prompt-diet.sh, docs/USER_GUIDE.md,
  docs/specs/SPEC-0130-spec-vagueness-gate.md,
  docs/issues/CHANGE-0144-vagueness-gate.md, CHANGELOG.md

Code review required: true (code, test and prompt changes); scope = the
explicit path list above as a diff against main.

## Companion obligations check (closed list)
- Prompt corpus bytes move: YES — `.aai/PLANNING.prompt.md` gains the single
  marker sentence (drafted at 404 B, budget ceiling 450 B). Fold in a
  `JUSTIFIED_ADDITIONS` entry in tests/skills/lib/prompt-diet-ledger.sh
  credited 1:1 at the MEASURED growth G, and bump the TEST-012 pin in
  tests/skills/test-aai-prompt-diet.sh from -5844 to -5844 + G (headroom stays
  1622, within the 2048 cap). No other `.aai/*.prompt.md` and no `.aai/AGENTS.md`
  byte moves.
- New `.aai/**` file: NO — both scripts are edited in place, so no
  `.aai/system/PROFILES.yaml` classification entry is owed.

## Acceptance Criteria Mapping

- Maps to: CHANGE-0144 AC-001
- Spec-AC-01: WHEN a document carries the canonical marker
  `[NEEDS-CLARIFICATION: <question>]` THEN spec-lint emits one
  `unresolved-clarification` finding per occurrence, each naming its 1-based
  line and the question text, AND a marker inside a fenced code block or an
  inline code span emits nothing, AND the masking that produces that exemption
  changes no line number and no table cell count.
- Verification: `node .aai/scripts/spec-lint.mjs --path <fixture>` exits 1 with one finding per live marker at the expected lines; the specimen fixture exits 0; the pre-existing rule findings on a mixed fixture are byte-identical to the pre-change tree.

- Maps to: CHANGE-0144 AC-002
- Spec-AC-02: WHEN a spec that would otherwise freeze carries at least one
  unresolved marker THEN `spec-freeze.mjs` REFUSES with exit 3, naming
  `unresolved-clarification` and each occurrence, and writes nothing (the file
  is byte-identical afterwards, `--dry-run` refuses identically); WHEN the
  same doc is merely linted pre-freeze THEN it is reported at exit 1 and
  nothing is blocked; removing the marker lets the same fixture freeze at exit
  0.
- Verification: `node .aai/scripts/spec-freeze.mjs --path <fixture>`; `echo $?` == 3; `cmp` of the fixture before and after; control run after deleting the marker exits 0.

- Maps to: CHANGE-0144 AC-003
- Spec-AC-03: WHEN an in-flight document carries more than three unresolved
  markers THEN exactly one additional `clarification-cap-exceeded` advisory
  finding is emitted at the fourth occurrence's line, naming the count, the
  cap 3 and the order scope > security/privacy > UX > technical detail; three
  markers emit no cap finding; the cap rule is absent from
  `PRECONDITION_RULES`, so a freeze refusal on such a doc names only
  `unresolved-clarification`; and the five DON'T-ASK defaults of D3 are
  recorded in this spec, in the PLANNING sentence and in the USER_GUIDE.
- Verification: four-marker fixture through spec-lint (4 + 1 findings, cap line == 4th occurrence); three-marker fixture (no cap finding); the freeze refusal text on the four-marker fixture; `grep -c 'clarification-cap-exceeded' .aai/scripts/spec-freeze.mjs` == 0; grep for the five DON'T-ASK tokens in `.aai/PLANNING.prompt.md` and `docs/USER_GUIDE.md`.

- Maps to: CHANGE-0144 AC-004
- Spec-AC-04: WHEN an in-flight spec's AC-table Description cell contains a
  whole word from the closed list `scalable`, `secure`, `robust`, `quickly`
  THEN one `ac-vague-term` advisory finding is emitted per offending row with
  the row's line, AND `fast` never fires (D4's measurement), AND a spec whose
  ONLY finding is `ac-vague-term` still FREEZES at exit 0 — proving the rule
  cannot block.
- Verification: vague fixture through spec-lint (one finding per row, expected lines); the `SPEC-0112`-derived control fixture at status implementing exits 0; `node .aai/scripts/spec-freeze.mjs --path <vague fixture>` exits 0 and the file is frozen.

- Maps to: CHANGE-0144 AC-005
- Spec-AC-05: WHEN the scope is complete THEN the ride gained no step, no
  agent invocation, no script, no CLI flag and no exit code — spec-lint still
  documents and returns 0/1/2 and spec-freeze 0/1/2/3 — and the ENTIRE
  prompt-corpus delta is one sentence of at most 450 bytes in
  `.aai/PLANNING.prompt.md`, credited 1:1 in the diet ledger with the TEST-012
  pin at exactly -5844 + G.
- Verification: `git diff main --stat -- .aai/` shows exactly the two scripts and PLANNING.prompt.md; `wc -c .aai/PLANNING.prompt.md` delta G <= 450; grep contracts for the unchanged usage/exit-code lines in both scripts; `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh` exits 0 with the bumped pin.

- Maps to: CHANGE-0144 AC-003 and AC-005 (scoping)
- Spec-AC-06: WHEN a document's frontmatter status is terminal THEN none of
  the three new rules fire, AND the full-corpus scan
  `node .aai/scripts/spec-lint.mjs` still reports 0 findings after the change,
  AND the recorded non-vacuity witnesses of D6 (fixture arms, the
  `SPEC-0112`-derived in-flight control, and this spec as the corpus's only
  in-flight document) are present as executable arms rather than prose.
- Verification: terminal-status fixture (marker + vague word + 4 markers) exits 0; `node .aai/scripts/spec-lint.mjs` exits 0 over the real corpus; `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0130-spec-vagueness-gate.md` exits 0.

- Maps to: CHANGE-0144 AC-006
- Spec-AC-07: WHEN the scope is complete THEN docs/USER_GUIDE.md's spec-lint
  section documents the marker spelling, the cap, the priority order, the five
  DON'T-ASK defaults, the three rule ids and D5's limits — including the
  explicit statement that a confident false assertion with no marker (the
  CHANGE-0140 shape) is NOT caught — and corrects the section's current
  "never writes files or hard-gates" sentence to the precise contract
  (spec-lint never blocks; spec-freeze reads a named subset of its rules as
  freeze preconditions); AND every stored RED log for this scope carries a
  `RED_CLASS:` line as line 1, written at capture time.
- Verification: grep contracts over docs/USER_GUIDE.md for the marker, the cap, the five DON'T-ASK tokens, the three rule ids, the CHANGE-0140 limit sentence, and the absence of the stale "never ... hard-gates" claim; `head -1` of every `docs/ai/tdd/red-*vagueness-gate*.log` is a `RED_CLASS:` line.

## Constitution deviations

None. (Checked v1 articles 1-7. Article 1: every AC above rides an executable
local command and the RED observations are stored before their GREEN. Article
2: no new script, no shared abstraction, no whitelist mechanism and no
speculative fourth rule — the vagueness word list is closed and measured, and
`fast` was removed rather than special-cased. Article 3: all artifacts are
plain git-diffable files and mktemp fixtures. Article 4: the freeze refusal
fails fast naming the rule and every occurrence, writing nothing; the two
advisory rules degrade to report-only by construction. Article 5: additive at
every public boundary — no exit code, flag, rule-id rename or output-format
change, and the new rules fire only on documents that opt in by carrying a
marker. Article 6: this planning pass does not write docs/ai/STATE.yaml; the
orchestrator records phase and strategy through state.mjs. Article 7: no merge
is performed.)

## Acceptance Criteria Status

| Spec-AC    | Description                                                                 | Status  | Evidence | Review-By | Notes |
|------------|-----------------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Marker vocabulary and detection — one finding per live marker with its line; code-span and fenced specimens exempt; masking preserves lines and cell counts | done    | 00ece96 TEST-001/003(clarify) green | —         | rule id `unresolved-clarification` |
| Spec-AC-02 | Freeze gate — exit 3 refusal naming each occurrence, nothing written; pre-freeze lint reports at exit 1 and blocks nothing | done    | 00ece96 TEST-002(clarify) green | —         | inherits spec-freeze `PRECONDITION_RULES`; no new exit code |
| Spec-AC-03 | Cap 3 advisory with priority order; DON'T-ASK defaults recorded in spec, prompt and guide; cap is never a precondition | done    | 00ece96 TEST-004+005(clarify) green | —         | rule id `clarification-cap-exceeded` |
| Spec-AC-04 | Vagueness advisory over AC Description cells for the closed measured word list; a vague-only spec still freezes | done    | 00ece96 TEST-006+007(clarify) green | —         | rule id `ac-vague-term`; `fast` excluded on a 12/12 false-positive measurement at origin/main (the count moves with the corpus, the zero-true-positive invariant does not) |
| Spec-AC-05 | Zero added ceremony — no step, agent, script, flag or exit code; prompt delta at most 450 B in one file with the ledger true-up | done    | 78b05e4 TEST-011(clarify) + diet TEST-012 green | —         | TEST-012 pin -5844 plus measured G |
| Spec-AC-06 | In-flight scoping — terminal docs exempt, real corpus stays at zero findings, non-vacuity witnesses executable | done    | 00ece96 TEST-009(clarify) green, corpus 130 specs 0 findings | —         | corpus has zero in-flight specs today; this spec becomes the first |
| Spec-AC-07 | Honest docs — guide states the vocabulary, the limits and the corrected gate claim; RED_CLASS stamped at capture | done    | a466195 TEST-010+012(clarify) green | —         | the CHANGE-0140 shape is documented as NOT caught |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan

Components affected:

- `.aai/scripts/spec-lint.mjs` — ONE contiguous block placed after the
  `## Deltas` shape validation and before the SPEC-FROZEN consistency block,
  guarded by the existing `IN_FLIGHT_STATUSES.includes(fmStatus)` predicate.
  It contains: a module-local masking helper (fenced blocks and inline code
  spans replaced with spaces, newlines and `|` preserved), the marker scan
  emitting `unresolved-clarification` per occurrence plus
  `clarification-cap-exceeded` when the count exceeds 3, and the
  `ac-vague-term` scan over `parseAcTable`/`parseLeanAcTable` Description
  cells of the MASKED content (line located by the id's own table row, the
  `ac-without-test` precedent). Header comment updated to list the three new
  rules and to say plainly which one is a freeze precondition.
- `.aai/scripts/spec-freeze.mjs` — `'unresolved-clarification'` appended to
  `PRECONDITION_RULES`; the header's precondition list and the `usage()` text
  gain the same one-line mention (the `--help` contract is pinned by
  test-aai-spec-tools TEST-023's shape).
- `.aai/PLANNING.prompt.md` — one sentence appended to PRINCIPLE 1 (the
  DON'T-GUESS twin of "you have written a wish"), carrying the marker
  spelling, the cap, the priority order, the DON'T-ASK defaults and the rule
  id. Budget 450 B; nothing else in the corpus moves.
- `tests/skills/test-aai-spec-lint.sh` — new arms with a `(clarify)` scope
  suffix, following the existing `(actest)` / `(delta-stage-2)` precedent.
- `tests/skills/test-aai-spec-tools.sh` — new freeze arms beside TEST-020..024.
- `tests/skills/lib/prompt-diet-ledger.sh` + `tests/skills/test-aai-prompt-diet.sh`
  — one `JUSTIFIED_ADDITIONS` entry and the bumped TEST-012 pin.
- `docs/USER_GUIDE.md` — the spec-lint section gains the vocabulary, the
  lists, the three rule ids and D5's limits, and loses the stale
  "never ... hard-gates" claim.
- `CHANGELOG.md` — one `## [unreleased] — <title>` heading (per-entry heading
  form, never bullets under the scaffold).

Data flows and seams (each crossed by a named test):

- SEAM-1 spec-lint rule ids to spec-freeze `PRECONDITION_RULES`: a rule
  renamed on one side silently disarms the gate while every unit test still
  passes. Crossed by TEST-002, which drives the real `spec-freeze.mjs` CLI end
  to end rather than `lintContent`.
- SEAM-2 masking helper to the shared table parsers: masking that swallowed a
  `|` or a newline would change cell counts or line numbers and could silently
  disarm `ac-row-unparseable` or shift every finding's line. Crossed by
  TEST-001 (exact line assertions on a mixed fixture) and TEST-009 (the real
  129-spec corpus must still report exactly 0 findings).
- SEAM-3 prompt corpus to the diet ledger: the added bytes are inside
  TEST-010's live `.aai/*.prompt.md` glob. Crossed by TEST-008.
- SEAM-4 lint behavior to the guide's claims: the guide currently says
  spec-lint never hard-gates, which this scope makes more untrue. Crossed by
  TEST-010.

Edge cases:

- Bare `[NEEDS-CLARIFICATION]` with no question, and a marker with an
  unterminated bracket: both count (fail closed).
- Two markers on ONE line: two findings, same line number.
- A marker inside a fenced block that is never closed: everything after the
  opening fence is masked (fail open toward silence there is safe — the
  document is malformed markdown and docs-audit owns that).
- A code span containing a `|` inside an AC cell: the mask preserves `|`, so
  the cell count is unchanged and the row still parses.
- Marker in the frontmatter block: counted (there is no legitimate reason for
  one, and excluding it would need a second parser).
- L0 documents (tech-note in the CHANGE doc) have no AC table, so
  `ac-vague-term` yields nothing; the marker rules still apply.
- Case variants and the spaced spelling are NOT markers (D5.4) — pinned by a
  negative control so a future "helpful" widening has to argue with a test.

Residual risks (written down, not silently accepted):

- The gate changes AUTHORING behavior, and authoring behavior is carried by
  one prompt sentence read by one role. If Planning does not mark, nothing
  fires — the mechanism's floor is prompt compliance, not enforcement.
- Deleting a marker without answering it satisfies the gate (D5.2). The
  compensating control is the visible diff and code review, both of which are
  human judgment.
- Intake documents remain ungated (D5.5); the CHANGE-0140 class therefore
  still relies on Planning reading the code, exactly as it did that day.
- A future rule-id rename in spec-lint that misses `PRECONDITION_RULES` is
  caught only by TEST-002; there is no structural binding between the two
  files, and creating one is out of budget for this scope.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                    | Description                                                                 | Status  |
|----------|------------|-------------|-----------------------------------------|-----------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-spec-lint.sh      | live markers produce one `unresolved-clarification` finding each with exact 1-based lines and the question excerpt; bare and unterminated markers count; two markers on one line give two findings | green   |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-spec-tools.sh     | `spec-freeze.mjs` on a marker-carrying freezable fixture exits 3 naming `unresolved-clarification` and every occurrence; `cmp` proves the file untouched; `--dry-run` refuses identically; control with the marker deleted exits 0 and freezes | green   |
| TEST-003 | Spec-AC-01 | unit        | tests/skills/test-aai-spec-lint.sh      | specimen exemption: markers inside a fenced block and inside inline code spans produce ZERO findings, and a mixed fixture's pre-existing rule findings keep byte-identical lines | green   |
| TEST-004 | Spec-AC-03 | unit        | tests/skills/test-aai-spec-lint.sh      | four markers give 4 plus exactly 1 `clarification-cap-exceeded` at the fourth occurrence's line naming cap 3 and the priority order; three markers give no cap finding | green   |
| TEST-005 | Spec-AC-03 | integration | tests/skills/test-aai-spec-tools.sh     | the freeze refusal on the four-marker fixture names ONLY `unresolved-clarification`; the cap id appears nowhere in spec-freeze.mjs; `--help` names the new precondition | green   |
| TEST-006 | Spec-AC-04 | unit        | tests/skills/test-aai-spec-lint.sh      | `ac-vague-term` fires once per AC row whose Description carries a listed word, at the row's line; the `SPEC-0112`-derived in-flight control with four `fast` rows stays clean; backticked specimens stay clean | green   |
| TEST-007 | Spec-AC-04 | integration | tests/skills/test-aai-spec-tools.sh     | a fixture whose only finding is `ac-vague-term` FREEZES at exit 0 and gains both freeze halves — the advisory rule cannot block | green   |
| TEST-008 | Spec-AC-05 | unit        | tests/skills/test-aai-prompt-diet.sh    | TEST-012 pin equals -5844 plus the measured G and equals the independent re-sum of `JUSTIFIED_ADDITIONS`; the new entry names the sentence and its measurement | green   |
| TEST-009 | Spec-AC-06 | integration | tests/skills/test-aai-spec-lint.sh      | terminal-status fixture carrying a marker, four markers and a vague AC row yields zero new findings; the real corpus scan exits 0; this spec's own path lints clean | green   |
| TEST-010 | Spec-AC-07 | unit        | tests/skills/test-aai-spec-lint.sh      | grep contracts: PLANNING.prompt.md carries the marker sentence exactly once; USER_GUIDE documents the marker, cap 3, priority order, five DON'T-ASK entries, the three rule ids, the CHANGE-0140 not-caught limit, and no longer claims spec-lint never hard-gates | green   |
| TEST-011 | Spec-AC-05 | unit        | tests/skills/test-aai-spec-lint.sh      | contract pins: spec-lint usage still documents exit 0/1/2 with no new flag, spec-freeze still documents 0/1/2/3, and `git diff main --stat -- .aai/` touches only the two scripts and PLANNING.prompt.md | green   |
| TEST-012 | Spec-AC-07 | unit        | docs/ai/tdd/ (stored RED logs)          | `head -1` of every stored RED log for this scope is a `RED_CLASS:` line written at capture time | green   |

RED plan (hybrid; every RED observed and STORED before its GREEN work, with
`RED_CLASS:` written as line 1 AT CAPTURE — `product_red` when the planted
input reaches the assertion, `infra_fail` otherwise, per SKILL_TDD):

- TEST-001/003/004/006/009 RED: run the pre-change `spec-lint.mjs` against
  each new fixture. Observed result is ZERO findings and exit 0 — the absence
  of the whole rule set is the RED, captured verbatim per fixture.
- TEST-002/005/007 RED: run the pre-change `spec-freeze.mjs` against the
  marker-carrying fixture. Observed result is a SUCCESSFUL freeze (exit 0,
  file rewritten) — a marker sailing through the gate is the defect, captured
  with the resulting frozen bytes.
- TEST-010 RED: grep the pre-change `.aai/PLANNING.prompt.md` and
  `docs/USER_GUIDE.md` for the marker token — zero hits, plus the stale
  "never ... hard-gates" sentence still present.
- TEST-008 RED arises mechanically: the pin is -5844 before the sentence
  lands and the suite fails on the measured growth until the ledger entry is
  added.
- TEST-011/TEST-012 are green-side discipline pins; their RED is the
  corresponding arm above.

## Verification
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-spec-lint.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-spec-tools.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-ceremony-levels.sh`
- `node .aai/scripts/spec-lint.mjs` (real corpus, expect exit 0)
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0130-spec-vagueness-gate.md`
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.

## Evidence contract
For each implementation, validation, TDD and code review artifact, record:
- ref_id: spec-vagueness-gate
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path (docs/ai/tdd/ for RED artifacts per the hybrid strategy;
  `RED_CLASS:` stamped as line 1 at capture)
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
