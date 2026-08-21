# Code Review — intake-numbers-some-doc-types-immediately

```yaml
review:
  scope: "git diff (uncommitted working tree) vs main @ ddc36f6 — .aai/INTAKE_COMMON.md, the eight .aai/INTAKE_*.prompt.md, .aai/scripts/docs-audit.mjs, tests/skills/test-aai-intake.sh, tests/skills/lib/prompt-diet-ledger.sh, tests/skills/test-aai-prompt-diet.sh, tests/skills/test-aai-spec-lint.sh, docs/INDEX.md, docs/ai/EVENTS.jsonl, docs/ai/decisions.jsonl, docs/specs/SPEC-0140-spec-intake-numbers-some-doc-types-immediately.md"
  spec: docs/specs/SPEC-0140-spec-intake-numbers-some-doc-types-immediately.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "TEST-012 + TEST-014 green (suite stdout: eight prompts 'rule present'; eight types numbered->1 / DRAFT->0)" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "TEST-013 green — 8 rows, research=RES, six rows matched to TYPE_MAP, two reported ABSENT; directory sub-clause deviates from the AC wording, see NB-3 + cannot_verify" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "TEST-014 green — numbered->1 numbered-at-intake, DRAFT->0, no-number-key->1 number-absent, unreadable->2, table-removed->2, POST-SAVE CHECK invocation present" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "TEST-015 green; four paths stat-ed present; git status --porcelain=v1 -uno -- docs/ has no R entry (re-run independently)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/lib/prompt-diet-ledger.sh, line: 77,
          issue: "unescaped backtick pair still executes `wc -c .aai/SKILL_ISSUES.prompt.md` at source time; line 153 does the same for SKILL_ROUTINE. The fix this ride shipped covered only the one entry it happened to edit, and both the new ledger entry and the round-2 report assert the class is gone.",
          failure_scenario: "source the library from any cwd other than the repo root (a suite that cds into its scratch dir, an exported copy, CI running from a parent): both wc calls write 'No such file or directory' to stderr and substitute EMPTY, so the entry text silently loses its measurement claim. From the repo root it instead substitutes '    3810 .aai/SKILL_ISSUES.prompt.md' into the prose. JUSTIFIED_GROWTH_BYTES is unaffected either way (the leading field survives), so no arm ever reddens." }
      - { rank: NON-BLOCKING, file: tests/skills/lib/prompt-diet-ledger.sh, line: 168,
          issue: "the new entry asserts 'no backtick in any ledger entry' — false at ship time in the strong sense (two unescaped, executing) and in the weak sense (line 69's escaped pair).",
          failure_scenario: "the ledger is the repository's own record of why every prompt byte exists; a future editor reading this sentence concludes the class is closed and does not escape the next backtick they write." }
      - { rank: NON-BLOCKING, file: docs/ai/validation/validation-20260821T072908Z-intake-numbers-some-doc-types-immediately-round2.md, line: 113,
          issue: "six fu- ids are named in the round-2 report as filings (F5-F10) and none exists in the follow-ups registry; round-1 F1 and F5 carry no id at all. Four unrelated follow-ups from this ride ARE filed, so the omission is selective, not systemic.",
          failure_scenario: "close the ride and every one of those eight findings evaporates — SKILL_CODE_REVIEW H6 and VALIDATION step 8b both treat an unrecorded WARNING as a closeout stop, so this fires at close rather than now." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-intake.sh, line: 47,
          issue: "TEST-013 and TEST-014 both derive their entire universe of table rows from intake_table_lines' single-space awk, while the gate parses with \\s*. Neither arm can ever observe a row the gate has and the test does not.",
          failure_scenario: "append '|spec|spec|docs/specs|SPEC|' to INTAKE_COMMON.md: the gate then exits 0 on docs/specs/SPEC-DRAFT-x.md (reproduced), TEST-013 still counts 8 rows and passes. The suite reddens only incidentally, via TEST-014's table-removal fixture whose grep -v shares the same spacing assumption — and it reddens with a misleading message ('a fixture with no type table exited 1')." }
      - { rank: NON-BLOCKING, file: .aai/INTAKE_COMMON.md, line: 27,
          issue: "the legacy FALLBACK block still instructs scan-and-mint of docs/<type>/<TYPE>-000N-<slug>.md, which is exactly what --intake-file now rejects; the POST-SAVE escape hatch excuses only a MISSING docs-audit.mjs, not a missing allocator. Found as round-1 F5, neither fixed nor filed.",
          failure_scenario: "an older AAI layer that has docs-audit.mjs but no allocator: the role follows the fallback, writes a numbered file, then hits 'fix the FILENAME and re-run until both pass' with no reachable fixed point." }
      - { rank: NON-BLOCKING, file: .aai/scripts/docs-audit.mjs, line: 371,
          issue: "main() dispatches on truthiness, so --intake-file with an absent or empty value falls through to a full repo audit and exits 0 (measured; also appends a docs_audit event when --no-event is absent). Round-1 F1, correctly classified there as a pre-existing sibling shape, but still unfiled.",
          failure_scenario: "any wrapper doing --intake-file \"$FILE\" with FILE unset prints '### Verdict: CLEAN' at exit 0 — indistinguishable from a pass on an artifact never read, which is the one property Spec-AC-03 and Constitution Article 4 both claim." }
      - { rank: NON-BLOCKING, file: .aai/INTAKE_COMMON.md, line: 52,
          issue: "the gate's invocation lives only in INTAKE_COMMON.md POST-SAVE CHECK, reachable from a per-type prompt only through the pre-existing SHARED POLICY line — the identical indirection the spec's own Summary blames for the four numbered documents. The naming rule was inlined into the eight prompts; the enforcement was not.",
          failure_scenario: "the same rare-type path that ignored 'apply durable doc identity exactly' ignores 'apply post-save check exactly' and lands a numbered doc with nothing run. AC-003 only asks that POST-SAVE CHECK invoke the flag, which it does — this is beyond the AC, but it is the ride's own causal model applied to its own fix." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-intake.sh, line: 199,
          issue: "the directory pin is a file-wide set equality over grep -oE 'docs/[a-z]+' and is fence-blind. Round-2 F6 records that it is weaker than Spec-AC-02's 'opening line'; it is also STRICTER than intended in the other direction.",
          failure_scenario: "a future edit adding a legitimate cross-reference ('see docs/specs/ for the spec') or a fenced example path to any INTAKE_*.prompt.md turns TEST-013 red for a non-defect, and the message blames the prompt's directory line." }
  cannot_verify:
    - { claim: "Spec-AC-02's literal clause that each per-type prompt's OPENING directory line names its table row's directory",
        closes_with: "an arm anchored to the first N lines (or the line matching 'save it under docs/...'), not a file-wide set — the current arm stays green if the opening line is deleted and the directory appears in a footnote" }
    - { claim: "that the eight intake types actually produce DRAFT artifacts in a live run",
        closes_with: "nothing available in CI — the spec is explicit about this (D5) and the mechanical two-half demonstration is the accepted substitute; recorded here as a named gap, not a defect" }
    - { claim: "that the four historical numbered documents were not renamed in some earlier commit of this ride",
        closes_with: "the ride is uncommitted, so TEST-015's working-tree check is the whole story today; re-run after the scope is committed, since git status -uno cannot see a rename that is already in a commit" }
    - { claim: "behavior of --intake-file under a slow pipe reader",
        closes_with: "runIntakeFile uses console.log + process.exit, the shape diagnosed one commit earlier in c59e12d and filed as fu-cli-exit-truncates-pipe-sweep; output here is ~4 lines so truncation cannot bite at current sizes, but the new code adds an instance rather than adopting the established exit() pattern" }
  overall: pass
```

