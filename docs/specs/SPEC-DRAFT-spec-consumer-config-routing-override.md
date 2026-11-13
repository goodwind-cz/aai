---
id: spec-consumer-config-routing-override
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: 754d4251ed6acc152f9ac71a24ccbbbb7bef32fa2a25392b2a8470f0ae9712e0
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

- Requirement: docs/issues/CHANGE-DRAFT-consumer-config-routing-override.md
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

Registry items closed by this scope: `fu-consumer-routing-seam`. Measured with
`node .aai/scripts/follow-ups.mjs list` on 2026-11-13: it is open (P2, ref
routing-tables-have-an-owner-and-a-seam) and names exactly this scope. Related
items left open on purpose: `fu-routing-pins-structural` and
`fu-routing-owner-cost-binding` (shipped-table concerns this scope does not
touch), `fu-effort-params-cursor-accepted` (effort_params accepts @unknown; this
scope refuses @unknown for its own section but does not edit effort_params).
`fu-routing-file-overwritten-on-update` is already dropped (2026-09-24).

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

## Out of scope

- A second routing table: no tier rows, no `validation_alternate`, no lane keys
  (`Role@lane`), no effort, no effort_params in the consumer file. Role to
  model, per harness, nothing else.
- Any change to how sync, update or prune treat the file: none is needed
  (measured above), so none of `aai-sync.sh`, `aai-sync.ps1`, `aai-update.sh`,
  `aai-update.ps1` is edited. The proof is a test, not an edit.
- Seeding the file on install. Absence is the default and changes nothing.
- The shipped tables' content, overwrite behaviour, freshness stamp, stamp guard
  and effort tiers.
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
  this spec.

## Ceremony

