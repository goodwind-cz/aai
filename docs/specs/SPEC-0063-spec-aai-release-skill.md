---
id: spec-aai-release-skill
type: spec
number: 63
status: draft
ceremony_level: 2
links:
  requirement: aai-release-skill
  rfc: null
  pr: []
  commits: []
---

# Implementation Spec — Portable `/aai-release` skill (deterministic release-cut engine)

SPEC-FROZEN: true

## Links
- Requirement / intake: docs/issues/CHANGE-0044-aai-release-skill.md
- Decision records: none
- Technology contract: docs/TECHNOLOGY.md
- Reference pattern: .aai/scripts/aai-update.sh (deterministic script; `--dry-run`;
  self-relocate; portable; prints evidence), .aai/SKILL_UPDATE.prompt.md +
  .claude/skills/aai-update/SKILL.md (thin-wrapper prompt + 3-agent-tree wrapper)
- Learned rules: docs/knowledge/LEARNED.md (Session 2026-07-19 — BSD/GNU +
  fresh-checkout portability)

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: see template semantics

## Implementation strategy
- Strategy: hybrid
- Rationale: The CHANGELOG-rollup transform and the fail-closed precondition
  engine are byte-surgical, data-integrity-critical (a wrong roll silently drops
  changelog entries or corrupts an outward-facing release) and carry real edge
  cases — they demand `tdd` (RED-proven per TEST before GREEN). The thin-wrapper
  prompt, the 3-agent-tree wrappers, the PROFILES.yaml classification, and the
  USER_GUIDE/CHANGELOG docs are mechanical wiring where RED-GREEN-REFACTOR adds
  little signal — `loop`. Hence `hybrid`.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: PR-bound feature touching six independent surfaces (new
  `aai-release.{sh,ps1}` engine, `SKILL_RELEASE.prompt.md`, three agent-tree
  wrappers, `PROFILES.yaml`, `tests/skills/test-aai-release.sh`, and
  `docs/USER_GUIDE.md`+`CHANGELOG.md`). Not `required`: no path lies in
  `protected_paths_l3` (state engine / allocator / guards / WORKFLOW / CONSTITUTION),
  and every edit is additive. A user decision is required before implementation
  because the recommendation is `recommended` (inline override permitted with an
  explicit review scope).
- User decision: undecided
- Base ref: main (current working branch feat/aai-release-skill)
- Worktree branch/path: <if selected by user>
- Inline review scope: `.aai/scripts/aai-release.sh`, `.aai/scripts/aai-release.ps1`,
  `.aai/SKILL_RELEASE.prompt.md`, `.claude/skills/aai-release/SKILL.md`,
  `.codex/skills/aai-release/SKILL.md`, `.gemini/skills/aai-release/SKILL.md`,
  `.aai/system/PROFILES.yaml`, `tests/skills/test-aai-release.sh`,
  `docs/USER_GUIDE.md`, `CHANGELOG.md`

## Code review
- code_review.required: true (new scripts, tests, profile manifest, and prompt
  wrappers — a code+workflow change, not read-only analysis).
- Scope: the Inline review scope path list above (or the branch diff range).

## Frozen design (authoritative for implementation)

### D1. CHANGELOG rollup transform (line-surgical, idempotent, content byte-preserved)
The repo's established released-section shape is
`## [v2026.07.04] — <type>: <title> (<refs>)` and unreleased entries are stacked
sibling headings `## [unreleased] — <type>: <title> (<refs>)` (heading separator
is U+2014 EM DASH with a surrounding space on each side: bytes `20 e2 80 94 20`).
There are 34 such `## [unreleased] — …` blocks in the current CHANGELOG.

RECONCILIATION (Planning decision): the intake's AC-002 phrasing "under a new
`## [<version>] — <YYYY-MM-DD>` heading" is reconciled to the repo's actual,
byte-verified convention — the transform is a **version-token swap that preserves
each block's own `— <type>: <title>` tail**, reproducing the existing
`[v2026.07.04]` sections exactly (Keep-a-Changelog fidelity per docs/TECHNOLOGY.md;
the CalVer version token already carries the date, so no separate `<YYYY-MM-DD>`
is added to the heading). The date is surfaced in the release NOTES, not the
CHANGELOG heading.

