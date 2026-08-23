# Code Review — the-subagent-contract-omits-the-hazards (adversarial, ceremony 2)

```yaml
review:
  scope: f46502e...f4b6f3f (branch feat/contract-carries-the-hazards)
  spec: docs/specs/SPEC-0147-spec-the-subagent-contract-omits-the-hazards.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/SUBAGENT_CONTRACT.md:9-37 (section at line 9, before ## Result block at 39); test_080 + test_083 green" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "5/5 citations resolve; HAZ-LEDGER's citation deviates from the frozen enumeration — see Deviation D-1, the swap moves AC-02 from arguably-non-compliant to compliant" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "test_083 bite proved on 10 mutations (spec asked for 5), control green, cardinality guard fires UNCOVERED; hygiene-pack rc=0 under bash 3.2.57" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "CONTRACT outside TEST-010 glob + extra list; PROFILES core; test_093 green" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "test_081/test_082 green; no cross-file rule duplication found by own sweep" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: docs/knowledge/LEARNED.md, line: 55,
          issue: "A dated, Source-attributed historical record is rewritten to assert a method that was not used: 'reproduced via git-stash comparison' became 'reproduced in a disposable worktree cut from HEAD ... NOT by stashing the shared tree'.",
          failure_scenario: "A role replaying LEARNED.md (payload component 3) cites the 2026-07-17 entry as evidence that worktree-based reproduction was already practice, or as precedent for the technique's provenance. The clause actively denies what happened. The same diff demonstrates the honest pattern twice — line 41 'the technique named here was not' and the dated CORRECTION block at 160 — so the standard is the diff's own." }
      - { rank: NON-BLOCKING, file: docs/knowledge/LEARNED.md, line: 37,
          issue: "Baseline silently moved from main to HEAD: 'stash/main comparison' became 'a DISPOSABLE WORKTREE cut from HEAD'. git worktree add --detach defaults to HEAD.",
          failure_scenario: "A validator on a feature branch with committed work cuts a worktree from HEAD, sees prompt-diet TEST-010 fail there too, concludes 'pre-existing on clean main, out of scope' — when its own committed edits caused it. Line 54-55 makes the drift explicit by asserting 'FAILS on clean main' in the same sentence that names HEAD as the tree." }
      - { rank: NON-BLOCKING, file: docs/knowledge/LEARNED.md, line: 145,
          issue: "'prefer worktree isolation' hardened into 'HAZ-RESTORE ... prohibits it outright; use a disposable worktree for any git-mutating role'. HAZ-RESTORE prohibits restoring git commands on tracked files; it says nothing about working inline.",
          failure_scenario: "A dispatched Implementation role reads the absolute prohibition in payload component 3 while its own spec says 'Worktree recommendation: not_needed / User decision: inline' (this very spec, line 143-144) and SKILL_CODE_REVIEW.prompt.md supports inline as a first-class mode. Two payload components conflict and the role must pick — the exact contradiction class this scope exists to remove." }
      - { rank: NON-BLOCKING, file: .aai/SUBAGENT_PROTOCOL.md, line: 6,
          issue: "Describes the CONTRACT as 'the ~60-line duty sheet'; it now ships at 84 lines. This is the fourth place stating the cap, against the spec's 'the three places that assert it'.",
          failure_scenario: "An orchestrator reading the sibling canon page budgets the payload at ~60 lines and treats a 84-line CONTRACT as already over. It is prose, not a comparison, so no suite catches it; the spec scoped SUBAGENT_PROTOCOL.md out before anyone noticed line 6 carried the number." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-hygiene-pack.sh, line: 869,
          issue: "test_083 pins the section's content but never asserts it precedes '## Result block'; hazards_section() matches the heading anywhere in the file.",
          failure_scenario: "A tidy-up moves Standing hazards below the result block. test_083, test_080 and TEST-020 all stay green while the spec's stated core ('a hazard read after the output format has already been read is a hazard read too late') is defeated." }
      - { rank: NON-BLOCKING, file: .aai/SUBAGENT_CONTRACT.md, line: 7,
          issue: "The cap counts LINES while the cost it proxies is bytes/tokens; on breaching 84 the section was brought under by unwrapping prose, not by saying less (lines 7 and 11 are 117 and 125 chars against ~78 for every other prose line in the section).",
          failure_scenario: "TEST-020's reported '>=6 lines below the 90 cap' is nominal — the same lines can be reclaimed again by rewrapping, so the guard is satisfiable indefinitely without reducing payload cost. Nothing was lost this time (see Question 2)." }
  cannot_verify:
    - { claim: "Behaviour of test_083's cardinality guard on native bash >= 4.4 (CI is ubuntu-latest).",
        closes_with: "One CI run, or a container with bash 5. This machine is bash 3.2.57; I ran the suites under /bin/bash explicitly and they pass, which is the platform the guard fails-closed on by accident rather than by design." }
    - { claim: "Whether Codex/Gemini dispatch assembly pastes the CONTRACT where Claude Code does not.",
        closes_with: "A dispatch transcript from each harness. First-hand observation covers this harness only." }
    - { claim: "Whether the six new filings are the complete set of meaning changes in the LEARNED.md rewrite.",
        closes_with: "A line-by-line diff review by a second reader; I judged the four entries the dispatch named plus the CORRECTION block." }
  overall: fail
```

