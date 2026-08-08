---
id: spec-live-status-dashboard
type: spec
number: null
status: implementing
ceremony_level: 2
links:
  requirement: live-status-dashboard
  rfc: null
  pr: []
  commits: []
---

# Implementation Spec — Optional zero-token live-status dashboard

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0127-live-status-dashboard.md
- Analysis (landscape, mechanisms, non-goals): docs/analysis/blume-and-alternatives.md
- Decision records: none
- Technology contract: docs/TECHNOLOGY.md
- Sibling generators (reuse the shape, do not fork the code):
  .aai/scripts/generate-factory-report.mjs, .aai/scripts/generate-overview.mjs
- Governance surfaces this scope must feed: .aai/system/PROFILES.yaml,
  .aai/system/RUNTIME_IGNORE.list, .aai/system/DOCS_AI_CANON.list,
  tests/skills/suite-map.yaml
- Opt-in hook overlay precedent: .aai/templates/hooks/settings-hooks.json,
  tests/skills/test-aai-hooks-overlay.sh

## Summary

A fourth, strictly OPTIONAL generator that answers what the existing three
cannot: what is running NOW, what it has cost TODAY, and how much official
plan-quota headroom is left — with zero LLM tokens, zero network calls and
Node stdlib only. `generate-dashboard.mjs` reports per-ride telemetry,
`generate-factory-report.mjs` reports time-series efficiency,
`generate-overview.mjs` reports what shipped; none of them reads a harness
session file, and none of them knows a session exists until a ride is flushed.

The data comes from three local, already-on-disk sources, all read-only:

1. Harness session transcripts, through a PER-HARNESS PARSER REGISTRY — one
   module per harness normalizing its on-disk format into one record shape.
   Adding a harness = adding one module + one registry row + tests, and
   nothing else in the generator changes.
2. An optional statusline-tap spool carrying the harness's own
   server-authoritative quota payload (no limit guessing, no OAuth polling).
3. An optional hooks spool (Stop/Notification) for liveness; absent, liveness
   falls back to an mtime heuristic that is LABELLED a heuristic.

Ground truth verified on the owner's machine at planning time (2026-08-08),
and the parser contract below is written against these observed shapes:

- Claude Code — `~/.claude/projects/<slug>/<session>.jsonl`, 485 MB over 8
  project dirs. `type: assistant` lines carry `requestId`, `message.id`,
  `message.model`, `message.usage.{input_tokens, output_tokens,
  cache_creation_input_tokens, cache_read_input_tokens}`, plus `cwd`,
  `sessionId`, `gitBranch`, `timestamp`. Usage is PER MESSAGE, and the same
  message can appear more than once — the ccusage dedup key
  `message.id` + `requestId` is required or totals inflate.
- Codex — `~/.codex/sessions/<YYYY>/<MM>/<DD>/rollout-<ts>-<uuid>.jsonl`, plus
  `~/.codex/session_index.jsonl` (`id`, `thread_name`, `updated_at`).
  `type: session_meta` carries `payload.session_id` and `payload.cwd`;
  `type: event_msg` with `payload.type: token_count` carries
  `payload.info.total_token_usage` (CUMULATIVE per session, not per turn) and
  `payload.rate_limits.primary.{used_percent, window_minutes, resets_at}` —
  server-authoritative quota, free of any tap.
- Gemini CLI — `~/.gemini/tmp/<project>/logs.json`, a JSON array of
  `{sessionId, messageId, type, message, timestamp}`. NO usage fields exist.
  Gemini therefore renders sessions and liveness only, with usage `N/A`.

Because the two accumulation semantics differ (Claude Code sums deduplicated
per-message usage; Codex must take the LAST cumulative total per session or it
multiplies its own spend), the accumulation MODE is part of the parser
contract, not an implementation detail.

## Ceremony level (RFC-0009)

