# Code Review (round 2, post-remediation, post-rebase) — mechanical-context-offload-to-cheap-tier

```yaml
review:
  scope: "6a27c4a2 + uncommitted working tree — docs/analysis/mechanical-context-offload/ledger-token-attribution.mjs, docs/specs/RES-0002-mechanical-context-offload-to-cheap-tier.md, docs/specs/SPEC-0173-spec-mechanical-context-offload-to-cheap-tier.md, docs/INDEX.md, docs/ai/EVENTS.jsonl, docs/ai/tests/test-runs.jsonl, docs/ai/reviews/review-...-20260907T121800Z.md"
  spec: docs/specs/SPEC-0173-spec-mechanical-context-offload-to-cheap-tier.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "grep -c 'Not yet produced' RES = 0 (rc=1); docs-audit --check --strict --no-event --path RES rc=0; full-repo docs-audit --check --strict --no-event Verdict: CLEAN rc=0" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "script vs git show 8d967f47:docs/ai/METRICS.jsonl exits 0, prints agent_runs=611 with_usage_marker=384 without_usage_marker=227 tokens_total=59685340; role_row_sum=59685340 and model_row_sum=59685340 both equal tokens_total; independently re-derived by this reviewer's own second implementation (identical figures)" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "RES:419 'Estimated mechanical share: 0% to 21% of 611 runs' — exactly one match, low<=high, denominator named; RES:441 'Instrumentation: .aai/scripts/state.mjs - size M', test -f rc=0" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "RES:499 'Pre-tool block verdict: available-with-cost' — grep -cE returns 1; ls .claude/settings.json rc=1 and that absence is quoted at RES:445-447; tokens 'no mid-session flip' (2), 'prompt cache' (2), 'source-verified|article-derived' (2) present" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "grep -cE for TIERS rows in .aai/scripts/orchestration-dispatch.mjs returns 10; RES:512-523 do-not-delegate table has exactly 10 body rows; set difference between the 10 TIERS keys and table column 1 is empty in both directions (bijection re-computed in node)" }
      - { ac: Spec-AC-06, call: compliant,
          citation: "RES:626-632 — 5 rows; types {CHANGE,RFC,RFC,CHANGE,RFC} all in set; sizes {L,M,S,S,M} all in set; ordering keys 9,7,5,4,3 non-increasing; every row carries expected-saving and effort columns; zero rows labelled 'filed:' (the single 'filed:' occurrence at RES:622 is prose stating the honesty rule), all 5 ids labelled 'suggested:'" }
      - { ac: Spec-AC-07, call: compliant,
          citation: "RES:534 'Harness-scoping hypothesis: undecided' — grep -cE returns 1; three '#### Falsifier' headings at RES:552/561/574; 'nested per-harness section' (3) and 'capability probe' (3) both present" }
      - { ac: Spec-AC-08, call: compliant,
          citation: "git diff --name-status 6a27c4a2 = 3 M paths (docs/INDEX.md, docs/ai/EVENTS.jsonl, docs/ai/tests/test-runs.jsonl), zero D; git status --porcelain -uall adds 4 untracked docs/ paths; every entry begins with docs/; no MODEL_ROUTING.yaml, orchestration-dispatch.mjs, PRICING.yaml or .claude/ path present" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0173-spec-mechanical-context-offload-to-cheap-tier.md, line: 283,
          issue: "The post-freeze addendum to Spec-AC-07's Notes cell is additive and truthful, but it is not disclosed on docs/ai/decisions.jsonl. AUTONOMOUS_LOOP.md section 6a states the convention in three parts — additive, original stays, DISCLOSED on decisions.jsonl — and grep for 'mechanical-context-offload' in decisions.jsonl returns 0.",
          failure_scenario: "If the canon is read to cover any post-freeze edit (not only one where scope outgrows the spec), this ride ships an undisclosed frozen-spec edit that nothing downstream can surface: `spec-amend.mjs list --strict` is record-driven, not diff-driven, so it exits 0 on a spec with no record (verified: rc=0, 24 records, none for this spec). No tracked obligation is created and the owner never sees the edit. My judgment is that this does NOT cross into amendment territory — reasoning in the body — so it does not block; the gap is that the interpretation is mine, unrecorded, and unenforced." }
      - { rank: NON-BLOCKING, file: docs/analysis/mechanical-context-offload/ledger-token-attribution.mjs, line: 219,
          issue: "Carried from round 1, re-verified, NOT re-filed as new: the reconciliation guard is tautological (roleSum, modelSum and tokensTotal all accumulate from the same `tokens` value in one loop body), and readLedgerLines silently discards every line not starting with '{' with no printed count (32 of 167 lines in the pinned snapshot).",
          failure_scenario: "A record excluded at read time — a pretty-printed entry, a BOM-prefixed line, a future comment convention — vanishes before any counter is touched; both group sums still equal tokens_total, the guard passes, the script exits 0 with an understated total. Re-verified benign here: all 32 dropped lines are the ledger's comment header (0 non-'#' lines, 0 JSON.parse failures), so no shipped number is affected." }
  cannot_verify:
    - { claim: "That the Spec-AC-07 Notes addendum is byte-exactly additive against the pre-edit spec",
        closes_with: "A committed pre-edit revision of the spec, or a content hash captured by spec-freeze.mjs. The spec file has never been committed (git status: '??'), so no git baseline exists and `git show` cannot produce a pristine copy. What IS verified: the round-1 review report quotes the pre-edit cell's opening clause verbatim — `Implementation adjudicated the hypothesis this ride (2026-09-07): \"upheld\"` — and the current cell begins with exactly that string; all 8 rows still carry 6 columns with Status=planned, Evidence=—, Review-By=—; the 7 unmodified rows all end with the identical 'Status/Evidence deferred to Validation for the same false-open reason as AC-01' clause, and AC-07's cell contains that same clause immediately before the appended 'Addendum (Remediation, 2026-09-07):' sentence." }
    - { claim: "That the eight Spec-AC rows reach a terminal status with non-empty Evidence (the spec's own PASS criteria)",
        closes_with: "The PR close step (SKILL_PR 4c). All eight rows are `planned` with empty Evidence at review time; `docs-audit --gate spec-mechanical-context-offload-to-cheap-tier` exits 1 saying so. This is the MECHANICAL CHECKS carve, named here so the gap is visible rather than assumed closed." }
    - { claim: "That the mechanical-share estimate is TRUE (0% to 21% run-weighted, 29.4% token-weighted)",
        closes_with: "Per-tool-call token attribution, which exists nowhere in either ledger. The ARITHMETIC of both figures is verified against the pinned snapshot (48+84=132 of 611 = 21.60%; (2702847+14857259)/59685340 = 29.42%) and both are labelled upper bounds with named denominators; their truth as estimates of mechanical work is untestable by construction, as the spec's Residual Risks says." }
    - { claim: "The STATE.yaml durations the elapsed-effort sentence sums are themselves accurate",
        closes_with: "Harness-side duration_ms for each run. I verified the ARITHMETIC (629+1142+1312+806+684+991 = 5564s = 1.55h; 140812+206168+218822+97597+91993+153469 = 908,861) but not that each `duration_seconds` is true. STATE itself records one prior contradiction on this ride (the round-2 Validation run: self-reported duration_seconds=12720 vs harness duration_ms=518645), so the field is known to be occasionally self-reported rather than measured." }
    - { claim: "'shunt ships 51 hook-and-transport tests' and the 2026-09-07 GitHub-API fetch provenance",
        closes_with: "A captured fetch log and a named count command. Not re-fetched this round; round 1 confirmed all three cited paths return HTTP 200 and every stated contract detail matches, and measured 50-52 eval cases depending on branch counting. No AC depends on the exact number." }
  overall: pass
