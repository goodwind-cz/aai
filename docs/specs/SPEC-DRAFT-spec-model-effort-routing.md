---
id: spec-model-effort-routing
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: b8de102aa34051daedf542ce311627df8b574310afc474cdf33c796934704fbe
ceremony_level: 3
links:
  requirement: model-effort-routing
  rfc: null
  pr: []
  commits: []
---

# Every dispatch carries an applicable effort tier, its token effect is recorded, and a deterministic evidence digest is measured before use

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/CHANGE-DRAFT-model-effort-routing.md
- Prior art this scope extends and does not undo: SPEC-0110 (advisory
  `suggested_effort`, no mid-session flip), SPEC-0177 (harness-scoped model
  routing, effort never harness-scoped), SPEC-0178 (telemetry fields, not
  prose), SPEC-0186 (canon.mjs build assembles contract first, scope last),
  SPEC-0286 (round cap, `round-budget.mjs sweep-plan`), RES-0002 (mechanical
  offload: measure before delegating).
- Vendor facts, read from primary docs on 2026-11-12:
  - code.claude.com/docs/en/sub-agents: `effort` frontmatter and a
    per-invocation `effort` parameter (low, medium, high, xhigh, max; v2.1.292
    or later); `CLAUDE_CODE_EFFORT_LEVEL` takes precedence over both.
  - code.claude.com/docs/en/changelog.md: 2.1.316 adds
    `CLAUDE_CODE_SUBAGENT_EFFORT` (level for subagents when nothing else names
    one); 2.1.317 makes a subagent on another model use that model's saved
    effort.
  - learn.chatgpt.com/docs/config-file/config-reference (Codex):
    `model_reasoning_effort`; `agents.default_subagent_reasoning_effort`, which
    an explicit spawn effort overrides.
  - aistudio.google.com/docs/thinking (Gemini): `thinking_level` low or high on
    gemini-3-pro-preview; minimal, low, medium or high on
    gemini-3-flash-preview.
  - UNVERIFIED here (research report only): cache price multipliers and the
    claim that a top-level effort change invalidates the prompt cache. No AC
    depends on them.
- The Agent tool in this Claude Code session exposes `effort` (low, medium,
  high, xhigh, max) and says to set it only when a skill or CLAUDE.md asks.
  SKILL_LOOP is such a skill, so canon text is the switch.
- Technology contract: docs/TECHNOLOGY.md (Node stdlib, bash suites through
  the canonical wrapper).

Registry items closed by this scope: none. `node .aai/scripts/follow-ups.mjs
list` holds no open item on effort routing, cache telemetry, metrics-report or
an evidence digest.

## Implementation strategy

- Strategy: tdd
- Rationale: every rule is a deterministic resolution, a refusal, a
  projection or a fixed output line, and each can be seen failing on the
  unchanged tree. Prose rules are pinned by grep tests that are red before the
  edit. Runs of about three Spec-ACs: (1) Spec-AC-01..04, (2) Spec-AC-05..07,
  (3) Spec-AC-08..09, (4) Spec-AC-10..12, (5) Spec-AC-13..14.

## Isolation and review

- Worktree recommendation: required (ceremony L3)
- Worktree rationale: state.mjs is a protected L3 surface. The main checkout
  is shared and holds uncommitted telemetry.
- User decision: worktree (owner-directed in the session brief of 2026-11-12,
  recorded in STATE)
- Base ref: origin/main at 44c272be
- Worktree branch/path: change/model-effort-routing at
  /Users/ales/Projects/aai-worktrees/model-effort-routing
- Review required: true (L3: mandatory, most capable tier)
- Review scope: diff range origin/main...HEAD over .aai/system/MODEL_ROUTING.yaml;
  .aai/scripts/orchestration-dispatch.mjs; .aai/scripts/state.mjs;
  .aai/scripts/metrics-flush.mjs; .aai/scripts/metrics-report.mjs;
  .aai/scripts/append-event.mjs; .aai/scripts/evidence-digest.mjs;
  .aai/SKILL_LOOP.prompt.md; .aai/ORCHESTRATION_PARALLEL.prompt.md;
  .aai/SUBAGENT_PROTOCOL.md; .aai/SKILL_SHIP.prompt.md;
  .aai/VALIDATION.prompt.md; .aai/system/PROFILES.yaml;
  docs/ai/docs-audit.yaml; tests/skills/test-aai-model-effort.sh;
  tests/skills/suite-map.yaml; tests/skills/suite-weights.tsv;
  tests/skills/lib/prompt-diet-ledger.sh; tests/skills/test-aai-prompt-diet.sh;
  tests/skills/test-aai-pr-preflight.sh; tests/skills/test-aai-legacy-migrations.sh;
  tests/skills/test-aai-retired-loop-runner.sh; any existing suite whose
  fixture must change (named in the hand-off); CHANGELOG.md;
  docs/product/model-effort-routing.md (written at /aai-ship step 4); the
  intake and this spec; the append-only ledger lines the ride writes.

## Ceremony

Ceremony level 3. The scope edits `.aai/scripts/state.mjs` (append-run and
log-tick flags), which `protected_paths_l3` in docs/ai/docs-audit.yaml lists.
L3 brings a recorded worktree decision (done), mandatory review on the most
capable tier, full re-check rounds, and an operator checkpoint before merge.
The owner merges on his own word. The round-cap rules of SPEC-0286 apply: two
rounds, a FAIL needs a backed BLOCKING finding, one full sweep.
`.aai/workflow/WORKFLOW.md` and `.aai/ORCHESTRATION.prompt.md` are not edited
(ORCHESTRATION is at its 45-line ceiling; its MODEL SELECTION line already
defers to the dispatch fields).

