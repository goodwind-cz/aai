---
id: spec-sync-deletes-target-only-hooks
type: spec
number: null
status: implementing
frozen_sha256: 230ebc5e27937b2e301ef66a9fcec7942e97fada0aeb5210662d8759ffc9b043
ceremony_level: 2
links:
  requirement: docs/issues/ISSUE-DRAFT-sync-deletes-target-only-hooks.md
  rfc: null
  pr: []
  commits: []
---

# Spec — aai-sync preserves target-only hooks and reports its deletions

SPEC-FROZEN: true

## Links
- Requirement / intake: docs/issues/ISSUE-DRAFT-sync-deletes-target-only-hooks.md
- Upstream report: https://github.com/goodwind-cz/aai/issues/414 (pin v2026.09.30, commit beb6a248)
- Decision records: none
- Technology contract: docs/TECHNOLOGY.md

## Measured current behaviour (pre-change, this session)

Every claim below was re-measured against the tree at `beb6a248`, not taken
from the intake.

1. `.aai/scripts/aai-sync.sh:548-552` — `hooks/` is copied with
   `copy_replace "$SRC_ROOT/hooks" "$DST_ROOT/hooks"`.
2. `.aai/scripts/aai-sync.sh:146-152` — `copy_replace` is `rm -rf "$dst"`
   then `cp -a "$src" "$dst"`. Target-only content under `hooks/` is therefore
   destroyed by construction.
3. `.aai/scripts/aai-sync.ps1:557-562` — the PowerShell engine has the same
   shape: `Copy-Replace $hooksDir (Join-Path $TargetRoot "hooks")`. The defect
   is cross-engine.
4. Reproduction (scratch fixture, real engine, no network): a target carrying
   `hooks/merge-guard.sh` plus a marker line appended to `hooks/hooks.json` was
   synced once. Result: `merge-guard.sh` absent after the run, marker count in
   `hooks/hooks.json` = 0, stdout line `  SYNC hooks/` and no `PRESERVE` line
   for `hooks/`.
5. The advisory produced by that same run named `.codex/skills/` and
   `.gemini/skills/` and nothing about `hooks/` — six lines of unrelated
   overwrite noise while the safety control was being removed.
6. `.aai/scripts/aai-sync.sh:741-751` — the advisory is generated from the
   single `OVERWRITE_CONFLICTS` array, under the heading
   "The following target files/directories had local content that differed
   from sync source and were overwritten." There is no deletions array.
   `aai-sync.ps1:781-802` is the same generator in PowerShell.
7. `.aai/scripts/aai-sync.sh:742` — the advisory is written only when
   `${#OVERWRITE_CONFLICTS[@]} -gt 0`. Measured consequence: a second sync of
   the same fixture with `.aai/zz-target-only/` present printed
   `CLEAN removed stale: .aai/zz-target-only`, deleted the directory, and
   wrote NO advisory at all. A purely destructive run is currently silent.
8. The precedent for the fix is in the same script: `.aai/scripts/`
   (`aai-sync.sh:360-372`) and `.claude/skills` (`aai-sync.sh:377-395`) both do
   a file-by-file merge and log `PRESERVE target-only ...`.
9. `aai-sync.sh` calls `node` zero times (`grep -n 'node ' .aai/scripts/aai-sync.sh`
   returns nothing). The sync engine has no JSON parser and no Node dependency.
10. `tests/skills/test-aai-layer-profiles.sh:121-129` — `tree_manifest`
    excludes `docs/ai/reports/*`, so a new advisory file cannot break the
    byte-identity (TEST-002) or prune-idempotence (TEST-004) assertions there.

## Scope decision — the JSON-registration half

The reporter lost two different things: three target-only FILES under `hooks/`,
and a target-added `PreToolUse` -> `Bash` registration block inside the
SOURCE-OWNED `hooks/hooks.json` and `hooks/hooks.windows.json`.