`ceremony_level: 2` — declared here, one level ABOVE the `ceremony_level: 1`
carried by the intake frontmatter. The upgrade is deliberate and is Planning's
call at freeze (WORKFLOW.md "Ceremony levels"; review may re-classify upward,
never silently downward). The intake level does not survive contact with the
delivered surface: this is not a single-surface fix but a new subsystem —
one generator, three parser modules, two spool-writer twins, two launcher
twins, one hook overlay template, one new test suite, and four governance
files. At level 1 the validation gate weakens to "suite re-run plus targeted
probe"; a new file-format parser whose honesty claims (dedup, N/A, degraded
SKIP) are the whole product deserves full independent validation. Level 3 is
NOT claimed: no path in `protected_paths_l3` (docs/ai/docs-audit.yaml) is
touched — no state engine, no allocator, no pre-commit guard, no workflow
canon.

Ceremony justification: not required at level 2; this section records the
assessment so the intake-vs-spec level difference is auditable rather than
looking like drift. The operator may reset the level to 1 explicitly.

## Frontmatter status values
- draft: spec being written / frozen-ready, implementation not yet started
- implementing: spec frozen, work in flight
- done: all Spec-AC terminal; validation PASS recorded

## Implementation strategy
- Strategy: hybrid
- Rationale: the parts that are easy to get subtly and silently WRONG earn
  RED-GREEN-REFACTOR — the two dedup/accumulation modes (a wrong key inflates
  or divides spend and nobody notices), the incremental mtime cutoff (a wrong
  cutoff silently drops a day), and every degradation path (an absent spool
  must produce a NAMED skip, never a plausible-looking zero). The HTML render,
  the launchers, the hook overlay template, the product doc and the four
  governance rows are low-risk mechanical wiring where one focused loop pass
  is sufficient. STATE carries no intake-sourced choice for this scope: the
  `implementation_strategy.selected: direct / source: intake` present at
  planning time belongs to the earlier `core-prompt-diet` ride (its rationale
  reads "docs-only knowledge entry") and is not a recorded choice about
  CHANGE-0127.

Allowed strategy values: loop | tdd | hybrid | direct | untested | undecided
(see .aai/templates/SPEC_TEMPLATE.md).

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: a PR-bound feature spanning eight-plus new files across
  four independent surfaces (generator + parsers, shell/PowerShell twins,
  governance lists, docs), with a long implementation arc; isolation keeps the
  governance-list edits from destabilizing the working tree mid-flight. NOT
  `required`: no `protected_paths_l3` surface is touched. The scope is already
  on the dedicated branch `feat/live-status-dashboard`, so `inline` on that
  branch is a fully reasonable operator answer.
- User decision: undecided
- Base ref: feat/live-status-dashboard
- Worktree branch/path: to be decided by Implementation Preparation
- Inline review scope: if inline is chosen —
  .aai/scripts/generate-live-status.mjs, .aai/scripts/live-parsers/,
  .aai/scripts/live-spool.sh, .aai/scripts/live-spool.ps1,
  .aai/scripts/aai-live.sh, .aai/scripts/aai-live.ps1,
  .aai/templates/hooks/live-status-hooks.json,
  tests/skills/test-aai-live-status.sh, tests/skills/suite-map.yaml,
  .aai/system/PROFILES.yaml, .aai/system/RUNTIME_IGNORE.list,
  .aai/system/DOCS_AI_CANON.list, .gitignore,
  docs/product/live-status-dashboard.md, docs/USER_GUIDE.md,
  docs/specs/SPEC-DRAFT-spec-live-status-dashboard.md,
  docs/issues/CHANGE-0127-live-status-dashboard.md, CHANGELOG.md

## Acceptance Criteria Mapping

- Intake AC-001 -> Spec-AC-01 (generator, model, zero-network, non-fatal
  degradation), Spec-AC-02 (registry contract and accumulation modes),
  Spec-AC-03 (incremental cutoff), Spec-AC-11 (runtime-sidecar class)
