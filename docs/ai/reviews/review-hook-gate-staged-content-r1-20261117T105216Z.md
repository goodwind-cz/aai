# Code Review — hook-gate-staged-content — round 1

```yaml
review:
  scope: "git diff origin/main (65113785) over .aai/scripts/lib/docs-audit-core.mjs, .aai/scripts/docs-audit.mjs, .aai/templates/git-hooks/pre-commit-index.sh, .aai/scripts/pre-commit-checks.sh, tests/skills/test-aai-docs-audit.sh, tests/skills/test-aai-pre-commit-checks.sh, tests/skills/suite-map.yaml, CHANGELOG.md, docs/product/docs-close-gate.md, docs/issues/ISSUE-0122-hook-gate-staged-content.md, docs/specs/SPEC-0300-spec-hook-gate-staged-content.md"
  spec: docs/specs/SPEC-0300-spec-hook-gate-staged-content.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "docs-audit-core.mjs scanGateEntries/readStagedDocSet; TEST-3860 rc 0 (reviewer re-run)" }
      - { ac: Spec-AC-02, call: compliant, citation: "readStagedDocSet HEAD: fallback; TEST-3861 rc 0 (reviewer re-run)" }
      - { ac: Spec-AC-03, call: compliant, citation: "pre-commit-index.sh:99 --staged; TEST-3863 rc 0; reviewer probe p6 (partial commit through temp GIT_INDEX_FILE gated on the HEAD spec)" }
      - { ac: Spec-AC-04, call: non-compliant, citation: "docs-audit.mjs:467-472 -- the --staged usage check runs after runIntakeFile/runGate; `--gate <ID> --staged` exits 0/1 on the working tree (B1, repro docs/ai/reviews/review-hook-gate-staged-content-r1-20261117T105216Z-repro-B1.sh)" }
      - { ac: Spec-AC-05, call: compliant, citation: "pre-commit-checks.sh:71,105,130 cat-file -e :0:; TEST-3864 rc 0" }
      - { ac: Spec-AC-06, call: compliant, citation: "pre-commit-checks.sh:86 *.env; TEST-3865 rc 0" }
      - { ac: Spec-AC-07, call: compliant, citation: "pre-commit-checks.sh:65-66 -z array; TEST-3866 rc 0" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-3454 / TEST-3461 rc 0 (reviewer re-run); whole suites rc 0 per VALIDATION r2" }
      - { ac: Spec-AC-09, call: compliant, citation: "CHANGELOG.md:33; docs/product/docs-close-gate.md; TEST-3868 rc 0" }
      - { ac: Spec-AC-10, call: compliant, citation: "readStagedDocSet fromHead/indexIds filter; TEST-3869 rc 0" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/docs-audit.mjs, line: 469,
          issue: "B1: --staged is silently dropped when combined with --gate <ID> or --intake-file; only a --staged reaching the check after those two dispatchers is refused",
          failure_scenario: "index holds a non-terminal linked spec, working tree holds a reconciled one; `docs-audit.mjs --gate ISSUE-5990 --staged` exits 0 with GATE PASS from the working tree instead of exit 2 (repro script exits 1)" }
      - { rank: NON-BLOCKING, file: .aai/scripts/pre-commit-checks.sh, line: 71,
          issue: "NB1: each staged file now costs up to three `git cat-file -e` plus three `git show` processes (CHECKs 2-4 each re-test existence, and CHECKs 3/4 test it before their extension filters)",
          failure_scenario: "600 staged .js files: origin/main script 7.8 s real, this diff 29.0 s real (3.7x) on the reviewer host; a downstream /aai-update or bulk commit pays this on every commit through the hook" }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/docs-audit-core.mjs, line: 2269,
          issue: "NB2: the try/catch around scanGateEntries catches every error in both modes and labels it 'staged mode needs a git work tree'",
          failure_scenario: "working-tree mode (no --staged), an unreadable doc under docs/specs (chmod 000): origin/main crashes exit 1 with EACCES; this diff exits 2 with 'GATE ERROR: staged mode needs a git work tree: EACCES ...' -- a false diagnostic on the path D1 says is unchanged" }
  cannot_verify:
    - { claim: "Windows (Git Bash / Windows git) behaviour of the NUL-separated read, process substitution and `git cat-file --batch` CRLF handling", closes_with: "the Windows Pester/CI leg green on the PR head" }
    - { claim: "Linux CI behaviour of the new tests (GNU tools, runner without identity)", closes_with: "GitHub Actions run green on the PR head" }
    - { claim: "Full-sweep non-regression (L3 surface forces FULL_RUN)", closes_with: "the one full sweep the orchestrator runs before close" }
  overall: fail
```

