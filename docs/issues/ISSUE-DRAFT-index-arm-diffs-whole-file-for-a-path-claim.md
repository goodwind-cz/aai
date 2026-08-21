---
id: index-arm-diffs-whole-file-for-a-path-claim
number: null
type: issue
status: draft
user_visible: false
ceremony_level: 1
capability: aai-docs-audit
links:
  pr: []
  commits: []
---

# Issue — a path assertion diffs the whole index, so it fails at UTC midnight

## Summary
- `tests/skills/test-aai-docs-audit.sh` TEST-003 is named *"real-repo INDEX paths are
  POSIX-only and the path change is a no-op on POSIX"*. It proves that by diffing the
  **entire** committed `docs/INDEX.md` against a fresh regeneration, stripping only
  `^Generated:`.
- The file carries a **second** dated line, `Today (UTC): <date>`, and a date-derived
  count, `## Overdue reviews (N)`. So the arm goes red every UTC midnight until someone
  regenerates the index, for a reason that has nothing to do with paths.

## Steps to Reproduce
1. Note the committed index's `Today (UTC):` line.
2. Wait for UTC midnight, or check out a repo whose index was generated on an earlier day.
3. `bash tests/skills/test-aai-docs-audit.sh`

**Expected:** an arm about path separators passes or fails on path separators.
**Actual:** `FAIL: POSIX-path change must be a no-op on POSIX (real INDEX byte-identical modulo Generated)`.

## Evidence
Measured on `main` 2026-08-21:

- `docs/INDEX.md:3` — `Generated: <ISO timestamp>` — **is** stripped before the diff
  (`tests/skills/test-aai-docs-audit.sh:1955,1957`).
- `docs/INDEX.md:431` — `Today (UTC): 2026-08-21 — counts above use this date for
  overdue checks.` — **is not** stripped.
- `docs/INDEX.md:6` — `## Overdue reviews (0)` — a count derived from that same date
  (`generate-docs-index.mjs:59-60` computes `todayUTC`; `:577` writes the line).

Round-2 validation of the `cli-output-survives-a-pipe` ride proved the failure on a
**pristine `git worktree add --detach HEAD` checkout with zero ride changes**, and
proved it clears after regenerating the index in that same checkout. Observed live at
03:35Z the same night: the committed index read `2026-08-20` while the date was
`2026-08-21`, and the arm was red.

## Suspected Cause
The arm uses a whole-file diff as a proxy for a claim about path separators. That proxy
silently asserts three separate things, only one of which is in the arm's name:

1. the index contains no backslash separators — **the stated claim**;
2. the committed index is a byte-current regeneration — a freshness claim;
3. nothing date-dependent has moved since it was generated — an accident of the proxy.

It fails on (3) and reports (1). A reader sent to look at path normalisation finds
nothing wrong, which is how a recurring red trains people to wave the suite through.

## Impact
- A daily false red on a suite that is otherwise a real gate. Cost is not the failure —
  it is that the failure carries no information, so the next genuine one is discounted.
- It has already been misattributed twice in one night: first to the in-flight ride,
  then to that ride's own new documents. Both diagnoses were wrong and both consumed a
  measurement cycle.

## Desired Behavior
- An assertion named for path separators fails on path separators.
- Whatever remains of the freshness claim (2) is stated as its own assertion, with its
  own name, or dropped deliberately — it is legitimate to want it, but not silently.
- No arm goes red purely because the calendar advanced.

## Acceptance Criteria
- AC-001: with the committed index generated on an earlier UTC day and no other
  difference, the suite passes. Demonstrated by constructing exactly that state.
- AC-002: a genuine backslash in an index path still fails the arm, and the message
  names the path problem. Prove by mutation.
- AC-003: whatever freshness property survives is asserted by a **separately named**
  arm whose failure message says the index is stale, not that paths moved. If the
  freshness claim is dropped instead, the spec says so and says why.
- AC-004: `## Overdue reviews (N)` crossing a Review-By boundary overnight does not fail
  any arm for that reason alone. Demonstrate with a fixture whose review date is in the
  past, not by reasoning about it.

## Verification
- construct the earlier-day state and run the suite; do not wait for midnight
- run whatever `node .aai/scripts/select-suites.mjs --files-from <changed files>` returns
- prove each assertion **bites** by mutation, with an unmutated green control

## Constraints / Risks
- `tests/skills/test-aai-docs-audit.sh` takes over four minutes; budget for it and do
  not run suites concurrently against this checkout.
- TEST-003 backs up and restores the real `docs/INDEX.md` around its regeneration. That
  restore is what made an earlier investigation report "something keeps reverting the
  index". Keep it, and keep it on every exit path.
- Do not change `generate-docs-index.mjs` output format to make the test easier; the
  dated lines are wanted in the artifact.
- No secret is referenced by this scope.

## Notes
- Registry item this scope closes: `fu-docsaudit-t003-utc-date-bomb` (P1).
- Ride discipline: ship on these acceptance criteria and nothing else. A finding outside
  them is filed, not fixed here. Two validation rounds maximum.
- Worth knowing while working: `grep` resolves to a shell function even non-interactively
  here, zsh does not word-split unquoted variables, `find -newermt` is a hard error, and
  reading an exit code after a pipe reports the pipe's last command — all four have
  produced fabricated measurements in this repo this week.
