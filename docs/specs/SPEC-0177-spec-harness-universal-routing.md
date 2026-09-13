---
id: spec-harness-universal-routing
type: spec
number: 177
status: done
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0182-harness-universal-routing.md
  rfc: null
  pr:
    - TBD
  commits:
    - 08f3abc1
---

# Spec — the dispatcher knows which harness it runs in, and routes models for that harness

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0182-harness-universal-routing.md
- Roadmap: docs/project-sessions/2026-09-12-wave-2-roadmap.md (wave 2, pair 1, capability half)
- Standing tier decision: docs/specs/RES-0002-mechanical-context-offload-to-cheap-tier.md
- Technology contract: docs/TECHNOLOGY.md

## Amendment (post-freeze, 2026-09-12 — remediation of validation FAIL)

Round-1 independent validation (`docs/ai/STATE.yaml` `last_validation`, run
2026-09-12T22:33:15Z; evidence under `docs/ai/tdd/spec-harness-universal-routing/
validation-20260912T222805Z-*`) returned `fail` on one BLOCKING defect plus test-side
findings. This amendment records the remediation, following the same
additive-with-disclosure convention already established (`docs/specs/SPEC-0132-...md`,
`docs/specs/SPEC-0153-...md`, `docs/specs/SPEC-0176-...md`). `SPEC-FROZEN: true` is
preserved; nothing below moves or deletes an existing AC's text.

- **BLOCKING-1 (Spec-AC-01/D6) — the `--confirm` record-failure fallback verdict
  carried NO `harness` key and, under the shipped Mode B routing file, regressed
  `suggested_model` to `null`.** `main()` stamped `out.harness = detectHarness(...)`
  once, then the confirm-record-failure arm replaced the whole object
  (`out = fallback`) with a fresh `decide()` result that was never re-stamped.
  Fixed at cause: `detectHarness(process.env)` is still called exactly ONCE per
  process (no-mid-session-flip stands), captured into a local (`harness`), and the
  local is re-applied (`fallback.harness = harness`) after the ONE arm that replaces
  `out`. TEST-038 gains a `harness`/`suggested_model` assertion against the shipped
  Mode B routing file (copied into the fixture root, matching the validator's own
  repro); reverting the re-stamp reddens it exactly (`mutation-sweep.txt`,
  "REMEDIATION ROUND 1", `BLOCKING-1`).
- **Test-strength findings (Spec-AC-04/Spec-AC-09), all mutation-verified** — the
  round-1 mutation matrix (`validation-20260912T222805Z-mutation-matrix.txt`) found
  two shipped controls that did not actually redden their named test (M7, M13) and
  four untested shapes (N3, N5, N6, N8), all confirmed as test-coverage gaps against
  the UNMUTATED shipped code, not shipped defects:
  - **M7** was a weak mutation that could not reach TEST-051's cursor arm. Replaced
    with the literal shape the spec bullet names (harness has no map at all falls
    through to the unsuffixed maps); re-recorded reddening.
  - **M13**'s test comment claimed "any ONE of the three header sentences" reddens
    TEST-058, but the "MODE A vs MODE B (D2), decided by the FILE" lead-in sentence
    was never separately pinned. TEST-058 gained a 5th header grep for that exact
    sentence; re-recorded reddening.
  - **N3** — TEST-051 gained a `tiers@gemini: {premium: ...}` (no `standard` row)
    fixture, proving a harness WITH a map but a missing routed-tier row also
    resolves null (the map-exists-row-missing shape D2 forbids), not just the
    no-map-at-all shape M7 already covered.
  - **N5** — TEST-053 gained a case where a differing `tiers@H` candidate and a
    differing `validation_alternate@H` both exist with DIFFERENT ids, pinning D4's
    stated order (tiers@H at/above the routed tier before validation_alternate@H).
  - **N6** — TEST-058 gained a `roles@codex:`-only fixture (no `tiers@codex:`
    alongside it) proving that section ALONE trips Mode B.
  - **N8** — TEST-050 gained an `AAI_HARNESS=bogus` assertion on the D3-required
    stderr NOTE text itself (previously only the resulting `unknown` value was
    checked).
  Every new/corrected mutation is recorded in `mutation-sweep.txt`'s "REMEDIATION
  ROUND 1" section with the exact code mutation, the reddening output, and a
  same-run confirmation that the UNMUTATED shipped code passes.