security_relevant: true

## Scope and inputs

- Diff: `git diff origin/main` in /Users/ales/Projects/aai-worktrees/hook-gate-staged-content (uncommitted
  tree on branch fix/hook-gate-staged-content, base 65113785), STATE `worktree.user_decision: worktree`.
- Spec: docs/specs/SPEC-0300-spec-hook-gate-staged-content.md (ceremony 3, one post-freeze amendment
  adding Spec-AC-10). Intake: docs/issues/ISSUE-0122-hook-gate-staged-content.md.
- Read: validation r1/r2 (PASS), TDD/mutation evidence listing.
- Coaching check: the dispatch named focus areas to scrutinize but did not pre-rate severity or
  exclude any area; the full scope was reviewed.

## Verdict 1 — spec_compliance: FAIL

AC walk (tests re-run by the reviewer, single functions, foreground, through aai-run-tests.sh, all rc 0:
3860, 3861, 3862, 3863, 3869, 3864, 3865, 3866, 3454, 3461, 3868).

| AC | Call | Citation |
|---|---|---|
| 01 | compliant | scanGateEntries `{staged}` -> readStagedDocSet; TEST-3860 |
| 02 | compliant | HEAD fallback / untracked not read; TEST-3861; reviewer probe p3 (project root in a subdirectory, HEAD-only spec) passes |
| 03 | compliant | hook passes `--staged`; TEST-3863; reviewer probe p6: `git commit -- <intake>` (partial commit, temp GIT_INDEX_FILE) is gated on HEAD's non-terminal spec, not the real index's reconciled one, and aborts — correct |
| 04 | **non-compliant** | B1 below. `--staged` alone exits 2 and `--check --staged` exits 2, but `--gate <ID> --staged` (and by code reading `--intake-file <f> --staged`) never reach the check |
| 05 | compliant | `cat-file -e ":0:$file"`; TEST-3864 |
| 06 | compliant | `.env|.env.*|*.env`; TEST-3865 |
| 07 | compliant | `diff --cached --name-only -z` into an array; TEST-3866 |
| 08 | compliant | moved pins 39/29 and 333/245; TEST-3454/3461 |
| 09 | compliant | one CHANGELOG heading; product doc statement; TEST-3868 |
| 10 | compliant | `fromHead && indexIds.has(fmId)` filter; TEST-3869 |

Deviations from the frozen spec:
- D2 / Spec-AC-04 (B1): "`--staged` without `--gate-file` is a usage error (exit 2)" holds only for
  invocations that are not `--gate` or `--intake-file`. The product doc line "`--staged` without
  `--gate-file`, or outside a git work tree, exits 2" is false for the same combinations.
- D1 "Without the option the working-tree scan is unchanged": the error path changed (NB2).

## Verdict 2 — code_quality: FAIL

### BLOCKING B1 — `--staged` silently ignored next to `--gate` / `--intake-file`
- File: .aai/scripts/docs-audit.mjs:467-473. `main()` dispatches `runIntakeFile` and `runGate` (both
  exit, never return) before the `args.staged && !args.gateFile` usage check.
- Failure scenario: index holds a linked spec with a non-terminal row, the working tree holds a
  reconciled copy. `node .aai/scripts/docs-audit.mjs --gate ISSUE-5990 --staged` prints `GATE PASS via
  linked spec(s)` and exits 0 — the working-tree verdict, while the operator asked for the staged one.
  A gate that silently answers a different question than the one asked is the false-pass shape this
  scope exists to remove.
- backed-by: repro docs/ai/reviews/review-hook-gate-staged-content-r1-20261117T105216Z-repro-B1.sh
  (exits 1 with "DEFECT B1 present"; the same script shows `--gate-file ... --staged` rc 1 and bare
  `--staged` rc 2 as the controls).
- Fix: move the usage check above the `runIntakeFile` line (and extend TEST-3862 with a `--gate <ID>
  --staged` case); the CHANGELOG and product doc wording then become true as written.

