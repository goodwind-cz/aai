---
id: node-first-phase5-closeout
type: change
number: null
status: draft
capability: node-first-phase5-closeout
user_visible: true
parent: smaller-node-core-and-faster-feedback
links:
  pr: []
  commits: []
---

# Close RFC-0017 phase 5: every shipped script is a launcher or kept native on purpose

## Summary
- The last step of RFC-0017 phase 5, after rides 1 to 12 of the
  [remaining-scripts plan](../analysis/node-first-remaining-plan.md). The
  re-measure after ride 12 (plan section 6) found twin duplication 0, but six
  scripts still carrying logic and two P2 follow-ups of the plan's refs open.
- Owner decisions (2026-11-23) for this ride:
  1. `.aai/scripts/claude-hook-gate.sh` (63 code lines, the bash pre-filter
     the hook-gate ride kept by design) goes on the RFC-0017 "Kept native
     scripts" list with its reason.
  2. `.aai/scripts/lib/test-residue.sh`, `lib/repo-tripwire.sh`,
     `lib/append-lock.sh` and `lib/git-bash-path.sh` go on that list with
     their reasons: they are sourced by the bash test runner or by the git
     hooks, which stay bash.
  3. `.aai/scripts/aai-release.ps1` (25 code lines) becomes a thin launcher
     of 20 code lines or fewer with no policy and unchanged behaviour; any
     logic moves into the Node release module; Pester under Windows
     PowerShell 5.1 and pwsh 7 still passes; the launcher follows the
     pattern of `aai-sync.ps1` and `aai-update.ps1`.
  4. The P2 phase 5 blockers `fu-cfshare-redact-escape-robust` and
     `fu-parity-win-odd-root-dirs`, and the reopened
     `fu-parity-win-source-path`, are closed test-first, each with evidence.
     The earlier test of `fu-parity-win-source-path` did not exercise the
     Windows path; the new test must, proven on the native Windows CI job.
- The kept-native list becomes machine-checked: a test enumerates every
  `.sh` and `.ps1` under `.aai/scripts` (including `lib/`) and fails unless
  each one is a launcher (20 code lines or fewer by the plan's section 1
  method, no policy), a row of the RFC-0017 kept-native table with a reason,
  or absent.
- RFC-0017 and the plan record the phase 5 status with a fresh re-measure;
  phase 5 is marked done only when every section 5 criterion holds,
  including the Windows PowerShell 5.1 and pwsh 7 CI legs green on the pull
  request head. Otherwise the record lists exactly what remains.

## Motivation / Business Value
- Phase 5's done criteria (plan section 5) cannot be met while six scripts
  are neither launchers nor named on the kept-native list; the owner decided
  which stay native and which shrink.
- Today the kept-native rule is prose plus a re-measure table that a later
  edit can let drift (TEST-4022 accepts a `logic` row as long as section 6
  names it). A test that fails on any undeclared logic script keeps the
  migration from regressing silently.
- `fu-cfshare-redact-escape-robust` (P2): the share command's redaction can
  print most of a credential tail when an unterminated CSI escape precedes a
  value split by a complete escape, and a raw ESC can reach stderr because
  the ANSI pattern misses nF/Fp escapes (`ESC 7`, `ESC 8`, `ESC ( B`).
- `fu-parity-win-odd-root-dirs` (P2): on Windows the bash update left empty
  root directories with unreadable wide-character names in the target
  project, visible in `git status`.
- `fu-parity-win-source-path` (P3, reopened): on Windows the bash sync
  recorded the source path as `/c/Users/...` where PowerShell recorded
  `C:\Users\...`; its close evidence ran on POSIX only.

## Scope
- In scope:
  - RFC-0017 "Kept native scripts" table: five new rows (the hook-gate
    pre-filter and the four bash libraries) with reasons; the existing four
    rows stay.
  - `aai-release.ps1` as a launcher of 20 code lines or fewer, no policy,
    behaviour unchanged (flags `-Version`, `-DryRun`, `-Confirm`, `-Yes`,
    `-NoRemote`, `-h`, extra arguments, the missing-Node refusal and its
    exit code, exit codes passed through); any marshalling that cannot fit
    moves into `aai-release.mjs` (or a launcher-argument helper it uses).
  - A machine check (a test, Planning names its suite and ids through the
    allocator) over every tracked `.sh`/`.ps1` under `.aai/scripts`: each is
    a launcher, a deprecation launcher (still 20 code lines or fewer, no
    policy), or a kept-native row with a non-empty reason; a kept-native row
    naming an absent file also fails.
  - `fu-cfshare-redact-escape-robust`: failing test first (the probe of the
    follow-up and nF/Fp escapes), then the fix in `cloudflare-share.mjs`.
  - `fu-parity-win-odd-root-dirs`: a test on the native Windows parity job
    that runs the shipped update path under Git Bash and asserts no new odd
    root entry; root cause found and fixed, or proven to live only in the
    frozen bash reference that no longer ships (then the shipped path is
    proven clean and the allowlist row is re-justified).
  - `fu-parity-win-source-path`: a test that runs the shipped
    `aai-sync.sh` launcher under Git Bash on native Windows and asserts the
    pin and the sync-conflicts report record the Windows spelling of the
    source path; the allowlist rows tracked by this follow-up are updated to
    match what remains (frozen reference only, or removed).
  - Updates to the earlier ride's checks that pin the current state
    (TEST-4021 expects `fu-parity-win-source-path` open, TEST-4022 expects
    the section 6 list), so they follow the new state rather than block it.
  - Plan doc and RFC-0017: a re-measure section for this ride (method of
    section 1), the phase 5 row status and what remains, if anything.
  - Wiring: suite map, weights, hygiene pins, `ps1-quality.yml` path lists,
    PROFILES classification if a shipped file is added, CHANGELOG
    `## [unreleased] — <title>` entry only for consumer-visible changes
    (the redaction fix and the Windows update and sync fixes are), product
    doc per the ship flow.