- **Undeclared surface (Spec-AC-08's suite-file boundary)** —
  `tests/skills/lib/cd-subshell-leak-baseline.tsv` changed (3 -> 4 for
  `test-aai-orchestration-dispatch.sh`'s subshell count) as a side effect of this
  scope's TDD implementation adding CLI test coverage, but the file sits outside
  this spec's declared surface (see `## Scope` and the Inline review scope below)
  and outside the recorded code-review scope. Declared here per the
  additive-with-disclosure convention: the Inline review scope line under
  `## Isolation and review` now names it, and this remediation returns a
  `state.mjs set-code-review --scope` command widening `docs/ai/STATE.yaml`
  `code_review.scope` to match, for the orchestrator to run (subagents do not
  write STATE — `.aai/SUBAGENT_CONTRACT.md` single-writer rule).

No new Spec-AC, no new Test ID — every change above extends an EXISTING test's
fixtures/assertions (TEST-038, TEST-050, TEST-051, TEST-053, TEST-058) or is a
declared-surface note.

### Round 2 — remediation of code-review NON-BLOCKING dispositions (2026-09-13)

Independent code review (`docs/ai/reviews/review-harness-universal-routing-20260913T002056Z.md`,
overall `pass`, 0 BLOCKING, 7 NON-BLOCKING) dispositioned six findings
`remediate-in-tree`. This records that remediation; `SPEC-FROZEN: true` is
preserved and no existing AC's text moves or is deleted. No new Spec-AC, no
new Test ID — every fix below extends an EXISTING test (TEST-038, TEST-051,
TEST-053, TEST-058) or a header comment/doc-only change.

- **NB-1 (fallback arm asserted at one harness value)** — `test_038` gained a
  second, independent fixture under `AAI_HARNESS=codex` asserting
  `o.harness === "codex"` and `o.suggested_model === "gpt-5"` (never the
  claude sentinel). No source change. Mutation: hardcoding
  `fallback.harness = 'claude'` reddens the new codex arm (observed:
  `assert failed: "harness" in o && o.harness === "codex"`, got
  `"harness":"claude"`), while leaving the pre-existing claude arm green.
- **NB-2 (`startIdx + 1` unpinned upper/self boundary)** — `test_053` gained a
  case where the routed tier (`premium`, the top of `TIER_ORDER`) is the ONLY
  differing candidate anywhere in the harness map (`roles@codex: { Validation:
  gpt-5-mini }` colliding with `implementer_model` at `suggested_tier:
  premium`, `tiers@codex.premium` differing). No source change (the shipped
  scan already starts at `startIdx`, not `startIdx + 1` — the gap was
  test-only). Mutation: `for (let i = startIdx + 1; ...)` reddens (observed:
  `AssertionError: expected 'gpt-5.3-codex-premium-nb2', got 'gpt-5-mini'` —
  the loop walks off the end of `TIER_ORDER` and the residual token fires
  instead of the in-map swap).
- **NB-3 (`validation_alternate@H` alone untested for Mode B)** — `test_058`
  gained a fourth fixture carrying ONLY `validation_alternate@codex:` (no
  `tiers@codex:`/`roles@codex:`) alongside a leftover unsuffixed `tiers:` row,
  symmetric with the existing N6 (`roles@<harness>`-only) case. No source
  change. Mutation: dropping `routing.mode = 'B'` from the
  `validation_alternate(?:@...)` branch reddens (observed:
  `assert failed: o.suggested_model === null`, got
  `"suggested_model":"leftover-must-never-leak-nb3"` — the file stayed Mode A
  and the leftover unsuffixed row leaked to both harnesses).
- **NB-4 (`--human` claims the routing file is absent when it is present)** —
  `orchestration-dispatch.mjs`: `humanBlock` now takes the loaded `routing`
  and a new `suggestedModelUnboundReason(out, routing)` helper distinguishes
  a genuinely absent/unreadable file (`routing === null`, the pre-existing
  string) from a present Mode B file with no `@<harness>` section for the
  detected harness (a new, truthful string naming the harness), falling back
  to a generic "no matching tier/role" string for every other null case
  (Mode A no-match, or a non-`dispatch` verdict). `test_051`'s cursor arm
  gained `--human` and two assertions: the new string appears, and the old
  "no .aai/system/MODEL_ROUTING.yaml" string does not. Mutation: restoring
  the old unconditional string reddens the first assertion (observed:
  `Suggested model id: (unbound — no .aai/system/MODEL_ROUTING.yaml)` printed
  against a fixture where three OTHER harnesses resolve real sentinels from
  that same file).
- **NB-6, documentation half only** — an `UPGRADING` paragraph was added to
  `.aai/system/MODEL_ROUTING.yaml`'s header stating plainly that the file is
  core-vendored and `/aai-update` overwrites a consumer's copy; a consumer's
  Mode A back-compat (Spec-AC-06) is a property of the CODE reading an
  old-shaped file, not a guarantee the file itself survives an update, and a
  customization is preserved across updates only by re-applying it as
  `@<harness>` section(s). The `aai-sync.sh` preserve-rule half of NB-6 is
  explicitly OUT of scope here (tracked by
  `fu-routing-file-overwritten-on-update`, filed at round-1 freeze) and is
  untouched.
- **NB-7 (four GREEN artifacts predated the tests they evidence)** —
  `green-050.txt`, `green-051.txt`, `green-053.txt` and `green-058.txt` under
  `docs/ai/tdd/spec-harness-universal-routing/` were re-captured against the
  CURRENT test file (individual `test_0NN_...` runs); each now carries its
  named clause (N8 in 050, N3 in 051, N5+NB-2 in 053, N6+NB-3 in 058).
  Evidence-only; no source or test assertion changed by this item itself.
- **INFO-1 (`suggestModel` mutates its argument, undocumented)** — one comment
  added immediately above `suggestModel`'s declaration stating it both
  returns a value and mutates `out.validator_independence` in place; left
  non-mutating rewrite NOT done (single call site, mutated object is the one
  printed as the verdict — no behavior difference either way, so the comment
  is the whole fix).

Left alone, per the review's own disposition (not this scope's to fix):
**NB-5** (out-of-set/mis-cased `@<harness>` suffix degrades to `null` silently
— follow-up, contradicts D2's literal absent-file parity text, needs an owner
decision) and **INFO-2** (`test_056` re-implements the routing parser inline
rather than importing `loadModelRouting` — deliberate, stronger-as-evidence
per the reviewer's own read). Both are pre-existing filed items, untouched.

Full verification re-run after all of the above (`env -u AAI_ROLE bash
tests/skills/test-aai-orchestration-dispatch.sh`): 83 PASS lines (81 test headers, 58 top-level invocations), exit 0 — the round-2 text said 84; round-3 validation measured 83 and this line was corrected after the round-3 verdict (text-only).
`test-framework.sh --skill aai-orchestration-dispatch --skill
aai-layer-profiles --skill aai-hygiene-pack --skill aai-token-capture`: 4/4
PASS. Mode A byte-identity (TEST-055) against the pinned blob
`0fb736ca831c9646d5b06d13fe5f62039cba02e7` still holds (stdout/exit identical
on every harness once the additive `harness` key is excluded) — the round-2
changes touch only the fallback re-stamp assertion depth, the D4 tier-scan
test depth, the Mode B trigger test depth, and the `--human`
already-in-scope string, none of which the Mode A arm (`routing.mode !==
'B'`) reaches.

## Implementation strategy
- Strategy: tdd
- Rationale: recorded at intake by the user (CHANGE-0182 `## Notes`, `Implementation mode (user choice): tdd`). Behavioral and multi-surface — detector, routing parser, two resolution modes, validator independence, PRICING resolution — and resolution order is exactly the logic where a test that cannot fail passes a wrong routing silently. Planning keeps the recorded choice.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: this scope edits `.aai/scripts/orchestration-dispatch.mjs`, the script the orchestrator executes on EVERY tick. A half-applied edit inline does not merely fail a test — it breaks the loop that is running the ride. The checkout is additionally shared between sessions (scar of 2026-09-06, P1). Neither condition is `required`: no `protected_paths_l3` surface is touched and no fixture merges into a repository.
- User decision: undecided
- Base ref: main (branch `feat/harness-universal-routing`, off 181d67e0)
- Worktree branch/path: to be decided by Implementation Preparation
- Inline review scope: `.aai/scripts/orchestration-dispatch.mjs .aai/scripts/lib/harness.mjs .aai/system/MODEL_ROUTING.yaml .aai/system/PROFILES.yaml .aai/SUBAGENT_PROTOCOL.md tests/skills/test-aai-orchestration-dispatch.sh tests/skills/lib/cd-subshell-leak-baseline.tsv` (the `.tsv` addition is a remediation-round-1 disclosure — see `## Amendment` above — of a mechanical byte-count ratchet update the TDD implementation triggered as a side effect, 3 -> 4 for `test-aai-orchestration-dispatch.sh`)

## Registry items closed by this scope

None. `node .aai/scripts/follow-ups.mjs list` was read in full at freeze. Two open
items sit adjacent to this surface and are deliberately NOT closed here:

- `fu-dispatch-gate-spawn-seam-untested` (P3) — the untested seam is `roadmapGate`'s
  spawn path, a different subsystem of the same file. This scope adds no roadmap-gate
  coverage and closing it would be a false claim.
- `fu-role-guard-blocks-own-fixtures` (P2, filed 2026-09-12) — the `AAI_ROLE=subagent`
  marker makes three CORE suites refuse their own fixtures. It affects how this scope's
  suites are RUN, not what they assert; the fix is a `state.mjs` guard change, outside
  this scope's declared surface.

## What is established before this scope starts

Measured on 2026-09-12 under bash with `/usr/bin/grep` (`grep` is aliased to ugrep
in the authoring shell; every count below was taken under `bash -c`).

1. `.aai/system/MODEL_ROUTING.yaml` binds `tiers`, `roles`, `validation_alternate`,
   `effort_tiers`, `effort_roles`. It is line-parsed by `loadModelRouting()` at
   exactly ONE level of nesting (`  <key>: <value>` under a flush-left section header).
2. `suggestModel(out, routing)` resolves `roles[role@lane] ?? roles[role] ?? tiers[tier] ?? null`,
   then swaps to `validation_alternate` when the routed Validation model equals the
   recorded implementer model. There is NO harness detection anywhere in the file and
   the verdict JSON has no `harness` key.
3. The shipped Claude ids are `claude-haiku-4-5`, `claude-sonnet-5`, `claude-opus-4-8`.
4. `.aai/system/MODEL_ROUTING.yaml` has exactly ONE consumer:
   `.aai/scripts/orchestration-dispatch.mjs`. Three prompts point at it in prose
   (`ORCHESTRATION`, `ORCHESTRATION_PARALLEL`, `SKILL_SHIP`) and `PROFILES.yaml`
   classifies it. Nothing else reads it.
5. `PRICING.yaml` is already multi-vendor and its resolver
   (`.aai/scripts/lib/pricing.mjs` `resolveModelKey`) is shared by flush and report.
   Every id this spec ships was run through it before being chosen — see D5.
6. Harness identity already exists for DISPLAY only: `generate-live-status.mjs`
   probes `CLAUDE_CONFIG_DIR` / `CODEX_HOME` / `GEMINI_HOME` for its per-harness
   session parsers. `state.mjs log-tick` records a free-text `harness_version`.
   Neither is consulted by dispatch.
7. `aai-doctor.mjs` CAT-16 states the standing rule: an agent CLI is probed for real,
   "never inferred from a harness name", and the four SUBAGENT_PROTOCOL capability
   fields are runtime properties of the ORCHESTRATING SESSION, reported as literal
   `UNKNOWN` because a child process cannot observe them.
8. Environment variables, unlike capabilities, ARE inherited by child processes.
   Measured in this session: a Bash child of a Claude Code session sees `CLAUDECODE`,
   `CLAUDE_CODE_ENTRYPOINT` and `CLAUDE_CODE_SESSION_ID` set. The same `env` dump also
   shows `GEMINI_CLI_IDE_SERVER_PORT`, `GEMINI_CLI_IDE_AUTH_TOKEN` and
   `GEMINI_CLI_IDE_WORKSPACE_PATH` set INSIDE a Claude Code session — an IDE-companion
   leak. That single measurement is why D3 below excludes the `GEMINI_CLI_IDE_*` family
   from the evidence ladder; a naive "any GEMINI_ variable means gemini" detector would
   have misread this very session.

## Decisions

### D1 — Key form: a flattened `@<harness>` section suffix, not deeper nesting

Sections may carry an `@<harness>` suffix: `tiers@claude:`, `roles@codex:`,
`validation_alternate@gemini:`. Rows underneath keep the exact two-space
`  <key>: <value>` shape. Chosen over extending the parser to two levels because:

- the file ALREADY uses `@` as its scoping sigil (`Validation@lightweight`), so a
  reader meets one convention, not two;
- the header's "nesting deeper than one level is not read" contract stays literally
  true, so the parser's blast radius is one regex per section header rather than a
  state machine;
- back-compat is structural rather than argued: a file with no `@` section suffix
  parses into byte-identical maps.

Back-compat is a requirement, not a courtesy: downstream AAI projects hold their own
copy of this file.

### D2 — Two resolution modes, decided by the FILE, never by the harness

- **Mode A (legacy file)** — the file declares ZERO `@<harness>` sections. Resolution
  is exactly today's, on every harness, including the validator-independence swap.
  Byte-identical output (Spec-AC-06).
- **Mode B (harness-aware file)** — the file declares at least one `@<harness>`
  section. The detected harness H selects `tiers@H` / `roles@H` /
  `validation_alternate@H`. A harness with no sections — `unknown` included — gets
  `suggested_model: null`, and `suggested_tier` stands, exactly as when the file is
  absent.
- In Mode B the unsuffixed `tiers:` / `roles:` / `validation_alternate:` sections are
  NOT consulted for model resolution. Falling through to them is the bug this ride
  exists to remove: it is precisely how a Codex loop gets handed `claude-opus-4-8`.
  Because silence there would be indistinguishable from a typo, a Mode B file that
  still carries unsuffixed model rows emits ONE stderr NOTE naming them and continues
  (Constitution article 4, degrade and report). The shipped file carries none, so the
  NOTE never fires on a clean install.
- `effort_tiers` / `effort_roles` are NOT harness-scoped and are read identically in
  both modes. Reasoning effort is a property of the ROLE, not of the vendor, and
  scoping it per harness would multiply the config without a behavior to justify it.

### D3 — Detection is a pure function of `process.env` with zero filesystem I/O

`.aai/scripts/lib/harness.mjs` exports `detectHarness(env)`. Ordered, first match wins:

1. `AAI_HARNESS` set and non-empty. Value in the closed set
   `claude` / `codex` / `gemini` / `cursor` / `unknown` wins outright; any other value
   resolves `unknown` and emits one stderr NOTE.
2. `CLAUDECODE` or `CLAUDE_CODE_ENTRYPOINT` non-empty then `claude`.
3. `CODEX_HOME` or `CODEX_SANDBOX` non-empty then `codex`.
4. `CURSOR_TRACE_ID` or `CURSOR_AGENT` non-empty then `cursor`.
5. `GEMINI_HOME` non-empty then `gemini`.
6. Otherwise `unknown`.

`unknown` is a first-class value: it never changes an exit code and it yields
`suggested_model: null`, which is today's behavior for a project with no routing file.

Evidence deliberately EXCLUDED, each with the reason it is not evidence:

- `GEMINI_CLI_IDE_*` — measured present inside a Claude Code session (point 8 above).
- `CLAUDE_CONFIG_DIR` — a user config override; people export it who are not running
  Claude Code. It is a path preference, not a process identity.
- the repository trees `.claude/`, `.codex/`, `.gemini/`, `.cursor/`, `.agents/` —
  vendored mirrors present in EVERY AAI project regardless of what is running.
- `~/.codex/sessions`, `~/.gemini/tmp` and their siblings — evidence that a harness was
  once installed, not that it is running now.
- any model name — the standing rule at `aai-doctor.mjs` CAT-16.

Zero filesystem I/O is what makes "cheap enough to run every tick" true by
construction rather than by benchmark.

### D4 — Validator independence resolves inside the detected harness

For a Validation dispatch in Mode B whose routed model equals the recorded
`implementer_model`, in order:

1. scan `tiers@H` at or above the routed tier (`mechanical` below `standard` below
   `premium`) and take the first id that differs;
2. otherwise `validation_alternate@H` when present and different;
3. otherwise keep the routed model AND set `validator_independence.residual` to the
   literal token `single_model_harness_reuse`, which is the residual the protocol
   already names for single-model environments.

Never an id from another harness's map: a Codex validator proposed a Claude id is
worse than no swap, because the loop would act on it.

Mode A keeps step 2 alone, unchanged — that is what makes Spec-AC-06 provable rather
than argued.

### D5 — The shipped maps, and why each id

Every id below was resolved through the real shared resolver before being written
here (`node -e` against `.aai/scripts/lib/pricing.mjs` `resolveModelKey` and the
shipped `PRICING.yaml`, 2026-09-12). All resolve EXACTLY. No `PRICING.yaml` edit is
needed in this scope.

- claude — mechanical `claude-haiku-4-5`, standard `claude-sonnet-5`, premium
  `claude-opus-5`; `Planning` and `Code Review` `claude-opus-5`; `Metrics Flush`
  `claude-haiku-4-5`; `Validation@lightweight` `claude-sonnet-5`;
  `validation_alternate@claude` `claude-opus-5`.
  Premium is `claude-opus-5` and NOT `claude-fable-5-1`, on a measurement:
  `claude-fable-5-1` is absent from `PRICING.yaml` and the longest-prefix rule maps it
  to `claude-fable-5` at 10.00 in / 50.00 out, against `claude-opus-5` at 5.00 / 25.00.
  Routing to it would silently double every premium run's recorded cost — in the very
  ledger wave 2 is ranked on. `claude-opus-5` resolves exactly, is already in
  `METRICS.jsonl` history, and is the model this factory demonstrably runs at premium.
  `claude-opus-4-8` leaves the routing file entirely; its `PRICING.yaml` entry stays,
  because history refers to it.
- codex — mechanical `gpt-5-mini`, standard `gpt-5`, premium `gpt-5.3-codex`;
  `Planning` and `Code Review` `gpt-5.3-codex`; `Metrics Flush` `gpt-5-mini`;
  `validation_alternate@codex` `gpt-5.3-codex`.
- gemini — mechanical `gemini-3-flash-preview`, standard `gemini-3-flash-preview`,
  premium `gemini-3-pro-preview`; `Planning` and `Code Review` `gemini-3-pro-preview`;
  `Metrics Flush` `gemini-3-flash-preview`;
  `validation_alternate@gemini` `gemini-3-pro-preview`.
  Mechanical and standard bind the SAME id: the current Gemini 3 lineup published in
  `PRICING.yaml` has two members, not three. Disclosed rather than papered over with a
  previous-generation id; the mechanical-versus-standard distinction survives on the
  effort axis, which is harness-independent.
- cursor — detected, but ships NO map, so `suggested_model` is null there. Cursor runs
  whichever model the user selected; inventing a binding would assert a fact this
  project has not measured.

### D6 — `harness` is carried on every verdict

`out.harness` is a top-level string from the closed set, present on `dispatch`,
`no_action` AND `needs_llm` verdicts — unlike `prompt_hash`, which is dispatch-only
because it hashes a role prompt that a no-action tick does not have. The harness is a
property of the PROCESS, so every verdict can state it, and the paired maintenance
ride (`telemetry-fields-not-prose`, CHANGE-0183) consumes it from there. `--human`
gains one `Harness:` line. Exit codes are untouched in every arm.

Detection runs ONCE per process, at the single resolution site, and is recorded with
the verdict — which is what preserves the file's HARD no-mid-session-flip rule.

## Scope

In scope: `detectHarness`; the `@<harness>` section form and its parser support; Mode
A / Mode B resolution; per-harness validator independence and its residual; `harness`
on every verdict; the shipped Claude, Codex and Gemini maps; the `MODEL_ROUTING.yaml`
header contract; the `PROFILES.yaml` classification of the new file; the
`SUBAGENT_PROTOCOL.md` validator-rule sentence; the suite.

Out of scope, stated so the delivery is not read as more than it is:

- **This ride does not prove that AAI works on Codex or Gemini.** No Codex or Gemini
  session executes any of this. The `codex` and `gemini` arms are proven by env
  fixtures and by PRICING resolution, not by a real harness running a real ride. The
  proof is the separate wave-2 list item `cross-harness-universality-proof`.
- Recording the harness on runs and on friction observations (CHANGE-0183).
- Which roles are delegable (RES-0002 stands unchanged; the cheap-implementer and
  strong-verifier split is a TIER statement, and this ride changes only the binding).
- `PRICING.yaml` content (no edit needed — D5).
- `.aai/STATE_FALLBACK.md` (measured: it carries no routing id).

## Constitution deviations

None.

- Article 2 (simplicity): one new 60-line pure module and one regex family in an
  existing parser; no framework, no dependency.
- Article 3 (portability): this scope is the article's direct subject — it makes the
  tri-platform claim true for routing instead of asserted.
- Article 4 (degrade and report): `unknown` degrades to today's null binding, and a
  half-migrated Mode B file is named on stderr rather than silently ignored.
- Article 5 (additive first): `harness` is an additive key and Mode A is byte-identity,
  pinned by a test against the pre-change script.

## Acceptance Criteria Mapping

- Maps to: CHANGE-0182 AC-001 through AC-007.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN any tick runs the dispatcher the verdict JSON SHALL carry a top-level `harness` string from the closed set on all three verdict kinds, and the exit code SHALL be unchanged in every arm. | done | docs/ai/tdd/spec-harness-universal-routing/red-050.txt; green-050.txt | — | TEST-050 |
| Spec-AC-02 | WHEN `detectHarness(env)` is called it SHALL return the first match of the D3 ladder, with `AAI_HARNESS` outranking every probe, an out-of-set `AAI_HARNESS` value resolving `unknown`, and an empty env resolving `unknown`. | done | docs/ai/tdd/spec-harness-universal-routing/red-048.txt; green-048.txt; mutation-sweep.txt (M1, M2) | — | TEST-048 |
| Spec-AC-03 | WHEN the env carries `GEMINI_CLI_IDE_SERVER_PORT`, or `CLAUDE_CONFIG_DIR`, or the root carries `.claude/`, `.codex/` and `.gemini/` directories, detection SHALL NOT be decided by any of them. | done | docs/ai/tdd/spec-harness-universal-routing/red-049.txt; green-049.txt; mutation-sweep.txt (M3, M4, M5) | — | TEST-049 |
| Spec-AC-04 | WHEN a Mode B routing file is present, a dispatch under `codex` SHALL resolve `suggested_model` from the codex map and never to an id starting `claude-`, and a harness with no map SHALL resolve null with `suggested_tier` unchanged. | done | docs/ai/tdd/spec-harness-universal-routing/red-051.txt; green-051.txt; red-052.txt; green-052.txt; mutation-sweep.txt (M7, M8) | — | TEST-051, TEST-052 |
| Spec-AC-05 | WHEN a Validation dispatch's routed model equals `implementer_model`, the replacement SHALL come from the detected harness's own map, and WHEN that map cannot supply a different id the verdict SHALL carry `validator_independence.residual` equal to `single_model_harness_reuse` rather than a foreign vendor's id. | done | docs/ai/tdd/spec-harness-universal-routing/red-053.txt; green-053.txt; red-054.txt; green-054.txt; mutation-sweep.txt (M9, M10, M11) | — | TEST-053, TEST-054 |
| Spec-AC-06 | WHEN the routing file declares no `@<harness>` section, the dispatcher's stdout JSON and exit code SHALL be identical to the pinned pre-change script's on the same STATE fixture once the additive `harness` key is removed, on every harness. | done | docs/ai/tdd/spec-harness-universal-routing/green-055.txt; mutation-055.txt | — | TEST-055 cannot RED by construction (Mutation checks); mutation-055.txt substitutes |
| Spec-AC-07 | WHEN every model id in every section of the SHIPPED `MODEL_ROUTING.yaml` is run through `resolveModelKey` against the SHIPPED `PRICING.yaml`, no id SHALL resolve to `unknown`. | done | docs/ai/tdd/spec-harness-universal-routing/red-056.txt; green-056.txt; mutation-056.txt | — | TEST-056 |
| Spec-AC-08 | The shipped routing file SHALL contain zero occurrences of `claude-opus-4-8`, and `tiers@claude` SHALL name exactly `claude-haiku-4-5`, `claude-sonnet-5` and `claude-opus-5`. | done | docs/ai/tdd/spec-harness-universal-routing/red-057.txt; green-057.txt | — | TEST-057; TEST-020's shipped-file grep updated in the same commit |
| Spec-AC-09 | The routing parser SHALL keep the one-level row shape, the file header SHALL state the `@<harness>` key form, the resolution order and the Mode A versus Mode B rule, and a Mode B file carrying leftover unsuffixed model rows SHALL emit one stderr NOTE naming them while stdout stays valid JSON and the exit code is unchanged. | done | docs/ai/tdd/spec-harness-universal-routing/red-058.txt; green-058.txt; red-060.txt; green-060.txt; mutation-sweep.txt (M12, M13, M14) | — | TEST-058, TEST-060 |
| Spec-AC-10 | The new `.aai/scripts/lib/harness.mjs` SHALL be classified in `.aai/system/PROFILES.yaml` so the live-tree union invariant holds. | done | docs/ai/tdd/spec-harness-universal-routing/red-059.txt; green-059.txt | — | TEST-059 (test-aai-layer-profiles.sh) |

## Implementation plan

Components affected:

- `.aai/scripts/lib/harness.mjs` (new) — `detectHarness(env)` plus the exported closed
  set. Pure, no I/O, no imports beyond none.
- `.aai/scripts/orchestration-dispatch.mjs` — `loadModelRouting()` gains `@<harness>`
  section parsing and a Mode A / Mode B flag; `suggestModel()` gains harness selection
  and the D4 independence resolution; `main()` sets `out.harness` before routing;
  `humanBlock()` gains one line.
- `.aai/system/MODEL_ROUTING.yaml` — header contract plus the three maps.
- `.aai/system/PROFILES.yaml` — one `core:` entry.
- `.aai/SUBAGENT_PROTOCOL.md` — the validator rule gains the within-harness clause and
  the `single_model_harness_reuse` residual token. This file sits OUTSIDE the prompt
  corpus glob (`.aai/*.prompt.md` plus the AGENTS / INTAKE_COMMON / STATE_FALLBACK /
  ROLE_COMMON extras), per the precedent recorded in the prompt-diet ledger, so it
  carries no ledger cost. No `.aai/*.prompt.md` byte changes in this scope, so the
  prompt-diet companion obligation does not apply.
- `tests/skills/test-aai-orchestration-dispatch.sh` — TEST-048 through TEST-060, and
  TEST-020's shipped-file grep updated to the new section (it currently pins
  `^  Metrics Flush: claude-haiku-4-5$` at the top level).

Data flow: orchestrating session env → inherited by the dispatcher child → `out.harness`
→ map selection → `suggested_model` and `validator_independence` → the orchestrator's
spawn decision → `append-run`'s recorded model → flush's cost arithmetic via PRICING.

Edge cases: empty env; `AAI_HARNESS` set to junk; `AAI_HARNESS` set to the empty
string (treated as unset); a Mode B file whose selected harness section exists but is
empty; a Mode B file carrying leftover unsuffixed rows; a routing file that is present
but unreadable (already returns null today, unchanged); `implementer_model` null.

One hazard the implementer must respect, or the suite passes locally and fails only on
CI: the suite itself runs INSIDE a harness. `CLAUDECODE` is set in a developer's
session and absent on a GitHub runner, so any test that does not control the child's
env asserts different things in the two places. Every new test either scrubs the
harness variables (`env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT ...`) or sets
`AAI_HARNESS` explicitly. No new test may read the ambient environment.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-048 | Spec-AC-02 | unit | tests/skills/test-aai-orchestration-dispatch.sh | Pure `detectHarness(env)` ladder table — each of the five markers, the `AAI_HARNESS` override for all five values, an out-of-set override value, an empty-string override, and an empty env. | green |
| TEST-049 | Spec-AC-03 | unit | tests/skills/test-aai-orchestration-dispatch.sh | Negative controls — `CLAUDECODE` plus `GEMINI_CLI_IDE_SERVER_PORT` together resolve `claude`, `GEMINI_CLI_IDE_SERVER_PORT` alone resolves `unknown`, `CLAUDE_CONFIG_DIR` alone resolves `unknown`. | green |
| TEST-050 | Spec-AC-01 | integration | tests/skills/test-aai-orchestration-dispatch.sh | CLI — `harness` present on a dispatch (exit 0), a paused no_action (exit 3) and a broken-state needs_llm (exit 4) verdict; scrubbed env reads `unknown`; `AAI_HARNESS=codex` reads `codex`; the three exit codes are identical with and without the override. | green |
| TEST-051 | Spec-AC-04 | integration | tests/skills/test-aai-orchestration-dispatch.sh | CLI over a Mode B fixture — codex resolves a codex sentinel and no id matching `^claude-`, claude resolves the claude sentinel, cursor resolves null with `suggested_tier` equal to the claude arm's, unknown resolves null. | green |
| TEST-052 | Spec-AC-04 | unit | tests/skills/test-aai-orchestration-dispatch.sh | Pure per-harness precedence — `roles@H[role@lane]` then `roles@H[role]` then `tiers@H[tier]` then null, with distinct sentinels per harness, plus the control that a `@codex` row never satisfies a claude lookup and vice versa. | green |
| TEST-053 | Spec-AC-05 | unit | tests/skills/test-aai-orchestration-dispatch.sh | Pure independence — a codex map whose standard id equals `implementer_model` resolves the codex PREMIUM id; a codex map that repeats one id with no alternate leaves the model unchanged and sets `residual` to `single_model_harness_reuse`; no arm ever returns an id from another harness's map. | green |
| TEST-054 | Spec-AC-05 | integration | tests/skills/test-aai-orchestration-dispatch.sh | CLI end to end — the residual token appears on a real Validation verdict's `validator_independence` block and on the `--human` stderr line, exit code unchanged. | green |
| TEST-055 | Spec-AC-06 | integration | tests/skills/test-aai-orchestration-dispatch.sh | Byte-identity — a legacy unsuffixed routing fixture run through the pinned pre-change blob and through the current script on the same STATE fixture produce identical stdout once the additive `harness` key is deleted, and identical exit codes; repeated under `AAI_HARNESS=codex` to prove Mode A is harness-independent. | green |
| TEST-056 | Spec-AC-07 | integration | tests/skills/test-aai-orchestration-dispatch.sh | PRICING sweep — every id in every section of the SHIPPED routing file resolved through `lib/pricing.mjs` against the SHIPPED `PRICING.yaml`; any `unknown` fails, and the sweep asserts it examined at least one id per shipped harness map. | green |
| TEST-057 | Spec-AC-08 | integration | tests/skills/test-aai-orchestration-dispatch.sh | Shipped-file contract — zero occurrences of `claude-opus-4-8`, the three `tiers@claude` rows exactly as specified, and the explicit `Metrics Flush` row present under `roles@claude`. | green |
| TEST-058 | Spec-AC-09 | integration | tests/skills/test-aai-orchestration-dispatch.sh | Header contract and loud degrade — the shipped header states the `@<harness>` form, the resolution order and the Mode A versus Mode B rule; a fixture carrying both `tiers@codex:` and an unsuffixed `tiers:` emits one stderr NOTE naming the ignored rows while stdout stays parseable JSON and the exit code is unchanged. | green |
| TEST-059 | Spec-AC-10 | integration | tests/skills/test-aai-layer-profiles.sh | The live-tree classification invariant over the new `.aai/scripts/lib/harness.mjs`, run as `bash tests/skills/test-aai-layer-profiles.sh`. | green |
| TEST-060 | Spec-AC-09 | unit | tests/skills/test-aai-orchestration-dispatch.sh | Parser shape guard — a four-space-indented key under `tiers@codex:` is NOT read, proving the one-level nesting contract is unchanged by the new section form. | green |

Every Spec-AC has at least one TEST row and every TEST row names exactly one Spec-AC.
Test ids continue the suite's existing sequence, which ends at TEST-047.

## Mutation checks

The scope this repository shipped immediately before this one carried five controls
that claimed a property they did not test; four were caught by mutation and one by an
external bot, after four internal rounds. So every test above is paired here with the
source mutation that MUST redden it, and any test that cannot go RED by construction is
named as such with the mutation control that substitutes for its RED.

Recorded under `docs/ai/tdd/spec-harness-universal-routing/`, one file per entry,
each holding the failing output. Every mutation is applied to a scratch COPY of the
tree, never to the shipping file (HAZ-RESTORE, HAZ-SCRATCH).

RED-first — these assert behavior that does not exist on the pre-change tree, so each
is observed FAILING there before any engine edit: TEST-048, TEST-049, TEST-050,
TEST-051, TEST-052, TEST-053, TEST-054, TEST-056, TEST-057, TEST-058, TEST-059,
TEST-060. `red-048.txt` through `red-060.txt`, minus `red-055.txt`.

- TEST-057 reddens on the pre-change tree because `claude-opus-4-8` IS present in the
  shipped file today; TEST-059 reddens because an unclassified new `.aai/**` file fails
  the live-tree union invariant. Both are genuine REDs, not vacuous passes.

CANNOT go RED by construction, so a mutation control stands in for the RED:

- `mutation-055.txt` — **required, and the one that matters most.** TEST-055 compares
  the pre-change script with the current one. On the pre-change tree both sides ARE the
  pre-change script, so it passes with this scope's implementation deleted. Its control
  is a deliberate mutation: remove the Mode A branch so an unsuffixed routing file is
  treated as Mode B. TEST-055 must then fail, because the `AAI_HARNESS=codex` arm
  resolves null where the pinned script resolved a model id. Without that recorded
  failure TEST-055 is evidence of nothing.
- `mutation-056.txt` — TEST-056 is half-tautological: every id in the routing file
  today already resolves, so the sweep passes before the maps are written. Its control
  is inserting `premium: gpt-9-does-not-exist` under `tiers@codex:` in the scratch copy,
  which must make TEST-056 fail naming that id. A second control deletes the whole
  `tiers@gemini:` section, which must make the "at least one id per shipped harness map"
  assertion fail — without it the sweep would pass vacuously over an empty set.

Additional mutations that must each redden a NAMED test, run in the same pass and
recorded in `mutation-sweep.txt`:

- Accepting any `AAI_HARNESS` value instead of the closed set must redden TEST-048.
- Moving the `GEMINI_HOME` probe above the `CLAUDECODE` probe must redden TEST-048.
- Adding `GEMINI_CLI_IDE_SERVER_PORT` to the gemini marker list must redden TEST-049.
- Adding `CLAUDE_CONFIG_DIR` to the claude marker list must redden TEST-049.
- Adding any `existsSync` probe of a `.codex` or `.gemini` directory to the detector
  must redden TEST-049, which is why that test's fixture root carries those directories.
- Emitting `harness` only on dispatch verdicts, mirroring `prompt_hash`, must redden
  TEST-050's no_action and needs_llm arms.
- Falling through to the unsuffixed `tiers:` when the detected harness has no map must
  redden TEST-051's cursor arm, which would then receive a claude id.
- Stripping the harness from the lookup key, so `roles@codex` can satisfy a claude
  lookup, must redden TEST-052.
- Starting the independence scan at `mechanical` instead of at the routed tier must
  redden TEST-053, which asserts the PREMIUM id is chosen.
- Consulting `validation_alternate@claude` when the detected harness is codex must
  redden TEST-053's foreign-id assertion.
- Omitting the `residual` field, or spelling its value differently, must redden
  TEST-053 and TEST-054.
- Deleting the stderr NOTE for leftover unsuffixed rows must redden TEST-058.
- Deleting any one of the three header contract sentences must redden TEST-058.
- Widening the row regex from two spaces to `\s+` must redden TEST-060.

Any mutation in that list that leaves every test green is a finding to fix in the test,
not a note to file.

## Seams

Each crossing is a place this scope shares state with something it does not own. Each
names the test that produces on one side and asserts on the other; two unit tests that
mock the boundary would test the mock.

1. **Dispatcher verdict JSON to its consumers.** A new top-level key travels to the
   loop, to `check-role-output.mjs` and into `append-run`. Crossed by TEST-050 (real
   CLI, real JSON) and TEST-055 (the whole stdout compared, not one field). Measured
   precondition: the suite's key-set assertions use `.every(k => k in o)` and no
   closed-key-set or key-count assertion exists over the verdict, so the key is
   additive-safe.
2. **This scope's `MODEL_ROUTING.yaml` to `PRICING.yaml`'s cost arithmetic**, owned by
   the metrics flush. Crossed by TEST-056, which runs the SHIPPED file through the
   SHARED resolver against the SHIPPED pricing file — not a copied lookup table.
3. **The shipped routing file to the suite's existing TEST-020 contract**, which greps
   for `^  Metrics Flush: claude-haiku-4-5$` at the top level and will break the moment
   the row moves under `roles@claude:`. Crossed by TEST-057, and TEST-020 is updated in
   the same commit rather than left to fail.
4. **A new `.aai/**` file to `PROFILES.yaml`'s union invariant.** Crossed by TEST-059
   against the LIVE tree, in the suite that owns the invariant.
5. **The orchestrating session's environment to the dispatcher child process.** This is
   the seam the whole feature rests on, and the doctor's CAT-16 note is about the
   adjacent one (capabilities are NOT observable from a child; env vars are). Crossed by
   TEST-050, which runs the real CLI under a controlled env rather than calling the
   detector directly.
6. **`validator_independence` to `SUBAGENT_PROTOCOL.md`'s validator rule and the
   orchestrator's spawn decision.** Crossed by TEST-054 (the verdict and the `--human`
   line a human reads) plus the protocol edit in the same commit.
