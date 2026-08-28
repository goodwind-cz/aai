---
id: hardcoded-path-defeats-suite-isolation
type: issue
number: 41
status: draft
links:
  pr: []
  commits: []
---

# A suite that hardcodes an absolute path into the shipping tree is still write-capable

## Summary
- The derivable route by which an "isolated" suite reached the shipping repository is
  being closed. The residual is a suite that does not derive the path at all but writes
  a literal absolute path into the shipping checkout. No harness mechanism prevents
  that, and the run still reports the suite as isolated.

## Type
- bug

## Impact
- Affected: every framework run, and the shipping checkout it runs beside.
- The run's own summary line is the thing that misleads: the suite is counted
  `isolated`, so the report says the property holds while the write has landed.
- The only surviving observer is the repo tripwire, which is report-only in some
  configurations and whose reporting has its own open defects.

## Current Behavior
- `fu-isolated-suite-reaches-shipping-repo` (P1, 2026-08-22) measured on a throwaway
  framework fixture built the way `tests/skills/test-aai-suite-isolation.sh` builds its
  own: "a probe suite resolving the shipping root from git-common-dir modified a tracked
  file, created an untracked file, created a shared tag and set shared config; the run
  printed `Isolation: 2/2 isolated; 0 degraded` and only the tripwire turned it red;
  with the tripwire neutralised and an any-degraded-FAILS gate added the same tree exits
  0 at `Passed: 2 (100%)` with the write landed."
- THE MAIN ROUTE IS ALREADY CLOSED, qualifiedly, by work in flight. The ride
  `isolation-shares-the-shipping-git` (branch `fix/suite-isolation-owns-its-git`,
  `docs/specs/SPEC-DRAFT-isolation-shares-the-shipping-git.md`, SPEC-FROZEN) replaces the
  shared-`.git` worktree with a per-suite `git clone --local --no-hardlinks` (D1) and
  redefines `isolated` as a MEASURED property (D3): the checkout's own
  `git rev-parse --git-common-dir` must not equal the shipping one nor be prefixed by
  `$PROJECT_ROOT/`, or the suite is counted `degraded`.
- That spec closes this item explicitly and names what it leaves behind, verbatim:
  "closed for the mechanism it names ... The derivable route (resolve own root, ask git
  one question, receive the shipping repository) is removed by D1; the gate is made to
  MEASURE the property by D3 ... What remains is a suite that hardcodes an absolute path,
  which no harness mechanism can prevent and which the permanent tripwire observes."
- THIS INTAKE IS THAT REMAINDER, and nothing else.

## Expected Behavior
- A suite writing a literal absolute path into the shipping checkout is either
  prevented, or observed reliably enough that the run cannot report success.
- If prevention is judged impossible (the D3 probe answers a question about the
  checkout's git surface, not about arbitrary filesystem writes), then the observation
  path must be load-bearing rather than advisory: the tripwire's verdict must be able to
  fail a run on its own, and its reporting must name the suite and the path.

## Steps to Reproduce (if applicable)
1) Build a throwaway framework fixture the way `tests/skills/test-aai-suite-isolation.sh`
   builds its own.
2) Add a probe suite that writes to a literal absolute path inside the shipping
   checkout, deriving nothing from git.
3) Run the framework and read the isolation summary: the suite is counted isolated even
   under the post-D1/D3 mechanism, because the probe D3 runs asks about the checkout's
   git surface, not about where the suite writes.

## Verification
- After the in-flight ride merges, re-run the fixture above and confirm the write is
  either refused or turns the run red without depending on a report-only path.
- The tripwire's verdict on that fixture names the suite and the absolute path.
- `fu-isolated-suite-reaches-shipping-repo` is closed only when the remainder recorded
  in the spec is itself addressed or explicitly accepted by the owner.

## Constraints / Risks
- The obvious general fix — running suites where the shipping path does not exist — is a
  much larger change than the per-suite clone, and the spec deliberately did not take it.
- The tripwire is the only current observer, and it is permanent by
  `hitl_decision 2026-08-23T20:05:00Z`; making it load-bearing interacts with its own
  open reporting defects, which are filed separately.

## Notes
- OUT OF SCOPE: the shared-`.git` mechanism, the `degraded` accounting, and the
  `git-common-dir` gate — all three land with the in-flight ride and must not be re-filed.
- OUT OF SCOPE: `fu-wrapper-hidden-suite-run-unreported` (P2), the sibling item under the
  same registry ref that covers a suite run whose COMMAND SHAPE hides the suite path from
  `aai_iso_is_suite_run`. That is a detection gap in the wrapper, not a hardcoded path.
- Registry ids covered: `fu-isolated-suite-reaches-shipping-repo` (P1, residual half only).
