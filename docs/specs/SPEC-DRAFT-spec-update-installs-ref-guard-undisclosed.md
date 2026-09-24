---
id: spec-update-installs-ref-guard-undisclosed
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: 374b28276233adfdce5bf2fd76408763be2d7e301cc3700ce2e691ed59db4909
ceremony_level: 2
links:
  requirement: docs/issues/ISSUE-0083-update-installs-ref-guard-undisclosed.md
  rfc: null
  pr: []
  commits: []
---

# Spec — a consumer learns that its git behaviour is about to change, and may say no in a way a machine can read

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/ISSUE-0083-update-installs-ref-guard-undisclosed.md
- Paired maintenance half: docs/issues/ISSUE-0047-agents-tree-not-synced.md
- Mandate: docs/project-sessions/2026-09-13-wave-3-subsystem-sweeps.md (sweep 5)
- Roadmap: docs/ai/roadmap.yaml (`update-installs-ref-guard-undisclosed` paired
  with `agents-tree-not-synced`, status `planned`)
- The decision this scope delivers, never reopens:
  docs/specs/SPEC-0156-spec-agent-shell-can-write-the-shipping-repo.md (D1/D3)
- Sweep 4 (merged, the model for this one):
  docs/specs/SPEC-0182-spec-close-ceremony-sweep.md
- Mutation gate: docs/specs/SPEC-0181-spec-mutation-gate-for-tests.md
- Technology contract: docs/TECHNOLOGY.md
- Ceremony table: .aai/workflow/WORKFLOW.md "Ceremony levels"
- Upstream report: GitHub `goodwind-cz/aai#369`

## Implementation strategy
- Strategy: tdd
- Rationale: every acceptance criterion here is either a REFUSAL (an installer
  that must decline a slot it was not asked to touch, a reader that must not
  read a typo as a decline, a release fallback that must report instead of
  dying) or a DISCLOSURE (a line of output that must exist and be true). Both
  shapes pass trivially when they are absent — an installer that installs
  everything satisfies "installs the index hook", and a category that WARNs
  satisfies nothing. A green run of such a control is not evidence, so every
  Test Plan row carries the mutation that must redden it and the RED is
  recorded before the fix.

## Isolation and review
- Worktree recommendation: required
- Worktree rationale: this scope edits `install-pre-commit-hook.sh`, which
  writes into the effective git hooks path of the tree it runs in, and
  `aai-release.sh`, whose fallback moves branches. A half-applied edit in the
  shared checkout does not fail a test; it changes what git does for every
  concurrent session in that checkout.
- User decision: worktree
- Base ref: main (f84f84ab)
- Worktree branch/path: feat/update-installs-ref-guard-undisclosed at
  /Users/ales/Projects/aai-feat-ref-guard-sweep
- Inline review scope: not applicable (worktree)
- Code review: required. Scope is the branch diff against main f84f84ab.

## Ceremony level

Level 2. Verified, not assumed: `protected_paths_l3` in docs/ai/docs-audit.yaml
lists `state.mjs`, `lib/state-engine.mjs`, `lib/state-core.mjs`,
`allocate-doc-number.mjs`, `pre-commit-checks.sh`, `pre-commit-checks.ps1`,
`.aai/workflow/WORKFLOW.md` and `docs/CONSTITUTION.md`. Not one file this scope
edits is on that list — `install-pre-commit-hook.sh`, `aai-doctor.mjs`,
`lib/guard-config.mjs`, `aai-sync.sh`, `aai-release.sh` and
`SKILL_UPDATE.prompt.md` are all outside it. The merge is nevertheless an
OWNER action under the wave-3 mandate, because the change is consumer-visible
git behaviour; that is a merge-authorization fact, not a ceremony level.

## What is established before this scope starts

Measured against the tree at f84f84ab, under plain bash with `/usr/bin/grep`.
Each fact below is re-measurable by the command named with it.

1. **The installer has no per-hook selection.** `install-pre-commit-hook.sh`
   accepts exactly `--force`, `--uninstall`, `--print`, `-h/--help`; anything
   else exits 2. Installing the docs-index hook without the ref-guard is not
   expressible. The `.ps1` twin accepts exactly `-Force` and `-Uninstall`.
2. **`--print` covers one of the two hooks.** Its awk extraction targets the
   `$HOOK_PATH` heredoc only; there is no way to obtain the `AAI:REF-GUARD`
   body at all.
3. **The installer instructs the operator to do what it refuses to make
   possible.** The foreign-hook refusal for the reference-transaction slot
   prints `Pass --force to overwrite, or merge the AAI:REF-GUARD body
   manually.` — and no command in this repository emits that body.
4. **The installer's own `--help` is honest.** It describes both hooks, names
   the `AAI_GIT_WRITE=1` requirement and cites SPEC-0156 D1/D3. The inaccurate
   contract is `.aai/SKILL_UPDATE.prompt.md` step 4, which grants an
   ask-nothing licence and justifies it with one safety property — "it refuses
   to overwrite a foreign pre-commit hook" — written on 2026-08-13 when the
   installer managed one hook. Step 4's own report line calls the result "the
   docs-index pre-commit hook". Fix the prompt; the installer help is already
   right.
5. **CAT-17 has two states where three are needed.** `aai-doctor.mjs` returns
   WARN for an absent guard with no way to express a declared choice. A project
   that deliberately declines is permanently counted in `DOCTOR ISSUES(n)`,
   because `issueCount` counts every WARN and FAIL and excludes only SKIP.
6. **`docs/ai/` is never overwritten by `/aai-update`.** `aai-sync.sh` prints
   `PRESERVE docs/ai/ runtime data` and copies nothing into it, so
   `docs/ai/docs-audit.yaml` is a project-owned file that survives every
   update. `lib/guard-config.mjs` is already the single JS reader of that file,
   and a conformance test (`tests/skills/test-aai-hygiene-pack.sh` test_031)
   already asserts that its thin shell mirrors agree with it.
7. **Three of the six registry items are already fixed in the tree.**
   `fu-agents-tree-not-synced`: `aai-sync.sh` copies `.agents/skills/`
   (lines 522-539, managed-prefix lists at 625 and 703) and `aai-sync.ps1`
   does the same (168, 522-540, 620); `tests/skills/test-aai-sync-seed.sh`
   TEST-022 pins it. `fu-gitignore-crlf-exact-line`:
   `.aai/scripts/lib/gitignore-block.sh` matches against a CR-stripped copy
   (`tr -d "\r"`, line 66); TEST-021 in the same suite pins it.
   `fu-sync-hash-compare-fails-open`: `file_content_different` now gates on
   `cmp` exit 1 only, and the `.ps1` twin's catch arm returns `$false` naming
   the follow-up id — but NO test drives the error path itself; the only pin
   (`test-aai-layer-profiles.sh` TEST-004) asserts a downstream symptom that
   a working `cmp` never produces.
