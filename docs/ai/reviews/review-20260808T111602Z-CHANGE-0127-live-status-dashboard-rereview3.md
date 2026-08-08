# Code Review (RE-REVIEW 3, after remediation b181d1f) — CHANGE-0127 / spec-live-status-dashboard

```yaml
review:
  scope: git diff origin/main...HEAD (feat/live-status-dashboard @ b181d1f, 15 commits, 27 files); remediation delta git show b181d1f (9 files, +572/-23)
  spec: docs/specs/SPEC-DRAFT-spec-live-status-dashboard.md (12 Spec-AC, 36-row Test Plan)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "my own real-repo run wrote both outputs and exited 0; --home /nonexistent-home-xyz exited 0 with all three harnesses named in degraded[]; zero http/https/net/tls/dgram imports and zero fetch() in the generator and all three parsers; TEST-001/002/003/028 green" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "unchanged by this delta; TEST-004/005/006/029/033/034 green in my own wrapper run. The warm-cache note replay verified last round still holds (TEST-033 exercises both a cold and a warm run). Honesty caveat for the NEW null-usage path recorded as NB3-2 below, not an AC breach — the AC's named observables (malformed FILE, ts-less record) are both still named" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "unchanged by this delta; TEST-007/008/035 green. My own chmod-000 cache probe still degrades LOUDLY with a named note and correct totals (`cache ... unreadable or corrupt (EACCES), rebuilding from a cold scan`)" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "TEST-009/010 green; my real-corpus run reports gemini-cli usage_today/usage_7d = null (never 0) with 765 files scanned" }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-020/023/032 green; the --home strip is unchanged from the round that verified it by execution" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-011/012/013/014 green; my mutation sweep exercised both tap-spool quota fields end to end (all four render fully escaped)" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-015 green; my sweep injected into hooks.jsonl session_id/hook_event_name/ts — the badge path renders escaped and falls back to the heuristic correctly" }
      - { ac: Spec-AC-08, call: compliant,
          citation: "my own grep: zero references to generate-live-status in close-work-item.mjs, autonomous-loop.sh, .aai/hooks/** and .github/workflows/**; TEST-016/017 green" }
      - { ac: Spec-AC-09, call: compliant,
          citation: "BLOCKING-I dead by my own argv-instrumented fixture under /bin/bash (GNU bash 3.2.57, the machine's only bash): bare `--watch` warm-up invokes the generator with ARGC=1 (script path only — zero stray empty-string args), writes both outputs, opener logs EXISTS, watch loop starts, rc 0 on SIGINT. `.aai/scripts/aai-live.sh:97`. The `--output` opener-target gap on the NON-watch branch is recorded as NB3-1 (NON-BLOCKING, same class and same severity as the NNB-2 this ride already accepted at that rank)" }
      - { ac: Spec-AC-10, call: compliant,
          citation: "BLOCKING-II dead by my own 99-case mutation sweep (every foreign field of all three parser record shapes + both spool shapes x 3 hostile payloads): zero live tags, zero verbatim payloads, zero unescaped 8-char payload slices, every usage value number|null. The SAME sweep produces 80 failures against the pre-fix tree (0f7dacd), all four confined to claude usage fields — the harness is proven sensitive, not vacuous. generate-live-status.mjs:511 naEsc; claude-code.mjs:57-68 / codex.mjs:66-81 Number-coercion. TEST-018/026/030/036 green" }
      - { ac: Spec-AC-11, call: compliant,
          citation: "real-repo generator run then `git status --porcelain` = only the orchestrator's uncommitted `M docs/ai/decisions.jsonl`; nothing under docs/ai from the run. .gitignore + RUNTIME_IGNORE.list + DOCS_AI_CANON.list rows read and correct; TEST-019 green" }
      - { ac: Spec-AC-12, call: compliant,
          citation: "test-aai-layer-profiles.sh and test-aai-hygiene-pack.sh green in my own runs; 11 new .aai paths appear exactly once in PROFILES.yaml extended; exactly one `aai-live-status:` suite-map row; check-test-registration.mjs tests/skills rc 0" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-live.sh, line: 112,
          issue: "The ONE-SHOT (non---watch) branch still opens the hardcoded `$REPO_ROOT/docs/ai/live-status.html` while the generator honors the invocation's own `--output`. `resolve_output_path` (:49-58) exists two functions above and is used only by the --watch branch. The .ps1 twin is symmetric: `Start-Process $OutputHtml` at aai-live.ps1:72 with the --output resolution loop present only inside the $Watch block (:56-64). The script's own header promises 'All args are passed through to generate-live-status.mjs' (:9).",
          failure_scenario: "Reproduced in a fresh scratch repo with an instrumented opener: `/bin/bash .aai/scripts/aai-live.sh --output custom/page.html` writes custom/page.html + custom/live-status-data.json, exits 0, and hands the opener `<repo>/docs/ai/live-status.html` -> opener log `MISSING ...`. On a machine that has run the launcher once at the default path the same invocation is worse: the opener silently shows a STALE page from an earlier run while the fresh page sits unopened. This is exactly the NNB-2 defect (opener target != generated page) that the previous round's remediation fixed on the --watch branch only. Fix: one line — `OPEN_TARGET=\"$(resolve_output_path \"$@\")\"` + the same absolute-path case block, and lift the ps1's resolution loop out of the $Watch block. Recommended disposition: remediate-in-tree." }
      - { rank: NON-BLOCKING, file: .aai/scripts/generate-live-status.mjs, line: 405,
          issue: "`if (r.usage === null || r.usage === undefined) continue;` drops the record with NO note. b181d1f routes a NEW input class into that silent path — a token field that fails to coerce to a finite number now yields null (the honest parser-level answer) and is then absorbed silently by the accumulator. The two lines below it (:410-419) state the opposite invariant for ts-less records ('an upstream format that stops writing timestamps must not look indistinguishable from a genuinely idle day'), and the block comment at :450-453 states it again for absent harnesses ('reporting 0 would let a consumer summing usage_today across harnesses silently absorb a missing source').",
          failure_scenario: "Measured on my own fixtures: a claude fixture whose only record has a non-numeric `input_tokens` produces `usage_today: 0`, `spend.today: []`, `notes: []` — indistinguishable from a genuinely idle day. Codex partial-shape and hostile-`total_tokens` fixtures both produce `usage_today: 0`, `notes: []`. Non-adversarial trigger with no attacker: an upstream drift to string/bigint-as-string token counts silently zeroes the harness on a page whose entire value proposition is honest numbers. Fix: push a named note in the `continue` branch, mirroring the ts-less branch three lines below. Recommended disposition: remediate-in-tree (folds naturally into the O1-family work already done for NB-2/NB-7)." }
      - { rank: NON-BLOCKING, file: .aai/scripts/generate-live-status.mjs, line: 81,
          issue: "`const na = ...` now has ZERO call sites (b181d1f moved the last one to naEsc) but stays in scope, three lines above a comment whose whole point is that calling it is a defect. A non-escaping helper named one character away from the escaping one, retained with no user, is the footgun that produced BLOCKING-1 and BLOCKING-II.",
          failure_scenario: "The next contributor adding a table cell reaches for the shorter, still-exported-looking `na()` — identical signature, identical output for every value they will test with — and re-opens BLOCKING-II with a green suite, because no test asserts 'na() has no call sites'. This is the same 'true only by accident, not by construction' argument the ride already accepted at NON-BLOCKING rank for esc()'s missing apostrophe (NNB-4). Fix: delete the binding (one line); naEsc already covers every case. Recommended disposition: remediate-in-tree." }
  cannot_verify:
    - { claim: "The .ps1 twins behave correctly at runtime on Windows — including that `& node $Gen @WarmupArgs` with an empty $WarmupArgs is the harmless no-op the bash fix's commit message asserts, and that NB3-1 reproduces there as it does in bash (static reading says yes to both).",
        closes_with: "A Windows CI job or a manual pwsh run. TEST-023 is parse + PSScriptAnalyzer only; TEST-031 exercises the bash twin exclusively. Spec RR-2 accepts this." }
    - { claim: "That my 99-case mutation sweep is exhaustive over foreign data. It enumerates every field of the three shipped parsers' record shapes and both spool shapes that I could derive by reading the parsers; a field a parser reads that I did not enumerate, or a fourth parser added later, is not covered — and the sweep lives in my scratchpad, not in the suite.",
        closes_with: "Landing a corpus-sweep/mutation test in tests/skills that derives its field list from the registry rather than from a hand-written list. This is the third round in a row this entry has been named; BLOCKING-II is what it would have caught at freeze." }
    - { claim: "Cache/notes growth on a real long-lived corpus (round 3's N2B-1). My real-corpus run emits notes: 0 and reads 765 files; the 3.6 MB figure came from a synthetic 20k-bad-line fixture.",
        closes_with: "A cache size sample from a machine that has run --watch for weeks." }
    - { claim: "The real Claude Code statusline stdin payload carries rate_limits.five_hour/seven_day in the shape the tap branch expects (spec RR-1).",
        closes_with: "One live statusLine install capturing a real payload." }
    - { claim: "The session-quotas branch renders REAL Codex rate limits correctly — every exercise of it, mine included, is synthetic.",
        closes_with: "A run against a Codex session captured while the account is quota-limited." }
    - { claim: "The hooks overlay merges cleanly into a real .claude/settings.json and the Stop/Notification hooks fire.",
        closes_with: "An install-then-observe run; no test merges the overlay into a real settings file." }
    - { claim: "Upstream harness on-disk formats stay as observed (spec RR-3).",
        closes_with: "Nothing in this repo; the parser registry localizes the blast radius, which is the accepted mitigation." }
  process:
    verdict: pass-with-notes
  overall: pass