- Intake AC-002 -> Spec-AC-06 (official quotas from tap spool and from
  in-session rate limits, named SKIP when absent)
- Intake AC-003 -> Spec-AC-07 (liveness from hooks spool, labelled heuristic
  fallback)
- Intake AC-004 -> Spec-AC-08 (opt-in only, negative control, product doc with
  install and uninstall)
- Intake AC-005 -> Spec-AC-05 (cross-platform discovery and helper twins)
- Intake AC-006 -> Spec-AC-04 (three shipped parsers, honest N/A)
- Intake AC-007 -> Spec-AC-09 (invocation modes), Spec-AC-10 (page layout and
  SKIP section)
- Companion obligation (.aai/PLANNING.prompt.md) -> Spec-AC-12 (PROFILES
  classification for every new .aai file, suite-map row for the new suite)

## Constitution deviations

None.

Article check at freeze (docs/CONSTITUTION.md v1): 1 Evidence before claims —
every Spec-AC below names one command and one observable, and each has at
least one TEST-xxx row. 2 Simplicity — one generator plus one module per
harness; no dependency, no server, no port, no daemon, no database; the three
explicit non-goals from the intake (config drift, LLM suggestions, OAuth
polling) stay out. 3 Portability — plain `.mjs` / `.sh` / `.ps1` / `.md`, Node
stdlib only, discovery through `os.homedir()` so the same code runs on
Windows. 4 Degrade and report — Spec-AC-01, Spec-AC-06, Spec-AC-07 and
Spec-AC-10 make "name the missing source, never fabricate the number" a
tested behavior rather than a promise. 5 Additive first — every file is new;
the four governance lists take additive rows; no existing script changes
behavior, and nothing in the ride path calls the generator (Spec-AC-08). 6
Single-writer state — the generator never reads or writes docs/ai/STATE.yaml.
7 Operator-only merge — Planning opens no PR and never merges.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN generate-live-status.mjs runs the system SHALL write docs/ai/live-status-data.json and docs/ai/live-status.html from one model using Node stdlib only with no network import and no outbound socket and SHALL exit 0 even when every harness directory is absent naming each absent harness in a machine-readable degraded array | done | TEST-001,002,003 green; docs/ai/tdd/green-20260808T085117Z.log | — | |
| Spec-AC-02 | The system SHALL resolve harnesses through a registry where each entry declares id discover parse and accumulation mode and SHALL apply mode event_sum_dedup for Claude Code keyed on message.id plus requestId and mode session_cumulative_last for Codex so that a duplicated Claude Code assistant line counts once and a Codex session with three token_count events reports its last cumulative total not their sum | done | TEST-004,005,006 green; docs/ai/tdd/red-20260808T085117Z-test_004_claude_code_dedup.log, red-...test_005_codex_cumulative_last.log (product_red), green-20260808T085117Z.log | — | |
| Spec-AC-03 | WHEN the generator runs a second time over an unchanged corpus it SHALL re-read zero session files reporting scan.files_skipped_unchanged equal to the corpus file count and SHALL produce aggregates byte-identical to the cold run and WHEN one session file gains a line it SHALL re-read exactly that file | done | TEST-007,008 green; docs/ai/tdd/red-20260808T085117Z-test_007_incremental_cutoff_unchanged.log, red-...test_008_incremental_cutoff_appended.log (product_red), green-20260808T085117Z.log | — | |
| Spec-AC-04 | The registry SHALL ship parsers for Claude Code and Codex and Gemini CLI and a harness whose records carry no usage fields SHALL render sessions and liveness with the usage value null and the rendered cell reading N/A and SHALL NEVER render a zero or an estimate in place of a missing usage figure | done | TEST-009,010 green; docs/ai/tdd/red-20260808T085117Z-test_009_gemini_usage_na.log (product_red), green-20260808T085117Z.log | — | |
| Spec-AC-05 | Every harness directory and spool path SHALL be built with os.homedir or an env override joined by path.join with no hardcoded forward-slash home string anywhere in the generator or parsers and the tap and launcher helpers SHALL ship as bash and PowerShell twins that both parse cleanly and each degradation message SHALL name the expected location for the running OS | done | TEST-020 green (test-aai-live-status.sh); TEST-023 green (test-ps1-quality.sh, live-spool.ps1 + aai-live.ps1 parse clean, 0 PSScriptAnalyzer errors) | — | |
| Spec-AC-06 | WHEN the statusline tap spool exists the quotas section SHALL render five_hour and seven_day used percentage and resets_at read from the spooled payload and WHEN a harness session file carries its own server-authoritative rate limits the section SHALL render them attributed to that harness and WHEN neither source exists the section SHALL render a SKIP naming the absent source and its install command and SHALL NOT render any estimated limit and the tap SHALL spool only whitelisted fields never message or transcript content | done | TEST-011,012,013,014 green; docs/ai/tdd/red-...test_011/012/014...log (product_red), green-20260808T085117Z.log | — | RR-1 (unverified real statusline payload shape) stands per spec |
| Spec-AC-07 | WHEN the hooks spool carries Stop or Notification lines for a session the state badge SHALL read finished or waiting-on-approval accordingly and WHEN no spool line exists for a session the badge SHALL derive from the transcript mtime window and SHALL carry the literal word heuristic | done | TEST-015 green; docs/ai/tdd/red-20260808T085117Z-test_015_liveness_hooks_and_heuristic.log (product_red), green-20260808T085117Z.log | — | |
| Spec-AC-08 | No ride path SHALL invoke the generator so that close-work-item.mjs and autonomous-loop.sh and hooks/session-start.sh and every file under .github/workflows contain no reference to generate-live-status and the product doc SHALL document install and uninstall for both the statusline tap and the liveness hooks | done | TEST-016,017 green; docs/ai/tdd/green-20260808T085117Z.log | — | |
| Spec-AC-09 | The generator SHALL support one-shot mode printing the output path and exiting 0 and a watch mode with a configurable interval that rewrites the outputs at least twice within four intervals and exits 0 on SIGINT leaving no child process and the launcher twins SHALL generate then open the page via the platform opener | done | TEST-024,025,027 green; docs/ai/tdd/green-20260808T085117Z.log | — | |
| Spec-AC-10 | The rendered page SHALL be one self-contained file with inline CSS and no external or network reference carrying a harness availability chip row and a quotas section and a live-sessions section with state badges and a spend today and 7d breakdown per project and per harness and a SKIP section listing every degraded source with its reason and its meta refresh interval SHALL equal the watch interval in seconds | done | TEST-018,026 green; docs/ai/tdd/green-20260808T085117Z.log | — | |
| Spec-AC-11 | The two output files and the spool directory SHALL be runtime sidecars so that after a generator run in a clean checkout git status --porcelain reports no untracked or modified path under docs/ai and docs-audit reports no docs/ai non-canonical entry for them | done | TEST-019 green; docs/ai/tdd/green-20260808T085117Z.log; .gitignore + RUNTIME_IGNORE.list + DOCS_AI_CANON.list updated | — | |
| Spec-AC-12 | Every new file under .aai SHALL appear exactly once across the PROFILES.yaml core and extended lists and the new test suite SHALL have exactly one suites row in tests/skills/suite-map.yaml | done | TEST-021 green (test-aai-layer-profiles.sh); TEST-022 green (test-aai-hygiene-pack.sh) | — | |