Scope established per preflight: `worktree.user_decision: inline`, inline review
scope named in the spec; reviewed `git diff f46502e f4b6f3f`. Read-only on
implementation files throughout; nothing in the shipping tree was mutated, no
restoring git command was run, and the contract's Standing hazards were obtained
by reading `.aai/SUBAGENT_CONTRACT.md` directly — **the dispatch's claim that
they arrived in the payload is false again this round**, a third consecutive
first-hand reproduction of `fu-contract-prefix-order-unenforced`.

---

## Question 1 — is this change worth shipping?

**Yes, and the shipped narrative is honest enough — with one correction owed.**

The honest description of what this ride buys is: *the rules become canonical,
greppable, scarred, and pinned against silent deletion.* `test_083` is a real
backstop for one real failure mode — a future tidy-up that drops a hazard now
turns the suite red. That is durable and it is not nothing.

What it does **not** buy is a lower failure rate for the incidents it cites, and
the diff does not claim otherwise: the spec's Problem section says the rule "has
been remembered every time and still failed twice", `fu-subagent-probe-hits-real-repo`
(P1) is deliberately left open, and the disclosure is in the ledger. Measured
against `fu-contract-prefix-order-unenforced`, the narrative holds because
nowhere in the shipped diff does the CONTRACT, the spec, or the test claim the
section is *delivered*. The false claim lives in the orchestrator's dispatch
prose, which is not in this diff. That is the right place for the P2 and it is
correctly filed there.

The one place the narrative slips is the LEARNED.md rewrite (blocker below):
a commit whose subject is honesty about hazards should not falsify a dated
record to make it comply.

## Question 2 — the 84-line ceiling: was anything load-bearing lost?

**No. The compression was pure reflow, and it is fully accounted for.**

The dispatch points at `cade339` vs `2350324` for the pre-compression text. That
is not where it is: the only CONTRACT change between those two commits is the
HAZ-LEDGER rewrite (5 lines → 6, net +1, 83 → 84), which is a *semantic
improvement* remediating round 1's `fu-haz-ledger-cites-weaker-scar` and
`fu-haz-ledger-cli-only-overstated`, not compression. The 87 → 84 pass happened
pre-commit and is not in git history at all.

It is still recoverable by measurement. Three lines had to go; exactly three
lines in the section are unwrapped against a ~78-char norm:

| Line | Chars | Content |
|---|---|---|
| 7 | 117 | "The Standing hazards below bind the dispatched unit's own hands…" |
| 11 | 125 | "These bind YOU on every dispatch whether or not the dispatch text repeats them…" |
| (cade339 HAZ-LEDGER tail) | 86 | "deliberately NOT wired to it — that rollback arm truncates…" |