```

## Scope, preflight, and method

- `git branch --show-current` = `feat/live-status-dashboard` (never switched, never pushed).
  `docs/ai/STATE.yaml` `worktree.user_decision: worktree`, so the skill's worktree policy
  selects `git diff <base>...HEAD`; `inline_review_scope` is not consulted.
- Review scope: `origin/main...HEAD` @ `b181d1f` (27 files, +4203/-6), with the remediation
  delta `git show b181d1f` (9 files, +572/-23) read hunk by hunk.
- `git status --porcelain` before and after every probe: exactly one line,
  `M docs/ai/decisions.jsonl` — the orchestrator's own uncommitted H6 entry, not mine.
  Every fixture I built lives under the session scratchpad, outside the repo.
- Read first: the round-3 report (105110Z), the round-2 report (102429Z) for severity
  precedent, the frozen spec's AC table and 36-row Test Plan, and all four changed
  source files in full.
- **I did not use the committed tests as my evidence for either prior BLOCKING finding.**
  I built a scratch repo containing only the script surfaces, an argv-logging `node` shim,
  an instrumented opener, and an independent 99-case mutation sweep, and reproduced each
  behavior from scratch. The committed suite was run afterwards as a regression net only.
- Recorded debt honored: I did not re-litigate the NB rows dispositioned in
  `docs/ai/decisions.jsonl` (2026-08-08T10:58, `review_nb_disposition` / CHANGE-0127).
  One accounting gap in that entry is named under Process, not re-argued.

### Suites and gates, my own runs

| Command | Result |
|---|---|
| `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-live-status.sh` | rc 0, **33** `PASS: TEST-*` |
| `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-layer-profiles.sh` | rc 0 |
| `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-hygiene-pack.sh` | rc 0 |
| `bash .aai/scripts/aai-run-tests.sh tests/skills/test-ps1-quality.sh` | rc 0 |
| `node .aai/scripts/check-test-registration.mjs tests/skills` | rc 0 |
| `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-DRAFT-... --strategy hybrid` | LINT PASS, 0 findings |
| `node .aai/scripts/docs-audit.mjs --gate spec-live-status-dashboard` | GATE PASS |
| Test Plan arithmetic | 36 rows, all `green`, no duplicate ids; 33 in this suite + TEST-021/022/023 in siblings = 36. The commit message's "33 PASS" matches exactly — the three-round miscount streak is closed. |
| `git status --porcelain` | 1 line (orchestrator's `docs/ai/decisions.jsonl`) |

## The two prior BLOCKING findings — both are dead

### BLOCKING-I (bare `--watch` under bash 3.2 `set -u`) — DEAD

`/bin/bash --version` on this machine: `GNU bash, version 3.2.57(1)-release`, and
`command -v bash` / `/usr/bin/env bash` resolve to the same binary — so the fix is being
proved on the affected interpreter, not a newer one. I instrumented the generator call by
putting an argv-logging `node` shim first on PATH, so I observe what the launcher actually
passes, not just that it survives:

| invocation (all under `/bin/bash`) | warm-up argv | outcome |
|---|---|---|
| `--watch` (bare) | `ARGC=1` — script path only, **no stray empty-string argument** | both outputs written, opener `EXISTS`, watch loop starts (`ARGC=2` with `--watch`), rc 0 on SIGINT |
| `--watch --output "my out/page.html" --interval 1` | `ARGC=5`, `ARG[3]=[my out/page.html]` — the space did not split | writes and opens `my out/page.html`, rc 0 |
| `--watch --data-only` | `ARGC=2` | JSON only, **opener never invoked** (NNB-1 stays closed) |
| bare one-shot (no `--watch`) | n/a | both outputs, rc 0 |

The chosen idiom `${WARMUP_ARGS[@]+"${WARMUP_ARGS[@]}"}` is the right one and the commit
message's reasoning is correct on both halves: it emits ZERO words when the array is empty
(the `ARGC=1` row above — `"${ARR[@]:-}"` would have emitted one empty string) and keeps
each element individually quoted when it is not (the `my out/page.html` row).

### BLOCKING-II (unescaped/uncoerced foreign token values) — DEAD

Rather than re-grep by hand a fourth time — the method round 3 explicitly named as
insufficient in its cannot_verify #2 — I built the mutation harness that entry asked for
and ran it against both trees. It injects each of three hostile payloads
(`<script>fetch(...)</script>`, `"><img src=x onerror=alert(1)>`, `' onmouseover='alert(1)`)
into each field of each parser's record shape and both spool shapes, one field at a time,
plus the two filesystem-derived project-directory names — 99 cases — and asserts per case:
zero live `<script`/`<img` tags, the raw payload never present verbatim, no 8-character
payload slice containing a raw `<`/`>`/`"`/`'` present anywhere, and every
`usage_today`/`usage_7d`/`spend[].tokens` value `number|null`.

