---
id: spec-layer-profiles
type: spec
number: 35
status: implementing
ceremony_level: 2
links:
  requirement: layer-profiles
  research: RES-0001
  pr: []
  commits: []
---

# SPEC — Core/Extended Profiles for the Vendored Layer (aai-sync)

SPEC-FROZEN: true

## Links
- Change: layer-profiles (docs/issues/CHANGE-0023-layer-profiles.md)
- Research: RES-0001 P3 recommendation 13 — "profiles for the vendored layer:
  core/extended prompt sets in aai-sync; stop installing all ~40 prompts
  everywhere" (OpenSpec pattern: core = the workflow engine)
  (docs/specs/RES-0001-aai-competitive-gap-and-model-efficiency.md)
- Pin contract: .aai/system/AAI_PIN.md (spec-doctor-vendored-layer-drift D1/D2)
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (SPEC-FROZEN: true)
- implementing: work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Ceremony level
`ceremony_level: 2` (full pipeline). The scope is M and touches the
distribution scripts (.aai/scripts/aai-sync.sh/.ps1) — behavior-bearing
infrastructure consumed by every downstream project, so nothing lighter than
L2 is defensible. It does NOT touch any surface currently listed in
`protected_paths_l3` (docs/ai/docs-audit.yaml): the state engine, allocator,
guards, and workflow canon are untouched, so L3 is not mandatory.

NOTE for the operator (decision deliberately NOT taken here): should
`.aai/scripts/aai-sync.sh` / `.aai/scripts/aai-sync.ps1` (and
`aai-update.sh/.ps1`) be ADDED to `protected_paths_l3`? Argument for: they are
the distribution channel — a defect replicates into every target project on
the next /aai-update, which is blast-radius comparable to the state engine.
Argument against: they are recoverable by re-running a fixed sync (no data
destroyed), unlike state/allocator corruption. This spec proceeds at L2 with
L3-like practice (worktree isolation, full validation); the list change is a
one-line project-owned config edit if the operator ratifies it.

## Constitution deviations

None.

Article walk (docs/CONSTITUTION.md v1):
1. Evidence before claims — honored: TDD RED logs + suite/audit/idempotence
   evidence recorded before any claim (see Verification).
2. Simplicity — honored: one flat YAML manifest, two path lists; no
   per-file cherry-picking (explicitly out of scope in the intake).
3. Portability — honored: PROFILES.yaml is a plain git-diffable file parsed
   by both bash and PowerShell with line-based extraction (no YAML library).
4. Degrade and report — honored: unknown --profile fails fast with a usage
   error; a core-listed file missing from the source is reported (WARN), the
   sync completes; skill wrappers absent a prompt already self-report.
5. Additive first — honored: --profile is a new optional flag; default
   resolves to extended = byte-identical copy behavior; the pin gains one
   ADDITIVE line that layer-drift's key-anchored parser skips by construction
   (tolerance proven by test, not assumed).
6. Single-writer state — honored: all STATE writes via state.mjs CLI.
7. Operator-only merge — honored: no commits, no merge in this scope.

## Implementation strategy
- Strategy: tdd
- Rationale: the deliverable is distribution-script behavior (what lands in
  every downstream project). Every AC is gated by a test observed RED first:
  the new suite tests/skills/test-aai-layer-profiles.sh fails on the
  pre-change tree (no manifest, no --profile, no pin Profile line, no doctor
  display), and the layer-drift suite gains a Profile-line tolerance test.
  Prompt/doc edits (SKILL_DOCTOR, AAI_PIN contract) are grep-RED in the same
  run. No hybrid split is needed — the suite is one coherent surface.
