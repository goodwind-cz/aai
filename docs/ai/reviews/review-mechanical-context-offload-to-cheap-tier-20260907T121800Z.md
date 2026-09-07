# Code Review — mechanical-context-offload-to-cheap-tier

```yaml
review:
  scope: "8d967f47 + uncommitted working tree — docs/analysis/mechanical-context-offload/ledger-token-attribution.mjs, docs/specs/RES-0002-mechanical-context-offload-to-cheap-tier.md, docs/specs/SPEC-0173-spec-mechanical-context-offload-to-cheap-tier.md, docs/INDEX.md, docs/ai/EVENTS.jsonl"
  spec: docs/specs/SPEC-0173-spec-mechanical-context-offload-to-cheap-tier.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "grep -c 'Not yet produced' returns 0 (rc=1); docs-audit --check --strict --no-event on the RES exits 0; full-repo docs-audit --check --strict verdict CLEAN" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "script vs 8d967f47 snapshot exits 0, prints agent_runs=611 with_usage_marker=384 without_usage_marker=227 tokens_total=59685340; role_row_sum and model_row_sum both equal tokens_total; every baseline cell located verbatim in stdout; independently re-derived by a second implementation (reviewer's verify.mjs)" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "RES:412 'Estimated mechanical share: 0% to 21% of 611 runs' — exactly one match, low<=high; RES:434 'Instrumentation: .aai/scripts/state.mjs - size M', test -f rc=0" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "RES:~504 'Pre-tool block verdict: available-with-cost' — exactly one match; ls .claude/settings.json rc=1 and that absence is quoted; tokens 'no mid-session flip' (2), 'prompt cache' (2), 'source-verified' (1) present; provenance independently confirmed — the three cited shunt paths return HTTP 200 and their contents match the described contract" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "grep -cE for TIERS rows returns 10; do-not-delegate table has 10 rows; set difference between TIERS keys and table column 1 is empty in both directions" }
      - { ac: Spec-AC-06, call: compliant,
          citation: "5 rows, types in {RFC,CHANGE}, sizes in {S,M,L}, ordering keys 9,7,5,4,3 non-increasing; zero rows labelled 'filed:' (the single 'filed:' occurrence at RES:615 is prose about the honesty rule); all 5 ids absent from follow-ups.mjs list --json (141 open items)" }
      - { ac: Spec-AC-07, call: compliant,
          citation: "RES:527 'Harness-scoping hypothesis: undecided' — exactly one match; three '#### Falsifier' headings; 'nested per-harness section' and 'capability probe' both present; the nested-collision claim empirically re-verified against loadModelRouting()'s live regex" }
      - { ac: Spec-AC-08, call: compliant,
          citation: "changed-path union of git diff --name-only 8d967f47...HEAD and git status --porcelain is 5 docs/ paths; grep -vcE '^docs/' returns 0; no MODEL_ROUTING.yaml, orchestration-dispatch.mjs, PRICING.yaml or .claude/ path present" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: docs/specs/RES-0002-mechanical-context-offload-to-cheap-tier.md, line: 621,
          issue: "Recommendation 1 justifies the top-priority follow-up with 'the 131-of-611-run (21%) population', while the Findings section (line 403) derives the same population as '48 + 84 = 132 of the 611'. The document contradicts itself on the single number its highest-ranked recommendation rests on.",
          failure_scenario: "A reader (or the CHANGE this row becomes) sizes the delegable population from Recommendation 1 and carries 131 forward. Re-running the shipped script against the pinned snapshot yields Implementation 48 + TDD Implementation 84 = 132. The deliverable's sole warrant is arithmetic consistency with its own baseline; here two sections of one document disagree and neither is marked as the authority." }
      - { rank: BLOCKING, file: docs/specs/RES-0002-mechanical-context-offload-to-cheap-tier.md, line: 305,
          issue: "'Elapsed effort on this spike: approximately 3 hours of agent time in one Implementation dispatch' is contradicted by this repository's own STATE.yaml, which records FIVE dispatches for this ref (Planning 629s, Implementation 1142s, Validation 1312s, Remediation 806s, Validation 684s = 4573s = 1.27h summed agent time, 755392 tokens). The Implementation dispatch alone ran 19 minutes, not 3 hours.",
          failure_scenario: "Spec D8 requires the document to record the actual elapsed effort 'so a reader can weigh the findings against what was spent on them'. A reader weighing these findings sees a cheap one-dispatch spike and under-counts the real cost by 5x on dispatch count and 2.4x on agent time. Because the deliverable merges to main as the durable record of this spike, the false cost figure outlives every other artifact of the ride." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0173-spec-mechanical-context-offload-to-cheap-tier.md, line: 283,
          issue: "Spec-AC-07's Notes cell asserts 'Implementation adjudicated the hypothesis this ride (2026-09-07): \"upheld\"'. The delivered document says 'undecided' (RES:527). Remediation softened the label and the AC table was not updated.",
          failure_scenario: "At PR close the AC row flips to a terminal status with Evidence, freezing a Notes cell that names the wrong verdict. Anyone auditing the spec's AC table against the deliverable — the exact check docs-audit --gate and a future verify pass perform — reads 'upheld' from the spec and 'undecided' from the artifact and cannot tell which is the delivered state." }
      - { rank: NON-BLOCKING, file: docs/analysis/mechanical-context-offload/ledger-token-attribution.mjs, line: 41,
          issue: "parseArgs ignores every unrecognized argument silently. A mistyped flag falls back to DEFAULT_LEDGER_PATH — the LIVE, growing docs/ai/METRICS.jsonl — and the script still exits 0.",
          failure_scenario: "Reviewer or validator runs `node ...mjs --pathh <snapshot>` (verified: exits 0, reads the live ledger, prints a full plausible report). D2 exists specifically because 'the numbers in the document become unreproducible the moment this very ride appends its own runs'. Once this ride's five runs are flushed, the same typo produces different numbers with no error, and the only warning is the snapshot= line a hurried reader scrolls past." }
      - { rank: NON-BLOCKING, file: docs/analysis/mechanical-context-offload/ledger-token-attribution.mjs, line: 212,
          issue: "The reconciliation guard is tautological for the failure mode D3 names. roleSum, modelSum and tokensTotal are all accumulated from the same `tokens` value inside one loop body with no intervening filter, so the equality cannot fail on any input. Separately, readLedgerLines silently discards every line not starting with '{' and prints no count of what it dropped (32 of the 167 lines in the pinned snapshot).",
          failure_scenario: "A record excluded at read time — a pretty-printed entry, a BOM-prefixed line, a future comment convention — vanishes before either counter is touched. work_items simply reads lower, both group sums still equal tokens_total, the guard passes and the script exits 0 with an understated total that the document then quotes as measured. Verified benign for this snapshot (all 32 dropped lines are the ledger's comment header, 0 JSON.parse failures), so no shipped number is wrong; the guard just cannot detect the class that would make one wrong." }
      - { rank: NON-BLOCKING, file: docs/analysis/mechanical-context-offload/ledger-token-attribution.mjs, line: 44,
          issue: "`--path` with no following value sets out.path to undefined; path.resolve then throws an unhandled TypeError instead of a usage message.",
          failure_scenario: "`node ...mjs --path` prints a node:path stack trace. Harmless to correctness (non-zero exit, no numbers emitted), but the script is the named reproduction command in the spec's Verification list and a truncated invocation gives a validator an internals stack trace rather than 'missing value for --path'." }
  cannot_verify:
    - { claim: "'approximately 3 hours of agent time' as a wall-clock intent rather than summed agent time",
        closes_with: "Nothing closes it as written — STATE.yaml refutes both readings (summed agent time 1.27h; ride wall clock 04:29:51Z to 09:04:24Z = 4h34m). Recorded here as cannot-verify only to state that no reading of the sentence is supported." }
    - { claim: "'shunt ships 51 hook-and-transport tests'",
        closes_with: "A named count command over the repo. Reviewer measured hook-evals.json 17 + bash-hook-evals.json 17 = 34 eval cases, plus 18 check() invocations in transport-evals.sh of which 16 are distinct test names (two pairs are if/else branches) — 50 to 52 depending on how branches are counted. The claim is in the right neighbourhood, no AC depends on it, and the exact 51 could not be reproduced deterministically." }
    - { claim: "That the shunt sources were fetched on 2026-09-07 specifically, and that the GitHub API (rather than raw.githubusercontent) was the channel",
        closes_with: "A captured fetch log. What IS verified: all three cited paths return HTTP 200 at spotify/portal-ai-plugins@main today, and every contract detail the deliverable states about them (PreToolUse matched on Read and on Bash, JSON on stdin, wc -l, SHUNT_MIN_LINES default 350, {\"decision\": \"block\", \"reason\": ...}, the offset/limit escape hatch, the pipe and redirection skips, jq-based shell not Node) matches the fetched sources exactly. The 'source-verified' provenance token is truthful." }
    - { claim: "That the mechanical share estimate is TRUE (0% to 21% run-weighted, 29.4% token-weighted)",
        closes_with: "Per-tool-call token attribution, which exists nowhere in either ledger. Spec Residual Risks says this explicitly. Reviewer confirms the ARITHMETIC of both figures against the pinned snapshot and confirms both are labelled upper bounds with named denominators; their truth as estimates of mechanical work is untestable by construction." }
    - { claim: "That the eight Spec-AC rows reach a terminal status with non-empty Evidence (the spec's own PASS criteria)",
        closes_with: "The PR close step (SKILL_PR 4c). All eight rows are `planned` with empty Evidence at review time and docs-audit --gate correctly exits 1 saying so. This is the MECHANICAL CHECKS carve, not a defect, and is named here so the gap is visible rather than assumed closed." }
    - { claim: "Full-sweep suite health for this scope",
        closes_with: "The 89-suite sweep with AAI_TEST_TIMEOUT=3000. Reviewer ran five suites: aai-check-state PASS, aai-docs-audit PASS, aai-spec-lint PASS, aai-follow-ups FAIL (TEST-005), aai-spec-amend FAIL (TEST-008). Both failures are the stale-branch decisions.jsonl artifact and are NOT defects — see the diagnosis section below." }
  overall: fail
```