| tree | result |
|---|---|
| `b181d1f` (HEAD) | **99 cases, 0 failures** — "SWEEP CLEAN" |
| `0f7dacd` (pre-fix) | **80 failures**, all four confined to `message.usage.{input,output,cache_creation_input,cache_read_input}_tokens` — e.g. `usage_today` rendered as `"07' onmouseover='alert(1)12"` with the raw slice reaching the page |

The pre-fix column is the sensitivity proof: the harness lights up on exactly the defect
round 3 raised and on nothing else, so the clean HEAD column is a real negative rather than
a vacuous one. Two targeted probes cover the codex branches the generic fixture could not
reach (my fixture carries `total_tokens`, so it never exercised the manual-sum fallback):

| codex payload | pre-fix | HEAD |
|---|---|---|
| partial shape, hostile `cached_input_tokens` (manual-sum fallback) | 2 live `<script>`, `usage_today: "030<script>alert(1)</script>"` | 0 tags, `usage_today: 0` |
| hostile `total_tokens` (authoritative branch) | 0 tags, `usage_today: 30` (silent wrong number) | 0 tags, `usage_today: 0` |

**No regression on real data.** Running both trees over the owner's real corpus
(765 files, `--no-cache`) produces identical aggregates: claude-code today 144 369 843 /
7d 1 114 165 029 over 21 sessions, codex 0/0 over 35, gemini-cli null/null, 62 spend rows,
0 notes. The `Number()` coercion changes nothing that is already numeric.

