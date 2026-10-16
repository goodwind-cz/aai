---
id: spec-git-platform-detected-at-bootstrap
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: c67fb6591f15f5605b9fcecb0245e2ec0cd3cfe7e4a22ccdcce65454d8d86ab8
ceremony_level: 2
links:
  requirement: git-platform-detected-at-bootstrap
  rfc: null
  pr: []
  commits: []
---

# Spec — bootstrap records the git platform, and /aai-merge runs through one platform adapter (ride 1, closes #468)

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/CHANGE-DRAFT-git-platform-detected-at-bootstrap.md
  (owner decisions 2026-10-16: one CHANGE with GitHub issue #468 as an
  acceptance case; ride 1 is the intake's suggested first slice; full TDD).
- Source issue (untrusted data, quoted in the intake): GitHub issue #468,
  `/aai-merge` refuses with `gh_read_failed` on an Azure DevOps origin.
- Engine: .aai/scripts/merge-cleanup.mjs (`ghPrView`, `ghDependents`,
  `ghApi`, `checkReviewThreads`, `checkRepo`, `readAndGate`, `remoteProof`,
  `runPreflight`).
- Classifier reused, not duplicated: .aai/scripts/pr-platform.mjs
  (`classify`, `extractHost`, `sanitize`, `readOriginUrl`).
- Canon: .aai/SKILL_MERGE.prompt.md (step 1), .aai/SKILL_BOOTSTRAP.prompt.md.
- Bootstrap: .aai/scripts/aai-bootstrap.sh.
- Prior art: docs/specs/SPEC-0218-spec-directed-merge-and-post-merge-cleanup.md
  (D3 the engine never merges, D4 one fixed PR read),
  docs/specs/SPEC-0222-spec-merge-cleanup-delete-remote-branch.md (remote
  branch proofs and dependents reads), SPEC-0103 platform-portable-pr (the
  closed platform set).
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, git CLI, POSIX
  shell plus PowerShell mirrors).

## Registry items closed by this scope

None. `node .aai/scripts/follow-ups.mjs list` at feca6e0b (183 open) holds no
item about platform detection at bootstrap or about `/aai-merge` on Azure.

## Registry items assessed, not closed

- `fu-azure-live-proof-on-adoption` (platform-portable-pr): the live Azure
  round trip. This ride adds new az command shapes but proves them only
  against stubs and the az CLI source; the live proof stays owner-run on the
  downstream Azure repository that reported #468 (intake Verification), so
  the item stays open and gains this ride's shapes as additional scope.
- `fu-merge-preflight-checks-not-started`, `fu-merge-foreign-journal-archive-path`,
  `fu-merge-pending-diverged-regression`, `fu-merge-skip-worktree-hidden-edit`
  (same engine, other subjects; untouched here).
- `fu-constitution-art7-directed-merge` (Article 7 wording; see
  Constitution deviations).
- `fu-shared-page-check-flags-own-pr` (pr-platform.mjs, the shared-page
  check; this ride does not touch that mode).

## Scope of this ride, and what is deferred

