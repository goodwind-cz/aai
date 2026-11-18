---
id: spec-precommit-blob-read-cost
type: spec
number: 301
status: done
mutation_gate: v1
frozen_sha256: cef95bb94ddcf968a18ea3456e824c82614fcf85b58e77d557cd4a7b8864170f
ceremony_level: 3
links:
  requirement: precommit-blob-read-cost
  rfc: null
  pr: []
  commits: []
---

# Pre-commit checks read the staged content in one batched index read

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/DEBT-0016-precommit-blob-read-cost.md
  (follow-up `fu-precommit-blob-read-cost`, P3).
- Prior scope this one builds on (closed, not edited):
  docs/specs/SPEC-0300-spec-hook-gate-staged-content.md (D4 NUL-separated
  staged list, D5 index existence and staged-blob reads; delivered the
  per-file `git cat-file -e` plus `git show` shape this scope replaces).
- Sources: docs/ai/reviews/review-hook-gate-staged-content-r2-20261117T112846Z.md
  NB-1; VALIDATION-hook-gate-staged-content-r4.md ("Fail-open read paths",
  "Performance", NON-BLOCKING 2); the r3 failure of the reverted scratch-copy
  variant (a 300 KB file with the secret on its last line, written under
  `ulimit -f 200`, was scanned as a truncated copy and passed).
- Technology contract: docs/TECHNOLOGY.md (bash 3.2 suites through
  `.aai/scripts/aai-run-tests.sh`; CHECKs 1-7 need no Node).
- Locks: .aai/system/LOCKS.md (no lock is taken by this scope; the hook
  runs in the committing process only).

## Implementation strategy

- Strategy: tdd
- Rationale: a guard on an L3 protected surface whose new behaviour is
  mostly error paths. Each fail-closed path and the process-count property
  can be seen failing on the unchanged script (origin/main prints no
  fail-closed message, starts 33 git processes for 5 staged files and 243
  for 40, and lets a staged blob with a deleted object through with exit 0),
  so each gets a RED observation before the change and a mutation record
  after it. The owner's brief makes the fail-closed test and the cost test
  RED-first. Not chosen at intake (autopilot); Planning chose it.

## Isolation and review

- Worktree recommendation: required
- Worktree rationale: L3 protected surface (`.aai/scripts/pre-commit-checks.sh`
  is listed in `protected_paths_l3`); the main checkout carries other
  sessions' uncommitted files.
- User decision: worktree (owner directive in the dispatch brief; already
  recorded in STATE, not re-decided here)
- Base ref: origin/main at 03f3e6df
- Worktree branch/path: fix/precommit-batched-index-read at
  /Users/ales/Projects/aai-worktrees/precommit-blob-read-cost
- Review required: true
- Review scope (explicit paths): .aai/scripts/pre-commit-checks.sh;
  tests/skills/test-aai-pre-commit-checks.sh; CHANGELOG.md;
  docs/issues/DEBT-0016-precommit-blob-read-cost.md;
  docs/specs/SPEC-0301-spec-precommit-blob-read-cost.md.

## Decisions

- D1 (staged list). CHECKs 2-4 take their list from ONE
  `git -C "$PROJECT_ROOT" diff --cached --raw -z --no-renames --no-abbrev --no-color`
  call whose output is written to a file in the scratch directory (D5), and
  whose exit status (and the write) is checked. Each record is
  `:<srcmode> <dstmode> <srcsha> <dstsha> <status>` NUL `<path>` NUL. The
  path list is the one `--name-only -z` gave (rename detection off, so a
  rename is a D of the old name, skipped, plus an A of the new name; the
  order is the same sorted order). A record is skipped (no stage-0 blob,
  as before) when its status is `D` or `U`, or its destination mode is
  `160000` (gitlink). Every other record must carry a full-length
  hexadecimal, non-zero destination object id; a record that does not start
  with `:`, lacks its path field, ends without a NUL, or carries no usable
  object id is a malformed list and fails closed (D6). Paths are never put
  on the batch protocol, so a name holding a newline or carriage return
  needs no separate read.
- D2 (one batched read, by object id). The destination object ids of all
  non-skipped records, one per line, in list order, go to ONE
  `git -C "$PROJECT_ROOT" cat-file --batch > <scratch>/batch` call (fed by
  `printf '%s\n'`, a builtin, so no argv limit). Its exit status (the
  pipeline under `pipefail`, which also covers a failed write of the
  scratch file) is checked. When no record needs a read (zero staged files,
  or only deletions), no `cat-file` process starts. Asking by object id
  means a `missing` response can only mean an unreadable object; it is
  never "no stage-0 entry" (that was settled by D1), so it fails closed.
