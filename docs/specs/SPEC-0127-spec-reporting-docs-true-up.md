---
id: spec-reporting-docs-true-up
type: spec
number: 127
status: implementing
ceremony_level: 1
links:
  requirement: docs/issues/CHANGE-0140-reporting-docs-true-up.md
  rfc: null
  pr: []
  commits: []
---

# Spec — reporting/docs true-up: USER_GUIDE matches the real skill set, dashboard reads real usage, no empty charts

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0140-reporting-docs-true-up.md
- Canonical note grammar this scope IMPORTS (never forks): `.aai/scripts/lib/usage-note.mjs` (SPEC-0089 Spec-AC-01, single-source contract)
- Reference consumer of that grammar: `.aai/scripts/generate-factory-report.mjs` (SPEC-0108 / CHANGE-0130)
- Generator this scope EXTENDS: `.aai/scripts/generate-dashboard.mjs` + `docs/dashboard-template.html`
- Rollup generator whose markers this scope must not violate: `.aai/scripts/generate-userguide-rollup.mjs` (SPEC-0092 D4)
- Prompt whose caveat becomes truthful: `.aai/SKILL_DASHBOARD.prompt.md`
- Prompt-diet companion obligation: tests/skills/lib/prompt-diet-ledger.sh + tests/skills/test-aai-prompt-diet.sh TEST-012 (pin currently -6642)
- Technology contract: docs/TECHNOLOGY.md

Ceremony justification: level 1 (declared by the intake and kept) — the scope
edits one deterministic report generator plus its template, performs a
documentation true-up on docs/USER_GUIDE.md, and rewrites one skill-prompt
caveat; nothing under `protected_paths_l3` (state engine, allocator, guards,
workflow canon) is touched, no exit code or CLI flag changes, and every
acceptance criterion below names a directly executable local command. The one
judgement recorded against the level: the surface count (generator, template,
prompt, USER_GUIDE, two new test suites, suite-map, ledger, product doc) sits
at the top of what level 1 covers; an operator may legitimately raise it to 2 —
Planning does not do that silently.

## Summary

Owner audit 2026-08-13 confirmed three defects, re-derived and sharpened here:

1. **USER_GUIDE drift** — docs/USER_GUIDE.md advertises `/aai-feedback-triage`
   and `/aai-feedback-upsert` as slash skills that do not exist in
   `.claude/skills/`, and never mentions `/aai-factory-report` (shipped
   CHANGE-0130) even though all 36 other vendored skills are mentioned.
2. **Dashboard reads fields the ledger never fills** —
   `normalizeLedgerEntry()` in generate-dashboard.mjs reads only
   `tokens_in`/`tokens_out`, which are null on every real `agent_runs[]`
   entry; real usage lives in the run note as `usage_total_tokens=<N>`
   (69 markers in the live METRICS.jsonl). Result: `summary.totalTokens: 0`
   and an all-zero token chart in docs/ai/dashboard-data.json today.
3. **Empty panels** — `tddStats`, `worktreeStats`, `publishStats` are all
   `null` against the real ledger, and the template renders their sections as
   bare empty canvases instead of a named no-data state.

## Confirmed drift catalogue (planning evidence, re-derived 2026-08-13)

Forward direction — every `aai-`-shaped token in docs/USER_GUIDE.md that does
NOT resolve to a `.claude/skills/<name>` directory, classified:

| Token | USER_GUIDE lines | Class | Disposition |
|---|---|---|---|
| `/aai-feedback-triage` | 2052 | DEAD skill alias (comment `# or /aai-feedback-triage`) | remove alias; the script `.aai/scripts/aai-feedback-triage.mjs` EXISTS and stays documented |
| `/aai-feedback-upsert` | 2060 | DEAD skill alias (comment `# or /aai-feedback-upsert`) | remove alias; the script `.aai/scripts/aai-feedback-upsert.mjs` EXISTS and stays documented |
| `/aai-test-unit` `/aai-test-e2e` `/aai-build` | 221-223, 1906 | LEGITIMATE generated-downstream examples (bootstrap output) | keep; explicit allowlist entries in the drift test |
| `aai-reports-abc123` `aai-reports-xyz` `aai-reports-dashboard` (pages.dev) | 1135, 1179, 1655 | LEGITIMATE illustrative URLs | keep; excluded structurally by the mention anchor (see D2) |
| `aai-run-tests` `aai-sync` `aai-reap-tests` `aai-feedback-status` etc. | 53, 1873-1918, 1937, 2043... | script-PATH mentions (`.aai/scripts/<name>.{sh,ps1,mjs}`) | keep; canonical script-writing convention (D1c); excluded structurally by the anchor |

Reverse direction — vendored skills with no USER_GUIDE mention: exactly ONE of
37, `aai-factory-report` (the generated rollup carries a "Factory performance
report" feature section at lines 2231-2235 but never the `/aai-factory-report`
command). All 36 others are mentioned.

INTAKE CORRECTION (recorded, not silently re-planned): the intake summary
claims "only aai-feedback-status.mjs exists". False — all three of
`aai-feedback-status.mjs`, `aai-feedback-triage.mjs`, `aai-feedback-upsert.mjs`
exist in `.aai/scripts/` and are vendored (`.aai/system/PROFILES.yaml` lines
215-217). Only the SKILL aliases are dead. The AC-001 wording "removed or
rewritten to the surviving reality" is satisfied by the rewrite arm: the
feedback section stays (it documents live scripts correctly) and only the two
false `# or /aai-feedback-*` alias comments are removed.

## Design decisions recorded at planning time (do not re-derive)

### D1 — USER_GUIDE surgery scope

a) **Feedback section (lines ~2023-2095): KEEP + minimal rewrite.** The
   documented script flow is real (see intake correction above). Remove only
   the two dead alias comments `# or /aai-feedback-triage` and
   `# or /aai-feedback-upsert`. No other feedback prose changes.
b) **`/aai-factory-report` gains a hand-authored section** in the
   Monitoring/analysis command area (adjacent to `/aai-dashboard`, ~line
   1166), plus a row in the Monitoring & Analysis command table (~line 191)
   and a Quick-reference entry (~line 1790). Content: what it shows (four KPI
   families — throughput, speed, token cost, quality — overall + per-ISO-week
   trend from METRICS.jsonl + EVENTS.jsonl; auto-refreshes at every work-item
   close) and when to use it vs `/aai-dashboard` (factory-report = trended
   factory-efficiency KPIs; dashboard = per-run operations/token charts). The
   hand section lives OUTSIDE the `AAI:USERGUIDE-ROLLUP` markers (2203/2345);
   nothing inside markers is ever hand-edited.
c) **Script-vs-skill writing convention (canonical):** skills are written as
   slash commands (`/aai-<name>`); scripts are ALWAYS written in path form
   (`node .aai/scripts/<name>.mjs`, `bash .aai/scripts/<name>.sh`,
   `.aai/scripts/<name>.ps1`), never as `/aai-<name>`. The current guide
   already conforms except the two dead aliases; the drift-test anchor (D2)
   encodes this convention.

### D2 — anti-drift test design (both directions, exceptions IN the test)

Forward: extract slash-command mentions with an ANCHORED pattern — a `/aai-`
token whose `/` is preceded by start-of-line, whitespace, backtick, `(` or
`|` (table cell). This structurally excludes script paths
(`.aai/scripts/aai-sync.sh` — `/` preceded by `s`) and URLs
(`https://aai-reports-x.pages.dev` — preceded by `/`), so neither class ever
needs a fuzzy allowlist. Each extracted name must exist as a
`.claude/skills/<name>` directory OR appear in the explicit
`ALLOWED_GENERATED` array declared IN the test (`aai-test-unit`,
`aai-test-e2e`, `aai-build` — bootstrap-generated downstream skills). A miss
FAILS naming the mention and its line number.

