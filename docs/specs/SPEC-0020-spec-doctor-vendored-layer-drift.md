---
id: spec-doctor-vendored-layer-drift
type: spec
number: 20
status: implementing
links:
  change: doctor-vendored-layer-drift
  research: RES-0001
  rfc: null
  pr: []
  commits: []
---

# SPEC — aai-doctor Reports Vendored-Layer Drift vs Canonical Main

SPEC-FROZEN: true

## Links
- Change: doctor-vendored-layer-drift
  (docs/issues/CHANGE-0013-doctor-vendored-layer-drift.md)
- Research: RES-0001
  (docs/specs/RES-0001-aai-competitive-gap-and-model-efficiency.md)
- Pattern precedent: `.aai/scripts/orchestration-mode.mjs` (pure decision core
  + thin CLI, deterministic exit codes, `--json`), `.aai/scripts/docs-lock.mjs`
  (documented exit-code contract consumed by callers)
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: as per template

## Problem (evidence-verified 2026-07-16)
1. `.aai/system/AAI_PIN.md` (stamped by `aai-sync.sh` lines 554-566 and
   `aai-sync.ps1` lines 610-624) records ONLY: `Source path`,
   `Template version`, `Template commit`, `Synced at (UTC)`. There is NO
   canonical repo URL in the pin — the only place the canonical remote is
   known is `aai-update.sh`'s hardcoded default `REPO="goodwind-cz/aai"`.
2. `.aai/SKILL_DOCTOR.prompt.md` runs 12 categories (CAT-01..CAT-12); none
   compares the pin's `Template commit` against the canonical repo, so a
   vendored project silently ages (operator hit this twice: ISSUE-0006/0008
   fixed in canon while the project kept minting wrong doc numbers).
3. Doctor checks are prompt-driven, but every non-trivial check delegates to a
   deterministic script (`docs-audit.mjs --quick`, `check-state` semantics).
   Drift computation (pin parsing, git plumbing, network degradation) is
   script-shaped work.

## Design decisions

### D1 — Pin contract extension: `Canonical repo` field
`AAI_PIN.md` gains one line, stamped by BOTH sync scripts going forward:

    - Canonical repo: <origin URL of the sync source, or UNKNOWN>

Derivation at sync time: `git -C "$SRC_ROOT" config --get remote.origin.url`
(empty/failed -> `UNKNOWN`). Backward-tolerant: a pin WITHOUT the field (or
with `UNKNOWN`) is legal — the drift check falls through the D2 resolution
order and, if nothing resolves, degrades to `unverifiable` (never an error).
The CHANGE draft's "out of scope: changing aai-sync/aai-update themselves" is
amended by this spec: the pin-writer block in the sync scripts is IN scope
(that is where the pin contract lives); sync/update BEHAVIOR is unchanged.
`aai-update.sh`'s post-sync evidence grep is widened to also surface the new
`Canonical repo` line (`canonical` added to its pattern) — evidence-only.

### D2 — Canonical remote resolution order
The check resolves the canonical comparison target in this order (first hit
wins; documented in the script header):
1. `--remote <url-or-path>` CLI flag (tests, CI, operator override).
2. Pin `Canonical repo:` field (D1; stamped going forward).
3. Pin `Source path:` when it names an EXISTING local directory that
   `git rev-parse` accepts (covers all pre-D1 pins synced from a local
   checkout — the dominant historical case).
