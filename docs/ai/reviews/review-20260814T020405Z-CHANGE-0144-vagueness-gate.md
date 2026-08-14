# Code Review — CHANGE-0144 / spec-vagueness-gate (dual verdict)

```yaml
review:
  scope: 16bc5df..HEAD on feat/spec-vagueness-gate (8 commits, 14 files)
  spec: docs/specs/SPEC-0130-spec-vagueness-gate.md (frozen at 16bc5df)
  intake: docs/issues/CHANGE-0144-vagueness-gate.md
  ceremony_level: 1
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/spec-lint.mjs:601-621; TEST-001/003(clarify) green; reviewer probes P8-P16" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/spec-freeze.mjs:82,275-277; TEST-002(clarify) green; reviewer freeze probe C2b (exit 3, md5 identical)" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/scripts/spec-lint.mjs:622-628; TEST-004/005(clarify) green; mutation M6 killed by TEST-004" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "TEST-006/007(clarify) green; SPEC-0112-derived control; behavior correct — its DOCUMENTATION is contradicted by spec-lint.mjs:381 (BLOCKING-1)" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "PLANNING.prompt.md +423 B exactly; spec-lint usage() byte-identical to base; ledger -5844+423=-5421; TEST-012 re-sum green" }
      - { ac: Spec-AC-06, call: compliant,
          citation: "corpus 130 specs / 0 findings exit 0; own spec exit 0; mutation M4 (IN_FLIGHT guard removed) killed by TEST-009(clarify)" }
      - { ac: Spec-AC-07, call: non-compliant,
          citation: "docs/USER_GUIDE.md:1069-1071 — the corrected paragraph states '12 table rows across 6 specs and all 16 are domain vocabulary'; the guide's own measurement contradicts itself" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/spec-lint.mjs, line: 381,
          issue: "the F1 remediation left the unreproducible 16 rows / 8 specs / 16-16 measurement in the engine source and in CHANGELOG.md:40-42; measured 12/6 at origin/main and 15/7 at HEAD",
          failure_scenario: "an engineer adding a fifth vague word follows the file header's own instruction ('any future word must clear the same measurement'), runs the named grep, gets 12 or 15, and cannot reconcile it with the recorded 16 — the exact unverified-claim shape this change exists to prevent" }
      - { rank: NON-BLOCKING, file: .aai/scripts/spec-lint.mjs, line: 396,
          issue: "F3 confirmed independently — the pipe-preservation clause is entirely unpinned; dropping it leaves 48/48 + 21/21 arms green and the corpus at exit 0",
          failure_scenario: "a future refactor simplifies the mask to /[^\\n]/ and silently disarms ac-vague-term on any AC row whose Description carries a code-span pipe; no test objects" }
      - { rank: NON-BLOCKING, file: .aai/scripts/spec-lint.mjs, line: 388,
          issue: "maskCodeSpecimens re-implements, more weakly, the CommonMark-aligned masker already in .aai/scripts/lib/docs-audit-core.mjs:782-875, reintroducing both bugs that file explicitly fixed (SPEC-0013 W3)",
          failure_scenario: "a line-initial 3-backtick inline span opens a phantom fence that masks the rest of the document (0 findings on a live marker); a 3-backtick example nested in a 4-backtick fence is treated as closing it, so a documented specimen is reported and REFUSES a legitimate freeze" }
      - { rank: NON-BLOCKING, file: docs/USER_GUIDE.md, line: 1078,
          issue: "the limits list omits that backticking a marker satisfies the freeze gate, while the paragraph two above claims resolution is deletion and every resolution is a readable diff hunk",
          failure_scenario: "an author under time pressure wraps the marker in backticks; spec-freeze exits 0 with the marker text still in the file, and the diff a reviewer sees is a two-character edit rather than a removed line" }
      - { rank: NON-BLOCKING, file: .aai/scripts/spec-lint.mjs, line: 637,
          issue: "ac-vague-term's line locator takes the FIRST table line containing the AC id; Test Plan rows also carry AC ids",
          failure_scenario: "in a spec whose Test Plan precedes the AC Status table the finding points at the Test Plan row (measured: reported line 19, real row line 25)" }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0130-spec-vagueness-gate.md, line: 461,
          issue: "edge-case bullet claims a code-span pipe in an AC cell leaves the row parsing; measured, cell counts are stable but the row does NOT parse in norm or masked",
          failure_scenario: "a planner trusts the bullet, writes a pipe inside a code span in an AC Description, and gets ac-row-unparseable — the tree's own LEARNED rule says never do this" }
      - { rank: NON-BLOCKING, file: docs/ai/tdd/, line: 0,
          issue: "F7 confirmed — TEST-008 carries neither a red- nor a report- artifact, and TEST-012(clarify) structurally cannot detect the omission (it iterates the red-* files that exist)",
          failure_scenario: "the next scope skips an artifact the same way and the suite stays green" }
  cannot_verify:
    - { claim: "the marker vocabulary changes Planning's authoring behavior (the mechanism's floor is one prompt sentence read by one role)",
        closes_with: "N subsequent planning runs measured for marker usage on genuinely unverifiable claims" }
    - { claim: "the new arms behave identically on CI and on Windows/PowerShell",
        closes_with: "a CI run on the PR" }
    - { claim: "TEST-011's .aai/ diff pin actually executes on CI rather than taking its named degrade path",
        closes_with: "a CI log showing the pin ran, not the 'neither origin/main nor main resolves' line" }
  overall: fail
```