Reverse: every `.claude/skills/aai-*` directory must have a `/​<name>` mention
in USER_GUIDE; the exception array in the test is EMPTY after this scope
(aai-factory-report is fixed, not excepted). A miss FAILS naming the skill.

Both arms are RED-first against the current tree (forward names the two
feedback aliases; reverse names aai-factory-report).

### D3 — note-parse placement: IMPORT the shared lib, mirroring is forbidden

`.aai/scripts/lib/usage-note.mjs` already exists as the single source of the
`usage_total_tokens=<N>` grammar, and test_120 in
tests/skills/test-aai-metrics.sh (token-economics TEST-003) greps ALL of
`.aai/scripts` and fails if the raw regex literal exists in more than one
file. A mirrored function is therefore not merely discouraged — it breaks an
existing suite. generate-dashboard.mjs imports `extractUsageTotal` from
`./lib/usage-note.mjs` exactly as generate-factory-report.mjs already does
(same relative path; both are vendored with the lib per PROFILES.yaml, and
suite-map escalates any `lib/**` change to FULL_RUN — this scope changes no
lib file). The structural pin is the import itself (TEST-005); no
structural-twin byte pin is needed because nothing is mirrored.

Per-run token precedence (never double-count, never fabricate): a run's token
total is `tokens_in + tokens_out` when either field is a finite number;
otherwise `extractUsageTotal(note)`; otherwise no token contribution. A
marker value is only ever a TOTAL — it is never split into in/out.

### D4 — empty-panel semantics: named no-data state, not omission

A chart section whose source stat is `null`/absent for the whole dataset
renders a deterministic named placeholder (e.g. a `no-data` element carrying
`data-panel="worktree"` and visible text "No data recorded in this dataset")
in place of the canvas. Chosen over omission because (a) the panel's absence
would hide that the capability exists at all, and (b) a named marker is
greppable, making both fixture directions (has-data / no-data) provable from
the rendered HTML. Applies to the TDD, Worktree and Publish sections (all
three are null against the live ledger today) and to the token chart when no
run in the dataset carries any token signal. The token chart additionally
gains a "Total Tokens" series (the template today hardcodes only
Input/Output datasets, which cannot show undecomposed totals); Input/Output
series remain for datasets that carry decomposed fields.

### D5 — everything locally provable

Every verification below is a local command: the generator run against
fixture METRICS.jsonl files in a temp dir, bash suites run via
`bash .aai/scripts/aai-run-tests.sh`, and grep/node one-liners over committed
files. No CI-only assertion exists in this spec.

## Implementation strategy
- Strategy: hybrid
- Rationale: The behavior-bearing surfaces (note-parse totals, no-data panel
  rendering, both-direction drift reconciliation) get TDD — each has a cheap
  deterministic RED available today (totalTokens renders 0; no-data marker
  absent; drift test names the two dead aliases and aai-factory-report), with
  RED artifacts stored under docs/ai/tdd/. The prose surfaces (USER_GUIDE
  surgery, SKILL_DASHBOARD caveat, product doc, ledger entry) are loop-lane
  glue verified by the same suites' pins. No intake-recorded strategy choice
  exists for CHANGE-0140 (STATE's current `implementation_strategy` belongs to
  the previous scope, canonical-test-invocation).

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: work already lives on the dedicated branch
  feat/reporting-docs-true-up; no parallel scope shares these files
