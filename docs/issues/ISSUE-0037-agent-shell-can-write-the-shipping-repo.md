---
id: agent-shell-can-write-the-shipping-repo
type: issue
number: 37
status: draft
links:
  pr: []
  commits: []
---

# Nothing structurally stops an agent shell or its probes from writing the shipping repository

## Summary
- Code an agent runs OUTSIDE the test framework — probe helpers, one-liners, sed
  mutations, ad hoc `git` verification — executes with the shipping checkout as its
  working directory and full write access to it. The only control is prose.

## Type
- bug

## Impact
- Affected: the shipping checkout (`$PROJECT_ROOT`) and every ride that runs
  in it. Four recorded instances, one of them P1, over 13 days.
- The failure mode is silent: a probe writes, the write survives into a later sweep,
  and the cost is paid by whichever run notices next.
- Severity: the registry carries this as P1 (`fu-subagent-probe-hits-real-repo`).

## Current Behavior
- `fu-subagent-probe-hits-real-repo` (P1, 2026-08-15): "a validator probe helper ran
  git commands against the real repository and created two commits on main". The
  helper `cd`-ed into a fixture inside a command substitution, which runs in a
  subshell, so the parent shell never left the real repository. Repaired by hand with
  `git reset --mixed 5116c36`.
- `fu-empty-path-cd-stays-in-shipping-repo` (P2, 2026-08-23): a `local a=1 b=$a` chain
  left the fixture path empty, `cd ""` silently stayed put, and the harness committed
  into the shipping repository.
- `fu-probe-redirect-lands-in-shipping-cwd` (P2, 2026-08-27, recorded on branch
  `fix/suite-isolation-owns-its-git`): an unescaped ampersand in a `sed` replacement
  turned a redirect into `2>iso_git`; the fixture ran before any `cd`, so the relative
  path resolved in the shipping checkout. The stray file survived unnoticed into a full
  81-suite sweep, and its later removal inside a tripwire snapshot window failed
  `aai-docs-audit`.
- `fu-orchestrator-probe-touched-git` (P3, 2026-08-27, same branch): the orchestrator
  ran `rm -rf` against the shipping repository's `.git/worktrees` to build an ad hoc
  gate probe — the same class it had just instructed two roles to avoid. No damage
  resulted and the probe timed out without producing evidence.
- The control that is supposed to prevent all four is HAZ-SCRATCH. Measured in a
  disposable clone of `origin/main`:
  `/usr/bin/grep -rn HAZ-SCRATCH .aai tests` returns exactly two lines —
  `.aai/SUBAGENT_CONTRACT.md:18` (the rule itself, prose) and
  `tests/skills/test-aai-hygiene-pack.sh:898` (`HAZ_IDS=(...)`), which asserts that the
  anchor and its scar citation are still present in the contract text. Nothing asserts
  that any agent shell obeyed it, because nothing can.
- The canonical wrapper does not cover this path either.
  `.aai/scripts/aai-run-tests.sh:324-344` (`aai_iso_is_suite_run`) returns success only
  when one of its arguments is an existing file under `$AAI_REPO_ROOT/tests`; every
  generator, build, `node` one-liner and probe run through the wrapper therefore
  executes in the shipping tree. That is `fu-adhoc-probes-unisolated-report-only` (P2),
  which measured a helper through the canonical wrapper printing the shipping repo as
  its toplevel on branch `main`.

## Expected Behavior
- An agent shell and anything it launches should be unable to write the shipping
  checkout by accident. Where a write is legitimate (the ride's own commits), it should
  be the deliberate, narrow exception rather than the ambient default.
- A boundary rather than a reminder: a wrong-cwd probe, an empty `cd`, a relative
  redirect or a stray `rm -rf` should fail or land somewhere harmless, not land in the
  shipping tree and be discovered by a later sweep.

## Steps to Reproduce (if applicable)
1) From an agent shell whose cwd is the shipping checkout, run any command that
   computes a fixture path and `cd`s to it inside a command substitution, or that
   emits a relative redirect before its `cd`.
2) Observe that the parent shell's cwd is still the shipping checkout and the write
   lands there.
3) Confirm no mechanism refused it: `/usr/bin/grep -rn HAZ-SCRATCH .aai tests` returns
   only the contract line and the hygiene-pack anchor list.

## Verification
- `/usr/bin/grep -rn HAZ-SCRATCH .aai tests` — after a fix, HAZ-SCRATCH is backed by an
  enforcing surface, not only by an anchor-presence assertion.
- A negative probe: a deliberately wrong-cwd write attempted from a dispatched role's
  shell must not modify `git status --porcelain=v1` in the shipping checkout.
- The four registry ids above are re-checked against the new mechanism and closed or
  re-scoped explicitly.

## Constraints / Risks
- The agent shell must still be able to commit the ride's own work, so a blanket
  read-only mount is not the answer; the boundary has to distinguish deliberate ride
  writes from incidental ones.
- Every mechanism considered so far has been prose, and prose has now failed four
  times, including once from the orchestrator's own seat.

## Notes
- OUT OF SCOPE: the SUITE path. A ride in flight
  (`isolation-shares-the-shipping-git`, branch `fix/suite-isolation-owns-its-git`)
  gives every suite its own `git clone --local --no-hardlinks`. Its spec's
  "NOT CLOSED" section says so directly about this item: the incident "was an agent's
  own probe helper running git from an agent shell, not a suite running inside the
  framework's checkout ... This scope makes the SUITE path structurally safe and leaves
  the AGENT path exactly where it was."
- OUT OF SCOPE: the repo tripwire's own reporting defects, filed separately.
- Registry ids covered: `fu-subagent-probe-hits-real-repo` (P1),
  `fu-empty-path-cd-stays-in-shipping-repo` (P2),
  `fu-probe-redirect-lands-in-shipping-cwd` (P2),
  `fu-orchestrator-probe-touched-git` (P3),
  `fu-adhoc-probes-unisolated-report-only` (P2, context).