## Scope and spec

Reviewed at `/Users/ales/Projects/aai-mechanical-context-offload`, branch
`feat/mechanical-context-offload-to-cheap-tier`, base `8d967f47`. The entire
scope is uncommitted in the working tree; the diff scope is the union of
`git diff --name-only 8d967f47...HEAD` (empty) and `git status --porcelain`:

```
docs/INDEX.md
docs/ai/EVENTS.jsonl
docs/analysis/mechanical-context-offload/ledger-token-attribution.mjs
docs/specs/RES-0002-mechanical-context-offload-to-cheap-tier.md
docs/specs/SPEC-0173-spec-mechanical-context-offload-to-cheap-tier.md
```

Spec: `docs/specs/SPEC-0173-spec-mechanical-context-offload-to-cheap-tier.md`
(`SPEC-FROZEN: true`, ceremony 2, 8 Spec-AC rows, 8 `check`-type TEST rows).

## The arithmetic, re-derived independently

The dispatch is right that the script is the sole warrant for the deliverable.
I did not read its numbers off the document. I wrote a second implementation
with a deliberately different code path (`indexOf` scanning instead of a regex,
its own role and model folding) and ran both against
`git show 8d967f47:docs/ai/METRICS.jsonl`.

Every figure agrees:

```
agent_runs 611            with_marker 384      without 227
tokens_total 59685340     multi_marker 0
distinct raw roles 13     6 canonical + 7 free-text singletons, all fold, remainder none
distinct raw model_ids 10 claude-opus-4-8[1m] appears 63 times; "unknown" 26 times
Implementation 48 + TDD Implementation 84 = 132 of 611 = 21.60%
token-weighted (2702847 + 14857259) / 59685340 = 29.421%
```

