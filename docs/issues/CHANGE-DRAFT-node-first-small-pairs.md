---
id: node-first-small-pairs
type: change
number: null
status: draft
capability: node-first-core
parent: smaller-node-core-and-faster-feedback
links:
  pr: []
  commits: []
---

# Move three small paired scripts to Node (validate-skills, pre-compact-save, aai-live)

## Summary
- RFC-0017 lists the `.sh`/`.ps1` pairs left after phase 3. Three of the
  "later candidate" pairs are small and have no pre-Node caller:
  `validate-skills` (47/55 lines), `pre-compact-save` (77/87) and `aai-live`
  (125/90).
- Each one's logic moves to one Node module, and the two scripts become thin
  launchers (or go away where nothing calls them). This reuses the pattern of
  the phase 3 slices (CHANGE-0222, CHANGE-0223, CHANGE-0224).
- The RFC-0017 remaining-pairs inventory is updated to match the tree.

## Motivation / Business Value
- One implementation per behavior instead of two that drift apart: half the
  maintenance and review cost and no Bash/PowerShell drift.
- These three are the cheapest pairs to move: no network, no git write, no
  process supervision, no protected surface.
- The owner asked for this on 2026-11-01 (menu answer "1 2": finish the
  evidence-reuse ride, and meanwhile move the cheap later-candidate pairs).

## Scope
- In scope:
  - `validate-skills`: twelve required-file checks plus two advisory warnings
    move to `.aai/scripts/validate-skills.mjs`; the measured cosmetic drift
    between the copies (error wording, exit behavior) is recorded and one
    behavior chosen.
  - `pre-compact-save`: the context snapshot moves to
    `.aai/scripts/pre-compact-save.mjs`. Both copies read
    `docs/ai/STATE.yaml`, which is not where the live state file is today;
    Planning measures where STATE lives and either fixes the path (reading the
    legacy path as a fallback) or retires the pair if no shipped install wires
    the hook (SPEC-0248 recorded none). `aai-doctor` currently checks that both
    scripts exist; its check follows the decision.
  - `aai-live`: the browser-opener choice and `--output` resolution around
    `generate-live-status.mjs` move into Node (into that generator or a small
    module next to it), keeping `AAI_LIVE_OPENER`, `--watch`, `--data-only`
    and the exit codes.
  - Parity: the existing tests of each pair pass against the new
    implementation on Linux and on native Windows (Windows PowerShell 5.1 and
    pwsh 7), plus new `node:test` cases for the logic and for each measured
    drift.
  - Downstream installs made by `aai-sync` keep working (PROFILES entries,
    launchers, self-hosting smoke test).
  - The RFC-0017 "Remaining paired scripts after phase 3" table drops or marks
    the three moved pairs, and the phase 3 row is not reopened.
- Out of scope:
  - Any other pair (process adapters, platform adapters kept on purpose,
    aai-release, cloudflare-share, aai-canonicalize, migrate-yaml-to-jsonl).
  - New features in the three behaviors beyond the recorded drift and path
    choices.
  - Bash-only scripts without a PowerShell twin (aai-bootstrap,
    claude-hook-gate).

## Affected Area
- `.aai/scripts/{validate-skills,pre-compact-save,aai-live}.{sh,ps1}` and new
  `.mjs` modules (or `generate-live-status.mjs` for aai-live)
- `.aai/scripts/aai-doctor.mjs` (pre-compact-save presence check)
- Tests: `tests/skills/test-aai-live-status.sh`, `tests/skills/test-aai-doctor.sh`,
  `tests/self-hosting/test-self-hosting-smoke.{sh,ps1}`, new
  `tests/skills/lib/*.test.mjs` and Pester files
- `.aai/system/PROFILES.yaml`, `tests/skills/suite-map.yaml`,
  `.github/workflows/ps1-quality.yml` path lists
- `docs/rfc/RFC-0017-*.md` remaining-pairs table; `docs/USER_GUIDE.md` and
  `docs/product/live-status-dashboard.md` where they name the scripts

## Desired Behavior (To-Be)
- Each of the three behaviors has exactly one implementation, in Node.
- The old `.sh` and `.ps1` commands still work on both platforms with the same
  output and exit codes, apart from recorded drift and path choices (or the
  pair is removed with every caller updated).
- The RFC inventory matches the pairs present in `.aai/scripts/`.

## Acceptance Criteria
- AC-001: For each of the three pairs, the logic lives in one Node module; the
  `.sh` and `.ps1` contain no copy of it (launcher only, or removed with no
  remaining caller).
- AC-002: The pre-existing tests touching the three pairs pass (or carry a
  recorded, justified adjustment) on Linux and on the native Windows CI job
  under Windows PowerShell 5.1 and pwsh 7.
- AC-003: New `node:test` cases cover each module's logic, including every case
  where the two copies behaved differently.
- AC-004: pre-compact-save either reads the live STATE location (legacy path as
  fallback) or is retired; aai-doctor's check matches the outcome.
- AC-005: A downstream install made by `aai-sync` still runs each kept
  behavior from its launcher.
- AC-006: The net line count of the three pairs plus their modules is lower
  than before, and the measurement is recorded.
- AC-007: The RFC-0017 remaining-pairs table lists exactly the pairs present in
  `.aai/scripts/` (a test checks it), and phase 3 stays `done`.

## Verification
- The touched suites and the new `node:test` files pass (rc 0).
- The Windows CI job passes on the pull request under both engines.
- A scratch `aai-sync` install runs each kept behavior from its launcher.
- A test compares the RFC inventory with the pairs present in `.aai/scripts/`.

## Constraints / Risks
- Lessons from the phase 3 slices: Windows parity is proven only by the hosted
  Windows PowerShell 5.1 Pester job; a .NET Framework stdin writer prefixes a
  UTF-8 BOM to a child's stdin; a hosted failure is diagnosed with a probe
  before code changes.
- aai-live opens a browser: tests use `AAI_LIVE_OPENER` as the seam and never
  open a real browser.
- pre-compact-save is a harness hook; it must never fail loudly in a way that
  disturbs compaction.
- Changing shipped scripts is consumer-visible; merge stays with the owner.
- The evidence-reuse ride (precise-suite-evidence-reuse) runs at the same time
  in its own worktree; this ride uses a separate worktree, and full sweeps of
  the two rides are not run at the same time.
- No secrets referenced.

## Notes
- Source: RFC-0017 "Remaining paired scripts after phase 3" table (later
  candidates); owner menu answer 2026-11-01 "1 2".
- Assumption (autopilot default): all three pairs in one ride, since together
  they are under 500 lines; Planning may split if the evidence says so.
