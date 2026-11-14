---
id: spec-consumer-config-routing-override
type: spec
number: 290
status: implementing
mutation_gate: v1
frozen_sha256: 625e279d6f4616bad9aea75ef4a4d9ffa195bb941bb21dc25da0083d30ebc931
ceremony_level: 2
links:
  requirement: consumer-config-routing-override
  rfc: null
  pr: []
  commits: []
---

# A consumer's routing exception lives in docs/ai/project-config.yaml, which no sync or update writes, and the dispatch applies it for the named harness only

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/CHANGE-0257-consumer-config-routing-override.md
  (intake AC-001..AC-009).
- Source requirement: docs/issues/CHANGE-0192-routing-tables-have-an-owner-and-a-seam.md
  AC-002, AC-003, AC-004 (the seam half; the keeper half shipped as SPEC-0289,
  PR #553, released v2026.11.13).
- Owner decision 2026-09-24 (recorded in CHANGE-0192): `/aai-update` keeps
  overwriting the shipped tables. This spec does not change that.
- Prior scopes this one builds on, not edited beyond what is listed here:
  SPEC-0177 harness-universal-routing (Mode A / Mode B, closed harness set,
  validator independence per harness), SPEC-0288 model-effort-routing (effort
  sections), SPEC-0289 routing-tables-have-an-owner-and-a-seam (routing_meta,
  stamp guard, CAT-21), SPEC-0284 install-path-parity-harness (the twin
  driver, used through its exports and NOT edited).
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, zero
  dependencies, bash suites through the canonical wrapper).
- Owner extension 2026-11-14 (amendment, disclosed below in "Owner extension
  2026-11-14"): intake AC-010..AC-015, round_extension with authority owner in
  docs/ai/EVENTS.jsonl at 2026-11-14T06:16:45Z, recorded before PR #555 merged.

Registry items closed by this scope: `fu-consumer-routing-seam`, `fu-pricing-unverified-rows`, `fu-unpriced-note-before-backstop-swap`, `fu-project-config-null-model-casing`. Measured with
`node .aai/scripts/follow-ups.mjs list` on 2026-11-13 (the first) and on
2026-11-14 (the other three, all open P3): `fu-consumer-routing-seam` names
exactly this scope; `fu-pricing-unverified-rows` is superseded by D-FULL and
closed with status dropped (the monthly routine now has to verify or mark every
row, gated by `table-freshness.mjs priced`; this ride edits no rate by hand);
the other two are fixed by D-DISPATCH-2 and D-FORMAT-2.

Related items left open on purpose: `fu-routing-pins-structural` and
`fu-routing-owner-cost-binding` (shipped-table concerns this scope does not
touch), `fu-effort-params-cursor-accepted` (effort_params accepts @unknown; this
scope refuses @unknown for its own section but does not edit effort_params).
`fu-routing-file-overwritten-on-update` is already dropped (2026-09-24).
Left open by the extension on purpose: `fu-routing-pins-structural` (a
full-table refresh still edits literal pins; deriving them is its own scope),
`fu-pc-tests-synthetic-override-ids` (the existing tests are not reworked here;
the new tests use synthetic `acme-*` ids), `fu-project-config-dangling-symlink`
(absence semantics are not touched).

## Re-measured facts (at 1667981e, worktree change/consumer-config-routing-override)

- Twin behaviour, measured on scratch installs under the session scratchpad,
  not reasoned from this repo: a git target synced with
  `bash .aai/scripts/aai-sync.sh <t> --profile core`, then given a
  `docs/ai/project-config.yaml` (CRLF bytes) and an edited
  `.aai/system/MODEL_ROUTING.yaml`, then run through `aai-sync.sh` again and
  through `aai-update.sh --repo <worktree> --ref change/consumer-config-routing-override`:
  exit 0 both times; the consumer file sha1 stayed
  bc5fd8436f0685cc42b4b1fecb11688d3785c079; the table returned to the shipped
  sha1 234503956de70a2868b00eadf4950ea2c724d936. The same sequence through
  `pwsh -File .aai/scripts/aai-sync.ps1 -TargetRoot <t>` and
  `aai-update.ps1 -Repo <worktree> -Ref <branch>` gave the same three facts.
  `git check-ignore docs/ai/project-config.yaml` exits 1 (not ignored) in both
  targets. No sync output line names the file (no seed, no prune, no migrate).
- The scratch target's own `node .aai/scripts/docs-audit.mjs` reports
  `docs/ai non-canonical: 1 (project-config.yaml)`: the name is NOT in
  `.aai/system/DOCS_AI_CANON.list`. This is the one companion the location
  needs (D-LOC).
- `.aai/system/RUNTIME_IGNORE.list` has no pattern matching
  `docs/ai/project-config.yaml`.
- `loadModelRouting(root)` and `suggestModel(out, routing)` in
  `.aai/scripts/orchestration-dispatch.mjs` (lines 1267 and 1470 at 1667981e)
  resolve Mode A and Mode B as the MODEL_ROUTING.yaml header describes; the
  closed role set is the key set of the `TIERS` constant (10 roles, line 96);
  the closed harness set is `HARNESS_VALUES` in `.aai/scripts/lib/harness.mjs`.
- `lib/pricing.mjs` `runCostUsd(pricing, id, 1, 1)` returns null for
  `claude-nonexistent-9` and `acme-model-1` (both resolve to the `unknown`
  entry, null rates) and a number for `claude-sonnet-5-5`,
  `claude-sonnet-5-5[1m]` and `claude-sonnet-5-5-20261101` (alias and
  longest-prefix rules). That is the exact test metrics-flush applies.
- `table-freshness.mjs stamp-guard` compares only non-comment routed lines of
  MODEL_ROUTING.yaml, so a comment-only edit of the UPGRADING note needs no
  re-stamp. The note's text is pinned by two live tests: TEST-639
  (test-aai-git-ref-guard.sh, `spec-update-installs-ref-guard-undisclosed Amendment 2`)
  and TEST-3660 (test-aai-pricing.sh, names `CHANGE-0192`, not the old draft id).
- `.aai/scripts/lib/**` is a `full_run_triggers.shared_lib_globs` entry in
  tests/skills/suite-map.yaml: a PR touching a new lib file runs the full CI
  matrix. Accepted (D-LIB).
- The parity suite's TEST-3560 pins the driver's scenario list to SPEC-0284's
  D-MATRIX table, so a new row in `SCENARIOS` would need an amendment of that
  done spec. This scope therefore drives the twins through the driver's
  exported functions with its own scenario objects (D-PARITY).

### Extension facts (at 5f066770, same worktree, 2026-11-14)

- PRICING.yaml `models:` rows carry `input_usd_per_m`, `output_usd_per_m`,
  `source_ref`, `last_verified_utc` and optional `notes`. There is no cache-rate
  field (cache tiers live only in `notes`), so a project price carries no cache
  rate either. No row carries a vendor field; the vendor is reachable only as
  `sources.<source_ref>.provider` (values today: openai, anthropic, google,
  deepseek, xai).
- `lib/pricing.mjs` `parsePricing` reads only the two rates per row plus
  `model_aliases` and `cost_blend`; it reads neither `source_ref` nor
  `sources:`.
- The lib/pricing.mjs consumers and their single load site each: metrics-flush.mjs
  line 1627 `const pricing = loadPricing(pricingPath);` (root from
  `repoRootOf(statePath)`, line 1622); metrics-report.mjs line 168 (paths
  resolved against `process.cwd()`); orchestration-dispatch.mjs line 1919 (the
  unpriced NOTE); aai-doctor.mjs line 715 (CAT-22). lib/project-config.mjs
  imports lib/pricing.mjs, so the reverse import would be a cycle.
- `table-freshness.mjs stamp-guard` compares every line under `models:` and
  `model_aliases:`; adding a field to a row is a priced-line change and needs a
  later `pricing_meta.last_updated_utc`. `routed` judges routed ids only;
  nothing judges the other 39 rows (o3 still reads 10/40; the vendor page read
  on 2026-11-13 says 2/8, `fu-pricing-unverified-rows`).
- `.aai/routines/ROUTING_REFRESH.routine.md` is outside the prompt corpus (no
  diet-ledger cost), is already listed under `extended:` in PROFILES.yaml, and
  is pinned by TEST-3671 and TEST-3672 (test-aai-routine.sh) and TEST-3673
  (test-aai-doctor.sh, PROFILES listing). The `aai-routine` row of
  tests/skills/suite-map.yaml globs SCRYER.routine.md but NOT
  ROUTING_REFRESH.routine.md, so an edit of the routine alone selects no routine
  suite today.
- Its Step 0 STOPs in any checkout where `git ls-files --error-unmatch` of the
  two tables fails, which is every consumer (downstream gitignores `.aai/`).
- The highest TEST id in use below 9000 is TEST-3695 (tests/skills, docs/specs,
  .aai); TEST-3696..TEST-3707 are free.

## Out of scope

- A second routing table: no tier rows, no `validation_alternate`, no lane keys
  (`Role@lane`), no effort, no effort_params in the consumer file. Role to
  model, per harness, nothing else. (Extension 2026-11-14: the file gains a
  second tenant, the `pricing:` section of D-PSECTION; the routing section
  itself stays role to model, per harness.)
- Any change to how sync, update or prune treat the file: none is needed
  (measured above), so none of `aai-sync.sh`, `aai-sync.ps1`, `aai-update.sh`,
  `aai-update.ps1` is edited. The proof is a test, not an edit.
- Seeding the file on install. Absence is the default and changes nothing.
- The shipped tables' content, overwrite behaviour, freshness stamp, stamp guard
  and effort tiers. (Extension 2026-11-14: no rate, id or stamp of either
  shipped table is edited by this ride, o3 included; PRICING.yaml gains only
  the documented optional row field `unverified_utc` in its header comment
  (D-FULL), and table-freshness.mjs gains the read-only `priced` subcommand.
  `stamp-guard`, `check` and `routed` are unchanged.)
- Extension 2026-11-14: a cache-rate field (PRICING.yaml has none), a new
  METRICS.jsonl field naming which table priced a run (R13), a `--human`
  dispatch line for a cross-vendor override, and any `.aai/*.prompt.md` edit
  (the routine file is outside the prompt corpus).
- Editing `tests/skills/lib/install-parity.mjs`, its allowlist or SPEC-0284.
- Any `.aai/*.prompt.md` or `.aai/AGENTS.md` edit (no prompt-corpus bytes, so no
  diet-ledger entry); `.aai/SKILL_DOCTOR.prompt.md` is not edited.
- A `--human` dispatch line for the override (the JSON key and the doctor are
  the visibility surfaces).

## Implementation strategy

- Strategy: tdd
- Rationale: a behavioural change across four surfaces (a new parser, the
  dispatch resolution, a doctor category, distribution files) whose central
  claims fail on the unchanged tree: no override is ever applied, the doctor has
  no CAT-22, the scratch consumer's docs-audit flags the file as non-canonical,
  the UPGRADING note says re-apply. Three ACs are non-regression claims that
  hold on the unchanged tree by construction (Spec-AC-01 survival, Spec-AC-05
  byte identity, Spec-AC-10 effort unaffected); for those the RED observation is
  the declared mutation turning the test red, recorded by mutation-run.mjs, and
  the brief says so. TDD runs of about three Spec-ACs each: (1) Spec-AC-02,
  Spec-AC-04, Spec-AC-06 (parser and the hit path); (2) Spec-AC-03, Spec-AC-05,
  Spec-AC-10 (precedence, byte identity, effort); (3) Spec-AC-07, Spec-AC-08
  (unpriced, doctor); (4) Spec-AC-01, Spec-AC-11 (twins, distribution seam);
  (5) Spec-AC-09, Spec-AC-12 (note, CHANGELOG and product docs, last).
- Extension 2026-11-14 (strategy unchanged, tdd): every new claim fails on the
  current tree (no `pricing:` section parses, no consumer costs a project price,
  no cross-vendor NOTE, no `priced` subcommand, the routine STOPs downstream and
  names no `unverified_utc`). Amended Spec-AC-01 is non-regression (its RED is
  the existing mutation record re-run over the new planted bytes). Runs:
  (E1) Spec-AC-13, Spec-AC-14, amended Spec-AC-07 (section parser, price
  precedence seam, the four consumers); (E2) Spec-AC-15, Spec-AC-16,
  Spec-AC-17 (doctor freshness, cross-vendor, `priced`); (E3) Spec-AC-18,
  Spec-AC-19, Spec-AC-21, amended Spec-AC-01 (routine both modes,
  suite-map, twins); then Spec-AC-20 (CHANGELOG and product docs) last, after
  the loop's flush.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound, multi-surface (a new core lib, the dispatch
  engine, the doctor, two vendored system files, a new suite, twin runs that
  write scratch targets); the main checkout is shared by other sessions.