## Measurements behind the decisions

From docs/ai/METRICS.jsonl at origin/main 44c272be, the last 30 flushed work
items (`slim-standing-role-context` to `release-corpus-hermetic`):

| Role | Runs | Runs with harness total | Sum tokens_total | Median tokens_total | Cost USD |
|---|---|---|---|---|---|
| Validation | 103 | 62 | 41,244,856 | 168,754 | 147.10 |
| Code Review | 68 | 45 | 12,279,494 | 136,625 | 98.22 |
| TDD Implementation | 35 | 20 | 13,799,537 | 269,927 | 47.84 |
| Remediation | 68 | 40 | 11,327,490 | 101,264 | 38.92 |
| Planning | 25 | 17 | 8,439,218 | 239,957 | 56.87 |
| Implementation | 17 | 1 | 301,385 | 301,385 | 2.71 |

Totals: 87,391,980 tokens_total, 391.67 USD. Across the whole ledger (1412
runs) 50 runs carry decomposed in and out tokens, 784 carry a `tokens_total`
field (524 of them non-null), 0 carry an effort and 0 a cache creation figure.
A Planning run on 2026-11-07 recorded `tokens_in` 44 and `tokens_total`
1,824,129, so the harness total is dominated by cached context, which no field
records today.

`canon.mjs build --role Validation` for refs `factory-round-cap` and
`round-cap-hardening` share 46,065 of 46,193 bytes; the only difference is in
the scope section, which is last. Stable-first ordering already holds; it has
no cross-ref test.

## Decisions

### D-VOCAB. A closed effort vocabulary

- `EFFORT_LEVELS = ['low', 'medium', 'high']`. A row under `effort_tiers:` or
  `effort_roles:` whose value is in the set resolves to it.
- The value `default` (the shipped value until now) is accepted and resolves
  to null, which keeps a consumer's old file meaning "let the harness decide".
- Any other value: the row is ignored and one stderr NOTE per row names the
  key and value. stdout stays valid JSON.

### D-TABLE. The shipped effort rows

- `effort_tiers:` mechanical low, standard medium, premium high.
- `effort_roles:` Planning high, Validation high, Code Review high,
  Implementation medium, TDD Implementation medium, Remediation medium,
  Metrics Flush low.
- Technology extraction, Bootstrap and Implementation Preparation / Worktree
  decision resolve low through the mechanical tier default.
- Every role in the dispatcher's `TIERS` table therefore resolves a non-null
  `suggested_effort`.

### D-PARAM. The harness translation

- A new section form `effort_params@<harness>:` with rows `  <level>: <token>`
  maps a level from EFFORT_LEVELS to the value the harness's own knob takes.
  The choice of level per role stays harness-independent (the existing
  never-scoped rule for `effort_tiers`/`effort_roles` is unchanged); only the
  spelling is per harness.
- Shipped rows: `effort_params@claude:` and `effort_params@codex:` map low,
  medium and high to themselves. `effort_params@gemini:` maps low to low,
  medium to high and high to high, because gemini-3-pro-preview accepts only
  low and high; rounding up never lowers effort.
- No `cursor` section: cursor runs the user's chosen model and settings.
- Every dispatch verdict carries `harness_effort`: the mapped token for the
  detected harness when `suggested_effort` is non-null and the harness has a
  row for it, else null. An unsuffixed `effort_params:` header, or a suffix
  outside the closed harness set, is ignored with one NOTE.
- The `--human` block gains one line `Harness effort: <token or (unset)>`.

### D-OVERRIDE. A visible environment override

- When the detected harness is `claude` and `CLAUDE_CODE_EFFORT_LEVEL` is set
  and non-empty, the verdict carries `effort_override:
  "CLAUDE_CODE_EFFORT_LEVEL"` (the name only, never the value) and the human
  block says the per-dispatch effort will not apply. Otherwise
  `effort_override` is null.
- No other harness has a documented variable that beats an explicit spawn
  effort, so none is probed.

### D-RECORD. Telemetry fields

- `state.mjs append-run` gains `--requested-effort <low|medium|high>`,
  `--effort-applied <param|not_supported|overridden>`, `--cache-read <int>` and
  `--cache-creation <int>`. Out-of-set or non-integer values exit 2 with the
  usage line and write nothing. The run gets `requested_effort`,
  `effort_applied`, `cache_read_tokens` and `cache_creation_tokens` only when
  the flag was passed.
- `effort_applied` meanings: `param` the value was passed through the
  harness's per-dispatch knob; `not_supported` the harness or session had no
  such knob or `harness_effort` was null; `overridden` the dispatch reported
  `effort_override`.
- `state.mjs log-tick` gains `--cache-creation <int>` beside its existing
  `--cache-read`, written as `cache_creation_tokens` only when passed.
- `metrics-flush.mjs` copies the four run fields into the METRICS line when
  present (numbers as numbers), and leaves them absent otherwise, the same
  shape as `requested_model`. Cost computation is unchanged.

### D-REPORT. The measurement

- `node .aai/scripts/metrics-report.mjs --by-effort [--split <YYYY-MM-DD>]
  [--metrics <path>]` prints a deterministic markdown table grouped by role
  (the role string with any ` (...)` suffix removed) and `requested_effort`
  (`unset` when absent), rows sorted by role then level, columns: runs, runs
  with tokens_total, sum and median tokens_total, sum cost_usd, sum
  cache_read_tokens, sum cache_creation_tokens, runs with cache figures.
