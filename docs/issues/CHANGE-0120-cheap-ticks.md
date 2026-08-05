---
id: cheap-ticks
number: 120
type: change
status: done
user_visible: true
ceremony_level: 2
links:
  pr:
    - 229
  commits:
    - 84ded3a4f24f45e7b5e6b00e62fd18135233eb5e
---

# Change — mechanical ticks stop respawning agents: confirm-by-script, scope edits by orchestrator, atomic freeze

## Summary
- Live cost forensics (InfluxDriver log): of ~11 agent runs for a one-line
  fix, at least 4 were process-self-repair that needed NO model judgment:
  (a) tick 1 respawned a FULL Implementation agent only to re-confirm an
  unchanged green state after a re-plan; (b) excluding the user's unrelated
  requirements.txt/.gitattributes changes from review scope ran a FULL
  re-Planning agent — a mechanical list edit; (c) Planning wrote
  `SPEC-FROZEN: true` while frontmatter stayed `status: draft` — the
  dispatcher bounced the scope back to Planning to fix its own paperwork.
- Three deterministic fixes:
  1. CONFIRM-BY-SCRIPT: when a re-plan changes no AC/TEST mapping for
     already-green items (computable diff of the spec's AC table + test
     list), the dispatcher marks the phase confirmed via a script check —
     no agent dispatch. Any real delta still dispatches normally.
  2. SCOPE EDITS AS STATE MUTATIONS: review-scope include/exclude of
     files UNTOUCHED by the ride (user side-changes) becomes an
     orchestrator-level spec edit via a small tool (audited, EVENTS line),
     not a Planning dispatch. Content changes to AC/tests still go to
     Planning.
  3. ATOMIC FREEZE: one tool writes status+marker together
     (spec-freeze.mjs or a state.mjs-adjacent script — NOT protected
     surfaces); spec-lint flags the half-frozen state at WRITE time so the
     mismatch cannot survive to dispatch.
