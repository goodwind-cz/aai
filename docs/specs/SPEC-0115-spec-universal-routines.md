---
id: spec-universal-routines
type: spec
number: 115
status: implementing
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0128-universal-routines.md
  rfc: null
  pr: []
  commits: []
---

# Spec — Standing routines become a vendored, on-demand, agent-neutral template

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0128-universal-routines.md
- Decision records: docs/ai/decisions.jsonl line 83 (2026-08-06 human
  authorization for the morning scryer, incl. merge)
- Technology contract: docs/TECHNOLOGY.md

## Summary

Today the morning scryer routine exists ONLY as an Anthropic-cloud trigger
config (`trig_01XpMxioptoJ7j32YKzzaKnR`) created by a hand-rolled API call.
The repository holds nothing of it but the merge authorization in
`docs/ai/decisions.jsonl`. It is not reproducible, not reviewable, not
portable off Claude cloud, and it was never test-fired at creation (it
crashed on its first real run — `docs/knowledge` memory rule
`cloud-routine-test-at-creation`).

This change turns the routine into what every other durable AAI artifact
already is: a plain, git-diffable, agent-neutral template in the vendored
layer, plus a deterministic emitter that instantiates it ON DEMAND for the
harness the operator names. A merge-enabled instantiation is gated on a
machine-checkable authorization record; without one, the emitter degrades to
a report-only routine and says so loudly. Every emission carries a
test-at-creation block.