- User decision: undecided
- Base ref: main
- Worktree branch/path: feat/reporting-docs-true-up (existing branch, inline)
- Inline review scope: .aai/scripts/generate-dashboard.mjs,
  docs/dashboard-template.html, .aai/SKILL_DASHBOARD.prompt.md,
  docs/USER_GUIDE.md, docs/product/aai-dashboard.md,
  tests/skills/test-aai-dashboard.sh, tests/skills/test-aai-userguide-drift.sh,
  tests/skills/suite-map.yaml, tests/skills/lib/prompt-diet-ledger.sh,
  tests/skills/test-aai-prompt-diet.sh, docs/specs/SPEC-0127-spec-reporting-docs-true-up.md,
  docs/issues/CHANGE-0140-reporting-docs-true-up.md, CHANGELOG.md

Code review required: true (code + template + tests + prompt bytes); scope =
the explicit path list above as a diff against main.

## Companion obligations check (closed list)
- Prompt corpus bytes move: YES — `.aai/SKILL_DASHBOARD.prompt.md` caveat
  rewrite changes `.aai/*.prompt.md` bytes. Folded into scope: a prompt-diet
  ledger true-up (JUSTIFIED_ADDITIONS entry for growth, or a savings note) and
  a moved TEST-012 checkpoint (from -6642) equal to the independent re-sum.
  Test Plan: TEST-010 via tests/skills/test-aai-prompt-diet.sh.
- New `.aai/**` file: NO — the generator and prompt are edited in place; new
  files land under tests/skills/ and docs/. No PROFILES.yaml entry required.

## Acceptance Criteria Mapping

- Maps to: CHANGE-0140 AC-001
- Spec-AC-01: WHEN docs/USER_GUIDE.md is read after the surgery THEN the two
  dead alias comments (`# or /aai-feedback-triage`, `# or /aai-feedback-upsert`)
  are gone with the feedback section otherwise intact, a hand-authored
  `/aai-factory-report` section exists outside the rollup markers (including a
  vs-`/aai-dashboard` comparison), the command table and quick reference list
  it, and every skill/script mention follows the D1c convention.
- Verification: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-userguide-drift.sh` (TEST-009 arm) exits 0; `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-userguide-rollup.sh` exits 0 (markers intact, containment held); `node .aai/scripts/generate-userguide-rollup.mjs` leaves bytes outside the markers untouched.

- Maps to: CHANGE-0140 AC-002
- Spec-AC-02: WHEN tests/skills/test-aai-userguide-drift.sh runs THEN it
  reconciles USER_GUIDE against `.claude/skills/` in BOTH directions with the
  D2 anchored extractor and in-test exception arrays, failing with the
  offending name (and line, forward) on any miss; it was observed RED on the
  pre-change tree naming `/aai-feedback-triage`, `/aai-feedback-upsert`
  (forward) and `aai-factory-report` (reverse); and the new suite carries a
  suite-map row (hygiene pin green).
- Verification: pre-change RED run stored in docs/ai/tdd/; post-change suite exits 0; `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-hygiene-pack.sh` exits 0.

- Maps to: CHANGE-0140 AC-003
- Spec-AC-03: WHEN generate-dashboard.mjs processes a ledger whose
  `agent_runs[].note` carries `usage_total_tokens=<N>` markers (tokens_in/out
  null) THEN summary.totalTokens, per-day tokensByTime totals and per-skill
  token stats equal the exact marker sums, computed via `extractUsageTotal`
  imported from `.aai/scripts/lib/usage-note.mjs` under the D3 precedence
  rule, with undecomposed totals reported ONLY as totals (never split into
  in/out), and the raw regex literal still lives in exactly one source file.
- Verification: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-dashboard.sh` exits 0 (TEST-001/002/005); `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-metrics.sh` exits 0 (test_120 single-source grep contract); `node .aai/scripts/generate-dashboard.mjs --data-only` against the real docs/ai/METRICS.jsonl reports `Total tokens:` greater than 0 (69 markers exist).

- Maps to: CHANGE-0140 AC-004
- Spec-AC-04: WHEN the rendered dashboard HTML is generated from a dataset
  whose TDD/worktree/publish (or all-token) source data is absent for the
  whole dataset THEN each affected section renders the named D4 no-data state
  (never a bare empty axis), and WHEN generated from a dataset that HAS the
  data THEN the chart renders and the no-data marker is absent — proven by
  fixtures in both directions.