4. Nothing resolves -> `unverifiable` ("pin lacks canonical remote — run
   /aai-update to restamp"), exit 4.
No hardcoded `goodwind-cz/aai` fallback: a fork-vendored project must never
be compared against the wrong upstream; restamping via /aai-update is the fix.
Placeholder pin values (`<set by sync script>`, `UNKNOWN`) are treated as
absent. Compared ref defaults to `main` (`--ref` overrides).

### D3 — Honest distance tiers (no lying about N)
- Tier LOCAL (canonical is a locally reachable git dir — resolution hit is an
  existing directory): full verdict.
  - `pin == rev-parse <ref>` -> `up-to-date`, exit 0.
  - pin is ancestor of canonical `<ref>` -> `behind` with
    N = `git rev-list --count <pin>..<ref>`, exit 3.
  - canonical `<ref>` is ancestor of pin -> `ahead` (pin from unmerged
    work), exit 0 with info note — not drift needing /aai-update.
  - pin unknown to canonical history / diverged -> `drift` with distance
    null, exit 3 ("unknown distance").
- Tier REMOTE (canonical is a URL): `git ls-remote <url> <ref>` yields ONLY
  the tip sha — equality is provable, distance is not.
  - equal -> `up-to-date`, exit 0.
  - different -> `behind` with distance null ("unknown distance — canonical
    not locally reachable"), exit 3. No fetch is performed: doctor is
    read-only and must stay fast.
- Tier OFFLINE: ls-remote fails or times out (bounded: 10s default,
  `--timeout-ms` override; `GIT_TERMINAL_PROMPT=0` so it can never hang on a
  credential prompt) -> `unverifiable (offline or canonical unreachable)`,
  exit 4.
- No pin file / placeholder pin -> `unverifiable`, exit 4 (the canonical
  template repo itself carries the placeholder pin, so doctor run in canon
  reports "not a vendored project" info, never drift).

### D4 — Strictly degrade-and-report
Exit codes are for CALLERS to branch on; doctor NEVER hard-fails from this
category. New script `.aai/scripts/layer-drift.mjs`:
- 0 = up-to-date (or ahead) ; 3 = drift detected (behind/diverged) ;
  4 = unverifiable (no pin / no remote / offline) ; 2 = usage error.
- `--json` prints one machine-readable object:
  `{status, relation, pin_commit, canonical_head, ref, remote, source,
    distance, message}` where status ∈ up_to_date|behind|unverifiable,
  relation ∈ equal|behind|ahead|diverged|unknown, source names the D2
  resolution hit (cli|pin_canonical_repo|pin_source_path|none).
- Human mode prints exactly one verdict line (the doctor report line).
SKILL_DOCTOR gains `[CAT-13] Vendored Layer Drift` which runs the script and
maps: exit 0 -> ✓, exit 3 -> ⚠ + `/aai-update` remedy, exit 4/2/missing
script -> ⚠ info. Category is informational — never BROKEN, never blocks.

### D5 — Fixture-driven tests, zero real network
`tests/skills/test-aai-layer-drift.sh` (framework conventions of
`test-aai-docs-lock.sh`: `set -euo pipefail`, log_pass/log_fail/log_skip 42,
mktemp fixtures, trap cleanup). Fake canonical = local `git init` repo with
K commits; REMOTE tier exercised via `file://` URLs (ls-remote code path, no
network); OFFLINE tier via a `file://` URL to a nonexistent path (fails
fast). The sync-stamping test copies the real `aai-sync.sh` into a minimal
fixture source repo (with an `origin` remote configured) and syncs into a
fixture target, then asserts the pin contains the D1 field.

## Implementation strategy
- Strategy: loop
- Rationale: one new self-contained read-only script + prompt wiring + sync
  stamp lines — mechanical, low-risk glue. RED-proof obligation still holds:
  the new suite is run BEFORE the implementation exists (script missing,
  grep targets absent) and its failure output captured as RED evidence.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: PR-bound work on the vendored-layer contract, developed
  in parallel with other in-flight scopes.
- User decision: worktree
- Base ref: main
- Worktree branch/path: feat/doctor-layer-drift @
  /Users/ales/Projects/aai-feat-layer-drift
- Inline review scope: .aai/scripts/layer-drift.mjs, .aai/scripts/aai-sync.sh,
  .aai/scripts/aai-sync.ps1, .aai/scripts/aai-update.sh,
  .aai/system/AAI_PIN.md, .aai/SKILL_DOCTOR.prompt.md,
  tests/skills/test-aai-layer-drift.sh,
  docs/issues/CHANGE-0013-doctor-vendored-layer-drift.md, this spec

## Acceptance Criteria Mapping
- Maps to: AC-001 (pin == remote HEAD -> up-to-date, exit unchanged)
  - Spec-AC-01: `layer-drift.mjs` with pin commit equal to canonical `<ref>`
    tip prints the up-to-date line naming the sha and exits 0, in BOTH the
    local-dir tier and the `file://` ls-remote tier.
  - Verification: TEST-002, TEST-004a.
- Maps to: AC-002 (behind -> BEHIND naming N, or unknown distance + remedy)
  - Spec-AC-02: pin N commits behind a locally reachable canonical prints
    "BEHIND canonical by N commit(s)" + `/aai-update` remedy, exit 3; the
    URL-only tier proves inequality and prints "unknown distance" + remedy,
    exit 3.
  - Verification: TEST-003, TEST-004b.
- Maps to: AC-003 (no network / no pin -> info line, doctor still completes)
  - Spec-AC-03: missing pin file, placeholder pin, unresolvable remote, and
    unreachable remote each print an `unverifiable` info line and exit 4 —
    never a crash, never exit 1; SKILL_DOCTOR CAT-13 maps 4 to ⚠ info and is
    documented informational/never-BROKEN.
  - Verification: TEST-005, TEST-006, TEST-007, TEST-011.
- Maps to: AC-004 (doctor suite covers all paths with fixtures, no network)
  - Spec-AC-04: `tests/skills/test-aai-layer-drift.sh` covers
    up-to-date/behind/unverifiable via local fixtures and `file://` URLs
    only; suite greps itself for forbidden real-network URL schemes.
  - Verification: TEST-001..TEST-011 all in one suite; suite passes on a
    machine with no network access.
- Maps to: AC-002 + D1 (pin contract extension, stamped going forward)
  - Spec-AC-05: both sync scripts stamp `- Canonical repo: <origin-url>`
    (or `UNKNOWN`); a real `aai-sync.sh` run into a fixture target produces a
    pin containing the field; missing field on old pins degrades per D2
    (source-path fallback proven by TEST-008).
  - Verification: TEST-008, TEST-010, TEST-010b (ps1 static parity grep).
- Maps to: Desired Behavior (doctor prints one of the three lines)
  - Spec-AC-06: SKILL_DOCTOR.prompt.md contains a CAT-13 section that invokes
    `node .aai/scripts/layer-drift.mjs`, maps the three exit tiers to
    ✓/⚠+remedy/⚠info, and appears in the OUTPUT FORMAT block.
  - Verification: TEST-011.

## Acceptance Criteria Status

| Spec-AC    | Description                                      | Status | Evidence | Review-By | Notes |
|------------|--------------------------------------------------|--------|----------|-----------|-------|
| Spec-AC-01 | equal pin -> up-to-date line, exit 0 (both tiers)| done   | RUN test-aai-layer-drift 2026-07-16 TEST-002/004a | — | — |
| Spec-AC-02 | behind -> N + remedy (local) / unknown distance (URL), exit 3 | done | RUN test-aai-layer-drift 2026-07-16 TEST-003/004b | — | — |
| Spec-AC-03 | no pin / placeholder / offline -> unverifiable info, exit 4 | done | RUN test-aai-layer-drift 2026-07-16 TEST-005/006/007 | — | — |
| Spec-AC-04 | fixture-driven suite, zero real network          | done   | RUN test-aai-layer-drift 2026-07-16 (full suite, file:// only) | — | — |
| Spec-AC-05 | pin contract: Canonical repo stamped by sync (sh+ps1), backward-tolerant | done | RUN test-aai-layer-drift 2026-07-16 TEST-008/010/010b | — | — |
| Spec-AC-06 | SKILL_DOCTOR CAT-13 wired, informational only    | done   | RUN test-aai-layer-drift 2026-07-16 TEST-011 | — | — |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan
- `.aai/scripts/layer-drift.mjs` (new, ~250 lines): pin parser + D2 resolver
  + D3 tier logic as pure functions, thin CLI with `--pin`, `--remote`,
  `--ref`, `--timeout-ms`, `--json`. Read-only; only child processes are
  `git` invocations with `GIT_TERMINAL_PROMPT=0` and a hard timeout.
- `.aai/scripts/aai-sync.sh`: derive `CANONICAL_URL` next to the existing
  `TEMPLATE_SHA` block; add the D1 line to the heredoc.
- `.aai/scripts/aai-sync.ps1`: same two-line parity change.
- `.aai/scripts/aai-update.sh`: widen the pin-evidence grep to include
  `canonical`.
- `.aai/system/AAI_PIN.md` (template): add the placeholder line + contract
  notes (field list, backward tolerance).
- `.aai/SKILL_DOCTOR.prompt.md`: CAT-13 section + OUTPUT FORMAT line.
- `docs/issues/CHANGE-0013-doctor-vendored-layer-drift.md`: scope wording
  amended per D1 (pin stamping in scope).
- Edge cases: pin sha shorter than full 40 (accept, compare via rev-parse
  when local; string-compare prefix-safe via `git rev-parse <pin>` in local
  tier; remote tier requires full-sha equality else falls to inequality with
  unknown distance); CRLF pins (strip `\r`); `--remote` pointing at a
  directory without git -> unverifiable, not crash.

## Test Plan

| Test ID   | Spec-AC    | Type | File path (expected)                  | Description | Status |
|-----------|------------|------|---------------------------------------|-------------|--------|
| TEST-001  | Spec-AC-03 | unit | tests/skills/test-aai-layer-drift.sh  | unknown flag / missing --pin value exits 2 with usage | green |
| TEST-002  | Spec-AC-01 | int  | tests/skills/test-aai-layer-drift.sh  | pin == local canonical HEAD -> "up-to-date", exit 0 | green |
| TEST-003  | Spec-AC-02 | int  | tests/skills/test-aai-layer-drift.sh  | pin 2 behind local canonical -> "BEHIND canonical by 2 commit(s)" + /aai-update, exit 3 | green |
| TEST-004a | Spec-AC-01 | int  | tests/skills/test-aai-layer-drift.sh  | file:// remote, equal -> up-to-date, exit 0 (ls-remote tier) | green |
| TEST-004b | Spec-AC-02 | int  | tests/skills/test-aai-layer-drift.sh  | file:// remote, different -> unknown distance + remedy, exit 3 | green |
| TEST-005  | Spec-AC-03 | int  | tests/skills/test-aai-layer-drift.sh  | file:// remote to nonexistent path -> unverifiable, exit 4 | green |
| TEST-006  | Spec-AC-03 | unit | tests/skills/test-aai-layer-drift.sh  | missing pin file -> unverifiable, exit 4 | green |
| TEST-007  | Spec-AC-03 | unit | tests/skills/test-aai-layer-drift.sh  | placeholder/template pin -> unverifiable "not stamped", exit 4 | green |
| TEST-008  | Spec-AC-05 | int  | tests/skills/test-aai-layer-drift.sh  | pin WITHOUT Canonical repo field but with reachable Source path -> local tier used (D2 order) | green |
| TEST-009  | Spec-AC-01..03 | unit | tests/skills/test-aai-layer-drift.sh | --json emits parseable object with status/relation/distance/source per tier | green |
| TEST-010  | Spec-AC-05 | e2e  | tests/skills/test-aai-layer-drift.sh  | real aai-sync.sh into fixture target stamps "- Canonical repo: <origin url>" | green |
| TEST-010b | Spec-AC-05 | unit | tests/skills/test-aai-layer-drift.sh  | aai-sync.ps1 contains the Canonical repo stamp line (static parity) | green |
| TEST-011  | Spec-AC-06 | unit | tests/skills/test-aai-layer-drift.sh  | SKILL_DOCTOR.prompt.md has CAT-13 invoking layer-drift.mjs, exit mapping, informational wording, OUTPUT FORMAT line | green |

Seam analysis: the pin file is written by aai-sync (sh+ps1) and read by
layer-drift.mjs — TEST-010 crosses that seam end-to-end (real sync writes the
pin, then the drift script reads THAT pin and verifies against the fixture
canonical). No other feature reads the pin today (aai-update only echoes it).

## Verification
- `bash tests/skills/test-aai-layer-drift.sh` — exit 0, all TEST-xxx PASS.
- RED evidence: same command captured BEFORE implementation (script missing,
  greps empty) — suite fails.
- Sweep: `node .aai/scripts/docs-audit.mjs --strict` exit 0;
  `node .aai/scripts/generate-docs-index.mjs` twice -> second run no diff;
  `node .aai/scripts/check-state.mjs` exit 0.
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal.

## Evidence contract
- ref_id: doctor-vendored-layer-drift
- RED run: tests/skills/test-aai-layer-drift.sh before implementation
  (captured in implementation notes / validation report)
- GREEN run: same suite, exit 0
- Sweep: docs-audit --strict, index idempotency, check-state outputs
- Commit SHA: recorded at PR time (this change ships uncommitted for review)

## Review finding dispositions (2026-07-16)

- B1 (main-guard never matched -> CLI silently exit 0, which doctor CAT-13
  reads as up-to-date): REMEDIATED. Remediation surfaced TWO stacked causes:
  (1) percent-encoded URL pathname vs decoded argv (spaces, non-ASCII);
  (2) node resolves symlinks for import.meta.url while argv keeps the invoked
  spelling (macOS /tmp -> /private/tmp), so decoded-only comparison STILL
  failed. Fix compares realpath-resolved decoded paths (realOrResolve both
  sides); TEST-014 space-in-path regression exercises both layers (mktemp
  under the /tmp symlink + a space in the dir name). Follow-up noted: other
  .mjs CLI guards in the repo use the decoded-only pattern and share latent
  layer (2) — candidate for a sweep CHANGE.
- N1 (garbage pin sha -> drift exit 3, not unverifiable): ACCEPTED — matches
  D3 (an unparseable pin IS drift evidence; the remedy line is identical).
- N2 (quoted URL not unquoted) / N3 (case-sensitive marker): ACCEPTED — sync
  never emits either form; degrade path is safe (unverifiable).