## Scope and method

Base ref `main` @ `ddc36f6`; the scope is uncommitted in the working tree, so the review scope is `git diff` over the spec's declared inline-review path list plus the untracked spec draft. Seventeen tracked files modified, one untracked added; `git diff --stat main...HEAD` is empty, confirming nothing is committed on the branch.

Suites were run **serially, one at a time**, never concurrently — the round-2 false red came from thirteen at once, two of which shell out to the repo-wide audit. Start/end of every long step is in the progress log.

| Command | Result |
|---|---|
| `bash tests/skills/test-aai-intake.sh` | rc 0, TEST-012..015 green with the per-type exit codes printed |
| `bash tests/skills/test-aai-prompt-diet.sh` | rc 0, TEST-012 pin `133 == independent re-sum`, TEST-010 headroom 1665/2048 |
| `bash tests/skills/test-aai-spec-lint.sh` | rc 0, TEST-011(clarify) accepts all 29 allowlisted `.aai/` paths across 9 groups |
| `node .aai/scripts/spec-lint.mjs` | rc 0, 0 findings over 140 specs |
| `node .aai/scripts/check-test-registration.mjs` | rc 0, silent |
| `node .aai/scripts/docs-audit.mjs --check --strict --no-event` | rc 0, `### Verdict: CLEAN` |
| `node .aai/scripts/allocate-doc-number.mjs --guard --base-ref origin/main` | rc 0, clean |
| `node .aai/scripts/select-suites.mjs --files-from <changed>` | 3 CORE + 10 SELECTED, 68 dropped, **no FULL_RUN** |
| `git diff --exit-code -- .aai/scripts/lib/docs-audit-core.mjs` | byte-identical to HEAD |
| `git diff --exit-code -- .aai/scripts/allocate-doc-number.mjs` | untouched (`protected_paths_l3` respected) |
| NUL byte scan, all 15 edited/added files | zero |
| `docs-audit --gate spec-intake-...` | FAIL on four `implementing` rows — deliberate, flip must precede `close-work-item.mjs` |