**Decision: the file half is fixed here; merging target-added ENTRIES inside
the source-owned hook JSONs is OUT of scope and split to a follow-up. This
hotfix instead makes that loss VISIBLE, which it is not today.**

Justification:

1. The two halves are different problems. The file half is the existing,
   twice-precedented file-by-file merge idiom applied to one more directory
   (evidence 8). The JSON half is a structural merge of a source-owned
   document with target-added entries.
2. The sync engine cannot parse JSON. It has no Node dependency at all
   (evidence 9) and runs at bootstrap time, before any project tooling is
   assumed. Adding one would either take a hard `node` dependency inside the
   installer or hand-roll JSON merging in `awk` in two languages. Choosing
   between those is a design decision, not a hotfix.
3. The merge SEMANTICS are undecided and cannot be guessed: what identifies a
   "target-added" entry across re-syncs, what happens when source and target
   register the same event plus matcher, how the result stays byte-idempotent,
   and how the `.sh` and `.ps1` engines are proven to produce the same bytes.
4. Shipping the file half alone already returns the safety-critical majority of
   the reported damage: the three `merge-guard.*` scripts survive, and the
   manual workaround shrinks from five paths to two.
5. Coupling a two-lines-per-engine fix to that design would delay the
   file-preservation fix for every downstream project that syncs.

What this hotfix DOES owe the JSON half, and delivers (Spec-AC-04): today the
two JSONs are overwritten with no advisory entry whatsoever (evidence 5). This
scope adds them to `OVERWRITE_CONFLICTS` whenever the target copy differs, with
a recommendation that names the registration loss by name. The loss stops being
silent, which is exactly the intake's second requirement — "any destructive
sync action has a review surface even where preserve does not apply."

Follow-up to file at close (suggested, not yet filed):
`fu-hooks-json-target-entries-lost` (P2) — a target-added registration inside
`hooks/hooks.json` / `hooks/hooks.windows.json` is still overwritten; the
advisory now names it, but nothing merges it back.

## Scope decision — how "target-only, keep" is told from "source removed it, drop it"

**Decision: the source-owned set for `hooks/` is the set of entries present in
the SOURCE `hooks/` tree at sync time. Everything else in the target's `hooks/`
is target-only and is preserved. A hook the source deliberately retires is
disarmed by the overwritten REGISTRATION, not by deleting its file.**

Mechanism, stated so it can be tested (Spec-AC-08): a hook only runs when a
source-owned `hooks/hooks.json` or `hooks/hooks.windows.json` entry invokes it.
Those two JSONs stay source-owned and are still overwritten wholesale by this
spec. So when the source retires `foo.sh`, the source's registration for it
disappears from the target on the next sync and the hook stops firing, even
though the target's copy of `foo.sh` lingers as an inert orphan.

Why no tombstone or retirement manifest:

- It is the rule `.aai/scripts/` and `.claude/skills` have used since the merge
  branch existed (evidence 8). Neither can retire a file either, and no defect
  has been filed against either in that time. Giving `hooks/` a retirement
  mechanism that the two precedent directories do not have would make `hooks/`
  the inconsistent one.
- A retirement list would be a new vendored `.aai/**` file plus a reader in two
  languages plus a `PROFILES.yaml` classification, and it would ship EMPTY —
  nothing is retired today. Constitution article 2 (YAGNI) rules it out until a
  requirement exists.
- The safety property the intake is actually protecting is "a stale hook must
  not keep firing". Deregistration delivers that. Deletion of the file is
  cosmetic by comparison.

Honest residual, stated rather than hidden: the intake's wording is "a stale
hook the source deliberately removed must still disappear", and after this
change its FILE does not disappear — it is disarmed and left on disk. If the
owner wants literal deletion, that is a tombstone mechanism and a separate
scope.

## Scope decision — what feeds the new deletions category