- RED-proof obligation: before any implementation edit, run
  `bash tests/skills/test-aai-layer-profiles.sh` on the pre-change tree and
  save failing output plus grep-RED absence proofs (no --profile in either
  sync script, no Profile field in the pin contract, no profile display in
  SKILL_DOCTOR, no PROFILES.yaml) to docs/ai/tdd/layer-profiles-red.log; a
  second staged RED (manifest present, sync unchanged) must show TEST-002+
  failing against the untouched engine. layer-drift TEST-015 is a SURVIVAL
  INVARIANT (SPEC-0030 TEST-010 precedent): it passes pre-change BY
  CONSTRUCTION — parsePin is already key-anchored — and is non-vacuous
  because it re-runs after the stamping lands and pins the parser against
  future changes; its pre-change PASS is recorded in the RED log. TEST-002
  (default byte-identity) is non-vacuous because it diff-compares against
  the HEAD (pre-change) sync engine's output tree.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: distribution-script changes with repo-wide test sweep;
  parallel sibling streams (speclint, truth, advisory) are in flight — file
  isolation prevents cross-stream contamination. Not `required`: no protected
  surface (state/allocator/guards/canon) is touched.
- User decision: worktree (already executing in
  /Users/ales/Projects/aai-p3-profiles, branch feat/layer-profiles)
- Base ref: main
- Inline review scope (explicit paths):
  - docs/specs/SPEC-0035-spec-layer-profiles.md (this spec)
  - docs/issues/CHANGE-0023-layer-profiles.md (intake, pre-existing)
  - .aai/system/PROFILES.yaml (new manifest)
  - .aai/scripts/aai-sync.sh (--profile + filter + pin stamp)
  - .aai/scripts/aai-sync.ps1 (parity)
  - .aai/system/AAI_PIN.md (contract: Profile field)
  - .aai/SKILL_DOCTOR.prompt.md (CAT-13 profile display)
  - tests/skills/test-aai-layer-profiles.sh (new suite)
  - tests/skills/test-aai-layer-drift.sh (TEST-015 tolerance test)

## Design decisions

### D1 — Manifest shape: two flat path lists, extended = everything
`.aai/system/PROFILES.yaml` holds two top-level keys, `core:` and
`extended:`, each a flat list of repo-relative file paths under `.aai/`.
Semantics: the EXTENDED profile is the entire vendored tree (core list plus
extended list — the union is total by construction, enforced by TEST-001);
the CORE profile is exactly the `core:` list. The extended sync path never
consults the manifest at all — it remains the existing copy-everything code
UNCHANGED, which is what makes default byte-identity a structural guarantee
rather than a filtering claim. Line-based format (`  - <path>`) so bash (awk)
and PowerShell (regex over lines) parse it identically without a YAML
library (Constitution art. 3).

### D2 — Classification rule (what "core" means, from the intake)
core = everything a target project needs to run the WORKFLOW ENGINE:
orchestration/roles/planning/implementation/validation/remediation prompts,
all intake, state+docs+index+events scripts and their lib closure, gates
(TDD/verify/debug/review/check-state/docs-audit/pre-commit/hook-gate/locks),
loop+HITL+flush, distribution & health (sync/update/doctor/layer-drift/
bootstrap/migrate-state), the templates those flows instantiate, and canon
(AGENTS/PLAYBOOK/WORKFLOW/ROLES/PATTERNS/SUBAGENT_PROTOCOL/STATE_FALLBACK,
system contracts incl. PRICING.yaml consumed by orchestration-dispatch).
extended = visualization/reporting/publishing (dashboard, profile,
metrics-report, docs-hub, share, validate-report), integrations (decapod,
expert registry/fetch), one-off maintenance/migration (canonicalize,
docs-canon, test-canon, migrate-yaml-to-jsonl), session conveniences
(session-journal, wrap-up), brownfield analysis (reverse-analysis,
docs-compress, generate-readme), deprecated (auto-trigger), and self-hosting
QA (test-skills, validate-skills, PSScriptAnalyzerSettings, SELF_HOSTING,
SUPERPOWERS_INTEGRATION). The core script set is import-closed (verified:
every `.mjs` import of a core script resolves inside the core set; extended
scripts may import core libs, never the reverse).