`tests/skills/test-aai-docs-audit.sh` was **not** run (>4 min, core-selected, already exercised by two validation rounds); named here rather than silently skipped.

## AC table walk

**Spec-AC-01 — compliant.** All eight `.aai/INTAKE_*.prompt.md` carry the `-DRAFT-` token, `number: null`, `status: draft` and an in-RULES-block pointer at the table; none retains "suggested filename"; the file count pins at eight. TEST-014 drove all eight table rows through the real predicate: `PRD/CHANGE/ISSUE/ISSUE/DEBT/RES/RFC/REL`-`0999` → exit 1 with `numbered-at-intake`, each DRAFT twin → exit 0. The RULES-block anchoring is load-bearing and correctly reasoned — a file-wide grep for the pointer was already satisfied at HEAD by the SHARED POLICY line, and the arm's comment says so.

**Spec-AC-02 — compliant on the headline, deviating on one sub-clause.** Eight rows, one intake type each, `research` → `RES`; `TYPE_MAP` imported read-only and matched on six rows, with `hotfix` and `research` printed as ABSENT rather than silently skipped. No prompt restates a display prefix. The deviation: the AC (and the AC-Status Evidence cell) say "every per-type prompt's own **opening** directory line", and the arm pins the file-wide **set** of `docs/<dir>` mentions. The Test Plan row for TEST-013 states it correctly; the AC and the Status table overstate. **The spec now overstates** — narrow the AC wording to "every `docs/<dir>` the prompt names" or anchor the arm to the opening line. Recorded as cannot_verify #1.

Refinement on the unanchored pair: `research`'s **prefix** is in fact anchored (the arm hard-codes `research != RES`); only its directory floats. `hotfix` is anchored in **neither** dimension, and its row is additionally a functional no-op in the gate today — `(type=issue, docs/issues, ISSUE)` is byte-identical to the `issue` row, so the gate cannot distinguish a hotfix intake at all. Change the hotfix row's prefix to `HOTFIX` and TEST-013 and TEST-014 both stay green while the gate quietly starts accepting `HOTFIX-DRAFT-*.md` for `type: issue`.

**Spec-AC-03 — compliant.** Every exit code the AC names was observed: 1 with `numbered-at-intake`, 0 on the twin, 1 with `number-absent` (D8), 2 on an unreadable artifact, 2 on a table-less fixture, and the POST-SAVE CHECK invocation asserted section-anchored (round-1 M6 proved the weaker form did not bite). D8 is right and the reasoning is right — it only ever failed open in the unnumbered direction. Two holes sit next to this AC's own "never passes something it never read" claim: the empty/absent flag value (NB-6) and the fact that nothing automated runs the flag (NB-7).

**Spec-AC-04 — compliant.** Four paths present; `git status --porcelain=v1 -uno -- docs/` re-run independently, no `R` entry. The arm reports rather than silently skips when there is no git tree. Boundary held: `docs-audit-core.mjs` byte-identical, `allocate-doc-number.mjs` untouched.

## The three things asked, judged

**1. Parser-strictness asymmetry — real, correctly diagnosed, and understated by one level.** Reproduced: a `|spec|spec|docs/specs|SPEC|` row makes the gate exit 0 on `SPEC-DRAFT-x.md` while `intake_table_lines` still reports eight and TEST-013 stays green. On the live file both readings agree (8 = 8), so the pin is *currently* sound.