7. **Mode A to every downstream project's existing routing file.** Crossed by TEST-055
   against a pinned pre-change blob — the only form of back-compat proof this repository
   accepts as evidence.

Residual risks, written down because no automated test crosses them:

- **R1** — no Codex, Gemini or Cursor session executes this code in CI. The non-Claude
  arms are proven by env fixtures and by PRICING resolution, never by a real harness.
  Tracked as the wave-2 item `cross-harness-universality-proof`.
- **R2** — the Codex and Cursor marker variable names (`CODEX_HOME`, `CODEX_SANDBOX`,
  `CURSOR_TRACE_ID`, `CURSOR_AGENT`) are assumptions, not measurements; only the Claude
  markers and the `GEMINI_CLI_IDE_*` leak were measured in a live session. A wrong
  marker name degrades to `unknown`, which is today's behavior, and `AAI_HARNESS` is the
  documented override. Confirming them is part of R1's proof ride.
- **R3** — `gemini-3-pro-preview` and `gemini-3-flash-preview` carry PREVIEW pricing
  in `PRICING.yaml`. Costing a Gemini run is therefore approximate until those rates
  are re-verified; the ids resolve, so nothing falls to `unknown`.
- **R4** — the `harness` value is recorded on the verdict but nothing yet asserts it
  against what the loop actually spawned. That crossing is the paired maintenance ride.

