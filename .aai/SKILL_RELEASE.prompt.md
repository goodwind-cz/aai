# Release Skill - Cut and Finish a Release

## Goal
Roll root `CHANGELOG.md` `[unreleased]` sections in an isolated temporary
worktree, push `chore/release-<version>`, and finish its release PR in one
operator-confirmed run. CI `release.yml` tags the merge SHA and publishes all
rolled sections. Verify publication before leased cleanup and safe base sync.

## Usage
```bash
/aai-release                          # plan only, zero writes
/aai-release --dry-run                # explicit plan; wins over --confirm
/aai-release --version v1.2.3         # verbatim version, any scheme
/aai-release --confirm                # cut and finish this release PR
/aai-release --version v1.2.3 --confirm # resume this explicit version
/aai-release --confirm --no-remote    # local cut; remote finish skipped
```

`--version` defaults to UTC CalVer `vYYYY.MM.DD` (`AAI_RELEASE_DATE` pins
the date). `--yes` aliases confirm; `AAI_RELEASE_NO_REMOTE=1` aliases
no-remote. Bare/dry-run, including dry-run plus confirm, writes no objects,
refs, FETCH_HEAD, index, files, journal or GitHub state. Remote preview needs
available objects: if the observed remote base object is missing, relay the
printed fetch-before-preview remedy and stop; do not fetch during preview.

## Instructions
Run from the target repository, forwarding user flags verbatim. Do not
implement the transform, checks or finish stages by hand:
```bash
.aai/scripts/aai-release.sh
```
```powershell
.aai/scripts/aai-release.ps1
```
Relay a short report: version, plan/cut, branch, PR URL, merge SHA, verified
tag SHA and release URL, cleanup and base sync result. Relay named skips and
refusals verbatim. On failure stop, report completed irreversible steps and
show the exact version-specific resume command; never change flags yourself.
Resume uses durable repository-local metadata and reread remote facts, without
duplicate PRs, merges, tags or releases. It does not silently absorb a moved
base: the same version can keep refusing. Operator recovery requires a fresh
audited cut or deliberate repair of the retained PR/journal, not automatic
rebase or deletion of progress.

## Audit and remote snapshot
Resolve the authoritative remote base SHA, not a possibly stale tracking ref
or detached caller HEAD. Confirm can obtain missing objects with no tracking
ref or FETCH_HEAD update. Roll and audit the same verified snapshot before
release branch, commit, push or PR creation. The shared `release-notes-gate.mjs` classifier checks
Git old/new modes as well as paths, including extensionless executables. Genuine
unnoted shipped history refuses; proven CHANGELOG-only, previous release PRs,
and valid same-line nonempty `no-notes: <reason>` history are exempt. Missing
history or required PR metadata never guesses clean.

Recheck the audited remote base before resumed preparation, waiting and merge.
An observed move refuses and retains progress. `--match-head-commit` pins only
the PR head: a base push between the last observation and GitHub's merge can
enter the merge unseen. No atomic base condition, universal audit of eventual
merge history or publication-prevention guarantee is promised for that race.

## Authorization and safety
- Never add confirm/yes yourself. Owner confirmation authorizes only this
  invocation's release PR: repository, version, base, branch and pushed head.
  Resume must prove the binding again; other PRs retain operator-only merge.
- Wait for all required checks to pass. Real pending exit8 reaches the watcher;
  failed, degraded, empty or malformed checks refuse. Squash-merge only the
  bound PR with `--match-head-commit <pushed-head>`; no auto/admin bypass.
- Await successful `release.yml` on the merge SHA; verify the peeled remote
  tag SHA and complete release body before cleanup. Delete remotely using an
  expected-head lease and refuse dependent PRs or changed branches. Safely
  fast-forward an available registered base checkout. Preserve unrelated
  dirty/detached/feature caller bytes; never stash/reset/overwrite or prune.
- No-remote makes a local cut with a named remote-finish skip. Without
  `release.yml`, report the manual-tagging skip after merge; the client never
  publishes tags/releases. No registered base means a named base-sync skip.
  Failed publication can leave a merged PR/tag; there is no rollback claim.

## Exit codes
- exit 1 = bad arguments
- exit 10 = not a git repository
- exit 11 = missing root CHANGELOG.md
- exit 12 = malformed unreleased heading/body
- exit 13 = no rollable entries
- exit 15 = existing tag without bound resumable progress
- exit 16 = gh absent/unauthenticated on the remote path
- exit 8 = finish pending (merge queue or branch policy); relay `PENDING` and the exact resume command, not a failure
- exit 20 = finish refused; relay one named cause and exact version-specific resume. On remote `--confirm`, 12/13/15/16 conditions surface as 20 with that cause