### D3 — Classification scope is the .aai tree; other surfaces are
profile-independent
The manifest classifies 100% of `.aai/**` files (`.aai/cache/**` excluded —
runtime artifact, never synced). Root shims (CLAUDE.md/CODEX.md/GEMINI.md/
SKILLS.md/README_AAI.md), hooks/, .github, .cursor, .claude-plugin, agent
skill WRAPPERS (.claude/.codex/.gemini skills) and docs/knowledge seeds are
always synced regardless of profile: wrappers are 6-line pointers whose
bodies already self-report when their prompt is absent ("SKILL_X not found —
are you in an AAI project?"), which is the documented degrade path
(Constitution art. 4). Residual observation (accepted, recorded): doctor
CAT-03 may report extended wrappers as orphaned in a core install — honest
reporting; the new CAT-13 profile display gives the operator the context.
Filtering wrapper indexes per profile is a follow-up candidate, out of scope
(intake: no per-file cherry-picking).

### D4 — Profile resolution: flag > sticky pin > extended
`--profile core|extended` on both scripts. When the flag is ABSENT, the sync
reads the TARGET's existing pin for a `- Profile: <name>` line and honors it
(stickiness); no flag and no pin line -> extended. Stickiness is what keeps
`/aai-update` (which invokes sync flag-less) from silently reinstalling the
full layer over a core install. Existing consumers have no Profile line ->
default extended -> byte-identical behavior (AC-002). Unknown profile values
fail fast (usage error, exit 1 / throw). aai-update passthrough of --profile
is NOT added (out of scope; stickiness covers the update path — noted as
follow-up).

### D5 — Core copy path: filtered copy + prune, target-only preserved
In core mode the `.aai` copy phase is replaced by: (1) copy each `core:` path
from source (creating parent dirs; a listed-but-missing source file WARNs and
continues); (2) prune target `.aai/**` files NOT in the core list — this
removes both extended files from a previous extended sync (profile
downgrade works) and stale files, EXCEPT `.aai/scripts/` files that do not
exist in the source (target-only scripts, preserved with the same PRESERVE
message as the extended path) and `.aai/cache/**`; (3) delete directories
left empty. Every non-.aai surface runs the UNCHANGED existing code in both
modes. The pin is stamped `- Profile: <resolved name>` (new line between
`Canonical repo` and `Synced at`) by both scripts.

### D6 — layer-drift tolerance is proven, not assumed
layer-drift.mjs `parsePin` matches an explicit key alternation
(`Source path|Template version|Template commit|Canonical repo|Synced at`)
and skips all other lines, so `- Profile: core` is ignored by construction.
No parser change is made. Tolerance is REGRESSION-PINNED by
test-aai-layer-drift.sh TEST-015: a pin containing the Profile line must
still verify up-to-date (exit 0) and emit an intact --json contract.
SKILL_DOCTOR CAT-13 additionally reads the pin's Profile line (grep-level,
absent -> "extended (implicit)") and appends `profile: <name>` to the
report line.

### D7 — Conformance test enumerates the ACTUAL tree (future-proof)
TEST-001 runs against the repository itself: `find .aai -type f` (minus
`.aai/cache/`), then asserts (a) every found file appears in the manifest,
(b) every manifest entry exists on disk (no stale entries), (c) no path is
listed in both profiles, (d) no duplicate entries. A future file added
without classification fails the suite — classification cannot be skipped.

## Acceptance Criteria Mapping

