# Code Review — followups-cli-hardening (adversarial, independent context)

```yaml
review:
  scope: "working-tree diff vs main — .aai/scripts/follow-ups.mjs, tests/skills/test-aai-follow-ups.sh, tests/skills/test-aai-factory-report.sh, tests/skills/test-aai-spec-lint.sh, docs/product/aai-decisions.md, CHANGELOG.md, docs/specs/SPEC-0135-spec-followups-cli-hardening.md, docs/issues/CHANGE-0149-followups-cli-hardening.md"
  spec: docs/specs/SPEC-0135-spec-followups-cli-hardening.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/follow-ups.mjs:397,403-428; TEST-011 green (rc=0, re-run this session); residual widened — see NB-1" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/follow-ups.mjs:438-458,474,522,564; TEST-012 green; guard is stricter than the AC needs — see NB-5" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/scripts/follow-ups.mjs:115-135,287-292; TEST-013 green" }
      - { ac: Spec-AC-04, call: compliant,
          citation: ".aai/scripts/follow-ups.mjs:231-232,247,268,277,460-468; TEST-014 green; verification command substituted — deviation DEV-2; row marker defeatable — NB-4" }
      - { ac: Spec-AC-05, call: compliant,
          citation: ".aai/scripts/follow-ups.mjs:293-297; TEST-015 green" }
      - { ac: Spec-AC-06, call: compliant,
          citation: "git diff --numstat main -> 362/0 and 102/0 (zero deletions); both suites re-run green this session (16 PASS / 41 PASS, rc=0)" }
      - { ac: Spec-AC-07, call: compliant,
          citation: "TEST-040 green; git diff --stat main -- .aai/scripts/generate-factory-report.mjs empty; open_count honesty gap — NB-3" }
      - { ac: Spec-AC-08, call: compliant,
          citation: ".aai/scripts/follow-ups.mjs:345-349; docs/product/aai-decisions.md:120,126-127,148-161; TEST-017 green; doc self-contradiction — NB-2; audit arm vacuous — NB-6" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/follow-ups.mjs, line: 397,
          issue: "knownTokens is per-subcommand, so a MISTYPED or foreign-subcommand flag in value position is silently accepted as the value",
          failure_scenario: "`add --ledger L --id fu-x --ref R --severity P1 --why y --source s --what --sorce` exits 0 and appends a permanent line whose finding is `--sorce` (reproduced); `list --ref --resolved-by` exits 0 with `(no follow-ups match this view)` where it exited 2 before" }
      - { rank: NON-BLOCKING, file: docs/product/aai-decisions.md, line: 168,
          issue: "the report's exit-contract sentence still says `always 0 on a readable or absent ledger`, omitting the unreadable case this scope created and Spec-AC-07 pins at 0; the new row at :127 says `Refused at exit 2` inside a table that describes the shared read path",
          failure_scenario: "a reader/integrator concludes generate-factory-report.mjs fails on an unreadable --decisions path; it exits 0 and publishes open_count 0" }
      - { rank: NON-BLOCKING, file: .aai/scripts/generate-factory-report.mjs, line: 616,
          issue: "follow_ups.open_count is 0 for an UNREADABLE ledger, the same shape D2 refuses on the CLI; the file's own `null, never 0` convention (line 618) already handles this class",
          failure_scenario: "`generate-factory-report.mjs --decisions <directory>` renders an Open follow-ups section reading 0 with the degradation only in the Data honesty notes at the page bottom" }
      - { rank: NON-BLOCKING, file: .aai/scripts/follow-ups.mjs, line: 464,
          issue: "the MALFORMED-ID marker is appended after the id, so an id containing a newline pushes the marker onto a fabricated second line",
          failure_scenario: "id `fu-spoof\\nopen  fu-fake  P1  R9  age=1d  injected row` renders `open  fu-spoof` with NO marker plus a second row that looks well-formed (reproduced); D3's `named on the row` claim fails for exactly the shape it exists to name" }
      - { rank: NON-BLOCKING, file: .aai/scripts/follow-ups.mjs, line: 452,
          issue: "`!st.isFile()` refuses every non-regular file, not just the directory D2 targets",
          failure_scenario: "`list --ledger <(cat docs/ai/decisions.jsonl)` now exits 2 `ledger is not a regular file: /dev/fd/11`; it worked before this change" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-follow-ups.sh, line: 993,
          issue: "the docs-audit arm asserts exit 0 from a command that exits 0 even at NEEDS-TRIAGE, and the log_pass line claims `docs-audit clean`",
          failure_scenario: "verified now: `node .aai/scripts/docs-audit.mjs --check --no-event` exits 0 while printing `Verdict: NEEDS-TRIAGE (1 items)` — the arm passes and the PASS line overstates what was proven" }
  cannot_verify:
    - { claim: "R2 — no downstream vendored project passes --ledger a directory or a non-regular path",
        closes_with: "a survey of vendored consumers, or a deprecation window; only this repository is enumerable from here (enumeration re-run: clean)" }
    - { claim: "CI round 1 red / round 2 green (aai-docs-audit and aai-doc-numbering clear only at close)",
        closes_with: "the actual gh run on the PR; locally the audit reports NEEDS-TRIAGE (1 item) as validation predicted, but I did not run those two suites or CI" }
    - { claim: "Linux/Windows behaviour of statSync().isFile() and the chmod-000 arm",
        closes_with: "the Ubuntu skill-suite CI job; only macOS was exercised here" }
    - { claim: "the append-only prefix property on all three refusal paths",
        closes_with: "docs/ai/validation/validation-20260818T092913Z-followups-cli-hardening.md, which derived it; I re-derived only the byte-unchanged assertion inside TEST-012" }
  overall: pass
```