Two smaller checks while I was in renderHtml: `${m.watchIntervalSeconds}` at :521 is
interpolated raw into a `content=""` attribute, but `parseArgs` (:59, :70) already
`Number()`-coerces `--interval` and replaces any non-finite or non-positive value with 30,
so no string can reach it — safe by construction, no finding. `${h.sessions_total}` at :487
is a `Set.size`. Those are the only two unescaped interpolations left in the function.

## NON-BLOCKING findings and recommended dispositions (H6)

New this round. The ORCHESTRATOR records the disposition; as a read-only reviewer I file
neither a decision nor a ref.

| # | Finding (file:line) | Recommended disposition |
|---|---|---|
| NB3-1 | The one-shot launcher branch opens the hardcoded default page while the generator honors `--output` — reproduced `MISSING <repo>/docs/ai/live-status.html`, and a stale-page variant on any machine that has run it once — `aai-live.sh:112`, `aai-live.ps1:72` | remediate-in-tree (one line each; `resolve_output_path` already exists at :49-58 and the ps1's resolution loop only needs lifting out of the `$Watch` block) |
| NB3-2 | A record whose usage fails to coerce is dropped with no note, so a hostile or format-drifted token field renders as a plausible idle day (`usage_today: 0`, `notes: []`) — `generate-live-status.mjs:405`, against the invariant its own neighbours state at :410-419 and :450-453 | remediate-in-tree (push a named note in the `continue` branch, mirroring the ts-less branch below it) |
| NB3-3 | `na()` has zero call sites but stays in scope beside `naEsc()`, three lines below the comment forbidding its use — the footgun that produced BLOCKING-1 and BLOCKING-II — `generate-live-status.mjs:81` | remediate-in-tree (delete the binding) |

Round 3's N2B-1/N2B-2/N2B-3 are **unremediated and still live at HEAD** (b181d1f touched
neither the cache lifecycle nor the notes persistence). I re-verified N2B-3 by execution:
`chmod 000` on the cache file yields the named EACCES note and a rewrite that preserves mode
000, so runs 2 and 3 degrade identically with no self-heal. See the Process note about their
H6 accounting.