Grammar classification — for every line matching `^## \[unreleased\]`:
- **ENTRY** heading: matches `^## \[unreleased\] — ` (space + EM DASH + space + tail).
- **SCAFFOLD** heading: matches `^## \[unreleased\][[:space:]]*$` AND has zero
  non-blank body lines before the next `^## ` heading or EOF (this is the fresh
  placeholder a prior cut leaves behind).
- **MALFORMED**: any `^## \[unreleased\]` line that is neither (e.g. a bare token
  followed by body content lines, or a token with trailing junk that is not ` — …`).

Transform algorithm (deterministic, no LLM in the write path):
1. Parse CHANGELOG.md into lines. The preamble (text before the first `## [`
   heading) is NEVER touched.
2. If any MALFORMED unreleased heading exists → FAIL-CLOSED, zero writes (never
   silently drop entries).
3. Let `entryCount` = number of ENTRY headings. If `entryCount == 0` → the
   `[unreleased]` section is EMPTY (scaffold-only) or ABSENT (none) → FAIL-CLOSED,
   zero writes (AC-003).
4. Otherwise build the new content line-by-line:
   - For each ENTRY heading line, replace the first occurrence of the literal
     substring `[unreleased]` with `[<version>]`. The regex only ever matches
     `[unreleased]`, never `[v…]`, so already-released headings are untouched.
   - Immediately before the FIRST ENTRY heading (original file order), insert the
     fresh scaffold exactly: the line `## [unreleased]` followed by one blank line.
   - Every other line (all block bodies, blank lines, released sections, preamble)
     is copied BYTE-FOR-BYTE.
5. Write atomically (tmp file + rename), preserving the file's final-newline state.

Idempotence: after a successful roll the only unreleased heading is the bare
SCAFFOLD (no ENTRY), so a second run with the same arguments and no newly-added
entries hits step 3 and REFUSES — there is no double-roll and released headings
can never be re-transformed. "Idempotent" here means: untouched lines are
byte-identical, and the engine never transforms an already-released heading.

### D2. Release-notes extraction (CHANGELOG ↔ release-notes seam, SEAM-1)
- Release TITLE = the resolved `<version>` string.
- Release BODY = the concatenation, in file order, of every just-rolled block
  (each rolled `## [<version>] — …` heading plus its body lines), with leading/
  trailing blank lines trimmed. In the repo's contiguous-unreleased layout this
  is the single contiguous span from the first rolled heading down to the line
  before the first pre-existing older `## [v…]` released heading (or EOF).
- The script writes this body to a temp notes file consumed by
  `gh release create <version> --title <version> --notes-file <file>`. The body
  is derived FROM the just-written CHANGELOG section (single source of truth) —
  the notes are never independently reconstructed.

### D3. Version resolution (clock-controllable for tests)
- `--version <v>`: used VERBATIM (any scheme accepted incl. SemVer; no leading
  `v` is added or stripped). This value is the CHANGELOG token, the tag name, and
  the release title.
- Omitted → default CalVer `vYYYY.MM.DD`:
  - If env `AAI_RELEASE_DATE` is set and non-empty, it is the date source
    (expected `YYYY-MM-DD`) and is reformatted to `vYYYY.MM.DD` by string
    substitution — the system clock is NOT consulted. Tests pin the date by
    setting `AAI_RELEASE_DATE=2026-07-20` → default version `v2026.07.20`.
  - Otherwise the default is `date -u +v%Y.%m.%d` (real UTC clock).

### D4. Operator gate (default-safe; explicit confirm required; never auto-publish)
- The CUT happens ONLY when `--confirm` (alias `--yes`) is present AND `--dry-run`
  is absent. Any other combination is PLAN-ONLY (prints the plan, zero writes,
  exit 0) — so a bare `aai-release.sh` invocation is default-safe. If both
  `--confirm` and `--dry-run` are given, `--dry-run` wins (safe).
