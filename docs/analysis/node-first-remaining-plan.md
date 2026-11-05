# What is left of the Node-first migration, and in which order (2026-11-05)

Scope: the shipped `.aai/scripts/*.sh` and `*.ps1` that still carry logic,
measured on `main` at `17ff82fc`, for RFC-0017 phase 5 ("migrate remaining
process adapters only with native evidence"). Read-only analysis; nothing
was changed while measuring. Owner decisions taken on this plan are in
section 4.

## 1. How it was measured

- Code lines: non-blank, non-comment lines (`grep -cvE '^\s*(#|$)'`), so
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
| aai-canonicalize | 223/228 | retire | one-off; 0 commits since 2026-07-27 |
| aai-update | 122/138 | port, 1 slice | after the Node-prerequisite decision (section 4) |
| migrate-state-to-local | 122/143 | retire, print a `git rm --cached` hint | legacy RFC-0001 migration |
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
| 1 | retire-legacy-migrations | retire migrate-yaml-to-jsonl, migrate-state-to-local, aai-canonicalize (one release as a deprecation launcher) | yes |
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