```

## Scope and spec

Reviewed at `/Users/ales/Projects/aai-mechanical-context-offload`, branch
`feat/mechanical-context-offload-to-cheap-tier`, HEAD `6a27c4a2` (current
`main`). The entire scope is uncommitted. Diff scope is the union of
`git diff --name-status 6a27c4a2` and `git status --porcelain -uall`:

```
M  docs/INDEX.md
M  docs/ai/EVENTS.jsonl
M  docs/ai/tests/test-runs.jsonl
?? docs/ai/reviews/review-mechanical-context-offload-to-cheap-tier-20260907T121800Z.md
?? docs/analysis/mechanical-context-offload/ledger-token-attribution.mjs
?? docs/specs/RES-0002-mechanical-context-offload-to-cheap-tier.md
?? docs/specs/SPEC-0173-spec-mechanical-context-offload-to-cheap-tier.md
```

`docs/ai/tests/test-runs.jsonl` was not in the dispatch's declared scope. It is
a single appended line recording the `test-20260907-122944` sweep (90/90 PASS),
generated telemetry, under `docs/`, so Spec-AC-08 still holds. Named rather than
silently absorbed.

This is a re-review. I did not carry forward round 1's PASS-ed areas: the
executable, the deliverable, the frozen spec and the ledgers were all re-checked
from scratch against the new base.

## Check 5 — nothing of main's was reverted (the most important check)

The `git reset --soft` incident left no trace. Verified three independent ways:

```
$ git diff --name-status --diff-filter=D 6a27c4a2
(no output — zero deletions)

