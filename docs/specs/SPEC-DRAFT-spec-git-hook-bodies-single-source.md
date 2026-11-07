---
id: spec-git-hook-bodies-single-source
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: f0cc237f6461129c994f2bd1653a0df1e38d97c38735a4750f092d2ef6576a54
ceremony_level: 2
links:
  requirement: git-hook-bodies-single-source
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Move the git hook bodies both installers embed to shared templates

SPEC-FROZEN: true

## Links

- Requirement: [Move the git hook bodies both installers embed to shared templates](../issues/CHANGE-DRAFT-git-hook-bodies-single-source.md).
- Parent: [RFC-0017](../rfc/RFC-0017-smaller-node-core-and-faster-feedback.md),
  phase 5, and the [remaining-scripts plan](../analysis/node-first-remaining-plan.md)
  ride 4 (owner sign-off: yes, on the plan, 2026-11-05).
- Pattern precedent: ride 3, [SPEC-0276](SPEC-0276-spec-cloudflare-share-on-node.md)
  (suite helpers `need_tool`, the Pester engine-under-test pattern, the
  scratch `aai-sync` install, the wiring list named up front).
- Technology contract: docs/TECHNOLOGY.md (bash, PowerShell 5.1 and 7,
  Pester 5, Node stdlib for the existing gates; nothing added).
- Baseline: main `244ef0bf`.

## Implementation strategy

- Strategy: tdd
- Rationale: the owner asked for TDD in runs of about three Spec-ACs (rides 1
  to 3). The scope changes what two shipped, consumer-visible installers
  write into every downstream repository's git hooks; the pipefail defect and
  the byte drift are behaviours that must be seen failing first (both were
  reproduced at planning, see Measurements). Inspection rows (wiring, RFC,
  line budget) are RED on the baseline too. Every row carries a mutation.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound change to two shipped installers, four new
  shipped templates, PROFILES, `.gitattributes`, a CI workflow path list, an
  umbrella RFC and the pins of five suites; the main checkout is shared and
  holds unrelated uncommitted files (docs/INDEX.md, docs/ai/EVENTS.jsonl,
  docs/ai/dashboard*, docs/ai/tests/test-runs.jsonl).
- User decision: worktree (autopilot default 2, recorded in STATE with
  rationale "autopilot default")
- Base ref: main
- Worktree branch/path: refactor/git-hook-bodies-single-source at /Users/ales/Projects/aai-worktrees/git-hook-bodies-single-source
- Inline review scope (a plain space-separated path list, as `set-code-review --scope` takes it):
  .aai/scripts/install-pre-commit-hook.sh .aai/scripts/install-pre-commit-hook.ps1
  .aai/templates/git-hooks/pre-commit-guard-checks.sh
  .aai/templates/git-hooks/pre-commit-index.sh
  .aai/templates/git-hooks/reference-transaction.sh
  .aai/templates/git-hooks/pre-push.sh
  .aai/system/PROFILES.yaml .aai/scripts/lib/guard-config.mjs .gitattributes
  .github/workflows/ps1-quality.yml
  tests/skills/test-aai-git-hook-templates.sh tests/skills/install-pre-commit-hook.Tests.ps1
  tests/skills/lib/vendor-hook-installer.sh tests/skills/suite-map.yaml
  tests/skills/suite-weights.tsv tests/skills/lib/cd-subshell-leak-baseline.tsv
  tests/skills/test-aai-hygiene-pack.sh tests/skills/test-aai-git-ref-guard.sh
  tests/skills/test-aai-doctor.sh tests/skills/test-aai-docs-audit.sh
  tests/skills/test-aai-tracked-ignored.sh
  docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md CHANGELOG.md
  docs/issues/CHANGE-DRAFT-git-hook-bodies-single-source.md
  docs/specs/SPEC-DRAFT-spec-git-hook-bodies-single-source.md docs/INDEX.md
  (cd-subshell-leak-baseline.tsv only if the ratchet asks for a row;
  guard-config.mjs is a comment-only edit).
- Code review required: true.

## Measurements behind the decisions

Measured on the planning tree (macOS arm64, bash 5, BSD `/usr/bin/grep`,
Node 22, pwsh 7.6.3, Pester 5.7.1, git) on 2026-11-07 at `244ef0bf`.
Windows PowerShell 5.1 was not available to Planning.

### Lines (the plan's method, section 1)

Code lines are non-blank, non-comment lines
(`grep -cvE '^[[:space:]]*(#|$)'` under bash with `/usr/bin/grep`); a hook
body's lines are counted between its heredoc or here-string delimiters.

| Body | .sh total | .sh code | .ps1 total | .ps1 code |
|---|---|---|---|---|
| reference-transaction (AAI:REF-GUARD) | 39 | 26 | 41 | 28 |
| guard block (AAI:GUARD-CHECKS) | 19 | 13 | inside pre-commit | inside pre-commit |
| pre-commit index body (AAI:INDEX-AUTOGEN) | 153 | 107 | 166 (with the guard block) | 117 (with the guard block) |
| pre-push (AAI:CLOSE-GATE) | 101 | 71 | 101 | 71 |
| all embedded bodies | 312 | 217 | 308 | 216 |
| whole installer | 1313 | 749 | 1097 | 749 |

Before: twin duplication of the embedded bodies is 216 code lines (the
smaller side), 308 total lines.

### Observed on the baseline

