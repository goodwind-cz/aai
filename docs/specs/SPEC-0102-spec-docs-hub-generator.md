---
id: spec-docs-hub-generator
type: spec
number: 102
status: implementing
ceremony_level: 2
links:
  requirement: CHANGE-0078
  rfc: null
  pr: []
  commits: []
---

## Links
- Requirement: docs/issues/CHANGE-0078-docs-hub-generator.md
- Decision records: none
- Technology contract: docs/TECHNOLOGY.md

## Summary
docs/SKILL_CATALOG.html (last hand-regenerated 2026-07-07) was 27/35 skills
stale, and the only mechanism to refresh it, `.aai/SKILL_DOCS_HUB.prompt.md`,
required an LLM to hand-scan every `.claude/skills/*/SKILL.md` and matching
`.aai/SKILL_*.prompt.md` (a ~70-file fan-out) and hand-author the HTML from
scratch on each run — exactly the class of drift `generate-overview.mjs`
already solved for the stakeholder overview page. This change adds
`.aai/scripts/generate-docs-hub.mjs` (mirroring `generate-overview.mjs`'s
shape: zero-dep, deterministic, byte-idempotent HTML+JSON emit), rewrites
`SKILL_DOCS_HUB.prompt.md` into a thin script-first wrapper, wires a
best-effort regen into the close ceremony, and regenerates the catalog with
the new generator as part of this change (fixing the staleness the change
exists to close).

## Implementation strategy
- Strategy: tdd
- Rationale: the deliverable is a new deterministic generator with concrete
  observable acceptance criteria (count pin, degrade-with-NOTE behavior,
  byte-idempotence) each provable by a fixture-driven RED-GREEN test, plus a
  prompt-corpus byte-budget change gated by the existing ledger suite
  (`tests/skills/test-aai-prompt-diet.sh` TEST-010/012). RED-first evidence
  proves both the new suite and the ledger pin actually bite before the
  fix, and pass after.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: small, clearly scoped script + prompt-rewrite + one
  wiring line in close-work-item.mjs; no protected L3 surface (state engine,
  allocator, guards, workflow canon — see `protected_paths_l3` in
  docs/ai/docs-audit.yaml, which does not name close-work-item.mjs) is
  touched; already on a dedicated feature branch
  (feat/docs-hub-generator).
- User decision: waived
- Base ref: main
- Worktree branch/path: feat/docs-hub-generator (current checkout)
- Inline review scope: .aai/scripts/generate-docs-hub.mjs,
  .aai/SKILL_DOCS_HUB.prompt.md, .aai/scripts/close-work-item.mjs,
  .aai/system/PROFILES.yaml, tests/skills/suite-map.yaml,
  tests/skills/test-aai-docs-hub.sh, tests/skills/lib/prompt-diet-ledger.sh,
  tests/skills/test-aai-prompt-diet.sh, docs/SKILL_CATALOG.html,
  docs/skill-catalog-data.json,
  docs/specs/SPEC-0102-spec-docs-hub-generator.md

## Acceptance Criteria Mapping
- Maps to: CHANGE-0078 AC-001
- Spec-AC-01: `.aai/scripts/generate-docs-hub.mjs` mechanically extracts
  name/description/model from each `.claude/skills/*/SKILL.md` frontmatter
  block and the `## Goal` section from the `.aai/SKILL_*.prompt.md` its
  SKILL.md body references, emitting a searchable, self-contained
  `docs/SKILL_CATALOG.html` (+ `docs/skill-catalog-data.json`); the reported
  skill count always equals the live `.claude/skills/` directory listing
  (never cached or hardcoded), and any extraction that comes up short (no
  prompt reference, no `## Goal` section, missing frontmatter field)
  produces a visible NOTE on that skill's card and in its JSON `notes`
  array — never a silent omission.
  - Verification: `bash tests/skills/test-aai-docs-hub.sh` TEST-001/002/003/005/007;
    manual `node .aai/scripts/generate-docs-hub.mjs` against the live repo,
    confirming the footer's `<N> skills` equals `ls .claude/skills | wc -l`.
- Maps to: CHANGE-0078 AC-002 (idempotence half)
- Spec-AC-02: the rendered HTML is byte-idempotent across repeated runs over
  unchanged inputs (stable skill ordering, fixed JSON key order, no
  timestamp in the HTML body); `docs/skill-catalog-data.json` carries
  `generatedAt` as the only run-varying field, exactly like
  `overview-data.json` does for `generate-overview.mjs`.
  - Verification: `bash tests/skills/test-aai-docs-hub.sh` TEST-004/006; live
    two-run `diff` of `docs/SKILL_CATALOG.html`.