- The agent/wrapper NEVER passes `--confirm` on its own initiative; publishing is
  operator-gated (mirrors the operator-only-merge boundary, Constitution Art. 7).

### D5. Remote seam (test-safety gate — never publish/push in tests, SEAM under RR-1)
- `--no-remote` flag OR env `AAI_RELEASE_NO_REMOTE=1` (unset by default): performs
  the full LOCAL cut (CHANGELOG rewrite + `chore(release)` commit + annotated tag)
  but SKIPS `git push` and `gh release create`, printing what it WOULD push/publish.
- The test suite exercises confirm-cuts with `AAI_RELEASE_NO_REMOTE=1` (local-cut
  arms) and, for the remote arm, with a STUB `gh` on PATH + a local `file://` bare
  remote — NEVER the real upstream. Absent the env/flag, a real cut pushes and
  publishes to the repo's actual `origin`/`gh` remote (operator use).

### D6. Fail-closed precondition matrix (zero writes on refusal, AC-003)
All preconditions are checked BEFORE any filesystem/git write, so any refusal
leaves the tree byte-identical. Two tiers:
- ALWAYS-checked (both plan and cut) — refusal is fail-closed exit non-zero:
  (a) not a git repo (`git rev-parse --git-dir` fails); (b) no `CHANGELOG.md` at
  repo root; (c) unreleased region ABSENT / EMPTY / MALFORMED (D1 steps 2–3).
- CUT-path gates (a plan/dry-run reports them as "would block" but still exits 0
  because it writes nothing; a `--confirm` cut refuses exit non-zero, zero writes):
  (d) dirty working tree (`git status --porcelain` non-empty); (e) a tag for the
  resolved version already exists; (f) `gh` absent or unauthenticated on the
  PUBLISH path (skipped entirely under `--no-remote`/`AAI_RELEASE_NO_REMOTE`; the
  gh-auth probe runs BEFORE the CHANGELOG write so a publish-auth failure yields
  zero writes rather than a committed-but-unpublished state). Dry-run must work
  fully offline (no `gh` required).

### D7. The cut sequence (confirm path, remote enabled)
Ordered so refusal is always zero-writes: (1) resolve version; (2) run the full
D6 precondition matrix; (3) rewrite CHANGELOG.md (D1); (4) `git add CHANGELOG.md`
(ONLY that path); (5) `git commit -m "chore(release): <version>"`; (6)
`git tag -a <version> -m "<version>"` (ANNOTATED); (7) unless `--no-remote`:
`git push` the commit + tag to the current branch's upstream, then
`gh release create <version> --title <version> --notes-file <notes>` (D2).

### D8. Portability (AC-004; LEARNED 2026-07-19)
- `.sh` (bash) + `.ps1` (PowerShell) parity kept in lockstep (like every other
  `.aai/scripts/aai-*.{sh,ps1}` pair). The bash skill-suite is the enforcing
  functional gate; `.ps1` parse is covered by the existing `ps1-quality` workflow.
- No BSD-only constructs: any `mktemp` uses a FULL `…​.XXXXXX` template (never
  `mktemp -t <bare-prefix>`); any `stat` tries GNU `stat -c` FIRST then BSD
  `stat -f` fallback (never `stat -f`-first).
- No AAI-repo-specific assumptions: the only inputs are the repo root, its
  `CHANGELOG.md`, and its git/`gh` remote — it runs identically in a deployed
  target project that has no `.aai/` of its own.

### D9. Thin-wrapper prompt + 3-agent-tree wrappers (mirror aai-update)
- `.aai/SKILL_RELEASE.prompt.md`: the canonical thin wrapper — Goal / Usage
  (documenting `--dry-run`, `--version`, `--confirm`/`--yes`, `--no-remote`) /
  Instructions (run the one script for the current OS, forward flags verbatim,
  relay a SHORT evidence report, decode exit codes) / Safety (never pass
  `--confirm` unprompted; never auto-publish; dry-run first). Mirrors the shape
  and quality of `.aai/SKILL_UPDATE.prompt.md`.