The emitter never installs anything and never calls a network API: it prints
a payload the operator (or the harness's own scheduling skill) installs. That
keeps it side-effect-free, testable offline, and portable.

## Implementation strategy
- Strategy: hybrid
- Rationale: TDD (RED first) for the two behaviors whose failure mode is
  silent and consequential — the merge-rights guard (a false positive grants
  a cron agent write authority on the repo) and the placeholder renderer
  (an unresolved or mis-substituted placeholder ships a broken routine) — and
  loop for the low-risk glue: the routine template prose, the four skill
  wrappers, SKILLS.md / suite-map rows, and the PROFILES + prompt-diet
  governance true-ups. STATE carried no intake-sourced strategy for this
  scope (the recorded `hybrid` belongs to the CHANGE-0127 ride), and the
  intake's `## Acceptance Criteria` records no `Implementation mode (user
  choice):` line, so this is Planning's call.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: the scope is additive — one new `.aai/routines/`
  directory, one new emitter script, one new thin-wrapper prompt, four
  wrapper stubs, one new test suite, and governance rows. No
  `protected_paths_l3` surface is touched (state engine, allocator,
  pre-commit guards, `.aai/workflow/WORKFLOW.md`, `docs/CONSTITUTION.md` —
  none appear in the file list). Work is already on a dedicated branch
  (`feat/universal-routines`), so isolation buys little beyond what the
  branch already gives.
- User decision: undecided
- Base ref: main
- Worktree branch/path: feat/universal-routines (current checkout)
- Inline review scope: .aai/routines/SCRYER.routine.md,
  .aai/scripts/routine-emit.mjs, .aai/SKILL_ROUTINE.prompt.md,
  .claude/skills/aai-routine/SKILL.md, .agents/skills/aai-routine/SKILL.md,
  .codex/skills/aai-routine/SKILL.md, .gemini/skills/aai-routine/SKILL.md,
  .aai/system/PROFILES.yaml, SKILLS.md, tests/skills/suite-map.yaml,
  tests/skills/lib/prompt-diet-ledger.sh, tests/skills/test-aai-prompt-diet.sh,
  tests/skills/test-aai-routine.sh, tests/fixtures/routines/**,
  docs/ai/decisions.jsonl, docs/specs/SPEC-0115-spec-universal-routines.md,
  docs/issues/CHANGE-0128-universal-routines.md

## Design decisions

- D1 — The Claude emission is a routine SPEC BLOCK, not a hand-rolled HTTP
  call. The repo holds zero evidence of the Anthropic routines API's request
  shape, and a hand-rolled call is exactly the non-reproducibility this
  change removes. `--harness claude` prints one JSON object
  (`name`, `cron`, `timezone`, `model`, `repo`, `merge_enabled`, `prompt`)
  plus a one-line handoff instruction naming the harness's own scheduling
  skill as the installer. The block is machine-parseable so a future direct
  API binding consumes it unchanged (Constitution Article 2 — nothing
  speculative built now).
- D2 — Merge authorization is a NEW structured record type, not a Czech
  free-text grep. The guard reads `docs/ai/decisions.jsonl` for a
  `type: routine_authorization` object with matching `ref`, `by: "human"`,
  and `"merge"` present in `grants[]`. The 2026-08-06 legacy record
  (`type: authorization`, free-text Czech answer) is NEVER parsed — prose
  heuristics are not an authorization mechanism. Implementation appends ONE
  canonical `routine_authorization` record for `aai-morning-scryer`
  transcribing that human answer, with `derived_from` naming the original
  timestamp and `question_ref`. The ledger is append-only: line 83 is not
  edited (Constitution Article 5).
- D3 — Byte-for-byte regenerability is proven against a checked-in golden
  fixture plus render idempotence plus a zero-unresolved-placeholder
  assertion, NOT against the live cloud trigger. Reading the live trigger
  config needs cloud auth no test has. Recorded as residual risk R1.
- D4 — The emitter is EMIT-ONLY: it writes nothing to crontab, launchd,
  Task Scheduler, or any API, and takes no network. All installation is text
  on stdout for the operator. This is what makes every AC testable offline.
- D5 — `/aai-routine` is invocation-only. Enforced by a grep-isolation pin
  over the automatic surfaces (bootstrap, sync, loop, orchestration prompts),
  mirroring `tests/skills/test-aai-advisory-skills.sh` TEST-012's pattern.
- D6 — The scryer contract text is reconstructed from CHANGE-0128 AC-001's
  enumeration of it (the live prompt text is not in the repo). The template
  is therefore the NEW source of truth; the live trigger is re-created from
  it as the operator's first act after merge, which is also the AC-01
  field-evidence step.

## Acceptance Criteria Mapping

- Maps to: CHANGE-0128 AC-001
- Spec-AC-01: `.aai/routines/SCRYER.routine.md` exists and carries, as
  greppable text, all six contract elements named in CHANGE-0128 AC-001 —
  step-0 prerequisite probes for `gh`, `git` and `node`; the resilience rule
  that a degraded digest is a SUCCESSFUL run; the three merge gates (CI
  green, top-level bot comments answered, never `[L3]`); a Czech digest
  shape; the UNTRUSTED-DATA rule for PR and issue comment text; and the rule
  that merge is the ONLY write action. It declares exactly the four
  placeholders `{{REPO}}`, `{{SCHEDULE}}`, `{{MERGE_ALLOWED}}`, `{{MODEL}}`
  in a `## Placeholders` block, and contains no `{{...}}` token outside that
  declared set.
  - Verification: `bash tests/skills/test-aai-routine.sh` TEST-001, TEST-002
    (six element pins, placeholder-set closure).
  - Verification (field, post-merge): the operator re-creates
    `trig_01XpMxioptoJ7j32YKzzaKnR` from the rendered output and records the
    new trigger id in `docs/ai/decisions.jsonl`. See residual risk R1.

- Maps to: CHANGE-0128 AC-001
- Spec-AC-02: `node .aai/scripts/routine-emit.mjs --routine SCRYER --harness
  claude --repo <slug> --schedule "<cron>" --model <id> --tz <zone>` renders
  the template with every placeholder substituted, and the rendered prompt is
  byte-identical to the checked-in golden
  `tests/fixtures/routines/scryer-claude-merge.golden.txt`. Rendering twice
  with identical arguments produces byte-identical output (idempotent), and
  the rendered text contains zero `{{` sequences. A missing required argument
  exits 2 with a named-flag message and writes nothing to stdout.
  - Verification: `bash tests/skills/test-aai-routine.sh` TEST-003 (golden
    diff, exit 0), TEST-004 (two renders byte-identical), TEST-005 (zero
    unresolved placeholders), TEST-006 (missing `--repo` exits 2, stdout
    empty).