What the filing calls a smuggled ninth row is a symptom of something structural: **TEST-013 and TEST-014 both take their universe of rows from the awk**, so no arm can ever see a row the gate has and the test does not. The arms are not merely evadable in this one case — they are incapable, by construction, of detecting gate over-permissiveness in the table dimension. The independence that was chosen deliberately (and for a good reason — a tool that reads its own table proves nothing) is only half-built: independence needs a **cross-check**, not just a second reader. The cheap fix is one assertion in TEST-013 — parse the table with the tool's own reading and assert the two counts agree — which turns today's accidental red into a named one. Note the incidental red round 2 relied on is itself spacing-coupled: TEST-014's table-removal `grep -v` uses the same single-space pattern.

Verdict on the framing: **it does not undermine the pin's current correctness; it undermines the pin's ability to notice.** Wider than "narrow as filed", still not a blocker.

**2. Is the pin honest? Mostly, and the spec overstates in exactly one place.** Set equality per prompt is stronger than asked on the "no other directory" half and weaker than asked on the "opening line" half — the AC text and the AC-Status Evidence cell both say "opening line" and neither is what runs. Say the spec overstates. Separately, the strictness cuts the other way too: the set pin is fence-blind, so the first legitimate cross-reference or fenced example path added to any intake prompt reddens TEST-013 for a non-defect (NB-8). Round 2 caught the weak direction; the brittle direction is unrecorded.

**3. Enforcement — R1 is honest, and there is a sharper version of it.** The ride's claim ("adds exactly that, at the one moment where created-at-intake is observable") is accurately hedged, and the AC-03 Status note names the prompt-level limit. But apply the ride's own causal model to its own fix: the four numbered documents happened because a per-type prompt referenced `INTAKE_COMMON.md`'s rules through one SHARED POLICY line and the per-type instruction won. This ride **inlined the naming rule** into all eight prompts — the correct fix — and **left the gate's invocation** in `INTAKE_COMMON.md`, reachable only through that same SHARED POLICY line. The half that was proven not to carry is the half the enforcement still rides on. Beyond AC-003 (which asks only that POST-SAVE CHECK invoke the flag, and it does), so a filing — but it is the most consequential thing beyond the ACs, and the remedy is one clause in the RULES bullet the eight prompts just gained.

## The ledger fix — checked, and the same shape survives twice

The `extra`-with-backticks fix is correct: sourcing from the repo root now emits nothing on stderr and the word is intact.

**The class is not closed.** `tests/skills/lib/prompt-diet-ledger.sh` lines 77 and 153 carry unescaped backtick pairs inside double-quoted array elements:

- line 77 — ``(3810 B, measured via `wc -c .aai/SKILL_ISSUES.prompt.md`)``
- line 153 — ``credited at the MEASURED file size (`wc -c .aai/SKILL_ROUTINE.prompt.md` = 2769 B, ...)``

Both **execute on every source**, in a file whose own header declares it "a PURE library: no `set -u`, no `cd`, no test execution", sourced by `test-aai-prompt-diet.sh`, `test-aai-verify-gate.sh`, `test-aai-deslop.sh`, `test-aai-update.sh` and `test-aai-win-fallback`.

Measured both ways:

```
# sourced from the repo root — wc succeeds, output substituted into the prose:
  "... (3810 B, measured via     3810 .aai/SKILL_ISSUES.prompt.md), measured deficit 2734 B ..."

# sourced from any other cwd — stderr, and the claim silently vanishes:
  wc: .aai/SKILL_ISSUES.prompt.md: open: No such file or directory
  wc: .aai/SKILL_ROUTINE.prompt.md: open: No such file or directory
  "... (3810 B, measured via ), measured deficit 2734 B ..."
```

`JUSTIFIED_GROWTH_BYTES` is 133 either way — the leading field is untouched — so TEST-012 and TEST-013 stay green in both cases. Exactly the silent shape the original bug had.

This is the one place where the dispatch, the ledger entry and the round-2 report all state something false. The round-2 report says "The only backticks anywhere in an entry are the escaped pair on line 69 (pre-existing, harmless)"; the new ledger entry says "no backtick in any ledger entry"; F10 correctly identifies that the real invariant is *no unescaped backtick* — and then does not check whether the ledger satisfies it. It does not, twice.

Recommended disposition: **remediate in tree.** Escaping two backtick pairs and correcting one clause is a handful of characters, cheaper than filing, and it makes the assertion the ride is shipping true. The existing open `fu-ledger-backticks-ran-as-command` should have its description widened either way — it currently describes only the `extra` instance.