- With `--split D`, work items whose `date_utc` is before D form a `Before D`
  table and the rest a `From D` table, followed by a `Delta by role` table:
  median tokens_total before and after and the change in percent with one
  decimal, `n/a` when either side has no value.
- Without `--by-effort` the output is byte-identical to today's (the golden
  test of test-aai-metrics.sh stays green unchanged).

### D-CANON. Passing the value

- SKILL_LOOP step 4: when the dispatch carries `harness_effort`, pass it
  through the harness's per-dispatch effort knob (Claude Code Agent `effort`,
  Codex spawn `reasoning_effort`) unless `effort_override` is set; record
  `--requested-effort <suggested_effort> --effort-applied <param|not_supported|overridden>`
  on that role's append-run. Step 6: pass `--cache-creation` with
  `--cache-read` when the harness reports them.
- SUBAGENT_PROTOCOL "Harness-reported usage capture": decomposed usage also
  passes `usage.cache_read_input_tokens` and
  `usage.cache_creation_input_tokens` as `--cache-read` and `--cache-creation`
  on append-run. A total-only result passes neither.
- ORCHESTRATION_PARALLEL MODEL SELECTION and SKILL_SHIP RUN step 2 each gain
  one clause: honor `harness_effort` the same way as `suggested_model`.
- The no-mid-session-flip rule stays: effort changes only between separate
  dispatches.

### D-PREFIX. Cache-friendly dispatch pin

- A test builds `canon.mjs build --role <R> --ref <a>` and `--ref <b>` for
  every role CANON.yaml declares and asserts the two payloads are
  byte-identical up to the `<<<AAI-CANON-SECTION scope` marker, and that the
  scope section is the last section. This pins existing behaviour; its RED is
  the mutation, not the unchanged tree.

### D-DIGEST. A deterministic evidence digest

- `node .aai/scripts/evidence-digest.mjs run --ref <ref> [--spec <path>]
  [--record] [--root <dir>]` reads the spec (default: STATE
  `current_focus.spec_path`) and prints, in this order:
  - one line per `## Acceptance Criteria Status` row:
    `AC <Spec-AC> status=<status> evidence_paths=<n> missing=<k>`, where
    evidence paths are cell tokens under `docs/` or `tests/` and `missing`
    counts those absent from the tree;
  - one line per `## Test Plan` row:
    `TEST <id> ac=<Spec-AC> file=<path> file_exists=<yes|no> id_in_file=<yes|no>`;
  - `GATE spec-lint rc=<n>`, `GATE mutation-gate rc=<n>`,
    `GATE docs-audit-gate rc=<n>` from `spec-lint.mjs --path <spec>`,
    `mutation-gate.mjs --spec <spec>` and `docs-audit.mjs --gate <spec id>`;
  - the `SWEEP ...` line of `round-budget.mjs sweep-plan --ref <ref>`;
  - a summary `DIGEST ref=<ref> head=<sha> acs=<n> acs_not_done=<a>
    evidence_missing=<k> tests_unlocated=<m> gates_red=<g> sweep_owed=<0 or 1>
    clean=<true|false>`, where clean is true only when a, k, m, g and
    sweep_owed are all 0.
- It exits 0 whatever it finds (a digest is never a verdict), 2 on usage, 3
  when the spec cannot be read.
- The dial is `evidence_digest:` in docs/ai/docs-audit.yaml: `off` (also when
  absent), `shadow` or `on`; another value is read as `off` with one NOTE.
- `--record` with the dial `shadow` or `on` appends one EVENTS line through
  `append-event.mjs --event evidence_digest --ref <ref> --head <40-hex>
  --clean <true|false> --flags <a+k+m+g+sweep_owed>`. With the dial `off` it
  prints `NOTE evidence_digest off; nothing recorded` and writes nothing.
  append-event refuses a malformed head, a clean value other than true or
  false, or a non-integer flags count.

### D-SCORE. Promotion is measured

- `node .aai/scripts/evidence-digest.mjs score [--events <path>] [--json]`
  pairs each `evidence_digest` line with the first later `check_verdict` line
  whose role is `validation` and whose ref and head match. It prints
  `SCORE pairs=<p> rides=<r> clean_pass=<cp> clean_fail=<cf> flagged_pass=<fp>
  flagged_fail=<ff> unpaired=<u>` and
  `PROMOTION <eligible|not-eligible> reason=<ok|min-pairs|min-rides|clean-fail>`.
- `clean_fail` is the false-pass candidate count: the digest said clean and
  the validator failed. It over-counts (a FAIL can be about behaviour the
  digest never claims), which is the safe side for a promotion gate.
- Eligible only when p is at least `PROMOTION_MIN_PAIRS` (20), r (distinct
  refs among pairs) is at least `PROMOTION_MIN_RIDES` (5) and cf is 0. The
  first failing reason in that order is printed.
- Eligibility changes nothing by itself. Making `on` the shipped default is a
  separate owner decision citing the score.
- VALIDATION canon gains one rule: with the dial `shadow`, run the digest with
  `--record` before judging and let no line replace a check; with `on`, a
  clean AC or GATE line may be cited for evidence existence and gate exit
  codes instead of re-opening each file, while behaviour checks, the selected
  suites and the sweep plan stay the validator's own; with `off`, skip it.
- This repository's own docs/ai/docs-audit.yaml sets `evidence_digest: shadow`
  so AAI's rides start the measurement. The code default stays `off`, so a
  downstream project changes nothing until it opts in.

### D-WIRE. Pins and wiring, named up front