Deletions are recorded at every site where this engine deletes content in the
target `.aai` tree: `CLEAN removed stale` (`aai-sync.sh:353-357`) and
`PROFILE prune (not in core)` (`aai-sync.sh:336-338`), plus any deletion the
new `hooks/` merge performs. The profile prune is included rather than filtered
so that the rule stays "every deletion this engine performs is listed", with no
judgement call for a future reader to re-litigate. Measured: a prune only fires
on an extended-to-core downgrade or on genuinely stale files, and a repeated
core sync is idempotent (`test-aai-layer-profiles.sh:509-537`), so the advisory
does not grow on steady-state runs.

Disclosed residual (not wired here): `copy_replace` on a DIRECTORY still does
`rm -rf` for `.codex/skills`, `.gemini/skills` and each `.claude/skills/<entry>`,
so target-only files under those three surfaces are still destroyed and are not
routed into the deletions category. Follow-up to file at close (suggested):
`fu-sync-rmrf-dirs-outside-deletions` (P3).

## Implementation strategy
- Strategy: direct
- Rationale: recorded at intake by the owner (`docs/ai/STATE.yaml`
  `implementation_strategy.source: intake`, `ref_id:
  sync-deletes-target-only-hooks`) — implement first, then targeted regression
  tests. Planning does NOT override a recorded human choice. Planning's own
  assessment agrees: the change is a small, twice-precedented edit to an
  existing idiom, and the RED observation is already recorded above as
  evidence 4, 5 and 7 from the pre-change tree.

Evidence this spec may demand under `direct` (see the template's
`### Evidence by strategy`): targeted regression tests green with exit codes,
plus the scoped diff. No stored RED artifact is required and none is demanded
below.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: the change edits the installer every downstream project
  runs, in two languages, and the regression suites run the real engine against
  the LIVE tree (`test-aai-layer-profiles.sh:33` reads
  `$PROJECT_ROOT/.aai/scripts/aai-sync.sh`). An isolated tree keeps a
  half-applied engine out of any other session's sync. Not `required`: the sync
  engine is not in `protected_paths_l3`.
- User decision: undecided — the `worktree` block in STATE currently holds a
  STALE decision from ride `original-request-outcome-backcheck` (branch
  `feat/original-request-outcome-backcheck`, a path that no longer exists per
  `git worktree list`). Implementation Preparation must re-ask; the returned
  `set-worktree` command resets it to `undecided`.
- Base ref: main (`beb6a248`)
- Worktree branch/path: to be decided by Implementation Preparation
- Inline review scope: if inline is chosen — `.aai/scripts/aai-sync.sh`
  `.aai/scripts/aai-sync.ps1` `tests/skills/test-aai-sync-seed.sh`
  `docs/specs/SPEC-DRAFT-spec-sync-deletes-target-only-hooks.md`
  `docs/issues/ISSUE-DRAFT-sync-deletes-target-only-hooks.md` `CHANGELOG.md`

## Acceptance Criteria Mapping

- Spec-AC-01 — WHEN a sync runs against a target holding a file under `hooks/`
  that the source `hooks/` does not contain, the engine SHALL leave that file
  in place byte-identical.
  Verification: create a fixture target, write `hooks/merge-guard.sh`, record
  its bytes, run `bash .aai/scripts/aai-sync.sh <target>`, then
  `cmp <recorded> <target>/hooks/merge-guard.sh` exits 0.
  Evidence: the fixture path, the sync stdout, the `cmp` exit code.

- Spec-AC-02 — WHEN the engine preserves a target-only entry under `hooks/`,
  it SHALL print one stdout line naming that entry's path relative to the
  target root.
  Verification: the same run's stdout contains the literal
  `PRESERVE target-only hook: hooks/merge-guard.sh`
  (`grep -qF` exits 0). A blanket directory-level line like the
  `.claude/skills` one does NOT satisfy this AC — the intake requires the file
  to be named.
  Evidence: the captured stdout.