Status values: planned | implementing | done | deferred | blocked | rejected

## Parser contract (the registry row)

One module per harness under `.aai/scripts/live-parsers/`, each default-
exporting one object. The generator knows nothing else about any harness.

- `id` — stable short id (`claude-code`, `codex`, `gemini-cli`), used as the
  chip label, the JSON key and the per-harness dedup namespace.
- `roots(env)` — array of candidate directories, ALWAYS built from
  `os.homedir()` (plus the harness's own env override, e.g.
  `CLAUDE_CONFIG_DIR`) with `path.join`. Returning an existing-but-empty root
  is `PRESENT`; returning only non-existent roots is `ABSENT` and is reported,
  never thrown.
- `discover(roots)` — session file descriptors `{path, mtimeMs, size}`.
- `parse(file, ctx)` — yields normalized records
  `{harness, sessionId, project, ts, model, usage|null, dedupKey|null,
  state|null}`. `usage: null` means "this format has no usage data" and must
  survive to the render as `N/A` (Spec-AC-04).
- `accumulation` — one of:
  - `event_sum_dedup`: sum per record, skipping any record whose `dedupKey`
    was already seen (Claude Code: `message.id` + `requestId`).
  - `session_cumulative_last`: per session take the LAST record's totals
    (Codex `payload.info.total_token_usage`); summing them would multiply the
    session's real spend by the number of `token_count` events.
  - `none`: the format carries no usage (Gemini CLI).
