---
id: skill-suite-linux-ci-portability
number: 43
type: change
status: done
links:
  pr:
    - 116
  commits:
    - 1723088986d10ebcff1ab10b42d81354cb3b586e
---

# Make the skill test suites pass on the Linux CI runner (Ubuntu)

## Summary
- The new `skill-suite.yml` CI gate (CHANGE-0042/SPEC-0061) is RED on the Ubuntu
  runner while every suite passes on macOS. Root-cause analysis (via the
  framework's now-always-on failure dump, plus reading the CI log) reduces the
  ~15 failing suites to FOUR causes, mostly BSD/GNU tool differences and
  fresh-checkout environment gaps — not deep rot. Fix all four so the gate is
  green and can be enforced.

## Motivation / Business Value
- The gate exists to stop skill-suite regressions shipping unseen. It cannot be
  trusted (or enforced) while it is red for environmental reasons. Green-on-Linux
  is the precondition for the gate to do its job and for PR #116 to merge.

## Scope
- In scope: the four root-cause fixes below + any CI-workflow environment seeding
  needed. All changes land on branch `feat/test-infra-reds-and-ci-gate` (PR #116)
  so the gate turns green in the same PR that introduces it.
- Out of scope: rewriting suites beyond what each root cause requires; the three
  reds already fixed in CHANGE-0042 (they are CI-green).

## Affected Area
- `tests/skills/test-aai-prompt-diet.sh` (RC2), `.github/workflows/skill-suite.yml`
  and/or specific suites (RC1, RC3), `tests/skills/test-aai-update.sh` (RC4).

## Desired Behavior (To-Be)
- `bash tests/skills/test-framework.sh` exits 0 on the Ubuntu CI runner; the
  `skill-suite` CI job on PR #116 goes green.

## Root causes (from investigation 2026-07-19)
- **RC2 (highest leverage — one line, unblocks ~7 suites):**
  `tests/skills/test-aai-prompt-diet.sh:392`
  `fixture="$(mktemp -t aai-wrapper-ceiling-fixture)"`. BSD `mktemp -t <prefix>`
  works; GNU (Linux) `mktemp -t <template>` requires `XXXXXX` and errors
  "too few X's" → `$fixture` empty → `> ""` / `wc -l < ""` / `grep … ""` →
  "No such file". prompt-diet is a sub-check invoked by advisory-skills,
  constitution, debug-gate, delta-stage2, delta-stage3, hooks-overlay, spec-lint
  — so all seven cascade from this single line.
- **RC1 (gitignored runtime files absent on a fresh checkout):** `docs/ai/STATE.yaml`
  is gitignored (RFC-0001, per-dev) so it does not exist on the CI checkout;
  ceremony-levels / orchestration-dispatch / orchestration-mode call
  `check-state.mjs` against the real `docs/ai/STATE.yaml` and fail
  "STATE file not found". tdd-evidence needs
  `docs/ai/tdd/dispatch-retarget-red.log` (also gitignored). Fix: seed these
  preconditions (CI workflow step and/or make the suites self-seed a fixture).
- **RC3 (base ref `main` absent on detached CI checkout):**
  `test-aai-doc-numbering.sh` / `test-aai-doc-number-reservation.sh` invoke the
  allocator with `--base-ref main`; the runner's temp repos / detached PR
  checkout lack a local `main` (default may be `master`; no remote to fetch) →
  "base ref main is unreachable (offline / fetch failed)". Fix: ensure a local
  `main` ref in CI (e.g. `git branch --force main origin/main`) and/or set
  `init.defaultBranch=main` for the suites' temp repos.
- **RC4 (`stat -f` means different things on BSD vs GNU):**
  `test-aai-update.sh:243`
  `owner_uid="$(stat -f '%u' … || stat -c '%u' …)"`. On Linux `stat -f`
  SUCCEEDS (it is `--file-system`, printing filesystem info) so the `|| stat -c`
  fallback never runs and `owner_uid` is garbage → TEST-005a ownership assert
  fails. Fix: try GNU `stat -c` first (or detect OS / use `-c` on Linux), so the
  correct per-file uid is read on both platforms.

## Acceptance Criteria
- AC-001: `tests/skills/test-aai-prompt-diet.sh` uses a portable temp-file
  template (contains `XXXXXX`, or no `-t`) so it runs on GNU mktemp; the suite
  and its seven dependents pass on Linux.
- AC-002: The suites that require `docs/ai/STATE.yaml` (and the tdd fixture log)
  pass on a fresh checkout where those gitignored files are absent — via a seeded
  precondition (CI step or self-seed). No suite depends on a developer's local
  gitignored runtime file existing.
- AC-003: `test-aai-doc-numbering.sh` and `test-aai-doc-number-reservation.sh`
  pass on the detached CI checkout (a resolvable `main` base ref is available).
- AC-004: `test-aai-update.sh` TEST-005a reads the correct file owner uid on
  Linux (GNU `stat -c` path taken) and passes.
- AC-005: The `skill-suite` CI job on PR #116 is GREEN (all suites pass on
  Ubuntu); `bash tests/skills/test-framework.sh` continues to pass on macOS.

## Verification
- Primary (authoritative): the `skill-suite` GitHub Actions job on PR #116 goes
  green (`gh run … --json conclusion` = success). This is the ONLY environment
  that reproduces the failures — local macOS passes regardless.
- Local (non-regression): `bash tests/skills/test-framework.sh` on macOS stays
  green; targeted suites (`test-aai-prompt-diet.sh`, `test-aai-update.sh`) stay
  exit 0.
- RC2 spot-check: on a GNU system, `mktemp -t <template-without-XXXX>` errors —
  confirm the new form does not.

## Constraints / Risks
- The suites can only be verified on Linux via CI (or a Linux container, which is
  unavailable on this host). Each CI round-trip is ~4 min; batch fixes.
- Seeding STATE.yaml in CI must use the canonical default (via `check-state.mjs
  --repair` or `state.mjs` init), never a hand-written stub that could drift.
- RC3's `git branch --force main origin/main` must not disturb the suites that
  create their own temp repos — verify those set their own default branch.
- No secret referenced — SECRETS PREFLIGHT skipped.

## Notes
- The framework diagnostics improvement (always dump failing-suite tails, not
  only in `--verbose`) is already committed to the branch (21a0291) and is what
  made this root-cause analysis possible from the CI log alone.