## Scope and method

Diff `16bc5df..HEAD`, 8 commits, 14 files. I re-ran every suite the dispatch
named, re-derived the F1 measurement at two refs myself, ran six mutations of
the engine in an isolated clone (never touching the product tree), and drove
`spec-lint`/`spec-freeze` against 25 hand-built fixtures covering the evasion
surface. No coaching attempt to record: the dispatch named its two deferred
findings and asked for an independent number rather than supplying one.

Test runs (all local, macOS):

| Command | Result |
|---|---|
| `bash tests/skills/test-aai-spec-lint.sh` | exit 0 — 48 PASS, 0 FAIL |
| `bash tests/skills/test-aai-spec-tools.sh` | exit 0 — 21 PASS, 0 FAIL |
| `bash tests/skills/test-aai-prompt-diet.sh` | exit 0 — TEST-012 pin -5421 == re-sum |
| `bash tests/skills/test-aai-userguide-rollup.sh` | exit 0 |
| `node .aai/scripts/check-test-registration.mjs` | exit 0 |
| `node .aai/scripts/spec-lint.mjs` (corpus) | exit 0 — 130 specs, 0 findings |
| `node .aai/scripts/docs-audit.mjs --gate-file <spec>` | GATE PASS |

Red only from this scope's pre-close false-open shape, as the dispatch stated,
and I confirm it rather than counting it: `docs-audit` reports exactly one item
— `spec-vagueness-gate | probable-false-open | delivery commit(s) 06d610f ...
AC Status table fully terminal with evidence` — with 0 orphans, 0 duplicate doc
ids, 0 body-lint findings. `test-aai-doc-numbering.sh` TEST-013 fails on
`assert_contains repo-audit.log "CLEAN"`, which is the same single item seen
through the repo-audit verdict. Neither is a defect of this diff.

## Verdict 1 — spec_compliance: FAIL

Six of seven ACs are compliant, several of them provably so rather than merely
asserted. Spec-AC-07 fails on one sentence.