- `rateLimits(records)` — optional; returns server-authoritative quota when the
  format carries it (Codex `payload.rate_limits.primary`), else null.
- `project(record)` — the human project label (Claude Code: `cwd` basename;
  Codex: `payload.cwd` basename; Gemini CLI: the `~/.gemini/tmp/<project>`
  directory name).

A malformed line is skipped and counted in `notes`, never fatal; a malformed
FILE is skipped and named. Every parser is pure over its inputs plus a clock
injected as `--now` so tests are deterministic.

## Implementation plan

- `.aai/scripts/generate-live-status.mjs` — new. Mirrors
  `generate-factory-report.mjs`: `parseArgs` (`--output`, `--data-only`,
  `--watch`, `--interval <s>`, `--now <iso>`, `--home <dir>` for fixtures,
  `--no-cache`), `buildModel()` returning ONE model, `renderHtml(model)`
  inline, `main()` writing `docs/ai/live-status-data.json` always and
  `docs/ai/live-status.html` unless `--data-only`.
- `.aai/scripts/live-parsers/{registry,claude-code,codex,gemini-cli}.mjs` —
  deliberately NOT under `.aai/scripts/lib/`: `lib/**` is a
  `full_run_triggers.shared_lib_globs` entry in tests/skills/suite-map.yaml,
  and these modules have exactly one consumer, so classifying them as
  unbounded-fan-out shared library code would escalate every parser edit to a
  FULL_RUN for no safety gain. Their own suite-map globs give precise
  selection instead.
