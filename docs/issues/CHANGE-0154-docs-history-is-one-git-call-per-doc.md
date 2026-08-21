---
id: docs-history-is-one-git-call-per-doc
number: 154
type: change
status: done
user_visible: false
ceremony_level: 1
capability: aai-docs-audit
links:
  pr:
    - 271
  commits:
    - 829b84ee51d38bddcbec75746cb3d6d551868acb
---

# Change — the docs audit asks git the same question once per document

## Summary
- `firstCommitDate` (`.aai/scripts/lib/docs-audit-core.mjs:301`) runs one
  `git log --diff-filter=A --format=%cs -- <file>` **per document**. `runAudit`
  calls it once per document in its main loop (`:979`), gated only on
  `legacy_until_date` being configured — and it is (`docs/ai/docs-audit.yaml:4`,
  `2026-06-12`).
- One whole-history pass answers the same question for every document at once.

## Evidence
Measured on `main` at `e0223a7`, on this repository:

```
docs-audit.mjs --check --strict --no-event   14056 ms
docs-audit.mjs --check --quick  --no-event     125 ms   (--quick skips firstCommitDate)
```

**This inference was wrong and is corrected here rather than deleted.** It read
the gap as "the history loop is 99.1% of the audit's cost". `--quick` skips
EVERY git probe, not only this one. Counted under a recording PATH shim during
the ride: a strict audit makes 581 git calls before the change and 211 after,
and 203 of the survivors are a different per-document probe,
`git log -1 --grep=<id>` at about 17-19 ms each. The history loop was the
larger half, not the whole: 12155 ms fell to 3667 ms, a measured 3.31x.

Direct comparison of the two strategies over every tracked document:

```
documents:            536
per-file (shipped): 15773 ms   (~29 ms x 536)
single pass:           49 ms
mismatches:          0 / 536
```

The same loop runs inside `generate-docs-index.mjs` (via `runAudit` at `:531`),
which the pre-commit hook invokes on **every commit**: one full generation costs
13657 ms.

## Impact
- Every commit in this repository pays ~14 s for it.
- `tests/skills/test-aai-docs-audit.sh` performs four full-repo generations and
  now takes 285 s of the 300 s canonical `aai-run-tests.sh` budget; Codex
  reproduced exit 124 on its own runner (`fu-docsaudit-suite-at-95pct-timeout`,
  P1). Removing this cost returns the suite to roughly 245 s without touching
  the test contract.
- CI pays it in every job that audits or regenerates.

## Suspected Cause
Not an algorithmic mistake in the caller — `runAudit` legitimately needs a
first-commit date per document. The cost is that the answer is fetched with one
subprocess per document, when git can stream the whole add-history in one walk.

## Desired Behavior
`runAudit` gets the same first-commit dates it gets today, from one git
invocation instead of 536, with no change to any value it derives from them.

## Acceptance Criteria
- AC-001: for every tracked `docs/**/*.md`, the new lookup returns **byte-identical**
  results to the shipped `firstCommitDate`. Demonstrated by comparing both
  strategies over the whole corpus, not a sample — 0 mismatches of 536.
- AC-002: `docs-audit.mjs --check --strict --no-event` spawns exactly one git
  process for first-commit history however large the corpus, produces a verdict
  identical to the pre-change run, and its wall clock falls by at least 3x.
  *(Amended during the ride. As first written this asked for under 2000 ms,
  inferred from the 14056/125 ms strict-vs-quick gap above. That inference is
  wrong: `--quick` skips **every** git probe, not only this one. A strict run
  makes 211 git calls and 203 of them are a different per-document probe —
  `git log -1 --grep=<id>` — filed as `fu-docsaudit-idmention-probe-per-doc`.
  The 99.1% figure in Evidence above overstates what this change can deliver;
  the measured result is 13569 ms to 3875 ms.)*
- AC-003: rename detection is pinned by a test. Without `--no-renames` the bulk
  walk reports a DRAFT-to-numbered close-ceremony rename as `R`, not `A`, and
  silently loses the date for those documents — measured at **23 of 536** on this
  repository. A fixture proves the numbered document keeps its date.
- AC-004: a document with no add commit in history (untracked, or added in a
  commit outside the walk) still yields `null`, not a crash and not a wrong date.
- AC-005: `firstCommitDate` keeps working as an exported single-document
  function — `generate-docs-index.mjs:266` calls it directly and is not in scope.

## Verification
- run the whole-corpus comparison as an executable arm, not as a one-off script
- time `--check --strict` before and after in the same session, same machine
- prove AC-003 bites by removing `--no-renames` and watching the fixture go red
- run whatever `node .aai/scripts/select-suites.mjs --files-from <changed files>` returns

## Constraints / Risks
- `docs-audit-core.mjs` is NOT in `protected_paths_l3`, but it is the shared
  engine behind the audit, the index generator and several gates. A wrong date
  here silently reclassifies documents as legacy or new.
- The existing no-`--follow` decision (CHANGE-0002 D13: rename detection
  mis-attributed a file's add commit to an unrelated commit) must not be
  reintroduced from the other direction. `--no-renames` is the reason AC-003 exists.
- `tests/skills/test-aai-docs-audit.sh` takes ~5 minutes and is at 95% of the
  canonical timeout. Do not run suites concurrently against this checkout.
- Cache invalidation is out of scope: build the map once per `runAudit` call and
  discard it. A process-lifetime cache would be wrong the moment a test fixture
  commits.
- No secret is referenced by this scope.

## Notes
- Registry item this scope closes: none directly; it is the measured fix for
  `fu-docsaudit-suite-at-95pct-timeout` (P1), which should be closed only once
  the suite is re-timed.
- Out of scope, worth stating because it will be noticed: for a document renamed
  at its close ceremony, `firstCommitDate` returns the **rename** date, not the
  date the draft was authored. That is today's shipped meaning and this change
  reproduces it exactly. Whether it is the right meaning is a separate decision.
- Ride discipline: ship on these acceptance criteria and nothing else. A finding
  outside them is filed, not fixed here. Two validation rounds maximum.
- Worth knowing while working: `grep` resolves to a shell function even
  non-interactively here, zsh does not word-split unquoted variables,
  `find -newermt` is a hard error, and reading an exit code after a pipe reports
  the pipe's last command — all four have produced fabricated measurements here.