- Maps to: CHANGE-0078 AC-002 (close-ceremony regen half)
- Spec-AC-03: `close-work-item.mjs` regenerates the skills catalog
  best-effort as the STRICTLY LAST step of a successful close (immediately
  after `regenerateUserguideRollupBestEffort()`), mirroring the existing
  `regenerateOverviewBestEffort()` / `regenerateUserguideRollupBestEffort()`
  pattern verbatim: `fs.existsSync` guard, every failure swallowed to an
  INFO stderr line, never reaches `rollback()`, never changes the close
  exit code.
  - Verification: `bash tests/skills/test-aai-close-work-item.sh` (full
    regression — no new negative-control test added in this scope, the
    existing suite's TEST-008/009-shaped pattern for the sibling generators
    already proves the shared best-effort call site is safe); manual read
    of `close-work-item.mjs`'s tail confirming the literal call-site
    ordering.
- Maps to: CHANGE-0078 AC-003
- Spec-AC-04: `.aai/system/PROFILES.yaml` classifies
  `.aai/scripts/generate-docs-hub.mjs` under `extended` (alongside its
  siblings `generate-dashboard.mjs`/`generate-overview.mjs`);
  `tests/skills/suite-map.yaml` carries an `aai-docs-hub` row (satisfying
  the hygiene pin in `test-aai-hygiene-pack.sh` automatically); the
  `SKILL_DOCS_HUB.prompt.md` rewrite is a corpus REDUCTION, so
  `tests/skills/lib/prompt-diet-ledger.sh` carries a NEGATIVE RECLAIMED
  ledger entry (-6099 B) landing `JUSTIFIED_GROWTH_BYTES` at exactly -13353
  and headroom back at exactly 636/2048 (the steady-state the corpus was at
  before this scope); `test-aai-prompt-diet.sh` TEST-012's pinned literal is
  bumped RED-first with paired RED/GREEN evidence under docs/ai/tdd/.
  - Verification: `bash tests/skills/test-aai-layer-profiles.sh` TEST-001
    (100% classification against the live tree); `bash
    tests/skills/test-aai-hygiene-pack.sh` (suite-map row pin);
    `bash tests/skills/test-aai-prompt-diet.sh` TEST-010 (byte floor +
    headroom cap) and TEST-012 (ledger sum); RED/GREEN logs under
    docs/ai/tdd/.
- Maps to: CHANGE-0078 Summary (stale catalog is the bug being fixed)
- Spec-AC-05: `.aai/SKILL_DOCS_HUB.prompt.md` is rewritten to a ~50-80 line
  script-first thin wrapper (SKILL_DOCTOR.prompt.md shape): it runs the
  generator and relays its summary verbatim, names the mechanical
  extraction contract (frontmatter is "when to use", prompt `## Goal` is
  "Goal"), and offers categorization commentary as an OPTIONAL LLM add-on
  only when explicitly asked — never as part of the deterministic output;
  `docs/SKILL_CATALOG.html` + `docs/skill-catalog-data.json` are
  regenerated with the new generator as part of this change, landing at the
  live 34/34 skill count (was 27/35 stale).
  - Verification: `wc -l -c .aai/SKILL_DOCS_HUB.prompt.md`; manual read
    confirming the LLM-categorization language is present and scoped
    "only if asked"; `node .aai/scripts/generate-docs-hub.mjs` live run
    against the repo, `grep -c 'skill-card' docs/SKILL_CATALOG.html`
    (== 34).

## Constitution deviations

None.

## Acceptance Criteria Status

Tracks per-Spec-AC delivery state. Separate from per-test lifecycle below.

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | Mechanical extraction, count pin, degrade-with-NOTE | done | docs/ai/tdd/green-20260728T014751Z-docs-hub-generator-suite.log | — | 34/34 live skills, 19 with extraction notes |
| Spec-AC-02 | Byte-idempotent HTML, generatedAt JSON-only | done | docs/ai/tdd/green-20260728T014751Z-docs-hub-generator-suite.log | — | TEST-004 two-run diff clean |
| Spec-AC-03 | close-work-item.mjs best-effort regen wiring | done | tests/skills/test-aai-close-work-item.sh full run (local, not logged to docs/ai/tdd) | — | literal last-statement pattern mirrored verbatim |
| Spec-AC-04 | PROFILES + suite-map + ledger true-up, TEST-012 RED-first | done | docs/ai/tdd/red-20260728T014447Z-docs-hub-generator.log and docs/ai/tdd/green-20260728T014526Z-docs-hub-generator.log | — | -6099 B NEGATIVE entry, JUSTIFIED_GROWTH_BYTES -7254 to -13353, headroom 636/2048 |
| Spec-AC-05 | SKILL_DOCS_HUB.prompt.md thin wrapper, catalog regenerated | done | docs/ai/tdd/green-20260728T014751Z-docs-hub-generator-suite.log | — | 9513 B/328 lines to 3409 B/63 lines; catalog 27/35 to 34/34 |