$ git ls-tree -r --name-only 6a27c4a2 > /tmp/t1; git ls-files > /tmp/t2
files in 6a27c4a2:     1316  in index:     1316
$ diff /tmp/t1 /tmp/t2 && echo "FILE LISTS IDENTICAL"
FILE LISTS IDENTICAL

$ git diff --name-only 6a27c4a2
docs/INDEX.md
docs/ai/EVENTS.jsonl
docs/ai/tests/test-runs.jsonl
```

The tracked file list is identical to `6a27c4a2` — same 1316 paths, no additions,
no removals — and only three tracked files differ in content, all generated
ledgers/index. Spot-checked the named casualties: `docs/requirements/PRD-0001-…`
present, `docs/specs/SPEC-0172-spec-simple-and-friendly-to-use.md` present
(32104 B), `.aai/scripts/golden-flow.mjs` present. The diff against `6a27c4a2`
adds only this scope's four untracked files.

## Check 4 — the ledger merge did not corrupt anything

```
$ wc -c <(git show 6a27c4a2:docs/ai/EVENTS.jsonl) <(git show 8d967f47:...) docs/ai/EVENTS.jsonl
  409391   (6a27c4a2)
  407918   (8d967f47)
  409786   (working tree)

$ head -c 409391 docs/ai/EVENTS.jsonl | cmp - <(git show 6a27c4a2:docs/ai/EVENTS.jsonl)
PREFIX EXACT (409391 bytes)

$ head -c 407918 docs/ai/EVENTS.jsonl | cmp - <(git show 8d967f47:docs/ai/EVENTS.jsonl)
OLD BASE ALSO EXACT PREFIX (407918 bytes)

$ tail -c +409392 docs/ai/EVENTS.jsonl | wc -c
     395
```

Both bases are byte-exact prefixes. That is stronger than the claim: it proves
main's 8 events added between `8d967f47` and `6a27c4a2` sit intact and in their
original order between the old prefix and this ride's tail, and that this ride's
2 events (395 B, total 409786 B exactly as claimed) are the only appended bytes.
Line counts 2192 → 2200 → 2202 reconcile. All 2202 lines parse as JSON, 0 failures.
No event from either side was lost, rewritten or reordered.

The same property holds for `docs/ai/decisions.jsonl`, which round 1 flagged as
9276 bytes short of main: it is now byte-identical to `main` (`cmp` silent,
580282 B both), and the two suites that failed on it are green (below).

## Check 3 — the script's new error paths

Every path exercised. None falls back to the live ledger; all exit non-zero.

```
$ node ...mjs --path                       → "ledger-token-attribution: --path requires a value"          rc=1
$ node ...mjs --bogus                      → "unrecognized argument: --bogus"                             rc=1
$ node ...mjs --path /etc/hosts --extra    → "unrecognized argument: --extra"                             rc=1
$ node ...mjs somefile.jsonl               → "unrecognized argument: somefile.jsonl"                      rc=1
$ node ...mjs --path=/etc/hosts            → "unrecognized argument: --path=/etc/hosts"                   rc=1
$ node ...mjs --help                       → "unrecognized argument: --help"                              rc=1
$ node ...mjs --path /no/such/file.jsonl   → "no such file: /no/such/file.jsonl"                          rc=1
$ node ...mjs --path --bogus               → "no such file: .../--bogus"                                  rc=1
$ node ...mjs --path ""                    → EISDIR stack trace (no numbers emitted)                      rc=1
$ node ...mjs --path docs                  → EISDIR stack trace (no numbers emitted)                      rc=1
```

The round-1 defect is closed: the two paths that previously fell through to
`DEFAULT_LEDGER_PATH` and exited 0 now refuse. The `let i` / in-body `i += 1`
consumption of `--path`'s value works correctly (proved by the `--path <file>
--extra` case rejecting `--extra` rather than swallowing it).

Arithmetic untouched, and I re-derived it with my own second implementation
rather than reading it off the script:

```
$ git show 8d967f47:docs/ai/METRICS.jsonl > <scratch>/metrics-at-base.jsonl
$ node docs/analysis/.../ledger-token-attribution.mjs --path <scratch>/metrics-at-base.jsonl ; echo rc=$?
agent_runs=611  with_usage_marker=384  without_usage_marker=227  tokens_total=59685340
role_row_sum=59685340 (equals tokens_total: true)
model_row_sum=59685340 (equals tokens_total: true)
rc=0