- Maps to: CHANGE-0128 AC-002
- Spec-AC-03: the emitter supports `--harness claude codex gemini generic`
  and `--os macos linux windows`. `--harness claude` prints a single JSON
  object that `JSON.parse` accepts, whose `prompt` field equals the rendered
  contract and whose `cron`/`model`/`repo` fields equal the passed arguments.
  Every other harness prints a local-scheduler installation: for
  `--os macos` or `--os linux` a crontab line whose schedule field equals
  `--schedule` plus a POSIX `sh` runner invoking the named agent CLI headless
  against a prompt file; for `--os windows` a PowerShell `Register-ScheduledTask`
  twin of the same runner. Every non-claude emission prints BOTH twins'
  filenames (`<name>.sh` and `<name>.ps1`). An unknown `--harness` or `--os`
  value exits 2 and writes nothing to stdout.
  - Verification: `bash tests/skills/test-aai-routine.sh` TEST-007 (claude
    JSON parses, prompt equals render, fields echo arguments), TEST-008
    (codex plus gemini plus generic on macos and linux emit a crontab line
    carrying the schedule and a headless CLI invocation), TEST-009 (windows
    emits Register-ScheduledTask and the .ps1 twin name), TEST-010 (bad
    `--harness` and bad `--os` each exit 2 with empty stdout).

- Maps to: CHANGE-0128 AC-003
- Spec-AC-04: with `--merge`, the emitter reads `docs/ai/decisions.jsonl`
  (override path via `--decisions <file>`) and emits the merge-enabled
  contract ONLY when a JSON line satisfies all four of: `type` equals
  `routine_authorization`, `ref` equals the `--ref` value, `by` equals
  `human`, and `grants` contains `merge`. When no such line exists the
  emitter emits the report-only variant instead, prints the loud line
  `MERGE DISABLED — no routine_authorization record for ref=<ref> in
  <path>` to stderr, and exits 0. The report-only render contains the
  literal `merge-allowed: false` and contains no merge-gate section; the
  merge-enabled render contains `merge-allowed: true` and all three merge
  gates. A malformed or unreadable decisions file is treated as NO
  authorization (fail-closed), never as an error that skips the check.
  - Verification: `bash tests/skills/test-aai-routine.sh` TEST-011 (fixture
    WITH a matching record yields merge-allowed true plus three gates, exit
    0), TEST-012 (fixture WITHOUT one yields merge-allowed false, no gates,
    the loud stderr line, exit 0), TEST-013 (fixture with a near-miss record
    per field — wrong ref, `by` not human, `grants` lacking merge, wrong
    type — yields report-only on all four), TEST-014 (truncated and absent
    decisions file both fail closed to report-only, exit 0).

- Maps to: CHANGE-0128 AC-003
- Spec-AC-05: `docs/ai/decisions.jsonl` gains exactly one appended
  `routine_authorization` line for `ref` `aai-morning-scryer` carrying
  `by: "human"`, `grants: ["merge"]`, the three recorded constraints, and a
  `derived_from` value naming the 2026-08-06T09:16:00Z record and its
  `question_ref`. The pre-existing line 83 is byte-unchanged. Running the
  emitter against the REAL repository ledger with
  `--ref aai-morning-scryer --merge` yields the merge-enabled variant.
  - Verification: `bash tests/skills/test-aai-routine.sh` TEST-015 (live
    ledger scan finds exactly one matching record with all required fields
    and a non-empty derived_from), TEST-016 (`git diff` of the ledger across
    the scope shows append-only — the first 83 lines are unchanged),
    TEST-017 (live-ledger emit prints merge-allowed true, exit 0).

- Maps to: CHANGE-0128 AC-002
- Spec-AC-06: `.aai/SKILL_ROUTINE.prompt.md` exists as a thin wrapper around
  `routine-emit.mjs`, pins verbatim the sentence `This skill runs ON DEMAND
  only — never from bootstrap, sync, or any automatic path.`, and neither
  `.aai/BOOTSTRAP.prompt.md`, `.aai/SKILL_BOOTSTRAP.prompt.md`,
  `.aai/SKILL_UPDATE.prompt.md`, `.aai/SKILL_LOOP.prompt.md`,
  `.aai/ORCHESTRATION.prompt.md`, `.aai/scripts/aai-sync.sh` nor
  `.aai/scripts/aai-sync.ps1` contains the string `routine-emit` or
  `aai-routine`. Wrapper stubs exist under `.claude/skills/aai-routine/`,
  `.agents/skills/aai-routine/`, `.codex/skills/aai-routine/` and
  `.gemini/skills/aai-routine/`, each pointing at
  `.aai/SKILL_ROUTINE.prompt.md` and each carrying the absent-prompt
  fallback sentence, matching the `aai-issues` wrapper shape.
  - Verification: `bash tests/skills/test-aai-routine.sh` TEST-018 (verbatim
    on-demand pin), TEST-019 (seven automatic surfaces are clean of both
    strings), TEST-020 (four wrappers exist, name frontmatter matches
    `aai-routine`, each names the prompt path and the fallback sentence).