In scope (owner's slice, 2026-10-16):

1. Bootstrap detects and records `platform:` in docs/ai/pr-config.yaml, with
   an auth check report, never overwriting silently.
2. One platform adapter module, .aai/scripts/lib/platform-adapter.mjs,
   reusing pr-platform.mjs, with GitHub and Azure DevOps implementations of
   exactly the operations merge-cleanup needs, and named skips for
   unknown/none.
3. merge-cleanup.mjs (preflight, the printed merge command, plan/apply, the
   remote branch proofs) and SKILL_MERGE moved onto the adapter. This closes
   #468.
4. A `platform_mismatch` refusal in merge-cleanup.
5. A static check that merge-cleanup.mjs has no direct gh/az call outside the
   adapter.

Deferred to later rides, each recorded as a follow-up (see Follow-ups to
file) so nothing is silently dropped: watch-ci.mjs, merge-policy.mjs,
lane-gate.mjs, pr-preflight.mjs, close-work-item.mjs, aai-release (.sh and
.ps1), claude-hook-gate.sh, the SKILL_PR and SKILL_RELEASE prompt text,
`/aai-doctor` and `aai-update` drift reporting for the recorded platform.
Intake AC-003 (watch-ci, merge-policy and release regression) and the
"every consumer" reading of intake AC-004/AC-005/AC-006 therefore apply in
this ride to merge-cleanup only; later rides extend the consumer list of the
static check (D12) one file at a time.

Disclosed deviation from the dispatch wording "(sh + ps1)": the layer has no
`aai-bootstrap.ps1` (only .aai/scripts/aai-bootstrap.sh, run through Git Bash
on Windows). The record step is therefore a Node CLI (D2) that bootstrap.sh
calls and that SKILL_BOOTSTRAP names for PowerShell too; TEST-065 proves the
PowerShell invocation writes the same bytes. Porting the whole bootstrap to
PowerShell is not part of this ride.

## Implementation strategy

- Strategy: tdd
- Rationale: the owner was offered full TDD and the dispatch recommends it.
  The scope moves the only merge path of the factory onto a new seam and
  adds the first Azure merge executor; the dangerous properties (head match,
  no silent overwrite of a committed config, refusal before any write,
  zero gh calls on Azure) all look correct until a test is seen failing
  without them. Every Spec-AC gets a stored RED and a mutation that reddens
  it. STATE's current implementation_strategy belongs to
  `docs-index-broken-refs-scope` (ref_id differs), so it is stale and is
  replaced; the intake records no `Implementation mode (user choice):` line.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound change across an engine, a new lib, a new
  CLI, bootstrap, two prompts and four suites. The main checkout is shared
  with other sessions and holds uncommitted docs/INDEX.md,
  docs/ai/roadmap.yaml and this ride's intake draft, which must not be
  committed or reverted from here. No `protected_paths_l3` surface is
  touched (D15), so a recorded user decision is not mandatory, but isolation
  keeps the shared checkout clean.
- User decision: undecided (Implementation Preparation asks)
- Base ref: main feca6e0b
- Worktree branch/path: change/git-platform-detected-at-bootstrap (suggested)
- Inline review scope: see Code review scope below.
- Code review required: true (engine, new lib and CLI, bootstrap, canon,
  tests).

## Phasing

One ride, 14 Spec-ACs, 15 TEST rows. Expected TDD dispatches (about three
ACs each):
(A) Spec-AC-01 to Spec-AC-04: record CLI, auth report, bootstrap wiring,
PowerShell parity (TEST-062 to TEST-065).
(B) Spec-AC-05, Spec-AC-06 (adapter arm), Spec-AC-07, Spec-AC-13: the adapter
module, generic skips, Windows az spawn, the static check (TEST-066,
TEST-067, TEST-069, TEST-075).
(C) Spec-AC-08, Spec-AC-10, Spec-AC-11, Spec-AC-06 (consumer arm),
Spec-AC-12: merge-cleanup on the adapter (TEST-068, TEST-070, TEST-072,
TEST-073, TEST-074).
(D) Spec-AC-09 and Spec-AC-14: the Azure merge executor and canon plus
governance (TEST-071, TEST-076), then V1 to V5.

## Measured facts (2026-10-16, this machine)

- F1 azure-devops CLI extension 1.0.6 (azure-cli 2.89.1), source
  `azext_devops/dev/repos/pull_request.py` `update_pull_request`: the call
  first reads the PR (`existing_pr = client.get_pull_request_by_id(id)`),
  and when `--status completed` sets
  `pr.last_merge_source_commit = existing_pr.last_merge_source_commit`
  before the PATCH. The completion is therefore pinned to the head that az
  itself read at the start of the same call, never to a caller-supplied sha.
- F2 Flag spellings, read from local `--help`: `az repos pr show --id
  --detect --output`; `az repos pr list --status --target-branch
  --source-branch --top --detect --output`; `az repos pr update --id
  --status --squash --delete-source-branch --detect --output`; `az devops
  invoke --area --resource --route-parameters --org --api-version
  --http-method --output` (`--api-version` defaults to 5.0, so it is passed).
- F3 merge-cleanup.mjs at feca6e0b has 1361 lines and makes exactly three
  kinds of gh call: `pr view <n> --json PR_FIELDS`, `pr list --state open
  --base|--head <b> --json number --limit 100`, and `api graphql` (review
  threads); it prints (never runs) one `gh pr merge` line. TEST-058 caps the
  file at 1490 lines.
- F4 lane-gate.mjs `--sweep-check`, which preflight runs, makes no gh call
  (git reads only), so it needs no adapter in this ride.
- F5 claude-hook-gate.sh gates `git merge*` and `gh pr merge*` only; an
  `az repos pr update` or a `node … platform.mjs merge` command is not gated
  by it (deferred, residual R3).
- F6 There is no .aai/scripts/aai-bootstrap.ps1; bootstrap is bash-only.
- F7 The existing merge-cleanup fixtures use a local bare path as origin
  (pr-platform classifies it `unknown`) and record no `platform:`; their PR
  JSON urls are `https://github.com/example/repo/pull/<n>`.
- F8 On Windows the Azure CLI is `az.cmd`; Node refuses to spawn a .cmd
  without a shell (EINVAL since the CVE-2024-27980 fix), so `spawnSync('az',
  …)` cannot work there. `gh` ships as gh.exe and spawns directly.

## Design decisions

- D1 Recorded key. docs/ai/pr-config.yaml gains a column-0 key
  `platform: github|azure|unknown|none`, parsed with the same column-0
  discipline as `reviewer_bots` (exact value after trimming; anything else is
  `invalid`). The file header documents the key. This repository records
  `platform: github`. `readReviewerBots` is unchanged.
- D2 Record CLI. A new CLI .aai/scripts/platform.mjs with subcommands
  `record` and `merge` (D9). `record [--repo-root <dir>] [--remote-url
  <url>] [--force] [--dry-run]` classifies origin with pr-platform.mjs's
  `classify(extractHost(url))` (none when there is no origin) and:
  - file absent: creates it with a short header plus the `platform:` line,
    prints `RECORDED platform=<v> (new file)`, exit 0;
  - key absent: appends the line, every existing byte kept, prints
    `RECORDED platform=<v>`, exit 0;
  - recorded equals detected, or detected is `unknown` (an enterprise or
    self-hosted host the classifier cannot name keeps its recorded value):
    no write, `UNCHANGED platform=<recorded>`, exit 0;
  - recorded differs from a detected `github`, `azure` or `none`, or is
    `invalid`: no write, `MISMATCH recorded=<a> detected=<b> re-record: node
    .aai/scripts/platform.mjs record --force`, exit 6;
  - `--force` on a mismatch rewrites only the `platform:` line, prints
    `RECORDED platform=<b> (was <a>)`, exit 0;
  - `--dry-run` writes nothing and prints `WOULD-RECORD …` or the same
    UNCHANGED/MISMATCH line; exit codes as above;
  - usage error exit 2. The printed remote is always `sanitize()`d.
- D3 Auth report. `record` then prints exactly one line
  `AUTH <platform> <ok|unauthenticated|cli_missing|extension_missing|skipped>`:
  github runs exactly `gh auth status` (exit 0 ok, spawn ENOENT cli_missing,
  other non-zero unauthenticated); azure runs exactly `az account show
  --output json` then, if that exits 0, `az extension show --name
  azure-devops --output json` (non-zero: extension_missing); unknown and
  none spawn nothing and print skipped. The auth result never changes the
  exit code or the file.
- D4 Bootstrap wiring. aai-bootstrap.sh calls `node
  "$BOOTSTRAP_SCRIPT_DIR/platform.mjs" record --repo-root "$ROOT"` (plus
  `--dry-run` under its own `--dry-run`), captures exit code and output
  without aborting under `set -e`, and prints the RECORDED/UNCHANGED/
  WOULD-RECORD/MISMATCH line and the AUTH line in its summary. A MISMATCH or
  a missing node never fails bootstrap. SKILL_BOOTSTRAP gains a short
  "Git platform" section naming the POSIX and the PowerShell
  (`node .aai/scripts/platform.mjs record`) forms and the `--force`
  re-record, and adds the platform and auth lines to "Report Results".
- D5 Platform resolution (shared by every consumer), in
  `resolvePlatform({ repoRoot, remoteUrl })` of the adapter:
  recorded = the D1 value (null when file or key absent); detected =
  classify(origin). Mismatch when recorded is `invalid`, or when recorded is
  set, detected is one of `github`, `azure`, `none`, and they differ.
  Effective platform = recorded when set; else detected when it is
  `github`, `azure` or `none`; else (no record and detected `unknown`)
  `github` with `legacy: true`. The legacy default keeps every existing
  installation (enterprise GitHub hosts, local-path test origins, F7)
  behaving exactly as today; a recorded `unknown` is how a project opts into
  generic mode. Unrecorded Azure origins resolve to `azure`, so #468 is
  fixed without re-running bootstrap.
- D6 Adapter API (.aai/scripts/lib/platform-adapter.mjs, Node stdlib only,
  imports the classifier from ../pr-platform.mjs). `createAdapter(platform,
  { cwd, runner })` returns `prView(n)`, `listDependents(branch, side)`
  (side `base` or `head`), `reviewThreads(n, pr)`, `repoMatches(originUrl,
  pr)`, `mergeCommand(n, head, engineDir)`, `authStatus()`. Every read
  returns `{ ok: true, value }`, `{ ok: false, reason, detail }` with reason
  `read_failed` or `read_invalid`, or `{ skip: true, reason:
  'platform_generic', op, manual }`. The normalized PR is
  `{ number, state: OPEN|MERGED|CLOSED, isDraft, headRefOid, headRefName,
  baseRefName, mergeCommit, url, isCrossRepository }`. `runner` is injected
  so merge-cleanup keeps its existing `AAI_MERGE_CLEANUP_GH_NODE` seam under
  `AAI_MERGE_CLEANUP_TEST_SEAMS=1` unchanged (TEST-005 and the Pester twin).
- D7 GitHub implementation: byte-identical argv to today (F3): `pr view <n>
  --json PR_FIELDS`, the two `pr list` reads with a 120 s timeout, the
  `api graphql --paginate --slurp [--hostname h] -F owner -F repo -F pr -f
  query` read; failures map to the existing refusal reasons `gh_read_failed`
  and `gh_read_invalid` with the existing details. `mergeCommand` returns
  exactly `AAI_OPERATOR_MERGE=1 gh pr merge <n> --squash
  --match-head-commit <head>`.
- D8 Azure implementation, exact argv (the stub pins these, deny by default):
  - A1 `az repos pr show --id <n> --detect true --output json`
  - A2 `az repos pr list --status active --target-branch <b> --top 100 --detect true --output json`
  - A3 `az repos pr list --status active --source-branch <b> --top 100 --detect true --output json`
  - A4 `az devops invoke --area git --resource pullRequestThreads --route-parameters project=<projectId> repositoryId=<repositoryId> pullRequestId=<n> --org <orgUrl> --api-version 7.1 --http-method GET --output json`
  - A5 (D9 only) `az repos pr update --id <n> --status completed --squash true --delete-source-branch false --detect true --output json`
  Normalization from A1: `status` active/completed/abandoned to
  OPEN/MERGED/CLOSED (anything else CLOSED); `isDraft`; `headRefOid` =
  `lastMergeSourceCommit.commitId`; `headRefName` and `baseRefName` =
  `sourceRefName`/`targetRefName` with the `refs/heads/` prefix stripped (a
  value without the prefix stays as is and fails the existing name checks);
  `mergeCommit` = `lastMergeCommit.commitId` only when completed;
  `isCrossRepository` = `Boolean(forkSource)`; `url` =
  `repository.webUrl + '/pullrequest/' + n`. `orgUrl` is derived from
  `repository.url` (scheme, host and, for dev.azure.com, the first path
  segment). Dependents: `pullRequestId` integers of A2/A3. Unresolved
  threads: entries of A4 `value` whose `status` is `active` or `pending` and
  that are not `isDeleted`; threads without a status (system threads) and
  closed/fixed/wontFix/byDesign threads are resolved. Failures map to
  `az_read_failed` and `az_read_invalid`. Repository identity
  (`repoMatches`): org/project/repo parsed from the origin URL (forms
  `https://[user@]dev.azure.com/<org>/<project>/_git/<repo>`,
  `git@ssh.dev.azure.com:v3/<org>/<project>/<repo>`,
  `https://<org>.visualstudio.com/[DefaultCollection/]<project>/_git/<repo>`)
  and from `repository.webUrl`, lower-cased and URL-decoded; a mismatch is
  `repo_mismatch`, an unparsable origin (local path) skips the check as
  today.
- D9 Azure merge executor and head match. Azure has no
  `--match-head-commit`. Preflight prints exactly one command:
  `AAI_OPERATOR_MERGE=1 node "<engineDir>/platform.mjs" merge --pr <n> --expect-head <sha>`,
  where `<engineDir>` is the absolute directory of the running
  merge-cleanup.mjs (the ride worktree of a downstream project may have no
  .aai/). `platform.mjs merge`:
  1. refuses (exit 3, no az write) unless `AAI_OPERATOR_MERGE=1`
     (`no_operator_merge`), `--expect-head` is 40 hex, and the D5 platform
     resolves to azure without mismatch (`platform_mismatch`, or
     `platform_not_azure` for github/unknown/none);
  2. A1 read: refuses `not_open`, `draft`, or `head_changed` (A1
     `headRefOid` differs from `--expect-head`) before any A5;
  3. runs A5 exactly once, immediately after step 2 (no other call between);
     A5 non-zero: exit 3 `merge_rejected <first stderr line>`;
  4. A1 re-read: completed with `headRefOid` equal to `--expect-head`: exit
     0 `MERGED PR #<n> head <sha> merge <mergeCommit>`; completed with a
     different head: exit 5 `head_race_lost expected <sha> merged <other>`
     (the owner is told; nothing is undone); still active: exit 4
     `completion_pending` (branch policies or a queued completion).
  The head-match proof is therefore: our A1 read equals the owner's sha,
  then az pins the completion to the head it read itself (F1), then the
  re-read proves which head was merged. Residual race R1 below.
- D10 Generic mode (effective platform `unknown` or `none`, recorded). Every
  adapter read returns the named skip of D6 with a non-empty `manual` text
  (for example `open PR <n> on your git host and merge it there; then delete
  the worktree and branch by hand`) and spawns nothing. merge-cleanup
  preflight, plan and apply then exit 3 with
  `REFUSE platform_generic <op> manual: <manual>` before any write; no
  output carries a `gh_` reason. (An unrecorded `unknown` is legacy GitHub,
  D5.)
- D11 merge-cleanup on the adapter. `resolvePlatform` runs first in every
  mode, before any platform read or write: mismatch gives exit 3
  `REFUSE platform_mismatch recorded=<a> detected=<b> re-record: node
  .aai/scripts/platform.mjs record --force`. `ghPrView`, `ghDependents`,
  `ghApi`, the GraphQL query and the merge command string move into the
  adapter; `checkRepo` uses `repoMatches`; `remoteProof` uses
  `listDependents`. Everything git-based (fetch, ancestry, worktree, lease
  delete) is unchanged. The legacy notice for D5 `legacy: true` is one
  stderr line `merge-cleanup: platform not recorded; assuming github (record
  it: node .aai/scripts/platform.mjs record)`; stdout is unchanged.
- D12 Static check. tests/skills/lib/platform-direct-calls.mjs takes a list
  of consumer files (this ride: .aai/scripts/merge-cleanup.mjs), drops lines
  whose first non-blank characters are `//` and `/* … */` blocks, and
  reports every remaining match of: a quoted token exactly `gh` or `az`
  (single, double or back quote), or the substrings `gh pr `, `gh api`,
  `az repos`, `az devops`. Exit 0 with `PLATFORM-CALLS clean <n> files`, or
  exit 1 listing `file:line`. An explicit allow-list array in the same file
  (empty this ride) exempts `file:line-content` pairs. The adapter and
  platform.mjs are not consumers.
- D13 Windows az spawn. The adapter's `azSpawnSpec(args, platform)` returns
  `{ cmd: 'az', args }` off Windows and, on `win32`, `{ cmd:
  process.env.ComSpec or 'cmd.exe', args: ['/d', '/s', '/c', 'az', ...args] }`
  after checking every arg against `^[A-Za-z0-9._/:=@-]+$`; any other arg
  (space, quote, `&`, `%`, `^` …) is refused as `az_arg_unsafe` before any
  spawn. Branch names already pass `BASE_NAME_RE`, a subset.
- D14 Canon and governance. SKILL_MERGE step 1: "run exactly the one merge
  line it printed, nothing added" names both forms (the GitHub literal kept
  verbatim, plus the Azure `platform.mjs" merge` form) and says a
  `platform_mismatch` or `platform_generic` REFUSE is relayed with its
  command and the run stops. Prompt growth of SKILL_MERGE and
  SKILL_BOOTSTRAP is credited in tests/skills/lib/prompt-diet-ledger.sh
  (key `git-platform-detected-at-bootstrap`, at most 900 B, measured with
  /usr/bin/wc -c), the TEST-012 `want_growth` pin in
  tests/skills/test-aai-prompt-diet.sh moves by exactly that credit, and the
  `want_growth` sum in tests/skills/test-aai-pr-preflight.sh adds the same
  term. .aai/system/PROFILES.yaml classifies .aai/scripts/platform.mjs and
  .aai/scripts/lib/platform-adapter.mjs as core (merge-cleanup.mjs and
  aai-bootstrap.sh are core). tests/skills/suite-map.yaml gains a row
  `aai-platform-adapter` (globs: the two new files, pr-platform.mjs,
  docs/ai/pr-config.yaml) and the two new files join the `aai-merge-cleanup`
  and `aai-bootstrap` rows.