- `.claude/skills/aai-release/SKILL.md`, `.codex/skills/aai-release/SKILL.md`,
  `.gemini/skills/aai-release/SKILL.md`: byte-shaped like the `aai-update`
  wrappers — read `.aai/SKILL_RELEASE.prompt.md`, invoke as `/aai-release`, with
  the "not found" degrade line.

### D10. PROFILES.yaml additions (AC-005; script ↔ PROFILES ↔ CI gate seam, SEAM-2)
- Add exactly the three NEW `.aai/**` paths to the `core:` list (classification
  rule D2 in PROFILES.yaml: distribution/health engine + workflow prompt →
  core): `.aai/scripts/aai-release.sh`, `.aai/scripts/aai-release.ps1`,
  `.aai/SKILL_RELEASE.prompt.md`. The wrappers under `.claude/.codex/.gemini`,
  the test suite, and the docs are NON-`.aai/` surfaces (profile-independent) and
  are NOT classified. `tests/skills/test-aai-layer-profiles.sh` TEST-001 enforces
  UNION == live `.aai` tree, so an unclassified addition fails the suite.

## Acceptance Criteria Mapping

- Maps to: intake AC-001 (dry-run, default-safe)
- Spec-AC-01: `aai-release.sh --dry-run` (and a bare invocation with neither
  `--confirm` nor `--dry-run`) in a seeded scratch repo prints the resolved
  version, the CHANGELOG rollup it WOULD write, the tag name, and the notes
  preview; changes NOTHING (no CHANGELOG edit, commit, tag, release, or push);
  exit 0.
- Verification: TEST-001, TEST-002 — assert stdout carries all four elements,
  `git status --porcelain` empty after, no new tag/commit, exit 0.

- Maps to: intake AC-002 (the cut)
- Spec-AC-02: with `--confirm` (and `--no-remote` or a stubbed remote in tests)
  the script (a) rewrites CHANGELOG.md per D1 (every `## [unreleased] — …` →
  `## [<version>] — …`, bodies byte-preserved, fresh bare `## [unreleased]`
  scaffold on top); (b) commits `chore(release): <version>` staging ONLY
  CHANGELOG.md; (c) creates an ANNOTATED tag `<version>`; (d) builds notes
  (title=`<version>`, body=the rolled section per D2) for `gh release create`;
  (e) pushes commit + tag and publishes when the remote is enabled, or SKIPS both
  under `--no-remote`. Exercised only against scratch repos / stubs, never the
  real upstream.
- Verification: TEST-003..008 (incl. SEAM-1 notes-equals-rolled-section
  integration test TEST-006 and idempotence TEST-008).

- Maps to: intake AC-003 (fail-closed preconditions, zero writes on refusal)
- Spec-AC-03: the script refuses with a clear message and makes ZERO writes on
  each D6 precondition — dirty tree; empty unreleased; absent unreleased;
  existing tag for the resolved version; `gh` absent/unauthenticated on the
  publish path (dry-run still works offline); not a git repo; no CHANGELOG.md;
  and a MALFORMED unreleased region (never silently drops entries).
- Verification: TEST-009..015 — each asserts non-zero exit and a byte-identical
  tree (CHANGELOG sha256 unchanged, no new commit/tag).

- Maps to: intake AC-004 (portable + generic)
- Spec-AC-04: `bash -n` parses; no BSD-only constructs (no `mktemp -t <bare>`, no
  `stat -f`-first); version resolves from `--version <v>` verbatim else CalVer
  `vYYYY.MM.DD` (pinnable via `AAI_RELEASE_DATE`); the script makes no
  AAI-repo-specific assumptions (runs in a non-`.aai` scratch repo); a `.ps1`
  parity twin exists exposing the same flags.
- Verification: TEST-016 (parse + BSD-construct grep), TEST-017 (version
  resolution incl. `AAI_RELEASE_DATE` pin), TEST-018 (generic non-AAI repo cut),
  TEST-019 (ps1 flag parity).