- `.aai/scripts/live-spool.sh` + `.ps1` — the tap/hook writer twins. Read JSON
  on stdin, project a WHITELIST of fields (`session_id`, `cwd`, `model`,
  `rate_limits`, `cost`, `hook_event_name`, plus the writer's own timestamp),
  append one line to `docs/ai/live/<statusline|hooks>.jsonl`, cap the file by
  line count, and ALWAYS exit 0 — a statusline that fails must never disturb
  the harness. The repo root is resolved from the script's own location, so
  the caller's cwd is irrelevant; `AAI_LIVE_SPOOL_DIR` overrides.
- `.aai/scripts/aai-live.sh` + `.ps1` — generate, then open via
  `open` / `xdg-open` / `start`; pass through `--watch`.
- `.aai/templates/hooks/live-status-hooks.json` — OPT-IN overlay in the shape
  of `.aai/templates/hooks/settings-hooks.json`, wiring `statusLine` plus the
  `Stop` and `Notification` hooks to `live-spool`. Nothing installs it
  automatically; the product doc carries install and uninstall.
- Incremental cache: `.aai/cache/live-status-index.json` (already gitignored),
  keyed `path -> {mtimeMs, size, aggregates}`; a file whose mtime and size are
  unchanged is not reopened. `--no-cache` forces a cold scan.
- Governance rows: PROFILES.yaml `extended` (reporting class) for every new
  `.aai` file; suite-map `suites.aai-live-status`; RUNTIME_IGNORE.list plus
  `.gitignore` for `docs/ai/live-status.html`,
  `docs/ai/live-status-data.json`, `docs/ai/live/**`; DOCS_AI_CANON.list for
  the two file names and the `live` directory.
- `docs/product/live-status-dashboard.md` (capability slug
  `live-status-dashboard`, matching the intake `id` the close gate keys on),
  which the existing `generate-userguide-rollup.mjs` rolls into
  docs/USER_GUIDE.md.
- Data flow: harness session files + optional spools -> registry parse ->
  one model -> {live-status-data.json, live-status.html}. Read-only over every
  input; writes only the two outputs and the cache.
- Edge cases: absent harness dir (ABSENT chip, not fatal); present-but-empty
  dir (PRESENT, zero sessions); malformed JSONL line (skip + note); duplicated
  Claude Code assistant line (dedup); Codex session with many `token_count`
  events (last cumulative wins); Gemini record with no usage (N/A, never 0);
  absent tap spool (SKIP with install hint); absent hooks spool (mtime
  heuristic, labelled); clock crossing a UTC day boundary mid-scan (all
  bucketing uses the single injected `--now`); a session file being appended
  to while it is read (partial last line skipped, counted).

## Seam analysis

Every crossing below is tested by producing on one side and asserting the real
result on the other — no mocked boundaries.

- SEAM 1 — spool writer to generator. The quota and liveness tests do NOT
  hand-write a spool fixture: they pipe a payload through the real
  `live-spool.sh` and then assert the generator's rendered output. A field the
  writer drops and the parser expects is exactly the defect this catches
  (TEST-011, TEST-014).
- SEAM 2 — generator output to git and docs-audit. The generator writes into
  `docs/ai/`, a tree governed by `.gitignore`, `RUNTIME_IGNORE.list` and
  `DOCS_AI_CANON.list`. TEST-019 runs the generator and then runs
  `git status --porcelain` and `docs-audit.mjs` over the result: three lists
  agreeing is the only thing that keeps a 100-run-per-day sidecar out of the
  history.
- SEAM 3 — one model, two renderers. TEST-018 asserts every KPI rendered in
  the HTML equals the same field in the data JSON, so the page cannot drift
  from the machine-readable file.
- SEAM 4 — new `.aai` files to the PROFILES union pin and the new suite to the
  suite-map hygiene pin (TEST-021, TEST-022). Both are existing suites that
  fail on an unclassified file; they are in scope because this change creates
  the files that would fail them.
- SEAM 5 — opt-in negative control. TEST-016 greps the four ride/CI surfaces
  for `generate-live-status` and asserts zero hits. The claim "never coupled
  to ride ceremony" is otherwise unfalsifiable prose.
- RESIDUAL RISK RR-1 — the Claude Code statusline stdin payload is documented
  by the harness, not by this repo, and was NOT observed live at planning time
  (no `statusLine` is configured on the owner's machine). Tests drive the tap
  with a synthetic payload shaped like the documented one. If the real
  payload's quota field names differ, the quotas section degrades to its
  tested SKIP path rather than lying — first live install is the verification,
  and the product doc must say so.
- RESIDUAL RISK RR-2 — real Windows execution is not exercised by this repo's
  CI (macOS/Linux only, docs/TECHNOLOGY.md). The twins get parse-level and
  PSScriptAnalyzer coverage plus path-construction assertions; end-to-end
  Windows behavior stays a manual check, same posture as SPEC-0046 RR-1.
- RESIDUAL RISK RR-3 — harness on-disk formats are undocumented and drift
  between versions. The registry localizes the blast radius to one module, and
  every parser degrades to ABSENT or to a named note; no automated test can
  pin an upstream format.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Status |
|---------|---------|------|----------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | unit | tests/skills/test-aai-live-status.sh | a run against a fixture home writes both output files and exits 0 | green |
| TEST-002 | Spec-AC-01 | unit | tests/skills/test-aai-live-status.sh | a run against a home with no harness directory at all exits 0 and lists all three harnesses as ABSENT in the degraded array | green |
| TEST-003 | Spec-AC-01 | unit | tests/skills/test-aai-live-status.sh | the generator and parser sources import only node builtin modules and contain no http or https or fetch or net call | green |
| TEST-004 | Spec-AC-02 | unit | tests/skills/test-aai-live-status.sh | a Claude Code fixture containing the same assistant line twice counts its usage exactly once | green |
| TEST-005 | Spec-AC-02 | unit | tests/skills/test-aai-live-status.sh | a Codex fixture with three token_count events reports the last cumulative total and not their sum | green |
| TEST-006 | Spec-AC-02 | unit | tests/skills/test-aai-live-status.sh | a registry entry missing a required contract field is refused with a named error instead of producing partial totals | green |
| TEST-007 | Spec-AC-03 | integration | tests/skills/test-aai-live-status.sh | a second run over an unchanged corpus skips every session file and yields aggregates byte-identical to the cold run | green |
| TEST-008 | Spec-AC-03 | integration | tests/skills/test-aai-live-status.sh | appending one line to one session file re-reads exactly that file and updates only its totals | green |
| TEST-009 | Spec-AC-04 | unit | tests/skills/test-aai-live-status.sh | a Gemini CLI logs.json fixture yields sessions with usage null and the rendered cell reads N/A with no zero and no estimate anywhere | green |
| TEST-010 | Spec-AC-04 | unit | tests/skills/test-aai-live-status.sh | all three parsers are reachable through the registry and each reports its own root and availability | green |
| TEST-011 | Spec-AC-06 | integration | tests/skills/test-aai-live-status.sh | SEAM 1 a statusline payload piped through live-spool.sh renders as five_hour and seven_day used percentage and resets_at in the generated page | green |
| TEST-012 | Spec-AC-06 | unit | tests/skills/test-aai-live-status.sh | with no tap spool the quotas section renders a SKIP naming the absent spool and its install command and the page contains no percentage figure | green |
| TEST-013 | Spec-AC-06 | unit | tests/skills/test-aai-live-status.sh | a Codex fixture carrying rate limits renders them attributed to the codex harness with its window and reset time | green |
| TEST-014 | Spec-AC-06 | integration | tests/skills/test-aai-live-status.sh | SEAM 1 a statusline payload carrying a transcript path and a message field spools neither of them and the whitelist keeps only the declared keys | green |
| TEST-015 | Spec-AC-07 | integration | tests/skills/test-aai-live-status.sh | a Stop line and a Notification line piped through live-spool.sh produce finished and waiting-on-approval badges and a session with no spool line gets an mtime badge carrying the word heuristic | green |
| TEST-016 | Spec-AC-08 | integration | tests/skills/test-aai-live-status.sh | SEAM 5 close-work-item.mjs and autonomous-loop.sh and hooks/session-start.sh and every .github/workflows file contain zero references to generate-live-status | green |
| TEST-017 | Spec-AC-08 | unit | tests/skills/test-aai-live-status.sh | the product doc documents both install and uninstall for the statusline tap and for the liveness hooks and passes the product-doc placeholder predicate | green |
| TEST-018 | Spec-AC-10 | unit | tests/skills/test-aai-live-status.sh | SEAM 3 every KPI rendered in the page equals the same field in the data JSON and the page has no external or network reference | green |
| TEST-019 | Spec-AC-11 | integration | tests/skills/test-aai-live-status.sh | SEAM 2 after a generator run in a fixture checkout git status --porcelain reports nothing under docs/ai and docs-audit reports no non-canonical docs/ai entry | green |
| TEST-020 | Spec-AC-05 | unit | tests/skills/test-aai-live-status.sh | no source file in the generator or parsers contains a hardcoded home path string and every root is built through os.homedir with path.join and an absent-harness message names the per-OS location | green |
| TEST-021 | Spec-AC-12 | integration | tests/skills/test-aai-layer-profiles.sh | every new .aai file is classified exactly once so the union-equals-tree pin stays green | green |
| TEST-022 | Spec-AC-12 | integration | tests/skills/test-aai-hygiene-pack.sh | the new suite has exactly one suites row in suite-map.yaml so the hygiene pin stays green | green |
| TEST-023 | Spec-AC-05 | integration | tests/skills/test-ps1-quality.sh | live-spool.ps1 and aai-live.ps1 parse under the ps1 gate and raise no PSScriptAnalyzer error | green |
| TEST-024 | Spec-AC-09 | unit | tests/skills/test-aai-live-status.sh | one-shot mode prints the output path and exits 0 | green |
| TEST-025 | Spec-AC-09 | integration | tests/skills/test-aai-live-status.sh | watch mode with a one second interval rewrites the outputs at least twice within four seconds and exits 0 on SIGINT leaving no surviving child process | green |
| TEST-026 | Spec-AC-10 | unit | tests/skills/test-aai-live-status.sh | the page meta refresh interval in seconds equals the watch interval and the SKIP section names every degraded source with its reason | green |
| TEST-027 | Spec-AC-09 | unit | tests/skills/test-aai-live-status.sh | aai-live.sh resolves an opener and refuses with a named error instead of hanging when none exists | green |

Test status values: pending -> red -> green.

RED-proof obligation (hybrid strategy): every AC-gating test above must be
observed FAILING on the pre-change tree before its green counts as evidence.
For the TDD-lane tests — TEST-004, TEST-005, TEST-007, TEST-008, TEST-009,
TEST-011, TEST-012, TEST-014, TEST-015 — the RED observation is STORED under
`docs/ai/tdd/` per .aai/SKILL_TDD.prompt.md. For the loop-lane remainder the
RED must be OBSERVED and reported; storage is optional. The three pins
(TEST-021, TEST-022, TEST-023) are RED by construction the moment the new
files exist unclassified — record that observation, do not skip it.

## Verification

- Commands:
  - `bash tests/skills/test-aai-live-status.sh`
  - `bash tests/skills/test-aai-layer-profiles.sh`
  - `bash tests/skills/test-aai-hygiene-pack.sh`
  - `bash tests/skills/test-ps1-quality.sh` (SKIP 42 without pwsh is an
    acceptable recorded outcome; the CI ps1-quality workflow is the backstop)
  - `node .aai/scripts/generate-live-status.mjs` — live smoke on the owner's
    real corpus: exit 0, both files written
  - `node .aai/scripts/docs-audit.mjs --check --strict --no-event --path docs/specs/SPEC-DRAFT-spec-live-status-dashboard.md`
  - `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-DRAFT-spec-live-status-dashboard.md`
- Measured but NOT gated: the wall-clock of the cold live smoke over the
  ~485 MB Claude Code corpus and of the warm incremental re-run, both recorded
  as evidence. A machine-dependent duration is not an acceptance threshold.
- Evidence artifacts: test stdout logs; the generated
  `docs/ai/live-status-data.json` from the live smoke; the stored RED
  artifacts for the TDD-lane tests.
- PASS criteria: all TEST-xxx green AND every Spec-AC in a terminal status.

## Evidence contract

For each implementation, TDD, validation and code review artifact record:
ref_id (`live-status-dashboard`); the Spec-AC and TEST-xxx touched; the command
run or the review scope; the exit code or review verdict; the evidence path;
and the commit SHA or diff range when available.

### Evidence by strategy

Strategy `hybrid`: the TDD-lane tests named above owe a STORED RED artifact
under `docs/ai/tdd/` plus the full verification matrix; the loop-lane tests owe
per-TEST green runs with the RED observed and reported.

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow. Plain
Markdown headings and body text; no emoji or decorative icons.