8. **Two of the six are real and unfixed.** `fu-release-fallback-branch-unguarded`:
   `aai-release.sh` lines 528-529 run `git branch` and `git reset -q --hard`
   with no rc check, so under `set -euo pipefail` a D/F-conflicting ref kills
   the script at git's own exit code with no `FALLBACK INCOMPLETE` report; the
   `.ps1` twin routes both through `Invoke-NativeChecked`, which THROWS past
   `$fallbackIncomplete` for the same silence. `fu-routing-file-overwritten-on-update`:
   `.aai/system/MODEL_ROUTING.yaml` is listed in `PROFILES.yaml` `core:`
   (line 203), so `copy_replace` overwrites a consumer's hand-edited routing
   file on every update; the file's own header admits this in prose.
9. **Prompt-diet headroom is 1942 of a 2048 cap**, with
   `JUSTIFIED_GROWTH_BYTES == 35417` (measured:
   `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-prompt-diet.sh`,
   TEST-010 and TEST-012). `.aai/SKILL_UPDATE.prompt.md` is 3015 bytes and its
   step 4 block is 872 bytes.
10. **The home suite already exists.** `tests/skills/test-aai-git-ref-guard.sh`
    globs `install-pre-commit-hook.{sh,ps1}`, `aai-doctor.mjs`,
    `.aai/SUBAGENT_CONTRACT.md` and SPEC-0156; it carries TEST-301..316 and
    TEST-446. Its globs do NOT yet include `lib/guard-config.mjs`,
    `docs/ai/docs-audit.yaml` or `.aai/SKILL_UPDATE.prompt.md`.
11. **The live TEST id band ends at TEST-605** across docs/specs and
    tests/skills (excluding the synthetic TEST-900 in SPEC-0181). This scope
    allocates from TEST-606.

## Decisions

**D1 — The default stays ARMED, and the disclosure is what changes.** Running
the installer with no flags installs both hooks, exactly as today. The reason
is not inertia: SPEC-0156 D1/D3 record that the reference-transaction hook is
the only chokepoint an agent shell cannot route around, and a safeguard whose
default is off is a safeguard that is off. What was actually wrong here was
never the default — it was that the operator learned about it from a refused
commit. So this scope buys disclosure and an exit, and pays for neither with
the default. Concretely: the installer says, at install time, that every
`refs/heads/main` update in this repository will now be refused without
`AAI_GIT_WRITE=1`, and it names the one command that declines. A consumer who
wants the guard does nothing and keeps it; a consumer who does not runs one
command. "Declinable" must not become "easy to lose", and a decline that costs
one deliberate command while the default costs none is the shape that holds.

**D2 — A decline is an act with a record, not a note.** The declared choice is
one column-0 line, `ref_guard: declined`, in `docs/ai/docs-audit.yaml` — the
file this repository already treats as the committed guard-policy surface, that
`lib/guard-config.mjs` already owns as the single JS reader, and that
`/aai-update` provably never overwrites (fact 6). It is written by
`install-pre-commit-hook.sh --decline-ref-guard`, which in the same run removes
an AAI-managed guard if one is present, so the declaration and the world agree
when it returns. It is not hand-written prose in a README and not a state key
in `STATE.yaml` (which is gitignored runtime, wiped by a reset, and single-
writer by Constitution article 6). Being a committed, diffable, column-0 line
means the choice is reviewable in a pull request and readable by both a shell
grep and a JS reader — which is precisely what "a machine can read" has to mean
here.

**D3 — The decline reader fails CLOSED, unlike every other dial in that file.**
`readRefGuardPolicy` returns `armed` for an absent file, an absent key, an
indented or commented key, and any value outside the closed set
`armed | declined`; an invalid value is named on stderr. This inverts the
fail-open discipline the `enforce`/`report-only` dials use on purpose: falling
open there degrades a REPORT, while falling open here would silently disarm a
SAFEGUARD on a typo. The asymmetry is deliberate, it is surprising, and
therefore it is tested (Spec-AC-05) rather than left to a comment.

**D4 — Reality outranks the declaration in CAT-17.** If a guard is actually
armed, CAT-17 reports `PASS armed` whatever the file says; the declaration only
changes what an ABSENT AAI guard means. A declared decline with a foreign
reference-transaction hook in the slot still WARNs — the consumer declined
AAI's guard, not somebody else's hook. Doctor reports what it probed, and the
declaration only answers the question "is this absence a finding?".

**D5 — The manual-merge path must cover both hooks.** This is not symmetry for
its own sake: the installer's foreign-hook refusal already TELLS the operator
to merge the `AAI:REF-GUARD` body by hand (fact 3), and no command emits it.
A control whose remediation text names an impossible action is the same class
of defect as a licence that outlived its justification. `--print <hook>` takes
`index` or `ref-guard`; bare `--print` keeps emitting the index body so
TEST-314 and any downstream muscle memory stay valid (Constitution article 5).
Both bodies are extracted from this script's own heredocs, never copied, so
`--print` can never drift from what `--force` installs.

**D6 — Per-hook selection is a set, not a pair of booleans.**
`--hooks <csv>` over the closed set `index`, `ref-guard`, `all` (default
`all`); an unknown token exits 2 naming the set. The existing both-checked-
before-either-is-written ordering is preserved over the SELECTED set only — a
foreign hook in a slot this run was not asked to touch is not a reason to
refuse. Attestation likewise covers exactly the selected set, so exit 0 keeps
meaning "git will run what I installed". `--uninstall` honours the same
selection. The `.ps1` twin takes `-Hooks` with the same closed set.

**D7 — A consumer's routing file is preserved, loudly.**
`.aai/system/MODEL_ROUTING.yaml` stays in `PROFILES.yaml` `core:` (it must
still ship to a target that has none), but `aai-sync` copies it only when the
target has no copy or a byte-identical one; a differing target copy is kept,
named in a NOTE line and recorded as an OVERWRITE_CONFLICT. The cost is real
and is stated rather than hidden: a consumer who edits the file stops receiving
new shipped tiers, and the NOTE on every single update is how they find out.
That is the degrade-with-NOTE convention, and it beats the current behaviour,
which is silent loss of the edit.

**D8 — Three already-fixed items close on a mutation, not on a reading.** Two
of them (`fu-agents-tree-not-synced`, `fu-gitignore-crlf-exact-line`) already
have pins; this scope proves those pins redden under a named mutation and
closes the items on that record. The third
(`fu-sync-hash-compare-fails-open`) has a FIX but no test of the error path, so
it gets the missing direct arm. "Already fixed" is a claim about the tree; the
sweep's standard is a test a named mutation reddens, and the cheapest honest
way to meet it for a fixed item is to redden its existing pin.