- `.aai/system/PROFILES.yaml` core: add `.aai/scripts/evidence-digest.mjs`
  (VALIDATION, a core prompt, calls it).
- tests/skills/suite-map.yaml: a new suite `aai-model-effort` whose globs are
  MODEL_ROUTING.yaml, orchestration-dispatch.mjs, state.mjs, metrics-flush.mjs,
  metrics-report.mjs, append-event.mjs, evidence-digest.mjs, canon.mjs,
  .aai/system/CANON.yaml, SKILL_LOOP, ORCHESTRATION_PARALLEL,
  SUBAGENT_PROTOCOL, SKILL_SHIP and VALIDATION. Add evidence-digest.mjs to the
  globs of `aai-orchestration-dispatch` only if the selector does not already
  reach it. Add a weight row in tests/skills/suite-weights.tsv measured from
  the suite's own run.
- Prompt diet: one `JUSTIFIED_ADDITIONS` entry named `model-effort-routing` in
  tests/skills/lib/prompt-diet-ledger.sh equal to the measured corpus delta of
  the edited prompt files (SKILL_LOOP, ORCHESTRATION_PARALLEL, SKILL_SHIP,
  VALIDATION; SUBAGENT_PROTOCOL.md is measured too if the TEST-010 glob covers
  it). TEST-010 headroom stays 0/2048.
- The TEST-012 `want_growth` pin in tests/skills/test-aai-prompt-diet.sh is
  bumped by the same amount, with its dated comment.
- test-aai-pr-preflight.sh TEST-008 gains one `+<n>/* model-effort-routing
  ledger credit */` term in its `want_growth` formula.
- test-aai-legacy-migrations.sh TEST-3398 and test-aai-retired-loop-runner.sh
  TEST-3410 re-sum later ledger entries; re-run them, edit only if they redden.
- Existing pins re-run, edited only if they redden:
  - test-aai-orchestration-dispatch.sh TEST-030..034 (effort resolution; the
    key-set check at TEST around line 465 is additive-safe) and the Mode A and
    Mode B routing cases (SPEC-0177).
  - test-aai-state.sh (append-run and log-tick flag sets and usage lines).
  - test-aai-metrics.sh (flush projection, report golden).
  - test-aai-canon.sh TEST-684 (ORCHESTRATION 45-line ceiling) and
    test-aai-hygiene-pack.sh.
  - test-aai-codex-usage.sh (its `append_run_flags` must stay accepted).
  - test-aai-round-budget.sh (sweep-plan output the digest echoes).
- `append-event.mjs` `EVENT_TYPES` gains `evidence_digest`.

## Acceptance Criteria Mapping

- Maps to: intake AC-001 to Spec-AC-01 and Spec-AC-02; intake AC-002 to
  Spec-AC-03 and Spec-AC-04; intake AC-003 to Spec-AC-05 and Spec-AC-06;
  intake AC-004 to Spec-AC-07; intake AC-005 to Spec-AC-10, Spec-AC-11 and
  Spec-AC-12; intake AC-006 to Spec-AC-09; canon wiring to Spec-AC-08; the
  scope's wiring and consumer-visible duties to Spec-AC-13 and Spec-AC-14.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN orchestration-dispatch resolves a dispatch with the shipped MODEL_ROUTING.yaml the system SHALL emit suggested_effort high for Planning, Validation and Code Review, medium for Implementation, TDD Implementation and Remediation, and low for Metrics Flush, Technology extraction, Bootstrap and Implementation Preparation | planned | tests/skills/test-aai-model-effort.sh TEST-3633; RED docs/ai/tdd/model-effort-routing/red-ac01-04.log; GREEN docs/ai/tdd/model-effort-routing/green-ac01-04.log; mutation docs/ai/tdd/spec-model-effort-routing/mutation-TEST-3633.txt | — | D-TABLE |