- Both installers run into fresh scratch repositories (`.sh` under bash,
  `.ps1` under pwsh 7) write three hooks that differ: pre-commit 7638 vs
  7380 bytes (28 differing diff lines), reference-transaction 1213 vs 1404
  bytes (12), pre-push 4701 vs 4700 bytes (4). Every `.ps1`-written hook
  ends without a final newline (`Set-Content -NoNewline`); every
  `.sh`-written hook ends with LF.
- The `.ps1` pre-commit body pipes into an early-closing reader at five
  sites: four pipes into `grep -q` or `grep -Eq` (staged-name check,
  close_gate dial, staged hunk check, body_lint dial) and one pipe into
  `head -1` (spec id). The `.sh` body uses here-strings at all five since
  PR #381. Counted with the `PGQ_PATTERN` of
  `tests/skills/lib/pipe-grep-q-ratchet.sh` over the here-string lines.
- Pipefail reproduction: a scratch repo with `docs/a.md` plus 4000 other
  staged files (230940 bytes of staged names) and a stub
  `.aai/scripts/generate-docs-index.mjs` that writes `docs/INDEX.md`. The
  `.ps1`-written hook, run with bash, exits 0 WITHOUT regenerating the index
  in 3 of 3 runs; the `.sh`-written hook regenerates it in 3 of 3; the
  `.ps1`-written hook with only `docs/a.md` staged regenerates it in 2 of 2.
- Other drift in the bodies: the "Installed by" lines; the reference-
  transaction refusal text (the `.sh` gives only the POSIX escape and a bash
  uninstall line, the `.ps1` gives a PowerShell escape, a POSIX escape and a
  pwsh uninstall line); an em dash versus a hyphen in the AAI:INDEX-AUTOGEN
  header line; a three-line `NOTE (CHANGE-0009 D8)` comment only in the
  `.ps1`; nine further em dashes in the `.ps1` body comments and messages,
  which Windows PowerShell 5.1's `Set-Content` encodes in the ANSI code page.

### Callers, readers and pins (tracked files; history and test results excluded)

- `.aai/scripts/aai-doctor.mjs` CAT-12, CAT-17 and the guard-caller check
  recognise hooks by marker and probe the reference-transaction hook for the
  literal `AAI:REF-GUARD` on stderr (SEAM-1). The markers and that line stay.
- `.aai/scripts/lib/guard-config.mjs` line 6 names "the shell grep embedded
  in install-pre-commit-hook.ps1" in a comment; the comment moves to the
  template (comment-only edit).
- `.github/workflows/ps1-quality.yml` line 1250 runs the `.sh` installer
  with `--arm-ref-guard` in the checkout (template path resolution covers it).
- Fixtures that copy an installer ALONE into a scratch root (they break
  once the installer reads templates): `test-aai-docs-audit.sh`
  `setup_spec0010_hook_repo` and `setup_spec0011_hook_repo`;
  `test-aai-doctor.sh` `test_1344_cat17_seam1_installed_hook_passes` and
  `t812_repo`; `test-aai-git-ref-guard.sh` `test_310_doctor_category`;
  `test-aai-hygiene-pack.sh` `sg_repo`, `test_813_ps1_twin_parity` and
  `test_818_ps1_upgrade_is_byte_exact_and_order_checked`;
  `test-aai-tracked-ignored.sh` `test_1709_real_hook_refuses_commit`.
- Source-shape pins that read a body out of an installer: `test-aai-git-ref-guard.sh`
  `test_309_ps1_twin_static` (extracts `$reftxBody`; asserts the refusal
  gives pwsh and not bash uninstall guidance); `test-aai-hygiene-pack.sh`
  `test_813_ps1_twin_parity` (extracts the `.sh` heredocs and `$prePushBody`)
  and `test_031_guard_config_conformance` (extracts the close_gate grep
  pattern from the `.ps1` and requires it to name `lib/guard-config.mjs`).
- `--print` callers keep working unchanged: TEST-314, 611, 612, 614
  (`test-aai-git-ref-guard.sh`), TEST-803, 804, 814 and the upgrade cases
  (`test-aai-hygiene-pack.sh`), and `test-aai-release.sh` line 1435.

### Wiring found at planning

- `tests/skills/suite-map.yaml`: 128 top-level rows; the new row makes 129.
  The rows of the five suites whose fixtures move to the new shared helper
  (`aai-docs-audit`, `aai-doctor`, `aai-git-ref-guard`, `aai-hygiene-pack`,
  `aai-tracked-ignored`) gain the helper and the templates glob.
- `tests/skills/test-aai-hygiene-pack.sh` pins the row count in
  `test_090_suite_map_pin` and `test_129_mutation_gate_suite_registration`;
  both move from 128 to 129.
- `tests/skills/lib/nested-suite-lint.mjs` (allowlist of 10 rows, run by
  hygiene-pack `test_133`): every cross-suite call in the new suite is in
  selector form, no new allowlist row.
- `tests/skills/suite-weights.tsv`: `<name><TAB>196` (the documented
  maximum; TEST-3338 pins it) with a `# sample <name> fallback unsampled (...)` line.
- `.aai/scripts/check-cd-subshell-leak.mjs` scans `tests/skills` and
  `.aai/scripts`; a `cd` inside a substitution in the new suite or the helper
  needs a recorded row. The templates are outside its scan.
- `.aai/scripts/check-test-registration.mjs`: every `test_*` of the new suite is called.
- `tests/skills/lib/pipe-grep-q-ratchet.sh`: its baseline is empty; the new
  suite and helper must not add an early-closing reader pipe.
- `.github/workflows/ps1-quality.yml`: both path lists gain
  `.aai/templates/git-hooks/**` (the `.ps1` reads them); the
  `tests/skills/*.Tests.ps1` glob already covers the Pester file; the pin in
  `test-aai-win-fallback.sh` (`test_034`) must stay green.