- D3 (parse by declared size, one descriptor). The batch file is opened
  once on a descriptor (`exec 3<`) and read with `read -u 3`. For each
  request, in order: read the header line; it must be exactly `<the requested
  id> blob <decimal size>`, else fail closed (missing, wrong id, other type,
  bad size). Copy the content to its own scratch file with `dd` reading the
  same descriptor (`bs=1048576` for the whole mebibytes, then one
  `bs=<remainder>` read; a size of 0 is created by `dd if=/dev/null of=`);
  the first `dd` creates the copy (`>`), a second appends (`>>`), so no
  builtin redirection is needed to create it (D13); a non-zero `dd` exit
  fails closed. Compare
  the copy's byte count (`wc -c`) with the declared size; a difference fails
  closed. Read the separator line; it must exist and be empty, else fail
  closed. A size is a decimal without a leading zero (except `0` itself) and
  at most 15 digits, else `unexpected response for PATH` (bash reads `028` as
  a bad octal; amended after VALIDATION r4 NB-1). After the last request the
  descriptor must be at end of file; any further non-NUL byte fails closed (a
  trailing NUL is accepted, because bash `read` drops NULs; every content
  byte was still scanned, so nothing is missed; wording corrected after
  VALIDATION r4 NB-5). A truncated, short, misaligned, dropped or
  extra response is therefore caught before any scan uses the copy.