- Maps to: CHANGE-0128 AC-004
- Spec-AC-07: every emission — all four harnesses, both merge modes — ends
  with a `TEST AT CREATION` block naming one immediate test-fire command for
  that harness and the three things to verify: a digest was produced, the run
  did not crash, and any degraded sections are named in the digest. The block
  is absent from no emission.
  - Verification: `bash tests/skills/test-aai-routine.sh` TEST-021 (loop over
    the four harnesses times two merge modes asserts the `TEST AT CREATION`
    heading, a harness-appropriate fire command, and all three verify items
    in each of the eight outputs).

- Maps to: CHANGE-0128 AC-004 (governance clause)
- Spec-AC-08: the companion governance obligations are satisfied — the three
  new `.aai/**` files (`.aai/routines/SCRYER.routine.md`,
  `.aai/scripts/routine-emit.mjs`, `.aai/SKILL_ROUTINE.prompt.md`) each
  appear exactly once in `.aai/system/PROFILES.yaml`; the new prompt's byte
  growth carries one new itemized `JUSTIFIED_ADDITIONS` entry in
  `tests/skills/lib/prompt-diet-ledger.sh` and the `TEST-012` expected pin in
  `tests/skills/test-aai-prompt-diet.sh` equals the independent re-sum;
  `SKILLS.md` gains one `aai-routine` row; `tests/skills/suite-map.yaml`
  gains an `aai-routine` suite row listing the scope's globs.
  - Verification: `bash tests/skills/test-aai-layer-profiles.sh` (TEST-001
    union-equals-live-tree), `bash tests/skills/test-aai-prompt-diet.sh`
    (TEST-010 floor plus headroom cap, TEST-012 pin equals re-sum, TEST-013
    entry shape), `bash tests/skills/test-aai-hygiene-pack.sh` (suite-map row
    per suite file), `bash tests/skills/test-aai-routine.sh` TEST-022
    (SKILLS.md row present and points at the prompt).

## Constitution deviations

- Article 7 (Operator-only merge) — DEVIATION, justified. This change ships
  a routine template whose merge-enabled variant authorizes a scheduled agent
  to merge factory PRs. Justification: the project owner recorded an explicit,
  scoped authorization on 2026-08-06 (`docs/ai/decisions.jsonl` line 83) —
  merge permitted only with CI green and bot comments answered, and NEVER for
  `[L3]` scopes, which the routine reports and leaves to the operator. The
  owner-override path is itself an established precedent
  (`merge-authorization-owner-override`). The deviation is narrowed by
  Spec-AC-04: no merge-enabled prompt can be emitted without a
  machine-checked authorization record, and the default is report-only. The
  guard fails closed, so the deviation cannot widen by accident.
- Articles 1, 2, 3, 4, 5, 6 — no deviation. Note in particular Article 3
  (portability): moving the routine out of a cloud-only trigger config into a
  plain git-diffable template is this change's whole point, and Article 4
  (degrade and report): the report-only fallback and the loud `MERGE
  DISABLED` line are the required explicit report.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN the routine template is read THEN it carries all six named contract elements and exactly the four declared placeholders | done | test-aai-routine.sh TEST-001/002 PASS 2026-08-08 | — | field re-creation of the live trigger is residual risk R1 |
