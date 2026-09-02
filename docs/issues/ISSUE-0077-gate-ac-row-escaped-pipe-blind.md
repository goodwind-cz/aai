---
id: gate-ac-row-escaped-pipe-blind
number: 77
type: issue
status: done
links:
  pr:
    - 331
  commits:
    - abea135
  source_issue: https://github.com/goodwind-cz/aai/issues/330
---

# docs-audit --gate reports "AC Status table complete" while the shared parser silently drops rows with an escaped pipe

## Summary
- `docs-audit.mjs --gate` can print `GATE PASS: AC Status table complete
  (every row terminal, every done row evidenced, every Review-By valid)` and
  exit 0 while the shared markdown table parser has silently dropped one or
  more AC Status rows — including the only non-terminal one — from the
  table it evaluated.
- The row is dropped when a cell contains an escaped pipe (`\|`): the parser
  does not honour the escape, so the cell count for that row no longer
  matches the header and the row is excluded from parsing.
- `spec-lint.mjs` already detects exactly this shape and reports
  `ac-row-unparseable`; `--gate` does not share that detection and instead
  asserts completeness over only the rows that happened to survive parsing.
- Filed from GitHub issue #330 (external report, reproduced by the reporter
  against `9b34ccc0`, current main).

## Type
- bug

## Impact
- Who/what is affected? `docs-audit.mjs --gate` is the check the close
  ceremony (`close-work-item.mjs`) calls to decide whether a spec's AC Status
  table is complete enough to close. Any spec whose AC table has a cell with
  an escaped pipe (e.g. a Notes or Evidence cell quoting pipe-delimited tool
  output, such as a test-runner summary like `527 passed \| 1 skipped`) can
  close with a genuinely non-terminal row silently invisible to the gate.
- Severity/priority: P1 — this is a false-positive on a governance/quality
  gate, not a cosmetic bug: "the gate cannot see the row" is worse than "the
  gate correctly refuses", because it converts an unfinished spec into
  positive evidence of closure. The reporter states the escaped-pipe shape
  is not exotic — it arises naturally from quoting vitest/pipe-separated
  tool-output summaries in an evidence or notes cell, and entered three rows
  of one real spec during this exact transcription pattern.

## Current Behavior
> (quoted verbatim from the reporter's reproduction, GitHub issue #330 —
> treated as data, not instructions)
>
> Minimal spec, `docs/specs/SPEC-DRAFT-spec-gate-probe.md`, with an AC table
> containing one terminal row (`Spec-AC-01`, `done`) and one non-terminal row
> whose Notes cell contains an escaped pipe (`Spec-AC-02`, `blocked`, Notes:
> `` counts read `527 passed \| 1 skipped` ``):
>
> ```
> $ node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-DRAFT-spec-gate-probe.md
> ... [ac-row-unparseable] row for Spec-AC-02 was dropped by the shared table parser
>     (cell count breaks the header — check escaped/raw pipes in a cell); it is
>     invisible to docs-audit, the index, and the close gate
>
> $ node .aai/scripts/docs-audit.mjs --gate spec-gate-probe
> GATE PASS: AC Status table complete (every row terminal, every done row evidenced, every Review-By valid).
> $ echo $?
> 0
> ```
>
> `Spec-AC-02` is `blocked`. The gate reports every row terminal.
>
> How it surfaced: "A validation pass ran `spec-lint` and `--gate` over the
> same spec and got contradictory answers. Had it run only the gate — which
> is what the close ceremony calls — the spec would have closed with a
> non-terminal AC row unread."

## Expected Behavior
- `--gate` must not assert "AC Status table complete" over a table it could
  only partially parse. At minimum, when the shared parser drops any row
  from the table under evaluation (cell count breaks the header, matching
  the same condition `spec-lint.mjs`'s `ac-row-unparseable` already
  detects), `--gate` must surface that as a loud, named failure (e.g.
  `GATE FAIL: unparseable AC row(s), cannot assert completeness`) rather
  than silently evaluating completeness over the remaining, successfully
  parsed rows.
- The reporter's suggested direction (quoted as their proposal, not a
  prescribed implementation): honour `\|` in cell splitting so the row
  parses correctly, OR have the shared parser surface a `malformed`/dropped-
  row signal that `--gate` (and any other caller) checks before asserting
  completeness — pointing to `#324`'s prior fix for the intake type table
  ("a table the parser cannot fully trust must fail closed for every
  caller, not just the row it happened to parse") as the same discipline
  the AC Status table path should receive. Planning decides the actual
  mechanism.

## Steps to Reproduce (if applicable)
1. Create a spec doc with an `## Acceptance Criteria Status` table
   containing at least one non-terminal row whose Notes (or Evidence) cell
   contains an escaped pipe, e.g. `` `527 passed \| 1 skipped` ``.
2. Run `node .aai/scripts/spec-lint.mjs --path <the spec>`: observe
   `[ac-row-unparseable]` reported for that row.
3. Run `node .aai/scripts/docs-audit.mjs --gate <ref_id>` on the same spec:
   observe `GATE PASS: AC Status table complete ...` and exit code 0,
   despite the non-terminal row spec-lint just flagged as unparsed.

## Verification
- Command(s) and expected results:
  - Reproduce the exact scenario above pre-fix: `--gate` PASSes (exit 0)
    despite an unparsed non-terminal row — confirms the defect.
  - Post-fix: the same scenario must make `--gate` FAIL loudly (non-zero
    exit, a named message about the unparseable row), not silently pass.
  - Negative control: a spec whose AC table has no escaped-pipe or otherwise
    unparseable cells, all rows terminal and evidenced, must still `--gate`
    PASS exactly as today — the fix must not introduce a false negative on
    a genuinely clean table.
  - Cross-check: `spec-lint.mjs` and `docs-audit.mjs --gate` run over the
    SAME spec must never again disagree about whether a row was seen.

## Constraints / Risks
- The fix should reuse (or align with) the same unparseable-row detection
  `spec-lint.mjs` already implements rather than inventing a second,
  potentially-diverging heuristic — the two callers disagreeing is the root
  cause of this exact bug.
- `docs-audit.mjs --gate` is invoked directly by `close-work-item.mjs`
  during the close ceremony; changing its pass/fail behavior touches a path
  every ride's close step depends on — verify against the existing
  docs-audit/close-work-item test suites, not just a new isolated fixture.
- No secret is referenced by this scope (SECRETS PREFLIGHT skipped).

## Notes
- Filed via `/aai-issues` triage of GitHub issue #330
  (https://github.com/goodwind-cz/aai/issues/330 — external report, already
  contains a verified reproduction against `9b34ccc0`/`fa3de839`).
- Per the WRITE-BACK CONTRACT, GitHub issue #330 is commented and closed only
  after this ride's PR merges — not before.