**D9 — Scope boundary.** SPEC-0156's decision is not reopened: the guard stays,
its behaviour is unchanged, and no byte of the installed hook body changes.
The two out-of-scope notes the intake parks (CAT-14's unnamed failing arm,
CAT-08's post-update dirty tree) stay parked and are named here so they are not
read as dropped.

## Constitution deviations

None.

## Acceptance Criteria Mapping

- Spec-AC-01: WHEN `install-pre-commit-hook.sh --hooks index` runs, the system
  SHALL install only the `AAI:INDEX-AUTOGEN` hook and leave the path
  `git rev-parse --git-path hooks/reference-transaction` resolves with no
  AAI-managed file; `--hooks ref-guard` SHALL do the inverse; no flag and
  `--hooks all` SHALL install both; an unknown token SHALL exit 2 naming the
  closed set; `--uninstall --hooks <sel>` SHALL remove only the selected
  hooks. The `.ps1` twin SHALL expose the same `-Hooks` selection.
  Verification: `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-git-ref-guard.sh`
  in a scratch repo fixture, asserting the presence and the ABSENCE of an
  AAI-managed file at each resolved path.

- Spec-AC-02: WHEN a foreign file occupies a slot this run was NOT asked to
  install, the installer SHALL proceed with the selected slot and exit 0; WHEN
  it occupies a SELECTED slot, the installer SHALL refuse and write nothing to
  either slot, and the attestation SHALL cover exactly the selected set.
  Verification: two fixtures per direction; the run's exit code plus a byte
  comparison of both slots before and after.

- Spec-AC-03: `--print ref-guard` SHALL emit the `AAI:REF-GUARD` hook body
  extracted from this script's own heredoc, byte-identical to what
  `--hooks ref-guard` installs; `--print index` and bare `--print` SHALL emit
  the index body; none of the three SHALL write anything; and the foreign
  reference-transaction refusal message SHALL name the exact command that
  produces the body it instructs the operator to merge.
  Verification: `diff` between the `--print ref-guard` stdout and the installed
  file, plus a grep of the refusal text for the command, plus running that
  command and asserting exit 0 and the marker.

- Spec-AC-04: WHEN the ref-guard is newly installed, the installer SHALL print
  a disclosure naming that a `refs/heads/main` update in this repository is now
  refused unless `AAI_GIT_WRITE=1` is set on that command, and naming the
  decline command; and `--help` SHALL document `--hooks`, its closed set,
  `--print <hook>` and `--decline-ref-guard`.
  Verification: grep of the install stdout and of `--help` for each token.

- Spec-AC-05: `install-pre-commit-hook.sh --decline-ref-guard` SHALL write the
  column-0 line `ref_guard: declined` into `docs/ai/docs-audit.yaml` (creating
  the file when absent), SHALL remove an AAI-managed reference-transaction hook
  when present, SHALL refuse to remove a foreign one, and SHALL be idempotent —
  a second run exits 0 and leaves the file byte-identical.
  `--arm-ref-guard` SHALL set the same key to `armed` and install the guard,
  leaving exactly one `ref_guard:` line.
  Verification: byte comparison of the config across two runs, `grep -c` of the
  key, and the resolved hook path's state after each run.

- Spec-AC-06: `lib/guard-config.mjs` SHALL export `readRefGuardPolicy(dir)`
  over the closed vocabulary `armed` and `declined`, returning `armed` for an
  absent file, an absent key, an indented key, a commented key and any
  out-of-vocabulary value, naming an out-of-vocabulary value on stderr; and the
  installer's thin shell grep SHALL agree with it on the same fixture set.
  Verification: a unit table of six fixtures against the reader, plus the
  existing conformance harness in `tests/skills/test-aai-hygiene-pack.sh` fed
  the same fixtures.

- Spec-AC-07: WHEN `ref_guard: declined` is declared and no AAI-managed guard
  is present, CAT-17 SHALL report a declined state that `DOCTOR ISSUES(n)` does
  NOT count and that names the config path and the re-arm command, and
  `aai-doctor --strict` SHALL exit 0 when that is the only category that would
  otherwise have WARNed; WHEN a guard IS armed, CAT-17 SHALL report PASS armed
  regardless of the declaration; WHEN a foreign reference-transaction hook
  occupies the slot, the declaration SHALL NOT suppress the existing WARN; and
  with no declaration the current WARN text SHALL be unchanged.
  Verification: four `aai-doctor --root <fixture>` runs, asserting the CAT-17
  line, the `DOCTOR` summary count and the exit code of each.

- Spec-AC-08: `.aai/SKILL_UPDATE.prompt.md` step 4 SHALL name both installed
  hooks, SHALL name the ref-guard's effect on `refs/heads/main` and the
  `AAI_GIT_WRITE=1` requirement, SHALL name the decline command, and its stated
  safety property SHALL be scoped to cover both hooks rather than the
  pre-commit hook alone; and the measured byte delta SHALL be credited 1:1 in
  `tests/skills/lib/prompt-diet-ledger.sh` with the TEST-012 `want_growth` pin
  bumped by exactly that number.
  Verification: grep of step 4 for each required token and for the ABSENCE of
  the pre-commit-only safety sentence, plus
  `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-prompt-diet.sh`
  green with TEST-010 headroom still inside the cap.

- Spec-AC-09: `aai-sync` SHALL keep a target's `.aai/system/MODEL_ROUTING.yaml`
  byte-identical when it differs from the shipped file, SHALL print a NOTE line
  naming the path and the reason, and SHALL record an OVERWRITE_CONFLICT entry;
  and SHALL copy the shipped file when the target has no copy or a
  byte-identical one. The `.ps1` twin SHALL behave the same. The file's own
  UPGRADING note SHALL be corrected to the new behaviour.
  Verification: three sync fixtures (absent, identical, edited) with a byte
  comparison and a grep of the sync stdout.

- Spec-AC-10: WHEN the protected-branch fallback's `git branch` or
  `git reset --hard` fails, `aai-release.sh` SHALL emit the
  `FALLBACK INCOMPLETE` report naming which of the two failed and SHALL exit
  18, leaving the target branch where the failure found it; and the `.ps1`
  twin SHALL route both calls through `$fallbackIncomplete` rather than
  throwing past it.
  Verification: a fixture with a D/F-conflicting ref (`chore/release-v9.8.0/x`
  present) driving the branch arm, a fixture with an unwritable index driving
  the reset arm, asserting exit 18, the report text and the branch tip.

- Spec-AC-11: `aai-sync.sh`'s `file_content_different` SHALL report NOT
  different when `cmp` cannot complete the comparison (exit 2), and the `.ps1`
  twin's catch arm SHALL return false; and the two already-fixed sync items
  SHALL close on their existing pins proven to redden under a named mutation
  rather than on a reading of the source.
  Verification: a direct unit arm driving `cmp` to exit 2, plus
  `node .aai/scripts/mutation-run.mjs` records for
  `tests/skills/test-aai-sync-seed.sh` TEST-021 and TEST-022.

## Acceptance Criteria Status

| Spec-AC    | Description                                                        | Status  | Evidence | Review-By | Notes |
|------------|--------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | WHEN a hook selection is given the installer installs only that set | planned | —        | —         | run 1 |
| Spec-AC-02 | WHEN a foreign hook sits in an unselected slot the install proceeds | planned | —        | —         | run 1 |
| Spec-AC-03 | The manual-merge path emits the body its own refusal names          | planned | —        | —         | run 1 |
| Spec-AC-04 | Installing the ref-guard discloses the git behaviour it changes     | planned | —        | —         | run 2 |
| Spec-AC-05 | A decline is one command that writes one committed line             | planned | —        | —         | run 2 |
| Spec-AC-06 | The decline reader fails closed over a closed vocabulary            | planned | —        | —         | run 2 |
| Spec-AC-07 | CAT-17 honours a declared decline and never over-reads it           | planned | —        | —         | run 3 |
| Spec-AC-08 | SKILL_UPDATE step 4 describes the installer it actually runs        | planned | —        | —         | run 3 |
| Spec-AC-09 | A consumer's edited routing file survives an update, loudly         | planned | —        | —         | run 3 |
| Spec-AC-10 | The release fallback reports its own failure instead of dying       | planned | —        | —         | run 4 |
| Spec-AC-11 | The sync comparison fails closed and the fixed items close on proof | planned | —        | —         | run 4 |

## Implementation plan

Components affected:
- `.aai/scripts/install-pre-commit-hook.sh` — argument parsing gains
  `--hooks <csv>`, `--print [hook]`, `--decline-ref-guard`, `--arm-ref-guard`;
  the foreign pre-check, the write blocks, the uninstall block and the
  attestation all become selection-aware; a disclosure block and a thin
  column-0 grep of `docs/ai/docs-audit.yaml` are added.
- `.aai/scripts/install-pre-commit-hook.ps1` — the same surface as `-Hooks`,
  `-Print`, `-DeclineRefGuard`, `-ArmRefGuard`; ASCII outside here-strings
  stays pinned by TEST-316.
- `.aai/scripts/lib/guard-config.mjs` — new `readRefGuardPolicy(dir)` and the
  `REF_GUARD_POLICY` vocabulary; the existing `GUARD_DIALS` array is NOT
  extended, because the grammar differs (D3).
- `.aai/scripts/aai-doctor.mjs` — `catGitRefGuard` consults the policy before
  returning its absent-guard verdict; a new non-counting status is used for the
  declined state.
- `.aai/SKILL_UPDATE.prompt.md` step 4, plus the diet ledger entry and the
  TEST-012 pin.
- `.aai/scripts/aai-sync.sh` and `.ps1` — the MODEL_ROUTING preserve arm and
  the `file_content_different` error-path arm.
- `.aai/system/MODEL_ROUTING.yaml` — the UPGRADING note corrected.
- `.aai/scripts/aai-release.sh` and `.ps1` — rc checks around the fallback's
  branch and reset.
- `tests/skills/suite-map.yaml` — the `aai-git-ref-guard` suite's globs gain
  `.aai/scripts/lib/guard-config.mjs`, `docs/ai/docs-audit.yaml` and
  `.aai/SKILL_UPDATE.prompt.md`, so an edit to any of them re-runs the suite
  that owns it.

Edge cases the implementation must hold:
- `core.hooksPath` and linked-worktree resolution stay untouched; every new
  code path resolves through the existing `resolve_hook_path`.
- The new config write must not disturb other keys in `docs/ai/docs-audit.yaml`
  or its comments, and must create a file with only its own key when none
  exists.
- `--decline-ref-guard` combined with `--hooks ref-guard` is contradictory and
  exits 2 naming the contradiction.
- The vendored-dependency check (`check-vendored-script-deps.mjs`) must still
  pass: the installer's new grep must stay a thin shell grep and must NOT
  import `guard-config.mjs`, because the installer ships into targets where a
  node module resolution is not guaranteed.

TDD slicing — four runs, three acceptance criteria each except the last:
- Run 1: Spec-AC-01, Spec-AC-02, Spec-AC-03 (the installer's own surface, both
  twins). These share one parsing change and one fixture builder, so splitting
  them across runs would rebuild the same scaffolding twice.
- Run 2: Spec-AC-04, Spec-AC-05, Spec-AC-06 (disclosure, the decline command,
  the reader). The reader and the writer are one contract and are written
  against each other.
- Run 3: Spec-AC-07, Spec-AC-08, Spec-AC-09 (the consumers of the decision:
  doctor, the update prompt, and the unrelated routing item that rides the same
  sync surface).
- Run 4: Spec-AC-10, Spec-AC-11 (the two items that touch neither the installer
  nor the doctor), then the full sweep and the close ceremony.

## Test Plan

Ids continue the live band; the highest id in the corpus at planning is
TEST-605, so this scope allocates from TEST-606. Every row names its own suite
and selector; the mutation evidence for each is
`docs/ai/tdd/spec-update-installs-ref-guard-undisclosed/mutation-<TEST-id>.txt`,
produced by `node .aai/scripts/mutation-run.mjs`.

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Mutation | Status |
|----------|------------|------|----------------------|-------------|----------|--------|
| TEST-606 | Spec-AC-01 | integration | tests/skills/test-aai-git-ref-guard.sh | test_606_hooks_selection — in a scratch repo, --hooks index leaves the resolved reference-transaction path with no AAI-managed file, --hooks ref-guard leaves the resolved pre-commit path with none, no flag installs both, and --hooks bogus exits 2 naming the closed set. | Make the ref-guard write block ignore the selection with sed:s/want_hook ref-guard/true/ so the index-only run installs both. | pending |
| TEST-607 | Spec-AC-01 | integration | tests/skills/test-aai-git-ref-guard.sh | test_607_uninstall_selection — --uninstall --hooks ref-guard removes only the guard and leaves the AAI-managed pre-commit hook byte-identical; --uninstall with no selection still removes both. | Drop the selection test from the uninstall block with sed:s/want_hook index \&\& /\&\& / so a guard-only uninstall also deletes the index hook. | pending |
| TEST-608 | Spec-AC-01 | unit | tests/skills/test-aai-git-ref-guard.sh | test_608_ps1_hooks_static — the .ps1 twin declares a -Hooks parameter, validates it against the same closed set, and guards both write blocks with it (static parse, mirroring TEST-309). | Remove the -Hooks entry from the param block in install-pre-commit-hook.ps1. | pending |
| TEST-609 | Spec-AC-02 | integration | tests/skills/test-aai-git-ref-guard.sh | test_609_unselected_foreign_slot — a foreign file in the reference-transaction slot does not stop --hooks index from installing and exiting 0, and the foreign file is byte-identical afterwards. | Restore the unconditional foreign pre-check with sed:s/if want_hook ref-guard \&\& \[\[ -f "\$REFTX_PATH"/if [[ -f "$REFTX_PATH"/ so the unselected slot refuses again. | pending |
| TEST-610 | Spec-AC-02 | integration | tests/skills/test-aai-git-ref-guard.sh | test_610_selected_foreign_slot_writes_nothing — a foreign file in a SELECTED slot makes the run exit 1 and leaves both slots byte-identical to their pre-run state, and the attestation covers exactly the selected set. | Move the attestation call for the unselected hook back outside its selection guard so an index-only run fails attestation on an absent guard. | pending |
| TEST-611 | Spec-AC-03 | integration | tests/skills/test-aai-git-ref-guard.sh | test_611_print_ref_guard_body — --print ref-guard stdout is byte-identical to the file --hooks ref-guard installs, --print index and bare --print emit the index body, and none of the three creates a file in the fixture repo. | Point the ref-guard extraction at the index heredoc with sed:s/REFTXHOOK/HOOK/ in the awk program so --print ref-guard emits the wrong body. | pending |
| TEST-612 | Spec-AC-03 | integration | tests/skills/test-aai-git-ref-guard.sh | test_612_foreign_reftx_names_a_real_command — the foreign reference-transaction refusal names install-pre-commit-hook.sh --print ref-guard, and running that exact command exits 0 and emits a body carrying the AAI:REF-GUARD marker. | Revert the refusal text with sed:s/or merge the AAI:REF-GUARD body with:/or merge the AAI:REF-GUARD body manually./ so the message names no command. | pending |
| TEST-613 | Spec-AC-04 | integration | tests/skills/test-aai-git-ref-guard.sh | test_613_install_discloses_ref_guard — a fresh guard install prints a line naming refs/heads/main, AAI_GIT_WRITE=1 and the --decline-ref-guard command; an index-only install prints none of them. | Delete the disclosure echo block after the guard install with sed:s/^echo "Effect: a refs\/heads\/main update/: "&"; echo "installed"; : "/ leaving the install silent about the change. | pending |
| TEST-614 | Spec-AC-04 | integration | tests/skills/test-aai-git-ref-guard.sh | test_614_help_documents_the_new_surface — --help names --hooks with its closed set, --print with a hook argument, --decline-ref-guard and --arm-ref-guard. | Strip the --hooks line from the script header comment that --help prints. | pending |
| TEST-615 | Spec-AC-05 | integration | tests/skills/test-aai-git-ref-guard.sh | test_615_decline_writes_one_line — --decline-ref-guard writes a column-0 ref_guard: declined into docs/ai/docs-audit.yaml (creating it when absent), removes an AAI-managed guard, exits 0, and a second run leaves the file byte-identical with grep -c of the key equal to 1. | Make the config write unconditionally append with sed:s/replace_or_append_key/append_key/ so the second run duplicates the line. | pending |
| TEST-616 | Spec-AC-05 | integration | tests/skills/test-aai-git-ref-guard.sh | test_616_decline_respects_a_foreign_hook — with a foreign reference-transaction hook present, --decline-ref-guard refuses, exits non-zero, leaves the foreign file byte-identical and writes no key; and --arm-ref-guard after a decline restores armed plus the guard with exactly one ref_guard line. | Remove the foreign-marker test from the decline removal path so it deletes a non-AAI hook. | pending |
| TEST-617 | Spec-AC-06 | unit | tests/skills/test-aai-git-ref-guard.sh | test_617_policy_reader_fails_closed — readRefGuardPolicy returns armed for an absent file, an absent key, an indented key, a commented key and the invalid value decline (naming it on stderr), and declined only for a column-0 ref_guard: declined. | Flip the out-of-vocabulary default with sed:s/return 'armed';/return 'declined';/ in the invalid-value branch of guard-config.mjs. | pending |
| TEST-618 | Spec-AC-06 | integration | tests/skills/test-aai-hygiene-pack.sh | test_618_ref_guard_grep_conformance — the installer's thin shell grep and readRefGuardPolicy agree on the same six fixtures, extending the existing test_031 conformance harness to the new key. | Loosen the shell grep to allow leading whitespace so it reads an indented key as a decline while the reader does not. | pending |
| TEST-619 | Spec-AC-07 | integration | tests/skills/test-aai-doctor.sh | test_619_cat17_declined_is_not_an_issue — with ref_guard: declined and no guard file, CAT-17 names the declined state, the config path and the re-arm command, DOCTOR ISSUES does not count it, and --strict exits 0 when it is the only would-be WARN. | Return WARN from the declined branch with sed:s/'DECLINED'/'WARN'/ in catGitRefGuard so the category is counted again. | pending |
| TEST-620 | Spec-AC-07 | integration | tests/skills/test-aai-doctor.sh | test_620_cat17_declaration_never_over_reads — an armed guard reports PASS armed despite a declined declaration, a foreign reference-transaction hook still WARNs despite it, and an undeclared fixture keeps the current not-armed WARN text verbatim. | Move the policy check above the file-existence and marker checks so the declaration short-circuits an armed and a foreign hook alike. | pending |
| TEST-621 | Spec-AC-08 | integration | tests/skills/test-aai-git-ref-guard.sh | test_621_update_prompt_names_both_hooks — SKILL_UPDATE step 4 names AAI:REF-GUARD, refs/heads/main, AAI_GIT_WRITE=1 and --decline-ref-guard, and no longer carries the pre-commit-only safety sentence as its whole justification. | Restore the original step-4 safety sentence and delete the guard paragraph in .aai/SKILL_UPDATE.prompt.md. | pending |
| TEST-622 | Spec-AC-08 | unit | tests/skills/test-aai-prompt-diet.sh | test_622_diet_true_up — this ride's JUSTIFIED_ADDITIONS entry carries a leading byte count equal to the measured wc -c delta of .aai/SKILL_UPDATE.prompt.md against f84f84ab, TEST-012's want_growth equals the independent re-sum, and TEST-010 headroom stays inside the 2048 cap. | Change the entry's leading byte count by one so the re-sum and the pin disagree. | pending |
| TEST-623 | Spec-AC-09 | integration | tests/skills/test-aai-sync-seed.sh | test_623_routing_file_preserved — a target whose MODEL_ROUTING.yaml differs keeps its bytes across a sync, the run prints a NOTE naming the path and the reason, a conflict entry is recorded, and a target with no copy or a byte-identical copy receives the shipped file. | Restore the unconditional copy with sed:s/routing_target_is_customized/false/ in aai-sync.sh. | dropped |
| TEST-624 | Spec-AC-09 | unit | tests/skills/test-aai-sync-seed.sh | test_624_ps1_routing_twin — the .ps1 sync carries the same preserve arm and NOTE for MODEL_ROUTING.yaml, and the file's own UPGRADING note states the preserve behaviour rather than the overwrite one. | Delete the preserve branch from aai-sync.ps1 so the twins disagree. | dropped |
| TEST-625 | Spec-AC-10 | integration | tests/skills/test-aai-release.sh | test_625_fallback_branch_failure_reports — with chore/release-v9.8.0/x present so git branch hits a D slash F conflict, the protected-branch fallback prints FALLBACK INCOMPLETE naming the branch step, exits 18, and leaves the target branch at the release commit rather than reset. | Delete the or-else clause that routes a failed git branch to fallback_incomplete, so the failure kills the script at git's own exit code; the exact expression is recorded in the mutation record. | pending |
| TEST-626 | Spec-AC-10 | integration | tests/skills/test-aai-release.sh | test_626_fallback_reset_failure_reports — a fallback whose git reset --hard fails prints FALLBACK INCOMPLETE naming the reset step and exits 18 with the release branch already created and reported. | Remove the rc check around the fallback's git reset --hard so the failure kills the script raw. | pending |
| TEST-627 | Spec-AC-10 | unit | tests/skills/test-aai-release.sh | test_627_ps1_fallback_guarded — the .ps1 fallback wraps both the branch and the reset invocations in try blocks routed to $fallbackIncomplete, so neither throws past the report. | Remove the try wrapper around the ps1 branch invocation so the throw escapes. | pending |
| TEST-628 | Spec-AC-11 | unit | tests/skills/test-aai-sync-seed.sh | test_628_compare_fails_closed — file_content_different reports NOT different when cmp cannot complete the comparison (exit 2, driven with an unreadable path), and the .ps1 twin's catch arm returns false. | sed:s/\[\[ "\$rc" -eq 1 \]\]/[[ "$rc" -ne 0 ]]/ in aai-sync.sh so an unobtainable comparison reads as different again. | pending |
| TEST-629 | Spec-AC-11 | integration | tests/skills/test-aai-sync-seed.sh | test_629_crlf_pin_still_bites — the existing CRLF pin is replayed under mutation, proving fu-gitignore-crlf-exact-line is closed by a test that reddens rather than by a reading of the source. | sed:s/tr -d "\\r" < "\$gitignore_path"/cat "$gitignore_path"/ in lib/gitignore-block.sh so the CR-blind exact match returns. | pending |
| TEST-630 | Spec-AC-11 | integration | tests/skills/test-aai-sync-seed.sh | test_630_agents_tree_pin_still_bites — the existing .agents/skills propagation pin is replayed under mutation, proving fu-agents-tree-not-synced is closed by a test that reddens. | Disable the .agents/skills copy loop in aai-sync.sh by making its directory guard false, so a target never receives the mirror. | pending |
| TEST-631 | Spec-AC-05 | integration | tests/skills/test-aai-git-ref-guard.sh | test_631_ps1_decline_arm_params — the PowerShell twin exposes DeclineRefGuard and ArmRefGuard, and asking for both at once is a usage error with nothing written. | Neuter the contradiction check so both switches together are accepted; the record is in mutation-TEST-631.txt (added by Amendment 2). | pending |
| TEST-632 | Spec-AC-06 | integration | tests/skills/test-aai-git-ref-guard.sh | test_632_ps1_policy_fails_closed — the twin reads the same key and falls back to armed on absent, indented, commented or invalid input, so one docs-audit.yaml serves a repository checked out on either platform. | Flip the fall-through default to declined; the record is in mutation-TEST-632.txt (added by Amendment 2). | pending |
| TEST-633 | Spec-AC-05 | integration | tests/skills/test-aai-git-ref-guard.sh | test_633_ps1_shared_refusal_helper — the twin prints its foreign-hook refusal through one shared helper rather than a duplicated literal. | Restore a duplicate literal copy of the refusal sentence; the record is in mutation-TEST-633.txt (added by Amendment 2). | pending |
| TEST-634 | Spec-AC-05 | integration | tests/skills/test-aai-git-ref-guard.sh | test_634_decline_arm_crlf_write — a decline against a CRLF docs/ai/docs-audit.yaml records the declaration and removes the hook, and the mirror arm case restores it; neither reports success it did not achieve. | Revert the awk whitespace class so it no longer accepts a carriage return, restoring the disagreement with the grep gate. | pending |
| TEST-635 | Spec-AC-05 | integration | tests/skills/test-aai-git-ref-guard.sh | test_635_decline_orders_write_before_removal — when the declaration cannot be written, the guard is still installed and armed afterwards; the decline never leaves a consumer disarmed with nothing recorded. | Patch the order back so the hook is removed before the declaration is written. | pending |
| TEST-636 | Spec-AC-05 | integration | tests/skills/test-aai-git-ref-guard.sh | test_636_plain_reinstall_honours_decline — a plain installer run after a decline leaves the guard uninstalled and says why, while an explicit arm and a forced run both still install it. | Neuter the condition that consults the declared policy before a plain ref-guard install. | pending |
| TEST-637 | Spec-AC-05 | integration | tests/skills/test-aai-git-ref-guard.sh | test_637_ps1_plain_reinstall_honours_decline_static — the PowerShell twin carries the same policy consultation before a plain install, asserted on the source text per this spec's residual-risk note. | Flip the compared policy value so the twin skips on armed instead of declined. | pending |
| TEST-638 | Spec-AC-01 | integration | tests/skills/test-aai-git-ref-guard.sh | test_638_hooks_empty_rejected — an empty hooks selection is a usage error in both twins rather than a run that installs nothing and reports success. | Neuter the empty-argument guard so the shell twin accepts it again. | pending |
| TEST-639 | Spec-AC-09 | integration | tests/skills/test-aai-git-ref-guard.sh | test_639_model_routing_note_cites_amendment_2 — the routing file's UPGRADING note cites the amendment that actually carries the owner's re-disposition. | Revert the citation to Amendment 1, which does not carry that decision. | pending |

## Seams

- S1 — the installer writes the file `aai-doctor.mjs` CAT-17 probes. Crossed by
  TEST-606 and TEST-619 through TEST-620 driving doctor over the fixture the
  installer actually produced, never a hand-built one.
- S2 — `docs/ai/docs-audit.yaml` is written by a SHELL script and read by a JS
  module. Crossed by TEST-618, which feeds one fixture set to both readers.
- S3 — `.aai/SKILL_UPDATE.prompt.md` describes a script it does not import.
  Crossed by TEST-621, which asserts the prompt's claims against the installer's
  actual behaviour rather than against itself.
- S4 — `PROFILES.yaml` classifies the file `aai-sync` copies. Crossed by
  TEST-623, which drives a real sync into a target rather than asserting the
  profile list.
- S5 — the prompt corpus and the diet ledger. Crossed by TEST-622.
- S6 — the suite-map globs decide which suite re-runs for an edited file. The
  new globs are exercised by the selected-suite run in every TDD round; a stale
  map would show up as a suite that does not re-run for its own file.

## Residual risks

- A consumer who declines the guard and later re-installs hooks by running the
  installer with no flags gets the guard back, because the default is armed and
  the declaration is only consulted by doctor and by the decline command
  itself. Making the installer refuse to install a declined guard would turn a
  committed file into an ambient veto over an explicit command; the explicit
  command wins, and the disclosure says so. Not covered by an automated test
  beyond the disclosure text.
- The preserve behaviour for `MODEL_ROUTING.yaml` means a consumer who edits it
  stops receiving new shipped tiers. The NOTE on every update is the only
  mitigation; whether it is read is outside this repository's reach.
- `.ps1` behaviour is asserted statically on POSIX (TEST-608, TEST-624,
  TEST-627) and behaviourally only on the Windows CI leg. A twin defect that a
  static parse cannot see reaches CI, not the suite.

## Verification

Remediation note (validation round 1, N9): the suite files are mode 0644, so
`aai-run-tests.sh tests/skills/X.sh` execs a non-executable file and exits
126. The working form names `bash` as the command `aai-run-tests.sh` runs,
corrected below. Housekeeping only — no AC or Test Plan row changes, so no
amendment is owed.

- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-git-ref-guard.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-doctor.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-sync-seed.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-hygiene-pack.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh`
- `node .aai/scripts/mutation-run.mjs --replay --spec <this spec>`
- `AAI_TEST_TIMEOUT=3000 bash .aai/scripts/aai-run-tests.sh` (full sweep, once,
  before close)
- PASS criteria: every TEST-xxx green, every mutation record RED on replay,
  every Spec-AC in a terminal status.

## Evidence contract

- ref_id: `update-installs-ref-guard-undisclosed`
- Per TDD run: the RED log at `docs/ai/tdd/spec-update-installs-ref-guard-undisclosed/`
  and the mutation record `mutation-<TEST-id>.txt` in the same directory, both
  cited in the AC Status Evidence cell.
- Per suite run: the command, its exit code and its output path.
- Code review: the branch diff against main f84f84ab, dual verdict.
- Strategy is `tdd`, so a stored RED artifact per AC-gating test is demanded
  and the mutation record is not optional.

## Registry items closed by this scope

Re-derived at planning from `node .aai/scripts/follow-ups.mjs list`, by
subject, and each measured against the tree at f84f84ab rather than taken from
the intake's list.

FIXED BY THIS SCOPE, each by the named Spec-AC, each with a test a named
mutation reddens:

- `fu-update-installs-ref-guard-undisclosed` — Spec-AC-01 through Spec-AC-08
- `fu-routing-file-overwritten-on-update` — Spec-AC-09
- `fu-release-fallback-branch-unguarded` — Spec-AC-10

ALREADY FIXED IN THE TREE, closed on evidence plus a mutation that reddens the
pin, with no production-code change:

- `fu-agents-tree-not-synced` — Spec-AC-11, TEST-630. The paired maintenance
  half of this ride. `aai-sync.sh` and `aai-sync.ps1` both copy
  `.agents/skills/` and both carry it in their managed-prefix lists;
  `test-aai-sync-seed.sh` TEST-022 already pins propagation, the gitignore
  line and the do-not-wholesale-delete behaviour.
- `fu-gitignore-crlf-exact-line` — Spec-AC-11, TEST-629.
  `lib/gitignore-block.sh` matches against a CR-stripped copy since PR #326;
  TEST-021 pins it.

FIXED IN THE TREE BUT UNTESTED ON ITS OWN PATH, so this scope adds the missing
arm:

- `fu-sync-hash-compare-fails-open` — Spec-AC-11, TEST-628. Both twins fail
  closed today, but no test drives the error path; the only pin asserts a
  downstream symptom a working comparison never produces.

REJECTED BY THIS SCOPE: none.

## GitHub issues

- Issue `goodwind-cz/aai#369` (`contract_violation`, SKILL_DOCTOR, medium,
  `evidence_ref: SPEC-0156`, `workaround: manual`, Windows, pin v2026.09.09) —
  FIXED by Spec-AC-01, Spec-AC-04, Spec-AC-05, Spec-AC-07 and Spec-AC-08. The
  record carries the friction envelope and no prose, so the fix is derived from
  the contract it names, not from a reading of the report: SPEC-0156's guard
  reached consumers through a prompt whose stated safety property covered one
  of the two hooks it installs. It is closed at this ride's PR citing the four
  criteria and their tests, and the closing comment names the `.ps1` twin
  explicitly because the reporter was on Windows.

## Amendment 1 (post-freeze, 2026-09-24 — the decline surface binds BOTH twins; three Mutation-cell deviations, TDD run 2)

**Spec-AC-05 and Spec-AC-06 bind the PowerShell twin as well as the shell one.**
Run 2 delivered the disclosure, the decline writer and the fail-closed reader in
`install-pre-commit-hook.sh` and named the gap honestly: the `.ps1` has no
decline or arm surface yet. Left there, this ride would ship an exit that only
POSIX consumers can take — and the consumer whose report opened
`goodwind-cz/aai#369` was on Windows. A guard that can only be declined on the
platform that did not report it is not the fix this intake asked for. The twin
is therefore in scope for run 3, not a later ride: same closed-set selection,
same one-line declaration, same fail-closed reading, and the `.ps1` must write
the identical key so one `docs/ai/docs-audit.yaml` serves a repository checked
out on either platform. The Windows CI leg remains the only real runtime check
on it; a static shape test is not a substitute and must not be reported as one.

**Three Mutation-cell deviations (cells left verbatim; records RED).** All three
are limits of how `mutation-run.mjs` applies `--sed`, not disagreements with what
the rows assert:

- **TEST-613.** The cell anchors with `^`. `--sed` compiles a JavaScript RegExp
  without the multiline flag, so `^` matches only at the start of the file and
  the expression can never fire mid-file. Recorded instead a prefix that turns
  the disclosure `echo` into a no-op.
- **TEST-616.** The cell describes removing a check that spanned two lines. A
  `--sed` replacement containing `\n` does not insert a newline (JavaScript
  treats the replacement literally there), so the first attempt silently
  corrupted the script. Run 2 refactored the check onto one line so a
  single-line expression applies cleanly, and recorded that.
- **TEST-617.** The cell's `sed:s/return 'armed';/return 'declined';/` hits the
  FIRST occurrence under a non-global replace — the absent-file branch, not the
  invalid-value branch the row is about. A distinguishing comment now makes the
  equivalent expression target the intended branch.

**One hazard run 2 introduced and fixed.** Copy-pasting an existing refusal
sentence into a new code path gave run 1's TEST-612 a second, unmutated copy of
its target string; the recorded `--sed` then hit whichever copy came first and
the row stopped proving its property. Caught by `--replay`, not by the suite.
Fixed by extracting one shared helper for that message. Filed as
`fu-duplicate-message-collides-mutation` (P3) because nothing prevents the next
occurrence.

Sign-off: none (tracked).

## Amendment 2 (post-freeze, 2026-09-24 — Spec-AC-09 re-dispositioned by the owner; TEST-620's evidence shape; three twin rows added)

**Spec-AC-09 is narrowed by an owner decision, not by the implementer.** Its
frozen text asks `aai-sync` to KEEP a target's edited
`.aai/system/MODEL_ROUTING.yaml` and to record a conflict. The owner decided on
2026-09-24 that the opposite is correct: the table binds tier to model id and
tracks a moving external world — new models, changed prices — and a consumer
will not track that for us, so overwriting the shipped table on update is the
behaviour to keep. What the frozen AC mistook for the defect is a consequence of
that being right. The real gaps are that nobody keeps the table current and
nothing notices when it lapses (measured: `PRICING.yaml` carries no `as_of` or
any freshness marker, and its three readers cannot tell fresh data from a
year-old copy), and that a consumer's exception has nowhere to live that an
update does not overwrite. Both are now their own scope:
`docs/issues/CHANGE-DRAFT-routing-tables-have-an-owner-and-a-seam.md` (PR #389).

Spec-AC-09 therefore delivers only what survives that decision: the routing
file's own UPGRADING note states the overwrite as INTENDED and points at the
owner/seam intake, instead of instructing every consumer to re-apply their
customization after each update — the defect handed to the user as a procedure.
No preservation mechanism, no conflict record, no conditional copy in either
sync twin. TEST-623 and TEST-624, which gated the withdrawn mechanism, are
withdrawn with it and are not owed. `fu-routing-file-overwritten-on-update` is
dropped against this ride and re-dispositioned to that intake, rather than
closed as if this scope had fixed it.

**TEST-620 is a negative control and its RED is the mutation, not a failing
run.** Its three assertions (armed passes, a foreign hook warns, an undeclared
project is unchanged) are already true on the unmodified tree, because the
policy check Spec-AC-07 adds lives only in the absent-guard branch. There is no
pre-implementation failure to capture, so `tdd-evidence-check.mjs` has nothing
to accept and the row's proof is its mutation record alone
(`mutation-TEST-620.txt`, which reorders the policy check above the existence
and marker checks and makes D4 — reality outranks the declaration — fail). The
suite's own `test_303_unmutated_control` has the same shape. Recorded here so
the row is not later read as missing evidence.

**Three rows added for the twin** that Amendment 1 moved into run 3: TEST-631,
TEST-632 and TEST-633, all against `install-pre-commit-hook.ps1`. Their proof is
static in the suite, per this spec's own residual-risk note that the Windows CI
leg is the only real runtime check on the twin — but run 3 also verified the
contract across twins by hand: a `.ps1` decline wrote the key and a `.sh` arm
read that same key back and replaced it, which is the property that matters and
was otherwise only asserted.

Sign-off: owner for the Spec-AC-09 re-disposition (decision of 2026-09-24);
none (tracked) for the rest.

## Amendment 3 (post-freeze, 2026-09-24 — validation round 1's blocking finding and five more rows)

Validation round 1 returned FAIL on one blocking finding, and the finding is
worth stating plainly because of where it sat.

**The decline writer was CRLF-blind, inside the ride that certifies a CRLF
blindness closed.** `write_ref_guard_policy` checked for a replaceable key with
a `grep -E` whose `[[:space:]]` includes a carriage return, then replaced it
with an `awk` whose `[ \t]` does not. On a `docs/ai/docs-audit.yaml` with
Windows line endings the gate said "replace it", the action matched nothing,
the append branch never ran, and the read-back honestly reported the old value
— so `--decline-ref-guard` removed the hook, recorded nothing, and exited 1.
The consumer ends up disarmed, with no record of having declined, and CAT-17
warns forever: the exact complaint ISSUE-0083 was filed about. The mirror case
re-armed while claiming failure. Meanwhile Spec-AC-11 of this same spec closes
`fu-gitignore-crlf-exact-line`, an older defect of exactly this class whose fix
was a `tr -d "\r"`. A ride can close a class and reintroduce it in the same
diff; only an adversarial round caught it. TEST-634 pins it.

Fixed as the class rather than the instance: the matchers in that file now agree
on what a line is, and the other two readers were checked — `lib/guard-config.mjs`
splits on `/\r?\n/` and the `.ps1` reads through `Get-Content`, so neither ever
had it. `.gitattributes` is deliberately NOT extended to pin `docs/ai/*.yaml` to
LF: the file is the project's own, a CRLF copy of it is legitimate, and matcher
parity fixes the case a bytes-rewrite would not reach.

**The decline left a partial state.** It removed the hook before writing the
declaration, so any write failure disarmed the consumer silently. The file
already applied "check both before writing either" to the two hook slots; the
decline's own two effects now get the same discipline — the declaration is
written first, and a failure leaves the guard installed and armed.

**A declared decline now survives `/aai-update`, and that was an
orchestrator override of the validator's own disposition.** Validation measured
that a plain installer run re-armed the guard while the config said `declined`,
and ruled it non-blocking because this spec accepts it as a residual risk. That
reading is fair, and it was overruled: D1 justifies the residual with "the
explicit command wins", and `/aai-update` is not the consumer's explicit
command — it is the automatic side effect that produced the complaint. A decline
that the next documentation refresh reverts does not fix the issue. Both twins
now consult the declaration before a plain install and skip the guard aloud;
`--arm-ref-guard` and `--force` remain two-way overrides, so the exit is not a
trap door.

Six rows added: TEST-634 through TEST-639, covering the above plus the empty
hooks selection the shell twin used to accept with a success footer, and the
routing note's citation, which pointed at Amendment 1 rather than the
Amendment 2 that carries the owner's decision. The Verification section's suite
commands were corrected in place (they named a form that exits 126 because the
suite files are not executable); that is a Verification text fix, not an AC
change.

Sign-off: none (tracked).

## Notes

Out of scope, named here so they are not read as dropped (intake `## Notes`,
D9): CAT-14 reports `N/3 arms passed` without naming the failing arm in text
mode, and CAT-08 reliably WARNs after an update because the update itself
leaves the tree dirty. Neither is a registry item today; if either is wanted,
it is a doctor-surface ride of its own.

SPEC-0156 is frozen and done. Nothing here reopens it: the guard stays, the
installed hook body is byte-identical before and after this scope, and the only
thing that changes is who is told about it and what a consumer may declare.
