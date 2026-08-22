---
id: drain-the-tripwire-known-offender-list
number: null
type: change
status: draft
user_visible: false
ceremony_level: 1
capability: aai-suite-isolation
links:
  pr: []
  commits: []
---

# Change — four suites are still exempt from the tripwire and none of them needs to be

## Summary
- `TRIPWIRE_KNOWN_OFFENDERS` (`tests/skills/test-framework.sh:64-69`) exempts four
  suites from the tripwire because they used to write to the shipping repository.
- Disposable-worktree isolation (SPEC-0138) fixed that. **All four were
  re-measured under isolation and all four are clean.** The exemptions are debt
  with nothing behind them.

## Evidence
Measured on `main` at `862e069`, each suite run serially through the real
framework inside a disposable clone, with the real tree and the clone
snapshotted (`git status` plus a sha256 of the three ratchet paths) before and
after each run:

| suite | exempt for | measured |
|---|---|---|
| `aai-hitl-propagation` | `docs/INDEX.md` | PASS 48 s, 1/1 isolated, tripwire attested clean, INDEX **not written** |
| `aai-metrics` | `overview.html`, `overview-data.json` | PASS, 1/1 isolated, attested clean, **not written** |
| `aai-state` | `docs/INDEX.md` | PASS 25 s, 1/1 isolated, attested clean, **not written** |
| `aai-token-capture` | `overview.html`, `overview-data.json` | PASS 1 s, 1/1 isolated, attested clean, **not written** |

The only shipping-repo change across all four runs was
`M docs/ai/tests/test-runs.jsonl` — the framework's own post-loop append, not a
suite (`fu-framework-appends-tracked-testruns`).

## Impact
- Four suites are graded more leniently than the other 77 for a reason that
  stopped being true. An exemption that outlives its cause is the mechanism by
  which a ratchet quietly becomes a rubber stamp.
- The registry carries four items whose only content is "this suite is exempt".

## Suspected Cause
Nothing went wrong. The list was correct when written; the thing it worked
around was fixed elsewhere, and nothing re-checked it. This scope is that
re-check, made once and then made automatic.

## Desired Behavior
No suite is exempt from the tripwire, and a future exemption cannot be added
without evidence and cannot outlive its cause unnoticed.

## Acceptance Criteria
- AC-001: all four entries are removed and the full framework run stays green,
  with all 81 suites tripwire-attested. Demonstrate with a full run before and
  after, not with `--skill` runs.
- AC-002: removal is proved to BITE, not merely to be tolerated — with the list
  empty, a suite that writes to a formerly exempt path must fail. Prove by
  mutation in a disposable clone.
- AC-003: the four registry items are closed against this scope, each with the
  measurement that justifies it, not with "no longer applicable".
- AC-004: an empty list is asserted by an arm, so that re-adding an entry is a
  deliberate act that a reviewer sees rather than a line that slips in. If the
  right answer is a ratchet on the list's LENGTH rather than emptiness, say why.
- AC-005: nothing else about the tripwire changes. The tripwire stays armed.

## Verification
- one full framework run before and one after; compare the pass set and the
  attested count, not just the exit code
- prove AC-002 by mutation with an unmutated green control
- run whatever `node .aai/scripts/select-suites.mjs --files-from <changed>` returns

## Constraints / Risks
- **The tripwire is NOT being retired here and must not be.** A separate scope
  attempted that and was stopped by its own AC-002: a suite inside a disposable
  checkout can still reach the shipping repository through the shared git
  common dir (`fu-isolated-suite-reaches-shipping-repo`, P1), measured, with the
  post-deletion counterfactual green while the write landed. Draining the list
  is the part that was proven; deletion is not.
- `test-framework.sh` funnels all 83 suites. This is the fifth change to it in
  three days — read the cumulative diff.
- Removing an exemption can only make the tripwire stricter, so the failure mode
  here is a red CI, not a silent hole. That is the right direction, but it means
  a mistake blocks everyone.
- `docs/ai/decisions.jsonl` and `docs/ai/tests/test-runs.jsonl` are append-only.
- Two full framework runs at 18-28 minutes each. Budget them.
- No secret is referenced by this scope.

## Notes
- Closes `fu-hitl-propagation-writes-real-index`, `fu-metrics-suite-writes-real-overview`,
  `fu-state-suite-writes-real-index`, `fu-token-capture-writes-overview`.
- Ride discipline: ship on these acceptance criteria and nothing else. A finding
  outside them is filed, not fixed here. Two validation rounds maximum.
- Worth knowing while working: `grep` resolves to a shell function even
  non-interactively here, zsh does not word-split unquoted variables,
  `find -newermt` is a hard error, reading an exit code after a pipe reports the
  pipe's last command, and in JavaScript `String.replace` a `$'` in the
  REPLACEMENT means "everything after the match" — all five have produced
  fabricated measurements or corrupted files in this repository this week.