- D15 Ceremony level 2. No touched path is in `protected_paths_l3`
  (docs/ai/docs-audit.yaml lists state.mjs, state-engine, state-core, the
  allocator, pre-commit-checks, WORKFLOW.md, CONSTITUTION.md);
  claude-hook-gate.sh is deferred, not touched. The merge path keeps its
  existing operator checkpoint (`/aai-merge` runs only on the owner's
  explicit direction). Review may raise the level as a recorded finding.

## Implementation anchors (the mutation rows depend on these spellings)

- platform-adapter.mjs: `const KNOWN_DETECTED = ['github', 'azure', 'none'];`
  and the mismatch test `KNOWN_DETECTED.includes(detected) && recorded !== detected`;
  the legacy line contains `legacy: true`; `const AZ_STATE = { active: 'OPEN', completed: 'MERGED', abandoned: 'CLOSED' };`;
  `headRefOid: pr.lastMergeSourceCommit?.commitId`;
  `isCrossRepository: Boolean(pr.forkSource)`;
  `const UNRESOLVED_THREAD_STATUSES = ['active', 'pending'];`;
  `const AZ_SAFE_ARG = /^[A-Za-z0-9._\/:=@-]+$/;`; the GitHub merge command
  template contains `--match-head-commit ${head}`; generic skips carry
  `reason: 'platform_generic'`; the A1 argv array literal contains
  `'--detect', 'true', '--output', 'json'`; the auth argv array literal
  contains `'extension', 'show', '--name', 'azure-devops'`.
