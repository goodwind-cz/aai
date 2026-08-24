---
id: a-branch-diff-pin-taxes-every-later-scope
number: 163
type: change
status: done
user_visible: false
ceremony_level: 1
capability: aai-spec-lint
links:
  pr:
    - 284
  commits:
    - 87767f8acb1ccf19e7b0af4bd4bc4d0843cf8141
---

# Change — a pin on one scope's diff bills every later scope forever

## Summary
- `tests/skills/test-aai-spec-lint.sh` TEST-011(clarify) pins that the *clarify*
  scope added no ceremony. Two halves: durable pins on `spec-freeze`'s usage
  line and exit contract, and a check that **the branch diff touches no
  unexpected `.aai/` path**.
- The second half is scoped to `git diff --name-only <main> -- .aai/`, so it
  fires for **any** later scope that edits `.aai/` — not for the scope it names.
  Each one must hand-add its paths to an allowlist inside the arm.

## Evidence
Measured on `main` at `f65ae56`:

```
recorded payments in the arm's own comments        6
allowlist entries after today                     34 paths / 12 case groups
payments made by this session alone                2
```

The arm's own comment says it: *"this pin is a BRANCH-DIFF allowlist, so any
LATER scope that legitimately edits `.aai/` on a branch cut from main trips it
until its paths are listed here."* The tax is documented, not accidental — but
it was accepted once and has been paid six times since.

**Precision, measured: 0 of 6.** Every recorded payment is a later scope's
legitimate edit. Not one is a clarify-scope ceremony addition, which is the
thing the arm is named for. Its recount line has also been stale three separate
times in one day (31 → 32 → 34) because the count lives in prose that nothing
asserts.

## Impact
- Every ride touching `.aai/` pays an unrelated edit plus a recount, and gets a
  red suite if it forgets. Two of today's rides hit it; one turned three suites
  red at once.
- The failure names a path, not a defect, so the reader has to learn that the
  arm is not about them.

## Suspected Cause
A pin on a historical fact — *what one scope did* — implemented against a moving
reference (`main`), which makes it a pin on *what everyone does next*.

## Desired Behavior
The clarify scope's zero-ceremony claim stays pinned. No later scope pays
anything to land an unrelated `.aai/` edit.

## Acceptance Criteria
- AC-001: the durable half survives untouched — `spec-freeze`'s usage line and
  exit contract are still pinned, and still bite. Prove by mutation.
- AC-002: a later scope editing an arbitrary `.aai/` path no longer fails this
  arm. Prove by adding one unrelated `.aai/` file in a disposable clone and
  watching the arm stay green.
- AC-003: whatever replaces the branch-diff half either measures the CLARIFY
  scope's own change (a fixed commit range or a stored manifest) or is removed
  with the reason stated. **If removed, say plainly what coverage is lost** —
  a deletion sold as a cleanup is worse than the tax.
- AC-004: no count lives in prose that nothing asserts. If a number survives,
  an arm computes it; otherwise no number is printed.
- AC-005: `fu-test011-branch-diff-allowlist-tax` closes, and the allowlist and
  its 12 case groups go with it if the half is removed.

## Verification
- prove AC-001 by mutating the usage line and the exit contract, one at a time
- prove AC-002 in a disposable clone with a throwaway `.aai/` file
- run whatever `node .aai/scripts/select-suites.mjs --files-from <changed>` returns

## Constraints / Risks
- **Do not weaken the clarify pin to remove the tax.** The zero-ceremony claim
  is the arm's content; the branch diff was only ever its evidence.
- `git log -S` finds two commits touching the failure string, so read them
  before concluding the half never caught anything — the 0-of-6 count is from
  the arm's own payment comments, not from a full history audit.
- `tests/skills/test-aai-spec-lint.sh` is a CORE suite: it runs on every PR.
- No secret is referenced by this scope.

## Notes
- Closes `fu-test011-branch-diff-allowlist-tax` (P2), the highest-recurrence
  item in the registry.
- Ride discipline: ship on these acceptance criteria and nothing else.
- Worth knowing while working: `grep` resolves to a shell function even
  non-interactively here, zsh does not word-split unquoted variables, reading an
  exit code after a pipe reports the pipe's last command, and a probe that exits
  non-zero for an unrelated reason reads exactly like a measurement — that
  happened twice in the session that filed this.