The seven folded role variants the document lists are exactly the seven the
ledger holds. The 63 bracket-suffixed ids are all `claude-opus-4-8[1m]`. The 26
`unknown` runs are all in the no-marker bucket, which is why they carry no token
row — the document's decision to keep them as a visible bucket is honest.

Three things I specifically tried to break and could not:

- **Zero / one / many usage markers.** `extractUsageTokens` returns
  `{tokens: null}` on zero, takes `matches[0]` on many, and prints
  `multi_marker_records`. There are 385 textual occurrences of
  `usage_total_tokens=` in run notes but only 384 marker-bearing runs. The 385th
  is a Planning note for `loop-token-usage-capture` that mentions the marker
  *grammar* in prose — `usage_total_tokens=` with no number. The `(\d+)` in the
  pattern correctly declines it. This is the one self-referential trap in the
  corpus and the script walks past it.
- **The nested-section collision claim.** The document argues a nested
  per-harness block would not fail to parse but would silently collide. I ran
  `loadModelRouting()`'s live regex against the four candidate line shapes:
  `"    mechanical: gpt-5.3-codex"` captures key `"  mechanical"`, which
  `.trim()` reduces to `"mechanical"` — the same key the top-level tier row uses.
  Confirmed. The argument is correct and non-obvious, and it is stronger than the
  intake's original "breaks the parse" framing.