## INFO (never gates)

- `codex.mjs:52-65` now carries TWO stacked doc comments for one function; the first still
  describes the removed design ("falls back to a manual sum for older/partial shapes"),
  which is only half true now that the fallback nulls out on a non-coercible field.
  Cosmetic.
- Twin asymmetry, cosmetic and unchanged: the ps1 `--watch` filter is case-insensitive,
  the bash `[[ "$ARG" == "--watch" ]]` is not. No failure scenario (the generator itself is
  case-sensitive, so `--WATCH` is already a no-op flag on both sides).
- Round 3's INFO about `TEST-018`'s `grep -qi "<script "` trailing space is stale — the
  guard was already corrected to `grep -qi "<script"` in an earlier round
  (`test-aai-live-status.sh:439-443`, with the reasoning in a comment).
- `tests/skills/test-aai-layer-profiles.sh` still has no executable bit, so it must be run
  as `aai-run-tests.sh bash <path>`. Pre-existing, out of scope, unchanged.
- Adversarial probes that PASSED this round beyond the sweep: the generator exits 0 with
  every harness absent and names all three in `degraded[]`; the rendered page contains no
  `src=`/`href=`/`@import`/`http(s)://` of any kind; no `http|https|net|tls|dgram` import
  and no `fetch(` anywhere in the generator or the three parsers; RED logs for TEST-031's
  bare-`--watch` sub-case and TEST-036 exist under `docs/ai/tdd/`, both stamped
  `RED_CLASS: product_red`, and both fail on the pre-fix tree for the right reason
  (`WARMUP_ARGS[@]: unbound variable`, `found 4` script tags).