- Spec-AC-03 — WHEN a target's copy of a SOURCE-OWNED hook file differs from
  the source, the engine SHALL replace it with the source bytes, and
  `hooks/session-start.sh` SHALL remain executable afterwards.
  Verification: seed the target's `hooks/session-start.sh` with different
  bytes and `chmod -x` it, sync, then `cmp <src>/hooks/session-start.sh
  <target>/hooks/session-start.sh` exits 0 and `test -x
  <target>/hooks/session-start.sh` exits 0.
  Evidence: both exit codes.

- Spec-AC-04 — WHEN the target's `hooks/hooks.json` or
  `hooks/hooks.windows.json` differs from the source copy, the advisory SHALL
  carry one `- Path:` entry for that file whose `- Recommendation:` text
  contains the word `registration`.
  Verification: append a marker line to the target's `hooks/hooks.json`, sync,
  then in the newest `<target>/docs/ai/reports/sync-conflicts-*.md`
  `grep -qF '- Path: hooks/hooks.json'` exits 0 and the following
  `- Recommendation:` line matches `grep -q 'registration'`.
  Evidence: the advisory file contents.

- Spec-AC-05 — WHEN at least one deletion was performed, the advisory SHALL
  contain a `## Deleted items` section listing one `- Path:` line per deleted
  path, and the advisory SHALL be written even when the overwrite list is
  empty.
  Verification: sync a fixture once, then create
  `<target>/.aai/zz-target-only/x.txt` and sync again; the newest advisory
  exists, `grep -qF '## Deleted items'` exits 0, and
  `grep -qF '- Path: .aai/zz-target-only'` exits 0. Measured pre-change
  baseline for this exact fixture: no advisory file at all (evidence 7).
  Evidence: the advisory file contents and the sync stdout.

- Spec-AC-06 — WHEN a run performs no deletion and triggers no new-in-this-scope
  overwrite entry, the advisory SHALL be byte-identical to the one the
  pre-change engine writes for the same inputs, except for the
  `- Generated at (UTC):` line.
  Verification: build one fixture SOURCE tree; copy it twice, swapping only
  `.aai/scripts/aai-sync.sh` for the pre-change version in one copy; sync both
  into identical fixture targets seeded to produce a non-empty overwrite list,
  no deletion and no hook-JSON divergence; then
  `diff <(grep -v '^- Generated at (UTC):' old_advisory) <(grep -v '^- Generated at (UTC):' new_advisory)`
  produces no output and exits 0. No empty `## Deleted items` heading appears,
  and the existing section order is unchanged.
  Scope note, stated because it deviates from the intake's literal phrasing:
  the intake asks for byte-identity on any run with no deletions. Spec-AC-04 is
  itself an intake requirement and DOES add an overwrite entry for a diverging
  hook JSON, so byte-identity is asserted for inputs that trigger neither a
  deletion nor a hook-JSON divergence. That is the guard the intake bullet
  exists for — it protects quiet runs from the advisory change.
  Evidence: the two advisory files and the diff exit code.

- Spec-AC-07 — The PowerShell engine `aai-sync.ps1` SHALL exhibit the
  behaviours of Spec-AC-01, Spec-AC-02, Spec-AC-04 and Spec-AC-05.
  Verification: when `pwsh` is on PATH, run
  `pwsh -NoProfile -File .aai/scripts/aai-sync.ps1 <target>` over the same
  fixtures and assert the same four observables. When `pwsh` is absent, the
  suite sets its documented `PWSH_ARM_SKIPPED` flag and exits 42 rather than
  reporting a full pass (existing discipline,
  `tests/skills/test-aai-sync-seed.sh:42-51`).
  Evidence: the pwsh run stdout, the preserved file, the advisory file, or the
  recorded skip.

- Spec-AC-08 — WHEN the source no longer ships a hook AND no source-owned
  `hooks/*.json` entry references it, the target's copy of that hook file SHALL
  survive the sync AND the target's `hooks/hooks.json` SHALL be byte-identical
  to the source's, carrying no reference to it.
  Verification: seed the target with `hooks/retired-hook.sh` (absent from
  source), sync, then `test -f <target>/hooks/retired-hook.sh` exits 0,
  `cmp <src>/hooks/hooks.json <target>/hooks/hooks.json` exits 0, and
  `grep -c retired-hook <target>/hooks/hooks.json` reports 0.
  Evidence: the three results. This is the executable statement of the
  retirement decision above — disarmed, not deleted.