- User decision: worktree (already decided by the orchestrator; the ride runs in
  this worktree)
- Base ref: origin/main at 1667981e
- Worktree branch/path: change/consumer-config-routing-override at
  /Users/ales/Projects/aai-worktrees/consumer-config-routing-override
- Review required: true (L2)
- Review scope: diff range origin/main...HEAD over
  .aai/scripts/lib/project-config.mjs; .aai/scripts/orchestration-dispatch.mjs;
  .aai/scripts/aai-doctor.mjs; .aai/system/MODEL_ROUTING.yaml;
  .aai/system/PROFILES.yaml; .aai/system/DOCS_AI_CANON.list;
  tests/skills/test-aai-project-config.sh; tests/skills/test-aai-doctor.sh;
  tests/skills/suite-map.yaml; tests/skills/suite-weights.tsv; CHANGELOG.md;
  docs/product/consumer-config.md; docs/product/aai-doctor.md; the intake and
  this spec. Extension 2026-11-14 adds: .aai/scripts/lib/pricing.mjs;
  .aai/scripts/metrics-flush.mjs; .aai/scripts/metrics-report.mjs;
  .aai/scripts/table-freshness.mjs; .aai/system/PRICING.yaml (header comment
  only); .aai/routines/ROUTING_REFRESH.routine.md;
  tests/skills/test-aai-pricing.sh; tests/skills/test-aai-routine.sh;
  docs/product/universal-routines.md.

## Ceremony

Ceremony level 2. No path in `protected_paths_l3` (docs/ai/docs-audit.yaml) is
touched: no state engine, allocator, pre-commit guard, hook gate, WORKFLOW.md
or CONSTITUTION.md edit, and no `.github/workflows/` edit. Level 1 would
understate it: the dispatch engine every tick runs, a doctor category, two
vendored system files and both install twins are in play. L2 gives full
independent validation and a required review.
The extension (2026-11-14) keeps level 2: metrics-flush.mjs,
metrics-report.mjs, table-freshness.mjs, lib/pricing.mjs and the routine file
are not in `protected_paths_l3` (measured against docs/ai/docs-audit.yaml).

## Decisions

### D-LOC. The file is `docs/ai/project-config.yaml`

- Outside `.aai/` (downstream gitignores `.aai/`), committed by the consumer
  (matches no RUNTIME_IGNORE pattern), in the directory where the consumer's
  other project-owned configs already live (`update-config.yaml`,
  `docs-audit.yaml`, `merge-policy.yaml`, `pr-config.yaml`, `roadmap.yaml`).
- Named for what the owner asked for (2026-09-24: the consumer's central
  config); the routing override is its first and only tenant. Each future
  tenant adds its own column-0 section to the parser's closed section list.
- `.aai/system/DOCS_AI_CANON.list` gains the exact line `project-config.yaml`
  under the files block, so a consumer's docs-audit does not report the file as
  non-canonical (measured: it does today).
- Not seeded, never written by any AAI script. The parser and the doctor only
  read it.

### D-FORMAT. What the file may say

Example (the whole feature):

```
# docs/ai/project-config.yaml - project-owned; /aai-update never writes it
routing_override@claude:
  Code Review: claude-sonnet-5-5
```

Line-based parse in `.aai/scripts/lib/project-config.mjs`, no YAML library:
- One leading UTF-8 BOM is stripped; lines split on `\r?\n`.
- A blank line, or a line whose trimmed text starts with `#`, is skipped
  anywhere.
- A column-0 line matching `^routing_override(?:@([^:\s]*))?:\s*$` opens a
  section. The suffix decides the section's fate:
  - one of `claude`, `codex`, `gemini`, `cursor` (exact, case-sensitive; the
    constant `OVERRIDE_HARNESSES` = `HARNESS_VALUES` minus `unknown`): active;
  - no `@` at all: IGNORED (an override that cannot name its harness would
    follow a project switching vendors, CHANGE-0192 AC-003);
  - any other suffix, including `unknown` (undetected is not a harness: an
    override keyed to it would apply to whatever undetected harness runs),
    `CLAUDE`, `codx` and the empty suffix: IGNORED.
  An ignored section yields one note naming its header; its rows are still
  validated (below) but never stored. Ignoring a section is NOT malformed.
- Every other column-0 non-comment line is an ERROR `unknown section` (this
  includes `effort_roles:`, `tiers:` and a key with an inline value). A header
  text that repeats an earlier header exactly is an ERROR `repeated section`.
- A row is an indented line matching `^ {2}(\S[^:#]*):\s*(\S+)\s*$` (the
  MODEL_ROUTING.yaml row shape: exactly two spaces, no inline comment). Any
  other indented non-comment line is an ERROR `malformed row`. A row before
  the first header is an ERROR `row outside a section`.
- The key, trimmed, must be one of the closed role set `OVERRIDE_ROLES` (the
  ten dispatch role names, equal to the key set of `TIERS` in
  orchestration-dispatch.mjs, pinned by TEST-3694), else ERROR `unknown role`.
  A lane key such as `Validation@lightweight` is therefore an unknown role.
- The value, after stripping one pair of matching single or double quotes, must
  match `^[A-Za-z0-9][A-Za-z0-9._:/\[\]-]*$` and must not be `null`, else ERROR
  `invalid model id`.
- The same key twice in one section is an ERROR `duplicate role`.
- ALL OR NOTHING: when any ERROR exists the result is malformed and carries no
  override at all. Function and code shapes the mutations rely on:
  `parseProjectConfig(text)` returns `{ ok, overrides, notes, errors }`
  (`overrides` a null-prototype map harness to null-prototype map role to
  model); its all-or-nothing line is
  `if (errors.length) return { ok: false, overrides: Object.create(null), notes, errors };`;
  the harness check is `if (!OVERRIDE_HARNESSES.includes(suffix))`;
  `loadProjectConfig(root)` returns `{ status, file, overrides, notes, errors }`
  with status `absent`, `ok` or `malformed`; `PROJECT_CONFIG_REL` is
  `'docs/ai/project-config.yaml'`.
- Each error string names the line number and the reason, for example
  `line 3: unknown role "Code Reveiw"`.

### D-RESOLVE. Where the override sits in resolution

- `overrideFor(overrides, harness, role)` (lib) returns the model or null; its
  first statement is `const h = overrides[harness];`.
- `suggestModel(out, routing, overrides = null)` gains a third parameter; every
  existing two-argument call resolves exactly as before. Inside it,
  `const override = overrideFor(...)` for the verdict's detected `out.harness`
  and `out.role`; only a `dispatch` verdict is resolved (unchanged guard).
- Shipped table absent (`routing` null): the result is the override, else null.
- Mode A: `let model = override ?? <the existing Mode A chain>`; the existing
  `validation_alternate` swap runs after it unchanged.
- Mode B: when the harness has no shipped map and there is no override, null as
  today; with an override and no shipped map, an empty map stands in. Then
  `let model = override ?? resolveModelFromMap(hmap, out.role, laneKey, out.suggested_tier);`
  and the existing per-harness validator-independence block runs after it
  unchanged (its condition line starts `if (model && out.role === 'Validation'`).
- The override is role-level: it beats the shipped `role@lane` row (for example
  `Validation@lightweight`), the shipped role row and the tier default.
- Validator independence wins over the consumer: an override equal to the
  recorded implementer model on a Validation dispatch is replaced by the same
  backstop as any routed model (Mode B: `tiers@H` at or above the routed tier,
  then `validation_alternate@H`, else keep and set
  `residual: single_model_harness_reuse`; Mode A: `validation_alternate`). This
  is SUBAGENT_PROTOCOL.md's validator rule; a consumer file cannot switch it
  off.
- Effort is not touched: `suggestEffort` and `harnessEffort` keep their
  arguments, and the consumer file cannot carry an effort section (unknown
  section).

### D-DISPATCH. What the dispatch prints

In `main()` of orchestration-dispatch.mjs, after `routing = loadModelRouting(root);`:
- `loadProjectConfig(root)` runs only for a `dispatch` verdict (no stderr noise
  on no_action or needs_llm ticks).
- stderr, one line each, prefix `orchestration-dispatch: NOTE — docs/ai/project-config.yaml`:
  every ignored section (naming the header and the allowed harnesses); for a
  malformed file every error, then one line saying the file is malformed and no
  override from it is applied; for an APPLIED override whose model is unpriced,
  one line naming harness, role and model and saying metrics cannot cost the run.
- `const applied = overrideFor(projectConfig.overrides, out.harness, out.role);`
  then `out.suggested_model = suggestModel(out, routing, projectConfig.overrides);`
  then the unchanged effort lines, then
  `if (applied !== null) out.model_override = { file: PROJECT_CONFIG_REL, harness: out.harness, role: out.role, model: applied };`.
  The key is additive and exists ONLY when an override applied. `model` is the
  consumer's value; `suggested_model` is the final value after the backstop, so
  the two differ exactly when the backstop swapped.
- `TIERS` is exported (`export { RULES, TIERS };`) for the drift test only.

### D-PRICE. Unpriced: applied and reported, not refused

- Priced means `runCostUsd(pricing, model, 1, 1) !== null` with the target's
  own `.aai/system/PRICING.yaml` through `lib/pricing.mjs` (the resolver
  metrics-flush uses, so alias and longest-prefix ids count as priced). The lib
  helper's test line is `if (runCostUsd(pricing, model, 1, 1) === null)`.
- An unpriced override is still applied. Refusing it would send the consumer
  back to editing the vendored table to adopt a model the central table does
  not price yet, which is the main reason to have an override at all. The
  cost gap is made visible instead: a dispatch NOTE whenever that override is
  applied, and a CAT-22 WARN while it exists. Metrics already record an
  unpriced run's cost as null, never as an estimate.

### D-DOCTOR. CAT-22 Project Config

`aai-doctor.mjs` imports from `./lib/project-config.mjs` and appends
`catProjectConfig(root)` after `catRoutingTables(root)` in `runDoctor`.
- File absent: returns null (`if (cfg.status === 'absent') return null;`), so
  every existing fixture and every consumer without the file is unaffected.
- Malformed: `CAT-22 WARN` naming the file, the words `no override applied` and
  every error.
- Valid with any ignored section or any unpriced override: `CAT-22 WARN` naming
  each active override, each ignored header and each unpriced id.
- Valid otherwise: `CAT-22 PASS` naming each active override, or
  `no routing overrides` when it has none.
- Each override is written by `describeOverride(o)` as `<harness>/<role> -> <model>`
  (body `return o.harness + '/' + o.role + ' -> ' + o.model;`), all of them on
  the one CAT-22 line (the doctor prints one line per category).
- `--json` carries `detail` = `{ file, status, overrides: [{ harness, role, model, priced }], ignored, errors }`.
- Never FAIL (only CAT-01/02/06 fail). `--strict` turns the WARN into exit 1, as
  for every other WARN. The WARN literal is `cat('CAT-22', 'Project Config', 'WARN'`.
- docs/product/aai-doctor.md documents CAT-22; SKILL_DOCTOR.prompt.md is not
  edited.

