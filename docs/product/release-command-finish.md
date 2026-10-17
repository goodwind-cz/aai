---
id: release-command-finish
type: product
capability: release-command-finish
status: current
delivered_by:
  - CHANGE-0213
  - release-command-finish
spec: docs/specs/SPEC-0233-spec-release-command-finish.md
updated: 2026-10-17
---

# Complete and resume a release

## What it does

The release command prepares a release PR, waits for required checks, merges its bound head, verifies CI publication, and cleans up safely. Repeating confirmation with the same explicit version resumes unfinished stages. Hosted proof: ps1-quality runs 39016764123, 39020377328 and 39022783097 passed on Windows PowerShell 5.1, Windows pwsh 7 and Linux (20 consecutive native-capture repetitions, no skips); the worktree-identity probe passed on win32.

## How to use it

Use Git, Node.js and authenticated GitHub CLI in the target checkout:

```sh
bash .aai/scripts/aai-release.sh --dry-run --version v1.2.3
bash .aai/scripts/aai-release.sh --confirm --version v1.2.3
```

PowerShell uses `powershell -NoProfile -File .aai/scripts/aai-release.ps1 -Version v1.2.3 -Confirm`, or `pwsh` with the same parameters. Omit confirmation to preview; dry-run wins even alongside confirmation. Versions default to UTC CalVer `vYYYY.MM.DD`; `AAI_RELEASE_DATE` pins the date. Resume with the exact explicit version printed in the failure's executable resume command.

Remote preview reads the authoritative base SHA but never fetches missing objects. If its object is unavailable, follow the printed fetch-before-preview remedy, then preview again. Confirm may fetch missing objects without changing tracking refs or FETCH_HEAD, and audits that exact remote snapshot before preparing release mutations. The audit derives its previous-release boundary from authoritative remote tags and their peeled commits, even when local tag refs are absent. Incomplete or unavailable history refuses; a true first release audits the complete shipped history. Genuine unnoted shipped history refuses; CHANGELOG-only history, proven previous release PRs and valid same-line nonempty `no-notes: <reason>` markers are exempt under the existing notes classifier. A shipped PR counts as noted when its `#N` or title is in the rolled notes, or when an `## [unreleased] — <title>` heading it added is present (rewritten to the version) among the rolled headings, so slug-cited headings need no `#N`. Only tags matching `v?[0-9]` are release boundaries; tags that do not peel to a commit are ignored.

`--no-remote` / `-NoRemote`, or `AAI_RELEASE_NO_REMOTE=1`, makes a local cut with a named remote-finish skip. Repositories without `release.yml` receive a manual-tagging skip after merge. The client does not publish tags or releases directly.

## Data model

Each version has a JSON journal in the shared Git metadata directory at `aai/releases/<SHA256-of-version>.json`. It binds repository/origin, version, base ref/SHA, release branch/prepared head, PR number, merge SHA, rolled notes, publication URL, temporary worktree and completed stage. Keep it for resume across registered worktrees. An unrelated existing branch or PR does not become authorized by a matching title.

A per-version `.claim` file carries the running confirmation’s PID, host and ownership token. A second confirmation refuses with `release-busy`; normal success and refusal release only their own claim. A killed same-host owner is automatically recovered only when the OS proves its PID is absent; exclusive generation guards serialize recovery. Live, foreign-host and malformed owners remain held. Repeated crashes inside recovery can reach a bounded conservative refusal requiring operator inspection. The durable journal remains intact; no age-based deletion of release authorization occurs.

Registered-base synchronization uses an exclusive token-owned Git index lock, a private index and a prepared expected-old Git ref transaction. A checkout or base-ref move at the mutation boundary refuses rather than advancing a feature branch. A killed same-host helper can recover its own completed private-index update after the recorded worker PID is proven absent; a live worker, changed caller index/data, failed or incomplete native update, unknown Git lock or foreign owner requires conservative refusal and inspection. These temporary files do not replace or delete the durable authorization journal.

The prepared commit changes only `CHANGELOG.md` and `docs/ai/AAI_VERSION.md`. Required remote PR/check/workflow/tag/release facts are reread on resume. Notes comparison normalizes line endings and outer whitespace.

## Interfaces and contracts

- Shell: bare / `--dry-run` previews; `--confirm --version <version>` completes or resumes; `--no-remote` cuts locally.
- PowerShell: `-DryRun`, `-Confirm`, `-Version`, `-NoRemote` mirror the shell behavior.
- Merge: only the bound release PR is squash-merged after required checks pass, with `--match-head-commit`; no auto/admin bypass. Real pending checks wait; errors, empty/malformed or degraded results refuse. Only required checks are read and watched. If the base uses a merge queue, the PR is enqueued and the command exits 8 with `PENDING: merge-queue` and the resume command (not a refusal); resume once the queue merges it.
- Publication: await successful `release.yml` for the merge SHA; verify the peeled tag SHA and every rolled section in the release body before cleanup.
- Cleanup: expected-head leased deletion refuses moved branches or dependent PRs. Safe registered-base fast-forward preserves unrelated dirty/detached/feature callers; unsafe overlap/divergence refuses, absent base names a skip.
- Audit: commits without a PR number in their subject are classified by their changed paths; a shipped one needs notes it added that survive in the rollup or a `no-notes:` line in its commit message, otherwise `missing-notes` names the commit.
- Version: must match `release.yml`'s tag pattern `v?[0-9]…`; anything else refuses `version` before any GitHub call.
- Result: version, PR, merge/tag SHA, release URL, cleanup and sync status. Finish refusal exits 20 with one named cause, completed facts and an explicit resume command; local/parser exit codes are listed in the release skill.
- Wait limits: `AAI_RELEASE_WAIT_SECONDS` defaults to 3600; `AAI_RELEASE_POLL_SECONDS` defaults to 15.

## Limits and non-goals

The payload and history audit use one observed authoritative remote base snapshot. A move observed before resumed preparation, waiting or merge refuses with `base-moved` and retains progress. Same-version resume deliberately does not rebase or absorb unaudited history and may continue refusing; operator recovery requires a fresh audited cut or deliberate repair of the retained PR/journal.

GitHub's match-head option pins the PR head only. An external race remains: A base push between the final observation and GitHub merge can enter the merge unseen. There is no atomic base condition or guarantee that every commit at the eventual merge was audited. A failed publication can leave an already merged PR/tag; no rollback or globally atomic release is promised.

Confirmation applies only to this invocation's bound repository/version/base/branch/head and its proven resume, not other PRs. Dry-run writes no objects, refs, FETCH_HEAD, index, files, journal or GitHub state. No live end-to-end release has run yet; the first `/aai-release --confirm` after merge is the live proof. Known gaps are tracked as `fu-release-checks-registration-grace` (the first required-checks read can come before GitHub registers checks; resume continues) and `fu-release-notes-heading-multiset` (two PRs adding a byte-identical heading are covered by one surviving heading).

## Links

- Request: [Release completion change](../issues/CHANGE-0213-release-command-finish.md)
- Spec: [Release completion specification](../specs/SPEC-0233-spec-release-command-finish.md)
- Validation evidence: Pending independent validation for this split scope; evidence paths will be added when produced.