## Verification

- `bash tests/skills/test-aai-orchestration-dispatch.sh` — all of TEST-048 through
  TEST-058 and TEST-060 green, and the pre-existing TEST-001 through TEST-047 green.
- `bash tests/skills/test-aai-layer-profiles.sh` — TEST-059.
- `bash tests/skills/test-aai-pricing.sh` — unchanged, run because this scope reasons
  about the resolver it owns.
- One full `bash tests/skills/test-framework.sh` sweep before the close ceremony
  (`AAI_TEST_TIMEOUT=3000`), per the VALIDATION suite-scope-per-round rule.
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0177-spec-harness-universal-routing.md`
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event --path docs/specs/SPEC-0177-spec-harness-universal-routing.md`
- PASS criteria: every TEST row green AND every Spec-AC in a terminal status.

## Evidence contract

- ref_id: `harness-universal-routing`
- RED artifacts: `docs/ai/tdd/spec-harness-universal-routing/red-0NN.txt`, one per
  RED-first test named in `## Mutation checks`.
- Mutation artifacts: `mutation-055.txt`, `mutation-056.txt`, `mutation-sweep.txt` in
  the same directory. A test named there as mutation-only has NO red file and MUST have
  its mutation file; the two sets are disjoint and together cover all thirteen tests.
- Per-test green runs with exit codes, plus the scoped diff.
- Commit SHA or diff range on every artifact.

Strategy row (tdd): a stored RED artifact per AC-gating test plus the full verification
matrix. The two tests that cannot RED are covered by the recorded mutation failures
instead, which is the substitution this section exists to declare.