Three over-long lines, three lines saved. Both surviving sentences are complete
and carry their full meaning — the "binds you whether or not the dispatch
repeats them" clause and the "may ADD, never waive" clause are both intact, and
those are the two load-bearing sentences in the preamble. **Nothing was cut.**

The finding is structural rather than about this instance: the guard counts the
wrong unit (filed P3). Bytes went 2752 → 4795; `maxlen` was 191 before and after,
so the file already had long lines and the norm is not enforced anywhere.

## Question 3 — the three cap assertions, and the fourth

All three verified live under `/bin/bash` (3.2.57), not read:

| Assertion | Shipped | Observed |
|---|---|---|
| hygiene `test_080` | `<= 90` | "SUBAGENT_CONTRACT.md present, 84 lines, required tokens present" |
| role-output `TEST-010` | `<= 90` | "CONTRACT 84 lines + EXPECT pointer" |
| role-output `TEST-020` | `<= 84` | "84 lines (<=84, >=6 below the 90 cap)" |

The `>= 6` relation holds exactly (90 − 84 = 6). All three suites rc=0.

**The sweep found a fourth, and it is inside the `.aai/` surface the dispatch
named**: `.aai/SUBAGENT_PROTOCOL.md:6` — "`.aai/SUBAGENT_CONTRACT.md` is the
per-dispatch payload — the **~60-line** duty sheet". Both validation rounds
swept for `-le 60` / `-le 54` *comparisons* and correctly found none; neither
swept for the cap stated as prose. It is untouched by the branch and now false
by 40%. The spec's D1 says the re-base lands "in the three places that assert
it" — that count is wrong, and `.aai/SUBAGENT_PROTOCOL.md` was scoped out
("Out of scope: … any edit to `.aai/SUBAGENT_PROTOCOL.md`") before anyone
noticed line 6 carried the number. Filed P3, non-blocking: no suite enforces it,
no runtime effect.

Frozen-spec restatements in `docs/specs/SPEC-0087` (≤60) and `SPEC-0094` (≤60,
TEST-010 row) are **not** findings — this repo treats frozen specs as historical
records and already tolerates drift there (SPEC-0087:188 records "58 lines" for
a file that shipped at 53).

## Question 4 — the LEARNED.md rewrite

This is where the diff is weakest, and neither validation round examined it:
both checked that the word `stash` was gone, not whether the replacement said
the same thing.

**Entry 1 (line 34-42) — intent preserved, baseline drifted.** The disclaimer
"The diagnostic need is real; the technique named here was not" is exactly the
right move and should be the template for the others. But `git worktree add
--detach` defaults to HEAD, and the advice it replaced named **main**.

**Entry 2 (line 53-60) — BLOCKING.** Two separate problems in one sentence.
The original recorded what was done in July 2026: "reproduced via git-stash
comparison before touching anything". The rewrite says "reproduced in a
disposable worktree cut from HEAD before touching anything, **NOT by stashing
the shared tree**". That is a past-tense, `Source:`-attributed factual claim
rewritten to assert a method that was not used, and the added clause actively
denies the one that was. Entry 1 and the CORRECTION block both show the author
knew how to do this honestly. Separately, the same sentence claims "FAILS on
clean main" while naming HEAD as the reproduction tree.