| Spec-AC-02 | WHEN the emitter renders SCRYER with full arguments THEN output matches the golden byte-for-byte, is idempotent, and holds no unresolved placeholder | done | test-aai-routine.sh TEST-003/004/005/006 PASS 2026-08-08 | — | — |
| Spec-AC-03 | WHEN a harness and OS are named THEN the emitter prints the matching installation payload, and exits 2 on an unknown value | done | test-aai-routine.sh TEST-007..010 PASS 2026-08-08 | — | claude payload is a JSON spec block per D1 |
| Spec-AC-04 | WHEN --merge is passed THEN a merge-enabled contract is emitted ONLY on a machine-checked routine_authorization record, else report-only with a loud stderr line | done | test-aai-routine.sh TEST-011..014 PASS 2026-08-08 | — | fail-closed on malformed ledger |
| Spec-AC-05 | The real decisions ledger gains one canonical routine_authorization record for aai-morning-scryer, appended, with provenance | done | test-aai-routine.sh TEST-015..017 PASS 2026-08-08 | — | line 85 stays byte-unchanged |
| Spec-AC-06 | The skill is on-demand only — verbatim pin present and no automatic surface references it — and four harness wrappers exist | done | test-aai-routine.sh TEST-018..020 PASS 2026-08-08 | — | mirrors the aai-issues wrapper shape |
| Spec-AC-07 | WHEN any emission is produced THEN it ends with a TEST AT CREATION block naming the fire command and three verifications | done | test-aai-routine.sh TEST-021 PASS 2026-08-08 | — | memory rule cloud-routine-test-at-creation |
| Spec-AC-08 | Governance companions are satisfied — PROFILES entries, diet-ledger entry plus TEST-012 re-sum, SKILLS.md row, suite-map row | done | test-aai-routine.sh TEST-022 + test-aai-layer-profiles.sh TEST-001 + test-aai-prompt-diet.sh TEST-010/012 + test-aai-hygiene-pack.sh PASS 2026-08-08 | — | closed two-entry companion check plus catalog wiring |

## Implementation plan

Components:
- `.aai/routines/SCRYER.routine.md` (NEW) — the agent-neutral contract with a
  `## Placeholders` declaration block and the routine body. Source of truth
  for the prompt text (D6).
- `.aai/scripts/routine-emit.mjs` (NEW) — zero-dep Node ESM, `node:` stdlib
  only, no network, emit-only (D4). Responsibilities: argument parsing with a
  closed flag set; template load and placeholder substitution; the
  authorization scan; per-harness payload assembly; the TEST AT CREATION
  block. Exit codes: 0 emitted (including the degraded report-only case), 2
  usage error with empty stdout.
- `.aai/SKILL_ROUTINE.prompt.md` (NEW) — thin wrapper in the
  `SKILL_ISSUES.prompt.md` shape: run the script, relay its output, obey the
  on-demand rule, walk the operator through the test-at-creation fire.
- Four wrapper stubs mirroring `.claude|.agents|.codex|.gemini/skills/aai-issues/`.
- `tests/fixtures/routines/` (NEW) — the golden render plus three decisions
  fixtures (authorized, unauthorized, near-miss records).