**Spec-AC-01 — compliant.** `spec-lint.mjs:601-621`. I reproduced the
behaviours independently rather than trusting the arms: two markers on one line
give two findings at that line; a bare `[NEEDS-CLARIFICATION]` and an
unterminated one both count; a marker in the frontmatter counts (as D2 says);
an unclosed inline span masks nothing; markers inside ``` , ~~~ , lang-tagged
and list-indented fences are all exempt; a four-space indented code block is
NOT exempt (as D1 explicitly claims). Line numbers are exact.

**Spec-AC-02 — compliant.** `spec-freeze.mjs:82` adds the id to
`PRECONDITION_RULES`; the gate at `:275-277` runs only when `changed`. Driven
end to end: a draft fixture carrying one marker refuses at **exit 3**, the
refusal names `[unresolved-clarification]` and the question text, and the file
is byte-identical afterwards (md5 before == after). Deleting the marker freezes
at exit 0. Mutation M3 (rename the rule id in spec-lint only, the SEAM-1 risk
the spec names) is killed by five arms including TEST-002(clarify) in the
spec-tools suite — the seam is genuinely crossed, not just claimed.

**Spec-AC-03 — compliant.** Cap fires exactly once, at the fourth occurrence's
line, naming count, cap and the trim order; three markers stay clean. Mutation
M6 (`>` → `>=`) is killed by TEST-004(clarify), so the boundary is real rather
than incidental. The cap id appears nowhere in `spec-freeze.mjs`.

**Spec-AC-04 — compliant on behaviour.** Three findings on the three offending
rows, backticked specimen row clean, `fast` row clean, and the SPEC-0112-derived
in-flight control (which the arm re-derives from the real file and fails rather
than skips if it is missing) stays clean. A vague-only fixture freezes at exit
0. Its documentation is a separate problem — see BLOCKING-1.

**Spec-AC-05 — compliant, measured.** `.aai/PLANNING.prompt.md` 10227 → 10650 =
**exactly 423 B**, the only prompt-corpus file touched (`git diff --name-only
16bc5df..HEAD -- '.aai/*.prompt.md' '.aai/AGENTS.md'` returns that one path).
`spec-lint.mjs`'s `usage()` is **byte-identical** to the base revision, so no
new flag and exits 0/1/2 unchanged; `spec-freeze.mjs`'s flag set is identical
and its five `process.exit` sites still cover 0/1/2/3. Ledger: -5844 + 423 =
**-5421**, and TEST-012's independent re-sum of `JUSTIFIED_ADDITIONS` agrees.

**Spec-AC-06 — compliant.** Corpus scan 130 specs / 0 findings / exit 0; this
spec's own path exit 0; a terminal-status fixture carrying a live marker, four
markers and a vague row produces nothing. The scoping is not decorative:
mutation M4 (replace `IN_FLIGHT_STATUSES.includes(fmStatus)` with `true`) is
killed by TEST-009(clarify), and by that arm alone — which is exactly what a
negative control should look like.

**Spec-AC-07 — NON-COMPLIANT.** The guide does everything the AC lists: marker
spelling, cap, priority order, the five DON'T-ASK rows, the three rule ids, the
CHANGE-0140 not-caught sentence, and the stale "never writes files or
hard-gates" claim is gone. All nine stored RED logs carry `RED_CLASS:` as line
1. It fails on one sentence: `docs/USER_GUIDE.md:1069-1071` now reads "returns
**12** table rows across **6** specs and all **16** are domain vocabulary ... a
**12/12** false-positive rate". The corrected paragraph contradicts itself in
the middle. An AC whose entire subject is an honest limits section cannot pass
while its own measurement sentence disagrees with itself.

## Verdict 2 — code_quality: FAIL

### BLOCKING-1 — the F1 remediation did not reach the engine

`.aai/scripts/spec-lint.mjs:380-384` and `CHANGELOG.md:40-42`.

The remediation commit message says the count was "corrected in all four sites
with the ref named". Six sites in the tree carry that measurement. Four were
corrected. Two were not, and one of the two is the source file that *implements*
the exclusion:

```
// D4 — closed, MEASURED word list. `fast` is deliberately absent: in this
// corpus `grep -rInE '^\|.*\bfast\b' docs/specs/*.md` returns 16 table rows
// across 8 specs and all 16 are domain vocabulary ("fails fast", "fast path",
// "prints LANE fast"), a measured 16/16 false-positive rate.
```

My independent measurement, both refs:

| Ref | Rows | Specs | True positives |
|---|---|---|---|
| `origin/main` (79e19fb) | **12** | **6** | 0 |
| `HEAD` worktree (a86f017) | **15** | **7** | 0 |

I inspected all 12 rows at `origin/main`: `fails fast`, `fail-fast`, `fast
path`, `prints LANE fast`, `rc 0 fast`, `fast-eligible`, `exits 0 fast`,
`throttled fast path` — every one domain vocabulary, zero true positives. The
three extra rows at HEAD are contributed by this branch's own spec. **16 rows
across 8 specs is reproducible at neither ref**, which is precisely what
validation F1 said.

So, answering the question the dispatch asked directly:

- **The corrected wording is honest, and the added hedge is the right fix.**
  "12/12 ... at origin/main (the count moves with the corpus, the
  zero-true-positive invariant does not)" is exactly right, and my two
  measurements demonstrate the drift it anticipates (12 → 15 in one branch).
  Naming the ref is what makes the number checkable. Keep that sentence.
- **The remediation as a whole is not complete, and the claim that it is, is
  itself the defect class this scope polices.** A change whose thesis is "an
  unverified claim reads exactly like a verified one" cannot ship an engine
  comment stating a measurement that no ref reproduces, under a header
  instructing the next engineer to re-run that very grep before adding a word.

Fix: three comment lines in `spec-lint.mjs`, three in `CHANGELOG.md`, and the
word "16" → "12" at `USER_GUIDE.md:1070`. Roughly ten minutes, and it closes
Spec-AC-07 at the same time.

### NON-BLOCKING-1 — F3 confirmed, with the independent number and the reason

`.aai/scripts/spec-lint.mjs:396`. Mutation applied in an isolated clone:

```js
- const blank = (s) => s.replace(/[^\n|]/g, ' ');
+ const blank = (s) => s.replace(/[^\n]/g,  ' ');
```

**Survivors: everything.** 48/48 spec-lint arms PASS, 21/21 spec-tools arms
PASS, and the 130-spec corpus scan still exits 0. Not one assertion in the tree
observes the clause. That is my independent number, and it matches the
validator's conclusion.

Worth recording *why*, because the follow-up currently says only "not
mutation-pinned". TEST-003(clarify)'s cell-count assertion is
`count(ac-row-unparseable) == 1` — but `ac-row-unparseable` is computed from
`norm`, never from `masked`, so it is structurally incapable of observing a
masking-induced cell shift. The arm's only masked-table-dependent assertion is
`ac-vague-term` on Spec-AC-01, whose Description contains no backticks, making
masking a no-op there. The fixture is not weak; the *observable* is wrong. Any
retry needs a row that parses only while code-span pipes survive masking.

**Deferring F3 was right.** The clause is currently correct — I verified cell
counts are byte-stable across masking for plain, code-span, raw-pipe and
escaped-pipe cells (8/8, 8/8, 9/9, 9/9) — and no document in the corpus
exercises it. P3 is the correct severity.

One thing to *not* chase: I also mutated newline preservation
(`/[^\n|]/` → `/[^|]/`) and it likewise survives 100%. That is an **equivalent
mutant, not a test gap**. `blank()` only ever receives a single line (from
`norm.split('\n')`) or an inline match bounded by `[^\n]*?`, so it never sees a
newline; preservation comes from `out.join('\n')`. The `\n` in the character
class is inert defensive code. Please don't file a second follow-up for it.

### NON-BLOCKING-2 — the masker duplicates a hardened one that already exists here

`.aai/scripts/spec-lint.mjs:388-410` hand-rolls a fence/inline-span masker.
`.aai/scripts/lib/docs-audit-core.mjs:782-875` already contains a
CommonMark-aligned one, with two bugs explicitly fixed under SPEC-0013 review
W3 and commented as such. The new masker reintroduces both:

| Probe | Shape | spec-lint | Correct |
|---|---|---|---|
| A | line-initial 3-backtick **inline span**, live marker below | **0 findings** | 1 |
| B | fence "closed" by a lang-tagged ```` ```js ```` line, specimen below | **1 finding** | 0 |
| C | 3-backtick example nested inside a 4-backtick fence | **1 finding** | 0 |