| Spec-AC-02 | WHEN an effort row carries the value default the system SHALL resolve null, and WHEN it carries a value outside low, medium and high the system SHALL ignore the row and print one stderr NOTE naming key and value while stdout stays valid JSON | planned | tests/skills/test-aai-model-effort.sh TEST-3634; RED docs/ai/tdd/model-effort-routing/red-ac01-04.log; GREEN docs/ai/tdd/model-effort-routing/green-ac01-04.log; mutation docs/ai/tdd/spec-model-effort-routing/mutation-TEST-3634.txt | — | D-VOCAB |
| Spec-AC-03 | WHEN the detected harness is claude, codex or gemini the verdict SHALL carry harness_effort mapped through that harness's effort_params section, with gemini medium mapped to high; WHEN the harness is cursor or unknown, the file is absent, or no effort_params section exists, harness_effort SHALL be null and every other verdict field SHALL equal the pre-change output for the same snapshot | planned | tests/skills/test-aai-model-effort.sh TEST-3635 and TEST-3636; RED docs/ai/tdd/model-effort-routing/red-ac01-04.log; GREEN docs/ai/tdd/model-effort-routing/green-ac01-04.log; mutation docs/ai/tdd/spec-model-effort-routing/mutation-TEST-3635.txt, docs/ai/tdd/spec-model-effort-routing/mutation-TEST-3636.txt | — | D-PARAM |
| Spec-AC-04 | WHEN the harness is claude and CLAUDE_CODE_EFFORT_LEVEL is non-empty the verdict SHALL carry effort_override CLAUDE_CODE_EFFORT_LEVEL without its value and the human block SHALL say the dispatch effort will not apply; otherwise effort_override SHALL be null | planned | tests/skills/test-aai-model-effort.sh TEST-3637; RED docs/ai/tdd/model-effort-routing/red-ac01-04.log; GREEN docs/ai/tdd/model-effort-routing/green-ac01-04.log; mutation docs/ai/tdd/spec-model-effort-routing/mutation-TEST-3637.txt | — | D-OVERRIDE |
| Spec-AC-05 | WHEN append-run is given requested-effort, effort-applied, cache-read and cache-creation the system SHALL write the four run fields, SHALL write none of them when the flags are absent, and SHALL exit 2 writing nothing on an out-of-set or non-integer value; log-tick SHALL accept cache-creation | planned | tests/skills/test-aai-model-effort.sh TEST-3638; RED docs/ai/tdd/model-effort-routing/red-ac05-07.log; GREEN docs/ai/tdd/model-effort-routing/green-ac05-07.log; mutation docs/ai/tdd/spec-model-effort-routing/mutation-TEST-3638.txt | — | D-RECORD; state.mjs is L3 |
| Spec-AC-06 | WHEN metrics-flush flushes a work item whose runs carry the four fields the METRICS line SHALL carry them with numeric cache counts, and a run without them SHALL carry none of the four keys | planned | tests/skills/test-aai-model-effort.sh TEST-3639; RED docs/ai/tdd/model-effort-routing/red-ac05-07.log; GREEN docs/ai/tdd/model-effort-routing/green-ac05-07.log; mutation docs/ai/tdd/spec-model-effort-routing/mutation-TEST-3639.txt | — | D-RECORD; seam append-run to flush to METRICS |
| Spec-AC-07 | WHEN metrics-report runs with by-effort over a fixture ledger the system SHALL print the per-role and per-effort table with unset for runs without effort, and with split the Before, From and Delta tables with one-decimal percent; without by-effort the output SHALL be byte-identical to the existing golden | planned | tests/skills/test-aai-model-effort.sh TEST-3640 and TEST-3641; RED docs/ai/tdd/model-effort-routing/red-ac05-07.log; GREEN docs/ai/tdd/model-effort-routing/green-ac05-07.log; mutation docs/ai/tdd/spec-model-effort-routing/mutation-TEST-3640.txt, mutation docs/ai/tdd/spec-model-effort-routing/mutation-TEST-3641.txt | — | D-REPORT; the measurement |
| Spec-AC-08 | SKILL_LOOP step 4 and step 6, SUBAGENT_PROTOCOL usage capture, ORCHESTRATION_PARALLEL MODEL SELECTION and SKILL_SHIP RUN step 2 SHALL name harness_effort, the Agent effort and Codex reasoning_effort knobs, effort_override, requested-effort, effort-applied and cache-creation as D-CANON lists, and ORCHESTRATION.prompt.md SHALL stay at or under 45 lines | planned | — | — | D-CANON |
| Spec-AC-09 | WHEN canon.mjs build runs for two different refs with the same role the system SHALL produce payloads byte-identical up to the scope section marker, and the scope section SHALL be the last section, for every role CANON.yaml declares | planned | — | — | D-PREFIX; pins existing behaviour |
| Spec-AC-10 | WHEN evidence-digest run reads a fixture spec and tree the system SHALL print the AC, TEST, GATE and SWEEP lines and a DIGEST summary whose counts match the fixture, with clean true only when all five counts are 0, and SHALL exit 0 whatever it finds | planned | — | — | D-DIGEST |
| Spec-AC-11 | WHEN evidence-digest run is given record the system SHALL append one evidence_digest EVENTS line through append-event only when the docs-audit.yaml dial is shadow or on, SHALL print a NOTE and write nothing when the dial is off or absent, and append-event SHALL refuse a malformed head, clean or flags value | planned | — | — | D-DIGEST; seam digest to append-event to EVENTS |
| Spec-AC-12 | WHEN evidence-digest score reads an EVENTS file the system SHALL pair digests with validation check_verdict lines by ref and head, print the SCORE counts, and print PROMOTION eligible only with at least 20 pairs, at least 5 refs and zero clean_fail; VALIDATION SHALL state the off, shadow and on rules and this repository's docs-audit.yaml SHALL set shadow | planned | — | — | D-SCORE |
| Spec-AC-13 | evidence-digest.mjs SHALL be classified core in PROFILES, mapped by suite-map to aai-model-effort, and the prompt-diet ledger entry, the TEST-012 pin and the companion pins SHALL agree with the measured corpus delta at headroom 0 | planned | — | — | D-WIRE |
| Spec-AC-14 | CHANGELOG.md SHALL carry exactly one entry for this change naming effort per role, the harness translation, the recorded fields, the by-effort report and the shadow digest, found under either a per-entry unreleased heading below the kept bare scaffold or a rolled release section | planned | — | — | Consumer-visible; the product doc is /aai-ship step 4, not an AC |

## Implementation plan

1. MODEL_ROUTING.yaml: replace the `default` values per D-TABLE, add the
   three `effort_params@<harness>` sections, and update the header comments
   (the ADVISORY EFFORT paragraph names the closed vocabulary and the
   translation section; the never-scoped sentence stays).
2. orchestration-dispatch.mjs:
   - `EFFORT_LEVELS` constant; the parser keeps a row only when
     `isEffortLevel(value)` or the value is `default`; others print the NOTE.
     Guard spelling `if (!isEffortLevel(v))`.
   - Parse `effort_params@<h>` into `routing.harnesses[h].effort_params`;
     reject unsuffixed and out-of-set suffixes with a NOTE (guard spelling
     `if (!effortParamsHarnessOk)`). The effort_params sections do not by
     themselves select Mode B.
   - `harnessEffort(out, routing, harness)` returns the mapped token or null;
     guard spelling `if (!map) return null`.
   - `effortOverride(env, harness)`; guard spelling
     `if (harness !== 'claude') return null`.
   - Both new fields are set on every verdict next to `suggested_effort`;
     human block lines `Harness effort:` and, when set, `Effort override:`.