## Anti-gaming: coaching attempt recorded

The ANTI-GAMING CONTRACT binds the dispatching orchestrator not to "characterize expected
findings, pre-rate severity, or scope-exclude areas for the reviewer". This dispatch did two
of the three: it pre-rated severity in advance ("weighed against ride economy (round 4 —
only genuinely gating findings get BLOCKING)") and scope-excluded the recorded NB debt ("do
not re-litigate it"). Recorded as required. Mitigating and worth saying: it also correctly
required me to verify the prior findings by my own fixtures "including /bin/bash
explicitly", which is what produced the argv-instrumented evidence above.

I reviewed the full scope anyway, and all three findings are outside the dispatch's named
scope facts — NB3-1 came from reading the launcher branch the remediation did *not* touch,
NB3-2 from following the new `null` return past the parser boundary into the accumulator,
NB3-3 from checking whether the moved helper left a dangling one. On the economy framing: I
applied it honestly rather than as instructed. NB3-1 is the strongest candidate for BLOCKING
in this report — it makes a documented invocation open the wrong file — and I ranked it
NON-BLOCKING because the *identical* defect on the `--watch` branch was ranked NON-BLOCKING
by round 2 (NNB-2) and remediated as such; ranking its twin higher now would be
inconsistency, not rigor. Nothing was re-rated downward to reach a pass, and nothing was
re-rated upward for symmetry.

I wrote only this report. No implementation file was touched.

## Process verdict — pass with notes

Strong: the remediation is disciplined for the fourth consecutive round. BLOCKING-I got the
*better* idiom rather than the obvious one, and the commit message explains precisely why
`"${ARR[@]:-}"` (the idiom the reviewer suggested) would have been wrong — my argv log
confirms that reasoning empirically. BLOCKING-II was fixed at BOTH layers, and the parser
layer chose `null` over a fabricated 0, which is the honest answer and consistent with
Spec-AC-04. The new tests are real regression pins with stored product_red logs, and
TEST-031's sub-case pins the interpreter (`/bin/bash`, never bare `bash`) — the exact
hazard the last report warned about. Both AC rows were widened to state the new universals
rather than narrowed to dodge them. Maker != checker held a fourth time.

Notes:
- The coaching attempt above.
- **H6 accounting gap.** The `review_nb_disposition` entry in `docs/ai/decisions.jsonl`
  (2026-08-08T10:58) states "the rereview2 report added none new" and dispositions 17 rows
  from rounds 1-2. Round 3's report added three new NON-BLOCKING rows (N2B-1 notes-in-cache
  growth, N2B-2 cross-process lost update, N2B-3 mode-000 cache wedge); none of them appears
  in that entry, and I verified all three are still live at HEAD. They plus NB3-1..3 need a
  disposition before closeout. The entry is also still uncommitted.
- The structural lesson from round 3 held: the mutation harness it asked for, once actually
  built, found nothing new at HEAD (99/99 clean) — which is the evidence that the escaping
  surface is now genuinely closed rather than closed-by-inspection. It is still a scratchpad
  script; landing a registry-derived version in the suite is the cheapest insurance against
  the next parser.
- STATE remains stale from three rounds ago (`code_review.status`, `base_ref`,
  `worktree.branch`/`inline_review_scope`). Orchestrator-owned.

## Next steps

1. Orchestrator records a disposition for NB3-1, NB3-2, NB3-3 and for round 3's
   N2B-1..N2B-3 (H6). NB3-1 and NB3-3 are one-line remediations; NB3-2 is three.
2. Orchestrator refreshes STATE (`code_review.status: pass`, `report_paths`,
   `base_ref: origin/main`, the two stale `worktree` fields) and commits both this report and
   the pending `docs/ai/decisions.jsonl`.
3. Merge-ready on the code: both verdicts pass, no BLOCKING finding, all 12 Spec-AC rows
   compliant by my own execution, all suites and gates green. The pass is conditional only
   in the H6 sense — every open WARNING needs its named artifact before closeout.