- Spec-AC-09 — The four sync-engine suites named by the intake SHALL exit 0 on
  the changed tree.
  Verification: each of
  `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-layer-drift.sh`,
  `... tests/skills/test-aai-layer-profiles.sh`,
  `... tests/skills/test-aai-sync-seed.sh`,
  `... tests/skills/test-aai-bootstrap.sh`
  exits 0 (exit 42 counts only for `test-aai-sync-seed.sh` when `pwsh` is
  absent, per Spec-AC-07).
  Evidence: the four exit codes and stdout tails.

## Constitution deviations

None.

Checked article by article against this scope: (1) evidence before claims — the
pre-change observations above were produced and read in this session, and every
AC names a command and an observable; (2) simplicity — the retirement tombstone
was explicitly rejected as speculative, and the JSON merge is split out;
(3) portability — shell plus PowerShell text edits only, no new dependency, no
binary store, and evidence 9 records that no Node dependency is introduced;
(4) degrade and report — the whole scope is the report side of a silent
degradation, and both residuals are named rather than hidden; (5) additive
first — the `## Deleted items` section appears only when non-empty, and
Spec-AC-06 pins that quiet runs are unchanged; (6) single-writer state — no
STATE write in this scope, and Planning returns its commands to the
orchestrator; (7) operator-only merge — unaffected.

## Acceptance Criteria Status

| Spec-AC    | Description                                                                      | Status  | Evidence | Review-By | Notes                                        |
|------------|----------------------------------------------------------------------------------|---------|----------|-----------|----------------------------------------------|
| Spec-AC-01 | WHEN a sync runs the engine SHALL leave a target-only file under hooks unchanged | planned | —        | —         | precedent: .aai/scripts merge                 |
| Spec-AC-02 | WHEN a target-only hook is preserved the engine SHALL name it on stdout          | planned | —        | —         | per-file line, not a blanket directory line   |
| Spec-AC-03 | WHEN a source-owned hook file differs the engine SHALL overwrite and keep +x     | planned | —        | —         | guards the chmod at aai-sync.sh:551           |
| Spec-AC-04 | WHEN a source-owned hooks JSON differs the advisory SHALL name it                | planned | —        | —         | the visible half of the split-out JSON merge  |
| Spec-AC-05 | WHEN a deletion occurs the advisory SHALL carry a Deleted items section          | planned | —        | —         | advisory now written on deletions alone       |
| Spec-AC-06 | WHEN nothing is deleted the advisory SHALL stay byte-identical to today          | planned | —        | —         | modulo the generated-at line                  |
| Spec-AC-07 | The PowerShell engine SHALL match AC-01, AC-02, AC-04 and AC-05                  | planned | —        | —         | pwsh-absent arm exits 42, never a silent pass |
| Spec-AC-08 | A source-retired hook SHALL survive as a file and carry no registration          | planned | —        | —         | executable form of the retirement decision    |
| Spec-AC-09 | The four named sync suites SHALL exit 0 on the changed tree                      | planned | —        | —         | regression guard for the engine edits         |

## Implementation plan

Components affected:

- `.aai/scripts/aai-sync.sh`
  - Replace the single `copy_replace "$SRC_ROOT/hooks" "$DST_ROOT/hooks"` at
    `:550` with a file-by-file merge modelled on `:360-372`: copy each source
    entry over the target, then walk the target and print
    `PRESERVE target-only hook: hooks/<rel>` for each entry absent from source.
    Keep the `chmod +x` on `session-start.sh`.
  - Before overwriting `hooks/hooks.json` and `hooks/hooks.windows.json`, use
    the existing `file_content_different` helper (`:161-167`, byte compare via
    `cmp`, fail-closed) and append an `OVERWRITE_CONFLICTS` entry whose
    recommendation names the registration loss.
  - Add a `DELETIONS=()` array beside `OVERWRITE_CONFLICTS` (`:144`), append to
    it at `CLEAN removed stale` (`:353-357`) and `PROFILE prune` (`:336-338`).
  - Change the advisory guard at `:742` to fire when EITHER array is non-empty,
    and emit `## Deleted items` after `## Overwritten items` only when
    `DELETIONS` is non-empty.