- **`suggestModel()` purity.** Read at `orchestration-dispatch.mjs:1154`. Takes
  `(out, routing)`, touches no `fs` and no network, returns a string or null.
  The resolution chain is exactly
  `roles[role@lane] ?? roles[role] ?? tiers[tier] ?? null`. The document's
  purity argument holds.

Also confirmed first-hand: `EVENTS.jsonl` at the base holds 2192 records, exactly
ten distinct event types matching the document's list, and every record has the
key set `actor/event/payload/ref/ts/v` — the document's "no field carrying a tool
name or a file path" claim is true of all 2192. `orchestration-dispatch.mjs`
contains exactly one occurrence of the string `harness`, and it is a comment
about prompt-cache behaviour. `.claude/` holds only `skills/`. `TIERS` holds ten
role keys and the do-not-delegate table's ten rows are a bijection onto them.
None of the five recommendation ids appear in the 141-item follow-up registry,
and no row is labelled `filed:`.

## AC table walk

| Spec-AC | Call | Evidence |
|---|---|---|
| Spec-AC-01 | compliant | grep rc=1 (zero placeholders); docs-audit strict on the RES exits 0; full-repo strict audit verdict CLEAN |
| Spec-AC-02 | compliant | script exits 0 on the pinned snapshot with all four reconciliation lines and both group sums equal; reproduced by an independent second implementation |
| Spec-AC-03 | compliant | RES:412 range form, low 0 <= high 21, denominator 611 named; RES:434 instrumentation line, path exists |
| Spec-AC-04 | compliant | one verdict line, value available-with-cost; settings.json absence quoted; all three required tokens present; provenance independently confirmed against the live shunt sources |
| Spec-AC-05 | compliant | 10 TIERS keys, 10 table rows, empty set difference both directions |
| Spec-AC-06 | compliant | 5 rows, valid types and sizes, keys 9 7 5 4 3 non-increasing, zero filed ids |
| Spec-AC-07 | compliant | one verdict line reading undecided, three falsifier headings, both rejected-alternative tokens |
| Spec-AC-08 | compliant | 5 changed paths, all under docs/, none of the four forbidden surfaces |