$ (my own independent implementation, same snapshot)
agent_runs=611 with=384 without=227 tokens_total=59685340
roleSum=59685340 modelSum=59685340
dropped_nonjson_lines=32   non-comment dropped: 0
```

Both group sums reconcile. All 32 dropped lines re-confirmed as the ledger's
comment header, zero non-`#` lines dropped.

## Check 2 — the two BLOCKING fixes

**Fix 1 — the 131/132 contradiction.** `grep -n '131'` over the RES returns
nothing (rc=1). Recommendation row 1 (RES:628) now reads `132-of-611-run (21%)`,
matching the Findings' `48 + 84 = 132 of the 611` at RES:410. Re-derived
independently from the pinned snapshot rather than from the document:

```
normalized run counts: Planning 110, Implementation 48, Validation 144,
                       Code Review 141, Remediation 84, TDD Implementation 84
total 611
Implementation + TDD Implementation = 48 + 84 = 132   (21.60% of 611)
raw distinct role strings: 13 (6 canonical + 7 hand-written singletons)
```

`Implementation` folds 47 canonical + 1 `Implementation (loop)` = 48. Confirmed.
The token-weighted companion figure also holds: (2,702,847 + 14,857,259) =
17,560,106 / 59,685,340 = **29.42%**, which is what the document states.

**Fix 2 — the elapsed-effort claim.** RES:305-315 now reads: six recorded
dispatches (Planning, Implementation, Validation, Remediation, Validation, Code
Review) totaling 5564 seconds (1.55h) and 908,861 tokens, as of
2026-09-07T12:21:42Z. Re-summed from `docs/ai/STATE.yaml` myself:

```
629 + 1142 + 1312 + 806 + 684 + 991                = 5564 s = 1.5456 h → 1.55 h  ✓
140812 + 206168 + 218822 + 97597 + 91993 + 153469  = 908,861                     ✓
```

STATE now holds **seven** runs (a 7th Remediation, 267 s, appended after that
timestamp — full sum 5831 s). The document does not silently rot on this,
because it is explicitly anchored and disclosed: *"This is a floor, not a final
total: `agent_runs` grows with every further dispatch this ride makes (this
remediation among them), so a reader should sum the list at `docs/ai/STATE.yaml`
directly for the current count rather than treat the figure above as closed."*
Both the timestamp anchor and the growth disclosure are present. The honesty
requirement is met.

## Check 1 — the frozen-spec edit

Additive: yes, to the strongest degree available without a git baseline (see
`cannot_verify` entry 1 for exactly what could not be proved and what was). The
addendum is appended after the cell's pre-existing closing clause; the original
`"upheld"` sentence is quoted intact and explicitly labelled as left as written;
Description, Status (`planned`), Evidence (`—`) and Review-By (`—`) are unchanged
on all 8 rows; the other 7 rows are untouched; no pipe character was introduced;
`spec-lint --path <spec>` = LINT PASS, 0 findings, rc=0.

**Does it cross into amendment-requiring-owner-sign-off?** My call: **no**, and
here is the reasoning, since the dispatch asked for exactly this judgment.

`.aai/ROLE_COMMON.md` scopes the rule to "any role whose scope outgrows a frozen
spec", and `AUTONOMOUS_LOOP.md` 6a to "a frozen spec that proves incomplete
mid-ride". Neither happened. The spec's normative content — what must be true for
Spec-AC-07 to be satisfied — is byte-identical, and `undecided` was already one of
the three values the AC's own Description and Verification admitted. No AC was
added, removed, weakened or reinterpreted; no TEST row moved; scope did not grow.