Ceremony level 2. No path in `protected_paths_l3` (docs/ai/docs-audit.yaml) is
touched: no state engine, allocator, pre-commit guard, hook gate, WORKFLOW.md
or CONSTITUTION.md edit, and no `.github/workflows/` edit. Level 1 would
understate it: the dispatch engine every tick runs, a doctor category, two
vendored system files and both install twins are in play. L2 gives full
independent validation and a required review.

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

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN a scratch target carrying a customized shipped MODEL_ROUTING.yaml and a docs/ai/project-config.yaml with BOM and CRLF bytes is updated (older-core target, step update) or re-synced (core base, step sync) by the bash twin and by the PowerShell twin the system SHALL exit 0 in every run, leave MODEL_ROUTING.yaml byte-equal to the source table, leave docs/ai/project-config.yaml byte-equal to the planted bytes, and report no twin divergence on either path | planned | — | — | D-PARITY; non-regression, RED is the mutation record |
| Spec-AC-02 | WHEN docs/ai/project-config.yaml holds routing_override@claude with Code Review set to claude-sonnet-5-5 the system SHALL resolve suggested_model claude-sonnet-5-5 and add model_override naming file, harness claude, role Code Review and the model for a Code Review dispatch on claude, and SHALL resolve every other role on claude and every role on codex, gemini, cursor and unknown exactly as without the file, for the shipped Mode B table, a Mode A table and an absent table; an override on cursor SHALL apply although the shipped table has no cursor map | planned | — | — | D-FORMAT, D-RESOLVE |
| Spec-AC-03 | WHEN an override names Validation on claude the system SHALL use it on a lightweight-lane Validation dispatch over the shipped Validation@lightweight row; WHEN that override equals the recorded implementer model the validator-independence backstop SHALL still replace it from the harness's own map (Mode B) or validation_alternate (Mode A), or set residual single_model_harness_reuse when no other id exists, while model_override.model keeps the consumer's value | planned | — | — | D-RESOLVE; consumer cannot switch off validator independence |
| Spec-AC-04 | WHEN the file holds a routing_override section with no harness suffix, or a suffix outside claude, codex, gemini and cursor (unknown, CLAUDE, codx, empty) the system SHALL print one stderr NOTE per such header naming it, apply none of its rows, and still apply the valid sections of the same file; aai-doctor SHALL report CAT-22 WARN naming each ignored header | planned | — | — | D-FORMAT ignored sections are not malformed |
| Spec-AC-05 | WHEN the file is absent, or holds only entries matching no harness and role of the tick, or holds only comments, the system SHALL print dispatch stdout and exit code byte-identical to the pre-ride dispatch script (blob 73668e4c1730c5e98f45a5bdcf94f866f0fc5e58) on the same fixture, with no model_override key and no project-config NOTE on stderr | planned | — | — | Non-regression, RED is the mutation record |
| Spec-AC-06 | WHEN the file holds any of an unknown column-0 section (including effort_roles and a key with an inline value), a repeated section header, a row outside a section, a tab-indented row, a row with an inline comment, a duplicate role, an unknown role (including a lane key), or an invalid model id (null, empty, containing a space or hash) next to an otherwise valid matching override the system SHALL apply no override from the file, print one stderr NOTE per error naming the line and reason plus one NOTE that no override is applied, and resolve suggested_model as without the file; a file with BOM, CRLF, quoted values and indented comments SHALL parse; the closed role set SHALL equal the dispatch TIERS keys | planned | — | — | D-FORMAT all or nothing |
| Spec-AC-07 | WHEN an applied override names a model id that lib/pricing.mjs cannot price (runCostUsd null) the system SHALL still apply it, print one stderr NOTE naming harness, role and model as unpriced, and aai-doctor SHALL report CAT-22 WARN naming it; an exact, bracket-suffixed or prefix-resolvable priced id SHALL produce no unpriced NOTE, and the suggested_model of a priced override SHALL cost to a non-null number through runCostUsd | planned | — | — | D-PRICE; seam dispatch to metrics pricing |
| Spec-AC-08 | WHEN aai-doctor runs over a tree with a valid file holding two overrides it SHALL print one CAT-22 PASS line naming each as harness/role -> model and carry detail.overrides with one object per override in --json; a valid file with none SHALL give CAT-22 PASS no routing overrides; a malformed file SHALL give CAT-22 WARN naming no override applied and the errors, exit 0 without --strict and 1 with it; no file SHALL give no CAT-22 line and the existing clean-fixture cases SHALL stay green | planned | — | — | D-DOCTOR |
| Spec-AC-09 | MODEL_ROUTING.yaml SHALL contain no case-insensitive re-apply, SHALL name docs/ai/project-config.yaml and routing_override, SHALL keep CHANGE-0192 and spec-update-installs-ref-guard-undisclosed Amendment 2, SHALL name no CHANGE-DRAFT id, and table-freshness stamp-guard against the merge-base with origin/main SHALL exit 0 with MODEL_ROUTING UNCHANGED | planned | — | — | D-NOTE; comment-only, no re-stamp |
| Spec-AC-10 | For every dispatch role on claude, codex, gemini and cursor the system SHALL resolve suggested_effort and harness_effort identically with and without an override file, and table-freshness check SHALL print identical output with and without the file | planned | — | — | Non-regression, RED is the mutation record |
| Spec-AC-11 | PROFILES.yaml SHALL list .aai/scripts/lib/project-config.mjs under core and DOCS_AI_CANON.list SHALL carry the exact line project-config.yaml; WHEN aai-sync.sh --profile core installs into a scratch git target the target SHALL hold no docs/ai/project-config.yaml, and after the file is added the target's own dispatch SHALL apply the override on claude and not on codex, its own doctor SHALL print CAT-22 naming it, its own docs-audit SHALL report no non-canonical entry for it, and git check-ignore SHALL exit 1 for it; select-suites SHALL select aai-project-config for a diff touching only aai-sync.ps1 | planned | — | — | D-LOC, D-LIB; seam sync to consumer readers |
| Spec-AC-12 | CHANGELOG.md SHALL gain exactly one per-entry heading for this change, unreleased or rolled, whose body names docs/ai/project-config.yaml, routing_override and CAT-22; docs/product/consumer-config.md SHALL exist with capability consumer-config and name the file path, the section form, the four harnesses, all-or-nothing, the unpriced rule, CAT-22 and that no sync or update writes the file; docs/product/aai-doctor.md SHALL document CAT-22 Project Config | planned | — | — | Consumer-visible; release-notes gate |

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
| TEST-3680 | Spec-AC-01 | integration | tests/skills/test-aai-project-config.sh | drives install-parity.mjs exports with scenarios CC-UP (older-core target, update) and CC-SY (core base, sync) and a setup planting a customized MODEL_ROUTING.yaml and a BOM plus CRLF consumer file; per twin asserts exit 0, table byte-equal to the source, consumer file byte-equal to the planted bytes, no twin divergence on the two paths; the ps1 half prints SKIP without pwsh | target `.aai/scripts/aai-sync.sh`; `sed:s/# docs\/ai: preserve existing runtime data, but sync template files./rm -f "$DST_ROOT\/docs\/ai\/project-config.yaml"/` deletes the consumer file on every sync and the case must fail | pending |
| TEST-3681 | Spec-AC-02 | integration | tests/skills/test-aai-project-config.sh | imports loadModelRouting, suggestModel and the lib; for the shipped table, a Mode A fixture table and no table, walks every TIERS role on claude, codex, gemini, cursor and unknown and both lanes, comparing suggestModel with and without overrides; asserts the only differences are the overridden pairs, including a cursor override where the shipped value is null | target `.aai/scripts/lib/project-config.mjs`; `sed:s/const h = overrides\[harness\];/const h = Object.values(overrides)[0];/` applies the claude override on every harness and the case must fail | pending |
| TEST-3682 | Spec-AC-02 | integration | tests/skills/test-aai-project-config.sh | real orchestration-dispatch on a fixture root that dispatches Code Review: AAI_HARNESS=claude gives suggested_model claude-sonnet-5-5 and model_override with file, harness, role and model; AAI_HARNESS=codex gives the shipped codex id and no model_override | target `.aai/scripts/orchestration-dispatch.mjs`; `sed:s/let model = override \?\? resolveModelFromMap/let model = resolveModelFromMap/` ignores the override in Mode B and the case must fail | pending |
| TEST-3683 | Spec-AC-03 | integration | tests/skills/test-aai-project-config.sh | a ceremony L1 fixture dispatching Validation on the lightweight lane under AAI_HARNESS=claude with a Validation override resolves the override, not the shipped Validation@lightweight row | target `.aai/scripts/orchestration-dispatch.mjs`; `sed:s/let model = override \?\? resolveModelFromMap/let model = resolveModelFromMap/` lets the lane row win and the case must fail | pending |
| TEST-3684 | Spec-AC-03 | integration | tests/skills/test-aai-project-config.sh | pure suggestModel cases: Mode B claude Validation override equal to implementer_model is replaced by a different claude tier id; a cursor override equal to implementer_model keeps the id with residual single_model_harness_reuse; Mode A swaps to validation_alternate; one CLI case asserts model_override.model is the consumer value while suggested_model differs | target `.aai/scripts/orchestration-dispatch.mjs`; `sed:s/if \(model && out.role === 'Validation'/if (model \&\& !override \&\& out.role === 'Validation'/` lets the override bypass the backstop and the case must fail | pending |
| TEST-3685 | Spec-AC-04 | integration | tests/skills/test-aai-project-config.sh | a file with routing_override (no suffix), routing_override@unknown, routing_override@CLAUDE, routing_override@codx and routing_override@ (each with a Code Review row) plus a valid routing_override@claude Planning row: stderr carries one NOTE per bad header naming it, Code Review resolves the shipped id on every harness, Planning on claude resolves the override | target `.aai/scripts/lib/project-config.mjs`; `sed:s/if \(!OVERRIDE_HARNESSES.includes\(suffix\)\)/if (false)/` accepts out-of-set suffixes and the case must fail | pending |
| TEST-3686 | Spec-AC-05 | integration | tests/skills/test-aai-project-config.sh | materializes the pre-ride dispatch from blob 73668e4c1730c5e98f45a5bdcf94f866f0fc5e58 next to the current one; for a Code Review fixture under AAI_HARNESS=claude with no file, a file overriding only codex Planning, and a comments-only file, asserts stdout and exit code byte-equal between the two scripts, no model_override key, and no project-config NOTE on stderr | target `.aai/scripts/orchestration-dispatch.mjs`; `sed:s/if \(applied !== null\) out.model_override/out.model_override/` adds the key on every dispatch and the case must fail | pending |
| TEST-3687 | Spec-AC-06 | integration | tests/skills/test-aai-project-config.sh | twelve malformed fixtures (unknown section, effort_roles section, key with inline value, repeated header, row before a section, tab row, inline comment row, duplicate role, unknown role, lane key, null model, model with a hash) each next to a valid matching claude Code Review override: real dispatch resolves the shipped id, carries no model_override, stderr names the line and reason plus the no-override NOTE; a BOM, CRLF, quoted, commented valid file applies | target `.aai/scripts/lib/project-config.mjs`; `sed:s/if \(errors.length\) return/if (false) return/` half-applies a malformed file and the case must fail | pending |
| TEST-3688 | Spec-AC-07 | integration | tests/skills/test-aai-project-config.sh | override Code Review on claude to acme-model-1: dispatch applies it and stderr names claude, Code Review and acme-model-1 as unpriced; claude-sonnet-5-5, claude-sonnet-5-5[1m] and claude-sonnet-5-5-20261101 give no unpriced NOTE; seam: the dispatched suggested_model of the priced override costs to a non-null number through lib/pricing.mjs runCostUsd | target `.aai/scripts/lib/project-config.mjs`; `sed:s/runCostUsd\(pricing, model, 1, 1\) === null/false/` hides the unpriced id and the case must fail | pending |
| TEST-3689 | Spec-AC-08 | integration | tests/skills/test-aai-doctor.sh | doctor fixture plus file: two overrides give one CAT-22 PASS line naming claude/Code Review -> claude-sonnet-5-5 and codex/Planning -> gpt-6.1-sol and --json detail.overrides of length 2; comments-only gives PASS no routing overrides; malformed gives WARN naming no override applied and the line reason, exit 0, --strict exit 1; an ignored header and an unpriced id each give WARN naming them; no file gives no CAT-22 line and the clean-fixture cases hold | target `.aai/scripts/aai-doctor.mjs`; `sed:s/'CAT-22', 'Project Config', 'WARN'/'CAT-22', 'Project Config', 'PASS'/g` hides the finding and the case must fail | pending |
| TEST-3690 | Spec-AC-09 | integration | tests/skills/test-aai-project-config.sh | greps MODEL_ROUTING.yaml: case-insensitive re-apply count 0, docs/ai/project-config.yaml and routing_override present, CHANGE-0192 and the Amendment 2 citation present, CHANGE-DRAFT count 0; runs table-freshness.mjs stamp-guard against the merge-base of HEAD and origin/main, exit 0 with an UNCHANGED line for MODEL_ROUTING, failing closed when the merge-base cannot be computed | target `.aai/system/MODEL_ROUTING.yaml`; `sed:s/docs\/ai\/project-config.yaml/re-apply after each update/` brings the instruction back and the case must fail | pending |
| TEST-3691 | Spec-AC-10 | integration | tests/skills/test-aai-project-config.sh | for every TIERS role on claude, codex, gemini and cursor, real dispatch on a fixture with and without an override file overriding that role gives equal suggested_effort and harness_effort; table-freshness.mjs check with a pinned --now gives identical stdout with and without the file | target `.aai/scripts/orchestration-dispatch.mjs`; `sed:s/out.suggested_effort = suggestEffort\(out, routing\);/out.suggested_effort = applied !== null ? 'low' : suggestEffort(out, routing);/` lets the override move effort and the case must fail | pending |
| TEST-3692 | Spec-AC-11 | integration | tests/skills/test-aai-project-config.sh | seam: aai-sync.sh --profile core from this checkout into a scratch git target; asserts no docs/ai/project-config.yaml after sync; adds a file overriding Planning on claude and a STATE that dispatches Planning; the target's own dispatch applies it under AAI_HARNESS=claude and not under codex; the target's doctor --json has CAT-22 naming claude/Planning; the target's docs-audit output has no non-canonical project-config.yaml; git check-ignore exits 1 | target `.aai/system/DOCS_AI_CANON.list`; `sed:s/\nproject-config.yaml\n/\n/` drops the canon entry so the consumer's docs-audit flags the file and the case must fail | pending |
| TEST-3693 | Spec-AC-11 | integration | tests/skills/test-aai-project-config.sh | PROFILES.yaml lists the lib inside the core block; DOCS_AI_CANON.list has the exact line; select-suites with a file list of only .aai/scripts/aai-sync.ps1 names aai-project-config, and with only docs/product/consumer-config.md names it too | target `.aai/system/PROFILES.yaml`; `sed:s/  - .aai\/scripts\/lib\/project-config.mjs\n//` drops the core entry and the case must fail | pending |
| TEST-3694 | Spec-AC-06 | integration | tests/skills/test-aai-project-config.sh | imports OVERRIDE_ROLES from the lib and TIERS from orchestration-dispatch.mjs and asserts the two sets are equal; a row naming Implementation Preparation / Worktree decision parses; rows named constructor and toString are unknown roles | target `.aai/scripts/lib/project-config.mjs`; `sed:s/'Metrics Flush'/'Metrics flush'/` drifts the closed role set and the case must fail | pending |
| TEST-3695 | Spec-AC-12 | integration | tests/skills/test-aai-project-config.sh | CHANGELOG has exactly one heading in the unreleased or rolled form whose title names the consumer config and whose body names docs/ai/project-config.yaml, routing_override and CAT-22; docs/product/consumer-config.md has capability consumer-config and the listed facts; docs/product/aai-doctor.md names CAT-22 Project Config | target `docs/product/consumer-config.md`; `sed:s/capability: consumer-config/capability: consumer-configuration/` breaks the capability and the case must fail | pending |

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