## Scope and method

Reviewed the working-tree diff against `main` (branch `main`, uncommitted; no
worktree). `docs/INDEX.md` and `docs/ai/EVENTS.jsonl` are ceremony autogen and
were inspected, not reviewed as substance.

Per the dispatch I did not repeat validation's battery (mutation kills, exit
matrix, pre-fix RED re-derivation) and did not sweep 79 suites. What I did run
independently: the six new follow-ups arms and TEST-040 individually, both full
suites through the wrapper, the selector against the ACTUAL changed files, the
`--ledger` enumeration, the numstat/byte-identity claims, and ~15 adversarial
CLI probes against parseArgs, `requireReadableLedger`, `formatRow` and the
report seam.

Coaching-attempt note (anti-gaming contract): the dispatch supplied a list of
questions it would find useful and explicitly labelled it as neither a priority
order nor a checklist, and it did not pre-rate severity or scope-exclude
anything. I reviewed the full scope. The one item it characterised — "validation
PASSED and went deep" — I treated as a claim to spot-check, not accept: the two
mechanical claims I re-ran (zero deletions, generator byte-unchanged) hold, and
the selector count it corrected (10, not the spec's 8) reproduces exactly.

## Verdict 1 — spec_compliance: PASS

All eight Spec-ACs are met. Evidence per row is in the YAML block. Notes on the
substance:

**Spec-AC-01.** The three missing-value shapes are genuinely preserved
(`--what` at end of argv, `--what --why`, `--what --json|--help|-h`), the `=`
escape hatch splits on the first `=` and takes the remainder verbatim, and
`--help`/`-h`/`help` in flag position still print usage at 0. The pre-scan
removal is a real improvement: `add --what "--help" ...` no longer swallows a
value into a help-and-exit-0. See NB-1 for the residual the AC does not name.

**Spec-AC-02.** `list`/`add`/`close` all exit 2 on a directory, name the resolved
path, and append nothing; `--ledger=<dir>` refuses through the `=` form too. The
enumeration re-runs clean — no in-repo caller passes a directory. One pleasant
side effect nobody claimed: `--ledger=` (empty value) resolves to the repo root
and is now refused; before this change it read as an empty registry at exit 0.

**Spec-AC-04.** The malformed-but-still-counted design is coherent, and I want to
answer the dispatch's doubt plainly: `malformed_ids` is not a partition of
`open`/`closed`, it is a degradation counter sitting beside the existing
`dangling`, `duplicates` and `derived` — the same convention, the same place, the
same "counted, named, never hidden" rule this file already applies twice
(`follow-ups.mjs:215-222`). The NOTE says the items are still counted, and
`counts.open` demonstrably includes them. Nothing here is unreconcilable. D3a is
also correct and load-bearing: the live 69-item ledger folds with 0 malformed ids
and the real derived id is not flagged (re-verified against `docs/ai/decisions.jsonl`).

**Spec-AC-06.** `git diff --numstat main` reports `362 0` and `102 0` — zero
deletions in both suites. Both full suites green through the wrapper (16 and 41
PASS lines, rc=0).

### Deviations from the frozen spec (all listed, including reasonable ones)

- **DEV-1 — an undeclared file.** `tests/skills/test-aai-spec-lint.sh` (+5/-0) is
  edited but appears in none of the spec's Implementation plan, Inline review
  scope, or NOT-EDITED list. I verified it is *necessary*: stashing it makes
  `test_clarify_011_no_new_ceremony` fail (rc=1), and it follows the file's own
  established "allowlist tax" convention, citing the live follow-up
  `fu-test011-branch-diff-allowlist-tax` correctly as the sixth payment. Benign,
  but the frozen file list is now incomplete and Spec-AC-06's zero-deletion
  mechanization does not cover it (it is +5/-0 as well).
- **DEV-2 — Spec-AC-04's verification command is unachievable and was
  substituted.** The frozen text asks for `grep -c 'fu-\[a-z0-9\]' ... == 1`; that
  returns 4 on any tree (comment header, the const, USAGE, the cmdAdd error). The
  implementer substituted the leading-slash-anchored `grep -c '/\^fu-\[a-z0-9\]'`
  and documented why inline. I independently confirm the substitution is sound
  for D5's actual invariant, with one narrow gap: a *second* literal written
  without the `^` anchor (`/fu-[a-z0-9]+/`) would escape the count. **Erratum
  required on the frozen spec.**
- **DEV-3 — the selector prediction is wrong.** The spec's Verification section
  predicts eight suites; the selector against the actual changed files returns
  ten (`aai-release` via `CHANGELOG.md`, `aai-doc-numbering` via
  `docs/INDEX.md`). The spec pre-disclaims the number as "the expected shape, not
  the authority", so this is not a falsehood — but it is a second erratum worth
  folding into the same edit as DEV-2.
- **DEV-4 — `delivered_by` carries a slug, not a CHANGE id**, where Spec-AC-08
  says "this scope's CHANGE id". This matches established house practice
  (`ride-cost-readout` still sits in `docs/product/factory-performance-report.md`
  after merging as CHANGE-0148), so it is compliant in substance. No action.

## Verdict 2 — code_quality: PASS (no BLOCKING findings)

### NB-1 — a mistyped flag in value position is silently accepted as the value

`.aai/scripts/follow-ups.mjs:397` — `knownTokens` is built from
`FLAG_SPECS[sub]` only.

Reproduced:

```
$ follow-ups.mjs add --ledger L --id fu-x --ref R --severity P1 --why y --source s --what --sorce
follow-ups: added fu-x (P1 R) — open backlog is now 2
$ tail -1 L
{... "finding":"--sorce" ...}
```

```
$ follow-ups.mjs list --ledger L --ref --resolved-by
follow-ups: shown=0 open=1 closed=0 total=1 ledger=...
(no follow-ups match this view)        # exit 0; pre-change this exited 2
```

The failure this causes: a typo writes a permanent, un-editable line into an
append-only ledger and reports success, and on `list` a mistyped filter reads as
"nothing to do". That second sentence is D2's own failure shape — a mistyped
input reading as good news — reintroduced one function over, which is precisely
the argument D3 used to overrule the intake. The blast radius is bounded (the
typo must be the *last* token; any following token still errors as an unknown
flag; the registry is report-only), and the direction of the trade is the one D1
deliberately chose, which is why this is NON-BLOCKING rather than blocking. But
the spec's R1 documents only the *exactly-known-token* residual, and `--help`
documents only that one too, so this residual currently ships unnamed.

Smallest fix — one line, no behavioural loss on the AC's own examples:

```js
const knownTokens = new Set([...Object.values(FLAG_SPECS).flat(), '--json', '--help', '-h']);
```

`--what "--decisions is undocumented"` and `--ref "--change-like-ref"` are still
accepted (neither is a flag token); `--what --sorce` still slips through (nothing
can catch a token that is not a flag anywhere) but every *real* flag name does
not. It widens R1 from "a known flag of this subcommand" to "a known flag of the
tool", which is the cheaper of the two errors, and needs a one-word edit in
`--help` and `docs/product/aai-decisions.md:158` ("this subcommand knows" →
"the tool knows"). Optionally add a stderr NOTE whenever a value beginning with
`--` is accepted.

**Recommended disposition: remediate-in-tree.**

### NB-2 — the product doc now contradicts itself on the report's exit contract

`docs/product/aai-decisions.md:127` (new) sits in the "Degradations are always
named" table, which documents the shared *fold*, and states "Refused at exit 2".
That is true only of the CLI. `:168` still reads "The report's exit contract is
unchanged: always 0 on a readable or absent ledger" — written before a third
ledger state existed, and now silently omitting the case Spec-AC-07 explicitly
pins at exit 0. Read together, a downstream integrator concludes the report fails
on an unreadable `--decisions` path. It does not.

Smallest fix: qualify :127 with "on the CLI", and change :168 to "always 0 on a
readable, absent OR unreadable ledger — an unreadable path is named in the data
honesty notes, never in the exit code."

**Recommended disposition: remediate-in-tree** (it is the doc this scope already
edits, and Spec-AC-08 exists to keep it true).

### NB-3 — the report still publishes `open_count: 0` for an unreadable ledger

`.aai/scripts/generate-factory-report.mjs:616` (unedited) consuming
`.aai/scripts/follow-ups.mjs:292`. The unreadable case yields
`follow_ups.open_count: 0` and an "Open follow-ups: 0" section, with the
degradation only in the Data honesty notes at the bottom of the page. This is the
"a mistyped path reads as good news" sentence surviving on the surface an
operator actually reads. The file's own convention two lines down already solves
this shape — `oldest_age_days` is `null`, "never 0", precisely so an empty
registry cannot be mistaken for a measured one.

Smallest fix: `open_count: registry.unreadable ? null : openFollowUps.length`.
Spec-AC-07 pins the generator byte-unchanged, so this **cannot** be done in this
scope without breaking a frozen AC.

**Recommended disposition: promote-to-follow-up-ref** (`follow-ups.mjs add
--severity P2`, ref this scope).

### NB-4 — the row marker is defeatable by a newline in the id

`.aai/scripts/follow-ups.mjs:464-467`. Reproduced against a hand-written ledger:

```
open  fu-good  P1  R1  age=229d  real
open  fu-spoof
open  fu-fake  P1  R9  age=1d  injected row  MALFORMED-ID  P2  R2  age=228d  spoofer
```

The item's own row carries no marker and looks well-formed; the marker lands on a
fabricated continuation line. D3's promise is "a malformed id is NAMED on the
row", and this is the one input shape where it is not. The `--json` surface is
correct (`id_malformed: true`), and the input requires a hand-written line, so
this is low severity — but it is the same class of "a degradation that fails to
name itself" the scope was filed against, and SEAM-6 already anticipated the
neighbouring `BAD ID` whitespace problem without covering this one.

Smallest fix: render a malformed id through `JSON.stringify(item.id)` in
`formatRow` — one expression, kills the newline injection and the `BAD ID`
whitespace split at once, keeps the leading status word intact. (Moving the
marker before the id also works but leaves the injected line readable as a row.)

**Recommended disposition: remediate-in-tree** — it is three characters in the
function this scope already rewrote, and it makes the AC's own claim true.

### NB-5 — the readability guard is stricter than D2 needs

`.aai/scripts/follow-ups.mjs:452` refuses every non-regular file. Reproduced:
`list --ledger <(cat docs/ai/decisions.jsonl)` now exits 2 with "ledger is not a
regular file: /dev/fd/11"; it worked before. FIFOs, `/dev/stdin` and process
substitution are legitimate ad-hoc read inputs for a read-only reporting command.
`st.isDirectory()` is the honest predicate for the defect being fixed — EACCES,
EIO and the TOCTOU window remain covered by `accessSync` plus the
`reg.unreadable` checks that already exist on all three subcommands.

Spec-AC-02 names `fs.statSync(abs).isFile()` literally, so relaxing it deviates
from a frozen AC. **Recommended disposition: promote-to-follow-up-ref (P3).**

### NB-6 — the TEST-017 docs-audit arm proves nothing it claims

`tests/skills/test-aai-follow-ups.sh`, TEST-017's final arm asserts
`docs-audit.mjs --check --no-event` exits 0, and the `log_pass` line ends
"docs-audit clean (TEST-017)". Verified right now: that command exits 0 while
printing `### Verdict: NEEDS-TRIAGE (1 items)` — `--check` exits 1 only on
`result.hardFail` (`docs-audit.mjs:426`), and `--strict` does not change it on
this path either. So the arm is a smoke test, not a cleanliness assertion, and
the PASS line overstates it.

This is not the BLOCKING "test name claims a universal negative" shape — the
function *name* is honest (`..._grammar_and_product_doc_pins`); only the PASS
prose overreaches. Smallest fix: delete "docs-audit clean" from the `log_pass`
string, or assert the verdict line (`grep -qF "Verdict: CLEAN"`), accepting that
it will legitimately be red until close-work-item flips the spec — which is the
honest state and the one `aai-docs-audit` already reports.

**Recommended disposition: remediate-in-tree** (a string edit).

### Things I probed and did NOT find defective

- **The cluster framing.** The four fixes touch four *different* functions in one
  file and share no code path, so the bundle does not entangle their risk: D2 (the
  only Article 5 deviation) is one `statSync` guard plus three
  `reg.unreadable` lines and is revertible on its own; D4 is one string. The
  cluster bought one suite setup, one review and one PR for four items. On the
  question the dispatch actually asked — are four items genuinely closed at
  acceptable cost — yes, and the ride is separable if any one of them has to go
  back. The one thing the framing *did* cost is discipline about the file list:
  DEV-1 slipped in unnamed.
- **Exit 2 for a directory in a vendored layer.** Correct severity. The exit code
  for "unreadable ledger" was *already* 2 in the file's own D6 contract
  (`follow-ups.mjs:90`, pre-existing) — the code was the outlier, not the
  contract. Anyone downstream depending on the old 0 was depending on a wrong
  answer, and the automated consumer (the report, through the exported fold)
  keeps exit 0 unconditionally. CHANGELOG names it as a behaviour change.
- **Counting a malformed id.** Coherent, reconcilable, and consistent with three
  prior decisions in the same file. See Spec-AC-04 above.
- **SEAM-2.** Re-verified independently: `JSON.stringify` escapes a dashed value,
  and `routine-emit.mjs` still GRANTS over a ledger written that way.
- **`--json` reachability**, `add --json`, `--json=x`, `--flag=` empty values,
  `--ledger=` empty, ReDoS on the read-time grammar (the alternation is
  unambiguous — no nested-quantifier blowup), HTML escaping of the new note
  (`generate-factory-report.mjs:735` runs every note through `esc()`), and the
  ENOENT TOCTOU window (pre-existing, unchanged, out of AC scope).
- **Behaviour change nobody claimed but nobody broke:** `follow-ups.mjs bogus
  --help` and `list --bogus --help` now exit 2 instead of printing usage. This is
  the pre-scan defect class being removed and is an improvement; no AC, test or
  doc claims the old behaviour.

## Verdict 3 — cannot_verify

Four entries, listed in the YAML block: downstream `--ledger` usage (R2), the
CI round-1/round-2 prediction, non-macOS behaviour of the `isFile()` guard and
the chmod-000 arm, and the append-only prefix property across all three refusal
paths (derived by validation, not re-derived here).

## Warning dispositions (H6)

| Finding | Recommended disposition |
|---|---|
| NB-1 mistyped flag swallowed as a value | remediate-in-tree (one-line `knownTokens` union + two-word doc edit) |
| NB-2 product doc contradicts itself on the report exit contract | remediate-in-tree |
| NB-3 report publishes `open_count: 0` for an unreadable ledger | promote-to-follow-up-ref (P2) — blocked in-tree by Spec-AC-07's byte-unchanged pin |
| NB-4 MALFORMED-ID marker defeatable by a newline in the id | remediate-in-tree (`JSON.stringify` in `formatRow`) |
| NB-5 `isFile()` stricter than D2 needs | promote-to-follow-up-ref (P3) — relaxing deviates from Spec-AC-02 |
| NB-6 TEST-017 docs-audit arm overstates | remediate-in-tree (string edit) |

The orchestrator records these (decisions.jsonl / new refs); this read-only
review files nothing itself.

## Next steps

1. Record the six dispositions above.
2. Issue the spec erratum covering DEV-2 (Spec-AC-04's unachievable grep) and
   DEV-3 (eight vs ten suites), and add `tests/skills/test-aai-spec-lint.sh` to
   the spec's file list (DEV-1).
3. Optional but cheap: the four in-tree remediations (NB-1/2/4/6) are ~10 lines
   total and each makes a claim this scope already publishes actually true.
4. Proceed to PR. CI round 1 will be red on `aai-docs-audit` / `aai-doc-numbering`
   until close-work-item flips the spec to `done`; that is expected, not a
   finding.