### D-NOTE. The UPGRADING note

Comment-only edit of `.aai/system/MODEL_ROUTING.yaml`: the sentences telling the
reader to re-apply a customization in this file after each update are replaced
by: an exception (a role pinned to another model on one harness) goes in the
project-owned `docs/ai/project-config.yaml` as a `routing_override@<harness>:`
section (docs/product/consumer-config.md), which no sync or update writes; the
table itself is kept current centrally (CHANGE-0192). The text keeps
`spec-update-installs-ref-guard-undisclosed Amendment 2` (TEST-639) and
`CHANGE-0192` (TEST-3660), contains no `re-apply` in any case, and names no
DRAFT id (the intake's number is assigned at merge). No non-comment line
changes, so `routing_meta` is not re-stamped.

### D-LIB. Distribution

- `.aai/scripts/lib/project-config.mjs` is listed under `core:` in
  `.aai/system/PROFILES.yaml` (import closure of the dispatch and the doctor).
  It imports only `./harness.mjs` and `./pricing.mjs`, both already core.
- `lib/` rather than a top-level script: the fixtures that vendor the dispatch
  (test-aai-downstream-autopilot.sh, test-aai-roadmap.sh) already copy
  `lib/*.mjs` whole, so the new import cannot strand them; the price is a full
  CI run for any PR touching the file, which suits a module two engines import.
- `install_doctor_copy` in test-aai-doctor.sh copies `lib/project-config.mjs`
  and `lib/pricing.mjs` as hard dependencies of every doctor copy
  (check-vendored-script-deps.mjs gates the rest).
- New suite `tests/skills/test-aai-project-config.sh`, row `aai-project-config`
  in tests/skills/suite-map.yaml with globs `.aai/scripts/lib/project-config.mjs`,
  `.aai/scripts/orchestration-dispatch.mjs`, `.aai/scripts/aai-doctor.mjs`,
  `.aai/system/MODEL_ROUTING.yaml`, `.aai/system/DOCS_AI_CANON.list`,
  `.aai/system/PROFILES.yaml`, the four sync and update twins and
  `docs/product/consumer-config.md`; the `aai-doctor` row gains
  `.aai/scripts/lib/project-config.mjs`; tests/skills/suite-weights.tsv gains
  the fallback-unsampled row (precedent: aai-model-effort).

### D-PARITY. Twin proof without touching the parity matrix

TEST-3680 imports `buildSource`, `defaultSetup`, `runMatrix` and `TWINS` from
tests/skills/lib/install-parity.mjs and runs two scenario objects of its own
(ids outside SPEC-0284's table, `filtered: true` so no stale check runs) with a
`ctx.setup` that first calls `defaultSetup` and then plants the customization:
- `CC-UP`: an `older-core` target, then step `update` (both twins update from
  the scratch source's `main`).
- `CC-SY`: a `base` target (current core install), then step `sync` with no
  profile.
In both, the planted state is a MODEL_ROUTING.yaml whose `roles@claude`
`Code Review` row names `claude-haiku-5-5`, and a consumer file whose bytes
carry a BOM and CRLF line ends. What it compares, per twin and scenario, and
nothing else: the step exit code is 0; the twin's output tree holds a
MODEL_ROUTING.yaml byte-equal to the scratch source's; the twin's output tree
holds a consumer file byte-equal to the planted bytes; and the run report lists
no divergence between the twins on either of these two paths. Other paths'
divergences are SPEC-0284's business and are not judged here. Without `pwsh`
the ps1 half is skipped with a printed SKIP line naming TEST-3680; the sh half
still runs.

### Owner extension 2026-11-14 (amends the decisions above)

Additive amendment of this frozen spec, disclosed with `spec-amend.mjs add`
(class contract). Authority: the owner's round_extension of 2026-11-14 (intake
"Owner extension 2026-11-14", AC-010..AC-015). Owner words: "K tomu pr 555 ...
Musí to aktualizovat pricing ale i cizí modely"; he chose all four additions
(full-table refresh, downstream pricing of override models, project prices,
cross-vendor overrides allowed).

Existing decisions amended by this block, each stated where it changes:
D-LOC (the file now has two tenants, routing_override and pricing), D-FORMAT
(the `pricing:` header is a known section; `null` is refused in any letter
case), D-DISPATCH (the model NOTEs move after the final suggested_model),
D-PRICE (priced now means the shipped table OR the project prices the id),
D-DOCTOR (CAT-22 also reports project prices, freshness and cross-vendor
overrides). Every other decision above stands unchanged.

### D-PSECTION. The `pricing:` section

Example (an override on codex to a model the shipped table does not price, and
its project price):

```
# docs/ai/project-config.yaml - project-owned; /aai-update never writes it
routing_override@codex:
  Code Review: acme-coder-2

pricing:
  acme-coder-2:
    input_usd_per_m: 1.20
    output_usd_per_m: 4.80
    source_url: https://acme.example/pricing
    last_verified_utc: "2026-11-14T06:00:00Z"
    provider: acme
```

Parse rules, same line-based parser, same all-or-nothing:
- A column-0 line whose text without trailing whitespace is exactly
  `pricing:` opens the pricing section (constant `PRICING_HEADER`). Any other
  `pricing`-prefixed header (`pricing@codex:`, `pricing: x`) stays an ERROR
  `unknown section`; a second `pricing:` is an ERROR `repeated section` (the
  existing seen-headers rule).
- Inside the section, a line matching `^ {2}(\S+):\s*$` opens a model entry.
  The key, after one pair of matching quotes is stripped, must match
  `^[A-Za-z0-9][A-Za-z0-9._/-]*$` (no brackets, no colon: lookup strips one
  bracket suffix before matching) and must not be `null` or `unknown` in any
  letter case, else ERROR `invalid model id`. A key repeated in the section is
  an ERROR `duplicate model`.
- A line matching `^ {4}([a-z_]+):\s*(.*?)\s*$` is a field of the current
  entry; before any entry it is an ERROR `field outside a model`. The field
  name must be in the closed list
  `const PRICE_FIELDS = Object.freeze(['input_usd_per_m', 'output_usd_per_m', 'source_url', 'last_verified_utc', 'provider', 'unverified_utc']);`
  checked by the line `if (!PRICE_FIELDS.includes(field))`, else ERROR
  `unknown field`; a field repeated in one entry is an ERROR `duplicate field`.
- Values, after one pair of matching quotes is stripped: the two rates must
  match `^[0-9]+([.][0-9]+)?$` (a non-negative decimal; `null` is
  refused, a project price exists to price), else ERROR `invalid rate`;
  `source_url` must match `^https://\S+$`, else ERROR `invalid source_url`;
  `last_verified_utc` and `unverified_utc` must match
  `^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$` and round-trip through `Date`
  unchanged, else ERROR `invalid timestamp`; `provider` must match
  `^[a-z][a-z0-9-]*$`, else ERROR `invalid provider`. An inline comment makes
  the value invalid (no comment stripping).
- An entry lacking `input_usd_per_m`, `output_usd_per_m`, `source_url` or
  `last_verified_utc` when its section ends is an ERROR naming the entry's line
  and the missing field. `provider` and `unverified_utc` are optional.
- Any other indented non-comment line in the section is an ERROR
  `malformed row` (a three-space or tab indent included). Blank and comment
  lines are skipped as everywhere else.
- `parseProjectConfig` returns `{ ok, overrides, prices, notes, errors }`;
  `prices` is a null-prototype map id to
  `{ input, output, source_url, last_verified_utc, provider, unverified_utc, line }`
  (`provider` and `unverified_utc` null when absent). The all-or-nothing line
  becomes
  `if (errors.length) return { ok: false, overrides: Object.create(null), prices: Object.create(null), notes, errors };`
  so a malformed pricing section also voids every override, and a malformed
  routing section voids every price. `loadProjectConfig` passes `prices`
  through (empty for absent and malformed).
- One table for the project: the section has no harness suffix. A price is
  not restricted to override ids (a project may price a runtime id its harness
  records, for example a null-priced shipped row such as `cursor-grok-4.6`).

### D-FORMAT-2. `null` in any letter case

The routing row's null test becomes the line
`const isNullId = model.toLowerCase() === 'null';` (used where the literal
`model === 'null'` comparison stood), so `NULL` and `Null` are refused like
`null` (closes `fu-project-config-null-model-casing`).

### D-PREC. Precedence and the one costing seam

- Shipped wins: a project price is used only when the shipped table cannot cost
  the id. The shipped table is refreshed monthly against primary sources and
  replaced on every update; a project row must not shadow it after the shipped
  table learns the id. A shadowed project row is reported (D-FRESH), never used.
- The seam is `lib/pricing.mjs`, so every cost reader gets the same answer:
  - `parsePricing` additionally returns `sources` (null-prototype map source id
    to `{ provider }`) and each model's `source_ref` (additive keys; existing
    readers ignore them).
  - `attachProjectPrices(pricing, prices)` returns a copy of `pricing` with
    `project: prices`.
  - `resolveProjectKey(prices, id)`: strip ONE trailing bracket suffix, then
    exact key, then the longest key that is a prefix of the id, else null. No
    alias step (aliases belong to the shipped table).
  - private `rateEntry(pricing, modelId)`, used by both `runCostUsd` and
    `blendedCostUsd` in place of their direct `pricing.models[...]` lookups:
    first statement `const shipped = pricing.models[resolveModelKey(pricing, modelId)];`,
    then `if (hasRates(shipped)) return shipped;`, then
    `const project = pricing.project ? pricing.project : null;`, then the
    project lookup through `resolveProjectKey`, else null. `hasRates` is the
    existing both-rates-finite test, factored out.
  - `priceSource(pricing, modelId)` returns `'shipped'`, `'project'` or null
    by the same order.
  - `modelProvider(pricing, modelId)`: when `resolveModelKey` lands on a key
    other than `unknown`, `sources[<that row's source_ref>].provider` (null if
    the source has none); otherwise the project row's `provider` through
    `resolveProjectKey`; otherwise null.
- The loader lives in `lib/project-config.mjs` (it already imports
  lib/pricing.mjs; the reverse would be a cycle):
  `loadCostPricing(root, pricingPath, cfg = loadProjectConfig(root))` returns
  `loadPricing(pricingPath)` with the project prices attached when
  `cfg.status === 'ok'`, else the shipped pricing alone.
  `isPricedModel(pricing, model)` keeps its body (`runCostUsd` now sees the
  fallback).

### D-PWIRE. The four consumers

Each replaces its one load site, nothing else:
- metrics-flush.mjs: `const pricing = loadCostPricing(root, pricingPath);`
  (`root` is the existing `repoRootOf(statePath)`; `--pricing` keeps working).
- metrics-report.mjs: `const pricing = loadCostPricing(process.cwd(), pricingPath);`
  (the base every one of its default paths resolves against).
- orchestration-dispatch.mjs: `const costPricing = loadCostPricing(root, path.join(root, '.aai', 'system', 'PRICING.yaml'), projectConfig);`
  read only when an override applied.
- aai-doctor.mjs `catProjectConfig`: the same call with the config it already
  loaded.
A malformed file gives every consumer the shipped pricing alone; metrics-flush
and metrics-report print nothing about it (the dispatch NOTE and CAT-22 do).
No METRICS.jsonl field is added (R13).

### D-DISPATCH-2. Model NOTEs after the final model

Amends D-DISPATCH: `out.suggested_model` is resolved first; then, guarded by
the line `if (applied !== null && out.suggested_model === applied)`, at most
two NOTEs, each one line with the existing prefix and `describeOverride`:
- unpriced (D-PRICE as amended: `isPricedModel(costPricing, applied)` is false,
  that is neither the shipped table nor a project price can cost it), text
  unchanged: `<harness>/<role> -> <model> is unpriced: metrics cannot cost the run`;
- cross-vendor (D-VENDOR).
A Validation override the backstop swapped is therefore not NOTEd (the model
that runs is a shipped one; closes `fu-unpriced-note-before-backstop-swap`).
The ignored-section and malformed NOTEs stay where they are, before the model
NOTEs. `model_override` is unchanged.

### D-FRESH. CAT-22 reports project prices and their age

- Horizon: `AAI_TABLES_HORIZON_DAYS` when it is a positive integer, else the
  `horizon_days` that `checkTables(root)` (table-freshness.mjs, already imported
  by the doctor) reports for `.aai/system/PRICING.yaml`, which is its
  `update_policy.cadence_days`; when that table is ABSENT or INVALID the
  horizon is null.
- `projectPriceRows(cfg, pricing, { now, horizonDays })` in the lib returns one
  row per project price: `{ model, provider, source_url, last_verified_utc,
  unverified_utc, age_days, stale, shadowed }`, with
  `stale: horizonDays !== null && ageDays > horizonDays` (the CAT-21 LAPSED
  rule, age in whole days) and `shadowed` true when `priceSource` over the
  shipped pricing alone is `'shipped'`.
- CAT-22 WARN when any row is stale, naming
  `<id> verified <YYYY-MM-DD> age=<n>d > <h>d`; WARN when the horizon is null
  and a project price exists, naming
  `project price freshness cannot be judged (PRICING.yaml cadence unreadable)`.
  The existing WARN reasons stand (malformed, ignored section, unpriced, where
  unpriced now means neither table prices the override).
- Named on the CAT-22 line without changing PASS to WARN: each project-priced
  override (`<desc> priced by project`), each shadowed row
  (`<id> shadowed by shipped PRICING`), each `unverified_utc`
  (`<id> unverified since <YYYY-MM-DD>`), each cross-vendor override (D-VENDOR).
  A file with prices and no overrides is PASS
  `no routing overrides; project prices: <id>, ...`.
- `--json` detail gains `prices` (the rows above), `horizon_days`, and per
  override `price_source` (`shipped`, `project` or null), `vendor` (string or
  null) and `cross_vendor` (boolean). `priced` stays and equals
  `price_source !== null`.

### D-VENDOR. Cross-vendor overrides are applied and named

- Harness vendor, a constant in the lib:
  `HARNESS_VENDOR` = claude `anthropic`, codex `openai`, gemini `google`,
  cursor null (cursor hosts several vendors' models, so nothing on cursor is
  cross-vendor). Its keys equal `OVERRIDE_HARNESSES` and every non-null value
  is a `provider:` of the shipped PRICING `sources:` (pinned by TEST-3702).
- Model vendor: `modelProvider(costPricing, model)` (D-PREC): shipped row's
  source provider, else the project row's `provider`, else null.
- `overrideVendor(pricing, harness, model)` returns
  `{ vendor, harnessVendor, crossVendor }` with the line
  `const crossVendor = hv !== null && mv !== null && mv !== hv;`.
- Dispatch: a cross-vendor override is applied exactly as any other (no
  refusal, no swap). Under the D-DISPATCH-2 guard it prints one NOTE:
  `<harness>/<role> -> <model> is cross-vendor: a <vendor> model on the <harness> harness (<harnessVendor>); applied`.
- Unknown vendor (an id neither table knows, a proxy or gateway id without a
  project `provider`): applied, no vendor NOTE. Reason: such an id is either
  unpriced (one NOTE already says so) or priced by a project row whose author
  can add `provider:` to make the check apply; a second NOTE for the same
  override would double the noise and break TEST-3688's exactly-one-line pin.
  CAT-22 detail carries `vendor: null` for it.
- CAT-22 names `<desc> (cross-vendor: <vendor> on <harness>)` on its line; it
  does not by itself turn PASS into WARN (an intended choice, not a defect).

### D-FULL. Upstream: the whole PRICING table, every run

- PRICING.yaml row schema gains one optional field, documented in the file's
  header comment block (comment-only edit, no row changes, so no re-stamp):
  `unverified_utc: "<run stamp>"`, meaning the refresh at that stamp tried and
  could not verify the row from a primary source; its rates and
  `last_verified_utc` stay as they were. A later successful verification
  removes the field. `lib/pricing.mjs` ignores it (the rates still cost).
- `table-freshness.mjs priced --since <YYYY-MM-DD> [--root <dir>]`, one line
  per `models:` row except `unknown`, in file order:
  `OK <id> <last_verified>` when `last_verified_utc` is on or after the date;
  else `UNVERIFIED <id> <unverified_utc> last=<last_verified>` when
  `unverified_utc` is on or after the date; else `STALE <id> <last_verified>`;
  `INVALID <id> <field>` for a present but unparseable `last_verified_utc` or
  `unverified_utc`. Exit 0 when no STALE and no INVALID line, 1 otherwise, 2 on
  a usage error; an absent PRICING.yaml prints
  `INVALID .aai/system/PRICING.yaml file is absent` and exits 1. Code shape:
  `pricingRows` gains `unverified`; the classification line is
  `const marked = u !== null && u >= sinceMs;`.
- Routine upstream mode: Step 1 reads the pricing page of every provider named
  in PRICING `sources:` (anthropic, openai, google, deepseek, xai today) plus
  the Cursor docs for cursor rows. Step 2: every `models:` row except `unknown`
  ends the run in exactly one state, re-verified (rates and
  `last_verified_utc` = run stamp, any `unverified_utc` removed; a null-priced
  row whose vendor still publishes no list price counts as re-verified with
  null rates) or marked (`unverified_utc` = run stamp, nothing else changed),
  and the table stamps move (stamp-guard requires it: a mark is a priced-line
  change). Routed ids that end marked also go into `TEST_3668_ALLOW_STALE` as
  today. Step 3 adds `node .aai/scripts/table-freshness.mjs priced --since <today>`,
  which must exit 0. The PR body lists every marked row.
- No rate is edited by hand in this ride; o3 and the other rows of
  `fu-pricing-unverified-rows` are left to the first full-table run (R12).

### D-DOWN. Downstream mode

Step 0 becomes a mode decision:
1. `git ls-files --error-unmatch .aai/system/MODEL_ROUTING.yaml .aai/system/PRICING.yaml tests/skills/test-aai-pricing.sh`
   succeeds: UPSTREAM mode (Steps 1 to 5, D-FULL). The suite path keeps a
   consumer that commits its `.aai/` out of upstream mode.
2. Otherwise, `.aai/system/PRICING.yaml` exists in the working tree (a vendored
   install): DOWNSTREAM mode, steps D1 to D7 below. Otherwise report
   `no AAI install` and STOP.
3. The tool probes stay as they are.

Downstream steps (the routine text carries them in this order):
- D1. Run `node .aai/scripts/aai-doctor.mjs --json` and read the `CAT-22`
  entry. No entry (no file) or an empty `detail.overrides`: report
  `no overrides to price` and STOP, a successful run, no branch. `detail.status`
  `malformed`: report its `errors` and STOP; never edit a malformed file.
- D2. Work list: every override whose `price_source` is null, every
  `detail.prices` row with `stale` true whose id the shipped table still does
  not price, and every row with `shadowed` true (to delete). Nothing else is
  researched, and never the shipped table.
- D3. For each id to price: read the vendor's own pricing page (primary sources
  only, as Step 1; the vendor named by `provider` when known). Verified: write
  or replace its entry under `pricing:` with both rates, `source_url`,
  `last_verified_utc` = run stamp and `provider`, removing `unverified_utc`.
  Not verifiable: an existing entry gets `unverified_utc` = run stamp and is
  otherwise kept; with no entry nothing is written and the id is listed as
  unpriced in the PR (never an invented number).
