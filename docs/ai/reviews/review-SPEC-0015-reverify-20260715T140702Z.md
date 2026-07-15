<!--
  Code-review re-verdict for SPEC-0015 / RFC-0007 (parallel-safe doc numbering).
  Independent re-review after the CR-1 remediation (evidence relocation out of
  the audit-scanned docs/validation/ directory). No YAML frontmatter, matching
  the convention of the prior review report in this same (now audit-excluded)
  directory.
-->

# Code Review Re-verification — SPEC-0015 / RFC-0007 Parallel-safe doc numbering

- Reviewer role: independent CODE REVIEW re-verifier (did not implement, did not
  perform the original validation or the original code review)
- Prior verdict: FAIL (1 blocking finding, CR-1 — see
  `docs/ai/reviews/review-SPEC-0015-20260715T140157Z.md`)
- Scope re-reviewed: `main...HEAD` working-tree diff of worktree
  `/Users/ales/Projects/aai-feature-parallel-safe-doc-numbering` (0 commits;
  all delta is uncommitted working-tree state)
- Base ref: main. Main repo `/Users/ales/Projects/aai` confirmed untouched
  (clean, HEAD `c243141`).
- Date (UTC): 2026-07-15T14:07:02Z

## Verdict: PASS

## 1. CR-1 re-check — confirmed fixed, re-executed not re-asserted

Reproduced the exact two commands the original CR-1 finding cited as failing:

```
$ bash tests/skills/test-aai-doc-numbering.sh
...
PASS: TEST-013 repo docs-audit CLEAN + index byte-idempotent
All doc-numbering tests passed.        # 13/13, exit 0

$ node .aai/scripts/docs-audit.mjs --check --strict --no-event
...
### Verdict: CLEAN                      # exit 0, 0 orphans/drifted/stale/type-warnings
```