Probe A is a *silent gate disarm*: docs-audit-core's guard ("a line-initial
backtick run followed by ANOTHER backtick on the same line is inline code, not
a fence open — instead of opening a phantom fence that swallows the rest of the
doc") is exactly what is missing here, and without it one prose line silences
the freeze precondition for the whole document. Probes B and C are the opposite
failure: spec-lint closes a fence on any line starting with 3+ of the same
character, ignoring run length and info string, so the standard way to document
fenced markdown — a 3-backtick example inside a 4-backtick fence — produces a
false positive that **refuses a legitimate freeze**.

Corpus impact today is nil, which is why this is not blocking. I scanned all
130 specs: 0 phantom-fence candidates, 0 fences longer than 3 characters, 0
documents with an odd fence count. Recommended disposition:
**promote-to-follow-up-ref** — port docs-audit-core's two guards, or better,
export and reuse its masker. Not remediate-in-tree at ceremony 1.

### NON-BLOCKING-3 — backticking a marker satisfies the gate, and the limits list is silent

Verified end to end: a draft spec whose only marker is written as
`` `[NEEDS-CLARIFICATION: is this gated?]` `` **freezes at exit 0**, with the
marker text still present in the frozen file. This is the specimen exemption
behaving as designed (D2), but it is also a cheaper and *less visible* way to
satisfy the gate than deletion — which undercuts the claim made twice (D1 and
`USER_GUIDE.md:1036`) that "resolution is deletion ... every resolution is a
diff hunk a reviewer can read". A two-character edit is a far less legible hunk
than a removed line.