**Entry 3 (line 141-146) — over-generalised, and inconsistent with practice.**
"Not 'prefer' — HAZ-RESTORE … prohibits it outright; use a disposable worktree
for any git-mutating role." HAZ-RESTORE prohibits *restoring git commands on
tracked files*. It does not prohibit working inline, and the rewrite attributes
a rule to it that it does not state. The dispatch asked whether the prohibition
is consistent with what the repo actually does: **it is not.** This scope's own
spec records `Worktree recommendation: not_needed` and `User decision: inline`;
`SKILL_CODE_REVIEW.prompt.md`'s preflight treats `worktree.user_decision ==
inline` as a supported mode; the orchestrator shipping this change worked inline
on the tree. A commit that exists to remove a payload contradiction introduced a
new one.

**Entry 4 (the CORRECTION block, line 159-177) — the strongest part of the
diff.** Dated, states what the old advice was, states why it is wrong, cites the
downstream consequence (close events dropped → false-done → TEST-013), names the
registry id, and gives the correct remedy (re-append, never rewrite). Correct
and well-built. One mild cost, not filed: it restates the prohibited command
verbatim, so the payload still contains the exact string
`git checkout -- docs/ai/EVENTS.jsonl …` and every future grep sweep will keep
hitting it. Justified here — a correction has to name what it corrects.

## Question 5 — shell correctness in the arm

Clean. Verified mechanically, not by eye, all under `/bin/bash` 3.2.57.

- **`printf | grep -q` above 64 KiB under pipefail** — no new occurrence. The
  live ratchet (`test_102`, `tests/skills/lib/pipe-grep-q-ratchet.sh`) scans
  `tests/skills/*.sh` including the changed files and is green in the rc=0 run.
  A scan of the added `+` lines for `grep -q` on a pipe returns nothing.
- **`local -a x=()` with `${#x[@]}` under `set -u` on bash 3.2.57** — not
  present. `HAZ_IDS`/`HAZ_SCARS` are file-scope arrays with 5 literal elements
  each; `${#HAZ_IDS[@]}` on a populated array is safe on 3.2. The whole suite
  runs green on this bash.
- **`log_fail` in a subshell** — correctly avoided, and deliberately. The one
  command substitution is `found="$(hazards_findings "$mutated")"`, and
  `hazards_findings` is documented as a pure reporter that "must not call
  log_fail, because the bite half of the arm runs it against a deliberately
  broken copy and log_fail exits the whole suite". Every `log_fail` in
  `test_083` is at function scope.
- **Bare `rc=$?` after a pipe** — not present in the added lines.

One INFO, not filed: `grep -vF -- "$tok" "$pristine" > "$mutated" || true`
(line 142 of the hunk) also swallows grep's exit 2 (real error, e.g. unreadable
input). Traced the consequence: `$mutated` would be empty, `cmp -s` would differ
so the UNCOVERED branch would not fire, `hazards_findings` would report
`MISSING-SECTION`, and the `case` would not match `MISSING-$tok` → `log_fail`.
It fails closed with a misleading message rather than passing. Acceptable.

## Question 6 — the spec-lint allowlist recount

**Correct.** Recounted from the case block independently:

| Group | Paths |
|---|---|
| spec-lint / spec-freeze / PLANNING | 3 |
| allocate-doc-number / SKILL_PR | 2 |
| deslop-unrequested / SKILL_DESLOP / AGENTS / PROFILES.yaml | 4 |
| close-work-item / append-event / orchestration-dispatch / SKILL_TDD / SKILL_TEST_SKILLS | 5 |
| docs-model | 1 |
| generate-factory-report | 1 |
| follow-ups | 1 |
| repo-tripwire / aai-run-tests | 2 |
| INTAKE_COMMON + 8 INTAKE prompts + docs-audit | 10 |
| docs-audit-core | 1 |
| SUBAGENT_CONTRACT | 1 |
| **11 groups** | **31 paths** |

Matches the shipped pass line exactly ("recounted 2026-08-23: 31 paths across 11
case groups"), and the arm is green. The stale-by-one-group claim in the comment
is also true: the previous line said 29/9, and this edit adds 1 group + 1 path,
so the pre-edit truth was 30 paths / 10 groups.

## Deviations from the frozen spec (all recorded, none blocking)

- **D-1 — Spec-AC-02's citation enumeration.** The frozen AC lists
  `.aai/scripts/follow-ups.mjs` as HAZ-LEDGER's citation; the shipped file cites
  `fu-append-only-merge-needs-prefix-order`. This is a **strengthening**: AC-02's
  normative clause requires "the measured incident behind it", and a script
  header describing a rollback that *would* truncate is a design note, not an
  incident. The original enumeration arguably failed AC-02's own clause; the
  swap makes it pass. Traceable via `fu-haz-ledger-cites-weaker-scar` and
  `fu-haz-ledger-cli-only-overstated`, both closed `done` in the ledger.
- **D-2 — files outside the declared scope.** The spec's `Components/files
  affected` and `Inline review scope` omit `docs/knowledge/LEARNED.md` and
  `tests/skills/test-aai-spec-lint.sh`, and its Notes say the LEARNED.md fix is
  "filed, not fixed". Both shipped. The spec-lint edit is mechanically forced
  (TEST-011 fails otherwise). The LEARNED.md fix is recorded via
  `fu-learned-stash-advice-vs-haz-restore` and
  `fu-learned-events-restore-vs-hazards`, both `done`. The spec text is stale,
  the ledger is correct, and the ledger is the authority.
- **D-3 — cosmetic staleness.** Spec says "53 -> 83 lines"; shipped 84. Spec
  says `test_083` "runs five mutations"; it runs ten (5 ids + 5 scars) —
  stronger than specified.

Per the dispatch, the spec's AC Evidence table was **not** touched
(`fu-ac-table-flip-trips-false-open`).

## The P1 backstop, and the AAI_ROLE contradiction

**Leaving `fu-subagent-probe-hits-real-repo` (P1) open is the right call**, and
for a harder reason than either round gave.

Round 1 proposed extending R-GUARD S1's shape (`state.mjs` exit 3 under
`AAI_ROLE=subagent`) to git operations. Round 2 correctly narrowed that: git has
no hook for `checkout`/`restore`/`stash`/`reset`/`prune`, so the chokepoint only
exists for `git commit` (pre-commit), and HAZ-SCRATCH needs OS-level sandboxing.
I re-derived both and agree — `grep -rn AAI_ROLE` outside `state.mjs` returns
only prompt text and the r-guard suite's own fixtures, and no custom `hooksPath`
is configured.

**But there is a prior problem neither round reached: R-GUARD is not armed on
any dispatch today.** The dispatch's measured fact is decisive — the orchestrator
has never set `AAI_ROLE=subagent` this session, so the marker is absent on every
dispatch, not just verdict-bearing ones. The "CLI chokepoint, not merely in
prose" that `.aai/SUBAGENT_PROTOCOL.md:35` and the CONTRACT's single-writer rule
both advertise has **zero live coverage**. Proposing to extend that shape is
proposing to extend a mechanism with no current effect.

**Which of the two instructions is wrong?** `SUBAGENT_PROTOCOL.md:35`. Its MUST
is stated unconditionally over all dispatches, but the canon already carves out
the opposite case: `SKILL_CODE_REVIEW.prompt.md:16-19` grants the STATE write
"when the dispatch grants it (single-agent mode or an explicit instruction)",
and every Validation dispatch is explicitly authorised to call `set-validation`.
Obeying line 35 literally would make those calls exit 3 with STATE unwritten —
so the orchestrator resolves the conflict the only way it can, by never setting
the marker at all, which disarms the guard universally.

The clean fix is the one `state.mjs` already models: it exempts `log-tick` and
`append-event.mjs` as *sanctioned subagent write paths*. `set-validation` and
`set-code-review` are the same category — a dispatched role recording its own
verdict — and were simply never added. Exempt those two from `STATE_MUTATORS`
and line 35's MUST becomes obeyable, at which point the marker can actually be
exported on every dispatch and the guard starts covering the rationalization row
it was built for. **Not filed** — outside this diff, and it belongs to SPEC-0113.

**The smallest real mechanical backstop for the P1** follows from that: do not
build it on an env var the orchestrator must remember to export. Build it at the
chokepoint that already exists and is already mandatory — the orchestrator's
merge step. Snapshot `git rev-parse HEAD` plus `git status --porcelain` of the
shipping repo immediately before dispatch, re-read both at result-merge, and
refuse the merge when a dispatch that declared no shipping-tree writes moved
either. That is detection rather than prevention, it needs no git hook, no PATH
shim and no OS sandbox, it catches all five hazards' *observable* effect
(including the two commits on `main` the P1 actually records), and the repo has
already built this shape twice — `suites-must-not-touch-the-shipping-repo` and
`a-run-must-say-whether-isolation-armed`. Extending that tripwire from suites to
dispatches is the smallest honest increment.

## Verdict

**fail** — one BLOCKING finding (`docs/knowledge/LEARNED.md:55`), one clause,
one-line fix. Everything else is non-blocking and filed.

To clear: restore the historical method in entry 2 and apply entry 1's
disclaimer pattern, e.g. "reproduced via git-stash comparison before touching
anything — the diagnostic need is real; do not use that technique now,
HAZ-RESTORE prohibits it, cut a disposable worktree from **main** instead". That
single edit closes `fu-learned-rewrites-past-method` and
`fu-learned-baseline-head-not-main` together. Re-review is a re-read of that
hunk; no suite re-run is needed beyond `test-aai-learned-append.sh`.

## Warning dispositions (H6)

All six NON-BLOCKING findings are promoted to typed follow-ups, read back via
`node .aai/scripts/follow-ups.mjs list --ref the-subagent-contract-omits-the-hazards --status open`:

| Finding | Registry id | Severity |
|---|---|---|
| LEARNED.md rewrites a dated method (BLOCKING) | `fu-learned-rewrites-past-method` | P2 |
| Baseline moved from main to HEAD | `fu-learned-baseline-head-not-main` | P2 |
| Worktree rule over-broad vs HAZ-RESTORE | `fu-learned-worktree-rule-overbroad` | P2 |
| PROTOCOL states a stale ~60-line cap | `fu-protocol-states-stale-60-line-cap` | P3 |
| test_083 omits the placement pin | `fu-haz-arm-omits-placement-pin` | P3 |
| Cap counts lines, not bytes | `fu-contract-cap-counts-lines-not-bytes` | P3 |

## Evidence

| Command | rc | Result |
|---|---|---|
| `/bin/bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-hygiene-pack.sh` | 0 | test_080 "84 lines"; test_083 "all 5 anchors + 5 incident citations; bite proved on 10 mutations, tracked file byte-unchanged"; ratchet test_102 green |
| `/bin/bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-role-output.sh` | 0 | TEST-010 "CONTRACT 84 lines"; TEST-020 "84 lines (<=84, >=6 below the 90 cap)" |
| `/bin/bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-spec-lint.sh` | 0 | TEST-011(clarify) "31 paths across 11 case groups" |
| `awk length` over CONTRACT at f46502e / cade339 / 2350324 | 0 | lines 53/83/84, bytes 2752/4739/4795, maxlen 191 throughout; 11 lines >80 chars at head |
| `git diff cade339 2350324 -- .aai/SUBAGENT_CONTRACT.md` | 0 | HAZ-LEDGER only, 5→6 lines; no other CONTRACT change |
| `/usr/bin/grep -n '~60-line' .aai/SUBAGENT_PROTOCOL.md` | 0 | line 6, untouched by the branch |
| added-lines scan for `printf\|grep`, `local -a`, `rc=$?`, `grep -q` on a pipe | 0 | only `grep -vF … \|\| true`; none of the four traps |
| allowlist recount from the `test_clarify_011` case block | 0 | 11 groups / 31 paths |
| `node .aai/scripts/follow-ups.mjs add` x6 then `list --status open` | 0 | all six read back |
| `bash --version` (`/bin/bash`) | 0 | 3.2.57(1)-release |

## Attacks that failed to break it

- No fourth *executable* cap assertion on the CONTRACT anywhere in `tests/` or
  `.aai/`; the three shipped ones are mutually consistent and the `>=6` relation
  is exact.
- The compression lost nothing: three saved lines map exactly to three unwrapped
  lines, and both surviving preamble sentences are semantically complete.
- No new `printf | grep -q` occurrence; the live ratchet proves it rather than a
  grep of mine.
- `log_fail` is correctly kept out of the one command substitution, by design and
  with a comment explaining why.
- The arm really does mutate only copies and proves the tracked file
  byte-unchanged; it is bound by the hazard it pins.
- The allowlist recount is right, and its "already one group stale" claim is
  right too.
- Spec-AC-02's citation swap is a strengthening, not a regression.