## Unrecorded findings (closeout precondition)

Six `fu-` ids are named in the round-2 report and **none exists in the registry**; round-1 F1 and F5 have no id at all. Four unrelated follow-ups from this ride are filed, so this is an omission, not a missing mechanism.

| id / finding | in registry |
|---|---|
| `fu-typemap-missing-research-hotfix` | filed |
| `fu-ceremony-test016-blanket-byte-pin` | filed |
| `fu-intake-templates-lack-number-key` | filed |
| `fu-ledger-backticks-ran-as-command` | filed |
| `fu-intake-dir-unanchored-for-research-and-hotfix` (F5) | **missing** |
| `fu-intake-dir-pin-is-set-not-opening-line` (F6) | **missing** |
| `fu-prefix-restatement-check-needs-the-hyphen` (F7) | **missing** |
| `fu-intake-table-parser-strictness-asymmetry` (F8) | **missing** |
| `fu-test012-sigpipe-rationale-overstated` (F9) | **missing** |
| `fu-ledger-no-backtick-claim-is-absolute` (F10) | **missing** |
| round-1 F1 (`--intake-file ""` fails open, P2) | **missing, unnamed** |
| round-1 F5 (FALLBACK contradicts POST-SAVE CHECK, P3) | **missing, unnamed** |

Under SKILL_CODE_REVIEW H6 and VALIDATION step 8b these stop closeout, not merge.

## Warning dispositions

| # | Finding | Disposition |
|---|---|---|
| NB-1 | ledger lines 77/153 execute `wc -c` on source | **remediate-in-tree** (escape both), and widen `fu-ledger-backticks-ran-as-command` |
| NB-2 | "no backtick in any ledger entry" is false | **remediate-in-tree** (one clause) |
| NB-3 | six named `fu-` ids + two round-1 findings unfiled | **promote-to-follow-up-ref** — file all eight via `follow-ups.mjs add` before close |
| NB-4 | test/gate parser asymmetry | **promote** as filed (F8), with the widened framing: add a two-readings-agree assertion to TEST-013 |
| NB-5 | FALLBACK block contradicts POST-SAVE CHECK | **promote** (round-1 F5, currently unfiled) |
| NB-6 | `--intake-file ""` / no value exits 0 | **promote** (round-1 F1); fix once for `--gate-file`, `--lint-body-file`, `--path` too |
| NB-7 | enforcement inlined nowhere the failing path reads | **promote** — new ref; or inline the invocation into the eight RULES bullets |
| NB-8 | directory pin is set-based and fence-blind (brittle direction) | **promote** — fold into F6's ref |

INFO, never gating: the shipped table has no markdown header or delimiter row, so it renders as literal text rather than a table (the parser's "header row cannot match by construction" comment is defensively correct — a real header would not match — but no header exists to be excluded); `runIntakeFile` adds a new `console.log` + `process.exit` site one commit after that shape was diagnosed and swept into `fu-cli-exit-truncates-pipe-sweep`, harmless at ~4 lines of output.

## Coaching-attempt record (ANTI-GAMING CONTRACT)

The dispatch named three areas to judge and stated the residual risk position for each, which the contract asks reviewers to record rather than object to. It also declared it had not ranked anything and invited findings outside the named areas. The full scope was reviewed regardless; the highest-value finding (ledger lines 77/153) is outside all three named areas and contradicts a claim the dispatch relayed as settled.

## Next steps

1. Escape the two backtick pairs; correct the "no backtick in any ledger entry" clause. Re-run `bash tests/skills/test-aai-prompt-diet.sh`.
2. File the eight unrecorded findings via `node .aai/scripts/follow-ups.mjs add`.
3. Decide NB-7 — inline the `--intake-file` invocation into the eight RULES bullets, or state in the spec that enforcement deliberately stays in `INTAKE_COMMON.md`.
4. Narrow Spec-AC-02's "opening line" wording (or the AC-Status Evidence cell) to match what TEST-013 pins.
5. Flip the four AC Status rows to `done` **before** `close-work-item.mjs` (`fu-ac-flip-must-precede-close`).

Merge readiness: **pass, conditional on the H6 dispositions above.** No BLOCKING finding. Nothing in the four ACs is unmet, the declared boundaries (`docs-audit-core.mjs` byte-identical, `allocate-doc-number.mjs` untouched, no rename under `docs/`) all hold, and `select-suites` confirms no FULL_RUN escalation.