- platform.mjs: `if (process.env.AAI_OPERATOR_MERGE !== '1')`;
  `if (before.headRefOid !== expectHead)`; `if (after.headRefOid !== expectHead)`;
  the write guard of record reads `if (mismatch && !opts.force)`; the
  dry-run guard reads `if (opts.dryRun)`.
- merge-cleanup.mjs: `refuse('platform_mismatch'`, `refuse('platform_generic'`.
- aai-bootstrap.sh: the call line contains `platform.mjs" record`.
- SKILL_MERGE.prompt.md carries `platform.mjs" merge --pr <n> --expect-head <sha>`;
  SKILL_BOOTSTRAP.prompt.md carries `node .aai/scripts/platform.mjs record`.

## Seams

- S1 Bootstrap to committed config to engine: aai-bootstrap.sh writes
  `platform:` (TEST-065), merge-cleanup reads the same file (TEST-072,
  TEST-073); both sides use the one D1 parser in the adapter, never a copy.
- S2 Classifier to adapter: the adapter imports pr-platform.mjs's
  `classify`/`extractHost`; TEST-062 runs the record matrix through the real
  classifier, TEST-070 runs preflight with a real Azure https origin URL and
  no record (the #468 shape).
- S3 Engine to az/gh: deny-by-default stubs on PATH with exact-argv logs;
  every Azure arm asserts the gh log is empty and the az log holds exactly
  the expected argv lines (positive control: the az log is non-empty).
- S4 Preflight to executor: the command preflight prints (TEST-070) is the
  one TEST-071 executes, with the absolute path it names.
- S5 Engine to bare remote: Azure apply (TEST-072) asserts on the bare
  origin (branch deleted by lease) and on the worktree list, not on the
  report alone.
- S6 Prompt corpus: diet ledger, TEST-012 pin and the pr-preflight sum must
  agree (TEST-076, V3).
- Not crossable by an automated test: a live Azure DevOps organization
  (R1, R2); recorded in Residual risks.

## Acceptance Criteria Mapping

- Intake AC-001 (record matrix, keep existing, report mismatch) ->
  Spec-AC-01, Spec-AC-02, Spec-AC-03, Spec-AC-04.
- Intake AC-002 (#468: Azure preflight READY, merge with head match, apply,
  zero gh) -> Spec-AC-08, Spec-AC-09, Spec-AC-10.
- Intake AC-003 (GitHub regression) -> Spec-AC-12 (merge-cleanup only this
  ride; watch-ci, merge-policy, release deferred).
- Intake AC-004 (platform_mismatch before any write) -> Spec-AC-11
  (merge-cleanup and platform.mjs merge).
- Intake AC-005 (unknown/none named skips) -> Spec-AC-06.
- Intake AC-006 (static check plus positive control) -> Spec-AC-13.
- Adapter seam and Windows spawn (design, not an intake AC) -> Spec-AC-05,
  Spec-AC-07. Canon and governance -> Spec-AC-14.

## Constitution deviations

- Article 7 (operator-only merge): platform.mjs `merge` is a merge executor
  the agent may run. It adds no new exception: it is the Azure form of the
  existing directed-merge line SKILL_MERGE already prints for GitHub, runs
  only on the owner's explicit `/aai-merge <n>` direction, and refuses
  without `AAI_OPERATOR_MERGE=1`. The Article 7 wording gap for directed
  merges is already tracked as `fu-constitution-art7-directed-merge`.
- Article 5 (additive first) is kept: the `platform:` key is additive, and
  the D5 legacy default preserves today's behaviour for every installation
  without the key.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN `node .aai/scripts/platform.mjs record --repo-root <fixture>` runs on fixture repos whose origin is github https, github ssh, azure https (dev.azure.com), azure ssh (ssh.dev.azure.com v3), azure legacy (visualstudio.com), gitlab, and no origin, the system SHALL leave docs/ai/pr-config.yaml with exactly one column-0 line `platform: <v>` equal to github, github, azure, azure, azure, unknown, none respectively, keep every pre-existing byte (a `reviewer_bots: expected` line survives), exit 0, and with `--dry-run` SHALL write nothing (file absent or byte-identical) while printing WOULD-RECORD. | planned | — | — | D1, D2 |
| Spec-AC-02 | WHEN the recorded value differs from a detected github, azure or none, or is not one of the four values, record SHALL leave the file byte-identical, print a MISMATCH line naming both values and the `record --force` command, and exit 6; WHEN recorded equals detected, or detected is unknown, it SHALL print UNCHANGED and leave the file byte-identical; WHEN `--force` is given on a mismatch it SHALL rewrite only the platform line (every other line byte-identical) and exit 0. | planned | — | — | D2, D5 |
| Spec-AC-03 | record SHALL print exactly one AUTH line: for github the gh stub log SHALL hold exactly `auth status`; for azure the az stub log SHALL hold exactly `account show --output json` then `extension show --name azure-devops --output json`; unknown and none SHALL spawn nothing and print skipped; a missing binary SHALL print cli_missing, a failing az extension read extension_missing, a failing gh or az account read unauthenticated; in every arm the exit code and the file SHALL equal those of the same run with authentication ok. | planned | — | — | D3 |
| Spec-AC-04 | WHEN aai-bootstrap.sh runs on a fixture with an Azure https origin it SHALL record `platform: azure`, exit 0 and print the RECORDED and AUTH lines; WHEN it runs again after origin was changed to a github URL it SHALL exit 0, print the MISMATCH line and leave pr-config.yaml byte-identical; under `--dry-run` it SHALL not create pr-config.yaml; SKILL_BOOTSTRAP SHALL name the POSIX and the PowerShell record command; and WHEN pwsh is on PATH the PowerShell form run on a fresh copy of the fixture SHALL produce a pr-config.yaml byte-identical to the bash run. | planned | — | — | D4; no aai-bootstrap.ps1 exists (F6) |
| Spec-AC-05 | WHEN the adapter is driven with stub binaries, the GitHub reads SHALL use argv byte-identical to F3 and the Azure reads SHALL use exactly the A1 to A4 argv of D8; the normalized PR SHALL map active, completed and abandoned to OPEN, MERGED and CLOSED, take the head from lastMergeSourceCommit, strip refs/heads/ from both branch names, set mergeCommit only when completed, set isCrossRepository true only when forkSource is present; dependents SHALL be the pullRequestId integers; unresolved threads SHALL count active and pending threads only; unparsable stub output SHALL return read_invalid and a non-zero stub exit read_failed. | planned | — | — | D6, D7, D8 |
| Spec-AC-06 | WHEN the effective platform is a recorded unknown or none, every adapter read SHALL return a skip with reason platform_generic and a non-empty manual text and SHALL spawn neither gh nor az (positive control: the same harness on github spawns one call), and merge-cleanup preflight, plan and apply SHALL each exit 3 with `REFUSE platform_generic` carrying `manual:`, print no `gh_` reason, leave the gh and az logs empty and leave the world digest unchanged. | planned | — | — | D10 |
| Spec-AC-07 | `azSpawnSpec` SHALL return the bare `az` command with the args unchanged for darwin and linux, and for win32 SHALL return ComSpec (or cmd.exe) with `/d /s /c az` followed by the args; an arg containing a space, a double quote, `&`, `%` or `^` SHALL be refused as az_arg_unsafe with no spawn. | planned | — | — | D13; executed on real Windows only by the owner's live proof (R4) |
| Spec-AC-08 | WHEN preflight runs for an open, non-draft PR on a ride whose origin is `https://dev.azure.com/acme/Proj/_git/foo` with no platform recorded, the az stub serving A1 at the expected head and A4 with no active thread, it SHALL exit 10 and print exactly one merge line equal to `AAI_OPERATOR_MERGE=1 node "<abs>/platform.mjs" merge --pr <n> --expect-head <sha>` whose path exists, the gh log SHALL be empty and the az log SHALL hold exactly the A1 and A4 lines; WHEN A1 reports another head, a draft, abandoned, or completed, or A4 has an active thread, or A1 fails, or the PR webUrl names another repository, preflight SHALL exit 3 with head_changed, draft, not_open, exit 0 already_merged, review_unresolved, az_read_failed or repo_mismatch respectively, with an empty gh log. | planned | — | — | D8, D9, D11; the #468 acceptance case |
| Spec-AC-09 | WHEN `platform.mjs merge --pr <n> --expect-head <sha>` runs with AAI_OPERATOR_MERGE=1 on an Azure origin and A1 shows the PR active at that sha, it SHALL run A5 exactly once and then A1 again, and exit 0 printing MERGED with the merge commit when the re-read is completed at that sha; it SHALL exit 3 with zero A5 calls when AAI_OPERATOR_MERGE is unset (no_operator_merge), when A1 shows another head (head_changed), or when the platform is github or mismatched; it SHALL exit 5 head_race_lost naming both shas when the re-read is completed at another head, exit 4 completion_pending when the re-read is still active, and exit 3 merge_rejected when A5 fails. | planned | — | — | D9; residual R1 |
| Spec-AC-10 | WHEN apply runs for a completed Azure PR with `platform: azure` recorded (bare local origin, lastMergeCommit the squash commit on the bare main, lastMergeSourceCommit the ride head, no forkSource), it SHALL exit 0, remove the ride worktree, delete the bare's ride branch by lease, hold exactly A1, A2 and A3 in the az log and nothing in the gh log; WHEN forkSource is present the remote branch SHALL be retained as remote_fork, and WHEN A2 or A3 lists an open PR it SHALL be retained as remote_has_dependents, the bare branch still existing and apply exiting 0. | planned | — | — | D8, D11 |
| Spec-AC-11 | WHEN `platform: azure` is recorded and origin is a github.com URL, or `platform: github` is recorded and origin is a dev.azure.com URL, merge-cleanup preflight, plan and apply SHALL each exit 3 with `REFUSE platform_mismatch recorded=<a> detected=<b>` naming the `record --force` command, with empty gh and az logs and an unchanged world digest, and platform.mjs merge SHALL refuse the same way with zero A5 calls. | planned | — | — | D5, D11 |
| Spec-AC-12 | tests/skills/test-aai-merge-cleanup.sh SHALL exit 0 with every pre-existing test function body unchanged (unrecorded platform, local-path origin: the legacy GitHub path), the Pester twin aai-merge-cleanup.Tests.ps1 SHALL pass, and WHEN `platform: github` is recorded with the same local-path origin preflight SHALL print the identical pinned `gh pr merge` line, while the unrecorded run SHALL add exactly one stderr line containing `platform not recorded` and leave stdout byte-identical. | planned | — | — | D5, D7, D11 |
| Spec-AC-13 | `node tests/skills/lib/platform-direct-calls.mjs .aai/scripts/merge-cleanup.mjs` SHALL exit 0 with PLATFORM-CALLS clean; run on a scratch copy with one injected `spawnSync('gh', [...])`, one `spawnSync('az', [...])`, one `execFileSync("gh", ...)` and one template literal containing `gh pr merge` it SHALL exit 1 and list each of the four injected lines. | planned | — | — | D12 |
| Spec-AC-14 | SKILL_MERGE step 1 SHALL keep the GitHub merge literal verbatim, name the Azure form `platform.mjs" merge --pr <n> --expect-head <sha>` and say a platform_mismatch or platform_generic REFUSE is relayed and stops; the prompt-diet ledger SHALL carry a `git-platform-detected-at-bootstrap` credit between 1 and 900; PROFILES.yaml SHALL list both new .aai files under core; pr-config.yaml SHALL document the platform key and record `platform: github`; test-aai-prompt-diet.sh, test-aai-pr-preflight.sh and test-aai-layer-profiles.sh SHALL exit 0. | planned | — | — | D1, D14 |

## Implementation plan

- .aai/scripts/lib/platform-adapter.mjs (new): `readRecordedPlatform`,
  `resolvePlatform` (D5), `createAdapter` with github, azure and generic
  implementations (D6 to D8, D10), `azSpawnSpec` (D13), `azureRepoId`
  parser for `repoMatches`. Imports `classify`, `extractHost`, `sanitize`,
  `readOriginUrl` from ../pr-platform.mjs (export `readOriginUrl`, the only
  change to pr-platform.mjs).
- .aai/scripts/platform.mjs (new CLI): `record` (D2, D3) and `merge` (D9);
  exit contracts as stated; `cli-pipe-guard` `runMain`/`exit` like the
  other CLIs.
- .aai/scripts/merge-cleanup.mjs: remove `ghPrView`, `ghDependents`,
  `ghApi`, the GraphQL text and the merge command string; build one adapter
  per run after `resolvePlatform` (D11); map adapter failures to the
  platform-specific reasons; the seam env vars keep their meaning. HELP and
  the header comment name the adapter; line count must stay at most 1490
  (TEST-058).
- .aai/scripts/aai-bootstrap.sh: the D4 call and summary lines.
- .aai/SKILL_MERGE.prompt.md, .aai/SKILL_BOOTSTRAP.prompt.md (D4, D14);
  harness wrappers are pointers only (`sync-harness-skills.mjs --check`
  stays green).
- docs/ai/pr-config.yaml: header for `platform:` and `platform: github`.
- .aai/system/PROFILES.yaml, tests/skills/suite-map.yaml,
  tests/skills/lib/prompt-diet-ledger.sh, tests/skills/test-aai-prompt-diet.sh,
  tests/skills/test-aai-pr-preflight.sh (D14).
- tests/skills/test-aai-platform-adapter.sh (new suite) with an az and gh
  stub writer (deny by default, exact argv per D3/D7/D8, `STUB-DENY` on
  anything else, every call logged), and
  tests/skills/lib/platform-direct-calls.mjs (D12).
- tests/skills/test-aai-merge-cleanup.sh: an `write_az_stub` helper beside
  `write_gh_stub`, Azure PR fixture writers, TEST-068, TEST-070, TEST-072,
  TEST-073, TEST-074 functions, selector cases and default order; no edit
  inside any pre-existing test function (Spec-AC-12).
- tests/skills/test-aai-bootstrap.sh: TEST-065.
- New test code is verified under each suite's own `set -euo pipefail` (no
  bare `rc=$?`, no `grep | head`), fixtures carry their own git identity,
  bare origins set `symbolic-ref HEAD`, every scratch path is checked
  non-empty and absolute before `cd` or `git -C`.