- `.aai/system/PROFILES.yaml`: the four templates under `core:` (the
  installers are core); `test-aai-layer-profiles.sh` TEST-001 rejects an
  unclassified `.aai` file.
- RFC-0017 inventory (`test-aai-expert-fetch.sh test_2624_inventory_matches_tree`)
  checks pair membership only; `install-pre-commit-hook` stays a pair, so its
  row stays byte for byte.
- Prompt corpus: no `.aai/*.prompt.md` and no `.aai/AGENTS.md` change, so no
  prompt-diet ledger entry, no TEST-012 move, and no companion pin move in
  `test-aai-pr-preflight.sh`, `test-aai-legacy-migrations.sh` or
  `test-aai-retired-loop-runner.sh`. If implementation finds a prompt line
  that must change, that is a scope change (spec amendment), not a fold-in.
- L3: neither installer, no template and no other path in scope is in
  `protected_paths_l3` (docs/ai/docs-audit.yaml) or the WORKFLOW.md defaults;
  `pre-commit-checks.sh` (L3) is called by the guard block and stays byte for
  byte. `claude-hook-gate.sh` is not touched. The installers match the merge
  policy's `consumer-facing` architecture glob, so the owner merges.

## Decisions

### D-TPL. The four templates

Directory `.aai/templates/git-hooks/`, git mode 100644, ASCII only, LF only,
each ending in exactly one LF:

| Template | Holds | --print token |
|---|---|---|
| `pre-commit-index.sh` | the AAI:INDEX-AUTOGEN pre-commit body, shebang `#!/usr/bin/env bash` first | `index` (and bare `--print`) |
| `pre-commit-guard-checks.sh` | the AAI:GUARD-CHECKS block, `# AAI:GUARD-CHECKS BEGIN` first and `# AAI:GUARD-CHECKS END` last | `guard-checks` |
| `reference-transaction.sh` | the AAI:REF-GUARD body, shebang `#!/bin/sh` first | `ref-guard` |
| `pre-push.sh` | the AAI:CLOSE-GATE body, shebang `#!/usr/bin/env bash` first | `pre-push` |

Content rules:

- The `.sh` copy at `244ef0bf` is the source of every body (it already uses
  here-strings at all five early-closing sites, D-PIPE), with these edits
  only: every em dash becomes `--` (the header line becomes
  `# AAI:INDEX-AUTOGEN -- auto-regenerate docs/INDEX.md on docs/ changes.`);
  every `# Installed by` line becomes
  `# Installed by .aai/scripts/install-pre-commit-hook.sh or .ps1 from .aai/templates/git-hooks/.`;
  the `.ps1` copy's `NOTE (CHANGE-0009 D8)` comment (three lines naming
  `lib/guard-config.mjs` as the canonical reader) joins the index body above
  the close-gate block; the reference-transaction refusal follows D-MSG.
- The guard block's bytes are unchanged from `244ef0bf` (identical in both
  copies today), so no existing install refreshes its block on the next
  plain run.
- What any hook decides is unchanged: markers, dials, ranges, messages other
  than D-MSG, and exit codes.

### D-COMPOSE. What both installers write

- pre-commit (fresh install or `--force`): line 1 of `pre-commit-index.sh`,
  then all of `pre-commit-guard-checks.sh`, then lines 2 to the end of
  `pre-commit-index.sh` (the composition the `.sh` already uses).
- reference-transaction and pre-push: the template bytes.
- Both installers resolve the templates from their own location
  (`<script dir>/../templates/git-hooks/`), never from the target repository,
  so running the checkout's installer against a scratch repository keeps
  working.
- Both remove every CR byte from a template when reading it (D-EOL), write
  through a temp sibling and rename (the `.sh` already does for pre-commit
  and pre-push; the `.ps1` moves from `Set-Content -NoNewline` to its
  existing `Write-BytesViaTemp` for all three), and set the executable bit
  where the platform has one.
- `--print <token>` (the `.sh`) emits exactly the bytes of D-TPL's template
  after D-EOL; `--print` for the index stays the bare index body (TEST-314).
- The guard-block insert and refresh paths of both installers take the
  shipped block from `pre-commit-guard-checks.sh`.

### D-EOL. Platform-specific bytes

None. Every written hook is LF-only on every platform and from either
installer. The repository keeps the templates LF through the existing
`*.sh text eol=lf` rule in `.gitattributes`; an explicit
`.aai/templates/git-hooks/*.sh text eol=lf` line is added so the rule does
not depend on the extension. A template that still arrives with CR bytes
(a copy that bypassed git) is read with every CR removed, so the hook git
runs is never CRLF.

### D-MSG. One reference-transaction refusal for every shell

The hook fires for a ref update from any shell on the machine, so the
installer that wrote it does not predict where the refusal is read. The
template's message keeps the first three lines of both copies and ends:

```
  Fix:    re-run this ONE command with AAI_GIT_WRITE=1 set.
            POSIX shell:  AAI_GIT_WRITE=1 git commit ...
            PowerShell:   pwsh -NoProfile -Command '$env:AAI_GIT_WRITE=1; git commit ...'
  Uninstall this guard: bash .aai/scripts/install-pre-commit-hook.sh --uninstall
            (PowerShell: pwsh .aai/scripts/install-pre-commit-hook.ps1 -Uninstall)
```

`test_309_ps1_twin_static` is rewritten to read the template: it keeps the
marker, both predicate pins, the effective-path pins on the `.ps1`, the pwsh
uninstall line and the PowerShell escape, and its "must not name bash"
assertion is replaced by "names both uninstall commands" (an operator on
Windows has Git Bash, which git itself runs the hooks with).