- D4. Delete every shadowed entry. Edit only the `pricing:` section of
  `docs/ai/project-config.yaml`: never a `routing_override` row, never
  anything under `.aai/`, never another file, no CHANGELOG.
- D5. Re-run `node .aai/scripts/aai-doctor.mjs --json`: CAT-22 must not be
  `malformed` and every verified id must show `price_source` `project` on its
  override. Otherwise discard the routine's own edit on its branch and STOP
  with a report.
- D6. Branch `chore/project-prices-<YYYY-MM>`, commit only
  `docs/ai/project-config.yaml`, push, open the PR with `gh pr create` (GitHub
  MCP `create_pull_request` as fallback). The body lists verified ids with
  URLs, marked ids, unpriced ids and deleted shadowed entries. NEVER merge.
- D7. Run report, as Step 5.
Safety rules gain the downstream write scope (that one file and one branch).
The routine's placeholders are unchanged; `{{REPO}}` names the consumer's
repository when it is instantiated there.

### D-DIST-2. Distribution and suite selection

- No new `.aai/**` file (no PROFILES.yaml entry), no prompt-corpus byte (no
  diet-ledger entry, no TEST-012 bump). DOCS_AI_CANON.list unchanged.
- tests/skills/suite-map.yaml: `aai-routine` globs gain
  `.aai/routines/ROUTING_REFRESH.routine.md`; `aai-project-config` globs gain
  `.aai/scripts/lib/pricing.mjs`, `.aai/scripts/metrics-flush.mjs`,
  `.aai/scripts/metrics-report.mjs`, `.aai/scripts/table-freshness.mjs`,
  `.aai/system/PRICING.yaml` and `.aai/routines/ROUTING_REFRESH.routine.md`;
  `aai-pricing` globs gain `.aai/scripts/lib/pricing.mjs` and
  `.aai/routines/ROUTING_REFRESH.routine.md`.
- metrics-flush.mjs (core) and metrics-report.mjs (extended) newly import
  `./lib/project-config.mjs` (core) and through it `./lib/harness.mjs` (core);
  `node .aai/scripts/check-vendored-script-deps.mjs` must stay exit 0, and any
  fixture that copies these scripts with an explicit lib list gains the two
  libs.