- docs/product (written after the loop completes) and a CHANGELOG
  `## [unreleased] — <title>` entry.
- Edge cases: an Azure project name with a space (URL-encoded in webUrl, raw
  in some origins); `targetRefName` without `refs/heads/`; an A4 response
  with `value` missing (read_invalid); a pr-config.yaml with CRLF line
  endings (the record keeps the file's line ending); a recorded value with
  trailing spaces (trimmed, still valid); `--remote-url ''` (none).

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-062 | Spec-AC-01 | integration | tests/skills/test-aai-platform-adapter.sh | test_062_record_matrix: seven scratch repos (github https and ssh, azure https, ssh v3 and visualstudio.com, gitlab, no origin); record writes the expected platform line once; a pre-seeded reviewer_bots line and comment survive byte for byte; dry-run leaves the file absent or byte-identical and prints WOULD-RECORD | sed:s/const KNOWN_DETECTED = \['github', 'azure', 'none'\];/const KNOWN_DETECTED = ['github', 'none'];/ | pending |
| TEST-063 | Spec-AC-02 | integration | tests/skills/test-aai-platform-adapter.sh | test_063_record_never_overwrites: recorded azure plus github origin gives MISMATCH, exit 6, sha256 unchanged; recorded github plus github gives UNCHANGED; recorded github plus gitlab gives UNCHANGED; invalid value gives MISMATCH; force rewrites only the platform line (diff of the other lines empty) | sed:s/if \(mismatch && !opts\.force\)/if (false)/ | pending |
| TEST-064 | Spec-AC-03 | integration | tests/skills/test-aai-platform-adapter.sh | test_064_auth_report: gh and az stubs with exact-argv logs; ok, unauthenticated, cli_missing (PATH without the binary), extension_missing arms; unknown and none spawn nothing; exit code and file equal across arms | sed:s/'extension', 'show', '--name', 'azure-devops'/'extension', 'list'/ | pending |
| TEST-065 | Spec-AC-04 | integration | tests/skills/test-aai-bootstrap.sh | test_065_bootstrap_records_platform: bootstrap on an Azure-origin fixture records azure and prints RECORDED and AUTH; second run after set-url to github exits 0, relays MISMATCH, file sha unchanged; dry-run creates no pr-config.yaml; SKILL_BOOTSTRAP carries both command forms; pwsh arm compares bytes with the bash run (logged SKIP only when pwsh is absent) | sed:s/platform\.mjs" record/platform.mjs" --version/ | pending |
| TEST-066 | Spec-AC-05 | unit | tests/skills/test-aai-platform-adapter.sh | test_066_adapter_shapes: a node harness imports the adapter with stub bins; asserts the GitHub argv equals today's, the A1 to A4 argv equal D8, and every normalized field for active, completed, abandoned, fork, refs/heads stripping, threads (active, pending, closed, fixed, system, deleted), malformed JSON and non-zero exit | sed:s/headRefOid: pr\.lastMergeSourceCommit\?\.commitId/headRefOid: pr.lastMergeCommit?.commitId/ | pending |
| TEST-067 | Spec-AC-06 | unit | tests/skills/test-aai-platform-adapter.sh | test_067_generic_named_skips: for recorded unknown and none every adapter read returns platform_generic with a non-empty manual and the stub logs stay empty; positive control on github logs one call | sed:s/reason: 'platform_generic'/reason: 'read_failed'/ | pending |
| TEST-068 | Spec-AC-06 | integration | tests/skills/test-aai-merge-cleanup.sh | test_068_generic_refuses_with_manual: recorded unknown and recorded none; preflight, plan and apply each exit 3 with REFUSE platform_generic and manual:, no gh_ in stdout or stderr, gh and az logs empty, world digest unchanged | sed:s/refuse\('platform_generic'/refuse('gh_read_failed'/ | pending |
| TEST-069 | Spec-AC-07 | unit | tests/skills/test-aai-platform-adapter.sh | test_069_az_windows_spawn_spec: azSpawnSpec for darwin, linux and win32 (ComSpec set and unset); unsafe args with space, double quote, ampersand, percent and caret refused as az_arg_unsafe; a safe org URL and branch name accepted | sed:s/const AZ_SAFE_ARG = .*;/const AZ_SAFE_ARG = \/.*\/;/ | pending |
| TEST-070 | Spec-AC-08 | integration | tests/skills/test-aai-merge-cleanup.sh | test_070_azure_preflight_ready_and_refusals: open_world with origin set-url to the Azure https URL, no record, az stub; READY exit 10 with exactly one merge line equal to the D9 form and an existing absolute path; gh log empty; az log exactly A1 and A4; refusal arms head_changed, draft, not_open, already_merged, review_unresolved (active and pending), az_read_failed, repo_mismatch, each with an empty gh log | sed:s/const UNRESOLVED_THREAD_STATUSES = \['active', 'pending'\];/const UNRESOLVED_THREAD_STATUSES = [];/ | pending |
| TEST-071 | Spec-AC-09 | integration | tests/skills/test-aai-platform-adapter.sh | test_071_azure_merge_head_match: scripted az stub (A1 sequence, A5 outcome); merged arm exit 0 with one A5; no_operator_merge, head_changed, github platform and mismatch arms exit 3 with zero A5; head_race_lost exit 5; completion_pending exit 4; merge_rejected exit 3; the A5 argv equals D8 exactly | sed:s/if \(before\.headRefOid !== expectHead\)/if (false)/ | pending |
| TEST-072 | Spec-AC-10 | integration | tests/skills/test-aai-merge-cleanup.sh | test_072_azure_apply_cleanup: build_world with platform azure recorded and an Azure completed-PR fixture; apply exit 0; worktree gone; bare has no refs/heads/ride/foo; az log exactly A1, A2, A3; gh log empty; fork arm retained remote_fork; dependents arm retained remote_has_dependents with the bare branch present | sed:s/isCrossRepository: Boolean\(pr\.forkSource\)/isCrossRepository: false/ | pending |
| TEST-073 | Spec-AC-11 | integration | tests/skills/test-aai-merge-cleanup.sh | test_073_platform_mismatch_refuses_before_any_read: recorded azure with github origin and recorded github with Azure origin; preflight, plan and apply each exit 3 platform_mismatch naming both values and record --force; gh and az logs empty; world digest unchanged | sed:s/KNOWN_DETECTED\.includes\(detected\) && recorded !== detected/false/ | pending |
| TEST-074 | Spec-AC-12 | integration | tests/skills/test-aai-merge-cleanup.sh | test_074_github_recorded_and_legacy_unchanged: preflight READY with platform github recorded prints the pinned gh pr merge line; the unrecorded run prints the same stdout and exactly one stderr line containing platform not recorded; plus V1 full-suite and Pester twin runs | sed:s/--match-head-commit \$\{head\}/--match-head-commit HEAD/ | pending |
| TEST-075 | Spec-AC-13 | contract | tests/skills/test-aai-platform-adapter.sh | test_075_no_direct_platform_calls: the checker on merge-cleanup.mjs exits 0 with PLATFORM-CALLS clean; on a scratch copy with the four injected lines it exits 1 and lists all four line numbers | sed:s/gh pr /gh-pr-never-matches / | pending |
| TEST-076 | Spec-AC-14 | contract | tests/skills/test-aai-platform-adapter.sh | test_076_canon_and_governance: SKILL_MERGE carries the GitHub literal and the Azure form and the REFUSE relay sentence; ledger credit for the key in 1..900; PROFILES lists both new files; pr-config.yaml documents and records platform github; runs test-aai-prompt-diet.sh TEST-012, test-aai-pr-preflight.sh and test-aai-layer-profiles.sh and expects exit 0 | sed:s/platform\.mjs" merge --pr <n> --expect-head <sha>/platform.mjs merge/ | pending |

Mutation targets: .aai/scripts/lib/platform-adapter.mjs for TEST-062,
TEST-064, TEST-066, TEST-067, TEST-069, TEST-070, TEST-072, TEST-073, TEST-074;
.aai/scripts/platform.mjs for TEST-063 and TEST-071;
.aai/scripts/merge-cleanup.mjs for TEST-068; .aai/scripts/aai-bootstrap.sh
for TEST-065; tests/skills/lib/platform-direct-calls.mjs for TEST-075;
.aai/SKILL_MERGE.prompt.md for TEST-076. If an anchor spelling has to change
during implementation, the row's mutation is re-pointed in the same commit
and recorded as a spec amendment (additive with disclosure).

## Verification

- V1: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-merge-cleanup.sh`
  exits 0 (every pre-existing test plus TEST-068, TEST-070, TEST-072 to
  TEST-074), and `git diff main -- tests/skills/test-aai-merge-cleanup.sh`
  deletes no line inside a pre-existing `test_*` function (only the default
  run list and selector cases change).
- V2: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-platform-adapter.sh`
  and `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-bootstrap.sh`
  exit 0; `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-platform.sh`
  exits 0 (classifier regression).
- V3: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh`,
  `… tests/skills/test-aai-pr-preflight.sh`, `… tests/skills/test-aai-layer-profiles.sh`,
  `… tests/skills/test-aai-hygiene-pack.sh` exit 0; `node .aai/scripts/sync-harness-skills.mjs --check` exits 0.
- V4: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-merge-cleanup.sh TEST-016`
  (Pester twin under local pwsh) exits 0; the suites
  `node .aai/scripts/select-suites.mjs` picks for the changed paths through
  the wrapper; `node .aai/scripts/docs-audit.mjs --check --strict`.
- V5 mutation: `node .aai/scripts/mutation-run.mjs` per Test Plan row on the
  targets above, then `node .aai/scripts/mutation-gate.mjs` at close.
- Lint: `node .aai/scripts/spec-lint.mjs --path <this spec>`.
- Live (owner-run, not a gate of this ride): one `/aai-merge` on the
  downstream Azure repository that reported #468.

PASS criteria: every TEST row green with a stored RED and a mutation record,
every Spec-AC terminal, V1 to V4 exit 0.

## Evidence contract

Every artifact records ref_id `git-platform-detected-at-bootstrap`, the
Spec-AC and TEST ids, the exact command, exit code, log path and diff or
commit identity. TDD stores RED per AC-gating test, GREEN output and one
mutation record per row under
`docs/ai/tdd/spec-git-platform-detected-at-bootstrap/`. Validation repeats
V1 to V4 independently, re-reads F1 in the installed az extension (or
states it could not), and runs the stub argv of D8 against local `az …
--help` for flag existence. The Validation report carries an admissible
aai-outcome-v1 block, and its path is the `set-validation --evidence` value.

### Evidence by strategy

Strategy `tdd`: stored RED artifact per AC-gating test under docs/ai/tdd/
plus the full verification matrix V1 to V5.

## Code review scope

.aai/scripts/lib/platform-adapter.mjs, .aai/scripts/platform.mjs,
.aai/scripts/pr-platform.mjs, .aai/scripts/merge-cleanup.mjs,
.aai/scripts/aai-bootstrap.sh, .aai/SKILL_MERGE.prompt.md,
.aai/SKILL_BOOTSTRAP.prompt.md, .aai/system/PROFILES.yaml,
docs/ai/pr-config.yaml, tests/skills/test-aai-platform-adapter.sh,
tests/skills/lib/platform-direct-calls.mjs,
tests/skills/test-aai-merge-cleanup.sh, tests/skills/test-aai-bootstrap.sh,
tests/skills/suite-map.yaml, tests/skills/lib/prompt-diet-ledger.sh,
tests/skills/test-aai-prompt-diet.sh, tests/skills/test-aai-pr-preflight.sh,
the intake and this spec (plus the product doc and CHANGELOG entry once
written).

## Follow-ups to file (deferred consumers and residuals)

Ids are at most 40 characters and avoid the ceremony prefixes; all under
ref `git-platform-detected-at-bootstrap`:

- `fu-platform-adapter-watch-ci` (P2): move watch-ci.mjs onto the adapter.
- `fu-platform-adapter-merge-policy` (P2): move merge-policy.mjs onto the adapter.
- `fu-platform-adapter-lane-gate` (P3): lane-gate.mjs (no live gh call today, F4; confirm and add to the D12 consumer list).
- `fu-platform-adapter-pr-preflight` (P2): move pr-preflight.mjs onto the adapter.
- `fu-platform-adapter-close-work-item` (P2): close-work-item.mjs (hash-pinned; re-pin last).
- `fu-platform-adapter-release` (P2): aai-release.sh and .ps1 onto the adapter.
- `fu-platform-adapter-hook-gate` (P1): claude-hook-gate.sh onto the adapter, including gating the Azure merge command of D9 (R3).
- `fu-platform-adapter-skill-pr-release` (P3): SKILL_PR and SKILL_RELEASE prompt text and the SKILL_PR platform gate reading the recorded value.
- `fu-platform-record-doctor-update-drift` (P3): `/aai-doctor` and `aai-update` report recorded-versus-origin drift.
- `fu-azure-server-pinned-completion` (P3): measure on a live organization whether a REST PATCH with a caller-supplied lastMergeSourceCommit is refused on mismatch; if so, replace D9 step 3 with it and close R1.

## Residual risks

- R1 Azure head race. Between platform.mjs's A1 read and az's own internal
  read inside A5 (F1), a push to the source branch can land; az then
  completes the newer head. Whether the server additionally refuses a stale
  lastMergeSourceCommit is not measured. The post-completion re-read turns
  this into a loud `head_race_lost` exit 5 naming both shas, but it detects,
  it does not prevent. Window: one az process start plus one REST read.
  Follow-up `fu-azure-server-pinned-completion`.
- R2 No live Azure organization was used. Field names (lastMergeSourceCommit,
  lastMergeCommit, forkSource, repository.webUrl, thread status values) come
  from the REST model and the az extension source, not from a live
  response; in particular that `lastMergeCommit` of a completed squash PR is
  the commit on the target branch is unverified. A wrong value fails closed
  at `merge_commit_not_on_base` (refusal before any write). The owner's live
  `/aai-merge` on the #468 repository is the proof;
  `fu-azure-live-proof-on-adoption` stays open.
- R3 claude-hook-gate.sh does not gate the Azure merge command (F5) until
  `fu-platform-adapter-hook-gate`; SKILL_MERGE's owner-direction rule and
  platform.mjs's AAI_OPERATOR_MERGE refusal are the only guards in this
  ride.
- R4 Windows: the cmd.exe spawn path (D13) is unit-tested by its spec
  builder only; no Windows runner executes a real az.cmd in this ride.
- R5 The D5 legacy default keeps an unrecorded GitLab or Bitbucket project
  on the gh path (today's `gh_read_failed`), not on the generic skip; the
  generic path needs `platform: unknown` recorded, which bootstrap now does.
- R6 Bootstrap now writes a committed file (docs/ai/pr-config.yaml); the
  owner commits it. A mismatch is never auto-resolved.

## Assumptions (recorded instead of questions)

- A1 Azure squash completion (`--squash true`) mirrors the GitHub
  `--squash`; the source branch is not deleted by Azure
  (`--delete-source-branch false`) so the existing lease delete stays the
  only remote deletion path.
- A2 `--detect true` resolves organization, project and repository from the
  checkout's origin, so A1 to A3 and A5 run with the ride checkout as cwd.
- A3 Exit 6 for a record MISMATCH and exit 5 for head_race_lost are new
  codes, chosen to avoid the existing 0/2/3/4/10 meanings.