- Verification: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-dashboard.sh` exits 0 (TEST-003 no-data fixture, TEST-004 has-data fixture); pre-change RED stored in docs/ai/tdd/.

- Maps to: CHANGE-0140 AC-005
- Spec-AC-05: WHEN `.aai/SKILL_DASHBOARD.prompt.md` is read post-change THEN
  the "Tokens are mostly null ... known gap" caveat is replaced by a truthful
  description of the note-parse behavior (including the troubleshooting row),
  and the prompt-diet ledger + TEST-012 checkpoint reflect the byte delta
  (independent re-sum equals the new pin).
- Verification: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-dashboard.sh` exits 0 (TEST-006 prompt pin); `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh` exits 0 (TEST-010 row here; suite TEST-010/012/013 checkpoints).

- Maps to: CHANGE-0140 AC-005 (product docs truthful) + intake `user_visible: true`, `capability: aai-dashboard`
- Spec-AC-06: WHEN the scope closes THEN docs/product/aai-dashboard.md exists
  as a REAL product doc (capability `aai-dashboard`, no placeholder sections
  per lib/product-doc.mjs) describing the dashboard truthfully (real token
  totals from note markers, named no-data panels), so the close-time product
  gate and the generated USER_GUIDE rollup pick it up.
- Verification: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-dashboard.sh` exits 0 (TEST-011 predicate check via node one-liner importing lib/product-doc.mjs); `node .aai/scripts/generate-userguide-rollup.mjs` includes the doc after close.

## Constitution deviations

None. (Checked v1 articles 1-7: evidence is executable and local (1, D5);
nothing speculative — every edit maps to a confirmed defect (2); all
artifacts are plain git-diffable files (3); the no-data state is an explicit
degrade-and-report of absent data (4); data-shape changes are additive —
tokensByTime gains `total` alongside `input`/`output`, no field removed, no
CLI flag changes (5); STATE.yaml is not written by this planning pass — the
orchestrator records phase/strategy through state.mjs (6); no merge is
performed (7).)

## Acceptance Criteria Status

| Spec-AC    | Description                                                        | Status  | Evidence | Review-By | Notes |
|------------|--------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | USER_GUIDE truth: dead aliases removed, factory-report documented, D1c convention | done | test-aai-userguide-drift.sh TEST-009 exit 0; test-aai-userguide-rollup.sh exit 0; rollup re-run outside-marker bytes byte-identical (2026-08-13) | — | — |
| Spec-AC-02 | Both-direction anti-drift suite, anchored extractor, in-test exceptions, RED-first | done | docs/ai/tdd/red-20260813T175818Z-reporting-docs-true-up-userguide-drift.log (names both aliases + aai-factory-report); post-change suite exit 0; hygiene-pack exit 0 | — | — |
| Spec-AC-03 | Dashboard parses usage_total_tokens via shared lib; totals never fabricated into in/out | done | test-aai-dashboard.sh TEST-001/002/005 exit 0; test-aai-metrics.sh exit 0 (test_120); real ledger run: Total tokens 37098869 == independent D3 recompute | — | — |
| Spec-AC-04 | Named no-data state for whole-dataset-absent chart sections; fixture-proven both ways | done | docs/ai/tdd/red-20260813T175818Z-reporting-docs-true-up-dashboard.log; test-aai-dashboard.sh TEST-003/004 exit 0; real HTML: tdd/worktree/publish no-data, tokenChart renders | — | — |
| Spec-AC-05 | SKILL_DASHBOARD caveat truthful; diet ledger + TEST-012 pin moved from -6642 | done | test-aai-dashboard.sh TEST-006 exit 0; test-aai-prompt-diet.sh exit 0 (+598 B entry, pin -6642 -> -6044 == independent re-sum) | — | — |
| Spec-AC-06 | Real product doc for capability aai-dashboard passes placeholder predicate | done | test-aai-dashboard.sh TEST-011 exit 0; rollup re-run renders product/aai-dashboard.md (24 features) | — | — |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan

Components affected:
- `.aai/scripts/generate-dashboard.mjs` — import `extractUsageTotal` from
  `./lib/usage-note.mjs`; normalizeLedgerEntry gains a per-run `tokensTotal`
  under the D3 precedence rule; summary/tokensByTime/skillStats aggregate the
  total (tokensByTime entries become `{input, output, total}` — additive).
- `docs/dashboard-template.html` — token chart gains a Total series; TDD /
  Worktree / Publish sections (and the token section on an all-absent
  dataset) branch to the named no-data element when their stat is null.
- `docs/USER_GUIDE.md` — D1 surgery (outside rollup markers only).
- `.aai/SKILL_DASHBOARD.prompt.md` — truthful note-parse description.
- `docs/product/aai-dashboard.md` — NEW real product doc (capability model).
- `tests/skills/test-aai-dashboard.sh` — NEW suite (TEST-001..006, 011).
- `tests/skills/test-aai-userguide-drift.sh` — NEW suite (TEST-007..009).
- `tests/skills/suite-map.yaml` — rows for both new suites (generous globs:
  the generator+template+prompt+skill dirs for aai-dashboard;
  docs/USER_GUIDE.md + .claude/skills/** for the drift suite).
- `tests/skills/lib/prompt-diet-ledger.sh` + `test-aai-prompt-diet.sh` —
  ledger true-up + TEST-012 pin move (measured at edit time).
- `CHANGELOG.md` — one `## [unreleased] — <title>` heading per convention.

