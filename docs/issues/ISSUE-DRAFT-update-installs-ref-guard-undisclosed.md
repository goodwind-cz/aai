---
id: update-installs-ref-guard-undisclosed
type: issue
number: null
status: draft
links:
  pr: []
  commits: []
---

# /aai-update silently arms a git ref-guard in every consumer, under a licence written for a different hook

## Summary
- `.aai/SKILL_UPDATE.prompt.md` step 4 instructs the agent to run
  `install-pre-commit-hook.sh` after a successful sync and explicitly to NOT ask
  first. It justifies that licence with one safety property: the installer
  "refuses to overwrite a foreign pre-commit hook".
- That justification was written on 2026-08-13 (commit 3758e00b), when the
  installer managed exactly one hook. On 2026-08-29 (commit b12df3f4, PR #302,
  SPEC-0156) the same installer gained a SECOND hook — a
  `reference-transaction` guard, marker `AAI:REF-GUARD`, which refuses every
  `refs/heads/main` update unless `AAI_GIT_WRITE=1` is set on that exact command.
- Step 4 was never updated. The ask-nothing licence, scoped to the docs-index
  convenience hook, now also covers a hook that changes how `git` itself behaves
  in the consumer's repository.
- There is no way to decline. `install-pre-commit-hook.sh` accepts only
  `--force`, `--uninstall`, `--print` — no per-hook switch. Taking the
  docs-index hook without the ref-guard is not expressible.
- The blast radius is downstream, not here. SPEC-0156 reasons about "the
  shipping repo" and never uses the words downstream, consumer, vendored or
  opt-out, but the guard ships inside the vendored `.aai/` layer and `CAT-17`
  WARNs in any project that does not have it armed. A policy chosen for the
  canonical repo became the default for every consumer of it.

## Type
- bug

## Impact
- Affected: every project that runs `/aai-update` on or after AAI
  `v2026.08.29`. Observed on an unrelated downstream project (Feramat/DashDev)
  on 2026-09-10 against pin `v2026.09.09`.
- The consumer's next `git commit`, `git merge`, fast-forward `git pull` or
  `git reset` on `main` is refused until they discover `AAI_GIT_WRITE=1`. The
  refusal message names the guard, so it is recoverable — but it arrives
  unannounced, from a command the operator ran to refresh documentation
  tooling.
- Reported upstream through the friction channel as
  `goodwind-cz/aai#369` (`contract_violation`, SKILL_DOCTOR,
  `evidence_ref: SPEC-0156`, `workaround: manual`).
- Severity: medium. Not destructive and not a data-loss risk; it is an
  undisclosed change to a consumer's git behaviour, and a contract the update
  prompt states inaccurately.

## Current Behavior
- Step 4 of `SKILL_UPDATE.prompt.md` runs the installer with no arguments.
- The installer writes BOTH hooks at the effective hooks path (the one
  `git rev-parse --git-path` resolves) and prints two install lines.
- The agent's report, following step 4's own wording, mentions the docs-index
  hook as the expected outcome; the ref-guard shows up only as an aside.
- The operator has no flag that installs one hook and not the other.
- A consumer who removes the guard afterwards trades the surprise for a
  permanent `CAT-17 WARN` in every `/aai-doctor` run, because `CAT-17` treats
  "not armed" as a finding regardless of whether the project wants it armed.

## Expected Behavior
- The ref-guard is disclosed before it is installed, or installed only on an
  explicit opt-in — the operator learns that their git behaviour is about to
  change from the update flow, not from the first refused commit.
- The installer exposes a per-hook selection so the docs-index hook and the
  ref-guard can be installed independently.
- `SKILL_UPDATE.prompt.md` step 4 describes what the installer actually does
  today, and its stated safety property covers both hooks or is re-scoped.
- `CAT-17` distinguishes "armed", "deliberately not armed" and "unarmed by
  accident", so a project that declines the guard is not permanently DEGRADED
  for a choice the canonical repo made for itself.

## Steps to Reproduce (if applicable)
1) Take any project vendoring an AAI layer older than `v2026.08.29`, on a
   branch other than `main`, with no AAI git hooks installed.
2) Run `/aai-update` (non-dry-run) against `goodwind-cz/aai@main`.
3) Observe that step 4 installs the `reference-transaction` hook alongside the
   pre-commit hook: `git rev-parse --git-path hooks/reference-transaction`
   resolves to a file containing `AAI:REF-GUARD`.
4) Check out `main` and commit anything. The commit is refused with the
   `AAI:REF-GUARD refused this refs/heads/main update` message.
5) Re-run the installer looking for a way to keep step 3's docs-index hook
   while dropping the guard. No such flag exists.

## Verification
- `bash .aai/scripts/install-pre-commit-hook.sh --help` documents a per-hook
  selection, and a run selecting only the docs-index hook leaves
  `git rev-parse --git-path hooks/reference-transaction` with no AAI-managed
  file.
- The inverse selection installs only the guard and leaves any existing
  pre-commit hook untouched.
- `/usr/bin/grep -n "REF-GUARD" .aai/SKILL_UPDATE.prompt.md` returns a step-4
  line naming the guard and its effect on `refs/heads/main`.
- A project that has deliberately declined the guard runs `/aai-doctor` and
  `CAT-17` does not count as an issue in the `DOCTOR ISSUES(n)` total.
- The existing installer suites still pass (`.aai/scripts/aai-run-tests.sh`
  selected suites covering the hook installer and doctor categories), and the
  idempotency and foreign-hook-refusal behaviour is unchanged for both hooks.

## Constraints / Risks
- The guard is a genuine safeguard, not decoration: SPEC-0156 D1/D3 record that
  it is the only chokepoint an agent shell cannot route around. Making it
  opt-out must not make it hard to keep — the default should stay "armed", with
  disclosure, not "off".
- Whether a consumer project WANTS operator-only writes to `main` is that
  project's call, not the canonical repo's. Changing `CAT-17` to honour a
  declared choice needs somewhere to declare it; picking that surface is part
  of the work, not assumed here.
- `SPEC-0156` is frozen and `done`. This issue does not reopen its decision —
  the guard stays. It addresses the delivery of that decision to consumers,
  which the spec never covered.
- The installer writes to the path `git rev-parse --git-path` resolves, which
  honours `core.hooksPath` and linked worktrees. Any new per-hook switch must
  preserve that resolution and the both-hooks-checked-before-either-is-written
  ordering, or a foreign hook in one slot can cause a partial install.
- No secret is referenced by this scope; secrets preflight skipped.

## Notes
- Root cause is a licence outliving its justification: step 4's "do NOT ask
  first" was correct for the hook it was written about, and adding a second
  hook to the invoked script silently widened it. The disclosure belongs to the
  installer, which knows what it installs, rather than to the caller, which
  described it once.
- Second lesson, same root: anything landing in `.aai/` is shipped to consumer
  projects. `SPEC-0156` reasoned entirely about this repository; the vendored
  layer carried its conclusion outward without the spec ever saying what a
  consumer would experience.
- Discovered while reviewing an `/aai-update` run on an unrelated project on
  2026-09-10 (upstream pin `v2026.09.09`, template commit fa2e917).
- Related friction issues filed the same day: `goodwind-cz/aai#368`
  (`deterministic_script_failure`, REMEDIATION/reproduce) — unrelated to this
  scope.
- Out of scope, noted here so they are not lost: `aai-doctor.mjs` CAT-14 reports
  `N/3 arms passed` without naming the failing arm in text mode (the arm names
  live in `detail`, which text mode deliberately omits), and CAT-08 reliably
  WARNs after an update because the update itself leaves the tree dirty.