- Out of scope:
  - Porting `aai-run-tests`, `aai-win-selftest.ps1`, `pre-commit-checks.sh`,
    the hook-gate pre-filter or the four bash libraries (kept native).
  - Deleting the deprecation launchers (they go in the next release, owner
    decision 2 of the plan).
  - `docs/ai/docs-audit.yaml` `protected_paths_l3` and PR #535.

## Affected Area
- `.aai/scripts/aai-release.ps1`, `.aai/scripts/aai-release.mjs` (argument
  intake only), `.aai/scripts/cloudflare-share.mjs`
- The update and sync path only if the odd-root-dirs or source-path root
  cause is in shipped code (`aai-update.mjs`, `aai-sync.mjs`, the doctor
  report helper, their launchers)
- `tests/skills/` (release, cloudflare-share, install-parity, sync-docs
  suites, Pester files, a new or extended machine check), wiring files
- `.github/workflows/ps1-quality.yml` (only if the Windows proof needs a step)
- `docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md`,
  `docs/analysis/node-first-remaining-plan.md`, `CHANGELOG.md`,
  `docs/product/`

## Desired Behavior (To-Be)
- Every `.sh` and `.ps1` under `.aai/scripts` is a launcher or is named on
  the RFC-0017 kept-native list with its reason, and a test fails the
  moment that stops being true.
- `aai-release.ps1` behaves exactly as before for every flag and exit code,
  in 20 code lines or fewer.
- The share command never prints a credential tail of eight or more
  characters and never writes a raw ESC byte, for any escape layout.
- On native Windows, the shipped update leaves no odd root directory, and
  the shipped sync records the source path in the Windows spelling.

## Acceptance Criteria
- AC-001: The RFC-0017 kept-native table names `claude-hook-gate.sh`,
  `lib/test-residue.sh`, `lib/repo-tripwire.sh`, `lib/append-lock.sh` and
  `lib/git-bash-path.sh` with a reason each, besides the four existing rows.
- AC-002: A test enumerates every tracked `.sh` and `.ps1` under
  `.aai/scripts` (lib included) and fails on any file that is neither 20
  code lines or fewer with no policy (section 1 method) nor a kept-native
  row with a non-empty reason, and on a kept-native row naming a file that
  is not tracked; it is proven to fail on a seeded logic script and on a
  seeded row without a reason.
- AC-003: `aai-release.ps1` has 20 code lines or fewer and no policy; every
  flag, the help, extra arguments, the missing-Node refusal (its line and
  exit code) and the module's exit codes behave as before, proven by the
  release suites and Pester under Windows PowerShell 5.1 and pwsh 7.
- AC-004: `fu-cfshare-redact-escape-robust` closed with evidence: a test
  that failed before the fix shows no credential tail of eight or more
  characters for the follow-up's probe and no raw ESC byte for nF/Fp
  escapes in the output.
- AC-005: `fu-parity-win-odd-root-dirs` closed with evidence from a test
  that runs the shipped update path under Git Bash on the native Windows
  job and asserts no odd root entry is born; the root cause is named.
- AC-006: `fu-parity-win-source-path` closed with evidence from a test that
  runs the shipped `aai-sync.sh` under Git Bash on the native Windows job
  and asserts the Windows spelling in the pin and the report; the test
  cannot pass vacuously on POSIX (it is proven to run on Windows by its
  output in the CI log).
- AC-007: The plan doc and RFC-0017 record a re-measure with the section 1
  method; the phase 5 status is done only if every section 5 criterion
  holds, including green Windows PowerShell 5.1 and pwsh 7 legs on the pull
  request head; otherwise the record lists exactly what remains; the
  earlier ride's checks (TEST-4021, TEST-4022) follow the new state; the
  existing suites pass.

## Verification
- `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash <suite>` for the
  release, cloudflare-share, parity, sync-docs and new suites.
- The `ps1-quality` workflow on the pull request head: the Windows
  PowerShell 5.1 and pwsh 7 legs and the windows-parity job green, with the
  new Windows assertions visible in their logs.

## Constraints / Risks
- Ceremony L3, merge by the owner (owner directive for this ride).
- The Windows proofs need the hosted Windows job; a local macOS run cannot
  exercise them, so the close of AC-005 and AC-006 depends on the PR's CI.
- Tests never sync, update, install hooks or release into this repository
  or any real one; scratch only, cleaned on failure; `GIT_CONFIG_*`
  scrubbed; no container daemon; no real tag, release or push.
- TEST-4000 to TEST-4002 exist twice (SPEC-0309 and SPEC-0310): new TEST ids
  come from the allocator, never reused.
- Secrets preflight: no local secret is referenced by this scope.

## Notes
- Source: owner brief 2026-11-23 (phase 5 closeout after PR #581).
- Worktree: owner-directed own worktree
  (`/Users/ales/Projects/aai-worktrees/node-first-phase5-closeout`, branch
  `chore/node-first-phase5-closeout`).
- Autopilot defaults: human_time_minutes null; no implementation-mode menu
  (Planning decides).