3. state.mjs: add the four append-run flags and the log-tick flag to the flag
   tables, usage lines, validation and the run writer. Guard spelling for the
   enum check `if (!EFFORT_LEVELS_RUN.includes(v))`.
4. metrics-flush.mjs: add `cache_read_tokens` and `cache_creation_tokens` to
   the numeric key list of the run reader, and copy the four fields in the
   projection beside `requested_model`, one guarded assignment each, e.g.
   `if (typeof r.cache_creation_tokens === 'number') out.cache_creation_tokens = r.cache_creation_tokens;`.
5. metrics-report.mjs: a `--by-effort` and `--split` mode in a separate
   function `renderByEffort(`, grouping on `r.requested_effort`; the default
   path is untouched.
6. append-event.mjs: `evidence_digest` type and its field checks; guard
   spelling `if (!digestOk)`.
7. evidence-digest.mjs (new, Node stdlib): `run` and `score` subcommands,
   `PROMOTION_MIN_PAIRS = 20`, `PROMOTION_MIN_RIDES = 5`, the dial reader, the
   clean rule `clean = counts.every((n) => n === 0)`. It reuses
   lib/docs-model.mjs table parsers for the AC and Test Plan tables.
8. Canon edits per D-CANON and D-SCORE. docs/ai/docs-audit.yaml gets
   `evidence_digest: shadow` with a comment naming the three values.
9. Suite tests/skills/test-aai-model-effort.sh (TEST-3633 to TEST-3648,
   house style, `set -euo pipefail`, `env -u AAI_ROLE` for nested calls,
   fixtures in temp dirs, `AAI_HARNESS` to force the harness), wiring per
   D-WIRE.
10. CHANGELOG entry and prompt-diet true-up last; measure the corpus delta
    after the final prompt edit. The product doc is written by /aai-ship step
    4 after LOOP COMPLETE.

Edge cases:
- A consumer's Mode A MODEL_ROUTING.yaml with `default` effort rows: same
  `suggested_effort` null as today, `harness_effort` null.
- A Mode B file without `effort_params` sections: `harness_effort` null.
- `AAI_HARNESS=cursor`: `harness_effort` null even with a non-null
  `suggested_effort`.
- A digest on a spec with no Test Plan: zero TEST lines, counts still printed.
- A spec whose evidence cells name only SHAs or `—`: `evidence_paths=0`.
- `score` with no EVENTS file: all counts 0, `PROMOTION not-eligible
  reason=min-pairs`.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3633 | Spec-AC-01 | integration | tests/skills/test-aai-model-effort.sh | for each of the ten TIERS roles, a fixture STATE that dispatches it (or the exported suggestEffort with the shipped routing) yields the D-TABLE level in the JSON | target `.aai/system/MODEL_ROUTING.yaml`; `sed:s/  Planning: high/  Planning: default/` drops Planning to null and the case must fail | pending |