### D-PIPE. The early-closing readers

The shared pre-commit body has no pipe into an early-closing reader (any
spelling `PGQ_PATTERN` counts): the staged-name check, both dial reads and
the staged hunk check use here-strings into `grep -q`/`grep -Eq`, and the
spec id is read with a here-string into `head -1`. The pipes into `grep -E`
or `grep -Ev` without a quiet or max-count flag (they read to EOF) stay.

### D-MISSING. A missing template

Before any write, an install checks that every template the selected hooks
need exists (pre-commit: index and guard-checks; ref-guard and
`--arm-ref-guard`: reference-transaction; close-gate: pre-push). A missing
one exits 1 with `ERROR: AAI hook template missing: <absolute path>` on
stderr (the `.ps1` through `[Console]::Error.WriteLine`, never `Write-Error`,
so the exit code is the one written) and writes and changes no hook.
`--print <token>` with its template missing exits 1 with the same line.
`--uninstall` and `--decline-ref-guard` need no template.

### D-HELPER. One way for a test to vendor an installer

`tests/skills/lib/vendor-hook-installer.sh` defines
`vendor_hook_installer <root> <sh|ps1|both>`: it copies the named
installer(s) to `<root>/.aai/scripts/` and the whole
`.aai/templates/git-hooks/` directory to `<root>/.aai/templates/git-hooks/`.
Every fixture listed under Measurements that copies an installer alone
calls it instead. A guard in the new suite fails when any `tests/skills/*.sh`
other than the helper copies an installer file (`cp` of a path ending
`install-pre-commit-hook.sh` or `.ps1`).

### D-WIRE. Wiring, named up front

- `tests/skills/suite-map.yaml`: new row `aai-git-hook-templates` with globs
  `.aai/scripts/install-pre-commit-hook.*`, `.aai/templates/git-hooks/**`,
  `.aai/scripts/aai-sync.sh`, `.aai/scripts/aai-doctor.mjs`,
  `.aai/system/PROFILES.yaml`, `.gitattributes`,
  `.github/workflows/ps1-quality.yml`,
  `docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md`,
  `tests/skills/test-aai-git-hook-templates.sh`,
  `tests/skills/install-pre-commit-hook.Tests.ps1`, and the shared test libs
  the suite reads: `tests/skills/lib/vendor-hook-installer.sh`,
  `tests/skills/lib/pipe-grep-q-ratchet.sh`,
  `tests/skills/lib/nested-suite-lint.mjs`,
  `tests/skills/lib/nested-suite-allowlist.tsv`,
  `tests/skills/suite-map.yaml`, `tests/skills/suite-weights.tsv`.
  The rows `aai-docs-audit`, `aai-doctor`, `aai-git-ref-guard`,
  `aai-hygiene-pack` and `aai-tracked-ignored` each gain
  `tests/skills/lib/vendor-hook-installer.sh` and `.aai/templates/git-hooks/**`.
- `tests/skills/suite-weights.tsv`:
  `# sample aai-git-hook-templates fallback unsampled (new suite of git-hook-bodies-single-source; no successful observation)`
  and `aai-git-hook-templates<TAB>196`.
- `tests/skills/test-aai-hygiene-pack.sh`: both row-count pins move from 128
  to 129, the message naming the git-hook-templates suite.
- Nested-suite lint: no new allowlist row (selector-form calls only).
- `tests/skills/lib/cd-subshell-leak-baseline.tsv`: a row only if
  `check-cd-subshell-leak.mjs` asks, recorded with `--record`.
- `.github/workflows/ps1-quality.yml`: `- '.aai/templates/git-hooks/**'` in
  both the push and the pull_request path lists.
- `.aai/system/PROFILES.yaml`: the four template paths under `core:`, after
  `.aai/templates/docs-audit.template.yaml`.
- `.gitattributes`: the D-EOL line.

### D-RFC. RFC-0017

- Phase 5 row: one sentence after the seventh-slice sentence and before the
  remaining-scripts-plan sentence:
  `The eighth slice [moved the git hook bodies to shared templates](../issues/CHANGE-DRAFT-git-hook-bodies-single-source.md): both installers write the same bytes from one copy, which ends the early-closing pipes of the PowerShell-written pre-commit hook.`
  Status stays `in progress`; frontmatter untouched; the inventory row of
  `install-pre-commit-hook` stays byte for byte. The allocator rewrites the
  link at merge; checks match only the suffix `git-hook-bodies-single-source.md`.
- After LOOP COMPLETE (ship convention, in the review scope, not a TEST row):
  CHANGELOG `## [unreleased] — refactor(hooks): both hook installers write one shared set of hook bodies`
  naming the pipefail fix, D-MSG, the final newline and encoding fix, the
  before and after line counts, and that a hook already installed keeps its
  bytes until `--force` (or `-Force`) re-installs it.

### D-SUITE

One new suite `aai-git-hook-templates` (`tests/skills/test-aai-git-hook-templates.sh`)
holds every row, with the `need_tool` helper of ride 3 (an absent tool fails
on CI, is a named SKIP-CASE locally). Every fixture is a fresh temp git
repository with a local identity; no case touches the checkout's own hooks.
The Pester file `tests/skills/install-pre-commit-hook.Tests.ps1` launches
the `.ps1` with the engine running the test (`(Get-Process -Id $PID).Path`),
so the hosted 5.1 step tests 5.1 and the pwsh 7 step tests pwsh 7.