Data flows / seams (each crossed by a named test):
- SEAM-1 note grammar: generate-dashboard.mjs -> lib/usage-note.mjs shared
  with metrics-flush/report, generate-overview, generate-factory-report —
  crossed by TEST-005 (import pin) + the existing metrics test_120 grep
  contract re-run green.
- SEAM-2 payload: dashboard-data.json -> `{{METRICS_DATA}}` -> template JS —
  crossed by TEST-003/004 asserting the RENDERED HTML, not just the JSON.
- SEAM-3 rollup markers: hand-authored USER_GUIDE sections vs
  generate-userguide-rollup.mjs containment — crossed by the existing
  test-aai-userguide-rollup.sh suite green plus an idempotent rollup re-run.
- SEAM-4 prompt bytes: SKILL_DASHBOARD.prompt.md vs the diet ledger pins —
  crossed by TEST-010 (prompt-diet suite).
- SEAM-5 product doc: docs/product/aai-dashboard.md vs the placeholder
  predicate + close-time rollup — crossed by TEST-011.

Edge cases:
- Marker with bracketed context (`claude-opus-4-8[1m]` nearby, marker at a
  sentence boundary, quoted/parenthesized) — covered by lib grammar; fixture
  includes these forms.
- Malformed marker (`usage_total_tokens=123oops`, `not_usage_total_tokens=456`)
  must contribute nothing (lib rejects; TEST-002 asserts).
- A run with BOTH finite tokens_in/out AND a marker: explicit fields win,
  marker ignored (no double count) — TEST-002.
- Legacy flat entries (`tokens: {input, output}`) keep working — TEST-004
  fixture includes one.
- All-zero vs absent: a dataset with runs but no token signal anywhere gets
  the token-section no-data state, not a flat zero line — TEST-003.