- Maps to: intake AC-005 (layer integrity)
- Spec-AC-05: the three new `.aai/**` files are classified `core` in
  PROFILES.yaml (layer-profiles suite green); `tests/skills/test-aai-release.sh`
  exists and is green on the Linux CI skill-suite gate; `docs/USER_GUIDE.md` and
  `CHANGELOG.md` document `/aai-release`.
- Verification: TEST-020 (SEAM-2 layer-profiles union==tree), TEST-021 (docs
  grep). The whole `test-aai-release.sh` suite passing on Ubuntu (the enforced
  `skill-suite` CI job) is the green-on-Linux evidence.

## Constitution deviations

None.

<!-- All 7 articles checked against this scope: Art.1 evidence — the suite
  provides executable evidence; Art.2 simplicity — mirrors the existing
  aai-update script pattern, no speculative features; Art.3 portability — sh+ps1
  tri-platform, plain files; Art.4 degrade-and-report — gh absent → clear
  publish refusal, dry-run works offline; Art.5 additive-first — all new files,
  no breaking edits to public boundaries; Art.6 single-writer STATE — STATE.yaml
  is not touched; Art.7 operator-only merge — the cut is operator-gated
  (--confirm), the agent never auto-publishes (reinforces the article). No
  canonical requirements change and docs/canonical/ is empty, so no ## Deltas
  section. -->

## Acceptance Criteria Status

| Spec-AC    | Description                                                     | Status  | Evidence | Review-By | Notes |
|------------|-----------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Dry-run / bare invocation is default-safe: prints plan, zero writes, exit 0 | done | TEST-001/002 green — `bash tests/skills/test-aai-release.sh` exit 0; docs/ai/tdd/green-20260720T083215Z-full-suite.log | — | — |
| Spec-AC-02 | Confirm cut: rolls CHANGELOG, commits, annotated tag, notes, push/publish (gated) | done | TEST-003..008 green — same suite/log; SEAM-1 (TEST-006) verified notes body == rolled section via stub gh | — | — |
| Spec-AC-03 | Fail-closed precondition matrix — refuse with zero writes       | done | TEST-009..015 green — same suite/log | — | — |
| Spec-AC-04 | Portable (sh+ps1, no BSD-only) + generic version resolution     | done | TEST-016..019 green — same suite/log; `aai-release.ps1` parses clean under pwsh | — | — |
| Spec-AC-05 | Layer integrity — PROFILES core, suite green on Linux, docs     | done | TEST-020/021 green — same suite/log; `bash tests/skills/test-aai-layer-profiles.sh` exit 0 (core=118); `grep -n "/aai-release" docs/USER_GUIDE.md CHANGELOG.md` non-empty | — | CI (Ubuntu) run pending on PR push — RR-1 residual (real `gh release create`/`git push` to github.com not exercised, only local/stub seams) |

## Implementation plan
- Components/modules affected:
  - `.aai/scripts/aai-release.sh` — the deterministic cut engine (D1–D8).
  - `.aai/scripts/aai-release.ps1` — PowerShell parity twin (same flags/behavior).
  - `.aai/SKILL_RELEASE.prompt.md` — thin-wrapper prompt (D9).
  - `.claude/skills/aai-release/SKILL.md`, `.codex/skills/aai-release/SKILL.md`,
    `.gemini/skills/aai-release/SKILL.md` — 3-agent-tree wrappers (D9).
  - `.aai/system/PROFILES.yaml` — 3 core classifications (D10).
  - `tests/skills/test-aai-release.sh` — Linux-portable bash-3.2 suite.
  - `docs/USER_GUIDE.md` (Skills Catalog) + `CHANGELOG.md` — document `/aai-release`.
- Data flows: CHANGELOG `[unreleased]` blocks → (rollup) → `[<version>]` blocks +
  fresh scaffold → (extract) → release notes → `gh release create`. The rolled
  CHANGELOG section is the single source for the notes (SEAM-1).