- D4 (scans). CHECK 2's content scan, CHECK 3's debug scan and CHECK 4's
  marker count read the per-object copy with `grep ... < <copy>` (stdin is
  the file, so grep's binary-match message keeps its `(standard input)`
  wording). Before each scan the copy must still be a readable regular file,
  and the secrets scan and the marker count must get a number from `grep -c`
  (a failed open is a redirection error whose status is 1, the same as "no
  match", and `|| true` would turn it into zero hits); anything else fails
  closed as `copy failed for PATH` (VALIDATION r3 NB-A). CHECK 3's output is
  the matched lines, so it has the readability test only. Patterns, skip
  lists, messages and output order are unchanged.
  No pipe into an early-closing reader is added (TEST-3455 ratchet stays 0).
- D5 (scratch). One directory from
  `mktemp -d "${TMPDIR:-/tmp}/aai-pre-commit.XXXXXX"` holds the list, the
  batch output and the per-object copies; a failed `mktemp` fails closed;
  an `EXIT` trap removes the directory on every exit path (the trap's `rm -rf`
  runs with descriptors 3 and 4 closed in its own process, so it keeps a free
  descriptor when the table is nearly full; verified with `ulimit -n` 4 to 8
  and 10 on bash 3.2, and not verified on bash 5 at `ulimit -n` 7 or lower;
  the signal exits are not covered; amended after VALIDATION r4 NB-2). The directory is
  created whenever a git directory exists (D7: a work tree, a cwd inside
  `.git`, GIT_DIR set) and not for a directory that is no repository.
- D6 (fail closed, one message). One function, `staged_read_fail`, prints
  through the existing `error` helper exactly one line
  `Staged content could not be read completely: <reason> — commit blocked`
  and exits 1 at once (no further check runs and no summary prints, so the
  message is the last stdout line). The reasons are fixed literals:

  | Reason literal | Raised when |
  |---|---|
  | cannot create a scratch directory | `mktemp -d` fails |
  | git diff --cached failed | the list read exits non-zero or its write fails |
  | malformed staged list | a list record breaks D1, or the list file's NUL terminators are not twice the records parsed (D13) |
  | git cat-file --batch failed | the batch pipeline exits non-zero or its write fails |
  | response missing for PATH | the batch file ends before the header of a requested object |
  | unexpected response for PATH | a header is not `<requested id> blob <size>`, or its size has a leading zero (other than `0`) or more than 15 digits (D3) |
  | copy failed for PATH | the copy file cannot be created or `dd` exits non-zero, or the copy cannot be opened at scan time (D4) |
  | staged list count mismatch | one more `git diff --cached --name-only -z` names a different number of paths than the list parsed to, or its count cannot be taken (D13) |
  | copy count mismatch | the number of copies made differs from the number of objects requested (D13) |
  | size mismatch for PATH | the copy's byte count differs from the declared size |
  | separator missing after PATH | the separator line is absent or not empty |
  | unrequested trailing output | bytes remain after the last requested response |
  | parse did not complete | the parse block did not reach its last statement although every check inside it passed, for instance after an expansion error (D13) |

  PATH is the staged path as listed. Opening the descriptor is guarded the
  same way (reason `git cat-file --batch failed`).
- D7 (one predicate: is there an index to judge?). Line 16 sets
  `IN_REPO=1` when `git rev-parse --git-dir` succeeds: in a work tree, with
  the cwd inside a git directory such as `.git` (whose index git reads), and
  with GIT_DIR set; it fails only where no repository exists at all.
  `PROJECT_ROOT` stays `git rev-parse --show-toplevel`, else `$(pwd)`. When
  `IN_REPO=1` every D6 path applies, work tree or not: a failed `mktemp`, a
  failed list read or write and every batch failure block the commit, so a
  staged secret blocks from a cwd inside `.git` as at 03f3e6df. When
  `IN_REPO=0` (a plain directory, the documented standalone use outside any
  repository) no scratch directory is created, the staged list is empty and
  the output stays "No staged files to check", exit 0, as today. Amended
  after VALIDATION r1 B1 (the first delivery skipped the read outside a work
  tree and passed a staged secret from a cwd inside `.git`) and r2 B2 (the
  r1 fix decided on `show-toplevel`, so a refused scratch list write with the
  cwd inside `.git` still read as "no staged files"): the decision is now one
  predicate on the git directory, with no `diff --cached --quiet` probe.
- D8 (behaviour changes, deliberate and disclosed). (a) A staged path whose
  blob object is absent or unreadable used to be skipped (`cat-file -e`
  failed) or scanned as empty (`git show` failed inside the pipe); it now
  blocks the commit with `unexpected response for PATH` (closes the
  fail-open recorded as VALIDATION r4 NON-BLOCKING 2). (b) A gitlink is
  skipped by its mode; before, it was skipped because its commit object is
  normally not in the superproject's store, and in the rare case that it
  was, `git show` of that commit was scanned. (c) A failing staged-list read
  inside a work tree now blocks instead of reading as "No staged files to
  check". (d) A staged path whose name is 253 bytes or longer was scanned as
  empty at 03f3e6df (`git show ":0:<name>"` failed with "File name too
  long" inside the pipe and the failure was swallowed); it is now read by
  object id and scanned (disclosed after VALIDATION r1 NB2; a safe-direction
  change). (e) Wherever a git directory exists, a missing or unusable
  TMPDIR blocks with the single fail-closed line even with nothing staged or
  a deletion-only stage (03f3e6df needed no scratch and passed those), and
  with a staged secret it still exits 1 but prints that line instead of the
  secret hit; a failing `git diff --cached` from a cwd inside a git
  directory blocks instead of reading as no staged files (disclosed after
  VALIDATION r2 NB4; safe-direction). A directory that is no repository is
  unaffected. (f) The staged list is read a second time with `git diff
  --cached --name-only -z` for the count cross-check (D13): one more git
  process, still constant in the staged count (6 for 5 and for 40 staged
  files), and an index that a concurrent git command changes between the two
  reads blocks the commit (safe direction). (g) The script uses descriptors 3
  and 4 for the whole run and no longer closes them by hand; when fewer than
  eight descriptors are available (`ulimit -n` 7 or lower) it blocks with a
  single fail-closed line where 03f3e6df blocked only on a secret and let a
  clean tree pass; at eight or more it gives the same exit code as 03f3e6df (the output
  may differ: at about 12 to 14 descriptors Node in CHECKs 8 and 9 hits
  EMFILE one limit earlier and adds one warning; amended after VALIDATION r4
  NB-3; disclosed after VALIDATION r3 B3; safe direction). Everything else in the output is byte-identical (Spec-AC-06,
  Spec-AC-07).
- D9 (anchor fragments). The mutation cells below target these literal
  fragments of `.aai/scripts/pre-commit-checks.sh`, which the implementation
  must contain verbatim: `git -C "$PROJECT_ROOT" diff --cached --raw -z --no-renames --no-abbrev`,
  `git -C "$PROJECT_ROOT" cat-file --batch >`, and each
  `staged_read_fail "<reason literal>` of D6 (PATH written as `$file`).
  Changing one after freeze is a disclosed amendment.
- D10 (SPEC-0300's moved anchors). SPEC-0300 is closed (`status: done`) and
  is not edited. Its TEST-3864 Mutation targets `cat-file -e ":0:$file"` and
  its TEST-3866 Mutation targets `--name-only -z`; both strings leave the
  script. Checked: no workflow under `.github/workflows/` runs a mutation
  step; `mutation-run.mjs --replay` runs only on an explicit `--spec`;
  `mutation-gate.mjs` (the close-time gate) reads records and never
  replays, and only for the spec being closed; the records themselves are
  gitignored local evidence under `docs/ai/tdd/spec-hook-gate-staged-content/`.
  So nothing automated replays SPEC-0300 after this change. A manual
  `mutation-run.mjs --replay --spec docs/specs/SPEC-0300-...` would now
  report TEST-3864 and TEST-3866 as targets that no longer change; that is
  expected, not a regression. The tests themselves stay and must stay green
  (Spec-AC-07), and the behaviours they guard get new mutation coverage in
  this spec: staged-then-deleted and quoted names through TEST-3876, the
  NUL-separated list through TEST-3876 and TEST-3874.
- D11 (product doc). None updated. `docs/product/` has no doc for the
  content checks of `pre-commit-checks.sh`; `docs/product/docs-close-gate.md`
  covers the docs-audit close gate in the hook, which this scope does not
  touch, and the intake does not set `user_visible: true`. The CHANGELOG
  entry (Spec-AC-08) is the consumer record.
- D12 (out of scope). CHECK 7 keeps its own `--diff-filter=ACM` newline list
  and working-tree read; CHECKs 1, 5, 6, 8, 9, the hook template
  `.aai/templates/git-hooks/pre-commit-index.sh` and `docs-audit.mjs` are
  unchanged. The git processes that CHECK 9's Node script starts are not
  counted by Spec-AC-01 (its count follows the number of `.gitignore` files,
  not staged files).

- D13 (descriptor safety and count cross-checks; amended after VALIDATION r3
  B3). When the descriptor table is nearly full, bash 3.2 cannot save a
  descriptor for a builtin's redirection (`read <<<`, `read <&3`, `: >`),
  prints `redirection error: cannot duplicate fd`, applies the redirection
  anyway and never restores stdin: the list loop then read the here-string,
  ended after one record and a staged secret passed with exit 0 (`ulimit -n`
  7 to 12, or descriptors 10..255 inherited at the default limit of 256).
  Fix at the cause: the parse uses no builtin redirection. The list is
  opened once with `exec 4<` and read with `read -u 4`; the record is split
  by parameter expansion and must hold exactly four spaces; the batch file is
  read with `read -u 3`; copies are created by `dd` (D3). Defence in depth,
  by tools that are not this loop: (1) `tr -cd '\000'` of the list file
  counted with `wc -c` must be twice the records parsed (`malformed staged
  list`); (2) one `git diff --cached --name-only -z --no-renames --no-color`
  counted the same way must equal the records parsed (`staged list count
  mismatch`; it also catches a list cut at a record boundary while git exits
  0, VALIDATION r1 NB3); (3) the non-empty entries of the copy array, counted after the batch
  loop, must equal the objects requested (`copy count mismatch`), checked
  before any scan. Each of (1) and (2) alone catches a list loop that stops
  early, and (3) catches a lost copy; the guard matrix in the r3 remediation
  evidence shows the fail-open only when both (1) and (2) are off. Decision on (2): taken,
  because it costs one constant git process, closes the boundary-cut case
  and makes the loop's count independently verifiable; the price is the
  concurrent-index race of D8(f), which blocks. The two descriptors are not
  closed by hand: `exec N<&-` needs the same save and prints the same error
  when none is free, and they close with the process (the trap's `rm -rf`
  closes them in its own process, D5). Amended after VALIDATION r4 NB-1:
  (4) a `PCC_PARSED=1` sentinel is the last statement of the parse block and
  a separate top-level command after it fails closed (`parse did not
  complete`) when it is unset, because bash 3.2 drops the whole block, count
  cross-checks included, on an arithmetic expansion error and goes on with
  exit 0. Amended after VALIDATION r4 NB-4: TEST-3881 pins (1) with a `tr`
  stub, the four-space shape check with a five-space record and (3) by the
  text of its line (no input reaches it past the size and separator checks);
  TEST-3873 pins the size checks and the sentinel.

## Acceptance Criteria Mapping

- Spec-AC-01 maps to the intake target "one batched index read; the git
  process count no longer grows with the number of staged files" (D1, D2).
- Spec-AC-02 maps to the fail-closed rule for truncation and scratch write
  failure (the r3 failure shape) (D3, D6).
- Spec-AC-03 maps to the fail-closed rule for response-count mismatch and a
  size that does not match the bytes present (D3, D6).
- Spec-AC-04 maps to the fail-closed rule for a non-zero reader exit, an
  unparseable header and the staged-list read (D1, D2, D6, D8).
- Spec-AC-05 maps to the fail-closed rule for scratch create/write failure
  and to scratch cleanup (D5, D6).
- Spec-AC-06 maps to "the staged-content semantics are exactly what #569
  left" (D1, D4, D7).
- Spec-AC-07 maps to preservation and the moved pins (intake Verification).
- Spec-AC-08 maps to the consumer record (CHANGELOG).
- Spec-AC-09 maps to the hook seam: the script reads the index git hands
  to the hook (a partial commit's temporary index) through the installed
  hook.
- Spec-AC-10 maps to the fail-closed rule for count mismatch and the
  descriptor-exhaustion failure of VALIDATION r3 (B3, NB-A, NB-C) (D4, D6,
  D13).

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN a fixture with 5 staged .js files and a fixture with 40 staged .js files are checked by bash .aai/scripts/pre-commit-checks.sh with a git wrapper first on PATH that logs one line per invocation, the two logs SHALL hold the same number of lines, each log SHALL hold exactly one line containing cat-file and that line SHALL contain cat-file --batch, and no line SHALL contain show or cat-file -e | done | TEST-3871 green docs/ai/tdd/precommit-blob-read-cost/green-full-suite-r4rem.log, mutation docs/ai/tdd/spec-precommit-blob-read-cost/mutation-TEST-3871.txt; validation docs/ai/validation/VALIDATION-precommit-blob-read-cost-r5.md | — | D1, D2 |
| Spec-AC-02 | WHEN a wrapper cuts the last 20 bytes of the cat-file --batch output and exits 0 while the last requested blob is z-big.txt (about 300 KB, its last line an api_key assignment with a quoted 12-character value), the script SHALL exit 1 and its last stdout line SHALL be the only line holding Staged content could not be read completely and SHALL name size mismatch for z-big.txt; WHEN the same fixture runs under ulimit -f 200 with no wrapper, the script SHALL exit 1 with the single message naming git cat-file --batch failed; neither run SHALL print ALL CHECKS PASS or PASS WITH WARNINGS | done | TEST-3872 green docs/ai/tdd/precommit-blob-read-cost/green-full-suite-r4rem.log, mutation docs/ai/tdd/spec-precommit-blob-read-cost/mutation-TEST-3872.txt; validation docs/ai/validation/VALIDATION-precommit-blob-read-cost-r5.md | — | D3, D6 |
| Spec-AC-03 | WHEN the wrapper drops the last requested object id before calling git, the script SHALL exit 1 with the single message naming response missing for z-big.txt; WHEN the wrapper appends one extra response line, it SHALL exit 1 naming unrequested trailing output; WHEN the wrapper adds 1 to the size in the first header, it SHALL exit 1 naming separator missing after a.txt | done | TEST-3873 green docs/ai/tdd/precommit-blob-read-cost/green-full-suite-r4rem.log, mutation docs/ai/tdd/spec-precommit-blob-read-cost/mutation-TEST-3873.txt; validation docs/ai/validation/VALIDATION-precommit-blob-read-cost-r5.md | — | D3, D6 |
| Spec-AC-04 | WHEN the loose object of a staged clean file c.txt is deleted from the object store, the script SHALL exit 1 with the single message naming unexpected response for c.txt (origin/main exits 0); WHEN the wrapper passes the full cat-file --batch output and exits 3 it SHALL exit 1 naming git cat-file --batch failed; WHEN the wrapper makes diff --cached --raw exit 128 it SHALL exit 1 naming git diff --cached failed; WHEN the wrapper cuts the last 3 bytes of the diff --cached --raw output it SHALL exit 1 naming malformed staged list | done | TEST-3874 green docs/ai/tdd/precommit-blob-read-cost/green-full-suite-r4rem.log, mutation docs/ai/tdd/spec-precommit-blob-read-cost/mutation-TEST-3874.txt; validation docs/ai/validation/VALIDATION-precommit-blob-read-cost-r5.md | — | D1, D2, D6, D8 |
| Spec-AC-05 | WHEN TMPDIR names a directory that does not exist, the script SHALL exit 1 with the single message naming cannot create a scratch directory; WHEN a dd on PATH exits 1, it SHALL exit 1 naming copy failed for a.txt; WHEN TMPDIR is an empty directory owned by the test, that directory SHALL hold no entry after a run that passes and after a run that fails closed | done | TEST-3875 green docs/ai/tdd/precommit-blob-read-cost/green-full-suite-r4rem.log, mutation docs/ai/tdd/spec-precommit-blob-read-cost/mutation-TEST-3875.txt; validation docs/ai/validation/VALIDATION-precommit-blob-read-cost-r5.md | — | D5, D6 |
| Spec-AC-06 | WHEN one fixture stages names with a space, a leading dash, a newline, a carriage return and a non-ASCII letter (each holding the api_key line), a git mv destination holding it, a file staged and then removed from the working tree, a staged deletion, an unmerged path, a gitlink, a binary file holding console.log, an empty file, a symlink, a 3.2 MB file with the api_key line last and an app.js with console.log and FIXME, the script SHALL give stdout, stderr and exit code byte-identical to the 03f3e6df script run on an identical fixture and SHALL print no Staged content could not be read completely line; run in a directory outside any git work tree, both scripts SHALL also give identical output and exit 0 | done | TEST-3876 green docs/ai/tdd/precommit-blob-read-cost/green-full-suite-r4rem.log, mutation docs/ai/tdd/spec-precommit-blob-read-cost/mutation-TEST-3876.txt; validation docs/ai/validation/VALIDATION-precommit-blob-read-cost-r5.md | — | D1, D4, D7 |
| Spec-AC-07 | bash tests/skills/test-aai-pre-commit-checks.sh SHALL exit 0, with TEST-3454 giving the 3e6b52d5 baseline's stdout, stderr and exit code on its seven fixtures and its numstat pin and the TEST-3461 line-count pin naming the new measured values, TEST-3455 counting 0 sites and TEST-3864 and TEST-3866 green; bash tests/skills/test-aai-docs-audit.sh SHALL exit 0 (TEST-3860 to TEST-3863, TEST-3869, TEST-3870); node .aai/scripts/check-cd-subshell-leak.mjs SHALL exit 0 | done | TEST-3877 green docs/ai/tdd/precommit-blob-read-cost/green-full-suite-r4rem.log, mutation docs/ai/tdd/spec-precommit-blob-read-cost/mutation-TEST-3877.txt; validation docs/ai/validation/VALIDATION-precommit-blob-read-cost-r5.md | — | preservation |
| Spec-AC-08 | CHANGELOG.md SHALL hold exactly one heading matching ## [unreleased] — perf: pre-commit checks read the staged content in one batched index read, and the entry under it SHALL contain the text Staged content could not be read completely | done | TEST-3878 green docs/ai/tdd/precommit-blob-read-cost/green-full-suite-r4rem.log, mutation docs/ai/tdd/spec-precommit-blob-read-cost/mutation-TEST-3878.txt; validation docs/ai/validation/VALIDATION-precommit-blob-read-cost-r5.md | — | consumer record |
| Spec-AC-09 | WHEN, with the pre-commit hook installed by install-pre-commit-hook.sh, app/config.txt holds the api_key line in the working tree and a clean copy in the index and git commit -m x -- app/config.txt runs, the commit SHALL exit non-zero, HEAD SHALL NOT move and the output SHALL hold Potential secret detected in app/config.txt exactly once; WHEN 40 clean .txt files are staged and committed through the same hook, git commit SHALL exit 0 and HEAD SHALL move | done | TEST-3879 green docs/ai/tdd/precommit-blob-read-cost/green-full-suite-r4rem.log, mutation docs/ai/tdd/spec-precommit-blob-read-cost/mutation-TEST-3879.txt; validation docs/ai/validation/VALIDATION-precommit-blob-read-cost-r5.md | — | hook seam |
| Spec-AC-10 | WHEN a fixture stages a clean a.txt, b.txt holding the api_key line and three more clean files and the script runs under ulimit -n 8, under ulimit -n 10, and at the default soft limit of 256 with descriptors 10 to 254 inherited open, each run SHALL exit 1 with no ALL CHECKS PASS or PASS WITH WARNINGS line, SHALL name the secret in b.txt or print the single fail-closed line, and SHALL print no cannot duplicate fd line on stderr; WHEN a git wrapper makes diff --cached --raw drop its last whole record, or print nothing, and exit 0, the script SHALL exit 1 with the single message naming staged list count mismatch; WHEN every scratch copy is removed after the first scan starts, the script SHALL exit 1 with the single message naming copy failed for b.txt | done | TEST-3880 green docs/ai/tdd/precommit-blob-read-cost/green-full-suite-r4rem.log, mutation docs/ai/tdd/spec-precommit-blob-read-cost/mutation-TEST-3880.txt; TEST-3881 green docs/ai/tdd/precommit-blob-read-cost/green-full-suite-r4rem.log, mutation docs/ai/tdd/spec-precommit-blob-read-cost/mutation-TEST-3881.txt; TEST-3882 green docs/ai/tdd/precommit-blob-read-cost/green-full-suite-r4rem.log, mutation docs/ai/tdd/spec-precommit-blob-read-cost/mutation-TEST-3882.txt; validation docs/ai/validation/VALIDATION-precommit-blob-read-cost-r5.md | — | D4, D6, D13 |

## Implementation plan

- `.aai/scripts/pre-commit-checks.sh`:
  - line 16: `IN_REPO` from `git rev-parse --git-dir` (D7);
  - before CHECK 2: the scratch directory and trap (D5), `staged_read_fail`
    (D6), the list read and parse into `STAGED` (all listed paths) plus a
    parallel array of object ids (empty for a skipped record) (D1), the one
    batch read (D2) and the per-object parse and copy into a parallel array
    of copy paths (D3);
  - CHECKs 2, 3 and 4: iterate the indices of `STAGED`; skip an index with
    no copy (replaces `cat-file -e`); scan the copy with `< <copy>`
    (replaces `git show ... |`) (D4). The name check of CHECK 2 is unchanged
    and still runs only for a path with a stage-0 blob.
  - bash 3.2 under `set -euo pipefail`: indexed arrays only, the
    `${arr[@]+"${arr[@]}"}` or `${#arr[@]}` guard for an empty array,
    `"${!arr[@]}"` for indices; no `mapfile`, no `declare -A`, no
    `read -N`. GNU and BSD: `dd bs= count=`, `wc -c` (BSD pads with spaces;
    compare with `-eq`), `mktemp -d` with a full `XXXXXX` template. No bare
    `cd` (cd-subshell-leak baseline stays 1), no pipe into an early-closing
    reader (TEST-3455).
- `tests/skills/test-aai-pre-commit-checks.sh`: new cases TEST-3871 to
  TEST-3876, TEST-3878 to TEST-3882 (wired into `main()`; hygiene
  test_093 checks registration); a shared helper that writes the git
  wrapper into the suite's own `$TEST_DIR` with the real git's absolute
  path baked in and puts it first on PATH only for the run under test (and
  a second helper for the `dd` stub); a `PRE_BATCH_SHA="03f3e6df"`
  baseline read with `git show` like `base_script` (named SKIP-CASE locally
  when the commit is absent, FAIL on CI). Re-pin TEST-3454 numstat and
  TEST-3461 counts to the measured values and extend their history
  comments; update the suite header's TEST range.
- `CHANGELOG.md`: one `## [unreleased] — perf: pre-commit checks read the
  staged content in one batched index read` entry stating the speed-up, the
  fail-closed message and the behaviour changes of D8.
- Seams crossed: the installed hook runs the script inside `git commit`
  with git's `GIT_INDEX_FILE` (TEST-3879 commits through it, including a
  partial commit whose temporary index differs from `.git/index`);
  `hook-gate.mjs` runs the same script before a Claude `git commit` and
  reads only its exit code and output (unchanged interface: exit 0/1,
  stdout lines); the `git diff --cached --raw` list and the batch read
  must agree on the object ids (both read the same index in one process
  each).
- Reference measurements from the Planning probe (prototype in the
  scratchpad, not shipping code): the existing suite cases TEST-3453,
  TEST-3454, TEST-3831 to TEST-3833 and TEST-3864 to TEST-3866 pass against
  the prototype; the Spec-AC-06 fixture is byte-identical to the 03f3e6df
  script; 600 staged .js files take 6.9 s against 7.7 s before #569 and
  28 s at 03f3e6df on the reference machine; 4 git processes for 5 and for
  40 staged files against 33 and 243 at 03f3e6df (6 after the
  VALIDATION r3 B3 fix, which adds the name-count `git diff`; the
  `rev-parse --git-dir` predicate of D7 had made it 5).

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3871 | Spec-AC-01 | integration | tests/skills/test-aai-pre-commit-checks.sh | logging git wrapper first on PATH; fixtures with 5 and with 40 staged .js files; equal log line counts, exactly one cat-file line and it is cat-file --batch, no show, no cat-file -e; RED at 03f3e6df (33 vs 243 lines) | target `.aai/scripts/pre-commit-checks.sh`; `sed:s/      size=""/      git -C "$PROJECT_ROOT" version >&2; size=""/` adds one git process per staged file with the same verdict and the case must fail at the git-count assertion (re-recorded after VALIDATION r1 NB1; the earlier xargs mutation failed at the exit-0 precondition and never reached the count assertions) | green |
| TEST-3872 | Spec-AC-02 | integration | tests/skills/test-aai-pre-commit-checks.sh | a.txt plus z-big.txt (about 300 KB, api_key line last); wrapper cuts 20 bytes of the batch output and exits 0: exit 1, single last-line message naming size mismatch for z-big.txt, no summary; same fixture under ulimit -f 200: exit 1 naming git cat-file --batch failed; RED at 03f3e6df (no message) | target `.aai/scripts/pre-commit-checks.sh`; `sed:s/staged_read_fail "size mismatch for /true "size mismatch for /g` drops the size check so the truncation is caught later under another reason and the case must fail | green |
| TEST-3873 | Spec-AC-03 | integration | tests/skills/test-aai-pre-commit-checks.sh | same fixture; wrapper drops the last requested id: response missing for z-big.txt; wrapper appends an extra response: unrequested trailing output; wrapper adds 1 to the first header size: separator missing after a.txt; wrapper rewrites the first header size to a zero-padded `08<size>` and to 20 nines: unexpected response for a.txt; a copy of the script without its leading-zero check run on the padded size still exits 1 with no passing summary (the parse-completed sentinel); each exit 1 with the single message; RED at 03f3e6df | target `.aai/scripts/pre-commit-checks.sh`; `sed:s/staged_read_fail "response missing for /true "response missing for /g` lets a dropped response through the header read and the case must fail | green |
| TEST-3874 | Spec-AC-04 | integration | tests/skills/test-aai-pre-commit-checks.sh | staged clean c.txt whose loose object is removed: unexpected response for c.txt (03f3e6df exits 0); wrapper exits 3 after full batch output: git cat-file --batch failed; wrapper makes diff --cached --raw exit 128: git diff --cached failed; wrapper cuts 3 bytes of the list: malformed staged list | target `.aai/scripts/pre-commit-checks.sh`; `sed:s/staged_read_fail "unexpected response for /true "unexpected response for /g` accepts a missing-object header and the case must fail | green |
| TEST-3875 | Spec-AC-05 | integration | tests/skills/test-aai-pre-commit-checks.sh | TMPDIR set to a missing directory: cannot create a scratch directory; dd stub on PATH exiting 1: copy failed for a.txt; TMPDIR set to an empty suite-owned directory stays empty after a passing run and after a wrapper-forced fail-closed run; with the cwd inside .git and a staged api_key line, a refused list write (ulimit -f 0) and a missing TMPDIR each exit 1 with the single message; a non-git directory with a missing TMPDIR exits 0 with no staged files | target `.aai/scripts/pre-commit-checks.sh`; `sed:s/staged_read_fail "copy failed for /true "copy failed for /g` ignores a failed copy and the case must fail | green |
| TEST-3876 | Spec-AC-06 | integration | tests/skills/test-aai-pre-commit-checks.sh | the Spec-AC-06 fixture built twice, once with the delivered script and once with git show 03f3e6df:.aai/scripts/pre-commit-checks.sh; cmp stdout and stderr, equal exit codes, no fail-closed line; both scripts run in a non-git directory give identical output and exit 0; both scripts run with the cwd inside the .git directory of a fixture staging a clean file and of one staging the api_key line give identical output and exit codes (0, and 1 with the secret hit) | target `.aai/scripts/pre-commit-checks.sh`; `sed:s/ --no-renames//` lets a rename record carry two paths and the case must fail | green |
| TEST-3877 | Spec-AC-07 | integration | tests/skills/test-aai-pre-commit-checks.sh | TEST-3454 parity over the seven 3e6b52d5 fixtures and its re-pinned numstat, TEST-3461 re-pinned line counts, the whole pre-commit and docs-audit suites exit 0, check-cd-subshell-leak.mjs exits 0 | target `tests/skills/test-aai-pre-commit-checks.sh`; `sed:s/\[\[ "\$numstat" == "/[[ "$numstat" == "9/` breaks the moved numstat pin and the case must fail | green |
| TEST-3878 | Spec-AC-08 | unit | tests/skills/test-aai-pre-commit-checks.sh | grep -cE of the heading in CHANGELOG.md (unreleased or a dated version) equals 1; the entry text up to the next heading contains Staged content could not be read completely | target `CHANGELOG.md`; `sed:s/— perf: pre-commit checks read the staged content in one batched index read/— perf: pre-commit checks read staged content/` removes the heading and the case must fail | green |
| TEST-3879 | Spec-AC-09 | integration | tests/skills/test-aai-pre-commit-checks.sh | fixture with the hook installed through vendor_hook_installer and install-pre-commit-hook.sh; partial commit of app/config.txt whose working copy holds the api_key line and whose index copy is clean: non-zero exit, HEAD unmoved, one Potential secret detected in app/config.txt line; 40 clean staged .txt files commit with exit 0 and HEAD moves | target `.aai/scripts/pre-commit-checks.sh`; `sed:s/git -C "\$PROJECT_ROOT" diff --cached --raw/env -u GIT_INDEX_FILE git -C "$PROJECT_ROOT" diff --cached --raw/` reads .git/index instead of the commit's temporary index and the case must fail | green |
| TEST-3880 | Spec-AC-10 | integration | tests/skills/test-aai-pre-commit-checks.sh | a.txt, b.txt (api_key line, the second record) and three clean files staged; run under ulimit -n 8, ulimit -n 10, and at the 256 limit with descriptors 10..254 held open by the parent; each exits 1, prints no passing summary, names the b.txt secret or the single fail-closed line, and prints no cannot duplicate fd line; RED at the r3 script (exit 0) | target `.aai/scripts/pre-commit-checks.sh`; `patch:docs/ai/tdd/spec-precommit-blob-read-cost/mutation-TEST-3880.patch` brings back the here-string split of the list records and disables the NUL-count, name-count and copy-count checks, so the loop stops after its first record and the secret passes, and the case must fail (each guard alone stays green by design: the matrix is in the r3 remediation evidence) | green |
| TEST-3881 | Spec-AC-10 | integration | tests/skills/test-aai-pre-commit-checks.sh | fixture with a secret in the last staged file; a git wrapper makes diff --cached --raw drop its last whole record (exit 0), then print nothing (exit 0): exit 1 with the single message naming staged list count mismatch; the unwrapped run reports the last file's secret; a `tr` stub adding one NUL to the list's NUL count (single message malformed staged list) and a wrapper giving every record a fifth space (the same message), and the copy-count line pinned by its text; RED at the r3 script (exit 0 or a different message) for the first two parts only, the later parts pin checks the r3 script already had | target `.aai/scripts/pre-commit-checks.sh`; `sed:s/staged_read_fail "staged list count mismatch"/true/g` turns the name-count cross-check into a no-op and the case must fail | green |
| TEST-3882 | Spec-AC-10 | integration | tests/skills/test-aai-pre-commit-checks.sh | a grep shim on PATH removes every scratch copy on its first call; a.txt is scanned, the copy of b.txt cannot be opened: exit 1 with the single message naming copy failed for b.txt, the scratch directory gone; RED at the r3 script (exit 0, the secret unreported) | target `.aai/scripts/pre-commit-checks.sh`; `sed:s/(?<!dev.null \x7c\x7c )staged_read_fail "copy failed for \$file"/true/g` turns every scan-time copy-failed guard (the readability tests and the numeric checks; the dd guards follow `dev/null ||` and stay) into a no-op and the case must fail | green |

RED observations: TEST-3880 to TEST-3882 were written first and run
against the r3 script (`red-test_3880_*`, `red-test_3881_*`,
`red-test_3882_*` under `docs/ai/tdd/precommit-blob-read-cost/`).
TEST-3871 to TEST-3875 are written first and run
against the 03f3e6df script (the worktree before the change); their
failing runs are stored as `red-<selector>.log` under
`docs/ai/tdd/precommit-blob-read-cost/`. TEST-3876, TEST-3877 and TEST-3879
guard preservation and hold on 03f3e6df by design; their failing
observation is the mutation record. TEST-3878 is red until the CHANGELOG
entry exists.

## Verification

- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pre-commit-checks.sh`
- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-docs-audit.sh`
- `node .aai/scripts/check-cd-subshell-leak.mjs`
- `/bin/bash -n .aai/scripts/pre-commit-checks.sh` and the new cases run
  under `/bin/bash` 3.2.57 on macOS; GNU userland through CI (Ubuntu).
- `node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-0301-spec-precommit-blob-read-cost.md`
- Benchmark (informational, not a test): 600 staged `.js` files, the
  03f3e6df script against the delivered one, wall clock recorded in the
  validation evidence.
- One full sweep before close (`tests/skills/test-framework.sh`; the L3 path
  forces FULL_RUN).
- PASS criteria: all TEST-xxx green and every Spec-AC terminal.

## Evidence contract

Per artifact: ref_id `precommit-blob-read-cost`, Spec-AC and TEST-xxx,
command, exit code, evidence path under
`docs/ai/tdd/precommit-blob-read-cost/` (RED and GREEN logs) and
`docs/ai/tdd/spec-precommit-blob-read-cost/` (mutation records), commit SHA
once committed.

Registry items closed by this scope: fu-precommit-blob-read-cost

## Residual risks

- Windows (Git Bash): the bash suites run on Ubuntu only in CI, so `dd`,
  `mktemp -d` and the descriptor reads under MSYS are not exercised by a
  test here.
- Two non-git processes per staged file remain (`dd` and `wc -c`, plus the
  unchanged greps); the cost test counts git processes only, and the
  wall-clock target is checked by the informational benchmark.
- The scratch directory holds the batch output plus one copy per object,
  about twice the staged content size; on a full disk the commit is blocked
  (fail closed) rather than let through.
- D8 (a)-(c) change behaviour on purpose; a project that commits a gitlink
  whose commit object is present in the superproject loses the (accidental)
  scan of `git show <commit>`.
- D10: a manual replay of SPEC-0300 reports its TEST-3864 and TEST-3866
  anchors as gone.