- `.aai/scripts/aai-sync.ps1` — the same four edits at `:557-562`, `:33`,
  `:781-802` and the prune/clean sites, keeping the two engines' advisory
  output byte-equivalent.
- `tests/skills/test-aai-sync-seed.sh` — the nine new TEST rows below. Chosen
  over the other three suites because it already builds temp targets, runs the
  REAL engines with no network (`:19`), asserts PRESERVED-byte-for-byte
  semantics, and carries the `PWSH_ARM_SKIPPED` exit-42 discipline that
  Spec-AC-07 needs.

Data flows: source tree -> per-entry copy decision -> two in-memory arrays
(`OVERWRITE_CONFLICTS`, `DELETIONS`) -> one advisory file under
`<target>/docs/ai/reports/`.

Edge cases:

- A target `hooks/` subdirectory that the source lacks — the walk must treat it
  as target-only and not descend destructively.
- A target-only entry whose name later appears in the source: the source wins
  from that sync on, which is the same rule `.aai/scripts/` uses.
- `hooks/` absent in the target entirely (fresh install) — the merge must
  `mkdir -p` and behave exactly as the old wholesale copy did.
- A path containing spaces or `[ ]` — the fixture at
  `test-aai-layer-profiles.sh:562` already pins this class for the engine; the
  new loops must quote every expansion.
- Advisory ordering: `## Overwritten items` keeps its position; `## Deleted
  items` is appended after it, so Spec-AC-06's diff sees no reordering.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                | Description                                                                                  | Mutation            | Status  |
|----------|------------|-------------|-------------------------------------|----------------------------------------------------------------------------------------------|---------------------|---------|
| TEST-773 | Spec-AC-01 | integration | tests/skills/test-aai-sync-seed.sh  | target-only hooks/merge-guard.sh survives a real sync byte-identical                          | n/a — direct        | pending |
| TEST-774 | Spec-AC-02 | integration | tests/skills/test-aai-sync-seed.sh  | sync stdout carries PRESERVE target-only hook naming hooks/merge-guard.sh                     | n/a — direct        | pending |
| TEST-775 | Spec-AC-03 | integration | tests/skills/test-aai-sync-seed.sh  | a differing hooks/session-start.sh is replaced by source bytes and stays executable           | n/a — direct        | pending |
| TEST-776 | Spec-AC-04 | integration | tests/skills/test-aai-sync-seed.sh  | a diverging hooks/hooks.json yields an advisory Path entry whose recommendation says registration | n/a — direct    | pending |
| TEST-777 | Spec-AC-05 | integration | tests/skills/test-aai-sync-seed.sh  | a deletion-only re-sync writes an advisory with a Deleted items section naming the path       | n/a — direct        | pending |
| TEST-778 | Spec-AC-06 | integration | tests/skills/test-aai-sync-seed.sh  | old-engine and new-engine advisories match for a quiet run, generated-at line excluded        | n/a — direct        | pending |
| TEST-779 | Spec-AC-07 | integration | tests/skills/test-aai-sync-seed.sh  | pwsh engine preserves, names, flags the JSON and reports deletions; absent pwsh exits 42      | n/a — direct        | pending |
| TEST-780 | Spec-AC-08 | integration | tests/skills/test-aai-sync-seed.sh  | a source-retired hook file survives while hooks.json matches source and names it nowhere      | n/a — direct        | pending |
| TEST-781 | Spec-AC-09 | integration | tests/skills/test-aai-sync-seed.sh  | the four named sync suites exit 0 on the changed tree, recorded as the regression run         | n/a — direct        | pending |