## Acceptance Criteria Mapping

- Intake AC-001 maps to Spec-AC-01 and Spec-AC-13.
- Intake AC-002 maps to Spec-AC-02, Spec-AC-03, Spec-AC-04 and hosted check
  H1 (the native Windows Pester jobs under Windows PowerShell 5.1 and pwsh 7
  run `tests/skills/install-pre-commit-hook.Tests.ps1`).
- Intake AC-003 maps to Spec-AC-05 and Spec-AC-06.
- Intake AC-004 maps to Spec-AC-07, Spec-AC-08 and Spec-AC-09.
- Intake AC-005 maps to Spec-AC-10, Spec-AC-11, Spec-AC-12 and Spec-AC-13.

## Constitution deviations

None. Article 4 (degrade and report): a missing template refuses by name
before any write instead of writing a partial hook set. Article 5 (additive
first): command names, flags, markers, exit codes and every `--print` token
stay; the changed bytes of the written hooks are listed in D-TPL and D-MSG
and in the CHANGELOG. Article 2 (simplicity): no new flag, variable,
dependency or runtime; the templates are plain files both installers copy.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | The four D-TPL templates exist under .aai/templates/git-hooks/ with git mode 100644, ASCII only, no CR byte, one final LF, the D-TPL first line and their marker; neither installer contains a heredoc or here-string delimiter of a hook body (REFTXHOOK, GUARDBLOCK, PREPUSHHOOK, the HOOK heredoc, hookBody, reftxBody, prePushBody assignments) or any of the body sentinel lines aai_guarded=0, _cg_refused=0, _gc_rc=0 and the GEN= generator line. | planned | — | — | — |
| Spec-AC-02 | WHEN install-pre-commit-hook.sh runs in a fresh scratch repository, the system SHALL write pre-commit, reference-transaction and pre-push equal byte for byte to the D-COMPOSE result of the templates, each executable; --print index, guard-checks, ref-guard and pre-push and bare --print SHALL emit exactly the template bytes and write nothing. | planned | — | — | — |
| Spec-AC-03 | WHEN install-pre-commit-hook.ps1 runs under pwsh in a fresh scratch repository and install-pre-commit-hook.sh in a twin one, the three hooks SHALL be byte-identical between the two (cmp), each SHALL end in LF and hold no CR byte, and the ps1-written ones SHALL be executable. | planned | — | — | — |
| Spec-AC-04 | tests/skills/install-pre-commit-hook.Tests.ps1 passes under Pester 5 with at least 6 cases and none failed or skipped, covering: the fresh install equals the D-COMPOSE bytes; the hooks equal those the sh installer writes into a twin TestDrive repository under bash; a missing template; a CRLF template; the guard-block insert into a pre-guard AAI hook; a plain re-run that changes no byte. | planned | — | — | — |
| Spec-AC-05 | WHEN a pre-commit hook written by either installer runs under bash in a repository holding docs/a.md and 4000 further staged paths (over 200 KB of staged names) with a stub generator, the system SHALL write and stage docs/INDEX.md; and WHEN the staged set adds a status done line to a spec whose staged diff exceeds 200 KB, the stub docs-audit.mjs SHALL receive exactly one --gate-file call. RED on the baseline for the ps1-written hook. | planned | — | — | — |
| Spec-AC-06 | The PGQ_PATTERN of tests/skills/lib/pipe-grep-q-ratchet.sh matches 0 lines in each of the four templates; positive control: it matches 5 lines in the hookBody here-string of install-pre-commit-hook.ps1 at 244ef0bf, read with git show. | planned | — | — | — |
| Spec-AC-07 | WHEN any one of the four templates is absent from a vendored copy, each installer SHALL exit 1 with the D-MISSING line naming that path on stderr and leave every hook slot byte-identical (absent slots stay absent) for a selection that needs it; --print of that token SHALL exit 1 the same way; --uninstall SHALL still exit 0. | planned | — | — | — |
| Spec-AC-08 | WHEN a template holds CRLF line endings, the hooks both installers write SHALL hold no CR byte and stay byte-identical between the installers; and a plain re-run of either installer over hooks either installer wrote SHALL leave all three byte-identical and print the already-installed lines. | planned | — | — | — |
| Spec-AC-09 | The reference-transaction template carries the D-MSG lines (both escape forms, both uninstall commands) and the AAI:REF-GUARD refused line; WHEN aai-doctor.mjs --json runs in a scratch repository armed by either installer, CAT-17 SHALL report the guard armed; test-aai-git-ref-guard.sh selectors test_309_ps1_twin_static, test_314_print_flag, test_316_ps1_ascii_outside_here_strings, test_611_print_ref_guard_body, test_612_foreign_reftx_names_a_real_command, test_613_install_discloses_ref_guard and test_614_help_documents_the_new_surface exit 0. | planned | — | — | — |
| Spec-AC-10 | WHEN aai-sync.sh --profile core installs into a scratch git target whose path holds a space, the target SHALL hold the four templates byte-identical to the source, and the target's own sh installer (and its ps1 under pwsh when present) SHALL write three hooks byte-identical to the D-COMPOSE result; PROFILES lists each template once under core and test-aai-layer-profiles.sh test_manifest_conformance exits 0. | planned | — | — | — |
| Spec-AC-11 | Every fixture listed under Measurements vendors its installer through vendor_hook_installer, no tests/skills/*.sh other than the helper copies an installer file, and the pins named under Measurements pass: test-aai-hygiene-pack.sh test_031_guard_config_conformance, test_813_ps1_twin_parity and test_818_ps1_upgrade_is_byte_exact_and_order_checked, test-aai-doctor.sh test_1344_cat17_seam1_installed_hook_passes, test-aai-git-ref-guard.sh test_310_doctor_category and test-aai-tracked-ignored.sh test_1709_real_hook_refuses_commit exit 0. | planned | — | — | — |
| Spec-AC-12 | Wiring per D-WIRE: select-suites selects aai-git-hook-templates for each template, both installers, the helper and the Pester file, and selects each of the five helper-reading suites for the helper; suite-weights holds the row; both hygiene-pack pins read 129 and their selectors pass; nested-suite lint with its allowlist, check-cd-subshell-leak, check-test-registration and the pipe-grep-q ratchet exit 0; both ps1-quality path lists name the templates glob and win-fallback test_034 passes; .gitattributes holds the D-EOL line. | planned | — | — | — |
| Spec-AC-13 | Measured with the plan's method on the delivered tree, install-pre-commit-hook.sh has at most 1050 lines and 560 code lines, install-pre-commit-hook.ps1 at most 840 lines and 570 code lines, the four templates together at most 330 lines; the suite prints the before and after counts of both installers and the templates; test-aai-expert-fetch.sh test_2624_inventory_matches_tree exits 0 and the RFC-0017 phase 5 row holds the D-RFC sentence once with status in progress. | planned | — | — | — |

## Implementation plan

TDD in five runs of about three Spec-ACs; each run stores RED under
`docs/ai/tdd/git-hook-bodies-single-source/red/` before its change, GREEN
under `green/`, and one mutation record per row
(`node .aai/scripts/mutation-run.mjs`) before the run's hand-off.

1. Run 1, Spec-AC-01, 02, 06: the suite skeleton, the four templates
   (D-TPL, D-PIPE, D-MSG), the `.sh` installer reading them (D-COMPOSE,
   `--print`).
2. Run 2, Spec-AC-03, 05, 08: the `.ps1` reading and writing bytes
   (D-COMPOSE, D-EOL), the pipefail fixture, the CRLF and re-run cases.
3. Run 3, Spec-AC-04, 07, 09: the Pester file, D-MISSING in both installers,
   the D-MSG pins and the doctor seam (`test_309` rewrite).
4. Run 4, Spec-AC-10, 11: PROFILES, the scratch install, D-HELPER and the
   fixture and pin moves in the five suites.
5. Run 5, Spec-AC-12, 13: D-WIRE, D-RFC, the measurement; then the CHANGELOG
   entry after LOOP COMPLETE.

Edge cases the runs must keep: a symlinked or directory slot, a CR-terminated
first line, a BOM, inverted or duplicated guard markers and a foreign hook
are refused exactly as at `244ef0bf` (existing TEST-80x/81x cases); the
`.ps1` keeps writing to the effective hooks path (`Resolve-HookPath`).

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3432 | Spec-AC-01 | inspection | tests/skills/test-aai-git-hook-templates.sh | test_3432_templates_single_copy requires each D-TPL template with git ls-files mode 100644, no byte above 0x7E or CR, a final single LF, its D-TPL first line and marker; requires neither installer to hold the body delimiters or sentinel lines of Spec-AC-01; RED on the baseline (templates absent, delimiters present) | `sed:s/^_cg_refused=0$/_cg_refused=00/` on .aai/templates/git-hooks/pre-push.sh | pending |
| TEST-3433 | Spec-AC-02 | integration | tests/skills/test-aai-git-hook-templates.sh | test_3433_sh_writes_templates runs the sh installer in a fresh scratch repo and cmp-compares the three hooks with the D-COMPOSE bytes built in the test from the templates, requires the executable bit; runs --print for index, guard-checks, ref-guard, pre-push and bare, cmp-compares each with its template and requires no hook written by a print in a second scratch repo | `sed:s/^AAI:REF-GUARD refused this refs\/heads\/main update\.$/AAI:REF-GUARD refused this update./` on .aai/templates/git-hooks/reference-transaction.sh | pending |
| TEST-3434 | Spec-AC-03 | integration | tests/skills/test-aai-git-hook-templates.sh | test_3434_twin_bytes (need_tool pwsh) installs with pwsh -NoProfile -File on the ps1 and with bash on the sh into twin scratch repos and cmp-compares the three hook pairs; requires a final LF, no CR and the executable bit on each ps1-written hook; RED on the baseline (three pairs differ, no final LF) | `sed:s/Write-BytesViaTemp -Path \$prePushPath -Bytes \$prePushBytes/Set-Content -Path $prePushPath -Value ([Text.Encoding]::ASCII.GetString($prePushBytes)) -NoNewline/` on .aai/scripts/install-pre-commit-hook.ps1 | pending |
| TEST-3435 | Spec-AC-04 | integration | tests/skills/test-aai-git-hook-templates.sh | test_3435_pester (need_tool pwsh; SKIP-CASE without Pester 5 locally, as SPEC-0276 TEST-3425) runs Invoke-Pester on tests/skills/install-pre-commit-hook.Tests.ps1 with PassThru and fails on FailedCount above 0, SkippedCount above 0 or TotalCount below 6; the cases are the six of Spec-AC-04, in TestDrive git fixtures with a local identity and core.autocrlf false, the twin case running bash on the sh installer | `sed:s/\$b = \$b -ne 13/$b = $b/` on .aai/scripts/install-pre-commit-hook.ps1 | pending |
| TEST-3436 | Spec-AC-05 | integration | tests/skills/test-aai-git-hook-templates.sh | test_3436_pipefail_large_stage builds the Planning reproduction (docs/a.md plus 4000 staged paths, a stub generator writing docs/INDEX.md) once per installer and runs the written pre-commit with bash: docs/INDEX.md exists and is staged; then stages a spec adding status done with a staged diff over 200 KB and a stub docs-audit.mjs that appends each argv to a log: exactly one --gate-file line; RED on the baseline for the ps1-written hook (index absent) | `patch:docs/ai/tdd/spec-git-hook-bodies-single-source/mutation-TEST-3436.patch` on .aai/templates/git-hooks/pre-commit-index.sh | pending |
| TEST-3437 | Spec-AC-06 | inspection | tests/skills/test-aai-git-hook-templates.sh | test_3437_no_early_reader sources tests/skills/lib/pipe-grep-q-ratchet.sh and counts PGQ_PATTERN matches with /usr/bin/grep -cE in each template (want 0); positive control: the hookBody here-string of git show 244ef0bf:.aai/scripts/install-pre-commit-hook.ps1 gives 5 | `patch:docs/ai/tdd/spec-git-hook-bodies-single-source/mutation-TEST-3437.patch` on .aai/templates/git-hooks/pre-commit-index.sh | pending |
| TEST-3438 | Spec-AC-07 | integration | tests/skills/test-aai-git-hook-templates.sh | test_3438_missing_template vendors both installers with vendor_hook_installer into scratch roots, removes one template at a time (four rounds), and per installer requires exit 1, the D-MISSING line naming the absolute path on stderr, and every hook slot unchanged (a pre-seeded AAI pre-push stays byte-identical, absent slots stay absent); --print of the removed token exits 1 with the line; --uninstall exits 0; the ps1 half needs pwsh | `sed:s/ERROR: AAI hook template missing: /ERROR: template missing: /` on .aai/scripts/install-pre-commit-hook.sh | pending |
| TEST-3439 | Spec-AC-08 | integration | tests/skills/test-aai-git-hook-templates.sh | test_3439_crlf_and_rerun converts the vendored templates to CRLF, installs with each installer (ps1 under pwsh) into twin repos, requires no CR byte and cmp equality; then re-runs each installer over hooks the other wrote and requires all three byte-identical and the three already-installed lines on stdout | `sed:s/tr -d .\\r./cat/` on .aai/scripts/install-pre-commit-hook.sh | pending |
| TEST-3440 | Spec-AC-09 | integration | tests/skills/test-aai-git-hook-templates.sh | test_3440_refguard_message_and_doctor requires the five D-MSG lines and the refused line in the template; arms a scratch repo with each installer (ps1 under pwsh) and requires aai-doctor.mjs --json --root to report CAT-17 armed for both; runs the seven test-aai-git-ref-guard.sh selectors of Spec-AC-09 (exit 0) | `sed:s/^AAI:REF-GUARD refused this/AAI-REF-GUARD refused this/` on .aai/templates/git-hooks/reference-transaction.sh | pending |
| TEST-3441 | Spec-AC-10 | e2e | tests/skills/test-aai-git-hook-templates.sh | test_3441_downstream_install runs aai-sync.sh --profile core into a scratch git target named with a space, requires the four templates there cmp-equal to the source, runs the target's own sh installer from inside the target (and its ps1 under pwsh when present) and cmp-compares the three hooks with the D-COMPOSE bytes; requires each template once under core in PROFILES and runs test-aai-layer-profiles.sh test_manifest_conformance (exit 0) | `sed:s/^  - \.aai\/templates\/git-hooks\/pre-push\.sh$/  - .aai\/templates\/git-hooks\/pre-push-gone.sh/` on .aai/system/PROFILES.yaml | pending |
| TEST-3442 | Spec-AC-11 | inspection | tests/skills/test-aai-git-hook-templates.sh | test_3442_fixtures_use_helper requires vendor_hook_installer in each Measurements fixture function and no cp of a path ending install-pre-commit-hook.sh or .ps1 in any tests/skills/*.sh but the helper (positive control: a scratch copy of one suite with a bare cp is reported); runs the six Spec-AC-11 selectors (exit 0) | `sed:s/cp -R "\$src\/.aai\/templates\/git-hooks"/: cp -R "$src\/.aai\/templates\/git-hooks"/` on tests/skills/lib/vendor-hook-installer.sh | pending |
| TEST-3443 | Spec-AC-12 | inspection | tests/skills/test-aai-git-hook-templates.sh | test_3443_wiring pipes each template, both installers, the helper and the Pester file to node .aai/scripts/select-suites.mjs --files-from - and requires aai-git-hook-templates (and the five helper suites for the helper); requires the suite-weights row; runs test-aai-hygiene-pack.sh test_090_suite_map_pin and test_129_mutation_gate_suite_registration; runs nested-suite-lint with its allowlist, check-cd-subshell-leak, check-test-registration and the pipe-grep-q ratchet check; requires the templates glob in both ps1-quality path lists and runs test-aai-win-fallback.sh test_034; requires the D-EOL line in .gitattributes | `sed:s/^      - \.aai\/templates\/git-hooks\/\*\*$/      - .aai\/templates\/git-hooks-gone\/**/` on tests/skills/suite-map.yaml | pending |
| TEST-3444 | Spec-AC-13 | inspection | tests/skills/test-aai-git-hook-templates.sh | test_3444_line_budget_and_rfc counts lines with wc -l and code lines with grep -cvE on the hash-comment and blank pattern under bash with /usr/bin/grep when present: sh at most 1050 and 560, ps1 at most 840 and 570, templates together at most 330; prints before (1313/749, 1097/749, embedded 312/217 and 308/216) and after; runs test-aai-expert-fetch.sh test_2624_inventory_matches_tree (exit 0) and requires the D-RFC sentence once in the phase 5 row with status in progress and a link ending git-hook-bodies-single-source.md | `sed:s/The eighth slice \[moved the git hook bodies to shared templates\]/The eighth slice [moved the hook bodies]/` on docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md | pending |

Test counts by type: inspection 6, integration 7, e2e 1 (13 rows; the
Pester file adds at least 6 cases inside TEST-3435).

The mutation strings name the expected implementation shapes (for example
`$prePushBytes`, `tr -d` for D-EOL, the helper's `cp -R` line); TDD may pick
different spellings and then re-points the mutation at the same behaviour
before the row turns green, recording it in the mutation record. The two
`patch:` mutations are written at GREEN: TEST-3436's turns the here-string
of the staged-name check back into a pipe into `grep -qE`; TEST-3437's adds
one pipe into `head -1`.

Seams crossed (Principle 2): each installer and the template files it reads
(TEST-3433, TEST-3434, TEST-3438, TEST-3439); the written hook and git's
bash running it under pipefail on a payload large enough to outrun the
reader (TEST-3436); the reference-transaction hook and aai-doctor's CAT-17
probe reading its stderr marker (TEST-3440); aai-sync's core profile copy
and the target's own installers (TEST-3441); each installer under every
engine that runs it (TEST-3434, TEST-3435; Windows PowerShell 5.1 and pwsh 7
on native Windows in H1); the fixtures of five other suites and the shared
helper (TEST-3442); select-suites, the hygiene pins, the nested-suite lint,
the cd ratchet, the registration check and the pipe-grep ratchet reading the
new suite (TEST-3443); the ps1-quality path lists read by win-fallback
`test_034` (TEST-3443); the RFC inventory read by `test_2624` (TEST-3444).

## Verification

- `env -u AAI_ROLE -u AAI_GIT_WRITE bash tests/skills/test-aai-git-hook-templates.sh`
  exits 0 (13 rows), plus the touched and selected suites, each with
  `env -u AAI_ROLE -u AAI_GIT_WRITE`: test-aai-hygiene-pack.sh,
  test-aai-git-ref-guard.sh, test-aai-doctor.sh, test-aai-docs-audit.sh,
  test-aai-tracked-ignored.sh, test-aai-release.sh, test-aai-layer-profiles.sh,
  test-aai-expert-fetch.sh, test-aai-win-fallback.sh, test-aai-suite-select.sh,
  test-aai-sync.sh (if selected), test-ps1-quality.sh (if selected). No full
  sweep is required by this spec; Validation decides its own.
- Unchanged surfaces, recorded in the validation report:
  `git diff --stat 244ef0bf -- .aai/scripts/pre-commit-checks.sh .aai/scripts/pre-commit-checks.ps1 .aai/scripts/claude-hook-gate.sh .aai/AGENTS.md`
  prints nothing, and no `.aai/*.prompt.md` differs from `244ef0bf`.
- The guard block is unchanged:
  `git show 244ef0bf:.aai/scripts/install-pre-commit-hook.sh` piped through
  the `--print guard-checks` awk of that commit equals
  `.aai/templates/git-hooks/pre-commit-guard-checks.sh` byte for byte.
- `node .aai/scripts/spec-lint.mjs --path <this spec>` and
  `node .aai/scripts/mutation-gate.mjs` for this spec pass.
- H1 (hosted): the ps1-quality Windows jobs pass under Windows PowerShell 5.1
  and pwsh 7 with `install-pre-commit-hook.Tests.ps1` discovered and not
  skipped.

## Evidence contract

ref_id `git-hook-bodies-single-source`; RED, GREEN and mutation evidence
under `docs/ai/tdd/git-hook-bodies-single-source/` (gitignored); each AC
row's Evidence names its green log and mutation record; the validation
report and review verdict under `docs/ai/reports/` and `docs/ai/reviews/`.

### Evidence by strategy

tdd: a stored RED artifact per AC-gating test plus the verification matrix
above.

## Residual risks

- Windows PowerShell 5.1 parity is proven only on the hosted job (H1);
  Planning had no Windows engine.
- A hook already installed downstream keeps its old bytes, including the
  early-closing pipes of a `.ps1`-written pre-commit hook, until a `--force`
  or `-Force` re-install: a plain run leaves an AAI-managed hook alone by
  design. The CHANGELOG says so; refreshing a known old shipped body in
  place is left to ride 11 (slot attestation and upgrade).
- The pipefail fixture depends on the pipe buffer being smaller than the
  staged payload (230940 bytes against a 64 KB buffer on the measured host);
  a host with a larger buffer would make the RED weaker, never the GREEN.
- The nine open `fu-ps1-*` installer items (flag lattice, decline wording,
  symlinked config, Write-Error exit codes, seed line endings) concern the
  installers' flag and config handling, not the hook bodies; they stay open
  for ride 11.

Registry items closed by this scope: none. The open installer items
(`fu-ps1-writeerror-terminates-before-exit`, `fu-ps1-symlink-config-replaced`,
`fu-ps1-decline-not-disclosed`, `fu-ps1-refusal-no-manual-merge`,
`fu-installer-flag-lattice-no-mode`, `fu-ps1-decline-force-advice-wrong`,
`fu-ps1-enable-refguard-no-rationale`, `fu-ps1-setcontent-rewrites-seed-eol`,
`fu-three-readers-three-whitespaces`) are about flags and the config file,
which this scope does not change; `fu-pre-commit-checks-pipe-grep-q` is
ride 5 (L3).