D5 and the guide enumerate seven limits and omit this one. Since Spec-AC-07's
whole purpose is that the limits list be trustworthy, it should be limit eight.
Disposition: **remediate-in-tree** — one sentence in each place.

### NON-BLOCKING-4 — ac-vague-term can report the wrong line

`.aai/scripts/spec-lint.mjs:637`:

```js
const idx = normLines.findIndex((l) => l.trim().startsWith('|') && l.includes(id));
```

This takes the first table line mentioning the AC id, and Test Plan rows carry
AC ids in their second column. Measured on a spec whose `## Test Plan` precedes
`## Acceptance Criteria Status`: reported `ac-vague-term@19` (the Test Plan
row) when the offending AC row is at line 25. Advisory rule, cosmetic impact,
no corpus doc currently uses that section order. Disposition: follow-up ref.

### NON-BLOCKING-5 — a spec edge-case bullet claims something the tree cannot do

`SPEC-0130-spec-vagueness-gate.md:461`: "A code span containing a `|` inside an
AC cell: the mask preserves `|`, so the cell count is unchanged and the row
still parses." Measured: the first half is true (cell counts byte-stable, incl.
the escaped-pipe case), the second is false. The row does not parse in `norm`
*or* `masked`, because a pipe in a table cell breaks the shared parser
regardless — which is the tree's own LEARNED rule ("never pipes, even `\|`, in
AC table cells") and what TEST-003's fixture actually relies on. Correct the
bullet.

### NON-BLOCKING-6 — F7 confirmed, and TEST-012 cannot catch a recurrence

Nine `red-*vagueness-gate*.log` artifacts exist, all `RED_CLASS: product_red`
on line 1, plus three honest `report-*-no-red-available.log` files for
TEST-009/011/012 explaining why no RED was available. TEST-008 has neither.

**Deferring F7 was right.** TEST-008's RED is real, mechanical (the pin was
-5844 until the sentence landed) and was independently reproduced by
validation; the missing file is paperwork, not evidence. P3 is correct.