Mutation column note: the Mutation gate applies to `tdd`/`hybrid` specs only
(`spec-lint.mjs` `mutationGateApplicability`). This spec's strategy is
`direct`, recorded at intake by the owner, so no mutation cell is demanded.

## Seams this scope crosses

1. `aai-sync.sh` <-> `aai-sync.ps1`. Two independent implementations of one
   advisory format. Crossed by TEST-779, which runs the PowerShell engine over
   the same fixtures rather than asserting a static text match between the two
   sources.
2. The sync engine <-> the advisory consumer. The advisory is the human review
   surface; a change to its shape is what Spec-AC-06 guards. TEST-778 runs both
   engine versions and diffs real output rather than reasoning about the
   generator.
3. The sync engine <-> `tests/skills/test-aai-layer-profiles.sh`, which runs the
   LIVE engine from `$PROJECT_ROOT` and compares whole trees. Measured: that
   suite's `tree_manifest` excludes `docs/ai/reports/*` (`:121-129`), so the new
   advisory cannot perturb its byte-identity or idempotence assertions.
   TEST-781 keeps that measurement honest.
4. The sync engine <-> `hooks/hooks.json` as a runtime contract read by the
   harness. Spec-AC-08 asserts the registration contract directly rather than
   reasoning about it.
5. Residual seam no automated test in this scope crosses: an actual downstream
   project's `/aai-update` run. The fixtures approximate it; nothing here
   proves the reporter's own tree recovers. That verification belongs to the
   reporter after the release.

## Verification

Commands, run from the repository root:

1. `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-sync-seed.sh`
2. `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-layer-drift.sh`
3. `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-layer-profiles.sh`
4. `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-bootstrap.sh`

Evidence artifacts: the four exit codes and stdout tails; the fixture advisory
files quoted in the validation report; the scoped diff over
`.aai/scripts/aai-sync.sh`, `.aai/scripts/aai-sync.ps1` and
`tests/skills/test-aai-sync-seed.sh`.

PASS criteria: TEST-773..TEST-781 green (TEST-779 may record the documented
pwsh skip) AND every Spec-AC in a terminal status.

## Evidence contract

- ref_id: `sync-deletes-target-only-hooks`
- Spec-AC and TEST links: as mapped in the Test Plan table above
- Command or review scope: the four commands under `## Verification`; review
  scope is the three changed files plus this spec, the intake and `CHANGELOG.md`
- Exit code or review verdict: recorded per command
- Evidence path: the validation report under `docs/ai/reports/`
- Commit SHA or diff range: recorded at hand-off

Under strategy `direct` this spec demands targeted regression tests green with
exit codes plus the scoped diff. It does NOT demand a stored RED artifact and
does not demand a verification matrix beyond the four commands listed above.

## Registry items closed by this scope

none — `node .aai/scripts/follow-ups.mjs list` reports no open item whose
subject is the sync engine's `hooks/` handling or the conflict advisory.

## Companion obligations

Both entries of the closed list in `.aai/PLANNING.prompt.md` were checked and
neither applies:

- Prompt corpus: this scope adds no bytes to `.aai/*.prompt.md` or
  `.aai/AGENTS.md`, so no prompt-diet ledger true-up and no TEST-012 bump.
- New `.aai/**` file: none. The rejected retirement manifest was the only
  candidate, and rejecting it is what keeps `.aai/system/PROFILES.yaml`
  untouched.

## Residual risks

1. The JSON-registration half stays broken until the follow-up lands. The
   advisory names it from this release on; it does not repair it.
2. A source-retired hook's FILE lingers in the target. It is disarmed, not
   deleted. Stated as a decision above, not discovered later.
3. `.codex/skills`, `.gemini/skills` and each `.claude/skills/<entry>` are still
   replaced wholesale, so target-only files there are still destroyed and are
   not in the deletions category.
4. Nothing in this scope proves the reporter's own downstream tree recovers;
   the fixtures approximate their setup.