- Expected effect (from the log's shape): ~3-4 agent runs saved on small
  rides = the difference between "small fix" and "3-5 % of a weekly limit".

## Acceptance Criteria
- AC-001: no-delta re-plan -> dispatcher confirms via script, EVENTS line
  recorded, zero agent dispatch (fixture); any AC/test delta -> normal
  dispatch (control).
  DELIVERED — rule 9x in `.aai/scripts/orchestration-dispatch.mjs`, evaluated
  immediately before 9a/9b/9c and confined to those phases. Confirms only when
  the AC table is fully green AND the spec content hash matches the last
  recorded `phase_confirmed` event (or, with no prior confirmation, an
  implementer agent_run exists). `--confirm` records the event via
  append-event.mjs, idempotently. RED-proven in docs/ai/tdd/CHANGE-0120-red.md;
  TEST-035 (pure arms incl. delta, missing-prior-green, not-green, legacy
  fail-closed, phase confinement, purity), TEST-036 (CLI exit 3, zero dispatch,
  exactly one event, idempotent re-tick, default read-only, STATE/spec
  untouched), TEST-037 (prose-only re-plan confirms; a real AC delta dispatches
  9a and records nothing) in tests/skills/test-aai-orchestration-dispatch.sh.
- AC-002: scope-exclusion tool edits the spec's review-scope list only for
  paths with no ride-diff, refuses otherwise; audited.
  DELIVERED — `.aai/scripts/spec-scope-edit.mjs`; refuses (exit 3) any path in
  the ride diff (committed, staged, unstaged or untracked), refuses (exit 4) on
  a missing review-scope bullet, an unreadable spec, or a failed git probe;
  appends a `spec_scope_edited` audit line; idempotent down to the ledger.
  TEST-001..005(scope) in tests/skills/test-aai-spec-tools.sh.
- AC-003: half-frozen spec (marker without status) is a spec-lint finding;
  the freeze tool cannot produce it.
  DELIVERED — the `half-frozen` rule in `.aai/scripts/spec-lint.mjs` (marker
  with a pre-implementation status, or `implementing` with no marker) and
  `.aai/scripts/spec-freeze.mjs`, which writes both halves in one
  write+rename or refuses (exit 3). TEST-001..004(halffrozen) in
  tests/skills/test-aai-spec-lint.sh (incl. negative controls and a real-corpus
  arm) and TEST-006..008(freeze) in tests/skills/test-aai-spec-tools.sh (incl.
  the half-frozen finding -> clean repair round-trip).

## Verification
- `bash tests/skills/test-aai-orchestration-dispatch.sh` (TEST-035..037 added;
  RED first — log in docs/ai/tdd/CHANGE-0120-red.md).
- `bash tests/skills/test-aai-spec-tools.sh` (new suite, TEST-001..008).
- `bash tests/skills/test-aai-spec-lint.sh` (TEST-001..004(halffrozen) added;
  the CHANGE-0122 stratev arms stay green and TEST-008(stratev)'s vacuous
  `$SPEC_LINT` assertion now genuinely runs).
- `bash tests/skills/test-aai-prompt-diet.sh` (TEST-010 headroom 1150/2048,
  TEST-012 pin -11352 -> -10463 for the +889 B wiring entry).
- `bash tests/skills/test-aai-state.sh`, `test-aai-hygiene-pack.sh`,
  `test-aai-layer-profiles.sh`, `test-aai-ceremony-levels.sh`,
  `test-aai-release.sh`, `test-aai-docs-audit.sh`, `test-aai-verify-gate.sh`,
  `test-aai-suite-select.sh`, `test-aai-doc-numbering.sh`.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` — CLEAN.

## Constraints / Risks
- Ceremony L2 — touches orchestration-dispatch.mjs (core) + spec-lint +
  a new small tool + prompts (ledger). The riskiest of the three intakes;
  ride with full validation.
- Honesty: confirm-by-script must compare against the FROZEN spec content,
  not trust the re-plan's self-report.
- CORPUS SHAPES (found by independent validation, now FIXED): the two
  deterministic editors were written against the SPEC_TEMPLATE shape and met a
  corpus that does not match it. `spec-freeze` corrupted every spec with NO `# `
  H1 (SPEC-0100/0101/0102 and all doc-generator specs) — the marker was spliced
  INSIDE the frontmatter at a stale offset and truncated adjacent content, at
  exit 0. `spec-scope-edit` read only the flat comma list, so the 30 nested and
  24 backticked corpus specs (54 of 114) parsed as EMPTY: `--exclude` reported
  "already out of scope" without editing or auditing, and `--include` wrote onto
  the label line. Both are fixed and covered (spec-tools TEST-009/010/011); the
  freeze now re-parses its own OUTPUT before writing and refuses (exit 1,
  nothing written) if it cannot prove the result is correctly frozen, and the
  scope editor refuses (exit 4) any scope bullet it cannot parse rather than
  reporting a no-op success.
- PATH SPELLING (found by independent validation, now FIXED): the scope
  editor's diff refusal compared raw strings, so `./committed.js`,
  `src/../committed.js`, `.//committed.js` and an absolute in-repo path all
  bypassed the gate — `--include` would launder a ride-touched path into the
  review scope at exit 0. Target and diff entries are now compared through one
  normalized repo-relative key (symlinked repo prefixes included).

## Residual risks (as delivered)

- BOOTSTRAP TICK: the first confirmation for a ref has no recorded hash to
  compare against, so it rests on (a) a fully green AC table — every row
  `done` WITH evidence — and (b) a recorded implementer agent_run. A re-plan
  that re-mapped a green AC's tests while leaving the row `done` with its old
  evidence would be confirmed on that one tick. Every LATER tick is fully
  hash-guarded. Narrowing this further needs a historical spec snapshot,
  which only git could supply and not deterministically inside a worktree.
- ADVISORY ASYMMETRY: dispatch rule 6 still ACCEPTS a frozen spec whose
  frontmatter status is `draft`, while the new spec-lint `half-frozen` rule
  reports it. That is deliberate — spec-lint is report-only and nudges Planning
  toward the canonical state; rule 6 stays back-compatible with the
  draft+frozen specs already in the wild. Tightening rule 6 is a separate,
  gate-changing scope.
- SCOPE-EDIT REACH: the diff probe is path-based. A path excluded from review
  scope while UNTOUCHED can still be touched later in the same ride; nothing
  re-checks the exclusion at close time. The compensating control is that the
  `spec_scope_edited` audit line records the op, target and base ref, so a
  reviewer can replay the decision against the final diff.
- CONFIRM WRITE MODE: `--confirm` is opt-in and only `.aai/ORCHESTRATION.prompt.md`
  passes it today. An orchestrator that omits it still gets the zero-dispatch
  saving, but records no snapshot — so every tick re-derives from the bootstrap
  evidence rather than the stronger hash comparison. When `--confirm` IS passed
  and the recording FAILS, the tick now falls back to a real dispatch with a
  stderr note (an unrecorded confirmation is invisible to the next tick and
  would otherwise repeat forever) — dispatch TEST-038.
- ANNOTATION FIDELITY (scope editor): a nested child bullet that names SEVERAL
  comma-separated paths under one shared trailing `(note)` is rewritten as one
  child per path, so the shared note stays with the LAST path only. No path is
  ever lost (verified across all 114 corpus specs), and this only happens on an
  actual edit — but the prose of such a shared annotation can degrade.

## Post-validation disclosures (re-validation round)
- R1 (FIXED): git's default core.quotePath C-quoted non-ASCII paths, letting a
  ride-touched file slip past the scope-edit refusal; all four git probes now
  run with -c core.quotePath=false (TEST-012 scope, non-ASCII fixture).
- R3 (FIXED): the confirm hash now covers each test's Type and File-path
  columns — a re-plan retargeting a test dispatches (TEST-037c). Test STATUS
  remains excluded by design.
- R2 (DISCLOSED, not fixed): 9 legacy specs carry prose/space-separated scope
  bullets that parse as one blob; --exclude there reports a no-op success
  instead of refusing (the exit-4 refusal fires only on zero parsable items).
  Legacy prose shapes; fixing means guessing intent — out of scope.
- R4 (DISCLOSED, latent, zero corpus reach): a spec with no real H1 whose
  first `# ` line sits inside a fenced code block would receive the freeze
  marker inside the fence; no such spec exists (verified across 114).
- Review round (3 BLOCKING fixed): decorated scope entries (`path` (new))
  now key correctly — iterative strip until stable (TEST-013); the R1
  regression pin test_012 is registered and RUNS; ORCHESTRATION rule-9x
  exception uses the flag form of set-phase (+14 B credited).
- Review NON-BLOCKING dispositions: test-STATUS exclusion from the confirm
  hash survives beyond the bootstrap tick (a re-plan flipping green->pending
  with a stale-done AC confirms) — accepted trade-off, follow-up candidate;
  valueless `SPEC-FROZEN:` line exits 1 not 3 (zero corpus reach, noted);
  --include of an out-of-repo ../path is accepted (advisory scope, follow-up
  candidate).