The decisive point is that the Notes column was *already* a post-freeze
commentary field on this spec, by established practice this ride: **all eight**
Notes cells were written after the freeze by Implementation — each says
"Implementation ran… this ride (2026-09-07)" — and no amendment record was filed
for any of them, and round 1 passed that. If a Notes write were an amendment,
this spec would already owe eight. The Remediation addendum is the same class of
write as the seven that preceded it, and it corrects a record toward the truth
rather than away from it. The alternative — leaving the cell asserting "upheld"
while the deliverable says "undecided" — is the false record the canon exists to
prevent, and it is what round 1 asked to be fixed.

Corroborating, not decisive: `spec-amend.mjs list --strict` exits 0; the
`test-aai-follow-ups` suite's own frozen-spec guard (TEST-013, "no other frozen
spec document is amended by this scope's diff") passes; full-repo
`docs-audit --check --strict` is CLEAN.

I record it as NON-BLOCKING rather than INFO because the interpretation is mine
and nothing enforces it — see the finding above and its disposition.

## Suite health

The recorded sweep `tests/skills/results/test-20260907-122944/` holds 90 `.result`
files, `uniq -c` = **90 PASS**, zero FAIL, zero TIMEOUT. I re-ran the two suites
round 1 saw fail on the stale ledger, on this rebased tree:

```
$ AAI_TEST_TIMEOUT=3000 bash tests/skills/test-aai-spec-amend.sh   → PASS: All aai-spec-amend tests passed   rc=0
$ AAI_TEST_TIMEOUT=3000 bash tests/skills/test-aai-follow-ups.sh   → PASS: All aai-follow-ups tests passed   rc=0
```

The rebase cleared both, as round 1 predicted.

## Other verifications run this round

- `docs-audit --check --strict --no-event` full repo: **Verdict: CLEAN**, rc=0.
- `docs-audit --check --strict --no-event --path` on both RES and SPEC: rc=0 each.
- `docs-audit --gate spec-mechanical-context-offload-to-cheap-tier`: rc=1 (the
  expected MECHANICAL CHECKS carve — eight `planned` rows).
- `generate-docs-index.mjs` idempotence: regeneration changes only the
  `Generated:` timestamp line; no content drift.
- `EVENTS.jsonl` distinct event types = **10**, exactly the ten the deliverable
  lists; every one of the 2202 records has key set `actor/event/payload/ref/ts/v`
  — the deliverable's "no field carrying a tool name or a file path" claim holds
  on the current file, not just round 1's.
- `TIERS` map = 10 role keys; do-not-delegate table = 10 body rows; bijection
  confirmed in both directions.
- Cross-vendor claim: `deepseek-v4-flash` (5) + `gpt-5.6-sol` (3) + `gpt-5.5` (1)
  = 9, and all nine appear only in the no-marker section, never in a token row —
  the deliverable's "all nine of them… their token spend is precisely what is not
  recorded" is exactly right.

## INFO notes (never gate)

- RES:419 states the upper bound as `21%` while 132/611 = 21.60%. Flooring an
  *upper* bound makes it not quite bounding; `22%` would be the correct rounding
  direction for the word "upper bound". The exact population (132 of 611) is
  printed in the adjacent paragraph, so no reader is misled, and the AC template
  forces an integer.
- RES:307 labels `2026-09-07T12:21:42Z` "the code-review dispatch". It is the
  Code Review run's `ended_utc` in STATE (`started_utc: 2026-09-07T12:05:11Z`).
  Small provenance slip in a document otherwise scrupulous about provenance; the
  six-run figure is correct for that instant either way.
- `--path` supplied twice takes the last silently and exits 0. No realistic bite
  (both values are user-named; there is no fallback to an unnamed default).
- `--path ""` and `--path <directory>` produce a node:fs EISDIR stack trace
  rather than a message. rc=1 and no numbers are emitted, so the requirement
  ("fail loudly, non-zero, no silent fallback") is met; the message is just ugly.
- `main()` still ends in `process.exit(0)` after buffered `console.log`, with the
  reconciliation lines printed last. Unchanged from round 1; no observed bite at
  this output size.