- Maps to: CHANGE layer-profiles AC-001 ("PROFILES.yaml classifies 100% of
  vendored files; conformance test enumerates the tree and fails on unlisted")
  - Spec-AC-01: .aai/system/PROFILES.yaml exists with `core:`/`extended:`
    lists whose union equals exactly the set of files under .aai/ (excluding
    .aai/cache/), disjoint, no stale entries, PROFILES.yaml itself included
    (core). Conformance is checked against the live tree, not a snapshot.
  - Verification: TEST-001 (RED on pre-change tree: manifest absent).

- Maps to: CHANGE layer-profiles AC-002 ("sync --profile core copies exactly
  the core set; ps1 parity; default run byte-identical to today")
  - Spec-AC-02: `aai-sync.sh --profile core` into a fresh fixture target
    yields under .aai/ exactly the core list (file-list equality, both
    directions) plus the freshly stamped AAI_PIN.md; extended-only files are
    absent; a previously-extended target re-synced with core is pruned to the
    core set with target-only scripts preserved. A default (flag-less) run
    into a fresh target is byte-identical to the HEAD (pre-change) script's
    output for every file except .aai/system/AAI_PIN.md, whose diff is
    exactly the documented additive `- Profile: extended` line (+ timestamp).
    `--profile extended` == default. Unknown value -> usage error.
    ps1 parity: aai-sync.ps1 parses clean, carries the same flag/filter/stamp
    structure (structural greps), and — pwsh being available — an end-to-end
    ps1 core run produces the same .aai file set as the sh core run.
  - Verification: TEST-002 (default byte-identity vs HEAD sync), TEST-003
    (core = exact set), TEST-004 (prune on downgrade + target-only script
    preserved + idempotence), TEST-005 (invalid flag), TEST-008 (ps1 parity
    end-to-end + structural), plus tests/skills/test-ps1-quality.sh sweep
    (parse + PSScriptAnalyzer over the changed ps1).

- Maps to: CHANGE layer-profiles AC-003 ("pin records profile; doctor
  displays it; suites + audit green")
  - Spec-AC-03: both sync scripts stamp `- Profile: <core|extended>` into
    AAI_PIN.md; a flag-less re-sync of a core target STAYS core (sticky pin);
    .aai/system/AAI_PIN.md documents the field; layer-drift.mjs is tolerant
    (TEST-015 in its suite: Profile-stamped pin verifies exit 0, --json
    intact); SKILL_DOCTOR CAT-13 reads and displays the profile (absent ->
    extended implicit) in both the category body and OUTPUT FORMAT line; full
    tests/skills sweep green (incl. test-aai-layer-drift.sh,
    test-ps1-quality.sh); `docs-audit --strict` CLEAN; check-state OK.
  - Verification: TEST-006 (pin stamp + stickiness), TEST-007 (doctor
    display, grep-RED), layer-drift TEST-015, full sweep + strict audit.

## Acceptance Criteria Status

| Spec-AC    | Description                                      | Status  | Evidence | Review-By | Notes |
|------------|--------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Manifest classifies 100% of .aai tree, test-enforced | done | docs/ai/tdd/layer-profiles-green.log (TEST-001: core=106 extended=41 total=147, 100%) | — | RED: docs/ai/tdd/layer-profiles-red.log (run 1: manifest absent) |
| Spec-AC-02 | --profile core exact set; default byte-identical; ps1 parity | done | docs/ai/tdd/layer-profiles-green.log (TEST-002..005, TEST-008); test-ps1-quality.sh PASS (parse + PSScriptAnalyzer 5.1/7.0 + Pester) | — | RED: red.log run 2b (TEST-002 failing pin diff vs HEAD engine); standalone default-profile idempotence probe PASS |
| Spec-AC-03 | Pin Profile line; drift tolerant; doctor displays; suites+audit green | done | green.log (TEST-006/007); test-aai-layer-drift.sh PASS incl. TEST-015; full sweep 25/26 suites PASS (test-aai-worktree.sh fails identically on pristine HEAD export — pre-existing, unrelated); docs-audit --strict CLEAN; check-state OK | — | TEST-015 pre-change PASS recorded in red.log (survival invariant, spec D6) |

## Implementation plan
- .aai/system/PROFILES.yaml — new manifest (D1/D2), self-documenting header.
- .aai/scripts/aai-sync.sh — arg loop (--profile), resolution (D4), core
  filtered-copy+prune path (D5), pin Profile stamp.
- .aai/scripts/aai-sync.ps1 — same, PowerShell (ValidateSet-free manual
  validation to keep 5.1 parse compatibility with an optional parameter).
- .aai/system/AAI_PIN.md — Profile field contract note.
- .aai/SKILL_DOCTOR.prompt.md — CAT-13 profile read+display; OUTPUT FORMAT.
- tests/skills/test-aai-layer-profiles.sh — new suite (TEST-001..TEST-008).
- tests/skills/test-aai-layer-drift.sh — TEST-015 Profile tolerance.
- Edge cases: pin with CRLF (parser tolerant by existing `\r` strip; sticky
  read uses tr -d '\r'); target with no pin; core-listed file missing in
  source (WARN, continue); empty dirs after prune; .aai/cache never touched;
  spaces in fixture paths (existing suite precedent).

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                        | Description                                                        | Status  |
|----------|------------|-------------|---------------------------------------------|--------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-layer-profiles.sh     | Manifest total/disjoint/no-stale vs live `find .aai -type f`        | green |
| TEST-002 | Spec-AC-02 | e2e         | tests/skills/test-aai-layer-profiles.sh     | Default run byte-identical to HEAD sync (all files; pin diff = Profile line + timestamp only); --profile extended == default | green |
| TEST-003 | Spec-AC-02 | e2e         | tests/skills/test-aai-layer-profiles.sh     | --profile core copies exactly the core set (two-way file-list equality; extended-only absent) | green |
| TEST-004 | Spec-AC-02 | e2e         | tests/skills/test-aai-layer-profiles.sh     | Extended->core re-sync prunes; target-only script preserved; core re-run idempotent (no tree diff except pin timestamp) | green |
| TEST-005 | Spec-AC-02 | integration | tests/skills/test-aai-layer-profiles.sh     | --profile bogus fails fast with usage error, target untouched      | green |
| TEST-006 | Spec-AC-03 | e2e         | tests/skills/test-aai-layer-profiles.sh     | Pin stamps `- Profile:`; flag-less re-sync honors sticky core pin  | green |
| TEST-007 | Spec-AC-03 | integration | tests/skills/test-aai-layer-profiles.sh     | SKILL_DOCTOR CAT-13 reads/displays profile incl. OUTPUT FORMAT (grep) | green |
| TEST-008 | Spec-AC-02 | e2e         | tests/skills/test-aai-layer-profiles.sh     | ps1 parity: parse-clean, structural flag/filter/stamp greps, end-to-end pwsh core run set-equal to sh core run | green |
| TEST-015 | Spec-AC-03 | integration | tests/skills/test-aai-layer-drift.sh        | layer-drift tolerates the Profile pin line: exit 0 up-to-date, --json contract intact | green |

## Verification
- bash tests/skills/test-aai-layer-profiles.sh (RED first ->
  docs/ai/tdd/layer-profiles-red.log; GREEN after)
- bash tests/skills/test-aai-layer-drift.sh (TEST-015 RED by grep-absence
  first; GREEN after)
- Full sweep: for t in tests/skills/test-*.sh; do bash "$t"; done
  (0 or 42-skip only; explicitly incl. test-aai-layer-drift.sh and
  test-ps1-quality.sh)
- node .aai/scripts/docs-audit.mjs --strict — CLEAN
- Real idempotence probe: two consecutive core syncs into the same target;
  second run changes nothing but the pin timestamp
- node .aai/scripts/check-state.mjs docs/ai/STATE.yaml — OK
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal

## Evidence contract
Record per artifact: ref_id (layer-profiles), Spec-AC / TEST-xxx link,
command, exit code, evidence path (docs/ai/tdd/layer-profiles-red.log, suite
output), diff range when available.

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
