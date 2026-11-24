---
id: node-first-leftovers
type: change
number: null
status: draft
capability: node-first-leftovers
user_visible: false
parent: smaller-node-core-and-faster-feedback
links:
  pr: []
  commits: []
---

# Node-first leftovers: the P3 fixes the migration left open

## Summary
- This is the second ride of the owner's 2026-11-24 node-first cleanup
  brief. The first ride (`node-first-cleanup`) takes the P2 items and the
  suite weights. This ride takes the P3 leftovers of the Node-first
  migration that are fixes.
- The brief also lists five P3 items that the measurement shows to be
  behaviour-contract changes pinned by frozen specs, not fixes. Per the
  brief, they stay open with evidence and are not done here:
  - `fu-runner-git-env-scrub`: SPEC-0310 D-GITENV chose a per-suite scrub.
  - `fu-bootstrap-seed-use-shared-lib`: SPEC-0306 Spec-AC-09 pins the
    bootstrap gitignore seed without CR stripping.
  - `fu-sync-aai-prefix-ignore`: SPEC-0310 pins the prefix rule as parity.
  - `fu-hook-upgrade-resets-mode`: SPEC-0308 pins the mode as parity.
  - `fu-parity-odd-row-tracker-successor`: the item tracks the allowlist
    row until `fu-parity-win-odd-root-cause` is named; that is correct as
    it stands.
- In scope:
  1. `fu-cfshare-redact-eaten-chars`: the share failure echo can still show
     18 of 20 token characters when unterminated escapes eat single
     characters.
  2. `fu-update-ps1-colon-flag-forms` and `fu-update-ps1-colon-switch-args`:
     `aai-update.ps1` passes `-DryRun:$false`, `-DryRun:true`, `-Repo:X`
     and in-session arrays to Node as literal words.
  3. `fu-sync-dr33-overbroad-managed-refusal` and
     `fu-sync-dr33-test-non-aai-entries`: the DR-33 refusal line says
     "which the sync replaces" for entries the sync only manages, and its
     test covers `.aai` only.
  4. `fu-sync-ps1-51-native-arg-quoting`: under Windows PowerShell 5.1,
     `-TargetRoot 'C:\My Projects\app\'` reaches Node with an embedded
     quote.
  5. `fu-sync-eagain-nonblocking-stdout`: `aai-sync.mjs` aborts mid-prune
     with EAGAIN on a non-blocking stdout pipe.
  6. `fu-guard-dials-ignore-bom`: a BOM-prefixed first line hides the first
     guard dial from `readGuardConfig` and from its shell mirrors.
  7. `fu-doubled-key-warning-valueless-first`: the doubled `ref_guard:`
     warning says "the first one wins" when a valueless first line loses.
  8. `fu-classify-socket-long-tmpdir`: TEST-3987 fails with EADDRINUSE
     when a long macOS TMPDIR pushes the socket path past 103 bytes.
  9. `fu-dr20-note-double-slash-pwd` and `fu-changelog-dr5-hooks-print`:
     one clause each in SPEC-0308 DR-20 and in the CHANGELOG.

## Motivation / Business Value
- Item 1 is security-relevant. A credential fragment can reach the share
  command's failure echo.
- Items 2 and 4 are PowerShell users' argument forms that silently do
  the wrong thing or fail closed.
- Items 5 and 6 make a direct run fail, or make one config file read two
  ways.
- Items 3, 7, 8 and 9 are wrong messages, a test gap or a flaky host
  case.

## Scope
- In scope: items 1 to 9, their tests, CHANGELOG entries, amendment
  records for frozen specs whose pinned text changes, and closing each
  item with evidence.
- Out of scope:
  - the five design items named above (they stay open with evidence);
  - `fu-parity-win-odd-root-cause` (owner decision);
  - the P2 items of the first ride.

## Affected Area
- `.aai/scripts/cloudflare-share.mjs`, `.aai/scripts/aai-update.ps1`,
  `.aai/scripts/aai-update.mjs`, `.aai/scripts/aai-sync.ps1`,
  `.aai/scripts/aai-sync.mjs`, `.aai/scripts/lib/guard-config.mjs`
  (L3).
- `.aai/scripts/pre-commit-checks.sh` (L3), and
  `.aai/templates/git-hooks/pre-commit-index.sh` and `pre-push.sh` (L3,
  the dial greps only).
- `.aai/scripts/install-pre-commit-hook.mjs` (L3, one message).
- Tests: `tests/skills/lib/*.test.mjs` and the Pester files.
- `docs/specs/SPEC-0308-spec-pre-commit-installer-on-node.md` (one
  clause) and `CHANGELOG.md`.

## Desired Behavior (To-Be)
- No eight-character run of the echo matches a secret even when escapes
  ate characters of it.
- The update launcher treats colon forms and arrays as the sync launcher
  does.
- The DR-33 line names what it guards, and the tests cover two managed
  entries other than `.aai`.
- A 5.1 `-TargetRoot` ending in a backslash reaches Node intact.
- The sync completes on a non-blocking stdout.
- A BOM never hides a guard dial.
- The doubled-key warning names the line that wins.
- The socket test passes on a long TMPDIR.
- The two documentation clauses are fixed.

## Acceptance Criteria
- AC-001: the share failure echo of the repro input holds no 8 consecutive
  characters that appear in order inside any 10 consecutive token
  characters.
- AC-002: `aai-update.ps1 -DryRun:$false` runs without dry-run,
  `-DryRun:$true` and `-DryRun` run with it, and `-Repo:X` sets the
  repository.
- AC-003: the DR-33 refusal for `.claude/...` and `.codex/skills/...`
  sources is tested, and the line no longer claims the sync replaces them.
- AC-004: under Windows PowerShell 5.1 a `-TargetRoot` value with a space
  and a trailing backslash reaches Node as the same path.
- AC-005: an EAGAIN from `fs.writeSync` is retried and the sync completes.
- AC-006: a BOM-prefixed `docs/ai/docs-audit.yaml` whose first line is a
  dial reads that dial in Node and in each shell mirror.
- AC-007: the doubled-key warning names the line whose value wins.
- AC-008: the socket case of TEST-3987 passes when TMPDIR is longer than
  80 bytes.
- AC-009: SPEC-0308 DR-20 and the CHANGELOG carry the two clauses.

## Verification
- The touched suites through `.aai/scripts/aai-run-tests.sh` with
  `env -u AAI_ROLE`, and the Pester legs on the hosted ps1-quality
  workflow (Windows PowerShell 5.1 and pwsh 7).

## Constraints / Risks
- L3 surfaces (`guard-config.mjs`, `pre-commit-checks.sh`, the hook body
  templates, `install-pre-commit-hook.mjs`), so ceremony level 3: the owner
  merges.
- The first ride edits other lines of `pre-commit-index.sh`. The two pull
  requests must merge without conflict, and the second rebases if needed.
- Windows PowerShell 5.1 behaviour is proven only on the hosted Windows
  leg.
- No secret is referenced. The tests use fake token values only.

## Notes
- Worktree: a sibling of the first ride's worktree,
  `/Users/ales/Projects/aai-worktrees/node-first-leftovers`, from
  origin/main. The second pull request of the owner's brief needs its own
  branch.
- Implementation mode: Planning decides. The owner's brief asks for TDD.