## Implementation plan
- `.aai/scripts/generate-docs-hub.mjs` (new): argument parsing
  (`--output`/`--data-only`, mirroring `generate-overview.mjs`), frontmatter
  reader (same regex-line-read house style as `readFrontmatter()`), prompt-
  reference finder (regex scan of the SKILL.md body for a literal
  `.aai/SKILL_*.prompt.md` path — mechanical, not name-transform-derived,
  since the real corpus has exactly one skill, `aai-overview`, with no such
  reference at all), `## Goal` section extractor, HTML+JSON renderers.
- `.aai/SKILL_DOCS_HUB.prompt.md` (rewrite): Goal/Usage/Instructions/What-
  the-catalog-contains/Advanced-LLM-add-on/Troubleshooting, naming the real
  script and never re-deriving its extraction logic in prose.
- `.aai/scripts/close-work-item.mjs`: new `GENERATE_DOCS_HUB` constant + new
  `regenerateDocsHubBestEffort()` function (copy of
  `regenerateUserguideRollupBestEffort()`'s shape verbatim), called as the
  new final statement of `main()` after `regenerateUserguideRollupBestEffort()`.
- `.aai/system/PROFILES.yaml`: one new `extended` line,
  `.aai/scripts/generate-docs-hub.mjs`, alphabetically between
  `generate-dashboard.mjs` and `generate-overview.mjs`.
- `tests/skills/suite-map.yaml`: one new `aai-docs-hub` row (globs: the
  prompt, the script, and the two generated output paths).
- `tests/skills/lib/prompt-diet-ledger.sh`: one new NEGATIVE
  `JUSTIFIED_ADDITIONS` entry (-6099 B) reclaiming exactly the measured
  corpus shrinkage so headroom lands back at 636/2048, mirroring the
  dashboard-refit/doctor-determinize precedent.
- `tests/skills/test-aai-prompt-diet.sh`: TEST-012 pinned literal bumped
  -7254 -> -13353 (comment block + assertion + log_pass message updated
  together, per LEARNED.md 2026-07-17 true-up discipline).
- `tests/skills/test-aai-docs-hub.sh` (new): RED-first product suite,
  mktemp fixtures, TEST-001..007 per the Acceptance Criteria Mapping above.
- `docs/SKILL_CATALOG.html` + `docs/skill-catalog-data.json` (regenerated):
  live output of the new generator against the repo's real
  `.claude/skills/` tree, replacing the stale hand-authored 2026-07-07
  catalog.

## Edge cases
- A skill directory with an unreadable or missing `SKILL.md`: the card still
  renders (name falls back to the directory name) with a NOTE naming the
  read failure — never a crash, never a dropped card (TEST-001 fixture
  shape covers the present-and-parseable path; the read-failure NOTE branch
  is exercised by code review of `buildSkill()`'s try/catch, not a separate
  fixture, since simulating an unreadable-but-listed directory entry
  portably across the bash 3.2 / GNU-vs-BSD matrix is not worth the
  fixture complexity for a defensive branch with no live corpus instance).
- A skill whose SKILL.md references a `.aai/SKILL_*.prompt.md` path that
  does not exist on disk (a broken/renamed reference): NOTE names the
  missing file explicitly; `goal` stays null. No live corpus instance
  today (all 33 non-script-first skills' references resolve), covered by
  code review of the `fs.readFileSync` try/catch in `buildSkill()`.
- `.claude/skills/` absent entirely (a non-Claude-Code checkout, or run from
  the wrong directory): `discoverSkillDirs()` catches the `readdirSync`
  failure and returns `[]` — a clean 0-skill catalog, exit 0, never a crash
  (TEST-007).
- The prompt-diet ledger literal going more negative (-7254 -> -13353): this
  is TEST-013's already-generalized leading-field regex accepting a `-`
  sign, no test change needed; it reflects that the corpus has shrunk
  further below any owed positive credit, not an error state.

## Test Plan
For each Spec-AC, enumerate concrete tests:

| Test ID | Spec-AC | Type | File path (expected) | Description | Status |
|---|---|---|---|---|---|
| TEST-001 | Spec-AC-01 | unit | tests/skills/test-aai-docs-hub.sh | Every fixture skill present; reported count equals live .claude/skills listing | green |
| TEST-002 | Spec-AC-01 | unit | tests/skills/test-aai-docs-hub.sh | Missing "## Goal" section degrades with a visible NOTE in JSON and HTML | green |
| TEST-003 | Spec-AC-01 | unit | tests/skills/test-aai-docs-hub.sh | No .aai/SKILL_*.prompt.md reference degrades with its own distinct NOTE | green |
| TEST-004 | Spec-AC-02 | unit | tests/skills/test-aai-docs-hub.sh | HTML byte-identical across two runs; JSON generatedAt varies, never embedded in HTML | green |
| TEST-005 | Spec-AC-01 | unit | tests/skills/test-aai-docs-hub.sh | Regeneration after new skill dirs appear always reflects the live count, names every skill | green |
| TEST-006 | Spec-AC-01,Spec-AC-02 | unit | tests/skills/test-aai-docs-hub.sh | docs/skill-catalog-data.json top-level and per-skill key shape | green |
| TEST-007 | Spec-AC-01 | unit | tests/skills/test-aai-docs-hub.sh | Absent .claude/skills/ degrades to a 0-skill catalog, exit 0 | green |
| TEST-008 | Spec-AC-03 | e2e | tests/skills/test-aai-close-work-item.sh | Full existing suite stays green with the new best-effort call wired in | green |
| TEST-009 | Spec-AC-04 | unit | tests/skills/test-aai-prompt-diet.sh | TEST-012 JUSTIFIED_GROWTH_BYTES == -13353 == independent re-sum, RED-first | green |
| TEST-010 | Spec-AC-04 | unit | tests/skills/test-aai-prompt-diet.sh | TEST-010 byte floor + headroom cap (636/2048) after the ledger true-up | green |
| TEST-011 | Spec-AC-04 | unit | tests/skills/test-aai-layer-profiles.sh | 100% .aai classification against the live tree, including the new script | green |
| TEST-012 | Spec-AC-04 | unit | tests/skills/test-aai-hygiene-pack.sh | Every test-aai-*.sh has a suite-map.yaml row (aai-docs-hub auto-satisfied) | green |
| TEST-013 | Spec-AC-05 | e2e | manual smoke | node generate-docs-hub.mjs against the live repo: 34 skill-card divs, footer "34 skills" | green |

Notes:
- Every Spec-AC has at least one TEST-xxx entry.
- Test IDs are stable — do not renumber after freeze.
- TEST-001..007 are the new RED-first product suite; TEST-008..012 are
  pre-existing companion suites this change must not regress; TEST-013 is a
  live manual smoke, not a scripted assertion.

## Verification
- `bash tests/skills/test-aai-docs-hub.sh`
- `bash tests/skills/test-aai-prompt-diet.sh`
- `bash tests/skills/test-aai-verify-gate.sh`
- `bash tests/skills/test-aai-hygiene-pack.sh`
- `bash tests/skills/test-aai-suite-select.sh`
- `bash tests/skills/test-aai-layer-profiles.sh`
- `bash tests/skills/test-aai-close-work-item.sh`
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0102-spec-docs-hub-generator.md`
- `node .aai/scripts/docs-audit.mjs --gate spec-docs-hub-generator --no-event`
- `node .aai/scripts/generate-docs-hub.mjs` (live, twice, diff docs/SKILL_CATALOG.html for idempotence)
- Evidence artifacts: docs/ai/tdd/red-20260728T014447Z-docs-hub-generator.log,
  docs/ai/tdd/green-20260728T014526Z-docs-hub-generator.log,
  docs/ai/tdd/red-20260728T014748Z-docs-hub-generator-suite.log,
  docs/ai/tdd/green-20260728T014751Z-docs-hub-generator-suite.log
- PASS criteria: all TEST-xxx in status green AND all Spec-AC in a terminal
  status.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: spec-docs-hub-generator
- Spec-AC and TEST-xxx links: see Test Plan table above
- command or review scope: bash tests/skills/test-aai-docs-hub.sh
- exit code or review verdict: 0 (suite green as of this freeze)
- evidence path: docs/ai/tdd/ logs listed under Verification
- commit SHA or diff range: uncommitted on feat/docs-hub-generator at freeze
  time; see `git log` on this branch for the landing commit

## Notes
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