- Edge cases: multiple stacked unreleased blocks (34 today); already-released
  headings must never re-transform; malformed unreleased region must fail-closed;
  SemVer `--version` (no date in heading); `AAI_RELEASE_DATE` pin; both
  `--confirm --dry-run` (dry-run wins); gh unauth vs absent; empty scaffold-only
  re-run (idempotent refusal); dirty tree; existing tag; non-AAI target repo.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)              | Description | Status |
|----------|------------|-------------|-----------------------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-release.sh  | `--dry-run` in seeded scratch repo prints version+rollup+tag+notes preview, exit 0, `git status` clean, no tag/commit | green |
| TEST-002 | Spec-AC-01 | integration | tests/skills/test-aai-release.sh  | Bare invocation (no `--confirm`, no `--dry-run`) is plan-only: zero writes, exit 0 (default-safe) | green |
| TEST-003 | Spec-AC-02 | integration | tests/skills/test-aai-release.sh  | `--version vX --confirm --no-remote` rolls CHANGELOG: all `[unreleased] — …`→`[vX] — …`, block bodies byte-preserved (sha), bare `## [unreleased]` scaffold on top | green |
| TEST-004 | Spec-AC-02 | integration | tests/skills/test-aai-release.sh  | Commit is `chore(release): vX` and stages ONLY CHANGELOG.md (`git show --stat` = one path) | green |
| TEST-005 | Spec-AC-02 | integration | tests/skills/test-aai-release.sh  | Annotated tag `vX` created (`git cat-file -t vX` == `tag`) | green |
| TEST-006 | Spec-AC-02 | integration | tests/skills/test-aai-release.sh  | SEAM-1: notes body handed to stubbed `gh release create --notes-file` equals the just-rolled CHANGELOG section (title=`vX`) | green |
| TEST-007 | Spec-AC-02 | integration | tests/skills/test-aai-release.sh  | Remote arm — stub `gh` + local `file://` bare remote: push + `gh release create` are ATTEMPTED (stub records); `--no-remote` arm asserts both SKIPPED | green |
| TEST-008 | Spec-AC-02 | integration | tests/skills/test-aai-release.sh  | Idempotence — re-run same cut after a successful roll refuses (scaffold-only ⇒ EMPTY), zero further writes | green |
| TEST-009 | Spec-AC-03 | integration | tests/skills/test-aai-release.sh  | Dirty tree → confirm cut refuses, exit ≠0, CHANGELOG sha unchanged, no commit/tag | green |
| TEST-010 | Spec-AC-03 | integration | tests/skills/test-aai-release.sh  | Empty unreleased (scaffold-only) → refuse, zero writes | green |
| TEST-011 | Spec-AC-03 | integration | tests/skills/test-aai-release.sh  | Absent unreleased (no `## [unreleased]` heading) → refuse, zero writes | green |
| TEST-012 | Spec-AC-03 | integration | tests/skills/test-aai-release.sh  | Existing tag for resolved version → refuse, zero writes | green |
| TEST-013 | Spec-AC-03 | integration | tests/skills/test-aai-release.sh  | `gh` absent/unauth on publish path (remote enabled) → refuse BEFORE any write (CHANGELOG sha unchanged, no commit/tag); dry-run still exits 0 offline | green |
| TEST-014 | Spec-AC-03 | integration | tests/skills/test-aai-release.sh  | Not a git repo → refuse zero writes; and no CHANGELOG.md → refuse zero writes | green |
| TEST-015 | Spec-AC-03 | integration | tests/skills/test-aai-release.sh  | Malformed unreleased region (bare scaffold WITH body content) → refuse, zero writes (never silently drop) | green |
| TEST-016 | Spec-AC-04 | unit/static | tests/skills/test-aai-release.sh  | `bash -n aai-release.sh` parses; grep asserts no `mktemp -t <bare>` and no `stat -f`-first (LEARNED 2026-07-19) | green |
| TEST-017 | Spec-AC-04 | integration | tests/skills/test-aai-release.sh  | Version resolution: `AAI_RELEASE_DATE=2026-07-20` (no `--version`) ⇒ `v2026.07.20`; `--version v1.2.3` ⇒ `v1.2.3` (clock not consulted) | green |
| TEST-018 | Spec-AC-04 | integration | tests/skills/test-aai-release.sh  | Generic — scratch repo with NO `.aai/` layer (only root+CHANGELOG+git) cuts successfully (`--confirm --no-remote`) | green |
| TEST-019 | Spec-AC-04 | static      | tests/skills/test-aai-release.sh  | ps1 parity — `.aai/scripts/aai-release.ps1` exists and exposes the same flags (dry-run/version/confirm/no-remote) as the bash script | green |
| TEST-020 | Spec-AC-05 | integration | tests/skills/test-aai-release.sh  | SEAM-2: `./tests/skills/test-aai-layer-profiles.sh` exits 0 with the 3 new `.aai/**` files classified core (union==tree) | green |
| TEST-021 | Spec-AC-05 | integration | tests/skills/test-aai-release.sh  | Docs — grep proves `docs/USER_GUIDE.md` (Skills Catalog) AND `CHANGELOG.md` document `/aai-release` | green |