- docs/product/universal-routines.md documents downstream mode (the same
  owner command with the consumer's `--repo`).
- TEST-3680 (D-PARITY) plants a consumer file that also carries a valid
  `pricing:` section (BOM and CRLF kept); nothing else in D-PARITY changes.

## Acceptance Criteria Mapping

- Intake AC-001 (file outside .aai/ that no twin writes; update proof both
  twins) maps to Spec-AC-01 and Spec-AC-11.
- Intake AC-002 (override changes suggested_model only for the named role on
  the named harness) maps to Spec-AC-02 and Spec-AC-03.
- Intake AC-003 (no harness or out-of-set harness ignored with NOTE) maps to
  Spec-AC-04.
- Intake AC-004 (absence byte-identical) maps to Spec-AC-05.
- Intake AC-005 (malformed: NOTE, doctor finding, no half-apply) maps to
  Spec-AC-06 and Spec-AC-08.
- Intake AC-006 (unpriced reported) maps to Spec-AC-07.
- Intake AC-007 (doctor names each active override) maps to Spec-AC-08.
- Intake AC-008 (UPGRADING note) maps to Spec-AC-09.
- Intake AC-009 (effort, harness effort, freshness stamp unaffected) maps to
  Spec-AC-10.
- Intake "product doc for the capability" and the release-notes duty map to
  Spec-AC-12.
- Extension 2026-11-14 (amendment): intake AC-010 (full-table refresh, rows
  verified or marked) maps to Spec-AC-17 and Spec-AC-18; AC-011 (downstream
  mode) maps to Spec-AC-19; AC-012 (project prices, shipped wins, four
  consumers, all or nothing) maps to Spec-AC-13, Spec-AC-14 and amended
  Spec-AC-07; AC-013 (freshness warning) maps to Spec-AC-15; AC-014
  (cross-vendor applied and named) maps to Spec-AC-16; AC-015 (docs, examples,
  ownership proof, CHANGELOG) maps to amended Spec-AC-01, Spec-AC-20 and
  Spec-AC-21.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN a scratch target carrying a customized shipped MODEL_ROUTING.yaml and a docs/ai/project-config.yaml with BOM and CRLF bytes that carries a routing_override section and a valid pricing section is updated (older-core target, step update) or re-synced (core base, step sync) by the bash twin and by the PowerShell twin the system SHALL exit 0 in every run, leave MODEL_ROUTING.yaml byte-equal to the source table, leave docs/ai/project-config.yaml byte-equal to the planted bytes, and report no twin divergence on either path | implementing | tests/skills/test-aai-project-config.sh TEST-3680 (pre-extension evidence mutation-TEST-3680.txt and VALIDATION-20261114T0123Z, re-earned over the new planted bytes) | — | D-PARITY, D-DIST-2; non-regression, RED is the mutation record; AMENDED 2026-11-14: planted file gains a pricing section |
| Spec-AC-02 | WHEN docs/ai/project-config.yaml holds routing_override@claude with Code Review set to claude-sonnet-5-5 the system SHALL resolve suggested_model claude-sonnet-5-5 and add model_override naming file, harness claude, role Code Review and the model for a Code Review dispatch on claude, and SHALL resolve every other role on claude and every role on codex, gemini, cursor and unknown exactly as without the file, for the shipped Mode B table, a Mode A table and an absent table; an override on cursor SHALL apply although the shipped table has no cursor map | done | tests/skills/test-aai-project-config.sh TEST-3681; mutation docs/ai/tdd/spec-consumer-config-routing-override/mutation-TEST-3681.txt; tests/skills/test-aai-project-config.sh TEST-3682; mutation docs/ai/tdd/spec-consumer-config-routing-override/mutation-TEST-3682.txt; docs/ai/reports/VALIDATION-20261114T0123Z-consumer-config-routing-override.md | — | D-FORMAT, D-RESOLVE |
| Spec-AC-03 | WHEN an override names Validation on claude the system SHALL use it on a lightweight-lane Validation dispatch over the shipped Validation@lightweight row; WHEN that override equals the recorded implementer model the validator-independence backstop SHALL still replace it from the harness's own map (Mode B) or validation_alternate (Mode A), or set residual single_model_harness_reuse when no other id exists, while model_override.model keeps the consumer's value | done | tests/skills/test-aai-project-config.sh TEST-3683; mutation docs/ai/tdd/spec-consumer-config-routing-override/mutation-TEST-3683.txt; tests/skills/test-aai-project-config.sh TEST-3684; mutation docs/ai/tdd/spec-consumer-config-routing-override/mutation-TEST-3684.txt; docs/ai/reports/VALIDATION-20261114T0123Z-consumer-config-routing-override.md | — | D-RESOLVE; consumer cannot switch off validator independence |
| Spec-AC-04 | WHEN the file holds a routing_override section with no harness suffix, or a suffix outside claude, codex, gemini and cursor (unknown, CLAUDE, codx, empty) the system SHALL print one stderr NOTE per such header naming it, apply none of its rows, and still apply the valid sections of the same file; aai-doctor SHALL report CAT-22 WARN naming each ignored header | done | tests/skills/test-aai-project-config.sh TEST-3685; mutation docs/ai/tdd/spec-consumer-config-routing-override/mutation-TEST-3685.txt; docs/ai/reports/VALIDATION-20261114T0123Z-consumer-config-routing-override.md | — | D-FORMAT ignored sections are not malformed |
| Spec-AC-05 | WHEN the file is absent, or holds only entries matching no harness and role of the tick, or holds only comments, the system SHALL print dispatch stdout and exit code byte-identical to the pre-ride dispatch script (blob 73668e4c1730c5e98f45a5bdcf94f866f0fc5e58) on the same fixture, with no model_override key and no project-config NOTE on stderr | done | tests/skills/test-aai-project-config.sh TEST-3686; mutation docs/ai/tdd/spec-consumer-config-routing-override/mutation-TEST-3686.txt; docs/ai/reports/VALIDATION-20261114T0123Z-consumer-config-routing-override.md | — | Non-regression, RED is the mutation record |
| Spec-AC-06 | WHEN the file holds any of an unknown column-0 section (including effort_roles and a key with an inline value), a repeated section header, a row outside a section, a tab-indented row, a row with an inline comment, a duplicate role, an unknown role (including a lane key), or an invalid model id (null, empty, containing a space or hash) next to an otherwise valid matching override the system SHALL apply no override from the file, print one stderr NOTE per error naming the line and reason plus one NOTE that no override is applied, and resolve suggested_model as without the file; a file with BOM, CRLF, quoted values and indented comments SHALL parse; the closed role set SHALL equal the dispatch TIERS keys | done | tests/skills/test-aai-project-config.sh TEST-3687; mutation docs/ai/tdd/spec-consumer-config-routing-override/mutation-TEST-3687.txt; tests/skills/test-aai-project-config.sh TEST-3694; mutation docs/ai/tdd/spec-consumer-config-routing-override/mutation-TEST-3694.txt; docs/ai/reports/VALIDATION-20261114T0123Z-consumer-config-routing-override.md | — | D-FORMAT all or nothing |
| Spec-AC-07 | WHEN an applied override that stays the final suggested_model names a model id that neither the shipped PRICING.yaml nor a project price can cost (runCostUsd over loadCostPricing is null) the system SHALL still apply it, print one stderr NOTE naming harness, role and model as unpriced, and aai-doctor SHALL report CAT-22 WARN naming it; an exact, bracket-suffixed or prefix-resolvable shipped-priced id, an id priced only by the project pricing section, and a Validation override the backstop replaced SHALL produce no unpriced NOTE, and the suggested_model of a priced override SHALL cost to a non-null number through runCostUsd | implementing | tests/skills/test-aai-project-config.sh TEST-3688 (pre-extension evidence mutation-TEST-3688.txt and VALIDATION-20261114T0123Z); tests/skills/test-aai-project-config.sh TEST-3700 | — | D-PRICE as amended by D-PREC and D-DISPATCH-2; seam dispatch to metrics pricing; AMENDED 2026-11-14: project fallback and final-model guard |
| Spec-AC-08 | WHEN aai-doctor runs over a tree with a valid file holding two overrides it SHALL print one CAT-22 PASS line naming each as harness/role -> model and carry detail.overrides with one object per override in --json; a valid file with none SHALL give CAT-22 PASS no routing overrides; a malformed file SHALL give CAT-22 WARN naming no override applied and the errors, exit 0 without --strict and 1 with it; no file SHALL give no CAT-22 line and the existing clean-fixture cases SHALL stay green | done | tests/skills/test-aai-doctor.sh TEST-3689; mutation docs/ai/tdd/spec-consumer-config-routing-override/mutation-TEST-3689.txt; docs/ai/reports/VALIDATION-20261114T0123Z-consumer-config-routing-override.md | — | D-DOCTOR |
| Spec-AC-09 | MODEL_ROUTING.yaml SHALL contain no case-insensitive re-apply, SHALL name docs/ai/project-config.yaml and routing_override, SHALL keep CHANGE-0192 and spec-update-installs-ref-guard-undisclosed Amendment 2, SHALL name no CHANGE-DRAFT id, and table-freshness stamp-guard against the merge-base with origin/main SHALL exit 0 with a non-VIOLATION verdict line for MODEL_ROUTING (UNCHANGED for this comment-only edit; a later correctly re-stamped refresh prints CHANGED-STAMPED and still passes) | done | tests/skills/test-aai-project-config.sh TEST-3690; mutation docs/ai/tdd/spec-consumer-config-routing-override/mutation-TEST-3690.txt; docs/ai/reports/VALIDATION-20261114T0123Z-consumer-config-routing-override.md | — | D-NOTE; comment-only, no re-stamp |
| Spec-AC-10 | For every dispatch role on claude, codex, gemini and cursor the system SHALL resolve suggested_effort and harness_effort identically with and without an override file, and table-freshness check SHALL print identical output with and without the file | done | tests/skills/test-aai-project-config.sh TEST-3691; mutation docs/ai/tdd/spec-consumer-config-routing-override/mutation-TEST-3691.txt; docs/ai/reports/VALIDATION-20261114T0123Z-consumer-config-routing-override.md | — | Non-regression, RED is the mutation record |
| Spec-AC-11 | PROFILES.yaml SHALL list .aai/scripts/lib/project-config.mjs under core and DOCS_AI_CANON.list SHALL carry the exact line project-config.yaml; WHEN aai-sync.sh --profile core installs into a scratch git target the target SHALL hold no docs/ai/project-config.yaml, and after the file is added the target's own dispatch SHALL apply the override on claude and not on codex, its own doctor SHALL print CAT-22 naming it, its own docs-audit SHALL report no non-canonical entry for it, and git check-ignore SHALL exit 1 for it; select-suites SHALL select aai-project-config for a diff touching only aai-sync.ps1 | done | tests/skills/test-aai-project-config.sh TEST-3692; mutation docs/ai/tdd/spec-consumer-config-routing-override/mutation-TEST-3692.txt; tests/skills/test-aai-project-config.sh TEST-3693; mutation docs/ai/tdd/spec-consumer-config-routing-override/mutation-TEST-3693.txt; docs/ai/reports/VALIDATION-20261114T0123Z-consumer-config-routing-override.md | — | D-LOC, D-LIB; seam sync to consumer readers |
| Spec-AC-12 | CHANGELOG.md SHALL gain exactly one per-entry heading for this change, unreleased or rolled, whose body names docs/ai/project-config.yaml, routing_override and CAT-22; docs/product/consumer-config.md SHALL exist with capability consumer-config and name the file path, the section form, the four harnesses, all-or-nothing, the unpriced rule, CAT-22 and that no sync or update writes the file; docs/product/aai-doctor.md SHALL document CAT-22 Project Config | done | tests/skills/test-aai-project-config.sh TEST-3695; mutation docs/ai/tdd/spec-consumer-config-routing-override/mutation-TEST-3695.txt; docs/ai/reports/VALIDATION-20261114T0123Z-consumer-config-routing-override.md | — | Consumer-visible; release-notes gate |
| Spec-AC-13 | WHEN docs/ai/project-config.yaml holds a pricing section the system SHALL parse each entry's input_usd_per_m, output_usd_per_m, source_url, last_verified_utc and optional provider and unverified_utc; WHEN the file holds, next to a valid matching routing override, any of a missing required field, an unknown field, a repeated field, a negative, null or non-numeric rate, an invalid source_url, timestamp or provider, a field before any entry, a duplicate model key, a key that is null, NULL, unknown or bracketed, a three-space or tab indent, a pricing@codex header or a second pricing header, the dispatch SHALL apply no override and print one NOTE per error naming line and reason plus the no-override NOTE, and loadCostPricing SHALL attach no project price; a routing row whose model is NULL or Null SHALL be an invalid model id | planned | tests/skills/test-aai-project-config.sh TEST-3696 | — | D-PSECTION, D-FORMAT-2; all or nothing across both tenants |
| Spec-AC-14 | WHEN loadCostPricing reads a valid file the system SHALL cost an id the shipped table prices at the shipped rates even when the project prices the same id differently, SHALL cost an id the shipped table cannot (an unknown id, the null-priced shipped row cursor-grok-4.6, a bracket-suffixed and a prefix-extended spelling of a project key) at the project rates through runCostUsd and blendedCostUsd, SHALL return shipped, project or null from priceSource accordingly, and SHALL attach nothing for a malformed file; metrics-flush over a fixture STATE whose run recorded tokens_in and tokens_out on a project-priced id SHALL write that run with cost_usd equal to the project-rate arithmetic and cost_basis decomposed, and null without the file; metrics-report SHALL fill a null ledger cost from the project price | planned | tests/skills/test-aai-project-config.sh TEST-3697; tests/skills/test-aai-project-config.sh TEST-3698; tests/skills/test-aai-project-config.sh TEST-3699 | — | D-PREC, D-PWIRE; seam project file to the metrics ledger |
| Spec-AC-15 | WHEN aai-doctor runs over a tree whose file prices an id with last_verified_utc older than the horizon (AAI_TABLES_HORIZON_DAYS, else the shipped PRICING update_policy.cadence_days) it SHALL print CAT-22 WARN naming the id, its verified date and its age over the horizon, exiting 0 without --strict and 1 with it; a price verified yesterday SHALL give no freshness WARN; a project-priced override SHALL be named priced by project; a row the shipped table also prices SHALL be named shadowed without a WARN; a project price under an unreadable PRICING cadence SHALL give a WARN that freshness cannot be judged; --json detail SHALL carry prices with age_days, stale and shadowed, horizon_days, and per override price_source, vendor and cross_vendor | planned | tests/skills/test-aai-doctor.sh TEST-3701 | — | D-FRESH, D-DOCTOR amended |
| Spec-AC-16 | WHEN routing_override@codex sets Code Review to claude-sonnet-5-5 the dispatch under AAI_HARNESS=codex SHALL suggest claude-sonnet-5-5, carry model_override and print exactly one stderr NOTE naming codex/Code Review -> claude-sonnet-5-5 as cross-vendor with anthropic and openai; the same id under claude and under cursor, and an id no table knows under codex, SHALL print no cross-vendor NOTE; a project-priced id with provider anthropic under codex SHALL print it; aai-doctor CAT-22 SHALL name the cross-vendor override and stay PASS when nothing else warns; HARNESS_VENDOR keys SHALL equal OVERRIDE_HARNESSES and each non-null value SHALL be a provider in the shipped PRICING sources | planned | tests/skills/test-aai-project-config.sh TEST-3702 | — | D-VENDOR; applied, never blocked |
| Spec-AC-17 | WHEN table-freshness.mjs priced --since D runs over a fixture PRICING it SHALL print OK for a row verified on or after D, UNVERIFIED for a row whose unverified_utc is on or after D, STALE for a row with neither, INVALID for an unparseable timestamp, no line for unknown, and exit 0 only when no STALE or INVALID line, 1 otherwise and 2 for a missing or malformed --since; stamp-guard SHALL report VIOLATION when a fixture adds unverified_utc to a row without moving pricing_meta.last_updated_utc and CHANGED-STAMPED when the stamp moves; runCostUsd SHALL cost a marked row at its kept rates; the shipped PRICING.yaml SHALL document unverified_utc in a comment and stamp-guard against the merge-base SHALL print UNCHANGED for PRICING | planned | tests/skills/test-aai-pricing.sh TEST-3703 | — | D-FULL; never silently kept |
| Spec-AC-18 | WHEN ROUTING_REFRESH renders for claude, codex, gemini and generic the render SHALL name every models: row as in scope, unverified_utc, table-freshness.mjs priced, TEST_3668_ALLOW_STALE and the re-stamp of both tables, and SHALL name each provider listed under sources: in the shipped PRICING.yaml (read from the table at test time); it SHALL still carry no merge command | planned | tests/skills/test-aai-routine.sh TEST-3704 | — | D-FULL; seam table sources to routine |
| Spec-AC-19 | WHEN ROUTING_REFRESH renders it SHALL carry a downstream mode chosen when git ls-files of the tables and tests/skills/test-aai-pricing.sh fails and .aai/system/PRICING.yaml exists, naming aai-doctor.mjs --json, CAT-22, price_source, stale, shadowed, docs/ai/project-config.yaml, the pricing: section, chore/project-prices-, gh pr create, NEVER merge and a rule never to edit .aai/, and SHALL no longer carry the line tables are refreshed upstream; run /aai-update; aai-doctor --json over a fixture consumer with an unpriced override, a stale price and a shadowed price SHALL emit CAT-22 detail whose override carries price_source null and whose prices carry stale true and shadowed true | planned | tests/skills/test-aai-routine.sh TEST-3705 | — | D-DOWN; seam doctor JSON to routine |
| Spec-AC-20 | The single CHANGELOG heading TEST-3695 counts SHALL have a body naming pricing:, cross-vendor, ROUTING_REFRESH and table-freshness.mjs priced; docs/product/consumer-config.md SHALL show a pricing: example and routing_override@codex: and routing_override@gemini: examples and state shipped wins, the cross-vendor rule and the CAT-22 freshness WARN; docs/product/universal-routines.md SHALL describe downstream mode naming docs/ai/project-config.yaml; docs/product/aai-doctor.md SHALL name the project price freshness WARN of CAT-22 | planned | tests/skills/test-aai-project-config.sh TEST-3706 | — | Consumer-visible; written after the flush |
| Spec-AC-21 | select-suites SHALL name aai-routine and aai-pricing for a file list of only .aai/routines/ROUTING_REFRESH.routine.md, and aai-project-config for only .aai/scripts/lib/pricing.mjs, only .aai/scripts/metrics-flush.mjs and only .aai/scripts/metrics-report.mjs; check-vendored-script-deps.mjs SHALL exit 0; the diff against the merge-base with origin/main SHALL add no file under .aai/ and change no .aai/*.prompt.md file | planned | tests/skills/test-aai-project-config.sh TEST-3707 | — | D-DIST-2 |

## Implementation plan

1. `.aai/scripts/lib/project-config.mjs` (new): constants `PROJECT_CONFIG_REL`,
   `OVERRIDE_HARNESSES`, `OVERRIDE_ROLES`; `parseProjectConfig(text)`,
   `loadProjectConfig(root)`, `overrideFor(overrides, harness, role)`,
   `isPricedModel(root, model)` (or a pricing object passed in),
   `unpricedOverrides(root, overrides)`, `describeOverride(o)`,
   `projectConfigNotes(cfg)` (the NOTE texts shared by dispatch and doctor).
   Null-prototype maps throughout (a role or harness named `constructor` must
   never hit an inherited member, the PR #376 lesson).
2. `orchestration-dispatch.mjs`: import; `suggestModel` third parameter
   (D-RESOLVE); `main()` wiring (D-DISPATCH); `export { RULES, TIERS };`.
3. `aai-doctor.mjs`: `catProjectConfig(root)` (D-DOCTOR) after
   `catRoutingTables(root)`; header comment line for CAT-22; the
   `runDoctor` filter comment names CAT-22 among the null-when-absent ones.
4. `MODEL_ROUTING.yaml` UPGRADING comment (D-NOTE). `PROFILES.yaml` core entry,
   `DOCS_AI_CANON.list` line (D-LOC, D-LIB).
5. Tests TEST-3680..3695 in house style under `set -euo pipefail`; nested CLI
   calls with `env -u AAI_ROLE`; dispatch fixtures force `AAI_HARNESS` (the
   runner itself sets CLAUDECODE, so an unforced fixture would detect claude);
   every new test function wired into `main()` (hygiene test_093).
   Fixture roots for CLI dispatch follow test-aai-orchestration-dispatch.sh
   (`mk_root`, `write_dstate`, `cp -r .aai/scripts`); the pre-ride script for
   TEST-3686 is materialized with `git cat-file -p` of the pinned blob, as
   `pre_harness_dispatch_tree` does.
6. suite-map row, aai-doctor glob, suite-weights row, then CHANGELOG and
   product docs last (after the loop's flush, per the ship order).

Extension 2026-11-14 (after the steps above, run order E1, E2, E3, docs):
7. lib/pricing.mjs: `sources` and `source_ref` in `parsePricing`, `hasRates`,
   `rateEntry`, `attachProjectPrices`, `resolveProjectKey`, `priceSource`,
   `modelProvider` (D-PREC).
8. lib/project-config.mjs: the `pricing:` section and `prices` (D-PSECTION),
   the null casing (D-FORMAT-2), `loadCostPricing`, `HARNESS_VENDOR`,
   `overrideVendor`, `projectPriceRows` (D-VENDOR, D-FRESH).
9. The four load sites (D-PWIRE); dispatch NOTE order and guard
   (D-DISPATCH-2); doctor CAT-22 extensions and detail (D-FRESH, D-VENDOR).
10. table-freshness.mjs `priced` and `pricingRows.unverified`; the PRICING.yaml
    header comment for `unverified_utc` (D-FULL).
11. ROUTING_REFRESH.routine.md: Step 0 mode decision, Steps 1 to 3 full table,
    downstream D1 to D7, safety write scopes (D-FULL, D-DOWN).
12. suite-map globs (D-DIST-2); TEST-3680 planted bytes.
13. Last, after the loop's flush: CHANGELOG entry body, consumer-config.md
    (pricing, codex and gemini examples, precedence, cross-vendor, freshness),
    universal-routines.md (downstream mode), aai-doctor.md (CAT-22 additions).

Edge cases the extension tests must hold: a pricing key `constructor` or
`toString` parses as an ordinary id and never resolves an inherited member;
an entry with only optional fields reports every missing required field; a
file with only a `pricing:` section is valid with zero overrides; CRLF and BOM
apply to the pricing section as to the routing section.

Edge cases the tests must hold:
- CRLF and BOM files parse; a file that is only comments is valid with zero
  overrides (PASS no routing overrides, byte-identical dispatch).
- A role or harness named `constructor` or `toString` never resolves an
  inherited member (unknown role error; ignored harness note).
- `Implementation Preparation / Worktree decision` (a role with spaces and a
  slash) parses as a key.
- An override with value `claude-sonnet-5-5[1m]` is priced (bracket rule).
- No `docs/ai/project-config.yaml` is created in this repository by the ride.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3680 | Spec-AC-01 | integration | tests/skills/test-aai-project-config.sh | drives install-parity.mjs exports with scenarios CC-UP (older-core target, update) and CC-SY (core base, sync) and a setup planting a customized MODEL_ROUTING.yaml and a BOM plus CRLF consumer file carrying a routing_override section and a valid pricing section (amended 2026-11-14); per twin asserts exit 0, table byte-equal to the source, consumer file byte-equal to the planted bytes, no twin divergence on the two paths; the ps1 half prints SKIP without pwsh | target `.aai/scripts/aai-sync.sh`; `sed:s/# docs\/ai: preserve existing runtime data, but sync template files./rm -f "$DST_ROOT\/docs\/ai\/project-config.yaml"/` deletes the consumer file on every sync and the case must fail | pending |
| TEST-3681 | Spec-AC-02 | integration | tests/skills/test-aai-project-config.sh | imports loadModelRouting, suggestModel and the lib; for the shipped table, a Mode A fixture table and no table, walks every TIERS role on claude, codex, gemini, cursor and unknown and both lanes, comparing suggestModel with and without overrides; asserts the only differences are the overridden pairs, including a cursor override where the shipped value is null | target `.aai/scripts/lib/project-config.mjs`; `sed:s/const h = overrides\[harness\];/const h = Object.values(overrides)[0];/` applies the claude override on every harness and the case must fail | pending |
| TEST-3682 | Spec-AC-02 | integration | tests/skills/test-aai-project-config.sh | real orchestration-dispatch on a fixture root that dispatches Code Review: AAI_HARNESS=claude gives suggested_model claude-sonnet-5-5 and model_override with file, harness, role and model; AAI_HARNESS=codex gives the shipped codex id and no model_override | target `.aai/scripts/orchestration-dispatch.mjs`; `sed:s/let model = override \?\? resolveModelFromMap/let model = resolveModelFromMap/` ignores the override in Mode B and the case must fail | pending |
| TEST-3683 | Spec-AC-03 | integration | tests/skills/test-aai-project-config.sh | a ceremony L1 fixture dispatching Validation on the lightweight lane under AAI_HARNESS=claude with a Validation override resolves the override, not the shipped Validation@lightweight row | target `.aai/scripts/orchestration-dispatch.mjs`; `sed:s/let model = override \?\? resolveModelFromMap/let model = resolveModelFromMap/` lets the lane row win and the case must fail | pending |
| TEST-3684 | Spec-AC-03 | integration | tests/skills/test-aai-project-config.sh | pure suggestModel cases: Mode B claude Validation override equal to implementer_model is replaced by a different claude tier id; a cursor override equal to implementer_model keeps the id with residual single_model_harness_reuse; Mode A swaps to validation_alternate; one CLI case asserts model_override.model is the consumer value while suggested_model differs | target `.aai/scripts/orchestration-dispatch.mjs`; `sed:s/if \(model && out.role === 'Validation'/if (model \&\& !override \&\& out.role === 'Validation'/` lets the override bypass the backstop and the case must fail | pending |
| TEST-3685 | Spec-AC-04 | integration | tests/skills/test-aai-project-config.sh | a file with routing_override (no suffix), routing_override@unknown, routing_override@CLAUDE, routing_override@codx and routing_override@ (each with a Code Review row) plus a valid routing_override@claude Planning row: stderr carries one NOTE per bad header naming it, Code Review resolves the shipped id on every harness, Planning on claude resolves the override | target `.aai/scripts/lib/project-config.mjs`; `sed:s/if \(!OVERRIDE_HARNESSES.includes\(suffix\)\)/if (false)/` accepts out-of-set suffixes and the case must fail | pending |
| TEST-3686 | Spec-AC-05 | integration | tests/skills/test-aai-project-config.sh | materializes the pre-ride dispatch from blob 73668e4c1730c5e98f45a5bdcf94f866f0fc5e58 next to the current one; for a Code Review fixture under AAI_HARNESS=claude with no file, a file overriding only codex Planning, and a comments-only file, asserts stdout and exit code byte-equal between the two scripts, no model_override key, and no project-config NOTE on stderr | target `.aai/scripts/orchestration-dispatch.mjs`; `sed:s/if \(applied !== null\) out.model_override/out.model_override/` adds the key on every dispatch and the case must fail | pending |
| TEST-3687 | Spec-AC-06 | integration | tests/skills/test-aai-project-config.sh | twelve malformed fixtures (unknown section, effort_roles section, key with inline value, repeated header, row before a section, tab row, inline comment row, duplicate role, unknown role, lane key, null model, model with a hash) each next to a valid matching claude Code Review override: real dispatch resolves the shipped id, carries no model_override, stderr names the line and reason plus the no-override NOTE; a BOM, CRLF, quoted, commented valid file applies | target `.aai/scripts/lib/project-config.mjs`; `sed:s/if \(errors.length\) return/if (false) return/` half-applies a malformed file and the case must fail | pending |
| TEST-3688 | Spec-AC-07 | integration | tests/skills/test-aai-project-config.sh | override Code Review on claude to acme-model-1: dispatch applies it and stderr names claude, Code Review and acme-model-1 as unpriced; claude-sonnet-5-5, claude-sonnet-5-5[1m] and claude-sonnet-5-5-20261101 give no unpriced NOTE; seam: the dispatched suggested_model of the priced override costs to a non-null number through lib/pricing.mjs runCostUsd | target `.aai/scripts/lib/project-config.mjs`; `sed:s/runCostUsd\(pricing, model, 1, 1\) === null/false/` hides the unpriced id and the case must fail | pending |
| TEST-3689 | Spec-AC-08 | integration | tests/skills/test-aai-doctor.sh | doctor fixture plus file: two overrides give one CAT-22 PASS line naming claude/Code Review -> claude-sonnet-5-5 and codex/Planning -> gpt-6.1-sol and --json detail.overrides of length 2; comments-only gives PASS no routing overrides; malformed gives WARN naming no override applied and the line reason, exit 0, --strict exit 1; an ignored header and an unpriced id each give WARN naming them; no file gives no CAT-22 line and the clean-fixture cases hold | target `.aai/scripts/aai-doctor.mjs`; `sed:s/'CAT-22', 'Project Config', 'WARN'/'CAT-22', 'Project Config', 'PASS'/g` hides the finding and the case must fail | pending |
| TEST-3690 | Spec-AC-09 | integration | tests/skills/test-aai-project-config.sh | greps MODEL_ROUTING.yaml: case-insensitive re-apply count 0, docs/ai/project-config.yaml and routing_override present, CHANGE-0192 and the Amendment 2 citation present, CHANGE-DRAFT count 0; runs table-freshness.mjs stamp-guard against the merge-base of HEAD and origin/main, exit 0 with an UNCHANGED, RESTAMPED or CHANGED-STAMPED line for MODEL_ROUTING and no VIOLATION line, failing closed when the merge-base cannot be computed | target `.aai/system/MODEL_ROUTING.yaml`; `sed:s/docs\/ai\/project-config.yaml/re-apply after each update/` brings the instruction back and the case must fail | pending |
| TEST-3691 | Spec-AC-10 | integration | tests/skills/test-aai-project-config.sh | for every TIERS role on claude, codex, gemini and cursor, real dispatch on a fixture with and without an override file overriding that role gives equal suggested_effort and harness_effort; table-freshness.mjs check with a pinned --now gives identical stdout with and without the file | target `.aai/scripts/orchestration-dispatch.mjs`; `sed:s/out.suggested_effort = suggestEffort\(out, routing\);/out.suggested_effort = applied !== null ? 'low' : suggestEffort(out, routing);/` lets the override move effort and the case must fail | pending |
| TEST-3692 | Spec-AC-11 | integration | tests/skills/test-aai-project-config.sh | seam: aai-sync.sh --profile core from this checkout into a scratch git target; asserts no docs/ai/project-config.yaml after sync; adds a file overriding Planning on claude and a STATE that dispatches Planning; the target's own dispatch applies it under AAI_HARNESS=claude and not under codex; the target's doctor --json has CAT-22 naming claude/Planning; the target's docs-audit output has no non-canonical project-config.yaml; git check-ignore exits 1 | target `.aai/system/DOCS_AI_CANON.list`; `sed:s/\nproject-config.yaml\n/\n/` drops the canon entry so the consumer's docs-audit flags the file and the case must fail | pending |
| TEST-3693 | Spec-AC-11 | integration | tests/skills/test-aai-project-config.sh | PROFILES.yaml lists the lib inside the core block; DOCS_AI_CANON.list has the exact line; select-suites with a file list of only .aai/scripts/aai-sync.ps1 names aai-project-config, and with only docs/product/consumer-config.md names it too | target `.aai/system/PROFILES.yaml`; `sed:s/  - .aai\/scripts\/lib\/project-config.mjs\n//` drops the core entry and the case must fail | pending |
| TEST-3694 | Spec-AC-06 | integration | tests/skills/test-aai-project-config.sh | imports OVERRIDE_ROLES from the lib and TIERS from orchestration-dispatch.mjs and asserts the two sets are equal; a row naming Implementation Preparation / Worktree decision parses; rows named constructor and toString are unknown roles | target `.aai/scripts/lib/project-config.mjs`; `sed:s/'Metrics Flush'/'Metrics flush'/` drifts the closed role set and the case must fail | pending |
| TEST-3695 | Spec-AC-12 | integration | tests/skills/test-aai-project-config.sh | CHANGELOG has exactly one heading in the unreleased or rolled form whose title names the consumer config and whose body names docs/ai/project-config.yaml, routing_override and CAT-22; docs/product/consumer-config.md has capability consumer-config and the listed facts; docs/product/aai-doctor.md names CAT-22 Project Config | target `docs/product/consumer-config.md`; `sed:s/capability: consumer-config/capability: consumer-configuration/` breaks the capability and the case must fail | pending |
| TEST-3696 | Spec-AC-13 | integration | tests/skills/test-aai-project-config.sh | parser cases through parseProjectConfig and loadCostPricing plus real dispatch: one valid pricing section parses with optional fields null when absent; fifteen malformed fixtures (missing rate, unknown field, repeated field, negative rate, null rate, rate with an inline comment, http source_url, bad timestamp, uppercase provider, field before entry, duplicate key, key NULL, key unknown, bracketed key, three-space indent) each next to a valid claude Code Review override give no model_override, a NOTE naming line and reason, the no-override NOTE and no attached price; pricing@codex and a second pricing header are errors; routing rows with NULL and Null are invalid model ids | target `.aai/scripts/lib/project-config.mjs`; `sed:s/if \(!PRICE_FIELDS.includes\(field\)\)/if (false)/` accepts an unknown field and the case must fail | pending |
| TEST-3697 | Spec-AC-14 | integration | tests/skills/test-aai-project-config.sh | imports lib/pricing.mjs and lib/project-config.mjs over a fixture root: claude-sonnet-5-5 priced by both costs at the shipped rate; acme-model-1, cursor-grok-4.6, acme-model-1[1m] and acme-model-1-2026 cost at the project rate through runCostUsd and blendedCostUsd; priceSource gives shipped, project and null; a malformed file attaches nothing | target `.aai/scripts/lib/pricing.mjs`; `sed:s/if \(hasRates\(shipped\)\) return shipped;/if (false) return shipped;/` lets the project shadow the shipped rate and the case must fail | pending |
| TEST-3698 | Spec-AC-14 | integration | tests/skills/test-aai-project-config.sh | seam: real metrics-flush.mjs over a fixture docs/ai/STATE.yaml with a validated item whose run recorded tokens_in and tokens_out on acme-model-1, with and without a file pricing it; the appended METRICS row's run has cost_usd equal to the project arithmetic and cost_basis decomposed with the file, cost_usd null without it | target `.aai/scripts/metrics-flush.mjs`; `sed:s/loadCostPricing\(root, pricingPath\)/loadCostPricing(path.join(root, 'no-such-root'), pricingPath)/` loses the project prices and the case must fail | pending |
| TEST-3699 | Spec-AC-14 | integration | tests/skills/test-aai-project-config.sh | seam: real metrics-report.mjs run in a fixture root whose METRICS.jsonl has a run on acme-model-1 with tokens and null cost_usd; the report's total equals the project arithmetic with the file and shows no cost for it without the file | target `.aai/scripts/metrics-report.mjs`; `sed:s/loadCostPricing\(process.cwd\(\), pricingPath\)/loadCostPricing(path.join(process.cwd(), 'no-such-root'), pricingPath)/` loses the project prices and the case must fail | pending |
| TEST-3700 | Spec-AC-07 | integration | tests/skills/test-aai-project-config.sh | real dispatch: acme-model-1 Code Review override on claude with a project price prints no unpriced NOTE and an empty stderr; a Validation override equal to implementer_model acme-model-1 (unpriced) that the backstop replaces with a shipped claude id prints no unpriced NOTE while model_override.model is acme-model-1 | target `.aai/scripts/orchestration-dispatch.mjs`; `sed:s/if \(applied !== null && out.suggested_model === applied\)/if (applied !== null)/` NOTEs the swapped override and the case must fail | pending |
| TEST-3701 | Spec-AC-15 | integration | tests/skills/test-aai-doctor.sh | doctor fixture plus file: a price verified 2020-01-01 gives CAT-22 WARN naming the id, date and age over 30d, exit 0, --strict exit 1; a price verified yesterday gives no freshness WARN and the override is named priced by project; AAI_TABLES_HORIZON_DAYS=1 makes a three-day-old price stale; a project row for claude-sonnet-5-5 is named shadowed and stays PASS; a fixture PRICING without cadence_days gives the cannot-be-judged WARN; --json detail has prices, horizon_days and price_source, vendor, cross_vendor per override | target `.aai/scripts/lib/project-config.mjs`; `sed:s/stale: horizonDays !== null && ageDays > horizonDays/stale: false/` hides the stale price and the case must fail | pending |
| TEST-3702 | Spec-AC-16 | integration | tests/skills/test-aai-project-config.sh | real dispatch under AAI_HARNESS=codex with routing_override@codex Code Review claude-sonnet-5-5 applies it with exactly one cross-vendor NOTE naming anthropic and openai; claude and cursor sections with the same id print none; acme-model-1 on codex prints only the unpriced NOTE; acme-model-1 with a project price and provider anthropic on codex prints the cross-vendor NOTE; the target doctor's CAT-22 is PASS and names the cross-vendor override; HARNESS_VENDOR pinned against OVERRIDE_HARNESSES and the shipped PRICING providers | target `.aai/scripts/lib/project-config.mjs`; `sed:s/const crossVendor = hv !== null && mv !== null && mv !== hv;/const crossVendor = false;/` hides the cross-vendor override and the case must fail | pending |
| TEST-3703 | Spec-AC-17 | integration | tests/skills/test-aai-pricing.sh | fixture PRICING with four rows (verified after D, marked after D, neither, garbage unverified_utc) plus unknown: priced prints OK, UNVERIFIED, STALE, INVALID and nothing for unknown, exit 1; with the STALE and INVALID rows removed exit 0; missing --since exit 2; a git fixture adding unverified_utc without a re-stamp gives stamp-guard VIOLATION and with a re-stamp CHANGED-STAMPED; runCostUsd costs the marked row; the shipped PRICING.yaml comment names unverified_utc and stamp-guard against the merge-base prints UNCHANGED for PRICING | target `.aai/scripts/table-freshness.mjs`; `sed:s/const marked = u !== null && u >= sinceMs;/const marked = true;/` reads the stale row as marked and the case must fail | pending |
| TEST-3704 | Spec-AC-18 | integration | tests/skills/test-aai-routine.sh | renders ROUTING_REFRESH for claude, codex, gemini and generic; asserts every models: row wording, unverified_utc, table-freshness.mjs priced, TEST_3668_ALLOW_STALE and the re-stamp rule; reads every provider under sources: of the shipped PRICING.yaml and asserts each is named in the render; no gh pr merge or merge_pull_request | target `.aai/routines/ROUTING_REFRESH.routine.md`; `sed:s/table-freshness.mjs priced/table-freshness.mjs prices/g` drops the gate and the case must fail | pending |
| TEST-3705 | Spec-AC-19 | integration | tests/skills/test-aai-routine.sh | renders ROUTING_REFRESH and asserts the downstream mode text: the mode rule naming tests/skills/test-aai-pricing.sh and .aai/system/PRICING.yaml, aai-doctor.mjs --json, CAT-22, price_source, stale, shadowed, docs/ai/project-config.yaml, pricing:, chore/project-prices-, gh pr create, NEVER merge, the never-edit-.aai/ rule, and the absence of the old STOP line; seam: runs a vendored doctor over a fixture consumer (unpriced override, stale price, shadowed price) and asserts the CAT-22 detail keys and values the routine names | target `.aai/routines/ROUTING_REFRESH.routine.md`; `sed:s/price_source/priced_by/g` makes the routine read a field the doctor does not emit and the case must fail | pending |
| TEST-3706 | Spec-AC-20 | integration | tests/skills/test-aai-project-config.sh | the consumer-config CHANGELOG entry body names pricing:, cross-vendor, ROUTING_REFRESH and table-freshness.mjs priced; consumer-config.md has a pricing: example, routing_override@codex: and routing_override@gemini: examples, shipped wins, cross-vendor and the freshness WARN; universal-routines.md names downstream mode and docs/ai/project-config.yaml; aai-doctor.md names the project price freshness WARN | target `docs/product/consumer-config.md`; `sed:s/routing_override@gemini:/routing_override@gemni:/g` breaks the gemini example and the case must fail | pending |
| TEST-3707 | Spec-AC-21 | integration | tests/skills/test-aai-project-config.sh | select-suites over single-file lists (ROUTING_REFRESH.routine.md names aai-routine and aai-pricing; lib/pricing.mjs, metrics-flush.mjs and metrics-report.mjs each name aai-project-config); check-vendored-script-deps.mjs exit 0; git diff --name-status against the merge-base with origin/main has no added .aai/ path and no .aai/*.prompt.md path, failing closed when the merge-base cannot be computed | target `tests/skills/suite-map.yaml`; `sed:s/      - .aai\/routines\/ROUTING_REFRESH.routine.md\n//g` drops the routine globs and the case must fail | pending |

Seams crossed:
- The consumer file written by the consumer and preserved by four install
  scripts, then read by two engines: TEST-3680 runs both real twins of update
  and sync; TEST-3692 runs the real core sync and then the target's own
  dispatch, doctor and docs-audit over the installed copy.
- PROFILES core list to the consumer's import closure: TEST-3692 (a missing
  core entry leaves the target's dispatch unable to import the lib).
- DOCS_AI_CANON.list (vendored) to the consumer's docs-audit: TEST-3692.
- One parser shared by dispatch and doctor: TEST-3685, TEST-3687 (dispatch side)
  and TEST-3689 (doctor side) run the same malformed and ignored-section
  fixtures through both readers.
- The override's model id leaves the dispatch as suggested_model and is priced
  later by metrics through lib/pricing.mjs: TEST-3688 produces with the real
  dispatch and costs with the real resolver.
- The override and SPEC-0177's validator-independence backstop share
  suggestModel: TEST-3684.
- The override and SPEC-0288's effort axis share the dispatch verdict:
  TEST-3691. SPEC-0289's stamp guard and the UPGRADING edit share
  MODEL_ROUTING.yaml: TEST-3690.
- The dispatch's suggested_model to the model the harness actually spawns: no
  automated test can cross it (the orchestrator honours the field); R3.
- Extension 2026-11-14 seams:
  - The project pricing section, written by the consumer or the downstream
    routine, read by four consumers through one lib seam: TEST-3698 (real
    metrics-flush CLI writes the ledger row), TEST-3699 (real metrics-report
    CLI), TEST-3700 (real dispatch), TEST-3701 (real doctor), TEST-3697 (the
    lib both share).
  - One parser, two tenants, one all-or-nothing verdict shared by dispatch,
    doctor and metrics: TEST-3696 (dispatch and loader), TEST-3701 (doctor).
  - The doctor's --json CAT-22 detail and the downstream routine that reads it:
    TEST-3705 runs the real doctor and asserts the exact fields the routine
    names.
  - PRICING `sources:` providers to HARNESS_VENDOR (TEST-3702) and to the
    routine's vendor list (TEST-3704).
  - Marking a PRICING row and SPEC-0289's stamp guard: TEST-3703.
  - The routine text to what an agent actually does on a schedule, and the
    downstream PR in a consumer repository: no automated test; R10, R11.

## Verification

All local runs use `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/<file>`.

1. RED before each GREEN per TDD run, stored as
   `docs/ai/tdd/consumer-config-routing-override/red-<run>.log` and
   `green-<run>.log`. For TEST-3680, TEST-3686 and TEST-3691 (non-regression)
   the RED is the mutation record of step 3.
2. Suites exit 0: aai-project-config, aai-doctor, aai-orchestration-dispatch,
   aai-pricing (TEST-3660), aai-git-ref-guard (TEST-639), aai-model-effort,
   aai-layer-profiles, aai-docs-audit (TEST-U02), aai-downstream-autopilot,
   aai-roadmap, aai-hygiene-pack, aai-suite-select, aai-install-parity, plus
   CORE. `node .aai/scripts/check-vendored-script-deps.mjs` exits 0.
3. Mutation records for TEST-3680..3695 under
   `docs/ai/tdd/spec-consumer-config-routing-override/`.
4. One full sweep with `AAI_TEST_TIMEOUT=3600` at final validation, per
   `round-budget.mjs sweep-plan` (the lib path triggers a full CI run anyway).
5. CI: the PR's CI log shows TEST-3680 running its ps1 half (no SKIP line) on at
   least one leg.
6. `git ls-files -ci --exclude-standard` empty before push; no
   `docs/ai/project-config.yaml` exists in this repository.
7. PASS criteria: every TEST row green, every Spec-AC done with evidence, CI
   green on the PR head.
8. Extension 2026-11-14: RED before GREEN per extension run, stored as
   `docs/ai/tdd/consumer-config-routing-override/red-E1.log` .. `red-E3.log`
   and the matching `green-E*.log` (amended Spec-AC-01: the TEST-3680 mutation
   record re-run). Mutation records for TEST-3696..TEST-3707 and re-runs for
   TEST-3680 and TEST-3688 under
   `docs/ai/tdd/spec-consumer-config-routing-override/`.
9. Extension suites exit 0 in addition to step 2: aai-routine, aai-metrics,
   aai-token-capture, aai-factory-report, aai-codex-usage (metrics-flush and
   metrics-report readers), aai-pricing (TEST-3703 and the pins).
   `node .aai/scripts/table-freshness.mjs stamp-guard --base $(git merge-base HEAD origin/main)`
   exits 0 with UNCHANGED for both tables;
   `node .aai/scripts/spec-amend.mjs list --strict` exits 0.
10. No rate, id or stamp of a shipped table differs from the merge-base
    (`git diff <merge-base> -- .aai/system/PRICING.yaml` touches comment lines
    only); no `docs/ai/project-config.yaml` exists in this repository.

## Evidence contract

Each artifact records the ref_id consumer-config-routing-override, its Spec-AC
and TEST links, the command, the exit code and the evidence path, plus the
commit SHA once one exists. RED and GREEN logs under
docs/ai/tdd/consumer-config-routing-override/, mutation records under
docs/ai/tdd/spec-consumer-config-routing-override/.

### Evidence by strategy

tdd: a stored RED artifact per AC-gating test (the mutation record for the three
non-regression rows) plus the verification matrix above.

## Residual risks

- R1. A host without pwsh runs only the sh half of TEST-3680 (printed SKIP).
  Validation must read one CI leg's log showing the ps1 half ran.
- R2. Only the dispatch and the doctor read the file. Other readers of
  MODEL_ROUTING.yaml (`table-freshness.mjs routed`, the shipped-id pins) judge
  the shipped table only; an override id is judged by the doctor's unpriced
  check, not by `routed`.
- R3. The override reaches the spawned model only through `suggested_model`; a
  harness or orchestrator that does not select models ignores it exactly as it
  ignores the shipped binding.
- R4. All or nothing includes unknown sections, so a file carrying a future
  tenant's section, read by an older AAI, applies no override until AAI is
  updated. Intended: a typo'd section must not be silently ignored. Stated in
  the product doc.
- R5. With the shipped table deleted (the documented opt-out) an override still
  applies and no validator swap is possible, as in Mode A without an
  alternate.
- R6. `model_override.model` and `suggested_model` differ when the backstop
  swapped a Validation override; documented in D-DISPATCH and the product doc.
- R7. The name `project-config.yaml` becomes reserved in every consumer's
  `docs/ai/`. A consumer already holding a file of that name for another
  purpose sees it parsed and reported malformed (WARN, nothing applied). Not
  measurable from this repository.
- R8. TEST-3680 judges twin agreement on two paths only; other divergences are
  SPEC-0284's allowlist's concern.
- R9. The mutation strings name code shapes fixed in Decisions; an
  implementation that needs a different shape amends this spec with disclosure
  rather than silently changing the row.
- R10. ROUTING_REFRESH is prose an agent follows on a schedule. TEST-3704 and
  TEST-3705 pin its contract text and the data it reads; whether an agent
  researches and marks correctly is first observed on the owner's first run.
- R11. Downstream mode's vendor research, page availability and the PR it opens
  in a consumer repository are not testable here; D5's doctor re-check is the
  routine's own gate.
- R12. No rate is corrected by hand: until the first full-table run, o3 (10/40
  in the file; 2/8 on the vendor page read 2026-11-13) and the other rows of
  `fu-pricing-unverified-rows` cost metrics as today. That follow-up is closed
  as superseded, so the owner should run ROUTING_REFRESH once after merge.
- R13. A METRICS row costed from a project price is indistinguishable in the
  ledger from a shipped-priced one; CAT-22 names project-priced ids at the time.
- R14. An override whose vendor neither table knows (a proxy or gateway id with
  no project `provider`) prints no vendor NOTE (D-VENDOR).
- R15. A project price is the consumer's (or the downstream routine's) claim;
  AAI checks its shape and age, not its truth.
- R16. An older AAI reading a file that carries `pricing:` reports the whole
  file malformed and applies no override (R4, now with a real second tenant).
- R17. metrics-report resolves the project file against `process.cwd()`, like
  its other default paths; run elsewhere it costs with shipped prices only.
- R18. Shipped wins: a consumer who believes a shipped rate is wrong cannot
  override it with a project price; the fix belongs upstream.