Residual risk (written down, not silently accepted): the template payload
escaping in generateDashboard() (`<` then backtick then backslash replacement
order, and String.replace `$`-pattern semantics) predates this scope; it
renders correctly against today's data and TEST-001..004 exercise the real
embed path with realistic note text, but a full escaping audit is out of
scope. If a fixture exposes corruption, fix-at-cause is in scope for the
payload line only.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                        | Description                                                        | Status  |
|----------|------------|-------------|---------------------------------------------|--------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-03 | integration | tests/skills/test-aai-dashboard.sh          | fixture ledger with marker-carrying notes: totalTokens, per-day and per-skill totals equal exact expected sums | green   |
| TEST-002 | Spec-AC-03 | integration | tests/skills/test-aai-dashboard.sh          | honesty: marker never split into in/out; explicit in/out wins over marker; malformed markers contribute nothing | green   |
| TEST-003 | Spec-AC-04 | integration | tests/skills/test-aai-dashboard.sh          | no-data fixture: rendered HTML carries the named no-data state per absent section, no bare empty axis | green   |
| TEST-004 | Spec-AC-04 | integration | tests/skills/test-aai-dashboard.sh          | has-data fixture (incl. legacy flat entries): charts render, no-data markers absent | green   |
| TEST-005 | Spec-AC-03 | unit        | tests/skills/test-aai-dashboard.sh          | structural pin: generate-dashboard.mjs imports lib/usage-note.mjs extractUsageTotal; no local regex literal | green   |
| TEST-006 | Spec-AC-05 | unit        | tests/skills/test-aai-dashboard.sh          | SKILL_DASHBOARD.prompt.md pin: stale known-gap caveat absent, note-parse behavior described | green   |
| TEST-007 | Spec-AC-02 | integration | tests/skills/test-aai-userguide-drift.sh    | forward reconcile: anchored /aai-* mentions resolve to .claude/skills or ALLOWED_GENERATED; miss FAILS naming mention and line | green   |
| TEST-008 | Spec-AC-02 | integration | tests/skills/test-aai-userguide-drift.sh    | reverse reconcile: every vendored skill mentioned; exception array empty; miss FAILS naming the skill | green   |
| TEST-009 | Spec-AC-01 | integration | tests/skills/test-aai-userguide-drift.sh    | truth pins: dead feedback aliases absent; factory-report section present with dashboard comparison; convention holds | green   |
| TEST-010 | Spec-AC-05 | integration | tests/skills/test-aai-prompt-diet.sh        | diet-ledger true-up: moved TEST-012 checkpoint equals independent re-sum after prompt byte delta | green   |
| TEST-011 | Spec-AC-06 | unit        | tests/skills/test-aai-dashboard.sh          | docs/product/aai-dashboard.md passes the lib/product-doc.mjs placeholder predicate (real doc) | green   |
| TEST-012 | Spec-AC-02 | integration | tests/skills/test-aai-hygiene-pack.sh       | both new suites carry suite-map rows (existing hygiene pin re-run) | green   |
| TEST-013 | Spec-AC-01 | integration | tests/skills/test-aai-userguide-rollup.sh   | rollup containment/idempotence green after USER_GUIDE surgery (markers untouched) | green   |

RED plan (hybrid): TEST-001 (totalTokens 0), TEST-003 (marker absent),
TEST-006 (caveat present), TEST-007 (names the two dead aliases), TEST-008
(names aai-factory-report), TEST-009 (factory-report section absent) are each
observed FAILING on the pre-change tree; RED runs recorded under docs/ai/tdd/
before GREEN work starts. TEST-002/004/005/011 ride the same suites with
fixture-negative controls; TEST-010/012/013 are existing-suite re-runs whose
RED arises mechanically from the byte/row changes.

## Verification
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-dashboard.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-userguide-drift.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-userguide-rollup.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-metrics.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-hygiene-pack.sh`
- `node .aai/scripts/generate-dashboard.mjs --data-only` (real ledger; Total tokens > 0)
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0127-spec-reporting-docs-true-up.md`
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: reporting-docs-true-up
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path (docs/ai/tdd/ for RED artifacts per the hybrid strategy)
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