### NON-BLOCKING NB1 — process count per staged file in pre-commit-checks.sh (P3)
- File: .aai/scripts/pre-commit-checks.sh:71,105,130 (existence tests) and 74,113,135 (blob reads).
- Each CHECK re-runs `git cat-file -e` per file; CHECKs 3 and 4 run it before their `case` filters,
  so even a `.md` file costs two extra git processes there. Measured: 600 staged `.js` files, origin/main
  script 7.8 s, this diff 29.0 s (reviewer host, /usr/bin/time -p).
- Recommended disposition: promote to follow-up ref (suggested: `fu-precommit-staged-blob-process-count`):
  test existence once into a parallel array (or one `git ls-files -s -z` pass) and move the `case`
  filters ahead of the existence test. Remediating in tree would move the TEST-3454/3461 pins again.

### NON-BLOCKING NB2 — catch-all relabels every scan error as a staged-mode error (P3)
- File: .aai/scripts/lib/docs-audit-core.mjs:2267-2273.
- Failure scenario: no `--staged`; an unreadable doc under docs/specs. origin/main: uncaught EACCES,
  exit 1. This diff: exit 2, `GATE ERROR: staged mode needs a git work tree: EACCES ...`. In staged mode
  a non-"not a work tree" git failure (maxBuffer, corrupt object) is mislabelled the same way. Both
  exit non-zero, so the hook still fails closed under enforce; the harm is a false diagnostic and an
  exit-code change on the path D1 calls unchanged.
- Recommended disposition: remediate in tree together with B1 (wrap only the staged branch, or word
  the reason as "cannot read the doc set: <why>").

### INFO (no gate)
- Pre-existing, outside the diff: `.aai/templates/git-hooks/pre-commit-index.sh` still builds
  `STAGED_GATED_DOCS` from the newline, C-quoted `git diff --cached --name-only`; a governed doc whose
  name git quotes (non-ASCII) makes `git show ":$f"` fail and the close gate `continue`s silently — the
  same class as `fu-precommit-quoted-path-skip`, in the hook rather than pre-commit-checks.sh. Worth a
  follow-up (suggested: `fu-hook-gate-quoted-doc-skip`); not part of this spec's D4.
- Staged vs working-tree admission parity: checked by reading — same `admitScanFile`, same
  `scanExcluded`, depth-0 EXCLUDE_DIRS equivalent to `parts[1]`. One divergence: a symlinked `.md` is
  read as its link text from the index but as its target from the working tree. Edge only.
- Verified sound by probe (reviewer fixtures under the session scratchpad `rev/`): bash 3.2.57 under
  `set -euo pipefail` with zero staged files and with a staged deletion only (rc 0, no unbound
  variable); a 200 000-line blob through `git show | grep -c` / `grep -n` (no early-closing reader,
  counts complete); `readBlobs` with a newline in a path (git show branch), a path with spaces and a
  trailing space, a non-UTF-8 doc and multi-byte content ahead of later batch entries (byte-accurate
  size accounting, verdicts correct); intent-to-add linked spec reads as the empty blob (fails closed,
  the commit would not include it); project root in a subdirectory (prefix handling correct);
  origin/main `docs-audit.mjs` given `--gate-file x --staged` ignores the flag and gates as before
  (D3 backward compatibility holds).

## cannot_verify

- Windows behaviour of the NUL read / process substitution / `cat-file --batch` output — closes with
  the Windows CI leg green on the PR head.
- Linux CI behaviour of the new tests — closes with GitHub Actions green on the PR head.
- Full-sweep non-regression (L3 FULL_RUN) — closes with the orchestrator's full sweep before close.

## Warning dispositions (H6)

- NB1: recommended promote-to-follow-up (suggested id `fu-precommit-staged-blob-process-count`, P3).
- NB2: recommended remediate-in-tree with B1.
- The orchestrator records the chosen artifact; this reviewer filed nothing.

## Next steps

1. Remediate B1 (move the usage check first in `main()`), add a `--gate <ID> --staged` case to TEST-3862
   with a RED observation, re-run the repro (must exit 0 with "B1 not reproduced").
2. NB2 with it; NB1 per disposition.
3. Re-review (round 2) of the remediation delta.
