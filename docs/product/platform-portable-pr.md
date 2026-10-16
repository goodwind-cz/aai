---
id: platform-portable-pr
type: product
capability: platform-portable-pr
status: current
delivered_by:
  - CHANGE-0085
  - git-platform-detected-at-bootstrap
spec: docs/specs/SPEC-0103-spec-platform-portable-pr.md
updated: 2026-10-16
---

# Platform-portable PR ceremony

## What it does

Bootstrap records which git host the project lives on (GitHub, Azure DevOps,
unknown or none) once, and `/aai-merge` follows that record: a directed
merge and the post-merge cleanup now work on Azure DevOps as well as on
GitHub, without ever calling `gh` there.


The PR ceremony (`/aai-pr`, `/aai-ship`) now works beyond GitHub. A
deterministic probe classifies the origin remote and the ceremony
branches accordingly; where reviewer bots do not exist, the factory's own
independent code review takes their place — quality is never silently
skipped on any git host.

## How to use it

- Nothing changes on GitHub. On Azure Repos the ceremony uses `az repos`
  commands; on any other host GENERIC MODE runs the internal review and
  hands the merge to you with an explicit message.
- Probe manually: `node .aai/scripts/pr-platform.mjs` (add `--json` for
  machine output; embedded credentials are always masked).
- Bootstrap writes `platform:` into `docs/ai/pr-config.yaml` and reports
  whether that host's CLI is signed in (`gh auth status`, or `az account
  show` plus the azure-devops extension). Record or re-record by hand:
  `node .aai/scripts/platform.mjs record` (`--force` to replace a value
  that no longer matches `origin`; without it a mismatch is reported, never
  overwritten).
- `/aai-merge <n>` on Azure DevOps prints and runs
  `node <repo>/.aai/scripts/platform.mjs merge --pr <n> --expect-head <sha>`
  instead of `gh pr merge`; everything after the merge (base sync,
  worktree and branch removal) is the same as on GitHub.

## Data model

- Probe output: `PLATFORM <github|azure|unknown|none> remote=<sanitized>`;
  `--json` = `{platform, remote}` (sanitized only).
- `docs/ai/pr-config.yaml` gains `platform: <github|azure|unknown|none>`
  next to `reviewer_bots`. A project with no recorded value keeps working:
  an Azure origin is treated as Azure, anything else as GitHub.

## Interfaces and contracts

- A recorded platform that no longer matches `origin` makes `/aai-merge`
  refuse before any read or write: `REFUSE platform_mismatch recorded=<r>
  detected=<d> re-record: node .aai/scripts/platform.mjs record --force`.
  A recorded `unknown` or `none` refuses `platform_generic`; merge in the
  host's own UI.
- Azure merge exit codes: 0 merged; 3 refused (nothing completed); 4
  completion still pending (re-run `/aai-merge <n>`); 5 `head_race_lost`,
  naming the expected and the merged head (stop; the owner's direction does
  not cover a head they did not name).

- Reviewer-fallback: on a platform without reviewer bots, an internal
  SKILL_CODE_REVIEW dispatch on the final PR diff is REQUIRED before any
  merge-readiness claim; findings are published as PR threads with
  closing replies; the PR records "internal review substituted for
  absent bot layer".
- GENERIC MODE ends with: "platform PR API unavailable — internal review
  substituted, merge is yours"; findings live in docs/ai/reports/ + spec
  dispositions. The agent-never-merges boundary is unchanged everywhere.

## Limits

- Azure has no head-pinned merge flag. `/aai-merge` checks the PR head
  immediately before completion and re-reads it afterwards, so a push in
  between is detected and reported, not prevented.
- Only `/aai-merge` uses the recorded platform so far. CI watching, merge
  lanes, the PR preflight, the close ceremony, release and the merge hook
  still call `gh` directly; they move over in later rides. The merge hook
  does not yet gate the Azure merge command.
- GitHub Enterprise hosts are recorded as `unknown`, which puts `/aai-merge`
  into generic mode there; keep or restore the unrecorded state until that
  is fixed.
- Not yet proven against a live Azure DevOps organisation or on a real
  Windows host.

- Azure command forms are doc-verified; the live round trip (incl. thread
  publication via `az devops invoke --resource pullRequestThreads`) is
  the Spec-AC-06 evidence contract at first Azure adoption (Review-By
  2026-08-15). GitLab/Bitbucket adapters are future variants.
- A GitHub repo with reviewer bots disabled keeps the empty-sweep
  shortcut (frozen-spec design; recorded hardening candidate R1).
