# What is left of the Node-first migration, and in which order (2026-11-05)

Scope: the shipped `.aai/scripts/*.sh` and `*.ps1` that still carry logic,
measured on `main` at `17ff82fc`, for RFC-0017 phase 5 ("migrate remaining
process adapters only with native evidence"). Read-only analysis; nothing
was changed while measuring. Owner decisions taken on this plan are in
section 4.

## 1. How it was measured

- Code lines: non-blank, non-comment lines (`grep -cvE '^[[:space:]]*(#|$)'`), so
  headers and comment blocks do not count as logic.
- Callers: tracked files naming `<script>.sh|.ps1`, docs history excluded,
  counted with `/usr/bin/grep` under bash (not `grep -rl` totals).
- Twin duplication: for each `.sh`/`.ps1` pair, the smaller side's code
  lines.
- Timings: a scratch detached worktree on the same commit, removed after.

The paired files total about 12,000 lines, but real twin duplication is
about 3,020 code lines. The rest is comments, scripts with no twin
(`aai-bootstrap.sh`, `claude-hook-gate.sh`) and a dispatcher that is not a
twin (`aai-run-tests.ps1`).

## 2. Per script

| Script | Code sh/ps1 | Recommendation | Main reason |
|---|---|---|---|
| install-pre-commit-hook | 749/749 | port, 3 slices, after the parity harness | ~750 duplicate lines; 9 open `fu-ps1-*` items; the `.ps1` has no Pester, only ~99 source-shape pins |
| aai-sync | 784/871 | port, 4 slices, last | main consumer install path; ~780 duplicate lines |
| aai-bootstrap | 920/none | port, 3 slices | no twin; gains a native Windows bootstrap |
| aai-run-tests | 441/522 | keep native | the `.ps1` is a WSL/Git-Bash dispatcher, not a twin; per-suite overhead (~0.9 s vs 0.07 s direct, n=2) is the isolation clone, not the shell |
| claude-hook-gate | 341/none | port, 1-2 slices, keep a bash pre-filter | closes P1 `fu-platform-adapter-hook-gate`; 7 `\| grep -q` sites under pipefail |
| autonomous-loop | 409/384 | retire | superseded by `/aai-loop`; 1 commit in 60 days, 0 METRICS/EVENTS mentions; only source-shape pins |
| aai-release | 290/351 | port, 2 slices | highest-churn twin (6 commits in 60 days) |
| pre-commit-checks | 239/221 | retire the `.ps1`, keep the `.sh` | the `.ps1` has no runtime caller; git hooks always run under Git's shell |
| aai-canonicalize | 223/228 | retire together with the `/aai-canonicalize` skill | one-off; 0 commits since 2026-07-27; `SKILL_CANONICALIZE.prompt.md` and `SKILLS.md` still invoke and advertise it, so the skill, its wrappers and catalog rows retire in the same ride |
| aai-update | 122/138 | port, 1 slice | after the Node-prerequisite decision (section 4) |
| migrate-state-to-local | 122/143 | port, 1 slice (not retire) | live callers: `aai-doctor.mjs` and both `aai-sync` twins direct legacy projects to it, and it does more than a `git rm --cached` (untracks several state and evidence paths, adds ignore entries, creates `EVENTS.jsonl`) |
| migrate-yaml-to-jsonl | 78/99 | retire | unchanged since 2026-03-03; needs python3 + PyYAML |
| cloudflare-share | 51/47 | port, 1 slice | cheapest real port; fixes the macOS `grep -oP` failure |
| aai-win-selftest.ps1 | 270 | keep native | inherently a PowerShell engine probe |

Already thin launchers: aai-reap-tests, validate-skills, aai-live, triage,
expert-fetch, live-spool.

Speed is not a reason to port. A README-only commit spends 7.3-7.9 s in
`pre-commit-checks.sh` (n=3); 6.65 s of it is `allocate-doc-number.mjs
--guard` (one traced run), the bash part is ~0.7 s.

## 3. Rides, in order

Ordering: retirements and dead twins first (most lines for least risk),
then live parity bugs with a small surface, then the high-churn and P1
surfaces, and the install/update path last, behind a parity harness that
runs on native Windows. Each port follows the reaper precedent (CHANGE-0241):
one Node module, thin launchers, `node:test` for every drift found, Pester
under 5.1 and 7, and a scratch `aai-sync` install proving the launchers.

| # | Roadmap ref | Scope | Owner sign-off |
|---|---|---|---|
| 1 | retire-legacy-migrations | (a) retire migrate-yaml-to-jsonl and aai-canonicalize with the `/aai-canonicalize` skill (prompt, wrappers, `SKILLS.md`, profiles), one release as a deprecation launcher saying the skill is retired; (b) port migrate-state-to-local to one Node module with thin launchers, same effects, callers unchanged | yes |
| 2 | retire-shell-loop-runner | retire autonomous-loop (one release as a deprecation launcher pointing at `/aai-loop`) | yes |
| 3 | cloudflare-share-on-node | one share module with an injectable deploy seam | no |
| 4 | git-hook-bodies-single-source | the three hook bodies both installers embed move to shared templates; fixes 4 `cmd \| grep -q` sites under pipefail in the `.ps1`-written pre-commit body | yes |
| 5 | pre-commit-checks-ps1-retire | retire the uncalled `.ps1`, fix the `.sh` pipe-grep (`fu-pre-commit-checks-pipe-grep-q`); L3 | yes |
| 6 | release-on-node | (a) changelog rollup and unlogged-PR classification in Node; (b) tag, publish and PR on the platform adapter, then delete the twins | merge by the owner |
| 7 | hook-gate-on-node | one decision module, bash pre-filter kept; also lists the hook gate under L3 (section 4) | yes |
| 8 | install-path-parity-harness | runs both twins of sync, update and the hook installer into scratch targets and diffs trees and exit codes, on Linux/macOS and the native Windows 5.1/7 job | no |
| 9 | bootstrap-on-node | (a) detection and planning; (b) rendering and writes; (c) hooks overlay, platform record, launchers | yes |
| 10 | update-on-node | aai-update as a Node module | yes |
| 11 | pre-commit-installer-on-node | (a) one resolved mode and guard policy through guard-config; (b) slot attestation and upgrade; (c) launchers and pin migration | yes |
| 12 | sync-on-node | (a) gitignore reconcile; (b) profile, copy plan, prune; (c) drop legacy-layout moves; (d) launchers, delete twins | yes |

Status (2026-11-22): rides 1 to 12 are delivered; section 6 re-measures what remains.

Optional later: move only the `iso_*` isolation policy of aai-run-tests
into Node for testability; supervision stays in bash.

## 4. Owner decisions (2026-11-05)

1. Node is a hard prerequisite on the install and update path. Launchers
   refuse without Node and print an install hint, as the reaper does. This
   unblocks rides 9-12.
2. Retired scripts stay one release as a deprecation launcher that names the
   replacement, then are deleted.
3. `claude-hook-gate.sh` becomes L3-protected (added to the protected paths
   list in ride 7).
4. The local pre-commit hook of this repository was reinstalled; it had been
   the June body without the GUARD-CHECKS block.

## 5. When phase 5 counts as done

- Every `.sh`/`.ps1` in `.aai/scripts` is a thin launcher (20 lines or
  fewer, no policy), on a "kept native" list in RFC-0017 with its reason
  (`aai-run-tests.sh`, `aai-run-tests.ps1`, `aai-win-selftest.ps1`,
  `pre-commit-checks.sh`), or deleted.
- Twin duplication is 0, re-measured with the method in section 1.
- The parity harness and Pester pass on Linux, macOS, PowerShell 5.1 and
  pwsh 7, and a scratch `aai-sync` install runs every launcher.
- No open P1/P2 node-first, release-adapter or hook-gate follow-ups.

Caveat: line counts and timings are single-host measurements on one
commit; they size the rides, they are not acceptance thresholds.

## 6. Re-measure after ride 12 (2026-11-22)

Measured with the method of section 1 (non-blank, non-comment lines, `/usr/bin/grep -cvE` under bash) over every tracked `.sh` and `.ps1` under `.aai/scripts/`, `lib/` included, on the tree that delivers ride 12 (sync-on-node). A file is a `launcher` when it has 20 code lines or fewer and names no policy (git, a profile, `.gitignore`, `PROFILES`); a `deprecation launcher` when its first lines say RETIRED; `kept native` when the table "Kept native scripts" of RFC-0017 names it with its reason; otherwise `logic`. The table lists every file that is not a `launcher`; the launchers are not listed. Rides 1 to 12 of section 3 are delivered; this section says what is left of phase 5.

| File | Code lines | Class | Reason or next step |
|---|---|---|---|
| `.aai/scripts/aai-canonicalize.ps1` | 2 | deprecation launcher | the retirement launcher stays one release (owner decision 2 of this plan) and is deleted in the next release |
| `.aai/scripts/aai-canonicalize.sh` | 2 | deprecation launcher | the retirement launcher stays one release (owner decision 2 of this plan) and is deleted in the next release |
| `.aai/scripts/aai-release.ps1` | 25 | logic | the PowerShell launcher marshals the parameter block into Node arguments, which is more than the 20-line form of the other launchers. Next step: reduce it to the argument marshalling of aai-sync.ps1 or list it as kept native |
| `.aai/scripts/aai-run-tests.ps1` | 525 | kept native | a WSL and Git-Bash dispatcher of the bash runner, not a twin of it |
| `.aai/scripts/aai-run-tests.sh` | 540 | kept native | supervises suite processes, timeouts and orphan cleanup in bash; the per-suite cost is the isolation clone, not the shell |
| `.aai/scripts/aai-win-selftest.ps1` | 270 | kept native | inherently a PowerShell engine probe |
| `.aai/scripts/autonomous-loop.ps1` | 2 | deprecation launcher | the retirement launcher stays one release (owner decision 2 of this plan) and is deleted in the next release |
| `.aai/scripts/autonomous-loop.sh` | 2 | deprecation launcher | the retirement launcher stays one release (owner decision 2 of this plan) and is deleted in the next release |
| `.aai/scripts/claude-hook-gate.sh` | 63 | logic | the bash pre-filter of the hook-gate ride (an L3 protected surface): it starts no Node process for a command that cannot concern a gate. Next step: owner decision to list it as kept native with that reason, or move the pre-filter into the Node module behind a 20-line launcher |
| `.aai/scripts/lib/append-lock.sh` | 50 | logic | serialised appends to the append-only ledgers in bash; the Node side has lib/append-lock.mjs. Next step: retire with the last bash caller, or list as kept native |
| `.aai/scripts/lib/git-bash-path.sh` | 45 | logic | in-process Windows to Git Bash path translation, sourced by aai-run-tests.sh. Next step: list as kept native with the runner, or fold into it |
| `.aai/scripts/lib/repo-tripwire.sh` | 158 | logic | the shipping-repository write tripwire, sourced by aai-run-tests.sh. Next step: as lib/test-residue.sh |
| `.aai/scripts/lib/test-residue.sh` | 526 | logic | removes the residue one test run provably created, sourced by aai-run-tests.sh. Next step: list it as kept native with the runner it serves, or port it with the optional move of the isolation policy to Node |
| `.aai/scripts/migrate-yaml-to-jsonl.ps1` | 2 | deprecation launcher | the retirement launcher stays one release (owner decision 2 of this plan) and is deleted in the next release |
| `.aai/scripts/migrate-yaml-to-jsonl.sh` | 2 | deprecation launcher | the retirement launcher stays one release (owner decision 2 of this plan) and is deleted in the next release |
| `.aai/scripts/pre-commit-checks.ps1` | 2 | deprecation launcher | the retirement launcher stays one release (owner decision 2 of this plan) and is deleted in the next release |
| `.aai/scripts/pre-commit-checks.sh` | 390 | kept native | git hooks always run under Git's shell; an L3 protected surface |

- Twin duplication: 0 code lines (a pair counts only when both files are logic; the only pair left that is not a launcher pair, `aai-run-tests`, is kept native and its `.ps1` is a dispatcher, not a twin).
- Parity harness and Pester (H1 to H3): pending, read from the pull request's ps1-quality run (the harness with the sync scenarios on pairs sh:ps1, sh:node and ps1:node, `aai-sync.Tests.ps1` with its five cases, and the Windows PowerShell 5.1 smoke through the launcher).
- Open P1 and P2 follow-ups whose ref is one of the twelve roadmap refs of section 3, `install-path-parity-harness` or starts with `node-first` (from `follow-ups.mjs list --status open --json`; the owner sign-off items `fu-amend-*` are counted by `spec-amend.mjs list`):

| Follow-up | Severity | Ref |
|---|---|---|
| `fu-cfshare-redact-escape-robust` | P2 | cloudflare-share-on-node |
| `fu-parity-win-odd-root-dirs` | P2 | install-path-parity-harness |

Phase 5 is not done: six files still carry logic, two P2 follow-ups of the plan's refs are open and the hosted checks are not yet read. RFC-0017 keeps the status `in progress` and its row names this list.

## 7. Re-measure after the phase 5 closeout (2026-11-23)

Measured with the method of section 1 (non-blank, non-comment lines, `/usr/bin/grep -cvE` under bash; the shared classifier `tests/skills/lib/script-classes.mjs` counts the same lines) over every tracked `.sh` and `.ps1` under `.aai/scripts/`, `lib/` included, on the tree of the node-first-phase5-closeout ride. A file is a `launcher` when it has 20 code lines or fewer and names no policy (git, a profile, `.gitignore`, `PROFILES`); a `deprecation launcher` when its first lines say RETIRED; `kept native` when the table "Kept native scripts" of RFC-0017 names it with its reason; otherwise `logic`. The table lists every file that is not a `launcher`; the launchers are not listed. Section 6 stays as written, a dated record of the tree before this ride.

| File | Code lines | Class | Reason or next step |
|---|---|---|---|
| `.aai/scripts/aai-canonicalize.ps1` | 2 | deprecation launcher | the retirement launcher stays one release (owner decision 2 of this plan) and is deleted in the next release |
| `.aai/scripts/aai-canonicalize.sh` | 2 | deprecation launcher | the retirement launcher stays one release (owner decision 2 of this plan) and is deleted in the next release |
| `.aai/scripts/aai-run-tests.ps1` | 525 | kept native | a WSL and Git-Bash dispatcher of the bash runner, not a twin of it |
| `.aai/scripts/aai-run-tests.sh` | 540 | kept native | supervises suite processes, timeouts and orphan cleanup in bash; the per-suite cost is the isolation clone, not the shell |
| `.aai/scripts/aai-win-selftest.ps1` | 270 | kept native | inherently a PowerShell engine probe |
| `.aai/scripts/autonomous-loop.ps1` | 2 | deprecation launcher | the retirement launcher stays one release (owner decision 2 of this plan) and is deleted in the next release |
| `.aai/scripts/autonomous-loop.sh` | 2 | deprecation launcher | the retirement launcher stays one release (owner decision 2 of this plan) and is deleted in the next release |
| `.aai/scripts/claude-hook-gate.sh` | 63 | kept native | the bash pre-filter of the Claude hook gate: it starts no Node process for a command that cannot concern a gate, so an ordinary agent shell command pays no Node start; an L3 protected surface (owner decision 2026-11-23) |
| `.aai/scripts/lib/append-lock.sh` | 50 | kept native | sourced by the bash suite framework tests/skills/test-framework.sh: serialised appends to the append-only run ledger; the Node callers use lib/append-lock.mjs (owner decision 2026-11-23) |
| `.aai/scripts/lib/git-bash-path.sh` | 45 | kept native | sourced by aai-run-tests.sh, which stays bash: in-process Windows to Git Bash path translation (owner decision 2026-11-23) |
| `.aai/scripts/lib/repo-tripwire.sh` | 158 | kept native | sourced by aai-run-tests.sh, which stays bash: the shipping-repository write tripwire around each suite (owner decision 2026-11-23) |
| `.aai/scripts/lib/test-residue.sh` | 526 | kept native | sourced by aai-run-tests.sh, which stays bash: removes the residue one test run provably created, inside the supervising shell (owner decision 2026-11-23) |
| `.aai/scripts/migrate-yaml-to-jsonl.ps1` | 2 | deprecation launcher | the retirement launcher stays one release (owner decision 2 of this plan) and is deleted in the next release |
| `.aai/scripts/migrate-yaml-to-jsonl.sh` | 2 | deprecation launcher | the retirement launcher stays one release (owner decision 2 of this plan) and is deleted in the next release |
| `.aai/scripts/pre-commit-checks.ps1` | 2 | deprecation launcher | the retirement launcher stays one release (owner decision 2 of this plan) and is deleted in the next release |
| `.aai/scripts/pre-commit-checks.sh` | 390 | kept native | git hooks always run under Git's shell; an L3 protected surface |

- Twin duplication: 0 code lines (a pair counts only when both files are logic; no file is logic now, and `aai-run-tests.ps1` is a dispatcher of the kept native bash runner, not a twin of it).
- Parity harness and Pester (H1 to H3): passed on 5af29daa2affcf4f1859fedf7bb98dc97a8f078c (ps1-quality run 45258428645): windows-5_1 (Windows PowerShell 5.1 and pwsh 7 legs), windows-parity with the launcher twin and the AAI-HOST-CHECK lines, windows-wsl1 and the Linux gate. The skill-suite run 45258436994 on the same head also passed; the full skill-suite is read again on the pull request's final head before merge (D-HOSTED step 5).
- Root cause of fu-parity-win-odd-root-dirs: not named after three hosted diagnostic runs (D-ODD step 6): the frozen bash updater path reproduces the odd root entries (AAI-ODD-SEEN UP-01 sh entries=4, under Windows PowerShell 5.1 and pwsh 7) while the shipped launcher and node module path leave none (entries=0), every AAI-HOST-CHECK passes and each of the nine doctor candidates re-run alone is born=0, shown by ps1-quality run 45115879244
- Open P1 and P2 follow-ups whose ref is one of the twelve roadmap refs of section 3, `install-path-parity-harness` or starts with `node-first` (from `follow-ups.mjs list --status open --json`; the owner sign-off items `fu-amend-*` are counted by `spec-amend.mjs list`):

| Follow-up | Severity | Ref |
|---|---|---|
| none | - | - |

- Open P2 follow-ups outside the plan refs, not counted: `fu-hook-gate-skips-renamed-doc` (ref precommit-residual-defects: the pre-commit index lists staged docs under default rename detection, a pre-commit script defect outside the launcher classification), `fu-release-pwsh-identity-crash` (ref release-corpus-hermetic: the dry-run test accepts pwsh crash output as a version, a test assertion and not the launcher) and `fu-release-preflight-scrubbed-env` (ref release-same-version-recovery: the release preflight runs repository tests with the operator environment, not the launcher or the module grammar).

Phase 5 is done by owner decision (2026-11-23): no file carries logic, twin duplication is 0 and the hosted parity and Pester runs passed, but the cause of `fu-parity-win-odd-root-dirs` was not named after three hosted diagnostic runs, so the owner downgraded that item to P3. It is dropped as superseded by the open P3 successor `fu-parity-win-odd-root-cause` (ref install-path-parity-harness), not closed as fixed, and the cause stays open there. The decision rests on the frozen bash updater leaving three or four odd root entries per run (AAI-ODD-SEEN UP-01 sh entries=3 or 4) while the shipped launcher and node module path leave none (entries=0), under Windows PowerShell 5.1 and pwsh 7, in ps1-quality runs 45115879244, 45199618817, 45202686129 and 45222012849, and on each of the nine doctor candidates re-run alone being born=0. No open P1 or P2 follow-up of the plan's refs remains, and RFC-0017 phase 5 reads `done`.