TEST-001 through TEST-008 are `check`-type rows with no test file by design
(strategy `untested`). I re-ran the command behind each row rather than trusting
the row. All eight are green as commands. The Status column of every Spec-AC row
is `planned` with empty Evidence — the MECHANICAL CHECKS carve; the terminal flip
belongs to PR close, and `docs-audit --gate` exits 1 naming all eight rows, which
is the expected shape at this stage.

`spec-lint` on the frozen spec: LINT PASS, 0 findings.
`generate-docs-index.mjs` is idempotent — regeneration changes only the
`Generated:` timestamp line, no content drift.
`EVENTS.jsonl` grew by exactly two appended lines at the tail; the base is a
byte-exact prefix (HAZ-LEDGER satisfied).

## The two failing suites — I agree with the diagnosis

I measured it independently rather than accepting it:

```
branch docs/ai/decisions.jsonl   571006 bytes
main   docs/ai/decisions.jsonl   580282 bytes   delta 9276
branch is byte-exact prefix of main: true
```

`test-aai-follow-ups` TEST-005 reports "working tree is 9276 bytes shorter than
base" and `test-aai-spec-amend` TEST-008 reports "SHORTER by 9276" — the same
number, to the byte. Nothing on this branch rewrote the ledger; main appended
after the fork and both suites compare against `origin/main`. A rebase clears
both. Not a defect in this scope, and I concur with the orchestrator.

(Round 2's validation note recorded the delta as 7763; main has advanced again
since, which is why it now reads 9276. The mechanism is identical.)

## The three opinions the dispatch asked for

**Is `docs/analysis/` the right home for the script?** Yes, and the
`select-suites` consequence is inherited rather than introduced. Every leg of D2
that I could check holds: `docs-audit` scans only `.md`, so the script adds no
doc-lifecycle obligation; `PROFILES.yaml` classifies `.aai/` paths only. And
`docs/analysis/` already held four committed `.md` files at the base commit,
every one of them equally unmapped — the tree was already a `FULL_RUN` trigger
before this scope existed. Confirmed:

```
$ printf 'docs/analysis/.../ledger-token-attribution.mjs\n' | node .aai/scripts/select-suites.mjs --files-from -
FULL_RUN reason=unmapped path=docs/analysis/mechanical-context-offload/ledger-token-attribution.mjs
```

The selector is fail-open by design and escalating is the safe direction. My
opinion: leave the script where it is, and separately map `docs/analysis/**` onto
the docs-hygiene suite list so analysis-only edits stop costing a 32-minute
sweep. That is a suite-map change, not a change this scope should make.

**Is `undecided` the honest label?** Yes, and it is the more honest of the two.
Falsifier 2 is the only one genuinely tested against live code, and I re-verified
that test myself — `orchestration-dispatch.mjs` really does contain exactly one
`harness` occurrence and it really is a comment. Falsifier 1 rests on
absence-of-evidence in this project's own data, which the document says in those
words. Falsifier 3 is untestable until the mechanism it would measure exists,
which is a correct reading, not an evasion. One real attempt out of three named
falsifiers does not earn "upheld". The adjudication section explains that
reasoning in the open rather than just changing a token, which is the right way
to walk a claim back.

**Is anything overclaimed?** No, materially. This document is unusually
disciplined about denominators: the run-count share names 611, the token-weighted
share names the 59,685,340 marker-bearing tokens rather than borrowing the
611-run denominator, both are labelled upper bounds, and the lower bound is
stated as 0% with the reason. The do-not-delegate table is presented as argument,
not measurement. One mild tension worth an INFO: the Findings assert "the
denominator for any share stated below is 611 runs", and the 29.4% figure two
sections later uses a token denominator instead — it names its own denominator in
the same sentence, so no reader is misled, but the blanket claim is over-broad
as written.

## INFO notes (never gate)

- RES:~309 labels the quoted block "Full stdout, unedited" while line 1 was edited
  from the real absolute path to `<scratch>/metrics-at-base.jsonl`. The
  substitution is obviously deliberate and reasonable; "unedited" is one word too
  strong for a document this careful about provenance elsewhere.