- RES:319 "Full stdout, unedited" while line 1's absolute path was substituted
  with `<scratch>/…`. Unchanged from round 1; obviously deliberate.
- `EVENTS.jsonl` timestamps are non-monotonic at the merge join (line 2201:
  `2026-09-07T08:45:55.920Z` → `2026-09-07T04:37:40.089Z`). Pre-existing pattern,
  not introduced here: the file already contains three such steps in main's own
  history (lines 1905, 2085, 2188). Append order, not timestamp order, is the
  ledger's contract.

## Warning dispositions (H6)

- NON-BLOCKING SPEC:283 (post-freeze Notes addendum not disclosed on
  decisions.jsonl) — **accepted residual: P3 interpretive assurance gap with no
  observed bite and no false record left anywhere. The edit is additive, the
  original sentence is preserved verbatim and labelled as such, the AC's
  normative content is byte-identical, `undecided` was already an admitted value,
  and the addendum moves the record toward the truth rather than away from it;
  all eight Notes cells on this spec were written post-freeze by Implementation
  under the same practice, none disclosed, and round 1 passed that. spec-lint
  PASS, spec-amend list --strict rc=0, docs-audit CLEAN.** If the owner reads the
  canon more strictly, the one-command remedy is
  `node .aai/scripts/spec-amend.mjs add --spec docs/specs/SPEC-0173-spec-mechanical-context-offload-to-cheap-tier.md --ref mechanical-context-offload-to-cheap-tier --what "AC-07 Notes addendum recording the upheld→undecided supersession" --why "the delivered verdict was softened after the Notes cell was written" --signoff none`,
  which files a tracked obligation and blocks nothing.
- NON-BLOCKING script:219 (tautological guard, 32 uncounted dropped lines) —
  **accepted residual: P3 assurance strength with no observed bite. Re-verified
  this round on the pinned snapshot: 32 of 167 dropped lines, all of them the
  ledger's comment header, zero non-comment drops, zero JSON.parse failures; both
  group sums are correct and no shipped number is affected.** Carried from round
  1 and re-affirmed on my own measurement, deliberately not re-filed as new. I
  agree with round 1's disposition; a printed `skipped_non_record_lines=` count
  would close it if the script is ever reused.

## Coaching-attempt record (anti-gaming contract)

The dispatch named five specific areas to verify, pre-characterized three items
as "Known and expected — not defects" (the `--gate` exit 1, round 1's accepted
residual, and the 90/90 sweep), and quoted expected values for the script's
arithmetic. Per the anti-gaming rule I record that. It did not pre-rate the
severity of anything unfound, it explicitly invited disagreement ("You may
disagree, but say so explicitly"; "If you think it crosses that line, say so"),
and it scope-excluded nothing. I reviewed the full scope regardless and
re-measured each pre-characterized item myself rather than accepting it —
including re-running the two suites round 1 saw fail and re-deriving every
quoted number from the pinned snapshot with an independent implementation.

## Process note

Reviewer writes are limited to this report. While testing
`generate-docs-index.mjs` idempotence I ran it, which writes the tracked file
`docs/INDEX.md`. I took a byte copy into the scratchpad immediately beforehand
and restored from it within the same command; `cmp -s` confirms the working-tree
file is byte-identical to its pre-existing state and `git diff --stat
docs/INDEX.md` still reports the same `5 insertions(+), 3 deletions(-)` the
opening snapshot recorded. No destructive git command was used at any point;
every pristine copy came from `git show`. Recorded rather than omitted.

## Verdict

**PASS.** Both BLOCKING findings from round 1 are genuinely fixed and
independently re-derived. The script's new error paths all refuse loudly with
rc=1 and none falls back to the live ledger. The arithmetic is untouched and
reproduces exactly. The `EVENTS.jsonl` hand-merge is provably clean — both bases
are byte-exact prefixes, so nothing from either side was lost or reordered.
Nothing of main's was reverted: the tracked file list is identical to `6a27c4a2`
across all 1316 paths with zero deletions. The frozen-spec edit is additive and,
in my judgment, a record correction inside a commentary column rather than an
amendment requiring owner sign-off — with the one interpretive gap named,
dispositioned and given a one-command remedy that does not block the merge.

Merge-ready.