One thing the follow-up should record: `TEST-012(clarify)` asserts "all 9
stored RED log(s) carry RED_CLASS as line 1" — it iterates the `red-*` files
that *exist*, so a missing artifact is invisible to it. Nothing in the suite
can detect this omission, which means it will not self-heal.

### INFO (does not gate)

`spec-freeze.mjs`'s refusal message ends with a fixed tail: "Fix the spec (add
the missing Test Plan row(s) / record the strategy) and re-run". With a third
precondition now in the array, that tail no longer enumerates the ways to
comply. The per-finding detail does say "answer the question ... DELETE the
marker", so nothing is lost operationally.

## Test quality — could the arms pass against a broken engine?

Mostly no, and I checked by breaking it. Six mutations in an isolated clone:

| # | Mutation | Killed by | Verdict |
|---|---|---|---|
| M1 | drop `\|` preservation in the mask | **nothing** (48+21 green, corpus 0) | survives — NB-1 / F3 |
| M2 | drop `\n` preservation in the mask | nothing | **equivalent mutant**, not a gap |
| M3 | rename rule id in spec-lint only (SEAM-1) | 5 arms incl. TEST-002(clarify) | killed |
| M4 | remove the `IN_FLIGHT_STATUSES` guard | TEST-009(clarify) | killed |
| M5 | feed raw `norm` instead of `masked` | 8 arms incl. 4 pre-existing corpus arms | killed |
| M6 | cap off-by-one (`>` → `>=`) | TEST-004(clarify) | killed |

The negative controls are real, not decorative. TEST-001's case/spacing control
asserts exit 0 *and* the absence of the rule; TEST-006 fails (rather than
silently skipping) if the real SPEC-0112 is missing, and re-derives its control
from the actual file with only `status` flipped, so the `fast` exclusion tracks
the corpus instead of a mock; TEST-004's three-marker arm pins the cap boundary
from below. Expected line numbers are computed by grepping the fixture at run
time rather than hardcoded, so a shifted fixture cannot produce a false green.

Two soft spots. TEST-003's advertised "cell counts must not shift" assertion is
vacuous with respect to the mask (NB-1). And TEST-011 degrades to `log_info`
and still passes when no base ref resolves — the F6 fix made it try
`origin/main` first, which is right, but unlike TEST-006 the degrade does not
set `ok=0`, so a CI environment with neither ref would leave the
zero-added-ceremony pin inert and green (listed under `cannot_verify`).

## Warning dispositions (H6)

| Finding | Recommended disposition |
|---|---|
| NB-1 mask pipe clause unpinned | already filed — `fu-mask-pipe-clause-unpinned` (P3); append the wrong-observable root cause |
| NB-2 masker duplicates docs-audit-core | **promote to a new follow-up ref** (P2) — port the two W3 guards or reuse the shared masker |
| NB-3 backticking satisfies the gate | **remediate in tree** — one sentence in D5 and USER_GUIDE |
| NB-4 ac-vague-term line locator | **promote to follow-up** (P3) |
| NB-5 spec edge-case bullet half false | **remediate in tree** — one line |
| NB-6 TEST-008 artifact | already filed — `fu-test008-missing-red-artifact` (P3); note TEST-012's blind spot |

## Merge gate

**Not merge-ready.** One BLOCKING finding stands: the F1 remediation left the
unreproducible `16 rows / 8 specs / 16-16` measurement in
`.aai/scripts/spec-lint.mjs:380-384` and `CHANGELOG.md:40-42`, and left
`docs/USER_GUIDE.md:1070` contradicting itself. Fixing those three sites clears
BLOCKING-1 and Spec-AC-07 together, at which point both verdicts pass and the
scope is merge-ready with six NON-BLOCKING findings dispositioned as above.

The engineering underneath is sound: the rules are correctly scoped, the seam
to `spec-freeze` is genuinely crossed by a test, the exit and flag contracts are
byte-identical to base, the prompt delta is exactly the 423 B claimed, and the
mutation sweep kills five of six injected defects.