- The blanket-denominator tension described above.
- The "51 hook-and-transport tests" count (see cannot_verify).
- `main()` ends in `process.exit(0)` after buffered `console.log` output. Node's
  stdout to a pipe is asynchronous and `process.exit` does not flush it, and the
  reconciliation and no-marker blocks are printed LAST. I probed it five times
  through a pipe and got the complete 44-line output every time, so there is no
  observed bite at this output size; a plain `return` would remove the class. The
  repo already has `lib/cli-pipe-guard.mjs` for exactly this, though D2's
  standalone intent argues against importing it here.
- A note carrying `usage_total_tokens=` with a malformed or absent number is
  bucketed as "no marker" with no distinct counter. Correct behaviour for the one
  case in the corpus (the prose mention described above); a genuinely malformed
  capture would be indistinguishable from a run that never captured usage.

## Warning dispositions (H6)

- NON-BLOCKING SPEC:283 (stale `upheld` note) — **remediate-in-tree**. One clause
  appended to the Notes cell recording that Remediation softened it to
  `undecided`. It must not survive the terminal AC flip.
- NON-BLOCKING script:41 (silent flag fallback to the live ledger) —
  **remediate-in-tree**. Refuse an unrecognized argument rather than ignoring it.
  Cheap, and it protects the one property D2 was written to protect.
- NON-BLOCKING script:212 (tautological guard, unaccounted dropped lines) —
  **accepted residual: P3 assurance strength with no observed bite. Every dropped
  line in the pinned snapshot is a comment (verified: 32 of 167, zero
  JSON.parse failures), both group sums are correct, and no shipped number is
  affected. The guard is weaker than it reads but leaves no false record.** A
  printed `skipped_non_record_lines=` count would close it if the script is ever
  reused.
- NON-BLOCKING script:44 (`--path` with no value) — **remediate-in-tree**,
  same edit as the flag fallback.

## Next steps

Both BLOCKING findings are single-line edits to text, not to logic:

1. `RES:621` — change `131-of-611-run` to `132-of-611-run`. The percentage in the
   same parenthesis stays `21%` (132/611 = 21.60%, floors to 21).
2. `RES:305` — restate elapsed effort against `docs/ai/STATE.yaml`: five recorded
   dispatches (Planning, Implementation, Validation, Remediation, Validation),
   4573 seconds of summed agent time, 755,392 tokens, against the 2-day timebox.
   Whatever form Remediation chooses, it should be re-derivable from STATE the way
   every other number in this document is re-derivable from the ledger.

Then the two remediate-in-tree NON-BLOCKING items, then a rebase onto main to
clear the two ledger-prefix suite failures, then the full sweep with
`AAI_TEST_TIMEOUT=3000` that round 2 correctly recorded as still owed.

Nothing in the measurement script's arithmetic needs to change. Everything it
prints is correct.

## Coaching-attempt record (anti-gaming contract)

The dispatch named an area to concentrate on, listed specific numbers to check,
and pre-characterized two known-expected findings (the `--gate` exit 1 and the
two ledger-prefix suite failures). Per the anti-gaming rule I record that here.
It did not pre-rate severity or scope-exclude anything, it explicitly invited
disagreement with the ledger diagnosis, and I reviewed the full scope regardless
— including re-measuring both pre-characterized items myself rather than
accepting them. The two BLOCKING findings below were not among the areas named.

## Process note

While checking `generate-docs-index.mjs` idempotence I ran
`git checkout-index -f -- docs/INDEX.md`, a restoring git command on a tracked
file, against HAZ-RESTORE. I had taken a byte-copy of `docs/INDEX.md` into the
scratchpad immediately beforehand and restored from it within the same minute;
`diff -q` confirms the working-tree file is byte-identical to the pre-existing
state and `git diff --stat` shows the same `6 insertions, 4 deletions` the
dispatch's opening snapshot recorded. No content was lost. Recorded rather than
omitted.