- Governance edits: `.aai/system/PROFILES.yaml` (three entries, `extended` —
  the emitter is an on-demand operator convenience, not the workflow engine,
  matching the classification rule's "session conveniences" bucket),
  `tests/skills/lib/prompt-diet-ledger.sh`, `tests/skills/test-aai-prompt-diet.sh`,
  `SKILLS.md`, `tests/skills/suite-map.yaml`.
- `docs/ai/decisions.jsonl` — one appended line (D2).

Data flows:
- arguments plus template file -> rendered prompt -> harness payload -> stdout.
- `docs/ai/decisions.jsonl` -> authorization predicate -> boolean that selects
  the merge-enabled or report-only branch of the template BEFORE rendering.

Edge cases:
- Decisions file absent, unreadable, truncated mid-line, or containing
  non-JSON lines -> fail closed to report-only, exit 0 (Spec-AC-04).
- A `routine_authorization` record for a DIFFERENT ref -> no authorization.
- `--merge` omitted -> report-only without the loud line (not a degradation,
  an explicit choice).
- Windows path: emitted text only; no attempt to detect or call `schtasks`.
- `--schedule` is passed through verbatim; the emitter does not validate cron
  syntax (out of scope, and a wrong schedule is caught by the
  test-at-creation fire).

## Seams

- S1 — routine template <-> emitter. Produced by the template author,
  consumed by the renderer. Crossed by TEST-003 and TEST-005: the golden diff
  and the zero-`{{` assertion run the REAL template through the REAL renderer,
  no mock.
- S2 — decisions ledger <-> merge guard. Written by the intake and HITL flows
  (and by this scope), read by the guard. Crossed on BOTH sides by TEST-015
  plus TEST-017: TEST-015 asserts the record this scope appends to the LIVE
  ledger has every field the guard requires, and TEST-017 runs the guard
  against that same live ledger. A fixture-only test here would test the
  fixture, which is exactly the seam bug this pair exists to prevent.
- S3 — new `.aai/**` files <-> the vendored-layer sync and profile machinery.
  Crossed by `test-aai-layer-profiles.sh` TEST-001, which enumerates the LIVE
  tree; an unclassified new file fails it.
- S4 — new suite file <-> CI suite selection. Crossed by
  `test-aai-hygiene-pack.sh`, which requires one `suites.<name>` row per
  `tests/skills/test-aai-*.sh` on disk.
- S5 — new prompt bytes <-> the prompt-diet floor. Crossed by
  `test-aai-prompt-diet.sh` TEST-010 (floor plus 2048 B headroom cap) and
  TEST-012 (pin equals independent re-sum). The headroom cap means the
  credit must be the MEASURED growth, not a rounded-up guess.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | unit | tests/skills/test-aai-routine.sh | template carries all six contract elements as greppable text | green |
| TEST-002 | Spec-AC-01 | unit | tests/skills/test-aai-routine.sh | placeholder set is exactly the four declared tokens, none undeclared | green |
| TEST-003 | Spec-AC-02 | int  | tests/skills/test-aai-routine.sh | render equals tests/fixtures/routines/scryer-claude-merge.golden.txt byte-for-byte | green |
| TEST-004 | Spec-AC-02 | int  | tests/skills/test-aai-routine.sh | two identical renders are byte-identical (idempotence) | green |
| TEST-005 | Spec-AC-02 | int  | tests/skills/test-aai-routine.sh | rendered output contains zero unresolved placeholder sequences | green |
| TEST-006 | Spec-AC-02 | unit | tests/skills/test-aai-routine.sh | missing required flag exits 2 and writes nothing to stdout | green |
| TEST-007 | Spec-AC-03 | int  | tests/skills/test-aai-routine.sh | claude payload parses as JSON, prompt equals render, fields echo arguments | green |
| TEST-008 | Spec-AC-03 | int  | tests/skills/test-aai-routine.sh | codex, gemini and generic on macos and linux emit a crontab line plus headless CLI runner | green |
| TEST-009 | Spec-AC-03 | int  | tests/skills/test-aai-routine.sh | windows emits Register-ScheduledTask and both twin filenames; the block parses as AST-clean PowerShell with pwsh Parser::ParseFile (exactly 3 top-level statements, zero errors) and New-ScheduledTaskAction / Register-ScheduledTask actually bind a non-empty -Argument / -Description via stubbed cmdlets, guarded with the pwsh-present skip convention | green |
| TEST-010 | Spec-AC-03 | unit | tests/skills/test-aai-routine.sh | unknown harness and unknown os each exit 2 with empty stdout | green |
| TEST-011 | Spec-AC-04 | int  | tests/skills/test-aai-routine.sh | authorized fixture yields merge-allowed true plus all three merge gates, exit 0 | green |
| TEST-012 | Spec-AC-04 | int  | tests/skills/test-aai-routine.sh | unauthorized fixture yields report-only, loud MERGE DISABLED stderr line, exit 0 | green |
| TEST-013 | Spec-AC-04 | int  | tests/skills/test-aai-routine.sh | four near-miss records (wrong ref, by not human, grants lacking merge, wrong type) each yield report-only | green |
| TEST-014 | Spec-AC-04 | int  | tests/skills/test-aai-routine.sh | absent and truncated decisions files fail closed to report-only, exit 0 | green |
| TEST-015 | Spec-AC-05 | int  | tests/skills/test-aai-routine.sh | live docs/ai/decisions.jsonl holds exactly one matching record with all required fields and non-empty derived_from | green |
| TEST-016 | Spec-AC-05 | int  | tests/skills/test-aai-routine.sh | ledger change is append-only across the scope, first 85 lines byte-unchanged | green |
| TEST-017 | Spec-AC-05 | e2e  | tests/skills/test-aai-routine.sh | emit against the live ledger with ref aai-morning-scryer and merge prints merge-allowed true, exit 0 | green |
| TEST-018 | Spec-AC-06 | unit | tests/skills/test-aai-routine.sh | skill prompt pins the on-demand sentence verbatim | green |
| TEST-019 | Spec-AC-06 | unit | tests/skills/test-aai-routine.sh | seven automatic surfaces contain neither routine-emit nor aai-routine | green |
| TEST-020 | Spec-AC-06 | unit | tests/skills/test-aai-routine.sh | four wrappers exist with matching name frontmatter, prompt path and fallback sentence | green |
| TEST-021 | Spec-AC-07 | int  | tests/skills/test-aai-routine.sh | all eight harness times merge-mode emissions carry the TEST AT CREATION block with fire command and three verifications | green |
| TEST-022 | Spec-AC-08 | unit | tests/skills/test-aai-routine.sh | SKILLS.md carries one aai-routine row naming the prompt path | green |
| TEST-023 | Spec-AC-08 | int  | tests/skills/test-aai-layer-profiles.sh | TEST-001 union equals the live .aai tree with the three new files classified | green |
| TEST-024 | Spec-AC-08 | int  | tests/skills/test-aai-prompt-diet.sh | TEST-010 floor plus headroom cap and TEST-012 pin equals independent re-sum after the new ledger entry | green |
| TEST-025 | Spec-AC-08 | int  | tests/skills/test-aai-hygiene-pack.sh | every tests/skills/test-aai-*.sh has exactly one suite-map row, including the new suite | green |

RED discipline (strategy hybrid): TEST-011 through TEST-014 (the merge guard)
and TEST-003 plus TEST-005 (the renderer) are the AC-gating tests and MUST be
observed FAILING before their implementation exists; store each RED transcript
under `docs/ai/tdd/` per the tdd/hybrid evidence row. The remaining rows are
loop-covered: green runs suffice, RED observation is expected but storage is
optional.

## Verification

Commands:
- `bash tests/skills/test-aai-routine.sh`
- `bash tests/skills/test-aai-layer-profiles.sh`
- `bash tests/skills/test-aai-prompt-diet.sh`
- `bash tests/skills/test-aai-hygiene-pack.sh`
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0115-spec-universal-routines.md`
- `node .aai/scripts/docs-audit.mjs --check --strict`

Evidence artifacts: suite stdout with per-TEST pass lines, the RED transcripts
under `docs/ai/tdd/`, the golden fixture, and the scoped diff.

PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.

## Evidence contract

Per artifact record: ref_id, Spec-AC and TEST-xxx links, command or review
scope, exit code or review verdict, evidence path, commit SHA or diff range.

### Evidence by strategy

Strategy is `hybrid`: stored RED artifacts are demanded for the AC-gating
tests named under RED discipline above, plus the full verification matrix.

## Residual risks

- R1 — Byte-for-byte equality between the rendered contract and the LIVE
  cloud trigger's prompt cannot be asserted by any automated test: reading
  `trig_01XpMxioptoJ7j32YKzzaKnR` needs cloud credentials the suite does not
  have, and D6 records that the live prompt text is not in the repo at all.
  Mitigation: the template becomes the source of truth and the operator
  re-creates the trigger from the rendered output, recording the new trigger
  id in `docs/ai/decisions.jsonl`. Accepted, not tested.
- R2 — The emitted local-scheduler payloads are text; whether a crontab line
  or a `Register-ScheduledTask` call actually installs and fires on a real
  macOS, Linux or Windows box is not exercised here (D4 makes the emitter
  side-effect-free on purpose). Mitigation: the Spec-AC-07 test-at-creation
  block forces a manual first fire at install time, which is precisely where
  that failure would surface. Accepted.
- R3 — Codex and Gemini headless CLI invocation syntax is taken from the
  existing wrapper conventions in `SKILLS.md`, not from a live run of those
  CLIs (neither is installed here). A syntax drift would produce a
  non-firing cron job, again caught by the test-at-creation fire. Accepted.

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