| TEST-3634 | Spec-AC-02 | unit | tests/skills/test-aai-model-effort.sh | a fixture routing file with rows default, high and turbo resolves null, high and null, prints exactly one NOTE naming turbo, and stdout parses as JSON | target `.aai/scripts/orchestration-dispatch.mjs`; `sed:s/if \(!isEffortLevel\(v\)\)/if (false)/` accepts turbo and the case must fail | pending |
| TEST-3635 | Spec-AC-03 | integration | tests/skills/test-aai-model-effort.sh | AAI_HARNESS claude, codex and gemini give harness_effort high, high and high for Validation and medium, medium and high for Remediation; cursor and unknown give null; a file without effort_params and an absent file give null; with the new sections removed every other field equals the pre-change verdict | target `.aai/scripts/orchestration-dispatch.mjs`; `sed:s/if \(!map\) return null/if (true) return null/` nulls every mapping and the case must fail | pending |
| TEST-3636 | Spec-AC-03 | unit | tests/skills/test-aai-model-effort.sh | an unsuffixed effort_params header and an effort_params@codx header each print one NOTE and add no mapping; an effort_params section alone does not switch a Mode A file to Mode B | target `.aai/scripts/orchestration-dispatch.mjs`; `sed:s/if \(!effortParamsHarnessOk\)/if (false)/` accepts the codx section without a NOTE and the case must fail | pending |
| TEST-3637 | Spec-AC-04 | integration | tests/skills/test-aai-model-effort.sh | with AAI_HARNESS claude and CLAUDE_CODE_EFFORT_LEVEL high the JSON has effort_override CLAUDE_CODE_EFFORT_LEVEL and no occurrence of the value, and the human block names it; empty variable or AAI_HARNESS codex give null | target `.aai/scripts/orchestration-dispatch.mjs`; `sed:s/if \(harness !== 'claude'\) return null/if (true) return null/` hides the override and the case must fail | pending |
| TEST-3638 | Spec-AC-05 | integration | tests/skills/test-aai-model-effort.sh | append-run in a temp STATE with the four flags writes the four fields; without them writes none; requested-effort turbo, effort-applied maybe and cache-read x each exit 2 and leave STATE byte-identical; log-tick with cache-creation 5 writes cache_creation_tokens 5 | target `.aai/scripts/state.mjs`; `sed:s/if \(!EFFORT_LEVELS_RUN.includes\(v\)\)/if (false)/` accepts turbo and the case must fail | pending |
| TEST-3639 | Spec-AC-06 | integration | tests/skills/test-aai-model-effort.sh | append-run with the four flags then metrics-flush with temp state and metrics paths produces a METRICS line whose run carries requested_effort, effort_applied and numeric cache counts; a second run without flags carries none of the keys | target `.aai/scripts/metrics-flush.mjs`; `sed:s/out.cache_creation_tokens = /void /` drops the field and the case must fail | pending |
| TEST-3640 | Spec-AC-07 | unit | tests/skills/test-aai-model-effort.sh | metrics-report by-effort over a fixture ledger of two items prints the exact expected table including an unset row; with split the Before, From and Delta tables match the expected text including a one-decimal percent and an n/a | target `.aai/scripts/metrics-report.mjs`; `sed:s/toFixed\(1\)/toFixed(0)/` changes the percent and the case must fail | pending |
| TEST-3641 | Spec-AC-07 | integration | tests/skills/test-aai-model-effort.sh | dispatch JSON suggested_effort for a Validation snapshot feeds append-run requested-effort, metrics-flush writes it, and metrics-report by-effort shows a Validation high row; metrics-report without by-effort equals the existing golden of test-aai-metrics.sh | target `.aai/scripts/metrics-report.mjs`; `sed:s/r.requested_effort/r.requested_effortX/g` loses the effort grouping and the case must fail | pending |
| TEST-3642 | Spec-AC-08 | unit | tests/skills/test-aai-model-effort.sh | greps SKILL_LOOP, SUBAGENT_PROTOCOL, ORCHESTRATION_PARALLEL and SKILL_SHIP for the D-CANON tokens and asserts ORCHESTRATION.prompt.md has at most 45 lines | target `.aai/SKILL_LOOP.prompt.md`; `sed:s/--effort-applied/--effort-appliedX/g` removes the recording rule and the case must fail | pending |
| TEST-3643 | Spec-AC-09 | integration | tests/skills/test-aai-model-effort.sh | for every role CANON.yaml declares, canon build for refs alpha-ref and beta-ref share every byte before the scope marker, and no section marker follows the scope section | target `.aai/scripts/canon.mjs`; `sed:s/const SECTION_OPEN = '<<<AAI-CANON-SECTION';/const SECTION_OPEN = '<<<AAI-CANON-SECTION' + process.argv.join(' ');/` puts the ref into every section marker and the case must fail | pending |
| TEST-3644 | Spec-AC-10 | integration | tests/skills/test-aai-model-effort.sh | in a scratch repo with a fixture spec (one done AC with a missing evidence file, one TEST row whose id is absent from its file, a spec-lint finding) the digest prints the expected AC, TEST, GATE and SWEEP lines and DIGEST with evidence_missing 1, tests_unlocated 1, gates_red at least 1 and clean false; a fixed fixture prints clean true; both exit 0 | target `.aai/scripts/evidence-digest.mjs`; `sed:s/counts.every\(\(n\) => n === 0\)/true/` reports clean on a dirty fixture and the case must fail | pending |
| TEST-3645 | Spec-AC-11 | integration | tests/skills/test-aai-model-effort.sh | record with no dial key prints the NOTE and leaves EVENTS absent; with shadow and with on it appends one evidence_digest line with the head and clean value; a dial of maybe behaves as off with a NOTE; append-event with a short head, clean yes or flags x exits 1 and writes nothing | target `.aai/scripts/append-event.mjs`; `sed:s/if \(!digestOk\)/if (false)/` accepts a malformed line and the case must fail | pending |
| TEST-3646 | Spec-AC-12 | unit | tests/skills/test-aai-model-effort.sh | score over fixture EVENTS prints the SCORE counts for paired, unpaired and other-ref lines; 20 clean_pass pairs over 5 refs print eligible; 19 pairs print min-pairs; 4 refs print min-rides; one clean_fail prints clean-fail | target `.aai/scripts/evidence-digest.mjs`; `sed:s/PROMOTION_MIN_PAIRS = 20/PROMOTION_MIN_PAIRS = 1/` makes 19 pairs eligible and the case must fail | pending |
| TEST-3647 | Spec-AC-12 | unit | tests/skills/test-aai-model-effort.sh | VALIDATION names evidence-digest.mjs run with record and the three dial values with their rules; docs/ai/docs-audit.yaml carries evidence_digest shadow; the code default with no key is off | target `.aai/VALIDATION.prompt.md`; `sed:s/evidence-digest.mjs run/evidence-digestX.mjs run/g` removes the rule and the case must fail | pending |
| TEST-3648 | Spec-AC-13 | integration | tests/skills/test-aai-model-effort.sh | PROFILES core lists evidence-digest.mjs; select-suites with it selects aai-model-effort; suite-weights has a row; TEST-010 headroom 0/2048 and TEST-012, pr-preflight TEST-008, legacy-migrations TEST-3398 and retired-loop-runner TEST-3410 green with the model-effort-routing entry | target `tests/skills/lib/prompt-diet-ledger.sh`; `sed:s/ model-effort-routing / model-effort-routingX /` hides the entry from the companion pins and the case must fail | pending |
| TEST-3649 | Spec-AC-14 | integration | tests/skills/test-aai-model-effort.sh | asserts exactly one bare unreleased scaffold and one entry naming effort per role, found under a per-entry unreleased heading or, in a fixture copy rolled by the release transform, under a release section; the release parser accepts the file | target `CHANGELOG.md`; `sed:s/## \[unreleased\](?=\n)/## [unreleased] — broken/` consumes the bare scaffold and the case must fail | pending |

