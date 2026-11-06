---
id: cloudflare-share-on-node
type: change
number: null
status: draft
capability: cloudflare-share-on-node
parent: smaller-node-core-and-faster-feedback
links:
  pr: []
  commits: []
---

# Port the Cloudflare share script pair to one Node module

## Summary
- Ride 3 of the [remaining-scripts plan](../analysis/node-first-remaining-plan.md)
  (RFC-0017 phase 5).
- Port `.aai/scripts/cloudflare-share.sh` and `.aai/scripts/cloudflare-share.ps1`
  to one Node module, `.aai/scripts/cloudflare-share.mjs`, whose Wrangler
  deploy call is an injectable seam so tests never deploy for real. Both
  script files become thin launchers that keep their names, arguments, exit
  codes and success output.
- Fix the macOS failure: the `.sh` extracts the `https://...pages.dev` URL with
  `grep -oP`, which BSD grep rejects, so on macOS every share deploys and then
  dies with exit 2, records nothing and leaves `.cloudflare-publish/` behind.

## Motivation / Business Value
- `/aai-share` and its non-agent scripts do not work on macOS today
  (reproduced on main `bd519bb3` with a stub `wrangler`: `grep: invalid option
  -- P`, exit 2).
- 98 code lines of twin duplication (non-blank, non-comment; 51 in the `.sh`,
  47 in the `.ps1`) carry drifted behaviour: the two twins disagree on usage,
  error streams, the branch name outside a git repository, the `size_kb`
  value, the history record's key order and line endings, and cleanup on
  failure.

## Scope
- In scope:
  - `.aai/scripts/cloudflare-share.mjs` (new): argument parsing, document
    check, conversion through the unchanged `share-convert.mjs`, Wrangler
    lookup, branch-name derivation, deploy, URL extraction, size, history
    record, cleanup and the report; every external effect (convert, deploy,
    git, clock, output) injectable.
  - Both script files rewritten as launchers of at most 20 lines that run the
    module, and refuse with an install hint and exit 1 when Node is missing
    (the reaper and migrate-state-to-local precedent).
  - An explicit decision, in the spec, for every behaviour difference found
    between the two twins, each pinned by a `node:test` case.
  - Tests: `node:test` for the module, a bash suite that runs the launchers
    with a stub `wrangler` on PATH, Pester for the `.ps1` launcher under
    Windows PowerShell 5.1 and pwsh 7, and a scratch `aai-sync` install that
    runs both launchers there.
  - Wiring named up front: `tests/skills/suite-map.yaml` (with rows for any
    shared test lib the new suite reads), `tests/skills/suite-weights.tsv`,
    `tests/skills/lib/cd-subshell-leak-baseline.tsv`, the suite-map row-count
    pins in `tests/skills/test-aai-hygiene-pack.sh`, the nested-suite lint,
    both path lists of `.github/workflows/ps1-quality.yml`,
    `.aai/system/PROFILES.yaml` for the new module.
  - RFC-0017: the cloudflare-share inventory row and one phase 5 sentence, as
    rides 1 and 2 did. Phase 5 stays `in progress`.
  - Before/after code-line measurement with the plan's method.
  - CHANGELOG `## [unreleased] — <title>` per-entry heading.
- Out of scope:
  - `share-convert.mjs` (unchanged; the module runs it as before).
  - The `/aai-share` agent flow in `.aai/SKILL_SHARE.prompt.md` beyond what the
    plan requires; its harness wrappers stay unchanged.
  - Any other script pair (ride 4 onward); historical docs.

## Affected Area
- `.aai/scripts/cloudflare-share.sh`, `.aai/scripts/cloudflare-share.ps1`,
  `.aai/scripts/cloudflare-share.mjs` (new), `.aai/system/PROFILES.yaml`
- `tests/skills/` (new suite, node:test file, Pester file, wiring files)
- `.github/workflows/ps1-quality.yml`
- `docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md`, `CHANGELOG.md`

## Desired Behavior (To-Be)
- `bash .aai/scripts/cloudflare-share.sh <document.md>` and
  `powershell -File .aai/scripts/cloudflare-share.ps1 <document.md>` publish
  the same way on Linux, macOS and Windows: the same success lines, the same
  URL, one history record of the same shape, exit 0; every failure exits 1,
  names its cause and removes `.cloudflare-publish/`.

## Acceptance Criteria
- AC-001: The share logic lives in one Node module with an injectable deploy
  seam; both script files are launchers of at most 20 lines with the same
  names and arguments, exit 1 with an install hint without Node, and print the
  same success lines as today.
- AC-002: On macOS (BSD grep) a share with a stub `wrangler` succeeds: exit 0,
  the URL is reported and recorded, and no `.cloudflare-publish/` is left.
- AC-003: Every behaviour difference between the two twins is listed in the
  spec with a decision, and each has a `node:test` case.
- AC-004: The launchers pass under bash and under Windows PowerShell 5.1 and
  pwsh 7 (Pester), and a scratch `aai-sync` install ships the module and both
  launchers and publishes there through a stub `wrangler`.
- AC-005: Wiring is complete (suite map, weights, cd-subshell baseline,
  hygiene-pack pins, nested-suite lint, ps1-quality paths, PROFILES), the
  RFC-0017 inventory test passes, and the before and after code lines are
  measured and recorded.

## Verification
- The new suite and the touched suites pass (rc 0), run with
  `env -u AAI_ROLE -u AAI_GIT_WRITE`.
- The Windows CI job passes on the pull request under both engines.
- No test runs a real `wrangler` or reaches the network.

## Constraints / Risks
- The scripts never read Cloudflare credentials themselves: Wrangler reads
  `CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID` (or its own login) from the
  environment it inherits. The module passes the environment through
  unchanged and never prints it.
- Secrets preflight: no local secret is read by this scope; the two names
  above are only passed through, so no preflight lines are recorded.
- On Windows an npm-installed `wrangler` is a `.cmd` shim, which Node cannot
  spawn without a shell; the deploy seam must handle it.
- Changing shipped core scripts is consumer-visible; error lines of the `.sh`
  may move streams. The CHANGELOG names every changed behaviour.
- Windows parity is proven only by the hosted Windows job.

## Notes
- Source: roadmap item `cloudflare-share-on-node`; plan ride 3 (no owner
  sign-off required by the plan).
- Pattern precedents: CHANGE-0241 (`aai-reap-tests` port) and ride 1's
  migrate-state-to-local port (CHANGE-0245).
- Assumption (autopilot default): callers are `.aai/SKILL_SHARE.prompt.md`
  (names both scripts for non-agent use), `docs/TECHNOLOGY.md`, PROFILES and
  the test wiring; no shipped hook, routine, aai-sync, aai-update or
  aai-doctor path invokes the scripts.
- Autopilot defaults: human_time_minutes null; no implementation-mode menu
  (Planning decides).