Notes:
- Every Spec-AC has ≥1 TEST-xxx entry. RED-proof obligation: every AC-gating test
  is observed FAILING (against the absent/stub engine) before its GREEN counts —
  including the loop-strategy wiring rows (a test never seen failing proves nothing).
- Test IDs are stable — do not renumber after freeze.
- Test-harness safety seam (frozen): scratch repos are created under
  `mktemp -d "${TMPDIR:-/tmp}/aai-release-test.XXXXXX"` (FULL template — GNU/BSD
  portable), each `git init -b main`, self-seeds a CHANGELOG + `git config`
  user.name/email locally + an initial commit; `gh` is stubbed by a fake
  executable prepended to PATH that records its args; push (when exercised)
  targets a local `file://` bare remote in the temp dir — NEVER the real
  upstream. The suite MUST NOT publish a real release or push to `origin`.
  bash-3.2 compatible; run via `.aai/scripts/aai-run-tests.sh`.

## Seam analysis
- SEAM-1 (CHANGELOG ↔ release-notes): the rolled CHANGELOG section is consumed by
  `gh release create` as the notes body. Covered end-to-end by TEST-006 — produce
  the roll on the CHANGELOG side, assert the exact bytes arrive at the stubbed
  `gh --notes-file` on the release side (not two mocks of the boundary).
- SEAM-2 (script ↔ PROFILES.yaml ↔ CI layer-profiles gate): the new `.aai/**`
  files must be classified or the `layer-profiles` conformance suite (union ==
  live tree) goes red. Covered by TEST-020 against the LIVE tree after the files
  land.
- Residual risks (no automated coverage possible):
  - RR-1: a real `gh release create` + `git push` to github.com cannot be
    exercised in CI without an outward-facing side effect; only the `--no-remote`
    / stubbed-`gh` / local-`file://`-remote seam is automated. The true
    end-to-end publish is validated manually by the operator on first dogfood
    (per the intake's dogfooding note).
  - RR-2: PowerShell FUNCTIONAL parity is not exercised by the bash suite (only
    `.ps1` parse via the `ps1-quality` workflow + static flag-parity grep
    TEST-019); real pwsh functional parity is manual / optional Pester.

## Verification
- Commands:
  - `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-release.sh` → exit 0
    (all 21 tests green; the enforced `skill-suite` CI job runs this on Ubuntu —
    the green-on-Linux evidence for Spec-AC-05/AC-04).
  - `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-layer-profiles.sh`
    → exit 0 (new files classified core, SEAM-2).
  - `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0063-spec-aai-release-skill.md`
    → structural findings report-only.
- PASS criteria: all TEST-xxx in status green AND all Spec-AC in a terminal status
  with non-empty Evidence.

## Evidence contract
Per artifact record: ref_id (`aai-release-skill`); the Spec-AC + TEST-xxx links;
the command or review scope; exit code / review verdict; evidence path (test log
under docs/ai/, CI run URL for the Linux skill-suite gate); commit SHA / diff
range when available.