Seams crossed:
- MODEL_ROUTING.yaml to orchestration-dispatch to the dispatch JSON to
  append-run to metrics-flush to METRICS to metrics-report: TEST-3641 runs the
  real CLIs end to end in a temp tree.
- evidence-digest to append-event to EVENTS to evidence-digest score paired
  with check_verdict lines written by append-event: TEST-3645 and TEST-3646
  (TEST-3646's pairing fixture is written with the real append-event CLI).
- CANON.yaml to canon.mjs build to the dispatched payload prefix: TEST-3643.
- The orchestrating agent actually passing `harness_effort` to the Agent or
  spawn knob: no automated test can cross it (an LLM reads canon). It is
  pinned only by the canon grep (TEST-3642) and observed later through
  `effort_applied` in METRICS. Residual risk R1.

## Verification

All local runs use `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh <cmd>`.

1. RED before each GREEN, per TDD run. Store in
   `docs/ai/tdd/model-effort-routing/red-<run>.log` and `green-<run>.log`.
2. `bash tests/skills/test-aai-model-effort.sh` exits 0.
3. Selected plus CORE suites for the ride diff exit 0, at least:
   aai-model-effort, aai-orchestration-dispatch, aai-state, aai-metrics,
   aai-canon, aai-prompt-diet, aai-pr-preflight, aai-legacy-migrations,
   aai-retired-loop-runner, aai-hygiene-pack, aai-codex-usage,
   aai-round-budget, aai-release, aai-suite-select, aai-layer-profiles.
4. Mutation records for TEST-3633 to TEST-3649 under
   `docs/ai/tdd/spec-model-effort-routing/`.
5. One full sweep with `AAI_TEST_TIMEOUT=3600`, recorded with
   `append-event --event full_sweep`; later rounds follow
   `round-budget.mjs sweep-plan`.
6. The PR body reports `metrics-report.mjs --by-effort` over origin/main's
   METRICS.jsonl (the baseline, all `unset`) and this ride's own
   `round-budget.mjs status`.
7. PASS criteria: every TEST row green, every Spec-AC done with evidence, CI
   green on the PR head.

## How the gain is measured

- At merge, the ride proves mechanism, not saving: every dispatch names an
  applicable effort, the run records it, and the report can split by it.
- Baseline: the table in "Measurements behind the decisions" (all runs
  `unset`), reproducible with `metrics-report.mjs --by-effort` on origin/main
  44c272be.
- After: `metrics-report.mjs --by-effort --split <release date>` once at least
  10 rides flushed after the release carry `requested_effort` on at least 80
  percent of their runs. The comparison is median tokens_total and summed cost
  per role and per ride, restricted to `effort_applied: param` runs. This is
  filed as follow-up `fu-effort-gain-remeasure`.
- Evidence digest: `evidence-digest.mjs score` on this repository's EVENTS
  after the shadow rides; the false-pass candidate count is the promotion
  input. Token saving from `on` is not claimed until it exists.
- A deterministic replay of saving is not possible: effort changes how many
  tokens a model spends, which no recorded ledger can recompute.

## Cut to follow-ups (filed at close with follow-ups.mjs add)

- `fu-effort-gain-remeasure`: the after-measurement above.
- `fu-cache-pricing-in-cost`: cost_usd ignores cache read and creation prices;
  PRICING.yaml has no cache columns.
- `fu-cheap-tier-log-triage`: a cheap-model step for reading red sweep logs, if
  a job remains after the deterministic digest.
- `fu-routing-table-model-refresh`: tiers@claude still binds
  claude-haiku-4-5, claude-sonnet-5 and claude-opus-5 while METRICS shows 5.5
  ids in use; belongs with CHANGE-0192 (routing tables have an owner).
- `fu-digest-history-backtest`: a backtest of the digest at past FAIL heads;
  not possible today because docs/ai/tdd and docs/ai/reports are gitignored.
- `fu-effort-xhigh-tier`: whether long Planning or TDD runs warrant xhigh;
  needs the remeasure first.

## Evidence contract

Each artifact records the ref_id model-effort-routing, its Spec-AC and TEST
links, the command, the exit code and the evidence path, plus the commit SHA
once one exists. RED and GREEN logs go under
docs/ai/tdd/model-effort-routing/ and mutation records under
docs/ai/tdd/spec-model-effort-routing/.

### Evidence by strategy

tdd: a stored RED artifact per AC-gating test plus the verification matrix
above.

## Residual risks

- R1. The orchestrator is an LLM reading canon; nothing forces it to pass
  `harness_effort` to the Agent or spawn knob. `effort_applied` in METRICS
  makes a miss visible after the fact, not impossible.
- R2. Planning and Code Review move from the harness default to `high` and
  Implementation from the session's level to `medium`. The net token effect is
  unknown until the remeasure; high may cost more than today on some roles.
- R3. Most runs record only a harness total, and the Agent tool exposes no
  cache split, so cache fields will be sparse on the main path.
- R4. `CLAUDE_CODE_SUBAGENT_EFFORT` is not probed: it applies only when
  nothing else names a level, and the dispatch names one.
- R5. The digest pairs with `check_verdict` lines; a ride whose validator
  never records one leaves its digests unpaired, which slows promotion but
  never makes it easier.
- R6. Gemini's mapping assumes the harness exposes a thinking-level knob to
  subagents; that is not verified. With no knob the run records
  `not_supported`.