Both are now green where they were previously red. Root-cause verification:
`docs/validation/` (the directory `docs-audit-core.mjs`'s `EXCLUDE_DIRS` did
NOT cover) no longer exists in the tree; `ls docs/validation` →
"No such file or directory"; `git status --porcelain` shows no entry for it.
The two evidence files that previously lived there
(`SPEC-0015-validation.md` and the code-review report) now live at
`docs/ai/reports/validation-SPEC-0015-20260715T140157Z.md` and
`docs/ai/reviews/review-SPEC-0015-20260715T140157Z.md` respectively — both
under `docs/ai/`, which IS in `EXCLUDE_DIRS` (verified: `EXCLUDE_DIRS = new
Set(['ai', 'knowledge', 'archive', '_archive', 'project-sessions',
'templates'])` at `docs-audit-core.mjs:23`, matched at scan depth 0). This is
a structural fix (evidence is now outside the scanner's walk), not a
one-off — any future report dropped into `docs/ai/reports/**` or
`docs/ai/reviews/**` is safe by construction, whereas `docs/validation/`
would recur the bug for the next writer.

No alternate/weaker remediation path was taken: `docs/ai/docs-audit.yaml`
`scan_exclude:` is still `[]` (unchanged), and `EXCLUDE_DIRS` in
`docs-audit-core.mjs` is unchanged (still the pre-existing 6-entry set) — the
fix was purely relocating the two files plus removing the empty directory,
not loosening the audit's guardrails.

## 2. Confirmed: remediation was evidence-relocation-only, no production-code delta

Compared the current tree against what the prior review (`review-SPEC-0015-
20260715T140157Z.md`) describes as reviewed:

- **Files the prior review explicitly names and content-inspected**:
  `.aai/scripts/allocate-doc-number.mjs`, `.aai/scripts/generate-docs-
  index.mjs`, `.aai/scripts/pre-commit-checks.sh`/`.ps1`,
  `tests/skills/test-aai-doc-numbering.sh`, the SPEC/RFC docs, and the
  intake/PR/template wiring diffs. Spot-read all of these again this
  session:
  - `baseRefNumbers()` (`allocate-doc-number.mjs:179-192`) — byte-for-byte
    the same logic quoted in the prior review: `git ls-tree -r --name-only
    <baseRef> -- docs/<dir>`, never the working tree. Unchanged.
  - `pre-commit-checks.sh` CHECK 8 block (lines 200-227) — same two-predicate
    guard, same report-only default, same `doc_number_guard: enforce` flip
    regex, same degrade-and-skip-when-absent path described in the prior
    review. Unchanged.
  - `docs/ai/docs-audit.yaml` diff vs `main`: only the new
    `doc_number_guard: report-only` config key + explanatory comment (the
    SPEC-0015 guard's own config surface, explicitly in scope per D6/AC-05,
    and already covered by the prior review's Non-defects section) — no
    change to `scan_exclude` or any audit-engine behavior.
  - `docs/ai/tests/test-runs.jsonl` diff: append-only telemetry (3 new lines
    from this session's test runs) — not production code.
  - `docs/INDEX.md` diff: generator output delta (SPEC-0015/RFC-0007 moved
    from Drafts to numbered), expected and mechanical.
- **Files that changed location since the prior review**: exactly the two
  evidence files (validation report, code-review report) — moved from
  `docs/validation/` to `docs/ai/reports/` and `docs/ai/reviews/`
  respectively — and the removal of the now-empty `docs/validation/`
  directory. Their *content* is unchanged (both still narrate the CR-1
  finding as history, including the old path names, which is correct — they
  are point-in-time evidence, not living config).
- **STATE.yaml**: present, reflects the pre-remediation state (`last_
  validation.status: not_run`, `code_review.status: not_run`) pending this
  re-verification's own STATE update per the operator's instructions — not a
  production-code file.

No new file, no deleted implementation file, no changed function signature,
no changed guard predicate, no changed CLI contract was found anywhere in the
allocator, the guards, the index generator, the prompts, or the templates
relative to what the prior review already examined and passed at Stage 1
(AC-01..09 all YES, AC-10 was the sole blocker). **Conclusion: the delta
between the FAIL and this PASS is evidence-relocation-only.**

## 3. Independent pass for new blocking findings

Re-ran the full `tests/skills/test-aai-doc-numbering.sh` (13/13) and the full
`tests/skills/test-framework.sh` (14/15, sole failure `aai-worktree`
independently re-confirmed pre-existing/unrelated — byte-identical test
script on `main`, fails at the identical step, no reference to any file this
change touches). Re-ran `--gate SPEC-0015` (GATE PASS) and the index generator
twice (byte-idempotent modulo the `Generated:` line). Spot-checked the
allocator's exit-code discipline and the duplicate/no-DRAFT guard predicates
by reading the code directly (Section 2, above) rather than trusting the
prior report's prose.

**No new blocking finding.** No regression was introduced by the
remediation — the production-code surface reviewed here is identical to what
the prior review already passed at Stage 1.

## 4. Prior non-blocking findings (not re-litigated)

CR-2 (dead-code positional-arg no-op in `allocate-doc-number.mjs:279`) and
CR-3 (validate-then-write batch allocation not transactional across fs
failures) remain non-blocking INFO items, unchanged and unaffected by the
evidence relocation. Neither escalated to blocking on re-inspection.

## Bottom line

CR-1 is fixed by relocating evidence out of the audit-scanned
`docs/validation/` directory into the project-canonical, audit-excluded
`docs/ai/reports/` and `docs/ai/reviews/` directories, and removing the empty
`docs/validation/` directory. This is the only delta since the prior FAIL;
the numbering engine itself (already found correct and defect-free at Stage 1
in the prior review) is untouched. All gates this review depends on
(TEST-013, repo `docs-audit --check --strict`, `--gate SPEC-0015`) were
re-executed fresh this session and are green.

**CODE REVIEW RE-VERDICT: PASS.**
